/* data.js 를 읽어 Dart 리터럴로 찍습니다. 손으로 옮기면 반드시 한 글자 틀립니다. */
const path = require('path');
global.window = global;
require(path.join(__dirname, '..', 'prototype', 'js', 'data.js'));
const D = global.MB_DATA;

function lit(v, indent) {
  const pad = ' '.repeat(indent), pad2 = ' '.repeat(indent + 2);
  if (v === null || v === undefined) return 'null';
  if (typeof v === 'number') return Number.isInteger(v) ? v + '.0' : String(v);
  if (typeof v === 'boolean') return String(v);
  if (typeof v === 'string') return "'" + v.replace(/\\/g, '\\\\').replace(/'/g, "\\'").replace(/\n/g, '\\n').replace(/\$/g, '\\$') + "'";
  if (Array.isArray(v)) {
    if (!v.length) return '<Object?>[]';
    return '[\n' + v.map(x => pad2 + lit(x, indent + 2)).join(',\n') + ',\n' + pad + ']';
  }
  const ks = Object.keys(v);
  if (!ks.length) return '<String, Object?>{}';
  return '{\n' + ks.map(k => pad2 + lit(k, 0) + ': ' + lit(v[k], indent + 2)).join(',\n') + ',\n' + pad + '}';
}

const out = [];
out.push(`/* =============================================================================
 * data.dart — prototype/js/data.js 를 그대로 옮긴 씨앗 데이터
 *
 * **손으로 옮기지 않았습니다.** data.js 를 읽어서 찍어낸 것입니다
 * (tools/gen-data-dart.js). 운동 종목 40개와 식품 23개를 눈으로 옮기면
 * 반드시 한 글자가 틀리고, 틀린 자리는 "닭가슴살 단백질 23g" 같은
 * 사용자가 그대로 믿는 숫자입니다.
 *
 * 정수도 전부 소수(22.0)로 찍습니다. 자바스크립트에는 정수형이 따로 없고
 * 우리는 그 산수를 흉내 내는 중이라, Dart 쪽에서만 int 로 들어가면
 * 나눗셈과 비교가 갈리는 자리가 생깁니다. 값은 같습니다 — 22.0 == 22.
 *
 * 원본이 바뀌면 다시 찍어내세요:  node tools/gen-data-dart.js
 * ========================================================================== */
library;
`);
out.push('const Map<String, Object?> kSeedProfile = ' + lit(D.SEED_PROFILE, 0) + ';\n');
out.push('const List<Object?> kSeedScans = ' + lit(D.SEED_SCANS, 0) + ';\n');
out.push('const Map<String, Object?> kStubOcrResult = ' + lit(D.STUB_OCR_RESULT, 0) + ';\n');
out.push('/// 운동 종목 풀 — 부위 → 종목 목록');
out.push('const Map<String, Object?> kExercises = ' + lit(D.EXERCISES, 0) + ';\n');
out.push('/// 한식 기반 식품 DB (100g 또는 1인분 기준)');
out.push('const List<Object?> kFoods = ' + lit(D.FOODS, 0) + ';\n');
out.push('/// 외식·편의점 가이드');
out.push('const List<Object?> kEatingOut = ' + lit(D.EATING_OUT, 0) + ';\n');
process.stdout.write(out.join('\n'));
