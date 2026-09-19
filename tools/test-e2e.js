/* =============================================================================
 * tools/test-e2e.js — 브라우저 두 개가 서버를 통해 친구가 되는지 확인
 *
 * 이 테스트가 필요한 이유: 여기 오기 전까지 브라우저 앱에는 fetch 가 한 개도
 * 없었습니다. 서버 테스트(test-social.js)는 HTTP 로만 때렸고, 화면 테스트
 * (smoke.js)는 localStorage 만 봤습니다. 둘 다 통과하는데 실제 앱에서는
 * 친구 기능이 한 브라우저 안에서만 작동했습니다.
 *
 * 그 사이를 재는 테스트가 이것입니다 — 진짜 브라우저 두 개, 진짜 서버.
 *   node tools/test-e2e.js
 * ========================================================================== */
'use strict';
const { spawn } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { chromium } = require(process.env.NODE_PATH
  ? path.join(process.env.NODE_PATH, 'playwright')
  : 'playwright');

const PORT = 8600 + Math.floor(Math.random() * 300);
const PAIR = 'e2e-pair-secret';
const DB = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'mybody-e2e-')), 'e2e.db');
const BASE = `http://localhost:${PORT}`;

let pass = 0, fail = 0;
const ok = (n, c, d) => {
  if (c) { pass++; console.log('  ✓', n); }
  else { fail++; console.log('  ✗', n, d === undefined ? '' : JSON.stringify(d)); }
};

async function waitUp(ms = 8000) {
  const until = Date.now() + ms;
  while (Date.now() < until) {
    try { if ((await fetch(BASE + '/health')).ok) return true; } catch {}
    await new Promise(r => setTimeout(r, 120));
  }
  throw new Error('서버가 뜨지 않습니다');
}

/** 한 "기기" = 브라우저 컨텍스트 하나. localStorage 가 서로 완전히 분리됩니다. */
async function device(browser, label) {
  const ctx = await browser.newContext({ viewport: { width: 420, height: 900 } });
  const page = await ctx.newPage();
  const errs = [];
  page.on('pageerror', e => errs.push(label + ': ' + e.message));
  page.on('console', m => { if (m.type() === 'error') errs.push(label + ' CONSOLE: ' + m.text().slice(0, 160)); });
  await page.goto(BASE + '/', { waitUntil: 'load' });
  await page.waitForTimeout(500);
  return { ctx, page, errs, label };
}

const ev = (d, fn, arg) => d.page.evaluate(fn, arg);

async function main() {
  const browser = await chromium.launch({ executablePath: process.env.CHROME ||
    '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const A = await device(browser, '가영폰');
  const B = await device(browser, '나린폰');

  console.log('\n[1] 서버가 앱을 서빙하는가');
  ok('앱이 로드됨', await ev(A, () => !!window.MB_APP));
  ok('sync 계층이 있음', await ev(A, () => !!window.MB_SYNC));
  ok('서버 주소를 자동으로 잡음',
     (await ev(A, () => window.MB_SYNC.status().baseUrl)) === BASE,
     await ev(A, () => window.MB_SYNC.status().baseUrl));

  console.log('\n[2] 계정 만들기 — 우리 서버에서');
  const bad = await ev(A, () => window.MB_SYNC.signUp({
    handle: 'gayoung', password: 'short', pairSecret: 'e2e-pair-secret' })
    .then(() => null).catch(e => e.message));
  ok('짧은 비밀번호 거부', /8자/.test(bad || ''), bad);

  const noPair = await ev(A, () => window.MB_SYNC.signUp({
    handle: 'gayoung', password: 'correct-horse-1', pairSecret: 'wrong' })
    .then(() => null).catch(e => e.message));
  ok('가입 코드 없이는 불가', /가입 코드/.test(noPair || ''), noPair);

  const rA = await ev(A, () => window.MB_SYNC.signUp({
    handle: 'gayoung', password: 'correct-horse-1', displayName: '가영',
    pairSecret: 'e2e-pair-secret' }).then(r => r.user).catch(e => ({ err: e.message })));
  ok('가영 가입', !!rA.inviteCode, rA);

  const rB = await ev(B, () => window.MB_SYNC.signUp({
    handle: 'narin', password: 'correct-horse-2', displayName: '나린',
    pairSecret: 'e2e-pair-secret' }).then(r => r.user).catch(e => ({ err: e.message })));
  ok('나린 가입', !!rB.inviteCode, rB);
  ok('초대 코드가 서로 다름', rA.inviteCode !== rB.inviteCode);

  console.log('\n[3] 비밀번호 로그인');
  const wrong = await ev(A, () => window.MB_SYNC.signIn({ handle: 'gayoung', password: 'nope-nope-1' })
    .then(() => null).catch(e => e.message));
  ok('틀린 비밀번호 거부', /맞지 않습니다/.test(wrong || ''), wrong);
  const right = await ev(A, () => window.MB_SYNC.signIn({ handle: 'gayoung', password: 'correct-horse-1' })
    .then(r => r.user.id).catch(e => ({ err: e.message })));
  ok('맞는 비밀번호로 로그인', right === rA.id, right);

  console.log('\n[4] 다른 기기끼리 친구가 되는가  ← 핵심');
  const sent = await ev(A, code => window.MB_SYNC.sendRequest(code)
    .then(() => 'ok').catch(e => e.message), rB.inviteCode);
  ok('초대 코드로 요청 전송', sent === 'ok', sent);
  await A.page.waitForTimeout(700);
  await ev(B, () => window.MB_SYNC.pull());
  await B.page.waitForTimeout(500);

  const incoming = await ev(B, () => window.MB_BACKEND.listFriends().incoming.map(x => x.displayName));
  ok('나린 폰에 가영의 요청이 도착', incoming.length === 1 && incoming[0] === '가영', incoming);

  await ev(B, id => window.MB_BACKEND.accept(id), rA.id);
  await ev(B, () => window.MB_SYNC.flush());
  await B.page.waitForTimeout(700);
  await ev(A, () => window.MB_SYNC.pull());
  await A.page.waitForTimeout(500);

  ok('가영 폰에도 친구로 보임',
     (await ev(A, () => window.MB_BACKEND.listFriends().accepted.map(x => x.displayName))).includes('나린'));
  ok('나린 폰에도 친구로 보임',
     (await ev(B, () => window.MB_BACKEND.listFriends().accepted.map(x => x.displayName))).includes('가영'));

  console.log('\n[5] 공유 설정이 상대 화면에 실제로 반영되는가');
  await ev(B, () => { window.MB_STORE.seed(); window.MB_STORE.publishWeekly(); });
  await ev(B, () => window.MB_SYNC.flush());
  await B.page.waitForTimeout(700);
  await ev(A, () => window.MB_SYNC.pull());
  await A.page.waitForTimeout(500);

  let row = await ev(A, id => {
    const r = window.MB_BACKEND.getFriendSnapshots(id, 26);
    return r.rows[0] || null;
  }, rB.id);
  ok('기본값에서는 몸 정보가 없다',
     !row || (!('dWeightKg' in row) && !('dBfmKg' in row) && !('weightKg' in row)), row);

  await ev(B, id => window.MB_BACKEND.setShare(id, { bfmTrend: true }), rA.id);
  await ev(B, () => window.MB_SYNC.flush());
  await B.page.waitForTimeout(700);
  await ev(A, () => window.MB_SYNC.pull());
  await A.page.waitForTimeout(500);

  row = await ev(A, id => {
    const r = window.MB_BACKEND.getFriendSnapshots(id, 26);
    return r.rows[0] || null;
  }, rB.id);
  ok('나린이 켠 항목이 가영 화면에 나타남', !!row && ('dBfmKg' in row), row);
  ok('안 켠 항목은 여전히 없음', !!row && !('dWeightKg' in row) && !('weightKg' in row), row);

  console.log('\n[6] 오프라인에서도 앱이 멈추지 않는가');
  await A.ctx.setOffline(true);
  const offlineOk = await ev(A, () => {
    try { window.MB_APP.go('P15'); return document.querySelector('#main').innerText.length > 30; }
    catch (e) { return 'ERR: ' + e.message; }
  });
  ok('오프라인에서 친구 탭이 열림', offlineOk === true, offlineOk);
  await ev(A, id => window.MB_BACKEND.setShare(id, { streak: false }), rB.id);
  const queued = await ev(A, () => window.MB_SYNC.status().pending);
  ok('오프라인 변경이 큐에 쌓임', queued > 0, { queued });
  await A.ctx.setOffline(false);
  await ev(A, () => window.MB_SYNC.flush());
  await A.page.waitForTimeout(900);
  ok('온라인이 되면 큐가 비워짐', (await ev(A, () => window.MB_SYNC.status().pending)) === 0);

  console.log('\n[7] 로그아웃하면 이 기기에 남의 흔적이 없는가');
  await ev(A, () => window.MB_SYNC.signOut());
  await A.page.waitForTimeout(400);
  const after = await ev(A, () => ({
    user: window.MB_BACKEND.currentUser(),
    raw: JSON.stringify(window.MB_BACKEND.raw()).length
  }));
  ok('로그아웃 후 계정 없음', after.user === null, after);

  /* 이 테스트는 일부러 실패하는 요청을 보냅니다 — 짧은 비밀번호(400),
     틀린 비밀번호(401), 오프라인(ERR_INTERNET_DISCONNECTED).
     브라우저는 그것도 콘솔 오류로 찍으므로, 예상된 것은 빼고 셉니다.
     실제 JS 예외(pageerror)는 하나도 없어야 합니다. */
  const EXPECTED = /status of (400|401|429)|ERR_INTERNET_DISCONNECTED/;
  const allErrs = [...new Set([...A.errs, ...B.errs])];
  const real = allErrs.filter(e => !EXPECTED.test(e));
  console.log('\n[8] JS 오류');
  ok('예상 못 한 오류 0건', real.length === 0, real.slice(0, 4));
  console.log('    (예상된 오류 ' + (allErrs.length - real.length) + '건은 제외 — 일부러 실패시킨 요청들)');

  await browser.close();
}

const srv = spawn(process.execPath, [path.join(__dirname, '..', 'server', 'server.js')], {
  env: { ...process.env, PORT: String(PORT), DB, PAIR_SECRET: PAIR }, stdio: 'ignore'
});
process.on('exit', () => srv.kill());

waitUp().then(main).then(() => {
  console.log(`\n통과 ${pass} / 실패 ${fail}`);
  srv.kill();
  process.exit(fail ? 1 : 0);
}).catch(e => { console.error(e); srv.kill(); process.exit(1); });
