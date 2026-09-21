/* =============================================================================
 * tools/difftest.js — 옮긴 Dart 가 원본 JS 와 **같은 답을 내는가**
 *
 *   node tools/difftest.js                     전부
 *   node tools/difftest.js --module=crosscheck
 *   node tools/difftest.js --n=5000 --seed=7
 *   node tools/difftest.js --keep               갈린 사례를 파일로 남깁니다
 *
 * 왜 이렇게 검증하는가
 *   화면을 Flutter 로 옮기는 일은 눈으로 볼 수 있습니다. 그런데
 *   crosscheck 와 engine 은 눈으로 못 봅니다 — 틀려도 그럴듯한 숫자가
 *   나오고, 사용자는 그 숫자를 믿습니다. "옮겼습니다" 라는 말로는
 *   아무것도 보증되지 않습니다.
 *
 *   그래서 시험을 몇 개 옮겨 쓰는 대신, **같은 입력을 양쪽에 넣고 답을
 *   글자 단위로 비교**합니다. 수천 개를 넣습니다. 하나라도 갈리면
 *   그 입력을 그대로 보여 줍니다 — 재현이 곧 수정의 출발점입니다.
 *
 *   무작위지만 씨앗(seed)을 고정합니다. 재현 안 되는 실패는 고쳤는지
 *   확인할 방법이 없습니다.
 *
 * 무엇을 넣는가
 *   그럴듯한 값만 넣으면 그럴듯한 곳에서만 같습니다. 그래서 일부러
 *   비틀어 넣습니다: 빈 칸, 0, 음수, 자릿수 오독(63.4 → 634),
 *   날짜 없음, 날짜 뒤집힘(backfill), 같은 시각 두 측정, 극단값.
 *   실제로 결과지 판독에서 나오는 것들입니다.
 * ========================================================================== */
'use strict';
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const ROOT = path.join(__dirname, '..');
const DART = process.env.DART || '/opt/dart-sdk/bin/dart';
const PKG = path.join(ROOT, 'packages', 'mybody_core');

const argv = process.argv.slice(2);
const flag = (k, d) => {
  const h = argv.find(a => a.indexOf('--' + k + '=') === 0);
  return h ? h.slice(k.length + 3) : d;
};
const N = Number(flag('n', 3000)) || 3000;
const SEED = Number(flag('seed', 1)) || 1;
const ONLY = flag('module', '');
const KEEP = argv.includes('--keep');

/* 씨앗 고정 난수 (mulberry32). 라이브러리를 안 씁니다. */
function rng(seed) {
  let a = seed >>> 0;
  return function () {
    a |= 0; a = (a + 0x6D2B79F5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const FIELDS = ['weightKg', 'smmKg', 'bfmKg', 'pbfPct', 'ffmKg', 'bmi', 'tbwL',
                'proteinKg', 'mineralKg', 'bmrKcal', 'visceralFatLevel', 'whr',
                'inbodyScore', 'idealWeightKg'];

/** 사람에 가까운 결과지 한 장. 여기서 출발해 일부러 망가뜨립니다. */
function plausible(rnd) {
  const w = 45 + rnd() * 55;                 // 45~100kg
  const pbf = 5 + rnd() * 35;                // 5~40%
  const bfm = w * pbf / 100;
  const ffm = w - bfm;
  const smm = ffm * (0.50 + rnd() * 0.12);
  const tbw = ffm * (0.70 + rnd() * 0.06);
  const protein = ffm * (0.19 + rnd() * 0.03);
  const mineral = ffm * (0.05 + rnd() * 0.02);
  const h = 1.5 + rnd() * 0.4;
  const r = x => Math.round(x * 10) / 10;
  return {
    scan: {
      weightKg: r(w), smmKg: r(smm), bfmKg: r(bfm), pbfPct: r(pbf), ffmKg: r(ffm),
      bmi: r(w / (h * h)), tbwL: r(tbw), proteinKg: r(protein), mineralKg: r(mineral),
      bmrKcal: Math.round(370 + 21.6 * ffm),
      visceralFatLevel: Math.round(1 + rnd() * 15),
      whr: Math.round((0.7 + rnd() * 0.3) * 100) / 100,
      inbodyScore: Math.round(50 + rnd() * 50),
      idealWeightKg: r(22 * h * h)
    },
    heightCm: Math.round(h * 100)
  };
}

/* 일부러 망가뜨리는 방법들 — 실제 판독에서 나오는 것들입니다. */
const BREAKERS = [
  (s, rnd) => { const k = FIELDS[(rnd() * FIELDS.length) | 0]; delete s[k]; },          // 칸 비우기
  (s, rnd) => { const k = FIELDS[(rnd() * FIELDS.length) | 0]; s[k] = null; },
  (s, rnd) => { const k = FIELDS[(rnd() * FIELDS.length) | 0]; if (typeof s[k] === 'number') s[k] = s[k] * 10; },  // 소수점 오독
  (s, rnd) => { const k = FIELDS[(rnd() * FIELDS.length) | 0]; if (typeof s[k] === 'number') s[k] = s[k] / 10; },
  (s, rnd) => { const k = FIELDS[(rnd() * FIELDS.length) | 0]; s[k] = 0; },
  (s, rnd) => { const k = FIELDS[(rnd() * FIELDS.length) | 0]; s[k] = -Math.abs(s[k] || 1); },   // 음수
  (s, rnd) => { const k = FIELDS[(rnd() * FIELDS.length) | 0]; s[k] = 'abc'; },                   // 숫자가 아님
  (s, rnd) => { const k = FIELDS[(rnd() * FIELDS.length) | 0]; s[k] = NaN; },
  (s, rnd) => { s.weightKg = 634; },                                                             // 63.4 → 634
  (s, rnd) => { s.smmKg = 73.9; },                                                               // 37.9 → 73.9 자리바꿈
  (s, rnd) => { const k = FIELDS[(rnd() * FIELDS.length) | 0]; s[k] = 1e9; },
  (s, rnd) => { const k = FIELDS[(rnd() * FIELDS.length) | 0]; s[k] = 0.0001; }
];

function makeCases(n, seed) {
  const rnd = rng(seed);
  const out = [];
  /* 손으로 고른 경계값들 — 무작위가 잘 안 만드는 것들입니다. */
  out.push({ scan: {}, profile: {}, prev: null });
  out.push({ scan: { weightKg: 70 }, profile: {}, prev: null });
  out.push({ scan: { weightKg: 70, pbfPct: 20 }, profile: { heightCm: 175, sex: 'male' }, prev: null });
  out.push({ scan: { weightKg: 70, bfmKg: 14, ffmKg: 56, measuredAt: '2026-01-01T00:00:00.000Z' },
             profile: { heightCm: 175 },
             prev: { weightKg: 70, bfmKg: 14, ffmKg: 56, smmKg: 31, measuredAt: '2026-01-01T00:00:00.000Z' } });
  out.push({ scan: { weightKg: 70, measuredAt: 'not-a-date' }, profile: {},
             prev: { weightKg: 70, measuredAt: '2026-01-01T00:00:00.000Z' } });

  while (out.length < n) {
    const base = plausible(rnd);
    const scan = Object.assign({}, base.scan);
    const howMany = (rnd() * 3) | 0;
    for (let i = 0; i < howMany; i++) BREAKERS[(rnd() * BREAKERS.length) | 0](scan, rnd);

    const profile = {};
    if (rnd() > 0.15) profile.heightCm = base.heightCm;
    if (rnd() > 0.3) profile.sex = rnd() > 0.5 ? 'male' : 'female';
    if (rnd() > 0.9) profile.heightCm = 0;

    let prev = null;
    if (rnd() > 0.35) {
      const p = plausible(rnd);
      prev = Object.assign({}, p.scan);
      if (rnd() > 0.7) BREAKERS[(rnd() * BREAKERS.length) | 0](prev, rnd);
      /* 날짜: 있음 · 없음 · 뒤집힘(backfill) · 같은 시각 */
      const roll = rnd();
      if (roll > 0.25) {
        const days = Math.round((rnd() - 0.3) * 200);      // 음수도 나옵니다
        const t0 = Date.UTC(2026, 0, 15);
        prev.measuredAt = new Date(t0).toISOString();
        scan.measuredAt = new Date(t0 + days * 86400000).toISOString();
      } else if (roll > 0.15) {
        prev.measuredAt = '2026-01-15T00:00:00.000Z';
        scan.measuredAt = '2026-01-15T00:00:00.000Z';      // 같은 시각
      }
    }
    out.push({ scan, profile, prev });
  }
  return out.slice(0, n);
}

/* --- JS 쪽 실행 ---------------------------------------------------------- */
function runJs(module, cases) {
  const g = { window: undefined };
  const sandbox = {};
  // crosscheck.js 는 MB_MODES 를 읽습니다 (없으면 기본값).
  global.MB_MODES = global.MB_MODES || { NOISE: { weight: 1.0, smm: 0.6, bfm: 1.0 } };
  const mod = require(path.join(ROOT, 'prototype', 'js', module + '.js'));
  return cases.map(c => {
    try { return { ok: true, v: mod.run(c.scan, c.profile, c.prev) }; }
    catch (e) { return { ok: false, v: String(e && e.message || e) }; }
  });
}

/* --- Dart 쪽 실행 -------------------------------------------------------- */
function runDart(module, casesFile) {
  const r = spawnSync(DART, ['run', path.join(PKG, 'bin', 'diffrun.dart'), module, casesFile],
    { cwd: PKG, encoding: 'utf8', timeout: 300000, maxBuffer: 256 * 1024 * 1024 });
  if (r.status !== 0) {
    return { error: (r.stderr || r.stdout || '').trim().split('\n').slice(0, 20).join('\n') };
  }
  try { return { list: JSON.parse(r.stdout) }; }
  catch (e) { return { error: 'Dart 출력이 JSON 이 아닙니다:\n' + (r.stdout || '').slice(0, 500) }; }
}

/* --- 비교 ----------------------------------------------------------------- */
/** 깊은 비교. 다르면 **어디가** 다른지 경로를 돌려줍니다. */
function diff(a, b, at) {
  at = at || '';
  if (a === b) return null;
  if (typeof a === 'number' && typeof b === 'number') {
    if (Number.isNaN(a) && Number.isNaN(b)) return null;
    /* 부동소수 찌꺼기까지 실패로 치면 진짜 차이가 묻힙니다.
       다만 아주 좁게 봅니다 — 0.5 반올림 차이는 걸려야 합니다. */
    if (Math.abs(a - b) < 1e-9) return null;
    return { at, js: a, dart: b };
  }
  if (a === null || b === null || typeof a !== typeof b) return { at, js: a, dart: b };
  if (Array.isArray(a) !== Array.isArray(b)) return { at, js: a, dart: b };
  if (typeof a !== 'object') return { at, js: a, dart: b };
  if (Array.isArray(a)) {
    if (a.length !== b.length) return { at: at + '.length', js: a.length, dart: b.length };
    for (let i = 0; i < a.length; i++) {
      const d = diff(a[i], b[i], at + '[' + i + ']');
      if (d) return d;
    }
    return null;
  }
  const keys = Array.from(new Set(Object.keys(a).concat(Object.keys(b)))).sort();
  for (const k of keys) {
    const d = diff(a[k], b[k], at ? at + '.' + k : k);
    if (d) return d;
  }
  return null;
}

/* Dart 가 없는 컴퓨터에서는 **건너뜁니다.**
   주인의 윈도우 노트북에는 Dart 가 없습니다. 거기서 배포 전 점검이
   "✗ 옮긴 로직" 으로 막히면, 앱과 아무 상관 없는 이유로 배포가 막히는
   셈입니다. 없으면 없다고 말하고 통과시킵니다 — 이 검사는 Dart 를
   깐 곳(여기, 그리고 CI)에서 의미가 있습니다. */
if (!fs.existsSync(DART)) {
  console.log('\nDart 가 없어서 건너뜁니다 (' + DART + ').');
  console.log('옮긴 로직을 검증하려면 Dart SDK 를 깔고 다시 돌리세요.');
  process.exit(0);
}

const MODULES = ['crosscheck'];
let failed = 0;

for (const m of MODULES) {
  if (ONLY && ONLY !== m) continue;
  process.stdout.write('\n' + m + ' — 사례 ' + N + '개 (씨앗 ' + SEED + ')\n');

  const cases = makeCases(N, SEED);
  const tmp = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'mybody-diff-')), 'cases.json');
  fs.writeFileSync(tmp, JSON.stringify(cases));

  const js = runJs(m, cases);
  const dr = runDart(m, tmp);
  if (dr.error) {
    console.log('  ✗ Dart 쪽이 못 돌았습니다:\n' + dr.error.split('\n').map(l => '    ' + l).join('\n'));
    failed++;
    continue;
  }
  const dart = dr.list;
  if (dart.length !== js.length) {
    console.log('  ✗ 사례 개수가 다릅니다: JS ' + js.length + ' · Dart ' + dart.length);
    failed++;
    continue;
  }

  const bad = [];
  for (let i = 0; i < js.length; i++) {
    const d = diff(js[i], dart[i]);
    if (d) bad.push({ i, d, input: cases[i] });
    if (bad.length >= 5) break;
  }

  if (!bad.length) {
    console.log('  ✓ ' + N + '개 전부 같은 답을 냅니다');
  } else {
    failed++;
    console.log('  ✗ ' + bad.length + '개 이상 갈립니다. 처음 것들:');
    for (const b of bad) {
      console.log('    사례 #' + b.i + '  ' + b.d.at);
      console.log('      JS   ' + JSON.stringify(b.d.js));
      console.log('      Dart ' + JSON.stringify(b.d.dart));
      if (KEEP) {
        const f = path.join(ROOT, 'tools', '.shots', 'diff-' + m + '-' + b.i + '.json');
        fs.mkdirSync(path.dirname(f), { recursive: true });
        fs.writeFileSync(f, JSON.stringify(b.input, null, 2));
        console.log('      입력: ' + f);
      } else {
        console.log('      입력: ' + JSON.stringify(b.input).slice(0, 300));
      }
    }
    console.log('    (--keep 을 붙이면 갈린 입력을 파일로 남깁니다)');
  }
  fs.rmSync(path.dirname(tmp), { recursive: true, force: true });
}

console.log('');
process.exit(failed ? 1 : 0);
