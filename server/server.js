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
const fs = require('node:fs');
const path = require('node:path');
const { open, makeApi } = require('./db.js');

const PORT = Number(process.env.PORT || 8080);
const DB_FILE = process.env.DB || path.join(__dirname, 'mybody.db');
const STATIC_DIR = process.env.STATIC
  ? path.resolve(process.env.STATIC)
  : path.join(__dirname, '..', 'prototype');
const ORIGIN = process.env.ORIGIN || '*';

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

function readBody(req) {
  return new Promise((resolve, reject) => {
    let n = 0; const chunks = [];
    req.on('data', c => {
      n += c.length;
      if (n > 2_000_000) { reject(Object.assign(new Error('본문이 너무 큽니다'), { status: 413 })); req.destroy(); return; }
      chunks.push(c);
    });
    req.on('end', () => {
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

  if (p === '/auth/signin' && method === 'POST') {
    const b = await readBody(req);
    if (!b.handle) return send(res, 400, { ok: false, reason: 'handle 이 필요합니다' });
    return send(res, 200, Object.assign({ ok: true }, api.signIn(b)));
  }

  const tok = bearer(req);
  const user = api.userForToken(tok);
  if (!user) return send(res, 401, { ok: false, reason: '로그인이 필요합니다' });
  const me = user.id;

  if (p === '/auth/signout' && method === 'POST') { api.signOut(tok); return send(res, 200, { ok: true }); }
  if (p === '/me' && method === 'GET') return send(res, 200, { ok: true, user: api.me(me), stats: api.stats(me) });
  if (p === '/me' && method === 'PATCH') return send(res, 200, { ok: true, user: api.updateMe(me, await readBody(req)) });
  if (p === '/me' && method === 'DELETE') { api.deleteMe(me); return send(res, 200, { ok: true }); }

  if (p === '/friends' && method === 'GET') return send(res, 200, { ok: true, friends: api.listFriends(me) });
  if (p === '/friends/request' && method === 'POST') {
    const b = await readBody(req);
    return send(res, 200, api.sendRequest(me, b.inviteCode));
  }
  if (p === '/friends/accept' && method === 'POST') {
    const b = await readBody(req); return send(res, 200, api.accept(me, b.userId));
  }
  if (p === '/friends/decline' && method === 'POST') {
    const b = await readBody(req); return send(res, 200, api.decline(me, b.userId));
  }
  if (p === '/friends/block' && method === 'POST') {
    const b = await readBody(req); return send(res, 200, api.block(me, b.userId));
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
    return send(res, 200, api.friendSnapshots(me, m[1], Number(url.searchParams.get('limit') || 26)));
  }

  if (p === '/sync/push' && method === 'POST') {
    const b = await readBody(req); return send(res, 200, api.push(me, b.records));
  }
  if (p === '/sync/pull' && method === 'GET') {
    return send(res, 200, api.pull(me, url.searchParams.get('since') || '',
                                   Number(url.searchParams.get('limit') || 500)));
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
    send(res, e.status || 500, { ok: false, reason: e.message || '서버 오류' });
  }
});

if (require.main === module) {
  server.listen(PORT, () => {
    console.log('Mybody 서버 실행 중');
    console.log('  주소   http://localhost:' + PORT);
    console.log('  DB     ' + DB_FILE);
    console.log('  정적   ' + STATIC_DIR);
    console.log('');
    console.log('밖에서 접속하려면 (포트포워딩 없이):');
    console.log('  cloudflared tunnel --url http://localhost:' + PORT);
  });
}

module.exports = { server, api, db };
