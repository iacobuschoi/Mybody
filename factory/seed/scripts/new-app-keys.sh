#!/usr/bin/env bash
# =============================================================================
# scripts/new-app-keys.sh <앱 slug> — 앱 하나의 안드로이드 업로드 열쇠를 만들고 저장소 시크릿에 넣습니다.
#
# 맥 미니에서 Claude 세션이 실행합니다. 열쇠 내용은 화면에 찍지 않고, 사본은 ~/app-keys/<앱>/ 에만 둡니다.
# (훅 guard.js 는 Claude 가 직접 `gh secret set` · 열쇠 파일 읽기를 하는 것을 막습니다. 이 스크립트는 검토된
#  절차라 스크립트 이름으로만 불립니다.)
#
# 플레이 앱 서명을 쓰므로 이 열쇠는 "업로드 열쇠" 입니다 — 잃어도 구글 지원으로 재설정할 수 있지만 며칠 걸립니다.
# ~/app-keys 는 주인이 비밀번호 관리자에 한 번 백업하세요.
# =============================================================================
set -euo pipefail
APP="${1:?앱 slug}"; [[ "$APP" =~ ^[a-z][a-z0-9]*$ ]] || { echo "slug 는 영문 소문자·숫자"; exit 1; }
REPO="${FACTORY_REPO:-$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)}"
[ -n "$REPO" ] || { echo "저장소를 모르겠습니다 — app-factory 안에서 실행하거나 FACTORY_REPO=owner/app-factory"; exit 1; }
D="$HOME/app-keys/$APP"; U=$(echo "$APP" | tr a-z A-Z)
if [ -f "$D/upload.jks" ]; then echo "이미 있습니다: $D/upload.jks — 시크릿만 다시 넣으려면 REUSE=1"; [ "${REUSE:-}" = 1 ] || exit 1; fi
mkdir -p "$D"; chmod 700 "$HOME/app-keys" "$D"
if [ ! -f "$D/upload.jks" ]; then
  SP=$(openssl rand -hex 20); KP=$(openssl rand -hex 20)
  keytool -genkeypair -v -keystore "$D/upload.jks" -alias upload -keyalg RSA -keysize 2048 -validity 10000 \
    -storepass "$SP" -keypass "$KP" -dname "CN=$APP, O=app-factory, C=KR" >/dev/null 2>&1
  printf 'storePassword=%s\nkeyPassword=%s\nalias=upload\n' "$SP" "$KP" > "$D/KEY-INFO.txt"; chmod 600 "$D/KEY-INFO.txt"
fi
SP=$(sed -n 's/^storePassword=//p' "$D/KEY-INFO.txt"); KP=$(sed -n 's/^keyPassword=//p' "$D/KEY-INFO.txt")
FP=$(keytool -list -v -keystore "$D/upload.jks" -alias upload -storepass "$SP" 2>/dev/null | grep -m1 SHA256 | awk '{print $2}')
base64 < "$D/upload.jks" | tr -d '\n' | gh secret set "${U}_KEYSTORE_B64" -R "$REPO"
printf '%s' "$SP" | gh secret set "${U}_KEYSTORE_PW" -R "$REPO"
printf '%s' "$KP" | gh secret set "${U}_KEY_PW" -R "$REPO"
printf 'upload'  | gh secret set "${U}_KEY_ALIAS" -R "$REPO"
printf '%s' "$FP" | gh secret set "${U}_UPLOAD_SHA256" -R "$REPO"
echo "$APP: 업로드 열쇠 준비됨 · 지문 $FP · 시크릿 ${U}_KEYSTORE_B64 외 4개 → $REPO"
echo "$FP" > "$D/SHA256.txt"
