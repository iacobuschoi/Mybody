/* =============================================================================
 * test-appversion.js — **앱 안 업데이트 안내에 쓰는 값** (GET /api/version)
 *
 *   node tools/test-appversion.js
 *
 * GitHub 에서 APK 를 받아 깐 친구는 새 판이 나와도 모릅니다. 그래서 서버가
 * "가게마다 최신판 · 최소판 · 가게 주소" 를 알려 주고, 앱이 자기 판과
 * 견줘 안내를 띄웁니다. 여기서 지키는 것:
 *   1. 로그인 없이 받는다 — 로그인이 안 되는 이유가 "앱이 낡아서" 일 수 있다.
 *   2. 아무것도 안 적었으면 빈 값 + 기본 주소 = 안내 없음.
 *   3. 주인이 값을 바꾸면 **서버를 다시 띄우지 않아도** 바로 나간다.
 *   4. 판 모양이 아닌 값은 빈 값으로 — 서버가 죽지도, 엉뚱한 값을 내보내지도 않는다.
 *      설정 파일이 통째로 망가졌으면 빈 값이 아니라 503 — 빈 값은 "주인이 다
 *      지웠다" 와 같아서, 그때 물은 앱이 안내를 지우고 여섯 시간을 쉰다.
 *   5. tools/app-version.js 는 틀린 판 · 가게 최신판보다 높은 최소판을 거절하고,
 *      설정 파일의 다른 값(가입 코드 · 판독 키)은 건드리지 않는다.
 *   6. 도구는 저장한 뒤 이 컴퓨터의 서버에 물어서, 그 값이 정말 나가는지
 *      말한다(꺼짐 · 옛 서버 · 다른 설정 파일).
 * ========================================================================== */
'use strict';
require('./testenv');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const http = require('node:http');
const { spawn, spawnSync, execFile } = require('node:child_process');

const ROOT = path.join(__dirname, '..');
const TOOL = path.join(ROOT, 'tools', 'app-version.js');
const APPVER = require('../server/appversion.js');

let pass = 0, fail = 0;
const ok = (m, cond, d) => {
  if (cond) { pass++; console.log('  ✓ ' + m); }
  else { fail++; console.log('  ✗ ' + m + (d !== undefined ? '\n      ' + JSON.stringify(d) : '')); }
};
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);

const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'mybody-appver-'));
const DB = path.join(dir, 'test.db');
const PORT = 8900 + Math.floor(Math.random() * 90);
const B = `http://localhost:${PORT}/api`;
/* 서버와 도구가 같은 집(testenv 가 만든 빈 HOME)의 설정을 봅니다. */
const HOME = process.env.HOME;
const CFG = path.join(HOME, '.mybody', 'config.json');

const srv = spawn(process.execPath, [path.join(ROOT, 'server', 'server.js')], {
  cwd: ROOT, stdio: ['ignore', 'pipe', 'pipe'],
  env: Object.assign({}, process.env, {
    PORT: String(PORT), PAIR_SECRET: 'appver-pair', DB,
    STATIC: path.join(ROOT, 'prototype'), NODE_NO_WARNINGS: '1'
  })
});
let srvErr = '';
srv.stdout.on('data', () => {});
srv.stderr.on('data', d => { srvErr += d; });

async function get(p, init) {
  const r = await fetch(B + p, init);
  let j = null; try { j = await r.json(); } catch (e) {}
  return { status: r.status, json: j || {}, headers: r.headers };
}

/** 도구를 돌립니다. home 을 주면 그 집에서 — 서버의 설정과 섞지 않을 때.
 *  port 를 주면 도구가 그 포트의 서버에 값을 확인합니다(안 주면 설정의 포트). */
function toolEnv(home, port) {
  const h = home || HOME;
  const env = Object.assign({}, process.env, { HOME: h, USERPROFILE: h, NODE_NO_WARNINGS: '1' });
  delete env.PORT;
  if (port) env.PORT = String(port);
  return env;
}
function tool(args, home, port) {
  const r = spawnSync(process.execPath, [TOOL].concat(args), {
    cwd: ROOT, encoding: 'utf8', timeout: 30000, env: toolEnv(home, port)
  });
  return { code: r.status, out: (r.stdout || '') + (r.stderr || '') };
}
/* 이 프로세스 안에 띄운 가짜 서버에 물을 때. spawnSync 는 이 프로세스를
   멈춰 세워서 가짜 서버가 답을 못 합니다. */
function toolAsync(args, home, port) {
  return new Promise(resolve => {
    execFile(process.execPath, [TOOL].concat(args), {
      cwd: ROOT, encoding: 'utf8', timeout: 30000, env: toolEnv(home, port)
    }, (err, stdout, stderr) => {
      resolve({ code: err ? (typeof err.code === 'number' ? err.code : 1) : 0,
                out: (stdout || '') + (stderr || '') });
    });
  });
}
/** 아무도 안 듣는 포트 하나. */
function freePort() {
  return new Promise(resolve => {
    const s = http.createServer();
    s.listen(0, '127.0.0.1', () => { const p = s.address().port; s.close(() => resolve(p)); });
  });
}
function writeCfg(file, obj) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, typeof obj === 'string' ? obj : JSON.stringify(obj, null, 2) + '\n');
}
const readCfg = file => JSON.parse(fs.readFileSync(file, 'utf8'));

const EMPTY = { appstore: '', play: '', apk: '' };

async function main() {
  let up = false;
  for (let i = 0; i < 60 && !up; i++) {
    try { up = (await fetch(B + '/health')).ok; } catch (e) {}
    if (!up) await new Promise(r => setTimeout(r, 150));
  }
  ok('서버가 떴다', up, srvErr.slice(0, 300));

  console.log('\n[1] 아무것도 안 적었을 때');
  ok('설정 파일이 없는 집에서 시작한다', !fs.existsSync(CFG));
  const a = await get('/version');
  ok('로그인 없이 200', a.status === 200 && a.json.ok === true, a);
  ok('모양: ok · latest · min · urls 만 (개인정보 없음)',
     same(Object.keys(a.json).sort(), ['latest', 'min', 'ok', 'urls']), Object.keys(a.json));
  ok('latest 는 가게 셋, 전부 빈 값', same(a.json.latest, EMPTY), a.json.latest);
  ok('min 은 빈 값', a.json.min === '', a.json.min);
  ok('urls 는 기본 주소 셋', same(a.json.urls, APPVER.DEFAULT_URLS), a.json.urls);
  ok('기본 주소가 약속한 그대로다', same(APPVER.DEFAULT_URLS, {
    appstore: 'https://apps.apple.com/kr/app/id6815144446',
    play: 'https://play.google.com/store/apps/details?id=io.github.iacobuschoi.mybody',
    apk: 'https://github.com/iacobuschoi/Mybody/releases/latest'
  }), APPVER.DEFAULT_URLS);
  ok('중간에서 저장해 두지 않는다 (Cache-Control: no-store)',
     a.headers.get('cache-control') === 'no-store', a.headers.get('cache-control'));
  const tok = await get('/version', { headers: { Authorization: 'Bearer not-a-real-token' } });
  ok('엉터리 토큰을 붙여 와도 200 (로그인과 무관)', tok.status === 200 && tok.json.ok, tok.status);

  console.log('\n[2] 다른 길은 그대로');
  const h = await get('/health');
  ok('/health 모양이 그대로다', h.status === 200 && h.json.ok === true &&
     same(Object.keys(h.json).sort(), ['now', 'ok', 'openSignup']), h.json);
  const post = await get('/version', { method: 'POST', body: '{}',
                                       headers: { 'Content-Type': 'application/json' } });
  ok('POST /version 은 안 받는다 (로그인 필요로 떨어진다)', post.status === 401, post);
  const me = await get('/me');
  ok('/me 는 여전히 로그인이 필요하다 (401)', me.status === 401, me.status);

  console.log('\n[3] 도구로 바꾸면 다시 띄우지 않아도 나간다');
  const t1 = tool(['--apk=0.2.8', '--play', '0.2.7', '--min=0.2.6'], null, PORT);
  ok('도구가 저장한다 (exit 0)', t1.code === 0, t1.out);
  ok('도구가 서버에 물어 그 값이 나가는 것을 확인한다', /확인했습니다/.test(t1.out) &&
     !/다릅니다|답하지 않습니다/.test(t1.out), t1.out.slice(-400));
  ok('0.2.8 이하의 최소판은 아무에게도 안 뜬다고 말한다',
     /최소판\(0\.2\.6\)으로는 아무에게도 안내가 안 뜹니다/.test(t1.out) &&
     !/비어 있습니다/.test(t1.out), t1.out.slice(-400));
  const b = await get('/version');
  ok('latest 가 바뀌었다', same(b.json.latest, { appstore: '', play: '0.2.7', apk: '0.2.8' }),
     b.json.latest);
  ok('min 이 바뀌었다', b.json.min === '0.2.6', b.json.min);
  const t2 = tool(['--apk=none']);
  const c = await get('/version');
  ok('none 으로 지우면 바로 빈 값이다', t2.code === 0 && c.json.latest.apk === '' &&
     c.json.latest.play === '0.2.7', c.json.latest);
  const cfgNow = readCfg(CFG);
  cfgNow.appLatestAppStore = '0.2.9';
  writeCfg(CFG, cfgNow);
  const d = await get('/version');
  ok('설정 파일을 손으로 고쳐도 바로 나간다', d.json.latest.appstore === '0.2.9', d.json.latest);

  console.log('\n[4] 판 모양이 아닌 값');
  writeCfg(CFG, {
    appLatestAppStore: '0.2',
    appLatestPlay: 28,
    appLatestApk: '0.2.8-beta',
    appMin: 'abc',
    appUrlAppStore: 'https://example.com/mybody',
    appUrlPlay: 'javascript:alert(1)',
    appUrlApk: 'http://example.com/app.apk'
  });
  const e = await get('/version');
  ok('여전히 200', e.status === 200 && e.json.ok === true, e);
  ok('판 모양이 아닌 latest 는 전부 빈 값', same(e.json.latest, EMPTY), e.json.latest);
  ok('판 모양이 아닌 min 도 빈 값', e.json.min === '', e.json.min);
  ok('https 주소는 설정대로 바뀐다', e.json.urls.appstore === 'https://example.com/mybody',
     e.json.urls.appstore);
  ok('https 가 아닌 주소는 기본 주소로', e.json.urls.play === APPVER.DEFAULT_URLS.play &&
     e.json.urls.apk === APPVER.DEFAULT_URLS.apk, e.json.urls);
  writeCfg(CFG, { appLatestApk: ['0.2.8'], appMin: { v: '0.2.6' }, appLatestPlay: null,
                  appLatestAppStore: ' 0.2.08 ' });
  const f = await get('/version');
  ok('배열 · 객체 · null 도 빈 값', f.json.latest.apk === '' && f.json.min === '' &&
     f.json.latest.play === '', f.json);
  ok('앞뒤 공백 · 앞의 0 은 다듬어서 내보낸다 (" 0.2.08 " → 0.2.8)',
     f.json.latest.appstore === '0.2.8', f.json.latest);
  writeCfg(CFG, '{ 이건 JSON 이 아닙니다');
  const g = await get('/version');
  ok('설정 파일이 망가지면 빈 값이 아니라 503 (앱은 지난 답을 들고 다시 묻는다)',
     g.status === 503 && g.json.ok === false && !('latest' in g.json), g);
  writeCfg(CFG, '');
  const g2 = await get('/version');
  ok('저장하는 도중처럼 빈 파일이어도 503', g2.status === 503 && g2.json.ok === false, g2);
  writeCfg(CFG, '["0.2.8"]');
  const g3 = await get('/version');
  ok('JSON 이지만 객체가 아니면 503', g3.status === 503, g3);
  ok('그 뒤에도 서버가 살아 있다', (await get('/health')).status === 200);
  fs.rmSync(CFG);
  const g4 = await get('/version');
  ok('설정 파일이 아예 없으면 200 · 빈 값 (안내 없음)', g4.status === 200 &&
     same(g4.json.latest, EMPTY) && g4.json.min === '' &&
     same(g4.json.urls, APPVER.DEFAULT_URLS), g4);

  console.log('\n[5] 판 견주기');
  const cmp = APPVER.compareVersions;
  ok('0.2.10 이 0.2.9 보다 뒤 (글자로 견주면 거꾸로)', cmp('0.2.10', '0.2.9') > 0);
  ok('같으면 0', cmp('0.2.8', '0.2.8') === 0);
  ok('1.0.0 이 0.99.99 보다 뒤', cmp('1.0.0', '0.99.99') > 0);
  ok('판 모양 검사', APPVER.cleanVersion('0.2.8') === '0.2.8' &&
     ['', '0.2', '0.2.8.1', 'v0.2.8', '0.2.8+262', '0.2.8-beta', '1.2.x', '1234567.0.0']
       .every(v => APPVER.cleanVersion(v) === ''));

  console.log('\n[6] 도구 — 따로 떼어 놓은 집에서');
  const home2 = fs.mkdtempSync(path.join(os.tmpdir(), 'mybody-appver-home-'));
  const cfg2 = path.join(home2, '.mybody', 'config.json');
  writeCfg(cfg2, { pairSecret: 'keep-this-pair', anthropicKey: 'sk-keep-this', port: 9123 });
  fs.chmodSync(cfg2, 0o600);

  const show0 = tool([], home2);
  ok('인자 없이 돌리면 지금 값을 보여 주고 끝낸다', show0.code === 0 && /최소판/.test(show0.out),
     show0.out.slice(0, 200));
  ok('보기만 해서는 파일이 안 바뀐다', same(readCfg(cfg2),
     { pairSecret: 'keep-this-pair', anthropicKey: 'sk-keep-this', port: 9123 }));

  for (const bad of ['0.2', 'v0.2.8', '0.2.8+262', 'abc', '0.2.8.1']) {
    const r = tool(['--apk=' + bad], home2);
    ok(`틀린 판 "${bad}" → 거절 (exit 1)`, r.code === 1 && !('appLatestApk' in readCfg(cfg2)),
       r.out.slice(0, 200));
  }
  const unk = tool(['--apps=0.2.8'], home2);
  ok('모르는 깃발 → 거절', unk.code === 1, unk.out.slice(0, 200));
  const proto = tool(['--constructor=0.2.8'], home2);
  ok('Object 의 물려받은 이름(--constructor)도 거절 · 파일 그대로', proto.code === 1 &&
     same(readCfg(cfg2), { pairSecret: 'keep-this-pair', anthropicKey: 'sk-keep-this', port: 9123 }),
     proto.out.slice(0, 200));
  const noval = tool(['--apk'], home2);
  ok('값 없는 깃발 → 거절', noval.code === 1, noval.out.slice(0, 200));

  const s1 = tool(['--apk=0.2.10', '--play=0.2.10', '--appstore=0.2.9'], home2);
  const c1 = readCfg(cfg2);
  ok('맞는 판은 저장한다', s1.code === 0 && c1.appLatestApk === '0.2.10' &&
     c1.appLatestPlay === '0.2.10' && c1.appLatestAppStore === '0.2.9', c1);
  ok('가입 코드 · 판독 키 · 포트는 그대로다', c1.pairSecret === 'keep-this-pair' &&
     c1.anthropicKey === 'sk-keep-this' && c1.port === 9123, c1);
  ok('환경변수나 기본값을 파일에 굳히지 않는다',
     !('openSignup' in c1) && !('static' in c1) && !('appUrlApk' in c1), Object.keys(c1));
  const raw1 = fs.readFileSync(cfg2, 'utf8');
  ok('형식이 CONFIG.save 와 같다 (두 칸 들여쓰기 · 끝 줄바꿈)',
     raw1 === JSON.stringify(c1, null, 2) + '\n');
  if (process.platform !== 'win32') {
    ok('파일 권한 600 을 지킨다', (fs.statSync(cfg2).mode & 0o777) === 0o600,
       (fs.statSync(cfg2).mode & 0o777).toString(8));
  }

  const m1 = tool(['--min=0.2.10'], home2);
  ok('어느 가게 최신판보다 높은 최소판 → 거절', m1.code === 1 && !readCfg(cfg2).appMin,
     m1.out.slice(0, 300));
  ok('거절할 때 어느 가게인지 말한다', /앱스토어/.test(m1.out), m1.out.slice(0, 300));
  const m2 = tool(['--min=0.2.9'], home2);
  ok('최신판과 같은 최소판은 받는다', m2.code === 0 && readCfg(cfg2).appMin === '0.2.9',
     m2.out.slice(0, 200));
  ok('0.2.8 보다 높은 최소판에는 "아무에게도 안 뜬다" 를 안 붙인다',
     !/아무에게도/.test(m2.out), m2.out.slice(-300));
  const m3 = tool(['--appstore=0.2.8'], home2);
  ok('최신판을 최소판 아래로 내리는 것도 거절', m3.code === 1 &&
     readCfg(cfg2).appLatestAppStore === '0.2.9', m3.out.slice(0, 300));
  const m4 = tool(['--appstore=none', '--min=0.2.10'], home2);
  ok('비어 있는 가게는 견주지 않는다 (나머지 가게 기준)', m4.code === 0 &&
     readCfg(cfg2).appMin === '0.2.10' && readCfg(cfg2).appLatestAppStore === '', m4.out.slice(0, 200));
  ok('비어 있는 가게가 있으면 짚어 준다', /비어 있습니다/.test(m4.out), m4.out.slice(-300));

  console.log('\n[7] 도구가 서버에 확인한다');
  ok('서버가 꺼져 있으면(이 집의 포트 9123) 그렇다고 말한다 · 저장은 그대로 (exit 0)',
     m4.code === 0 && /9123 포트에서 서버가 답하지 않습니다/.test(m4.out), m4.out.slice(-500));
  const other = tool(['--apk=0.2.11'], home2, PORT);
  ok('그 포트의 서버가 다른 설정 파일을 읽으면 "다릅니다" · 저장은 그대로 (exit 0)',
     other.code === 0 && /내보내는 값이 여기 적힌 것과 다릅니다/.test(other.out) &&
     readCfg(cfg2).appLatestApk === '0.2.11', other.out.slice(-500));
  /* /api/version 이 생기기 전의 옛 서버 — 모르는 길에 로그인부터 묻습니다(401). */
  const old = http.createServer((q, s) => {
    s.writeHead(401, { 'Content-Type': 'application/json; charset=utf-8' });
    s.end(JSON.stringify({ ok: false, reason: '로그인이 필요합니다' }));
  });
  await new Promise(r => old.listen(0, '127.0.0.1', r));
  const o = await toolAsync(['--apk=0.2.12'], home2, old.address().port);
  old.close();
  ok('옛 서버 코드면 "다시 띄워야" 를 말한다', o.code === 0 && /옛 서버 코드/.test(o.out) &&
     /다시 띄워야/.test(o.out), o.out.slice(-500));
  const nobody = await freePort();
  const shown = tool([], home2, nobody);
  ok('값 보기만 해도 서버에 확인한다', shown.code === 0 &&
     new RegExp(nobody + ' 포트에서 서버가 답하지 않습니다').test(shown.out), shown.out.slice(-400));

  const cl1 = tool(['--min=', '--play', ''], home2);
  const cc = readCfg(cfg2);
  ok('빈 값 "" 으로도 지운다', cl1.code === 0 && cc.appMin === '' && cc.appLatestPlay === '', cc);
  const cl2 = tool(['--apk=없음'], home2);
  ok('"없음" 으로도 지운다', cl2.code === 0 && readCfg(cfg2).appLatestApk === '', readCfg(cfg2));
  const z = tool(['--apk=0.2.08'], home2);
  ok('앞의 0 은 다듬어 저장한다 (0.2.08 → 0.2.8)', z.code === 0 &&
     readCfg(cfg2).appLatestApk === '0.2.8', readCfg(cfg2));

  const broken = '{ "pairSecret": "keep", 망가짐';
  writeCfg(cfg2, broken);
  const br = tool(['--apk=0.2.9'], home2);
  ok('망가진 설정 파일 위에는 안 쓴다 (exit 1 · 내용 그대로)',
     br.code === 1 && fs.readFileSync(cfg2, 'utf8') === broken, br.out.slice(0, 200));

  const home3 = fs.mkdtempSync(path.join(os.tmpdir(), 'mybody-appver-home-'));
  const n = tool(['--apk=0.2.8'], home3);
  const cfg3 = path.join(home3, '.mybody', 'config.json');
  ok('설정이 없는 집이면 새로 만들고 그렇다고 말한다', n.code === 0 && fs.existsSync(cfg3) &&
     readCfg(cfg3).appLatestApk === '0.2.8' && /새로 만듭니다/.test(n.out), n.out.slice(0, 200));

  for (const hh of [home2, home3]) { try { fs.rmSync(hh, { recursive: true, force: true }); } catch (e) {} }
}

main()
  .catch(e => { fail++; console.error(e); })
  .finally(() => {
    try { srv.kill(); } catch (e) {}
    try { fs.rmSync(dir, { recursive: true, force: true }); } catch (e) {}
    console.log(`\n${pass} 통과 · ${fail} 실패`);
    process.exit(fail ? 1 : 0);
  });
