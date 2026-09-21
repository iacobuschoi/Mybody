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

    var out = { days: 0, openToday: false, lastKept: null, missedAt: null,
                everPlanned: days.length > 0, staleDays: null, stale: false };
    /* 쉬는 날은 안 끊지만, 몇 주씩 비어 있는 것은 쉬는 날이 아닙니다.
     *
     * 계획한 날만 세기 때문에, 8월에 사흘 지키고 9월에 이틀 지킨 사람은
     * 그 사이에 끊길 날이 없었습니다 — 아무 날도 안 정했으니까요.
     * 그래서 "5일 연속" 이 됐습니다. 38일 쉬고 돌아온 사람에게 그건
     * 연속이 아니라 서로 다른 두 시기입니다. 규칙은 사람이 쉬는 리듬을
     * 벌주지 않으려고 만든 것이지, 없던 연속을 만들어 주려는 게 아닙니다.
     *
     * 지킨 날 사이가 14일을 넘으면 거기서 끊습니다 — 신선도와 같은
     * 경계입니다. "이번 주도 지난주도 아니면 다른 시기" 하나로 설명됩니다. */
    var GAP_DAYS = 14;
    function gap(a, b) {
      return Math.round((new Date(a + 'T00:00:00') - new Date(b + 'T00:00:00')) / 86400000);
    }
    var prevKept = null;
    for (var i = 0; i < days.length; i++) {
      var k = days[i], e = sch[k];
      var kept = isKept({ plan: e.plan || [], done: e.done || {} });
      if (k === today && !kept) { out.openToday = true; continue; }
      if (!kept) { out.missedAt = k; break; }
      if (prevKept && gap(prevKept, k) > GAP_DAYS) break;   // 너무 오래 비었다
      out.days++;
      prevKept = k;
      if (!out.lastKept) out.lastKept = k;
    }

    /* 얼마나 오래된 기록인가.
     *
     * 이 셈은 **계획한 날만** 봅니다. 그래서 8월에 사흘 지키고 그 뒤로
     * 아무 날도 안 정한 사람은, 9월에도 끊긴 날이 없습니다 — 끊길 날이
     * 없었으니까요. 화면은 그걸 "3일 연속" 이라고 그렸습니다. 40일 전
     * 얘기인데 현재형입니다.
     *
     * 숫자를 0으로 지우지는 않습니다. 지우면 "네 기록은 없다" 가 되고,
     * 그건 사실이 아닙니다. 대신 며칠 지났는지를 같이 돌려주고, 화면이
     * 과거형으로 말합니다 — "있었고 지금은 안 세는 중" 이 사실입니다.
     *
     * 경계는 14일입니다. 이번 주도 지난주도 아니면 지난 기록으로 봅니다.
     * 이 앱의 리듬이 주 단위라 설명할 수 있는 숫자여야 했습니다. */
    if (out.lastKept) {
      var a = new Date(out.lastKept + 'T00:00:00');
      var b = new Date(today + 'T00:00:00');
      out.staleDays = Math.round((b - a) / 86400000);
      out.stale = out.staleDays > 14;
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

    var out = { days: 0, openToday: false, last7: 0 };
    var cursor = today;
    if (!has[today]) { out.openToday = true; cursor = shiftKey(today, -1); }
    for (var g = 0; g < 400 && has[cursor]; g++) {
      out.days++;
      cursor = shiftKey(cursor, -1);
    }
    /* 연속이 끊긴 날에도 최근 7일 중 며칠 적었는지는 남습니다.
       어제 하루 빼먹어 연속이 0이어도 7일 중 5일이면 잘 하고 있는
       겁니다. 연속 하나만 보여 주면 그 사람은 앱을 닫습니다. */
    for (var d2 = 0; d2 < 7; d2++) if (has[shiftKey(today, -d2)]) out.last7++;
    return out;
  }

  global.MB_SCHED = {
    TYPES: TYPES, DOW: DOW, typeOf: typeOf, labelOf: labelOf, indexOf: indexOf,
    shiftKey: shiftKey, isKept: isKept,
    week: week, weekSummary: weekSummary,
    workoutStreak: workoutStreak, foodStreak: foodStreak
  };
})(window);
