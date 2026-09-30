/* =============================================================================
 * tools/test-launch-wait.js — 사람이 없을 때도 공개 주소가 돌아오는가
 *
 *   node tools/test-launch-wait.js
 *
 * 왜 이 검사가 있나 (노트북 보고 48, 2026-09-30)
 *   서버 컴퓨터는 주인의 윈도우 노트북이고, 작업 스케줄러가 로그온 30초
 *   뒤 창 없이 launch.js 를 띄웁니다. 그날 충전기가 빠져 절전 → 비정상
 *   종료 → 부팅. launch.js 가 떴을 때 Tailscale 은 아직 덜 떠 있었고,
 *   launch.js 는 funnel 을 건너뛰었습니다. 서버는 멀쩡히 200 을 내는데
 *   공개 주소(https://….ts.net)는 사람이 작업을 다시 띄울 때까지 죽어
 *   있었습니다. 화면이 없으니 아무도 몰랐습니다.
 *
 *   그래서 launch.js 가 스스로 하게 됐습니다.
 *     · ts.net 주소로 쓰는 컴퓨터는 Tailscale 이 늦어도 Cloudflare 로
 *       넘어가지 않고, 서버를 먼저 띄운 채 기다렸다가 funnel 을 엽니다.
 *       --cloudflare 로 한 번 띄운 뒤에도 그 "묶임" 은 안 풀립니다.
 *     · Tailscale 이 "로그인 필요 · 꺼짐" 이면 기기 이름이 남아 있어도
 *       준비됐다고 보지 않습니다(진짜 `status --json` 은 그때도 0 으로 끝납니다).
 *     · funnel 이 도중에 죽으면 간격을 늘려 가며 다시 붙이고, 붙으면 중계를
 *       한 번 다시 잡습니다(debug rebind · restun).
 *     · 로그는 안 쌓입니다 — 기다리는 줄 · 끊김 줄 · 다시 붙음 줄 모두 한도가 있습니다.
 *     · 그래도 Ctrl+C · 작업 끝내기에는 남김없이 꺼지고, 걸어 둔 타이머가 안 울립니다.
 *   이것들은 부팅 직후 · 절전 뒤에만 일어나서 손으로는 거의 못 봅니다.
 *   가짜 tailscale · cloudflared 로 그 순간을 만들어 봅니다.
 *
 * 시간을 줄이는 법
 *   launch.js 의 기다림은 분 단위입니다. MYBODY_TS_POLL_MS ·
 *   MYBODY_TS_BACKOFF_MS 로 줄여서 돌립니다 — 나머지 간격은 이 두 값의
 *   배수라 모양은 그대로입니다. 주소 확인(verifyUrl)은 가짜 도메인이라
 *   어차피 안 열리므로 MYBODY_VERIFY_TRIES=0 으로 바로 끝냅니다.
 *   그리고 절들을 세 개씩 **동시에** 돌립니다(LW_JOBS 로 바꿉니다). 첫 절만
 *   혼자 돕니다 — 배포 빌드가 낡았으면 serve.js 가 다시 만드는데, 여럿이
 *   한꺼번에 만들면 서로 밟습니다. 출력은 절마다 모아 두었다가 순서대로 찍습니다.
 *
 * 실패해도 뒤에 남기지 않습니다
 *   launch.js 는 자기 프로세스 묶음(detached)으로 띄우고, 끝날 때 · 중간에
 *   던질 때 · Ctrl+C 에 그 묶음째 끕니다. 안 그러면 실패한 실행마다 서버가
 *   포트를 쥔 채 남고, 그 아래 기록 폴더는 지워집니다.
 *
 * 윈도우에서는 가짜 실행 파일(셸 스크립트)을 못 만들어 건너뜁니다
 * (test-selfhost.js [8-6] 과 같습니다).
 * ========================================================================== */
'use strict';
const fs = require('node:fs');
const os = require('node:os');
const net = require('node:net');
const path = require('node:path');
const { spawn, spawnSync } = require('node:child_process');

const ROOT = path.join(__dirname, '..');
const LAUNCH = path.join(ROOT, 'tools', 'launch.js');
const NAME = 'mypc.tail9f2c.ts.net';
const TS_URL = 'https://' + NAME;
/* 기기 이름이 바뀐 경우(다시 깔기 · 이름 바꾸기로 "-1" 이 붙음) */
const NAME2 = 'mypc-1.tail9f2c.ts.net';
const TS_URL2 = 'https://' + NAME2;
/* 주소가 **상자 안에** 찍혔는가. 주소 글자만 찾으면 "이 컴퓨터 주소는 …" 같은
   안내 줄에도 걸려서, funnel 이 안 떴는데도 통과합니다 (처음에 그랬습니다). */
const boxUrl = name => new RegExp('│\\s+주소\\s+https://' + name.replace(/\./g, '\\.'));
const BOX_URL = boxUrl(NAME);
const JOBS = Math.max(1, Number(process.env.LW_JOBS) || 3);

const wait = ms => new Promise(r => setTimeout(r, ms));

if (process.platform === 'win32') {
  console.log('  · 윈도우에서는 가짜 실행파일을 못 만들어 건너뜁니다');
  process.exit(0);
}

/* --- 뒤처리 ------------------------------------------------------------------
 * 띄운 것 · 만든 폴더를 전부 여기 적어 두고, 어떻게 끝나든(통과 · 실패 ·
 * 던짐 · Ctrl+C) 묶음째 끄고 지웁니다.
 * -------------------------------------------------------------------------- */
const RUNS = new Set();
const WORLDS = new Set();
function killGroup(run) {
  try { process.kill(-run.child.pid, 'SIGKILL'); } catch (e) {}
}
function cleanup(w) {
  (w.runs || []).forEach(killGroup);
  try { fs.rmSync(w.dir, { recursive: true, force: true }); } catch (e) {}
  WORLDS.delete(w);
}
process.on('exit', () => {
  RUNS.forEach(killGroup);
  WORLDS.forEach(w => { try { fs.rmSync(w.dir, { recursive: true, force: true }); } catch (e) {} });
});
['SIGINT', 'SIGTERM'].forEach(s => process.on(s, () => process.exit(130)));

/* 빈 포트 — test-selfhost.js 와 같은 방식 (한 실행 안에서 같은 번호를 두 번 안 줍니다). */
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

async function healthy(port) {
  try {
    const r = await fetch('http://127.0.0.1:' + port + '/health');
    return r.ok;
  } catch (e) { return false; }
}

/** pred 가 참이 될 때까지 (최대 ms). 참이 됐으면 true. */
async function until(pred, ms, step) {
  const end = Date.now() + ms;
  while (Date.now() < end) {
    if (await pred()) return true;
    await wait(step || 150);
  }
  return !!(await pred());
}

const count = (s, re) => (s.match(re) || []).length;
const lines = f => { try { return fs.readFileSync(f, 'utf8').split('\n').filter(Boolean); } catch (e) { return []; } };
const alive = pid => { try { process.kill(pid, 0); return true; } catch (e) { return false; } };

/** 이 세계의 폴더 경로가 인자에 든 프로세스 — 끈 뒤에 남은 것이 있는지 봅니다. */
function leftovers(dir) {
  const r = spawnSync('ps', ['-eo', 'pid=,args='], { encoding: 'utf8' });
  if (r.status !== 0) return null;         // ps 가 없으면 모릅니다
  return (r.stdout || '').split('\n').filter(l => l.includes(dir) && !l.includes('ps -eo'));
}

/* --- 가짜 세계 ---------------------------------------------------------------
 * 한 절마다 따로 만듭니다: 가짜 실행 파일 폴더 · 임시 HOME(설정) · 기록 폴더.
 * 가짜 tailscale 은 불릴 때마다 기록 폴더에 적어서, 시험이 "몇 번 불렸나 ·
 * 무엇이 아직 살아 있나" 를 셀 수 있게 합니다.
 *
 * `status` 는 진짜 `tailscale status --json` 처럼 답합니다: tailscaled 가 떠
 * 있으면 **로그아웃이어도 0 으로 끝나고** BackendState 로 말합니다. 1 로
 * 끝나는 것은 tailscaled 에 아예 못 붙을 때(부팅 직후)뿐입니다.
 * -------------------------------------------------------------------------- */
const json = (state, name) => `echo '{"BackendState":"${state}","Self":{"DNSName":"${name}."}}'; exit 0`;
const NOT_RUNNING = `>&2 echo "failed to connect to local tailscaled; it doesn't appear to be running"; exit 1`;
const STATUS = {
  ready: json('Running', NAME),
  renamed: json('Running', NAME2),
  /* 부팅 직후의 Tailscale — 표지 파일이 생기기 전까지는 tailscaled 에 못 붙습니다 */
  marker: `if [ -f "$ST/ready" ]; then ${json('Running', NAME)}; fi\n  ${NOT_RUNNING}`,
  down: NOT_RUNNING,
  /* 대답이 느리기까지 한 경우 — 끌 때 묻는 중인 자식도 같이 꺼지는지 봅니다 */
  slow: `sleep 1; ${NOT_RUNNING}`,
  /* 키가 만료됐거나 로그아웃 — 옛 네트워크 지도가 남아 기기 이름은 그대로 있습니다 */
  needsLogin: json('NeedsLogin', NAME)
};
const FUNNEL = {
  stay: url => `echo "Available on the internet:"; echo "${url}/"; echo "|-- proxy http://127.0.0.1"; exec sleep 60`,
  /* 첫 번째만 주소를 낸 뒤 2초 만에 죽고, 두 번째부터는 버팁니다 (절전에서 깨어난 뒤처럼) */
  onceDies: `n=$(wc -l < "$ST/funnel-pids")\n` +
            `  echo "Available on the internet:"; echo "${TS_URL}/"\n` +
            `  if [ "$n" -le 1 ]; then sleep 2; >&2 echo "tailscaled went away (fake)"; exit 1; fi\n` +
            `  exec sleep 60`,
  /* 늘 곧바로 죽습니다 — 다시 붙이기가 촘촘히 돌지 않는지 봅니다 */
  alwaysDies: `>&2 echo "Funnel is not enabled on your tailnet."; ` +
              `>&2 echo "To enable: https://login.tailscale.com/f/funnel?node=abc"; exit 1`,
  /* 주소는 내고 0.3초 만에 죽기를 되풀이합니다 — 2분(여기선 2.4초)을 못 버티니
     간격은 끝(1.2초)에 붙어 있고, 붙을 때마다 "다시 붙음" 이 나올 자리가 생깁니다. */
  flaps: `echo "Available on the internet:"; echo "${TS_URL}/"; sleep 0.3; ` +
         `>&2 echo "tailscaled went away (fake)"; exit 1`,
  /* 곧바로 두 번 죽고 → 세 번째는 3초 버티다 죽고 → 네 번째부터 버팁니다.
     2.4초(= 24 × 0.1초) 넘게 버틴 뒤의 끊김은 새 사고라 간격이 처음부터여야 합니다. */
  resetCheck: `n=$(wc -l < "$ST/funnel-pids")\n` +
              `  if [ "$n" -le 2 ]; then >&2 echo "tailscaled went away (fake)"; exit 1; fi\n` +
              `  echo "Available on the internet:"; echo "${TS_URL}/"\n` +
              `  if [ "$n" -eq 3 ]; then sleep 3; >&2 echo "tailscaled went away (fake)"; exit 1; fi\n` +
              `  exec sleep 60`
};

function tailscaleScript(st, status, funnel) {
  return '#!/bin/sh\n' +
    `ST='${st}'\n` +
    'if [ "$1" = "status" ]; then\n' +
    '  echo x >> "$ST/status-calls"\n' +
    '  ' + status + '\n' +
    'fi\n' +
    /* debug-hangs 가 있으면 대답 없이 붙들고 있습니다 — 끌 때 같이 꺼지는지 봅니다 */
    'if [ "$1" = "debug" ]; then echo "$2" >> "$ST/debug-calls"\n' +
    '  if [ -f "$ST/debug-hangs" ]; then echo $$ >> "$ST/debug-pids"; exec sleep 60; fi; exit 0; fi\n' +
    'if [ "$1" = "funnel" ] && [ "$2" = "status" ]; then echo "(fake) funnel status"; exit 0; fi\n' +
    'if [ "$1" = "funnel" ]; then\n' +
    '  echo $$ >> "$ST/funnel-pids"\n' +
    '  ' + funnel + '\n' +
    'fi\n' +
    'exit 0\n';
}

async function world(tag, opts) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'mb-lw-' + tag + '-'));
  const bin = path.join(dir, 'bin');
  const home = path.join(dir, 'home');
  const st = path.join(dir, 'st');
  [bin, st, path.join(home, '.mybody')].forEach(d => fs.mkdirSync(d, { recursive: true }));
  const w = { dir, bin, home, st, runs: [], port: await freePort() };
  WORLDS.add(w);
  w.writeTailscale = (status, funnel) => {
    fs.writeFileSync(path.join(bin, 'tailscale'), tailscaleScript(st, status, funnel));
    fs.chmodSync(path.join(bin, 'tailscale'), 0o755);
  };
  if (opts.status) w.writeTailscale(opts.status, opts.funnel || FUNNEL.stay(TS_URL));
  /* cloudflared 는 늘 둡니다 — "있어도 안 쓰는가" 가 이 시험이 보려는 것입니다. */
  const cfUrl = opts.cfUrl || 'https://should-not-be-used.trycloudflare.com';
  fs.writeFileSync(path.join(bin, 'cloudflared'),
    '#!/bin/sh\n' + `echo x >> '${st}/cf-used'\n` +
    'sleep 1\n>&2 echo "INF |  ' + cfUrl + '  |"\nexec sleep 60\n');
  fs.chmodSync(path.join(bin, 'cloudflared'), 0o755);
  const cfgFile = path.join(home, '.mybody', 'config.json');
  const cfg = {
    port: w.port, static: 'release', pairSecret: 'lw-test-secret',
    owner: '', ownerContact: '', ownerOmitted: true, openSignup: true, alwaysOn: true,
    vapidPublic: 'x', vapidPrivate: 'y', origin: opts.origin || '', trustProxy: !!opts.origin, db: ''
  };
  if (opts.tailscaleOrigin) cfg.tailscaleOrigin = opts.tailscaleOrigin;
  fs.writeFileSync(cfgFile, JSON.stringify(cfg), { mode: 0o600 });
  w.config = () => JSON.parse(fs.readFileSync(cfgFile, 'utf8'));
  w.mtime = () => fs.statSync(cfgFile).mtimeMs;
  w.funnelPids = () => lines(path.join(st, 'funnel-pids')).map(Number);
  w.statusCalls = () => lines(path.join(st, 'status-calls')).length;
  w.debugCalls = () => lines(path.join(st, 'debug-calls'));
  w.debugPids = () => lines(path.join(st, 'debug-pids')).map(Number);
  w.cfUsed = () => lines(path.join(st, 'cf-used')).length;
  return w;
}

/** launch.js 를 이 세계에서 띄웁니다. out() 으로 지금까지의 출력, exited 로 끝.
 *  자기 프로세스 묶음으로 띄웁니다 — 끝에 serve.js · server.js · 가짜 funnel 까지
 *  묶음째 끌 수 있게. SIGTERM 은 launch.js 에만 갑니다(그게 시험하려는 것입니다). */
function launch(w, args, envExtra) {
  const env = Object.assign({}, process.env, {
    HOME: w.home, USERPROFILE: w.home, DB: path.join(w.dir, 'test.db'), NODE_NO_WARNINGS: '1',
    PATH: w.bin + path.delimiter + (process.env.PATH || ''),
    MYBODY_TS_POLL_MS: '250', MYBODY_TS_BACKOFF_MS: '300',
    MYBODY_VERIFY_TRIES: '0', MYBODY_VERIFY_GAP: '200'
  }, envExtra || {});
  const child = spawn(process.execPath, [LAUNCH].concat(args || []),
    { cwd: ROOT, env, stdio: ['ignore', 'pipe', 'pipe'], detached: true });
  let buf = '';
  child.stdout.on('data', d => { buf += d; });
  child.stderr.on('data', d => { buf += d; });
  const exited = new Promise(res => child.on('exit', (code, sig) => res({ code, sig, at: Date.now() })));
  const run = { child, out: () => buf, exited };
  w.runs.push(run);
  RUNS.add(run);
  exited.then(() => RUNS.delete(run));
  return run;
}

/** SIGTERM 을 보내고 얼마 만에 끝나는지 (ms). 5초 안에 안 끝나면 묶음째 SIGKILL 하고 -1. */
async function stop(run) {
  const t0 = Date.now();
  run.child.kill('SIGTERM');
  const r = await Promise.race([run.exited, wait(5000).then(() => null)]);
  if (!r) { killGroup(run); return -1; }
  return r.at - t0;
}

/* --- 절 ----------------------------------------------------------------------
 * 절마다 ok 줄을 모아 두었다가 순서대로 찍습니다(동시에 돌아서).
 * 절 안에서 던지면 그 절만 실패로 적고, 만든 세계는 절이 끝날 때 치웁니다.
 * -------------------------------------------------------------------------- */
const BLOCKS = [];
const block = (title, fn) => BLOCKS.push({ title, fn });

block('[1] ts.net 주소로 쓰는 컴퓨터 — Tailscale 이 늦어도 서버부터 띄우고 기다린다', async t => {
  const w = await t.world('slow', { origin: TS_URL, status: STATUS.marker });
  const mtime0 = w.mtime();
  const run = launch(w);
  const up = await until(() => healthy(w.port), 30000, 200);
  t.ok('Tailscale 이 준비되기 전에 서버가 먼저 뜬다 (/health 200)', up, run.out().slice(-800));
  t.ok('기다린다고 한 번 말한다', count(run.out(), /Tailscale 준비를 기다립니다/g) === 1, run.out().slice(0, 800));
  t.ok('왜 기다리는지 적는다 (tailscale 이 한 말)', /doesn't appear to be running/.test(run.out()),
       run.out().slice(0, 800));
  t.ok('Cloudflare 로 안 넘어간다고 말한다', /Cloudflare 로는 넘어가지 않습니다/.test(run.out()),
       run.out().slice(0, 800));
  /* 몇 번 묻는 것까지 보고 나서 Tailscale 을 "켭니다" */
  const polled = await until(() => w.statusCalls() >= 3, 5000);
  t.ok('기다리는 동안 다시 묻는다', polled, 'status 호출 ' + w.statusCalls());
  t.ok('기다리는 동안은 funnel 을 안 띄운다', w.funnelPids().length === 0, w.funnelPids());
  /* 기다리는 **동안** 설정을 건드리지 않았는가. funnel 이 열린 뒤에만 보면, 그 사이
     origin 을 비우거나 trycloudflare 로 덮었다가 열릴 때 다시 ts.net 으로 덮은 것을
     못 잡습니다 — 이 사고가 바로 그 모양입니다. */
  t.ok('기다리는 동안 설정의 주소가 그대로다', w.config().origin === TS_URL, w.config().origin);
  t.ok('기다리는 동안 설정 파일을 다시 쓰지 않는다', w.mtime() === mtime0, mtime0 + ' → ' + w.mtime());
  fs.writeFileSync(path.join(w.st, 'ready'), '1');
  const opened = await until(() => BOX_URL.test(run.out()), 8000);
  t.ok('준비되면 funnel 을 연다', w.funnelPids().length === 1, w.funnelPids());
  t.ok('안 바뀌는 주소를 찍는다', opened, run.out().slice(-800));
  t.ok('준비됐다고 말한다', /Tailscale 준비됨/.test(run.out()), run.out().slice(-800));
  t.ok('친구에게 보낼 상자를 찍는다', /친구에게 이 줄을 보내세요/.test(run.out()), run.out().slice(-800));
  t.ok('cloudflared 는 한 번도 안 불렸다', w.cfUsed() === 0);
  t.ok('trycloudflare 주소가 안 나온다', !/trycloudflare/.test(run.out()), run.out().slice(-800));
  t.ok('설정의 주소가 그대로다', w.config().origin === TS_URL, w.config().origin);
  t.ok('Tailscale 주소를 따로 기억해 둔다 (tailscaleOrigin)', w.config().tailscaleOrigin === TS_URL,
       w.config().tailscaleOrigin);
  /* 9/24 · 9/29 · 9/30 에 사람이 손으로 쳐서 풀었던 두 줄 */
  const kicked = await until(() => w.debugCalls().length >= 2, 4000, 100);
  t.ok('붙은 뒤 중계를 한 번 다시 잡는다 (rebind → restun)',
       kicked && w.debugCalls().join(',') === 'rebind,restun', w.debugCalls());
  t.ok('다시 잡는다고 한 줄 적는다', count(run.out(), /중계를 한 번 다시 잡습니다/g) === 1, run.out().slice(-800));
  const pids = w.funnelPids();
  const ms = await stop(run);
  t.ok('SIGTERM 에 끝난다', ms >= 0 && ms < 3000, ms + 'ms');
  t.ok('funnel 이 같이 꺼진다', pids.every(p => !alive(p)), pids);
});

block('[2] funnel 이 도중에 죽으면 다시 붙인다', async t => {
  /* 이미 한 번 Tailscale 로 연 적이 있는 컴퓨터(설정이 다 적혀 있음) */
  const w = await t.world('reattach', { origin: TS_URL, tailscaleOrigin: TS_URL,
                                        status: STATUS.ready, funnel: FUNNEL.onceDies });
  const mtime0 = w.mtime();
  const run = launch(w);
  const back = await until(() => /터널 다시 붙음/.test(run.out()), 25000, 200);
  await wait(800);
  const out = run.out();
  t.ok('다시 띄운다 (funnel 두 번 이상)', w.funnelPids().length >= 2, w.funnelPids());
  t.ok('다시 붙었다고 말한다', back, out.slice(-900));
  t.ok('끊겼다고 말한다 (한 번)', count(out, /터널이 끊겼습니다/g) === 1, out.slice(-900));
  t.ok('언제 다시 붙이는지 말한다', /뒤 다시 붙여 봅니다/.test(out), out.slice(-900));
  t.ok('친구에게 보낼 상자는 한 번만 찍는다', count(out, /친구에게 이 줄을 보내세요/g) === 1, out.slice(-900));
  t.ok('살다 죽은 funnel 에 "Funnel 을 켜세요" 를 안 한다',
       !/Funnel 이 이 테일넷에서 아직 안 켜져/.test(out), out.slice(-900));
  t.ok('cloudflared 로 안 바꾼다', w.cfUsed() === 0);
  t.ok('설정의 주소가 그대로다', w.config().origin === TS_URL, w.config().origin);
  /* 부팅마다 설정 파일을 통째로 다시 쓰면, 비정상 종료 직후에 찢어질 수 있습니다 */
  t.ok('바뀐 것이 없으면 설정 파일을 다시 쓰지 않는다', w.mtime() === mtime0, mtime0 + ' → ' + w.mtime());
  t.ok('중계 다시 잡기는 5분에 한 번까지 (다시 붙어도 또 안 한다)', w.debugCalls().length === 2,
       w.debugCalls());
  const pids = w.funnelPids();
  const ms = await stop(run);
  t.ok('SIGTERM 에 끝난다', ms >= 0 && ms < 3000, ms + 'ms');
  t.ok('다시 띄운 funnel 까지 같이 꺼진다', pids.every(p => !alive(p)), pids);
});

block('[3] funnel 이 계속 죽어도 촘촘히 돌지 않는다 (간격이 늘고, 로그가 안 쌓인다)', async t => {
  /* 간격 0.1 → 0.2 → 0.4 → 0.8 → 1.2초(끝), 끝에 닿은 뒤로는 6초에 한 줄
     (진짜로는 5초 → 60초, 5분에 한 줄 — 둘 다 MYBODY_TS_BACKOFF_MS 의 배수). */
  const w = await t.world('backoff', { origin: TS_URL, status: STATUS.ready, funnel: FUNNEL.alwaysDies });
  const run = launch(w, [], { MYBODY_TS_BACKOFF_MS: '100', MYBODY_EXIT_DELAY_MS: '1500' });
  const up = await until(() => w.funnelPids().length >= 1, 20000, 100);
  const t1 = Date.now();
  await wait(12000);
  const n = w.funnelPids().length;
  const out = run.out();
  /* 12초면 13번쯤입니다. 간격이 안 늘면 80번이 넘습니다. */
  t.ok('다시 시도는 한다 (12초에 8번 이상)', up && n >= 8, n);
  t.ok('간격이 늘어난다 (12초에 20번 이하)', n <= 20, n + '번 / ' + (Date.now() - t1) + 'ms');
  t.ok('긴 설명은 한 번만', count(out, /터널이 주소를 못 만들고 끝났습니다/g) === 1, out.slice(-900));
  t.ok('tailscale 이 한 말 · 켜는 링크는 보여 준다',
       /Funnel is not enabled/.test(out) && /login\.tailscale\.com\/f\/funnel/.test(out), out.slice(-900));
  /* 간격이 끝에 닿기 전 3줄 + 닿은 뒤 6초에 한 줄 → 12초에 4~5줄. 한도가 없으면 12줄쯤. */
  t.ok('끊김 줄은 간격 끝에 닿으면 줄인다 (12초에 7줄 이하)', count(out, /터널이 또 끊겼습니다/g) <= 7,
       count(out, /터널이 또 끊겼습니다/g) + '줄\n' + out.slice(-900));
  t.ok('줄인 동안 몇 번이었는지 센다 ("그 사이 N번 더")', /그 사이 \d+번 더/.test(out), out.slice(-900));
  t.ok('주소를 찍지 않는다 (안 열리는 주소)', !out.includes(TS_URL), out.slice(-900));
  t.ok('ts.net 에 묶인 컴퓨터에 --cloudflare 를 권하지 않는다', !/--cloudflare/.test(out), out.slice(-900));
  t.ok('cloudflared 로 안 바꾼다', w.cfUsed() === 0);
  /* 끄기. launch.js 는 서버가 꺼진 뒤 1.5초 더 살아 있다가 끝납니다(MYBODY_EXIT_DELAY_MS) —
     서버가 늦게 꺼지는 날을 흉내 냅니다. 그 사이 걷지 못한 다시 붙이기 타이머가
     있으면 울려서 tailscale 을 또 부릅니다. */
  const t0 = Date.now();
  run.child.kill('SIGTERM');
  await wait(150);
  const s0 = w.statusCalls(), f0 = w.funnelPids().length;
  const r = await Promise.race([run.exited, wait(5000).then(() => null)]);
  await wait(300);
  t.ok('SIGTERM 에 끝난다 (늦게 꺼지는 1.5초 포함 3초 안)', r && r.at - t0 < 3000, r ? (r.at - t0) + 'ms' : '안 끝남');
  t.ok('끈 뒤에는 다시 묻지도 띄우지도 않는다 (걸어 둔 타이머가 안 울린다)',
       w.statusCalls() === s0 && w.funnelPids().length === f0,
       'status ' + s0 + ' → ' + w.statusCalls() + ' · funnel ' + f0 + ' → ' + w.funnelPids().length);
});

block('[4] 붙었다 끊기기를 되풀이해도 "다시 붙음" 줄이 안 쌓인다', async t => {
  /* 끊김 줄만 줄이고 "다시 붙음" 은 매번 찍으면, 진짜 간격(60초)으로 하루 1,400줄이
     회전 없는 mybody.log 에 쌓입니다. 적은 끊김만 "다시 붙음" 으로 닫는지 봅니다. */
  const w = await t.world('flap', { origin: TS_URL, status: STATUS.ready, funnel: FUNNEL.flaps });
  const run = launch(w, [], { MYBODY_TS_BACKOFF_MS: '100' });
  const up = await until(() => w.funnelPids().length >= 1, 20000, 100);
  await wait(12000);
  const out = run.out();
  const n = w.funnelPids().length;
  const back = count(out, /터널 다시 붙음/g);
  /* 적은 끊김 = 첫 긴 설명의 "… 뒤 다시 붙여 봅니다" + 짧은 "또 끊겼습니다" 줄 */
  const downLines = count(out, /뒤 다시 붙여 봅니다/g) + count(out, /터널이 또 끊겼습니다/g);
  t.ok('계속 다시 붙인다 (12초에 7번 이상)', up && n >= 7, n);
  t.ok('"다시 붙음" 은 적은 끊김 수를 넘지 않는다', back >= 1 && back <= downLines,
       '다시 붙음 ' + back + ' · 적은 끊김 ' + downLines + ' · funnel ' + n);
  t.ok('"다시 붙음" 이 붙은 횟수만큼 쌓이지 않는다 (12초에 6줄 이하)', back <= 6 && back < n - 1,
       '다시 붙음 ' + back + ' · funnel ' + n);
  t.ok('상자는 한 번만', count(out, /친구에게 이 줄을 보내세요/g) === 1, out.slice(-900));
  t.ok('중계 다시 잡기도 한도 안에서만 (6초에 한 번)', w.debugCalls().length <= 6, w.debugCalls());
  const ms = await stop(run);
  t.ok('SIGTERM 에 끝난다', ms >= 0 && ms < 3000, ms + 'ms');
});

block('[5] 간격 되돌리기 — 2분(여기선 2.4초) 넘게 버티다 죽은 것은 새 사고로 본다', async t => {
  const w = await t.world('reset', { origin: TS_URL, status: STATUS.ready, funnel: FUNNEL.resetCheck });
  const run = launch(w, [], { MYBODY_TS_BACKOFF_MS: '100' });
  const back = await until(() => /터널 다시 붙음/.test(run.out()), 20000, 100);
  await wait(300);
  const out = run.out();
  const again = out.split('\n').filter(l => /터널이 또 끊겼습니다/.test(l));
  t.ok('네 번째에 다시 붙는다', back && w.funnelPids().length >= 4, w.funnelPids().length + '\n' + out.slice(-900));
  t.ok('곧바로 죽는 동안은 간격이 는다 (0.1 → 0.2초)',
       /0\.1초 뒤 다시 붙여 봅니다/.test(out) && again.length >= 1 && /0\.2초 뒤/.test(again[0]), again);
  t.ok('버티다 죽은 뒤에는 처음 간격으로 (0.4초가 아니라 0.1초)',
       again.length >= 2 && /0\.1초 뒤/.test(again[1]), again);
  t.ok('적은 끊김은 "다시 붙음" 으로 닫는다 (한 번)', count(out, /터널 다시 붙음/g) === 1, out.slice(-900));
  t.ok('상자는 처음 주소를 받았을 때 한 번만', count(out, /친구에게 이 줄을 보내세요/g) === 1, out.slice(-900));
  const ms = await stop(run);
  t.ok('SIGTERM 에 끝난다', ms >= 0 && ms < 3000, ms + 'ms');
});

block('[6] ts.net 에 안 묶인 컴퓨터는 그대로 — 로그인 안 됐으면 cloudflared 로, 이유와 함께', async t => {
  /* 진짜 CLI 처럼 0 으로 끝나며 NeedsLogin — 기기 이름은 남아 있습니다 */
  const w = await t.world('free', { origin: '', status: STATUS.needsLogin,
                                    cfUrl: 'https://fallback-test-abc.trycloudflare.com' });
  const run = launch(w);
  const got = await until(() => /fallback-test-abc\.trycloudflare\.com/.test(run.out()), 25000, 200);
  const out = run.out();
  t.ok('Cloudflare 임시 터널로 연다', /Cloudflare 임시 터널로 엽니다/.test(out), out.slice(0, 800));
  t.ok('Tailscale 을 안 쓴 이유를 말한다', /안 쓴 이유/.test(out) && /로그인/.test(out), out.slice(0, 800));
  t.ok('cloudflared 주소를 찍는다', got, out.slice(-800));
  t.ok('기다리지 않는다', !/Tailscale 준비를 기다립니다/.test(out), out.slice(0, 800));
  t.ok('funnel 은 안 띄운다 (남은 기기 이름만 보고 "준비됨" 이라 하지 않는다)', w.funnelPids().length === 0,
       w.funnelPids());
  t.ok('ts.net 에 묶였다고 적지 않는다', !w.config().tailscaleOrigin, w.config().tailscaleOrigin);
  await stop(run);
});

block('[7] Tailscale 을 기다리는 중에 끄면 — 곧바로, 남김없이', async t => {
  const w = await t.world('term', { origin: TS_URL, status: STATUS.slow });
  const run = launch(w);
  const up = await until(() => healthy(w.port), 30000, 200);
  t.ok('서버는 떠 있다', up, run.out().slice(-800));
  await until(() => w.statusCalls() >= 3, 8000);
  const ms = await stop(run);
  t.ok('3초 안에 끝난다', ms >= 0 && ms < 3000, ms + 'ms');
  t.ok('funnel 은 한 번도 안 떴다', w.funnelPids().length === 0, w.funnelPids());
  t.ok('cloudflared 도 안 떴다', w.cfUsed() === 0);
  const left = leftovers(w.dir);
  if (left === null) t.note('ps 가 없어 남은 프로세스는 못 봅니다');
  else t.ok('묻던 tailscale 까지 남은 프로세스가 없다', left.length === 0, left.join('\n'));
  await wait(300);
  t.ok('서버도 꺼졌다', !(await healthy(w.port)));
  t.ok('끈다고 "끊겼습니다" 를 찍지 않는다', !/끊겼습니다/.test(run.out()), run.out().slice(-600));
});

block('[8] ts.net 주소로 쓰는데 Tailscale 이 아예 없으면 — 같은 와이파이로 버티다 깔리면 연다', async t => {
  /* 이 컴퓨터에 진짜 tailscale 이 기본 자리에 있으면 "없는" 상태를 못 만듭니다. */
  const real = ['/usr/bin/tailscale', '/usr/local/bin/tailscale', '/opt/homebrew/bin/tailscale',
                '/Applications/Tailscale.app/Contents/MacOS/Tailscale'].filter(p => fs.existsSync(p));
  if (real.length) { t.note('진짜 tailscale 이 있어 건너뜁니다: ' + real.join(', ')); return; }
  const w = await t.world('none', { origin: TS_URL });
  /* PATH 에서도 빼 둡니다 — 가짜 폴더(지금은 cloudflared 만)와 기본 명령만. */
  const run = launch(w, [], { PATH: w.bin + path.delimiter + '/usr/bin:/bin' });
  const up = await until(() => healthy(w.port), 30000, 200);
  const out = run.out();
  t.ok('서버는 띄운다 (같은 와이파이로라도)', up, out.slice(-800));
  t.ok('안 깔려 있다고 말한다', /Tailscale 준비를 기다립니다 — Tailscale 이 안 깔려 있습니다/.test(out),
       out.slice(0, 800));
  t.ok('까는 법은 Tailscale 쪽만 보여 준다',
       /tailscale\.com\/install\.sh|brew install tailscale/.test(out) && !/Cloudflare, 계정 없이/.test(out),
       out.slice(0, 1200));
  t.ok('끝내지 않는다 (작업 스케줄러가 포기하기 전에 스스로 버틴다)', run.child.exitCode === null);
  t.ok('cloudflared 는 안 쓴다', w.cfUsed() === 0);
  /* 누가 tailscale 을 깔았다 */
  w.writeTailscale(STATUS.ready, FUNNEL.stay(TS_URL));
  const opened = await until(() => BOX_URL.test(run.out()), 8000);
  t.ok('깔리면 알아채고 주소를 연다', opened && w.funnelPids().length === 1, run.out().slice(-800));
  const ms = await stop(run);
  t.ok('SIGTERM 에 끝난다', ms >= 0 && ms < 3000, ms + 'ms');
});

block('[9] 로그인이 풀린 채 기다리면 — 사람이 필요하다고 말하고, 묻는 간격 · 로그가 줄어든다', async t => {
  /* 키 만료 · 로그아웃: status --json 은 0 으로 끝나고 기기 이름도 남아 있습니다.
     묻기 0.1초 → 2.4초 뒤부터 0.6초, "아직 기다리는 중" 은 6초에 한 줄
     (진짜로는 5초 → 2분 뒤 30초, 5분에 한 줄 — 모두 MYBODY_TS_POLL_MS 의 배수). */
  const w = await t.world('login', { origin: TS_URL, status: STATUS.needsLogin });
  const run = launch(w, [], { MYBODY_TS_POLL_MS: '100' });
  const up = await until(() => healthy(w.port), 30000, 100);
  t.ok('서버는 먼저 뜬다', up, run.out().slice(-800));
  t.ok('로그인이 필요하다고 · 기다려도 안 풀린다고 말한다',
       /Tailscale 준비를 기다립니다 — Tailscale 에 다시 로그인해야 합니다/.test(run.out()) &&
       /저절로 안 풀립니다/.test(run.out()), run.out().slice(0, 900));
  /* 띄울 때 한 번 + 기다리며 처음 묻기 → 여기서부터 잽니다 */
  await until(() => w.statusCalls() >= 2, 10000, 20);
  const tFast = Date.now(), cFast = w.statusCalls();
  await wait(1000);
  const fast = w.statusCalls() - cFast;
  t.ok('처음에는 촘촘히 묻는다 (1초에 5번 이상)', fast >= 5, fast + '번');
  const said = await until(() => /아직 기다리는 중/.test(run.out()), 15000, 50);
  const tSaid = Date.now();
  t.ok('"아직 기다리는 중" 은 한참 뒤에야 처음 찍는다 (5초 넘어서)', said && tSaid - tFast >= 5000,
       (tSaid - tFast) + 'ms');
  const cSlow = w.statusCalls();
  await wait(3000);
  const slow = w.statusCalls() - cSlow;
  const out = run.out();
  t.ok('나중에는 드문드문 묻는다 (3초에 9번 이하)', slow <= 9, slow + '번');
  t.ok('"아직 기다리는 중" 은 한 줄뿐 (묻는 때마다 찍지 않는다)', count(out, /아직 기다리는 중/g) === 1,
       count(out, /아직 기다리는 중/g) + '줄');
  t.ok('그 줄에도 사람이 필요하다고 적는다',
       /아직 기다리는 중 \([^)]*\) — Tailscale 에 다시 로그인해야 합니다/.test(out), out.slice(-600));
  t.ok('남은 기기 이름만 보고 funnel 을 띄우지 않는다', w.funnelPids().length === 0, w.funnelPids());
  t.ok('주소 상자를 안 찍는다', !BOX_URL.test(out), out.slice(-600));
  t.ok('cloudflared 도 안 쓴다', w.cfUsed() === 0);
  const ms = await stop(run);
  t.ok('SIGTERM 에 끝난다', ms >= 0 && ms < 3000, ms + 'ms');
});

block('[10] --cloudflare 로 한 번 띄운 뒤에도 ts.net 에 묶인 채로 남는다', async t => {
  /* 이 판 전에 만든 설정(노트북) — tailscaleOrigin 이 없고 origin 만 ts.net */
  const CF = 'https://random-abc.trycloudflare.com';
  const w = await t.world('sticky', { origin: TS_URL, status: STATUS.down, cfUrl: CF });
  const a = launch(w, ['--cloudflare']);
  const got = await until(() => a.out().includes(CF) && w.config().origin === CF, 20000, 150);
  const outA = a.out();
  t.ok('--cloudflare 는 사람이 고른 것이라 그대로 따른다', got && /Cloudflare 임시 터널로 엽니다/.test(outA),
       outA.slice(-800));
  t.ok('원래 ts.net 주소를 기억해 둔다고 말한다', /원래 주소\(https:\/\/mypc\.tail9f2c\.ts\.net\)는 기억해 둡니다/.test(outA),
       outA.slice(-900));
  t.ok('설정에 ts.net 주소를 따로 남긴다', w.config().tailscaleOrigin === TS_URL, w.config());
  await stop(a);
  const cfBefore = w.cfUsed();
  /* 그 다음 부팅 — Tailscale 이 아직 안 떴다 */
  const b = launch(w);
  const waiting = await until(async () => /Tailscale 준비를 기다립니다/.test(b.out()) && await healthy(w.port),
                              30000, 150);
  await wait(2000);            // 터널은 서버를 띄우고 1.5초 뒤에 고릅니다 — 그 뒤까지 봅니다
  const outB = b.out();
  t.ok('다음 부팅에는 Cloudflare 로 안 넘어가고 기다린다', waiting && !/Cloudflare 임시 터널로 엽니다/.test(outB),
       outB.slice(0, 900));
  t.ok('기다리는 까닭에 원래 주소를 적는다', /이 컴퓨터 주소는 https:\/\/mypc\.tail9f2c\.ts\.net/.test(outB),
       outB.slice(0, 900));
  t.ok('cloudflared 를 다시 부르지 않는다', w.cfUsed() === cfBefore, cfBefore + ' → ' + w.cfUsed());
  const ms = await stop(b);
  t.ok('SIGTERM 에 끝난다', ms >= 0 && ms < 3000, ms + 'ms');
});

block('[11] 기기 이름이 바뀌어 ts.net 주소가 달라지면 — 크게 말한다', async t => {
  const w = await t.world('renamed', { origin: TS_URL, tailscaleOrigin: TS_URL,
                                       status: STATUS.renamed, funnel: FUNNEL.stay(TS_URL2) });
  /* 덤으로: 중계 다시 잡기(rebind)가 대답 없이 붙들고 있을 때 끄면 그것도 같이 꺼지는가 */
  fs.writeFileSync(path.join(w.st, 'debug-hangs'), '1');
  const run = launch(w);
  const opened = await until(() => boxUrl(NAME2).test(run.out()), 20000, 150);
  await wait(200);
  const out = run.out();
  t.ok('새 주소로 연다', opened, out.slice(-900));
  t.ok('주소가 바뀌었다고 경고한다', /공개 주소가 \*\*바뀌었습니다/.test(out), out.slice(-1200));
  t.ok('전 주소와 새 주소를 둘 다 보여 준다',
       new RegExp('전\\s+' + TS_URL.replace(/\./g, '\\.')).test(out) &&
       new RegExp('지금\\s+' + TS_URL2.replace(/\./g, '\\.')).test(out), out.slice(-1200));
  t.ok('"이 주소는 안 바뀝니다" 를 하지 않는다', !/이 주소는 \*\*안 바뀝니다/.test(out), out.slice(-900));
  t.ok('설정은 새 주소로 넘긴다 (서버는 실제 주소로 돌아야 합니다)',
       w.config().origin === TS_URL2 && w.config().tailscaleOrigin === TS_URL2, w.config());
  const hung = await until(() => w.debugPids().length >= 1, 4000, 50);
  const dpids = w.debugPids();
  const ms = await stop(run);
  t.ok('SIGTERM 에 끝난다', ms >= 0 && ms < 3000, ms + 'ms');
  await wait(200);
  t.ok('붙들고 있던 중계 다시 잡기(rebind)도 같이 꺼진다', hung && dpids.every(p => !alive(p)), dpids);
});

/* --- 돌리기 --------------------------------------------------------------- */
(async () => {
  const T0 = Date.now();
  const results = BLOCKS.map(() => null);
  let printed = 0;
  const flush = () => {
    while (printed < results.length && results[printed]) {
      const r = results[printed++];
      console.log('\n' + r.title + '   (' + Math.round(r.ms / 100) / 10 + '초)');
      r.lines.forEach(l => console.log(l));
    }
  };
  const runBlock = async i => {
    const b = BLOCKS[i];
    const res = { title: b.title, lines: [], pass: 0, fail: 0, ms: 0 };
    const worlds = [];
    const t = {
      ok: (n, c, d) => {
        if (c) { res.pass++; res.lines.push('  ✓ ' + n); }
        else { res.fail++; res.lines.push('  ✗ ' + n + ' ' + (d === undefined ? '' : String(
          typeof d === 'object' ? JSON.stringify(d) : d).slice(0, 600))); }
      },
      note: m => res.lines.push('  · ' + m),
      world: async (tag, opts) => { const w = await world(tag, opts); worlds.push(w); return w; }
    };
    const s = Date.now();
    try { await b.fn(t); }
    catch (e) { t.ok('절이 끝까지 돈다', false, (e && e.stack) || e); }
    finally { worlds.forEach(cleanup); }
    res.ms = Date.now() - s;
    results[i] = res;
    flush();
  };

  /* 첫 절은 혼자 — 배포 빌드가 낡았으면 여기서 한 번 만들어집니다. */
  await runBlock(0);
  let next = 1;
  const lane = async () => { while (next < BLOCKS.length) await runBlock(next++); };
  await Promise.all(Array.from({ length: Math.min(JOBS, BLOCKS.length - 1) }, lane));

  const pass = results.reduce((n, r) => n + r.pass, 0);
  const fail = results.reduce((n, r) => n + r.fail, 0);
  console.log(`\n통과 ${pass} / 실패 ${fail}   (${Math.round((Date.now() - T0) / 1000)}초)`);
  process.exit(fail ? 1 : 0);
})().catch(e => { console.error(e); process.exit(1); });
