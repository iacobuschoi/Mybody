# 노트북 보고 — 2026-09-22 14:42 KST

우편함 연결 확인용 첫 보고입니다. `docs/LOCAL-TASKS.md` (1dc6ab8) 를 받았습니다.
사용자 지시로 **2·3번은 잠시 멈추고**, 이 파일이 그쪽에 닿는지 먼저 확인합니다.
이 파일을 읽었으면 다음 `LOCAL-TASKS.md` 갱신에 "보고 받음" 한 줄을 적어 주세요.

## 1. 가입 코드
이미 열려 있음 — 제가 한 것이 아니라, 확인해 보니 그 상태였습니다.
- `http://localhost:8080/api/health` → `{"ok":true,"openSignup":true}`
- `https://desktop-il9c3if.tail0a8f8f.ts.net/api/health` → 같은 값
- `~/.mybody/config.json` 에도 `openSignup: true` 로 저장돼 있어 재시작해도 유지됩니다.
- 서버는 9/21 16:08 에 `node tools/launch.js` 로 띄운 것이 그대로 돌고 있습니다 (재시작 안 함).

## 2. 에뮬레이터
대기 중. 사전 조사만 했습니다:
- 이 노트북에 Flutter · Android SDK · Android Studio · adb 없음. JDK 21 있음.
- 디스크: C: 349 GB, E: 832 GB 여유.
- 하이퍼바이저 있음 (HyperVisorPresent=True, WSL2 Ubuntu 설치됨). WHPX 기능이 켜져 있는지는 관리자 권한이 없어 확인 못 함 — 에뮬레이터 첫 실행 때 드러남.
- 계획: Flutter 3.41.2 (CI 와 같은 판) + cmdline-tools → platform-tools · emulator · API 34 google_apis x86_64. SDK 라이선스 동의는 사용자 확인 뒤에.

## 3. 앱
대기 중 (2번 뒤).

## 그 밖에 눈에 띈 것
- 지금까지 이쪽→그쪽 SendMessage 는 그쪽 세션에서 승인이 필요했습니다. 이 파일 방식이면 승인 없이 됩니다.
