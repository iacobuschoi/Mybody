#!/usr/bin/env bash
# =============================================================================
# factory/desk/install.sh — 맥 미니에 책상 시스템 설치. 다시 돌려도 안전.
#
#   bash factory/desk/install.sh
#
# 하는 일: 파이썬 환경 · 받아쓰기 모델 내려받기 · 전원 설정(맥은 안 자고 화면만 꺼짐) · 비서 폴더 ·
#         deskctl 명령 · 로그인 시 자동 실행(launchd) · 점검.
# 한 번은 사람이 해야 하는 것(스크립트가 끝에 다시 알려 줌):
#   · 「deskd 이(가) 마이크에 접근하려고 합니다」 창 — 허용 (시험 때는 「터미널」 도 한 번)
#   · 얼굴 등록(deskctl enroll) — 「deskd 이(가) 카메라에 접근하려고 합니다」 창도 허용
#   · (선택) 시스템 음성 Yuna (프리미엄) 내려받기 — 설정 → 손쉬운 사용 → 읽기 및 말하기. 평소엔 Supertonic 이 말하고 say 는 예비
#   · 화면이 꺼졌다 켜질 때 암호 안 묻게 — 설정 → 잠금 화면 → 「화면 보호기 시작 또는 디스플레이가 꺼진 후 암호 요구」 → 안 함
# =============================================================================
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
DESK="$HOME/lab/desk"; ASSIST="$HOME/lab/desk-assistant"; VENV="$DESK/.venv"
say_() { printf '\n\033[1m== %s\033[0m\n' "$*"; }
[ "$(uname)" = Darwin ] || { echo "맥에서만 돌립니다"; exit 1; }
[ "$(uname -m)" = arm64 ] || echo "※ 애플 실리콘이 아니면 mlx-whisper 가 안 돕니다 — config 의 stt 를 바꿔야 합니다"

say_ "코드 복사 → $DESK"
mkdir -p "$DESK" "$ASSIST" "$HOME/.config/desk" "$HOME/Library/Logs" "$HOME/Library/LaunchAgents" "$HOME/.local/bin"
rsync -a --delete --exclude .venv "$HERE/" "$DESK/"
[ -f "$HOME/.config/desk/config.toml" ] || cp "$HERE/config.example.toml" "$HOME/.config/desk/config.toml"
if command -v gh >/dev/null && gh auth status >/dev/null 2>&1; then
  me=$(gh api user -q .login)
  sed -i '' -e "s#^repo = \"\"#repo = \"$me/app-factory\"#" -e "s#^ship_repo = \"\"#ship_repo = \"$me/app-factory-ship\"#" "$HOME/.config/desk/config.toml"
fi

say_ "파이썬 환경"
PY=$(command -v python3.12 || command -v python3.13 || command -v python3.11 || true)
[ -n "$PY" ] || { HOMEBREW_NO_ASK=1 brew install -q python@3.12; PY=$(command -v python3.12); }
[ -d "$VENV" ] || "$PY" -m venv "$VENV"
"$VENV/bin/pip" install -q --upgrade pip
"$VENV/bin/pip" install -q numpy sounddevice webrtcvad-wheels mlx-whisper pyobjc-framework-Quartz \
  opencv-python-headless pyobjc-framework-AVFoundation \
  supertonic     # 얼굴 인증(맥 안에서만) · 카메라 이름으로 고르기 · 신경망 목소리(맥 안에서, 키 · 결제 없음)

say_ "마이크 · 스피커 고르기"
# 마이크: Brio 가 있으면 그것. 스피커: 맥 미니 내장(TV 가 꺼져 있어도 안내가 들리게).
MIC=$("$VENV/bin/python" -c "import sounddevice as sd; print(next((d['name'] for d in sd.query_devices() if d['max_input_channels']>0 and 'brio' in d['name'].lower()), ''))" 2>/dev/null || true)
SPK=$(say -a '?' 2>/dev/null | grep -iE 'mac ?mini' | grep -iE 'speaker|스피커' | head -1 | sed -E 's/^ *[0-9]+ +//' || true)
"$VENV/bin/python" - "$HOME/.config/desk/config.toml" "$MIC" "$SPK" <<'PY'
import re, sys
path, mic, spk = sys.argv[1:4]
s = open(path, encoding="utf-8").read()
def put(section, key, val):
    global s
    m = re.search(rf"(^\[{section}\][^\[]*?^{key} = )\"[^\"]*\"", s, flags=re.M | re.S)
    if m and val:
        s = s[:m.start()] + m.group(1) + '"' + val.replace('"', '') + '"' + s[m.end():]
put("audio", "device", mic.split(",")[0].strip())
put("tts", "device", spk.strip())
open(path, "w", encoding="utf-8").write(s)
PY
echo "  마이크: ${MIC:-시스템 기본}  ·  스피커: ${SPK:-시스템 기본}"

say_ "받아쓰기 모델 내려받기 (처음 한 번, 1.5GB 안팎)"
( cd "$DESK" && "$VENV/bin/python" -c "from desk.stt import WhisperSTT; from desk import config; c=config.load()['stt']; WhisperSTT(c['model'], c['language']).warmup(); print('모델 준비됨')" ) || echo "※ 모델 준비 실패 — 네트워크 확인 뒤 다시"
say_ "목소리 모델 내려받기 (처음 한 번, 380MB 안팎)"
( cd "$DESK" && "$VENV/bin/python" -c "from supertonic import TTS; from desk import config; TTS(model=config.load()['tts']['model']); print('목소리 준비됨')" ) || echo "※ 목소리 모델 실패 — 그동안은 say 로 말함"

say_ "얼굴 인증 모델 (처음 한 번, 37MB · 등록 데이터는 ~/.local/share/desk/face — 다시 깔아도 남음)"
( cd "$DESK" && "$VENV/bin/python" -m desk face models ) || echo "※ 얼굴 모델 준비 실패 — 네트워크 확인 뒤 다시(그동안은 박수만으로 깨어남)"

say_ "전원: 맥은 안 자고, 화면만 꺼짐"
sudo pmset -a sleep 0 disksleep 0 displaysleep 30 powernap 0 autorestart 1 womp 1 >/dev/null || true
echo "  시스템 잠자기 끔 · 화면은 30분 안전망(평소엔 deskd 가 끔) · 정전 뒤 자동 켜짐"

say_ "비서 폴더 $ASSIST"
cp "$HERE/assistant/CLAUDE.md" "$ASSIST/CLAUDE.md"
touch "$ASSIST/memory.md"
mkdir -p "$ASSIST/.claude/hooks"
GUARD="$HERE/../seed/.claude/hooks/guard.js"
if [ -f "$GUARD" ]; then
  cp "$GUARD" "$ASSIST/.claude/hooks/guard.js"
  # 권한 규칙은 덮어쓰지 않고 합침 — 사람이(말로) 고친 settings.json 을 다시 설치해도 지우지 않게
  SET=$(cd "$DESK" && "$VENV/bin/python" -m desk.settings_merge "$HERE/../seed/.claude/settings.json" "$ASSIST/.claude/settings.json")
  echo "  공장 훅(guard.js) 적용 · 권한 규칙: $SET"
fi
[ -d "$ASSIST/.git" ] || git -C "$ASSIST" init -q

say_ "deskctl 명령"
cat > "$HOME/.local/bin/deskctl" <<SH
#!/bin/bash
cd "$DESK" && exec "$VENV/bin/python" -m desk ctl "\$@"
SH
chmod +x "$HOME/.local/bin/deskctl"
grep -q '.local/bin' "$HOME/.zprofile" 2>/dev/null || echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.zprofile"

say_ "마이크 권한 받을 실행 파일 (deskd)"
# launchd 가 파이썬을 바로 띄우면 권한 창이 안 뜨고 소리가 0 만 들어옵니다(Python.app 에 마이크 사용 이유가 없음).
# 사용 이유를 품은 작은 실행 파일이 파이썬을 띄우게 합니다. 소스가 그대로면 다시 만들지 않습니다 —
# 다시 만들면 macOS 가 새 프로그램으로 보고 권한을 또 묻습니다.
LAUNCHER="$HOME/.local/libexec/deskd"; mkdir -p "$(dirname "$LAUNCHER")"
SRC_SUM=$(cat "$HERE/launcher/deskd.c" "$HERE/launcher/Info.plist" | shasum | cut -c1-16)
if [ ! -x "$LAUNCHER" ] || [ "$(cat "$LAUNCHER.sum" 2>/dev/null)" != "$SRC_SUM" ]; then
  if xcrun clang -O2 -o "$LAUNCHER" "$HERE/launcher/deskd.c" -sectcreate __TEXT __info_plist "$HERE/launcher/Info.plist" \
     && codesign -s - -f -i lab.deskd "$LAUNCHER" >/dev/null 2>&1; then
    echo "$SRC_SUM" > "$LAUNCHER.sum"; echo "  만듦: $LAUNCHER"
  else
    rm -f "$LAUNCHER"; echo "  ※ 못 만듦(개발자 도구 없음?) — 파이썬을 바로 띄웁니다. 마이크가 0 이면: xcode-select --install 뒤 다시"
  fi
else
  echo "  그대로 씀: $LAUNCHER"
fi
RUN_ARGS="<string>$VENV/bin/python</string><string>-m</string><string>desk</string><string>run</string>"
[ -x "$LAUNCHER" ] && RUN_ARGS="<string>$LAUNCHER</string>$RUN_ARGS"

say_ "로그인할 때 자동 실행 (launchd)"
PL="$HOME/Library/LaunchAgents/lab.deskd.plist"
cat > "$PL" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>lab.deskd</string>
  <key>ProgramArguments</key><array>$RUN_ARGS</array>
  <key>WorkingDirectory</key><string>$DESK</string>
  <key>EnvironmentVariables</key><dict>
    <key>PATH</key><string>$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    <key>PYTHONUNBUFFERED</key><string>1</string>
  </dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ProcessType</key><string>Interactive</string>
  <key>StandardOutPath</key><string>$HOME/Library/Logs/deskd.log</string>
  <key>StandardErrorPath</key><string>$HOME/Library/Logs/deskd.log</string>
</dict></plist>
PLIST
launchctl bootout "gui/$(id -u)/lab.deskd" 2>/dev/null || true
# bootout 은 끝날 때까지 기다려 주지 않습니다 — 옛 것이 다 내려가기 전에 bootstrap 하면 "5: Input/output error"
for _ in $(seq 20); do launchctl print "gui/$(id -u)/lab.deskd" >/dev/null 2>&1 || break; sleep 0.5; done
launchctl bootstrap "gui/$(id -u)" "$PL" 2>/dev/null || { sleep 2; launchctl bootstrap "gui/$(id -u)" "$PL"; }
echo "  시작됨 — 로그: tail -f ~/Library/Logs/deskd.log"
echo "  → 곧 「deskd 이(가) 마이크에 접근하려고 합니다」 창이 뜨면 【허용】"

say_ "점검"
( cd "$DESK" && "$VENV/bin/python" -m unittest discover -s tests -t . -q ) && echo "  시험 통과"
cat <<TXT

남은 것 (한 번만, 사람이):
  1. 「deskd」 · 「터미널」 이 마이크를 쓰겠다고 하면 허용.
     놓쳤으면: 설정 → 개인정보 보호 및 보안 → 마이크 → deskd 켜기 (selftest 가 막혔는지 알려 줌).
  2. (선택) 설정 → 손쉬운 사용 → 읽기 및 말하기 → 시스템 음성 → 한국어 Yuna (프리미엄) 내려받기 — 예비 목소리.
  3. 설정 → 잠금 화면 → 디스플레이가 꺼진 후 암호 요구 → 안 함.  (키보드 없이 쓰려면 필요)
  4. 방에서:  cd $DESK && $VENV/bin/python -m desk calibrate   → 박수 몇 번 쳐서 ★ 가 뜨는지.
  5.          $VENV/bin/python -m desk selftest
  6. 얼굴 등록: 화면이 켜진 채 웹캠을 보고  deskctl enroll   → 「deskd 카메라 접근」 창이 뜨면 허용 뒤 한 번 더.
     그다음부터 박수 → "얼굴 인증해 주세요" → 주인이면 켜짐. 끄려면 config [face] enabled = false
그다음 화면이 꺼지면(또는 deskctl sleep), 박수 두 번.
TXT
