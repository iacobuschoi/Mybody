# 맥미니 세션(MyBody_mac)이 할 일

클라우드 세션(MyBody)이 적습니다. **이 파일이 맥의 우편함**입니다. 노트북 세션의 우편함
(`docs/LOCAL-TASKS.md`)과 따로 둡니다. 서버를 옮기는 동안에는 두 세션이 같이 돌기 때문입니다.

- 클라우드는 이 파일에 과제를 적은 뒤, 이 세션에 「git pull 하고 MAC-TASKS 의 M<번호>」 라는 메시지를
  보내 깨웁니다. 메시지가 없어도 이 파일이 기준입니다.
- 결과는 `docs/MAC-REPORT.md` 에 적고 **그 파일만** 커밋 · push 합니다. 코드는 클라우드가 고칩니다.
- 브랜치: `claude/body-management-app-prototype-m4mv4k` 하나. 시작 전에 `git pull`,
  **밀기 전에 늘 `git fetch` 와 rebase**. 클라우드와 노트북도 같은 브랜치에 밉니다.
- 전체 안내서는 `docs/MAC.md` 입니다. 과제에 적힌 절만 합니다. 안내서의 다른 절을 앞질러 하지 않습니다.
- **[주인]** 표시는 맥 비밀번호(sudo) · 화면 클릭 · 로그인 링크가 필요한 일입니다. 그 줄은 하지 말고
  주인에게 「터미널에 이것을 붙여 넣어 주세요」 라고 명령을 보여 준 뒤 기다립니다.
- 비밀은 저장소와 보고에 적지 않습니다: 비밀번호 · 토큰 · `~/.mybody/config.json` 의 값 · 이메일 ·
  `server/*.db` · 열쇠 파일. 보고에는 개수 · 상태 · 판 번호만 적습니다.
- `prototype/` 의 웹 화면은 고치지 않습니다. `tools/test-selfhost.js` 는 돌리지 않습니다.
- 플레이 프로덕션 출시 · 프로덕션 액세스 신청은 하지 않습니다(주인 승인 사항).

---

## M1. 맥 상태 보기 — 읽기만 (10/5 16:05 · 주인 "맥미니 M1 으로 서버 옮길거에요 · 기본 세팅은 돼 있음")

아무것도 설치 · 변경하지 않습니다. sudo 도 쓰지 않습니다. 아래를 보고 한 줄씩 적습니다.

1. 기계: `sw_vers` · `uname -m` · 메모리(`sysctl -n hw.memsize`) · 남은 디스크(`df -h /`).
2. 전원 · 잠자기: `pmset -g | egrep 'sleep|autorestart|womp|powernap'`.
3. 디스크 암호화: `fdesetup status`.
4. 원격 로그인(SSH): `nc -z -G 2 127.0.0.1 22 && echo 켜짐 || echo 꺼짐`.
5. 네트워크: 지금 인터넷이 이더넷인지 와이파이인지(`route -n get default | grep interface` → `networksetup -listallhardwareports` 에서 그 장치 이름).
6. 자동 업데이트: `defaults read /Library/Preferences/com.apple.SoftwareUpdate 2>/dev/null | egrep 'Automatic|Critical|Config'`.
7. 도구 판: `brew --version` · `which node` · `node -v` · `git --version` · `gh --version` · `xcode-select -p` · `claude --version`.
   - GitHub 로그인: `gh auth status` 는 **로그인됐는지 · 계정 이름**만 적습니다(토큰 줄은 적지 않음).
   - 이 저장소에 push 가 되는지는 4번째 줄의 보고 push 로 확인됩니다.
8. Tailscale: `which tailscale` · `tailscale version` · `tailscale status 2>&1 | head -3` ·
   `ls /Applications | grep -i tailscale` · `brew list --formula 2>/dev/null | grep -i tailscale`.
   → 어느 판인지(Homebrew 판 / App Store · Standalone 앱 / 없음), 로그인 됐는지, 이 맥의 Tailscale 이름.
9. 저장소: `ls -d ~/Mybody ~/mybody-server 2>&1` · `git -C ~/Mybody status -sb | head -3` ·
   이 세션이 도는 폴더(`pwd`). `~/.mybody/` 가 있는지만(안의 값은 읽지 않음).
10. 이 세션: `claude remote-control` 로 켰는지, 세션 이름, 권한 모드(질문하면 묻는 방식인지).

보고: `docs/MAC-REPORT.md` 맨 아래에 "M1 끝 (날짜 시각 KST)" + 위 1~10 한 줄씩 → 그 파일만 commit · push.
push 가 인증 때문에 막히면 **[주인]** 으로 `gh auth login --web` → `gh auth setup-git` 을 보여 주고 기다립니다.
