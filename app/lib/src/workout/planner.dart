/* =============================================================================
 * planner.dart — 엔진의 세션을 내 자리에 맞게 고칩니다
 *
 * 엔진(engine.workoutFor)은 부위와 세트·반복을 정하고 종목은 풀에서 앞에서부터
 * 집습니다. 그 풀에는 바벨과 머신이 섞여 있어서, 집에서 하는 사람이나 머신이
 * 두 대뿐인 동네 헬스장에서는 계획의 반이 "할 수 없는 것" 이 됩니다.
 *
 * 여기서는 종목을 바꾸고, 정해진 종목에 세트 · 횟수 · 쉬는 시간을 다시 매깁니다
 * (scheme.dart). 엔진의 5-8 / 10-15 두 칸은 맨몸 스쿼트에 바벨 규칙을 붙였고
 * 플랭크에 「10-15회」 를 붙였습니다(3차 피드백 31) — 종목이 정해진 뒤에 기구 ·
 * 움직임 · 경력 · 목표로 숫자를 정해야 맞습니다. RPE 와 순서는 엔진 그대로.
 * 마지막에 세션 시간(minutes)을 넘으면 쉬는 시간만 줄입니다. 같은 입력이면
 * 언제나 같은 답입니다 (무작위 없음).
 *
 * 화면은 tailorSession 을 직접 부르지 않고 [tailorSessionFor] 로 옵니다 — 프로필의
 * 경력과 플랜의 국면을 여기서 한 번 읽어 넘깁니다. 플랜 탭과 헬스 화면이 각자
 * 읽으면 한쪽만 초보 숫자가 되는 날이 옵니다(3차 리뷰).
 * ========================================================================== */
library;

import 'exercises.dart';
import 'prefs.dart';
import 'scheme.dart';

/// 대체한 종목의 메모 앞머리. 화면이 "원래 무엇이었나" 를 이걸로 보여 줍니다.
const String kSubstitutePrefix = '대체: 원래 ';
const String kFamiliarPrefix = '익숙한 종목: 원래 ';
/// 대체할 것이 없어 그대로 둘 때.
const String kSkipNote = '기구가 없으면 건너뛰기';

/// 종목마다 흔들리지 않는 'id' 를 답니다 — 사전에 있으면 그 번호, 없으면
/// 이름에서 만든 것. 화면의 체크 상태가 이 값에 매달립니다.
List<Map<String, Object?>> withIds(List exercises) => [
      for (final x in exercises)
        if (x is Map) _withId(x.cast<String, Object?>()),
    ];

Map<String, Object?> _withId(Map<String, Object?> e) {
  final out = Map<String, Object?>.of(e);
  final id = out['id'];
  if (id is String && id.isNotEmpty) return out;
  final name = '${out['name'] ?? ''}';
  out['id'] = exerciseByName(name)?.id ?? slugOf(name);
  return out;
}

/* --- 프로필 · 플랜에서 스킴의 두 축 ------------------------------------------
 *
 * scheme.dart 는 경력(trainingAge)과 목표(goalKind)로 숫자를 고릅니다. 그 둘을
 * state 에서 읽는 곳은 여기 하나 — 플랜 탭 · 헬스 화면 · 「종목 추가」 · 플랜 없는
 * 날의 기본 종목이 전부 같은 값을 써야 두 화면의 세트 수가 어긋나지 않습니다.
 * -------------------------------------------------------------------------- */

/// 프로필의 경력 — 'novice' · 'intermediate' · 'advanced'. 없으면 초보(보수적).
String trainingAgeOf(Map<String, Object?> state) {
  final profile = state['profile'];
  final ta = profile is Map ? profile['trainingAge'] : null;
  return ta is String && ta.isNotEmpty ? ta : 'novice';
}

/// 지금 국면 — 플랜의 phases 에서 [dateKey] 가 든 단계의 'cut' · 'bulk' · 'maintain'.
/// 플랜이 끝난 뒤면 마지막 단계, 플랜이나 단계가 없으면 ''. 저장된 플랜에는 goalInfo 가
/// 없어서(setPlan 이 남기는 키에 없음) 단계표가 "지금 뭘 하는 중인가" 의 유일한 답입니다 —
/// 분할 전략(감량 → 증량)에서는 증량 주에만 바벨 복합이 근력 구간으로 갑니다.
String goalKindOf(Map<String, Object?> state, String dateKey) {
  final plan = state['plan'];
  if (plan is! Map) return '';
  final phases = plan['phases'];
  if (phases is! List || phases.isEmpty) return '';
  final week = _planWeekOf(plan['startDate'], dateKey);
  String? last;
  for (final p in phases) {
    if (p is! Map) continue;
    final kind = p['phase'];
    if (kind is! String || kind.isEmpty) continue;
    last = kind;
    final from = _int(p['from']) ?? 0, to = _int(p['to']);
    if (week >= from && (to == null || week < to)) return kind;
  }
  return last ?? '';
}

/// 'YYYY-MM-DD' 둘 사이의 계획 주차(0부터, 시작 전은 0) — 엔진 planWeekOf 와 같은 셈.
int _planWeekOf(Object? startKey, String dateKey) {
  final a = DateTime.tryParse('${startKey ?? ''}T00:00:00Z');
  final b = DateTime.tryParse('${dateKey}T00:00:00Z');
  if (a == null || b == null) return 0;
  final days = b.difference(a).inDays;
  return days <= 0 ? 0 : days ~/ 7;
}

/// 화면이 부르는 [tailorSession] — 프로필의 경력과 [dateKey] 의 국면을 채워서.
List<Map<String, Object?>> tailorSessionFor(
        Map<String, Object?> state, Map<String, Object?> session, GymPrefs prefs,
        {required String dateKey}) =>
    tailorSession(session, prefs,
        trainingAge: trainingAgeOf(state), goalKind: goalKindOf(state, dateKey));

/// 사전 종목 하나를 계획 줄로 — 세트 · 횟수(또는 초) · 휴식 · 편측을 스킴으로 채워서.
/// 「종목 추가」 와 플랜 없는 날의 기본 종목이 씁니다. 엔진 힌트가 없으니 사전이 답이고,
/// 세션 예산(fitRestToBudget)은 여기서 안 합니다 — 세션 minutes 가 없습니다.
Map<String, Object?> schemeRowFor(Exercise e, {required String trainingAge, required String goalKind}) {
  final m = <String, Object?>{
    'id': e.id, 'name': e.name, 'group': e.group, 'equip': e.equip, 'note': e.note,
  };
  final s = schemeFor(
    exercise: e,
    name: e.name,
    equip: e.equip,
    pattern: e.pattern,
    goalKind: goalKind,
    trainingAge: trainingAge,
    isCompound: false,
  );
  return _applyScheme(m, s);
}

/* --- 메모 읽기 ----------------------------------------------------------------
 *
 * tailorSession 이 남기는 메모는 '대체: 원래 바벨 벤치프레스 · 요령' 모양의
 * 엔진 내부 글입니다. 화면은 이 세 함수로 읽습니다 — 플랜 탭도 헬스 화면도
 * 같은 규칙이어야 한쪽에만 「대체: 원래 …」 가 새어 나가지 않습니다.
 * -------------------------------------------------------------------------- */

/// 종목에 붙는 표. 대체됐으면 '대체', 잘 아는 종목으로 바꿨으면 '익숙', 아니면 null.
String? tailorTag(Map<String, Object?> e) {
  final note = '${e['note'] ?? ''}';
  if (note.startsWith(kFamiliarPrefix)) return '익숙';
  if (note.startsWith(kSubstitutePrefix)) return '대체';
  return null;
}

/// 종목 밑 한 줄. 바꾼 종목이면 「원래 X · 요령」, 아니면 엔진의 요령 그대로.
/// [original] 을 끄면 「원래 X」 를 빼고 요령만 — 설정을 안 만진 초보 프리셋에서는
/// 사용자 관점의 "원래" 가 없어서, 그 말은 정보가 아니라 "내 플랜이 어긋났나" 입니다.
String? tailorNote(Map<String, Object?> e, {bool original = true}) {
  var note = '${e['note'] ?? ''}';
  for (final p in [kFamiliarPrefix, kSubstitutePrefix]) {
    if (!note.startsWith(p)) continue;
    final rest = note.substring(p.length);
    if (original) {
      note = '원래 $rest';
    } else {
      /* _Row.replace 가 '$원래 이름 · $요령' 으로 붙였습니다 — 첫 ' · ' 앞이 이름. */
      final cut = rest.indexOf(' · ');
      note = cut < 0 ? '' : rest.substring(cut + 3);
    }
    break;
  }
  return note.isEmpty ? null : note;
}

/// Adapts one engine session to the person's gym. Pure and deterministic.
///
/// 규칙 (위에서부터 차례로):
///  1. 기구가 없는 종목은 같은 부위의 되는 종목으로 — 잘 아는 것 > 같은
///     움직임 > (헬스장에서 머신 자리가 남으면) 머신 > (집에서는) 맨몸 > 나머지,
///     같으면 사전 순서. 메모에 '대체: 원래 X' — 들어온 것이 잘 아는 종목이면
///     '익숙한 종목: 원래 X'. 화면의 「익숙」 표는 "왜 이 종목인가" 의 답이지
///     몇 번째 규칙으로 들어왔나가 아닙니다.
///  2. machineCount 가 있으면 머신·케이블은 앞에서부터 그 개수까지만 두고
///     나머지는 프리웨이트·맨몸으로. 메모는 1 과 같은 규칙.
///  3. 잘 아는 종목이 같은 부위에 있으면 하나 바꿔 넣습니다. 부위마다 한 번만 —
///     아는 것만 남으면 계획이 늘 같아집니다.
///  4. 바벨이 없는 헬스장에서 machineCount 에 자리가 남으면 프리웨이트·맨몸 줄을
///     같은 움직임의 머신으로 올립니다(앞에서부터, 잘 아는 종목은 두고). 바벨이
///     없으면 머신이 주된 종목이고, 「하루에 쓸 머신 수」 는 그때 한도가 아니라
///     목표입니다 — 초보 프리셋의 약속이 "머신 4개 + 덤벨" 입니다(2차 피드백 15).
///  5. 같은 종목은 두 번 나오지 않습니다. 바꿀 것이 없으면 원래 것을 두고
///     '기구가 없으면 건너뛰기' 를 답니다.
///  6. 정해진 종목마다 스킴(scheme.dart)을 매깁니다 — 'sets' · 'reps' · 'restSec' 를
///     덮어쓰고, 시간으로 하는 종목은 'seconds' 를 넣고 'reps' 는 ''. 'perSide' ·
///     'why' 를 더합니다. [trainingAge] 는 프로필의 경력(novice · intermediate ·
///     advanced), [goalKind] 는 목표('cut' · 'bulk' · 'recomp' · '') — 호출부가
///     안 넘기면 초보 · 목표 없음으로 봅니다.
///  7. 세트 × (동작 + 휴식) 의 합이 session['minutes'] 를 넘으면 휴식을 비례로 줄입니다
///     (바닥 [kMinRestSec]). 동작 시간은 없는 것이라 줄일 수 없고, 세트를 빼면 볼륨이
///     빠지니까요.
List<Map<String, Object?>> tailorSession(Map<String, Object?> session, GymPrefs prefs,
    {String trainingAge = 'novice', String goalKind = ''}) {
  final raw = session['exercises'];
  if (raw is! List || raw.isEmpty || session['rest'] == true) return const [];

  final rows = <_Row>[
    for (final x in raw)
      if (x is Map) _Row(x.cast<String, Object?>()),
  ];
  final used = <String>{for (final r in rows) r.id};
  final cap = prefs.machineCount;
  final atGym = !prefs.isHome;

  bool available(Exercise e) =>
      (e.equip == 'bodyweight' || prefs.equipment.contains(e.equip)) &&
      !(e.needsBar && prefs.isHome);

  int machines() => rows.where((r) => r.isMachine).length;

  /// 헬스장이고 머신 자리가 남았는가 — 그때는 같은 움직임의 머신을 먼저 권합니다.
  bool machineRoom() => atGym && (cap == null || machines() < cap);

  /// 바꿔 넣은 것이 잘 아는 종목이면 「익숙」, 아니면 「대체」.
  String prefixFor(Exercise alt) =>
      prefs.familiar.contains(alt.id) ? kFamiliarPrefix : kSubstitutePrefix;

  void swap(_Row r, Exercise alt) {
    used.remove(r.id);
    r.replace(alt, prefixFor(alt));
    used.add(r.id);
  }

  /* 1. 기구가 없는 종목을 바꿉니다. */
  for (final r in rows) {
    if (r.available(prefs)) continue;
    final alt = _bestAlternative(r, prefs, used, available, preferMachine: machineRoom());
    if (alt == null) {
      r.markSkip();
    } else {
      swap(r, alt);
    }
  }

  /* 2. 머신 개수 제한 — 앞에서부터 셉니다. 앞이 보통 주된 종목입니다. */
  if (cap != null) {
    var n = 0;
    for (final r in rows) {
      if (!r.isMachine) continue;
      if (n < cap) {
        n++;
        continue;
      }
      final alt = _bestAlternative(r, prefs, used, (e) => available(e) && !e.isMachine);
      if (alt == null) {
        r.markSkip();
      } else {
        swap(r, alt);
      }
    }
  }

  /* 3. 잘 아는 종목을 하나씩 넣습니다. */
  if (prefs.familiar.isNotEmpty) {
    final familiar = <Exercise>[];
    for (final id in prefs.familiar) {
      final e = exerciseById(id);
      if (e != null) familiar.add(e);
    }
    final groups = <String>[];
    for (final r in rows) {
      if (!groups.contains(r.group)) groups.add(r.group);
    }
    for (final g in groups) {
      final inGroup = rows.where((r) => r.group == g).toList();
      if (inGroup.any((r) => prefs.familiar.contains(r.id))) continue;   // 이미 하나 있습니다
      var swapped = false;
      for (final f in familiar) {
        if (swapped) break;
        if (f.group != g || used.contains(f.id) || !available(f)) continue;
        /* 같은 움직임인 것을 먼저, 없으면 뒤쪽(보조 종목)을 바꿉니다 —
           첫 종목은 대개 그 날의 주된 복합 운동입니다. */
        _Row? target;
        for (final r in inGroup) {
          if (r.pattern.isNotEmpty && r.pattern == f.pattern) target = r;
        }
        target ??= inGroup.last;
        if (f.isMachine && !target.isMachine && cap != null && machines() >= cap) {
          continue;                                     // 머신 자리가 없습니다
        }
        used.remove(target.id);
        target.replace(f, kFamiliarPrefix);
        used.add(target.id);
        swapped = true;
      }
    }
  }

  /* 4. 바벨 없는 헬스장 — 남은 머신 자리를 같은 움직임의 머신으로 채웁니다.
     잘 아는 종목(3 에서 넣은 것 · 원래 있던 것)은 건드리지 않습니다. */
  if (atGym && cap != null && !prefs.equipment.contains('barbell')) {
    for (final r in rows) {
      if (machines() >= cap) break;
      if (r.isMachine || prefs.familiar.contains(r.id)) continue;
      final alt = _bestAlternative(
          r, prefs, used, (e) => available(e) && e.isMachine && e.pattern == r.pattern);
      if (alt != null) swap(r, alt);
    }
  }

  /* 6. 종목이 정해졌으니 숫자를 매깁니다. 엔진의 sets · reps · restSec 는 힌트로 넘깁니다. */
  final out = [
    for (final r in rows) _withScheme(r, trainingAge: trainingAge, goalKind: goalKind),
  ];

  /* 7. 세션 예산. */
  fitRestToBudget(out, session['minutes']);
  return out;
}

Map<String, Object?> _withScheme(_Row r, {required String trainingAge, required String goalKind}) {
  final m = r.toMap();
  final engineSets = _int(m['sets']);
  final engineRest = _int(m['restSec']);
  final engineReps = m['reps'] == null ? null : '${m['reps']}';
  final s = schemeFor(
    exercise: r.lib,
    name: r.name,
    equip: r.equip,
    pattern: r.pattern,
    goalKind: goalKind,
    trainingAge: trainingAge,
    /* 엔진은 복합에만 5-8 · 150초를 줍니다 — 그 표식이 "복합" 의 뜻입니다. */
    isCompound: engineReps == '5-8' || (engineRest != null && engineRest >= 120),
    engineSets: engineSets,
    engineReps: engineReps,
    engineRestSec: engineRest,
  );
  return _applyScheme(m, s);
}

/// 스킴의 숫자를 계획 줄에 적습니다 — 'sets' · 'reps' · 'restSec' 를 덮어쓰고, 시간 종목은
/// 'seconds' 를 넣고 아니면 뺍니다. 'perSide' · 'why' 를 더합니다.
Map<String, Object?> _applyScheme(Map<String, Object?> m, Scheme s) {
  m['sets'] = s.sets;
  m['reps'] = s.reps;
  m['restSec'] = s.restSec;
  if (s.seconds != null) {
    m['seconds'] = s.seconds;
  } else {
    m.remove('seconds');
  }
  m['perSide'] = s.perSide;
  m['why'] = s.why;
  return m;
}

int? _int(Object? v) {
  if (v is int) return v;
  if (v is num && v.isFinite) return v.round();
  if (v is String) return int.tryParse(v.trim());
  return null;
}

/// 쉬는 시간의 바닥. 이보다 짧으면 다음 세트가 안 나옵니다.
const int kMinRestSec = 30;

/// 세션 예산 — 세트 × (동작 + 휴식) 의 합이 [minutes] 분을 넘으면 휴식을 한 비율로
/// 줄입니다(5초 단위, 바닥 [kMinRestSec]). 바닥에 걸린 줄은 빼고 나머지를 다시 나눕니다 —
/// 그래야 바닥 때문에 남은 초과가 긴 휴식 쪽으로 갑니다. 제자리에서 고칩니다.
/// [minutes] 가 없거나 0 이하면 아무것도 안 합니다. 예산 안이면 그대로 — 남는 시간을
/// 채우려 늘리지 않습니다.
void fitRestToBudget(List<Map<String, Object?>> exercises, Object? minutes) {
  final min = minutes is num && minutes.isFinite ? minutes : null;
  if (min == null || min <= 0 || exercises.isEmpty) return;
  final budget = (min * 60).round();
  var work = 0;
  for (final e in exercises) {
    work += (_int(e['sets']) ?? 3) * workSecondsOf(e);
  }
  /* 한 번에 끝나지 않는 것은 바닥에 걸린 줄 때문입니다 — 줄 수만큼이면 언제나 수렴합니다. */
  for (var pass = 0; pass <= exercises.length; pass++) {
    var fixed = 0;
    var adjustable = 0;
    for (final e in exercises) {
      final sets = _int(e['sets']) ?? 3;
      final r = _int(e['restSec']) ?? 0;
      if (r <= kMinRestSec) {
        fixed += sets * r;
      } else {
        adjustable += sets * r;
      }
    }
    final over = work + fixed + adjustable - budget;
    if (over <= 0 || adjustable <= 0) return;
    final factor = (adjustable - over) / adjustable;
    for (final e in exercises) {
      final r = _int(e['restSec']) ?? 0;
      if (r <= kMinRestSec) continue;
      final cut = factor <= 0 ? kMinRestSec : (r * factor / 5).floor() * 5;
      e['restSec'] = cut < kMinRestSec ? kMinRestSec : cut;
    }
  }
}

/// 세션의 계획 시간(초) — 세트 × (동작 + 휴식) 의 합. 예산 규칙의 검산용입니다 —
/// 화면은 session['minutes'] 를 보여 줍니다(주인이 「상체 A · 7종목 · 60분」 을 골랐습니다).
int plannedSeconds(List<Map<String, Object?>> exercises) {
  var total = 0;
  for (final e in exercises) {
    final sets = _int(e['sets']) ?? 3;
    total += sets * (workSecondsOf(e) + (_int(e['restSec']) ?? 0));
  }
  return total;
}

/// 같은 부위에서 되는 것 중 가장 가까운 종목. 없으면 null.
/// [preferMachine] 이면 머신·케이블에 가산점 — 헬스장에서 머신 자리가 남을 때.
Exercise? _bestAlternative(
    _Row r, GymPrefs prefs, Set<String> used, bool Function(Exercise) ok,
    {bool preferMachine = false}) {
  Exercise? best;
  var bestScore = -1;
  for (final e in exercisesFor(r.group)) {
    if (e.id == r.id || used.contains(e.id) || !ok(e)) continue;
    final samePattern = r.pattern.isNotEmpty && e.pattern == r.pattern;
    /* 맨몸 가산점은 집에서, 움직임이 다를 때만 — 같은 움직임끼리는 사전 순서가
       정합니다. 덤벨이 있는 사람에게 로우 대신 책상 로우를 주지 않게. 헬스장에서는
       맨몸보다 머신이 먼저입니다 — 앉아서 손잡이를 밀면 되니까요. */
    final score = (prefs.familiar.contains(e.id) ? 100 : 0) +
        (samePattern ? 10 : 0) +
        (preferMachine && e.isMachine ? 5 : 0) +
        (!samePattern && prefs.isHome && e.equip == 'bodyweight' ? 1 : 0);
    if (score > bestScore) {
      best = e;
      bestScore = score;
    }
  }
  return best;
}

/// 세션의 종목 한 줄. 엔진이 준 Map 을 들고 있다가 이름·기구·메모만 갈아 끼웁니다.
class _Row {
  _Row(this.src)
      : lib = exerciseByName('${src['name'] ?? ''}'),
        name = '${src['name'] ?? ''}',
        original = '${src['name'] ?? ''}',
        note = src['note'] == null ? '' : '${src['note']}' {
    equip = lib?.equip ?? '${src['equip'] ?? 'bodyweight'}';
    group = lib?.group ?? '${src['group'] ?? ''}';
    pattern = lib?.pattern ?? '';
    id = lib?.id ?? slugOf(name);
  }

  final Map<String, Object?> src;
  Exercise? lib;
  String name;
  /// 엔진이 준 이름. 두 번 바뀌어도(1 에서 머신으로, 4 에서 다른 머신으로) 메모의
  /// 「원래 X」 는 언제나 이것입니다 — 사용자가 아는 "원래" 는 플랜의 이름입니다.
  final String original;
  String note;
  late String equip;
  late String group;
  late String pattern;
  late String id;

  bool get isMachine => equip == 'machine' || equip == 'cable';

  /// 사전에 없는 종목은 엔진이 준 기구로만 판단합니다.
  bool available(GymPrefs prefs) {
    if (equip == 'bodyweight' && !(lib?.needsBar == true && prefs.isHome)) return true;
    if (equip == 'bodyweight') return false;
    return prefs.equipment.contains(equip);
  }

  void replace(Exercise e, String prefix) {
    lib = e;
    name = e.name;
    equip = e.equip;
    pattern = e.pattern;
    id = e.id;
    final extra = e.note == null || e.note!.isEmpty ? '' : ' · ${e.note}';
    note = '$prefix$original$extra';
  }

  void markSkip() {
    note = note.isEmpty ? kSkipNote : '$note · $kSkipNote';
  }

  Map<String, Object?> toMap() => {
        ...src,
        'id': id,
        'name': name,
        'equip': equip,
        'group': group.isEmpty ? src['group'] : group,
        'note': note,
      };
}
