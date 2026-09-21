/* =============================================================================
 * tools/test-gate-ui.js — "웹 링크로 들어오면 앱 받기부터" 가 실제로 되는가
 *
 *   NODE_PATH=/opt/node22/lib/node_modules node tools/test-gate-ui.js
 *
 * 주인 요청: "웹 링크 들어가면 앱 다운로드 버튼만 나오게 하고,
 *             안드로이드, 아이폰, 아이패드 모두에서 작동하게 해"
 *
 * 이 화면에서 제일 위험한 실수는 **문을 하나만 만들고 잠그는 것**입니다.
 * 설치가 아예 막힌 경우가 실제로 많습니다 — 파이어폭스, 아이폰의 크롬,
 * 카카오톡 안 브라우저, 그리고 지금 쓰는 임시 터널 주소. 그때 설치
 * 버튼만 보여 주면 친구는 들어올 길이 없습니다.
 *
 * 그래서 여기서 보는 것은 두 가지입니다.
 *   (가) 기기마다 **맞는** 안내가 나오는가 (아이패드를 맥으로 읽지 않는가)
 *   (나) 어떤 경우에도 **들어올 길이 있는가**
 * ========================================================================== */
'use strict';
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const { chromium } = require(process.env.NODE_PATH
  ? path.join(process.env.NODE_PATH, 'playwright') : 'playwright');

const ROOT = path.join(__dirname, '..', 'prototype');
const PORT = 9700 + Math.floor(Math.random() * 200);
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
  else { fail++; console.log('  ✗', n, d === undefined ? '' : JSON.stringify(d).slice(0, 300)); }
};

/* 실제 기기들의 UA. 아이패드가 왜 따로 있냐면 — iPadOS 13 부터
   UA 가 "Macintosh" 라서, 문자열만 보면 데스크톱으로 읽힙니다.
   그러면 "주소창의 설치 아이콘을 누르세요" 가 나오는데 사파리에는
   그런 아이콘이 없습니다. 손가락 개수로 갈라야 합니다. */
const UAS = {
  android: 'Mozilla/5.0 (Linux; Android 14; SM-S911N) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Mobile Safari/537.36',
  iphone:  'Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Mobile/15E148 Safari/604.1',
  ipadOld: 'Mozilla/5.0 (iPad; CPU OS 18_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Mobile/15E148 Safari/604.1',
  ipadNew: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Safari/605.1.15',
  iosChrome: 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/140.0.0.0 Mobile/15E148 Safari/604.1',
  kakao:   'Mozilla/5.0 (Linux; Android 14; SM-S911N) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Mobile Safari/537.36 KAKAOTALK 10.5.0',
  firefox: 'Mozilla/5.0 (Android 14; Mobile; rv:130.0) Gecko/130.0 Firefox/130.0',
  desktop: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36'
};

(async () => {
  await new Promise(r => server.listen(PORT, r));
  const browser = await chromium.launch({ executablePath: CHROME });
  const errs = [];

  /** 그 기기로 주소를 열고 화면 글자를 돌려줍니다. */
  async function open(kind, opts) {
    opts = opts || {};
    const ctx = await browser.newContext({
      userAgent: UAS[kind],
      viewport: /desktop|ipad/.test(kind) ? { width: 900, height: 900 } : { width: 390, height: 844 },
      hasTouch: kind !== 'desktop',
      isMobile: !/desktop|ipadNew/.test(kind)
    });
    const page = await ctx.newPage();
    page.on('pageerror', e => errs.push(kind + ': ' + e.message.slice(0, 160)));
    /* iPadOS 13+ 의 데스크톱 UA 를 흉내내려면 손가락 개수까지 속여야
       합니다 — 그게 이 갈림의 유일한 단서니까요. */
    if (kind === 'ipadNew') {
      await page.addInitScript(() => {
        Object.defineProperty(navigator, 'maxTouchPoints', { get: () => 5 });
      });
    }
    await page.goto(`http://localhost:${PORT}/${opts.query || ''}`, { waitUntil: 'load' });
    await page.waitForTimeout(500);
    const text = await page.evaluate(() => document.body.innerText || '');
    const uids = await page.evaluate(() =>
      [...document.querySelectorAll('[data-uid]')].map(e => e.getAttribute('data-uid')));
    return { page, ctx, text, uids };
  }

  console.log('\n[1] 웹 주소로 들어오면 앱 받기부터 나온다');
  {
    const r = await open('android');
    ok('앱 받기 화면이 뜬다', r.uids.indexOf('P22') >= 0, r.uids.slice(0, 8));
    ok('앱 화면(탭 막대)은 안 나온다', r.uids.indexOf('P00-C01') < 0, r.uids.slice(0, 8));
    ok('"앱으로 받기" 라고 말한다', /앱으로 받기/.test(r.text), r.text.slice(0, 200));
    ok('깔면 뭐가 좋은지 적는다', /아이콘이 생깁니다/.test(r.text), r.text.slice(0, 400));
    await r.ctx.close();
  }

  console.log('\n[2] 기기마다 맞는 방법을 말한다');
  {
    const a = await open('android');
    ok('안드로이드 — 메뉴(⋮)를 말한다', /메뉴\(⋮\)/.test(a.text), a.text.slice(0, 500));
    ok('안드로이드 — 공유 버튼 이야기는 안 한다', !/공유 버튼/.test(a.text));
    await a.ctx.close();

    const i = await open('iphone');
    ok('아이폰 — 공유 버튼을 말한다', /공유 버튼/.test(i.text), i.text.slice(0, 500));
    ok('아이폰 — "아래쪽" 이라고 말한다', /아래쪽의 공유/.test(i.text), i.text.slice(0, 500));
    ok('아이폰 — 홈 화면에 추가', /홈 화면에 추가/.test(i.text));
    await i.ctx.close();

    const p1 = await open('ipadOld');
    ok('아이패드(옛 UA) — "위쪽" 이라고 말한다', /위쪽의 공유/.test(p1.text), p1.text.slice(0, 500));
    await p1.ctx.close();

    /* 여기가 이 시험의 핵심입니다. iPadOS 13+ 는 UA 가 Macintosh 라
       문자열만 보면 데스크톱입니다. 그러면 사파리에 없는 "주소창의
       설치 아이콘" 을 누르라고 하게 됩니다. */
    const p2 = await open('ipadNew');
    ok('아이패드(데스크톱 UA) — 맥으로 안 읽는다',
       !/주소창 오른쪽의 설치 아이콘/.test(p2.text), p2.text.slice(0, 500));
    ok('아이패드(데스크톱 UA) — 공유 버튼을 말한다',
       /위쪽의 공유/.test(p2.text), p2.text.slice(0, 500));
    await p2.ctx.close();

    const d = await open('desktop');
    ok('데스크톱 — 주소창 아이콘을 말한다',
       /주소창 오른쪽의 설치 아이콘/.test(d.text), d.text.slice(0, 500));
    await d.ctx.close();
  }

  console.log('\n[3] 못 까는 경우에도 들어올 길이 있다  ← 제일 중요');
  {
    /* 문을 하나만 만들고 잠가 두면, 못 까는 사람은 앱을 아예 못 씁니다.
       아래 넷은 전부 "기다려도 안 되는" 경우입니다. */
    for (const [kind, label, expect] of [
      ['iosChrome', '아이폰의 크롬', /사파리/],
      ['kakao', '카카오톡 안 브라우저', /다른 브라우저로 열기/],
      ['firefox', '파이어폭스', /파이어폭스는 앱 설치를 지원하지 않습니다/]
    ]) {
      const r = await open(kind);
      ok(label + ' — 왜 못 까는지 말한다', expect.test(r.text), r.text.slice(0, 400));
      ok(label + ' — 그래도 쓸 수 있는 버튼이 있다',
         r.uids.indexOf('P22-B02') >= 0, r.uids);
      await r.ctx.close();
    }

    const a = await open('android');
    ok('깔 수 있는 경우에도 브라우저로 쓰는 길은 남긴다',
       a.uids.indexOf('P22-B02') >= 0, a.uids);
    await a.ctx.close();
  }

  console.log('\n[4] "브라우저에서 바로 쓰기" 를 누르면 앱이 뜨고, 다시 안 묻는다');
  {
    const r = await open('android');
    await r.page.click('[data-uid="P22-B02"]');
    await r.page.waitForTimeout(500);
    const uids = await r.page.evaluate(() =>
      [...document.querySelectorAll('[data-uid]')].map(e => e.getAttribute('data-uid')));
    ok('앱 화면으로 넘어간다', uids.indexOf('P00-C01') >= 0, uids.slice(0, 8));
    ok('앱 받기 화면은 사라진다', uids.indexOf('P22') < 0, uids.slice(0, 8));

    /* 한 번 고른 사람에게 같은 벽을 다시 세우면 그건 벽이 아니라 괴롭힘입니다. */
    await r.page.reload({ waitUntil: 'load' });
    await r.page.waitForTimeout(500);
    const again = await r.page.evaluate(() =>
      [...document.querySelectorAll('[data-uid]')].map(e => e.getAttribute('data-uid')));
    ok('새로고침해도 다시 안 묻는다', again.indexOf('P22') < 0, again.slice(0, 8));
    await r.ctx.close();
  }

  console.log('\n[5] 깔고 나서 아이콘으로 열면 관문을 지나간다');
  {
    /* 매니페스트의 start_url 이 ?app=1 입니다 — 홈 화면 아이콘으로
       열면 이 주소로 들어옵니다. 이게 안 되면 앱을 깔아 놓고도 매번
       "앱 받기" 를 보게 됩니다. */
    const manifest = JSON.parse(fs.readFileSync(path.join(ROOT, 'manifest.webmanifest'), 'utf8'));
    ok('매니페스트의 start_url 에 표식이 있다',
       /\?app=1/.test(manifest.start_url), manifest.start_url);

    const r = await open('android', { query: '?app=1' });
    ok('그 주소로 열면 바로 앱이다', r.uids.indexOf('P00-C01') >= 0, r.uids.slice(0, 8));
    ok('앱 받기 화면을 안 거친다', r.uids.indexOf('P22') < 0, r.uids.slice(0, 8));
    await r.ctx.close();
  }

  console.log('\n[6] 홈 화면에서 실행 중이면(standalone) 관문이 없다');
  {
    const ctx = await browser.newContext({ userAgent: UAS['iphone'],
      viewport: { width: 390, height: 844 }, hasTouch: true, isMobile: true });
    const page = await ctx.newPage();
    page.on('pageerror', e => errs.push('standalone: ' + e.message.slice(0, 160)));
    /* 아이폰의 홈 화면 앱은 navigator.standalone 이 true 입니다. */
    await page.addInitScript(() => {
      Object.defineProperty(navigator, 'standalone', { get: () => true });
    });
    await page.goto(`http://localhost:${PORT}/`, { waitUntil: 'load' });
    await page.waitForTimeout(500);
    const uids = await page.evaluate(() =>
      [...document.querySelectorAll('[data-uid]')].map(e => e.getAttribute('data-uid')));
    ok('아이폰 홈 화면 앱은 바로 앱이다', uids.indexOf('P00-C01') >= 0, uids.slice(0, 8));
    ok('관문을 안 거친다', uids.indexOf('P22') < 0, uids.slice(0, 8));
    await ctx.close();
  }

  console.log('\n[7] 화면이 콘솔에 오류를 안 낸다');
  ok('페이지 오류 없음', errs.length === 0, errs.slice(0, 3));

  console.log(`\n통과 ${pass} / 실패 ${fail}`);
  await browser.close();
  server.close();
  process.exit(fail ? 1 : 0);
})().catch(e => { console.error(e); process.exit(1); });
