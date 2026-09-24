/* 달성률 계산과 주간 체크인이 그 숫자를 쓰는지.
 *
 * 체크인의 「얼마나 지켰나」 는 사람이 적지 않고 기록에서 셉니다. 그래서
 * 세는 규칙이 곧 제품입니다: 계획한 날만 분모, 오늘 안 한 것은 놓친 게
 * 아니라 열린 것, 식단은 3일은 적어야 판단. */
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mybody/src/adherence.dart';
import 'package:mybody/src/api.dart';
import 'package:mybody/src/app_state.dart';
import 'package:mybody/src/scope.dart';
import 'package:mybody/src/screens/checkin.dart';
import 'package:mybody/src/theme.dart';
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

/* 서버는 없습니다 — 모든 요청에 404. */
Widget host(AppState app, Widget child) {
  final api = Api(baseUrl: '', client: MockClient((_) async => http.Response('{"ok":false}', 404)));
  api.setToken('tok');
  return Scope(
      state: app, api: api, onServerChange: (_) async {},
      child: MaterialApp(theme: mbLight(), home: child));
}

Future<AppState> seeded({bool withPlan = true}) async {
  SharedPreferences.setMockInitialValues({});
  final app = await AppState.boot();
  app.store.set({'profile': _profile, 'onboarded': true});
  app.store.addScan({..._scan});
  if (withPlan) {
    final goal = {'weightKg': 80.5, 'smmKg': 39.0, 'bfmKg': 12.0};
    final cmp = core.compareLevels({..._scan}, _profile, goal, '2026-03-01', null, null);
    final plan = core.buildPlan(cmp, 'mid', {..._scan}, _profile);
    app.store.setGoal(goal);
    if (plan != null) app.store.setPlan(plan);
  }
  return app;
}

void log(AppState app, String date, double kcal, double p) => app.store.addFoodLog({
      'date': date, 'meal': '점심', 'source': 'manual',
      'items': [{'name': 'x', 'g': 100, 'kcal': kcal, 'p': p, 'c': 0, 'f': 0}],
    });

void main() {
  test('운동 — 계획한 날만 분모, 오늘 안 한 것은 열린 것', () async {
    final app = await seeded(withPlan: false);
    final s = app.store, sch = app.schedule;
    final today = s.dayKey();
    expect(workoutAdherence(s, 7)['pct'], isNull, reason: '계획이 없으면 0% 가 아니라 없음');

    for (final d in [-1, -2, -3, -4]) {
      s.setSchedulePlan(sch.shiftKey(today, d), 'gym', true);
    }
    s.setScheduleDone(sch.shiftKey(today, -1), 'gym', true);
    s.setScheduleDone(sch.shiftKey(today, -2), 'gym', true);
    s.setScheduleDone(sch.shiftKey(today, -4), 'gym', true);
    s.setSchedulePlan(today, 'cardio', true);          // 오늘, 아직 안 함
    s.setSchedulePlan(sch.shiftKey(today, -20), 'gym', true);   // 창 밖

    final w = workoutAdherence(s, 7);
    expect(w['plannedDays'], 5);
    expect(w['keptDays'], 3);
    expect(w['missedDays'], 1);
    expect(w['openDays'], 1);
    expect(w['pct'], 75, reason: '3 / (3 + 1). 오늘은 분모에 안 듭니다');
    final byType = (w['byType'] as Map).cast<String, Map<String, int>>();
    expect(byType['gym'], {'planned': 4, 'done': 3});
    expect(byType['cardio'], {'planned': 1, 'done': 0});
    expect((w['days'] as List).length, 7);

    final w30 = workoutAdherence(s, 30);
    expect(w30['plannedDays'], 6, reason: '30일 창에는 20일 전 것도 듭니다');
    expect(w30['missedDays'], 2);
  });

  test('식단 — 3일은 적어야 판단하고, 범위 안 비율이 곧 dietPct', () async {
    final app = await seeded();
    final s = app.store, sch = app.schedule;
    final today = s.dayKey();
    final intake = core.jsToNumber((s.get()['plan'] as Map)['macros']['intakeKcal']);

    expect(weekExecution(s)['dietPct'], isNull, reason: '기록 없음');
    log(app, sch.shiftKey(today, -1), intake, 150);
    log(app, sch.shiftKey(today, -2), intake, 150);
    expect(weekExecution(s)['dietPct'], isNull, reason: '2일은 부족');
    expect(weekExecution(s)['loggedDays'], 2);

    log(app, sch.shiftKey(today, -3), intake * 1.3, 150);   // 범위 위
    final ex = weekExecution(s);
    expect(ex['loggedDays'], 3);
    expect(ex['inBandDays'], 2);
    expect(ex['dietPct'], 67);
    expect(ex['hasTarget'], isTrue);
  });

  test('식단 — 목표가 없으면 판단하지 않는다', () async {
    final app = await seeded(withPlan: false);
    final s = app.store, sch = app.schedule;
    for (final d in [-1, -2, -3]) {
      log(app, sch.shiftKey(s.dayKey(), d), 2000, 150);
    }
    final ex = weekExecution(s);
    expect(ex['hasTarget'], isFalse);
    expect(ex['dietPct'], isNull);
    expect(ex['loggedDays'], 3);
  });

  testWidgets('체크인 — 묻지 않고 기록에서 센 값을 보여 주고 저장한다', (t) async {
    t.view.physicalSize = const Size(1000, 4000);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final app = await seeded();
    final s = app.store, sch = app.schedule;
    final today = s.dayKey();
    final intake = core.jsToNumber((s.get()['plan'] as Map)['macros']['intakeKcal']);
    for (final d in [-1, -2, -3]) {
      s.setSchedulePlan(sch.shiftKey(today, d), 'gym', true);
      log(app, sch.shiftKey(today, d), intake * 0.5, 100);   // 셋 다 범위 아래
    }
    s.setScheduleDone(sch.shiftKey(today, -1), 'gym', true);

    await t.pumpWidget(host(app, const CheckinScreen()));
    await t.pump(const Duration(milliseconds: 200));

    /* 옛 카드가 없습니다. */
    expect(find.text('얼마나 지켰나'), findsNothing);
    expect(find.text('컨디션'), findsNothing);
    expect(find.byType(Slider), findsNothing);
    expect(find.byType(RadioListTile<String>), findsNothing);

    expect(find.text('지난 7일 실행'), findsOneWidget);
    expect(find.text('1/3일'), findsOneWidget);
    expect(find.text('33%'), findsOneWidget);
    expect(find.text('0/3일'), findsOneWidget);
    expect(find.text('0% 범위 안'), findsOneWidget);

    await t.enterText(find.byType(TextField), '86.0');
    await t.pump();
    /* 식단 0% → 엔진은 "실행이 덜 됐습니다" 로 계획을 그대로 둡니다. */
    expect(find.text('실행이 덜 됐습니다'), findsOneWidget);

    await t.tap(find.text('체크인 저장'));
    await t.pump(const Duration(milliseconds: 300));
    final c = ((app.state['checkins'] as List).single as Map).cast<String, Object?>();
    expect(c['weightKg'], 86.0);
    expect(c['workoutPct'], 33);
    expect(c['dietPct'], 0);
    expect(c['derived'], isTrue);
    expect(c.containsKey('condition'), isFalse);
  });

  testWidgets('체크인 — 식단 기록이 모자라면 판단을 보류하고 그렇다고 말한다', (t) async {
    t.view.physicalSize = const Size(1000, 4000);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final app = await seeded();
    /* 지난주 체크인이 하나 있어야 판정이 납니다 — 첫 체크인은 기준점이라
       판정 자체가 없고, 그때는 "반영 못 했다" 고 말할 판정도 없습니다. */
    app.store.set({'checkins': [
      {'at': DateTime.now().toUtc().subtract(const Duration(days: 8)).toIso8601String(),
       'weightKg': 86.4},
    ]});
    await t.pumpWidget(host(app, const CheckinScreen()));
    await t.pump(const Duration(milliseconds: 200));
    expect(find.text('기록 없음'), findsOneWidget);
    expect(find.text('일정 없음'), findsOneWidget);
    await t.enterText(find.byType(TextField), '86.0');
    await t.pump();
    expect(find.textContaining('실행 여부는 반영하지 못했습니다'), findsOneWidget);
    await t.tap(find.text('체크인 저장'));
    await t.pump(const Duration(milliseconds: 300));
    final c = ((app.state['checkins'] as List).last as Map).cast<String, Object?>();
    expect(c['workoutPct'], isNull);
    expect(c['dietPct'], isNull);
  });
}
