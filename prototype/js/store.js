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

  var publishing = false;

  function save() {
    try { localStorage.setItem(KEY, JSON.stringify(state)); } catch (e) {}
    // 친구에게 나갈 값이 바뀌었을 수 있으니 여기서 올린다.
    //
    // 호출처마다 publishWeekly() 를 넣는 방법도 있지만, 이 기능이 망가져 있던 이유가
    // 정확히 "호출을 한 군데도 안 넣었다" 였다. 11개 호출처 중 하나를 빠뜨리면
    // 그 경로로 바꾼 값만 친구에게 영원히 안 보이는, 찾기 어려운 버그가 된다.
    // 저장하면 올라간다 — 빠뜨릴 수가 없는 자리에 둔다. 같은 주는 덮어쓰므로 멱등이다.
    if (!publishing) {
      publishing = true;
      try { publishWeekly(); } catch (e) {} finally { publishing = false; }
    }
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
  /**
   * 특정 끼니를 통째로 복사한다.
   * 이 앱의 재조정 루프는 기록된 칼로리를 읽지 않고 실측 체중만 본다.
   * 그래서 중요한 건 절대 정확도가 아니라 **편향이 흔들리지 않는 것**이다.
   * 같은 음식을 같은 추정치로 재사용하면 주마다 편향이 흔들리지 않는다 —
   * 모델을 키우는 것보다 이 한 탭이 루프에 훨씬 이롭다.
   */
  function lastMealLike(meal, beforeDate) {
    var before = beforeDate || dayKey();
    var logs = (state.foodLogs || [])
      .filter(function (x) { return x.meal === meal && x.date < before && (x.items || []).length; })
      .sort(function (a, b) { return a.date < b.date ? 1 : -1; });
    return logs[0] || null;
  }
  function copyMeal(sourceLog, toDate, meal) {
    if (!sourceLog) return null;
    return addFoodLog({
      date: toDate || dayKey(),
      meal: meal || sourceLog.meal,
      items: JSON.parse(JSON.stringify(sourceLog.items || [])),
      source: 'repeat'
    });
  }
  /** 어제 먹은 것 전부 */
  function yesterdayLogs(fromDate) {
    var d = new Date((fromDate || dayKey()) + 'T00:00:00');
    d.setDate(d.getDate() - 1);
    return logsForDate(dayKey(d));
  }

  function toggleFavorite(name) {
    state.foodFavorites = state.foodFavorites || [];
    var i = state.foodFavorites.indexOf(name);
    if (i >= 0) state.foodFavorites.splice(i, 1); else state.foodFavorites.push(name);
    save();
    return state.foodFavorites.indexOf(name) >= 0;
  }
  function isFavorite(name) { return (state.foodFavorites || []).indexOf(name) >= 0; }

  /* ------------------------------------------------------------------ */
  /* 주간 스냅샷 — 친구에게 나가는 값                                      */
  /*                                                                      */
  /* 이게 없어서 친구 기능의 절반이 존재하지 않았다. publishSnapshot 을    */
  /* 앱에서 아무도 부르지 않아서, 친구가 공유 항목을 전부 켜도 상대 화면은 */
  /* 영원히 "아직 공유한 게 없습니다" 였다. 공유 토글의 반대편이 없었다.  */
  /* ------------------------------------------------------------------ */

  /** 그 날짜가 속한 주의 월요일 (ISO 문자열) */
  function weekStartOf(date) {
    var d = date ? new Date(date) : new Date();
    d.setHours(0, 0, 0, 0);
    var dow = (d.getDay() + 6) % 7;          // 월=0
    d.setDate(d.getDate() - dow);
    return d.getFullYear() + '-' +
           String(d.getMonth() + 1).padStart(2, '0') + '-' +
           String(d.getDate()).padStart(2, '0');
  }

  /**
   * 이번 주에 친구에게 나갈 수 있는 값 전부를 담은 꾸러미.
   * 무엇이 실제로 나가는지는 읽는 쪽에서 친구별 공유 설정으로 거른다.
   * 여기서 거르지 않는 이유: 한 사람이 친구마다 다른 항목을 공유하기 때문이다.
   */
  function weeklySnapshot() {
    var E = global.MB_ENGINE;
    var prof = state.profile || (global.MB_DATA && global.MB_DATA.SEED_PROFILE);
    var scans = sortedScans();
    var out = { dWeightKg: null, dSmmKg: null, dBfmKg: null,
                progressPct: null, checkedIn: false };
    if (!E || !prof) return out;

    // 변화량은 직전 측정 대비. 측정이 한 번뿐이면 변화량은 "없음"이지 0 이 아니다.
    if (scans.length >= 2) {
      var a = E.derive(scans[scans.length - 2], prof);
      var b = E.derive(scans[scans.length - 1], prof);
      out.dWeightKg = Math.round((b.weightKg - a.weightKg) * 10) / 10;
      out.dSmmKg = Math.round((b.smmKg - a.smmKg) * 100) / 100;
      out.dBfmKg = Math.round((b.bfmKg - a.bfmKg) * 100) / 100;
    }
    if (scans.length) {
      var last = E.derive(scans[scans.length - 1], prof);
      out.weightKg = last.weightKg; out.smmKg = last.smmKg;
      out.bfmKg = last.bfmKg; out.pbfPct = last.pbfPct;
    }
    if (state.plan && state.goal && scans.length && state.plan.trajectory) {
      var cur = E.derive(scans[scans.length - 1], prof);
      var s0 = state.plan.trajectory[0].bfmKg, t0 = state.goal.bfmKg;
      if (Math.abs(s0 - t0) > 0.01) {
        out.progressPct = Math.max(0, Math.min(100,
          Math.round((s0 - cur.bfmKg) / (s0 - t0) * 100)));
      }
    }
    // "이번 주에 기록했는가". 예전엔 "한 번이라도 기록했는가" 였는데
    // 화면은 "이번 주 기록"이라고 적고 있었다 — 서로 다른 말이다.
    var wk = weekStartOf();
    out.checkedIn = (state.checkins || []).some(function (c) {
      return weekStartOf(c.at) === wk;
    });
    return out;
  }

  /**
   * 이번 주 스냅샷을 백엔드에 올린다. 로그인 안 했으면 조용히 아무것도 안 한다.
   * 측정·체크인·목표 변경처럼 친구가 볼 값이 바뀌는 자리에서 부른다.
   */
  function publishWeekly() {
    var B = global.MB_BACKEND;
    if (!B || !B.currentUser || !B.currentUser()) return { ok: false, reason: '로그인 안 함' };
    try {
      return B.publishSnapshot(weekStartOf(), weeklySnapshot());
    } catch (e) {
      return { ok: false, reason: String(e && e.message || e) };
    }
  }

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
    lastMealLike: lastMealLike, copyMeal: copyMeal, yesterdayLogs: yesterdayLogs,
    toggleFavorite: toggleFavorite, isFavorite: isFavorite,
    weekStartOf: weekStartOf, weeklySnapshot: weeklySnapshot, publishWeekly: publishWeekly,
    exportJSON: exportJSON, importJSON: importJSON, blank: blank
  };
})(window);
