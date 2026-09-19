/* =============================================================================
 * tools/test-social.js — 친구 기능 전 구간 검증 (HTTP 계층까지)
 *
 * 서버를 직접 띄우고 실제 요청을 쏩니다. 권한 판정은 서버가 하므로
 * db.js 를 직접 부르지 않고 HTTP 로 두드려야 의미가 있습니다.
 *
 *   node tools/test-social.js
 * ========================================================================== */
'use strict';
const { spawn } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const PORT = 8300 + Math.floor(Math.random() * 500);
const DB = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'mybody-test-')), 'test.db');
const B = `http://localhost:${PORT}/api`;

let pass = 0, fail = 0;
const ok = (n, c, d) => {
  if (c) { pass++; console.log('  ✓', n); }
  else { fail++; console.log('  ✗', n, d === undefined ? '' : JSON.stringify(d)); }
};

async function call(m, p, body, tok) {
  const r = await fetch(B + p, {
    method: m,
    headers: { 'content-type': 'application/json', ...(tok ? { authorization: 'Bearer ' + tok } : {}) },
    body: body ? JSON.stringify(body) : undefined
  });
  return { status: r.status, json: await r.json().catch(() => ({})) };
}

async function waitUp(ms = 5000) {
  const until = Date.now() + ms;
  while (Date.now() < until) {
    try { if ((await fetch(`http://localhost:${PORT}/health`)).ok) return true; } catch {}
    await new Promise(r => setTimeout(r, 100));
  }
  throw new Error('서버가 뜨지 않습니다');
}

async function main() {
  console.log('\n[1] 로그인 · 계정');
  const A = await call('POST', '/auth/signin', { handle: 'gayoung', displayName: '가영' });
  const Bo = await call('POST', '/auth/signin', { handle: 'narin', displayName: '나린' });
  const ta = A.json.token, tb = Bo.json.token;
  ok('A 로그인', !!ta, A.json);
  ok('B 로그인', !!tb, Bo.json);
  ok('handle 없으면 400', (await call('POST', '/auth/signin', {})).status === 400);
  ok('같은 handle 재로그인 = 같은 계정',
     (await call('POST', '/auth/signin', { handle: 'gayoung' })).json.user.id === A.json.user.id);

  const meA = (await call('GET', '/me', null, ta)).json.user;
  const meB = (await call('GET', '/me', null, tb)).json.user;
  ok('초대코드 발급', !!meA.inviteCode && !!meB.inviteCode);
  ok('초대코드가 서로 다름', meA.inviteCode !== meB.inviteCode);
  ok('토큰 없으면 401', (await call('GET', '/me')).status === 401);
  ok('가짜 토큰 401', (await call('GET', '/me', null, 'deadbeef')).status === 401);
  ok('이름 수정',
     (await call('PATCH', '/me', { displayName: '가영2' }, ta)).json.user.displayName === '가영2');

  console.log('\n[2] 친구 요청 · 수락');
  ok('없는 코드 거부', (await call('POST', '/friends/request', { inviteCode: 'ZZZZZZ' }, ta)).json.ok === false);
  ok('내 코드로 요청 거부', (await call('POST', '/friends/request', { inviteCode: meA.inviteCode }, ta)).json.ok === false);
  ok('친구 요청', (await call('POST', '/friends/request', { inviteCode: meB.inviteCode }, ta)).json.ok === true);
  ok('같은 요청 두 번은 거부', (await call('POST', '/friends/request', { inviteCode: meB.inviteCode }, ta)).json.ok === false);
  const bl = (await call('GET', '/friends', null, tb)).json.friends;
  ok('B에게 요청 도착', bl.incoming.length === 1 && bl.outgoing.length === 0, bl);
  ok('보낸 쪽은 outgoing 에 있다', (await call('GET', '/friends', null, ta)).json.friends.outgoing.length === 1);
  ok('내가 보낸 요청을 내가 수락할 수 없다', (await call('POST', '/friends/accept', { userId: meB.id }, ta)).json.ok === false);
  ok('수락 전엔 남의 추이를 못 본다', (await call('GET', '/snapshots/' + meB.id, null, ta)).json.ok === false);
  ok('수락', (await call('POST', '/friends/accept', { userId: meA.id }, tb)).json.ok === true);
  ok('양쪽 모두 친구 목록에',
     (await call('GET', '/friends', null, ta)).json.friends.accepted.length === 1 &&
     (await call('GET', '/friends', null, tb)).json.friends.accepted.length === 1);

  console.log('\n[3] 공유 — 켠 것만 나간다');
  const payload = { dWeightKg: -0.8, dSmmKg: 0.2, dBfmKg: -0.9, progressPct: 42, checkedIn: true,
                    weightKg: 86.3, smmKg: 38.1, bfmKg: 19.9, pbfPct: 23.1 };
  await call('POST', '/snapshots', { weekStart: '2026-09-14', payload }, tb);
  const BODY = ['dWeightKg', 'dSmmKg', 'dBfmKg', 'progressPct', 'weightKg', 'smmKg', 'bfmKg', 'pbfPct'];
  let row = (await call('GET', '/snapshots/' + meB.id, null, ta)).json.rows[0];
  ok('기본값: 몸에 대한 정보는 하나도 안 나간다', BODY.every(k => !(k in row)), row);
  ok('기본값: 체크인 여부만 보인다', 'checkedIn' in row, row);

  ok('B가 체중만 켠다', (await call('PUT', '/share/' + meA.id, { weightTrend: true }, tb)).json.ok === true);
  row = (await call('GET', '/snapshots/' + meB.id, null, ta)).json.rows[0];
  ok('체중 변화 보임', 'dWeightKg' in row, row);
  ok('골격근·체지방은 여전히 숨김', !('dSmmKg' in row) && !('dBfmKg' in row), row);
  ok('실제 수치는 따로 켜야 나온다', !('weightKg' in row), row);
  ok('남의 공유 설정은 못 바꾼다', (await call('PUT', '/share/' + meB.id, { smmTrend: true }, ta)).json.ok === false ||
     !('dSmmKg' in (await call('GET', '/snapshots/' + meB.id, null, ta)).json.rows[0]));

  // 회귀 방지: absolute 는 표시 방식일 뿐, 항목을 새로 여는 스위치가 아닙니다.
  await call('PUT', '/share/' + meA.id, { absolute: true }, tb);
  row = (await call('GET', '/snapshots/' + meB.id, null, ta)).json.rows[0];
  ok('실제 수치는 켠 항목에만 붙는다', 'weightKg' in row, row);
  ok('안 켠 항목이 실제 수치로 새지 않는다',
     !('smmKg' in row) && !('bfmKg' in row) && !('pbfPct' in row), row);
  ok('아무 항목도 안 켜면 absolute 는 꺼진다',
     (await call('PUT', '/share/' + meA.id, { weightTrend: false }, tb)).json.share.absolute === false);

  console.log('\n[4] 끊기 · 차단 · 탈퇴');
  ok('친구 끊기', (await call('DELETE', '/friends/' + meB.id, null, ta)).json.ok === true);
  ok('끊으면 즉시 안 보인다', (await call('GET', '/snapshots/' + meB.id, null, ta)).json.ok === false);
  await call('POST', '/friends/request', { inviteCode: meB.inviteCode }, ta);
  ok('차단', (await call('POST', '/friends/block', { userId: meA.id }, tb)).json.ok === true);
  ok('차단하면 다시 요청 못 한다', (await call('POST', '/friends/request', { inviteCode: meB.inviteCode }, ta)).json.ok === false);

  console.log('\n[5] 동기화');
  await call('POST', '/sync/push', { records: [
    { kind: 'scan', id: 's1', updatedAt: '2026-09-01T00:00:00Z', payload: { weightKg: 86.3 } }
  ] }, ta);
  const pull = (await call('GET', '/sync/pull?since=', null, ta)).json;
  ok('푸시한 게 그대로 돌아온다', pull.records.length === 1 && pull.records[0].payload.weightKg === 86.3, pull);
  ok('커서 뒤는 빈 결과',
     (await call('GET', '/sync/pull?since=' + encodeURIComponent(pull.cursor), null, ta)).json.records.length === 0);
  ok('남의 기록은 안 섞인다', (await call('GET', '/sync/pull?since=', null, tb)).json.records.length === 0);

  console.log('\n[6] 탈퇴 뒷정리');
  const C = await call('POST', '/auth/signin', { handle: 'temp', displayName: '임시' });
  ok('탈퇴', (await call('DELETE', '/me', null, C.json.token)).json.ok === true);
  ok('탈퇴하면 토큰이 죽는다', (await call('GET', '/me', null, C.json.token)).status === 401);
  ok('탈퇴한 계정 코드로는 친구 요청이 안 된다',
     (await call('POST', '/friends/request', { inviteCode: C.json.user.inviteCode }, ta)).json.ok === false);
}

const srv = spawn(process.execPath, [path.join(__dirname, '..', 'server', 'server.js')], {
  env: { ...process.env, PORT: String(PORT), DB },
  stdio: 'ignore'
});
process.on('exit', () => srv.kill());

waitUp()
  .then(main)
  .then(() => {
    console.log(`\n통과 ${pass} / 실패 ${fail}`);
    srv.kill();
    process.exit(fail ? 1 : 0);
  })
  .catch(e => { console.error(e); srv.kill(); process.exit(1); });
