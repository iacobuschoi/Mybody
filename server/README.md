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
| `PAIR_SECRET` | (없으면 시작 안 함) | 가입 코드. 이걸 아는 사람만 계정을 만들 수 있습니다 |
| `ANTHROPIC_API_KEY` | (없음) | 결과지 자동 판독용 키. **없으면 자동 판독만 꺼집니다** — 앱은 그대로 돕니다 |
| `OCR_MODEL` | `claude-opus-5` | 판독에 쓸 모델 |
| `OCR_PER_DAY` | `40` | 사람당 하루 판독 횟수. 사진 한 장이 돈이 드는 요청이라 막아 둡니다 |
| `OCR_API_URL` | 앤트로픽 API | 사내 프록시를 거쳐야 할 때만 바꾸세요 |

```bash
PORT=3000 DB=~/mybody.db ORIGIN=https://mybody.example.com node server/server.js
```

## 계정

카카오·애플 같은 외부 로그인을 쓰지 않습니다. 이 서버가 직접 관리합니다.
외부 OAuth 는 사업자 등록과 앱 심사가 필요하고, 자가호스팅이라는 전제와도
맞지 않습니다.

- **아이디** 는 이메일이 아니라 영문·숫자 3~32자입니다. 이메일을 받으면
  보관해야 하는 개인정보가 하나 늘어나는데, 이 서버는 비밀번호 재발송을
  하지 않으므로 이메일이 할 일이 없습니다.
- **비밀번호** 는 scrypt 해시로만 저장됩니다. 원문은 어디에도 남지 않습니다.
- **비밀번호를 잊으면 되돌릴 방법이 없습니다.** 메일을 보내지 않기 때문입니다.
  잊었다면 서버 주인이 DB 에서 계정을 지우고 다시 만드는 수밖에 없습니다.
- 로그인 실패는 아이디별로 15분에 8번까지입니다. 무차별 대입을 막습니다.
- 세션은 90일 뒤 만료됩니다. 비밀번호를 바꾸면 다른 기기가 전부 로그아웃됩니다 —
  토큰이 샜을 때의 복구 수단입니다.

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
| `POST` | `/api/auth/signup` | `{handle, password, displayName, pairSecret}` → `{token, user}` (로그인 불필요) |
| `POST` | `/api/auth/signin` | `{handle, password}` → `{token, user}` (로그인 불필요) |
| `POST` | `/api/auth/signout` | 이 토큰만 폐기 |
| `POST` | `/api/auth/signout-all` | 모든 기기 로그아웃 |
| `POST` | `/api/auth/password` | `{current, next}` 비밀번호 변경 (다른 기기 전부 로그아웃) |
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

- **비밀번호 찾기**: 지금은 잊으면 되돌릴 방법이 없습니다. 나와 친구 몇 명은
  괜찮지만 남에게 주려면 이게 먼저입니다. 메일을 보내려면 보관할 개인정보가
  하나 늘어나므로, 복구 코드를 가입 때 한 번 보여주는 쪽이 이 앱에 맞습니다.
  (외부 OAuth 는 쓰지 않기로 했습니다 — 사업자 등록과 앱 심사가 필요하고
  자가호스팅이라는 전제와도 맞지 않습니다.)
- **HTTPS 직접 종료**: 터널을 쓰면 필요 없습니다. 직접 하려면 Caddy 한 줄이 가장 쉽습니다.
- **스냅샷을 보는 사람별로 미리 걸러 저장**: 지금은 읽을 때 거릅니다. 읽기 경로가
  하나 뚫려도 허용 안 된 값이 애초에 없도록 하려면 저장할 때 걸러야 합니다.
