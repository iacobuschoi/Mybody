/* 주간 체크인 — 저장한 것이 어디에 반영되는가.
 *
 * 예전엔 체크인을 저장해도 거의 아무 데도 안 나왔습니다. 체중은 추이에도,
 * 다음 체크인 그래프에도 없었고, 「하루 150kcal 늘리기」 는 글로만 있고 적용할
 * 길이 없었고, 홈은 했는지 안 했는지 몰랐습니다. 그리고 판정은 계획 다음 날
 * 0.5kg 차이(체중계 차이)로 "빠릅니다" 를 냈습니다. */
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mybody_core/mybody_core.dart' as core;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mybody/src/api.dart';
import 'package:mybody/src/app_state.dart';
import 'package:mybody/src/checkins.dart';
import 'package:mybody/src/scope.dart';
import 'package:mybody/src/screens/checkin.dart';
import 'package:mybody/src/screens/home.dart';
import 'package:mybody/src/screens/progress.dart';
import 'package:mybody/src/theme.dart';

const _scan = {
  'id': 's1', 'weightKg': 86.7, 'smmKg': 38.0, 'bfmKg': 20.0,
  'pbfPct': 23.1, 'ffmKg': 66.7, 'bmi': 24.8, 'bmrKcal': 1810,
  'measuredAt': '2026-03-01T00:00:00.000Z',
};
const _profile = {
  'sex': 'male', 'age': 22, 'heightCm': 187, 'activityLevel': 'moderate',
  'trainingAge': 'novice', 'daysPerWeek': 4, 'mealsPerDay': 3,
};

Widget host(AppState app, Widget child) {
  final api = Api(baseUrl: '', client: MockClient((_) async => http.Response('{"ok":false}', 404)));
  api.setToken('tok');
  return Scope(
      state: app, api: api, onServerChange: (_) async {},
      child: MaterialApp(
        theme: mbLight(),
        home: Builder(builder: (context) => Scaffold(
              body: Center(child: TextButton(
                onPressed: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => child)),
                child: const Text('열기'),
              )),
            )),
      ));
}

String _iso(DateTime d) => d.toUtc().toIso8601String();

/// 계획을 [weeksAgo] 주 전에 시작한 것으로 세웁니다 — 오늘이 그 주차.
Future<AppState> seeded({int weeksAgo = 0}) async {
  SharedPreferences.setMockInitialValues({});
  final app = await AppState.boot();
  app.store.set({'profile': _profile, 'onboarded': true});
  app.store.addScan({..._scan});
  final goal = {'weightKg': 80.5, 'smmKg': 39.0, 'bfmKg': 12.0};
  final cmp = core.compareLevels({..._scan}, _profile, goal, '2026-03-01', null, null);
  final plan = core.buildPlan(cmp, 'mid', {..._scan}, _profile)!;
  final start = DateTime.now().subtract(Duration(days: 7 * weeksAgo));
  plan['startDate'] = app.store.dayKey(_iso(start));
  app.store.setGoal(goal);
  app.store.setPlan(plan);
  return app;
}

double _planW(AppState app, int week) {
  final tr = ((app.state['plan'] as Map)['trajectory'] as List).cast<Map>();
  return core.jsToNumber(tr.firstWhere((p) => p['week'] == week)['weightKg']);
}

Future<void> open(WidgetTester t, AppState app, Widget child) async {
  t.view.physicalSize = const Size(1000, 4200);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(host(app, child));
  await t.tap(find.text('열기'));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('첫 체크인은 기준점 — 계획 다음 날 0.5kg 달라도 "빠릅니다" 가 없다', (t) async {
    final app = await seeded();
    await open(t, app, const CheckinScreen());
    await t.enterText(find.byType(TextField), '86.2');
    await t.pump();
    expect(find.text('기준 잡음'), findsOneWidget);
    expect(find.text('기준 체중을 잡았습니다'), findsOneWidget);
    expect(find.text('빠릅니다'), findsNothing);
    expect(find.textContaining('150kcal'), findsNothing);
    expect(find.text('저장하고 제안 적용'), findsNothing);

    await t.tap(find.text('체크인 저장'));
    await t.pumpAndSettle();
    final c = ((app.state['checkins'] as List).single as Map).cast<String, Object?>();
    expect(c['weightKg'], 86.2);
    expect(c['status'], 'early');
    expect(c['applied'], isFalse);
  });

  /// 4주 전에 시작한 계획, 매주 계획선보다 0.6kg 씩 더 무거워지는 체크인 4번(0·7·14·21일).
  Future<AppState> stalled() async {
    final app = await seeded(weeksAgo: 4);
    final now = DateTime.now();
    app.store.set({'checkins': [
      for (var k = 0; k < 4; k++)
        {'at': _iso(now.subtract(Duration(days: 28 - 7 * k))),
         'weightKg': double.parse((_planW(app, k) + 0.6 * k).toStringAsFixed(1))},
    ]});
    return app;
  }

  testWidgets('추세가 두 번 연속 벗어나면 제안을 적용할 수 있고, 계획의 하루 칼로리가 바뀐다', (t) async {
    final app = await stalled();
    final before = core.jsToNumber((app.state['plan'] as Map)['macros']['intakeKcal']);
    await open(t, app, const CheckinScreen());

    expect(find.text('지난 체크인'), findsOneWidget);
    await t.enterText(find.byType(TextField), (_planW(app, 4) + 2.4).toStringAsFixed(1));
    await t.pump();
    expect(find.text('느립니다'), findsOneWidget);
    expect(find.text('하루 150kcal 줄이기'), findsOneWidget);
    /* 누르기 전에 실제로 바뀌는 숫자를 보여 줍니다. */
    expect(find.textContaining('적용하면', findRichText: true), findsOneWidget);

    await t.tap(find.text('저장하고 제안 적용'));
    await t.pumpAndSettle();
    expect(find.text('계획을 이렇게 바꿀까요?'), findsOneWidget);
    await t.tap(find.text('적용'));
    await t.pumpAndSettle();

    final plan = (app.state['plan'] as Map).cast<String, Object?>();
    final after = core.jsToNumber((plan['macros'] as Map)['intakeKcal']);
    expect(after, lessThan(before), reason: '식단 탭 목표가 이 값을 읽습니다');
    expect(before - after, lessThanOrEqualTo(150));
    final adj = (plan['adjustments'] as List).single as Map;
    final last = ((app.state['checkins'] as List).last as Map).cast<String, Object?>();
    expect(last['applied'], isTrue);
    expect(last['at'], adj['at'], reason: '조정한 체크인부터 다시 보려면 시각이 같아야 합니다');

    /* 다음 판정은 조정한 체크인부터 — 같은 정체로 또 줄이라고 하지 않습니다. */
    final again = core.checkinReview(plan, readingsFor(app.store, plan), null);
    expect(again['status'], 'early');
  });

  testWidgets('한 번 벗어나면 지켜보기만 — 적용 버튼 없음', (t) async {
    final app = await seeded(weeksAgo: 3);
    final now = DateTime.now();
    app.store.set({'checkins': [
      for (var k = 0; k < 3; k++)
        {'at': _iso(now.subtract(Duration(days: 21 - 7 * k))),
         'weightKg': double.parse((_planW(app, k) + 0.6 * k).toStringAsFixed(1))},
    ]});
    await open(t, app, const CheckinScreen());
    await t.enterText(find.byType(TextField), (_planW(app, 3) + 1.8).toStringAsFixed(1));
    await t.pump();
    expect(find.text('지켜보는 중'), findsOneWidget);
    expect(find.text('저장하고 제안 적용'), findsNothing);
  });

  testWidgets('저장만 하면 계획은 그대로', (t) async {
    final app = await stalled();
    final before = core.jsToNumber((app.state['plan'] as Map)['macros']['intakeKcal']);
    await open(t, app, const CheckinScreen());
    await t.enterText(find.byType(TextField), (_planW(app, 4) + 2.4).toStringAsFixed(1));
    await t.pump();
    await t.tap(find.text('저장만 하기 — 계획은 그대로'));
    await t.pumpAndSettle();
    expect(core.jsToNumber((app.state['plan'] as Map)['macros']['intakeKcal']), before);
    expect((app.state['checkins'] as List).length, 5);
  });

  testWidgets('같은 계획 주에 다시 저장하면 그 주 값을 새 값으로 바꾼다 — 목록에 둘 다 남지 않는다', (t) async {
    final app = await seeded();
    app.store.set({'checkins': [
      {'at': _iso(DateTime.now().subtract(const Duration(minutes: 1))), 'weightKg': 88.0, 'applied': true},
    ]});
    await open(t, app, const CheckinScreen());
    expect(find.textContaining('다시 저장하면 이번 주 값을 새 값으로', findRichText: true), findsOneWidget);
    await t.enterText(find.byType(TextField), '86.6');
    await t.pump();
    await t.tap(find.text('체크인 저장'));
    await t.pumpAndSettle();
    final list = (app.state['checkins'] as List).cast<Map>();
    expect(list, hasLength(1));
    expect(list.single['weightKg'], 86.6);
    expect(list.single['applied'], isTrue, reason: '「조정함」 표시는 남깁니다');
  });

  testWidgets('NaN 같은 글자는 막는다', (t) async {
    final app = await seeded();
    await open(t, app, const CheckinScreen());
    await t.enterText(find.byType(TextField), 'NaN');
    await t.pump();
    expect(find.textContaining('숫자로 넣어 주세요'), findsOneWidget);
    expect(t.widget<FilledButton>(find.widgetWithText(FilledButton, '체크인 저장')).onPressed, isNull);
  });

  testWidgets('홈 — 이번 주에 체크인했으면 완료로 보인다', (t) async {
    final app = await seeded(weeksAgo: 2);
    await open(t, app, Scaffold(body: HomeScreen(go: (_, [__]) {})));
    expect(find.text('이번 주 체크인'), findsOneWidget);

    app.store.set({'checkins': [
      {'at': _iso(DateTime.now()), 'weightKg': 85.4},
    ]});
    await t.pumpAndSettle();
    expect(find.text('이번 주 체크인 완료 · 85.4kg'), findsOneWidget);
  });

  testWidgets('계획 주가 바뀌어도 5일 안에 했으면 완료 — 일요일에 하고 월요일에 또 부르지 않는다', (t) async {
    final app = await seeded(weeksAgo: 2);
    /* 계획은 14일 전 시작 → 오늘은 2주차 첫날. 어제는 1주차 마지막 날. */
    app.store.set({'checkins': [
      {'at': _iso(DateTime.now().subtract(const Duration(days: 1))), 'weightKg': 85.4},
    ]});
    await open(t, app, Scaffold(body: HomeScreen(go: (_, [__]) {})));
    expect(find.text('이번 주 체크인 완료 · 85.4kg'), findsOneWidget);
  });

  testWidgets('지난주 체크인은 이번 주 완료가 아니다', (t) async {
    final app = await seeded(weeksAgo: 2);
    app.store.set({'checkins': [
      {'at': _iso(DateTime.now().subtract(const Duration(days: 8))), 'weightKg': 85.4},
    ]});
    await open(t, app, Scaffold(body: HomeScreen(go: (_, [__]) {})));
    expect(find.text('이번 주 체크인'), findsOneWidget);
    expect(find.textContaining('완료'), findsNothing);
  });

  testWidgets('추이 — 체크인 체중이 점선으로 나온다', (t) async {
    final app = await seeded(weeksAgo: 1);
    app.store.addScan({..._scan, 'id': 's2', 'weightKg': 85.9,
                       'measuredAt': _iso(DateTime.now().subtract(const Duration(days: 3)))});
    app.store.set({'checkins': [
      {'at': _iso(DateTime.now().subtract(const Duration(days: 6))), 'weightKg': 86.1},
      {'at': _iso(DateTime.now()), 'weightKg': 85.6},
    ]});
    await open(t, app, Scaffold(body: ProgressScreen(go: (_, [__]) {})));
    expect(find.textContaining('점선은 주간 체크인'), findsOneWidget);
    expect(find.text('체크인 체중'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('소수점을 빠뜨린 값(862)은 막고 이유를 말한다 — 기준점이 되면 판정이 다 틀어져서', (t) async {
    final app = await seeded();
    await open(t, app, const CheckinScreen());
    await t.enterText(find.byType(TextField), '862');
    await t.pump();
    expect(find.textContaining('20~300kg'), findsOneWidget);
    expect(t.widget<FilledButton>(find.widgetWithText(FilledButton, '체크인 저장')).onPressed, isNull);
    /* 범위 안이어도 가장 최근 기록에서 너무 다르면 막습니다(어제 체크인 86.2 → 100.2). */
    app.store.set({'checkins': [
      {'at': _iso(DateTime.now().subtract(const Duration(days: 1))), 'weightKg': 86.2},
    ]});
    await t.pump();
    await t.enterText(find.byType(TextField), '100.2');
    await t.pump();
    expect(find.textContaining('너무 많이 다릅니다'), findsOneWidget);
    expect(t.widget<FilledButton>(find.widgetWithText(FilledButton, '체크인 저장')).onPressed, isNull);
    await t.enterText(find.byType(TextField), '86.2');
    await t.pump();
    expect(t.widget<FilledButton>(find.widgetWithText(FilledButton, '체크인 저장')).onPressed, isNotNull);
  });

  testWidgets('지난 체크인을 지울 수 있다', (t) async {
    final app = await seeded(weeksAgo: 1);
    app.store.set({'checkins': [
      {'at': _iso(DateTime.now().subtract(const Duration(days: 6))), 'weightKg': 86.1},
      {'at': _iso(DateTime.now().subtract(const Duration(days: 1))), 'weightKg': 85.9},
    ]});
    await open(t, app, const CheckinScreen());
    await t.tap(find.byTooltip('지우기').first);
    await t.pumpAndSettle();
    expect(find.text('이 체크인을 지울까요?'), findsOneWidget);
    await t.tap(find.widgetWithText(FilledButton, '지우기'));
    await t.pumpAndSettle();
    final left = (app.state['checkins'] as List).cast<Map>();
    expect(left, hasLength(1));
    expect(left.single['weightKg'], 86.1, reason: '목록은 최신부터 — 맨 위(85.9)를 지웠습니다');
  });

  testWidgets('오래된 체크인보다 최근 인바디를 기준으로 — 몇 달 사이 실제로 뺀 체중을 막지 않는다', (t) async {
    final app = await seeded();
    app.store.set({'checkins': [
      {'at': _iso(DateTime.now().subtract(const Duration(days: 150))), 'weightKg': 95.0},
    ]});
    app.store.addScan({..._scan, 'id': 'recent', 'weightKg': 80.5,
                       'measuredAt': _iso(DateTime.now().subtract(const Duration(days: 1)))});
    expect(checkinWeightProblem(app.store, 80.5), isNull);
    expect(checkinWeightProblem(app.store, 805), isNotNull);
  });
}
