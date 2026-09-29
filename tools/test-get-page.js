/* =============================================================================
 * tools/test-get-page.js — 설치 링크 (GET /get)
 *
 *   node tools/test-get-page.js
 *
 * 왜 이 시험이 있나
 *   시험해 줄 사람에게 보내는 링크 하나입니다. 주인의 말: "친구 추가 링크처럼 누르면 바로 —
 *   그런데 친구가 되면 안 된다". 그래서 지킬 것이 둘입니다.
 *     · 기종에 맞는 곳으로 — 아이폰은 TestFlight(App Store 에 나간 뒤 App Store)로 곧장(302),
 *       안드로이드는 ① 그룹 ② 참여 ③ 플레이 단추(출시 뒤 플레이로 곧장), 컴퓨터는 둘 다.
 *     · 친구가 되는 길이 하나도 없다 — 코드 · 앱 열기(mybody:// · intent) · 클립보드 담기 ·
 *       플레이 추천인이 페이지에 없고, 앱 링크 파일이 /get 을 앱의 것이라고 하지 않는다.
 *   그리고 초대 페이지와 같은 머리글(CSP · noindex · no-referrer)이고 받은 것을 안 찍는지.
 *
 * 보는 것
 *   [1] 아이폰 — 시험 중 TestFlight 로 302 · 링크 없으면 "곧 열려요" 200 · 출시 뒤 App Store 로 302
 *   [2] 안드로이드 — ①②③ 차례 · 추천인 없는 플레이 · 그룹이 없으면 그 단계 뺌 · 참여 링크가 없으면
 *       "곧 열려요" · 출시 뒤 플레이로 302
 *   [3] 컴퓨터 — 두 기종 다 · "폰에서 열면 더 쉬워요"
 *   [3-2] 아이폰만 먼저 App Store — 시험 중이어도 앱스토어 판(appLatestAppStore)이 적혀 있으면 아이폰은
 *       App Store 로 302(앱 안 브라우저 · 컴퓨터 칸은 "App Store 에서 받기"), 안드로이드는 ①②③ 그대로
 *       (앱스토어 판이 없을 때와 글자 하나 다르지 않음) · 틀린 모양의 판은 없는 것으로
 *   [4] 앱 안 브라우저 — 302 대신 그 기종만의 페이지 · 카카오톡은 기본 브라우저로 넘김(가짜 브라우저에서
 *       실행) · 그 밖(이름 없는 메일 앱의 WebView · WKWebView 도)은 "다른 브라우저로 열기" 한 줄 ·
 *       삼성 인터넷 · 아이폰 크롬은 보통 브라우저
 *   [5] 경로 · 방법 — /get/ · HEAD(GET 과 같은 머리글) · POST 405 · /get/x 는 이 페이지가 아님
 *   [6] 머리글 — 초대 페이지와 같은 CSP(스타일 · 스크립트 해시가 페이지와 맞음) · noindex ·
 *       no-referrer · DENY · Vary: * · nosniff · no-store · 302 도 no-referrer
 *   [7] 받은 것을 안 찍는다 — 쿼리 · User-Agent · 이상한 Host
 *   [8] 친구가 되는 길이 없다 — 모든 200 페이지 · 앱 링크 파일 · 앱의 링크 받는 주소(/i/ 만)
 *   [9] 설정 파일이 망가져도 뜬다 · 초대 페이지 제목은 그대로
 * ========================================================================== */
'use strict';
/* 검사하는 사람의 ~/.mybody 설정(진짜 참여 링크)이 결과를 바꾸지 않게. */
const TESTENV = require('./testenv.js');
const { spawn } = require('node:child_process');
const http = require('node:http');
const crypto = require('node:crypto');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const vm = require('node:vm');

const ROOT = path.join(__dirname, '..');
let pass = 0, fail = 0;
const ok = (n, c, d) => {
  if (c) { pass++; console.log('  ✓', n); }
  else { fail++; console.log('  ✗', n, d === undefined ? '' : JSON.stringify(d).slice(0, 500)); }
};
const wait = ms => new Promise(r => setTimeout(r, ms));
const TMP = fs.mkdtempSync(path.join(os.tmpdir(), 'mybody-get-'));
const CFG = path.join(TESTENV.home, '.mybody', 'config.json');
let PORT = 0;
function freePort() {
  return new Promise((resolve, reject) => {
    const s = http.createServer();
    s.once('error', reject);
    s.listen(0, '127.0.0.1', () => { const n = s.address().port; s.close(() => resolve(n)); });
  });
}

const UA = {
  android: 'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Mobile Safari/537.36',
  ios: 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1',
  ipad: 'Mozilla/5.0 (iPad; CPU OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1',
  criOs: 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/126.0.6478.54 Mobile/15E148 Safari/604.1',
  samsung: 'Mozilla/5.0 (Linux; Android 14; SM-S921N) AppleWebKit/537.36 (KHTML, like Gecko) SamsungBrowser/25.0 Chrome/121.0.0.0 Mobile Safari/537.36',
  /* 이름 없는 앱이 자기 안에서 연 창 — 메일 · 메신저 앱. 안드로이드 WebView 는 "; wv)", WKWebView 는 "Safari/" 가 없음. */
  wvAndroid: 'Mozilla/5.0 (Linux; Android 14; SM-S921N; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/126.0 Mobile Safari/537.36',
  wkIos: 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148',
  desktop: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36',
  kakaoIos: 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 KAKAOTALK 10.8.0',
  kakaoAndroid: 'Mozilla/5.0 (Linux; Android 13; SM-S911N) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Mobile Safari/537.36 KAKAOTALK 10.4.5',
  instaIos: 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 Instagram 339.0.0.37.93',
  lineAndroid: 'Mozilla/5.0 (Linux; Android 14; Pixel 8; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/126.0 Mobile Safari/537.36 Line/14.10.1'
};
const PKG = 'io.github.iacobuschoi.mybody';
/* 앱과 약속한 가게 주소 — 설치 링크의 플레이 주소에는 추천인이 **없습니다.** */
const APPSTORE = 'https://apps.apple.com/app/id6815144446';
const PLAY = 'https://play.google.com/store/apps/details?id=' + PKG;
const JA = 'https://play.google.com/apps/testing/' + PKG;
const JG = 'https://groups.google.com/g/mybody-testers';
const JI = 'https://testflight.apple.com/join/AbCdEf12';
const TIP = '오른쪽 위 ⋯ → 다른 브라우저로 열기';
const STEP_TOP = '위에서부터 하나씩 — 끝나면 이 페이지로 돌아와 다음 단추를 눌러 주세요';
const ACCOUNT = '<p class="hint">그룹 · 플레이 모두 같은 구글 계정으로</p>';
const DESK = '폰에서 이 링크를 열면 더 쉬워요 · 그 폰에 맞는 안내만 나와요';
/* 한 기종 페이지에 없어야 할 다른 기종 몫 — 컴퓨터 줄도. */
const NOT_IOS = ['<h2>안드로이드</h2>', JG, JA, PLAY, DESK];
const NOT_ANDROID = ['<h2>아이폰</h2>', JI, 'TestFlight', DESK];

let srv = null, out = '';
function boot(env) {
  out = '';
  const p = spawn(process.execPath, [path.join(ROOT, 'server', 'server.js')], {
    cwd: ROOT, stdio: ['ignore', 'pipe', 'pipe'],
    env: Object.assign({}, process.env, {
      PORT: String(PORT), PAIR_SECRET: 'get-pair-secret', DB: path.join(TMP, 'srv.db'),
      STATIC: path.join(ROOT, 'prototype'), NODE_NO_WARNINGS: '1'
    }, env || {})
  });
  p.stdout.on('data', d => { out += d; });
  p.stderr.on('data', d => { out += d; });
  srv = p;
}
async function stop() {
  if (!srv) return;
  const p = srv; srv = null;
  await new Promise(r => { p.once('exit', r); try { p.kill('SIGTERM'); } catch (e) { r(); } setTimeout(r, 3000); });
}
async function waitUp() {
  for (let i = 0; i < 80; i++) {
    if (!srv || srv.exitCode !== null || srv.signalCode !== null) return false;
    try { if ((await fetch(`http://127.0.0.1:${PORT}/api/health`)).ok) return true; } catch (e) {}
    await wait(150);
  }
  return false;
}
/** 한 장. fetch 는 Host 를 못 바꾸고 302 를 따라가서 http.request 로. */
function page(p, opt) {
  const o = opt || {};
  const headers = Object.assign({}, o.ua !== undefined ? { 'User-Agent': o.ua } : {}, o.headers || {});
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
function writeCfg(obj) {
  fs.mkdirSync(path.dirname(CFG), { recursive: true });
  fs.writeFileSync(CFG, JSON.stringify(obj, null, 2) + '\n');
}
const ALL = { appJoinAndroid: JA, appJoinAndroidGroup: JG, appJoinIos: JI };
const unesc = s => s.replace(/&#39;/g, "'").replace(/&quot;/g, '"').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&');
function hrefs(html) {
  const r = [], re = /<a\b[^>]*\bhref="([^"]*)"[^>]*>([\s\S]*?)<\/a>/g;
  let m;
  while ((m = re.exec(html))) r.push({ href: unesc(m[1]), label: m[2], tag: m[0] });
  return r;
}
const meta = (html, attr, name) => {
  const m = new RegExp('<meta ' + attr + '="' + name.replace(/[:.]/g, '\\$&') + '" content="([^"]*)">').exec(html);
  return m ? unesc(m[1]) : null;
};
const scriptOf = html => (/<script>([\s\S]*?)<\/script>/.exec(html) || [])[1] || '';
const shaOf = s => "'sha256-" + crypto.createHash('sha256').update(s, 'utf8').digest('base64') + "'";
const labels = html => hrefs(html).map(x => x.label);
const is302 = (r, to) => r.status === 302 && r.headers.location === to && r.body === '' &&
  /^text\/plain/.test(r.headers['content-type'] || '');

/** 가짜 브라우저 — 카카오톡 페이지의 스크립트를 그대로 돌려 어디로 가는지 · 무엇을 담는지 봅니다. */
function runScript(html, href) {
  const nav = [], clip = [], timers = [];
  const attrs = {};
  const tag = (/<body\b([^>]*)>/.exec(html) || [])[1] || '';
  for (const m of tag.matchAll(/\s(data-[a-z-]+)="([^"]*)"/g)) attrs[m[1]] = unesc(m[2]);
  const store = {};
  const ctx = {
    document: {
      body: { getAttribute: k => (Object.hasOwn(attrs, k) ? attrs[k] : null) },
      querySelectorAll: () => [], getElementById: () => null, addEventListener() {}, visibilityState: 'visible'
    },
    location: { get href() { return href; }, set href(v) { nav.push(['href', v]); }, replace(v) { nav.push(['replace', v]); } },
    navigator: { clipboard: { writeText(t) { clip.push(t); return Promise.resolve(); } } },
    sessionStorage: { getItem: k => (Object.hasOwn(store, k) ? store[k] : null), setItem: (k, v) => { store[k] = String(v); } },
    setTimeout: (f, ms) => { timers.push(ms); return timers.length; }
  };
  let error = null;
  try { vm.runInNewContext(scriptOf(html), ctx, { timeout: 1000 }); } catch (e) { error = e; }
  return { nav, clip, timers, error };
}

/* 모든 200 페이지를 모아 [6] · [8] 에서 한꺼번에 봅니다. */
const pages = [];
const keep = (nm, r) => { if (r.status === 200) pages.push([nm, r]); return r; };

async function main() {
  PORT = await freePort();
  boot({ TRUST_PROXY: '1' });
  ok('서버가 뜬다', await waitUp(), out.slice(-400));
  const inviteCsp = (await page('/i/ABCD2345', { ua: UA.desktop })).headers['content-security-policy'] || '';

  console.log('\n[1] 아이폰');
  writeCfg(ALL);
  const i1 = await page('/get', { ua: UA.ios });
  ok('시험 중 · TestFlight 링크 있음 → 302 그 링크 (본문 없음 · text/plain)', is302(i1, JI), [i1.status, i1.headers]);
  ok('아이패드(사파리)도 같은 곳으로', is302(await page('/get', { ua: UA.ipad }), JI));
  ok('아이폰 크롬(CriOS — "Safari/" 있음)도 같은 곳으로', is302(await page('/get', { ua: UA.criOs }), JI));
  writeCfg({ appJoinAndroid: JA, appJoinAndroidGroup: JG });
  const i2 = keep('아이폰 곧 열려요', await page('/get', { ua: UA.ios }));
  ok('시험 중 · TestFlight 링크 없음 → 200 "아이폰은 곧 열려요 — 조금 뒤에 이 링크를 다시 눌러 주세요"',
     i2.status === 200 && i2.body.includes('아이폰은 곧 열려요 — 조금 뒤에 이 링크를 다시 눌러 주세요'), [i2.status, i2.body.slice(-400)]);
  ok('그 페이지에 단추 · 안드로이드 안내는 없다', hrefs(i2.body).length === 0 && !i2.body.includes('안드로이드'),
     labels(i2.body));
  writeCfg(Object.assign({ appTesting: false }, ALL));
  const i3 = await page('/get', { ua: UA.ios });
  ok('출시 뒤 → 302 App Store (' + APPSTORE + ')', is302(i3, APPSTORE), [i3.status, i3.headers.location]);

  console.log('\n[2] 안드로이드');
  writeCfg(ALL);
  const a1 = keep('안드로이드 ①②③', await page('/get', { ua: UA.android }));
  const L = hrefs(a1.body);
  ok('시험 중 → 200 · 단추 셋 그대로 차례대로: ① 구글 그룹 가입 → ② 테스트 참여 → ③ Google Play 에서 설치',
     a1.status === 200 && L.length === 3 &&
     L[0].label === '① 구글 그룹 가입' && L[0].href === JG &&
     L[1].label === '② 테스트 참여' && L[1].href === JA &&
     L[2].label === '③ Google Play 에서 설치' && L[2].href === PLAY, L.map(x => x.label + ' ' + x.href));
  ok('③ 은 추천인 없는 플레이 주소 (&referrer= 없음)', L[2] && L[2].href === PLAY && !/[?&](amp;)?referrer=/.test(a1.body), L[2]);
  const [top, acct, btn1] = [a1.body.indexOf(STEP_TOP), a1.body.indexOf(ACCOUNT), a1.body.indexOf('class="btn')];
  ok('단추 위에 차례로: "' + STEP_TOP + '" → "그룹 · 플레이 모두 같은 구글 계정으로" → ① 단추',
     top > 0 && top < acct && acct < btn1, [top, acct, btn1]);
  ok('안드로이드 페이지에 아이폰 링크 · 스크립트는 없다', !a1.body.includes(JI) && !a1.body.includes('아이폰') &&
     !/<script/i.test(a1.body));
  writeCfg({ appJoinAndroid: JA, appJoinIos: JI });
  const a2 = keep('안드로이드 그룹 없음', await page('/get', { ua: UA.android }));
  const L2 = hrefs(a2.body);
  ok('그룹이 없으면 그 단계를 빼고 ① 테스트 참여 → ② Google Play 에서 설치',
     L2.length === 2 && L2[0].label === '① 테스트 참여' && L2[0].href === JA &&
     L2[1].label === '② Google Play 에서 설치' && L2[1].href === PLAY &&
     !a2.body.includes('③') && !a2.body.includes('구글 그룹') && !a2.body.includes('그룹 · 플레이'), L2.map(x => x.label));
  writeCfg({ appJoinAndroidGroup: JG, appJoinIos: JI });
  const a3 = keep('안드로이드 곧 열려요', await page('/get', { ua: UA.android }));
  ok('참여 링크가 없으면 "안드로이드는 곧 열려요" · 단추 없음 (그룹만 있어도)',
     a3.status === 200 && a3.body.includes('안드로이드는 곧 열려요 — 조금 뒤에 이 링크를 다시 눌러 주세요') &&
     hrefs(a3.body).length === 0, labels(a3.body));
  writeCfg(Object.assign({ appTesting: false }, ALL));
  const a4 = await page('/get', { ua: UA.android });
  ok('출시 뒤 → 302 추천인 없는 플레이', is302(a4, PLAY), [a4.status, a4.headers.location]);

  console.log('\n[3] 컴퓨터');
  writeCfg(ALL);
  for (const [nm, ua] of [['컴퓨터', UA.desktop], ['User-Agent 없음', '']]) {
    const d = keep(nm, await page('/get', { ua }));
    const D = hrefs(d.body);
    ok(nm + ' → 200 · 안드로이드 · 아이폰 두 칸 다 (적힌 링크 그대로)', d.status === 200 &&
       d.body.includes('<h2>안드로이드</h2>') && d.body.includes('<h2>아이폰</h2>') &&
       [JG, JA, PLAY, JI].every(u => D.some(x => x.href === u)), D.map(x => x.label));
    ok(nm + ': "' + DESK + '" 가 맨 위', d.body.indexOf(DESK) > 0 &&
       d.body.indexOf(DESK) < d.body.indexOf('<h2>안드로이드</h2>'));
  }
  const d1 = (await page('/get', { ua: UA.desktop })).body;
  ok('아이폰 칸: "TestFlight 에서 받기" + "TestFlight 앱이 있어야 열려요 · TestFlight 받기"',
     hrefs(d1).some(x => x.label === 'TestFlight 에서 받기' && x.href === JI) &&
     hrefs(d1).some(x => x.label === 'TestFlight 받기' && /^https:\/\/apps\.apple\.com\/app\/testflight\/id\d+$/.test(x.href)));
  writeCfg(Object.assign({ appTesting: false }, ALL));
  const d2 = keep('컴퓨터 출시 뒤', await page('/get', { ua: UA.desktop }));
  ok('출시 뒤 컴퓨터: 가게 둘만 (Google Play 에서 받기 · App Store 에서 받기 — 참여 링크 없음)',
     d2.status === 200 && labels(d2.body).join('|') === 'Google Play 에서 받기|App Store 에서 받기' &&
     hrefs(d2.body)[0].href === PLAY && hrefs(d2.body)[1].href === APPSTORE && ![JA, JG, JI].some(u => d2.body.includes(u)),
     hrefs(d2.body).map(x => x.label + ' ' + x.href));

  console.log('\n[3-2] 아이폰만 먼저 App Store — 시험 중이어도 앱스토어 판이 적혀 있으면');
  /* 아이폰은 심사를 지나 App Store 에 나갔는데 안드로이드는 아직 플레이 비공개 테스트인 때. 주인은
     testing 을 켠 채 --appstore=<판> 만 적습니다 — 아이폰만 App Store 로, 안드로이드는 ①②③ 그대로. */
  const AS = { appLatestAppStore: '0.2.20' };
  writeCfg(ALL);
  const andBefore = await page('/get', { ua: UA.android }), deskBefore = await page('/get', { ua: UA.desktop });
  const wvBefore = await page('/get', { ua: UA.wvAndroid });
  writeCfg(Object.assign({}, AS, ALL));
  const as1 = await page('/get', { ua: UA.ios });
  ok('아이폰 → 302 App Store (' + APPSTORE + ') — TestFlight 링크가 적혀 있어도', is302(as1, APPSTORE), [as1.status, as1.headers.location]);
  ok('아이패드 · 아이폰 크롬도 App Store 로', is302(await page('/get', { ua: UA.ipad }), APPSTORE) &&
     is302(await page('/get', { ua: UA.criOs }), APPSTORE));
  const ash = await page('/get', { method: 'HEAD', ua: UA.ios });
  ok('HEAD (아이폰) → 302 같은 App Store', ash.status === 302 && ash.headers.location === APPSTORE, ash.headers.location);
  for (const [nm, ua] of [['메일 앱 WKWebView(아이폰)', UA.wkIos], ['인스타그램(아이폰)', UA.instaIos],
                          ['카카오톡(아이폰)', UA.kakaoIos]]) {
    const w = keep(nm + ' · 앱스토어 판', await page('/get', { ua }));
    ok(nm + ': 200 (302 아님) · "App Store 에서 받기" 단추 하나만 · TestFlight · 안드로이드 · 컴퓨터 줄 없음',
       w.status === 200 && !w.headers.location && labels(w.body).join('|') === 'App Store 에서 받기' &&
       hrefs(w.body)[0].href === APPSTORE && !w.body.includes('TestFlight') && !w.body.includes(JI) &&
       NOT_IOS.every(t => !w.body.includes(t)), [w.status, hrefs(w.body).map(x => x.label + ' ' + x.href)]);
  }
  const ask = await page('/get', { ua: UA.kakaoIos });
  const ark = runScript(ask.body, 'https://mybody-get.example.ts.net/get');
  ok('카카오톡(아이폰): 여전히 기본 브라우저로 넘김 (거기서 App Store 로 302)', /<body data-inapp="kakao">/.test(ask.body) &&
     !ark.error && ark.nav.length === 1 && ark.nav[0][0] === 'replace' && /^kakaotalk:\/\/web\/openExternal\?url=/.test(ark.nav[0][1]),
     ark.nav);
  const asd = keep('컴퓨터 · 앱스토어 판', await page('/get', { ua: UA.desktop }));
  const iosCard = (/<h2>아이폰<\/h2>([\s\S]*?)<\/section>/.exec(asd.body) || [])[1] || '';
  const andCard = (/<h2>안드로이드<\/h2>([\s\S]*?)<\/section>/.exec(asd.body) || [])[1] || '';
  ok('컴퓨터: 아이폰 칸은 "App Store 에서 받기" 하나 (TestFlight 없음)', asd.status === 200 &&
     labels(iosCard).join('|') === 'App Store 에서 받기' && hrefs(iosCard)[0].href === APPSTORE &&
     !iosCard.includes('TestFlight') && !asd.body.includes(JI), hrefs(iosCard).map(x => x.label + ' ' + x.href));
  ok('컴퓨터: 안드로이드 칸은 그대로 ① 구글 그룹 가입 → ② 테스트 참여 → ③ Google Play 에서 설치',
     labels(andCard).join('|') === '① 구글 그룹 가입|② 테스트 참여|③ Google Play 에서 설치' &&
     hrefs(andCard).map(x => x.href).join(' ') === [JG, JA, PLAY].join(' ') && andCard.includes(STEP_TOP),
     labels(andCard));
  ok('컴퓨터: 아이폰 칸 말고는 앱스토어 판이 없을 때와 글자 하나 다르지 않다',
     asd.body.replace(iosCard, '#') === deskBefore.body.replace(/<h2>아이폰<\/h2>([\s\S]*?)<\/section>/, '<h2>아이폰</h2>#</section>'));
  const asa = keep('안드로이드 · 앱스토어 판', await page('/get', { ua: UA.android }));
  ok('안드로이드: 302 하지 않고 ①②③ 페이지 — 앱스토어 판이 없을 때와 글자 하나 다르지 않다',
     asa.status === 200 && !asa.headers.location && asa.body === andBefore.body && labels(asa.body).length === 3, labels(asa.body));
  ok('안드로이드 메일 앱 WebView 도 그대로', (await page('/get', { ua: UA.wvAndroid })).body === wvBefore.body);
  writeCfg(Object.assign({}, AS, { appJoinAndroid: JA, appJoinAndroidGroup: JG }));
  ok('TestFlight 링크가 없어도 아이폰은 App Store 로 ("곧 열려요" 아님)', is302(await page('/get', { ua: UA.ios }), APPSTORE));
  writeCfg(Object.assign({ appLatestAppStore: '0.2' }, ALL));
  ok('모양이 틀린 판("0.2")은 없는 것으로 — 아이폰은 그대로 TestFlight', is302(await page('/get', { ua: UA.ios }), JI));
  writeCfg(Object.assign({ appTesting: false }, AS, ALL));
  ok('출시 뒤(testing 꺼짐)에는 두 기종 다 가게로 — 아이폰 App Store · 안드로이드 플레이',
     is302(await page('/get', { ua: UA.ios }), APPSTORE) && is302(await page('/get', { ua: UA.android }), PLAY));

  console.log('\n[4] 앱 안 브라우저 — 302 대신 페이지');
  writeCfg(ALL);
  const HOST = 'mybody-get.example.ts.net';
  const HREF = 'https://' + HOST + '/get';
  const KAKAO = 'kakaotalk://web/openExternal?url=' + encodeURIComponent(HREF);
  for (const [nm, ua, want, not] of [['카카오톡(아이폰)', UA.kakaoIos, [JI], NOT_IOS],
                                     ['카카오톡(안드로이드)', UA.kakaoAndroid, [JG, JA, PLAY], NOT_ANDROID]]) {
    const k = keep(nm, await page('/get', { ua }));
    ok(nm + ': 200 · 그 기종 단추 · <body data-inapp="kakao"> 만 (다른 data-… 없음)', k.status === 200 &&
       want.every(u => hrefs(k.body).some(x => x.href === u)) && /<body data-inapp="kakao">/.test(k.body), labels(k.body));
    ok(nm + ': 다른 기종 칸 · 컴퓨터 줄은 없다', not.every(t => !k.body.includes(t)), not.filter(t => k.body.includes(t)));
    const r = runScript(k.body, HREF);
    ok(nm + ': 스크립트가 곧바로 kakaotalk://web/openExternal?url=<지금 주소> 로 (location.replace) · 담기 없음 · 타이머 없음',
       !r.error && r.nav.length === 1 && r.nav[0][0] === 'replace' && r.nav[0][1] === KAKAO && r.clip.length === 0 &&
       r.timers.length === 0, [r.error && String(r.error), r.nav, r.clip]);
    ok(nm + ': 스크립트는 초대 페이지의 것 그대로 (CSP 해시가 맞음)', (k.headers['content-security-policy'] || '')
       .split('; ').includes('script-src ' + shaOf(scriptOf(k.body))));
  }
  writeCfg(Object.assign({ appTesting: false }, ALL));
  for (const [nm, ua] of [['카카오톡', UA.kakaoAndroid], ['메일 앱 WebView', UA.wvAndroid]]) {
    const ko = keep(nm + ' 출시 뒤', await page('/get', { ua }));
    ok(nm + '(안드로이드)은 출시 뒤에도 302 하지 않고 "Google Play 에서 받기" 페이지', ko.status === 200 &&
       !ko.headers.location && hrefs(ko.body).some(x => x.label === 'Google Play 에서 받기' && x.href === PLAY), ko.status);
  }
  writeCfg(ALL);
  for (const [nm, ua, want, not] of [['인스타그램(아이폰)', UA.instaIos, [JI], NOT_IOS],
                                     ['라인(안드로이드)', UA.lineAndroid, [JG, JA, PLAY], NOT_ANDROID],
                                     ['메일 앱 WebView(안드로이드, "; wv)")', UA.wvAndroid, [JG, JA, PLAY], NOT_ANDROID],
                                     ['메일 앱 WKWebView(아이폰, "Safari/" 없음)', UA.wkIos, [JI], NOT_IOS]]) {
    const p2 = keep(nm, await page('/get', { ua }));
    const at = p2.body.indexOf(TIP);
    ok(nm + ': 200 (302 아님) · "' + TIP + '" 을 단추 위에 · 스크립트 없음', p2.status === 200 && !p2.headers.location &&
       at > 0 && at < p2.body.indexOf('class="btn') && !/<script/i.test(p2.body) && /<body>/.test(p2.body), [p2.status, at]);
    ok(nm + ': 그 기종 단추만 · 다른 기종 칸 · 컴퓨터 줄은 없다', want.every(u => hrefs(p2.body).some(x => x.href === u)) &&
       not.every(t => !p2.body.includes(t)), [labels(p2.body), not.filter(t => p2.body.includes(t))]);
  }
  const sm = keep('삼성 인터넷', await page('/get', { ua: UA.samsung }));
  ok('삼성 인터넷("; wv)" 없음)은 보통 브라우저: ①②③ 페이지 · 그 한 줄 없음', sm.status === 200 &&
     hrefs(sm.body).length === 3 && !sm.body.includes(TIP), labels(sm.body));
  for (const [nm, ua] of [['안드로이드', UA.android], ['컴퓨터', UA.desktop]]) {
    ok(nm + ' 보통 브라우저에는 그 한 줄이 없다', !(await page('/get', { ua })).body.includes(TIP));
  }

  console.log('\n[5] 경로 · 방법');
  ok('/get/ 도 같은 곳으로 (아이폰 302)', is302(await page('/get/', { ua: UA.ios }), JI));
  const s1 = await page('/get', { ua: UA.desktop }), s2 = keep('/get/', await page('/get/', { ua: UA.desktop }));
  ok('/get/ 도 같은 페이지 (컴퓨터)', s2.status === 200 && s2.body === s1.body);
  const hd = await page('/get', { method: 'HEAD', ua: UA.desktop });
  const SAME = ['content-type', 'content-security-policy', 'x-robots-tag', 'referrer-policy', 'vary', 'x-frame-options',
                'x-content-type-options', 'cache-control'];
  ok('HEAD → 200 · GET 과 같은 머리글 (' + SAME.join(' · ') + ')', hd.status === 200 &&
     /^text\/html/.test(hd.headers['content-type']) && SAME.every(k => s1.headers[k] && hd.headers[k] === s1.headers[k]),
     SAME.filter(k => hd.headers[k] !== s1.headers[k]));
  const hi = await page('/get', { method: 'HEAD', ua: UA.ios });
  ok('HEAD (아이폰) → 302 같은 Location · text/plain · no-referrer', hi.status === 302 && hi.headers.location === JI &&
     /^text\/plain/.test(hi.headers['content-type'] || '') && hi.headers['referrer-policy'] === 'no-referrer', hi.headers);
  for (const p2 of ['/get', '/get/']) {
    for (const m of ['POST', 'PUT', 'DELETE']) {
      const r = await page(p2, { method: m, ua: UA.ios });
      ok(m + ' ' + p2 + ' → 405 (Allow: GET, HEAD) · Location 없음', r.status === 405 && r.headers.allow === 'GET, HEAD' &&
         !r.headers.location, [r.status, r.headers.allow]);
    }
  }
  for (const p2 of ['/get/x', '/getx', '/get.html']) {
    const r = await page(p2, { ua: UA.ios });
    ok(p2 + ' 는 이 페이지가 아님 (404 · 302 아님)', r.status === 404 && !r.headers.location, r.status);
  }

  console.log('\n[6] 머리글');
  const h = s1.headers;
  const csp = h['content-security-policy'] || '';
  ok('CSP 는 초대 페이지와 같다', csp && csp === inviteCsp, [csp, inviteCsp]);
  ok("CSP: default-src 'none' · 'unsafe-inline' 없음 · frame-ancestors 'none'", /(^|; )default-src 'none'(;|$)/.test(csp) &&
     !/unsafe-inline|unsafe-eval|https?:|\*/.test(csp) && /frame-ancestors 'none'/.test(csp));
  ok('X-Robots-Tag: noindex (+ 메타)', h['x-robots-tag'] === 'noindex' && meta(s1.body, 'name', 'robots') === 'noindex');
  ok('Referrer-Policy: no-referrer (+ 메타)', h['referrer-policy'] === 'no-referrer' &&
     meta(s1.body, 'name', 'referrer') === 'no-referrer');
  ok('X-Frame-Options: DENY · Vary: * · nosniff · no-store', h['x-frame-options'] === 'DENY' && h.vary === '*' &&
     h['x-content-type-options'] === 'nosniff' && h['cache-control'] === 'no-store', h);
  ok('302 도 no-referrer · noindex · no-store (TestFlight · 가게로 이 주소가 안 따라감)',
     i1.headers['referrer-policy'] === 'no-referrer' && i1.headers['x-robots-tag'] === 'noindex' &&
     i1.headers['cache-control'] === 'no-store', i1.headers);
  for (const [nm, r] of pages) {
    const styles = [...r.body.matchAll(/<style>([\s\S]*?)<\/style>/g)].map(m => m[1]);
    const scripts = [...r.body.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script>/gi)];
    const pcsp = r.headers['content-security-policy'] || '';
    ok(nm + ': 같은 머리글 · <style> 하나가 CSP 해시와 맞음 · 스크립트는 카카오톡만(해시 맞음)',
       pcsp === inviteCsp && r.headers['x-robots-tag'] === 'noindex' && r.headers['referrer-policy'] === 'no-referrer' &&
       r.headers.vary === '*' && styles.length === 1 && pcsp.includes('style-src ' + shaOf(styles[0])) &&
       (/data-inapp="kakao"/.test(r.body)
         ? scripts.length === 1 && scripts[0][1] === '' && pcsp.split('; ').includes('script-src ' + shaOf(scripts[0][2]))
         : scripts.length === 0), [nm, styles.length, scripts.length]);
    const html = r.body.replace(/<script>[\s\S]*?<\/script>/, '');
    ok(nm + ': on…= 핸들러 · javascript: · style="…" 없음 · 밖으로 가는 링크는 전부 rel="noreferrer"',
       !/\son[a-z]+\s*=/i.test(html) && !/javascript:/i.test(r.body) && !/\sstyle=/i.test(html) &&
       hrefs(r.body).every(x => /^https:\/\//.test(x.href) && /rel="noreferrer"/.test(x.tag)), hrefs(r.body).map(x => x.tag));
  }

  console.log('\n[7] 받은 것을 안 찍는다');
  const MARK = 'zqx' + crypto.randomBytes(4).toString('hex');
  const q = '?x=%3Cscript%3E' + MARK + '&noapp=1&stay=1&code=ABCD2345&' + MARK + '=1';
  const qi = await page('/get' + q, { ua: UA.ios });
  ok('쿼리가 있어도 아이폰 302 는 같은 곳 (Location 에 안 실음)', is302(qi, JI), qi.headers.location);
  for (const [nm, ua] of [['컴퓨터', UA.desktop], ['안드로이드', UA.android], ['카카오톡', UA.kakaoIos]]) {
    const r = await page('/get' + q, { ua });
    const plain = await page('/get', { ua });
    ok(nm + ': 쿼리를 페이지에 안 찍는다 (쿼리 없는 페이지와 글자 하나 다르지 않음)', r.status === 200 &&
       !r.body.includes(MARK) && !r.body.includes('ABCD2345') && r.body === plain.body);
  }
  const uaMark = UA.desktop + ' <b>' + MARK + '</b>';
  const um = await page('/get', { ua: uaMark });
  ok('User-Agent 를 안 찍는다', um.status === 200 && !um.body.includes(MARK));
  const ui = await page('/get', { ua: UA.ios + ' ' + MARK });
  ok('User-Agent 가 Location 에 안 실린다', is302(ui, JI) && !JSON.stringify(ui.headers).includes(MARK));
  const fwd = await page('/get', { ua: UA.desktop, headers: { 'X-Forwarded-Proto': 'https', 'X-Forwarded-Host': HOST } });
  ok('미리보기: og:title Mybody 받기 · og:image 는 연 주소의 앱 아이콘', meta(fwd.body, 'property', 'og:title') === 'Mybody 받기' &&
     meta(fwd.body, 'property', 'og:image') === 'https://' + HOST + '/assets/icon-512.png' &&
     meta(fwd.body, 'property', 'og:url') === null, meta(fwd.body, 'property', 'og:image'));
  const evil = await page('/get', { ua: UA.desktop,
    headers: { Host: 'evil.example"><script>alert(1)</script>', 'X-Forwarded-Host': 'x" onload="' + MARK } });
  ok('이상한 Host · X-Forwarded-Host → og:image 를 안 박음 · 그대로 찍지 않음', evil.status === 200 &&
     meta(evil.body, 'property', 'og:image') === null && !/<script|onload|evil\.example/.test(evil.body) &&
     !evil.body.includes(MARK), evil.body.slice(0, 600));

  console.log('\n[8] 친구가 되는 길이 없다');
  ok('본 200 페이지가 충분하다 (' + pages.length + '장)', pages.length >= 12, pages.map(p2 => p2[0]));
  for (const [nm, r] of pages) {
    const b = r.body;
    /* 카카오톡 페이지의 스크립트는 초대 페이지와 같은 글자라 'a[data-install]' 같은 이름이 들어 있습니다 —
       HTML 쪽(스크립트 밖)에서 봅니다. 스크립트가 그 이름들로 할 일은 HTML 에 그 속성이 있어야 생깁니다. */
    const html = b.replace(/<script>[\s\S]*?<\/script>/, '');
    ok(nm + ': 제목 · h1 "Mybody 받기" · "친구" · "초대" · 코드 · 앱 열기 · 담기 · 추천인 없음',
       b.includes('<title>Mybody 받기</title>') && b.includes('<h1>Mybody 받기</h1>') &&
       !b.includes('친구') && !b.includes('초대') && !/class="code"/.test(b) && !/\/i\//.test(b) &&
       !/mybody:\/\/|intent:/i.test(b) && !/data-(copy|install|code|intent|later)\b/.test(html) &&
       !/referrer=|invite%3D/.test(b), nm);
  }
  const aa = await page('/.well-known/apple-app-site-association');
  let comps = null; try { comps = JSON.parse(aa.body).applinks.details[0].components; } catch (e) {}
  ok('아이폰 앱 링크 파일은 /i/* 만 앱의 것 — /get 은 앱이 깔려 있어도 브라우저로 열림',
     Array.isArray(comps) && comps.length === 1 && comps[0]['/'] === '/i/*' && !aa.body.includes('/get'), aa.body);
  /* 안드로이드 앱이 받는 https 주소 — 이 서버 이름으로는 /i/ 만. "/" 전체로 넓히면 /get 이 앱을
     열고, 앱은 링크를 친구 초대로 읽습니다. */
  const man = fs.readFileSync(path.join(ROOT, 'app', 'android', 'app', 'src', 'main', 'AndroidManifest.xml'), 'utf8');
  const hostData = [...man.matchAll(/<data\b[^>]*android:host="\$\{inviteHost\}"[^>]*\/>/g)].map(m => m[0]);
  ok('안드로이드 앱이 받는 이 서버 주소는 /i/ 만 (pathPrefix="/i/")', hostData.length > 0 &&
     hostData.every(t => /android:pathPrefix="\/i\/"/.test(t) && !/android:path(Pattern|AdvancedPattern)?="/.test(t.replace(/android:pathPrefix="\/i\/"/, ''))),
     hostData);

  console.log('\n[9] 설정이 망가져도 · 초대 페이지는 그대로');
  fs.writeFileSync(CFG, '{ 망가진 설정');
  const b1 = await page('/get', { ua: UA.ios }), b2 = await page('/get', { ua: UA.desktop });
  ok('설정 파일이 망가져도 200 (시험 중으로 읽고 "곧 열려요")', b1.status === 200 && b2.status === 200 &&
     b1.body.includes('아이폰은 곧 열려요') && b2.body.includes('안드로이드는 곧 열려요'), [b1.status, b2.status]);
  fs.rmSync(CFG, { force: true });
  const inv = await page('/i/ABCD2345', { ua: UA.android });
  ok('초대 페이지 제목은 그대로 "Mybody 친구 초대"', inv.status === 200 && inv.body.includes('<h1>Mybody 친구 초대</h1>') &&
     !inv.body.includes('Mybody 받기'));
  ok('로그에 /get 이 안 남는다', !out.includes('/get'), out.slice(-300));
}

main()
  .catch(e => { fail++; console.error(e); })
  .finally(async () => {
    await stop();
    try { fs.rmSync(TMP, { recursive: true, force: true }); } catch (e) {}
    console.log(`\n${pass} 통과 · ${fail} 실패`);
    process.exit(fail ? 1 : 0);
  });
