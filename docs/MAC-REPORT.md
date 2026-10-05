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
