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
tail -f "${path.join(logDir, 'mybody.log')}"   # 뭐라고 하는지 보기`;
  if (WRITE) { writeFile(where, body); console.log('\n걸려면:\n  launchctl load -w "' + where + '"\n'); }
  else out('macOS — 로그인하면 자동으로 켜집니다', body, where, how);

} else if (process.platform === 'win32') {
  const where = path.join(ROOT, 'mybody-autostart.cmd');
  const body = `@echo off\r\ncd /d "${ROOT}"\r\n"${NODE}" "${SERVE}"\r\n`;
  const how = `작업 스케줄러(taskschd.msc)를 열고
  1. "작업 만들기"
  2. 트리거: "로그온할 때"
  3. 동작: 프로그램 시작 → "${where}"
  4. 조건 탭에서 "컴퓨터가 배터리로 전환되면 중지" 를 끄세요`;
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
sudo loginctl enable-linger $USER          # 로그아웃해도 계속 돌게`;
  if (WRITE) { writeFile(where, body); console.log('\n' + how + '\n'); }
  else out('리눅스 — 켜지면 자동으로 켜집니다 (systemd user)', body, where, how);
}

if (!WRITE) {
  console.log('  이대로 만들어 드릴까요:  node tools/autostart.js --write');
  console.log('');
  console.log('  터널도 같이 떠 있어야 밖에서 접속됩니다. cloudflared 는');
  console.log('  자기 서비스 설치 기능이 있습니다 — Cloudflare 문서를 보세요.');
  console.log('');
}
