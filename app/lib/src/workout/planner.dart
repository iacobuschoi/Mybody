/* =============================================================================
 * planner.dart — 엔진의 세션을 내 자리에 맞게 고칩니다
 *
 * 엔진(engine.workoutFor)은 부위와 세트·반복을 정하고 종목은 풀에서 앞에서부터
 * 집습니다. 그 풀에는 바벨과 머신이 섞여 있어서, 집에서 하는 사람이나 머신이
 * 두 대뿐인 동네 헬스장에서는 계획의 반이 "할 수 없는 것" 이 됩니다.
 *
 * 여기서는 종목만 바꿉니다. 세트 · 반복 · 쉬는 시간 · RPE 와 순서는 엔진이
 * 정한 그대로 둡니다 — 그건 몸 상태로 정한 것이고, 기구가 없다고 바뀔 이유가
 * 없습니다. 같은 입력이면 언제나 같은 답입니다 (무작위 없음).
 * ========================================================================== */
library;

import 'exercises.dart';
import 'prefs.dart';

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

/// Adapts one engine session to the person's gym. Pure and deterministic.
///
/// 규칙 (위에서부터 차례로):
///  1. 기구가 없는 종목은 같은 부위의 되는 종목으로 — 잘 아는 것 > 같은
///     움직임 > 맨몸 > 나머지, 같으면 사전 순서. 메모에 '대체: 원래 X'.
///  2. machineCount 가 있으면 머신·케이블은 앞에서부터 그 개수까지만 두고
///     나머지는 프리웨이트·맨몸으로.
///  3. 잘 아는 종목이 같은 부위에 있으면 하나 바꿔 넣습니다. 부위마다 한 번만 —
///     아는 것만 남으면 계획이 늘 같아집니다.
///  4. 같은 종목은 두 번 나오지 않습니다. 바꿀 것이 없으면 원래 것을 두고
///     '기구가 없으면 건너뛰기' 를 답니다.
List<Map<String, Object?>> tailorSession(Map<String, Object?> session, GymPrefs prefs) {
  final raw = session['exercises'];
  if (raw is! List || raw.isEmpty || session['rest'] == true) return const [];

  final rows = <_Row>[
    for (final x in raw)
      if (x is Map) _Row(x.cast<String, Object?>()),
  ];
  final used = <String>{for (final r in rows) r.id};
  final cap = prefs.machineCount;

  bool available(Exercise e) =>
      (e.equip == 'bodyweight' || prefs.equipment.contains(e.equip)) &&
      !(e.needsBar && prefs.isHome);

  /* 1. 기구가 없는 종목을 바꿉니다. */
  for (final r in rows) {
    if (r.available(prefs)) continue;
    final alt = _bestAlternative(r, prefs, used, available);
    if (alt == null) {
      r.markSkip();
    } else {
      used.remove(r.id);
      r.replace(alt, kSubstitutePrefix);
      used.add(r.id);
    }
  }

  /* 2. 머신 개수 제한 — 앞에서부터 셉니다. 앞이 보통 주된 종목입니다. */
  if (cap != null) {
    var machines = 0;
    for (final r in rows) {
      if (!r.isMachine) continue;
      if (machines < cap) {
        machines++;
        continue;
      }
      final alt = _bestAlternative(r, prefs, used, (e) => available(e) && !e.isMachine);
      if (alt == null) {
        r.markSkip();
      } else {
        used.remove(r.id);
        r.replace(alt, kSubstitutePrefix);
        used.add(r.id);
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
        if (f.isMachine && !target.isMachine && cap != null) {
          final machines = rows.where((r) => r.isMachine).length;
          if (machines >= cap) continue;                // 머신 자리가 없습니다
        }
        used.remove(target.id);
        target.replace(f, kFamiliarPrefix);
        used.add(target.id);
        swapped = true;
      }
    }
  }

  return [for (final r in rows) r.toMap()];
}

/// 같은 부위에서 되는 것 중 가장 가까운 종목. 없으면 null.
Exercise? _bestAlternative(
    _Row r, GymPrefs prefs, Set<String> used, bool Function(Exercise) ok) {
  Exercise? best;
  var bestScore = -1;
  for (final e in exercisesFor(r.group)) {
    if (e.id == r.id || used.contains(e.id) || !ok(e)) continue;
    final samePattern = r.pattern.isNotEmpty && e.pattern == r.pattern;
    /* 맨몸 가산점은 움직임이 다를 때만 — 같은 움직임끼리는 사전 순서가
       정합니다. 덤벨이 있는 사람에게 로우 대신 책상 로우를 주지 않게. */
    final score = (prefs.familiar.contains(e.id) ? 100 : 0) +
        (samePattern ? 10 : 0) +
        (!samePattern && e.equip == 'bodyweight' ? 1 : 0);
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
        note = src['note'] == null ? '' : '${src['note']}' {
    equip = lib?.equip ?? '${src['equip'] ?? 'bodyweight'}';
    group = lib?.group ?? '${src['group'] ?? ''}';
    pattern = lib?.pattern ?? '';
    id = lib?.id ?? slugOf(name);
  }

  final Map<String, Object?> src;
  Exercise? lib;
  String name;
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
    final original = name;
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
