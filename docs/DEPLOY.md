# 배포

> 마음먹었을 때 바로 할 수 있게 적어 둔 문서입니다.
> 명령을 위에서 아래로 그대로 치면 됩니다.

---

## 0. 한 번만 확인 (2분)

```bash
node tools/preflight.js
```

빨간 줄이 하나도 없으면 배포해도 됩니다. 빨간 줄이 있으면 그것만 고치세요 —
무엇을 고쳐야 하는지 줄마다 적혀 있습니다.

---

## 1. 서버 띄우기

### 처음 한 번

```bash
# 가입 코드를 만들어 파일에 저장 (이걸 아는 사람만 계정을 만들 수 있습니다)
openssl rand -hex 16 > ~/.mybody-pair
chmod 600 ~/.mybody-pair
```

### 매번

```bash
cd ~/Mybody
node tools/build-release.js                       # release/ 생성

PAIR_SECRET=$(cat ~/.mybody-pair) \
STATIC=./release \
ORIGIN=https://내주소.example.com \
node server/server.js
```

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

## 2. 밖에서 접속하게

```bash
cloudflared tunnel --url http://localhost:8080
```

`https://xxxx.trycloudflare.com` 이 나옵니다. HTTPS까지 같이 됩니다.
**HTTPS여야 합니다** — 서비스워커와 카메라가 HTTP에서는 안 돕니다.

그 주소를 `ORIGIN` 에도 넣고 서버를 다시 띄우세요.

고정 주소가 필요하면 Cloudflare 계정을 연결해 이름 있는 터널을 만듭니다.
더 사적으로 하려면 Tailscale (`tailscale serve https / http://localhost:8080`) —
대신 상대도 Tailscale 을 깔아야 합니다.

---

## 3. 폰에 앱처럼 깔기

주소를 열고:

- **iPhone (Safari)** — 공유 → 홈 화면에 추가
- **Android (Chrome)** — 주소창 옆 설치 아이콘, 또는 메뉴 → 앱 설치

깔고 나면 주소창 없이 뜨고, 인터넷이 끊겨도 열립니다.

---

## 4. 백업

```bash
# crontab -e 에 한 줄
0 4 * * * sqlite3 ~/Mybody/server/mybody.db ".backup ~/backup/mybody-$(date +\%F).db"
```

DB 파일 하나에 전부 들어 있습니다. 사진은 서버가 아니라 각자 기기에만
있으므로 백업 대상이 아닙니다 — 그 말은 폰을 잃어버리면 사진도 같이
사라진다는 뜻입니다.

---

## 5. 친구 들이기

1. 친구에게 **주소**와 **가입 코드**(`~/.mybody-pair` 내용)를 줍니다.
2. 친구가 계정을 만듭니다. 가입 코드는 가입할 때만 필요합니다.
3. 앱 안에서 서로 **초대 코드**를 주고받아 친구를 맺습니다.
   (전화번호·이메일로는 서로를 찾을 수 없습니다. 의도한 것입니다.)
4. 공유는 기본이 거의 다 꺼져 있습니다. 친구마다 항목을 직접 켜야 나갑니다.

---

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
| 비밀번호 찾기 | 메일을 안 보냅니다. 잊으면 서버 주인이 DB 에서 지우고 다시 만드는 수밖에 없습니다. |
| 상시 접속 | 컴퓨터가 꺼지면 친구도 못 봅니다. 라즈베리파이나 클라우드로 옮겨야 해결됩니다. |
| 사진 백업 | 사진은 기기에만 있습니다. 폰을 잃으면 사진도 잃습니다. 숫자는 서버에 있어 남습니다. |
| 여러 기기 동시 수정 | 나중에 저장한 쪽이 이깁니다. 혼자 쓰면 문제되지 않습니다. |

남에게 **파는** 앱으로 갈 거면 위 네 개와 건강정보 처리방침이 먼저입니다.
친구 몇 명과 쓰는 데는 지금 상태로 충분합니다.
