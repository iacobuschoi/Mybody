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

async function freePort() {
  return new Promise(res => {
    const s = net.createServer();
    s.listen(0, '127.0.0.1', () => { const p = s.address().port; s.close(() => res(p)); });
  });
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
    ok('확인한 포트를 그 명령에 싣는다', new RegExp('PORT=' + port).test(r.stdout || ''),
       (r.stdout || '').slice(-300));
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

  console.log(`\n통과 ${pass} / 실패 ${fail}`);
  fs.rmSync(HOME, { recursive: true, force: true });
  process.exit(fail ? 1 : 0);
})().catch(e => { console.error(e); process.exit(1); });
