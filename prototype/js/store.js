/* =============================================================================
 * store.js — localStorage 상태 저장소
 *
 * 계산도 저장도 전부 여기서 일어난다. 서버는 있지만 이 파일은 서버를 모른다 —
 * save() 가 publishWeekly() 를 부르고, 그게 backend/sync 로 넘어간다.
 *
 * 무엇이 기기 밖으로 나가는가 (2026-09 기준):
 *   나감    친구에게 보일 주간 요약 — 최근 체중 · 골격근 · 체지방 · 체지방률과
 *           그 변화량. 로그인했을 때만. 친구가 실제로 볼 수 있는 것은 그 친구에게
 *           켜 둔 항목뿐이지만, 값 자체는 서버에 올라가 있다.
 *   안 나감 측정 기록 · 프로필 · 목표 · 계획 · 체크인 · 식단 기록.
 *           그래서 기기를 바꾸면 따라오지 않는다. 백업은 exportJSON() 뿐이다.
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
      schedule: {},
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

  /* 저장이 실패할 수 있습니다. 그리고 실패를 삼키면 안 됩니다.
   *
   * localStorage 는 보통 5MB 가 한도인데, 결과지 사진이 같은 칸을 씁니다.
   * 꽉 차면 setItem 이 QuotaExceededError 를 던지고, 예전에는 그걸
   * 조용히 먹었습니다. 사용자는 "저장했습니다" 토스트를 보고, 새로고침
   * 하면 그 측정이 없습니다. 앱이 틀렸다고 생각하기 전에 자기 기억을
   * 의심하게 되는 종류의 버그입니다.
   *
   * 이제 두 가지를 합니다.
   *   (가) 공간이 모자라면 사진부터 버리고 다시 시도합니다 — 숫자가
   *        사진보다 중요합니다. 사진은 다시 찍을 수 있지만 지나간
   *        측정일의 숫자는 되찾을 수 없습니다.
   *   (나) 그래도 안 되면 false 를 돌려줍니다. 부르는 쪽이 사실대로
   *        말할 수 있게.
   */
  var lastSaveOk = true;

  function writeState() {
    try { localStorage.setItem(KEY, JSON.stringify(state)); return true; }
    catch (e) {
      // 사진을 버려서 자리를 만들어 봅니다 (오래된 것부터)
      try {
        var P = global.MB_PHOTO;
        if (P) {
          var map = P.list();
          var ids = Object.keys(map).sort(function (a, b) {
            return (map[a].at || '') < (map[b].at || '') ? -1 : 1;
          });
          while (ids.length) {
            P.remove(ids.shift());
            try { localStorage.setItem(KEY, JSON.stringify(state)); return true; }
            catch (e2) { /* 계속 버립니다 */ }
          }
        }
      } catch (e3) {}
      return false;
    }
  }

  function save() {
    lastSaveOk = writeState();
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
    return lastSaveOk;
  }

  /** 마지막 저장이 실제로 기기에 쓰였는가 */
  function saved() { return lastSaveOk; }

  function get() { return state; }
  function set(patch) { Object.assign(state, patch); save(); return state; }
  function onChange(fn) { listeners.push(fn); }

  function reset() {
    /* "모든 데이터를 지울까요?" 에 사진이 안 들어 있었습니다.
       측정 · 목표 · 플랜은 지워지는데 결과지 사진은 기기에 남았습니다.
       사진에는 보통 이름 · 나이 · 성별이 같이 인쇄돼 있습니다 — 전부
       지웠다고 믿고 폰을 넘긴 사람에게는 그게 전부입니다. */
    if (global.MB_PHOTO) { try { global.MB_PHOTO.clearAll(); } catch (e) {} }
    state = blank();
    save();
  }

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
    /* 딸린 사진도 같이 지웁니다.
       예전에는 측정만 지우고 사진을 두고 왔습니다. 사용자는 "이 측정을
       지웠다" 고 생각하는데 결과지 사진은 기기에 남아 있었고, 어디서도
       보이지 않으니 지울 방법도 없었습니다. 사진 칸(최근 6장)만 계속
       차지했고요. 다른 측정이 같은 사진을 가리키고 있으면 남겨 둡니다. */
    var gone = state.scans.filter(function (s) { return s.id === id; })[0];
    state.scans = state.scans.filter(function (s) { return s.id !== id; });
    if (gone && gone.photoId && global.MB_PHOTO) {
      var stillUsed = state.scans.some(function (s) { return s.photoId === gone.photoId; });
      if (!stillUsed) { try { global.MB_PHOTO.remove(gone.photoId); } catch (e) {} }
    }
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

  /* --- 주간 운동 일정 --------------------------------------------------
   * "월요일에 헬스" 같은 약속을 요일이 아니라 **날짜**로 저장합니다.
   *
   * 요일 인덱스(월=0)로 저장하면 주가 넘어가는 순간 지난주 체크가
   * 이번주 칸에 그대로 남습니다. 월요일에 갔다고 체크한 게 다음주
   * 월요일에도 체크돼 있으면, 스트릭은 영원히 안 끊기고 화면은
   * 거짓말을 합니다. 날짜로 저장하면 그 일이 생길 수 없고, 덤으로
   * 지난 기록이 그대로 남아 스트릭을 계산할 수 있습니다.
   *
   * 한 날의 모양: { plan: ['gym'], done: { gym: '2026-09-20T19:02:00Z' } }
   *   plan  그 날 하기로 한 것
   *   done  실제로 했다고 체크한 것과 체크한 시각
   * 둘 다 비면 그 날 칸을 지웁니다 — 안 그러면 넘긴 날마다 빈 객체가
   * 쌓여서 백업 파일이 계속 커집니다.
   * ------------------------------------------------------------------ */
  var SCHED_TYPES = ['gym', 'cardio'];

  function scheduleDay(date) {
    state.schedule = state.schedule || {};
    var e = state.schedule[dayKey(date)];
    return {
      plan: (e && e.plan || []).slice(),
      done: Object.assign({}, e && e.done)
    };
  }

  function writeDay(k, e) {
    state.schedule = state.schedule || {};
    if (!(e.plan || []).length && !Object.keys(e.done || {}).length) delete state.schedule[k];
    else state.schedule[k] = { plan: e.plan, done: e.done };
    save();
  }

  /** 그 날 그 운동을 하기로 한다 / 안 하기로 한다 */
  function setSchedulePlan(date, type, on) {
    if (SCHED_TYPES.indexOf(type) < 0) return null;
    var k = dayKey(date), e = scheduleDay(k);
    var i = e.plan.indexOf(type);
    if (on && i < 0) e.plan.push(type);
    if (!on && i >= 0) {
      e.plan.splice(i, 1);
      /* 계획을 지우면 그 날의 체크도 같이 지웁니다.
         "안 하기로 한 운동을 했다"는 상태는 화면에 그릴 자리가 없고,
         다시 계획을 켰을 때 예전 체크가 살아나면 안 갔는데 간 것이 됩니다. */
      delete e.done[type];
    }
    writeDay(k, e);
    return scheduleDay(k);
  }

  /** 그 날 그 운동을 했다고 체크한다 / 체크를 푼다
   *  아직 오지 않은 날은 체크할 수 없습니다 — 내일 갈 헬스를 오늘 체크하는 건
   *  기록이 아니라 소원입니다. 대신 지나간 날은 나중에라도 체크할 수 있게
   *  둡니다. 갔는데 누르는 걸 잊은 쪽이 훨씬 흔하고, 그걸 막으면 앱이
   *  사실보다 나쁜 기록을 들고 있게 됩니다. 언제 눌렀는지는 남겨 둡니다. */
  function setScheduleDone(date, type, on) {
    if (SCHED_TYPES.indexOf(type) < 0) return null;
    var k = dayKey(date);
    if (k > dayKey()) return scheduleDay(k);
    var e = scheduleDay(k);
    if (on) {
      if (e.plan.indexOf(type) < 0) e.plan.push(type);   // 계획에 없이 한 것도 기록은 남긴다
      e.done[type] = new Date().toISOString();
    } else {
      delete e.done[type];
    }
    writeDay(k, e);
    return scheduleDay(k);
  }

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

    /* 이번 주 운동 일정 — 숫자 네 개.
       엔진도 프로필도 없어도 셀 수 있는 값이라 위의 early return 보다
       먼저 넣습니다. 인바디를 한 번도 안 올린 사람도 운동 일정은
       쓸 수 있고, 그 사람의 친구는 그걸 볼 수 있어야 합니다. */
    var W = global.MB_SCHED;
    if (W) {
      var sum = W.weekSummary(weekStartOf());
      if (sum.plannedDays > 0) {
        out.plannedDays = sum.plannedDays;
        out.keptDays = sum.keptDays;
        out.missedDays = sum.missedDays;
        out.openDays = sum.openDays;
      }
      /* 계획이 0일이면 키를 아예 안 넣습니다. 0 을 보내면 친구 화면에
         "계획 0일 · 지킴 0일" 이 뜨고, 그건 "안 했다" 로 읽힙니다.
         실제로는 앱에 안 적었다는 뜻일 뿐입니다 — 다른 말입니다. */
    }

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
  /** 스냅샷에 친구에게 보여 줄 것이 하나라도 들어 있는가 */
  function hasAnything(snap) {
    if (!snap) return false;
    if (snap.checkedIn) return true;
    if (snap.plannedDays != null) return true;
    var KEYS = ['dWeightKg', 'dSmmKg', 'dBfmKg', 'progressPct',
                'weightKg', 'smmKg', 'bfmKg', 'pbfPct'];
    for (var i = 0; i < KEYS.length; i++) if (snap[KEYS[i]] != null) return true;
    return false;
  }

  function publishWeekly() {
    var B = global.MB_BACKEND;
    if (!B || !B.currentUser || !B.currentUser()) return { ok: false, reason: '로그인 안 함' };
    /* 빈 스냅샷은 안 올립니다.
     *
     * 빈 스냅샷은 서버에 아무 가치가 없는데, 서버는 같은 주를 덮어씁니다.
     * 그래서 앱을 지웠다 다시 깔고 로그인하면 — 온보딩의 첫 저장이
     * publishWeekly() 를 부르고, 빈 값이 서버에 멀쩡히 남아 있던 이번 주
     * 기록을 덮어썼습니다. 친구 화면에서 그 사람의 이번 주 점이 그 자리에서
     * 꺼집니다. 기기를 정리한 것이 남의 화면에서 내 기록을 지우는 일이
     * 되면 안 됩니다.
     *
     * 예전엔 이 검사가 "측정이 0건인가" 였습니다. 그런데 이제 인바디가
     * 없어도 올릴 것이 있습니다 — 운동 일정과 체크인은 몸이 아니라
     * 행동이고, 인바디를 한 번도 안 올린 사람도 그건 씁니다. 측정으로
     * 판정하면 그 사람의 친구 화면은 영원히 비어 있습니다.
     * 그래서 "이 꾸러미에 들어 있는 게 있는가" 로 봅니다. 원래 막으려던
     * 것(정말 빈 값이 남의 기록을 덮어쓰는 것)은 그대로 막힙니다. */
    var snap = weeklySnapshot();
    if (!hasAnything(snap)) return { ok: false, reason: '올릴 것 없음' };
    try {
      return B.publishSnapshot(weekStartOf(), snap);
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
    load: load, save: save, saved: saved, get: get, set: set, reset: reset, seed: seed,
    onChange: onChange, latestScan: latestScan, sortedScans: sortedScans,
    addScan: addScan, removeScan: removeScan, scanById: scanById,
    setGoal: setGoal, setPlan: setPlan, planMatchesGoal: planMatchesGoal, sameGoal: sameGoal,
    dayKey: dayKey, addFoodLog: addFoodLog, removeFoodLog: removeFoodLog,
    logsForDate: logsForDate, dayTotals: dayTotals, sumItems: sumItems,
    loggedDates: loggedDates, recentFoods: recentFoods,
    lastMealLike: lastMealLike, copyMeal: copyMeal, yesterdayLogs: yesterdayLogs,
    toggleFavorite: toggleFavorite, isFavorite: isFavorite,
    SCHED_TYPES: SCHED_TYPES, scheduleDay: scheduleDay,
    setSchedulePlan: setSchedulePlan, setScheduleDone: setScheduleDone,
    weekStartOf: weekStartOf, weeklySnapshot: weeklySnapshot, publishWeekly: publishWeekly,
    exportJSON: exportJSON, importJSON: importJSON, blank: blank
  };
})(window);
