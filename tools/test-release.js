/* =============================================================================
 * tools/test-release.js — 배포 빌드가 정말 배포 빌드인가
 *
 *   node tools/build-release.js && NODE_PATH=/opt/node22/lib/node_modules node tools/test-release.js
 *
 * 빌드 스크립트가 "통과" 라고 말하는 것과, 브라우저에서 실제로 그렇게
 * 도는 것은 다른 이야기입니다. 플래그를 바꿔 놓고 화면 어딘가에서 그
 * 플래그를 안 물어보면 개발용 UI 가 그대로 남습니다.
 *
 * 그래서 진짜 브라우저로 열어서 확인합니다:
 *   - 고유번호 배지가 하나도 안 보이는가
 *   - 개발 전용 버튼이 DOM 에 없는가 (숨은 게 아니라 아예 없어야)
 *   - i · f 키가 아무 일도 안 하는가
 *   - #P13 으로 들어가도 ID 목록이 안 뜨는가
 *   - 매니페스트와 아이콘이 실제로 받아지는가
 *   - 서비스워커가 등록되고, 네트워크를 끊어도 앱이 열리는가
 *   - 그러면서 앱 자체는 멀쩡히 도는가 (이게 제일 중요합니다)
 * ========================================================================== */
'use strict';
const { chromium } = require('playwright');
const http = require('http');
const fs = require('fs');
const path = require('path');

const DIR = process.env.OUT || path.join(__dirname, '..', 'release');
const PORT = Number(process.env.PORT || 8761);
const CHROME = process.env.CHROME_PATH || '/opt/pw-browsers/chromium-1194/chrome-linux/chrome';

const MIME = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8',
               '.css': 'text/css; charset=utf-8', '.json': 'application/json',
               '.webmanifest': 'application/manifest+json', '.png': 'image/png', '.svg': 'image/svg+xml' };
let offline = false;
const server = http.createServer((req, res) => {
  if (offline) { req.destroy(); return; }
  let p = decodeURIComponent(req.url.split('?')[0]);
  if (p === '/') p = '/index.html';
  const f = path.join(DIR, p);
  if (!f.startsWith(DIR) || !fs.existsSync(f) || fs.statSync(f).isDirectory()) {
    res.writeHead(404); return res.end('404');
  }
  res.writeHead(200, { 'Content-Type': MIME[path.extname(f)] || 'application/octet-stream' });
  res.end(fs.readFileSync(f));
});

let pass = 0, fail = 0;
const ok = (n, c, d) => {
  if (c) { pass++; console.log('  ✓', n); }
  else { fail++; console.log('  ✗', n, d === undefined ? '' : JSON.stringify(d).slice(0, 200)); }
};

/* 개발 빌드에만 있어야 하는 것들 */
const DEV_UIDS = ['P02-B02', 'P03-B03', 'P03-B09', 'P12-C05', 'P12-B07', 'P12-B08', 'P12-B09', 'P12-B10'];

(async () => {
  if (!fs.existsSync(DIR)) { console.error('release/ 가 없습니다. 먼저 node tools/build-release.js'); process.exit(1); }
  await new Promise(r => server.listen(PORT, r));
  const browser = await chromium.launch({ executablePath: CHROME });
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 } });
  const page = await ctx.newPage();
  const errs = [];
  page.on('pageerror', e => errs.push(String(e.message).slice(0, 200)));
  page.on('console', m => { if (m.type() === 'error') errs.push('console: ' + m.text().slice(0, 200)); });

  await page.goto(`http://localhost:${PORT}/`, { waitUntil: 'load' });
  await page.waitForTimeout(600);

  console.log('\n[1] 빌드 플래그');
  const build = await page.evaluate(() => window.MB_BUILD);
  ok('release: true', build && build.release === true, build);
  ok('버전이 박혀 있다', build && build.version && build.version !== 'dev', build && build.version);
  ok('빌드 시각이 박혀 있다', !!(build && build.builtAt));

  console.log('\n[2] 고유번호 배지 — 쓰는 사람에게는 보이면 안 됩니다');
  await page.evaluate(() => { window.MB_STORE.seed(); window.MB_APP.go('P02'); });
  await page.waitForTimeout(500);
  const badges = await page.evaluate(() => {
    const all = [...document.querySelectorAll('.uid-badge')];
    const shown = all.filter(e => e.offsetParent !== null && getComputedStyle(e).display !== 'none');
    return { total: all.length, shown: shown.length, uidOff: document.body.classList.contains('uid-off') };
  });
  ok('화면에 보이는 배지 0개', badges.shown === 0, badges);
  ok('data-uid 속성은 남아 있다 (검증 도구가 씁니다)',
     (await page.evaluate(() => document.querySelectorAll('[data-uid]').length)) > 10);

  console.log('\n[3] 개발 전용 UI — 숨은 게 아니라 아예 없어야 합니다');
  for (const uid of DEV_UIDS) {
    const there = await page.evaluate(u => {
      // 이 버튼이 있을 만한 화면을 다 돌아봅니다
      return ['P02', 'P03', 'P12'].some(s => {
        window.MB_APP.go(s);
        return !!document.querySelector('[data-uid="' + u + '"]');
      });
    }, uid);
    ok(`${uid} 없음`, !there);
  }
  const p13 = await page.evaluate(() => (window.MB_APP.screenIds || []).includes('P13'));
  ok('P13 화면이 등록조차 안 됨', !p13);
  await page.goto(`http://localhost:${PORT}/#P13`, { waitUntil: 'load' });
  await page.waitForTimeout(500);
  ok('#P13 으로 들어와도 ID 목록이 아님',
     (await page.evaluate(() => window.MB_APP.current)) !== 'P13');

  console.log('\n[4] 개발 단축키');
  await page.evaluate(() => window.MB_APP.go('P02'));
  await page.waitForTimeout(300);
  await page.keyboard.press('i');
  await page.waitForTimeout(200);
  ok('i 키가 배지를 켜지 않는다',
     (await page.evaluate(() => [...document.querySelectorAll('.uid-badge')]
        .filter(e => e.offsetParent !== null).length)) === 0);
  await page.keyboard.press('f');
  await page.waitForTimeout(200);
  ok('f 키가 피드백 모드를 켜지 않는다',
     !(await page.evaluate(() => document.body.classList.contains('uid-feedback'))));

  console.log('\n[5] PWA');
  const mani = await page.evaluate(async () => {
    const l = document.querySelector('link[rel="manifest"]');
    if (!l) return null;
    const r = await fetch(l.href);
    return r.ok ? await r.json() : { httpError: r.status };
  });
  ok('매니페스트가 받아진다', mani && !mani.httpError, mani);
  ok('이름 · 시작주소 · 표시모드', mani && mani.name && mani.start_url && mani.display === 'standalone');
  ok('아이콘 3종 (maskable 포함)',
     mani && mani.icons && mani.icons.length >= 3 && mani.icons.some(i => i.purpose === 'maskable'));
  for (const i of (mani && mani.icons) || []) {
    const r = await page.evaluate(async s => (await fetch(s)).ok, i.src);
    ok(`아이콘 ${i.sizes}${i.purpose ? ' (' + i.purpose + ')' : ''} 실제로 있음`, r);
  }
  ok('apple-touch-icon',
     await page.evaluate(async () => {
       const l = document.querySelector('link[rel="apple-touch-icon"]');
       return !!l && (await fetch(l.href)).ok;
     }));
  ok('theme-color', await page.evaluate(() => !!document.querySelector('meta[name="theme-color"]')));

  console.log('\n[6] 서비스워커 · 오프라인');
  const reg = await page.evaluate(async () => {
    if (!('serviceWorker' in navigator)) return 'no-sw-api';
    const r = await navigator.serviceWorker.ready.catch(() => null);
    return r ? (r.active ? 'active' : 'registered') : 'none';
  });
  ok('서비스워커가 활성화된다', reg === 'active', reg);
  const cached = await page.evaluate(async () => {
    const keys = await caches.keys();
    if (!keys.length) return 0;
    const c = await caches.open(keys[0]);
    return (await c.keys()).length;
  });
  ok('껍데기가 캐시에 들어갔다', cached > 20, cached);

  offline = true;                        // 서버를 끊습니다
  const off = await ctx.newPage();
  const offErrs = [];
  off.on('pageerror', e => offErrs.push(String(e.message).slice(0, 160)));
  let opened = false, txt = '';
  try {
    await off.goto(`http://localhost:${PORT}/`, { waitUntil: 'load', timeout: 15000 });
    await off.waitForTimeout(900);
    txt = await off.evaluate(() => (document.getElementById('main') || {}).innerText || '');
    opened = txt.length > 30;
  } catch (e) { txt = 'THREW: ' + e.message.slice(0, 120); }
  ok('서버가 죽어도 앱이 열린다', opened, txt.slice(0, 120));
  ok('오프라인에서 JS 오류 없음', offErrs.length === 0, offErrs);
  offline = false;
  await off.close();

  console.log('\n[7] 배포 빌드에서도 앱이 멀쩡한가');
  const p2 = await ctx.newPage();
  const appErrs = [];
  p2.on('pageerror', e => appErrs.push(String(e.message).slice(0, 200)));
  p2.on('console', m => { if (m.type() === 'error') appErrs.push('console: ' + m.text().slice(0, 200)); });
  await p2.goto(`http://localhost:${PORT}/`, { waitUntil: 'load' });
  await p2.waitForTimeout(500);
  await p2.evaluate(() => { localStorage.clear(); window.MB_STORE.seed(); });
  await p2.reload({ waitUntil: 'load' });
  await p2.waitForTimeout(600);
  const screens = await p2.evaluate(() => window.MB_APP.screenIds);
  const empties = [];
  for (const s of screens) {
    await p2.evaluate(x => window.MB_APP.go(x), s);
    await p2.waitForTimeout(220);
    const n = await p2.evaluate(() => ((document.getElementById('main') || {}).innerText || '').trim().length);
    if (n < 30) empties.push(s + ':' + n);
  }
  ok(`화면 ${screens.length}개가 전부 내용을 그린다`, empties.length === 0, empties);
  ok('앱 전체에서 JS 오류 0건', appErrs.length === 0, appErrs.slice(0, 3));

  console.log(`\n통과 ${pass} / 실패 ${fail}`);
  await browser.close(); server.close();
  process.exit(fail ? 1 : 0);
})().catch(e => { console.error(e); server.close(); process.exit(1); });
