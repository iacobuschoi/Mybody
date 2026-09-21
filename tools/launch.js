/* =============================================================================
 * tools/launch.js — 한 줄로 배포까지
 *
 *   node tools/launch.js
 *
 * 하는 일 (없는 것만 알아서 만듭니다)
 *   1. 이 컴퓨터가 띄울 수 있는지 봅니다
 *   2. 설정이 없으면 만듭니다 (가입 코드 자동 생성, 이름은 안 겁니다)
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
 * 임시 터널 주의
 *   도메인 없이 쓰면 주소가 **띄울 때마다 바뀝니다.** 브라우저는 기록을
 *   주소별로 따로 저장하므로, 주소가 바뀌면 친구들 폰에서 그동안의
 *   기록이 통째로 안 보이게 됩니다. 그래서 처음 한 번은 이걸로 열어
 *   보되, 계속 쓸 거면 고정 주소를 만들라고 큰 소리로 말합니다.
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
 * cloudflared 가 제일 흔하고 계정 없이도 임시 주소를 줍니다.
 * 없으면 **어떻게 까는지 OS 별로** 말해 줍니다 — "설치하세요" 는
 * 아무에게도 도움이 안 됩니다.
 * -------------------------------------------------------------------------- */
function findTunnel() {
  const which = process.platform === 'win32' ? 'where' : 'which';
  for (const bin of ['cloudflared']) {
    const r = spawnSync(which, [bin], { encoding: 'utf8' });
    if (r.status === 0 && (r.stdout || '').trim()) return bin;
  }
  return null;
}
function installHint() {
  if (process.platform === 'darwin') {
    return ['맥이면:', '    brew install cloudflared',
            '  (brew 가 없으면 https://brew.sh 먼저)'];
  }
  if (process.platform === 'win32') {
    return ['윈도우면:', '    winget install --id Cloudflare.cloudflared',
            '  (winget 이 없으면 https://github.com/cloudflare/cloudflared/releases 에서', 
            '   cloudflared-windows-amd64.exe 를 받아 PATH 에 두세요)'];
  }
  return ['리눅스면:',
          '    curl -L -o cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64',
          '    chmod +x cloudflared && sudo mv cloudflared /usr/local/bin/'];
}

/* --- 1~4. 준비 ------------------------------------------------------------ */
function prepare() {
  let { cfg } = CONFIG.load();

  if (!cfg.pairSecret) {
    line('설정이 없어서 만듭니다 (한 번만 합니다)');
    const r = run('serve.js', ['--setup', '--no-owner']);
    process.stdout.write(r.stdout || '');
    if (r.status !== 0) { process.stderr.write(r.stderr || ''); process.exit(1); }
    cfg = CONFIG.load().cfg;
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
function startTunnel(port, onUrl) {
  const child = spawn('cloudflared',
    ['tunnel', '--no-autoupdate', '--url', 'http://localhost:' + port],
    { cwd: ROOT, stdio: ['ignore', 'pipe', 'pipe'] });

  let found = false;
  const scan = buf => {
    const m = /https:\/\/[a-z0-9-]+\.trycloudflare\.com/i.exec(String(buf));
    if (m && !found) { found = true; onUrl(m[0]); }
  };
  child.stdout.on('data', scan);
  child.stderr.on('data', scan);
  child.on('exit', code => {
    if (!found) {
      line('');
      line('터널이 주소를 못 만들고 끝났습니다 (종료 코드 ' + code + ').');
      line('인터넷이 막혀 있거나 cloudflared 가 차단됐을 수 있습니다.');
      line('서버 자체는 그대로 돌고 있습니다 — 같은 와이파이에서는 쓸 수 있습니다.');
    }
  });
  return child;
}

/* --- 달리기 --------------------------------------------------------------- */
function main() {
  line('');
  const cfg = prepare();
  const tunnel = has('no-tunnel') ? null : findTunnel();

  if (!has('no-tunnel') && !tunnel) {
    line('');
    line('터널 도구(cloudflared)가 없습니다.');
    line('없으면 **같은 와이파이에서만** 쓸 수 있고, 폰 알림도 안 됩니다.');
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
    tun = startTunnel(cfg.port, url => {
      /* 주소를 설정에 적어 둡니다 — 서버가 터널 뒤에서 사람별로 요청을
         세려면 이 값이 필요합니다. 다음에 띄울 때 또 바뀌면 그 때 덮습니다. */
      try {
        const c = CONFIG.load().cfg;
        c.origin = url; c.trustProxy = true;
        CONFIG.save(c);
      } catch (e) {}

      line('');
      box([
        '친구에게 이 두 줄을 보내세요',
        '',
        '  주소      ' + url,
        '  가입 코드  ' + cfg.pairSecret,
        '',
        '폰에서 열고 "앱처럼 깔기" 를 누르면 아이콘이 생깁니다.',
        '아이폰은 공유 → 홈 화면에 추가.'
      ]);
      line('');
      line('⚠ 이 주소는 **끌 때까지만** 살아 있고, 다시 띄우면 바뀝니다.');
      line('  주소가 바뀌면 친구들 폰에서 그동안의 기록이 안 보이게 됩니다');
      line('  (브라우저가 주소별로 따로 저장합니다).');
      line('  계속 쓸 거면 고정 주소를 만드세요 — docs/START.md 4-B.');
      line('');
      line('이 창을 닫으면 서버와 터널이 같이 꺼집니다.');
      line('');
    });
  }, 1500);
}

main();
