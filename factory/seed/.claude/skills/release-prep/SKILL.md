---
name: release-prep
description: 출시 준비(S6). 한 앱의 출시 후보를 만들고, 스토어 문안 · 스크린샷 · 개인정보 답안을 맞추고, 심사 반려 점검을 통과시킨 뒤 ship 워크플로를 실행해 주인에게 승인 요청을 보낸다. "/release-prep <slug>" 또는 S5 가 끝났을 때.
argument-hint: <앱 slug>
---

앱: **$ARGUMENTS**

하나라도 빨간색이면 승인 요청을 보내지 않습니다. 고치고 처음부터 다시 봅니다.

## 1. 출시 후보 빌드

- [ ] `main` 이 초록이고, `docs/factory/QUALITY.md` L1~L5 가 이 커밋에서 초록
- [ ] 판 번호 결정(`1.<기능>.<고침>`) · `portfolio/<slug>/CHANGELOG.md` 에 사용자 말로 3줄
- [ ] 안드로이드 업로드 열쇠가 없으면(첫 판) mac-lab 에 `scripts/new-app-keys.sh <slug>` 를 부탁(세 줄 메시지)
- [ ] `store/` 를 fastlane 배치로 먼저 채움(2절) — release-candidate 의 queue 단계가 그대로 복사합니다
- [ ] `gh workflow run release-candidate.yml -f app=<slug> -f version=<판>` → TestFlight · 플레이 내부 테스트에
      올라감 · 출시 창구 `queue/<slug>/<판>/` 에 문안이 들어감
- [ ] **올라간 결과물 확인**: AAB 서명 지문이 이 앱의 업로드 열쇠와 같음 · IPA 번들 ID · 판 번호 ·
      빌드 번호 · 권한 목록(매니페스트 · Info.plist 를 꺼내서) — 워크플로 요약에 찍힌 것을 읽음
- [ ] `device-lab` 을 이 빌드로 한 번 더 (실기기 초록, 스크린샷)

## 2. 스토어 문안 · 그림 (`portfolio/<slug>/store/`)

- [ ] 배치(fastlane 표준 — ship 이 그대로 올림): `store/ios/metadata/<ko,en-GB>/{name,subtitle,keywords,description,
      release_notes,promotional_text,privacy_url,support_url}.txt` · `store/ios/screenshots/<ko>/` ·
      `store/android/<ko-KR,en-US>/{title,short_description,full_description}.txt` · `store/android/<ko-KR>/changelogs/<versionCode>.txt` ·
      `store/android/<ko-KR>/images/{icon.png,featureGraphic.png,phoneScreenshots/}` · 사용자가 있는 앱이면 `store/phased` 파일(단계적 출시)
- [ ] 한국어 · 영어: 이름(30) · 부제(30, 애플) · 짧은 설명(80, 구글) · 설명 · 키워드(100, 애플) ·
      새로운 기능. 글자 수는 스크립트로 셉니다.
- [ ] 키워드는 `research.md` 후보에서, 이름 · 부제와 겹치지 않게(애플은 겹치면 낭비)
- [ ] 스크린샷: 첫 세 장이 "무슨 앱인지 · 핵심 가치 · 차별점" 을 말함. 실제 앱 화면(목업 금지),
      애플 6.9" · 6.5" · 구글 폰 크기. 시험 데이터는 그럴듯하게(“test123” 금지).
- [ ] 개인정보처리방침 · 지원 · 계정 삭제 페이지 주소가 열림(200)

## 3. 개인정보 · 심사 답안

- [ ] 코드에서 데이터 흐름표를 뽑음(네트워크 호출 · SDK · 권한 · 저장 위치)
- [ ] 애플 「앱 개인정보 보호」 · 구글 「데이터 보안」 답안을 그 표에서 만들고 한 칸씩 대조
- [ ] 연령 등급 설문 답 · 수출 규정(암호화) 답 · 심사 메모(심사용 계정, 특별한 사용법)
- [ ] `store-reviewer` 에이전트 → `store/review-check.md` 에 **반려 예상 0**

처음 내는 앱이면 콘솔에서만 되는 칸이 있습니다(`docs/factory/PIPELINE.md` 「사람만 되는 칸」).
그 칸들의 답을 **복사해서 붙일 수 있게** `store/console-answers.md` 에 정리하고 상황판
「주인 할 일」에 링크합니다. 이것은 앱마다 처음 한 번뿐입니다.

## 4. 승인 요청

- [ ] 출시 PR(또는 상황판) 본문을 CLAUDE.md §5 「출시 요청」 형식으로
- [ ] `gh workflow run ship.yml -R <주인>/app-factory-ship -f app=<slug> -f version=<판> -f rollout=<새 앱 1 · 업데이트 0.2>`
      → `store-production` 환경에서 멈추고 GitHub 이 주인에게 승인 요청을 보냅니다
- [ ] 주인에게 알림 한 번: "<앱> v<판> 출시 승인 요청 — 바뀐 것 한 줄 · 실기기 n대 초록 · 링크"

승인 뒤 ship 이 돌면: 애플은 심사 제출(통과하면 자동 출시), 구글은 프로덕션 트랙으로(사용자가 있는
앱의 업데이트는 20% 단계적 배포 → 지표를 보고 100% 를 다시 승인 요청). 심사 결과와 배포 비율은
상황판에 갱신하고, 반려되면 반려 사유를 읽고 고쳐서 다시 요청합니다(새 승인 필요).
