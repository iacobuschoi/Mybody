# Mybody 서버 (자가호스팅)

내 컴퓨터에서 돌리는 서버입니다. **설치할 게 없습니다** — Node 만 있으면 됩니다.
데이터베이스는 Node 내장 SQLite 를 씁니다.

> **처음이면 [../docs/START.md](../docs/START.md) 를 보세요.**
> 거기가 "받아서 폰으로 쓰기" 까지 10분짜리 길입니다.
>
> ```bash
> node tools/serve.js --setup     # 한 번만
> node tools/serve.js
> ```
>
> 이 문서는 환경변수를 직접 다룰 때, 그리고 서버가 무엇을 어떻게 하는지
> 알아야 할 때 봅니다.

## 직접 띄우기

```bash
PAIR_SECRET=<가입 코드> node server/server.js
```

`PAIR_SECRET` 은 **이 서버에 계정을 만들 수 있는 사람을 정하는 값**입니다.
이 값을 알려준 사람만 가입할 수 있습니다. 없으면 서버가 시작하지 않습니다 —
아무나 로그인할 수 있는 서버가 되기 때문입니다.

값은 `node tools/serve.js --setup` 이 한 번 만들어 주고
`~/.mybody/config.json` 에 넣어 둡니다. 지금 값은 이렇게 봅니다:

```bash
node tools/serve.js --show
```

가입한 뒤에는 **비밀번호만으로** 들어옵니다. 로그인할 때마다 이 값을
요구하면 그게 사실상 공용 비밀번호가 되어, 한 사람만 새도 전원이 뚫립니다.

```
Mybody 서버 실행 중
  주소   http://localhost:8080
  폰에서 http://192.168.0.5:8080   (같은 와이파이)
  DB     server/mybody.db
  정적   release
```

브라우저에서 <http://localhost:8080> 을 열면 앱이 그대로 뜹니다.

> `STATIC` 을 안 주면 **개발 빌드**(`prototype/`)가 나갑니다 — 화면에 번호
> 배지가 전부 뜨고 개발용 버튼이 살아 있습니다. 서버가 시작할 때 그렇다고
> 말해 줍니다. 남에게 줄 주소라면 `STATIC=./release` 를 주세요.

### 데이터는 어디에

`server/mybody.db` 에 들어갑니다. 저장소 폴더 안이지만 git 은 안 봅니다
(`.gitignore`). 다만 **저장소를 다시 clone 하면 계정도 같이 사라집니다** —
옮길 생각이면 이 파일부터 챙기세요.

서버가 켜져 있는 동안에는 새 기록이 `mybody.db-wal` 이라는 곁파일에 쌓입니다.
그래서 `cp mybody.db` 로는 백업이 안 됩니다. `node tools/backup.js` 를 쓰세요
— 자세한 것은 [../docs/START.md](../docs/START.md) 의 백업 절.

### 설정

| 환경변수 | 기본값 | 설명 |
|---|---|---|
| `PORT` | `8080` | 포트 |
| `DB` | `server/mybody.db` | DB 파일 경로 |
| `STATIC` | `../prototype` | 정적 파일 폴더 |
| `ORIGIN` | `*` | CORS 허용 출처. 인터넷에 열 때는 실제 도메인으로 좁히세요 |
| `TRUST_PROXY` | (꺼짐) | `1` 로 켜면 `x-forwarded-for` 를 믿습니다. **터널이나 리버스 프록시 뒤에서만** 켜세요 — 직접 노출된 서버에서 켜면 아무나 헤더 한 줄로 속도 제한을 피합니다 |
| `LOG` | `1` | `/api` 요청을 한 줄씩 찍습니다 (시각·메서드·경로·상태·시간). 본문·토큰·사진·몸에 대한 숫자는 안 남깁니다. `0` 으로 끕니다 |
| `RATE_MAX` | `300` | `/api` 분당 허용 요청 수 (IP당). 정적 파일은 안 셉니다 |
| `AUTH_MAX` | `20` | 로그인·가입 분당 허용 횟수 (IP당). 비밀번호 확인은 scrypt 라 비싸서 따로 더 빡빡하게 막습니다 |
| `BODY_TIMEOUT_MS` | `30000` | 본문을 다 받기까지 기다리는 시간. 넘으면 끊습니다 |
| `PAIR_SECRET` | (없으면 시작 안 함) | 가입 코드. 이걸 아는 사람만 계정을 만들 수 있습니다 |
| `ANTHROPIC_API_KEY` | (없음) | 결과지 자동 판독용 키. **없으면 자동 판독만 꺼집니다** — 앱은 그대로 돕니다 |
| `OCR_MODEL` | `claude-sonnet-5` | 판독에 쓸 모델. `tools/ocr-compare.js` 로 자기 결과지에 재 보고 정하세요 |
| `OCR_PER_DAY` | `10` | **사람당** 하루 판독 횟수 |
| `OCR_PER_DAY_TOTAL` | `250` | **서버 전체** 하루 판독 횟수. 가입 코드가 새면 계정을 늘려 사람당 한도를 피할 수 있어서, 청구서는 이걸로 막습니다 |
| `OCR_API_URL` | 앤트로픽 API | 사내 프록시를 거쳐야 할 때만 바꾸세요 |
| `FCM_SERVICE_ACCOUNT` | `~/.mybody/fcm-service-account.json` | 앱 알림(FCM) 서비스 계정 JSON 의 **경로**. 설정 파일의 `fcmServiceAccount` 로도 됩니다. **파일이 없으면 앱 알림만 꺼지고** 나머지는 그대로 돕니다 — 아래 "앱 알림 켜기" |
| `FEEDBACK_NOTIFY` | (없음) | 앱 안 「의견 보내기」 로 새 의견이 오면 알림을 받을 계정의 **아이디**. 설정 파일의 `feedbackNotify` 로도 됩니다. 비워 두면 알림 없이 쌓이기만 합니다 — 아래 "의견 보내기" |
| `FEEDBACK_PER_DAY` | `20` | 의견을 하루에 받는 개수 — 로그인했으면 **사람마다**, 아니면 **보낸 주소(IP)마다** |
| `FEEDBACK_PER_DAY_TOTAL` | `300` | **서버 전체** 하루 의견 개수. 로그인 없이도 받는 길이라 디스크를 채우는 남용을 막는 울타리입니다 |
| `FEEDBACK_NOTIFY_GAP_MS` | `600000` | 주인 알림 사이 최소 간격(10분). 시험이 줄여 쓰는 값이라 운영에서는 그대로 두세요 |
| `FCM_BASE_URL` · `FCM_TOKEN_URL` | 구글 주소 | 시험(`tools/test-fcm.js`)이 가짜 서버로 바꿀 때만 씁니다. `https` 이면서 localhost(127.0.0.1)이거나 `NODE_ENV=test` 일 때만 받고, 받으면 뜰 때 "시험용 FCM 주소 사용 중" 을 찍습니다. 운영 서버에 새면 진짜 접근 토큰과 알림 본문이 그 주소로 가기 때문입니다 |

```bash
PORT=3000 DB=~/mybody.db ORIGIN=https://mybody.example.com node server/server.js
```

### 앱 알림 켜기 (FCM — 안드로이드 · 아이폰 앱)

친구의 운동 독촉 · 친구 요청 · 운동 소식은 원래 **웹 푸시(크롬)** 로만 나갔습니다.
그래서 앱을 깔아 쓰는 사람도 알림은 크롬에서 받았습니다. 서비스 계정 파일을
놓으면 서버가 앱으로 직접 보냅니다(안드로이드는 FCM, 아이폰은 FCM 이 APNs 로).

1. **FCM 보내기만 하는 서비스 계정**을 만들어 그 키를 받습니다. Firebase 콘솔의
   "서비스 계정 → Firebase Admin SDK → 새 비공개 키" 는 쓰지 마세요 — 그 계정은 프로젝트
   전체의 Firebase 관리자 권한이라, 이 컴퓨터에서 새면 알림을 넘어 프로젝트가 통째로 넘어갑니다.
   [Google Cloud 콘솔](https://console.cloud.google.com/iam-admin/serviceaccounts) → 이 앱의
   프로젝트 → "서비스 계정 만들기" → 이름 `mybody-fcm-sender` → 역할
   **"Firebase Cloud Messaging API 관리자"**(`roles/firebasecloudmessaging.admin`) 하나만 →
   완료 → 그 계정 → 키 → "키 추가 → 새 키 만들기 → JSON". (자세한 길: `docs/LOCAL-TASKS.md` 28-6)
2. 그 파일을 서버 컴퓨터의 `~/.mybody/fcm-service-account.json` 으로 옮깁니다
   (윈도우는 `%USERPROFILE%\.mybody\fcm-service-account.json`). 맥 · 리눅스는
   `chmod 600` 으로 남이 못 읽게 해 두세요 — 남도 읽을 수 있으면 서버가 뜰 때 경고를
   한 줄 찍습니다. **저장소 안에는 절대 두지 마세요** —
   공개 저장소이고, 이 파일이 있으면 누구나 우리 앱 사용자에게 알림을 쏠 수 있습니다
   (`.gitignore` 가 이름으로 막고 있지만 다른 이름으로 두면 못 막습니다).
3. 아이폰까지 보내려면 같은 프로젝트 설정 → **클라우드 메시징** → Apple 앱 구성에
   APNs 인증 키(`.p8`)를 올립니다. 안 올리면 안드로이드만 가고, 서버가 뜬 뒤 첫
   아이폰 알림 때 "APNs 인증 키를 올리세요" 를 한 번 찍습니다.
4. **서버를 다시 띄웁니다.** 파일은 뜰 때 한 번 읽습니다. 뜰 때 한 줄로 말합니다:
   `앱 알림(FCM) 켜짐 — 프로젝트 <id>` 또는 `꺼짐 — <경로> 파일 없음`.

어디로 가는가

- 로그인한 앱이 켜질 때마다 자기 토큰을 올립니다(`POST /api/push/device`). 그 토큰은 **그
  로그인에 묶여** 로그아웃 · 모든 기기 로그아웃 · 비밀번호 변경 · 탈퇴 · 만료 때 같이 지워집니다.
  만료된 로그인은 서버가 뜰 때와 하루 한 번 지웁니다.
- **FCM 으로는 일반 문구만 갑니다.** 웹 푸시는 암호화되지만 FCM 의 알림 본문은 평문이라 구글 ·
  애플이 읽습니다. 그래서 친구 이름 · "이번 주 N일째" · 공유 기본값은 웹 푸시에만 싣고, 앱 알림은
  "친구가 운동하라고 콕 찔렀어요" 처럼 무슨 일인지만 적습니다. 알림 칸을 모으는 tag 에도 사용자
  id 를 쓰지 않습니다(독촉 번호 · 받는 사람별 HMAC). 알림을 거절한 기기로는 보내지 않습니다.
- 최근 30일 안에 앱이 토큰을 올린 사람에게는 **크롬(웹 푸시)을 보내지 않습니다** —
  같은 독촉이 두 번 울리고, 하필 크롬이 먼저 울렸습니다. 앱 알림을 거절한 폰은 "앱이
  있다" 로 치지 않습니다. 서비스 계정 열쇠가 폐기되는 등 **서버 쪽 문제로 앱에 한 건도
  못 보냈으면** 크롬은 막지 않습니다.
- 앱은 등록이 되면(FCM 이 켜진 서버 · 알림을 허락한 폰) 그 계정의 크롬 구독을 **계정마다 한 번
  저절로** 지웁니다(`DELETE /api/push/web`). 예전 웹 앱이 남긴 구독 때문에 크롬이 울리던 것을
  사람이 설정에서 찾아 끄지 않아도 되게 — 설정의 「크롬(웹) 알림 끄기」 는 없어졌습니다.
- 받는 사람은 웹 푸시와 **같은 규칙**으로 고릅니다. 일정 공유를 끈 친구에게는 운동
  소식이 앱으로도 안 갑니다. 알림이 공유 설정을 우회하는 뒷문이 되면 안 됩니다.
- 앱이 없어진 기기(UNREGISTERED)는 FCM 이 알려 주는 대로 지우고, 잠깐 실패(429 · 5xx)는
  지우지 않고 셉니다. 로그에는 토큰의 앞 8자만 남습니다.

### 의견 보내기 (앱 안 → 운영자의 「의견함」 · 노트북)

시험판을 쓰는 사람이 앱 안에서 화면 캡처(최대 3장)와 글(없어도 됨)을 바로 보냅니다
(`POST /api/feedback`). **로그인 없이도 받습니다** — 로그인했으면 그 계정에 묶이고, 토큰이
없거나 틀리면 익명입니다(401 을 주지 않습니다).

보기 — 폰에서: 운영자(아래 `feedbackNotify` 에 적은 아이디의 계정)로 로그인한 앱의 **설정 → 「의견함」**.
새것부터 글 · 붙인 화면 · 앱 판 · 기종 · 화면 · 받은 시각 · 보낸 사람(로그인해서 보냈으면 표시 이름, 아니면
「익명」)이 나오고, 누르면 글 전체와 화면을 크게 봅니다. 열면 읽음이 되고, 지울 수 있습니다. 새 의견 알림을
누르면 바로 여기로 옵니다. 다른 계정의 앱에는 이 칸이 없고, 길을 직접 두드려도 403 입니다.

보기 — 컴퓨터 브라우저에서: **`<서버>/inbox`** 를 열고 운영자 계정으로 로그인합니다. 넓은 화면에 목록과 자세히가
나란히 서고, 앱과 같은 길(아래)을 씁니다 — 아래 "컴퓨터로 보는 의견함 (`/inbox`)".

```
GET    /api/feedback/inbox?limit=30&before=<번호>   {ok, unread, items:[…], nextBefore}  새것부터 · limit 1~50
GET    /api/feedback/inbox/<번호>/image/<n>         사진 바이트(image/png · image/jpeg) · 없으면 404
POST   /api/feedback/inbox/<번호>/read              읽음 표시
POST   /api/feedback/inbox/read-all                 안 읽은 것 전부 ({"upTo": <번호>} 를 주면 거기까지만)
DELETE /api/feedback/inbox/<번호>                   의견과 사진을 함께 지움
```

전부 로그인이 필요하고(없으면 401), **운영자가 아니면 어느 길이든 403** 입니다 — 운영자인지는 요청마다
서버가 설정의 아이디로 다시 찾습니다(로그인과 같이 대소문자 무시). `GET /api/me` 의 `user.isOperator` 는
운영자 본인에게만 `true` 로 붙고, 다른 사람의 응답에는 칸 자체가 없습니다. 응답은 전부
`Cache-Control: private, no-store` 입니다. `feedbackNotify` 가 비어 있으면 아무도 운영자가 아닙니다.

같은 운영자의 설정에는 **「가입자 목록」** 도 섭니다(`GET /api/operator/users`, 아래 API 표) — 아이디 ·
표시 이름 · 가입일, 새 가입부터. 줄을 누르면 아이디가 복사되어 노트북의 `node tools/reset-password.js <아이디>`
에 바로 붙여 넣습니다. 규칙(401 · 403 · 캐시 금지)은 의견함과 같습니다.

> **운영자 계정을 지웠다면 `feedbackNotify` 도 지우거나 바꾸세요.** 아이디로 찾기 때문에, 같은 아이디로
> 새로 가입한 사람이 의견함(과 「가입자 목록」)을 봅니다. 그 계정이 아직 없으면 서버가 뜰 때 `⚠ 의견함: …` 으로 알립니다 —
> 누구나 가입할 수 있는 서버(`openSignup`)면 아무나, 아니어도 가입 코드를 받은 사람이면 그 아이디를 먼저
> 가져갑니다. 그 계정의 비밀번호는 다른 곳과 다르게 두세요 — 새면 모든 의견과 화면 캡처가 같이 샙니다.

보기 — 서버 컴퓨터에서:

```bash
node tools/feedback.js                    # 안 읽은 의견, 새것부터 + 붙인 화면을 파일로 꺼냄
node tools/feedback.js --mark-read        # 방금 본 것을 읽음으로
node tools/feedback.js --all              # 읽은 것까지
node tools/feedback.js --since=2026-09-20 # 그날(한국 시각)부터, 읽은 것도 같이
node tools/feedback.js --no-export        # 화면을 파일로 꺼내지 않음
```

한 줄에 번호 · 받은 시각(KST) · 앱 판 · 기종 · 화면 · 보낸 사람 · 사진 수가 나오고, 그 아래에
글이 **전부** 나옵니다. 화면 캡처는 `~/.mybody/feedback/<번호>-<n>.png|jpg` 로 꺼냅니다(폴더 700 ·
파일 600 — 몸 숫자가 찍혀 있을 수 있습니다). 보낸 사람은 **아이디 대신 가명 6자**
(sha256(내부 id) 앞 6자)로만 나옵니다 — 같은 사람끼리는 묶어 볼 수 있고, 출력을 화면 공유하거나
이슈에 붙여도 누구인지 드러나지 않습니다. 로그인 없이 보낸 것은 「익명」. DB 는 서버와 같은 규칙으로
찾습니다(환경변수 `DB` → 설정의 `db` → `server/mybody.db`). 읽음 표시는 의견함과 같은 칸을 씁니다.

알림 — `~/.mybody/config.json` 에 `"feedbackNotify": "<내 아이디>"` 를 적고(또는 `FEEDBACK_NOTIFY`)
서버를 다시 띄우면, 새 의견이 올 때 그 계정의 폰으로 「새 의견이 왔어요 · 눌러서 보기」
한 줄이 **10분에 한 번까지** 갑니다. 누르면 앱이 「의견함」을 엽니다(`route: 'feedback'`). 의견 내용 ·
보낸 사람은 싣지 않습니다(FCM 본문은 구글 · 애플이 읽는 평문입니다) — 내용은 의견함이 로그인한 채로
서버에서 가져옵니다. 뜰 때 `의견 알림 켜짐` 또는 `⚠ … 계정이 없습니다` 를, 계정이 있으면 `의견함 켜짐` 을
한 줄씩 찍습니다(아이디는 안 찍습니다).

막는 것
- 글 2000자, 사진 3장 · 한 장 1.5MB(풀어 낸 크기). base64 는 엄격하게 풀고, 앞머리 바이트가
  말한 형식과 맞아야 합니다(PNG `89 50 4E 47` · JPEG `FF D8 FF`). 이 길만 본문 상한이 6.2MB 입니다.
- 하루 20개(사람마다 · 로그인 없으면 주소마다) + 서버 전체 300개. 거절된 요청은 세지 않습니다.
  본문을 받기 전에 한 번, 저장 직전에 한 번 더 셉니다 — 동시에 여러 개를 열어도 한도를 못 넘습니다.
  Cloudflare Tunnel 뒤에서 `TRUST_PROXY` 를 안 켰으면 익명은 전부 한 주소로 보여 20개를 나눠 씁니다.
- 동시에 본문을 받는 의견은 서버 전체 6개 · 한 사람(주소) 2개까지이고, 넘치면 503 「잠시 뒤에 다시」
  입니다(한 건이 받는 동안 6MB 넘게 메모리를 쥡니다). 본문을 기다리는 시간은 다른 길의 세 배
  (`BODY_TIMEOUT_MS` × 3, 기본 90초) — 올리기가 느린 폰의 캡처 세 장이 중간에 끊기지 않게.
- 제어 문자(ESC 등)는 저장할 때 빼고, 도구가 찍을 때도 한 번 더 뺍니다 — 로그인 없이 보낸 글이
  주인의 터미널에 찍히기 때문입니다.

지우는 것 — 계정을 지우면 그 계정의 의견과 화면이 같이 지워지고, **받은 지 1년**이 지난 것은 서버가
뜰 때와 하루 한 번 지웁니다(처리방침과 같은 숫자 — `server/feedback.js` 의 `KEEP_DAYS`). 운영자가
의견함에서 지우면 그때 바로 지워집니다(사진까지 한 번에). 보낸 곳의 주소(IP)는 저장하지 않습니다
(하루 개수는 메모리에서만 셉니다). 노트북에 꺼내 둔 캡처도 같은 규칙입니다 —
`tools/feedback.js` 는 돌릴 때마다 DB 에서 지워진 의견의 `~/.mybody/feedback/<번호>-<n>.*` 를 지웁니다
(의견 번호는 다시 쓰이지 않습니다).

## 계정

카카오·애플 같은 외부 로그인을 쓰지 않습니다. 이 서버가 직접 관리합니다.
외부 OAuth 는 사업자 등록과 앱 심사가 필요하고, 자가호스팅이라는 전제와도
맞지 않습니다.

- **아이디** 는 이메일이 아니라 영문·숫자 3~32자입니다. 이메일을 받으면
  보관해야 하는 개인정보가 하나 늘어나는데, 이 서버는 메일을 보내지 않으므로
  이메일이 할 일이 없습니다.
- **비밀번호** 는 scrypt 해시로만 저장됩니다. 원문은 어디에도 남지 않습니다.
- **건강정보 별도 동의** 가 있어야 계정이 만들어집니다. 로그인하면 친구가
  하나도 없어도 주간 요약(체중·골격근량·체지방량·체지방률)이 서버에
  저장되므로, 가입이 곧 업로드 동의가 됩니다. 그래서 계정 동의와 섞지 않고
  따로 받습니다 — `signUp` 은 `healthConsent` 가 받아 주는 판(`ACCEPTED_CONSENT_VERSIONS`:
  현재 판 `HEALTH_CONSENT_VERSION` 과, 이미 깔린 앱이 보내는 옛 판)일 때만 통과하고,
  **받은 판을 그대로** 적습니다. 동의 시각과 판은 `users.consent_health_at` ·
  `consent_version` 에 남고, 본인은 `/api/me` 에서 볼 수 있습니다(`healthConsentCurrent` 가
  서버의 현재 판). 앱은 켤 때 둘이 다르면 새 문구를 보여 주고 `POST /api/me/consent` 로 다시 받습니다.
  문구를 고치면 판을 올리세요 — 옛 판으로 동의한 사람에게 다시 물어야 합니다.
- 로그인 실패는 아이디별로 15분에 8번까지입니다. 무차별 대입을 막습니다.
- 세션은 90일 뒤 만료됩니다. 비밀번호를 바꾸면 다른 기기가 전부 로그아웃됩니다 —
  토큰이 샜을 때의 복구 수단입니다.

### 비밀번호를 잊었을 때 — 복구 코드

메일을 보내지 않으므로 "재설정 링크" 가 없습니다. 대신 **가입할 때 복구 코드를
한 번** 보여주고, 서버에는 scrypt 해시만 남깁니다. DB 를 통째로 가져가도 코드는
되돌릴 수 없고, 우리도 다시 꺼내 줄 수 없습니다.

```
XXXX-XXXX-XXXX-XXXX     0/O · 1/I/L 을 뺀 31글자 × 16자리 ≈ 79비트
```

- 잊었으면 `POST /api/auth/recover` 에 `{handle, code, password}` 를 보냅니다.
  성공하면 **다른 기기의 세션이 전부 끊기고**, 새 코드가 한 번 나옵니다.
  계정을 되찾는 상황이라면 남이 들어와 있을 수 있어서입니다.
- **한 번 쓰면 끝입니다.** 쓴 코드는 그 자리에서 새것으로 바뀝니다 —
  메모장에 남아 있어도 그때부터 쓸모가 없습니다.
- 코드를 잃어버렸으면 로그인한 상태에서 `POST /api/auth/recovery-code` 로
  새로 받습니다 (비밀번호를 다시 확인합니다). 앱에서는 **계정 → 복구 코드
  새로 받기**.
- 찍어 보는 시도는 로그인과 같은 잠금을 씁니다 — 아이디별로 15분에 8번.
  없는 아이디와 틀린 코드는 같은 문장으로 거부하고, 없는 아이디여도 해시를
  한 번 돌립니다. 응답 시간으로 계정 존재 여부를 알 수 없게 하기 위해서입니다.
- **비밀번호와 코드를 둘 다 잃으면** 그때는 정말 길이 없습니다. 서버 주인이
  DB 에서 계정을 지우고 다시 만들어야 하고, 친구 관계와 주간 기록이 같이
  사라집니다.

## 밖에서 접속하기 (친구 기능)

집 컴퓨터는 보통 공유기 뒤에 있어서 밖에서 바로 못 들어옵니다.
**포트포워딩 없이** 공개 주소를 얻는 방법 두 가지:

> **먼저 읽어주세요.** 아래 둘 다 집 안 서버를 인터넷에 여는 방법입니다.
> 열기 전에 `PAIR_SECRET` 이 추측하기 어려운 값인지, 비밀번호가 충분히 긴지
> 확인하세요. 한 번 열면 전 세계가 로그인 화면을 두드릴 수 있습니다.

### 1. Cloudflare Tunnel (친구가 아무 기기에서나 접속)

```bash
# 설치: https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/
cloudflared tunnel --url http://localhost:8080
```

`https://xxxx-yyyy.trycloudflare.com` 주소가 나옵니다. HTTPS도 같이 됩니다.
고정 주소가 필요하면 Cloudflare 계정을 연결해 이름 있는 터널을 만드세요.

### 2. Tailscale (더 사적, 친구도 Tailscale 설치 필요)

```bash
tailscale serve https / http://localhost:8080
```

공개 인터넷에 노출되지 않고 내 tailnet 안에서만 보입니다.
친구를 tailnet에 초대해야 접속할 수 있어서, 아무나 들어올 수 없습니다.

**어느 쪽이든 컴퓨터가 꺼져 있으면 친구도 못 봅니다.** 상시 접속이 필요하면
라즈베리파이나 미니PC를 켜두거나, 클라우드로 옮기는 편이 낫습니다.

## 백업

DB 파일 하나만 복사하면 끝입니다. WAL 모드라 실행 중에도 아래 방법이 안전합니다.

```bash
sqlite3 server/mybody.db ".backup server/backup-$(date +%F).db"
# sqlite3 가 없으면 서버를 잠깐 끄고 그냥 복사해도 됩니다
cp server/mybody.db ~/backup/mybody-$(date +%F).db
```

## 보안

- 권한 검사는 **전부 서버에서** 합니다. 클라이언트가 보내는 "나는 누구다"를 믿지 않고
  토큰으로만 판단합니다.
- 친구가 아닌 사람은 남의 스냅샷을 못 읽습니다. 친구여도 **상대가 켜 둔 항목만** 나갑니다.
- 요청 속도 제한이 걸려 있습니다 (IP당 분당 300회).
- 인터넷에 열 때는 `ORIGIN`을 실제 도메인으로 좁히세요.
- 사진은 기본적으로 **기기 밖으로 나가지 않습니다.** 사용자가 설정에서 자동 판독을
  켜고 판독 버튼을 누를 때만 이 서버로 올라갑니다. 키가 없으면 그 경로 자체가 없습니다.
  예외는 사용자가 「의견 보내기」 로 **직접 붙여 보낸 화면 캡처**뿐이고, 그건 이 서버의 DB 에
  1년 동안 남습니다(위 "의견 보내기").

## API

전부 `/api` 아래이고, 로그인 · `/api/health` · `/api/version` · `/api/feedback` 외에는
`Authorization: Bearer <token>` 이 필요합니다. `/api` 밖에는 친구 초대 링크 페이지(`GET /i/<코드>`)와
그 링크를 폰이 앱으로 바로 열게 하는 앱 링크 파일 둘(`GET /.well-known/assetlinks.json` ·
`GET /.well-known/apple-app-site-association`), 컴퓨터 브라우저로 보는 의견함 페이지(`GET /inbox`)가 있습니다 —
아래 "친구 초대 링크" · "앱 링크 파일" · "컴퓨터로 보는 의견함".
0.2.20 부터 앱은 모든 요청에 `X-Mybody-App: <판>` 머리를 붙입니다(기록 칸의 주인을 아는 판). 서버는
지금은 막지 않고 거절 로그에만 적습니다 — 고친 판이 퍼지면 owner 없는 기록 사본을 거절하도록 켤 수 있게.

| 메서드 | 경로 | 설명 |
|---|---|---|
| `GET` | `/api/health` | 살아 있는지 (로그인 불필요) |
| `GET` | `/api/version` | `{latest:{appstore,testflight,play,apk}, min, urls:{…}, join:{ios?, android?, androidGroup?}, testing}` 앱 안 업데이트 안내용. 빈 값이면 안내 없음. `latest` 는 그 길로 깐 사람이 지금 받을 수 있는 판 — `testflight` 는 friends(공개 링크) 베타 심사 승인판, `play` 는 비공개(나중엔 프로덕션) 트랙 게시판(내부 테스트 판은 안 적음). `join` 은 시험판 참여 링크(TestFlight 공개 링크 · 플레이 비공개 테스트 · 그 테스트의 구글 그룹) — **적힌 https 만** 나가고 비었으면 `{}`. `testing` 은 비공개 시험 기간인가(참/거짓) — **안 적었으면 `true`**, 분명히 끈 것(`--testing=off`)만 `false`. `tools/app-version.js`(`--join-ios` · `--join-android` · `--join-android-group` · `--testing=on\|off`)로 고치고, 부를 때마다 설정을 새로 읽습니다. 설정 파일이 망가졌으면 빈 값 대신 503 (로그인 불필요) |
| `POST` | `/api/feedback` | `{text?, images?:[{type:'image/png'\|'image/jpeg', data:<base64>}], appVersion?, platform?:'android'\|'ios', screen?}` 앱 안 의견 보내기 → `{ok, id}`. 글(≤2000자)이나 사진(≤3장, 한 장 ≤1.5MB) 중 하나는 있어야 함. 로그인 선택 — 유효한 토큰이면 그 계정에 묶고, 없거나 틀리면 익명(401 없음). 틀리면 400 `{ok:false, error}`, 본문 6.2MB 초과 413, 하루 20개(사람 · 주소마다)를 넘으면 429, 동시에 받는 것이 넘치면 503 |
| `POST` | `/api/auth/signup` | `{handle, password, displayName, pairSecret, healthConsent}` → `{token, user, recoveryCode}` (로그인 불필요) |
| `POST` | `/api/auth/signin` | `{handle, password}` → `{token, user}` (로그인 불필요) |
| `POST` | `/api/auth/signout` | 이 토큰만 폐기 |
| `POST` | `/api/auth/signout-all` | 모든 기기 로그아웃 |
| `POST` | `/api/auth/password` | `{current, next}` 비밀번호 변경 (다른 기기 전부 로그아웃) |
| `POST` | `/api/auth/recover` | `{handle, code, password}` 복구 코드로 비밀번호 재설정 → `{token, user, recoveryCode}` (로그인 불필요) |
| `POST` | `/api/auth/recovery-code` | `{password}` 복구 코드 재발급 → `{recoveryCode}` |
| `GET` | `/api/me` | 내 정보 + 기록 수 |
| `PATCH` | `/api/me` | `{displayName}` |
| `DELETE` | `/api/me` | 계정 삭제 (친구·공유·스냅샷·기록 · 보낸 의견과 화면 연쇄 삭제) |
| `POST` | `/api/me/consent` | `{healthConsent}` 현재 판으로 건강정보 동의를 다시 받음 → `{user}` |
| `GET` | `/api/operator/users` | **운영자만**(아니면 403 `{ok:false, error:'운영자만 볼 수 있어요'}`) 앱 설정의 「가입자 목록」 → `{total, users:[{handle, displayName, createdAt, me?}]}`. 새 가입부터 · `?limit=` 1~1000(기본 1000) · `total` 은 전체 수 · `me:true` 는 운영자 본인 줄에만. 아이디 · 표시 이름 · 가입 시각 말고는 싣지 않음(비밀번호 · 복구 코드 · 토큰 · 초대 코드 · 내부 id 없음). `Cache-Control: private, no-store` |
| `GET` | `/api/friends` | 친구 · 받은 요청 · 보낸 요청 · 차단 |
| `POST` | `/api/friends/request` | `{inviteCode, via?}` → 보통은 `{status:'pending', otherId}`(코드 주인이 수락해야 친구). 상대가 먼저 나에게 요청해 둔 사이면 그 자리에서 `{status:'accepted'}`. **`via:'link'`**(앱이 초대 링크 · 설치 추천인으로 받은 코드 — 손으로 친 코드 · 클립보드는 안 붙임)이면 요청 없이 **곧바로 친구** — 코드 주인이 수락을 누른 것과 같은 길이라 각 방향 기본 공유가 복사되는 것까지 같음. 내가 이미 보낸 요청이 있어도 · 상대가 보낸 요청이 있어도 수락되고, 이미 친구면 아무것도 안 바꾸고 `{status:'accepted', already:true}`(알림 없음). 코드 주인에게는 수락 알림(웹 푸시 「○○님과 친구가 됐어요」, 앱 알림은 일반 문구 「친구 요청이 수락됐어요」). 친구가 됐을 때(`accepted`)만 상대의 표시 이름을 `friend:{name}` 으로 실음 — 요청 · 실패에는 없음(코드 → 이름 사전이 되지 않게). 내 코드 · 없는 코드 · 차단은 `via` 와 상관없이 거절. 코드 주인이 나를 **거절 · 친구 끊기 · 차단(풀었어도)** 한 적이 있으면 `via:'link'` 여도 예전처럼 요청(`pending`, 코드 주인이 다시 고름 — 코드는 바뀌지 않아서 옛 링크로 곧바로 되돌아오지 못하게. 서버가 `friend_refusals` 에 적어 두고, 다시 친구가 되면 지움). `via` 는 `'link'` 만 보고 다른 값은 없는 것으로 |
| `POST` | `/api/friends/accept` | `{userId}` 수락. 각 방향은 **그 방향 주인의 기본값**(`/api/share-defaults`)으로 시작 — 맞요청으로 곧바로 친구가 될 때도 같음 |
| `POST` | `/api/friends/decline` | `{userId}` |
| `POST` | `/api/friends/block` | `{userId}` |
| `DELETE` | `/api/friends/:userId` | 친구 끊기 |
| `GET` | `/api/share/:userId` | 내가 그 사람에게 공유하는 항목 |
| `PUT` | `/api/share/:userId` | 항목별 on/off |
| `GET` | `/api/share-defaults` | 새 친구에게 기본으로 보여 줄 것 → `{defaults}`. 정한 적이 없으면 처음 값(몸 쪽 넷 · `absolute` 꺼짐, `streak` · `schedule` · `diet` 켜짐) |
| `PUT` | `/api/share-defaults` | 바꾼 스위치만 `{weightTrend:true}` → `{defaults}`. 참/거짓이 아니면 400(하나라도 틀리면 아무것도 안 바뀜), 모르는 이름은 무시, 몸 항목이 하나도 없으면 `absolute` 는 꺼짐. 이미 맺은 친구는 안 바뀜 |
| `POST` | `/api/share-defaults/apply` | `{expect}`(화면에서 본 값, 옛 앱은 생략) → `{applied}`. **수락된 친구에게 내가 보여 주는 쪽**만 기본값으로 덮음 — 대기 · 차단 · 끊은 관계는 빼고, 친구별로 따로 정한 것도 덮음. `expect` 가 저장된 기본값과 다르면 409 `{conflict, defaults}` 로 아무것도 안 바꿈 |
| `POST` | `/api/snapshots` | `{weekStart, payload}` 내 주간 요약 올리기. `payload.owner`(새 앱이 싣는 그 기록의 계정 id)가 있고 토큰의 계정과 다르면 **409** `{ok:false, conflict:'owner', reason:'다른 계정의 기록입니다'}` · 행 안 바뀜(owner 는 떼고 저장, 없는 옛 앱은 받음) |
| `GET` | `/api/snapshots/:ownerId` | 친구가 **나에게 허용한 항목만** |
| `POST` | `/api/sync/push` | `{records:[{kind,id,updatedAt,deleted,payload}]}`. 어느 레코드든 `payload.syncMeta.owner` 가 토큰의 계정과 다르면 통째로 **409** `{ok:false, conflict:'owner', reason:'다른 계정의 기록입니다'}` · 아무 행도 안 씀(owner 없는 옛 앱은 받음). 거절은 로그에 한 줄(앱 판만, 계정 id 없이) |
| `GET` | `/api/sync/pull?since=` | 그 시각 이후 변경분 |
| `POST` | `/api/ocr` | `{mediaType, data}` (base64 사진) → `{fields}` 결과지 판독 초안 |
| `POST` | `/api/push/device` | `{token, platform: 'android'\|'ios', appVersion?, permission?, secret?}` 앱 알림 기기 등록 → `{ok, fcm}`. 토큰은 20~4096자 `[A-Za-z0-9_-:.]`, 한 사람당 10대(오래 안 켠 것부터 버림). `secret` 은 앱이 서버마다 만든 난수(16~128자, 서버는 sha256 만 둠). 같은 토큰이 **다른 계정의 살아 있는 로그인**에 묶여 있으면 비밀이 맞을 때만 옮기고 아니면 409. FCM 이 꺼진 서버도 받아 둠. 형식이 틀리면 400 |
| `DELETE` | `/api/push/device` | `{token}` 내 기기 등록 해제. 남의 토큰 · 없는 토큰이어도 똑같이 200 `{ok:true}`(아무것도 안 지움 — 답으로 토큰이 있는지 알 수 없게) |
| `GET` | `/api/push/status` | `{fcm, web, devices, webSubs, webMuted}` — `webMuted` 는 "앱이 있어서 크롬으로는 안 보냄". 앱 설정의 「푸시 알림」 줄은 `fcm` 만 봄(크롬 칸은 화면에 없음) |
| `DELETE` | `/api/push/web` | 내 웹 푸시(크롬) 구독 전부 삭제 → `{removed}`. `/api/push/web-subscriptions` 도 같음. 설정의 단추는 없어졌고, 앱이 이 기기의 앱 알림을 등록한 뒤(서버 FCM 켜짐 · 폰 알림 허락일 때만) **계정마다 한 번 저절로** 부름 — 실패하면 다음 등록 때 다시 |

## 친구 초대 링크 (`/i/<코드>`)

앱의 「초대 링크 보내기」가 건네는 주소입니다: `<서버 주소>/i/<코드>` (코드는 대문자 8자,
`ABCDEFGHJKLMNPQRSTUVWXYZ23456789` — 헷갈리는 I · O · 0 · 1 없음). 로그인 없이 열리는 작은
페이지이고, 누르면 앱이 열려 **곧바로 친구가 됩니다**(앱이 `via:'link'` 로 보냄 — 코드 주인의 수락
없이, 위 `/api/friends/request`). 페이지 글도 "링크를 누르면 바로 친구가 돼요".

- **링크만 누르면 바로** — 앱이 깔려 있으면 폰이 이 주소를 앱의 것으로 알고(아래 "앱 링크 파일")
  브라우저 없이 앱을 엽니다. 이 페이지는 앱이 없거나 · 확인이 아직이거나 · 앱 안 브라우저가 링크를
  쥐고 있을 때 보입니다.
- **앱에서 열기** — 안드로이드는 `intent://invite/<코드>#Intent;scheme=mybody;package=io.github.iacobuschoi.mybody;S.browser_fallback_url=<…>;end`,
  아이폰은 `mybody://invite/<코드>`, 컴퓨터는 단추 없이 두 기종의 설치 안내만. fallback(앱이 없을 때)은
  시험 기간이면 이 페이지 `?noapp=1`(설치 안내를 앞세움), 정식 출시 뒤에는 추천인 붙은 플레이 주소.
- **저절로** — 무엇을 할지는 서버가 User-Agent 와 설정으로 정해 `<body data-…>` 에 적고, 페이지의
  스크립트(하나, CSP 해시로만 허락)가 실행합니다.
  - 카카오톡 안 브라우저 → 곧바로 `kakaotalk://web/openExternal?url=<지금 주소>` 로 기본 브라우저에 넘김
  - 인스타그램 · 페이스북 · 라인 · 네이버 안 브라우저 → "오른쪽 위 ⋯ → 다른 브라우저로 열기" 한 줄
  - 안드로이드 → 열리자마자 위 intent 로(단추도 그대로 — 크롬이 누름 없이는 막을 수 있음)
  - 아이폰 → 1.5초 뒤 설치 페이지로("앱이 없으면 설치 페이지로 가요… 여기 있기"). 그 사이에 누르거나
    화면이 가려졌으면 안 가고, `?stay=1`("여기 있기")이면 안 갑니다
  - 한 탭에서 한 번씩만(sessionStorage) — 뒤로 가기로 돌아와도 다시 튕기지 않음.
    스크립트가 꺼져 있어도 단추는 전부 진짜 링크입니다
- **앱이 없나요?** — `tools/app-version.js` 의 설정을 부를 때마다 읽습니다.

  | | 아이폰 | 안드로이드 |
  |---|---|---|
  | 시험 기간(`testing`, 기본) | TestFlight 공개 링크(`--join-ios`) | ① 구글 그룹(`--join-android-group`, 있으면) ② 테스트 참여(`--join-android`) ③ Google Play(추천인) |
  | 출시 뒤(`--testing=off`) | `https://apps.apple.com/app/id6815144446` | Google Play(추천인) |

  필요한 링크가 없으면 "곧 열려요 — 코드 <코드> 를 적어 두세요". Google Play 주소는
  `https://play.google.com/store/apps/details?id=io.github.iacobuschoi.mybody&referrer=invite%3D<코드>` —
  앱이 첫 실행에 설치 추천인으로 초대를 읽습니다. 설치 단추를 누르면 `Mybody 초대 <코드> <이 페이지 주소>` 를
  클립보드에 담고 갑니다(못 담아도 그냥 감). 안드로이드 앱은 처음 탭 화면에서 한 번 읽어 "친구 요청할까요?" 를
  묻고, 아이폰 앱은 스스로 읽지 않고(붙여넣기 허용 창) 「초대 코드 붙여넣기」 를 누를 때 씁니다. 아이폰이
  저절로 설치 페이지로 갈 때는 담을 수 없어서(누른 순간이 아님) 깐 뒤 링크를 다시 누르면 됩니다.
- **누구 코드인지 안 찾습니다.** DB 를 보지 않고 모양만 봅니다 — 있는 코드든 없는 코드든 같은
  페이지라, 주소를 두드려서 이름이나 "이 서버에 있다" 를 알아낼 수 없습니다. 소문자는 대문자
  주소로 302(`noapp` · `stay` 만 이어 붙임), 모양이 틀리면 같은 모양의 404(스크립트 없음).
- CSP `default-src 'none'` 에 스크립트 · 스타일은 해시 하나씩만(페이지에 박는 글자와 같은 문자열에서
  계산 — 어긋날 수 없음. 윈도우에서 git 이 server.js 를 CRLF 로 꺼내도 스크립트의 줄바꿈은 LF 로 맞춰
  내보냅니다 — 브라우저는 `\r\n` 을 `\n` 으로 바꾼 뒤에 해시를 재서, 안 맞추면 스크립트가 조용히
  막힙니다). `noindex` · `no-store` · `Referrer-Policy: no-referrer`(참여 단추를 눌러도 코드가 든 주소가
  따라가지 않음), 로그에도 안 남깁니다.
- 미리보기(og:image · og:url) · 안드로이드 fallback · 담는 글의 주소는 절대 주소가 필요해서, **받은 사람이
  연 주소**(요청의 Host · 터널의 `X-Forwarded-*` 는 `TRUST_PROXY` 일 때만)로 짓습니다 — 공개 주소(`ORIGIN`)가
  옛것이어도 fallback 이 지금 페이지로 돌아오게. Host 가 `ORIGIN` 과 같은 이름이거나, localhost 이거나,
  이상한 모양이면 `ORIGIN` 을 씁니다.
- `Vary: *` — 이 서버의 웹 앱을 연 적 있는 브라우저의 서비스워커가 페이지를 캐시에 담지 못하게
  (담기면 `?noapp=1` 이 캐시의 보통 페이지로 나옵니다).

## 앱 링크 파일 (`/.well-known/…`)

폰이 `https://<서버>/i/…` 를 **앱의 것**으로 확인하는 파일입니다(안드로이드 App Links · 아이폰 Universal
Links). 대답이 틀리거나 없으면 폰은 아무 말 없이 브라우저로 엽니다. 로그인 없음 · 리디렉션 없이 200 ·
`Content-Type: application/json` · `Cache-Control: public, max-age=3600` · HEAD 도 됩니다. 정적 파일보다
먼저 보므로 내보내는 폴더에 같은 이름의 파일이 있어도 이것이 나갑니다. 설정은 부를 때마다 읽습니다
(환경변수가 먼저, 설정 파일이 망가졌으면 기본값).

| 파일 | 내용 | 설정 |
|---|---|---|
| `assetlinks.json` | `io.github.iacobuschoi.mybody` + 서명 인증서 SHA-256 지문. 업로드 키 `06:D9:…:DE:11` 은 늘 들어감 | `androidCertSha256`(배열 또는 쉼표로 이은 글자) · 환경변수 `ANDROID_CERT_SHA256` — 플레이 콘솔 「앱 무결성 → 앱 서명」 의 앱 서명 키 지문을 **더합니다**(없으면 플레이로 깐 폰에서만 링크가 브라우저로 열림). 소문자 · 공백 · 콜론 없는 64자 · `SHA256:` 머리도 다듬고, 모양이 틀린 값은 빼고 로그에 한 번 |
| `apple-app-site-association` | `{"applinks":{"details":[{"appIDs":["<팀>.io.github.iacobuschoi.mybody"],"components":[{"/":"/i/*","comment":"friend invite"}]}]}}` | `appleTeamId` · 환경변수 `APPLE_TEAM_ID`(영문 대문자 · 숫자 10자, 없거나 틀리면 `JT4YLVNKDZ`) |

예전의 `TWA_PACKAGE` · `TWA_FINGERPRINT`(웹 앱을 플레이에 감싸 올리던 길)는 없앴습니다 — 같은 패키지
이름의 진짜 앱이 나왔고, 이 파일은 이제 설정 없이도 늘 나갑니다.

## 컴퓨터로 보는 의견함 (`/inbox`)

운영자 폰 앱의 설정 → 「의견함」 을 컴퓨터 브라우저에서 봅니다: `<서버>/inbox`. 서버 코드가 만들어 보내는
페이지라(`server/inbox-page.js`) 어느 폴더를 내보내든(`STATIC=./release` 여도) 같이 나갑니다.

- **로그인** — 아이디 · 비밀번호(`/api/auth/signin`). `/api/me` 의 `user.isOperator` 가 참이 아니면
  「운영자 계정만 볼 수 있어요」 를 띄우고 방금 받은 로그인을 곧바로 끊습니다(`/api/auth/signout`). 토큰은 기본
  이 탭에만(sessionStorage), 「이 컴퓨터에서 로그인 유지」 를 켜면 localStorage. 「로그아웃」 은 서버의 로그인도
  끊고 둘 다 비우며, 열어 둔 다른 `/inbox` 탭도 같이 나갑니다(같이 쓰는 컴퓨터에서 잊은 탭에 글이 남지 않게).
  나가면 로그인 칸의 아이디도 비웁니다(운영자 아이디를 남기지 않음). 로그인이 끊기면(401) 로그인 칸으로 돌아옵니다.
- **목록 · 자세히** — 앱과 같은 길(위 "의견 보내기" 의 `/api/feedback/inbox…`). 넓으면 왼쪽 목록 · 오른쪽
  자세히(따로 스크롤), 좁으면 한 줄(「← 목록」 은 보던 자리로). 목록 한 줄에 안 읽음 점 · 받은 시각(한국
  시각) · 보낸 사람(표시 이름, 로그인 없이 보냈으면 「익명」) · 판 · 기종 · 보던 화면 · 사진 수 · 글 앞부분. 「안 읽은 것만 / 전체」(안 읽은 것이 더
  있으면 다음 쪽을 저절로) · 「더 보기」 · 「모두 읽음」(받아 둔 가장 새 번호까지) · 「새로고침」(탭으로 돌아왔을
  때 30초가 지났으면 저절로). 열면 읽음(앱과 같음). 사진은 로그인한 채로 받아 페이지 안에서만
  보이고(blob), 누르면 크게, 다른 의견으로 가면 버립니다. 「지우기」 는 페이지 안에서 한 번 묻고.
  키보드 `j` · `k` 로 위아래, `Esc` 로 닫기.
- **남의 글** — 의견 글 · 이름 · 판 · 화면 이름은 로그인 없이도 보낼 수 있는 남의 글자라 전부 글자로만 놓습니다
  (HTML 로 끼워 넣지 않음). CSP `default-src 'none'` 에 스크립트 · 스타일은 해시 하나씩(초대 페이지와 같은
  방식 · 윈도우의 CRLF 에도 맞음), 사진은 `blob:` 만, 요청은 이 서버만(`connect-src 'self'`), 폼은 어디로도
  못 보냄(`form-action 'none'`), 다른 페이지 안에 못 들어감(`frame-ancestors 'none'` · `X-Frame-Options: DENY`).
  `no-store` · `Vary: *`(웹 앱의 서비스워커가 못 담음) · `noindex` · `no-referrer`. 페이지는 누구에게나 같은
  글자이고 DB 를 보지 않습니다 — 막는 것은 API 가 요청마다(401 · 403).

## 검증

```bash
node tools/test-social.js        # 친구·공유 권한 (서버를 띄워 실제 요청)
node tools/test-ocr.js           # 판독 프록시 (가짜 모델 API 로)
node tools/test-fcm.js           # 앱 알림 (가짜 OAuth · FCM 으로 — JWT 서명까지 검증)
node tools/test-feedback.js      # 의견 보내기 (검사 · 한도 · 탈퇴 · 1년 · 주인 알림 · 노트북 도구)
node tools/test-operator-users.js # 운영자의 「가입자 목록」 (운영자만 · 비밀 칸 없음 · 새 가입부터 · 1000명 상한)
node tools/test-sync-owner.js    # 다른 계정의 기록 사본 · 주간 요약은 409 (행 안 바뀜 · owner 없는 옛 앱은 받음)
node tools/test-find-mixed.js    # 섞인 계정 찾기 도구 (믿을 수 있는 id 만 · 씨앗 · scan-h 제외 · DB 에 안 씀)
node tools/test-inbox-page.js    # 컴퓨터로 보는 의견함 /inbox (머리 · CSP 해시 · CRLF · 남의 글이 글자 그대로 ·
                                 #   로그인 · 읽음 · 지우기 · 다른 탭 로그아웃 — 진짜 브라우저로. playwright 가
                                 #   없으면 그 부분만 건너뜀)
node tools/test-appversion.js    # 앱 안 업데이트 안내 · 시험판 참여 링크 · 시험 기간
node tools/test-invite.js        # 친구 초대 링크 페이지 (기종별 앱 열기 · 설치 안내 · 새지 않음 · CSP ·
                                 #   앱 링크 파일 · 스크립트를 가짜 브라우저에서 돌려 봄)
node tools/test-crosscheck.js    # 결과지 검산
node tools/validate.js           # 엔진 예측 대 실제 논문 (게이트)
USERS=100 YEARS=3 node tools/simulate.js
```

가상 사용자 100명이 3년 동안 측정·목표 설정·목표 변경·계획 재조정·체크인·
친구 요청·수락·공유 토글·친구 조회·차단·탈퇴·재가입을 반복합니다.
매 주 불변식을 검사합니다 — 특히 **공유하지 않은 값이 친구 응답에 섞여 나가는지**.

## 다음에 할 일

- **HTTPS 직접 종료**: 터널을 쓰면 필요 없습니다. 직접 하려면 Caddy 한 줄이 가장 쉽습니다.
- **스냅샷을 보는 사람별로 미리 걸러 저장**: 지금은 읽을 때 거릅니다. 읽기 경로가
  하나 뚫려도 허용 안 된 값이 애초에 없도록 하려면 저장할 때 걸러야 합니다.
