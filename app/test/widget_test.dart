/* =============================================================================
 * widget_test.dart — 화면을 **실제로 눌러서** 봅니다
 *
 * 폰 없이 돕니다. `flutter test` 한 줄이면 끝이라, 화면을 고칠 때마다
 * 바로 돌릴 수 있습니다. 여기서 잡히는 것과 폰에서만 잡히는 것을 나눠
 * 두면, 폰이 필요한 일만 사람 손에 남습니다.
 * ========================================================================== */
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mybody/main.dart';
import 'package:mybody/src/api.dart';
import 'package:mybody/src/theme.dart';

/// 서버 대신 대답하는 가짜. 진짜 서버를 안 띄우고도 화면의 처신을 봅니다.
MockClient fake(Map<String, Object> routes, {List<String>? seen}) {
  /* 한글을 바이트로 돌려줍니다.
     http.Response(String, ...) 는 latin1 로 인코딩해서 한글이면 던집니다 —
     진짜 서버는 utf-8 바이트를 보내므로 이쪽이 실제와 같은 모양입니다.
     (이 차이 때문에 api.dart 의 진짜 버그가 드러났습니다.) */
  http.Response json(Object body, int status) => http.Response.bytes(
        utf8.encode(jsonEncode(body)), status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
  return MockClient((req) async {
    seen?.add('${req.method} ${req.url.path}');
    final key = req.url.path.replaceFirst('/api', '');
    final v = routes[key];
    if (v == null) return json({'ok': false, 'reason': '없는 길'}, 404);
    if (v is int) return json({'ok': false, 'reason': '거부'}, v);
    return json(v, 200);
  });
}

Widget wrap(Widget child) => MaterialApp(theme: mbLight(), home: child);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('서버 주소 화면', () {
    testWidgets('https 가 아니면 저장하지 않는다', (t) async {
      var saved = '';
      await t.pumpWidget(wrap(ServerScreen(onSet: (u) async { saved = u; })));
      await t.enterText(find.byType(TextField), 'my-server.local');
      await t.tap(find.widgetWithText(FilledButton, '연결'));
      await t.pumpAndSettle();
      expect(find.textContaining('https:// 로 시작'), findsOneWidget);
      expect(saved, '', reason: '틀린 주소가 저장되면 다음 화면부터 전부 실패합니다');
    });

    testWidgets('닿지 않는 주소는 저장하지 않고 이유를 말한다', (t) async {
      var saved = '';
      await t.pumpWidget(wrap(ServerScreen(onSet: (u) async { saved = u; })));
      await t.enterText(find.byType(TextField), 'https://nope.example');
      await t.tap(find.widgetWithText(FilledButton, '연결'));
      await t.pumpAndSettle();
      /* 오타 난 주소를 저장해 두면 사용자는 어디가 틀렸는지 영영 모릅니다. */
      expect(find.textContaining('응답이 없습니다'), findsOneWidget);
      expect(saved, '');
    });
  });

  group('로그인 화면', () {
    testWidgets('실패하면 서버가 준 이유를 그대로 보여준다', (t) async {
      final api = Api(baseUrl: 'https://x.test',
          client: fake({'/auth/signin': {'ok': false, 'reason': '아이디 또는 비밀번호가 맞지 않습니다'}}));
      await t.pumpWidget(wrap(SignInScreen(api: api, onDone: () {}, onServerChange: (_) async {})));
      await t.enterText(find.byType(TextField).first, 'chulsoo');
      await t.enterText(find.byType(TextField).last, 'wrong');
      await t.tap(find.widgetWithText(FilledButton, '로그인'));
      await t.pumpAndSettle();
      expect(find.text('아이디 또는 비밀번호가 맞지 않습니다'), findsOneWidget);
    });

    testWidgets('비밀번호를 잊었을 때 갈 곳을 알려준다', (t) async {
      /* 이게 없어서 사람들이 새 계정을 만들고 있었습니다 —
         로그인 실패 6 · 로그인 성공 1 · 가입 7 이 실제 로그였습니다. */
      final api = Api(baseUrl: 'https://x.test', client: fake({}));
      await t.pumpWidget(wrap(SignInScreen(api: api, onDone: () {}, onServerChange: (_) async {})));
      expect(find.textContaining('복구 코드'), findsOneWidget);
      expect(find.textContaining('띄운 사람에게 말하면'), findsOneWidget);
    });

    testWidgets('성공하면 다음으로 넘어간다', (t) async {
      var done = false;
      final api = Api(baseUrl: 'https://x.test',
          client: fake({'/auth/signin': {'ok': true, 'token': 'tok', 'user': {'handle': 'chulsoo'}}}));
      await t.pumpWidget(wrap(SignInScreen(api: api, onDone: () { done = true; }, onServerChange: (_) async {})));
      await t.enterText(find.byType(TextField).first, 'chulsoo');
      await t.enterText(find.byType(TextField).last, 'right');
      await t.tap(find.widgetWithText(FilledButton, '로그인'));
      await t.pumpAndSettle();
      expect(done, isTrue);
      expect(api.signedIn, isTrue);
    });
  });

  group('계정 화면', () {
    testWidgets('이름과 친구 수를 보여준다 (한글이 실제로 그려진다)', (t) async {
      final api = Api(baseUrl: 'https://x.test', client: fake({
        '/me': {'ok': true, 'user': {'handle': 'chulsoo', 'displayName': '철수'}},
        '/friends': {'ok': true, 'accepted': [{'id': 'a'}, {'id': 'b'}]},
      }));
      await t.pumpWidget(wrap(AccountScreen(api: api, onServerChange: (_) async {})));
      await t.pumpAndSettle();
      expect(find.text('철수님'), findsOneWidget);
      expect(find.text('친구 2명'), findsOneWidget);
    });

    testWidgets('서버가 꺼져 있으면 그렇다고 말한다', (t) async {
      /* 서버가 주인 노트북이라 실제로 꺼져 있을 수 있습니다.
         빈 화면이나 영원히 도는 원으로 두면 앱이 고장 난 줄 압니다. */
      final api = Api(baseUrl: 'https://x.test', client: MockClient((_) async {
        throw Exception('연결 실패');
      }));
      await t.pumpWidget(wrap(AccountScreen(api: api, onServerChange: (_) async {})));
      await t.pumpAndSettle();
      expect(find.textContaining('컴퓨터가 꺼져 있을 수 있습니다'), findsOneWidget);
    });
  });

  group('API', () {
    test('다른 요청의 401 로는 로그아웃하지 않는다', () async {
      /* 지금 앱에서 이것 때문에 데였습니다 — 판독 키가 거부됐을 뿐인데
         사용자를 로그아웃시켜서 쓰던 화면이 통째로 날아갔습니다. */
      final api = Api(baseUrl: 'https://x.test',
          client: fake({'/auth/signin': {'ok': true, 'token': 'tok'}, '/ocr': 401}));
      await api.signIn(handle: 'a', password: 'b');
      expect(api.signedIn, isTrue);
      await api.me();
      expect(api.signedIn, isTrue, reason: '/me 를 안 불렀으면 세션은 그대로여야 합니다');
    });

    test('/me 가 401 이면 그때는 로그아웃한다', () async {
      final api = Api(baseUrl: 'https://x.test',
          client: fake({'/auth/signin': {'ok': true, 'token': 'tok'}, '/me': 401}));
      await api.signIn(handle: 'a', password: 'b');
      expect(api.signedIn, isTrue);
      final alive = await api.sessionAlive();
      expect(alive, isFalse);
      expect(api.signedIn, isFalse);
    });
  });
}
