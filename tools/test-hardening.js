/* =============================================================================
 * tools/test-hardening.js — 서버를 인터넷에 열었을 때
 *
 *   node tools/test-hardening.js
 *
 * 이 서버는 비전문가가 집 컴퓨터에서 띄워 터널로 여는 것을 전제로
 * 합니다. 그 말은 로그인 화면을 전 세계가 두드린다는 뜻입니다.
 * 여기서는 "적대적인 사람이 실제로 해 볼 법한 것"만 봅니다.
 *
 * 이 검사가 잡아낸 것들
 *   · 형제 디렉터리 유출 — STATIC 이 /srv/webroot 일 때 /srv/webroot-x
 *     가 그대로 열렸습니다. startsWith 에 구분자가 없었습니다.
 *
 * 검사 자신에 대한 규칙: 서버가 안 뜨면 "전부 막힘" 이 아니라 실패로
 * 셉니다. 처음에 서버 경로를 틀리게 적어서 아무것도 확인하지 못한 채
 * "유출 없음" 을 찍었습니다. 아무것도 안 한 검사가 통과를 말하면,
 * 그 검사는 없느니만 못합니다.
 * ========================================================================== */
'use strict';
/* 검사하는 사람의 ~/.mybody 설정이 결과를 바꾸지 않게 떼어 놓습니다. */
require('./testenv.js');
const { spawn } = require('child_process');
const fs = require('fs'); const os = require('os'); const path = require('path');
const base = fs.mkdtempSync(path.join(os.tmpdir(),'trav-'));
const root = path.join(base,'webroot');
fs.mkdirSync(root);
fs.writeFileSync(path.join(root,'index.html'),'PUBLIC');
fs.writeFileSync(path.join(base,'secret.txt'),'SECRET-TOKEN-12345');
fs.mkdirSync(path.join(base,'webroot-x'));
fs.writeFileSync(path.join(base,'webroot-x','z.txt'),'SIBLING-LEAK');
const PORT = 8820 + (process.pid % 100);
const srv = spawn(process.execPath,[path.join(__dirname,'..','server','server.js')],
  {env:{...process.env,PORT:String(PORT),DB:path.join(base,'t.db'),PAIR_SECRET:'x',STATIC:root,
   /* 속도 제한을 올려 둡니다. 안 올리면 아래 잠금 검사가 429 에 먼저
      막혀서, 정작 보려던 로직을 한 번도 안 지나갑니다. 429 자체는
      올바른 방어라 그건 그것대로 두고 여기서는 잠금만 봅니다. */
   RATE_MAX:'100000', AUTH_MAX:'100000', LOGIN_MAP_MAX:'20',
   BODY_TIMEOUT_MS:'3000'},stdio:'ignore'});
process.on('exit',()=>srv.kill());
(async()=>{
  let up=false;
  for(let i=0;i<60;i++){try{if((await fetch(`http://localhost:${PORT}/health`)).ok){up=true;break;}}catch{}await new Promise(r=>setTimeout(r,120));}
  if(!up){ console.error('서버가 안 떴습니다 — 이 검사는 아무것도 확인하지 못했습니다'); srv.kill(); process.exit(2); }
  const get = async u => {
    try { const r = await fetch(`http://localhost:${PORT}${u}`); return {s:r.status, t:(await r.text()).slice(0,40)}; }
    catch(e){ return {s:0,t:String(e.message).slice(0,40)}; }
  };
  console.log('  경로 탈출');
  const cases = [
    ['정상', '/'],
    ['%2e%2e%2f', '/%2e%2e%2fsecret.txt'],
    ['..%2f', '/..%2fsecret.txt'],
    ['%2e%2e/', '/%2e%2e/secret.txt'],
    ['이중 인코딩', '/%252e%252e%252fsecret.txt'],
    ['형제 디렉터리', '/%2e%2e%2fwebroot-x%2fz.txt'],
    ['백슬래시', '/..%5csecret.txt']
  ];
  let leak = 0;
  for (const [n,u] of cases) {
    const r = await get(u);
    const bad = /SECRET-TOKEN|SIBLING-LEAK/.test(r.t);
    if (bad) leak++;
    console.log(`  ${bad?'✗ 샜다':'✓ 막힘'}  ${n.padEnd(14)} ${r.s}  ${JSON.stringify(r.t)}`);
  }
  console.log(leak ? `\n  유출 ${leak}건` : '\n  유출 없음');

  /* --- 계정 잠금을 쓰레기로 풀 수 있나 ---------------------------------
   * 비밀번호를 8번 틀리면 15분 잠깁니다. 그런데 실패 기록을 담는 맵이
   * 5000을 넘으면 통째로 비워졌습니다 — 아무 아이디로 5000번을 흘리면
   * 진짜 계정의 잠금까지 같이 풀렸습니다. 잠금을 지우려고 쓰레기를
   * 밀어 넣는 것이 그대로 공격이 됩니다. */
  console.log('\n  계정 잠금');
  let lockFail = 0;
  /* 가입에는 건강정보 별도 동의가 필요합니다(개인정보보호법 제23조).
     검사도 실제 사용자와 같은 문을 지나야 의미가 있으므로, 가입 요청에만
     동의 판을 채워 보냅니다. */
  const post = (path2, body) => fetch(`http://localhost:${PORT}/api${path2}`, {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify(path2 === '/auth/signup'
      ? Object.assign({ healthConsent: '2026-09-20' }, body) : body)
  });
  await post('/auth/signup', { handle: 'victim', password: 'victim-password-1',
                               displayName: '피해자', pairSecret: 'x' });
  for (let i = 0; i < 9; i++) await post('/auth/signin', { handle: 'victim', password: 'wrong-' + i });
  // 잠기면 429 로 "몇 분 뒤에 다시" 라고 답합니다 (401 이 아닙니다)
  const locked = await post('/auth/signin', { handle: 'victim', password: 'victim-password-1' });
  if (locked.status === 429) console.log('    ✓ 8번 틀리면 잠긴다 (맞는 비밀번호도 막힘)');
  else { console.log('    ✗ 안 잠긴다', locked.status); lockFail++; }

  /* 쓰레기 아이디를 흘려서 잠금을 푸는 공격.
     실제 상한은 5000 이지만 여기서는 LOGIN_MAP_MAX=20 으로 줄여 둡니다.
     scrypt 를 5000번 돌리면 몇 분이 걸리고 — 그 사실 자체가 아래
     [속도] 검사가 보는 문제입니다 — 여기서 보려는 것은 "상한을 넘겼을
     때 잠금이 살아남는가" 뿐입니다. */
  for (let i = 0; i < 40; i++) {
    await post('/auth/signin', { handle: 'junk' + i, password: 'x'.repeat(9) });
  }
  const still = await post('/auth/signin', { handle: 'victim', password: 'victim-password-1' });
  if (still.status === 429) console.log('    ✓ 쓰레기로 상한을 넘겨도 잠금이 안 풀린다');
  else { console.log('    ✗ 쓰레기로 잠금이 풀렸다', still.status); lockFail++; }

  /* --- 인증 안 한 요청으로 서버를 묶을 수 있나 -------------------------
   * 비밀번호 확인은 scrypt 라 건당 약 46ms 를 쓰고, 노드는 스레드가
   * 하나입니다. 일반 제한(분당 300)으로는 300 × 46ms = 14초를 허용하는
   * 셈이라 모자랍니다. 로그인·가입에는 따로 더 빡빡한 제한을 둡니다. */
  console.log('\n  로그인 폭주');
  const sep = spawn(process.execPath, ['/home/user/Mybody/server/server.js'], {
    env: { ...process.env, PORT: String(PORT + 1), DB: path.join(base,'t2.db'),
           PAIR_SECRET: 'x', STATIC: root }, stdio: 'ignore'
  });
  let up2 = false;
  for (let i = 0; i < 60; i++) {
    try { if ((await fetch(`http://localhost:${PORT+1}/health`)).ok) { up2 = true; break; } } catch {}
    await new Promise(r => setTimeout(r, 120));
  }
  if (!up2) { console.log('    ✗ 두 번째 서버가 안 떴습니다'); lockFail++; }
  else {
    const t0 = Date.now();
    const codes = [];
    for (let i = 0; i < 40; i++) {
      const r = await fetch(`http://localhost:${PORT+1}/api/auth/signin`, {
        method: 'POST', headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ handle: 'nobody' + i, password: 'x'.repeat(9) })
      });
      codes.push(r.status);
    }
    const ms = Date.now() - t0;
    const blocked = codes.filter(c => c === 429).length;
    if (blocked >= 15) console.log(`    ✓ 40번 중 ${blocked}번이 scrypt 전에 잘렸다 (${ms}ms)`);
    else { console.log(`    ✗ 거의 다 통과했다 — ${blocked}번만 429 (${ms}ms)`); lockFail++; }
    if (ms < 5000) console.log(`    ✓ 40번이 ${ms}ms 에 끝났다 (제한이 없으면 수 초)`);
    else { console.log(`    ✗ ${ms}ms 나 걸렸다`); lockFail++; }
    sep.kill();
  }

  /* --- 만료 컬럼 이전에 발급된 토큰 -------------------------------------
   * userForToken 의 검사가 `s.expires_at && ...` 이라, 컬럼이 생기기 전에
   * 발급된 세션(expires_at = NULL)은 검사를 통째로 건너뛰고 영원히
   * 살았습니다. 하필 가장 오래된, 그래서 샜을 가능성이 제일 높은
   * 토큰들입니다. 만료를 붙인 이유가 정확히 그건데 그 대상만 빠졌습니다. */
  console.log('\n  옛 세션');
  {
    const { open, makeApi } = require(path.join(__dirname, '..', 'server', 'db.js'));
    const f = path.join(base, 'sess.db');
    const sdb = open(f);
    const sapi = makeApi(sdb);
    const u = sapi.signUp({ handle: 'legacy', password: 'legacy-password-1', displayName: 'L',
                              healthConsent: '2026-09-20' });
    const tok = u.token;
    if (sapi.userForToken(tok)) console.log('    ✓ 정상 토큰은 통과한다');
    else { console.log('    ✗ 정상 토큰이 막힌다'); lockFail++; }
    sdb.exec('UPDATE sessions SET expires_at = NULL');
    if (!sapi.userForToken(tok)) console.log('    ✓ expires_at 없는 토큰은 죽는다');
    else { console.log('    ✗ expires_at 없는 토큰이 살아 있다'); lockFail++; }
    // 다시 열면 마이그레이션이 채워 줍니다 (만든 날 + 90일)
    const u2 = sapi.signUp({ handle: 'legacy2', password: 'legacy-password-1', displayName: 'L2',
                               healthConsent: '2026-09-20' });
    sdb.exec('UPDATE sessions SET expires_at = NULL');
    const sdb2 = open(f);
    const sapi2 = makeApi(sdb2);
    if (sapi2.userForToken(u2.token)) console.log('    ✓ 다시 열면 만료일이 채워져 살아난다');
    else { console.log('    ✗ 마이그레이션이 만료일을 안 채운다'); lockFail++; }
  }

  /* --- 본문을 보내다 마는 연결 -------------------------------------------
   * 연결만 열어 두고 본문을 끝내지 않으면, 예전에는 그 요청이 최대 2MB 를
   * 붙든 채 영원히 남았습니다. 인증도 필요 없어서 그런 연결을 수백 개
   * 열면 메모리가 그만큼 묶입니다. */
  console.log('\n  느린 본문');
  {
    const net = require('net');
    const t0 = Date.now();
    const closed = await new Promise(resolve => {
      const sock = net.connect(PORT, 'localhost', () => {
        // Content-Length 는 100 이라고 해 놓고 10바이트만 보냅니다
        sock.write('POST /api/auth/signin HTTP/1.1\r\nHost: x\r\n' +
                   'Content-Type: application/json\r\nContent-Length: 100\r\n\r\n');
        sock.write('{"handle":');
      });
      let got = '';
      sock.on('data', d => { got += d.toString(); });
      sock.on('close', () => resolve({ ms: Date.now() - t0, got: got.slice(0, 40) }));
      sock.on('error', () => resolve({ ms: Date.now() - t0, got: 'error' }));
      setTimeout(() => { sock.destroy(); resolve({ ms: Date.now() - t0, got: 'timeout' }); }, 12000);
    });
    if (closed.ms < 11000) console.log(`    ✓ ${Math.round(closed.ms/1000)}초 만에 서버가 끊는다`);
    else { console.log('    ✗ 서버가 안 끊는다 — 연결이 계속 살아 있다'); lockFail++; }
  }

  /* --- 이상한 타입을 보내면 400 인가 500 인가 ---------------------------
   * 500 은 "서버가 예상 못 한 일이 일어났다" 는 뜻이고, 스택이 로그에
   * 쌓이고 때로는 내부 구조가 응답에 섞입니다. 클라이언트가 잘못 보낸
   * 것은 400 이어야 합니다. 어느 쪽인지는 짐작하지 말고 실제로 두드려
   * 봅니다. */
  console.log('\n  이상한 입력');
  {
    const me2 = await post('/auth/signup', { handle: 'fuzz', password: 'fuzz-password-1',
                                             displayName: 'F', pairSecret: 'x' });
    const tok2 = me2.json ? null : null;
    const t2 = (await (await fetch(`http://localhost:${PORT}/api/auth/signin`, {
      method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ handle: 'fuzz', password: 'fuzz-password-1' })
    })).json()).token;

    const WEIRD = [ {}, [], 123, true, null, '', '[object Object]',
                    { __proto__: { polluted: 1 } }, { toString: 1 }, 'x'.repeat(5000) ];
    const shots = [];
    for (const w of WEIRD) {
      shots.push(['POST', '/snapshots', { weekStart: w, payload: { a: 1 } }]);
      shots.push(['POST', '/snapshots', { weekStart: '2026-09-14', payload: w }]);
      shots.push(['POST', '/friends/request', { inviteCode: w }]);
      shots.push(['POST', '/friends/accept', { userId: w }]);
      shots.push(['PATCH', '/me', { displayName: w }]);
      shots.push(['POST', '/sync/push', { records: w }]);
      shots.push(['POST', '/sync/push', { records: [{ kind: w, id: w, updatedAt: w, payload: w }] }]);
    }
    let fives = [];
    for (const [m, path2, body] of shots) {
      const r = await fetch(`http://localhost:${PORT}/api${path2}`, {
        method: m, headers: { 'content-type': 'application/json',
                              authorization: 'Bearer ' + t2 },
        body: JSON.stringify(body)
      });
      if (r.status >= 500) fives.push(m + ' ' + path2 + ' ' + JSON.stringify(body).slice(0, 60) + ' → ' + r.status);
    }
    if (!fives.length) console.log(`    ✓ ${shots.length}가지 이상한 입력에 500 이 없다`);
    else {
      console.log(`    ✗ 500 이 ${fives.length}건`);
      fives.slice(0, 6).forEach(f => console.log('        ' + f));
      lockFail++;
    }
    // 프로토타입 오염이 실제로 일어났는지
    const polluted = await fetch(`http://localhost:${PORT}/api/me`,
      { headers: { authorization: 'Bearer ' + t2 } }).then(r => r.json()).catch(() => ({}));
    if (!('polluted' in (polluted.user || {}))) console.log('    ✓ 프로토타입 오염 흔적 없음');
    else { console.log('    ✗ 프로토타입이 오염됐다'); lockFail++; }
  }

  /* --- 복구 코드 -------------------------------------------------------
   * 비밀번호를 잊은 사람이 돌아오는 유일한 길입니다. 이 서버는 메일을
   * 보내지 않으니 다른 길이 없습니다. 그래서 여기가 뚫리면 계정을
   * 가져가는 문이 하나 더 열리는 것과 같습니다.
   *
   * 보는 것
   *   · 틀린 코드로는 못 지나간다
   *   · 맞는 코드는 사람이 옮겨 적은 모양(소문자·공백)으로도 통한다
   *   · 쓴 코드는 두 번 안 통한다 — 메모장에 남아 있어도 무용지물
   *   · 되찾으면 다른 기기의 세션이 끊긴다
   *   · 찍어 보는 시도는 아이디별로 잠긴다 (로그인과 같은 잠금)
   *   · 로그인한 채 코드를 새로 받으려면 비밀번호를 다시 대야 한다
   */
  console.log('\n  복구 코드');
  {
    const json = r => r.json().catch(() => ({}));
    const up = await json(await post('/auth/signup',
      { handle: 'rec', password: 'rec-password-1', displayName: 'R', pairSecret: 'x' }));

    if (/^[A-HJ-NP-Z2-9]{4}(-[A-HJ-NP-Z2-9]{4}){3}$/.test(up.recoveryCode || ''))
      console.log('    ✓ 가입할 때 코드가 나온다 (헷갈리는 글자 없음)');
    else { console.log('    ✗ 코드 모양이 이상하다: ' + JSON.stringify(up.recoveryCode)); lockFail++; }

    const oldToken = up.token;

    // 틀린 코드
    const wrong = await post('/auth/recover',
      { handle: 'rec', code: 'AAAA-BBBB-CCCC-DDDD', password: 'new-password-1' });
    if (wrong.status === 400) console.log('    ✓ 틀린 코드는 거부한다');
    else { console.log('    ✗ 틀린 코드가 통했다 ' + wrong.status); lockFail++; }

    // 없는 아이디도 같은 말로 거부해야 합니다 (계정이 있는지 알려주지 않기)
    const ghost = await json(await post('/auth/recover',
      { handle: 'no-such-person', code: 'AAAA-BBBB-CCCC-DDDD', password: 'new-password-1' }));
    const wrongBody = await json(wrong.clone ? wrong.clone() : wrong);
    if (ghost.reason && wrongBody.reason && ghost.reason === wrongBody.reason)
      console.log('    ✓ 없는 아이디와 틀린 코드를 같은 말로 거부한다');
    else { console.log('    ✗ 말이 다르다 — 계정 존재 여부가 샌다'); lockFail++; }

    // 맞는 코드 — 사람이 옮겨 적은 모양으로
    const typed = String(up.recoveryCode).toLowerCase().replace(/-/g, ' ');
    const okRes = await post('/auth/recover',
      { handle: 'rec', code: typed, password: 'new-password-1' });
    const ok = await json(okRes);
    if (okRes.status === 200 && ok.token) console.log('    ✓ 소문자·공백으로 적어도 통한다');
    else { console.log('    ✗ 맞는 코드가 막혔다 ' + okRes.status); lockFail++; }

    if (ok.recoveryCode && ok.recoveryCode !== up.recoveryCode)
      console.log('    ✓ 쓰고 나면 새 코드를 준다');
    else { console.log('    ✗ 새 코드를 안 준다'); lockFail++; }

    // 옛 세션이 죽었나
    const oldStill = await fetch(`http://localhost:${PORT}/api/me`,
      { headers: { authorization: 'Bearer ' + oldToken } });
    if (oldStill.status === 401) console.log('    ✓ 되찾으면 다른 기기가 끊긴다');
    else { console.log('    ✗ 옛 토큰이 살아 있다 ' + oldStill.status); lockFail++; }

    // 쓴 코드 재사용
    const reuse = await post('/auth/recover',
      { handle: 'rec', code: up.recoveryCode, password: 'other-password-1' });
    if (reuse.status === 400) console.log('    ✓ 쓴 코드는 두 번 안 통한다');
    else { console.log('    ✗ 쓴 코드가 또 통했다 ' + reuse.status); lockFail++; }

    // 새 비밀번호로 로그인
    const back = await post('/auth/signin', { handle: 'rec', password: 'new-password-1' });
    if (back.status === 200) console.log('    ✓ 새 비밀번호로 들어가진다');
    else { console.log('    ✗ 새 비밀번호로 못 들어간다 ' + back.status); lockFail++; }

    // 찍어 보는 시도는 잠긴다 (아이디별 잠금이 recover 에도 걸리는가)
    await post('/auth/signup', { handle: 'guessme', password: 'guess-password-1',
                                 displayName: 'G', pairSecret: 'x' });
    let hit429 = 0;
    for (let i = 0; i < 12; i++) {
      const r = await post('/auth/recover',
        { handle: 'guessme', code: 'ZZZZ-ZZZZ-ZZZZ-ZZZ' + 'ABCDEFGHJKMN'[i], password: 'x-password-1' });
      if (r.status === 429) hit429++;
    }
    if (hit429 > 0) console.log(`    ✓ 찍어 보면 잠긴다 (12번 중 ${hit429}번 429)`);
    else { console.log('    ✗ 아무리 찍어도 안 잠긴다'); lockFail++; }

    // 로그인한 채 코드 새로 받기 — 비밀번호를 다시 대야 합니다
    const sess = await json(await post('/auth/signin',
      { handle: 'rec', password: 'new-password-1' }));
    const reissue = (body) => fetch(`http://localhost:${PORT}/api/auth/recovery-code`, {
      method: 'POST',
      headers: { 'content-type': 'application/json', authorization: 'Bearer ' + sess.token },
      body: JSON.stringify(body)
    });
    const noPw = await reissue({});
    if (noPw.status === 400) console.log('    ✓ 비밀번호 없이는 새 코드를 못 받는다');
    else { console.log('    ✗ 비밀번호 없이 코드가 나왔다 ' + noPw.status); lockFail++; }
    const withPw = await json(await reissue({ password: 'new-password-1' }));
    if (withPw.ok && withPw.recoveryCode) console.log('    ✓ 비밀번호를 대면 새 코드가 나온다');
    else { console.log('    ✗ 맞는 비밀번호로도 못 받는다'); lockFail++; }

    // 토큰 없이는 아예 못 부릅니다
    const noAuth = await post('/auth/recovery-code', { password: 'new-password-1' });
    if (noAuth.status === 401) console.log('    ✓ 로그인 안 하면 못 부른다');
    else { console.log('    ✗ 로그인 없이 통했다 ' + noAuth.status); lockFail++; }

    /* 로그인 잠금과 복구 잠금이 섞이면 안 됩니다.
     *
     * 예전엔 칸이 하나였습니다. 비밀번호를 여덟 번 틀린 사람은 복구
     * 코드를 한 번도 못 넣어 보고 막혔습니다 — 비밀번호가 기억 안 나서
     * 복구하러 온 사람이 정확히 그 상태인데, 유일한 출구가 들어오는
     * 길에 잠겨 있었습니다. */
    await post('/auth/signup', { handle: 'locked', password: 'locked-password-1',
                                 displayName: 'L', pairSecret: 'x' });
    const lockedCode = (await json(await post('/auth/signup',
      { handle: 'locked2', password: 'locked-password-1', displayName: 'L2', pairSecret: 'x' }))).recoveryCode;
    for (let i = 0; i < 9; i++) await post('/auth/signin', { handle: 'locked2', password: 'no-' + i });
    const stillLocked = await post('/auth/signin', { handle: 'locked2', password: 'locked-password-1' });
    if (stillLocked.status === 429) console.log('    ✓ 비밀번호를 틀리면 로그인은 잠긴다');
    else { console.log('    ✗ 로그인이 안 잠긴다 ' + stillLocked.status); lockFail++; }
    const rescue = await post('/auth/recover',
      { handle: 'locked2', code: lockedCode, password: 'rescued-password-1' });
    if (rescue.status === 200) console.log('    ✓ 로그인이 잠겨도 복구는 된다');
    else { console.log('    ✗ 복구까지 같이 잠겼다 ' + rescue.status); lockFail++; }
    const afterRescue = await post('/auth/signin', { handle: 'locked2', password: 'rescued-password-1' });
    if (afterRescue.status === 200) console.log('    ✓ 되찾으면 로그인 잠금도 풀린다');
    else { console.log('    ✗ 되찾았는데도 로그인이 막혀 있다 ' + afterRescue.status); lockFail++; }

    // 이상한 타입으로 500 이 나는가
    let recFive = 0;
    for (const w of [{}, [], 123, true, null, { toString: 1 }, 'x'.repeat(5000)]) {
      const r = await post('/auth/recover', { handle: w, code: w, password: w });
      if (r.status >= 500) recFive++;
      const r2 = await reissue({ password: w });
      if (r2.status >= 500) recFive++;
    }
    if (!recFive) console.log('    ✓ 이상한 입력에 500 이 없다');
    else { console.log(`    ✗ 500 이 ${recFive}건`); lockFail++; }
  }

  const bad = leak + lockFail;
  console.log(bad ? `\n실패 ${bad}건` : '\n통과');
  srv.kill();
  process.exit(bad?1:0);
})();
