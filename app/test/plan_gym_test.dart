/* =============================================================================
 * plan_gym_test.dart — 플랜 탭의 종목은 기구 설정을 거친다
 *
 * 0.2.9 에서 「운동 장소와 기구」(머신 대수 · 익숙한 종목)를 만들었는데, 설정
 * 화면에만 있고 플랜 탭의 종목 목록은 엔진이 준 그대로였습니다. 주인: "이거는
 * 전혀 반영 안 된 거 같은데". 플랜 탭이 설정 요약과 여는 단추를 보여 주고,
 * 종목은 설정에 맞춘 것이어야 합니다.
 * ========================================================================== */
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mybody/src/api.dart';
import 'package:mybody/src/app_state.dart';
import 'package:mybody/src/scope.dart';
import 'package:mybody/src/screens/gym_settings.dart';
import 'package:mybody/src/screens/plan.dart';
import 'package:mybody/src/theme.dart';
import 'package:mybody/src/workout/exercises.dart';
import 'package:mybody/src/workout/planner.dart';
import 'package:mybody/src/workout/prefs.dart';
import 'package:mybody_core/mybody_core.dart' as core;
import 'package:shared_preferences/shared_preferences.dart';

const _scan = {
  'id': 's1', 'weightKg': 86.7, 'smmKg': 38.0, 'bfmKg': 20.0,
  'pbfPct': 23.1, 'ffmKg': 66.7, 'bmi': 24.8, 'bmrKcal': 1810,
  'measuredAt': '2026-03-01T00:00:00.000Z',
};
const _profile = {
  'sex': 'male', 'age': 22, 'heightCm': 187, 'activityLevel': 'moderate',
  'trainingAge': 'novice', 'daysPerWeek': 4, 'mealsPerDay': 3,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<AppState> seeded() async {
    SharedPreferences.setMockInitialValues({});
    final app = await AppState.boot();
    app.store.set({'profile': _profile, 'onboarded': true});
    app.store.addScan({..._scan});
    final goal = {'weightKg': 80.5, 'smmKg': 39.0, 'bfmKg': 12.0};
    final cmp = core.compareLevels({..._scan}, _profile, goal, '2026-03-01', null, null);
    final plan = core.buildPlan(cmp, 'mid', {..._scan}, _profile);
    app.store.setGoal(goal);
    app.store.setPlan(plan!);
    return app;
  }

  Api api() {
    final a = Api(baseUrl: '', client: MockClient((_) async => http.Response('{"ok":false}', 404)));
    a.setToken('tok');
    return a;
  }

  Widget host(AppState app, Widget child) => Scope(
        state: app,
        api: api(),
        onServerChange: (_) async {},
        child: MaterialApp(theme: mbLight(), home: child),
      );

  void noop(String route, [Object? arg]) {}

  Future<void> open(WidgetTester t, AppState app) async {
    t.view.physicalSize = const Size(1000, 4000);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(host(app, Scaffold(body: PlanScreen(go: noop))));
    await t.pumpAndSettle();
    expect(find.byType(ErrorWidget), findsNothing);
  }

  /// 플랜의 첫 운동 세션(쉬는 날 아닌 것).
  Map<String, Object?> firstSession(AppState app) {
    final sessions = ((app.state['plan'] as Map)['workout'] as Map)['sessions'] as List;
    for (final s in sessions) {
      if ((s as Map)['rest'] != true) return s.cast<String, Object?>();
    }
    fail('운동 세션이 없습니다');
  }

  test('설정 요약 한 줄', () {
    expect(gymPrefsSummary(GymPrefs.fromSettings(null)), startsWith('헬스장 · 기구 '));
    expect(gymPrefsSummary(GymPrefs.fromSettings(null)), contains('머신 제한 없음'));
    expect(gymPrefsSummary(GymPrefs.fromSettings(null)), endsWith('익숙한 종목 없음'));
    final home = GymPrefs.fromSettings({'gym': {'place': 'home', 'familiar': ['push-up', 'squat']}});
    expect(gymPrefsSummary(home), startsWith('집 · '));
    expect(gymPrefsSummary(home), isNot(contains('머신')));
    expect(gymPrefsSummary(home), endsWith('익숙한 종목 2개'));
  });

  testWidgets('플랜 탭에 기구 설정 요약과 「기구 설정」 단추가 있고, 누르면 설정 카드가 열린다', (t) async {
    final app = await seeded();
    await open(t, app);
    await t.scrollUntilVisible(find.byKey(const Key('open-gym-settings')), 300);
    expect(find.textContaining('헬스장 · 기구'), findsOneWidget);
    await t.tap(find.byKey(const Key('open-gym-settings')));
    await t.pumpAndSettle();
    expect(find.byType(GymSettingsScreen), findsOneWidget);
    expect(find.byType(GymSettingsCard), findsOneWidget);
  });

  testWidgets('집으로 바꾸면 플랜 탭의 종목이 집 기구에 맞춰 바뀌고, 원래 종목이 적힌다', (t) async {
    final app = await seeded();
    final session = firstSession(app);
    final raw = [for (final e in (session['exercises'] as List)) '${(e as Map)['name']}'];
    /* 집(기본 기구: 맨몸 · 밴드 정도)에서는 엔진의 머신·바벨 종목이 살아남지 못합니다. */
    updateGymPrefs(app, (p) => p.copyWith(
        place: 'home', equipment: GymPrefs.defaultEquipment('home'), machineCount: null));
    final tailored = tailorSession(session, GymPrefs.fromSettings(app.state['settings'] as Map<String, Object?>?));
    final swapped = tailored.where((e) => '${e['note']}'.startsWith(kSubstitutePrefix)).toList();
    expect(swapped, isNotEmpty, reason: '집에서는 대체가 생겨야 시험이 의미 있습니다: $raw');

    await open(t, app);
    await t.scrollUntilVisible(find.text('${session['label']}'), 300);
    expect(find.textContaining('집 · 기구'), findsOneWidget);
    expect(find.textContaining('${swapped.length}종목 바꿈'), findsWidgets);
    await t.tap(find.text('${session['label']}'));
    await t.pumpAndSettle();
    /* 바꾼 종목의 이름과 「대체」 표, 그리고 원래 종목 이름. */
    expect(find.text('${swapped.first['name']}'), findsWidgets);
    expect(find.text('대체'), findsWidgets);
    expect(find.textContaining('${swapped.first['note']}'), findsWidgets);
  });

  testWidgets('익숙한 종목을 고르면 「익숙」 표로 그 종목이 들어간다', (t) async {
    final app = await seeded();
    final session = firstSession(app);
    /* 세션의 부위 중 하나에서, 지금 목록에 없는 같은 부위 종목을 익숙한 종목으로 고릅니다. */
    final prefs0 = GymPrefs.fromSettings(null);
    final current = tailorSession(session, prefs0);
    final ids = {for (final e in current) '${e['id']}'};
    String? pick;
    for (final e in current) {
      final group = '${e['group']}';
      for (final x in exercisesFor(group)) {
        if (!ids.contains(x.id) && prefs0.equipment.contains(x.equip)) {
          pick = x.id;
          break;
        }
      }
      if (pick != null) break;
    }
    expect(pick, isNotNull);
    updateGymPrefs(app, (p) => p.copyWith(familiar: [pick!]));
    final tailored = tailorSession(session, GymPrefs.fromSettings(app.state['settings'] as Map<String, Object?>?));
    final fam = tailored.where((e) => '${e['note']}'.startsWith(kFamiliarPrefix)).toList();
    expect(fam, hasLength(1));

    await open(t, app);
    await t.scrollUntilVisible(find.text('${session['label']}'), 300);
    expect(find.textContaining('익숙한 종목 1개'), findsOneWidget);
    await t.tap(find.text('${session['label']}'));
    await t.pumpAndSettle();
    expect(find.text('${fam.first['name']}'), findsWidgets);
    expect(find.text('익숙'), findsOneWidget);
  });
}
