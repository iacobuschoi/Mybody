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

function makeScanCases(n, seed) {
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
    /* 엔진은 나이와 활동량도 읽습니다. 일부러 자주 비웁니다 —
       없는 값으로 산수하면 NaN 이 나오는데, 그 NaN 이 양쪽에서
       **같은 자리**에 나와야 옮긴 것이 맞습니다. */
    if (rnd() > 0.2) profile.age = Math.round(18 + rnd() * 50);
    if (rnd() > 0.25) {
      const ls = ['sedentary', 'light', 'moderate', 'active', 'veryActive'];
      profile.activityLevel = ls[(rnd() * ls.length) | 0];
    } else if (rnd() > 0.5) {
      profile.activityLevel = 'nonsense';   // 모르는 값이면 moderate 로 떨어져야 합니다
    }

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

/* --- 계획 엔진용 사례 -------------------------------------------------------
 *
 * 검산(crosscheck)은 결과지 한 장이면 되지만, 계획 엔진은 **사람**이
 * 필요합니다 — 훈련연령, 나이, 주당 운동일수, 목표. 그래서 사례 모양이
 * 다릅니다.
 *
 * 한 가지 규칙을 지킵니다: **앞 단계의 출력은 미리 계산해서 사례 파일에
 * 적어 둡니다.** stepWeek 을 시험하는데 params 를 양쪽이 각자 만들면,
 * 갈렸을 때 stepWeek 이 틀린 건지 paramsAt 이 틀린 건지 알 수가 없습니다.
 * 층마다 따로 세워서 따로 무너뜨립니다.
 * -------------------------------------------------------------------------- */

function planProfile(rnd, base) {
  const p = {};
  if (rnd() > 0.1) p.heightCm = base.heightCm;
  if (rnd() > 0.15) p.sex = rnd() > 0.5 ? 'male' : 'female';
  if (rnd() > 0.2) p.age = Math.round(15 + rnd() * 55);          // 미성년·고령 둘 다
  const tas = ['novice', 'intermediate', 'advanced', 'elite'];
  const ta = rnd();
  if (ta > 0.2) p.trainingAge = tas[(rnd() * tas.length) | 0];
  else if (ta > 0.1) p.trainingAge = 'nonsense';                 // 모르는 값 → intermediate
  const ls = ['sedentary', 'light', 'moderate', 'active', 'veryActive'];
  if (rnd() > 0.15) p.activityLevel = ls[(rnd() * ls.length) | 0];
  else if (rnd() > 0.5) p.activityLevel = 'nonsense';
  if (rnd() > 0.25) p.daysPerWeek = Math.round(rnd() * 7);        // 0 도 나옵니다
  /* 저항운동 게이트는 **없음 / null / 숫자**를 다르게 다룹니다.
     Dart Map 에서는 앞의 둘이 같아 보이므로 여기서 반드시 셋 다 만듭니다. */
  const roll = rnd();
  if (roll > 0.66) p.resistanceDaysPerWeek = Math.round(rnd() * 7);
  else if (roll > 0.33) p.resistanceDaysPerWeek = null;
  if (rnd() > 0.85) p.hadPriorPeak = true;
  if (rnd() > 0.8) p.sessionMinutes = Math.round(30 + rnd() * 60);
  return p;
}

/** 몸만들기 모드의 제약. modes.js 가 주는 모양입니다. */
function planCon(rnd) {
  if (rnd() > 0.6) return null;
  const con = {};
  if (rnd() > 0.2) { con.aMin = rnd() * 0.5; con.aMax = con.aMin + rnd() * 0.5; }
  if (rnd() > 0.7) { con.aMax = con.aMin; }                       // 폭 0 → span 1 로 떨어져야
  if (rnd() > 0.3) { con.proteinPerFfmMin = 1.6 + rnd(); con.proteinPerFfmMax = con.proteinPerFfmMin + rnd(); }
  if (rnd() > 0.6) con.strategy = ['auto', 'simultaneous', 'split'][(rnd() * 3) | 0];
  return con;
}

function planGoal(rnd, cur) {
  const r1 = x => Math.round(x * 10) / 10;
  const g = {
    weightKg: r1(cur.weightKg + (rnd() - 0.5) * 20),
    bfmKg: r1(Math.max(0.5, cur.bfmKg + (rnd() - 0.65) * 12)),
    smmKg: r1(Math.max(1, cur.smmKg + (rnd() - 0.3) * 8))
  };
  if (rnd() > 0.93) delete g.bfmKg;        // 도달 불가 → 208주 끝까지 돌아야 합니다
  if (rnd() > 0.95) g.smmKg = null;
  return g;
}

/* --- 모드 선택용 사례 -------------------------------------------------------
 *
 * modes.select 는 **계획을 만들어도 되는지**를 먼저 정합니다. 그래서
 * 여기서는 그럴듯한 사람보다 **경계에 선 사람**이 중요합니다: 열여덟 살,
 * 체지방률 15% 언저리, 마감 4주, 항등식이 1.5kg 어긋난 목표.
 *
 * 값이 **없는 것**과 **null 인 것**도 반드시 갈라서 넣습니다. 자바스크립트는
 * `undefined < 19` 를 거짓으로, `null < 19` 를 참으로 봅니다 — 미성년 보호
 * 게이트가 이 차이 하나로 뒤집힙니다.
 * -------------------------------------------------------------------------- */
function modeCase(rnd) {
  const male = rnd() > 0.45;
  const w = 45 + rnd() * 55;
  const pbf = 5 + rnd() * 35;
  const bfm = w * pbf / 100;
  const ffm = w - bfm;
  const h = 150 + rnd() * 40;
  const r1 = x => Math.round(x * 10) / 10;

  const i = {
    sex: rnd() > 0.06 ? (male ? 'male' : 'female') : (rnd() > 0.5 ? 'other' : undefined),
    age: Math.round(14 + rnd() * 55),            // 미성년 게이트(19)를 자주 밟습니다
    heightCm: Math.round(h),
    curWeightKg: r1(w), curBfmKg: r1(bfm), curSmmKg: r1(ffm * (0.5 + rnd() * 0.12)),
    curPbfPct: r1(pbf), curBmi: r1(w / ((h / 100) * (h / 100))),
    dWeightKg: r1((rnd() - 0.55) * 14),
    dBfmKg: r1((rnd() - 0.6) * 10),
    dSmmKg: r1((rnd() - 0.35) * 4)
  };
  /* 항등식(체중 = 지방 + 제지방)을 절반은 맞춰 줍니다. 안 맞추면 거부 규칙 6이
     거의 전부를 먼저 잡아서 그 뒤의 규칙 22개를 한 번도 안 밟습니다. */
  if (rnd() > 0.35) {
    const k = i.curSmmKg / (i.curWeightKg - i.curBfmKg);
    i.dWeightKg = r1(i.dBfmKg + i.dSmmKg / k);
  }
  const tas = ['novice', 'intermediate', 'advanced', 'elite'];
  const ta = rnd();
  if (ta > 0.18) i.trainingAge = tas[(rnd() * tas.length) | 0];
  else if (ta > 0.1) i.trainingAge = 'oops';     // 화이트리스트 밖 → taExp false
  if (rnd() > 0.8) i.hadPriorPeak = true;
  if (rnd() > 0.5) i.tdeeKcal = Math.round(1600 + rnd() * 1600);

  /* 마감: 숫자 · **명시적 null** · 아예 없음 — 셋이 전부 다르게 동작합니다. */
  const dl = rnd();
  if (dl > 0.6) i.deadlineWeeks = Math.round(2 + rnd() * 30);
  else if (dl > 0.3) i.deadlineWeeks = null;

  /* 직전 국면도 마찬가지 (select 가 undefined 만 null 로 바꿔 줍니다). */
  const ph = rnd();
  if (ph > 0.75) i.currentPhase = 'bulk';
  else if (ph > 0.6) i.currentPhase = ['cut', 'maintain'][(rnd() * 2) | 0];
  else if (ph > 0.45) i.currentPhase = null;

  /* recentTrend 가 **아예 없으면** 거부 규칙이 예외를 던지고, 원본은 그걸
     '걸림'으로 칩니다. 그 경로도 반드시 밟아야 합니다. */
  const tr = rnd();
  if (tr > 0.55) {
    i.recentTrend = { weeksSpan: Math.round(1 + rnd() * 20),
                      dWeightKg: r1((rnd() - 0.7) * 10),
                      dSmmKg: r1((rnd() - 0.5) * 3),
                      dBfmKg: r1((rnd() - 0.6) * 6),
                      gapDays: Math.round(7 + rnd() * 120) };
  } else if (tr > 0.3) {
    i.recentTrend = null;
  }

  /* 필수 칸 하나를 비우거나 null 로 만듭니다 — 거부 규칙 1 의 두 경로입니다. */
  if (rnd() > 0.85) {
    const f = ['curWeightKg', 'curSmmKg', 'curBfmKg', 'heightCm', 'age',
               'dWeightKg', 'dSmmKg', 'dBfmKg'][(rnd() * 8) | 0];
    if (rnd() > 0.5) delete i[f]; else i[f] = null;
  }
  return i;
}

/* 인바디 결과지의 **부위별 근육/지방** 칸. 앱에 들어오는 길은 아직 없지만
   워크아웃 처방이 이걸 읽고 종목을 바꾸므로, 있을 때와 없을 때를 둘 다 넣습니다. */
function withSegmental(scan, rnd) {
  if (rnd() > 0.45) return scan;
  const v = () => ['표준이하', '표준', '표준이상'][(rnd() * 3) | 0];
  const s2 = Object.assign({}, scan);
  if (rnd() > 0.2) s2.segmentalLean = { rightArm: v(), leftArm: v(), trunk: v(), rightLeg: v(), leftLeg: v() };
  if (rnd() > 0.4) s2.segmentalFat = { rightArm: v(), leftArm: v(), trunk: v(), rightLeg: v(), leftLeg: v() };
  return s2;
}

/** 식단 기록 사례 — 미기록일·빈칸·문자열까지 섞습니다. */
function logCase(rnd, module) {
  const target = {
    intakeKcal: Math.round(1200 + rnd() * 1800),
    proteinG: Math.round(90 + rnd() * 120),
    carbG: rnd() > 0.12 ? Math.round(80 + rnd() * 300) : 0,     // 0 은 거짓 → pct null
    fatG: rnd() > 0.12 ? Math.round(30 + rnd() * 90) : 0
  };
  const day = () => {
    const logged = rnd() > 0.3;
    const d = { date: '2026-03-01', logged: logged };
    if (logged) {
      d.kcal = Math.round(target.intakeKcal * (0.6 + rnd() * 0.8));
      d.p = Math.round(target.proteinG * (0.5 + rnd() * 0.9));
      if (rnd() > 0.15) d.c = Math.round(rnd() * 350);
      if (rnd() > 0.15) d.f = Math.round(rnd() * 110);
      if (rnd() > 0.95) d.kcal = 0;
    }
    return d;
  };
  if (module === 'engine.dietAdherence') {
    const n = (rnd() * 10) | 0;                                  // 0일도 넣습니다
    return { days: Array.from({ length: n }, day), target: rnd() > 0.05 ? target : null };
  }
  if (module === 'engine.dietNudge') {
    return { today: day(), target: rnd() > 0.05 ? target : null,
             /* 원본은 new Date().getHours() 를 읽습니다. 양쪽이 **같은 시각**을
                봐야 비교가 성립하므로 시계를 고정해서 넘깁니다. */
             nowISO: '2026-03-01T' + String((rnd() * 24) | 0).padStart(2, '0') + ':30:00' };
  }
  return {
    plan: null,
    expected: { weightKg: 70 + (rnd() - 0.5) * 20, prevWeightKg: 70 + (rnd() - 0.5) * 20 },
    actual: { weightKg: 70 + (rnd() - 0.5) * 20 },
    adherence: rnd() > 0.4 ? { dietPct: Math.round(rnd() * 120) } : (rnd() > 0.5 ? {} : null)
  };
}

/**
 * 계획 엔진 사례. module 에 따라 필요한 칸을 채웁니다.
 * cur · goalInfo · params 는 **JS 로 미리 계산해서** 넣습니다.
 */
function makePlanCases(n, seed, module) {
  const rnd = rng(seed);
  const E = loadJs('engine');
  const out = [];
  if (module.indexOf('modes.') === 0) {
    while (out.length < n) out.push({ input: modeCase(rnd) });
    return out;
  }
  while (out.length < n) {
    const base = plausible(rnd);
    const scan = Object.assign({}, base.scan);
    if (rnd() > 0.85) BREAKERS[(rnd() * BREAKERS.length) | 0](scan, rnd);
    const profile = planProfile(rnd, base);
    const cur = E.derive(scan, profile);
    const goal = planGoal(rnd, cur);
    const con = planCon(rnd);
    const a = rnd();
    const c = { cur: cur, goal: goal, profile: profile, con: con, a: a };

    if (module === 'engine.classifyGoal') { out.push({ cur: cur, goal: goal }); continue; }
    if (module === 'engine.paramsAt') {
      out.push({ a: rnd() > 0.9 ? [null, 'abc', -1, 2, 0, 1][(rnd() * 6) | 0] : a,
                 mode: rnd() > 0.5 ? 'cut' : (rnd() > 0.2 ? 'bulk' : 'nonsense'),
                 con: con });
      continue;
    }

    const goalInfo = E.classifyGoal(cur, goal);
    if (module === 'engine.resolveTraining') {
      const params = E.paramsAt(a, rnd() > 0.5 ? 'cut' : 'bulk', con);
      out.push({ profile: profile, params: params, goalInfo: rnd() > 0.1 ? goalInfo : null });
      continue;
    }
    if (module === 'engine.baseSmmRatePerWeek') {
      out.push({ weightKg: cur.weightKg, profile: profile, smmToFfm: cur.smmToFfm,
                 ffmKg: rnd() > 0.15 ? cur.ffmKg : null,
                 weekIndex: rnd() > 0.5 ? Math.round(rnd() * 200) : (rnd() > 0.5 ? null : undefined) });
      continue;
    }
    if (module === 'engine.stepWeek') {
      const phase = ['cut', 'bulk', 'maintain'][(rnd() * 3) | 0];
      const params = E.paramsAt(a, phase === 'bulk' ? 'bulk' : 'cut', con);
      const st = { smmKg: cur.smmKg, bfmKg: cur.bfmKg };
      if (rnd() > 0.92) st.smmKg = null;
      if (rnd() > 0.94) delete st.bfmKg;
      const wi = rnd();
      out.push({ st: st, phase: phase, params: params, profile: profile,
                 k: rnd() > 0.1 ? cur.smmToFfm : (rnd() > 0.5 ? 0 : null),
                 weekIndex: wi > 0.6 ? Math.round(rnd() * 200) : (wi > 0.3 ? 0 : null) });
      continue;
    }
    if (module === 'engine.dietAdherence' || module === 'engine.dietNudge' ||
        module === 'engine.checkinAdvice') {
      out.push(logCase(rnd, module));
      continue;
    }

    /* 여기서부터는 **시뮬레이션 결과가 입력**입니다. 미리 계산해서 넣습니다. */
    if (module === 'engine.macrosFor' || module === 'engine.workoutFor' ||
        module === 'engine.dietFor' || module === 'engine.milestonesFrom') {
      const sim = E.bestAt(cur, goal, profile, a, goalInfo, con);
      if (module === 'engine.macrosFor') { out.push({ sim: sim, cur: cur, profile: profile }); continue; }
      if (module === 'engine.milestonesFrom') {
        out.push({ traj: sim.trajectory, startISO: rnd() > 0.2 ? '2026-03-15' : '2026-12-28' });
        continue;
      }
      const macros = E.macrosFor(sim, cur, profile);
      if (module === 'engine.dietFor') {
        const pr = Object.assign({}, profile);
        const r = rnd();
        if (r > 0.66) pr.mealsPerDay = 2; else if (r > 0.33) pr.mealsPerDay = 4;
        else if (rnd() > 0.5) pr.mealsPerDay = 5;      // 모르는 값 → 3끼로 떨어져야
        out.push({ macros: macros, profile: pr });
        continue;
      }
      out.push({ sim: sim, cur: cur, profile: profile,
                 scan: withSegmental(scan, rnd), goalInfo: rnd() > 0.1 ? goalInfo : null });
      continue;
    }

    if (module === 'engine.planDrift') {
      /* 계획을 만들고 → 몇 주 지난 뒤의 측정을 넣습니다. 계획대로 간 경우,
         앞선 경우, 뒤처진 경우, 근육만 빠진 경우를 골고루 밟아야 합니다. */
      const modes = realModeDefs();
      const modeDef = rnd() > 0.5 ? modes[(rnd() * modes.length) | 0] : null;
      const cmp = E.compareLevels(scan, profile, goal, '2026-03-15', null, modeDef);
      if (!cmp.results.length) continue;
      const lvl = ['high', 'mid', 'low'][(rnd() * 3) | 0];
      const plan = E.buildPlan(cmp, lvl, scan, profile);
      if (!plan) continue;
      if (modeDef) plan.goal.modeId = modeDef.id;
      const wks = Math.round(rnd() * 40);
      const at = plan.trajectory[Math.min(plan.trajectory.length - 1, wks)];
      /* 실제 측정은 계획과 어긋납니다 — 그 어긋남이 이 함수의 전부입니다. */
      const later = Object.assign({}, scan, {
        weightKg: Math.round((at.weightKg + (rnd() - 0.5) * 6) * 10) / 10,
        bfmKg: Math.round((at.bfmKg + (rnd() - 0.5) * 5) * 10) / 10,
        smmKg: Math.round((at.smmKg + (rnd() - 0.55) * 3) * 10) / 10,
        measuredAt: new Date(Date.UTC(2026, 2, 15) + wks * 7 * 86400000).toISOString()
      });
      delete later.pbfPct; delete later.ffmKg;
      out.push({ plan: plan, scans: [later], profile: profile });
      continue;
    }

    if (module === 'engine.buildPlan') {
      const modes = realModeDefs();
      const modeDef = rnd() > 0.5 ? modes[(rnd() * modes.length) | 0] : null;
      const cmp = E.compareLevels(scan, profile, goal, '2026-03-15',
                                  rnd() > 0.5 ? Math.round(4 + rnd() * 40) : null, modeDef);
      out.push({ comparison: cmp,
                 level: rnd() > 0.1 ? ['high', 'mid', 'low'][(rnd() * 3) | 0] : 'nope',
                 scan: withSegmental(scan, rnd), profile: profile });
      continue;
    }

    if (module === 'engine.compareLevels') {
      const modes = realModeDefs();
      const roll = rnd();
      out.push({
        scan: scan, profile: profile, goal: goal,
        /* 시작일은 **반드시 넣습니다.** 안 넣으면 원본이 new Date() 를 써서
           양쪽이 서로 다른 순간을 봅니다 — 자정을 넘기면 하루가 갈립니다. */
        startDateISO: roll > 0.5 ? '2026-03-15' : '2026-12-28T00:00:00',
        deadlineWeeks: rnd() > 0.5 ? Math.round(4 + rnd() * 60) : (rnd() > 0.5 ? 0 : null),
        modeDef: rnd() > 0.35 ? modes[(rnd() * modes.length) | 0] : null
      });
      continue;
    }
    out.push(c);  /* bestAt · scanCurve · simulate* 는 통째로 씁니다 */
    void goalInfo;
  }
  return out.slice(0, n);
}

/* --- JS 쪽 실행 ----------------------------------------------------------
 *
 * engine.js 는 브라우저용이라 `window` 를 기대합니다. 노드에는 없으므로
 * 얹어 주고 나서 읽습니다 — 파일을 고치지 않는 쪽이 낫습니다. 검사하려고
 * 원본을 건드리면 검사한 것과 실제로 도는 것이 달라집니다.
 * -------------------------------------------------------------------------- */
let depsLoaded = false;
function loadJs(file) {
  if (typeof global.window === 'undefined') global.window = global;
  /* 먼저 얹어야 하는 것들.
     · modes.js — engine.js 의 classifyGoal 이 `global.MB_MODES.NOISE` 를 읽고
       그 객체를 goalInfo.noise 칸에 **통째로** 실어 내보냅니다. 예전엔 여기서
       숫자 세 개짜리 가짜를 얹었는데, 그러면 앱이 실제로 내보내는 값과 다른
       것을 비교하게 됩니다 — 통과해도 보증되는 게 없습니다.
     · data.js — dietFor·workoutFor 가 `global.MB_DATA` 에서 식품과 종목을 읽습니다.
     한 번만 합니다. 서로 부르게 두면 끝없이 돕니다 (실제로 그랬습니다). */
  if (!depsLoaded) {
    depsLoaded = true;
    require(path.join(ROOT, 'prototype', 'js', 'modes.js'));
    require(path.join(ROOT, 'prototype', 'js', 'data.js'));
  }
  require(path.join(ROOT, 'prototype', 'js', file + '.js'));
  if (file === 'crosscheck') return global.MB_CHECK;
  if (file === 'modes') return global.MB_MODES;
  if (file === 'data') return global.MB_DATA;
  return global.MB_ENGINE;
}

/* 몸만들기 모드의 **진짜** 값들. 지어내면 실제로 도는 구간을 안 밟습니다 —
   예컨대 유지모드의 a 범위는 0~0.08 이라 세 강도가 전부 한 점에 모입니다.
   compareLevels 가 읽는 칸만 가져옵니다(나머지는 몇 KB 짜리 산문이라
   사례 파일만 부풀립니다 — 어차피 양쪽이 같은 파일을 읽습니다). */
function realModeDefs() {
  const M = loadJs('modes');
  return M.MODES.map(m => ({
    id: m.id, nameKo: m.nameKo, aMin: m.aMin, aMax: m.aMax, strategy: m.strategy,
    proteinPerFfmMin: m.proteinPerFfmMin, proteinPerFfmMax: m.proteinPerFfmMax
  }));
}

/* dietNudge 는 `new Date().getHours()` 로 지금 시각을 읽습니다. 양쪽이 서로
   다른 순간을 보면 19시 경계에서 답이 갈리고, 그건 옮긴 코드의 잘못이
   아닙니다. 그래서 검사하는 동안만 시계를 세웁니다 — 원본은 안 건드립니다. */
function withFrozenClock(iso, fn) {
  const Real = global.Date;
  const fixed = new Real(iso).getTime();
  function Frozen(...a) { return a.length === 0 ? new Real(fixed) : new Real(...a); }
  Frozen.prototype = Real.prototype;
  Frozen.now = () => fixed;
  Frozen.parse = Real.parse;
  Frozen.UTC = Real.UTC;
  global.Date = Frozen;
  try { return fn(); } finally { global.Date = Real; }
}

/** 모듈 이름 → JS 쪽에서 실제로 부를 함수 */
function jsCaller(module) {
  if (module === 'crosscheck') {
    const m = loadJs('crosscheck');
    return c => m.run(c.scan, c.profile, c.prev);
  }
  if (module.indexOf('modes.') === 0) {
    const M = loadJs('modes');
    loadJs('engine');           // select 가 근성장 모델을 엔진에서 가져옵니다
    if (module === 'modes.select') {
      /* select 는 입력 객체를 복사해서 파생값을 얹고 `i.input = i` 로 자기를
         가리키게 합니다 — 그대로 JSON 으로 찍으면 순환 참조로 터집니다.
         돌려주는 값에는 그 고리가 없지만, 혹시 몰라 얕게 확인합니다. */
      return c => M.select(c.input);
    }
    if (module === 'modes.forDisplay') return c => M.forDisplay(c.input && c.input.text);
    throw new Error('모르는 모듈: ' + module);
  }
  const m = loadJs('engine');
  switch (module) {
    case 'engine.validateScan':   return c => m.validateScan(c.scan, c.prev);
    case 'engine.derive':         return c => m.derive(c.scan, c.profile);
    case 'engine.classifyGoal':   return c => m.classifyGoal(c.cur, c.goal);
    case 'engine.paramsAt':       return c => m.paramsAt(c.a, c.mode, c.con);
    case 'engine.resolveTraining':return c => m.resolveTraining(c.profile, c.params, c.goalInfo);
    case 'engine.baseSmmRatePerWeek':
      return c => m.baseSmmRatePerWeek(c.weightKg, c.profile, c.smmToFfm, c.ffmKg, c.weekIndex);
    case 'engine.stepWeek':
      return c => m.stepWeek(c.st, c.phase, c.params, c.profile, c.k, c.weekIndex);
    case 'engine.simulateSimultaneous':
      return c => m.simulateSimultaneous(c.cur, c.goal, c.profile, c.a, m.classifyGoal(c.cur, c.goal), c.con);
    case 'engine.simulateSplit':
      return c => m.simulateSplit(c.cur, c.goal, c.profile, c.a, m.classifyGoal(c.cur, c.goal), c.con);
    case 'engine.bestAt':
      return c => m.bestAt(c.cur, c.goal, c.profile, c.a, m.classifyGoal(c.cur, c.goal), c.con);
    case 'engine.scanCurve':
      return c => m.scanCurve(c.cur, c.goal, c.profile, m.classifyGoal(c.cur, c.goal), c.con);
    case 'engine.compareLevels':
      return c => m.compareLevels(c.scan, c.profile, c.goal, c.startDateISO, c.deadlineWeeks, c.modeDef);
    case 'engine.macrosFor':      return c => m.macrosFor(c.sim, c.cur, c.profile);
    case 'engine.workoutFor':     return c => m.workoutFor(c.sim, c.cur, c.profile, c.scan, c.goalInfo);
    case 'engine.dietFor':        return c => m.dietFor(c.macros, c.profile);
    case 'engine.milestonesFrom': return c => m.milestonesFrom(c.traj, c.startISO);
    case 'engine.dietAdherence':  return c => m.dietAdherence(c.days, c.target);
    case 'engine.dietNudge':      return c => withFrozenClock(c.nowISO, () => m.dietNudge(c.today, c.target));
    case 'engine.checkinAdvice':  return c => m.checkinAdvice(c.plan, c.expected, c.actual, c.adherence);
    case 'engine.planDrift':      return c => m.planDrift(c.plan, c.scans, c.profile);
    case 'engine.buildPlan':      return c => m.buildPlan(c.comparison, c.level, c.scan, c.profile);
    default: throw new Error('모르는 모듈: ' + module);
  }
}

function runJs(module, cases) {
  const call = jsCaller(module);
  return cases.map(c => {
    try { return { ok: true, v: JSON.parse(JSON.stringify(call(c) ?? null)) }; }
    catch (e) { return { ok: false, v: String(e && e.message || e) }; }
  });
}

/* --- Dart 쪽 실행 -------------------------------------------------------- */
function runDart(module, casesFile, noiseFile) {
  const r = spawnSync(DART, ['run', path.join(PKG, 'bin', 'diffrun.dart'), module, casesFile, noiseFile || ''],
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

/* 모듈마다 사례 모양과 **감당할 수 있는 개수**가 다릅니다.
   scanCurve 한 건은 208주짜리 시뮬레이션을 51번 돌립니다 — 3000건을
   넣으면 며칠이 걸리고 출력이 수 GB 가 됩니다. 적게 넣되 한 건이
   훨씬 깊습니다. cap 은 "이 모듈은 이보다 많이 넣지 않는다" 입니다. */
const MODULES = [
  { name: 'crosscheck',               gen: makeScanCases },
  { name: 'engine.validateScan',      gen: makeScanCases },
  { name: 'engine.derive',            gen: makeScanCases },
  { name: 'engine.classifyGoal',      gen: makePlanCases },
  { name: 'engine.paramsAt',          gen: makePlanCases },
  { name: 'engine.resolveTraining',   gen: makePlanCases },
  { name: 'engine.baseSmmRatePerWeek',gen: makePlanCases },
  { name: 'engine.stepWeek',          gen: makePlanCases },
  { name: 'engine.simulateSimultaneous', gen: makePlanCases, cap: 300 },
  { name: 'engine.simulateSplit',     gen: makePlanCases, cap: 300 },
  { name: 'engine.bestAt',            gen: makePlanCases, cap: 300 },
  { name: 'engine.scanCurve',         gen: makePlanCases, cap: 12 },
  { name: 'engine.compareLevels',     gen: makePlanCases, cap: 10 },
  { name: 'engine.macrosFor',         gen: makePlanCases, cap: 200 },
  { name: 'engine.workoutFor',        gen: makePlanCases, cap: 200 },
  { name: 'engine.dietFor',           gen: makePlanCases, cap: 200 },
  { name: 'engine.milestonesFrom',    gen: makePlanCases, cap: 200 },
  { name: 'engine.dietAdherence',     gen: makePlanCases },
  { name: 'engine.dietNudge',         gen: makePlanCases },
  { name: 'engine.checkinAdvice',     gen: makePlanCases },
  { name: 'modes.select',             gen: makePlanCases },
  { name: 'engine.planDrift',         gen: makePlanCases, cap: 40 },
  { name: 'engine.buildPlan',         gen: makePlanCases, cap: 10 }
];
let failed = 0;

for (const spec of MODULES) {
  const m = spec.name;
  if (ONLY && ONLY !== m) continue;
  const n = Math.min(N, spec.cap || N);
  process.stdout.write('\n' + m + ' — 사례 ' + n + '개 (씨앗 ' + SEED + ')\n');

  const made = spec.gen(n, SEED, m);
  const tmp = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'mybody-diff-')), 'cases.json');
  fs.writeFileSync(tmp, JSON.stringify(made));

  /* **파일에서 다시 읽어서 JS 에 넣습니다.**
   *
   * 안 그러면 양쪽이 다른 입력을 받습니다. JSON.stringify 는 NaN 을
   * null 로 바꿔 쓰는데, 메모리의 배열에는 NaN 이 그대로 있습니다.
   * 그래서 JS 는 NaN 을, Dart 는 null 을 받고 — 자바스크립트에서 그 둘은
   * 산수 결과가 다릅니다(NaN*2=NaN, null*2=0). 옮긴 코드가 멀쩡한데도
   * 갈렸다고 나왔습니다. 한동안 진짜 차이인 줄 알고 들여다봤습니다.
   *
   * 검사가 비교하는 것은 **같은 입력에 대한 두 답**이어야 합니다.
   * 입력이 다르면 무엇을 비교하고 있는지 알 수가 없습니다. */
  const cases = JSON.parse(fs.readFileSync(tmp, 'utf8'));

  /* NOISE 는 사례마다 같은 객체라 따로 한 번만 넘깁니다 (근거 문장이 10KB). */
  const noiseFile = path.join(path.dirname(tmp), 'noise.json');
  fs.writeFileSync(noiseFile, JSON.stringify(loadJs('modes').NOISE));

  const js = runJs(m, cases);
  const dr = runDart(m, tmp, noiseFile);
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
    console.log('  ✓ ' + n + '개 전부 같은 답을 냅니다');
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
