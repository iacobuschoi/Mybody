/* =============================================================================
 * tools/test-selfhost.js — "내 컴퓨터에서 띄우기" 가 실제로 되는가
 *
 *   node tools/test-selfhost.js
 *
 * 왜 이 검사가 있나
 *   나머지 검사들은 전부 "앱이 맞게 도는가" 를 봅니다. 그런데 사용자가
 *   제일 먼저 만나는 벽은 앱이 아니라 그 앞입니다 — 노드가 낡았거나,
 *   포트가 차 있거나, 빌드를 안 했거나, 윈도우에서 환경변수 문법이
 *   다르거나. 거기서 막히면 앱이 아무리 멀쩡해도 못 씁니다.
 *
 *   그래서 doctor · serve 를 실제로 돌려 보고, 진짜로 서버가 떠서
 *   배포 빌드를 내보내는지까지 확인합니다.
 *
 * 이 검사가 잡아낸 것
 *   · STATIC 을 빼먹으면 개발 빌드(번호 배지가 전부 뜨는)가 그대로
 *     나가는데 서버가 아무 말도 안 했습니다.
 *   · 포트가 차 있으면 노드 스택 추적이 쏟아졌습니다.
 *   · --setup 을 터미널이 아닌 데서 돌리면 질문을 던지다 죽으면서
 *     설정 파일도 안 남겼습니다.
 * ========================================================================== */
'use strict';
const fs = require('node:fs');
const os = require('node:os');
const net = require('node:net');
const path = require('node:path');
const { spawn, spawnSync } = require('node:child_process');

const ROOT = path.join(__dirname, '..');
let pass = 0, fail = 0;
const ok = (n, c, d) => {
  if (c) { pass++; console.log('  ✓', n); }
  else { fail++; console.log('  ✗', n, d === undefined ? '' : String(d).slice(0, 300)); }
};

/* 집(HOME)을 임시 폴더로 옮겨서 돕니다 — 진짜 설정을 건드리면 안 됩니다. */
const HOME = fs.mkdtempSync(path.join(os.tmpdir(), 'mb-home-'));
const DB = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'mb-db-')), 'test.db');
const baseEnv = () => Object.assign({}, process.env, {
  HOME: HOME, USERPROFILE: HOME, DB: DB, NODE_NO_WARNINGS: '1'
});

function run(args, env, input) {
  return spawnSync(process.execPath, args.map(a => a.startsWith('-') ? a : path.join(ROOT, a)),
    { cwd: ROOT, env: env || baseEnv(), encoding: 'utf8', input: input, timeout: 120000 });
}

/* 빈 포트 고르기.
 *
 * 0 번으로 bind 해서 커널이 준 번호를 받고 닫는 고전적인 방법인데,
 * **닫은 순간부터 서버가 다시 bind 할 때까지 사이가 비어 있습니다.**
 * 그 사이에 다른 프로세스가 같은 번호를 집어가면 서버가 EADDRINUSE 로
 * 죽고, 시험은 "서버를 못 띄웠다" 고 보고합니다 — 제품은 멀쩡한데요.
 *
 * 실제로 배포 전 점검에서 그렇게 터졌습니다. 20분짜리 인터랙션 전수가
 * 막 끝나 포트가 어지럽던 때였고, 혼자 돌리면 93/93 인데 그때만 91/93
 * 이었습니다. 원인을 모른 채 "가끔 그러네" 로 넘기면, 진짜 고장도
 * 같은 말로 넘어가게 됩니다.
 *
 * 그래서 두 가지를 합니다.
 *   (가) 최근에 내준 번호는 다시 안 내줍니다 (한 실행 안에서).
 *   (나) 서버를 띄우는 쪽에서 EADDRINUSE 면 새 번호로 다시 시도합니다
 *        (아래 tryPorts).
 */
const usedPorts = new Set();
async function freePort() {
  for (let i = 0; i < 40; i++) {
    const p = await new Promise(res => {
      const s = net.createServer();
      s.listen(0, '127.0.0.1', () => { const n = s.address().port; s.close(() => res(n)); });
    });
    if (!usedPorts.has(p)) { usedPorts.add(p); return p; }
  }
  throw new Error('빈 포트를 못 찾았습니다');
}

/** 포트를 집어가는 경쟁에 한 번 더 기회를 줍니다. fn(port) 가 참 같은 값을
 *  돌려주면 성공으로 봅니다. EADDRINUSE 로 실패하면 새 포트로 다시. */
async function tryPorts(fn, attempts = 3) {
  let last = null;
  for (let i = 0; i < attempts; i++) {
    const port = await freePort();
    const r = await fn(port);
    if (r && r.ok !== false) return r;
    last = r;
    if (!(r && r.addrInUse)) return r;      // 다른 이유로 실패한 것은 그대로 돌려줍니다
  }
  return last;
}
const wait = ms => new Promise(r => setTimeout(r, ms));

(async () => {
  console.log('\n[1] doctor — 준비가 안 됐으면 못 띄운다고 말한다');
  {
    const r = run(['tools/doctor.js']);
    ok('설정이 없으면 0 이 아닌 값으로 끝난다', r.status !== 0, 'status=' + r.status);
    ok('가입 코드가 없다고 말한다', /가입 코드/.test(r.stdout || ''), r.stdout);
    ok('무엇을 하면 되는지도 적는다', /serve\.js --setup/.test(r.stdout || ''),
       (r.stdout || '').slice(0, 400));
    ok('노드 버전을 실제로 시험해서 말한다',
       /노드 버전[\s\S]*?데이터베이스까지 잘 됩니다/.test(r.stdout || ''), r.stdout);
  }

  console.log('\n[1-2] 오래된 Node 로 띄우면 사람 말로 끝난다');
  {
    /* 이 서버는 Node 내장 SQLite 를 씁니다. 옛 Node 에는 없어서 예전에는
       첫 줄부터 ERR_UNKNOWN_BUILTIN_MODULE 스택이 쏟아졌습니다. 개발자가
       아니면 그게 "Node 를 새로 깔아라" 라는 뜻인 줄 모릅니다.
       이 컴퓨터에 옛 Node 가 있으면 실제로 그걸로 띄워 봅니다. */
    const olds = ['/opt/node20/bin/node', '/opt/node21/bin/node']
      .filter(p2 => { try { return fs.statSync(p2).isFile(); } catch (e) { return false; } });
    if (!olds.length) {
      console.log('  · 이 컴퓨터에 옛 Node 가 없어 건너뜁니다');
    } else {
      for (const old of olds) {
        const v = spawnSync(old, ['--version'], { encoding: 'utf8' }).stdout.trim();
        const r = spawnSync(old, [path.join(ROOT, 'server', 'server.js')],
          { cwd: ROOT, encoding: 'utf8', env: Object.assign(baseEnv(), { PAIR_SECRET: 'x' }) });
        const out = (r.stderr || '') + (r.stdout || '');
        ok(v + ' — 스택 추적이 아니라 할 일을 알려준다',
           !/at Module\._load|internal\/modules/.test(out) && /nodejs\.org/.test(out),
           out.slice(0, 200));
        ok(v + ' — doctor 도 같은 이유로 막는다',
           /node:sqlite|못 띄웁니다/.test(
             spawnSync(old, [path.join(ROOT, 'tools', 'doctor.js')],
               { cwd: ROOT, encoding: 'utf8', env: baseEnv() }).stdout || ''));
      }
    }
  }

  console.log('\n[2] serve --setup — 터미널이 아니어도 설정이 남는다');
  {
    const r = run(['tools/serve.js', '--setup', '--owner=검사 주인', '--contact=t@example.com']);
    ok('끝난다 (질문을 던지다 죽지 않는다)', r.status === 0, (r.stderr || r.stdout || '').slice(0, 200));
    const file = path.join(HOME, '.mybody', 'config.json');
    ok('설정 파일이 생긴다', fs.existsSync(file), file);
    const cfg = JSON.parse(fs.readFileSync(file, 'utf8'));
    ok('가입 코드를 만들어 준다', (cfg.pairSecret || '').length >= 32, cfg.pairSecret && cfg.pairSecret.length);
    ok('운영자를 적어 둔다', cfg.owner === '검사 주인' && cfg.ownerContact === 't@example.com', cfg);
    if (process.platform !== 'win32') {
      const mode = fs.statSync(file).mode & 0o777;
      ok('남이 못 읽게 해 둔다 (600)', mode === 0o600, mode.toString(8));
    }
    ok('가입 코드를 화면에 한 번 보여준다', /가입 코드를 새로 만들었습니다/.test(r.stdout || ''), r.stdout);
    ok('--show 가 비밀을 통째로 안 찍는다',
       !(run(['tools/serve.js', '--show']).stdout || '').includes(cfg.pairSecret));
  }

  console.log('\n[3] doctor — 준비가 되면 띄울 수 있다고 말한다');
  {
    const port = await freePort();
    const r = run(['tools/doctor.js'], Object.assign(baseEnv(), { PORT: String(port) }));
    ok('0 으로 끝난다', r.status === 0, (r.stdout || '').slice(-400));
    ok('"띄울 수 있습니다" 라고 말한다', /띄울 수 있습니다/.test(r.stdout || ''));
    ok('칠 명령을 그대로 준다', /node tools\/serve\.js/.test(r.stdout || ''), (r.stdout||'').slice(-300));
    /* 없는 파일을 읽는 명령을 알려주면 안 됩니다. ~/.mybody-pair 는
       이제 아무 도구도 안 만드는데, 예전 doctor 는 그걸 cat 하라고
       했습니다 — 그대로 치면 빈 값이 들어가 서버가 안 뜹니다. */
    ok('아무도 안 만드는 파일을 읽으라고 안 한다',
       !/\.mybody-pair/.test(r.stdout || ''), (r.stdout || '').slice(-300));
    /* 폰에서 칠 주소를 아무도 안 알려줘서, 폰으로 쓰려는 사람은 자기
       컴퓨터의 내부 주소를 따로 찾아내야 했습니다. 어디서 찾는지
       모르면 거기서 끝입니다. */
    const anyLan = Object.values(os.networkInterfaces()).flat()
      .some(n => n && n.family === 'IPv4' && !n.internal);
    if (anyLan) {
      ok('폰에서 칠 주소를 알려준다', /폰에서는  http:\/\/\d+\.\d+\.\d+\.\d+:/.test(r.stdout || ''),
         (r.stdout || '').slice(-400));
      ok('그 주소로는 뭐가 안 되는지도 말한다', /앱 설치/.test(r.stdout || ''));
    }
  }

  console.log('\n[3-2] 서버가 폰 주소와 올바른 형식을 내보낸다');
  {
    const port = await freePort();
    const srv = spawn(process.execPath, [path.join(ROOT, 'server', 'server.js')],
      { cwd: ROOT, env: Object.assign(baseEnv(), {
          PORT: String(port), PAIR_SECRET: 'x', STATIC: path.join(ROOT, 'release') }) });
    let out = '';
    srv.stdout.on('data', d => { out += d; });
    srv.stderr.on('data', d => { out += d; });
    let up = false;
    for (let i = 0; i < 60; i++) {
      try { if ((await fetch(`http://127.0.0.1:${port}/health`)).ok) { up = true; break; } } catch (e) {}
      await wait(200);
    }
    ok('뜬다', up, out.slice(-200));
    if (up) {
      const anyLan = Object.values(os.networkInterfaces()).flat()
        .some(n => n && n.family === 'IPv4' && !n.internal);
      if (anyLan) {
        ok('시작할 때 폰에서 칠 주소를 찍는다',
           /폰에서 http:\/\/\d+\.\d+\.\d+\.\d+:/.test(out), out.slice(0, 400));
      }
      /* 매니페스트를 알 수 없는 형식으로 내보내면 브라우저가 "폰에 설치"
         를 안 띄울 수 있습니다. 검사 도구들은 자기 정적 서버에서 올바른
         형식으로 내보내서 이 차이를 못 잡았습니다 — 진짜 서버에 묻습니다. */
      const ct = p2 => fetch(`http://127.0.0.1:${port}/${p2}`).then(r => r.headers.get('content-type') || '');
      ok('매니페스트 형식이 맞다', /application\/manifest\+json/.test(await ct('manifest.webmanifest')),
         await ct('manifest.webmanifest'));
      ok('아이콘 형식이 맞다', /image\/png/.test(await ct('assets/icon-192.png')));
      ok('방침 형식이 맞다', /text\/html/.test(await ct('privacy.html')));
    }
    srv.kill();
    await wait(300);
  }

  console.log('\n[3-3] 데이터베이스 파일이 깨져 있으면 doctor 가 잡는다');
  {
    /* 메모리에서만 열어 보면 "노드는 되는데 내 파일이 깨진" 경우를
       놓칩니다 — 전부 ✓ 를 준 뒤 서버가 영문 스택으로 죽습니다. */
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'mb-bad-'));
    const bad = path.join(dir, 'broken.db');
    fs.writeFileSync(bad, 'this is not a database');
    const r = run(['tools/doctor.js'], Object.assign(baseEnv(), { DB: bad }));
    ok('깨진 파일을 잡는다', r.status !== 0 && /데이터베이스 파일을 못 엽니다/.test(r.stdout || ''),
       (r.stdout || '').slice(0, 400));
    fs.rmSync(dir, { recursive: true, force: true });
  }

  console.log('\n[4] 포트가 차 있으면 사람이 읽을 수 있게 말한다');
  {
    const port = await freePort();
    const blocker = net.createServer(() => {});
    await new Promise(r => blocker.listen(port, '0.0.0.0', r));

    const d = run(['tools/doctor.js'], Object.assign(baseEnv(), { PORT: String(port) }));
    ok('doctor 가 막는다', d.status !== 0);
    ok('포트를 바꾸는 법을 알려준다', /PORT=\d+/.test(d.stdout || ''), d.stdout);

    const s = spawnSync(process.execPath, [path.join(ROOT, 'server', 'server.js')],
      { cwd: ROOT, encoding: 'utf8',
        env: Object.assign(baseEnv(), { PORT: String(port), PAIR_SECRET: 'x' }) });
    const out = (s.stderr || '') + (s.stdout || '');
    ok('서버도 스택 추적을 안 쏟는다', !/at Server\.|node:net:/.test(out), out.slice(0, 200));
    ok('무엇을 하면 되는지 적는다', /포트를 바꿔서|이미 떠 있을 수도/.test(out), out.slice(0, 300));
    await new Promise(r => blocker.close(r));
  }

  console.log('\n[5] STATIC 을 빼먹으면 개발 빌드가 나가는데, 그렇다고 말한다');
  {
    const port = await freePort();
    const s = spawn(process.execPath, [path.join(ROOT, 'server', 'server.js')],
      { cwd: ROOT, env: Object.assign(baseEnv(), { PORT: String(port), PAIR_SECRET: 'x' }) });
    let out = '';
    s.stdout.on('data', d => { out += d; });
    s.stderr.on('data', d => { out += d; });
    await wait(1800);
    ok('개발 빌드라고 경고한다', /개발 빌드입니다/.test(out), out.slice(0, 300));
    ok('배포 빌드로 바꾸는 명령을 준다', /build-release\.js/.test(out), out.slice(0, 400));
    const body = await fetch('http://127.0.0.1:' + port + '/').then(r => r.text()).catch(() => '');
    ok('실제로 개발 빌드가 나간다 (경고가 맞는 말이다)', /uid\.css/.test(body));
    s.kill();
    await wait(300);
  }

  console.log('\n[5-2] 없는 폴더를 가리키면 "실행 중" 이라고만 하지 않는다');
  {
    /* STATIC 을 상대경로로 주고 다른 폴더에서 띄우면 cwd 기준으로 풀려서
       엉뚱한 데를 가리킵니다. 예전엔 그래도 "실행 중" 이라고만 했고,
       브라우저에는 빈 404 만 나왔습니다 — 무엇이 잘못됐는지 알 길이
       없습니다. */
    const port = await freePort();
    const elsewhere = fs.mkdtempSync(path.join(os.tmpdir(), 'mb-cwd-'));
    const s2 = spawn(process.execPath, [path.join(ROOT, 'server', 'server.js')],
      { cwd: elsewhere, env: Object.assign(baseEnv(), {
          PORT: String(port), PAIR_SECRET: 'x', STATIC: './release' }) });
    let out2 = '';
    s2.stdout.on('data', d => { out2 += d; });
    s2.stderr.on('data', d => { out2 += d; });
    await wait(1800);
    ok('앱이 없다고 말한다', /여기에 앱이 없습니다|index\.html 이 없습니다/.test(out2), out2.slice(0, 400));
    ok('상대경로가 어디 기준인지 알려준다', out2.includes(elsewhere), out2.slice(0, 400));
    ok('어떻게 띄우면 되는지 알려준다', /tools\/serve\.js/.test(out2));
    const code = await fetch('http://127.0.0.1:' + port + '/').then(r => r.status).catch(() => 0);
    ok('실제로 404 가 맞다 (경고가 참이다)', code === 404, code);
    s2.kill();
    await wait(300);
    fs.rmSync(elsewhere, { recursive: true, force: true });
  }


  console.log('\n[6] serve — 한 줄로 띄우면 배포 빌드가 나간다');
  {
    const port = await freePort();
    const cfgFile = path.join(HOME, '.mybody', 'config.json');
    const cfg = JSON.parse(fs.readFileSync(cfgFile, 'utf8'));
    cfg.port = port; cfg.db = DB;
    fs.writeFileSync(cfgFile, JSON.stringify(cfg));

    fs.rmSync(path.join(ROOT, 'release'), { recursive: true, force: true });
    const child = spawn(process.execPath, [path.join(ROOT, 'tools', 'serve.js')],
      { cwd: ROOT, env: baseEnv() });
    let out = '';
    child.stdout.on('data', d => { out += d; });
    child.stderr.on('data', d => { out += d; });

    let up = false;
    for (let i = 0; i < 80; i++) {
      try { if ((await fetch('http://127.0.0.1:' + port + '/health')).ok) { up = true; break; } } catch (e) {}
      await wait(250);
    }
    ok('서버가 뜬다', up, out.slice(-400));
    ok('빌드가 없으면 알아서 만든다', /배포 빌드를 새로 만듭니다/.test(out), out.slice(0, 200));

    if (up) {
      const body = await fetch('http://127.0.0.1:' + port + '/').then(r => r.text()).catch(() => '');
      ok('배포 빌드가 나간다 (번호 배지 없음)', !/uid\.css/.test(body) && /MB_APP/.test(body));
      ok('방침이 열린다', (await fetch('http://127.0.0.1:' + port + '/privacy.html')).status === 200);
      const pv = await fetch('http://127.0.0.1:' + port + '/privacy.html').then(r => r.text());
      ok('방침에 설정한 운영자가 박힌다', pv.includes('검사 주인'), pv.slice(0, 200));
      ok('experimental 경고를 안 찍는다', !/ExperimentalWarning/.test(out), out.slice(0, 200));

      /* 설정한 가입 코드로 실제 가입이 되는가 — 설정과 서버가 이어져 있는지 */
      const r = await fetch('http://127.0.0.1:' + port + '/api/auth/signup', {
        method: 'POST', headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ handle: 'selfhost', password: 'selfhost-password-1',
                               displayName: '자가호스팅', pairSecret: cfg.pairSecret,
                               healthConsent: '2026-09-20' })
      }).then(x => x.json()).catch(e => ({ err: String(e) }));
      ok('설정의 가입 코드로 계정이 만들어진다', !!r.token, r);
      const bad = await fetch('http://127.0.0.1:' + port + '/api/auth/signup', {
        method: 'POST', headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ handle: 'nope', password: 'selfhost-password-1',
                               displayName: 'x', pairSecret: 'wrong',
                               healthConsent: '2026-09-20' })
      });
      ok('틀린 코드로는 안 된다', bad.status === 401 || bad.status === 400, bad.status);
    }
    child.kill();
    await wait(400);
  }

  console.log('\n[7] 같은 와이파이에서 http 로 열면 — 무엇이 안 되는지 말한다');
  {
    /* 제일 먼저 시도할 길입니다: 노트북에서 띄우고 폰에서 192.168.x.x 로 들어오기.
       그런데 브라우저는 http 를 "안전하지 않은 출처" 로 보고 세 가지를 막습니다 —
       앱 설치(서비스워커) · 오프라인 · 버튼 복사. 앱 자체는 멀쩡히 돌아서,
       사용자는 "왜 설치가 안 뜨지" 를 혼자 한참 찾습니다. */
    let ip = null;
    for (const list of Object.values(os.networkInterfaces())) {
      for (const n of list || []) {
        if (n.family === 'IPv4' && !n.internal) { ip = n.address; break; }
      }
      if (ip) break;
    }
    if (!ip) {
      console.log('  · 이 기계에 바깥 IP 가 없어 건너뜁니다');
    } else {
      let chromium = null;
      try {
        chromium = require(process.env.NODE_PATH
          ? path.join(process.env.NODE_PATH, 'playwright') : 'playwright').chromium;
      } catch (e) {}
      if (!chromium) {
        console.log('  · playwright 가 없어 건너뜁니다 (NODE_PATH 를 주면 돕니다)');
      } else {
        const port = await freePort();
        const srv = spawn(process.execPath, [path.join(ROOT, 'server', 'server.js')],
          { cwd: ROOT, env: Object.assign(baseEnv(), {
              PORT: String(port), PAIR_SECRET: 'x', STATIC: path.join(ROOT, 'release') }) });
        let up = false;
        for (let i = 0; i < 60; i++) {
          try { if ((await fetch(`http://${ip}:${port}/health`)).ok) { up = true; break; } } catch (e) {}
          await wait(200);
        }
        ok('바깥 IP 로도 열린다', up, ip + ':' + port);
        if (up) {
          const b = await chromium.launch({ executablePath:
            process.env.CHROME_PATH || '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
          const read = async base => {
            const ctx = await b.newContext({ viewport: { width: 390, height: 844 } });
            const pg = await ctx.newPage();
            await pg.goto(base + '/', { waitUntil: 'load' });
            await wait(1500);
            const r = await pg.evaluate(async () => {
              window.MB_APP.go('P12');
              await new Promise(x => setTimeout(x, 450));
              const w = document.querySelector('[data-uid="P12-S02"]');
              return { secure: window.isSecureContext, app: !!window.MB_APP,
                       clipboard: !!(navigator.clipboard && navigator.clipboard.writeText),
                       notice: w ? w.innerText : null };
            });
            await ctx.close();
            return r;
          };
          const lan = await read(`http://${ip}:${port}`);
          const local = await read(`http://localhost:${port}`);

          ok('http 는 안전하지 않은 출처로 잡힌다', lan.secure === false, lan);
          ok('그래도 앱은 그대로 돈다', lan.app === true, lan);
          ok('복사가 막히는 것을 실제로 확인', lan.clipboard === false, lan);
          ok('무엇이 왜 안 되는지 화면이 말한다',
             !!lan.notice && /앱처럼 깔기/.test(lan.notice), lan.notice);
          ok('https(localhost)에서는 그 안내가 안 뜬다', local.notice === null, local);
          await b.close();
        }
        srv.kill();
        await wait(300);
      }
    }
  }

  /* --------------------------------------------------------------------
   * [8] 백업이 실제로 데이터를 담는가
   *
   * 이 데이터베이스는 WAL 방식입니다. 서버가 켜져 있는 동안 새 기록은
   * 곁파일에 쌓이고 본파일은 거의 안 자랍니다. 계정을 하나 만든 직후
   * mybody.db 는 4KB 이고, 그걸 복사하면 users 테이블조차 없습니다.
   * 백업한 줄 알았는데 아무것도 없는 상태가 제일 나쁩니다.
   * ------------------------------------------------------------------ */
  console.log('\n[7-2] 설정을 바꾸면 다시 빌드한다');
  {
    /* 운영자 이름은 빌드할 때 방침에 박힙니다. 이름만 바꾸면 prototype/ 은
       안 건드려지니, 파일 시각만 보는 판정으로는 "빌드는 최신" 이 됩니다 —
       방침에는 남의 이름이 그대로 남습니다. */
    const cfgFile = path.join(HOME, '.mybody', 'config.json');
    const cfg = JSON.parse(fs.readFileSync(cfgFile, 'utf8'));
    cfg.owner = '바뀐 이름';
    cfg.port = await freePort();
    fs.writeFileSync(cfgFile, JSON.stringify(cfg));

    const child = spawn(process.execPath, [path.join(ROOT, 'tools', 'serve.js')],
      { cwd: ROOT, env: baseEnv() });
    let out = '';
    child.stdout.on('data', d => { out += d; });
    child.stderr.on('data', d => { out += d; });
    let up = false;
    for (let i = 0; i < 80; i++) {
      try { if ((await fetch('http://127.0.0.1:' + cfg.port + '/health')).ok) { up = true; break; } } catch (e) {}
      await wait(250);
    }
    ok('서버가 뜬다', up, out.slice(-300));
    if (up) {
      const pv = await fetch('http://127.0.0.1:' + cfg.port + '/privacy.html').then(r => r.text());
      ok('바뀐 이름이 방침에 박힌다', pv.includes('바뀐 이름'), pv.slice(0, 200));
      ok('옛 이름이 안 남는다', !pv.includes('검사 주인'));
    }
    child.kill();
    await wait(400);
  }

  console.log('\n[8] 서버가 켜진 채로 뜬 백업에 데이터가 들어 있다');
  {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'mb-bk-'));
    const db = path.join(dir, 'mybody.db');
    const out = path.join(dir, 'backups');
    const port = await freePort();
    const env = Object.assign(baseEnv(), {
      PORT: String(port), PAIR_SECRET: 'bk-secret', DB: db,
      STATIC: path.join(ROOT, 'release')
    });
    const srv = spawn(process.execPath, [path.join(ROOT, 'server', 'server.js')],
      { cwd: ROOT, env: env, stdio: 'ignore' });
    let up = false;
    for (let i = 0; i < 60; i++) {
      try { if ((await fetch(`http://127.0.0.1:${port}/health`)).ok) { up = true; break; } } catch (e) {}
      await wait(200);
    }
    ok('검사용 서버가 뜬다', up);

    if (up) {
      for (const h of ['bka', 'bkb']) {
        await fetch(`http://127.0.0.1:${port}/api/auth/signup`, {
          method: 'POST', headers: { 'content-type': 'application/json' },
          body: JSON.stringify({ handle: h, password: 'backup-password-1', displayName: h,
                                 pairSecret: 'bk-secret', healthConsent: '2026-09-20' })
        }).catch(() => {});
      }

      /* 정말로 본파일이 비어 있는지 먼저 확인합니다 — 이 검사가 지키려는
         상황이 실재하는지부터 봐야 합니다. 안 그러면 언젠가 WAL 이 아니게
         바뀌어도 이 검사는 계속 통과합니다. */
      const { DatabaseSync } = require('node:sqlite');
      let rawCopyRows = null;
      const raw = path.join(dir, 'naive-copy.db');
      fs.copyFileSync(db, raw);
      try {
        const d = new DatabaseSync(raw, { readOnly: true });
        rawCopyRows = d.prepare('SELECT COUNT(*) c FROM users').get().c;
        d.close();
      } catch (e) { rawCopyRows = 'no-table'; }
      ok('그냥 복사하면 쓸모없다 (이 검사가 지킬 값이 있다)',
         rawCopyRows === 'no-table' || rawCopyRows === 0, rawCopyRows);

      const b = run(['tools/backup.js', '--out=' + out], Object.assign(env, { DB: db }));
      ok('백업이 끝난다', b.status === 0, (b.stderr || b.stdout || '').slice(0, 200));
      ok('몇 명이 들어갔는지 말해 준다', /계정 2명/.test(b.stdout || ''), b.stdout);

      const made = fs.existsSync(out) ? fs.readdirSync(out).filter(f => f.endsWith('.db')) : [];
      ok('백업 파일이 생긴다', made.length === 1, made);
      if (made.length) {
        const d = new DatabaseSync(path.join(out, made[0]), { readOnly: true });
        ok('백업본에 계정이 들어 있다', d.prepare('SELECT COUNT(*) c FROM users').get().c === 2);
        d.close();
      }

      /* 켜져 있을 때 되돌리려 하면 막아야 합니다 — 켠 채로 바꾸면
         서버가 옛 데이터로 도로 덮어씁니다. */
      const bad = run(['tools/backup.js', '--restore=' + path.join(out, made[0] || 'x.db')],
        Object.assign(env, { DB: db }));
      ok('켜져 있으면 되돌리기를 막는다',
         bad.status !== 0 && /아직 켜져 있습니다/.test((bad.stderr || '') + (bad.stdout || '')),
         (bad.stderr || bad.stdout || '').slice(0, 160));
    }

    /* 제대로 끄면 곁파일이 본파일에 합쳐져야 합니다 */
    srv.kill('SIGTERM');
    await wait(1500);
    ok('끄면 곁파일이 사라진다 (파일 하나로 온전해진다)',
       !fs.existsSync(db + '-wal'), fs.readdirSync(dir));

    if (up) {
      const { DatabaseSync } = require('node:sqlite');
      const after = path.join(dir, 'after-close.db');
      fs.copyFileSync(db, after);
      let n = null;
      try { const d = new DatabaseSync(after, { readOnly: true });
            n = d.prepare('SELECT COUNT(*) c FROM users').get().c; d.close(); } catch (e) { n = 'ERR'; }
      ok('끈 뒤에는 그냥 복사해도 온전하다', n === 2, n);

      /* 되돌리기 — 서버가 꺼진 지금은 돼야 합니다 */
      const made2 = fs.readdirSync(out).filter(f => f.endsWith('.db'));
      const d0 = new DatabaseSync(db);
      d0.exec('DELETE FROM users');
      d0.close();
      const r = run(['tools/backup.js', '--restore=' + path.join(out, made2[0])],
        Object.assign(env, { DB: db }));
      await wait(400);
      ok('꺼져 있으면 되돌려진다', /되돌렸습니다/.test(r.stdout || ''), (r.stdout || r.stderr || '').slice(0, 200));
      const d2 = new DatabaseSync(db, { readOnly: true });
      ok('되돌린 뒤 계정이 살아난다', d2.prepare('SELECT COUNT(*) c FROM users').get().c === 2);
      d2.close();
      ok('옛 파일을 옆에 치워 둔다',
         fs.readdirSync(dir).some(f => /\.before-/.test(f)), fs.readdirSync(dir));
    }
    fs.rmSync(dir, { recursive: true, force: true });
  }

  console.log('\n[8-2] 로그 — 볼 것은 있고, 남으면 안 되는 것은 없다');
  {
    /* 로그가 기동 배너뿐이라 친구가 "안 돼요" 할 때 주인이 볼 게 없었습니다.
       그렇다고 몸에 대한 숫자를 로그에 남기면 지워야 할 곳이 하나 더 생깁니다 —
       그런 로그는 보통 백업도 안 되고 보관 기간도 없습니다. */
    const port = await freePort();
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'mb-log-'));
    const srv = spawn(process.execPath, [path.join(ROOT, 'server', 'server.js')],
      { cwd: ROOT, env: Object.assign(baseEnv(), {
          PORT: String(port), PAIR_SECRET: 'log-secret', DB: path.join(dir, 'l.db'),
          STATIC: path.join(ROOT, 'release') }) });
    let out = '';
    srv.stdout.on('data', d => { out += d; });
    srv.stderr.on('data', d => { out += d; });
    let up = false;
    for (let i = 0; i < 60; i++) {
      try { if ((await fetch(`http://127.0.0.1:${port}/health`)).ok) { up = true; break; } } catch (e) {}
      await wait(200);
    }
    if (!up) { ok('로그 검사용 서버가 뜬다', false, out.slice(-200)); }
    else {
      const post = (p2, b) => fetch(`http://127.0.0.1:${port}/api${p2}`, {
        method: 'POST', headers: { 'content-type': 'application/json' },
        body: JSON.stringify(b) }).then(r => r.json().catch(() => ({})));
      const me = await post('/auth/signup', { handle: 'loguser', password: 'log-password-1',
        displayName: '로그', pairSecret: 'log-secret', healthConsent: '2026-09-20' });
      await post('/auth/signin', { handle: 'loguser', password: 'nope' });
      await fetch(`http://127.0.0.1:${port}/api/snapshots`, {
        method: 'POST',
        headers: { 'content-type': 'application/json', authorization: 'Bearer ' + me.token },
        body: JSON.stringify({ weekStart: '2026-09-14',
                               payload: { weightKg: 86.7, smmKg: 37.9, bfmKg: 20.0 } })
      }).catch(() => {});
      await fetch(`http://127.0.0.1:${port}/`).catch(() => {});
      await wait(500);

      ok('요청이 한 줄씩 남는다', /POST {2}\/api\/auth\/signup/.test(out), out.slice(-400));
      ok('실패도 상태로 보인다', /401 {2}POST {2}\/api\/auth\/signin/.test(out), out.slice(-400));
      ok('정적 파일은 안 센다 (묻히지 않게)', !/GET {4}\/index\.html|200 {2}GET {4}\/ /.test(out), out.slice(-400));
      ok('상태 확인(/health)은 안 센다', !/\/health/.test(out.split('\n').filter(l => /^\d\d:\d\d/.test(l)).join('\n')));

      /* 여기서부터가 진짜 중요한 것 */
      ok('몸에 대한 숫자가 안 남는다', !/86\.7|37\.9|20\.0/.test(out), out.slice(-500));
      ok('토큰이 안 남는다', !(me.token && out.includes(me.token)));
      ok('복구 코드가 안 남는다', !(me.recoveryCode && out.includes(me.recoveryCode)));
      ok('비밀번호가 안 남는다', !/log-password-1/.test(out));
      ok('가입 코드가 안 남는다', !/log-secret/.test(out));
      ok('끄는 법을 알려준다', /LOG=0/.test(out));
    }
    srv.kill();
    await wait(300);
    fs.rmSync(dir, { recursive: true, force: true });
  }

  console.log('\n[8-3] 한글·공백이 든 경로에서도 돈다');
  {
    /* 윈도우면 C:\Users\아무개\내 문서\... 가 흔하고, 맥에서도 한글
       폴더를 씁니다. 경로에 공백이 있으면 따옴표를 빠뜨린 자리가
       바로 깨집니다. */
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'mb-한글 공백-'));
    const db = path.join(dir, '내 데이터', 'mybody.db');
    const out = path.join(dir, '백업 폴더');
    fs.mkdirSync(path.dirname(db), { recursive: true });

    const d = run(['tools/doctor.js'], Object.assign(baseEnv(), { DB: db }));
    ok('doctor 가 돈다', /띄울 수 있습니다|못 띄웁니다/.test(d.stdout || ''), (d.stdout || '').slice(-200));

    /* 백업도 — 먼저 서버를 한 번 띄워 DB 를 만듭니다 */
    const port = await freePort();
    const srv = spawn(process.execPath, [path.join(ROOT, 'server', 'server.js')],
      { cwd: ROOT, stdio: 'ignore', env: Object.assign(baseEnv(), {
          PORT: String(port), PAIR_SECRET: 'x', DB: db, STATIC: path.join(ROOT, 'release') }) });
    let up = false;
    for (let i = 0; i < 60; i++) {
      try { if ((await fetch(`http://127.0.0.1:${port}/health`)).ok) { up = true; break; } } catch (e) {}
      await wait(200);
    }
    ok('서버가 한글 경로의 DB 로 뜬다', up, db);
    srv.kill();
    await wait(800);

    const b = run(['tools/backup.js', '--out=' + out], Object.assign(baseEnv(), { DB: db }));
    ok('백업이 한글·공백 경로에 떨어진다',
       b.status === 0 && fs.existsSync(out) && fs.readdirSync(out).some(f => f.endsWith('.db')),
       (b.stdout || b.stderr || '').slice(0, 200));
    fs.rmSync(dir, { recursive: true, force: true });
  }

  console.log('\n[8-4] git 저장소가 아니어도 조용히 빌드된다');
  {
    /* ZIP 으로 받으면 .git 이 없습니다. 예전엔 git 이 자기 오류를
       터미널에 그대로 찍어서 — fatal: not a git repository — 빌드는
       멀쩡히 되는데 화면에 fatal 이 두 줄 떴습니다. 쓰는 사람은
       뭔가 망가진 줄 압니다. */
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'mb-nogit-'));
    for (const f of ['prototype', 'tools', 'server']) {
      fs.cpSync(path.join(ROOT, f), path.join(dir, f), { recursive: true });
    }
    const r = spawnSync(process.execPath, [path.join(dir, 'tools', 'build-release.js')],
      { cwd: dir, encoding: 'utf8',
        env: Object.assign(baseEnv(), { OWNER: '주인', OWNER_CONTACT: 'a@b' }), timeout: 120000 });
    const all = (r.stdout || '') + (r.stderr || '');
    ok('빌드가 된다', r.status === 0, all.slice(-300));
    ok('git 오류가 안 샌다', !/fatal:/.test(all), all.slice(0, 200));
    ok('버전이 내용을 따라간다', /nogit-[0-9a-f]{8}/.test(r.stdout || ''), (r.stdout || '').slice(0, 120));
    fs.rmSync(dir, { recursive: true, force: true });
  }

  console.log('\n[9] 자동 시작 · 더블클릭 실행');
  {
    /* 자동 시작은 평소 쓰는 PATH 도 HOME 도 안 물려받습니다. 손으로 적은
       설정이 "node: command not found" 로 죽는 자리라, 도구가 지금 돌고
       있는 노드의 실제 경로를 박아야 합니다. */
    const r = run(['tools/autostart.js']);
    ok('내 OS 에 맞는 설정을 보여준다', r.status === 0 && (r.stdout || '').length > 200,
       (r.stdout || r.stderr || '').slice(0, 200));
    ok('node 의 전체 경로를 박는다', (r.stdout || '').includes(process.execPath), process.execPath);
    ok('serve.js 의 전체 경로를 박는다',
       (r.stdout || '').includes(path.join(ROOT, 'tools', 'serve.js')));
    ok('거는 법까지 알려준다', /거는 법|작업 스케줄러/.test(r.stdout || ''));

    /* --write 가 진짜로 파일을 만드는가 — 임시 HOME 안에서 */
    const w = run(['tools/autostart.js', '--write']);
    ok('--write 가 파일을 만든다', /만들었습니다/.test(w.stdout || ''), (w.stdout || w.stderr || '').slice(0, 200));
    const made = (w.stdout || '').match(/만들었습니다: (.+)/);
    if (made) ok('그 파일이 실제로 있다', fs.existsSync(made[1].trim()), made[1]);

    /* 더블클릭 실행기 */
    ok('start.command 가 있고 실행 권한이 있다', (() => {
      try {
        const st = fs.statSync(path.join(ROOT, 'start.command'));
        return process.platform === 'win32' ? true : !!(st.mode & 0o111);
      } catch (e) { return false; }
    })());
    ok('start.cmd 가 있다', fs.existsSync(path.join(ROOT, 'start.cmd')));
    const sh = fs.readFileSync(path.join(ROOT, 'start.command'), 'utf8');
    ok('Node 가 없을 때 무엇을 하라고 말한다', /nodejs\.org/.test(sh));
    ok('창이 바로 안 닫힌다 (오류를 읽을 수 있다)', /read -r/.test(sh));
  }

  console.log(`\n통과 ${pass} / 실패 ${fail}`);
  fs.rmSync(HOME, { recursive: true, force: true });
  process.exit(fail ? 1 : 0);
})().catch(e => { console.error(e); process.exit(1); });
