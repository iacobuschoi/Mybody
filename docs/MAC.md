# 맥미니로 개발하고 서버도 돌리기

중고 **맥미니 M1 · 16GB · 256GB** 한 대가 두 가지 일을 맡습니다.

1. **상시 서버:** 노트북 대신 24시간 켜 둡니다. **주소는 그대로**
   `https://desktop-il9c3if.tail0a8f8f.ts.net` 입니다. 맥의 Tailscale 기기 이름을 노트북과 같은
   `desktop-il9c3if` 로 붙이기 때문입니다. 스토어에 나간 앱에는 이 주소가 박혀 있어서, 바뀌면 앱을
   다시 내야 합니다.
2. **개발:** Xcode와 시뮬레이터를 씁니다. 케이블로 꽂은 아이폰 · 안드로이드 폰에서 앱을 바로 실행하고,
   맥에서 Claude 세션을 돌립니다.

그대로 두는 것도 있습니다.
- 스토어에 올리는 빌드는 계속 GitHub이 만듭니다 (`ios-release.yml` → TestFlight,
  `release.yml` → APK · AAB).
- 코드는 대부분 클라우드 세션이 짭니다.

걸리는 시간은 대략 이렇습니다.
- 처음 켜기 30분
- 개발 도구 1~2시간 (Xcode 받는 시간이 대부분)
- 서버 옮기기 30분. 그중 서버가 멈추는 건 10분쯤입니다.

표시: **[주인]** 은 화면을 누르거나 비밀번호를 넣어야 하는 일입니다. **[맥 세션]** 은 맥의 Claude가 해도
되는 일입니다. **[노트북]** 은 노트북 세션이 할 일로, `docs/LOCAL-TASKS.md` 18번입니다.
`OWNER` 는 맥 계정 이름으로 바꿔 읽으세요.

---

## 0. 한눈에

| 일 | 어디서 |
|---|---|
| 스토어용 빌드 (아이폰 · 안드로이드) | GitHub — 지금 그대로 |
| 코드 대부분 | 클라우드 세션 — 지금 그대로 |
| 폰에서 바로 실행 · 시뮬레이터 | **맥** (새로) |
| 서버 · 매일 백업 | **맥** (노트북에서 옮김, 주소 그대로) |
| Play Console · App Store Connect 올리기 | 브라우저 — 맥이든 노트북이든 |
| 카메라 촬영, 며칠에 걸친 알림 | **실제 아이폰** — 맥으로도 대신 못 합니다 |

**맥에는 저장소를 두 벌 둡니다.**

| 폴더 | 용도 |
|---|---|
| `~/mybody-server` | 서버가 도는 사본입니다. **손으로 고치지 않고** `git pull` 만 합니다. |
| `~/Mybody` | 개발용입니다. 맥의 Claude도 여기서 일합니다. |

한 벌이면 안 되는 이유가 있습니다.
- 서버는 오류가 나거나 재부팅되면 **그 폴더에 있는 코드를 그대로** 다시 띄웁니다. 개발하다 반쯤 고친
  코드가 그대로 서비스될 수 있습니다.
- 데이터베이스도 사본마다 따로입니다 (`server/mybody.db`). 개발하면서 해 보는 일이 진짜 기록을
  건드리지 않습니다.

---

## 1. 받는 날 (직거래 자리에서)

**맥**
- 사과 메뉴 → 이 Mac에 관하여: 칩 **Apple M1**, 메모리 **16GB**, 저장공간 **256GB**.
- 시스템 정보 → 하드웨어 → **활성화 잠금: 비활성화**. 켜져 있으면 판매자의 Apple ID가 걸려 있어서,
  초기화해도 못 씁니다.
- 초기화돼 있어야 합니다(켜면 언어 고르는 화면부터). 아니면 그 자리에서 판매자가 시스템 설정 →
  일반 → 전송 또는 재설정 → **모든 콘텐츠 및 설정 지우기**를 하게 하세요.
- 회사 관리 기기가 아닌지 확인합니다. 터미널에서 `profiles status -type enrollment` 를 쳐서
  `Enrolled via DEP: No` 가 나와야 합니다.

**아이폰 12**
- 설정 맨 위에 판매자 Apple ID가 없어야 합니다(로그아웃).
- 나의 iPhone 찾기가 꺼져 있어야 합니다.
- 설정 → 배터리 → 배터리 성능 상태를 봅니다.

**케이블:** 아이폰 12 는 라이트닝입니다. 맥미니 M1 뒷면의 USB-A 에 기본 USB-A–라이트닝 케이블을
꽂으면 됩니다(USB-C–라이트닝도 됩니다).

---

## 2. 처음 켜기 [주인]

모니터 · 키보드 · 마우스는 **처음 한 번만** 있으면 됩니다. 그 뒤로는 노트북에서 화면 공유로 합니다(2-6).
**랜선을 꽂으세요.** 정전 뒤 잠금 해제(2-3)가 유선에서 가장 확실하게 됩니다.

### 2-1. 설정 지원

- **계정 이름**은 짧은 영문으로 합니다(예: `owner`).
- **비밀번호는 길게** 합니다. 이 비밀번호가 디스크 잠금을 풀고 원격 접속도 하는 열쇠입니다.
- **Apple ID** 는 개발자 계정과 같은 것으로 로그인합니다. Xcode와 App Store에서 씁니다.
- **FileVault(디스크 암호화)를 묻는 화면에서 켭니다.** 이유는 2-3에 있습니다. 복구 키는 종이에 적거나
  비밀번호 관리 앱에 두세요. iCloud에 맡겨도 됩니다.

### 2-2. macOS 올리기

시스템 설정 → 일반 → 소프트웨어 업데이트에서 **macOS 26(Tahoe) 최신판**으로 올립니다.
- 최신 Xcode(27)는 macOS 26.6 이상을 요구하는 것으로 알려져 있습니다.
- App Store에서 Xcode 설치가 막히면 macOS부터 올리세요.
- macOS 27 은 막 나왔습니다(2026-09-14). 서버로 쓰는 맥은 몇 번 고친 판(27.1 이상)이 나온 뒤에 올리세요.

### 2-3. 디스크 암호화(FileVault) — 켭니다

**켜는 이유**
- 데이터베이스에는 친구들의 **건강 정보(민감정보)**가 있습니다.
- `~/.mybody/config.json` 에는 판독 API 키와 알림 비밀 키가 있습니다.
- 켜 두면 맥을 통째로 들고 가도 못 읽습니다.

**치르는 값**
- **예고 없는 정전** 뒤 맥이 다시 켜지면 디스크가 잠긴 채 멈춥니다. 서버도 안 뜹니다.
- 그때는 집 와이파이에 붙은 폰이나 노트북에서 SSH로 비밀번호를 한 번 넣으면 풀립니다(1분).
  macOS 26부터 되는 기능이고, 원격 로그인(2-6)이 켜져 있어야 합니다.
  ```
  ssh OWNER@<맥의 집 안 IP>      # 비밀번호 → 잠시 끊겼다가 1~2분 뒤 서버가 뜹니다
  ```
  - 폰에서는 SSH 앱(예: Termius)을 쓰면 됩니다.
  - 이때는 Tailscale이 아직 안 떠 있어서 **집 안에서만** 됩니다.
- **계획된 재부팅**은 `sudo fdesetup authrestart` 로 합니다. 잠금 없이 한 번 다시 켜집니다.

**자동 로그인은 FileVault와 같이 쓸 수 없습니다.** 그래서 서버는 **로그인 없이 뜨는 방식**
(LaunchDaemon, 7절)으로 겁니다. 로그인해야 뜨는 방식이면 정전 뒤 로그인 화면에서 서버가 멈춥니다.

**끄는 쪽을 고를 수도 있습니다.** 정전 뒤 사람 손 없이 서버가 바로 돌아와야 한다면 끄세요. 대신 이
조건을 지킵니다.
- 도난당하면 기록이 읽힐 수 있다는 걸 알고 끕니다.
- **자동 로그인은 끈 채로** 둡니다.
- 서버는 여전히 LaunchDaemon으로 겁니다.

### 2-4. 잠자기 끄기 · 정전 뒤 켜지기

```
sudo pmset -a sleep 0 disksleep 0 displaysleep 10 powernap 0 womp 1 tcpkeepalive 1 autorestart 1
pmset -g        # sleep 0 · disksleep 0 · autorestart 1 · womp 1 이 보이면 됩니다
```

같은 것을 시스템 설정 → 에너지에서도 켤 수 있습니다.
- 디스플레이가 꺼져 있을 때 자동으로 잠자기 방지
- 네트워크 접근 시 깨우기
- 정전 후 자동으로 시동

**정전 뒤 자동 켜기는 실제로 시험하세요.** M1 맥미니 일부가 다시 안 켜진다는 보고가 있습니다.
켜진 상태에서 전원 코드를 뽑고, 10초 뒤 꽂아 보세요. 안 켜지면 정전 뒤에는 사람이 전원 버튼을 눌러야
합니다. 작은 UPS를 달면 짧은 정전은 아예 넘어갑니다(선택).

### 2-5. 자동 업데이트는 받기만

시스템 설정 → 일반 → 소프트웨어 업데이트 → 자동 업데이트 (i):

| 항목 | 값 | 이유 |
|---|---|---|
| 새로운 업데이트 다운로드 | 켬 | |
| macOS 업데이트 설치 | **끔** | 밤새 재부팅되면 FileVault 잠금에서 멈춥니다 |
| App Store 앱 업데이트 설치 | **끔** | Xcode가 빌드하는 도중에 바뀌지 않게 |
| 보안 대응 및 시스템 파일 설치 | 켬 | 대개 재부팅이 없습니다 |

업데이트는 한 달에 한 번, **집에 있을 때** 손으로 합니다. 끝나면 7-3의 상태 확인을 합니다.

### 2-6. 원격으로 관리하기

- **SSH:** 시스템 설정 → 일반 → 공유 → **원격 로그인** 켬 → 허용할 사용자는 나만.
  정전 뒤 잠금 해제에도 필요합니다. 비밀번호 로그인은 끄지 마세요 — 잠금 해제는 비밀번호로만 됩니다.
- **화면 공유:** 같은 곳에서 **화면 공유** 켬 → (i) → "VNC 뷰어가 암호로 화면을 제어할 수 있음" 에
  암호를 넣습니다.
  - 윈도우 노트북에서는 TigerVNC나 RealVNC Viewer로 `desktop-il9c3if:5900` 에 붙습니다.
    옮기기 전에는 `mybody-mac:5900` 입니다.
  - **Tailscale 안에서만** 씁니다. 공유기에서 포트를 열지 마세요 — VNC 암호는 약합니다.
- **공유기에서 맥의 IP를 고정**합니다(DHCP 예약). 정전 뒤 잠금 해제할 때 그 주소로 붙습니다.
  맥의 IP는 시스템 설정 → 네트워크 → 이더넷에 있습니다.

---

## 3. 256GB 나눠 쓰기

| 무엇 | 대략 |
|---|---|
| macOS · 시스템 데이터 | 25–35GB |
| Xcode | 12–15GB |
| iOS 시뮬레이터 (한 판) | 8–10GB |
| Xcode 캐시 (DerivedData · 기기 지원 파일) | 5–20GB, 쓰면서 자랍니다 |
| Flutter · pub · CocoaPods 캐시 | 4–6GB |
| Android Studio · SDK · Gradle 캐시 (에뮬레이터 빼고) | 10–15GB |
| Homebrew · Node · Tailscale | 1–2GB |
| 저장소 두 벌 · 데이터베이스 · 백업 30일 | 1–3GB |
| **합계** | **약 70–110GB** |

256GB 맥은 실제로 약 245GB로 보이니, 처음에는 130GB 넘게 남습니다. 숫자는 대략이고, 판마다 다릅니다.

**규칙: 늘 40GB 이상 비워 둡니다.**
- macOS와 Xcode 업데이트는 설치하는 동안 그만큼을 씁니다.
- 디스크가 꽉 차면 서버가 기록을 저장하지 못합니다.

**안 까는 것**
- 안드로이드 에뮬레이터: 안드로이드 폰을 케이블로 쓰면 됩니다.
- iOS 시뮬레이터의 옛 판
- watchOS · tvOS · visionOS 플랫폼

**얼마나 쓰는지 보기**
```
df -h /
du -sh ~/Library/Developer ~/Library/Android ~/.gradle ~/flutter ~/.pub-cache ~/mybody-backups 2>/dev/null
```

**비우기** (다시 필요하면 저절로 다시 받습니다)
```
rm -rf ~/Library/Developer/Xcode/DerivedData/*
xcrun simctl delete unavailable                  # 지금 Xcode가 못 쓰는 시뮬레이터
xcrun simctl runtime list                        # 옛 iOS 판 → xcrun simctl runtime delete <ID>
ls ~/Library/Developer/Xcode/iOS\ DeviceSupport  # 지금 폰의 iOS 판만 두고 지우기
(cd ~/Mybody/app && flutter clean)
rm -rf ~/.gradle/caches
brew cleanup
```

**외장 SSD**는 남은 공간이 40GB 아래로 자주 내려가면 삽니다. USB-C · 썬더볼트 NVMe면 됩니다.
- 옮겨도 되는 것: 사진 · 영상, Time Machine 백업(8절)
- 옮기면 안 되는 것: **서버 사본(`~/mybody-server`)과 데이터베이스.** 외장이 빠지면 서버가 멈추거나
  기록이 갈라집니다.

---

## 4. 개발 도구 [맥 세션 · 비밀번호와 App Store 로그인은 주인]

### 4-1. Xcode

App Store에서 **Xcode**를 설치합니다(한 시간쯤). 처음 열 때 플랫폼은 **iOS만** 고르세요.

```
sudo sh -c 'xcode-select -s /Applications/Xcode.app/Contents/Developer && xcodebuild -runFirstLaunch'
sudo xcodebuild -license accept
xcodebuild -version
```

- GitHub 빌드는 Xcode 26.6을 씁니다(0.2.6 빌드 기록). 맥은 App Store 최신판이면 됩니다.
- **아이폰을 iOS 27로 올렸다면 Xcode도 27이어야** 그 폰에 앱을 깔 수 있습니다.

### 4-2. Homebrew · Node · CocoaPods · gh

```
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
eval "$(/opt/homebrew/bin/brew shellenv)"
brew install node@24 cocoapods gh
echo 'export PATH="/opt/homebrew/opt/node@24/bin:$PATH"' >> ~/.zprofile
exec zsh -l
node -v        # v24.x
```

**`node` 가 아니라 `node@24` 인 이유**
- 그냥 `node` 는 해마다 큰 판으로 뛰어서, 서버가 시험 안 된 새 노드로 바뀝니다.
- 서버는 노드 22.13 이상이면 됩니다. 24는 2028년 4월까지 지원됩니다.
- 자동 시작은 판 번호가 없는 경로(`/opt/homebrew/opt/node@24/bin/node`)로 걸립니다
  (`tools/autostart.js`). 그래서 `brew upgrade` 뒤에도 안 깨집니다.

### 4-3. Flutter 3.41.2 — GitHub 빌드와 같은 판

```
git clone --depth 1 --branch 3.41.2 https://github.com/flutter/flutter.git ~/flutter
echo 'export PATH="$HOME/flutter/bin:$PATH"' >> ~/.zprofile
exec zsh -l
flutter --version      # Flutter 3.41.2
flutter doctor
```

- `flutter doctor` 가 Rosetta를 달라고 하면 `sudo softwareupdate --install-rosetta --agree-to-license` 를 칩니다.
- **판을 올릴 때는 GitHub과 같이 올립니다** (`.github/workflows/*.yml` 의 `FLUTTER_VERSION`).
  한쪽만 올리면 "내 맥에서는 되는데" 가 생깁니다.

### 4-4. 안드로이드 (선택)

```
brew install --cask android-studio
```

- Android Studio를 한 번 열어 기본 설치(SDK)만 합니다. **에뮬레이터는 만들지 않습니다**(3절).
- 그다음 `flutter doctor --android-licenses` 로 라이선스를 모두 받습니다(`y`).
- 안드로이드 폰은 설정 → 휴대전화 정보 → 빌드번호를 일곱 번 누르고, 개발자 옵션 → **USB 디버깅**을
  켠 뒤 케이블로 꽂습니다.
- GitHub 빌드는 JDK 17을 씁니다. 맥에서는 Flutter가 Android Studio에 든 JDK를 씁니다.

### 4-5. 개발 사본

```
gh auth login          # GitHub.com → HTTPS → 브라우저로 로그인
gh auth setup-git
git clone -b claude/body-management-app-prototype-m4mv4k https://github.com/iacobuschoi/Mybody.git ~/Mybody
```

**`~/Desktop` · `~/Documents` · `~/Downloads` 나 iCloud 동기화 폴더에는 두지 않습니다.**
- 그 폴더들은 macOS가 자동 실행 프로그램의 접근을 막습니다.
- iCloud는 데이터베이스 파일을 쓰는 도중에 올려 버립니다.

### 4-6. 늘 돌리는 검사

```
cd ~/Mybody
(cd packages/mybody_core && dart pub get && dart test)
(cd app && flutter pub get && flutter analyze && flutter test)
node tools/difftest.js
node tools/test-selfhost.js
```

- 개발 사본에서 서버를 따로 띄울 일이 있으면 `PORT=8090 node tools/serve.js` 로 띄웁니다. 8080은
  진짜 서버 것입니다.
- **개발 사본에서는 `launch.js` 를 쓰지 않습니다.** 공개 주소를 건드립니다.

---

## 5. 아이폰에서 바로 실행하기

1. 아이폰을 케이블로 꽂습니다. 폰에 "이 컴퓨터를 신뢰하겠습니까?" 가 뜨면 **신뢰**를 누르고 폰 암호를
   넣습니다.
2. Xcode → 설정 → **Accounts** → `+` → 개발자 계정 Apple ID로 로그인합니다.
3. `cd ~/Mybody/app && flutter pub get` 을 한 번 하고, `open ios/Runner.xcworkspace` → 왼쪽 Runner →
   타깃 Runner → **Signing & Capabilities**
   - "Automatically manage signing" 켬
   - Team: 개발자 계정 팀(`JT4YLVNKDZ`)
   - 이러면 아이폰이 계정에 저절로 등록됩니다.
4. 아이폰: 설정 → 개인정보 보호 및 보안 → **개발자 모드** 켬 → 재시동 → 켜기 확인.
   이 메뉴는 폰을 Xcode가 있는 맥에 한 번 꽂은 뒤에 나타납니다.
5. 실행합니다.
   ```
   cd ~/Mybody/app
   flutter devices                 # 아이폰 이름이 보여야 합니다
   flutter run -d <아이폰 이름>     # 디버그. 속도를 볼 때는 --release
   ```
   처음 한 번 케이블로 돌린 뒤에는 Xcode → Window → Devices and Simulators → 그 폰 → **Connect via
   network** 로 무선으로도 됩니다.

**3번은 프로젝트 파일을 바꿉니다.** `app/ios/Runner.xcodeproj/project.pbxproj` 에
`DEVELOPMENT_TEAM = JT4YLVNKDZ;` 줄이 생깁니다.
- 커밋해도 됩니다. GitHub의 스토어 빌드는 빌드 직전에 서명 설정을 통째로 바꿔 끼웁니다
  (`tools/ios-sign-project.js` 가 그 줄을 지우고 다시 넣습니다).
- 다만 `git diff app/ios` 에 **`DEVELOPMENT_TEAM` 줄 말고 다른 것**이 섞였으면 커밋하지 말고 클라우드
  세션에 물어보세요.

**폰에서 돌리는 앱은 진짜 서버에 붙습니다.** 앱의 기본 주소가 공개 주소이기 때문입니다.
시험은 **시험용 계정**으로 하세요. 친구 계정이나 내 진짜 계정으로 하지 않습니다.

**어디서 무엇을 보나**

| 시뮬레이터로 됨 | 실제 폰이어야 함 |
|---|---|
| 화면 · 흐름 · 글자 넘침 | 카메라로 결과지 찍기 |
| 로그인 · 동기화 · 친구 | 알림이 며칠 동안 제시간에 오는지 (잠금 화면 · 집중 모드 · 배터리) |
| 예약 알림이 뜨는지 (시간을 가깝게 두고) | 스크롤 · 애니메이션 속도, 손맛 |
| 앨범에서 사진 고르기 (`xcrun simctl addmedia booted 사진.jpg`) | 권한 팝업을 처음 받는 흐름 (새로 설치) |

---

## 6. 맥에서 Claude

- **설치:** `curl -fsSL https://claude.ai/install.sh | bash`, 또는 Claude 데스크톱 앱. 설치 방법이
  바뀌었으면 claude.ai의 Claude Code 안내를 따르세요.
- **켜기:** `cd ~/Mybody && claude remote-control`. 폰의 Claude 앱에 이 맥 세션이 나타나서, 지금처럼
  폰으로 시키면 됩니다.
  - 이 세션은 로그인한 화면 안에서 돕니다.
  - 재부팅한 뒤에는 화면 공유로 로그인해서 다시 켜세요.
  - 서버는 로그인 없이도 도니, 이 세션이 꺼져 있어도 앱은 됩니다.

**이 세션이 맡는 일**
- 폰과 시뮬레이터에서 실행해 확인하기
- 서버 운영: 코드 반영, 재시작, 백업 확인 (7-3)
- 스토어 콘솔에 올리기

**서버를 옮긴 뒤로는 맥 세션이 노트북 세션의 자리를 이어받는 것을 기본으로 합니다**(주인이 달리
정하지 않으면). `docs/LOCAL-TASKS.md` 를 받아 하고 `docs/LOCAL-REPORT.md` 에 보고합니다.
다른 세션과 같은 규칙을 따릅니다.
- 브랜치는 `claude/body-management-app-prototype-m4mv4k` 하나입니다. **밀기 전에 늘 `git fetch` 와 rebase**
  를 합니다. 클라우드 세션도 같은 브랜치에 밉니다.
- 비밀 파일(8절 표)은 커밋하지 않습니다.
- `prototype/` 의 웹 화면은 고치지 않습니다.
- `~/mybody-server` 에서는 `git pull` 과 재시작만 합니다.

---

## 7. 서버 옮기기 — 노트북 → 맥

### 7-1. 준비 — 서버는 안 멈춥니다 [맥 세션 · 로그인 링크는 주인]

**Tailscale은 Homebrew 판으로 깝니다.**
```
brew install tailscale
sudo brew services start tailscale
sudo tailscale up --hostname=mybody-mac    # 찍히는 링크를 열어 노트북과 같은 Tailscale 계정으로 로그인
tailscale status
```
- **App Store판이나 Standalone판 Tailscale 앱은 깔지 않습니다.** 둘 다 누가 로그인해야 돌아서, 정전 뒤
  로그인 화면에서 주소가 죽습니다. Homebrew 판은 부팅하면 로그인 없이 돕니다. 이미 깔려 있으면 지우세요.
- 관리 화면(<https://login.tailscale.com/admin/machines>) → `mybody-mac` → ⋯ → **Disable key expiry**.
  그냥 두면 180일 뒤 조용히 로그아웃되고, 주소가 죽습니다.

**서버 사본과 자동 시작 파일**
```
git clone -b claude/body-management-app-prototype-m4mv4k https://github.com/iacobuschoi/Mybody.git ~/mybody-server
cd ~/mybody-server
node tools/autostart.js --daemon --write
```
- 이 명령은 plist 두 개(서버 · 매일 04:00 백업)를 `~/.mybody/launchd/` 에 만들고, 거는 명령을 찍어 줍니다.
- **아직 걸지 않습니다.** 데이터베이스를 옮긴 뒤에 겁니다.
- 찍힌 노드 경로가 `/opt/homebrew/opt/node@24/bin/node` 인지 봅니다. `Cellar` 가 들어 있으면 4-2를
  다시 확인하세요.

### 7-2. 옮기기 — 서버가 10분쯤 멈춥니다

심사 중인 스토어 빌드가 있으면 한가한 시간에 합니다. 노트북 쪽 순서는 `docs/LOCAL-TASKS.md` 18번입니다.

1. **[노트북]** 서버 창에서 Ctrl+C 를 누릅니다. `launch.js` 가 연 주소도 같이 닫힙니다.
   `tailscale funnel status` 가 비어 있어야 합니다. 남아 있으면 `tailscale funnel reset`.
2. **[노트북]** 마지막 백업을 합니다. 서버를 끈 **뒤에** 해야 끄기 직전 기록까지 들어갑니다.
   ```powershell
   node tools/backup.js --out="$HOME\mybody-move"
   node tools/backup.js --out="$HOME\mybody-move" --list    # 계정 N명 · 친구 M건 — 적어 둡니다
   ```
3. **[노트북]** 맥으로 보냅니다. 맥의 원격 로그인이 켜져 있어야 합니다.
   ```powershell
   scp "$HOME\.mybody\config.json" OWNER@mybody-mac:config.json
   scp "$HOME\mybody-move\mybody-<날짜>.db" OWNER@mybody-mac:last.db
   ```
   받는 쪽 경로를 `:config.json` 처럼 적으면 맥 계정의 홈 폴더로 갑니다.
   `mybody-mac` 이 안 찾아지면 맥의 Tailscale 주소(`tailscale status` 의 100.x)를 씁니다.
   **git으로는 절대 옮기지 않습니다.**
4. **[맥]** 설정과 기록을 제자리에 놓습니다.
   ```
   mkdir -p ~/.mybody && mv ~/config.json ~/.mybody/config.json
   chmod 700 ~/.mybody && chmod 600 ~/.mybody/config.json
   cd ~/mybody-server
   # 노트북 설정에 윈도우 경로(db)가 있으면 빼고, 배포 빌드(release)를 쓰게 합니다 — oracle-setup.sh 와 같은 처리
   node -e 'const f=process.argv[1],fs=require("fs");const c=JSON.parse(fs.readFileSync(f,"utf8"));let ch=false;if(c.db&&/\\|^[A-Za-z]:/.test(c.db)){delete c.db;ch=true}if(c.static!=="release"){c.static="release";ch=true}if(ch)fs.writeFileSync(f,JSON.stringify(c,null,2))' ~/.mybody/config.json
   grep '"origin"' ~/.mybody/config.json       # https://desktop-il9c3if.tail0a8f8f.ts.net 이어야 합니다
   node tools/backup.js --restore ~/last.db    # 계정 · 친구 수가 2번과 같은지
   node tools/doctor.js                        # 빨간 줄(BLOCK)이 없어야 합니다
   ```
   `db` 를 빼야 하는 이유: 윈도우 경로(`C:\…`)가 남아 있으면 맥은 그걸 이상한 이름의 파일로 읽고,
   **빈 데이터베이스를 새로 만들어** 조용히 뜹니다.
5. **[맥]** 자동 시작을 겁니다. `autostart.js` 가 찍어 준 명령과 같습니다.
   ```
   touch ~/Library/Logs/mybody.log ~/Library/Logs/mybody-backup.log
   sudo cp ~/.mybody/launchd/com.mybody.server.plist ~/.mybody/launchd/com.mybody.backup.plist /Library/LaunchDaemons/
   sudo chown root:wheel /Library/LaunchDaemons/com.mybody.server.plist /Library/LaunchDaemons/com.mybody.backup.plist
   sudo chmod 644 /Library/LaunchDaemons/com.mybody.server.plist /Library/LaunchDaemons/com.mybody.backup.plist
   sudo launchctl bootstrap system /Library/LaunchDaemons/com.mybody.server.plist
   sudo launchctl bootstrap system /Library/LaunchDaemons/com.mybody.backup.plist
   curl -s localhost:8080/health
   ```
   "백그라운드 항목이 추가됨" 알림이 뜨면 허용합니다. 시스템 설정 → 일반 → 로그인 항목 및 확장
   프로그램에서 **백그라운드에서 허용**이 켜져 있어야 합니다.
6. **[주인 · 관리 화면]** 이름을 바꿉니다. **순서가 중요합니다.**
   1. 노트북 `desktop-il9c3if` → ⋯ → Edit machine name → **`laptop`**
   2. `mybody-mac` → ⋯ → Edit machine name → **`desktop-il9c3if`**. "Auto-generate from OS hostname" 은 끕니다.

   이름이 비기 전에 붙이면 맥은 `desktop-il9c3if-1` 이 됩니다. 그러면 앱에 박힌 주소와 달라집니다.
7. **[맥]** 주소를 엽니다.
   ```
   tailscale status --json | grep -m1 DNSName    # "desktop-il9c3if.tail0a8f8f.ts.net." 이어야 합니다
   sudo tailscale funnel reset
   sudo tailscale funnel --bg 8080
   tailscale funnel status
   ```
   - funnel 설정은 기기 이름에 묶여 있습니다. 그래서 **이름을 바꾼 뒤에** 겁니다.
   - `--bg` 로 건 것은 재부팅해도 남습니다.
8. **확인**은 폰의 와이파이를 끄고 LTE로 합니다.
   - `https://desktop-il9c3if.tail0a8f8f.ts.net/health` 가 열려야 합니다. 처음엔 인증서를 받느라 30초~1분
     걸립니다.
   - 앱에서 로그인하고, 친구 목록을 열고, 기록 하나를 남깁니다. 되면 결과지 판독도 한 장 해 봅니다.
   - 다 되면 맥의 옮겨 온 사본을 지웁니다: `rm ~/last.db` (백업은 매일 따로 뜹니다)
9. **재부팅 시험**
   - `sudo fdesetup authrestart` → 몇 분 뒤, **로그인하지 않은 채로** 8번의 주소가 열려야 합니다.
     FileVault를 껐으면 `sudo shutdown -r now` 로 합니다.
   - 정전 시험(2-4)을 할 때 FileVault 잠금 해제(2-3)도 한 번 해 봅니다.
10. **[노트북]** 더는 서버를 띄우지 않습니다. 이름이 `laptop` 이라 공개 주소와는 무관하지만, 헷갈리니
    `launch.js` 를 돌리지 않습니다.

**되돌리기** — 맥이 이상할 때
1. [맥] 서버를 내리고 주소를 닫습니다: `sudo launchctl bootout system/com.mybody.server`,
   `sudo tailscale funnel reset`
2. [맥] 그동안 맥에 쌓인 기록을 챙깁니다: `cd ~/mybody-server && node tools/backup.js`
3. [관리 화면] 맥 이름을 `mybody-mac` 으로, 노트북 이름을 `desktop-il9c3if` 로 되돌립니다.
4. [노트북] 맥의 새 백업을 받아 `node tools/backup.js --restore <파일>` 한 뒤, `node tools/launch.js` 를
   띄웁니다.

### 7-3. 평소 운영 [맥 세션]

| 할 일 | 명령 |
|---|---|
| 코드 반영 ("서버 다시 띄우기") | `cd ~/mybody-server && git pull --ff-only && sudo launchctl kickstart -k system/com.mybody.server` |
| 도는지 | `sudo launchctl print system/com.mybody.server \| grep -E 'state =\|pid ='` · `curl -s localhost:8080/health` |
| 로그 | `tail -f ~/Library/Logs/mybody.log` (회전 없이 자랍니다 — 가끔 `: > ~/Library/Logs/mybody.log`) |
| 계획된 재부팅 | `sudo fdesetup authrestart` |
| 멈추기 · 다시 걸기 | `sudo launchctl bootout system/com.mybody.server` · `sudo launchctl bootstrap system /Library/LaunchDaemons/com.mybody.server.plist` |

- **이 맥에서는 `launch.js` 를 쓰지 않습니다.** 서버는 launchd가, 주소는 `funnel --bg` 가 맡습니다.
  `launch.js` 는 창을 닫으면 같이 닫히는 주소를 따로 열려다 부딪힙니다.
- **plist를 고쳤으면** `bootout` 뒤 `bootstrap` 을 다시 해야 반영됩니다. `kickstart` 로는 안 됩니다.

---

## 8. 백업과 비밀 파일

**매일 04:00** 에 `~/mybody-backups` 로 백업되고, 30일치가 남습니다(`com.mybody.backup`).
- 그 시각에 맥이 꺼져 있었으면 그날 백업은 없습니다.
- 확인: `cd ~/mybody-server && node tools/backup.js --list`

**같은 디스크 안의 백업은 디스크 고장이나 도난을 못 막습니다.** 주 1회는 밖으로 꺼냅니다.
- **쉬운 길:** 외장 SSD에 Time Machine을 켭니다. 백업 디스크 암호화에 체크하세요. `~/mybody-backups`
  까지 같이 들어갑니다.
- **노트북으로 가져오기**(PowerShell):
  ```powershell
  mkdir -Force "$HOME\mybody-copies"
  scp OWNER@desktop-il9c3if:mybody-backups/mybody-<날짜>.db "$HOME\mybody-copies\"
  ```

**`config.json` 은 백업에 안 들어갑니다.** 한 부를 비밀번호 관리 앱이나 암호화한 USB에 두세요.
잃으면 가입 코드와 알림 키가 바뀌어서, 웹 알림 구독이 모두 끊깁니다.

| 비밀 | 어디에 | 저장소에 |
|---|---|---|
| `~/.mybody/config.json` (판독 키 · 알림 키 · 가입 코드) | 맥 + 오프라인 사본 한 부 | **절대 안 올림** |
| `~/mybody-server/server/mybody.db` (+ `-wal` · `-shm`) | 맥 | 안 올림 (`.gitignore`) |
| `~/mybody-backups/*.db` | 맥 · 외장 | 안 올림 |
| 안드로이드 서명 키 `.jks` · `key.properties` | GitHub Secrets + 노트북의 보관 사본 | 안 올림 — 맥에는 둘 필요 없습니다 |
| 애플 API 키 `.p8` | GitHub Secrets | 안 올림 |
| `play/계정.txt` (심사용 계정) | 노트북 `play` 폴더 | 안 올림 |
| FileVault 복구 키 | 종이 · 비밀번호 관리 앱 | — |

---

## 9. 문제가 생기면

| 증상 | 할 일 |
|---|---|
| 재부팅 뒤 서버가 안 뜸 | 로그인 화면에서 멈춰 있으면 FileVault 잠금입니다. 2-3의 SSH 잠금 해제. 아니면 `sudo launchctl print system/com.mybody.server` 의 `last exit code` 와 `tail -50 ~/Library/Logs/mybody.log` |
| 주소가 안 열림 | `tailscale status` (로그아웃 · 키 만료?) → `tailscale funnel status` (비었으면 `sudo tailscale funnel --bg 8080`) |
| 이름이 `desktop-il9c3if-1` | 관리 화면에서 겹친 이름을 정리하고, 맥 이름을 `desktop-il9c3if` 로 → `sudo tailscale funnel reset && sudo tailscale funnel --bg 8080` |
| `brew upgrade` 뒤 서버가 죽음 | `/Library/LaunchDaemons/com.mybody.server.plist` 의 노드 경로에 `Cellar` 가 있으면: `node tools/autostart.js --daemon --write` → `bootout` → 7-2의 5번 다시 |
| 디스크가 꽉 참 | 3절의 비우기. 꽉 찬 동안은 기록이 저장되지 않습니다 |
| "포트가 이미 쓰이고 있습니다" | 서버가 이미 도는 중입니다(정상). 다시 띄우기는 `kickstart`. 개발 사본은 `PORT=8090` |
| 정전 뒤 안 켜짐 | 이 맥은 자동 켜기가 안 먹는 것입니다. 전원 버튼을 누르고, UPS를 고려하세요 |

---

확인 필요 — 직접 못 해 보고 문서 · 보고로만 확인한 것입니다. 해 보고 다르면 이 문서를 고치세요.
- M1 맥미니의 정전 뒤 자동 켜기
- Xcode 27이 요구하는 macOS 판
- 시스템 설정 메뉴의 한글 이름
- `claude remote-control` 이 로그인 없이(SSH만으로) 도는지
