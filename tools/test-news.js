/* =============================================================================
 * tools/test-news.js — 친구 소식: 좋은 것만 흐르는가
 *
 *   node tools/test-news.js
 *
 * 이 기능의 핵심은 무엇이 흐르느냐가 아니라 **무엇이 흐를 수 없느냐** 입니다.
 * 소식은 "지킴 일수가 늘었을 때" 만 생깁니다. 그래서 "안 했다" 는 못 만든
 * 기능이 아니라 만들 수 없는 상태여야 하고, 그걸 여기서 셉니다.
 * ========================================================================== */
global.window = global;
let mem = {};
global.localStorage = {
  getItem: k => (k in mem ? mem[k] : null),
  setItem: (k, v) => { mem[k] = String(v); },
  removeItem: k => { delete mem[k]; }
};
require('../prototype/js/news.js');
const N = window.MB_NEWS;

let pass = 0, fail = 0;
const t = (n, c, d) => {
  if (c) { pass++; console.log('  ✓ ' + n); }
  else { fail++; console.log('  ✗ ' + n, d === undefined ? '' : JSON.stringify(d)); }
};
const reset = () => { mem = {}; };
const WK = '2026-09-14';
const snap = (id, kept, planned, week) => ([{ id,
  rows: [{ weekStart: week || WK, keptDays: kept, plannedDays: planned == null ? 4 : planned }] }]);
const FR = [{ id: 'f1', displayName: '나린' }];

console.log('\n[1] 처음 보는 친구는 조용하다');
reset();
t('첫 pull 에서는 소식이 안 생긴다', N.apply(snap('f1', 3), FR, '2026-09-20T10:00:00Z') === 0);
t('목록도 비어 있다', N.list().length === 0);
/* 안 그러면 친구를 맺은 첫 순간에 지난 사흘치가 방금 일어난 것처럼 쏟아집니다. */

console.log('\n[2] 늘어나면 소식이 된다');
t('3 → 4 는 소식 1건', N.apply(snap('f1', 4), FR, '2026-09-20T11:00:00Z') === 1);
const it = N.list()[0];
/* 이름은 박아 두지 않습니다 — 친구가 이름을 바꾸면 옛 이름이 남습니다.
   화면이 그릴 때 친구 목록에서 찾습니다. 여기서는 누구인지만 있으면 됩니다. */
t('누구인지 알 수 있다', it && it.friendId === 'f1', it);
t('이름을 박아 두지 않는다', it && it.name === undefined, it);
t('몇 일째인지 적혀 있다', it && it.keptDays === 4, it);
t('계획 일수도 같이 온다', it && it.plannedDays === 4, it);

console.log('\n[3] 나쁜 소식은 흐를 수 없다');
t('그대로면 소식 없음', N.apply(snap('f1', 4), FR, '2026-09-20T12:00:00Z') === 0);
t('줄어들어도 소식 없음', N.apply(snap('f1', 2), FR, '2026-09-20T13:00:00Z') === 0);
t('0 이 되어도 소식 없음', N.apply(snap('f1', 0), FR, '2026-09-20T14:00:00Z') === 0);
t('계획만 늘어도 소식 없음',
  N.apply(snap('f1', 0, 7), FR, '2026-09-20T15:00:00Z') === 0);
/* 줄어드는 동안 새 소식은 한 건도 안 생겼습니다(위 네 줄이 전부 0).
   그리고 근거가 사라진 "4일째" 줄은 거둬들여져 있어야 합니다 —
   자세한 것은 [3-2]. 여기서 볼 것은 "늘어난 것이 없다" 입니다. */
t('남은 줄이 지금 값보다 큰 숫자를 주장하지 않는다',
  N.list().every(function (x) { return x.keptDays <= 0; }), N.list());

console.log('\n[3-2] 친구가 체크를 되돌리면 그 소식은 거둬들인다');
reset();
N.apply(snap('f1', 1), FR, '2026-09-20T10:00:00Z');
N.apply(snap('f1', 2), FR, '2026-09-20T11:00:00Z');
N.apply(snap('f1', 3), FR, '2026-09-20T12:00:00Z');
t('소식 두 건', N.list().length === 2, N.list().map(x => x.keptDays));
N.apply(snap('f1', 2), FR, '2026-09-20T13:00:00Z');
t('3일째 주장은 사라진다', N.list().every(x => x.keptDays <= 2), N.list().map(x => x.keptDays));
t('아직 참인 2일째는 남는다', N.list().length === 1 && N.list()[0].keptDays === 2, N.list());
t('거둬들인 것이 되살아나지 않는다', (function () {
  N.apply(snap('f1', 2), FR, '2026-09-20T14:00:00Z');
  return N.list().length === 1;
})(), N.list());
t('다시 올라가면 새 소식이 된다',
  N.apply(snap('f1', 3), FR, '2026-09-20T15:00:00Z') === 1);

console.log('\n[4] 주가 바뀌어 0 으로 돌아간 것은 소식이 아니다');
reset();
N.apply(snap('f1', 3), FR, '2026-09-20T10:00:00Z');
t('새 주 첫 값은 조용하다',
  N.apply(snap('f1', 0, 4, '2026-09-21'), FR, '2026-09-21T09:00:00Z') === 0);
t('그 주에 하나 하면 그때부터 소식',
  N.apply(snap('f1', 1, 4, '2026-09-21'), FR, '2026-09-21T20:00:00Z') === 1);

console.log('\n[4-2] 친구가 아니게 되거나 공유를 끄면 소식도 사라진다');
reset();
N.apply(snap('f1', 1), FR, '2026-09-20T10:00:00Z');
N.apply(snap('f1', 2), FR, '2026-09-20T11:00:00Z');
t('소식이 있다', N.list().length === 1);
/* 친구가 일정 공유를 끕니다 — 스냅샷에 keptDays 가 안 실려 옵니다 */
N.apply([{ id: 'f1', rows: [{ weekStart: WK, checkedIn: true }] }], FR, '2026-09-20T12:00:00Z');
t('공유를 끄면 그 사람 소식이 사라진다', N.list().length === 0, N.list());
/* 친구를 끊으면 목록에서 빠집니다 */
reset();
N.apply(snap('f1', 1), FR, '2026-09-20T10:00:00Z');
N.apply(snap('f1', 2), FR, '2026-09-20T11:00:00Z');
N.apply([], [], '2026-09-20T12:00:00Z');
t('친구를 끊으면 소식도 사라진다', N.list().length === 0, N.list());

console.log('\n[4-3] 오래된 소식은 버린다');
reset();
N.apply(snap('f1', 1), FR, '2026-08-01T10:00:00Z');
N.apply(snap('f1', 2), FR, '2026-08-01T11:00:00Z');
t('그 시점엔 남아 있다', N.list().length === 1);
N.apply(snap('f1', 3), FR, '2026-09-20T10:00:00Z');
t('세 주가 지나면 옛 소식은 없다',
  N.list().every(function (x) { return x.at > '2026-09-01'; }), N.list());

console.log('\n[5] 일정을 공유 안 하는 친구');
reset();
t('숫자가 아예 없으면 소식도 없다',
  N.apply([{ id: 'f1', rows: [{ weekStart: WK, checkedIn: true }] }], FR) === 0);
t('그 뒤에 켜도 첫 값은 조용하다',
  N.apply(snap('f1', 2), FR, '2026-09-20T10:00:00Z') === 0);

console.log('\n[6] 안 읽은 표시');
reset();
N.apply(snap('f1', 1), FR, '2026-09-20T10:00:00Z');
N.apply(snap('f1', 2), FR, '2026-09-20T11:00:00Z');
t('안 읽은 것이 있다', N.unread() === 1, N.unread());
N.markRead();
t('읽으면 0', N.unread() === 0);
N.apply(snap('f1', 3), FR, '2026-09-20T12:00:00Z');
t('그 뒤 새 소식은 다시 잡힌다', N.unread() === 1, N.list());
/* 읽음 표시를 시각으로 하면 기기 시계가 틀어졌을 때 새 소식이 묻힙니다.
   번호로 세므로 과거 시각이 찍힌 소식도 제대로 잡혀야 합니다. */
N.markRead();
N.apply(snap('f1', 4), FR, '2020-01-01T00:00:00Z');
t('시계가 과거로 돌아가도 새 소식은 안 묻힌다', N.unread() === 1, N.list()[0]);

console.log('\n[7] 같은 소식이 두 번 쌓이지 않는다');
reset();
N.apply(snap('f1', 1), FR, '2026-09-20T10:00:00Z');
N.apply(snap('f1', 2), FR, '2026-09-20T11:00:00Z');
mem['mybody.news.v1'] = JSON.stringify(Object.assign(
  JSON.parse(mem['mybody.news.v1']), { seen: {} }));       // 거울만 날려 봅니다
N.apply(snap('f1', 2), FR, '2026-09-20T12:00:00Z');
t('거울이 날아가도 같은 소식이 두 번 안 생긴다', N.list().length === 1, N.list());

console.log('\n[8] 목록이 무한히 자라지 않는다');
reset();
for (let i = 1; i <= N.MAX + 15; i++) {
  N.apply(snap('f1', i, 99), FR, '2026-09-20T' + String(10 + (i % 10)).padStart(2, '0') + ':00:00Z');
}
t('상한을 넘지 않는다', N.list(999).length <= N.MAX, N.list(999).length);
t('최신이 앞에 온다', N.list()[0].keptDays > N.list()[1].keptDays, N.list().slice(0, 2));

console.log('\n[9] 지우면 남의 기록이 안 남는다');
N.reset();
t('목록이 비었다', N.list().length === 0);
t('안 읽은 것도 0', N.unread() === 0);
t('저장소 칸 자체가 없다', mem['mybody.news.v1'] === undefined);

console.log('\n[10] 저장소가 깨져도 앱이 안 멈춘다');
mem['mybody.news.v1'] = '{깨진 json';
t('목록은 빈 배열', N.list().length === 0);
t('그 뒤 새 소식은 정상', (function () {
  N.apply(snap('f1', 1), FR, '2026-09-20T10:00:00Z');
  return N.apply(snap('f1', 2), FR, '2026-09-20T11:00:00Z') === 1;
})());

console.log('\n' + (fail ? '✗ ' + fail + '개 실패 / ' : '✓ 전부 통과 — ') + (pass + fail) + '개');
process.exit(fail ? 1 : 0);
