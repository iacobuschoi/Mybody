/* =============================================================================
 * checkins.dart — 주간 체크인 기록을 읽는 곳 (체크인 화면 · 홈 · 추이가 같이 씀)
 *
 * 체크인은 state['checkins'] 에 쌓입니다:
 *   {at, weightKg, workoutPct, dietPct, derived, status, devKg, applied}
 *
 * **주차는 계획 시작일부터 셉니다** — 체크인 화면 제목의 「계획 N주차」와 같은
 * 수입니다. 달력 주(월요일 시작)가 아닙니다. 그래서 "이번 주에 했는가" 도
 * 계획 주로 봅니다.
 *
 * 계획을 다시 세우면 그 전 체크인은 옛 계획선에 대한 것이라 판정에 안
 * 넣습니다(계획 시작일 이전 것은 뺍니다). 조정을 적용한 뒤의 기준점은
 * 코어(checkinReview)가 plan.adjustments 로 다시 잡습니다.
 * ========================================================================== */
import 'package:mybody_core/mybody_core.dart' as core;

/// 저장된 체크인, 오래된 것부터. `at` 은 전부 UTC ISO 라 글자 순서가 시간 순서입니다.
List<Map<String, Object?>> checkinsOf(Map<String, Object?> state) {
  final list = [
    for (final c in (state['checkins'] as List?) ?? const [])
      if (c is Map) c.cast<String, Object?>()
  ];
  list.sort((a, b) => '${a['at']}'.compareTo('${b['at']}'));
  return list;
}

/// 그 순간이 계획 몇 주차인가 (0부터).
int planWeekAt(core.Store store, Map<String, Object?> plan, Object? at) =>
    core.planWeekOf(plan['startDate'], store.dayKey(at));

/// 지금 계획 이후의 체크인만 (계획 시작일 당일 포함).
List<Map<String, Object?>> checkinsInPlan(core.Store store, Map<String, Object?> plan) {
  final start = '${plan['startDate']}';
  return [
    for (final c in checkinsOf(store.get()))
      if (store.dayKey(c['at']).compareTo(start) >= 0) c
  ];
}

/// 판정에 넣을 값 — [{week, weightKg, at}]. 체중이 없는 체크인도 그대로 넘기고
/// 코어가 건너뜁니다(어떤 것을 버리는지는 한 곳에서만 정합니다).
List<Map<String, Object?>> readingsFor(core.Store store, Map<String, Object?> plan) => [
      for (final c in checkinsInPlan(store, plan))
        {'week': planWeekAt(store, plan, c['at']), 'weightKg': c['weightKg'], 'at': c['at']},
    ];

/// 이번 계획 주에 한 체크인 (없으면 null). 여러 번이면 마지막 것.
Map<String, Object?>? checkinThisWeek(core.Store store) {
  final plan = store.get()['plan'];
  if (plan is! Map) return null;
  final p = plan.cast<String, Object?>();
  final now = core.planWeekOf(p['startDate'], store.dayKey());
  Map<String, Object?>? hit;
  for (final c in checkinsInPlan(store, p)) {
    if (planWeekAt(store, p, c['at']) == now) hit = c;
  }
  return hit;
}

/// 판정 이름 — 체크인 화면 · 지난 체크인 목록이 같이 씁니다.
String checkinStatusLabel(Object? status) => switch ('$status') {
      'early' => '기준 잡음',
      'onTrack' => '계획대로',
      'watch' => '지켜보는 중',
      'slow' => '느립니다',
      'fast' => '빠릅니다',
      'adherence' => '실행이 덜 됐습니다',
      _ => '',
    };
