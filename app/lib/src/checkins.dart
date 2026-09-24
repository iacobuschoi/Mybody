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

/// 판정에 넣을 값 — [{week, day, weightKg, at}]. day 는 계획 시작일로부터 며칠째인지 —
/// 코어가 계획선을 그날 자리에서 읽습니다(주 단위로 자르면 요일 차이가 가짜 차이가 됩니다).
/// 체중이 없는 체크인도 그대로 넘기고 코어가 건너뜁니다(버리는 규칙은 한 곳에서만).
List<Map<String, Object?>> readingsFor(core.Store store, Map<String, Object?> plan) => [
      for (final c in checkinsInPlan(store, plan))
        {
          'week': planWeekAt(store, plan, c['at']),
          'day': core.planDayOf(plan['startDate'], store.dayKey(c['at'])),
          'weightKg': c['weightKg'],
          'at': c['at'],
        },
    ];

/// 판정이 "같은 체크인" 으로 묶는 간격 — 코어(checkinReview)의 5일과 같습니다.
const int kCheckinMergeDays = 5;

/// 이번 주 체크인을 이미 했는가 — 같은 계획 주이거나 **5일 안**이면 했다고 봅니다.
/// 계획 주만 보면, 일요일에 하고 월요일(다음 계획 주)에 또 하라고 불렀습니다.
/// 코어는 5일 안의 두 값을 하나로 묶으니, 불러 봐야 앞의 값을 덮을 뿐입니다.
Map<String, Object?>? checkinThisWeek(core.Store store) {
  final plan = store.get()['plan'];
  if (plan is! Map) return null;
  final p = plan.cast<String, Object?>();
  final today = store.dayKey();
  final nowWeek = core.planWeekOf(p['startDate'], today);
  final nowDay = core.planDayOf(p['startDate'], today);
  Map<String, Object?>? hit;
  for (final c in checkinsInPlan(store, p)) {
    final k = store.dayKey(c['at']);
    if (core.planWeekOf(p['startDate'], k) == nowWeek ||
        nowDay - core.planDayOf(p['startDate'], k) < kCheckinMergeDays) {
      hit = c;
    }
  }
  return hit;
}

/// 판정 이름 — 체크인 화면 · 지난 체크인 목록이 같이 씁니다.
String checkinStatusLabel(Object? status) => switch ('$status') {
      'early' => '기준 잡음',
      'collecting' => '모으는 중',
      'onTrack' => '계획대로',
      'watch' => '지켜보는 중',
      'slow' => '느립니다',
      'fast' => '빠릅니다',
      'heavy' => '무겁습니다',
      'light' => '가볍습니다',
      'adherence' => '실행이 덜 됐습니다',
      _ => '',
    };

/// 넣은 체중이 말이 되는가 — 862 처럼 소수점을 빠뜨린 값이 기준점으로 한 번
/// 들어가면 그 뒤 판정이 전부 틀어집니다. 괜찮으면 null.
///
/// 견주는 값은 **날짜가 가장 최근인 것** — 마지막 체크인과 최근 인바디 중에서.
/// 오래된 체크인과 견주면, 몇 달 동안 실제로 10kg 을 뺀 사람의 맞는 체중을 막았습니다.
/// 허용 폭도 시간이 지난 만큼 넓힙니다(15% + 주당 1%, 최대 40%).
String? checkinWeightProblem(core.Store store, double? w) {
  if (w == null) return null;
  if (!w.isFinite) return '숫자로 넣어 주세요';
  if (w < 20 || w > 300) return '20~300kg 사이로 넣어 주세요';
  double? ref;
  DateTime? refAt;
  for (final c in checkinsOf(store.get()).reversed) {
    final cw = c['weightKg'];
    final at = DateTime.tryParse('${c['at']}');
    if (cw is num && cw >= 20 && cw <= 300 && at != null) {
      ref = cw.toDouble();
      refAt = at;
      break;
    }
  }
  final scans = store.sortedScans();
  if (scans.isNotEmpty) {
    final sw = core.jsToNumber(scans.last['weightKg']);
    final sat = DateTime.tryParse('${scans.last['measuredAt']}');
    if (sw >= 20 && sw <= 300 && sat != null && (refAt == null || sat.isAfter(refAt))) {
      ref = sw;
      refAt = sat;
    }
  }
  if (ref == null || refAt == null) return null;
  final weeks = DateTime.now().difference(refAt).inDays / 7;
  final tol = (0.15 + 0.01 * (weeks < 0 ? 0 : weeks)).clamp(0.15, 0.40);
  if ((w - ref).abs() / ref > tol) {
    return '지난 기록(${core.toFixed(ref, 1)}kg)과 너무 많이 다릅니다 — 숫자를 확인해 주세요';
  }
  return null;
}
