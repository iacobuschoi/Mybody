/* =============================================================================
 * fooddb.dart — 식품 검색과 배수 계산 (prototype/js/fooddb.js 의 이식)
 *
 * 식품표 자체는 fooddb_data.dart 에 찍혀 있습니다. 여기에는 찾는 방법과
 * "1.5인분" 을 실제 숫자로 바꾸는 계산만 있습니다.
 * ========================================================================== */
library;

import 'fooddb_data.dart';
import 'js_num.dart';

export 'fooddb_data.dart';

/// 이름·별명·분류를 한 줄로 이어 붙여 **부분 일치**로 찾습니다.
/// 이름의 맨 앞에서 걸리면 먼저 보여 줍니다.
List<Map<String, Object?>> search(Object? q, [Object? limit]) {
  final needle = '${q ?? ''}'.trim().toLowerCase();
  if (needle.isEmpty) return [];
  final hits = <Map<String, Object?>>[];
  final scores = <double>[];
  for (final x0 in kFoodDb) {
    final x = (x0 as Map).cast<String, Object?>();
    final hay = '${x['name']} ${x['alias']} ${x['cat']}'.toLowerCase();
    final idx = hay.indexOf(needle);
    if (idx >= 0) {
      hits.add(x);
      scores.add(('${x['name']}'.toLowerCase().indexOf(needle) == 0 ? 0 : 1) + idx * 0.001);
    }
  }
  /* JS 의 sort 는 안정 정렬입니다. 점수가 같은 식품(예: 같은 자리에서 걸린
     '프로틴 쉐이크' 세 종류)의 순서가 화면에서 뒤바뀌지 않게 맞춥니다. */
  final order = List<int>.generate(hits.length, (i) => i);
  order.sort((a, b) {
    final c = scores[a] - scores[b];
    if (c < 0) return -1;
    if (c > 0) return 1;
    return a - b;
  });
  final n = jsTruthy(limit) ? jsToNumber(limit).toInt() : 30;
  final out = [for (final i in order) hits[i]];
  return out.length > n ? out.sublist(0, n) : out;
}

List<Map<String, Object?>> byCat(Object? cat) => [
      for (final x0 in kFoodDb)
        if ((x0 as Map)['cat'] == cat) x0.cast<String, Object?>()
    ];

Map<String, Object?>? byName(Object? name) {
  for (final x0 in kFoodDb) {
    final x = (x0 as Map).cast<String, Object?>();
    if (x['name'] == name) return x;
  }
  return null;
}

/// 배수를 적용한 실제 섭취값. `mult || 1` 이라 0 은 1 이 됩니다.
Map<String, Object?> scaled(Map<String, Object?> food, [Object? mult]) {
  final m = jsTruthy(mult) ? jsToNumber(mult) : 1.0;
  return {
    'name': food['name'], 'unit': food['unit'], 'mult': m,
    'g': jsRound(jsToNumber(food['g']) * m),
    'kcal': jsRound(jsToNumber(food['kcal']) * m),
    'p': jsRound(jsToNumber(food['p']) * m * 10) / 10,
    'c': jsRound(jsToNumber(food['c']) * m * 10) / 10,
    'f': jsRound(jsToNumber(food['f']) * m * 10) / 10,
    'conf': food['conf'],
  };
}
