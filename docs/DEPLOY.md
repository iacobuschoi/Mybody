# 배포

> **처음이면 [START.md](START.md) 를 보세요.** 거기가 "내 컴퓨터에서 띄워서
> 폰으로 쓰기" 까지 10분짜리 길입니다.
>
> 이 문서는 그 뒤입니다 — 남에게 주소를 줄 때 확인할 것들, 환경변수를 직접
> 다룰 때의 이야기, 그리고 알고 올려야 하는 것들.

---

## 0. 내 이름과 연락처를 정하기 (한 번만)

앱이 다루는 것은 몸에 대한 숫자입니다 — 개인정보보호법이 말하는
**민감정보(건강에 관한 정보)** 입니다. 그래서 개인정보처리방침에
"이 서버를 운영하는 사람이 누구이고 어디로 연락하면 되는지" 가
적혀 있어야 합니다. 그 칸은 코드가 알 수 없으니 여기서 정합니다.

```bash
echo 'export MYBODY_OWNER="김아무개"'            >> ~/.mybody-env
echo 'export MYBODY_CONTACT="me@example.com"'    >> ~/.mybody-env
```

연락처는 메일 주소든 오픈채팅 링크든, **받는 사람이 실제로 읽는 곳**이면
됩니다. 안 적으면 방침에 "아직 적지 않았습니다" 가 그대로 나가고,
아래 점검이 빨간 줄로 막습니다.

> 이 문서는 법률 자문이 아닙니다. 친구 몇 명과 쓰는 것과 불특정 다수에게
> 여는 것은 지는 의무가 다릅니다. 널리 열 생각이면 자기 상황을 한 번
> 확인해 보세요.

---

## 1. 한 번만 확인 (2분)

```bash
source ~/.mybody-env
OWNER="$MYBODY_OWNER" OWNER_CONTACT="$MYBODY_CONTACT" node tools/preflight.js
```

빨간 줄이 하나도 없으면 배포해도 됩니다. 빨간 줄이 있으면 그것만 고치세요 —
무엇을 고쳐야 하는지 줄마다 적혀 있습니다.

---

## 2. 서버 띄우기

### 처음 한 번

```bash
# 가입 코드를 만들어 파일에 저장 (이걸 아는 사람만 계정을 만들 수 있습니다)
openssl rand -hex 16 > ~/.mybody-pair
chmod 600 ~/.mybody-pair
```

### 매번

```bash
cd ~/Mybody
source ~/.mybody-env

# release/ 생성 — 방침의 운영자 칸이 여기서 채워집니다
OWNER="$MYBODY_OWNER" OWNER_CONTACT="$MYBODY_CONTACT" node tools/build-release.js

PAIR_SECRET=$(cat ~/.mybody-pair) \
STATIC=./release \
ORIGIN=https://내주소.example.com \
TRUST_PROXY=1 \
node server/server.js
```

`TRUST_PROXY=1` 은 터널을 쓸 때 넣으세요. 터널 뒤에서는 모든 사람이
같은 IP 로 보이는데, 서버의 요청 제한은 IP 당입니다 — 넣지 않으면
다섯 명이 분당 300 회를 나눠 쓰고, 한 사람이 많이 쓰면 나머지가
막힙니다. 터널(cloudflared)이 붙여 주는 실제 IP 를 믿고 사람별로
셉니다. **터널 없이 직접 여는 경우에는 넣지 마세요** — 그러면
아무나 헤더를 꾸며서 제한을 우회할 수 있습니다.

`STATIC=./release` 가 핵심입니다. 이걸 빼면 개발 빌드(`prototype/`)가 나가고,
쓰는 사람 화면에 고유번호 배지가 전부 뜹니다.

### 자동 판독까지 켤 거면

```bash
ANTHROPIC_API_KEY=sk-ant-... \
PAIR_SECRET=$(cat ~/.mybody-pair) STATIC=./release node server/server.js
```

키가 없으면 자동 판독만 꺼지고 나머지는 그대로 돕니다. 사용자도 설정에서
직접 켜야 하므로, 키를 넣어도 본인이 안 켜면 사진은 한 장도 안 나갑니다.

---

## 3. 밖에서 접속하게

> **주소는 한 번 정하면 바꾸지 마세요.** 측정 기록은 브라우저가 주소별로
> 따로 저장합니다. 주소가 바뀌면 친구들 폰에서 그동안의 기록이 통째로
> 안 보이게 됩니다 — 지워진 건 아니지만 새 주소에서는 없는 것과 같고,
> 본인은 그걸 알 방법이 없습니다. 그래서 **이름 있는 터널이 기본**입니다.

### 이름 있는 터널 (권장 — 주소가 안 바뀝니다)

```bash
cloudflared tunnel login                       # 한 번만, 브라우저로 로그인
cloudflared tunnel create mybody
cloudflared tunnel route dns mybody mybody.내도메인.com
cloudflared tunnel run --url http://localhost:8080 mybody
```

도메인이 하나 있어야 합니다(연 1~2만원). 노트북을 껐다 켜도 주소가
그대로라서, 친구들이 한 번 깐 앱을 계속 씁니다.

### 임시 터널 (도메인 없이 바로, 대신 주소가 매번 바뀝니다)

```bash
cloudflared tunnel --url http://localhost:8080
```

`https://xxxx.trycloudflare.com` 이 나옵니다. **띄울 때마다 다른 주소**가
나오므로, 혼자 시험해 볼 때만 쓰세요. 친구에게 주소를 줬다가 바뀌면
그 친구의 기록은 옛 주소에 남고 새 주소에서는 처음부터 시작합니다.

**HTTPS여야 합니다** — 서비스워커와 카메라가 HTTP에서는 안 돕니다.
어느 쪽이든 그 주소를 `ORIGIN` 에도 넣고 서버를 다시 띄우세요.

더 사적으로 하려면 Tailscale (`tailscale serve https / http://localhost:8080`) —
주소가 고정이지만 상대도 Tailscale 을 깔아야 합니다.

### 주소가 이미 바뀌었다면

옛 주소를 아직 알고 있다면 그 주소로 들어가 **설정 → 내보내기 → 파일로
저장** 을 하고, 새 주소에서 **설정 → 가져오기** 로 넣으면 그대로 돌아옵니다.
친구들에게 새 주소를 주기 전에 이 말을 같이 해 주세요.

---

## 4. 폰에 앱처럼 깔기

주소를 열고:

- **iPhone (Safari)** — 공유 → 홈 화면에 추가
- **Android (Chrome)** — 주소창 옆 설치 아이콘, 또는 메뉴 → 앱 설치

깔고 나면 주소창 없이 뜨고, 인터넷이 끊겨도 열립니다.

---

## 5. 백업

```bash
node tools/backup.js            # 서버를 끄지 않아도 됩니다

# 매일 새벽 4시 (crontab -e). node 의 전체 경로를 적으세요.
0 4 * * * cd ~/Mybody && /usr/local/bin/node tools/backup.js
```

**`cp server/mybody.db` 로는 안 됩니다.** WAL 방식이라 서버가 켜져 있는
동안 새 기록은 곁파일(`mybody.db-wal`)에 쌓입니다. 본파일만 복사하면
테이블조차 없는 파일이 나옵니다 — 실제로 확인했습니다. `tools/backup.js`
는 SQLite 에게 직접 온전한 사본을 만들게 시킵니다(VACUUM INTO).

sqlite3 명령은 안 씁니다. 대부분의 컴퓨터에 안 깔려 있어서, 그걸 쓰는
크론을 적어 두면 조용히 한 번도 안 돕니다 — 그러다 정작 필요할 때
백업이 하나도 없습니다.

30일 지난 백업은 알아서 지웁니다. 누가 계정을 지워도 옛 백업에는 그
사람의 체중·체지방이 그대로 남습니다. 지우기로 한 것이 어딘가에 남아
있으면 지운 게 아닙니다. 30일은 "실수로 지웠을 때 되살릴 수 있는 기간"
과 "필요 없는 건강정보를 오래 안 들고 있기" 사이에서 고른 숫자이고,
방침에 적힌 숫자와 같습니다.

되돌릴 때는 서버를 먼저 끄고 `node tools/backup.js --restore <파일>`.

DB 파일 하나에 전부 들어 있습니다. 사진은 서버가 아니라 각자 기기에만
있으므로 백업 대상이 아닙니다 — 그 말은 폰을 잃어버리면 사진도 같이
사라진다는 뜻입니다.

---

## 6. 친구 들이기

1. 친구에게 **주소**와 **가입 코드**(`~/.mybody-pair` 내용)를 줍니다.
2. 친구가 계정을 만듭니다. 가입 코드는 가입할 때만 필요합니다.
3. 앱 안에서 서로 **초대 코드**를 주고받아 친구를 맺습니다.
   (전화번호·이메일로는 서로를 찾을 수 없습니다. 의도한 것입니다.)
4. 공유는 기본이 거의 다 꺼져 있습니다. 친구마다 항목을 직접 켜야 나갑니다.

---

## 7. 구글 플레이에 올리기

친구 10명에게만 줄 거면 **비공개 테스트 트랙**까지만 하면 됩니다(스토어 검색에는
안 나오지만 참여 링크로 설치·자동 업데이트가 됩니다). 정식 출시(프로덕션)는
2023-11-13 이후 만든 개인 계정이면 **테스터 12명 이상이 14일 연속** 참여한 뒤
「프로덕션 액세스 신청」을 통과해야 합니다.

### 올리기 전에 (한 번)

1. **GitHub Pages 켜기** — 저장소 Settings → Pages → Source `Deploy from a branch`,
   Branch = 기본 브랜치, 폴더 `/docs` → Save. 잠시 뒤
   `https://iacobuschoi.github.io/Mybody/privacy.html` 과 `…/delete-account.html` 이 열려야
   합니다. 두 페이지의 **이메일 자리표시자**를 채우세요(콘솔에도 같은 주소를 적습니다).
2. **AAB 받기** — Releases 페이지의 `mybody-vX.Y.Z-playstore.aab`(다음 릴리스부터
   같이 올라옵니다) 또는 Actions → 최신 초록 실행 → Artifacts `app-N` 안의
   `app-release.aab`. versionCode 는 커밋 수라 어느 쪽이든 친구 폰의 것보다 큽니다.
3. **심사용 계정** — 서버에서 가입 코드로 계정 하나 만들고
   `node tools/reset-password.js <아이디>` 로 비밀번호를 정해 둡니다. 심사 기간에는
   노트북 서버와 터널을 켜 둡니다(로그인·판독·계정 삭제가 전부 서버입니다).

### 콘솔에서

4. **앱 만들기** — Play Console → 모든 앱 → 앱 만들기: 이름 `Mybody`, 한국어, 앱, 무료.
5. **앱 서명 — AAB 를 올리기 전에** — 「Google Play로 보호됨 → Play 스토어 배포 →
   Play 앱 서명」(구 메뉴: 테스트 및 출시 → 앱 무결성) → **앱 서명 키 변경 → Java 키
   저장소에서 내보내기 및 업로드**. 화면의 `pepk.jar` 와 암호화 키를 받아 노트북에서:
   ```
   java -jar pepk.jar --keystore=%USERPROFILE%\mybody-signing-key\mybody.jks --alias=mybody ^
     --output=mybody-pepk.zip --include-cert --rsa-aes-encryption ^
     --encryption-key-path=encryption_public_key.pem
   ```
   나온 zip 을 올립니다. **이걸 건너뛰면** 구글이 새 열쇠를 만들어 플레이 판의 서명이
   지금 친구들 폰의 APK 와 달라지고, 친구들은 앱을 지웠다 다시 깔아야 합니다.
   등록 뒤 페이지의 SHA-256 이 `06d945a3…83de11` 인지 확인합니다.
6. **앱 콘텐츠**(정책 및 프로그램 → 앱 콘텐츠) — 개인정보처리방침 URL / 앱 액세스
   「일부 기능 제한」+ 심사용 아이디·비밀번호·가입 코드 / 광고 없음 / 콘텐츠 등급 설문 /
   타겟층 18세 이상 / 뉴스 앱 아니오 / 정부 앱 아니오 / 금융 기능 없음 / 광고 ID 사용 안 함 /
   **건강 앱**: 건강 및 피트니스 → 「활동 및 피트니스」+「영양 및 체중 관리」, 의료 아님 /
   **데이터 보안**: 수집 = 사용자 ID·이름, 건강 정보·피트니스 정보, 사진(선택);
   공유 없음; 전송 암호화 예; 삭제 요청 가능 예; 계정 삭제 URL =
   `https://iacobuschoi.github.io/Mybody/delete-account.html`.
7. **스토어 등록정보** — 아이콘 512×512(`prototype/assets/icon-512.png`), 그래픽 이미지
   1024×500(새로 만들어야 함), 폰 스크린샷 2장 이상(`tools/.shots/flutter/`), 짧은 설명·
   자세한 설명. 설명 끝에 「이 앱은 의료기기가 아니며 진단·치료 목적이 아닙니다」 한 줄.
8. **내부 테스트 → 비공개 테스트** — 테스트 및 출시 → 테스트 → 내부 테스트 → 테스터
   이메일 목록(본인 Google 계정) → 새 버전 → AAB 업로드 → 출시. 첫 출시라 검토
   (몇 시간~7일)가 붙습니다. 되면 비공개 테스트 트랙에 친구들 이메일 목록을 넣고
   같은 버전을 승격 → 참여 링크를 친구들에게. 기존 APK 위에 업데이트로 깔립니다.
9. **(정식 출시를 원하면)** 12명·14일이 채워지면 대시보드 → 프로덕션 액세스 신청 →
   승인 뒤 프로덕션 트랙에 승격.

다음 판부터는 릴리스 워크플로가 만든 `-playstore.aab` 를 같은 트랙에 새 버전으로
올리면 됩니다.

---

## 8. 아이폰 — TestFlight 에 올리기 (맥 없이, 폰으로)

애플 개발자 계정(연 ₩129,000)이 승인된 뒤. 빌드도 서명도 깃허브의 맥 러너가
합니다 — 인증서·프로파일을 애플 API 로 러너가 직접 만들기 때문에(`tools/asc.js`)
**맥이 없어도 됩니다.** 폰 사파리로 아래 다섯 가지를 하면 끝입니다.

1. **App Store Connect API 키** — appstoreconnect.apple.com → 사용자 및 액세스 →
   통합 → App Store Connect API → 팀 키 「+」 → 이름 `github`, 액세스 **App Manager**.
   화면의 **Issuer ID** 와 **키 ID** 를 적고, **한 번만** 내려받을 수 있는 `.p8` 을
   받습니다. 폰이면 파일 앱에서 그 파일을 열어 내용(`-----BEGIN PRIVATE KEY-----`
   부터 `-----END PRIVATE KEY-----` 까지)을 그대로 복사합니다.
2. **깃허브 Secrets** — github.com 저장소 → Settings → Secrets and variables →
   Actions → New repository secret. 세 개:
   `ASC_ISSUER_ID`, `ASC_KEY_ID`, `ASC_KEY_P8`(.p8 내용 그대로 붙여넣기).
   (`MYBODY_SERVER_URL` 은 안드로이드 때 이미 있음.)
3. **App Store Connect 에 앱 만들기** — 나의 앱 「+」 → iOS, 이름은 `appstore/등록정보.md`
   후보 중 하나(`MyBody` 는 이미 있음), 기본 언어 한국어, 번들 ID
   `io.github.iacobuschoi.mybody`, SKU `mybody-ios`. 번들 ID 가 목록에 없으면
   4번을 먼저 한 번 돌리면 러너가 등록해 줍니다(그 실행은 앱이 없어 올리기에서
   멈추지만 번들 ID 는 남습니다). 또는 developer.apple.com → Identifiers 에서 직접 등록.
4. **돌리기** — github.com → Actions → 「아이폰 TestFlight」 → Run workflow → 판 번호.
   러너가 열쇠·CSR 을 만들고 → 배포 인증서 발급 → 프로파일 생성 → 서명 → 올리기.
   10분쯤 뒤 App Store Connect → TestFlight 에 빌드가 나타나고(처리 10~30분)
   내부 테스터에게 바로 갑니다.
5. **테스터** — App Store Connect → TestFlight → 내부 테스팅 「+」 그룹에 본인 Apple
   계정 추가 → 아이폰에 TestFlight 앱 설치 → 초대 수락. 외부 테스터(친구들)는 첫
   빌드만 베타 심사(하루 안팎).

실행할 때마다 지난 실행이 만든 인증서를 폐기하고 새로 만듭니다(열쇠가 러너와
함께 사라지므로). 이미 올라간 빌드에는 영향이 없습니다. 배포 인증서 한도(팀당
몇 개)에 걸리면 러너가 어디서 무엇을 지우라고 말합니다.

**맥에서 만든 인증서를 쓰고 싶으면** (선택) — Xcode → Settings → Accounts → Manage
Certificates → Apple Distribution → 키체인에서 `.p12` 내보내기, developer.apple.com →
Profiles 에서 App Store 프로파일 내려받기. `base64 -i 파일 | pbcopy` 로
`IOS_CERT_P12_BASE64`, `IOS_CERT_PASSWORD`, `IOS_PROFILE_BASE64` 를 넣으면 그쪽을 씁니다.

---

## 9. 새 판을 낸 뒤 — 앱 안 업데이트 안내

앱(0.2.8 부터)은 켤 때 서버에 `GET /api/version` 을 묻고, 자기 판이 낮으면 홈
화면 맨 위에 안내를 띄웁니다. 앱스토어·플레이는 알아서 업데이트하지만, GitHub
에서 APK 를 받아 깐 친구는 이 안내가 없으면 새 판이 나온 것을 모릅니다.

값은 **서버가 도는 컴퓨터에서, 서버를 돌리는 사용자로** `tools/app-version.js` 로
적습니다(그 사용자의 `~/.mybody/config.json` 에 들어갑니다). 서버를 다시 띄울 필요는
없습니다. 앱은 6시간에 한 번까지만 묻기 때문에 폰에 뜨기까지 몇 시간 걸릴 수 있습니다.

**처음 한 번은 서버를 이 코드로 올리고 다시 띄워야 합니다.** 그 전의 서버에는
`/api/version` 이 없어서, 값을 적어도 안 나갑니다. 맥은
`cd ~/mybody-server && git pull --ff-only && sudo launchctl kickstart -k system/com.mybody.server`,
오라클은 `bash ~/mybody/tools/oracle-setup.sh update`. 도구는 적은 뒤 이 컴퓨터의 서버에
직접 물어서, 꺼져 있거나 · 옛 서버 코드이거나 · 다른 설정 파일을 읽고 있으면 그렇다고
말합니다. "확인했습니다" 가 나오면 나가는 것입니다.

| 언제 | 명령 |
|---|---|
| GitHub Release 에 APK 가 올라간 직후 | `node tools/app-version.js --apk=0.2.8` |
| 플레이 출시가 끝나 받을 수 있게 된 뒤 | `node tools/app-version.js --play=0.2.8` |
| 앱스토어 심사를 지나 배포가 시작된 뒤 | `node tools/app-version.js --appstore=0.2.8` |
| 지금 값 보기 | `node tools/app-version.js` |

**가게에 실제로 올라가기 전에는 올리지 마세요.** [업데이트] 단추는 그 가게의 앱
페이지를 엽니다. 아직 그 판이 없으면 눌러도 옛 판 그대로이고, 안내는 계속 뜹니다.
심사 중인 판을 먼저 적으면 심사가 끝날 때까지 아이폰 쓰는 사람 모두가 그 상태입니다.
그래서 가게마다 따로 적습니다. 잘못 올렸으면 `--appstore=none` 처럼 지우면 됩니다.

TestFlight 로 받은 사람에게는 새 판 안내를 안 합니다 — TestFlight 가 알아서
알려 줍니다. 앱스토어 값을 같이 보지만, 아래의 최소판 안내만 받습니다.

플레이에 올리는 AAB 는 `STORE=play` 로 만들어져서(`apk.yml`) 누가 깔았든 플레이 안내만
합니다. 플레이의 출시 전 보고서는 앱을 adb 로 까는데, 그걸 직접 깐 APK 로 보면 플레이
기기에 "GitHub 에서 새 APK 를 받으세요" 가 뜹니다 — 플레이 밖 업데이트로 이끄는 것은
플레이 정책 위반입니다. 그래서 **AAB 는 꼭 이 빌드(Releases 나 Actions)의 것을** 올립니다.

### 최소판 — 서버가 옛 앱을 더는 못 받게 됐을 때만

`node tools/app-version.js --min=0.2.9` 처럼 적으면 그보다 낮은 앱은 **닫을 수 없는**
안내를 봅니다(홈 맨 위, 그리고 로그인·첫 설정 화면). 이 판은 서버와 맞지 않아
로그인·동기화·친구가 안 될 수 있다는 말입니다(기기 안의 기록은 그대로 씁니다).

- **안내는 0.2.8 부터 앱에 들어 있습니다.** 0.2.7 이하 앱은 이 값을 몰라서 아무것도
  못 봅니다 — 그래서 0.2.8 이하의 최소판은 누구에게도 안 뜹니다(도구가 그렇다고
  말해 줍니다). 0.2.7 이하를 쓰는 친구에게는 따로 알려야 합니다.
- 서버를 고쳐서 옛 앱의 요청을 **정말로 거절하게 됐을 때만** 올립니다. 동의 판을
  올렸을 때처럼 서버가 옛 판도 받아 주는 동안에는 올릴 이유가 없습니다.
- 그 판이 **모든 가게에** 올라간 뒤에 올립니다. 도구는 어느 가게의 최신판보다
  높은 최소판을 거절합니다 — 그 가게로 깐 사람은 받을 판이 없기 때문입니다.
- 지우려면 `--min=none`.

단추가 여는 주소를 바꾸려면 `~/.mybody/config.json` 에 `appUrlAppStore` ·
`appUrlPlay` · `appUrlApk` 를 적습니다(https 만). 비워 두면 기본 주소(앱스토어 앱
페이지 · 플레이 앱 페이지 · GitHub 최신 릴리스)입니다.

## 되돌리기

배포한 게 잘못됐으면:

```bash
git checkout <이전-커밋> -- prototype/
node tools/build-release.js
# 서버 재시작
```

DB 는 건드리지 않습니다. 코드만 되돌아갑니다.

---

## 아직 안 되는 것 (알고 배포하는 것들)

| | 왜 |
|---|---|
| 비밀번호와 복구 코드를 둘 다 잃으면 | 그때는 길이 없습니다. 서버 주인이 DB 에서 계정을 지우고 다시 만들어야 하고, 친구 관계와 주간 기록이 같이 사라집니다. |
| 상시 접속 | 컴퓨터가 꺼지면 친구도 못 봅니다. 늘 켜 두는 기계로 옮겨야 해결됩니다 — 맥미니는 `docs/MAC.md`, 오라클 무료 VM 은 `docs/ORACLE.md`. |
| 사진 백업 | 사진은 기기에만 있습니다. 폰을 잃으면 사진도 잃습니다. 숫자는 서버에 있어 남습니다. |
| 측정 기록 백업 | 측정 기록은 서버로 안 올라갑니다. 설정 → 내보내기 → 파일로 저장으로 각자 챙겨야 합니다. |
| 주소가 바뀌면 | 브라우저는 주소별로 따로 저장합니다. 새 주소는 처음부터 시작합니다 — 이름 있는 터널을 쓰세요. |
| 여러 기기 동시 수정 | 나중에 저장한 쪽이 이깁니다. 혼자 쓰면 문제되지 않습니다. |

친구에게 주소를 줄 때 이 넷을 한 번 말해 주세요. 나중에 알게 되는 것과
미리 아는 것은 다릅니다.

남에게 **파는** 앱으로 갈 거면 위의 것들에 더해, 개인정보처리방침을
자기 상황에 맞게 다시 검토하고 약관을 따로 갖춰야 합니다.
