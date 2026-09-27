/* =============================================================================
 * feedback_bubble_test.dart — 화면 옆에 늘 떠 있는 「의견 보내기」 말풍선
 *
 * 주인의 말: "의견보내기는 설정 드가서 하는게 아니라 앱 어딘가에 상시 떠있는 버튼으로
 * ㄱㄱ 위치/크기는 적절히 정해봐". 그래서 여기서 못 박는 것:
 *
 *   · 어디에나   탭 화면 · 밀어 올린 화면(설정) · 로그인 · 첫 설정 화면 모두에 뜬다.
 *                진짜 앱(main.dart)에서도 — 켜는 중(Scope 없음)에는 안 보이고, 준비되면 뜬다.
 *                Navigator 바깥(위)에 있다.
 *   · 자리       오른쪽 가장자리 8px 안쪽 · 높이 58%. 360×640 · 430×932(안전 영역 있음 ·
 *                없음)에서 「인바디」 단추 · 탭바 · 앱바와 겹치지 않는다 — 끝까지 끌어도.
 *   · 숨는 때    키보드가 올라와 있을 때 · 의견 시트가 떠 있을 때(찍는 중부터). 흐려지며.
 *   · 누르면     지금 화면을 찍어 붙인 시트, 화면 이름은 홈 · 식단 · 설정(밀어 올린 화면)
 *                · 다이얼로그 위에서는 그 밑의 화면.
 *   · 안 찍힌다   캡처 경계 안에 말풍선이 없고, 켜 있을 때와 꺼 있을 때 찍힌 그림이 같다
 *                (경계 밖을 같이 찍으면 달라진다 — 비교가 헛돌지 않는다는 대조).
 *   · 끌기       놓으면 가까운 쪽에 붙고, 다시 켜도 그 자리(SharedPreferences).
 *   · 길게       「의견 버튼 숨기기」 → 숨고 "설정 → 도움말에서 다시 켤 수 있어요",
 *                다시 켜도 숨은 채, 설정의 「의견 버튼 보이기」 로 곧바로 돌아온다.
 *   · 스크린리더  「의견 보내기」 단추 · 길게 누르기 힌트 · 숨으면 트리에서 빠진다.
 *   · 360px · 글자 1.3배 · 밝게/어둡게 — 넘치지 않고 색은 테마에서.
 * ========================================================================== */
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:mybody/main.dart' show MyBodyApp;
import 'package:mybody/src/api.dart';
import 'package:mybody/src/app_state.dart';
import 'package:mybody/src/scope.dart';
import 'package:mybody/src/screens/account.dart' show SignInScreen;
import 'package:mybody/src/screens/feedback.dart';
import 'package:mybody/src/screens/feedback_bubble.dart';
import 'package:mybody/src/screens/onboarding.dart' show OnboardingScreen;
import 'package:mybody/src/screens/settings.dart';
import 'package:mybody/src/screens/tester_welcome.dart' show markTesterWelcomeSeen;
import 'package:mybody/src/shell.dart';
import 'package:mybody/src/theme.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 1×1 PNG — 캡처 흉내가 돌려주는 그림.
final _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==');

const _profile = {
  'sex': 'male', 'age': 22, 'heightCm': 187, 'activityLevel': 'moderate',
  'trainingAge': 'novice', 'daysPerWeek': 4, 'mealsPerDay': 3,
};

final _bubble = find.byKey(const Key('feedback-bubble'));
final _dot = find.byKey(const Key('feedback-bubble-dot'));
final _send = find.byKey(const Key('feedback-send'));
final _text = find.byKey(const Key('feedback-text'));
final _thumbs = find.byWidgetPredicate(
    (w) => w.key is ValueKey<String> && (w.key as ValueKey<String>).value.startsWith('feedback-thumb-'));
final _switch = find.byKey(const Key('settings-feedback-bubble'));

/// 이번 시험의 서버 · 캡처 흉내.
class _Env {
  final sent = <Map<String, dynamic>>[];
  int captures = 0;
  late AppState app;
  late Api api;
}

void _phone(WidgetTester t, Size size, {double text = 1.0, EdgeInsets pad = EdgeInsets.zero}) {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1.0;
  final p = FakeViewPadding(left: pad.left, top: pad.top, right: pad.right, bottom: pad.bottom);
  t.view.padding = p;
  t.view.viewPadding = p;
  t.platformDispatcher.textScaleFactorTestValue = text;
  addTearDown(t.view.reset);
  addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
}

/// 앱과 같은 겹 — Scope > MaterialApp(navigatorObservers: [feedbackRoutes], builder: appFrame).
/// [keepPrefs] 면 저장소를 비우지 않습니다(앱을 다시 켠 것과 같음).
Future<_Env> _boot(
  WidgetTester t, {
  Size size = const Size(390, 844),
  double text = 1.0,
  EdgeInsets pad = EdgeInsets.zero,
  ThemeData? theme,
  bool guest = true,
  bool onboarded = true,
  bool scans = true,
  bool keepPrefs = false,
  Widget? home,
  TransitionBuilder? builder,
}) async {
  _phone(t, size, text: text, pad: pad);
  if (!keepPrefs) SharedPreferences.setMockInitialValues({});
  PackageInfo.setMockInitialValues(
      appName: 'Mybody', packageName: 'test.mybody', version: '0.2.17',
      buildNumber: '310', buildSignature: '');
  final env = _Env();
  env.api = Api(
    baseUrl: 'https://x.test',
    client: MockClient((req) async {
      final path = req.url.path.replaceFirst('/api', '');
      if (path == '/feedback') {
        env.sent.add((jsonDecode(req.body) as Map).cast<String, dynamic>());
        return http.Response.bytes(utf8.encode(jsonEncode({'ok': true, 'id': env.sent.length})), 200,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }
      return http.Response.bytes(utf8.encode(jsonEncode({'ok': true})), 200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    }),
  );
  final app = env.app = await AppState.boot();
  if (guest) app.store.set({'guest': true});
  if (onboarded) app.store.set({'onboarded': true, 'profile': _profile});
  markTesterWelcomeSeen(app);
  if (scans) {
    app.store.addScan({'id': 's1', 'weightKg': 86.7, 'smmKg': 38.0, 'bfmKg': 20.0,
        'pbfPct': 23.1, 'measuredAt': '2026-03-01T00:00:00.000Z'});
  }
  feedbackCapture = () async {
    env.captures++;
    return _png;
  };
  feedbackPick = (_) async => const [];
  await t.pumpWidget(Scope(
    state: app,
    api: env.api,
    onServerChange: (_) async {},
    child: MaterialApp(
      theme: theme ?? mbLight(),
      navigatorObservers: [feedbackRoutes],
      builder: builder ?? appFrame,
      home: home ?? const Shell(),
    ),
  ));
  await _settle(t);
  return env;
}

/// 몇 프레임 — 저장된 자리를 읽고, 흐려지며 나타나기(0.18초)가 끝나게. 셸에는 도는 것이
/// 있을 수 있어 pumpAndSettle 대신 시간을 정해 넘깁니다.
Future<void> _settle(WidgetTester t) async {
  await t.pump();
  await t.pump(const Duration(milliseconds: 300));
  await t.pump(const Duration(milliseconds: 300));
}

double _opacity(WidgetTester t) => t
    .widget<AnimatedOpacity>(find.ancestor(of: _bubble, matching: find.byType(AnimatedOpacity)).first)
    .opacity;

/// 보이고 눌리는가.
bool _shown(WidgetTester t) => _opacity(t) == 1.0 && _bubble.hitTestable().evaluate().isNotEmpty;

/// 숨었고 누름이 밑으로 지나가는가.
bool _hidden(WidgetTester t) => _opacity(t) == 0.0 && _bubble.hitTestable().evaluate().isEmpty;

/// 말풍선을 눌러 시트를 띄웁니다(찍기 → 시트).
Future<void> _tapBubble(WidgetTester t) async {
  await t.tap(_bubble);
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
  await t.pump(const Duration(milliseconds: 400));
  expect(_send, findsOneWidget, reason: '의견 시트가 떠야 합니다');
}

/// 보내고 시트가 닫히기까지 — 닫히면 말풍선이 다시 나타납니다.
Future<void> _sendAndClose(WidgetTester t) async {
  await t.tap(_send);
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
  await t.pump(const Duration(milliseconds: 400));
  expect(_send, findsNothing);
}

/// 화면 설정 톱니 → 설정 화면.
Future<void> _openSettings(WidgetTester t) async {
  await t.tap(find.byTooltip('설정'));
  await _settle(t);
  expect(find.byType(SettingsScreen), findsOneWidget);
}

/// 앱 전체 경계(캡처 경계 · 시험이 둔 바깥 경계)를 날 RGBA 로.
Future<Uint8List> _rgba(WidgetTester t, GlobalKey key) async {
  final ro = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  return (await t.runAsync(() async {
    final img = await ro.toImage(pixelRatio: 1.0);
    final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    img.dispose();
    return data!.buffer.asUint8List();
  }))!;
}

void main() {
  final origCapture = feedbackCapture;
  final origPick = feedbackPick;
  setUp(() => feedbackBubbleOn.value = true);
  tearDown(() {
    feedbackCapture = origCapture;
    feedbackPick = origPick;
    feedbackBubbleOn.value = true;
  });

  group('어디에나 뜬다', () {
    testWidgets('탭 화면 · 밀어 올린 화면(설정) — 오른쪽 가장자리 8px 안쪽 · 높이 58% · Navigator 바깥', (t) async {
      await _boot(t);
      expect(_shown(t), isTrue);
      final dot = t.getRect(_dot);
      expect(dot.width, 40);
      expect(dot.height, 40);
      expect(dot.right, 390 - 8, reason: '오른쪽 가장자리에서 8px');
      expect(dot.center.dy, closeTo(844 * 0.58, 0.5));
      expect(t.getRect(_bubble).size, const Size(48, 48), reason: '누르는 칸은 48px');
      expect(find.descendant(of: find.byType(Navigator), matching: _bubble), findsNothing,
          reason: 'Navigator 위(앱 맨 위)에 있어야 모든 화면에 뜹니다');

      await t.tap(find.widgetWithText(NavigationDestination, '식단'));
      await _settle(t);
      expect(_shown(t), isTrue, reason: '다른 탭에서도');

      await _openSettings(t);
      expect(_shown(t), isTrue, reason: '밀어 올린 화면에서도');
      expect(t.getRect(_dot), dot, reason: '화면이 바뀌어도 같은 자리');
      expect(t.takeException(), isNull);
    });

    testWidgets('로그인 화면 · 첫 설정 화면에도 뜬다', (t) async {
      await _boot(t, guest: false, onboarded: false, scans: false);
      expect(find.byType(SignInScreen), findsOneWidget);
      expect(_shown(t), isTrue, reason: '로그인 화면에서도');

      await _boot(t, onboarded: false, scans: false);
      expect(find.byType(OnboardingScreen), findsOneWidget);
      expect(_shown(t), isTrue, reason: '첫 설정 화면에서도');
      expect(t.takeException(), isNull);
    });

    /* main.dart 는 켜는 동안 MaterialApp 을 바로 내놓고, 준비되면 그 위에 Scope 를 씌웁니다.
       말풍선이 Navigator 를 GlobalKey 로 잡았다면 이때 켜는 중의 화면이 경로로 남아 셸이
       영영 안 뜹니다 — 지켜보는 쪽(feedbackRoutes)은 새 Navigator 로 옮겨 붙어야 합니다. */
    testWidgets('진짜 앱(main.dart) — 켜는 중엔 숨고, 준비되면 로그인 화면 옆에 뜨고 눌린다', (t) async {
      _phone(t, const Size(390, 844));
      SharedPreferences.setMockInitialValues({'mybody.server.v1': 'https://x.test'});
      PackageInfo.setMockInitialValues(
          appName: 'Mybody', packageName: 'test.mybody', version: '0.2.17',
          buildNumber: '310', buildSignature: '');
      var captures = 0;
      feedbackCapture = () async {
        captures++;
        return _png;
      };
      await t.pumpWidget(const MyBodyApp());
      expect(find.byType(Shell), findsNothing, reason: '켜는 중');
      expect(_hidden(t), isTrue, reason: '켜는 중에는 보낼 곳(Scope)이 없습니다');
      for (var i = 0; i < 30 && find.byType(Shell).evaluate().isEmpty; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(Shell), findsOneWidget);
      await _settle(t);
      expect(find.byType(SignInScreen), findsOneWidget);
      expect(_shown(t), isTrue);
      expect(feedbackRoutes.navigator, isNotNull, reason: '새 Navigator 에 붙어 있어야 합니다');
      expect(feedbackScreenName(feedbackRoutes.pageContext!), '계정', reason: '로그인 화면의 앱바 제목');

      await _tapBubble(t);
      expect(captures, 1);
      expect(_thumbs, findsOneWidget);
      await t.tapAt(const Offset(20, 20));   // 바깥을 눌러 닫기
      await _settle(t);
      expect(_send, findsNothing);
      expect(_shown(t), isTrue);
      expect(t.takeException(), isNull);
    });
  });

  group('숨는 때', () {
    testWidgets('Scope 가 없으면(앱이 켜지는 중) 저장된 값을 읽은 뒤에도 숨어 있다 — 보낼 곳이 없다', (t) async {
      _phone(t, const Size(390, 844));
      SharedPreferences.setMockInitialValues({});
      await t.pumpWidget(MaterialApp(
        navigatorObservers: [feedbackRoutes],
        builder: appFrame,
        home: const Scaffold(body: Center(child: CircularProgressIndicator())),
      ));
      await _settle(t);
      expect(feedbackBubbleOn.value, isTrue, reason: '켜져 있고 읽기도 끝났지만');
      expect(_hidden(t), isTrue);
    });

    testWidgets('키보드가 올라오면 흐려지며 숨고(누름은 밑으로), 내려가면 돌아온다', (t) async {
      await _boot(t);
      expect(_shown(t), isTrue);
      t.view.viewInsets = const FakeViewPadding(bottom: 300);
      await t.pump();
      await t.pump(const Duration(milliseconds: 60));
      expect(_opacity(t), 0.0, reason: '흐려지기 시작');
      expect(_bubble.hitTestable(), findsNothing, reason: '숨는 동안부터 눌리지 않습니다');
      await t.pump(const Duration(milliseconds: 300));
      expect(_hidden(t), isTrue);
      final o = t.widget<AnimatedOpacity>(find.ancestor(of: _bubble, matching: find.byType(AnimatedOpacity)).first);
      expect(o.duration, lessThanOrEqualTo(const Duration(milliseconds: 300)), reason: '끝이 있는 짧은 애니메이션');

      t.view.viewInsets = FakeViewPadding.zero;
      await _settle(t);
      expect(_shown(t), isTrue);
    });
  });

  group('누르면', () {
    testWidgets('지금 화면을 찍어 붙인 시트 — 화면 이름은 홈 · 식단 · 설정(밀어 올린 화면), 다이얼로그 위에선 그 밑 화면',
        (t) async {
      final env = await _boot(t);

      await _tapBubble(t);
      expect(env.captures, 1, reason: '누르는 순간의 화면을 찍습니다');
      expect(_thumbs, findsOneWidget, reason: '찍은 화면이 이미 붙어 있습니다');
      expect(_hidden(t), isTrue, reason: '시트가 떠 있는 동안은 숨습니다');
      expect(feedbackBusy.value, isTrue);
      await _sendAndClose(t);
      expect(env.sent.single['screen'], '홈');
      expect((env.sent.single['images'] as List), hasLength(1));
      expect(feedbackBusy.value, isFalse);
      await _settle(t);
      expect(_shown(t), isTrue, reason: '시트가 닫히면 돌아옵니다');

      await t.tap(find.widgetWithText(NavigationDestination, '식단'));
      await _settle(t);
      await _tapBubble(t);
      await t.enterText(_text, '식단에서');
      await t.pump();
      await _sendAndClose(t);
      expect(env.sent.last['screen'], '식단');
      expect(env.sent.last['text'], '식단에서');

      await _openSettings(t);
      await _settle(t);
      await _tapBubble(t);
      await _sendAndClose(t);
      expect(env.sent.last['screen'], '설정', reason: '밀어 올린 화면의 앱바 제목');

      /* 다이얼로그(PopupRoute)는 화면이 아닙니다 — 그 밑의 설정으로. */
      showDialog<void>(
          context: feedbackRoutes.navigator!.context,
          builder: (_) => const AlertDialog(content: Text('확인할까요?')));
      await _settle(t);
      expect(find.text('확인할까요?'), findsOneWidget);
      expect(_shown(t), isTrue, reason: '다이얼로그 위에서도 떠 있습니다');
      await _tapBubble(t);
      await _sendAndClose(t);
      expect(env.sent.last['screen'], '설정');
      expect(env.sent, hasLength(4));
      expect(t.takeException(), isNull);
    });

    testWidgets('두 번 빨리 눌러도 시트는 한 장, 찍기도 한 번', (t) async {
      final env = await _boot(t);
      await t.tap(_bubble);
      await t.tap(_bubble, warnIfMissed: false);
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      await t.pump(const Duration(milliseconds: 400));
      expect(env.captures, 1);
      expect(_send, findsOneWidget);
    });

    /* 화면이 뜨는 중에 누르면 다 뜰 때까지 기다렸다 찍습니다. 그 사이 시트가 **또** 올라오면
       (셸이 /me 를 기다렸다 띄우는 테스터 인사처럼) 그것도 다 뜬 뒤에 — 처음 본 화면만
       기다리면 막 올라오기 시작한 시트의 첫 프레임을 찍고 그 위에 의견 시트를 띄웁니다. */
    testWidgets('화면이 뜨는 중에 누르고 그 사이 시트가 또 올라와도 — 다 뜬 뒤에 찍는다', (t) async {
      final env = await _boot(t);
      Route<dynamic>? topAtCapture;
      bool? settledAtCapture;
      feedbackCapture = () async {
        env.captures++;
        final r = topAtCapture = feedbackRoutes.top;
        settledAtCapture = r is TransitionRoute && !r.animation!.isAnimating;
        return _png;
      };
      await t.tap(find.byTooltip('설정'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));
      final page = feedbackRoutes.top;
      expect(page is TransitionRoute && page.animation!.isAnimating, isTrue, reason: '설정이 뜨는 중');
      await t.tap(_bubble);
      await t.pump(const Duration(milliseconds: 200));
      await t.pump(const Duration(milliseconds: 150));
      expect(env.captures, 0, reason: '다 뜰 때까지 기다립니다');
      expect(page is TransitionRoute && page.animation!.isAnimating, isTrue, reason: '설정이 아직 뜨는 중');
      /* 설정이 다 뜨기 직전에 시트가 올라옵니다 — 설정이 다 뜬 때에 시트는 아직 반쯤입니다. */
      unawaited(showModalBottomSheet<void>(
          context: feedbackRoutes.navigator!.context,
          builder: (_) => const SizedBox(height: 200, child: Center(child: Text('인사')))));
      await t.pump();
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(env.captures, 1);
      expect(topAtCapture, isA<ModalBottomSheetRoute<void>>(), reason: '나중에 올라온 시트까지');
      expect(settledAtCapture, isTrue, reason: '반쯤 올라온 시트를 찍지 않습니다');
      expect(_send, findsOneWidget);
      await _sendAndClose(t);
      expect(env.sent.single['screen'], '설정', reason: '시트 밑의 화면');
      expect(t.takeException(), isNull);
    });

    /* 캡처 경계는 창 전체입니다 — 말풍선이 그 안에 있으면 보낸 화면마다 찍혀 밑의 내용을
       가립니다. 모양(경계 안에 말풍선이 없음)과 그림(켜 있을 때와 꺼 있을 때 같음) 둘 다
       봅니다. 대조: 경계 **밖**까지 찍는 시험용 경계에서는 둘이 달라야 비교가 헛돌지 않습니다. */
    testWidgets('말풍선은 캡처 경계 밖 — 찍힌 그림은 말풍선이 켜 있을 때와 꺼 있을 때 같다', (t) async {
      final outer = GlobalKey();
      await _boot(
        t,
        home: Scaffold(appBar: AppBar(title: const Text('홈')), body: const Center(child: Text('찍힐 화면'))),
        builder: (c, child) => RepaintBoundary(key: outer, child: appFrame(c, child)),
      );
      expect(_shown(t), isTrue);
      final boundary = find.byKey(kAppCaptureKey);
      expect(boundary, findsOneWidget);
      expect(find.descendant(of: boundary, matching: _bubble), findsNothing, reason: '경계 안에 없어야 합니다');
      expect(find.descendant(of: boundary, matching: find.byType(Navigator)), findsOneWidget,
          reason: '경계는 여전히 모든 화면(Navigator)을 감쌉니다');
      final layer = find.byType(FeedbackBubbleLayer);
      expect(find.descendant(of: layer, matching: boundary), findsOneWidget);
      expect(find.descendant(of: layer, matching: _bubble), findsOneWidget, reason: '경계의 형제');

      final png = await t.runAsync(captureAppScreen);
      expect(png, isNotNull, reason: '말풍선이 떠 있어도 캡처는 됩니다');
      final bd = ByteData.sublistView(png!);
      expect([bd.getUint32(16), bd.getUint32(20)], [390, 844], reason: '창 전체');

      final withBubble = await _rgba(t, kAppCaptureKey);
      final outerWith = await _rgba(t, outer);
      await setFeedbackBubbleOn(false);
      await _settle(t);
      expect(_hidden(t), isTrue);
      final without = await _rgba(t, kAppCaptureKey);
      final outerWithout = await _rgba(t, outer);
      expect(withBubble, orderedEquals(without), reason: '찍힌 그림에 말풍선이 없습니다');
      expect(outerWith, isNot(orderedEquals(outerWithout)),
          reason: '대조 — 경계 밖까지 찍으면 말풍선이 보여야 합니다(그려지고 있음)');
    });
  });

  group('끌기', () {
    testWidgets('끌면 따라오고, 놓으면 가까운 쪽에 붙는다 — 다시 켜도 그 자리', (t) async {
      await _boot(t);
      final start = t.getCenter(_dot);
      final gesture = await t.startGesture(start);
      await gesture.moveBy(const Offset(-100, -50));
      await t.pump();
      await gesture.moveBy(const Offset(-160, -100));
      await t.pump();
      expect(t.getCenter(_dot).dx, closeTo(start.dx - 260, 0.5), reason: '누른 자리부터 손을 따라옵니다');
      expect(t.getCenter(_dot).dy, closeTo(start.dy - 150, 0.5));
      await gesture.up();
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      final mid = t.getCenter(_dot).dx;
      expect(mid, lessThan(start.dx - 260), reason: '놓으면 미끄러지며 붙습니다(중간)');
      expect(mid, greaterThan(28));
      await _settle(t);
      final dot = t.getRect(_dot);
      expect(dot.left, 8, reason: '왼쪽(가까운 쪽) 가장자리에서 8px');
      expect(dot.center.dy, closeTo(start.dy - 150, 0.5), reason: '높이는 놓은 그대로');

      final sp = await SharedPreferences.getInstance();
      expect(sp.getString(kFeedbackBubbleSideKey), 'left');
      expect(sp.getDouble(kFeedbackBubbleYKey), closeTo((start.dy - 150) / 844, 1e-6));

      /* 다시 켜기 — 트리를 통째로 내리고 저장소는 그대로 둔 채 새로 세웁니다. */
      await t.pumpWidget(const SizedBox());
      await _boot(t, keepPrefs: true);
      expect(_shown(t), isTrue);
      expect(t.getRect(_dot), dot, reason: '다시 켜도 옮긴 자리');

      /* 가운데를 조금 넘겨 놓으면 반대쪽(오른쪽)으로. */
      await t.drag(_bubble, const Offset(190, 0));
      await _settle(t);
      expect(t.getRect(_dot).right, 390 - 8);
      expect(sp.getString(kFeedbackBubbleSideKey), 'right');
    });

    /* 자리는 비율로 적으므로 돌려도(가로 · 세로) 같은 쪽 · 같은 느낌의 높이 — 가로 화면은
       낮아서 범위 안으로 당겨지고, 그때도 「인바디」 · 탭바 · 앱바를 덮지 않습니다.
       다시 세우면 원래 자리로 돌아옵니다(당겨진 자리를 적어 두지 않음). */
    testWidgets('돌려도(가로 ↔ 세로) 같은 쪽 · 범위 안, 덮지 않고, 다시 세우면 원래 자리', (t) async {
      await _boot(t);
      await t.drag(_bubble, const Offset(-300, 150));
      await _settle(t);
      final portrait = t.getRect(_dot);
      expect(portrait.left, 8);

      t.view.physicalSize = const Size(844, 390);
      await _settle(t);
      final b = t.getRect(_bubble);
      expect(t.getRect(_dot).left, 8, reason: '같은 쪽(왼쪽)');
      for (final (name, f) in [
        ('「인바디」', find.byType(FloatingActionButton)),
        ('탭바', find.byType(NavigationBar)),
        ('앱바', find.byType(AppBar)),
      ]) {
        expect(b.overlaps(t.getRect(f)), isFalse, reason: '가로 — $name 와 겹침: 말풍선 $b · $name ${t.getRect(f)}');
      }
      expect(b.bottom, lessThanOrEqualTo(390));

      t.view.physicalSize = const Size(390, 844);
      await _settle(t);
      expect(t.getRect(_dot), portrait, reason: '다시 세우면 원래 자리');
      expect(t.takeException(), isNull);
    });

    for (final (size, pad) in const [
      (Size(360, 640), EdgeInsets.zero),
      (Size(430, 932), EdgeInsets.zero),
      (Size(360, 640), EdgeInsets.only(top: 24, bottom: 48)),
      (Size(430, 932), EdgeInsets.only(top: 47, bottom: 34)),
    ]) {
      testWidgets(
          '${size.width.toInt()}×${size.height.toInt()} 안전 영역 ${pad.top.toInt()}/${pad.bottom.toInt()} — '
          '「인바디」 · 탭바 · 앱바를 덮지 않는다(처음 자리 · 끝까지 끌어도)', (t) async {
        await _boot(t, size: size, pad: pad);
        final fab = find.byType(FloatingActionButton);
        expect(fab, findsOneWidget, reason: '측정이 있으면 홈에 「인바디」 단추');
        final screen = Offset.zero & size;
        void clear(String when) {
          final b = t.getRect(_bubble);
          for (final (name, f) in [
            ('「인바디」', fab),
            ('탭바', find.byType(NavigationBar)),
            ('앱바', find.byType(AppBar)),
          ]) {
            final r = t.getRect(f);
            expect(b.overlaps(r), isFalse, reason: '$when — $name 와 겹침: 말풍선 $b · $name $r');
          }
          expect(b.top, greaterThanOrEqualTo(pad.top), reason: '$when — 상태 막대 밑으로');
          expect(b.bottom, lessThanOrEqualTo(size.height - pad.bottom), reason: '$when — 시스템 막대 위로');
          expect(screen.contains(b.topLeft) && screen.contains(b.bottomRight - const Offset(0.1, 0.1)), isTrue,
              reason: '$when — 화면 안');
        }

        clear('처음 자리');
        await t.drag(_bubble, const Offset(0, 2000));
        await _settle(t);
        clear('맨 아래로 끌어 놓은 뒤');
        await t.drag(_bubble, const Offset(-40, -4000));
        await _settle(t);
        clear('맨 위로 끌어 놓은 뒤');
        await t.drag(_bubble, const Offset(-1000, 2000));
        await _settle(t);
        clear('왼쪽 맨 아래로 끌어 놓은 뒤');
        expect(t.takeException(), isNull);
      });
    }
  });

  group('길게 누르기 · 설정', () {
    testWidgets('길게 누르면 「의견 버튼 숨기기」 → 숨고 한 줄 안내, 다시 켜도 숨은 채 · 설정 스위치로 곧바로 돌아온다',
        (t) async {
      await _boot(t);
      await t.longPress(_bubble);
      await _settle(t);
      final hide = find.byKey(const Key('feedback-bubble-hide'));
      expect(hide, findsOneWidget);
      expect(find.text('의견 버튼 숨기기'), findsOneWidget);
      /* 메뉴는 말풍선 옆(안쪽)에 — 말풍선이 메뉴를 가리지 않게. */
      expect(t.getRect(find.byType(PopupMenuItem<String>)).right, lessThanOrEqualTo(t.getRect(_bubble).left));
      await t.tap(hide);
      await _settle(t);
      expect(_hidden(t), isTrue);
      expect(find.text('설정 → 도움말에서 다시 켤 수 있어요'), findsOneWidget);
      final sp = await SharedPreferences.getInstance();
      expect(sp.getBool(kFeedbackBubbleOnKey), isFalse);

      /* 다시 켜도 숨은 채. */
      await t.pumpWidget(const SizedBox());
      feedbackBubbleOn.value = true;   // 기억은 저장소에만 — 새로 켠 앱처럼
      await _boot(t, keepPrefs: true);
      expect(_hidden(t), isTrue, reason: '숨긴 것은 다시 켜도 숨은 채');

      /* 설정 → 도움말의 스위치(같은 값)로 되돌리면 이 화면 옆에 곧바로. */
      await _openSettings(t);
      await t.scrollUntilVisible(_switch, 300, scrollable: find.byType(Scrollable).first);
      await _settle(t);
      expect(t.widget<SwitchListTile>(_switch).value, isFalse);
      await t.tap(_switch);
      await _settle(t);
      expect(t.widget<SwitchListTile>(_switch).value, isTrue);
      expect(_shown(t), isTrue, reason: '뒤로 가기 전에도 곧바로');
      expect(sp.getBool(kFeedbackBubbleOnKey), isTrue);

      /* 스위치로 끄면 말풍선도 곧바로. */
      await t.tap(_switch);
      await _settle(t);
      expect(_hidden(t), isTrue);
      expect(sp.getBool(kFeedbackBubbleOnKey), isFalse);
      expect(t.takeException(), isNull);
    });

    testWidgets('메뉴를 그냥 닫으면 아무것도 안 바뀐다', (t) async {
      await _boot(t);
      await t.longPress(_bubble);
      await _settle(t);
      await t.tapAt(const Offset(20, 300));
      await _settle(t);
      expect(find.byKey(const Key('feedback-bubble-hide')), findsNothing);
      expect(_shown(t), isTrue);
      expect(feedbackBubbleOn.value, isTrue);
    });

    /* 말풍선은 Navigator 위라 메뉴의 가림막이 말풍선을 못 덮습니다 — 메뉴가 떠 있는 동안
       말풍선을 누르면 의견 시트가 메뉴 위에 쌓이고, 또 길게 누르면 메뉴가 두 장이 됐습니다. */
    testWidgets('메뉴가 떠 있는 동안 말풍선은 아무것도 안 한다 — 시트도, 두 번째 메뉴도, 끌기도', (t) async {
      final env = await _boot(t);
      final at = t.getRect(_dot);
      await t.longPress(_bubble);
      await _settle(t);
      final hide = find.byKey(const Key('feedback-bubble-hide'));
      expect(hide, findsOneWidget);

      await t.tap(_bubble);
      await _settle(t);
      expect(env.captures, 0);
      expect(_send, findsNothing, reason: '메뉴 위에 의견 시트가 쌓이지 않습니다');
      await t.longPress(_bubble);
      await _settle(t);
      expect(hide, findsOneWidget, reason: '메뉴는 한 장');
      await t.drag(_bubble, const Offset(-200, -100));
      await _settle(t);
      expect(t.getRect(_dot), at, reason: '메뉴만 옛 자리에 남지 않게 — 안 움직입니다');

      /* 메뉴를 닫으면 다시 평소대로. */
      await t.tapAt(const Offset(20, 300));
      await _settle(t);
      expect(hide, findsNothing);
      await _tapBubble(t);
      expect(env.captures, 1);
      expect(t.takeException(), isNull);
    });

    testWidgets('스크린리더 — 「의견 보내기」 단추 · 길게 누르기 힌트, 숨으면 트리에서 빠진다', (t) async {
      final h = t.ensureSemantics();
      await _boot(t);
      expect(
          t.getSemantics(_bubble),
          isSemantics(
            label: '의견 보내기',
            isButton: true,
            hasTapAction: true,
            hasLongPressAction: true,
            onLongPressHint: '의견 버튼 숨기기',
          ));
      expect(find.semantics.byLabel('의견 보내기'), findsOne, reason: '실제 시맨틱 트리에 하나');
      await setFeedbackBubbleOn(false);
      await _settle(t);
      expect(find.semantics.byLabel('의견 보내기'), findsNothing, reason: '안 보이는 단추를 짚으면 안 됩니다');
      h.dispose();
    });
  });

  group('360px · 글자 1.3배', () {
    for (final (name, theme) in [('밝게', mbLight), ('어둡게', mbDark)]) {
      testWidgets('$name — 넘치지 않고, 색은 테마에서(표면 0.9 · 가는 테두리 · 그림자 · 주색 아이콘)', (t) async {
        await _boot(t, size: const Size(360, 640), text: 1.3, theme: theme());
        expect(t.takeException(), isNull);
        expect(_shown(t), isTrue);
        final b = t.getRect(_bubble);
        expect(b.left, greaterThanOrEqualTo(0));
        expect(b.right, lessThanOrEqualTo(360));
        expect(b.bottom, lessThanOrEqualTo(640));
        expect(b.overlaps(t.getRect(find.byType(FloatingActionButton))), isFalse);
        expect(b.overlaps(t.getRect(find.byType(NavigationBar))), isFalse);

        final scheme = Theme.of(t.element(_dot)).colorScheme;
        expect(Theme.of(t.element(_dot)).brightness, theme().brightness);
        final deco = t.widget<DecoratedBox>(_dot).decoration as BoxDecoration;
        expect(deco.shape, BoxShape.circle);
        expect(deco.color, scheme.surface.withValues(alpha: 0.9));
        expect((deco.border as Border).top.color, scheme.outlineVariant);
        expect((deco.border as Border).top.width, lessThanOrEqualTo(1.0), reason: '가는 선');
        expect(deco.boxShadow, isNotEmpty);
        final icon = t.widget<Icon>(find.descendant(of: _dot, matching: find.byType(Icon)));
        expect(icon.icon, LucideIcons.messageSquare);
        expect(icon.size, 20);
        expect(icon.color, scheme.primary);

        /* 설정 화면(글자 1.3배)의 도움말 카드도 넘치지 않습니다. */
        await _openSettings(t);
        await t.scrollUntilVisible(_switch, 300, scrollable: find.byType(Scrollable).first);
        await _settle(t);
        expect(t.takeException(), isNull);
        final r = t.getRect(_switch);
        expect(r.right, lessThanOrEqualTo(360));
      });
    }
  });
}
