/* =============================================================================
 * tools/autostart.js — 컴퓨터를 켜면 서버도 같이 켜지게
 *
 *   node tools/autostart.js            내 OS 에 맞는 설정을 보여줍니다
 *   node tools/autostart.js --write    실제로 파일을 만들고 거는 법까지
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

const ROOT = path.join(__dirname, '..');
const NODE = process.execPath;          // 지금 돌고 있는 노드의 전체 경로
const SERVE = path.join(ROOT, 'tools', 'serve.js');
const HOME = os.homedir();
const WRITE = process.argv.includes('--write');
const LABEL = 'com.mybody.server';

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

if (process.platform === 'darwin') {
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
    <string>${NODE}</string>
    <string>${SERVE}</string>
  </array>
  <key>WorkingDirectory</key><string>${ROOT}</string>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>${path.join(logDir, 'mybody.log')}</string>
  <key>StandardErrorPath</key><string>${path.join(logDir, 'mybody.log')}</string>
</dict>
</plist>`;
  const how = `launchctl load -w "${where}"      # 걸기
launchctl unload -w "${where}"    # 풀기
tail -f "${path.join(logDir, 'mybody.log')}"   # 뭐라고 하는지 보기

# 이 파일은 회전도 보유 기간도 없이 계속 자랍니다.
# 요청 한 줄씩이라 느리게 자라지만, 몇 달이면 큽니다.
# 가끔 비우기:  : > "${path.join(logDir, 'mybody.log')}"
# 아예 안 남기려면 위 plist 에 이 두 줄을 넣으세요:
#   <key>EnvironmentVariables</key><dict><key>LOG</key><string>0</string></dict>`;
  if (WRITE) { writeFile(where, body); console.log('\n걸려면:\n  launchctl load -w "' + where + '"\n'); }
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
  console.log('  이대로 만들어 드릴까요:  node tools/autostart.js --write');
  console.log('');
  console.log('  서버는 요청 한 줄씩(시각·방식·경로·상태·시간)을 찍습니다.');
  console.log('  계정 번호는 앞 네 글자만 남기고 가립니다. 아예 안 남기려면');
  console.log('  위 설정에 LOG=0 을 넣으세요 — 대신 고장을 쫓기 어려워집니다.');
  console.log('');
  console.log('  터널도 같이 떠 있어야 밖에서 접속됩니다. cloudflared 는');
  console.log('  자기 서비스 설치 기능이 있습니다 — Cloudflare 문서를 보세요.');
  console.log('');
}
