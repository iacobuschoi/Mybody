#!/usr/bin/env sh
# =============================================================================
# make-signing-key.sh — 앱 서명 열쇠를 만들고 깃허브에 넣습니다 (맥 · 리눅스)
#
#   sh tools/make-signing-key.sh
#
# 윈도우면 옆에 있는 make-signing-key.ps1 을 쓰세요.
#
# 왜 이걸 내 컴퓨터에서 하나: 이 열쇠는 **앱의 신분증**입니다. 잃어버리면
# 같은 앱의 업데이트를 영영 못 만들고, 남이 가지면 내 앱의 업데이트인 척하는
# 앱을 만들 수 있습니다. 그래서 만든 자리에서 바로 깃허브 금고로 넣고,
# 중간에 아무 데도 안 거칩니다.
# =============================================================================
set -e

OUT="$HOME/mybody-signing-key"
JKS="$OUT/mybody.jks"
ALIAS=mybody

if [ -e "$JKS" ]; then
  echo "이미 있습니다: $JKS"
  echo "새로 만들면 예전 열쇠로 서명한 앱들과 안 맞습니다. 멈춥니다."
  exit 1
fi

command -v keytool >/dev/null 2>&1 || {
  echo "자바가 없습니다. https://adoptium.net/ 에서 17 을 받아 깔고 다시 해 주세요."
  exit 1
}

mkdir -p "$OUT"
chmod 700 "$OUT"

# 비밀번호는 **직접 만듭니다.** 사람이 정한 비밀번호를 쓰면 대개 다른 데서
# 쓰던 걸 씁니다. 어차피 외울 필요가 없는 값입니다 — 파일에 적어 둡니다.
PW=$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 40)

keytool -genkeypair -v \
  -keystore "$JKS" -storetype PKCS12 \
  -keyalg RSA -keysize 4096 -validity 10000 \
  -alias "$ALIAS" \
  -storepass "$PW" -keypass "$PW" \
  -dname "CN=Mybody, O=Mybody, C=KR" >/dev/null

cat > "$OUT/열쇠-정보.txt" <<TXT
Mybody 앱 서명 열쇠
===================

이 폴더를 **지우지 마세요.** 지우면 같은 앱의 업데이트를 영영 못 만듭니다.
클라우드 드라이브나 USB 에 한 벌 복사해 두세요.

파일      : $JKS
별칭      : $ALIAS
비밀번호  : $PW

깃허브에 넣는 값 (Settings → Secrets and variables → Actions):
  ANDROID_KEYSTORE_BASE64  = 이 폴더의 base64.txt 내용 전부
  ANDROID_STORE_PASSWORD   = 위 비밀번호
  ANDROID_KEY_PASSWORD     = 위 비밀번호
  ANDROID_KEY_ALIAS        = $ALIAS
TXT
chmod 600 "$OUT/열쇠-정보.txt"

base64 < "$JKS" | tr -d '\n' > "$OUT/base64.txt"
chmod 600 "$OUT/base64.txt"

echo "열쇠를 만들었습니다: $JKS"
echo "지문:"
keytool -list -v -keystore "$JKS" -storepass "$PW" 2>/dev/null \
  | grep -i "SHA256:" | head -1 | sed 's/^/  /'
echo

# gh 가 있으면 여기서 바로 넣습니다. 그러면 손으로 할 일이 없습니다.
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  echo "깃허브에 넣는 중…"
  gh secret set ANDROID_KEYSTORE_BASE64 < "$OUT/base64.txt"
  printf '%s' "$PW"    | gh secret set ANDROID_STORE_PASSWORD
  printf '%s' "$PW"    | gh secret set ANDROID_KEY_PASSWORD
  printf '%s' "$ALIAS" | gh secret set ANDROID_KEY_ALIAS
  echo
  echo "끝났습니다. 이제 Actions 에서 한 번 돌리면 이 열쇠로 서명됩니다."
  echo "  gh workflow run apk.yml"
else
  echo "gh 명령이 없어서 자동으로는 못 넣었습니다. 두 줄만 해 주세요:"
  echo
  echo "  1) 이 주소를 엽니다:"
  echo "     https://github.com/iacobuschoi/Mybody/settings/secrets/actions"
  echo "  2) New repository secret 으로 네 개를 넣습니다."
  echo "     무슨 값을 넣는지는 여기 적혀 있습니다:"
  echo "     $OUT/열쇠-정보.txt"
fi
echo
echo "이 폴더를 어딘가에 복사해 두세요. 잃어버리면 못 되살립니다:"
echo "  $OUT"
