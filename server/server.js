/* =============================================================================
 * server/server.js — Mybody 자가호스팅 서버 (의존성 0, Node 22 내장 기능만)
 *
 *   node server/server.js
 *   PORT=8080 DB=./mybody.db STATIC=../prototype node server/server.js
 *
 * 권한은 전부 서버에서 겁니다. 클라이언트가 보내는 "나는 누구다"를 믿지 않고
 * 토큰으로만 판단합니다.
 * ========================================================================== */
'use strict';
const http = require('node:http');
const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const { open, makeApi } = require('./db.js');
const { runOcr: callOcr } = require('./ocr.js');

const PORT = Number(process.env.PORT || 8080);
const DB_FILE = process.env.DB || path.join(__dirname, 'mybody.db');
const STATIC_DIR = process.env.STATIC
  ? path.resolve(process.env.STATIC)
  : path.join(__dirname, '..', 'prototype');
const ORIGIN = process.env.ORIGIN || '*';

/* 페어링 비밀 — 이 서버에 기기를 등록할 때 쓰는 한 개의 값.
 *
 * 이게 없을 때 /api/auth/signin 은 handle 만으로 세션을 발급했습니다.
 * 남의 handle 을 알면(친구끼리는 대개 압니다) 그 계정으로 그냥 로그인됐습니다.
 * 계정 탈취이고, 체성분 전체와 친구 관계가 통째로 넘어갑니다.
 *
 * 127.0.0.1 바인딩으로 막지 않는 이유: 주인이 "서버는 내 컴퓨터로 사용해"라고
 * 했고, 같은 와이파이의 폰이 못 들어오면 결국 되돌리게 됩니다. */
const PAIR_SECRET = process.env.PAIR_SECRET || '';

/* 2층 판독. 키가 없으면 /api/ocr 은 503 을 돌려주고, 앱은 0층(직접
   입력)으로 조용히 남습니다 — 판독은 편의기능이지 바닥이 아닙니다. */
const ANTHROPIC_KEY = process.env.ANTHROPIC_API_KEY || '';
const OCR_MODEL = process.env.OCR_MODEL || 'claude-opus-5';
const OCR_PER_DAY = Number(process.env.OCR_PER_DAY || 40);

function pairOk(given) {
  const got = Buffer.from(String(given || ''), 'utf8');
  const want = Buffer.from(PAIR_SECRET, 'utf8');
  if (got.length !== want.length) return false;
  return crypto.timingSafeEqual(got, want);   // 길이가 같을 때만 안전하게 비교
}

/** 쿼리 파라미터를 정수로. 못 읽으면 기본값 — 예전엔 SQLite 까지 내려가 HTTP 500 이 났습니다. */
function intParam(v, def, lo, hi) {
  const n = Number.parseInt(v, 10);
  return Number.isFinite(n) ? Math.min(hi, Math.max(lo, n)) : def;
}
/** 본문에서 받은 사용자 id. 문자열이 아니면 거절합니다. */
function idParam(v) {
  return (typeof v === 'string' && /^[\w-]{1,64}$/.test(v)) ? v : null;
}

const db = open(DB_FILE);
const api = makeApi(db);

/* --- 간단한 속도 제한: 인터넷에 열어두면 반드시 필요합니다 ---------------- */
const hits = new Map();
function rateLimited(ip) {
  const now = Date.now();
  const win = 60_000, max = 300;
  const rec = hits.get(ip) || { t: now, n: 0 };
  if (now - rec.t > win) { rec.t = now; rec.n = 0; }
  rec.n++;
  hits.set(ip, rec);
  if (hits.size > 5000) hits.clear();
  return rec.n > max;
}

/* --- 로그인 시도 제한 -------------------------------------------------------
 * 비밀번호 로그인은 무차별 대입의 표적입니다. 일반 속도 제한(분당 300)으로는
 * 턱없이 모자랍니다 — 분당 300번이면 흔한 비밀번호 목록을 하루에 다 돌립니다.
 * 아이디별로 따로 셉니다. IP 별로만 세면 여러 IP 로 한 계정을 때릴 수 있고,
 * 반대로 한 IP 뒤의 여러 사람이 서로를 막게 됩니다. */
/* 사람당 하루 판독 횟수. 사진 한 장이 돈이 드는 요청이라, 버그로
   같은 요청이 반복돼도 청구서가 터지지 않게 막아 둡니다. */
const ocrHits = new Map();
function ocrLimited(userId) {
  const day = new Date().toISOString().slice(0, 10);
  const key = userId + '|' + day;
  const n = (ocrHits.get(key) || 0) + 1;
  ocrHits.set(key, n);
  if (ocrHits.size > 2000) {
    for (const k of ocrHits.keys()) { if (!k.endsWith('|' + day)) ocrHits.delete(k); }
  }
  return n > OCR_PER_DAY;
}

async function runOcr(body) {
  return callOcr(body, { apiKey: ANTHROPIC_KEY, model: OCR_MODEL });
}

const loginFails = new Map();
const LOGIN = { max: 8, windowMs: 15 * 60_000 };

function loginBlocked(handle) {
  const rec = loginFails.get(handle);
  if (!rec) return 0;
  if (Date.now() - rec.t > LOGIN.windowMs) { loginFails.delete(handle); return 0; }
  return rec.n >= LOGIN.max ? Math.ceil((LOGIN.windowMs - (Date.now() - rec.t)) / 60000) : 0;
}
function noteLoginFail(handle) {
  const rec = loginFails.get(handle) || { t: Date.now(), n: 0 };
  if (Date.now() - rec.t > LOGIN.windowMs) { rec.t = Date.now(); rec.n = 0; }
  rec.n++;
  loginFails.set(handle, rec);
  if (loginFails.size > 5000) loginFails.clear();
}
function clearLoginFails(handle) { loginFails.delete(handle); }

const MIME = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8',
               '.css': 'text/css; charset=utf-8', '.json': 'application/json; charset=utf-8',
               '.svg': 'image/svg+xml', '.png': 'image/png', '.ico': 'image/x-icon' };

function send(res, status, body, headers = {}) {
  const h = Object.assign({
    'Access-Control-Allow-Origin': ORIGIN,
    'Access-Control-Allow-Headers': 'content-type, authorization',
    'Access-Control-Allow-Methods': 'GET,POST,PUT,PATCH,DELETE,OPTIONS',
    'Cache-Control': 'no-store',
    'X-Content-Type-Options': 'nosniff'
  }, headers);
  if (typeof body === 'object' && !Buffer.isBuffer(body)) {
    body = JSON.stringify(body);
    h['Content-Type'] = 'application/json; charset=utf-8';
  }
  res.writeHead(status, h);
  res.end(body);
}

/* 본문 읽기.
 *
 * 한도를 넘으면 소켓을 바로 끊지 않습니다. 끊으면 브라우저에는 413 이
 * 아니라 "Failed to fetch" 가 뜨고, 그건 서버가 죽은 것과 구분이 안 됩니다.
 * 대신 남은 데이터를 버리면서 끝까지 받아 주고, 응답으로 413 을 보냅니다.
 * (그래도 무한정 받지는 않습니다 — HARD 를 넘으면 그때는 끊습니다.)
 */
function readBody(req, limit = 2_000_000) {
  const HARD = limit * 4;
  return new Promise((resolve, reject) => {
    let n = 0, over = false; const chunks = [];
    req.on('data', c => {
      n += c.length;
      if (n > HARD) {
        if (!over) { over = true; reject(Object.assign(new Error('본문이 너무 큽니다'), { status: 413 })); }
        req.destroy();
        return;
      }
      if (n > limit) { over = true; chunks.length = 0; return; }
      chunks.push(c);
    });
    req.on('end', () => {
      if (over) return reject(Object.assign(new Error('본문이 너무 큽니다'), { status: 413 }));
      if (!chunks.length) return resolve({});
      try { resolve(JSON.parse(Buffer.concat(chunks).toString('utf8'))); }
      catch { reject(Object.assign(new Error('JSON 형식이 아닙니다'), { status: 400 })); }
    });
    req.on('error', reject);
  });
}

function bearer(req) {
  const a = req.headers.authorization || '';
  return a.startsWith('Bearer ') ? a.slice(7) : null;
}

/* --- 라우팅 --------------------------------------------------------------- */
async function handleApi(req, res, url) {
  const p = url.pathname.replace(/^\/api/, '') || '/';
  const method = req.method;

  if (p === '/health') return send(res, 200, { ok: true, now: new Date().toISOString() });

  /* 계정 만들기 — 페어링 비밀이 필요합니다.
     이 서버는 주인 것이지 공개 가입 서비스가 아닙니다. 비밀을 아는 사람만
     계정을 만들 수 있고, 그 비밀은 주인이 초대하고 싶은 사람에게만 줍니다. */
  if (p === '/auth/signup' && method === 'POST') {
    const b = await readBody(req);
    if (!pairOk(b.pairSecret)) {
      return send(res, 401, { ok: false, reason: '이 서버의 가입 코드가 필요합니다' });
    }
    const r = api.signUp(b);
    return send(res, r.ok ? 200 : 400, r);
  }

  /* 로그인 — 가입 후에는 비밀번호만으로 들어옵니다.
     페어링 비밀을 계속 요구하면 그게 사실상 공용 비밀번호가 되어,
     한 사람만 새도 전원이 뚫립니다. */
  if (p === '/auth/signin' && method === 'POST') {
    const b = await readBody(req);
    const h = String(b.handle || '').trim().toLowerCase();
    if (!h) return send(res, 400, { ok: false, reason: '아이디가 필요합니다' });
    const wait = loginBlocked(h);
    if (wait) {
      return send(res, 429, { ok: false, reason: '로그인 시도가 너무 많습니다. ' + wait + '분 뒤에 다시 해주세요' });
    }
    const r = api.signIn(b);
    if (!r.ok) { noteLoginFail(h); return send(res, 401, r); }
    clearLoginFails(h);
    return send(res, 200, r);
  }

  const tok = bearer(req);
  const user = api.userForToken(tok);
  if (!user) return send(res, 401, { ok: false, reason: '로그인이 필요합니다' });
  const me = user.id;

  if (p === '/auth/signout' && method === 'POST') { api.signOut(tok); return send(res, 200, { ok: true }); }
  if (p === '/auth/signout-all' && method === 'POST') return send(res, 200, api.signOutEverywhere(me));
  if (p === '/auth/password' && method === 'POST') {
    const b = await readBody(req);
    const r = api.changePassword(me, b);
    return send(res, r.ok ? 200 : 400, r);
  }
  if (p === '/me' && method === 'GET') return send(res, 200, { ok: true, user: api.me(me), stats: api.stats(me) });
  if (p === '/me' && method === 'PATCH') return send(res, 200, { ok: true, user: api.updateMe(me, await readBody(req)) });
  if (p === '/me' && method === 'DELETE') { api.deleteMe(me); return send(res, 200, { ok: true }); }

  if (p === '/friends' && method === 'GET') return send(res, 200, { ok: true, friends: api.listFriends(me) });
  if (p === '/friends/request' && method === 'POST') {
    const b = await readBody(req);
    return send(res, 200, api.sendRequest(me, b.inviteCode));
  }
  if (p === '/friends/accept' && method === 'POST') {
    const b = await readBody(req);
    const uid = idParam(b.userId);
    if (!uid) return send(res, 400, { ok: false, reason: 'userId 가 필요합니다' });
    return send(res, 200, api.accept(me, uid));
  }
  if (p === '/friends/decline' && method === 'POST') {
    const b = await readBody(req);
    const uid = idParam(b.userId);
    if (!uid) return send(res, 400, { ok: false, reason: 'userId 가 필요합니다' });
    return send(res, 200, api.decline(me, uid));
  }
  if (p === '/friends/block' && method === 'POST') {
    const b = await readBody(req);
    const uid = idParam(b.userId);
    if (!uid) return send(res, 400, { ok: false, reason: 'userId 가 필요합니다' });
    return send(res, 200, api.block(me, uid));
  }
  if (p === '/friends/unblock' && method === 'POST') {
    const b = await readBody(req);
    const uid = idParam(b.userId);
    if (!uid) return send(res, 400, { ok: false, reason: 'userId 가 필요합니다' });
    return send(res, 200, api.unblock(me, uid));
  }
  let m = p.match(/^\/friends\/([\w-]+)$/);
  if (m && method === 'DELETE') return send(res, 200, api.removeFriend(me, m[1]));

  m = p.match(/^\/share\/([\w-]+)$/);
  if (m && method === 'GET') return send(res, 200, { ok: true, share: api.shareFields(me, m[1]) });
  if (m && method === 'PUT') {
    const b = await readBody(req); return send(res, 200, api.setShare(me, m[1], b || {}));
  }

  if (p === '/snapshots' && method === 'POST') {
    const b = await readBody(req);
    if (!b.weekStart) return send(res, 400, { ok: false, reason: 'weekStart 가 필요합니다' });
    return send(res, 200, api.publishSnapshot(me, b.weekStart, b.payload));
  }
  m = p.match(/^\/snapshots\/([\w-]+)$/);
  if (m && method === 'GET') {
    return send(res, 200, api.friendSnapshots(me, m[1], intParam(url.searchParams.get('limit'), 26, 1, 200)));
  }

  if (p === '/sync/push' && method === 'POST') {
    const b = await readBody(req); return send(res, 200, api.push(me, b.records));
  }
  if (p === '/sync/pull' && method === 'GET') {
    return send(res, 200, api.pull(me, url.searchParams.get('since') || '',
                                   intParam(url.searchParams.get('limit'), 500, 1, 2000)));
  }

  /* 2층 — 결과지 사진 판독 프록시.
   *
   * 왜 프록시인가: API 키를 정적 클라이언트에 넣을 수 없습니다. 키는
   * 이 서버의 환경변수에만 있고, 브라우저는 자기 계정 토큰으로만
   * 이 경로를 부릅니다.
   *
   * 사진 본문은 다른 요청보다 큽니다(base64 가 4/3 배). 그래서 한도를
   * 따로 줍니다. photo.js 가 이미 900KB 아래로 줄여서 보냅니다.
   */
  if (p === '/ocr' && method === 'POST') {
    if (!ANTHROPIC_KEY) {
      return send(res, 503, { ok: false, reason: '이 서버에는 판독 키가 설정되지 않았습니다' });
    }
    if (ocrLimited(me)) {
      return send(res, 429, { ok: false, reason: '판독 요청이 너무 잦습니다. 잠시 뒤에 다시 해 주세요' });
    }
    const b = await readBody(req, 8_000_000);
    const out = await runOcr(b);
    return send(res, out.status, out.body);
  }

  return send(res, 404, { ok: false, reason: '그런 경로가 없습니다' });
}

function serveStatic(req, res, url) {
  let rel = decodeURIComponent(url.pathname);
  if (rel === '/') rel = '/index.html';
  const file = path.join(STATIC_DIR, rel);
  if (!file.startsWith(STATIC_DIR) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) {
    return send(res, 404, 'not found', { 'Content-Type': 'text/plain; charset=utf-8' });
  }
  send(res, 200, fs.readFileSync(file),
       { 'Content-Type': MIME[path.extname(file)] || 'application/octet-stream' });
}

const server = http.createServer(async (req, res) => {
  const ip = req.socket.remoteAddress || 'unknown';
  if (rateLimited(ip)) return send(res, 429, { ok: false, reason: '요청이 너무 많습니다' });
  if (req.method === 'OPTIONS') return send(res, 204, '');
  const url = new URL(req.url, 'http://localhost');
  try {
    if (url.pathname === '/health' || url.pathname.startsWith('/api/')) return await handleApi(req, res, url);
    serveStatic(req, res, url);
  } catch (e) {
    // 예전엔 SQLite 드라이버 원문이 그대로 나갔습니다 ("Provided value cannot be
    // bound to SQLite parameter 1"). 내부 구조를 밖에 알려줄 이유가 없습니다.
    if (e && e.status) return send(res, e.status, { ok: false, reason: e.message || '요청 오류' });
    console.error('[500]', e && e.stack || e);
    send(res, 500, { ok: false, reason: '서버 오류' });
  }
});

if (require.main === module) {
  if (!PAIR_SECRET) {
    console.error('PAIR_SECRET 없이는 시작하지 않습니다.');
    console.error('');
    console.error('  아무나 로그인할 수 있는 서버가 되기 때문입니다.');
    console.error('  아래처럼 값을 하나 정해서 넘기고, 같은 값을 내 기기에만 알려주세요:');
    console.error('');
    console.error('    PAIR_SECRET=$(openssl rand -hex 16) node server/server.js');
    console.error('');
    process.exit(1);
  }
  server.listen(PORT, () => {
    console.log('Mybody 서버 실행 중');
    console.log('  주소   http://localhost:' + PORT);
    console.log('  DB     ' + DB_FILE);
    console.log('  정적   ' + STATIC_DIR);
    console.log('');
    // cloudflared 안내는 뺐습니다. 집 안 서버를 공개 서버로 바꾸는 두 줄이었고,
    // 그 상태에서 인증 구멍이 있으면 피해가 바로 현실이 됩니다.
    console.log('  밖에서 접속하려면 먼저 server/README.md 의 "밖에서 접속하기"를 읽어 주세요.');
  });
}

module.exports = { server, api, db };
