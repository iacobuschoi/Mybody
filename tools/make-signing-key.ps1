# =============================================================================
# make-signing-key.ps1 — 앱 서명 열쇠를 만들고 깃허브에 넣습니다 (윈도우)
#
# 파워셸을 열고 저장소 폴더에서:
#   powershell -ExecutionPolicy Bypass -File tools\make-signing-key.ps1
#
# **이 파일은 돌려 보지 못했습니다.** 개발하는 곳에 파워셸이 없습니다.
# 깃을 깔면 같이 오는 Git Bash 에서 옆의 make-signing-key.sh 를 쓰는 쪽이
# 확실합니다 — 그건 끝까지 돌려 보고 결과를 확인했습니다.
#
# 왜 내 컴퓨터에서 하나: 이 열쇠는 **앱의 신분증**입니다. 잃어버리면 같은
# 앱의 업데이트를 영영 못 만들고, 남이 가지면 내 앱의 업데이트인 척하는
# 앱을 만들 수 있습니다. 그래서 만든 자리에서 바로 깃허브 금고로 넣고,
# 중간에 아무 데도 안 거칩니다.
# =============================================================================
$ErrorActionPreference = 'Stop'

$Out   = Join-Path $HOME 'mybody-signing-key'
$Jks   = Join-Path $Out  'mybody.jks'
$Alias = 'mybody'

if (Test-Path $Jks) {
  Write-Host "이미 있습니다: $Jks"
  Write-Host "새로 만들면 예전 열쇠로 서명한 앱들과 안 맞습니다. 멈춥니다."
  exit 1
}

if (-not (Get-Command keytool -ErrorAction SilentlyContinue)) {
  Write-Host "자바가 없습니다. https://adoptium.net/ 에서 17 을 받아 깔고 다시 해 주세요."
  Write-Host "(안드로이드 스튜디오가 깔려 있으면 이미 있을 수도 있습니다.)"
  exit 1
}

New-Item -ItemType Directory -Force -Path $Out | Out-Null

# 비밀번호는 직접 만듭니다. 외울 필요 없습니다 — 파일에 적어 둡니다.
$bytes = New-Object byte[] 30
[System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
$Pw = ([Convert]::ToBase64String($bytes) -replace '[^A-Za-z0-9]', '').Substring(0, 40)

keytool -genkeypair -v `
  -keystore $Jks -storetype PKCS12 `
  -keyalg RSA -keysize 4096 -validity 10000 `
  -alias $Alias `
  -storepass $Pw -keypass $Pw `
  -dname "CN=Mybody, O=Mybody, C=KR" | Out-Null

$b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($Jks))
$b64Path = Join-Path $Out 'base64.txt'
[IO.File]::WriteAllText($b64Path, $b64)

@"
Mybody 앱 서명 열쇠
===================

이 폴더를 **지우지 마세요.** 지우면 같은 앱의 업데이트를 영영 못 만듭니다.
클라우드 드라이브나 USB 에 한 벌 복사해 두세요.

파일      : $Jks
별칭      : $Alias
비밀번호  : $Pw

깃허브에 넣는 값 (Settings → Secrets and variables → Actions):
  ANDROID_KEYSTORE_BASE64  = 이 폴더의 base64.txt 내용 전부
  ANDROID_STORE_PASSWORD   = 위 비밀번호
  ANDROID_KEY_PASSWORD     = 위 비밀번호
  ANDROID_KEY_ALIAS        = $Alias
"@ | Set-Content -Path (Join-Path $Out '열쇠-정보.txt') -Encoding UTF8

Write-Host "열쇠를 만들었습니다: $Jks"
Write-Host "지문:"
(keytool -list -v -keystore $Jks -storepass $Pw | Select-String 'SHA256:' |
  Select-Object -First 1) -replace '^\s*', '  ' | Write-Host
Write-Host ""

$gh = Get-Command gh -ErrorAction SilentlyContinue
if ($gh) { gh auth status 2>$null | Out-Null }
if ($gh -and $LASTEXITCODE -eq 0) {
  Write-Host "깃허브에 넣는 중…"
  # **파이프로 넘기지 않습니다.** 파이프는 끝에 줄바꿈을 붙이는데, 그게
  # 비밀번호에 딸려 들어가면 빌드가 "keystore password was incorrect" 로
  # 죽습니다. --body 는 준 값을 그대로 넣습니다.
  gh secret set ANDROID_KEYSTORE_BASE64 --body $b64
  gh secret set ANDROID_STORE_PASSWORD  --body $Pw
  gh secret set ANDROID_KEY_PASSWORD    --body $Pw
  gh secret set ANDROID_KEY_ALIAS       --body $Alias
  Write-Host ""
  Write-Host "끝났습니다. 이제 Actions 에서 한 번 돌리면 이 열쇠로 서명됩니다."
  Write-Host "  gh workflow run apk.yml"
} else {
  Write-Host "gh 명령이 없어서 자동으로는 못 넣었습니다. 두 줄만 해 주세요:"
  Write-Host ""
  Write-Host "  1) 이 주소를 엽니다:"
  Write-Host "     https://github.com/iacobuschoi/Mybody/settings/secrets/actions"
  Write-Host "  2) New repository secret 으로 네 개를 넣습니다."
  Write-Host "     무슨 값을 넣는지는 여기 적혀 있습니다:"
  Write-Host "     $(Join-Path $Out '열쇠-정보.txt')"
  Start-Process "https://github.com/iacobuschoi/Mybody/settings/secrets/actions"
  Start-Process explorer.exe $Out
}
Write-Host ""
Write-Host "이 폴더를 어딘가에 복사해 두세요. 잃어버리면 못 되살립니다:"
Write-Host "  $Out"
