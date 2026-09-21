/* =============================================================================
 * tools/test-friendpush.js — 친구 요청이 오면 알림이 가는가
 *
 *   node tools/test-friendpush.js
 *
 * 진짜 서버를 띄우고, 진짜 VAPID 열쇠로 서명하고, 가짜 푸시 서비스를
 * 하나 세워서 **실제로 날아온 암호문을 풀어** 무슨 말이 들어 있는지 봅니다.
 * 중간을 흉내 내면 "보냈다고 생각했는데 안 갔다" 를 못 잡습니다.
 *
 * 여기서 제일 중요한 것은 문구가 아니라 **누구에게 갔는가** 입니다.
 * 알림은 공유 설정을 우회하는 뒷문이 되기 쉽습니다 — 엉뚱한 사람에게
 * 가면 그건 기능이 아니라 유출입니다.
 * ========================================================================== */
'use strict';
const { spawn, spawnSync } = require('node:child_process');
const https = require('node:https');
const crypto = require('node:crypto');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const ROOT = path.join(__dirname, '..');
const PUSH = require(path.join(ROOT, 'server', 'push.js'));

const PORT = 8760 + Math.floor(Math.random() * 120);
const HOOK = PORT + 1;
const PAIR = 'test-pair-secret';
const PW = 'test-password-1';
const DB = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'mybody-fp-')), 'test.db');
const B = `http://localhost:${PORT}/api`;

let pass = 0, fail = 0;
const ok = (n, c, d) => {
  if (c) { pass++; console.log('  ✓', n); }
  else { fail++; console.log('  ✗', n, d === undefined ? '' : JSON.stringify(d)); }
};

/* --- 가짜 푸시 서비스 -----------------------------------------------------
 *
 * **https 여야 합니다.** 서버가 구독 endpoint 에 https 를 강제하는데,
 * 그건 까다로움이 아니라 SSRF 방어입니다 — http 를 허용하면 아무나
 * `http://127.0.0.1:<내부포트>/...` 를 구독으로 등록해서 서버가 자기
 * 안쪽으로 POST 를 쏘게 만들 수 있습니다. 시험 편하자고 그 규칙을
 * 풀면 안 되므로, 시험 쪽이 인증서를 만들어 씁니다.
 * -------------------------------------------------------------------------- */
const CERT = (() => {
  const d = fs.mkdtempSync(path.join(os.tmpdir(), 'mybody-cert-'));
  const key = path.join(d, 'k.pem'), crt = path.join(d, 'c.pem');
  spawnSync('openssl', ['req', '-x509', '-newkey', 'rsa:2048', '-nodes',
    '-keyout', key, '-out', crt, '-days', '1', '-subj', '/CN=localhost',
    '-addext', 'subjectAltName=IP:127.0.0.1,DNS:localhost'], { encoding: 'utf8' });
  return { key: fs.readFileSync(key), cert: fs.readFileSync(crt), dir: d };
})();

const got = [];      // { path, body }
const hook = https.createServer({ key: CERT.key, cert: CERT.cert }, (req, res) => {
  const chunks = [];
  req.on('data', c => chunks.push(c));
  req.on('end', () => {
    got.push({ path: req.url, body: Buffer.concat(chunks) });
    res.writeHead(201); res.end();
  });
});

/* --- 구독자 열쇠 한 벌 (브라우저가 만드는 것과 같은 모양) ----------------- */
function newSubscriber(tag) {
  const ecdh = crypto.createECDH('prime256v1');
  ecdh.generateKeys();
  return {
    tag,
    priv: ecdh.getPrivateKey(),
    endpoint: `https://127.0.0.1:${HOOK}/sub/${tag}`,
    p256dh: PUSH.b64u(ecdh.getPublicKey()),
    auth: PUSH.b64u(crypto.randomBytes(16))
  };
}

let srv = null;
function boot(env) {
  const p = spawn(process.execPath, [path.join(ROOT, 'server', 'server.js')], {
    cwd: ROOT, stdio: ['ignore', 'pipe', 'pipe'],
    env: Object.assign({}, process.env, {
      PORT: String(PORT), PAIR_SECRET: PAIR, DB,
      STATIC: path.join(ROOT, 'prototype'), NODE_NO_WARNINGS: '1',
      /* 스스로 서명한 인증서를 쓰는 가짜 푸시 서비스라 검증을 끕니다.
         **시험용 자식 프로세스에만** 겁니다 — 제품 코드는 안 건드립니다. */
      NODE_TLS_REJECT_UNAUTHORIZED: '0'
    }, env)
  });
  p.stdout.on('data', () => {});
  p.stderr.on('data', () => {});
  return p;
}
function stop() { if (srv) { try { srv.kill(); } catch (e) {} srv = null; } }

async function waitUp() {
  for (let i = 0; i < 80; i++) {
    try { if ((await fetch(`http://localhost:${PORT}/api/health`)).ok) return true; } catch (e) {}
    await new Promise(r => setTimeout(r, 150));
  }
  return false;
}
async function call(method, p, body, token) {
  const r = await fetch(B + p, {
    method,
    headers: Object.assign({ 'Content-Type': 'application/json' },
      token ? { Authorization: 'Bearer ' + token } : {}),
    body: body ? JSON.stringify(body) : undefined
  });
  let j = null; try { j = await r.json(); } catch (e) {}
  return { status: r.status, json: j };
}
const wait = ms => new Promise(r => setTimeout(r, ms));

async function main() {
  const vapid = PUSH.generateVapid();
  srv = boot({ VAPID_PUBLIC: vapid.publicKey, VAPID_PRIVATE: vapid.privateKey });
  ok('서버가 떴다', await waitUp());

  console.log('\n[1] 세 사람 — 보내는 사람 · 받는 사람 · 상관없는 사람');
  const mk = async (handle, name) => {
    const r = await call('POST', '/auth/signup', {
      handle, password: PW, displayName: name, pairSecret: PAIR,
      healthConsent: require(path.join(ROOT, 'server', 'db.js')).HEALTH_CONSENT_VERSION
    });
    return r.json;
  };
  const sender = await mk('chulsoo', '철수');
  const target = await mk('younghee', '영희');
  const other = await mk('minsu', '민수');
  ok('세 계정이 생겼다', !!(sender.token && target.token && other.token),
     [sender.reason, target.reason, other.reason]);

  console.log('\n[2] 받는 사람과 상관없는 사람이 알림을 켠다');
  const subT = newSubscriber('target');
  const subO = newSubscriber('other');
  const subS = newSubscriber('sender');
  for (const [s, tok] of [[subT, target.token], [subO, other.token], [subS, sender.token]]) {
    const r = await call('POST', '/push/subscribe',
      { endpoint: s.endpoint, p256dh: s.p256dh, auth: s.auth }, tok);
    ok(s.tag + ' 구독됨', r.json && r.json.ok, r.json);
  }

  console.log('\n[3] 친구 요청을 보낸다');
  got.length = 0;
  const req = await call('POST', '/friends/request',
    { inviteCode: target.user.inviteCode }, sender.token);
  ok('요청이 받아들여진다', req.json && req.json.ok && req.json.status === 'pending', req.json);
  await wait(600);   // 알림은 응답을 안 기다립니다 — 조금 줍니다

  ok('알림이 딱 한 통 갔다', got.length === 1, got.map(g => g.path));
  ok('받는 사람에게 갔다', got.length === 1 && /\/sub\/target$/.test(got[0].path),
     got.map(g => g.path));
  /* 이게 핵심입니다. 상관없는 사람에게 가면 그건 기능이 아니라 유출입니다.
     보낸 사람에게 가면 자기가 보낸 요청을 알림으로 되돌려받는 꼴입니다. */
  ok('상관없는 사람에게는 안 갔다', !got.some(g => /\/sub\/other$/.test(g.path)),
     got.map(g => g.path));
  ok('보낸 사람에게도 안 갔다', !got.some(g => /\/sub\/sender$/.test(g.path)),
     got.map(g => g.path));

  console.log('\n[4] 무슨 말이 들어 있나 — 실제로 풀어 봅니다');
  if (got.length === 1) {
    let msg = null;
    try { msg = JSON.parse(PUSH.decrypt(got[0].body, subT.priv, subT.auth).toString('utf8')); }
    catch (e) { msg = { _err: String(e && e.message || e) }; }
    ok('암호문이 풀린다', msg && !msg._err, msg);
    ok('보낸 사람 이름이 들어 있다', !!(msg && /철수/.test(msg.t)), msg && msg.t);
    ok('친구 요청이라고 말한다', !!(msg && /친구 요청/.test(msg.t)), msg && msg.t);
    /* 기본 공유가 무엇인지 여기서 한 번 더 말해 줍니다 — 수락 버튼을
       누르기 전에 무엇이 보이게 되는지 알아야 합니다. */
    ok('몸 숫자는 기본 비공개라고 알려준다', !!(msg && /몸 숫자는 기본 비공개/.test(msg.b)),
       msg && msg.b);
    ok('친구 화면으로 보낸다', !!(msg && msg.u === '/#P15'), msg && msg.u);
  } else {
    ok('암호문이 풀린다', false, '알림이 안 와서 확인 못 함');
  }

  console.log('\n[5] 같은 요청을 또 보내도 알림이 또 울리지 않는다');
  got.length = 0;
  const again = await call('POST', '/friends/request',
    { inviteCode: target.user.inviteCode }, sender.token);
  await wait(500);
  ok('두 번째 요청은 거절된다', again.json && !again.json.ok, again.json);
  /* 버튼을 연타하면 상대 폰이 계속 울리는 길이 있으면 안 됩니다. */
  ok('알림이 다시 가지 않는다', got.length === 0, got.map(g => g.path));

  console.log('\n[6] 상대가 맞요청하면 "친구가 되었습니다" 가 간다');
  got.length = 0;
  const back = await call('POST', '/friends/request',
    { inviteCode: sender.user.inviteCode }, target.token);
  ok('맞요청은 곧 수락이다', back.json && back.json.ok && back.json.status === 'accepted', back.json);
  await wait(600);
  ok('이번엔 처음 보낸 사람에게 간다', got.length === 1 && /\/sub\/sender$/.test(got[0].path),
     got.map(g => g.path));
  if (got.length === 1) {
    let msg = null;
    try { msg = JSON.parse(PUSH.decrypt(got[0].body, subS.priv, subS.auth).toString('utf8')); }
    catch (e) { msg = null; }
    ok('친구가 되었다고 말한다', !!(msg && /친구가 되었습니다/.test(msg.t)), msg && msg.t);
  }

  console.log('\n[6-2] 보통 흐름 — A 가 요청하고 B 가 수락 버튼을 누른다');
  {
    /* 여기가 실제로 제일 흔한 길입니다. 앞의 [6] 은 서로 요청한 경우고,
       보통은 한쪽이 요청하고 다른 쪽이 앱에서 수락을 누릅니다.
       이 길에 알림이 없으면 보낸 사람은 계속 기다립니다. */
    const a = await mk('dongsu', '동수');
    const bb = await mk('sujin', '수진');
    const subA = newSubscriber('dongsu');
    const subB = newSubscriber('sujin');
    for (const [sb, tok] of [[subA, a.token], [subB, bb.token]]) {
      await call('POST', '/push/subscribe',
        { endpoint: sb.endpoint, p256dh: sb.p256dh, auth: sb.auth }, tok);
    }
    got.length = 0;
    await call('POST', '/friends/request', { inviteCode: bb.user.inviteCode }, a.token);
    await wait(500);
    ok('요청 알림은 수진에게', got.length === 1 && /\/sub\/sujin$/.test(got[0].path),
       got.map(g => g.path));

    got.length = 0;
    const acc = await call('POST', '/friends/accept', { userId: a.user.id }, bb.token);
    ok('수락된다', acc.json && acc.json.ok, acc.json);
    await wait(600);
    ok('수락 알림이 동수에게 간다', got.length === 1 && /\/sub\/dongsu$/.test(got[0].path),
       got.map(g => g.path));
    ok('수락한 본인에게는 안 간다', !got.some(g => /\/sub\/sujin$/.test(g.path)),
       got.map(g => g.path));
    if (got.length === 1) {
      let msg = null;
      try { msg = JSON.parse(PUSH.decrypt(got[0].body, subA.priv, subA.auth).toString('utf8')); }
      catch (e) { msg = null; }
      ok('수락한 사람 이름이 들어 있다', !!(msg && /수진/.test(msg.t)), msg && msg.t);
      ok('수락했다고 말한다', !!(msg && /수락했습니다/.test(msg.t)), msg && msg.t);
    }

    /* 이미 친구인데 또 누르면 — 연타로 울리는 길이 없어야 합니다. */
    got.length = 0;
    const twice = await call('POST', '/friends/accept', { userId: a.user.id }, bb.token);
    await wait(400);
    ok('이미 친구면 수락이 안 된다', twice.json && !twice.json.ok, twice.json);
    ok('알림도 다시 안 간다', got.length === 0, got.map(g => g.path));
  }

  console.log('\n[7] 알림 열쇠가 없는 서버는 조용히 넘어간다');
  stop();
  await wait(300);
  srv = boot({});                       // VAPID 없이
  ok('그래도 서버가 뜬다', await waitUp());
  const s2 = await call('POST', '/auth/signin', { handle: 'minsu', password: PW });
  const t2 = await call('POST', '/auth/signin', { handle: 'chulsoo', password: PW });
  got.length = 0;
  const r3 = await call('POST', '/friends/request',
    { inviteCode: other.user.inviteCode }, t2.json.token);
  await wait(400);
  /* 알림이 안 되는 서버에서 친구 요청까지 막히면 안 됩니다 —
     알림은 곁다리고, 친구 맺기가 본체입니다. */
  ok('친구 요청은 그대로 된다', r3.json && r3.json.ok, r3.json);
  ok('알림은 안 간다', got.length === 0, got.length);
}

hook.listen(HOOK, '127.0.0.1', () => {
  main()
    .then(() => {
      console.log(`\n통과 ${pass} / 실패 ${fail}`);
      stop(); hook.close();
      try { fs.rmSync(CERT.dir, { recursive: true, force: true }); } catch (e) {}
      process.exit(fail ? 1 : 0);
    })
    .catch(e => { console.error(e); stop(); hook.close(); process.exit(1); });
});
process.on('exit', () => { stop(); });
