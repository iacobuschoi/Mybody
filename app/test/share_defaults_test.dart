/* =============================================================================
 * share_defaults_test.dart — 「친구에게 기본으로 보여 주는 것」 (피드백 40)
 *
 * 서버가 준 기본값을 그대로 그리는가, 바꾼 스위치 **하나만** 보내는가(캐시에서
 * 본 옛 값으로 나머지를 덮지 않게), 「모두에게 적용」 은 한 번 더 묻는가,
 * 옛 서버 · 오프라인에서 거짓말을 하지 않는가, 360px 에서 넘치지 않는가.
 * ========================================================================== */
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mybody/src/api.dart';
import 'package:mybody/src/app_state.dart';
import 'package:mybody/src/scope.dart';
import 'package:mybody/src/screens/settings.dart';
import 'package:mybody/src/screens/share_defaults.dart';
import 'package:mybody/src/screens/social.dart';
import 'package:mybody/src/sync_queue.dart';
import 'package:mybody/src/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// server/db.js blankShare() — 체성분(몸 셋 · 목표 진행률 · 실제 수치)은 꺼짐, 나머지는 켜짐.
Map<String, bool> _blank() => {
      'weightTrend': false, 'smmTrend': false, 'bfmTrend': false, 'planProgress': false,
      'streak': true, 'schedule': true, 'absolute': false, 'diet': true,
    };

http.Response _json(Object body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status,
        headers: {'content-type': 'application/json; charset=utf-8'});

/// 서버 흉내 — 기본값을 들고 있고, PUT 은 서버처럼 합치고 absolute 규칙을 겁니다.
/// apply 는 진짜 서버처럼 expect 가 저장된 값과 다르면 409 로 돌려보냅니다.
class _FakeServer {
  final defaults = _blank();
  final calls = <String>[];
  final puts = <Map<String, dynamic>>[];
  final applies = <Map<String, dynamic>?>[];
  List<String> friends = ['f1', 'f2', 'f3'];
  List<Map<String, Object?>> incoming = [];
  int? applied;              // null 이면 친구 수
  int friendsGets = 0;
  /// 기본값 GET 을 이 횟수만큼 503 으로 — 카드가 캐시를 보여 주게.
  int failGets = 0;
  /// 채워 두면 PUT 이 이게 끝날 때까지 답하지 않습니다(겹친 요청).
  Completer<void>? gate;
  /// PUT 에 이 코드로 답합니다(저장 안 함).
  int? putStatus;
  /// PUT 은 저장하는데 답은 잃습니다(시간 초과 흉내).
  bool putLosesReply = false;
  /// 친구별 공유 PUT 이 망 오류.
  bool shareFails = false;

  MockClient get client => MockClient((req) async {
        final p = req.url.path.replaceFirst('/api', '');
        calls.add('${req.method} $p');
        if (p == '/share-defaults' && req.method == 'GET') {
          if (failGets > 0) {
            failGets--;
            return _json({'ok': false, 'reason': '잠깐 못 닿음'}, 503);
          }
          return _json({'ok': true, 'defaults': defaults});
        }
        if (p == '/share-defaults' && req.method == 'PUT') {
          final b = (jsonDecode(req.body) as Map).cast<String, dynamic>();
          puts.add(b);
          if (gate != null) await gate!.future;
          if (putStatus != null) return _json({'ok': false, 'reason': '서버 오류'}, putStatus!);
          b.forEach((k, v) { if (defaults.containsKey(k)) defaults[k] = v as bool; });
          if (!defaults['weightTrend']! && !defaults['smmTrend']! && !defaults['bfmTrend']!) {
            defaults['absolute'] = false;
          }
          if (putLosesReply) throw http.ClientException('reply lost');
          return _json({'ok': true, 'defaults': defaults});
        }
        if (p == '/share-defaults/apply' && req.method == 'POST') {
          final b = req.body.isEmpty ? null : (jsonDecode(req.body) as Map).cast<String, dynamic>();
          applies.add(b);
          final exp = b?['expect'];
          if (exp is Map && defaults.entries.any((e) => exp[e.key] != e.value)) {
            return _json({'ok': false, 'conflict': true, 'defaults': defaults,
                'reason': '기본값이 방금 바뀌었습니다 — 다시 확인해 주세요'}, 409);
          }
          return _json({'ok': true, 'applied': applied ?? friends.length});
        }
        if (p.startsWith('/share/') && req.method == 'PUT') {
          if (shareFails) throw http.ClientException('offline');
          return _json({'ok': true, 'share': _blank()});
        }
        if (p == '/friends') {
          friendsGets++;
          return _json({'ok': true, 'friends': {
            'accepted': [for (final id in friends) {'id': id, 'displayName': '친구$id'}],
            'incoming': incoming, 'outgoing': [],
          }});
        }
        if (p == '/me') {
          return _json({'ok': true, 'user': {'id': 'me', 'displayName': '나', 'inviteCode': 'ABCD'}});
        }
        return _json({'ok': false, 'reason': '그런 경로가 없습니다'}, 404);
      });
}

class _MemQueue implements QueueStorage {
  String? v;
  @override
  String? read() => v;
  @override
  void write(String raw) => v = raw;
}

Future<Api> _api(http.Client client) async {
  final api = Api(baseUrl: 'https://x.test', client: client);
  await api.setToken('tok');
  return api;
}

Future<void> _pump(WidgetTester t, Api api, Widget home, {SyncQueue? queue}) async {
  final app = await AppState.boot();
  await t.pumpWidget(Scope(
    state: app, api: api, queue: queue, onServerChange: (_) async {},
    child: MaterialApp(theme: mbLight(), home: home),
  ));
  await t.pumpAndSettle();
}

/// 폭 360 — 이 앱이 넘치지 않아야 하는 가장 좁은 폰.
void _narrow(WidgetTester t, {double height = 1600}) {
  t.view.physicalSize = Size(360, height);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
}

SwitchListTile _sw(WidgetTester t, String label) =>
    t.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, label));

OutlinedButton _applyButton(WidgetTester t) => t.widget<OutlinedButton>(find.ancestor(
    of: find.text('지금 친구 모두에게 적용'),
    matching: find.byWidgetPredicate((w) => w is OutlinedButton)));

void main() {
  testWidgets('서버의 기본값을 그리고, 바꾼 스위치 하나만 보낸다 (360px)', (t) async {
    _narrow(t);
    SharedPreferences.setMockInitialValues({});
    final s = _FakeServer();
    await _pump(t, await _api(s.client), const ShareDefaultsScreen());

    expect(t.takeException(), isNull, reason: '360px 에서 넘치면 안 됩니다');
    expect(find.text('친구에게 기본으로 보여 주는 것'), findsOneWidget);
    expect(find.byType(SwitchListTile), findsNWidgets(kShareFields.length));
    expect(find.text('3개 켜짐 · 새 친구에게 자동으로 적용'), findsOneWidget);
    expect(_sw(t, '기록 여부 · 스트릭').value, isTrue);
    expect(_sw(t, '오늘 식단 (칼로리·탄단지)').value, isTrue);
    expect(_sw(t, '체중 변화').value, isFalse, reason: '체성분은 기본 꺼짐');
    expect(_sw(t, '변화량이 아니라 실제 수치까지').onChanged, isNull,
        reason: '몸 항목이 하나도 없으면 「실제 수치까지」 는 뜻이 없습니다');

    await t.tap(find.widgetWithText(SwitchListTile, '체중 변화'));
    await t.pumpAndSettle();
    expect(s.puts, [{'weightTrend': true}], reason: '바꾼 것 하나만 — 나머지를 옛 값으로 덮지 않게');
    expect(_sw(t, '체중 변화').value, isTrue);
    expect(find.text('4개 켜짐 · 새 친구에게 자동으로 적용'), findsOneWidget);

    await t.tap(find.widgetWithText(SwitchListTile, '변화량이 아니라 실제 수치까지'));
    await t.pumpAndSettle();
    expect(s.puts.last, {'absolute': true});

    /* 마지막 몸 항목을 끄면 「실제 수치까지」 도 같이 꺼집니다 — 서버와 같은 규칙. */
    await t.tap(find.widgetWithText(SwitchListTile, '체중 변화'));
    await t.pumpAndSettle();
    expect(s.puts.last, {'weightTrend': false});
    expect(_sw(t, '변화량이 아니라 실제 수치까지').value, isFalse);
    expect(s.defaults['absolute'], isFalse);
    expect(t.takeException(), isNull);
  });

  testWidgets('「지금 친구 모두에게 적용」 — 몇 명 · 무엇이 나가는지 묻고, 본 값을 보내고, 친구 캐시만 고친다',
      (t) async {
    _narrow(t);
    final stale = jsonEncode({..._blank(), 'streak': false});
    SharedPreferences.setMockInitialValues({
      'mybody.share.cache.v1.f1': stale,
      'mybody.share.cache.v1.x9': stale,     // 이제 친구가 아닌 사람
    });
    final s = _FakeServer()..defaults['bfmTrend'] = true;
    await _pump(t, await _api(s.client), const ShareDefaultsScreen());

    await t.tap(find.text('지금 친구 모두에게 적용'));
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget, reason: '덮어쓰기 전에 페이지 안에서 묻습니다');
    expect(find.text('친구 3명에게 적용할까요?'), findsOneWidget);
    expect(find.textContaining('체지방 변화', findRichText: true), findsWidgets);
    expect(find.text('친구마다 따로 정한 것도 덮어씁니다'), findsOneWidget,
        reason: '친구별로 따로 열어 둔(닫아 둔) 것이 조용히 사라지면 안 됩니다');
    expect(t.takeException(), isNull, reason: '360px 확인 창');
    await t.tap(find.text('그대로'));
    await t.pumpAndSettle();
    expect(s.calls.where((c) => c.startsWith('POST')), isEmpty, reason: '「그대로」 면 아무것도 안 보냅니다');

    await t.tap(find.text('지금 친구 모두에게 적용'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, '적용'));
    await t.pumpAndSettle();
    expect(s.calls, contains('POST /share-defaults/apply'));
    expect(s.applies.last, {'expect': s.defaults}, reason: '확인 창에서 본 값을 같이 보냅니다');
    expect(find.text('친구 3명에게 적용했습니다'), findsOneWidget);

    final sp = await SharedPreferences.getInstance();
    final cached = jsonDecode(sp.getString('mybody.share.cache.v1.f1')!) as Map;
    expect(cached['streak'], isTrue, reason: '비행기 모드의 친구 상세가 적용 전 값을 보여 주면 안 됩니다');
    expect(cached['bfmTrend'], isTrue);
    expect(sp.getString('mybody.share.cache.v1.x9'), stale, reason: '수락된 친구가 아니면 "적용됨" 을 쓰지 않습니다');
    expect(t.takeException(), isNull);
  });

  testWidgets('친구가 없으면 「적용」 버튼이 없다', (t) async {
    SharedPreferences.setMockInitialValues({});
    final s = _FakeServer()..friends = [];
    await _pump(t, await _api(s.client), const ShareDefaultsScreen());
    expect(find.byType(SwitchListTile), findsNWidgets(kShareFields.length));
    expect(find.text('지금 친구 모두에게 적용'), findsNothing);
  });

  testWidgets('서버가 적용한 친구가 0명이면 없다고 말한다', (t) async {
    SharedPreferences.setMockInitialValues({});
    final s = _FakeServer()..applied = 0;
    await _pump(t, await _api(s.client), const ShareDefaultsScreen());
    await t.tap(find.text('지금 친구 모두에게 적용'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, '적용'));
    await t.pumpAndSettle();
    expect(find.text('아직 친구가 없습니다'), findsOneWidget);
  });

  /* 결함: 실패하면 "누르기 직전 값" 으로 되돌렸습니다. 그 값에는 앞서 누르고 아직
     가는 중인 스위치가 이미 들어 있어서, 둘 다 실패하면 앞 스위치가 서버와 다른
     채로 남았습니다(화면 체중 켜짐 · 서버 꺼짐, 또는 반대로 화면 꺼짐 · 서버 켜짐). */
  testWidgets('겹친 두 요청이 모두 실패하면 — 서버가 확인한 값으로 돌아가고, 가는 중엔 「적용」 을 잠근다',
      (t) async {
    _narrow(t);
    SharedPreferences.setMockInitialValues({});
    final s = _FakeServer();
    await _pump(t, await _api(s.client), const ShareDefaultsScreen());
    s.gate = Completer<void>();
    s.putStatus = 500;

    await t.tap(find.widgetWithText(SwitchListTile, '체중 변화'));
    await t.pump();
    await t.tap(find.widgetWithText(SwitchListTile, '골격근 변화'));
    await t.pump();
    expect(_sw(t, '체중 변화').value, isTrue, reason: '누른 것은 바로 보입니다');
    expect(_sw(t, '골격근 변화').value, isTrue);
    expect(_applyButton(t).onPressed, isNull, reason: '서버에 아직 없는 값을 친구 전원에게 쓰면 안 됩니다');
    final getsBefore = s.calls.where((c) => c == 'GET /share-defaults').length;

    s.gate!.complete();
    await t.pumpAndSettle();
    expect(_sw(t, '체중 변화').value, isFalse, reason: '서버는 꺼짐 — 앞 요청도 실패했습니다');
    expect(_sw(t, '골격근 변화').value, isFalse);
    expect(s.defaults['weightTrend'], isFalse);
    expect(s.calls.where((c) => c == 'GET /share-defaults').length, getsBefore + 1,
        reason: '다 끝나면 서버 값을 한 번 다시 읽습니다');
    expect(_applyButton(t).onPressed, isNotNull);
    expect(t.takeException(), isNull);
  });

  testWidgets('겹친 요청이 모두 통하면 — 마지막 답으로 둘 다 켜진 채', (t) async {
    SharedPreferences.setMockInitialValues({});
    final s = _FakeServer();
    await _pump(t, await _api(s.client), const ShareDefaultsScreen());
    s.gate = Completer<void>();
    await t.tap(find.widgetWithText(SwitchListTile, '체중 변화'));
    await t.pump();
    await t.tap(find.widgetWithText(SwitchListTile, '골격근 변화'));
    await t.pump();
    s.gate!.complete();
    await t.pumpAndSettle();
    expect(_sw(t, '체중 변화').value, isTrue);
    expect(_sw(t, '골격근 변화').value, isTrue);
    expect(s.puts, [{'weightTrend': true}, {'smmTrend': true}]);
  });

  testWidgets('저장은 됐는데 답만 잃으면 — 다시 읽어 서버 값을 보여 준다', (t) async {
    SharedPreferences.setMockInitialValues({});
    final s = _FakeServer()..putLosesReply = true;
    await _pump(t, await _api(s.client), const ShareDefaultsScreen());
    await t.tap(find.widgetWithText(SwitchListTile, '체중 변화'));
    await t.pumpAndSettle();
    expect(s.defaults['weightTrend'], isTrue);
    expect(_sw(t, '체중 변화').value, isTrue,
        reason: '화면이 꺼짐이면 사람은 끈 줄 알고, 새 친구에게 체중이 나갑니다');
  });

  /* 결함: 캐시(몸 꺼짐)를 보여 주는 동안 「적용」 을 누르면 서버의 다른 값(다른
     기기에서 켠 몸 켜짐)이 친구 전원에게 쓰였습니다. */
  testWidgets('캐시를 보여 주는 중 「적용」 — 서버의 지금 값을 다시 받아 보여 주고, 몸 항목은 따로 눈에 띄게',
      (t) async {
    _narrow(t);
    SharedPreferences.setMockInitialValues({'mybody.share.defaults.cache.v1': jsonEncode(_blank())});
    final s = _FakeServer()..failGets = 1;
    s.defaults
      ..['weightTrend'] = true
      ..['absolute'] = true;
    await _pump(t, await _api(s.client), const ShareDefaultsScreen());
    expect(find.textContaining('마지막으로 본 설정'), findsOneWidget);
    expect(_sw(t, '체중 변화').value, isFalse);

    await t.tap(find.text('지금 친구 모두에게 적용'));
    await t.pumpAndSettle();
    expect(find.text('친구 3명에게 적용할까요?'), findsOneWidget);
    expect(_sw(t, '체중 변화').value, isTrue, reason: '화면도 서버의 지금 값으로');
    expect(find.textContaining('마지막으로 본 설정'), findsNothing);
    final reach = t.widget<ShareReach>(find.byType(ShareReach));
    expect(reach.flags['weightTrend'], isTrue);
    expect(find.textContaining('체중 변화 · 실제 수치', findRichText: true), findsOneWidget,
        reason: '몸 숫자가 나간다는 것이 확인 창에 보여야 합니다');
    expect(t.takeException(), isNull);
    await t.tap(find.widgetWithText(FilledButton, '적용'));
    await t.pumpAndSettle();
    expect(s.applies.last, {'expect': s.defaults});
  });

  testWidgets('확인 창을 보는 사이 다른 기기에서 바뀌면 — 409, 성공이라고 하지 않고 새 값을 보여 준다',
      (t) async {
    SharedPreferences.setMockInitialValues({});
    final s = _FakeServer();
    await _pump(t, await _api(s.client), const ShareDefaultsScreen());
    await t.tap(find.text('지금 친구 모두에게 적용'));
    await t.pumpAndSettle();
    s.defaults['bfmTrend'] = true;                 // 그 사이 다른 기기에서
    await t.tap(find.widgetWithText(FilledButton, '적용'));
    await t.pumpAndSettle();
    expect(find.textContaining('기본값이 방금 바뀌었습니다'), findsOneWidget);
    expect(find.textContaining('적용했습니다'), findsNothing);
    expect(_sw(t, '체지방 변화').value, isTrue);
  });

  /* 결함: 친구 상세가 큐에 남긴 공유 변경(예전엔 스위치 전체 값)이 「적용」 뒤에
     도착해 적용한 값을 조용히 되돌렸습니다. */
  testWidgets('친구별 공유 변경이 큐에 남아 있으면 — 먼저 보내 보고, 안 가면 적용하지 않는다', (t) async {
    _narrow(t);      // 긴 화면 — 첫 토스트가 버튼을 가리지 않게
    SharedPreferences.setMockInitialValues({});
    final s = _FakeServer()..shareFails = true;
    final api = await _api(s.client);
    final q = SyncQueue(api: api, storage: _MemQueue());
    await _pump(t, api, const ShareDefaultsScreen(), queue: q);
    q.add('setShare', {'userId': 'f1', 'patch': {'weightTrend': true}});
    await t.pumpAndSettle();
    expect(q.pendingOf('setShare'), 1);

    await t.tap(find.text('지금 친구 모두에게 적용'));
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.textContaining('아직 서버에 안 갔습니다'), findsOneWidget);
    expect(s.calls, isNot(contains('POST /share-defaults/apply')));

    /* 망이 돌아오면 큐가 먼저 가고 그다음에 적용 — 옛 변경이 적용을 되돌리지 않습니다. */
    s.shareFails = false;
    await t.tap(find.text('지금 친구 모두에게 적용'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, '적용'));
    await t.pumpAndSettle();
    expect(q.pending, 0);
    expect(s.calls.lastIndexOf('PUT /share/f1'), lessThan(s.calls.indexOf('POST /share-defaults/apply')));
    q.dispose();
  });

  test('로그아웃하면 친구 · 공유 캐시를 지운다 — 다음 계정에 앞 사람의 설정이 안 보이게', () async {
    SharedPreferences.setMockInitialValues({
      'mybody.share.defaults.cache.v1': '{}',
      'mybody.share.cache.v1.f1': '{}',
      'mybody.friends.cache.v1': '{}',
      'mybody.state.v1': 'keep',
      'mybody.server.v1': 'keep',
    });
    final api = await _api(MockClient((_) async => _json({'ok': true})));
    await api.signOut();
    final sp = await SharedPreferences.getInstance();
    expect(sp.getKeys(), {'mybody.state.v1', 'mybody.server.v1'});
  });

  testWidgets('받은 요청 — 수락 옆에 내 기본값으로 나갈 것, 몸 항목까지 (360px)', (t) async {
    _narrow(t, height: 1200);
    SharedPreferences.setMockInitialValues({});
    final s = _FakeServer()
      ..friends = []
      ..incoming = [{'id': 'r1', 'displayName': '다솜'}];
    s.defaults
      ..['weightTrend'] = true
      ..['absolute'] = true;
    await _pump(t, await _api(s.client), Scaffold(body: SocialScreen(go: (_, [__]) {})));
    expect(find.text('다솜'), findsOneWidget);
    expect(find.textContaining('수락하면 보여 줄 것', findRichText: true), findsOneWidget);
    expect(find.textContaining('체중 변화 · 실제 수치', findRichText: true), findsOneWidget);
    expect(find.textContaining('기본 비공개'), findsNothing, reason: '몸을 켜 둔 사람에게 "기본 비공개" 는 거짓말');
    expect(find.text('무엇이 보일지는 「기본 공유」에서 정합니다'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('옛 서버(404)면 한 줄로 — 스위치도 버튼도 없다', (t) async {
    _narrow(t);
    SharedPreferences.setMockInitialValues({});
    final api = await _api(MockClient((_) async => _json({'ok': false, 'reason': '그런 경로가 없습니다'}, 404)));
    await _pump(t, api, const ShareDefaultsScreen());
    expect(find.text('서버를 업데이트하면 쓸 수 있습니다'), findsOneWidget);
    expect(find.byType(SwitchListTile), findsNothing);
    expect(find.text('지금 친구 모두에게 적용'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('오프라인 — 마지막으로 본 값을 보여 주고, 못 보낸 변경은 되돌린다', (t) async {
    SharedPreferences.setMockInitialValues({});
    final s = _FakeServer()..defaults['smmTrend'] = true;
    await _pump(t, await _api(s.client), const ShareDefaultsScreen(key: ValueKey('online')));
    expect(find.text('4개 켜짐 · 새 친구에게 자동으로 적용'), findsOneWidget);

    final dead = await _api(MockClient((_) async => throw http.ClientException('offline')));
    await _pump(t, dead, const ShareDefaultsScreen(key: ValueKey('offline')));
    expect(find.textContaining('서버에 못 닿아 마지막으로 본 설정'), findsOneWidget);
    expect(_sw(t, '골격근 변화').value, isTrue, reason: '"다 꺼졌네" 로 보이면 사람은 다시 켭니다');

    await t.tap(find.widgetWithText(SwitchListTile, '골격근 변화'));
    await t.pumpAndSettle();
    expect(_sw(t, '골격근 변화').value, isTrue,
        reason: '서버가 모르는 기본값을 화면만 바꿔 두면 새 친구에게 다른 것이 나갑니다');
    expect(find.textContaining('서버에 닿지 못했습니다'), findsOneWidget);
  });

  testWidgets('오프라인에 캐시도 없으면 — 모른다고만, 스위치를 지어내지 않는다', (t) async {
    SharedPreferences.setMockInitialValues({});
    final dead = await _api(MockClient((_) async => throw http.ClientException('offline')));
    await _pump(t, dead, const ShareDefaultsScreen());
    expect(find.byType(SwitchListTile), findsNothing);
    expect(find.textContaining('서버에 닿지 못했습니다'), findsOneWidget);
    expect(find.byTooltip('다시'), findsOneWidget);
  });

  testWidgets('설정 — 로그인했으면 카드가 접힌 채로 있고, 펴면 스위치', (t) async {
    t.view.physicalSize = const Size(1000, 4000);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    SharedPreferences.setMockInitialValues({});
    final s = _FakeServer();
    await _pump(t, await _api(s.client), const SettingsScreen());

    expect(find.text('친구에게 기본으로 보여 주는 것'), findsOneWidget);
    expect(find.text('3개 켜짐 · 새 친구에게 자동으로 적용'), findsOneWidget);
    expect(find.widgetWithText(SwitchListTile, '체중 변화'), findsNothing, reason: '설정에서는 접혀 있습니다');
    await t.tap(find.text('친구에게 기본으로 보여 주는 것'));
    await t.pumpAndSettle();
    expect(find.widgetWithText(SwitchListTile, '체중 변화'), findsOneWidget);
  });

  testWidgets('설정 — 로그인 안 했으면 카드가 없다', (t) async {
    SharedPreferences.setMockInitialValues({});
    final app = await AppState.boot();
    final api = Api(baseUrl: 'https://x.test', client: _FakeServer().client);
    await t.pumpWidget(Scope(state: app, api: api, onServerChange: (_) async {},
        child: MaterialApp(theme: mbLight(), home: const SettingsScreen())));
    await t.pumpAndSettle();
    expect(find.text('친구에게 기본으로 보여 주는 것'), findsNothing);
  });

  testWidgets('친구 탭의 「기본 공유」 — 같은 카드를 펼친 채로 열고, 돌아오면 목록을 다시 받는다 (360px)',
      (t) async {
    _narrow(t, height: 1200);
    SharedPreferences.setMockInitialValues({});
    final s = _FakeServer();
    await _pump(t, await _api(s.client), Scaffold(body: SocialScreen(go: (_, [__]) {})));
    expect(t.takeException(), isNull);
    final before = s.friendsGets;

    await t.tap(find.text('기본 공유'));
    await t.pumpAndSettle();
    expect(find.byType(ShareDefaultsScreen), findsOneWidget);
    expect(find.byType(SwitchListTile), findsNWidgets(kShareFields.length), reason: '펼친 채로');

    await t.pageBack();
    await t.pumpAndSettle();
    expect(s.friendsGets, greaterThan(before));
    expect(t.takeException(), isNull);
  });
}
