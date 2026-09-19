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
      created_at TEXT NOT NULL
    );
    CREATE TABLE IF NOT EXISTS sessions (
      token TEXT PRIMARY KEY,
      user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      created_at TEXT NOT NULL,
      last_seen TEXT NOT NULL
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
    CREATE INDEX IF NOT EXISTS idx_records_sync ON records(user_id, updated_at);
    CREATE INDEX IF NOT EXISTS idx_snapshots_owner ON snapshots(owner_id, week_start DESC);
  `);
  return db;
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

    insertSession: db.prepare('INSERT INTO sessions (token, user_id, created_at, last_seen) VALUES (?,?,?,?)'),
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
    recordsSince: db.prepare('SELECT * FROM records WHERE user_id=? AND updated_at > ? ORDER BY updated_at LIMIT ?'),
    countRecords: db.prepare('SELECT COUNT(*) c FROM records WHERE user_id=?')
  };

  function pub(u) {
    return u && { id: u.id, displayName: u.display_name, provider: u.provider,
                  inviteCode: u.invite_code, createdAt: u.created_at };
  }

  return {
    SHARE_FIELDS, blankShare,

    signIn({ provider = 'kakao', handle, displayName }) {
      if (!handle) throw Object.assign(new Error('handle 이 필요합니다'), { status: 400 });
      let u = q.userByHandle.get(handle);
      if (!u) {
        const uid = id('user');
        q.insertUser.run(uid, handle, provider,
          (displayName || '사용자').slice(0, 20), inviteCode(), nowISO());
        u = q.userById.get(uid);
      }
      const t = token();
      q.insertSession.run(t, u.id, nowISO(), nowISO());
      return { token: t, user: pub(u) };
    },
    signOut(t) { q.deleteSession.run(t); },
    userForToken(t) {
      if (!t) return null;
      const s = q.sessionByToken.get(t);
      if (!s) return null;
      q.touchSession.run(nowISO(), t);
      return q.userById.get(s.user_id) || null;
    },
    me(uid) { return pub(q.userById.get(uid)); },
    updateMe(uid, { displayName }) {
      if (displayName) q.updateName.run(String(displayName).slice(0, 20), uid);
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
      const other = q.userByCode.get(String(code || '').toUpperCase());
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
      if (!q.edge.get(x, y)) return { ok: false, reason: '친구가 아닙니다' };
      q.deleteEdge.run(x, y);
      q.deleteShare.run(me, otherId);
      q.deleteShare.run(otherId, me);
      return { ok: true };
    },
    block(me, otherId) {
      const [x, y] = pair(me, otherId);
      if (!q.edge.get(x, y)) q.insertEdge.run(x, y, 'blocked', me, nowISO());
      q.setEdgeBlocked.run('blocked', me, nowISO(), x, y);
      q.deleteShare.run(me, otherId);
      q.deleteShare.run(otherId, me);
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
      for (const k of SHARE_FIELDS) if (k in patch) cur[k] = !!patch[k];
      if (cur.absolute && !cur.weightTrend && !cur.smmTrend && !cur.bfmTrend) cur.absolute = false;
      q.upsertShare.run(me, viewerId, JSON.stringify(cur), nowISO());
      return { ok: true, share: cur };
    },

    exists(uid) { return !!(uid && q.userById.get(uid)); },

    publishSnapshot(me, weekStart, payload) {
      if (!this.exists(me)) return { ok: false, reason: '없는 계정입니다' };
      if (!weekStart) return { ok: false, reason: 'weekStart 가 필요합니다' };
      q.upsertSnap.run(me, String(weekStart), JSON.stringify(payload || {}), nowISO());
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
        if (s.absolute) {
          for (const k of ['weightKg', 'smmKg', 'bfmKg', 'pbfPct']) if (p[k] != null) o[k] = p[k];
        }
        return o;
      });
      return { ok: true, rows, allowed: s };
    },

    push(me, records) {
      if (!this.exists(me)) return { ok: false, reason: '없는 계정입니다', accepted: 0 };
      let n = 0;
      for (const r of records || []) {
        if (!r || !r.kind || !r.id || !r.updatedAt) continue;
        q.upsertRecord.run(me, String(r.kind), String(r.id), String(r.updatedAt),
                           r.deleted ? 1 : 0, JSON.stringify(r.payload || {}));
        n++;
      }
      return { ok: true, accepted: n };
    },
    pull(me, since = '', limit = 500) {
      if (!this.exists(me)) return { ok: false, reason: '없는 계정입니다', records: [], cursor: since };
      const rows = q.recordsSince.all(me, String(since || ''), Math.min(2000, limit));
      return {
        ok: true,
        records: rows.map(r => ({ kind: r.kind, id: r.id, updatedAt: r.updated_at,
                                  deleted: !!r.deleted, payload: safeParse(r.payload) })),
        cursor: rows.length ? rows[rows.length - 1].updated_at : since
      };
    },
    stats(me) { return { records: q.countRecords.get(me).c }; }
  };
}

function safeParse(s) { try { return JSON.parse(s); } catch { return {}; } }

module.exports = { open, makeApi, SHARE_FIELDS, blankShare, nowISO };
