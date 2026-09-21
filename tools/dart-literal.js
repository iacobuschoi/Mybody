/* =============================================================================
 * dart-literal.js — 자바스크립트 값을 Dart 리터럴로 찍습니다.
 *
 * data.js · modes.js · fooddb.js 세 군데서 같은 일을 합니다. 복사해 두면
 * 한 군데만 고쳐지고 나머지는 조용히 달라집니다 — 특히 따옴표와 줄바꿈
 * 이스케이프가 그렇습니다.
 *
 * 정수도 소수(22.0)로 찍습니다. 자바스크립트에는 정수형이 따로 없고
 * 우리는 그 산수를 흉내 내는 중이라, Dart 쪽에서만 int 로 들어가면
 * 나눗셈과 비교가 갈리는 자리가 생깁니다. 값은 같습니다 — 22.0 == 22.
 * ========================================================================== */
'use strict';

function lit(v, indent) {
  indent = indent || 0;
  const pad = ' '.repeat(indent), pad2 = ' '.repeat(indent + 2);
  if (v === null || v === undefined) return 'null';
  if (typeof v === 'number') return Number.isInteger(v) ? v + '.0' : String(v);
  if (typeof v === 'boolean') return String(v);
  if (typeof v === 'string') {
    return "'" + v.replace(/\\/g, '\\\\').replace(/'/g, "\\'")
                  .replace(/\n/g, '\\n').replace(/\r/g, '\\r').replace(/\$/g, '\\$') + "'";
  }
  if (Array.isArray(v)) {
    if (!v.length) return '<Object?>[]';
    return '[\n' + v.map(x => pad2 + lit(x, indent + 2)).join(',\n') + ',\n' + pad + ']';
  }
  const ks = Object.keys(v).filter(k => typeof v[k] !== 'function');
  if (!ks.length) return '<String, Object?>{}';
  return '{\n' + ks.map(k => pad2 + lit(k, 0) + ': ' + lit(v[k], indent + 2)).join(',\n') + ',\n' + pad + '}';
}

/** prototype/js/<name>.js 를 노드에서 읽습니다 (브라우저용이라 window 가 필요합니다). */
function loadPrototype(names) {
  const path = require('path');
  if (typeof global.window === 'undefined') global.window = global;
  for (const n of [].concat(names)) {
    require(path.join(__dirname, '..', 'prototype', 'js', n + '.js'));
  }
}

module.exports = { lit, loadPrototype };
