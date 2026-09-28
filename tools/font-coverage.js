/* =============================================================================
 * font-coverage.js — 앱이 그릴 수 있는 글자와, 글꼴이 가진 글자를 맞춰 봅니다.
 *
 * 시험(test-fontcover.js)과 고치는 도구(fix-fonts.js)가 **같은 눈**으로 봐야
 * 합니다. 따로 두면 시험은 통과하는데 고치는 쪽이 다른 글자를 넣습니다.
 * ========================================================================== */
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const ROOT = path.join(__dirname, '..');

/** Material 아이콘·위젯으로 그리는 것 — 글꼴에 없어도 됩니다.
 *
 *  **이모지 범위를 통째로 빼지 않습니다.** 폰(안드로이드 · 아이폰)은 기기의 이모지
 *  글꼴로 그리지만, 웹 빌드(CanvasKit)는 구글에서 받아 옵니다. 글꼴에 넣지도 않습니다
 *  — 넣으면 폰의 컬러 이모지를 흑백 윤곽으로 덮습니다(도너 FreeSans · DejaVu 에는 대개 없기도 합니다).
 *  그래서 화면 문구에는 이모지를 안 쓰고 아이콘으로 그립니다(ui/symbols.dart). 여기에는
 *  **화면이 그 글자를 위젯으로 바꿔 그리는 것만** 적습니다. */
/* `split('')` 이 아니라 스프레드입니다.
   split('') 은 UTF-16 **코드 단위**로 쪼개서 이모지를 반으로 자릅니다 —
   그러면 codePointAt(0) 이 서러게이트 반쪽을 돌려주고, 면제 목록에 적어
   둔 이모지가 하나도 안 걸립니다. 실제로 그래서 "🟢 을 못 넣었습니다" 가
   나왔습니다. 스프레드는 코드포인트 단위로 돕니다. */
const EXEMPT = new Set([
  ...[...'★☆'].map(c => c.codePointAt(0)),            // DifficultyStars 가 그립니다
  ...[...'⛔🟢🟡🔴'].map(c => c.codePointAt(0)),        // VerdictDot 이 그립니다
  ...[...'🏋🏃🍚📋📈👥📷🏠'].map(c => c.codePointAt(0)), // Material 아이콘
  0xFE0F, 0x200D, 0x2699                                // 변형 선택자 · ⚙
]);

function collect(dir, exts) {
  const out = [];
  (function walk(d) {
    if (!fs.existsSync(d)) return;
    for (const f of fs.readdirSync(d)) {
      const p = path.join(d, f);
      const st = fs.statSync(p);
      if (st.isDirectory()) { if (f !== 'build' && f[0] !== '.') walk(p); }
      else if (exts.some(e => f.endsWith(e))) out.push(p);
    }
  })(dir);
  return out;
}

/* **Dart 쪽만 봅니다.** prototype/js 는 브라우저가 그리고, 브라우저는 시스템
   글꼴을 씁니다. 여기서 재는 것은 "설치하는 앱이 자기 글꼴만으로 그릴 수
   있는가" 입니다. 코어의 Dart 에는 옮긴 문구가 그대로 들어 있어 같이 봅니다. */
function usedChars() {
  const files = [
    ...collect(path.join(ROOT, 'app', 'lib'), ['.dart']),
    ...collect(path.join(ROOT, 'packages', 'mybody_core', 'lib'), ['.dart'])
  ];
  const STR = /'((?:[^'\\\n]|\\.)*)'|"((?:[^"\\\n]|\\.)*)"/g;
  const seen = new Map();
  for (const f of files) {
    const src = fs.readFileSync(f, 'utf8');
    let m;
    while ((m = STR.exec(src))) {
      for (const ch of (m[1] || m[2] || '')) {
        const cp = ch.codePointAt(0);
        if (cp < 0x20) continue;
        if (!seen.has(cp)) seen.set(cp, path.relative(ROOT, f));
      }
    }
  }
  return seen;
}

/** 글꼴이 가진 코드포인트. fontTools 가 없으면 null. */
function fontChars(file) {
  const r = spawnSync('python3', ['-c',
    `from fontTools.ttLib import TTFont\nimport json\nprint(json.dumps(sorted(TTFont(${JSON.stringify(file)}).getBestCmap().keys())))`
  ], { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
  if (r.status !== 0) return null;
  return new Set(JSON.parse(r.stdout));
}

/** 앱이 그리는데 글꼴에 없는 글자 */
function missing(file) {
  const have = fontChars(file);
  if (!have) return null;
  const out = [];
  for (const [cp, where] of usedChars()) {
    if (have.has(cp) || EXEMPT.has(cp)) continue;
    out.push({ cp, ch: String.fromCodePoint(cp), where });
  }
  return out;
}

const FONTS = [
  path.join(ROOT, 'app', 'assets', 'fonts', 'Pretendard-Regular.ttf'),
  path.join(ROOT, 'app', 'assets', 'fonts', 'Pretendard-Bold.ttf')
];

module.exports = { ROOT, EXEMPT, usedChars, fontChars, missing, FONTS };
