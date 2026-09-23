@echo off
setlocal
rem =====================================================================
rem pepk.cmd — 내 서명 열쇠(mybody.jks)를 구글에 올릴 수 있게 암호화합니다
rem
rem 콘솔 「Play 앱 서명 → 앱 서명 키 변경 → Java 키 저장소에서 내보내기」
rem 화면에서 받은 pepk.jar 와 encryption_public_key.pem 을 이 폴더에 넣고
rem 더블클릭. 비밀번호는 %USERPROFILE%\mybody-signing-key\KEY-INFO.txt.
rem 만들어지는 mybody-pepk.zip 을 그 화면에 올립니다. 열쇠 원본은 그대로.
rem =====================================================================
set "KS=%USERPROFILE%\mybody-signing-key\mybody.jks"
set "OUT=%~dp0mybody-pepk.zip"
set "JAR=%~dp0pepk.jar"
set "PEM=%~dp0encryption_public_key.pem"
set "HEX=%~dp0encryption-key.txt"

if not exist "%KS%" (
  echo 열쇠가 없습니다: %KS%
  echo 노트북에서 만든 mybody.jks 가 있는 컴퓨터에서 하세요.
  pause & exit /b 1
)
if not exist "%JAR%" (
  echo pepk.jar 가 이 폴더에 없습니다.
  echo 콘솔의 Play 앱 서명 화면에서 받아 이 폴더에 넣고 다시 하세요.
  pause & exit /b 1
)
where java >nul 2>nul || (
  echo 자바가 없습니다. https://adoptium.net/ 에서 17 을 받아 깔고 다시 하세요.
  pause & exit /b 1
)

if exist "%PEM%" (
  echo 공개키 파일로 암호화합니다...
  java -jar "%JAR%" --keystore="%KS%" --alias=mybody --output="%OUT%" --include-cert --rsa-aes-encryption --encryption-key-path="%PEM%"
) else if exist "%HEX%" (
  set /p KEYHEX=<"%HEX%"
  echo 16진수 키로 암호화합니다...
  java -jar "%JAR%" --keystore="%KS%" --alias=mybody --output="%OUT%" --include-cert --encryptionkey=%KEYHEX%
) else (
  echo 암호화 키가 없습니다. 콘솔 화면의 encryption_public_key.pem 을 이 폴더에 넣거나,
  echo 화면이 긴 16진수 문자열을 주면 그것을 encryption-key.txt 로 저장하세요.
  pause & exit /b 1
)

if errorlevel 1 (
  echo.
  echo 실패했습니다. 비밀번호는 KEY-INFO.txt 에 있습니다 ^(저장소 비밀번호 = 키 비밀번호^).
  echo 'RSA/NONE/OAEP' 오류면 자바 21 로 다시 해 보세요.
  pause & exit /b 1
)
echo.
echo 만들어졌습니다: %OUT%
echo 콘솔 화면에 이 파일을 올리고 저장하세요. 열쇠 원본은 그대로 둡니다.
pause
