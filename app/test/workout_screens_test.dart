/* =============================================================================
 * workout_screens_test.dart — 헬스장에서 쓰는 화면들이 **실제로 기록을 남기는가**
 *
 * 화면이 서는지(회색 네모)만이 아니라, 세트 버튼이 올라가고 「저장」 이
 * 코어의 일정 기록(setScheduleLog)에 분 · kcal 을 남기는지까지 봅니다.
 * 시계는 [WorkoutSessionScreen.clock] 과 store.now 로 세워 둡니다 — 시험이
 * 진짜 40분을 기다릴 수는 없습니다.
 * ========================================================================== */
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mybody/src/api.dart';
import 'package:mybody/src/app_state.dart';
import 'package:mybody/src/nudge.dart';
import 'package:mybody/src/scope.dart';
import 'package:mybody/src/screens/gym_settings.dart';
import 'package:mybody/src/screens/workout_session.dart';
import 'package:mybody/src/theme.dart';
import 'package:mybody/src/ui/fmt.dart';
import 'package:mybody/src/ui/widgets.dart';
import 'package:mybody/src/workout/exercises.dart';
import 'package:mybody/src/workout/kcal.dart';
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
      final sets = core.jsToNumber(tailored.first['sets']).round();
      expect(find.text('세트 완료 (0/$sets)'), findsWidgets);
      expect(find.text('건너뛰기'), findsNothing);

      await t.tap(find.text('세트 완료 (0/$sets)').first);
      await t.pump();
      expect(find.text('세트 완료 (1/$sets)'), findsOneWidget);
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
      expect(find.text('세트 완료 (0/$sets)'), findsWidgets);
      expect(find.text('세트 완료 (1/$sets)'), findsNothing);
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
      await t.tap(find.textContaining('세트 완료 (0/').first);
      await t.pump();

      await t.tap(find.text('종료'));
      await t.pumpAndSettle();
      final weight = latestWeightKg(app)!;
      final expectKcal =
          workoutKcal(weightKg: weight, duration: const Duration(minutes: 40), kind: 'gym').round();
      expect(find.descendant(of: find.byType(Stat), matching: find.text('40')), findsOneWidget);
      expect(find.descendant(of: find.byType(Stat), matching: find.text(n0(expectKcal))), findsOneWidget);

      await t.tap(find.text('저장'));
      await t.pumpAndSettle();

      final log = logOf(app, day, 'gym');
      expect(log['kind'], 'gym');
      expect(log['minutes'], 40);
      expect(core.jsToNumber(log['kcal']), greaterThan(0));
      expect(log['kcal'], expectKcal);
      expect(log['sets'], 1);
      expect((log['exercises'] as List), hasLength(1));
      expect(core.jsTruthy((app.store.scheduleDay(day)['done'] as Map)['gym']), isTrue, reason: '기록하면 그 날이 체크됩니다');
      expect(find.byType(WorkoutSessionScreen), findsNothing, reason: '저장하면 닫힙니다');
      expect(find.textContaining('헬스 40분'), findsOneWidget, reason: '수고했다는 토스트');
    });

    testWidgets('플랜이 없어도 전신 기본 종목이 나온다', (t) async {
      final app = await seeded(withPlan: false);
      await open(t, app, WorkoutSessionScreen(dateKey: _todayKey, type: 'gym'));
      expect(find.text('오늘 플랜에 없는 날 — 전신 기본 종목'), findsOneWidget);
      expect(find.textContaining('세트 완료 (0/'), findsWidgets);
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
      expect(log['km'], 5.0);
      expect(log['kcal'], expectKcal.round());
      expect(core.jsTruthy((app.store.scheduleDay(_todayKey)['done'] as Map)['cardio']), isTrue);
      expect(find.byType(WorkoutSessionScreen), findsNothing);
      expect(find.textContaining('달리기 30분'), findsOneWidget);
    });

    testWidgets('시계로 잰 시간이 종료 시트에 미리 들어간다', (t) async {
      final app = await seeded();
      await open(t, app, WorkoutSessionScreen(dateKey: _todayKey, type: 'cardio'));
      await t.tap(find.text('시작'));
      await t.pump();
      now = now.add(const Duration(minutes: 25, seconds: 40));
      await t.pump(const Duration(seconds: 1));
      await t.tap(find.text('종료'));
      await t.pumpAndSettle();
      final field = t.widget<TextField>(find.widgetWithText(TextField, '시간'));
      expect(field.controller!.text, '26', reason: '25분 40초는 26분으로 반올림');
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

  group('설정 — 운동 장소와 기구', () {
    testWidgets('기구 칩을 끄고 켜면 settings[gym] 에 남는다', (t) async {
      final app = await seeded(withPlan: false);
      t.view.physicalSize = const Size(1000, 3000);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(host(app, Scaffold(body: ListView(children: const [GymSettingsCard()]))));
      await t.pump();
      expect(find.text('있는 기구에 맞춰 종목을 바꿉니다. 익숙한 종목은 먼저 넣습니다.'), findsOneWidget);

      GymPrefs prefs() => GymPrefs.fromSettings((app.state['settings'] as Map?)?.cast<String, Object?>());
      expect(prefs().equipment, contains('barbell'), reason: '헬스장 기본은 바벨이 있습니다');

      await t.tap(find.widgetWithText(FilterChip, kEquipLabel['barbell']!));
      await t.pump();
      expect(prefs().equipment, isNot(contains('barbell')));
      expect(((app.state['settings'] as Map)['gym'] as Map)['equipment'], isNot(contains('barbell')));

      await t.tap(find.widgetWithText(FilterChip, kEquipLabel['barbell']!));
      await t.pump();
      expect(prefs().equipment, contains('barbell'));
    });

    testWidgets('집으로 바꾸면 place 가 home 이 되고 머신 대수는 사라진다', (t) async {
      final app = await seeded(withPlan: false);
      t.view.physicalSize = const Size(1000, 3000);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(host(app, Scaffold(body: ListView(children: const [GymSettingsCard()]))));
      await t.pump();
      expect(find.text('머신 대수'), findsOneWidget);
      await t.tap(find.text('집'));
      await t.pump();
      expect(((app.state['settings'] as Map)['gym'] as Map)['place'], 'home');
      expect(find.text('머신 대수'), findsNothing);
    });

    testWidgets('머신 대수 눈금 — 제한 없음에서 내려가고, 눈금 사이 값은 아래 눈금', (t) async {
      final app = await seeded(withPlan: false);
      t.view.physicalSize = const Size(1000, 3000);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(host(app, Scaffold(body: ListView(children: const [GymSettingsCard()]))));
      await t.pump();
      expect(find.text('제한 없음'), findsOneWidget);
      await t.tap(find.byTooltip('적게'));
      await t.pump();
      expect(((app.state['settings'] as Map)['gym'] as Map)['machineCount'], 6);
      expect(find.text('6대'), findsOneWidget);
      expect(machineStopIndex(3), 1, reason: '3대는 2대 눈금');
      expect(machineStopIndex(null), kMachineStops.length - 1);
    });

    testWidgets('익숙한 종목 — 시트에서 고르면 id 가 남고 칩에 이름이 뜬다', (t) async {
      final app = await seeded(withPlan: false);
      t.view.physicalSize = const Size(1000, 3000);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(host(app, Scaffold(body: ListView(children: const [GymSettingsCard()]))));
      await t.pump();
      await t.tap(find.text('종목 고르기'));
      await t.pumpAndSettle();
      final first = kExerciseLibrary.first;
      await t.enterText(find.byType(TextField).last, first.name);
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(CheckboxListTile, first.name));
      await t.pumpAndSettle();
      expect(((app.state['settings'] as Map)['gym'] as Map)['familiar'], [first.id]);
      await t.tap(find.text('닫기'));
      await t.pumpAndSettle();
      expect(find.widgetWithText(InputChip, first.name), findsOneWidget);
    });
  });
}

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
