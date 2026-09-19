/* =============================================================================
 * tools/validate.js — 실증 검증 하네스 (empirical validation harness)
 *
 *   cd /home/user/Mybody && NODE_PATH=/opt/node22/lib/node_modules node tools/validate.js
 *
 * 목적: engine.js 의 주차별 시뮬레이션을, 내부 논리가 아니라 **실제 발표된
 * 개입연구 데이터**에 대고 맞춰 본다. 엔진은 한 줄도 고치지 않는다.
 * (허용된 변경: engine.js 에 stepWeek 하나를 export 한 것뿐.)
 *
 * 이 하네스가 틀릴 수 있는 지점은 REPORT 하단 "TRANSLATION ASSUMPTIONS" 에
 * 전부 적어 둔다. 엔진이 틀린 것과 번역이 틀린 것을 섞으면 검증이 아니다.
 * ========================================================================== */
'use strict';
const path = require('node:path');
const fs = require('node:fs');

global.window = global;
require(path.join(__dirname, '..', 'prototype', 'js', 'data.js'));
require(path.join(__dirname, '..', 'prototype', 'js', 'modes.js'));
require(path.join(__dirname, '..', 'prototype', 'js', 'engine.js'));
const E = global.MB_ENGINE;

if (typeof E.stepWeek !== 'function') {
  throw new Error('engine.js 가 stepWeek 을 export 하지 않습니다. 하네스는 엔진을 복제하지 않습니다.');
}

const CASES_PATH = path.join(__dirname, 'validation-cases.json');
const OUT_PATH   = path.join(__dirname, 'validation-results.json');
const CASES = JSON.parse(fs.readFileSync(CASES_PATH, 'utf8'));

/* ---------------------------------------------------------------------------
 * 0. 전역 번역 상수
 * ------------------------------------------------------------------------- */
const K_SMM_TO_FFM = 0.55;   // ★ 최대 번역 오차원. 연구는 FFM, 엔진 상태변수는 SMM.
const PAL_KEYS = ['sedentary', 'light', 'moderate', 'active', 'veryActive'];
const DEFAULT_AGE = 30;
const DEFAULT_H = { male: 175, female: 163, mixed: 175 };

/* 'mixed' 성별을 엔진의 male/female 이분법에 억지로 밀어 넣는다.
 * male 을 고르면 근성장 천장이 2배(sexFactor 1.0 vs 0.5)가 되고 제지방 손실
 * 트리거 체지방률도 10% vs 18% 로 바뀐다. 두 선택 다 오차를 만든다.
 * 여기서는 male 로 고정하고, 그게 어느 방향으로 틀리는지 기록만 한다. */
function engineSex(sex) { return sex === 'female' ? 'female' : 'male'; }

/* ---------------------------------------------------------------------------
 * 1. 케이스 -> 엔진 입력
 * ------------------------------------------------------------------------- */
function buildProfile(c, activityLevel) {
  return {
    sex: engineSex(c.sex),
    age: c.ageYears != null ? c.ageYears : DEFAULT_AGE,
    heightCm: c.heightCm != null ? c.heightCm : DEFAULT_H[c.sex] || DEFAULT_H.male,
    activityLevel: activityLevel,
    trainingAge: c.trainingStatus,
    daysPerWeek: Math.min(6, Math.max(3, c.resistanceTrainingDaysPerWeek || 3)),
    sessionMinutes: 60,
    mealsPerDay: 3,
    hadPriorPeak: false
  };
}

function buildScan(c) {
  return {
    measuredAt: '2020-01-01',
    weightKg: c.baselineWeightKg,
    bfmKg: c.baselineFatMassKg,
    ffmKg: c.baselineLeanMassKg,
    smmKg: c.baselineLeanMassKg * K_SMM_TO_FFM
    // bmrKcal 은 일부러 주지 않는다 -> derive() 가 Katch-McArdle 을 쓴다
  };
}

/* 연구가 함의하는 TDEE. deficitKcalPerDay / deficitPctOfTdee 둘 다 있을 때만.
 * (부호 규약: deficitPctOfTdee 는 적자가 +, 잉여가 -) */
function impliedTdee(c) {
  if (c.deficitKcalPerDay == null || !c.deficitPctOfTdee) return null;
  const v = Math.abs(c.deficitKcalPerDay) / Math.abs(c.deficitPctOfTdee);
  return (isFinite(v) && v > 800 && v < 6000) ? v : null;
}

/* PAL 선택: 함의 TDEE 가 있으면 5개 PAL 중 가장 가까운 것.
 * 없으면 훈련량 기반 폴백(그리고 그 사실을 이유에 적는다). */
function chooseActivity(c) {
  const ffm = c.baselineLeanMassKg;
  const bmr = 370 + 21.6 * ffm;
  const target = impliedTdee(c);
  if (target != null) {
    let best = null;
    for (const key of PAL_KEYS) {
      const tdee = bmr * E.PAL[key].mult;
      const err = Math.abs(tdee - target);
      if (!best || err < best.err) best = { key, tdee, err };
    }
    return {
      key: best.key,
      reason: `implied TDEE ${Math.round(target)} kcal (= |${c.deficitKcalPerDay}| / ${Math.abs(c.deficitPctOfTdee)}); ` +
              `Katch BMR ${Math.round(bmr)} x PAL ${E.PAL[best.key].mult} = ${Math.round(best.tdee)} ` +
              `(off by ${Math.round(best.err)} kcal, the closest of the engine's five)`,
      targetTdee: Math.round(target),
      engineTdee: Math.round(best.tdee),
      matched: true
    };
  }
  // 폴백: 주당 훈련일 + 유산소 처방
  const d = c.resistanceTrainingDaysPerWeek || 0;
  const hasCardio = c.cardioDescription && !/none prescribed|No cardio|No exercise/i.test(c.cardioDescription);
  let key;
  if (d === 0 && !hasCardio) key = 'moderate';      // 좌식은 아니고 자유생활 성인
  else if (d <= 3) key = 'moderate';
  else if (d <= 5) key = 'active';
  else key = 'veryActive';
  return {
    key,
    reason: `no implied TDEE (deficitKcalPerDay missing or zero); fallback from training load ` +
            `(${d} RT d/wk, cardio=${hasCardio ? 'yes' : 'no'}) -> PAL ${E.PAL[key].mult}, ` +
            `engine TDEE ${Math.round(bmr * E.PAL[key].mult)} kcal`,
    targetTdee: null,
    engineTdee: Math.round(bmr * E.PAL[key].mult),
    matched: false
  };
}

/* ---------------------------------------------------------------------------
 * 2. 연구의 실제 처방에 해당하는 공격성 a 역산
 * ------------------------------------------------------------------------- */
function phaseOf(c) {
  const d = c.deficitPctOfTdee;
  if (d == null) return 'maintain';
  if (d < -0.02) return 'bulk';
  if (d > 0.02) return 'cut';
  return 'maintain';
}

/* paramsAt 을 0..1 로 훑어서, 연구의 deficitPct(또는 surplusPct)에 가장 가까운 a. */
function invertA(c, phase) {
  const target = Math.abs(c.deficitPctOfTdee || 0);
  const mode = phase === 'bulk' ? 'bulk' : 'cut';
  const field = phase === 'bulk' ? 'surplusPct' : 'deficitPct';
  let best = null;
  for (let i = 0; i <= 10000; i++) {
    const a = i / 10000;
    const p = E.paramsAt(a, mode, null);
    const err = Math.abs(p[field] - target);
    if (!best || err < best.err) best = { a, err, value: p[field] };
  }
  const R = mode === 'bulk' ? E.BULK_RANGE.surplusPct : E.CUT_RANGE.deficitPct;
  const lo = Math.min(R[0], R[1]), hi = Math.max(R[0], R[1]);
  // 'maintain' 국면에서는 stepWeek 이 deficitPct 를 읽지 않으므로 클램프는 무의미하다.
  const clamped = phase !== 'maintain' && (target < lo - 1e-9 || target > hi + 1e-9);
  return {
    a: best.a,
    achieved: best.value,
    target,
    clamped,
    clampNote: clamped
      ? `study ${(target * 100).toFixed(1)}% is OUTSIDE the engine's ${field} range ` +
        `[${(lo * 100).toFixed(1)}%..${(hi * 100).toFixed(1)}%]; clamped to ${(best.value * 100).toFixed(1)}% ` +
        `(the engine literally cannot run this study's prescription)`
      : null
  };
}

/* ---------------------------------------------------------------------------
 * 3. 시뮬레이션 — 엔진의 stepWeek 을 그대로 쓴다 (복제 아님)
 * ------------------------------------------------------------------------- */
function simulate(c, profile, params, phase, k, weeks) {
  let st = {
    smmKg: c.baselineLeanMassKg * k,
    bfmKg: c.baselineFatMassKg
  };
  const log = [];
  const whole = Math.floor(weeks + 1e-9);
  const frac = weeks - whole;
  let leanLossTotal = 0, anyCapped = false, anyFloored = false;

  for (let wk = 1; wk <= whole; wk++) {
    const r = E.stepWeek(st, phase, params, profile, k);
    st = { smmKg: r.state.smmKg, bfmKg: r.state.bfmKg };
    leanLossTotal += r.leanLoss || 0;
    anyCapped = anyCapped || r.capped;
    anyFloored = anyFloored || r.floored;
    if (wk <= 3 || wk === whole) {
      log.push({ week: wk, tdee: r.tdee, intake: r.intake, deficit: r.deficit,
                 smmKg: +st.smmKg.toFixed(3), bfmKg: +st.bfmKg.toFixed(3) });
    }
  }
  // 소수 주(8.5주, 5.3주)는 마지막 한 주의 델타를 비례 배분한다.
  if (frac > 1e-9) {
    const r = E.stepWeek(st, phase, params, profile, k);
    const smmDelta = r.state.smmKg - st.smmKg;
    const bfmDelta = r.state.bfmKg - st.bfmKg;
    st = {
      smmKg: Math.max(1, st.smmKg + smmDelta * frac),
      bfmKg: Math.max(0.5, st.bfmKg + bfmDelta * frac)
    };
    leanLossTotal += (r.leanLoss || 0) * frac;
    anyCapped = anyCapped || r.capped;
    anyFloored = anyFloored || r.floored;
    log.push({ week: +(whole + frac).toFixed(2), partial: frac, tdee: r.tdee,
               intake: r.intake, deficit: r.deficit,
               smmKg: +st.smmKg.toFixed(3), bfmKg: +st.bfmKg.toFixed(3) });
  }

  const ffm = st.smmKg / k;                 // ★ 역변환: SMM -> FFM
  return {
    endLeanKg: ffm,
    endFatKg: st.bfmKg,
    endWeightKg: ffm + st.bfmKg,
    leanLossTotalKg: leanLossTotal,
    capped: anyCapped, floored: anyFloored,
    log
  };
}

/* ---------------------------------------------------------------------------
 * 4. 케이스 실행
 * ------------------------------------------------------------------------- */
function runCase(c) {
  const act = chooseActivity(c);
  const profile = buildProfile(c, act.key);
  const scan = buildScan(c);
  const derived = E.derive(scan, profile);
  const phase = phaseOf(c);
  const inv = invertA(c, phase);
  const k = K_SMM_TO_FFM;

  const params = E.paramsAt(inv.a, phase === 'bulk' ? 'bulk' : 'cut', null);

  /* 단백질: 엔진의 leanLossPerWeek 는 params.proteinPerFFM 을 읽는다. a 로
   * 보간된 값이 아니라 **연구가 실제로 먹인 단백질**을 넣어야 프로토콜을
   * 충실히 번역한 것이다. (엔진 로직 변경 아님 — 입력 변경) */
  const proteinPerFfmStudy = c.proteinGPerKgBW != null
    ? c.proteinGPerKgBW * c.baselineWeightKg / c.baselineLeanMassKg
    : null;
  const paramsStudy = Object.assign({}, params);
  if (proteinPerFfmStudy != null) paramsStudy.proteinPerFFM = proteinPerFfmStudy;

  const sim    = simulate(c, profile, paramsStudy, phase, k, c.weeks);
  const simAlt = simulate(c, profile, params,      phase, k, c.weeks);  // a-보간 단백질 사용 시

  const pred = {
    deltaWeightKg: sim.endWeightKg - c.baselineWeightKg,
    deltaFatMassKg: sim.endFatKg - c.baselineFatMassKg,
    deltaLeanMassKg: sim.endLeanKg - c.baselineLeanMassKg
  };
  const act3 = {
    deltaWeightKg: c.deltaWeightKg,
    deltaFatMassKg: c.deltaFatMassKg,
    deltaLeanMassKg: c.deltaLeanMassKg
  };
  const err = {};
  const errPct = {};
  for (const key of Object.keys(act3)) {
    err[key] = pred[key] - act3[key];
    errPct[key] = Math.abs(act3[key]) > 1e-9 ? (err[key] / Math.abs(act3[key])) * 100 : null;
  }

  return {
    id: c.id,
    groupLabel: c.groupLabel,
    citation: c.citation,
    sweep: c.sweep,
    direction: phase === 'cut' ? 'cut' : (phase === 'bulk' ? 'bulk' : 'recomp'),
    trainingStatus: c.trainingStatus,
    sex: c.sex,
    weeks: c.weeks,
    n: c.n,
    measurementMethod: c.measurementMethod,
    translation: {
      kSmmToFfm: k,
      baselineLeanMassKg: c.baselineLeanMassKg,
      baselineSmmKg: +(c.baselineLeanMassKg * k).toFixed(3),
      engineSex: profile.sex,
      age: profile.age,
      heightCm: profile.heightCm,
      trainingAge: profile.trainingAge
    },
    pal: {
      activityLevel: act.key,
      mult: E.PAL[act.key].mult,
      impliedStudyTdee: act.targetTdee,
      engineTdeeAtBaseline: act.engineTdee,
      engineDerivedTdee: derived.tdeeKcal,
      matchedToStudy: act.matched,
      reason: act.reason
    },
    aggressiveness: {
      phase,
      a: +inv.a.toFixed(4),
      studyTargetPct: +(inv.target * 100).toFixed(2),
      engineAchievedPct: +(inv.achieved * 100).toFixed(2),
      clamped: inv.clamped,
      clampNote: inv.clampNote,
      ratePctPerWeek: params.ratePct != null ? +(params.ratePct * 100).toFixed(3) : null,
      leanFraction: params.leanFraction != null ? +params.leanFraction.toFixed(3) : null,
      proteinPerFfmFromA: +params.proteinPerFFM.toFixed(2),
      proteinPerFfmFromStudy: proteinPerFfmStudy != null ? +proteinPerFfmStudy.toFixed(2) : null
    },
    predicted: {
      deltaWeightKg: +pred.deltaWeightKg.toFixed(2),
      deltaFatMassKg: +pred.deltaFatMassKg.toFixed(2),
      deltaLeanMassKg: +pred.deltaLeanMassKg.toFixed(2),
      engineLeanLossPathKg: +sim.leanLossTotalKg.toFixed(3),
      mobilizationCapHit: sim.capped,
      intakeFloorHit: sim.floored
    },
    predictedWithAProtein: {
      deltaWeightKg: +(simAlt.endWeightKg - c.baselineWeightKg).toFixed(2),
      deltaFatMassKg: +(simAlt.endFatKg - c.baselineFatMassKg).toFixed(2),
      deltaLeanMassKg: +(simAlt.endLeanKg - c.baselineLeanMassKg).toFixed(2)
    },
    actual: act3,
    error: {
      deltaWeightKg: +err.deltaWeightKg.toFixed(2),
      deltaFatMassKg: +err.deltaFatMassKg.toFixed(2),
      deltaLeanMassKg: +err.deltaLeanMassKg.toFixed(2)
    },
    errorPct: {
      deltaWeightKg: errPct.deltaWeightKg == null ? null : +errPct.deltaWeightKg.toFixed(0),
      deltaFatMassKg: errPct.deltaFatMassKg == null ? null : +errPct.deltaFatMassKg.toFixed(0),
      deltaLeanMassKg: errPct.deltaLeanMassKg == null ? null : +errPct.deltaLeanMassKg.toFixed(0)
    },
    weeklyLog: sim.log,
    inferredFields: c.inferredFields || [],
    notes: c.notes
  };
}

/* ---------------------------------------------------------------------------
 * 5. 통계
 * ------------------------------------------------------------------------- */
const OUTCOMES = ['deltaWeightKg', 'deltaFatMassKg', 'deltaLeanMassKg'];
const OUT_LABEL = { deltaWeightKg: 'weight', deltaFatMassKg: 'fat mass', deltaLeanMassKg: 'lean mass' };

function stats(rows) {
  const out = {};
  for (const key of OUTCOMES) {
    const e = rows.map(r => r.error[key]);
    const mean = e.reduce((a, b) => a + b, 0) / e.length;
    const mae = e.reduce((a, b) => a + Math.abs(b), 0) / e.length;
    const sd = Math.sqrt(e.reduce((a, b) => a + (b - mean) ** 2, 0) / Math.max(1, e.length - 1));
    const signs = e.filter(x => Math.abs(x) > 0.05);
    const over = signs.filter(x => x > 0).length;
    out[key] = {
      n: e.length,
      meanError: +mean.toFixed(2),
      meanAbsError: +mae.toFixed(2),
      sdError: +sd.toFixed(2),
      maxAbsError: +Math.max(...e.map(Math.abs)).toFixed(2),
      bias: mean > 0.05 ? 'over-predicts (predicted > actual)'
          : mean < -0.05 ? 'under-predicts (predicted < actual)' : 'unbiased',
      overPredictedCount: over,
      underPredictedCount: signs.length - over
    };
  }
  return out;
}

function groupBy(rows, fn) {
  const m = new Map();
  for (const r of rows) {
    const g = fn(r);
    if (!m.has(g)) m.set(g, []);
    m.get(g).push(r);
  }
  return m;
}

/* ---------------------------------------------------------------------------
 * 6. 출력
 * ------------------------------------------------------------------------- */
function pad(s, w, right) {
  s = String(s);
  if (s.length > w) s = s.slice(0, w - 1) + '…';
  return right ? s.padStart(w) : s.padEnd(w);
}
function num(x, d) { return x == null ? '  n/a' : (x >= 0 ? '+' : '') + x.toFixed(d == null ? 2 : d); }
function rule(ch, w) { return (ch || '-').repeat(w || 150); }

function printMainTable(rows) {
  const W = [22, 5, 4, 6, 6, 8, 8, 8, 8, 8, 8, 8, 8, 8, 7];
  const head = ['case', 'dir', 'wk', 'a', 'PAL',
                'ΔW pred', 'ΔW act', 'ΔW err',
                'ΔFM pred', 'ΔFM act', 'ΔFM err',
                'ΔLM pred', 'ΔLM act', 'ΔLM err', 'LM err%'];
  console.log(rule('=', 148));
  console.log(head.map((h, i) => pad(h, W[i], i > 4)).join(' '));
  console.log(rule('-', 148));
  for (const r of rows) {
    const cells = [
      pad(r.id, W[0]),
      pad(r.direction === 'recomp' ? 'rcmp' : r.direction, W[1]),
      pad(r.weeks, W[2], true),
      pad(r.aggressiveness.a.toFixed(2), W[3], true),
      pad(r.pal.mult.toFixed(3), W[4], true),
      pad(num(r.predicted.deltaWeightKg), W[5], true),
      pad(num(r.actual.deltaWeightKg), W[6], true),
      pad(num(r.error.deltaWeightKg), W[7], true),
      pad(num(r.predicted.deltaFatMassKg), W[8], true),
      pad(num(r.actual.deltaFatMassKg), W[9], true),
      pad(num(r.error.deltaFatMassKg), W[10], true),
      pad(num(r.predicted.deltaLeanMassKg), W[11], true),
      pad(num(r.actual.deltaLeanMassKg), W[12], true),
      pad(num(r.error.deltaLeanMassKg), W[13], true),
      pad(r.errorPct.deltaLeanMassKg == null ? 'n/a' : r.errorPct.deltaLeanMassKg + '%', W[14], true)
    ];
    console.log(cells.join(' '));
  }
  console.log(rule('=', 148));
}

function printStats(title, s) {
  console.log('\n' + title);
  console.log(rule('-', 96));
  console.log(pad('outcome', 12) + pad('n', 5, true) + pad('mean err', 11, true) +
              pad('MAE', 9, true) + pad('SD', 9, true) + pad('max |err|', 11, true) +
              '  ' + pad('over/under', 12) + 'bias');
  for (const key of OUTCOMES) {
    const v = s[key];
    console.log(pad(OUT_LABEL[key], 12) + pad(v.n, 5, true) + pad(num(v.meanError), 11, true) +
                pad(v.meanAbsError.toFixed(2), 9, true) + pad(v.sdError.toFixed(2), 9, true) +
                pad(v.maxAbsError.toFixed(2), 11, true) + '  ' +
                pad(v.overPredictedCount + ' / ' + v.underPredictedCount, 12) + v.bias);
  }
}

/* ---------------------------------------------------------------------------
 * 7. main
 * ------------------------------------------------------------------------- */
const rows = CASES.filter(c => c.usableForSimulation !== false).map(runCase);
const sorted = rows.slice().sort(
  (a, b) => Math.abs(b.error.deltaLeanMassKg) - Math.abs(a.error.deltaLeanMassKg));

console.log('\nMYBODY ENGINE — EMPIRICAL VALIDATION AGAINST PUBLISHED INTERVENTION DATA');
console.log('engine: prototype/js/engine.js (unmodified except one stepWeek export)');
console.log(`cases: ${rows.length}   |   SMM = FFM x ${K_SMM_TO_FFM} (the single biggest translation assumption)`);
console.log('sorted by |lean-mass error|, worst first\n');
printMainTable(sorted);

console.log('\nPAL CHOICES (activityLevel picked so engine TDEE tracks the study\'s implied TDEE)');
console.log(rule('-', 150));
for (const r of rows) {
  console.log(pad(r.id, 26) + pad(r.pal.activityLevel, 12) + pad('x' + r.pal.mult, 8) +
              pad(r.pal.impliedStudyTdee == null ? 'study n/a' : r.pal.impliedStudyTdee + ' kcal', 12, true) +
              pad(r.pal.engineTdeeAtBaseline + ' kcal', 12, true) +
              pad(r.pal.impliedStudyTdee == null ? '' :
                  num(r.pal.engineTdeeAtBaseline - r.pal.impliedStudyTdee, 0) + ' kcal', 11, true) + '  ' +
              (r.pal.matchedToStudy ? 'matched' : 'FALLBACK') +
              (r.pal.impliedStudyTdee != null &&
               Math.abs(r.pal.engineTdeeAtBaseline - r.pal.impliedStudyTdee) > 250
                 ? '  <-- PAL grid cannot reach it' : ''));
}

console.log('\nAGGRESSIVENESS INVERSION (a chosen so the engine runs the study\'s own deficit/surplus)');
console.log(rule('-', 150));
for (const r of rows) {
  const g = r.aggressiveness;
  console.log(pad(r.id, 26) + pad(g.phase, 10) + pad('a=' + g.a.toFixed(3), 10) +
              pad('study ' + g.studyTargetPct + '%', 14) +
              pad('engine ' + g.engineAchievedPct + '%', 15) +
              pad('prot ' + g.proteinPerFfmFromStudy + ' g/kgFFM', 24) +
              (g.clamped ? 'CLAMPED: ' + g.clampNote : ''));
}

printStats('SUMMARY — ALL CASES (n=' + rows.length + ')', stats(rows));

for (const [dir, rs] of [...groupBy(rows, r => r.direction)].sort()) {
  printStats(`SUMMARY — DIRECTION = ${dir.toUpperCase()} (n=${rs.length}): ` +
             rs.map(r => r.id).join(', '), stats(rs));
}
for (const [ta, rs] of [...groupBy(rows, r => r.trainingStatus)].sort()) {
  printStats(`SUMMARY — TRAINING STATUS = ${ta.toUpperCase()} (n=${rs.length}): ` +
             rs.map(r => r.id).join(', '), stats(rs));
}

/* 진단: 엔진이 구조적으로 무시하는 변수들 */
console.log('\nSTRUCTURAL DIAGNOSTICS (things the engine cannot express, checked numerically)');
console.log(rule('-', 150));
function pairDiff(idA, idB, label) {
  const a = rows.find(r => r.id === idA), b = rows.find(r => r.id === idB);
  if (!a || !b) return;
  const predD = a.predicted.deltaLeanMassKg - b.predicted.deltaLeanMassKg;
  const actD  = a.actual.deltaLeanMassKg - b.actual.deltaLeanMassKg;
  console.log(pad(label, 46) +
    pad('actual ΔLM gap ' + num(actD), 26) +
    pad('engine ΔLM gap ' + num(predD), 26) +
    (Math.abs(predD) < 0.05 ? '<-- engine sees NO difference' : ''));
}
pairDiff('villareal2017-resistance', 'villareal2017-aerobic', 'RT vs aerobic, same trial, matched deficit');
pairDiff('beavers2017-wl-rt', 'beavers2017-wl-at', 'RT vs aerobic (Beavers), same trial');
pairDiff('villareal2011-dietexercise', 'villareal2011-diet', 'diet+exercise vs diet alone (Villareal 2011)');
pairDiff('campbell2018-highprotein', 'campbell2018-lowprotein', 'protein 2.5 vs 0.9 g/kg at maintenance');
pairDiff('longland2016-highprotein', 'longland2016-lowprotein', 'protein 2.4 vs 1.2 g/kg in a 40% deficit');
pairDiff('garthe2011-slow', 'garthe2011-fast', 'slow vs fast weight loss in elite athletes');
{
  const a = rows.find(r => r.id === 'hatamoto2024-pe40'), b = rows.find(r => r.id === 'hatamoto2024-p10');
  if (a && b) {
    console.log(pad('surplus +40% vs +10% (Hatamoto, no RT)', 46) +
      pad('actual ΔFM gap ' + num(a.actual.deltaFatMassKg - b.actual.deltaFatMassKg), 26) +
      pad('engine ΔFM gap ' + num(a.predicted.deltaFatMassKg - b.predicted.deltaFatMassKg), 26));
    console.log(pad('   (engine bulk path: surplusPct never enters mass balance)', 46));
  }
}

console.log('\nTRANSLATION ASSUMPTIONS THAT CAN PRODUCE ERROR INDEPENDENT OF THE MODEL');
console.log(rule('-', 150));
[
 '1.  SMM = FFM x 0.55, and FFM = SMM / 0.55 on the way out. The studies measure FFM/lean mass; the engine\'s',
 '    state variable is skeletal muscle mass. Every lean-mass number in the table is a round trip through this',
 '    constant. Because baseSmmRatePerWeek multiplies by smmToFfm and stepWeek divides by k, the k cancels for',
 '    the muscle-GAIN path but NOT for the lean-LOSS path (leanLossPerWeek is a fraction of FFM, converted back',
 '    with x k), nor for BMR (BMR is computed from FFM = SMM/k). A k of 0.50 or 0.60 instead of 0.55 moves',
 '    baseline BMR by roughly +/-9%, which moves the whole fat trajectory.',
 '2.  DXA "lean mass" vs DXA "lean soft tissue" vs 4C-model FFM are not the same tissue. Kistler is the explicit',
 '    case (5.2 vs 6.6 kg depending on which the review quoted); Hatamoto used a 4-compartment model, Antonio used',
 '    BodPod. A systematic 1-1.5 kg definitional offset is inside these rows.',
 '3.  sex = "mixed" (9 of 22 cases) is forced to "male". That doubles the engine\'s muscle-gain ceiling',
 '    (sexFactor 1.0 vs 0.5) and moves the low-body-fat lean-loss trigger from 18% to 10%. Choosing "female"',
 '    instead would halve every predicted lean gain in those rows.',
 '4.  Nine baselines are algebraically back-solved from rounded published percentages (Garthe, Villareal 2011,',
 '    Beavers, Wycherley). Group-mean algebra assumes the mean subject behaves like a single subject, which is',
 '    false for anything nonlinear. Wycherley\'s baselines come from a BMI and an ASSUMED 1.68 m height.',
 '5.  deficitPctOfTdee is a mixture of three different quantities across the set: PRESCRIBED restriction (Garthe,',
 '    Longland, Wycherley), ACHIEVED average net imbalance BACK-CALCULATED FROM THE TISSUE CHANGE ITSELF',
 '    (Villareal, Beavers), and SELF-REPORTED intake change (all four Antonio arms). The Villareal/Beavers rows',
 '    are therefore partly circular: the deficit was derived from the very fat loss the engine is being asked to',
 '    predict, which flatters fat-mass accuracy and says nothing about lean mass. The Antonio rows are built on',
 '    self-reported intakes (2042 kcal/d for a 72 kg trained lifter) that are almost certainly wrong.',
 '6.  A long-run AVERAGE deficit is not the same trajectory as the real one. Beavers ran 18 months with an early',
 '    steep phase and a regain plateau; feeding the engine a flat 3-5% deficit for 78 weeks is not the study.',
 '7.  PAL is picked from only five discrete values, so engine TDEE can land up to ~12% off the implied TDEE even',
 '    at the best choice. And the implied TDEE is itself |kcal/day| / |fraction|, i.e. the ratio of two numbers',
 '    that are each inferred in half these rows.',
 '8.  The engine has no adaptive-thermogenesis term and no bodyweight-driven PAL change; PAL is held at its',
 '    starting value for all 78 weeks. Real TDEE falls with weight loss beyond what the FFM term captures.',
 '9.  Weeks of 8.5 and 5.3 are simulated as whole weeks plus a linearly prorated final week. The engine has no',
 '    sub-week semantics, so this is the harness\'s choice, not the engine\'s.',
 '10. proteinPerFFM is overridden with the study\'s actual prescription (g/kg BW x BW / FFM) instead of the',
 '    a-interpolated value, because the engine\'s lean-loss path keys on it. The "predictedWithAProtein" field in',
 '    validation-results.json shows what the untouched a-interpolation would have given.',
 '11. trainingStatus -> trainingAge is a judgement call per study, and it is the single strongest lever in the',
 '    model (MUSCLE_BASE spans 1.25 down to 0.175 %BW/month, a 7x range). Longland\'s "untrained overweight young',
 '    men" as novice and Antonio\'s 8.9-year lifters as advanced are defensible; Garthe\'s national-team athletes',
 '    as elite rather than advanced is a coin flip that changes the prediction.',
 '12. Age defaults to 30 and height to 175/163 cm where missing. Height does not enter the simulation at all',
 '    (only BMI display), but age does, through ageFactor().',
 '13. Every case is run with hadPriorPeak = false. Several cohorts (Garthe\'s athletes cutting into a competition',
 '    season, Kistler\'s bodybuilder) plausibly qualify for muscle memory, which would multiply gain by 2.5.',
 '14. The engine is deterministic and single-valued; the studies report means with SDs that often straddle zero',
 '    (Longland +1.2 +/- 1.0, Antonio 2014 +1.3 +/- 2.0). An "error" of 1 kg against an SD of 2 kg is not',
 '    distinguishable from noise for that row on its own. Only the consistent direction across rows is evidence.',
 '15. n ranges from 1 (Kistler) to 83 (Beavers) and every case is weighted equally in the summary statistics.'
].forEach(l => console.log(l));

fs.writeFileSync(OUT_PATH, JSON.stringify({
  generatedAt: new Date().toISOString(),
  engine: 'prototype/js/engine.js',
  engineChange: 'one export added: MB_ENGINE.stepWeek (no parameter or logic change)',
  kSmmToFfm: K_SMM_TO_FFM,
  caseCount: rows.length,
  summary: {
    all: stats(rows),
    byDirection: Object.fromEntries([...groupBy(rows, r => r.direction)].map(([g, rs]) => [g, stats(rs)])),
    byTrainingStatus: Object.fromEntries([...groupBy(rows, r => r.trainingStatus)].map(([g, rs]) => [g, stats(rs)]))
  },
  cases: sorted
}, null, 2));
console.log('\nwrote ' + OUT_PATH);
