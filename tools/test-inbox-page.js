/* =============================================================================
 * tools/test-inbox-page.js — 컴퓨터 브라우저로 보는 「의견함」 (GET /inbox)
 *
 *   node tools/test-inbox-page.js
 *   NODE_PATH=/opt/node22/lib/node_modules node tools/test-inbox-page.js   (playwright 가 있는 곳)
 *
 * 왜 이 시험이 있나
 *   /inbox 는 누구나 여는 페이지이고, 로그인한 운영자에게는 **로그인 없이도 보낼 수 있는 남의 글**을
 *   보여 줍니다. 그래서 지켜야 할 것이 셋입니다.
 *     · 남의 글이 글자 그대로 — <img onerror> · </script> 가 든 의견 · 이름 · 화면 이름이 태그가 되면
 *       운영자의 브라우저에서 남의 스크립트가 운영자 토큰으로 돕니다. 페이지 글자에 HTML 로 끼워
 *       넣는 길이 없는지 읽어 보고, 진짜 브라우저에서 그런 의견을 띄워 봅니다.
 *     · 스크립트 · 스타일은 해시 하나씩 — CSP 가 허락하는 것은 페이지에 박힌 한 덩이뿐이고(글자
 *       그대로 맞아야), 윈도우에서 파일이 CRLF 로 꺼내져도 맞아야 합니다(test-invite.js [15] 와 같음).
 *     · 운영자만 — 운영자가 아닌 계정으로 로그인하면 거절하고 그 로그인을 바로 끊습니다.
 *
 * 보는 것
 *   [1] 페이지 — 200 · 머리(no-store · Vary: * · noindex · no-referrer · DENY · nosniff) · CSP 가 정한
 *       그대로 · 해시가 <script> · <style> 과 맞음 · 요청이 달라도 한 글자도 안 바뀜 · 내보내는 폴더의
 *       inbox 파일이 못 가로챔 · /inbox/ → 302 · POST 405 · HEAD
 *   [2] 페이지 글자 — innerHTML · insertAdjacentHTML · document.write · eval · on…= 속성 · style= ·
 *       javascript: · 밖의 주소가 없음 · 스크립트가 페이지를 끊지 않음(</ · <!--) · CR 없음
 *   [3] 진짜 브라우저(playwright — 없으면 이 부분만 건너뜀)
 *       · 로그인(틀린 비밀번호 · 비운영자는 거절 + 토큰이 끊김 · 운영자 · Enter 로도) · 토큰은 기본
 *         sessionStorage, 「로그인 유지」 면 localStorage · 주소에 비밀번호 · 토큰이 안 실림
 *       · 목록(익명 · 이름 · 판 · 기종 · 화면 · 사진 수 · 한국 시각 · 안 읽음 점) · 자세히(pre-wrap) ·
 *         사진(Authorization 로 받아 blob: · 누르면 크게 · 떠나면 revoke) · 글이 태그가 아니라 글자 ·
 *         열면 읽음 · j/k · 「안 읽은 것만」(모자라면 다음 쪽을 저절로) · 「더 보기」 · 새로고침(받아
 *         둔 옛 쪽 유지) · 「모두 읽음」(upTo) · 「지우기」(페이지 안에서 묻기 — confirm() 없음)
 *       · 401 → 로그인 칸 · 로그아웃(서버 로그인도 끊김 · 저장소 비움)
 *       · 360px 에서 가로로 안 밀림(목록 · 자세히 · 로그인) · 어두운 테마
 *       · alert · 페이지 오류 · 콘솔 오류 · CSP 위반이 하나도 없음
 *   [4] 윈도우 줄바꿈 — server/inbox-page.js 를 CRLF 로 읽어도 스크립트 · 스타일은 LF 로 나가고
 *       브라우저가 줄바꿈을 맞춘 뒤 재는 해시가 CSP 와 맞음
 *
 * 포트는 11000~11299 (다른 서버 시험과 안 겹치게 — test-feedback-inbox 10200~ · test-operator-users 10600~).
 * ========================================================================== */
'use strict';
/* 검사하는 사람의 ~/.mybody 설정(의견 알림 아이디 등)이 결과를 바꾸지 않게. */
require('./testenv.js');
const { spawn } = require('node:child_process');
const crypto = require('node:crypto');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const zlib = require('node:zlib');
const { DatabaseSync } = require('node:sqlite');

const ROOT = path.join(__dirname, '..');
const DBM = require(path.join(ROOT, 'server', 'db.js'));
const PAGE_MOD = path.join(ROOT, 'server', 'inbox-page.js');

let pass = 0, fail = 0;
const ok = (n, c, d) => {
  if (c) { pass++; console.log('  ✓', n); }
  else { fail++; console.log('  ✗', n, d === undefined ? '' : JSON.stringify(d).slice(0, 500)); }
};
const wait = ms => new Promise(r => setTimeout(r, ms));
const TMP = fs.mkdtempSync(path.join(os.tmpdir(), 'mybody-inboxpage-'));
const PW = 'test-password-1';
const PORT = 11000 + Math.floor(Math.random() * 300);
const PAIR = 'inboxpage-pair-secret';
const DB = path.join(TMP, 'srv.db');
const BASE = `http://127.0.0.1:${PORT}`;
const CHROME = process.env.CHROME_PATH || '/opt/pw-browsers/chromium-1194/chrome-linux/chrome';

/* 내보내는 폴더 — inbox 라는 파일을 일부러 둡니다(서버 코드의 페이지가 이겨야 함). 아이콘은
   페이지가 부르는 것 하나만 옮겨 둡니다(없으면 브라우저가 404 를 콘솔에 찍음). */
const STATIC = path.join(TMP, 'static');
fs.mkdirSync(path.join(STATIC, 'assets'), { recursive: true });
fs.writeFileSync(path.join(STATIC, 'index.html'), 'WEB-APP');
fs.writeFileSync(path.join(STATIC, 'inbox'), 'STATIC-INBOX');
fs.copyFileSync(path.join(ROOT, 'prototype', 'assets', 'favicon-32.png'), path.join(STATIC, 'assets', 'favicon-32.png'));

let srv = null, out = '';
function boot(env, nodeArgs) {
  out = '';
  const p = spawn(process.execPath, (nodeArgs || []).concat([path.join(ROOT, 'server', 'server.js')]), {
    cwd: ROOT, stdio: ['ignore', 'pipe', 'pipe'],
    env: Object.assign({}, process.env, {
      PORT: String(PORT), PAIR_SECRET: PAIR, DB, AUTH_MAX: '100000', RATE_MAX: '100000',
      STATIC, NODE_NO_WARNINGS: '1', FEEDBACK_NOTIFY: 'owner'
    }, env || {})
  });
  p.stdout.on('data', d => { out += d; });
  p.stderr.on('data', d => { out += d; });
  srv = p;
  return p;
}
async function stop() {
  if (!srv) return;
  const p = srv; srv = null;
  await new Promise(r => { p.once('exit', r); try { p.kill('SIGTERM'); } catch (e) { r(); } setTimeout(r, 3000); });
}
async function waitUp() {
  for (let i = 0; i < 80; i++) {
    if (srv && srv.exitCode !== null) return false;
    try { if ((await fetch(`${BASE}/api/health`)).ok) return true; } catch (e) {}
    await wait(150);
  }
  return false;
}
async function call(method, p, body, token) {
  const r = await fetch(BASE + '/api' + p, {
    method,
    headers: Object.assign({ 'Content-Type': 'application/json' }, token ? { Authorization: 'Bearer ' + token } : {}),
    body: body !== undefined && body !== null ? JSON.stringify(body) : undefined
  });
  const text = await r.text();
  let j = null; try { j = JSON.parse(text); } catch (e) {}
  return { status: r.status, json: j || {}, text };
}
async function get(p, opt) {
  const r = await fetch(BASE + p, Object.assign({ redirect: 'manual' }, opt || {}));
  const buf = Buffer.from(await r.arrayBuffer());
  return { status: r.status, h: r.headers, body: buf.toString('utf8'), raw: buf };
}
async function until(fn, ms = 5000) {
  const t0 = Date.now();
  while (Date.now() - t0 < ms) {
    try { if (await fn()) return true; } catch (e) {}
    await wait(50);
  }
  try { return !!(await fn()); } catch (e) { return false; }
}
const shaOf = s => "'sha256-" + crypto.createHash('sha256').update(s, 'utf8').digest('base64') + "'";
const scriptsOf = html => [...html.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script>/gi)];
const stylesOf = html => [...html.matchAll(/<style\b([^>]*)>([\s\S]*?)<\/style>/gi)];
/** CSP 를 {지시어: [값…]} 으로. */
function cspMap(csp) {
  const m = {};
  for (const part of String(csp || '').split(';')) {
    const w = part.trim().split(/\s+/).filter(Boolean);
    if (w.length) m[w[0]] = w.slice(1);
  }
  return m;
}
/* 한국 시각 — 페이지와 다른 길(Intl)로 계산해 맞대 봅니다. */
function kstParts(iso) {
  const f = new Intl.DateTimeFormat('en-US', { timeZone: 'Asia/Seoul', year: 'numeric', month: 'numeric',
    day: 'numeric', hour: '2-digit', minute: '2-digit', hourCycle: 'h23' });
  const p = {};
  for (const x of f.formatToParts(new Date(iso))) p[x.type] = x.value;
  return { y: p.year, label: `${Number(p.month)}월 ${Number(p.day)}일 ${p.hour.padStart(2, '0')}:${p.minute}` };
}

/* 진짜로 풀리는 작은 PNG(단색) — 브라우저가 그려야 하므로 앞머리만 맞춘 가짜로는 안 됩니다. */
function makePng(w, h, rgb) {
  const table = new Int32Array(256).map((_, n) => {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    return c;
  });
  const crc = buf => { let c = -1; for (const b of buf) c = table[(c ^ b) & 0xff] ^ (c >>> 8); return (c ^ -1) >>> 0; };
  const chunk = (type, data) => {
    const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
    const td = Buffer.concat([Buffer.from(type, 'ascii'), data]);
    const c = Buffer.alloc(4); c.writeUInt32BE(crc(td));
    return Buffer.concat([len, td, c]);
  };
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4); ihdr[8] = 8; ihdr[9] = 2;
  const raw = Buffer.alloc((w * 3 + 1) * h);
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) raw.set(rgb, y * (w * 3 + 1) + 1 + x * 3);
  return Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr), chunk('IDAT', zlib.deflateSync(raw)), chunk('IEND', Buffer.alloc(0))]);
}

/* playwright — 다른 UI 시험처럼 NODE_PATH 의 것, 아니면 보통 require, 아니면 배포 전 점검
   (tools/preflight.js)이 NODE_PATH 로 주는 기본 자리. 어디에도 없으면 브라우저 부분만 건너뜁니다. */
function loadPlaywright() {
  const tries = [];
  if (process.env.NODE_PATH) tries.push(path.join(process.env.NODE_PATH, 'playwright'));
  tries.push('playwright', '/opt/node22/lib/node_modules/playwright');
  for (const t of tries) { try { return require(t); } catch (e) {} }
  return null;
}

/* --- [1] 페이지 · 머리 --------------------------------------------------- */
let LF_PAGE = '';
async function pageAndHeaders() {
  console.log('\n[1] GET /inbox — 머리 · CSP · 한 글자도 안 바뀜');
  const r = await get('/inbox');
  const h = r.h;
  ok('200 · text/html; charset=utf-8', r.status === 200 && h.get('content-type') === 'text/html; charset=utf-8',
     [r.status, h.get('content-type')]);
  ok('Cache-Control: no-store', h.get('cache-control') === 'no-store', h.get('cache-control'));
  ok('Vary: * (웹 앱 서비스워커가 캐시에 못 담음)', h.get('vary') === '*', h.get('vary'));
  ok('X-Robots-Tag: noindex', h.get('x-robots-tag') === 'noindex', h.get('x-robots-tag'));
  ok('Referrer-Policy: no-referrer', h.get('referrer-policy') === 'no-referrer', h.get('referrer-policy'));
  ok('X-Frame-Options: DENY', h.get('x-frame-options') === 'DENY', h.get('x-frame-options'));
  ok('X-Content-Type-Options: nosniff', h.get('x-content-type-options') === 'nosniff');
  const csp = h.get('content-security-policy') || '';
  const m = cspMap(csp);
  const want = {
    'default-src': ["'none'"], 'img-src': ["'self'", 'blob:'], 'connect-src': ["'self'"],
    'base-uri': ["'none'"], 'form-action': ["'none'"], 'frame-ancestors': ["'none'"]
  };
  ok("CSP: default-src 'none' · img-src 'self' blob: · connect-src 'self' · base-uri · form-action · frame-ancestors 'none'",
     Object.keys(want).every(k => JSON.stringify(m[k]) === JSON.stringify(want[k])), m);
  ok('CSP 지시어는 정한 여덟 개뿐', JSON.stringify(Object.keys(m).sort()) === JSON.stringify(
    ['base-uri', 'connect-src', 'default-src', 'form-action', 'frame-ancestors', 'img-src', 'script-src', 'style-src']),
     Object.keys(m));
  ok("CSP 에 'unsafe-inline' · 'unsafe-eval' · 'strict-dynamic' · 주소 · * · data: 없음",
     !/unsafe-inline|unsafe-eval|strict-dynamic|https?:|\*|data:/.test(csp), csp);
  const scripts = scriptsOf(r.body), styles = stylesOf(r.body);
  ok('<script> 하나 · 속성 없음 · CSP 의 script-src 는 그 해시 하나', scripts.length === 1 && scripts[0][1] === '' &&
     JSON.stringify(m['script-src']) === JSON.stringify([shaOf(scripts[0][2])]), [scripts.length, m['script-src']]);
  ok('<style> 하나 · 속성 없음 · CSP 의 style-src 는 그 해시 하나', styles.length === 1 && styles[0][1] === '' &&
     JSON.stringify(m['style-src']) === JSON.stringify([shaOf(styles[0][2])]), [styles.length, m['style-src']]);
  ok('스크립트가 제법 길다 (빈 페이지를 시험하지 않게)', scripts.length === 1 && scripts[0][2].length > 5000);
  ok('서버 모듈이 지은 글자 그대로 나간다', r.body === require(PAGE_MOD).INBOX_HTML);
  LF_PAGE = r.body;

  /* 받은 것(쿼리 · 머리)을 싣지 않는다 — 누구에게나 같은 글자. */
  const r2 = await get('/inbox?x=%3Cscript%3Ealert(1)%3C/script%3E&handle=owner', {
    headers: { 'User-Agent': '<b>ua</b>', 'X-Forwarded-Host': 'evil.example', 'Accept-Language': 'en' } });
  ok('쿼리 · User-Agent · 머리가 달라도 한 글자도 안 바뀐다', r2.status === 200 && r2.body === r.body &&
     r2.h.get('content-security-policy') === csp);
  ok('내보내는 폴더의 inbox 파일이 못 가로챈다 (서버 코드의 페이지가 먼저)', !r.body.includes('STATIC-INBOX') &&
     r.body.includes('id="login-form"'));
  const slash = await get('/inbox/?q=%3Cx%3E');
  ok('/inbox/ → 302 /inbox (받은 쿼리는 안 실음)', slash.status === 302 && slash.h.get('location') === '/inbox',
     [slash.status, slash.h.get('location')]);
  const post = await get('/inbox', { method: 'POST', body: 'x' });
  ok('POST → 405 · Allow: GET, HEAD', post.status === 405 && post.h.get('allow') === 'GET, HEAD', post.status);
  const head = await get('/inbox', { method: 'HEAD' });
  ok('HEAD → 200 · 같은 CSP · 몸통 없음', head.status === 200 && head.h.get('content-security-policy') === csp &&
     head.raw.length === 0);
  const deeper = await get('/inbox/x');
  ok('/inbox/x 는 이 페이지가 아니다 (없는 파일 → 404)', deeper.status === 404 && !deeper.body.includes('login-form'),
     deeper.status);
  ok('로그에 /inbox 줄이 안 남는다 (API 만 찍음)', !/\s\/inbox\b/.test(out), out.slice(-300));
}

/* --- [2] 페이지 글자 ------------------------------------------------------ */
function staticScan() {
  console.log('\n[2] 페이지 글자 — HTML 로 끼워 넣는 길 · 인라인 핸들러가 없다');
  const body = LF_PAGE;
  const scripts = scriptsOf(body);
  const js = scripts.length === 1 ? scripts[0][2] : '';
  const html = body.replace(/<script>[\s\S]*?<\/script>/, '').replace(/<style>[\s\S]*?<\/style>/, '');
  for (const [name, re] of [
    ['innerHTML', /innerHTML/], ['outerHTML', /outerHTML/], ['insertAdjacentHTML', /insertAdjacentHTML/],
    ['document.write', /document\s*\.\s*write/], ['eval(', /\beval\s*\(/], ['new Function', /new\s+Function\b/],
    ['DOMParser · createContextualFragment', /DOMParser|createContextualFragment/],
    ['setAttribute(\'on…\')', /setAttribute\(\s*['"]on/i], ['요소.on…= 핸들러', /\.on[a-z]+\s*=(?!=)/],
    ['문자열 setTimeout', /setTimeout\(\s*['"`]/], ['javascript:', /javascript:/i]
  ]) ok('스크립트에 ' + name + ' 없음', js.length > 0 && !re.test(js), (js.match(re) || [])[0]);
  ok('스크립트는 글자를 textContent · createElement 로 놓는다', /createElement\(/.test(js) &&
     /createTextNode\(/.test(js) && /\.textContent\s*=/.test(js));
  ok('스크립트 안에 </ · <!-- 가 없다 (페이지를 끊지 않음)', !js.includes('</') && !js.includes('<!--'));
  ok('페이지 어디에도 CR(\\r) 이 없다 (줄바꿈은 LF — [4])', !body.includes('\r'));
  ok('HTML 에 인라인 이벤트 속성(on…=) 없음', !/\son[a-z]+\s*=/i.test(html), (html.match(/\son[a-z]+\s*=/i) || [])[0]);
  ok('HTML 에 style= · javascript: · 다른 <script> 없음', !/\sstyle\s*=/i.test(html) && !/javascript:/i.test(html) &&
     !/<script/i.test(html));
  const refs = [...body.matchAll(/\s(?:src|href|action)\s*=\s*"([^"]*)"/gi)].map(x => x[1]);
  ok('부르는 자원은 이 서버 것뿐 (밖의 글꼴 · 그림 없음)', refs.every(u => /^\/[^/]/.test(u)) && !/https?:\/\//.test(body),
     refs);
  ok('폼은 post 이고 action 이 없다 (스크립트가 막혀도 비밀번호가 주소에 안 실림 · form-action 이 막음)',
     /<form id="login-form" method="post"(?![^>]*action)/.test(body));
}

/* --- [3] 진짜 브라우저 ---------------------------------------------------- */
async function browserRun() {
  console.log('\n[3] 진짜 브라우저 — 로그인 · 목록 · 자세히 · 사진 · 읽음 · 지우기 · XSS');
  const pw = loadPlaywright();
  if (!pw) {
    console.log('  · playwright 를 찾을 수 없어 브라우저 시험은 건너뜁니다 (NODE_PATH 를 playwright 가 있는 node_modules 로)');
    return;
  }
  let browser;
  try {
    browser = await pw.chromium.launch(process.env.CHROME_PATH || fs.existsSync(CHROME) ? { executablePath: CHROME } : {});
  } catch (e) {
    console.log('  · 브라우저를 못 띄워 건너뜁니다: ' + String(e && e.message || e).split('\n')[0]);
    return;
  }
  try { await browserChecks(browser); } finally { await browser.close().catch(() => {}); }
}

async function browserChecks(browser) {
  const signup = async (handle, name) => (await call('POST', '/auth/signup', {
    handle, password: PW, displayName: name, pairSecret: PAIR, healthConsent: DBM.HEALTH_CONSENT_VERSION })).json;
  const O = await signup('owner', '운영자');
  const NAME = '<s>이름</s>';
  const T = await signup('tester1', NAME);
  ok('운영자 · 다른 사람 계정', !!(O.token && T.token));
  ok('운영자는 /api/me 에 isOperator', (await call('GET', '/me', null, O.token)).json.user.isOperator === true);

  const XSS = '<img src=x onerror=alert(1)></script><b>굵게</b>\n  둘째 줄\t탭 <script>alert(4)</script>';
  const VER = '0.2.19<b>x</b>', SCR = '<svg onload=alert(2)>';
  const PNG_W = 30, PNG_H = 48;
  const png = makePng(PNG_W, PNG_H, [0x4f, 0x46, 0xe5]);
  const f1 = await call('POST', '/feedback', { text: XSS, appVersion: VER, platform: 'android', screen: SCR });
  const f2 = await call('POST', '/feedback', { text: '사진 붙임 ' + 'A'.repeat(400), platform: 'ios', appVersion: '0.2.19+330',
    screen: '설정', images: [{ type: 'image/png', data: png.toString('base64') }] }, T.token);
  const id1 = f1.json.id, id2 = f2.json.id;
  ok('의견 둘 (하나는 익명 · 태그 글, 하나는 로그인 · PNG 사진)', f1.status === 200 && f2.status === 200 && id1 && id2,
     [f1.text, f2.text]);
  const inbox = async () => (await call('GET', '/feedback/inbox?limit=50', null, O.token)).json;
  const first = await inbox();
  const it1 = first.items.find(i => i.id === id1), it2 = first.items.find(i => i.id === id2);

  const ctx = await browser.newContext({ viewport: { width: 1280, height: 800 } });
  /* 페이지보다 먼저 도는 관찰자 — CSP 위반 · 만든 · 거둔 blob URL 을 적어 둡니다(페이지 CSP 밖에서 돕니다). */
  await ctx.addInitScript(() => {
    window.__csp = [];
    window.__made = [];
    window.__revoked = [];
    document.addEventListener('securitypolicyviolation', e => window.__csp.push(e.violatedDirective + ' ' + e.blockedURI));
    const mk = URL.createObjectURL.bind(URL), rv = URL.revokeObjectURL.bind(URL);
    URL.createObjectURL = b => { const u = mk(b); window.__made.push(u); return u; };
    URL.revokeObjectURL = u => { window.__revoked.push(u); return rv(u); };
  });
  const dialogs = [], errors = [], csp = [], reqs = [];
  const watch = page => {
    page.on('dialog', d => { dialogs.push(d.type() + ': ' + d.message()); d.dismiss().catch(() => {}); });
    page.on('pageerror', e => errors.push('pageerror: ' + e.message));
    page.on('console', msg => {
      if (msg.type() !== 'error') return;
      /* 일부러 부른 401(틀린 비밀번호 · 끊긴 로그인)은 브라우저가 자원 오류로 찍습니다 — 그것만 봐줍니다. */
      if (/Failed to load resource: the server responded with a status of 401/.test(msg.text())) return;
      errors.push('console: ' + msg.text());
    });
    page.on('request', r => reqs.push(r));
  };
  const collectCsp = async page => { try { csp.push(...await page.evaluate(() => window.__csp)); } catch (e) {} };
  const page = await ctx.newPage();
  watch(page);
  const rows = () => page.$$eval('#list .row', bs => bs.map(b => Number(b.getAttribute('data-id'))));
  const selId = () => page.$eval('#list .row.sel', b => Number(b.getAttribute('data-id'))).catch(() => null);
  const text = sel => page.$eval(sel, e => e.textContent).catch(() => null);
  const storage = () => page.evaluate(() => ({
    s: sessionStorage.getItem('mybody-inbox-token'), l: localStorage.getItem('mybody-inbox-token') }));
  const noHScroll = () => page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth &&
    document.body.scrollWidth <= window.innerWidth);

  /* --- 로그인 --- */
  await page.goto(BASE + '/inbox');
  ok('처음엔 로그인 칸 (목록은 숨김)', await until(() => page.isVisible('#login-form')) && !(await page.isVisible('#inbox')));
  await page.fill('#handle', 'owner');
  await page.fill('#password', 'wrong-password-9');
  await page.click('#login-btn');
  ok('틀린 비밀번호 → 서버의 까닭 한 줄', await until(async () => /맞지 않습니다/.test(await text('#login-msg') || '')),
     await text('#login-msg'));

  await page.fill('#handle', 'tester1');
  await page.fill('#password', PW);
  const [tResp] = await Promise.all([
    page.waitForResponse(r => r.url().endsWith('/api/auth/signin') && r.request().method() === 'POST'),
    page.press('#password', 'Enter')
  ]);
  const tTok = (await tResp.json().catch(() => ({}))).token;
  ok('비운영자 → 「운영자 계정만 볼 수 있어요」 (Enter 로 보냄)',
     await until(async () => (await text('#login-msg') || '').includes('운영자 계정만 볼 수 있어요')) &&
     !(await page.isVisible('#inbox')), await text('#login-msg'));
  ok('비운영자의 방금 로그인은 서버에서 끊겼다 (그 토큰으로 /api/me → 401)',
     !!tTok && (await call('GET', '/me', null, tTok)).status === 401);
  const st0 = await storage();
  ok('비운영자 토큰은 어디에도 저장되지 않았다', st0.s === null && st0.l === null, st0);
  ok('비밀번호 칸은 비워졌다', (await page.inputValue('#password')) === '');

  await page.fill('#handle', 'owner');
  await page.fill('#password', PW);
  await page.click('#login-btn');
  ok('운영자 로그인 → 목록에 두 건', await until(async () => (await rows()).length === 2), await rows());
  ok('새것부터 (번호 내림차순)', JSON.stringify(await rows()) === JSON.stringify([id2, id1]), await rows());
  const st1 = await storage();
  ok('토큰은 기본 sessionStorage (localStorage 에는 없음)', !!st1.s && st1.l === null, st1);
  ok('주소에 비밀번호 · 토큰이 안 실렸다', page.url() === BASE + '/inbox' &&
     reqs.every(r => !r.url().includes(PW) && !r.url().includes(st1.s)), page.url());
  ok('안 읽음 2 · 탭 제목에도', (await text('#unread')) === '안 읽음 2' && (await page.title()) === '(2) 의견함 · Mybody',
     [await text('#unread'), await page.title()]);
  ok('안 읽음 점 둘', (await page.$$('#list .dot')).length === 2);

  /* --- 목록 한 줄 --- */
  const row1 = await text(`#list .row[data-id="${id1}"]`) || '';
  const row2 = await text(`#list .row[data-id="${id2}"]`) || '';
  ok('익명 의견은 「익명」 · 판 · 기종 · 화면이 글자 그대로', row1.includes('익명') && row1.includes(VER) &&
     row1.includes('Android') && row1.includes(SCR), row1);
  ok('글 앞부분이 태그가 아니라 글자 (<img …> · </script> · <b> 그대로)',
     row1.includes('<img src=x onerror=alert(1)></script><b>굵게</b>'), row1);
  ok('로그인해서 보낸 의견은 표시 이름(태그 그대로) · iOS · 사진 1', row2.includes(NAME) && row2.includes('iOS') &&
     row2.includes('사진 1') && row2.includes('설정'), row2);
  const k1 = kstParts(it1.createdAt);
  ok('받은 시각은 한국 시각 (' + k1.label + ')', (await text(`#list .row[data-id="${id1}"] .time`)) ===
     (k1.y === kstParts(new Date().toISOString()).y ? k1.label : k1.y + '년 ' + k1.label),
     await text(`#list .row[data-id="${id1}"] .time`));
  ok('목록에 태그가 생기지 않았다 (img · b · s · svg · script 없음)',
     (await page.$$('#list img, #list b, #list s, #list svg, #list script')).length === 0);

  /* --- 자세히 (태그 글) --- */
  await page.click(`#list .row[data-id="${id1}"]`);
  ok('누르면 자세히 — 글 전체가 서버의 글과 한 글자도 다르지 않다',
     await until(async () => (await text('#d-text')) === it1.text), [await text('#d-text'), it1.text]);
  ok('글 칸에는 요소가 하나도 없다 (글자뿐)', await page.$eval('#d-text', e => e.children.length === 0));
  ok('글은 pre-wrap (줄바꿈 · 칸 그대로)', await page.$eval('#d-text', e => getComputedStyle(e).whiteSpace) === 'pre-wrap');
  const info1 = await text('#detail .meta') || '';
  ok('정보: 보낸 사람 익명 · 판 · 기종 · 보던 화면 · 한국 시각 · 번호', info1.includes('익명') && info1.includes(VER) &&
     info1.includes('Android') && info1.includes(SCR) && info1.includes('(한국 시각)') && info1.includes('#' + id1) &&
     info1.includes(k1.y + '년 ' + k1.label), info1);
  ok('자세히에도 태그가 생기지 않았다', (await page.$$('#detail img, #detail b, #detail svg, #detail script')).length === 0);
  /* 사진 없는 의견에서 빈 자리가 "null" 이라는 글자로 찍힌 적이 있습니다(replaceChildren(null)). */
  ok('빈 값이 글자로 찍히지 않는다 (null · undefined · NaN — 자세히 · 목록)',
     !/\bnull\b|undefined|NaN/.test(await text('#detail') || 'null') && !/\bnull\b|undefined|NaN/.test(await text('#list') || 'null'),
     [await text('#detail'), await text('#list')]);
  ok('열면 읽음 — 서버에 read:true', await until(async () => (await inbox()).items.find(i => i.id === id1).read === true));
  ok('열면 읽음 — 점이 사라지고 안 읽음 1', await until(async () =>
    (await page.$$(`#list .row[data-id="${id1}"] .dot`)).length === 0 && (await text('#unread')) === '안 읽음 1'));

  /* --- 자세히 (사진) --- */
  await page.click(`#list .row[data-id="${id2}"]`);
  ok('보낸 사람 이름도 글자 그대로', await until(async () => (await text('#detail h2')) === NAME), await text('#detail h2'));
  ok('사진 의견의 자세히에도 빈 값 글자가 없다', !/\bnull\b|undefined|NaN/.test(await text('#detail') || 'null'));
  ok('사진이 그려진다 (blob: · 원래 크기)', await until(() => page.$eval('#detail .shot img', i =>
    i.complete && i.naturalWidth === 30 && i.naturalHeight === 48 && i.src.startsWith('blob:')).catch(() => false)));
  const blob2 = await page.$eval('#detail .shot img', i => i.src).catch(() => '');
  const imgReq = reqs.find(r => r.url().endsWith(`/api/feedback/inbox/${id2}/image/1`));
  const imgHdr = imgReq ? await imgReq.allHeaders() : {};
  ok('사진은 Authorization 머리로 받았다 (주소에 토큰 없음)', !!imgReq &&
     imgHdr.authorization === 'Bearer ' + st1.s, imgHdr.authorization);
  await page.click('#detail .shot');
  ok('누르면 크게 (같은 blob)', await until(() => page.isVisible('#viewer')) &&
     await page.$eval('#viewer-img', i => i.src) === blob2 &&
     await until(() => page.$eval('#viewer-img', i => i.complete && i.naturalWidth === 30)));
  await page.keyboard.press('Escape');
  ok('Esc 로 닫힘', await until(async () => !(await page.isVisible('#viewer'))));
  await page.click('#detail .shot');
  await until(() => page.isVisible('#viewer'));
  await page.click('#viewer-img');
  ok('크게 본 사진을 누르면 닫힘', await until(async () => !(await page.isVisible('#viewer'))));
  ok('사진 의견도 열면 읽음 → 안 읽음 0 · 배지 없음 · 「모두 읽음」 꺼짐', await until(async () =>
    !(await page.isVisible('#unread')) && await page.isDisabled('#read-all') && (await page.title()) === '의견함 · Mybody'));

  await page.click(`#list .row[data-id="${id1}"]`);
  ok('다른 의견으로 가면 보던 사진의 blob URL 을 거둔다(revoke)', await until(() =>
    page.evaluate(u => window.__revoked.includes(u), blob2)), blob2);

  /* --- j / k --- */
  await page.keyboard.press('k');
  ok('k → 위(새것)로', await until(async () => (await selId()) === id2), await selId());
  await page.keyboard.press('j');
  ok('j → 아래(옛것)로', await until(async () => (await selId()) === id1), await selId());

  /* --- 새로고침 · 「안 읽은 것만」 · 「모두 읽음」 --- */
  const f3 = await call('POST', '/feedback', { text: '셋째 의견' });
  const id3 = f3.json.id;
  await page.click('#refresh');
  ok('새로고침 → 새 의견이 맨 위 · 안 읽음 점', await until(async () => JSON.stringify(await rows()) ===
     JSON.stringify([id3, id2, id1])) && (await page.$$(`#list .row[data-id="${id3}"] .dot`)).length === 1, await rows());
  ok('새로고침해도 보던 자세히는 그대로', (await selId()) === id1 && (await text('#d-text')) === it1.text);
  await page.click('#f-unread');
  ok('「안 읽은 것만」 → 안 읽은 것 + 지금 보는 것만', await until(async () =>
    JSON.stringify(await rows()) === JSON.stringify([id3, id1])) &&
     await page.getAttribute('#f-unread', 'aria-pressed') === 'true', await rows());
  const [raReq] = await Promise.all([
    page.waitForRequest(r => r.url().endsWith('/api/feedback/inbox/read-all')),
    page.click('#read-all')
  ]);
  let raBody = null; try { raBody = JSON.parse(raReq.postData() || 'null'); } catch (e) {}
  ok('「모두 읽음」 은 받아 둔 가장 새 번호까지만 (upTo)', raBody && raBody.upTo === id3, raBody);
  ok('「모두 읽음」 → 서버의 안 읽음 0', await until(async () => (await inbox()).unread === 0));
  ok('「모두 읽음」 → 점 없음 · 「안 읽은 것만」 에는 보는 것만', await until(async () =>
    (await page.$$('#list .dot')).length === 0 && JSON.stringify(await rows()) === JSON.stringify([id1])), await rows());
  await page.click('#f-all');
  ok('「전체」 → 세 건', await until(async () => (await rows()).length === 3), await rows());

  /* --- 지우기 --- */
  await page.click(`#list .row[data-id="${id3}"]`);
  await until(async () => (await text('#d-text')) === '셋째 의견');
  await page.click('#del');
  ok('「지우기」 → 페이지 안에서 묻는다 (confirm() 창 없음)', await until(() => page.isVisible('#confirm')) &&
     dialogs.length === 0 && (await text('#confirm-q') || '').includes('지울까요'));
  await page.click('#del-no');
  ok('취소 → 묻기가 닫히고 그대로 있다', await until(async () => !(await page.isVisible('#confirm'))) &&
     (await rows()).includes(id3) && (await inbox()).items.some(i => i.id === id3));
  await page.click('#del');
  await until(() => page.isVisible('#del-yes'));
  await page.click('#del-yes');
  ok('지우면 목록에서 빠지고 서버에도 없다', await until(async () => !(await rows()).includes(id3)) &&
     await until(async () => !(await inbox()).items.some(i => i.id === id3)), await rows());
  ok('지운 뒤 자세히는 비고 「지웠어요」', (await text('#detail') || '').includes('지웠어요') && (await selId()) === null);

  /* --- 더 보기 · 새로고침이 옛 쪽을 지킴 --- */
  const d = new DatabaseSync(DB);
  const ins = d.prepare('INSERT INTO feedback (created_at, text) VALUES (?, ?)');
  const bulk = [];
  for (let i = 0; i < 35; i++) bulk.push(Number(ins.run(new Date().toISOString(), '묶음 ' + i).lastInsertRowid));
  d.close();
  await page.click('#refresh');
  ok('새로고침 → 30건 · 「더 보기」 가 보인다', await until(async () => (await rows()).length === 30) &&
     await page.isVisible('#more'), (await rows()).length);
  await page.click('#more');
  ok('「더 보기」 → 37건 전부 · 끝이면 「더 보기」 없음', await until(async () => (await rows()).length === 37) &&
     await until(async () => !(await page.isVisible('#more'))), (await rows()).length);
  await page.click('#refresh');
  await until(async () => !(await page.isDisabled('#refresh')));
  ok('새로고침해도 「더 보기」 로 받아 둔 옛 쪽이 남는다', (await rows()).length === 37 && !(await page.isVisible('#more')),
     (await rows()).length);
  ok('안 읽음 35 (새로 넣은 것)', (await text('#unread')) === '안 읽음 35', await text('#unread'));

  /* 다시 열면(토큰은 이 탭에 남음) 첫 쪽만 — 「안 읽은 것만」 은 모자라는 안 읽은 것을 저절로 더 받는다. */
  await collectCsp(page);
  await page.reload();
  ok('다시 열어도 로그인 유지(이 탭) · 첫 쪽 30건', await until(async () => (await rows()).length === 30), (await rows()).length);
  await page.click('#f-unread');
  ok('「안 읽은 것만」 → 안 읽은 35건을 저절로 다 받는다', await until(async () => (await rows()).length === 35) &&
     (await rows()).every(id => bulk.includes(id)), (await rows()).length);
  await page.click('#f-all');
  await until(async () => (await rows()).length === 37);

  /* --- 좁은 화면 · 어두운 테마 --- */
  await page.setViewportSize({ width: 360, height: 740 });
  ok('360px 목록 — 가로로 안 밀린다', await until(noHScroll));
  await page.click(`#list .row[data-id="${id2}"]`);
  ok('360px 자세히 — 목록 자리에 서고 「← 목록」 이 보인다', await until(() => page.isVisible('#back')) &&
     !(await page.isVisible('#list')));
  ok('360px 자세히 — 긴 글 · 사진이 있어도 가로로 안 밀린다', await until(() => page.$eval('#detail .shot img',
    i => i.complete && i.naturalWidth > 0).catch(() => false)) && await noHScroll());
  await page.click('#back');
  ok('「← 목록」 → 목록으로', await until(() => page.isVisible('#list')) && !(await page.isVisible('#back')));
  await page.emulateMedia({ colorScheme: 'dark' });
  const darkBg = await page.evaluate(() => getComputedStyle(document.body).backgroundColor);
  await page.emulateMedia({ colorScheme: 'light' });
  const lightBg = await page.evaluate(() => getComputedStyle(document.body).backgroundColor);
  ok('어두운 테마 · 밝은 테마를 컴퓨터 설정대로', darkBg === 'rgb(14, 16, 20)' && lightBg === 'rgb(246, 247, 249)',
     [darkBg, lightBg]);
  await page.setViewportSize({ width: 1280, height: 800 });

  /* --- 401 → 로그인 칸 --- */
  const cur = (await storage()).s;
  await call('POST', '/auth/signout', null, cur);
  await page.click('#refresh');
  ok('로그인이 끊기면(401) 로그인 칸으로 · 한 줄 안내', await until(() => page.isVisible('#login-form')) &&
     (await text('#login-msg') || '').includes('다시 로그인'), await text('#login-msg'));
  const st2 = await storage();
  ok('끊긴 토큰은 저장소에서 지웠다', st2.s === null && st2.l === null, st2);
  ok('목록 · 자세히가 화면에서 치워졌다', (await page.$$('#list .row')).length === 0 && !(await page.isVisible('#inbox')));
  const made1 = await page.evaluate(() => window.__made);
  const revoked1 = await page.evaluate(() => window.__revoked);
  ok('만든 blob URL 은 전부 거뒀다', made1.length > 0 && made1.every(u => revoked1.includes(u)), [made1.length, revoked1.length]);

  /* --- 로그인 유지 · 로그아웃 --- */
  await page.fill('#handle', 'owner');
  await page.fill('#password', PW);
  await page.check('#keep');
  await page.click('#login-btn');
  await until(async () => (await rows()).length > 0);
  const st3 = await storage();
  ok('「이 컴퓨터에서 로그인 유지」 → localStorage (sessionStorage 에는 없음)', !!st3.l && st3.s === null, st3);
  await collectCsp(page);
  const page2 = await ctx.newPage();
  watch(page2);
  await page2.goto(BASE + '/inbox');
  ok('새 탭에서도 로그인 없이 바로 목록', await until(() => page2.isVisible('#list .row')) &&
     !(await page2.isVisible('#login-form')));
  await page2.click('#logout');
  ok('로그아웃 → 로그인 칸 · 「로그아웃했어요」', await until(() => page2.isVisible('#login-form')) &&
     (await page2.$eval('#login-msg', e => e.textContent)) === '로그아웃했어요');
  ok('로그아웃 → 서버의 로그인도 끊겼다', await until(async () => (await call('GET', '/me', null, st3.l)).status === 401));
  ok('로그아웃 → 저장소가 비었다', await until(() => page2.evaluate(() =>
    localStorage.getItem('mybody-inbox-token') === null && sessionStorage.getItem('mybody-inbox-token') === null)));
  await page2.setViewportSize({ width: 360, height: 740 });
  ok('360px 로그인 칸 — 가로로 안 밀린다', await until(() => page2.evaluate(() =>
    document.documentElement.scrollWidth <= window.innerWidth)));
  await collectCsp(page2);

  /* --- 한 번도 없었어야 하는 것 --- */
  ok('alert · confirm 같은 창이 한 번도 안 떴다', dialogs.length === 0, dialogs);
  ok('페이지 오류 · 콘솔 오류 없음', errors.length === 0, errors.slice(0, 5));
  ok('CSP 위반 없음', csp.length === 0, csp.slice(0, 5));
  /* blob: 은 페이지가 받은 사진을 제 안에서 가리키는 주소라 이 서버 것입니다. */
  const foreign = reqs.map(r => r.url()).filter(u => !u.startsWith(BASE + '/') && !u.startsWith('blob:' + BASE + '/'));
  ok('이 서버 밖으로 나간 요청 없음', foreign.length === 0, foreign.slice(0, 5));
  ok('스크립트가 실제로 돌았다 (API 를 불렀다 — 해시가 맞았다는 뜻)', reqs.some(r => r.url().endsWith('/api/feedback/inbox?limit=30')));
  await ctx.close();
}

/* --- [4] 윈도우 줄바꿈 ---------------------------------------------------- */
async function crlfCheckout() {
  console.log('\n[4] 윈도우 줄바꿈 (CRLF 로 읽힌 server/inbox-page.js)');
  const pre = path.join(TMP, 'crlf-preload.js');
  fs.writeFileSync(pre, [
    "const M = require('node:module');",
    'const orig = M.prototype._compile;',
    'M.prototype._compile = function (content, filename) {',
    "  if (/[\\\\/]server[\\\\/]inbox-page\\.js$/.test(filename)) {",
    "    content = content.replace(/\\r?\\n/g, '\\r\\n');",
    "    process.stdout.write('CRLF-PRELOAD ' + (content.match(/\\r\\n/g) || []).length + '\\n');",
    '  }',
    '  return orig.call(this, content, filename);',
    '};', ''].join('\n'));
  boot({}, ['-r', pre]);
  ok('서버(CRLF) 가 뜬다', await waitUp(), out.slice(-300));
  const n = Number((/CRLF-PRELOAD (\d+)/.exec(out) || [])[1] || 0);
  ok('inbox-page.js 를 정말 CRLF 로 읽었다 (시험이 헛돌지 않게)', n > 300, [n, out.slice(0, 200)]);
  const r = await get('/inbox');
  const m = cspMap(r.h.get('content-security-policy'));
  const js = (scriptsOf(r.body)[0] || [])[2] || '';
  const css = (stylesOf(r.body)[0] || [])[2] || '';
  /* 브라우저가 재는 글자 = HTML 의 줄바꿈 맞추기(\r\n · \r → \n)를 거친 것. */
  ok('브라우저가 재는 스크립트 해시(줄바꿈을 맞춘 뒤)가 CSP 와 맞는다',
     r.status === 200 && js.length > 5000 && JSON.stringify(m['script-src']) === JSON.stringify([shaOf(js.replace(/\r\n?/g, '\n'))]));
  ok('스타일 해시도 맞는다', css.length > 1000 && JSON.stringify(m['style-src']) === JSON.stringify([shaOf(css.replace(/\r\n?/g, '\n'))]));
  ok('페이지에 CR 이 없고, LF 로 읽은 서버의 페이지와 한 글자도 다르지 않다',
     !r.body.includes('\r') && LF_PAGE.length > 5000 && r.body === LF_PAGE, [r.body.includes('\r'), r.body.length, LF_PAGE.length]);
  await stop();
}

async function main() {
  boot();
  ok('서버가 뜬다', await waitUp(), out.slice(-400));
  await pageAndHeaders();
  staticScan();
  await browserRun();
  await stop();
  await crlfCheckout();
}

main()
  .catch(e => { fail++; console.error(e); })
  .finally(async () => {
    await stop();
    try { fs.rmSync(TMP, { recursive: true, force: true }); } catch (e) {}
    console.log(`\n${pass} 통과 · ${fail} 실패`);
    process.exit(fail ? 1 : 0);
  });
