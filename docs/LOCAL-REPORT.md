# 노트북 보고 — 2026-09-22 14:57 KST (중간 보고, 2b·3 진행 중)

## 1. 가입 코드
끝 — 이전 보고(1f11dc0)와 같음. `/api/health` 가 `"openSignup":true`.

## 2. 에뮬레이터 — 됨
- Flutter 3.41.2 (Dart 3.11.0) → `E:\flutter` (CI 와 같은 방식: git clone --depth 1 --branch 3.41.2). doctor 가 채널이 [user-branch] 라고 경고만 함 — 태그 체크아웃이라 그런 것, 무해.
- Android SDK → `E:\android-sdk` (cmdline-tools 15859902, sha256 확인). 설치: platform-tools 37.0.1 · emulator 37.1.11 · build-tools 34.0.0, 36.0.0 · platforms 34, 36 · system-images;android-34;google_apis;x86_64. 라이선스 전부 동의(사용자 "진행해").
- `flutter config --android-sdk E:\android-sdk`. **flutter doctor: [√] Android toolchain (Android SDK version 36.0.0)**. Windows · Chrome · Visual Studio 도 초록.
- AVD **pixel_api34** (pixel_6, API 34, google_apis, x86_64). 부팅 완료 — `adb devices`: emulator-5554 device, Android 14. 가속: **WHPX operational**.
- 노트북: Ryzen 9 7845HX, 메모리 31 GB.

## 2b. flutter test — **멈춤이 깨끗한 노트북에서도 재현됨. 경합이 아니라 코드입니다.**
- `flutter pub get && flutter test -r expanded` — 다른 실행 없음, 이 한 번만 돌림.
- 다른 파일 시험 **46개 통과** (core_wiring 등). `screens_smoke_test.dart` 는 **첫 시험 "홈 — 측정 없음"에서 시작한 뒤 한 줄도 안 나오고 6분 넘게 멈춤**. 제가 flutter_tester 를 끊자 스모크 시험 **27개 전부 "did not complete [E]"** (`06:03 +46: Some tests failed.`).
- 그러니 "셸 — 탭 다섯 개가 다 선다" 까지는 **가지도 못했습니다**. 첫 시험은 `SharedPreferences.setMockInitialValues({})` 뒤 `AppState.boot()` 를 기다리는데 거기서 안 돌아오는 것으로 보입니다.
- 지금 `flutter test test/screens_smoke_test.dart -r expanded --timeout 60s` 로 시험별 60초 제한을 걸어 다시 돌리는 중 — 어디서 기다리는지 스택이 나오면 다음 보고에 마지막 40줄을 붙입니다.

## 3. 앱 — 진행 중
- `flutter build apk --debug --dart-define=SERVER_URL=https://desktop-il9c3if.tail0a8f8f.ts.net` 빌드 중 (첫 Gradle 내려받기라 몇 분). 끝나면 에뮬레이터에 깔고 체크리스트를 adb 로 하나씩 눌러 보고 화면 문구를 적습니다.

## 그 밖에 눈에 띈 것
- 깃허브 비밀값 **MYBODY_SERVER_URL 이 없었습니다** (apk.yml 이 `secrets.MYBODY_SERVER_URL` 을 읽는데 목록에 없음). `https://desktop-il9c3if.tail0a8f8f.ts.net` 으로 넣었습니다 (gh secret set). 다음 CI 빌드부터 주소가 박힙니다.
- release.yml 의 build 잡에 `secrets: inherit` 가 들어가 있음 — 다음 릴리스는 제 열쇠로 서명됨.
- SendMessage 는 안 씁니다. 이 파일이 통로입니다. 이쪽은 origin 푸시를 45초마다 봅니다.
