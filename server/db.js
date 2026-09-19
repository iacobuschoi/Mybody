/* =============================================================================
 * server/db.js — 스키마와 질의. Node 22 내장 SQLite 만 씁니다 (설치할 것 없음).
 *
 * 권한은 전부 여기와 server.js 에서 겁니다. 클라이언트를 믿지 않습니다.
 * ========================================================================== */
'use strict';
const { DatabaseSync } = require('node:sqlite');
const crypto = require('node:crypto');
const path = require('node:path');
const fs = require('node:fs');

const SHARE_FIELDS = ['weightTrend', 'smmTrend', 'bfmTrend', 'planProgress', 'streak', 'absolute'];

function open(file) {
  const dir = path.dirname(file);
  if (dir && dir !== '.' && !fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
  const db = new DatabaseSync(file);
  db.exec('PRAGMA journal_mode = WAL');
  db.exec('PRAGMA foreign_keys = ON');
  db.exec(`
    CREATE TABLE IF NOT EXISTS users (
      id TEXT PRIMARY KEY,
      handle TEXT UNIQUE NOT NULL,
      provider TEXT NOT NULL,
      display_name TEXT NOT NULL,
      invite_code TEXT UNIQUE NOT NULL,
      created_at TEXT NOT NULL,
      -- 비밀번호는 scrypt 해시로만 저장합니다. 원문은 어디에도 남지 않습니다.
      pw_hash TEXT,
      pw_salt TEXT,
      pw_n INTEGER
    );
    CREATE TABLE IF NOT EXISTS sessions (
      token TEXT PRIMARY KEY,
      user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      created_at TEXT NOT NULL,
      last_seen TEXT NOT NULL,
      -- 세션에 만료를 둡니다. 예전엔 무기한이라 한 번 샌 토큰이 영원히 살았습니다.
      expires_at TEXT
    );
    CREATE TABLE IF NOT EXISTS friendships (
      a_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      b_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      status TEXT NOT NULL,
      requested_by TEXT NOT NULL,
      blocked_by TEXT,
      created_at TEXT NOT NULL,
      responded_at TEXT,
      PRIMARY KEY (a_id, b_id)
    );
    CREATE TABLE IF NOT EXISTS shares (
      owner_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      viewer_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      fields TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      PRIMARY KEY (owner_id, viewer_id)
    );
    CREATE TABLE IF NOT EXISTS snapshots (
      owner_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      week_start TEXT NOT NULL,
      payload TEXT NOT NULL,
      computed_at TEXT NOT NULL,
      PRIMARY KEY (owner_id, week_start)
    );
    CREATE TABLE IF NOT EXISTS records (
      user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      kind TEXT NOT NULL,
      id TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      deleted INTEGER NOT NULL DEFAULT 0,
      payload TEXT NOT NULL,
      PRIMARY KEY (user_id, kind, id)
    );
    CREATE INDEX IF NOT EXISTS idx_records_sync ON records(user_id, updated_at, kind, id);
    CREATE INDEX IF NOT EXISTS idx_snapshots_owner ON snapshots(owner_id, week_start DESC);
  `);
  /* 이미 만들어진 DB 에 컬럼을 더합니다. ALTER 가 실패하면 이미 있다는 뜻입니다. */
  for (const stmt of ['ALTER TABLE users ADD COLUMN pw_hash TEXT',
                      'ALTER TABLE users ADD COLUMN pw_salt TEXT',
                      'ALTER TABLE users ADD COLUMN pw_n INTEGER',
                      'ALTER TABLE sessions ADD COLUMN expires_at TEXT']) {
    try { db.exec(stmt); } catch { /* 이미 있음 */ }
  }

  /* 만료 컬럼이 생기기 전에 발급된 세션은 expires_at 이 NULL 입니다.
     userForToken 의 검사가 `s.expires_at && ...` 이라 NULL 은 통째로
     건너뛰었고, 그 토큰들은 영원히 살았습니다 — 하필 가장 오래된,
     그래서 샜을 가능성이 제일 높은 것들입니다. 만료를 붙인 이유가
     정확히 그건데 그 대상만 빠져 있었습니다.
     만든 날에서 90일로 채웁니다. 만든 날도 없으면 이미 만료로 봅니다 —
     정체를 알 수 없는 토큰을 살려 둘 이유가 없습니다. */
  try {
    db.exec(`UPDATE sessions
                SET expires_at = COALESCE(
                      datetime(created_at, '+90 days'),
                      '1970-01-01T00:00:00.000Z')
              WHERE expires_at IS NULL`);
  } catch { /* 빈 DB 등 */ }

  return db;
}

/* ---------------------------------------------------------------------------
 * 비밀번호 — scrypt (node:crypto 내장). 의존성 0 을 유지합니다.
 * ------------------------------------------------------------------------- */
const SCRYPT_N = 16384, SCRYPT_r = 8, SCRYPT_p = 1, KEYLEN = 64;

function hashPassword(plain, saltHex, n) {
  const salt = saltHex ? Buffer.from(saltHex, 'hex') : crypto.randomBytes(16);
  const cost = n || SCRYPT_N;
  const key = crypto.scryptSync(str(plain), salt, KEYLEN,
                                { N: cost, r: SCRYPT_r, p: SCRYPT_p, maxmem: 256 * 1024 * 1024 });
  return { hash: key.toString('hex'), salt: salt.toString('hex'), n: cost };
}

/** 길이가 달라도 타이밍이 새지 않게 비교합니다. */
function verifyPassword(plain, user) {
  if (!user || !user.pw_hash || !user.pw_salt) return false;
  const got = hashPassword(plain, user.pw_salt, user.pw_n || SCRYPT_N).hash;
  const a = Buffer.from(got, 'hex'), b = Buffer.from(user.pw_hash, 'hex');
  if (a.length !== b.length) return false;
  return crypto.timingSafeEqual(a, b);
}

/** 비밀번호 정책. 짧은 것만 막습니다 — 복잡도 규칙은 실제로 더 나쁜 비밀번호를 만듭니다. */
function passwordProblem(plain) {
  const s = str(plain);
  if (s.length < 8) return '비밀번호는 8자 이상이어야 합니다';
  if (s.length > 200) return '비밀번호가 너무 깁니다';
  if (/^\d+$/.test(s)) return '숫자만으로는 안 됩니다';
  return null;
}

const SESSION_DAYS = 90;

/* 바깥에서 온 값을 문자열로.
 *
 * String(x) 는 던질 수 있습니다. { toString: 1 } 을 넣으면
 * "Cannot convert object to primitive value" 가 나고, 라우트가
 * 500 을 돌려줍니다. 500 은 "서버가 예상 못 한 일" 이라는 뜻이라
 * 로그에 스택이 쌓이고, 클라이언트가 잘못 보낸 것과 서버가 망가진
 * 것을 구분할 수 없게 됩니다.
 *
 * 애초에 문자열과 숫자만 받습니다. 그 밖은 '' 입니다 — 객체를
 * 문자열로 바꿔서 쓸 일이 이 서버에는 없습니다. */
function str(x) {
  if (typeof x === 'string') return x;
  if (typeof x === 'number' && Number.isFinite(x)) return String(x);
  if (typeof x === 'boolean') return String(x);
  return '';
}

function nowISO() { return new Date().toISOString(); }
function id(prefix) { return prefix + '_' + crypto.randomBytes(9).toString('hex'); }
function token() { return crypto.randomBytes(32).toString('hex'); }
function inviteCode() {
  const A = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  let s = '';
  const buf = crypto.randomBytes(8);
  for (let i = 0; i < 8; i++) s += A[buf[i] % A.length];
  return s;
}
function pair(a, b) { return a < b ? [a, b] : [b, a]; }
function blankShare() {
  // 친구가 되어도 몸에 대한 정보는 기본으로 아무것도 안 나갑니다.
  // 체크인 여부만 켜 둡니다 — 이건 몸이 아니라 행동에 대한 정보입니다.
  return { weightTrend: false, smmTrend: false, bfmTrend: false,
           planProgress: false, streak: true, absolute: false };
}

function makeApi(db) {
  const q = {
    userByHandle: db.prepare('SELECT * FROM users WHERE handle = ?'),
    userById: db.prepare('SELECT * FROM users WHERE id = ?'),
    userByCode: db.prepare('SELECT * FROM users WHERE invite_code = ?'),
    insertUser: db.prepare(
      'INSERT INTO users (id, handle, provider, display_name, invite_code, created_at) VALUES (?,?,?,?,?,?)'),
    updateName: db.prepare('UPDATE users SET display_name = ? WHERE id = ?'),
    deleteUser: db.prepare('DELETE FROM users WHERE id = ?'),

    insertSession: db.prepare('INSERT INTO sessions (token, user_id, created_at, last_seen, expires_at) VALUES (?,?,?,?,?)'),
    deleteSessionsOf: db.prepare('DELETE FROM sessions WHERE user_id = ?'),
    setPassword: db.prepare('UPDATE users SET pw_hash=?, pw_salt=?, pw_n=? WHERE id=?'),
    sessionByToken: db.prepare('SELECT * FROM sessions WHERE token = ?'),
    touchSession: db.prepare('UPDATE sessions SET last_seen = ? WHERE token = ?'),
    deleteSession: db.prepare('DELETE FROM sessions WHERE token = ?'),

    edge: db.prepare('SELECT * FROM friendships WHERE a_id = ? AND b_id = ?'),
    insertEdge: db.prepare(
      'INSERT INTO friendships (a_id,b_id,status,requested_by,created_at) VALUES (?,?,?,?,?)'),
    setEdgeStatus: db.prepare('UPDATE friendships SET status=?, responded_at=? WHERE a_id=? AND b_id=?'),
    setEdgeBlocked: db.prepare('UPDATE friendships SET status=?, blocked_by=?, responded_at=? WHERE a_id=? AND b_id=?'),
    deleteEdge: db.prepare('DELETE FROM friendships WHERE a_id=? AND b_id=?'),
    edgesOf: db.prepare('SELECT * FROM friendships WHERE a_id = ? OR b_id = ?'),

    getShare: db.prepare('SELECT * FROM shares WHERE owner_id=? AND viewer_id=?'),
    upsertShare: db.prepare(
      'INSERT INTO shares (owner_id,viewer_id,fields,updated_at) VALUES (?,?,?,?) ' +
      'ON CONFLICT(owner_id,viewer_id) DO UPDATE SET fields=excluded.fields, updated_at=excluded.updated_at'),
    deleteShare: db.prepare('DELETE FROM shares WHERE owner_id=? AND viewer_id=?'),

    upsertSnap: db.prepare(
      'INSERT INTO snapshots (owner_id,week_start,payload,computed_at) VALUES (?,?,?,?) ' +
      'ON CONFLICT(owner_id,week_start) DO UPDATE SET payload=excluded.payload, computed_at=excluded.computed_at'),
    snapsOf: db.prepare('SELECT * FROM snapshots WHERE owner_id=? ORDER BY week_start DESC LIMIT ?'),

    upsertRecord: db.prepare(
      'INSERT INTO records (user_id,kind,id,updated_at,deleted,payload) VALUES (?,?,?,?,?,?) ' +
      'ON CONFLICT(user_id,kind,id) DO UPDATE SET updated_at=excluded.updated_at, ' +
      'deleted=excluded.deleted, payload=excluded.payload WHERE excluded.updated_at >= records.updated_at'),
    // 커서는 (updated_at, kind, id) 복합입니다. updated_at 단독으로 비교하면
    // 같은 타임스탬프를 가진 형제 행들이 커서를 넘기는 순간 영구히 건너뛰어집니다.
    // (기본키가 (user_id, kind, id) 라서 같은 id 가 kind 마다 존재할 수 있습니다)
    recordsSince: db.prepare(
      'SELECT * FROM records WHERE user_id=? AND (updated_at, kind, id) > (?,?,?) ' +
      'ORDER BY updated_at, kind, id LIMIT ?'),
    countRecords: db.prepare('SELECT COUNT(*) c FROM records WHERE user_id=?')
  };

  function pub(u) {
    return u && { id: u.id, displayName: u.display_name, provider: u.provider,
                  inviteCode: u.invite_code, createdAt: u.created_at };
  }

  return {
    SHARE_FIELDS, blankShare,

    /* --- 계정 만들기 -------------------------------------------------
     * 카카오·애플 같은 외부 제공자를 쓰지 않습니다. 이 서버가 직접 계정을
     * 관리합니다. 외부 OAuth 는 사업자 등록과 앱 심사가 필요하고,
     * 자가호스팅이라는 이 앱의 전제와도 맞지 않습니다.
     *
     * 아이디는 이메일이 아니라 임의 문자열입니다 — 이메일을 받으면
     * 보관해야 하는 개인정보가 하나 늘어나는데, 이 서버는 비밀번호 재발송을
     * 하지 않으므로 이메일이 할 일이 없습니다.
     * ----------------------------------------------------------------- */
    signUp({ handle, password, displayName }) {
      const h = str(handle).trim().toLowerCase();
      if (!/^[a-z0-9_.-]{3,32}$/.test(h)) {
        return { ok: false, reason: '아이디는 영문·숫자·(_ . -) 3~32자입니다' };
      }
      const pwBad = passwordProblem(password);
      if (pwBad) return { ok: false, reason: pwBad };
      if (q.userByHandle.get(h)) return { ok: false, reason: '이미 있는 아이디입니다' };

      const pw = hashPassword(password);
      const uid = id('user');
      q.insertUser.run(uid, h, 'local', (displayName || h).slice(0, 20), inviteCode(), nowISO());
      q.setPassword.run(pw.hash, pw.salt, pw.n, uid);
      const u = q.userById.get(uid);
      return Object.assign({ ok: true }, this._newSession(u));
    },

    signIn({ handle, password }) {
      const h = String(handle || '').trim().toLowerCase();
      const u = q.userByHandle.get(h);
      /* 아이디가 없을 때도 해시 계산을 한 번 돌립니다. 안 그러면 응답 시간만으로
         "이 아이디가 존재하는가"를 알아낼 수 있습니다. */
      if (!u) { hashPassword(str(password), null, SCRYPT_N); }
      if (!u || !verifyPassword(password, u)) {
        // 어느 쪽이 틀렸는지 알려주지 않습니다
        return { ok: false, reason: '아이디 또는 비밀번호가 맞지 않습니다' };
      }
      return Object.assign({ ok: true }, this._newSession(u));
    },

    changePassword(uid, { current, next }) {
      const u = q.userById.get(uid);
      if (!u) return { ok: false, reason: '없는 계정입니다' };
      if (!verifyPassword(current, u)) return { ok: false, reason: '지금 비밀번호가 맞지 않습니다' };
      const bad = passwordProblem(next);
      if (bad) return { ok: false, reason: bad };
      const pw = hashPassword(next);
      q.setPassword.run(pw.hash, pw.salt, pw.n, uid);
      // 비밀번호를 바꾸면 다른 기기의 세션을 전부 끊습니다
      q.deleteSessionsOf.run(uid);
      const fresh = q.userById.get(uid);
      return Object.assign({ ok: true }, this._newSession(fresh));
    },

    /** 모든 기기에서 로그아웃 — 토큰이 샜을 때의 유일한 복구 수단입니다. */
    signOutEverywhere(uid) {
      q.deleteSessionsOf.run(uid);
      return { ok: true };
    },

    _newSession(u) {
      const t = token();
      const now = new Date();
      const exp = new Date(now.getTime() + SESSION_DAYS * 86400000);
      q.insertSession.run(t, u.id, now.toISOString(), now.toISOString(), exp.toISOString());
      return { token: t, user: pub(u) };
    },
    signOut(t) { q.deleteSession.run(t); },
    userForToken(t) {
      if (!t) return null;
      const s = q.sessionByToken.get(t);
      if (!s) return null;
      /* 만료된 세션은 그 자리에서 지웁니다.
         expires_at 이 없는 세션도 만료로 봅니다. 마이그레이션이 채워
         주지만, 그 사이에 들어온 요청이나 손으로 만든 행이 있을 수
         있습니다. 모르는 토큰을 살려 두는 쪽이 항상 더 위험합니다. */
      if (!s.expires_at || s.expires_at < nowISO()) { q.deleteSession.run(t); return null; }
      q.touchSession.run(nowISO(), t);
      return q.userById.get(s.user_id) || null;
    },
    me(uid) { return pub(q.userById.get(uid)); },
    updateMe(uid, { displayName }) {
      if (displayName) {
        const dn = str(displayName).slice(0, 20);
        if (dn) q.updateName.run(dn, uid);
      }
      return pub(q.userById.get(uid));
    },
    deleteMe(uid) { q.deleteUser.run(uid); },      // 연쇄 삭제로 친구·공유·스냅샷·기록 전부 사라짐

    areFriends(a, b) {
      const [x, y] = pair(a, b);
      const e = q.edge.get(x, y);
      return !!(e && e.status === 'accepted');
    },

    sendRequest(me, code) {
      if (!this.exists(me)) return { ok: false, reason: '없는 계정입니다' };
      const other = q.userByCode.get(str(code).toUpperCase());
      if (!other) return { ok: false, reason: '그런 코드를 가진 사람이 없습니다' };
      if (other.id === me) return { ok: false, reason: '자기 자신은 추가할 수 없습니다' };
      const [x, y] = pair(me, other.id);
      const e = q.edge.get(x, y);
      if (e) {
        if (e.status === 'blocked') return { ok: false, reason: '요청할 수 없는 상대입니다' };
        if (e.status === 'accepted') return { ok: false, reason: '이미 친구입니다' };
        if (e.requested_by === me) return { ok: false, reason: '이미 보낸 요청입니다' };
        return this.accept(me, other.id);
      }
      q.insertEdge.run(x, y, 'pending', me, nowISO());
      return { ok: true, status: 'pending' };
    },
    accept(me, otherId) {
      const [x, y] = pair(me, otherId);
      const e = q.edge.get(x, y);
      if (!e || e.status !== 'pending') return { ok: false, reason: '받은 요청이 없습니다' };
      if (e.requested_by === me) return { ok: false, reason: '내가 보낸 요청은 내가 수락할 수 없습니다' };
      q.setEdgeStatus.run('accepted', nowISO(), x, y);
      const t = nowISO();
      q.upsertShare.run(me, otherId, JSON.stringify(blankShare()), t);
      q.upsertShare.run(otherId, me, JSON.stringify(blankShare()), t);
      return { ok: true, status: 'accepted' };
    },
    decline(me, otherId) {
      const [x, y] = pair(me, otherId);
      const e = q.edge.get(x, y);
      if (!e || e.status !== 'pending') return { ok: false, reason: '받은 요청이 없습니다' };
      q.deleteEdge.run(x, y);
      return { ok: true };
    },
    removeFriend(me, otherId) {
      const [x, y] = pair(me, otherId);
      const e = q.edge.get(x, y);
      if (!e) return { ok: false, reason: '친구가 아닙니다' };
      // 차단당한 사람이 "친구 끊기"로 자기를 막고 있는 행을 지울 수 있었습니다.
      // 차단은 차단한 사람만 풀 수 있습니다.
      if (e.status === 'blocked' && e.blocked_by !== me)
        return { ok: false, reason: '친구가 아닙니다' };
      if (e.status === 'pending' && e.requested_by !== me)
        return { ok: false, reason: '받은 요청은 거절로 처리합니다' };
      q.deleteEdge.run(x, y);
      q.deleteShare.run(me, otherId);
      q.deleteShare.run(otherId, me);
      return { ok: true };
    },
    block(me, otherId) {
      if (!this.exists(me) || !this.exists(otherId)) return { ok: false, reason: '없는 계정입니다' };
      if (me === otherId) return { ok: false, reason: '자기 자신은 차단할 수 없습니다' };
      const [x, y] = pair(me, otherId);
      const e = q.edge.get(x, y);
      // 맞차단으로 남의 차단을 자기 것으로 덮어쓰면, 그걸 풀어서 관계를 되살릴 수 있습니다.
      if (e && e.status === 'blocked' && e.blocked_by !== me)
        return { ok: false, reason: '요청할 수 없는 상대입니다' };
      if (!e) q.insertEdge.run(x, y, 'blocked', me, nowISO());
      q.setEdgeBlocked.run('blocked', me, nowISO(), x, y);
      q.deleteShare.run(me, otherId);
      q.deleteShare.run(otherId, me);
      return { ok: true };
    },
    /** 차단 해제. 차단한 본인만. 이게 없으면 차단한 사람이 영원히 지울 수 없는 행에 묶입니다. */
    unblock(me, otherId) {
      const [x, y] = pair(me, otherId);
      const e = q.edge.get(x, y);
      if (!e || e.status !== 'blocked') return { ok: false, reason: '차단하지 않은 상대입니다' };
      if (e.blocked_by !== me) return { ok: false, reason: '내가 차단한 상대가 아닙니다' };
      q.deleteEdge.run(x, y);
      return { ok: true };
    },
    listFriends(me) {
      if (!this.exists(me)) return { accepted: [], incoming: [], outgoing: [], blocked: [] };
      const out = { accepted: [], incoming: [], outgoing: [], blocked: [] };
      for (const e of q.edgesOf.all(me, me)) {
        const otherId = e.a_id === me ? e.b_id : e.a_id;
        const u = q.userById.get(otherId);
        if (!u) continue;
        const row = { id: otherId, displayName: u.display_name,
                      since: e.responded_at || e.created_at };
        if (e.status === 'accepted') {
          row.iShare = this.shareSummary(me, otherId);
          row.theyShare = this.shareSummary(otherId, me);
          out.accepted.push(row);
        } else if (e.status === 'pending') {
          (e.requested_by === me ? out.outgoing : out.incoming).push(row);
        } else if (e.status === 'blocked' && e.blocked_by === me) {
          out.blocked.push(row);
        }
      }
      return out;
    },

    shareFields(owner, viewer) {
      const r = q.getShare.get(owner, viewer);
      if (!r) return blankShare();
      try { return Object.assign(blankShare(), JSON.parse(r.fields)); }
      catch { return blankShare(); }
    },
    shareSummary(owner, viewer) {
      const s = this.shareFields(owner, viewer);
      const LABEL = { weightTrend: '체중 변화', smmTrend: '골격근 변화', bfmTrend: '체지방 변화',
                      planProgress: '목표 달성률', streak: '체크인 기록', absolute: '실제 수치까지' };
      const on = SHARE_FIELDS.filter(k => s[k]);
      return { count: on.length, labels: on.map(k => LABEL[k]), settings: s };
    },
    setShare(me, viewerId, patch) {
      if (!this.exists(me) || !this.exists(viewerId)) return { ok: false, reason: '없는 계정입니다' };
      if (!this.areFriends(me, viewerId)) return { ok: false, reason: '친구가 아닙니다' };
      const cur = this.shareFields(me, viewerId);
      // !! 강제변환이면 문자열 "false" 가 true 가 됩니다. 이 앱에서 가장 민감한
      // 스위치가 한쪽 방향으로만(= 더 열리는 쪽으로만) 실패하던 자리입니다.
      for (const k of SHARE_FIELDS) {
        if (!(k in patch)) continue;
        if (typeof patch[k] !== 'boolean')
          return { ok: false, reason: '공유 설정은 true/false 여야 합니다' };
        cur[k] = patch[k];
      }
      if (cur.absolute && !cur.weightTrend && !cur.smmTrend && !cur.bfmTrend) cur.absolute = false;
      q.upsertShare.run(me, viewerId, JSON.stringify(cur), nowISO());
      return { ok: true, share: cur };
    },

    exists(uid) { return !!(uid && q.userById.get(uid)); },

    publishSnapshot(me, weekStart, payload) {
      if (!this.exists(me)) return { ok: false, reason: '없는 계정입니다' };
      if (!weekStart) return { ok: false, reason: 'weekStart 가 필요합니다' };
      /* weekStart 를 검사하지 않고 String() 으로 감쌌습니다.
         객체를 보내면 '[object Object]' 라는 주가 생기고, 아무 문자열이나
         보내면 그때마다 새 행이 하나씩 늘어납니다 — 주당 한 행이라는
         전제가 깨지고 행 수에 상한이 없어집니다.
         주 시작일은 YYYY-MM-DD 하나뿐입니다. */
      const wk = str(weekStart);
      if (!/^\d{4}-\d{2}-\d{2}$/.test(wk) || !Number.isFinite(Date.parse(wk + 'T00:00:00Z'))) {
        return { ok: false, reason: 'weekStart 는 YYYY-MM-DD 형식이어야 합니다' };
      }
      /* 범위는 아주 넓게 둡니다.
         처음엔 "10년 전 ~ 1주 뒤" 로 좁혔는데, 그러면 기기 시계가 하루
         앞선 사용자의 기록이 거부됩니다. 시계가 틀린 건 사용자 잘못이
         아니고, 그걸로 기록을 막으면 원인도 안 보입니다.
         행이 무한정 늘어나는 것을 막는 것은 위의 형식 검사입니다 —
         YYYY-MM-DD 하나당 한 행이고 1900~2200 이면 최대 1만 5천 행,
         한 사람이 아무리 장난쳐도 그 이상은 안 됩니다. */
      const t = Date.parse(wk + 'T00:00:00Z');
      const y = Number(wk.slice(0, 4));
      if (!Number.isFinite(t) || y < 1900 || y > 2200) {
        return { ok: false, reason: 'weekStart 가 쓸 수 있는 범위 밖입니다' };
      }
      q.upsertSnap.run(me, wk, JSON.stringify(payload || {}), nowISO());
      return { ok: true };
    },
    /** 친구가 나에게 허용한 항목만. 허용 안 된 키는 응답 객체에 존재하지 않습니다. */
    friendSnapshots(me, ownerId, limit = 26) {
      if (!this.exists(me) || !this.exists(ownerId)) return { ok: false, reason: '없는 계정입니다', rows: [] };
      if (!this.areFriends(me, ownerId)) return { ok: false, reason: '친구가 아닙니다', rows: [] };
      const s = this.shareFields(ownerId, me);
      const rows = q.snapsOf.all(ownerId, Math.min(200, Math.max(1, limit))).map(r => {
        let p = {};
        try { p = JSON.parse(r.payload); } catch {}
        const o = { weekStart: r.week_start };
        if (s.weightTrend && p.dWeightKg != null) o.dWeightKg = p.dWeightKg;
        if (s.smmTrend && p.dSmmKg != null) o.dSmmKg = p.dSmmKg;
        if (s.bfmTrend && p.dBfmKg != null) o.dBfmKg = p.dBfmKg;
        if (s.planProgress && p.progressPct != null) o.progressPct = p.progressPct;
        if (s.streak && p.checkedIn != null) o.checkedIn = p.checkedIn;
        // absolute 는 "숫자로 보여준다"는 뜻이지 "항목을 하나 더 연다"는 뜻이 아닙니다.
        // 켠 항목에만 붙습니다 — 체중만 켠 사람의 골격근/체지방이 여기로 새면 안 됩니다.
        if (s.absolute) {
          if (s.weightTrend && p.weightKg != null) o.weightKg = p.weightKg;
          if (s.smmTrend && p.smmKg != null) o.smmKg = p.smmKg;
          if (s.bfmTrend && p.bfmKg != null) o.bfmKg = p.bfmKg;
          // 원칙: 다른 두 값으로 계산되는 항목은 두 게이트의 논리곱으로 잠급니다.
          // pbfPct = bfmKg / weightKg 이므로 둘이 같이 나가면 체중이 복원됩니다.
          // 실측: bfmKg 18.9 + pbfPct 25.5 → 역산 74.12kg (실제 74.2kg).
          // 체중 공유를 명시적으로 끈 사람의 체중입니다.
          if (s.weightTrend && s.bfmTrend && p.pbfPct != null) o.pbfPct = p.pbfPct;
        }
        return o;
      });
      return { ok: true, rows, allowed: s };
    },

    /* 한 번에 받을 수 있는 레코드 수.
       클라이언트 큐 상한이 500 이라 넉넉합니다. 상한이 없으면 2MB
       본문에 수만 건을 담아 보낼 수 있고, node:sqlite 는 동기라서
       그동안 서버 전체가 — 다른 사람의 로그인까지 — 멈춥니다.
       노드는 스레드가 하나입니다. */
    PUSH_MAX: 1000,

    push(me, records) {
      if (!this.exists(me)) return { ok: false, reason: '없는 계정입니다', accepted: 0, rejected: [] };
      const list = Array.isArray(records) ? records : [];
      if (list.length > this.PUSH_MAX) {
        return { ok: false, reason: '한 번에 ' + this.PUSH_MAX + '건까지 보낼 수 있습니다',
                 accepted: 0, rejected: [], max: this.PUSH_MAX };
      }
      let n = 0;
      const rejected = [];
      /* 하나씩 커밋하면 건당 디스크 동기화가 일어납니다. 500건이면
         500번입니다. 트랜잭션으로 묶으면 한 번이고, 중간에 실패해도
         반쯤 들어간 상태가 남지 않습니다. */
      db.exec('BEGIN IMMEDIATE');
      try {
        for (const r of list) {
          if (!r || !r.kind || !r.id || !r.updatedAt) { rejected.push({ id: r && r.id, why: '필수 필드 누락' }); continue; }
          if (!str(r.kind) || !str(r.id)) { rejected.push({ id: null, why: 'kind · id 는 문자열이어야 합니다' }); continue; }
          // updatedAt 을 검증하고 정규화합니다. 예전엔 'zzzz' 같은 값이 그대로 저장됐고,
          // 그게 모든 ISO 문자열보다 큰 값이라 커서가 그 위로 올라가면
          // 그 계정의 동기화가 영구히 멈췄습니다.
          const t = Date.parse(r.updatedAt);
          if (!Number.isFinite(t)) { rejected.push({ id: r.id, why: 'updatedAt 이 날짜가 아닙니다' }); continue; }
          q.upsertRecord.run(me, str(r.kind), str(r.id), new Date(t).toISOString(),
                             r.deleted ? 1 : 0, JSON.stringify(r.payload || {}));
          n++;
        }
        db.exec('COMMIT');
      } catch (e) {
        try { db.exec('ROLLBACK'); } catch {}
        throw e;
      }
      return { ok: true, accepted: n, rejected: rejected };
    },
    pull(me, since = '', limit = 500) {
      if (!this.exists(me)) return { ok: false, reason: '없는 계정입니다', records: [], cursor: since, hasMore: false };
      const lim = Math.min(2000, Math.max(1, Number.isFinite(+limit) ? +limit : 500));
      // 커서 형식: "<iso>|<kind>|<id>". 빈 문자열이면 처음부터.
      const parts = str(since).split('|');
      const cAt = parts[0] || '', cKind = parts[1] || '', cId = parts[2] || '';
      const rows = q.recordsSince.all(me, cAt, cKind, cId, lim);
      const last = rows.length ? rows[rows.length - 1] : null;
      return {
        ok: true,
        records: rows.map(r => ({ kind: r.kind, id: r.id, updatedAt: r.updated_at,
                                  deleted: !!r.deleted, payload: safeParse(r.payload) })),
        cursor: last ? (last.updated_at + '|' + last.kind + '|' + last.id) : str(since),
        hasMore: rows.length === lim
      };
    },
    stats(me) { return { records: q.countRecords.get(me).c }; }
  };
}

function safeParse(s) { try { return JSON.parse(s); } catch { return {}; } }

module.exports = { open, makeApi, SHARE_FIELDS, blankShare, nowISO, str };
