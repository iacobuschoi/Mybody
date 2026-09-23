/* =============================================================================
 * adherence.dart — 달성률: 일정과 식단 기록에서 "얼마나 지켰나" 를 셉니다.
 *
 * 예전에는 주간 체크인에서 사람이 슬라이더로 적었습니다. 그런데 운동은
 * 홈에서 매일 체크하고 식단은 끼니마다 적으므로, 이미 있는 기록에서 세는
 * 편이 맞습니다 — 잘 보이려고 높게 찍을 일도 없고, 두 번 묻지도 않습니다.
 *
 * 분모를 반드시 씁니다. 기록 없는 날을 0으로 치면 안 적은 사람이 안 지킨
 * 사람이 됩니다. 운동은 "계획한 날" 만, 식단은 "기록한 날" 만 셉니다.
 * ========================================================================== */
import 'package:mybody_core/mybody_core.dart' as core;
import 'package:mybody_core/schedule.dart' show isKept;

/// 식단 판정에 필요한 최소 기록 일수. 이보다 적으면 "모른다" 고 답합니다 —
/// 하루 적고 100% 라고 말하는 것은 숫자가 아니라 우연입니다.
const int kMinLoggedDays = 3;

DateTime _base(core.Store store) =>
    DateTime.tryParse('${store.dayKey()}T00:00:00') ?? DateTime.now();

/// 최근 n일의 식단 하루 합계, 오래된 날부터. core.dietAdherence 에 그대로 넣습니다.
List<Map<String, Object?>> dietDays(core.Store store, int n) {
  final today = _base(store);
  return [
    for (var i = n - 1; i >= 0; i--)
      () {
        final key = store.dayKey(DateTime(today.year, today.month, today.day - i));
        final tt = store.dayTotals(key);
        return <String, Object?>{
          'date': key, 'logged': tt['logged'], 'kcal': tt['kcal'],
          'p': tt['p'], 'c': tt['c'], 'f': tt['f'],
        };
      }(),
  ];
}

/// 최근 n일의 운동 실행도.
///
/// pct 는 **판정이 끝난 날** 만으로 냅니다 — 지킨 날 / (지킨 날 + 놓친 날).
/// 오늘 아직 안 한 것은 놓친 게 아니라 열린 것이라 분모에 안 들어갑니다.
/// 계획한 날이 하나도 없으면 pct 는 null 입니다 ("0%" 가 아닙니다).
Map<String, Object?> workoutAdherence(core.Store store, int n) {
  final today = store.dayKey();
  final base = _base(store);
  final days = <Map<String, Object?>>[];
  var planned = 0, kept = 0, missed = 0, open = 0;
  final byType = <String, Map<String, int>>{};
  for (var i = n - 1; i >= 0; i--) {
    final d = DateTime(base.year, base.month, base.day - i);
    final k = store.dayKey(d);
    final e = store.scheduleDay(k);
    final plan = (e['plan'] as List).cast<Object?>();
    final done = e['done'] as Map;
    final isToday = k == today;
    final wasKept = isKept(e);
    final wasMissed = !wasKept && plan.isNotEmpty && !isToday;
    final isOpen = !wasKept && plan.isNotEmpty && isToday;
    if (plan.isNotEmpty) planned++;
    if (wasKept) {
      kept++;
    } else if (wasMissed) {
      missed++;
    } else if (isOpen) {
      open++;
    }
    for (final t in plan) {
      final b = byType.putIfAbsent('$t', () => {'planned': 0, 'done': 0});
      b['planned'] = b['planned']! + 1;
      if (core.jsTruthy(done[t])) b['done'] = b['done']! + 1;
    }
    days.add({
      'key': k, 'dow': core.kDow[(d.weekday - 1) % 7], 'isToday': isToday,
      'plan': plan, 'kept': wasKept, 'missed': wasMissed, 'open': isOpen,
    });
  }
  final judged = kept + missed;
  return {
    'totalDays': n, 'plannedDays': planned, 'keptDays': kept,
    'missedDays': missed, 'openDays': open,
    'pct': judged == 0 ? null : (kept / judged * 100).round(),
    'days': days, 'byType': byType,
  };
}

/// 주간 체크인이 쓰는 "지난 7일 실행" — 운동과 식단 한 벌.
///
/// dietPct 는 달성률 화면의 「범위 안」 과 같은 숫자입니다 (기록한 날 중
/// 칼로리가 목표 ±10% 안에 든 날의 비율). 화면마다 다른 숫자를 보여 주면
/// 어느 쪽이 진짜냐고 묻게 됩니다. 기록이 kMinLoggedDays 보다 적거나 목표가
/// 없으면 null — 엔진은 그때 순응도 없이(체중만으로) 판단합니다.
Map<String, Object?> weekExecution(core.Store store, {int days = 7}) {
  final w = workoutAdherence(store, days);
  final plan = store.get()['plan'];
  final m = plan is Map ? plan['macros'] : null;
  final target = m is Map ? m.cast<String, Object?>() : null;
  final dd = dietDays(store, days);
  final adh = core.dietAdherence(dd, target);
  /* 기록 일수는 목표가 없어도 셉니다 — "목표가 없어서 못 봤다" 와
     "안 적어서 못 봤다" 는 화면에서 다른 말입니다. */
  final logged = dd.where((d) => core.jsTruthy(d['logged'])).length;
  final inBand = adh == null ? 0 : core.jsToNumber(adh['inBandDays']).toInt();
  final dietPct = (adh == null || logged < kMinLoggedDays)
      ? null
      : core.jsToNumber(adh['inBandPct']).round();
  return {
    'days': days,
    'workoutPct': w['pct'],
    'plannedDays': w['plannedDays'], 'keptDays': w['keptDays'],
    'missedDays': w['missedDays'], 'openDays': w['openDays'],
    'dietPct': dietPct, 'loggedDays': logged, 'inBandDays': inBand,
    'hasTarget': target != null, 'minLoggedDays': kMinLoggedDays,
  };
}
