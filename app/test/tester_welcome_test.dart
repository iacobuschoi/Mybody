/* =============================================================================
 * tester_welcome_test.dart — 테스터 인사 시트 · 친구 코드 · 보내는 글 · 의견 버튼
 *
 * 주인이 고른 모양(시트 한 장 · 세 쪽 · 「건너뛰기」 · 쪽 점 · 아래 큰 단추)이
 * 실제로 그렇게 서고, **한 번만** 뜨는지를 봅니다. 한 번 더 뜨면 안내가 아니라
 * 방해이고, 로그인 · 온보딩 화면 위에 뜨면 첫 화면을 가립니다.
 *
 *   · 언제 뜨나   로그인 · 온보딩 화면에서는 안 뜨고, 탭 화면이 처음 설 때 한 번.
 *                다시 켜도 안 뜨고, 설정의 「다시 보기」(force)로는 뜨고, 두 장이 겹치지 않음.
 *   · 쪽 넘기기   「다음」 · 밀기 · 「건너뛰기」(본 것으로 적힘) · 마지막 「시작하기」.
 *   · 3쪽        로그인했으면 /me 의 코드 · 복사(클립보드) · 보내기(서버의 참여 주소까지)
 *                · 코드 넣고 「요청」(친구 탭과 같은 요청, 결과는 시트 안에) · 실패 문구.
 *                로그인 안 했으면 로그인 카드 → 로그인하고 돌아오면 그 자리에 코드.
 *   · 보내는 글   inviteShareText — 주소가 있을 때 · 없을 때.
 *   · 새 판 답    VersionInfo 가 join 을 https 만 받아 둔다.
 *   · 360 폭 · 글자 1.3배 · 밝은/어두운 테마에서 넘치지 않고, 키보드가 올라와도
 *     「요청」 이 키보드 위에 보인다.
 *   · 앱바에는 의견 단추가 없다 — 의견은 화면 옆 말풍선(1쪽이 그렇게 가리킴).
 *   · 1쪽 제목은 기종마다 — 아이폰은 「함께해 주셔서 고마워요!」(앱스토어 심사에 "테스트"
 *     라는 말이 안 가게), 안드로이드는 비공개 테스트 인사. 나머지 글은 같다.
 *   · 의견 시트가 떠 있으면(찍는 중 포함) 인사는 그 위에 안 뜨고, 닫히면 한 번 뜬다.
 * ========================================================================== */
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:mybody/src/api.dart';
import 'package:mybody/src/app_state.dart';
import 'package:mybody/src/scope.dart';
import 'package:mybody/src/screens/account.dart';
import 'package:mybody/src/screens/feedback.dart'
    show feedbackBusy, feedbackCapture, feedbackPick, openFeedback;
import 'package:mybody/src/screens/feedback_bubble.dart' show appFrame, feedbackRoutes;
import 'package:mybody/src/screens/onboarding.dart';
import 'package:mybody/src/screens/social.dart' show cleanInviteCode;
import 'package:mybody/src/screens/tester_welcome.dart';
import 'package:mybody/src/shell.dart';
import 'package:mybody/src/theme.dart';
import 'package:mybody/src/ui/edge.dart';
import 'package:mybody/src/update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _profile = {
  'sex': 'male', 'age': 22, 'heightCm': 187, 'activityLevel': 'moderate',
  'trainingAge': 'novice', 'daysPerWeek': 4, 'mealsPerDay': 3,
};

const _me = {
  'ok': true,
  'user': {'id': 'me', 'displayName': '나', 'inviteCode': 'ABCD2345'},
};

/// 서버 흉내. [routes] 의 값이 Map 이면 200 + 그 몸, int 면 그 상태, 없으면 404.
/// 나간 요청을 [sent] 에 남깁니다.
class _Server {
  _Server([Map<String, Object>? routes]) : routes = {...?routes};
  final Map<String, Object> routes;
  final sent = <(String path, Map<String, dynamic>? body)>[];

  /// 있으면 그 길은 이게 풀릴 때까지 답하지 않습니다(느린 서버).
  final gates = <String, Completer<void>>{};

  Api api({bool signedIn = true}) {
    http.Response json(Object body, int status) => http.Response.bytes(
          utf8.encode(jsonEncode(body)), status,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
    final a = Api(
      baseUrl: 'https://x.test',
      client: MockClient((req) async {
        final path = req.url.path.replaceFirst('/api', '');
        sent.add((path, req.body.isEmpty ? null : (jsonDecode(req.body) as Map).cast<String, dynamic>()));
        final gate = gates[path];
        if (gate != null) await gate.future;
        final v = routes[path];
        if (v is Map) return json(v, 200);
        if (v is int) return json({'ok': false}, v);
        return json({'ok': false, 'reason': '없는 길'}, 404);
      }),
    );
    if (signedIn) a.setToken('tok');
    return a;
  }

  List<Map<String, dynamic>?> bodiesTo(String path) =>
      [for (final r in sent) if (r.$1 == path) r.$2];
}

Future<AppState> _app({bool onboarded = true, bool seen = false, bool guest = false}) async {
  SharedPreferences.setMockInitialValues({});
  final app = await AppState.boot();
  if (onboarded) app.store.set({'profile': _profile, 'onboarded': true});
  if (guest) app.store.set({'guest': true});
  if (seen) markTesterWelcomeSeen(app);
  return app;
}

void _phone(WidgetTester t, Size size, {double text = 1.0}) {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1.0;
  t.platformDispatcher.textScaleFactorTestValue = text;
  addTearDown(t.view.reset);
  addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
}

/// 앱과 같은 겹: Scope > MaterialApp(builder: edgeSafe) > [home]. home 이 없으면 「열기」
/// 단추 하나 — 누르면 인사를 force 로 띄웁니다(설정의 「다시 보기」 와 같은 길).
Future<void> _host(WidgetTester t,
    {required AppState app, required Api api, Widget? home, UpdateCheck? update, bool dark = false}) async {
  await t.pumpWidget(Scope(
    state: app,
    api: api,
    update: update,
    onServerChange: (_) async {},
    child: MaterialApp(
      theme: dark ? mbDark() : mbLight(),
      builder: edgeSafe,
      home: home ??
          Builder(
            builder: (c) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showTesterWelcome(c, force: true),
                  child: const Text('열기'),
                ),
              ),
            ),
          ),
    ),
  ));
  await t.pumpAndSettle();
}

Future<void> _open(WidgetTester t) async {
  await t.tap(find.text('열기'));
  await t.pumpAndSettle();
  expect(find.byType(TesterWelcomeSheet), findsOneWidget);
}

/// 화면 글이 [s] 인 Text — 시트의 큰 글은 낱말 잇기(U+2060)가 끼어 있어 그것을 빼고 견줍니다.
Finder _text(String s) => find.byWidgetPredicate(
    (w) => w is Text && (w.data ?? '').replaceAll('\u2060', '') == s,
    description: 'text "$s"');

Finder get _primary => find.byKey(const Key('welcome-primary'));

String _primaryLabel(WidgetTester t) =>
    (t.widget<Text>(find.descendant(of: _primary, matching: find.byType(Text))).data)!;

Future<void> _toPage3(WidgetTester t) async {
  await t.tap(_primary);
  await t.pumpAndSettle();
  await t.tap(_primary);
  await t.pumpAndSettle();
  expect(_text('친구랑 같이 해요'), findsOneWidget);
}

/// 클립보드 흉내 — 복사한 글을 돌려받습니다.
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /* --- 보내는 글 --------------------------------------------------------------- */
  group('inviteShareText', () {
    test('주소가 없으면 코드와 넣을 곳 한 줄', () {
      expect(inviteShareText('ABCD2345', const JoinLinks()),
          'Mybody 같이 해요! 내 친구 코드: ABCD2345\n앱에서 친구 탭 → 친구 추가에 넣어 주세요');
    });

    test('아이폰 · 안드로이드(그룹 먼저) — 있는 것만, 차례대로', () {
      const join = JoinLinks(
          ios: 'https://testflight.apple.com/join/abc',
          android: 'https://play.google.com/apps/testing/x',
          androidGroup: 'https://groups.google.com/g/mybody');
      expect(
          inviteShareText('ABCD2345', join),
          'Mybody 같이 해요! 내 친구 코드: ABCD2345\n'
          '아이폰: https://testflight.apple.com/join/abc\n'
          '안드로이드: ① https://groups.google.com/g/mybody 가입 ② https://play.google.com/apps/testing/x 에서 참여');
    });

    test('안드로이드만 · 그룹 없음 — 주소 한 줄, 넣을 곳 안내는 없음', () {
      final s = inviteShareText('Q', const JoinLinks(android: 'https://play.google.com/apps/testing/x'));
      expect(s.split('\n'), ['Mybody 같이 해요! 내 친구 코드: Q', '안드로이드: https://play.google.com/apps/testing/x']);
    });

    test('아이폰만', () {
      final s = inviteShareText('Q', const JoinLinks(ios: 'https://testflight.apple.com/join/abc'));
      expect(s.split('\n'), ['Mybody 같이 해요! 내 친구 코드: Q', '아이폰: https://testflight.apple.com/join/abc']);
    });

    test('그룹 주소만 있으면(참여 주소 없음) 반쪽 길이라 안 싣고 넣을 곳 안내', () {
      final s = inviteShareText('Q', const JoinLinks(androidGroup: 'https://groups.google.com/g/x'));
      expect(s, isNot(contains('groups.google.com')));
      expect(s, contains('앱에서 친구 탭 → 친구 추가에 넣어 주세요'));
    });
  });

  /* --- 친구 코드 다듬기 --------------------------------------------------------- */
  test('cleanInviteCode — 받은 글을 통째로 붙여도 코드만, 빈칸 · 줄표는 뺀다', () {
    expect(cleanInviteCode(' ab12cd '), 'ab12cd');
    expect(cleanInviteCode('ABCD 2345'), 'ABCD2345');
    expect(cleanInviteCode('ABCD-2345'), 'ABCD2345');
    expect(
        cleanInviteCode(inviteShareText('WXYZ2345',
            const JoinLinks(ios: 'https://testflight.apple.com/join/abc'))),
        'WXYZ2345');
    expect(cleanInviteCode('   '), '');
  });

  /* --- 줄 바꿈 ------------------------------------------------------------------ */
  test('keepWords — 가운데 큰 글은 빈칸에서만 줄을 바꾼다(「감사합 / 니다!」 없음)', () {
    const s = '비공개 테스트에 참여해 주셔서 감사합니다!';
    final words = s.split(' ').toSet();
    List<String> lines(String text) {
      final tp = TextPainter(
          text: TextSpan(text: text, style: const TextStyle(fontSize: 20)),
          textDirection: TextDirection.ltr)
        ..layout(maxWidth: 200);
      final out = <String>[];
      var pos = 0;
      while (pos < text.length) {
        final r = tp.getLineBoundary(TextPosition(offset: pos));
        if (r.end <= pos) break;
        out.add(text.substring(r.start, r.end).replaceAll('\u2060', '').trim());
        pos = r.end;
      }
      tp.dispose();
      return out;
    }

    bool whole(List<String> ls) =>
        ls.every((l) => l.isEmpty || l.split(' ').every(words.contains));
    /* 전제 — 그냥 두면 이 폭에서 낱말 한가운데서 끊깁니다(안 끊기면 이 시험이 아무것도 못 가립니다). */
    expect(whole(lines(s)), isFalse);
    final kept = lines(keepWords(s));
    expect(kept.length, greaterThan(1));
    expect(whole(kept), isTrue, reason: '$kept');
    expect(keepWords(s).replaceAll('\u2060', ''), s, reason: '글자는 그대로');
  });

  /* --- 새 판 답의 join ------------------------------------------------------- */
  group('VersionInfo.join', () {
    test('https 주소만, 정한 칸만 받는다', () {
      final i = VersionInfo.fromJson({
        'ok': true,
        'latest': {'apk': '0.2.17'},
        'join': {
          'ios': ' https://testflight.apple.com/join/abc ',
          'android': 'http://play.google.com/apps/testing/x',   // http — 버림
          'androidGroup': 'javascript:alert(1)',                // 버림
          'web': 'https://evil.test',                           // 모르는 칸 — 버림
        },
      });
      expect(i.join, const JoinLinks(ios: 'https://testflight.apple.com/join/abc'));
      expect(i.join.toJson(), {'ios': 'https://testflight.apple.com/join/abc'});
    });

    test('세 칸 다 · 없거나 모양이 틀리면 비어 있음', () {
      final i = VersionInfo.fromJson({
        'join': {
          'ios': 'https://a.test/i',
          'android': 'https://a.test/a',
          'androidGroup': 'https://a.test/g',
        },
      });
      expect(i.join.ios, 'https://a.test/i');
      expect(i.join.android, 'https://a.test/a');
      expect(i.join.androidGroup, 'https://a.test/g');
      for (final j in <Object?>[null, 'x', 3, [], {'ios': 7}]) {
        expect(VersionInfo.fromJson({'join': j}).join.isEmpty, isTrue, reason: '$j');
      }
      expect(VersionInfo.fromJson({}).join.isEmpty, isTrue, reason: '옛 서버 — 칸 없음');
    });

    test('이 기기에 남긴 답(toJson)에서 되살아나고, 없으면 칸을 안 적는다', () {
      final i = VersionInfo.fromJson({
        'join': {'android': 'https://a.test/a', 'androidGroup': 'https://a.test/g'},
      });
      final back = VersionInfo.fromJson(jsonDecode(jsonEncode(i.toJson())));
      expect(back.join, i.join);
      expect(const VersionInfo().toJson().containsKey('join'), isFalse);
    });
  });

  /* --- 언제 뜨나 -------------------------------------------------------------- */
  group('언제 뜨나', () {
    testWidgets('로그인 · 온보딩 화면에서는 안 뜨고, 탭 화면이 처음 설 때 한 번', (t) async {
      _phone(t, const Size(390, 844));
      final app = await _app(onboarded: false);
      final s = _Server({'/me': _me});
      final api = s.api(signedIn: false);
      await _host(t, app: app, api: api, home: const Shell());
      expect(find.byType(SignInScreen), findsOneWidget);
      expect(find.byType(TesterWelcomeSheet), findsNothing, reason: '로그인 화면 위에 뜨면 안 됩니다');

      await api.setToken('tok');
      await t.pumpAndSettle();
      expect(find.byType(OnboardingScreen), findsOneWidget);
      expect(find.byType(TesterWelcomeSheet), findsNothing, reason: '온보딩 위에 뜨면 안 됩니다');
      expect(testerWelcomeSeen(app.state), isFalse, reason: '못 본 것을 본 것으로 적으면 안 됩니다');

      app.store.set({'profile': _profile, 'onboarded': true});   // 온보딩을 마친 것과 같습니다
      await t.pumpAndSettle();
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(TesterWelcomeSheet), findsOneWidget, reason: '탭 화면이 서면 한 번');
      expect(_text('비공개 테스트에 참여해 주셔서 감사합니다!'), findsOneWidget);
      expect(testerWelcomeSeen(app.state), isTrue, reason: '띄우는 순간 본 것으로');

      /* 닫고 셸이 다시 그려져도(탭 이동 · 상태 변경) 다시 안 뜹니다. */
      await t.tap(find.byKey(const Key('welcome-skip')));
      await t.pumpAndSettle();
      expect(find.byType(TesterWelcomeSheet), findsNothing);
      await t.tap(find.widgetWithText(NavigationDestination, '식단'));
      await t.pumpAndSettle();
      app.store.set({'foodFavorites': ['밥']});
      await t.pumpAndSettle();
      expect(find.byType(TesterWelcomeSheet), findsNothing, reason: '두 번 뜨면 안 됩니다');
      expect(t.takeException(), isNull);
    });

    testWidgets('이미 쓰던 사람(온보딩 끝)도 업데이트 뒤 한 번 — 다시 켜면 안 뜬다', (t) async {
      _phone(t, const Size(390, 844));
      final app = await _app();
      final s = _Server({'/me': _me});
      await _host(t, app: app, api: s.api(), home: const Shell());
      expect(find.byType(TesterWelcomeSheet), findsOneWidget);
      /* 바깥을 눌러 닫아도 본 것입니다. */
      await t.tapAt(const Offset(200, 10));
      await t.pumpAndSettle();
      expect(find.byType(TesterWelcomeSheet), findsNothing);

      /* 다시 켠 것처럼 — 같은 저장소로 새로 세웁니다. */
      await t.pumpWidget(const SizedBox());
      final again = await AppState.boot();
      expect(testerWelcomeSeen(again.state), isTrue, reason: '저장소에 남아야 합니다');
      await _host(t, app: again, api: s.api(), home: const Shell());
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(TesterWelcomeSheet), findsNothing, reason: '다시 켜도 또 뜨면 방해입니다');
    });

    /* 동의 게이트는 /me 를 받기 전까지 탭을 세워 두었다가 옛 동의면 동의 화면으로 바꿉니다.
       그 사이에 인사가 뜨면 동의 화면을 덮습니다 — 동의를 마치고 탭이 다시 설 때 한 번. */
    testWidgets('옛 동의로 로그인한 사람 — 동의 화면 위에는 안 뜨고, 동의하고 탭이 서면 한 번', (t) async {
      _phone(t, const Size(390, 844));
      final app = await _app();
      final s = _Server({
        '/me': {
          'ok': true,
          'user': {
            ...(_me['user'] as Map<String, Object>),
            'healthConsentVersion': '2000-01-01',
            'healthConsentCurrent': kHealthConsentVersion,
          },
        },
        '/me/consent': {'ok': true},
      });
      await _host(t, app: app, api: s.api(), home: const Shell());
      expect(find.text('동의 문구가 바뀌었습니다'), findsOneWidget, reason: '이 시험의 전제 — 옛 동의');
      expect(find.byType(TesterWelcomeSheet), findsNothing, reason: '동의 화면을 덮으면 안 됩니다');
      expect(testerWelcomeSeen(app.state), isFalse, reason: '못 본 것을 본 것으로 적으면 안 됩니다');

      s.routes['/me'] = _me;   // 동의한 뒤의 /me
      await t.tap(find.text('동의합니다'));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('동의하고 계속'));
      await t.tap(find.text('동의하고 계속'));
      await t.pumpAndSettle();
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(TesterWelcomeSheet), findsOneWidget, reason: '탭이 다시 서면 그때 한 번');
      expect(t.takeException(), isNull);
    });

    testWidgets('로그인 없이 쓰는 사람에게도 탭 화면에서 한 번', (t) async {
      _phone(t, const Size(390, 844));
      final app = await _app(guest: true);
      await _host(t, app: app, api: _Server().api(signedIn: false), home: const Shell());
      expect(find.byType(TesterWelcomeSheet), findsOneWidget);
    });

    testWidgets('본 적이 있으면 그냥 돌아오고, force(설정의 「다시 보기」)면 뜬다 — 두 장은 안 쌓인다', (t) async {
      _phone(t, const Size(390, 844));
      final app = await _app(seen: true);
      late BuildContext ctx;
      await _host(t, app: app, api: _Server({'/me': _me}).api(),
          home: Builder(builder: (c) {
            ctx = c;
            return const Scaffold(body: SizedBox());
          }));
      await showTesterWelcome(ctx);
      await t.pumpAndSettle();
      expect(find.byType(TesterWelcomeSheet), findsNothing);

      showTesterWelcome(ctx, force: true);
      await t.pumpAndSettle();
      showTesterWelcome(ctx, force: true);
      await t.pumpAndSettle();
      expect(find.byType(TesterWelcomeSheet), findsOneWidget, reason: '겹쳐 뜨면 안 됩니다');

      await t.tap(find.byKey(const Key('welcome-skip')));
      await t.pumpAndSettle();
      expect(find.byType(TesterWelcomeSheet), findsNothing);
      /* 닫은 뒤에는 다시 띄울 수 있어야 합니다(「다시 보기」 를 또 누르는 사람). */
      showTesterWelcome(ctx, force: true);
      await t.pumpAndSettle();
      expect(find.byType(TesterWelcomeSheet), findsOneWidget);
    });
  });

  /* --- 쪽 넘기기 -------------------------------------------------------------- */
  group('세 쪽', () {
    testWidgets('「다음」 · 밀기로 넘기고, 마지막 「시작하기」 로 닫는다', (t) async {
      _phone(t, const Size(390, 844));
      await _host(t, app: await _app(), api: _Server({'/me': _me}).api());
      await _open(t);

      expect(_text('비공개 테스트에 참여해 주셔서 감사합니다!'), findsOneWidget);
      expect(_text('새 버전이 나오면 앱이 알려 드려요'), findsOneWidget);
      expect(_text('의견은 화면 옆 말풍선으로 — 화면이 같이 붙어요'), findsOneWidget);
      expect(_primaryLabel(t), '다음');
      expect(find.byKey(const Key('welcome-skip')).hitTestable(), findsOneWidget);

      await t.tap(_primary);
      await t.pumpAndSettle();
      expect(_text('이렇게 써요'), findsOneWidget);
      expect(_text('네 가지면 끝이에요'), findsOneWidget);
      for (final s in ['인바디 결과지 찍기', '숫자는 앱이 읽어요', '목표 고르기', '주차별 운동·식단 플랜이 나와요',
          '매일 기록', '헬스·유산소·식단, 누르기만 하면 돼요', '변화 보기', '체지방·골격근이 그래프로']) {
        expect(find.text(s), findsOneWidget, reason: s);
      }

      /* 손으로 밀어도 넘어갑니다. */
      await t.fling(find.byType(PageView), const Offset(-300, 0), 1000);
      await t.pumpAndSettle();
      expect(_text('친구랑 같이 해요'), findsOneWidget);
      expect(_text('오늘 한 운동을 서로 보고, 안 한 친구는 콕 찔러요'), findsOneWidget);
      expect(_primaryLabel(t), '시작하기');
      expect(find.byKey(const Key('welcome-skip')).hitTestable(), findsNothing,
          reason: '마지막 쪽에서는 「시작하기」 가 같은 일을 합니다');

      /* 거꾸로 밀면 돌아갑니다(제목에서 — 코드 칸 위의 가로 끌기는 글자 고르기 몫). */
      await t.flingFrom(t.getCenter(_text('친구랑 같이 해요')), const Offset(300, 0), 1000);
      await t.pumpAndSettle();
      expect(_text('이렇게 써요'), findsOneWidget);
      await t.tap(_primary);
      await t.pumpAndSettle();

      await t.tap(_primary);
      await t.pumpAndSettle();
      expect(find.byType(TesterWelcomeSheet), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('첫 쪽의 「건너뛰기」 — 닫히고 본 것으로 적힌다', (t) async {
      _phone(t, const Size(390, 844));
      final app = await _app();
      late BuildContext ctx;
      await _host(t, app: app, api: _Server({'/me': _me}).api(),
          home: Builder(builder: (c) {
            ctx = c;
            return const Scaffold(body: SizedBox());
          }));
      showTesterWelcome(ctx);
      await t.pumpAndSettle();
      expect(find.byType(TesterWelcomeSheet), findsOneWidget);
      await t.tap(find.text('건너뛰기'));
      await t.pumpAndSettle();
      expect(find.byType(TesterWelcomeSheet), findsNothing);
      expect(testerWelcomeSeen(app.state), isTrue);
      /* 본 것이니 force 가 아니면 다시 안 뜹니다. */
      showTesterWelcome(ctx);
      await t.pumpAndSettle();
      expect(find.byType(TesterWelcomeSheet), findsNothing);
    });
  });

  /* --- 3쪽: 친구 -------------------------------------------------------------- */
  group('3쪽 — 로그인했을 때', () {
    testWidgets('내 친구 코드(/me) · 복사 · 보내기(서버의 참여 주소까지)', (t) async {
      _phone(t, const Size(390, 844));
      final clip = _clipboard(t);
      final shared = <String>[];
      final before = testerWelcomeShare;
      testerWelcomeShare = (text, origin) async => shared.add(text);
      addTearDown(() => testerWelcomeShare = before);

      final s = _Server({
        '/me': _me,
        '/version': {
          'ok': true,
          'latest': {'apk': '0.2.17'},
          'join': {
            'ios': 'https://testflight.apple.com/join/abc',
            'android': 'https://play.google.com/apps/testing/x',
            'androidGroup': 'https://groups.google.com/g/mybody',
          },
        },
      });
      final api = s.api();
      final update = UpdateCheck(
        api: api,
        packageInfo: () async => PackageInfo(
            appName: 'Mybody', packageName: 'x', version: '0.2.17', buildNumber: '1'),
        platform: TargetPlatform.android,
        web: false,
      );
      addTearDown(update.dispose);
      await t.runAsync(update.start);
      expect(update.info?.join.isEmpty, isFalse, reason: '이 시험의 전제 — 새 판 답에 참여 주소');

      await _host(t, app: await _app(), api: api, update: update);
      await _open(t);
      await _toPage3(t);
      expect(find.text('내 친구 코드'), findsOneWidget);
      expect(find.byKey(const Key('welcome-code')), findsOneWidget);
      expect(find.text('ABCD2345'), findsOneWidget);

      await t.tap(find.byKey(const Key('welcome-copy')));
      await t.pumpAndSettle();
      expect(clip.value, 'ABCD2345');
      expect(find.text('복사했어요'), findsOneWidget, reason: '시트 안에 보여야 합니다');

      await t.tap(find.byKey(const Key('welcome-share')));
      await t.pumpAndSettle();
      expect(shared, hasLength(1));
      expect(shared.single, inviteShareText('ABCD2345', update.info!.join));
      expect(shared.single, contains('아이폰: https://testflight.apple.com/join/abc'));
      expect(shared.single, contains('① https://groups.google.com/g/mybody 가입'));
      expect(t.takeException(), isNull);
    });

    testWidgets('공유 시트가 실패하면 보낼 글을 복사해 둔다', (t) async {
      _phone(t, const Size(390, 844));
      final clip = _clipboard(t);
      final before = testerWelcomeShare;
      testerWelcomeShare = (text, origin) async => throw StateError('공유 없음');
      addTearDown(() => testerWelcomeShare = before);
      await _host(t, app: await _app(), api: _Server({'/me': _me}).api());
      await _open(t);
      await _toPage3(t);
      await t.tap(find.byKey(const Key('welcome-share')));
      await t.pumpAndSettle();
      expect(clip.value, inviteShareText('ABCD2345', const JoinLinks()));
      expect(find.textContaining('보낼 글을 복사했어요'), findsOneWidget);
    });

    testWidgets('코드를 넣고 「요청」 — 친구 탭과 같은 요청, 결과는 시트 안에', (t) async {
      _phone(t, const Size(390, 844));
      final s = _Server({'/me': _me, '/friends/request': {'ok': true, 'status': 'pending'}});
      await _host(t, app: await _app(), api: s.api());
      await _open(t);
      await _toPage3(t);
      expect(find.text('친구 코드가 있나요?'), findsOneWidget);
      expect(find.text('받은 요청은 친구 탭에서 수락해요'), findsOneWidget);

      final field = find.byKey(const Key('welcome-code-input'));
      final tf = t.widget<TextField>(field);
      expect(tf.autocorrect, isFalse, reason: '코드는 낱말이 아닙니다');
      expect(tf.enableSuggestions, isFalse);
      expect(tf.textInputAction, TextInputAction.done);
      expect(t.widget<FilledButton>(find.byKey(const Key('welcome-request'))).onPressed, isNull,
          reason: '빈 칸이면 「요청」 은 못 누릅니다');

      await t.tap(field);
      await t.pumpAndSettle();
      await t.enterText(field, ' wxyz2345 ');
      await t.pump();
      await t.tap(find.byKey(const Key('welcome-request')));
      await t.pumpAndSettle();
      expect(s.bodiesTo('/friends/request'), [
        {'inviteCode': 'wxyz2345'}
      ]);
      expect(find.text('요청을 보냈어요 — 친구가 수락하면 친구 탭에 떠요'), findsOneWidget);
      expect(find.byType(TesterWelcomeSheet), findsOneWidget, reason: '시트를 떠나지 않습니다');
      expect(t.widget<TextField>(field).controller!.text, isEmpty, reason: '다음 코드를 넣을 수 있게');
      expect(t.testTextInput.hasAnyClients, isFalse, reason: '보냈으면 키보드를 내려 결과가 보이게');

      /* 완료 키로도 보냅니다. 받은 글을 통째로 붙여 넣어도 코드만 갑니다. */
      await t.tap(field);
      await t.pumpAndSettle();
      await t.enterText(field, 'Mybody 같이 해요! 내 친구 코드: QRST6789');
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pumpAndSettle();
      expect(s.bodiesTo('/friends/request').last, {'inviteCode': 'QRST6789'});
      expect(t.takeException(), isNull);
    });

    testWidgets('맞요청이면 "친구가 됐어요"', (t) async {
      _phone(t, const Size(390, 844));
      final s = _Server({'/me': _me, '/friends/request': {'ok': true, 'status': 'accepted'}});
      await _host(t, app: await _app(), api: s.api());
      await _open(t);
      await _toPage3(t);
      await t.enterText(find.byKey(const Key('welcome-code-input')), 'WXYZ2345');
      await t.pump();
      await t.tap(find.byKey(const Key('welcome-request')));
      await t.pumpAndSettle();
      expect(find.text('친구가 됐어요 — 친구 탭에서 볼 수 있어요'), findsOneWidget);
    });

    testWidgets('실패는 서버가 준 까닭 그대로 — 칸은 그대로 두어 고쳐 넣게', (t) async {
      _phone(t, const Size(390, 844));
      final s = _Server({
        '/me': _me,
        '/friends/request': {'ok': false, 'reason': '그런 코드를 가진 사람이 없습니다'},
      });
      await _host(t, app: await _app(), api: s.api());
      await _open(t);
      await _toPage3(t);
      final field = find.byKey(const Key('welcome-code-input'));
      await t.enterText(field, 'NOPE0000');
      await t.pump();
      await t.tap(find.byKey(const Key('welcome-request')));
      await t.pumpAndSettle();
      expect(find.text('그런 코드를 가진 사람이 없습니다'), findsOneWidget);
      expect(t.widget<TextField>(field).controller!.text, 'NOPE0000');
      expect(find.textContaining('요청을 보냈어요'), findsNothing);

      /* 서버에 못 닿으면 — 친구 탭과 같은 문구(큐에 담지 않음). */
      s.routes.remove('/friends/request');
      s.routes['/friends/request'] = 503;
      await t.tap(find.byKey(const Key('welcome-request')));
      await t.pumpAndSettle();
      expect(find.text('요청이 실패했습니다 (503)'), findsOneWidget);
    });

    testWidgets('코드를 못 받으면 조용히 「다시」 — 누르면 다시 받아 온다', (t) async {
      _phone(t, const Size(390, 844));
      final s = _Server();   // /me 가 404
      await _host(t, app: await _app(), api: s.api());
      await _open(t);
      await _toPage3(t);
      expect(find.text('못 불러왔어요'), findsOneWidget);
      expect(t.widget<OutlinedButton>(find.byKey(const Key('welcome-copy'))).onPressed, isNull);

      s.routes['/me'] = _me;
      await t.tap(find.byKey(const Key('welcome-code-retry')));
      await t.pumpAndSettle();
      expect(find.text('ABCD2345'), findsOneWidget);
      expect(find.text('못 불러왔어요'), findsNothing);
    });
  });

  group('3쪽 — 로그인 안 했을 때', () {
    testWidgets('로그인 카드 → 로그인하고 돌아오면 그 자리에 코드', (t) async {
      _phone(t, const Size(390, 844));
      final s = _Server({'/me': _me});
      final api = s.api(signedIn: false);
      await _host(t, app: await _app(guest: true), api: api);
      await _open(t);
      await _toPage3(t);
      expect(find.text('로그인하면 내 친구 코드가 생겨요'), findsOneWidget);
      expect(find.text('기록은 이 폰에 그대로 있어요'), findsOneWidget);
      expect(find.text('친구 코드가 있나요?'), findsNothing, reason: '로그인 없이는 요청을 못 보냅니다');
      expect(_primaryLabel(t), '나중에 하고 시작하기');
      expect(find.descendant(of: _primary, matching: find.byType(Text)), findsOneWidget);
      expect(t.widget(_primary), isA<OutlinedButton>(), reason: '로그인이 주된 길 — 끝내기는 한 발 물러서게');
      expect(s.bodiesTo('/me'), isEmpty, reason: '로그인 전에는 코드를 묻지 않습니다');

      await t.tap(find.byKey(const Key('welcome-signin')));
      await t.pumpAndSettle();
      expect(find.byType(SignInScreen), findsOneWidget);

      /* 로그인이 되면 SignInScreen 이 onDone 을 부릅니다 — 그와 같이. */
      await api.setToken('tok');
      t.widget<SignInScreen>(find.byType(SignInScreen)).onDone();
      await t.pumpAndSettle();
      expect(find.byType(SignInScreen), findsNothing);
      expect(find.byType(TesterWelcomeSheet), findsOneWidget, reason: '시트로 돌아옵니다');
      expect(find.text('ABCD2345'), findsOneWidget);
      expect(find.text('친구 코드가 있나요?'), findsOneWidget);
      expect(_primaryLabel(t), '시작하기');
      expect(t.takeException(), isNull);
    });
  });

  /* --- 작은 폰 · 큰 글씨 · 두 테마 · 키보드 -------------------------------------- */
  group('360 폭 · 글자 1.3배', () {
    for (final dark in [false, true]) {
      for (final signedIn in [true, false]) {
        final name = '${dark ? '어두운' : '밝은'} 테마 · ${signedIn ? '로그인' : '로그인 없이'}';
        testWidgets('$name — 세 쪽 모두 넘치지 않는다', (t) async {
          _phone(t, const Size(360, 640), text: 1.3);
          final s = _Server({'/me': _me});
          await _host(t,
              app: await _app(guest: !signedIn), api: s.api(signedIn: signedIn), dark: dark);
          await _open(t);
          expect(t.takeException(), isNull, reason: '1쪽');
          await t.tap(_primary);
          await t.pumpAndSettle();
          expect(t.takeException(), isNull, reason: '2쪽');
          await t.tap(_primary);
          await t.pumpAndSettle();
          expect(_text('친구랑 같이 해요'), findsOneWidget);
          expect(t.takeException(), isNull, reason: '3쪽');
          /* 맨 아래까지 스크롤해도 — 아래 단추는 늘 보입니다. */
          await t.drag(find.byType(SingleChildScrollView).last, const Offset(0, -600));
          await t.pumpAndSettle();
          expect(_primary.hitTestable(), findsOneWidget);
          expect(t.takeException(), isNull);
        });
      }
    }

    testWidgets('못 받은 코드(「다시」)도 넘치지 않는다', (t) async {
      _phone(t, const Size(360, 640), text: 1.3);
      await _host(t, app: await _app(), api: _Server().api());
      await _open(t);
      await _toPage3(t);
      expect(find.text('못 불러왔어요'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });

  group('키보드', () {
    const kb = 300.0;
    for (final size in const [Size(360, 640), Size(360, 740), Size(390, 844)]) {
      testWidgets('${size.width.toInt()}×${size.height.toInt()} — 코드 칸을 누르면 「요청」 이 키보드 위에 보인다',
          (t) async {
        _phone(t, size, text: 1.3);
        final s = _Server({'/me': _me, '/friends/request': {'ok': true}});
        await _host(t, app: await _app(), api: s.api());
        await _open(t);
        await _toPage3(t);

        final field = find.byKey(const Key('welcome-code-input'));
        await t.tap(field);
        await t.pumpAndSettle();
        expect(t.testTextInput.hasAnyClients, isTrue);
        t.view.viewInsets = const FakeViewPadding(bottom: kb);
        await t.pumpAndSettle();

        for (final f in [field, find.byKey(const Key('welcome-request'))]) {
          final r = t.getRect(f);
          expect(r.bottom, lessThanOrEqualTo(size.height - kb), reason: '키보드 뒤에 깔림: $r');
          expect(r.top, greaterThanOrEqualTo(0), reason: '화면 위로 나감: $r');
        }
        expect(_primary, findsNothing, reason: '키보드가 떠 있는 동안 큰 단추는 접어 자리를 냅니다');

        await t.enterText(field, 'WXYZ2345');
        await t.pump();
        await t.tap(find.byKey(const Key('welcome-request')));
        await t.pumpAndSettle();
        expect(s.bodiesTo('/friends/request'), hasLength(1), reason: '키보드 위에서 실제로 눌려야 합니다');
        expect(t.testTextInput.hasAnyClients, isFalse);

        /* 키보드가 내려가면 큰 단추가 돌아옵니다. */
        t.view.viewInsets = FakeViewPadding.zero;
        await t.pumpAndSettle();
        expect(_primary.hitTestable(), findsOneWidget);
        expect(find.text('요청을 보냈어요 — 친구가 수락하면 친구 탭에 떠요'), findsOneWidget);
        expect(t.takeException(), isNull);
      });
    }
  });

  /* --- 1쪽 제목 — 기종마다 ------------------------------------------------------- */
  group('1쪽 제목', () {
    test('welcomeTitle — 아이폰은 테스트라는 말 없이, 그 밖은 비공개 테스트 인사', () {
      expect(welcomeTitle(TargetPlatform.iOS), '함께해 주셔서 고마워요!');
      expect(welcomeTitle(TargetPlatform.android), '비공개 테스트에 참여해 주셔서 감사합니다!');
      for (final w in ['테스트', '베타', '시험']) {
        expect(welcomeTitle(TargetPlatform.iOS), isNot(contains(w)), reason: '앱스토어 심사 지침 2.2');
      }
    });

    for (final (platform, title) in const [
      (TargetPlatform.iOS, '함께해 주셔서 고마워요!'),
      (TargetPlatform.android, '비공개 테스트에 참여해 주셔서 감사합니다!'),
    ]) {
      testWidgets('${platform.name} — 제목은 「$title」, 나머지 글은 같다', (t) async {
        debugDefaultTargetPlatformOverride = platform;
        try {
          _phone(t, const Size(390, 844));
          await _host(t, app: await _app(), api: _Server({'/me': _me}).api());
          await _open(t);
          expect(_text(title), findsOneWidget);
          final other = platform == TargetPlatform.iOS
              ? '비공개 테스트에 참여해 주셔서 감사합니다!'
              : '함께해 주셔서 고마워요!';
          expect(_text(other), findsNothing);
          expect(_text('Mybody 를 가장 먼저 써 보는 분이에요. 불편한 점은 뭐든 알려 주세요 — 바로 고칩니다.'),
              findsOneWidget);
          expect(_text('새 버전이 나오면 앱이 알려 드려요'), findsOneWidget);
          expect(_text('의견은 화면 옆 말풍선으로 — 화면이 같이 붙어요'), findsOneWidget);
          expect(t.takeException(), isNull);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }
  });

  /* --- 의견 시트와 겹치지 않게 ----------------------------------------------------- */
  group('의견 시트와 겹치지 않게', () {
    final origCapture = feedbackCapture;
    final origPick = feedbackPick;
    tearDown(() {
      feedbackCapture = origCapture;
      feedbackPick = origPick;
    });

    /* 셸은 로그인한 사람의 /me 를 기다린 뒤 인사를 부릅니다(4초까지). 그 사이 말풍선을
       눌러 의견 시트를 연 사람 위에 인사가 덮이면 쓰던 글 · 붙인 화면이 가려집니다. */
    testWidgets('의견 시트가 떠 있으면 인사는 기다렸다가, 시트가 닫히면 한 번 뜬다', (t) async {
      _phone(t, const Size(390, 844));
      final app = await _app();
      final s = _Server({'/me': _me});
      final me = s.gates['/me'] = Completer<void>();
      var captures = 0;
      feedbackCapture = () async {
        captures++;
        return null;
      };
      feedbackPick = (_) async => const [];
      await t.pumpWidget(Scope(
        state: app,
        api: s.api(),
        onServerChange: (_) async {},
        child: MaterialApp(
          theme: mbLight(),
          navigatorObservers: [feedbackRoutes],
          builder: appFrame,
          home: const Shell(),
        ),
      ));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(TesterWelcomeSheet), findsNothing, reason: '/me 를 기다리는 중');

      /* 화면 옆 말풍선으로 의견 시트를 엽니다. */
      await t.tap(find.byKey(const Key('feedback-bubble')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
      expect(captures, 1);
      final sheet = find.byKey(const Key('feedback-send'));
      expect(sheet, findsOneWidget);
      expect(feedbackBusy.value, isTrue);

      /* /me 가 돌아와 인사가 뜨려 하지만 — 의견 시트 위에는 안 뜹니다. */
      me.complete();
      await t.pump();
      await t.pump(const Duration(seconds: 1));
      expect(find.byType(TesterWelcomeSheet), findsNothing, reason: '의견 시트를 덮으면 안 됩니다');
      expect(sheet, findsOneWidget);
      expect(testerWelcomeSeen(app.state), isFalse, reason: '아직 안 띄웠으니 본 것이 아닙니다');

      /* 의견 시트를 닫으면 한 번 뜹니다. */
      await t.tapAt(const Offset(20, 20));
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
      await t.pump(const Duration(milliseconds: 500));
      expect(sheet, findsNothing);
      expect(feedbackBusy.value, isFalse);
      expect(find.byType(TesterWelcomeSheet), findsOneWidget, reason: '닫히면 그때 한 번');
      expect(testerWelcomeSeen(app.state), isTrue);
      await t.pump(const Duration(seconds: 3));   // 폭죽이 끝나게
      expect(find.byType(TesterWelcomeSheet), findsOneWidget, reason: '두 장이 쌓이지 않습니다');
      expect(t.takeException(), isNull);
    });

    testWidgets('기다리는 동안 또 불려도 인사는 한 장 — 시트가 안 떠 있으면 곧바로', (t) async {
      _phone(t, const Size(390, 844));
      feedbackCapture = () async => null;
      await _host(t, app: await _app(), api: _Server({'/me': _me}).api(),
          home: Builder(
            builder: (c) => Scaffold(
              body: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  TextButton(onPressed: () => openFeedback(c), child: const Text('의견')),
                  TextButton(
                      onPressed: () => showTesterWelcome(c, force: true), child: const Text('열기')),
                ]),
              ),
            ),
          ));
      await t.tap(find.text('의견'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('feedback-send')), findsOneWidget);
      /* 시트 밖 단추는 가림막 밑이라 눌리지 않습니다 — 셸처럼 코드에서 부릅니다(두 번). */
      final c = t.element(find.text('열기'));
      unawaited(showTesterWelcome(c, force: true));
      unawaited(showTesterWelcome(c, force: true));
      await t.pumpAndSettle();
      expect(find.byType(TesterWelcomeSheet), findsNothing);

      await t.tapAt(const Offset(20, 20));
      await t.pumpAndSettle();
      expect(find.byType(TesterWelcomeSheet), findsOneWidget);
      await t.tap(find.byKey(const Key('welcome-skip')));
      await t.pumpAndSettle();
      expect(find.byType(TesterWelcomeSheet), findsNothing, reason: '한 장만 떴으니 한 번 닫으면 끝');

      /* 의견 시트가 없으면 기다리지 않습니다. */
      await t.tap(find.text('열기'));
      await t.pumpAndSettle();
      expect(find.byType(TesterWelcomeSheet), findsOneWidget);
    });
  });

  /* --- 앱바에는 의견 단추가 없다 -------------------------------------------------- */
  testWidgets('셸 앱바 — 의견 단추는 없고 톱니만(의견은 화면 옆 말풍선)', (t) async {
    _phone(t, const Size(390, 844));
    await _host(t, app: await _app(seen: true, guest: true), api: _Server().api(signedIn: false),
        home: const Shell());
    await t.pumpAndSettle();
    expect(find.byKey(const Key('shell-feedback')), findsNothing);
    expect(find.byTooltip('의견 보내기'), findsNothing);
    final bar = find.byType(AppBar);
    expect(find.descendant(of: bar, matching: find.byIcon(LucideIcons.messageSquare)), findsNothing);
    expect(find.descendant(of: bar, matching: find.byType(IconButton)), findsOneWidget, reason: '톱니 하나');
    expect(find.byTooltip('설정'), findsOneWidget);
  });
}
