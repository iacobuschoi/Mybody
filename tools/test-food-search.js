/* =============================================================================
 * tools/test-food-search.js — 음식 고르기에서 오타를 쳐도 비슷한 이름이 뜨는가
 *
 *   NODE_PATH=/opt/node22/lib/node_modules node tools/test-food-search.js
 *
 * 계산은 test-fuzzy.js 가 봅니다(similar 가 무엇을 돌려주는가). 여기서 보는
 * 건 그것이 화면까지 닿는가입니다 — '김치찌게' 를 치면 "찾는 음식이
 * 없습니다" 대신 김치찌개가 같은 모양의 행으로 뜨는가, 검색어는 친 그대로
 * 남는가, 눌러서 담을 수 있는가, 정확히 겹치는 게 있을 땐 끼어들지 않는가.
 *
 * 왜 따로 보나: 검색 함수가 맞는 답을 돌려줘도 화면이 그걸 빈 상태 뒤에
 * 숨기면 쓰는 사람에게는 없는 기능입니다. 오타를 친 사람은 표에 없는 줄
 * 알고 직접 입력으로 갑니다 — 그 한 번이 그 음식의 영양 정보를 영영
 * 대충 적힌 값으로 만듭니다.
 * ========================================================================== */
'use strict';
/* 검사하는 사람의 ~/.mybody 설정이 결과를 바꾸지 않게 떼어 놓습니다. */
require('./testenv.js');
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const { chromium } = require(process.env.NODE_PATH
  ? path.join(process.env.NODE_PATH, 'playwright') : 'playwright');

const ROOT = path.join(__dirname, '..', 'prototype');
const PORT = 8900 + Math.floor(Math.random() * 200);
const CHROME = process.env.CHROME_PATH || '/opt/pw-browsers/chromium-1194/chrome-linux/chrome';
const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css',
               '.json': 'application/json', '.svg': 'image/svg+xml',
               '.webmanifest': 'application/manifest+json' };

const server = http.createServer((req, res) => {
  let p = decodeURIComponent(req.url.split('?')[0]);
  if (p === '/') p = '/index.html';
  const f = path.join(ROOT, p);
  if (!f.startsWith(ROOT) || !fs.existsSync(f) || fs.statSync(f).isDirectory()) {
    res.writeHead(404); return res.end('404');
  }
  res.writeHead(200, { 'Content-Type': MIME[path.extname(f)] || 'application/octet-stream' });
  res.end(fs.readFileSync(f));
});

let pass = 0, fail = 0;
const ok = (n, c, d) => {
  if (c) { pass++; console.log('  ✓', n); }
  else { fail++; console.log('  ✗', n, d === undefined ? '' : JSON.stringify(d).slice(0, 240)); }
};

(async () => {
  await new Promise(r => server.listen(PORT, r));
  const browser = await chromium.launch({ executablePath: CHROME });
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 } });
  const page = await ctx.newPage();
  const errs = [];
  page.on('pageerror', e => errs.push('PAGEERROR: ' + e.message.slice(0, 200)));
  page.on('console', m => {
    if (m.type() !== 'error') return;
    /* 정적 서버에 /health 가 없는 건 맞는 상태입니다 (smoke.js 와 같은 이유) */
    if (/health|Failed to load resource/.test(m.text())) return;
    errs.push('CONSOLE: ' + m.text().slice(0, 200));
  });

  /* 개발 빌드에만 있는 우하단 도크를 치웁니다 — 목록 아래쪽 버튼을 가립니다. */
  const hideDock = () => page.addStyleTag({ content: '.uid-dock{display:none!important}' });
  const u = s => `[data-uid="${s}"]`;
  const count = s => page.locator(u(s)).count();
  const text = s => page.locator(u(s)).innerText();
  /* 검색칸에 넣고 화면이 따라오길 잠깐 기다립니다. fill 은 input 이벤트를
     쏘므로 화면의 onInput 이 그대로 돕니다. */
  const type = async s => { await page.locator(u('P19-F01')).fill(s); await page.waitForTimeout(120); };
  const inputValue = () => page.locator(u('P19-F01')).inputValue();
  /* 비슷한 이름 행들의 (이름 줄, 전체 글) */
  const rows = () => page.locator('[data-uid^="P19-B12#"]').evaluateAll(els => els.map(e => ({
    name: e.querySelector('div > div > div').innerText, all: e.innerText
  })));

  await page.goto(`http://localhost:${PORT}/?app=1`, { waitUntil: 'load' });
  await page.waitForTimeout(350);
  await hideDock();
  await page.evaluate(() => { window.MB_STORE.seed(); window.MB_APP.go('P19'); });
  await page.waitForTimeout(350);
  ok('음식 고르기 화면이 뜬다', await count('P19-F01') === 1);

  console.log('\n[1] 오타 — 정확히 겹치는 게 없을 때 비슷한 이름이 뜬다  ← 핵심');
  await type('김치찌게');
  ok('search 는 정말 0건이다 (시험의 전제)',
     await page.evaluate(() => window.MB_FOOD.search('김치찌게').length) === 0);
  ok('"찾는 음식이 없습니다" 가 아니다', await count('P19-S01') === 0);
  ok('비슷한 이름 구간이 있다', await count('P19-L02') === 1);
  {
    const t = await text('P19-L02');
    ok("제목이 친 그대로를 인용한다 — '김치찌게' 와 비슷한 이름",
       t.includes("'김치찌게' 와 비슷한 이름"), t.slice(0, 80));
    const r = await rows();
    ok('첫 행이 김치찌개', r.length > 0 && /^김치찌개/.test(r[0].name), r[0]);
    ok('첫 행에 "비슷한 이름" 표시', r.length > 0 && r[0].name.includes('비슷한 이름'), r[0]);
    ok('행이 검색 결과 행과 같은 모양(단위·kcal·단백질)',
       r.length > 0 && /g · \d+kcal · 단백질/.test(r[0].all), r[0]);
    ok('8개 이하', r.length >= 1 && r.length <= 8, r.length);
    ok('직접 입력으로 가는 길이 그 아래 있다',
       await page.locator(u('P19-L02') + ' ' + u('P19-B02')).count() === 1 &&
       t.includes('직접 입력'));
  }
  ok('검색어를 지우거나 고치지 않는다', await inputValue() === '김치찌게', await inputValue());

  console.log('\n[2] 행을 누르면 그대로 담긴다');
  await page.locator(u('P19-B12#1')).click();
  await page.waitForTimeout(250);
  ok('양 고르기 창이 뜬다', await count('M40') === 1);
  ok('창 제목이 김치찌개', (await text('M40')).includes('김치찌개'));
  await page.locator(u('M40-B99')).click();
  await page.waitForTimeout(250);
  ok('닫으면 검색어가 그대로 남아 있다', await inputValue() === '김치찌게');
  ok('비슷한 이름도 그대로', await count('P19-L02') === 1);

  console.log('\n[3] 왜 나왔는지 — 작은 표시');
  await type('ㄷㄱㅅㅅ');
  { const r = await rows();
    ok('초성 → 닭가슴살 · "초성"', r.length > 0 && /^닭가슴살/.test(r[0].name) && r[0].name.includes('초성'), r[0]); }
  await type('ekfrktmatkf');
  { const r = await rows();
    ok('한/영 전환 안 함 → 닭가슴살 · "한/영 자판"',
       r.length > 0 && /^닭가슴살/.test(r[0].name) && r[0].name.includes('한/영 자판'), r[0]); }
  await type('닭가ㅅ');
  { const r = await rows();
    ok('치는 중(받침) → 닭가슴살, 표시 없음',
       r.length > 0 && /^닭가슴살/.test(r[0].name) &&
       !/비슷한 이름|초성|한\/영 자판/.test(r[0].name), r[0]); }

  console.log('\n[4] 정확히 겹치는 게 있을 땐 끼어들지 않는다');
  await type('김치찌개');
  ok('검색 결과가 있다', await page.locator(u('P19-L01') + ' .card').count() > 0);
  ok('비슷한 이름 구간이 없다', await count('P19-L02') === 0);
  await type('김치찌');
  ok('치는 중에도(부분 일치가 있으면) 없다', await count('P19-L02') === 0 &&
     await page.locator(u('P19-L01') + ' .card').count() > 0);

  console.log('\n[5] 비슷한 것도 없으면 기존 빈 상태 그대로');
  await type('zzzz');
  ok('비슷한 이름 구간이 없다', await count('P19-L02') === 0);
  ok('"찾는 음식이 없습니다" + 직접 입력', await count('P19-S01') === 1 &&
     await page.locator(u('P19-S01') + ' ' + u('P19-B02')).count() === 1);

  console.log('\n[6] 한 글자씩 칠 때 검색칸이 흔들리지 않는다');
  await type('');
  await page.locator(u('P19-F01')).pressSequentially('김치찌게', { delay: 40 });
  await page.waitForTimeout(150);
  ok('값이 친 그대로', await inputValue() === '김치찌게', await inputValue());
  ok('포커스가 검색칸에 남아 있다',
     await page.evaluate(() => document.activeElement === document.querySelector('[data-uid="P19-F01"]')));
  ok('비슷한 이름이 떠 있다', await count('P19-L02') === 1);
  ok('9번째 행은 없다', await count('P19-B12#9') === 0);

  console.log('\n[7] 분류 칩은 비슷한 이름에도 똑같이 걸린다');
  await page.locator(u('P19-F02') + ' .chip', { hasText: '국찌개' }).click();
  await page.waitForTimeout(200);
  ok('칩을 눌러도 검색어는 남는다', await inputValue() === '김치찌게');
  ok('국찌개 칩 → 김치찌개가 보인다', await count('P19-L02') === 1 &&
     /^김치찌개/.test(((await rows())[0] || {}).name || ''));
  await page.locator(u('P19-F02') + ' .chip', { hasText: '밥' }).first().click();
  await page.waitForTimeout(200);
  {
    /* 밥 칩이 켜져 있으면 밥 분류만 — 김치찌개(국찌개)는 안 끼고, 김치김밥 같은 밥 음식만 남습니다. */
    const names = (await rows()).map(r => r.name || '');
    const F = await page.evaluate(() => window.MB_FOOD.FOODS.map(x => [x.name, x.cat]));
    const cat = Object.fromEntries(F);
    ok('밥 칩 → 국찌개는 끼어들지 않고 밥 분류만', names.every(n => { const k = Object.keys(cat).find(x => n.indexOf(x) === 0); return !k || cat[k] === '밥'; }) &&
       !names.some(n => /^김치찌개/.test(n)), names);
  }
  await page.locator(u('P19-F02') + ' .chip', { hasText: '전체' }).click();
  await page.waitForTimeout(200);

  console.log('\n[8] 고유번호 규칙');
  {
    const uids = await page.evaluate(() =>
      [...document.querySelectorAll('#main [data-uid]')].map(e => ({
        uid: e.getAttribute('data-uid'), label: e.getAttribute('data-uid-label') || '' })));
    const RE = /^(P\d{2}|M\d{2}|A\d{2})(-[A-Z]\d{2})?(#\d+)?$/;
    const seen = new Set(), dup = [];
    uids.forEach(x => { if (seen.has(x.uid)) dup.push(x.uid); seen.add(x.uid); });
    ok('형식 위반 없음', uids.every(x => RE.test(x.uid)), uids.filter(x => !RE.test(x.uid)));
    ok('중복 없음', dup.length === 0, dup);
    ok('라벨 없는 번호 없음', uids.every(x => x.label), uids.filter(x => !x.label));
    ok('P19-L02 · P19-B12#1 이 실제로 있다', seen.has('P19-L02') && seen.has('P19-B12#1'));
  }

  console.log('\n[9] JS 오류');
  ok('오류 0건', errs.length === 0, errs.slice(0, 3));

  await browser.close();
  server.close();
  console.log(`\n통과 ${pass} / 실패 ${fail}`);
  process.exit(fail ? 1 : 0);
})().catch(e => { console.error(e); server.close(); process.exit(1); });
