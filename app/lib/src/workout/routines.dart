/* =============================================================================
 * routines.dart — 내 루틴 (state['routines'])
 *
 * 헬스 화면에서 종목을 넣고 빼고 무게를 정하고 나면 그 구성은 그 날 기록에만
 * 남았습니다. 2차 피드백 20: "운동 종료하면 내 루틴으로 저장, 다음에 불러오기".
 * 여기 있는 것은 그 목록의 읽기 · 쓰기뿐입니다 — 화면은 workout_session.dart.
 *
 * 모양:
 *   state['routines'] = [{id, name, label, exercises: [{name, sets, reps, restSec, kg?}],
 *                         createdAt, updatedAt}]
 *   · label 은 플랜 세션 라벨('상체 A'). 같은 라벨의 날에 열면 자동으로 이 루틴을
 *     씁니다 — 사용자가 적게 누르고 앱이 알아서.
 *   · 기기 사이 동기화됩니다(merge.dart 의 mergedLists 에 'routines': 'id' —
 *     양쪽이 각각 만든 루틴은 다 남고, 같은 것은 updatedAt 이 나중인 쪽).
 *   · 값은 전부 JSON 으로 그대로 적히는 것만(문자열 · 숫자 · 목록).
 * ========================================================================== */
library;

import 'dart:math';

import '../app_state.dart';
import 'exercises.dart';

const String kRoutinesKey = 'routines';

/// 종료 시트의 기본 이름 — '(세션 라벨) 내 루틴'.
String defaultRoutineName(String label) => label.trim().isEmpty ? '내 루틴' : '${label.trim()} 내 루틴';

/// 저장된 루틴 전부, 최근에 고친 것이 앞. 깨진 항목은 거릅니다.
List<Map<String, Object?>> routinesOf(AppState app) {
  final raw = app.state[kRoutinesKey];
  if (raw is! List) return const [];
  final out = <Map<String, Object?>>[
    for (final x in raw)
      if (x is Map && x['id'] is String && (x['id'] as String).isNotEmpty) x.cast<String, Object?>(),
  ];
  out.sort((a, b) => '${b['updatedAt'] ?? ''}'.compareTo('${a['updatedAt'] ?? ''}'));
  return out;
}

Map<String, Object?>? routineById(AppState app, String id) {
  for (final r in routinesOf(app)) {
    if (r['id'] == id) return r;
  }
  return null;
}

/// 그 세션 라벨로 저장한 루틴 중 가장 최근 것. 없으면 null.
Map<String, Object?>? routineForLabel(AppState app, String label) {
  final l = label.trim();
  for (final r in routinesOf(app)) {
    if ('${r['label'] ?? ''}'.trim() == l) return r;
  }
  return null;
}

/// 루틴의 종목 목록(복사본). 같은 종목이 두 번이면 첫 것만 — 헬스 화면의 줄 키가
/// 종목 id 라 겹치면 목록이 깨집니다. 이 화면에서 만든 루틴은 겹칠 수 없지만,
/// 다른 기기에서 합쳐진 것이나 손으로 고친 백업은 그렇지 않습니다.
List<Map<String, Object?>> routineExercises(Map<String, Object?> routine) {
  final xs = routine['exercises'];
  if (xs is! List) return const [];
  final seen = <String>{};
  final out = <Map<String, Object?>>[];
  for (final x in xs) {
    if (x is! Map) continue;
    final m = x.cast<String, Object?>();
    final name = '${m['name'] ?? ''}';
    if (seen.add(exerciseByName(name)?.id ?? slugOf(name))) out.add(m);
  }
  return out;
}

/// 저장. [id] 가 있으면 그것을 고치고, 없으면 **같은 이름**이 있으면 그것을 고칩니다 —
/// 같은 이름을 두 번 저장했는데 둘로 늘어나면 목록이 금방 지저분해집니다.
/// 둘 다 아니면 새로 만듭니다. 돌려주는 것은 저장된 루틴.
Map<String, Object?> saveRoutine(
  AppState app, {
  String? id,
  required String name,
  String label = '',
  required List<Map<String, Object?>> exercises,
}) {
  final list = routinesOf(app);
  final now = (app.store.now ?? DateTime.now)().toUtc().toIso8601String();
  final n = name.trim().isEmpty ? defaultRoutineName(label) : name.trim();
  Map<String, Object?>? old;
  for (final r in list) {
    if ((id != null && r['id'] == id) || (id == null && r['name'] == n)) {
      old = r;
      break;
    }
  }
  final saved = <String, Object?>{
    'id': old?['id'] ?? 'r-${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(1 << 20)}',
    'name': n,
    'label': label.trim(),
    'exercises': [for (final x in exercises) _cleanExercise(x)],
    'createdAt': old?['createdAt'] ?? now,
    'updatedAt': now,
  };
  final next = [for (final r in list) if (r['id'] != saved['id']) r, saved];
  app.store.set({kRoutinesKey: next});
  return saved;
}

/// 지우기. 있었으면 true. 묘비를 같이 세웁니다 — 기준본 없는 동기화(새 기기 ·
/// 재로그인)가 "저쪽에 있고 여기 없는 것" 을 지운 것으로 알아보는 유일한 단서입니다.
bool deleteRoutine(AppState app, String id) {
  final list = routinesOf(app);
  final next = [for (final r in list) if (r['id'] != id) r];
  if (next.length == list.length) return false;
  app.store.tombstone(kRoutinesKey, id);
  app.store.set({kRoutinesKey: next});
  return true;
}

/// 종목 한 줄을 저장 모양으로 — 이름 · 세트 · 반복 · 쉬는 시간 · (있으면) kg.
Map<String, Object?> _cleanExercise(Map<String, Object?> x) {
  final sets = x['sets'], rest = x['restSec'], kg = x['kg'];
  return {
    'name': '${x['name'] ?? ''}',
    'sets': sets is num && sets >= 1 ? sets.round() : 3,
    'reps': '${x['reps'] ?? '10-15'}',
    'restSec': rest is num && rest >= 0 ? rest.round() : 75,
    if (kg is num && kg > 0) 'kg': kg.toDouble(),
  };
}
