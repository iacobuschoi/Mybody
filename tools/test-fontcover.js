/* =============================================================================
 * test-fontcover.js — **앱이 그리는 글자가 앱 안에 다 있는가**
 *
 * Flutter 는 글꼴에 없는 글자를 만나면 fonts.gstatic.com 에서 받아 오려
 * 합니다. 실제로 화면 한 번 도는 동안 요청이 1,900건 나갔습니다 —
 * −, ≈, ★ 과 이모지가 우리가 넣어 둔 글꼴에 없어서였습니다.
 *
 * 망이 막힌 곳에서는 그 자리가 네모가 되고, 안 막힌 곳에서는 몸 관리 앱을
 * 켤 때마다 구글에 신호가 갑니다. 둘 다 안 됩니다.
 *
 * 빠진 글자가 있으면 `node tools/fix-fonts.js` 가 채워 넣습니다.
 * 시험과 그 도구는 **같은 눈**(tools/font-coverage.js)으로 봅니다.
 * ========================================================================== */
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const { missing, fontChars, usedChars, FONTS } = require('./font-coverage');

let pass = 0, fail = 0;
const ok = (m) => { pass++; console.log('  ✓ ' + m); };
const no = (m, d) => { fail++; console.log('  ✗ ' + m + (d ? '\n      ' + d : '')); };

console.log('\n앱이 그리는 글자가 앱 안에 다 있는가\n');

for (const font of FONTS) {
  const name = path.basename(font);
  if (!fs.existsSync(font)) { no(name + ' 이 없습니다'); continue; }

  const gaps = missing(font);
  if (gaps === null) {
    console.log('  ! fontTools 가 없어 건너뜁니다 (pip install fonttools)');
    process.exit(0);
  }
  if (!gaps.length) {
    ok(name + ': 화면에 나갈 수 있는 글자가 전부 들어 있습니다 (' +
       usedChars().size + '자 확인)');
  } else {
    const shown = gaps.slice(0, 12)
      .map(g => `${g.ch} (U+${g.cp.toString(16).toUpperCase()}) ${g.where}`).join('\n      ');
    no(name + ': ' + gaps.length + '자가 없습니다 — 폰에서 네모가 되거나 구글에서 받아 옵니다',
       shown + (gaps.length > 12 ? `\n      … 외 ${gaps.length - 12}자` : '') +
       '\n      고치려면: node tools/fix-fonts.js');
  }

  /* 한글은 통째로 있어야 합니다 — 사용자 이름과 음식 이름은 우리가 정하는
     글자가 아닙니다. 부분집합으로 줄이면 누군가의 이름이 네모가 됩니다. */
  const have = fontChars(font);
  let hangul = 0;
  for (let cp = 0xAC00; cp <= 0xD7A3; cp++) if (have.has(cp)) hangul++;
  if (hangul === 11172) ok(name + ': 한글 11,172자가 전부 있습니다');
  else no(name + ': 한글이 ' + hangul + '자뿐입니다 (11,172자 있어야 합니다)',
          '사용자 이름·음식 이름은 우리가 정하는 글자가 아닙니다');
}

console.log('\n통과 ' + pass + ' / 실패 ' + fail);
process.exit(fail ? 1 : 0);
