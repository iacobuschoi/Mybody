/* =============================================================================
 * review_upgrade_test.dart — 추정으로 시작한 뒤 첫 결과지를 검수 화면에서 저장하면
 *
 * 검수 화면은 결과지를 "이전 측정" 과 대조합니다(골격근/제지방 비율 · 변화량).
 * 이전 측정이 키 · 체중 추정이면 대조가 거짓 경보를 냅니다 — 오너는 추정 비율
 * 0.529 로 "골격근량이 35.3kg 근처여야" 가 뜨는데 실측은 38.0 입니다. 추정은
 * 대조 상대가 아닙니다.
 *
 * 저장하면 추정이 걷히고 추정 위의 계획이 실측에서 다시 서며, 토스트가
 * 「실측으로 바꿨어요」 라고 말합니다. 실측 날짜가 추정보다 앞서도 "지난 기록 —
 * 계획은 그대로" 가 아닙니다. 계획은 그대로가 아니니까요.
 * ========================================================================== */
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mybody/src/api.dart';
import 'package:mybody/src/app_state.dart';
import 'package:mybody/src/estimate.dart';
import 'package:mybody/src/scope.dart';
import 'package:mybody/src/screens/review.dart';
import 'package:mybody/src/theme.dart';
import 'package:mybody_core/mybody_core.dart' as core;
import 'package:shared_preferences/shared_preferences.dart';

const _profile = {
  'sex': 'male', 'age': 22, 'heightCm': 187, 'activityLevel': 'moderate',
  'trainingAge': 'novice', 'daysPerWeek': 4, 'sessionMinutes': 60, 'mealsPerDay': 3,
};

/// 추정 + 그 위에 세운 계획(목표 화면 추천 · 중 · 도장).
Future<AppState> _seeded() async {
  SharedPreferences.setMockInitialValues({});
  final app = await AppState.boot();
  app.store.set({'profile': Map<String, Object?>.of(_profile), 'onboarded': true});
  final est = saveEstimate(app.store, sex: 'male', age: 22, heightCm: 187, weightKg: 86.7)!;
  const goal = {'weightKg': 81.6, 'smmKg': 36.7, 'bfmKg': 12.2};
  final cmp = core.compareLevels(est, app.profile!, goal, app.store.dayKey(), null, null);
  final plan = core.buildPlan(cmp, 'mid', est, app.profile!)!..['fromEstimate'] = true;
  app.store.setGoal(goal);
  app.store.setPlan(plan);
  return app;
}

Map<String, Object?> _draft(String at) => {
      'id': 'scan-x', 'measuredAt': at, 'source': 'ocr',
      'weightKg': 86.7, 'smmKg': 38.0, 'bfmKg': 20.0, 'pbfPct': 23.1,
      'ffmKg': 66.7, 'bmi': 24.8, 'bmrKcal': 1810,
    };

Future<void> _open(WidgetTester t, AppState app, Map<String, Object?> draft) async {
  t.view.physicalSize = const Size(1000, 3000);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final api = Api(baseUrl: '', client: MockClient((_) async => http.Response('{"ok":false}', 404)));
  api.setToken('tok');
  await t.pumpWidget(Scope(
    state: app,
    api: api,
    onServerChange: (_) async {},
    child: MaterialApp(
      theme: mbLight(),
      home: Scaffold(body: Builder(builder: (c) => TextButton(
        onPressed: () => Navigator.of(c).push(
            MaterialPageRoute(builder: (_) => ReviewScreen(draft: draft))),
        child: const Text('go'),
      ))),
    ),
  ));
  await t.tap(find.text('go'));
  await t.pumpAndSettle();
}

Future<void> _save(WidgetTester t) async {
  await t.ensureVisible(find.text('저장하기'));
  await t.tap(find.text('저장하기'));
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('추정 뒤의 첫 결과지 — 거짓 경보 없이 검산 통과, 저장하면 실측으로 바꾼다', (t) async {
    final app = await _seeded();
    final estId = app.store.sortedScans().single['id'];
    await _open(t, app, _draft(DateTime.now().add(const Duration(minutes: 1)).toUtc().toIso8601String()));

    expect(find.textContaining('물리적으로 맞지 않는 값', findRichText: true), findsNothing);
    expect(find.textContaining('골격근량이', findRichText: true), findsNothing,
        reason: '추정의 골격근/제지방 비율로 실측을 대조하지 않는다');
    expect(find.textContaining('움직였습니다', findRichText: true), findsNothing,
        reason: '추정 → 실측 차이를 몸의 변화로 읽지 않는다');
    expect(find.textContaining('같은 시각의 측정', findRichText: true), findsNothing);
    expect(find.textContaining('검산을 통과했습니다', findRichText: true), findsOneWidget);

    await _save(t);
    final scans = app.store.sortedScans();
    expect(scans.map((s) => s['id']), ['scan-x']);
    expect(((app.state['tombstones'] as Map)['scans'] as Map).containsKey(estId), isTrue);
    final plan = (app.state['plan'] as Map).cast<String, Object?>();
    expect(planFromEstimate(plan), isFalse);
    expect((plan['goal'] as Map)['smmKg'], 39.0);
    expect((app.state[kEstimateUpgradeKey] as Map)['plan'], 'rebuilt');
    expect(find.textContaining('실측으로 바꿨어요', findRichText: true), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('실측 날짜가 추정보다 30일 앞서도 backfill 이 아니다 — "계획은 그대로" 라고 안 한다', (t) async {
    final app = await _seeded();
    final estAt = DateTime.parse('${app.store.sortedScans().single['measuredAt']}');
    await _open(t, app, _draft(estAt.subtract(const Duration(days: 30)).toUtc().toIso8601String()));
    expect(find.textContaining('골격근량이', findRichText: true), findsNothing);

    await _save(t);
    expect(app.store.sortedScans().where(isEstimate), isEmpty);
    expect(planFromEstimate(app.state['plan']), isFalse);
    expect(find.textContaining('계획은 그대로', findRichText: true), findsNothing);
    expect(find.textContaining('실측으로 바꿨어요', findRichText: true), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('추정과 같은 시각이어도 덮어쓰기를 묻지 않는다 — 추정은 덮어쓸 기록이 아니다', (t) async {
    final app = await _seeded();
    final estAt = '${app.store.sortedScans().single['measuredAt']}';
    await _open(t, app, _draft(estAt));
    expect(find.textContaining('같은 시각의 측정', findRichText: true), findsNothing);
    expect(find.byType(SwitchListTile), findsNothing);
    await _save(t);
    expect(app.store.sortedScans().map((s) => s['id']), ['scan-x'],
        reason: '추정 자리를 이어받지 않고 새 기록 — 추정은 묘비와 함께 지워진다');
    expect(find.textContaining('실측으로 바꿨어요', findRichText: true), findsOneWidget);
  });
}
