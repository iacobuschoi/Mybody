/* =============================================================================
 * tools/test-operator-users.js — 운영자의 앱 안 「가입자 목록」 (GET /api/operator/users)
 *
 *   node tools/test-operator-users.js
 *
 * 왜 이 시험이 있나
 *   가입한 사람의 아이디 · 이름 · 가입일은 노트북에서 tools/reset-password.js 로만 보던 것입니다.
 *   그 문을 "운영자 계정의 앱" 으로 넓혔으니, 넓힌 문이 **운영자 한 사람에게만** 열리는지와
 *   열린 쪽으로 **비밀(비밀번호 · 복구 코드 해시, 토큰, 초대 코드, 내부 id, 알림 기기)이 한 조각도
 *   안 나가는지**를 HTTP 로 두드려 봅니다. 운영자 = 설정의 feedbackNotify(FEEDBACK_NOTIFY) 아이디의
 *   계정(의견함과 같음). 비었으면 아무도 아님.
 *
 * 보는 것
 *   [1] DB — 새 가입부터 · total · limit 1~1000 · me 표시 · 세 칸만 · 표시 이름 거르기
 *   [2] 진짜 서버
 *       · 로그인 없음 · 틀린 토큰 → 401 / 운영자 아님 → /api/operator/ 아래 어느 길이든 403
 *       · 운영자 → 200 {ok, total, users} · 새 가입부터 · me 는 본인 줄에만 · 캐시 금지
 *       · 응답에 비밀 칸 · 비밀 값이 없다 (DB 에서 꺼낸 실제 값과 맞대 봄)
 *       · limit 범위 · 1000명 상한(넘으면 새 가입부터 1000명, total 은 전체)
 *       · 운영자에게도 없는 길은 404 · 로그에 이름이 안 남음
 *   [3] FEEDBACK_NOTIFY 가 비었으면 아무도 운영자가 아님
 * ========================================================================== */
'use strict';
/* 검사하는 사람의 ~/.mybody 설정(의견 알림 아이디 등)이 결과를 바꾸지 않게. */
require('./testenv.js');
const { spawn } = require('node:child_process');
const crypto = require('node:crypto');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { DatabaseSync } = require('node:sqlite');

const ROOT = path.join(__dirname, '..');
const DBM = require(path.join(ROOT, 'server', 'db.js'));

let pass = 0, fail = 0;
const ok = (n, c, d) => {
  if (c) { pass++; console.log('  ✓', n); }
  else { fail++; console.log('  ✗', n, d === undefined ? '' : JSON.stringify(d).slice(0, 400)); }
};
const wait = ms => new Promise(r => setTimeout(r, ms));
const TMP = fs.mkdtempSync(path.join(os.tmpdir(), 'mybody-opusers-'));
const PW = 'test-password-1';
const KEYS = ['createdAt', 'displayName', 'handle'];
const keysOk = u => {
  const k = Object.keys(u).filter(x => x !== 'me').sort();
  return JSON.stringify(k) === JSON.stringify(KEYS) && (!('me' in u) || u.me === true);
};

/* 서버를 거치지 않고 계정 행을 넣습니다 — scrypt 를 천 번 돌리지 않고 상한을 보려고. */
function insertUsers(file, n, { from = Date.UTC(2020, 0, 1), step = 60000, prefix = 'bulk' } = {}) {
  const d = new DatabaseSync(file);
  try {
    const st = d.prepare('INSERT INTO users (id, handle, provider, display_name, invite_code, created_at) VALUES (?,?,?,?,?,?)');
    d.exec('BEGIN');
    for (let i = 0; i < n; i++) {
      st.run('user_' + crypto.randomBytes(8).toString('hex'), `${prefix}${String(i).padStart(4, '0')}`, 'local',
             '묶음' + i, crypto.randomBytes(6).toString('hex').toUpperCase(), new Date(from + i * step).toISOString());
    }
    d.exec('COMMIT');
  } finally { d.close(); }
}

/* --- [1] DB ---------------------------------------------------------------- */
function dbUnit() {
  console.log('\n[1] DB — operatorListUsers');
  const file = path.join(TMP, 'unit.db');
  const api = DBM.makeApi(DBM.open(file));
  const mk = (h, name) => api.signUp({ handle: h, password: PW, displayName: name, healthConsent: DBM.HEALTH_CONSENT_VERSION });
  const a = mk('alpha1', '가나다');
  const b = mk('beta22', '라마‮바\n사\x1b');
  const c = mk('gamma3', '아자차');

  const all = api.operatorListUsers({ meId: b.user.id });
  ok('새 가입부터 (gamma3 · beta22 · alpha1) · total 3', JSON.stringify(all.users.map(u => u.handle)) ===
     JSON.stringify(['gamma3', 'beta22', 'alpha1']) && all.total === 3, all);
  ok('줄마다 handle · displayName · createdAt 만 (+ 본인 줄에만 me:true)', all.users.every(keysOk) &&
     all.users.filter(u => u.me).length === 1 && all.users[1].me === true, all.users);
  ok('createdAt 은 ISO 시각', all.users.every(u => /^\d{4}-\d{2}-\d{2}T[\d:.]+Z$/.test(u.createdAt)));
  ok('표시 이름의 제어 · 방향 뒤집기 문자는 거르고 한 줄로', all.users[1].displayName === '라마바 사', all.users[1].displayName);
  const text = JSON.stringify(all);
  ok('내부 id · 초대 코드가 없다', ![a, b, c].some(x => text.includes(x.user.id) || text.includes(x.user.inviteCode)));
  ok('meId 가 없으면 me 도 없다', api.operatorListUsers().users.every(u => !('me' in u)));
  ok('limit 1~1000 으로 자름 (0 → 1명 · 2 → 2명 · 글자 → 전부)', api.operatorListUsers({ limit: 0 }).users.length === 1 &&
     api.operatorListUsers({ limit: 2 }).users.length === 2 && api.operatorListUsers({ limit: 'x' }).users.length === 3 &&
     api.operatorListUsers({ limit: 2 }).total === 3);
  ok('reset-password 의 목록(adminListUsers)은 그대로 — 옛 가입부터 세 칸', JSON.stringify(api.adminListUsers().map(u => u.handle)) ===
     JSON.stringify(['alpha1', 'beta22', 'gamma3']) && api.adminListUsers().every(u => JSON.stringify(Object.keys(u).sort()) === JSON.stringify(KEYS)));
  ok('상한 상수는 1000', DBM.USERS_LIST_MAX === 1000);
}

/* --- [2] 진짜 서버 ------------------------------------------------------------ */
const PORT = 10600 + Math.floor(Math.random() * 300);
const PAIR = 'opusers-pair-secret';
const DB = path.join(TMP, 'srv.db');
const B = `http://127.0.0.1:${PORT}/api`;

let srv = null, out = '';
function boot(env) {
  out = '';
  const p = spawn(process.execPath, [path.join(ROOT, 'server', 'server.js')], {
    cwd: ROOT, stdio: ['ignore', 'pipe', 'pipe'],
    env: Object.assign({}, process.env, {
      PORT: String(PORT), PAIR_SECRET: PAIR, DB, AUTH_MAX: '100000',
      STATIC: path.join(ROOT, 'prototype'), NODE_NO_WARNINGS: '1'
    }, env || {})
  });
  p.stdout.on('data', d => { out += d; });
  p.stderr.on('data', d => { out += d; });
  return p;
}
async function stop() {
  if (!srv) return;
  const p = srv; srv = null;
  await new Promise(r => { p.once('exit', r); try { p.kill('SIGTERM'); } catch (e) { r(); } setTimeout(r, 3000); });
}
async function waitUp() {
  for (let i = 0; i < 80; i++) {
    try { if ((await fetch(`http://127.0.0.1:${PORT}/api/health`)).ok) return true; } catch (e) {}
    await wait(150);
  }
  return false;
}
async function call(method, p, body, token) {
  const r = await fetch(B + p, {
    method,
    headers: Object.assign({ 'Content-Type': 'application/json' }, token ? { Authorization: 'Bearer ' + token } : {}),
    body: body !== undefined && body !== null ? JSON.stringify(body) : undefined
  });
  const text = await r.text();
  let j = null; try { j = JSON.parse(text); } catch (e) {}
  return { status: r.status, json: j || {}, text, h: r.headers };
}
function dbRows(sql, ...args) {
  const d = new DatabaseSync(DB, { readOnly: true });
  try { return d.prepare(sql).all(...args); } finally { d.close(); }
}
const is403 = r => r.status === 403 && r.json.ok === false && r.json.error === '운영자만 볼 수 있어요' &&
  !/users|handle|displayName/.test(r.text);
const is401 = r => r.status === 401 && r.json.ok === false;
const noStore = r => r.h.get('cache-control') === 'private, no-store';

async function integration() {
  console.log('\n[2] 진짜 서버 — 운영자(FEEDBACK_NOTIFY=" Owner ")');
  srv = boot({ FEEDBACK_NOTIFY: ' Owner ' });
  ok('서버가 뜬다', await waitUp(), out.slice(-400));
  const mk = async (handle, name) => (await call('POST', '/auth/signup', {
    handle, password: PW, displayName: name, pairSecret: PAIR, healthConsent: DBM.HEALTH_CONSENT_VERSION })).json;
  /* 서버가 뜬 **뒤에** 운영자 계정이 생깁니다 — 운영자를 요청마다 다시 찾는지. */
  const T = await mk('tester1', '시험자');
  const O = await mk('owner', '주인');
  const X = await mk('other1', '다른이');
  ok('계정 셋 (시험자 → 주인 → 다른이 차례로 가입)', !!(O.token && T.token && X.token));
  const pushTok = 'ok_owner_' + crypto.randomBytes(24).toString('hex');
  ok('운영자 폰(앱 알림) 등록 — 알림 기기 토큰이 목록에 새는지 보려고',
     (await call('POST', '/push/device', { token: pushTok, platform: 'android', permission: 'granted' }, O.token)).status === 200);

  /* --- 막는 것 ------------------------------------------------------------------ */
  const routes = [['GET', '/operator/users'], ['GET', '/operator/users?limit=1'], ['POST', '/operator/users'],
                  ['GET', '/operator'], ['GET', '/operator/nope'], ['DELETE', '/operator/users/owner']];
  const unauth = [], badTok = [], nonOp = [];
  for (const [m, p] of routes) {
    unauth.push([m, p, is401(await call(m, p))]);
    badTok.push([m, p, is401(await call(m, p, null, 'not-a-real-token'))]);
    nonOp.push([m, p, is403(await call(m, p, null, T.token)) && is403(await call(m, p, null, X.token))]);
  }
  ok('로그인 없으면 401 (다른 길과 같은 관문)', unauth.every(x => x[2]), unauth.filter(x => !x[2]));
  ok('틀린 토큰도 401', badTok.every(x => x[2]), badTok.filter(x => !x[2]));
  ok('운영자가 아니면 어느 길이든 403 {ok:false, error:"운영자만 볼 수 있어요"} (없는 길도 — 길이 있는지 모르게)',
     nonOp.every(x => x[2]), nonOp.filter(x => !x[2]));
  const nonOpRes = await call('GET', '/operator/users', null, T.token);
  ok('403 도 캐시 금지 · 이름 · 아이디가 한 조각도 없다', noStore(nonOpRes) && !/tester1|owner|other1|시험자|주인|다른이/.test(nonOpRes.text),
     nonOpRes.text);

  /* --- 운영자 ------------------------------------------------------------------- */
  const L = await call('GET', '/operator/users', null, O.token);
  ok('운영자: 200 {ok:true, total, users}', L.status === 200 && L.json.ok === true && Array.isArray(L.json.users) &&
     L.json.total === 3, L.json);
  ok('캐시 금지 (private, no-store) · nosniff', noStore(L) && L.h.get('x-content-type-options') === 'nosniff',
     L.h.get('cache-control'));
  ok('새 가입부터 (other1 · owner · tester1)', JSON.stringify((L.json.users || []).map(u => u.handle)) ===
     JSON.stringify(['other1', 'owner', 'tester1']), (L.json.users || []).map(u => u.handle));
  ok('createdAt 내림차순', (L.json.users || []).every((u, i, a) => i === 0 || a[i - 1].createdAt >= u.createdAt));
  const by = h => (L.json.users || []).find(u => u.handle === h) || {};
  ok('이름 · 가입 시각이 실린다', by('tester1').displayName === '시험자' && by('owner').displayName === '주인' &&
     /^\d{4}-\d{2}-\d{2}T[\d:.]+Z$/.test(by('other1').createdAt), L.json.users);
  ok('me:true 는 운영자 본인 줄에만', by('owner').me === true && !('me' in by('tester1')) && !('me' in by('other1')));
  ok('줄마다 handle · displayName · createdAt (+me) 만', (L.json.users || []).every(keysOk), L.json.users);

  /* 비밀 — DB 에서 실제 값을 꺼내 응답에 한 조각이라도 있는지 맞대 봅니다. */
  const secrets = [];
  for (const u of dbRows('SELECT id, invite_code, pw_hash, pw_salt, rc_hash, rc_salt FROM users')) {
    secrets.push(u.id, u.invite_code, u.pw_hash, u.pw_salt, u.rc_hash, u.rc_salt);
  }
  for (const s of dbRows('SELECT token FROM sessions')) secrets.push(s.token);
  for (const d of dbRows('SELECT token FROM push_devices')) secrets.push(d.token);
  secrets.push(O.recoveryCode, T.recoveryCode, X.recoveryCode, PW, pushTok);
  const leaked = secrets.filter(s => s && L.text.includes(String(s).slice(0, 16)));
  ok('비밀 값이 하나도 없다 (내부 id · 초대 코드 · 비밀번호/복구 코드 해시 · 솔트 · 세션 토큰 · 알림 토큰 · 복구 코드)',
     secrets.length >= 20 && leaked.length === 0, leaked.map(s => String(s).slice(0, 8)));
  ok('비밀 칸 이름도 없다 (password · salt · hash · token · invite · recovery · email · avatar · id)',
     !/pw_|password|salt|hash|token|invite|recover|email|avatar|"id"|userId|consent|provider/i.test(L.text), L.text.slice(0, 300));

  /* --- limit · 상한 --------------------------------------------------------------- */
  const l1 = await call('GET', '/operator/users?limit=1', null, O.token);
  const l0 = await call('GET', '/operator/users?limit=0', null, O.token);
  const lBad = await call('GET', '/operator/users?limit=abc', null, O.token);
  ok('limit=1 → 가장 새 한 명 · total 은 전체 3', l1.json.users.length === 1 && l1.json.users[0].handle === 'other1' &&
     l1.json.total === 3, l1.json);
  ok('limit=0 → 1명 · 글자 → 기본(전부)', l0.json.users.length === 1 && lBad.json.users.length === 3,
     [l0.json.users.length, lBad.json.users.length]);

  /* 1005명을 더 넣습니다 — 2020년(지금 계정들보다 옛날)에 1분 간격. 마지막 하나는 일부러 다른 행들보다
     먼저 넣고 시각만 가장 늦게(2021년) 둡니다: 차례는 넣은 차례(rowid)가 아니라 가입 시각입니다. */
  insertUsers(DB, 1, { from: Date.UTC(2021, 5, 1), prefix: 'late' });
  insertUsers(DB, 1004);
  const big = await call('GET', '/operator/users', null, O.token);
  const bh = (big.json.users || []).map(u => u.handle);
  ok('1008명이면 새 가입부터 1000명만 · total 은 1008', bh.length === 1000 && big.json.total === 1008,
     [bh.length, big.json.total]);
  ok('맨 위는 여전히 지금 가입한 셋 · 그다음이 2021년 행(나중에 넣은 차례가 아니라 가입 시각)',
     JSON.stringify(bh.slice(0, 4)) === JSON.stringify(['other1', 'owner', 'tester1', 'late0000']), bh.slice(0, 5));
  ok('잘린 것은 가장 옛 가입 여덟 (bulk0000 ~ bulk0007)', bh[999] === 'bulk0008' &&
     !bh.some(h => /^bulk000[0-7]$/.test(h)), bh.slice(-3));
  ok('전체가 createdAt 내림차순', big.json.users.every((u, i, a) => i === 0 || a[i - 1].createdAt >= u.createdAt));
  const huge = await call('GET', '/operator/users?limit=5000', null, O.token);
  ok('limit=5000 이어도 1000명까지', huge.json.users.length === 1000 && huge.json.total === 1008, huge.json.users.length);
  ok('응답 크기가 한 번에 끝없이 크지 않다 (1000명 < 200KB)', big.text.length < 200_000, big.text.length);

  /* --- 운영자에게도 없는 길 --------------------------------------------------------- */
  const nf = [];
  for (const [m, p] of [['POST', '/operator/users'], ['GET', '/operator'], ['GET', '/operator/nope'],
                        ['DELETE', '/operator/users/owner'], ['GET', '/operator/users/1']]) {
    const r = await call(m, p, null, O.token);
    if (!(r.status === 404 && r.json.ok === false && noStore(r))) nf.push([m, p, r.status]);
  }
  ok('운영자에게도 없는 길 · 메서드는 404 {ok:false} · no-store', nf.length === 0, nf);

  ok('로그에는 경로 · 상태만 — 이름 · 아이디가 안 남는다', /GET\s+\/api\/operator\/users/.test(out) &&
     !/시험자|다른이|tester1|other1/.test(out), out.split('\n').filter(l => /operator/.test(l)).slice(0, 3));

  /* --- [3] 운영자가 없을 때 ----------------------------------------------------- */
  console.log('\n[3] FEEDBACK_NOTIFY 가 비었으면 아무도 운영자가 아님');
  await stop();
  srv = boot({ FEEDBACK_NOTIFY: '' });
  ok('FEEDBACK_NOTIFY="" 로 다시 뜬다', await waitUp(), out.slice(-300));
  const emptyBad = [];
  for (const [m, p] of routes) {
    const r = await call(m, p, null, O.token);
    if (!is403(r)) emptyBad.push([m, p, r.status]);
  }
  ok('비었으면: 옛 운영자도 모든 길 403', emptyBad.length === 0, emptyBad);
  await stop();
}

(async () => {
  try {
    dbUnit();
    await integration();
  } catch (e) {
    fail++;
    console.error(e);
  }
  await stop();
  try { fs.rmSync(TMP, { recursive: true, force: true }); } catch (e) {}
  console.log(`\n통과 ${pass} / 실패 ${fail}`);
  process.exit(fail ? 1 : 0);
})();
process.on('exit', () => { if (srv) { try { srv.kill(); } catch (e) {} } });
