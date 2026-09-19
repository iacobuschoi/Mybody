/* =============================================================================
 * tools/simulate.js — 가상 사용자 시뮬레이션
 *
 *   USERS=100 YEARS=3 node tools/simulate.js
 *
 * 100명이 3년 동안 앱의 모든 기능을 쓰는 상황을 주 단위로 돌립니다.
 * 목적은 "잘 돌아간다"를 보는 게 아니라 **깨지는 지점을 찾는 것**입니다.
 * 매 주 불변식을 검사하고, 깨지면 그 순간의 상태와 함께 기록합니다.
 * ========================================================================== */
'use strict';
const path = require('node:path');
const fs = require('node:fs');

global.window = global;
require(path.join(__dirname, '..', 'prototype', 'js', 'data.js'));
require(path.join(__dirname, '..', 'prototype', 'js', 'modes.js'));
require(path.join(__dirname, '..', 'prototype', 'js', 'fooddb.js'));
require(path.join(__dirname, '..', 'prototype', 'js', 'engine.js'));
const E = global.MB_ENGINE, MODES = global.MB_MODES, FOOD = global.MB_FOOD;
const { open, makeApi } = require(path.join(__dirname, '..', 'server', 'db.js'));

const N_USERS = Number(process.env.USERS || 100);
const YEARS = Number(process.env.YEARS || 3);
const WEEKS = Math.round(YEARS * 52);
const DB_FILE = process.env.SIM_DB || '/tmp/mybody-sim.db';
const SEED = Number(process.env.SEED || 20260919);

try { fs.unlinkSync(DB_FILE); fs.unlinkSync(DB_FILE + '-wal'); fs.unlinkSync(DB_FILE + '-shm'); } catch {}
const api = makeApi(open(DB_FILE));

/* --- 결정적 난수 (같은 시드 = 같은 결과, 버그 재현 가능) ------------------ */
let _s = SEED >>> 0;
function rnd() { _s ^= _s << 13; _s >>>= 0; _s ^= _s >> 17; _s ^= _s << 5; _s >>>= 0; return _s / 4294967296; }
function pick(a) { return a[Math.floor(rnd() * a.length)]; }
function between(a, b) { return a + rnd() * (b - a); }
function chance(p) { return rnd() < p; }

/* --- 문제 기록 ------------------------------------------------------------ */
const issues = [];
function fail(kind, detail, ctx) {
  issues.push({ kind, detail, ctx });
  if (issues.length > 4000) issues.length = 4000;
}
const counters = {};
function bump(k, n = 1) { counters[k] = (counters[k] || 0) + n; }

/* --- 가상 사용자 ---------------------------------------------------------- */
const START = new Date('2026-01-05T00:00:00Z');   // 월요일
function weekISO(w) {
  const d = new Date(START.getTime() + w * 7 * 86400000);
  return d.toISOString().slice(0, 10);
}

function makeUser(i) {
  const sex = chance(0.68) ? 'male' : 'female';
  const heightCm = sex === 'male' ? Math.round(between(163, 192)) : Math.round(between(150, 178));
  const age = Math.round(between(19, 58));
  // 시작 체성분을 사람마다 넓게 깐다 — 마른 사람, 비만, 근육질 전부 나오게
  const bmi = between(17.5, 36);
  const weightKg = +(bmi * Math.pow(heightCm / 100, 2)).toFixed(1);
  const pbf = sex === 'male' ? between(8, 38) : between(18, 46);
  const bfmKg = +(weightKg * pbf / 100).toFixed(1);
  const ffmKg = +(weightKg - bfmKg).toFixed(1);
  const smmKg = +(ffmKg * between(0.50, 0.60)).toFixed(1);
  return {
    i, handle: 'sim:' + i,
    profile: {
      sex, age, heightCm,
      activityLevel: pick(['sedentary', 'light', 'moderate', 'moderate', 'active', 'veryActive']),
      trainingAge: pick(['novice', 'novice', 'intermediate', 'intermediate', 'advanced', 'elite']),
      daysPerWeek: Math.round(between(2, 6)),
      sessionMinutes: pick([30, 45, 60, 60, 90]),
      environment: pick(['gym', 'home', 'hybrid']),
      injuries: '', dietFlags: [], mealsPerDay: pick([2, 3, 3, 4]),
      cookingLevel: pick(['none', 'simple', 'free']),
      hadPriorPeak: chance(0.18)
    },
    body: { weightKg, smmKg, bfmKg },
    // 성향
    diligence: between(0.15, 0.98),        // 측정·체크인 빈도
    adherence: between(0.35, 1.0),         // 계획을 얼마나 지키는가
    social: between(0, 1),                 // 친구 활동성
    churnWeek: chance(0.35) ? Math.round(between(8, WEEKS)) : null,   // 도중 이탈
    returnWeek: null,
    logHabit: between(0, 1),               // 식단을 얼마나 꾸준히 적는가
    logDecay: between(0.994, 1.0),         // 시간이 갈수록 기록이 줄어드는 정도
    token: null, id: null,
    foodDays: [],                          // [{date, logged, kcal, p, c, f}]
    scans: [], goal: null, plan: null, baselinePlan: null, checkins: [],
    goalHistory: [], lastScanWeek: -99, active: true, friends: new Set()
  };
}

/* --- 몸의 실제 변화(앱 바깥의 현실) --------------------------------------- */
function advanceBody(u, week) {
  const b = u.body;
  const k = b.smmKg / (b.weightKg - b.bfmKg);
  if (!u.plan || !u.active) {
    // 계획이 없으면 서서히 원래대로 — 약간 찌는 쪽
    b.bfmKg += between(-0.05, 0.12);
    b.smmKg += between(-0.03, 0.02);
  } else {
    const t = u.plan.trajectory;
    const w = Math.max(0, Math.min(t.length - 2, week - u.plan.startWeek));
    const dF = (t[w + 1].bfmKg - t[w].bfmKg);
    const dS = (t[w + 1].smmKg - t[w].smmKg);
    // 계획대로 100% 가지 않는다. 순응도 + 노이즈.
    b.bfmKg += dF * u.adherence + between(-0.12, 0.12);
    b.smmKg += dS * u.adherence + between(-0.04, 0.04);
  }
  b.bfmKg = Math.max(1.5, b.bfmKg);
  b.smmKg = Math.max(8, b.smmKg);
  b.weightKg = +(b.smmKg / k + b.bfmKg).toFixed(1);
  b.bfmKg = +b.bfmKg.toFixed(1);
  b.smmKg = +b.smmKg.toFixed(1);
}

function measure(u, week) {
  // 인바디 측정 노이즈 — 수분/시각 변동
  const n = () => between(-0.6, 0.6);
  const scan = {
    id: 'scan-' + u.i + '-' + week,
    measuredAt: new Date(START.getTime() + week * 7 * 86400000 + 8 * 3600000).toISOString(),
    device: 'InBody270', source: 'sheet',
    weightKg: +(u.body.weightKg + n() * 0.5).toFixed(1),
    smmKg: +(u.body.smmKg + n() * 0.5).toFixed(1),
    bfmKg: +Math.max(1, u.body.bfmKg + n()).toFixed(1)
  };
  scan.ffmKg = +(scan.weightKg - scan.bfmKg).toFixed(1);
  scan.pbfPct = +(scan.bfmKg / scan.weightKg * 100).toFixed(1);
  u.scans.push(scan);
  if (u.scans.length > 200) u.scans.shift();
  u.lastScanWeek = week;
  return scan;
}

/* --- 목표 만들기 ---------------------------------------------------------- */
function proposeGoal(u) {
  const scan = u.scans[u.scans.length - 1];
  if (!scan) return null;
  const cur = E.derive(scan, u.profile);
  const targetPbf = u.profile.sex === 'male' ? between(11, 20) : between(20, 29);
  const smm = +(cur.smmKg + between(-0.5, 3.0)).toFixed(1);
  const ffm = smm / cur.smmToFfm;
  const weight = +(ffm / (1 - targetPbf / 100)).toFixed(1);
  const bfm = +(weight - ffm).toFixed(1);
  return { weightKg: weight, smmKg: smm, bfmKg: bfm,
           deadlineWeeks: chance(0.3) ? Math.round(between(6, 40)) : null };
}

function selectMode(u, goal) {
  const scan = u.scans[u.scans.length - 1];
  const cur = E.derive(scan, u.profile);
  const gi = E.classifyGoal(cur, goal);
  let trend = null;
  if (u.scans.length >= 2) {
    const a = E.derive(u.scans[0], u.profile), b = cur;
    const days = (new Date(scan.measuredAt) - new Date(u.scans[0].measuredAt)) / 86400000;
    trend = { weeksSpan: days / 7, dWeightKg: b.weightKg - a.weightKg,
              dSmmKg: b.smmKg - a.smmKg, dBfmKg: b.bfmKg - a.bfmKg };
  }
  return MODES.select({
    dWeightKg: gi.dWeightKg, dSmmKg: gi.dSmmKg, dBfmKg: gi.dBfmKg,
    curWeightKg: cur.weightKg, curSmmKg: cur.smmKg, curBfmKg: cur.bfmKg,
    curPbfPct: cur.pbfPct, curBmi: cur.bmi, heightCm: u.profile.heightCm,
    tdeeKcal: cur.tdeeKcal, sex: u.profile.sex, age: u.profile.age,
    trainingAge: u.profile.trainingAge, hadPriorPeak: u.profile.hadPriorPeak,
    deadlineWeeks: goal.deadlineWeeks || null, recentTrend: trend, currentPhase: null
  });
}

function buildPlan(u, week, level) {
  const scan = u.scans[u.scans.length - 1];
  if (!scan || !u.goal) return null;
  const modeDef = u.goal.modeId ? MODES.byId(u.goal.modeId) : null;
  const startISO = weekISO(week);
  const cmp = E.compareLevels(scan, u.profile, u.goal, startISO, u.goal.deadlineWeeks || null, modeDef);
  if (cmp.impossible || !cmp.results.length) { bump('도달 불가 목표'); return null; }
  const lv = level && cmp.results.some(r => r.level === level) ? level
           : (cmp.recommended || 'mid');
  const plan = E.buildPlan(cmp, lv, scan, u.profile);
  if (!plan) return null;
  plan.startWeek = week;
  return plan;
}

/* --- 식단 기록 ------------------------------------------------------------
 * 하루 단위로 돈다. 핵심은 "안 적은 날"이 충분히 많이 생기게 하는 것 —
 * 미기록일 처리가 이 기능의 가장 위험한 지점이기 때문이다.                  */
function logFoodForWeek(u, week) {
  if (!u.plan) return;
  const target = u.plan.macros;
  // 기록 습관은 시간이 갈수록 떨어진다 (실제 앱의 이탈 패턴)
  const habit = u.logHabit * Math.pow(u.logDecay, week);
  for (let d = 0; d < 7; d++) {
    const date = new Date(START.getTime() + (week * 7 + d) * 86400000).toISOString().slice(0, 10);
    if (!chance(habit)) { u.foodDays.push({ date, logged: false }); continue; }

    // 그날 실제로 먹은 양 — 순응도에 노이즈를 얹는다
    const drift = between(-0.28, 0.35);
    const kcal = Math.max(300, Math.round(target.intakeKcal * (1 + drift * (1 - u.adherence * 0.6))));
    const pRatio = between(0.55, 1.25);
    const items = [];
    let acc = { kcal: 0, p: 0, c: 0, f: 0 };
    // 실제 음식으로 채운다 — 음식 DB의 값이 합쳐지는 경로도 같이 검사한다
    let guard = 0;
    while (acc.kcal < kcal * 0.9 && guard++ < 12) {
      const food = pick(FOOD.FOODS);
      const mult = pick([0.5, 1, 1, 1.5, 2]);
      const sc = FOOD.scaled(food, mult);
      items.push(sc);
      acc.kcal += sc.kcal; acc.p += sc.p; acc.c += sc.c; acc.f += sc.f;
    }
    const day = { date, logged: true,
                  kcal: Math.round(acc.kcal),
                  p: Math.round(acc.p * pRatio * 10) / 10,
                  c: Math.round(acc.c * 10) / 10,
                  f: Math.round(acc.f * 10) / 10 };
    u.foodDays.push(day);
    bump('식단 기록');

    // 불변식: 항목 합이 유한하고 음수가 아니어야 한다
    if (![day.kcal, day.p, day.c, day.f].every(v => isFinite(v) && v >= 0)) {
      fail('식단 합계 비정상', JSON.stringify(day), { user: u.i, week });
    }
    // 오늘 안내가 어떤 입력에도 죽지 않아야 한다
    const nudge = E.dietNudge(day, target);
    if (!nudge || !nudge.text) fail('dietNudge 결과 없음', JSON.stringify(day), { user: u.i, week });
    else if (/그만|먹지|금지/.test(nudge.text)) {
      fail('금지형 문구가 나왔다', nudge.text, { user: u.i, week });
    }
  }
  if (u.foodDays.length > 1200) u.foodDays = u.foodDays.slice(-1200);
}

function checkAdherence(u, week) {
  if (!u.plan || u.foodDays.length < 7) return;
  const target = u.plan.macros;
  [7, 30].forEach(n => {
    const days = u.foodDays.slice(-n);
    const a = E.dietAdherence(days, target);
    const ctx = { user: u.i, week, window: n };
    if (!a) { fail('dietAdherence 결과 없음', '', ctx); return; }
    const loggedCount = days.filter(d => d.logged).length;
    if (a.loggedDays !== loggedCount) fail('기록일수 계산 오류', a.loggedDays + ' vs ' + loggedCount, ctx);
    if (a.totalDays !== days.length) fail('전체일수 계산 오류', a.totalDays + ' vs ' + days.length, ctx);
    if (!loggedCount) {
      if (a.avg !== null) fail('기록 없는데 평균이 나왔다', JSON.stringify(a.avg), ctx);
      return;
    }
    if (!a.avg) { fail('기록이 있는데 평균이 없다', '', ctx); return; }
    // 가장 중요한 불변식: 미기록일을 0으로 치환하면 평균이 실제보다 낮아진다.
    // 기록한 날만의 산술평균과 정확히 같아야 한다.
    const manual = days.filter(d => d.logged)
      .reduce((s2, d) => s2 + d.kcal, 0) / loggedCount;
    if (Math.abs(a.avg.kcal - Math.round(manual)) > 1) {
      fail('평균이 기록일 기준이 아니다', a.avg.kcal + ' vs ' + Math.round(manual), ctx);
    }
    const naive = days.reduce((s2, d) => s2 + (d.kcal || 0), 0) / days.length;
    if (loggedCount < days.length && Math.abs(a.avg.kcal - naive) < 1) {
      fail('미기록일을 0으로 세고 있다', a.avg.kcal + ' == ' + Math.round(naive), ctx);
    }
    ['kcal', 'p', 'c', 'f'].forEach(k => {
      if (!isFinite(a.avg[k]) || a.avg[k] < 0) fail('평균 비정상', k + '=' + a.avg[k], ctx);
    });
    if (a.inBandDays > loggedCount) fail('범위 안 일수가 기록일수보다 많다', '', ctx);
    if (a.proteinHitDays > loggedCount) fail('단백질 달성일이 기록일수보다 많다', '', ctx);
    if (a.logRatePct < 0 || a.logRatePct > 100) fail('기록률 범위 이탈', String(a.logRatePct), ctx);
  });
}

/* --- 불변식 검사 ---------------------------------------------------------- */
function checkPlan(u, plan, week) {
  if (!plan) return;
  const ctx = { user: u.i, week, mode: u.goal && u.goal.modeId, level: plan.level,
                pal: u.profile.activityLevel, ta: u.profile.trainingAge };
  if (!(plan.weeks > 0) || !isFinite(plan.weeks)) fail('plan.weeks 비정상', String(plan.weeks), ctx);
  if (!plan.targetDate || isNaN(new Date(plan.targetDate))) fail('plan.targetDate 비정상', String(plan.targetDate), ctx);
  const m = plan.macros;
  if (!m) { fail('macros 없음', '', ctx); return; }
  ['intakeKcal', 'proteinG', 'carbG', 'fatG'].forEach(k => {
    if (!isFinite(m[k])) fail('매크로 NaN', k + '=' + m[k], ctx);
  });
  if (m.intakeKcal < 900) fail('섭취량이 너무 낮음', m.intakeKcal + 'kcal', ctx);
  if (m.intakeKcal > 6000) fail('섭취량이 너무 높음', m.intakeKcal + 'kcal · 체중 ' +
    Math.round(plan.trajectory[0].weightKg) + 'kg · 제지방 ' + Math.round(plan.trajectory[0].ffmKg) +
    'kg · TDEE ' + m.tdeeKcal + ' · 활동 ' + (ctx.pal || '?'), ctx);
  if (m.proteinG < 40) fail('단백질이 너무 낮음', m.proteinG + 'g', ctx);
  if (m.proteinG / m.intakeKcal * 4 > 0.65) fail('단백질 비중이 비현실적', Math.round(m.proteinG * 4 / m.intakeKcal * 100) + '%', ctx);
  if (m.carbG < 0 || m.fatG < 0) fail('매크로 음수', JSON.stringify(m), ctx);
  const t = plan.trajectory || [];
  for (let i = 0; i < t.length; i++) {
    if (!isFinite(t[i].weightKg) || !isFinite(t[i].smmKg) || !isFinite(t[i].bfmKg)) {
      fail('궤적 NaN', 'week ' + i, ctx); break;
    }
    if (t[i].bfmKg < 0 || t[i].smmKg < 0 || t[i].weightKg < 20) {
      fail('궤적 값이 비현실적', JSON.stringify(t[i]), ctx); break;
    }
    if (t[i].pbfPct < 2) { fail('궤적 체지방률 2% 미만', JSON.stringify(t[i]), ctx); break; }
  }
  if (t.length > 300) fail('궤적이 너무 김', t.length + '주', ctx);
  if (plan.workout) {
    if (plan.workout.daysPerWeek < 1 || plan.workout.daysPerWeek > 7) fail('운동일수 비정상', String(plan.workout.daysPerWeek), ctx);
    if (!plan.workout.sessions || plan.workout.sessions.length !== 7) fail('주간 스케줄이 7일이 아님', '', ctx);
  }
  if (plan.diet && plan.diet.meals) {
    const sum = plan.diet.meals.reduce((a, x) => a + x.kcal, 0);
    if (Math.abs(sum - m.intakeKcal) > m.intakeKcal * 0.12) {
      fail('끼니 합이 하루 목표와 어긋남', sum + ' vs ' + m.intakeKcal, ctx);
    }
  }
  if (!plan.milestones || !plan.milestones.length) fail('마일스톤 없음', '', ctx);
}

/* --- 소셜 불변식: 허용 안 된 값이 새는지 --------------------------------- */
const TREND_KEYS = { weightTrend: 'dWeightKg', smmTrend: 'dSmmKg', bfmTrend: 'dBfmKg',
                     planProgress: 'progressPct', streak: 'checkedIn' };
const ABS_KEYS = ['weightKg', 'smmKg', 'bfmKg', 'pbfPct'];
// 실제 수치는 그 항목을 켰을 때만 나갈 수 있습니다 (absolute 는 표시 방식일 뿐)
const ABS_OWNER = { weightKg: 'weightTrend', smmKg: 'smmTrend',
                    bfmKg: 'bfmTrend', pbfPct: 'bfmTrend' };

function checkLeak(viewer, owner, res, week) {
  if (!res.ok) return;
  const allowed = api.shareFields(owner.id, viewer.id);
  for (const row of res.rows) {
    for (const [flag, key] of Object.entries(TREND_KEYS)) {
      if (row[key] !== undefined && !allowed[flag]) {
        fail('공유 안 한 값이 샜다', key + ' (' + flag + ' 꺼짐)',
             { viewer: viewer.i, owner: owner.i, week, row });
      }
    }
    for (const k of ABS_KEYS) {
      if (row[k] === undefined) continue;
      if (!allowed.absolute) {
        fail('실제 수치가 샜다', k, { viewer: viewer.i, owner: owner.i, week, row });
      } else if (!allowed[ABS_OWNER[k]]) {
        fail('안 켠 항목이 실제 수치로 샜다', k + ' (' + ABS_OWNER[k] + ' 꺼짐)',
             { viewer: viewer.i, owner: owner.i, week, row });
      }
    }
    for (const k of Object.keys(row)) {
      if (k === 'weekStart') continue;
      const known = Object.values(TREND_KEYS).includes(k) || ABS_KEYS.includes(k);
      if (!known) fail('모르는 키가 응답에 있다', k, { viewer: viewer.i, owner: owner.i, week });
    }
  }
}

/* ========================================================================== */
console.log(`시뮬레이션 시작 — 사용자 ${N_USERS}명 · ${YEARS}년(${WEEKS}주) · 시드 ${SEED}`);
const t0 = Date.now();
const users = [];
for (let i = 0; i < N_USERS; i++) {
  const u = makeUser(i);
  const s = api.signIn({ provider: 'kakao', handle: u.handle, displayName: '사용자' + i });
  u.token = s.token; u.id = s.user.id; u.inviteCode = s.user.inviteCode;
  users.push(u);
}
bump('가입', users.length);

for (let week = 0; week < WEEKS; week++) {
  for (const u of users) {
    /* 이탈과 복귀 */
    if (u.churnWeek !== null && week === u.churnWeek) {
      u.active = false;
      u.returnWeek = chance(0.55) ? week + Math.round(between(4, 40)) : null;
      bump('이탈');
    }
    if (!u.active && u.returnWeek !== null && week >= u.returnWeek) {
      u.active = true;
      if (!u.id) {
        // 탈퇴했다가 돌아온 경우 — 실제 앱에서도 새 계정이 된다.
        // 기기에 남아 있던 측정 기록은 그대로지만 친구 관계는 사라진다.
        const s2 = api.signIn({ provider: 'kakao', handle: u.handle + ':again' + week,
                                displayName: '사용자' + u.i });
        u.token = s2.token; u.id = s2.user.id; u.inviteCode = s2.user.inviteCode;
        u.friends.clear();
        bump('재가입');
        if (api.listFriends(u.id).accepted.length) {
          fail('재가입했는데 옛 친구가 남아 있다', 'user=' + u.i, { week });
        }
      }
      bump('복귀');
    }

    advanceBody(u, week);
    if (!u.active) continue;

    /* 측정 */
    const gap = week - u.lastScanWeek;
    const wantScan = u.scans.length === 0 || gap >= Math.round(2 + (1 - u.diligence) * 10);
    if (wantScan && chance(0.85)) {
      measure(u, week);
      bump('측정');
    }
    if (!u.scans.length) continue;

    /* 목표 설정 / 달성 / 변경 */
    if (!u.goal && chance(0.6)) {
      const g = proposeGoal(u);
      if (g) {
        const sel = selectMode(u, g);
        if (sel.refused) { bump('목표 거부'); }
        else {
          g.modeId = sel.modeId;
          u.goalHistory.push({ goal: JSON.parse(JSON.stringify(g)), atWeek: week });
          u.goal = g;
          bump('목표 설정');
          const p = buildPlan(u, week, null);
          if (p) { u.plan = p; u.baselinePlan = JSON.parse(JSON.stringify(p)); checkPlan(u, p, week); bump('플랜 생성'); }
          else { u.goal = null; }     // 도달 불가 → 목표를 접고 다음에 다시 잡는다
        }
      }
    }

    if (u.goal && u.plan) {
      const cur = E.derive(u.scans[u.scans.length - 1], u.profile);
      const reachedFat = cur.bfmKg <= u.goal.bfmKg + 0.3;
      const reachedSmm = cur.smmKg >= u.goal.smmKg - 0.3;
      if (reachedFat && reachedSmm) {
        bump('목표 달성');
        u.goal = null; u.plan = null; u.baselinePlan = null;    // 새 목표를 다시 잡게 둔다
      } else if (chance(0.03)) {                                 // 가끔 목표를 바꾼다
        const g = proposeGoal(u);
        if (g) {
          const sel = selectMode(u, g);
          if (!sel.refused) {
            g.modeId = sel.modeId;
            u.goalHistory.push({ goal: JSON.parse(JSON.stringify(g)), atWeek: week });
            u.goal = g;
            const p = buildPlan(u, week, u.plan.level);
            if (p) { u.plan = p; checkPlan(u, p, week); bump('목표 변경'); }
          }
        }
      }
    }

    /* 체크인 + 이탈 감지 + 재조정 */
    if (u.plan && chance(u.diligence * 0.8)) {
      u.checkins.push({ week });
      bump('체크인');
      const drift = E.planDrift(u.plan, u.scans, u.profile);
      if (drift) {
        if (!isFinite(drift.weeksAhead)) fail('planDrift NaN', JSON.stringify(drift), { user: u.i, week });
        if (drift.recommendChange && chance(0.5)) {
          const p = buildPlan(u, week, u.plan.level);
          if (p) { u.plan = p; checkPlan(u, p, week); bump('계획 재조정'); }
        }
      }
    }

    /* 식단 기록 + 달성률 */
    logFoodForWeek(u, week);
    if (week % 2 === 0) checkAdherence(u, week);

    /* 주간 스냅샷 게시 */
    if (u.scans.length >= 2) {
      const prof = u.profile;
      const a = E.derive(u.scans[u.scans.length - 2], prof);
      const b = E.derive(u.scans[u.scans.length - 1], prof);
      let progress = null;
      if (u.plan && u.goal) {
        const s0 = u.plan.trajectory[0].bfmKg, t0g = u.goal.bfmKg;
        if (Math.abs(s0 - t0g) > 0.01) {
          progress = Math.max(0, Math.min(100, Math.round((s0 - b.bfmKg) / (s0 - t0g) * 100)));
        }
      }
      const snapRes = api.publishSnapshot(u.id, weekISO(week), {
        dWeightKg: +(b.weightKg - a.weightKg).toFixed(1),
        dSmmKg: +(b.smmKg - a.smmKg).toFixed(2),
        dBfmKg: +(b.bfmKg - a.bfmKg).toFixed(2),
        progressPct: progress,
        checkedIn: u.checkins.some(c => c.week === week),
        weightKg: b.weightKg, smmKg: b.smmKg, bfmKg: b.bfmKg, pbfPct: b.pbfPct
      });
      if (!snapRes.ok) fail('스냅샷 게시 실패', snapRes.reason, { user: u.i, week });
      else bump('스냅샷');
    }

    /* 소셜 */
    if (chance(u.social * 0.12)) {                       // 친구 요청 보내기
      const other = pick(users);
      if (other !== u) {
        const r = api.sendRequest(u.id, other.inviteCode);
        if (r.ok) bump(r.status === 'accepted' ? '즉시 친구' : '요청 보냄');
      }
    }
    const inbox = api.listFriends(u.id);
    for (const req of inbox.incoming) {                  // 받은 요청 처리
      if (chance(0.55)) { api.accept(u.id, req.id); u.friends.add(req.id); bump('요청 수락'); }
      else if (chance(0.2)) { api.decline(u.id, req.id); bump('요청 거절'); }
    }
    for (const fr of inbox.accepted) {
      u.friends.add(fr.id);
      if (chance(0.06)) {                                // 공유 설정 토글
        const key = pick(MODES ? ['weightTrend', 'smmTrend', 'bfmTrend', 'planProgress', 'streak', 'absolute']
                              : ['streak']);
        const patch = {}; patch[key] = chance(0.6);
        const r = api.setShare(u.id, fr.id, patch);
        if (r.ok) bump('공유 변경');
      }
      if (chance(0.25)) {                                // 친구 화면 보기 → 유출 검사
        const owner = users.find(x => x.id === fr.id);
        if (owner) {
          const res = api.friendSnapshots(u.id, fr.id, 26);
          checkLeak(u, owner, res, week);
          bump('친구 조회');
        }
      }
      if (chance(0.004)) { api.removeFriend(u.id, fr.id); u.friends.delete(fr.id); bump('친구 끊기'); }
      if (chance(0.001)) { api.block(u.id, fr.id); u.friends.delete(fr.id); bump('차단'); }
    }

    /* 동기화 */
    if (chance(0.3)) {
      api.push(u.id, [{ kind: 'scan', id: u.scans[u.scans.length - 1].id,
                        updatedAt: u.scans[u.scans.length - 1].measuredAt,
                        payload: u.scans[u.scans.length - 1] }]);
      bump('동기화 push');
    }
  }

  /* 탈퇴한 사람이 남긴 흔적 검사 */
  if (week % 26 === 25) {
    const victim = users.find(x => x.active && x.id && chance(0.5));
    if (victim && N_USERS > 20) {
      const before = api.listFriends(victim.id).accepted.length;
      api.deleteMe(victim.id);
      bump('계정 삭제');
      for (const other of users) {
        if (other === victim || !other.id) continue;
        const l = api.listFriends(other.id);
        if (l.accepted.some(f => f.id === victim.id) ||
            l.incoming.some(f => f.id === victim.id) ||
            l.outgoing.some(f => f.id === victim.id)) {
          fail('삭제된 계정이 친구 목록에 남음', 'victim=' + victim.i, { other: other.i, week });
        }
        const snaps = api.friendSnapshots(other.id, victim.id, 5);
        if (snaps.ok && snaps.rows.length) {
          fail('삭제된 계정의 스냅샷이 아직 읽힘', 'victim=' + victim.i, { other: other.i, week });
        }
      }
      victim.active = false; victim.id = null;
      void before;
    }
  }

  if (week % 26 === 0) {
    process.stdout.write(`  ${week}주 (${(week / 52).toFixed(1)}년) · 문제 ${issues.length}건\n`);
  }
}

/* --- 결과 ---------------------------------------------------------------- */
const secs = ((Date.now() - t0) / 1000).toFixed(1);
console.log(`\n완료 — ${secs}초\n`);

console.log('=== 발생한 행동 ===');
Object.entries(counters).sort((a, b) => b[1] - a[1])
  .forEach(([k, v]) => console.log(`  ${k.padEnd(14)} ${String(v).padStart(7)}`));

const byKind = {};
issues.forEach(x => { (byKind[x.kind] = byKind[x.kind] || []).push(x); });
console.log(`\n=== 문제 ${issues.length}건 · ${Object.keys(byKind).length}종 ===`);
Object.entries(byKind).sort((a, b) => b[1].length - a[1].length).forEach(([k, list]) => {
  console.log(`\n[${list.length}건] ${k}`);
  list.slice(0, 3).forEach(x => console.log(`   ${x.detail}  ${JSON.stringify(x.ctx).slice(0, 150)}`));
});

const survivors = users.filter(u => u.active && u.id).length;
const withPlan = users.filter(u => u.plan).length;
console.log(`\n=== 끝난 시점 ===`);
console.log(`  활성 ${survivors}명 / ${N_USERS}명 · 플랜 보유 ${withPlan}명`);
console.log(`  총 측정 ${counters['측정'] || 0}건 · 스냅샷 ${counters['스냅샷'] || 0}건 · 친구 조회 ${counters['친구 조회'] || 0}건`);

fs.writeFileSync(path.join(__dirname, '.shots', 'simulation-issues.json'),
  JSON.stringify({ seed: SEED, users: N_USERS, weeks: WEEKS, counters, issues }, null, 1));
console.log(`\n상세: tools/.shots/simulation-issues.json`);
process.exit(issues.length ? 1 : 0);
