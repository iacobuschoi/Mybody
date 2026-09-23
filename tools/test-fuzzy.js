/* =============================================================================
 * tools/test-fuzzy.js — 음식 검색 "비슷한 이름"(fooddb.similar) 시험
 *
 *   node tools/test-fuzzy.js
 *
 * search() 는 글자열 포함만 보니 '김치찌게' 처럼 한 글자 틀리면 0건입니다.
 * similar() 는 그때 비슷한 이름을 올립니다. 시험은 세 방향입니다.
 *   (가) 명세의 기대 예시가 그대로 나오는가
 *   (나) 흔한 오타(받침 빠짐·모음 바뀜·인접 글자 바꿈·띄어쓰기·영문 자판)
 *        에서 "첫 결과" 가 기대한 음식인가 — 사용자는 첫 줄만 누릅니다
 *   (다) 결과 모양이 명세대로인가 — 정수 점수, 정렬, limit, 이상 입력
 * ========================================================================== */
global.window = global;
require('../prototype/js/fooddb.js');
const F = window.MB_FOOD;

let pass = 0, fail = 0;
function t(name, cond, extra) {
  if (cond) { pass++; console.log('  ✓ ' + name); }
  else { fail++; console.log('  ✗ ' + name + (extra ? '\n      ' + extra : '')); }
}
/* 첫 결과가 기대한 이름인가. why 를 주면 그것도 같아야 합니다. */
function first(q, name, why, label) {
  const r = F.similar(q);
  const top = r[0];
  const ok = !!top && top.name === name && (!why || top.why === why);
  t((label ? label + ' — ' : '') + JSON.stringify(q) + ' → ' + name + (why ? ' (' + why + ')' : ''), ok,
    '실제: ' + JSON.stringify(r.slice(0, 3)));
}

console.log('\n[1] 명세의 기대 예시');
first('김치찌게', '김치찌개', 'typo');
first('제육복음', '제육볶음', 'typo');
first('닭가습살', '닭가슴살(생)', 'typo');
first('닭가ㅅ', '닭가슴살(생)', 'partial');
first('ㄷㄱㅅㅅ', '닭가슴살(생)', 'chosung');
/* 명세의 예시 'ekfrktmatkf' 는 닭가슴살 두벌식(ekfrrktmatkf)에서 r 하나가
   빠진 것입니다. 자판 후보 위에서 편집거리 1 로 잡혀 why 는 qwerty 로 나옵니다. */
first('ekfrktmatkf', '닭가슴살(생)', 'qwerty');
first('ekfrrktmatkf', '닭가슴살(생)', 'qwerty', '빠진 키 없이');
first('초밥연어', '초밥(연어) 10개', 'partial');
first('된장찌게', '된장찌개', 'typo');
first('삼결살', '삼겹살 구이', 'typo');
first('프로틴 바', '프로틴바(일반) 1개', 'partial');
first('햇반', '즉석밥(햇반 210g)', 'partial');
t('"zzz" → []', F.similar('zzz').length === 0, JSON.stringify(F.similar('zzz')));
{
  const r = F.similar('밥');
  t('"밥" → 밥 들어간 것 다수 (자모 3개라 정상)', r.length > 0 && r.every(x => x.why === 'partial'),
    JSON.stringify(r));
}

console.log('\n[2] 받침 빠짐 · 자음 바뀜');
first('삼겹사', '삼겹살 구이', 'partial', '받침 빠짐');
first('닭가슴사', '닭가슴살(생)', 'partial', '받침 빠짐');
first('제육보끔', '제육볶음', 'typo', '받침 빠짐(ㅇ)');
first('비빔밤', '비빔밥', 'typo', '받침 바뀜');
first('쨔장면', '짜장면', 'typo', '모음 하나 바뀜');  // '자장면' 은 이제 별명이라 search 가 먼저 잡습니다

console.log('\n[3] 모음 바뀜');
first('순두부찌게', '순두부찌개', 'typo');
first('부대찌게', '부대찌개', 'typo');
first('게란후라이', '계란후라이', 'typo');
first('오무라이스', '오므라이스', 'partial', '별명에 있는 오타');

console.log('\n[4] 인접 글자 바꿈');
/* '곹망' 은 ㅁ·ㅌ 을 바꿔 친 것. 자모 6개라 허용 거리가 1 이므로
   바꿈을 1 로 세지 않으면(치환 2) 못 잡습니다 — 교환 규칙 자체의 시험. */
first('곹망', '곰탕', 'typo', 'ㅁㅌ 바꿈');
first('삼겻발', '삼겹살 구이', 'typo', 'ㅂㅅ 바꿈');
first('가리ㅂ탕', '갈비탕', 'typo', 'ㄹㅂ 바꿈(입력기 결과 그대로)');

console.log('\n[5] 띄어쓰기');
first('김치 찌개', '김치찌개', 'partial');
first('닭 가슴살', '닭가슴살(생)', 'partial');
first('삼겹살구이', '삼겹살 구이', 'partial', '붙여 씀');
first('프로틴 쉐이크', '프로틴 쉐이크(물)', 'partial');
first('된장 찌게', '된장찌개', 'typo', '띄어쓰기 + 오타');

console.log('\n[6] 영문 자판 (한/영 전환 안 함)');
first('rlaclWlro', '김치찌개', 'qwerty');
first('tkaruqtkf', '삼겹살 구이', 'qwerty');
first('tkarutkf', '삼겹살 구이', 'qwerty', '키 하나 빠짐');
first('fkaus', '라면', 'qwerty');
first('qlqlaqkq', '비빔밥', 'qwerty');
/* 떡볶이 를 담은 이름이 다섯이고 점수가 같아 정규화 이름이 제일 짧은
   컵떡볶이 가 앞입니다 — 명세의 3단 정렬(점수 → 짧은 이름 → 표 순서). */
first('EjrqhRdl', '컵떡볶이', 'qwerty', '대문자 = 쌍자음');
t('영문 별명은 자판 변환 없이 그대로도 잡힌다 ("chicken")',
  F.similar('chicken').length > 0 && F.similar('chicken')[0].why === 'partial',
  JSON.stringify(F.similar('chicken').slice(0, 3)));

console.log('\n[6b] 앞뒤에 붙인 말 · 괄호 순서 · 별명 둘 붙이기');
first('아이스아메리카노', '아메리카노', 'partial');
first('소주 1병', '소주', 'partial');
first('삼겹살 200g', '삼겹살 구이', 'partial');
first('물냉면', '냉면(물)', 'partial');
first('크림파스타', '파스타(크림)', 'partial');
first('돼지고기 김치찌개', '김치찌개', 'partial');
first('protien bar', '프로틴바(일반) 1개', 'typo');
first('닭가슴살 샐러드', '샐러드(닭가슴살) 1볼', 'partial');
t('오타 하나가 "품은 말" 보다 위 — 김치찌게 → 김치찌개', F.similar('김치찌게')[0].name === '김치찌개');

console.log('\n[7] 초성');
first('ㄱㅊㅉㄱ', '김치찌개', 'chosung');
first('ㅅㄱㅅ', '삼겹살 구이', 'chosung');
first('ㅍㄹㅌㅂ', '프로틴바(일반) 1개', 'chosung');
t('초성은 이름(88)이 별명(85)보다 앞', (() => {
  const r = F.similar('ㅍㄹㅌㅂ');
  return r[0].score === 88 && r.some(x => x.score === 85) &&
         r.findIndex(x => x.score === 85) > r.findIndex(x => x.score === 88);
})(), JSON.stringify(F.similar('ㅍㄹㅌㅂ')));

console.log('\n[8] 결과 모양');
{
  const r = F.similar('닭가슴살');
  t('키는 name·score·why 만', r.length > 0 && r.every(x => Object.keys(x).join(',') === 'name,score,why'),
    JSON.stringify(r[0]));
  t('점수는 정수', r.every(x => Number.isInteger(x.score)), JSON.stringify(r.map(x => x.score)));
  t('점수 내림차순', r.every((x, i) => i === 0 || r[i - 1].score >= x.score),
    JSON.stringify(r.map(x => x.score)));
  t('why 는 네 가지 중 하나', r.every(x => ['partial', 'typo', 'chosung', 'qwerty'].indexOf(x.why) >= 0),
    JSON.stringify(r.map(x => x.why)));
  t('50점 미만은 없다', r.every(x => x.score >= 50));
}
t('기본 limit 8', F.similar('밥').length === 8, F.similar('밥').length);
t('limit 3', F.similar('밥', 3).length === 3, F.similar('밥', 3).length);
t('같은 점수는 짧은 이름 → 표 순서 (삼결살: 삼겹살 구이 < 삼겹살 1인분)', (() => {
  const r = F.similar('삼결살');
  return r[0].name === '삼겹살 구이' && r[1].name === '삼겹살 1인분' && r[0].score === r[1].score;
})(), JSON.stringify(F.similar('삼결살')));
t('두 번 불러도 글자 단위로 같다',
  JSON.stringify(F.similar('김치찌게')) === JSON.stringify(F.similar('김치찌게')));
t('search 가 0건인 오타를 similar 가 받는다', F.search('김치찌게').length === 0 && F.similar('김치찌게').length > 0);
t('FOODS 항목에 칸이 늘지 않았다 (Dart 표 생성기가 그대로 찍는다)',
  F.FOODS.every(x => Object.keys(x).join(',') === 'name,cat,unit,g,kcal,p,c,f,conf,alias'),
  Object.keys(F.FOODS[0]).join(','));

console.log('\n[9] 빈 입력 · 이상 입력에서 안 터진다');
[['', '빈 문자열'], ['   ', '공백만'], [null, 'null'], [undefined, 'undefined'], ['z', '영문 한 글자'],
 ['ㅋ', '자모 한 글자'], ['1', '숫자 한 글자'], ['(())', '기호만'], [12, '숫자형']].forEach(([q, nm]) => {
  let ok = true, out = null, err = '';
  try { out = F.similar(q); } catch (e) { ok = false; err = String(e); }
  t(nm + ' → 예외 없이 []', ok && Array.isArray(out) && out.length === 0, err || JSON.stringify(out));
});
{
  let ok = true, err = '';
  try { F.similar('아주아주긴검색어를넣어도괜찮아야합니다김치찌개된장찌개순두부찌개'); F.similar('a'.repeat(200)); }
  catch (e) { ok = false; err = String(e); }
  t('긴 입력에서 예외 없음', ok, err);
}

console.log('\n통과 ' + pass + ' / 실패 ' + fail);
process.exit(fail ? 1 : 0);
