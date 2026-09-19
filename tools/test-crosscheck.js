/* =============================================================================
 * tools/test-crosscheck.js — 판독 검산 (1층) 시험
 *
 *   node tools/test-crosscheck.js
 *
 * 검산의 목적은 하나입니다: 그럴듯하게 생긴 틀린 숫자를 잡는 것.
 * 그래서 시험도 두 방향입니다.
 *   (가) 진짜 결과지는 조용히 통과하는가      — 거짓 경보가 없어야
 *   (나) 한 칸을 흔한 방식으로 망가뜨리면 걸리는가 — 놓치는 게 없어야
 * ========================================================================== */
global.window = global;
require('../prototype/js/crosscheck.js');
const C = window.MB_CHECK;

let pass = 0, fail = 0;
function t(name, cond, extra) {
  if (cond) { pass++; console.log('  ✓ ' + name); }
  else { fail++; console.log('  ✗ ' + name + (extra ? '\n      ' + extra : '')); }
}

const PROF = { heightCm: 181, sex: 'male' };

/* 주인 실측 결과지 3건. 앞 2건은 그래프에서 읽은 부분 데이터라
   칸이 적고, 마지막 1건이 전체 시트입니다. */
const S1 = { measuredAt: '2026-06-30T07:36:00+09:00', weightKg: 89.0, smmKg: 36.2,
             bfmKg: 25.3, pbfPct: 28.4, ffmKg: 63.7 };
const S2 = { measuredAt: '2026-08-31T08:35:00+09:00', weightKg: 86.9, smmKg: 37.4,
             bfmKg: 21.0, pbfPct: 24.2, ffmKg: 65.9 };
const S3 = { measuredAt: '2026-09-19T11:09:00+09:00', weightKg: 86.7, smmKg: 37.9,
             bfmKg: 20.0, pbfPct: 23.1, ffmKg: 66.7, bmi: 26.5, tbwL: 48.7,
             proteinKg: 13.3, mineralKg: 4.70, bmrKcal: 1811, whr: 0.90, inbodyScore: 76 };

console.log('\n[1] 진짜 결과지는 조용히 통과하는가');
[['1차', S1, null], ['2차', S2, S1], ['3차 (전체 시트)', S3, S2]].forEach(([nm, s, p]) => {
  const r = C.run(s, PROF, p);
  t(nm + ' — 모순 0건', r.counts.fail === 0,
    r.checks.filter(c => !c.ok).map(c => c.id + ': ' + c.why).join('\n      '));
  t(nm + ' — 범위 경보 0건', r.rangeIssues.length === 0,
    JSON.stringify(r.rangeIssues));
  t(nm + ' — 변화량 경보 0건', r.deltaIssues.length === 0,
    JSON.stringify(r.deltaIssues));
});

console.log('\n[2] 한 칸을 망가뜨리면 걸리는가');
/* 결과지 판독에서 실제로 나오는 오독들. 각 항목은
   [설명, 망가뜨릴 칸, 망가진 값, 이 칸이 모순으로 찍혀야 하는가] */
const BREAKS = [
  ['소수점 소실 — 체중 86.7 → 867', 'weightKg', 867, true],
  ['소수점 소실 — 골격근 37.9 → 379', 'smmKg', 379, true],
  ['자리바꿈 — 골격근 37.9 → 73.9', 'smmKg', 73.9, true],
  ['자리바꿈 — 체지방 20.0 → 02.0', 'bfmKg', 2.0, true],
  ['량/률 혼동 — 체지방량 칸에 체지방률', 'bfmKg', 23.1, true],
  ['글자 혼동 — 제지방 66.7 → 65.7', 'ffmKg', 65.7, true],   // C1 허용치 0.5kg 밖
  ['글자 혼동 — 체수분 48.7 → 43.7', 'tbwL', 43.7, true],
  ['BMR 자릿수 — 1811 → 1311', 'bmrKcal', 1311, true],
  ['체지방률 소수점 — 23.1 → 2.31', 'pbfPct', 2.31, true],
  ['BMI 오독 — 26.5 → 20.5', 'bmi', 20.5, true],
  ['단백질 오독 — 13.3 → 18.3', 'proteinKg', 18.3, true]
];
BREAKS.forEach(([nm, field, bad, shouldCatch]) => {
  const s = Object.assign({}, S3); s[field] = bad;
  const r = C.run(s, PROF, S2);
  const caught = r.fields[field] === 'conflict' ||
                 r.rangeIssues.some(i => i.field === field && i.level === 'bad') ||
                 r.deltaIssues.some(i => i.field === field && i.level === 'bad');
  t(nm, caught === shouldCatch,
    '잡힘=' + caught + ' 기대=' + shouldCatch + ' · 깨진 검산 ' +
    r.checks.filter(c => !c.ok).map(c => c.id).join(',') + ' · 칸 ' + r.fields[field]);
});

console.log('\n[3] 골격근 구멍 — 짝이 없는 칸은 지난 측정으로 잡는다');
/* 골격근은 결과지 안에 짝이 없습니다. 체중·체지방을 고정하고 골격근만
   훑으면 지난 측정이 없을 때 어디까지 통과하는지 재 봅니다. */
function holeWidth(prev) {
  let lo = null, hi = null;
  for (let x = 10; x <= 60; x = Math.round((x + 0.1) * 10) / 10) {
    const r = C.run(Object.assign({}, S3, { smmKg: x }), PROF, prev);
    const ok = r.fields.smmKg !== 'conflict';
    if (ok && lo === null) lo = x;
    if (ok) hi = x;
  }
  return { lo, hi, width: Math.round((hi - lo) * 10) / 10 };
}
const noPrev = holeWidth(null);
const withPrev = holeWidth(S2);
console.log('    지난 측정 없음: ' + noPrev.lo + '~' + noPrev.hi + 'kg (폭 ' + noPrev.width + ')');
console.log('    지난 측정 있음: ' + withPrev.lo + '~' + withPrev.hi + 'kg (폭 ' + withPrev.width + ')');
t('짝이 없으면 구멍이 넓다 (검산만으로는 못 잡는다는 사실 자체를 기록)', noPrev.width > 10);
t('지난 측정이 구멍을 3kg 아래로 줄인다', withPrev.width <= 3.0, '폭 ' + withPrev.width);
t('실제 값 37.9 는 좁아진 구간 안에 있다', 37.9 >= withPrev.lo && 37.9 <= withPrev.hi);

console.log('\n[4] 복구 제안은 확실할 때만 한다');
{
  const s = Object.assign({}, S3, { weightKg: 867 });
  const r = C.run(s, PROF, S2);
  const sug = r.suggestions.find(x => x.field === 'weightKg');
  t('867kg → 86.7kg 를 제안한다', !!sug && sug.to === 86.7,
    JSON.stringify(r.suggestions));
}
{
  // 두 칸이 동시에 망가지면 무엇이 맞는지 모릅니다 — 제안하면 안 됩니다.
  const s = Object.assign({}, S3, { weightKg: 867, bfmKg: 200 });
  const r = C.run(s, PROF, S2);
  t('두 칸이 동시에 망가지면 제안하지 않는다', r.suggestions.length === 0,
    JSON.stringify(r.suggestions));
}
{
  const r = C.run(S3, PROF, S2);
  t('멀쩡한 결과지에는 제안이 없다', r.suggestions.length === 0);
}

console.log('\n[4-2] 망가진 칸에서 나온 고침 제안은 내보내지 않는다');
{
  /* 체중을 867 로 잘못 넣으면 제지방이 847 이 되고, 거기서 나온
     "골격근량을 481.3kg 로" 버튼이 실제로 화면에 떴습니다.
     누르면 틀린 칸이 하나에서 둘로 늘어납니다. */
  const s = Object.assign({}, S3, { weightKg: 867 });
  const r = C.run(s, PROF, S2);
  const bogus = r.checks.filter(c => c.fix)
    .filter(c => {
      const R = C.RANGE[c.fix.field];
      return R && (c.fix.value < R.hard[0] || c.fix.value > R.hard[1]);
    });
  t('사람의 값이 아닌 고침 제안이 없다', bogus.length === 0,
    JSON.stringify(bogus.map(c => c.id + ':' + c.fix.field + '=' + c.fix.value)));
  t('그래도 어긋났다는 말은 한다', r.counts.fail > 0);
  t('대신 자릿수 제안이 올라온다', r.suggestions.some(x => x.field === 'weightKg' && x.to === 86.7));
}
{
  // 멀쩡한 판에서는 고침 제안이 제대로 나와야 합니다
  const s = Object.assign({}, S3, { ffmKg: 60.0 });   // C1 이 깨짐, 나머지는 정상
  const r = C.run(s, PROF, S2);
  const fix = r.checks.find(c => c.id === 'C1' && c.fix);
  t('고칠 수 있는 경우엔 제안이 나온다', !!fix && Math.abs(fix.fix.value - 66.7) < 0.05,
    JSON.stringify(r.checks.filter(c => !c.ok).map(c => c.id + ' fix=' + JSON.stringify(c.fix))));
}

console.log('\n[5] 남의 결과지 / 시간 뒤틀림');
{
  // 다른 사람 결과지를 잘못 올린 경우: 하루 만에 골격근 5kg
  const s = Object.assign({}, S3, { smmKg: 42.9, weightKg: 92.0, bfmKg: 22.0,
                                    pbfPct: 23.9, ffmKg: 70.0, measuredAt: '2026-09-01T09:00:00+09:00' });
  const r = C.run(s, PROF, S2);
  t('하루 만의 급변은 bad 로 잡힌다', r.deltaIssues.some(i => i.level === 'bad'),
    JSON.stringify(r.deltaIssues));
}
{
  // 측정 간격을 모르면 k 검산을 건너뜁니다 — 0일로 치면 허용치가 최소가 돼
  // 멀쩡한 값이 모순으로 찍힙니다.
  const s = Object.assign({}, S3); delete s.measuredAt;
  const r = C.run(s, PROF, S2);
  t('측정일이 없으면 k 검산을 건너뛴다', !r.checks.some(c => c.id === 'CK'));
  t('그래도 나머지 검산은 돈다', r.counts.pass >= 6);
}

console.log('\n[6] 부분 데이터에서도 안 터진다');
[{}, { weightKg: 86.7 }, { weightKg: 86.7, bfmKg: 20.0 },
 { smmKg: 37.9 }, { weightKg: 0 }, { weightKg: null, smmKg: undefined }].forEach((s, i) => {
  let ok = true, err = '';
  try { C.run(s, PROF, null); C.run(s, null, S2); C.run(s, {}, {}); }
  catch (e) { ok = false; err = String(e); }
  t('부분 입력 ' + (i + 1) + ' 에서 예외 없음', ok, err);
});

console.log('\n통과 ' + pass + ' / 실패 ' + fail);
process.exit(fail ? 1 : 0);
