/* =============================================================================
 * screens_smoke_test.dart — **화면이 실제로 그려지는가**
 *
 * 릴리스 빌드에서 build() 가 던지면 Flutter 는 조용히 **회색 네모**를
 * 그립니다. 오류도 안 찍힙니다. 실제로 그걸 봤습니다 — 검수 화면이
 * 통째로 회색이었고 콘솔은 깨끗했습니다.
 *
 * 그래서 화면마다 한 번씩 세워 보고 예외가 나는지 봅니다. 예쁜지는
 * 스크린샷이 보고, 여기서는 **서는지**만 봅니다.
 * ========================================================================== */
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mybody/src/api.dart';
import 'package:mybody/src/app_state.dart';
import 'package:mybody/src/scope.dart';
import 'package:mybody/src/screens/food.dart';
import 'package:mybody/src/screens/goal.dart';
import 'package:mybody/src/screens/history.dart';
import 'package:mybody/src/screens/home.dart';
import 'package:mybody/src/screens/onboarding.dart';
import 'package:mybody/src/screens/plan.dart';
import 'package:mybody/src/screens/progress.dart';
import 'package:mybody/src/screens/review.dart';
import 'package:mybody/src/screens/scandetail.dart';
import 'package:mybody/src/screens/settings.dart';
import 'package:mybody/src/screens/social.dart';
import 'package:mybody/src/screens/upload.dart';
import 'package:mybody/src/shell.dart';
import 'package:mybody/src/theme.dart';
import 'package:mybody_core/mybody_core.dart' as core;
import 'package:shared_preferences/shared_preferences.dart';

const _scan = {
  'id': 's1', 'weightKg': 86.7, 'smmKg': 38.0, 'bfmKg': 20.0,
  'pbfPct': 23.1, 'ffmKg': 66.7, 'bmi': 24.8, 'bmrKcal': 1810,
  'measuredAt': '2026-03-01T00:00:00.000Z',
};
const _scan2 = {
  'id': 's2', 'weightKg': 84.4, 'smmKg': 38.6, 'bfmKg': 17.5,
  'pbfPct': 20.7, 'measuredAt': '2026-05-20T00:00:00.000Z',
};
const _profile = {
  'sex': 'male', 'age': 22, 'heightCm': 187, 'activityLevel': 'moderate',
  'trainingAge': 'novice', 'daysPerWeek': 4, 'mealsPerDay': 3,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<AppState> seeded({bool withPlan = false, bool twoScans = false}) async {
    SharedPreferences.setMockInitialValues({});
    final app = await AppState.boot();
    app.store.set({'profile': _profile, 'onboarded': true});
    app.store.addScan({..._scan});
    if (twoScans) app.store.addScan({..._scan2});
    if (withPlan) {
      final goal = {'weightKg': 80.5, 'smmKg': 39.0, 'bfmKg': 12.0};
      final cmp = core.compareLevels(
          {..._scan}, _profile, goal, '2026-03-01', null, null);
      final plan = core.buildPlan(cmp, 'mid', {..._scan}, _profile);
      app.store.setGoal(goal);
      if (plan != null) app.store.setPlan(plan);
    }
    return app;
  }

  /* **Scope 를 MaterialApp 위에 둡니다 — 앱이 실제로 그렇게 두기 때문입니다.**
     안에 두면 밀어 올린 화면(push)에서 Scope 가 안 보이는데, 시험은
     화면을 home 자리에 직접 세워서 그 차이를 못 봅니다. 실제로 그래서
     검수 화면이 릴리스에서 회색 네모가 됐는데 시험 열아홉 개가 전부
     통과했습니다. */
  Widget host(AppState app, Widget child) => Scope(
        state: app,
        api: Api(baseUrl: ''),
        onServerChange: (_) async {},
        child: MaterialApp(theme: mbLight(), home: child),
      );

  void noop(String route, [Object? arg]) {}

  Future<void> standsUp(WidgetTester t, AppState app, Widget child) async {
    await t.pumpWidget(host(app, child));
    await t.pump(const Duration(milliseconds: 200));
    /* **회색 네모가 안 나와야 합니다.** ErrorWidget 이 하나라도 있으면
       그 화면은 릴리스에서 통째로 회색입니다. */
    expect(find.byType(ErrorWidget), findsNothing);
    expect(t.takeException(), isNull);
  }

  testWidgets('홈 — 측정 없음', (t) async {
    SharedPreferences.setMockInitialValues({});
    final app = await AppState.boot();
    await standsUp(t, app, Scaffold(body: HomeScreen(go: noop)));
  });

  testWidgets('홈 — 측정만', (t) async {
    final app = await seeded();
    await standsUp(t, app, Scaffold(body: HomeScreen(go: noop)));
  });

  testWidgets('홈 — 계획까지', (t) async {
    final app = await seeded(withPlan: true, twoScans: true);
    await standsUp(t, app, Scaffold(body: HomeScreen(go: noop)));
  });

  testWidgets('인바디 넣기', (t) async {
    final app = await seeded();
    await standsUp(t, app, const UploadScreen());
  });

  /* **프로필도 측정도 없는 막 깐 앱.** 웹 빌드에서 검수 화면이 통째로
     회색이 된 것이 정확히 이 상태였습니다 — 시험은 전부 프로필을 넣고
     시작해서 그 길을 한 번도 안 밟았습니다. */
  testWidgets('판독 검수 — 막 깐 앱 (프로필 없음)', (t) async {
    SharedPreferences.setMockInitialValues({});
    final app = await AppState.boot();
    await standsUp(t, app, const ReviewScreen(draft: {
      'id': 'draft', 'measuredAt': '2026-09-21T00:00:00.000Z',
      'weightKg': 86.7, 'smmKg': 38.0, 'bfmKg': 20.0,
    }));
  });

  testWidgets('인바디 넣기 — 막 깐 앱', (t) async {
    SharedPreferences.setMockInitialValues({});
    final app = await AppState.boot();
    await standsUp(t, app, const UploadScreen());
  });

  testWidgets('목표 설정 — 막 깐 앱', (t) async {
    SharedPreferences.setMockInitialValues({});
    final app = await AppState.boot();
    await standsUp(t, app, const GoalScreen());
  });

  testWidgets('판독 검수 — 첫 측정', (t) async {
    SharedPreferences.setMockInitialValues({});
    final app = await AppState.boot();
    app.store.set({'profile': _profile});
    await standsUp(t, app, const ReviewScreen(draft: {
      'id': 'draft', 'measuredAt': '2026-06-01T00:00:00.000Z',
      'weightKg': 86.7, 'smmKg': 38.0, 'bfmKg': 20.0,
    }));
  });

  testWidgets('판독 검수 — 이전 측정이 있을 때', (t) async {
    final app = await seeded();
    await standsUp(t, app, const ReviewScreen(draft: {
      'id': 'draft', 'measuredAt': '2026-06-01T00:00:00.000Z',
      'weightKg': 86.7, 'smmKg': 38.0, 'bfmKg': 20.0,
    }));
  });

  testWidgets('판독 검수 — 값이 서로 안 맞을 때', (t) async {
    final app = await seeded();
    await standsUp(t, app, const ReviewScreen(draft: {
      'id': 'draft', 'measuredAt': '2026-06-01T00:00:00.000Z',
      'weightKg': 867.0, 'smmKg': 38.0, 'bfmKg': 20.0,
    }));
  });

  testWidgets('목표 설정', (t) async {
    final app = await seeded();
    await standsUp(t, app, const GoalScreen());
  });

  testWidgets('플랜 — 계획 없음', (t) async {
    final app = await seeded();
    await standsUp(t, app, Scaffold(body: PlanScreen(go: noop)));
  });

  testWidgets('플랜 — 계획 있음', (t) async {
    final app = await seeded(withPlan: true);
    await standsUp(t, app, Scaffold(body: PlanScreen(go: noop)));
  });

  testWidgets('추이 — 측정 하나', (t) async {
    final app = await seeded();
    await standsUp(t, app, Scaffold(body: ProgressScreen(go: noop)));
  });

  testWidgets('추이 — 측정 둘', (t) async {
    final app = await seeded(twoScans: true, withPlan: true);
    await standsUp(t, app, Scaffold(body: ProgressScreen(go: noop)));
  });

  testWidgets('식단', (t) async {
    final app = await seeded(withPlan: true);
    await standsUp(t, app, Scaffold(body: FoodScreen(go: noop)));
  });

  testWidgets('음식 검색', (t) async {
    final app = await seeded();
    await standsUp(t, app, const FoodSearchScreen(date: '2026-06-01'));
  });

  testWidgets('측정 기록', (t) async {
    final app = await seeded(twoScans: true);
    await standsUp(t, app, const HistoryScreen());
  });

  testWidgets('측정 상세', (t) async {
    final app = await seeded(twoScans: true);
    await standsUp(t, app, const ScanDetailScreen(scanId: 's2'));
  });

  testWidgets('설정', (t) async {
    final app = await seeded();
    await standsUp(t, app, const SettingsScreen());
  });

  testWidgets('친구 — 로그인 안 함', (t) async {
    final app = await seeded();
    await standsUp(t, app, Scaffold(body: SocialScreen(go: noop)));
  });

  /* **밀어 올린 화면도 섭니다.**
     이 시험이 없어서 릴리스에서만 회색이 되는 것을 못 잡았습니다.
     화면을 직접 세우는 것과, 앱처럼 밀어 올리는 것은 다른 일입니다. */
  testWidgets('밀어 올린 화면이 상태를 본다 (push 경로)', (t) async {
    final app = await seeded(twoScans: true);
    await t.pumpWidget(host(app, const _Pusher()));
    await t.pump();
    await t.tap(find.text('열기'));
    await t.pumpAndSettle();
    expect(find.byType(ErrorWidget), findsNothing,
        reason: 'Scope 가 MaterialApp 아래에 있으면 여기서 회색 네모가 됩니다');
    expect(t.takeException(), isNull);
    expect(find.text('측정 기록'), findsWidgets);
  });

  /* **프로필 없이 홈으로 못 들어갑니다.**
     들어가면 코어가 씨앗 프로필(주인의 몸: 187cm · 22세 · 남성)로
     계산합니다 — 키 155cm 인 사람에게 187cm 기준 식단이 나가고,
     틀렸다는 표시는 어디에도 없습니다. */
  testWidgets('막 깐 앱은 온보딩을 먼저 세운다', (t) async {
    SharedPreferences.setMockInitialValues({});
    final app = await AppState.boot();
    await t.pumpWidget(host(app, const Shell()));
    await t.pump();
    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(find.text('홈'), findsNothing, reason: '프로필 없이 홈이 보이면 안 됩니다');
  });

  testWidgets('온보딩을 마치면 프로필이 남고 홈이 열린다', (t) async {
    SharedPreferences.setMockInitialValues({});
    final app = await AppState.boot();
    await t.pumpWidget(host(app, const Shell()));
    await t.pump();

    await t.enterText(find.widgetWithText(TextField, '키'), '155');
    await t.enterText(find.widgetWithText(TextField, '나이'), '34');
    await t.pump();
    await t.tap(find.text('다음'));
    await t.pumpAndSettle();
    await t.tap(find.text('다음'));
    await t.pumpAndSettle();
    await t.tap(find.text('읽었고 이해했습니다'));
    await t.pump();
    await t.tap(find.text('시작하기'));
    await t.pumpAndSettle();

    expect(app.onboarded, isTrue);
    expect(app.profile?['heightCm'], 155.0);
    expect(app.profile?['age'], 34.0);
    expect(find.byType(OnboardingScreen), findsNothing);
    /* 씨앗 프로필(주인 키 187)이 새어 들어오지 않았는지 못 박습니다. */
    expect(app.profile?['heightCm'], isNot(187));
  });

  /* **별표가 화면에 나가면 안 됩니다.**
     문구 안의 `**굵게**` 표시를 Flutter 의 Text 는 모릅니다 — 그대로 찍습니다.
     실제로 온보딩 고지에 "측정 기록은 **이 기기에만** 저장됩니다" 가
     별표째로 나갔습니다. 제일 중요한 문장이 제일 어설퍼 보이는 자리였습니다. */
  testWidgets('화면에 마크다운 별표가 안 나온다', (t) async {
    SharedPreferences.setMockInitialValues({});
    final fresh = await AppState.boot();
    final planned = await seeded(withPlan: true, twoScans: true);

    for (final (name, app, screen) in <(String, AppState, Widget)>[
      ('온보딩', fresh, const OnboardingScreen()),
      ('설정', planned, const SettingsScreen()),
      ('홈', planned, Scaffold(body: HomeScreen(go: noop))),
      ('플랜', planned, Scaffold(body: PlanScreen(go: noop))),
      ('추이', planned, Scaffold(body: ProgressScreen(go: noop))),
    ]) {
      await t.pumpWidget(host(app, screen));
      await t.pump(const Duration(milliseconds: 200));
      final stars = <String>[];
      for (final w in t.widgetList<Text>(find.byType(Text))) {
        final s = w.data ?? w.textSpan?.toPlainText() ?? '';
        if (s.contains('**')) stars.add(s);
      }
      expect(stars, isEmpty, reason: '$name 화면에 별표가 그대로 나갑니다: $stars');
    }
  });

  testWidgets('셸 — 탭 다섯 개가 다 선다', (t) async {
    final app = await seeded(withPlan: true, twoScans: true);
    await t.pumpWidget(host(app, const Shell()));
    await t.pump(const Duration(milliseconds: 200));
    for (final label in ['식단', '플랜', '추이', '친구', '홈']) {
      await t.tap(find.text(label));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.byType(ErrorWidget), findsNothing, reason: '$label 탭이 회색 네모가 됩니다');
      expect(t.takeException(), isNull, reason: '$label 탭에서 예외');
    }
  });
}

/// 진짜 앱처럼 화면을 **밀어 올려** 봅니다.
class _Pusher extends StatelessWidget {
  const _Pusher();
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const HistoryScreen())),
            child: const Text('열기'),
          ),
        ),
      );
}
