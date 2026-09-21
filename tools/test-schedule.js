/* =============================================================================
 * tools/test-schedule.js — 주간 운동 일정과 스트릭 시험
 *
 *   node tools/test-schedule.js
 *
 * 스트릭은 틀리면 조용히 거짓말하는 종류의 기능입니다. 화면에 "12일째"
 * 라고 떠 있으면 아무도 그걸 검산하지 않습니다. 그래서 여기서 셉니다.
 *
 * 특히 이 세 가지가 이 앱의 약속입니다.
 *   (가) 쉬는 날은 스트릭을 끊지 않는다   — 계획한 날만 센다
 *   (나) 오늘은 하루가 끝나기 전엔 실패가 아니다
 *   (다) 주가 넘어가면 지난주 체크가 이번주 칸에 남지 않는다
 * ========================================================================== */
global.window = global;

/* localStorage 흉내. 실제 저장 동작(용량 초과 시 사진 버리기 등)은
   여기서 시험하지 않습니다 — 그건 test-dataloss 가 봅니다. */
let mem = {};
global.localStorage = {
  getItem: k => (k in mem ? mem[k] : null),
  setItem: (k, v) => { mem[k] = String(v); },
  removeItem: k => { delete mem[k]; }
};

require('../prototype/js/store.js');
require('../prototype/js/schedule.js');
const S = window.MB_STORE, W = window.MB_SCHED;

let pass = 0, fail = 0;
function t(name, cond, extra) {
  if (cond) { pass++; console.log('  ✓ ' + name); }
  else { fail++; console.log('  ✗ ' + name + (extra ? '\n      ' + extra : '')); }
}
function reset() { mem = {}; S.load(); S.set({ schedule: {}, foodLogs: [] }); }

/* 오늘을 고정합니다. new Date() 를 그대로 쓰면 자정을 넘기는 순간
   결과가 달라지는 시험이 됩니다 — 밤 11시 59분에만 빨간 CI 는
   찾기 제일 어려운 종류입니다. */
const TODAY = '2026-09-20';           // 일요일
function d(n) { return W.shiftKey(TODAY, n); }

console.log('\n[1] 하루 정하고 체크하기');
reset();
S.setSchedulePlan(d(0), 'gym', true);
t('계획이 들어간다', S.scheduleDay(d(0)).plan.join() === 'gym');
S.setSchedulePlan(d(0), 'cardio', true);
t('두 개도 들어간다', S.scheduleDay(d(0)).plan.sort().join() === 'cardio,gym');
S.setScheduleDone(d(0), 'gym', true);
t('체크가 들어간다', !!S.scheduleDay(d(0)).done.gym);
t('체크에 시각이 남는다', /^\d{4}-\d{2}-\d{2}T/.test(S.scheduleDay(d(0)).done.gym));
S.setSchedulePlan(d(0), 'gym', false);
t('계획을 지우면 그 체크도 사라진다', !S.scheduleDay(d(0)).done.gym,
  JSON.stringify(S.scheduleDay(d(0))));
S.setSchedulePlan(d(0), 'cardio', false);
t('둘 다 비면 그 날 칸 자체를 지운다', !(S.get().schedule || {})[d(0)],
  JSON.stringify(S.get().schedule));
t('모르는 종목은 안 받는다', S.setSchedulePlan(d(0), 'yoga', true) === null);

console.log('\n[2] 아직 오지 않은 날은 체크할 수 없다');
reset();
const future = W.shiftKey(S.dayKey(), 3);
S.setSchedulePlan(future, 'gym', true);
S.setScheduleDone(future, 'gym', true);
t('내일 갈 헬스를 오늘 체크할 수 없다', !S.scheduleDay(future).done.gym);
const past = W.shiftKey(S.dayKey(), -3);
S.setSchedulePlan(past, 'gym', true);
S.setScheduleDone(past, 'gym', true);
t('지나간 날은 나중에라도 체크할 수 있다', !!S.scheduleDay(past).done.gym);

console.log('\n[3] 스트릭 — 쉬는 날은 끊지 않는다');
reset();
/* 월·수·금만 계획하고 전부 지킨 사람. 화·목은 쉬는 날입니다. */
[-6, -4, -2].forEach(n => {
  S.setSchedulePlan(d(n), 'gym', true);
  S.setScheduleDone(d(n), 'gym', true);
});
let st = W.workoutStreak(TODAY);
t('주 3회를 다 지키면 3일째', st.days === 3, JSON.stringify(st));
t('쉬는 날이 끼어도 안 끊긴다', st.missedAt === null);

console.log('\n[4] 스트릭 — 오늘은 하루가 끝나기 전엔 실패가 아니다');
reset();
[-2, -1].forEach(n => {
  S.setSchedulePlan(d(n), 'gym', true);
  S.setScheduleDone(d(n), 'gym', true);
});
S.setSchedulePlan(TODAY, 'gym', true);          // 오늘은 아직 안 갔다
st = W.workoutStreak(TODAY);
t('오늘 안 갔어도 어제까지의 2일이 살아 있다', st.days === 2, JSON.stringify(st));
t('오늘은 "남음"으로 표시된다', st.openToday === true);
S.setScheduleDone(TODAY, 'gym', true);
st = W.workoutStreak(TODAY);
t('오늘 체크하면 3일째', st.days === 3);
t('더 이상 남지 않았다', st.openToday === false);

console.log('\n[5] 스트릭 — 지나간 날을 빼먹으면 거기서 끊긴다');
reset();
[-4, -3].forEach(n => {
  S.setSchedulePlan(d(n), 'gym', true);
  S.setScheduleDone(d(n), 'gym', true);
});
S.setSchedulePlan(d(-2), 'gym', true);          // 안 갔다
S.setSchedulePlan(d(-1), 'gym', true);
S.setScheduleDone(d(-1), 'gym', true);
st = W.workoutStreak(TODAY);
t('끊긴 뒤부터 다시 센다 (1일째)', st.days === 1, JSON.stringify(st));
t('어디서 끊겼는지 안다', st.missedAt === d(-2));

console.log('\n[6] 계획 중 하나만 하면 그 날은 지킨 날이 아니다');
reset();
S.setSchedulePlan(d(-1), 'gym', true);
S.setSchedulePlan(d(-1), 'cardio', true);
S.setScheduleDone(d(-1), 'gym', true);
st = W.workoutStreak(TODAY);
t('둘 중 하나만 했으면 안 쳐준다', st.days === 0, JSON.stringify(st));
S.setScheduleDone(d(-1), 'cardio', true);
t('나머지도 하면 쳐준다', W.workoutStreak(TODAY).days === 1);

console.log('\n[7] 계획이 하나도 없으면 스트릭은 0 이고 그건 실패가 아니다');
reset();
st = W.workoutStreak(TODAY);
t('0일째', st.days === 0);
t('끊긴 자리가 없다', st.missedAt === null);
t('정한 적이 없다고 말할 수 있다', st.everPlanned === false);

console.log('\n[7-2] 오래된 기록을 현재형으로 말하지 않는다');
reset();
['2026-08-10', '2026-08-11', '2026-08-12'].forEach(k => {
  S.setSchedulePlan(k, 'gym', true); S.setScheduleDone(k, 'gym', true);
});
st = W.workoutStreak(TODAY);                    // TODAY = 2026-09-20
t('숫자는 지우지 않는다', st.days === 3, JSON.stringify(st));
t('며칠 지났는지 안다', st.staleDays === 39, st.staleDays);
t('오래된 기록이라고 표시한다', st.stale === true);
t('마지막으로 지킨 날을 안다', st.lastKept === '2026-08-12');

console.log('\n[7-3] 몇 주씩 비어 있는 것은 쉬는 날이 아니다');
/* 계획한 날만 세기 때문에, 그 사이에 끊길 날이 없어서 "5일 연속" 이
   됐습니다. 38일 쉬고 돌아온 사람에게 그건 서로 다른 두 시기입니다. */
['2026-09-19', '2026-09-20'].forEach(k => {
  S.setSchedulePlan(k, 'gym', true); S.setScheduleDone(k, 'gym', true);
});
st = W.workoutStreak(TODAY);
t('돌아온 뒤부터 다시 센다 (2일)', st.days === 2, JSON.stringify(st));
t('더 이상 오래된 기록이 아니다', st.stale === false);
/* 경계 확인: 14일 이내면 이어집니다 */
reset();
S.setSchedulePlan('2026-09-07', 'gym', true); S.setScheduleDone('2026-09-07', 'gym', true);
S.setSchedulePlan('2026-09-20', 'gym', true); S.setScheduleDone('2026-09-20', 'gym', true);
t('13일 떨어져 있으면 이어진다', W.workoutStreak(TODAY).days === 2,
  JSON.stringify(W.workoutStreak(TODAY)));
reset();
S.setSchedulePlan('2026-09-05', 'gym', true); S.setScheduleDone('2026-09-05', 'gym', true);
S.setSchedulePlan('2026-09-20', 'gym', true); S.setScheduleDone('2026-09-20', 'gym', true);
t('15일 떨어져 있으면 끊긴다', W.workoutStreak(TODAY).days === 1,
  JSON.stringify(W.workoutStreak(TODAY)));

console.log('\n[8] 이번 주 일곱 칸');
reset();
const wk = W.week('2026-09-14');                 // 월요일
t('일곱 칸', wk.days.length === 7);
t('첫 칸이 월요일', wk.days[0].dow === '월' && wk.days[0].key === '2026-09-14');
t('마지막 칸이 일요일', wk.days[6].dow === '일' && wk.days[6].key === '2026-09-20');
t('날짜 숫자가 맞다', wk.days[0].dayNum === 14 && wk.days[6].dayNum === 20);

console.log('\n[9] 주가 넘어가도 지난주 체크가 따라오지 않는다');
reset();
S.setSchedulePlan('2026-09-14', 'gym', true);    // 지난주 월요일
S.setScheduleDone('2026-09-14', 'gym', true);
const thisWeek = W.week('2026-09-21');           // 다음주 월요일
t('다음주 월요일 칸은 비어 있다', thisWeek.days[0].plan.length === 0,
  JSON.stringify(thisWeek.days[0]));
t('지난주 칸에는 그대로 남아 있다', W.week('2026-09-14').days[0].kept === true);

console.log('\n[10] 주간 요약');
reset();
['2026-09-14', '2026-09-16', '2026-09-18'].forEach(k => S.setSchedulePlan(k, 'gym', true));
S.setScheduleDone('2026-09-14', 'gym', true);
const sum = W.weekSummary('2026-09-14');
t('계획한 날 3일', sum.plannedDays === 3, JSON.stringify(sum));
t('지킨 날 1일', sum.keptDays === 1);
t('지나갔는데 못 한 날 2일', sum.missedDays === 2);
t('계획 = 지킴 + 못함 + 남음', sum.plannedDays === sum.keptDays + sum.missedDays + sum.openDays);

console.log('\n[11] 식단 기록 스트릭');
reset();
t('기록이 없으면 0일', W.foodStreak(TODAY).days === 0);
[-2, -1, 0].forEach(n => S.addFoodLog({ date: d(n), meal: '점심', items: [{ name: '밥', kcal: 300 }] }));
let fs = W.foodStreak(TODAY);
t('사흘 연속이면 3일', fs.days === 3, JSON.stringify(fs));
t('오늘 적었으니 남은 게 없다', fs.openToday === false);
reset();
[-3, -2, -1].forEach(n => S.addFoodLog({ date: d(n), meal: '점심', items: [{ name: '밥', kcal: 300 }] }));
fs = W.foodStreak(TODAY);
t('오늘 아직 안 적었어도 어제까지 3일이 살아 있다', fs.days === 3, JSON.stringify(fs));
t('오늘은 "남음"', fs.openToday === true);
reset();
[-3, -1].forEach(n => S.addFoodLog({ date: d(n), meal: '점심', items: [{ name: '밥', kcal: 300 }] }));
t('하루 비면 거기서 끊긴다', W.foodStreak(TODAY).days === 1);
/* 연속이 끊긴 날에도 최근 7일 창은 남아야 합니다 — 연속 하나만
   보여 주면 하루 빼먹은 사람은 앱을 닫습니다. */
t('최근 7일 중 며칠인지도 센다', W.foodStreak(TODAY).last7 === 2,
  JSON.stringify(W.foodStreak(TODAY)));

console.log('\n[11-2] 요일 체크만 해도 "이번 주 기록함" 이 된다');
/* 이것만 쓰는 사람이 친구 화면에서 영원히 "이번 주 아직" 으로 남았습니다 —
   매일 체크하고 있는데요. 재는 것이 "기록을 했는가" 라면 둘 다 기록입니다. */
reset();
t('아무것도 안 했으면 false', S.weeklySnapshot().checkedIn === false);
S.setSchedulePlan(S.dayKey(), 'gym', true);
t('계획만 세운 것은 기록이 아니다', S.weeklySnapshot().checkedIn === false,
  JSON.stringify(S.weeklySnapshot()));
S.setScheduleDone(S.dayKey(), 'gym', true);
t('체크하면 기록한 것이 된다', S.weeklySnapshot().checkedIn === true,
  JSON.stringify(S.weeklySnapshot()));
reset();
S.set({ checkins: [{ at: new Date().toISOString(), weightKg: 80 }] });
t('주간 체크인만 해도 여전히 true', S.weeklySnapshot().checkedIn === true);

console.log('\n[12] 기기에 실제로 남는가');
reset();
S.setSchedulePlan(d(-1), 'gym', true);
S.setScheduleDone(d(-1), 'gym', true);
const raw = mem['mybody.state.v1'];
t('저장소에 그 날이 적혀 있다', raw.indexOf(d(-1)) > 0);
t('백업 파일에 일정이 들어 있다', S.exportJSON().indexOf('"schedule"') > 0);

/* 앱을 껐다 켜는 것 흉내: 메모리 상태를 비우고 저장소에서 다시 읽습니다.
   (store.load() 는 저장소가 비어 있으면 현재 상태를 그대로 둡니다 —
   앱에서는 부팅 때 한 번만 부르므로 그게 맞습니다. 그래서 여기서도
   저장소를 비우는 대신 저장소 내용을 그대로 두고 상태만 갈아 끼웁니다.) */
S.importJSON(JSON.stringify(S.blank()));
t('상태를 비우면 스트릭도 0', W.workoutStreak(TODAY).days === 0);
mem['mybody.state.v1'] = raw;
S.load();
t('다시 켜면 일정이 돌아온다', W.workoutStreak(TODAY).days === 1,
  JSON.stringify(S.get().schedule));

console.log('\n' + (fail ? '✗ ' + fail + '개 실패 / ' : '✓ 전부 통과 — ') + (pass + fail) + '개');
if (fail) process.exit(1);

/* --- 시간대 --------------------------------------------------------------
 * 날짜 계산은 시간대가 UTC 나 한국일 때만 맞는 경우가 흔합니다. 실제로
 * dayKey() 가 'YYYY-MM-DD' 를 UTC 자정으로 읽어서, UTC 뒤쪽 시간대에서는
 * 저장 키가 하루씩 밀렸습니다 — 화면은 멀쩡한데 스트릭이 오늘 것을 영영
 * 못 찾았습니다. 컨테이너가 UTC 라 시험은 전부 통과했습니다.
 *
 * 그래서 이 파일을 몇 개 시간대에서 다시 돌립니다. 개발 기기의 시간대가
 * 무엇이든 같은 답이 나와야 합니다.
 * ---------------------------------------------------------------------- */
if (!process.env.MB_TZ_SWEEP) {
  const cp = require('node:child_process');
  const ZONES = ['UTC', 'Asia/Seoul', 'America/Los_Angeles',
                 'America/Sao_Paulo', 'Pacific/Kiritimati', 'Asia/Kathmandu'];
  console.log('\n[시간대] 같은 시험을 다른 시간대에서');
  let bad = 0;
  for (const tz of ZONES) {
    const r = cp.spawnSync(process.execPath, [__filename], {
      env: { ...process.env, TZ: tz, MB_TZ_SWEEP: '1' }, encoding: 'utf8'
    });
    const okTz = r.status === 0;
    if (!okTz) bad++;
    const line = (r.stdout || '').trim().split('\n').filter(Boolean).pop() || '';
    console.log('  ' + (okTz ? '✓' : '✗') + ' ' + tz + (okTz ? '' : '   ' + line));
  }
  console.log('\n' + (bad ? '✗ 시간대 ' + bad + '개에서 실패' : '✓ 시간대 ' + ZONES.length + '개 전부 통과'));
  process.exit(bad ? 1 : 0);
}
