#!/bin/bash
# 비서 앱 APK — Gradle 없이 aapt2 · javac · d8 · apksigner. 열쇠는 맥의 ~/.config/desk/phone_token 을 빌드 때 넣음(저장소엔 안 들어감)
set -euo pipefail
cd "$(dirname "$0")"
export JAVA_HOME=${JAVA_HOME:-/opt/homebrew/opt/openjdk@17}
SDK=${ANDROID_HOME:-/opt/homebrew/share/android-commandlinetools}
BT=$SDK/build-tools/34.0.0
JAR=$SDK/platforms/android-34/android.jar
BASE=${DESK_PHONE_BASE:-http://100.83.32.36:7071}
TOKEN=$(tr -d '\n' < ~/.config/desk/phone_token)
KS=~/.config/desk/phone-app.keystore
rm -rf build && mkdir -p build/gen/lab/desk/phone build/classes build/flat
cat > build/gen/lab/desk/phone/Secrets.java <<J
package lab.desk.phone;
final class Secrets { static final String BASE = "$BASE"; static final String TOKEN = "$TOKEN"; }
J
$BT/aapt2 compile --dir res -o build/flat
$BT/aapt2 link -o build/base.apk -I $JAR --manifest AndroidManifest.xml --java build/gen build/flat/*.flat
$JAVA_HOME/bin/javac -source 11 -target 11 -encoding UTF-8 -classpath $JAR -d build/classes \
  $(find src build/gen -name '*.java') 2>&1 | grep -v "bootstrap classpath" || true
$BT/d8 --lib $JAR --min-api 26 --output build $(find build/classes -name '*.class')
(cd build && zip -q base.apk classes.dex)
$BT/zipalign -f 4 build/base.apk build/aligned.apk
if [ ! -f $KS ]; then
  $JAVA_HOME/bin/keytool -genkeypair -keystore $KS -storepass desk-phone -keypass desk-phone -alias desk \
    -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=desk phone" >/dev/null
  chmod 600 $KS
fi
$BT/apksigner sign --ks $KS --ks-pass pass:desk-phone --key-pass pass:desk-phone --out build/desk-phone.apk build/aligned.apk
$BT/apksigner verify build/desk-phone.apk
mkdir -p ~/.local/share/desk && cp build/desk-phone.apk ~/.local/share/desk/desk-phone.apk
ls -la ~/.local/share/desk/desk-phone.apk
