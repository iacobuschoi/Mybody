# Mybody 서버 (자가호스팅)

내 컴퓨터에서 돌리는 서버입니다. **설치할 게 없습니다** — Node 22만 있으면 됩니다.
데이터베이스는 Node 내장 SQLite를 쓰고 파일 하나(`mybody.db`)에 전부 들어갑니다.

## 실행

```bash
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

```bash
PORT=3000 DB=~/mybody.db ORIGIN=https://mybody.example.com node server/server.js
```

## 밖에서 접속하기 (친구 기능)

집 컴퓨터는 보통 공유기 뒤에 있어서 밖에서 바로 못 들어옵니다.
**포트포워딩 없이** 공개 주소를 얻는 방법 두 가지:

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
- 지금 로그인은 프로토타입용 목업입니다. 실제 카카오 로그인은 아래 "다음에 할 일" 참고.

## API

전부 `/api` 아래이고, 로그인 외에는 `Authorization: Bearer <token>` 이 필요합니다.

| 메서드 | 경로 | 설명 |
|---|---|---|
| `POST` | `/api/auth/signin` | `{provider, handle, displayName}` → `{token, user}` |
| `POST` | `/api/auth/signout` | 토큰 폐기 |
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

## 검증

```bash
USERS=100 YEARS=3 node tools/simulate.js
```

가상 사용자 100명이 3년 동안 측정·목표 설정·목표 변경·계획 재조정·체크인·
친구 요청·수락·공유 토글·친구 조회·차단·탈퇴·재가입을 반복합니다.
매 주 불변식을 검사합니다 — 특히 **공유하지 않은 값이 친구 응답에 섞여 나가는지**.

## 다음에 할 일

- **실제 카카오 로그인**: 카카오 개발자 콘솔에서 앱 등록 → REST API 키 발급 →
  `/api/auth/kakao/callback` 라우트를 추가해 인가 코드를 토큰으로 교환하고,
  카카오 사용자 ID를 `handle` 로 쓰면 됩니다. 지금 구조에서 라우트 하나만 추가하면 됩니다.
- **HTTPS 직접 종료**: 터널을 쓰면 필요 없습니다. 직접 하려면 Caddy 한 줄이 가장 쉽습니다.
- **스냅샷을 보는 사람별로 미리 걸러 저장**: 지금은 읽을 때 거릅니다. 읽기 경로가
  하나 뚫려도 허용 안 된 값이 애초에 없도록 하려면 저장할 때 걸러야 합니다.
