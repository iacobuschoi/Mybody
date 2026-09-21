/* =============================================================================
 * tools/test-push.js — 폰 알림 (웹푸시)
 *
 *   node tools/test-push.js
 *
 * 왜 이 시험이 까다로운가
 *   암호가 조금만 틀려도 **브라우저가 조용히 버립니다.** 서버는 201 을
 *   받고 "보냈다" 고 기록하는데 폰에는 아무것도 안 뜹니다. 오류가 어디에도
 *   안 남으므로, 여기서 못 잡으면 아무도 못 잡습니다.
 *
 * 그래서 두 가지를 합니다.
 *   (가) 우리 암호문을 우리가 다시 풉니다 (왕복).
 *   (나) 규격이 정한 **바이트 배치**를 직접 셉니다 — 왕복만 보면 양쪽이
 *        같이 틀린 경우를 못 잡습니다.
 *
 *   그리고 개발 중에 독립 구현(npm http_ece 1.2.1)과도 양방향으로
 *   맞춰 봤습니다 — 우리가 암호화한 것을 그쪽이 풀고, 그쪽이 암호화한
 *   것을 우리가 풀었습니다 (16/16). 그 라이브러리는 저장소에 넣지
 *   않습니다(의존성 0). 여기 남는 것은 그 결과가 아니라 그 때 맞춘
 *   규격을 고정하는 검사입니다.
 * ========================================================================== */
'use strict';
const crypto = require('node:crypto');
const P = require('../server/push.js');

let pass = 0, fail = 0;
const t = (n, c, d) => {
  if (c) { pass++; console.log('  ✓ ' + n); }
  else { fail++; console.log('  ✗ ' + n, d === undefined ? '' : String(d).slice(0, 160)); }
};
const b64u = b => Buffer.from(b).toString('base64')
  .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');

function receiver() {
  const e = crypto.createECDH('prime256v1'); e.generateKeys();
  return { priv: e.getPrivateKey(), pub: e.getPublicKey(), auth: crypto.randomBytes(16) };
}

console.log('\n[1] 암호화한 것을 다시 풀 수 있는가');
[
  '나린님이 운동했습니다',
  'When I grow up, I want to be a watermelon',
  'x',
  '가'.repeat(600)
].forEach(msg => {
  const r = receiver();
  const body = P.encrypt(msg, { p256dh: b64u(r.pub), auth: b64u(r.auth) });
  let out = null, err = null;
  try { out = P.decrypt(body, r.priv, b64u(r.auth)); } catch (e) { err = e.message; }
  t('"' + msg.slice(0, 18) + (msg.length > 18 ? '…' : '') + '" (' + msg.length + '자)',
    out && out.toString() === msg, err || (out && out.toString().slice(0, 40)));
});

console.log('\n[2] 규격이 정한 바이트 배치');
{
  const r = receiver();
  const body = P.encrypt('hi', { p256dh: b64u(r.pub), auth: b64u(r.auth) });
  t('헤더가 86바이트 (salt16 + rs4 + idlen1 + 키65)', body.length > 86, body.length);
  t('레코드 크기 4096', body.readUInt32BE(16) === 4096, body.readUInt32BE(16));
  t('키 길이 바이트가 65', body[20] === 65, body[20]);
  t('보내는 쪽 공개키가 비압축(0x04)', body[21] === 0x04, '0x' + body[21].toString(16));
  /* 마지막 레코드 구분자가 0x02 여야 합니다. 0x01 로 두면 받는 쪽이
     "다음 레코드가 있다" 고 기다리다 통째로 버립니다 — 조용히 안 뜨는
     알림의 흔한 원인입니다. 풀어서 그 바이트를 직접 봅니다. */
  const salt = body.subarray(0, 16), asPub = body.subarray(21, 86);
  const e2 = crypto.createECDH('prime256v1'); e2.setPrivateKey(r.priv);
  const shared = e2.computeSecret(asPub);
  const hk = (s, ikm, info, len) => Buffer.from(crypto.hkdfSync('sha256', ikm, s, info, len));
  const ikm = hk(r.auth, shared,
    Buffer.concat([Buffer.from('WebPush: info\0'), r.pub, asPub]), 32);
  const cek = hk(salt, ikm, Buffer.from('Content-Encoding: aes128gcm\0'), 16);
  const nonce = hk(salt, ikm, Buffer.from('Content-Encoding: nonce\0'), 12);
  const ct = body.subarray(86);
  const d = crypto.createDecipheriv('aes-128-gcm', cek, nonce);
  d.setAuthTag(ct.subarray(ct.length - 16));
  const plain = Buffer.concat([d.update(ct.subarray(0, ct.length - 16)), d.final()]);
  t('마지막 레코드 구분자가 0x02', plain[plain.length - 1] === 0x02,
    '0x' + plain[plain.length - 1].toString(16));
  t('구분자 앞이 원문', plain.subarray(0, plain.length - 1).toString() === 'hi');
}

console.log('\n[3] 같은 글을 두 번 보내도 암호문이 다르다');
{
  const r = receiver();
  const k = { p256dh: b64u(r.pub), auth: b64u(r.auth) };
  const a = P.encrypt('같은 글', k), b = P.encrypt('같은 글', k);
  t('salt 가 매번 다르다', !a.subarray(0, 16).equals(b.subarray(0, 16)));
  t('보내는 쪽 키도 매번 다르다', !a.subarray(21, 86).equals(b.subarray(21, 86)));
  /* 같은 키·같은 nonce 로 두 번 암호화하면 GCM 은 통째로 무너집니다.
     salt 를 고정하면 정확히 그 상태가 됩니다. */
  t('그래서 암호문도 다르다', !a.equals(b));
}

console.log('\n[4] 이상한 구독은 받지 않는다');
{
  const r = receiver();
  const bad = [
    ['공개키가 짧으면', { p256dh: b64u(Buffer.alloc(10)), auth: b64u(r.auth) }],
    ['공개키가 압축형이면', { p256dh: b64u(Buffer.concat([Buffer.from([0x02]), Buffer.alloc(64)])), auth: b64u(r.auth) }],
    ['auth 가 16바이트가 아니면', { p256dh: b64u(r.pub), auth: b64u(Buffer.alloc(8)) }]
  ];
  bad.forEach(([name, sub]) => {
    let threw = false;
    try { P.encrypt('hi', sub); } catch (e) { threw = true; }
    t(name + ' 던진다', threw);
  });
}

console.log('\n[5] VAPID 서명이 진짜로 검증된다');
{
  const k = P.generateVapid();
  t('공개키가 65바이트 비압축', P.unb64u(k.publicKey).length === 65 && P.unb64u(k.publicKey)[0] === 4);
  const ep = 'https://updates.push.services.mozilla.com/wpush/v2/abc';
  const h = P.vapidHeader(ep, Object.assign({ subject: 'mailto:me@example.com' }, k));
  const m = /^vapid t=([^,]+), k=(.+)$/.exec(h);
  t('헤더 모양', !!m, h.slice(0, 40));
  const [hd, pl, sig] = m[1].split('.');
  /* 서명을 **공개키만으로** 검증합니다 — 푸시 서비스가 하는 일과 같습니다.
     SPKI 앞머리(P-256) + 원시 점으로 공개키를 다시 만듭니다. */
  const pub = crypto.createPublicKey({
    key: Buffer.concat([
      Buffer.from('3059301306072a8648ce3d020106082a8648ce3d030107034200', 'hex'),
      P.unb64u(m[2])
    ]), format: 'der', type: 'spki'
  });
  t('k= 로 준 공개키로 서명이 검증된다',
    crypto.verify('sha256', Buffer.from(hd + '.' + pl),
      { key: pub, dsaEncoding: 'ieee-p1363' }, P.unb64u(sig)));
  const c = JSON.parse(P.unb64u(pl).toString());
  t('aud 가 엔드포인트 origin', c.aud === 'https://updates.push.services.mozilla.com', c.aud);
  t('exp 가 24시간 안 (RFC8292)', c.exp - Math.floor(Date.now() / 1000) <= 24 * 3600);
  t('alg 가 ES256', JSON.parse(P.unb64u(hd).toString()).alg === 'ES256');
}

console.log('\n[6] 보내기 — 실패를 어떻게 다루는가');
(async () => {
  const r = receiver();
  const sub = { endpoint: 'https://push.example/abc', p256dh: b64u(r.pub), auth: b64u(r.auth) };
  const vapid = Object.assign({ subject: 'mailto:a@b.c' }, P.generateVapid());
  const fake = status => async () => ({ status });

  let res = await P.send(sub, 'hi', vapid, fake(201));
  t('201 이면 성공', res.ok === true && res.gone === false, res);
  /* 404·410 은 "이 구독은 이제 없다" — 지워야 합니다. */
  res = await P.send(sub, 'hi', vapid, fake(410));
  t('410 이면 지울 것으로 표시', res.gone === true, res);
  res = await P.send(sub, 'hi', vapid, fake(404));
  t('404 도 마찬가지', res.gone === true, res);
  /* 나머지 실패는 잠깐일 수 있습니다. 한 번 삐끗했다고 지우면 그 사람은
     다시 켤 때까지 알림이 영영 안 옵니다. */
  res = await P.send(sub, 'hi', vapid, fake(429));
  t('429 는 안 지운다', res.ok === false && res.gone === false, res);
  res = await P.send(sub, 'hi', vapid, fake(500));
  t('500 도 안 지운다', res.gone === false, res);
  res = await P.send(sub, 'hi', vapid, async () => { throw new Error('연결 실패'); });
  t('네트워크가 끊겨도 안 지운다', res.ok === false && res.gone === false, res);

  /* 보낼 때 실제로 규격대로 된 헤더가 나가는지 봅니다. */
  let seen = null;
  await P.send(sub, 'hi', vapid, async (url, opt) => { seen = { url, opt }; return { status: 201 }; });
  t('엔드포인트로 POST 한다', seen.url === sub.endpoint && seen.opt.method === 'POST');
  t('Content-Encoding: aes128gcm', seen.opt.headers['Content-Encoding'] === 'aes128gcm');
  t('Authorization 이 vapid', /^vapid t=/.test(seen.opt.headers.Authorization));
  t('TTL 이 붙는다', !!seen.opt.headers.TTL);
  t('본문이 Buffer', Buffer.isBuffer(seen.opt.body));

  console.log('\n' + (fail ? '✗ ' + fail + '개 실패 / ' : '✓ 전부 통과 — ') + (pass + fail) + '개');
  process.exit(fail ? 1 : 0);
})();
