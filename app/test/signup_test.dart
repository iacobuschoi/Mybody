/* 가입과 비밀번호 복구.
 *
 * 예전에는 **로그인만** 있었습니다. 기존 친구들은 웹에서 만든 계정이 있어
 * 티가 안 났고, 그래서 오래 안 보였습니다. 새로 들어오는 친구는 계정을
 * 만들 길이 없었고, 비밀번호를 잊은 사람은 화면이 "복구 코드가 필요합니다"
 * 라고 말하는 걸 읽고도 넣을 데가 없었습니다. */
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mybody/src/api.dart';
import 'package:mybody/src/screens/account.dart';
import 'package:mybody/src/theme.dart';

MockClient fake(Map<String, Object> routes, {List<String>? seen, Map<String, Object?>? sentTo}) {
  http.Response json(Object body, int status) => http.Response.bytes(
        utf8.encode(jsonEncode(body)), status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
  return MockClient((req) async {
    final key = req.url.path.replaceFirst('/api', '');
    seen?.add('${req.method} $key');
    if (sentTo != null && req.body.isNotEmpty) {
      try { sentTo.addAll(jsonDecode(req.body) as Map<String, Object?>); } catch (_) {}
    }
    final v = routes[key];
    if (v == null) return json({'ok': false, 'reason': '없는 길'}, 404);
    return json(v, 200);
  });
}

Widget wrap(Widget child) => MaterialApp(theme: mbLight(), home: child);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  /* 시험 화면을 **길게** 잡습니다.
   *
   * 가입 화면은 동의 상자 때문에 폰 한 화면보다 깁니다. 기본 시험 화면
   * (600px)에서는 버튼이 밖으로 나가는데, ListView 는 화면 밖 자식을 아예
   * 만들지 않아서 finder 가 못 찾습니다. 스크롤을 흉내 내면 시험이 무엇을
   * 보는지보다 어떻게 굴리는지가 길어집니다 — 화면을 늘려서 전부 세웁니다. */
  setUp(() {
    final v = TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher.views.first;
    v.physicalSize = const Size(1000, 3000);
    v.devicePixelRatio = 1.0;
    addTearDown(() { v.resetPhysicalSize(); v.resetDevicePixelRatio(); });
  });

  Future<void> open(WidgetTester t, Api api, {VoidCallback? onDone}) async {
    await t.pumpWidget(wrap(SignInScreen(
        api: api, onDone: onDone ?? () {}, onServerChange: (_) async {})));
    await t.pumpAndSettle();
  }

  testWidgets('계정을 만들 길이 화면에 있다', (t) async {
    await open(t, Api(baseUrl: 'https://x.test', client: fake({'/health': {'ok': true}})));
    expect(find.text('처음이에요'), findsOneWidget);
    expect(find.text('비밀번호 잊음'), findsOneWidget);
  });

  testWidgets('서버가 가입 코드를 요구하면 그 칸이 나온다', (t) async {
    await open(t, Api(baseUrl: 'https://x.test',
        client: fake({'/health': {'ok': true, 'openSignup': false}})));
    await t.tap(find.text('처음이에요'));
    await t.pumpAndSettle();
    expect(find.widgetWithText(TextField, '가입 코드'), findsOneWidget);
  });

  testWidgets('아무나 받는 서버면 가입 코드를 안 묻는다', (t) async {
    /* 모르는 빈 칸 하나가 "나는 이걸 모르는데" 를 만듭니다. */
    await open(t, Api(baseUrl: 'https://x.test',
        client: fake({'/health': {'ok': true, 'openSignup': true}})));
    await t.tap(find.text('처음이에요'));
    await t.pumpAndSettle();
    expect(find.widgetWithText(TextField, '가입 코드'), findsNothing);
  });

  testWidgets('동의 없이는 계정을 안 만든다', (t) async {
    final seen = <String>[];
    await open(t, Api(baseUrl: 'https://x.test',
        client: fake({'/health': {'ok': true, 'openSignup': true}}, seen: seen)));
    await t.tap(find.text('처음이에요'));
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextField, '아이디'), 'chulsoo');
    await t.tap(find.text('계정 만들기'));
    await t.pumpAndSettle();
    expect(find.textContaining('동의해야'), findsOneWidget);
    expect(seen.where((s) => s.contains('signup')), isEmpty,
        reason: '동의를 안 받고 서버로 보내면 안 됩니다');
  });

  testWidgets('가입하면 서버가 받는 판 번호를 그대로 보낸다', (t) async {
    /* 서버는 글자까지 같은 값만 받습니다 (db.js 의 HEALTH_CONSENT_VERSION).
       다르면 가입이 400 으로 거부되는데, 화면에는 이유가 안 보입니다. */
    final sent = <String, Object?>{};
    await open(t, Api(baseUrl: 'https://x.test', client: fake({
      '/health': {'ok': true, 'openSignup': true},
      '/auth/signup': {'ok': true, 'token': 'tok', 'recoveryCode': 'ABCD-1234'},
    }, sentTo: sent)));
    await t.tap(find.text('처음이에요'));
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextField, '아이디'), 'chulsoo');
    await t.enterText(find.widgetWithText(TextField, '비밀번호'), 'pw12345678');
    await t.tap(find.text('동의합니다'));
    await t.pumpAndSettle();
    await t.tap(find.text('계정 만들기'));
    await t.pumpAndSettle();
    expect(sent['healthConsent'], kHealthConsentVersion);
    expect(sent['handle'], 'chulsoo');
  });

  testWidgets('복구 코드를 한 번 보여 준다', (t) async {
    /* 서버는 해시만 들고 있어서 다시 꺼내 줄 수 없습니다. 여기서 안 보여
       주면 비밀번호를 잊었을 때 길이 없습니다. */
    await open(t, Api(baseUrl: 'https://x.test', client: fake({
      '/health': {'ok': true, 'openSignup': true},
      '/auth/signup': {'ok': true, 'token': 'tok', 'recoveryCode': 'ABCD-1234'},
    })));
    await t.tap(find.text('처음이에요'));
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextField, '아이디'), 'chulsoo');
    await t.enterText(find.widgetWithText(TextField, '비밀번호'), 'pw12345678');
    await t.tap(find.text('동의합니다'));
    await t.pumpAndSettle();
    await t.tap(find.text('계정 만들기'));
    await t.pumpAndSettle();
    expect(find.text('ABCD-1234'), findsOneWidget);
    expect(find.textContaining('다시 보여 드릴 수 없습니다'), findsOneWidget);
  });

  testWidgets('비밀번호 잊음이 실제로 서버로 간다', (t) async {
    final seen = <String>[];
    final sent = <String, Object?>{};
    var done = false;
    await open(t, Api(baseUrl: 'https://x.test', client: fake({
      '/health': {'ok': true},
      '/auth/recover': {'ok': true, 'token': 'tok'},
    }, seen: seen, sentTo: sent)), onDone: () { done = true; });
    await t.tap(find.text('비밀번호 잊음'));
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextField, '아이디'), 'chulsoo');
    await t.enterText(find.widgetWithText(TextField, '복구 코드'), 'ABCD-1234');
    await t.enterText(find.widgetWithText(TextField, '새 비밀번호'), 'newpw12345');
    await t.tap(find.widgetWithText(FilledButton, '비밀번호 바꾸기'));
    await t.pumpAndSettle();
    expect(seen, contains('POST /auth/recover'));
    expect(sent['code'], 'ABCD-1234');
    expect(done, isTrue);
  });

  testWidgets('로그인은 그대로 된다', (t) async {
    var done = false;
    await open(t, Api(baseUrl: 'https://x.test', client: fake({
      '/health': {'ok': true},
      '/auth/signin': {'ok': true, 'token': 'tok'},
    })), onDone: () { done = true; });
    await t.enterText(find.widgetWithText(TextField, '아이디'), 'chulsoo');
    await t.enterText(find.widgetWithText(TextField, '비밀번호'), 'right');
    await t.tap(find.widgetWithText(FilledButton, '로그인'));
    await t.pumpAndSettle();
    expect(done, isTrue);
  });

  /* --- 옛 판으로 동의한 계정에 다시 묻기 -------------------------------------
   * 판을 올려도 서버가 확인하는 곳은 가입뿐이라, 이미 가입한 사람은 옛 문구
   * ("주간 요약만 올라간다 · 로그인 없이 써도 된다")에 동의한 채로 기록
   * 사본이 계속 올라갔습니다. */
  group('다시 묻기', () {
    const old = '2026-09-22';

    test('서버가 현재 판을 알려 주고 내 판이 옛 판일 때만 묻는다', () {
      expect(needsReconsent({'healthConsentVersion': old,
          'healthConsentCurrent': kHealthConsentVersion}), isTrue);
      expect(needsReconsent({'healthConsentVersion': kHealthConsentVersion,
          'healthConsentCurrent': kHealthConsentVersion}), isFalse);
      /* 옛 서버 — 현재 판을 안 알려 줍니다. 물으면 보낼 곳이 없습니다. */
      expect(needsReconsent({'healthConsentVersion': old}), isFalse);
      /* 서버가 이 앱보다 새 판 — 이 앱에는 그 문구가 없습니다. */
      expect(needsReconsent({'healthConsentVersion': old,
          'healthConsentCurrent': '2099-01-01'}), isFalse);
      expect(needsReconsent(null), isFalse);
    });

    Future<Api> signedIn(http.Client c) async {
      final api = Api(baseUrl: 'https://x.test', client: c);
      await api.setToken('tok');
      return api;
    }

    Map<String, Object> me(String? v, {bool current = true}) => {
      'ok': true,
      'user': {
        'healthConsentVersion': v,
        if (current) 'healthConsentCurrent': kHealthConsentVersion,
      },
    };

    testWidgets('옛 판이면 새 문구를 보여 주고, 동의하면 새 판을 보내고 앱으로 간다', (t) async {
      final seen = <String>[];
      final sent = <String, Object?>{};
      final api = await signedIn(fake({
        '/me': me(old),
        '/me/consent': me(kHealthConsentVersion),
      }, seen: seen, sentTo: sent));
      await t.pumpWidget(wrap(ConsentGate(api: api, child: const Text('앱 본체'))));
      await t.pumpAndSettle();

      expect(find.text('동의 문구가 바뀌었습니다'), findsOneWidget);
      expect(find.text('앱 본체'), findsNothing);
      expect(find.textContaining('내 계정에도 저장됩니다'), findsOneWidget);
      /* 체크 전에는 못 넘어갑니다. */
      expect(t.widget<FilledButton>(find.widgetWithText(FilledButton, '동의하고 계속'))
          .onPressed, isNull);

      await t.tap(find.text('동의합니다'));
      await t.pumpAndSettle();
      await t.tap(find.text('동의하고 계속'));
      await t.pumpAndSettle();

      expect(seen, contains('POST /me/consent'));
      expect(sent['healthConsent'], kHealthConsentVersion);
      expect(find.text('앱 본체'), findsOneWidget);
    });

    testWidgets('동의하지 않으면 로그아웃하고 로그인 없이 이어 간다', (t) async {
      final api = await signedIn(fake({'/me': me(old), '/auth/signout': {'ok': true}}));
      var declined = false;
      await t.pumpWidget(wrap(ConsentGate(
          api: api, onDecline: () => declined = true, child: const Text('앱 본체'))));
      await t.pumpAndSettle();
      await t.tap(find.text('동의하지 않고 로그인 없이 쓰기'));
      await t.pumpAndSettle();
      expect(api.signedIn, isFalse);
      expect(declined, isTrue, reason: '셸이 「로그인 없이 쓰기」로 넘기게 알려야 합니다');
    });

    testWidgets('이미 새 판이면 안 묻는다', (t) async {
      final api = await signedIn(fake({'/me': me(kHealthConsentVersion)}));
      await t.pumpWidget(wrap(ConsentGate(api: api, child: const Text('앱 본체'))));
      await t.pumpAndSettle();
      expect(find.text('앱 본체'), findsOneWidget);
      expect(find.text('동의 문구가 바뀌었습니다'), findsNothing);
    });

    testWidgets('서버가 안 닿으면 막지 않는다', (t) async {
      /* 지하철에서 켰다고 앱이 잠기면 안 됩니다. */
      final api = await signedIn(fake({}));
      await t.pumpWidget(wrap(ConsentGate(api: api, child: const Text('앱 본체'))));
      await t.pumpAndSettle();
      expect(find.text('앱 본체'), findsOneWidget);
    });

    testWidgets('옛 서버(현재 판을 안 알려 줌)면 안 묻는다', (t) async {
      final api = await signedIn(fake({'/me': me(old, current: false)}));
      await t.pumpWidget(wrap(ConsentGate(api: api, child: const Text('앱 본체'))));
      await t.pumpAndSettle();
      expect(find.text('앱 본체'), findsOneWidget);
    });
  });

  testWidgets('가입 동의 문구가 실제 동작과 같다 — 기록 전체 동기화, 거부해도 로그인 없이', (t) async {
    /* 예전 문구: "가장 최근 측정만 · 52주까지만". 동기화가 생긴 뒤로는 기록
       전체가 계정을 지울 때까지 남습니다. 거부하면 「로그인 없이 쓰기」가
       있으니 그 길을 말합니다. */
    await open(t, Api(baseUrl: 'https://x.test',
        client: fake({'/health': {'ok': true, 'openSignup': true}})));
    await t.tap(find.text('처음이에요'));
    await t.pumpAndSettle();
    expect(find.textContaining('내 계정에도 저장됩니다(동기화)'), findsOneWidget);
    expect(find.textContaining('로그인 없이 계속 쓸 수 있습니다'), findsOneWidget);
    expect(find.textContaining('결과지 사진은 올라가지 않습니다'), findsOneWidget);
    expect(find.textContaining('가장 최근 측정'), findsNothing);
    expect(find.text('자세히 — 개인정보처리방침'), findsOneWidget);
  });
}
