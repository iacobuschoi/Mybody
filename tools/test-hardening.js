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
  const post = (path2, body) => fetch(`http://localhost:${PORT}/api${path2}`, {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify(body)
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
    const u = sapi.signUp({ handle: 'legacy', password: 'legacy-password-1', displayName: 'L' });
    const tok = u.token;
    if (sapi.userForToken(tok)) console.log('    ✓ 정상 토큰은 통과한다');
    else { console.log('    ✗ 정상 토큰이 막힌다'); lockFail++; }
    sdb.exec('UPDATE sessions SET expires_at = NULL');
    if (!sapi.userForToken(tok)) console.log('    ✓ expires_at 없는 토큰은 죽는다');
    else { console.log('    ✗ expires_at 없는 토큰이 살아 있다'); lockFail++; }
    // 다시 열면 마이그레이션이 채워 줍니다 (만든 날 + 90일)
    const u2 = sapi.signUp({ handle: 'legacy2', password: 'legacy-password-1', displayName: 'L2' });
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

  const bad = leak + lockFail;
  console.log(bad ? `\n실패 ${bad}건` : '\n통과');
  srv.kill();
  process.exit(bad?1:0);
})();
