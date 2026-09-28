/* 「의견함」 — 운영자가 앱 안에서 의견을 읽는 곳(screens/feedback_inbox.dart · api.dart).
 *
 * 주인의 물음 "의견 어디서 봐" 의 답. 여기서 지키는 것:
 *
 *   · Api — /me 의 isOperator 를 읽어 두고(로그인이 바뀌면 잊음), 의견함 한 쪽을 읽고
 *     (익명 · 이름 · 판 · 기종 · 화면 · 사진 목록 · 다음 쪽 번호), 사진은 토큰을 붙여 바이트로
 *     받아 메모리에 30장까지(오래 안 본 것부터 뺌). limit 은 1~50 으로 자릅니다.
 *   · 설정 — 운영자에게만 도움말 맨 위에 「의견함」 줄과 안 읽은 개수. 다른 사람 · 로그인 안 한
 *     사람에게는 줄이 없고, 의견함 길을 부르지도 않습니다. 의견함에서 돌아오면 개수를 다시 받습니다.
 *   · 목록 — 새것부터, 안 읽음 점, 「익명」, 판 · 기종 · 화면 칸, 글 세 줄, 캡처 작은 그림(받아서).
 *     끝에 가까워지면 다음 쪽, 끌어 내리면 새로. 비었으면 「아직 의견이 없어요」.
 *   · 상세 — 열면 읽음(목록의 점 · 개수도 바로), 서버에 못 닿으면 되돌림. 지우기는 한 번 묻고,
 *     지우면 목록에서 빠집니다. 캡처를 누르면 전체 화면(키우기 · 옆으로 넘기기).
 *   · 실패 — 첫 쪽 실패는 가운데에 「다시 시도」, 운영자가 아니면(403) 무엇을 하면 되는지로.
 *   · 알림 — route 'feedback' 을 따라가고(모르는 값은 여전히 버림), 셸이 의견함을 엽니다.
 *     로그인하지 않았으면 아무것도 안 엽니다 — 보던 화면도 안 닫습니다.
 *   · 받는 사이 로그인이 바뀌면 앞 계정의 캡처는 버리고, 다음 번호가 줄지 않는 답은 믿지 않습니다.
 *   · 360px · 글자 1.3배 · 밝게/어둡게 — 넘치지 않습니다. */
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mybody/src/api.dart';
import 'package:mybody/src/app_state.dart';
import 'package:mybody/src/native_push.dart' show pushRoute, kPushRoutes;
import 'package:mybody/src/nudge.dart' show notificationRoute;
import 'package:mybody/src/scope.dart';
import 'package:mybody/src/screens/feedback_inbox.dart';
import 'package:mybody/src/screens/settings.dart';
import 'package:mybody/src/screens/tester_welcome.dart' show markTesterWelcomeSeen;
import 'package:mybody/src/shell.dart';
import 'package:mybody/src/theme.dart';
import 'package:mybody/src/ui/widgets.dart';

/// 1×1 PNG — 진짜로 열리는 가장 작은 그림.
final _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==');

/// 시험의 「지금」 — 이 폰의 시각으로 9월 28일 정오.
final _now = DateTime(2026, 9, 28, 12, 0);

http.Response _json(Object body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status,
        headers: {'content-type': 'application/json; charset=utf-8'});

/// 서버 흉내 — server.js handleFeedbackInbox 의 약속대로.
class _Server {
  bool operator = true;

  /// 새것부터.
  final items = <Map<String, dynamic>>[];
  final calls = <String>[];

  /// 사진 요청에 붙어 온 Authorization.
  final imageAuth = <String?>[];

  /// 다음 목록 요청 하나를 이 상태로 실패시킵니다.
  int? failInbox;

  /// 읽음 · 모두 읽음 · 지우기를 이 상태로 실패시킵니다(계속).
  int? failRead;
  int? failReadAll;
  int? failDelete;
  Object? readAllBody;

  /// 있으면 사진 요청이 이게 풀릴 때까지 답하지 않고, 풀린 뒤에는 404(못 받음).
  Completer<void>? imageGate;

  /// 사진 요청이 차례로 하나씩 가져가 풀릴 때까지 기다린 뒤 평소대로 답합니다(느린 받기).
  final imageHolds = <Completer<void>>[];

  /// 다음 쪽 요청에 before 를 그대로 nextBefore 로 돌려줍니다(서버의 실수 흉내).
  bool stuckNext = false;

  void add(int id, {
    DateTime? at,
    String text = '',
    bool read = false,
    int images = 0,
    String? from,
    bool anonymous = false,
    String? appVersion = '0.2.14+300',
    String? platform = 'android',
    String? screen = '홈',
  }) {
    items.add({
      'id': id,
      'createdAt': (at ?? _now.subtract(Duration(hours: id))).toUtc().toIso8601String(),
      'appVersion': appVersion,
      'platform': platform,
      'screen': screen,
      'text': text,
      'read': read,
      'images': [for (var n = 1; n <= images; n++) {'n': n, 'type': 'image/png'}],
      'from': anonymous ? null : {'name': from ?? '친구$id'},
    });
    items.sort((a, b) => (b['id'] as int).compareTo(a['id'] as int));
  }

  int get unread => items.where((i) => i['read'] != true).length;
  int count(String call) => calls.where((c) => c == call).length;

  MockClient get client => MockClient((req) async {
        final path = req.url.path.replaceFirst('/api', '');
        final q = req.url.query;
        calls.add('${req.method} $path${q.isEmpty ? '' : '?$q'}');
        if (path == '/me') {
          return _json({'ok': true, 'user': {'id': 'u1', 'displayName': '주인', if (operator) 'isOperator': true}});
        }
        if (!path.startsWith('/feedback/inbox')) return _json({'ok': true});
        if (req.headers['authorization'] == null) return _json({'ok': false, 'reason': '로그인이 필요합니다'}, 401);
        if (!operator) return _json({'ok': false, 'error': '운영자만 볼 수 있어요', 'reason': '운영자만 볼 수 있어요'}, 403);
        if (path == '/feedback/inbox' && req.method == 'GET') {
          if (failInbox case final st?) {
            failInbox = null;
            return _json({'ok': false, 'error': '서버가 잠깐 아파요'}, st);
          }
          final limit = int.parse(req.url.queryParameters['limit'] ?? '30');
          final before = int.tryParse(req.url.queryParameters['before'] ?? '');
          final rest = [for (final i in items) if (before == null || (i['id'] as int) < before) i];
          final page = rest.take(limit).toList();
          return _json({
            'ok': true,
            'unread': unread,
            'items': page,
            'nextBefore': stuckNext && before != null ? before : (rest.length > limit ? page.last['id'] : null),
          });
        }
        if (path == '/feedback/inbox/read-all' && req.method == 'POST') {
          if (failReadAll case final st?) return _json({'ok': false, 'error': '못 했어요'}, st);
          readAllBody = req.body.isEmpty ? null : jsonDecode(req.body);
          final upTo = readAllBody is Map ? (readAllBody as Map)['upTo'] as int? : null;
          for (final i in items) {
            if (upTo == null || (i['id'] as int) <= upTo) i['read'] = true;
          }
          return _json({'ok': true});
        }
        final m = RegExp(r'^/feedback/inbox/(\d+)(?:/(read|image)(?:/(\d+))?)?$').firstMatch(path);
        if (m == null) return _json({'ok': false, 'error': '그런 경로가 없습니다'}, 404);
        final id = int.parse(m[1]!);
        final it = items.where((i) => i['id'] == id).firstOrNull;
        if (m[2] == 'image') {
          imageAuth.add(req.headers['authorization']);
          if (imageGate case final g?) {
            await g.future;
            return _json({'ok': false, 'error': '그 사진이 없어요'}, 404);
          }
          if (imageHolds.isNotEmpty) await imageHolds.removeAt(0).future;
          final n = int.parse(m[3]!);
          if (it == null || n > (it['images'] as List).length) {
            return _json({'ok': false, 'error': '그 사진이 없어요'}, 404);
          }
          return http.Response.bytes(_png, 200,
              headers: {'content-type': 'image/png', 'cache-control': 'private, no-store'});
        }
        if (m[2] == 'read' && req.method == 'POST') {
          if (failRead case final st?) return _json({'ok': false, 'error': '못 했어요'}, st);
          it?['read'] = true;
          return _json({'ok': true});
        }
        if (m[2] == null && req.method == 'DELETE') {
          if (failDelete case final st?) return _json({'ok': false, 'error': '지우지 못했어요'}, st);
          items.removeWhere((i) => i['id'] == id);
          return _json({'ok': true});
        }
        return _json({'ok': false, 'error': '그런 경로가 없습니다'}, 404);
      });
}

Future<Api> _api(_Server s, {bool signedIn = true}) async {
  final api = Api(baseUrl: 'https://x.test', client: s.client);
  if (signedIn) await api.setToken('tok');
  return api;
}

/// 첫 화면 위에 의견함을 밀어 올린 상태 — 앱에서처럼(뒤로 가기가 있게).
Future<void> _pumpInbox(WidgetTester t, Api api,
    {Size size = const Size(420, 900), ThemeData? theme}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final app = await AppState.boot();
  await t.pumpWidget(Scope(
    state: app,
    api: api,
    onServerChange: (_) async {},
    child: MaterialApp(
      theme: theme ?? mbLight(),
      home: Builder(
          builder: (context) => Scaffold(
                body: Center(
                    child: TextButton(
                  onPressed: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => FeedbackInboxScreen(now: () => _now))),
                  child: const Text('첫 화면'),
                )),
              )),
    ),
  ));
  await t.tap(find.text('첫 화면'));
  await t.pumpAndSettle();
}

Finder _item(int id) => find.byKey(ValueKey('inbox-item-$id'));
Finder _dot(int id) => find.byKey(ValueKey('inbox-unread-$id'));
final _readAll = find.byKey(const Key('inbox-read-all'));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  /* --- 시각 ------------------------------------------------------------------------ */
  group('보낸 때', () {
    test('한 시간 안이면 「방금」 · 「N분 전」, 그 밖은 「9월 28일 04:12」', () {
      expect(inboxTimeLabel(_now.subtract(const Duration(seconds: 20)), _now), '방금');
      expect(inboxTimeLabel(_now.subtract(const Duration(minutes: 5)), _now), '5분 전');
      expect(inboxTimeLabel(_now.subtract(const Duration(minutes: 59)), _now), '59분 전');
      expect(inboxTimeLabel(DateTime(2026, 9, 28, 4, 12), _now), '9월 28일 04:12');
      expect(inboxTimeLabel(DateTime(2025, 12, 1, 23, 5), _now), '12월 1일 23:05',
          reason: '목록에는 연도 없이 — 서버가 1년만 두고, 새것부터라 차례가 연도를 말합니다');
    });

    test('서버 시계가 조금 앞서도 「방금」 — 음수 「-2분 전」 은 없다', () {
      expect(inboxTimeLabel(_now.add(const Duration(minutes: 2)), _now), '방금');
    });

    test('상세(relative: false)는 한 시간 안이어도 날짜와 시각 — 올해가 아니면 연도까지', () {
      expect(inboxTimeLabel(DateTime(2026, 9, 28, 11, 55), _now, relative: false), '9월 28일 11:55');
      expect(inboxTimeLabel(DateTime(2025, 12, 1, 23, 5), _now, relative: false), '2025년 12월 1일 23:05');
    });
  });

  /* --- Api -------------------------------------------------------------------------- */
  group('Api', () {
    test('/me 의 isOperator 를 적어 두고, 로그인이 바뀌면 잊는다', () async {
      final s = _Server();
      final api = await _api(s);
      expect(api.isOperator, isNull, reason: '아직 안 물었으면 모름');
      await api.me();
      expect(api.isOperator, isTrue);
      await api.setToken('other');
      expect(api.isOperator, isNull, reason: '다른 계정 — 앞 사람의 값을 쓰지 않습니다');
      s.operator = false;
      await api.me();
      expect(api.isOperator, isFalse);
      await api.setToken(null);
      expect(api.isOperator, isFalse, reason: '로그인 안 했으면 운영자가 아닙니다');
      expect(Api.isOperatorUser({'isOperator': true}), isTrue);
      expect(Api.isOperatorUser({'isOperator': 'true'}), isFalse);
      expect(Api.isOperatorUser(null), isFalse);
    });

    test('한 쪽을 읽는다 — 익명 · 이름 · 칸 · 사진 · 다음 쪽', () async {
      final s = _Server()
        ..add(3, text: '버튼이 안 눌려요', images: 2, from: '민지', screen: '식단',
            at: DateTime(2026, 9, 28, 4, 12))
        ..add(2, anonymous: true, platform: 'ios', appVersion: null, screen: null, read: true)
        ..add(1, text: '좋아요');
      final api = await _api(s);
      final p = await api.fetchInbox(limit: 2);
      expect(p.ok, isTrue);
      expect(s.calls.last, 'GET /feedback/inbox?limit=2');
      expect(p.unread, 2);
      expect(p.nextBefore, 2);
      expect([for (final i in p.items) i.id], [3, 2]);
      final a = p.items.first;
      expect(a.text, '버튼이 안 눌려요');
      expect(a.anonymous, isFalse);
      expect(a.fromName, '민지');
      expect(a.appVersion, '0.2.14+300');
      expect(a.platform, 'android');
      expect(a.screen, '식단');
      expect(a.read, isFalse);
      expect(a.images, [(n: 1, type: 'image/png'), (n: 2, type: 'image/png')]);
      expect(a.createdAt, DateTime(2026, 9, 28, 4, 12), reason: '이 폰의 시각으로');
      final b = p.items.last;
      expect(b.anonymous, isTrue);
      expect(inboxFrom(b), '익명');
      expect(b.appVersion, isNull);
      expect(b.screen, isNull);
      expect(b.read, isTrue);
      expect(b.text, '');

      final next = await api.fetchInbox(before: p.nextBefore, limit: 2);
      expect(s.calls.last, 'GET /feedback/inbox?limit=2&before=2');
      expect([for (final i in next.items) i.id], [1]);
      expect(next.nextBefore, isNull, reason: '마지막 쪽');
    });

    test('limit 은 1~50 으로 자른다', () async {
      final s = _Server();
      final api = await _api(s);
      await api.fetchInbox(limit: 0);
      expect(s.calls.last, 'GET /feedback/inbox?limit=1');
      await api.fetchInbox(limit: 999);
      expect(s.calls.last, 'GET /feedback/inbox?limit=50');
      await api.fetchInbox();
      expect(s.calls.last, 'GET /feedback/inbox?limit=30');
    });

    test('이상한 칸은 버리거나 비운다 — id 없는 칸 · 숫자 글자 id · 모르는 모양', () {
      final p = InboxPage.from(const ApiResult(200, {
        'ok': true,
        'unread': '4',
        'nextBefore': null,
        'items': [
          {'text': 'id 가 없음'},
          'nonsense',
          {'id': '7', 'text': null, 'images': [{'type': 'image/png'}, {'n': 2}], 'from': {'name': ' '}},
        ],
      }));
      expect(p.items.single.id, 7);
      expect(p.items.single.text, '');
      expect(p.items.single.images, [(n: 2, type: 'image/png')]);
      expect(p.items.single.anonymous, isFalse);
      expect(inboxFrom(p.items.single), '이름 없음', reason: '계정은 있는데 이름이 비었을 때');
      expect(p.unread, 4);
    });

    test('운영자가 아니면(403) · 로그인이 없으면(401) 무엇을 하면 되는지로', () async {
      final s = _Server()..operator = false;
      final api = await _api(s);
      final p = await api.fetchInbox();
      expect(p.denied, isTrue);
      expect(p.reason, '운영자 계정으로 로그인하면 볼 수 있어요');
      final out = await _api(s, signedIn: false);
      final q = await out.fetchInbox();
      expect(q.result.status, 401);
      expect(q.denied, isTrue);
      expect(inboxReason(const ApiResult(500, {'ok': false, 'error': '서버가 아파요'})), '서버가 아파요');
      expect(inboxReason(const ApiResult(0, {})), contains('서버에 닿지 못했습니다'));
    });

    test('사진은 토큰을 붙여 바이트로 받고, 한 번 받은 것은 다시 안 받는다', () async {
      final s = _Server()..add(5, images: 1);
      final api = await _api(s);
      final a = await api.inboxImage(5, 1);
      expect(a, _png);
      expect(s.imageAuth.single, 'Bearer tok');
      expect(api.cachedInboxImage(5, 1), _png);
      final b = await api.inboxImage(5, 1);
      expect(b, _png);
      expect(s.count('GET /feedback/inbox/5/image/1'), 1, reason: '캐시에서');
      /* 동시에 둘이 청해도 한 번. */
      final both = await Future.wait([api.inboxImage(5, 9), api.inboxImage(5, 9)]);
      expect(both, [null, null], reason: '없는 사진은 null');
      expect(s.count('GET /feedback/inbox/5/image/9'), 1);
      expect(await api.inboxImage(5, 9), isNull);
      expect(s.count('GET /feedback/inbox/5/image/9'), 2, reason: '실패는 캐시하지 않습니다 — 다시 해 볼 수 있게');
    });

    test('캐시는 30장까지 — 오래 안 본 것부터 빼고, 로그인이 바뀌면 비운다', () async {
      final s = _Server();
      for (var i = 1; i <= 31; i++) {
        s.add(i, images: 1);
      }
      final api = await _api(s);
      for (var i = 1; i <= 30; i++) {
        await api.inboxImage(i, 1);
      }
      expect(api.inboxImageCacheSize, 30);
      /* 1번을 다시 보면 가장 최근 것이 되고, 31번이 들어올 때 2번이 빠집니다. */
      expect(api.cachedInboxImage(1, 1), isNotNull);
      await api.inboxImage(31, 1);
      expect(api.inboxImageCacheSize, kInboxImageCacheCount);
      expect(api.cachedInboxImage(1, 1), isNotNull);
      expect(api.cachedInboxImage(2, 1), isNull);

      await api.setToken('someone-else');
      expect(api.inboxImageCacheSize, 0, reason: '다른 계정에게 앞 운영자의 캡처가 나오면 안 됩니다');
    });

    test('받는 사이 로그인이 바뀌면 앞 계정의 캡처는 화면에도 캐시에도 안 준다 — 새 계정의 받기는 그대로', () async {
      final holdA = Completer<void>(), holdB = Completer<void>();
      final s = _Server()..add(5, images: 1);
      s.imageHolds.addAll([holdA, holdB]);
      final api = await _api(s);
      final a = api.inboxImage(5, 1);
      await pumpEventQueue();
      await api.setToken('someone-else');
      final b1 = api.inboxImage(5, 1);
      await pumpEventQueue();
      holdA.complete();
      expect(await a, isNull, reason: '앞 계정으로 청한 것');
      expect(api.cachedInboxImage(5, 1), isNull);
      /* 앞 받기가 끝나며 새 받기의 자리를 지우면, 같은 장을 또 청할 때 한 번 더 받습니다. */
      final b2 = api.inboxImage(5, 1);
      holdB.complete();
      expect(await b1, _png);
      expect(await b2, _png);
      expect(s.count('GET /feedback/inbox/5/image/1'), 2);
      expect(s.imageAuth, ['Bearer tok', 'Bearer someone-else']);
    });

    test('로그인하지 않았으면 사진을 청하지도 않는다', () async {
      final s = _Server()..add(1, images: 1);
      final api = await _api(s, signedIn: false);
      expect(await api.inboxImage(1, 1), isNull);
      expect(s.calls, isEmpty);
    });

    test('읽음 · 모두 읽음(upTo) · 지우기 — 지우면 그 사진도 캐시에서 뺀다', () async {
      final s = _Server()
        ..add(2, images: 1)
        ..add(1);
      final api = await _api(s);
      expect((await api.markRead(2)).ok, isTrue);
      expect(s.calls.last, 'POST /feedback/inbox/2/read');
      expect((await api.markAllRead(upTo: 2)).ok, isTrue);
      expect(s.calls.last, 'POST /feedback/inbox/read-all');
      expect(s.readAllBody, {'upTo': 2});
      await api.markAllRead();
      expect(s.readAllBody, isNull, reason: 'upTo 없이 부르면 몸통도 없이');
      await api.inboxImage(2, 1);
      expect(api.cachedInboxImage(2, 1), isNotNull);
      expect((await api.deleteFeedback(2)).ok, isTrue);
      expect(s.calls.last, 'DELETE /feedback/inbox/2');
      expect(api.cachedInboxImage(2, 1), isNull);
    });
  });

  /* --- 설정 ------------------------------------------------------------------------- */
  group('설정의 「의견함」 줄', () {
    Future<void> openSettings(WidgetTester t, Api api) async {
      t.view.physicalSize = const Size(1000, 4000);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      final app = await AppState.boot();
      app.store.set({'onboarded': true, 'profile': {'sex': 'male', 'age': 30, 'heightCm': 175}});
      await t.pumpWidget(Scope(
        state: app,
        api: api,
        onServerChange: (_) async {},
        child: MaterialApp(
          theme: mbLight(),
          home: Builder(
              builder: (context) => Scaffold(
                    body: Center(
                        child: TextButton(
                      onPressed: () => Navigator.of(context)
                          .push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
                      child: const Text('첫 화면'),
                    )),
                  )),
        ),
      ));
      await t.tap(find.text('첫 화면'));
      await t.pumpAndSettle();
    }

    final row = find.byKey(const Key('settings-feedback-inbox'));
    final badge = find.byKey(const Key('settings-feedback-inbox-unread'));

    testWidgets('운영자면 도움말 맨 위에 줄과 안 읽은 개수, 누르면 의견함, 돌아오면 개수를 다시', (t) async {
      final s = _Server()
        ..add(3, text: '첫째')
        ..add(2, text: '둘째')
        ..add(1, text: '셋째', read: true);
      final api = await _api(s);
      await openSettings(t, api);
      expect(row, findsOneWidget);
      expect(find.descendant(of: row, matching: find.text('의견함')), findsOneWidget);
      expect(find.descendant(of: badge, matching: find.text('2')), findsOneWidget);
      expect(s.calls, contains('GET /feedback/inbox?limit=1'), reason: '개수만 — 한 건만 받습니다');

      /* 자리 — 도움말 카드 안, 말풍선 스위치보다 위. */
      final help = find.ancestor(of: find.text('도움말'), matching: find.byType(MbCard));
      expect(find.descendant(of: help, matching: row), findsOneWidget);
      expect(t.getRect(row).bottom,
          lessThanOrEqualTo(t.getRect(find.byKey(const Key('settings-feedback-bubble'))).top + 0.01));

      await t.tap(row);
      await t.pumpAndSettle();
      expect(find.byType(FeedbackInboxScreen), findsOneWidget);
      expect(find.widgetWithText(AppBar, '의견함'), findsOneWidget, reason: '줄 이름과 같은 제목');

      /* 하나를 열어 읽고 돌아오면 개수가 1. */
      await t.tap(_item(3));
      await t.pumpAndSettle();
      await t.pageBack();
      await t.pumpAndSettle();
      await t.pageBack();
      await t.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(find.descendant(of: badge, matching: find.text('1')), findsOneWidget);
    });

    testWidgets('/me 를 이미 받았으면 다시 묻지 않는다', (t) async {
      final s = _Server()..add(1);
      final api = await _api(s);
      await api.me();
      s.calls.clear();
      await openSettings(t, api);
      expect(row, findsOneWidget);
      expect(s.calls.where((c) => c == 'GET /me'), isEmpty);
    });

    testWidgets('안 읽은 것이 없으면 개수 없이 줄만', (t) async {
      final s = _Server()..add(1, read: true);
      final api = await _api(s);
      await openSettings(t, api);
      expect(row, findsOneWidget);
      expect(badge, findsNothing);
    });

    testWidgets('운영자가 아니면 줄이 없고 의견함 길도 안 부른다', (t) async {
      final s = _Server()
        ..operator = false
        ..add(1);
      final api = await _api(s);
      await openSettings(t, api);
      expect(row, findsNothing);
      expect(find.text('의견함'), findsNothing, reason: '자리표시도 없이');
      expect(s.calls, contains('GET /me'));
      expect(s.calls.where((c) => c.contains('/feedback/inbox')), isEmpty);
    });

    testWidgets('로그인하지 않았으면 줄이 없고 /me 도 안 묻는다', (t) async {
      final s = _Server()..add(1);
      final api = await _api(s, signedIn: false);
      await openSettings(t, api);
      expect(row, findsNothing);
      expect(s.calls.where((c) => c == 'GET /me' || c.contains('/feedback/inbox')), isEmpty);
    });

    testWidgets('/me 는 참인데 의견함이 403 이면(설정이 바뀐 직후) 줄을 거둔다', (t) async {
      final s = _Server()..add(1);
      final api = await _api(s);
      await api.me();
      s.operator = false;
      await openSettings(t, api);
      expect(row, findsNothing);
    });
  });

  /* --- 목록 ------------------------------------------------------------------------- */
  group('목록', () {
    testWidgets('새것부터 — 안 읽음 점 · 이름 · 익명 · 칸 · 글 세 줄 · 작은 그림', (t) async {
      final s = _Server()
        ..add(3,
            text: List.filled(12, '홈 화면에서 버튼이 안 눌려요.').join(' '),
            images: 2,
            from: '민지',
            at: _now.subtract(const Duration(minutes: 5)))
        ..add(2, anonymous: true, platform: 'ios', screen: '설정', read: true, at: DateTime(2026, 9, 28, 4, 12))
        ..add(1, text: '', images: 1, appVersion: null, platform: null, screen: null);
      final api = await _api(s);
      await _pumpInbox(t, api);

      expect(t.getRect(_item(3)).top, lessThan(t.getRect(_item(2)).top), reason: '새것부터');
      expect(_dot(3), findsOneWidget);
      expect(_dot(2), findsNothing, reason: '읽은 것은 점이 없습니다');
      expect(find.byKey(const Key('inbox-unread-count')), findsOneWidget);
      expect(find.text('안 읽은 의견 2개'), findsOneWidget);

      Finder inCard(int id, Finder f) => find.descendant(of: _item(id), matching: f);
      expect(inCard(3, find.text('민지')), findsOneWidget);
      expect(inCard(3, find.text('5분 전')), findsOneWidget);
      expect(inCard(2, find.text('익명')), findsOneWidget);
      expect(inCard(2, find.text('9월 28일 04:12')), findsOneWidget);

      expect(inCard(3, find.text('0.2.14+300')), findsOneWidget);
      expect(inCard(3, find.text('Android')), findsOneWidget);
      expect(inCard(3, find.text('홈')), findsOneWidget);
      expect(inCard(2, find.text('iOS')), findsOneWidget);
      expect(inCard(2, find.text('설정')), findsOneWidget);
      expect(inCard(1, find.byKey(const Key('inbox-chip-version'))), findsNothing, reason: '없는 칸은 안 그립니다');
      expect(inCard(1, find.text('글 없이 캡처만 보냈어요')), findsOneWidget);

      final text = t.widget<Text>(find.byKey(const ValueKey('inbox-text-3')));
      expect(text.maxLines, 3);
      expect(text.overflow, TextOverflow.ellipsis);

      /* 작은 그림 — 받아서 그립니다(토큰을 붙여). */
      expect(find.byKey(const ValueKey('inbox-thumb-3-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('inbox-thumb-3-2')), findsOneWidget);
      expect(find.byKey(const ValueKey('inbox-img-3-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('inbox-img-1-1')), findsOneWidget);
      final img = t.widget<Image>(find.byKey(const ValueKey('inbox-img-3-1')));
      expect(img.image, isA<ResizeImage>(), reason: '작게 풀어서 — 큰 캡처를 통째로 메모리에 올리지 않게');
      expect(s.imageAuth, everyElement('Bearer tok'));
    });

    testWidgets('사진을 받는 동안은 자리표시, 못 받으면 깨진 그림', (t) async {
      final s = _Server()
        ..add(1, images: 1)
        ..imageGate = Completer<void>();
      final api = await _api(s);
      await _pumpInbox(t, api);
      expect(find.byKey(const ValueKey('inbox-img-wait-1-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('inbox-img-broken-1-1')), findsNothing);
      s.imageGate!.complete();
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('inbox-img-broken-1-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('inbox-img-1-1')), findsNothing);
    });

    testWidgets('비었으면 「아직 의견이 없어요」 — 모두 읽음은 못 누른다', (t) async {
      final api = await _api(_Server());
      await _pumpInbox(t, api);
      expect(find.text('아직 의견이 없어요'), findsOneWidget);
      expect(t.widget<TextButton>(_readAll).onPressed, isNull);
    });

    testWidgets('끝에 가까워지면 다음 쪽을 받아 잇는다', (t) async {
      final s = _Server();
      for (var i = 45; i >= 1; i--) {
        s.add(i, text: '의견 $i');
      }
      final api = await _api(s);
      await _pumpInbox(t, api);
      expect(s.calls.where((c) => c.startsWith('GET /feedback/inbox?')), ['GET /feedback/inbox?limit=30']);

      await t.scrollUntilVisible(_item(16), 400, scrollable: find.byType(Scrollable).first);
      await t.pumpAndSettle();
      expect(s.calls, contains('GET /feedback/inbox?limit=30&before=16'));
      await t.scrollUntilVisible(_item(1), 400, scrollable: find.byType(Scrollable).first);
      await t.pumpAndSettle();
      expect(_item(1), findsOneWidget);
      expect(find.byKey(const Key('inbox-more')), findsNothing, reason: '마지막 쪽 — 더 없음');
      expect(s.calls.where((c) => c.startsWith('GET /feedback/inbox?')).length, 2,
          reason: '끝에 닿아도 더 부르지 않습니다');
    });

    testWidgets('다음 번호가 줄지 않으면(서버의 실수) 같은 쪽을 되풀이해 부르지 않는다', (t) async {
      final s = _Server()..stuckNext = true;
      for (var i = 35; i >= 1; i--) {
        s.add(i);
      }
      final api = await _api(s);
      await _pumpInbox(t, api);
      await t.scrollUntilVisible(_item(1), 400, scrollable: find.byType(Scrollable).first);
      await t.pumpAndSettle();
      await t.pump(const Duration(seconds: 1));
      expect(s.calls.where((c) => c.startsWith('GET /feedback/inbox?')),
          ['GET /feedback/inbox?limit=30', 'GET /feedback/inbox?limit=30&before=6']);
      expect(find.byKey(const Key('inbox-more')), findsNothing);
    });

    testWidgets('다음 쪽이 실패하면 끝에 「다시 시도」 — 누르면 이어 받는다', (t) async {
      final s = _Server();
      for (var i = 35; i >= 1; i--) {
        s.add(i);
      }
      final api = await _api(s);
      await _pumpInbox(t, api);
      s.failInbox = 500;
      await t.scrollUntilVisible(find.byKey(const Key('inbox-more-retry')), 400,
          scrollable: find.byType(Scrollable).first);
      await t.pumpAndSettle();
      expect(find.text('서버가 잠깐 아파요'), findsOneWidget);
      final asked = s.calls.length;
      await t.pump(const Duration(seconds: 1));
      expect(s.calls.length, asked, reason: '실패를 되풀이해 부르지 않습니다');
      await t.tap(find.byKey(const Key('inbox-more-retry')));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(_item(1), 400, scrollable: find.byType(Scrollable).first);
      expect(_item(1), findsOneWidget);
    });

    testWidgets('끌어 내리면 새로 받는다 — 새 의견이 맨 위에', (t) async {
      final s = _Server()..add(1, text: '옛 의견');
      final api = await _api(s);
      await _pumpInbox(t, api);
      expect(_item(2), findsNothing);
      s.add(2, text: '새 의견', at: _now);
      await t.fling(find.byKey(const Key('inbox-list')), const Offset(0, 400), 1000);
      await t.pumpAndSettle();
      expect(_item(2), findsOneWidget);
      expect(find.text('방금'), findsOneWidget);
      expect(t.getRect(_item(2)).top, lessThan(t.getRect(_item(1)).top));
      expect(s.count('GET /feedback/inbox?limit=30'), 2);
    });

    testWidgets('첫 쪽을 못 받으면 가운데에 까닭과 「다시 시도」', (t) async {
      final s = _Server()
        ..add(1, text: '살아났어요')
        ..failInbox = 500;
      final api = await _api(s);
      await _pumpInbox(t, api);
      expect(find.byKey(const Key('inbox-error')), findsOneWidget);
      expect(find.text('서버가 잠깐 아파요'), findsOneWidget);
      await t.tap(find.byKey(const Key('inbox-retry')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('inbox-error')), findsNothing);
      expect(_item(1), findsOneWidget);
    });

    testWidgets('새로 고침이 실패하면 보던 목록은 두고 맨 위에 한 줄', (t) async {
      final s = _Server()..add(1, text: '보던 것');
      final api = await _api(s);
      await _pumpInbox(t, api);
      s.failInbox = 503;
      await t.fling(find.byKey(const Key('inbox-list')), const Offset(0, 400), 1000);
      await t.pumpAndSettle();
      expect(_item(1), findsOneWidget);
      expect(find.byKey(const Key('inbox-error')), findsOneWidget);
    });

    testWidgets('운영자가 아니면(403) 무엇을 하면 되는지 — 모두 읽음은 못 누른다', (t) async {
      final s = _Server()
        ..operator = false
        ..add(1);
      final api = await _api(s);
      await _pumpInbox(t, api);
      expect(find.text('운영자 계정으로 로그인하면 볼 수 있어요'), findsOneWidget);
      expect(_item(1), findsNothing);
      expect(t.widget<TextButton>(_readAll).onPressed, isNull);
    });

    testWidgets('모두 읽음 — 점이 다 사라지고, 받아 둔 가장 새 번호까지만', (t) async {
      final s = _Server()
        ..add(4)
        ..add(3, read: true)
        ..add(2);
      final api = await _api(s);
      await _pumpInbox(t, api);
      expect(_dot(4), findsOneWidget);
      await t.tap(_readAll);
      await t.pumpAndSettle();
      expect(_dot(4), findsNothing);
      expect(_dot(2), findsNothing);
      expect(find.byKey(const Key('inbox-unread-count')), findsNothing);
      expect(s.readAllBody, {'upTo': 4});
      expect(s.unread, 0);
      expect(t.widget<TextButton>(_readAll).onPressed, isNull);
    });

    testWidgets('모두 읽음이 실패하면 되돌리고 까닭을 알린다', (t) async {
      final s = _Server()
        ..add(2)
        ..failReadAll = 500;
      final api = await _api(s);
      await _pumpInbox(t, api);
      await t.tap(_readAll);
      await t.pumpAndSettle();
      expect(_dot(2), findsOneWidget);
      expect(find.text('못 했어요'), findsOneWidget);
    });
  });

  /* --- 상세 ------------------------------------------------------------------------- */
  group('상세', () {
    testWidgets('열면 읽음 — 글 전체(고를 수 있게) · 목록의 점과 개수도 바로', (t) async {
      final long = List.filled(20, '길게 쓴 의견입니다.').join(' ');
      final s = _Server()
        ..add(2, text: long, from: '민지', screen: '식단', at: DateTime(2026, 9, 28, 4, 12))
        ..add(1);
      final api = await _api(s);
      await _pumpInbox(t, api);
      expect(find.text('안 읽은 의견 2개'), findsOneWidget);
      await t.tap(_item(2));
      await t.pumpAndSettle();
      expect(find.byType(FeedbackDetailScreen), findsOneWidget);
      final full = t.widget<SelectableText>(find.byKey(const Key('inbox-detail-text')));
      expect(full.data, long);
      expect(find.text('민지'), findsOneWidget);
      expect(find.text('9월 28일 04:12'), findsOneWidget);
      expect(find.text('식단'), findsOneWidget);
      expect(s.calls, contains('POST /feedback/inbox/2/read'));
      expect(s.items.firstWhere((i) => i['id'] == 2)['read'], isTrue);

      await t.pageBack();
      await t.pumpAndSettle();
      expect(_dot(2), findsNothing);
      expect(_dot(1), findsOneWidget);
      expect(find.text('안 읽은 의견 1개'), findsOneWidget);
    });

    testWidgets('읽음이 서버에 못 닿으면 되돌린다', (t) async {
      final s = _Server()
        ..add(1)
        ..failRead = 500;
      final api = await _api(s);
      await _pumpInbox(t, api);
      await t.tap(_item(1));
      await t.pumpAndSettle();
      await t.pageBack();
      await t.pumpAndSettle();
      expect(_dot(1), findsOneWidget, reason: '서버는 아직 안 읽음 — 화면만 읽음이면 다음에 또 안 읽음으로 나옵니다');
    });

    testWidgets('읽은 것을 열면 읽음을 다시 보내지 않는다', (t) async {
      final s = _Server()..add(1, read: true);
      final api = await _api(s);
      await _pumpInbox(t, api);
      await t.tap(_item(1));
      await t.pumpAndSettle();
      expect(s.calls.where((c) => c.endsWith('/read')), isEmpty);
    });

    testWidgets('지우기 — 한 번 묻고, 지우면 목록에서 빠진다', (t) async {
      final s = _Server()
        ..add(2, text: '지울 것', images: 1)
        ..add(1, text: '남길 것');
      final api = await _api(s);
      await _pumpInbox(t, api);
      await t.tap(_item(2));
      await t.pumpAndSettle();

      await t.tap(find.byKey(const Key('inbox-delete')));
      await t.pumpAndSettle();
      expect(find.text('이 의견을 지울까요?'), findsOneWidget);
      await t.tap(find.byKey(const Key('inbox-delete-cancel')));
      await t.pumpAndSettle();
      expect(s.calls.where((c) => c.startsWith('DELETE')), isEmpty, reason: '취소는 아무것도 안 합니다');
      expect(find.byType(FeedbackDetailScreen), findsOneWidget);

      await t.tap(find.byKey(const Key('inbox-delete')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('inbox-delete-confirm')));
      await t.pumpAndSettle();
      expect(s.calls, contains('DELETE /feedback/inbox/2'));
      expect(find.byType(FeedbackDetailScreen), findsNothing);
      expect(find.byType(FeedbackInboxScreen), findsOneWidget);
      expect(_item(2), findsNothing);
      expect(_item(1), findsOneWidget);
      expect(find.text('지웠어요'), findsOneWidget);
      expect(api.cachedInboxImage(2, 1), isNull);
    });

    testWidgets('지우기가 실패하면 상세에 남고 까닭을 알린다', (t) async {
      final s = _Server()
        ..add(1)
        ..failDelete = 500;
      final api = await _api(s);
      await _pumpInbox(t, api);
      await t.tap(_item(1));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('inbox-delete')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('inbox-delete-confirm')));
      await t.pumpAndSettle();
      expect(find.byType(FeedbackDetailScreen), findsOneWidget);
      expect(find.text('지우지 못했어요'), findsOneWidget);
      expect(t.widget<IconButton>(find.byKey(const Key('inbox-delete'))).onPressed, isNotNull,
          reason: '다시 누를 수 있게');
    });

    testWidgets('캡처를 누르면 전체 화면 — 키울 수 있고 옆으로 넘긴다, 사진은 한 번만 받는다', (t) async {
      final s = _Server()..add(1, text: '사진 두 장', images: 2);
      final api = await _api(s);
      await _pumpInbox(t, api);
      await t.tap(_item(1));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('inbox-detail-img-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('inbox-detail-img-1')), findsOneWidget);

      await t.tap(find.byKey(const ValueKey('inbox-detail-img-0')));
      await t.pumpAndSettle();
      expect(find.byType(FeedbackImageViewer), findsOneWidget);
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(find.text('1 / 2'), findsOneWidget);
      expect(t.widget<InteractiveViewer>(find.byType(InteractiveViewer)).maxScale, greaterThan(1));

      await t.drag(find.byKey(const Key('inbox-viewer')), const Offset(-300, 0));
      await t.pumpAndSettle();
      expect(find.text('2 / 2'), findsOneWidget);

      /* 두 번 톡 — 키우면 넘기기가 멈추고(그림을 옮기게), 다시 두 번 톡이면 원래대로. */
      final page = find.byType(InteractiveViewer);
      await t.tap(page);
      await t.pump(const Duration(milliseconds: 50));
      await t.tap(page);
      await t.pumpAndSettle();
      expect(t.widget<PageView>(find.byKey(const Key('inbox-viewer'))).physics,
          isA<NeverScrollableScrollPhysics>());
      await t.tap(page);
      await t.pump(const Duration(milliseconds: 50));
      await t.tap(page);
      await t.pumpAndSettle();
      expect(t.widget<PageView>(find.byKey(const Key('inbox-viewer'))).physics, isNull);

      expect(s.count('GET /feedback/inbox/1/image/1'), 1, reason: '목록 → 상세 → 전체 화면 — 캐시에서');
      expect(s.count('GET /feedback/inbox/1/image/2'), 1);
    });
  });

  /* --- 알림 ------------------------------------------------------------------------- */
  group('알림', () {
    test('route \'feedback\' 을 따라간다 — 모르는 값은 여전히 버린다', () {
      expect(kPushRoutes, contains('feedback'));
      expect(pushRoute({'route': 'feedback', 'kind': 'feedback'}), 'feedback');
      expect(pushRoute({'route': 'feedback-admin'}), isNull);
    });

    Future<Api> shell(WidgetTester t, _Server s, {required bool signedIn}) async {
      t.view.physicalSize = const Size(1000, 2400);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      final app = await AppState.boot();
      app.store.set({
        'guest': true,
        'onboarded': true,
        'profile': {'sex': 'male', 'age': 30, 'heightCm': 175, 'activityLevel': 'moderate',
            'trainingAge': 'novice', 'daysPerWeek': 3, 'mealsPerDay': 3},
      });
      markTesterWelcomeSeen(app);
      final api = await _api(s, signedIn: signedIn);
      await t.pumpWidget(Scope(
          state: app, api: api, onServerChange: (_) async {},
          child: MaterialApp(theme: mbLight(), home: const Shell())));
      await t.pumpAndSettle();
      return api;
    }

    testWidgets('셸이 notificationRoute \'feedback\' 을 받으면 위의 화면을 닫고 의견함을 연다', (t) async {
      final s = _Server()..add(1, text: '알림으로 온 의견');
      await shell(t, s, signedIn: true);
      Navigator.of(t.element(find.byType(NavigationBar)))
          .push(MaterialPageRoute(builder: (_) => const Scaffold(body: Text('위에 뜬 화면'))));
      await t.pumpAndSettle();
      notificationRoute.value = 'feedback';
      await t.pumpAndSettle();
      expect(notificationRoute.value, isNull);
      expect(find.text('위에 뜬 화면'), findsNothing);
      expect(find.byType(FeedbackInboxScreen), findsOneWidget);
      expect(_item(1), findsOneWidget);

      /* 뒤로 가면 셸 — 의견함은 셸 위에 하나. */
      await t.pageBack();
      await t.pumpAndSettle();
      expect(find.byType(FeedbackInboxScreen), findsNothing);
      expect(find.byType(NavigationBar), findsOneWidget);
    });

    testWidgets('로그인하지 않았으면(늦게 온 한 통) 아무것도 안 연다 — 보던 화면도 안 닫는다', (t) async {
      final s = _Server()..add(1);
      await shell(t, s, signedIn: false);
      Navigator.of(t.element(find.byType(NavigationBar)))
          .push(MaterialPageRoute(builder: (_) => const Scaffold(body: Text('위에 뜬 화면'))));
      await t.pumpAndSettle();
      notificationRoute.value = 'feedback';
      await t.pumpAndSettle();
      expect(notificationRoute.value, isNull);
      expect(find.text('위에 뜬 화면'), findsOneWidget, reason: '열 것이 없으면 쓰던 화면을 닫지 않습니다');
      expect(find.byType(FeedbackInboxScreen), findsNothing);
      expect(s.calls.where((c) => c.contains('/feedback/inbox')), isEmpty);
    });

    testWidgets('운영자가 아닌 계정이면 의견함이 서버의 403 을 말로', (t) async {
      final s = _Server()
        ..operator = false
        ..add(1);
      await shell(t, s, signedIn: true);
      notificationRoute.value = 'feedback';
      await t.pumpAndSettle();
      expect(find.byType(FeedbackInboxScreen), findsOneWidget);
      expect(find.text('운영자 계정으로 로그인하면 볼 수 있어요'), findsOneWidget);
    });
  });

  /* --- 좁은 화면 --------------------------------------------------------------------- */
  group('360px · 글자 1.3배', () {
    for (final (name, theme) in [('밝게', mbLight), ('어둡게', mbDark)]) {
      testWidgets('$name — 목록 · 상세 · 전체 화면 · 지우기 확인이 넘치지 않는다', (t) async {
        t.platformDispatcher.textScaleFactorTestValue = 1.3;
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        final s = _Server()
          ..add(2,
              text: List.filled(30, '아주 긴 의견').join(' '),
              images: 3,
              from: '이름이아주아주아주아주긴친구입니다정말로',
              appVersion: '0.2.140-beta.12+30000',
              screen: '아주 긴 화면 이름 — 운동 기록 · 맨몸 운동 따라 하기',
              at: DateTime(2025, 12, 28, 23, 59))
          ..add(1, anonymous: true, platform: 'ios');
        final api = await _api(s);
        await _pumpInbox(t, api, size: const Size(360, 740), theme: theme());
        expect(t.takeException(), isNull);
        final card = t.getRect(_item(2));
        expect(card.right, lessThanOrEqualTo(360));
        for (var n = 1; n <= 3; n++) {
          expect(t.getRect(find.byKey(ValueKey('inbox-thumb-2-$n'))).right, lessThanOrEqualTo(card.right));
        }

        await t.tap(_item(2));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        await t.tap(find.byKey(const Key('inbox-delete')));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        final dialog = t.getRect(find.byType(AlertDialog));
        for (final k in ['inbox-delete-cancel', 'inbox-delete-confirm']) {
          final r = t.getRect(find.byKey(Key(k)));
          expect(r.left, greaterThanOrEqualTo(dialog.left));
          expect(r.right, lessThanOrEqualTo(dialog.right));
        }
        await t.tap(find.byKey(const Key('inbox-delete-cancel')));
        await t.pumpAndSettle();

        await t.scrollUntilVisible(find.byKey(const ValueKey('inbox-detail-img-0')), 300,
            scrollable: find.byType(Scrollable).first);
        await t.tap(find.byKey(const ValueKey('inbox-detail-img-0')));
        await t.pumpAndSettle();
        expect(find.text('1 / 3'), findsOneWidget);
        expect(t.takeException(), isNull);
      });

      testWidgets('$name — 설정의 줄과 개수가 넘치지 않는다', (t) async {
        t.platformDispatcher.textScaleFactorTestValue = 1.3;
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        t.view.physicalSize = const Size(360, 740);
        t.view.devicePixelRatio = 1.0;
        addTearDown(t.view.reset);
        final s = _Server();
        for (var i = 1; i <= 120; i++) {
          s.add(i);
        }
        final api = await _api(s);
        final app = await AppState.boot();
        await t.pumpWidget(Scope(
            state: app, api: api, onServerChange: (_) async {},
            child: MaterialApp(theme: theme(), home: const SettingsScreen())));
        await t.pumpAndSettle();
        final row = find.byKey(const Key('settings-feedback-inbox'));
        await t.scrollUntilVisible(row, 300, scrollable: find.byType(Scrollable).first);
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        expect(find.text('99+'), findsOneWidget, reason: '세 자리는 99+ — 칸이 넓어지지 않게');
        expect(t.getRect(row).right, lessThanOrEqualTo(360));
      });
    }
  });
}
