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

const SHARE_FIELDS = ['weightTrend', 'smmTrend', 'bfmTrend', 'planProgress', 'streak', 'schedule', 'absolute', 'diet'];

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
      pw_n INTEGER,
      -- 건강정보(체성분) 업로드에 대한 별도 동의 — 언제, 어느 문구에
      consent_health_at TEXT,
      consent_version TEXT
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
    CREATE TABLE IF NOT EXISTS push_subs (
      endpoint TEXT PRIMARY KEY,
      user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      p256dh TEXT NOT NULL,
      auth TEXT NOT NULL,
      created_at TEXT NOT NULL,
      fails INTEGER NOT NULL DEFAULT 0
    );
    /* 판독(OCR) 을 오늘 몇 번 썼는가.
     *
     * 예전에는 이 숫자가 **메모리에만** 있었습니다. 그래서 서버를 껐다
     * 켜면 그날 한도가 0 으로 돌아갔습니다. 개발 중에는 하루에도 여러 번
     * 껐다 켜므로, 사실상 한도가 없는 것과 같았습니다.
     *
     * 이건 취향 문제가 아니라 **지갑 문제**입니다. 판독 한 장이 수십 원이고
     * 가입이 열려 있으면 주소를 아는 사람이 계정을 만들어 태울 수 있습니다.
     * 한도는 서버가 죽었다 살아나도 그대로여야 합니다. */
    CREATE TABLE IF NOT EXISTS ocr_usage (
      day TEXT NOT NULL,
      who TEXT NOT NULL,
      n INTEGER NOT NULL,
      PRIMARY KEY (day, who)
    );
    CREATE INDEX IF NOT EXISTS idx_push_user ON push_subs(user_id);
    CREATE INDEX IF NOT EXISTS idx_records_sync ON records(user_id, updated_at, kind, id);
    CREATE INDEX IF NOT EXISTS idx_snapshots_owner ON snapshots(owner_id, week_start DESC);
  `);
  /* 이미 만들어진 DB 에 컬럼을 더합니다. ALTER 가 실패하면 이미 있다는 뜻입니다. */
  for (const stmt of ['ALTER TABLE users ADD COLUMN pw_hash TEXT',
                      'ALTER TABLE users ADD COLUMN pw_salt TEXT',
                      'ALTER TABLE users ADD COLUMN pw_n INTEGER',
                      'ALTER TABLE sessions ADD COLUMN expires_at TEXT',
                      'ALTER TABLE users ADD COLUMN rc_hash TEXT',
                      'ALTER TABLE users ADD COLUMN rc_salt TEXT',
                      'ALTER TABLE users ADD COLUMN rc_n INTEGER',
                      'ALTER TABLE users ADD COLUMN rc_used_at TEXT',
                      /* 건강정보 업로드에 대한 별도 동의. 언제 · 어느 문구에
                         동의했는지를 남깁니다. 문구가 바뀌면 version 이
                         올라가고, 옛 버전으로 동의한 사람에게 다시 묻습니다. */
                      'ALTER TABLE users ADD COLUMN consent_health_at TEXT',
                      'ALTER TABLE users ADD COLUMN consent_version TEXT',
                      /* 프로필 사진. 데이터 URL 문자열 그대로 넣습니다 —
                         192×192 JPEG 라 24KB 를 넘지 않고, 이 규모(친구
                         몇 명)에서 파일 저장소를 따로 두는 것보다 백업이
                         단순합니다. backup.js 의 VACUUM INTO 한 방에 같이
                         따라옵니다. */
                      'ALTER TABLE users ADD COLUMN avatar TEXT']) {
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

  /* 공유 설정에 **나중에 생긴 항목이 조용히 켜지지 않게** 못을 박습니다.
   *
   * shareFields() 는 Object.assign(blankShare(), 저장된값) 으로 읽습니다.
   * 저장된 행에 없는 키는 blankShare() 의 기본값이 그대로 남습니다.
   * 그래서 기본 켜짐인 항목을 새로 만들면, 그 항목이 생기기 전에 저장된
   * **모든 기존 관계에서 저절로 켜집니다.** "전부 끄기" 를 눌러 둔
   * 사람까지 포함해서.
   *
   * 실제로 그렇게 됐습니다. schedule 을 기본 켜짐으로 넣자, 저장된 행이
   * {… streak:false, absolute:false} 인 사람(전부 끈 사람)의 읽은 값이
   * {… schedule:true} 가 되고 친구 화면에 "계획 4일 · 지킴 2일" 이
   * 떴습니다. 껐다고 믿는 사람은 다시 확인하지 않습니다 — 이 앱에서
   * 제일 나쁜 종류의 고장입니다.
   *
   * 규칙: **사용자가 본 적 없는 항목은 켜져 있을 수 없습니다.** 동의는
   * 읽은 문장에 대해 하는 것이지 코드에 대해 하는 것이 아닙니다.
   * 그래서 저장된 행에 없는 키는 전부 false 로 명시해 둡니다. 새로
   * 맺는 관계는 blankShare() 를 그대로 쓰므로 기본 켜짐이 살아 있습니다 —
   * 그 사람은 지금 화면에 적힌 문장을 읽고 친구를 맺은 사람입니다.
   *
   * 여러 번 돌아도 안전합니다. 한 번 지나가면 모든 행이 모든 키를
   * 명시하고 있어서 그 뒤로는 아무것도 안 바뀝니다. */
  try {
    const rows = db.prepare('SELECT owner_id, viewer_id, fields FROM shares').all();
    const fix = db.prepare('UPDATE shares SET fields=? WHERE owner_id=? AND viewer_id=?');
    for (const r of rows) {
      let f;
      try { f = JSON.parse(r.fields); } catch { f = {}; }
      if (!f || typeof f !== 'object') f = {};
      let changed = false;
      for (const k of SHARE_FIELDS) {
        if (typeof f[k] !== 'boolean') { f[k] = false; changed = true; }
      }
      if (changed) fix.run(JSON.stringify(f), r.owner_id, r.viewer_id);
    }
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

/* ---------------------------------------------------------------------------
 * 복구 코드
 *
 * 이 서버는 메일을 보내지 않습니다. 보내려면 주소를 받아서 보관해야 하고,
 * 그건 지키기로 한 "민감한 것은 최소한만" 과 어긋납니다. 그래서 가입할 때
 * 코드를 한 번 보여주고, 비밀번호를 잊으면 그걸로 새로 정합니다.
 *
 * 왜 이게 없으면 런칭을 못 하나
 *   지금은 잊으면 끝입니다. 서버 주인이 DB 에서 계정을 지우고 다시
 *   만드는 수밖에 없는데, 그러면 친구 관계와 그동안의 주간 기록이
 *   같이 사라집니다. 나 혼자면 참을 수 있지만 남에게 줄 수는 없습니다.
 *
 * 모양: XXXX-XXXX-XXXX-XXXX, 숫자와 헷갈리지 않는 글자만 (0/O, 1/I/L 제외).
 * 글자 31종 × 16자리 = 31^16 ≈ 7.3e23 ≈ 79비트. 아이디별로 시간당
 * 몇 번만 시도할 수 있으므로 무차별 대입은 우주의 나이보다 오래 걸립니다.
 *
 * 저장은 비밀번호와 똑같이 scrypt 해시로만 합니다 — DB 를 통째로 가져가도
 * 코드를 되돌릴 수 없어야 합니다.
 *
 * 한 번 쓰면 새 코드를 발급합니다. 쓴 코드가 메모장에 남아 있어도 그때부터
 * 쓸모가 없어야 합니다.
 */
const RC_ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';   // 0 O 1 I L 제외
const RC_GROUPS = 4, RC_PER_GROUP = 4;

function makeRecoveryCode() {
  const n = RC_GROUPS * RC_PER_GROUP;
  const bytes = crypto.randomBytes(n * 2);
  let out = '';
  for (let i = 0; i < n; i++) {
    // 모듈로 편향을 피하려고 넉넉히 뽑아 버립니다
    let v = bytes[i * 2] * 256 + bytes[i * 2 + 1];
    while (v >= 65536 - (65536 % RC_ALPHABET.length)) v = crypto.randomBytes(2).readUInt16BE(0);
    out += RC_ALPHABET[v % RC_ALPHABET.length];
    if ((i + 1) % RC_PER_GROUP === 0 && i + 1 < n) out += '-';
  }
  return out;
}

/** 사람이 옮겨 적은 코드를 비교할 수 있는 모양으로. 대소문자·하이픈·공백 무시. */
function normalizeCode(x) {
  return str(x).toUpperCase().replace(/[^A-Z0-9]/g, '');
}

function hashCode(plain, saltHex, n) {
  return hashPassword(normalizeCode(plain), saltHex, n);
}

function verifyCode(plain, user) {
  if (!user || !user.rc_hash || !user.rc_salt) return false;
  const got = hashCode(plain, user.rc_salt, user.rc_n || SCRYPT_N).hash;
  const a = Buffer.from(got, 'hex'), b = Buffer.from(user.rc_hash, 'hex');
  if (a.length !== b.length) return false;
  return crypto.timingSafeEqual(a, b);
}

/* 건강정보 업로드 동의 문구의 판. 문구가 바뀌면 올립니다 —
   옛 판으로 동의한 사람에게는 다시 물어야 하기 때문입니다.
   화면(modals.js M29)에 적힌 문구와 이 값이 같아야 합니다. */
const HEALTH_CONSENT_VERSION = '2026-09-20';

/* 주간 요약 보유 기간. 화면이 보는 26주의 두 배입니다.
   가입 동의 문구(modals.js M29)와 처리방침(privacy.html 7번)에
   적힌 숫자와 같아야 합니다 — 셋이 어긋나면 하나는 거짓말입니다. */
const SNAPSHOT_WEEKS = 52 * 7;   // 일 단위 (SQLite date() 가 일로 셉니다)

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
  // 행동에 대한 것 둘만 켜 둡니다 — 체크인 여부와 이번 주 일정 숫자 네 개.
  //
  // 일정이 기본 켜짐인 이유: 나가는 것이 주 단위 숫자 네 개(하기로 한 날 ·
  // 지킨 날 · 지나갔는데 체크가 없는 날 · 아직 남은 날)뿐이고,
  // 무슨 요일에 무슨 운동을 했는지는 안 나갑니다. 몸이 아니라 본인이 적은
  // 행동이고, 같이 운동하자고 친구를 맺은 사이에서 이 둘이 안 보이면
  // 친구 기능이 아무것도 아닌 것이 됩니다. 한 번 눌러 끌 수 있습니다.
  //
  // diet(오늘 식단 — 먹은 칼로리·탄단지와 목표)도 몸이 아니라 본인이 적은
  // 행동이라 기본 켜짐입니다. 이 항목이 생기기 전의 관계는 위 마이그레이션
  // 규칙대로 꺼진 채 시작합니다 — 본 적 없는 문장에 동의한 사람은 없습니다.
  return { weightTrend: false, smmTrend: false, bfmTrend: false,
           planProgress: false, streak: true, schedule: true, absolute: false,
           diet: true };
}

function makeApi(db) {
  const q = {
    userByHandle: db.prepare('SELECT * FROM users WHERE handle = ?'),
    allUsers: db.prepare('SELECT handle, display_name, created_at FROM users ORDER BY created_at'),
    userById: db.prepare('SELECT * FROM users WHERE id = ?'),
    userByCode: db.prepare('SELECT * FROM users WHERE invite_code = ?'),
    insertUser: db.prepare(
      'INSERT INTO users (id, handle, provider, display_name, invite_code, created_at) VALUES (?,?,?,?,?,?)'),
    updateName: db.prepare('UPDATE users SET display_name = ? WHERE id = ?'),
    deleteUser: db.prepare('DELETE FROM users WHERE id = ?'),

    insertSession: db.prepare('INSERT INTO sessions (token, user_id, created_at, last_seen, expires_at) VALUES (?,?,?,?,?)'),
    deleteSessionsOf: db.prepare('DELETE FROM sessions WHERE user_id = ?'),
    setPassword: db.prepare('UPDATE users SET pw_hash=?, pw_salt=?, pw_n=? WHERE id=?'),
    setRecovery: db.prepare('UPDATE users SET rc_hash=?, rc_salt=?, rc_n=?, rc_used_at=? WHERE id=?'),
    setConsent: db.prepare('UPDATE users SET consent_health_at=?, consent_version=? WHERE id=?'),
    /* 보유 기간이 지난 주간 요약을 버립니다. week_start 는 YYYY-MM-DD
       문자열이라 date() 로 비교됩니다 (형식은 publishSnapshot 이 강제합니다). */
    pruneSnaps: db.prepare(
      "DELETE FROM snapshots WHERE owner_id = ? AND week_start < date('now', '-' || ? || ' days')"),
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

    bumpOcr: db.prepare(
      'INSERT INTO ocr_usage (day, who, n) VALUES (?,?,1) ' +
      'ON CONFLICT(day, who) DO UPDATE SET n = n + 1'),
    getOcr: db.prepare('SELECT n FROM ocr_usage WHERE day=? AND who=?'),
    pruneOcr: db.prepare('DELETE FROM ocr_usage WHERE day < ?'),
    deleteOcrOf: db.prepare('DELETE FROM ocr_usage WHERE who=?'),

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
    countRecords: db.prepare('SELECT COUNT(*) c FROM records WHERE user_id=?'),
    updateAvatar: db.prepare('UPDATE users SET avatar=? WHERE id=?'),

    addPush: db.prepare(
      'INSERT INTO push_subs (endpoint,user_id,p256dh,auth,created_at,fails) VALUES (?,?,?,?,?,0) ' +
      'ON CONFLICT(endpoint) DO UPDATE SET user_id=excluded.user_id, p256dh=excluded.p256dh, ' +
      'auth=excluded.auth, fails=0'),
    delPush: db.prepare('DELETE FROM push_subs WHERE endpoint=?'),
    delPushOf: db.prepare('DELETE FROM push_subs WHERE user_id=?'),
    pushOf: db.prepare('SELECT * FROM push_subs WHERE user_id=?'),
    bumpPushFail: db.prepare('UPDATE push_subs SET fails=fails+1 WHERE endpoint=?'),
    prevSnap: db.prepare('SELECT payload FROM snapshots WHERE owner_id=? AND week_start=?')
  };

  /* 프로필 사진 검사.
   *
   * 여기로 들어오는 것은 친구의 브라우저가 보낸 문자열입니다. 브라우저를
   * 거치지 않고 직접 때릴 수 있으므로 서버가 다시 봅니다 — 화면의
   * 검사는 편의이고, 여기가 방어선입니다.
   *
   * SVG 를 안 받는 이유: SVG 안에는 <script> 가 들어갑니다. 우리는
   * <img src="data:..."> 로만 그리니 실행되지 않지만, 언젠가 누가
   * 새 탭에서 열게 만들면 그 순간 스크립트가 됩니다. 처음부터 안
   * 받는 쪽이 그 실수를 못 하게 막습니다.
   */
  function bad(msg) { const e = new Error(msg); e.status = 400; return e; }
  const AVATAR_MAX = 24 * 1024;
  const AVATAR_RE = /^data:image\/(jpeg|png|webp);base64,[A-Za-z0-9+/]+=*$/;
  function checkAvatar(v) {
    if (v === null || v === '' || v === undefined) return null;   // 지우기
    const t = str(v);
    /* server.js 의 바깥 catch 가 e.status 를 보고 그 코드로 내보냅니다.
       안 달면 500 + 스택 로그가 됩니다 — 사용자 잘못을 서버 잘못처럼
       기록하고, 화면에는 "서버 오류"라는 틀린 말이 뜹니다. */
    if (t.length > AVATAR_MAX) throw bad('프로필 사진이 너무 큽니다');
    if (!AVATAR_RE.test(t)) throw bad('프로필 사진 형식을 받을 수 없습니다');
    return t;
  }

  function pub(u) {
    return u && { id: u.id, displayName: u.display_name, provider: u.provider,
                  inviteCode: u.invite_code, createdAt: u.created_at,
                  avatar: u.avatar || null,
                  /* 본인이 언제 · 어느 문구에 동의했는지는 본인이 볼 수
                     있어야 합니다 (제35조 열람). */
                  healthConsentAt: u.consent_health_at || null,
                  healthConsentVersion: u.consent_version || null };
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
    signUp({ handle, password, displayName, healthConsent }) {
      const h = str(handle).trim().toLowerCase();
      if (!/^[a-z0-9_.-]{3,32}$/.test(h)) {
        return { ok: false, reason: '아이디는 영문·숫자·(_ . -) 3~32자입니다' };
      }
      const pwBad = passwordProblem(password);
      if (pwBad) return { ok: false, reason: pwBad };
      /* 체성분은 민감정보입니다. 계정을 만드는 것과 "내 몸 숫자를 서버에
         올리는 것" 은 다른 일이고, 동의도 따로 받아야 합니다. 로그인하면
         친구가 하나도 없어도 주간 요약이 올라가므로, 가입이 곧 업로드
         동의가 됩니다 — 그래서 여기서 막습니다.
         화면이 안 물어보고 보냈으면 그건 화면의 버그입니다. */
      if (str(healthConsent) !== HEALTH_CONSENT_VERSION) {
        return { ok: false, reason: '건강정보 업로드에 동의해야 계정을 만들 수 있습니다' };
      }
      if (q.userByHandle.get(h)) return { ok: false, reason: '이미 있는 아이디입니다' };

      const pw = hashPassword(password);
      const uid = id('user');
      q.insertUser.run(uid, h, 'local', (displayName || h).slice(0, 20), inviteCode(), nowISO());
      q.setPassword.run(pw.hash, pw.salt, pw.n, uid);
      q.setConsent.run(nowISO(), HEALTH_CONSENT_VERSION, uid);
      /* 복구 코드는 지금 한 번만 원문으로 나갑니다. 서버에는 해시만
         남으므로, 사용자가 이걸 놓치면 우리도 되찾아 줄 수 없습니다.
         화면이 그 사실을 분명히 말해야 합니다. */
      const code = makeRecoveryCode();
      const rc = hashCode(code);
      q.setRecovery.run(rc.hash, rc.salt, rc.n, null, uid);
      const u = q.userById.get(uid);
      return Object.assign({ ok: true, recoveryCode: code }, this._newSession(u));
    },

    /* 복구 코드로 비밀번호를 새로 정합니다.
     *
     * 성공하면 세 가지를 같이 합니다:
     *   1. 새 비밀번호를 건다
     *   2. 다른 기기의 세션을 전부 끊는다 — 계정을 되찾는 상황이라면
     *      남이 들어와 있을 수 있고, 그 사람을 남겨 둘 이유가 없습니다
     *   3. 새 복구 코드를 발급한다 — 쓴 코드가 메모장에 남아 있어도
     *      그때부터 쓸모가 없어야 합니다
     */
    recoverPassword({ handle, code, password }) {
      const h = str(handle).trim().toLowerCase();
      const u = q.userByHandle.get(h);
      /* 아이디가 없어도 해시를 한 번 돌립니다 — 응답 시간으로 계정
         존재 여부를 알아낼 수 없게. signIn 과 같은 이유입니다. */
      if (!u) { hashCode(code, null, SCRYPT_N); }
      const pwBad = passwordProblem(password);
      if (!u || !u.rc_hash || !verifyCode(code, u)) {
        // 어느 쪽이 틀렸는지 알려주지 않습니다
        return { ok: false, reason: '아이디 또는 복구 코드가 맞지 않습니다' };
      }
      // 코드는 맞았습니다. 이제 비밀번호 자체의 문제를 말해 줍니다.
      if (pwBad) return { ok: false, reason: pwBad };

      const pw = hashPassword(password);
      q.setPassword.run(pw.hash, pw.salt, pw.n, u.id);
      q.deleteSessionsOf.run(u.id);
      const next = makeRecoveryCode();
      const rc = hashCode(next);
      q.setRecovery.run(rc.hash, rc.salt, rc.n, nowISO(), u.id);
      const fresh = q.userById.get(u.id);
      return Object.assign({ ok: true, recoveryCode: next }, this._newSession(fresh));
    },

    /** 로그인한 상태에서 새 복구 코드를 받습니다 (잃어버렸을 때) */
    newRecoveryCode(uid, { password }) {
      const u = q.userById.get(uid);
      if (!u) return { ok: false, reason: '없는 계정입니다' };
      // 잠깐 열린 폰을 집어든 사람이 코드를 새로 뽑아 가지 못하게 합니다
      if (!verifyPassword(password, u)) return { ok: false, reason: '비밀번호가 맞지 않습니다' };
      const code = makeRecoveryCode();
      const rc = hashCode(code);
      q.setRecovery.run(rc.hash, rc.salt, rc.n, null, uid);
      return { ok: true, recoveryCode: code };
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

    /* 주인이 대신 풀어 주는 비밀번호 초기화.
     *
     * 이 서버는 메일을 안 보냅니다. 그래서 비밀번호를 잊은 사람이
     * 돌아올 길은 가입할 때 한 번 보여준 **복구 코드**뿐인데, 그걸
     * 안 적어 둔 사람에게는 길이 없습니다.
     *
     * 실제로 그래서 무슨 일이 났냐면 — 로그 한 판에서 로그인 실패 6회,
     * 로그인 성공 1회, 가입 7회가 나왔습니다. 사람들이 로그인이 안 되니까
     * **그냥 새 계정을 만들고 있었습니다.** 그러면 그 사람의 기록과
     * 친구 연결이 통째로 끊깁니다.
     *
     * 서버가 주인 컴퓨터에 있으니 주인은 풀어 줄 수 있습니다.
     * HTTP 로는 열지 않습니다 — 이건 tools/reset-password.js 에서만
     * 부르는, 그 컴퓨터 앞에 앉은 사람의 권한입니다.
     *
     * 복구 코드도 같이 새로 냅니다. 여기까지 온 사람은 십중팔구 그걸
     * 잃은 사람이라, 비밀번호만 주면 다음에 또 같은 자리로 옵니다. */
    adminResetPassword(handle, next) {
      const u = q.userByHandle.get(str(handle).toLowerCase());
      if (!u) return { ok: false, reason: '그런 아이디가 없습니다' };
      const bad = passwordProblem(next);
      if (bad) return { ok: false, reason: bad };
      const pw = hashPassword(next);
      q.setPassword.run(pw.hash, pw.salt, pw.n, u.id);
      /* 쓰던 기기의 세션을 전부 끊습니다. 비밀번호를 바꾸는 이유가
         "못 들어간다" 일 수도, "남이 들어갔다" 일 수도 있습니다.
         뒤쪽이면 세션을 남겨 두는 순간 초기화가 무의미합니다. */
      q.deleteSessionsOf.run(u.id);
      const code = makeRecoveryCode();
      const rc = hashCode(code);
      q.setRecovery.run(rc.hash, rc.salt, rc.n, null, u.id);
      return { ok: true, handle: u.handle, displayName: u.display_name, recoveryCode: code };
    },

    /** 주인이 계정을 찾아볼 수 있게. 비밀은 하나도 안 싣습니다. */
    adminListUsers() {
      return q.allUsers.all().map(u => ({
        handle: u.handle, displayName: u.display_name, createdAt: u.created_at
      }));
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
    updateMe(uid, { displayName, avatar }) {
      if (displayName) {
        const dn = str(displayName).slice(0, 20);
        if (dn) q.updateName.run(dn, uid);
      }
      /* undefined 와 null 은 다른 뜻입니다.
         undefined = 이 요청은 사진 얘기를 안 했다 (그대로 둔다)
         null/'' = 사진을 지워 달라
         그래서 `if (avatar)` 로 쓰면 지우기가 영영 안 먹습니다. */
      if (avatar !== undefined) q.updateAvatar.run(checkAvatar(avatar), uid);
      return pub(q.userById.get(uid));
    },
    /* 연쇄 삭제로 친구·공유·스냅샷·기록은 전부 사라집니다.
       **판독 횟수는 안 사라집니다.** ocr_usage 만 users 를 참조하지 않아서
       외래키가 없고, 그날 치 행은 다음 날 청소 전까지 남습니다 —
       `{ day: '2026-09-21', who: 'user_e73fe…', n: 1 }`.
       한 줄이고 그날 안에 지워질 것이긴 한데, 바로 그것이 이 파일이
       "안 남기기로 했다" 고 적어 둔 종류의 기록입니다(bumpOcr 주석).
       탈퇴는 "이제 없다" 여야 하고, 그 말에 예외를 두지 않습니다. */
    deleteMe(uid) {
      q.deleteOcrOf.run(uid);
      q.deleteUser.run(uid);
    },

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
        return Object.assign({ otherId: other.id }, this.accept(me, other.id));
      }
      q.insertEdge.run(x, y, 'pending', me, nowISO());
      /* 상대의 id 를 같이 돌려줍니다 — 서버가 그 사람에게 알림을 보내야
         하는데, 여기 말고는 "방금 누구에게 갔는가" 를 아는 곳이 없습니다.
         새어 나가는 것은 없습니다: 초대 코드를 쥐고 방금 그 사람을 추가한
         쪽에게 그 사람의 id 를 주는 것뿐입니다.
         **새로 생긴 요청일 때만** 여기까지 옵니다. 같은 요청을 다시 보내면
         위에서 '이미 보낸 요청입니다' 로 끝나므로, 알림을 반복해서 울리는
         길이 없습니다 — 버튼을 연타해도 한 번만 갑니다. */
      return { ok: true, status: 'pending', otherId: other.id };
    },
    accept(me, otherId) {
      const [x, y] = pair(me, otherId);
      const e = q.edge.get(x, y);
      if (!e || e.status !== 'pending') return { ok: false, reason: '받은 요청이 없습니다' };
      if (e.requested_by === me) return { ok: false, reason: '내가 보낸 요청은 내가 수락할 수 없습니다' };
      q.setEdgeStatus.run('accepted', nowISO(), x, y);
      /* updated_at 을 **빈 문자열**로 둡니다 — "기본값 그대로, 아직 아무도
         고른 적 없음" 이라는 뜻입니다.
         여기에 수락 시각을 넣으면 "한 번도 안 고른 것" 과 "고른 것" 이
         구분되지 않고, 앱은 그 구분으로 "친구가 되었습니다 — 지금 보이는
         것은 둘입니다" 안내를 띄울지 정합니다. 시각을 넣어 두면 그 안내가
         아무에게도 안 뜨거나(서버 기준) 누구에게나 다시 뜹니다(거울 기준).
         빈 문자열을 쓰는 이유는 컬럼이 NOT NULL 이기 때문입니다. */
      q.upsertShare.run(me, otherId, JSON.stringify(blankShare()), '');
      q.upsertShare.run(otherId, me, JSON.stringify(blankShare()), '');
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
          /* 사진은 수락한 친구에게만 보냅니다.
             아직 수락 안 한 요청에까지 실어 보내면, 초대 코드를 아는
             사람이 누구에게나 이미지를 밀어 넣을 수 있게 됩니다.
             누구의 요청인지는 이름과 직접 건네받은 초대 코드로 아는
             것이 원래 이 앱의 흐름이라, 잃는 것이 없습니다. */
          row.avatar = u.avatar || null;
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
      /* 저장된 행이 있으면 **그 행이 전부** 입니다. 없는 키를 blankShare()
         의 기본값으로 채우지 않습니다 — 그러면 나중에 생긴 기본 켜짐
         항목이 옛 관계에서 저절로 켜집니다(위 마이그레이션 주석 참고).
         행이 아예 없을 때만 기본값을 씁니다. 그건 아직 아무것도 정한
         적이 없는 새 관계라는 뜻입니다. */
      try {
        const saved = JSON.parse(r.fields) || {};
        const out = {};
        for (const k of SHARE_FIELDS) out[k] = saved[k] === true;
        return out;
      } catch { return blankShare(); }
    },
    shareSummary(owner, viewer) {
      const s = this.shareFields(owner, viewer);
      /* 언제 정했는가도 같이 보냅니다.
         이게 빠져 있어서 pull() 한 번마다 모든 친구의 updatedAt 이
         null 로 돌아갔고, 이미 전부 꺼 둔 사람에게 "친구가 되었습니다"
         안내가 계속 다시 떴습니다 — 끄기를 누른 직후 flush→pull 로
         곧바로요. 서버가 아는 값을 안 보내서 생긴 일입니다. */
      const r = q.getShare.get(owner, viewer);
      s.updatedAt = (r && r.updated_at) || null;
      const LABEL = { weightTrend: '체중 변화', smmTrend: '골격근 변화', bfmTrend: '체지방 변화',
                      planProgress: '목표 달성률', streak: '이번 주 기록 여부',
                      schedule: '이번 주 운동 일정', absolute: '실제 수치까지',
                      diet: '오늘 식단' };
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
      /* 덮어쓰기 전에 지난 값을 봐 둡니다 — 알림을 보낼지 판단하는
         재료입니다. **늘어났을 때만** 보냅니다. 안 한 것은 알림이 될 수
         없고, 그건 못 만든 게 아니라 만들 수 없게 만들어 둔 것입니다
         (news.js 와 같은 규칙). */
      let grew = false;
      try {
        const before = q.prevSnap.get(me, wk);
        const prev = before ? JSON.parse(before.payload) : null;
        const now = payload || {};
        if (now.keptDays != null && prev && prev.keptDays != null && now.keptDays > prev.keptDays) {
          grew = true;
        }
      } catch { /* 지난 값이 깨져 있으면 알림만 안 보냅니다 */ }

      q.upsertSnap.run(me, wk, JSON.stringify(payload || {}), nowISO());
      /* 보유 기간을 지킵니다.
       *
       * 개인정보보호법 제21조는 보유 기간이 지나면 지체 없이 파기하라고
       * 합니다. 여기 쌓이는 것은 건강정보라 더 그렇습니다. 그런데 지금까지
       * 스냅샷은 주 단위로 무한정 쌓였습니다 — 10년을 쓰면 520주가 남고,
       * 친구 화면은 최근 26주만 봅니다. 아무도 안 보는 오래된 체지방
       * 기록을 계속 들고 있을 이유가 없습니다.
       *
       * 52주로 둡니다. 화면이 보는 26주의 두 배이고, 가입 동의 문구와
       * 처리방침에 적힌 숫자와 같습니다. 셋이 어긋나면 그중 하나는
       * 거짓말이 됩니다. */
      q.pruneSnaps.run(me, SNAPSHOT_WEEKS);
      return { ok: true, grew, keptDays: (payload || {}).keptDays,
               plannedDays: (payload || {}).plannedDays };
    },

    /* --- 폰 알림 구독 -------------------------------------------------
     * 브라우저가 준 PushSubscription 을 그대로 보관합니다. endpoint 가
     * 키라서 같은 기기가 다시 구독하면 덮어씁니다 — 기기를 바꾸거나
     * 알림을 껐다 켜면 endpoint 가 바뀌고, 옛것은 푸시 서비스가
     * 404/410 을 주는 순간 지웁니다.
     * ---------------------------------------------------------------- */
    addPushSub(uid, sub) {
      if (!this.exists(uid)) return { ok: false, reason: '없는 계정입니다' };
      const ep = str(sub && sub.endpoint);
      const p256dh = str(sub && sub.p256dh);
      const auth = str(sub && sub.auth);
      if (!/^https:\/\//.test(ep)) return { ok: false, reason: 'endpoint 는 https 여야 합니다' };
      if (ep.length > 800) return { ok: false, reason: 'endpoint 가 너무 깁니다' };
      /* 키 길이를 여기서 봅니다. 틀린 키를 받아 두면 보낼 때마다
         조용히 실패하고, 사용자는 "알림을 켰는데 안 온다" 만 겪습니다. */
      if (!/^[A-Za-z0-9\-_]{86,88}$/.test(p256dh)) return { ok: false, reason: 'p256dh 형식 오류' };
      if (!/^[A-Za-z0-9\-_]{22,24}$/.test(auth)) return { ok: false, reason: 'auth 형식 오류' };
      q.addPush.run(ep, uid, p256dh, auth, nowISO());
      return { ok: true };
    },
    removePushSub(uid, endpoint) {
      const row = db.prepare('SELECT user_id FROM push_subs WHERE endpoint=?').get(str(endpoint));
      if (!row) return { ok: true };                      // 없으면 이미 없는 것
      if (row.user_id !== uid) return { ok: false, reason: '내 구독이 아닙니다' };
      q.delPush.run(str(endpoint));
      return { ok: true };
    },
    pushSubsOf(uid) {
      return q.pushOf.all(uid).map(r => ({
        endpoint: r.endpoint, p256dh: r.p256dh, auth: r.auth, fails: r.fails
      }));
    },
    dropPushSub(endpoint) { q.delPush.run(str(endpoint)); },

    /**
     * 판독을 한 번 썼다고 적고, 오늘 쓴 횟수를 돌려줍니다.
     * 서버가 죽었다 살아나도 숫자가 안 없어집니다 — 그게 이 함수가
     * 메모리 대신 DB 를 쓰는 유일한 이유입니다.
     * @returns {{user:number, total:number}}
     */
    /* 올리지 않고 **보기만** 합니다.
       한도 확인과 횟수 올리기가 한 함수에 붙어 있으면, 실패한 요청까지
       한도를 깎습니다. 키가 망가진 날 열 번 눌러 보면 그날 한도가 끝나고,
       화면 문구가 진짜 원인에서 "오늘 판독 한도를 다 썼습니다" 로 바뀌어
       원인이 덮입니다 — 고치는 사람이 제일 헷갈릴 때 그렇게 됩니다. */
    peekOcr(userId, day) {
      const d = str(day) || nowISO().slice(0, 10);
      const me = str(userId) || '?';
      const a = q.getOcr.get(d, me);
      const b = q.getOcr.get(d, '*');
      return { user: (a && a.n) || 0, total: (b && b.n) || 0 };
    },

    bumpOcr(userId, day) {
      const d = str(day) || nowISO().slice(0, 10);
      const me = str(userId) || '?';
      q.bumpOcr.run(d, me);
      q.bumpOcr.run(d, '*');
      const a = q.getOcr.get(d, me);
      const b = q.getOcr.get(d, '*');
      /* 지난 날 기록은 쌓아 둘 이유가 없습니다. 이 숫자는 그날의
         한도를 지키려고 있는 것이지 통계가 아닙니다 — 오래 들고 있으면
         "누가 언제 몇 장 올렸나" 가 되고, 그건 우리가 안 남기기로 한
         종류의 기록입니다. */
      q.pruneOcr.run(d);
      return { user: (a && a.n) || 0, total: (b && b.n) || 0 };
    },
    notePushFail(endpoint) { q.bumpPushFail.run(str(endpoint)); },

    /** 이 사람이 운동했다는 소식을 받을 친구들 (일정 공유를 켠 사람만) */
    pushTargetsFor(ownerId) {
      const out = [];
      for (const e of q.edgesOf.all(ownerId, ownerId)) {
        if (e.status !== 'accepted') continue;
        const viewer = e.a_id === ownerId ? e.b_id : e.a_id;
        /* 그 친구에게 일정을 안 보여주기로 했으면 알림도 안 갑니다.
           알림이 공유 설정을 우회하는 뒷문이 되면 안 됩니다. */
        if (!this.shareFields(ownerId, viewer).schedule) continue;
        for (const s of this.pushSubsOf(viewer)) out.push({ viewer, sub: s });
      }
      return out;
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
        if (s.streak) {
          if (p.checkedIn != null) o.checkedIn = p.checkedIn;
          /* 스트릭(운동 며칠째 · 식단 며칠째)도 행동입니다 — 같은 스위치. */
          if (p.streaks && typeof p.streaks === 'object') o.streaks = p.streaks;
        }
        /* 일정은 주 단위 숫자 네 개(며칠 하기로 했고 · 지켰고 · 체크가 없고 ·
           남았는가)에 더해 **요일별 계획과 체크**가 나갑니다. 처음엔 요일을
           안 보냈습니다 — 남의 한 주를 재구성하는 것은 확인이 아니라 감시라고.
           주인이 결정을 바꿨습니다: 같이 운동하자고 맺은 사이에서는 "화요일에
           헬스 갔네" 가 바로 그 확인이라고. 여전히 한 번 눌러 끌 수 있습니다. */
        if (s.schedule) {
          if (p.plannedDays != null) {
            o.plannedDays = p.plannedDays;
            o.keptDays = p.keptDays;
            o.missedDays = p.missedDays;
            o.openDays = p.openDays;
          }
          if (p.week && typeof p.week === 'object') o.week = p.week;
        }
        /* 오늘 식단 — 먹은 칼로리·탄단지와 목표. 몸 수치는 아닙니다. */
        if (s.diet && p.today && typeof p.today === 'object') o.today = p.today;
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

module.exports = { open, makeApi, SHARE_FIELDS, blankShare, nowISO, str, HEALTH_CONSENT_VERSION };
