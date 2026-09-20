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
/* 포트를 0 으로 열면 커널이 빈 포트를 줍니다. 고정 포트를 쓰면
   검증 도구 두 개를 같이 돌릴 때 서로를 막습니다 — 실제로 막혔습니다. */
let PORT = Number(process.env.PORT || 0);
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
/* 배포본에 있으면 안 되는 것들.
 * P12-B05(시드 주입)는 한동안 이 목록에 없었고, 그래서 플래그를 안 건
 * 채로 배포본에 그대로 나갔습니다 — 누르면 쓰는 사람의 기록이 전부
 * 지워지고 이 앱을 만든 사람의 몸 숫자가 대신 들어갑니다.
 * 개발용 화면을 하나 만들면 이 목록에도 한 줄 더합니다. */
const DEV_UIDS = ['P01-B05', 'P02-B02', 'P03-B03', 'P03-B09', 'P18-B08',
                  'P12-C05', 'P12-B05', 'P12-B07', 'P12-B08', 'P12-B09', 'P12-B10',
                  /* 배지 크기 조절 — 배포본에는 배지가 없어서 움직여도
                     아무 일이 안 일어납니다. 고장 난 설정으로 보입니다. */
                  'P12-F02'];

(async () => {
  if (!fs.existsSync(DIR)) { console.error('release/ 가 없습니다. 먼저 node tools/build-release.js'); process.exit(1); }
  await new Promise(r => server.listen(PORT, r));
  PORT = server.address().port;
  const browser = await chromium.launch({ executablePath: CHROME });
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 } });
  const page = await ctx.newPage();
  const errs = [];
  page.on('pageerror', e => errs.push(String(e.message).slice(0, 200)));
  /* /health 404 는 예상한 것입니다 — 이 검사는 정적 호스트를 흉내 내고,
     앱은 켜질 때 그 주소에 우리 서버가 있는지 한 번 물어봅니다.
     없다는 답이 오는 것이 맞고, 화면은 그때 "서버가 없습니다" 라고
     말합니다. */
  const EXPECTED_404 = /health|Failed to load resource/;
  page.on('console', m => {
    if (m.type() === 'error' && !EXPECTED_404.test(m.text())) errs.push('console: ' + m.text().slice(0, 200));
  });

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
      return ['P01', 'P02', 'P03', 'P12', 'P18'].some(s => {
        window.MB_APP.go(s);
        return !!document.querySelector('[data-uid="' + u + '"]');
      });
    }, uid);
    ok(`${uid} 없음`, !there);
  }
  const gated = await page.evaluate(() => {
    const ids = window.MB_APP.screenIds || [];
    return { P13: ids.includes('P13'), P20: ids.includes('P20') };
  });
  ok('P13 (ID 목록) 이 등록조차 안 됨', !gated.P13);
  // P20 은 사진을 실제로 읽지 못합니다 — 지어낸 음식이 식단 기록에
  // 들어가면 칼로리·단백질 계산이 통째로 어긋납니다.
  ok('P20 (음식 사진) 이 등록조차 안 됨', !gated.P20);
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
  /* navigator.serviceWorker.ready 는 등록이 없으면 거부되지 않고 그냥
     영원히 안 끝납니다. .catch() 를 붙여도 소용없어서 검증이 통째로
     멈춰 있었습니다. 기다릴 시간을 정해 두고, 안 오면 "안 옴" 이라고
     말하게 합니다 — 검사가 멈추는 것과 실패하는 것은 다릅니다. */
  const reg = await page.evaluate(async () => {
    if (!('serviceWorker' in navigator)) return 'no-sw-api';
    const timeout = new Promise(r => setTimeout(() => r('timeout'), 10000));
    const got = await Promise.race([navigator.serviceWorker.ready, timeout]);
    if (got === 'timeout') {
      const regs = await navigator.serviceWorker.getRegistrations();
      return 'timeout(등록 ' + regs.length + '건)';
    }
    return got.active ? 'active' : 'registered';
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
  p2.on('console', m => {
    if (m.type() === 'error' && !EXPECTED_404.test(m.text())) appErrs.push('console: ' + m.text().slice(0, 200));
  });
  await p2.goto(`http://localhost:${PORT}/`, { waitUntil: 'load' });
  await p2.waitForTimeout(500);
  await p2.evaluate(() => { localStorage.clear(); window.MB_STORE.seed(); });
  await p2.reload({ waitUntil: 'load' });
  await p2.waitForTimeout(600);
  /* "글자 수가 적으면 빈 화면" 으로 재다가 멀쩡한 화면을 빨갛게 찍었습니다.
     P06 의 "먼저 목표를 정해주세요 + 목표 설정하기 버튼" 은 23자인데,
     왜 비었는지 말하고 나갈 길도 주는 좋은 빈 상태입니다.
     중요한 건 길이가 아니라 (가) 무슨 일인지 말해주는가 (나) 나갈 길이
     있는가 입니다. */
  const screens = await p2.evaluate(() => window.MB_APP.screenIds);
  const empties = [];
  for (const s of screens) {
    await p2.evaluate(x => window.MB_APP.go(x), s);
    await p2.waitForTimeout(220);
    const r = await p2.evaluate(() => {
      const m = document.getElementById('main') || {};
      const txt = (m.innerText || '').trim();
      const out = m.querySelector ? m.querySelector('button, a, .chip, input') : null;
      const nav = document.querySelector('.tabbar, [data-uid^="P00-N"]');
      return { chars: txt.length, escape: !!(out || nav) };
    });
    if (r.chars < 12 || !r.escape) empties.push(s + ':' + r.chars + (r.escape ? '' : '/나갈길없음'));
  }
  ok(`화면 ${screens.length}개가 전부 말을 하고 나갈 길이 있다`, empties.length === 0, empties);
  ok('앱 전체에서 JS 오류 0건', appErrs.length === 0, appErrs.slice(0, 3));

  /* --------------------------------------------------------------------
   * [8] 개인정보처리방침
   *
   * 이 앱은 건강에 관한 정보를 다룹니다. 남이 쓸 물건이 되는 순간,
   * "무엇이 어디로 가는가" 를 읽을 수 있는 곳에 적어 두는 것은 예의가
   * 아니라 기본입니다.
   *
   * 여기서 보는 것은 세 가지입니다
   *   · 문서가 실제로 배포본에 들어갔고 주소로 열리는가
   *   · 자리표시자가 그대로 남아 있지 않은가
   *   · 운영자 칸이 비어 있지 않은가 — 누구에게 말해야 하는지 모르는
   *     방침은 권리를 행사할 방법이 없다는 뜻입니다
   * ------------------------------------------------------------------ */
  /* 배포본이 자기를 뭐라고 부르는가.
     "프로토타입 · 검증용" 이라고 적혀 있으면 받은 사람은 미완성을
     쓰고 있다고 읽습니다. 그리고 버전 번호는 문제가 생겼을 때
     "어느 판이냐" 를 물어볼 수 있는 유일한 손잡이입니다. */
  {
    await p2.evaluate(() => window.MB_APP.go('P12'));
    await p2.waitForTimeout(300);
    const foot = await p2.evaluate(() => {
      const c = document.querySelector('[data-uid="P12-C06"]');
      return c ? c.innerText : '';
    });
    ok('"프로토타입 · 검증용" 이 안 보인다', !/프로토타입|검증용/.test(foot), foot.slice(0, 120));
    ok('빌드 버전이 적혀 있다', build && foot.includes(build.version), foot.slice(0, 120));
  }

  console.log('\n[8] 개인정보처리방침');
  {
    const pv = await ctx.newPage();
    const r = await pv.goto(`http://localhost:${PORT}/privacy.html`, { waitUntil: 'load' })
      .then(x => ({ status: x.status() })).catch(e => ({ err: e.message }));
    ok('주소로 열린다', r.status === 200, r);
    const txt = await pv.evaluate(() => document.body.innerText).catch(() => '');
    ok('자리표시자가 안 남아 있다', !/__OWNER_/.test(txt));
    ok('운영자와 연락처가 적혀 있다', !txt.includes('따로 적어 두지 않았습니다'),
       'node tools/serve.js --setup --owner="이름" --contact="연락처" 로 정하고 다시 빌드하세요');
    ok('민감정보라고 말한다', /민감정보/.test(txt));
    ok('앱으로 돌아가는 길이 있다',
       await pv.locator('a[href="./index.html"]').count().then(n => n > 0));
    await pv.close();

    /* 방침이 "추적 코드가 없습니다" 라고 말합니다. 글꼴 하나라도 바깥에서
       받아 오면 그 문장이 그 자리에서 거짓이 됩니다 — 페이지를 여는 것만으로
       남의 서버에 내 IP 가 남기 때문입니다. 말이 아니라 실제 요청을 셉니다. */
    const out = [];
    const pw = await ctx.newPage();
    pw.on('request', q => {
      const u = q.url();
      if (!u.startsWith('http://localhost:' + PORT) && !u.startsWith('data:') && !u.startsWith('blob:')) out.push(u);
    });
    await pw.goto(`http://localhost:${PORT}/privacy.html`, { waitUntil: 'load' });
    await pw.waitForTimeout(400);
    await pw.goto(`http://localhost:${PORT}/`, { waitUntil: 'load' });
    await pw.waitForTimeout(900);
    ok('앱과 방침이 바깥으로 요청을 안 보낸다', out.length === 0, out.slice(0, 4));
    await pw.close();

    // 앱 안에서 이 문서로 갈 수 있는가 — 주소를 아는 사람만 읽는 방침은 공개가 아닙니다
    const linked = await p2.evaluate(() => {
      window.MB_APP.go('P12');
      return new Promise(res => setTimeout(() => {
        const a = document.querySelector('[data-uid="P12-B15"]');
        res(!!a && /privacy\.html/.test(a.getAttribute('href') || ''));
      }, 250));
    });
    ok('설정에서 링크로 갈 수 있다', linked);
  }

  console.log(`\n통과 ${pass} / 실패 ${fail}`);
  await browser.close(); server.close();
  process.exit(fail ? 1 : 0);
})().catch(e => { console.error(e); server.close(); process.exit(1); });
