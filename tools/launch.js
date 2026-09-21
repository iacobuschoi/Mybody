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

/** 실행 파일을 찾습니다. PATH 에 없으면 기본 설치 자리도 봅니다. */
function findBin(bin) {
  const which = process.platform === 'win32' ? 'where' : 'which';
  const r = spawnSync(which, [bin], { encoding: 'utf8' });
  if (r.status === 0 && (r.stdout || '').trim()) return bin;
  for (const p of (WELL_KNOWN[bin] || [])) {
    try { if (fs.existsSync(p)) return p; } catch (e) {}
  }
  return null;
}

/** tailscale 이 왜 안 되는지까지 알려줍니다. { bin, name, why } */
function tailscaleState() {
  const bin = findBin('tailscale');
  if (!bin) {
    return { bin: null, name: null,
      why: process.platform === 'win32'
        ? 'Tailscale 이 안 깔려 있습니다 (winget install --id tailscale.tailscale). ' +
          '방금 깔았다면 **PowerShell 창을 닫고 새로 여세요.**'
        : 'Tailscale 이 안 깔려 있습니다.' };
  }
  const r = spawnSync(bin, ['status', '--json'], { encoding: 'utf8', timeout: 8000 });
  if (r.status !== 0) {
    const msg = ((r.stderr || '') + (r.stdout || '')).trim().split('\n')[0];
    return { bin: bin, name: null,
      why: /logged out|NeedsLogin|not running|Tailscale is stopped/i.test(msg)
        ? 'Tailscale 에 로그인해야 합니다 — 트레이(또는 메뉴 막대)의 Tailscale 에서 로그인하세요.'
        : 'Tailscale 이 대답하지 않습니다' + (msg ? ' (' + msg.slice(0, 80) + ')' : '') };
  }
  let dns = '';
  try {
    const j = JSON.parse(r.stdout || '{}');
    dns = ((j.Self && j.Self.DNSName) || '').replace(/\.$/, '');
    if (!dns) {
      return { bin: bin, name: null,
        why: 'Tailscale 은 도는데 이 기기 이름이 없습니다 — 로그인이 끝났는지 보세요.' };
    }
  } catch (e) {
    return { bin: bin, name: null, why: 'Tailscale 상태를 읽지 못했습니다' };
  }
  return { bin: bin, name: dns, why: null };
}

/** 어떤 터널을 쓸 것인가. { kind, name, bin } 또는 null */
function findTunnel() {
  if (!has('cloudflare')) {
    const ts = tailscaleState();
    if (ts.name) return { kind: 'tailscale', name: ts.name, bin: ts.bin };
    /* 왜 안 썼는지 말합니다. 조용히 cloudflared 로 넘어가면, 주인은
       Tailscale 을 깔아 놓고도 계속 바뀌는 주소를 받으면서 이유를
       모릅니다 — 실제로 그렇게 됐습니다. */
    if (has('tailscale')) {
      line('Tailscale 을 쓰려고 했는데 준비가 안 됐습니다:');
      line('  ' + ts.why);
      line('');
      return null;
    }
    tunnelNote = ts.why;
  }
  const cf = findBin('cloudflared');
  if (cf) return { kind: 'cloudflared', name: null, bin: cf };
  return null;
}

function installHint() {
  /* 두 길을 다 보여 주되, **주소가 안 바뀌는 쪽을 먼저** 적습니다.
     빠른 길만 알려 주면 나중에 반드시 다시 옵니다 — 주소가 바뀌어서. */
  const ts = process.platform === 'darwin'
    ? '    brew install tailscale && sudo tailscale up'
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
  return [
    '① 주소가 안 바뀌는 길 (추천) — Tailscale, 개인 무료',
    ...ts.split('\n'),
    '   주소: https://<기기이름>.<테일넷>.ts.net  — 껐다 켜도 그대로입니다.',
    '   크롬이 막지 않아서 **폰에 앱으로 깔 수 있습니다.**',
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
function startTunnel(tunnel, port, onUrl) {
  const isTs = tunnel.kind === 'tailscale';
  const child = isTs
    /* funnel 은 443·8443·10000 에서만 받습니다. 기본 443 으로 두고
       안쪽 포트만 넘깁니다. --bg 를 안 붙이는 이유: 이 창을 닫으면
       터널도 같이 꺼져야 합니다. 붙이면 서버만 죽고 주소는 살아남아
       "열려 있는데 아무것도 없는 주소" 가 됩니다. */
    ? spawn(tunnel.bin || 'tailscale', ['funnel', String(port)],
            { cwd: ROOT, stdio: ['ignore', 'pipe', 'pipe'] })
    : spawn(tunnel.bin || 'cloudflared',
            ['tunnel', '--no-autoupdate', '--url', 'http://localhost:' + port],
            { cwd: ROOT, stdio: ['ignore', 'pipe', 'pipe'] });

  let found = false;
  let alive = true;
  let out = '';
  const RE = isTs ? /https:\/\/[a-z0-9-]+\.[a-z0-9.-]+\.ts\.net/i
                  : /https:\/\/[a-z0-9-]+\.trycloudflare\.com/i;
  const scan = buf => {
    out += String(buf);
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
    if (isTs) {
      String(buf).split('\n').forEach(l => {
        const t = l.trim();
        if (t) line('  tailscale: ' + t);
      });
    }
    const m = RE.exec(String(buf));
    if (m && !found) { found = true; onUrl(m[0].replace(/\/$/, '')); }
  };
  child.stdout.on('data', scan);
  child.stderr.on('data', scan);

  /* tailscale 은 이미 이름을 알고 있습니다 — 굳이 출력에서 긁어내지
     않아도 됩니다. 출력 형식이 바뀌어도 여기서 안 막히게 해 둡니다.
     다만 **프로세스가 아직 살아 있을 때만** 씁니다. 죽은 뒤에 이름만
     보고 주소를 찍으면, 안 열리는 주소를 자신 있게 알려 주게 됩니다 —
     주인이 실제로 그 주소를 받고 "안 들어가진다" 고 했습니다. */
  if (isTs && tunnel.name) {
    setTimeout(() => {
      if (!found && alive) { found = true; onUrl('https://' + tunnel.name); }
    }, 2500);
  }

  child.on('exit', code => {
    alive = false;
    /* 내가 끄는 중이면 아무 말도 안 합니다. 사용자가 Ctrl+C 를 눌렀는데
       "터널이 끊겼습니다" 가 뜨면 고장으로 읽힙니다. */
    if (QUITTING.now) return;
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
      const said = out.trim().split('\n').filter(l => l.trim()).slice(-4);
      if (said.length) { line('tailscale 이 한 말:'); said.forEach(l => line('  ' + l.trim())); }
      if (hint) { line(''); line('여기서 한 번 켜 주세요:'); line('  ' + hint); }
      else {
        line('');
        line('Funnel 이 이 테일넷에서 아직 안 켜져 있을 수 있습니다:');
        line('  https://login.tailscale.com/admin/settings/keys 가 아니라');
        line('  https://login.tailscale.com/admin/acls 의 nodeAttrs 에 funnel 이 필요합니다.');
        line('  (관리자 화면에서 Funnel 을 켜면 자동으로 들어갑니다)');
      }
      line('그래도 안 되면 Cloudflare 로:  node tools/launch.js --cloudflare');
    } else {
      line('인터넷이 막혀 있거나 cloudflared 가 차단됐을 수 있습니다.');
    }
    line('서버 자체는 그대로 돌고 있습니다 — 같은 와이파이에서는 쓸 수 있습니다.');
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

function verifyUrl(url, tunnel, tries) {
  tries = tries || 0;
  const MAX = VERIFY_TRIES;
  if (QUITTING.now) return Promise.resolve(false);
  return fetch(url + '/health', { redirect: 'follow' })
    .then(r => r.ok ? r.json().catch(() => null) : null)
    .then(j => {
      if (j && j.ok) {
        line('✓ 이 주소로 실제로 들어와집니다. 폰에서 열어 보세요.');
        line('');
        return true;
      }
      throw new Error('우리 서버가 아닌 답');
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
                             { encoding: 'utf8', timeout: 8000 });
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
        const link = (out.match(/https:\/\/login\.tailscale\.com\/f\/funnel\S*/) || [])[0];
        if (link) {
          line('이 링크를 눌러 한 번 켜 주세요 (tailscale 이 준 링크입니다):');
          line('  ' + link);
          line('');
        }
        line('손으로 켜려면 두 군데를 봐야 합니다:');
        line('  ① https://login.tailscale.com/admin/dns');
        line('     MagicDNS 와 HTTPS Certificates 를 **둘 다** 켜세요.');
        line('  ② https://login.tailscale.com/admin/acls');
        line('     정책 파일에 이 세 줄을 넣으세요:');
        line('       "nodeAttrs": [');
        line('         { "target": ["autogroup:member"], "attr": ["funnel"] }');
        line('       ]');
        line('  그다음 이 창을 끄고 node tools/launch.js 를 다시 치세요.');
        line('');
        line('지금 당장 쓰려면:  node tools/launch.js --cloudflare');
        line('  (주소가 바뀌고 앱 설치는 안 되지만, 열리기는 합니다)');
      } else {
        line('cloudflared 가 주소를 만들었지만 아직 연결이 안 됐습니다.');
        line('잠시 뒤 다시 열어 보세요. 계속 안 되면 서버를 끄고 다시 띄우세요.');
      }
      line('');
      return false;
    });
}

/* --- 달리기 --------------------------------------------------------------- */
function main() {
  line('');
  const cfg = prepare();
  const tunnel = has('no-tunnel') ? null : findTunnel();

  if (tunnel) {
    if (tunnel.kind === 'tailscale') {
      line('Tailscale 로 엽니다 — 주소가 안 바뀝니다.');
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

  let tun = null;
  const bye = () => {
    QUITTING.now = true;
    try { if (tun) tun.kill(); } catch (e) {}
    try { server.kill(); } catch (e) {}
  };
  process.on('SIGINT', bye);
  process.on('SIGTERM', bye);
  server.on('exit', code => { bye(); process.exit(code == null ? 0 : code); });

  if (!tunnel) return;

  /* 서버가 뜰 시간을 줍니다. 너무 일찍 붙으면 cloudflared 가 502 를
     한참 뱉다가 스스로 회복하는데, 그 사이 사용자는 깨진 줄 압니다. */
  setTimeout(() => {
    tun = startTunnel(tunnel, cfg.port, url => {
      /* 주소를 설정에 적어 둡니다 — 서버가 터널 뒤에서 사람별로 요청을
         세려면 이 값이 필요합니다. 다음에 띄울 때 또 바뀌면 그 때 덮습니다. */
      try {
        const c = CONFIG.load().cfg;
        c.origin = url; c.trustProxy = true;
        CONFIG.save(c);
      } catch (e) {}

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
      if (tunnel.kind === 'tailscale') {
        /* 주소가 안 바뀌면 이 앱의 제일 큰 함정 하나가 통째로 사라집니다.
           그 사실을 말해 주는 편이, 없는 경고를 계속 찍는 것보다 낫습니다. */
        line('✓ 이 주소는 **안 바뀝니다.** 껐다 켜도 그대로입니다 —');
        line('  친구들 폰에 깔아 둔 앱과 그동안의 기록이 그대로 남습니다.');
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
      }
      line('');
      line('이 창을 닫으면 서버와 터널이 같이 꺼집니다.');
      line('');
      /* 마지막으로 **정말 열리는지** 우리가 두드려 봅니다.
         주소를 찍는 것과 그 주소가 열리는 것은 다른 일입니다. */
      verifyUrl(url, tunnel).catch(() => {});
    });
  }, 1500);
}

main();
