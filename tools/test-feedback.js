/* =============================================================================
 * tools/test-feedback.js — 앱 안 「의견 보내기」 (POST /api/feedback) 전 구간
 *
 *   node tools/test-feedback.js
 *
 * 왜 이 시험이 있나
 *   의견은 **로그인 없이도** 받는 길입니다. 로그인 관문 앞에 있는 길은 전부
 *   남용의 표적이라, 막는 장치 하나하나가 실제로 막는지를 HTTP 로 두드려 봅니다.
 *   그리고 이 길은 사진(몸 숫자가 찍혀 있을 수 있는 화면 캡처)을 저장합니다.
 *   처리방침에 "탈퇴하면 지웁니다 · 1년 뒤 지웁니다 · 알림에는 내용이 안 실립니다"
 *   라고 적었으니, 그 약속이 코드에서 지켜지는지를 여기서 봅니다.
 *
 * 보는 것
 *   [1] 검사 규칙(server/feedback.js) — 글 · 사진 · 판 · 기종 · 화면
 *   [2] DB — 넣기 · 목록 · 탈퇴하면 지움 · 1년 지나면 지움
 *   [3] 진짜 서버 + 가짜 FCM(https) — 익명 · 로그인 · 틀린 토큰은 익명 · 400 · 413 ·
 *       429(21번째) · 동시에 보내도 한도를 못 넘음 · 받는 중인 것 묶음(503) · 느린 올리기 ·
 *       주인 알림 한 번(10분 묶음) · 알림에 내용 없음 · 로그에 내용 없음 ·
 *       탈퇴 · 뜰 때 1년 지난 것 정리 · 설정 키(feedbackNotify)
 *   [4] GET /api/version 의 참여 링크(join)와 tools/app-version.js --join-*
 *   [5] 노트북 도구 tools/feedback.js — 목록 · 사진 꺼내기 · 읽음 표시 · 아이디를 안 찍음 ·
 *       지워진 의견의 꺼낸 캡처 지우기 · 번호를 다시 안 씀
 *
 * 진짜 구글을 부르지 않습니다. 가짜 OAuth · FCM 을 https 로 세웁니다(test-fcm.js 와
 * 같은 방법 — 서버는 http 로 바꾼 FCM 주소를 무시합니다).
 * ========================================================================== */
'use strict';
/* 검사하는 사람의 ~/.mybody 설정(진짜 서비스 계정 · 의견 알림 아이디)이 결과를 바꾸지 않게. */
const TESTENV = require('./testenv.js');
const { spawn, spawnSync } = require('node:child_process');
const http = require('node:http');
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
const TMP = fs.mkdtempSync(path.join(os.tmpdir(), 'mybody-feedback-'));
const PW = 'test-password-1';

/* 앞머리만 맞춘 가짜 사진. 서버는 앞머리 · 크기 · base64 모양만 봅니다. */
const PNG_HEAD = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
const JPG_HEAD = Buffer.from([0xff, 0xd8, 0xff, 0xe0]);
const png = (n = 64) => Buffer.concat([PNG_HEAD, crypto.randomBytes(Math.max(0, n - PNG_HEAD.length))]);
const jpg = (n = 64) => Buffer.concat([JPG_HEAD, crypto.randomBytes(Math.max(0, n - JPG_HEAD.length))]);
const img = (type, buf) => ({ type, data: buf.toString('base64') });

/* --- [1] 검사 규칙 -------------------------------------------------------- */
function unit() {
  console.log('\n[1] 검사 규칙 (server/feedback.js)');
  const P = FB.parseFeedback;
  const t = P({ text: '  홈 화면 숫자가 겹쳐요  ' });
  ok('글만 → 통과 (앞뒤 공백은 다듬음)', t.ok && t.value.text === '홈 화면 숫자가 겹쳐요' && t.value.images.length === 0, t);
  const i = P({ images: [img('image/png', png())] });
  ok('사진만 → 통과 (글 없음 = null)', i.ok && i.value.text === null && i.value.images.length === 1 &&
     Buffer.isBuffer(i.value.images[0].data), i.ok);
  ok('JPEG 도 통과', P({ images: [img('image/jpeg', jpg())] }).ok);
  ok('글 · 사진 둘 다 없으면 거절', !P({}).ok && /하나는 있어야/.test(P({}).reason), P({}));
  ok('공백만 있는 글 + 사진 없음 → 거절', !P({ text: '   \n  ', images: [] }).ok);
  ok('본문이 배열 · null 이면 거절', !P([]).ok && !P(null).ok);
  ok('2000자 → 통과', P({ text: '가'.repeat(2000) }).ok);
  ok('2001자 → 거절', !P({ text: '가'.repeat(2001) }).ok && /2000자/.test(P({ text: '가'.repeat(2001) }).reason));
  ok('이모지 2000개도 통과 (글자 수는 코드 포인트로)', P({ text: '😀'.repeat(2000) }).ok);
  ok('글이 숫자 · 객체면 거절', !P({ text: 12 }).ok && !P({ text: { a: 1 } }).ok);
  const esc = P({ text: 'a\x1b]0;hacked\x07b\r\nc\u202ed' });
  ok('제어 문자 · 방향 뒤집기 문자는 빼고, \\r\\n 은 \\n 으로', esc.ok && esc.value.text === 'a]0;hackedb\ncd', esc.value);
  ok('사진 3장 → 통과', P({ images: [img('image/png', png()), img('image/jpeg', jpg()), img('image/png', png())] }).ok);
  const four = P({ images: [1, 2, 3, 4].map(() => img('image/png', png())) });
  ok('사진 4장 → 거절', !four.ok && /3장/.test(four.reason), four);
  ok('images 가 배열이 아니면 거절', !P({ images: 'x' }).ok && !P({ images: { 0: 1 } }).ok);
  ok('모르는 형식(image/gif) → 거절', !P({ images: [{ type: 'image/gif', data: png().toString('base64') }] }).ok);
  ok('형식 이름이 없으면 거절', !P({ images: [{ data: png().toString('base64') }] }).ok);
  ok('물려받은 이름(constructor · __proto__ · toString)을 형식으로 대도 거절 (500 이 아님)',
     ['constructor', '__proto__', 'toString', 'hasOwnProperty'].every(ty =>
       !P({ images: [{ type: ty, data: png().toString('base64') }] }).ok));
  ok('이상한 모양은 전부 거절 — 던지지 않는다', [
    { images: [null] }, { images: [5] }, { images: [{ type: 'image/png', data: 123 }] },
    { text: 'x', appVersion: {} }, { text: 'x', screen: 5 }, { text: 'x', platform: ['ios'] }, 'hello', 7
  ].every(b => P(b).ok === false));
  ok('확장자: png · jpg · 모르면 bin', FB.extFor('image/png') === 'png' && FB.extFor('image/jpeg') === 'jpg' &&
     FB.extFor('constructor') === 'bin');
  const b64 = png(30).toString('base64');
  ok('base64 에 틀린 글자 → 거절', !P({ images: [{ type: 'image/png', data: b64.slice(0, -4) + '$$$$' }] }).ok);
  ok('base64 길이가 4의 배수가 아니면 거절', !P({ images: [{ type: 'image/png', data: b64 + 'A' }] }).ok);
  ok('base64 안에 줄바꿈 → 거절', !P({ images: [{ type: 'image/png', data: b64.slice(0, 8) + '\n' + b64.slice(8) }] }).ok);
  /* "iVBORw0KGgo=" 는 끝의 남는 비트가 0 이 아니라 되돌려 인코딩하면 달라집니다. */
  ok('남는 비트가 0 이 아닌 base64 → 거절 (되돌려 인코딩이 다름)',
     !P({ images: [{ type: 'image/png', data: 'iVBORw0KGgp=' }] }).ok);
  ok('data URL 머리(data:image/png;base64,)는 안 받음',
     !P({ images: [{ type: 'image/png', data: 'data:image/png;base64,' + b64 }] }).ok);
  const liar = P({ images: [img('image/png', jpg())] });
  ok('PNG 라면서 JPEG 바이트 → 거절', !liar.ok && /PNG 가 아닙니다/.test(liar.reason), liar);
  ok('JPEG 라면서 PNG 바이트 → 거절', !P({ images: [img('image/jpeg', png())] }).ok);
  ok('앞머리보다 짧은 사진 → 거절', !P({ images: [img('image/png', PNG_HEAD.subarray(0, 2))] }).ok);
  ok('풀어서 딱 1.5MB → 통과', P({ images: [img('image/png', png(FB.IMAGE_BYTES_MAX))] }).ok);
  const big = P({ images: [img('image/png', png(FB.IMAGE_BYTES_MAX + 3))] });
  ok('1.5MB 넘으면 → 거절', !big.ok && /너무 큽니다/.test(big.reason), big);
  ok('appVersion "0.2.17+310" 통과', P({ text: 'x', appVersion: '0.2.17+310' }).value.appVersion === '0.2.17+310');
  ok('appVersion 33자 · 한글 · 숫자 → 거절', !P({ text: 'x', appVersion: '1'.repeat(33) }).ok &&
     !P({ text: 'x', appVersion: '판' }).ok && !P({ text: 'x', appVersion: 17 }).ok);
  ok('platform android · ios 통과, web 거절', P({ text: 'x', platform: 'ios' }).ok &&
     P({ text: 'x', platform: 'android' }).ok && !P({ text: 'x', platform: 'web' }).ok);
  ok('screen 64자 통과 · 65자 거절', P({ text: 'x', screen: '홈'.repeat(64) }).ok && !P({ text: 'x', screen: '홈'.repeat(65) }).ok);
  ok('screen 의 줄바꿈은 한 칸 공백 · 제어 문자는 뺌', P({ text: 'x', screen: '친구\n탭\x1b' }).value.screen === '친구 탭');
  ok('빈 appVersion · platform · screen 은 없음(null)', (() => {
    const v = P({ text: 'x', appVersion: '', platform: '', screen: '' }).value;
    return v.appVersion === null && v.platform === null && v.screen === null;
  })());
  ok('모르는 칸(userId 등)은 무시 — 보낸 사람은 토큰으로만', P({ text: 'x', userId: 'user_x' }).ok &&
     !('userId' in P({ text: 'x', userId: 'user_x' }).value));
  ok('가명: 6자 16진수 · 같은 사람 = 같은 가명 · 익명', /^[0-9a-f]{6}$/.test(FB.pseudonym('user_abc')) &&
     FB.pseudonym('user_abc') === FB.pseudonym('user_abc') && FB.pseudonym('user_abc') !== FB.pseudonym('user_abd') &&
     FB.pseudonym(null) === '익명');
  let now = 0;
  const allow = FB.makeThrottle(1000, () => now);
  const seq = [allow(), (now = 500, allow()), (now = 999, allow()), (now = 1000, allow()), (now = 1500, allow())];
  ok('알림 묶음: 처음 → 예, 간격 안 → 아니요, 간격 지나면 → 예', JSON.stringify(seq) === '[true,false,false,true,false]', seq);
  ok('약속한 숫자: 2000자 · 3장 · 1.5MB · 하루 20개 · 1년 · 알림 10분', FB.TEXT_MAX === 2000 && FB.IMAGES_MAX === 3 &&
     FB.IMAGE_BYTES_MAX === 1_500_000 && FB.PER_DAY === 20 && FB.KEEP_DAYS === 365 && FB.NOTIFY_GAP_MS === 600_000);
  ok('본문 상한은 사진 3장(base64)이 들어갈 만큼', FB.BODY_LIMIT >= 3 * FB.IMAGE_B64_MAX + 50_000 && FB.BODY_LIMIT <= 6_500_000,
     FB.BODY_LIMIT);
}

/* --- [2] DB ---------------------------------------------------------------- */
function dbUnit() {
  console.log('\n[2] DB — 넣기 · 목록 · 탈퇴 · 1년');
  const file = path.join(TMP, 'unit.db');
  const api = DBM.makeApi(DBM.open(file));
  const mk = h => api.signUp({ handle: h, password: PW, displayName: h, healthConsent: DBM.HEALTH_CONSENT_VERSION });
  const a = mk('dbuser1'), b = mk('dbuser2');
  const va = FB.parseFeedback({ text: '첫 의견', images: [img('image/png', png(100)), img('image/jpeg', jpg(80))],
                                appVersion: '0.2.17+310', platform: 'android', screen: '홈' }).value;
  const idA = api.addFeedback(a.user.id, va);
  const idB = api.addFeedback(b.user.id, FB.parseFeedback({ images: [img('image/png', png(50))] }).value);
  const idN = api.addFeedback(null, FB.parseFeedback({ text: '익명 의견' }).value);
  ok('번호가 늘어난다', idA > 0 && idB > idA && idN > idB, [idA, idB, idN]);
  const list = api.listFeedback();
  ok('목록은 새것부터 · 사진 개수 · 메타가 그대로', list.length === 3 && list[0].id === idN &&
     list[2].images === 2 && list[2].appVersion === '0.2.17+310' && list[2].platform === 'android' &&
     list[2].screen === '홈' && list[2].userId === a.user.id && list[0].userId === null, list);
  const ims = api.feedbackImages(idA);
  ok('사진은 순서 · 형식 · 바이트 그대로', ims.length === 2 && ims[0].idx === 1 && ims[0].type === 'image/png' &&
     ims[0].data.equals(va.images[0].data) && ims[1].type === 'image/jpeg', ims.map(x => [x.idx, x.type, x.data.length]));
  ok('세기: 사람별 · 전체', api.countFeedbackSince(a.user.id, '2000-01-01') === 1 &&
     api.countFeedbackSince(null, '2000-01-01') === 3 && api.countFeedbackSince(a.user.id, '2999-01-01') === 0);
  ok('읽음 표시 → 안 읽은 목록에서 빠짐 · 두 번째는 0개', api.markFeedbackRead([idB]) === 1 &&
     api.markFeedbackRead([idB]) === 0 && api.listFeedback().length === 2 &&
     api.listFeedback({ includeRead: true }).length === 3);

  api.deleteMe(a.user.id);
  const raw = new DatabaseSync(file, { readOnly: true });
  const cnt = (sql, ...x) => raw.prepare(sql).get(...x).c;
  ok('탈퇴하면 그 사람의 의견이 안 남는다', cnt('SELECT COUNT(*) c FROM feedback WHERE user_id=?', a.user.id) === 0);
  ok('탈퇴하면 그 의견에 붙인 화면도 안 남는다', cnt('SELECT COUNT(*) c FROM feedback_images WHERE feedback_id=?', idA) === 0);
  ok('다른 사람 · 익명 의견은 그대로', cnt('SELECT COUNT(*) c FROM feedback') === 2 &&
     cnt('SELECT COUNT(*) c FROM feedback_images WHERE feedback_id=?', idB) === 1);
  raw.close();

  /* 1년 — created_at 을 직접 과거로 돌려 둡니다. */
  const w = new DatabaseSync(file);
  const ago = d => new Date(Date.now() - d * 86400000).toISOString();
  w.prepare('UPDATE feedback SET created_at=? WHERE id=?').run(ago(366), idB);
  w.prepare('UPDATE feedback SET created_at=? WHERE id=?').run(ago(364), idN);
  w.close();
  const gone = api.pruneOldFeedback();
  const r2 = new DatabaseSync(file, { readOnly: true });
  ok('1년 지난 의견을 지운다 (지운 개수 1)', gone === 1 &&
     r2.prepare('SELECT COUNT(*) c FROM feedback WHERE id=?').get(idB).c === 0, gone);
  ok('1년 지난 의견의 화면도 지운다', r2.prepare('SELECT COUNT(*) c FROM feedback_images WHERE feedback_id=?').get(idB).c === 0);
  ok('1년 안 된 것은 남긴다', r2.prepare('SELECT COUNT(*) c FROM feedback WHERE id=?').get(idN).c === 1);
  r2.close();

  /* 옛 DB(표가 없던 때)를 열어도 표가 생긴다 — 마이그레이션. */
  const old = path.join(TMP, 'old.db');
  const o = new DatabaseSync(old);
  o.exec('CREATE TABLE users (id TEXT PRIMARY KEY, handle TEXT UNIQUE NOT NULL, provider TEXT NOT NULL, ' +
         'display_name TEXT NOT NULL, invite_code TEXT UNIQUE NOT NULL, created_at TEXT NOT NULL)');
  o.close();
  DBM.open(old).close();
  const o2 = new DatabaseSync(old, { readOnly: true });
  const tables = o2.prepare("SELECT name FROM sqlite_master WHERE type='table'").all().map(x => x.name);
  const cols = o2.prepare('PRAGMA table_info(feedback)').all().map(c => c.name);
  o2.close();
  ok('옛 DB 에 feedback · feedback_images 가 생긴다', tables.includes('feedback') && tables.includes('feedback_images'), tables);
  ok('feedback 칸: id · created_at · user_id · app_version · platform · screen · text · read_at',
     JSON.stringify(cols) === JSON.stringify(['id', 'created_at', 'user_id', 'app_version', 'platform', 'screen', 'text', 'read_at']), cols);
}

/* --- 가짜 OAuth · FCM (https) --------------------------------------------- */
const PORT = 9100 + Math.floor(Math.random() * 400);
const HOOK = PORT + 500 + Math.floor(Math.random() * 50);
const PAIR = 'feedback-pair-secret';
const DB = path.join(TMP, 'srv.db');
const B = `http://127.0.0.1:${PORT}/api`;
const RSA = crypto.generateKeyPairSync('rsa', { modulusLength: 2048 });
const SA = {
  type: 'service_account', project_id: 'mybody-test', private_key_id: 'kid-1',
  private_key: RSA.privateKey.export({ type: 'pkcs8', format: 'pem' }),
  client_email: 'push@mybody-test.iam.gserviceaccount.com', token_uri: `https://127.0.0.1:${HOOK}/token`
};
const CERT = (() => {
  const d = fs.mkdtempSync(path.join(os.tmpdir(), 'mybody-fbcert-'));
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
async function call(method, p, body, token, raw) {
  const r = await fetch(B + p, {
    method,
    headers: Object.assign({ 'Content-Type': 'application/json' }, token ? { Authorization: 'Bearer ' + token } : {}),
    body: raw !== undefined ? raw : (body ? JSON.stringify(body) : undefined)
  });
  let j = null; try { j = await r.json(); } catch (e) {}
  return { status: r.status, json: j || {} };
}
const send = (body, token) => call('POST', '/feedback', body, token);
/* 본문을 반만 보내 두고 멈춥니다 — "받는 중" 인 의견을 만들어 동시에 온 것을 흉내 냅니다.
   finish() 가 나머지를 보내고 {status, json} 을 돌려줍니다(끊기면 status 0). */
function partial(body, token) {
  const raw = Buffer.from(JSON.stringify(body));
  const cut = Math.floor(raw.length / 2);
  let done;
  const result = new Promise(r => { done = r; });
  const req = http.request(B + '/feedback', {
    method: 'POST',
    headers: Object.assign({ 'Content-Type': 'application/json', 'Content-Length': raw.length },
                           token ? { Authorization: 'Bearer ' + token } : {})
  }, res => {
    const chunks = [];
    res.on('data', c => chunks.push(c));
    res.on('end', () => {
      let j = {}; try { j = JSON.parse(Buffer.concat(chunks).toString('utf8')); } catch (e) {}
      done({ status: res.statusCode, json: j });
    });
  });
  req.on('error', () => done({ status: 0, json: {} }));
  req.write(raw.subarray(0, cut));
  return { finish: () => { req.end(raw.subarray(cut)); return result; } };
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
const is400 = r => r.status === 400 && r.json.ok === false && typeof r.json.error === 'string' &&
  /[가-힣]/.test(r.json.error) && r.json.reason === r.json.error;

async function integration() {
  /* 주인이 실제로 하는 그대로: 설정 파일에 feedbackNotify(아이디), 서비스 계정 파일은 기본 자리. */
  const home = path.join(TESTENV.home, '.mybody');
  fs.mkdirSync(home, { recursive: true });
  fs.writeFileSync(path.join(home, 'fcm-service-account.json'), JSON.stringify(SA));
  fs.writeFileSync(path.join(home, 'config.json'), JSON.stringify({ feedbackNotify: 'Owner' }));

  console.log('\n[3] 진짜 서버 — 받기');
  srv = boot();
  ok('서버가 뜬다', await waitUp(), out.slice(-400));
  const mk = async (handle, name) => (await call('POST', '/auth/signup', {
    handle, password: PW, displayName: name, pairSecret: PAIR, healthConsent: DBM.HEALTH_CONSENT_VERSION })).json;
  const O = await mk('owner', '주인'), T = await mk('tester1', '시험자'), T2 = await mk('tester2', '둘째');
  ok('계정 셋', !!(O.token && T.token && T2.token));
  const reg = await call('POST', '/push/device', { token: 'ok_owner_' + crypto.randomBytes(24).toString('hex'),
                                                   platform: 'android', permission: 'granted' }, O.token);
  ok('주인 폰(앱 알림) 등록', reg.status === 200 && reg.json.fcm === true, reg.json);

  const MARK = '비밀스러운-의견-내용-' + crypto.randomBytes(4).toString('hex');
  const a = await send({ text: MARK + ' 홈 화면 숫자가 겹쳐요', appVersion: '0.2.17+310', platform: 'android', screen: '홈' }, T.token);
  ok('글만 (로그인) → 200 {ok, id:숫자}', a.status === 200 && a.json.ok === true && Number.isInteger(a.json.id), a);
  const rowA = dbRows('SELECT * FROM feedback WHERE id=?', a.json.id)[0] || {};
  ok('로그인했으면 그 계정에 묶인다', rowA.user_id === T.user.id, rowA.user_id);
  ok('판 · 기종 · 화면 · 시각이 저장된다', rowA.app_version === '0.2.17+310' && rowA.platform === 'android' &&
     rowA.screen === '홈' && /^\d{4}-\d{2}-\d{2}T/.test(rowA.created_at) && rowA.read_at === null, rowA);

  ok('주인에게 알림이 한 번 간다', await until(() => feedbackPushes().length === 1), fcmGot.length);
  const note = (feedbackPushes()[0] || {}).m || {};
  ok('알림 문구는 일반 문구뿐 (새 의견이 왔어요 · 노트북에서 확인하세요)',
     note.notification && note.notification.title === '새 의견이 왔어요' &&
     note.notification.body === '노트북에서 확인하세요', note.notification);
  const rawNote = (feedbackPushes()[0] || {}).raw || '';
  ok('알림에 의견 내용 · 보낸 사람 · 판이 안 실린다', rawNote && !rawNote.includes(MARK) && !rawNote.includes('tester1') &&
     !rawNote.includes(T.user.id) && !rawNote.includes('0.2.17') && !rawNote.includes('시험자'), rawNote.slice(0, 300));
  ok('앱이 모르는 곳으로 가지 않는다 (route 없음) · 한 칸(tag feedback)',
     !('route' in (note.data || {})) && note.android && note.android.notification.tag === 'feedback', note.data);

  const pngBuf = png(2000);
  const b = await send({ images: [img('image/png', pngBuf)] });
  ok('사진만 (로그인 없음) → 200', b.status === 200 && b.json.ok === true, b);
  ok('로그인 없으면 익명 (user_id 없음)', (dbRows('SELECT user_id FROM feedback WHERE id=?', b.json.id)[0] || {}).user_id === null);
  const imRow = dbRows('SELECT type, data FROM feedback_images WHERE feedback_id=?', b.json.id)[0] || {};
  ok('사진 바이트가 그대로 저장된다', imRow.type === 'image/png' && Buffer.from(imRow.data || []).equals(pngBuf));
  const c = await send({ text: '틀린 토큰으로 보냄' }, 'not-a-real-token');
  ok('틀린 토큰이면 401 이 아니라 익명으로 받는다', c.status === 200 && c.json.ok === true &&
     (dbRows('SELECT user_id FROM feedback WHERE id=?', c.json.id)[0] || {}).user_id === null, c);
  await wait(400);
  ok('10분 안의 의견은 알림을 더 안 보낸다 (그대로 1번)', feedbackPushes().length === 1, feedbackPushes().length);

  console.log('\n[3-1] 거절 — 400 · 413');
  ok('글 · 사진 둘 다 없음 → 400 {ok:false, error:한국어}', is400(await send({ appVersion: '0.2.17' }, T.token)));
  ok('2001자 → 400', is400(await send({ text: '가'.repeat(2001) }, T.token)));
  ok('사진 4장 → 400', is400(await send({ images: [1, 2, 3, 4].map(() => img('image/png', png())) }, T.token)));
  ok('base64 가 깨짐 → 400', is400(await send({ images: [{ type: 'image/png', data: '!!!!' + png().toString('base64') }] }, T.token)));
  ok('PNG 라면서 JPEG 바이트 → 400', is400(await send({ images: [img('image/png', jpg())] }, T.token)));
  ok('사진 한 장이 1.5MB 넘음 → 400', is400(await send({ images: [img('image/png', png(FB.IMAGE_BYTES_MAX + 10))] }, T.token)));
  ok('platform 이 web → 400', is400(await send({ text: 'x', platform: 'web' }, T.token)));
  ok('JSON 이 아님 → 400', (await call('POST', '/feedback', null, T.token, '{깨짐')).status === 400);
  const huge = await call('POST', '/feedback', null, T.token, JSON.stringify({ text: 'x'.repeat(FB.BODY_LIMIT + 1000) }));
  ok('본문이 상한(6.2MB)을 넘음 → 413 {ok:false}', huge.status === 413 && huge.json.ok === false && !!huge.json.error, huge);
  const three = await send({ text: '큰 사진 세 장', images: [png, jpg, png].map((g, k) =>
    img(k === 1 ? 'image/jpeg' : 'image/png', g(FB.IMAGE_BYTES_MAX - 10))) }, T2.token);
  ok('1.5MB 사진 세 장(본문 약 6MB)은 받는다 — 이 길만 상한을 올림', three.status === 200 && three.json.ok, three);
  ok('다른 길은 그대로 2MB (PATCH /me 에 3MB → 413)',
     (await call('PATCH', '/me', { displayName: 'x', pad: 'x'.repeat(3_000_000) }, T2.token)).status === 413);
  ok('의견을 읽는 HTTP 길은 없다 (GET → 로그인 없으면 401 · 있으면 404)',
     (await call('GET', '/feedback')).status === 401 && (await call('GET', '/feedback', null, O.token)).status === 404);

  console.log('\n[3-2] 하루 20개');
  /* 시험자는 지금까지 1개를 저장했고, 400 으로 거절된 것 여러 개는 세지 않습니다. */
  let lastT = null;
  for (let k = 2; k <= 20; k++) lastT = await send({ text: '의견 ' + k }, T.token);
  ok('로그인: 20번째까지 받는다', lastT && lastT.status === 200, lastT);
  const t21 = await send({ text: '21번째' }, T.token);
  ok('로그인: 21번째 → 429 {ok:false, error}', t21.status === 429 && t21.json.ok === false && /20개/.test(t21.json.error), t21);
  ok('거절된 요청(400)은 한도를 안 깎았다 (저장된 것 정확히 20개)',
     dbRows('SELECT COUNT(*) c FROM feedback WHERE user_id=?', T.user.id)[0].c === 20);
  ok('다른 사람은 막히지 않는다', (await send({ text: '둘째도 보냄' }, T2.token)).status === 200);
  /* 익명은 지금까지 2개(사진만 · 틀린 토큰). 같은 주소(127.0.0.1)입니다. */
  let lastA = null;
  for (let k = 3; k <= 20; k++) lastA = await send({ text: '익명 ' + k });
  ok('익명: 같은 주소에서 20번째까지 받는다', lastA && lastA.status === 200, lastA);
  const a21 = await send({ text: '익명 21번째' }, 'expired-or-wrong');
  ok('익명: 21번째 → 429 (틀린 토큰도 익명으로 셈)', a21.status === 429 && a21.json.ok === false, a21);
  ok('익명이 막혀도 로그인한 사람은 된다', (await send({ text: '주인 시험' }, O.token)).status === 200);
  ok('서버 로그에 의견 내용이 안 남는다 (경로 · 상태만)', /POST\s+\/api\/feedback/.test(out) && !out.includes(MARK) &&
     !out.includes('홈 화면 숫자가'), out.split('\n').filter(l => /feedback/.test(l)).slice(0, 3));

  console.log('\n[3-2b] 동시에 보낸 것도 한도를 못 넘는다 · 받는 중인 것은 한 사람 둘까지');
  const T3 = (await mk('tester3', '셋째'));
  for (let k = 1; k <= 19; k++) await send({ text: '셋째 ' + k }, T3.token);
  /* 둘을 본문 중간에서 멈춰 둡니다 — 둘 다 "오늘 19개" 를 보고 들어간 상태입니다. */
  const s1 = partial({ text: '동시에 하나' }, T3.token), s2 = partial({ text: '동시에 둘' }, T3.token);
  await wait(300);
  const third = await send({ text: '동시에 셋' }, T3.token);
  ok('한 사람이 셋째를 동시에 올리면 503 {ok:false, error} (받는 중인 것은 둘까지)',
     third.status === 503 && third.json.ok === false && /잠시 뒤/.test(third.json.error || ''), third);
  const both = (await Promise.all([s1.finish(), s2.finish()])).map(x => x.status).sort();
  ok('동시에 들어온 둘 중 하나만 저장되고 다른 하나는 429 (앞 검사만 믿지 않음)',
     JSON.stringify(both) === '[200,429]', both);
  ok('그래서 저장된 것은 정확히 20개', dbRows('SELECT COUNT(*) c FROM feedback WHERE user_id=?', T3.user.id)[0].c === 20);
  ok('받는 중인 것이 끝나면 묶음이 풀린다 (다음은 503 이 아니라 한도의 429)',
     (await send({ text: '끝난 뒤' }, T3.token)).status === 429);

  console.log('\n[3-3] 탈퇴하면 의견과 화면도 지워진다');
  const t2ids = dbRows('SELECT id FROM feedback WHERE user_id=?', T2.user.id).map(r => r.id);
  ok('지우기 전: 둘째의 의견 · 화면이 있다', t2ids.length === 2 &&
     dbRows(`SELECT COUNT(*) c FROM feedback_images WHERE feedback_id IN (${t2ids.join(',')})`)[0].c === 3, t2ids);
  const anonBefore = dbRows('SELECT COUNT(*) c FROM feedback WHERE user_id IS NULL')[0].c;
  const del = await call('DELETE', '/me', null, T2.token);
  ok('탈퇴 200', del.status === 200, del);
  ok('탈퇴한 사람의 의견이 안 남는다', dbRows('SELECT COUNT(*) c FROM feedback WHERE user_id=?', T2.user.id)[0].c === 0);
  ok('탈퇴한 사람이 붙인 화면이 안 남는다',
     dbRows(`SELECT COUNT(*) c FROM feedback_images WHERE feedback_id IN (${t2ids.join(',')})`)[0].c === 0);
  ok('익명 의견은 그대로 (계정과 이어져 있지 않음)',
     dbRows('SELECT COUNT(*) c FROM feedback WHERE user_id IS NULL')[0].c === anonBefore);

  console.log('\n[3-4] 1년 지난 것은 서버가 뜰 때 지운다 · 알림 간격이 지나면 다시 울린다');
  const w = new DatabaseSync(DB);
  const ago = d => new Date(Date.now() - d * 86400000).toISOString();
  const oldId = Number(w.prepare('INSERT INTO feedback (created_at, text) VALUES (?, ?)').run(ago(400), '작년 의견').lastInsertRowid);
  w.prepare('INSERT INTO feedback_images (feedback_id, idx, type, data) VALUES (?,?,?,?)').run(oldId, 1, 'image/png', png());
  const keepId = Number(w.prepare('INSERT INTO feedback (created_at, text) VALUES (?, ?)').run(ago(300), '석 달 전').lastInsertRowid);
  w.close();
  await stop();
  srv = boot({ FEEDBACK_NOTIFY_GAP_MS: '1500', BODY_TIMEOUT_MS: '1000' });
  ok('다시 뜬다', await waitUp(), out.slice(-300));
  /* 처음 띄울 때는 주인 계정이 아직 없어서 "계정이 없습니다" 였습니다(그게 맞습니다 —
     그 뒤 가입하면 보낼 때 다시 찾으므로 알림은 갔습니다). 이번에는 있습니다. */
  const bannerLine = () => out.split('\n').find(l => /의견 알림/.test(l)) || '';
  ok('뜰 때 의견 알림이 켜졌다고 말하고, 아이디는 안 찍는다',
     await until(() => /의견 알림 켜짐/.test(bannerLine())) && !/owner/i.test(bannerLine()), bannerLine());
  ok('1년 지난 의견이 지워졌다', await until(() => dbRows('SELECT COUNT(*) c FROM feedback WHERE id=?', oldId)[0].c === 0));
  ok('그 의견의 화면도 지워졌다', dbRows('SELECT COUNT(*) c FROM feedback_images WHERE feedback_id=?', oldId)[0].c === 0);
  ok('1년 안 된 것은 남았다', dbRows('SELECT COUNT(*) c FROM feedback WHERE id=?', keepId)[0].c === 1);
  const n0 = feedbackPushes().length;
  await send({ text: '다시 뜬 뒤 첫 의견' }, O.token);
  ok('다시 뜬 뒤 첫 의견 → 알림', await until(() => feedbackPushes().length === n0 + 1), feedbackPushes().length - n0);
  await send({ text: '바로 다음' }, O.token);
  await wait(400);
  ok('간격 안 → 알림 없음', feedbackPushes().length === n0 + 1, feedbackPushes().length - n0);
  await wait(1300);
  await send({ text: '간격 지난 뒤' }, O.token);
  ok('간격이 지나면 → 다시 알림', await until(() => feedbackPushes().length === n0 + 2), feedbackPushes().length - n0);
  /* 이번 서버는 본문 시간 제한이 1초입니다. 의견은 본문이 세 배라 세 배(3초)를 기다립니다 —
     느린 폰이 올리는 6MB 가 다른 길과 같은 30초에 끊기면 안 됩니다. */
  const lazy = partial({ text: '느리게 올린 의견' });
  await wait(1500);
  const lz = await lazy.finish();
  ok('의견 본문은 다른 길의 세 배까지 기다린다 (1초 제한 서버에서 1.5초 → 200)', lz.status === 200 && lz.json.ok === true, lz);

  await stop();
  srv = boot({ FEEDBACK_NOTIFY: 'nobody-here' });
  ok('없는 아이디로 띄운다 (환경변수가 설정 파일을 이김)', await waitUp());
  ok('뜰 때 "적은 아이디의 계정이 없습니다" 를 말한다',
     await until(() => /의견 알림 ⚠ 설정\(feedbackNotify\)에 적은 아이디의 계정이 없습니다/.test(out)),
     out.split('\n').filter(l => /의견 알림/.test(l)));
  const n1 = feedbackPushes().length;
  const nb = await send({ text: '받을 사람 없음' }, O.token);
  await wait(500);
  ok('알림 받을 사람이 없어도 의견은 받는다 · 알림은 안 간다', nb.status === 200 && feedbackPushes().length === n1, nb);

  console.log('\n[4] GET /api/version 의 참여 링크 (join)');
  const v0 = await call('GET', '/version');
  ok('아무것도 안 적었으면 join 은 {}', v0.status === 200 && JSON.stringify(v0.json.join) === '{}', v0.json);
  const tool = spawnSync(process.execPath, [path.join(ROOT, 'tools', 'app-version.js'),
    '--join-ios=https://testflight.apple.com/join/AbCd1234', '--join-android-group=https://groups.google.com/g/mybody-t'], {
    cwd: ROOT, encoding: 'utf8', timeout: 30000,
    env: Object.assign({}, process.env, { PORT: String(PORT), NODE_NO_WARNINGS: '1' }) });
  const v1 = await call('GET', '/version');
  ok('tools/app-version.js --join-* 로 적으면 다시 띄우지 않아도 나간다', tool.status === 0 &&
     JSON.stringify(v1.json.join) === JSON.stringify({ ios: 'https://testflight.apple.com/join/AbCd1234',
                                                       androidGroup: 'https://groups.google.com/g/mybody-t' }),
     [tool.status, v1.json.join, (tool.stdout || '').slice(-200)]);
  const cfgNow = JSON.parse(fs.readFileSync(path.join(home, 'config.json'), 'utf8'));
  ok('도구가 설정의 다른 값(feedbackNotify)은 건드리지 않는다', cfgNow.feedbackNotify === 'Owner', cfgNow);
  const bad = spawnSync(process.execPath, [path.join(ROOT, 'tools', 'app-version.js'), '--join-android=http://x.example'], {
    cwd: ROOT, encoding: 'utf8', timeout: 30000, env: Object.assign({}, process.env, { PORT: String(PORT) }) });
  ok('https 가 아니면 거절', bad.status === 1 && /https 주소가 아닙니다/.test(bad.stderr + bad.stdout));
  await stop();
}

/* --- [5] 노트북 도구 ------------------------------------------------------- */
function cli() {
  console.log('\n[5] 노트북 도구 tools/feedback.js');
  const home = fs.mkdtempSync(path.join(os.tmpdir(), 'mybody-fbcli-home-'));
  const file = path.join(TMP, 'cli.db');
  const api = DBM.makeApi(DBM.open(file));
  const u = api.signUp({ handle: 'cliperson', password: PW, displayName: '홍길동', healthConsent: DBM.HEALTH_CONSENT_VERSION });
  const pngB = png(300), jpgB = jpg(200);
  const id1 = api.addFeedback(u.user.id, FB.parseFeedback({ text: '첫 줄\n둘째 줄 전체가 나와야 함', appVersion: '0.2.17+310',
                                                            platform: 'ios', screen: '친구' }).value);
  const id2 = api.addFeedback(null, FB.parseFeedback({ images: [img('image/png', pngB), img('image/jpeg', jpgB)],
                                                        platform: 'android', screen: '홈' }).value);
  /* 서버를 거치지 않고 들어간 행(옛 행 · 손으로 넣은 행)도 도구가 걸러 찍는지 봅니다. */
  const raw = new DatabaseSync(file);
  const id3 = Number(raw.prepare('INSERT INTO feedback (created_at, user_id, text) VALUES (?,?,?)')
    .run(new Date().toISOString(), u.user.id, '색\x1b[31m빨강\x1b]0;제목\x07끝').lastInsertRowid);
  raw.close();
  const env = Object.assign({}, process.env, { HOME: home, USERPROFILE: home, DB: file, NODE_NO_WARNINGS: '1' });
  const run = (...args) => {
    const r = spawnSync(process.execPath, [path.join(ROOT, 'tools', 'feedback.js')].concat(args),
                        { cwd: ROOT, encoding: 'utf8', timeout: 30000, env });
    return { code: r.status, out: (r.stdout || '') + (r.stderr || '') };
  };

  const r1 = run();
  ok('기본: 안 읽은 의견 3개를 보여 준다 (exit 0)', r1.code === 0 && /안 읽은 의견 3개/.test(r1.out), r1.out.slice(0, 300));
  ok('새것부터', r1.out.indexOf('#' + id3) < r1.out.indexOf('#' + id2) && r1.out.indexOf('#' + id2) < r1.out.indexOf('#' + id1));
  ok('한국 시각 · 판 · 기종 · 화면 · 사진 수', /\d{4}-\d{2}-\d{2} \d{2}:\d{2} KST · 0\.2\.17\+310 · ios · 친구/.test(r1.out) &&
     /android · 홈 · 익명 · 사진 2장/.test(r1.out), r1.out);
  ok('글을 끝까지 (여러 줄 그대로)', /    첫 줄\n    둘째 줄 전체가 나와야 함/.test(r1.out));
  ok('글 없는 의견은 (글 없음)', /\(글 없음\)/.test(r1.out));
  ok('보낸 사람은 가명 6자 · 익명', r1.out.includes(FB.pseudonym(u.user.id)) && /익명/.test(r1.out));
  ok('아이디 · 이름 · 내부 id 를 안 찍는다', !r1.out.includes('cliperson') && !r1.out.includes('홍길동') &&
     !r1.out.includes(u.user.id));
  ok('제어 문자(ESC · BEL)를 터미널에 안 흘린다', !/[\x1b\x07]/.test(r1.out) && /색\[31m빨강\]0;제목끝/.test(r1.out));
  const dir = path.join(home, '.mybody', 'feedback');
  const f1 = path.join(dir, id2 + '-1.png'), f2 = path.join(dir, id2 + '-2.jpg');
  ok('붙인 화면을 ~/.mybody/feedback/<번호>-<n>.png|jpg 로 꺼낸다', fs.existsSync(f1) && fs.existsSync(f2) &&
     fs.readFileSync(f1).equals(pngB) && fs.readFileSync(f2).equals(jpgB), fs.existsSync(dir) ? fs.readdirSync(dir) : 'no dir');
  if (process.platform !== 'win32') {
    ok('폴더 700 · 파일 600 (몸 숫자가 찍혀 있을 수 있음)', (fs.statSync(dir).mode & 0o777) === 0o700 &&
       (fs.statSync(f1).mode & 0o777) === 0o600, [(fs.statSync(dir).mode & 0o777).toString(8), (fs.statSync(f1).mode & 0o777).toString(8)]);
  }
  ok('다 본 뒤 읽음 표시하는 법을 알려 준다', /--mark-read/.test(r1.out));

  const r2 = run('--mark-read');
  ok('--mark-read: 보여 준 3개를 읽음으로', r2.code === 0 && /읽음으로 표시했습니다: 3개/.test(r2.out), r2.out.slice(-200));
  const r3 = run();
  ok('그 뒤 기본 목록은 비었다', r3.code === 0 && /안 읽은 의견이 없습니다/.test(r3.out), r3.out);
  const r4 = run('--all', '--no-export');
  ok('--all: 읽은 것까지 (읽음) 표시와 함께', r4.code === 0 && /모든 의견 3개/.test(r4.out) && (r4.out.match(/\(읽음\)/g) || []).length === 3, r4.out.slice(0, 300));
  const kstToday = new Date(Date.now() + 9 * 3600e3).toISOString().slice(0, 10);
  const kstTomorrow = new Date(Date.now() + 33 * 3600e3).toISOString().slice(0, 10);
  ok('--since=오늘(한국 날짜) → 3개', /부터 온 의견 3개/.test(run('--since=' + kstToday, '--no-export').out));
  ok('--since=내일 → 없음', /부터 온 의견이 없습니다/.test(run('--since=' + kstTomorrow).out));

  fs.rmSync(dir, { recursive: true, force: true });
  const id4 = api.addFeedback(null, FB.parseFeedback({ images: [img('image/png', png(40))] }).value);
  const r5 = run('--no-export');
  ok('--no-export: 사진을 안 꺼낸다', r5.code === 0 && r5.out.includes('#' + id4) && !fs.existsSync(dir), r5.out);
  const r7 = run('--all');
  const f4 = path.join(dir, id4 + '-1.png');
  ok('--all 은 읽은 의견의 사진도 꺼낸다', r7.code === 0 && fs.existsSync(f1) && fs.existsSync(f2) && fs.existsSync(f4),
     fs.existsSync(dir) ? fs.readdirSync(dir) : 'no dir');
  fs.writeFileSync(path.join(dir, 'memo.txt'), '주인이 둔 파일');
  /* 가장 최근 의견(id4)이 1년이 지나 서버가 지웠다고 칩니다. */
  const w3 = new DatabaseSync(file);
  w3.prepare('UPDATE feedback SET created_at=? WHERE id=?').run(new Date(Date.now() - 400 * 86400000).toISOString(), id4);
  w3.close();
  api.pruneOldFeedback();
  const id5 = api.addFeedback(null, FB.parseFeedback({ images: [img('image/jpeg', jpg(60))] }).value);
  ok('지운 번호를 다시 쓰지 않는다 (가장 큰 번호를 지운 뒤에도 새 번호가 더 큼)', id5 > id4, [id4, id5]);
  const r8 = run('--no-export');
  ok('DB 에서 지워진 의견의 꺼낸 캡처는 다음에 돌릴 때 지운다 (--no-export 여도)', r8.code === 0 &&
     !fs.existsSync(f4) && /캡처 1장을 .* 에서 지웠습니다/.test(r8.out), r8.out.slice(0, 300));
  ok('남아 있는 의견의 캡처 · 주인이 둔 다른 파일은 그대로', fs.existsSync(f1) && fs.existsSync(f2) &&
     fs.existsSync(path.join(dir, 'memo.txt')) && !fs.existsSync(path.join(dir, id5 + '-1.jpg')), fs.readdirSync(dir));
  ok('모르는 깃발 → exit 1', run('--mark-raed').code === 1);
  ok('틀린 날짜 → exit 1', run('--since=2026-13-01').code === 1 && run('--since=20260901').code === 1);
  const missing = path.join(TMP, 'nope', 'none.db');
  const r6 = spawnSync(process.execPath, [path.join(ROOT, 'tools', 'feedback.js')],
    { cwd: ROOT, encoding: 'utf8', env: Object.assign({}, env, { DB: missing }) });
  ok('DB 가 없으면 만들지 않고 exit 1', r6.status === 1 && !fs.existsSync(missing) && /데이터베이스가 없습니다/.test(r6.stderr));
  try { fs.rmSync(home, { recursive: true, force: true }); } catch (e) {}
}

(async () => {
  try {
    unit();
    dbUnit();
    await new Promise(r => hook.listen(HOOK, '127.0.0.1', r));
    await integration();
    cli();
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
