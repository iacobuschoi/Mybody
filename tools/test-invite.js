/* =============================================================================
 * tools/test-invite.js — 친구 초대 링크 페이지 (GET /i/<코드>)
 *
 *   node tools/test-invite.js
 *
 * 왜 이 시험이 있나
 *   초대 링크는 **로그인 없이 누구나 여는 페이지**이고, 카카오톡 · 문자로 돌아다닙니다.
 *   그래서 지켜야 할 것이 셋입니다.
 *     · 새지 않는다 — 코드 주인이 누구인지(이름 · 아이디 · "있는 코드인가")를 페이지로
 *       알 수 없어야 합니다. 있는 코드와 없는 코드의 페이지가 글자 하나 다르지 않아야 합니다.
 *     · 앱과 약속한 모양 그대로 — 안드로이드 intent:// (패키지 · 스킴 · fallback 이 URL 인코딩),
 *       아이폰 mybody://invite/<코드>. 한 글자만 어긋나도 "앱에서 열기" 가 아무 일도 안 합니다.
 *     · 스크립트는 해시 하나 — CSP 가 허락하는 것은 페이지의 스크립트 한 덩이뿐이고(해시가
 *       글자 그대로 맞아야), 받은 것(Host · 설정의 링크)은 이스케이프되어야 합니다.
 *   그리고 주인의 말 "링크만 누르면 바로 친추 · 앱이 없으면 스토어로 · 모든 걸 자동으로" 를
 *   지키는지 — 앱 링크 파일 둘(폰이 링크를 앱으로 바로 열게 하는 것)과, 페이지의 스크립트를
 *   가짜 브라우저(vm)에서 **실제로 돌려** 어디로 가는지 봅니다.
 *
 * 보는 것
 *   [1] 글자판 — server.js 의 초대 코드 글자판이 db.js inviteCode() 와 같다
 *   [2] 맞는 코드 → 200 HTML · 큰 코드 · og 태그 · noindex
 *   [3] 소문자 · 끝의 / → 대문자 주소로 302 (noapp 만 이어 붙임)
 *   [4] 틀린 코드 → 같은 모양의 404 · 받은 글자를 다시 찍지 않음
 *   [5] 기종별 "앱에서 열기" — 안드로이드 intent · 아이폰 mybody:// · 컴퓨터는 없음
 *   [6] 설치 안내 — 참여 링크가 없으면 "곧 열려요 — 코드 <코드>", 있으면 단추(도구로 적은
 *       그대로 · 안드로이드는 ① 그룹 ② 참여 ③ 추천인 붙은 플레이) · 시험 기간을 끄면 가게 주소 ·
 *       시험 중이어도 앱스토어 판(--appstore)을 적으면 아이폰만 App Store(안드로이드는 글자 그대로)
 *   [7] ?noapp=1 — 설치 안내를 앞세움
 *   [8] 새지 않는다 — 이름 · 아이디가 안 나오고, 있는 코드 = 없는 코드 · 로그에 코드 없음 ·
 *       초대 페이지 코드는 DB 를 부르지 않음
 *   [9] 머리글 — CSP(스크립트 · 스타일 해시가 페이지와 글자 그대로 일치) · nosniff · no-store · no-referrer ·
 *       Vary: * (웹 앱의 서비스워커가 페이지를 담아 두면 ?noapp=1 이 보통 페이지로 나옵니다)
 *  [10] 절대 주소 — 받은 사람이 연 주소(Host · 믿는 프록시의 X-Forwarded-*)가 먼저, 이 컴퓨터
 *       자신 · 이상한 Host 면 ORIGIN · 안 믿는 X-Forwarded-* 는 무시 · 이상한 Host 는 안 박음 ·
 *       ORIGIN 이 옛 주소여도 fallback 은 지금 페이지로
 *  [11] 이스케이프 — 설정의 링크에 든 ' & < " 가 그대로 박히지 않음 (단추 · data-… 둘 다)
 *  [12] 앱 링크 파일 — assetlinks.json · apple-app-site-association 이 글자 그대로 · 지문 다듬기 ·
 *       설정으로 더하기 · 틀린 값 버리기 · 팀 ID 기본값 · application/json · 리디렉션 없음 ·
 *       환경변수가 먼저 · 내보내는 폴더의 같은 이름 파일이 못 가로챔
 *  [13] 스크립트 (가짜 브라우저에서 실제로 실행) — 카카오톡은 기본 브라우저로 · 안드로이드는
 *       intent(fallback: 시험 중 ?noapp=1 · 뒤 추천인 플레이) · 아이폰은 1.5초 뒤 설치 페이지
 *       (?stay=1 · 누름 · 가려짐이면 안 감 · 앱스토어 판이 적혀 있으면 시험 중이어도 App Store) ·
 *       설치 단추는 초대 글을 담고 감 · 한 탭에 한 번
 *  [14] 스크립트가 꺼져 있어도 — 단추는 전부 진짜 주소 · "설치 페이지로 가요…" 는 숨김
 *  [15] 윈도우 줄바꿈 — server.js 를 CRLF 로 읽어도(git 의 core.autocrlf) 스크립트는 LF 로 나가고,
 *       브라우저가 줄바꿈을 맞춘 뒤에 재는 해시가 CSP 와 맞는다
 * ========================================================================== */
'use strict';
/* 검사하는 사람의 ~/.mybody 설정(진짜 참여 링크 · 공개 주소)이 결과를 바꾸지 않게. */
const TESTENV = require('./testenv.js');
const { spawn, spawnSync } = require('node:child_process');
const http = require('node:http');
const crypto = require('node:crypto');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const vm = require('node:vm');

const ROOT = path.join(__dirname, '..');
const DBM = require(path.join(ROOT, 'server', 'db.js'));
const TOOL = path.join(ROOT, 'tools', 'app-version.js');

let pass = 0, fail = 0;
const ok = (n, c, d) => {
  if (c) { pass++; console.log('  ✓', n); }
  else { fail++; console.log('  ✗', n, d === undefined ? '' : JSON.stringify(d).slice(0, 500)); }
};
const wait = ms => new Promise(r => setTimeout(r, ms));
const TMP = fs.mkdtempSync(path.join(os.tmpdir(), 'mybody-invite-'));
/* 포트는 운영체제에게 빈 것을 받습니다(main 첫 줄). 어림으로 고른 포트가 이미 떠 있는 다른 서버와
   겹치면, 우리 서버는 못 뜨고 waitUp 은 **남의 서버**에 붙어 엉뚱한 설정으로 시험합니다. */
let PORT = 0;
function freePort() {
  return new Promise((resolve, reject) => {
    const s = http.createServer();
    s.once('error', reject);
    s.listen(0, '127.0.0.1', () => { const n = s.address().port; s.close(() => resolve(n)); });
  });
}
const PAIR = 'invite-pair-secret';
const DB = path.join(TMP, 'srv.db');
const CFG = path.join(TESTENV.home, '.mybody', 'config.json');

const UA = {
  android: 'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Mobile Safari/537.36',
  kakaoAndroid: 'Mozilla/5.0 (Linux; Android 13; SM-S911N) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Mobile Safari/537.36 KAKAOTALK 10.4.5',
  ios: 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1',
  ipad: 'Mozilla/5.0 (iPad; CPU OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148',
  desktop: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36',
  kakaoIos: 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 KAKAOTALK 10.8.0',
  instaAndroid: 'Mozilla/5.0 (Linux; Android 14; SM-S918N Build/UP1A; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/126.0 Mobile Safari/537.36 Instagram 339.0.0.37.93 Android',
  instaIos: 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 Instagram 339.0.0.37.93',
  fbIos: 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 [FBAN/FBIOS;FBAV/470.0.0.40.109]',
  lineAndroid: 'Mozilla/5.0 (Linux; Android 14; Pixel 8; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/126.0 Mobile Safari/537.36 Line/14.10.1',
  naverIos: 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 NAVER(inapp; search; 2000; 12.6.3)'
};
const PKG = 'io.github.iacobuschoi.mybody';
/* 앱과 약속한 가게 주소 (계약 (D) · (E)). 플레이는 코드마다 추천인이 붙습니다. */
const APPSTORE = 'https://apps.apple.com/app/id6815144446';
const playOf = c => 'https://play.google.com/store/apps/details?id=' + PKG + '&referrer=invite%3D' + c;
const UPLOAD_CERT = '06:D9:45:A3:83:79:71:CE:A7:AF:0C:03:BC:EF:F3:13:96:4F:57:7B:C8:C1:6A:41:03:3A:A2:60:17:83:DE:11';

let srv = null, out = '';
/* nodeArgs: 노드에 먼저 줄 인자(예: ['-r', 미리 읽을 파일]) — [15] 가 씁니다. */
function boot(env, nodeArgs) {
  out = '';
  const p = spawn(process.execPath, (nodeArgs || []).concat([path.join(ROOT, 'server', 'server.js')]), {
    cwd: ROOT, stdio: ['ignore', 'pipe', 'pipe'],
    env: Object.assign({}, process.env, {
      PORT: String(PORT), PAIR_SECRET: PAIR, DB, AUTH_MAX: '100000',
      STATIC: path.join(ROOT, 'prototype'), NODE_NO_WARNINGS: '1'
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
    /* 우리가 띄운 서버가 벌써 끝났으면(포트가 차 있음 등) 그 포트의 대답은 남의 것입니다. */
    if (!srv || srv.exitCode !== null || srv.signalCode !== null) return false;
    try { if ((await fetch(`http://127.0.0.1:${PORT}/api/health`)).ok) return true; } catch (e) {}
    await wait(150);
  }
  return false;
}
/** 페이지 한 장. fetch 는 Host 를 못 바꿔서 http.request 로 — 머리글을 마음대로 싣습니다. */
function page(p, opt) {
  const o = opt || {};
  const headers = Object.assign({}, o.ua ? { 'User-Agent': o.ua } : {}, o.headers || {});
  return new Promise((resolve, reject) => {
    const req = http.request({ host: '127.0.0.1', port: PORT, path: p, method: o.method || 'GET', headers }, res => {
      const chunks = [];
      res.on('data', c => chunks.push(c));
      res.on('end', () => resolve({ status: res.statusCode, headers: res.headers,
                                    body: Buffer.concat(chunks).toString('utf8') }));
    });
    req.on('error', reject);
    req.end();
  });
}
async function api(method, p, body, token) {
  const r = await fetch(`http://127.0.0.1:${PORT}/api${p}`, {
    method, headers: Object.assign({ 'Content-Type': 'application/json' }, token ? { Authorization: 'Bearer ' + token } : {}),
    body: body ? JSON.stringify(body) : undefined
  });
  let j = null; try { j = await r.json(); } catch (e) {}
  return { status: r.status, json: j || {} };
}
/** 도구로 설정을 고칩니다 — 주인이 실제로 하는 그대로. PORT 를 주어 이 서버에 확인하게. */
function tool(args) {
  const env = Object.assign({}, process.env, { NODE_NO_WARNINGS: '1', PORT: String(PORT) });
  const r = spawnSync(process.execPath, [TOOL].concat(args), { cwd: ROOT, encoding: 'utf8', timeout: 30000, env });
  return { code: r.status, out: (r.stdout || '') + (r.stderr || '') };
}
function writeCfg(obj) {
  fs.mkdirSync(path.dirname(CFG), { recursive: true });
  fs.writeFileSync(CFG, JSON.stringify(obj, null, 2) + '\n');
}
/** 페이지의 링크(href)들 — &amp; 등은 풀어서. */
function hrefs(html) {
  const out2 = [];
  const re = /<a\b[^>]*\bhref="([^"]*)"[^>]*>([\s\S]*?)<\/a>/g;
  let m;
  while ((m = re.exec(html))) out2.push({ href: unesc(m[1]), label: m[2], tag: m[0] });
  return out2;
}
const unesc = s => s.replace(/&#39;/g, "'").replace(/&quot;/g, '"').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&');
const meta = (html, attr, name) => {
  const m = new RegExp('<meta ' + attr + '="' + name.replace(/[:.]/g, '\\$&') + '" content="([^"]*)">').exec(html);
  return m ? unesc(m[1]) : null;
};
const openBtn = html => hrefs(html).find(a => a.label === '앱에서 열기');
/** 페이지의 스크립트 글자 그대로 (없으면 ''). */
const scriptOf = html => (/<script>([\s\S]*?)<\/script>/.exec(html) || [])[1] || '';
/** 태그의 속성들 — 값은 풀어서, 값 없는 속성(hidden · data-install)은 ''. */
function attrsOf(tag) {
  const a = {};
  const re = /\s([a-z][a-z0-9-]*)(?:="([^"]*)")?/g;
  let m;
  while ((m = re.exec(tag))) a[m[1]] = m[2] === undefined ? '' : unesc(m[2]);
  return a;
}
const bodyData = html => attrsOf((/<body\b([^>]*)>/.exec(html) || [])[1] || '');
/** CSP 해시 한 조각 — 'sha256-<base64>'. */
const shaOf = s => "'sha256-" + crypto.createHash('sha256').update(s, 'utf8').digest('base64') + "'";
/* 첫 서버(LF 로 읽은 server.js)가 내보낸 스크립트 — [15] 가 CRLF 로 읽힌 서버의 것과 견줍니다. */
let LF_SCRIPT = '';
const settle = () => new Promise(r => setImmediate(r));

/** 가짜 브라우저 — 페이지의 스크립트를 **그대로** vm 에서 돌립니다.
 *  스크립트가 만지는 것만 흉내 냅니다: body 의 data-… · a[data-install] · #later · 문서의 이벤트 ·
 *  location(href 읽기/쓰기 · replace) · navigator.clipboard · sessionStorage · setTimeout ·
 *  visibilityState. 어디로 가려 했는지(nav) · 무엇을 담았는지(clip) 를 남깁니다.
 *  opt: href(지금 주소) · session(이미 있는 sessionStorage) · noStorage · noClipboard · clipFail ·
 *       clipHang · hidden(화면이 가려짐) */
function runScript(html, opt) {
  const o = opt || {};
  const nav = [], clip = [], timers = [], docOn = {};
  const store = Object.assign({}, o.session || {});
  const body = bodyData(html);
  const anchors = hrefs(html).filter(a => /\sdata-install[\s>]/.test(a.tag)).map(a => ({
    href: a.href, label: a.label, on: {},
    addEventListener(t, f) { (this.on[t] = this.on[t] || []).push(f); },
    getAttribute(k) { return k === 'href' ? this.href : null; }
  }));
  const laterTag = /<p\b[^>]*\bid="later"[^>]*>/.exec(html);
  const later = laterTag ? { hidden: Object.hasOwn(attrsOf(laterTag[0]), 'hidden') } : null;
  const location = {
    get href() { return o.href || 'https://mybody.example.ts.net/i/X'; },
    set href(v) { nav.push(['href', v]); },
    replace(v) { nav.push(['replace', v]); }
  };
  const ctx = {
    document: {
      body: { getAttribute: k => (k.startsWith('data-') && Object.hasOwn(body, k)) ? body[k] : null },
      querySelectorAll: sel => (sel === 'a[data-install]' ? anchors : []),
      getElementById: id => (id === 'later' ? later : null),
      addEventListener(t, f) { (docOn[t] = docOn[t] || []).push(f); },
      visibilityState: o.hidden ? 'hidden' : 'visible'
    },
    location,
    navigator: o.noClipboard ? {} : { clipboard: { writeText(t) {
      clip.push(t);
      if (o.clipHang) return new Promise(() => {});      // 허락 창이 떠서 영영 안 끝나는 경우
      return o.clipFail ? Promise.reject(new Error('NotAllowedError')) : Promise.resolve();
    } } },
    sessionStorage: o.noStorage ? undefined : {
      getItem: k => (Object.hasOwn(store, k) ? store[k] : null),
      setItem: (k, v) => { store[k] = String(v); }
    },
    setTimeout: (f, ms) => { timers.push({ f, ms, done: false }); return timers.length; }
  };
  let error = null;
  try { vm.runInNewContext(scriptOf(html), ctx, { timeout: 1000 }); } catch (e) { error = e; }
  return {
    nav, clip, timers, store, later, anchors, error,
    /** ms 이하로 걸린 타이머를 차례로 돌립니다 — "그만큼 시간이 지났다". */
    tick(ms) { timers.filter(t => !t.done && t.ms <= ms).forEach(t => { t.done = true; t.f(); }); },
    /** 문서에서 사람이 뭔가를 누름. */
    touch(type) { (docOn[type || 'pointerdown'] || []).forEach(f => f({ type: type || 'pointerdown' })); },
    /** 설치 단추 누르기 → 기본 동작을 막았는지. */
    click(a, extra) {
      let prevented = false;
      const ev = Object.assign({ button: 0, preventDefault() { prevented = true; } }, extra || {});
      (a.on.click || []).forEach(f => f.call(a, ev));
      return prevented;
    }
  };
}
/** 이스케이프된 글자판 코드 — 시험마다 새 코드. */
function randCode() {
  const A = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  return Array.from(crypto.randomBytes(8), b => A[b % A.length]).join('');
}

function alphabet() {
  console.log('\n[1] 글자판 — db.js inviteCode() 와 같다');
  const dbSrc = fs.readFileSync(path.join(ROOT, 'server', 'db.js'), 'utf8');
  const srvSrc = fs.readFileSync(path.join(ROOT, 'server', 'server.js'), 'utf8');
  const a = (/function inviteCode\(\)\s*\{\s*const A = '([A-Z0-9]+)'/.exec(dbSrc) || [])[1];
  const b = (/const INVITE_ALPHABET = '([A-Z0-9]+)'/.exec(srvSrc) || [])[1];
  ok('db.js 와 server.js 의 글자판이 같다', a && a === b, [a, b]);
  ok('글자판에 I · O · 0 · 1 이 없다 (32자)', b && b.length === 32 && !/[IO01]/.test(b), b);
}

async function main() {
  PORT = await freePort();
  alphabet();

  /* 첫 서버: 공개 주소 없음 · 터널 뒤(TRUST_PROXY) — 요청의 X-Forwarded-* 로 주소를 짓습니다. */
  boot({ TRUST_PROXY: '1' });
  ok('서버가 뜬다', await waitUp(), out.slice(-400));

  /* 코드 주인 — 이름 · 아이디가 페이지에 절대 안 나와야 합니다. */
  const NAME = '숨은이름' + crypto.randomBytes(3).toString('hex');
  const HANDLE = 'hiddenowner' + crypto.randomBytes(3).toString('hex');
  const su = await api('POST', '/auth/signup', { handle: HANDLE, password: 'test-password-1', displayName: NAME,
                                                pairSecret: PAIR, healthConsent: DBM.HEALTH_CONSENT_VERSION });
  const me = await api('GET', '/me', null, su.json.token);
  const CODE = me.json.user && me.json.user.inviteCode;
  ok('코드 주인 계정을 만들고 코드를 받는다', su.status === 200 && /^[A-Z2-9]{8}$/.test(CODE || ''), [su.status, CODE]);

  console.log('\n[2] 맞는 코드 → 200 HTML');
  const a = await page('/i/' + CODE, { ua: UA.android });
  ok('200 · text/html', a.status === 200 && /^text\/html; charset=utf-8$/.test(a.headers['content-type']), [a.status, a.headers['content-type']]);
  ok('<!doctype html> · lang="ko"', /^<!doctype html>\n<html lang="ko">/.test(a.body));
  ok('<title>Mybody 친구 초대</title>', a.body.includes('<title>Mybody 친구 초대</title>'));
  ok('큰 코드 글자 (class="code")', a.body.includes('<p class="code">' + CODE + '</p>'));
  ok('og:title = Mybody 친구 초대', meta(a.body, 'property', 'og:title') === 'Mybody 친구 초대');
  ok('og:description = 링크를 누르면 바로 친구가 돼요 · 코드 <CODE>',
     meta(a.body, 'property', 'og:description') === '링크를 누르면 바로 친구가 돼요 · 코드 ' + CODE,
     meta(a.body, 'property', 'og:description'));
  ok('og:type website · twitter:card summary', meta(a.body, 'property', 'og:type') === 'website' &&
     meta(a.body, 'name', 'twitter:card') === 'summary');
  ok('robots noindex (메타 · 머리글 둘 다)', meta(a.body, 'name', 'robots') === 'noindex' &&
     a.headers['x-robots-tag'] === 'noindex');
  ok('"앱을 연 뒤에는 바로 친구가 돼요 (로그인 필요)"',
     a.body.includes('앱을 연 뒤에는 바로 친구가 돼요 (로그인 필요)'));
  ok('"앱이 없나요?" 칸', a.body.includes('<h2>앱이 없나요?</h2>'));
  const icon = /<img class="icon" src="([^"]+)"/.exec(a.body);
  ok('앱 아이콘을 같은 서버에서 보여 준다', icon && icon[1] === '/assets/icon-192.png', icon && icon[1]);
  const head = await page('/i/' + CODE, { method: 'HEAD', ua: UA.android });
  ok('HEAD → 200 · 본문 없음', head.status === 200 && head.body === '' && /text\/html/.test(head.headers['content-type']), head.status);
  const post = await page('/i/' + CODE, { method: 'POST' });
  ok('POST → 405 (Allow: GET, HEAD)', post.status === 405 && post.headers.allow === 'GET, HEAD', [post.status, post.headers.allow]);

  console.log('\n[3] 소문자 · 끝의 / → 대문자 주소로');
  const lo = await page('/i/' + CODE.toLowerCase());
  ok('소문자 → 302 /i/<대문자>', lo.status === 302 && lo.headers.location === '/i/' + CODE, [lo.status, lo.headers.location]);
  /* 영문 한 글자만 소문자로 — 앞 네 글자만 낮추면 그 넷이 전부 숫자(2~9)인 코드(1/256)에서 주소가
     안 바뀌어 302 가 안 나오고, 시험이 가끔 이유 없이 떨어집니다. */
  const mixed = CODE.replace(/[A-Z]/, c => c.toLowerCase());
  const mx = await page('/i/' + mixed + '?noapp=1&x=%3Cscript%3E');
  ok('섞인 대소문자 + noapp → noapp 만 이어 붙인다 (다른 쿼리는 뗌)', mx.status === 302 &&
     mx.headers.location === '/i/' + CODE + '?noapp=1', mx.headers.location);
  const sl = await page('/i/' + CODE + '/');
  ok('끝의 / → 302 /i/<코드>', sl.status === 302 && sl.headers.location === '/i/' + CODE, sl.headers.location);
  const lo2 = await page(lo.headers.location, { ua: UA.ios });
  ok('돌려보낸 주소는 200', lo2.status === 200 && lo2.body.includes('<p class="code">' + CODE + '</p>'));

  console.log('\n[4] 틀린 코드 → 같은 모양의 404');
  const bads = ['/i/ABCD0000', '/i/ABCDEFGI', '/i/abcdefgo', '/i/ABC2345', '/i/ABCD23456', '/i/', '/i',
                '/i/ABCD2345/x', '/i/%3Cscript%3Ealert(1)%3C%2Fscript%3E', '/i/ABCD234%35', '/i/..%2F..%2Fetc'];
  for (const b of bads) {
    const r = await page(b, { ua: UA.android });
    const echoed = b.length > 3 && r.body.includes(decodeURIComponent(b.slice(3) || '~~'));
    ok('404 ' + b + ' — 같은 모양 · 받은 글자를 안 찍음 · 앱 열기 없음', r.status === 404 &&
       /text\/html/.test(r.headers['content-type']) && r.body.includes('<h1>Mybody 친구 초대</h1>') &&
       r.body.includes('초대 링크가 맞지 않아요') && !echoed && !/<script/i.test(r.body) &&
       !openBtn(r.body) && r.headers['content-security-policy'] === a.headers['content-security-policy'],
       [r.status, r.body.slice(0, 120)]);
  }

  console.log('\n[5] 기종별 "앱에서 열기"');
  const base = 'https://mybody-fwd.example.ts.net';
  const fwd = { 'X-Forwarded-Proto': 'https', 'X-Forwarded-Host': 'mybody-fwd.example.ts.net' };
  const an = await page('/i/' + CODE, { ua: UA.android, headers: fwd });
  const ab = openBtn(an.body);
  const wantIntent = 'intent://invite/' + CODE + '#Intent;scheme=mybody;package=' + PKG +
    ';S.browser_fallback_url=' + encodeURIComponent(base + '/i/' + CODE + '?noapp=1') + ';end';
  ok('안드로이드 → intent:// (약속한 모양 그대로)', ab && ab.href === wantIntent, ab && ab.href);
  const fb = ab && /;S\.browser_fallback_url=([^;]*);end$/.exec(ab.href);
  ok('fallback 은 URL 인코딩 (: / ? = 가 날것으로 없음) · 풀면 이 페이지 + ?noapp=1',
     fb && !/[:/?=]/.test(fb[1]) && decodeURIComponent(fb[1]) === base + '/i/' + CODE + '?noapp=1', fb && fb[1]);
  ok('안드로이드의 "앱에서 열기" 는 큰(주) 단추', ab && /btn--primary/.test(ab.tag), ab && ab.tag);
  const ka = openBtn((await page('/i/' + CODE, { ua: UA.kakaoAndroid, headers: fwd })).body);
  ok('카카오톡 안드로이드 안의 브라우저도 안드로이드로 ("앱에서 열기" 는 같은 intent)', ka && ka.href === wantIntent, ka && ka.href);
  const io = await page('/i/' + CODE, { ua: UA.ios, headers: fwd });
  const ib = openBtn(io.body);
  ok('아이폰 → mybody://invite/<코드>', ib && ib.href === 'mybody://invite/' + CODE, ib && ib.href);
  ok('아이폰 페이지에 intent:// 는 없다', !io.body.includes('intent://'));
  const ip = openBtn((await page('/i/' + CODE, { ua: UA.ipad })).body);
  ok('아이패드도 아이폰 쪽', ip && ip.href === 'mybody://invite/' + CODE, ip && ip.href);
  for (const [nm, ua] of [['컴퓨터', UA.desktop], ['User-Agent 없음', '']]) {
    const d = await page('/i/' + CODE, { ua });
    ok(nm + ' → "앱에서 열기" 없음 · 안드로이드 · 아이폰 안내 둘 다', !openBtn(d.body) &&
       !d.body.includes('intent://') && !d.body.includes('mybody://') &&
       d.body.includes('<h3>안드로이드</h3>') && d.body.includes('<h3>아이폰</h3>'), d.body.slice(-600));
  }

  console.log('\n[6] 설치 안내 — 설정대로');
  ok('참여 링크가 없으면 안드로이드: "곧 열려요 — 코드 <코드> 를 적어 두세요"',
     an.body.includes('안드로이드는 곧 열려요 — 코드 ' + CODE + ' 를 적어 두세요') && !an.body.includes('설치한 뒤') &&
     !hrefs(an.body).some(x => /play\.google\.com/.test(x.href)), an.body.slice(-400));
  ok('참여 링크가 없으면 아이폰: "곧 열려요 — 코드 <코드> 를 적어 두세요"',
     io.body.includes('아이폰은 곧 열려요 — 코드 ' + CODE + ' 를 적어 두세요'));
  const JA = 'https://play.google.com/apps/testing/' + PKG;
  const JG = 'https://groups.google.com/g/mybody-testers';
  const JI = 'https://testflight.apple.com/join/AbCdEf12';
  const t1 = tool(['--join-android=' + JA, '--join-android-group=' + JG, '--join-ios=' + JI]);
  ok('도구로 참여 링크 셋을 적는다', t1.code === 0, t1.out.slice(-300));
  const an2 = await page('/i/' + CODE, { ua: UA.android });
  const l2 = hrefs(an2.body);
  const g = l2.findIndex(x => x.label === '① 구글 그룹 가입' && x.href === JG);
  const j = l2.findIndex(x => x.label === '② 테스트 참여' && x.href === JA);
  const pl = l2.findIndex(x => x.label === '③ Google Play 에서 설치' && x.href === playOf(CODE));
  ok('안드로이드: ① 구글 그룹 가입 → ② 테스트 참여 → ③ Google Play 에서 설치 (순서대로 · 적은 주소 그대로)',
     g >= 0 && j > g && pl > j, l2.map(x => x.label));
  ok('③ 은 추천인 붙은 플레이 주소 (&referrer=invite%3D<코드> — 한 번 인코딩)',
     pl >= 0 && l2[pl].href === 'https://play.google.com/store/apps/details?id=' + PKG + '&referrer=invite%3D' + CODE &&
     l2[pl].tag.includes('&amp;referrer=invite%3D' + CODE), pl >= 0 && l2[pl].tag);
  ok('①②③ 은 설치 단추 (data-install)', [g, j, pl].every(i => i >= 0 && /\sdata-install[\s>]/.test(l2[i].tag)));
  ok('안드로이드: "곧 열려요" 가 사라지고 "설치한 뒤 돌아와서" 가 붙는다',
     !an2.body.includes('곧 열려요') && an2.body.includes('설치한 뒤 돌아와서 「앱에서 열기」'));
  ok('안드로이드 페이지에 아이폰 참여 링크는 없다', !an2.body.includes(JI));
  const io2 = await page('/i/' + CODE, { ua: UA.ios });
  const tf = hrefs(io2.body).find(x => x.label === 'TestFlight 에서 받기');
  ok('아이폰: "TestFlight 에서 받기" 단추 → 적은 주소', tf && tf.href === JI, tf);
  ok('아이폰: TestFlight 앱이 있어야 한다는 한 줄 · 받는 곳', io2.body.includes('TestFlight 앱이 있어야 열려요') &&
     hrefs(io2.body).some(x => /^https:\/\/apps\.apple\.com\/app\/testflight\/id\d+$/.test(x.href)));
  ok('아이폰 페이지에 안드로이드 참여 링크는 없다', !io2.body.includes(JA) && !io2.body.includes(JG));
  const d2 = await page('/i/' + CODE, { ua: UA.desktop });
  ok('컴퓨터: 둘 다 적힌 대로', [JA, JG, JI].every(u => hrefs(d2.body).some(x => x.href === u)) &&
     !d2.body.includes('곧 열려요'));
  const t2 = tool(['--join-android-group=none', '--join-ios=none']);
  const an3 = await page('/i/' + CODE, { ua: UA.android });
  const l3 = hrefs(an3.body);
  ok('그룹이 없으면 그 단계를 빼고 ① 테스트 참여 → ② Google Play 에서 설치', t2.code === 0 &&
     l3.findIndex(x => x.label === '① 테스트 참여' && x.href === JA) >= 0 &&
     l3.findIndex(x => x.label === '② Google Play 에서 설치' && x.href === playOf(CODE)) >
       l3.findIndex(x => x.label === '① 테스트 참여') &&
     !an3.body.includes('③') && !an3.body.includes('구글 그룹') && !an3.body.includes(JG),
     l3.map(x => x.label));
  const d3 = await page('/i/' + CODE, { ua: UA.desktop });
  ok('컴퓨터: 적힌 안드로이드만 단추, 아이폰은 "곧 열려요"', hrefs(d3.body).some(x => x.href === JA) &&
     d3.body.includes('아이폰은 곧 열려요') && !d3.body.includes('안드로이드는 곧 열려요'));
  const off = tool(['--testing=off']);
  const v = await api('GET', '/version');
  const an4 = await page('/i/' + CODE, { ua: UA.android });
  const io4 = await page('/i/' + CODE, { ua: UA.ios });
  ok('시험 기간을 끄면 /api/version testing:false', off.code === 0 && v.json.testing === false, [off.code, v.json.testing]);
  ok('시험 기간이 끝나면 안드로이드는 추천인 붙은 Google Play 가게 주소 · 참여 링크는 안 보임',
     hrefs(an4.body).some(x => x.label === 'Google Play 에서 받기' && x.href === playOf(CODE)) && !an4.body.includes(JA) &&
     !an4.body.includes(JG), hrefs(an4.body).map(x => x.label + ' ' + x.href));
  ok('시험 기간이 끝나면 아이폰은 App Store (' + APPSTORE + ')',
     hrefs(io4.body).some(x => x.label === 'App Store 에서 받기' && x.href === APPSTORE) &&
     !io4.body.includes('곧 열려요') && !io4.body.includes(JI), hrefs(io4.body).map(x => x.label + ' ' + x.href));
  const d4 = await page('/i/' + CODE, { ua: UA.desktop });
  ok('시험 기간이 끝나면 컴퓨터: 두 가게 모두 (참여 링크 없음)', hrefs(d4.body).some(x => x.href === playOf(CODE)) &&
     hrefs(d4.body).some(x => x.href === APPSTORE) && ![JA, JG, JI].some(u => d4.body.includes(u)));
  const on = tool(['--testing=on']);
  ok('다시 켜면 참여 링크로', on.code === 0 && (await page('/i/' + CODE, { ua: UA.android })).body.includes(JA));

  /* 아이폰만 먼저 App Store — 애플 심사를 지나 App Store 에 나갔는데 안드로이드는 아직 플레이 비공개
     테스트(프로덕션 없음)인 때. 주인은 시험 기간을 켠 채 도구로 앱스토어 판만 적습니다(--appstore).
     아이폰은 App Store 로, 안드로이드는 참여 단계 그대로(글자 하나 다르지 않게)여야 합니다. */
  tool(['--join-android-group=' + JG, '--join-ios=' + JI]);
  const asAnB = await page('/i/' + CODE, { ua: UA.android, headers: fwd });
  const asNaB = await page('/i/' + CODE + '?noapp=1', { ua: UA.android, headers: fwd });
  const asSet = tool(['--appstore=0.2.20']);
  const asV = await api('GET', '/version');
  ok('도구로 앱스토어 판을 적는다 (--appstore=0.2.20 · 시험 기간은 켠 채)', asSet.code === 0 &&
     asV.json.latest && asV.json.latest.appstore === '0.2.20' && asV.json.testing === true,
     [asSet.code, asV.json.latest, asV.json.testing, asSet.out.slice(-300)]);
  const asIo = await page('/i/' + CODE, { ua: UA.ios, headers: fwd });
  const asIoL = hrefs(asIo.body);
  ok('아이폰: "App Store 에서 받기" (' + APPSTORE + ') · 설치 단추(data-install) · TestFlight 는 없다',
     asIoL.some(x => x.label === 'App Store 에서 받기' && x.href === APPSTORE && /\sdata-install[\s>]/.test(x.tag)) &&
     !asIo.body.includes('TestFlight') && !asIo.body.includes(JI) && !asIo.body.includes('곧 열려요'),
     asIoL.map(x => x.label + ' ' + x.href));
  ok('아이폰: 저절로 갈 곳(data-later)도 App Store · "앱에서 열기" 는 그대로 mybody://invite/<코드>',
     bodyData(asIo.body)['data-later'] === APPSTORE && (openBtn(asIo.body) || {}).href === 'mybody://invite/' + CODE &&
     asIo.body.includes('설치한 뒤 돌아와서 「앱에서 열기」'), bodyData(asIo.body));
  const asNi = hrefs((await page('/i/' + CODE + '?noapp=1', { ua: UA.ios })).body);
  ok('아이폰 noapp: App Store 단추 뒤에 "앱에서 열기"', asNi.findIndex(x => x.href === APPSTORE) >= 0 &&
     asNi.findIndex(x => x.label === '앱에서 열기') > asNi.findIndex(x => x.href === APPSTORE), asNi.map(x => x.label));
  const asD = (await page('/i/' + CODE, { ua: UA.desktop })).body;
  const asDi = asD.slice(asD.indexOf('<h3>아이폰</h3>'), asD.indexOf('</section>', asD.indexOf('<h3>아이폰</h3>')));
  const asDa = asD.slice(asD.indexOf('<h3>안드로이드</h3>'), asD.indexOf('<h3>아이폰</h3>'));
  ok('컴퓨터: 아이폰 칸은 App Store 하나 · 안드로이드 칸은 ① 구글 그룹 ② 테스트 참여 ③ 플레이(추천인) 그대로',
     hrefs(asDi).map(x => x.label + ' ' + x.href).join('|') === 'App Store 에서 받기 ' + APPSTORE &&
     hrefs(asDa).map(x => x.href).join(' ') === [JG, JA, playOf(CODE)].join(' ') && !asD.includes(JI),
     [hrefs(asDi).map(x => x.label), hrefs(asDa).map(x => x.label)]);
  ok('안드로이드: 페이지 · ?noapp=1 이 앱스토어 판이 없을 때와 글자 하나 다르지 않다 (fallback 도 ?noapp=1 그대로)',
     (await page('/i/' + CODE, { ua: UA.android, headers: fwd })).body === asAnB.body &&
     (await page('/i/' + CODE + '?noapp=1', { ua: UA.android, headers: fwd })).body === asNaB.body &&
     asAnB.body.includes(JA) && asAnB.body.includes(encodeURIComponent('?noapp=1')));
  tool(['--join-ios=none']);
  const asNo = await page('/i/' + CODE, { ua: UA.ios });
  ok('TestFlight 링크를 지워도 아이폰은 App Store ("곧 열려요" 아님) · "설치한 뒤 돌아와서" 도 그대로',
     hrefs(asNo.body).some(x => x.href === APPSTORE) && !asNo.body.includes('곧 열려요') &&
     bodyData(asNo.body)['data-later'] === APPSTORE && asNo.body.includes('설치한 뒤 돌아와서 「앱에서 열기」'),
     hrefs(asNo.body).map(x => x.label));
  /* App Store 에서 깐 친구가 돌아와 누를 단추 — 참여 링크가 없어도 설치할 곳(App Store)이 있으니 있어야 합니다. */
  const asNoNa = await page('/i/' + CODE + '?noapp=1', { ua: UA.ios });
  const asNoNaL = hrefs(asNoNa.body);
  ok('TestFlight 링크가 없어도 아이폰 noapp: App Store 단추 뒤에 "설치했으면 이 단추로" · "앱에서 열기"',
     asNoNa.body.includes('설치했으면 이 단추로') && asNoNaL.findIndex(x => x.href === APPSTORE) >= 0 &&
     asNoNaL.findIndex(x => x.label === '앱에서 열기') > asNoNaL.findIndex(x => x.href === APPSTORE),
     asNoNaL.map(x => x.label));
  const asClr = tool(['--appstore=none', '--join-ios=' + JI]);
  const asBack = await page('/i/' + CODE, { ua: UA.ios });
  ok('앱스토어 판을 지우면 아이폰은 다시 TestFlight', asClr.code === 0 &&
     hrefs(asBack.body).some(x => x.label === 'TestFlight 에서 받기' && x.href === JI) && !asBack.body.includes(APPSTORE) &&
     bodyData(asBack.body)['data-later'] === JI, hrefs(asBack.body).map(x => x.label));
  /* 안드로이드 참여 링크가 없을 때도 — 위는 참여 링크가 있어 testing 과 상관없이 설치 안내가 붙는 모양이라,
     아이폰 규칙(앱스토어 판)이 안드로이드로 새는지는 여기서만 보입니다. 새면 "곧 열려요" 옆에
     "설치한 뒤 돌아와서" · noapp 의 「앱에서 열기」 가 붙습니다(아직 없는 가게를 전제로). */
  tool(['--join-android=none']);
  const anNoB = await page('/i/' + CODE, { ua: UA.android, headers: fwd });
  const anNoNaB = await page('/i/' + CODE + '?noapp=1', { ua: UA.android, headers: fwd });
  const asOn2 = tool(['--appstore=0.2.20']);
  const anNoA = await page('/i/' + CODE, { ua: UA.android, headers: fwd });
  const anNoNaA = await page('/i/' + CODE + '?noapp=1', { ua: UA.android, headers: fwd });
  ok('안드로이드 참여 링크가 없을 때: 앱스토어 판을 적어도 페이지 · ?noapp=1 이 글자 하나 다르지 않다 ("곧 열려요" 그대로)',
     asOn2.code === 0 && anNoA.body === anNoB.body && anNoNaA.body === anNoNaB.body &&
     anNoB.body.includes('안드로이드는 곧 열려요 — 코드 ' + CODE + ' 를 적어 두세요'), asOn2.out.slice(-300));
  ok('  그리고 "설치한 뒤 돌아와서" · "설치했으면 이 단추로" 가 붙지 않는다',
     ![anNoA, anNoNaA].some(x => x.body.includes('설치한 뒤 돌아와서') || x.body.includes('설치했으면 이 단추로')));
  tool(['--appstore=none', '--join-android=' + JA]);
  tool(['--join-android-group=none', '--join-ios=none']);

  console.log('\n[7] ?noapp=1 — 앱이 없어서 돌아온 경우');
  tool(['--join-android-group=' + JG, '--join-ios=' + JI]);
  const na = await page('/i/' + CODE + '?noapp=1', { ua: UA.android, headers: fwd });
  const nl = hrefs(na.body);
  const flagAt = na.body.indexOf('앱이 없어서 설치 안내로 왔어요');
  ok('"앱이 없어서 설치 안내로 왔어요" 를 맨 앞에', flagAt > 0 && flagAt < na.body.indexOf('class="code"'), flagAt);
  ok('설치 칸을 강조 (card--em)', /<section class="card card--em"><h2>앱이 없나요\?<\/h2>/.test(na.body));
  const iOpen = nl.findIndex(x => x.label === '앱에서 열기'), iJoin = nl.findIndex(x => x.href === JA);
  ok('"앱에서 열기" 는 설치 단추 뒤로 · 주 단추가 아님', iOpen > iJoin && iJoin >= 0 && !/btn--primary/.test(nl[iOpen].tag) &&
     nl[iOpen].href === wantIntent, nl.map(x => x.label));
  ok('설치 단추는 여전히 순서대로', nl.findIndex(x => x.href === JG) < iJoin);
  tool(['--join-android=none']);
  const nb = await page('/i/' + CODE + '?noapp=1', { ua: UA.android });
  ok('참여 링크가 없으면 noapp 에도 "곧 열려요" 만 (헛도는 "앱에서 열기" 없음)',
     nb.body.includes('안드로이드는 곧 열려요') && !openBtn(nb.body), hrefs(nb.body).map(x => x.label));
  const ni = await page('/i/' + CODE + '?noapp=1', { ua: UA.ios });
  ok('아이폰 noapp: TestFlight 단추 뒤에 "앱에서 열기"', (() => {
    const L = hrefs(ni.body);
    return L.findIndex(x => x.href === JI) >= 0 && L.findIndex(x => x.label === '앱에서 열기') > L.findIndex(x => x.href === JI);
  })(), hrefs(ni.body).map(x => x.label));

  console.log('\n[8] 새지 않는다');
  tool(['--join-android=' + JA]);
  let other = randCode();
  while (other === CODE) other = randCode();
  for (const [nm, ua] of [['안드로이드', UA.android], ['아이폰', UA.ios], ['컴퓨터', UA.desktop]]) {
    const mine = await page('/i/' + CODE, { ua });
    const none = await page('/i/' + other, { ua });
    ok(nm + ': 이름 · 아이디가 안 나온다', !mine.body.includes(NAME) && !mine.body.includes(HANDLE));
    ok(nm + ': 있는 코드와 없는 코드의 페이지가 (코드만 빼면) 똑같다',
       mine.status === 200 && none.status === 200 && mine.body.split(CODE).join('#') === none.body.split(other).join('#'));
  }
  ok('로그에 초대 코드가 안 남는다', !out.includes(CODE) && !out.includes(other), out.slice(-300));
  /* 초대 페이지 코드는 DB(api · db)를 부르지 않습니다 — 주석을 뺀 코드에서 봅니다. */
  const srvSrc = fs.readFileSync(path.join(ROOT, 'server', 'server.js'), 'utf8');
  const s0 = srvSrc.indexOf('/* --- 친구 초대 링크'), s1 = srvSrc.indexOf('/* --- 무슨 일이 있었는지');
  const sect = s0 > 0 && s1 > s0 ? srvSrc.slice(s0, s1).replace(/\/\*[\s\S]*?\*\//g, '').replace(/\/\/[^\n]*/g, '') : '';
  ok('초대 페이지 코드는 api · db 를 안 부른다', sect.length > 1000 && !/\b(api|db)\.[a-zA-Z]/.test(sect), sect.length);

  console.log('\n[9] 머리글 · 스크립트는 해시 하나');
  const h = an.headers;
  const csp = h['content-security-policy'] || '';
  ok("CSP: default-src 'none'", /(^|; )default-src 'none'(;|$)/.test(csp), csp);
  ok("CSP: 'unsafe-inline' · 'unsafe-eval' · 'strict-dynamic' · 주소 허락 없음 · frame-ancestors 'none' · base-uri 'none'",
     !/unsafe-inline|unsafe-eval|strict-dynamic|https?:|\*/.test(csp) && /frame-ancestors 'none'/.test(csp) &&
     /base-uri 'none'/.test(csp), csp);
  const styles = [...an.body.matchAll(/<style>([\s\S]*?)<\/style>/g)].map(m => m[1]);
  const sh = styles.length === 1 ? "'sha256-" + crypto.createHash('sha256').update(styles[0], 'utf8').digest('base64') + "'" : '';
  ok('CSP 의 스타일 해시가 페이지의 <style> 과 맞는다 (하나뿐)', sh && csp.includes('style-src ' + sh), [styles.length, sh]);
  const scripts = [...an.body.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script>/gi)];
  const jh = scripts.length === 1 ? "'sha256-" + crypto.createHash('sha256').update(scripts[0][2], 'utf8').digest('base64') + "'" : '';
  ok('CSP 의 스크립트 해시가 페이지의 <script> 와 글자 그대로 맞는다 (하나뿐 · 속성 없음 · 그 해시만)',
     jh && scripts[0][1] === '' && csp.split('; ').includes('script-src ' + jh),
     [scripts.length, jh, (/script-src [^;]*/.exec(csp) || [])[0]]);
  ok('스크립트는 코드 · 기종이 달라도 한 글자도 안 바뀐다 (해시 하나로 충분)',
     [io2.body, d2.body, na.body].every(b => scriptOf(b) === scripts[0][2]) && scripts[0][2].length > 500);
  ok('스크립트 안에 </ · <!-- 가 없다 (페이지를 끊지 않음)', scripts.length === 1 && !scripts[0][2].includes('</') &&
     !scripts[0][2].includes('<!--'));
  ok('스크립트에 CR(\\r) 이 없다 (줄바꿈은 LF — [15])', scripts.length === 1 && !scripts[0][2].includes('\r'));
  LF_SCRIPT = scripts.length === 1 ? scripts[0][2] : '';
  for (const [nm, body] of [['안드로이드', an.body], ['아이폰', io2.body], ['컴퓨터', d2.body], ['noapp', na.body],
                            ['404', (await page('/i/nope')).body]]) {
    const html = body.replace(/<script>[\s\S]*?<\/script>/, '');
    ok(nm + ': 스크립트 밖에 <script> · on…= 핸들러 · javascript: · style="…" 없음', !/<script/i.test(html) &&
       !/\son[a-z]+\s*=/i.test(html) && !/javascript:/i.test(body) && !/\sstyle=/i.test(html));
    ok(nm + ': 밖의 자원을 안 부른다 (img · link · iframe 은 같은 서버만)',
       ![...body.matchAll(/<(img|link|iframe|source|video|audio)\b[^>]*\b(src|href)="([^"]*)"/gi)]
         .some(m => /^(https?:)?\/\//i.test(m[3])));
    ok(nm + ': 밖으로 가는 링크는 전부 rel="noreferrer"',
       hrefs(body).filter(x => /^https?:/.test(x.href)).every(x => /rel="noreferrer"/.test(x.tag)));
  }
  ok('X-Content-Type-Options: nosniff', h['x-content-type-options'] === 'nosniff');
  ok('Cache-Control: no-store', h['cache-control'] === 'no-store');
  ok('Referrer-Policy: no-referrer (+ 메타)', h['referrer-policy'] === 'no-referrer' &&
     meta(an.body, 'name', 'referrer') === 'no-referrer');
  ok('X-Frame-Options: DENY', h['x-frame-options'] === 'DENY');
  /* 웹 앱(prototype/sw.js)의 서비스워커는 200 을 Cache Storage 에 담고 물음표 뒤를 빼고 찾습니다.
     담기면 fallback(?noapp=1)이 캐시의 보통 페이지로 나옵니다 — 크롬에서 실제로 그랬습니다.
     Cache.put 은 Vary: * 를 거절하므로 이 머리글이 있으면 담기지 않습니다. */
  ok('Vary: * (서비스워커 캐시에 안 담김)', h.vary === '*', h.vary);
  const nf = await page('/i/ABCD0000');
  ok('404 에는 스크립트가 없다 (할 일이 없음)', !/<script/i.test(nf.body) && /<body>/.test(nf.body));
  ok('404 도 같은 머리글', nf.headers['content-security-policy'] === csp && nf.headers['cache-control'] === 'no-store' &&
     nf.headers['x-content-type-options'] === 'nosniff' && nf.headers['referrer-policy'] === 'no-referrer' &&
     nf.headers.vary === '*');

  console.log('\n[10] 절대 주소 (og:image · og:url · fallback)');
  ok('믿는 프록시(TRUST_PROXY)의 X-Forwarded-* 로 https 절대 주소',
     meta(an.body, 'property', 'og:image') === base + '/assets/icon-512.png' &&
     meta(an.body, 'property', 'og:url') === base + '/i/' + CODE, [meta(an.body, 'property', 'og:image')]);
  const img = await fetch(`http://127.0.0.1:${PORT}/assets/icon-512.png`);
  ok('og:image 그림은 이 서버가 실제로 내보내는 것 (200 image/png)', img.status === 200 &&
     img.headers.get('content-type') === 'image/png');
  const plain = await page('/i/' + CODE, { ua: UA.android, headers: { Host: 'phone-lan.local:8080' } });
  ok('X-Forwarded-* 가 없으면 Host 로 (http)', meta(plain.body, 'property', 'og:image') === 'http://phone-lan.local:8080/assets/icon-512.png',
     meta(plain.body, 'property', 'og:image'));
  const evil = await page('/i/' + CODE, { ua: UA.android,
    headers: { Host: 'evil.example"><script>alert(1)</script>', 'X-Forwarded-Host': 'x" onload="alert(1)' } });
  ok('이상한 Host · X-Forwarded-Host → 주소를 안 박음 (og:image · og:url · fallback 없음) · 그대로 찍지 않음',
     evil.status === 200 && scriptOf(evil.body) === scriptOf(an.body) &&
     !/<script|onload|evil\.example/.test(evil.body.replace('<script>' + scriptOf(an.body) + '</script>', '')) &&
     meta(evil.body, 'property', 'og:image') === null &&
     meta(evil.body, 'property', 'og:url') === null && openBtn(evil.body) &&
     openBtn(evil.body).href === 'intent://invite/' + CODE + '#Intent;scheme=mybody;package=' + PKG + ';end',
     evil.body.slice(0, 900));
  ok('이상한 Host 면 담을 글에도 주소를 안 싣는다 ("Mybody 초대 <코드>" 만) · 저절로 가는 intent 도 fallback 없음',
     bodyData(evil.body)['data-copy'] === 'Mybody 초대 ' + CODE &&
     bodyData(evil.body)['data-intent'] === openBtn(evil.body).href, bodyData(evil.body));
  await stop();

  /* 둘째 서버: 설정의 공개 주소(ORIGIN) — launch.js 가 터널 주소로 채우는 값. launch.js 는
     TRUST_PROXY 도 같이 켭니다. */
  const ORIGIN = 'https://mybody-origin.example.ts.net';
  const fbOf = b => 'intent://invite/' + CODE + '#Intent;scheme=mybody;package=' + PKG + ';S.browser_fallback_url=' +
                    encodeURIComponent(b + '/i/' + CODE + '?noapp=1') + ';end';
  boot({ ORIGIN: ORIGIN + '/', TRUST_PROXY: '1' });
  ok('서버(ORIGIN) 가 뜬다', await waitUp(), out.slice(-300));
  const o = await page('/i/' + CODE, { ua: UA.android, headers: { Host: 'localhost:' + PORT } });
  ok('이 컴퓨터 자신(localhost)으로 열면 ORIGIN — og:image 는 https 절대 주소',
     meta(o.body, 'property', 'og:image') === ORIGIN + '/assets/icon-512.png', meta(o.body, 'property', 'og:image'));
  ok('fallback 도 ORIGIN 으로', (openBtn(o.body) || {}).href === fbOf(ORIGIN), (openBtn(o.body) || {}).href);
  /* 프록시가 X-Forwarded-Proto 를 안 실어도, ORIGIN 과 같은 이름이면 https 인 줄 압니다. */
  const o2 = await page('/i/' + CODE, { ua: UA.android, headers: { Host: 'mybody-origin.example.ts.net' } });
  ok('ORIGIN 과 같은 이름으로 오면 ORIGIN (https)', (openBtn(o2.body) || {}).href === fbOf(ORIGIN),
     (openBtn(o2.body) || {}).href);
  /* ORIGIN 이 옛 주소(바뀐 터널 · 잘못 적은 공개 주소)여도, 받은 사람은 **지금 연 주소**로 돌아와야
     설치 안내를 봅니다. 옛 ORIGIN 으로 보내면 앱이 없는 사람이 엉뚱한 곳에 떨어집니다. */
  const NOW = 'https://mybody-now.example.ts.net';
  const o3 = await page('/i/' + CODE, { ua: UA.android, headers: { Host: 'mybody-now.example.ts.net',
    'X-Forwarded-Host': 'mybody-now.example.ts.net', 'X-Forwarded-Proto': 'https' } });
  ok('ORIGIN 과 다른 주소로 열었으면 그 주소로 — fallback · og:url · og:image',
     (openBtn(o3.body) || {}).href === fbOf(NOW) && meta(o3.body, 'property', 'og:url') === NOW + '/i/' + CODE &&
     meta(o3.body, 'property', 'og:image') === NOW + '/assets/icon-512.png' && !o3.body.includes('mybody-origin'),
     [(openBtn(o3.body) || {}).href, meta(o3.body, 'property', 'og:url')]);
  const o4 = await page('/i/' + CODE, { ua: UA.android, headers: { Host: 'x"><b>', 'X-Forwarded-Host': 'y" onload="z' } });
  ok('이상한 Host 면 ORIGIN (그대로 찍지 않음)', (openBtn(o4.body) || {}).href === fbOf(ORIGIN) &&
     !/onload|<b>/.test(o4.body), (openBtn(o4.body) || {}).href);
  await stop();

  /* 셋째 서버: 프록시를 안 믿음(TRUST_PROXY 꺼짐) — X-Forwarded-* 는 아무나 적어 보낼 수 있습니다. */
  boot({});
  ok('서버(TRUST_PROXY 꺼짐) 가 뜬다', await waitUp(), out.slice(-300));
  const u = await page('/i/' + CODE, { ua: UA.android, headers: { Host: 'mybody.lan:8080', 'X-Forwarded-Host': 'attacker.example',
                                                                 'X-Forwarded-Proto': 'https' } });
  ok('프록시를 안 믿으면 X-Forwarded-* 무시 → Host (http)',
     meta(u.body, 'property', 'og:image') === 'http://mybody.lan:8080/assets/icon-512.png' && !u.body.includes('attacker'),
     meta(u.body, 'property', 'og:image'));

  console.log('\n[11] 이스케이프 — 설정의 링크');
  /* 도구는 https 모양만 받고, 서버는 new URL 로 다듬습니다. 그래도 ' & 는 주소에 남습니다. */
  writeCfg({ appJoinAndroid: "https://play.example/a'b?x=1&y=<\"z\">", appJoinIos: 'https://tf.example/j?a=1&b=2' });
  const e1 = await page('/i/' + CODE, { ua: UA.desktop });
  ok("' & < \" 가 날것으로 안 박힌다", e1.status === 200 && e1.body.includes('href="https://play.example/a&#39;b?x=1&amp;y=%3C%22z%22%3E"') &&
     !e1.body.includes("a'b") && !e1.body.includes('&y=') && !/<"z">/.test(e1.body),
     hrefs(e1.body).map(x => x.tag));
  ok('풀어 읽으면 적은 주소 그대로', hrefs(e1.body).some(x => x.href === 'https://play.example/a\'b?x=1&y=%3C%22z%22%3E') &&
     hrefs(e1.body).some(x => x.href === 'https://tf.example/j?a=1&b=2'));
  /* 아이폰은 같은 링크를 <body data-later="…"> 에도 싣습니다 — 속성에서도 날것이면 안 됩니다. */
  writeCfg({ appJoinIos: "https://tf.example/j'q?a=1&b=<\"x\">" });
  const e4 = await page('/i/' + CODE, { ua: UA.ios });
  const e4tag = (/<body\b[^>]*>/.exec(e4.body) || [''])[0];
  ok("data-later 에도 ' & < \" 가 날것으로 안 박힌다 · 풀면 적은 주소", e4tag.includes('data-later="https://tf.example/j&#39;q?a=1&amp;b=%3C%22x%22%3E"') &&
     bodyData(e4.body)['data-later'] === "https://tf.example/j'q?a=1&b=%3C%22x%22%3E" && !/<"x">|j'q/.test(e4tag), e4tag);
  writeCfg({ appJoinAndroid: 'javascript:alert(1)', appJoinIos: 'http://tf.example/x' });
  const e2 = await page('/i/' + CODE, { ua: UA.desktop });
  ok('https 가 아닌 링크는 버린다 → "곧 열려요"', !/javascript:|http:\/\/tf/.test(e2.body) &&
     e2.body.includes('안드로이드는 곧 열려요') && e2.body.includes('아이폰은 곧 열려요'));
  fs.writeFileSync(CFG, '{ 망가진 설정');
  const e3 = await page('/i/' + CODE, { ua: UA.android });
  ok('설정 파일이 망가져도 페이지는 뜬다 (코드 · 앱 열기는 그대로, 설치는 "곧 열려요")', e3.status === 200 &&
     e3.body.includes('<p class="code">' + CODE + '</p>') && !!openBtn(e3.body) && e3.body.includes('곧 열려요'));
  fs.rmSync(CFG, { force: true });
  await stop();

  /* 넷째 서버: 터널 뒤(TRUST_PROXY) — 실제 운영과 같은 https 주소로 앱 링크 파일 · 스크립트를 봅니다. */
  boot({ TRUST_PROXY: '1' });
  ok('서버(앱 링크 · 스크립트) 가 뜬다', await waitUp(), out.slice(-300));
  await wellKnownFromConfig();
  await scriptBehaviour(CODE);
  await noJsFallback(CODE);
  await stop();

  /* 다섯째 서버: 환경변수가 설정 파일을 이기고 · 내보내는 폴더의 같은 이름 파일이 못 가로챈다. */
  await wellKnownEnvAndShadow();

  /* 여섯째 서버: server.js 를 CRLF 로 읽힌 채로. */
  await crlfCheckout(CODE);
}

/* --- [12] 앱 링크 파일 ---------------------------------------------------- */
const AL = '/.well-known/assetlinks.json';
const AA = '/.well-known/apple-app-site-association';
/* 구글 · 애플이 읽는 모양을 **글자 그대로** 적어 둡니다 — 키 순서 · 이름 한 글자만 달라도
   폰은 아무 말 없이 링크를 브라우저로 엽니다. */
const wantAL = fps => '[{"relation":["delegate_permission/common.handle_all_urls"],"target":{"namespace":"android_app",' +
  '"package_name":"' + PKG + '","sha256_cert_fingerprints":' + JSON.stringify(fps) + '}}]';
const wantAA = team => '{"applinks":{"details":[{"appIDs":["' + team + '.' + PKG + '"],' +
  '"components":[{"/":"/i/*","comment":"friend invite"}]}]}}';
const fp = hex => hex.toUpperCase().match(/../g).join(':');

async function wellKnownFromConfig() {
  console.log('\n[12] 앱 링크 파일 (/.well-known) — 설정 파일로');
  fs.rmSync(CFG, { force: true });
  const al0 = await page(AL), aa0 = await page(AA);
  ok('assetlinks.json — 설정이 없어도 200 · 글자 그대로 (업로드 키 하나)', al0.status === 200 &&
     al0.body === wantAL([UPLOAD_CERT]), [al0.status, al0.body]);
  ok('apple-app-site-association — 200 · 글자 그대로 (기본 팀 JT4YLVNKDZ · /i/*)', aa0.status === 200 &&
     aa0.body === wantAA('JT4YLVNKDZ'), [aa0.status, aa0.body]);
  for (const [nm, r] of [['assetlinks.json', al0], ['apple-app-site-association', aa0]]) {
    ok(nm + ': Content-Type application/json · 캐시 짧게(max-age=3600) · Location 없음 · 길이 맞음',
       r.headers['content-type'] === 'application/json' && /(^|, )max-age=3600(,|$)/.test(r.headers['cache-control'] || '') &&
       !r.headers.location && r.headers['content-length'] === String(Buffer.byteLength(r.body)) &&
       r.headers['x-content-type-options'] === 'nosniff', r.headers);
  }
  ok('애플 파일에 확장자 없는 이름 그대로 (…association.json 은 없는 파일)', (await page(AA + '.json')).status === 404);
  const alh = await page(AL, { method: 'HEAD' }), aah = await page(AA, { method: 'HEAD' });
  ok('HEAD → 200 · 본문 없음 · GET 과 같은 길이 · 같은 형식', alh.status === 200 && alh.body === '' &&
     alh.headers['content-length'] === al0.headers['content-length'] && aah.status === 200 && aah.body === '' &&
     aah.headers['content-type'] === 'application/json', [alh.status, aah.status]);
  const alp = await page(AL, { method: 'POST' });
  ok('POST → 405 (Allow: GET, HEAD)', alp.status === 405 && alp.headers.allow === 'GET, HEAD', [alp.status, alp.headers.allow]);
  const enc = await page('/%2Ewell-known/assetlinks.json');
  ok('돌려 적은 이름(%2E)도 같은 대답 (정적 파일로 새지 않음)', enc.status === 200 && enc.body === al0.body, enc.status);
  ok('로그인 없이 · 로그에 안 남음', al0.status === 200 && !out.includes('.well-known'), out.slice(-200));

  /* 설정으로 더하는 지문 — 플레이 앱 서명 키. 사람이 옮겨 적는 값이라 모양이 제각각입니다. */
  const PLAY_SIGN = 'AB:'.repeat(31) + 'CD';
  const bare = crypto.randomBytes(32).toString('hex');             // apksigner 모양: 소문자 · 콜론 없음
  writeCfg({ androidCertSha256: ['SHA256: ' + PLAY_SIGN.toLowerCase(),     // keytool 줄을 통째로
                                 bare,
                                 UPLOAD_CERT.toLowerCase().replace(/:/g, ' : '),  // 업로드 키를 또 — 한 번만
                                 PLAY_SIGN,                                 // 겹침 — 한 번만
                                 'AA:BB:CC', 'ZZ'.repeat(32), 42, null, ''], appleTeamId: ' abcde12345 ' });
  const al1 = await page(AL), aa1 = await page(AA);
  let fps1 = null; try { fps1 = JSON.parse(al1.body)[0].target.sha256_cert_fingerprints; } catch (e) {}
  ok('설정(배열)의 지문을 더한다 — 업로드 키가 먼저 · 대문자 콜론 모양 · 겹침은 한 번 · 모양이 틀린 것은 뺌',
     al1.body === wantAL([UPLOAD_CERT, PLAY_SIGN, fp(bare)]), fps1);
  ok('지문은 전부 콜론으로 끊긴 대문자 32덩이', Array.isArray(fps1) &&
     fps1.every(x => /^([0-9A-F]{2}:){31}[0-9A-F]{2}$/.test(x)), fps1);
  await page(AL);                  // 한 번 더 받아도
  await wait(300);                 // (자식 서버의 출력이 파이프로 건너올 틈)
  const warned = (out.match(/androidCertSha256 에 SHA-256 지문 모양이 아닌 값/g) || []).length;
  ok('모양이 틀린 지문(넷)은 서버 로그에 값마다 한 번만 말한다', warned === 4, [warned, out.slice(-600)]);
  ok('설정의 팀 ID (앞뒤 공백 · 소문자는 다듬음)', aa1.body === wantAA('ABCDE12345'), aa1.body);
  writeCfg({ androidCertSha256: PLAY_SIGN.toLowerCase() + ' , ' + bare.toUpperCase() + ',', appleTeamId: 'NOT-A-TEAM' });
  const al2 = await page(AL), aa2 = await page(AA);
  ok('쉼표로 이은 글자도 받는다', al2.body === wantAL([UPLOAD_CERT, PLAY_SIGN, fp(bare)]), al2.body);
  ok('모양이 틀린 팀 ID 는 기본값으로 (빈 appIDs 를 내지 않음)', aa2.body === wantAA('JT4YLVNKDZ'), aa2.body);
  /* 윈도우 PowerShell 5 로 고친 설정 파일은 앞에 BOM 이 붙습니다 — 그래도 적은 값이 먹어야 합니다. */
  fs.writeFileSync(CFG, '\uFEFF' + JSON.stringify({ androidCertSha256: [PLAY_SIGN], appleTeamId: 'BOMTEAM123' }, null, 2) + '\r\n');
  const alb = await page(AL), aab = await page(AA);
  ok('설정 파일 앞에 BOM(\\uFEFF) · 끝에 CRLF 가 있어도 적은 지문 · 팀 ID 가 먹는다',
     alb.body === wantAL([UPLOAD_CERT, PLAY_SIGN]) && aab.body === wantAA('BOMTEAM123'), [alb.body, aab.body]);
  writeCfg({ androidCertSha256: { x: 1 }, appleTeamId: 12345 });
  const al3 = await page(AL), aa3 = await page(AA);
  ok('이상한 타입이면 기본값만 (업로드 키 · 기본 팀)', al3.body === wantAL([UPLOAD_CERT]) && aa3.body === wantAA('JT4YLVNKDZ'),
     [al3.body, aa3.body]);
  fs.writeFileSync(CFG, '{ 망가진 설정');
  const al4 = await page(AL), aa4 = await page(AA);
  ok('설정 파일이 망가져도 200 · 기본값 (업로드 키 · 기본 팀은 그래도 맞음)', al4.status === 200 && aa4.status === 200 &&
     al4.body === wantAL([UPLOAD_CERT]) && aa4.body === wantAA('JT4YLVNKDZ'), [al4.status, aa4.status]);
  fs.rmSync(CFG, { force: true });
}

async function wellKnownEnvAndShadow() {
  console.log('\n[12-2] 앱 링크 파일 — 환경변수가 먼저 · 정적 파일이 못 가로챔');
  const st = path.join(TMP, 'static');
  fs.mkdirSync(path.join(st, '.well-known'), { recursive: true });
  fs.writeFileSync(path.join(st, 'index.html'), '<!doctype html><title>x</title>');
  fs.writeFileSync(path.join(st, '.well-known', 'assetlinks.json'), '[{"SHADOW":1}]');
  fs.writeFileSync(path.join(st, '.well-known', 'apple-app-site-association'), '{"SHADOW":1}');
  writeCfg({ androidCertSha256: ['CD:'.repeat(31) + 'EF'], appleTeamId: 'FILETEAM01' });
  const envHex = 'ab'.repeat(32);
  boot({ STATIC: st, ANDROID_CERT_SHA256: envHex, APPLE_TEAM_ID: 'envteam999' });
  ok('서버(환경변수 · 가짜 정적 파일) 가 뜬다', await waitUp(), out.slice(-300));
  const al = await page(AL), aa = await page(AA), alEnc = await page('/%2Ewell-known/assetlinks.json');
  ok('환경변수 ANDROID_CERT_SHA256 이 설정 파일을 이긴다 (다듬어서 · 업로드 키는 그대로 먼저)',
     al.body === wantAL([UPLOAD_CERT, fp(envHex)]), al.body);
  ok('환경변수 APPLE_TEAM_ID 가 설정 파일을 이긴다 (대문자로)', aa.body === wantAA('ENVTEAM999'), aa.body);
  ok('내보내는 폴더의 같은 이름 파일이 대답을 가로채지 못한다 (돌려 적은 이름도)',
     ![al, aa, alEnc].some(r => r.body.includes('SHADOW')) && alEnc.body === al.body, [al.body.slice(0, 60), aa.body.slice(0, 60)]);
  ok('같은 폴더의 다른 정적 파일은 그대로 나간다', (await page('/')).body.includes('<title>x</title>'));
  fs.rmSync(CFG, { force: true });
  await stop();
}

/* --- [13] 스크립트 — 가짜 브라우저에서 ------------------------------------- */
async function scriptBehaviour(CODE) {
  console.log('\n[13] 스크립트 — 가짜 브라우저에서 실제로 돌려 봄');
  const HOST = 'mybody-js.example.ts.net';
  const SELF = 'https://' + HOST + '/i/' + CODE;
  const fwd = { 'X-Forwarded-Proto': 'https', 'X-Forwarded-Host': HOST };
  const pg = (q, ua) => page('/i/' + CODE + (q || ''), { ua, headers: fwd });
  const JA = 'https://play.google.com/apps/testing/' + PKG;
  const JG = 'https://groups.google.com/g/mybody-testers';
  const JI = 'https://testflight.apple.com/join/AbCdEf12';
  const COPY = 'Mybody 초대 ' + CODE + ' ' + SELF;
  const fallbackOf = href => { const m = /;S\.browser_fallback_url=([^;]*);end$/.exec(href || ''); return m ? m[1] : null; };

  writeCfg({ appJoinAndroid: JA, appJoinAndroidGroup: JG, appJoinIos: JI });

  /* 카카오톡 — 앱 링크가 안 먹는 앱 안 브라우저. 곧바로 기본 브라우저로 넘깁니다. */
  const HREF = SELF + '?noapp=1&from=kakao';
  const KAKAO = 'kakaotalk://web/openExternal?url=https%3A%2F%2F' + HOST + '%2Fi%2F' + CODE + '%3Fnoapp%3D1%26from%3Dkakao';
  for (const [nm, ua] of [['카카오톡(안드로이드)', UA.kakaoAndroid], ['카카오톡(아이폰)', UA.kakaoIos]]) {
    const k = await pg('', ua);
    const d = bodyData(k.body);
    ok(nm + ': data-inapp="kakao" · 저절로 앱 부르기(intent) · 가게로 가기(later) 는 없음',
       d['data-inapp'] === 'kakao' && !('data-intent' in d) && !('data-later' in d), d);
    const r = runScript(k.body, { href: HREF });
    ok(nm + ': 열리자마자 kakaotalk://web/openExternal?url=<지금 주소를 인코딩> 로 (location.replace)',
       !r.error && r.nav.length === 1 && r.nav[0][0] === 'replace' && r.nav[0][1] === KAKAO, [r.error && String(r.error), r.nav]);
    const q = r.nav[0] && r.nav[0][1].slice('kakaotalk://web/openExternal?url='.length);
    ok(nm + ': 실은 주소는 : / ? & = 가 날것으로 없고 풀면 지금 주소 그대로',
       q && !/[:/?&=]/.test(q) && decodeURIComponent(q) === HREF, q);
    ok(nm + ': 넘기기가 안 돼도 쓸 수 있게 단추가 그대로 (앱에서 열기 · 설치)',
       !!openBtn(k.body) && hrefs(k.body).some(x => x.href === JI || x.href === JA) && r.timers.length === 0);
    const again = runScript(k.body, { href: HREF, session: r.store });
    ok(nm + ': 같은 탭에서 다시 열면(뒤로 가기) 또 넘기지 않는다', again.nav.length === 0, again.nav);
  }

  /* 그 밖의 앱 안 브라우저 — 넘기는 길이 없어 한 줄로 알려 주고, 저절로는 아무 데도 안 갑니다. */
  const TIP = '오른쪽 위 ⋯ → 다른 브라우저로 열기';
  for (const [nm, ua] of [['인스타그램(안드로이드)', UA.instaAndroid], ['인스타그램(아이폰)', UA.instaIos],
                          ['페이스북', UA.fbIos], ['라인', UA.lineAndroid], ['네이버', UA.naverIos]]) {
    const p2 = await pg('', ua);
    const d = bodyData(p2.body);
    const at = p2.body.indexOf(TIP);
    const r = runScript(p2.body);
    ok(nm + ': "' + TIP + '" 을 단추 위에 · 저절로 아무 데도 안 감', at > 0 && at < p2.body.indexOf('class="btn') &&
       !('data-inapp' in d) && !('data-intent' in d) && !('data-later' in d) && r.nav.length === 0 && r.timers.length === 0,
       [at, d, r.nav]);
  }
  for (const [nm, ua] of [['안드로이드', UA.android], ['아이폰', UA.ios], ['컴퓨터', UA.desktop]]) {
    ok(nm + ' 보통 브라우저에는 그 한 줄이 없다', !(await pg('', ua)).body.includes(TIP));
  }

  /* 안드로이드 — 시험 기간: fallback 은 이 페이지 + ?noapp=1 */
  const a1 = await pg('', UA.android);
  const d1 = bodyData(a1.body);
  const ob1 = openBtn(a1.body);
  ok('안드로이드(시험 중): data-intent = "앱에서 열기" 단추와 같은 intent · fallback 은 이 페이지 + ?noapp=1',
     ob1 && d1['data-intent'] === ob1.href && decodeURIComponent(fallbackOf(ob1.href) || '') === SELF + '?noapp=1',
     [d1['data-intent'], ob1 && ob1.href]);
  const r1 = runScript(a1.body);
  ok('안드로이드: 열리자마자 그 intent 로 (location.replace — 뒤로 가기가 다시 튕기지 않게)',
     !r1.error && r1.nav.length === 1 && r1.nav[0][0] === 'replace' && r1.nav[0][1] === ob1.href, [r1.error && String(r1.error), r1.nav]);
  ok('안드로이드: 같은 탭에서 다시 열면 또 부르지 않는다', runScript(a1.body, { session: r1.store }).nav.length === 0);
  ok('안드로이드: sessionStorage 를 못 써도 (막힌 브라우저) 그냥 부른다',
     runScript(a1.body, { noStorage: true }).nav.length === 1);
  ok('안드로이드: "앱에서 열기" 단추는 그대로 (크롬이 누름 없이는 막을 수 있음)', ob1 && /btn--primary/.test(ob1.tag));
  for (const q of ['?noapp=1', '?stay=1']) {
    const x = await pg(q, UA.android);
    const rx = runScript(x.body);
    ok('안드로이드 ' + q + ': 저절로 앱을 부르지 않는다', !('data-intent' in bodyData(x.body)) && rx.nav.length === 0, rx.nav);
  }

  /* 아이폰 — 시험 기간: 1.5초 뒤 TestFlight 공개 링크 */
  const i1 = await pg('', UA.ios);
  const di = bodyData(i1.body);
  const line = /<p class="hint" id="later" hidden>([\s\S]*?)<\/p>/.exec(i1.body);
  const stayA = line && hrefs(line[0])[0];
  ok('아이폰(시험 중): data-later = TestFlight 공개 링크 · "앱에서 열기" = mybody://invite/<코드>',
     di['data-later'] === JI && (openBtn(i1.body) || {}).href === 'mybody://invite/' + CODE, di);
  ok('아이폰: "앱이 없으면 설치 페이지로 가요…" 줄 + "여기 있기"(/i/<코드>?stay=1) — 처음엔 숨김',
     line && line[1].startsWith('앱이 없으면 설치 페이지로 가요…') && stayA && stayA.label === '여기 있기' &&
     stayA.href === '/i/' + CODE + '?stay=1', line && line[0]);
  const ri = runScript(i1.body);
  ok('아이폰: 스크립트가 그 줄을 켠다 · 곧바로 가지는 않는다', !ri.error && ri.later && ri.later.hidden === false &&
     ri.nav.length === 0, [ri.error && String(ri.error), ri.later, ri.nav]);
  ri.tick(1400);
  ok('아이폰: 1.4초까지는 그대로', ri.nav.length === 0);
  ri.tick(1500);
  ok('아이폰: 1.5초 뒤 설치 페이지로 (TestFlight)', ri.nav.length === 1 && ri.nav[0][0] === 'href' && ri.nav[0][1] === JI, ri.nav);
  ok('아이폰: 가면서 "설치 페이지로 가요…" 줄을 숨긴다 (다른 앱에서 돌아왔을 때 지난 예고가 안 남게)',
     ri.later.hidden === true, ri.later);
  const rt = runScript(i1.body);
  rt.touch('touchstart');
  rt.tick(1500);
  ok('아이폰: 그 사이에 화면을 누르면 안 간다 (줄도 다시 숨김)', rt.nav.length === 0 && rt.later.hidden === true, rt.nav);
  const rk = runScript(i1.body);
  rk.touch('keydown');
  rk.tick(1500);
  ok('아이폰: 키를 눌러도 안 간다', rk.nav.length === 0);
  const rh = runScript(i1.body, { hidden: true });
  rh.tick(1500);
  ok('아이폰: 화면이 가려졌으면(다른 앱 · 탭으로 감) 안 간다', rh.nav.length === 0, rh.nav);
  const r2 = runScript(i1.body, { session: ri.store });
  r2.tick(1500);
  ok('아이폰: 같은 탭에서 다시 열면(뒤로 가기) 또 가지 않는다 · 줄도 숨김', r2.nav.length === 0 && r2.later.hidden === true);
  const st1 = await pg('?stay=1', UA.ios);
  const rs = runScript(st1.body);
  rs.tick(5000);
  ok('아이폰 ?stay=1: 저절로 안 감 · 그 줄도 없음 · 단추는 그대로',
     !('data-later' in bodyData(st1.body)) && !/id="later"/.test(st1.body) && rs.nav.length === 0 &&
     !!openBtn(st1.body) && hrefs(st1.body).some(x => x.href === JI), rs.nav);
  const lo = await page('/i/' + CODE.toLowerCase() + '?stay=1&junk=1');
  ok('소문자 주소 + ?stay=1 → 대문자 주소로 돌려보낼 때 stay 도 싣는다 (다른 쿼리는 뗌)', lo.status === 302 &&
     lo.headers.location === '/i/' + CODE + '?stay=1', lo.headers.location);

  /* 설치 단추 — 초대 글을 담고 간다 (계약 (D)) */
  const dk = await pg('', UA.desktop);
  ok('담을 글 = "Mybody 초대 <코드> https://<주소>/i/<코드>"', bodyData(dk.body)['data-copy'] === COPY, bodyData(dk.body)['data-copy']);
  const rc = runScript(dk.body);
  ok('컴퓨터: 저절로는 아무 데도 안 감', rc.nav.length === 0 && rc.timers.length === 0);
  const labels = rc.anchors.map(a => a.label);
  ok('설치 단추가 전부 잡힌다 (구글 그룹 · 테스트 참여 · 플레이 · TestFlight · TestFlight 앱) · "앱에서 열기" 는 아님',
     [JG, JA, playOf(CODE), JI].every(u => rc.anchors.some(a => a.href === u)) && !labels.includes('앱에서 열기'), labels);
  const b0 = rc.anchors.find(a => a.href === playOf(CODE));
  const prevented = rc.click(b0);
  ok('누르면: 클립보드에 초대 글을 담고(writeText) 기본 이동은 잠시 막음', prevented && rc.clip.length === 1 && rc.clip[0] === COPY, rc.clip);
  await settle();
  ok('담기가 끝나면 그 단추의 주소로 간다', rc.nav.length === 1 && rc.nav[0][0] === 'href' && rc.nav[0][1] === playOf(CODE), rc.nav);
  rc.tick(800);
  ok('시간 제한이 와도 두 번 가지 않는다', rc.nav.length === 1);
  const rf = runScript(dk.body, { clipFail: true });
  rf.click(rf.anchors.find(a => a.href === JI));
  await settle();
  ok('담기가 거절돼도(권한 없음) 그냥 간다', rf.nav.length === 1 && rf.nav[0][1] === JI, rf.nav);
  const rhg = runScript(dk.body, { clipHang: true });
  rhg.click(rhg.anchors[0]);
  await settle();
  const before = rhg.nav.length;
  rhg.tick(800);
  ok('담기가 안 끝나도(허락 창) 0.8초 뒤에는 간다', before === 0 && rhg.nav.length === 1 && rhg.nav[0][1] === rhg.anchors[0].href, rhg.nav);
  const rn = runScript(dk.body, { noClipboard: true });
  ok('클립보드가 없는 브라우저면 막지 않는다 (링크가 알아서 감)', rn.click(rn.anchors[0]) === false && rn.nav.length === 0);
  const rm = runScript(dk.body);
  ok('⌘ · Ctrl 을 누른 채(새 탭)면 막지 않는다 — 담기는 한다', rm.click(rm.anchors[0], { ctrlKey: true }) === false &&
     rm.click(rm.anchors[0], { metaKey: true }) === false && rm.clip.length === 2 && rm.nav.length === 0);
  const ria = runScript(i1.body);
  const tfBtn = ria.anchors.find(a => a.href === JI);
  ria.click(tfBtn);
  await settle();
  ria.tick(1500);
  ok('아이폰: 카운트다운 중 설치 단추를 누르면 그 단추대로 한 번만 (담고 감)', ria.clip[0] === COPY &&
     ria.nav.length === 1 && ria.nav[0][1] === JI, ria.nav);

  /* 아이폰 — 시험 중인데 TestFlight 링크가 없으면: 갈 곳이 없으니 안 간다 */
  writeCfg({ appJoinAndroid: JA });
  const i2 = await pg('', UA.ios);
  const r3 = runScript(i2.body);
  r3.tick(5000);
  ok('아이폰(시험 중 · 링크 없음): 저절로 안 감 · "곧 열려요 — 코드 <코드> 를 적어 두세요"',
     !('data-later' in bodyData(i2.body)) && r3.nav.length === 0 && i2.body.includes('아이폰은 곧 열려요 — 코드 ' + CODE + ' 를 적어 두세요'),
     r3.nav);

  /* 아이폰만 먼저 App Store (시험 기간은 켠 채 앱스토어 판) — 아이폰은 1.5초 뒤 App Store,
     안드로이드는 시험 중 그대로(fallback 은 ?noapp=1 — 아직 없는 플레이 가게로 보내지 않음). */
  writeCfg({ appJoinAndroid: JA, appJoinAndroidGroup: JG, appJoinIos: JI, appLatestAppStore: '0.2.20' });
  const i4 = await pg('', UA.ios);
  const r6 = runScript(i4.body);
  r6.tick(1500);
  ok('아이폰(시험 중 · 앱스토어 판): data-later = App Store · 1.5초 뒤 App Store (' + APPSTORE + ')',
     bodyData(i4.body)['data-later'] === APPSTORE && r6.nav.length === 1 && r6.nav[0][0] === 'href' &&
     r6.nav[0][1] === APPSTORE, r6.nav);
  ok('안드로이드(시험 중 · 앱스토어 판): 페이지가 글자 하나 다르지 않다 — intent 의 fallback 은 이 페이지 + ?noapp=1',
     (await pg('', UA.android)).body === a1.body);
  const dk2 = await pg('', UA.desktop);
  const rc2 = runScript(dk2.body);
  const asBtn = rc2.anchors.find(a => a.href === APPSTORE);
  ok('컴퓨터(시험 중 · 앱스토어 판): App Store 도 설치 단추 — 누르면 초대 글을 담고 감 · TestFlight 단추는 없음',
     !!asBtn && rc2.click(asBtn) && rc2.clip[0] === COPY && !rc2.anchors.some(a => a.href === JI) &&
     rc2.anchors.some(a => a.href === playOf(CODE)), rc2.anchors.map(a => a.label));
  await settle();
  ok('담기가 끝나면 App Store 로', rc2.nav.length === 1 && rc2.nav[0][1] === APPSTORE, rc2.nav);

  /* 정식 출시 뒤 (testing 꺼짐) */
  writeCfg({ appJoinAndroid: JA, appJoinAndroidGroup: JG, appJoinIos: JI, appTesting: false });
  const a2 = await pg('', UA.android);
  const ob2 = openBtn(a2.body);
  const fb2 = fallbackOf(ob2 && ob2.href);
  ok('안드로이드(출시 뒤): fallback 은 추천인 붙은 플레이 가게 — 앱이 없으면 한 번에 설치로',
     fb2 && decodeURIComponent(fb2) === playOf(CODE), fb2);
  ok('fallback 인코딩: : / ? & = 가 날것으로 없고, 추천인은 두 번 인코딩돼 실림 (referrer%3Dinvite%253D<코드>)',
     fb2 && !/[:/?&=]/.test(fb2) && fb2.includes('referrer%3Dinvite%253D' + CODE), fb2);
  const r4 = runScript(a2.body);
  ok('안드로이드(출시 뒤): 열리자마자 그 intent 로', r4.nav.length === 1 && r4.nav[0][0] === 'replace' &&
     r4.nav[0][1] === ob2.href && bodyData(a2.body)['data-intent'] === ob2.href, r4.nav);
  const i3 = await pg('', UA.ios);
  const r5 = runScript(i3.body);
  r5.tick(1500);
  ok('아이폰(출시 뒤): 1.5초 뒤 App Store (' + APPSTORE + ')', bodyData(i3.body)['data-later'] === APPSTORE &&
     r5.nav.length === 1 && r5.nav[0][1] === APPSTORE, r5.nav);
  const rs2 = runScript((await pg('?stay=1', UA.ios)).body);
  rs2.tick(5000);
  ok('아이폰(출시 뒤) ?stay=1: 안 감', rs2.nav.length === 0);
  fs.rmSync(CFG, { force: true });
}

/* --- [14] 스크립트가 꺼져 있어도 ------------------------------------------- */
async function noJsFallback(CODE) {
  console.log('\n[14] 스크립트가 꺼져 있어도 — 단추는 진짜 주소');
  const JA = 'https://play.google.com/apps/testing/' + PKG;
  const JI = 'https://testflight.apple.com/join/AbCdEf12';
  const fwd = { 'X-Forwarded-Proto': 'https', 'X-Forwarded-Host': 'mybody-nojs.example.ts.net' };
  for (const testing of [true, false]) {
    writeCfg({ appJoinAndroid: JA, appJoinAndroidGroup: 'https://groups.google.com/g/x', appJoinIos: JI, appTesting: testing });
    for (const [nm, ua] of [['안드로이드', UA.android], ['아이폰', UA.ios], ['컴퓨터', UA.desktop], ['카카오톡', UA.kakaoIos]]) {
      const p2 = await page('/i/' + CODE, { ua, headers: fwd });
      const L = hrefs(p2.body);
      const inst = L.filter(x => /\sdata-install[\s>]/.test(x.tag));
      ok((testing ? '시험 중 · ' : '출시 뒤 · ') + nm + ': 설치 단추는 전부 https 주소 (스크립트 없이 눌러도 감)',
         inst.length > 0 && inst.every(x => /^https:\/\/[^\s"]+$/.test(x.href)), inst.map(x => x.href));
      ok((testing ? '시험 중 · ' : '출시 뒤 · ') + nm + ': 모든 링크에 주소가 있다 (intent · mybody · https · /i/…)',
         L.every(x => /^(https:\/\/|intent:\/\/invite\/|mybody:\/\/invite\/|\/i\/[A-Z2-9]{8}\?stay=1$)/.test(x.href)), L.map(x => x.href));
      if (nm === '아이폰') {
        ok((testing ? '시험 중' : '출시 뒤') + ' · 아이폰: "설치 페이지로 가요…" 는 HTML 에서 숨김(hidden) — 스크립트가 없으면 거짓말이 됨',
           /<p class="hint" id="later" hidden>/.test(p2.body) && p2.body.includes('[hidden]{display:none!important}'));
      }
    }
  }
  fs.rmSync(CFG, { force: true });
}

/* --- [15] 윈도우 줄바꿈 ---------------------------------------------------- */
/* 서버를 띄우는 노트북은 윈도우이고, Git for Windows 의 기본값(core.autocrlf=true)은 파일을
   CRLF 로 꺼냅니다. 스크립트는 함수의 toString() 이라 그 \r\n 이 그대로 실리는데, 브라우저는
   HTML 을 읽을 때 \r\n 을 \n 으로 바꾼 **뒤에** 해시를 잽니다 — 어긋나면 CSP 가 스크립트를 조용히
   막아 저절로 하는 일이 전부 멈춥니다. 여기서는 노드가 server.js 를 읽는 순간 줄바꿈을 CRLF 로
   바꿔(-r 로 미리 읽는 파일) 윈도우에서 꺼낸 것과 같게 띄웁니다. */
async function crlfCheckout(CODE) {
  console.log('\n[15] 윈도우 줄바꿈 (CRLF 로 읽힌 server.js)');
  const pre = path.join(TMP, 'crlf-preload.js');
  fs.writeFileSync(pre, [
    "const M = require('node:module');",
    'const orig = M.prototype._compile;',
    'M.prototype._compile = function (content, filename) {',
    "  if (/[\\\\/]server[\\\\/]server\\.js$/.test(filename)) {",
    "    content = content.replace(/\\r?\\n/g, '\\r\\n');",
    "    process.stdout.write('CRLF-PRELOAD ' + (content.match(/\\r\\n/g) || []).length + '\\n');",
    '  }',
    '  return orig.call(this, content, filename);',
    '};', ''].join('\n'));
  boot({ TRUST_PROXY: '1' }, ['-r', pre]);
  ok('서버(CRLF) 가 뜬다', await waitUp(), out.slice(-300));
  const n = Number((/CRLF-PRELOAD (\d+)/.exec(out) || [])[1] || 0);
  ok('server.js 를 정말 CRLF 로 읽었다 (시험이 헛돌지 않게)', n > 1000, [n, out.slice(0, 200)]);
  const r = await page('/i/' + CODE, { ua: UA.ios, headers: { 'X-Forwarded-Proto': 'https', 'X-Forwarded-Host': 'mybody-crlf.example.ts.net' } });
  const s = scriptOf(r.body);
  const csp = r.headers['content-security-policy'] || '';
  /* 브라우저가 재는 글자 = HTML 의 줄바꿈 맞추기(\r\n · \r → \n)를 거친 스크립트. */
  const seen = s.replace(/\r\n?/g, '\n');
  ok('브라우저가 재는 해시(줄바꿈을 맞춘 뒤)가 CSP 의 script-src 와 맞는다',
     r.status === 200 && s.length > 500 && csp.split('; ').includes('script-src ' + shaOf(seen)), [r.status, s.length]);
  ok('스크립트에 CR 이 없고, LF 로 읽은 서버의 것과 한 글자도 다르지 않다',
     !s.includes('\r') && LF_SCRIPT.length > 500 && s === LF_SCRIPT, [s.includes('\r'), s.length, LF_SCRIPT.length]);
  await stop();
}

main()
  .catch(e => { fail++; console.error(e); })
  .finally(async () => {
    await stop();
    try { fs.rmSync(TMP, { recursive: true, force: true }); } catch (e) {}
    console.log(`\n${pass} 통과 · ${fail} 실패`);
    process.exit(fail ? 1 : 0);
  });
