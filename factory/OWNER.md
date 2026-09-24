# 주인이 하는 일 전부

공장의 목표는 주인의 개입을 **법 · 돈 · 본인 확인 · 승인 버튼**만 남기는 것입니다. 나머지는 스크립트와 Claude 가 합니다.
아래가 전부이고, 이 밖의 일이 주인에게 오면 그건 공장의 버그입니다(상황판에 「주인 할 일」로 뜨면 왜 자동이 아닌지도 적혀야 합니다).

## A. 한 번만 (반나절)

| # | 무엇 | 왜 사람인가 | 걸리는 시간 |
|---|---|---|---|
| 1 | Claude **Max** 결제 · GitHub Pro(선택) | 돈 | 5분 |
| 2 | 맥 미니: 실험실 전용 사용자 만들고 자동 로그인 · FileVault 끄기 · App Store 에서 **Xcode 설치** · Xcode → Settings → Accounts 에 Apple ID | Apple ID 로그인 · 관리자 권한 | 30분(다운로드 대기 포함) |
| 3 | 맥 미니 터미널: `gh auth login` · `claude` 로그인 · Tailscale 로그인 | 계정 인증 | 5분 |
| 4 | 폰 연결: 아이폰 「신뢰」 · 개발자 모드, 안드로이드 USB 디버깅 허용 · 잠금 해제 · 자동 업데이트 끔 | 폰 화면 터치 | 폰당 3분 |
| 5 | 스토어 계정 단위: 애플 유료 앱 계약 · 세금 · 은행 · 소규모 사업자 프로그램 신청 · Play 결제 프로필 · 본인 확인 | 계약 · 본인 확인 | 30분 |
| 6 | 스토어 열쇠 발급 → 맥 미니 `~/app-keys/store/` 에 파일로: App Store Connect API 키 둘(Developer 역할 → `asc-beta.keyid`+`asc-beta.p8`, App Manager → `asc-prod.*`, 공통 `asc.issuer`), Play 서비스 계정 둘(`play-beta.json` 테스트 트랙 권한 · `play-prod.json` 프로덕션 권한), `claude setup-token` → `claude.token` | 콘솔에서만 발급 | 20분 |
| 7 | 맥 미니 Claude 세션에 한 줄: **"factory/scripts/macmini-setup.sh 돌리고, bootstrap.sh 돌려"** | — | 대기 30분 |
| 8 | claude.ai/code → Projects → 「앱 공장」 만들기(저장소 `app-factory` 하나) · 프로젝트 지침에 seed/CLAUDE.md §2 · §5 · §6 붙여 넣기 · 첫 메시지 "매일 21시 daily-digest 루틴 만들어" | 프로젝트 UI 는 API 없음 | 10분 |
| 9 | 폰 GitHub 앱 알림에서 「배포 검토」 켜기 | 폰 설정 | 1분 |
| 10 | (권장) 사업자등록 → 통신판매업 신고 → 애플 · 구글 세금 정보 → **플레이 조직 계정**(D-U-N-S) — 앱마다 12명 · 14일 테스트가 없어짐 | 법 · 세금 | 하루 (MONEY.md 7절) |

## B. 앱마다 한 번 (15~30분, 콘솔에서만 되는 칸)

Claude 가 `portfolio/<앱>/store/console-answers.md` 에 **붙여 넣을 답**을 다 만들어 두고 상황판에 링크합니다. 주인은 복사-붙여넣기.

| 어디 | 무엇 |
|---|---|
| App Store Connect | 새 앱 만들기(이름 · 번들 ID · SKU) · 앱 개인정보 보호 답안 |
| Play Console | 앱 만들기 · **첫 AAB** 올리기(내부 테스트; 산출물에서 받음) · 앱 콘텐츠 선언(등급 · 타깃 연령 · 광고 · 앱 액세스) |
| (개인 계정만) | 비공개 테스트 테스터 12명 초대 → 14일 뒤 프로덕션 액세스 신청 |

> 이 칸들도 없애는 길이 있습니다 — [PIPELINE.md](PIPELINE.md) 5절 「console-bot」. 맥 미니의 브라우저 프로파일에 두 콘솔을
> 로그인해 두면 Claude 가 Playwright 로 대신 채웁니다. 세션이 만료되면 몇 달에 한 번 다시 로그인. 첫 앱을 손으로 낸 뒤 켭니다.

## C. 출시마다 (30초)

폰 GitHub 앱 알림 → 실행 열기 → 요약의 상황판 링크 한 번 훑기 → **Approve and deploy**.
멈추고 싶으면 Reject 하고 Claude 앱에 한 줄.

**승인 자체도 없애려면**: `app-factory-ship` → Settings → Environments → store-production → Required reviewers 를 끕니다.
그러면 Claude 가 ship 을 실행하는 순간 나갑니다. 계정이 자산이라([MONEY.md](MONEY.md) 5절) 첫 앱 몇 개는 버튼을 권합니다.

## D. 매일 (10초)

21시 푸시 한 줄. 첫 줄이 「주인 할 일: 없음」이면 끝.
