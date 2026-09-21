/* =============================================================================
 * tools/test-signup-ui.js — 가입 화면이 이 서버의 실제 규칙을 말하는가
 *
 *   NODE_PATH=/opt/node22/lib/node_modules node tools/test-signup-ui.js
 *
 * 주인이 "가입코드 없애" 라고 해서 서버 쪽은 열었습니다. 그런데 화면이
 * 그걸 모르면, 친구는 **받은 적 없는 코드를 넣으라는 빈칸** 앞에서
 * 멈춥니다. 서버가 열렸다는 사실이 화면까지 닿는지를 여기서 봅니다.
 *
 * 반대쪽도 같이 봅니다 — 코드가 필요한 서버인데 칸을 안 그리면 친구는
 * 코드를 넣을 데가 없어 영영 가입을 못 합니다. 그래서 "모르겠으면
 * 보여 준다" 가 기본이어야 합니다 (아직 /health 를 못 받은 상태).
 *
 * 진짜 서버는 안 띄웁니다 — 여기서 확인할 것은 앱의 판단이고,
 * "열린 서버가 실제로 코드 없이 계정을 만들어 주는가" 는
 * test-selfhost.js [2-3] 이 진짜 서버로 봅니다.
 * ========================================================================== */
'use strict';
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const { chromium } = require(process.env.NODE_PATH
  ? path.join(process.env.NODE_PATH, 'playwright') : 'playwright');

const ROOT = path.join(__dirname, '..', 'prototype');
const PORT = 9300 + Math.floor(Math.random() * 200);
const CHROME = process.env.CHROME_PATH || '/opt/pw-browsers/chromium-1194/chrome-linux/chrome';
const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css',
               '.json': 'application/json', '.svg': 'image/svg+xml',
               '.webmanifest': 'application/manifest+json' };

/* /health 의 대답을 시험이 바꿔 가며 씁니다.
   null 이면 아예 답하지 않습니다 (서버가 없는 것과 같은 상태). */
let health = null;

const server = http.createServer((req, res) => {
  let p = decodeURIComponent(req.url.split('?')[0]);
  if (p === '/health') {
    if (health === null) { res.writeHead(404); return res.end('no'); }
    res.writeHead(200, { 'Content-Type': 'application/json' });
    return res.end(JSON.stringify(health));
  }
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
  else { fail++; console.log('  ✗', n, d === undefined ? '' : JSON.stringify(d).slice(0, 300)); }
};

(async () => {
  await new Promise(r => server.listen(PORT, r));
  const browser = await chromium.launch({ executablePath: CHROME });
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 } });
  const page = await ctx.newPage();
  const errs = [];
  page.on('pageerror', e => errs.push('PAGEERROR: ' + e.message.slice(0, 200)));

  const u = s => `[data-uid="${s}"]`;

  /** 앱을 새로 열고 계정 화면까지 갑니다. probe() 가 /health 를 한 번
   *  두드릴 시간을 줍니다 — 그 답이 이 시험의 전부입니다. */
  const open = async () => {
    await page.goto(`http://localhost:${PORT}/`, { waitUntil: 'load' });
    await page.waitForTimeout(400);
    await page.addStyleTag({ content: '.uid-dock{display:none!important}' });
    await page.evaluate(() => { window.MB_STORE.seed(); window.MB_APP.go('P14'); });
    await page.waitForTimeout(400);
  };
  /** 가입(처음이에요) 화면까지 */
  const toSignUp = async () => {
    await page.locator(u('P14-B01')).click();
    await page.waitForTimeout(250);
    await page.locator(u('M29-B11')).click();          // 처음이에요
    await page.waitForTimeout(250);
  };
  const closeModal = () => page.evaluate(() => {
    document.querySelectorAll('.modal, .sheet').forEach(e => e.remove());
    document.querySelectorAll('.scrim, .backdrop').forEach(e => e.remove());
  });

  console.log('\n[1] 코드가 필요한 서버 — 칸이 있어야 한다');
  health = { ok: true, openSignup: false };
  await open();
  ok('서버를 우리 것으로 본다',
     await page.evaluate(() => window.MB_SYNC.status().serverKind) === 'ours');
  ok('가입에 코드가 필요하다고 안다',
     await page.evaluate(() => window.MB_SYNC.status().openSignup) === false);
  await toSignUp();
  ok('가입 코드 칸이 있다', await page.locator(u('M29-F05')).count() === 1);
  {
    const t = await page.locator(u('M29')).innerText();
    ok('공개 가입이 아니라고 말한다', t.includes('공개 가입 서비스가 아닙니다'), t.slice(0, 300));
  }
  await closeModal();
  {
    const t = await page.locator(u('P14-C02')).innerText();
    ok('계정 안내도 코드가 필요하다고 말한다', t.includes('가입 코드가 필요하고'), t);
  }

  console.log('\n[2] 열어 둔 서버 — 칸이 없어야 한다');
  health = { ok: true, openSignup: true };
  await open();
  ok('가입이 열렸다고 안다',
     await page.evaluate(() => window.MB_SYNC.status().openSignup) === true);
  await toSignUp();
  ok('가입 코드 칸이 없다', await page.locator(u('M29-F05')).count() === 0);
  {
    const t = await page.locator(u('M29')).innerText();
    ok('누구나 만들 수 있다고 말한다', t.includes('누구나 계정을 만들 수 있습니다'), t.slice(0, 300));
    ok('없는 코드 이야기를 안 한다', !t.includes('주인이 알려준 코드'), t.slice(0, 300));
  }
  /* 칸이 없어도 가입이 **끝까지 가는가.** 칸을 지우면서 pair.value 를
     그대로 읽으면 여기서 TypeError 로 죽습니다 — 화면은 멀쩡해 보이고
     "계속" 을 누르는 순간에만 터지는 자리라 눈으로는 못 봅니다. */
  await page.locator(u('M29-F01')).fill('opentest');
  await page.locator(u('M29-F02')).fill('open-password-1');
  await page.locator(u('M29-F03')).fill('open-password-1');
  await page.locator(u('M29-B14')).click();            // 동의합니다
  await page.waitForTimeout(150);
  await page.locator(u('M29-B02')).click();            // 계속
  await page.waitForTimeout(600);
  ok('"계속" 을 눌러도 터지지 않는다 (없는 칸을 읽지 않는다)',
     !errs.some(e => /pair|null|undefined/i.test(e)), errs.slice(0, 3));
  await closeModal();
  {
    const t = await page.locator(u('P14-C02')).innerText();
    ok('계정 안내도 누구나 할 수 있다고 말한다', t.includes('가입은 누구나 할 수 있고'), t);
  }

  console.log('\n[3] 아직 모를 때 — 있는 칸을 빼먹지 않는다');
  health = null;                                        // /health 가 404
  await open();
  ok('안 물어봤으면 null 로 둔다 (false 로 단정하지 않는다)',
     await page.evaluate(() => window.MB_SYNC.status().openSignup) === null);
  await toSignUp();
  ok('모를 때는 가입 코드 칸을 보여준다', await page.locator(u('M29-F05')).count() === 1);

  console.log('\n[4] 서버를 바꾸면 그 서버에 다시 물어본다');
  {
    /* 열린 서버를 본 뒤 다른 주소로 바꿨는데 "열려 있다" 가 남아 있으면,
       코드가 필요한 서버에서 칸이 사라집니다 — 친구는 코드를 넣을 데가
       없습니다. 주소가 바뀌면 그 답은 버려야 합니다. */
    health = { ok: true, openSignup: true };
    await open();
    const after = await page.evaluate(() => {
      window.MB_SYNC.configure('http://127.0.0.1:9');   // 아무도 없는 주소
      return window.MB_SYNC.status().openSignup;
    });
    ok('주소를 바꾸면 옛 서버의 답을 버린다', after === null, after);
  }

  console.log('\n[5] 화면이 콘솔에 오류를 안 낸다');
  ok('페이지 오류 없음', errs.length === 0, errs.slice(0, 3));

  console.log(`\n통과 ${pass} / 실패 ${fail}`);
  await browser.close();
  server.close();
  process.exit(fail ? 1 : 0);
})().catch(e => { console.error(e); process.exit(1); });
