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
    /* 근성장 게이트는 daysPerWeek 가 아니라 이 값을 씁니다.
       daysPerWeek 는 위에서 3 이상으로 클램프되므로, 운동을 안 한 군까지
       주 3회로 보이게 만듭니다. null(미보고)은 null 로 넘겨야 게이트가
       1.0 으로 남고 기존 동작이 유지됩니다. */
    resistanceDaysPerWeek: c.resistanceTrainingDaysPerWeek,
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
    const r = E.stepWeek(st, phase, params, profile, k, wk);
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
    const r = E.stepWeek(st, phase, params, profile, k, whole + 1);
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
    // 발표 기준 체중이 아니라 지방+제지방 변화의 합. 위 주석 참조.
    deltaWeightKg: (sim.endFatKg - c.baselineFatMassKg) + (sim.endLeanKg - c.baselineLeanMassKg),
    deltaFatMassKg: sim.endFatKg - c.baselineFatMassKg,
    deltaLeanMassKg: sim.endLeanKg - c.baselineLeanMassKg
  };
  /* 채점 기준.
   * deltaLeanMassKgScoring 이 있으면 그걸 쓴다 — 4구획 "제지방" 이 아니라 체단백 변화다.
   * 엔진은 근육을 예측하는데 4C FFM 증가분이 수분/글리코겐이면, 그걸로 채점하는 순간
   * 근육 파라미터를 수분에 맞추게 된다. (Hatamoto 2024: 4C FFM +0.73kg, 체단백 0.00kg)
   *
   * 체중은 지방+제지방으로 계산한다. 6개 케이스는 발표된 기준 체중이 지방+제지방보다
   * 2.5~2.8kg 크다(골무기질·기타). 예측은 지방+제지방만 추적하므로 발표 체중을 기준으로
   * 빼면 그 차이가 통째로 오차로 잡힌다 — 엔진이 아니라 회계가 틀린 것이다. */
  const leanBasis = c.deltaLeanMassKgScoring != null ? 'bodyProtein' : 'published';
  const act3 = {
    deltaWeightKg: c.deltaFatMassKg + (c.deltaLeanMassKgScoring != null
      ? c.deltaLeanMassKgScoring : c.deltaLeanMassKg),
    deltaFatMassKg: c.deltaFatMassKg,
    deltaLeanMassKg: c.deltaLeanMassKgScoring != null ? c.deltaLeanMassKgScoring : c.deltaLeanMassKg
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
    leanScoringBasis: leanBasis,
    leanScoringNote: c.leanScoringBasis || null,
    deficitSource: c.deficitSource || 'unknown',
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
    console.log(pad('surplus +40% vs +10% -> FAT (Hatamoto, no RT)', 46) +
      pad('actual ΔFM gap ' + num(a.actual.deltaFatMassKg - b.actual.deltaFatMassKg), 26) +
      pad('engine ΔFM gap ' + num(a.predicted.deltaFatMassKg - b.predicted.deltaFatMassKg), 26) +
      'right answer, wrong mechanism (see below)');
    console.log(pad('surplus +40% vs +10% -> LEAN (Hatamoto)', 46) +
      pad('actual ΔLM gap ' + num(a.actual.deltaLeanMassKg - b.actual.deltaLeanMassKg), 26) +
      pad('engine ΔLM gap ' + num(a.predicted.deltaLeanMassKg - b.predicted.deltaLeanMassKg), 26) +
      '<-- gap is baseline-weight only');
  }
}

/* 증량 국면의 구조적 성질을 숫자로 확인한다 (주장하지 말고 돌려 보고 말한다) */
{
  console.log('');
  const prof = buildProfile(CASES.find(c => c.id === 'hatamoto2024-p10'), 'moderate');
  const st0 = { smmKg: 52 * K_SMM_TO_FFM, bfmKg: 11 };
  const probe = [0.0, 0.25, 0.5, 0.75, 1.0].map(a => {
    const p = E.paramsAt(a, 'bulk', null);
    const r = E.stepWeek(st0, 'bulk', p, prof, K_SMM_TO_FFM);
    return { a, surplusPct: +(p.surplusPct * 100).toFixed(1), leanFraction: +p.leanFraction.toFixed(3),
             intake: r.intake, smmDelta: +(r.state.smmKg - st0.smmKg).toFixed(4),
             fatDelta: +(r.state.bfmKg - st0.bfmKg).toFixed(4) };
  });
  console.log('BULK-PATH PROBE — same body, a swept 0..1, one week of stepWeek(phase="bulk"):');
  console.log('  ' + pad('a', 6) + pad('surplus%', 10, true) + pad('intake', 9, true) +
              pad('leanFrac', 10, true) + pad('ΔSMM kg', 10, true) + pad('ΔFAT kg', 10, true));
  probe.forEach(x => console.log('  ' + pad(x.a.toFixed(2), 6) + pad(x.surplusPct, 10, true) +
    pad(x.intake, 9, true) + pad(x.leanFraction, 10, true) +
    pad(x.smmDelta.toFixed(4), 10, true) + pad(x.fatDelta.toFixed(4), 10, true)));
  const smmSame = probe.every(x => Math.abs(x.smmDelta - probe[0].smmDelta) < 1e-9);
  console.log('  -> muscle gain is ' + (smmSame ? 'IDENTICAL' : 'different') +
              ' across a 4x range of surplus: in stepWeek("bulk"), surplusPct sets INTAKE only.');
  console.log('  -> fat gain varies only because leanFraction happens to co-vary with a. No kcal ever');
  console.log('     reaches the fat compartment: eating +1000 kcal/d and +150 kcal/d at the same a give');
  console.log('     byte-identical body composition. The bulk path has no energy balance at all.');
}

/* 근육 증가가 저항운동 여부를 전혀 보지 않는다는 것도 숫자로 */
{
  const r = rows.find(x => x.id === 'villareal2011-diet');
  if (r) {
    console.log('');
    console.log('NO-TRAINING PROBE — villareal2011-diet is a 70-year-old obese cohort with ZERO prescribed exercise.');
    console.log('  engine predicts ΔLM ' + num(r.predicted.deltaLeanMassKg) + ' kg over 52 weeks; the trial measured ' +
                num(r.actual.deltaLeanMassKg) + ' kg.');
    console.log('  stepWeek() takes no training input, so profile.trainingAge="novice" pays out the full');
    console.log('  MUSCLE_BASE 1.25 %BW/month ceiling to someone who never lifted. That single fact accounts for');
    console.log('  most of the +' + stats(rows.filter(x => x.direction === 'cut')).deltaLeanMassKg.meanError.toFixed(2) +
                ' kg mean lean-mass error across the cut cases.');
  }
}

console.log('\nTRANSLATION ASSUMPTIONS THAT CAN PRODUCE ERROR INDEPENDENT OF THE MODEL');
console.log(rule('-', 150));
[
 '1.  SMM = FFM x 0.55 on the way in, FFM = SMM / 0.55 on the way out. THIS HARNESS IS INSENSITIVE TO k:',
 '    baseline SMM is built as lean x k and immediately divided by k again, so k cancels exactly. Re-running at',
 '    k = 0.45 / 0.55 / 0.65 gives bit-identical results. An earlier version of this file claimed k was the',
 '    largest error source and moved BMR by +/-9%; that was WRONG and it is retracted here, because it was being',
 '    used to wave away the lean-mass bias. k CANNOT explain any error in this table.',
 '    NOTE the flip side: a real InBody user has SMM and FFM measured independently, so k is DATA, not a',
 '    constant -- and the engine\'s sensitivity to it is therefore completely untested by this harness.',
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

/* 결과에 엔진 SHA 를 박는다. 이게 없어서 한 번 사고가 났다 — 결과 JSON 이 엔진보다
 * 오래된 채로 분석의 근거로 인용됐다. 작업트리가 더러우면 그것도 기록한다. */
function engineStamp() {
  const { execFileSync } = require('node:child_process');
  const run = a => { try { return execFileSync('git', a, { cwd: __dirname, encoding: 'utf8' }).trim(); }
                     catch { return null; } };
  const sha = run(['log', '-1', '--format=%H', '--', '../prototype/js/engine.js']);
  const dirty = run(['status', '--porcelain', '--', '../prototype/js/engine.js']);
  // HEAD 는 일부러 안 넣는다. 엔진과 무관한 커밋마다 결과 파일이 바뀌어
  // diff 노이즈만 만들고, 재현에 필요한 것은 engineSha 뿐이다.
  return { engineSha: sha, engineDirty: !!dirty,
           warning: dirty ? 'engine.js 에 커밋되지 않은 변경이 있습니다 — 이 결과는 재현 불가' : null };
}

fs.writeFileSync(OUT_PATH, JSON.stringify({
  generatedAt: new Date().toISOString(),
  engine: 'prototype/js/engine.js',
  engineChange: 'one export added: MB_ENGINE.stepWeek (no parameter or logic change)',
  provenance: engineStamp(),
  kSmmToFfm: K_SMM_TO_FFM,
  caseCount: rows.length,
  scoring: {
    leanMass: 'deltaLeanMassKgScoring (body protein) when present, else published lean/FFM',
    weight: 'deltaFat + deltaLean on both sides — published baseline weight includes bone mineral the engine does not track'
  },
  summary: {
    all: stats(rows),
    byDirection: Object.fromEntries([...groupBy(rows, r => r.direction)].map(([g, rs]) => [g, stats(rs)])),
    byTrainingStatus: Object.fromEntries([...groupBy(rows, r => r.trainingStatus)].map(([g, rs]) => [g, stats(rs)])),
    /* 가장 중요한 분할. 'provided'/'prescribed' 만이 에너지 모델을 독립적으로 검증한다.
     * 'backsolved-from-tissue' 는 예측 대상인 조직 변화에서 적자를 역산한 것이라 순환이다. */
    byDeficitSource: Object.fromEntries([...groupBy(rows, r => r.deficitSource)].map(([g, rs]) => [g, stats(rs)]))
  },
  cases: sorted
}, null, 2));
console.log('\nwrote ' + OUT_PATH);

/* ---------------------------------------------------------------------------
 * 게이트 — 이 파일이 엔진 정확도의 판정자입니다.
 *
 * 예전에는 오차를 출력만 하고 항상 exit 0 이었습니다. 그래서 제지방을 평균
 * 2.24kg 과대예측하는 상태로 "통과"가 계속 찍혔습니다.
 *
 * 시뮬레이션(tools/simulate.js)은 자기가 만든 생리 모델로 채점하므로
 * 절대 정확도를 판정할 수 없습니다 — 두 모델이 다를 때 누가 맞는지 모릅니다.
 * 실제 논문 22개군과 대조하는 이쪽이 그 역할을 합니다.
 *
 * 임계값은 "지금보다 나빠지면 잡는다" 기준입니다. 현재값에서 약간의 여유만
 * 둡니다 — 크게 두면 서서히 나빠지는 것을 못 잡습니다.
 * ------------------------------------------------------------------------- */
const GATE = {
  leanMAE: 1.60,      // 현재 1.36
  leanBias: 1.00,     // 현재 +0.55
  fatMAE: 1.30,       // 현재 1.11
  providedLeanMAE: 0.70   // 독립 검증군(전량 제공식) 현재 0.37
};
const all = stats(rows);
const provided = (() => {
  const g = rows.filter(r => r.deficitSource === 'provided');
  return g.length ? stats(g) : null;
})();
const fails = [];
if (all.deltaLeanMassKg.meanAbsError > GATE.leanMAE)
  fails.push(`제지방 MAE ${all.deltaLeanMassKg.meanAbsError} > ${GATE.leanMAE}`);
if (Math.abs(all.deltaLeanMassKg.meanError) > GATE.leanBias)
  fails.push(`제지방 편향 ${all.deltaLeanMassKg.meanError} (절대값 > ${GATE.leanBias})`);
if (all.deltaFatMassKg.meanAbsError > GATE.fatMAE)
  fails.push(`지방 MAE ${all.deltaFatMassKg.meanAbsError} > ${GATE.fatMAE}`);
if (provided && provided.deltaLeanMassKg.meanAbsError > GATE.providedLeanMAE)
  fails.push(`독립 검증군 제지방 MAE ${provided.deltaLeanMassKg.meanAbsError} > ${GATE.providedLeanMAE}`);

console.log('\n=== 게이트 ===');
console.log(`  제지방 MAE       ${all.deltaLeanMassKg.meanAbsError} / ${GATE.leanMAE}`);
console.log(`  제지방 편향      ${all.deltaLeanMassKg.meanError} / ±${GATE.leanBias}`);
console.log(`  지방 MAE         ${all.deltaFatMassKg.meanAbsError} / ${GATE.fatMAE}`);
if (provided) console.log(`  독립군 제지방MAE ${provided.deltaLeanMassKg.meanAbsError} / ${GATE.providedLeanMAE}`);
if (fails.length) {
  console.log('\n실패 — 엔진 정확도가 기준을 벗어났습니다:');
  fails.forEach(f => console.log('  ✗ ' + f));
  process.exit(1);
}
console.log('\n통과');
