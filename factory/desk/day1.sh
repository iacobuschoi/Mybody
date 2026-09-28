#!/usr/bin/env bash
# =============================================================================
# 맥 미니 첫날 — 터미널에 이 한 줄:
#
#   bash <(curl -fsSL https://raw.githubusercontent.com/iacobuschoi/Mybody/claude/app-dev-automation-workflow-h4d88r/factory/desk/day1.sh)
#
# Homebrew · git · gh · 파이썬 · Claude Code 를 깔고, 저장소를 ~/lab/Mybody 로 받고, 책상 시스템을 설치합니다.
# 중간에 맥 로그인 암호를 두세 번 묻습니다(Homebrew · 전원 설정). 다시 돌려도 안전합니다.
# =============================================================================
set -euo pipefail
BRANCH="claude/app-dev-automation-workflow-h4d88r"
REPO="https://github.com/iacobuschoi/Mybody.git"
step() { printf '\n\033[1;36m▶ %s\033[0m\n' "$*"; }

[ "$(uname)" = Darwin ] || { echo "맥에서 돌리세요"; exit 1; }

step "1/5 Homebrew (처음이면 5~10분 · 암호를 물으면 맥 로그인 암호)"
if ! command -v brew >/dev/null && [ ! -x /opt/homebrew/bin/brew ]; then
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
eval "$(/opt/homebrew/bin/brew shellenv)"
grep -q 'brew shellenv' "$HOME/.zprofile" 2>/dev/null || echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> "$HOME/.zprofile"

step "2/5 git · gh · 파이썬 3.12"
brew install -q git gh python@3.12 jq

step "3/5 저장소 → ~/lab/Mybody"
mkdir -p "$HOME/lab"
if [ -d "$HOME/lab/Mybody/.git" ]; then
  git -C "$HOME/lab/Mybody" fetch -q origin "$BRANCH" && git -C "$HOME/lab/Mybody" checkout -q "$BRANCH" && git -C "$HOME/lab/Mybody" pull -q
else
  git clone -q -b "$BRANCH" "$REPO" "$HOME/lab/Mybody"
fi

step "4/5 Claude Code"
if ! command -v claude >/dev/null && [ ! -x "$HOME/.local/bin/claude" ]; then
  curl -fsSL https://claude.ai/install.sh | bash
fi
grep -q '.local/bin' "$HOME/.zprofile" 2>/dev/null || echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.zprofile"
export PATH="$HOME/.local/bin:$PATH"

step "5/5 책상 시스템"
bash "$HOME/lab/Mybody/factory/desk/install.sh"

cat <<'TXT'

────────────────────────────────────────────────────────────
설치 끝. 남은 것 (터미널에서 차례로):

  1) claude            → /login 으로 claude.ai 로그인 → 로그인되면 /exit
  2) gh auth login     → GitHub.com · HTTPS · 브라우저로 로그인  (공장 브리핑용 · 지금 안 해도 됨)
  3) cd ~/lab/desk && .venv/bin/python -m desk selftest
  4) .venv/bin/python -m desk calibrate      → 박수 두 번 쳐서 ★ 확인, Ctrl+C
  5) deskctl sleep     → 화면이 꺼지면 박수 두 번!

막히면 화면 사진을 Claude 에게.
────────────────────────────────────────────────────────────
TXT
