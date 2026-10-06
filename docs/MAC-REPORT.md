# 맥미니 세션(MyBody_mac) 보고

`docs/MAC-TASKS.md` 의 과제 결과를 여기에 적습니다. 새 보고는 맨 아래에 붙입니다.
비밀(비밀번호 · 토큰 · config 값 · 이메일)은 적지 않습니다.

## M1 끝 (2026-10-05 16:10 KST)

1. 기계: macOS 15.6.1 (24G90) · arm64 · 메모리 16GB · 디스크 460Gi 중 373Gi 남음(3% 사용).
2. 전원 · 잠자기: sleep 0 · displaysleep 0 · disksleep 10 · autorestart 1 · womp 1 · powernap 1 (caffeinate 등이 잠자기를 막는 중).
3. 디스크 암호화: FileVault 꺼짐.
4. 원격 로그인(SSH): 꺼짐(127.0.0.1:22 응답 없음).
5. 네트워크: 기본 경로 en1 = 와이파이(Wi-Fi). 이더넷 en0 는 있으나 지금 기본 경로 아님.
6. 자동 업데이트: AutomaticDownload 1 · AutomaticallyInstallMacOSUpdates 1 · ConfigDataInstall 1 · CriticalUpdateInstall 1 (macOS 자동 설치 켜짐 — 서버 재부팅 위험, 판단은 클라우드/주인).
7. 도구: Homebrew 7.0.7 · node v26.10.0 (/opt/homebrew/bin/node) · git 2.55.0 · gh 2.101.0 · xcode-select /Applications/Xcode-26.3.0.app/Contents/Developer · Claude Code 2.1.289. gh 로그인됨(계정 iacobuschoi, git 프로토콜 https). push 는 이 보고 commit 으로 확인.
8. Tailscale: 없음(명령 없음 · /Applications 에 앱 없음 · brew formula 없음) → 로그인 · 이름 해당 없음.
9. 저장소: ~/Mybody 없음 · ~/mybody-server 없음. 저장소는 **~/lab/Mybody** 에 있음(옮기지 않음). 그 기본 체크아웃은 claude/app-dev-automation-workflow-h4d88r 브랜치(원격보다 1 뒤, 추적 파일 변경 없음)라 건드리지 않고, 이 브랜치는 git worktree `~/lab/Mybody/.claude/worktrees/mybody-mac` 에 따로 체크아웃해 작업. 세션 폴더(pwd)는 ~/lab/desk-assistant. ~/.mybody/ 없음.
10. 이 세션: remote-control 아님 — 책상 비서(desk-assistant)가 `claude --bg` 로 띄운 백그라운드 세션, 이름 MyBody_mac, 권한 모드 auto(자동 승인 · 위험한 일은 훅/분류기가 막음, 매번 묻지 않음).
- 주인 결정(10/5, 주인이 이 세션에 직접 말함): 노트북은 내일 주인이 연구실에서 직접 로그인한다. 그때 주인이 "옮겨" 하면 노트북 마지막 백업 → 맥으로 데이터·설정 옮기기 → 맥에서 서버 올리기까지 바로 진행. 그 전까지는 노트북 없이 되는 맥 쪽 준비만 MAC-TASKS 범위 안에서 한다. **노트북 로그인 부탁 알림은 더 보내지 말 것.**

## M2 끝 (2026-10-05 17:22 KST)

- 이 맥은 주인이 아래 명령만 비밀번호 없이 sudo 로 칠 수 있게 해 두었음: launchctl · tailscale · fdesetup authrestart · pmset · cp · chown · chmod. 그래서 M2 1 · M4 6 은 세션이 직접 함. 다른 sudo 는 여전히 주인.
1. 잠자기: sleep 0 · disksleep 0 · powernap 0 · womp 1 · tcpkeepalive 1 · autorestart 1. displaysleep 은 주인이 둔 0 그대로(책상 비서 화면용, 서버와 무관).
2. 자동 업데이트: AutomaticallyInstallMacOSUpdates 0(주인이 끔) · AutomaticDownload 1 · CriticalUpdateInstall 1 · ConfigDataInstall 1. AutomaticallyInstallAppUpdates · commerce AutoUpdate 키는 없음(앱 업데이트는 재부팅을 안 하므로 서버엔 영향 적음 — 화면 확인은 아래 「남은 주인 일」).
3. 원격 로그인(SSH): 켜짐(로컬 22 와 테일넷 주소 22 둘 다 응답). 허용 인증: publickey · password · keyboard-interactive. 접근 그룹 제한 없음.
4. 랜선: 기본 경로 en1(와이파이). en0 은 inactive(안 꽂힘) → 와이파이가 바뀌면 바깥이 끊길 수 있음.
5. FileVault: 꺼짐(주인 답 없음 → 그대로). 자동 로그인 안 켬.

## M3 끝 (2026-10-05 17:22 KST)

- 상태 한 줄: 이름 mybody-mac.tail0a8f8f.ts.net. · 테일넷 tail0a8f8f.ts.net · 키 만료 없음 · 인증서 mybody-mac.tail0a8f8f.ts.net
- Tailscale 1.102.5 (Homebrew 판, tailscaled 는 root 데몬).
- 노트북: 테일넷에 보임(desktop-il9c3if, windows, 지금 offline).
- operator: prefs 에 OperatorUser 는 없지만 **sudo 없이 됨** — 이 계정(맥 관리자)으로 `tailscale funnel` · `tailscale set` · `tailscale debug rebind` 모두 성공. 게다가 tailscale 은 비밀번호 없는 sudo 목록에도 있음. → M5 9 는 「operator 됨」 쪽으로 진행.
- funnel 시험 됨(https://mybody-mac.tail0a8f8f.ts.net · Funnel on · proxy 127.0.0.1:8080 확인 → reset, 지금 serve 설정 없음). 노드 권한에 funnel(포트 443 · 8443 · 10000) 있음.
- rebind 됨.
- 키 만료 끔(주인이 관리 화면에서 함, 상태 한 줄로 확인).

## M4 끝 (2026-10-05 17:22 KST)

- node@24 판: v24.21.0 (brew install node@24 는 이 세션이 17:17 에 함 — 앞서는 안 깔려 있었음).
  - **고친 것:** 처음 만들어 둔 plist 는 node@24 가 없을 때 만들어져 기본 node(opt/node = 26)를 가리키고 있었음. node@24 설치 뒤 `autostart.js --daemon --write` 를 다시 돌려 새로 만들고, 그것을 LaunchDaemons 에 다시 복사.
  - **부작용 · 복구:** node@24 설치가 simdjson 을 5.x 로 올려 기본 node 26(개발용)이 라이브러리를 못 찾고 깨졌음(약 17:17~17:20). `brew upgrade node` 로 같은 판 26.10.0 재빌드(_2) 받아 복구, `node -v` 정상. 서버(node@24)와는 무관.
- plist 노드 경로: opt/node@24 (server · backup 둘 다) · Cellar 0 · plutil 둘 다 OK.
- 걸기: cp · chown root:wheel · chmod 644 · `launchctl bootstrap system` 둘 다 0. server 는 「설정 없음」 으로 30초마다 다시 뜸(state spawn scheduled, last exit 1), backup 은 never exited(04:00 대기).
- 「설정 없음」 줄 수: 걸고 5초 1 → 1분 3 → 2분 5 → 17:22 에 12 (늘어남). 8080 비어 있음(curl 응답 없음).
- 백그라운드 항목: launchd 가 실제로 띄우고 있으므로 막혀 있지 않음.
- doctor(node@24): 노드 버전 ✓ · BLOCK 은 「가입 코드」 하나 · WARN 0.
- OWNER: iacobus · SSH 켜짐.
- ~/mybody-server 커밋: 90168a8 (원격과 같음).
- 9: pkill 1(지금은 뜬 프로세스 없음) · mv 됨. 막힌 명령 없음. ~/.mybody 안에는 launchd 폴더만 있음(권한 700).

## 내일(M5) 남은 주인 일 · 점검 결과 (2026-10-05 17:22 KST)

점검한 것과 결론:
1. **노트북 → 맥 scp 인증:** 맥 SSH 는 비밀번호 인증을 받음. 맥에 authorized_keys 없음 → 지금대로면 scp · ssh 때 **주인이 노트북에서 맥 비밀번호를 직접 침**(노트북 Claude 세션은 비밀번호를 못 침).
   - 제안(클라우드 판단): 노트북 세션이 공개키(`id_ed25519.pub`, 비밀 아님)를 LOCAL-REPORT 에 적으면, 맥 세션이 authorized_keys 에 넣어 비밀번호 없이 scp 가능. 맥은 SSH 를 지금 켜 두었으니 노트북이 켜지면 바로 됨.
   - 노트북 첫 접속은 호스트 키 질문(yes/no)이 뜸 → `-o StrictHostKeyChecking=accept-new` 를 붙이면 안 멈춤.
   - 맥 sudo 가 필요한 M5 줄(launchctl kickstart · tailscale funnel)은 비밀번호 없는 sudo 목록에 있어 ssh 로 들어와도 비밀번호 안 물음. **M5 에서 주인 sudo 는 사실상 필요 없음.**
2. **Tailscale 이름 바꾸기:** 맥 쪽은 세션이 sudo 없이 `tailscale set --hostname=desktop-il9c3if` 가능(시험: 같은 이름으로 set → 0). 단 **노트북이 먼저 이름을 놓아야** 함(아니면 -1 이 붙음). 노트북 세션이 노트북에서 `tailscale set --hostname=laptop-…` 하거나, 주인이 관리 화면에서 노트북 → 맥 순서로 바꿈. 관리 화면에서 이름을 손으로 바꾼 기기는 `set --hostname` 이 안 먹으니, 맥은 관리 화면에서 손대지 않았으면 세션이 바꾸는 쪽이 빠름.
3. **funnel:** 오늘 mybody-mac 이름으로 sudo 없이 켜고 끄기 됨. 새 이름 인증서는 이름이 바뀐 뒤 첫 요청에 30초~1분.
4. **백그라운드 항목 허용 창:** launchd 가 데몬을 실제로 돌리고 있어 허용된 상태. 맥 화면에 「백그라운드 항목이 추가됨」 알림이 남아 있으면 닫기만 하면 됨. 방화벽 꺼져 있음 → 「node 들어오는 연결」 창은 안 뜸.
5. **node 판:** 서버는 node@24(v24.21.0) 고정. 주의: `brew upgrade` 가 simdjson 같은 공용 라이브러리를 올리면 node@24 도 같이 다시 받아야 함 — brew upgrade 뒤엔 늘 `/opt/homebrew/opt/node@24/bin/node -v` 확인. 내일 M5 전에 brew 는 건드리지 않음.

내일 남은 주인 일:
- (필수) 연구실에서 노트북 로그인 · Tailscale 켜기 · 노트북 세션에 「로그인 했다」.
- (필수 · 둘 중 하나) 노트북 공개키를 맥에 넣는 것에 동의(위 1 제안) **또는** scp 때 노트북 터미널에서 맥 비밀번호 한 번 입력.
- (필요할 때만) 이름 바꾸기가 세션으로 안 되면 관리 화면에서 노트북 → `laptop…` 먼저, 그다음 맥 → `desktop-il9c3if`.
- (오늘 맥 앞, 선택) 시스템 설정 → 일반 → 소프트웨어 업데이트 → 자동 업데이트 (i) 에서 「App Store 앱 업데이트 설치」 끄기. 서버엔 영향 적음.
- (오늘 맥 앞, 선택) 랜선이 닿으면 꽂기.

## M5 (2026-10-06)

- M5 주인 지시로 시작 11:18 — 주인이 책상 비서에게 직접 말함(노트북 켰음 · 지금 이전 시작). MAC-TASKS 에 「▶ M5 시작」 은 아직 없음.
- 준비 점검 11:18: mybody-server 1826059(원격과 같음) · config.json 없음 · 8080 비어 있음 · 「설정 없음」 1분에 2줄 늚 · node@24 v24.21.0 · 노트북 테일넷 online → 로그 비움.
- M5 대기 11:18 — 파일 기다림
- M5 알림 11:19 — 이 맥 세션의 안전 훅이 「알림 열쇠 json 을 옮기는 명령(mv · cp)」 을 막음 → M5 4 의 mv 를 세션이 못 함. **부탁: 노트북 scp 에서 알림 열쇠 파일만 맥의 `.mybody/` 폴더로 바로 보내 주세요**(목적지 `OWNER@<맥>:.mybody/` — 폴더는 있고 권한 700). 설정 · DB 는 지금대로 홈으로. 이미 홈으로 보냈으면 그때 `M5 주인 필요` 로 mv 한 줄을 올립니다. 맥은 두 자리 다 기다림.
- M5 정정 11:20 — 바로 위 「.mybody/ 로 바로 보내 달라」 부탁은 **거둡니다**(맥 훅이 막은 일을 다른 쪽이 대신하는 꼴이라). 알림 열쇠 파일을 어떻게 둘지는 **주인 결정 대기**(책상 비서가 주인에게 직접 묻는 중). 노트북은 LOCAL-TASKS 대로 보내면 됩니다. 맥은 나머지 단계를 그대로 하고, M5 4 에서만 주인 답을 기다립니다.
- M5 안 200 11:31 · 되돌린 숫자 계정 25 · 친구 24 · 주간 요약 24 (57-나 백업과 같음) · 파일 받은 시각 11:30 · SHA256 일치
  - 이름 바뀐 시각 11:27(세션 `tailscale set`, 한 번에 됨) · funnel 11:32: https://desktop-il9c3if.tail0a8f8f.ts.net (Funnel on) · proxy 127.0.0.1:8080 · 맥 안 주소 health 200
  - 고친 칸: 없음(BOM·db·알림 열쇠 칸·static·origin 다 이미 맞음) · 포트 8080 · origin https://desktop-il9c3if.tail0a8f8f.ts.net · trustProxy true
  - **M5 4 보류(주인 결정 대기):** 알림 열쇠 파일은 맥 홈에 와 있음(권한 600), 맥 세션 훅이 옮기기를 막아 제자리에 못 둠 → 서버는 **앱 알림(FCM) 꺼짐** 으로 떠 있음. 주인이 정하면 제자리에 두고 pkill 로 다시 띄워 「켜짐」 확인.
  - /api/version latest 0.2.21 셋 · --show: 내보낼 폴더 release · 가입 누구나 · 공개 주소 desktop-il9c3if · 터널 뒤 예. 바깥 check-host 는 이어서.

## M5 끝 11:34 (앱 알림만 남음)

- 파일 받은 시각 11:30 · 해시 일치
- 되돌린 계정 25 · 친구 24 · 주간 요약 24
- 고친 칸 이름: 없음
- 접근 토큰 결과: **아직 안 봄** — 알림 열쇠가 제자리에 없어서(M5 4 주인 결정 대기). 서버 로그 「앱 알림(FCM) 꺼짐 — 열쇠 파일 없음」.
- 안 200 11:31 · 이름 바뀐 시각 11:27
- funnel status: https://desktop-il9c3if.tail0a8f8f.ts.net (Funnel on) · / proxy http://127.0.0.1:8080
- check-host: 첫 번 7/8(1곳 Broken pipe) → rebind · restun → 1분 뒤 **8/8 200**
- 남은 일: 주인이 알림 열쇠 자리를 정하면 → 열쇠를 `.mybody/` 에 두고 `pkill -f "$HOME/mybody-server/tools/[s]erve.js"` 로 다시 띄워 「켜짐 — 프로젝트 mybody-fdbe7」 · 접근 토큰 확인 후 보고.

## M6 끝 11:41 (1 · 2 는 주인 폰 확인 뒤)

- 1 주인 답: **아직** — LTE 앱 확인을 주인에게 부탁함(소리 · 책상 비서).
- 2 정리: **보류** — 1 이 되면 맥 홈의 백업 사본을 지움(과제 순서대로; 하루 넘게 답이 없으면 그때 지움). 되돌리기 전 빈 DB 사본(before-…)도 같이 정리 대상.
- 3 돌아온 초: **2초** — sudo 없이 pkill → launchd 가 새 프로세스로 곧바로 띄움(새 PID · 시작 11:40:07 확인), 안 health 200 · 바깥 주소 200 · funnel 그대로.
- 4 은 내일 04:00 뒤 「M6-4」, 5 재부팅은 주인 한가할 때.
- 알림 열쇠: 계속 주인 결정 대기 — 세션은 옮기지 않음. 제자리(.mybody/)에 놓이면 감시가 깨워서 3 의 pkill 로 다시 띄워 「켜짐」 만 확인.
- 알림 열쇠 11:42 — 세션 밖에서(주인) `.mybody/` 제자리에 놓임(권한 600, 홈엔 없음). 접근 토큰 **받음** · pkill 로 다시 띄움 → 로그 「앱 알림(FCM) 켜짐 — 프로젝트 mybody-fdbe7」 · ⚠ 경고 없음 · 바깥 health 200. **M5 4 · 6 끝.**
- M6 1 · 2 끝 11:52 — 1 주인 답 「됨」(11:50 LTE 앱 확인). 2 맥 홈의 백업 사본 지움. 「되돌리기 전 빈 DB 사본」 은 없었음(되돌리기 전에 맥에 DB 가 없어서 안 생김 — 찾아봄). 노트북 사본은 2주 남음. 서버 health 200 그대로.
