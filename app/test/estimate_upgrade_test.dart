/* =============================================================================
 * estimate_upgrade_test.dart — 첫 실측이 들어오면 추정이 걷히고 계획이 다시 서는가
 *
 * 진짜 엔진으로 봅니다(AppState.boot 로 엔진 고리까지 꽂은 채). "사람이 원한 것을
 * 지킨다" 는 약속 — 목표 체중은 그대로, 골격근은 변화량, 체지방은 실측 비율로 맞춤,
 * 강도 · 모드 · 마감은 그대로 — 은 엔진이 실제로 그 목표로 계획을 세워 줘야 의미가
 * 있습니다. 손으로 만든 표로는 그 약속을 볼 수 없습니다.
 *
 * 설계 때 손으로 푼 예(오너): 추정 {81.6 · 36.7 · 12.2} 중 → 실측 {81.6 · 39.0 · 13.1} 중.
 *
 * 안전 규칙에 걸리는 경우(마른 실측에서 옮긴 목표가 하한 아래), 추정 계획이 아니면
 * 손대지 않는 경우, 동기화로 실측이 들어와 저장소 듣는 쪽이 정리하는 경우, 실측이
 * 추정보다 옛날인 경우, 추정 기록은 지웠는데 계획만 남은 경우도 봅니다.
 *
 * 화면 두 가지: 기간 판이 추정 위에서 계획을 세우면 도장(fromEstimate)을 찍는지,
 * 목표 화면이 추정 몸에 「추정」 알약을 달고 좁은 폰 · 큰 글자 · 어두운 테마에서
 * 넘치지 않는지.
 * ========================================================================== */
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mybody/src/api.dart';
import 'package:mybody/src/app_state.dart';
import 'package:mybody/src/estimate.dart';
import 'package:mybody/src/estimate_upgrade.dart';
import 'package:mybody/src/scope.dart';
import 'package:mybody/src/screens/duration.dart';
import 'package:mybody/src/screens/goal.dart';
import 'package:mybody/src/screens/intensity.dart';
import 'package:mybody/src/screens/workout_session.dart';
import 'package:mybody/src/theme.dart';
import 'package:mybody/src/ui/widgets.dart';
import 'package:mybody_core/mybody_core.dart' as core;
import 'package:shared_preferences/shared_preferences.dart';

const _profile = {
  'sex': 'male', 'age': 22, 'heightCm': 187, 'activityLevel': 'moderate',
  'trainingAge': 'novice', 'daysPerWeek': 4, 'mealsPerDay': 3,
};

String _nowIso([Duration shift = Duration.zero]) =>
    DateTime.now().add(shift).toUtc().toIso8601String();

/// 오너의 진짜 인바디.
Map<String, Object?> _real({String id = 'r1', String? at}) => {
      'id': id, 'measuredAt': at ?? _nowIso(const Duration(seconds: 1)),
      'weightKg': 86.7, 'smmKg': 38.0, 'bfmKg': 20.0, 'pbfPct': 23.1,
      'ffmKg': 66.7, 'bmi': 24.8, 'bmrKcal': 1810,
    };

Future<AppState> _boot() async {
  SharedPreferences.setMockInitialValues({});
  final app = await AppState.boot();
  app.store.set({'profile': Map<String, Object?>.of(_profile), 'onboarded': true});
  return app;
}

Map<String, Object?> _estimate(AppState app, {double weightKg = 86.7}) =>
    saveEstimate(app.store, sex: 'male', age: 22, heightCm: 187, weightKg: weightKg)!;

/// 목표 화면의 추천 — 체지방률 15%(남) · 근육 +1kg. (_recommend 와 같은 식)
Map<String, Object?> _recommend(Map<String, Object?> cur) {
  final smm = core.r1(core.jsToNumber(cur['smmKg']) + 1.0);
  final ffm = smm / core.jsToNumber(cur['smmToFfm']);
  final weight = core.r1(ffm / (1 - 15 / 100));
  return {'weightKg': weight, 'smmKg': smm, 'bfmKg': core.r1(weight - ffm)};
}

/// 추정 위에 계획을 세웁니다 — 강도 화면의 _commit 과 같은 길 + 도장.
Map<String, Object?> _planOnEstimate(AppState app, Map<String, Object?> est,
    Map<String, Object?> goal, {String level = 'mid', Map<String, Object?>? modeDef}) {
  final profile = app.profile!;
  final cmp = core.compareLevels(
      est, profile, goal, app.store.dayKey(), goal['deadlineWeeks'], modeDef);
  expect(cmp['impossible'], isNot(true), reason: '시험의 전제 — 추정 몸에선 계획이 선다');
  final plan = core.buildPlan(cmp, level, est, profile)!..['fromEstimate'] = true;
  app.store.setGoal(goal);
  app.store.setPlan(plan);
  return plan;
}

Map<String, Object?> _goal(AppState app) => (app.state['goal'] as Map).cast<String, Object?>();
Map<String, Object?>? _plan(AppState app) =>
    (app.state['plan'] as Map?)?.cast<String, Object?>();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('(1) 계획이 없으면 추정만 걷는다 — 묘비 · 기록 plan none · 두 번째는 null', () async {
    final app = await _boot();
    final est = _estimate(app);
    app.store.addScan(_real());
    final rec = upgradeEstimates(app.store)!;

    expect(app.store.sortedScans().map((s) => s['id']), ['r1']);
    final tomb = ((app.state['tombstones'] as Map)['scans'] as Map);
    expect(tomb.containsKey(est['id']), isTrue, reason: '다른 기기에서도 지워지게');
    expect(rec['plan'], 'none');
    expect((rec['before'] as Map)['smmKg'], 35.7);
    expect((rec['before'] as Map)['pbfPct'], 22.1);
    expect((rec['after'] as Map)['smmKg'], 38.0);
    expect((rec['after'] as Map)['pbfPct'], 23.1);
    expect(rec['goalBefore'], isNull);
    expect(app.state[kEstimateUpgradeKey], rec);
    expect(upgradeNotice(app.state, DateTime.now()), isNotNull);
    expect(upgradeEstimates(app.store), isNull, reason: '멱등');
    await Future<void>.delayed(Duration.zero);
    expect(app.state[kEstimateUpgradeKey], rec, reason: '듣는 쪽의 두 번째 부름이 기록을 덮지 않는다');
  });

  test('(2) 추정 위의 계획 → 실측에서 다시 — 체중 그대로 · 근육 변화량 · 체지방 맞춤 · 같은 강도', () async {
    final app = await _boot();
    final est = _estimate(app);
    final cur = core.derive(est, app.profile!);
    final goal = _recommend(cur);
    expect(goal, {'weightKg': 81.6, 'smmKg': 36.7, 'bfmKg': 12.2}, reason: '설계의 예');
    final old = _planOnEstimate(app, est, goal);
    expect(needsEstimateUpgrade(app.state), isFalse, reason: '실측 전엔 할 일 없음');

    app.store.addScan(_real());
    final rec = upgradeEstimates(app.store)!;

    final g = _goal(app);
    expect(g['weightKg'], 81.6);
    expect(g['smmKg'], 39.0);
    expect(g['bfmKg'], 13.1);
    final info = core.classifyGoal(core.derive(_real(), app.profile!), g);
    expect(info['mismatchKg'], 0.0, reason: '세 숫자가 서로 맞는다');
    expect(info['dWeightKg'], -5.1);
    expect(info['dSmmKg'], 1.0);

    final plan = _plan(app)!;
    expect(plan['level'], 'mid');
    expect(plan.containsKey('fromEstimate'), isFalse);
    expect(plan['startDate'], app.store.dayKey());
    expect((plan['goal'] as Map)['smmKg'], 39.0);
    final base = (app.state['baselinePlan'] as Map).cast<String, Object?>();
    expect((base['goal'] as Map)['smmKg'], 39.0, reason: '기준 계획도 실측에서');
    expect(base.containsKey('fromEstimate'), isFalse);

    expect(rec['plan'], 'rebuilt');
    expect(rec['weeksBefore'], old['weeks']);
    expect([rec['weeksBefore'], rec['weeksAfter']], [30, 27], reason: '설계의 예 — 중 30주 → 27주');
    expect(rec['weeksAfter'], plan['weeks']);
    expect(rec['goalBefore'], {'weightKg': 81.6, 'smmKg': 36.7, 'bfmKg': 12.2});
    expect(rec['goalAfter'], {'weightKg': 81.6, 'smmKg': 39.0, 'bfmKg': 13.1});
    expect(rec['reason'], isNull);
    final hist = (app.state['goalHistory'] as List).cast<Map>();
    expect(hist.last['reason'], kUpgradeReason);
    expect((hist.last['goal'] as Map)['smmKg'], 36.7);
    expect(needsEstimateUpgrade(app.state), isFalse);
    expect(upgradeEstimates(app.store), isNull);
  });

  test('(3) 모드와 마감은 그대로 간다', () async {
    final app = await _boot();
    final est = _estimate(app);
    final profile = app.profile!;
    final cur = core.derive(est, profile);
    final goal = {..._recommend(cur), 'deadlineWeeks': 30};
    final sel = selectGoalMode(
        scans: app.store.sortedScans(), cur: cur, goal: goal, profile: profile,
        deadlineWeeks: 30);
    expect(sel['refused'], isNot(true));
    final modeDef = core.modeById(sel['modeId'])!;
    final old = _planOnEstimate(app, est, goal, modeDef: modeDef);
    expect((old['mode'] as Map)['id'], modeDef['id']);

    app.store.addScan(_real());
    final rec = upgradeEstimates(app.store)!;
    expect(rec['plan'], 'rebuilt', reason: '${rec['reason']}');
    final plan = _plan(app)!;
    expect((plan['mode'] as Map)['id'], modeDef['id']);
    expect(_goal(app)['deadlineWeeks'], 30);
    expect(plan['level'], old['level']);
  });

  test('(3b) 기간 길로 세운 계획은 모드가 null — null 로 둔다', () async {
    final app = await _boot();
    final est = _estimate(app);
    final goal = {..._recommend(core.derive(est, app.profile!)), 'deadlineWeeks': 30};
    _planOnEstimate(app, est, goal);
    app.store.addScan(_real());
    expect(upgradeEstimates(app.store)!['plan'], 'rebuilt');
    expect(_plan(app)!['mode'], isNull);
  });

  test('(4) 실측 기준으론 하한 아래 — 계획을 비우고 목표는 옮긴 값, needsGoal', () async {
    final app = await _boot();
    final est = _estimate(app);
    final cur = core.derive(est, app.profile!);
    // 추정 몸에선 괜찮은 감량 목표 — 76kg · 근육 그대로 · 체지방 11%대
    final k = core.jsToNumber(cur['smmToFfm']);
    final goal = {'weightKg': 76.0, 'smmKg': 35.7, 'bfmKg': core.r1(76.0 - 35.7 / k)};
    final pre = selectGoalMode(
        scans: app.store.sortedScans(), cur: cur, goal: goal, profile: app.profile!);
    expect(pre['refused'], isNot(true), reason: '시험의 전제 — 추정 몸에선 된다');
    final cmp = core.compareLevels(est, app.profile!, goal, app.store.dayKey(), null, null);
    final level = resultsOf(cmp).firstWhere((r) => !isBlocked(r))['level'] as String;
    _planOnEstimate(app, est, goal, level: level);

    // 마른 실측 — 같은 체중인데 근육이 훨씬 많다
    app.store.addScan({
      'id': 'lean', 'measuredAt': _nowIso(const Duration(seconds: 1)),
      'weightKg': 86.7, 'smmKg': 42.0, 'bfmKg': 11.0, 'pbfPct': 12.7,
    });
    final rec = upgradeEstimates(app.store)!;
    expect(rec['plan'], 'needsGoal');
    expect(rec['reason'], isNotNull);
    expect('${rec['reason']}', isNotEmpty);
    expect(_plan(app), isNull);
    expect(app.state['baselinePlan'], isNull);

    final g = _goal(app);
    expect(g['weightKg'], 76.0);
    expect(g['smmKg'], 42.0, reason: '근육 변화량 0 을 옮김');
    final pbf = core.jsToNumber(g['bfmKg']) / 76.0 * 100;
    expect(pbf, lessThan(8), reason: '옮긴 목표가 하한 아래라 거절');
    expect(rec['goalAfter'], {'weightKg': 76.0, 'smmKg': 42.0, 'bfmKg': g['bfmKg']});
    expect((app.state['goalHistory'] as List).cast<Map>().last['reason'], kUpgradeReason);
    expect(needsEstimateUpgrade(app.state), isFalse);
  });

  test('(5) 추정 계획이 아니면 목표 · 계획을 건드리지 않는다', () async {
    final app = await _boot();
    final est = _estimate(app);
    final goal = _recommend(core.derive(est, app.profile!));
    final plan = _planOnEstimate(app, est, goal)..remove('fromEstimate');
    app.store.setPlan(plan);
    final goalBefore = Map<String, Object?>.of(_goal(app));
    app.store.addScan(_real());
    final rec = upgradeEstimates(app.store)!;
    expect(rec['plan'], 'none');
    expect(_goal(app), goalBefore);
    expect(_plan(app)!['weeks'], plan['weeks']);
    expect(_plan(app)!['startDate'], plan['startDate']);
    expect(app.store.sortedScans().where(isEstimate), isEmpty);
  });

  test('(6) 동기화처럼 저장소에 바로 들어온 실측도 — 듣는 쪽이 한 박자 뒤 정리', () async {
    final app = await _boot();
    final est = _estimate(app);
    _planOnEstimate(app, est, _recommend(core.derive(est, app.profile!)));
    app.store.addScan(_real());
    expect(app.store.sortedScans().where(isEstimate), hasLength(1), reason: '아직 — 마이크로태스크 전');
    await Future<void>.delayed(Duration.zero);
    expect(app.store.sortedScans().where(isEstimate), isEmpty);
    final rec = (app.state[kEstimateUpgradeKey] as Map).cast<String, Object?>();
    expect(rec['plan'], 'rebuilt');
    expect(planFromEstimate(app.state['plan']), isFalse);
  });

  test('(6b) 부팅 — 섞인 채 저장된 상태(꺼지기 직전 · 옛 판)를 켜자마자 정리', () async {
    final first = await _boot();
    final est = _estimate(first);
    final mixed = {...first.state, 'scans': [est, _real()]};
    SharedPreferences.setMockInitialValues({core.storeKey: jsonEncode(mixed)});
    final app = await AppState.boot();
    await Future<void>.delayed(Duration.zero);
    expect(app.store.sortedScans().map((s) => s['id']), ['r1']);
    expect(app.state[kEstimateUpgradeKey], isNotNull);
  });

  test('(7) 실측이 추정보다 옛날이어도 교체한다', () async {
    final app = await _boot();
    final est = _estimate(app);
    _planOnEstimate(app, est, _recommend(core.derive(est, app.profile!)));
    app.store.addScan(_real(at: _nowIso(const Duration(days: -30))));
    final rec = upgradeEstimates(app.store)!;
    expect(app.store.sortedScans().map((s) => s['id']), ['r1']);
    expect(rec['plan'], 'rebuilt');
    expect(_goal(app)['smmKg'], 39.0);
  });

  test('(8) 추정 기록은 지웠는데 계획만 남았으면 — 궤적 첫 점을 출발점으로', () async {
    final app = await _boot();
    final est = _estimate(app);
    _planOnEstimate(app, est, _recommend(core.derive(est, app.profile!)));
    app.store.removeScan(est['id']);
    expect(app.store.sortedScans(), isEmpty);
    expect(planFromEstimate(app.state['plan']), isTrue);
    expect(needsEstimateUpgrade(app.state), isFalse, reason: '실측이 없으면 할 일 없음');

    app.store.addScan(_real());
    final rec = upgradeEstimates(app.store)!;
    expect(rec['plan'], 'rebuilt');
    expect((rec['before'] as Map)['smmKg'], 35.7, reason: '궤적 첫 점(소수 둘째)을 첫째로');
    expect(_goal(app)['smmKg'], 39.0);
    expect(_goal(app)['weightKg'], 81.6);
  });

  test('(9) 운동 추천 — 추정이면 골격근 · 체지방률을 안 쓴다, 체중은 쓴다', () async {
    final app = await _boot();
    _estimate(app);
    expect(latestSmmKg(app), isNull);
    expect(latestPbfPct(app), isNull);
    expect(latestWeightKg(app), 86.7);
    app.store.addScan(_real());
    expect(latestSmmKg(app), 38.0);
    expect(latestPbfPct(app), 23.1);
  });

  test('(12) 동기화 엇갈림 — 목표는 이미 실측 기준인데 추정 계획이 되살아나도 변화량을 두 번 얹지 않는다', () async {
    /* 기기 A 가 실측으로 바꿨고(목표 · 계획), 기기 B 는 그걸 못 받은 채 옛 추정 계획에
       체크인을 했습니다. 합치면 목표는 A 것(한쪽만 바꿈), 계획은 둘 다 바꿨으니 나중인 B 것
       — 실측 목표 + 추정 계획. 목표에 변화량을 또 얹으면 39.0 → 41.3kg 이 됩니다. */
    final app = await _boot();
    final est = _estimate(app);
    final goal = _recommend(core.derive(est, app.profile!));
    final onB = Map<String, Object?>.of(_planOnEstimate(app, est, goal))
      ..['adjustments'] = [
        {'at': _nowIso(), 'week': 1, 'kcalDelta': -100},
      ];
    app.store.addScan(_real());
    expect(upgradeEstimates(app.store)!['plan'], 'rebuilt');
    expect(_goal(app)['smmKg'], 39.0);

    app.store.set({'plan': onB}); // 합친 결과 — 계획만 B 의 추정 계획
    expect(needsEstimateUpgrade(app.state), isTrue);
    final rec = upgradeEstimates(app.store)!;
    expect(rec['plan'], 'rebuilt');
    final g = _goal(app);
    expect([g['weightKg'], g['smmKg'], g['bfmKg']], [81.6, 39.0, 13.1],
        reason: '계획의 goal(추정 틀)에서 변화량을 읽는다 — 이미 옮긴 목표에 또 얹지 않는다');
    expect(rec['goalBefore'], {'weightKg': 81.6, 'smmKg': 36.7, 'bfmKg': 12.2});
    expect(rec['weeksAfter'], 27);
    expect(planFromEstimate(app.state['plan']), isFalse);
  });

  test('(13) 골격근 칸이 빠진 옛 실측 — 기록에 NaN 을 적지 않는다(적으면 그 뒤 저장이 전부 실패)', () async {
    final app = await _boot();
    _estimate(app);
    app.store.addScan({
      'id': 'old', 'measuredAt': _nowIso(const Duration(seconds: 1)),
      'weightKg': 86.7, 'pbfPct': 23.1,
    });
    final rec = upgradeEstimates(app.store)!;
    expect((rec['after'] as Map)['smmKg'], isNull);
    expect((rec['after'] as Map)['weightKg'], 86.7);
    expect(app.store.saved(), isTrue);
    expect(() => jsonEncode(app.state), returnsNormally);
    app.store.set({'onboarded': true});
    expect(app.store.saved(), isTrue, reason: '다음 저장도 된다');
  });

  /* --- 화면 ------------------------------------------------------------------ */

  Api api() {
    final a = Api(
        baseUrl: '',
        client: MockClient((_) async => http.Response('{"ok":false}', 404)));
    a.setToken('tok');
    return a;
  }

  Widget host(AppState app, Widget child, {ThemeData? theme}) => Scope(
        state: app,
        api: api(),
        onServerChange: (_) async {},
        child: MaterialApp(theme: theme ?? mbLight(), home: child),
      );

  Future<void> stacked(WidgetTester t, AppState app, Widget top) async {
    await t.pumpWidget(host(app, const Scaffold(body: Text('home'))));
    final nav = t.state<NavigatorState>(find.byType(Navigator));
    nav.push(MaterialPageRoute(builder: (_) => const Scaffold(body: Text('between'))));
    nav.push<Object?>(MaterialPageRoute(builder: (_) => top));
    await t.pumpAndSettle();
  }

  Finder firstOption() => find.byWidgetPredicate((w) {
        final k = w.key;
        return k is ValueKey<String> && k.value.startsWith('option-');
      }).first;

  Future<void> startFromDuration(WidgetTester t, AppState app) async {
    t.view.physicalSize = const Size(1000, 6000);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await stacked(t, app, const DurationScreen());
    await t.tap(firstOption());
    await t.pump();
    await t.tap(find.text('이 계획으로 시작하기'));
    await t.pumpAndSettle();
  }

  testWidgets('(10) 기간 판 — 추정 위에서 세운 계획엔 도장, 실측 위에선 없음', (t) async {
    final app = await t.runAsync(_boot);
    _estimate(app!);
    await startFromDuration(t, app);
    expect(find.text('계획을 세웠습니다'), findsOneWidget);
    expect(_plan(app)!['fromEstimate'], true);
  });

  testWidgets('(10b) 기간 판 — 실측뿐이면 도장 없음', (t) async {
    final app = await t.runAsync(_boot);
    app!.store.addScan(_real());
    await startFromDuration(t, app);
    expect(find.text('계획을 세웠습니다'), findsOneWidget);
    expect(_plan(app)!.containsKey('fromEstimate'), isFalse);
  });

  testWidgets('(10c) 강도 화면 — 표를 추정에서 세운 뒤 실측이 들어와도 도장을 찍어 곧 실측으로 다시 선다', (t) async {
    t.view.physicalSize = const Size(1000, 6000);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final app = await t.runAsync(_boot);
    final est = _estimate(app!);
    final goal = _recommend(core.derive(est, app.profile!));
    await stacked(t, app, IntensityScreen(goal: goal));

    // 화면이 열린 사이 동기화로 실측이 들어와 듣는 쪽이 추정을 걷어 냅니다(계획은 아직 없음).
    app.store.addScan(_real());
    await t.pump();
    expect(app.store.sortedScans().where(isEstimate), isEmpty);

    await t.tap(find.text('이 계획으로 시작하기'));
    await t.pumpAndSettle();
    if (find.text('그대로 가기').evaluate().isNotEmpty) {
      await t.tap(find.text('그대로 가기'));
      await t.pumpAndSettle();
    }
    expect(find.text('home'), findsOneWidget);
    expect(planFromEstimate(app.state['plan']), isFalse, reason: '도장 → 듣는 쪽이 바로 다시 세움');
    expect(_goal(app)['smmKg'], 39.0, reason: '추정 틀의 목표가 실측으로 옮겨졌다');
    expect((_plan(app)!['goal'] as Map)['smmKg'], 39.0);
    expect((app.state[kEstimateUpgradeKey] as Map)['plan'], 'rebuilt');
    expect(t.takeException(), isNull);
  });

  for (final c in [
    (name: '밝은 테마', theme: mbLight()),
    (name: '어두운 테마', theme: mbDark()),
  ]) {
    testWidgets('(11) 목표 화면 — 추정 몸엔 「추정」 알약, 360px · 글자 1.3배 · ${c.name}', (t) async {
      t.view.physicalSize = const Size(360, 800);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      t.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      final app = await t.runAsync(_boot);
      _estimate(app!);
      await t.pumpWidget(host(app, const GoalScreen(), theme: c.theme));
      await t.pump(const Duration(milliseconds: 200));
      expect(find.widgetWithText(Pill, '추정'), findsOneWidget);
      expect(find.textContaining('현재 ('), findsOneWidget);
      expect(t.takeException(), isNull);

      await t.tap(find.text('기간으로 정하기'));
      await t.pumpAndSettle();
      expect(find.widgetWithText(Pill, '추정'), findsOneWidget, reason: '기간 판에서도 지금 몸 카드는 그대로');
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('(11b) 목표 화면 — 실측이면 알약 없음', (t) async {
    t.view.physicalSize = const Size(1000, 3000);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final app = await t.runAsync(_boot);
    app!.store.addScan(_real());
    await t.pumpWidget(host(app, const GoalScreen()));
    await t.pump(const Duration(milliseconds: 200));
    expect(find.widgetWithText(Pill, '추정'), findsNothing);
    expect(t.takeException(), isNull);
  });
}
