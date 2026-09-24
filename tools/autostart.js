/* =============================================================================
 * tools/autostart.js — 컴퓨터를 켜면 서버도 같이 켜지게
 *
 *   node tools/autostart.js            내 OS 에 맞는 설정을 보여줍니다
 *   node tools/autostart.js --write    실제로 파일을 만들고 거는 법까지
 *   node tools/autostart.js --daemon   (맥) 로그인 없이 켜지는 상시 서버용 — docs/MAC.md
 *
 * 왜 필요한가
 *   노트북을 닫거나 재부팅하면 서버가 죽습니다. 그러면 친구 화면에서
 *   내가 사라지고, 친구도 접속을 못 합니다. 그때마다 터미널을 열어
 *   다시 치는 것을 기억하기를 바라는 건 무리입니다.
 *
 * 왜 도구로 만드나
 *   문서에 적어 두면 두 곳에서 막힙니다. 크론·launchd·systemd 는 평소
 *   쓰는 PATH 도 HOME 도 안 물려받습니다 — `node` 를 못 찾거나, 설정
 *   파일(~/.mybody/config.json)을 못 찾습니다. 지금 이 프로세스가
 *   아는 실제 경로를 박아서 만들면 그 두 가지가 처음부터 맞습니다.
 * ========================================================================== */
'use strict';
process.removeAllListeners('warning');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

/* **노드 경로는 안 바뀌는 쪽으로 박습니다.** 맥의 Homebrew 에서
   /opt/homebrew/bin/node 는 Cellar/node@24/24.21.0/bin/node 를 가리키는
   링크이고, 노드는 자기 경로를 링크를 다 푼 쪽(판 번호가 든 쪽)으로 압니다.
   그걸 박아 두면 `brew upgrade` 가 옛 판을 지우는 순간 자동 시작이
   "그런 파일 없음" 으로 계속 죽습니다. 같은 노드를 가리키는 opt 링크
   (/opt/homebrew/opt/node@24/bin/node)가 있으면 그쪽을 씁니다. */
function stableNode(p) {
  const m = /^(.*)\/Cellar\/([^/]+)\/[^/]+\/bin\/node$/.exec(p);
  if (m) {
    const opt = m[1] + '/opt/' + m[2] + '/bin/node';
    try { if (fs.realpathSync(opt) === fs.realpathSync(p)) return opt; } catch (e) {}
  }
  return p;
}

const ROOT = path.join(__dirname, '..');
const NODE = stableNode(process.execPath);   // 지금 돌고 있는 노드의 전체 경로
const SERVE = path.join(ROOT, 'tools', 'serve.js');
const HOME = os.homedir();
const WRITE = process.argv.includes('--write');
const DAEMON = process.argv.includes('--daemon');
const LABEL = 'com.mybody.server';
const PORT = (() => { try { return require('./config.js').load().cfg.port; } catch (e) { return 8080; } })();

/* opt 링크가 없는 설치(nvm · volta · fnm · asdf, Cellar 를 직접 가리키는 것)는
   판 번호가 경로에 남습니다. 막지는 않고, 올리면 깨진다고 말합니다. */
if (/\/Cellar\/|\/\.nvm\/versions\/|\/\.volta\/|\/fnm\/|\/\.asdf\/installs\/|\/mise\/installs\/|[\\/]nvm[\\/]v\d/.test(NODE)) {
  console.log('');
  console.log('⚠ 이 노드 경로에는 판 번호가 들어 있습니다: ' + NODE);
  console.log('  노드를 올리거나 지우면 자동 시작이 깨집니다. 경로가 안 바뀌는 설치를 권합니다 —');
  console.log('  맥은 brew install node@24 (또는 nodejs.org 설치 파일), 리눅스는 배포판 패키지.');
}

/** plist 문자열 안에 넣을 값 (경로에 & 나 < 가 있어도 깨지지 않게) */
function esc(v) {
  return String(v).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

function out(title, body, where, how) {
  console.log('');
  console.log(title);
  console.log('');
  console.log('  파일: ' + where);
  console.log('');
  body.split('\n').forEach(l => console.log('    ' + l));
  console.log('');
  console.log('  거는 법:');
  how.split('\n').forEach(l => console.log('    ' + l));
  console.log('');
}

function writeFile(where, body) {
  fs.mkdirSync(path.dirname(where), { recursive: true });
  fs.writeFileSync(where, body);
  console.log('만들었습니다: ' + where);
}

if (process.platform === 'darwin' && DAEMON) {
  /* **맥미니 상시 서버는 이쪽입니다.** 로그인용(LaunchAgent)은 누가 로그인해야
     켜집니다. 디스크 암호화(FileVault)를 켜 두면 자동 로그인이 안 되므로,
     정전 뒤 다시 켜진 맥은 로그인 화면에서 멈추고 서버는 안 뜹니다.
     LaunchDaemon 은 부팅하면 로그인 없이 뜹니다 — 주인 계정으로 돌게
     UserName 을 넣고, launchd 가 안 물려주는 HOME 을 직접 넣습니다
     (설정 파일 ~/.mybody/config.json 을 거기서 찾습니다). */
  if (process.getuid && process.getuid() === 0) {
    console.error('sudo 없이 실행하세요 — 주인 계정 이름과 홈 폴더를 여기서 읽습니다.');
    console.error('파일은 홈 폴더에 만들고, /Library/LaunchDaemons 로 옮기는 sudo 명령을 찍어 드립니다.');
    process.exit(1);
  }
  const user = os.userInfo().username;
  const logDir = path.join(HOME, 'Library', 'Logs');
  const log = path.join(logDir, 'mybody.log');
  const blog = path.join(logDir, 'mybody-backup.log');
  const backups = path.join(HOME, 'mybody-backups');
  const staging = path.join(HOME, '.mybody', 'launchd');
  const env = `  <key>EnvironmentVariables</key>
  <dict>
    <key>HOME</key><string>${esc(HOME)}</string>
    <key>PATH</key><string>${esc(path.dirname(NODE))}:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
  </dict>`;
  const head = `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>`;
  /* ThrottleInterval 30: 서버가 곧바로 죽으면(포트가 이미 쓰이는 등) 기본 10초마다
     다시 띄웁니다. 띄울 때마다 점검이 돌고 로그가 쌓이니 간격을 벌립니다. */
  const serverBody = `${head}
  <key>Label</key><string>${LABEL}</string>
  <key>UserName</key><string>${esc(user)}</string>
  <key>GroupName</key><string>staff</string>
  <key>ProgramArguments</key>
  <array>
    <string>${esc(NODE)}</string>
    <string>${esc(SERVE)}</string>
  </array>
  <key>WorkingDirectory</key><string>${esc(ROOT)}</string>
${env}
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ThrottleInterval</key><integer>30</integer>
  <key>StandardOutPath</key><string>${esc(log)}</string>
  <key>StandardErrorPath</key><string>${esc(log)}</string>
</dict>
</plist>
`;
  /* 매일 새벽 4시 백업 — 오라클 VM 의 크론과 같은 일. 그 시각에 맥이 꺼져
     있었으면 그날은 건너뜁니다(잠들어 있었으면 깨어날 때 돕니다). */
  const backupBody = `${head}
  <key>Label</key><string>com.mybody.backup</string>
  <key>UserName</key><string>${esc(user)}</string>
  <key>GroupName</key><string>staff</string>
  <key>ProgramArguments</key>
  <array>
    <string>${esc(NODE)}</string>
    <string>${esc(path.join(ROOT, 'tools', 'backup.js'))}</string>
    <string>--out=${esc(backups)}</string>
  </array>
  <key>WorkingDirectory</key><string>${esc(ROOT)}</string>
${env}
  <key>StartCalendarInterval</key>
  <dict><key>Hour</key><integer>4</integer><key>Minute</key><integer>0</integer></dict>
  <key>StandardOutPath</key><string>${esc(blog)}</string>
  <key>StandardErrorPath</key><string>${esc(blog)}</string>
</dict>
</plist>
`;
  const S = path.join(staging, LABEL + '.plist');
  const B = path.join(staging, 'com.mybody.backup.plist');
  const how = `touch "${log}" "${blog}"     # 로그 파일을 주인 것으로 먼저 만들어 둡니다
sudo cp "${S}" "${B}" /Library/LaunchDaemons/
sudo chown root:wheel /Library/LaunchDaemons/com.mybody.server.plist /Library/LaunchDaemons/com.mybody.backup.plist
sudo chmod 644 /Library/LaunchDaemons/com.mybody.server.plist /Library/LaunchDaemons/com.mybody.backup.plist
sudo launchctl bootstrap system /Library/LaunchDaemons/com.mybody.server.plist    # 걸기(바로 뜹니다)
sudo launchctl bootstrap system /Library/LaunchDaemons/com.mybody.backup.plist
sudo tailscale funnel --bg ${PORT}      # 주소 열기 — 한 번만. 재부팅해도 유지됩니다
# 이 뒤로 이 맥에서는 launch.js 를 쓰지 않습니다 — 서버는 launchd 가, 주소는 funnel --bg 가 맡습니다.

sudo launchctl print system/${LABEL} | grep -E 'state =|pid ='   # 도는지
sudo launchctl kickstart -k system/${LABEL}   # git pull 뒤 다시 띄우기
sudo launchctl bootout system/${LABEL}        # 멈추고 내리기(부팅 때도 안 뜸 — 다시 걸려면 bootstrap)
tail -f "${log}"                              # 뭐라고 하는지 보기
curl -s localhost:${PORT}/health              # 대답하는지

# plist 를 고쳤으면 bootout 뒤 bootstrap 을 다시 해야 반영됩니다.
# 서버 로그는 회전 없이 자랍니다. 가끔 비우기:  : > "${log}"`;
  const agent = path.join(HOME, 'Library', 'LaunchAgents', LABEL + '.plist');
  if (fs.existsSync(agent)) {
    console.log('');
    console.log('⚠ 로그인용 자동 시작(LaunchAgent)이 이미 있습니다: ' + agent);
    console.log('  둘 다 걸면 서버가 두 번 뜨려다 포트에서 부딪힙니다. 먼저 내리세요:');
    console.log('    launchctl bootout gui/$(id -u)/' + LABEL + '; rm "' + agent + '"');
  }
  if (WRITE) {
    writeFile(S, serverBody);
    writeFile(B, backupBody);
    console.log('\n아직 안 걸었습니다. 거는 법:\n');
    how.split('\n').forEach(l => console.log('  ' + l));
    console.log('');
  } else {
    out('macOS — 로그인 없이 부팅하면 켜집니다 (LaunchDaemon · 상시 서버)', serverBody.trimEnd(), '/Library/LaunchDaemons/' + LABEL + '.plist', how);
    console.log('  같이 만드는 백업 작업 (매일 04:00 → ' + backups + '):');
    console.log('');
    backupBody.trimEnd().split('\n').forEach(l => console.log('    ' + l));
    console.log('');
  }

} else if (process.platform === 'darwin') {
  const where = path.join(HOME, 'Library', 'LaunchAgents', LABEL + '.plist');
  const logDir = path.join(HOME, 'Library', 'Logs');
  const body = `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>${LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>${esc(NODE)}</string>
    <string>${esc(SERVE)}</string>
  </array>
  <key>WorkingDirectory</key><string>${esc(ROOT)}</string>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ThrottleInterval</key><integer>30</integer>
  <key>StandardOutPath</key><string>${esc(path.join(logDir, 'mybody.log'))}</string>
  <key>StandardErrorPath</key><string>${esc(path.join(logDir, 'mybody.log'))}</string>
</dict>
</plist>`;
  const how = `launchctl bootstrap gui/$(id -u) "${where}"          # 걸기
launchctl bootout gui/$(id -u)/${LABEL}              # 풀기
launchctl kickstart -k gui/$(id -u)/${LABEL}         # 다시 띄우기
tail -f "${path.join(logDir, 'mybody.log')}"   # 뭐라고 하는지 보기

# 누가 로그인해야 켜집니다. 맥을 상시 서버로 두면(로그인 없이, 정전 뒤에도)
# node tools/autostart.js --daemon 을 쓰세요 — docs/MAC.md
# 이 파일은 회전도 보유 기간도 없이 계속 자랍니다.
# 요청 한 줄씩이라 느리게 자라지만, 몇 달이면 큽니다.
# 가끔 비우기:  : > "${path.join(logDir, 'mybody.log')}"
# 아예 안 남기려면 위 plist 에 이 두 줄을 넣으세요:
#   <key>EnvironmentVariables</key><dict><key>LOG</key><string>0</string></dict>`;
  if (WRITE) { writeFile(where, body); console.log('\n걸려면:\n  launchctl bootstrap gui/$(id -u) "' + where + '"\n'); }
  else out('macOS — 로그인하면 자동으로 켜집니다', body, where, how);

} else if (process.platform === 'win32') {
  const where = path.join(ROOT, 'mybody-autostart.cmd');
  const winLog = path.join(HOME, 'mybody.log');
  /* 예전에는 출력이 어디로도 안 갔습니다. 자동 시작으로 걸어 두면
     창이 없으니, 서버가 왜 안 뜨는지 볼 방법이 아예 없었습니다.
     파일로 받되 **띄울 때마다 새로 씁니다**(>) — 이어 붙이면(>>)
     회전도 보유 기간도 없이 영원히 자랍니다. */
  const body = `@echo off\r\ncd /d "${ROOT}"\r\n"${NODE}" "${SERVE}" > "${winLog}" 2>&1\r\n`;
  const how = `작업 스케줄러(taskschd.msc)를 열고
  1. "작업 만들기"
  2. 트리거: "로그온할 때"
  3. 동작: 프로그램 시작 → "${where}"
  4. 조건 탭에서 "컴퓨터가 배터리로 전환되면 중지" 를 끄세요

뭐라고 하는지 보기: ${winLog}  (띄울 때마다 새로 씁니다)`;
  if (WRITE) { writeFile(where, body); console.log('\n' + how + '\n'); }
  else out('윈도우 — 로그온하면 자동으로 켜집니다', body, where, how);

} else {
  const where = path.join(HOME, '.config', 'systemd', 'user', 'mybody.service');
  const body = `[Unit]
Description=Mybody 자가호스팅 서버
After=network-online.target

[Service]
Type=simple
WorkingDirectory=${ROOT}
ExecStart=${NODE} ${SERVE}
Restart=always
RestartSec=5

[Install]
WantedBy=default.target`;
  const how = `systemctl --user daemon-reload
systemctl --user enable --now mybody       # 걸기
systemctl --user status mybody             # 지금 상태
journalctl --user -u mybody -f             # 뭐라고 하는지 보기
# 요청 줄을 아예 안 남기려면 위 [Service] 에:  Environment=LOG=0
sudo loginctl enable-linger $USER          # 로그아웃해도 계속 돌게`;
  if (WRITE) { writeFile(where, body); console.log('\n' + how + '\n'); }
  else out('리눅스 — 켜지면 자동으로 켜집니다 (systemd user)', body, where, how);
}

if (!WRITE) {
  console.log('  이대로 만들어 드릴까요:  node tools/autostart.js ' + (DAEMON && process.platform === 'darwin' ? '--daemon --write' : '--write'));
  console.log('');
  console.log('  서버는 요청 한 줄씩(시각·방식·경로·상태·시간)을 찍습니다.');
  console.log('  계정 번호는 앞 네 글자만 남기고 가립니다. 아예 안 남기려면');
  console.log('  위 설정에 LOG=0 을 넣으세요 — 대신 고장을 쫓기 어려워집니다.');
  console.log('');
}
if (!WRITE && !(DAEMON && process.platform === 'darwin')) {
  console.log('  터널도 같이 떠 있어야 밖에서 접속됩니다. 자동 시작은 서버만 띄웁니다 —');
  console.log('  launch.js 가 여는 주소는 그 창을 닫으면 같이 닫힙니다.');
  console.log('  Tailscale 이면 한 번만:  tailscale funnel --bg ' + PORT + '   (맥 · 리눅스는 앞에 sudo · 재부팅해도 유지)');
  console.log('  그 뒤로 그 컴퓨터에서는 launch.js 를 쓰지 마세요 — 창을 닫으면 같이 닫히는');
  console.log('  launch.js 의 주소와 부딪힙니다. 다시 띄우기는 위의 "다시 띄우기" 로.');
  console.log('  cloudflared 는 자기 서비스 설치 기능이 있습니다 — Cloudflare 문서를 보세요.');
  console.log('');
}
