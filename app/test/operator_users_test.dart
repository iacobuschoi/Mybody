/* 「가입자 목록」 — 운영자가 앱 안에서 가입한 계정을 보는 곳(screens/user_list.dart · api.dart).
 *
 * 노트북의 reset-password.js 로만 보던 아이디 · 이름 · 가입일을 운영자 폰에서. 여기서 지키는 것:
 *
 *   · Api — 목록을 읽고(새 가입부터 · total · 본인 표시 me), 이상한 칸은 버리고, limit 은 1~1000.
 *     403 · 401 은 「운영자 계정으로 로그인하면 볼 수 있어요」, 옛 서버(404)는 missing.
 *     설정의 줄 둘이 같이 물어도 /me 는 한 번(askOperator).
 *   · 설정 — 운영자에게만 「의견함」 바로 아래 「가입자 목록」 줄과 수. 다른 사람 · 로그인 안 한 사람에게는
 *     줄이 없고 그 길을 부르지도 않습니다. 줄은 그 길이 답한 뒤에 섭니다 — 403 · 404(옛 서버)면
 *     기다리는 동안에도 끝나서도 없고, 못 닿음 · 5xx 면 섭니다. 받은 답은 Api 가 기억해서 다음에
 *     열 때는 기다리지 않습니다(operatorUsersSeen).
 *   · 화면 — 「가입자 N명」, 이름(굵게) · 아이디 · 가입일(2026.09.28), 내 줄에 「나」. 누르면 아이디가
 *     클립보드로 가고 「아이디를 복사했어요」. 받는 중 · 실패(다시 시도) · 빈 목록 · 1000명 넘음 ·
 *     끌어 내려 새로 · 옛 서버(404)면 다시 시도 없이 한 줄.
 *   · 360px · 글자 1.3배 · 밝게/어둡게 — 넘치지 않습니다. */
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mybody/src/api.dart';
import 'package:mybody/src/app_state.dart';
import 'package:mybody/src/scope.dart';
import 'package:mybody/src/screens/settings.dart';
import 'package:mybody/src/screens/user_list.dart';
import 'package:mybody/src/theme.dart';
import 'package:mybody/src/ui/widgets.dart';

http.Response _json(Object body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status,
        headers: {'content-type': 'application/json; charset=utf-8'});

/// 서버 흉내 — server.js handleOperator 의 약속대로.
class _Server {
  bool operator = true;

  /// 이 길이 없는 옛 서버 — 404.
  bool missing = false;

  /// 새 가입부터.
  final users = <Map<String, dynamic>>[];

  /// 잘리기 전 전체 수. null 이면 users 의 길이.
  int? total;
  final calls = <String>[];

  /// 다음 목록 요청 하나를 이 상태로 실패시킵니다.
  int? failNext;

  /// 있으면 /operator 요청이 이게 풀릴 때까지 답하지 않습니다(받는 중 — 404 · 403 도).
  Completer<void>? gate;

  void add(String handle, {String? name, DateTime? at, bool me = false}) {
    users.add({
      'handle': handle,
      'displayName': name ?? '$handle 이름',
      'createdAt': (at ?? DateTime(2026, 9, 28, 12)).toUtc().toIso8601String(),
      if (me) 'me': true,
    });
  }

  int count(String prefix) => calls.where((c) => c.startsWith(prefix)).length;

  MockClient get client => MockClient((req) async {
        final path = req.url.path.replaceFirst('/api', '');
        final q = req.url.query;
        calls.add('${req.method} $path${q.isEmpty ? '' : '?$q'}');
        if (path == '/me') {
          return _json({'ok': true, 'user': {'id': 'u1', 'displayName': '주인', if (operator) 'isOperator': true}});
        }
        if (path.startsWith('/feedback/inbox')) {
          if (!operator) return _json({'ok': false, 'error': '운영자만 볼 수 있어요'}, 403);
          return _json({'ok': true, 'unread': 0, 'items': [], 'nextBefore': null});
        }
        if (!path.startsWith('/operator')) return _json({'ok': true});
        if (gate case final g?) await g.future;
        if (missing) return _json({'ok': false, 'reason': '그런 경로가 없습니다'}, 404);
        if (req.headers['authorization'] == null) return _json({'ok': false, 'reason': '로그인이 필요합니다'}, 401);
        if (!operator) return _json({'ok': false, 'error': '운영자만 볼 수 있어요', 'reason': '운영자만 볼 수 있어요'}, 403);
        if (path == '/operator/users' && req.method == 'GET') {
          if (failNext case final st?) {
            failNext = null;
            return _json({'ok': false, 'error': '서버가 잠깐 아파요'}, st);
          }
          final limit = int.tryParse(req.url.queryParameters['limit'] ?? '') ?? 1000;
          return _json({'ok': true, 'total': total ?? users.length, 'users': users.take(limit).toList()});
        }
        return _json({'ok': false, 'error': '그런 경로가 없습니다'}, 404);
      });
}

Future<Api> _api(_Server s, {bool signedIn = true}) async {
  final api = Api(baseUrl: 'https://x.test', client: s.client);
  if (signedIn) await api.setToken('tok');
  return api;
}

/// 클립보드 흉내 — 넣은 글을 들고 있습니다.
ValueNotifier<String?> _clipboard(WidgetTester t) {
  final clip = ValueNotifier<String?>(null);
  final m = t.binding.defaultBinaryMessenger;
  m.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'Clipboard.setData') clip.value = (call.arguments as Map)['text'] as String?;
    if (call.method == 'Clipboard.getData') return {'text': clip.value};
    return null;
  });
  addTearDown(() => m.setMockMethodCallHandler(SystemChannels.platform, null));
  return clip;
}

/// 첫 화면 위에 가입자 목록을 밀어 올린 상태 — 앱에서처럼(뒤로 가기가 있게).
Future<void> _pumpUsers(WidgetTester t, Api api,
    {Size size = const Size(420, 900), ThemeData? theme, bool settle = true}) async {
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
                  onPressed: () =>
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OperatorUsersScreen())),
                  child: const Text('첫 화면'),
                )),
              )),
    ),
  ));
  await t.tap(find.text('첫 화면'));
  if (settle) {
    await t.pumpAndSettle();
  } else {
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
  }
}

Finder _row(String handle) => find.byKey(ValueKey('users-row-$handle'));
final _count = find.byKey(const Key('users-count'));
final _me = find.byKey(const Key('users-me'));

_Server _three() => _Server()
  ..add('newbie', name: '새친구', at: DateTime(2026, 9, 28, 9, 30))
  ..add('owner', name: '주인', at: DateTime(2026, 9, 1, 8), me: true)
  ..add('oldie', name: '옛친구', at: DateTime(2025, 12, 31, 23, 50));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  /* --- 가입일 ----------------------------------------------------------------------- */
  test('가입일은 이 폰의 날짜로 「2026.09.28」 — 한 자리 달 · 날은 0 을 붙여', () {
    expect(userJoinedLabel(DateTime(2026, 9, 28, 23, 59)), '2026.09.28');
    expect(userJoinedLabel(DateTime(2025, 1, 2)), '2025.01.02');
    final utc = DateTime.utc(2026, 3, 4, 12);
    expect(userJoinedLabel(utc), userJoinedLabel(utc.toLocal()), reason: '서버의 UTC 시각은 이 폰의 날짜로');
  });

  /* --- Api -------------------------------------------------------------------------- */
  group('Api', () {
    test('목록을 읽는다 — 새 가입부터 · 이름 · 아이디 · 가입 시각 · 본인 표시 · 전체 수', () async {
      final s = _three()..total = 1203;
      final api = await _api(s);
      final p = await api.fetchOperatorUsers();
      expect(s.calls.last, 'GET /operator/users');
      expect(p.ok, isTrue);
      expect([for (final u in p.users) u.handle], ['newbie', 'owner', 'oldie']);
      expect(p.total, 1203, reason: '잘리기 전 전체 수');
      final a = p.users.first;
      expect(a.displayName, '새친구');
      expect(a.createdAt, DateTime(2026, 9, 28, 9, 30), reason: '이 폰의 시각으로');
      expect(a.me, isFalse);
      expect(p.users[1].me, isTrue);
      expect(p.users.where((u) => u.me), hasLength(1));
    });

    test('limit 은 1~1000 으로 자르고, 안 주면 붙이지 않는다(서버 기본 1000)', () async {
      final s = _three();
      final api = await _api(s);
      await api.fetchOperatorUsers(limit: 0);
      expect(s.calls.last, 'GET /operator/users?limit=1');
      await api.fetchOperatorUsers(limit: 5000);
      expect(s.calls.last, 'GET /operator/users?limit=1000');
      await api.fetchOperatorUsers();
      expect(s.calls.last, 'GET /operator/users');
    });

    test('이상한 칸은 버리거나 비운다 — 아이디 없는 칸 · 모르는 모양 · 전체 수가 목록보다 작음', () {
      final p = OperatorUsersPage.from(const ApiResult(200, {
        'ok': true,
        'total': 1,
        'users': [
          {'displayName': '아이디 없음'},
          'nonsense',
          {'handle': ' ', 'displayName': '빈 아이디'},
          {'handle': 'kim', 'displayName': null, 'createdAt': '엉망', 'me': 'true'},
          {'handle': 'lee', 'displayName': ' 이 ', 'createdAt': '2026-09-28T03:00:00.000Z'},
        ],
      }));
      expect([for (final u in p.users) u.handle], ['kim', 'lee']);
      expect(p.users.first.displayName, '');
      expect(p.users.first.createdAt, isNull);
      expect(p.users.first.me, isFalse, reason: '참/거짓만 — 글자 "true" 는 아님');
      expect(p.users.last.displayName, '이');
      expect(p.total, 2, reason: '받은 사람보다 적은 전체 수는 믿지 않습니다');
      expect(OperatorUsersPage.from(const ApiResult(200, {'ok': true, 'users': []})).total, 0);
    });

    test('운영자가 아니면(403) · 로그인이 없으면(401) 무엇을 하면 되는지로, 옛 서버(404)는 missing', () async {
      final s = _three()..operator = false;
      final p = await (await _api(s)).fetchOperatorUsers();
      expect(p.denied, isTrue);
      expect(p.missing, isFalse);
      expect(p.reason, '운영자 계정으로 로그인하면 볼 수 있어요');
      final out = await (await _api(s, signedIn: false)).fetchOperatorUsers();
      expect(out.denied, isTrue);
      expect(out.reason, '운영자 계정으로 로그인하면 볼 수 있어요');
      final old = await (await _api(_three()..missing = true)).fetchOperatorUsers();
      expect(old.missing, isTrue);
      expect(old.denied, isFalse);
      final down = OperatorUsersPage.from(const ApiResult(0, {}));
      expect(down.reason, contains('서버에 닿지 못했습니다'));
      final sick = OperatorUsersPage.from(const ApiResult(500, {'ok': false, 'error': '서버가 잠깐 아파요'}));
      expect(sick.reason, '서버가 잠깐 아파요');
    });

    test('operatorUsersSeen — 열림과 수 · 403/404 는 닫힘 · 5xx 는 앞 답 그대로 · 로그인이 바뀌면 비움', () async {
      final s = _three();
      final api = await _api(s);
      expect(api.operatorUsersSeen, isNull);
      await api.fetchOperatorUsers(limit: 1);
      expect(api.operatorUsersSeen, (open: true, total: 3));
      s.failNext = 500;
      await api.fetchOperatorUsers(limit: 1);
      expect(api.operatorUsersSeen, (open: true, total: 3), reason: '길이 있는지 말해 주지 않는 실패');
      s.missing = true;
      await api.fetchOperatorUsers(limit: 1);
      expect(api.operatorUsersSeen, (open: false, total: 0));

      await api.setToken('other');
      expect(api.operatorUsersSeen, isNull, reason: '앞 계정의 답');
      s
        ..missing = false
        ..operator = false;
      await api.fetchOperatorUsers();
      expect(api.operatorUsersSeen?.open, isFalse);

      /* 기다리는 사이 로그인이 바뀌면 앞 계정의 답은 적지 않습니다. */
      s
        ..operator = true
        ..gate = Completer<void>();
      await api.setToken('third');
      final going = api.fetchOperatorUsers(limit: 1);
      await api.setToken('fourth');
      s.gate!.complete();
      expect((await going).ok, isTrue);
      expect(api.operatorUsersSeen, isNull);
      await api.setToken(null);
      expect(api.operatorUsersSeen, isNull);
    });

    test('askOperator — 모르면 /me 를 한 번만(같이 불러도), 알면 묻지 않고, 로그인이 바뀌면 다시', () async {
      final s = _three();
      final api = await _api(s);
      final both = await Future.wait([api.askOperator(), api.askOperator()]);
      expect(both, [true, true]);
      expect(s.count('GET /me'), 1, reason: '줄 둘이 같이 물어도 한 번');
      expect(await api.askOperator(), isTrue);
      expect(s.count('GET /me'), 1, reason: '이미 알면 묻지 않습니다');
      s.operator = false;
      await api.setToken('other');
      expect(await api.askOperator(), isFalse);
      expect(s.count('GET /me'), 2);
      await api.setToken(null);
      expect(await api.askOperator(), isFalse, reason: '로그인 안 했으면 묻지 않고 거짓');
      expect(s.count('GET /me'), 2);
    });
  });

  /* --- 설정의 줄 ------------------------------------------------------------------- */
  group('설정의 「가입자 목록」 줄', () {
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

    final row = find.byKey(const Key('settings-operator-users'));
    final inboxRow = find.byKey(const Key('settings-feedback-inbox'));
    final total = find.byKey(const Key('settings-operator-users-count'));

    testWidgets('운영자면 「의견함」 바로 아래 줄과 수, 누르면 가입자 목록 — /me 는 한 번만', (t) async {
      final s = _three();
      final api = await _api(s);
      await openSettings(t, api);
      expect(row, findsOneWidget);
      expect(find.descendant(of: row, matching: find.text('가입자 목록')), findsOneWidget);
      expect(find.descendant(of: total, matching: find.text('3명'), matchRoot: true), findsOneWidget);
      expect(s.calls, contains('GET /operator/users?limit=1'), reason: '수만 — 한 명만 받습니다');
      expect(s.count('GET /me'), 1, reason: '의견함 줄과 같은 물음');

      /* 자리 — 도움말 카드 안, 「의견함」 바로 아래 · 말풍선 스위치보다 위. */
      final help = find.ancestor(of: find.text('도움말'), matching: find.byType(MbCard));
      expect(find.descendant(of: help, matching: row), findsOneWidget);
      expect(t.getRect(row).top, greaterThanOrEqualTo(t.getRect(inboxRow).bottom - 0.01));
      expect(t.getRect(row).top - t.getRect(inboxRow).bottom, lessThan(1), reason: '사이에 다른 것 없이');
      expect(t.getRect(row).bottom,
          lessThanOrEqualTo(t.getRect(find.byKey(const Key('settings-feedback-bubble'))).top + 0.01));

      await t.tap(row);
      await t.pumpAndSettle();
      expect(find.byType(OperatorUsersScreen), findsOneWidget);
      expect(find.widgetWithText(AppBar, '가입자 목록'), findsOneWidget, reason: '줄 이름과 같은 제목');

      /* 돌아오면 수를 다시 — 그사이 한 명이 가입했습니다. */
      s.users.insert(0, {'handle': 'fresh', 'displayName': '막 가입', 'createdAt': '2026-09-28T04:00:00.000Z'});
      await t.pageBack();
      await t.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(find.descendant(of: total, matching: find.text('4명'), matchRoot: true), findsOneWidget);
    });

    testWidgets('운영자가 아니면 줄이 없고 가입자 길도 안 부른다', (t) async {
      final s = _three()..operator = false;
      final api = await _api(s);
      await openSettings(t, api);
      expect(row, findsNothing);
      expect(find.text('가입자 목록'), findsNothing, reason: '자리표시도 없이');
      expect(s.count('GET /me'), 1);
      expect(s.calls.where((c) => c.contains('/operator')), isEmpty);
    });

    testWidgets('로그인하지 않았으면 줄이 없고 /me 도 안 묻는다', (t) async {
      final s = _three();
      final api = await _api(s, signedIn: false);
      await openSettings(t, api);
      expect(row, findsNothing);
      expect(s.calls.where((c) => c == 'GET /me' || c.contains('/operator')), isEmpty);
    });

    testWidgets('/me 는 참인데 가입자 길이 403 이면(설정이 바뀐 직후) 줄을 거둔다', (t) async {
      final s = _three();
      final api = await _api(s);
      await api.me();
      s.operator = false;
      await openSettings(t, api);
      expect(row, findsNothing);
    });

    testWidgets('이 길이 없는 옛 서버(404)면 줄을 거둔다 — 의견함 줄은 그대로', (t) async {
      final s = _three()..missing = true;
      final api = await _api(s);
      await openSettings(t, api);
      expect(row, findsNothing);
      expect(inboxRow, findsOneWidget);
    });

    /* 앱이 서버보다 먼저 새 판일 때 — /me 는 운영자라고 하는데 이 길은 아직 없음. 답을 기다리는 동안
       줄이 섰다가 404 에 사라지면 아래 스위치 · 버튼이 튀고, 그 틈에 누르면 빈 화면으로 갑니다. */
    testWidgets('옛 서버(404) — 답을 기다리는 동안에도 줄이 서지 않고, 다음에 열 때도', (t) async {
      final s = _three()
        ..missing = true
        ..gate = Completer<void>();
      final api = await _api(s);
      await api.me();
      await openSettings(t, api);
      expect(s.calls, contains('GET /operator/users?limit=1'));
      expect(inboxRow, findsOneWidget);
      expect(row, findsNothing, reason: '답이 오기 전');
      final below = t.getRect(find.byKey(const Key('settings-feedback-bubble'))).top;
      s.gate!.complete();
      await t.pumpAndSettle();
      expect(row, findsNothing);
      expect(t.getRect(find.byKey(const Key('settings-feedback-bubble'))).top, below, reason: '아래가 튀지 않음');

      /* 다시 열면 — 기억한 404 대로 기다리는 동안에도 없음. */
      await t.pageBack();
      await t.pumpAndSettle();
      s.gate = Completer<void>();
      await t.tap(find.text('첫 화면'));
      await t.pumpAndSettle();
      expect(inboxRow, findsOneWidget);
      expect(row, findsNothing);
      s.gate!.complete();
      await t.pumpAndSettle();
      expect(row, findsNothing);
    });

    testWidgets('새 서버 — 줄은 답이 온 뒤에 서고, 다음에 열 때는 기억한 수와 함께 곧바로', (t) async {
      final s = _three()..gate = Completer<void>();
      final api = await _api(s);
      await api.me();
      await openSettings(t, api);
      expect(row, findsNothing, reason: '답이 오기 전');
      s.gate!.complete();
      await t.pumpAndSettle();
      expect(row, findsOneWidget);
      expect(find.descendant(of: total, matching: find.text('3명'), matchRoot: true), findsOneWidget);

      await t.pageBack();
      await t.pumpAndSettle();
      s.gate = Completer<void>();
      await t.tap(find.text('첫 화면'));
      await t.pumpAndSettle();
      expect(row, findsOneWidget, reason: '한 번 열렸던 길 — 기다리지 않음');
      expect(find.descendant(of: total, matching: find.text('3명'), matchRoot: true), findsOneWidget);
      s.users.insert(0, {'handle': 'fresh', 'displayName': '막 가입', 'createdAt': '2026-09-28T04:00:00.000Z'});
      s.gate!.complete();
      await t.pumpAndSettle();
      expect(find.descendant(of: total, matching: find.text('4명'), matchRoot: true), findsOneWidget);
    });

    testWidgets('처음 물음이 5xx 면(길이 있는지 모름) 줄을 세운다 — 들어가서 받는다', (t) async {
      final s = _three()..failNext = 503;
      final api = await _api(s);
      await openSettings(t, api);
      expect(row, findsOneWidget);
      expect(total, findsNothing, reason: '수는 모름');
      await t.tap(row);
      await t.pumpAndSettle();
      expect(_row('newbie'), findsOneWidget);
    });
  });

  /* --- 화면 ------------------------------------------------------------------------- */
  group('목록', () {
    testWidgets('「가입자 N명」 · 새 가입부터 이름(굵게) · 아이디 · 가입일 · 내 줄에만 「나」', (t) async {
      final s = _three();
      await _pumpUsers(t, await _api(s));
      expect(find.descendant(of: _count, matching: find.text('가입자 3명'), matchRoot: true), findsOneWidget);
      expect(find.byKey(const Key('users-capped')), findsNothing);
      final tops = [for (final h in ['newbie', 'owner', 'oldie']) t.getRect(_row(h)).top];
      expect(tops, orderedEquals([...tops]..sort()), reason: '서버가 준 차례(새 가입부터) 그대로');

      final name = t.widget<Text>(find.descendant(of: _row('newbie'), matching: find.text('새친구')));
      expect(name.style?.fontWeight, FontWeight.w700);
      expect(find.descendant(of: _row('newbie'), matching: find.text('newbie')), findsOneWidget);
      expect(find.descendant(of: _row('newbie'), matching: find.text('2026.09.28')), findsOneWidget);
      expect(find.descendant(of: _row('oldie'), matching: find.text('2025.12.31')), findsOneWidget);

      expect(_me, findsOneWidget);
      expect(find.descendant(of: _row('owner'), matching: _me), findsOneWidget);
      expect(find.descendant(of: _row('owner'), matching: find.text('나')), findsOneWidget);
    });

    testWidgets('줄을 누르면 아이디가 클립보드로 — 「아이디를 복사했어요」', (t) async {
      final clip = _clipboard(t);
      final s = _three();
      await _pumpUsers(t, await _api(s));
      await t.tap(_row('oldie'));
      await t.pump();
      expect(clip.value, 'oldie', reason: 'reset-password.js <아이디> 에 붙여 넣을 값 그대로');
      expect(find.widgetWithText(SnackBar, '아이디를 복사했어요'), findsOneWidget);
      await t.pumpAndSettle();

      await t.tap(_row('owner'));
      await t.pump();
      expect(clip.value, 'owner');
      expect(find.byType(SnackBar), findsOneWidget, reason: '앞 알림은 거두고 하나만');
      await t.pumpAndSettle();
    });

    testWidgets('받는 동안은 도는 원, 받으면 목록', (t) async {
      final s = _three()..gate = Completer<void>();
      await _pumpUsers(t, await _api(s), settle: false);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(_count, findsNothing);
      s.gate!.complete();
      await t.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(_row('newbie'), findsOneWidget);
    });

    testWidgets('처음에 못 받으면 가운데에 까닭과 「다시 시도」 — 누르면 받는다', (t) async {
      final s = _three()..failNext = 500;
      await _pumpUsers(t, await _api(s));
      expect(find.byKey(const Key('users-error')), findsOneWidget);
      expect(find.text('서버가 잠깐 아파요'), findsOneWidget);
      expect(_row('newbie'), findsNothing);
      await t.tap(find.byKey(const Key('users-retry')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('users-error')), findsNothing);
      expect(_row('newbie'), findsOneWidget);
    });

    testWidgets('서버에 못 닿으면 그 말로', (t) async {
      final api = Api(baseUrl: 'https://x.test', client: MockClient((_) async => throw Exception('끊김')));
      await api.setToken('tok');
      await _pumpUsers(t, api);
      expect(find.textContaining('서버에 닿지 못했습니다'), findsOneWidget);
      expect(find.byKey(const Key('users-retry')), findsOneWidget);
    });

    testWidgets('끌어 내리면 새로 받는다 — 새 가입이 맨 위에', (t) async {
      final s = _three();
      await _pumpUsers(t, await _api(s));
      s.users.insert(0, {'handle': 'fresh', 'displayName': '막 가입', 'createdAt': '2026-09-28T04:00:00.000Z'});
      await t.fling(find.byKey(const Key('users-list')), const Offset(0, 400), 1200);
      await t.pumpAndSettle();
      expect(s.count('GET /operator/users'), 2);
      expect(find.text('가입자 4명'), findsOneWidget);
      expect(t.getRect(_row('fresh')).top, lessThan(t.getRect(_row('newbie')).top));
    });

    testWidgets('새로 고침이 실패하면 보던 목록은 두고 맨 위에 한 줄', (t) async {
      final s = _three();
      await _pumpUsers(t, await _api(s));
      s.failNext = 503;
      await t.fling(find.byKey(const Key('users-list')), const Offset(0, 400), 1200);
      await t.pumpAndSettle();
      expect(find.byKey(const Key('users-error')), findsOneWidget);
      expect(_row('newbie'), findsOneWidget);
      expect(t.getRect(find.byKey(const Key('users-error'))).top, lessThan(t.getRect(_count).top));
    });

    testWidgets('운영자가 아니면(403) 무엇을 하면 되는지', (t) async {
      final s = _three()..operator = false;
      await _pumpUsers(t, await _api(s));
      expect(find.byKey(const Key('users-denied')), findsOneWidget);
      expect(find.text('운영자 계정으로 로그인하면 볼 수 있어요'), findsOneWidget);
      expect(_count, findsNothing);
    });

    testWidgets('이 길이 없는 옛 서버(404)면 다시 시도 없이 무엇을 하면 되는지', (t) async {
      final s = _three()..missing = true;
      await _pumpUsers(t, await _api(s));
      expect(find.byKey(const Key('users-missing')), findsOneWidget);
      expect(find.text('서버를 새 판으로 올리면 볼 수 있어요'), findsOneWidget);
      expect(find.byKey(const Key('users-retry')), findsNothing);
      expect(find.text('그런 경로가 없습니다'), findsNothing);
    });

    testWidgets('비었으면 「아직 가입자가 없어요」', (t) async {
      final s = _Server();
      await _pumpUsers(t, await _api(s));
      expect(find.byKey(const Key('users-empty')), findsOneWidget);
      expect(find.text('가입자 0명'), findsOneWidget);
    });

    testWidgets('1000명보다 많으면 전체 수와 「최근 N명만 보여요」', (t) async {
      final s = _three()..total = 1203;
      await _pumpUsers(t, await _api(s));
      expect(find.text('가입자 1203명'), findsOneWidget);
      expect(
          find.descendant(
              of: find.byKey(const Key('users-capped')), matching: find.text('최근 3명만 보여요'), matchRoot: true),
          findsOneWidget);
    });
  });

  /* --- 좁은 화면 --------------------------------------------------------------------- */
  group('360px · 글자 1.3배', () {
    for (final (name, theme) in [('밝게', mbLight), ('어둡게', mbDark)]) {
      testWidgets('$name — 긴 이름 · 긴 아이디 · 「나」 · 가입일이 넘치지 않는다', (t) async {
        t.platformDispatcher.textScaleFactorTestValue = 1.3;
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        final s = _Server()
          ..add('a.very-long_handle.for-testing32', name: '이름이아주아주긴친구입니다정말로요', me: true,
              at: DateTime(2026, 12, 31, 23, 59))
          ..add('kim', name: '')
          ..total = 5000;
        await _pumpUsers(t, await _api(s), size: const Size(360, 740), theme: theme());
        expect(t.takeException(), isNull);
        final r = t.getRect(_row('a.very-long_handle.for-testing32'));
        expect(r.right, lessThanOrEqualTo(360));
        expect(t.getRect(_me).right, lessThanOrEqualTo(r.right));
        expect(find.text('이름 없음'), findsOneWidget, reason: '이름이 비면 빈 줄이 아니라 「이름 없음」');
        expect(find.text('2026.12.31'), findsOneWidget);
      });

      testWidgets('$name — 설정의 줄과 수가 넘치지 않는다', (t) async {
        t.platformDispatcher.textScaleFactorTestValue = 1.3;
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        t.view.physicalSize = const Size(360, 740);
        t.view.devicePixelRatio = 1.0;
        addTearDown(t.view.reset);
        final s = _three()..total = 12345;
        final api = await _api(s);
        final app = await AppState.boot();
        await t.pumpWidget(Scope(
            state: app, api: api, onServerChange: (_) async {},
            child: MaterialApp(theme: theme(), home: const SettingsScreen())));
        await t.pumpAndSettle();
        final row = find.byKey(const Key('settings-operator-users'));
        await t.scrollUntilVisible(row, 300, scrollable: find.byType(Scrollable).first);
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        expect(find.text('12345명'), findsOneWidget);
        expect(t.getRect(row).right, lessThanOrEqualTo(360));
      });
    }
  });
}
