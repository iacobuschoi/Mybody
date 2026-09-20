/* =============================================================================
 * schedule.js — 이번 주 운동 일정과 스트릭 (읽기 전용 계산)
 *
 * 저장은 store.js 가 합니다. 여기는 저장된 날짜별 기록을 화면이 쓸 모양으로
 * 바꾸는 일만 합니다 — 이번 주 일곱 칸, 그리고 스트릭.
 *
 * 스트릭을 이 앱에 넣어도 되는 이유:
 *   이 앱에는 "측정 오차보다 작은 변화를 달성/미달성으로 채점하지 않는다"는
 *   규칙이 있습니다. 체중 -0.3kg 은 저울의 떨림일 수 있고, 그걸 성공이라
 *   부르면 미신을, 실패라 부르면 무력감을 만듭니다.
 *   그런데 "헬스장에 갔다/안 갔다"에는 오차가 없습니다. 본인이 직접 누른
 *   사실이고 소수점이 없습니다. 몸무게로 스트릭을 만드는 건 거짓이지만
 *   행동으로 만드는 건 거짓이 아닙니다. 그래서 스트릭은 **행동에만**
 *   답니다 — 체중·골격근·체지방에는 절대 달지 않습니다.
 *
 * 스트릭이 사람을 해치지 않게 하는 두 가지 규칙:
 *   (가) 쉬는 날은 스트릭을 끊지 않습니다. 계획한 날만 셉니다.
 *        주 3회 계획한 사람에게 매일 스트릭을 들이대면, 계획대로
 *        지키고도 나흘마다 0 이 됩니다.
 *   (나) 오늘은 하루가 끝나기 전엔 실패가 아닙니다. 오전 9시에
 *        "스트릭이 끊겼습니다"라고 말하는 앱은 틀린 말을 하는 겁니다.
 * ========================================================================== */
(function (global) {
  'use strict';

  var TYPES = [
    { id: 'gym',    label: '헬스',   short: '헬', icon: '🏋️' },
    { id: 'cardio', label: '유산소', short: '유', icon: '🏃' }
  ];
  var DOW = ['월', '화', '수', '목', '금', '토', '일'];

  function S() { return global.MB_STORE; }
  function typeOf(id) {
    for (var i = 0; i < TYPES.length; i++) if (TYPES[i].id === id) return TYPES[i];
    return null;
  }
  function labelOf(id) { var t = typeOf(id); return t ? t.label : id; }
  /* 고유번호의 #뒤 숫자로 씁니다. 화면에 몇 번째로 그려졌느냐가 아니라
     종목의 고유 순서라, 오늘 유산소만 남아도 유산소는 언제나 #2 입니다 —
     그 번호에 달아 둔 피드백 메모가 다른 버튼으로 옮겨가지 않습니다. */
  function indexOf(id) {
    for (var i = 0; i < TYPES.length; i++) if (TYPES[i].id === id) return i;
    return -1;
  }

  /** 'YYYY-MM-DD' 에 n일 더한 키 */
  function shiftKey(key, n) {
    var d = new Date(key + 'T00:00:00');
    d.setDate(d.getDate() + n);
    return S().dayKey(d);
  }

  /** 계획한 것을 전부 했는가. 계획이 없는 날은 "지킬 것이 없던 날"이지 지킨 날이 아니다. */
  function isKept(e) {
    if (!e || !(e.plan || []).length) return false;
    for (var i = 0; i < e.plan.length; i++) if (!e.done[e.plan[i]]) return false;
    return true;
  }

  /**
   * 이번 주(월~일) 일곱 칸.
   * weekStart 를 안 주면 오늘이 속한 주.
   */
  function week(weekStart) {
    var ST = S();
    var start = weekStart || ST.weekStartOf();
    var today = ST.dayKey();
    var out = [];
    for (var i = 0; i < 7; i++) {
      var k = shiftKey(start, i);
      var e = ST.scheduleDay(k);
      var doneList = e.plan.filter(function (t) { return !!e.done[t]; });
      out.push({
        key: k,
        dow: DOW[i],
        dayNum: Number(k.slice(8, 10)),
        isToday: k === today,
        isPast: k < today,
        isFuture: k > today,
        plan: e.plan,
        done: e.done,
        doneList: doneList,
        kept: isKept(e),
        /* 지난 날 중 계획은 있었는데 다 못 한 날. 오늘과 앞날은 여기 안 들어옵니다. */
        missed: k < today && e.plan.length > 0 && !isKept(e)
      });
    }
    return { start: start, days: out };
  }

  /** 그 주의 한 줄 요약 */
  function weekSummary(weekStart) {
    var w = week(weekStart);
    var planned = 0, kept = 0, missed = 0, open = 0;
    w.days.forEach(function (d) {
      if (!d.plan.length) return;
      planned++;
      if (d.kept) kept++;
      else if (d.missed) missed++;
      else open++;                       // 오늘이거나 아직 안 온 날
    });
    return { start: w.start, plannedDays: planned, keptDays: kept,
             missedDays: missed, openDays: open, days: w.days };
  }

  /**
   * 운동 스트릭 — 계획한 날을 연달아 몇 번 지켰는가.
   * 쉬는 날은 건너뜁니다. 오늘이 아직 안 끝났으면 끊지 않고 open 으로 둡니다.
   */
  function workoutStreak(todayKey) {
    var ST = S();
    var today = todayKey || ST.dayKey();
    var sch = ST.get().schedule || {};
    var days = Object.keys(sch).filter(function (k) {
      return k <= today && (sch[k].plan || []).length;
    }).sort().reverse();

    var out = { days: 0, openToday: false, lastKept: null, missedAt: null, everPlanned: days.length > 0 };
    for (var i = 0; i < days.length; i++) {
      var k = days[i], e = sch[k];
      var kept = isKept({ plan: e.plan || [], done: e.done || {} });
      if (k === today && !kept) { out.openToday = true; continue; }
      if (!kept) { out.missedAt = k; break; }
      out.days++;
      if (!out.lastKept) out.lastKept = k;
    }
    return out;
  }

  /**
   * 식단 기록 스트릭 — 연달아 며칠 기록했는가.
   * 이름을 "식단 지킴"이 아니라 "식단 기록"이라 부르는 건 이게 재는 것이
   * 적게 먹었는지가 아니라 적었는지이기 때문입니다. 앱은 전자를 모릅니다.
   */
  function foodStreak(todayKey) {
    var ST = S();
    var today = todayKey || ST.dayKey();
    var has = {};
    (ST.get().foodLogs || []).forEach(function (x) { has[x.date] = true; });

    var out = { days: 0, openToday: false };
    var cursor = today;
    if (!has[today]) { out.openToday = true; cursor = shiftKey(today, -1); }
    for (var g = 0; g < 400 && has[cursor]; g++) {
      out.days++;
      cursor = shiftKey(cursor, -1);
    }
    return out;
  }

  global.MB_SCHED = {
    TYPES: TYPES, DOW: DOW, typeOf: typeOf, labelOf: labelOf, indexOf: indexOf,
    shiftKey: shiftKey, isKept: isKept,
    week: week, weekSummary: weekSummary,
    workoutStreak: workoutStreak, foodStreak: foodStreak
  };
})(window);
