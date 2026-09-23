/* =============================================================================
 * test-consent.js — **건강정보 동의의 판이 올라갔을 때**
 *
 *   node tools/test-consent.js
 *
 * 2026-09-23 에 동의 문구를 고쳐 판을 올렸습니다. 예전 문구는 "주간 요약만
 * 올라간다 · 로그인 없이 써도 된다" 였는데, 기록 전체를 계정에 저장(동기화)
 * 하게 된 뒤로 둘 다 거짓이었습니다.
 *
 * 판을 올릴 때 지켜야 하는 것:
 *   1. 이미 깔린 앱(0.2.4 까지)은 옛 판을 보냅니다 — 그 앱으로도 가입은 된다.
 *   2. 그때 **받은 판 그대로** 적는다. 현재 판으로 적으면 읽지 않은 문구에
 *      동의한 것이 된다.
 *   3. 새 앱이 "다시 물어야 하나" 를 정하게 /me 가 현재 판을 알려 준다.
 *   4. 다시 받는 길(/me/consent)은 **현재 판만** 받는다.
 *   5. 동의 없는 가입은 여전히 거절한다.
 * ========================================================================== */
'use strict';
require('./testenv');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawn } = require('node:child_process');

const ROOT = path.join(__dirname, '..');
const { HEALTH_CONSENT_VERSION: CUR, ACCEPTED_CONSENT_VERSIONS } = require('../server/db.js');
const OLD = '2026-09-22';

let pass = 0, fail = 0;
const ok = (m, cond, d) => {
  if (cond) { pass++; console.log('  ✓ ' + m); }
  else { fail++; console.log('  ✗ ' + m + (d !== undefined ? '\n      ' + JSON.stringify(d) : '')); }
};

const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'mybody-consent-'));
const DB = path.join(dir, 'test.db');
const PORT = 8900 + Math.floor(Math.random() * 90);
const PAIR = 'consent-pair';
const PW = 'pw-that-is-long-enough';
const B = `http://localhost:${PORT}/api`;

const srv = spawn(process.execPath, [path.join(ROOT, 'server', 'server.js')], {
  cwd: ROOT, stdio: ['ignore', 'pipe', 'pipe'],
  env: Object.assign({}, process.env, {
    PORT: String(PORT), PAIR_SECRET: PAIR, DB,
    STATIC: path.join(ROOT, 'prototype'), NODE_NO_WARNINGS: '1'
  })
});
srv.stdout.on('data', () => {});
srv.stderr.on('data', () => {});

async function call(method, p, body, token) {
  const r = await fetch(B + p, {
    method,
    headers: Object.assign({ 'Content-Type': 'application/json' },
      token ? { Authorization: 'Bearer ' + token } : {}),
    body: body ? JSON.stringify(body) : undefined
  });
  let j = null; try { j = await r.json(); } catch (e) {}
  return { status: r.status, json: j || {} };
}

async function main() {
  let up = false;
  for (let i = 0; i < 60 && !up; i++) {
    try { up = (await fetch(B + '/health')).ok; } catch (e) {}
    if (!up) await new Promise(r => setTimeout(r, 150));
  }
  ok('서버가 떴다', up);

  console.log('\n[판]');
  ok('현재 판이 옛 판과 다르다 (문구를 고쳤으면 판도 올린다)', CUR !== OLD, CUR);
  ok('가입은 현재 판과 옛 판을 받는다', ACCEPTED_CONSENT_VERSIONS.includes(CUR) &&
     ACCEPTED_CONSENT_VERSIONS.includes(OLD), ACCEPTED_CONSENT_VERSIONS);
  const same = (f) => fs.readFileSync(path.join(ROOT, f), 'utf8').includes(`'${CUR}'`);
  ok('웹 앱(sync.js)이 같은 판을 들고 있다', same('prototype/js/sync.js'));
  ok('앱(account.dart)이 같은 판을 들고 있다', same('app/lib/src/screens/account.dart'));

  const signUp = (handle, healthConsent) => call('POST', '/auth/signup', {
    handle, password: PW, displayName: handle, pairSecret: PAIR, healthConsent });

  console.log('\n[1] 이미 깔린 앱(옛 판)으로 가입');
  const a = await signUp('oldapp', OLD);
  ok('가입된다', a.status === 200 && !!a.json.token, a.json);
  ok('받은 판(옛 판) 그대로 적힌다', a.json.user && a.json.user.healthConsentVersion === OLD,
     a.json.user);
  ok('/me 가 서버의 현재 판을 알려 준다', a.json.user && a.json.user.healthConsentCurrent === CUR,
     a.json.user);

  console.log('\n[2] 다시 받기');
  const bad = await call('POST', '/me/consent', { healthConsent: OLD }, a.json.token);
  ok('옛 판으로는 다시 받지 않는다 (400)', bad.status === 400, bad);
  const none = await call('POST', '/me/consent', {}, a.json.token);
  ok('판 없이도 안 받는다', none.status === 400, none);
  const noAuth = await call('POST', '/me/consent', { healthConsent: CUR });
  ok('로그인 없이는 안 된다 (401)', noAuth.status === 401, noAuth);
  const good = await call('POST', '/me/consent', { healthConsent: CUR }, a.json.token);
  ok('현재 판이면 받는다', good.status === 200 && good.json.ok, good);
  const me = await call('GET', '/me', null, a.json.token);
  ok('다시 받은 뒤 /me 의 판이 현재 판이다',
     me.json.user && me.json.user.healthConsentVersion === CUR, me.json.user);
  ok('동의 시각이 있다', me.json.user && !!me.json.user.healthConsentAt, me.json.user);

  console.log('\n[3] 새 앱으로 가입');
  const b = await signUp('newapp', CUR);
  ok('현재 판으로 가입되고 그대로 적힌다',
     b.status === 200 && b.json.user && b.json.user.healthConsentVersion === CUR, b.json);

  console.log('\n[4] 동의 없는 가입');
  for (const v of [null, true, 'yes', '2026-01-01']) {
    const r = await signUp('nope' + String(v).replace(/\W/g, '').slice(0, 8), v);
    ok(`healthConsent=${JSON.stringify(v)} → 거절`, r.status >= 400 && !r.json.token, r.json);
  }
}

main()
  .catch(e => { fail++; console.error(e); })
  .finally(() => {
    try { srv.kill(); } catch (e) {}
    try { fs.rmSync(dir, { recursive: true, force: true }); } catch (e) {}
    console.log(`\n${pass} 통과 · ${fail} 실패`);
    process.exit(fail ? 1 : 0);
  });
