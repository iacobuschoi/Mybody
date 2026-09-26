/* =============================================================================
 * server/fcm.js — 앱 알림 (Firebase Cloud Messaging HTTP v1). 의존성 0.
 *
 * 왜 있는가
 *   친구의 운동 독촉이 앱이 아니라 크롬(웹 푸시)으로 왔습니다. 앱에는 서버가
 *   밀어 주는 알림 길이 없었고, 앱은 켜질 때만 독촉을 가져갔기 때문입니다.
 *   안드로이드는 FCM 이 직접, 아이폰은 FCM 이 APNs 로 넘겨 줍니다 — 서버는
 *   FCM 하나만 부르면 됩니다.
 *
 * 왜 직접 짜는가
 *   push.js 와 같은 이유입니다. 필요한 것은 RS256 서명 하나와 HTTPS 두 번
 *   (접근 토큰 받기 · 보내기)뿐이고, 둘 다 node:crypto 와 fetch 로 됩니다.
 *   firebase-admin 을 들이면 수십 개 패키지의 갱신과 공급망이 이 서버의
 *   문제가 됩니다.
 *
 * 설정이 없으면
 *   서비스 계정 파일(~/.mybody/fcm-service-account.json)이 없거나 망가졌으면
 *   null 을 돌려주고 끝입니다. 서버는 예전처럼 웹 푸시만으로 돕니다.
 *   저장소는 공개라 이 파일은 절대 저장소 안에 두지 않습니다(.gitignore).
 *
 * 조용히 실패하는 자리들 (전부 다루고 있습니다)
 *   · 앱을 지웠거나 토큰이 바뀜 → UNREGISTERED 등은 gone 으로 돌려주고,
 *     server.js 가 그 기기 행을 지웁니다.
 *   · 서비스 계정 열쇠를 폐기함 · 컴퓨터 시계가 어긋남 → 토큰 교환이
 *     invalid_grant 로 실패합니다. 5분 동안 다시 묻지 않고 한 번만 찍습니다.
 *     매 건마다 물으면 구글에 헛요청을 쏟고 로그가 같은 줄로 묻힙니다.
 *   · APNs 키를 Firebase 에 안 올림 → 아이폰만 THIRD_PARTY_AUTH_ERROR.
 *     기기 잘못이 아니므로 지우지 않고, 할 일을 한 번 찍습니다.
 *   · FCM 이 잠깐 죽음(429 · 5xx · 네트워크) → 지우지 않고 셉니다.
 *     한 번 삐끗했다고 지우면 그 사람은 앱을 다시 켤 때까지 알림을 못 받습니다.
 *
 * 로그
 *   기기 토큰은 앞 8자만 찍습니다. 로그는 회전도 보유 기간도 없이 쌓이므로
 *   기기를 가리키는 식별자를 통째로 남기지 않습니다.
 *
 * 본문은 구글 · 애플이 읽습니다
 *   웹 푸시(push.js)는 종단 암호화라 중계하는 쪽이 본문을 못 읽지만, FCM 의
 *   notification 은 평문입니다. 그래서 여기로 오는 제목 · 본문에는 이름 · 숫자 ·
 *   공유 설정을 넣지 않습니다(server.js 가 일반 문구만 줍니다). 같은 친구의
 *   알림을 한 칸에 모으는 tag 도 사용자 id 대신 받는 사람별 HMAC(tagFor)입니다.
 * ========================================================================== */
'use strict';
const crypto = require('node:crypto');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const SCOPE = 'https://www.googleapis.com/auth/firebase.messaging';
const TOKEN_URL = 'https://oauth2.googleapis.com/token';
const FCM_BASE = 'https://fcm.googleapis.com';
const GRANT = 'urn:ietf:params:oauth:grant-type:jwt-bearer';
/* 앱이 만들어 두는 알림 채널(nudge.dart 의 'friends')과 같은 이름이어야
   합니다. 다르면 안드로이드가 '기타' 채널로 띄우고, 사람이 그 채널을 끄면
   친구 알림이 전부 사라집니다. */
const CHANNEL = 'friends';
/* 흰색 단색 아이콘(res/drawable/ic_stat_mybody). 컬러 아이콘을 쓰면 상태바에
   흰 덩어리로 나옵니다. */
const ICON = 'ic_stat_mybody';
/* 구글이 주는 토큰은 한 시간짜리입니다. 끝나기 직전에 쓰다 401 을 받지
   않게 55분만 씁니다. */
const TOKEN_LIFE_MAX_SEC = 55 * 60;
const FAIL_WAIT_MS = 5 * 60 * 1000;
const NET_WAIT_MS = 30 * 1000;
/* fetch 에는 기본 시간 제한이 없습니다. FCM 이 연결을 붙든 채 답을 안 주면
   그 사람의 알림 루프가 영원히 멈춥니다. */
const TIMEOUT_MS = 10 * 1000;

const b64u = buf => Buffer.from(buf).toString('base64')
  .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');

/** 로그에 남길 기기 토큰 — 앞 8자만. */
function mask(t) {
  const s = String(t || '');
  return s ? s.slice(0, 8) + '…' : '(없음)';
}

function isHttps(u) {
  if (!u) return false;
  try { return new URL(String(u)).protocol === 'https:'; } catch (e) { return false; }
}

/* 시험용 주소 덮어쓰기(FCM_BASE_URL · FCM_TOKEN_URL)는 이 컴퓨터 안(localhost)이거나
   NODE_ENV=test 일 때만 받습니다. 운영 서버에 시험 설정이 새어 들어가면 진짜 접근
   토큰(Bearer)과 알림 본문이 조용히 남의 호스트로 가기 때문입니다. */
const LOOPBACK = new Set(['localhost', '127.0.0.1', '[::1]', '::1']);
function testUrlOk(u, env) {
  if (!isHttps(u)) return false;
  if (env && env.NODE_ENV === 'test') return true;
  try { return LOOPBACK.has(new URL(String(u)).hostname); } catch (e) { return false; }
}

/* 서비스 계정 파일은 사람이 직접 놓으므로 맥 · 리눅스 기본 umask 에서는 644(모두 읽기)로
   남습니다. 같은 컴퓨터의 다른 계정이 읽으면 우리 이름으로 알림을 쏠 수 있어서, 뜰 때
   한 줄로 알려 줍니다(고치지는 않습니다 — 남의 파일 권한을 서버가 바꾸면 놀랍니다). */
function looseModeWarning(file, platform) {
  if ((platform || process.platform) === 'win32') return '';
  let st;
  try { st = fs.statSync(file); } catch (e) { return ''; }
  if (!(st.mode & 0o077)) return '';
  return '서비스 계정 파일을 다른 사용자도 읽을 수 있습니다 (권한 ' +
         (st.mode & 0o777).toString(8) + ') — chmod 600 ' + displayPath(file);
}

function timeoutSignal() {
  try { return AbortSignal.timeout(TIMEOUT_MS); } catch (e) { return undefined; }
}

/* --- 설정 파일 ------------------------------------------------------------ */
/** 기본 위치. config.json 과 같은 폴더입니다(윈도우면 %USERPROFILE%\.mybody). */
function defaultPath() {
  return path.join(os.homedir(), '.mybody', 'fcm-service-account.json');
}

/** 환경변수 FCM_SERVICE_ACCOUNT(경로)가 이깁니다. 설정 파일의 fcmServiceAccount 는
 *  server.js 가 이 환경변수로 옮겨 줍니다. */
function resolvePath(env) {
  const v = String((env && env.FCM_SERVICE_ACCOUNT) || '').trim();
  if (!v) return defaultPath();
  /* 설정 파일에 "~/..." 로 적는 사람이 많습니다. 셸이 아니라서 아무도
     풀어 주지 않으므로 여기서 풉니다. */
  if (v === '~' || v.startsWith('~/') || v.startsWith('~\\')) return path.join(os.homedir(), v.slice(1));
  return path.resolve(v);
}

/** 화면에 찍을 경로 — 홈은 ~ 로 줄입니다(사용자 이름이 로그에 덜 남게). */
function displayPath(file) {
  const home = os.homedir();
  return home && file.startsWith(home) ? '~' + file.slice(home.length) : file;
}

/**
 * 서비스 계정 JSON 을 읽습니다.
 * @returns {{sa: object|null, why: string}} why 는 꺼진 이유(사람 말)
 */
function readServiceAccount(file) {
  let raw;
  try { raw = fs.readFileSync(file, 'utf8'); }
  catch (e) { return { sa: null, why: e && e.code === 'ENOENT' ? '파일 없음' : '파일을 읽을 수 없음' }; }
  let j;
  try { j = JSON.parse(raw); } catch (e) { return { sa: null, why: 'JSON 이 아님' }; }
  if (!j || typeof j !== 'object' || Array.isArray(j)) return { sa: null, why: 'JSON 객체가 아님' };
  /* google-services.json(앱 설정)을 잘못 놓는 일이 흔합니다. 그건 비밀이
     아니고 보내기에는 못 씁니다 — type 으로 가릅니다. */
  if (j.type !== 'service_account') return { sa: null, why: '서비스 계정 파일이 아님 (type 이 service_account 가 아님)' };
  for (const k of ['project_id', 'client_email', 'private_key']) {
    if (typeof j[k] !== 'string' || !j[k].trim()) return { sa: null, why: k + ' 가 없음' };
  }
  let key;
  try { key = crypto.createPrivateKey(j.private_key); }
  catch (e) { return { sa: null, why: '개인 키를 읽을 수 없음' }; }
  if (key.asymmetricKeyType !== 'rsa') return { sa: null, why: 'RSA 키가 아님' };
  return {
    sa: {
      projectId: j.project_id.trim(),
      clientEmail: j.client_email.trim(),
      privateKeyId: typeof j.private_key_id === 'string' ? j.private_key_id : '',
      key,
      /* 파일이 가리키는 토큰 주소는 https 일 때만 믿습니다. 서명한 assertion 이
         평문으로 새지 않게. */
      tokenUri: isHttps(j.token_uri) ? String(j.token_uri) : TOKEN_URL
    },
    why: ''
  };
}

function loadServiceAccount(file) { return readServiceAccount(file).sa; }

/* --- 접근 토큰 ------------------------------------------------------------ */
/**
 * 구글 OAuth 에 내는 JWT (RS256).
 * RSA 열쇠로 crypto.sign('sha256', …) 을 하면 PKCS#1 v1.5 서명이 나오고,
 * 그게 그대로 RS256 입니다 — ES256 처럼 모양을 바꿀 필요가 없습니다.
 */
function assertion(sa, nowSec, aud) {
  const h = { alg: 'RS256', typ: 'JWT' };
  if (sa.privateKeyId) h.kid = sa.privateKeyId;
  const c = { iss: sa.clientEmail, scope: SCOPE, aud: aud || sa.tokenUri,
              iat: nowSec, exp: nowSec + 3600 };
  const input = b64u(JSON.stringify(h)) + '.' + b64u(JSON.stringify(c));
  return input + '.' + b64u(crypto.sign('sha256', Buffer.from(input), sa.key));
}

/* --- 보낼 본문 ------------------------------------------------------------ */
/* FCM 이 data 에 못 쓰게 막아 둔 이름들. 들어가면 보내기 자체가 400 입니다. */
const RESERVED = /^(from|notification|message_type|collapse_key)$|^(google|gcm)(\.|$)/i;

/**
 * note: { t, b, route, kind, tag, data }
 *   t · b  알림 제목 · 본문
 *   route  앱이 누르면 갈 곳('pokes' · 'social'). 모르는 값은 앱이 버립니다.
 *   kind   무슨 소식인가 — 앱이 앞에 떠 있을 때 고르는 데 씁니다.
 *   tag    같은 tag 는 알림 한 칸을 덮어씁니다(64바이트 이하).
 */
function buildMessage(token, note) {
  const n = note || {};
  const data = {};
  const extra = n.data && typeof n.data === 'object' ? n.data : {};
  for (const k of Object.keys(extra)) {
    const v = extra[k];
    if (v === undefined || v === null || RESERVED.test(k)) continue;
    data[k] = String(v);       // FCM 의 data 값은 전부 문자열이어야 합니다
  }
  if (n.route) data.route = String(n.route);
  if (n.kind) data.kind = String(n.kind);
  const tag = typeof n.tag === 'string' && n.tag && Buffer.byteLength(n.tag) <= 64 ? n.tag : '';
  /* 앱이 앞에 떠 있으면(안드로이드) 앱이 직접 띄우는데, 같은 tag 로 띄워야 뒤에 있을 때
     시스템이 띄운 것과 한 칸을 씁니다. 그래서 data 로도 넘깁니다. */
  if (tag) data.tag = tag;

  const androidNote = { channel_id: CHANNEL, icon: ICON };
  if (tag) androidNote.tag = tag;
  const apnsHeaders = { 'apns-priority': '10', 'apns-push-type': 'alert' };
  if (tag) apnsHeaders['apns-collapse-id'] = tag;
  return {
    message: {
      token: String(token),
      notification: { title: String(n.t || ''), body: String(n.b || '') },
      data,
      /* HIGH 가 아니면 절전 중인 안드로이드가 몇 시간씩 미룹니다. 독촉은
         그날 안에 닿아야 뜻이 있습니다. 하루가 지난 독촉은 버립니다. */
      android: { priority: 'HIGH', ttl: '86400s', notification: androidNote },
      apns: { headers: apnsHeaders,
              payload: { aps: { sound: 'default', 'thread-id': CHANNEL } } }
    }
  };
}

/* --- 오류 해석 ------------------------------------------------------------ */
/**
 * FCM 응답을 { ok, status, gone, code } 로 읽습니다. 다시 보내지는 않습니다.
 * gone=true 면 그 토큰은 영영 안 되므로 지워야 합니다.
 */
function classify(status, body) {
  const ok = status >= 200 && status < 300;
  if (ok) return { ok: true, status, gone: false, code: '' };
  const err = (body && typeof body === 'object' && body.error) || {};
  const details = Array.isArray(err.details) ? err.details : [];
  let code = '';
  for (const d of details) {
    if (d && /google\.firebase\.fcm\.v1\.FcmError$/.test(String(d['@type'] || '')) && d.errorCode) {
      code = String(d.errorCode);
    }
  }
  if (!code && typeof err.status === 'string') code = err.status;
  const tokenField = details.some(d => d && /google\.rpc\.BadRequest$/.test(String(d['@type'] || '')) &&
    Array.isArray(d.fieldViolations) &&
    d.fieldViolations.some(v => v && v.field === 'message.token'));
  /* 지우는 것은 "그 기기가 없다" 가 확실할 때뿐입니다.
     · 404 는 UNREGISTERED 일 때만 — 코드 없는 404 는 보내는 주소(프로젝트 경로)가
       틀린 것일 수 있고, 그때 지우면 모든 사람의 기기가 한꺼번에 사라집니다.
     · SENDER_ID_MISMATCH 는 지우지 않습니다 — 서버의 서비스 계정이 앱의 설정 파일과
       다른 프로젝트 것이면 **모든** 기기가 이 코드를 받습니다. 지우면 앱이 12시간 뒤
       다시 등록하고 또 지워지는 일이 끝없이 되풀이되고, 로그는 "없는 기기" 로만 찍혀
       설정 문제라는 것이 드러나지 않습니다. 정말 다른 프로젝트의 토큰이면 그
       로그인이 만료될 때 같이 지워집니다(db.js pruneExpiredSessions). */
  const gone = code === 'UNREGISTERED' ||
               (status === 400 && code === 'INVALID_ARGUMENT' && tokenField);
  return { ok: false, status, gone, code };
}

/* --- 보내는 쪽 ------------------------------------------------------------ */
/**
 * @param {object} o
 *   sa         readServiceAccount 의 sa
 *   fetchImpl  시험에서 가짜로 바꿉니다
 *   now        시험용 시계 (ms)
 *   fcmBase    시험용 가짜 FCM — https 이면서 localhost 이거나 env.NODE_ENV=test 일 때만
 *   tokenUrl   시험용 가짜 OAuth — 조건은 위와 같습니다
 *   env        위 조건을 볼 환경(기본 process.env)
 *   log        한 줄 찍기
 */
function createSender(o) {
  const opts = o || {};
  const sa = opts.sa;
  if (!sa || !sa.key) throw new Error('서비스 계정이 필요합니다');
  const f = opts.fetchImpl || ((u, init) => globalThis.fetch(u, init));
  const now = opts.now || Date.now;
  const log = opts.log || (m => console.log(m));
  const env = opts.env || process.env;
  const base = (testUrlOk(opts.fcmBase, env) ? String(opts.fcmBase) : FCM_BASE).replace(/\/+$/, '');
  const tokenUrl = testUrlOk(opts.tokenUrl, env) ? String(opts.tokenUrl) : sa.tokenUri;
  const sendUrl = base + '/v1/projects/' + encodeURIComponent(sa.projectId) + '/messages:send';

  let cached = null;        // { value, exp }
  let pending = null;       // 토큰 요청이 겹치지 않게 하나만
  let restUntil = 0;        // 실패한 뒤 쉬는 끝
  const said = new Set();
  const once = (key, msg) => {
    if (said.has(key)) return;
    said.add(key);
    try { log(msg); } catch (e) {}
  };
  const stats = { tokenFetches: 0 };

  /* 알림 칸을 모으는 tag 용 열쇠. 서비스 계정의 개인 키에서 끌어냅니다 — 서버를 다시
     띄워도 같은 값이라 칸이 이어지고, 열쇠가 없는 사람은 tag 에서 사용자 id 를 거꾸로
     찾지 못합니다. 받는 사람마다 값이 달라 여러 사람의 알림을 서로 잇지도 못합니다. */
  const tagKey = crypto.createHash('sha256').update('mybody-fcm-tag-v1\n')
    .update(sa.key.export({ type: 'pkcs8', format: 'der' })).digest();
  function tagFor(prefix, recipient, subject) {
    const h = crypto.createHmac('sha256', tagKey)
      .update(String(recipient)).update('\n').update(String(subject)).digest();
    return String(prefix) + '-' + b64u(h.subarray(0, 16));
  }

  async function fetchToken() {
    stats.tokenFetches++;
    const t0 = now();
    const body = new URLSearchParams({
      grant_type: GRANT, assertion: assertion(sa, Math.floor(t0 / 1000), tokenUrl)
    }).toString();
    let res;
    try {
      res = await f(tokenUrl, { method: 'POST',
        headers: { 'content-type': 'application/x-www-form-urlencoded' },
        body, signal: timeoutSignal() });
    } catch (e) {
      throw Object.assign(new Error('토큰 서버에 닿지 못했습니다'), { transient: true });
    }
    let j = null;
    try { j = await res.json(); } catch (e) {}
    if (!res.ok || !j || typeof j.access_token !== 'string' || !j.access_token) {
      const why = (j && (j.error_description || j.error)) || ('HTTP ' + res.status);
      throw Object.assign(new Error(String(why)), {
        transient: res.status === 429 || res.status >= 500, oauth: j && j.error
      });
    }
    const life = Math.max(60, Math.min(TOKEN_LIFE_MAX_SEC, (Number(j.expires_in) || 3600) - 60));
    cached = { value: j.access_token, exp: t0 + life * 1000 };
    said.delete('token-fail');      // 되살아났으면 다음 실패는 다시 알립니다
    return cached.value;
  }

  function accessToken() {
    if (cached && now() < cached.exp) return Promise.resolve(cached.value);
    if (now() < restUntil) return Promise.reject(Object.assign(new Error('토큰 실패 뒤 쉬는 중'), { resting: true }));
    if (!pending) {
      pending = fetchToken().catch(e => {
        restUntil = now() + (e.transient ? NET_WAIT_MS : FAIL_WAIT_MS);
        const hint = e.oauth === 'invalid_grant'
          ? ' — 서비스 계정 열쇠가 폐기됐거나 이 컴퓨터 시계가 틀렸습니다. Firebase 콘솔에서 새 열쇠를 받아 '
            + '같은 자리에 두고 서버를 다시 띄우세요'
          : '';
        once('token-fail', '앱 알림(FCM): 접근 토큰을 못 받았습니다 (' + e.message + ')' + hint);
        throw e;
      }).finally(() => { pending = null; });
    }
    return pending;
  }

  /** 기기 하나에 한 건. 던지지 않습니다. */
  async function send(token, note) {
    const tok = String(token || '');
    if (!tok) return { ok: false, status: 0, gone: false, code: 'NO_TOKEN' };
    let bearer;
    try { bearer = await accessToken(); }
    catch (e) { return { ok: false, status: 0, gone: false, code: 'AUTH' }; }
    let res;
    try {
      res = await f(sendUrl, { method: 'POST',
        headers: { authorization: 'Bearer ' + bearer, 'content-type': 'application/json; charset=utf-8' },
        body: JSON.stringify(buildMessage(tok, note)), signal: timeoutSignal() });
    } catch (e) {
      /* 네트워크가 안 되는 것은 기기 잘못이 아닙니다 — 지우면 안 됩니다. */
      return { ok: false, status: 0, gone: false, code: 'NETWORK' };
    }
    let j = null;
    try { j = await res.json(); } catch (e) {}
    const r = classify(res.status, j);
    if (r.status === 401 && r.code !== 'THIRD_PARTY_AUTH_ERROR') {
      /* 토큰이 중간에 무효가 됐습니다. 버려 두면 다음 건이 새로 받습니다. */
      if (cached && cached.value === bearer) cached = null;
    }
    if (r.code === 'THIRD_PARTY_AUTH_ERROR') {
      once('apns', '앱 알림(FCM): 아이폰으로 못 보냈습니다 — Firebase 콘솔 → 프로젝트 설정 → '
        + '클라우드 메시징 → Apple 앱 구성에 APNs 인증 키(.p8)를 올리세요');
    } else if (r.code === 'SENDER_ID_MISMATCH') {
      once('sender', '앱 알림(FCM): 이 서버의 서비스 계정(프로젝트 ' + sa.projectId + ')과 앱에 든 '
        + 'Firebase 설정이 다른 프로젝트입니다 (403 SENDER_ID_MISMATCH) — 기기는 지우지 않습니다. '
        + '서비스 계정을 앱과 같은 프로젝트에서 받아 같은 자리에 두고 서버를 다시 띄우세요');
    } else if (r.status === 404 && !r.gone) {
      once('not-found', '앱 알림(FCM): 보내는 주소를 FCM 이 모릅니다 (404 ' + (r.code || '코드 없음') + ') — '
        + '기기는 지우지 않습니다. 서비스 계정의 project_id(' + sa.projectId + ')가 맞는지 보세요');
    } else if (r.gone) {
      log('앱 알림(FCM): 더는 없는 기기 ' + mask(tok) + ' 를 정리합니다 (' + (r.code || r.status) + ')');
    } else if (r.status === 400) {
      once('bad-request', '앱 알림(FCM): FCM 이 보낸 본문을 거절했습니다 (400 ' + r.code + ') — 서버 쪽 문제입니다');
    } else if (r.status === 403) {
      once('forbidden', '앱 알림(FCM): 권한이 없습니다 (403 ' + r.code + ') — Google Cloud 에서 '
        + 'Firebase Cloud Messaging API 가 켜져 있는지, 서비스 계정이 그 프로젝트 것인지 확인하세요');
    }
    return r;
  }

  return {
    projectId: sa.projectId,
    clientEmail: sa.clientEmail,
    send,
    accessToken,
    tagFor,
    base,
    tokenUrl,
    _stats: stats
  };
}

/**
 * 환경변수로 정해진 파일을 읽어 보내는 쪽을 만듭니다.
 * @returns {{sender: object|null, file: string, why: string, warnings: string[]}}
 *   warnings 는 켜졌지만 주인이 알아야 할 것(파일 권한 · 시험용 주소) — 서버가 뜰 때 한 줄씩 찍습니다.
 */
function load(env, o) {
  const e = env || process.env;
  const opts = o || {};
  const file = resolvePath(e);
  const r = readServiceAccount(file);
  if (!r.sa) return { sender: null, file, why: r.why, warnings: [] };
  const warnings = [];
  const loose = looseModeWarning(file, opts.platform);
  if (loose) warnings.push(loose);
  for (const k of ['FCM_BASE_URL', 'FCM_TOKEN_URL']) {
    const v = String(e[k] || '').trim();
    if (!v) continue;
    warnings.push(testUrlOk(v, e)
      ? '시험용 FCM 주소 사용 중 (' + k + ') — 운영 서버라면 이 환경변수를 지우세요'
      : k + ' 를 무시합니다 — 시험용이라 https 이면서 localhost 이거나 NODE_ENV=test 일 때만 받습니다');
  }
  const sender = createSender({ sa: r.sa, fcmBase: e.FCM_BASE_URL, tokenUrl: e.FCM_TOKEN_URL, env: e,
                                fetchImpl: opts.fetchImpl, now: opts.now, log: opts.log });
  return { sender, file, why: '', warnings };
}

/** 설정이 없으면 null — 조용히 꺼집니다. */
function fromEnv(env, o) { return load(env, o).sender; }

/** 서버가 뜰 때 찍는 한 줄. */
function describe(state) {
  if (state && state.sender) {
    return '켜짐 — 프로젝트 ' + state.sender.projectId;
  }
  return '꺼짐 — ' + displayPath((state && state.file) || defaultPath()) +
         ' ' + ((state && state.why) || '파일 없음');
}

module.exports = {
  SCOPE, TOKEN_URL, FCM_BASE, CHANNEL, ICON,
  defaultPath, resolvePath, readServiceAccount, loadServiceAccount, looseModeWarning, testUrlOk,
  assertion, buildMessage, classify, createSender, load, fromEnv, describe, mask, b64u
};
