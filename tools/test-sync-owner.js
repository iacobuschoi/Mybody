/* =============================================================================
 * tools/test-sync-owner.js — 다른 계정의 기록 사본 · 주간 요약을 서버가 받지 않는가 (피드백 52)
 *
 *   node tools/test-sync-owner.js
 *
 * 왜 이 시험이 있나
 *   계정 A 로 쓰던 폰에서 로그아웃하고 새 계정 B 로 가입하니, A 의 기록이 B 의 서버 사본
 *   (records state/main)과 주간 요약(snapshots)으로 올라갔습니다. 앱은 이제 기록 칸에 주인을
 *   적고 계정이 바뀌면 칸을 갈아 끼웁니다(app/lib/src/local_owner.dart). 서버는 한 겹 더 막습니다 —
 *   새 앱은 사본의 syncMeta.owner 와 요약의 payload.owner 에 그 기록의 주인(계정 id)을 싣고,
 *   토큰의 계정과 다르면 409 {reason:'다른 계정의 기록입니다'} 로 거절하며 **아무 행도 안 바꿉니다.**
 *   owner 가 없는 옛 앱(0.2.19)은 받습니다.
 *
 * 보는 것
 *   [1] DB — push · publishSnapshot 이 owner ≠ me 면 거절하고 행이 그대로 · owner 없으면 받음 ·
 *       한 번에 보낸 것 중 하나라도 남의 것이면 하나도 안 씀 · 요약에서 owner 는 떼고 저장
 *   [2] 진짜 서버(A/B 두 계정) — 409 · 까닭 · 어느 계정의 행도 안 바뀜 · 옛 앱 모양은 200 ·
 *       미리 묻기(OPTIONS)가 X-Mybody-App 머리를 허락 · 거절 로그에 계정 id 가 없음
 * ========================================================================== */
'use strict';
require('./testenv.js');
const { spawn } = require('node:child_process');
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
const TMP = fs.mkdtempSync(path.join(os.tmpdir(), 'mybody-syncowner-'));
const PW = 'test-password-1';

const state = (owner, scans) => ({
  version: 1, onboarded: true, scans,
  syncMeta: Object.assign({ changedAt: {}, from: '' }, owner === undefined ? {} : { owner })
});
const rec = (payload, at) => ({ kind: 'state', id: 'main', updatedAt: at, payload });

/* --- [1] DB ------------------------------------------------------------------ */
function dbUnit() {
  console.log('\n[1] DB — push · publishSnapshot 의 주인 확인');
  const api = DBM.makeApi(DBM.open(path.join(TMP, 'unit.db')));
  const mk = h => api.signUp({ handle: h, password: PW, displayName: h, healthConsent: DBM.HEALTH_CONSENT_VERSION });
  const A = mk('alpha1').user.id, B = mk('bravo2').user.id;
  const rowsOf = me => JSON.stringify(api.pull(me).records);

  ok('A 가 자기 사본(owner=A)을 올린다', api.push(A, [rec(state(A, [{ id: 'scan-1758240000000' }]), '2026-09-19T00:00:00.000Z')]).ok);
  const aBefore = rowsOf(A);
  const r = api.push(B, [rec(state(A, [{ id: 'scan-1758240000000' }]), '2026-09-28T00:00:00.000Z')]);
  ok('B 토큰으로 온 A 의 사본(owner=A) → 거절 · conflict:owner · 까닭', r.ok === false && r.conflict === 'owner' &&
     r.reason === '다른 계정의 기록입니다' && r.accepted === 0, r);
  ok('B 의 행은 안 생기고 A 의 행도 그대로', rowsOf(B) === '[]' && rowsOf(A) === aBefore);

  const mixed = api.push(B, [rec(state(B, [{ id: 'b1' }]), '2026-09-28T00:00:00.000Z'),
                             Object.assign(rec(state(A, []), '2026-09-28T00:00:00.000Z'), { id: 'other' })]);
  ok('한 번에 보낸 것 중 하나라도 남의 것이면 하나도 안 씀', mixed.conflict === 'owner' && rowsOf(B) === '[]', mixed);

  ok('owner 가 없는 옛 앱(0.2.19) 모양은 받는다', api.push(B, [rec(state(undefined, [{ id: 'old' }]), '2026-09-28T00:00:00.000Z')]).ok &&
     /old/.test(rowsOf(B)));
  ok('자기 것(owner=B)은 받는다', api.push(B, [rec(state(B, [{ id: 'b1' }]), '2026-09-28T00:00:01.000Z')]).ok &&
     /b1/.test(rowsOf(B)) && rowsOf(A) === aBefore);

  const wk = '2026-09-28';
  ok('A 의 요약(owner=A)', api.publishSnapshot(A, wk, { owner: A, keptDays: 2 }).ok);
  const s1 = api.publishSnapshot(B, wk, { owner: A, keptDays: 5, weightKg: 86.7 });
  ok('B 토큰으로 온 A 의 요약 → 거절', s1.ok === false && s1.conflict === 'owner' && s1.reason === '다른 계정의 기록입니다', s1);
  const d = new DatabaseSync(path.join(TMP, 'unit.db'), { readOnly: true });
  try {
    const rowsB = d.prepare('SELECT payload FROM snapshots WHERE owner_id=?').all(B);
    const rowsA = d.prepare('SELECT payload FROM snapshots WHERE owner_id=?').all(A);
    ok('B 의 요약 행은 안 생긴다', rowsB.length === 0, rowsB);
    ok('A 의 요약은 그대로 · 저장된 요약에는 owner 칸이 없다', rowsA.length === 1 &&
       JSON.parse(rowsA[0].payload).keptDays === 2 && !('owner' in JSON.parse(rowsA[0].payload)), rowsA);
  } finally { d.close(); }
  ok('owner 없는 옛 요약 · 자기 요약은 받는다', api.publishSnapshot(B, wk, { keptDays: 1 }).ok &&
     api.publishSnapshot(B, wk, { owner: B, keptDays: 3 }).ok);
}

/* --- [2] 진짜 서버 ------------------------------------------------------------ */
const PORT = 10900 + Math.floor(Math.random() * 300);
const PAIR = 'syncowner-pair-secret';
const DB = path.join(TMP, 'srv.db');
const BASE = `http://127.0.0.1:${PORT}/api`;
let srv = null, out = '';

function boot() {
  out = '';
  const p = spawn(process.execPath, [path.join(ROOT, 'server', 'server.js')], {
    cwd: ROOT, stdio: ['ignore', 'pipe', 'pipe'],
    env: Object.assign({}, process.env, {
      PORT: String(PORT), PAIR_SECRET: PAIR, DB, AUTH_MAX: '100000',
      STATIC: path.join(ROOT, 'prototype'), NODE_NO_WARNINGS: '1'
    })
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
async function call(method, p, body, token, extra) {
  const r = await fetch(BASE + p, {
    method,
    headers: Object.assign({ 'Content-Type': 'application/json' },
      token ? { Authorization: 'Bearer ' + token } : {}, extra || {}),
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

async function integration() {
  console.log('\n[2] 진짜 서버 — 계정 A · B');
  srv = boot();
  ok('서버가 뜬다', await waitUp(), out.slice(-400));
  const mk = async h => (await call('POST', '/auth/signup', {
    handle: h, password: PW, displayName: h, pairSecret: PAIR, healthConsent: DBM.HEALTH_CONSENT_VERSION })).json;
  const A = await mk('acct_a'), B = await mk('acct_b');
  ok('두 계정 · 가입 응답에 user.id(앱이 칸의 주인으로 씀)', !!(A.token && B.token && A.user && A.user.id && B.user.id), [A, B]);
  const app = { 'X-Mybody-App': '0.2.20' };

  const a1 = await call('POST', '/sync/push', { records: [rec(state(A.user.id, [{ id: 'scan-1758240000000' }]), '2026-09-19T00:00:00.000Z')] }, A.token, app);
  ok('A 의 사본(owner=A) → 200', a1.status === 200 && a1.json.ok === true, a1.json);
  const snapRows = () => JSON.stringify(dbRows('SELECT owner_id, week_start, payload FROM snapshots ORDER BY owner_id'));
  const recRows = () => JSON.stringify(dbRows('SELECT user_id, kind, id, updated_at, payload FROM records ORDER BY user_id'));
  await call('POST', '/snapshots', { weekStart: '2026-09-28', payload: { owner: A.user.id, keptDays: 2 } }, A.token, app);
  const before = { recs: recRows(), snaps: snapRows() };

  /* 피드백 52 의 모양 — 로그아웃한 A 의 기록이 새로 가입한 B 의 토큰으로. */
  const leak = await call('POST', '/sync/push', { records: [rec(state(A.user.id, [{ id: 'scan-1758240000000' }]), '2026-09-28T00:00:00.000Z')] }, B.token, app);
  ok('B 토큰 + A 의 사본 → 409 {ok:false, reason:"다른 계정의 기록입니다"}', leak.status === 409 &&
     leak.json.ok === false && leak.json.reason === '다른 계정의 기록입니다', [leak.status, leak.json]);
  const leakSnap = await call('POST', '/snapshots', { weekStart: '2026-09-28', payload: { owner: A.user.id, keptDays: 5, weightKg: 86.7 } }, B.token, app);
  ok('B 토큰 + A 의 요약 → 409', leakSnap.status === 409 && leakSnap.json.reason === '다른 계정의 기록입니다', [leakSnap.status, leakSnap.json]);
  ok('어느 계정의 행도 안 바뀐다 (records · snapshots)', recRows() === before.recs && snapRows() === before.snaps);
  ok('B 쪽 행은 하나도 없다', dbRows('SELECT 1 FROM records WHERE user_id=?', B.user.id).length === 0 &&
     dbRows('SELECT 1 FROM snapshots WHERE owner_id=?', B.user.id).length === 0);

  /* 옛 앱(0.2.19) — owner 도 머리도 없습니다. 막을 방법이 없으니 받습니다. */
  const old = await call('POST', '/sync/push', { records: [rec(state(undefined, [{ id: 'b-old' }]), '2026-09-28T00:00:00.000Z')] }, B.token);
  ok('owner 없는 옛 앱의 사본 → 200', old.status === 200 && old.json.ok === true, old.json);
  const oldSnap = await call('POST', '/snapshots', { weekStart: '2026-09-28', payload: { keptDays: 1 } }, B.token);
  ok('owner 없는 옛 앱의 요약 → 200', oldSnap.status === 200, oldSnap.json);
  const own = await call('POST', '/sync/push', { records: [rec(state(B.user.id, [{ id: 'b1' }]), '2026-09-28T00:00:01.000Z')] }, B.token, app);
  ok('자기 사본(owner=B) → 200', own.status === 200, own.json);
  ok('A 의 행은 끝까지 그대로', JSON.stringify(dbRows(
    'SELECT user_id, kind, id, updated_at, payload FROM records WHERE user_id=? ORDER BY user_id', A.user.id)) === before.recs);
  const pulledA = await call('GET', '/sync/pull', null, A.token);
  ok('A 가 받아 보면 A 의 것만', pulledA.status === 200 && /scan-1758240000000/.test(pulledA.text) && !/b-old|"b1"/.test(pulledA.text));

  const pre = await fetch(BASE + '/sync/push', { method: 'OPTIONS',
    headers: { Origin: 'https://example.test', 'Access-Control-Request-Method': 'POST',
               'Access-Control-Request-Headers': 'content-type, authorization, x-mybody-app' } });
  ok('미리 묻기(OPTIONS)가 x-mybody-app 머리를 허락', /x-mybody-app/i.test(pre.headers.get('access-control-allow-headers') || ''),
     pre.headers.get('access-control-allow-headers'));

  await wait(100);
  const lines = out.split('\n').filter(l => /다른 계정의 기록을 거절/.test(l));
  ok('거절은 로그에 한 줄씩 · 앱 판은 적고 계정 id 는 안 적는다', lines.length === 2 &&
     lines.every(l => /0\.2\.20/.test(l) && !l.includes(A.user.id) && !l.includes(B.user.id)), lines);
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
