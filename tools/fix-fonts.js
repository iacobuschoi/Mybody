/* =============================================================================
 * fix-fonts.js — 앱 글꼴에 **빠진 글자를 채워 넣습니다**
 *
 *   node tools/fix-fonts.js
 *
 * 앱이 그리는 글자 중 글꼴에 없는 것을 찾아, FreeSans 에서 그 글자만
 * 떼어다 붙입니다. 둘 다 단위가 1000 이라 크기가 안 틀어집니다
 * (DejaVu 는 2048 이라 붙이면 그 글자만 커집니다).
 *
 * 왜 필요한가: Flutter 는 글꼴에 없는 글자를 fonts.gstatic.com 에서
 * 받아 오려 합니다. 망이 막힌 곳에서는 네모가 되고, 안 막힌 곳에서는
 * 몸 관리 앱을 켤 때마다 구글에 신호가 갑니다.
 * ========================================================================== */
'use strict';
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const { missing, FONTS } = require('./font-coverage');

let bad = 0;
for (const font of FONTS) {
  const gaps = missing(font);
  if (gaps === null) {
    console.log('fontTools 가 없어 건너뜁니다 (pip install fonttools)');
    process.exit(0);
  }
  if (!gaps.length) {
    console.log(path.basename(font) + ': 빠진 글자 없음');
    continue;
  }
  console.log(path.basename(font) + ': ' + gaps.length + '자 채웁니다 — ' +
              gaps.map(g => g.ch).join(' '));
  const r = spawnSync('python3',
    [path.join(__dirname, 'font-add-glyphs.py'), font,
     ...gaps.map(g => g.cp.toString(16))],
    { encoding: 'utf8', stdio: 'inherit' });
  if (r.status !== 0) bad++;
}
process.exit(bad ? 1 : 0);
