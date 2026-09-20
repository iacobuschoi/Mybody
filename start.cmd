@echo off
rem 윈도우에서 더블클릭으로 띄우기.
rem 끌 때는 이 창에서 Ctrl+C, 또는 창을 닫으면 됩니다.
cd /d "%~dp0"

where node >nul 2>nul
if errorlevel 1 (
  echo.
  echo Node.js 가 없습니다.
  echo   https://nodejs.org 에서 LTS 를 받아 깔고, 이 파일을 다시 더블클릭하세요.
  echo.
  pause
  exit /b 1
)

node tools\serve.js

echo.
echo 서버를 껐습니다. 아무 키나 누르면 이 창이 닫힙니다.
pause >nul
