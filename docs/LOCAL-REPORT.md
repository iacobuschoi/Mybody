# 노트북 보고 —  (2b 진단 완료 · 3 진행 중)

## 1. 가입 코드
끝 — 이전 보고(1f11dc0)와 같음. `/api/health` 가 `"openSignup":true`.

## 2. 에뮬레이터 — 됨
- Flutter 3.41.2 (Dart 3.11.0) → `E:\flutter` (CI 와 같은 방식: git clone --depth 1 --branch 3.41.2). doctor 가 채널이 [user-branch] 라고 경고만 함 — 태그 체크아웃이라 그런 것, 무해.
- Android SDK → `E:\android-sdk` (cmdline-tools 15859902, sha256 확인). 설치: platform-tools 37.0.1 · emulator 37.1.11 · build-tools 34.0.0, 36.0.0 · platforms 34, 36 · system-images;android-34;google_apis;x86_64. 라이선스 전부 동의(사용자 "진행해").
- `flutter config --android-sdk E:\android-sdk`. **flutter doctor: [√] Android toolchain (Android SDK version 36.0.0)**. Windows · Chrome · Visual Studio 도 초록.
- AVD **pixel_api34** (pixel_6, API 34, google_apis, x86_64). 부팅 완료 — `adb devices`: emulator-5554 device, Android 14. 가속: **WHPX operational**.
- 노트북: Ryzen 9 7845HX, 메모리 31 GB.

## 2b. flutter test — **멈춤 재현됨. 원인은 코드이고, 어디서 멈추는지도 찾았습니다.**

**재현.** `flutter pub get && flutter test -r expanded` 를 깨끗한 노트북에서 한 번만 돌림(동시 실행 없음).
다른 파일 시험 **46개 통과**. `screens_smoke_test.dart` 는 **첫 시험 "홈 — 측정 없음"에서 시작한 뒤 한 줄도 안 나오고 6분 넘게 멈춤**.
flutter_tester 를 끊자 스모크 시험 **27개 전부 "did not complete [E]"** (`06:03 +46: Some tests failed.`).
"셸 — 탭 다섯 개가 다 선다" 까지는 **가지도 못했습니다** — 그 시험이 문제가 아니라 파일의 첫 시험부터 멈춥니다.
`--timeout 60s` 로 다시 돌려도 안 터짐(flutter_test 가 자체 10분 제한으로 덮어씀) — 스택은 못 받았고, 대신 코드로 짚었습니다.

**어디서.** `AppState.boot()` → `FilePhotos.open()` → `await getApplicationDocumentsDirectory().timeout(3s)` (lib/src/photos.dart 32행).

**왜 시험에서만.**
- `testWidgets` 는 **가짜 시간(FakeAsync)** 안에서 돕니다. 플러그인 채널(path_provider) 응답은 진짜 비동기 이벤트라 `tester.runAsync` 밖에서는 **영영 안 옵니다**. 그래서 await 가 안 끝납니다.
- `.timeout(3초)` 도 **안 터집니다** — 가짜 시계는 `pump`/`elapse` 로만 움직이는데, 시험은 `pumpWidget` 전에 `await AppState.boot()` 을 하고 있어서 시계가 멈춰 있습니다. 결국 둘 다 기다리기만 합니다.
- `core_wiring_test.dart` 도 `boot()` 을 부르지만 통과한 이유: 그건 `test()`(진짜 시간)라 3초 뒤 타임아웃이 터지고 `try/catch` 가 삼켜서 사진 없이 갑니다.
- 그러니 실기기에서는 3초 타임아웃이 제대로 작동할 것이고, **시험만** 걸립니다. 클라우드에서 본 "did not complete" 도 경합이 아니라 이것입니다.

**고치는 길(시험 쪽, 코드는 그쪽이).** 셋 중 하나:
1. 시험에서 path_provider 를 가짜로: `PathProviderPlatform.instance = 임시폴더를 돌려주는 가짜` 를 `setUp` 에서 (path_provider_platform_interface 의 `PathProviderPlatform` 상속, `getApplicationDocumentsPath` 만 구현). 제일 정석.
2. 시험에서 `await t.runAsync(() => AppState.boot())` 로 감싸기 — 진짜 시간이 흘러 3초 뒤 타임아웃이 터지고 사진 없이 부팅. 시험마다 3초씩 느려짐.
3. `AppState.boot({PhotoHost? photos})` 처럼 주입 가능하게 하고 시험은 메모리 구현을 넘김.

## 3. 앱 — 진행 중
- `flutter build apk --debug --dart-define=SERVER_URL=https://desktop-il9c3if.tail0a8f8f.ts.net` 빌드 중 (첫 Gradle 내려받기라 몇 분). 끝나면 에뮬레이터에 깔고 체크리스트를 adb 로 하나씩 눌러 보고 화면 문구를 적습니다.

## 그 밖에 눈에 띈 것
- 깃허브 비밀값 **MYBODY_SERVER_URL 이 없었습니다** (apk.yml 이 `secrets.MYBODY_SERVER_URL` 을 읽는데 목록에 없음). `https://desktop-il9c3if.tail0a8f8f.ts.net` 으로 넣었습니다 (gh secret set). 다음 CI 빌드부터 주소가 박힙니다.
- release.yml 의 build 잡에 `secrets: inherit` 가 들어가 있음 — 다음 릴리스는 제 열쇠로 서명됨.
- SendMessage 는 안 씁니다. 이 파일이 통로입니다. 이쪽은 origin 푸시를 45초마다 봅니다.
