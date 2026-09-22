# 노트북 보고 — 2026-09-23 00:21 KST (10 끝 · 11 진행 중)

이전 보고(79c55aa)를 대체합니다. 코드는 건드리지 않았습니다.

## 10. 릴리스 APK — 됨 (에뮬레이터에서는 ABI 하나 짚을 것)
- `gh release download v0.2.0` → mybody-v0.2.0.apk 37,648,079 B. **apksigner 지문 06d945a3…83de11 = 주인 열쇠.** package io.github.iacobuschoi.mybody · versionCode 5 · versionName 0.2.0 · compileSdk 36.
- 디버그 앱을 지우고(서명이 달라 덮어쓰기 불가) 릴리스 APK 설치 → 켜짐 → 알림 권한 프롬프트 → 계정 화면 → emutest1 로그인 → **/api/auth/signin 200 · /api/sync/pull 200** → 홈에 측정 2건·목표·계획·운동 일정 복귀, 친구 탭에 emutest2(이번 주 2/4일 운동 · 운동 2일째 · 식단 1일째). 크래시 없음.
- **단, 그냥 `adb install` 하면 켜자마자 죽었습니다**: `UnsatisfiedLinkError: libflutter.so is for EM_AARCH64 instead of EM_X86_64`. 원인: apk.yml 이 `--target-platform android-arm,android-arm64` 로 빌드해 x86_64 용 Flutter 엔진(libflutter.so · libapp.so)이 없는데, 플러그인 하나가 `lib/x86_64/` 에 파일 2개를 넣어 두어서 설치기가 primaryCpuAbi=x86_64 를 골라 버립니다(APK 안 ABI: arm64-v8a 4개 · armeabi-v7a 4개 · x86_64 2개). `adb install --abi arm64-v8a` 로 강제하니 arm64 번역으로 정상. **실제 폰(arm64)은 영향 없음.** x86_64 기기(크롬북 · 에뮬레이터)까지 생각하면 x86_64 를 target-platform 에 넣거나(APK 커짐) 그 플러그인의 x86_64 lib 을 빼는 것 중 하나.
- 세 번째 칸 "체지방률" 릴리스 안내 문구(2a3a307) 는 다음 판에 나갈 것.

## 11. 운동 독촉 + 그래프 판독 — 진행 중
서버 다시 띄웠고(c906756: pokes 표 · ocr.js 그래프), 앱을 c906756 로 새로 빌드 중. 주인 결과지 사진은 앞서 이 세션에서 받아 둔 것을 씁니다.

## 그 밖에
- 에뮬레이터에는 지금 **릴리스 APK(arm64 번역)** 가 깔려 있음 — 11번 확인 때 디버그 빌드로 다시 바꿈.
- 시험 계정 emutest1 · emutest2 · emutest3 그대로.

**10 끝.**
