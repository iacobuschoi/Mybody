/* =============================================================================
 * tools/test-ocr-ui.js — 자동 판독을 화면에서 끝까지 해 본다
 *
 *   NODE_PATH=/opt/node22/lib/node_modules node tools/test-ocr-ui.js
 *
 * 왜 이 검사가 따로 있나
 *   tools/test-ocr.js 는 서버가 사진을 어떻게 다루는지를 HTTP 로 봅니다.
 *   화면은 한 번도 안 봅니다. 그래서 "서버는 잘 읽는데 쓰는 사람은 판독
 *   버튼을 한 번도 못 보는" 상태로도 통과합니다.
 *
 *   실제로 그랬습니다. 앱을 미리보기 링크로 열면 서버가 없어서 판독이
 *   꺼지는데, 화면은 "자동 판독은 꺼져 있습니다 · 설정에서 켤 수
 *   있습니다" 한 줄만 보여 줬습니다. 설정에 들어가도 켤 스위치가
 *   없었습니다 — 서버가 없으니까요. 쓰는 사람은 이 앱에 자동 판독이
 *   없다고 결론을 냈고, 그게 맞는 결론이었습니다. 그 사람이 본 화면에는
 *   정말 없었으니까요.
 *
 *   그래서 여기서는 진짜 브라우저로 세 상태를 다 지나갑니다:
 *     서버 없음 → 로그인 안 함 → 꺼 둠 → 켬 → 판독 → 검수 화면에 숫자
 *
 * 모델은 가짜입니다. 보려는 것은 모델의 정확도가 아니라, 사진이 화면에서
 * 출발해 서버를 거쳐 숫자로 돌아오는 길이 이어져 있는가입니다.
 * ========================================================================== */
'use strict';
const { spawn } = require('node:child_process');
const http = require('node:http');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { chromium } = require(process.env.NODE_PATH
  ? path.join(process.env.NODE_PATH, 'playwright')
  : 'playwright');

const PORT = 8900 + Math.floor(Math.random() * 200);
const FAKE_PORT = PORT + 1;
const PAIR = 'ocr-ui-pair';
const DB = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'mybody-ocrui-')), 'test.db');
const BASE = `http://localhost:${PORT}`;
const CHROME = process.env.CHROME_PATH || '/opt/pw-browsers/chromium-1194/chrome-linux/chrome';

let pass = 0, fail = 0;
const ok = (n, c, d) => {
  if (c) { pass++; console.log('  ✓', n); }
  else { fail++; console.log('  ✗', n, d === undefined ? '' : JSON.stringify(d).slice(0, 200)); }
};

/* --- 가짜 모델 --------------------------------------------------------- */
/* 오너의 실제 결과지 값을 돌려줍니다 — 검산이 통과하는 조합이라
   "판독은 됐는데 검산에서 다 빨간불" 로 헷갈리지 않습니다. */
const SHEET = {
  weightKg: 86.7, smmKg: 37.9, bfmKg: 20.0, pbfPct: 23.1,
  ffmKg: 66.7, bmi: 24.8, tbwL: 48.7, proteinKg: 13.3, mineralKg: 4.70,
  measuredAt: '2026-09-19T11:09:00+09:00', notInBody: false
};
let sawRequest = null;
const fake = http.createServer((req, res) => {
  let body = '';
  req.on('data', c => { body += c; });
  req.on('end', () => {
    try { sawRequest = JSON.parse(body); } catch { sawRequest = null; }
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end(JSON.stringify({
      content: [{ type: 'tool_use', name: 'record_sheet', input: SHEET }],
      usage: { input_tokens: 1200, output_tokens: 80 }
    }));
  });
});

/* --- 결과지 사진 한 장 ---------------------------------------------------
   내용은 중요하지 않습니다(모델이 가짜라서). 다만 진짜 JPEG 이어야
   photo.js 의 캔버스 축소가 지나갑니다. 1×1 짜리 유효한 JPEG 입니다. */
const JPEG_1PX = Buffer.from(
  '/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0a' +
  'HBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/wAALCAABAAEBAREA/8QAFAABAAAAAAAA' +
  'AAAAAAAAAAAACf/EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAD8AKp//2Q==', 'base64');

async function waitUp(url, ms = 10000) {
  const until = Date.now() + ms;
  while (Date.now() < until) {
    try { if ((await fetch(url)).ok) return true; } catch {}
    await new Promise(r => setTimeout(r, 120));
  }
  throw new Error('서버가 뜨지 않습니다: ' + url);
}

async function main() {
  const browser = await chromium.launch({ executablePath: CHROME });
  const ctx = await browser.newContext({ viewport: { width: 420, height: 900 } });
  const page = await ctx.newPage();
  const errs = [];
  page.on('pageerror', e => errs.push(String(e.message).slice(0, 200)));
  page.on('console', m => { if (m.type() === 'error') errs.push('console: ' + m.text().slice(0, 200)); });
  await page.goto(BASE + '/', { waitUntil: 'load' });
  await page.waitForTimeout(500);

  const text = () => page.evaluate(() => (document.getElementById('main').innerText || ''));
  const seen = uid => page.locator(`[data-uid="${uid}"]`).count().then(n => n > 0);
  const go = s => page.evaluate(x => window.MB_APP.go(x), s).then(() => page.waitForTimeout(250));

  /* --- 1. 서버가 없을 때 ------------------------------------------------- */
  console.log('\n[1] 서버 주소가 없을 때 — 미리보기로 열었을 때의 화면');
  await page.evaluate(() => { localStorage.clear(); });
  await page.reload({ waitUntil: 'load' });
  await page.waitForTimeout(400);
  await page.evaluate(() => window.MB_SYNC.configure(null));
  await go('P03');
  /* 주소가 아예 없는 경우와, 주소는 있는데 우리 서버가 아닌 경우는
     사용자에게 같은 상황입니다 — 미리보기 링크가 후자입니다. 둘 다 봅니다. */
  ok('자동 판독 카드가 보인다', await seen('P03-C08'));
  {
    const t = await text();
    ok('"서버가 없다"고 말한다', /서버가 없습니다/.test(t), t.slice(0, 200));
    ok('손으로 적는 길을 같이 알려준다', /옮겨 적으시면|직접 입력/.test(t));
  }
  ok('서버 주소를 넣을 길이 있다', await seen('P03-B15'));

  /* 주소는 적혀 있는데 그 주소에 우리 서버가 없을 때 (= 미리보기 링크).
     예전엔 defaultBase() 가 location.origin 을 잡아서 "서버가 있다" 고
     믿고 "로그인하면 켤 수 있습니다" 라고 했습니다. 눌러도 아무 데도
     안 닿습니다. */
  console.log('\n[1-2] 주소는 있는데 우리 서버가 아닐 때');
  await page.evaluate(() => window.MB_SYNC.configure('http://127.0.0.1:9931'));
  await page.waitForTimeout(600);
  await go('P02'); await go('P03');
  ok('닿지 않는다는 것을 안다',
     (await page.evaluate(() => window.MB_SYNC.status().reachable)) === false);
  ok('"서버가 없다"고 말한다', /서버가 없습니다/.test(await text()));

  /* 정적 호스트에 올렸을 때 — 웹서버는 있는데 우리 API 가 없는 경우.
     연결 자체가 안 되는 경우(서버가 꺼짐)와는 할 일이 다릅니다:
     여기서는 주소를 넣어야 하고, 저기서는 주소를 그대로 둬야 합니다.
     둘을 같은 말로 다루면 한쪽은 틀린 안내를 받습니다 — 그리고
     "주소를 바꾸세요" 는 브라우저가 주소마다 따로 저장하는 탓에
     그동안의 기록을 날립니다. */
  console.log('\n[1-3] 웹서버는 있는데 우리 API 가 아닐 때');
  {
    const other = require('node:http').createServer((q, r) => { r.writeHead(200); r.end('hello'); });
    await new Promise(r => other.listen(0, '127.0.0.1', r));
    const op = other.address().port;
    await page.evaluate(b => window.MB_SYNC.configure(b), 'http://127.0.0.1:' + op);
    await page.waitForTimeout(700);
    const kind = await page.evaluate(() => window.MB_SYNC.status().serverKind);
    /* 다른 출처의 서버가 CORS 머리글을 안 붙이면 브라우저가 응답을
       통째로 막아서, "꺼짐" 과 구분할 방법이 아예 없습니다. 그래서
       'down' 이 나오는 게 맞습니다 — 대신 그 경우 ownServer 가 false 라
       "주소가 틀렸거나 서버가 없습니다" 쪽 안내로 갑니다. 그게 맞는
       안내입니다. 진짜로 갈라야 하는 것은 같은 출처일 때이고,
       그건 test-release 가 정적 호스트로 확인합니다. */
    ok('남의 출처는 구분할 수 없고, 그때는 꺼짐으로 본다', kind === 'down', kind);
    await go('P02'); await go('P03');
    ok('주소를 넣으라고 한다', await seen('P03-B15'));
    await new Promise(r => other.close(r));

    /* 연결 자체가 안 되는 경우 */
    await page.evaluate(() => window.MB_SYNC.configure('http://127.0.0.1:9931'));
    await page.waitForTimeout(700);
    ok('연결이 안 되면 꺼진 것으로 본다',
       (await page.evaluate(() => window.MB_SYNC.status().serverKind)) === 'down');
  }

  /* --- 2. 서버는 있는데 로그인 안 했을 때 -------------------------------- */
  console.log('\n[2] 로그인 전');
  await page.evaluate(b => window.MB_SYNC.configure(b), BASE);
  await page.waitForTimeout(600);
  ok('진짜 서버는 닿는 것으로 본다',
     (await page.evaluate(() => window.MB_SYNC.status().reachable)) === true);
  await go('P02'); await go('P03');
  ok('"로그인하면 켤 수 있다"고 말한다', /로그인하면/.test(await text()));
  ok('바로 로그인할 길이 있다', await seen('P03-B16'));

  /* --- 3. 로그인은 했는데 꺼 둔 상태 ------------------------------------- */
  console.log('\n[3] 로그인 후 — 아직 꺼져 있음');
  await page.evaluate(p => window.MB_SYNC.signUp({
    handle: 'ocruser', password: 'ocr-password-1', displayName: '판독', pairSecret: p,
    healthConsent: true
  }), PAIR);
  await page.waitForTimeout(500);
  await go('P02'); await go('P03');
  ok('여기서 바로 켤 수 있다', await seen('P03-B17'));

  /* 켤 때 국외 이전을 알리는가 — 법이 요구하는 다섯 가지 */
  await page.click('[data-uid="P03-B17"]');
  await page.waitForTimeout(250);
  ok('켜기 전에 동의 창이 뜬다', await seen('M46'));
  {
    const m = await page.evaluate(() => document.querySelector('[data-uid="M46"]').innerText);
    ok('어디로 가는지 (국가)', /미국/.test(m));
    ok('받는 곳과 연락처', /Anthropic/.test(m) && /privacy@anthropic\.com/.test(m));
    ok('서버가 사진을 저장하지 않는다는 사실', /저장하지 않|메모리에서 중계/.test(m));
    ok('거부해도 앱을 쓸 수 있다는 사실', /직접 입력/.test(m));
  }
  await page.click('[data-uid="M46"] .modal__actions .btn--primary');
  await page.waitForTimeout(400);
  ok('켜진다', await page.evaluate(() => window.MB_SYNC.canOcr()));

  /* --- 4. 사진을 올리고 실제로 판독 -------------------------------------- */
  console.log('\n[4] 사진 → 서버 → 숫자  ← 핵심');
  await go('P02'); await go('P03');
  await page.setInputFiles('[data-uid="P03-F01"]', {
    name: 'inbody.jpg', mimeType: 'image/jpeg', buffer: JPEG_1PX
  });
  await page.waitForTimeout(900);
  ok('사진이 화면에 붙는다', await seen('P03-C05'));
  ok('판독 버튼이 사진 바로 아래 있다', await seen('P03-B13'));

  await page.click('[data-uid="P03-B13"]');
  await page.waitForTimeout(2500);

  ok('서버가 모델을 실제로 불렀다', !!sawRequest);
  ok('보낸 것이 사진이다',
     !!sawRequest && JSON.stringify(sawRequest).includes('base64'));

  const after = await page.evaluate(() => ({
    screen: window.MB_APP.current,
    w: (document.querySelector('[data-uid="P04-F01"]') || {}).value,
    s: (document.querySelector('[data-uid="P04-F02"]') || {}).value,
    b: (document.querySelector('[data-uid="P04-F03"]') || {}).value,
    txt: (document.getElementById('main').innerText || '').slice(0, 400)
  }));
  ok('검수 화면으로 넘어간다', after.screen === 'P04', after.screen);
  ok('체중이 채워져 있다', String(after.w).indexOf('86.7') === 0, after.w);
  ok('골격근량이 채워져 있다', String(after.s).indexOf('37.9') === 0, after.s);
  ok('체지방량이 채워져 있다', String(after.b).indexOf('20') === 0, after.b);
  ok('검산 결과를 같이 보여 준다', /검산|검산됨|미검산/.test(after.txt), after.txt.slice(0, 160));

  /* --- 5. 끄면 정말 안 나가는가 ------------------------------------------ */
  console.log('\n[5] 끄면 그 뒤로 한 장도 안 나간다');
  sawRequest = null;
  await page.evaluate(() => window.MB_SYNC.setOcr(false));
  await go('P02'); await go('P03');
  ok('다시 꺼짐 안내로 돌아온다', await seen('P03-C08'));
  ok('판독 버튼이 사라진다', !(await seen('P03-B13')));
  ok('모델을 안 부른다', sawRequest === null);

  console.log('\n[6] JS 오류');
  /* 일부러 닿지 않는 주소를 물어봤습니다(위 [1-2]). 브라우저는 그것도
     콘솔 오류로 찍습니다 — 예상한 것은 빼고 셉니다. */
  /* 일부러 닿지 않는 주소와 CORS 를 안 여는 남의 서버를 물어봤습니다
     (위 [1-2]·[1-3]). 브라우저는 그것도 콘솔 오류로 찍습니다. */
  const EXPECTED = /status of (400|401|429)|ERR_CONNECTION_REFUSED|ERR_UNSAFE_PORT|Failed to load resource|blocked by CORS policy/;
  const real = [...new Set(errs)].filter(e => !EXPECTED.test(e));
  ok('예상 못 한 오류 0건', real.length === 0, real.slice(0, 3));

  await browser.close();
}

const srv = spawn(process.execPath, [path.join(__dirname, '..', 'server', 'server.js')], {
  env: { ...process.env, PORT: String(PORT), DB, PAIR_SECRET: PAIR,
         ANTHROPIC_API_KEY: 'test-key-not-real',
         OCR_API_URL: `http://localhost:${FAKE_PORT}/v1/messages` },
  stdio: 'ignore'
});
process.on('exit', () => { srv.kill(); fake.close(); });

fake.listen(FAKE_PORT, () => {
  waitUp(BASE + '/health').then(main).then(() => {
    console.log(`\n통과 ${pass} / 실패 ${fail}`);
    srv.kill(); fake.close();
    process.exit(fail ? 1 : 0);
  }).catch(e => { console.error(e); srv.kill(); fake.close(); process.exit(1); });
});
