/* =============================================================================
 * plan_tab_test.dart — 플랜 탭은 글 대신 숫자와 표로 말한다
 *
 * 0.2.11 의 운동 카드는 「근육군당 주 12세트 · Z2 저강도 · 더블 프로그레션 · RPE」
 * 를 그대로 내보냈고, 주인은 "텍스트 너무 많음 — 초보자는 무슨 운동을 해야
 * 하는지 모름" 이라고 했습니다(피드백 14 · 15). 궤적 그래프는 지방과 골격근을
 * 한 축에 겹쳐서 변화가 안 보였습니다(25). 여기서 못 박는 것:
 *   · 운동 카드 = 숫자 타일 셋 + 접힌 「왜 이렇게 짰나요?」, 용어 없음.
 *   · 세션 = 따라 하기 카드: 순서 · 기구 표 · 세트 × 반복 · 휴식. 오늘 것만 펼침.
 *   · 궤적 = 체중 · 골격근 · 체지방률 그래프 셋, 각자 축.
 *   · 「하루 3끼 예시」 는 두되 메모는 접힘.
 *   · 360px 에서 넘치지 않음.
 * ========================================================================== */
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mybody/src/api.dart';
import 'package:mybody/src/app_state.dart';
import 'package:mybody/src/scope.dart';
import 'package:mybody/src/screens/plan.dart';
import 'package:mybody/src/theme.dart';
import 'package:mybody/src/ui/charts.dart';
import 'package:mybody/src/ui/fmt.dart';
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

/// 2026-03-02 는 월요일 — 상하체 4분할의 「상체 A」 날.
final _monday = DateTime(2026, 3, 2);
/// 수요일 — 4분할의 쉬는 날.
final _wednesday = DateTime(2026, 3, 4);

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

  Future<void> open(WidgetTester t, AppState app, {DateTime? today, Size size = const Size(1000, 6000)}) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(host(app, Scaffold(body: PlanScreen(go: noop, today: today ?? _monday))));
    await t.pumpAndSettle();
    expect(find.byType(ErrorWidget), findsNothing);
  }

  List<Map<String, Object?>> sessionsOf(AppState app) =>
      (((app.state['plan'] as Map)['workout'] as Map)['sessions'] as List).cast<Map<String, Object?>>();

  Map<String, Object?> workoutOf(AppState app) =>
      ((app.state['plan'] as Map)['workout'] as Map).cast<String, Object?>();

  /* ---- 순수 함수 ---------------------------------------------------------- */

  test('유산소 타일 — 「40분 × 2회」 를 읽고, 섞였거나 못 읽으면 주당 분', () {
    final one = cardioStat({'cardioPlan': 'Z2 저강도 40분 × 2회', 'cardioMinPerWeek': 96});
    expect(one.value, '40분');
    expect(one.unit, '× 2회');
    expect(one.delta, isNull);
    final two = cardioStat({'cardioPlan': 'Z2 저강도 40분 × 4회 + HIIT 15분 × 2회', 'cardioMinPerWeek': 190});
    expect(two.value, '190');
    expect(two.unit, '분/주');
    final none = cardioStat({'cardioMinPerWeek': 80});
    expect(none.value, '80');
    expect(none.unit, '분/주');
    /* 체크인 조정으로 더한 분은 보조 줄로. */
    final adj = cardioStat({
      'cardioPlan': 'Z2 저강도 40분 × 2회 + 추가 유산소 주 30분 (체크인 조정)',
      'cardioMinPerWeek': 110,
    });
    expect(adj.value, '40분');
    expect(adj.delta, '+30분/주');
    /* 엔진은 소수도 적을 수 있습니다 — '7.5분' 이 조용히 빠지면 안 됩니다. 뺀 것은 '-'. */
    expect(cardioStat({'cardioPlan': 'Z2 저강도 40분 × 2회 + 추가 유산소 주 7.5분 (체크인 조정)'}).delta, '+7.5분/주');
    expect(cardioStat({'cardioPlan': 'Z2 저강도 40분 × 2회 + 추가 유산소 주 -20분 (체크인 조정)'}).delta, '-20분/주');
  });

  test('휴식 시간 — 75초 · 2분 · 2분 30초', () {
    expect(restLabel(75), '75초');
    expect(restLabel(90), '1분 30초');
    expect(restLabel(120), '2분');
    expect(restLabel(150), '2분 30초');
    expect(restLabel(0), '');
    expect(restLabel(null), '');
  });

  test('펼쳐 둘 세션 — 오늘 것, 쉬는 날이면 다음 운동 날, 없으면 null', () {
    final sessions = [
      for (final (i, l) in ['상체 A', '하체 A', '휴식', '상체 B', '하체 B', '휴식', '휴식'].indexed)
        <String, Object?>{'day': i, 'label': l, 'rest': l == '휴식'},
    ];
    expect(openSessionIndex(sessions, 0), 0);
    expect(openSessionIndex(sessions, 2), 3);
    expect(openSessionIndex(sessions, 6), 0);           // 일요일 → 다음 주 월요일
    expect(openSessionIndex([for (final s in sessions) {...s, 'rest': true}], 0), isNull);
    expect(openSessionIndex(const [], 0), isNull);
  });

  test('종목 표 — 기구는 사전(없으면 엔진 값), 메모는 접두어를 걷어낸다', () {
    expect(equipTag({'id': 'bench-press', 'name': '바벨 벤치프레스'}), '바벨');
    expect(equipTag({'id': 'x-unknown', 'name': '이상한 머신', 'equip': 'machine'}), '머신');
    expect(equipTag({'id': 'x-unknown', 'name': '이상한 것', 'equip': 'rope'}), 'rope');
    expect(equipTag({'name': '아무것'}), isNull);
    expect(tailorNote({'note': '견갑 고정'}), '견갑 고정');
    expect(tailorNote({'note': '$kSubstitutePrefix바벨 벤치프레스 · 홈트 대체'}), '원래 바벨 벤치프레스 · 홈트 대체');
    expect(tailorNote({'note': '$kFamiliarPrefix바벨 로우'}), '원래 바벨 로우');
    expect(tailorNote({'note': ''}), isNull);
    expect(tailorNote({}), isNull);
  });

  test('목표 체지방률 = 목표 지방 ÷ 목표 체중', () {
    expect(goalPbfPct({'weightKg': 80.0, 'bfmKg': 12.0}), closeTo(15.0, 1e-9));
    expect(goalPbfPct({'weightKg': 0, 'bfmKg': 12.0}), isNull);
    expect(goalPbfPct({'bfmKg': 12.0}), isNull);
    expect(goalPbfPct(null), isNull);
  });

  /* ---- 운동 카드 ---------------------------------------------------------- */

  testWidgets('운동 카드 — 숫자 타일 셋, 용어 없음, 근거 메모는 접힘', (t) async {
    final app = await seeded();
    await open(t, app);
    final w = workoutOf(app);
    await t.scrollUntilVisible(find.text('${w['splitName']}'), 300);
    expect(find.text('주 횟수'), findsOneWidget);
    expect(find.text('회당'), findsOneWidget);
    expect(find.text('유산소'), findsOneWidget);
    expect(find.text(cardioStat(w).value), findsWidgets);

    /* 전문용어는 화면에 없습니다. */
    for (final jargon in ['근육군당', 'Z2', '더블 프로그레션', 'RPE', '아래 종목은']) {
      expect(find.textContaining(jargon), findsNothing, reason: jargon);
    }
    expect(find.text(kProgressionHint), findsOneWidget);
    expect(find.byKey(const Key('open-gym-settings')), findsOneWidget);

    /* 엔진 메모는 「왜 이렇게 짰나요?」 를 누르기 전엔 안 보입니다. */
    final bias = (w['inbodyBias'] as List).map((b) => '$b').toList();
    expect(bias, isNotEmpty);
    expect(find.textContaining(bias.first), findsNothing);
    await t.tap(find.text('왜 이렇게 짰나요?'));
    await t.pumpAndSettle();
    expect(find.textContaining(bias.first), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('세션 카드 — 오늘 것만 펼쳐지고, 순서 · 기구 표 · 세트 × 반복 · 휴식이 보인다', (t) async {
    final app = await seeded();
    await open(t, app);            // 월요일 → 상체 A
    final sessions = sessionsOf(app);
    final upper = sessions[0], lower = sessions[1];
    expect(upper['label'], '상체 A');
    expect(lower['label'], '하체 A');
    await t.scrollUntilVisible(find.text('상체 A'), 300);

    /* 머리: 「상체 A」 + 「오늘」 + 「7종목 · 60분」 (상체 B 도 같은 줄이라 둘). */
    expect(find.text('오늘'), findsOneWidget);
    final ex = tailorSession(upper, GymPrefs.fromSettings(null));
    expect(find.textContaining('${ex.length}종목 · ${n0(upper['minutes'])}분'), findsWidgets);

    /* 몸: 첫 종목의 순서 번호 · 이름 · 기구 표 · 세트 × 반복 · 휴식. RPE 는 없음. */
    final first = ex.first;
    expect(find.text('1'), findsWidgets);
    expect(find.text('${first['name']}'), findsOneWidget);
    expect(find.text(equipTag(first)!), findsWidgets);
    expect(find.textContaining('${first['sets']}세트 × ${first['reps']}'), findsWidgets);
    expect(find.textContaining('휴식 ${restLabel(first['restSec'])}'), findsWidgets);
    expect(find.textContaining('휴식 150초'), findsNothing);

    /* 하체 A 는 접혀 있습니다 — 그 종목은 안 보입니다. 누르면 보입니다. */
    final lowerFirst = tailorSession(lower, GymPrefs.fromSettings(null)).first;
    expect(find.text('${lowerFirst['name']}'), findsNothing);
    await t.tap(find.text('하체 A'));
    await t.pumpAndSettle();
    expect(find.text('${lowerFirst['name']}'), findsOneWidget);
    /* 다시 누르면 접힙니다. */
    await t.tap(find.text('하체 A'));
    await t.pumpAndSettle();
    expect(find.text('${lowerFirst['name']}'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('초보 프리셋(설정을 안 만진 사람)에게는 「대체」 표 · 「N종목 바꿈」 · 「원래 X」 가 없다 — 요령만', (t) async {
    final app = await seeded();
    await open(t, app);            // 월요일 → 상체 A 펼침
    final sessions = sessionsOf(app);
    final ex = tailorSession(sessions[0], GymPrefs.fromSettings(null));
    final swapped = ex.where((e) => tailorTag(e) != null).toList();
    expect(swapped, isNotEmpty, reason: '초보 프리셋은 바벨 종목을 바꿉니다 — 바꾼 것이 있어야 시험이 뜻이 있습니다');
    await t.scrollUntilVisible(find.text('상체 A'), 300);
    expect(find.text('대체'), findsNothing);
    expect(find.textContaining('종목 바꿈'), findsNothing);
    expect(find.textContaining('원래 '), findsNothing);
    expect(find.textContaining(kSubstitutePrefix), findsNothing);
    /* 요령은 그대로 — 바꾼 종목의 자기 요령 한 줄. */
    final tip = tailorNote(swapped.first, original: false);
    expect(tip, isNotNull);
    expect(find.text(tip!), findsWidgets);
    expect(t.takeException(), isNull);
  });

  testWidgets('오늘이 쉬는 날이면 다음 운동 날의 세션이 펼쳐지고 「오늘」 표는 없다', (t) async {
    final app = await seeded();
    await open(t, app, today: _wednesday);          // 수요일 휴식 → 목요일 상체 B
    final sessions = sessionsOf(app);
    expect(sessions[2]['rest'], isTrue);
    expect(sessions[3]['label'], '상체 B');
    await t.scrollUntilVisible(find.text('상체 B'), 300);
    expect(find.text('오늘'), findsNothing);
    final upperFirst = tailorSession(sessions[3], GymPrefs.fromSettings(null)).first;
    /* 상체 A 와 상체 B 는 종목이 같습니다 — 펼쳐진 것이 하나뿐이면 이름도 하나입니다. */
    expect(find.text('${upperFirst['name']}'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  /* ---- 주차별 궤적 -------------------------------------------------------- */

  testWidgets('주차별 궤적 — 체중 · 골격근 · 체지방률 그래프 셋, 각자 목표선', (t) async {
    final app = await seeded();
    await open(t, app);
    expect(find.text('주차별 궤적'), findsOneWidget);
    expect(find.text('체중'), findsOneWidget);
    expect(find.text('골격근'), findsOneWidget);
    expect(find.text('체지방률'), findsOneWidget);
    final charts = t.widgetList<LineChart>(find.byType(LineChart)).toList();
    expect(charts, hasLength(3));
    for (final ch in charts) {
      expect(ch.legend, isFalse);
      expect(ch.height, 120);
      expect(ch.series, hasLength(1));
      expect(ch.goals, hasLength(1));
    }
    /* 목표선: 체중 80.5 · 골격근 39 · 체지방률 12/80.5. */
    expect(charts[0].goals.first.y, closeTo(80.5, 1e-9));
    expect(charts[1].goals.first.y, closeTo(39.0, 1e-9));
    expect(charts[2].goals.first.y, closeTo(12.0 / 80.5 * 100, 1e-9));
    /* 예전의 겹친 그래프 범례는 없습니다. */
    expect(find.text('목표 지방'), findsNothing);
    expect(find.text('목표 근육'), findsNothing);
    expect(t.takeException(), isNull);
  });

  /* ---- 식단 예시 ---------------------------------------------------------- */

  testWidgets('「하루 3끼 예시」 는 남고, 메모 세 줄은 접혀 있다', (t) async {
    final app = await seeded();
    await open(t, app);
    final diet = ((app.state['plan'] as Map)['diet'] as Map).cast<String, Object?>();
    final notes = (diet['notes'] as List).map((n) => '$n').toList();
    expect(notes, hasLength(3));
    await t.scrollUntilVisible(find.byKey(const Key('diet-notes')), 300);
    expect(find.textContaining('하루 3끼 예시'), findsOneWidget);
    expect(find.textContaining(notes.first), findsNothing);
    await t.tap(find.byKey(const Key('diet-notes')));
    await t.pumpAndSettle();
    expect(find.textContaining(notes.first), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  /* ---- 360px ------------------------------------------------------------- */

  testWidgets('360px 폭에서 넘치지 않는다 (세션 펼친 채)', (t) async {
    final app = await seeded();
    await open(t, app, size: const Size(360, 7000));
    expect(find.text('오늘'), findsOneWidget);
    /* 접힌 세션도 전부 펼쳐서 봅니다. */
    for (final l in ['하체 A', '상체 B', '하체 B']) {
      await t.tap(find.text(l));
      await t.pumpAndSettle();
    }
    await t.tap(find.text('왜 이렇게 짰나요?'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });
}
