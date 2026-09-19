/* =============================================================================
 * tools/add-scan.js — 새 인바디 결과지를 넣어 보고, 무엇이 달라지는지 본다
 *
 *   node tools/add-scan.js '{"measuredAt":"2026-11-20T08:30:00",
 *                            "weightKg":85.2,"smmKg":38.2,"bfmKg":18.1}'
 *   node tools/add-scan.js scan.json
 *   node tools/add-scan.js --seed          시드에 추가할 코드 조각까지 출력
 *
 * 하는 일 (아무것도 저장하지 않습니다 — 보기만 합니다)
 *   1. 결과지 안에서 검산합니다 (crosscheck.js — 앱과 같은 것)
 *   2. 지난 측정과 비교합니다. 오차 안인지 밖인지 같이 말합니다
 *   3. 지금 계획이 있다면, 이 측정이 계획을 어떻게 바꾸는지 봅니다
 *
 * 왜 따로 만드는가
 *   새 측정을 앱에 넣기 전에 "이 숫자들이 서로 맞나" 를 먼저 보는 게
 *   낫습니다. 결과지를 잘못 읽었으면 그 값이 몇 주짜리 계획을 정하고,
 *   틀린 채로 4주를 보내면 사용자는 "앱이 틀렸다" 가 아니라 "내 몸이
 *   이상하다" 고 결론짓습니다.
 * ========================================================================== */
'use strict';
global.window = global;
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..');
['data', 'modes', 'modes-copy', 'fooddb', 'engine', 'crosscheck']
  .forEach(f => require(path.join(ROOT, 'prototype', 'js', f + '.js')));

const E = window.MB_ENGINE, C = window.MB_CHECK, D = window.MB_DATA;

/* --- 입력 ---------------------------------------------------------------- */
const argv = process.argv.slice(2);
const wantSeed = argv.includes('--seed');
let goalArg = null;
const gi = argv.indexOf('--goal');
if (gi >= 0 && argv[gi + 1]) { goalArg = argv[gi + 1]; argv.splice(gi, 2); }
const arg = argv.filter(a => a !== '--seed')[0];
if (!arg) {
  console.error('쓰는 법:');
  console.error('  node tools/add-scan.js \'{"measuredAt":"2026-11-20T08:30:00",');
  console.error('                           "weightKg":85.2,"smmKg":38.2,"bfmKg":18.1}\'');
  console.error('  node tools/add-scan.js scan.json');
  console.error('');
  console.error('핵심은 넷입니다 — 측정일시 · 체중 · 골격근량 · 체지방량.');
  console.error('결과지에 있는 다른 값(체지방률 · BMI · 체수분 · 단백질 · 무기질 ·');
  console.error('기초대사량 · 복부지방률 · InBody 점수)도 넣으면 검산이 더 촘촘해집니다.');
  console.error('');
  console.error('목표까지 보려면:');
  console.error('  --goal \'{"weightKg":78,"smmKg":38.9,"bfmKg":12}\'');
  console.error('시드에 넣을 코드까지 보려면:  --seed');
  process.exit(1);
}

let scan;
try {
  scan = JSON.parse(fs.existsSync(arg) ? fs.readFileSync(arg, 'utf8') : arg);
} catch (e) {
  console.error('JSON 을 읽지 못했습니다:', e.message);
  process.exit(1);
}

const prof = D.SEED_PROFILE;
const prev = D.SEED_SCANS[D.SEED_SCANS.length - 1];

function n1(x) { return x == null ? '—' : (Math.round(x * 10) / 10).toFixed(1); }
function sign(x) { return (x > 0 ? '+' : x < 0 ? '−' : '±') + n1(Math.abs(x)); }

console.log('\n' + '─'.repeat(56));
console.log('새 측정  ' + (scan.measuredAt || '(측정일시 없음)'));
console.log('─'.repeat(56));

/* --- 1. 검산 ------------------------------------------------------------- */
const r = C.run(scan, prof, prev);
console.log('\n[검산]  ' + (
  r.status === 'ok' ? '맞아떨어집니다'
  : r.status === 'conflict' ? '어긋나는 곳이 있습니다'
  : '한 번 확인해 주세요'));

r.checks.forEach(c => console.log('  ' + (c.ok ? '✓' : '✗') + ' ' + c.why));
r.rangeIssues.concat(r.deltaIssues).forEach(i =>
  console.log('  ' + (i.level === 'bad' ? '✗' : '!') + ' ' + i.why));
if (r.suspect) console.log('\n  → 틀렸을 가능성이 높은 칸: ' + r.suspect);
if (r.involved) console.log('\n  → 이 중 하나가 어긋납니다: ' + r.involved.join(' · '));
r.suggestions.forEach(s => console.log('  → ' + s.why));

const printed = Object.keys(r.fields).length;
console.log('\n  검산된 칸 ' + Object.values(r.fields).filter(x => x === 'verified').length +
            ' / 어긋난 칸 ' + Object.values(r.fields).filter(x => x === 'conflict').length +
            ' (인쇄된 칸 ' + printed + '개 기준)');

/* --- 2. 지난 측정과 비교 -------------------------------------------------- */
const NOISE = window.MB_MODES.NOISE;
const FLOOR = { weightKg: NOISE.weight * Math.SQRT2,
                smmKg: NOISE.smm * Math.SQRT2,
                bfmKg: NOISE.bfm * Math.SQRT2 };

console.log('\n[지난 측정과]  ' + prev.measuredAt.slice(0, 10) + ' → ' +
            String(scan.measuredAt || '').slice(0, 10));
const gapDays = Math.round((Date.parse(scan.measuredAt) - Date.parse(prev.measuredAt)) / 86400000);
if (isFinite(gapDays)) console.log('  ' + gapDays + '일 만');

const a = E.derive(prev, prof);
let b = null;
try { b = E.derive(scan, prof); } catch (e) { b = null; }
if (b) {
  [['체중', 'weightKg'], ['골격근량', 'smmKg'], ['체지방량', 'bfmKg']].forEach(([label, k]) => {
    const d = b[k] - a[k];
    const under = Math.abs(d) < FLOOR[k];
    console.log('  ' + label.padEnd(6) + ' ' + n1(a[k]) + ' → ' + n1(b[k]) +
                '  ' + sign(d) + 'kg' +
                (under ? '   (오차 안 — 변했는지 알 수 없습니다)' : ''));
  });
  console.log('\n  오차 문턱: 체중 ' + n1(FLOOR.weightKg) + ' · 골격근 ' +
              n1(FLOOR.smmKg) + ' · 체지방 ' + n1(FLOOR.bfmKg) + 'kg');
}

/* --- 3. 계획이 어떻게 달라지나 --------------------------------------------
   목표는 시드에 없습니다 — 앱에서 사람이 정하는 것이라서요.
   그래서 여기서는 인자로 받습니다. 안 주면 이 칸은 건너뜁니다. */
let goal = null;
if (goalArg) {
  try { goal = JSON.parse(goalArg); }
  catch (e) { console.log('\n[계획]  --goal 을 읽지 못했습니다: ' + e.message); }
}
if (b && goal) {
  console.log('\n[계획]  목표 체중 ' + n1(goal.weightKg) + ' · 골격근 ' +
              n1(goal.smmKg) + ' · 체지방 ' + n1(goal.bfmKg) + 'kg');
  const today = String(scan.measuredAt || '').slice(0, 10);
  [['이 측정으로', scan], ['지난 측정으로', prev]].forEach(([label, s]) => {
    try {
      const cmp = E.compareLevels(s, prof, goal, today, null, null);
      const p = E.buildPlan(cmp, 'mid', s, prof);
      console.log('  ' + label.padEnd(10) + ' ' +
                  (p ? p.weeks + '주 · ' + p.targetDate : '계획을 만들지 못했습니다'));
    } catch (e) {
      console.log('  ' + label.padEnd(10) + ' 오류: ' + e.message.slice(0, 60));
    }
  });
  console.log('\n  두 줄의 차이는 이 측정 한 번이 만든 것입니다.');
  console.log('  측정 오차만으로도 도착일은 몇 주씩 움직입니다.');
} else if (b && !goalArg) {
  console.log('\n[계획]  --goal 을 주면 이 측정이 목표일을 어떻게 바꾸는지 같이 봅니다.');
}

/* --- 4. 플래너가 받아 주는가 ---------------------------------------------- */
const bad = E.validateScan(scan, prev);
console.log('\n[플래너]  ' + (bad ? '받지 않습니다' : '받습니다'));
if (bad) bad.reasons.forEach(x => console.log('  · ' + x));

/* --- 5. 시드에 넣을 코드 --------------------------------------------------- */
if (wantSeed) {
  const id = 'scan-' + String(scan.measuredAt || '').replace(/[^0-9]/g, '').slice(0, 8);
  const keys = ['measuredAt', 'weightKg', 'smmKg', 'bfmKg', 'pbfPct', 'ffmKg', 'bmi',
                'tbwL', 'proteinKg', 'mineralKg', 'bmrKcal', 'whr', 'inbodyScore',
                'visceralFatLevel', 'idealWeightKg'];
  console.log('\n[시드에 넣을 코드]  prototype/js/data.js 의 SEED_SCANS 끝에');
  console.log('    {');
  console.log("      id: '" + id + "',");
  keys.forEach(k => {
    if (scan[k] == null) return;
    console.log('      ' + k + ': ' + (typeof scan[k] === 'string' ? "'" + scan[k] + "'" : scan[k]) + ',');
  });
  console.log("      source: 'sheet', device: '" + (scan.device || 'InBody270') + "', partial: false");
  console.log('    }');
}

console.log('\n' + '─'.repeat(56));
console.log('아무것도 저장하지 않았습니다. 앱에 실제로 넣으려면');
console.log('앱에서 인바디 넣기 → 사진 + 숫자 세 칸을 쓰세요.\n');
