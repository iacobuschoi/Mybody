/* =============================================================================
 * tools/test-delete-page.js — 앱 없이 계정을 지우는 페이지
 *
 *   node tools/test-delete-page.js
 *
 * 구글 플레이는 계정을 만드는 앱에 **앱 밖(웹)에서도** 계정을 지울 수
 * 있는 URL 을 요구합니다. 그 URL 을 콘솔에 적어 내는데, 적어 낸 주소가
 * 실제로 안 지우면 그건 거짓 신고입니다.
 *
 * 그래서 흉내 내지 않고 끝까지 갑니다 — 진짜 서버, 진짜 브라우저,
 * 진짜 삭제. 그리고 **친구 쪽에서도 사라졌는지**까지 봅니다. 서버에
 * 올린 주간 요약은 친구 화면에 떠 있던 것이라, 계정만 지우고 그게
 * 남으면 "지웠다" 가 거짓말이 됩니다.
 * ========================================================================== */
'use strict';
/* 검사하는 사람의 ~/.mybody 설정이 결과를 바꾸지 않게 떼어 놓습니다. */
require('./testenv.js');
const { spawn } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const ROOT = path.join(__dirname, '..');
const DB = require(path.join(ROOT, 'server', 'db.js'));
const { chromium } = require('playwright');

const PORT = 8830 + Math.floor(Math.random() * 60);
const PAIR = 'test-pair-secret';
const PW = 'test-password-1';
const DBF = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'mybody-del-')), 'd.db');
const BASE = `http://localhost:${PORT}`;

let pass = 0, fail = 0;
const ok = (n, c, d) => {
  if (c) { pass++; console.log('  ✓', n); }
  else { fail++; console.log('  ✗', n, d === undefined ? '' : JSON.stringify(d)); }
};

let srv = null;
function stop() { if (srv) { try { srv.kill(); } catch (e) {} srv = null; } }
const wait = ms => new Promise(r => setTimeout(r, ms));

async function call(method, p, body, token) {
  const r = await fetch(BASE + '/api' + p, {
    method,
    headers: Object.assign({ 'Content-Type': 'application/json' },
      token ? { Authorization: 'Bearer ' + token } : {}),
    body: body ? JSON.stringify(body) : undefined
  });
  let j = null; try { j = await r.json(); } catch (e) {}
  return { status: r.status, json: j };
}

async function main() {
  /* 배포 빌드를 씁니다 — 그게 실제로 올라가는 것이고, 자리표시자가
     바뀐 것도 거기서만 확인됩니다. */
  const REL = path.join(ROOT, 'release');
  if (!fs.existsSync(path.join(REL, 'delete-account.html'))) {
    console.log('release/ 가 없습니다. 먼저: OWNER="..." OWNER_CONTACT="..." node tools/build-release.js');
    process.exit(1);
  }

  srv = spawn(process.execPath, [path.join(ROOT, 'server', 'server.js')], {
    cwd: ROOT, stdio: ['ignore', 'pipe', 'pipe'],
    env: Object.assign({}, process.env, {
      PORT: String(PORT), PAIR_SECRET: PAIR, DB: DBF, STATIC: REL, NODE_NO_WARNINGS: '1'
    })
  });
  srv.stdout.on('data', () => {}); srv.stderr.on('data', () => {});
  let up = false;
  for (let i = 0; i < 80; i++) {
    try { if ((await fetch(BASE + '/api/health')).ok) { up = true; break; } } catch (e) {}
    await wait(150);
  }
  ok('서버가 떴다', up);

  console.log('\n[1] 친구 둘 — 한 명이 지우면 다른 쪽에서도 사라져야 합니다');
  const consent = DB.HEALTH_CONSENT_VERSION;
  const mk = async (h, n) => (await call('POST', '/auth/signup',
    { handle: h, password: PW, displayName: n, pairSecret: PAIR, healthConsent: consent })).json;
  const gone = await mk('goinggone', '떠날사람');
  const stays = await mk('stayshere', '남을사람');
  ok('두 계정이 생겼다', !!(gone.token && stays.token), [gone.reason, stays.reason]);

  await call('POST', '/friends/request', { inviteCode: stays.user.inviteCode }, gone.token);
  await call('POST', '/friends/accept', { userId: gone.user.id }, stays.token);
  await call('POST', '/snapshots', { weekStart: '2026-09-14', keptDays: 3, plannedDays: 4 }, gone.token);

  /* HTTP 응답은 {ok, friends:{accepted:[...]}} 로 한 겹 더 쌓여 있습니다
     (db 계층은 평평하게 돌려줍니다). 이걸 잘못 읽으면 아래 "사라졌다"
     검사가 undefined → [] 로 **저절로** 통과합니다 — 지워지지 않아도
     초록이 뜨는 검사였습니다. */
  const accepted = r => (((r.json || {}).friends || {}).accepted) || [];
  const before = await call('GET', '/friends', null, stays.token);
  ok('친구로 보인다', accepted(before).length === 1, before.json);
  const snapBefore = await call('GET', '/snapshots/' + gone.user.id, null, stays.token);
  ok('주간 요약도 보인다', ((snapBefore.json.rows) || []).length > 0, snapBefore.json);

  console.log('\n[2] 페이지를 브라우저로 엽니다');
  const b = await chromium.launch({ executablePath:
    process.env.CHROME_PATH || '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const ctx = await b.newContext({ viewport: { width: 390, height: 844 } });
  const pg = await ctx.newPage();
  const errs = [];
  pg.on('pageerror', e => errs.push(String(e)));
  await pg.goto(BASE + '/delete-account.html', { waitUntil: 'load' });
  await wait(400);

  const body = await pg.innerText('body');
  ok('자리표시자가 안 보인다', !/__OWNER_/.test(body), (body.match(/__OWNER_\w+__/g) || []));
  /* 지워지는 것과 안 지워지는 것을 둘 다 말해야 합니다. 폰 안의 사진은
     서버로 안 가므로 여기서 못 지웁니다 — 그걸 안 적으면 사람들은
     지워졌다고 믿습니다. */
  ok('무엇이 지워지는지 적혀 있다', /친구 관계|주간 요약/.test(body), body.slice(0, 200));
  ok('안 지워지는 것도 적혀 있다', /폰에 있는 기록|사진.*남습니다/.test(body), body.slice(0, 200));

  console.log('\n[3] 남의 계정은 못 지웁니다');
  pg.on('dialog', d => d.accept());
  await pg.fill('#h', 'goinggone');
  await pg.fill('#p', 'wrong-password');
  await pg.click('#go');
  await wait(1200);
  const afterWrong = await pg.innerText('body');
  ok('비밀번호가 틀리면 거부한다', /맞지 않습니다/.test(afterWrong), afterWrong.slice(0, 300));
  const stillThere = await call('POST', '/auth/signin', { handle: 'goinggone', password: PW });
  ok('그 계정은 그대로 살아 있다', !!(stillThere.json && stillThere.json.ok), stillThere.json);

  console.log('\n[4] 본인이면 지웁니다');
  await pg.fill('#p', PW);
  await pg.click('#go');
  await wait(2000);
  const done = await pg.innerText('body');
  ok('지웠다고 말한다', /지웠습니다/.test(done), done.slice(0, 300));
  ok('폰에 남는 것도 다시 알려준다', /앱을 지우면/.test(done), done.slice(0, 300));

  console.log('\n[5] 진짜로 지워졌는가 — 서버에 물어봅니다');
  const reLogin = await call('POST', '/auth/signin', { handle: 'goinggone', password: PW });
  ok('그 아이디로 못 들어간다', !(reLogin.json && reLogin.json.ok), reLogin.json);

  const after = await call('GET', '/friends', null, stays.token);
  ok('친구 목록에서 사라졌다', accepted(after).length === 0, after.json);
  const snapAfter = await call('GET', '/snapshots/' + gone.user.id, null, stays.token);
  /* 친구 쪽 화면에 떠 있던 주간 요약이 남으면 "지웠다" 가 거짓말입니다. */
  ok('주간 요약도 사라졌다', ((snapAfter.json.rows) || []).length === 0, snapAfter.json);

  ok('JS 오류 0건', errs.length === 0, errs.slice(0, 2));
  await b.close();
}

main()
  .then(() => {
    console.log(`\n통과 ${pass} / 실패 ${fail}`);
    stop();
    process.exit(fail ? 1 : 0);
  })
  .catch(e => { console.error(e); stop(); process.exit(1); });
process.on('exit', stop);
