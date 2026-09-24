/* =============================================================================
 * progress_plan_test.dart — 추이 탭에 플랜의 예상 변화가 점선으로 겹쳐 나오는가
 *
 * 0.2.9 를 써 본 뒤 "플랜의 예상 변화 그래프랑 중첩해서 비교가능하게 해줘".
 * 규칙은 lib/src/screens/progress.dart 머리에 있습니다. 여기서는 둘을 봅니다 —
 * (1) 점 계산: 시작일 + 주차×7일이 측정과 같은 "에포크 이후 일수" 이고 y 가
 *     궤적 값인지, 숫자가 아닌 칸을 0 으로 그리지 않고 건너뛰는지.
 * (2) 화면: 체중 · 골격근 · 체지방률 카드 셋의 범례에 「플랜」 이 하나씩 나오고,
 *     계획이 없으면 하나도 없는지. 체크인 점선이 있는 체중 카드는 선이 셋입니다.
 *
 * 시험 데이터는 briefing_test 와 같은 모양(인바디 둘 · 목표 · mid 플랜)이지만
 * 그 파일을 import 하지는 않습니다 — 시험끼리 얽히면 하나가 바뀔 때 둘이 깨집니다.
 * ========================================================================== */
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mybody/src/api.dart';
import 'package:mybody/src/app_state.dart';
import 'package:mybody/src/scope.dart';
import 'package:mybody/src/screens/progress.dart';
import 'package:mybody/src/theme.dart';
import 'package:mybody/src/ui/charts.dart';
import 'package:mybody_core/mybody_core.dart' as core;
import 'package:shared_preferences/shared_preferences.dart';

const _scan = {
  'id': 's1', 'weightKg': 86.7, 'smmKg': 38.0, 'bfmKg': 20.0,
  'pbfPct': 23.1, 'ffmKg': 66.7, 'bmi': 24.8, 'bmrKcal': 1810,
  'measuredAt': '2026-03-01T00:00:00.000Z',
};
const _scan2 = {
  'id': 's2', 'weightKg': 84.4, 'smmKg': 38.6, 'bfmKg': 17.5,
  'pbfPct': 20.7, 'measuredAt': '2026-05-20T00:00:00.000Z',
};
const _profile = {
  'sex': 'male', 'age': 22, 'heightCm': 187, 'activityLevel': 'moderate',
  'trainingAge': 'novice', 'daysPerWeek': 4, 'mealsPerDay': 3,
};

/// 계획 시작일 — 마지막 인바디(5/20) 뒤에 둡니다. 계획선이 측정 뒤로 이어져야
/// x축이 미래로 늘어나는지를 볼 수 있습니다.
const _planStart = '2026-09-07';

/// 에포크 이후 일수 — 화면이 측정 시각과 계획선에 같이 쓰는 x 단위.
double _days(DateTime d) => d.millisecondsSinceEpoch / 86400000.0;

/* 체중 카드 밑 설명은 체크인 점이 있을 때 이 한 줄뿐 — 「플랜」 점선은 범례가 말합니다(피드백 24). */
const _checkinNote = '체크인 점은 집 체중계 값 — 인바디와 0.5~1kg 다를 수 있습니다';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<AppState> seeded({bool withPlan = true, bool withCheckin = false}) async {
    SharedPreferences.setMockInitialValues({});
    final app = await AppState.boot();
    app.store.set({'profile': _profile, 'onboarded': true});
    app.store.addScan({..._scan});
    app.store.addScan({..._scan2});
    if (withPlan) {
      final goal = {'weightKg': 80.5, 'smmKg': 39.0, 'bfmKg': 12.0};
      final cmp = core.compareLevels({..._scan}, _profile, goal, '2026-03-01', null, null);
      final plan = core.buildPlan(cmp, 'mid', {..._scan}, _profile)!;
      plan['startDate'] = _planStart;
      app.store.setGoal(goal);
      app.store.setPlan(plan);
    }
    if (withCheckin) {
      app.store.set({'checkins': [{'at': '2026-09-14T00:00:00.000Z', 'weightKg': 84.0}]});
    }
    return app;
  }

  Api api() {
    final a = Api(
        baseUrl: '', client: MockClient((_) async => http.Response('{"ok":false}', 404)));
    a.setToken('tok');
    return a;
  }

  Widget host(AppState app, Widget child) => Scope(
        state: app,
        api: api(),
        onServerChange: (_) async {},
        child: MaterialApp(theme: mbLight(), home: child),
      );

  /// 추이 화면을 세웁니다. 세로를 넉넉히 — ListView 는 보이는 카드만 만드니,
  /// 화면이 짧으면 셋째 카드의 범례를 못 세는 거짓 실패가 납니다.
  Future<void> open(WidgetTester t, AppState app) async {
    t.view.physicalSize = const Size(1000, 5000);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(host(app, Scaffold(body: ProgressScreen(go: (_, [__]) {}))));
    await t.pump(const Duration(milliseconds: 200));
  }

  List<LineChart> charts(WidgetTester t) =>
      t.widgetList<LineChart>(find.byType(LineChart)).toList();

  /* --- 점 계산 ---------------------------------------------------------------- */

  group('planSeriesPoints', () {
    final plan = <String, Object?>{
      'startDate': _planStart,
      'trajectory': [
        {'week': 0, 'weightKg': 86.7, 'smmKg': 38.0, 'pbfPct': 23.1},
        {'week': 1, 'weightKg': 86.0, 'smmKg': 38.1, 'pbfPct': 22.6},
        {'week': 2, 'weightKg': 85.3, 'smmKg': 38.2, 'pbfPct': 22.1},
      ],
    };

    test('x 는 시작일부터 7일 간격, y 는 궤적 값', () {
      final pts = planSeriesPoints(plan, 'weightKg');
      expect(pts, hasLength(3));
      expect(pts.first.x, closeTo(_days(DateTime.parse(_planStart)), 1e-9));
      for (var i = 1; i < pts.length; i++) {
        expect(pts[i].x - pts[i - 1].x, closeTo(7, 1e-9));
      }
      expect([for (final p in pts) p.y], [86.7, 86.0, 85.3]);
      expect([for (final p in planSeriesPoints(plan, 'smmKg')) p.y], [38.0, 38.1, 38.2]);
      expect([for (final p in planSeriesPoints(plan, 'pbfPct')) p.y], [23.1, 22.6, 22.1]);
    });

    test('숫자가 아닌 칸은 건너뛴다 — 없는 칸을 0 으로 그리지 않는다', () {
      final holed = <String, Object?>{
        'startDate': _planStart,
        'trajectory': [
          {'week': 0, 'weightKg': 86.7},                         // pbfPct 칸 없음
          {'week': 1, 'weightKg': null, 'pbfPct': 22.6},
          {'week': 2, 'weightKg': 'x', 'pbfPct': double.nan},
          {'week': 3, 'weightKg': 85.0, 'pbfPct': 22.0},
          'garbage',                                             // 맵이 아닌 칸
        ],
      };
      final w = planSeriesPoints(holed, 'weightKg');
      expect([for (final p in w) p.y], [86.7, 85.0]);
      expect(w.last.x - w.first.x, closeTo(21, 1e-9));           // 3주 뒤 자리 그대로
      final f = planSeriesPoints(holed, 'pbfPct');
      expect([for (final p in f) p.y], [22.6, 22.0]);
      expect(f.first.x - w.first.x, closeTo(7, 1e-9));
    });

    test('week 칸이 없으면 자리 번호가 주차 — 코어(_trajWeek)와 같은 규칙', () {
      final noWeek = <String, Object?>{
        'startDate': _planStart,
        'trajectory': [{'weightKg': 80.0}, {'weightKg': 79.5}, {'weightKg': 79.0}],
      };
      final pts = planSeriesPoints(noWeek, 'weightKg');
      expect(pts, hasLength(3));
      expect(pts[1].x - pts[0].x, closeTo(7, 1e-9));
      expect(pts[2].x - pts[0].x, closeTo(14, 1e-9));
    });

    test('시작일이나 궤적이 없으면 빈 목록', () {
      final traj = plan['trajectory'];
      expect(planSeriesPoints({'trajectory': traj}, 'weightKg'), isEmpty);
      expect(planSeriesPoints({'startDate': 'oops', 'trajectory': traj}, 'weightKg'), isEmpty);
      expect(planSeriesPoints({'startDate': _planStart}, 'weightKg'), isEmpty);
      expect(planSeriesPoints({'startDate': _planStart, 'trajectory': 'x'}, 'weightKg'), isEmpty);
    });

    test('엔진이 만든 플랜 — 궤적 점이 전부 들어가고 마지막 점은 마지막 측정 뒤', () async {
      final app = await seeded();
      final plan = (app.state['plan'] as Map).cast<String, Object?>();
      final traj = (plan['trajectory'] as List).cast<Map>();
      expect(traj.length, greaterThan(1));
      final lastScan = _days(DateTime.parse('${_scan2['measuredAt']}'));
      for (final key in ['weightKg', 'smmKg', 'pbfPct']) {
        final pts = planSeriesPoints(plan, key);
        expect(pts, hasLength(traj.length), reason: key);
        expect(pts.first.y, core.jsToNumber(traj.first[key]), reason: key);
        expect(pts.last.y, core.jsToNumber(traj.last[key]), reason: key);
        expect(pts.first.x, closeTo(_days(DateTime.parse(_planStart)), 1e-9));
        expect(pts.last.x, greaterThan(lastScan), reason: '$key — 계획선은 측정 뒤로 이어집니다');
        /* 주차 사이는 7일의 배수 — 궤적이 주를 건너뛰어도 날짜 자리는 맞아야 합니다. */
        for (var i = 1; i < pts.length; i++) {
          final dx = pts[i].x - pts[i - 1].x;
          expect(dx, greaterThan(0));
          expect(dx / 7, closeTo((dx / 7).roundToDouble(), 1e-9));
        }
      }
    });
  });

  /* --- 화면 ------------------------------------------------------------------ */

  testWidgets('추이 — 카드 셋마다 범례에 「플랜」 점선, 회색 네모 없음', (t) async {
    final app = await seeded();
    await open(t, app);
    expect(t.takeException(), isNull);
    expect(find.byType(ErrorWidget), findsNothing);
    expect(find.byType(LineChart), findsNWidgets(3));
    expect(find.text('플랜'), findsNWidgets(3));
    /* 범례의 점선 표시도 셋 — 카드마다 플랜 점선 하나. */
    expect(find.byKey(const ValueKey('legend-dashed')), findsNWidgets(3));

    /* 그래프마다: 그 카드의 실선 뒤에 플랜 점선 · 점 없음 · 계획 시작일부터 목표일까지.
       LineChart 는 모든 선으로 x·y 범위를 잡으니 마지막 점이 측정 뒤면 x축이 미래로 늘어납니다. */
    final lastScan = _days(DateTime.parse('${_scan2['measuredAt']}'));
    final list = charts(t);
    for (final (i, title) in ['체중', '골격근', '체지방률'].indexed) {
      expect([for (final s in list[i].series) s.label], [title, '플랜'], reason: title);
      expect(list[i].legend, isTrue);
      final plan = list[i].series.last;
      expect(plan.dashed, isTrue);
      expect(plan.dots, isFalse);
      expect(plan.width, 1.4);
      expect(plan.points.length, greaterThan(1));
      expect(plan.points.first.x, closeTo(_days(DateTime.parse(_planStart)), 1e-9));
      expect(plan.points.last.x, greaterThan(lastScan), reason: '$title — 계획선은 미래로');
      /* 플랜은 카드 색을 옅게 — 진한 선(실제)과 같은 색이되 구분됩니다. */
      final actual = list[i].series.first.color;
      expect(plan.color.a, lessThan(actual.a));
      expect((plan.color.r, plan.color.g, plan.color.b), (actual.r, actual.g, actual.b));
    }

    /* 「플랜」 점선 설명문은 없습니다 — 범례가 말합니다. */
    expect(find.textContaining('점선'), findsNothing);
    expect(find.text(_checkinNote), findsNothing);
  });

  testWidgets('계획이 없으면 「플랜」 도 설명도 없다', (t) async {
    final app = await seeded(withPlan: false);
    await open(t, app);
    expect(t.takeException(), isNull);
    expect(find.byType(ErrorWidget), findsNothing);
    expect(find.byType(LineChart), findsNWidgets(3));
    expect(find.text('플랜'), findsNothing);
    expect(find.textContaining('플랜'), findsNothing);
    expect(find.byKey(const ValueKey('legend-dashed')), findsNothing);
    for (final ch in charts(t)) {
      expect(ch.series, hasLength(1));
      expect(ch.legend, isFalse);              // 선이 하나면 제목이 범례입니다
    }
  });

  testWidgets('체크인이 있으면 체중 카드는 선 셋 — 체중 · 체크인 체중 · 플랜, 설명은 체크인 한 줄', (t) async {
    final app = await seeded(withCheckin: true);
    await open(t, app);
    expect(t.takeException(), isNull);
    expect(find.byType(ErrorWidget), findsNothing);
    expect(find.text('플랜'), findsNWidgets(3));
    expect(find.text('체크인 체중'), findsOneWidget);
    expect(find.byKey(const ValueKey('legend-dashed')), findsNWidgets(4));
    final weight = charts(t).first;
    expect([for (final s in weight.series) s.label], ['체중', '체크인 체중', '플랜']);
    expect(find.text(_checkinNote), findsOneWidget);
    /* 예전의 세 문장짜리 설명도, 「플랜」 점선 설명도 없습니다. */
    expect(find.textContaining('주간 체크인에 넣은'), findsNothing);
    expect(find.textContaining('점 하나로'), findsNothing);
    expect(find.textContaining('점선'), findsNothing);
  });

  testWidgets('계획 없이 체크인만 있으면 체크인 문장 하나', (t) async {
    final app = await seeded(withPlan: false, withCheckin: true);
    await open(t, app);
    expect(t.takeException(), isNull);
    expect(find.text(_checkinNote), findsOneWidget);
    expect(find.textContaining('플랜'), findsNothing);
    expect([for (final s in charts(t).first.series) s.label], ['체중', '체크인 체중']);
  });
}
