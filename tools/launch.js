/* =============================================================================
 * tools/launch.js — 한 줄로 배포까지
 *
 *   node tools/launch.js
 *
 * 하는 일 (없는 것만 알아서 만듭니다)
 *   1. 이 컴퓨터가 띄울 수 있는지 봅니다
 *   2. 설정이 없으면 만듭니다 (이름은 안 겁니다)
 *   3. 알림 열쇠가 없으면 만듭니다
 *   4. 배포 빌드가 낡았으면 다시 만듭니다
 *   5. 서버를 띄웁니다
 *   6. 터널을 띄워 https 주소를 받습니다
 *   7. **친구에게 보낼 것을 한 덩어리로 찍어 줍니다**
 *
 * 왜 따로 만드는가
 *   serve.js 는 "서버를 띄운다" 하나만 합니다. 그건 그대로 두는 편이
 *   낫습니다 — 고칠 때 무엇을 건드리는지가 분명하니까요. 여기는 그
 *   위에서 순서를 잡는 자리입니다.
 *
 * 가입
 *   기본은 **코드 없이 가입** 입니다. 주인이 그렇게 정했습니다 — 친구에게
 *   주소 한 줄만 보내면 됩니다. 대신 **주소를 아는 사람은 누구나 계정을
 *   만들 수 있습니다.** 내 몸 숫자를 보는 것은 아니지만(친구 맺기는
 *   초대 코드가 따로 필요합니다), 모르는 사람 계정이 쌓일 수 있습니다.
 *   닫고 싶으면:  node tools/launch.js --pair-code
 *
 * 상시 접속
 *   주인이 컴퓨터를 계속 켜 두기로 했습니다. 그래서 배포 전 점검의
 *   "컴퓨터가 꺼지면 친구도 못 봅니다" 잔소리를 끕니다. 껐다 켰다 할
 *   거면:  node tools/launch.js --not-always-on
 *
 * 터널 두 가지 — 주소가 바뀌느냐가 전부입니다
 *   tailscale   주소가 **안 바뀝니다**. 계정이 필요하지만 개인은 무료입니다.
 *               크롬이 이 도메인을 막지 않아서 **폰에 앱으로 깔 수 있습니다.**
 *   cloudflared 계정 없이 30초면 되지만 **띄울 때마다 주소가 바뀌고**,
 *               trycloudflare 는 구글이 위험 사이트로 표시해서 크롬이
 *               앱 설치를 아예 안 내줍니다.
 *
 *   브라우저는 기록을 주소별로 따로 저장합니다. 주소가 바뀌면 친구들
 *   폰에서 그동안의 기록이 통째로 안 보이게 됩니다. 그래서 둘 다 있으면
 *   tailscale 을 씁니다 — 취향이 아니라 데이터 문제입니다.
 *   일부러 바꾸려면 --cloudflare.
 *
 * 사람이 없을 때 (자동 시작 — 노트북 보고 48)
 *   이미 ts.net 주소로 쓰는 컴퓨터(설정의 origin · tailscaleOrigin, 또는
 *   --tailscale)는 Tailscale 이 늦어도 **Cloudflare 로 넘어가지 않습니다.**
 *   서버를 먼저 띄우고 Tailscale 이 준비될 때까지 기다렸다가 funnel 을 엽니다.
 *   funnel 이 도중에 죽으면 5초 → 10초 → … → 60초 간격으로 다시 붙이고,
 *   붙은 뒤에는 중계를 한 번 다시 잡습니다(debug rebind · restun).
 *   자세한 까닭은 아래 "6-3" · "6-4" 에 있습니다.
 * ========================================================================== */
'use strict';
const { spawn, spawnSync } = require('node:child_process');
const path = require('node:path');
const fs = require('node:fs');
const os = require('node:os');

const ROOT = path.join(__dirname, '..');
const CONFIG = require(path.join(__dirname, 'config.js'));
const args = process.argv.slice(2);
const has = f => args.includes('--' + f);

/* 내가 일부러 끄는 중인가. 종료 중에 나오는 "끊겼습니다" 는 고장이
   아니라 정상인데, 그렇게 말하면 사람이 고장으로 읽습니다. */
const QUITTING = { now: false };

/* 걸어 둔 타이머와 살아 있는 자식 — 끌 때 **하나도 안 남기려고** 한 곳에 둡니다.
 *
 * 이제 이 프로세스는 오래 삽니다. Tailscale 을 기다리며 몇 초마다 묻고,
 * funnel 이 죽으면 조금 뒤 다시 붙입니다. 그 타이머 하나가 Ctrl+C 뒤에
 * 살아 있으면, 서버는 꺼졌는데 funnel 이 새로 떠서 "열려 있는데 아무것도
 * 없는 주소" 가 생깁니다. 그래서 전부 later() 로 걸고, 끌 때 한 번에
 * 걷습니다. 걷기 전에 울려도 QUITTING 이면 아무것도 안 합니다. */
const TIMERS = new Set();
const KIDS = { tunnel: null, poll: null, kick: null };
/* 노드는 2147483647ms(약 24일)보다 긴 setTimeout 을 **1ms** 로 바꿔 버립니다.
   환경변수를 잘못 넣어 간격이 그만큼 커지면 "몇 분마다" 가 "쉬지 않고" 가
   됩니다 — 사람 없는 노트북에서 funnel 을 1ms 마다 띄우는 고리. 여기서 막습니다. */
const MAX_DELAY = 2147483647;
function later(fn, ms) {
  const t = setTimeout(() => { TIMERS.delete(t); if (!QUITTING.now) fn(); },
                       Math.min(Math.max(Number(ms) || 0, 0), MAX_DELAY));
  TIMERS.add(t);
  return t;
}
function cancel(t) { clearTimeout(t); TIMERS.delete(t); }
function stopEverything() {
  QUITTING.now = true;
  TIMERS.forEach(t => clearTimeout(t));
  TIMERS.clear();
  try { if (KIDS.poll) KIDS.poll.kill(); } catch (e) {}
  try { if (KIDS.kick) KIDS.kick.kill(); } catch (e) {}
  try { if (KIDS.tunnel) KIDS.tunnel.kill(); } catch (e) {}
}

function line(s) { console.log(s); }
function box(lines) {
  const w = Math.max(...lines.map(l => [...l].reduce((n, c) => n + (c.charCodeAt(0) > 0x2000 ? 2 : 1), 0)));
  const bar = '─'.repeat(Math.min(w + 2, 72));
  line('┌' + bar + '┐');
  lines.forEach(l => line('│ ' + l));
  line('└' + bar + '┘');
}
const node = process.execPath;
function run(script, extra, env) {
  return spawnSync(node, [path.join(__dirname, script)].concat(extra || []),
    { cwd: ROOT, env: env || process.env, encoding: 'utf8' });
}

/* --- 터널 도구 찾기 --------------------------------------------------------
 *
 * 두 가지를 씁니다. **주소가 바뀌느냐**가 갈림길입니다.
 *
 *   tailscale   주소가 **안 바뀝니다** (https://<기기>.<테일넷>.ts.net).
 *               계정이 필요하지만 개인은 무료이고, 인증서도 진짜입니다.
 *               크롬이 이 도메인을 막지 않아서 **앱 설치가 됩니다.**
 *   cloudflared 계정 없이 30초면 되지만 **띄울 때마다 주소가 바뀝니다.**
 *               그리고 trycloudflare 는 공용 도메인이라 크롬이 위험
 *               사이트로 표시하고, 그 상태에서는 앱 설치를 막습니다.
 *
 * 브라우저는 기록을 주소별로 따로 저장합니다. 주소가 바뀌면 친구들
 * 폰에서 그동안의 기록이 통째로 안 보이게 됩니다. 그래서 둘 다 있으면
 * **tailscale 을 씁니다.** 이건 취향이 아니라 데이터 문제입니다.
 * -------------------------------------------------------------------------- */
/* 방금 깐 프로그램은 **이미 열려 있는 터미널의 PATH 에 없습니다.**
 * 윈도우가 특히 그렇습니다 — winget 으로 깔고 바로 쳐도 "없다" 고 나옵니다.
 * 주인이 실제로 여기서 막혔습니다: Tailscale 을 깔았고 100.x 주소까지
 * 받았는데, launch 는 끝내 cloudflared 로 갔습니다.
 *
 * "터미널을 새로 여세요" 라고 말하는 것도 필요하지만, 그 전에 **기본
 * 설치 자리를 직접 봐 주는 편**이 낫습니다. 사람에게 시킬 수 있는 일을
 * 도구가 할 수 있으면 도구가 합니다. */
/** Tailscale 을 왜 안 썼는지. cloudflared 로 갈 때 같이 찍습니다. */
let tunnelNote = null;

const WELL_KNOWN = {
  tailscale: process.platform === 'win32'
    ? [path.join(process.env['ProgramFiles'] || 'C:\\Program Files', 'Tailscale', 'tailscale.exe'),
       path.join(process.env['ProgramFiles(x86)'] || 'C:\\Program Files (x86)', 'Tailscale', 'tailscale.exe')]
    : process.platform === 'darwin'
      ? ['/Applications/Tailscale.app/Contents/MacOS/Tailscale',
         '/opt/homebrew/bin/tailscale', '/usr/local/bin/tailscale']
      : ['/usr/bin/tailscale', '/usr/local/bin/tailscale'],
  cloudflared: process.platform === 'win32'
    ? [path.join(process.env['ProgramFiles'] || 'C:\\Program Files', 'cloudflared', 'cloudflared.exe')]
    : ['/opt/homebrew/bin/cloudflared', '/usr/local/bin/cloudflared', '/usr/bin/cloudflared']
};

/** 실행 파일을 찾습니다. PATH 에 없으면 기본 설치 자리도 봅니다.
 *  windowsHide: 이제 기다리는 동안 30초마다 부릅니다. 창 없이 도는
 *  작업 스케줄러 아래에서 콘솔 창이 30초마다 번쩍이면 안 됩니다. */
function findBin(bin) {
  const which = process.platform === 'win32' ? 'where' : 'which';
  const r = spawnSync(which, [bin], { encoding: 'utf8', windowsHide: true });
  if (r.status === 0 && (r.stdout || '').trim()) return bin;
  for (const p of (WELL_KNOWN[bin] || [])) {
    try { if (fs.existsSync(p)) return p; } catch (e) {}
  }
  return null;
}

function tailscaleMissing() {
  return { bin: null, name: null,
    why: process.platform === 'win32'
      ? 'Tailscale 이 안 깔려 있습니다 (winget install --id tailscale.tailscale). ' +
        '방금 깔았다면 **PowerShell 창을 닫고 새로 여세요.**'
      : 'Tailscale 이 안 깔려 있습니다.' };
}

/** tailscale 이 왜 안 되는지까지 알려줍니다. { bin, name, why }
 *  띄울 때 한 번은 여기서 그 자리에서 묻고, 준비를 기다리는 동안은
 *  tailscaleStateLater 로 묻습니다 — 읽는 법은 readTailscale 하나입니다. */
function tailscaleState() {
  const bin = findBin('tailscale');
  if (!bin) return tailscaleMissing();
  return readTailscale(bin, spawnSync(bin, ['status', '--json'],
    { encoding: 'utf8', timeout: 8000, windowsHide: true }));
}

/* BackendState 마다 사람에게 할 말.
 *
 * `tailscale status --json` 은 **로그아웃 · 꺼짐이어도 0 으로 끝나고**
 * JSON 을 냅니다. 1 로 끝나며 "Logged out." 을 찍는 것은 --json 없이 부를
 * 때뿐입니다. 그리고 키가 만료됐거나(기본 180일 — 사람 없는 노트북에서
 * 조용히 옵니다) 트레이에서 Disconnect 를 눌러도 tailscaled 는 마지막
 * 네트워크 지도를 쥐고 있어서 Self.DNSName 이 **그대로 남습니다.** 이름만
 * 보고 "준비됨" 이라 하면 funnel 을 띄우고 상자까지 찍은 뒤 영원히 다시
 * 붙이면서, 정작 사람이 할 일(다시 로그인 · Connect)은 한 번도 말하지
 * 않게 됩니다.
 *
 * 그래서 Running 일 때만 준비됨으로 봅니다. 앞의 셋은 **기다려도 안
 * 풀립니다** — 5분마다 찍히는 "아직 기다리는 중" 줄이 부팅 중인지 사람이
 * 필요한지를 가를 수 있게, 이유에 그 말을 넣습니다. */
const BACKEND_WHY = {
  NeedsLogin: 'Tailscale 에 다시 로그인해야 합니다(키 만료 포함) — 기다려도 저절로 안 풀립니다. ' +
              '트레이(또는 메뉴 막대)의 Tailscale 에서 로그인하세요.',
  NeedsMachineAuth: '이 기기가 테일넷 관리자 승인을 기다립니다 — 기다려도 저절로 안 풀립니다. ' +
                    'https://login.tailscale.com/admin/machines 에서 승인하세요.',
  Stopped: 'Tailscale 이 꺼져 있습니다(Disconnect) — 기다려도 저절로 안 풀립니다. ' +
           '트레이의 Tailscale 에서 Connect 를 누르세요.',
  InUseOtherUser: '이 컴퓨터의 다른 사용자가 Tailscale 을 쓰고 있습니다 — 기다려도 저절로 안 풀립니다.',
  NoState: 'Tailscale 이 아직 켜지는 중입니다 (NoState)',
  Starting: 'Tailscale 이 아직 켜지는 중입니다 (Starting)'
};

/** `tailscale status --json` 의 결과({ status, stdout, stderr })를 읽습니다. */
function readTailscale(bin, r) {
  if (r.status !== 0) {
    /* 여기로 오는 것은 대개 tailscaled 자체가 안 떠 있을 때입니다(부팅 직후).
       --json 없이 부른 옛 판 · 가짜 도구가 "Logged out." 으로 1 을 낼 때도
       있어서 그 말은 그대로 알아듣습니다. */
    const msg = ((r.stderr || '') + (r.stdout || '')).trim().split('\n')[0];
    return { bin: bin, name: null,
      why: /logged out|NeedsLogin|not running|Tailscale is stopped/i.test(msg)
        ? 'Tailscale 에 로그인해야 합니다 — 트레이(또는 메뉴 막대)의 Tailscale 에서 로그인하세요.'
        : 'Tailscale 이 대답하지 않습니다' + (msg ? ' (' + msg.slice(0, 80) + ')' : '') };
  }
  let j;
  try { j = JSON.parse(r.stdout || '{}') || {}; }
  catch (e) { return { bin: bin, name: null, why: 'Tailscale 상태를 읽지 못했습니다' }; }
  const state = String(j.BackendState || '');
  /* BackendState 가 아예 없으면(모르는 판) 이름으로만 봅니다 — 예전 동작. */
  if (state && state !== 'Running') {
    return { bin: bin, name: null, state: state,
      why: BACKEND_WHY[state] || ('Tailscale 이 아직 준비되지 않았습니다 (' + state.slice(0, 40) + ')') };
  }
  const dns = String((j.Self && j.Self.DNSName) || '').replace(/\.$/, '');
  if (!dns) {
    return { bin: bin, name: null,
      why: 'Tailscale 은 도는데 이 기기 이름이 없습니다 — 로그인이 끝났는지 보세요.' };
  }
  return { bin: bin, name: dns, why: null };
}

/** tailscaleState 와 같은 답을 **기다리지 않고** 받습니다 (Promise).
 *
 * 준비를 기다리는 동안 몇 초마다 묻는데, spawnSync 로 물으면 tailscale 이
 * 대답을 안 하는 동안(부팅 직후에 흔합니다) 이 프로세스가 최대 8초 통째로
 * 멈춥니다. 그 사이 Ctrl+C · 작업 끝내기가 안 먹습니다. 그래서 여기서는
 * 따로 띄워서 묻고, 묻는 중인 자식은 KIDS.poll 에 걸어 둡니다 — 끌 때
 * 같이 끕니다. */
function tailscaleStateLater() {
  return new Promise(resolve => {
    const bin = findBin('tailscale');
    if (!bin) return resolve(tailscaleMissing());
    let stdout = '', stderr = '', done = false, t = null;
    let ch;
    const finish = status => {
      if (done) return;
      done = true;
      clearTimeout(t);
      if (KIDS.poll === ch) KIDS.poll = null;
      resolve(readTailscale(bin, { status: status, stdout: stdout, stderr: stderr }));
    };
    try {
      ch = spawn(bin, ['status', '--json'], { stdio: ['ignore', 'pipe', 'pipe'], windowsHide: true });
    } catch (e) {
      return resolve(readTailscale(bin, { status: null, stdout: '', stderr: String(e.message || e) }));
    }
    KIDS.poll = ch;
    t = setTimeout(() => { try { ch.kill(); } catch (e) {} finish(null); }, 8000);
    ch.stdout.on('data', d => { stdout += d; });
    ch.stderr.on('data', d => { stderr += d; });
    ch.on('error', e => { stderr += String(e.message || e); finish(null); });
    ch.on('close', code => finish(code));
  });
}

/** 이 컴퓨터가 **Tailscale 주소에 묶여 있는가.**
 *
 * 설정의 origin 이 https://….ts.net 이면 친구들 폰에 깔린 앱과 기록이
 * 전부 그 주소에 붙어 있습니다. 그런 컴퓨터가 Cloudflare 로 넘어가면
 * "터널이 열렸다" 는 말과 함께 **아무도 모르는 새 주소**가 생기고, 원래
 * 주소는 그대로 죽어 있습니다 — 터널이 없는 것보다 나쁩니다. 없으면
 * 적어도 사람이 이상한 줄은 압니다.
 * --tailscale 을 붙여도 같은 뜻으로 봅니다. --cloudflare 는 사람이 일부러
 * 바꾸는 것이라 묶지 않습니다.
 *
 * origin 하나로만 보면 안 됩니다. origin 은 **마지막으로 연 터널 주소**라서
 * --cloudflare 로 한 번 띄우면 trycloudflare 주소로 덮이고, 그 다음 부팅부터
 * 이 컴퓨터는 "안 묶인 컴퓨터" 가 되어 Tailscale 이 늦을 때 다시 조용히
 * Cloudflare 로 넘어갑니다 — 고치려던 사고 그대로입니다. 게다가 funnel 이
 * 안 열릴 때 이 스크립트가 바로 그 --cloudflare 를 권했습니다.
 * 그래서 Tailscale 로 연 주소는 tailscaleOrigin 에 **따로** 적어 둡니다
 * (announceUrl). Cloudflare 로 띄워도 이 값은 안 지웁니다. 정말 Tailscale 을
 * 그만 쓸 거면 설정 파일에서 tailscaleOrigin 을 지우거나, 늘 --cloudflare
 * 로 띄우면 됩니다.
 * 돌려주는 값: 'origin' · 'flag' (묶임, 무엇 때문인지) · '' (안 묶임) */
function tsUrl(v) {
  try {
    const u = new URL(String(v || '').trim());
    if (u.protocol === 'https:' && /\.ts\.net$/i.test(u.hostname)) return u.origin;
  } catch (e) {}
  return '';
}
/** 이 컴퓨터가 묶여 있는 ts.net 주소. 지금 origin 이 먼저, 없으면 기억해 둔 것. */
function tailscaleHome(cfg) {
  return tsUrl(cfg && cfg.origin) || tsUrl(cfg && cfg.tailscaleOrigin);
}
function committedToTailscale(cfg) {
  if (has('cloudflare')) return '';
  if (tailscaleHome(cfg)) return 'origin';
  return has('tailscale') ? 'flag' : '';
}
/** main 에서 한 번 정합니다. 안내 문구가 "--cloudflare 로 가 보라" 를 해도
 *  되는지 여기서 봅니다(suggestCloudflare). */
let COMMITTED = '';

/** "지금 당장 쓰려면 --cloudflare" — ts.net 주소에 묶인 컴퓨터에는 안 합니다.
 *  거기서 그 말을 따르면 공개 주소가 바뀌고, 친구들 앱은 옛 주소를 붙든 채
 *  안 열립니다. installHint(true) 가 ② 를 빼는 것과 같은 까닭입니다. */
function suggestCloudflare(lines) {
  if (!COMMITTED) lines.forEach(l => line(l));
}

/** 어떤 터널을 쓸 것인가. { kind, name, bin } 또는 null
 *  committed 이고 Tailscale 이 아직이면 { kind: 'tailscale', pending: true, why } */
function findTunnel(committed) {
  if (!has('cloudflare')) {
    const ts = tailscaleState();
    if (ts.name) return { kind: 'tailscale', name: ts.name, bin: ts.bin };
    /* 이 컴퓨터가 ts.net 주소로 쓰이고 있으면 **기다립니다.**
     *
     * 노트북 보고 48 (2026-09-30): 충전기가 빠져 절전 → 비정상 종료 →
     * 14:47 부팅. 작업 스케줄러가 30초 뒤 이 스크립트를 띄웠는데 Tailscale
     * 이 아직 덜 떠서 "기기 이름이 없다" 였고, 여기서 그냥 지나갔습니다.
     * 서버는 떴는데 공개 주소는 14:59 에 사람이 다시 띄울 때까지 죽어
     * 있었습니다. 그 컴퓨터에 cloudflared 까지 있었다면 더 나빴습니다 —
     * 아무도 모르는 trycloudflare 주소가 열리고 설정의 origin 까지 그걸로
     * 덮였을 겁니다.
     *
     * 부팅 직후 Tailscale 이 늦는 것은 고장이 아니라 순서 문제입니다.
     * 그러니 넘어가지 말고 기다립니다 (아래 6-3). */
    if (committed) {
      return { kind: 'tailscale', name: null, bin: ts.bin, pending: true, why: ts.why };
    }
    /* 왜 안 썼는지 말합니다. 조용히 cloudflared 로 넘어가면, 주인은
       Tailscale 을 깔아 놓고도 계속 바뀌는 주소를 받으면서 이유를
       모릅니다 — 실제로 그렇게 됐습니다. */
    tunnelNote = ts.why;
  }
  const cf = findBin('cloudflared');
  if (cf) return { kind: 'cloudflared', name: null, bin: cf };
  return null;
}

function installHint(tailscaleOnly) {
  /* 두 길을 다 보여 주되, **주소가 안 바뀌는 쪽을 먼저** 적습니다.
     빠른 길만 알려 주면 나중에 반드시 다시 옵니다 — 주소가 바뀌어서.
     ts.net 주소에 묶인 컴퓨터(tailscaleOnly)에는 ① 만 보여 줍니다 —
     거기서 ② 를 고르면 주소가 바뀌어 친구들 기록이 안 보이게 됩니다. */
  const ts = process.platform === 'darwin'
    /* brew 로 깔면 tailscaled 를 서비스로 켜야 up 이 붙을 데가 있습니다.
       이 방식은 로그인 없이도 돌아서 상시 서버에 맞습니다(docs/MAC.md). */
    ? '    brew install tailscale && sudo brew services start tailscale && sudo tailscale up'
    : process.platform === 'win32'
      ? '    winget install --id tailscale.tailscale\n' +
        '    그다음 트레이의 Tailscale 에서 로그인하세요 (개인 계정 무료)'
      : '    curl -fsSL https://tailscale.com/install.sh | sh && sudo tailscale up';
  const cf = process.platform === 'darwin'
    ? '    brew install cloudflared'
    : process.platform === 'win32'
      ? '    winget install --id Cloudflare.cloudflared'
      : '    curl -L -o cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64\n' +
        '    chmod +x cloudflared && sudo mv cloudflared /usr/local/bin/';
  const first = [
    '① 주소가 안 바뀌는 길 (추천) — Tailscale, 개인 무료',
    ...ts.split('\n'),
    '   주소: https://<기기이름>.<테일넷>.ts.net  — 껐다 켜도 그대로입니다.',
    '   크롬이 막지 않아서 **폰에 앱으로 깔 수 있습니다.**'
  ];
  if (tailscaleOnly) return first;
  return [
    ...first,
    '',
    '② 빨리 한 번 보는 길 — Cloudflare, 계정 없이 30초',
    ...cf.split('\n'),
    '   주소가 띄울 때마다 바뀌고, 크롬이 앱 설치를 막습니다.'
  ];
}

/* --- 1~4. 준비 ------------------------------------------------------------ */
function prepare() {
  let { cfg } = CONFIG.load();

  /* 주인이 정한 두 가지를 여기서 설정에 박습니다.
     설정 파일은 이 컴퓨터에만 있고 git 에 안 들어갑니다. 그래서
     "어떻게 띄울지" 는 설정이 아니라 **이 스크립트** 가 알아야
     합니다 — 안 그러면 새 컴퓨터에서 처음 띄울 때 조용히 예전
     기본값으로 돌아갑니다. */
  const wantOpen = !has('pair-code');
  const wantAlwaysOn = !has('not-always-on');

  if (!cfg.pairSecret) {
    line('설정이 없어서 만듭니다 (한 번만 합니다)');
    const setupArgs = ['--setup', '--no-owner',
                       wantOpen ? '--open-signup' : '--close-signup'];
    if (wantAlwaysOn) setupArgs.push('--always-on');
    const r = run('serve.js', setupArgs);
    process.stdout.write(r.stdout || '');
    if (r.status !== 0) { process.stderr.write(r.stderr || ''); process.exit(1); }
    cfg = CONFIG.load().cfg;
  } else if (!!cfg.openSignup !== wantOpen || !!cfg.alwaysOn !== wantAlwaysOn) {
    /* 이미 설정이 있는 컴퓨터에서 마음을 바꿔 다시 띄울 때.
       설정을 처음 만들 때만 반영하면, 이미 설정이 있는 컴퓨터에서는
       --pair-code 를 붙여도 아무것도 안 바뀝니다. 켜는 쪽만 반영하면
       되돌리는 깃발이 조용히 먹통이 되므로 양쪽 다 따라갑니다. */
    const was = !!cfg.openSignup;
    cfg.openSignup = wantOpen;
    cfg.alwaysOn = wantAlwaysOn;
    try { CONFIG.save(cfg); } catch (e) {}
    cfg = CONFIG.load().cfg;
    if (was !== wantOpen) {
      line(wantOpen ? '가입을 열었습니다 (코드 없이 가입)'
                    : '가입을 닫았습니다 (코드가 필요합니다)');
    }
  }

  if (!cfg.vapidPublic || !cfg.vapidPrivate) {
    line('폰 알림 열쇠를 만듭니다 (한 번만 합니다)');
    const r = run('push-keys.js');
    if (r.status !== 0) { process.stdout.write(r.stdout || ''); process.stderr.write(r.stderr || ''); }
    cfg = CONFIG.load().cfg;
  }
  return cfg;
}

/* --- 6. 터널에서 주소 뽑기 ------------------------------------------------
 * cloudflared 는 주소를 **stderr** 로 찍습니다. stdout 만 보면 영원히
 * 안 옵니다 — 처음 짤 때 여기서 30분을 썼습니다.
 * -------------------------------------------------------------------------- */
function startTunnel(tunnel, port, onUrl, opts) {
  /* opts.quiet  — 다시 붙이는 중입니다(6-3). tailscale 이 하는 말을 줄마다
                   찍지 않고, 죽어도 긴 설명을 다시 하지 않습니다. 그 설명은
                   처음 한 번이면 충분하고, 60초마다 같은 열 줄이 쌓이면
                   정작 새로운 줄이 묻힙니다.
     opts.onExit — 내가 끄는 게 아닌데 죽었을 때 (code, { found, last }). */
  opts = opts || {};
  const quiet = !!opts.quiet;
  const isTs = tunnel.kind === 'tailscale';
  const child = isTs
    /* funnel 은 443·8443·10000 에서만 받습니다. 기본 443 으로 두고
       안쪽 포트만 넘깁니다. --bg 를 안 붙이는 이유: 이 창을 닫으면
       터널도 같이 꺼져야 합니다. 붙이면 서버만 죽고 주소는 살아남아
       "열려 있는데 아무것도 없는 주소" 가 됩니다. */
    ? spawn(tunnel.bin || 'tailscale', ['funnel', String(port)],
            { cwd: ROOT, stdio: ['ignore', 'pipe', 'pipe'], windowsHide: true })
    : spawn(tunnel.bin || 'cloudflared',
            ['tunnel', '--no-autoupdate', '--url', 'http://localhost:' + port],
            { cwd: ROOT, stdio: ['ignore', 'pipe', 'pipe'], windowsHide: true });

  let found = false;
  let alive = true;
  let out = '';
  const RE = isTs ? /https:\/\/[a-z0-9-]+\.[a-z0-9.-]+\.ts\.net/i
                  : /https:\/\/[a-z0-9-]+\.trycloudflare\.com/i;
  const scan = buf => {
    out += String(buf);
    /* verifyUrl 이 "tailscale 이 준 켜는 링크" 를 찾을 때 이걸 봅니다.
       예전에는 거기서 이 함수 안의 out 을 그냥 불러서, 확인이 끝내
       실패하면 안내 전체가 ReferenceError 로 조용히 사라졌습니다. */
    tunnel.said = out;
    /* **tailscale 이 하는 말은 그대로 보여 줍니다.**
     *
     * 예전에는 전부 모아 두고 프로세스가 죽을 때만 찍었습니다. 그런데
     * Funnel 이 아직 안 켜진 테일넷에서는 tailscale 이 **죽지 않고**
     * "여기서 켜세요: https://login.tailscale.com/f/funnel?node=…" 를
     * 찍은 채로 기다립니다. 그 링크가 우리 버퍼 안에서 사라졌습니다 —
     * 주인은 "Funnel 어떻게 켜?" 를 물어야 했고, 답은 화면에 이미
     * 와 있었습니다.
     *
     * cloudflared 는 수다스러워서(연결 로그가 계속 나옵니다) 안 찍고,
     * 죽을 때만 마지막 몇 줄을 보여 줍니다. tailscale 은 몇 줄뿐입니다. */
    if (isTs && !quiet) {
      String(buf).split('\n').forEach(l => {
        const t = l.trim();
        if (t) line('  tailscale: ' + t);
      });
    }
    const m = RE.exec(String(buf));
    if (m && !found && !QUITTING.now) { found = true; onUrl(m[0].replace(/\/$/, '')); }
  };
  child.stdout.on('data', scan);
  child.stderr.on('data', scan);

  /* tailscale 은 이미 이름을 알고 있습니다 — 굳이 출력에서 긁어내지
     않아도 됩니다. 출력 형식이 바뀌어도 여기서 안 막히게 해 둡니다.
     다만 **프로세스가 아직 살아 있을 때만** 씁니다. 죽은 뒤에 이름만
     보고 주소를 찍으면, 안 열리는 주소를 자신 있게 알려 주게 됩니다 —
     주인이 실제로 그 주소를 받고 "안 들어가진다" 고 했습니다. */
  if (isTs && tunnel.name) {
    later(() => {
      if (!found && alive) { found = true; onUrl('https://' + tunnel.name); }
    }, 2500);
  }

  /* 'error'(실행 파일이 사라졌다 등)와 'exit' 는 둘 다 올 수도, 하나만
     올 수도 있습니다. 한 번만 처리합니다. 'error' 를 안 받아 두면 노드가
     "처리 안 된 오류" 로 이 프로세스를 — 서버째로 — 끝냅니다. 다시 붙이는
     동안 tailscale 이 업데이트되며 잠깐 사라지는 일은 충분히 있습니다. */
  let ended = false;
  const onEnd = code => {
    if (ended) return;
    ended = true;
    alive = false;
    /* 내가 끄는 중이면 아무 말도 안 합니다. 사용자가 Ctrl+C 를 눌렀는데
       "터널이 끊겼습니다" 가 뜨면 고장으로 읽힙니다. */
    if (QUITTING.now) return;
    const said = out.trim().split('\n').map(l => l.trim()).filter(l => l);
    const info = { found: found, last: said.length ? said[said.length - 1] : '' };
    if (quiet) { if (opts.onExit) opts.onExit(code, info); return; }
    line('');
    /* found 여도 말해야 합니다. 주소를 이미 찍은 뒤에 터널이 죽으면,
       그 주소는 이제 거짓입니다. 조용하면 사람은 주소를 의심하지 않고
       자기 폰을 의심합니다. */
    line(found ? '터널이 끊겼습니다 (종료 코드 ' + code + '). 위 주소는 이제 안 됩니다.'
               : '터널이 주소를 못 만들고 끝났습니다 (종료 코드 ' + code + ').');
    if (isTs) {
      /* Funnel 은 테일넷 정책에서 한 번 켜 줘야 합니다. 처음 쓰는
         사람은 여기서 막히는데, tailscale 이 그 링크를 출력에 적어
         줍니다 — 그걸 그대로 보여 주는 편이 제 설명보다 정확합니다. */
      const hint = (out.match(/https:\/\/login\.tailscale\.com\S*/) || [])[0];
      const last4 = said.slice(-4);
      if (last4.length) { line('tailscale 이 한 말:'); last4.forEach(l => line('  ' + l)); }
      if (hint) { line(''); line('여기서 한 번 켜 주세요:'); line('  ' + hint); }
      else if (!found) {
        /* 주소까지 받았다가 죽은 것이면 Funnel 설정 문제가 아닙니다 —
           절전 · 재시작으로 tailscale 이 잠깐 내려간 쪽입니다. 그때
           "Funnel 을 켜세요" 를 찍으면 멀쩡한 설정을 뒤지게 됩니다. */
        line('');
        line('Funnel 이 이 테일넷에서 아직 안 켜져 있을 수 있습니다:');
        line('  https://login.tailscale.com/admin/settings/keys 가 아니라');
        line('  https://login.tailscale.com/admin/acls 의 nodeAttrs 에 funnel 이 필요합니다.');
        line('  (관리자 화면에서 Funnel 을 켜면 자동으로 들어갑니다)');
      }
      if (!found) suggestCloudflare(['그래도 안 되면 Cloudflare 로:  node tools/launch.js --cloudflare']);
    } else {
      line('인터넷이 막혀 있거나 cloudflared 가 차단됐을 수 있습니다.');
    }
    line('서버 자체는 그대로 돌고 있습니다 — 같은 와이파이에서는 쓸 수 있습니다.');
    if (opts.onExit) opts.onExit(code, info);
  };
  child.on('exit', code => onEnd(code));
  child.on('error', e => {
    if (!out) out = String((e && e.message) || e) + '\n';
    onEnd(null);
  });
  return child;
}

/* --- 6-2. 그 주소가 **진짜로 열리는가** ------------------------------------
 *
 * 주소를 찍었다는 것과 그 주소가 열린다는 것은 다릅니다. 주인이 그
 * 사이에서 막혔습니다 — 예쁜 상자에 담긴 주소를 받았는데 폰에서 안
 * 열렸고, 화면은 아무 말도 안 했습니다.
 *
 * 그래서 우리가 직접 두드려 봅니다. 첫 실행이면 Tailscale 이 인증서를
 * 받아 오느라 30초~1분 걸릴 수 있어서, 한 번 실패로 단정하지 않고
 * 그 동안 기다립니다.
 * -------------------------------------------------------------------------- */
/* 얼마나 기다릴 것인가. 첫 실행이면 Tailscale 이 인증서를 받아 오느라
   30초~1분 걸립니다. 검사에서는 1분을 기다릴 수 없어서 줄일 수 있게
   열어 둡니다 (RATE_MAX · OCR_PER_DAY 와 같은 방식). */
const VERIFY_TRIES = Number(process.env.MYBODY_VERIFY_TRIES || 12);
const VERIFY_GAP = Number(process.env.MYBODY_VERIFY_GAP || 5000);

/* 이 주소가 **바깥 세상의 DNS 에도 있는가.**
 *
 * 이게 없어서 제가 거짓말을 했습니다. 확인을 이 컴퓨터에서 하는데,
 * Tailscale 이 깔린 컴퓨터는 <기기>.<테일넷>.ts.net 을 **자기 안에서**
 * 풉니다(MagicDNS). 그래서 funnel 이 공개되지 않았는데도 "✓ 실제로
 * 들어와집니다" 가 떴고, 주인은 그 말을 믿고 폰을 꺼냈다가
 * DNS_PROBE_FINISHED_NXDOMAIN 을 봤습니다.
 *
 * 시스템 해석기를 쓰지 않고 공개 DNS 서버에 직접 묻습니다. 그게
 * 친구 폰이 보는 세상입니다. */
function publicDns(host) {
  return new Promise(resolve => {
    let R;
    try {
      R = new (require('node:dns').Resolver)();
      R.setServers(['1.1.1.1', '8.8.8.8']);
    } catch (e) { return resolve({ known: false }); }
    let left = 2, found = false, errs = 0;
    const done = () => { if (--left === 0) resolve({ known: errs < 2, found: found }); };
    const ask = (fn) => {
      try {
        fn.call(R, host, (err, addrs) => {
          if (!err && addrs && addrs.length) found = true;
          else if (err && !/ENODATA|ENOTFOUND|NOTFOUND/.test(String(err.code))) errs++;
          done();
        });
      } catch (e) { errs++; done(); }
    };
    ask(R.resolve4); ask(R.resolve6);
    setTimeout(() => resolve({ known: errs < 2, found: found }), 6000);
  });
}

function verifyUrl(url, tunnel, tries) {
  tries = tries || 0;
  const MAX = VERIFY_TRIES;
  if (QUITTING.now) return Promise.resolve(false);
  return fetch(url + '/health', { redirect: 'follow' })
    .then(r => r.ok ? r.json().catch(() => null) : null)
    .then(j => {
      if (!(j && j.ok)) throw new Error('우리 서버가 아닌 답');
      /* 여기까지는 **이 컴퓨터에서** 열린다는 뜻뿐입니다.
         친구 폰이 보는 세상은 공개 DNS 입니다. 그걸 따로 봅니다. */
      let host = '';
      try { host = new URL(url).hostname; } catch (e) {}
      return publicDns(host).then(dnsOk => {
        if (!dnsOk.known) {
          line('✓ 이 컴퓨터에서는 열립니다.');
          line('  (바깥 DNS 는 확인하지 못했습니다 — 폰에서 한번 열어 보세요.)');
          line('');
          return true;
        }
        if (dnsOk.found) {
          /* ts.net 은 이 컴퓨터에서 부르면 테일넷 안으로 가서 funnel 의 공개
             중계를 **안 거칩니다.** 노트북에서 세 번(9/24 · 9/29 · 9/30) 여기는
             열리는데 바깥은 중계 한 대가 "Broken pipe" 였습니다. 그러니
             Tailscale 이면 "실제로 들어와진다" 고 말하지 않습니다.
             cloudflared 는 이 컴퓨터에서도 바깥 가장자리를 돌아 들어오므로
             그 말이 맞습니다. */
          if (tunnel.kind === 'tailscale') {
            line('✓ 이 컴퓨터(테일넷)에서 열리고, 바깥 DNS 에도 있습니다.');
            line('  바깥 중계까지는 여기서 확인 못 합니다 — 폰(와이파이 끄고)에서 열어 보세요.');
          } else {
            line('✓ 이 주소로 실제로 들어와집니다 — 바깥 DNS 에도 있습니다.');
            line('  폰에서 열어 보세요.');
          }
          line('');
          return true;
        }
        line('');
        line('⚠ 이 컴퓨터에서는 열리는데 **밖에서는 아직 안 됩니다.**');
        line('  ' + host + ' 이 공개 DNS 에 아직 없습니다.');
        line('  폰에서 열면 "사이트에 연결할 수 없음 · DNS_PROBE_FINISHED_NXDOMAIN"');
        line('  이 뜹니다. 이 컴퓨터는 Tailscale 이 자기 안에서 풀어 주기 때문에');
        line('  열리는 것뿐입니다.');
        if (tunnel.kind === 'tailscale') {
          line('');
          line('  남은 것은 하나입니다 — 테일넷 정책에 Funnel 권한 주기.');
          line('  ① https://login.tailscale.com/admin/acls 로 갑니다.');
          line('  ② 왼쪽 메뉴에서 Access controls → **JSON editor** 를 누릅니다.');
          line('     (첫 화면 Policies 에는 그 칸이 없습니다)');
          line('  ③ "acls" 블록 다음에 이것을 넣고 Save:');
          line('');
          line('       "nodeAttrs": [');
          line('         {"target": ["autogroup:member"], "attr": ["funnel"]},');
          line('       ],');
          line('');
          line('  ④ 이 창을 끄고 node tools/launch.js 를 다시 치세요.');
          line('     공개 DNS 에 뜨기까지 1~2분 더 걸릴 수 있습니다.');
        }
        suggestCloudflare(['', '  지금 당장 쓰려면:  node tools/launch.js --cloudflare']);
        return false;
      });
    })
    .catch(() => {
      if (QUITTING.now) return false;
      if (tries < MAX) {
        if (tries === 2) {
          line('… 주소가 아직 안 열립니다. 첫 실행이면 인증서를 받느라');
          line('  30초~1분 걸립니다. 기다리는 중…');
        }
        return new Promise(r => setTimeout(r, VERIFY_GAP)).then(() => verifyUrl(url, tunnel, tries + 1));
      }
      line('');
      line('⚠ 이 주소가 안 열립니다. 지금 폰에서 열어도 안 됩니다.');
      if (tunnel.kind === 'tailscale') {
        const st = spawnSync(tunnel.bin || 'tailscale', ['funnel', 'status'],
                             { encoding: 'utf8', timeout: 8000, windowsHide: true });
        const said = ((st.stdout || '') + (st.stderr || '')).trim();
        if (said) { line(''); line('tailscale funnel status:');
                    said.split('\n').slice(0, 10).forEach(l => line('  ' + l)); }
        line('');
        if (/No serve config/i.test(said)) {
          line('"No serve config" — funnel 이 아무것도 등록하지 못했습니다.');
          line('거의 언제나 **테일넷에서 Funnel 이 안 켜져 있어서** 입니다.');
          line('');
        }
        /* tailscale 이 켜는 링크를 줬으면 그게 제일 빠릅니다. */
        const link = (String(tunnel.said || '').match(/https:\/\/login\.tailscale\.com\/f\/funnel\S*/) || [])[0];
        if (link) {
          line('이 링크를 눌러 한 번 켜 주세요 (tailscale 이 준 링크입니다):');
          line('  ' + link);
          line('');
        }
        line('손으로 켜려면 두 군데입니다:');
        line('');
        line('  ① https://login.tailscale.com/admin/acls');
        line('     왼쪽 메뉴에서 Access controls → **JSON editor** 를 누르세요.');
        line('     (Policies 화면에는 Funnel 칸이 없습니다 — 거긴 접속 규칙만입니다)');
        line('     열린 JSON 안, "acls" 블록 **다음에** 이걸 넣고 Save:');
        line('');
        line('       "nodeAttrs": [');
        line('         {"target": ["autogroup:member"], "attr": ["funnel"]},');
        line('       ],');
        line('');
        line('  ② https://login.tailscale.com/admin/dns');
        line('     **MagicDNS** 와 **HTTPS Certificates** 를 둘 다 켜세요.');
        line('');
        line('  그다음 이 창을 끄고 node tools/launch.js 를 다시 치세요.');
        suggestCloudflare(['', '지금 당장 쓰려면:  node tools/launch.js --cloudflare',
                           '  (주소가 바뀌고 앱 설치는 안 되지만, 열리기는 합니다)']);
      } else {
        line('cloudflared 가 주소를 만들었지만 아직 연결이 안 됐습니다.');
        line('잠시 뒤 다시 열어 보세요. 계속 안 되면 서버를 끄고 다시 띄우세요.');
      }
      line('');
      return false;
    });
}

/* --- 6-3. Tailscale 을 **기다리고, 끊기면 다시 붙이기** ----------------------
 *
 * 노트북 보고 48 (2026-09-30). 서버 컴퓨터는 주인의 윈도우 노트북이고,
 * 작업 스케줄러 「Mybody 서버」 가 로그온 30초 뒤 창 없이 이 스크립트를
 * 띄웁니다. 그날 충전기가 빠져 절전 → 비정상 종료 → 14:47 부팅. 서버는
 * 떴는데 Tailscale 이 아직 덜 떠서 funnel 을 건너뛰었고, 공개 주소는 14:59
 * 에 사람이 작업을 다시 띄울 때까지 죽어 있었습니다. 창도 사람도 없는
 * 컴퓨터라 "다시 치세요" 라고 말해 봐야 들을 사람이 없습니다.
 *
 * 그래서 두 가지를 스스로 합니다.
 *
 *   기다리기    Tailscale 이 준비될 때까지 물어봅니다. 처음 2분은 5초마다
 *               (부팅 직후는 대개 1분 안에 붙습니다), 그 뒤로는 30초마다,
 *               서버가 살아 있는 한 계속. "스스로 끝내고 작업 스케줄러가
 *               다시 띄우게" 하는 길도 있었지만, 그 작업은 1분 간격으로
 *               세 번만 다시 띄우고 포기합니다 — 3분 넘게 늦는 날은 그대로
 *               끝입니다. 그리고 끝낼 때마다 서버도 같이 내려가서, 같은
 *               와이파이로 쓰던 사람까지 끊깁니다.
 *   다시 붙이기  funnel 이 도중에 죽으면(절전에서 깨어남 · tailscale 재시작)
 *               5초 → 10초 → 20초 → 40초 → 60초 간격으로 다시 띄웁니다.
 *               2분 넘게 버티다 죽은 것이면 새 사고로 보고 5초부터 다시.
 *
 * 로그는 %USERPROFILE%\mybody.log 한 파일로 가고 회전이 없습니다. 물을
 * 때마다 한 줄씩 찍으면 하루에 수천 줄이 쌓여 정작 볼 줄이 묻힙니다.
 * 그래서 기다리는 동안은 5분에 한 줄, 다시 붙이기가 60초 간격에 닿은
 * 뒤로도 5분에 한 줄만 찍습니다. "다시 붙음" 줄도 같은 한도를 탑니다.
 * 기다리는 줄에는 지금 이유를 같이 적어서, 부팅 중인지(켜지는 중) 사람이
 * 필요한지(로그인 · Connect — "저절로 안 풀립니다")를 로그만 보고 가릅니다.
 *
 * cloudflared 는 다시 붙이지 않습니다 — 띄울 때마다 주소가 바뀌니, 조용히
 * 다시 붙이면 아무도 모르는 새 주소가 하나 더 생길 뿐입니다.
 *
 * 시험에서는 몇 분을 기다릴 수 없어서 두 값으로 전부 줄일 수 있게 열어
 * 둡니다 (MYBODY_VERIFY_TRIES 와 같은 방식). 나머지는 이 두 값의 배수라,
 * 줄여도 "처음엔 촘촘히, 나중엔 드문드문" 의 모양은 그대로입니다.
 * -------------------------------------------------------------------------- */
function envMs(name, def) {
  const n = Number(process.env[name]);
  /* 0 이나 엉뚱한 값이면 기본값 — 0 이면 쉬지 않고 도는 고리가 됩니다.
     위로도 막습니다(1분). 아래 값들은 이것의 60배까지 곱해지는데, 너무 크면
     노드가 setTimeout 을 1ms 로 바꿔서 역시 쉬지 않는 고리가 됩니다(later). */
  return Number.isFinite(n) && n >= 100 && n <= 60000 ? n : def;
}
const TS_POLL = envMs('MYBODY_TS_POLL_MS', 5000);       // 처음엔 5초마다 묻고
const TS_POLL_SLOW = TS_POLL * 6;                       // 2분 뒤로는 30초마다
const TS_POLL_FAST_FOR = TS_POLL * 24;                  // 촘촘히 묻는 시간 2분
const TS_SAY_EVERY = TS_POLL * 60;                      // "아직 기다리는 중" 은 5분에 한 줄
const TS_BACKOFF = envMs('MYBODY_TS_BACKOFF_MS', 5000); // 다시 붙이기 첫 간격 5초
const TS_BACKOFF_MAX = TS_BACKOFF * 12;                 // 두 배씩 늘다가 60초에서 멈춤
const TS_STABLE = TS_BACKOFF * 24;                      // 2분 버텼으면 간격을 처음부터
const TS_QUIET = TS_BACKOFF * 60;                       // 60초 간격에 닿으면 5분에 한 줄

/** 사람이 읽는 시간 — "0.3초", "40초", "12분" */
function dur(ms) {
  if (ms < 1000) return (Math.round(ms / 100) / 10) + '초';
  const s = Math.round(ms / 1000);
  return s < 60 ? s + '초' : Math.floor(s / 60) + '분';
}

/** Tailscale 이 준비될 때까지 묻다가, 되면 ready({ kind, name, bin }) 를 부릅니다.
 *  서버가 살아 있는 한 포기하지 않습니다 — 끝나는 길은 QUITTING 하나입니다. */
function waitForTailscale(ready) {
  const since = Date.now();
  let saidAt = since;
  const tick = () => {
    tailscaleStateLater().then(ts => {
      if (QUITTING.now) return;
      if (ts.name) {
        line('');
        line('Tailscale 준비됨 — ' + dur(Date.now() - since) + ' 기다렸습니다. 주소를 엽니다.');
        ready({ kind: 'tailscale', name: ts.name, bin: ts.bin });
        return;
      }
      /* 이유가 바뀌었을 수도 있어서(안 깔림 → 로그인 필요) 지금 이유를 같이 적습니다. */
      const now = Date.now();
      if (now - saidAt >= TS_SAY_EVERY) {
        saidAt = now;
        line('아직 기다리는 중 (' + dur(now - since) + ') — ' + ts.why);
      }
      later(tick, now - since < TS_POLL_FAST_FOR ? TS_POLL : TS_POLL_SLOW);
    }).catch(() => later(tick, TS_POLL_SLOW));
  };
  later(tick, TS_POLL);
}

/** funnel 을 띄우고, 내가 끄는 게 아닌데 죽으면 간격을 늘려 가며 다시 띄웁니다.
 *  announce(tunnel, url) — 상자 · 설정 · 확인. 주소를 처음 받았을 때만 부릅니다
 *  (다시 붙을 때마다 상자를 또 찍으면, 로그만 보는 사람은 주소가 바뀐 줄 압니다).
 *  주소가 정말 바뀌었으면(기기 이름을 바꿨다 등) 그때는 다시 부릅니다. */
function keepFunnel(first, port, announce) {
  let born = 0;              // 지금 funnel 을 띄운 시각
  let step = 0;              // 간격 단계: 5 → 10 → 20 → 40 → 60초
  let told = false;          // 첫 고장의 긴 설명을 이미 했는가
  let shown = null;          // 상자에 담아 준 주소
  let downAt = 0;            // 끊긴 시각 — 다시 붙으면 얼마나 끊겼는지 적습니다
  let downSaid = false;      // 이번 끊김을 로그에 적었는가 — 적은 것만 "다시 붙음" 으로 닫습니다
  let saidAt = 0, held = 0;  // 짧은 줄을 5분에 한 번으로 줄이는 데 씁니다

  const nextWait = () => {
    const w = Math.min(TS_BACKOFF * Math.pow(2, step), TS_BACKOFF_MAX);
    step++;
    return w;
  };
  /* 60초 간격에 닿은 뒤로는 5분에 한 줄 — 그 사이 몇 번이었는지는 같이 적습니다.
     찍었으면 true. */
  const say = (text, atMax) => {
    const now = Date.now();
    if (atMax && now - saidAt < TS_QUIET) { held++; return false; }
    line(text + (held ? ' (그 사이 ' + held + '번 더)' : ''));
    saidAt = now; held = 0;
    return true;
  };

  const retry = () => {
    tailscaleStateLater().then(ts => {
      if (QUITTING.now) return;
      if (ts.name) return open({ kind: 'tailscale', name: ts.name, bin: ts.bin });
      const wait = nextWait();
      if (say('Tailscale 이 아직 안 돌아왔습니다 — ' + ts.why + ' · ' + dur(wait) + ' 뒤 다시',
              wait >= TS_BACKOFF_MAX)) downSaid = true;
      later(retry, wait);
    }).catch(() => later(retry, TS_BACKOFF_MAX));
  };

  const open = t => {
    born = Date.now();
    KIDS.tunnel = startTunnel(t, port, url => {
      /* 붙을 때마다 중계를 다시 잡습니다(6-4). 5분에 한 번까지. */
      later(() => kickRelays(t.bin), TS_BACKOFF);
      if (shown === url) {
        /* "다시 붙음" 도 끊김 줄과 같은 한도를 탑니다. 2분을 못 버티고 죽기를
           되풀이하는 funnel 이면, 끊김 줄은 5분에 한 번인데 이 줄만 1분마다
           쌓여 하루 1,400줄이 됩니다. 로그에 적은 끊김만 이 줄로 닫고, 줄여서
           안 적은 끊김은 다음 끊김 줄의 "(그 사이 N번 더)" 가 셉니다. */
        if (downSaid) {
          line('터널 다시 붙음 — ' + url + (downAt ? ' (' + dur(Date.now() - downAt) + ' 끊겼음)' : ''));
        }
        downAt = 0; downSaid = false;
        return;
      }
      shown = url;
      downAt = 0; downSaid = false;
      announce(t, url);
    }, { quiet: told, onExit: (code, info) => {
      if (Date.now() - born >= TS_STABLE) step = 0;
      if (!downAt) downAt = Date.now();
      const wait = nextWait();
      if (!told) {
        /* 긴 설명(tailscale 이 한 말 · 켜는 링크)은 startTunnel 이 방금 찍었습니다. */
        told = true;
        downSaid = true;
        saidAt = Date.now();
        line(dur(wait) + ' 뒤 다시 붙여 봅니다 — Tailscale 이 돌아오면 저절로 다시 열립니다.');
      } else if (say('터널이 또 끊겼습니다 (종료 코드 ' + code +
                     (info.last ? ' · ' + info.last.slice(0, 80) : '') + ') — ' + dur(wait) + ' 뒤 다시 붙입니다',
                     wait >= TS_BACKOFF_MAX)) {
        downSaid = true;
      }
      later(retry, wait);
    } });
  };
  open(first);
}

/* --- 6-4. funnel 이 붙은 뒤 **중계를 한 번 다시 잡기** ----------------------
 *
 * funnel 은 바깥에서 공개 중계(두 대)를 거쳐 들어옵니다. 노트북에서 세 번
 * — 9/24(와이파이가 바뀐 뒤) · 9/29 13:18 재시작 · 9/30 14:59 재시작(보고 48)
 * — funnel 은 떴고 이 컴퓨터에서는 열리는데, 바깥에서는 중계 한 대(또는
 * 둘 다)가 "Broken pipe" 였습니다. 셋 다 `tailscale debug rebind` +
 * `tailscale debug restun` 한 번으로 바로 풀렸습니다(12/12 200).
 *
 * 사람이 없으면 그 두 줄을 칠 사람도 없습니다. 그래서 funnel 이 붙을 때마다
 * (처음 · 다시 붙을 때) 스스로 한 번 칩니다 — 멀쩡할 때 쳐도 잠깐 UDP 를
 * 다시 여는 것뿐이라 해가 없습니다(9/29 21:04 처럼 필요 없던 날도 있습니다).
 * 되풀이해서 붙는 날에 1분마다 치지 않게 5분에 한 번까지만. 각 8초 안에
 * 안 끝나면 끊고, 실패해도 서버 · 터널은 그대로 둡니다 — 실패하면 한 줄만.
 * -------------------------------------------------------------------------- */
let kickedAt = 0;
function kickRelays(bin) {
  const now = Date.now();
  if (kickedAt && now - kickedAt < TS_QUIET) return;
  kickedAt = now;
  const steps = [['debug', 'rebind'], ['debug', 'restun']];
  line('Tailscale 중계를 한 번 다시 잡습니다 (debug rebind · restun) — 재시작 뒤 바깥에서 안 열리던 일 때문입니다.');
  const next = () => {
    const a = steps.shift();
    if (!a || QUITTING.now) return;
    let ch, err = '', done = false, t = null;
    const end = code => {
      if (done) return;
      done = true;
      if (t) cancel(t);
      if (KIDS.kick === ch) KIDS.kick = null;
      if (QUITTING.now) return;
      if (code !== 0) {
        line('  (tailscale ' + a.join(' ') + ' 가 안 됐습니다' +
             (err.trim() ? ': ' + err.trim().split('\n')[0].slice(0, 80) : '') + ')');
      }
      next();
    };
    try {
      ch = spawn(bin || 'tailscale', a, { stdio: ['ignore', 'ignore', 'pipe'], windowsHide: true });
    } catch (e) { err = String(e.message || e); return end(null); }
    KIDS.kick = ch;
    t = later(() => { try { ch.kill(); } catch (e) {} }, 8000);
    ch.stderr.on('data', d => { if (err.length < 500) err += d; });
    ch.on('error', e => { err += String(e.message || e); end(null); });
    ch.on('close', code => end(code));
  };
  next();
}

/** 주소를 받았을 때 — 설정에 적고, 친구에게 보낼 상자를 찍고, 정말 열리는지 봅니다. */
function announceUrl(cfg, tunnel, url) {
  const isTs = tunnel.kind === 'tailscale';
  /* 이 컴퓨터가 **지금까지** 묶여 있던 ts.net 주소 — 파일에 적힌 것 기준.
     아래에서 덮기 전에 읽어 둡니다. */
  let home = '';
  /* 주소를 설정에 적어 둡니다 — 서버가 터널 뒤에서 사람별로 요청을
     세려면 이 값이 필요합니다. 다음에 띄울 때 또 바뀌면 그 때 덮습니다.
     Tailscale 로 연 주소는 tailscaleOrigin 에도 적습니다(committedToTailscale).
     Cloudflare 로 덮을 때는 그 전 ts.net 주소를 거기로 옮겨 둡니다 — 이 판
     전에 설정이 만들어진 컴퓨터(노트북)는 tailscaleOrigin 이 아직 없습니다.

     **바뀐 것이 없으면 안 씁니다.** 이 줄은 부팅마다 돕니다. 보고 48 의
     노트북은 방금 비정상 종료(Kernel-Power 41)로 켜진 컴퓨터였고, 그런 때
     파일을 통째로 다시 쓰다 찢어지면 load() 는 {} 를 돌려줍니다 — 그러면
     prepare() 가 설정을 처음부터 다시 만들어 가입 코드 · 알림 열쇠가 바뀌고
     origin 까지 비어 "안 묶인 컴퓨터" 가 됩니다. 안 쓰는 것이 제일 안전합니다. */
  try {
    const file = CONFIG.loadFile();
    home = tailscaleHome(file);
    const want = { origin: url, trustProxy: true };
    if (isTs) want.tailscaleOrigin = url;
    else if (home && !tsUrl(file.tailscaleOrigin)) want.tailscaleOrigin = home;
    if (!Object.keys(want).every(k => file[k] === want[k])) {
      const c = CONFIG.load().cfg;
      Object.assign(c, want);
      CONFIG.save(c);
    }
  } catch (e) {}
  /* 묶여 있던 주소와 다른 ts.net 주소가 나왔다 = **기기 이름이 바뀌었다.**
     다시 깔기 · 상태를 잃음(desktop-…-1 처럼 뒤에 번호가 붙습니다) · 기기
     이름 바꾸기. 친구들 폰의 앱은 전부 옛 주소를 보고 있으니, 여기서
     평소처럼 "안 바뀝니다" 를 찍으면 로그만 보는 사람은 영영 모릅니다.
     한 번 크게 말하고, 설정은 새 주소로 넘깁니다(서버는 실제 주소로 돌아야
     합니다). 이름을 되돌리면 다음 부팅에 한 번 더 이 말이 나오고 끝납니다. */
  const moved = isTs && home && tsUrl(url) !== home;
  if (moved) {
    line('');
    line('⚠ 이 컴퓨터의 공개 주소가 **바뀌었습니다.**');
    line('    전    ' + home);
    line('    지금  ' + url);
    line('  친구들 폰에 깔린 앱과 기록은 **전 주소**를 보고 있어서, 그쪽에서는 이제 안 열립니다.');
    line('  Tailscale 기기 이름이 바뀐 것입니다(다시 깔기 · 이름 바꾸기 · 뒤에 "-1" 이 붙음).');
    line('  되돌리려면 https://login.tailscale.com/admin/machines 에서 옛 기기를 지우고,');
    line('  이 기기 이름을 전 이름으로 바꾼 뒤 이 서버를 다시 띄우세요.');
    line('  일부러 옮긴 것이면 그대로 두세요 — 다음부터는 새 주소를 기준으로 봅니다.');
  }

  line('');
  box(cfg.openSignup ? [
    '친구에게 이 줄을 보내세요',
    '',
    '  주소  ' + url,
    '',
    '가입 코드는 없습니다 — 주소만 있으면 계정을 만듭니다.',
    '폰에서 열고 "앱처럼 깔기" 를 누르면 아이콘이 생깁니다.',
    '아이폰은 공유 → 홈 화면에 추가.'
  ] : [
    '친구에게 이 두 줄을 보내세요',
    '',
    '  주소      ' + url,
    '  가입 코드  ' + cfg.pairSecret,
    '',
    '폰에서 열고 "앱처럼 깔기" 를 누르면 아이콘이 생깁니다.',
    '아이폰은 공유 → 홈 화면에 추가.'
  ]);
  line('');
  /* 열어 둔 것은 주소를 찍을 때마다 같이 찍습니다.
     설정 파일 안에만 있으면 몇 주 뒤엔 열어 둔 줄도 잊습니다. */
  if (cfg.openSignup) {
    line('⚠ 가입 코드를 꺼 둔 상태입니다 — 이 주소를 아는 사람은 누구나');
    line('  계정을 만들 수 있습니다. 내 숫자를 보는 것은 아니지만');
    line('  (친구 맺기는 초대 코드가 따로 필요합니다) 모르는 계정이 쌓일 수 있습니다.');
    line('  닫으려면 이 창을 끄고:  node tools/launch.js --pair-code');
    line('');
  }
  if (isTs) {
    /* 주소가 안 바뀌면 이 앱의 제일 큰 함정 하나가 통째로 사라집니다.
       그 사실을 말해 주는 편이, 없는 경고를 계속 찍는 것보다 낫습니다.
       방금 바뀐 경우(moved)에는 이 말이 거짓이라 안 합니다. */
    if (!moved) {
      line('✓ 이 주소는 **안 바뀝니다.** 껐다 켜도 그대로입니다 —');
      line('  친구들 폰에 깔아 둔 앱과 그동안의 기록이 그대로 남습니다.');
    }
    line('  크롬도 이 도메인은 막지 않아서 **앱으로 깔 수 있습니다.**');
    line('');
    line('  다만 이 창을 닫으면 서버가 꺼지고, 그 동안은 아무도 못 씁니다.');
    line('  켤 때마다 자동으로 띄우려면:  node tools/autostart.js --write');
  } else {
    line('⚠ 이 주소는 **끌 때까지만** 살아 있고, 다시 띄우면 바뀝니다.');
    line('  주소가 바뀌면 친구들 폰에서 그동안의 기록이 안 보이게 됩니다');
    line('  (브라우저가 주소별로 따로 저장합니다).');
    line('');
    line('  그리고 크롬이 trycloudflare 를 위험 사이트로 표시해서');
    line('  **폰에 앱으로 깔 수가 없습니다.** 깔고 싶으면 주소를 고정하세요:');
    line('    ① Tailscale — 개인 무료, 주소 안 바뀜. 깔아 두면 이 명령이');
    line('       알아서 그쪽을 씁니다.');
    line('    ② 내 도메인 — docs/START.md 4-B');
    if (home) {
      /* ts.net 에 묶인 컴퓨터를 사람이 일부러 --cloudflare 로 띄운 경우. */
      line('');
      line('  이 컴퓨터의 원래 주소(' + home + ')는 기억해 둡니다.');
      line('  친구들 앱은 그 주소를 보고 있어서 이 주소로는 안 들어옵니다.');
      line('  --cloudflare 없이 다시 띄우면 그 주소로 돌아갑니다.');
    }
  }
  line('');
  line('이 창을 닫으면 서버와 터널이 같이 꺼집니다.');
  line('');
  /* 마지막으로 **정말 열리는지** 우리가 두드려 봅니다.
     주소를 찍는 것과 그 주소가 열리는 것은 다른 일입니다. */
  verifyUrl(url, tunnel).catch(() => {});
}

/* 시험 전용 — **서버가 늦게 꺼지는 컴퓨터**를 흉내 냅니다(기본 0).
 *
 * 평소에는 serve.js 가 몇십 ms 만에 꺼지고 이 프로세스도 곧바로 끝나서,
 * 끌 때 걷지 못한 타이머가 있어도 울릴 틈이 없습니다 — 시험이 그 실수를
 * 못 잡습니다. 그런데 서버가 연결을 정리하느라 몇 초 걸리는 날에는 그 틈에
 * 타이머가 울려 funnel 을 새로 띄울 수 있습니다. 이 값만큼 늦게 끝나게 해서
 * 그 틈을 시험에서 일부러 만듭니다. 10초를 넘는 값은 무시합니다. */
const EXIT_DELAY = (() => {
  const n = Number(process.env.MYBODY_EXIT_DELAY_MS);
  return Number.isFinite(n) && n > 0 && n <= 10000 ? n : 0;
})();

/* --- 달리기 --------------------------------------------------------------- */
function main() {
  line('');
  const cfg = prepare();
  const committed = has('no-tunnel') ? '' : committedToTailscale(cfg);
  COMMITTED = committed;
  const tunnel = has('no-tunnel') ? null : findTunnel(committed);

  if (tunnel) {
    if (tunnel.kind === 'tailscale') {
      line('Tailscale 로 엽니다 — 주소가 안 바뀝니다.');
      if (tunnel.pending) {
        /* 이유는 여기서 한 번만 말합니다. 기다리는 동안은 5분에 한 줄. */
        line('Tailscale 준비를 기다립니다 — ' + tunnel.why);
        if (!tunnel.bin) {
          line('');
          installHint(true).forEach(l => line('  ' + l));
          line('');
        }
        line('  서버는 먼저 띄웁니다 — 같은 와이파이에서는 지금도 쓸 수 있고,');
        line('  Tailscale 이 준비되면 그때 주소를 엽니다.');
        line('  Cloudflare 로는 넘어가지 않습니다 (' +
             (committed === 'origin' ? '이 컴퓨터 주소는 ' + tailscaleHome(cfg)
                                     : '--tailscale 로 띄웠습니다') + ').');
        line('  주소가 바뀌면 친구들 폰에서 그동안의 기록이 안 보이게 됩니다.');
      }
    } else {
      line('Cloudflare 임시 터널로 엽니다 — 주소가 띄울 때마다 바뀝니다.');
      if (tunnelNote) line('  (Tailscale 을 안 쓴 이유: ' + tunnelNote + ')');
    }
    line('');
  }

  if (!has('no-tunnel') && !tunnel) {
    line('');
    line('밖에서 접속할 길(터널)이 없습니다.');
    line('없으면 **같은 와이파이에서만** 쓸 수 있고, 그 주소는 https 가');
    line('아니라 **폰에 앱으로 깔 수도, 알림을 받을 수도 없습니다.**');
    line('');
    installHint().forEach(l => line('  ' + l));
    line('');
    line('깐 다음 다시 이 명령을 치세요. 지금 당장 같은 와이파이에서만');
    line('써 볼 거면:  node tools/launch.js --no-tunnel');
    process.exit(1);
  }

  /* 서버를 먼저 띄웁니다. 터널이 붙을 자리가 있어야 하니까요. */
  const server = spawn(node, [path.join(__dirname, 'serve.js')],
    { cwd: ROOT, stdio: 'inherit' });

  /* 끌 때는 기다리던 것 · 다시 붙이려던 것까지 전부 걷습니다 (later · KIDS). */
  const bye = () => {
    stopEverything();
    try { server.kill(); } catch (e) {}
  };
  process.on('SIGINT', bye);
  process.on('SIGTERM', bye);
  server.on('exit', code => {
    bye();
    const c = code == null ? 0 : code;
    if (EXIT_DELAY) setTimeout(() => process.exit(c), EXIT_DELAY);
    else process.exit(c);
  });

  if (!tunnel) return;

  const announce = (t, url) => announceUrl(cfg, t, url);
  /* 서버가 뜰 시간을 줍니다. 너무 일찍 붙으면 cloudflared 가 502 를
     한참 뱉다가 스스로 회복하는데, 그 사이 사용자는 깨진 줄 압니다. */
  later(() => {
    if (tunnel.kind !== 'tailscale') {
      KIDS.tunnel = startTunnel(tunnel, cfg.port, url => announce(tunnel, url));
      return;
    }
    if (!tunnel.pending) { keepFunnel(tunnel, cfg.port, announce); return; }
    waitForTailscale(ready => keepFunnel(ready, cfg.port, announce));
  }, 1500);
}

main();
