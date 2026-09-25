/* =============================================================================
 * goal_duration_test.dart — 기간으로 목표 정하기 · 여섯 달 규칙
 *
 * 그림은 엔진 없이 봅니다. 기간 판은 옵션 표를 만드는 자리(compute)를 바꿔
 * 끼울 수 있어서, 손으로 만든 표를 넣고 카드 · 추천 · 막대 · 차트 · 버튼이
 * 제대로 서는지만 봅니다. 엔진이 옳은 표를 내는지는 코어 시험이 봅니다.
 *
 * 여섯 달 규칙은 진짜 엔진으로 봅니다 — "26주를 넘는 계획" 은 엔진이 그렇게
 * 계산해야 나오는 것이고, 그 전제를 시험 안에서 먼저 확인합니다.
 *
 * 강도 화면이 처음 골라 두는 카드(마감에 가장 가까운 것 · 막힌 것은 빼고)는 손으로
 * 만든 강도 표(compute)로 봅니다 — 어느 카드가 골라졌는지는 궤적 그래프가 그리는
 * 점의 수(주수 + 1)로 읽습니다. 막힌 카드는 진짜 엔진의 표에서 판정만 바꿔 넣습니다.
 *
 * 기간 판이 고른 옵션으로 강도 화면 없이 바로 저장하는 길도 진짜 엔진으로 봅니다 —
 * 옵션의 목표로 compareLevels 를 세우면 고른 주수 ±1주 카드가 있다는 약속이 엔진의
 * 것이라서, 손으로 만든 표로는 그 약속을 볼 수 없습니다.
 * ========================================================================== */
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mybody/src/api.dart';
import 'package:mybody/src/app_state.dart';
import 'package:mybody/src/scope.dart';
import 'package:mybody/src/screens/duration.dart';
import 'package:mybody/src/screens/goal.dart';
import 'package:mybody/src/screens/intensity.dart';
import 'package:mybody/src/theme.dart';
import 'package:mybody/src/ui/charts.dart';
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

/// 26주를 넘는 목표 — 지방 12kg 감량 + 근육 2kg. 엔진으로 어느 강도든 34주 이상,
/// 목표 화면이 고르는 감량모드로도 34주 이상입니다. 시험마다 전제를 다시 확인합니다.
const _farGoal = {'weightKg': 78.0, 'smmKg': 40.0, 'bfmKg': 7.8};

/// 26주 안의 목표 — 상 12주.
const _nearGoal = {'weightKg': 84.5, 'smmKg': 39.0, 'bfmKg': 16.0};

/* --- 손으로 만든 옵션 표 ------------------------------------------------------
 * 엔진 계약(durationOptions)과 같은 모양입니다. 숫자는 일부러 int 로도 넣습니다 —
 * 화면은 jsToNumber 로 읽어야 하고, 그걸 안 지키면 여기서 터집니다. */

Map<String, Object?> _option({
  required String id,
  required String direction,
  required String level,
  required String label,
  required double weightKg,
  required double smmKg,
  required double bfmKg,
  required int weeks,
  int? stoppedAt,
  String? note,
}) {
  const w0 = 86.7, s0 = 38.0, f0 = 20.0;
  final pbf = bfmKg / weightKg * 100;
  double at(double a, double b, int wk) => a + (b - a) * wk / weeks;
  return {
    'id': id,
    'direction': direction,
    'directionLabel': direction == 'cut' ? '감량' : '증량',
    'level': level,
    'label': label,
    'a': level == 'high' ? 0.9 : (level == 'mid' ? 0.6 : 0.3),
    'goal': {'weightKg': weightKg, 'smmKg': smmKg, 'bfmKg': bfmKg, 'pbfPct': pbf},
    'delta': {
      'weightKg': weightKg - w0, 'smmKg': smmKg - s0, 'bfmKg': bfmKg - f0,
      'pbfPct': pbf - 23.1,
    },
    'intakeKcal': 2100, 'proteinG': 160, 'daysPerWeek': 4, 'sessionMinutes': 60,
    'trajectory': [
      for (var wk = 0; wk <= weeks; wk++)
        {
          'week': wk,
          'weightKg': at(w0, weightKg, wk),
          'smmKg': at(s0, smmKg, wk),
          'bfmKg': at(f0, bfmKg, wk),
          'pbfPct': at(f0, bfmKg, wk) / at(w0, weightKg, wk) * 100,
        },
    ],
    'stoppedAt': stoppedAt,
    'note': note,
  };
}

Map<String, Object?> _fixture(int weeks,
    {List<String> warnings = const [], bool empty = false, int? stopHighAt,
    bool bulkSingle = false}) {
  return {
    'weeks': weeks,
    'options': empty
        ? <Object?>[]
        : [
            /* 증량을 먼저 넣습니다 — 화면이 감량을 앞에 세우는지 보려고. */
            if (bulkSingle)
              /* 엔진이 증량을 강도 없이 한 장으로 줄 때의 모양 — label 은 방향 이름,
                 levels 는 셋 다. */
              {
                ..._option(id: 'bulk', direction: 'bulk', level: 'mid', label: '증량',
                    weightKg: 88.5, smmKg: 39.6, bfmKg: 20.6, weeks: weeks),
                'levels': ['low', 'mid', 'high'],
              }
            else
              _option(id: 'bulk-mid', direction: 'bulk', level: 'mid', label: '중',
                  weightKg: 88.5, smmKg: 39.6, bfmKg: 20.6, weeks: weeks),
            _option(id: 'cut-low', direction: 'cut', level: 'low', label: '하',
                weightKg: 85.0, smmKg: 38.3, bfmKg: 18.0, weeks: weeks),
            _option(id: 'cut-mid', direction: 'cut', level: 'mid', label: '중',
                weightKg: 83.5, smmKg: 38.4, bfmKg: 16.8, weeks: weeks),
            _option(id: 'cut-high', direction: 'cut', level: 'high', label: '상',
                weightKg: 82.0, smmKg: 38.2, bfmKg: 15.2, weeks: weeks,
                stoppedAt: stopHighAt,
                note: stopHighAt == null ? null : '$stopHighAt주에 하한에 닿습니다.'),
          ],
    'recommended': empty ? null : 'cut-mid',
    'warnings': warnings,
  };
}

/* --- 손으로 만든 강도 표 -------------------------------------------------------
 * compareLevels 의 결과 모양. 카드가 읽는 칸만 있습니다. */

Map<String, Object?> _level(String level, int weeks, double a, {String verdict = 'ok'}) {
  const names = {'high': ('상', '최단'), 'mid': ('중', '표준'), 'low': ('하', '여유')};
  return {
    'level': level, 'label': names[level]!.$1, 'title': names[level]!.$2,
    'blurb': '$level 설명', 'weeks': weeks, 'targetDate': '2026-06-01', 'a': a,
    'sim': {
      'reached': true,
      'trajectory': [
        for (var w = 0; w <= weeks; w++)
          {'week': w, 'bfmKg': 20.0 - 4.0 * w / weeks, 'smmKg': 38.0 + 0.5 * w / weeks},
      ],
    },
    'macros': {'intakeKcal': 2100, 'proteinG': 160},
    'feasibility': {
      'verdict': verdict,
      'message': verdict == 'blocked'
          ? '목표 체지방률 6%는 필수지방(8%) 아래입니다.'
          : '이 강도로 약 $weeks주 걸립니다.',
    },
    'difficulty': 2, 'difficultyLabel': '보통', 'daysPerWeek': 4,
  };
}

Map<String, Object?> _cmp(List<Map<String, Object?>> results, {Object? recommended = 'mid'}) => {
      'results': results, 'recommended': recommended, 'warnings': <String>[],
      'goal': {..._nearGoal}, 'startDate': '2026-03-01',
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<AppState> seeded() async {
    SharedPreferences.setMockInitialValues({});
    final app = await AppState.boot();
    app.store.set({'profile': _profile, 'onboarded': true});
    app.store.addScan({..._scan});
    return app;
  }

  Api api() {
    final a = Api(
        baseUrl: '',
        client: MockClient((_) async => http.Response('{"ok":false}', 404)));
    a.setToken('tok');
    return a;
  }

  /* Scope 를 MaterialApp 위에 — 앱이 실제로 그렇게 두고, 밀어 올린 화면에서도
     보여야 합니다(screens_smoke_test 와 같은 이유). */
  Widget host(AppState app, Widget child) => Scope(
        state: app,
        api: api(),
        onServerChange: (_) async {},
        child: MaterialApp(theme: mbLight(), home: child),
      );

  void tall(WidgetTester t, [double h = 6000]) {
    t.view.physicalSize = Size(1000, h);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
  }

  /// 홈 → 자리 하나 → [top]. 계획을 세우면 강도 화면은 두 번, 기간 판은 한 번 pop
  /// 하므로, 그 pop 이 홈 위에서 끝나야 시험이 빈 화면에 안 떨어집니다.
  Future<Future<Object?>> stacked(WidgetTester t, AppState app, Widget top) async {
    await t.pumpWidget(host(app, const Scaffold(body: Text('home'))));
    final nav = t.state<NavigatorState>(find.byType(Navigator));
    nav.push(MaterialPageRoute(builder: (_) => const Scaffold(body: Text('between'))));
    final result = nav.push<Object?>(MaterialPageRoute(builder: (_) => top));
    await t.pumpAndSettle();
    return result;
  }

  FilledButton pickButton(WidgetTester t) =>
      t.widget<FilledButton>(find.widgetWithText(FilledButton, '이 계획으로 시작하기'));

  /* ---------------------------------------------------------------- 목표 화면 */

  testWidgets('목표 — 맨 위에 두 갈래가 있고, 기간으로 바꾸면 기간 판이 그 자리에 선다', (t) async {
    tall(t);
    final app = await seeded();
    await t.pumpWidget(host(app, const GoalScreen()));
    await t.pump(const Duration(milliseconds: 200));

    expect(find.text('체성분으로 정하기'), findsOneWidget);
    expect(find.text('기간으로 정하기'), findsOneWidget);
    expect(find.widgetWithText(TextField, '목표 체중'), findsOneWidget);
    expect(find.byType(DurationPanel), findsNothing);

    await t.tap(find.text('기간으로 정하기'));
    await t.pumpAndSettle();
    expect(find.byType(DurationPanel), findsOneWidget);
    expect(find.widgetWithText(TextField, '목표 체중'), findsNothing);
    expect(find.text('기간 계산하기'), findsNothing);
    expect(find.text('이 계획으로 시작하기'), findsOneWidget);
    expect(find.textContaining('현재 ('), findsOneWidget, reason: '지금 몸은 두 길에 다 보입니다');
    expect(find.byType(ErrorWidget), findsNothing);

    await t.tap(find.text('체성분으로 정하기'));
    await t.pumpAndSettle();
    expect(find.byType(DurationPanel), findsNothing);
    expect(find.widgetWithText(TextField, '목표 체중'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  /* ---------------------------------------------------------------- 기간 판 */

  testWidgets('기간 — 손으로 만든 표가 방향별 카드로 서고, 골라야 버튼이 열린다', (t) async {
    tall(t);
    final app = await seeded();
    await t.pumpWidget(host(app, DurationScreen(compute: _fixture)));
    await t.pump(const Duration(milliseconds: 200));

    expect(find.text('감량'), findsOneWidget);
    expect(find.text('증량'), findsOneWidget);
    for (final id in ['cut-low', 'cut-mid', 'cut-high', 'bulk-mid']) {
      expect(find.byKey(ValueKey('option-$id')), findsOneWidget, reason: id);
    }
    /* 감량이 증량보다 위 — 표에는 증량이 먼저 들어 있습니다. */
    expect(t.getTopLeft(find.text('감량')).dy, lessThan(t.getTopLeft(find.text('증량')).dy));
    expect(find.text('추천'), findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('option-cut-mid')), matching: find.text('추천')),
        findsOneWidget);
    expect(find.text('하루 2100 kcal · 단백질 160 g'), findsNWidgets(4));
    expect(find.text('20.0 → 16.8 · 23.1 → 20.1%'), findsOneWidget, reason: 'cut-mid 의 체지방 줄');
    expect(find.text('중 · 표준'), findsNWidgets(2), reason: '감량 중 · 증량 중');

    /* 아직 아무것도 안 골랐으니 버튼은 닫혀 있고, 차트 선은 다 같은 굵기 */
    expect(pickButton(t).onPressed, isNull);
    final before = t.widget<LineChart>(find.byType(LineChart)).series;
    expect(before, hasLength(4));
    expect(before.every((s) => s.width < 2), isTrue);

    await t.tap(find.byKey(const ValueKey('option-cut-mid')));
    await t.pump();
    expect(pickButton(t).onPressed, isNotNull);
    final after = t.widget<LineChart>(find.byType(LineChart)).series;
    expect(after.where((s) => s.width > 3).map((s) => s.label), ['감량 중'],
        reason: '고른 것만 굵게');

    expect(find.byType(ErrorWidget), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('기간 — 칩을 누르면 그 주수로 다시 계산하고, 같은 주수는 다시 계산하지 않는다', (t) async {
    tall(t);
    final asked = <int>[];
    final app = await seeded();
    await t.pumpWidget(host(app, DurationScreen(compute: (w) {
      asked.add(w);
      return _fixture(w);
    })));
    await t.pump(const Duration(milliseconds: 200));
    expect(asked, [kDurationDefault]);
    expect(t.widget<Text>(find.byKey(const Key('duration-weeks'))).data, '12주');

    await t.tap(find.widgetWithText(ChoiceChip, '24주'));
    await t.pump();
    expect(asked, [12, 24]);
    expect(t.widget<Text>(find.byKey(const Key('duration-weeks'))).data, '24주');
    expect(t.widget<Slider>(find.byType(Slider)).value, 24);
    expect(find.text('24주 동안의 체지방'), findsOneWidget);

    await t.tap(find.widgetWithText(ChoiceChip, '12주'));
    await t.pump();
    expect(asked, [12, 24], reason: '한 번 계산한 주수는 들고 있습니다');
    expect(t.takeException(), isNull);
  });

  /* 8주 아래는 인바디 오차보다 작은 변화라 안 내줍니다 — 4주짜리를 고르게 두고
     경고로 막던 것을 자 자체에서 뺐습니다. */
  testWidgets('기간 — 슬라이더는 8~52주, 4주는 고를 수 없다', (t) async {
    tall(t);
    final asked = <int>[];
    final app = await seeded();
    await t.pumpWidget(host(app, DurationScreen(compute: (w) {
      asked.add(w);
      return _fixture(w);
    }, initialWeeks: 4)));
    await t.pump(const Duration(milliseconds: 200));
    final s = t.widget<Slider>(find.byType(Slider));
    expect(s.min, kDurationMin);
    expect(kDurationMin, 8);
    expect(s.max, 52);
    expect(s.divisions, 44);
    expect(find.text('4주'), findsNothing);
    expect(find.text('8주'), findsNWidgets(3), reason: '머리글(8주로 올라감) · 칩 · 자의 왼쪽 끝');
    expect(find.text('52주'), findsOneWidget);
    expect(kDurationChips, [8, 12, 16, 24]);
    expect(asked, [8], reason: '4주로 열어도 8주로 올려서 계산합니다');
    expect(t.widget<Text>(find.byKey(const Key('duration-weeks'))).data, '8주');
    /* 기간 카드에 설명문은 없습니다 — 제목 · 주수(밑에 도달일) · 칩 · 자뿐. */
    expect(find.textContaining('갈 수 있는 몸'), findsNothing);
    expect(find.textContaining('보여 줍니다'), findsNothing);
  });

  /* 칩은 빠르고 자는 대충이라 15주 · 20주 같은 그 사이의 딱 한 주수는 − / + 로 맞춥니다.
     끝(8 · 52주)에서는 그쪽 단추가 닫혀야 — 눌러도 안 움직이는 단추는 고장으로 보입니다. */
  testWidgets('기간 — − / + 는 1주씩 옮기고, 8주와 52주 끝에서는 그쪽 단추가 닫힌다', (t) async {
    tall(t);
    final asked = <int>[];
    final app = await seeded();
    await t.pumpWidget(host(app, DurationScreen(compute: (w) {
      asked.add(w);
      return _fixture(w);
    })));
    await t.pump(const Duration(milliseconds: 200));
    final minus = find.byKey(const Key('duration-minus'));
    final plus = find.byKey(const Key('duration-plus'));
    String weeks() => t.widget<Text>(find.byKey(const Key('duration-weeks'))).data!;
    VoidCallback? pressOf(Finder f) => t.widget<IconButton>(f).onPressed;
    expect(minus, findsOneWidget);
    expect(plus, findsOneWidget);
    expect(pressOf(minus), isNotNull);
    expect(pressOf(plus), isNotNull);
    /* 단추는 자와 한 줄에, 왼쪽 − · 오른쪽 + */
    final slider = find.byType(Slider);
    expect(t.getCenter(minus).dx, lessThan(t.getCenter(slider).dx));
    expect(t.getCenter(plus).dx, greaterThan(t.getCenter(slider).dx));
    expect(t.getCenter(minus).dy, moreOrLessEquals(t.getCenter(slider).dy, epsilon: 4));

    await t.tap(plus);
    await t.pump();
    expect(weeks(), '13주');
    expect(t.widget<Slider>(slider).value, 13);
    expect(asked, [12, 13], reason: '한 주 늘리면 그 주수로 다시 계산합니다');
    expect(find.text('13주 동안의 체지방'), findsOneWidget);
    expect(find.byType(ChoiceChip).evaluate().map((e) => (e.widget as ChoiceChip).selected),
        everyElement(isFalse), reason: '13주는 칩에 없습니다');

    await t.tap(minus);
    await t.pump();
    expect(weeks(), '12주');
    expect(asked, [12, 13], reason: '12주는 들고 있던 표');

    /* 아래 끝 — 8주에서는 − 가 닫히고 눌러도 그대로 */
    await t.tap(find.widgetWithText(ChoiceChip, '8주'));
    await t.pump();
    expect(weeks(), '8주');
    expect(pressOf(minus), isNull);
    expect(pressOf(plus), isNotNull);
    await t.tap(minus);
    await t.pump();
    expect(weeks(), '8주');
    await t.tap(plus);
    await t.pump();
    expect(weeks(), '9주');
    expect(pressOf(minus), isNotNull, reason: '8주를 벗어나면 − 가 다시 열립니다');

    /* 위 끝 — 자를 52주로 끌면 + 가 닫히고 눌러도 그대로 */
    t.widget<Slider>(slider).onChanged!(52);
    await t.pump();
    expect(weeks(), '52주');
    expect(pressOf(plus), isNull);
    expect(pressOf(minus), isNotNull);
    await t.tap(plus);
    await t.pump();
    expect(weeks(), '52주');
    await t.tap(minus);
    await t.pump();
    expect(weeks(), '51주');
    expect(pressOf(plus), isNotNull);
    expect(find.byType(ErrorWidget), findsNothing);
    expect(t.takeException(), isNull);
  });

  /* 피드백 37 — 주수만 있으면 "12주가 언제까지인지" 를 사람이 세야 합니다. 오른쪽 주수
     바로 아래에 도달일을 작게, 주수를 바꾸면 날짜가 같이. 손으로 만든 표에는 도달일이
     없어서 오늘 + 주×7일이고, 엔진이 표에 적어 보내면 그 날입니다. 판 머리에 한 번만 —
     카드에는 없습니다. */
  testWidgets('기간 — 주수 아래에 도달일이 있고, 주수를 바꾸면 날짜가 같이 바뀐다', (t) async {
    tall(t);
    final app = await seeded();
    app.store.now = () => DateTime(2026, 9, 25, 9);
    expect(app.store.dayKey(), '2026-09-25', reason: '시험의 시계');
    await t.pumpWidget(host(app, DurationScreen(compute: _fixture)));
    await t.pump(const Duration(milliseconds: 200));
    final target = find.byKey(const Key('duration-target'));
    final weeks = find.byKey(const Key('duration-weeks'));
    String date() => t.widget<Text>(target).data!;
    expect(date(), '2026. 12. 18.', reason: '표에 도달일이 없으면 오늘 + 12주');
    /* 주수 바로 아래, 오른쪽 끝을 맞춰서 */
    expect(t.getTopLeft(target).dy, greaterThanOrEqualTo(t.getBottomLeft(weeks).dy - 1));
    expect(t.getBottomRight(target).dx, moreOrLessEquals(t.getBottomRight(weeks).dx, epsilon: 1));
    expect(t.getTopLeft(target).dy, lessThan(t.getTopLeft(find.byType(Slider)).dy),
        reason: '자보다 위 — 기간 카드의 머리에');

    await t.tap(find.widgetWithText(ChoiceChip, '24주'));
    await t.pump();
    expect(date(), '2027. 3. 12.');
    await t.tap(find.byKey(const Key('duration-plus')));
    await t.pump();
    expect(t.widget<Text>(weeks).data, '25주');
    expect(date(), '2027. 3. 19.');
    /* 판 머리에 한 번만 — 카드에는 날짜가 없습니다. */
    expect(find.textContaining('2027.'), findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('option-cut-mid')), matching: find.textContaining('2027')),
        findsNothing);
    expect(find.byType(ErrorWidget), findsNothing);
    expect(t.takeException(), isNull);

    /* 엔진이 도달일을 적어 보내면 그 날 — 주수로 다시 세지 않습니다. */
    await t.pumpWidget(host(
        app,
        DurationScreen(
            key: const Key('engine-date'),
            compute: (w) => {..._fixture(w), 'targetDate': '2027-01-01'})));
    await t.pump(const Duration(milliseconds: 200));
    expect(date(), '2027. 1. 1.');
    expect(t.takeException(), isNull);
  });

  test('durationTargetDate — 표의 도달일이 먼저, 없거나 못 쓰는 값이면 오늘 + 주×7일', () {
    expect(durationTargetDate({'targetDate': '2026-12-11'}, '2026-09-25', 12), '2026-12-11');
    expect(durationTargetDate(const {}, '2026-09-25', 12), '2026-12-18');
    expect(durationTargetDate({'targetDate': null}, '2026-09-25', 1), '2026-10-02');
    expect(durationTargetDate({'targetDate': ''}, '2026-09-25', 8), '2026-11-20');
    expect(durationTargetDate({'targetDate': core.invalidDateISO}, '2026-09-25', 52), '2027-09-24');
    /* 해를 넘겨도 달력대로 */
    expect(durationTargetDate(const {}, '2026-12-01', 8), '2027-01-26');
  });

  /* 엔진이 증량을 강도 없이 한 장(label '증량', levels [low, mid, high])으로 주면
     '증량 · 표준' 한 장입니다 — 셋으로 쪼개 보이려 하지 않습니다. */
  testWidgets('기간 — 증량이 한 장으로 오면 「증량 · 표준」 한 장, 범례는 「증량」', (t) async {
    tall(t);
    final app = await seeded();
    await t.pumpWidget(host(app, DurationScreen(compute: (w) => _fixture(w, bulkSingle: true))));
    await t.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const ValueKey('option-bulk')), findsOneWidget);
    expect(find.text('증량 · 표준'), findsOneWidget);
    expect(find.text('증량'), findsNWidgets(2), reason: '방향 머리글 · 차트 범례');
    expect(find.text('중 · 표준'), findsOneWidget, reason: '감량 중 만');
    final legend = t.widget<LineChart>(find.byType(LineChart)).series.map((s) => s.label);
    expect(legend, contains('증량'));
    expect(legend, isNot(contains('증량 증량')));
    expect(find.byType(ErrorWidget), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('기간 — 고른 것이 없으면 경고만 보이고 버튼은 닫힌다', (t) async {
    tall(t);
    final app = await seeded();
    await t.pumpWidget(host(app, DurationScreen(
        compute: (w) => _fixture(w, empty: true, warnings: ['$w주는 너무 짧습니다.']))));
    await t.pump(const Duration(milliseconds: 200));
    expect(find.text('12주는 너무 짧습니다.'), findsOneWidget);
    expect(find.byType(LineChart), findsNothing);
    expect(find.textContaining('하루 '), findsNothing, reason: '카드가 없습니다');
    expect(find.byKey(const Key('training-line')), findsNothing);
    expect(pickButton(t).onPressed, isNull);
    expect(t.takeException(), isNull);
  });

  testWidgets('기간 — 옵션도 경고도 없으면 그렇다고 말한다', (t) async {
    tall(t);
    final app = await seeded();
    await t.pumpWidget(host(app, DurationScreen(compute: (w) => _fixture(w, empty: true))));
    await t.pump(const Duration(milliseconds: 200));
    expect(find.text('이 기간에는 계획이 없습니다 — 기간을 바꿔 보세요'), findsOneWidget);
    expect(pickButton(t).onPressed, isNull);
  });

  testWidgets('기간 — 도중에 멈추는 옵션은 카드에 엔진의 말을 적고, 말이 없으면 우리 말로', (t) async {
    tall(t);
    final app = await seeded();
    await t.pumpWidget(host(app, DurationScreen(compute: (w) => _fixture(w, stopHighAt: 9))));
    await t.pump(const Duration(milliseconds: 200));
    /* 엔진이 이유를 보냈으면 그 말 그대로 — 같은 말을 두 번 하지 않습니다. */
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('option-cut-high')),
            matching: find.text('9주에 하한에 닿습니다.')),
        findsOneWidget);
    expect(find.textContaining('9주째에 멈춥니다'), findsNothing);
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('option-cut-mid')),
            matching: find.textContaining('닿습니다')),
        findsNothing);

    /* 이유 없이 멈춘 주만 왔을 때 */
    await t.pumpWidget(host(app, DurationScreen(compute: (w) {
      final f = _fixture(w, stopHighAt: 9);
      for (final o in (f['options'] as List).cast<Map<String, Object?>>()) {
        o['note'] = null;
      }
      return f;
    })));
    await t.pump(const Duration(milliseconds: 200));
    expect(find.text('9주째에 멈춥니다'), findsOneWidget);
    expect(find.textContaining('더 못 갑니다'), findsNothing, reason: '한 줄 — 같은 말을 두 번 하지 않습니다');
    expect(t.takeException(), isNull);
  });

  testWidgets('기간 — 측정이 없으면 먼저 넣으라고 한다', (t) async {
    SharedPreferences.setMockInitialValues({});
    final app = await AppState.boot();
    await t.pumpWidget(host(app, const DurationScreen()));
    await t.pump(const Duration(milliseconds: 200));
    expect(find.text('먼저 인바디를 넣어야 합니다'), findsOneWidget);
    expect(find.byType(Slider), findsNothing);
    expect(find.byType(ErrorWidget), findsNothing);
    expect(t.takeException(), isNull);
  });

  /* 폰에서 본 첫 반응 — "텍스트를 줄이고 체지방 · 골격근 변화를 확실히", "왜 다 주 4회지?".
     변화량이 줄에서 가장 큰 글자이고, 운동 횟수는 카드가 아니라 위에 한 번입니다. */
  testWidgets('기간 — 카드는 변화량이 주인공이고, 운동 횟수는 카드가 아니라 위에 한 번', (t) async {
    tall(t);
    final app = await seeded();
    await t.pumpWidget(host(app, DurationScreen(compute: _fixture)));
    await t.pump(const Duration(milliseconds: 200));
    final cutMid = find.byKey(const ValueKey('option-cut-mid'));
    Finder inCard(String text) => find.descendant(of: cutMid, matching: find.text(text));
    expect(inCard('−3.2 kg'), findsOneWidget, reason: '체지방 16.8 − 20.0');
    expect(inCard('+0.4 kg'), findsOneWidget, reason: '골격근 38.4 − 38.0');
    expect(inCard('20.0 → 16.8 · 23.1 → 20.1%'), findsOneWidget);
    expect(inCard('38.0 → 38.4'), findsOneWidget);
    expect(inCard('체중 86.7 → 83.5'), findsOneWidget);
    expect(inCard('하루 2100 kcal · 단백질 160 g'), findsOneWidget);
    expect(find.text('−2.0 kg'), findsOneWidget, reason: '감량 하');
    expect(find.text('−4.8 kg'), findsOneWidget, reason: '감량 상');
    expect(find.text('+0.6 kg'), findsOneWidget, reason: '증량의 체지방');
    expect(find.text('+1.6 kg'), findsOneWidget, reason: '증량의 골격근');
    /* 변화량이 그 줄에서 가장 큰 글자 — 제목보다도 큽니다 — 이고, 방향의 색입니다.
       다만 처음의 titleLarge(22px)는 "너무 크다" 여서 18px 로 살짝만 — 굵기는 그대로. */
    final theme = Theme.of(t.element(cutMid));
    final fat = t.widget<Text>(inCard('−3.2 kg')).style!;
    expect(fat.fontSize, kChangeFontSize);
    expect(kChangeFontSize, 18);
    expect(fat.fontSize!, lessThan(theme.textTheme.titleLarge!.fontSize!), reason: '옛 크기(22)보다 작게');
    expect(fat.fontWeight, FontWeight.w800, reason: '굵기는 그대로');
    expect(fat.fontSize!, greaterThan(t.widget<Text>(inCard('38.0 → 38.4')).style!.fontSize!));
    expect(fat.fontSize!, greaterThan(t.widget<Text>(inCard('중 · 표준')).style!.fontSize!));
    expect(fat.color, MbColors.light.fat);
    final smm = t.widget<Text>(inCard('+0.4 kg')).style!;
    expect(smm.color, MbColors.light.muscle);
    expect(smm.fontSize, kChangeFontSize);
    /* 옛 글(숫자 여섯 개짜리 두 줄 · 긴 설명)은 없습니다. */
    expect(find.textContaining('Δ'), findsNothing);
    expect(find.textContaining('카드의 막대는'), findsNothing);
    expect(find.text('연한 줄 지금 · 진한 줄 그때'), findsOneWidget);
    /* 운동 횟수는 카드 위에 한 번 — 엔진은 어느 강도에나 내 몸 정보의 횟수를 쓰니
       모든 카드가 같은 값이고, 같은 값을 네 번 적으면 카드가 그걸로 갈리는 줄 읽힙니다. */
    expect(find.text('운동 주 4회 · 회당 60분 — 내 몸 정보 기준'), findsOneWidget);
    expect(find.textContaining('주 4회'), findsOneWidget, reason: '카드에는 없습니다');
    expect(find.descendant(of: cutMid, matching: find.textContaining('주 4회')), findsNothing);
    expect(t.getTopLeft(find.byKey(const Key('training-line'))).dy,
        lessThan(t.getTopLeft(cutMid).dy), reason: '카드보다 위에');
    expect(find.byType(ErrorWidget), findsNothing);
    expect(t.takeException(), isNull);

    /* 카드마다 횟수가 다르면(내 몸 정보에 횟수가 없어 엔진이 강도마다 잡은 경우) 위의
       한 줄 대신 카드가 각자 적습니다. */
    await t.pumpWidget(host(app, DurationScreen(compute: (w) {
      final f = _fixture(w);
      var days = 3;
      for (final o in (f['options'] as List).cast<Map<String, Object?>>()) {
        o['daysPerWeek'] = days++;
      }
      return f;
    })));
    await t.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const Key('training-line')), findsNothing);
    expect(find.textContaining('· 주 '), findsNWidgets(4));
    expect(inCard('하루 2100 kcal · 단백질 160 g · 주 5회'), findsOneWidget,
        reason: '표의 순서대로 증량 3 · 하 4 · 중 5 · 상 6');
    expect(t.takeException(), isNull);
  });

  /* 폰 너비(360px)에서 — 변화량 옆의 작은 글이 길어도(체지방률까지) 줄이 넘치지 않아야
     합니다. 넘치면 디버그에서는 예외로 잡히고, 폰에서는 노란 줄무늬입니다. */
  testWidgets('기간 — 360px 폰 너비에서도 카드의 줄과 자(− +)가 넘치지 않는다', (t) async {
    t.view.physicalSize = const Size(360, 4000);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final app = await seeded();
    await t.pumpWidget(host(app, DurationScreen(compute: _fixture)));
    await t.pump(const Duration(milliseconds: 200));
    for (final id in ['cut-low', 'cut-mid', 'cut-high', 'bulk-mid']) {
      expect(find.byKey(ValueKey('option-$id')), findsOneWidget, reason: id);
    }
    expect(find.text('20.0 → 16.8 · 23.1 → 20.1%'), findsOneWidget);
    /* 자와 양옆 단추가 한 줄에 다 들어가고, 단추는 화면 안에 있습니다. */
    expect(find.byKey(const Key('duration-minus')), findsOneWidget);
    expect(find.byKey(const Key('duration-plus')), findsOneWidget);
    expect(t.getTopLeft(find.byKey(const Key('duration-minus'))).dx, greaterThanOrEqualTo(0));
    expect(t.getBottomRight(find.byKey(const Key('duration-plus'))).dx, lessThanOrEqualTo(360));
    expect(t.getSize(find.byType(Slider)).width, greaterThan(150), reason: '자가 끌 만큼은 남습니다');
    /* 주수 밑의 도달일도 카드 안에 — 오른쪽 끝이 화면을 안 넘습니다. */
    expect(find.byKey(const Key('duration-target')), findsOneWidget);
    expect(t.getBottomRight(find.byKey(const Key('duration-target'))).dx, lessThanOrEqualTo(360));
    await t.tap(find.byKey(const Key('duration-plus')));
    await t.pump();
    expect(t.widget<Text>(find.byKey(const Key('duration-weeks'))).data, '13주');
    expect(find.byType(ErrorWidget), findsNothing);
    expect(t.takeException(), isNull, reason: '넘침(RenderFlex overflow)은 예외로 옵니다');
  });

  test('trainingLine — 모든 카드가 같을 때만 한 줄, 회당 시간은 같을 때만, 출처는 내 몸 정보에 있을 때만', () {
    final opts = (_fixture(12)['options'] as List).cast<Map<String, Object?>>();
    expect(trainingLine(opts, _profile), '운동 주 4회 · 회당 60분 — 내 몸 정보 기준');
    /* 내 몸 정보에 횟수가 없는데 우연히 같으면 — 어디서 왔다고 말하지 않습니다. */
    expect(trainingLine(opts, {..._profile, 'daysPerWeek': null}), '운동 주 4회 · 회당 60분');
    expect(trainingLine(opts, {..._profile, 'daysPerWeek': 0}), '운동 주 4회 · 회당 60분');
    /* 회당 시간이 없거나(옛 표) 강도마다 다르면 횟수만. */
    expect(trainingLine([for (final o in opts) {...o, 'sessionMinutes': null}], _profile),
        '운동 주 4회 — 내 몸 정보 기준');
    expect(
        trainingLine(
            [for (var i = 0; i < opts.length; i++) {...opts[i], 'sessionMinutes': 45 + i}],
            _profile),
        '운동 주 4회 — 내 몸 정보 기준');
    /* 횟수가 다르면 줄이 없습니다 — 카드가 각자 적습니다. */
    expect(
        trainingLine(
            [for (var i = 0; i < opts.length; i++) {...opts[i], 'daysPerWeek': 3 + i}],
            _profile),
        isNull);
    expect(trainingLine([for (final o in opts) {...o, 'daysPerWeek': null}], _profile), isNull);
    expect(trainingLine(const [], _profile), isNull);
    /* "4" 와 4.0 은 같은 값입니다. */
    expect(
        trainingLine([
          {...opts.first, 'daysPerWeek': '4'},
          {...opts.last, 'daysPerWeek': 4.0},
        ], _profile),
        startsWith('운동 주 4회'));
  });

  /* 시험이 목표 표만 받아 보는 길 — 세 숫자는 엔진이 준 그대로, 마감은 고른 주수,
     화면 사정(공격성 · 어디서 왔는지)은 표에 안 섞입니다. 저장되는 목표라서요. */
  testWidgets('기간 — onPick 이 있으면 저장하지 않고 세 숫자와 마감 주수만 넘긴다', (t) async {
    tall(t);
    final app = await seeded();
    Map<String, Object?>? got;
    await t.pumpWidget(host(
        app,
        Scaffold(
            body: ListView(children: [
          DurationPanel(compute: _fixture, onPick: (g) => got = g),
        ]))));
    await t.pump(const Duration(milliseconds: 200));
    await t.tap(find.byKey(const ValueKey('option-cut-mid')));
    await t.pump();
    await t.tap(find.text('이 계획으로 시작하기'));
    await t.pumpAndSettle();
    expect(got, {'weightKg': 83.5, 'smmKg': 38.4, 'bfmKg': 16.8, 'deadlineWeeks': 12});
    expect(app.state['goal'], isNull);
    expect(app.state['plan'], isNull);
    expect(find.byType(IntensityScreen), findsNothing);
    expect(t.takeException(), isNull);
  });

  /* 고르면 여기서 바로 계획을 세웁니다 — 강도 화면을 거치지 않습니다. 진짜 엔진으로
     봅니다: 옵션의 목표는 엔진이 12주 안에 닿는다고 계산한 몸이라 compareLevels 에도
     12주 ±1주 카드가 있어야 하고, 그 카드가 계획이 되어야 합니다. */
  testWidgets('기간 — 「이 계획으로 시작하기」는 강도 화면 없이 바로 저장하고 화면을 닫는다', (t) async {
    tall(t);
    final app = await seeded();
    await stacked(t, app, const DurationScreen());
    final card = find.byKey(const ValueKey('option-cut-mid'));
    expect(card, findsOneWidget, reason: '이 시험의 전제 — 엔진이 감량 중 카드를 냅니다');
    await t.tap(card);
    await t.pump();
    await t.tap(find.text('이 계획으로 시작하기'));
    await t.pumpAndSettle();

    expect(find.byType(IntensityScreen), findsNothing, reason: '기간을 다시 고르게 하지 않습니다');
    expect(find.byType(DurationScreen), findsNothing);
    expect(find.text('between'), findsOneWidget, reason: '한 번 pop — 판이 선 화면이 닫힙니다');
    expect(find.text('계획을 세웠습니다'), findsOneWidget);

    final goal = (app.state['goal'] as Map).cast<String, Object?>();
    expect(goal['deadlineWeeks'], 12);
    expect(goal.containsKey('preferA'), isFalse);
    expect(goal.containsKey('fromDuration'), isFalse);
    /* 카드의 세 숫자가 그대로 목표 — 반올림하지 않고 넘깁니다. */
    final options =
        (core.durationOptions({..._scan}, _profile, 12, app.store.dayKey(), null)['options'] as List)
            .cast<Map<String, Object?>>();
    final picked =
        (options.firstWhere((o) => o['id'] == 'cut-mid')['goal'] as Map).cast<String, Object?>();
    expect(goal['weightKg'], core.jsToNumber(picked['weightKg']));
    expect(goal['smmKg'], core.jsToNumber(picked['smmKg']));
    expect(goal['bfmKg'], core.jsToNumber(picked['bfmKg']));

    final plan = (app.state['plan'] as Map).cast<String, Object?>();
    expect((core.jsToNumber(plan['weeks']) - 12).abs(), lessThanOrEqualTo(kDeadlineSlackWeeks),
        reason: '고른 주수에 가장 가까운 카드가 계획입니다');
    expect((plan['goal'] as Map)['bfmKg'], goal['bfmKg']);
    expect(t.takeException(), isNull);
  });

  /* ---------------------------------------------------------------- 여섯 달 규칙 */

  /// 시험의 전제 — 이 목표는 추천 강도가 26주를 넘습니다.
  void assumeFar(Map<String, Object?>? modeDef) {
    final cmp = core.compareLevels({..._scan}, _profile, {..._farGoal}, '2026-03-01', null, modeDef);
    final rec = (cmp['results'] as List)
        .cast<Map>()
        .firstWhere((r) => r['level'] == cmp['recommended']);
    expect(core.jsToNumber(rec['weeks']), greaterThan(kLongGoalWeeks),
        reason: '이 시험의 전제 — 추천 강도가 26주를 넘어야 합니다');
  }

  testWidgets('기간 고르기 — 26주를 넘는 계획은 먼저 묻고, 「그대로 가기」면 그대로 저장한다', (t) async {
    tall(t);
    assumeFar(null);
    final app = await seeded();
    await stacked(t, app, const IntensityScreen(goal: _farGoal));

    await t.tap(find.text('이 계획으로 시작하기'));
    await t.pumpAndSettle();
    expect(find.text('장기 목표는 동기를 잃기 쉬워요!'), findsOneWidget);
    expect(find.textContaining('기간별로 가능한 계획을 추천해 드릴까요?'), findsOneWidget);
    expect(app.state['plan'], isNull, reason: '묻는 동안은 저장하지 않습니다');

    await t.tap(find.text('그대로 가기'));
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(app.state['plan'], isNotNull);
    expect((app.state['goal'] as Map)['weightKg'], 78.0);
    expect(core.jsToNumber((app.state['plan'] as Map)['weeks']), greaterThan(kLongGoalWeeks));
    expect(find.text('home'), findsOneWidget, reason: '두 번 pop 해서 홈으로');
    expect(t.takeException(), isNull);
  });

  testWidgets('기간 고르기 — 「기간으로 정하기」는 저장하지 않고 답을 들고 돌아간다', (t) async {
    tall(t);
    assumeFar(null);
    final app = await seeded();
    final result = await stacked(t, app, const IntensityScreen(goal: _farGoal));

    await t.tap(find.text('이 계획으로 시작하기'));
    await t.pumpAndSettle();
    await t.tap(find.descendant(
        of: find.byType(AlertDialog), matching: find.text('기간으로 정하기')));
    await t.pumpAndSettle();

    expect(await result, IntensityScreen.pickDuration);
    expect(app.state['plan'], isNull);
    expect(app.state['goal'], isNull);
    expect(find.text('between'), findsOneWidget, reason: '한 번만 pop — 목표 화면 자리로');
    expect(t.takeException(), isNull);
  });

  testWidgets('기간 고르기 — 물음을 닫으면 아무것도 하지 않는다', (t) async {
    tall(t);
    assumeFar(null);
    final app = await seeded();
    await stacked(t, app, const IntensityScreen(goal: _farGoal));
    await t.tap(find.text('이 계획으로 시작하기'));
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await t.tapAt(const Offset(5, 5)); // 바깥을 눌러 닫기
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(app.state['plan'], isNull);
    expect(find.byType(IntensityScreen), findsOneWidget, reason: '그 자리에 그대로');
  });

  testWidgets('기간 고르기 — 기간 화면에서 온 목표는 묻지 않는다', (t) async {
    tall(t);
    assumeFar(null);
    final app = await seeded();
    await stacked(t, app, const IntensityScreen(
        goal: {..._farGoal, 'deadlineWeeks': 34}, fromDuration: true));
    await t.tap(find.text('이 계획으로 시작하기'));
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(app.state['plan'], isNotNull);
    final goal = app.state['goal'] as Map;
    expect(goal['deadlineWeeks'], 34);
    expect(goal.containsKey('fromDuration'), isFalse);
    expect(t.takeException(), isNull);
  });

  testWidgets('기간 고르기 — 26주 안의 계획은 묻지 않는다', (t) async {
    tall(t);
    final cmp = core.compareLevels({..._scan}, _profile, {..._nearGoal}, '2026-03-01', null, null);
    for (final r in (cmp['results'] as List).cast<Map>()) {
      expect(core.jsToNumber(r['weeks']), lessThanOrEqualTo(kLongGoalWeeks),
          reason: '이 시험의 전제 — 어느 강도든 26주 안');
    }
    final app = await seeded();
    await stacked(t, app, const IntensityScreen(goal: _nearGoal));
    await t.tap(find.text('이 계획으로 시작하기'));
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(app.state['plan'], isNotNull);
    expect(t.takeException(), isNull);
  });

  /* 목표 화면부터 끝까지 — 세 숫자 → 강도 → 물음 → 「기간으로 정하기」 → 목표
     화면이 기간 모드로 → 카드 고르기 → 저장. 이 길은 진짜 엔진(compareLevels ·
     durationOptions)을 탑니다. */
  testWidgets('목표 → 강도 → 「기간으로 정하기」 → 기간 판에서 고르면 바로 저장하고 목표 화면이 닫힌다', (t) async {
    tall(t);
    assumeFar(core.modeById('fatLoss'));
    final app = await seeded();
    await stacked(t, app, const GoalScreen());

    await t.enterText(find.widgetWithText(TextField, '목표 체중'), '78');
    await t.enterText(find.widgetWithText(TextField, '목표 골격근량'), '40');
    await t.pump();
    expect(find.text('세 숫자가 서로 안 맞습니다.'), findsNothing);
    /* 마감 칩을 골라 둡니다 — 돌아온 기간 판이 이 주수에서 열려야 합니다. */
    await t.tap(find.widgetWithText(ChoiceChip, '24주'));
    await t.pump();
    await t.tap(find.text('기간 계산하기'));
    await t.pumpAndSettle();
    expect(find.byType(IntensityScreen), findsOneWidget);
    expect(t.widget<IntensityScreen>(find.byType(IntensityScreen)).goal['deadlineWeeks'], 24);

    await t.tap(find.text('이 계획으로 시작하기'));
    await t.pumpAndSettle();
    expect(find.text('장기 목표는 동기를 잃기 쉬워요!'), findsOneWidget);
    await t.tap(find.descendant(
        of: find.byType(AlertDialog), matching: find.text('기간으로 정하기')));
    await t.pumpAndSettle();

    expect(find.byType(IntensityScreen), findsNothing);
    expect(find.byType(GoalScreen), findsOneWidget);
    expect(find.byType(DurationPanel), findsOneWidget, reason: '기간 모드로 바뀌어 있어야 합니다');
    expect(t.widget<DurationPanel>(find.byType(DurationPanel)).initialWeeks, 24);
    expect(t.widget<Text>(find.byKey(const Key('duration-weeks'))).data, '24주',
        reason: '고른 마감 칩에서 엽니다');
    expect(find.widgetWithText(TextField, '목표 체중'), findsNothing);
    expect(app.state['plan'], isNull);
    expect(find.byType(ErrorWidget), findsNothing);
    expect(t.takeException(), isNull);

    /* 기간 판에서 추천 카드를 고르고 시작 — 강도 화면을 다시 거치지 않고 저장하고, 목표
       화면이 닫혀 그 아래(셸 자리)로 돌아갑니다. 기간은 이미 골랐으니까요. */
    await t.tap(find.text('추천'));
    await t.pump();
    await t.tap(find.text('이 계획으로 시작하기'));
    await t.pumpAndSettle();
    expect(find.byType(IntensityScreen), findsNothing);
    expect(find.byType(GoalScreen), findsNothing);
    expect(find.text('between'), findsOneWidget, reason: '한 번 pop — 목표 화면이 닫힙니다');
    expect(find.text('계획을 세웠습니다'), findsOneWidget);
    expect((app.state['goal'] as Map)['deadlineWeeks'], 24);
    expect((core.jsToNumber((app.state['plan'] as Map)['weeks']) - 24).abs(),
        lessThanOrEqualTo(kDeadlineSlackWeeks));
    expect(t.takeException(), isNull);
  });

  testWidgets('목표 — 마감 칩 없이 기간으로 바꾸면 12주에서 연다', (t) async {
    tall(t);
    final app = await seeded();
    await t.pumpWidget(host(app, const GoalScreen()));
    await t.pump(const Duration(milliseconds: 200));
    await t.tap(find.text('기간으로 정하기'));
    await t.pumpAndSettle();
    expect(t.widget<DurationPanel>(find.byType(DurationPanel)).initialWeeks, kDurationDefault);
    expect(t.widget<Text>(find.byKey(const Key('duration-weeks'))).data, '12주');
  });

  /* ---------------------------------------------------------------- 처음 골라 두는 카드 */

  /// 궤적 그래프가 그리는 점의 수 = 고른 카드의 주수 + 1.
  int shownWeeks(WidgetTester t) =>
      t.widget<LineChart>(find.byType(LineChart)).series.first.points.length - 1;

  FilledButton startButton(WidgetTester t) =>
      t.widget<FilledButton>(find.widgetWithText(FilledButton, '이 계획으로 시작하기'));

  test('closestToDeadline — 가장 가까운 주수, 같으면 더 긴 쪽, ±1주 안에서는 a 가 가까운 쪽', () {
    final far = [_level('high', 10, 0.9), _level('mid', 16, 0.6), _level('low', 20, 0.3)];
    expect(closestToDeadline(far, 12)?['level'], 'high');
    expect(closestToDeadline(far, 18)?['level'], 'low', reason: '16 과 20 이 같은 거리면 긴(여유로운) 쪽');
    expect(closestToDeadline(far, 17)?['level'], 'mid');
    expect(closestToDeadline(far, 19)?['level'], 'low');
    expect(closestToDeadline(far, 12, preferA: 0.3)?['level'], 'high',
        reason: '±1주 안에 카드가 없으면 a 는 안 봅니다');
    expect(closestToDeadline(far, null), isNull);
    expect(closestToDeadline(far, 0), isNull);
    expect(closestToDeadline(const [], 12), isNull);

    final tie = [_level('high', 10, 0.9), _level('mid', 14, 0.6), _level('low', 20, 0.3)];
    expect(closestToDeadline(tie, 12)?['level'], 'mid', reason: '10 과 14 가 같은 거리면 긴(여유로운) 쪽');

    final near = [_level('high', 11, 0.9), _level('mid', 12, 0.6), _level('low', 13, 0.3)];
    expect(closestToDeadline(near, 12)?['level'], 'mid');
    expect(closestToDeadline(near, 12, preferA: 0.3)?['level'], 'low');
    expect(closestToDeadline(near, 12, preferA: 0.95)?['level'], 'high');
    expect(closestToDeadline(near, 12, preferA: 0.75)?['level'], 'mid', reason: '0.9 와 0.6 중 가까운 0.6');
  });

  test('closestToDeadline — 같은 거리는 긴 쪽', () {
    final r = [_level('high', 16, 0.9), _level('mid', 20, 0.6)];
    expect(closestToDeadline(r, 18)?['level'], 'mid');
  });

  test('initialLevel — 막힌 카드는 안 고르고, 마감이 있으면 추천보다 마감', () {
    final r = [_level('high', 10, 0.9), _level('mid', 16, 0.6), _level('low', 20, 0.3)];
    expect(initialLevel(r, 'mid'), 'mid');
    expect(initialLevel(r, null), 'high', reason: '추천이 없으면 첫 열린 카드');
    expect(initialLevel(r, 'mid', deadlineWeeks: 12), 'high');
    expect(initialLevel(r, 'mid', deadlineWeeks: 19), 'low');

    final midBlocked = [_level('high', 10, 0.9), _level('mid', 16, 0.6, verdict: 'blocked'), _level('low', 20, 0.3)];
    expect(initialLevel(midBlocked, 'mid'), 'high', reason: '추천이 막혔으면 첫 열린 카드');
    expect(initialLevel(midBlocked, 'mid', deadlineWeeks: 16), 'low',
        reason: '막힌 16주 카드 대신 그다음 가까운 20주(10주보다 가깝습니다)');
    expect(initialLevel(midBlocked, 'mid', deadlineWeeks: 15), 'low',
        reason: '10 과 20 이 같은 거리면 긴 쪽');

    final all = [for (final l in ['high', 'mid', 'low']) _level(l, 12, 0.5, verdict: 'blocked')];
    expect(initialLevel(all, 'mid'), isNull);
    expect(initialLevel(const [], 'mid'), isNull);
    expect(isBlocked(_level('mid', 12, 0.5, verdict: 'blocked')), isTrue);
    expect(isBlocked(_level('mid', 12, 0.5, verdict: 'unrealistic')), isFalse);
    expect(isBlocked({'level': 'mid'}), isFalse, reason: '판정 칸이 없으면 막힌 것이 아닙니다');
  });

  testWidgets('기간 고르기 — 기간 화면에서 온 목표는 추천이 아니라 고른 주수에 가장 가까운 카드', (t) async {
    tall(t);
    final app = await seeded();
    final table = _cmp([_level('high', 10, 0.9), _level('mid', 16, 0.6), _level('low', 20, 0.3)]);
    await t.pumpWidget(host(app, IntensityScreen(
        goal: const {..._nearGoal, 'deadlineWeeks': 12},
        fromDuration: true,
        preferA: 0.6,
        compute: (_) => table)));
    await t.pumpAndSettle();
    expect(shownWeeks(t), 10, reason: '12주에 가장 가까운 10주 카드(상), 추천(중 · 16주)이 아니라');
    expect(find.text('추천'), findsOneWidget, reason: '추천 표시는 그대로 중에');
    expect(
        find.descendant(of: find.widgetWithText(InkWell, '중 · 표준'), matching: find.text('추천')),
        findsOneWidget);
    /* ±1주 안에 카드가 없으니 그렇다고 말합니다. */
    expect(find.byKey(const Key('duration-note')), findsOneWidget);
    expect(find.text('기간으로 고른 계획 — 주수가 조금 다를 수 있습니다'),
        findsOneWidget);
    expect(startButton(t).onPressed, isNotNull);
    expect(t.takeException(), isNull);

    /* 같은 표를 기간 화면을 거치지 않고 열면 추천대로. 열쇠를 바꿔서 새 화면으로 —
       같은 자리의 같은 위젯이면 상태(고른 카드)가 남습니다. */
    await t.pumpWidget(host(app, IntensityScreen(
        key: const Key('second'),
        goal: const {..._nearGoal, 'deadlineWeeks': 12}, compute: (_) => table)));
    await t.pumpAndSettle();
    expect(shownWeeks(t), 16);
    expect(find.byKey(const Key('duration-note')), findsNothing);
  });

  testWidgets('기간 고르기 — 마감 ±1주 안에 카드가 여럿이면 옵션의 a 에 가장 가까운 카드, 안내 없음', (t) async {
    tall(t);
    final app = await seeded();
    final table = _cmp([_level('high', 11, 0.9), _level('mid', 12, 0.6), _level('low', 13, 0.3)]);
    await t.pumpWidget(host(app, IntensityScreen(
        goal: const {..._nearGoal, 'deadlineWeeks': 12},
        fromDuration: true,
        preferA: 0.3,
        compute: (_) => table)));
    await t.pumpAndSettle();
    expect(shownWeeks(t), 13, reason: 'a 0.3 인 하 카드 — 기간 화면에서 「하 · 여유」 를 골랐으니');
    expect(find.byKey(const Key('duration-note')), findsNothing, reason: '12주 카드가 있으니 안내가 없습니다');

    await t.pumpWidget(host(app, IntensityScreen(
        key: const Key('second'),
        goal: const {..._nearGoal, 'deadlineWeeks': 12},
        fromDuration: true,
        compute: (_) => table)));
    await t.pumpAndSettle();
    expect(shownWeeks(t), 12, reason: 'a 가 없으면 주수만 봅니다');
    expect(t.takeException(), isNull);
  });

  /* ---------------------------------------------------------------- 막힌 계획 */

  Map<String, Object?> realTable({Set<String> blocked = const {}}) {
    final cmp = core.compareLevels({..._scan}, _profile, {..._nearGoal}, '2026-03-01', null, null);
    for (final r in (cmp['results'] as List).cast<Map<String, Object?>>()) {
      if (blocked.contains(r['level'])) {
        (r['feasibility'] as Map)['verdict'] = 'blocked';
        (r['feasibility'] as Map)['message'] = '목표 체지방률 6%는 필수지방(8%) 아래입니다.';
      }
    }
    return cmp;
  }

  testWidgets('기간 고르기 — 추천이 막혔으면 다른 카드를 골라 두고, 시작해도 막힌 계획은 저장되지 않는다', (t) async {
    tall(t);
    final app = await seeded();
    final table = realTable();
    final rec = '${table['recommended']}';
    final blockedTable = realTable(blocked: {rec});
    await stacked(t, app, IntensityScreen(goal: _nearGoal, compute: (_) => blockedTable));

    expect(find.byKey(const Key('all-blocked')), findsNothing);
    expect(startButton(t).onPressed, isNotNull, reason: '열린 카드가 있으니 시작할 수 있습니다');
    await t.tap(find.text('이 계획으로 시작하기'));
    await t.pumpAndSettle();
    final plan = app.state['plan'] as Map?;
    expect(plan, isNotNull);
    expect(plan!['level'], isNot(rec), reason: '막힌 추천 대신 열린 카드로');
    expect(find.text('home'), findsOneWidget, reason: '저장하고 두 번 pop');
    expect(t.takeException(), isNull);
  });

  testWidgets('기간 고르기 — 셋 다 막혔으면 아무것도 안 골라져 있고 단추가 닫힌다', (t) async {
    tall(t);
    final app = await seeded();
    final table = realTable(blocked: {'high', 'mid', 'low'});
    await stacked(t, app, IntensityScreen(goal: _nearGoal, compute: (_) => table));
    expect(startButton(t).onPressed, isNull);
    expect(find.byKey(const Key('all-blocked')), findsOneWidget);
    expect(find.textContaining('고를 수 있는 계획이 없습니다'), findsOneWidget);
    /* 막힌 카드는 눌러도 안 골라집니다. */
    await t.tap(find.text('중 · 표준'), warnIfMissed: false);
    await t.pump();
    expect(startButton(t).onPressed, isNull);
    expect(app.state['plan'], isNull);
    expect(app.state['goal'], isNull);
    expect(find.byType(IntensityScreen), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  test('blockedMessage — 필수지방이 기본, 근육 상한이면 그쪽', () {
    expect(blockedMessage(_level('mid', 12, 0.5, verdict: 'blocked')),
        '이 계획은 필수지방 아래로 내려가서 만들 수 없습니다 — 목표를 조금 올리세요');
    expect(
        blockedMessage({
          'feasibility': {'verdict': 'blocked', 'message': '목표 골격근량이 약물 없이 도달 가능한 상한을 넘습니다'}
        }),
        contains('근육 목표를 조금 낮추세요'));
    expect(blockedMessage({'level': 'mid'}), contains('필수지방'));
  });

  testWidgets('여섯 달 물음 — 주와 개월을 같이 말한다', (t) async {
    final app = await seeded();
    LongGoalChoice? got;
    await t.pumpWidget(host(
        app,
        Builder(
            builder: (ctx) => Scaffold(
                  body: TextButton(
                    onPressed: () async => got = await showLongGoalDialog(ctx, 30),
                    child: const Text('열기'),
                  ),
                ))));
    await t.tap(find.text('열기'));
    await t.pumpAndSettle();
    expect(find.text('이 계획은 30주(약 7개월)입니다. 기간별로 가능한 계획을 추천해 드릴까요?'),
        findsOneWidget);
    await t.tap(find.text('그대로 가기'));
    await t.pumpAndSettle();
    expect(got, LongGoalChoice.proceed);
  });

  /* 27 · 28주는 달로 반올림하면 도로 6개월 — "장기" 라면서 "약 6개월" 이라고 하지 않습니다. */
  testWidgets('여섯 달 물음 — 27주는 「6개월을 넘깁니다」', (t) async {
    final app = await seeded();
    await t.pumpWidget(host(
        app,
        Builder(
            builder: (ctx) => Scaffold(
                  body: TextButton(
                    onPressed: () => showLongGoalDialog(ctx, 27),
                    child: const Text('열기'),
                  ),
                ))));
    await t.tap(find.text('열기'));
    await t.pumpAndSettle();
    expect(find.text('이 계획은 27주로 6개월을 넘깁니다. 기간별로 가능한 계획을 추천해 드릴까요?'),
        findsOneWidget);
    expect(find.textContaining('약 6개월'), findsNothing);
  });

  test('longGoalSpan — 27 · 28주는 넘긴다고, 29주부터는 약 N개월', () {
    expect(longGoalSpan(27), '27주로 6개월을 넘깁니다');
    expect(longGoalSpan(28), '28주로 6개월을 넘깁니다');
    expect(longGoalSpan(29), '29주(약 7개월)입니다');
    expect(longGoalSpan(52), '52주(약 12개월)입니다');
  });

  test('isLongGoal — 26주까지는 짧은 계획', () {
    expect(isLongGoal(26), isFalse);
    expect(isLongGoal(26.0), isFalse);
    expect(isLongGoal(27), isTrue);
    expect(isLongGoal(26.5), isTrue);
    expect(isLongGoal(null), isFalse);
  });

  /* ---------------------------------------------------------------- 작은 것들 */

  test('groupByDirection — 감량이 먼저, 안에서는 온 순서대로', () {
    final opts = (_fixture(12)['options'] as List).cast<Map<String, Object?>>();
    final groups = groupByDirection(opts);
    expect(groups.map((g) => g.label), ['감량', '증량']);
    expect(groups.first.options.map((o) => o['id']), ['cut-low', 'cut-mid', 'cut-high']);
    expect(groups.last.options.map((o) => o['id']), ['bulk-mid']);
  });

  test('optionTitle — 강도에 한마디, 합친 것은 같은 계획, 방향 이름 한 장은 표준', () {
    expect(optionTitle({'level': 'high', 'label': '상'}), '상 · 크게');
    expect(optionTitle({'level': 'mid', 'label': '중'}), '중 · 표준');
    expect(optionTitle({'level': 'low', 'label': '하'}), '하 · 여유');
    expect(optionTitle({'level': 'mid', 'label': '하·중'}), '하·중 · 같은 계획');
    expect(optionTitle({'level': 'mid', 'label': '하·중·상', 'levels': ['low', 'mid', 'high']}),
        '하·중·상 · 같은 계획');
    /* 엔진이 증량을 강도 없이 한 장으로 줄 때 — level 이 무엇이든 표준 한 장. */
    expect(optionTitle({'level': 'mid', 'label': '증량', 'levels': ['low', 'mid', 'high']}), '증량 · 표준');
    expect(optionTitle({'level': 'bulk', 'label': '증량'}), '증량 · 표준');
    expect(optionTitle({'level': 'high', 'label': '상', 'levels': ['low', 'mid', 'high']}), '상 · 표준');
    expect(optionTitle({'level': 'mid'}), '표준');
    expect(seriesLabel({'directionLabel': '감량', 'label': '중'}), '감량 중');
    expect(seriesLabel({'directionLabel': '증량', 'label': '증량'}), '증량');
    expect(seriesLabel({'directionLabel': '증량'}), '증량');
  });

  test('별표 — 기간 판의 문구에 **표시**가 섞여 있지 않다', () {
    /* toast 와 Text 는 마크다운을 모릅니다(widgets.dart). */
    final opts = (_fixture(12)['options'] as List).cast<Map<String, Object?>>();
    for (final s in [
      '이 계획으로 시작하기',
      '먼저 인바디를 넣어야 합니다',
      '연한 줄 지금 · 진한 줄 그때',
      '계획을 세웠습니다',
      trainingLine(opts, _profile)!,
    ]) {
      expect(s.contains('**'), isFalse);
    }
  });
}
