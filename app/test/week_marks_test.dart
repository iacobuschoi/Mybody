/* =============================================================================
 * week_marks_test.dart — 요일 동그라미(DayMark)와 식단 막대의 목표선
 *
 * 색만으로는 못 읽는다는 피드백(16·17)에서 나온 것들: 지킴은 체크, 놓침은
 * ×, 오늘은 점, 쉬는 날은 옅은 점 — 달성률·홈·친구 세 화면이 같은 위젯을
 * 쓰고 범례가 한 줄 붙는지. 식단 막대는 목표선이 점선 + 「목표 149g」
 * 라벨이고, 기록 없는 날은 「·」 대신 흐린 요일 글자인지.
 * ========================================================================== */
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:mybody/src/api.dart';
import 'package:mybody/src/app_state.dart';
import 'package:mybody/src/scope.dart';
import 'package:mybody/src/screens/adherence.dart';
import 'package:mybody/src/screens/home.dart';
import 'package:mybody/src/screens/social.dart';
import 'package:mybody/src/theme.dart';
import 'package:mybody/src/ui/fmt.dart';
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

/* 서버는 없습니다 — 모든 요청에 404. */
Widget host(AppState app, Widget child, {http.Client? client}) {
  final api = Api(baseUrl: client == null ? '' : 'https://x.test',
      client: client ?? MockClient((_) async => http.Response('{"ok":false}', 404)));
  api.setToken('tok');
  return Scope(
      state: app, api: api, onServerChange: (_) async {},
      child: MaterialApp(theme: mbLight(), home: child));
}

Future<AppState> seeded({bool withPlan = true}) async {
  SharedPreferences.setMockInitialValues({});
  final app = await AppState.boot();
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

void log(AppState app, String date, double kcal, double p) => app.store.addFoodLog({
      'date': date, 'meal': '점심', 'source': 'manual',
      'items': [{'name': 'x', 'g': 100, 'kcal': kcal, 'p': p, 'c': 0, 'f': 0}],
    });

Finder mark(DayMarkState s) => find.byKey(ValueKey('daymark-${s.name}'));

/// 화면 폭을 실기기 최소(360)로 — 넘치면 예외로 잡힙니다.
void phone(WidgetTester t, {double height = 3000}) {
  t.view.physicalSize = Size(360, height);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
}

void main() {
  testWidgets('DayMark — 상태마다 키와 모양이 다르다', (t) async {
    await t.pumpWidget(MaterialApp(theme: mbLight(), home: Scaffold(
      body: Row(children: [
        for (final s in DayMarkState.values) DayMark(s),
      ]),
    )));
    for (final s in DayMarkState.values) {
      expect(mark(s), findsOneWidget, reason: '${s.name} 키');
    }
    expect(find.descendant(of: mark(DayMarkState.kept), matching: find.byIcon(LucideIcons.check)),
        findsOneWidget, reason: '지킴 = 체크');
    expect(find.descendant(of: mark(DayMarkState.missed), matching: find.byIcon(LucideIcons.x)),
        findsOneWidget, reason: '놓침 = ×');
    for (final s in [DayMarkState.today, DayMarkState.future, DayMarkState.rest]) {
      expect(find.descendant(of: mark(s), matching: find.byType(Icon)), findsNothing,
          reason: '${s.name} 에는 아이콘이 없습니다');
    }
    /* 범례용(tagged: false)은 키가 없어서 실제 칸만 셀 수 있습니다. */
    await t.pumpWidget(MaterialApp(theme: mbLight(), home: const Scaffold(
      body: DayMark(DayMarkState.kept, tagged: false),
    )));
    expect(mark(DayMarkState.kept), findsNothing);
    expect(find.byIcon(LucideIcons.check), findsOneWidget);
  });

  test('dayMarkState — 달성률·홈·친구 공유의 맵을 다 읽는다', () {
    const today = '2026-09-24';
    /* 달성률(workoutAdherence): kept/missed/open. */
    expect(dayMarkState({'key': today, 'plan': ['gym'], 'kept': false, 'missed': false, 'open': true},
        today: today), DayMarkState.today);
    expect(dayMarkState({'key': '2026-09-22', 'plan': ['gym'], 'kept': false, 'missed': true},
        today: today), DayMarkState.missed);
    /* 홈(schedule.week): done 이 Map. */
    expect(dayMarkState({'key': '2026-09-23', 'plan': ['gym'], 'done': {'gym': true}, 'kept': true,
        'missed': false}, today: today), DayMarkState.kept);
    expect(dayMarkState({'key': '2026-09-26', 'plan': ['gym'], 'done': {}, 'kept': false,
        'missed': false, 'isFuture': true}, today: today), DayMarkState.future);
    expect(dayMarkState({'key': '2026-09-23', 'plan': [], 'done': {}, 'kept': false, 'missed': false},
        today: today), DayMarkState.rest, reason: '계획 없는 날은 언제나 쉬는 날');
    expect(dayMarkState({'key': today, 'plan': [], 'done': {}}, today: today), DayMarkState.rest,
        reason: '오늘이라도 계획이 없으면 쉬는 날');
    /* 옛 친구 공유(kept 키 없음): done 이 List — 다 했을 때만 지킴. */
    expect(dayMarkState({'key': '2026-09-23', 'plan': ['gym', 'cardio'], 'done': ['gym']},
        today: today), DayMarkState.missed);
    expect(dayMarkState({'key': '2026-09-23', 'plan': ['gym', 'cardio'], 'done': ['gym', 'cardio']},
        today: today), DayMarkState.kept);
    expect(dayMarkState({'key': today, 'plan': ['gym'], 'done': []}, today: today),
        DayMarkState.today);
    expect(dayMarkState({'key': '2026-09-25', 'plan': ['gym'], 'done': []}, today: today),
        DayMarkState.future);
  });

  testWidgets('달성률 — 요일 줄에 지킴·놓침·오늘 표시와 범례, 월간도 같은 표시', (t) async {
    phone(t, height: 6000);
    final app = await seeded(withPlan: false);
    final today = app.store.dayKey();
    final y1 = app.schedule.shiftKey(today, -1), y2 = app.schedule.shiftKey(today, -2);
    app.store.setSchedulePlan(y1, 'gym', true);
    app.store.setScheduleDone(y1, 'gym', true);
    app.store.setSchedulePlan(y2, 'gym', true);
    app.store.setSchedulePlan(today, 'gym', true);

    await t.pumpWidget(host(app, AdherenceScreen(go: (_, [__]) {})));
    await t.pump(const Duration(milliseconds: 200));
    expect(t.takeException(), isNull);
    expect(mark(DayMarkState.kept), findsOneWidget);
    expect(mark(DayMarkState.missed), findsOneWidget);
    expect(mark(DayMarkState.today), findsOneWidget);
    expect(mark(DayMarkState.rest), findsNWidgets(4));
    expect(mark(DayMarkState.future), findsNothing, reason: '최근 7일에 앞날은 없습니다');
    expect(find.descendant(of: mark(DayMarkState.kept), matching: find.byIcon(LucideIcons.check)),
        findsOneWidget);
    expect(find.descendant(of: mark(DayMarkState.missed), matching: find.byIcon(LucideIcons.x)),
        findsOneWidget);
    /* 범례 한 줄 — 글자는 RichText 라 findRichText 로 찾습니다. 화면 제목
       「오늘」 을 세는 다른 테스트와 겹치지 않게 한 것입니다. */
    final legend = find.byKey(const ValueKey('daymark-legend'));
    expect(legend, findsOneWidget);
    for (final label in ['지킴', '놓침', '오늘', '쉬는 날']) {
      expect(find.descendant(of: legend, matching: find.text(label, findRichText: true)),
          findsOneWidget, reason: '범례 $label');
      expect(find.text(label), findsNothing, reason: '범례 글자는 find.text 에 안 잡힙니다');
    }

    await t.tap(find.text('월간'));
    await t.pump(const Duration(milliseconds: 200));
    expect(t.takeException(), isNull);
    expect(mark(DayMarkState.kept), findsOneWidget);
    expect(mark(DayMarkState.missed), findsOneWidget);
    expect(mark(DayMarkState.today), findsOneWidget);
    expect(mark(DayMarkState.rest), findsNWidgets(27));
    expect(find.byKey(const ValueKey('daymark-legend')), findsOneWidget);
  });

  testWidgets('식단 막대 — 「목표 149g」 라벨이 선 끝에, 빈 날은 「·」 대신 흐린 요일', (t) async {
    phone(t, height: 6000);
    final app = await seeded();
    final today = app.store.dayKey();
    final macros = ((app.state['plan'] as Map)['macros'] as Map).cast<String, Object?>();
    final p = core.jsToNumber(macros['proteinG']);
    final kcal = core.jsToNumber(macros['intakeKcal']);
    log(app, today, kcal * 1.5, p * 0.5);   // 오늘만 기록 — 칼로리는 목표 위, 단백질은 아래

    await t.pumpWidget(host(app, AdherenceScreen(go: (_, [__]) {})));
    await t.pump(const Duration(milliseconds: 200));
    expect(t.takeException(), isNull, reason: '360px 에서 넘치지 않습니다');
    expect(find.text('목표 ${n0(p)}g'), findsOneWidget, reason: '단백질 목표선 라벨');
    expect(find.text('목표 ${n0(kcal)}kcal'), findsOneWidget, reason: '칼로리 목표선 라벨');
    expect(find.text('목표 ${n0(macros['carbG'])}g'), findsOneWidget);
    expect(find.text('목표 ${n0(macros['fatG'])}g'), findsOneWidget);
    expect(find.text('·'), findsNothing, reason: '빈 날에 점을 찍지 않습니다');

    /* 어제(기록 없음)의 요일 글자: 운동 줄에 1개(보통 색) + 식단 카드 4개(흐림). */
    final yDow = core.kDow[(DateTime.parse('${app.schedule.shiftKey(today, -1)}T00:00:00').weekday - 1) % 7];
    final faded = t.widgetList<Text>(find.text(yDow))
        .where((w) => (w.style?.color?.a ?? 1) < 0.5)
        .length;
    expect(faded, 4, reason: '식단 카드 넷 다 어제를 흐리게');
    /* 오늘(기록 있음)의 요일 글자는 흐리지 않습니다. */
    final tDow = core.kDow[(DateTime.parse('${today}T00:00:00').weekday - 1) % 7];
    final fadedToday = t.widgetList<Text>(find.text(tDow))
        .where((w) => (w.style?.color?.a ?? 1) < 0.5)
        .length;
    expect(fadedToday, 0);
    /* 요약은 숫자 한 줄 — 「평균 …g · 목표의 …%」. */
    expect(find.textContaining('· 목표의 '), findsNWidgets(4));
  });

  testWidgets('홈 — 이번 주 칸마다 DayMark, 아래 범례 한 줄', (t) async {
    phone(t, height: 2600);
    final app = await seeded();
    final today = app.store.dayKey();
    app.store.setSchedulePlan(today, 'gym', true);
    final days = ((app.schedule.week()['days'] as List)).cast<Map<String, Object?>>();
    final past = days.where((d) => d['isPast'] == true).map((d) => '${d['key']}').toList();
    final future = days.where((d) => d['isFuture'] == true).map((d) => '${d['key']}').toList();
    if (past.isNotEmpty) {
      app.store.setSchedulePlan(past.first, 'gym', true);
      app.store.setScheduleDone(past.first, 'gym', true);
    }
    if (past.length > 1) app.store.setSchedulePlan(past.last, 'cardio', true);
    if (future.isNotEmpty) app.store.setSchedulePlan(future.first, 'gym', true);

    await t.pumpWidget(host(app, Scaffold(body: HomeScreen(go: (_, [__]) {}))));
    await t.pump(const Duration(milliseconds: 200));
    expect(t.takeException(), isNull);
    expect(find.text('이번 주 운동'), findsOneWidget);
    expect(find.byKey(const ValueKey('daymark-legend')), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w is DayMark && w.tagged), findsNWidgets(7));
    expect(mark(DayMarkState.today), findsOneWidget);
    expect(mark(DayMarkState.kept), past.isEmpty ? findsNothing : findsOneWidget);
    expect(mark(DayMarkState.missed), past.length > 1 ? findsOneWidget : findsNothing);
    expect(mark(DayMarkState.future), future.isEmpty ? findsNothing : findsOneWidget);
    /* 운동 종류 점은 그대로 아래에 — 오늘 칸에 헬스 점 하나. */
    expect(find.byIcon(LucideIcons.check), findsNWidgets(past.isEmpty ? 1 : 2),
        reason: '범례의 체크 + 지킨 날의 체크');
  });

  testWidgets('친구 — 주간 카드도 같은 DayMark 와 범례', (t) async {
    phone(t, height: 4000);
    SharedPreferences.setMockInitialValues({});
    final app = await AppState.boot();
    final today = app.store.dayKey();
    String k(int n) => app.schedule.shiftKey(today, n);
    Map<String, Object?> day(String key, List<String> plan, List<String> done, {bool missed = false}) =>
        {'key': key, 'dow': '?', 'dayNum': int.parse(key.substring(8)), 'plan': plan, 'done': done,
         'kept': plan.isNotEmpty && plan.every(done.contains), 'missed': missed};
    final row = {
      'weekStart': k(-3), 'plannedDays': 4, 'keptDays': 1, 'missedDays': 1, 'openDays': 2,
      'week': {'start': k(-3), 'days': [
        day(k(-3), ['gym'], ['gym']),
        day(k(-2), [], []),
        day(k(-1), ['gym', 'cardio'], ['gym'], missed: true),
        day(k(0), ['gym'], []),
        day(k(1), ['cardio'], []),
        day(k(2), [], []),
        day(k(3), [], []),
      ]},
    };
    const shareKeys = ['weightTrend', 'smmTrend', 'bfmTrend', 'planProgress', 'streak',
        'schedule', 'absolute', 'diet'];
    final client = MockClient((req) async {
      final path = req.url.path;
      if (path.endsWith('/share/f1')) {
        return http.Response(jsonEncode({'ok': true,
            'share': {for (final s in shareKeys) s: s == 'schedule'}}), 200);
      }
      if (path.contains('/snapshots/f1')) {
        return http.Response.bytes(utf8.encode(jsonEncode({'ok': true, 'rows': [row]})), 200,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }
      return http.Response('{"ok":false}', 404);
    });
    await t.pumpWidget(host(app, const FriendDetailScreen(
        person: {'id': 'f1', 'displayName': '나린', 'handle': 'narin'}), client: client));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(find.text('이번 주 운동'), findsOneWidget);
    expect(find.byKey(const ValueKey('daymark-legend')), findsOneWidget);
    expect(mark(DayMarkState.kept), findsOneWidget);
    expect(mark(DayMarkState.missed), findsOneWidget);
    expect(mark(DayMarkState.today), findsOneWidget);
    expect(mark(DayMarkState.future), findsOneWidget);
    expect(mark(DayMarkState.rest), findsNWidgets(3));
  });
}
