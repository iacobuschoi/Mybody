/* =============================================================================
 * server/push.js — 웹푸시 (VAPID + aes128gcm). 의존성 0.
 *
 * 왜 직접 짜는가
 *   이 저장소는 node 내장 모듈만 씁니다. 웹푸시에 필요한 것은 전부
 *   node:crypto 안에 있습니다 — P-256 ECDH, HKDF-SHA256, AES-128-GCM,
 *   그리고 ES256 서명. 라이브러리 하나를 들이면 그 라이브러리의 갱신과
 *   공급망까지 이 앱의 문제가 됩니다.
 *
 * 무엇을 보내는가
 *   "나린님이 운동했습니다 · 이번 주 3일째" 같은 한 줄뿐입니다.
 *   **늘어난 것만** 보냅니다 — 안 한 것은 푸시가 될 수 없습니다.
 *   news.js 와 같은 규칙이고, 이건 못 만든 게 아니라 만들 수 없게
 *   만들어 둔 것입니다.
 *
 * 조용히 실패하는 자리들 (전부 다루고 있습니다)
 *   · 구독이 만료됨 → 404/410 이면 그 구독을 지웁니다.
 *   · 푸시 서비스가 잠깐 죽음 → 429/5xx 는 지우지 않고 실패만 셉니다.
 *   · HTTPS 가 아님 → 브라우저에 서비스워커가 없어서 구독 자체가 안 됩니다.
 *     그 경우 화면이 "폰 알림은 터널(HTTPS)로 열었을 때만 됩니다" 라고 말합니다.
 *
 * 암호 구현 메모 (밟았던 자리)
 *   · crypto.sign('sha256', buf, {key, dsaEncoding:'ieee-p1363'}) 가 ES256 이
 *     요구하는 raw R‖S 64바이트를 바로 줍니다. createSign 을 쓰면 DER 이
 *     나와서 직접 잘라야 하고, 그 변환이 흔한 버그 자리입니다.
 *   · crypto.hkdfSync 는 **ArrayBuffer** 를 돌려줍니다. 다음 hkdf 에 그대로
 *     넣으면 조용히 틀린 키가 나옵니다 — Buffer.from() 으로 감싸야 합니다.
 *   · SPKI DER 의 마지막 65바이트가 브라우저가 applicationServerKey 로 받는
 *     비압축 점(0x04 로 시작)입니다.
 * ========================================================================== */
'use strict';
const crypto = require('node:crypto');

/* --- base64url ----------------------------------------------------------- */
const b64u = buf => Buffer.from(buf).toString('base64')
  .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const unb64u = s => Buffer.from(String(s).replace(/-/g, '+').replace(/_/g, '/'), 'base64');

/* --- VAPID 키 ------------------------------------------------------------ */
/** 새 키 한 쌍. publicKey 는 브라우저에 그대로 주는 비압축 점입니다. */
function generateVapid() {
  const { publicKey, privateKey } = crypto.generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
  const spki = publicKey.export({ type: 'spki', format: 'der' });
  const raw = spki.subarray(spki.length - 65);        // 0x04 || X(32) || Y(32)
  if (raw[0] !== 0x04) throw new Error('예상 못 한 공개키 형식입니다');
  const pkcs8 = privateKey.export({ type: 'pkcs8', format: 'der' });
  return { publicKey: b64u(raw), privateKey: b64u(pkcs8) };
}

function vapidKeyObject(privateKeyB64u) {
  return crypto.createPrivateKey({
    key: unb64u(privateKeyB64u), format: 'der', type: 'pkcs8'
  });
}

/**
 * VAPID Authorization 헤더.
 * aud 는 엔드포인트의 origin, sub 는 연락 수단(mailto: 또는 https:).
 * exp 는 12시간 — RFC8292 는 24시간을 넘기지 말라고 합니다.
 */
function vapidHeader(endpoint, { publicKey, privateKey, subject }, nowSec) {
  const aud = new URL(endpoint).origin;
  const now = nowSec || Math.floor(Date.now() / 1000);
  const header = b64u(JSON.stringify({ typ: 'JWT', alg: 'ES256' }));
  const body = b64u(JSON.stringify({ aud, exp: now + 12 * 3600, sub: subject }));
  const signed = header + '.' + body;
  const sig = crypto.sign('sha256', Buffer.from(signed), {
    key: vapidKeyObject(privateKey), dsaEncoding: 'ieee-p1363'
  });
  return 'vapid t=' + signed + '.' + b64u(sig) + ', k=' + publicKey;
}

/* --- 본문 암호화 (RFC 8291 / aes128gcm) ---------------------------------- */
const hkdf = (salt, ikm, info, len) =>
  Buffer.from(crypto.hkdfSync('sha256', ikm, salt, info, len));

/**
 * plaintext(문자열|Buffer) 를 구독자에게 보낼 본문으로 만듭니다.
 * sub: { p256dh, auth }  — 브라우저 PushSubscription 의 keys 그대로.
 * 반환: Buffer (헤더 86바이트 + 암호문)
 *
 * salt 와 보내는 쪽 키는 매번 새로 만듭니다. 고정하면 같은 키로 두 번
 * 암호화하는 셈이라 GCM 의 전제가 깨집니다.
 */
function encrypt(plaintext, sub, opts) {
  const uaPublic = unb64u(sub.p256dh);
  const authSecret = unb64u(sub.auth);
  if (uaPublic.length !== 65 || uaPublic[0] !== 0x04) throw new Error('구독자 공개키 형식 오류');
  if (authSecret.length !== 16) throw new Error('auth 비밀 길이 오류');

  const salt = (opts && opts.salt) || crypto.randomBytes(16);
  const ecdh = crypto.createECDH('prime256v1');
  if (opts && opts.asPrivate) ecdh.setPrivateKey(opts.asPrivate);
  else ecdh.generateKeys();
  const asPublic = ecdh.getPublicKey();                 // 65바이트 비압축
  const shared = ecdh.computeSecret(uaPublic);

  /* RFC 8291 §3.3 — auth 비밀로 먼저 한 번 늘립니다.
     key_info 는 "WebPush: info" || 0x00 || ua_public || as_public */
  const keyInfo = Buffer.concat([
    Buffer.from('WebPush: info\0'), uaPublic, asPublic
  ]);
  const ikm = hkdf(authSecret, shared, keyInfo, 32);

  const cek = hkdf(salt, ikm, Buffer.from('Content-Encoding: aes128gcm\0'), 16);
  const nonce = hkdf(salt, ikm, Buffer.from('Content-Encoding: nonce\0'), 12);

  /* aes128gcm 은 레코드마다 구분자를 붙입니다. 마지막(이자 유일한)
     레코드는 0x02 입니다. 이걸 0x01 로 두면 받는 쪽이 "더 있다" 고
     기다리다 버립니다 — 조용히 안 뜨는 알림의 흔한 원인입니다. */
  const body = Buffer.concat([Buffer.from(plaintext), Buffer.from([0x02])]);
  const cipher = crypto.createCipheriv('aes-128-gcm', cek, nonce);
  const ct = Buffer.concat([cipher.update(body), cipher.final(), cipher.getAuthTag()]);

  const rs = Buffer.alloc(4);
  rs.writeUInt32BE(4096, 0);
  const header = Buffer.concat([salt, rs, Buffer.from([asPublic.length]), asPublic]);
  return Buffer.concat([header, ct]);
}

/** 받는 쪽. 우리 구현을 우리가 검산하려고 둡니다 (시험에서 씁니다). */
function decrypt(body, uaPrivate, authSecretB64u) {
  const salt = body.subarray(0, 16);
  const idlen = body[20];
  const asPublic = body.subarray(21, 21 + idlen);
  const ct = body.subarray(21 + idlen);

  const ecdh = crypto.createECDH('prime256v1');
  ecdh.setPrivateKey(uaPrivate);
  const uaPublic = ecdh.getPublicKey();
  const shared = ecdh.computeSecret(asPublic);
  const authSecret = unb64u(authSecretB64u);

  const ikm = hkdf(authSecret, shared,
    Buffer.concat([Buffer.from('WebPush: info\0'), uaPublic, asPublic]), 32);
  const cek = hkdf(salt, ikm, Buffer.from('Content-Encoding: aes128gcm\0'), 16);
  const nonce = hkdf(salt, ikm, Buffer.from('Content-Encoding: nonce\0'), 12);

  const tag = ct.subarray(ct.length - 16);
  const d = crypto.createDecipheriv('aes-128-gcm', cek, nonce);
  d.setAuthTag(tag);
  const out = Buffer.concat([d.update(ct.subarray(0, ct.length - 16)), d.final()]);
  // 마지막 바이트는 레코드 구분자입니다
  let end = out.length - 1;
  while (end >= 0 && out[end] === 0x00) end--;
  return out.subarray(0, end);
}

/* --- 보내기 --------------------------------------------------------------- */
/**
 * 한 구독에 한 건 보냅니다.
 * 반환: { ok, status, gone }  gone=true 면 그 구독을 지워야 합니다.
 */
async function send(sub, payload, vapid, fetchImpl) {
  const f = fetchImpl || globalThis.fetch;
  let body;
  try { body = encrypt(payload, sub); }
  catch (e) { return { ok: false, status: 0, gone: false, reason: e.message }; }

  let res;
  try {
    res = await f(sub.endpoint, {
      method: 'POST',
      headers: {
        'TTL': '86400',
        'Content-Encoding': 'aes128gcm',
        'Content-Type': 'application/octet-stream',
        'Content-Length': String(body.length),
        'Urgency': 'normal',
        'Authorization': vapidHeader(sub.endpoint, vapid)
      },
      body
    });
  } catch (e) {
    /* 네트워크가 안 되는 것은 구독 잘못이 아닙니다 — 지우면 안 됩니다. */
    return { ok: false, status: 0, gone: false, reason: String(e && e.message || e) };
  }

  /* 404 · 410 은 "이 구독은 이제 없다" 는 뜻입니다 (폰을 초기화했거나
     알림을 껐거나). 그 외의 실패는 잠깐일 수 있으므로 살려 둡니다 —
     한 번 삐끗했다고 지우면 그 사람은 다시 켤 때까지 알림이 영영 안 옵니다. */
  const gone = res.status === 404 || res.status === 410;
  return { ok: res.status >= 200 && res.status < 300, status: res.status, gone };
}

module.exports = { generateVapid, vapidHeader, encrypt, decrypt, send, b64u, unb64u };
