#!/usr/bin/env bash
# =============================================================================
# tools/oracle-setup.sh — 오라클 무료 VM(우분투)에 Mybody 서버 올리기
#
#   처음:   curl -fsSL https://raw.githubusercontent.com/iacobuschoi/Mybody/claude/body-management-app-prototype-m4mv4k/tools/oracle-setup.sh | bash
#   고친 뒤: bash ~/mybody/tools/oracle-setup.sh update      (git pull → 다시 빌드 → 재시작)
#   상태:   bash ~/mybody/tools/oracle-setup.sh status
#
# 몇 번 돌려도 됩니다 — 이미 된 것은 건너뜁니다.
#
# 왜 Tailscale 인가
#   노트북에서 쓰던 주소(https://desktop-il9c3if.tail0a8f8f.ts.net)가 앱에 박혀
#   있습니다. VM 의 Tailscale 기기 이름을 같은 이름으로 붙이면 주소가 그대로라
#   앱을 다시 낼 필요가 없습니다. Funnel 은 안에서 밖으로 나가는 연결이라
#   오라클 방화벽(보안 목록 · iptables)에 구멍을 낼 일도 없습니다.
#
# 이 스크립트가 하지 않는 것 (사람이 해야 함)
#   · ~/.mybody/config.json 과 데이터베이스 백업을 노트북에서 가져오기
#   · sudo tailscale up (로그인 링크를 폰으로 열어야 함)
#   docs/ORACLE.md 에 순서가 있습니다.
# =============================================================================
set -euo pipefail

BRANCH="claude/body-management-app-prototype-m4mv4k"
REPO="https://github.com/iacobuschoi/Mybody.git"
DIR="$HOME/mybody"
BACKUPS="$HOME/mybody-backups"
CFG="$HOME/.mybody/config.json"

say()  { printf '\n\033[1m%s\033[0m\n' "$*"; }
ok()   { printf '  ✓ %s\n' "$*"; }
warn() { printf '  ! %s\n' "$*"; }

build_and_restart() {
  cd "$DIR"
  node tools/build-release.js >/dev/null
  ok "배포 빌드(release/) 만듦"
  if [ -f "$CFG" ]; then
    sudo systemctl restart mybody
    sleep 2
    if curl -fsS http://localhost:8080/health >/dev/null; then ok "서버 켜짐 (localhost:8080)"; else warn "서버가 안 떴습니다 — journalctl -u mybody -n 50"; fi
  else
    warn "설정($CFG)이 아직 없어서 서버는 안 켰습니다 — docs/ORACLE.md 3단계"
  fi
}

case "${1:-setup}" in
  update)
    say "새 코드 받기"
    git -C "$DIR" pull --ff-only
    build_and_restart
    exit 0 ;;
  status)
    systemctl --no-pager status mybody | head -5 || true
    curl -fsS http://localhost:8080/health && echo || echo "서버 응답 없음"
    tailscale funnel status 2>/dev/null || echo "funnel 꺼짐"
    ls -1t "$BACKUPS" 2>/dev/null | head -3
    exit 0 ;;
  setup) ;;
  *) echo "사용법: oracle-setup.sh [setup|update|status]"; exit 2 ;;
esac

say "1. 메모리 — 1GB 짜리(E2.1.Micro)면 스왑 2GB"
mem_kb=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
if [ "$mem_kb" -lt 2000000 ] && ! swapon --show | grep -q /swapfile; then
  sudo fallocate -l 2G /swapfile && sudo chmod 600 /swapfile && sudo mkswap /swapfile >/dev/null && sudo swapon /swapfile
  grep -q '/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab >/dev/null
  ok "스왑 2GB"
else
  ok "건너뜀 (메모리 $((mem_kb / 1024))MB)"
fi

say "2. 기본 도구 · Node 22"
sudo apt-get update -qq
sudo apt-get install -y -qq git curl ca-certificates >/dev/null
if ! command -v node >/dev/null || ! node -v | grep -qE '^v(2[2-9]|[3-9][0-9])\.'; then
  # 서버가 내장 SQLite(node:sqlite)를 쓰므로 22 이상이어야 합니다. 우분투 기본 node 는 안 됩니다.
  curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash - >/dev/null
  sudo apt-get install -y -qq nodejs >/dev/null
fi
ok "node $(node -v)"

say "3. 저장소"
if [ -d "$DIR/.git" ]; then
  git -C "$DIR" pull --ff-only -q && ok "최신으로"
else
  git clone -q --branch "$BRANCH" --single-branch "$REPO" "$DIR" && ok "$DIR 에 받음"
fi

say "4. Tailscale"
if ! command -v tailscale >/dev/null; then
  curl -fsSL https://tailscale.com/install.sh | sh >/dev/null
fi
ok "tailscale $(tailscale version | head -1)"

say "5. 서버를 시스템 서비스로 (껐다 켜도 알아서 뜸)"
sudo tee /etc/systemd/system/mybody.service >/dev/null <<UNIT
[Unit]
Description=Mybody server
After=network-online.target
Wants=network-online.target

[Service]
User=$USER
WorkingDirectory=$DIR
ExecStart=$(command -v node) tools/serve.js
Restart=always
RestartSec=3
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
UNIT
sudo systemctl daemon-reload
sudo systemctl enable mybody >/dev/null 2>&1
ok "mybody.service"

say "6. 매일 새벽 4시 백업 (30일치 보관)"
mkdir -p "$BACKUPS"
line="0 4 * * * cd $DIR && $(command -v node) tools/backup.js --out=$BACKUPS >> $BACKUPS/backup.log 2>&1"
( crontab -l 2>/dev/null | grep -v 'tools/backup.js' ; echo "$line" ) | crontab -
ok "crontab"

say "7. 빌드 · 시작"
if [ -f "$CFG" ]; then
  # 노트북 설정에 윈도우 경로(db)가 들어 있으면 여기서는 기본 위치(server/mybody.db)를 씁니다.
  node -e '
    const f=process.argv[1], fs=require("fs"); const c=JSON.parse(fs.readFileSync(f,"utf8"));
    let ch=false; if (c.db && /\\|^[A-Za-z]:/.test(c.db)) { delete c.db; ch=true; }
    if (c.static !== "release") { c.static = "release"; ch=true; }
    if (ch) fs.writeFileSync(f, JSON.stringify(c, null, 2));' "$CFG"
fi
build_and_restart

say "남은 것"
if ! tailscale status >/dev/null 2>&1; then
  echo "  sudo tailscale up --hostname=desktop-il9c3if     # 나오는 링크를 폰으로 열어 로그인"
fi
echo "  sudo tailscale funnel --bg 8080                   # 주소를 인터넷에 엽니다 (재부팅해도 유지)"
echo "  자세한 순서: $DIR/docs/ORACLE.md"
