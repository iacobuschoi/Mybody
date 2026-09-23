# 서버를 오라클 무료 VM 으로 옮기기

노트북에서 돌던 서버를 오라클 클라우드 **Always Free**(서울) VM 으로 옮깁니다.
**주소는 그대로**입니다 — `https://desktop-il9c3if.tail0a8f8f.ts.net`.
VM 의 Tailscale 기기 이름을 노트북과 같은 `desktop-il9c3if` 로 붙이기 때문에,
앱을 다시 낼 필요도, 도메인을 살 필요도, 오라클 방화벽을 열 필요도 없습니다.

걸리는 시간: 계정 만들기 20분 + 옮기기 20분. 옮기는 동안 5분쯤 서버가 멈춥니다.

---

## 1. 오라클 계정 (폰이나 PC 브라우저, 주인)

1. <https://signup.cloud.oracle.com> → 국가 **대한민국**, **홈 리전은 `South Korea Central (Seoul)`**.
   홈 리전은 나중에 못 바꿉니다. 춘천은 ARM(A1) VM 을 못 만듭니다.
2. 해외결제 되는 카드로 본인 확인(1달러 승인 후 취소). 무료 한도 안에서는 청구가 없습니다.
3. 가입이 끝나면 **Billing → Upgrade to Pay As You Go** 를 권합니다. 무료 계정은
   "7일간 CPU·네트워크 20% 미만" 이면 VM 을 회수할 수 있는데(이 앱은 거의 항상
   그 아래입니다), PAYG 로 바꾸면 그 규칙에서 빠지고 **무료 한도 안에서는 여전히 0원**입니다.
   바꾼 뒤 **Budgets** 에서 월 ₩10,000 알림을 하나 걸어 두세요.

## 2. VM 만들기 (브라우저, 주인)

Compute → Instances → **Create instance**

| 칸 | 값 |
|---|---|
| Name | `mybody` |
| Image | **Canonical Ubuntu 24.04** |
| Shape | **Ampere A1.Flex, 1 OCPU · 6 GB** (Always Free). "Out of capacity" 면 **VM.Standard.E2.1.Micro** (1GB) — 그걸로도 충분합니다 |
| Networking | 기본값 (공개 IP 있는 새 VCN) |
| SSH keys | **Generate a key pair for me** → **개인 키 저장**(`ssh-key-….key`) |

**보안 목록(Ingress)은 건드리지 않습니다.** Funnel 은 밖으로 나가는 연결이라 SSH(22) 말고는 열 게 없습니다.

만들어지면 화면의 **Public IP** 를 적어 둡니다.

## 3. 설치 (노트북 세션에 맡기면 됨)

노트북 Claude 세션에 `docs/LOCAL-TASKS.md 15번 해줘` 라고 하면 아래를 합니다. 직접 할 때:

```powershell
# 노트북 PowerShell — 개인 키 권한 좁히기(윈도우 ssh 가 넓으면 거부)
icacls "$HOME\Downloads\ssh-key-XXXX.key" /inheritance:r /grant:r "$env:USERNAME:R"
ssh -i "$HOME\Downloads\ssh-key-XXXX.key" ubuntu@<공개IP>
```

VM 에서:

```bash
curl -fsSL https://raw.githubusercontent.com/iacobuschoi/Mybody/claude/body-management-app-prototype-m4mv4k/tools/oracle-setup.sh | bash
```

Node 22 · 저장소 · Tailscale · 서비스 등록 · 매일 백업까지 합니다. 설정이 아직 없어서 서버는 안 켭니다(정상).

## 4. 옮기기 (노트북 → VM)

순서가 중요합니다 — **노트북 서버를 끈 다음** 마지막 백업을 떠야 그 뒤 기록이 안 빠집니다.

```powershell
# 노트북 — 1) 서버 끄기: launch.js 창에서 Ctrl+C (Tailscale Funnel 도 같이 꺼집니다)
# 2) 마지막 백업
node tools/backup.js --out=$HOME\mybody-move
# 3) 설정과 백업을 VM 으로
scp -i "$HOME\Downloads\ssh-key-XXXX.key" $HOME\.mybody\config.json ubuntu@<공개IP>:/home/ubuntu/
scp -i "$HOME\Downloads\ssh-key-XXXX.key" (Get-ChildItem $HOME\mybody-move\mybody-*.db | Sort LastWriteTime | Select -Last 1).FullName ubuntu@<공개IP>:/home/ubuntu/last.db
```

`config.json` 에는 가입 코드 · 알림 열쇠(VAPID) · 판독 API 키가 들어 있습니다. **알림 열쇠가 바뀌면
친구들 폰 알림 구독이 전부 끊기니** 새로 만들지 말고 꼭 이 파일을 옮기세요. 저장소에는 절대 넣지 않습니다.

VM 에서:

```bash
mkdir -p ~/.mybody && mv ~/config.json ~/.mybody/config.json && chmod 600 ~/.mybody/config.json
cd ~/mybody && node tools/backup.js --restore ~/last.db      # "계정 N명 · 친구 N건" 이 노트북과 같은지
bash ~/mybody/tools/oracle-setup.sh                          # 설정을 읽어 서버를 켭니다
```

## 5. 주소 넘기기 (Tailscale 이름)

같은 테일넷 안에서 기기 이름은 하나만 쓸 수 있습니다.

1. <https://login.tailscale.com/admin/machines> → 노트북(`desktop-il9c3if`) **⋯ → Edit machine name** →
   `laptop` 으로 바꿈 (노트북은 테일넷에 그대로 남아도 됩니다).
2. VM 에서:
   ```bash
   sudo tailscale up --hostname=desktop-il9c3if     # 링크를 폰으로 열어 로그인
   sudo tailscale funnel --bg 8080
   ```
   이미 로그인했는데 이름이 `mybody` 등으로 붙었으면 관리 화면에서 VM 이름을
   `desktop-il9c3if` 로 바꾸면 됩니다.
3. 확인 — 폰 데이터(와이파이 끄고)로 `https://desktop-il9c3if.tail0a8f8f.ts.net/health` 가 열리는지,
   앱에서 로그인·친구 목록·인바디 판독 한 번.

Funnel 이 "not enabled for this node" 라고 하면 노트북 때처럼
<https://login.tailscale.com/admin/acls> 의 `nodeAttrs` 에 funnel 이 있는지 봅니다(`tools/launch.js` 가 안내하던 것과 같음).

## 6. 그 뒤

| 할 때 | 명령 (VM) |
|---|---|
| 코드 고친 걸 반영 | `bash ~/mybody/tools/oracle-setup.sh update` |
| 상태 보기 | `bash ~/mybody/tools/oracle-setup.sh status` |
| 로그 | `journalctl -u mybody -n 100 --no-pager` |
| 백업 목록 | `cd ~/mybody && node tools/backup.js --list --out=~/mybody-backups` |

백업은 VM 안(`~/mybody-backups`, 30일치)에만 있습니다. VM 이 통째로 사라지는 경우를 대비해
한 달에 한 번쯤 노트북으로 하나 받아 두세요: `scp -i … ubuntu@<공개IP>:mybody-backups/<파일> .`

노트북은 이제 서버를 안 켜도 됩니다. **다시 켜면 안 됩니다** — 두 곳에서 기록이 갈라집니다.
