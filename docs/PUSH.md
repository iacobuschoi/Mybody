# 앱 알림(푸시) — 안드로이드 FCM · 아이폰 APNs

친구의 운동 독촉이 **앱이 아니라 크롬으로** 왔습니다. 앱에는 서버가 밀어 주는 길이 없었고
(앱은 켜질 때만 독촉을 가져갔습니다), 예전 웹 앱이 크롬에 남긴 웹 푸시 구독만 살아 있었기
때문입니다. 그래서 진짜 앱 알림을 넣었습니다. 안드로이드는 FCM(Firebase Cloud Messaging)이
직접 보내고, 아이폰은 FCM 이 애플의 APNs 로 넘겨 줍니다. 서버는 FCM 하나만 부릅니다.

**비밀이 하나도 없어도 지금처럼 빌드되고 돌아갑니다.** 설정이 없으면 앱은 알림 없이 켤 때
독촉을 가져가고, 서버는 예전처럼 웹 푸시만 씁니다. 켜는 순서는 [5절](#5-처음-켜기)이고,
노트북이 할 몫은 `docs/LOCAL-TASKS.md` 28절입니다.

---

## 1. 구조

```
 앱(안드로이드 · 아이폰)
   │  로그인해 있으면 켜질 때마다: Firebase 가 준 이 기기의 알림 주소(FCM 토큰)를
   │  POST /api/push/device {token, platform, appVersion, permission, secret}
   ▼
 서버 (server.js · db.js)
   push_devices 표 — 토큰을 **지금 로그인(세션)** 에 묶어 둡니다.
   로그아웃 · 모든 기기 로그아웃 · 비밀번호 변경 · 탈퇴 · 만료(서버가 뜰 때와 하루 한 번 정리) 때
   세션과 같이 지워집니다.
   │
   │  독촉 · 친구 요청 · 친구 수락 · 운동 소식 → pushToUser(사람, 알림)
   │
   ├─▶ FCM HTTP v1 (server/fcm.js, 의존성 0)
   │     1) 서비스 계정 열쇠로 JWT(RS256)를 만들어 → oauth2.googleapis.com 에서 접근 토큰(55분 캐시)
   │     2) POST fcm.googleapis.com/v1/projects/<프로젝트>/messages:send
   │           ├─ 안드로이드: FCM 이 폰으로 — 채널 'friends' · 아이콘 ic_stat_mybody
   │           └─ 아이폰:    FCM → APNs(Firebase 에 올린 APNs 열쇠 .p8 로) → 폰
   │
   └─▶ 웹 푸시(VAPID, server/push.js) — 최근 30일 안에 앱을 등록한 기기가 없는 사람에게만
```

- **누가 받는가**는 부르는 쪽이 정합니다(공유 설정 · 차단). 운동 소식은 일정을 보여 주기로 한
  친구에게만 갑니다. 알림이 공유 설정을 우회하는 뒷문이 되지 않게 `pushToUser` 는 사람을 늘리지 않습니다.
- **크롬은 조용히.** FCM 이 켜진 서버에서, 그 사람이 최근 30일 안에 알림을 거절하지 않은 앱을
  등록했으면 웹 푸시를 보내지 않습니다(같은 독촉이 두 번 울리던 것). 알림을 거절한 폰은 "앱이
  있다" 로 치지 않고, 앱 쪽이 **우리 설정 문제**(접근 토큰 실패 · APNs 열쇠 없음 · 401/403)로 전부
  막혔을 때도 크롬으로 보냅니다 — 아무 데서도 못 받는 일이 없게.
- **독촉은 두 번 안 뜹니다.** FCM 이 한 기기에라도 받는 **즉시**(나머지 기기를 기다리지 않고) 그 독촉을
  `pushed` 로 표시해서, 앱이 켜질 때 가져가도 다시 띄우지 않습니다. 표시가 적히기 전에 가져간 경우는 앱이
  막습니다 — 앱 알림과 가져오기 중 번호를 먼저 잡은 쪽만 띄우고(`NativePush.claimPoke`), 안드로이드에서는
  둘이 같은 칸(tag `poke-<번호>`, 번호 0)을 써서 늦게 온 쪽이 덮어씁니다.
- **FCM 에는 일반 문구만.** 웹 푸시는 종단 암호화지만 FCM 의 notification 은 평문이라 구글과 애플(APNs)이
  읽습니다. 그래서 앱 알림은 「친구가 운동하라고 콕 찔렀어요」 · 「친구가 운동했어요」 · 「친구 요청이 왔어요」 처럼
  무슨 일인지만 싣고, 이름 · "이번 주 N일째" · 공유 기본값은 웹 푸시(암호화)에만 실립니다(`server.js` `APP_TEXT`).
  누구인지는 앱이 열린 뒤 서버에서 가져와 보여 줍니다. 알림 칸을 모으는 tag 도 사용자 id 가 아니라 독촉 번호
  (`poke-<번호>`) 또는 받는 사람별 HMAC(`news-…` · `friend-…`, 서비스 계정 열쇠에서 끌어냄)입니다.
- **알림을 거절한 기기로는 FCM 을 보내지 않습니다**(`permission: 'denied'`) — 띄우지도 못할 문구를 구글에 넘기지
  않고, 그 사람은 크롬(웹)으로 받습니다.
- **구글 등록은 로그인한 뒤에만.** 매니페스트 · Info.plist 에서 FCM 자동 초기화를 꺼 두고, 앱이 서버에 등록할 때
  켜고 로그아웃하면 끕니다. 「로그인 없이 쓰기」 사용자는 구글에 설치 ID · 토큰이 생기지 않습니다.
- **토큰만으로는 남의 기기를 못 가져갑니다.** 앱은 서버마다 따로 만든 난수 비밀(`secret`)을 같이 보내고,
  서버는 그 해시만 둡니다. 이미 **다른 계정의 살아 있는 로그인**에 묶인 토큰은 비밀이 맞을 때만 옮기고,
  아니면 409 입니다. `DELETE /api/push/device` 는 남의 토큰이어도 아무것도 지우지 않고 똑같이 200 으로 답합니다.
- **서버 주소를 바꾸면** 앱이 옛 서버에 이 기기를 빼 달라고 말하고(4초), 토큰도 새로 받아 새 서버에만 등록합니다.
- 알림의 `data.route` 는 `pokes` · `social` 두 가지만 앱이 따라갑니다. 모르는 값은 버립니다.
- 앱이 **앞에 떠 있을 때**: 아이폰은 AppDelegate 가 시스템 배너를 띄우게 해 두었고, 안드로이드는
  FCM 이 띄우지 않으므로 앱이 같은 'friends' 채널로 직접 띄웁니다(`app/lib/src/native_push.dart`).
- 앱 설정 화면의 「푸시 알림」 줄이 지금 상태(켜짐 · 꺼짐 · 서버 미지원)를 보여 주고, 예전 웹 앱의
  크롬 구독이 남아 있으면 「크롬(웹) 알림 끄기」 가 나옵니다(`DELETE /api/push/web`).

---

## 2. 비밀과 파일 — 무엇이 어디에

**저장소는 공개입니다.** 아래 파일은 어느 것도 저장소에 넣지 않습니다. `.gitignore` 가
`google-services.json` · `GoogleService-Info.plist` · `fcm-service-account.json` ·
`*service-account*.json` · `*.p8` 을 막고 있습니다.

| 무엇 | 얼마나 비밀인가 | 두는 곳 | 쓰는 쪽 |
|---|---|---|---|
| `google-services.json` (안드로이드 앱 설정) | 비밀 아님 — 안의 API 키는 APK 에 그대로 들어가 공개됩니다. 막는 것은 **API 키 제한**(LOCAL-TASKS 28 의 5-1). 저장소에는 안 둠 | GitHub Secret **`FIREBASE_ANDROID_JSON_B64`** (파일의 base64 한 줄). 원본은 노트북 `~/.mybody/firebase/` | CI 가 `app/android/app/google-services.json` 으로 풀어 빌드 |
| `GoogleService-Info.plist` (아이폰 앱 설정) | 위와 같음(IPA 안에 그대로 들어감) | GitHub Secret **`FIREBASE_IOS_PLIST_B64`** (base64 한 줄). 원본은 노트북 `~/.mybody/firebase/` | CI 가 `app/ios/Runner/GoogleService-Info.plist` 로 풀고, Xcode 의 「Copy GoogleService-Info」 단계가 앱에 복사 |
| 서비스 계정 JSON — **FCM 보내기 전용 계정** `mybody-fcm-sender`(역할 「Firebase Cloud Messaging API 관리자」 하나). Firebase Admin SDK 열쇠는 쓰지 않음(프로젝트 전체 관리자 권한) | **진짜 비밀** — 있으면 누구나 우리 이름으로 알림을 쏠 수 있음 | **서버 컴퓨터**의 `~/.mybody/fcm-service-account.json` (권한 600 — 넓으면 서버가 뜰 때 경고). **CI 에는 절대 안 넣음** | `server/fcm.js` |
| APNs 인증 키 `AuthKey_<Key ID>.p8` | **진짜 비밀** — 한 번만 내려받을 수 있음 | Firebase 콘솔에 올리고, 원본은 노트북 `~/.mybody/` (권한 600). CI · 서버에는 안 넣음 | Firebase(FCM)가 APNs 에 보낼 때 |
| App Store Connect API 키 (`ASC_*`) | 비밀(기존) | GitHub Secrets (그대로) | CI 가 App ID 에 Push Notifications 를 켜는 데도 씀 |
| `app/ios/Runner/Runner.entitlements` | 비밀 아님 | 저장소(커밋됨). 프로젝트는 가리키지 않음 | CI 가 조건이 맞을 때만 서명에 붙임 |

서버가 서비스 계정 파일을 찾는 순서(앞이 이김):

1. 환경변수 `FCM_SERVICE_ACCOUNT` (경로)
2. `~/.mybody/config.json` 의 `fcmServiceAccount` (경로 — 열쇠 내용은 여기 적지 않습니다)
3. 기본값 `~/.mybody/fcm-service-account.json` (윈도우는 `%USERPROFILE%\.mybody\fcm-service-account.json`)

**서버를 돌리는 사용자**의 홈입니다. 윈도우 노트북은 작업 스케줄러 「Mybody 서버」 가 도는 계정,
맥미니는 `docs/MAC.md` 의 서버 사용자, 오라클은 VM 의 그 사용자입니다. 파일은 서버가 뜰 때 한 번
읽으므로, 놓거나 바꾼 뒤에는 **서버를 다시 띄워야** 합니다.

---

## 3. CI 가 하는 일

### 안드로이드 — `.github/workflows/apk.yml` (배포 `release.yml` 이 그대로 불러 씀)

1. 「앱 알림 설정 꺼내기」: `FIREBASE_ANDROID_JSON_B64` 가 없으면 **"푸시 설정 없음 — 푸시 없이 빌드"**
   를 찍고 넘어갑니다. 있으면 줄바꿈 · 공백을 버리고 풀어서, JSON 인지 · 이 앱의 패키지
   (`io.github.iacobuschoi.mybody`)가 있는지 · 앱 ID 가 있는지 봅니다. 하나라도 틀리면 파일을 치우고
   경고만 합니다(다른 앱의 파일이면 플러그인이 "No matching client found" 로 빌드를 깨기 때문).
   `project_info`(project_number · project_id)가 있는지, 앱 ID 가 `1:<숫자>:android:<16진수>` 모양인지도 봅니다 —
   아니면 google-services 플러그인이 빌드 자체를 깹니다. 안의 API 키는 `add-mask` 로 로그에서 가리지만 이건
   막는 수단이 아닙니다(같은 키가 APK 에 들어감). 막는 것은 API 키 제한입니다.
2. 빌드는 그대로입니다. `app/android/app/build.gradle.kts` 가 파일이 **있을 때만** google-services
   플러그인을 켭니다.
3. 「나온 앱에 앱 알림 설정이 있는가」: APK 의 리소스에 `google_app_id` 가 있는지 보고, 요약에
   `앱 알림(FCM): 켜짐 / 꺼짐 — 이유` 를 적습니다. 배포(`release.yml`) 요약에도 한 줄 남습니다.

### 아이폰 — `.github/workflows/ios-release.yml`

| 단계 | 하는 일 | 안 되면 |
|---|---|---|
| 앱 알림 설정 꺼내기 | `FIREBASE_IOS_PLIST_B64` 를 plist 로 풀고, `BUNDLE_ID` 가 이 앱인지 · 필요한 값이 있는지 · `GOOGLE_APP_ID` 가 `1:<숫자>:ios:<16진수>` · `GCM_SENDER_ID` 가 숫자 · `IS_GCM_ENABLED` 가 (있으면) true 인지 · Xcode 에 복사 단계가 있는지 봄 → `fcm=yes`. 모양이 틀린 plist 는 넣지 않음 — 넣으면 FirebaseApp.configure() 가 네이티브에서 던져 **앱이 켜지자마자 죽음** | 없으면 "푸시 설정 없음 — 푸시 없이 빌드", 틀리면 경고 · `fcm=no` |
| App ID 에 푸시 켜기 (자동 서명일 때만) | 서명 도구가 `--entitlements` 를 아는지 먼저 보고(`supportsEntitlements`), App Store Connect API 로 App ID 의 `PUSH_NOTIFICATIONS` 를 확인하고 없으면 켬(멱등, 409 는 "이미 있음") | 경고만. 판정은 다음 단계가 함 |
| 인증서·프로파일 만들기 | 예전 그대로 — 프로파일을 매번 새로 만들므로, 푸시가 켜진 App ID 면 `aps-environment=production` 이 저절로 들어옴 | — |
| 프로파일 설치 | 프로파일의 `Entitlements:aps-environment` 를 읽어 `profile_aps` 로 | — |
| 앱 타깃 서명 설정 | `fcm=yes` **이고** 프로파일에 aps 가 있을 때만 `Runner.entitlements` 에 그 값을 넣고 `tools/ios-sign-project.js --entitlements Runner/Runner.entitlements` 로 서명에 붙임. 붙었는지 프로젝트 파일에서 확인 | plist 를 치우고 `fcm=no` 로 내려 **알림 없이** 올림(경고) |
| 나온 앱에 앱 알림이 들어갔는가 | .ipa 를 열어 번들의 plist 와 서명의 aps-environment 를 봄. `continue-on-error` — 이 단계가 어떻게 실패해도 올리기는 돔 | 경고 · 요약에 "확인 필요" |
| TestFlight 에 올리기 | 요약에 `앱 알림(APNs · FCM): 켜짐 / 꺼짐 — 이유 · 프로파일 aps=…` | — |

- 엔타이틀먼트를 **늘** 붙이지 않는 이유: 푸시가 없는 프로파일로 서명하는 날
  "doesn't match the entitlements file's value for the aps-environment entitlement" 로 서명이 깨지고
  릴리스가 멈춥니다. 그래서 프로파일에 실제로 들어 있을 때만 붙입니다.
- **수동 서명**(맥에서 만든 `IOS_PROFILE_BASE64`)일 때는 App ID 를 건드리지 않습니다. 켜는 순간 그
  프로파일이 애플 쪽에서 무효가 되는데, CI 는 그 프로파일을 새로 만들 수 없기 때문입니다. 주인이
  developer.apple.com 에서 Push 를 켜고 프로파일을 다시 만들어 Secret 을 갈면 그다음 실행부터 켜집니다.
- `ios.yml`(서명 없는 컴파일 확인)은 바뀐 것이 없습니다 — plist 가 없는 길로 컴파일만 확인합니다.
- 비밀 값은 로그에 찍지 않습니다. 비밀을 다루는 단계는 `set +x` 로 시작하고, 풀어 낸 파일의 내용은
  출력하지 않으며, 설정 파일 안의 API 키는 `add-mask` 합니다. Secret 값 자체는 깃허브가 가립니다.

---

## 4. 설정이 없을 때 (지금처럼 돕니다)

| 어디 | 무슨 일 |
|---|---|
| 안드로이드 빌드 | `google-services.json` 이 없으니 플러그인이 안 켜지고 예전과 똑같이 빌드됩니다. |
| 아이폰 빌드 | 복사 단계가 할 일 없이 지나가고, 엔타이틀먼트도 안 붙습니다. `Info.plist` 의 `UIBackgroundModes: remote-notification` 은 무해합니다. |
| 앱 | `Firebase.initializeApp()` 이 실패하면 받아서 넘어가고, 독촉은 켤 때 · 돌아올 때 가져옵니다. 설정 화면은 「꺼짐 — 이 판은 앱 알림을 받지 못합니다」. |
| 서버 | 서비스 계정 파일이 없거나 틀리면 FCM 을 조용히 끄고, 뜰 때 한 줄만 찍습니다: `앱 알림(FCM) 꺼짐 — ~/.mybody/fcm-service-account.json 파일 없음`. 웹 푸시는 예전 그대로. 앱이 올리는 기기 토큰은 그래도 저장해 두어, 나중에 켜면 바로 씁니다. |

---

## 5. 처음 켜기

순서가 중요합니다. **폰은 비밀이 들어간 뒤에 만든 빌드를 깔아야** 알림을 받습니다.

1. **Firebase 준비(노트북, 주인은 로그인만)** — `docs/LOCAL-TASKS.md` 28절:
   프로젝트 「Mybody」(애널리틱스 끔) → 안드로이드 앱 · iOS 앱 등록(둘 다 `io.github.iacobuschoi.mybody`)
   → 설정 파일 두 개를 base64 로 GitHub Secrets 에 → 두 설정 파일의 API 키에 앱 제한 · API 제한 →
   FCM 보내기 전용 서비스 계정(`mybody-fcm-sender`)의 열쇠를 서버의 `~/.mybody/` 에(권한 600) →
   APNs 열쇠(.p8)를 만들어 Firebase 에 올림(팀 ID `JT4YLVNKDZ`) → 서버 재시작.
2. **서버 확인** — 뜰 때 로그에 `앱 알림(FCM) 켜짐 — 프로젝트 <프로젝트 ID>`.
3. **새 판 내기** — 안드로이드는 「친구들에게 줄 앱」(release.yml), 아이폰은 「아이폰 TestFlight」.
   두 요약에 `앱 알림 … 켜짐` 이 나와야 합니다.
4. **폰에서** — 새 판을 깔고 로그인 → 설정 → 「푸시 알림」 이 **켜짐**. 아이폰은 첫 로그인 뒤 알림
   허용을 한 번 묻습니다. 안드로이드는 예전부터 묻던 알림 권한 그대로입니다.
5. 예전 웹 앱을 쓰던 사람은 설정 → 「크롬(웹) 알림 끄기」 로 크롬 구독을 지워도 됩니다(안 지워도
   서버가 앱이 있는 동안은 크롬으로 안 보냅니다).

---

## 6. 확인하는 법

- **서버**: 뜰 때 찍는 `앱 알림(FCM) 켜짐/꺼짐` 한 줄. 열쇠가 실제로 되는지는 저장소 폴더에서
  `node -e "const f=require('./server/fcm.js');const s=f.load(process.env);console.log(f.describe(s));if(s.sender)s.sender.accessToken().then(()=>console.log('접근 토큰 받음'),e=>console.log('접근 토큰 실패: '+e.message))"`
  (토큰 값은 찍지 않습니다).
- **앱에서 서버에**: `GET /api/push/status` → `{fcm, web, devices, webSubs, webMuted}`. 설정 화면이 이걸 씁니다.
- **CI**: Actions 실행의 요약(Summary) 맨 아래 `앱 알림 …` 줄.
- **진짜 알림**: 친구 계정으로 독촉 → 받는 폰의 앱을 **완전히 닫은 채로** 알림이 오는지. 아이폰은
  TestFlight 판이어야 합니다(시뮬레이터와 Xcode 디버그 빌드는 APNs 환경이 다릅니다).

---

## 7. 문제 해결

| 증상 | 원인 | 할 일 |
|---|---|---|
| 요약에 `꺼짐 — FIREBASE_…_B64 없음` | Secret 이 없거나 이름이 틀림 | Settings → Secrets and variables → Actions 에서 이름을 정확히(`FIREBASE_ANDROID_JSON_B64` · `FIREBASE_IOS_PLIST_B64`) |
| `base64 로 싼 JSON(plist)이 아님` | 파일을 base64 하지 않고 붙였거나 잘림 | 28절의 명령으로 다시 만들어 넣기 |
| `다른 앱의 것` · `BUNDLE_ID 가 다름` | Firebase 에 앱을 다른 패키지/번들 ID 로 등록 | Firebase → 프로젝트 설정 → 일반 → 내 앱에서 `io.github.iacobuschoi.mybody` 로 다시 등록하고 새 파일로 교체 |
| 아이폰 `새로 만든 프로파일에 푸시 권한이 없음 (App ID 푸시 켜기: failed)` | ASC API 키에 Identifiers 권한이 없음 등 | developer.apple.com → Certificates, Identifiers & Profiles → Identifiers → `io.github.iacobuschoi.mybody` → Capabilities 에서 **Push Notifications** 체크 → Save. 다음 실행이 새 프로파일을 만듭니다 |
| 아이폰 `프로파일(IOS_PROFILE_BASE64)에 푸시 권한이 없음` | 수동 서명의 옛 프로파일 | 위처럼 Push 를 켜고 Profiles 에서 프로파일을 다시 만들어 `IOS_PROFILE_BASE64` 교체 |
| 아이폰 `ios-sign-project.js 가 엔타이틀먼트를 넣지 못함` | 서명 도구가 `--entitlements` 를 모르는 판 | 도구를 고친 코드로 다시 돌리기 |
| 서버 `꺼짐 — … 파일 없음` / `파일을 읽을 수 없음` | 경로가 틀림 · 서버를 도는 계정이 파일을 못 읽음 | 서버를 돌리는 사용자의 `~/.mybody/` 인지, 권한이 그 사용자에게 있는지 |
| 서버 `서비스 계정 파일이 아님` | `google-services.json` 을 잘못 놓음 | Google Cloud IAM 의 `mybody-fcm-sender` 서비스 계정 → 키 → 「새 키 만들기(JSON)」 로 받은 파일이어야 함(LOCAL-TASKS 28-6) |
| 서버 `⚠ 앱 알림(FCM): 서비스 계정 파일을 다른 사용자도 읽을 수 있습니다` | 맥 · 리눅스 기본 umask 로 644 가 됨 | `chmod 600 ~/.mybody/fcm-service-account.json` |
| 서버 `⚠ … 시험용 FCM 주소 사용 중` · `FCM_BASE_URL 를 무시합니다` | 시험 설정(`FCM_BASE_URL` · `FCM_TOKEN_URL`)이 운영 서버의 환경에 남음 | 그 환경변수를 지우고 서버 재시작. localhost · `NODE_ENV=test` 가 아니면 서버가 받지 않습니다 |
| 서버 `… 다른 프로젝트입니다 (403 SENDER_ID_MISMATCH)` | 서버의 서비스 계정과 앱에 든 설정 파일이 서로 다른 Firebase 프로젝트 것(프로젝트가 둘 생김) | 앱의 설정 파일과 **같은 프로젝트**에서 서비스 계정 키를 받아 같은 자리에 두고 재시작. 그동안 기기는 지우지 않고, 그 사람들은 크롬(웹)으로 받습니다 |
| 서버 `보내는 주소를 FCM 이 모릅니다 (404 …)` | 서비스 계정의 project_id 가 틀림 | 위와 같이 올바른 프로젝트의 키로 교체. 기기는 지우지 않습니다 |
| 앱 등록이 409 `다른 계정에 등록된 기기입니다` | 그 토큰이 다른 계정의 살아 있는 로그인에 묶여 있고 설치 비밀이 안 맞음 | 정상 동작(토큰만으로 남의 기기를 못 가져감). 같은 폰이면 앞 계정에서 로그아웃하거나, 앞 로그인이 만료되면 풀립니다 |
| 서버 `접근 토큰을 못 받았습니다 (invalid_grant)` | 열쇠가 폐기됐거나 컴퓨터 시계가 틀림 | 시계 동기화 → 그래도 안 되면 새 열쇠를 받아 같은 자리에 두고 서버 재시작 |
| 서버 `권한이 없습니다 (403 …)` | Firebase Cloud Messaging API(V1)가 꺼짐 · 다른 프로젝트의 서비스 계정 | Firebase → 프로젝트 설정 → 클라우드 메시징에서 API(V1) 「사용 설정됨」 확인, 열쇠가 같은 프로젝트 것인지 |
| 서버 `아이폰으로 못 보냈습니다 — … APNs 인증 키(.p8)를 올리세요` (`THIRD_PARTY_AUTH_ERROR`) | APNs 열쇠를 안 올렸거나 Key ID · 팀 ID 가 틀림 · 열쇠가 Sandbox 전용 | 클라우드 메시징 → Apple 앱 구성 → APNs 인증 키를 다시 올림(팀 ID `JT4YLVNKDZ`). TestFlight 은 Production 환경이라 열쇠는 「Sandbox & Production」 |
| 앱 설정 「꺼짐 — 이 판은 앱 알림을 받지 못합니다」 | 비밀을 넣기 전에 만든 빌드 | 새 판을 깔기 |
| 앱 설정 「꺼짐 — 폰 설정에서 Mybody 알림을 켜면…」 | 알림 권한 거절 | 폰 설정 → 앱 → Mybody → 알림 켜기. 그동안은 크롬 알림이 계속 갑니다 |
| 앱 설정 「서버 미지원」 | 서버가 옛 코드거나 서비스 계정이 없음 | `git pull` 뒤 서버 재시작, 뜰 때 한 줄 확인 |
| 아직도 크롬으로 옴 | 서버 FCM 이 꺼짐 · 그 폰이 30일 넘게 앱을 안 켬 · 알림 거절 · 앱 쪽이 우리 설정 문제로 전부 막힘 | 위 서버 줄들을 확인. 크롬이 필요 없으면 설정 → 「크롬(웹) 알림 끄기」 |
| 안드로이드 알림이 「기타」 채널 · 흰 네모 아이콘 | 채널 · 아이콘이 들어가기 전의 앱 | 새 판을 깔기(채널 'friends' 는 앱이 켜질 때 미리 만듭니다) |
| 아이폰에서 앱을 쓰는 중에 끼니 알림까지 안 뜸 | AppDelegate 의 willPresent 덮어쓰기가 빠짐 | `app/ios/Runner/AppDelegate.swift` 확인 |
| App Store Connect 에서 ITMS-90078(Missing Push Notification Entitlement) 메일 | 알림이 꺼진 판(엔타이틀먼트 없음)을 올림 | 경고일 뿐 올리기 · 심사는 막지 않습니다. 켜진 판부터는 안 옵니다 |

### 열쇠가 샜을 때 (저장소 · 채팅 · 스크린숏에 올라갔을 때)

공개 저장소에 한 번 올라간 것은 커밋을 지워도 **새었다고 봅니다.** 바로 폐기하고 새로 만듭니다.

- 서비스 계정: Google Cloud 콘솔 → IAM 및 관리자 → 서비스 계정 → `mybody-fcm-sender@…` → 키 → 「키 추가」 로
  새 열쇠를 받고, 새 열쇠의 ID 를 확인한 뒤 옛 키 삭제 → 새 열쇠를 서버에 두고(`chmod 600`) 재시작.
  예전 안내대로 `firebase-adminsdk-…` 의 키를 받아 두었다면 그 키도 삭제합니다(프로젝트 전체 관리자 권한).
- APNs 열쇠: developer.apple.com → Keys → 그 열쇠 → Revoke → 새로 만들어 Firebase 에 다시 올림.
- 앱 설정 파일(API 키): 이 키는 앱 안에 들어가 **처음부터 공개**라 "샜을 때" 가 따로 없습니다. 막는 것은
  키 제한입니다 — LOCAL-TASKS 28 의 5-1(안드로이드 패키지 + 서명 SHA-1 · iOS 번들 ID · 허용 API 두 개)이
  걸려 있는지 확인합니다. 제한 없이 남이 쓴 흔적이 있으면 키를 다시 만들고 새 설정 파일로 Secret 을 갈고 새 판을 냅니다.

---

## 8. 코드 위치

| 무엇 | 파일 |
|---|---|
| 앱: Firebase 초기화 · 토큰 등록 · 누르면 이동 · 앞에 있을 때 | `app/lib/src/native_push.dart` |
| 앱: 설정 화면 「푸시 알림」 · 「크롬(웹) 알림 끄기」 | `app/lib/src/screens/settings.dart` |
| 안드로이드: 조건부 플러그인 · 채널 · 아이콘 | `app/android/app/build.gradle.kts` · `AndroidManifest.xml` · `res/drawable/ic_stat_mybody.xml` |
| 아이폰: 앞에 있을 때 보이기 · 백그라운드 모드 · 권한 · plist 복사 단계 | `AppDelegate.swift` · `Info.plist` · `Runner.entitlements` · `Runner.xcodeproj/project.pbxproj` |
| 서버: FCM 보내기 · 기기 표 · 엔드포인트 | `server/fcm.js` · `server/db.js`(`push_devices`) · `server/server.js`(`/api/push/*`, `pushToUser`) |
| CI | `.github/workflows/apk.yml` · `release.yml` · `ios-release.yml` |
| 시험 | `tools/test-fcm.js`(배포 전 점검 `preflight.js` 의 BLOCK) · `tools/test-android.js`(플러그인 조건 · 채널 · 아이콘 · 자동 초기화 · 설정 파일이 저장소에 없는지) · `tools/test-asc.js`(서명 도구의 `--entitlements`) · `tools/test-push.js` · `tools/test-friendpush.js` · `app/test/native_push_test.dart` |
