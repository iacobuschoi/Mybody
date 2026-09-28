/* =============================================================================
 * tools/test-feedback-inbox.js — 운영자의 앱 안 「의견함」 (GET /api/feedback/inbox …)
 *
 *   node tools/test-feedback-inbox.js
 *
 * 왜 이 시험이 있나
 *   의견은 로그인 없이도 받고, 붙인 화면 캡처에는 몸 숫자가 찍혀 있을 수 있습니다.
 *   "노트북 앞에 앉은 사람만 본다" 던 것을 "운영자 계정의 앱에서도 본다" 로 넓혔으니,
 *   넓힌 문이 **운영자 한 사람에게만** 열리는지를 길마다 HTTP 로 두드려 봅니다.
 *   운영자 = 설정의 feedbackNotify(FEEDBACK_NOTIFY) 아이디의 계정. 비었으면 아무도 아님.
 *
 * 보는 것
 *   [1] DB — 새것부터 · 번호로 넘기기 · 안 읽은 수 · 보낸 사람 이름/익명 · 사진 한 장 ·
 *       전부 읽음(upTo) · 지우기(사진까지 한 트랜잭션)
 *   [2] 진짜 서버 + 가짜 FCM(https)
 *       · 새 의견 알림: route 'feedback' · 「새 의견이 왔어요 · 눌러서 보기」 · 내용 없음 · 운영자에게만
 *       · /api/me 의 isOperator — 운영자 본인에게만 true, 다른 사람은 칸 자체가 없음 · 친구에게 안 샘
 *       · 로그인 없음 · 틀린 토큰 → 모든 길 401 / 운영자 아님 → 모든 길(사진 포함) 403
 *       · 목록 순서 · 쪽 넘기기 · limit 범위 · 틀린 before 400 · 캐시 금지
 *       · 사진 바이트 · Content-Type · no-store · 없는 사진 404 · 틀린 번호 400 · 모르는 형식은 octet-stream
 *       · 읽음 · 전부 읽음 · 지우기(사진도) · 노트북 도구(tools/feedback.js)가 지워진 것의 꺼낸 캡처를 지움
 *       · 로그에 의견 내용이 안 남음
 *   [3] FEEDBACK_NOTIFY 가 비었거나 없는 아이디 → 아무도 운영자가 아님 · 뜰 때 알림
 *
 * 진짜 구글을 부르지 않습니다. 가짜 OAuth · FCM 을 https 로 세웁니다(test-feedback.js 와 같은 방법).
 * ========================================================================== */
'use strict';
/* 검사하는 사람의 ~/.mybody 설정(진짜 서비스 계정 · 의견 알림 아이디)이 결과를 바꾸지 않게. */
const TESTENV = require('./testenv.js');
const { spawn, spawnSync } = require('node:child_process');
const https = require('node:https');
const crypto = require('node:crypto');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { DatabaseSync } = require('node:sqlite');

const ROOT = path.join(__dirname, '..');
const FB = require(path.join(ROOT, 'server', 'feedback.js'));
const DBM = require(path.join(ROOT, 'server', 'db.js'));

let pass = 0, fail = 0;
const ok = (n, c, d) => {
  if (c) { pass++; console.log('  ✓', n); }
  else { fail++; console.log('  ✗', n, d === undefined ? '' : JSON.stringify(d).slice(0, 400)); }
};
const wait = ms => new Promise(r => setTimeout(r, ms));
const TMP = fs.mkdtempSync(path.join(os.tmpdir(), 'mybody-inbox-'));
const PW = 'test-password-1';

/* 앞머리만 맞춘 가짜 사진. 서버는 앞머리 · 크기 · base64 모양만 봅니다. */
const PNG_HEAD = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
const JPG_HEAD = Buffer.from([0xff, 0xd8, 0xff, 0xe0]);
const png = (n = 64) => Buffer.concat([PNG_HEAD, crypto.randomBytes(Math.max(0, n - PNG_HEAD.length))]);
const jpg = (n = 64) => Buffer.concat([JPG_HEAD, crypto.randomBytes(Math.max(0, n - JPG_HEAD.length))]);
const img = (type, buf) => ({ type, data: buf.toString('base64') });

/* --- [1] DB ---------------------------------------------------------------- */
function dbUnit() {
  console.log('\n[1] DB — 의견함 목록 · 사진 · 읽음 · 지우기');
  const file = path.join(TMP, 'unit.db');
  const api = DBM.makeApi(DBM.open(file));
  const a = api.signUp({ handle: 'inboxdb1', password: PW, displayName: '가나다', healthConsent: DBM.HEALTH_CONSENT_VERSION });
  const p1 = png(120), j1 = jpg(90);
  const id1 = api.addFeedback(a.user.id, FB.parseFeedback({ text: '첫 의견', appVersion: '0.2.18+320',
                                                            platform: 'ios', screen: '설정' }).value);
  const id2 = api.addFeedback(null, FB.parseFeedback({ images: [img('image/png', p1), img('image/jpeg', j1)] }).value);
  const id3 = api.addFeedback(a.user.id, FB.parseFeedback({ text: '셋째' }).value);
  /* 서버를 거치지 않고 들어간 행 — 글자 방향 뒤집기 · ESC 가 그대로 들어 있습니다. */
  const raw = new DatabaseSync(file);
  const id4 = Number(raw.prepare('INSERT INTO feedback (created_at, text, screen) VALUES (?,?,?)')
    .run(new Date().toISOString(), '보이는\u202e글\x1b[31m', '홈\u2066').lastInsertRowid);
  raw.close();

  const all = api.feedbackInbox();
  ok('새것부터 (번호 내림차순)', JSON.stringify(all.items.map(x => x.id)) === JSON.stringify([id4, id3, id2, id1]),
     all.items.map(x => x.id));
  ok('안 읽은 수 = 4 · 다음 쪽 없음', all.unread === 4 && all.nextBefore === null, [all.unread, all.nextBefore]);
  const i1 = all.items.find(x => x.id === id1), i2 = all.items.find(x => x.id === id2);
  ok('칸: 판 · 기종 · 화면 · 시각 · 글 · 읽음', i1.appVersion === '0.2.18+320' && i1.platform === 'ios' &&
     i1.screen === '설정' && /^\d{4}-\d{2}-\d{2}T/.test(i1.createdAt) && i1.text === '첫 의견' && i1.read === false, i1);
  ok('로그인해서 보냈으면 from = {name: 표시 이름} 만 (아이디 · 내부 id 없음)',
     JSON.stringify(i1.from) === JSON.stringify({ name: '가나다' }) && !JSON.stringify(all).includes('inboxdb1') &&
     !JSON.stringify(all).includes(a.user.id), i1.from);
  ok('익명이면 from = null · 글 없으면 text = \'\' · 없는 메타는 null', i2.from === null && i2.text === '' &&
     i2.appVersion === null && i2.platform === null && i2.screen === null, i2);
  ok('사진은 번호 · 형식만 (바이트는 목록에 안 실림)',
     JSON.stringify(i2.images) === JSON.stringify([{ n: 1, type: 'image/png' }, { n: 2, type: 'image/jpeg' }]) &&
     i1.images.length === 0, i2.images);
  const i4 = all.items.find(x => x.id === id4);
  ok('손으로 넣은 행의 제어 문자 · 방향 뒤집기 문자는 내보낼 때 거른다',
     i4.text === '보이는글[31m' && i4.screen === '홈', [i4.text, i4.screen]);
  /* 표시 이름은 가입 · 이름 바꾸기에서 길이만 자르고 저장됩니다 — 방향 뒤집기 문자로 "누가
     보냈나" 를 다르게 보이게 하거나 줄바꿈으로 칸을 늘리지 못하게, 나갈 때 거릅니다. */
  const bidi = api.signUp({ handle: 'inboxdb2', password: PW, displayName: '가‮나\n다\x1b',
                            healthConsent: DBM.HEALTH_CONSENT_VERSION });
  const id5 = api.addFeedback(bidi.user.id, FB.parseFeedback({ text: '이름 거르기' }).value);
  const i5 = api.feedbackInbox().items.find(x => x.id === id5) || {};
  ok('보낸 사람 이름의 제어 · 방향 뒤집기 문자도 거르고 한 줄로', JSON.stringify(i5.from) === JSON.stringify({ name: '가나 다' }),
     i5.from);
  api.deleteFeedback(id5);

  const pg1 = api.feedbackInbox({ limit: 2 });
  const pg2 = api.feedbackInbox({ limit: 2, before: pg1.nextBefore });
  ok('쪽 넘기기: 2개씩 → [4,3] 다음 [2,1] · 마지막 쪽은 nextBefore null',
     JSON.stringify(pg1.items.map(x => x.id)) === JSON.stringify([id4, id3]) && pg1.nextBefore === id3 &&
     JSON.stringify(pg2.items.map(x => x.id)) === JSON.stringify([id2, id1]) && pg2.nextBefore === null, [pg1, pg2]);
  ok('limit 은 1~50 으로 자름 (0 → 1개 · 999 → 50 까지라 지금은 4개 전부 · 글자 → 기본 30)',
     api.feedbackInbox({ limit: 0 }).items.length === 1 && api.feedbackInbox({ limit: 999 }).items.length === 4 &&
     api.feedbackInbox({ limit: 'x' }).items.length === 4, api.feedbackInbox({ limit: 0 }).items.length);

  const im = api.feedbackImage(id2, 2);
  ok('사진 한 장: 형식 · 바이트 그대로', im && im.type === 'image/jpeg' && Buffer.isBuffer(im.data) && im.data.equals(j1));
  ok('없는 사진 → null', api.feedbackImage(id2, 3) === null && api.feedbackImage(id1, 1) === null &&
     api.feedbackImage(999999, 1) === null);

  ok('전부 읽음 upTo=id2 → id1 · id2 만 (2개)', api.markAllFeedbackRead(id2) === 2 && api.feedbackInbox().unread === 2);
  ok('전부 읽음 (upTo 없음) → 나머지 2개 · 안 읽은 수 0', api.markAllFeedbackRead() === 2 && api.feedbackInbox().unread === 0);
  ok('읽음이 목록에 read:true 로', api.feedbackInbox().items.every(x => x.read === true));

  ok('지우기 → true · 없는 번호 → false', api.deleteFeedback(id2) === true && api.deleteFeedback(id2) === false);
  const r = new DatabaseSync(file, { readOnly: true });
  ok('지운 의견의 행 · 사진이 안 남는다', r.prepare('SELECT COUNT(*) c FROM feedback WHERE id=?').get(id2).c === 0 &&
     r.prepare('SELECT COUNT(*) c FROM feedback_images WHERE feedback_id=?').get(id2).c === 0);
  r.close();
  ok('다른 의견은 그대로 · 지운 번호는 feedbackIds 에서 빠짐', api.feedbackInbox().items.length === 3 &&
     !api.feedbackIds().includes(id2) && api.feedbackIds().includes(id1));
}

/* --- 가짜 OAuth · FCM (https) --------------------------------------------- */
const PORT = 10200 + Math.floor(Math.random() * 300);
const HOOK = PORT + 400 + Math.floor(Math.random() * 50);
const PAIR = 'inbox-pair-secret';
const DB = path.join(TMP, 'srv.db');
const B = `http://127.0.0.1:${PORT}/api`;
const RSA = crypto.generateKeyPairSync('rsa', { modulusLength: 2048 });
const SA = {
  type: 'service_account', project_id: 'mybody-test', private_key_id: 'kid-1',
  private_key: RSA.privateKey.export({ type: 'pkcs8', format: 'pem' }),
  client_email: 'push@mybody-test.iam.gserviceaccount.com', token_uri: `https://127.0.0.1:${HOOK}/token`
};
const CERT = (() => {
  const d = fs.mkdtempSync(path.join(os.tmpdir(), 'mybody-inboxcert-'));
  const key = path.join(d, 'k.pem'), crt = path.join(d, 'c.pem');
  spawnSync('openssl', ['req', '-x509', '-newkey', 'rsa:2048', '-nodes',
    '-keyout', key, '-out', crt, '-days', '1', '-subj', '/CN=localhost',
    '-addext', 'subjectAltName=IP:127.0.0.1,DNS:localhost'], { encoding: 'utf8' });
  return { key: fs.readFileSync(key), cert: fs.readFileSync(crt), dir: d };
})();
const fcmGot = [];
const hook = https.createServer({ key: CERT.key, cert: CERT.cert }, (req, res) => {
  const chunks = [];
  req.on('data', c => chunks.push(c));
  req.on('end', () => {
    const raw = Buffer.concat(chunks).toString('utf8');
    const reply = (st, obj) => { res.writeHead(st, { 'content-type': 'application/json' }); res.end(JSON.stringify(obj || {})); };
    if (req.url === '/token') return reply(200, { access_token: 't1', expires_in: 3599, token_type: 'Bearer' });
    if (req.url === '/v1/projects/mybody-test/messages:send') {
      let m = null; try { m = JSON.parse(raw).message; } catch (e) {}
      fcmGot.push({ m, raw });
      return reply(200, { name: 'projects/mybody-test/messages/' + fcmGot.length });
    }
    reply(404, {});
  });
});

let srv = null, out = '';
function boot(env) {
  out = '';
  const p = spawn(process.execPath, [path.join(ROOT, 'server', 'server.js')], {
    cwd: ROOT, stdio: ['ignore', 'pipe', 'pipe'],
    env: Object.assign({}, process.env, {
      PORT: String(PORT), PAIR_SECRET: PAIR, DB, AUTH_MAX: '100000',
      STATIC: path.join(ROOT, 'prototype'), NODE_NO_WARNINGS: '1',
      FCM_BASE_URL: `https://127.0.0.1:${HOOK}`,
      /* 스스로 서명한 인증서의 가짜 서버라 검증을 끕니다 — 시험용 자식 프로세스에만. */
      NODE_TLS_REJECT_UNAUTHORIZED: '0'
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
/* 응답을 통째로 — 상태 · 머리 · 바이트 · (JSON 이면) 본문. */
async function call(method, p, body, token) {
  const r = await fetch(B + p, {
    method,
    headers: Object.assign({ 'Content-Type': 'application/json' }, token ? { Authorization: 'Bearer ' + token } : {}),
    body: body !== undefined && body !== null ? JSON.stringify(body) : undefined
  });
  const buf = Buffer.from(await r.arrayBuffer());
  let j = null; try { j = JSON.parse(buf.toString('utf8')); } catch (e) {}
  return { status: r.status, json: j || {}, buf, text: buf.toString('utf8'), h: r.headers };
}
function dbRows(sql, ...args) {
  const d = new DatabaseSync(DB, { readOnly: true });
  try { return d.prepare(sql).all(...args); } finally { d.close(); }
}
async function until(fn, ms = 3000) {
  const t0 = Date.now();
  while (Date.now() - t0 < ms) { if (fn()) return true; await wait(50); }
  return fn();
}
const feedbackPushes = () => fcmGot.filter(x => x.m && x.m.data && x.m.data.kind === 'feedback');
const is403 = r => r.status === 403 && r.json.ok === false && r.json.error === '운영자만 볼 수 있어요' &&
  !/owner|주인/i.test(r.text);
const is401 = r => r.status === 401 && r.json.ok === false;
const noStore = r => r.h.get('cache-control') === 'private, no-store';

async function integration() {
  /* 서비스 계정 파일은 기본 자리에 둡니다. 운영자 아이디는 **대문자로** 적습니다 — 로그인이
     아이디를 소문자로 맞추듯 운영자도 같은 규칙으로 찾아야 합니다. */
  const home = path.join(TESTENV.home, '.mybody');
  fs.mkdirSync(home, { recursive: true });
  fs.writeFileSync(path.join(home, 'fcm-service-account.json'), JSON.stringify(SA));

  console.log('\n[2] 진짜 서버 — 운영자(FEEDBACK_NOTIFY=" Owner ")');
  srv = boot({ FEEDBACK_NOTIFY: ' Owner ' });
  ok('서버가 뜬다', await waitUp(), out.slice(-400));
  const mk = async (handle, name) => (await call('POST', '/auth/signup', {
    handle, password: PW, displayName: name, pairSecret: PAIR, healthConsent: DBM.HEALTH_CONSENT_VERSION })).json;
  /* 서버가 뜬 **뒤에** 운영자 계정이 생깁니다 — 운영자를 뜰 때 한 번만 찾아 기억해 두면
     아래가 전부 403 입니다(요청마다 다시 찾는지). */
  const O = await mk('owner', '주인'), T = await mk('tester1', '시험자'), X = await mk('other1', '다른이');
  ok('계정 셋', !!(O.token && T.token && X.token));
  const ownerTok = 'ok_owner_' + crypto.randomBytes(24).toString('hex');
  const testerTok = 'ok_tester_' + crypto.randomBytes(24).toString('hex');
  ok('운영자 · 시험자 폰(앱 알림) 등록',
     (await call('POST', '/push/device', { token: ownerTok, platform: 'android', permission: 'granted' }, O.token)).status === 200 &&
     (await call('POST', '/push/device', { token: testerTok, platform: 'ios', permission: 'granted' }, T.token)).status === 200);

  /* --- /api/me 의 isOperator ------------------------------------------------ */
  const meO = await call('GET', '/me', null, O.token), meT = await call('GET', '/me', null, T.token);
  ok('/api/me: 운영자 본인에게 user.isOperator === true', meO.status === 200 && meO.json.user.isOperator === true, meO.json.user);
  ok('/api/me: 다른 사람에게는 칸 자체가 없다', meT.status === 200 && !('isOperator' in meT.json.user) &&
     !/isOperator|operator/i.test(meT.text), meT.json.user);
  const patO = await call('PATCH', '/me', { displayName: '주인' }, O.token);
  const patT = await call('PATCH', '/me', { displayName: '시험자' }, T.token);
  ok('PATCH /me 의 답도 같다 (운영자 true · 다른 사람 없음)', patO.json.user && patO.json.user.isOperator === true &&
     patT.json.user && !('isOperator' in patT.json.user), [patO.json.user, patT.json.user]);
  /* 운영자와 친구가 되어도 운영자라는 것이 친구 쪽 응답에 새지 않는다. */
  const fr = await call('POST', '/friends/request', { inviteCode: meO.json.user.inviteCode }, T.token);
  const acc = await call('POST', '/friends/accept', { userId: T.user.id }, O.token);
  const flist = await call('GET', '/friends', null, T.token);
  ok('친구의 친구 목록에 운영자 표시가 안 샌다', fr.status === 200 && acc.status === 200 && flist.status === 200 &&
     flist.text.includes(O.user.id) && !/isOperator|operator/i.test(flist.text), flist.text.slice(0, 300));

  /* --- 의견 넣기 + 새 의견 알림 --------------------------------------------- */
  const MARK = '비밀스러운-의견-' + crypto.randomBytes(4).toString('hex');
  const send = (body, token) => call('POST', '/feedback', body, token);
  const f1 = (await send({ text: MARK + ' 첫 의견', appVersion: '0.2.18+320', platform: 'android', screen: '홈' }, T.token)).json.id;
  ok('운영자 폰으로 알림이 한 번', await until(() => feedbackPushes().length === 1), fcmGot.length);
  const note = (feedbackPushes()[0] || {}).m || {};
  const rawNote = (feedbackPushes()[0] || {}).raw || '';
  ok('알림: route feedback (누르면 의견함) · tag feedback', note.data && note.data.route === 'feedback' &&
     note.data.kind === 'feedback' && note.android && note.android.notification.tag === 'feedback', note.data);
  ok('알림 문구: 새 의견이 왔어요 · 눌러서 보기', note.notification && note.notification.title === '새 의견이 왔어요' &&
     note.notification.body === '눌러서 보기', note.notification);
  ok('알림에 의견 내용 · 보낸 사람 · 판 · 번호가 안 실린다', rawNote && !rawNote.includes(MARK) &&
     !rawNote.includes('tester1') && !rawNote.includes('시험자') && !rawNote.includes(T.user.id) &&
     !rawNote.includes('0.2.18') && !Object.keys(note.data || {}).some(k => /id|text|from/i.test(k) && k !== 'kind'),
     rawNote.slice(0, 300));
  ok('운영자에게만 간다 (시험자 폰으로는 안 감)', feedbackPushes().every(x => x.m.token === ownerTok),
     feedbackPushes().map(x => (x.m.token || '').slice(0, 12)));

  const P1 = png(3000), J1 = jpg(2500), P2 = png(500);
  const f2 = (await send({ images: [img('image/png', P1), img('image/jpeg', J1)], platform: 'ios', screen: '친구' })).json.id;
  const f3 = (await send({ images: [img('image/png', P2)] }, T.token)).json.id;
  const f4 = (await send({ text: '틀린 토큰은 익명' }, 'not-a-real-token')).json.id;
  const f5 = (await send({ text: '다른이의 의견' }, X.token)).json.id;
  ok('의견 다섯 개', [f1, f2, f3, f4, f5].every(Number.isInteger) && f5 > f4 && f4 > f3 && f3 > f2 && f2 > f1,
     [f1, f2, f3, f4, f5]);

  /* --- 모든 길: 로그인 없음 401 · 운영자 아님 403 ---------------------------- */
  const routes = [
    ['GET', '/feedback/inbox'], ['GET', '/feedback/inbox?limit=5&before=' + f5],
    ['GET', `/feedback/inbox/${f2}/image/1`], ['POST', `/feedback/inbox/${f1}/read`],
    ['POST', '/feedback/inbox/read-all'], ['DELETE', `/feedback/inbox/${f1}`],
    /* 없는 길 · 틀린 번호도 — 운영자가 아니면 모양과 상관없이 403 (길이 있는지도 모르게). */
    ['GET', '/feedback/inbox/abc/image/1'], ['GET', '/feedback/inbox/999999/image/9'], ['PUT', '/feedback/inbox']
  ];
  const unauth = [], badTok = [], nonOp = [];
  for (const [m, p] of routes) {
    unauth.push([m, p, is401(await call(m, p))]);
    badTok.push([m, p, is401(await call(m, p, null, 'not-a-real-token'))]);
    nonOp.push([m, p, is403(await call(m, p, null, T.token)) && is403(await call(m, p, null, X.token))]);
  }
  ok('로그인 없으면 모든 길 401 (다른 길과 같은 관문)', unauth.every(x => x[2]), unauth.filter(x => !x[2]));
  ok('틀린 토큰도 모든 길 401', badTok.every(x => x[2]), badTok.filter(x => !x[2]));
  ok('운영자가 아니면 모든 길(사진 포함) 403 {ok:false, error:"운영자만 볼 수 있어요"}',
     nonOp.every(x => x[2]), nonOp.filter(x => !x[2]));
  ok('운영자가 아닌 사람이 두드려도 아무것도 안 바뀐다 (지우기 · 읽음 안 됨)',
     dbRows('SELECT COUNT(*) c FROM feedback')[0].c === 5 && dbRows('SELECT COUNT(*) c FROM feedback WHERE read_at IS NOT NULL')[0].c === 0);
  const img403 = await call('GET', `/feedback/inbox/${f2}/image/1`, null, T.token);
  ok('403 사진 응답에 사진 바이트가 한 조각도 없다', img403.status === 403 && !img403.buf.includes(P1.subarray(8, 40)));

  /* --- 운영자 목록 ------------------------------------------------------------- */
  const L = await call('GET', '/feedback/inbox', null, O.token);
  ok('운영자: 200 {ok:true, unread, items, nextBefore}', L.status === 200 && L.json.ok === true &&
     Array.isArray(L.json.items) && 'nextBefore' in L.json, L.json);
  ok('새것부터 (번호 내림차순)', JSON.stringify(L.json.items.map(x => x.id)) === JSON.stringify([f5, f4, f3, f2, f1]),
     L.json.items.map(x => x.id));
  ok('안 읽은 수 5 · 다음 쪽 없음', L.json.unread === 5 && L.json.nextBefore === null, [L.json.unread, L.json.nextBefore]);
  ok('목록도 캐시 금지 (private, no-store)', noStore(L), L.h.get('cache-control'));
  const by = id => L.json.items.find(x => x.id === id) || {};
  ok('로그인해서 보낸 것: from {name:"시험자"} · 글 · 판 · 기종 · 화면 · 시각 · read:false',
     JSON.stringify(by(f1).from) === JSON.stringify({ name: '시험자' }) && by(f1).text === MARK + ' 첫 의견' &&
     by(f1).appVersion === '0.2.18+320' && by(f1).platform === 'android' && by(f1).screen === '홈' &&
     /^\d{4}-\d{2}-\d{2}T[\d:.]+Z$/.test(by(f1).createdAt) && by(f1).read === false && by(f1).images.length === 0, by(f1));
  ok('로그인 없이 보낸 것 · 틀린 토큰으로 보낸 것: from null (익명)', by(f2).from === null && by(f4).from === null,
     [by(f2).from, by(f4).from]);
  ok('사진만 보낸 것: text "" · images [{n:1,png},{n:2,jpeg}]', by(f2).text === '' &&
     JSON.stringify(by(f2).images) === JSON.stringify([{ n: 1, type: 'image/png' }, { n: 2, type: 'image/jpeg' }]) &&
     by(f2).platform === 'ios' && by(f2).screen === '친구' && by(f2).appVersion === null, by(f2));
  ok('다른 사람의 이름도 그 사람 표시 이름으로', JSON.stringify(by(f5).from) === JSON.stringify({ name: '다른이' }));
  ok('아이디 · 내부 id · 사진 바이트는 목록에 안 실린다', !/tester1|other1|"owner"/.test(L.text) &&
     !L.text.includes(T.user.id) && !L.text.includes(X.user.id) && !L.text.includes(P1.toString('base64').slice(0, 40)),
     L.text.slice(0, 200));

  /* --- 쪽 넘기기 ---------------------------------------------------------------- */
  const seen = [];
  let before = null, pages = 0, last = null;
  do {
    const r = await call('GET', '/feedback/inbox?limit=2' + (before ? '&before=' + before : ''), null, O.token);
    last = r;
    seen.push(...(r.json.items || []).map(x => x.id));
    before = r.json.nextBefore;
    pages++;
  } while (before && pages < 10);
  ok('limit=2 로 넘기면 3쪽 · 빠짐도 겹침도 없이 새것부터 · 마지막 쪽 nextBefore null',
     pages === 3 && JSON.stringify(seen) === JSON.stringify([f5, f4, f3, f2, f1]) && last.json.nextBefore === null,
     [pages, seen]);
  const p1 = await call('GET', '/feedback/inbox?limit=2', null, O.token);
  const f6 = (await send({ text: '넘기는 사이에 온 의견' }, X.token)).json.id;
  const p2 = await call('GET', '/feedback/inbox?limit=2&before=' + p1.json.nextBefore, null, O.token);
  ok('넘기는 사이에 새 의견이 와도 다음 쪽이 밀리지 않는다 (번호로 넘김)',
     JSON.stringify(p2.json.items.map(x => x.id)) === JSON.stringify([f3, f2]), p2.json.items.map(x => x.id));
  ok('unread 는 쪽과 상관없이 전체 (6)', p2.json.unread === 6, p2.json.unread);
  const lim0 = await call('GET', '/feedback/inbox?limit=0', null, O.token);
  const limBig = await call('GET', '/feedback/inbox?limit=999', null, O.token);
  const limBad = await call('GET', '/feedback/inbox?limit=abc', null, O.token);
  ok('limit 은 1~50 (0 → 1개 · 999 → 전부 6개 · 글자 → 기본 30)', lim0.json.items.length === 1 &&
     lim0.json.nextBefore === f6 && limBig.json.items.length === 6 && limBad.json.items.length === 6,
     [lim0.json.items.length, limBig.json.items.length, limBad.json.items.length]);
  const badBefore = [];
  for (const v of ['abc', '0', '-1', '1e3', '1.5', '0x10', '99999999999999999999']) {
    const r = await call('GET', '/feedback/inbox?before=' + encodeURIComponent(v), null, O.token);
    badBefore.push([v, r.status === 400 && r.json.ok === false && /[가-힣]/.test(r.json.error || '')]);
  }
  ok('틀린 before → 400 (첫 쪽으로 바꿔 주지 않음)', badBefore.every(x => x[1]), badBefore.filter(x => !x[1]));
  const oldest = await call('GET', '/feedback/inbox?before=' + f1, null, O.token);
  ok('before=가장 오래된 번호 → 빈 쪽 · nextBefore null', oldest.status === 200 && oldest.json.items.length === 0 &&
     oldest.json.nextBefore === null, oldest.json);

  /* --- 사진 ---------------------------------------------------------------------- */
  const i1 = await call('GET', `/feedback/inbox/${f2}/image/1`, null, O.token);
  ok('사진 1: 200 · image/png · 바이트 그대로', i1.status === 200 && i1.h.get('content-type') === 'image/png' &&
     i1.buf.equals(P1), [i1.status, i1.h.get('content-type'), i1.buf.length]);
  ok('사진: Cache-Control private, no-store · nosniff · 길이', noStore(i1) &&
     i1.h.get('x-content-type-options') === 'nosniff' && Number(i1.h.get('content-length')) === P1.length,
     [i1.h.get('cache-control'), i1.h.get('x-content-type-options'), i1.h.get('content-length')]);
  const i2 = await call('GET', `/feedback/inbox/${f2}/image/2`, null, O.token);
  ok('사진 2: image/jpeg · 바이트 그대로', i2.status === 200 && i2.h.get('content-type') === 'image/jpeg' && i2.buf.equals(J1));
  const i3 = await call('GET', `/feedback/inbox/${f3}/image/1`, null, O.token);
  ok('로그인해서 보낸 사진도 운영자는 본다', i3.status === 200 && i3.buf.equals(P2));
  const miss = [
    [`/feedback/inbox/${f2}/image/3`, 404], [`/feedback/inbox/${f2}/image/4`, 404], [`/feedback/inbox/${f2}/image/99`, 404],
    [`/feedback/inbox/${f1}/image/1`, 404], ['/feedback/inbox/999999/image/1', 404],
    [`/feedback/inbox/${f2}/image/0`, 400], [`/feedback/inbox/${f2}/image/x`, 400], [`/feedback/inbox/${f2}/image/1.0`, 400],
    ['/feedback/inbox/abc/image/1', 400], ['/feedback/inbox/0/image/1', 400], ['/feedback/inbox/-3/image/1', 400],
    [`/feedback/inbox/${f2}/image`, 404], [`/feedback/inbox/${f2}/nope`, 404]
  ];
  const missBad = [];
  for (const [p, st] of miss) {
    const r = await call('GET', p, null, O.token);
    if (!(r.status === st && r.json.ok === false && noStore(r))) missBad.push([p, r.status, st]);
  }
  ok('없는 사진 · 없는 의견 → 404 · 틀린 번호 → 400 (모두 {ok:false} · no-store)', missBad.length === 0, missBad);
  /* 서버를 거치지 않고 들어간 행의 형식이 text/html 이어도 그대로 내보내지 않는다. */
  const w = new DatabaseSync(DB);
  const hId = Number(w.prepare('INSERT INTO feedback (created_at, text) VALUES (?, ?)').run(new Date().toISOString(), '손으로 넣음').lastInsertRowid);
  w.prepare('INSERT INTO feedback_images (feedback_id, idx, type, data) VALUES (?,?,?,?)')
    .run(hId, 1, 'text/html', Buffer.from('<script>alert(1)</script>'));
  w.close();
  const ih = await call('GET', `/feedback/inbox/${hId}/image/1`, null, O.token);
  ok('모르는 형식(text/html)으로 저장된 사진 → application/octet-stream 으로', ih.status === 200 &&
     ih.h.get('content-type') === 'application/octet-stream', ih.h.get('content-type'));

  /* --- 읽음 · 전부 읽음 ------------------------------------------------------------ */
  const rd = await call('POST', `/feedback/inbox/${f1}/read`, null, O.token);
  const at1 = (dbRows('SELECT read_at FROM feedback WHERE id=?', f1)[0] || {}).read_at;
  ok('읽음: {ok:true} · read_at 이 찍힌다 · no-store', rd.status === 200 && rd.json.ok === true &&
     /^\d{4}-\d{2}-\d{2}T/.test(at1 || '') && noStore(rd), [rd.json, at1]);
  await wait(20);
  await call('POST', `/feedback/inbox/${f1}/read`, null, O.token);
  ok('두 번 읽어도 처음 읽은 시각 그대로', (dbRows('SELECT read_at FROM feedback WHERE id=?', f1)[0] || {}).read_at === at1);
  const afterRead = await call('GET', '/feedback/inbox', null, O.token);
  ok('목록에 read:true · 안 읽은 수가 하나 줄었다 (7 → 6)',
     (afterRead.json.items.find(x => x.id === f1) || {}).read === true && afterRead.json.unread === 6, afterRead.json.unread);
  ok('없는 번호를 읽음 → {ok:true} (할 일이 없는 것이지 실패가 아님)',
     (await call('POST', '/feedback/inbox/999999/read', null, O.token)).json.ok === true);
  ok('읽음에 틀린 번호 → 400', (await call('POST', '/feedback/inbox/abc/read', null, O.token)).status === 400);
  ok('읽음을 GET 으로 → 404 (길은 POST 만)', (await call('GET', `/feedback/inbox/${f2}/read`, null, O.token)).status === 404);

  const upBad = await call('POST', '/feedback/inbox/read-all', { upTo: 'abc' }, O.token);
  ok('전부 읽음 upTo 가 틀림 → 400 · 아무것도 안 바뀜', upBad.status === 400 &&
     dbRows('SELECT COUNT(*) c FROM feedback WHERE read_at IS NULL')[0].c === 6);
  const up = await call('POST', '/feedback/inbox/read-all', { upTo: f3 }, O.token);
  const unreadIds = dbRows('SELECT id FROM feedback WHERE read_at IS NULL ORDER BY id').map(r => r.id);
  ok('전부 읽음 {upTo:f3} → f3 까지만 (그 뒤에 온 것은 그대로)', up.status === 200 && up.json.ok === true &&
     JSON.stringify(unreadIds) === JSON.stringify([f4, f5, f6, hId]), unreadIds);
  const ra = await call('POST', '/feedback/inbox/read-all', null, O.token);
  const afterAll = await call('GET', '/feedback/inbox', null, O.token);
  ok('전부 읽음 (본문 없음) → 안 읽은 것 전부 · unread 0', ra.status === 200 && ra.json.ok === true &&
     afterAll.json.unread === 0 && afterAll.json.items.every(x => x.read === true), afterAll.json.unread);

  /* --- 지우기 + 노트북 도구가 꺼낸 캡처 ------------------------------------------- */
  const toolHome = fs.mkdtempSync(path.join(os.tmpdir(), 'mybody-inbox-tool-'));
  const tool = (...args) => {
    const r = spawnSync(process.execPath, [path.join(ROOT, 'tools', 'feedback.js')].concat(args), {
      cwd: ROOT, encoding: 'utf8', timeout: 30000,
      env: Object.assign({}, process.env, { HOME: toolHome, USERPROFILE: toolHome, DB, NODE_NO_WARNINGS: '1' }) });
    return { code: r.status, out: (r.stdout || '') + (r.stderr || '') };
  };
  const dir = path.join(toolHome, '.mybody', 'feedback');
  const t1 = tool('--all');
  const c1 = path.join(dir, f2 + '-1.png'), c2 = path.join(dir, f2 + '-2.jpg'), c3 = path.join(dir, f3 + '-1.png');
  ok('노트북 도구가 먼저 캡처를 꺼내 둔다', t1.code === 0 && fs.existsSync(c1) && fs.existsSync(c2) && fs.existsSync(c3),
     [t1.code, fs.existsSync(dir) ? fs.readdirSync(dir) : 'no dir']);

  const d1 = await call('DELETE', `/feedback/inbox/${f2}`, null, O.token);
  ok('지우기: {ok:true} · no-store', d1.status === 200 && d1.json.ok === true && noStore(d1), d1.json);
  ok('지운 의견의 행이 안 남는다', dbRows('SELECT COUNT(*) c FROM feedback WHERE id=?', f2)[0].c === 0);
  ok('지운 의견의 사진도 안 남는다', dbRows('SELECT COUNT(*) c FROM feedback_images WHERE feedback_id=?', f2)[0].c === 0);
  const afterDel = await call('GET', '/feedback/inbox', null, O.token);
  ok('목록에서 빠지고 나머지는 그대로', !afterDel.json.items.some(x => x.id === f2) && afterDel.json.items.length === 6 &&
     afterDel.json.items.some(x => x.id === f3), afterDel.json.items.map(x => x.id));
  ok('지운 의견의 사진 → 404', (await call('GET', `/feedback/inbox/${f2}/image/1`, null, O.token)).status === 404);
  ok('다시 지워도 {ok:true} (다른 기기에서 먼저 지운 경우)',
     (await call('DELETE', `/feedback/inbox/${f2}`, null, O.token)).json.ok === true);
  ok('지우기에 틀린 번호 → 400', (await call('DELETE', '/feedback/inbox/1x', null, O.token)).status === 400);
  const t2 = tool('--no-export');
  ok('노트북 도구가 다음에 돌 때 지워진 의견의 꺼낸 캡처를 지운다', t2.code === 0 && !fs.existsSync(c1) &&
     !fs.existsSync(c2) && /캡처 2장을 .* 에서 지웠습니다/.test(t2.out), t2.out.slice(0, 300));
  ok('남아 있는 의견의 캡처는 그대로', fs.existsSync(c3), fs.existsSync(dir) ? fs.readdirSync(dir) : 'no dir');
  try { fs.rmSync(toolHome, { recursive: true, force: true }); } catch (e) {}

  ok('서버 로그에는 경로 · 상태만 — 의견 내용이 안 남는다', /GET\s+\/api\/feedback\/inbox/.test(out) &&
     !out.includes(MARK) && !out.includes('넘기는 사이에'), out.split('\n').filter(l => /inbox/.test(l)).slice(0, 3));
  ok('뜰 때 운영자 아이디를 찍지 않는다', !/owner/i.test(out.split('\n').filter(l => /의견/.test(l)).join('\n')),
     out.split('\n').filter(l => /의견/.test(l)));

  /* --- [3] 운영자가 없을 때 ----------------------------------------------------- */
  console.log('\n[3] FEEDBACK_NOTIFY 가 비었거나 없는 아이디 → 아무도 운영자가 아님');
  await stop();
  srv = boot({ FEEDBACK_NOTIFY: '' });
  ok('FEEDBACK_NOTIFY="" 로 다시 뜬다', await waitUp(), out.slice(-300));
  const meE = await call('GET', '/me', null, O.token);
  ok('비었으면: 옛 운영자에게도 isOperator 칸이 없다', meE.status === 200 && !('isOperator' in meE.json.user), meE.json.user);
  const emptyBad = [];
  for (const [m, p] of routes) {
    const r = await call(m, p, null, O.token);
    if (!is403(r)) emptyBad.push([m, p, r.status]);
  }
  ok('비었으면: 옛 운영자도 모든 길 403', emptyBad.length === 0, emptyBad);
  ok('비었으면: 뜰 때 의견함 줄이 없다', !/의견함/.test(out), out.split('\n').filter(l => /의견/.test(l)));

  await stop();
  srv = boot({ FEEDBACK_NOTIFY: 'nobody-here' });
  ok('없는 아이디로 다시 뜬다', await waitUp());
  /* 가입 코드가 있는 서버여도 — 코드를 받은 시험자가 그 아이디를 먼저 가져갈 수 있습니다. */
  ok('없는 아이디: 가입 코드 서버에서도 뜰 때 "⚠ 의견함 … 계정이 아직 없습니다" (아이디는 안 찍음)',
     await until(() => /⚠ 의견함: 설정\(feedbackNotify\)에 적은 아이디의 계정이 아직 없습니다/.test(out)) &&
     !/nobody-here/.test(out), out.split('\n').filter(l => /의견/.test(l)));
  const meN = await call('GET', '/me', null, O.token);
  ok('없는 아이디: 아무에게도 isOperator 가 없다 · 의견함 403', !('isOperator' in meN.json.user) &&
     is403(await call('GET', '/feedback/inbox', null, O.token)) && is403(await call('GET', '/feedback/inbox', null, T.token)));
  const nNow = feedbackPushes().length;
  await send({ text: '받을 사람 없음' }, T.token);
  await wait(400);
  ok('없는 아이디: 의견은 받고 알림은 아무에게도 안 간다', feedbackPushes().length === nNow);

  await stop();
  srv = boot({ FEEDBACK_NOTIFY: 'OWNER' });
  ok('있는 아이디로 다시 뜬다 → 뜰 때 "의견함 켜짐" (아이디는 안 찍음)', await waitUp() &&
     await until(() => /의견함\s+켜짐/.test(out)) && !/owner/i.test(out.split('\n').filter(l => /의견/.test(l)).join('\n')),
     out.split('\n').filter(l => /의견/.test(l)));
  ok('다시 뜬 뒤에도 운영자는 그대로 본다', (await call('GET', '/feedback/inbox', null, O.token)).status === 200);

  await stop();
  srv = boot({ FEEDBACK_NOTIFY: 'future-owner', OPEN_SIGNUP: '1' });
  ok('누구나 가입 + 아직 없는 아이디 → 뜰 때 "먼저 가입한 사람이 모든 의견을 본다" 를 크게 말한다',
     await waitUp() && await until(() => /⚠ 의견함: 누구나 가입할 수 있는데/.test(out)),
     out.split('\n').filter(l => /의견/.test(l)));
  await stop();
}

(async () => {
  try {
    dbUnit();
    await new Promise(r => hook.listen(HOOK, '127.0.0.1', r));
    await integration();
  } catch (e) {
    fail++;
    console.error(e);
  }
  await stop();
  hook.close();
  try { fs.rmSync(CERT.dir, { recursive: true, force: true }); } catch (e) {}
  try { fs.rmSync(TMP, { recursive: true, force: true }); } catch (e) {}
  console.log(`\n통과 ${pass} / 실패 ${fail}`);
  process.exit(fail ? 1 : 0);
})();
process.on('exit', () => { if (srv) { try { srv.kill(); } catch (e) {} } });
