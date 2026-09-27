/* =============================================================================
 * feedback_bubble_test.dart — 화면 가장자리에 늘 떠 있는 「의견 보내기」 말풍선
 *
 * 주인의 말: "의견보내기는 설정 드가서 하는게 아니라 앱 어딘가에 상시 떠있는 버튼으로",
 * 그리고 피드백 42 — "꾹 누르면 드래그로 위치 바꿀 수 있게 / 화면 가장자리 아무데로나 /
 * 디폴트 위치를 인바디 사진올리기 버튼 바로위로 / 꾹 눌렀을때 화면 하단 중앙에 x아이콘 …
 * 갖다대면 없어지게 / 테스트기간에는 '테스트 기간에는 없앨수없어요' / 이후에는 '다시
 * 키려면 설정탭에서' / 설정에서 의견보내기 아이콘 표시 끄고킬수있게". 그래서 못 박는 것:
 *
 *   · 어디에나   탭 화면 · 밀어 올린 화면(설정) · 로그인 · 첫 설정 화면 모두에 뜬다.
 *                진짜 앱(main.dart)에서도 — 켜는 중(Scope 없음)에는 안 보이고, 준비되면 뜬다.
 *                Navigator 바깥(위)에 있다.
 *   · 처음 자리   오른쪽 가장자리, 홈 「인바디」 단추 바로 위(12px 틈 · 오른쪽 끝 나란히) —
 *                360×640 · 390×844 · 430×932(안전 영역 있음 · 없음)의 진짜 홈에서, 단추 ·
 *                탭바와 겹치지 않는다.
 *   · 숨는 때    키보드가 올라와 있을 때 · 의견 시트가 떠 있을 때(찍는 중부터). 흐려지며.
 *   · 누르면     지금 화면을 찍어 붙인 시트, 화면 이름은 홈 · 식단 · 설정(밀어 올린 화면)
 *                · 다이얼로그 위에서는 그 밑의 화면.
 *   · 안 찍힌다   캡처 경계 안에 말풍선이 없고, 켜 있을 때와 꺼 있을 때 찍힌 그림이 같다.
 *   · 꾹 눌러야   그냥 끌면 안 움직이고(시트도 안 뜸), 꾹 누르면 들린다(커짐 · 떨림).
 *   · 가장자리    놓으면 네 가장자리 중 가장 가까운 곳 — 그 가장자리를 따라서는 놓은 그대로,
 *                안전 영역 안, 다시 켜도 · 돌려도 그 자리. 옛 {쪽, 높이} 는 같은 높이로 옮긴다.
 *   · X          들린 동안만 아래 가운데에. 닿으면 커지고 붉어지고 한 번 떨린다. 놓으면 —
 *                시험 기간: 「테스트 기간에는 없앨 수 없어요」 · 들기 전 자리로.
 *                시험 끝: 사라지고 「다시 켜려면 설정 → 도움말에서 켜세요」.
 *   · 설정       시험 기간에는 켜진 채 잠김(「테스트 기간에는 켜 둡니다」), 옛 판에서 꺼 둔
 *                기기에도 말풍선이 뜬다. 시험이 끝나면 평소처럼 켜고 끈다.
 *   · 스크린리더  「의견 보내기」 단추(누르기만) · 숨으면 트리에서 빠진다.
 *   · 360px · 글자 1.3배 · 밝게/어둡게 — 넘치지 않고 색은 테마에서. 애니메이션은 끝이 있다.
 * ========================================================================== */
import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
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
import 'package:mybody/src/update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 1×1 PNG — 캡처 흉내가 돌려주는 그림.
final _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==');

const _profile = {
  'sex': 'male', 'age': 22, 'heightCm': 187, 'activityLevel': 'moderate',
  'trainingAge': 'novice', 'daysPerWeek': 4, 'mealsPerDay': 3,
};

const _locked = '테스트 기간에는 없앨 수 없어요';
const _removed = '다시 켜려면 설정 → 도움말에서 켜세요';

final _bubble = find.byKey(const Key('feedback-bubble'));
final _dot = find.byKey(const Key('feedback-bubble-dot'));
final _bin = find.byKey(const Key('feedback-bubble-bin'));
final _send = find.byKey(const Key('feedback-send'));
final _text = find.byKey(const Key('feedback-text'));
final _thumbs = find.byWidgetPredicate(
    (w) => w.key is ValueKey<String> && (w.key as ValueKey<String>).value.startsWith('feedback-thumb-'));
final _switch = find.byKey(const Key('settings-feedback-bubble'));
final _fab = find.byType(FloatingActionButton);

/// 이번 시험의 서버 · 캡처 흉내.
class _Env {
  final sent = <Map<String, dynamic>>[];
  int captures = 0;
  late AppState app;
  late Api api;

  /// GET /api/version 의 testing — null 이면 칸을 안 싣습니다(옛 서버).
  Object? testing;

  /// Scope 에 건 새 판 확인기. [_boot] 에 testing 을 안 주면 없습니다(확인기 없음 = 시험 중).
  UpdateCheck? update;
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
/// [testing] 을 주면 그 값을 답하는 서버에 물은 새 판 확인기를 Scope 에 겁니다.
/// [startUpdate] 가 거짓이면 확인기를 만들기만 합니다(이 기기의 지난 답을 아직 못 읽음).
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
  Map<String, Object> prefs = const {},
  Object? testing,
  bool startUpdate = true,
  Widget? home,
  TransitionBuilder? builder,
}) async {
  _phone(t, size, text: text, pad: pad);
  if (!keepPrefs) SharedPreferences.setMockInitialValues(prefs);
  PackageInfo.setMockInitialValues(
      appName: 'Mybody', packageName: 'test.mybody', version: '0.2.17',
      buildNumber: '310', buildSignature: '');
  final env = _Env()..testing = testing;
  http.Response json(Object body) => http.Response.bytes(utf8.encode(jsonEncode(body)), 200,
      headers: {'content-type': 'application/json; charset=utf-8'});
  env.api = Api(
    baseUrl: 'https://x.test',
    client: MockClient((req) async {
      final path = req.url.path.replaceFirst('/api', '');
      if (path == '/feedback') {
        env.sent.add((jsonDecode(req.body) as Map).cast<String, dynamic>());
        return json({'ok': true, 'id': env.sent.length});
      }
      if (path == '/version') {
        return json({'ok': true, 'latest': {}, 'min': '', if (env.testing != null) 'testing': env.testing});
      }
      return json({'ok': true});
    }),
  );
  if (testing != null) {
    final u = env.update = UpdateCheck(api: env.api, platform: TargetPlatform.android, web: false);
    if (startUpdate) await t.runAsync(u.start);
  }
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
    update: env.update,
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

/// 서버가 답하는 testing 을 바꾸고 확인기가 새로 묻게 합니다.
Future<void> _serverSays(WidgetTester t, _Env env, Object? testing) async {
  env.testing = testing;
  await t.runAsync(() => env.update!.check(force: true));
  await _settle(t);
}

/// 몇 프레임 — 저장된 자리를 읽고, 흐려지며 나타나기(0.18초) · 붙기(0.22초)가 끝나게. 셸에는
/// 도는 것이 있을 수 있어 pumpAndSettle 대신 시간을 정해 넘깁니다.
Future<void> _settle(WidgetTester t) async {
  await t.pump();
  await t.pump(const Duration(milliseconds: 300));
  await t.pump(const Duration(milliseconds: 300));
}

double _opacityOf(WidgetTester t, Finder f) =>
    t.widget<AnimatedOpacity>(find.ancestor(of: f, matching: find.byType(AnimatedOpacity)).first).opacity;

double _opacity(WidgetTester t) => _opacityOf(t, _bubble);

/// 보이고 눌리는가.
bool _shown(WidgetTester t) => _opacity(t) == 1.0 && _bubble.hitTestable().evaluate().isNotEmpty;

/// 숨었고 누름이 밑으로 지나가는가.
bool _hidden(WidgetTester t) => _opacity(t) == 0.0 && _bubble.hitTestable().evaluate().isEmpty;

/// X 가 떠 있나.
bool _binUp(WidgetTester t) => _opacityOf(t, _bin) == 1.0;

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

Future<void> _scrollToSwitch(WidgetTester t) async {
  await t.scrollUntilVisible(_switch, 300, scrollable: find.byType(Scrollable).first);
  await _settle(t);
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

/// 폰의 떨림(HapticFeedback)을 받아 적습니다 — 'HapticFeedbackType.mediumImpact' 꼴.
List<String> _haptics(WidgetTester t) {
  final calls = <String>[];
  t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (c) async {
    if (c.method == 'HapticFeedback.vibrate') calls.add('${c.arguments}');
    return null;
  });
  addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
  return calls;
}

/// 말풍선을 쥔 손가락.
class _Hand {
  _Hand(this.g, this.at);
  final TestGesture g;
  Offset at;

  /// 몇 걸음에 나눠 [to] 까지 — 손가락처럼.
  Future<void> to(WidgetTester t, Offset to, {int steps = 4}) async {
    final from = at;
    for (var i = 1; i <= steps; i++) {
      await g.moveTo(Offset.lerp(from, to, i / steps)!);
      await t.pump(const Duration(milliseconds: 16));
    }
    at = to;
  }

  Future<void> up(WidgetTester t) async {
    await g.up();
    await _settle(t);
  }
}

/// 말풍선 가운데를 꾹(kBubbleLongPress 넘게) — 들린 채로 돌려줍니다.
Future<_Hand> _lift(WidgetTester t) async {
  final c = t.getCenter(_bubble);
  final g = await t.startGesture(c);
  await t.pump(kBubbleLongPress + const Duration(milliseconds: 50));
  await t.pump(const Duration(milliseconds: 200));
  return _Hand(g, c);
}

/// 꾹 눌러 [to] 에 놓기.
Future<void> _moveBubble(WidgetTester t, Offset to) async {
  final h = await _lift(t);
  await h.to(t, to);
  expect(t.getCenter(_bubble).dx, closeTo(to.dx, 0.5), reason: '들린 동안 손가락을 따라옵니다');
  expect(t.getCenter(_bubble).dy, closeTo(to.dy, 0.5));
  await h.up(t);
}

Future<FeedbackBubblePos?> _saved() async {
  final raw = (await SharedPreferences.getInstance()).getString(kFeedbackBubblePosKey);
  return raw == null ? null : FeedbackBubblePos.fromJson(jsonDecode(raw));
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
    testWidgets('탭 화면 · 밀어 올린 화면(설정) — 같은 자리 · Navigator 바깥', (t) async {
      await _boot(t);
      expect(_shown(t), isTrue);
      final dot = t.getRect(_dot);
      expect(dot.size, const Size(40, 40));
      expect(t.getRect(_bubble).size, const Size(48, 48), reason: '누르는 칸은 48px');
      expect(find.descendant(of: find.byType(Navigator), matching: _bubble), findsNothing,
          reason: 'Navigator 위(앱 맨 위)에 있어야 모든 화면에 뜹니다');

      await t.tap(find.widgetWithText(NavigationDestination, '식단'));
      await _settle(t);
      expect(_shown(t), isTrue, reason: '다른 탭에서도');
      expect(t.getRect(_dot), dot);

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

  /* 주인의 말: "디폴트 위치를 인바디 사진올리기 버튼 바로위로". 진짜 홈(셸 · 측정 있음)에서
     「인바디」 단추를 찾아 그 위 12px · 오른쪽 끝 나란히 — 단추도 탭바도 덮지 않습니다. */
  group('처음 자리 — 「인바디」 단추 바로 위', () {
    for (final (size, pad) in const [
      (Size(360, 640), EdgeInsets.zero),
      (Size(390, 844), EdgeInsets.zero),
      (Size(430, 932), EdgeInsets.zero),
      (Size(360, 640), EdgeInsets.only(top: 24, bottom: 48)),
      (Size(430, 932), EdgeInsets.only(top: 47, bottom: 34)),
    ]) {
      testWidgets(
          '${size.width.toInt()}×${size.height.toInt()} 안전 영역 ${pad.top.toInt()}/${pad.bottom.toInt()}',
          (t) async {
        await _boot(t, size: size, pad: pad);
        expect(_shown(t), isTrue);
        expect(_fab, findsOneWidget, reason: '측정이 있으면 홈에 「인바디」 단추');
        expect(find.descendant(of: _fab, matching: find.text('인바디')), findsOneWidget);
        final fab = t.getRect(_fab), nav = t.getRect(find.byType(NavigationBar));
        final dot = t.getRect(_dot), hit = t.getRect(_bubble);
        expect(dot.bottom, closeTo(fab.top - 12, 0.5), reason: '단추 위 끝보다 12px 위: 말풍선 $dot · 단추 $fab');
        expect(dot.right, closeTo(fab.right, 0.5), reason: '오른쪽 끝이 단추와 나란히');
        expect(dot.left, greaterThanOrEqualTo(fab.left), reason: '단추 바로 위(단추 폭 안)');
        for (final (name, r) in [('「인바디」', fab), ('탭바', nav), ('앱바', t.getRect(find.byType(AppBar)))]) {
          expect(hit.overlaps(r), isFalse, reason: '$name 와 겹침: 말풍선 $hit · $name $r');
        }
        expect(hit.top, greaterThanOrEqualTo(pad.top));
        expect(hit.right, lessThanOrEqualTo(size.width));
        expect(await _saved(), isNull, reason: '처음 자리는 적어 두지 않습니다 — 화면마다 단추 위로 셉니다');
        expect(t.takeException(), isNull);
      });
    }

    test('계산 — 오른쪽 가장자리 16px, 아래에서 탭바 80 + 여백 16 + 단추 56 + 틈 12 + 반지름 20', () {
      expect(feedbackBubbleHome(const Size(390, 844), EdgeInsets.zero), const Offset(390 - 36, 844 - 184));
      expect(feedbackBubbleHome(const Size(430, 932), const EdgeInsets.only(top: 47, bottom: 34)),
          const Offset(430 - 36, 932 - 34 - 184));
      expect(feedbackBubbleCenter(null, const Size(360, 640), EdgeInsets.zero),
          feedbackBubbleHome(const Size(360, 640), EdgeInsets.zero), reason: '저장된 자리가 없으면 처음 자리');
      /* 아주 낮은 화면(가로)에서도 안전 영역 안으로 당겨집니다. */
      final low = feedbackBubbleHome(const Size(640, 200), EdgeInsets.zero);
      expect(low.dy, greaterThanOrEqualTo(36));
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
       봅니다. 대조: 경계 **밖**까지 찍는 시험용 경계에서는 둘이 달라야 비교가 헛돌지 않습니다.
       끌 수 있어야 하므로 시험이 끝난 서버로. */
    testWidgets('말풍선은 캡처 경계 밖 — 찍힌 그림은 말풍선이 켜 있을 때와 꺼 있을 때 같다', (t) async {
      final outer = GlobalKey();
      await _boot(
        t,
        testing: false,
        home: Scaffold(appBar: AppBar(title: const Text('홈')), body: const Center(child: Text('찍힐 화면'))),
        builder: (c, child) => RepaintBoundary(key: outer, child: appFrame(c, child)),
      );
      expect(_shown(t), isTrue);
      final boundary = find.byKey(kAppCaptureKey);
      expect(boundary, findsOneWidget);
      expect(find.descendant(of: boundary, matching: _bubble), findsNothing, reason: '경계 안에 없어야 합니다');
      expect(find.descendant(of: boundary, matching: _bin), findsNothing, reason: 'X 도 경계 밖');
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

  group('꾹 눌러 옮기기', () {
    /* 말풍선은 목록 위에 떠 있습니다 — 스크롤하던 엄지가 걸려도 말풍선이 따라오면 안 됩니다. */
    testWidgets('그냥 끌면 아무 일도 없다(안 움직이고 시트도 안 뜸) — 누르면 시트', (t) async {
      final env = await _boot(t);
      final at = t.getRect(_dot);
      await t.drag(_bubble, const Offset(-200, -150));
      await _settle(t);
      expect(t.getRect(_dot), at, reason: '꾹 누르지 않은 끌기는 옮기지 않습니다');
      await t.fling(_bubble, const Offset(0, -300), 2000);
      await _settle(t);
      expect(t.getRect(_dot), at);
      expect(env.captures, 0);
      expect(_send, findsNothing, reason: '끌기는 누르기가 아닙니다');
      expect(await _saved(), isNull);
      expect(_binUp(t), isFalse, reason: 'X 도 안 뜹니다');

      await _tapBubble(t);
      expect(env.captures, 1, reason: '누르기는 그대로 의견 시트');
      expect(t.takeException(), isNull);
    });

    testWidgets('꾹 누르기는 0.35초 — 예전 기본(0.5초)보다 짧고, 그 전에 떼면 탭(피드백 46)', (t) async {
      expect(kBubbleLongPress, const Duration(milliseconds: 350));
      final haptics = _haptics(t);
      await _boot(t);
      /* 0.35초가 되기 전(0.3초)에는 아직 안 들립니다. */
      final g = await t.startGesture(t.getCenter(_bubble));
      await t.pump(const Duration(milliseconds: 300));
      expect(_binUp(t), isFalse, reason: '0.3초에는 아직');
      expect(haptics, isEmpty);
      /* 0.4초 — 예전 기본(0.5초)이면 아직이었을 때 — 들립니다. */
      await t.pump(const Duration(milliseconds: 100));
      await t.pump(const Duration(milliseconds: 200));
      expect(haptics, ['HapticFeedbackType.mediumImpact'], reason: '0.4초에 잡힘');
      expect(_binUp(t), isTrue);
      await g.up();
      await _settle(t);
    });

    testWidgets('꾹 누르면 들린다 — 커지고 한 번 떨리고, X 는 들린 동안만 아래 가운데에', (t) async {
      final haptics = _haptics(t);
      await _boot(t);
      final at = t.getRect(_dot);
      expect(_binUp(t), isFalse, reason: '들기 전에는 X 가 없습니다');
      expect(_bin.hitTestable(), findsNothing);

      final h = await _lift(t);
      expect(haptics, ['HapticFeedbackType.mediumImpact'], reason: '잡았다 — 한 번');
      expect(t.getRect(_dot).width, greaterThan(40), reason: '살짝 커집니다');
      expect(t.getRect(_dot).center.dx, closeTo(at.center.dx, 0.5), reason: '제자리에서 커질 뿐');
      expect(_binUp(t), isTrue, reason: '들린 동안 X');
      final bin = t.getRect(_bin);
      expect(bin.size, const Size(56, 56));
      expect(bin.center.dx, closeTo(390 / 2, 0.5), reason: '아래 가운데');
      expect(bin.bottom, closeTo(844 - 24, 0.5), reason: '아래 안전 영역 위');
      expect(find.descendant(of: _bin, matching: find.byIcon(LucideIcons.x)), findsOneWidget);
      expect(_send, findsNothing, reason: '꾹 누르기는 시트를 열지 않습니다');

      /* 안 움직이고 놓으면 제자리 — 자리를 새로 적지 않습니다(처음 자리가 비율로 굳지 않게). */
      await h.up(t);
      expect(t.getRect(_dot), at);
      expect(_binUp(t), isFalse, reason: '놓으면 X 가 사라집니다');
      expect(await _saved(), isNull);
      expect(find.text(_locked), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('놓으면 가장 가까운 가장자리로 — 네 곳 모두, 그 가장자리를 따라서는 놓은 그대로 · 다시 켜도 그 자리',
        (t) async {
      await _boot(t);
      /* 390×844, 안전 영역 없음 — 가운데가 설 수 있는 네모는 (36, 36) ~ (354, 808). */
      Future<void> check(String name, Offset drop, Offset center, FeedbackBubblePos pos) async {
        await _moveBubble(t, drop);
        await _settle(t);
        final dot = t.getRect(_dot);
        expect(dot.size, const Size(40, 40), reason: '$name — 놓으면 제 크기');
        expect(dot.center.dx, closeTo(center.dx, 0.5), reason: '$name — $dot');
        expect(dot.center.dy, closeTo(center.dy, 0.5), reason: '$name — $dot');
        final saved = (await _saved())!;
        expect(saved.edge, pos.edge, reason: name);
        expect(saved.t, closeTo(pos.t, 1e-6), reason: name);
      }

      await check('왼쪽', const Offset(70, 300), const Offset(36, 300),
          const FeedbackBubblePos(FeedbackEdge.left, (300 - 36) / (808 - 36)));
      expect(t.getRect(_dot).left, 16, reason: '가장자리에서 16px');
      await check('위', const Offset(200, 90), const Offset(200, 36),
          const FeedbackBubblePos(FeedbackEdge.top, (200 - 36) / (354 - 36)));
      expect(t.getRect(_dot).top, 16);
      await check('오른쪽', const Offset(340, 520), const Offset(354, 520),
          const FeedbackBubblePos(FeedbackEdge.right, (520 - 36) / (808 - 36)));
      expect(t.getRect(_dot).right, 390 - 16);
      await check('아래', const Offset(90, 770), const Offset(90, 808),
          const FeedbackBubblePos(FeedbackEdge.bottom, (90 - 36) / (354 - 36)));
      expect(t.getRect(_dot).bottom, 844 - 16);
      final dot = t.getRect(_dot);

      /* 다시 켜기 — 트리를 통째로 내리고 저장소는 그대로 둔 채 새로 세웁니다. */
      await t.pumpWidget(const SizedBox());
      await _boot(t, keepPrefs: true);
      expect(_shown(t), isTrue);
      expect(t.getRect(_dot), dot, reason: '다시 켜도 옮긴 자리');
      expect(t.takeException(), isNull);
    });

    testWidgets('아래 가장자리 가운데(X 자리)에는 비켜서 붙는다', (t) async {
      await _boot(t);
      /* X 가운데 (195, 792) 에서 64px 밖 — X 위가 아닌 곳에 놓았지만 가장 가까운 곳은 아래. */
      await _moveBubble(t, const Offset(225, 700));
      final c = t.getRect(_dot).center;
      expect(c.dy, closeTo(808, 0.5), reason: '아래 가장자리');
      expect(c.dx, closeTo(195 + 72, 0.5), reason: '놓은 쪽(오른쪽)으로 비킴');
      expect(find.text(_locked), findsNothing, reason: 'X 에 놓은 것이 아닙니다');
      /* 다시 들어도 X 위에서 시작하지 않습니다. */
      final h = await _lift(t);
      expect(t.getRect(_dot).overlaps(t.getRect(_bin)), isFalse);
      await h.up(t);
      expect(t.takeException(), isNull);
    });

    /* 비율은 화면마다 다른 픽셀입니다 — 가로에서 비켜 붙인 아래 자리가 세로로 돌리면 X 가운데
       가까이 옵니다. 그대로 두면 다음에 들 때 X 위에서 시작하고, 조금만 옮겨 놓아도 치워집니다.
       그릴 때마다 다시 비켜야 합니다. */
    testWidgets('가로에서 아래에 붙인 자리 — 세로로 돌려도 X 자리를 비킨다', (t) async {
      await _boot(t, size: const Size(844, 390));
      await _moveBubble(t, const Offset(500, 330));
      expect(t.getRect(_dot).center.dx, closeTo(500, 0.5), reason: '가로 — X 가운데(422)에서 78px, 비킬 것 없음');
      expect(t.getRect(_dot).center.dy, closeTo(390 - 36, 0.5));
      expect((await _saved())!.edge, FeedbackEdge.bottom);

      t.view.physicalSize = const Size(390, 844);
      await _settle(t);
      final c = t.getRect(_dot).center;
      expect(c.dy, closeTo(808, 0.5), reason: '같은 가장자리(아래)');
      expect(c.dx, closeTo(195 + 72, 0.5), reason: '비율대로면 X 가운데에서 32px — 놓은 쪽(오른쪽)으로 비킴');
      final h = await _lift(t);
      expect(t.getRect(_dot).overlaps(t.getRect(_bin)), isFalse, reason: '들어도 X 위에서 시작하지 않습니다');
      await h.to(t, c + const Offset(0, -12));
      await h.up(t);
      expect(find.text(_locked), findsNothing, reason: '조금 옮겨 놓은 것은 치우기가 아닙니다');
      expect(_shown(t), isTrue);
      expect(t.takeException(), isNull);
    });

    test('아래 가장자리는 어느 화면에서든 X 가운데에서 72px 밖 — 비율이 가운데여도', () {
      for (final size in const [Size(360, 640), Size(390, 844), Size(430, 932), Size(844, 390)]) {
        for (final tt in const [0.45, 0.5, 0.55]) {
          final c = feedbackBubbleCenter(FeedbackBubblePos(FeedbackEdge.bottom, tt), size, EdgeInsets.zero);
          final bin = feedbackBubbleBinCenter(size, EdgeInsets.zero);
          expect((c.dx - bin.dx).abs(), greaterThanOrEqualTo(72 - 1e-9), reason: '$size · $tt');
          expect(feedbackBubbleOverBin(c, size, EdgeInsets.zero), isFalse, reason: '$size · $tt');
        }
      }
    });

    testWidgets('들린 동안은 안전 영역 안 — 화면 끝까지 끌어도 상태 막대 · 아래 제스처 띠 밖으로 안 나간다', (t) async {
      const pad = EdgeInsets.only(top: 47, bottom: 34);
      await _boot(t, size: const Size(430, 932), pad: pad);
      final h = await _lift(t);
      await h.to(t, const Offset(-200, -200));
      expect(t.getCenter(_bubble), const Offset(36, 47 + 36.0), reason: '왼쪽 위 모서리에서 멈춤');
      await h.to(t, const Offset(900, 1400));
      expect(t.getCenter(_bubble), const Offset(430 - 36, 932 - 34 - 36.0), reason: '오른쪽 아래 모서리에서 멈춤');
      await h.up(t);
      final hit = t.getRect(_bubble);
      expect(hit.top, greaterThanOrEqualTo(pad.top));
      expect(hit.bottom, lessThanOrEqualTo(932 - pad.bottom));
      expect(hit.right, lessThanOrEqualTo(430));
      expect(t.takeException(), isNull);
    });

    testWidgets('손가락이 취소되면(전화가 옴 등) 들기 전 자리로 — 적지 않는다', (t) async {
      await _boot(t);
      final at = t.getRect(_dot);
      final h = await _lift(t);
      await h.to(t, const Offset(80, 200));
      await h.g.cancel();
      await _settle(t);
      expect(t.getRect(_dot), at);
      expect(_binUp(t), isFalse);
      expect(await _saved(), isNull);
    });

    /* 자리는 비율로 적으므로 돌려도(가로 · 세로) 같은 가장자리 · 같은 비율. 다시 세우면 원래 자리. */
    testWidgets('돌려도(가로 ↔ 세로) 같은 가장자리, 다시 세우면 원래 자리', (t) async {
      await _boot(t);
      await _moveBubble(t, const Offset(60, 300));
      final portrait = t.getRect(_dot);
      expect(portrait.left, 16);

      t.view.physicalSize = const Size(844, 390);
      await _settle(t);
      final land = t.getRect(_dot);
      expect(land.left, 16, reason: '같은 가장자리(왼쪽)');
      expect(land.center.dy, closeTo(36 + (300 - 36) / (808 - 36) * (390 - 72), 0.5), reason: '같은 비율');
      expect(land.bottom, lessThanOrEqualTo(390));

      t.view.physicalSize = const Size(390, 844);
      await _settle(t);
      expect(t.getRect(_dot), portrait, reason: '다시 세우면 원래 자리');
      expect(t.takeException(), isNull);
    });

    /* 옛 판은 {쪽, 가운데 높이 비율} 을 적었습니다. 새 판에서 처음 켤 때 그 화면에서 같은 높이가
       되게 옮겨 적고 옛 칸은 지웁니다 — 옮겨 둔 자리가 업데이트로 사라지면 안 됩니다. */
    testWidgets('옛 자리({쪽, 높이})는 같은 높이로 옮겨 적고 옛 칸은 지운다', (t) async {
      await _boot(t, prefs: {kFeedbackBubbleSideKey: 'left', kFeedbackBubbleYKey: 0.3});
      final dot = t.getRect(_dot);
      expect(dot.left, 16, reason: '왼쪽');
      expect(dot.center.dy, closeTo(0.3 * 844, 0.5), reason: '옛 판과 같은 높이');
      final sp = await SharedPreferences.getInstance();
      expect(sp.containsKey(kFeedbackBubbleSideKey), isFalse);
      expect(sp.containsKey(kFeedbackBubbleYKey), isFalse);
      final saved = (await _saved())!;
      expect(saved.edge, FeedbackEdge.left);
      expect(saved.t, closeTo((0.3 * 844 - 36) / (808 - 36), 1e-6));

      await t.pumpWidget(const SizedBox());
      await _boot(t, keepPrefs: true);
      expect(t.getRect(_dot), dot, reason: '옮겨 적은 뒤에도 그 자리');

      /* 옛 규칙의 범위(앱바 밑 ~ 「인바디」 위) 밖이던 값은 옛 판이 보이던 대로 당겨서. */
      await t.pumpWidget(const SizedBox());
      await _boot(t, prefs: {kFeedbackBubbleSideKey: 'right', kFeedbackBubbleYKey: 0.99});
      expect(t.getRect(_dot).right, 390 - 16);
      expect(t.getRect(_dot).center.dy, closeTo(844 - 160 - 24, 0.5));
      expect(t.takeException(), isNull);
    });

    test('자리 읽기 — 틀린 값은 처음 자리(null), 비율은 0~1 로', () {
      for (final j in <Object?>[null, 3, 'x', [], {}, {'edge': 'middle', 't': 0.5}, {'edge': 'left'},
        {'edge': 'left', 't': 'x'}, {'edge': 'left', 't': double.nan}]) {
        expect(FeedbackBubblePos.fromJson(j), isNull, reason: '$j');
      }
      expect(FeedbackBubblePos.fromJson({'edge': 'top', 't': 3}), const FeedbackBubblePos(FeedbackEdge.top, 1));
      expect(FeedbackBubblePos.fromJson({'edge': 'bottom', 't': -1}),
          const FeedbackBubblePos(FeedbackEdge.bottom, 0));
      const p = FeedbackBubblePos(FeedbackEdge.right, 0.25);
      expect(FeedbackBubblePos.fromJson(jsonDecode(jsonEncode(p.toJson()))), p);
      /* 화면 크기를 모르면 옛 높이 비율을 그대로 — 비슷한 자리. */
      expect(feedbackBubbleFromLegacy(right: false, y: 0.4, size: Size.zero, pad: EdgeInsets.zero),
          const FeedbackBubblePos(FeedbackEdge.left, 0.4));
      /* 거리가 같으면 옆이 먼저. */
      expect(feedbackBubbleSnap(const Offset(36 + 10, 36 + 10), const Size(390, 844), EdgeInsets.zero).edge,
          FeedbackEdge.left);
    });
  });

  group('X — 치우기', () {
    for (final (name, testing) in [('확인기 없음(모름)', null), ('서버 testing 참', true)]) {
      testWidgets('시험 기간($name) — 닿으면 커지고 붉어지고 한 번 떨림, 놓으면 「$_locked」 · 들기 전 자리로',
          (t) async {
        final haptics = _haptics(t);
        await _boot(t, testing: testing);
        final at = t.getRect(_dot);
        final h = await _lift(t);
        final bin = t.getRect(_bin);
        final scheme = Theme.of(t.element(_bin)).colorScheme;
        expect((t.widget<AnimatedContainer>(_bin).decoration as BoxDecoration).color,
            scheme.inverseSurface.withValues(alpha: 0.88), reason: '닿기 전');

        await h.to(t, bin.center + const Offset(0, -40));
        await t.pump(const Duration(milliseconds: 200));
        expect((t.widget<AnimatedContainer>(_bin).decoration as BoxDecoration).color, scheme.error,
            reason: '64px 안 — 붉어집니다');
        expect(t.getRect(_bin).width, greaterThan(56), reason: '커집니다');
        final icon = t.widget<Icon>(find.descendant(of: _bin, matching: find.byType(Icon)));
        expect(icon.color, scheme.onError);
        await h.to(t, bin.center);
        await h.to(t, bin.center + const Offset(20, 0));
        expect(haptics, ['HapticFeedbackType.mediumImpact', 'HapticFeedbackType.heavyImpact'],
            reason: '들 때 한 번, X 에 들어설 때 한 번 — 안에서 움직여도 더 안 떨림');

        await h.up(t);
        expect(find.text(_locked), findsOneWidget);
        expect(t.getRect(_dot), at, reason: '들기 전 자리로 돌아갑니다');
        expect(_shown(t), isTrue);
        expect(feedbackBubbleOn.value, isTrue);
        expect(await _saved(), isNull, reason: 'X 에 놓은 것은 옮긴 것이 아닙니다');
        expect(_binUp(t), isFalse);
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('X 에서 다시 나오면 원래 색 — 들어설 때마다 한 번씩만 떨린다', (t) async {
      final haptics = _haptics(t);
      await _boot(t);
      final h = await _lift(t);
      final bin = t.getRect(_bin);
      await h.to(t, bin.center);
      await h.to(t, bin.center + const Offset(0, -200));
      await t.pump(const Duration(milliseconds: 200));
      final scheme = Theme.of(t.element(_bin)).colorScheme;
      expect((t.widget<AnimatedContainer>(_bin).decoration as BoxDecoration).color,
          scheme.inverseSurface.withValues(alpha: 0.88));
      await h.to(t, bin.center);
      expect(haptics.where((e) => e == 'HapticFeedbackType.heavyImpact'), hasLength(2));
      await h.to(t, const Offset(60, 300));
      await h.up(t);
      expect(find.text(_locked), findsNothing, reason: 'X 밖에서 놓았습니다');
      expect(t.getRect(_dot).left, 16);
    });

    testWidgets('시험 끝 — X 에 놓으면 사라지고 「$_removed」, 다시 켜도 숨은 채 · 설정 스위치로 곧바로', (t) async {
      await _boot(t, testing: false);
      await _moveBubble(t, const Offset(60, 300));
      final moved = t.getRect(_dot);
      final h = await _lift(t);
      await h.to(t, t.getRect(_bin).center);
      await h.up(t);
      expect(_hidden(t), isTrue);
      expect(find.text(_removed), findsOneWidget);
      final sp = await SharedPreferences.getInstance();
      expect(sp.getBool(kFeedbackBubbleOnKey), isFalse);
      expect((await _saved())!.edge, FeedbackEdge.left, reason: '옮겨 둔 자리는 그대로');

      /* 다시 켜도 숨은 채. */
      await t.pumpWidget(const SizedBox());
      feedbackBubbleOn.value = true;   // 기억은 저장소에만 — 새로 켠 앱처럼
      await _boot(t, keepPrefs: true, testing: false);
      expect(_hidden(t), isTrue, reason: '치운 것은 다시 켜도 숨은 채');

      /* 설정 → 도움말의 스위치(같은 값)로 되돌리면 이 화면 옆에 곧바로 — 옮겨 둔 자리에. */
      await _openSettings(t);
      await _scrollToSwitch(t);
      final sw = t.widget<SwitchListTile>(_switch);
      expect(sw.value, isFalse);
      expect(sw.onChanged, isNotNull, reason: '시험이 끝났으면 켜고 끌 수 있습니다');
      expect(find.descendant(of: _switch, matching: find.text('테스트 기간에는 켜 둡니다')), findsNothing);
      await t.tap(_switch);
      await _settle(t);
      expect(t.widget<SwitchListTile>(_switch).value, isTrue);
      expect(_shown(t), isTrue, reason: '뒤로 가기 전에도 곧바로');
      expect(t.getRect(_dot), moved);
      expect(sp.getBool(kFeedbackBubbleOnKey), isTrue);

      /* 스위치로 끄면 말풍선도 곧바로. */
      await t.tap(_switch);
      await _settle(t);
      expect(_hidden(t), isTrue);
      expect(sp.getBool(kFeedbackBubbleOnKey), isFalse);
      expect(t.takeException(), isNull);
    });
  });

  group('시험 기간 · 설정', () {
    testWidgets('시험 기간에는 옛 판에서 꺼 둔 기기에도 뜨고, 설정 스위치는 켜진 채 잠김 — 시험이 끝나면 풀린다',
        (t) async {
      final env = await _boot(t, testing: true, prefs: {kFeedbackBubbleOnKey: false});
      expect(feedbackBubbleOn.value, isFalse, reason: '저장된 값은 꺼짐 그대로');
      expect(_shown(t), isTrue, reason: '시험 기간이라 보입니다');

      await _openSettings(t);
      await _scrollToSwitch(t);
      var sw = t.widget<SwitchListTile>(_switch);
      expect(sw.value, isTrue, reason: '켜진 채');
      expect(sw.onChanged, isNull, reason: '잠김');
      expect(find.descendant(of: _switch, matching: find.text('테스트 기간에는 켜 둡니다')), findsOneWidget);
      await t.tap(_switch);
      await _settle(t);
      expect(feedbackBubbleOn.value, isFalse, reason: '눌러도 안 바뀝니다');
      expect(_shown(t), isTrue);

      /* 주인이 시험을 끝냄(--testing=off) — 설정 화면을 연 채로도 곧바로 풀리고, 꺼 둔 대로 숨습니다. */
      await _serverSays(t, env, false);
      sw = t.widget<SwitchListTile>(_switch);
      expect(sw.value, isFalse);
      expect(sw.onChanged, isNotNull);
      expect(find.descendant(of: _switch, matching: find.text('테스트 기간에는 켜 둡니다')), findsNothing);
      expect(_hidden(t), isTrue);
      expect(t.takeException(), isNull);
    });

    testWidgets('틀린 testing 값 · 칸 없음(옛 서버)은 시험 중으로 — X 로 못 치운다', (t) async {
      for (final v in <Object>['off', 0]) {
        await t.pumpWidget(const SizedBox());
        final env = await _boot(t, testing: v);
        expect(env.update!.testing, isTrue, reason: '$v');
        final h = await _lift(t);
        await h.to(t, t.getRect(_bin).center);
        await h.up(t);
        expect(find.text(_locked), findsOneWidget, reason: '$v');
        expect(_shown(t), isTrue);
        await t.pump(const Duration(seconds: 4));
      }
      /* 칸이 없는 옛 서버. */
      await t.pumpWidget(const SizedBox());
      final env = await _boot(t, testing: false);
      await _serverSays(t, env, null);
      expect(env.update!.testing, isTrue);
      final h = await _lift(t);
      await h.to(t, t.getRect(_bin).center);
      await h.up(t);
      expect(find.text(_locked), findsOneWidget);
      expect(_shown(t), isTrue);
    });

    /* 시험이 끝난 뒤 꺼 둔 사람 — 확인기가 이 기기의 지난 답을 읽기 전에는 "모름(시험 중)" 이라,
       그때 보여 주면 앱을 켤 때마다 번쩍입니다. 읽은 뒤에 정합니다. */
    testWidgets('꺼 둔 기기 — 확인기가 지난 답을 읽기 전에는 번쩍이지 않고, 읽은 뒤 시험 기간이면 뜬다', (t) async {
      final env = await _boot(t, testing: true, startUpdate: false, prefs: {kFeedbackBubbleOnKey: false});
      expect(env.update!.loaded, isFalse);
      expect(_hidden(t), isTrue, reason: '아직 모름 — 기다립니다');
      await t.runAsync(env.update!.start);
      await _settle(t);
      expect(_shown(t), isTrue, reason: '시험 기간 — 꺼 두었어도 뜹니다');
    });
  });

  group('스크린리더', () {
    testWidgets('「의견 보내기」 단추(누르기만), 숨으면 트리에서 빠진다 · X 는 알리지 않는다', (t) async {
      final h = t.ensureSemantics();
      await _boot(t, testing: false);
      expect(
          t.getSemantics(_bubble),
          isSemantics(
            label: '의견 보내기',
            isButton: true,
            hasTapAction: true,
            hasLongPressAction: false,
          ));
      expect(find.semantics.byLabel('의견 보내기'), findsOne, reason: '실제 시맨틱 트리에 하나');
      final hand = await _lift(t);
      expect(find.semantics.byLabel('의견 버튼 숨기기'), findsNothing, reason: '옛 메뉴는 없습니다');
      expect(find.byKey(const Key('feedback-bubble-hide')), findsNothing);
      await hand.up(t);
      await setFeedbackBubbleOn(false);
      await _settle(t);
      expect(find.semantics.byLabel('의견 보내기'), findsNothing, reason: '안 보이는 단추를 짚으면 안 됩니다');
      h.dispose();
    });
  });

  group('360px · 글자 1.3배', () {
    for (final (name, theme) in [('밝게', mbLight), ('어둡게', mbDark)]) {
      testWidgets('$name — 넘치지 않고, 색은 테마에서(말풍선 · X · 설정 카드)', (t) async {
        await _boot(t, size: const Size(360, 640), text: 1.3, theme: theme());
        expect(t.takeException(), isNull);
        expect(_shown(t), isTrue);
        final b = t.getRect(_bubble);
        expect(b.left, greaterThanOrEqualTo(0));
        expect(b.right, lessThanOrEqualTo(360));
        expect(b.bottom, lessThanOrEqualTo(640));
        expect(b.overlaps(t.getRect(_fab)), isFalse);
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

        /* X — 반대색 동그라미, 닿으면 error. 화면 안. */
        final h = await _lift(t);
        final bin = t.getRect(_bin);
        expect(bin.left, greaterThanOrEqualTo(0));
        expect(bin.right, lessThanOrEqualTo(360));
        expect(bin.bottom, lessThanOrEqualTo(640));
        final binDeco = t.widget<AnimatedContainer>(_bin).decoration as BoxDecoration;
        expect(binDeco.color, scheme.inverseSurface.withValues(alpha: 0.88));
        expect(t.widget<Icon>(find.descendant(of: _bin, matching: find.byType(Icon))).color,
            scheme.onInverseSurface);
        await h.to(t, bin.center);
        await t.pump(const Duration(milliseconds: 200));
        expect((t.widget<AnimatedContainer>(_bin).decoration as BoxDecoration).color, scheme.error);
        await h.to(t, const Offset(300, 200));
        await h.up(t);
        expect(t.takeException(), isNull);

        /* 설정 화면(글자 1.3배)의 도움말 카드도 넘치지 않습니다 — 잠긴 줄(시험 기간). */
        await _openSettings(t);
        await _scrollToSwitch(t);
        expect(t.takeException(), isNull);
        expect(find.descendant(of: _switch, matching: find.text('테스트 기간에는 켜 둡니다')), findsOneWidget);
        expect(t.getRect(_switch).right, lessThanOrEqualTo(360));
      });
    }

    testWidgets('시험이 끝난 설정 줄(「꾹 눌러 옮겨요」)도 넘치지 않는다', (t) async {
      await _boot(t, size: const Size(360, 640), text: 1.3, theme: mbDark(), testing: false);
      await _openSettings(t);
      await _scrollToSwitch(t);
      expect(t.takeException(), isNull);
      expect(find.descendant(of: _switch, matching: find.text('화면 가장자리 말풍선 · 꾹 눌러 옮겨요')), findsOneWidget);
      expect(t.getRect(_switch).right, lessThanOrEqualTo(360));
    });
  });

  /* 도는 것이 없는 화면에서 들기 · 끌기 · 놓기 · X 가 끝나면 프레임이 멈춰야 합니다 — 끝없는
     애니메이션은 배터리를 먹고 시험의 pumpAndSettle 을 막습니다. */
  testWidgets('애니메이션은 끝이 있다 — 들기 · 붙기 · X · 치우기 뒤 프레임이 멈춘다', (t) async {
    await _boot(t,
        testing: false,
        home: Scaffold(appBar: AppBar(title: const Text('홈')), body: const Center(child: Text('화면'))));
    final h = await _lift(t);
    await t.pumpAndSettle();
    await h.to(t, const Offset(60, 400));
    await t.pumpAndSettle();
    await h.up(t);
    await t.pumpAndSettle();
    expect(t.binding.hasScheduledFrame, isFalse);
    for (final w in t.widgetList<ImplicitlyAnimatedWidget>(find.descendant(
        of: find.byType(FeedbackBubbleLayer), matching: find.byWidgetPredicate((w) => w is ImplicitlyAnimatedWidget)))) {
      expect(w.duration, lessThanOrEqualTo(const Duration(milliseconds: 300)), reason: '$w');
    }
    final h2 = await _lift(t);
    await h2.to(t, t.getRect(_bin).center);
    await t.pumpAndSettle();
    await h2.g.up();
    await t.pumpAndSettle();
    expect(_hidden(t), isTrue);
    expect(t.binding.hasScheduledFrame, isFalse);
    expect(t.takeException(), isNull);
  });
}
