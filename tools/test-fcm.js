/* =============================================================================
 * tools/test-fcm.js — 앱 알림(FCM)
 *
 *   node tools/test-fcm.js
 *
 * 왜 이 시험이 있나
 *   친구의 운동 독촉이 앱이 아니라 크롬으로 왔습니다. 서버가 앱에 밀어 주는
 *   길(FCM)을 새로 냈고, 여기서 그 길 전체를 봅니다.
 *
 *   진짜 구글을 부르지 않습니다. 가짜 OAuth · 가짜 FCM 을 https 로 세우고,
 *   가짜 OAuth 는 **서버가 낸 JWT 서명을 공개키로 직접 검증**합니다. 중간을
 *   흉내 내면 "서명했다고 생각했는데 구글이 거절한다" 를 못 잡습니다.
 *
 *   제일 중요한 것은 두 가지입니다.
 *     · 누구에게 갔는가 — 공유 설정을 끈 친구에게 운동 소식이 가면 유출입니다.
 *     · 설정이 없을 때 아무것도 안 바뀌는가 — 서비스 계정 파일이 없는 서버는
 *       예전과 똑같이 웹 푸시로만 돌아야 합니다.
 * ========================================================================== */
'use strict';
/* 검사하는 사람의 ~/.mybody 설정(진짜 서비스 계정 파일)이 결과를 바꾸지 않게. */
const TESTENV = require('./testenv.js');
const { spawn, spawnSync } = require('node:child_process');
const https = require('node:https');
const crypto = require('node:crypto');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { DatabaseSync } = require('node:sqlite');

const ROOT = path.join(__dirname, '..');
const FCM = require(path.join(ROOT, 'server', 'fcm.js'));
const PUSH = require(path.join(ROOT, 'server', 'push.js'));
const DBM = require(path.join(ROOT, 'server', 'db.js'));

let pass = 0, fail = 0;
const ok = (n, c, d) => {
  if (c) { pass++; console.log('  ✓', n); }
  else { fail++; console.log('  ✗', n, d === undefined ? '' : JSON.stringify(d).slice(0, 400)); }
};
const wait = ms => new Promise(r => setTimeout(r, ms));
const TMP = fs.mkdtempSync(path.join(os.tmpdir(), 'mybody-fcm-'));
const PW = 'test-password-1';

/* --- 시험용 서비스 계정 --------------------------------------------------- */
const RSA = crypto.generateKeyPairSync('rsa', { modulusLength: 2048 });
const PEM = RSA.privateKey.export({ type: 'pkcs8', format: 'pem' });
function saJson(over) {
  return Object.assign({
    type: 'service_account', project_id: 'mybody-test', private_key_id: 'kid-123',
    private_key: PEM, client_email: 'push@mybody-test.iam.gserviceaccount.com',
    token_uri: 'https://oauth2.googleapis.com/token'
  }, over || {});
}
function writeSa(name, obj) {
  const f = path.join(TMP, name);
  fs.writeFileSync(f, typeof obj === 'string' ? obj : JSON.stringify(obj));
  return f;
}
const unb64u = s => Buffer.from(String(s).replace(/-/g, '+').replace(/_/g, '/'), 'base64');
function parseJwt(jwt) {
  const [h, c, s] = String(jwt).split('.');
  return { header: JSON.parse(unb64u(h)), claims: JSON.parse(unb64u(c)), input: h + '.' + c, sig: unb64u(s) };
}

/* --- 가짜 fetch (단위 시험) ----------------------------------------------- */
function fakeFetch(route) {
  const calls = [];
  const f = async (url, init) => {
    calls.push({ url, init });
    const r = await route(url, init, calls);
    if (r instanceof Error) throw r;
    return { ok: r.status >= 200 && r.status < 300, status: r.status,
             json: async () => { if (r.body === undefined) throw new Error('no body'); return r.body; } };
  };
  f.calls = calls;
  return f;
}
const fcmErr = (status, st, code, extra) => ({ status, body: { error: {
  code: status, status: st, message: 'x',
  details: [].concat(code ? [{ '@type': 'type.googleapis.com/google.firebase.fcm.v1.FcmError', errorCode: code }] : [],
                     extra || []) } } });

async function unit() {
  console.log('\n[1] 서비스 계정 파일 — 없거나 망가졌으면 조용히 꺼진다');
  {
    const good = writeSa('good.json', saJson());
    const sa = FCM.loadServiceAccount(good);
    ok('제대로 된 파일을 읽는다', !!(sa && sa.projectId === 'mybody-test' && sa.clientEmail && sa.key), sa && sa.projectId);
    ok('없는 파일 → null', FCM.loadServiceAccount(path.join(TMP, 'nope.json')) === null);
    ok('없는 이유를 사람 말로 준다', FCM.readServiceAccount(path.join(TMP, 'nope.json')).why === '파일 없음');
    ok('JSON 이 아니면 null', FCM.loadServiceAccount(writeSa('bad.json', '{not json')) === null);
    /* google-services.json(앱 설정)을 잘못 놓는 일이 흔합니다 */
    ok('앱 설정 파일(google-services.json 모양)이면 null',
       FCM.loadServiceAccount(writeSa('gs.json', { project_info: { project_id: 'x' }, client: [] })) === null);
    ok('private_key 가 빠지면 null',
       FCM.loadServiceAccount(writeSa('nokey.json', saJson({ private_key: undefined }))) === null);
    ok('client_email 이 빠지면 null',
       FCM.loadServiceAccount(writeSa('nomail.json', saJson({ client_email: '' }))) === null);
    ok('개인 키가 깨졌으면 null',
       FCM.loadServiceAccount(writeSa('brokenkey.json', saJson({ private_key: '-----BEGIN PRIVATE KEY-----\nAAAA\n-----END PRIVATE KEY-----\n' }))) === null);
    const ec = crypto.generateKeyPairSync('ec', { namedCurve: 'prime256v1' }).privateKey.export({ type: 'pkcs8', format: 'pem' });
    ok('RSA 가 아닌 키면 null', FCM.loadServiceAccount(writeSa('ec.json', saJson({ private_key: ec }))) === null);
    ok('token_uri 가 https 가 아니면 구글 기본 주소를 쓴다',
       FCM.loadServiceAccount(writeSa('http.json', saJson({ token_uri: 'http://evil.example/token' }))).tokenUri === FCM.TOKEN_URL);
    ok('fromEnv — 경로의 파일이 없으면 null',
       FCM.fromEnv({ FCM_SERVICE_ACCOUNT: path.join(TMP, 'nope.json') }) === null);
    ok('fromEnv — 기본 자리(~/.mybody)에 파일이 없으면 null (시험 HOME 은 비어 있음)',
       FCM.fromEnv({}) === null);
    ok('기본 자리는 ~/.mybody/fcm-service-account.json',
       FCM.defaultPath() === path.join(TESTENV.home, '.mybody', 'fcm-service-account.json'), FCM.defaultPath());
    ok('설정에 ~/ 로 적어도 홈으로 푼다',
       FCM.resolvePath({ FCM_SERVICE_ACCOUNT: '~/x/sa.json' }) === path.join(os.homedir(), 'x', 'sa.json'));
    const s = FCM.fromEnv({ FCM_SERVICE_ACCOUNT: good }, { log: () => {} });
    ok('fromEnv — 파일이 있으면 보내는 쪽이 생긴다', !!(s && s.projectId === 'mybody-test'));
    ok('꺼졌을 때 한 줄 설명에 경로와 이유가 있다',
       /꺼짐 — .*fcm-service-account\.json 파일 없음/.test(FCM.describe(FCM.load({}))), FCM.describe(FCM.load({})));

    /* 사람이 직접 놓는 파일이라 umask 대로 644 가 되기 쉽습니다 — 뜰 때 알려야 합니다. */
    const loose = writeSa('loose.json', saJson());
    fs.chmodSync(loose, 0o644);
    const lw = FCM.load({ FCM_SERVICE_ACCOUNT: loose }, { log: () => {}, platform: 'linux' }).warnings;
    ok('남도 읽을 수 있는 파일(644)이면 chmod 600 을 알려 준다', lw.length === 1 && /chmod 600/.test(lw[0]), lw);
    fs.chmodSync(loose, 0o600);
    ok('600 이면 경고 없음',
       FCM.load({ FCM_SERVICE_ACCOUNT: loose }, { log: () => {}, platform: 'linux' }).warnings.length === 0);
    ok('윈도우는 모드 비트가 뜻이 없어 보지 않는다', FCM.looseModeWarning(good, 'win32') === '');
  }

  console.log('\n[2] 구글에 내는 JWT (RS256)');
  {
    const sa = FCM.loadServiceAccount(writeSa('good.json', saJson()));
    const j = parseJwt(FCM.assertion(sa, 1_800_000_000));
    ok('머리: alg RS256 · typ JWT · kid', j.header.alg === 'RS256' && j.header.typ === 'JWT' && j.header.kid === 'kid-123', j.header);
    ok('iss 는 서비스 계정 이메일', j.claims.iss === 'push@mybody-test.iam.gserviceaccount.com');
    ok('scope 는 firebase.messaging', j.claims.scope === 'https://www.googleapis.com/auth/firebase.messaging');
    ok('aud 는 토큰 주소', j.claims.aud === 'https://oauth2.googleapis.com/token', j.claims.aud);
    ok('exp - iat = 3600', j.claims.exp - j.claims.iat === 3600 && j.claims.iat === 1_800_000_000);
    ok('공개키로 서명이 검증된다',
       crypto.verify('sha256', Buffer.from(j.input), RSA.publicKey, j.sig));
    const other = crypto.generateKeyPairSync('rsa', { modulusLength: 2048 }).publicKey;
    ok('다른 공개키로는 검증되지 않는다 (검증이 실제로 일을 한다)',
       !crypto.verify('sha256', Buffer.from(j.input), other, j.sig));
  }

  const sa = FCM.loadServiceAccount(writeSa('good.json', saJson()));
  const okRoute = async (url) => {
    if (url.endsWith('/token')) return { status: 200, body: { access_token: 'tok-' + Math.random().toString(36).slice(2, 8), expires_in: 3599 } };
    return { status: 200, body: { name: 'projects/mybody-test/messages/1' } };
  };

  console.log('\n[3] 보내는 본문');
  {
    const f = fakeFetch(okRoute);
    let t = 1_800_000_000_000;
    const logs = [];
    const s = FCM.createSender({ sa, fetchImpl: f, now: () => t, log: m => logs.push(m) });
    const DEV = 'dev-token-abcdefghijklmnopqrstuvwxyz0123456789';
    const r = await s.send(DEV, { t: '철수님이 운동하라고 콕 찔렀어요', b: '오늘 운동 어때요?',
      route: 'pokes', kind: 'poke', tag: 'poke-user_abc', data: { pokeId: 42, from: 'x', 'google.x': 'y', gone: null } });
    ok('성공으로 돌려준다', r.ok === true && r.gone === false, r);
    ok('토큰 한 번 · 보내기 한 번', f.calls.length === 2, f.calls.map(c => c.url));
    const tk = f.calls[0];
    ok('토큰 요청은 폼 인코딩', /x-www-form-urlencoded/.test(tk.init.headers['content-type']));
    const form = new URLSearchParams(tk.init.body);
    ok('grant_type 은 jwt-bearer', form.get('grant_type') === 'urn:ietf:params:oauth:grant-type:jwt-bearer');
    ok('assertion 서명이 공개키로 검증된다', (() => {
      const j = parseJwt(form.get('assertion'));
      return crypto.verify('sha256', Buffer.from(j.input), RSA.publicKey, j.sig);
    })());
    const snd = f.calls[1];
    ok('보내는 주소 /v1/projects/<id>/messages:send',
       snd.url === 'https://fcm.googleapis.com/v1/projects/mybody-test/messages:send', snd.url);
    ok('Bearer 로 접근 토큰을 싣는다', /^Bearer tok-/.test(snd.init.headers.authorization));
    const m = JSON.parse(snd.init.body).message;
    ok('기기 토큰', m.token === DEV);
    ok('notification 제목 · 본문', m.notification.title === '철수님이 운동하라고 콕 찔렀어요' && m.notification.body === '오늘 운동 어때요?', m.notification);
    ok('data.route · kind', m.data.route === 'pokes' && m.data.kind === 'poke', m.data);
    ok('data.tag 도 같은 tag (앱이 앞에 떠 있을 때 같은 칸에 띄우게)', m.data.tag === 'poke-user_abc', m.data);
    ok('data 값은 전부 문자열', Object.values(m.data).every(v => typeof v === 'string') && m.data.pokeId === '42', m.data);
    ok('FCM 이 막아 둔 data 이름은 뺀다 (from · google.*)', !('from' in m.data) && !('google.x' in m.data), m.data);
    ok('android.priority HIGH', m.android.priority === 'HIGH', m.android);
    ok('android ttl 하루', m.android.ttl === '86400s');
    ok('android 채널 friends · 아이콘 ic_stat_mybody · tag',
       m.android.notification.channel_id === 'friends' && m.android.notification.icon === 'ic_stat_mybody' &&
       m.android.notification.tag === 'poke-user_abc', m.android.notification);
    ok('apns 머리: priority 10 · push-type alert · collapse-id',
       m.apns.headers['apns-priority'] === '10' && m.apns.headers['apns-push-type'] === 'alert' &&
       m.apns.headers['apns-collapse-id'] === 'poke-user_abc', m.apns.headers);
    ok('aps: sound · thread-id', m.apns.payload.aps.sound === 'default' && m.apns.payload.aps['thread-id'] === 'friends');
    const long = FCM.buildMessage('x', { t: 'a', b: 'b', tag: 'x'.repeat(65) }).message;
    ok('64바이트를 넘는 tag 는 뺀다 (APNs 가 거절함)',
       !('tag' in long.android.notification) && !('apns-collapse-id' in long.apns.headers));
    ok('성공한 기기는 로그에 안 남는다', logs.length === 0, logs);

    console.log('\n[4] 접근 토큰 캐시');
    await s.send(DEV, { t: 'a', b: 'b' });
    ok('바로 다음 건은 토큰을 다시 안 받는다', s._stats.tokenFetches === 1, s._stats);
    t += 54 * 60 * 1000;
    await s.send(DEV, { t: 'a', b: 'b' });
    ok('54분 뒤에도 재사용', s._stats.tokenFetches === 1, s._stats);
    t += 2 * 60 * 1000;
    await s.send(DEV, { t: 'a', b: 'b' });
    ok('56분 뒤에는 새로 받는다', s._stats.tokenFetches === 2, s._stats);

    const f2 = fakeFetch(async (url) => { await wait(30); return okRoute(url); });
    const s2 = FCM.createSender({ sa, fetchImpl: f2, now: () => t, log: () => {} });
    const rs = await Promise.all([1, 2, 3].map(i => s2.send(DEV + i, { t: 'a', b: 'b' })));
    ok('동시 3건이어도 토큰 요청은 1번', s2._stats.tokenFetches === 1 &&
       f2.calls.filter(c => c.url.endsWith('/token')).length === 1, s2._stats);
    ok('세 건 다 간다', rs.every(r => r.ok));
  }

  console.log('\n[5] 오류 해석 — 지울 것과 살려 둘 것');
  {
    const table = [
      ['404 UNREGISTERED → 지움', fcmErr(404, 'NOT_FOUND', 'UNREGISTERED'), true],
      /* 코드 없는 404 는 보내는 주소(프로젝트 경로)가 틀린 것일 수 있습니다 — 지우면 전원이 사라짐 */
      ['404 (코드 없음) → 살림', { status: 404, body: {} }, false],
      ['404 NOT_FOUND (UNREGISTERED 아님) → 살림', fcmErr(404, 'NOT_FOUND', ''), false],
      /* 서비스 계정과 앱 설정이 다른 프로젝트면 모든 기기가 이 코드를 받습니다 */
      ['403 SENDER_ID_MISMATCH → 살림', fcmErr(403, 'PERMISSION_DENIED', 'SENDER_ID_MISMATCH'), false],
      ['400 message.token 형식 오류 → 지움', fcmErr(400, 'INVALID_ARGUMENT', 'INVALID_ARGUMENT',
        [{ '@type': 'type.googleapis.com/google.rpc.BadRequest', fieldViolations: [{ field: 'message.token', description: 'bad' }] }]), true],
      ['400 그 밖의 본문 오류 → 살림 (우리 버그)', fcmErr(400, 'INVALID_ARGUMENT', 'INVALID_ARGUMENT',
        [{ '@type': 'type.googleapis.com/google.rpc.BadRequest', fieldViolations: [{ field: 'message.android.ttl' }] }]), false],
      ['403 PERMISSION_DENIED → 살림 (서비스 계정 권한 문제)', fcmErr(403, 'PERMISSION_DENIED', ''), false],
      ['429 QUOTA_EXCEEDED → 살림', fcmErr(429, 'RESOURCE_EXHAUSTED', 'QUOTA_EXCEEDED'), false],
      ['503 UNAVAILABLE → 살림', fcmErr(503, 'UNAVAILABLE', 'UNAVAILABLE'), false],
      ['500 INTERNAL → 살림', fcmErr(500, 'INTERNAL', 'INTERNAL'), false],
      ['401 THIRD_PARTY_AUTH_ERROR → 살림', fcmErr(401, 'UNAUTHENTICATED', 'THIRD_PARTY_AUTH_ERROR'), false]
    ];
    for (const [name, resp, gone] of table) {
      const f = fakeFetch(async (url) => url.endsWith('/token')
        ? { status: 200, body: { access_token: 'a', expires_in: 3599 } } : resp);
      const s = FCM.createSender({ sa, fetchImpl: f, log: () => {} });
      const r = await s.send('dev-token-abcdefghijklmnopqrstuvwxyz', { t: 'a', b: 'b' });
      ok(name, r.ok === false && r.gone === gone, r);
    }
    {
      const f = fakeFetch(async (url) => url.endsWith('/token')
        ? { status: 200, body: { access_token: 'a', expires_in: 3599 } } : new Error('ECONNRESET'));
      const r = await FCM.createSender({ sa, fetchImpl: f, log: () => {} }).send('dev-token-abcdefghijklmnopqrstuvwxyz', {});
      ok('네트워크 오류 → 살림 (status 0)', r.ok === false && r.gone === false && r.status === 0 && r.code === 'NETWORK', r);
    }
    {
      /* 401 UNAUTHENTICATED — 접근 토큰이 중간에 무효가 됨. 버려야 다음 건이 새로 받습니다. */
      let n = 0;
      const f = fakeFetch(async (url) => {
        if (url.endsWith('/token')) return { status: 200, body: { access_token: 'a' + (++n), expires_in: 3599 } };
        return n === 1 ? fcmErr(401, 'UNAUTHENTICATED', '') : { status: 200, body: {} };
      });
      const s = FCM.createSender({ sa, fetchImpl: f, log: () => {} });
      const r1 = await s.send('dev-token-abcdefghijklmnopqrstuvwxyz', {});
      const r2 = await s.send('dev-token-abcdefghijklmnopqrstuvwxyz', {});
      ok('401 → 지우지 않고, 캐시한 접근 토큰을 버린다', r1.gone === false && s._stats.tokenFetches === 2 && r2.ok, [r1, s._stats]);
    }
    {
      const logs = [];
      const f = fakeFetch(async (url) => url.endsWith('/token')
        ? { status: 200, body: { access_token: 'a', expires_in: 3599 } } : fcmErr(401, 'UNAUTHENTICATED', 'THIRD_PARTY_AUTH_ERROR'));
      const s = FCM.createSender({ sa, fetchImpl: f, log: m => logs.push(m) });
      await s.send('dev-token-abcdefghijklmnopqrstuvwxyz', {});
      await s.send('dev-token-abcdefghijklmnopqrstuvwxyz', {});
      ok('APNs 키가 없으면 할 일을 한 번만 말한다', logs.length === 1 && /APNs/.test(logs[0]), logs);
      ok('그때 접근 토큰은 안 버린다 (토큰 잘못이 아님)', s._stats.tokenFetches === 1, s._stats);
    }
    {
      const logs = [];
      const f = fakeFetch(async (url) => url.endsWith('/token')
        ? { status: 200, body: { access_token: 'a', expires_in: 3599 } } : fcmErr(403, 'PERMISSION_DENIED', 'SENDER_ID_MISMATCH'));
      const s = FCM.createSender({ sa, fetchImpl: f, log: m => logs.push(m) });
      const rs = [];
      for (let i = 0; i < 3; i++) rs.push(await s.send('dev-token-' + i + '-abcdefghijklmnopqrstuvwxyz', {}));
      ok('SENDER_ID_MISMATCH 가 여러 기기에서 나도 아무것도 안 지운다', rs.every(r => !r.ok && !r.gone), rs);
      ok('설정 문제라고 한 번만 말한다 (기기마다 "없는 기기" 로 찍지 않음)',
         logs.length === 1 && /다른 프로젝트/.test(logs[0]) && !/더는 없는 기기/.test(logs.join('\n')), logs);
    }
    {
      const logs = [];
      const FULL = 'gonegone-token-SECRETPART-abcdefghijklmnopqrstuvwxyz';
      const f = fakeFetch(async (url) => url.endsWith('/token')
        ? { status: 200, body: { access_token: 'a', expires_in: 3599 } } : fcmErr(404, 'NOT_FOUND', 'UNREGISTERED'));
      await FCM.createSender({ sa, fetchImpl: f, log: m => logs.push(m) }).send(FULL, {});
      ok('정리한 기기는 앞 8자만 로그에 남는다',
         logs.length === 1 && logs[0].includes('gonegone…') && !logs[0].includes('SECRETPART'), logs);
    }
  }

  console.log('\n[6] 토큰 교환이 실패하면 — 5분 동안 다시 안 묻고 한 번만 말한다');
  {
    let t = 1_800_000_000_000;
    const logs = [];
    const f = fakeFetch(async (url) => url.endsWith('/token')
      ? { status: 400, body: { error: 'invalid_grant', error_description: 'Invalid JWT Signature.' } }
      : { status: 200, body: {} });
    const s = FCM.createSender({ sa, fetchImpl: f, now: () => t, log: m => logs.push(m) });
    const r1 = await s.send('dev-token-abcdefghijklmnopqrstuvwxyz', {});
    ok('보내기는 실패로 돌려주고 기기는 안 지운다', r1.ok === false && r1.gone === false && r1.code === 'AUTH', r1);
    t += 60 * 1000;
    await s.send('dev-token-abcdefghijklmnopqrstuvwxyz', {});
    ok('1분 뒤에는 구글에 다시 안 묻는다', s._stats.tokenFetches === 1, s._stats);
    ok('보내기 요청도 안 나간다 (토큰 없이 보내지 않음)', f.calls.every(c => c.url.endsWith('/token')));
    ok('사람 말로 한 번만 찍는다 (invalid_grant 의 뜻까지)', logs.length === 1 && /폐기|시계/.test(logs[0]), logs);
    t += 5 * 60 * 1000;
    await s.send('dev-token-abcdefghijklmnopqrstuvwxyz', {});
    ok('5분이 지나면 다시 묻는다', s._stats.tokenFetches === 2, s._stats);
  }

  console.log('\n[7] 시험용 주소 바꾸기는 https 만 받는다 (Bearer 가 평문으로 새지 않게)');
  {
    const f = fakeFetch(okRoute);
    const s = FCM.createSender({ sa, fetchImpl: f, log: () => {},
      fcmBase: 'http://127.0.0.1:1', tokenUrl: 'http://127.0.0.1:2/token' });
    await s.send('dev-token-abcdefghijklmnopqrstuvwxyz', {});
    ok('http 로 준 토큰 주소는 무시한다', f.calls[0].url === 'https://oauth2.googleapis.com/token', f.calls[0].url);
    ok('http 로 준 FCM 주소는 무시한다', f.calls[1].url.startsWith('https://fcm.googleapis.com/'), f.calls[1].url);
    const f2 = fakeFetch(okRoute);
    const s2 = FCM.createSender({ sa, fetchImpl: f2, log: () => {},
      fcmBase: 'https://127.0.0.1:9', tokenUrl: 'https://127.0.0.1:9/token' });
    await s2.send('dev-token-abcdefghijklmnopqrstuvwxyz', {});
    ok('https 면 받는다', f2.calls[0].url === 'https://127.0.0.1:9/token' &&
       f2.calls[1].url === 'https://127.0.0.1:9/v1/projects/mybody-test/messages:send', f2.calls.map(c => c.url));
    ok('그때 JWT 의 aud 도 그 주소다', parseJwt(new URLSearchParams(f2.calls[0].init.body).get('assertion')).claims.aud === 'https://127.0.0.1:9/token');

    /* 운영 서버에 시험 설정이 새면 진짜 Bearer 와 알림 본문이 남의 호스트로 갑니다. */
    const f3 = fakeFetch(okRoute);
    const s3 = FCM.createSender({ sa, fetchImpl: f3, log: () => {}, env: {},
      fcmBase: 'https://evil.example', tokenUrl: 'https://evil.example/token' });
    await s3.send('dev-token-abcdefghijklmnopqrstuvwxyz', {});
    ok('https 여도 localhost 가 아니면 무시한다', f3.calls[0].url === 'https://oauth2.googleapis.com/token' &&
       f3.calls[1].url.startsWith('https://fcm.googleapis.com/'), f3.calls.map(c => c.url));
    const s4 = FCM.createSender({ sa, fetchImpl: fakeFetch(okRoute), log: () => {}, env: { NODE_ENV: 'test' },
      fcmBase: 'https://fake-fcm.test' });
    ok('NODE_ENV=test 이면 받는다', s4.base === 'https://fake-fcm.test', s4.base);
    const good = writeSa('good-7.json', saJson());
    fs.chmodSync(good, 0o600);
    const lp = FCM.load({ FCM_SERVICE_ACCOUNT: good, FCM_BASE_URL: 'https://127.0.0.1:9' }, { log: () => {}, platform: 'linux' });
    ok('localhost 주소를 받으면 뜰 때 "시험용 FCM 주소 사용 중" 이라고 말한다',
       lp.sender.base === 'https://127.0.0.1:9' && lp.warnings.some(w => /시험용 FCM 주소 사용 중/.test(w)), lp.warnings);
    const le = FCM.load({ FCM_SERVICE_ACCOUNT: good, FCM_BASE_URL: 'https://evil.example' }, { log: () => {}, platform: 'linux' });
    ok('남의 호스트면 무시하고 그렇다고 말한다',
       le.sender.base === FCM.FCM_BASE && le.warnings.some(w => /FCM_BASE_URL 를 무시합니다/.test(w)), [le.sender.base, le.warnings]);
  }

  console.log('\n[7b] 알림 칸(tag) — 사용자 id 대신 받는 사람별 HMAC');
  {
    const s = FCM.createSender({ sa, fetchImpl: fakeFetch(okRoute), log: () => {} });
    const t1 = s.tagFor('news', 'user_viewer1', 'user_owner');
    ok('같은 받는 사람 · 같은 친구면 같은 값 (한 칸을 덮어씀)', t1 === s.tagFor('news', 'user_viewer1', 'user_owner'));
    ok('서버를 다시 띄워도 같은 값 (열쇠에서 끌어냄)',
       t1 === FCM.createSender({ sa: FCM.loadServiceAccount(writeSa('again.json', saJson())), log: () => {} })
         .tagFor('news', 'user_viewer1', 'user_owner'));
    ok('받는 사람이 다르면 다른 값 (여러 사람의 알림을 잇지 못함)', t1 !== s.tagFor('news', 'user_viewer2', 'user_owner'));
    ok('사용자 id 가 들어 있지 않다', !/user_/.test(t1) && /^news-[A-Za-z0-9_-]{22}$/.test(t1), t1);
    ok('64바이트 안 (APNs collapse-id 한도)', Buffer.byteLength(t1) <= 64);
  }
}

/* --- db 계층 --------------------------------------------------------------- */
function dbUnit() {
  console.log('\n[8] 기기 토큰 저장 (db)');
  const file = path.join(TMP, 'unit.db');
  const db = DBM.open(file);
  const api = DBM.makeApi(db);
  const mk = h => api.signUp({ handle: h, password: PW, displayName: h, healthConsent: DBM.HEALTH_CONSENT_VERSION });
  const A = mk('dev-a'), B = mk('dev-b'), C = mk('dev-c');
  const T = n => 'tok_' + String(n).padStart(3, '0') + '_' + 'x'.repeat(30);
  const add = (u, tok, b) => api.addPushDevice(u.user.id, u.token, Object.assign({ token: tok, platform: 'android' }, b || {}));
  const rows = uid => db.prepare('SELECT * FROM push_devices WHERE user_id=?').all(uid);

  ok('정상 등록', add(A, T(1), { appVersion: '0.2.15+300', permission: 'granted' }).ok === true);
  ok('너무 짧은 토큰은 거절', add(A, 'short').ok === false);
  ok('모르는 글자가 든 토큰은 거절', add(A, 'x'.repeat(30) + ' <script>').ok === false);
  ok('4096자를 넘는 토큰은 거절', add(A, 'x'.repeat(4097)).ok === false);
  ok('문자열이 아닌 토큰은 거절', add(A, 12345678901234567890123).ok === false);
  ok('platform 은 android · ios 만', add(A, T(2), { platform: 'web' }).ok === false);
  ok('ios 도 받는다', add(A, T(2), { platform: 'ios' }).ok === true);
  ok('appVersion 이 32자를 넘으면 거절', add(A, T(3), { appVersion: 'v'.repeat(33) }).ok === false);
  ok('다른 사람 세션으로는 못 건다 (토큰 없는 세션)',
     api.addPushDevice(A.user.id, 'no-such-session', { token: T(4), platform: 'android' }).ok === false);
  ok('아이폰 authorized 는 granted 로 적힌다',
     add(A, T(5), { platform: 'ios', permission: 'authorized' }).ok &&
     db.prepare('SELECT permission FROM push_devices WHERE token=?').get(T(5)).permission === 'granted');
  ok('모르는 권한 값은 모름(NULL)',
     add(A, T(6), { permission: 'weird' }).ok &&
     db.prepare('SELECT permission FROM push_devices WHERE token=?').get(T(6)).permission === null);

  /* 토큰만 아는 사람(같은 폰을 쓰던 사람 · 토큰을 받아 간 다른 서버의 운영자)이
     남의 기기를 자기 계정으로 옮기면, 원래 주인의 폰에 남의 알림이 뜹니다. */
  const S1 = 'install-secret-A-' + 'x'.repeat(20);
  add(A, T(20), { secret: S1 });
  ok('비밀은 원문이 아니라 해시로 둔다',
     (() => { const r = db.prepare('SELECT secret_hash FROM push_devices WHERE token=?').get(T(20));
              return r && /^[0-9a-f]{64}$/.test(r.secret_hash) && !r.secret_hash.includes(S1); })());
  const steal = add(B, T(20));
  ok('비밀 없이 남의 (살아 있는) 기기를 옮기려 하면 거절 (conflict)',
     steal.ok === false && steal.conflict === true && rows(A.user.id).some(r => r.token === T(20)), steal);
  ok('틀린 비밀로도 거절', add(B, T(20), { secret: 'wrong-secret-' + 'y'.repeat(20) }).conflict === true &&
     rows(B.user.id).every(r => r.token !== T(20)));
  ok('비밀 형식이 이상하면 거절', add(A, T(21), { secret: 'short' }).ok === false &&
     add(A, T(21), { secret: 'x'.repeat(20) + ' <' }).ok === false);
  /* 같은 폰에서 로그아웃이 서버에 못 닿은 채 다른 아이디로 들어온 경우 — 같은 설치라
     비밀이 같습니다. 옛 주인에게 남겨 두면 그 사람의 알림이 지금 이 폰을 쥔 사람에게 뜹니다. */
  ok('같은 설치의 비밀이면 다른 계정으로 옮긴다', add(B, T(20), { secret: S1 }).ok === true &&
     rows(A.user.id).every(r => r.token !== T(20)) && rows(B.user.id).some(r => r.token === T(20)));
  {
    const A2 = api.signIn({ handle: 'dev-a', password: PW });
    add(A2, T(22), { secret: 'install-secret-A2-' + 'z'.repeat(20) });
    db.prepare('UPDATE sessions SET expires_at=? WHERE token=?').run('2000-01-01T00:00:00.000Z', A2.token);
    ok('옛 주인의 로그인이 끝났으면(만료) 비밀 없이도 옮긴다', add(B, T(22)).ok === true &&
       rows(B.user.id).some(r => r.token === T(22)));
    add(B, T(23), { secret: 'install-secret-B-' + 'w'.repeat(20) });
    add(B, T(23));
    ok('같은 계정이 비밀 없이 다시 올리면(옛 앱) 있던 비밀을 지킨다',
       !!db.prepare('SELECT secret_hash FROM push_devices WHERE token=?').get(T(23)).secret_hash);
  }

  ok('남의 기기 지우기는 ok 로 답하지만 아무것도 안 지운다 (답으로 있는지 알 수 없게)',
     api.removePushDevice(A.user.id, T(20)).ok === true && rows(B.user.id).some(r => r.token === T(20)));
  ok('없는 토큰 지우기도 같은 답', api.removePushDevice(A.user.id, T(999)).ok === true);
  ok('내 기기는 지운다', api.removePushDevice(B.user.id, T(20)).ok === true &&
     rows(B.user.id).every(r => r.token !== T(20)));
  api.removePushDevice(B.user.id, T(22)); api.removePushDevice(B.user.id, T(23));

  /* 사람당 상한 10 — 오래 안 켠 것부터 버립니다 */
  for (let i = 100; i < 110; i++) add(C, T(i));
  ok('10개까지 받는다', rows(C.user.id).length === 10, rows(C.user.id).length);
  db.prepare('UPDATE push_devices SET updated_at=? WHERE token=?').run('2000-01-01T00:00:00.000Z', T(104));
  add(C, T(110));
  ok('11번째가 오면 10개로 줄인다', rows(C.user.id).length === 10, rows(C.user.id).length);
  ok('버리는 것은 가장 오래 안 켠 것', !rows(C.user.id).some(r => r.token === T(104)) &&
     rows(C.user.id).some(r => r.token === T(110)));

  console.log('\n[9] 로그아웃 · 탈퇴 · 만료 — 기기 행이 같이 사라진다');
  {
    const D = mk('dev-d');
    const D2 = api.signIn({ handle: 'dev-d', password: PW });
    add(D, T(200)); add(D2, T(201));
    api.signOut(D2.token);
    ok('로그아웃하면 그 세션이 건 기기만 지워진다',
       rows(D.user.id).map(r => r.token).join() === T(200), rows(D.user.id).map(r => r.token));
    api.signOutEverywhere(D.user.id);
    ok('모든 기기 로그아웃이면 전부', rows(D.user.id).length === 0);

    const E = mk('dev-e');
    add(E, T(300));
    const cp = api.changePassword(E.user.id, { current: PW, next: 'test-password-2' });
    ok('비밀번호를 바꾸면 옛 세션의 기기가 지워진다', cp.ok && rows(E.user.id).length === 0);
    const Ereset = api.adminResetPassword('dev-e', 'test-password-3');
    ok('주인이 초기화해도 (세션과 같이)', Ereset.ok && rows(E.user.id).length === 0);

    const F = mk('dev-f');
    add(F, T(400));
    api.deleteMe(F.user.id);
    ok('탈퇴하면 전부', db.prepare('SELECT COUNT(*) c FROM push_devices WHERE token=?').get(T(400)).c === 0);

    const G = mk('dev-g');
    add(G, T(500));
    ok('살아 있는 세션의 기기는 보낼 대상', api.pushDevicesOf(G.user.id).length === 1);
    db.prepare('UPDATE sessions SET expires_at=? WHERE token=?').run('2000-01-01T00:00:00.000Z', G.token);
    ok('만료된 세션(아직 안 지워진)의 기기는 보내지 않는다', api.pushDevicesOf(G.user.id).length === 0);
    ok('그 기기는 "최근 앱" 으로도 안 친다', api.hasRecentAppDevice(G.user.id, 30) === false);
    ok('(정리 전) 행은 아직 남아 있다', rows(G.user.id).length === 1);
    const G2 = api.signIn({ handle: 'dev-g', password: PW });
    add(G2, T(501));
    ok('만료된 로그인 정리 — 지운 수를 돌려준다', api.pruneExpiredSessions() >= 1);
    ok('만료된 세션에 묶인 기기 행이 같이 지워진다 (보관 기간)', rows(G.user.id).map(r => r.token).join() === T(501),
       rows(G.user.id).map(r => r.token));
    ok('살아 있는 세션은 안 건드린다', api.userForToken(G2.token) !== null);
  }

  console.log('\n[10] 크롬(웹) 알림을 생략하는 기준');
  {
    const H = mk('dev-h');
    ok('앱 기기가 없으면 생략 안 함', api.hasRecentAppDevice(H.user.id, 30) === false);
    add(H, T(600), { permission: 'granted' });
    ok('방금 등록했으면 생략', api.hasRecentAppDevice(H.user.id, 30) === true);
    db.prepare('UPDATE push_devices SET updated_at=? WHERE token=?')
      .run(new Date(Date.now() - 31 * 86400000).toISOString(), T(600));
    ok('31일 동안 앱이 안 켜졌으면 생략 안 함', api.hasRecentAppDevice(H.user.id, 30) === false);
    add(H, T(600), { permission: 'denied' });
    ok('앱 알림을 거절한 폰이면 생략 안 함 (아무 데서도 못 받게 되니까)', api.hasRecentAppDevice(H.user.id, 30) === false);
    ok('알림을 거절한 기기로는 FCM 을 보내지 않는다 (띄우지도 못할 문구를 구글에 안 넘김)',
       api.pushDevicesOf(H.user.id).length === 0);
    add(H, T(600));
    ok('권한을 모르면 허용처럼 본다', api.hasRecentAppDevice(H.user.id, 30) === true &&
       api.pushDevicesOf(H.user.id).length === 1);

    const P256 = 'B'.repeat(87), AUTH = 'C'.repeat(22);
    api.addPushSub(H.user.id, { endpoint: 'https://push.example.com/h1', p256dh: P256, auth: AUTH });
    api.addPushSub(H.user.id, { endpoint: 'https://push.example.com/h2', p256dh: P256, auth: AUTH });
    ok('설정 화면 숫자 — 기기 1 · 웹 구독 2', JSON.stringify(api.pushCounts(H.user.id)) === '{"devices":1,"webSubs":2}',
       api.pushCounts(H.user.id));
    const r = api.dropPushSubsOf(H.user.id);
    ok('웹 알림 끄기 — 지운 수를 돌려준다', r.ok && r.removed === 2 && api.pushSubsOf(H.user.id).length === 0, r);
  }

  console.log('\n[11] 운동 소식을 받을 사람 — 공유 설정 · 차단 그대로');
  {
    const O = mk('news-o'), V1 = mk('news-v1'), V2 = mk('news-v2'), V3 = mk('news-v3'), V4 = mk('news-v4');
    const friend = (a, b) => { api.sendRequest(a.user.id, b.user.inviteCode); api.accept(b.user.id, a.user.id); };
    friend(O, V1); friend(O, V2); friend(O, V3);
    api.sendRequest(O.user.id, V4.user.inviteCode);          // 대기 중
    api.setShare(O.user.id, V2.user.id, { schedule: false });  // 일정 공유 끔
    api.block(O.user.id, V3.user.id);                          // 차단
    const got = api.newsViewersFor(O.user.id);
    ok('일정을 보여 주는 수락된 친구만', got.length === 1 && got[0] === V1.user.id, got);
    ok('웹 쪽 규칙(pushTargetsFor)과 같은 사람', (() => {
      api.addPushSub(V1.user.id, { endpoint: 'https://push.example.com/v1', p256dh: 'B'.repeat(87), auth: 'C'.repeat(22) });
      api.addPushSub(V2.user.id, { endpoint: 'https://push.example.com/v2', p256dh: 'B'.repeat(87), auth: 'C'.repeat(22) });
      const web = [...new Set(api.pushTargetsFor(O.user.id).map(x => x.viewer))];
      return web.length === 1 && web[0] === V1.user.id;
    })());

    console.log('\n[12] 독촉 — 앱 알림으로 닿았는지 표시');
    const p1 = api.poke(V1.user.id, O.user.id);
    const p2 = api.poke(O.user.id, V1.user.id);
    api.markPokePushed(p1.id);
    const pulled = api.pullPokes(O.user.id).pokes;
    ok('앱 알림으로 닿은 독촉은 pushed:true', pulled.length === 1 && pulled[0].pushed === true, pulled);
    const pulled2 = api.pullPokes(V1.user.id).pokes;
    ok('안 닿은 것은 pushed:false (앱이 켜질 때 로컬 알림으로 띄움)', pulled2.length === 1 && pulled2[0].pushed === false && p2.ok, pulled2);
  }
  db.close();

  console.log('\n[13] 이미 있던 DB 에도 새 칸이 생긴다');
  {
    const old = path.join(TMP, 'old.db');
    const d = new DatabaseSync(old);
    d.exec(`CREATE TABLE pokes (id INTEGER PRIMARY KEY AUTOINCREMENT, from_id TEXT NOT NULL,
            to_id TEXT NOT NULL, kind TEXT NOT NULL, created_at TEXT NOT NULL, delivered_at TEXT)`);
    d.close();
    const d2 = DBM.open(old);
    const cols = d2.prepare('PRAGMA table_info(pokes)').all().map(c => c.name);
    const tables = d2.prepare("SELECT name FROM sqlite_master WHERE type='table'").all().map(t => t.name);
    ok('pokes.pushed_at 이 더해진다', cols.includes('pushed_at'), cols);
    ok('push_devices 테이블이 생긴다', tables.includes('push_devices'), tables);
    d2.close();
  }
}

/* --- 통합: 진짜 서버 + 가짜 OAuth · FCM · 웹 푸시 ------------------------- */
const PORT = 8900 + Math.floor(Math.random() * 90);
const HOOK = PORT + 100 + Math.floor(Math.random() * 50);
const PAIR = 'fcm-pair-secret';
const DB = path.join(TMP, 'srv.db');
const B = `http://localhost:${PORT}/api`;
const SA_OK = saJson({ token_uri: `https://127.0.0.1:${HOOK}/token` });

/* 가짜 서버는 https 여야 합니다. 서버가 http 로 바꾼 주소를 무시하기 때문입니다
   (그게 맞습니다 — Bearer 토큰이 평문으로 새면 안 됩니다). */
const CERT = (() => {
  const d = fs.mkdtempSync(path.join(os.tmpdir(), 'mybody-fcmcert-'));
  const key = path.join(d, 'k.pem'), crt = path.join(d, 'c.pem');
  spawnSync('openssl', ['req', '-x509', '-newkey', 'rsa:2048', '-nodes',
    '-keyout', key, '-out', crt, '-days', '1', '-subj', '/CN=localhost',
    '-addext', 'subjectAltName=IP:127.0.0.1,DNS:localhost'], { encoding: 'utf8' });
  return { key: fs.readFileSync(key), cert: fs.readFileSync(crt), dir: d };
})();

const fcmGot = [];      // 받은 message
const webGot = [];      // 웹 푸시 경로
const tokenCalls = [];  // { ok, why }
const hook = https.createServer({ key: CERT.key, cert: CERT.cert }, (req, res) => {
  const chunks = [];
  req.on('data', c => chunks.push(c));
  req.on('end', () => {
    const raw = Buffer.concat(chunks);
    const reply = (st, obj) => { res.writeHead(st, { 'content-type': 'application/json' }); res.end(JSON.stringify(obj || {})); };
    if (req.url === '/token') {
      const form = new URLSearchParams(raw.toString('utf8'));
      let j = null, sigOk = false;
      try { j = parseJwt(form.get('assertion')); sigOk = crypto.verify('sha256', Buffer.from(j.input), RSA.publicKey, j.sig); } catch (e) {}
      const c = (j && j.claims) || {};
      const why = !sigOk ? 'sig' : form.get('grant_type') !== 'urn:ietf:params:oauth:grant-type:jwt-bearer' ? 'grant'
        : c.aud !== `https://127.0.0.1:${HOOK}/token` ? 'aud' : c.scope !== FCM.SCOPE ? 'scope'
        : c.iss === 'revoked@mybody-test.iam.gserviceaccount.com' ? 'revoked'
        : c.iss !== SA_OK.client_email ? 'iss' : '';
      tokenCalls.push({ ok: !why, why });
      if (why) return reply(400, { error: 'invalid_grant', error_description: 'Invalid JWT Signature. (' + why + ')' });
      return reply(200, { access_token: 't1', expires_in: 3599, token_type: 'Bearer' });
    }
    if (req.url === '/v1/projects/mybody-test/messages:send') {
      if (req.headers.authorization !== 'Bearer t1') return reply(401, { error: { code: 401, status: 'UNAUTHENTICATED' } });
      let m = null;
      try { m = JSON.parse(raw.toString('utf8')).message; } catch (e) {}
      fcmGot.push(m);
      const tok = String(m && m.token);
      if (tok.startsWith('gone')) return reply(404, { error: { code: 404, status: 'NOT_FOUND', details: [
        { '@type': 'type.googleapis.com/google.firebase.fcm.v1.FcmError', errorCode: 'UNREGISTERED' }] } });
      if (tok.startsWith('down')) return reply(503, { error: { code: 503, status: 'UNAVAILABLE' } });
      if (tok.startsWith('slow')) return setTimeout(() => reply(200, { name: 'slow' }), 2500);
      return reply(200, { name: 'projects/mybody-test/messages/' + fcmGot.length });
    }
    if (req.url.startsWith('/sub/')) { webGot.push(req.url.slice(5)); res.writeHead(201); return res.end(); }
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
      /* 스스로 서명한 인증서를 쓰는 가짜 서버라 검증을 끕니다.
         **시험용 자식 프로세스에만** 겁니다 — 제품 코드는 안 건드립니다. */
      NODE_TLS_REJECT_UNAUTHORIZED: '0'
    }, env)
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
    try { if ((await fetch(`http://localhost:${PORT}/api/health`)).ok) return true; } catch (e) {}
    await wait(150);
  }
  return false;
}
async function call(method, p, body, token) {
  const r = await fetch(B + p, {
    method,
    headers: Object.assign({ 'Content-Type': 'application/json' },
      token ? { Authorization: 'Bearer ' + token } : {}),
    body: body ? JSON.stringify(body) : undefined
  });
  let j = null; try { j = await r.json(); } catch (e) {}
  return { status: r.status, json: j };
}
function newSubscriber(tag) {
  const ecdh = crypto.createECDH('prime256v1');
  ecdh.generateKeys();
  return { endpoint: `https://127.0.0.1:${HOOK}/sub/${tag}`,
           p256dh: PUSH.b64u(ecdh.getPublicKey()), auth: PUSH.b64u(crypto.randomBytes(16)) };
}
const devTok = (kind, who) => kind + '_' + who + '_' + crypto.randomBytes(24).toString('hex');
function dbRows(sql, ...args) {
  const d = new DatabaseSync(DB, { readOnly: true });
  try { return d.prepare(sql).all(...args); } finally { d.close(); }
}
/* 알림은 응답을 기다리지 않고 나갑니다 — 조건이 맞을 때까지 조금 기다립니다. */
async function until(fn, ms = 2500) {
  const t0 = Date.now();
  while (Date.now() - t0 < ms) { if (fn()) return true; await wait(50); }
  return fn();
}

async function integration() {
  /* 기본 자리(~/.mybody/fcm-service-account.json)에 둡니다 — 주인이 실제로
     하는 그대로입니다. HOME 은 testenv 가 만든 빈 임시 폴더입니다. */
  const saDir = path.join(TESTENV.home, '.mybody');
  fs.mkdirSync(saDir, { recursive: true });
  fs.writeFileSync(path.join(saDir, 'fcm-service-account.json'), JSON.stringify(SA_OK));
  const vapid = PUSH.generateVapid();
  const VAPID_ENV = { VAPID_PUBLIC: vapid.publicKey, VAPID_PRIVATE: vapid.privateKey };

  console.log('\n[14] 서비스 계정 파일이 있으면 켜진다');
  srv = boot(VAPID_ENV);
  ok('서버가 뜬다', await waitUp(), out.slice(-300));
  ok('뜰 때 "앱 알림(FCM) 켜짐" 을 말한다', /앱 알림\(FCM\) 켜짐 — 프로젝트 mybody-test/.test(out), out.slice(0, 600));
  ok('시험용 FCM 주소를 쓰고 있다고 말한다', /시험용 FCM 주소 사용 중/.test(out), out.slice(0, 900));

  const mk = async (handle, name) => (await call('POST', '/auth/signup', {
    handle, password: PW, displayName: name, pairSecret: PAIR, healthConsent: DBM.HEALTH_CONSENT_VERSION })).json;
  const A = await mk('chulsoo', '철수'), Bu = await mk('younghee', '영희'), C = await mk('minsu', '민수');
  ok('세 계정', !!(A.token && Bu.token && C.token));

  console.log('\n[15] 엔드포인트 — 로그인 필수 · 형식 검사');
  const okB = devTok('ok', 'b');
  ok('로그인 없이 기기 등록 → 401', (await call('POST', '/push/device', { token: okB, platform: 'android' })).status === 401);
  ok('로그인 없이 기기 삭제 → 401', (await call('DELETE', '/push/device', { token: okB })).status === 401);
  ok('로그인 없이 상태 → 401', (await call('GET', '/push/status')).status === 401);
  ok('로그인 없이 웹 알림 끄기 → 401', (await call('DELETE', '/push/web')).status === 401);
  ok('짧은 토큰 → 400', (await call('POST', '/push/device', { token: 'abc', platform: 'android' }, Bu.token)).status === 400);
  ok('이상한 글자 → 400', (await call('POST', '/push/device', { token: 'x'.repeat(30) + '/../', platform: 'android' }, Bu.token)).status === 400);
  ok('너무 긴 토큰 → 400', (await call('POST', '/push/device', { token: 'x'.repeat(4097), platform: 'android' }, Bu.token)).status === 400);
  ok('모르는 platform → 400', (await call('POST', '/push/device', { token: okB, platform: 'web' }, Bu.token)).status === 400);
  ok('토큰 없이 삭제 → 400', (await call('DELETE', '/push/device', {}, Bu.token)).status === 400);
  const reg = await call('POST', '/push/device', { token: okB, platform: 'android', appVersion: '0.2.15', permission: 'granted' }, Bu.token);
  ok('정상 등록 → {ok, fcm:true}', reg.status === 200 && reg.json.ok && reg.json.fcm === true, reg.json);

  /* 영희는 크롬 구독도 있습니다 — 바로 이 사람의 불만이 "크롬에서 온다" 였습니다. */
  const subB = newSubscriber('younghee'), subA = newSubscriber('chulsoo'), subC = newSubscriber('minsu');
  for (const [s, tok] of [[subB, Bu.token], [subA, A.token], [subC, C.token]]) {
    await call('POST', '/push/subscribe', { endpoint: s.endpoint, p256dh: s.p256dh, auth: s.auth }, tok);
  }
  const st = (await call('GET', '/push/status', null, Bu.token)).json;
  ok('상태: fcm · web · 기기 1 · 웹 구독 1 · 크롬은 조용히',
     st && st.fcm === true && st.web === true && st.devices === 1 && st.webSubs === 1 && st.webMuted === true, st);
  const stA = (await call('GET', '/push/status', null, A.token)).json;
  ok('앱이 없는 사람은 크롬이 그대로', stA && stA.devices === 0 && stA.webMuted === false, stA);

  console.log('\n[16] 친구 요청 → 앱으로 가고 크롬은 조용하다');
  fcmGot.length = 0; webGot.length = 0;
  await call('POST', '/friends/request', { inviteCode: Bu.user.inviteCode }, A.token);
  ok('앱(FCM)으로 한 통', await until(() => fcmGot.length === 1), fcmGot.length);
  await wait(300);
  ok('route social · kind friend_request', fcmGot[0] && fcmGot[0].data.route === 'social' &&
     fcmGot[0].data.kind === 'friend_request', fcmGot[0] && fcmGot[0].data);
  /* FCM 의 notification 은 평문이라 구글 · 애플이 읽습니다(웹 푸시는 암호화). */
  const leaks = (m, words) => { const j = JSON.stringify(m || {}); return words.filter(w => j.includes(w)); };
  ok('일반 문구만 — "친구 요청이 왔어요"', fcmGot[0] && fcmGot[0].notification.title === '친구 요청이 왔어요', fcmGot[0] && fcmGot[0].notification);
  ok('보낸 사람 이름 · 사용자 id · 받는 사람의 공유 기본값이 평문에 없다',
     leaks(fcmGot[0], ['철수', A.user.id, Bu.user.id, '수락하면', '체중', '보입니다']).length === 0,
     leaks(fcmGot[0], ['철수', A.user.id, Bu.user.id, '수락하면', '체중', '보입니다']));
  ok('tag 는 friend-<HMAC> (사용자 id 아님)', fcmGot[0] && /^friend-[A-Za-z0-9_-]{22}$/.test(fcmGot[0].android.notification.tag) &&
     fcmGot[0].apns.headers['apns-collapse-id'] === fcmGot[0].android.notification.tag, fcmGot[0] && fcmGot[0].android.notification);
  ok('앱이 있는 영희에게 크롬 알림은 0건', webGot.length === 0, webGot);

  fcmGot.length = 0; webGot.length = 0;
  await call('POST', '/friends/accept', { userId: A.user.id }, Bu.token);
  ok('앱이 없는 철수에게는 크롬이 그대로 간다', await until(() => webGot.includes('chulsoo')), webGot);
  await wait(300);
  ok('철수에게 FCM 은 안 간다 (기기 없음)', fcmGot.length === 0, fcmGot.length);

  console.log('\n[17] 운동 독촉 — 이번 불만의 본체');
  fcmGot.length = 0; webGot.length = 0;
  const pk = await call('POST', '/pokes', { userId: Bu.user.id }, A.token);
  ok('독촉이 된다', pk.json && pk.json.ok, pk.json);
  ok('앱(FCM)으로 간다', await until(() => fcmGot.length === 1), fcmGot.length);
  await wait(300);
  const m = fcmGot[0] || { data: {}, notification: {}, android: { notification: {} }, apns: { headers: {} } };
  ok('route pokes · kind poke · pokeId', m.data.route === 'pokes' && m.data.kind === 'poke' && m.data.pokeId === String(pk.json.id), m.data);
  ok('notification 은 이름 없는 일반 문구', m.notification.title === '친구가 운동하라고 콕 찔렀어요' &&
     leaks(m, ['철수', A.user.id, Bu.user.id]).length === 0, [m.notification, leaks(m, ['철수', A.user.id, Bu.user.id])]);
  ok('android.priority HIGH · 채널 friends', m.android.priority === 'HIGH' && m.android.notification.channel_id === 'friends', m.android);
  ok('apns 머리 (priority 10 · alert · collapse-id = poke-<독촉 번호>)', m.apns.headers['apns-priority'] === '10' &&
     m.apns.headers['apns-push-type'] === 'alert' && m.apns.headers['apns-collapse-id'] === 'poke-' + pk.json.id &&
     m.data.tag === 'poke-' + pk.json.id, m.apns.headers);
  ok('크롬 알림은 0건 (중복 방지)', webGot.length === 0, webGot);
  const pulled = (await call('GET', '/pokes', null, Bu.token)).json;
  ok('앱이 가져갈 때 pushed:true (로컬 알림을 또 띄우지 않게)',
     pulled && pulled.pokes.length === 1 && pulled.pokes[0].pushed === true, pulled);
  ok('웹 푸시로 갈 때의 이름은 앱이 가져가서 보여 준다', pulled && pulled.pokes[0].from.displayName === '철수');

  console.log('\n[17b] 첫 기기가 받는 즉시 pushed — 느린 기기를 기다리지 않는다');
  {
    /* 민수와 영희를 친구로 */
    await call('POST', '/friends/request', { inviteCode: Bu.user.inviteCode }, C.token);
    await call('POST', '/friends/accept', { userId: C.user.id }, Bu.token);
    await wait(300);
    const slowB = devTok('slow', 'b');
    await call('POST', '/push/device', { token: slowB, platform: 'android' }, Bu.token);
    await wait(20);
    /* okB 를 다시 올려 맨 앞(가장 최근)으로 — 빠른 기기가 먼저, 느린 기기가 나중 */
    await call('POST', '/push/device', { token: okB, platform: 'android', appVersion: '0.2.15', permission: 'granted' }, Bu.token);
    fcmGot.length = 0;
    const pk2 = await call('POST', '/pokes', { userId: Bu.user.id }, C.token);
    ok('두 번째 독촉', pk2.json && pk2.json.ok, pk2.json);
    await until(() => fcmGot.length >= 2);
    await wait(200);
    /* 느린 기기는 아직 2.5초를 기다리는 중 */
    const early = (await call('GET', '/pokes', null, Bu.token)).json;
    ok('느린 기기가 끝나기 전에 가져가도 pushed:true (앱이 같은 독촉을 또 띄우지 않음)',
       early && early.pokes.length === 1 && early.pokes[0].pushed === true, early);
    await wait(2600);
    await call('DELETE', '/push/device', { token: slowB }, Bu.token);
  }

  console.log('\n[18] 운동 소식 · 죽은 기기 정리 · 잠깐 실패한 기기는 살림');
  const goneB = devTok('gone', 'b'), downB = devTok('down', 'b');
  await call('POST', '/push/device', { token: goneB, platform: 'ios' }, Bu.token);
  await call('POST', '/push/device', { token: downB, platform: 'android' }, Bu.token);
  const snap = kept => call('POST', '/snapshots', { weekStart: '2026-09-21', payload: { plannedDays: 4, keptDays: kept } }, A.token);
  await snap(1);
  await wait(300);
  fcmGot.length = 0; webGot.length = 0;
  await snap(2);
  ok('세 기기 모두에 시도', await until(() => fcmGot.length === 3), fcmGot.length);
  await wait(400);
  ok('kind workout · route social', fcmGot.every(x => x.data.kind === 'workout' && x.data.route === 'social'), fcmGot.map(x => x.data));
  ok('운동 소식도 일반 문구 — 이름 · "이번 주 N일째 · 계획 M일" · 사용자 id 가 평문에 없다',
     fcmGot.every(x => x.notification.title === '친구가 운동했어요' &&
                       leaks(x, ['철수', '일째', '계획', A.user.id, Bu.user.id]).length === 0),
     fcmGot.map(x => [x.notification, leaks(x, ['철수', '일째', '계획', A.user.id, Bu.user.id])]));
  ok('같은 받는 사람의 기기들은 같은 tag (한 칸)', new Set(fcmGot.map(x => x.android.notification.tag)).size === 1);
  ok('UNREGISTERED 기기 행은 지워진다', dbRows('SELECT 1 FROM push_devices WHERE token=?', goneB).length === 0);
  const down = dbRows('SELECT fails FROM push_devices WHERE token=?', downB);
  ok('503 기기는 남고 실패만 센다', down.length === 1 && down[0].fails === 1, down);
  ok('살아 있는 기기로는 닿았으니 크롬은 0건', webGot.length === 0, webGot);
  ok('로그에 토큰 전체가 없다 (앞 8자만)', !out.includes(goneB) && out.includes(goneB.slice(0, 8) + '…'),
     out.split('\n').filter(l => /FCM/.test(l)));
  ok('성공한 기기 토큰은 로그에 아예 없다', !out.includes(okB.slice(0, 20)));

  console.log('\n[19] 일정 공유를 끈 친구에게는 운동 소식 앱 알림도 안 간다');
  await call('PUT', '/share/' + Bu.user.id, { schedule: false }, A.token);
  fcmGot.length = 0; webGot.length = 0;
  await snap(3);
  await wait(900);
  ok('FCM 0건 (공유 설정을 우회하는 뒷문이 없다)', fcmGot.length === 0, fcmGot.map(x => x.data));
  ok('크롬도 0건', webGot.length === 0, webGot);
  await call('PUT', '/share/' + Bu.user.id, { schedule: true }, A.token);
  /* 위의 0건이 "아예 안 보내서" 가 아니라 "걸러서" 인지 확인합니다. */
  fcmGot.length = 0;
  await snap(4);
  ok('다시 켜면 다시 간다 (위의 0건은 거른 결과)', await until(() => fcmGot.length >= 1), fcmGot.length);
  await wait(300);

  console.log('\n[20] 남의 기기 · 웹 알림 끄기');
  const del = await call('DELETE', '/push/device', { token: okB }, C.token);
  const delNone = await call('DELETE', '/push/device', { token: devTok('ok', 'none') }, C.token);
  ok('남의 토큰 삭제는 없는 토큰과 똑같이 200 {ok:true} (있는지 알 수 없게)',
     del.status === 200 && delNone.status === 200 && JSON.stringify(del.json) === JSON.stringify(delNone.json), [del, delNone]);
  ok('영희 기기는 그대로', dbRows('SELECT 1 FROM push_devices WHERE token=?', okB).length === 1);
  const grab = await call('POST', '/push/device', { token: okB, platform: 'android' }, C.token);
  ok('남의 토큰을 내 계정으로 등록하려 하면 409, 영희 기기는 그대로',
     grab.status === 409 && dbRows('SELECT user_id FROM push_devices WHERE token=?', okB)[0].user_id === Bu.user.id, grab);
  {
    const denB = devTok('ok', 'denied');
    await call('POST', '/push/device', { token: denB, platform: 'ios', permission: 'denied' }, Bu.token);
    fcmGot.length = 0;
    await snap(5);
    await until(() => fcmGot.length >= 1);
    await wait(400);
    ok('알림을 거절한 기기로는 FCM 을 보내지 않는다', fcmGot.length >= 1 && !fcmGot.some(x => x.token === denB),
       fcmGot.map(x => x.token.slice(0, 10)));
    await call('DELETE', '/push/device', { token: denB }, Bu.token);
  }
  ok('내 기기 삭제', (await call('DELETE', '/push/device', { token: downB }, Bu.token)).json.ok === true &&
     dbRows('SELECT 1 FROM push_devices WHERE token=?', downB).length === 0);
  const wo = await call('DELETE', '/push/web', null, Bu.token);
  ok('웹 알림 끄기 → 지운 수', wo.status === 200 && wo.json.ok && wo.json.removed === 1, wo.json);
  ok('상태의 웹 구독 0', (await call('GET', '/push/status', null, Bu.token)).json.webSubs === 0);
  const wo2 = await call('DELETE', '/push/web-subscriptions', null, C.token);
  ok('다른 이름(/push/web-subscriptions)도 받는다', wo2.status === 200 && wo2.json.removed === 1, wo2.json);

  console.log('\n[21] 로그아웃 · 모든 기기 로그아웃 · 탈퇴 → 기기 행 0');
  {
    const s2 = (await call('POST', '/auth/signin', { handle: 'younghee', password: PW })).json;
    const ok2 = devTok('ok', 'b2');
    await call('POST', '/push/device', { token: ok2, platform: 'ios' }, s2.token);
    await call('POST', '/auth/signout', null, s2.token);
    ok('로그아웃한 세션의 기기는 지워진다', dbRows('SELECT 1 FROM push_devices WHERE token=?', ok2).length === 0);
    ok('다른 세션의 기기는 남는다', dbRows('SELECT 1 FROM push_devices WHERE token=?', okB).length === 1);
    await call('POST', '/auth/signout-all', null, Bu.token);
    ok('모든 기기 로그아웃 → 영희 기기 0', dbRows('SELECT 1 FROM push_devices WHERE user_id=?', Bu.user.id).length === 0);

    const D = await mk('dongsu', '동수');
    await call('POST', '/push/device', { token: devTok('ok', 'd'), platform: 'android' }, D.token);
    ok('동수 기기 1', dbRows('SELECT 1 FROM push_devices WHERE user_id=?', D.user.id).length === 1);
    await call('DELETE', '/me', null, D.token);
    ok('탈퇴 → 동수 기기 0', dbRows('SELECT 1 FROM push_devices WHERE user_id=?', D.user.id).length === 0);
  }
  await stop();

  console.log('\n[22] 서비스 계정 파일이 없으면 — 예전과 똑같이 크롬으로 간다');
  srv = boot(Object.assign({}, VAPID_ENV, { FCM_SERVICE_ACCOUNT: path.join(TMP, 'none.json') }));
  ok('그래도 서버가 뜬다', await waitUp(), out.slice(-300));
  ok('뜰 때 꺼졌다고 말한다', /앱 알림\(FCM\) 꺼짐 — .*none\.json 파일 없음/.test(out), out.slice(0, 600));
  const B2 = (await call('POST', '/auth/signin', { handle: 'younghee', password: PW })).json;
  const reg2 = await call('POST', '/push/device', { token: devTok('ok', 'b3'), platform: 'android' }, B2.token);
  ok('기기 등록은 받아 둔다 (나중에 켜면 바로 씀) · fcm:false', reg2.status === 200 && reg2.json.fcm === false, reg2.json);
  await call('POST', '/push/subscribe', { endpoint: subB.endpoint, p256dh: subB.p256dh, auth: subB.auth }, B2.token);
  const st2 = (await call('GET', '/push/status', null, B2.token)).json;
  ok('상태: fcm false · 크롬 안 조용함', st2.fcm === false && st2.webMuted === false, st2);
  const E = await mk('eunji', '은지');
  fcmGot.length = 0; webGot.length = 0; tokenCalls.length = 0;
  await call('POST', '/friends/request', { inviteCode: B2.user.inviteCode }, E.token);
  ok('앱 기기가 있어도 FCM 이 꺼져 있으면 크롬으로 간다', await until(() => webGot.includes('younghee')), webGot);
  ok('FCM · OAuth 는 안 불린다', fcmGot.length === 0 && tokenCalls.length === 0, [fcmGot.length, tokenCalls.length]);
  await stop();

  console.log('\n[23] 열쇠가 폐기돼 토큰을 못 받으면 — 크롬 알림을 막지 않는다');
  const revoked = writeSa('revoked.json', saJson({ token_uri: `https://127.0.0.1:${HOOK}/token`,
    client_email: 'revoked@mybody-test.iam.gserviceaccount.com' }));
  srv = boot(Object.assign({}, VAPID_ENV, { FCM_SERVICE_ACCOUNT: revoked }));
  ok('서버가 뜬다 (켜짐)', await waitUp() && /앱 알림\(FCM\) 켜짐/.test(out), out.slice(0, 400));
  const B3 = (await call('POST', '/auth/signin', { handle: 'younghee', password: PW })).json;
  await call('POST', '/push/device', { token: devTok('ok', 'b4'), platform: 'android' }, B3.token);
  const F = await mk('fanny', '패니');
  fcmGot.length = 0; webGot.length = 0; tokenCalls.length = 0;
  await call('POST', '/friends/request', { inviteCode: B3.user.inviteCode }, F.token);
  ok('앱으로 못 보냈으니 크롬으로 간다 (아무 데서도 못 받는 일이 없게)', await until(() => webGot.includes('younghee')), webGot);
  ok('가짜 OAuth 가 서명을 확인하고 거절했다', tokenCalls.length === 1 && tokenCalls[0].why === 'revoked', tokenCalls);
  ok('FCM 보내기는 안 나갔다', fcmGot.length === 0);
  ok('주인에게 사람 말로 한 번 말한다', /접근 토큰을 못 받았습니다[\s\S]*폐기/.test(out), out.split('\n').filter(l => /FCM/.test(l)));
  await stop();
}

(async () => {
  try {
    await unit();
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
