# 품질 · 시험 체계

"안 깨진다" 는 자동 시험으로 보장하고, "쓸 만하다" 는 조사 · 비평 · 탐색 시험으로 좁힙니다.
자동 시험이 초록이어도 **첫 30초가 지루하면 지워집니다** — 그래서 L4 와 product-critic 이 있습니다.

---

## 시험 층

| 층 | 어디서 | 무엇 | 도구 |
|---|---|---|---|
| **L1 정적 · 단위** | ci (리눅스) · 매 PR | 분석 · 로직 단위 시험 · 위젯 시험 · 골든 스크린샷 · 문구 · 글꼴 | `flutter analyze` · `flutter test` · `dart test` |
| **L2 통합** | 맥 미니 · 시뮬레이터 / 에뮬레이터 | 첫 실행 → 핵심 가치 · 결제 흐름 · 권한 거절 · 오프라인 | Maestro(흐름 YAML) · StoreKit 구성 파일 |
| **L3 실기기** | 맥 미니 · 아이폰 12 · 안드로이드 폰들 | 실제 입력기 · 알림 도착 · 백그라운드 복귀 · 카메라 · 제조사 절전 | 안드로이드: Maestro · 아이폰: Patrol 또는 integration_test |
| **L4 AI 탐색** | 맥 미니 · 출시 후보마다 | 헌장 6개(첫 사용자 · 거친 입력 · 중단 · 권한 거절 · 큰 글꼴/다크 · 결제) | `qa-explorer` + mobile-mcp |
| **L5 비기능 · 결과물** | ci + release-candidate | 시작 시간 · 크기 · 접근성 · 스토어 규정 정적 검사 · 올라간 결과물 열어 보기 | 스크립트 |
| **L6 출시 뒤** | 루틴 | 크래시 · ANR · 리뷰 · 지표 | Crashlytics · Play vitals · App Store Connect |

도구 선택 근거 (2026-09 확인):
- **Maestro** — 시뮬레이터 · 에뮬레이터 · 안드로이드 실기기 OK. **실제 아이폰은 공식 지원 안 함**
  ([#686](https://github.com/mobile-dev-inc/Maestro/issues/686) 열린 채). YAML 이라 Claude 가 쓰고 고치기 쉽고,
  CLI 에 MCP 서버가 들어 있음.
- **Patrol** — Flutter 전용, 실기기 iOS · 안드로이드, 권한 창 · 알림 · 다크 모드 같은 **OS 화면**까지 누름.
  실제 아이폰에는 릴리스 빌드와 `RunnerUITests.xctrunner` 서명이 필요
  ([설정](https://github.com/leancodepl/patrol/blob/master/docs/documentation/physical-ios-devices-setup.mdx)).
- **integration_test** — Flutter 기본. 실기기 OK, 하지만 OS 권한 창은 못 누름.
- **mobile-mcp** — iOS 시뮬 · 실제 아이폰(USB · 신뢰) · 안드로이드 에뮬 · 실기기를 Claude 가 직접 봄/누름
  ([README](https://github.com/mobile-next/mobile-mcp)). 정해진 시험이 아니라 탐색용.
- **Firebase Test Lab**(선택) — 가진 폰에 없는 기종이 필요할 때. 무료(Spark) 하루 가상 10회 · 실기기 5회.

---

## L1 — 매 PR

- 모든 화면을 세워서 `ErrorWidget` 이 없는지 — **밀어 올린(push) 화면도**, 빈 데이터 · 가득 찬 데이터 둘 다
- 골든: 라이트 · 다크 × 글자 배율 1.0 · 2.0 × 가장 작은 폭(320~360dp)
- 접근성: Flutter 내장 기준 `meetsGuideline(textContrastGuideline)` · `labeledTapTargetGuideline` ·
  `androidTapTargetGuideline` · `iOSTapTargetGuideline` 을 화면마다
- 시험에는 **가짜 플랫폼 플러그인**을 꽂음 — 진짜 플러그인 `await` 는 시험에서 영영 안 돌아옴(MyBody)
- 문구표 검사: 스토어 글자 수 · 금지어(검증 안 된 "1위" "최고" 등) · 빈 문자열 · 영어 섞임
- 글꼴 커버리지: 앱이 그리는 모든 글자가 번들 글꼴에 있는지(MyBody `tools/test-fontcover.js` 방식)

## L2 · L3 — 기기 실험실

**흐름 묶음 (앱마다 `.maestro/`)** — 최소 이 다섯:
1. `first-run` — 설치 직후 → 온보딩 → 첫 핵심 가치 화면 (탭 수를 셈)
2. `core-loop` — 핵심 반복 행동 한 바퀴, 재실행 뒤 기록이 남는가
3. `paywall` — 결제 벽 노출 · 구매(샌드박스) · 복원 · 취소
4. `denied` — 권한 전부 거절하고도 앱이 설명하며 계속 도는가
5. `offline` — 비행기 모드로 켜기 · 저장 · 망 복귀 뒤 동기화(서버가 있으면)

**실기기에서만 보는 것**
- 한글 입력(조합 중 저장, 받침) — 에뮬레이터엔 한글 입력기가 없음(MyBody)
- 예약 알림이 실제로 오는가(1~2분 뒤로 걸어 봄) · 안드로이드 7~11 알람 묶기 · 제조사 절전
- 백그라운드 30분 뒤 복귀 · 강제 종료 뒤 재실행
- 느린 기기에서 시작 시간

## L5 — 결과물 열어 보기 · 스토어 규정 정적 검사

**빌드가 초록인 것 ≠ 결과물이 맞는 것.** release-candidate 는 아래를 파일에서 직접 꺼내 확인하고
하나라도 틀리면 멈춥니다:

| 검사 | 방법 | 왜 |
|---|---|---|
| AAB 서명 · 지문 | `unzip -l` 로 `META-INF/*.RSA\|EC` · `keytool -printcert -jarfile` 지문 = 앱 업로드 열쇠 | MyBody: 서명 안 된 중간 AAB, 디버그 서명 배포 |
| 번들 ID · 판 · 빌드 번호 | 매니페스트 · Info.plist 에서 | 두 스토어 번호 어긋남 방지 |
| 권한 목록 | 컴파일된 매니페스트 · Info.plist | 인터넷 권한 빠짐, 안 쓰는 권한 들어감 |
| 권한 문구 | 모든 `NS*UsageDescription` 존재 · 한국어 | 반려 사유 1순위 |
| `PrivacyInfo.xcprivacy` | IPA 안에 있고 필수 사유 API 선언 | 2024-05 부터 없으면 업로드 거부. `shared_preferences` 는 UserDefaults 를 씀 |
| targetSdk | ≥ 36 | 2026-08-31 부터 새 앱 · 업데이트 필수([공식](https://developer.android.com/google/play/requirements/target-sdk)) |
| 16KB 페이지 | 네이티브 `.so` 정렬 확인 | 2027-02-01 부터 미대응 업데이트 출시 불가([공식](https://developer.android.com/guide/practices/page-sizes)) |
| iOS SDK | Xcode 26 / iOS 26 SDK 이상 | 2026-04-28 부터 필수([공식](https://developer.apple.com/news/upcoming-requirements/)) |
| 암호화 신고 | `ITSAppUsesNonExemptEncryption=false`(HTTPS 만 쓸 때) | 매 업로드마다 수출 규정 질문을 피함 |
| 계정 삭제 | 계정 기능이 있으면 앱 안 삭제 경로 존재 | 애플 5.1.1(v) |
| 구독 화면 요소 | 가격 · 기간 · 자동 갱신 · 해지 · 약관 · 개인정보 · 복원 | 애플 3.1.2 |
| 방침 · 지원 · 삭제 URL | HTTP 200 | 등록정보 필수 |
| 데이터 흐름 ↔ 개인정보 답안 | 코드의 네트워크 호출 · SDK 목록과 답안 대조 | 불일치는 반려 · 정책 위반 |
| 시작 시간 | 안드로이드 `adb shell am start -W` · iOS 첫 프레임 로그 | 중급 실기기 2초 기준 |
| 크기 | AAB · IPA 크기, 전 판 대비 | 갑자기 커지면 원인 확인 |

## L6 — 출시 뒤

| 지표 | 기준 | 넘으면 |
|---|---|---|
| 크래시 없는 사용자 | ≥ 99.5% | 배포 멈추기 승인 요청 |
| 안드로이드 사용자 체감 비정상 종료율 | < 1.09% (Play 「나쁜 동작」 기준선) | 멈추기 · 고침 — 넘으면 스토어 노출이 줄어듦 |
| 안드로이드 체감 ANR 률 | < 0.47% | 같음 |
| 새 1~3점 리뷰 | 원문을 하루 요약에 | 버그면 이슈, 오해면 답변 초안(주인 확인 없이 달아도 되는 범위를 정해 둠) |

---

## 기기표 (맥 미니에 붙이면서 채움)

| 이름 | 기종 | OS | 화면 | 맡는 것 | 연결 |
|---|---|---|---|---|---|
| iphone12 | iPhone 12 | iOS 26.x | 6.1" | iOS 실기기 기준(느린 쪽) | 맥 미니 USB |
| sim-small | iPhone SE (3세대) 시뮬 | 최신 | 4.7" | 가장 작은 화면 | 맥 미니 |
| sim-large | 가장 큰 iPhone 시뮬 | 최신 | 6.9" | 스토어 스크린샷 크기 | 맥 미니 |
| android-? | (가진 폰) | | | 제조사 · 판 · 크기를 섞어서 | 맥 미니 USB 허브 |
| emu-min | 에뮬레이터 | 앱 최소 API | | 가장 오래된 판 | 윈도우 |
| emu-latest | 에뮬레이터 | API 36 | | 최신 판 | 맥 미니 또는 윈도우 |

**주인이 실제로 쓰는 폰은 이 표에 넣지 않습니다.** `qa-explorer` 는 표에 없는 기기를 건드리지 않습니다.
