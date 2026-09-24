#!/usr/bin/env bash
# =============================================================================
# factory/scripts/macmini-setup.sh — 맥 미니를 기기 실험실로. 다시 돌려도 안전.
#
#   bash factory/scripts/macmini-setup.sh
#
# 주인이 미리 해 둘 것 (스크립트가 못 하는 것):
#   · App Store 에서 Xcode 설치 → 한 번 실행 → Settings → Accounts 에 Apple ID 로그인 (자동 서명용)
#   · 시스템 설정 → 사용자: 실험실 전용 사용자로 자동 로그인 · FileVault 끄기(정전 뒤 무인 부팅)
#   · gh auth login · claude 로그인
#   · 폰 연결: 아이폰 「신뢰」 + 개발자 모드 · 안드로이드 USB 디버깅 허용 (docs/factory/SETUP.md 4-3)
# =============================================================================
set -euo pipefail
FLUTTER_VERSION="${FLUTTER_VERSION:-3.41.2}"
say() { printf '\n\033[1m== %s\033[0m\n' "$*"; }

say "Xcode"
xcode-select -p >/dev/null 2>&1 && xcodebuild -version | head -1 || { echo "Xcode 가 없습니다 — App Store 에서 설치 후 다시"; exit 1; }
sudo xcodebuild -license accept 2>/dev/null || true
xcodebuild -downloadPlatform iOS >/dev/null 2>&1 || true

say "Homebrew · 도구"
command -v brew >/dev/null || /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
eval "$(/opt/homebrew/bin/brew shellenv)"
brew install -q git gh node jq tmux cocoapods openjdk@17 2>/dev/null || true
brew install -q --cask android-commandlinetools 2>/dev/null || true
sudo ln -sfn /opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk /Library/Java/JavaVirtualMachines/openjdk-17.jdk 2>/dev/null || true
command -v gem >/dev/null && sudo gem install fastlane -N -q >/dev/null 2>&1 || true

say "Flutter $FLUTTER_VERSION"
[ -d "$HOME/flutter" ] || git clone -q --depth 1 --branch "$FLUTTER_VERSION" https://github.com/flutter/flutter.git "$HOME/flutter"
grep -q 'flutter/bin' "$HOME/.zprofile" 2>/dev/null || echo 'export PATH="$HOME/flutter/bin:$HOME/.pub-cache/bin:$HOME/.maestro/bin:$PATH"' >> "$HOME/.zprofile"
export PATH="$HOME/flutter/bin:$HOME/.pub-cache/bin:$HOME/.maestro/bin:$PATH"
flutter --version | head -1

say "Android SDK (arm64)"
export ANDROID_HOME="$HOME/Library/Android/sdk"; mkdir -p "$ANDROID_HOME"
grep -q ANDROID_HOME "$HOME/.zprofile" || echo "export ANDROID_HOME=\"$ANDROID_HOME\"; export PATH=\"\$ANDROID_HOME/platform-tools:\$ANDROID_HOME/emulator:\$PATH\"" >> "$HOME/.zprofile"
SDKM="$(ls /opt/homebrew/share/android-commandlinetools/cmdline-tools/latest/bin/sdkmanager 2>/dev/null || true)"
if [ -n "$SDKM" ]; then
  yes | "$SDKM" --sdk_root="$ANDROID_HOME" --licenses >/dev/null 2>&1 || true
  "$SDKM" --sdk_root="$ANDROID_HOME" "platform-tools" "emulator" "platforms;android-36" "build-tools;36.0.0" "system-images;android-36;google_apis;arm64-v8a" >/dev/null
  flutter config --android-sdk "$ANDROID_HOME" >/dev/null
  yes | flutter doctor --android-licenses >/dev/null 2>&1 || true
fi

say "시험 도구 (Maestro · Patrol)"
command -v maestro >/dev/null || curl -fsSL "https://get.maestro.mobile.dev" | bash >/dev/null
dart pub global activate patrol_cli >/dev/null 2>&1 || true

say "Claude Code · mobile-mcp · 세션 설정"
command -v claude >/dev/null || curl -fsSL https://claude.ai/install.sh | bash >/dev/null
claude mcp add --scope user mobile-mcp -- npx -y @mobilenext/mobile-mcp@latest >/dev/null 2>&1 || true
mkdir -p "$HOME/.claude"; S="$HOME/.claude/settings.json"; [ -f "$S" ] || echo '{}' > "$S"
# 클라우드 스레드의 메시지가 승인 창 없이 들어오게 (MyBody 에서 SendMessage 가 걸린 원인) · 실험 기능 팀은 끔
jq '. + {"crossSessionInbound":"accept","dialogExpiry":"never","env":((.env//{}) + {"CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS":"0"})}' "$S" > "$S.tmp" && mv "$S.tmp" "$S"
echo "  ~/.claude/settings.json: crossSessionInbound=accept"

say "켜 두기"
sudo pmset -a sleep 0 disksleep 0 displaysleep 10 autorestart 1 womp 1 >/dev/null 2>&1 || true

say "mac-lab 상주 세션 (로그인 항목)"
mkdir -p "$HOME/lab" "$HOME/Library/LaunchAgents"
LAB="$HOME/lab/app-factory"
[ -d "$LAB" ] || gh repo clone "$(gh api user -q .login)/app-factory" "$LAB" -- -q 2>/dev/null || true
cat > "$HOME/lab/mac-lab.sh" <<'SH'
#!/bin/bash
export PATH="$HOME/flutter/bin:$HOME/.pub-cache/bin:$HOME/.maestro/bin:$HOME/.local/bin:/opt/homebrew/bin:$PATH"
cd "$HOME/lab/app-factory" && git pull -q || true
tmux has-session -t lab 2>/dev/null || tmux new -d -s lab 'claude remote-control --name mac-lab --spawn worktree --permission-mode auto'
SH
chmod +x "$HOME/lab/mac-lab.sh"
cat > "$HOME/Library/LaunchAgents/lab.maclab.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>Label</key><string>lab.maclab</string><key>ProgramArguments</key><array><string>$HOME/lab/mac-lab.sh</string></array>
<key>RunAtLoad</key><true/><key>StartInterval</key><integer>600</integer></dict></plist>
PL
launchctl unload "$HOME/Library/LaunchAgents/lab.maclab.plist" 2>/dev/null || true
launchctl load "$HOME/Library/LaunchAgents/lab.maclab.plist"
echo "  로그인마다 · 10분마다 mac-lab 이 떠 있는지 확인"

say "확인"
flutter doctor 2>&1 | grep -E '^\[' || true
adb devices 2>/dev/null | tail -n +2 | grep -v '^$' || echo "  안드로이드 기기 없음"
xcrun xctrace list devices 2>/dev/null | grep -i iphone | grep -v Simulator || echo "  아이폰 실기기 없음"
echo; echo "끝. 러너 등록은 factory/scripts/bootstrap.sh (5절) 가 합니다."
