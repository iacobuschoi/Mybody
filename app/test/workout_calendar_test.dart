/* =============================================================================
 * workout_calendar_test.dart — 지난 운동 기록의 「달력」 (의견 84)
 *
 * "달력 이전 기록 보게 해주세요(저번주 or 저번달)" — 홈은 이번 주 일곱 칸뿐이었습니다.
 * 여기서 보는 것:
 *   · 한 달씩 ‹ › 로 넘기고, 왼쪽 끝은 처음 기록이 있는 달 · 오른쪽 끝은 이번 달.
 *   · 「처음 기록으로」 · 「이번 달로」 한 번에.
 *   · 칸은 홈과 같은 DayMark — 지난달 계획만 하고 못 한 날은 놓침, 앱 쓰기 전 날은 쉬는 날.
 *   · 날을 누르면 기록 카드(종목 · 세트) 또는 체크만 한 날의 한 줄.
 *   · 홈 「이번 주 운동」 의 달력 아이콘이 달력부터 연다.
 *   · 360 폭에서 넘치지 않는다.
 * ========================================================================== */
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mybody/src/api.dart';
import 'package:mybody/src/app_state.dart';
import 'package:mybody/src/scope.dart';
import 'package:mybody/src/screens/home.dart';
import 'package:mybody/src/screens/workout_calendar.dart';
import 'package:mybody/src/screens/workout_history.dart';
import 'package:mybody/src/theme.dart';
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

final _now = DateTime(2026, 9, 27, 18, 0);   // 일요일

Future<AppState> seeded() async {
  SharedPreferences.setMockInitialValues({});
  final app = await AppState.boot();
  app.store.now = () => _now;
  app.store.set({'profile': _profile, 'onboarded': true});
  app.store.addScan({..._scan});
  return app;
}

/// 7월에 처음 체크 · 8월에 계획만 하고 못 한 날 · 9월에 세트까지 적은 날.
Future<AppState> withHistory() async {
  final app = await seeded();
  app.store.setScheduleDone('2026-07-14', 'gym', true);
  app.store.setSchedulePlan('2026-08-05', 'gym', true);
  app.store.setScheduleDone('2026-08-07', 'cardio', true);
  app.store.setScheduleLog('2026-09-25', 'gym', {
    'kind': 'gym', 'minutes': 50, 'seconds': 3000, 'kcal': 260, 'sets': 2,
    'exercises': [
      {'name': '바벨 벤치프레스', 'sets': 2, 'of': 3, 'reps': '5-8', 'kg': 80,
       'setLog': [{'kg': 80, 'reps': 5}, {'kg': 80, 'reps': 5}]},
    ],
  });
  return app;
}

Widget host(AppState app, Widget child) {
  final api = Api(baseUrl: '', client: MockClient((_) async => http.Response('{"ok":false}', 404)));
  api.setToken('tok');
  return Scope(state: app, api: api, onServerChange: (_) async {},
      child: MaterialApp(theme: mbLight(), home: child));
}

Future<void> open(WidgetTester t, AppState app, Widget screen, {double width = 360}) async {
  t.view.physicalSize = Size(width, 1400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(host(app, screen));
  await t.pumpAndSettle();
  expect(t.takeException(), isNull);
}

String month(WidgetTester t) => t.widget<Text>(find.byKey(const ValueKey('cal-month'))).data!;
bool enabled(WidgetTester t, String key) => t.widget<IconButton>(find.byKey(ValueKey(key))).onPressed != null;
Finder markOn(String day, String state) => find.descendant(
    of: find.byKey(ValueKey('cal-day-$day')), matching: find.byKey(ValueKey('daymark-$state')));

void main() {
  test('달 셈 · 처음 기록 · 한 달 요약', () async {
    expect(calShift((year: 2026, month: 1), -1), (year: 2025, month: 12));
    expect(calShift((year: 2025, month: 12), 1), (year: 2026, month: 1));
    expect(calLabel(calMonthOf('2026-07-14')), '2026년 7월');

    final empty = await seeded();
    expect(firstScheduleKey(empty.state), isNull);

    final app = await withHistory();
    expect(firstScheduleKey(app.state), '2026-07-14');
    final aug = monthDays(app, (year: 2026, month: 8));
    expect(aug.length, 31);
    expect(aug.first['key'], '2026-08-01');
    final s = monthSummary(aug, '2026-09-27');
    expect((s.planned, s.kept, s.missed), (2, 1, 1));
  });

  testWidgets('이번 달에서 시작 → ‹ 로 지난달 → 처음 기록까지, 끝에서는 단추가 꺼진다', (t) async {
    final app = await withHistory();
    await open(t, app, const WorkoutHistoryScreen(calendar: true));
    expect(month(t), '2026년 9월');
    expect(enabled(t, 'cal-next'), isFalse, reason: '이번 달 뒤로는 안 갑니다');
    expect(enabled(t, 'cal-prev'), isTrue);
    expect(markOn('2026-09-25', 'kept'), findsOneWidget);
    expect(markOn('2026-09-27', 'rest'), findsOneWidget);

    await t.tap(find.byKey(const ValueKey('cal-prev')));
    await t.pumpAndSettle();
    expect(month(t), '2026년 8월');
    expect(markOn('2026-08-05', 'missed'), findsOneWidget);
    expect(markOn('2026-08-07', 'kept'), findsOneWidget);
    expect(find.text('이 달 계획 2일 중 1일 지킴 · 놓친 날 1일'), findsOneWidget);

    await t.tap(find.byKey(const ValueKey('cal-first')));
    await t.pumpAndSettle();
    expect(month(t), '2026년 7월');
    expect(enabled(t, 'cal-prev'), isFalse, reason: '처음 기록이 있는 달이 왼쪽 끝');
    expect(find.byKey(const ValueKey('cal-first')), findsNothing);
    expect(markOn('2026-07-14', 'kept'), findsOneWidget);
    expect(markOn('2026-07-01', 'rest'), findsOneWidget, reason: '앱 쓰기 전 날은 놓침이 아니라 쉬는 날');

    /* 체크만 한 날 — 기록 카드 대신 한 줄. */
    await t.tap(find.byKey(const ValueKey('cal-day-2026-07-14')));
    await t.pumpAndSettle();
    expect(find.text('7/14 (화)'), findsOneWidget);
    expect(find.text('헬스 — 했음'), findsOneWidget);

    await t.tap(find.byKey(const ValueKey('cal-this-month')));
    await t.pumpAndSettle();
    expect(month(t), '2026년 9월');
    expect(find.text('헬스 — 했음'), findsNothing, reason: '달을 바꾸면 고른 날은 풀립니다');

    /* 세트까지 적은 날 — 날짜별 목록과 같은 카드. */
    await t.tap(find.byKey(const ValueKey('cal-day-2026-09-25')));
    await t.pumpAndSettle();
    expect(find.text('9/25 (금)'), findsOneWidget);
    expect(find.text('바벨 벤치프레스'), findsOneWidget);
    expect(find.text('80×5 ×2'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('옆으로 밀면 한 달씩', (t) async {
    final app = await withHistory();
    await open(t, app, const WorkoutHistoryScreen(calendar: true));
    await t.fling(find.byKey(const ValueKey('cal-day-2026-09-16')), const Offset(300, 0), 1000);
    await t.pumpAndSettle();
    expect(month(t), '2026년 8월');
    await t.fling(find.byKey(const ValueKey('cal-day-2026-08-12')), const Offset(-300, 0), 1000);
    await t.pumpAndSettle();
    expect(month(t), '2026년 9월');
    /* 천천히 밀고 멈춰도(끝 속도 0) 거리로 넘어갑니다. */
    await t.drag(find.byKey(const ValueKey('cal-day-2026-09-16')), const Offset(150, 0));
    await t.pumpAndSettle();
    expect(month(t), '2026년 8월');
  });

  testWidgets('기록이 하나도 없어도 달력은 이번 달을 그린다', (t) async {
    final app = await seeded();
    await open(t, app, const WorkoutHistoryScreen(calendar: true));
    expect(month(t), '2026년 9월');
    expect(enabled(t, 'cal-prev'), isFalse);
    expect(enabled(t, 'cal-next'), isFalse);
    expect(find.text('이 달은 계획한 날이 없습니다'), findsOneWidget);
    /* 목록 쪽은 예전처럼 빈 안내. */
    await t.tap(find.text('날짜별'));
    await t.pumpAndSettle();
    expect(find.text('아직 운동 기록이 없습니다'), findsOneWidget);
  });

  testWidgets('360 폭 · 글자 1.3배에서도 넘치지 않는다', (t) async {
    final app = await withHistory();
    t.view.physicalSize = const Size(360, 1400);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(MediaQuery(
        data: const MediaQueryData(size: Size(360, 1400), textScaler: TextScaler.linear(1.3)),
        child: host(app, const WorkoutHistoryScreen(calendar: true))));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    await t.tap(find.byKey(const ValueKey('cal-day-2026-09-25')));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });

  testWidgets('홈 「이번 주 운동」 의 달력 아이콘이 달력부터 연다', (t) async {
    final app = await withHistory();
    await open(t, app, Scaffold(body: HomeScreen(go: (_, [__]) {})), width: 412);
    await t.ensureVisible(find.byKey(const ValueKey('home-workout-history')));
    await t.tap(find.byKey(const ValueKey('home-workout-history')));
    await t.pumpAndSettle();
    expect(find.text('지난 운동 기록'), findsOneWidget);
    expect(month(t), '2026년 9월');
    await t.tap(find.byKey(const ValueKey('cal-prev')));
    await t.pumpAndSettle();
    expect(month(t), '2026년 8월');
  });
}
