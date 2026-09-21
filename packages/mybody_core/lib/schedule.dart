/* =============================================================================
 * schedule.dart — 주간 운동 일정과 스트릭 (prototype/js/schedule.js 의 이식)
 *
 * 스트릭에는 규칙이 둘 있고 둘 다 사람을 위한 것입니다:
 *   · 쉬는 날은 안 끊습니다 (계획한 날만 셉니다).
 *   · 그런데 몇 주씩 비어 있는 것은 쉬는 날이 아닙니다 — 14일 넘게
 *     비면 거기서 끊습니다. 38일 쉬고 돌아온 사람에게 "5일 연속" 은
 *     연속이 아니라 서로 다른 두 시기입니다.
 * ========================================================================== */
library;

import 'js_num.dart';
import 'store.dart';

const List<Map<String, String>> kSchedTypes = [
  {'id': 'gym', 'label': '헬스', 'short': '헬', 'icon': '🏋️'},
  {'id': 'cardio', 'label': '유산소', 'short': '유', 'icon': '🏃'},
];

const List<String> kDow = ['월', '화', '수', '목', '금', '토', '일'];

Map<String, String>? typeOf(Object? id) {
  for (final t in kSchedTypes) {
    if (t['id'] == id) return t;
  }
  return null;
}

String labelOf(Object? id) => typeOf(id)?['label'] ?? '$id';

/// 고유번호의 #뒤 숫자로 씁니다. 화면에 몇 번째로 그려졌느냐가 아니라
/// 종목의 고유 순서라, 오늘 유산소만 남아도 유산소는 언제나 #2 입니다.
int indexOf(Object? id) {
  for (var i = 0; i < kSchedTypes.length; i++) {
    if (kSchedTypes[i]['id'] == id) return i;
  }
  return -1;
}

/// 계획한 것을 **전부** 했는가. 계획이 없는 날은 "지킬 것이 없던 날" 이지
/// 지킨 날이 아닙니다.
bool isKept(Map<String, Object?>? e) {
  final plan = e?['plan'] as List? ?? const [];
  if (plan.isEmpty) return false;
  final done = (e?['done'] as Map?) ?? const {};
  for (final t in plan) {
    if (!jsTruthy(done[t])) return false;
  }
  return true;
}

class Schedule {
  Schedule(this.store);
  final Store store;

  /// 'YYYY-MM-DD' 에 n일 더한 키.
  String shiftKey(String key, int n) {
    final d = DateTime.tryParse('${key}T00:00:00');
    if (d == null) return store.dayKey(key);
    return store.dayKey(DateTime(d.year, d.month, d.day + n));
  }

  /// 이번 주(월~일) 일곱 칸. weekStart 를 안 주면 오늘이 속한 주.
  Map<String, Object?> week([Object? weekStart]) {
    final start = jsTruthy(weekStart) ? '$weekStart' : store.weekStartOf();
    final today = store.dayKey();
    final out = <Map<String, Object?>>[];
    for (var i = 0; i < 7; i++) {
      final k = shiftKey(start, i);
      final e = store.scheduleDay(k);
      final plan = e['plan'] as List;
      final done = e['done'] as Map;
      final doneList = plan.where((t) => jsTruthy(done[t])).toList();
      final kept = isKept(e);
      out.add({
        'key': k,
        'dow': kDow[i],
        'dayNum': double.tryParse(k.substring(8, 10)) ?? double.nan,
        'isToday': k == today,
        'isPast': k.compareTo(today) < 0,
        'isFuture': k.compareTo(today) > 0,
        'plan': plan,
        'done': done,
        'doneList': doneList,
        'kept': kept,
        /* 지난 날 중 계획은 있었는데 다 못 한 날. 오늘과 앞날은 안 들어옵니다. */
        'missed': k.compareTo(today) < 0 && plan.isNotEmpty && !kept,
      });
    }
    return {'start': start, 'days': out};
  }

  /// 그 주의 한 줄 요약.
  Map<String, Object?> weekSummary([Object? weekStart]) {
    final w = week(weekStart);
    var planned = 0, kept = 0, missed = 0, open = 0;
    for (final d0 in (w['days'] as List)) {
      final d = (d0 as Map).cast<String, Object?>();
      if ((d['plan'] as List).isEmpty) continue;
      planned++;
      if (jsTruthy(d['kept'])) {
        kept++;
      } else if (jsTruthy(d['missed'])) {
        missed++;
      } else {
        open++;                       // 오늘이거나 아직 안 온 날
      }
    }
    return {
      'start': w['start'], 'plannedDays': planned, 'keptDays': kept,
      'missedDays': missed, 'openDays': open, 'days': w['days'],
    };
  }

  /// 운동 스트릭 — 계획한 날을 연달아 몇 번 지켰는가.
  Map<String, Object?> workoutStreak([Object? todayKey]) {
    final today = jsTruthy(todayKey) ? '$todayKey' : store.dayKey();
    final sch = ((store.get()['schedule'] as Map?) ?? const {}).cast<String, Object?>();
    final days = sch.keys
        .where((k) {
          final e = (sch[k] as Map?) ?? const {};
          return k.compareTo(today) <= 0 && (e['plan'] as List? ?? const []).isNotEmpty;
        })
        .toList()
      ..sort();
    final ordered = days.reversed.toList();

    final out = <String, Object?>{
      'days': 0, 'openToday': false, 'lastKept': null, 'missedAt': null,
      'everPlanned': ordered.isNotEmpty, 'staleDays': null, 'stale': false, 'last28': 0,
    };

    /* 지킨 날 사이가 14일을 넘으면 거기서 끊습니다 — 신선도와 같은 경계입니다.
       "이번 주도 지난주도 아니면 다른 시기" 하나로 설명됩니다. */
    const gapDays = 14;
    double gap(String a, String b) {
      final da = DateTime.tryParse('${a}T00:00:00');
      final db = DateTime.tryParse('${b}T00:00:00');
      if (da == null || db == null) return double.nan;
      return jsRound(
              (da.millisecondsSinceEpoch - db.millisecondsSinceEpoch) / 86400000)
          .toDouble();
    }

    String? prevKept;
    var streak = 0;
    for (final k in ordered) {
      final e = (sch[k] as Map).cast<String, Object?>();
      final kept = isKept({'plan': e['plan'] ?? const [], 'done': e['done'] ?? const {}});
      if (k == today && !kept) {
        out['openToday'] = true;
        continue;
      }
      if (!kept) {
        out['missedAt'] = k;
        break;
      }
      if (prevKept != null && gap(prevKept, k) > gapDays) break;   // 너무 오래 비었습니다
      streak++;
      prevKept = k;
      out['lastKept'] ??= k;
    }
    out['days'] = streak;

    /* 최근 28일 중 며칠 지켰는가.
       연속 숫자만 보여 주면 끊기는 날 그동안 한 일이 통째로 사라진 것처럼
       보입니다 — 사람이 앱을 닫는 지점이 정확히 거기입니다. 이 숫자는
       끊겨도 안 줄어듭니다. */
    var last28 = 0;
    for (var d = 0; d < 28; d++) {
      final kk = shiftKey(today, -d);
      final ee = (sch[kk] as Map?)?.cast<String, Object?>();
      if (ee != null &&
          isKept({'plan': ee['plan'] ?? const [], 'done': ee['done'] ?? const {}})) {
        last28++;
      }
    }
    out['last28'] = last28;

    /* 얼마나 오래된 기록인가. 숫자를 0 으로 지우지는 않습니다 — 지우면
       "네 기록은 없다" 가 되고 그건 사실이 아닙니다. 대신 며칠 지났는지를
       같이 돌려주고, 화면이 과거형으로 말합니다. */
    final lastKept = out['lastKept'];
    if (lastKept != null) {
      final a = DateTime.tryParse('${lastKept}T00:00:00');
      final b = DateTime.tryParse('${today}T00:00:00');
      final stale = (a == null || b == null)
          ? double.nan
          : jsRound((b.millisecondsSinceEpoch - a.millisecondsSinceEpoch) / 86400000)
              .toDouble();
      out['staleDays'] = stale;
      out['stale'] = stale > 14;
    }
    return out;
  }

  /// 식단 **기록** 스트릭 — 연달아 며칠 적었는가.
  /// "식단 지킴" 이 아니라 "기록" 인 것은, 이게 재는 것이 적게 먹었는지가
  /// 아니라 적었는지이기 때문입니다. 앱은 전자를 모릅니다.
  Map<String, Object?> foodStreak([Object? todayKey]) {
    final today = jsTruthy(todayKey) ? '$todayKey' : store.dayKey();
    final has = <String>{};
    for (final x in (store.get()['foodLogs'] as List? ?? const [])) {
      has.add('${(x as Map)['date']}');
    }

    var days = 0, last7 = 0;
    var openToday = false;
    var cursor = today;
    if (!has.contains(today)) {
      openToday = true;
      cursor = shiftKey(today, -1);
    }
    for (var g = 0; g < 400 && has.contains(cursor); g++) {
      days++;
      cursor = shiftKey(cursor, -1);
    }
    /* 연속이 끊긴 날에도 최근 7일 중 며칠 적었는지는 남습니다. 어제 하루
       빼먹어 연속이 0이어도 7일 중 5일이면 잘 하고 있는 겁니다. */
    for (var d = 0; d < 7; d++) {
      if (has.contains(shiftKey(today, -d))) last7++;
    }
    return {'days': days, 'openToday': openToday, 'last7': last7};
  }
}
