# 환경 세팅 — 기기 · 계정 · GitHub · Claude

[README](README.md) 의 그림에서 각 칸을 실제로 세우는 법입니다. 위에서부터 한 번씩만 하면 됩니다.
표시: 🙋 = 주인이 직접(로그인 · 결제 · 본인 인증 · 폰 화면 터치) · 🤖 = Claude 세션에 맡기면 됨.

---

## 0. 기기마다 맡는 일

| 기기 | 맡는 일 | 왜 이 기기인가 |
|---|---|---|
| **클라우드 (Claude Code on the web)** | 조사 · 기획 · 코드 · PR · 보고. 앱 하나에 세션 하나 | 노트북을 꺼도 돕니다. 폰으로 보고 · 지시. 여러 앱을 나란히 |
| **GitHub 러너 (리눅스)** | 단위 · 위젯 시험, 안드로이드 빌드, 스토어 업로드 · 제출 | 비용 0에 가깝고, 스토어 열쇠가 기기에 안 남음 |
| **맥 미니 M1 16GB** | **기기 실험실**: iOS 빌드 · 시뮬레이터 · 아이폰 12 · 안드로이드 폰 몇 대 · AI 탐색 시험 | iOS 는 맥이 있어야 시뮬레이터 · 실기기가 됨. 24시간 켜 두기 좋음(전력 수 와트) |
| **아이폰 12** | 실기기 iOS 시험 (맥 미니에 USB 로 상주) | iOS 26 까지 올라가는 가장 오래된 축의 기기 — 느린 쪽 기준 |
| **안드로이드 폰들** | 실기기 안드로이드 시험 (제조사 · 판 · 화면 크기를 섞어서) | 에뮬레이터가 못 잡는 것: 제조사 절전, 알림 묶기, 한글 입력기, 카메라 |
| **윈도우 (ASUS TUF)** | 예비 실험실: 안드로이드 에뮬레이터 여러 판(API 26~36) · 추가 폰 · 맥 미니가 죽었을 때 대타 | x86 에뮬레이터가 빠름. 노트북이라 상주용으로는 둘째 |

MyBody 때와 다른 점: 노트북 세션이 우편함(LOCAL-TASKS.md)을 읽고 주인이 "15번 해줘" 를 전달하던
일을 **맥 미니의 GitHub 러너가 대신**합니다. 클라우드 세션이 워크플로를 실행하면 맥 미니가 받아서
돌리고 결과를 올립니다. 사람이 끼지 않습니다.

---

## 1. 계정 · 요금 (🙋, 한 번)

| 무엇 | 얼마 | 왜 |
|---|---|---|
| Claude **Max** (5x 또는 20x) | $100 / $200 월 | 앱 여러 개를 자율로 굴리면 Pro 한도로는 주 중반에 멈춥니다. 5x 로 시작해 주간 한도에 걸리면 20x |
| GitHub Pro (권장, 필수 아님) | $4 월 | 비공개 저장소의 **브랜치 보호**(빨간 CI 는 머지 못 하게) · 환경 Secrets · Actions 3,000분 |
| Apple Developer | $99 년 | 있음 |
| Google Play 개발자 | $25 한 번 | 있음 |
| 도메인 1개 | 연 1~2만원 | 모든 앱의 개인정보처리방침 · 지원 · 계정 삭제 페이지와 문의 메일(support@) |
| RevenueCat · Firebase(Crashlytics · Analytics) · Sentry | 0원에서 시작 | 매출이 생기기 전까지 무료 구간 ([MONEY.md](MONEY.md)) |

앱 하나 늘어날 때 드는 돈은 사실상 0 입니다. 늘어나는 것은 **Claude 사용량**과 **주인이 콘솔에서
처음 한 번 넣는 15~30분**입니다.

### 스토어 계정 단위로 한 번만 하는 것 (🙋)
- App Store Connect: **유료 앱 계약(Paid Apps Agreement)** · 세금(W-8BEN) · 은행 계좌. 이게 없으면
  인앱결제 · 구독이 **샌드박스에서도 안 뜹니다.**
- App Store Connect → 사용자 및 액세스 → 통합 → **API 키 두 개** (3절 「열쇠를 둘로 나누는 이유」):
  - `factory-beta` — 역할 **Developer** (빌드 업로드 · TestFlight)
  - `factory-prod` — 역할 **App Manager** (심사 제출 · 출시)
- Play Console: 결제 프로필(판매자 계정) · 세금 정보 · **본인 확인**.
- Play Console → 사용자 및 권한 → Google Cloud 서비스 계정 **두 개**를 초대:
  - `factory-beta@…` — 「테스트 트랙으로 앱 출시」 권한만
  - `factory-prod@…` — 「프로덕션으로 출시 …」 권한까지
- **소규모 사업자 프로그램**(애플 수수료 15%) 신청 — 신청해야 적용됩니다.

> **먼저 확인할 것 — 플레이 개발자 계정을 만든 날짜.** 개인 계정이 **2023-11-13 이후**에
> 만들어졌다면 구글은 **앱마다** 프로덕션 전에 「테스터 12명 · 14일 연속」 비공개 테스트를 요구합니다
> ([공식](https://support.google.com/googleplay/android-developer/answer/14151465)). 공장에는 큰
> 병목입니다(앱 하나에 최소 2주 + 사람 12명). D-U-N-S 번호로 확인된 **조직 계정은 면제**라서,
> 수익화를 위해 어차피 할 사업자등록([MONEY.md](MONEY.md) 7절)과 묶어 조직 계정으로 가는 것을
> 권합니다. 그 전까지는 지인 12명 이상을 구글 그룹 하나로 묶어 모든 앱의 비공개 테스트에 씁니다.

---

## 2. 저장소 (🙋 만들기 5분 → 🤖 채우기)

**권장: 저장소 둘.**
- `app-factory` — **비공개** 모노레포. 모든 앱의 코드 · 시험 · 문서. Claude 가 일하는 곳.
- `app-factory-ship` — **공개**, 코드 없음. 출시 워크플로 한 개와 출시용 열쇠만 있는 **출시 창구**.
  왜 따로인지는 3절.

```
app-factory/
  CLAUDE.md  .claude/            ← 이 폴더의 seed/ 를 그대로 복사
  apps/<앱>/                     Flutter 앱
  packages/                      같이 쓰는 것 (결제 벽 · 설정 · 법적 화면 · 측정 · 디자인)
  portfolio/                     조사 · 기획 · 보고 · 지표
  .github/workflows/             ci · device-lab · release-candidate · ship
```

앱마다 저장소를 따로 두지 않는 이유:
- **러너 하나 · Secrets 한 벌.** 개인 계정의 self-hosted 러너는 저장소마다 따로 등록해야 합니다.
  앱이 10개면 맥 미니에 러너 10개입니다.
- 앞선 앱의 코드 · 시험 · 실수가 다음 앱 세션의 눈앞에 있습니다(“지난번엔 이렇게 했다”).
- 같이 쓰는 패키지를 고치면 모든 앱이 한 PR 에서 시험됩니다.

공개 저장소로 두면 안 되는 이유: 코드가 복제되는 것도 있지만, **공개 저장소에 self-hosted 러너를
붙이면 남이 올린 PR 이 맥 미니에서 코드를 돌릴 수 있습니다.** (MyBody 는 공개 저장소라 맥 미니
러너를 붙이지 마세요.)

만드는 법: GitHub → New repository → `app-factory`(Private) 와 `app-factory-ship`(Public) →
클라우드 세션에서 "MyBody 의 factory/seed 를 app-factory 에 풀고, MyBody 빌드 워크플로를 공장용으로
옮기고, 출시 창구 워크플로를 만들어 줘" 🤖.

---

## 3. GitHub 설정 (🙋, 10분)

### 출시 승인 버튼 = 공개 저장소의 환경 보호 규칙
GitHub 의 「Required reviewers」(잡이 사람 승인을 기다리게 하는 것)는 Free · Pro · Team 요금제에서
**공개 저장소에서만** 됩니다. 비공개 저장소에서 쓰려면 Enterprise 가 필요합니다
([GitHub 문서 원문](https://github.com/github/docs/blob/main/content/actions/reference/workflows-and-actions/deployments-and-environments.md)).
그래서 승인 버튼만 공개 저장소 `app-factory-ship` 에 둡니다. 거기에는 코드가 없습니다 — 이미 스토어에
올라가 있는 빌드를 「제출해라 / 프로덕션으로 올려라」 하는 워크플로뿐입니다.

`app-factory-ship` → Settings → Environments → `store-production`:
- **Required reviewers: 주인** · 「Prevent self-reviews」는 **끔** (아래 이유)
- Environment secrets: `ASC_PROD_KEY_ID` · `ASC_PROD_ISSUER_ID` · `ASC_PROD_KEY_P8` · `PLAY_PROD_SA_JSON` ·
  `FACTORY_READ_TOKEN` (app-factory 를 **읽기만** 하는 fine-grained 토큰 — 스토어 문안 · 스크린샷을 가져옴)

`app-factory`(비공개) → Settings → Secrets → Actions:
- `ASC_BETA_*` · `PLAY_BETA_SA_JSON` — 테스트 트랙까지만 되는 열쇠
- 앱별 안드로이드 업로드 열쇠 `<APP>_KEYSTORE_B64` · `<APP>_KEYSTORE_PW` · `<APP>_KEY_ALIAS` ·
  `<APP>_KEY_PW` (5절 스크립트가 넣음)

### 열쇠를 둘로 나누는 이유
Claude 의 GitHub 활동은 **주인 계정 이름으로** 기록됩니다. GitHub 입장에서는 Claude 와 주인이 같은
사람이라, 계정으로는 "Claude 는 출시 못 하게" 를 나눌 수 없습니다. (같은 이유로 「Prevent self-reviews」를
켜면 Claude 가 실행한 출시를 주인도 승인 못 합니다.) 그래서 잠금을 이렇게 겹칩니다:
1. 출시 권한이 있는 열쇠(`*_PROD_*`)는 공개 저장소의 `store-production` 환경에만 있습니다. 그 환경의
   잡은 **승인 버튼이 눌려야** 시작되고, 그 전에는 열쇠가 어디에도 풀리지 않습니다. 워크플로 파일을
   고쳐도 이 규칙은 GitHub 이 강제합니다.
2. 클라우드 세션의 도구에는 승인 버튼을 누르는 기능이 없고, 맥 미니 세션은 훅(`guard.js`)이 승인
   API 를 막습니다.
3. 평소에 쓰는 열쇠(`*_BETA_*`)는 애플 · 구글 쪽 권한 자체가 테스트 트랙까지라, 새더라도
   프로덕션으로는 못 나갑니다.

공개 저장소라서 생기는 것: 출시 워크플로의 **실행 기록을 누구나 볼 수 있습니다**(비밀값은 가려짐).
앱 이름 · 판 번호 정도만 찍히게 만듭니다. 이 저장소에는 self-hosted 러너를 붙이지 않습니다.

### 그 밖에
- `app-factory` → Settings → Branches → `main` 보호(Pro 필요): **상태 검사 통과 필수**(ci).
  Claude 가 자기 PR 을 머지하되 빨간 채로는 못 하게. 강제 푸시 금지.
- Settings → Actions → General → Fork pull request workflows: **외부 기여자 승인 필요** (비공개면 기본).
- **Claude GitHub App** 을 두 저장소에 설치 (claude.ai → Settings → Connectors → GitHub).
- 폰의 **GitHub 앱** → 알림 → Actions · 배포 검토(Deployment review) 켜기. 승인 요청이 여기로 옵니다.

---

## 4. 맥 미니 — 기기 실험실 (🙋 1시간 + 🤖)

### 4-1. 켜 두기
```bash
sudo pmset -a sleep 0 disksleep 0 displaysleep 10 autorestart 1 womp 1
```
- 시스템 설정 → 사용자: 실험실 전용 사용자 `lab` 을 만들고 **자동 로그인**. 시뮬레이터와 러너는
  로그인된 화면 세션이 있어야 돕니다. (FileVault 가 켜져 있으면 자동 로그인이 안 됩니다 — 정전 뒤에는
  직접 로그인해야 합니다. 개인 자료가 없는 전용 기기면 끄는 쪽이 편합니다.)
- 시스템 설정 → 에너지: 「정전 후 자동 시작」.
- **Tailscale** 설치(이미 씀) → 밖에서 폰으로 화면 공유 · SSH 로 맥 미니를 볼 수 있습니다.

### 4-2. 도구 (🤖 — 맥 미니 Claude 세션에 이 절을 통째로 맡겨도 됩니다)
```bash
# Xcode: App Store 에서 설치 후
sudo xcodebuild -license accept && xcodebuild -runFirstLaunch
xcodebuild -downloadPlatform iOS

# Homebrew 가 없으면 https://brew.sh 한 줄
brew install git gh node tmux cocoapods fastlane openjdk@17
brew install --cask android-commandlinetools

# Flutter — CI 와 같은 판을 씁니다 (MyBody: 3.41.2)
git clone -b 3.41.2 --depth 1 https://github.com/flutter/flutter.git ~/flutter
echo 'export PATH="$HOME/flutter/bin:$PATH"' >> ~/.zprofile

# 안드로이드 SDK (애플 실리콘이라 arm64 이미지)
sdkmanager "platform-tools" "emulator" "platforms;android-36" "build-tools;36.0.0" \
  "system-images;android-36;google_apis;arm64-v8a"
flutter doctor --android-licenses

# 흐름 시험
curl -fsSL "https://get.maestro.mobile.dev" | bash
```
끝나면 `flutter doctor` 가 iOS · Android 둘 다 초록이어야 합니다.

### 4-3. 폰 연결 (🙋, 폰 화면을 눌러야 함)
USB 허브(전원 있는 것)로 폰들을 맥 미니에 상주시킵니다.

**아이폰 12**
- USB 연결 → 「이 컴퓨터를 신뢰」 → 설정 → 개인정보 보호 및 보안 → **개발자 모드** 켜기(재시동).
- Xcode → Window → Devices and Simulators 에서 보이는지. Xcode → Settings → Accounts 에 Apple ID
  로그인(개발용 서명 자동 발급).
- 설정: 자동 잠금 안 함 · 화면 밝기 최소 · 자동 업데이트 끔 · 알림 요약 끔 · 시험용 Apple ID(샌드박스
  구매 시험용 계정은 App Store Connect → 사용자 및 액세스 → 샌드박스 테스터).
- 계속 충전하면 배터리가 부풉니다. 「최적화된 충전」 켜고, 가능하면 스마트 플러그로 하루 몇 시간만 충전.

**안드로이드 폰들**
- 개발자 옵션 → **USB 디버깅** (샤오미는 「USB 디버깅(보안 설정)」도) · 「충전 중 화면 켜짐 유지」.
- 잠금 화면 없음 · 자동 업데이트 끔 · 시험용 구글 계정(라이선스 테스터로 등록하면 구독 시험이 무료).
- 삼성: 설정 → 배터리 → **배터리 보호(최대 85%)**.
- `adb devices` 에 전부 `device` 로 보이면 끝.
- **주인이 실제로 쓰는 폰은 연결하지 않습니다.** 시험 기기는 공장 전용으로 초기화한 폰만.

기기 이름 · 시리얼 · OS 판을 `docs/factory/QUALITY.md` 「기기표」에 적습니다 🤖.

### 4-4. GitHub 러너 등록 (🙋 토큰 복사 → 🤖)
`app-factory` → Settings → Actions → Runners → New self-hosted runner → macOS · ARM64 에 나오는
명령을 그대로 실행하되, 라벨을 붙입니다:
```bash
./config.sh --url https://github.com/<주인>/app-factory --token <화면의 토큰> \
  --name macmini-lab --labels lab,macos,ios,android --work _work
./svc.sh install && ./svc.sh start      # 로그인 세션에서 도는 서비스(LaunchAgent)
```
워크플로에서 `runs-on: [self-hosted, lab]` 이면 맥 미니로 갑니다. 한 번에 한 잡만(메모리 16GB).

### 4-5. 맥 미니의 Claude (🙋 로그인)
```bash
curl -fsSL https://claude.ai/install.sh | bash
claude                         # /login 으로 claude.ai 로그인
claude mcp add --scope user mobile-mcp -- npx -y @mobilenext/mobile-mcp@latest
```
- `/config` → 「Push when actions required」 「Push when Claude decides」 켜기 — 폰으로 알림.
- `~/.claude/settings.json`(lab 사용자)에 `"crossSessionInbound": "accept"` · `"dialogExpiry": "never"` — 클라우드
  스레드의 메시지가 **승인 창 없이** 들어오게. MyBody 에서 SendMessage 가 승인에 걸려 문서 우편함으로 후퇴한 원인이
  이 설정입니다([SESSIONS.md](SESSIONS.md) 3절).
- 상주 세션(폰에서 들여다보기 · 급한 일 맡기기) — bypass 가 아니라 **auto** 로:
  ```bash
  tmux new -d -s lab 'cd ~/lab/app-factory && claude remote-control --name mac-lab --spawn worktree --permission-mode auto'
  ```
  claude.ai/code 나 Claude 앱의 세션 목록에 `mac-lab` 이 보입니다.
- 워크플로 안에서 AI 탐색 시험을 돌릴 때는 `claude setup-token` 으로 만든 토큰을 저장소 Secret
  `CLAUDE_CODE_OAUTH_TOKEN` 으로 넣습니다(구독 한도에서 차감).

---

## 5. 앱마다 한 번 — 업로드 열쇠 (🤖 맥 미니에서)

새 앱을 출시 준비(S6)까지 올리면 Claude 가 맥 미니에서 스크립트를 돌려:
1. 앱 전용 업로드 열쇠(.jks)를 만들고, 2. 비밀번호와 함께 `gh secret set` 으로 저장소에 넣고,
3. 사본을 `~/app-keys/<앱>/`(맥 미니 로컬, 저장소 밖)에 둡니다.

Claude 는 열쇠 파일 내용을 보지 않습니다(훅이 막음). 주인은 `~/app-keys` 를 **비밀번호 관리자나
외장 저장소에 한 번 백업**하세요. 플레이 앱 서명을 쓰므로 업로드 열쇠를 잃어도 구글 지원으로
재설정할 수는 있지만 며칠 걸립니다.

> MyBody 에서 이 단계는 주인이 pepk.cmd 를 더블클릭하던 일입니다. 새 앱은 처음부터 플레이 앱
> 서명(구글이 앱 서명 키 보관)으로 만들므로 pepk 단계가 없습니다.

---

## 6. 윈도우 노트북 — 예비 실험실 (선택)

- 제어판 → Windows 기능 → **Windows 하이퍼바이저 플랫폼** 켜기(관리자, 재시동). 꺼져 있으면
  에뮬레이터가 안 뜹니다(MyBody 때 확인한 것).
- MyASUS 또는 Armoury Crate → **배터리 관리 충전 모드(80%)**. 덮개 닫아도 잠자지 않게.
- 러너를 `--labels lab-win,android` 로 등록하고 서비스로. 에뮬레이터는 `-no-window` 로 돌리면
  화면 세션 없이도 됩니다.
- 여기엔 스토어 열쇠 · 업로드 열쇠를 두지 않습니다.

---

## 7. Claude 쪽 설정 (🙋 10분)

### 클라우드 환경
claude.ai/code → 환경 설정(기존 MyBody 환경을 복제해도 됨):
- **설정 스크립트**: Flutter(CI 와 같은 판) · Java 17 설치 — 캐시되므로 세션마다 다시 안 깝니다.
- **네트워크**: Custom → 기본 목록 + `itunes.apple.com` · `play.google.com` (조사 단계가 스토어
  검색 결과를 읽음) · `pub.dev` · `storage.googleapis.com`(Flutter).
- 스토어 열쇠는 **넣지 않습니다.** 클라우드 세션은 스토어에 직접 닿을 일이 없습니다.

### 루틴 (claude.ai/code/routines)
| 이름 | 언제 | 무엇 |
|---|---|---|
| 하루 요약 | 매일 21:00 | `daily-digest` 스킬 — 새 세션, **푸시 알림 켬** |
| 주간 포트폴리오 | 일요일 10:00 | 출시 앱 지표로 계속/개선/정리 판정 초안, 대기열 주제 다음 순서 |
| 출시 뒤 살피기 | 출시(Release) 이벤트 | 크래시 · 리뷰 · 단계적 배포 비율 확인 |

루틴은 GitHub 트리거가 **PR 과 릴리스만** 받습니다(이슈는 안 받음). 그래서 주제 접수는 이슈가 아니라
Claude 앱에서 새 세션을 열어 `/new-app <주제>` 로 합니다.

### 프로젝트 (claude.ai/code → Projects, 계정에 열려 있으면)
- 새 프로젝트 「앱 공장」 · 저장소는 **`app-factory` 하나만**(하나여야 저장소의 훅 · 권한 규칙이 스레드에 적용됩니다) ·
  환경은 위 공장 환경.
- Project settings → Memory → **프로젝트 지침**에 `seed/CLAUDE.md` 의 §2 · §5 · §6 요약(16,000자 안)을 붙입니다.
- 첫 메시지: "주제를 주면 스레드 하나로 `/new-app` 을 돌려. 스레드는 앱마다 하나, 동시에 두 개까지. 시작 전에 묻지 말고 시작해."
- 하루 요약 루틴은 프로젝트 대화에서 "매일 21시에 daily-digest 를 돌리는 루틴 만들어 줘" 로 — Routines 탭에 붙습니다.
- Projects 가 아직 안 보이면(점진 배포) 아래 방식으로 시작하고, 열리면 세션에서 「Continue as a project」.

### 주제를 던지는 법 (매번)
- **프로젝트가 있으면**: Claude 앱 → 프로젝트 「앱 공장」 대화에 `운동 기록 없이 쓰는 단백질 계산기` 한 줄. 공장장이
  스레드를 열어 `/new-app` 을 돌립니다. 진행은 Overview, 멈추려면 같은 대화에 "습관 멈춰".
- **없으면**: Claude 앱 → Code → 새 세션 → 저장소 `app-factory` · 공장 환경 → `/new-app <주제>`. 그 세션이 그 앱의
  담당 세션이 되어 출시 요청까지 갑니다.

세션끼리 어떻게 말을 주고받는지는 [SESSIONS.md](SESSIONS.md).
