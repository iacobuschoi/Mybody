/* =============================================================================
 * workout_screens_test.dart — 헬스장에서 쓰는 화면들이 **실제로 기록을 남기는가**
 *
 * 화면이 서는지(회색 네모)만이 아니라, 세트 버튼이 올라가고 「저장」 이
 * 코어의 일정 기록(setScheduleLog)에 분 · kcal 을 남기는지까지 봅니다.
 * 시계는 [WorkoutSessionScreen.clock] 과 store.now 로 세워 둡니다 — 시험이
 * 진짜 40분을 기다릴 수는 없습니다.
 * ========================================================================== */
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mybody/src/api.dart';
import 'package:mybody/src/app_state.dart';
import 'package:mybody/src/nudge.dart';
import 'package:mybody/src/scope.dart';
import 'package:mybody/src/screens/workout_session.dart';
import 'package:mybody/src/theme.dart';
import 'package:mybody/src/ui/confetti.dart';
import 'package:mybody/src/ui/fmt.dart';
import 'package:mybody/src/ui/widgets.dart';
import 'package:mybody/src/workout/exercises.dart';
import 'package:mybody/src/workout/kcal.dart';
import 'package:mybody/src/workout/loads.dart';
import 'package:mybody/src/workout/planner.dart';
import 'package:mybody/src/workout/prefs.dart';
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

/// 시험의 오늘 — 2026-09-27 일요일 저녁. 그 주 월~일이 전부 "지난 날 또는 오늘" 이라
/// 플랜의 어느 요일 세션이든 기록할 수 있습니다.
final _today = DateTime(2026, 9, 27, 18, 0);
const _todayKey = '2026-09-27';
const _tomorrowKey = '2026-09-28';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /* 시계를 세웁니다. 화면(경과 시간)과 코어(오늘이 며칠인가)가 같은 시각을 봐야
     "앞날" 판정이 흔들리지 않습니다. */
  DateTime now = _today;
  setUp(() {
    now = _today;
    WorkoutSessionScreen.clock = () => now;
  });
  tearDown(() => WorkoutSessionScreen.clock = DateTime.now);

  Future<AppState> seeded({bool withPlan = true}) async {
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

  /// 플랜에서 쉬는 날이 아닌 첫 요일 — 이번 주(9/21 월 ~ 9/27 일)의 그 날짜.
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

  /* Scope 는 MaterialApp 위에 — 앱이 실제로 그렇게 둡니다(screens_smoke_test 참고). */
  Widget host(AppState app, Widget child) => Scope(
        state: app,
        api: api(),
        onServerChange: (_) async {},
        child: MaterialApp(theme: mbLight(), home: child),
      );

  /// 화면을 **밀어 올려서** 엽니다 — 저장하면 pop 하므로 돌아갈 자리가 있어야 하고,
  /// 토스트도 그 자리의 Scaffold 에 뜹니다.
  Future<void> open(WidgetTester t, AppState app, Widget screen) async {
    t.view.physicalSize = const Size(1000, 4000);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(host(app, _Launch(child: screen)));
    await t.tap(find.text('열기'));
    await t.pumpAndSettle();
    expect(find.byType(ErrorWidget), findsNothing);
    expect(t.takeException(), isNull);
  }

  Map<String, Object?> logOf(AppState app, String dateKey, String type) {
    final day = app.store.scheduleDay(dateKey);
    final log = (day['log'] as Map?)?[type];
    expect(log, isA<Map>(), reason: '$dateKey 의 $type 기록이 없습니다: $day');
    return (log as Map).cast<String, Object?>();
  }

  group('헬스', () {
    testWidgets('플랜의 오늘 종목이 나오고, 세트 버튼이 올라가며 휴식이 시작된다', (t) async {
      final app = await seeded();
      final day = gymDay(app);
      final session = planSessionFor(app.state, day)!;
      final tailored = tailorSession(session, GymPrefs.fromSettings(null));
      expect(tailored, isNotEmpty);

      await open(t, app, WorkoutSessionScreen(dateKey: day, type: 'gym'));
      for (final e in tailored) {
        expect(find.text('${e['name']}'), findsWidgets, reason: '종목 ${e['name']} 이 화면에 없습니다');
      }
      /* 진행은 머리글의 '0/N 세트' 하나로 읽습니다 — 줄마다 있던 '세트 완료 (0/3)'
         버튼은 없어졌고(주인이 "못생겼다" 고 했습니다) 줄에는 작은 「세트」 단추뿐입니다. */
      final total = tailored.fold<int>(0, (a, e) => a + core.jsToNumber(e['sets']).round());
      final first = '${tailored.first['name']}';
      expect(find.text('0/$total 세트'), findsOneWidget);
      expect(setButton(first), findsOneWidget);
      expect(find.text('건너뛰기'), findsNothing);
      expect(find.byTooltip('한 세트 빼기'), findsNothing, reason: '뺄 세트가 없으면 「−」 도 없습니다');

      await t.tap(setButton(first));
      await t.pump();
      expect(find.text('1/$total 세트'), findsOneWidget);
      expect(find.text('건너뛰기'), findsOneWidget, reason: '세트를 마치면 휴식 카운트다운이 뜹니다');
      expect(find.text('일시정지'), findsOneWidget, reason: '시작을 안 눌렀어도 세트를 누르면 시간이 갑니다');

      /* 휴식은 시계로 잽니다 — 쉬는 시간이 지나면 사라집니다. */
      final restSec = core.jsToNumber(tailored.first['restSec']).round();
      now = now.add(Duration(seconds: restSec + 1));
      await t.pump(const Duration(seconds: 1));
      expect(find.text('건너뛰기'), findsNothing);

      /* 한 세트 빼기 */
      await t.tap(find.byTooltip('한 세트 빼기').first);
      await t.pump();
      expect(find.text('0/$total 세트'), findsOneWidget);
      expect(find.text('1/$total 세트'), findsNothing);
      expect(find.byTooltip('한 세트 빼기'), findsNothing);

      /* 줄 어디를 눌러도 한 세트 — 단추만 표적이면 땀 난 손에는 너무 작습니다. */
      await t.tap(exerciseRow(first));
      await t.pump();
      expect(find.text('1/$total 세트'), findsOneWidget);
    });

    testWidgets('종료 → 저장하면 분 · kcal · 세트가 그 날 기록에 남고 체크된다', (t) async {
      final app = await seeded();
      final day = gymDay(app);
      await open(t, app, WorkoutSessionScreen(dateKey: day, type: 'gym'));

      await t.tap(find.text('시작'));
      await t.pump();
      now = now.add(const Duration(minutes: 40));
      await t.pump(const Duration(seconds: 1));
      expect(find.text('40:00'), findsOneWidget, reason: '경과는 시계로 잽니다');

      /* 첫 종목 한 세트 */
      await t.tap(anySetButton().first);
      await t.pump();

      await t.tap(find.text('종료'));
      await t.pumpAndSettle();
      final weight = latestWeightKg(app)!;
      final expectKcal =
          workoutKcal(weightKg: weight, duration: const Duration(minutes: 40), kind: 'gym').round();
      /* 시계로 쟀으면 잰 시간이 그대로 — 입력칸은 없습니다. */
      expect(find.descendant(of: find.byType(Stat), matching: find.text('40:00')), findsOneWidget);
      expect(find.widgetWithText(TextField, '운동 시간'), findsNothing, reason: '쟀는데 또 묻지 않습니다');
      expect(find.descendant(of: find.byType(Stat), matching: find.text(n0(expectKcal))), findsOneWidget);

      await t.tap(find.text('저장'));
      await t.pumpAndSettle();

      final log = logOf(app, day, 'gym');
      expect(log['kind'], 'gym');
      expect(log['minutes'], 40);
      expect(log['seconds'], 2400);
      expect(core.jsToNumber(log['kcal']), greaterThan(0));
      expect(log['kcal'], expectKcal);
      expect(log['sets'], 1);
      expect((log['exercises'] as List), hasLength(1));
      expect(core.jsTruthy((app.store.scheduleDay(day)['done'] as Map)['gym']), isTrue, reason: '기록하면 그 날이 체크됩니다');
      /* 스낵바가 아니라 폭죽 — 헬스도 맨몸 운동과 같은 축하를 받습니다. */
      expect(find.textContaining('kcal 소모했어요! 축하합니다'), findsOneWidget);
      expect(find.textContaining('헬스 40:00'), findsOneWidget);
      expect(find.byType(Confetti), findsOneWidget);
      await t.tap(find.text('닫기'));
      await t.pumpAndSettle();
      expect(find.byType(WorkoutSessionScreen), findsNothing, reason: '축하를 닫으면 화면도 닫힙니다');
    });

    testWidgets('9초만 재고 종료해도 잰 값으로 저장된다 — 1분 미만이라고 다시 묻지 않는다', (t) async {
      final app = await seeded();
      final day = gymDay(app);
      await open(t, app, WorkoutSessionScreen(dateKey: day, type: 'gym'));
      await t.tap(find.text('시작'));
      await t.pump();
      now = now.add(const Duration(seconds: 9));
      await t.pump(const Duration(seconds: 1));
      await t.tap(find.text('종료'));
      await t.pumpAndSettle();
      expect(find.descendant(of: find.byType(Stat), matching: find.text('00:09')), findsOneWidget);
      expect(find.widgetWithText(TextField, '운동 시간'), findsNothing);
      final save = t.widget<FilledButton>(find.widgetWithText(FilledButton, '저장'));
      expect(save.onPressed, isNotNull, reason: '9초도 잰 값입니다');
      await t.tap(find.text('저장'));
      await t.pumpAndSettle();
      final log = logOf(app, day, 'gym');
      expect(log['seconds'], 9);
      expect(log['minutes'], 1, reason: '기록의 분은 1 아래로 안 내려갑니다');
      await t.tap(find.text('닫기'));
      await t.pumpAndSettle();
    });

    testWidgets('시작을 안 눌렀으면 분을 넣는 칸이 나온다', (t) async {
      final app = await seeded();
      final day = gymDay(app);
      await open(t, app, WorkoutSessionScreen(dateKey: day, type: 'gym'));
      await t.tap(find.text('종료'));
      await t.pumpAndSettle();
      expect(find.widgetWithText(TextField, '운동 시간'), findsOneWidget);
      expect(t.widget<FilledButton>(find.widgetWithText(FilledButton, '저장')).onPressed, isNull);
      await t.enterText(find.widgetWithText(TextField, '운동 시간'), '35');
      await t.pump();
      await t.tap(find.text('저장'));
      await t.pumpAndSettle();
      final log = logOf(app, day, 'gym');
      expect(log['minutes'], 35);
      expect(log['seconds'], 2100);
      expect(find.textContaining('헬스 35분'), findsOneWidget);
      await t.tap(find.text('닫기'));
      await t.pumpAndSettle();
    });

    testWidgets('세트를 누르고 같은 초에 종료해도 갇히지 않는다 — 0초면 분 칸이 나온다', (t) async {
      final app = await seeded();
      final day = gymDay(app);
      await open(t, app, WorkoutSessionScreen(dateKey: day, type: 'gym'));
      /* 세트를 누르면 시계가 알아서 켜집니다 — 시계를 안 움직인 채 바로 종료. */
      await t.tap(anySetButton().first);
      await t.pump();
      expect(find.text('일시정지'), findsOneWidget);
      await t.tap(find.text('종료'));
      await t.pumpAndSettle();
      expect(find.widgetWithText(TextField, '운동 시간'), findsOneWidget, reason: '0초는 잰 시간이 아닙니다');
      expect(t.widget<FilledButton>(find.widgetWithText(FilledButton, '저장')).onPressed, isNull);
      await t.enterText(find.widgetWithText(TextField, '운동 시간'), '20');
      await t.pump();
      await t.tap(find.text('저장'));
      await t.pumpAndSettle();
      final log = logOf(app, day, 'gym');
      expect(log['minutes'], 20);
      expect(log['seconds'], 1200);
      expect(log['sets'], 1);
      expect(find.textContaining('헬스 20분'), findsOneWidget);
      await t.tap(find.text('닫기'));
      await t.pumpAndSettle();
    });

    testWidgets('플랜이 없어도 전신 기본 종목이 나온다', (t) async {
      final app = await seeded(withPlan: false);
      await open(t, app, WorkoutSessionScreen(dateKey: _todayKey, type: 'gym'));
      expect(find.text('오늘 플랜에 없는 날 — 전신 기본 종목'), findsOneWidget);
      expect(anySetButton(), findsWidgets);
      expect(find.textContaining(RegExp(r'^0/\d+ 세트$')), findsOneWidget, reason: '아직 한 세트도 안 했습니다');
    });
  });

  group('유산소', () {
    testWidgets('시간을 직접 넣기 — 5km · 30분 달리기의 kcal 을 보여 주고 저장한다', (t) async {
      final app = await seeded();
      await open(t, app, WorkoutSessionScreen(dateKey: _todayKey, type: 'cardio'));

      await t.tap(find.text('시간을 직접 넣기'));
      await t.pumpAndSettle();
      await t.tap(find.text('달리기'));
      await t.pump();
      await t.enterText(find.widgetWithText(TextField, '시간'), '30');
      await t.enterText(find.widgetWithText(TextField, '거리'), '5');
      await t.pump();

      final weight = latestWeightKg(app)!;
      final expectKcal =
          workoutKcal(weightKg: weight, duration: const Duration(minutes: 30), kind: 'run', km: 5);
      expect(expectKcal, greaterThan(0));
      expect(find.descendant(of: find.byType(Stat), matching: find.text(n0(expectKcal))), findsOneWidget,
          reason: '거리와 시간을 넣으면 kcal 이 바로 바뀝니다');

      await t.tap(find.text('저장'));
      await t.pumpAndSettle();
      final log = logOf(app, _todayKey, 'cardio');
      expect(log['kind'], 'run');
      expect(log['minutes'], 30);
      expect(log['seconds'], 1800);
      expect(log['km'], 5.0);
      expect(log['kcal'], expectKcal.round());
      expect(core.jsTruthy((app.store.scheduleDay(_todayKey)['done'] as Map)['cardio']), isTrue);
      expect(find.textContaining('kcal 소모했어요! 축하합니다'), findsOneWidget);
      expect(find.textContaining('달리기 30분 · 5.0km'), findsOneWidget);
      await t.tap(find.text('닫기'));
      await t.pumpAndSettle();
      expect(find.byType(WorkoutSessionScreen), findsNothing);
    });

    testWidgets('시계로 잰 시간은 그대로 쓴다 — 종료 시트에 시간 칸이 없다', (t) async {
      final app = await seeded();
      await open(t, app, WorkoutSessionScreen(dateKey: _todayKey, type: 'cardio'));
      await t.tap(find.text('시작'));
      await t.pump();
      now = now.add(const Duration(minutes: 25, seconds: 40));
      await t.pump(const Duration(seconds: 1));
      await t.tap(find.text('종료'));
      await t.pumpAndSettle();
      expect(find.widgetWithText(TextField, '시간'), findsNothing, reason: '쟀는데 또 묻지 않습니다');
      expect(find.descendant(of: find.byType(Stat), matching: find.text('25:40')), findsOneWidget);
      expect(find.widgetWithText(TextField, '거리'), findsOneWidget, reason: '거리는 시계가 모릅니다');
      await t.tap(find.text('저장'));
      await t.pumpAndSettle();
      final log = logOf(app, _todayKey, 'cardio');
      expect(log['seconds'], 25 * 60 + 40);
      expect(log['minutes'], 26, reason: '25분 40초는 26분으로 반올림');
      expect(log['km'], isNull);
      expect(find.textContaining('걷기 25:40'), findsOneWidget);
      await t.tap(find.text('닫기'));
      await t.pumpAndSettle();
    });

    testWidgets('시계를 켜면 「시간을 직접 넣기」 는 사라진다 — 종료 시트에 분 칸이 없으니까', (t) async {
      final app = await seeded();
      await open(t, app, WorkoutSessionScreen(dateKey: _todayKey, type: 'cardio'));
      expect(find.text('시간을 직접 넣기'), findsOneWidget);
      await t.tap(find.text('시작'));
      await t.pump();
      expect(find.text('시간을 직접 넣기'), findsNothing);
    });
  });

  group('집에서 맨몸', () {
    testWidgets('다 체크하고 전체 완료하면 bodyweight 기록이 남고 축하가 뜬다', (t) async {
      final app = await seeded();
      await open(t, app, WorkoutSessionScreen(dateKey: _todayKey, type: 'bodyweight'));

      final boxes = find.byType(CheckboxListTile);
      expect(boxes, findsWidgets, reason: '오늘 할 맨몸 종목이 있어야 합니다');
      FilledButton doneBtn() => t.widget<FilledButton>(find.widgetWithText(FilledButton, '전체 완료'));
      expect(doneBtn().onPressed, isNull, reason: '하나도 안 했으면 완료할 수 없습니다');

      final n = t.widgetList(boxes).length;
      for (var i = 0; i < n; i++) {
        await t.tap(boxes.at(i));
        await t.pump();
      }
      expect(doneBtn().onPressed, isNotNull);
      await t.tap(find.text('전체 완료'));
      await t.pumpAndSettle();

      expect(find.textContaining('kcal 소모했어요! 축하합니다'), findsOneWidget);
      expect(find.text('오늘 계획을 지켰습니다 — 내일도 만나요'), findsOneWidget);
      final log = logOf(app, _todayKey, 'gym');
      expect(log['kind'], 'bodyweight');
      expect(core.jsToNumber(log['minutes']), greaterThan(0));
      expect(core.jsToNumber(log['kcal']), greaterThan(0));
      expect((log['exercises'] as List), hasLength(n));
      expect(core.jsTruthy((app.store.scheduleDay(_todayKey)['done'] as Map)['gym']), isTrue);

      await t.tap(find.text('닫기'));
      await t.pumpAndSettle();
      expect(find.byType(WorkoutSessionScreen), findsNothing, reason: '축하를 닫으면 화면도 닫힙니다');
    });

    testWidgets('60% 넘게 했으면 확인을 받고 그만큼만 기록한다', (t) async {
      final app = await seeded();
      await open(t, app, WorkoutSessionScreen(dateKey: _todayKey, type: 'bodyweight'));
      final boxes = find.byType(CheckboxListTile);
      final n = t.widgetList(boxes).length;
      final need = (n * 0.6).ceil();
      for (var i = 0; i < need; i++) {
        await t.tap(boxes.at(i));
        await t.pump();
      }
      await t.tap(find.text('전체 완료'));
      await t.pumpAndSettle();
      expect(find.text('기록하기'), findsOneWidget, reason: '다 안 했으면 먼저 묻습니다');
      await t.tap(find.text('기록하기'));
      await t.pumpAndSettle();
      final log = logOf(app, _todayKey, 'gym');
      expect(log['kind'], 'bodyweight');
      expect((log['exercises'] as List), hasLength(need));
    });
  });

  group('아직 오지 않은 날', () {
    testWidgets('헬스 — 안내가 뜨고 저장이 막힌다', (t) async {
      final app = await seeded();
      await open(t, app, WorkoutSessionScreen(dateKey: _tomorrowKey, type: 'gym'));
      expect(find.textContaining('아직 오지 않은 날입니다'), findsOneWidget);
      await t.tap(find.text('시작'));
      await t.pump();
      now = now.add(const Duration(minutes: 10));
      await t.tap(find.text('종료'));
      await t.pumpAndSettle();
      final save = t.widget<FilledButton>(find.widgetWithText(FilledButton, '저장'));
      expect(save.onPressed, isNull);
      expect((app.store.scheduleDay(_tomorrowKey)['log'] as Map?) ?? const {}, isEmpty);
    });

    testWidgets('맨몸 — 전체 완료가 막힌다', (t) async {
      final app = await seeded();
      await open(t, app, WorkoutSessionScreen(dateKey: _tomorrowKey, type: 'bodyweight'));
      expect(find.textContaining('아직 오지 않은 날입니다'), findsOneWidget);
      final boxes = find.byType(CheckboxListTile);
      final n = t.widgetList(boxes).length;
      for (var i = 0; i < n; i++) {
        await t.tap(boxes.at(i));
        await t.pump();
      }
      final btn = t.widget<FilledButton>(find.widgetWithText(FilledButton, '전체 완료'));
      expect(btn.onPressed, isNull);
    });
  });

  group('헬스 — 이 화면에서 고치기 (무게 · 세트 초과 · 종목 추가/제거 · 내 루틴)', () {
    /// 오늘 목록에서 무게가 있는 첫 종목과 그 추천 무게 — 화면과 같은 재료로 계산합니다.
    (Map<String, Object?>, Load) weightedFirst(AppState app, String day) {
      final plan = gymExercisesFor(app.state, day);
      final target = plan.firstWhere((m) => stepFor('${m['equip']}', 1) > 0,
          orElse: () => fail('무게 있는 종목이 하나도 없습니다: $plan'));
      final load = recommendLoad(
          name: '${target['name']}', reps: '${target['reps']}', profile: _profile,
          weightKg: latestWeightKg(app), smmKg: latestSmmKg(app));
      expect(load.kg, isNotNull);
      expect(load.source, 'body');
      return (target, load);
    }

    /// 종료 → 분 넣고 저장 → 축하 닫기.
    Future<void> finish(WidgetTester t, {bool routine = false, String? routineName}) async {
      await t.tap(find.text('종료'));
      await t.pumpAndSettle();
      await t.enterText(find.widgetWithText(TextField, '운동 시간'), '30');
      await t.pump();
      if (routine) {
        await t.tap(find.byKey(const ValueKey('routine-save')));
        await t.pumpAndSettle();
        if (routineName != null) {
          await t.enterText(find.byKey(const ValueKey('routine-name')), routineName);
          await t.pump();
        }
      }
      await t.tap(find.text('저장'));
      await t.pumpAndSettle();
      await t.tap(find.text('닫기'));
      await t.pumpAndSettle();
    }

    testWidgets('무게 칩 — 체성분 추천이 보이고, 스테퍼로 올리면 그 kg 이 기록에 남는다', (t) async {
      final app = await seeded();
      final day = gymDay(app);
      final (target, load) = weightedFirst(app, day);
      final name = '${target['name']}';
      await open(t, app, WorkoutSessionScreen(dateKey: day, type: 'gym'));

      final chip = kgChip(name);
      expect(chip, findsOneWidget);
      expect(find.descendant(of: chip, matching: find.text('추천 ${kgText(load.kg!)}kg')), findsOneWidget);
      expect(find.text(load.hint), findsNothing, reason: '힌트는 줄마다 되풀이하지 않습니다 — 스테퍼 시트에만');

      await t.tap(chip);
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('kg-value')), findsOneWidget);
      expect(find.text(load.hint), findsOneWidget, reason: '"안 되면 … 줄여 보세요" 는 시트에');
      expect(find.text('${kgText(load.kg!)} kg'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('kg-plus')));
      await t.pump();
      final up = load.kg! + load.step;
      expect(find.text('${kgText(up)} kg'), findsOneWidget, reason: '+ 는 기구 단위(${load.step})만큼');
      await t.tap(find.byKey(const ValueKey('kg-minus')));
      await t.pump();
      expect(find.text('${kgText(load.kg!)} kg'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('kg-plus')));
      await t.pump();
      await t.tap(find.byKey(const ValueKey('kg-ok')));
      await t.pumpAndSettle();
      /* 정한 뒤에는 '추천' 이 떨어지고 숫자만 */
      expect(find.descendant(of: kgChip(name), matching: find.text('${kgText(up)}kg')), findsOneWidget);
      expect(find.descendant(of: kgChip(name), matching: find.textContaining('추천')), findsNothing);

      await t.tap(setButton(name));
      await t.pump();
      await finish(t);
      final log = logOf(app, day, 'gym');
      final xs = (log['exercises'] as List).cast<Map>();
      expect(xs, hasLength(1));
      expect(xs.single['name'], name);
      expect(xs.single['kg'], up);
      expect(xs.single['reps'], target['reps']);
      expect(xs.single['restSec'], isNotNull);
    });

    testWidgets('스테퍼에서 「맨몸」 을 고르면 kg 이 null 로 남는다', (t) async {
      final app = await seeded();
      final day = gymDay(app);
      final (target, _) = weightedFirst(app, day);
      final name = '${target['name']}';
      await open(t, app, WorkoutSessionScreen(dateKey: day, type: 'gym'));
      await t.tap(kgChip(name));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('kg-none')));
      await t.pump();
      expect(t.widget<Text>(find.byKey(const ValueKey('kg-value'))).data, '맨몸');
      await t.tap(find.byKey(const ValueKey('kg-ok')));
      await t.pumpAndSettle();
      expect(find.descendant(of: kgChip(name), matching: find.text('맨몸')), findsOneWidget);
      await t.tap(setButton(name));
      await t.pump();
      await finish(t);
      final xs = (logOf(app, day, 'gym')['exercises'] as List).cast<Map>();
      expect(xs.single.containsKey('kg'), isTrue);
      expect(xs.single['kg'], isNull);
    });

    testWidgets('지난 30일 기록이 있으면 그 무게 — 다 채웠으면 한 단위 위, 칩에 "추천" 이 없다', (t) async {
      final app = await seeded();
      final day = gymDay(app);
      final (target, load) = weightedFirst(app, day);
      final name = '${target['name']}';
      /* 열흘 전 헬스 기록 — 그 종목 3/3 세트 · 이 무게로 */
      final before = DateTime.parse('${day}T00:00:00').subtract(const Duration(days: 10));
      final beforeKey = '${before.year}-${before.month.toString().padLeft(2, '0')}-${before.day.toString().padLeft(2, '0')}';
      app.store.setScheduleLog(beforeKey, 'gym', {
        'kind': 'gym', 'minutes': 30, 'kcal': 100, 'sets': 3,
        'exercises': [{'name': name, 'sets': 3, 'of': 3, 'kg': load.kg}],
      });
      await open(t, app, WorkoutSessionScreen(dateKey: day, type: 'gym'));
      final up = load.kg! + load.step;
      expect(find.descendant(of: kgChip(name), matching: find.text('${kgText(up)}kg')), findsOneWidget);
      final hint = '지난번 ${kgText(load.kg!)}kg · 다 채워서 +${kgText(load.step)}kg';
      expect(find.text(hint), findsNothing, reason: '칩의 숫자로 충분합니다 — 힌트는 시트에');
      await t.tap(kgChip(name));
      await t.pumpAndSettle();
      expect(find.text(hint), findsOneWidget);
      expect(find.text('추천 ${kgText(up)}kg'), findsOneWidget, reason: '올린 값은 「추천」 — 「지난번 60kg」 은 거짓말');
    });

    testWidgets('글자 1.3배 — 스테퍼의 「117.5 kg」 이 두 줄로 접히지 않는다', (t) async {
      final app = await seeded();
      final day = gymDay(app);
      final (target, load) = weightedFirst(app, day);
      final name = '${target['name']}';
      /* 지난 기록 112.5 · 3/3 → 추천 = 112.5 + 단위. 머신이면 117.5 — 소수 있는 세 자리. */
      final before = DateTime.parse('${day}T00:00:00').subtract(const Duration(days: 3));
      final beforeKey = '${before.year}-${before.month.toString().padLeft(2, '0')}-${before.day.toString().padLeft(2, '0')}';
      app.store.setScheduleLog(beforeKey, 'gym', {
        'kind': 'gym', 'minutes': 30, 'kcal': 100, 'sets': 3,
        'exercises': [{'name': name, 'sets': 3, 'of': 3, 'kg': 112.5}],
      });
      t.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      await open(t, app, WorkoutSessionScreen(dateKey: day, type: 'gym'));
      await t.tap(kgChip(name));
      await t.pumpAndSettle();
      final value = find.byKey(const ValueKey('kg-value'));
      expect(t.widget<Text>(value).data, '${kgText(112.5 + load.step)} kg');
      final rp = t.renderObject<RenderParagraph>(value);
      expect(rp.didExceedMaxLines, isFalse);
      expect(rp.size.height, lessThan(60), reason: '한 줄(36px 글자)이어야 합니다 — 두 줄이면 90px 이 넘습니다');
      expect(t.getSize(find.byKey(const ValueKey('kg-minus'))).height, greaterThan(0));
      expect(t.takeException(), isNull);
    });

    testWidgets('종목 줄의 메모는 요령만 — 엔진 접두어 「대체: 원래 …」 는 헬스 화면에 안 나온다', (t) async {
      final app = await seeded();
      final day = gymDay(app);
      final plan = gymExercisesFor(app.state, day);
      final swapped = plan.firstWhere((m) => '${m['note']}'.startsWith(kSubstitutePrefix),
          orElse: () => fail('초보 프리셋이면 바뀐 종목이 있어야 합니다: $plan'));
      await open(t, app, WorkoutSessionScreen(dateKey: day, type: 'gym'));
      expect(find.textContaining(kSubstitutePrefix), findsNothing);
      expect(find.textContaining('원래 '), findsNothing);
      final tip = tailorNote(swapped, original: false);
      if (tip != null) {
        expect(find.descendant(of: exerciseRow('${swapped['name']}'), matching: find.textContaining(tip)), findsOneWidget);
      }
      expect(t.takeException(), isNull);
    });

    testWidgets('세트를 다 채워도 「+」 가 남아 계획보다 더 한 세트가 기록된다 — sets: 한 것, of: 계획', (t) async {
      final app = await seeded();
      final day = gymDay(app);
      final plan = gymExercisesFor(app.state, day);
      final first = '${plan.first['name']}';
      final sets = core.jsToNumber(plan.first['sets']).round();
      await open(t, app, WorkoutSessionScreen(dateKey: day, type: 'gym'));
      for (var i = 0; i < sets; i++) {
        await t.tap(setButton(first));
        await t.pump();
      }
      expect(find.descendant(of: exerciseRow(first), matching: find.text('완료')), findsOneWidget);
      expect(setButton(first), findsOneWidget, reason: '완료 뒤에도 「+」 는 남습니다');
      await t.tap(setButton(first));
      await t.pump();
      expect(find.descendant(of: exerciseRow(first), matching: find.text('${sets + 1}/$sets')), findsOneWidget);
      /* 「−」 로 도로 내려갑니다 */
      await t.tap(find.descendant(of: exerciseRow(first), matching: find.byTooltip('한 세트 빼기')));
      await t.pump();
      expect(find.descendant(of: exerciseRow(first), matching: find.text('${sets + 1}/$sets')), findsNothing);
      await t.tap(setButton(first));
      await t.pump();
      await finish(t);
      final log = logOf(app, day, 'gym');
      expect(log['sets'], sets + 1);
      final x = (log['exercises'] as List).cast<Map>().single;
      expect(x['sets'], sets + 1);
      expect(x['of'], sets);
    });

    testWidgets('「종목 추가」 — 부위 한 번, 종목 한 번이면 3세트 × 10-15 로 붙고 기록에도 남는다', (t) async {
      final app = await seeded();
      final day = gymDay(app);
      final plan = gymExercisesFor(app.state, day);
      final names = {for (final m in plan) '${m['name']}'};
      final total = plan.fold<int>(0, (a, e) => a + core.jsToNumber(e['sets']).round());
      final pick = exercisesFor('chest', equip: {'machine'}).firstWhere((e) => !names.contains(e.name));
      await open(t, app, WorkoutSessionScreen(dateKey: day, type: 'gym'));
      expect(exerciseRow(pick.name), findsNothing);

      await t.tap(find.byKey(const ValueKey('ex-add')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('pick-group-chest')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(ValueKey('pick-${pick.id}')));
      await t.pumpAndSettle();

      expect(exerciseRow(pick.name), findsOneWidget);
      expect(find.descendant(of: exerciseRow(pick.name), matching: find.textContaining('3세트 × 10-15')), findsOneWidget);
      expect(find.text('0/${total + 3} 세트'), findsOneWidget);
      expect(kgChip(pick.name), findsOneWidget, reason: '머신이니 추천 무게가 붙습니다');

      /* 같은 종목은 다시 못 고릅니다 — 목록에 있는 것은 고르기에서 빠집니다. */
      await t.tap(find.byKey(const ValueKey('ex-add')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('pick-group-chest')));
      await t.pumpAndSettle();
      expect(find.byKey(ValueKey('pick-${pick.id}')), findsNothing);
      await t.tap(find.byKey(const ValueKey('pick-back')));
      await t.pumpAndSettle();
      Navigator.of(t.element(find.byKey(const ValueKey('pick-search')))).pop();
      await t.pumpAndSettle();

      await t.tap(setButton(pick.name));
      await t.pump();
      await finish(t);
      final xs = (logOf(app, day, 'gym')['exercises'] as List).cast<Map>();
      expect(xs.single['name'], pick.name);
      expect(xs.single['of'], 3);
      expect(xs.single['reps'], '10-15');
      expect(xs.single['restSec'], 75);
    });

    testWidgets('줄을 왼쪽으로 밀면 빠지고, 「되돌리기」 로 제자리에 돌아온다', (t) async {
      final app = await seeded();
      final day = gymDay(app);
      final plan = gymExercisesFor(app.state, day);
      final first = '${plan.first['name']}';
      final total = plan.fold<int>(0, (a, e) => a + core.jsToNumber(e['sets']).round());
      final firstSets = core.jsToNumber(plan.first['sets']).round();
      await open(t, app, WorkoutSessionScreen(dateKey: day, type: 'gym'));

      await t.drag(exerciseRow(first), const Offset(-700, 0));
      await t.pumpAndSettle();
      expect(exerciseRow(first), findsNothing);
      expect(find.text('0/${total - firstSets} 세트'), findsOneWidget);
      expect(find.text('되돌리기'), findsOneWidget);

      await t.tap(find.text('되돌리기'));
      await t.pumpAndSettle();
      expect(exerciseRow(first), findsOneWidget);
      expect(find.text('0/$total 세트'), findsOneWidget);
      /* 제자리 — 첫 줄 */
      final rows = find.byWidgetPredicate(
          (w) => w.key is ValueKey<String> && (w.key as ValueKey<String>).value.startsWith('ex-'));
      expect(t.widget(rows.first).key, ValueKey('ex-${slugOf(first)}'));
    });

    testWidgets('빼고 나서 5초 안에 다른 루틴을 불러오면 「되돌리기」 는 닫힌다 — 옛 목록에 넣지 않는다', (t) async {
      final app = await seeded();
      final day = gymDay(app);
      final plan = gymExercisesFor(app.state, day);
      final first = '${plan.first['name']}';
      saveRoutine(app, name: '다른 것', label: '(다른)', exercises: const [
        {'name': '레그프레스', 'sets': 3, 'reps': '10-15', 'restSec': 75},
      ]);
      await open(t, app, WorkoutSessionScreen(dateKey: day, type: 'gym'));
      await t.drag(exerciseRow(first), const Offset(-700, 0));
      await t.pumpAndSettle();
      expect(find.text('되돌리기'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('routine-load')));
      await t.pumpAndSettle();
      await t.tap(find.text('다른 것'));
      await t.pumpAndSettle();
      expect(find.text('되돌리기'), findsNothing, reason: '목록이 바뀌면 되돌릴 자리가 없습니다');
      expect(exerciseRow('레그프레스'), findsOneWidget);
      expect(exerciseRow(first), first == '레그프레스' ? findsOneWidget : findsNothing);
      expect(find.text('0/3 세트'), findsOneWidget);
    });

    testWidgets('종료 시트의 「내 루틴으로 저장」 — 저장되고, 같은 라벨의 날에 자동으로 쓰이며, 되돌리고 다시 불러올 수 있다', (t) async {
      final app = await seeded();
      final day = gymDay(app);
      final session = planSessionFor(app.state, day)!;
      final label = '${session['label']}';
      final plan = gymExercisesFor(app.state, day);
      final names = {for (final m in plan) '${m['name']}'};
      final pick = exercisesFor('back', equip: {'machine'}).firstWhere((e) => !names.contains(e.name));

      await open(t, app, WorkoutSessionScreen(dateKey: day, type: 'gym'));
      expect(find.byKey(const ValueKey('routine-load')), findsNothing, reason: '루틴이 없으면 칩도 없습니다');
      /* 종목 하나 더 넣어 플랜과 다르게 */
      await t.tap(find.byKey(const ValueKey('ex-add')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('pick-group-back')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(ValueKey('pick-${pick.id}')));
      await t.pumpAndSettle();
      await t.tap(setButton('${plan.first['name']}'));
      await t.pump();

      await t.tap(find.text('종료'));
      await t.pumpAndSettle();
      await t.enterText(find.widgetWithText(TextField, '운동 시간'), '30');
      await t.pump();
      expect(find.byKey(const ValueKey('routine-name')), findsNothing, reason: '스위치를 켜야 이름칸');
      await t.tap(find.byKey(const ValueKey('routine-save')));
      await t.pumpAndSettle();
      expect(t.widget<TextField>(find.byKey(const ValueKey('routine-name'))).controller!.text, '$label 내 루틴');
      await t.enterText(find.byKey(const ValueKey('routine-name')), '$label 내 버전');
      await t.pump();
      await t.tap(find.text('저장'));
      await t.pumpAndSettle();
      expect(find.textContaining('내 루틴 「$label 내 버전」'), findsOneWidget);
      await t.tap(find.text('닫기'));
      await t.pumpAndSettle();

      final saved = routinesOf(app);
      expect(saved, hasLength(1));
      expect(saved.single['name'], '$label 내 버전');
      expect(saved.single['label'], label);
      final xs = routineExercises(saved.single);
      expect(xs, hasLength(plan.length + 1), reason: '한 세트도 안 한 종목도 구성입니다');
      expect(xs.last['name'], pick.name);
      expect(xs.last['sets'], 3);
      expect(xs.last['kg'], isA<num>(), reason: '머신의 추천 무게가 같이 남습니다');
      expect(routineForLabel(app, label)!['id'], saved.single['id']);

      /* 같은 날을 다시 열면 — 묻지 않고 그 루틴 */
      await open(t, app, WorkoutSessionScreen(dateKey: day, type: 'gym'));
      expect(find.byKey(const ValueKey('routine-current')), findsOneWidget);
      expect(find.text('내 루틴: $label 내 버전'), findsOneWidget);
      expect(exerciseRow(pick.name), findsOneWidget);

      /* 「플랜 종목으로」 → 플랜 목록, 「루틴 불러오기」 → 다시 루틴 */
      await t.tap(find.byKey(const ValueKey('routine-reset')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('routine-current')), findsNothing);
      expect(exerciseRow(pick.name), findsNothing);
      expect(find.byKey(const ValueKey('routine-load')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('routine-load')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(ValueKey('routine-${saved.single['id']}')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('routine-current')), findsOneWidget);
      expect(exerciseRow(pick.name), findsOneWidget);

      /* 길게 누르면 지웁니다 — 지금 쓰던 루틴이면 머리글의 이름도 내려갑니다(종목은 그대로). */
      await t.tap(find.byKey(const ValueKey('routine-load')));
      await t.pumpAndSettle();
      await t.longPress(find.byKey(ValueKey('routine-${saved.single['id']}')));
      await t.pumpAndSettle();
      await t.tap(find.text('지우기'));
      await t.pumpAndSettle();
      expect(routinesOf(app), isEmpty);
      expect(find.text('저장한 루틴이 없습니다'), findsOneWidget);
      await t.tapAt(const Offset(500, 40));                              // 시트 밖
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('routine-current')), findsNothing, reason: '지운 이름을 계속 쓰면 안 됩니다');
      expect(find.byKey(const ValueKey('routine-reset')), findsNothing);
      expect(exerciseRow(pick.name), findsOneWidget, reason: '종목은 그대로');
      /* 종료 시트의 루틴 이름도 기본으로 — 지운 이름으로 되살리지 않습니다. */
      await t.tap(find.text('종료'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('routine-save')));
      await t.pumpAndSettle();
      expect(t.widget<TextField>(find.byKey(const ValueKey('routine-name'))).controller!.text, '$label 내 루틴');
    });

    testWidgets('다른 라벨의 날에는 자동으로 쓰지 않는다 — 칩으로 불러올 수만 있다', (t) async {
      final app = await seeded();
      final day = gymDay(app);
      final label = '${planSessionFor(app.state, day)!['label']}';
      saveRoutine(app, name: '다른 날 것', label: '$label (다른)', exercises: [
        {'name': '레그프레스', 'sets': 3, 'reps': '10-15', 'restSec': 75},
      ]);
      await open(t, app, WorkoutSessionScreen(dateKey: day, type: 'gym'));
      expect(find.byKey(const ValueKey('routine-current')), findsNothing);
      expect(find.byKey(const ValueKey('routine-load')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('routine-load')));
      await t.pumpAndSettle();
      await t.tap(find.text('다른 날 것'));
      await t.pumpAndSettle();
      expect(find.text('내 루틴: 다른 날 것'), findsOneWidget);
      expect(exerciseRow('레그프레스'), findsOneWidget);
      expect(find.text('0/3 세트'), findsOneWidget);
    });

    testWidgets('360px 폭에서도 줄이 넘치지 않는다 — 무게 칩 · 완료 · 초과 세트까지', (t) async {
      final app = await seeded();
      final day = gymDay(app);
      final plan = gymExercisesFor(app.state, day);
      final first = '${plan.first['name']}';
      final sets = core.jsToNumber(plan.first['sets']).round();
      saveRoutine(app, name: '아주아주 긴 이름의 내 루틴 이름입니다', label: '${planSessionFor(app.state, day)!['label']}',
          exercises: [for (final m in plan) {'name': m['name'], 'sets': m['sets'], 'reps': m['reps'], 'restSec': m['restSec']}]);
      t.view.physicalSize = const Size(360, 800);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(host(app, WorkoutSessionScreen(dateKey: day, type: 'gym')));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      for (var i = 0; i <= sets; i++) {
        await t.tap(setButton(first), warnIfMissed: false);
        await t.pump();
        expect(t.takeException(), isNull, reason: '${i + 1}번째 세트에서 넘쳤습니다');
      }
      expect(find.descendant(of: exerciseRow(first), matching: find.text('${sets + 1}/$sets')), findsOneWidget);
    });
  });

  group('운동 알림 — 헬스를 계획했는데 안 간 날 저녁 8시 반', () {
    final schedule = <String, Object?>{
      '2026-09-24': {'plan': ['gym'], 'done': {}},                       // 오늘 — 안 감
      '2026-09-25': {'plan': ['gym'], 'done': {'gym': '2026-09-25T10:00:00Z'}},   // 이미 감
      '2026-09-26': {'plan': ['cardio'], 'done': {}},                    // 헬스 아님
      '2026-09-30': {'plan': ['gym', 'cardio'], 'done': {'cardio': '2026-09-30T08:00:00Z'}},
      '2026-10-20': {'plan': ['gym'], 'done': {}},                       // 14일 밖
    };

    test('계획했고 아직 체크 없는 헬스 날만, 하루 하나, 20:30', () {
      final r = planWorkoutReminders(now: DateTime(2026, 9, 24, 9, 0), schedule: schedule);
      expect([for (final x in r) x.dateKey], ['2026-09-24', '2026-09-30']);
      expect(r.first.at, DateTime(2026, 9, 24, 20, 30));
      expect(r.last.at, DateTime(2026, 9, 30, 20, 30));
      expect(r.first.id, kWorkoutIdBase);
      expect(r.last.id, kWorkoutIdBase + 6);
      expect(r.first.title, '오늘 헬스를 못 갔나요?');
      expect(r.first.body, contains('15분 맨몸 운동'));
    });

    test('오늘 8시 반이 지났으면 오늘 것은 없다', () {
      final r = planWorkoutReminders(now: DateTime(2026, 9, 24, 20, 30), schedule: schedule);
      expect([for (final x in r) x.dateKey], ['2026-09-30'], reason: '20:30 정각은 이미 지난 것으로 봅니다');
    });

    test('일정이 비어 있으면 아무것도 안 건다', () {
      expect(planWorkoutReminders(now: DateTime(2026, 9, 24, 9, 0), schedule: const {}), isEmpty);
    });

    test('번호는 2000 부터 14개 안 — 간식(7) · 끼니(100~141) · 독촉(1000~1999)과 안 겹친다', () {
      expect(kWorkoutIdBase, 2000);
      expect(kWorkoutIdBase + kWorkoutDays, lessThanOrEqualTo(2014));
      expect(kWorkoutIdBase, greaterThanOrEqualTo(2000));
      expect(kMealIdBase + kMealDays * 3, lessThan(1000));
    });

    test('payload 는 셸이 되읽을 수 있다', () {
      final p = workoutPayload('bodyweight', '2026-09-24');
      expect(p, 'workout:bodyweight:2026-09-24');
      expect(parseWorkoutPayload(p), (type: 'bodyweight', dateKey: '2026-09-24'));
      expect(parseWorkoutPayload('workout:gym:2026-09-24'), (type: 'gym', dateKey: '2026-09-24'));
      expect(parseWorkoutPayload('food:아침'), isNull);
      expect(parseWorkoutPayload('workout:swim:2026-09-24'), isNull);
      expect(parseWorkoutPayload('workout:gym:tomorrow'), isNull);
    });
  });

}

/// 종목 줄과 그 줄의 「세트」 단추. 화면이 종목 이름의 slug 로 키를 답니다 —
/// 글자('세트')는 줄마다 같아서 글자로는 어느 줄인지 못 고릅니다.
Finder exerciseRow(String name) => find.byKey(ValueKey('ex-${slugOf(name)}'));
Finder setButton(String name) => find.byKey(ValueKey('set-${slugOf(name)}'));
Finder kgChip(String name) => find.byKey(ValueKey('kg-${slugOf(name)}'));

/// 아무 종목의 「세트」 단추 — 어떤 종목이 나왔는지는 상관없을 때.
Finder anySetButton() => find.byWidgetPredicate(
    (w) => w.key is ValueKey<String> && (w.key as ValueKey<String>).value.startsWith('set-'));

/// 화면을 push 로 여는 자리. 저장하면 여기로 돌아옵니다.
class _Launch extends StatelessWidget {
  const _Launch({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: FilledButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => child)),
            child: const Text('열기'),
          ),
        ),
      );
}
