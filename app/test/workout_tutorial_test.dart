/* =============================================================================
 * workout_tutorial_test.dart — 헬스 화면 「따라 해 보기」 가 **실제로 가르치는가**
 *
 * 네 단계를 손으로 따라 해 봅니다(세트 · 무게 칩 · 밀어 빼기 · 꾹 눌러 옮기기).
 * 단계마다 체크가 뜨고 알아서 다음으로 가는지, 넷째를 해내면 닫히는지, 「건너뛰기」 가 늘 되는지,
 * 한 번 본 뒤에는 안 뜨는지, 그리고 연습이 실제 기록에 아무것도 남기지 않는지.
 * 헬스 화면의 첫 진입(튜토리얼 → 건너뛴 사람의 첫 줄 힌트)도 여기서 봅니다.
 * ========================================================================== */
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mybody/src/api.dart';
import 'package:mybody/src/app_state.dart';
import 'package:mybody/src/scope.dart';
import 'package:mybody/src/screens/settings.dart';
import 'package:mybody/src/screens/workout_session.dart';
import 'package:mybody/src/screens/workout_tutorial.dart';
import 'package:mybody/src/theme.dart';
import 'package:mybody/src/workout/exercises.dart';
import 'package:mybody/src/workout/loads.dart';
import 'package:mybody/src/workout/routines.dart';
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

/// 시험의 오늘 — 2026-09-27 일요일 저녁(workout_screens_test 와 같은 날).
final _today = DateTime(2026, 9, 27, 18, 0);

/// 연습 줄들의 손잡이 — 화면이 종목 이름의 slug 로 키를 답니다.
final Finder practiceRow = find.byKey(ValueKey('ex-${slugOf('연습 종목')}'));
final Finder otherRow = find.byKey(ValueKey('ex-${slugOf('다른 종목')}'));
final Finder practiceSet = find.byKey(ValueKey('set-${slugOf('연습 종목')}'));
final Finder practiceKg = find.byKey(ValueKey('kg-${slugOf('연습 종목')}'));
final Finder check = find.byKey(const ValueKey('tut-check'));
final Finder skip = find.byKey(const ValueKey('tut-skip'));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  DateTime now = _today;
  setUp(() {
    now = _today;
    WorkoutSessionScreen.clock = () => now;
  });
  tearDown(() => WorkoutSessionScreen.clock = DateTime.now);

  /// 처음 온 사람 — settings 가 비어 있습니다. 플랜은 헬스 화면을 여는 시험에만.
  Future<AppState> fresh({bool withPlan = false}) async {
    SharedPreferences.setMockInitialValues({});
    final app = await AppState.boot();
    app.store.now = () => now;
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

  String gymDay(AppState app) {
    final sessions = ((app.state['plan'] as Map)['workout'] as Map)['sessions'] as List;
    for (var i = 0; i < 7; i++) {
      if ((sessions[i] as Map)['rest'] != true) return '2026-09-${(21 + i).toString().padLeft(2, '0')}';
    }
    fail('플랜에 운동일이 없습니다');
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

  void size(WidgetTester t, double width) {
    t.view.physicalSize = Size(width, width < 500 ? 800 : 4000);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
  }

  Map<String, Object?> settings(AppState app) =>
      ((app.state['settings'] as Map?) ?? const {}).cast<String, Object?>();

  /// settings 중 헬스 화면의 표만 — 스토어가 기본으로 넣는 것(theme 등)은 뺍니다.
  Map<String, Object?> gymFlags(AppState app) =>
      {for (final e in settings(app).entries) if (e.key.startsWith('gym')) e.key: e.value};

  String step(WidgetTester t) => t.widget<Text>(find.byKey(const ValueKey('tut-step'))).data!;

  /// 네 단계를 끝까지 — 단계마다 해내면 체크가 뜨고 잠깐 뒤 알아서 다음 장, 넷째 뒤엔 닫힙니다.
  Future<void> followAll(WidgetTester t) async {
    /* ① 세트 */
    expect(step(t), '1/4');
    expect(check, findsNothing);
    expect(practiceSet, findsOneWidget);
    expect(find.byType(ExerciseRow), findsOneWidget, reason: '연습 줄은 실제 줄과 같은 위젯');
    await t.tap(practiceSet);
    await t.pump();
    expect(check, findsOneWidget, reason: '해내면 체크');
    expect(step(t), '1/4', reason: '체크를 보여 준 뒤에 넘어갑니다');
    await t.pump(const Duration(milliseconds: 800));
    expect(step(t), '2/4');
    expect(check, findsNothing);
    expect(t.takeException(), isNull);

    /* ② 무게 칩 → 실제와 같은 스테퍼 */
    expect(find.descendant(of: practiceKg, matching: find.text('추천 20kg')), findsOneWidget);
    await t.tap(practiceKg);
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('kg-value')), findsOneWidget, reason: '헬스 화면의 스테퍼 그대로');
    await t.tap(find.byKey(const ValueKey('kg-plus')));
    await t.pump();
    await t.tap(find.byKey(const ValueKey('kg-ok')));
    await t.pumpAndSettle();
    final up = kgText(20 + stepFor('machine', 20));
    expect(find.descendant(of: practiceKg, matching: find.text('${up}kg')), findsOneWidget, reason: '정한 무게가 칩에 — 머신 단위만큼');
    expect(check, findsOneWidget);
    await t.pump(const Duration(milliseconds: 800));
    expect(step(t), '3/4');
    expect(t.takeException(), isNull);

    /* ③ 밀어 빼기 — 먼저 힌트가 살짝 밀렸다 돌아오고, 그건 빼는 게 아닙니다 */
    expect(find.byType(SwipeHint), findsOneWidget);
    await t.pump(const Duration(seconds: 2));
    expect(practiceRow, findsOneWidget, reason: '힌트는 그림만 움직입니다');
    expect(check, findsNothing);
    await t.drag(practiceRow, const Offset(-700, 0));
    await t.pumpAndSettle();
    expect(practiceRow, findsNothing);
    expect(check, findsOneWidget);
    await t.pump(const Duration(milliseconds: 800));
    expect(step(t), '4/4');
    expect(t.takeException(), isNull);

    /* ④ 꾹 눌러 옮기기 — 연습 줄이 다시 서고, 「다른 종목」 아래로 */
    expect(practiceRow, findsOneWidget);
    expect(otherRow, findsOneWidget);
    expect(t.getTopLeft(practiceRow).dy, lessThan(t.getTopLeft(otherRow).dy));
    await longPressDrag(t, practiceRow, t.getCenter(otherRow) + const Offset(0, 40));
    expect(t.getTopLeft(otherRow).dy, lessThan(t.getTopLeft(practiceRow).dy), reason: '자리가 바뀌었습니다');
    expect(check, findsOneWidget);
    expect(skip, findsOneWidget, reason: '건너뛰기는 끝까지 있습니다');
    /* 넷째를 해내면 체크 뒤에 알아서 닫힙니다 — 「시작하기」 도 글로 된 안내 장도 없습니다. */
    await t.pump(const Duration(milliseconds: 800));
    await t.pumpAndSettle();
    expect(find.byType(WorkoutTutorial), findsNothing);
    expect(find.byKey(const ValueKey('tut-start')), findsNothing);
    expect(find.textContaining('이제 진짜로'), findsNothing);
    expect(t.takeException(), isNull);
  }

  group('WorkoutTutorial.show', () {
    testWidgets('네 단계를 따라 하면 true 로 닫히고, 본 것 · 힌트 본 것으로 적히며, 기록에는 아무것도 없다', (t) async {
      final app = await fresh();
      size(t, 1000);
      bool? result;
      await t.pumpWidget(host(app, _Launch(onResult: (r) => result = r)));
      await t.tap(find.text('열기'));
      await t.pumpAndSettle();
      expect(find.byType(WorkoutTutorial), findsOneWidget);
      expect(WorkoutTutorial.seen(app.state), isFalse, reason: '보는 중에는 아직');

      await followAll(t);

      expect(result, isTrue);
      expect(WorkoutTutorial.seen(app.state), isTrue);
      expect(gymFlags(app), {kGymTutorialSeenKey: true, kGymSwipeHintSeenKey: true},
          reason: '끝까지 한 사람은 밀어 빼기도 해 봤습니다 — 어디서 열었든 show 가 적습니다');
      expect(routinesOf(app), isEmpty);
      expect((app.state['schedule'] as Map?) ?? const {}, isEmpty, reason: '연습 세트는 기록이 아닙니다');
    });

    testWidgets('「건너뛰기」 — 어느 장에서든 false 로 닫히고, 그래도 본 것으로 적힌다', (t) async {
      final app = await fresh();
      size(t, 1000);
      bool? result;
      await t.pumpWidget(host(app, _Launch(onResult: (r) => result = r)));
      await t.tap(find.text('열기'));
      await t.pumpAndSettle();
      /* 한 장 넘긴 뒤에 건너뜁니다 */
      await t.tap(practiceSet);
      await t.pump(const Duration(milliseconds: 800));
      expect(step(t), '2/4');
      await t.tap(skip);
      await t.pumpAndSettle();
      expect(find.byType(WorkoutTutorial), findsNothing);
      expect(result, isFalse);
      expect(WorkoutTutorial.seen(app.state), isTrue, reason: '건너뛴 사람에게 다음에 또 올리면 방해입니다');
      expect(routinesOf(app), isEmpty);
    });

    testWidgets('360px — 네 장 모두 넘치지 않는다', (t) async {
      final app = await fresh();
      size(t, 360);
      await t.pumpWidget(host(app, _Launch(onResult: (_) {})));
      await t.tap(find.text('열기'));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await followAll(t);
    });
  });

  group('헬스 화면 첫 진입', () {
    testWidgets('처음이면 튜토리얼이 뜨고, 건너뛰면 다음부턴 안 뜨며 첫 줄 힌트가 한 번 온다', (t) async {
      final app = await fresh(withPlan: true);
      final day = gymDay(app);
      size(t, 1000);
      await t.pumpWidget(host(app, WorkoutSessionScreen(dateKey: day, type: 'gym')));
      await t.pumpAndSettle();
      expect(find.byType(WorkoutTutorial), findsOneWidget, reason: '첫 진입');
      expect(step(t), '1/4');

      await t.tap(skip);
      /* 길이 내려가는 동안 — 전환(0.8초)이 끝나는 프레임까지만 돌립니다. pumpAndSettle 은
         힌트까지 다 돌려 버려서 힌트가 떴는지 볼 수 없습니다. */
      for (var i = 0; i < 20 && find.byType(WorkoutTutorial).evaluate().isNotEmpty; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(WorkoutTutorial), findsNothing);
      expect(WorkoutTutorial.seen(app.state), isTrue);
      expect(find.byType(SwipeHint), findsOneWidget, reason: '건너뛴 사람에게는 첫 줄 힌트');
      expect(settings(app)[kGymSwipeHintSeenKey], isNull, reason: '아직 안 보여 줬습니다');
      await t.pumpAndSettle();                                  // 힌트가 끝까지
      expect(find.byType(SwipeHint), findsNothing);
      expect(settings(app)[kGymSwipeHintSeenKey], isTrue);
      expect(find.text('되돌리기'), findsNothing, reason: '힌트는 빼지 않습니다');
      expect(t.takeException(), isNull);

      /* 다시 열면 — 튜토리얼도 힌트도 없음 */
      await t.pumpWidget(host(app, WorkoutSessionScreen(dateKey: day, type: 'gym')));
      await t.pumpAndSettle();
      expect(find.byType(WorkoutTutorial), findsNothing);
      expect(find.byType(SwipeHint), findsNothing);
      expect(find.byType(ExerciseRow), findsWidgets);
    });

    testWidgets('끝까지 따라 한 사람에게는 첫 줄 힌트도 없다 — 이미 밀어 봤으니까', (t) async {
      final app = await fresh(withPlan: true);
      final day = gymDay(app);
      size(t, 1000);
      await t.pumpWidget(host(app, WorkoutSessionScreen(dateKey: day, type: 'gym')));
      await t.pumpAndSettle();
      expect(find.byType(WorkoutTutorial), findsOneWidget);
      await followAll(t);
      await t.pumpAndSettle();
      expect(find.byType(SwipeHint), findsNothing);
      expect(gymFlags(app), {kGymTutorialSeenKey: true, kGymSwipeHintSeenKey: true});
      expect(find.byType(ExerciseRow), findsWidgets, reason: '돌아오면 실제 종목 줄');
      expect(find.text('0/${_totalSets(app, day)} 세트'), findsOneWidget, reason: '연습 세트는 셈에 안 들어갑니다');
      expect((app.store.scheduleDay(day)['log'] as Map?) ?? const {}, isEmpty);
    });

    testWidgets('유산소 · 맨몸 화면에는 안 뜬다 — 헬스 화면의 길을 가르치는 것이니까', (t) async {
      final app = await fresh(withPlan: true);
      size(t, 1000);
      for (final type in ['cardio', 'bodyweight']) {
        await t.pumpWidget(host(app, WorkoutSessionScreen(dateKey: '2026-09-27', type: type)));
        await t.pumpAndSettle();
        expect(find.byType(WorkoutTutorial), findsNothing, reason: type);
      }
      expect(WorkoutTutorial.seen(app.state), isFalse);
    });

    testWidgets('설정의 줄 이름은 화면 제목과 같은 「헬스 화면 따라 해 보기」 — 거기서 다시 연다', (t) async {
      final app = await fresh();
      WorkoutTutorial.markSeen(app);
      size(t, 1000);
      await t.pumpWidget(host(app, const SettingsScreen()));
      await t.pump(const Duration(milliseconds: 200));
      expect(find.text('헬스 화면 도움말 다시 보기'), findsNothing, reason: '같은 것에 이름 둘이면 안 됩니다');
      final line = find.text(kGymTutorialTitle);
      expect(line, findsOneWidget);
      await t.ensureVisible(line);
      await t.tap(line);
      await t.pumpAndSettle();
      expect(find.byType(WorkoutTutorial), findsOneWidget);
      await t.tap(skip);
      await t.pumpAndSettle();
      expect(find.byType(WorkoutTutorial), findsNothing);
      expect(find.byType(SettingsScreen), findsOneWidget);
    });

    testWidgets('설정에서 열어 끝까지 하면 첫 줄 힌트도 본 것으로 적힌다 — 첫 헬스 진입에 힌트가 또 뜨지 않게', (t) async {
      final app = await fresh();
      size(t, 1000);
      await t.pumpWidget(host(app, const SettingsScreen()));
      await t.pump(const Duration(milliseconds: 200));
      final line = find.text(kGymTutorialTitle);
      await t.ensureVisible(line);
      await t.tap(line);
      await t.pumpAndSettle();
      await followAll(t);
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(gymFlags(app), {kGymTutorialSeenKey: true, kGymSwipeHintSeenKey: true});
      expect(WorkoutTutorial.swipeHintSeen(app.state), isTrue);
    });
  });
}

int _totalSets(AppState app, String day) =>
    gymExercisesFor(app.state, day).fold<int>(0, (a, e) => a + core.jsToNumber(e['sets']).round());

/// 꾹 눌러(긴 누름) 끌어다 놓기 — ReorderableDelayedDragStartListener 는 kLongPressTimeout 뒤에
/// 끌기를 시작합니다. 몇 걸음에 나눠 움직여야 목록이 자리를 바꿉니다.
Future<void> longPressDrag(WidgetTester t, Finder from, Offset to) async {
  final start = t.getCenter(from);
  final g = await t.startGesture(start);
  await t.pump(kLongPressTimeout + const Duration(milliseconds: 50));
  for (var i = 1; i <= 6; i++) {
    await g.moveTo(Offset.lerp(start, to, i / 6)!);
    await t.pump(const Duration(milliseconds: 16));
  }
  await g.up();
  await t.pumpAndSettle();
}

/// 튜토리얼을 여는 자리 — 닫히면 답(끝까지 했는가)을 받아 둡니다.
class _Launch extends StatelessWidget {
  const _Launch({required this.onResult});
  final ValueChanged<bool> onResult;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: FilledButton(
            onPressed: () async => onResult(await WorkoutTutorial.show(context)),
            child: const Text('열기'),
          ),
        ),
      );
}
