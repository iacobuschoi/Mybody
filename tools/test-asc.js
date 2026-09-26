/* tools/test-asc.js — asc.js 가 애플에 무엇을 어떤 순서로 보내는가 (가짜 서버)
 *
 * 진짜 API 는 열쇠가 있어야 부를 수 있으니, fetch 를 가짜로 바꿔 넣고
 *   · JWT 가 ES256 으로 제대로 서명되는가 (같은 열쇠의 공개키로 검증)
 *   · 번들 ID 없으면 만들고, 있으면 안 만드는가
 *   · 우리 프로파일에 묶인 인증서만 폐기하는가 (남의 것은 그대로)
 *   · 파일 두 개가 out 에 떨어지는가
 * 를 봅니다. node tools/test-asc.js
 */
'use strict';
const crypto = require('node:crypto');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const asc = require('./asc.js');

let pass = 0, fail = 0;
function ok(cond, msg) { if (cond) { pass++; console.log('  ✓ ' + msg); } else { fail++; console.log('  ✗ ' + msg); } }

/* 애플 열쇠 흉내 — P-256 */
const { privateKey, publicKey } = crypto.generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
const pem = privateKey.export({ type: 'pkcs8', format: 'pem' });

/* --- JWT ---------------------------------------------------------------- */
{
  const t = asc.makeJwt({ keyId: 'ABC123', issuerId: 'iss-1', pem, now: 1_700_000_000_000 });
  const [h, p, s] = t.split('.');
  const dec = x => JSON.parse(Buffer.from(x.replace(/-/g, '+').replace(/_/g, '/'), 'base64').toString());
  ok(dec(h).alg === 'ES256' && dec(h).kid === 'ABC123' && dec(h).typ === 'JWT', 'JWT 머리: ES256 · kid · typ');
  const pl = dec(p);
  ok(pl.iss === 'iss-1' && pl.aud === 'appstoreconnect-v1' && pl.exp - pl.iat === 900, 'JWT 본문: iss · aud · 15분');
  const sig = Buffer.from(s.replace(/-/g, '+').replace(/_/g, '/'), 'base64');
  ok(sig.length === 64, '서명은 R‖S 64바이트 (DER 아님)');
  ok(crypto.verify('sha256', Buffer.from(h + '.' + p), { key: publicKey, dsaEncoding: 'ieee-p1363' }, sig),
     '같은 열쇠의 공개키로 서명이 검증된다');
}

/* --- 열쇠 읽기 ----------------------------------------------------------- */
{
  ok(asc.loadKeyPem({ ASC_KEY_P8: pem }).includes('BEGIN PRIVATE KEY'), 'PEM 원문 그대로');
  ok(asc.loadKeyPem({ ASC_KEY_P8_BASE64: Buffer.from(pem).toString('base64') }).includes('BEGIN PRIVATE KEY'), 'base64 로 감싼 PEM');
  const body = pem.replace(/-----[^-]+-----/g, '').replace(/\s+/g, '');
  const k = asc.loadKeyPem({ ASC_KEY_P8_BASE64: body });
  let parsed = false;
  try { crypto.createPrivateKey(k); parsed = true; } catch (e) { parsed = false; }
  ok(parsed, 'PEM 머리 없이 본문만 넣어도 열쇠로 읽힌다');
  let threw = false;
  try { asc.loadKeyPem({}); } catch (e) { threw = true; }
  ok(threw, '열쇠가 없으면 바로 멈춘다');
}

/* --- 가짜 애플 ----------------------------------------------------------- */
function fakeApple(state) {
  const calls = [];
  const json = (status, body) => ({ ok: status < 400, status, text: async () => JSON.stringify(body) });
  const fetchImpl = async (url, init) => {
    const u = new URL(url);
    const m = init.method;
    calls.push(m + ' ' + u.pathname + (u.search || ''));
    const auth = init.headers.authorization || '';
    if (!/^Bearer [\w-]+\.[\w-]+\.[\w-]+$/.test(auth)) return json(401, { errors: [{ status: '401', title: 'NOT_AUTHORIZED' }] });
    const body = init.body ? JSON.parse(init.body) : null;

    if (m === 'GET' && u.pathname === '/v1/bundleIds') {
      const want = u.searchParams.get('filter[identifier]');
      return json(200, { data: state.bundleIds.filter(b => !want || b.attributes.identifier === want) });
    }
    if (m === 'POST' && u.pathname === '/v1/bundleIds') {
      const b = { type: 'bundleIds', id: 'B' + (state.bundleIds.length + 1), attributes: body.data.attributes };
      state.bundleIds.push(b);
      return json(201, { data: b });
    }
    if (m === 'GET' && u.pathname === '/v1/profiles') {
      const want = u.searchParams.get('filter[name]');
      return json(200, { data: state.profiles.filter(p => !want || p.attributes.name === want) });
    }
    const pc = u.pathname.match(/^\/v1\/profiles\/([^/]+)\/certificates$/);
    if (m === 'GET' && pc) {
      const p = state.profiles.find(x => x.id === pc[1]);
      return json(200, { data: (p ? p.certs : []).map(id => ({ type: 'certificates', id })) });
    }
    const pd = u.pathname.match(/^\/v1\/profiles\/([^/]+)$/);
    if (m === 'DELETE' && pd) {
      state.profiles = state.profiles.filter(x => x.id !== pd[1]);
      return { ok: true, status: 204, text: async () => '' };
    }
    const cd = u.pathname.match(/^\/v1\/certificates\/([^/]+)$/);
    if (m === 'DELETE' && cd) {
      state.certs = state.certs.filter(x => x.id !== cd[1]);
      return { ok: true, status: 204, text: async () => '' };
    }
    if (m === 'POST' && u.pathname === '/v1/certificates') {
      if (state.certs.length >= state.maxCerts) {
        return json(409, { errors: [{ status: '409', code: 'ENTITY_ERROR', title: 'There is a problem with the request entity', detail: 'You already have a current Distribution certificate or a pending certificate request. Maximum reached.' }] });
      }
      if (!/BEGIN CERTIFICATE REQUEST/.test(body.data.attributes.csrContent)) return json(400, { errors: [{ title: 'bad csr' }] });
      const c = { type: 'certificates', id: 'C' + (++state.certSeq), attributes: { certificateType: 'DISTRIBUTION', displayName: 'Tester', certificateContent: Buffer.from('DER' + state.certSeq).toString('base64') } };
      state.certs.push(c);
      return json(201, { data: c });
    }
    if (m === 'POST' && u.pathname === '/v1/profiles') {
      const certIds = body.data.relationships.certificates.data.map(x => x.id);
      const p = { type: 'profiles', id: 'P' + (++state.profSeq), certs: certIds,
                  attributes: { name: body.data.attributes.name, profileType: body.data.attributes.profileType, uuid: 'uuid-' + state.profSeq, profileContent: Buffer.from('PROFILE' + state.profSeq).toString('base64') } };
      state.profiles.push(p);
      return json(201, { data: p });
    }
    return json(404, { errors: [{ title: 'no route ' + m + ' ' + u.pathname }] });
  };
  return { fetchImpl, calls };
}

const csrPem = '-----BEGIN CERTIFICATE REQUEST-----\nMIIB\n-----END CERTIFICATE REQUEST-----\n';
const out = fs.mkdtempSync(path.join(os.tmpdir(), 'asc-'));

(async () => {
  /* 첫 실행 — 아무것도 없는 계정 */
  const state = { bundleIds: [], certs: [{ type: 'certificates', id: 'MAC1', attributes: {} }], profiles: [], certSeq: 0, profSeq: 0, maxCerts: 3 };
  const a = fakeApple(state);
  const r1 = await asc.prepare({ keyId: 'K', issuerId: 'I', pem, fetchImpl: a.fetchImpl, bundle: 'io.example.app', csrPem, out, profileName: 'Mybody AppStore GHA' });
  ok(r1.bundleCreated === true && state.bundleIds.length === 1, '번들 ID 가 없으면 등록한다');
  ok(r1.revoked.length === 0, '첫 실행은 아무것도 폐기하지 않는다');
  ok(state.certs.some(c => c.id === 'MAC1'), '맥에서 만든(남의) 인증서는 그대로');
  ok(r1.certificateId === 'C1' && r1.profileId === 'P1', '인증서와 프로파일이 생긴다');
  ok(fs.readFileSync(r1.certFile).toString() === 'DER1', 'cert.cer 는 DER 본문');
  ok(fs.readFileSync(r1.profileFile).toString() === 'PROFILE1', 'profile.mobileprovision 본문');
  ok(a.calls[0].startsWith('GET /v1/bundleIds?filter') && a.calls.includes('POST /v1/certificates') && a.calls[a.calls.length - 1] === 'POST /v1/profiles',
     '순서: 번들 확인 → 인증서 → 프로파일');

  /* 두 번째 실행 — 지난 인증서를 폐기하고 새로 */
  const b = fakeApple(state);
  const r2 = await asc.prepare({ keyId: 'K', issuerId: 'I', pem, fetchImpl: b.fetchImpl, bundle: 'io.example.app', csrPem, out, profileName: 'Mybody AppStore GHA' });
  ok(r2.bundleCreated === false && state.bundleIds.length === 1, '번들 ID 는 다시 안 만든다');
  ok(r2.revoked.length === 1 && r2.revoked[0] === 'C1', '지난 실행의 인증서(C1)만 폐기');
  ok(!state.certs.some(c => c.id === 'C1') && state.certs.some(c => c.id === 'MAC1'), 'C1 은 없어지고 MAC1 은 남는다');
  ok(state.profiles.length === 1 && state.profiles[0].id === 'P2', '프로파일은 하나만 남는다 (새것)');
  ok(r2.certificateId === 'C2', '새 인증서');

  /* 한도에 걸리면 무엇을 하라고 말하는가 */
  const state3 = { bundleIds: [{ type: 'bundleIds', id: 'B1', attributes: { identifier: 'io.example.app' } }], certs: [{ id: 'X1' }, { id: 'X2' }, { id: 'X3' }], profiles: [], certSeq: 9, profSeq: 0, maxCerts: 3 };
  const c3 = fakeApple(state3);
  let msg = '';
  try { await asc.prepare({ keyId: 'K', issuerId: 'I', pem, fetchImpl: c3.fetchImpl, bundle: 'io.example.app', csrPem, out, profileName: 'X' }); }
  catch (e) { msg = e.message; }
  ok(/Revoke/.test(msg) && /developer.apple.com/.test(msg), '인증서 한도면 어디서 무엇을 지우라고 말한다');

  /* 열쇠가 틀리면 401 이 그대로 올라온다 */
  const c4 = fakeApple({ bundleIds: [], certs: [], profiles: [], certSeq: 0, profSeq: 0, maxCerts: 3 });
  let m4 = '';
  try {
    await asc.prepare({ keyId: 'K', issuerId: 'I', pem, fetchImpl: async (u, i) => { i.headers.authorization = 'Bearer nope'; return c4.fetchImpl(u, i); }, bundle: 'x', csrPem, out, profileName: 'X' });
  } catch (e) { m4 = e.message; }
  ok(/401/.test(m4), '인증 실패는 401 로 바로 보인다');

  /* 앱 타깃만 수동 서명 — 진짜 프로젝트 파일로 */
  const { patch } = require('./ios-sign-project.js');
  const pbx = fs.readFileSync(path.join(__dirname, '..', 'app', 'ios', 'Runner.xcodeproj', 'project.pbxproj'), 'utf8');
  const r = patch(pbx, { team: 'ABCDE12345', profile: 'Mybody AppStore GHA', bundle: 'io.github.iacobuschoi.mybody' });
  ok(r.touched.sort().join(',') === 'Profile,Release', 'Runner 의 Release·Profile 두 곳만 고친다');
  ok((r.text.match(/PROVISIONING_PROFILE_SPECIFIER = "Mybody AppStore GHA";/g) || []).length === 2, '프로파일 이름이 두 번 들어간다');
  ok(!/RunnerTests;[\s\S]{0,400}PROVISIONING_PROFILE_SPECIFIER/.test(r.text), '시험 타깃(RunnerTests)은 안 건드린다');
  const removed = pbx.split('\n').filter(l => !r.text.includes(l));
  ok(removed.length === 0, '원래 줄은 하나도 안 없어진다 (넣기만)');
  ok(patch(r.text, { team: 'ABCDE12345', profile: 'Mybody AppStore GHA', bundle: 'io.github.iacobuschoi.mybody' }).text === r.text, '두 번 돌려도 같다');
  let bad = false;
  try { patch(pbx, { team: 'abc', profile: 'x', bundle: 'y' }); } catch (e) { bad = true; }
  ok(bad, '팀 ID 가 이상하면 멈춘다');

  /* 앱 알림 — --entitlements 를 주면 두 곳, 안 주면 0곳 */
  const BID = 'io.github.iacobuschoi.mybody';
  ok(!/CODE_SIGN_ENTITLEMENTS/.test(r.text), '엔타이틀먼트를 안 주면 CODE_SIGN_ENTITLEMENTS 는 0곳 (예전 그대로)');
  const re = patch(pbx, { team: 'ABCDE12345', profile: 'Mybody AppStore GHA', bundle: BID,
                          entitlements: 'Runner/Runner.entitlements' });
  const entLines = re.text.match(/CODE_SIGN_ENTITLEMENTS = Runner\/Runner\.entitlements;/g) || [];
  ok(entLines.length === 2 && re.touched.sort().join(',') === 'Profile,Release',
     '엔타이틀먼트를 주면 Runner 의 Release·Profile 두 곳에만 들어간다');
  /* CI 가 확인할 때 쓰는 grep 과 같은 식으로 — 들어갔는데 CI 가 못 찾으면 알림을 끕니다 */
  ok((re.text.match(/CODE_SIGN_ENTITLEMENTS = "?Runner\/Runner\.entitlements"?;/g) || []).length === 2,
     'CI 의 확인(grep)이 두 곳을 센다');
  ok(!/RunnerTests;[\s\S]{0,400}CODE_SIGN_ENTITLEMENTS/.test(re.text), '시험 타깃은 안 건드린다');
  ok(pbx.split('\n').filter(l => !re.text.includes(l)).length === 0, '엔타이틀먼트를 넣어도 원래 줄은 안 없어진다');
  /* Xcode 처럼 키 이름순 — CODE_SIGN_ENTITLEMENTS 는 CODE_SIGN_IDENTITY 앞 */
  const relBlock = (re.text.match(/buildSettings = \{[^}]*PROVISIONING_PROFILE_SPECIFIER = "Mybody AppStore GHA";[\s\S]*?\n\t\t\t\};/) || [''])[0];
  ok(relBlock.indexOf('CODE_SIGN_ENTITLEMENTS') >= 0 &&
     relBlock.indexOf('CODE_SIGN_ENTITLEMENTS') < relBlock.indexOf('CODE_SIGN_IDENTITY = '), '키 이름순을 지킨다');
  ok(patch(re.text, { team: 'ABCDE12345', profile: 'Mybody AppStore GHA', bundle: BID,
                      entitlements: 'Runner/Runner.entitlements' }).text === re.text, '엔타이틀먼트도 두 번 돌려도 같다');
  for (const badEnt of ['Runner/"x.entitlements', 'Runner/x.entitlements\nFOO = 1', '../Runner.entitlements',
                        '/etc/x.entitlements', 'Runner/Runner.plist', 'Runner/a;b.entitlements']) {
    let threw = false;
    try { patch(pbx, { team: 'ABCDE12345', profile: 'P', bundle: BID, entitlements: badEnt }); } catch (e) { threw = true; }
    ok(threw, '이상한 엔타이틀먼트 경로는 거절: ' + JSON.stringify(badEnt));
  }
  ok(require('./ios-sign-project.js').supportsEntitlements === true, 'CI 가 물을 수 있게 지원 여부를 내보낸다');
  {
    const tmp = path.join(os.tmpdir(), 'mybody-pbx-' + process.pid + '.pbxproj');
    fs.writeFileSync(tmp, pbx);
    const run = extra => require('node:child_process').spawnSync(process.execPath,
      [path.join(__dirname, 'ios-sign-project.js'), '--team', 'ABCDE12345', '--profile', 'P', '--project', tmp].concat(extra),
      { encoding: 'utf8' });
    const r1 = run(['--entitlements', 'Runner/Runner.entitlements']);
    ok(r1.status === 0 && (fs.readFileSync(tmp, 'utf8').match(/CODE_SIGN_ENTITLEMENTS/g) || []).length === 2,
       '명령줄 --entitlements 가 실제로 먹는다 (예전에는 조용히 버렸음)');
    fs.writeFileSync(tmp, pbx);
    const r2 = run(['--entitlements', '../x.entitlements']);
    ok(r2.status !== 0 && fs.readFileSync(tmp, 'utf8') === pbx, '명령줄에서도 이상한 경로면 멈추고 파일을 안 고친다');
    fs.rmSync(tmp, { force: true });
  }

  fs.rmSync(out, { recursive: true, force: true });
  console.log(`\n통과 ${pass} / 실패 ${fail}`);
  process.exit(fail ? 1 : 0);
})().catch(e => { console.error(e); process.exit(1); });
