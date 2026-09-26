/* =============================================================================
 * sports_test.dart — 유산소 화면이 스포츠도 받는가 (피드백 41 — 필라테스 · 탁구 …)
 *
 * 종목 표(kSports)의 MET 과 kcal, 종료 시트의 칩 줄(걷기 · 달리기 · 자전거 + 최근
 * 종목)과 「다른 종목」 시트(칩 → 타일, 두 번 터치), 거리 칸이 거리 있는 종목에만
 * 보이는 것, 기록의 kind 가 id 로 남는 것, 홈 브리핑의 완료 줄이 종목 이름을 쓰는 것,
 * 표에 없는 kind(옛 판 · 다음 판의 기록)가 일반 유산소로 읽히는 것을 봅니다.
 * ========================================================================== */
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mybody/src/api.dart';
import 'package:mybody/src/app_state.dart';
import 'package:mybody/src/briefing.dart';
import 'package:mybody/src/scope.dart';
import 'package:mybody/src/screens/workout_session.dart';
import 'package:mybody/src/screens/workout_tutorial.dart';
import 'package:mybody/src/theme.dart';
import 'package:mybody/src/ui/fmt.dart';
import 'package:mybody/src/ui/widgets.dart';
import 'package:mybody/src/workout/kcal.dart';
import 'package:mybody_core/mybody_core.dart' as core;
import 'package:shared_preferences/shared_preferences.dart';

const _scan = {
  'id': 's1', 'weightKg': 70.0, 'smmKg': 31.0, 'bfmKg': 14.0,
  'pbfPct': 20.0, 'ffmKg': 56.0, 'bmi': 22.9, 'bmrKcal': 1580,
  'measuredAt': '2026-03-01T00:00:00.000Z',
};
const _profile = {
  'sex': 'female', 'age': 30, 'heightCm': 175, 'activityLevel': 'moderate',
  'trainingAge': 'novice', 'daysPerWeek': 3, 'mealsPerDay': 3,
};

/// 시험의 오늘 — 2026-09-27 일요일 저녁.
final _today = DateTime(2026, 9, 27, 18, 0);
const _todayKey = '2026-09-27';

/// 오늘에서 [n]일 전의 날짜 열쇠.
String _daysAgo(int n) {
  final d = DateTime(_today.year, _today.month, _today.day - n);
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('종목 표', () {
    test('맨 앞 넷은 처음부터 있던 id · 이름 그대로 — 옛 기록이 읽힌다', () {
      expect(kSports.take(4).map((s) => s.id), ['walk', 'run', 'bike', 'cardio']);
      expect(kSports.take(4).map((s) => s.label), ['걷기', '달리기', '자전거', '유산소']);
      expect(kQuickSports, ['walk', 'run', 'bike']);
    });

    test('id 는 겹치지 않고, 묶음은 모두 시트의 묶음 중 하나', () {
      final ids = kSports.map((s) => s.id).toList();
      expect(ids.toSet(), hasLength(ids.length));
      final groups = {for (final (g, _) in kSportGroups) g};
      for (final s in kSports) {
        expect(groups, contains(s.group), reason: '${s.id} 의 묶음 ${s.group}');
        expect(s.met, inInclusiveRange(2.0, 12.5), reason: '${s.id} 의 MET');
      }
      for (final id in ['pilates', 'yoga', 'table-tennis', 'badminton', 'tennis', 'soccer',
          'futsal', 'basketball', 'golf', 'swim', 'hiking', 'climbing', 'boxing', 'ski']) {
        expect(sportOf(id), isNotNull, reason: id);
      }
    });

    test('거리는 걷기 · 달리기 · 자전거 · 수영 · 등산만', () {
      expect([for (final s in kSports) if (s.hasDistance) s.id],
          unorderedEquals(['walk', 'run', 'bike', 'swim', 'hiking']));
    });

    test('MET — Compendium 값 그대로', () {
      expect(workoutMet(kind: 'pilates'), 3.0);
      expect(workoutMet(kind: 'yoga'), 2.5);
      expect(workoutMet(kind: 'table-tennis'), 4.0);
      expect(workoutMet(kind: 'badminton'), 5.5);
      expect(workoutMet(kind: 'tennis'), 7.3);
      expect(workoutMet(kind: 'futsal'), 8.0);
      expect(workoutMet(kind: 'swim'), 5.8);
      expect(workoutMet(kind: 'jump-rope'), 11.8);
      expect(workoutMet(kind: 'martial-arts'), 7.0,
          reason: '15430(10.3)은 쉬지 않고 하는 속도 — 성인 취미 수련은 15425(5.3)와 그 사이');
      expect(workoutMet(kind: 'jiu-jitsu'), workoutMet(kind: 'martial-arts'), reason: '같은 줄(15430)의 두 종목');
      expect(workoutMet(kind: 'golf'), 3.5, reason: '카트(15290) — 한국 골프장은 카트가 기본');
      expect(workoutMet(kind: 'ski'), lessThan(5.3), reason: '19160(5.3)은 타는 시간만 — 시계는 리프트까지 잽니다');
      expect(workoutMet(kind: 'snowboard'), workoutMet(kind: 'ski'));
    });

    test('kcal — 필라테스 70kg · 45분 = 3.0 × 3.5 × 70 / 200 × 45', () {
      expect(workoutKcal(weightKg: 70, duration: const Duration(minutes: 45), kind: 'pilates'),
          closeTo(3.0 * 3.5 * 70 / 200 * 45, 0.001));
    });

    test('속도 보정은 걷기 · 달리기 · 자전거만 — 수영 · 등산은 거리를 줘도 표의 값', () {
      const hour = Duration(hours: 1);
      expect(workoutKcal(weightKg: 70, duration: hour, kind: 'swim', km: 3),
          closeTo(workoutKcal(weightKg: 70, duration: hour, kind: 'swim'), 0.001));
      expect(workoutKcal(weightKg: 70, duration: hour, kind: 'hiking', km: 8),
          closeTo(6.0 * 3.5 * 70 / 200 * 60, 0.001));
      expect(workoutMet(kind: 'run', kmh: 14.5), closeTo(12.8, 0.001), reason: '달리기는 그대로');
    });

    test('모르는 kind — 일반 유산소 6.0 · 이름은 「유산소」', () {
      expect(sportOf('curling-2099'), isNull);
      expect(workoutMet(kind: 'curling-2099'), 6.0);
      expect(sportLabel('curling-2099'), '유산소');
      expect(sportLabel(null), '유산소');
      expect(cardioKindLabel('curling-2099'), '유산소');
      expect(cardioKindLabel('pilates'), '필라테스');
      expect(cardioKindLabel('gym'), '헬스', reason: '헬스 · 맨몸 이름은 그대로');
    });

    test('최근 종목 — 30일 안, 최근 것부터, 겹치지 않게, 표에 없는 것은 빼고', () {
      Map<String, Object?> day(String kind) => {
            'plan': ['cardio'],
            'done': {'cardio': 'x'},
            'log': {'cardio': {'kind': kind, 'minutes': 30}},
          };
      final schedule = <String, Object?>{
        _daysAgo(0): day('pilates'),
        _daysAgo(1): day('walk'),
        _daysAgo(3): day('pilates'),
        _daysAgo(5): day('zzz'),
        _daysAgo(10): day('table-tennis'),
        _daysAgo(29): day('yoga'),
        _daysAgo(30): day('tennis'),
        _daysAgo(2): {'plan': ['gym'], 'done': {}, 'log': {'gym': {'kind': 'gym'}}},
      };
      expect(recentSportIds(schedule, _todayKey), ['pilates', 'walk', 'table-tennis', 'yoga']);
      expect(recentSportIds(schedule, _todayKey, days: 2), ['pilates', 'walk']);
      expect(recentSportIds(const {}, _todayKey), isEmpty);
      expect(recentSportIds(schedule, 'nope'), isEmpty);
    });

    test('기본 종목 — 두 번 이상 한 것 중 가장 최근, 기록하려는 그 날은 빼고, 없으면 걷기', () {
      Map<String, Object?> day(String kind) => {'log': {'cardio': {'kind': kind, 'minutes': 30}}};
      /* 오늘 자전거로 출근 · 어제 테니스 한 번 · 필라테스는 두 번. */
      final schedule = <String, Object?>{
        _daysAgo(0): day('bike'),
        _daysAgo(1): day('tennis'),
        _daysAgo(3): day('pilates'),
        _daysAgo(8): day('pilates'),
      };
      expect(defaultSportId(schedule, _todayKey, skip: _todayKey), 'pilates');
      expect(defaultSportId({_daysAgo(1): day('tennis')}, _todayKey, skip: _todayKey), 'walk',
          reason: '한 번 해 본 종목은 칩으로만 — 걷기가 「저장」 한 번에 테니스로 남으면 안 됩니다');
      expect(defaultSportId({_daysAgo(0): day('bike'), _daysAgo(2): day('bike')}, _todayKey,
              skip: _todayKey),
          'walk', reason: '오늘 기록은 셈에서 빠집니다 — 두 번째 세션의 기본값이 되면 안 됩니다');
      expect(defaultSportId(const {}, _todayKey), 'walk');
    });

    test('수영만 거리를 m 로 받는다', () {
      expect([for (final s in kSports) if (s.meters) s.id], ['swim']);
    });
  });

  /* --- 종료 시트 -------------------------------------------------------------- */

  group('종료 시트', () {
    DateTime now = _today;
    setUp(() {
      now = _today;
      WorkoutSessionScreen.clock = () => now;
    });
    tearDown(() => WorkoutSessionScreen.clock = DateTime.now);

    Future<AppState> seeded() async {
      SharedPreferences.setMockInitialValues({});
      final app = await AppState.boot();
      app.store.now = () => now;
      app.store.set({
        'profile': _profile,
        'onboarded': true,
        'settings': {kGymTutorialSeenKey: true, kGymSwipeHintSeenKey: true},
      });
      app.store.addScan({..._scan});
      return app;
    }

    Api api() {
      final a = Api(baseUrl: '', client: MockClient((_) async => http.Response('{"ok":false}', 404)));
      a.setToken('tok');
      return a;
    }

    Future<void> open(WidgetTester t, AppState app, {Size size = const Size(1000, 4000)}) async {
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(Scope(
        state: app,
        api: api(),
        onServerChange: (_) async {},
        child: MaterialApp(
          theme: mbLight(),
          home: Builder(
            builder: (ctx) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => Navigator.of(ctx).push(MaterialPageRoute(
                      builder: (_) => const WorkoutSessionScreen(dateKey: _todayKey, type: 'cardio'))),
                  child: const Text('열기'),
                ),
              ),
            ),
          ),
        ),
      ));
      await t.tap(find.text('열기'));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    }

    Map<String, Object?> cardioLog(AppState app) =>
        ((app.store.scheduleDay(_todayKey)['log'] as Map)['cardio'] as Map).cast<String, Object?>();

    bool chipSelected(WidgetTester t, String id) =>
        t.widget<ChoiceChip>(find.byKey(ValueKey('sport-chip-$id'))).selected;

    Finder kmField() => find.widgetWithText(TextField, '거리');

    testWidgets('화면 이름은 「유산소 · 스포츠」', (t) async {
      final app = await seeded();
      await open(t, app);
      expect(find.text('유산소 · 스포츠'), findsOneWidget);
    });

    testWidgets('「다른 종목」 → 필라테스: 두 번 터치로 고르고, kind 는 id 로 · 축하는 이름으로', (t) async {
      final app = await seeded();
      await open(t, app);
      await t.tap(find.text('시간을 직접 넣기'));
      await t.pumpAndSettle();
      expect(chipSelected(t, 'walk'), isTrue, reason: '기록이 없으면 걷기');
      expect(find.byKey(const ValueKey('sport-chip-pilates')), findsNothing);

      await t.tap(find.text('다른 종목'));                       // 1
      await t.pumpAndSettle();
      for (final (_, name) in kSportGroups.where((g) => kSports.any((s) => s.group == g.$1))) {
        expect(find.descendant(of: find.byKey(const ValueKey('sport-grid')), matching: find.text(name)),
            findsWidgets, reason: '묶음 $name');   // 「유산소」 는 묶음 이름이자 종목 이름
      }
      await t.tap(find.byKey(const ValueKey('sport-pilates')));   // 2
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('sport-grid')), findsNothing, reason: '고르면 닫힙니다');
      expect(chipSelected(t, 'pilates'), isTrue, reason: '고른 종목이 칩 줄에 선택된 채로');
      expect(chipSelected(t, 'walk'), isFalse);
      expect(kmField(), findsNothing, reason: '필라테스에 km 칸은 없습니다');

      await t.enterText(find.widgetWithText(TextField, '시간'), '45');
      await t.pump();
      final weight = latestWeightKg(app)!;
      final expectKcal = workoutKcal(weightKg: weight, duration: const Duration(minutes: 45), kind: 'pilates');
      expect(find.descendant(of: find.byType(Stat), matching: find.text(n0(expectKcal))), findsOneWidget);

      await t.tap(find.text('저장'));
      await t.pumpAndSettle();
      final log = cardioLog(app);
      expect(log['kind'], 'pilates');
      expect(log['minutes'], 45);
      expect(log['km'], isNull);
      expect(log['kcal'], expectKcal.round());
      expect(core.jsTruthy((app.store.scheduleDay(_todayKey)['done'] as Map)['cardio']), isTrue);
      expect(find.textContaining('필라테스 45분'), findsOneWidget);
      await t.tap(find.text('닫기'));
      await t.pumpAndSettle();
    });

    testWidgets('시계로 잰 필라테스 — 축하는 「필라테스 45:00」', (t) async {
      final app = await seeded();
      await open(t, app);
      await t.tap(find.text('시작'));
      await t.pump();
      now = now.add(const Duration(minutes: 45));
      await t.pump(const Duration(seconds: 1));
      await t.tap(find.text('종료'));
      await t.pumpAndSettle();
      await t.tap(find.text('다른 종목'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('sport-pilates')));
      await t.pumpAndSettle();
      await t.tap(find.text('저장'));
      await t.pumpAndSettle();
      expect(cardioLog(app)['kind'], 'pilates');
      expect(cardioLog(app)['seconds'], 45 * 60);
      expect(find.textContaining('필라테스 45:00'), findsOneWidget);
      await t.tap(find.text('닫기'));
      await t.pumpAndSettle();
    });

    testWidgets('거리 칸 — 걷기 · 수영에는 있고 탁구에는 없다, 숨은 km 는 기록되지 않는다', (t) async {
      final app = await seeded();
      await open(t, app);
      await t.tap(find.text('시간을 직접 넣기'));
      await t.pumpAndSettle();
      expect(kmField(), findsOneWidget, reason: '걷기');
      await t.enterText(find.widgetWithText(TextField, '시간'), '60');
      await t.enterText(kmField(), '3');
      await t.pump();

      await t.tap(find.text('다른 종목'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('sport-swim')));
      await t.pumpAndSettle();
      expect(kmField(), findsOneWidget, reason: '수영은 거리가 있습니다');

      await t.tap(find.text('다른 종목'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('sport-table-tennis')));
      await t.pumpAndSettle();
      expect(kmField(), findsNothing, reason: '탁구는 거리가 없습니다');
      expect(find.byKey(const ValueKey('sport-chip-table-tennis')), findsOneWidget);
      /* 분 칸이 마지막 칸 — 「다음」 이 아니라 완료. */
      final minutes = t.widget<TextField>(find.widgetWithText(TextField, '시간'));
      expect(minutes.textInputAction, TextInputAction.done);
      expect(minutes.onEditingComplete, isNull);

      final weight = latestWeightKg(app)!;
      final expectKcal = workoutKcal(weightKg: weight, duration: const Duration(minutes: 60), kind: 'table-tennis');
      expect(find.descendant(of: find.byType(Stat), matching: find.text(n0(expectKcal))), findsOneWidget);

      await t.tap(find.text('저장'));
      await t.pumpAndSettle();
      final log = cardioLog(app);
      expect(log['kind'], 'table-tennis');
      expect(log['km'], isNull, reason: '숨은 칸의 3km 는 탁구 기록이 아닙니다');
      expect(log['kcal'], expectKcal.round());
      expect(find.textContaining('탁구 60분'), findsOneWidget);
      expect(find.textContaining('km'), findsNothing);
      await t.tap(find.text('닫기'));
      await t.pumpAndSettle();
    });

    testWidgets('최근 종목 — 30일 안의 스포츠가 칩으로 올라오고, 두 번 이상 한 것 중 가장 최근 것이 기본 선택',
        (t) async {
      final app = await seeded();
      app.store.setScheduleLog(_daysAgo(2), 'cardio', {'kind': 'pilates', 'minutes': 50});
      app.store.setScheduleLog(_daysAgo(4), 'cardio', {'kind': 'table-tennis', 'minutes': 40});
      app.store.setScheduleLog(_daysAgo(5), 'cardio', {'kind': 'pilates', 'minutes': 50});
      app.store.setScheduleLog(_daysAgo(6), 'cardio', {'kind': 'run', 'minutes': 30});
      app.store.setScheduleLog(_daysAgo(40), 'cardio', {'kind': 'yoga', 'minutes': 60});
      await open(t, app);
      await t.tap(find.text('시간을 직접 넣기'));
      await t.pumpAndSettle();

      for (final id in ['walk', 'run', 'bike', 'pilates', 'table-tennis']) {
        expect(find.byKey(ValueKey('sport-chip-$id')), findsOneWidget, reason: id);
      }
      expect(find.byKey(const ValueKey('sport-chip-yoga')), findsNothing, reason: '40일 전은 최근이 아닙니다');
      expect(chipSelected(t, 'pilates'), isTrue, reason: '다니는 종목(두 번 이상) 중 가장 최근');
      expect(kmField(), findsNothing);

      /* 한 번 — 칩 하나로 바꿉니다. */
      await t.tap(find.byKey(const ValueKey('sport-chip-table-tennis')));
      await t.pump();
      expect(chipSelected(t, 'table-tennis'), isTrue);
      expect(chipSelected(t, 'pilates'), isFalse);

      await t.enterText(find.widgetWithText(TextField, '시간'), '30');
      await t.pump();
      await t.tap(find.text('저장'));
      await t.pumpAndSettle();
      expect(cardioLog(app)['kind'], 'table-tennis');
      await t.tap(find.text('닫기'));
      await t.pumpAndSettle();
    });

    /* 결함: 유산소 기록은 하루 하나인데, 두 번째 기록이 첫 기록을 말없이 덮었습니다.
       게다가 오늘 한 종목이 기본값이라 「저장」 한 번에 잘못된 종목으로 덮였습니다. */
    testWidgets('같은 날 두 번째 — 앞 기록이 있다고 말하고, 오늘 한 종목이 기본값이 되지 않는다', (t) async {
      final app = await seeded();
      app.store.setScheduleLog(_todayKey, 'cardio', {'kind': 'bike', 'minutes': 40, 'km': 12.0, 'kcal': 330});
      await open(t, app, size: const Size(360, 740));
      await t.tap(find.text('시간을 직접 넣기'));
      await t.pumpAndSettle();
      expect(find.text('이미 자전거 40분 — 저장하면 바뀝니다'), findsOneWidget);
      expect(chipSelected(t, 'bike'), isFalse, reason: '오늘의 자전거가 저녁 운동의 기본값이 되면 안 됩니다');
      expect(chipSelected(t, 'walk'), isTrue);
      expect(t.takeException(), isNull);
    });

    testWidgets('기록이 없는 날은 그 줄이 없다', (t) async {
      final app = await seeded();
      await open(t, app);
      await t.tap(find.text('시간을 직접 넣기'));
      await t.pumpAndSettle();
      expect(find.textContaining('저장하면 바뀝니다'), findsNothing);
    });

    testWidgets('수영 거리는 m — 1500 은 1.5km 로 남는다, 단위가 바뀌면 칸을 비운다', (t) async {
      final app = await seeded();
      await open(t, app);
      await t.tap(find.text('시간을 직접 넣기'));
      await t.pumpAndSettle();
      await t.enterText(find.widgetWithText(TextField, '시간'), '40');
      await t.enterText(kmField(), '3');
      await t.pump();

      await t.tap(find.text('다른 종목'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('sport-swim')));
      await t.pumpAndSettle();
      final field = t.widget<TextField>(kmField());
      expect(field.decoration?.suffixText, 'm');
      expect(field.controller?.text, isEmpty, reason: '걷기의 3(km)이 수영의 3m 가 되면 안 됩니다');

      await t.enterText(kmField(), '1500');
      await t.pump();
      await t.tap(find.text('저장'));
      await t.pumpAndSettle();
      final log = cardioLog(app);
      expect(log['kind'], 'swim');
      expect(log['km'], 1.5);
      expect(find.textContaining('수영 40분 · 1.5km'), findsOneWidget);
      await t.tap(find.text('닫기'));
      await t.pumpAndSettle();
    });

    /* 결함: 떠 있는 키보드는 「다음/완료」 가 바뀐 것을 몰라서, 칩으로 필라테스(거리 없음)로
       바꿔도 「다음」 이 남아 포커스가 엉뚱한 곳으로 갔습니다. */
    testWidgets('칩으로 종목을 바꾸면 키보드의 다음/완료 키도 바뀐다', (t) async {
      final app = await seeded();
      app.store.setScheduleLog(_daysAgo(1), 'cardio', {'kind': 'pilates', 'minutes': 50});
      app.store.setScheduleLog(_daysAgo(3), 'cardio', {'kind': 'pilates', 'minutes': 50});
      await open(t, app);
      await t.tap(find.text('시간을 직접 넣기'));
      await t.pumpAndSettle();
      expect(chipSelected(t, 'pilates'), isTrue);
      expect(t.testTextInput.setClientArgs?['inputAction'], 'TextInputAction.done',
          reason: '필라테스 — 분 칸이 마지막');

      await t.tap(find.byKey(const ValueKey('sport-chip-walk')));
      await t.pumpAndSettle();
      final minutes = t.widget<EditableText>(find.descendant(
          of: find.widgetWithText(TextField, '시간'), matching: find.byType(EditableText)));
      expect(minutes.focusNode.hasPrimaryFocus, isTrue, reason: '분 칸의 포커스가 이어집니다');
      expect(t.testTextInput.setClientArgs?['inputAction'], 'TextInputAction.next',
          reason: '걷기 — 분 다음에 거리');

      await t.tap(find.byKey(const ValueKey('sport-chip-pilates')));
      await t.pumpAndSettle();
      expect(t.testTextInput.setClientArgs?['inputAction'], 'TextInputAction.done');
    });

    testWidgets('360px — 칩 줄과 「다른 종목」 시트가 넘치지 않는다', (t) async {
      final app = await seeded();
      for (final (i, id) in ['martial-arts', 'aqua-aerobics', 'stairs'].indexed) {
        app.store.setScheduleLog(_daysAgo(i + 1), 'cardio', {'kind': id, 'minutes': 30});
      }
      await open(t, app, size: const Size(360, 740));
      await t.tap(find.text('시간을 직접 넣기'));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(find.byKey(const ValueKey('sport-chip-martial-arts')), findsOneWidget);

      await t.tap(find.text('다른 종목'));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      final tile = find.byKey(const ValueKey('sport-martial-arts'));
      await t.scrollUntilVisible(tile, 200, scrollable: find.descendant(
          of: find.byKey(const ValueKey('sport-grid')), matching: find.byType(Scrollable)));
      expect(t.getRect(tile).right, lessThanOrEqualTo(360));
      await t.tap(tile);
      await t.pumpAndSettle();
      expect(chipSelected(t, 'martial-arts'), isTrue);
      expect(t.takeException(), isNull);
    });
  });

  /* --- 홈 브리핑 -------------------------------------------------------------- */

  group('브리핑', () {
    Future<AppState> booted() async {
      SharedPreferences.setMockInitialValues({});
      final app = await AppState.boot();
      app.store.now = () => _today;
      app.store.set({'profile': _profile, 'onboarded': true});
      app.store.addScan({..._scan});
      return app;
    }

    List<String> texts(Briefing b) => [for (final l in b.lines) l.text];

    test('완료 줄은 종목 이름 — 「필라테스 완료 · 45분 · 약 165kcal」', () async {
      final app = await booted();
      app.store.setScheduleLog(_todayKey, 'cardio', {'kind': 'pilates', 'minutes': 45, 'kcal': 165});
      final b = buildBriefing(app, now: _today);
      expect(texts(b), contains('필라테스 완료 · 45분 · 약 165kcal'));
      expect(b.lines.firstWhere((l) => l.text.startsWith('필라테스')).done, isTrue);
    });

    test('거리 있는 종목은 km 까지 — 「수영 완료 · 40분 · 1.5km · 약 280kcal」', () async {
      final app = await booted();
      app.store.setScheduleLog(_todayKey, 'cardio', {'kind': 'swim', 'minutes': 40, 'km': 1.5, 'kcal': 280});
      expect(texts(buildBriefing(app, now: _today)), contains('수영 완료 · 40분 · 1.5km · 약 280kcal'));
    });

    test('모르는 kind · 기록 없는 체크는 「유산소 완료」', () async {
      final app = await booted();
      app.store.setScheduleLog(_todayKey, 'cardio', {'kind': 'curling-2099', 'minutes': 30});
      expect(texts(buildBriefing(app, now: _today)), contains('유산소 완료 · 30분'));

      final app2 = await booted();
      app2.store.setSchedulePlan(_todayKey, 'cardio', true);
      app2.store.setScheduleDone(_todayKey, 'cardio', true);
      expect(texts(buildBriefing(app2, now: _today)), contains('유산소 완료'));
    });

    test('남은 유산소 — 줄과 버튼은 「유산소 · 스포츠」', () async {
      final app = await booted();
      app.store.setSchedulePlan(_todayKey, 'cardio', true);
      final b = buildBriefing(app, now: _today);
      expect(texts(b), anyElement(startsWith('오늘은 유산소 · 스포츠 하는 날')));
      expect([b.primary?.label, ...b.secondary.map((a) => a.label)], contains('유산소 · 스포츠 시작'));
    });
  });
}
