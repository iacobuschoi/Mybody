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

/* =============================================================================
 * 아이폰 TestFlight 워크플로(.github/workflows/ios-release.yml) — 초대 링크(Universal Links)
 *
 * 친구가 받은 https://<서버>/i/<코드> 를 누르면 사파리 없이 앱이 열리려면 서명에
 * associated-domains = ["applinks:<서버 호스트>"] 가 붙어야 합니다. CI 는 맥 러너에서만 돌고
 * 한 번 도는 데 30분이라, 잘못 짠 bash 한 줄(bash -e 에서 실패하는 명령)이 **릴리스 전체를**
 * 멈출 수 있습니다 — 초대 링크는 부가 기능인데요. 그래서
 *   · 호스트를 떼는 단계와 서명 설정 단계의 bash 를 **그대로 꺼내 여기서 돌려 봅니다**
 *     (PlistBuddy 는 가짜 · 서명 도구와 프로젝트 파일은 진짜의 사본). 어느 길로 가도 0 으로
 *     끝나고, 프로파일에 없는 권한은 절대 붙이지 않는지.
 *   · 나머지는 글자로 봅니다: App ID 에 Associated Domains 를 켜는 단계(자동 서명일 때만 ·
 *     limit 없이 · 409 는 이미 있음), 프로파일에서 권한을 읽는 줄, 나온 앱을 열어 보는 확인.
 * ========================================================================== */
function iosReleaseWorkflow() {
  const { spawnSync } = require('node:child_process');
  const ROOT = path.join(__dirname, '..');
  const WF = path.join(ROOT, '.github', 'workflows', 'ios-release.yml');
  const wf = fs.readFileSync(WF, 'utf8');
  console.log('\n아이폰 워크플로 — 초대 링크(Universal Links)');

  /* 단계 나누기 — steps: 아래 "- " 가 한 단계의 시작입니다(들여쓰기로만 봅니다). */
  const lines = wf.split('\n');
  const stepsAt = lines.findIndex(l => /^\s*steps:\s*$/.test(l));
  const itemIndent = stepsAt >= 0 ? lines[stepsAt].match(/^\s*/)[0].length + 2 : 6;
  const steps = [];
  for (let i = stepsAt + 1; i < lines.length; i++) {
    const l = lines[i];
    const ind = l.match(/^\s*/)[0].length;
    if (l.trim() && ind < itemIndent) break;
    if (ind === itemIndent && l.slice(ind).startsWith('- ')) steps.push({ start: i, lines: [] });
    if (steps.length) steps[steps.length - 1].lines.push(l);
  }
  for (const s of steps) {
    s.text = s.lines.join('\n');
    s.name = ((s.text.match(/^\s*-?\s*name:\s*(.+)$/m) || [])[1] || '').trim();
    const ri = s.lines.findIndex(l => /^\s*run:\s*\|\s*$/.test(l));
    if (ri >= 0) {
      const runIndent = s.lines[ri].match(/^\s*/)[0].length;
      const body = [];
      for (let j = ri + 1; j < s.lines.length; j++) {
        const l = s.lines[j];
        if (l.trim() && l.match(/^\s*/)[0].length <= runIndent) break;
        body.push(l);
      }
      const min = Math.min(...body.filter(l => l.trim()).map(l => l.match(/^\s*/)[0].length));
      s.run = body.map(l => l.slice(min)).join('\n').replace(/\s+$/, '') + '\n';
    }
  }
  const step = n => steps.find(s => s.name.startsWith(n));
  const idx = n => steps.findIndex(s => s.name.startsWith(n));

  const HOST_STEP = '초대 링크 주소';
  const CAP_STEP = 'App ID 에 초대 링크(Associated Domains) 켜기';
  const PUSH_STEP = 'App ID 에 푸시 켜기';
  const SIGN_STEP = '앱 타깃 서명 설정';
  const host = step(HOST_STEP), cap = step(CAP_STEP), push = step(PUSH_STEP), sign = step(SIGN_STEP);
  const prof = step('프로파일 설치'), check = step('나온 앱에 앱 알림이 들어갔는가'), up = step('TestFlight 에 올리기');
  ok(host && cap && push && sign && prof && check && up, '단계가 다 있다 (호스트 · App ID 둘 · 프로파일 · 서명 · 확인 · 올리기)');
  if (!(host && cap && push && sign && prof && check && up)) return;

  /* --- 순서와 조건 (글자) --- */
  ok(idx(HOST_STEP) < idx(CAP_STEP) && idx(CAP_STEP) < idx('인증서·프로파일 만들기') &&
     idx('인증서·프로파일 만들기') < idx('프로파일 설치') && idx('프로파일 설치') < idx(SIGN_STEP),
     '순서: 호스트 → App ID 켜기 → 프로파일 새로 만들기 → 프로파일 읽기 → 서명 (켠 뒤에 만들어야 권한이 들어옴)');
  const capIf = (cap.text.match(/^\s*if:\s*(.+)$/m) || [])[1] || '';
  ok(/env\.mode == 'auto'/.test(capIf) && /env\.invite_host != ''/.test(capIf),
     'Associated Domains 켜기는 자동 서명 · 호스트가 정해졌을 때만 (수동 프로파일을 무효로 만들지 않음)');
  ok(/if:\s*env\.mode == 'auto' && env\.fcm == 'yes'/.test(push.text) && /'PUSH_NOTIFICATIONS'/.test(push.text),
     '푸시 켜기 단계는 예전 조건 그대로 (초대 링크 때문에 바뀌지 않음)');
  ok(/const TYPE = 'ASSOCIATED_DOMAINS'/.test(cap.text) &&
     /c\.call\('GET', `\/v1\/bundleIds\/\$\{bundleIdId\}\/bundleIdCapabilities`\)/.test(cap.text) &&
     /c\.call\('POST', '\/v1\/bundleIdCapabilities'/.test(cap.text) && /e\.status === 409/.test(cap.text),
     'App ID 에 ASSOCIATED_DOMAINS: GET → 없으면 POST, 409 는 이미 있음');
  ok(/supportsEntitlements/.test(cap.text) && /ul_cap=/.test(cap.text) && /\|\| echo "ul_cap=failed"/.test(cap.run || ''),
     '서명 도구가 권한을 못 붙이는 판이면 App ID 를 안 건드리고, 어떻게 실패해도 단계는 안 멈춤');
  const capLines = [wf, fs.readFileSync(path.join(__dirname, 'asc.js'), 'utf8')].join('\n').split('\n')
    .filter(l => /bundleIdCapabilities/.test(l) && !/^\s*(\/\*|\*|\/\/|#)/.test(l) && !/limit 을 붙이면/.test(l));
  ok(capLines.length > 0 && capLines.every(l => !/limit/.test(l)),
     'bundleIdCapabilities 요청에 limit 이 없다 (붙이면 애플이 400 PARAMETER_ERROR.ILLEGAL)');
  ok(/Print :Entitlements:com\.apple\.developer\.associated-domains/.test(prof.text) && /profile_ad=\$ad/.test(prof.text),
     '프로파일에서 associated-domains 가 있는지 읽어 profile_ad 로 (값은 옮기지 않음 — 배열일 수 있음)');
  ok(check.text.includes('continue-on-error: true') && /com\.apple\.developer\.associated-domains/.test(check.text) &&
     /applinks:\$invite_host/.test(check.text) && /ul=partial/.test(check.text),
     '나온 앱의 서명에 applinks:<호스트> 가 있는지 보고, 없으면 경고만 (continue-on-error)');
  ok(/초대 링크\(Universal Links\): \*\*켜짐\*\*/.test(up.text) && /초대 링크\(Universal Links\): 꺼짐 — /.test(up.text),
     '요약에 「초대 링크(Universal Links): 켜짐/꺼짐 — 이유」 한 줄');

  /* 기본 호스트 = 앱의 기본 서버(lib/main.dart) = 안드로이드(build.gradle.kts). */
  const dartDefault = (fs.readFileSync(path.join(ROOT, 'app', 'lib', 'main.dart'), 'utf8')
    .match(/'SERVER_URL',\s*defaultValue:\s*'https:\/\/([^'/:]+)/) || [])[1];
  const gradleFallback = (fs.readFileSync(path.join(ROOT, 'app', 'android', 'app', 'build.gradle.kts'), 'utf8')
    .match(/val fallback = "([^"]+)"/) || [])[1];
  const wfFallback = ((host.run || '').match(/^fallback=(\S+)$/m) || [])[1];
  ok(dartDefault && wfFallback === dartDefault && gradleFallback === dartDefault,
     '비밀이 없을 때의 호스트가 앱 · 안드로이드 · 아이폰 셋 다 같다 (' + wfFallback + ')');

  /* 이 단계들은 비밀을 다루므로 set +x 로 시작합니다(명령이 로그에 펼쳐지지 않게). */
  ok([host, cap, sign].every(s => /^set \+x$/m.test(s.run || '')), '비밀을 만지는 단계는 set +x');

  const tmpRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'mybody-iosrel-'));
  const nodeDir = path.dirname(process.execPath);
  /* 워크플로는 맥 러너의 bash 로 돕니다. 윈도우(노트북)의 Git Bash 는 경로 · 실행 권한이 달라 건너뜁니다. */
  const bashOk = process.platform !== 'win32' && spawnSync('bash', ['-c', 'true']).status === 0;
  if (!bashOk) {
    console.log('  · bash 가 없거나 윈도우라 단계를 돌려 보는 시험은 건너뜁니다');
    fs.rmSync(tmpRoot, { recursive: true, force: true });
    return;
  }
  /* 깃허브의 bash 와 같게: bash --noprofile --norc -eo pipefail */
  function runStep(script, env, cwd) {
    const f = path.join(tmpRoot, 'step-' + Math.random().toString(36).slice(2) + '.sh');
    fs.writeFileSync(f, script);
    const ghEnv = path.join(tmpRoot, 'ghenv-' + Math.random().toString(36).slice(2));
    fs.writeFileSync(ghEnv, '');
    const r = spawnSync('bash', ['--noprofile', '--norc', '-eo', 'pipefail', f], {
      cwd: cwd || tmpRoot, encoding: 'utf8',
      env: Object.assign({ PATH: nodeDir + path.delimiter + (process.env.PATH || '/usr/bin:/bin'), GITHUB_ENV: ghEnv }, env) });
    const vars = {};
    for (const l of fs.readFileSync(ghEnv, 'utf8').split('\n')) {
      const i = l.indexOf('=');
      if (i > 0) vars[l.slice(0, i)] = l.slice(i + 1);
    }
    return { status: r.status, out: (r.stdout || '') + (r.stderr || ''), vars, envLines: fs.readFileSync(ghEnv, 'utf8') };
  }

  /* --- 호스트 떼기: 진짜 bash 로 --- */
  const HOST_CASES = [
    ['', dartDefault, '비었으면 기본 호스트'],
    ['https://Mybody.Example.COM:8443/api?x=1#y', 'mybody.example.com', '포트 · 경로 · 물음 · 조각을 버리고 소문자'],
    ['https://user:pw@srv.tail1.ts.net/', 'srv.tail1.ts.net', '사용자:비밀번호@ 를 버림'],
    ['  https://sp.example.com/\n', 'sp.example.com', '붙여 넣을 때 섞인 공백 · 줄바꿈'],
    ['HTTPS://Up.Example.com', 'up.example.com', 'HTTPS 대문자도 https'],
    ['srv2.example.org', 'srv2.example.org', 'scheme 없이 호스트만'],
    ['http://plain.example.com', '', 'http 는 끔 (연결된 도메인은 https 만)'],
    ['https://1.2.3.4/', '', 'IP 주소는 끔'],
    ['https://localhost', '', '점 없는 이름은 끔'],
    ['https://bad_host.com', '', '호스트에 못 쓰는 글자면 끔'],
    ['https://x.com\ninvite_host=evil.com\nul=yes', '', '줄바꿈으로 GITHUB_ENV 에 끼워 넣기 — 안 먹힘'],
    ['https://a.com;rm -rf /', '', '셸 글자가 섞이면 끔 (실행되지 않음)'],
    ['https://$(touch pwned).example.com', '', '$(…) 는 실행되지 않고 끔'],
  ];
  for (const [su, want, why] of HOST_CASES) {
    const r = runStep(host.run, { SU: su });
    const got = r.vars.invite_host;
    const extraKeys = Object.keys(r.vars).filter(k => !['invite_host', 'ul', 'ul_why'].includes(k));
    const good = r.status === 0 && (got || '') === want && !extraKeys.length &&
      (want ? !r.vars.ul : r.vars.ul === 'no' && !!r.vars.ul_why) && !fs.existsSync(path.join(tmpRoot, 'pwned'));
    ok(good, '호스트: ' + why + (good ? '' : ' — 받은 ' + JSON.stringify({ status: r.status, vars: r.vars })));
  }
  /* GITHUB_ENV 에 쓴 값은 뒤 단계마다 로그의 env: 목록에 펼쳐집니다 — 그래서 가리기(::add-mask::)
     명령 말고는 어디에도 호스트가 나오면 안 되고, 가리기는 GITHUB_ENV 에 쓰기 **전에** 해야 합니다.
     (러너는 ::add-mask:: 줄 자체는 로그에 남기지 않습니다.) */
  {
    const r = runStep(host.run, { SU: 'https://secret-host.example.net/x' });
    const outLines = r.out.split('\n');
    const maskAt = outLines.findIndex(l => l === '::add-mask::secret-host.example.net');
    ok(r.vars.invite_host === 'secret-host.example.net' && maskAt >= 0 &&
       outLines.every((l, i) => i === maskAt || !l.includes('secret-host')),
       '비밀에서 나온 호스트를 로그에 찍지 않고, 뒤 단계의 env: 목록에서도 가린다 (::add-mask::)');
    ok(!/add-mask/.test(runStep(host.run, { SU: '' }).out),
       '비밀이 비어 기본 호스트(저장소에 이미 있는 값)를 쓸 때는 가리지 않는다');
    const maskLine = host.run.split('\n').findIndex(l => /::add-mask::\$host/.test(l));
    const envLine = host.run.split('\n').findIndex(l => /echo "invite_host=\$host" >> "\$GITHUB_ENV"/.test(l));
    ok(maskLine >= 0 && envLine > maskLine, '가리기가 GITHUB_ENV 에 쓰기보다 먼저');
  }

  /* --- 서명 설정: 진짜 bash · 진짜 서명 도구(사본) · 가짜 PlistBuddy --- */
  const fakePb = path.join(tmpRoot, 'PlistBuddy');
  fs.writeFileSync(fakePb, `#!/usr/bin/env node
'use strict';
/* PlistBuddy 흉내 — Set · Add · Delete · Print 만. 상태는 FAKE_PB_STATE(JSON). 한 명령이라도
   틀리면 저장하지 않고 1 로 끝납니다. FAKE_PB_FAIL 글자가 든 명령은 일부러 실패. */
const fs = require('fs');
const a = process.argv.slice(2), cmds = [];
for (let i = 0; i < a.length; i++) if (a[i] === '-c') cmds.push(a[++i]);
const st = process.env.FAKE_PB_STATE;
const s = fs.existsSync(st) ? JSON.parse(fs.readFileSync(st, 'utf8')) : {};
const die = m => { console.error(m); process.exit(1); };
for (const c of cmds) {
  if (process.env.FAKE_PB_FAIL && c.includes(process.env.FAKE_PB_FAIL)) die('일부러 실패: ' + c);
  const p = c.split(' ');
  const keyPath = (p[1] || '').replace(/^:/, '').split(':');
  const k = keyPath[0];
  if (p[0] === 'Set') { if (!(k in s)) die('Does Not Exist'); s[k] = p.slice(2).join(' '); }
  else if (p[0] === 'Delete') { if (!(k in s)) die('Does Not Exist'); delete s[k]; }
  else if (p[0] === 'Print') { if (!(k in s)) die('Does Not Exist'); console.log(s[k]); }
  else if (p[0] === 'Add') {
    const v = p.slice(3).join(' ');
    if (keyPath.length > 1) { if (!Array.isArray(s[k])) die('Not an array'); s[k].push(v); }
    else { if (k in s) die('Entry Already Exists'); s[k] = p[2] === 'array' ? [] : v; }
  } else die('모르는 명령 ' + c);
}
fs.writeFileSync(st, JSON.stringify(s));
`, { mode: 0o755 });
  const PBX = fs.readFileSync(path.join(ROOT, 'app', 'ios', 'Runner.xcodeproj', 'project.pbxproj'), 'utf8');
  const signScript = sign.run.split('/usr/libexec/PlistBuddy').join(fakePb);
  ok(signScript !== sign.run, '서명 단계가 PlistBuddy 로 엔타이틀먼트를 고친다');
  const AD = 'com.apple.developer.associated-domains';
  const BASE = { team_id: 'ABCDE12345', profile_name: 'Mybody AppStore GHA', BUNDLE_ID: 'io.github.iacobuschoi.mybody' };
  function sign1(env, opt) {
    opt = opt || {};
    const dir = fs.mkdtempSync(path.join(tmpRoot, 'repo-'));
    fs.mkdirSync(path.join(dir, 'app', 'ios', 'Runner.xcodeproj'), { recursive: true });
    fs.mkdirSync(path.join(dir, 'app', 'ios', 'Runner'), { recursive: true });
    fs.mkdirSync(path.join(dir, 'tools'), { recursive: true });
    fs.writeFileSync(path.join(dir, 'app', 'ios', 'Runner.xcodeproj', 'project.pbxproj'), PBX);
    fs.copyFileSync(path.join(ROOT, 'app', 'ios', 'Runner', 'Runner.entitlements'), path.join(dir, 'app', 'ios', 'Runner', 'Runner.entitlements'));
    fs.writeFileSync(path.join(dir, 'app', 'ios', 'Runner', 'GoogleService-Info.plist'), 'x');
    fs.writeFileSync(path.join(dir, 'tools', 'ios-sign-project.js'), opt.oldSignTool
      ? "console.log('수동 서명으로 바꿈 (옛 판 — 모르는 인자는 버림)');\n"
      : fs.readFileSync(path.join(__dirname, 'ios-sign-project.js'), 'utf8'));
    const state = path.join(dir, 'pb.json');
    fs.writeFileSync(state, JSON.stringify({ 'aps-environment': 'production' }));   /* 커밋된 파일의 내용 */
    const r = runStep(signScript, Object.assign({ FAKE_PB_STATE: state, FAKE_PB_FAIL: opt.pbFail || '' }, BASE, env), dir);
    r.ent = JSON.parse(fs.readFileSync(state, 'utf8'));
    r.attached = (fs.readFileSync(path.join(dir, 'app', 'ios', 'Runner.xcodeproj', 'project.pbxproj'), 'utf8')
      .match(/CODE_SIGN_ENTITLEMENTS = "?Runner\/Runner\.entitlements"?;/g) || []).length;
    r.plistLeft = fs.existsSync(path.join(dir, 'app', 'ios', 'Runner', 'GoogleService-Info.plist'));
    return r;
  }
  const H = 'mybody.example.com';
  const same = (x, y) => JSON.stringify(x) === JSON.stringify(y);
  {
    const r = sign1({ mode: 'auto', fcm: 'no', invite_host: H, profile_ad: 'yes', ul_cap: 'created' });
    ok(r.status === 0 && same(r.ent, { [AD]: ['applinks:' + H] }) && r.attached === 2 && r.vars.ul === 'yes' &&
       /초대 링크\(Universal Links\): 켜짐/.test(r.out),
       '푸시가 꺼진 날에도 초대 링크만 붙인다 — aps-environment 는 지우고 applinks 만 (' + JSON.stringify(r.ent) + ')');
  }
  {
    const r = sign1({ mode: 'auto', fcm: 'yes', profile_aps: 'production', invite_host: H, profile_ad: 'yes' });
    ok(r.status === 0 && same(r.ent, { 'aps-environment': 'production', [AD]: ['applinks:' + H] }) && r.attached === 2 &&
       r.vars.ul === 'yes' && r.plistLeft, '둘 다 맞으면 둘 다 붙인다');
  }
  {
    const r = sign1({ mode: 'auto', fcm: 'yes', profile_aps: 'production', invite_host: H, profile_ad: 'no', ul_cap: 'failed' });
    ok(r.status === 0 && same(r.ent, { 'aps-environment': 'production' }) && r.attached === 2 && r.vars.ul === 'no' &&
       /연결된 도메인 권한이 없음/.test(r.vars.ul_why) && /꺼짐 — /.test(r.out),
       '프로파일에 연결된 도메인 권한이 없으면 applinks 는 안 붙이고 (서명 안 깨짐) 푸시는 그대로');
  }
  {
    const r = sign1({ mode: 'manual', fcm: 'no', invite_host: H, profile_ad: 'no' });
    ok(r.status === 0 && r.attached === 0 && r.vars.ul === 'no' && /Associated Domains 를 켜고 프로파일을 다시/.test(r.vars.ul_why),
       '수동 프로파일에 권한이 없으면 무엇을 하라고 말하고, 엔타이틀먼트는 안 붙인다 (예전 그대로)');
  }
  {
    const r = sign1({ mode: 'auto', fcm: 'no', invite_host: '', ul: 'no', ul_why: '서버 주소가 https 가 아님', profile_ad: 'yes' });
    ok(r.status === 0 && r.attached === 0 && !(AD in r.ent) && /꺼짐 — 서버 주소가 https 가 아님/.test(r.out),
       '호스트가 없으면 앞 단계의 이유를 그대로 말하고 아무것도 안 붙인다');
  }
  {
    const r = sign1({ mode: 'auto', fcm: 'yes', profile_aps: '', invite_host: H, profile_ad: 'yes' });
    ok(r.status === 0 && same(r.ent, { [AD]: ['applinks:' + H] }) && r.attached === 2 && r.vars.fcm === 'no' && !r.plistLeft,
       '푸시 권한이 없는 프로파일이면 푸시는 끄고(plist 치움) 초대 링크만 붙인다');
  }
  {
    const r = sign1({ mode: 'auto', fcm: 'no', invite_host: H, profile_ad: 'yes' }, { pbFail: 'applinks:' });
    ok(r.status === 0 && r.attached === 0 && !(AD in r.ent) && r.vars.ul === 'no' && /PlistBuddy/.test(r.vars.ul_why),
       'applinks 를 못 적으면 초대 링크만 끄고 빌드는 계속 (단계가 0 으로 끝남)');
  }
  {
    const r = sign1({ mode: 'auto', fcm: 'yes', profile_aps: 'production', invite_host: H, profile_ad: 'yes' }, { oldSignTool: true });
    ok(r.status === 0 && r.attached === 0 && r.vars.ul === 'no' && r.vars.fcm === 'no' && !r.plistLeft,
       '서명 도구가 엔타이틀먼트를 못 넣으면 둘 다 끄고 빌드는 계속');
  }
  {
    const r = sign1({ mode: 'auto', fcm: 'no', invite_host: '', profile_ad: 'no' });
    ok(r.status === 0 && r.attached === 0 && !r.vars.ul_cap,
       '둘 다 아니면 예전과 같다 — 엔타이틀먼트를 안 붙임');
  }

  /* 워크플로 파일 자체가 YAML 로 읽히는가 — python3 · PyYAML 이 있을 때만. 실패로 치는 것은
     PyYAML 이 낸 문법 오류뿐입니다 — python3 이 없거나 가짜(맥의 「도구를 설치하세요」 껍데기)면
     건너뜁니다. 시험할 수 없는 것을 워크플로가 틀렸다고 말하지 않게. */
  const py = spawnSync('python3', ['-c', 'import sys, yaml; yaml.safe_load(open(sys.argv[1], encoding="utf-8")); print("ok")', WF],
                       { encoding: 'utf8' });
  const pyErr = (py.stderr || '') + String(py.error || '');
  if (py.status === 0 && /ok/.test(py.stdout)) ok(true, 'ios-release.yml 이 YAML 로 읽힌다');
  else if (/yaml\.\w+\.\w*(Error|Exception)\b|(Scanner|Parser|Composer|Constructor|Reader)Error/.test(pyErr))
    ok(false, 'ios-release.yml 이 YAML 로 안 읽힌다: ' + pyErr.split('\n').slice(-3).join(' '));
  else console.log('  · python3 · PyYAML 이 없어 YAML 읽기는 건너뜁니다');

  fs.rmSync(tmpRoot, { recursive: true, force: true });
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

  iosReleaseWorkflow();

  fs.rmSync(out, { recursive: true, force: true });
  console.log(`\n통과 ${pass} / 실패 ${fail}`);
  process.exit(fail ? 1 : 0);
})().catch(e => { console.error(e); process.exit(1); });
