/* =============================================================================
 * store.js — localStorage 상태 저장소 (프로토타입용, 전부 로컬)
 * 서버 없음. 건강 데이터는 이 기기 밖으로 나가지 않는다.
 * ========================================================================== */
(function (global) {
  'use strict';
  var KEY = 'mybody.state.v1';
  var VERSION = 1;

  function blank() {
    return {
      version: VERSION,
      profile: null,
      scans: [],
      goal: null,
      goalHistory: [],
      comparison: null,
      plan: null,
      baselinePlan: null,
      checkins: [],
      foodLogs: [],
      foodFavorites: [],
      settings: { theme: 'auto', units: 'metric', checkinEveryWeeks: 1, defaultLevel: 'mid' },
      onboarded: false,
      disclaimerAccepted: false
    };
  }

  var state = blank();
  var listeners = [];

  function load() {
    try {
      var raw = localStorage.getItem(KEY);
      if (raw) {
        var parsed = JSON.parse(raw);
        if (parsed && parsed.version === VERSION) state = Object.assign(blank(), parsed);
      }
    } catch (e) { /* 손상 시 초기 상태 */ }
    return state;
  }

  function save() {
    try { localStorage.setItem(KEY, JSON.stringify(state)); } catch (e) {}
    listeners.forEach(function (f) { try { f(state); } catch (e) {} });
  }

  function get() { return state; }
  function set(patch) { Object.assign(state, patch); save(); return state; }
  function onChange(fn) { listeners.push(fn); }

  function reset() { state = blank(); save(); }

  /** 오너의 실제 인바디 데이터로 채운다 (프로토타입 검증용 한 방 버튼) */
  function seed() {
    var D = global.MB_DATA;
    state = blank();
    state.profile = JSON.parse(JSON.stringify(D.SEED_PROFILE));
    state.scans = JSON.parse(JSON.stringify(D.SEED_SCANS));
    state.onboarded = true;
    state.disclaimerAccepted = true;
    save();
    return state;
  }

  function latestScan() {
    if (!state.scans.length) return null;
    return state.scans.slice().sort(function (a, b) {
      return new Date(b.measuredAt) - new Date(a.measuredAt);
    })[0];
  }
  function sortedScans() {
    return state.scans.slice().sort(function (a, b) {
      return new Date(a.measuredAt) - new Date(b.measuredAt);
    });
  }
  function addScan(scan) {
    var i = state.scans.findIndex(function (s) { return s.id === scan.id; });
    if (i >= 0) state.scans[i] = scan; else state.scans.push(scan);
    save();
  }
  function removeScan(id) {
    state.scans = state.scans.filter(function (s) { return s.id !== id; });
    save();
  }
  function scanById(id) { return state.scans.find(function (s) { return s.id === id; }) || null; }

  /**
   * 목표를 바꾼다. 이전 목표는 이력에 남긴다.
   * 목표를 바꿀 때마다 이전 값이 사라지면 "내가 뭘 목표로 했었지"를 알 수 없고,
   * 추이 화면의 목표선이 언제 왜 움직였는지도 설명할 수 없다.
   */
  function setGoal(goal, reason) {
    if (state.goal) {
      state.goalHistory = state.goalHistory || [];
      state.goalHistory.push({
        goal: JSON.parse(JSON.stringify(state.goal)),
        setAt: state.goal.setAt || null,
        replacedAt: new Date().toISOString(),
        reason: reason || null,
        planLevel: state.plan ? state.plan.level : null,
        planTargetDate: state.plan ? state.plan.targetDate : null
      });
      if (state.goalHistory.length > 30) state.goalHistory.shift();
    }
    var next = JSON.parse(JSON.stringify(goal));
    next.setAt = new Date().toISOString();
    state.goal = next;
    save();
    return next;
  }

  function sameGoal(a, b) {
    if (!a || !b) return false;
    function near(x, y) { return Math.abs((x || 0) - (y || 0)) < 0.05; }
    return near(a.weightKg, b.weightKg) && near(a.smmKg, b.smmKg) && near(a.bfmKg, b.bfmKg);
  }

  /**
   * 플랜을 저장한다. 목표가 그대로인 채 다시 만든 것이면 "원래 계획"은 건드리지 않는다.
   * 계획을 갱신할 때마다 원본이 사라지면 "계획보다 빠른가 느린가"를 영영 말할 수 없다.
   */
  function setPlan(plan) {
    var freshGoal = !state.baselinePlan || !sameGoal(state.baselinePlan.goal, plan.goal);
    state.plan = plan;
    if (freshGoal) {
      state.baselinePlan = JSON.parse(JSON.stringify(plan));
      state.baselinePlan.isBaseline = true;
    }
    save();
    return plan;
  }

  /** 지금 플랜이 지금 목표로 만들어진 것인가 */
  function planMatchesGoal() {
    if (!state.plan || !state.goal) return true;
    var g = state.plan.goal;
    if (!g) return false;
    function near(a, b) { return Math.abs((a || 0) - (b || 0)) < 0.05; }
    return near(g.weightKg, state.goal.weightKg) &&
           near(g.smmKg, state.goal.smmKg) &&
           near(g.bfmKg, state.goal.bfmKg) &&
           (g.modeId || null) === (state.goal.modeId || null);
  }

  /* --- 식단 기록 ----------------------------------------------------------
   * 핵심 규칙: 기록하지 않은 날을 0으로 치환하지 않는다.
   * 0으로 채우면 주 평균이 폭락하고, 엔진은 "이 사람 대사가 예상보다 낮다"고
   * 판단해 칼로리를 더 깎는다. 실제로는 목표치를 먹고 있었는데도.
   * 그래서 미기록일은 분모에서 빼고, 뺐다는 사실을 화면에 쓴다.
   * -------------------------------------------------------------------- */
  function dayKey(d) {
    var x = d ? new Date(d) : new Date();
    return x.getFullYear() + '-' + String(x.getMonth() + 1).padStart(2, '0') + '-' +
           String(x.getDate()).padStart(2, '0');
  }

  function addFoodLog(entry) {
    state.foodLogs = state.foodLogs || [];
    var row = {
      id: entry.id || ('f' + Date.now() + '_' + Math.floor(state.foodLogs.length)),
      date: entry.date || dayKey(),
      meal: entry.meal || '간식',
      items: entry.items || [],
      source: entry.source || 'manual',     // manual | photo | recent
      at: entry.at || new Date().toISOString()
    };
    state.foodLogs.push(row);
    if (state.foodLogs.length > 20000) state.foodLogs.shift();
    save();
    return row;
  }
  function removeFoodLog(id) {
    state.foodLogs = (state.foodLogs || []).filter(function (x) { return x.id !== id; });
    save();
  }
  function logsForDate(date) {
    var k = dayKey(date);
    return (state.foodLogs || []).filter(function (x) { return x.date === k; });
  }
  function sumItems(items) {
    var t = { kcal: 0, p: 0, c: 0, f: 0 };
    (items || []).forEach(function (i) {
      t.kcal += i.kcal || 0; t.p += i.p || 0; t.c += i.c || 0; t.f += i.f || 0;
    });
    t.kcal = Math.round(t.kcal);
    t.p = Math.round(t.p * 10) / 10;
    t.c = Math.round(t.c * 10) / 10;
    t.f = Math.round(t.f * 10) / 10;
    return t;
  }
  function dayTotals(date) {
    var logs = logsForDate(date);
    var all = [];
    logs.forEach(function (l) { all = all.concat(l.items || []); });
    var t = sumItems(all);
    t.logged = logs.length > 0;
    t.entries = logs.length;
    return t;
  }
  /** 기록이 하나라도 있는 날짜 목록 (미기록일 판정의 기준) */
  function loggedDates() {
    var set = {};
    (state.foodLogs || []).forEach(function (x) { set[x.date] = true; });
    return Object.keys(set).sort();
  }
  /** 최근에 먹은 것 — 마찰을 줄이는 가장 효과적인 장치 */
  function recentFoods(limit) {
    var seen = {}, out = [];
    var logs = (state.foodLogs || []).slice().reverse();
    for (var i = 0; i < logs.length && out.length < (limit || 12); i++) {
      (logs[i].items || []).forEach(function (it) {
        if (out.length >= (limit || 12)) return;
        if (seen[it.name]) return;
        seen[it.name] = true;
        out.push(it);
      });
    }
    return out;
  }
  function toggleFavorite(name) {
    state.foodFavorites = state.foodFavorites || [];
    var i = state.foodFavorites.indexOf(name);
    if (i >= 0) state.foodFavorites.splice(i, 1); else state.foodFavorites.push(name);
    save();
    return state.foodFavorites.indexOf(name) >= 0;
  }
  function isFavorite(name) { return (state.foodFavorites || []).indexOf(name) >= 0; }

  function exportJSON() { return JSON.stringify(state, null, 2); }
  function importJSON(text) {
    var parsed = JSON.parse(text);
    if (!parsed || parsed.version !== VERSION) throw new Error('버전이 맞지 않는 데이터입니다');
    state = Object.assign(blank(), parsed);
    save();
  }

  global.MB_STORE = {
    load: load, save: save, get: get, set: set, reset: reset, seed: seed,
    onChange: onChange, latestScan: latestScan, sortedScans: sortedScans,
    addScan: addScan, removeScan: removeScan, scanById: scanById,
    setGoal: setGoal, setPlan: setPlan, planMatchesGoal: planMatchesGoal, sameGoal: sameGoal,
    dayKey: dayKey, addFoodLog: addFoodLog, removeFoodLog: removeFoodLog,
    logsForDate: logsForDate, dayTotals: dayTotals, sumItems: sumItems,
    loggedDates: loggedDates, recentFoods: recentFoods,
    toggleFavorite: toggleFavorite, isFavorite: isFavorite,
    exportJSON: exportJSON, importJSON: importJSON, blank: blank
  };
})(window);
