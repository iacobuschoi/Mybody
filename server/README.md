# Mybody 서버 (자가호스팅)

내 컴퓨터에서 돌리는 서버입니다. **설치할 게 없습니다** — Node 22만 있으면 됩니다.
데이터베이스는 Node 내장 SQLite를 쓰고 파일 하나(`mybody.db`)에 전부 들어갑니다.

## 실행

```bash
PAIR_SECRET=$(openssl rand -hex 16) node server/server.js
```

`PAIR_SECRET` 은 **이 서버에 계정을 만들 수 있는 사람을 정하는 값**입니다.
이 값을 알려준 사람만 가입할 수 있습니다. 없으면 서버가 시작하지 않습니다 —
아무나 로그인할 수 있는 서버가 되기 때문입니다.

가입한 뒤에는 **비밀번호만으로** 들어옵니다. 로그인할 때마다 이 값을
요구하면 그게 사실상 공용 비밀번호가 되어, 한 사람만 새도 전원이 뚫립니다.

값은 한 번 정하면 계속 같은 것을 쓰세요 (예: `~/.mybody-pair` 에 저장):

```bash
export PAIR_SECRET=$(cat ~/.mybody-pair)
node server/server.js
```

```
Mybody 서버 실행 중
  주소   http://localhost:8080
  DB     server/mybody.db
  정적   prototype
```

브라우저에서 <http://localhost:8080> 을 열면 앱이 그대로 뜹니다.

### 설정

| 환경변수 | 기본값 | 설명 |
|---|---|---|
| `PORT` | `8080` | 포트 |
| `DB` | `server/mybody.db` | DB 파일 경로 |
| `STATIC` | `../prototype` | 정적 파일 폴더 |
| `ORIGIN` | `*` | CORS 허용 출처. 인터넷에 열 때는 실제 도메인으로 좁히세요 |
| `TRUST_PROXY` | (꺼짐) | `1` 로 켜면 `x-forwarded-for` 를 믿습니다. **터널이나 리버스 프록시 뒤에서만** 켜세요 — 직접 노출된 서버에서 켜면 아무나 헤더 한 줄로 속도 제한을 피합니다 |
| `RATE_MAX` | `300` | `/api` 분당 허용 요청 수 (IP당). 정적 파일은 안 셉니다 |
| `AUTH_MAX` | `20` | 로그인·가입 분당 허용 횟수 (IP당). 비밀번호 확인은 scrypt 라 비싸서 따로 더 빡빡하게 막습니다 |
| `BODY_TIMEOUT_MS` | `30000` | 본문을 다 받기까지 기다리는 시간. 넘으면 끊습니다 |
| `PAIR_SECRET` | (없으면 시작 안 함) | 가입 코드. 이걸 아는 사람만 계정을 만들 수 있습니다 |
| `ANTHROPIC_API_KEY` | (없음) | 결과지 자동 판독용 키. **없으면 자동 판독만 꺼집니다** — 앱은 그대로 돕니다 |
| `OCR_MODEL` | `claude-opus-5` | 판독에 쓸 모델 |
| `OCR_PER_DAY` | `40` | **사람당** 하루 판독 횟수 |
| `OCR_PER_DAY_TOTAL` | `OCR_PER_DAY × 5` | **서버 전체** 하루 판독 횟수. 가입 코드가 새면 계정을 늘려 사람당 한도를 피할 수 있어서, 청구서는 이걸로 막습니다 |
| `OCR_API_URL` | 앤트로픽 API | 사내 프록시를 거쳐야 할 때만 바꾸세요 |

```bash
PORT=3000 DB=~/mybody.db ORIGIN=https://mybody.example.com node server/server.js
```

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
  따로 받습니다 — `signUp` 은 `healthConsent` 가 현재 문구 판(`HEALTH_CONSENT_VERSION`)과
  같을 때만 통과합니다. 동의 시각과 판은 `users.consent_health_at` ·
  `consent_version` 에 남고, 본인은 `/api/me` 에서 볼 수 있습니다.
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

## API

전부 `/api` 아래이고, 로그인 외에는 `Authorization: Bearer <token>` 이 필요합니다.

| 메서드 | 경로 | 설명 |
|---|---|---|
| `GET` | `/api/health` | 살아 있는지 (로그인 불필요) |
| `POST` | `/api/auth/signup` | `{handle, password, displayName, pairSecret, healthConsent}` → `{token, user, recoveryCode}` (로그인 불필요) |
| `POST` | `/api/auth/signin` | `{handle, password}` → `{token, user}` (로그인 불필요) |
| `POST` | `/api/auth/signout` | 이 토큰만 폐기 |
| `POST` | `/api/auth/signout-all` | 모든 기기 로그아웃 |
| `POST` | `/api/auth/password` | `{current, next}` 비밀번호 변경 (다른 기기 전부 로그아웃) |
| `POST` | `/api/auth/recover` | `{handle, code, password}` 복구 코드로 비밀번호 재설정 → `{token, user, recoveryCode}` (로그인 불필요) |
| `POST` | `/api/auth/recovery-code` | `{password}` 복구 코드 재발급 → `{recoveryCode}` |
| `GET` | `/api/me` | 내 정보 + 기록 수 |
| `PATCH` | `/api/me` | `{displayName}` |
| `DELETE` | `/api/me` | 계정 삭제 (친구·공유·스냅샷·기록 연쇄 삭제) |
| `GET` | `/api/friends` | 친구 · 받은 요청 · 보낸 요청 · 차단 |
| `POST` | `/api/friends/request` | `{inviteCode}` |
| `POST` | `/api/friends/accept` | `{userId}` |
| `POST` | `/api/friends/decline` | `{userId}` |
| `POST` | `/api/friends/block` | `{userId}` |
| `DELETE` | `/api/friends/:userId` | 친구 끊기 |
| `GET` | `/api/share/:userId` | 내가 그 사람에게 공유하는 항목 |
| `PUT` | `/api/share/:userId` | 항목별 on/off |
| `POST` | `/api/snapshots` | `{weekStart, payload}` 내 주간 요약 올리기 |
| `GET` | `/api/snapshots/:ownerId` | 친구가 **나에게 허용한 항목만** |
| `POST` | `/api/sync/push` | `{records:[{kind,id,updatedAt,deleted,payload}]}` |
| `GET` | `/api/sync/pull?since=` | 그 시각 이후 변경분 |
| `POST` | `/api/ocr` | `{mediaType, data}` (base64 사진) → `{fields}` 결과지 판독 초안 |

## 검증

```bash
node tools/test-social.js        # 친구·공유 권한 (서버를 띄워 실제 요청)
node tools/test-ocr.js           # 판독 프록시 (가짜 모델 API 로)
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
