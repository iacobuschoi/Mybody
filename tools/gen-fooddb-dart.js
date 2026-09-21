/* fooddb.js 의 식품 90여 개를 Dart 로 찍습니다. 사용자가 "삼겹살 1인분" 을
   고르면 그대로 750kcal 로 기록되는 값들이라 한 글자도 틀리면 안 됩니다. */
const { lit, loadPrototype } = require('./dart-literal');
loadPrototype('fooddb');
const F = global.MB_FOOD;

const out = [];
out.push(`/* =============================================================================
 * fooddb_data.dart — prototype/js/fooddb.js 의 식품표 (손으로 옮기지 않았습니다)
 *
 * 찍어낸 것입니다: node tools/gen-fooddb-dart.js
 * 검색과 배수 계산은 fooddb.dart 에 있습니다.
 * ========================================================================== */
library;
`);
out.push('/// 한식 중심 식품표. g·kcal·단백·탄수·지방과 편차 신뢰도(conf).');
out.push('const List<Object?> kFoodDb = ' + lit(F.FOODS, 0) + ';\n');
out.push('/// 분류 순서 — 화면의 탭 순서이기도 합니다.');
out.push('const List<String> kFoodCats = [' + F.CATS.map(c => lit(c)).join(', ') + '];\n');
out.push('/// 1인분 프리셋 — 사진으로 재는 것보다 이게 정확합니다.');
out.push('const List<Object?> kPortions = ' + lit(F.PORTIONS, 0) + ';\n');
out.push('/// 편차가 얼마나 큰지 — 숫자를 얼마나 믿어도 되는지 말해 줍니다.');
out.push('const Map<String, Object?> kConfLabel = ' + lit(F.CONF_LABEL, 0) + ';\n');
process.stdout.write(out.join('\n'));
