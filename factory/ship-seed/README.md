# app-factory-ship — 출시 창구

코드가 없는 공개 저장소입니다. 하는 일은 하나: **주인이 승인한 판만** 스토어에 제출 · 배포합니다.

- 왜 따로인가: GitHub 의 승인 버튼(환경 Required reviewers)이 개인 요금제에서는 공개 저장소에서만 됩니다.
  비공개 `app-factory` 에는 코드와 테스트 트랙까지만 되는 열쇠를, 여기에는 프로덕션 열쇠를 둡니다.
- 열쇠는 `store-production` 환경 안에만 있고, 그 환경의 잡은 승인 버튼이 눌려야 시작됩니다.
- `queue/<앱>/<판>/` 은 `app-factory` 의 release-candidate 워크플로가 배포 열쇠로 넣습니다:
  `build.json`(판 · 빌드 번호 · 번들 ID) · `ios/metadata/<ko,en-GB>/*.txt` · `ios/screenshots/<ko>/…` ·
  `android/<ko-KR,en-US>/{title,short_description,full_description}.txt` · `android/<ko-KR>/changelogs/<versionCode>.txt` ·
  `android/<ko-KR>/images/phoneScreenshots/…` (fastlane deliver · supply 의 표준 배치).
- 워크플로: `ship.yml`(심사 제출 · 프로덕션) · `ship-control.yml`(배포 비율 · 멈춤).

승인은 폰 GitHub 앱 → 알림 「Review pending deployment」 → **Approve and deploy**.
