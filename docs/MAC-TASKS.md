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

---

> **▶ 지금(10/5 17:10) 할 것: M2 · M3 · M4 를 같이.** 주인이 오늘 맥 앞에 있습니다. [주인] 줄은 M2 머리말대로 한 블록으로 합쳐 보여 주세요.
> 주인 답이 아직 없으면: **FileVault 는 끈 채로**(M2 5) · **operator 는 넣어서**(M3 2 — 주인이 블록에서 `--operator=$USER` 를 빼면 안 함으로 봄).
> **M5 는 내일, 클라우드가 이 파일에 「▶ M5 시작」 을 적은 뒤에만** 합니다. M6 은 M5 뒤.

## M2. 맥 기본 설정: 잠자기 · 자동 업데이트 · 원격 로그인 · 랜선 (10/5 · M1 보고 기준 · MAC.md 2-3~2-6)

M1 에서 모자랐던 것만 고칩니다. 하기 전에 값을 다시 읽어 보고, 이미 맞으면 건너뜁니다.

- **이 저장소는 공개입니다.** 보고에 `/Users/…` 경로, `ls -l` 출력, 로그 줄, 100.x 주소를 붙이지 않습니다.
- 이 세션은 auto 모드로 도는 백그라운드 세션입니다(M1 10). 그래서 **sudo 는 늘 주인이 칩니다.**
- 주인은 **오늘은 맥 앞에** 있고, **옮기는 날(내일)에는 연구실 노트북 앞에** 있습니다. 주인 손이 드는 맥 일은 **오늘 다 끝냅니다.**
- **M2 · M3 · M4 를 같이 받았으면** sudo 없는 일을 먼저 다 합니다(M3 1, M4 1~5).
  - 그다음 **[주인]** 줄을 **한 블록으로 합쳐** 보여 줍니다. 순서는 M2 1·2·3 → M4 6 → M3 2 입니다.
  - M3 2 의 `tailscale up` 은 로그인 링크를 기다리므로 맨 끝에 둡니다. 한 창에서 이어 치면 비밀번호를 한 번만 묻습니다.

1. 잠자기 (M1 2: disksleep 10 · powernap 1) → **[주인]**
   ```
   sudo pmset -a sleep 0 disksleep 0 displaysleep 10 powernap 0 womp 1 tcpkeepalive 1 autorestart 1
   ```
   확인(세션): `pmset -g | egrep ' sleep|disksleep|powernap|womp|autorestart'` → sleep 0 · disksleep 0 · powernap 0 · womp 1 · autorestart 1.
2. 자동 업데이트 (M1 6: macOS 자동 설치 켜짐) → **[주인]**. 밤에 저절로 재부팅되면 서버가 멈춥니다.
   ```
   sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticallyInstallMacOSUpdates -bool false
   sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticallyInstallAppUpdates -bool false
   sudo defaults write /Library/Preferences/com.apple.commerce AutoUpdate -bool false
   ```
   - 받기(AutomaticDownload)와 보안 대응(CriticalUpdateInstall · ConfigDataInstall)은 켠 채로 둡니다.
   - 확인(세션): M1 6 의 명령 → AutomaticallyInstallMacOSUpdates 0 · AutomaticallyInstallAppUpdates 0.
   - **[주인]** 화면도 한 번 봅니다. 시스템 설정 → 일반 → 소프트웨어 업데이트 → 자동 업데이트 (i) 에서 「macOS 업데이트 설치」 와 「App Store 앱 업데이트 설치」 가 꺼져 있어야 합니다. 켜져 있으면 끕니다.
   - macOS 판 올리기(15.6.1 → 26, MAC.md 2-2)는 **지금 하지 않습니다.** 옮긴 뒤 주인이 집에 있을 때 따로 합니다.
3. 원격 로그인 SSH (M1 4: 꺼짐) → **[주인]**
   - 노트북이 이 길로 파일을 보냅니다. 내일 주인이 연구실에서 맥 sudo 를 칠 때도 이 길을 씁니다.
   ```
   sudo systemsetup -setremotelogin on
   ```
   - "Full Disk Access" 오류가 나면 화면에서 켭니다. 시스템 설정 → 일반 → 공유 → **원격 로그인** 켬 → (i) → 허용할 사용자를 「이 사용자만」 으로.
   - 확인(세션): `nc -z -G 2 127.0.0.1 22 && echo 켜짐 || echo 꺼짐` → 켜짐.
4. 랜선 (M1 5: 와이파이 en1) → **[주인]**
   - 공유기까지 랜선이 닿으면 꽂습니다. 와이파이는 예비로 켜 둡니다.
   - 확인(세션): `route -n get default | grep interface` → en0 이면 끝입니다.
   - 꽂았는데도 en1 이면 **[주인]** 시스템 설정 → 네트워크 → 아래 「…」 → 서비스 순서 설정에서 이더넷을 맨 위로 올립니다.
   - 못 꽂으면 그대로 갑니다. 보고에 「와이파이가 바뀌면 바깥이 끊길 수 있음」 이라고 한 줄 적습니다.
5. FileVault (M1 3: 꺼짐) → **[주인 결정]**. 이 과제에서는 바꾸지 않습니다.
   - 끄면: 맥을 도난당했을 때 친구들 건강 기록과 비밀 키를 읽을 수 있습니다.
   - 켜면: 이 맥은 macOS 15 라서, 정전 뒤 **맥 앞에서** 비밀번호를 넣어야 서버가 뜹니다. SSH 로 원격에서 푸는 기능은 macOS 26 부터입니다(MAC.md 2-3).
   - 클라우드 메시지에 주인 답이 있으면 그대로 따릅니다.
     - 「켬」 이면 **[주인]** 시스템 설정 → 개인정보 보호 및 보안 → FileVault 를 켭니다. 복구 키는 주인이 따로 보관하고 보고에 적지 않습니다.
     - 답이 없으면 끈 채로 둡니다. macOS 26 으로 올릴 때 다시 정합니다.
   - 어느 쪽이든 자동 로그인은 켜지 않습니다.

보고: "M2 끝" + 1~4 의 확인 값을 한 줄씩 + 5 의 상태.

## M3. Tailscale: Homebrew 판 · 이름 `mybody-mac` · Funnel 미리 시험 (MAC.md 7-1 · 서버는 안 멈춤)

M1 8 에서 Tailscale 은 없었습니다. 그래서 새로 깝니다. App Store 판이나 Standalone 앱은 쓰지 않습니다. Homebrew 판과 같이 못 돕니다.

1. 세션: `brew install tailscale` (sudo 없음).
2. **[주인]** 합친 블록의 맨 끝에 넣습니다:
   ```
   sudo brew services start tailscale
   sleep 3
   sudo tailscale up --hostname=mybody-mac --operator=$USER
   ```
   - 셋째 줄이 링크를 찍고 기다립니다. 링크를 열어 **노트북과 같은 Tailscale 계정**으로 로그인합니다.
   - `--operator=$USER` 를 넣으면 이 세션이 sudo 없이 `tailscale funnel` · `tailscale debug` 를 칠 수 있습니다. 그러면 내일 주인이 맥 앞에 없어도 주소를 열 수 있습니다.
     - 대신 이 맥 계정으로 도는 **모든 프로그램**도 sudo 없이 Tailscale 을 바꿀 수 있게 됩니다(주소 열고 닫기, 로그아웃).
     - 클라우드 메시지에 「operator 안 함」 이 있으면 이 부분을 빼고 보여 줍니다.
     - 나중에 되돌리려면 `sudo tailscale set --operator=` 를 칩니다.
3. 확인(세션). 아래 명령을 「상태 한 줄」 이라고 부릅니다. M5 에서도 씁니다.
   ```
   tailscale status --json | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const j=JSON.parse(s),m=j.Self||{};console.log("이름 "+m.DNSName+" · 테일넷 "+j.MagicDNSSuffix+" · 키 만료 "+(m.KeyExpiry||"없음")+" · 인증서 "+(j.CertDomains||[]).join(","))})'
   ```
   - 테일넷이 **`tail0a8f8f.ts.net`** 이어야 합니다.
     - 다르면 다른 계정으로 로그인한 것이고, 그러면 주소도 달라집니다.
     - 그때는 **[주인]** `sudo tailscale logout` 을 친 뒤 2 를 다시 합니다.
   - 이름이 `mybody-mac.tail0a8f8f.ts.net.` 이어야 합니다.
   - `tailscale status | grep desktop-il9c3if` 로 노트북이 보이면 같은 테일넷입니다. offline 으로 보여도 됩니다. 노트북은 내일 로그인하기 전까지 꺼진 채로 보일 수 있습니다.
4. Funnel 미리 시험. **오늘 끝냅니다.** 내일은 주인이 맥 앞에 없습니다.
   - 8080 에는 아직 아무것도 없습니다. 그래서 몇 초 동안 `mybody-mac` 주소가 502 를 낼 뿐입니다.
   ```
   tailscale funnel --bg 8080 && tailscale funnel status; tailscale funnel reset
   tailscale debug rebind && echo rebind 됨
   ```
   - 「Funnel 을 켜라」 는 링크가 찍히고 멈춰 있으면, 주인에게 링크를 보여 줍니다. **[주인]** 이 지금 누르고, 다시 시험합니다.
   - "access denied" 같은 말이 나오면(operator 안 됨 또는 안 함) **[주인]** 이 같은 줄에 `sudo` 를 붙여 칩니다. 그 경우 내일은 이 줄들을 주인이 노트북에서 ssh 로 들어와 칩니다(M5 머리말).
   - status 에 `https://mybody-mac.tail0a8f8f.ts.net` 과 Funnel on 이 보였으면 「funnel 시험 됨」 입니다.
   - auto 모드가 명령을 막으면 막힌 명령을 보고에 적습니다.
5. **[주인]** <https://login.tailscale.com/admin/machines> → `mybody-mac` → ⋯ → **Disable key expiry**.
   - 그냥 두면 180일 뒤 조용히 로그아웃되고, 주소가 죽습니다.
   - 확인(세션): 상태 한 줄의 키 만료가 「없음」.
6. 관리 화면에서 이름 바꾸기와 진짜 `funnel --bg` 는 M5 에서만 합니다.

보고: "M3 끝" + 상태 한 줄 · 노트북이 테일넷에 보이는지 · operator 됨/안 됨/안 함 · funnel 시험 됨/안 됨 · rebind 됨/안 됨. 로그인 계정과 이메일은 적지 않습니다.

## M4. 서버 사본 · node@24 · 자동 시작 미리 걸기 (MAC.md 7-1 + 7-2 의 5 · 서버는 안 멈춤)

MAC.md 7-2 의 5번(자동 시작 걸기)을 **지금으로 앞당깁니다.** MAC.md 와 다르면 **이 과제를 따릅니다.**
- 설정 파일 `~/.mybody/config.json` 은 아직 없습니다. 그래서 서버는 뜨지 않고, 30초마다 「아직 설정이 없습니다」 만 찍습니다.
- 옮기는 날 설정 파일을 제자리에 넣으면, 그 순간 서버가 저절로 뜹니다. 서버가 멈춘 동안 주인 sudo 가 필요 없습니다.

M1 7 을 보면 이 맥의 기본 `node` 는 26 입니다. 서버는 **node@24** 로만 돌립니다.
- 그냥 `node` 는 `brew upgrade` 때 큰 판으로 바뀌어 버립니다.
- 기본 `node`, PATH, `~/lab/Mybody`(개발 사본)는 건드리지 않습니다.
- 아래 `N` 은 늘 이 값입니다. 명령마다 앞에 이 줄을 붙입니다:
```
N=/opt/homebrew/opt/node@24/bin/node
```

1. `brew install node@24` → `$N -v` 가 v24.x 인지 봅니다.
2. 서버 사본을 만듭니다:
   ```
   git clone -b claude/body-management-app-prototype-m4mv4k https://github.com/iacobuschoi/Mybody.git ~/mybody-server
   git -C ~/mybody-server log -1 --oneline
   ```
   - 이미 있으면 `git -C ~/mybody-server pull --ff-only` 만 합니다.
   - 이 폴더는 손으로 고치지 않습니다.
3. 막히는 것이 없는지 봅니다. 하나라도 걸리면 **멈추고 보고합니다.**
   - `ls ~/.mybody/config.json ~/.mybody-pair 2>&1` → 둘 다 「No such file」 이어야 합니다. 있으면 6 을 하는 순간 빈 데이터베이스로 서버가 뜹니다.
   - `lsof -nP -iTCP:8080 -sTCP:LISTEN` → 비어 있어야 합니다. 뭔가 있으면 프로그램 이름만 적습니다.
   - `cd ~/mybody-server && $N tools/doctor.js`
     - 「노드 버전」 이 ✓ 여야 합니다.
     - BLOCK 은 「가입 코드」 하나뿐이어야 합니다. 설정이 아직 없어서 나는 것이라 정상입니다.
     - 출력은 붙이지 않고 BLOCK · WARN 항목 이름만 적습니다. 운영자 연락처가 찍힐 수 있습니다.
4. plist 를 만듭니다. **sudo 없이, `~/mybody-server` 에서, node@24 로** 합니다:
   ```
   cd ~/mybody-server && $N tools/autostart.js --daemon --write
   grep -c Cellar ~/.mybody/launchd/*.plist        # 둘 다 0
   plutil -lint ~/.mybody/launchd/*.plist          # 둘 다 OK
   grep -A3 ProgramArguments ~/.mybody/launchd/com.mybody.server.plist
   # → /opt/homebrew/opt/node@24/bin/node · …/mybody-server/tools/serve.js (보고에는 붙이지 않음)
   ```
   - 찍힌 「거는 법」 에 있는 **`sudo tailscale funnel --bg 8080` 은 치지 않습니다.** M5 에서만 칩니다.
   - `~/lab/Mybody` 에서 돌리면 서버가 개발 코드를 가리키게 됩니다. 반드시 `~/mybody-server` 에서 돌립니다.
5. `touch ~/Library/Logs/mybody.log ~/Library/Logs/mybody-backup.log && chmod 700 ~/.mybody`
6. **[주인]** 합친 블록에 넣습니다. autostart.js 가 찍은 것과 같고, funnel 줄만 뺐습니다:
   ```
   sudo cp ~/.mybody/launchd/com.mybody.server.plist ~/.mybody/launchd/com.mybody.backup.plist /Library/LaunchDaemons/
   sudo chown root:wheel /Library/LaunchDaemons/com.mybody.server.plist /Library/LaunchDaemons/com.mybody.backup.plist
   sudo chmod 644 /Library/LaunchDaemons/com.mybody.server.plist /Library/LaunchDaemons/com.mybody.backup.plist
   sudo launchctl bootstrap system /Library/LaunchDaemons/com.mybody.server.plist
   sudo launchctl bootstrap system /Library/LaunchDaemons/com.mybody.backup.plist
   ```
   - 「백그라운드 항목이 추가됨」 알림이 뜨면 허용합니다.
   - 시스템 설정 → 일반 → 로그인 항목 및 확장 프로그램에서 **백그라운드에서 허용** 이 켜져 있어야 합니다.
   - 「node 가 들어오는 연결을 받게 할까요」 가 뜨면(오늘이든 나중이든) **거부** 합니다.
     - Funnel 은 맥 안(127.0.0.1)으로 들어오므로 거부해도 상관없습니다.
     - 거부하면 같은 와이파이의 다른 기기가 암호화 없이 서버에 바로 들어오지 못합니다.
7. 1분 간격으로 두 번 확인합니다(세션):
   - `grep -c '아직 설정이 없습니다' ~/Library/Logs/mybody.log` → 숫자가 2쯤 늘면 정상입니다. 30초마다 다시 뜨기 때문입니다.
   - `curl -s -m 3 localhost:8080/health` → 응답이 없어야 합니다.
   - 숫자가 0 그대로면 데몬이 안 걸린 것입니다. **[주인]** 에게 `sudo launchctl print system/com.mybody.server | grep -E 'state|last exit'` 를 보여 주고 결과를 받습니다.
8. 노트북이 쓸 것: `whoami` → 맥 계정 이름입니다. 아래에서 OWNER 라고 부릅니다. 100.x 주소는 노트북이 직접 읽으므로 적지 않습니다.
9. auto 모드가 내일 쓸 명령을 막는지 미리 봅니다. 바뀌는 것은 없습니다:
   ```
   pkill -f "$HOME/mybody-server/tools/[s]erve.js"; echo "pkill $?"
   touch ~/.t && mv ~/.t ~/.mybody/.t && rm ~/.mybody/.t && echo "mv 됨"
   ```
   - pkill 이 0 이든 1 이든 괜찮습니다. 지금은 「설정 없음」 으로 곧 끝나는 프로세스뿐입니다.
   - 막힌 명령은 보고에 적습니다. 클라우드가 M5 에서 그 줄을 [주인] 으로 바꿉니다.

**M4 와 M5 사이에 이 맥에서 하지 않을 것**
- `serve.js --setup`, `launch.js`, `start.command`, `test-selfhost.js` 를 돌리지 않습니다.
- `~/.mybody/` 에 파일을 만들지 않습니다.
  - 개발 사본도 같은 `~/.mybody/config.json` 을 읽습니다.
  - 설정이 생기는 순간 빈 데이터베이스로 서버가 뜹니다.

보고: "M4 끝" + 아래를 한 줄씩. 경로와 로그 줄은 붙이지 않습니다.
- node@24 판
- plist 의 노드 경로가 opt/node@24 인지, Cellar 0 인지
- 「설정 없음」 줄 수가 느는지 · 8080 이 비어 있는지
- doctor 의 BLOCK 이름
- OWNER · SSH 켜짐 여부
- `~/mybody-server` 커밋
- 9 에서 막힌 명령

## M5. 옮기기, 맥 쪽 (서버가 10분쯤 멈춤 · **클라우드가 「M5 시작」 이라고 할 때만** · 노트북 57-나 와 같이)

- **주인은 이때 연구실(노트북 앞)에 있습니다.** 이 과제의 **[주인]** 줄은 이렇게 처리합니다.
  1. 세션이 MAC-REPORT 에 `M5 주인 필요 HH:MM — <명령>` 을 적고 push 한 뒤 기다립니다.
  2. 노트북 세션과 클라우드가 그 줄을 주인에게 전합니다.
  3. 주인은 노트북에서 `ssh -t OWNER@<맥 100.x>` 로 들어와 그 줄을 치고, 맥 비밀번호를 넣습니다.
  - 그 줄에 비밀 값을 넣지 않습니다.
- 이 과제 동안 다른 일은 하지 않습니다. push 는 「M5 대기」, 「M5 안 200」, 「주인 필요」, 「M5 끝」 때만 합니다.
- `N=/opt/homebrew/opt/node@24/bin/node`

1. 준비:
   - `git pull` 을 하고, `git -C ~/mybody-server pull --ff-only` 를 합니다.
   - `ls ~/.mybody/config.json` 은 없어야 합니다.
   - 8080 은 비어 있어야 합니다.
   - 「설정 없음」 줄 수가 늘어야 합니다(M4 7 과 같은 방법).
   - 하나라도 다르면 「M5 대기」 를 적지 않고 보고만 합니다.
   - 다 맞으면 `: > ~/Library/Logs/mybody.log` 로 로그를 비웁니다.
   - 그다음 **곧바로** MAC-REPORT 에 `M5 대기 HH:MM — 파일 기다림` 한 줄을 적고 push 합니다. **노트북은 이 줄을 본 뒤에야 서버를 끕니다.**
2. 파일을 기다립니다. **60분까지** 10초마다 `ls ~/config.json ~/fcm-service-account.json ~/mybody-*.db` 를 봅니다.
   - 60분이 지나면 `M5 멈춤 HH:MM — 파일 안 옴` 을 push 하고 끝냅니다.
   - 세 파일이 다 보이면 바로 `chmod 600 ~/config.json ~/fcm-service-account.json ~/mybody-*.db` 를 합니다.
   - **다 왔는지 확인합니다.** scp 가 아직 쓰고 있을 수 있습니다.
     - 30초마다 `git pull` 을 해서, LOCAL-REPORT 의 「57-나 백업」 줄(숫자 · 크기 · SHA256)을 기다립니다.
     - `shasum -a 256 ~/mybody-<날짜>.db` 가 그 해시와 같아야 합니다. 대소문자는 무시합니다.
     - 다르면 30초 뒤 다시 봅니다. 5분이 지나도 다르면 멈추고 보고합니다.
3. 기록을 되돌립니다. 설정이 아직 없어서 서버가 안 떠 있으므로 바로 됩니다:
   ```
   cd ~/mybody-server && $N tools/backup.js --restore ~/mybody-<날짜>.db
   chmod 600 ~/mybody-server/server/mybody.db
   ```
   - 계정 · 친구 · 주간 요약 수가 「57-나 백업」 숫자와 같아야 합니다.
   - 다르거나 '?' 가 있으면 **멈추고** 보고합니다. 아래 「되돌리기」 로 갑니다.
4. 앱 알림 열쇠를 제자리에 둡니다:
   ```
   mkdir -p ~/.mybody && chmod 700 ~/.mybody
   mv ~/fcm-service-account.json ~/.mybody/ && chmod 600 ~/.mybody/fcm-service-account.json
   ```
5. 설정을 고칩니다. **아직 `~/config.json` 자리에서** 고칩니다. 제자리로 옮기면 서버가 바로 뜨기 때문입니다.
   - BOM 을 뗍니다.
   - `db` 와 `fcmServiceAccount` 를 지웁니다. 맥은 늘 기본 자리를 씁니다.
   - `static` 을 `release` 로 바꿉니다.
   - origin 이 노트북 새 이름(`laptop…`)으로 바뀌어 있으면 되돌립니다.
   ```
   $N -e 'const fs=require("fs"),f=process.argv[1],U="https://desktop-il9c3if.tail0a8f8f.ts.net";let r=fs.readFileSync(f,"utf8");const ch=[];if(r.charCodeAt(0)===0xFEFF){r=r.slice(1);ch.push("BOM")}const c=JSON.parse(r);for(const k of ["db","fcmServiceAccount"])if(k in c){if(c[k])ch.push(k);delete c[k]}if(c.static!=="release"){c.static="release";ch.push("static")}if(/^https:\/\/laptop\./.test(c.origin||"")){c.origin=c.tailscaleOrigin=U;ch.push("origin")}fs.writeFileSync(f,JSON.stringify(c,null,2)+"\n");console.log("고친 것: "+(ch.join(", ")||"없음")+" · 포트 "+(c.port||8080)+" · origin "+c.origin+" · trustProxy "+!!c.trustProxy)' ~/config.json
   chmod 600 ~/config.json
   ```
   - 다음 셋이 맞아야 합니다. 아니면 멈추고 보고합니다.
     - origin 이 **`https://desktop-il9c3if.tail0a8f8f.ts.net`**
     - 포트 8080
     - trustProxy true
   - 「고친 것」 에 origin 이 있으면 보고에 「노트북이 먼저 이름이 바뀌어 origin 을 고침」 이라고 적습니다.
   - 다른 칸은 그대로 둡니다. 값은 보고에 적지 않습니다. origin 은 적어도 됩니다.
6. 알림 열쇠가 되는지 봅니다(PUSH.md 6절):
   ```
   cd ~/mybody-server && $N -e "const f=require('./server/fcm.js');const s=f.load(process.env);console.log(f.describe(s));if(s.sender)s.sender.accessToken().then(()=>console.log('접근 토큰 받음'),e=>console.log('접근 토큰 실패: '+e.message))"
   ```
   - 「접근 토큰 받음」 이 아니면 보고에 적고 계속합니다. 서버는 앱 알림만 빠진 채로 뜹니다.
7. 서버를 켭니다. 설정을 제자리로 옮기면 **30초 안에 launchd 가 저절로** 띄웁니다:
   ```
   mv ~/config.json ~/.mybody/config.json
   for i in $(seq 1 24); do curl -s -m 3 localhost:8080/health && break; sleep 5; done
   ```
   - 첫 기동은 점검(doctor)과 배포 빌드(`release/`) 때문에 10초쯤 더 걸립니다.
   - 2분이 지나도 응답이 없으면 `tail -40 ~/Library/Logs/mybody.log` 를 봅니다.
     - BLOCK 줄이 있으면 그 안내대로 고칩니다. sudo 없는 것만 합니다.
     - 새 줄이 아예 없으면 **[주인]** `sudo launchctl kickstart -k system/com.mybody.server`.
   - 뜬 뒤 확인합니다:
     - `grep -a "앱 알림(FCM) [켜꺼]짐" ~/Library/Logs/mybody.log | tail -1` → 「켜짐 — 프로젝트 mybody-fdbe7」.
     - 경고는 `grep -a "⚠ 앱 알림(FCM)" ~/Library/Logs/mybody.log | tail -3` 으로 따로 봅니다.
     - `curl -s localhost:8080/api/version` → latest 의 appstore · testflight · play 가 모두 0.2.21.
     - `$N tools/serve.js --show` 에서 네 줄만 봅니다: 내보낼 폴더 release · 가입 · 공개 주소 · 터널 뒤 예. 운영자 · 연락처 · 키 줄은 보고에 옮기지 않습니다.
   - 여기까지 되면 짧게 보고하고 push 합니다: "M5 안 200 HH:MM · 되돌린 숫자".
8. 이름을 가져옵니다. 30초마다 `git pull` 해서 LOCAL-REPORT 에 「57-나 이름 놓음」 이 보이면 세션이 `tailscale set --hostname=desktop-il9c3if` 를 칩니다(sudo 없이 됨 — M3 보고).
   그 줄이 안 오면 노트북 세션이 주인에게 관리 화면 이름 바꾸기를 부탁한 것입니다. 아래처럼 기다립니다.
   - 10초마다 30분까지 「상태 한 줄」(M3 3)을 봅니다. 이름이 **`desktop-il9c3if.tail0a8f8f.ts.net.`** 이 되면 됩니다.
   - 10분이 지나도 그대로면 `M5 주인 필요 — 관리 화면 이름 두 개(노트북 → laptop 먼저)` 를 push 합니다.
   - `desktop-il9c3if-1` 이 되면 `M5 주인 필요 — 이름 -1` 을 push 합니다. 주인이 할 일은 둘입니다.
     - 관리 화면에서 겹친 이름을 정리합니다. 노트북이 아직 그 이름을 쥐고 있는지 봅니다.
     - 맥 이름을 다시 `desktop-il9c3if` 로 바꿉니다.
9. 주소를 엽니다. **이름이 바뀐 뒤에만** 합니다. funnel 설정이 기기 이름에 묶여 있기 때문입니다.
   - operator 됨(M3 4): 세션이 `tailscale funnel reset && tailscale funnel --bg 8080 && tailscale funnel status`.
   - operator 안 됨: **[주인]** `sudo tailscale funnel reset && sudo tailscale funnel --bg 8080` → 그 뒤 세션이 `tailscale funnel status`.
   - status 에 `https://desktop-il9c3if.tail0a8f8f.ts.net` · Funnel on · `proxy http://127.0.0.1:8080` 이 보여야 합니다.
   - `--bg` 로 건 것은 재부팅해도 남습니다.
10. 확인:
    - 맥 안에서: `curl -s -m 60 -o /dev/null -w '%{http_code}\n' https://desktop-il9c3if.tail0a8f8f.ts.net/api/health` → 200.
      - 첫 인증서에 30초~1분 걸립니다.
      - 이것은 Tailscale 안쪽 길이라 바깥 확인이 아닙니다.
    - 바깥: check-host 로 봅니다:
      ```
      ID=$(curl -s -H 'Accept: application/json' 'https://check-host.net/check-http?host=https://desktop-il9c3if.tail0a8f8f.ts.net/api/health&max_nodes=8' | sed -E 's/.*"request_id":"([^"]+)".*/\1/'); sleep 20; curl -s -H 'Accept: application/json' "https://check-host.net/check-result/$ID"
      ```
      - 200 이 몇 곳인지 셉니다.
      - "Broken pipe" 가 섞이면 `tailscale debug rebind && tailscale debug restun` 을 합니다(operator 아니면 **[주인]** sudo). 1분 뒤 다시 봅니다.
    - 기준은 클라우드가 돌리는 「서버 살아 있나」(server-check.yml)입니다.

보고: "M5 끝 HH:MM" + 아래를 한 줄씩. 비밀 값 · 연락처 · 파일 내용은 적지 않습니다.
- 파일 받은 시각 · 해시 일치
- 되돌린 계정 · 친구 · 주간 요약 수
- 고친 칸 이름
- 접근 토큰 결과
- 안 200 시각 · 이름 바뀐 시각
- funnel status 한 줄
- check-host 200 개수

**되돌리기: 클라우드가 「M5 되돌리기」 라고 할 때만.** sudo 없이 됩니다.
1. 주소를 닫습니다: `tailscale funnel reset` (operator 아니면 **[주인]** sudo). 이제 새 기록이 안 들어옵니다.
2. 서버를 끕니다. 재부팅해도 다시 안 뜹니다:
   ```
   mv ~/.mybody/config.json ~/.mybody/config.json.off && pkill -f "$HOME/mybody-server/tools/[s]erve.js"
   ```
   - `curl -s -m 3 localhost:8080/health` → 응답이 없어야 합니다.
   - 설정을 아직 옮기기 전(7 전)이면 이 단계는 건너뜁니다.
3. 맥 기록을 챙깁니다. **9(funnel)를 한 번이라도 했으면 늘 합니다:**
   - `cd ~/mybody-server && $N tools/backup.js` 를 칩니다.
   - 파일 이름과 계정 · 친구 · 주간 요약 수를 보고하고 push 합니다.
4. 이름을 되돌립니다. **맥을 먼저** `mybody-mac` 으로(세션: `tailscale set --hostname=mybody-mac`), **그다음** 노트북을 `desktop-il9c3if` 로(노트북 세션: `tailscale set --hostname=desktop-il9c3if`). 둘 중 하나라도 안 먹으면 **[주인 · 관리 화면]** 에서 같은 순서로 바꿉니다.
5. 노트북은 57 의 「되돌리기」 를 합니다.
- launchd 에서 내리기(`bootout` · `disable`)는 나중에 주인이 맥 앞에 있을 때 합니다. 그때까지 서버는 「설정 없음」 으로만 돕니다.

## M6. 옮긴 뒤 확인 · 평소 운영 (M5 가 끝난 뒤)

`N=/opt/homebrew/opt/node@24/bin/node`

1. **[주인 · 폰]** 와이파이를 끄고 LTE 로 앱을 엽니다.
   - 로그인이 유지되는지, 친구 목록이 보이는지, 기록 하나가 남는지 봅니다.
   - 되면 결과지 판독 한 장(선택).
   - 진짜 알림(선택): 친구 계정으로 독촉합니다. 받는 폰의 앱을 완전히 닫은 채로 알림이 오는지 봅니다.
2. 정리합니다. 1 이 되면 `rm ~/mybody-<날짜>.db`.
   - 주인 확인이 하루 넘게 늦어져도 지웁니다. 노트북 사본이 2주 남아 있습니다.
3. sudo 없이 다시 띄우기 시험입니다. 코드를 반영할 때 이 방법을 씁니다:
   ```
   pkill -f "$HOME/mybody-server/tools/[s]erve.js"
   for i in $(seq 1 18); do curl -s -m 3 localhost:8080/health && break; sleep 5; done
   ```
   - 서버는 주인 계정으로 돕니다. 그래서 sudo 없이 끌 수 있고, launchd(KeepAlive)가 곧 다시 띄웁니다.
   - 몇 초 만에 돌아왔는지 적습니다.
   - 90초 안에 안 돌아오면 **[주인]** `sudo launchctl kickstart -k system/com.mybody.server` 를 하고, 그 사실을 보고합니다.
4. 백업 확인. 다음 날 04:00 뒤에 클라우드가 「M6-4」 로 따로 부릅니다:
   - `cd ~/mybody-server && $N tools/backup.js --list` → 오늘 날짜 파일과 계정 · 친구 수.
   - `tail -3 ~/Library/Logs/mybody-backup.log`.
5. 재부팅 시험. **[주인]** 이 집에서 한가할 때 합니다. 서버가 2~3분 멈춥니다.
   - `sudo shutdown -r now`. FileVault 를 켰으면 `sudo fdesetup authrestart`.
   - **로그인하지 않은 채로** 3분 기다립니다. 그동안 클라우드가 바깥을 봅니다.
   - 200 이 확인된 뒤 맥에 로그인합니다. 이 Claude 세션은 로그인해야 다시 켤 수 있습니다.
   - 세션이 돌아오면 「상태 한 줄」 · `tailscale funnel status` · health 를 보고합니다.
6. 이 맥의 운영 규칙입니다. MAC.md 7-3 을 이렇게 읽습니다:

   | 할 일 | 명령 |
   |---|---|
   | 코드 반영 | `cd ~/mybody-server && git pull --ff-only` → 3 의 `pkill`. 안 되면 **[주인]** `sudo launchctl kickstart -k system/com.mybody.server` |
   | 도는지 | `pgrep -fl 'mybody-server/tools/[s]erve.js'` · `curl -s localhost:8080/health` |
   | 로그 | `tail -50 ~/Library/Logs/mybody.log` (회전 없음. 가끔 `: > ~/Library/Logs/mybody.log`) |
   | 바깥만 안 됨(안은 200) | `tailscale debug rebind && tailscale debug restun` (operator 아니면 **[주인]** `sudo …`) → 1분 뒤 check-host |
   | 주소가 사라짐 | `tailscale funnel status` 가 비었으면 `tailscale funnel --bg 8080` (operator 아니면 **[주인]** `sudo …`) |
   | 안내 값 바꾸기 | `cd ~/mybody-server && $N tools/app-version.js …` (노트북에서 하던 것) |
   | 백업 보기 | `cd ~/mybody-server && $N tools/backup.js --list` |

   - **이 맥에서 쓰지 않는 것:** `launch.js` · `start.command` · `test-selfhost.js` · `serve.js --setup`.
   - 개발 사본(`~/lab/Mybody`)에서 서버를 띄울 때는 `PORT=8090` 으로만 띄웁니다. 개발 사본도 같은 설정 파일을 읽습니다.
   - Tailscale 설정을 바꿀 일이 있으면 `tailscale up` 대신 `tailscale set …` 을 씁니다.
     - 예: 이름은 `tailscale set --hostname=desktop-il9c3if`.
     - operator 가 아니면 **[주인]** sudo 로 칩니다.
   - `brew upgrade` 뒤 plist 에 `Cellar` 가 보이면:
     1. `$N tools/autostart.js --daemon --write`
     2. **[주인]** `sudo launchctl bootout system/com.mybody.server; sudo launchctl bootout system/com.mybody.backup`
     3. M4 의 6 을 다시 합니다.
   - 노트북 우편함의 윈도우 처방은 이렇게 바꿔 읽습니다.
     - 「Mybody 서버」 다시 실행 → 3 의 `pkill`
     - `%USERPROFILE%\mybody.log` → `~/Library/Logs/mybody.log`
     - rebind · restun → 위 표
   - 서버 일(코드 반영 · 안내 값 · 백업)은 이제 이 세션이 맡습니다(MAC.md 6절).

보고: "M6 끝" + 1 의 주인 답 · 3 의 돌아온 초 · 5 를 했으면 바깥 200 시각. 4 는 다음 날 「M6-4」 로 따로 보고합니다.
