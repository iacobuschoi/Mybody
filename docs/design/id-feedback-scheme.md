# Mybody 프로토타입 — 고유 ID & 피드백 시스템 설계서

> 대상: `/home/user/Mybody/prototype/` (zero-build, vanilla HTML/CSS/JS, localStorage only)
> 이 문서는 프로토타입 단계의 **검증 인프라** 명세다. 화면 기능 자체보다 이게 먼저 확정되어야 한다 — 소유자가 "P03의 B12가 이상해"라고 말할 수 있어야 반복 주기가 성립하기 때문.
> 제안 파일: `/home/user/Mybody/prototype/index.html`, `/home/user/Mybody/prototype/uid-registry.js`, `/home/user/Mybody/prototype/uid.js`, `/home/user/Mybody/prototype/uid.css`

---

## 1. ID 체계 (Taxonomy)

### 1.1 접두어 정의

| 접두어 | 의미 | 범위 | 배지 색 | 비고 |
|---|---|---|---|---|
| `P` | Page / 화면 | **전역** | `#6D28D9` 바이올렛 | 라우팅 단위. 한 번에 하나만 보임 |
| `M` | Modal / 팝업 / 시트 | **전역** | `#BE185D` 핑크 | 여러 화면에서 열리므로 화면에 종속시키지 않음 |
| `A` | Alert / 토스트 / 배너 | **전역** | `#B91C1C` 레드 | 공용 컴포넌트. 발생 화면이 여러 개 |
| `N` | Nav item | 컨테이너 종속 | `#4338CA` 인디고 | 셸(P00)의 자식 |
| `T` | Tab | 컨테이너 종속 | `#0E7490` 시안 | 화면 내부 탭 |
| `B` | Button / 액션 | 컨테이너 종속 | `#1D4ED8` 블루 | 아이콘 버튼·링크 버튼 포함 |
| `F` | Field / 입력 | 컨테이너 종속 | `#0F766E` 틸 | input, select, slider, stepper, toggle |
| `C` | Card / 섹션 | 컨테이너 종속 | `#92400E` 앰버 | 시각적 블록 경계 |
| `L` | List / Table | 컨테이너 종속 | `#334155` 슬레이트 | 반복 렌더 컨테이너 |
| `G` | Graph / Chart | 컨테이너 종속 | `#7E22CE` 퍼플 | 차트·게이지·프로그레스 시각화 |

10종으로 고정한다. 아이콘·라벨·이미지 같은 순수 장식 요소는 **ID를 주지 않는다.** ID가 붙은 요소는 "피드백 대상으로서 의미가 있는 요소"라는 신호여야 하고, 모든 DOM 노드에 번호를 뿌리면 배지가 노이즈가 되어 시스템 전체가 죽는다. (예외: 소유자가 특정 텍스트/이미지를 지목하고 싶다고 하면 그때 `C`로 승격시킨다.)

### 1.2 번호 스코프 — **하이브리드 스코프로 결정**

**규칙: 컨테이너(`P`, `M`)와 전역 컴포넌트(`A`)는 전역 연번. 나머지 모든 리프(`N`,`T`,`B`,`F`,`C`,`L`,`G`)는 소속 컨테이너 내부 연번이며, 항상 `컨테이너-리프` 2세그먼트로 표기한다.**

```
P03-F02        ← 스캔 검수 화면의 2번 입력 필드
M04-B01        ← 목표 경고 모달의 1번 버튼
P00-N03        ← 앱 셸(하단 탭바)의 3번 내비 항목
A02            ← 전역 토스트 2번
P08-L01#3      ← 히스토리 화면 1번 리스트의 3번째 행 (런타임 자동 부여)
```

**근거 (전역 연번을 버린 이유):**

1. **자기 위치 표현.** `B47`은 어느 화면인지 알 수 없어 소유자도 나도 찾아야 한다. `P06-B04`는 듣는 즉시 위치가 확정된다. 음성 메모나 카톡으로 던질 때도 7글자면 충분하다.
2. **삽입 내성.** 전역 연번은 화면 하나가 추가되면 "번호가 화면 순서와 어긋나는" 현상이 전체 앱으로 퍼진다. 컨테이너 스코프면 어긋남이 그 화면 안에 갇힌다.
3. **병렬 작업.** 화면별로 번호 블록이 독립이라 두 화면을 동시에 늘려도 번호 충돌이 없다.
4. **검색성.** `P06-` 로 grep 하면 플랜 화면 전체가 나온다. 전역 연번은 불가능하다.

**모달을 화면에 종속시키지 않는 이유:** 촬영 가이드 모달(M02)은 업로드(P02)와 스캔 검수(P03) 양쪽에서 열린다. `P02-M01`로 묶으면 같은 모달이 두 개의 ID를 갖게 되어 피드백이 쪼개진다. 모달은 전역 시민이다. 토스트도 같은 이유.

### 1.3 깊이는 최대 2세그먼트 — 3단 중첩 금지

`P03-C02-F01` 같은 표기는 **쓰지 않는다.** 카드 안의 필드도 `P03-F01`이다. 이유:

- 3세그먼트는 읽고 말하기에 너무 길다 (검증 단계의 목적은 "말하기 쉬움").
- 요소를 다른 카드로 옮기면 ID가 바뀐다 → 안정성 계약 위반.
- 중첩 관계는 레지스트리의 `설명` 컬럼과 화면 자체가 알려준다. ID가 트리 구조까지 인코딩할 필요는 없다.

### 1.4 반복 행(list row) 처리

리스트는 컨테이너 `L`에만 ID를 부여하고, 행 인스턴스는 런타임이 `#n` 접미를 자동으로 붙인다 (`P06-L01#2`). `#n`은 **레지스트리에 등록하지 않는다** (데이터 개수에 따라 변하므로). 행 내부의 반복 버튼은 `P06-L01#2 / 교체 버튼` 형태로 피드백에 라벨이 같이 실려서 구분된다.

### 1.5 번호 대역 예약

| 대역 | 용도 |
|---|---|
| `P00` | 앱 셸 (앱바 / 탭바 / 개발자 독) |
| `P01`–`P09` | 핵심 플로우 화면 |
| `P10`–`P19` | 부가 화면 (ID 인덱스 등) |
| `P90`–`P99` | 개발/디버그 전용 화면 |
| `M01`–`M89` | 제품 모달 |
| `M90`–`M99` | 피드백 시스템 자체의 모달 |
| `A01`–`A89` | 제품 토스트/배너 |
| `A90`–`A99` | 피드백 시스템 토스트 |

리프는 각 컨테이너 안에서 `01`부터. 2자리 제로패딩 고정(`B01`, 아니면 `B1`/`B10` 정렬이 깨진다). 한 컨테이너에 99개 넘는 동종 리프가 생기면 그건 화면을 쪼개라는 신호다.

---

## 2. 배지 렌더링 규칙

### 2.1 구현 방식: **실제 `<span>` 주입** (CSS `::after` 아님)

`::after`를 쓰지 않는 결정적 이유:

- `<input>`, `<img>`, `<canvas>`, `<select>`, `<progress>`는 **replaced element라 의사요소가 아예 생성되지 않는다.** 이 앱은 입력 필드(F)와 차트(canvas, G)가 핵심인데 그 둘에 배지를 못 다는 방식은 탈락.
- 배지를 **클릭해서 복사**해야 한다. 의사요소는 독립 이벤트 타겟이 아니다.
- `overflow:hidden`인 카드 안에서 의사요소는 잘린다. 실제 span은 포털 없이도 `position:absolute` + 앵커 래퍼로 통제 가능.
- 라벨 확장, 메모 카운트 뱃지 등 **자식 구조**가 필요하다.

배지 DOM:

```html
<span class="uid-badge" data-uid-for="P03-F02" data-uid-pos="tr" aria-hidden="true">
  <span class="uid-badge__id">P03-F02</span><span class="uid-badge__label">골격근량</span>
</span>
```

### 2.2 크기 · 타이포

| 속성 | 값 | 이유 |
|---|---|---|
| `font-size` | `9px` (`--uid-badge-fs`) | 본문 대비 확실히 작아 시선을 뺏지 않지만 6자 ID가 판독 가능한 하한 |
| `font-family` | `ui-monospace, SFMono-Regular, Menlo, Consolas, monospace` | `0/O`, `1/I` 구분. ID는 반드시 고정폭 |
| `font-weight` | `600` | 9px에서 400은 안티에일리어싱에 뭉갠다 |
| `font-variant-numeric` | `tabular-nums` | 배지들이 세로로 줄 맞음 |
| `letter-spacing` | `.02em` | 9px 고정폭의 자간 보정 |
| `line-height` | `1` |  |
| `padding` | `1px 3px` | 총 높이 약 12px |
| `border-radius` | `3px` |  |
| `설정 노출` | P09-F05에서 9 / 10 / 11px 선택 | 소유자 시력·디스플레이 배율 대응 |

### 2.3 위치

컨테이너형(`P`,`M`,`C`,`L`,`G`)은 **좌상단 바깥** `top:-6px; left:-6px`.
컨트롤형(`B`,`F`,`N`,`T`,`A`)은 **우상단 바깥** `top:-5px; right:-5px`.

컨트롤을 우상단으로 보내는 이유: 버튼은 보통 선행 아이콘이 좌측에 있고, 폼 필드는 좌측 상단에 `<label>`이 붙는다. 좌상단은 이미 점유된 자리다. 반대로 카드/섹션은 좌상단이 제목 시작점이라 배지가 "이 블록의 이름표"처럼 자연스럽게 읽힌다.

**뷰포트 클리핑 방지 3중 안전장치:**

1. 셸 루트에 `overflow-x: clip` (배지 6px 돌출이 가로 스크롤바를 만들지 않게. `hidden`이 아니라 `clip`이라 `position:sticky`가 안 깨짐).
2. 부팅 시 각 배지의 `getBoundingClientRect()`를 검사해 뷰포트 밖이면 `data-uid-pos="tl-in"` / `"tr-in"`으로 전환 → 요소 **안쪽** `top:2px; left:2px`로 접힘.
3. 중첩 깊이 오프셋: 조상 중 `[data-uid]` 개수를 `--uid-depth`로 넣어 `top`을 깊이당 `12px` 내린다. 카드(C) 배지와 그 안 첫 버튼(B) 배지가 겹치지 않는다.

### 2.4 레이아웃 무해성

- 배지는 항상 `position:absolute`. 호스트는 **`getComputedStyle(el).position === 'static'`일 때만** `.uid-anchored { position: relative }`를 부여한다. 이미 `absolute`/`fixed`/`sticky`인 요소의 포지셔닝을 건드리지 않는다.
- replaced element는 JS가 `<span class="uid-wrap">`(`display:contents`가 아닌 `inline-block`, 원본의 `width:100%` 승계)로 감싸고 배지를 래퍼에 단다. 감싸기 전 원본의 `display`를 읽어 블록 요소면 래퍼도 `display:block`.
- 배지는 **flex/grid 컨테이너의 자식이 되어도 무해**하다 — `position:absolute` 자식은 flex item으로 취급되지 않는다. 단 `gap` 계산에는 영향이 없음을 부팅 시 자동 검증(섹션 6.6 `auditLayout()`).
- 배지 OFF 상태는 `display:none`이므로 렌더 트리에서 완전히 빠진다. ID를 끈 상태의 화면은 최종 앱과 픽셀 단위로 동일해야 한다.

### 2.5 대비 — 라이트/다크 양쪽에서 살아남는 법

핵심 기법: **이중 링(double ring)**.

```css
box-shadow:
  0 0 0 1px rgba(255,255,255,.70),   /* 안쪽 밝은 링 — 어두운 배경에서 배지를 분리 */
  0 0 0 2px rgba(0,0,0,.45);         /* 바깥 어두운 링 — 밝은 배경에서 배지를 분리 */
```

배지 칩 자체는 흰 글자 + 유형별 단색. 링 두 개가 항상 함께 있으므로 배경이 흰색이든 검정이든 사진(인바디 사진 위 오버레이!)이든 배지 경계가 무너지지 않는다. 다크 모드에서는 알파만 조정(`.55` / `.60`)하고 순서는 그대로 둔다 — 순서를 바꾸면 배경이 중간 밝기일 때 오히려 나빠진다.

칩 색은 전부 흰 글자 기준 **4.5:1 이상**(대부분 7:1 이상)으로 선정:

| 유형 | HEX | 흰 글자 대비(근사) |
|---|---|---|
| P | `#6D28D9` | 7.6:1 |
| M | `#BE185D` | 6.5:1 |
| B | `#1D4ED8` | 8.0:1 |
| F | `#0F766E` | 5.6:1 |
| C | `#92400E` | 7.8:1 |
| T | `#0E7490` | 4.9:1 |
| N | `#4338CA` | 8.4:1 |
| L | `#334155` | 11.2:1 |
| G | `#7E22CE` | 7.2:1 |
| A | `#B91C1C` | 7.0:1 |

다크 모드에서는 각 색을 `color-mix(in srgb, var(--uid-X) 82%, white)`로 살짝 올려 어두운 배경에서의 채도 침몰을 막는다.

### 2.6 호버 동작

| 트리거 | 동작 |
|---|---|
| 평상시 | `opacity: .72` — 존재하지만 화면을 지배하지 않음 |
| 호스트 요소 호버 | 배지 `opacity: 1`, `transform: scale(1.25)` |
| 배지 자체 호버 | 위 + **한글 라벨 펼침** (`max-width: 3ch → 16ch` 트랜지션), `cursor: copy`, `title="클릭: ID 복사 · Shift+클릭: 메모 · Alt+클릭: 링크 복사"` |
| 배지 포커스(Tab) | 호버와 동일 + `outline: 2px solid currentColor` |
| 메모 있는 요소 | 배지 배경이 `#B91C1C`로, 우측에 `●3` 카운트 표시 |
| `prefers-reduced-motion` | 모든 `transition`/`animation` 제거, 상태 전환은 즉시 |
| `@media print` | `.uid-badge { display: none !important }` |

접근성: 배지는 `aria-hidden="true"` + `tabindex="-1"`(배지 레이어 OFF 시). 배지 ON일 때만 `tabindex="0"`로 승격되어 키보드로도 순회 가능. 스크린리더에게 ID를 읽히지 않는 이유 — 이건 개발 도구지 제품 UI가 아니다. ID 검색은 P10 인덱스에서 정상 접근성으로 제공.

---

## 3. 피드백을 마찰 없게 만드는 기능

### 3.1 배지 전역 토글

- **`Shift + I`** (ID의 I) — 모든 배지 표시/숨김. `<html class="uid-on">` 하나로 제어.
- 개발자 독(P00-C03, 우하단 플로팅)의 `P00-B02` 버튼으로도 토글.
- 상태는 `localStorage['mybody.uid.badges.v1']`에 저장, 새로고침 후 유지. 프로토타입 기본값 **ON**.
- 입력 중(`INPUT`/`TEXTAREA`/`contenteditable`)에는 단축키를 무시한다. 단 `Escape`는 항상 받는다.

전체 단축키:

| 키 | 동작 |
|---|---|
| `Shift + I` | 배지 표시/숨김 |
| `Shift + F` | 피드백 모드 on/off |
| `Shift + K` | ID 인덱스(P10) 열기 / 점프 팔레트 |
| `Shift + E` | 피드백 내보내기 모달(M91) |
| `Shift + D` | 다크/라이트 전환 |
| `Shift + /` | 단축키 도움말(M92) |
| `Escape` | 모달 닫기 → 피드백 모드 해제 순으로 |

### 3.2 배지 클릭 = 복사

- **클릭**: `P03-B02 / 플랜 생성 버튼` 을 클립보드로. 형식은 `{ID} / {한글 라벨}` — 소유자가 붙여넣기만 해도 내가 대상과 명칭을 동시에 안다.
- **Alt + 클릭**: 딥링크 URL 복사 (`.../index.html#P03-B02`).
- **Shift + 클릭**: 메모 작성(3.3).
- `file://`은 **secure context가 아니라 `navigator.clipboard`가 없다.** 반드시 `document.execCommand('copy')` 폴백을 둔다(6.3 코드 참조). 폴백까지 실패하면 토스트 대신 텍스트 선택 상태로 남겨 `Ctrl+C`를 유도한다.
- 복사 성공 시 `A90` 토스트: "복사됨 · P03-B02".

### 3.3 피드백 모드

`Shift+F` 또는 `P00-B03`으로 진입. `<html class="uid-fb">`가 붙으면:

- `[data-uid]` 전부에 `outline: 1px dashed rgba(190,24,93,.35)`, `cursor: crosshair`.
- **캡처 단계**에서 클릭을 가로채 `preventDefault` + `stopPropagation` → 제품 동작은 일어나지 않고 메모 팝오버(`M90`)만 열린다. 캡처 단계여야 하는 이유: 버튼 자신의 핸들러보다 먼저 잡아야 화면이 전환되지 않는다.
- 팝오버는 클릭한 요소에 앵커링(뷰포트 밖이면 자동 플립), 상단에 `P03-F02 · 골격근량 입력` 고정 표시.
- 입력 항목: 본문(textarea), 심각도(`치명 / 중요 / 사소 / 아이디어`), 상태(`열림 / 해결`).
- `Ctrl+Enter` 저장, `Esc` 취소. 저장 즉시 배지가 빨강 + 카운트로 바뀐다.
- 저장 위치: `localStorage['mybody.uid.feedback.v1']`, 배열.

```js
{
  nid: "n_1758240000123_7f3a",   // 노트 고유키
  uid: "P03-F02",
  label: "골격근량(SMM) 입력",
  screen: "P03 스캔 검수",
  text: "OCR이 28.4를 2.84로 읽음. 소수점 처리 확인 필요",
  severity: "치명",
  status: "열림",
  createdAt: "2026-09-19T11:04:22.000Z",
  updatedAt: "2026-09-19T11:04:22.000Z",
  registryVersion: 1,
  viewport: "390x844"            // 모바일/데스크톱 재현용
}
```

한 요소에 메모 여러 개 허용(스레드). 팝오버 하단에 기존 메모 목록 + 수정/삭제.

### 3.4 전체 피드백 내보내기

`Shift+E` / `P00-B04` → `M91` 모달. **복사 버튼**(클립보드)과 **.md 다운로드**(Blob) 둘 다 제공. 출력은 화면별로 그룹핑되고 심각도 순으로 정렬:

```markdown
# Mybody 프로토타입 피드백
- 일시: 2026-09-19 20:04
- 레지스트리: v1 (2026-09-19)
- 총 12건 (치명 2 · 중요 5 · 사소 3 · 아이디어 2)
- 열림 10 / 해결 2

## P03 스캔 검수 (3건)

- [ ] **P03-F02** · 골격근량(SMM) 입력 · `치명`
  > OCR이 28.4를 2.84로 읽음. 소수점 처리 확인 필요
- [ ] **P03-B02** · 낮은 신뢰도 항목만 보기 · `사소`
  > 이 버튼 토글인지 필터인지 모르겠음
- [x] **P03-G01** · 체성분 막대 그래프 · `아이디어`
  > 목표치를 점선으로 같이 그려주면 좋겠다

## P05 강도 선택 (2건)
...

---
### 미분류 / 레지스트리 불일치
- **P07-B09** (레지스트리에 없는 ID) > ...
```

`- [ ]` 체크박스 형식인 이유: 소유자가 그대로 붙여넣으면 나에게 **실행 가능한 할 일 목록**이 되고, 다음 턴에 내가 `- [x]`로 바꿔 돌려줄 수 있다. JSON 내보내기도 같이 제공(`M91-B03`) — 왕복 병합용.

### 3.5 ID 인덱스 화면 (P10)

- 레지스트리 전체를 테이블로. 컬럼: ID / 종류 / 화면 / 한글 라벨 / 설명 / 상태 / 메모 수.
- 검색(`P10-F01`): ID, 한글 라벨, 설명 전부 대상. 한글 초성 검색은 하지 않는다(과도한 구현) — 대신 부분 문자열 + 공백 무시 매칭.
- 필터 칩: 종류(P/M/B/F/...), 상태(활성/폐기/예정), 메모 유무.
- 행 클릭 → 해당 화면으로 점프 + 하이라이트. 행의 복사 아이콘 → `ID / 라벨` 복사.
- **드리프트 검사(`P10-B03`)**: DOM 실측과 레지스트리를 대조해 3종 리포트 — `미등록`(DOM엔 있고 레지스트리엔 없음), `미구현`(레지스트리 활성인데 DOM에 없음), `중복`(같은 ID 2개 이상). 이게 이 화면의 진짜 가치다. 빌드 시스템이 없으니 런타임 감사가 CI 역할을 한다.
- 커버리지 요약 카드(`P10-C01`): 총 ID 수 / 화면별 개수 / 활성·폐기 비율.

### 3.6 딥링크

- `#P03` → 해당 화면으로 라우팅.
- `#P03-B02` → 화면 라우팅 후 `scrollIntoView({block:'center'})` + `.uid-flash` 펄스(1.2s × 2회).
- `#M04` → 모달을 여는 기저 화면(레지스트리의 `openFrom` 필드)으로 이동 후 모달 오픈.
- `#P08-L01#3` → 리스트 3번째 행 하이라이트(행이 없으면 리스트 자체를 하이라이트하고 `A92` 토스트로 알림).
- `hashchange` 리스너로 처리하며, 대상이 아직 렌더되지 않았으면 `requestAnimationFrame` 2틱 후 재시도(최대 10회).
- 피드백 내보내기의 각 항목에 딥링크를 옵션으로 포함 가능(`M91-F01` 체크박스).

---

## 4. 안정성 계약 (Stability Contract)

> **최상위 원칙: 소유자가 어제 적어둔 `P06-B04`는 내일도 같은 버튼이다. 번호는 절대 밀리지 않는다.**

### 4.1 규칙

1. **한 번 부여된 번호는 영구하다.** 재사용 금지, 재번호 매기기 금지.
2. **삭제 = 폐기(retire)**, 행 삭제가 아니다. 레지스트리에서 `status: "retired"`, `retiredIn: 3`으로 남긴다. 그 번호는 영원히 비어 있다. `P04-B02`를 지웠다면 `P04-B02`는 다시 태어나지 않는다.
3. **추가 = 해당 컨테이너의 다음 빈 정수.** 시각적 위치와 무관하다. 화면 맨 위에 버튼을 새로 넣어도 그건 `P04-B09`다. 시각 순서와 번호 순서가 어긋나는 건 **의도된 비용**이며, 그 대가로 소유자의 메모가 절대 무효화되지 않는다. 레지스트리 표의 행 순서가 시각 순서를 표현한다.
4. **다른 화면으로 이동 = 폐기 + 신규.** ID가 위치를 인코딩하므로 이동은 정체성의 변경이다. 구 행에 `movedTo: "P05-B07"`을 남겨 기존 피드백이 자동으로 따라가게 한다(내보내기 시 `(구 P04-B03에서 이동)` 주석).
5. **라벨 변경은 ID에 영향 없음.** `labelHistory` 배열에 이전 라벨을 쌓아, 소유자가 옛 이름으로 검색해도 P10에서 찾힌다.
6. **화면 삭제 시 `P0n` 번호도 폐기.** 새 화면은 `P11`, `P12`로 계속 나아간다. 화면 번호 재활용은 가장 치명적인 혼동이므로 예외 없다.
7. **레지스트리 버전.** `REGISTRY_VERSION` 정수를 반복마다 +1. 모든 메모에 기록되어, v1에서 쓴 메모를 v4에서 볼 때 "그 사이 이 ID가 폐기됨" 경고를 띄울 수 있다.
8. **번호 예약 금지.** "나중에 쓸 것 같으니 B05~B08 비워두자"는 하지 않는다. 예약은 규칙 1·3만으로 충분히 해결되는 문제를 사람이 기억해야 하는 문제로 바꾼다.

### 4.2 레지스트리 파일

단일 소스: `/home/user/Mybody/prototype/uid-registry.js` (JSON을 `fetch`하면 `file://`에서 CORS로 막히므로 **JS 파일에 객체 리터럴**로 둔다. 이게 zero-build + `file://` 제약의 정답이다.)

```js
window.UID_REGISTRY = {
  version: 1,
  updatedAt: "2026-09-19",
  screens: {
    P00: { label: "앱 셸",       kind: "shell" },
    P03: { label: "스캔 검수",   kind: "page", order: 4 },
    M04: { label: "목표 현실성 경고", kind: "modal", openFrom: "P04" }
  },
  items: [
    { id:"P03-F02", type:"F", screen:"P03", label:"골격근량(SMM) 입력",
      desc:"OCR 인식값, 편집 가능, 0.1 단위", status:"active", since:1 },
    { id:"P04-B02", type:"B", screen:"P04", label:"추천 목표 자동 채우기",
      desc:"", status:"retired", since:1, retiredIn:3,
      note:"M04 경고 안에 흡수됨" }
  ]
};
```

`uid.js`가 부팅 시 `byId` 인덱스를 만들고, `audit()`으로 DOM과 대조해 불일치를 콘솔 경고 + P10에 표시한다. 레지스트리 갱신은 화면 코드 수정과 **같은 커밋**에서 이뤄져야 하며, 이를 지키게 하는 장치가 런타임 감사다.

### 4.3 반복 주기 절차

각 검증 라운드마다:
1. 소유자가 `Shift+E` → 마크다운을 채팅에 붙여넣음.
2. 내가 반영 → 삭제된 요소는 `retired`, 신규는 다음 빈 번호, `version` +1.
3. 변경 요약을 `CHANGELOG` 섹션(레지스트리 상단 주석)에 `v2: P04-B02 폐기, P05-F05 신규` 형태로 남김.
4. 소유자는 P10에서 "이번에 바뀐 ID"만 필터해 확인.

---

## 5. 초안 ID 레지스트리

> 상태는 모두 `활성(v1)`. 화면 표시 순서는 행 순서를 따른다.

### P00 — 앱 셸 (전역 크롬)

| ID | 종류 | 화면 | 한글 라벨 | 설명 |
|---|---|---|---|---|
| P00 | 화면 | — | 앱 셸 | 앱바 + 탭바 + 개발자 독을 담는 전역 프레임 |
| P00-C01 | 카드 | P00 | 상단 앱바 | 화면 제목 · 뒤로가기 · 테마 버튼 |
| P00-C02 | 카드 | P00 | 하단 탭바 | 5개 주요 화면 내비게이션 |
| P00-C03 | 카드 | P00 | 개발자 독 | 우하단 플로팅, ID/피드백 도구 모음 |
| P00-N01 | 내비 | P00 | 홈 | 대시보드(현재는 P02로 연결) |
| P00-N02 | 내비 | P00 | 플랜 | P06 플랜 결과로 이동 |
| P00-N03 | 내비 | P00 | 체크인 | P07 오늘 체크인 |
| P00-N04 | 내비 | P00 | 히스토리 | P08 추이 |
| P00-N05 | 내비 | P00 | 설정 | P09 |
| P00-B01 | 버튼 | P00 | 뒤로가기 | 이전 화면 복귀, 히스토리 스택 기반 |
| P00-B02 | 버튼 | P00 | ID 배지 토글 | Shift+I 와 동일 |
| P00-B03 | 버튼 | P00 | 피드백 모드 토글 | Shift+F 와 동일 |
| P00-B04 | 버튼 | P00 | 피드백 내보내기 | M91 오픈 |
| P00-B05 | 버튼 | P00 | ID 인덱스 | P10으로 점프 |
| P00-B06 | 버튼 | P00 | 단축키 도움말 | M92 오픈 |
| P00-B07 | 버튼 | P00 | 라이트/다크 전환 | 배지 대비 검증용으로도 사용 |

### P01 — 온보딩 / 기본 정보

| ID | 종류 | 화면 | 한글 라벨 | 설명 |
|---|---|---|---|---|
| P01 | 화면 | — | 온보딩 | 최초 1회, 이후 P09에서 수정 |
| P01-C01 | 카드 | P01 | 서비스 소개 히어로 | 한 줄 가치 제안 |
| P01-C02 | 카드 | P01 | 3단계 안내 | 사진 → 목표 → 플랜 |
| P01-C03 | 카드 | P01 | 기본 정보 입력 섹션 | 아래 F01~F06을 담음 |
| P01-F01 | 입력 | P01 | 닉네임 | 선택 사항 |
| P01-F02 | 입력 | P01 | 성별 | 대사량·플랜 계산에 사용 |
| P01-F03 | 입력 | P01 | 생년 / 나이 | BMR 추정 입력값 |
| P01-F04 | 입력 | P01 | 키(cm) | BMI·FFMI 계산용 |
| P01-F05 | 입력 | P01 | 활동 수준 | 좌식~고활동 5단계, TDEE 계수 |
| P01-F06 | 입력 | P01 | 운동 경력 | 초/중/상급, 볼륨 처방에 반영 |
| P01-B01 | 버튼 | P01 | 시작하기 | P02로 진행 |
| P01-B02 | 버튼 | P01 | 나중에 입력 | 스킵하고 P02로 |
| P01-B03 | 버튼 | P01 | 데모 데이터로 둘러보기 | 목업 인바디 3회분 주입 |

### P02 — 인바디 사진 업로드

| ID | 종류 | 화면 | 한글 라벨 | 설명 |
|---|---|---|---|---|
| P02 | 화면 | — | 인바디 업로드 | 플로우 진입점 |
| P02-C01 | 카드 | P02 | 업로드 드롭존 | 드래그&드롭 + 탭 영역 |
| P02-C02 | 카드 | P02 | 선택된 사진 미리보기 | 썸네일 + 파일명 + 용량 |
| P02-C03 | 카드 | P02 | 분석 진행 상태 | 스텁 OCR 진행 바(가짜 3초) |
| P02-B01 | 버튼 | P02 | 사진 촬영 | M01 오픈 (모바일 카메라) |
| P02-B02 | 버튼 | P02 | 갤러리/파일 선택 | file input 트리거 |
| P02-B03 | 버튼 | P02 | 촬영 가이드 보기 | M02 오픈 |
| P02-B04 | 버튼 | P02 | 수치 직접 입력 | M03 오픈, 사진 없이 진행 |
| P02-B05 | 버튼 | P02 | 분석 시작 | 스텁 OCR 실행 후 P03 |
| P02-B06 | 버튼 | P02 | 사진 제거 | 선택 해제 |
| P02-L01 | 리스트 | P02 | 최근 스캔 목록 | 과거 업로드 3건, 재사용 가능 |
| P02-F01 | 입력 | P02 | 측정일시 | 사진에서 못 읽을 때 수동 지정 |

### P03 — 스캔 검수 (OCR 결과 확인·보정)

| ID | 종류 | 화면 | 한글 라벨 | 설명 |
|---|---|---|---|---|
| P03 | 화면 | — | 스캔 검수 | **인식값 신뢰 확보 구간 — 가장 중요** |
| P03-C01 | 카드 | P03 | 원본 이미지 뷰어 | 인식 영역 박스 오버레이 |
| P03-C02 | 카드 | P03 | 핵심 3지표 카드 | 체중·골격근량·체지방량 강조 |
| P03-C03 | 카드 | P03 | 상세 지표 카드 | PBF/BMI/FFM/BMR 등 |
| P03-C04 | 카드 | P03 | 부위별 근육 분석 | 오른팔·왼팔·몸통·오른다리·왼다리 |
| P03-C05 | 카드 | P03 | 부위별 지방 분석 | 동일 5부위 |
| P03-C06 | 카드 | P03 | 인식 신뢰도 요약 배너 | 저신뢰 항목 개수 안내 |
| P03-F01 | 입력 | P03 | 체중 (kg) | 편집 가능, 0.1 단위 |
| P03-F02 | 입력 | P03 | 골격근량 SMM (kg) | 사용자가 말한 "근력량"의 실제 필드 |
| P03-F03 | 입력 | P03 | 체지방량 BFM (kg) | |
| P03-F04 | 입력 | P03 | 체지방률 PBF (%) | BFM/체중 자동 검산 |
| P03-F05 | 입력 | P03 | BMI | 키 기반 자동 검산 |
| P03-F06 | 입력 | P03 | 제지방량 FFM (kg) | 체중−BFM 검산 |
| P03-F07 | 입력 | P03 | 기초대사량 BMR (kcal) | 목표 칼로리 산출 기준 |
| P03-F08 | 입력 | P03 | 내장지방레벨 VFL | |
| P03-F09 | 입력 | P03 | 체수분 TBW (L) | |
| P03-F10 | 입력 | P03 | 단백질 (kg) | |
| P03-F11 | 입력 | P03 | 무기질 (kg) | |
| P03-F12 | 입력 | P03 | 복부지방률 WHR | |
| P03-F13 | 입력 | P03 | InBody 점수 | |
| P03-F14 | 입력 | P03 | 측정일시 | |
| P03-G01 | 차트 | P03 | 체성분 구성 막대 | 근육/지방/체수분 비율 |
| P03-G02 | 차트 | P03 | 부위별 균형 차트 | 좌우 비대칭 시각화 |
| P03-B01 | 버튼 | P03 | 이미지 확대/회전 | 뷰어 컨트롤 |
| P03-B02 | 버튼 | P03 | 저신뢰 항목만 보기 | 필터 토글 |
| P03-B03 | 버튼 | P03 | 전체 재인식 | 스텁 OCR 재실행 |
| P03-B04 | 버튼 | P03 | 값 초기화 | 편집 취소, 원 인식값 복원 |
| P03-B05 | 버튼 | P03 | 확인하고 목표 설정 | P04로 진행 |
| P03-B06 | 버튼 | P03 | 이 측정 삭제 | M09 확인 후 P02 복귀 |

### P04 — 목표 설정

| ID | 종류 | 화면 | 한글 라벨 | 설명 |
|---|---|---|---|---|
| P04 | 화면 | — | 목표 설정 | 체중·골격근량·체지방량 목표 |
| P04-T01 | 탭 | P04 | 절대값 입력 | "68kg" 방식 |
| P04-T02 | 탭 | P04 | 변화량 입력 | "−4kg" 방식 (사용자 요청 표현) |
| P04-C01 | 카드 | P04 | 현재 수치 요약 | P03 확정값 표시 |
| P04-C02 | 카드 | P04 | 목표 입력 섹션 | F01~F05 |
| P04-C03 | 카드 | P04 | 주당 변화량 계산 결과 | kg/주, 체중 대비 % |
| P04-C04 | 카드 | P04 | 현실성 판정 배너 | 안전/주의/위험 3단계 |
| P04-F01 | 입력 | P04 | 목표 체중 | 슬라이더 + 숫자 동기화 |
| P04-F02 | 입력 | P04 | 목표 골격근량 | |
| P04-F03 | 입력 | P04 | 목표 체지방량 | |
| P04-F04 | 입력 | P04 | 목표 기간 (주) | 4~52주 |
| P04-F05 | 입력 | P04 | 우선순위 | 감량 / 증량 / 리컴프 |
| P04-F06 | 입력 | P04 | 체지방률 목표 (%) | F03과 양방향 연동 |
| P04-B01 | 버튼 | P04 | 값 ±0.5 스테퍼 | 각 필드 좌우 증감 |
| P04-B02 | 버튼 | P04 | 추천 목표 자동 채우기 | 현재 수치 기반 안전 범위 제안 |
| P04-B03 | 버튼 | P04 | 현실성 근거 보기 | M04 오픈 |
| P04-B04 | 버튼 | P04 | 목표 초기화 | |
| P04-B05 | 버튼 | P04 | 다음: 강도 선택 | P05로 |
| P04-G01 | 차트 | P04 | 목표 궤적 예상 | 주차별 3지표 예상선 |
| P04-G02 | 차트 | P04 | 현재↔목표 비교 막대 | |

### P05 — 실현 강도 선택 (상 / 중 / 하)

| ID | 종류 | 화면 | 한글 라벨 | 설명 |
|---|---|---|---|---|
| P05 | 화면 | — | 실현 강도 선택 | 사용자 요청의 핵심 분기 |
| P05-C01 | 카드 | P05 | 강도 개념 설명 헤더 | "무엇을 감수할지 고르는 화면" |
| P05-C02 | 카드 | P05 | 하(下) — 지속 가능형 | 주 3회 / 느슨한 식단 |
| P05-C03 | 카드 | P05 | 중(中) — 균형형 | 주 4~5회 / 중간 적자 |
| P05-C04 | 카드 | P05 | 상(上) — 공격형 | 주 5~6회 / 엄격 식단 |
| P05-C05 | 카드 | P05 | 개인 제약 섹션 | F01~F04 |
| P05-B01 | 버튼 | P05 | 하 선택 | |
| P05-B02 | 버튼 | P05 | 중 선택 | |
| P05-B03 | 버튼 | P05 | 상 선택 | |
| P05-B04 | 버튼 | P05 | 세 강도 비교 보기 | M05 오픈 |
| P05-B05 | 버튼 | P05 | 제약 조건 편집 | M11 / M12 오픈 |
| P05-B06 | 버튼 | P05 | 플랜 생성 | 로딩 후 P06 — **최종 액션** |
| P05-F01 | 입력 | P05 | 주당 운동 가능 일수 | 1~7 |
| P05-F02 | 입력 | P05 | 회당 운동 가능 시간 | 30/45/60/90분 |
| P05-F03 | 입력 | P05 | 식단 엄격도 | 느슨 / 보통 / 엄격 |
| P05-F04 | 입력 | P05 | 운동 환경 | 헬스장 / 홈 / 혼합 |
| P05-F05 | 입력 | P05 | 식사 횟수 | 3식 / 4식 / 5식 |
| P05-L01 | 리스트 | P05 | 강도별 요약 비교표 | 주당 감량·훈련일·적자 |
| P05-G01 | 차트 | P05 | 예상 달성 확률 게이지 | 목표+강도 조합 평가 |

### P06 — 플랜 결과 (운동 + 식단)

| ID | 종류 | 화면 | 한글 라벨 | 설명 |
|---|---|---|---|---|
| P06 | 화면 | — | 플랜 결과 | 앱의 산출물 |
| P06-T01 | 탭 | P06 | 요약 | 한눈 대시보드 |
| P06-T02 | 탭 | P06 | 운동 | 주간 프로그램 |
| P06-T03 | 탭 | P06 | 식단 | 칼로리·매크로·끼니 |
| P06-C01 | 카드 | P06 | 플랜 헤더 | 강도·기간·목표 요약 뱃지 |
| P06-C02 | 카드 | P06 | 주간 스플릿 개요 | 월~일 분할 방식 |
| P06-C03 | 카드 | P06 | 선택 요일 운동 상세 | 종목·세트·반복·휴식 |
| P06-C04 | 카드 | P06 | 일일 칼로리·매크로 | 목표 kcal / P·C·F g |
| P06-C05 | 카드 | P06 | 주차별 진행 로드맵 | 4주 단위 점진 과부하 |
| P06-C06 | 카드 | P06 | 주의사항·전제 | 계산 가정 명시 |
| P06-L01 | 리스트 | P06 | 요일별 운동 리스트 | 행 = 하루 |
| P06-L02 | 리스트 | P06 | 종목 리스트 | 행 = 운동 1종 |
| P06-L03 | 리스트 | P06 | 끼니별 식단 리스트 | 아침/점심/저녁/간식 |
| P06-L04 | 리스트 | P06 | 장보기 목록 | 주간 식재료 집계 |
| P06-G01 | 차트 | P06 | 매크로 도넛 | 탄·단·지 비율 |
| P06-G02 | 차트 | P06 | 예상 체성분 변화 | 주차별 3지표 라인 |
| P06-G03 | 차트 | P06 | 주간 훈련 볼륨 막대 | 부위별 세트 수 |
| P06-B01 | 버튼 | P06 | 종목 상세 보기 | M06 오픈 |
| P06-B02 | 버튼 | P06 | 종목 교체 | 대체 운동 제안 |
| P06-B03 | 버튼 | P06 | 음식 상세/대체 | M07 오픈 |
| P06-B04 | 버튼 | P06 | 플랜 저장 | localStorage 확정 |
| P06-B05 | 버튼 | P06 | 플랜 재생성 | 동일 조건 재계산 |
| P06-B06 | 버튼 | P06 | 강도 변경 | P05로 복귀 |
| P06-B07 | 버튼 | P06 | 목표 수정 | P04로 복귀 |
| P06-B08 | 버튼 | P06 | 내보내기/공유 | M08 오픈 |
| P06-B09 | 버튼 | P06 | 오늘 체크인 시작 | P07로 |
| P06-B10 | 버튼 | P06 | 장보기 목록 복사 | 클립보드 |

### P07 — 체크인 (일일 기록)

| ID | 종류 | 화면 | 한글 라벨 | 설명 |
|---|---|---|---|---|
| P07 | 화면 | — | 오늘 체크인 | 실행 추적 |
| P07-C01 | 카드 | P07 | 오늘 날짜 헤더 | 날짜 이동 포함 |
| P07-C02 | 카드 | P07 | 연속 기록 스트릭 | 며칠째 |
| P07-C03 | 카드 | P07 | 이번 주 요약 | 준수율·완료율 |
| P07-C04 | 카드 | P07 | 오늘 측정 입력 섹션 | F01~F03 |
| P07-F01 | 입력 | P07 | 오늘 체중 | |
| P07-F02 | 입력 | P07 | 오늘 골격근량 | 인바디 측정일에만 |
| P07-F03 | 입력 | P07 | 오늘 체지방량 | |
| P07-F04 | 입력 | P07 | 컨디션 | 1~5 |
| P07-F05 | 입력 | P07 | 수면 시간 | |
| P07-F06 | 입력 | P07 | 식단 준수율 | 0~100% 슬라이더 |
| P07-F07 | 입력 | P07 | 메모 | 자유 텍스트 |
| P07-L01 | 리스트 | P07 | 오늘 운동 체크리스트 | 종목별 완료 체크 |
| P07-L02 | 리스트 | P07 | 오늘 식단 체크리스트 | 끼니별 완료 체크 |
| P07-B01 | 버튼 | P07 | 사진 첨부 | 눈바디/인바디 |
| P07-B02 | 버튼 | P07 | 전체 완료 처리 | 일괄 체크 |
| P07-B03 | 버튼 | P07 | 저장 | |
| P07-B04 | 버튼 | P07 | 오늘 건너뛰기 | 휴식일 처리 |
| P07-B05 | 버튼 | P07 | 플랜 조정 제안 보기 | 진행 지연 시 재계산 제안 |
| P07-G01 | 차트 | P07 | 주간 준수율 막대 | |

### P08 — 히스토리 / 추이

| ID | 종류 | 화면 | 한글 라벨 | 설명 |
|---|---|---|---|---|
| P08 | 화면 | — | 히스토리 | 변화 추적 |
| P08-T01 | 탭 | P08 | 그래프 | |
| P08-T02 | 탭 | P08 | 기록 목록 | |
| P08-T03 | 탭 | P08 | 사진 비교 | 전/후 |
| P08-C01 | 카드 | P08 | 기간 요약 카드 | 시작 대비 증감 |
| P08-C02 | 카드 | P08 | 목표 대비 진행률 | % 달성 |
| P08-F01 | 입력 | P08 | 기간 필터 | 1개월/3개월/6개월/전체 |
| P08-F02 | 입력 | P08 | 표시 지표 선택 | 다중 선택 |
| P08-G01 | 차트 | P08 | 체중 추이 | 목표선 오버레이 |
| P08-G02 | 차트 | P08 | 골격근량 추이 | |
| P08-G03 | 차트 | P08 | 체지방량 추이 | |
| P08-G04 | 차트 | P08 | 체지방률 추이 | |
| P08-G05 | 차트 | P08 | 목표 대비 진행 게이지 | |
| P08-L01 | 리스트 | P08 | 측정 기록 테이블 | 날짜별 전체 수치 |
| P08-L02 | 리스트 | P08 | 사진 타임라인 | 썸네일 그리드 |
| P08-B01 | 버튼 | P08 | 기록 상세 보기 | P03 읽기 모드로 |
| P08-B02 | 버튼 | P08 | 기록 삭제 | M09 확인 |
| P08-B03 | 버튼 | P08 | CSV 내보내기 | |
| P08-B04 | 버튼 | P08 | 두 시점 비교 | 사진/수치 나란히 |

### P09 — 설정

| ID | 종류 | 화면 | 한글 라벨 | 설명 |
|---|---|---|---|---|
| P09 | 화면 | — | 설정 | |
| P09-C01 | 카드 | P09 | 프로필 섹션 | P01 값 수정 |
| P09-C02 | 카드 | P09 | 표시 설정 섹션 | |
| P09-C03 | 카드 | P09 | 데이터 섹션 | |
| P09-C04 | 카드 | P09 | 개발자/검증 섹션 | 프로토타입 전용 |
| P09-C05 | 카드 | P09 | 앱 정보 | 버전·레지스트리 버전 |
| P09-F01 | 입력 | P09 | 단위 | kg / lb |
| P09-F02 | 입력 | P09 | 알림 시간 | 체크인 리마인더 |
| P09-F03 | 입력 | P09 | 테마 | 시스템/라이트/다크 |
| P09-F04 | 입력 | P09 | 주 시작 요일 | 월/일 |
| P09-F05 | 입력 | P09 | ID 배지 크기 | 9/10/11px |
| P09-F06 | 입력 | P09 | ID 배지 기본 표시 | 켜짐/꺼짐 |
| P09-B01 | 버튼 | P09 | 프로필 수정 | P01 재진입 |
| P09-B02 | 버튼 | P09 | 데이터 내보내기 | 전체 JSON |
| P09-B03 | 버튼 | P09 | 데이터 가져오기 | JSON 업로드 |
| P09-B04 | 버튼 | P09 | 전체 초기화 | M09 확인 필수 |
| P09-B05 | 버튼 | P09 | ID 인덱스 열기 | P10 |
| P09-B06 | 버튼 | P09 | 데모 데이터 재생성 | |
| P09-B07 | 버튼 | P09 | 피드백 전체 삭제 | M09 확인 |

### P10 — ID 인덱스 (검증 도구)

| ID | 종류 | 화면 | 한글 라벨 | 설명 |
|---|---|---|---|---|
| P10 | 화면 | — | ID 인덱스 | 전체 ID 디렉터리 |
| P10-C01 | 카드 | P10 | 커버리지 요약 | 총/활성/폐기/메모 수 |
| P10-C02 | 카드 | P10 | 드리프트 리포트 | 미등록·미구현·중복 |
| P10-F01 | 입력 | P10 | 검색 | ID·라벨·설명 대상 |
| P10-F02 | 입력 | P10 | 종류 필터 | P/M/B/F/C/T/N/L/G/A 칩 |
| P10-F03 | 입력 | P10 | 화면 필터 | |
| P10-F04 | 입력 | P10 | 상태 필터 | 활성/폐기/메모 있음 |
| P10-L01 | 리스트 | P10 | ID 테이블 | 전체 행 |
| P10-B01 | 버튼 | P10 | 행 복사 | `ID / 라벨` |
| P10-B02 | 버튼 | P10 | 해당 위치로 이동 | 딥링크 실행 |
| P10-B03 | 버튼 | P10 | 드리프트 검사 실행 | DOM ↔ 레지스트리 대조 |
| P10-B04 | 버튼 | P10 | 레지스트리 JSON 내보내기 | |
| P10-B05 | 버튼 | P10 | 전체 ID 목록 마크다운 복사 | 이 문서 표 형식 |

### 모달 / 팝업

| ID | 종류 | 화면 | 한글 라벨 | 설명 |
|---|---|---|---|---|
| M01 | 모달 | P02 | 사진 소스 선택 | 카메라 / 갤러리 / 파일 |
| M01-B01 | 버튼 | M01 | 카메라로 촬영 | |
| M01-B02 | 버튼 | M01 | 갤러리에서 선택 | |
| M01-B03 | 버튼 | M01 | 취소 | |
| M02 | 모달 | P02 | 인바디 촬영 가이드 | 인식률 높이는 법 |
| M02-C01 | 카드 | M02 | 좋은 예 / 나쁜 예 | |
| M02-B01 | 버튼 | M02 | 확인 | |
| M02-F01 | 입력 | M02 | 다시 보지 않기 | 체크박스 |
| M03 | 모달 | P02 | 수치 직접 입력 | 사진 없이 진행 |
| M03-F01 | 입력 | M03 | 체중 | |
| M03-F02 | 입력 | M03 | 골격근량 | |
| M03-F03 | 입력 | M03 | 체지방량 | |
| M03-F04 | 입력 | M03 | 측정일시 | |
| M03-B01 | 버튼 | M03 | 저장하고 계속 | |
| M03-B02 | 버튼 | M03 | 취소 | |
| M04 | 모달 | P04 | 목표 현실성 경고 | 주당 변화량 과다 시 |
| M04-C01 | 카드 | M04 | 근거 설명 | 안전 범위 기준 제시 |
| M04-B01 | 버튼 | M04 | 안전 목표로 조정 | 자동 보정 |
| M04-B02 | 버튼 | M04 | 그대로 진행 | 경고 무시 |
| M04-B03 | 버튼 | M04 | 목표 다시 수정 | 닫고 P04 유지 |
| M05 | 모달 | P05 | 강도 3종 상세 비교 | 상·중·하 나란히 |
| M05-L01 | 리스트 | M05 | 항목별 비교표 | |
| M05-B01 | 버튼 | M05 | 이 강도로 선택 | 각 열의 CTA |
| M05-B02 | 버튼 | M05 | 닫기 | |
| M06 | 모달 | P06 | 운동 종목 상세 | 자세·주의·대체 |
| M06-C01 | 카드 | M06 | 수행 방법 | |
| M06-C02 | 카드 | M06 | 타겟 근육 | |
| M06-L01 | 리스트 | M06 | 대체 종목 목록 | |
| M06-B01 | 버튼 | M06 | 이 종목으로 교체 | |
| M06-B02 | 버튼 | M06 | 닫기 | |
| M07 | 모달 | P06 | 음식 상세 / 대체 | 칼로리·매크로 |
| M07-C01 | 카드 | M07 | 영양 정보 | |
| M07-L01 | 리스트 | M07 | 대체 음식 목록 | 매크로 근사 순 |
| M07-F01 | 입력 | M07 | 섭취량 조정 | g / 인분 |
| M07-B01 | 버튼 | M07 | 교체 적용 | |
| M07-B02 | 버튼 | M07 | 닫기 | |
| M08 | 모달 | P06 | 플랜 내보내기 / 공유 | |
| M08-B01 | 버튼 | M08 | 텍스트로 복사 | |
| M08-B02 | 버튼 | M08 | 이미지로 저장 | 스텁 |
| M08-B03 | 버튼 | M08 | 닫기 | |
| M09 | 모달 | 공용 | 삭제/초기화 확인 | 파괴적 액션 공용 |
| M09-B01 | 버튼 | M09 | 삭제 | 위험색 |
| M09-B02 | 버튼 | M09 | 취소 | |
| M10 | 모달 | P09 | 단위 변경 확인 | 기존 기록 환산 안내 |
| M10-B01 | 버튼 | M10 | 변경 | |
| M10-B02 | 버튼 | M10 | 취소 | |
| M11 | 모달 | P05 | 식단 제약 설정 | 알레르기·비건·종교 |
| M11-F01 | 입력 | M11 | 알레르기 선택 | 다중 |
| M11-F02 | 입력 | M11 | 기피 식품 | 자유 입력 |
| M11-F03 | 입력 | M11 | 식이 유형 | 일반/베지테리언/비건 |
| M11-B01 | 버튼 | M11 | 적용 | |
| M11-B02 | 버튼 | M11 | 취소 | |
| M12 | 모달 | P05 | 부상·운동 제약 설정 | |
| M12-F01 | 입력 | M12 | 부상 부위 선택 | 어깨/허리/무릎 등 |
| M12-F02 | 입력 | M12 | 제외할 종목 | |
| M12-B01 | 버튼 | M12 | 적용 | |
| M12-B02 | 버튼 | M12 | 취소 | |
| M90 | 모달 | 공용 | 피드백 메모 팝오버 | 요소에 앵커링 |
| M90-C01 | 카드 | M90 | 대상 ID 헤더 | `P03-F02 · 골격근량 입력` |
| M90-F01 | 입력 | M90 | 메모 본문 | textarea |
| M90-F02 | 입력 | M90 | 심각도 | 치명/중요/사소/아이디어 |
| M90-F03 | 입력 | M90 | 상태 | 열림/해결 |
| M90-L01 | 리스트 | M90 | 기존 메모 목록 | 수정·삭제 |
| M90-B01 | 버튼 | M90 | 저장 | Ctrl+Enter |
| M90-B02 | 버튼 | M90 | 삭제 | |
| M90-B03 | 버튼 | M90 | 취소 | Esc |
| M91 | 모달 | 공용 | 피드백 내보내기 | |
| M91-C01 | 카드 | M91 | 마크다운 미리보기 | |
| M91-F01 | 입력 | M91 | 딥링크 포함 | 체크박스 |
| M91-F02 | 입력 | M91 | 해결 항목 포함 | 체크박스 |
| M91-B01 | 버튼 | M91 | 마크다운 복사 | |
| M91-B02 | 버튼 | M91 | .md 다운로드 | |
| M91-B03 | 버튼 | M91 | JSON 내보내기 | |
| M91-B04 | 버튼 | M91 | 전체 메모 삭제 | M09 경유 |
| M91-B05 | 버튼 | M91 | 닫기 | |
| M92 | 모달 | 공용 | 단축키 도움말 | |
| M92-L01 | 리스트 | M92 | 단축키 목록 | |
| M92-B01 | 버튼 | M92 | 닫기 | |

### 토스트 / 전역 알림

| ID | 종류 | 화면 | 한글 라벨 | 설명 |
|---|---|---|---|---|
| A01 | 알림 | 공용 | 저장 완료 | |
| A02 | 알림 | 공용 | 저장 실패 | localStorage 용량 초과 등 |
| A03 | 알림 | P02 | 지원하지 않는 파일 형식 | |
| A04 | 알림 | P02 | 파일 용량 초과 | |
| A05 | 알림 | P03 | 인식 신뢰도 낮음 | 검수 유도 |
| A06 | 알림 | P03 | 수치 검산 불일치 | 예: BFM+FFM ≠ 체중 |
| A07 | 알림 | P04 | 목표가 안전 범위를 벗어남 | |
| A08 | 알림 | P05 | 제약과 강도가 충돌 | 예: 주 2일인데 상 |
| A09 | 알림 | P06 | 플랜 생성 완료 | |
| A10 | 알림 | P07 | 오늘 체크인 저장됨 | |
| A11 | 알림 | P08 | 기록 삭제됨 (되돌리기) | |
| A90 | 알림 | 공용 | ID 복사됨 | 피드백 시스템 |
| A91 | 알림 | 공용 | 피드백 저장됨 | |
| A92 | 알림 | 공용 | 딥링크 대상 없음 | 폐기/미구현 ID |
| A93 | 알림 | 공용 | 복사 실패 — 수동 복사 필요 | `file://` 폴백 |

**합계 202행** (화면 11 · 모달 15 · 토스트 14 · 리프 162).

---

## 6. 구현 방식 (zero-build 실코드)

### 6.1 HTML 마크업 규약

모든 화면은 **DOM에 동시에 존재**하고 `hidden` 속성으로 숨긴다. 이유: 드리프트 감사(`audit()`)가 전체 ID를 한 번에 실측할 수 있고, 딥링크가 렌더 타이밍 경쟁 없이 동작한다.

```html
<body>
  <header data-uid="P00-C01"> … </header>

  <main id="screens">
    <section class="screen" id="P03" data-uid="P03" hidden>
      <div class="card" data-uid="P03-C02">
        <label for="f-smm">골격근량 (kg)</label>
        <input id="f-smm" type="number" step="0.1" data-uid="P03-F02">
      </div>
      <button class="btn-primary" data-uid="P03-B05">확인하고 목표 설정</button>
    </section>
  </main>

  <nav data-uid="P00-C02"> … </nav>

  <script src="uid-registry.js"></script>
  <script src="app.js"></script>
  <script src="uid.js"></script>
</body>
```

규약 3가지:
- **`data-uid` 하나만** 쓴다. `id` 속성과 섞지 않는다 (CSS/JS가 `id`를 쓰면 ID 체계가 코드 구조에 묶여 리팩터링이 막힌다). 화면 루트만 예외적으로 `id`를 겸한다(해시 라우팅 대상).
- 화면 루트는 `data-uid="P03"` (리프 세그먼트 없음).
- 동적 생성 행은 렌더 시 `data-uid="P06-L01" data-uid-index="3"` → JS가 배지 텍스트를 `P06-L01#3`으로 만든다.

### 6.2 CSS (`uid.css`)

```css
:root{
  --uid-badge-fs: 9px;
  --uid-z: 2147483000;
  --uid-P:#6D28D9; --uid-M:#BE185D; --uid-B:#1D4ED8; --uid-F:#0F766E;
  --uid-C:#92400E; --uid-T:#0E7490; --uid-N:#4338CA; --uid-L:#334155;
  --uid-G:#7E22CE; --uid-A:#B91C1C;
  --uid-ring-in: rgba(255,255,255,.70);
  --uid-ring-out: rgba(0,0,0,.45);
}
@media (prefers-color-scheme: dark){
  :root:not([data-theme="light"]){ --uid-ring-in: rgba(255,255,255,.55); --uid-ring-out: rgba(0,0,0,.60); }
}
:root[data-theme="dark"]{ --uid-ring-in: rgba(255,255,255,.55); --uid-ring-out: rgba(0,0,0,.60); }

html{ overflow-x: clip; }                 /* 배지 돌출이 가로 스크롤을 만들지 않게 */
.uid-anchored{ position: relative; }       /* JS가 static 요소에만 부여 */
.uid-wrap{ position: relative; display: inline-block; }  /* input/canvas 등 래퍼 */
.uid-wrap.is-block{ display: block; }

.uid-badge{
  position: absolute;
  z-index: var(--uid-z);
  display: none;                            /* 기본 OFF: 렌더 트리에서 제외 */
  align-items: center;
  box-sizing: content-box;
  max-width: 4ch; overflow: hidden; white-space: nowrap;
  padding: 1px 3px; border-radius: 3px;
  font: 600 var(--uid-badge-fs)/1 ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
  font-variant-numeric: tabular-nums;
  letter-spacing: .02em;
  color: #fff;
  background: var(--uid-c, var(--uid-L));
  box-shadow: 0 0 0 1px var(--uid-ring-in), 0 0 0 2px var(--uid-ring-out);
  opacity: .72;
  cursor: copy;
  user-select: none;
  pointer-events: auto;
  transition: opacity .12s ease, transform .12s ease, max-width .18s ease;
}
html.uid-on .uid-badge{ display: inline-flex; }

/* 위치 변형 — 깊이 오프셋(--uid-dy) 포함 */
.uid-badge[data-uid-pos="tl"]   { top: calc(-6px + var(--uid-dy,0px)); left: -6px;  transform-origin: top left; }
.uid-badge[data-uid-pos="tr"]   { top: calc(-5px + var(--uid-dy,0px)); right:-5px;  transform-origin: top right; }
.uid-badge[data-uid-pos="tl-in"]{ top: calc(2px + var(--uid-dy,0px));  left:  2px;  transform-origin: top left; }
.uid-badge[data-uid-pos="tr-in"]{ top: calc(2px + var(--uid-dy,0px));  right: 2px;  transform-origin: top right; }

.uid-badge__label{ max-width:0; overflow:hidden; opacity:0; transition: max-width .18s ease, opacity .12s ease; }
[data-uid]:hover > .uid-badge{ opacity: 1; transform: scale(1.25); }
.uid-badge:hover, .uid-badge:focus-visible{
  opacity: 1; transform: scale(1.3); max-width: 20ch; z-index: calc(var(--uid-z) + 10);
}
.uid-badge:hover .uid-badge__label,
.uid-badge:focus-visible .uid-badge__label{ max-width: 16ch; opacity: 1; margin-left: 3px; }
.uid-badge:focus-visible{ outline: 2px solid #fff; outline-offset: 1px; }

/* 메모가 달린 요소 */
.uid-badge.has-note{ background: var(--uid-A); }
.uid-badge.has-note .uid-badge__count::before{ content:"●"; margin-left:2px; }

/* 피드백 모드 */
html.uid-fb [data-uid]{ outline: 1px dashed rgba(190,24,93,.35); outline-offset: 2px; }
html.uid-fb #screens *{ cursor: crosshair !important; }

/* 딥링크 하이라이트 */
@keyframes uid-flash{
  0%,100%{ box-shadow: 0 0 0 0 rgba(29,78,216,0); }
  25%,65%{ box-shadow: 0 0 0 4px rgba(29,78,216,.55); }
}
.uid-flash{ animation: uid-flash 1.2s ease-out 2; border-radius: 6px; }

@media (prefers-reduced-motion: reduce){
  .uid-badge, .uid-badge__label{ transition: none; }
  .uid-flash{ animation: none; outline: 3px solid rgba(29,78,216,.7); }
}
@media print{ .uid-badge{ display: none !important; } }
```

### 6.3 JS 코어 (`uid.js`) — 배지 주입

```js
const UID = (() => {
  const K_BADGE='mybody.uid.badges.v1', K_FB='mybody.uid.feedback.v1';
  const REG = window.UID_REGISTRY || {version:0, items:[], screens:{}};
  const BY_ID = Object.fromEntries(REG.items.map(i => [i.id, i]));
  const REPLACED = /^(INPUT|IMG|CANVAS|SELECT|TEXTAREA|VIDEO|IFRAME|PROGRESS|METER|SVG)$/;
  const POS = {P:'tl', M:'tl', C:'tl', L:'tl', G:'tl', B:'tr', F:'tr', N:'tr', T:'tr', A:'tr'};

  const typeOf = id => { const last = id.split('-').pop(); return last[0]; };
  const labelOf = id => (BY_ID[id]?.label) || '(미등록)';
  const screenOf = id => { const s = id.split('-')[0]; return `${s} ${REG.screens[s]?.label ?? ''}`.trim(); };

  function depthOf(el){
    let d = 0, p = el.parentElement;
    while (p){ if (p.hasAttribute?.('data-uid')) d++; p = p.parentElement; }
    return d;
  }

  function decorate(root = document){
    root.querySelectorAll('[data-uid]:not([data-uid-ready])').forEach(el => {
      el.setAttribute('data-uid-ready','');
      const base = el.dataset.uid;
      const idx  = el.dataset.uidIndex;
      const id   = idx ? `${base}#${idx}` : base;
      const type = typeOf(base);

      // 1) 배지를 담을 앵커 확보
      let host = el;
      if (REPLACED.test(el.tagName)){
        const w = document.createElement('span');
        w.className = 'uid-wrap';
        if (getComputedStyle(el).display !== 'inline') w.classList.add('is-block');
        el.parentNode.insertBefore(w, el); w.appendChild(el);
        host = w;
      } else if (getComputedStyle(el).position === 'static'){
        el.classList.add('uid-anchored');
      }

      // 2) 배지 생성
      const b = document.createElement('span');
      b.className = 'uid-badge';
      b.dataset.uidFor = id;
      b.dataset.uidPos = POS[type] || 'tr';
      b.setAttribute('aria-hidden','true');
      b.tabIndex = -1;
      b.title = '클릭: ID 복사 · Shift+클릭: 메모 · Alt+클릭: 링크 복사';
      b.style.setProperty('--uid-c', `var(--uid-${type})`);
      b.style.setProperty('--uid-dy', `${depthOf(el) * 12}px`);

      const sid = document.createElement('span');
      sid.className = 'uid-badge__id'; sid.textContent = id;
      const slb = document.createElement('span');
      slb.className = 'uid-badge__label'; slb.textContent = labelOf(base);
      const cnt = document.createElement('span');
      cnt.className = 'uid-badge__count';
      b.append(sid, slb, cnt);

      host.appendChild(b);
    });
    fitBadges();
    refreshNoteMarks();
  }

  // 뷰포트 밖으로 삐져나간 배지는 안쪽으로 접기
  function fitBadges(){
    document.querySelectorAll('.uid-badge').forEach(b => {
      const r = b.getBoundingClientRect();
      if (!r.width) return;                       // 숨김 상태
      if (r.left < 0)  b.dataset.uidPos = 'tl-in';
      if (r.right > innerWidth) b.dataset.uidPos = 'tr-in';
      if (r.top  < 0)  b.dataset.uidPos = b.dataset.uidPos.endsWith('-in')
                          ? b.dataset.uidPos : b.dataset.uidPos + '-in';
    });
  }

  // 동적 렌더 대응
  new MutationObserver(ms => {
    for (const m of ms) for (const n of m.addedNodes)
      if (n.nodeType === 1) decorate(n.parentNode || document);
  }).observe(document.documentElement, {childList:true, subtree:true});

  return { decorate, labelOf, screenOf, BY_ID, REG };
})();
```

### 6.4 복사 — `file://` 폴백 필수

```js
async function uidCopy(text){
  try{
    if (window.isSecureContext && navigator.clipboard){
      await navigator.clipboard.writeText(text);
      return true;
    }
  }catch(_){}
  // file:// 은 secure context 가 아니라 clipboard API 가 없다 → execCommand 폴백
  const ta = document.createElement('textarea');
  ta.value = text;
  ta.setAttribute('readonly','');
  ta.style.cssText = 'position:fixed;top:0;left:-9999px;opacity:0';
  document.body.appendChild(ta);
  ta.select(); ta.setSelectionRange(0, text.length);
  let ok = false;
  try{ ok = document.execCommand('copy'); }catch(_){}
  ta.remove();
  return ok;
}
```

### 6.5 이벤트 배선 (캡처 단계)

```js
document.addEventListener('click', async (e) => {
  const badge = e.target.closest?.('.uid-badge');
  if (badge){
    e.preventDefault(); e.stopPropagation();
    const id = badge.dataset.uidFor, base = id.split('#')[0];
    if (e.shiftKey) return openNote(id);
    if (e.altKey){
      const url = location.href.split('#')[0] + '#' + base;
      return toast(await uidCopy(url) ? 'A90' : 'A93', url);
    }
    const line = `${id} / ${UID.labelOf(base)}`;
    return toast(await uidCopy(line) ? 'A90' : 'A93', line);
  }
  if (document.documentElement.classList.contains('uid-fb')){
    const host = e.target.closest?.('[data-uid]');
    if (host){
      e.preventDefault(); e.stopPropagation();        // 제품 동작 차단
      const idx = host.dataset.uidIndex;
      openNote(idx ? `${host.dataset.uid}#${idx}` : host.dataset.uid);
    }
  }
}, true);   // ← capture:true 가 핵심. 버튼 자신의 핸들러보다 먼저 잡아야 화면이 안 넘어간다.

addEventListener('keydown', (e) => {
  const t = e.target;
  const typing = /^(INPUT|TEXTAREA|SELECT)$/.test(t.tagName) || t.isContentEditable;
  if (e.key === 'Escape'){ return closeTop(); }
  if (typing || e.ctrlKey || e.metaKey || e.altKey || !e.shiftKey) return;
  switch (e.code){
    case 'KeyI': e.preventDefault(); toggleBadges(); break;
    case 'KeyF': e.preventDefault(); toggleFeedback(); break;
    case 'KeyK': e.preventDefault(); go('#P10'); break;
    case 'KeyE': e.preventDefault(); openModal('M91'); break;
    case 'KeyD': e.preventDefault(); toggleTheme(); break;
    case 'Slash': e.preventDefault(); openModal('M92'); break;
  }
});

function toggleBadges(force){
  const on = force ?? !document.documentElement.classList.contains('uid-on');
  document.documentElement.classList.toggle('uid-on', on);
  document.querySelectorAll('.uid-badge').forEach(b => b.tabIndex = on ? 0 : -1);
  try{ localStorage.setItem('mybody.uid.badges.v1', on ? '1' : '0'); }catch(_){}
  if (on) requestAnimationFrame(fitBadges);
}
```

### 6.6 메모 저장 · 내보내기 · 딥링크 · 감사

```js
const FB = {
  all(){ try{ return JSON.parse(localStorage.getItem('mybody.uid.feedback.v1') || '[]'); }
         catch(_){ return []; } },
  write(list){ try{ localStorage.setItem('mybody.uid.feedback.v1', JSON.stringify(list)); }
               catch(_){ toast('A02','저장 공간 부족'); } },
  save(n){
    const list = this.all();
    const i = list.findIndex(x => x.nid === n.nid);
    n.updatedAt = new Date().toISOString();
    i >= 0 ? (list[i] = n) : list.push(n);
    this.write(list); refreshNoteMarks();
  },
  forUid(id){ return this.all().filter(n => n.uid === id); }
};

function newNote(uid){
  const base = uid.split('#')[0];
  return { nid: 'n_' + Date.now().toString(36) + '_' + Math.random().toString(36).slice(2,6),
           uid, label: UID.labelOf(base), screen: UID.screenOf(base),
           text: '', severity: '중요', status: '열림',
           createdAt: new Date().toISOString(), updatedAt: null,
           registryVersion: UID.REG.version,
           viewport: `${innerWidth}x${innerHeight}` };
}

function exportMarkdown({deepLinks = false, includeDone = true} = {}){
  const RANK = {치명:0, 중요:1, 사소:2, 아이디어:3};
  const all = FB.all().filter(n => includeDone || n.status !== '해결');
  const groups = {};
  all.forEach(n => (groups[n.screen] ||= []).push(n));
  const count = s => all.filter(n => n.severity === s).length;

  let md = `# Mybody 프로토타입 피드백\n`
    + `- 일시: ${new Date().toLocaleString('ko-KR')}\n`
    + `- 레지스트리: v${UID.REG.version}\n`
    + `- 총 ${all.length}건 (치명 ${count('치명')} · 중요 ${count('중요')} · 사소 ${count('사소')} · 아이디어 ${count('아이디어')})\n\n`;

  Object.keys(groups).sort().forEach(screen => {
    md += `## ${screen} (${groups[screen].length}건)\n\n`;
    groups[screen]
      .sort((a,b) => (RANK[a.severity] - RANK[b.severity]) || a.uid.localeCompare(b.uid))
      .forEach(n => {
        const box = n.status === '해결' ? 'x' : ' ';
        const link = deepLinks ? ` ([열기](#${n.uid.split('#')[0]}))` : '';
        md += `- [${box}] **${n.uid}** · ${n.label} · \`${n.severity}\`${link}\n`;
        n.text.split('\n').forEach(l => md += `  > ${l}\n`);
        md += `\n`;
      });
  });
  return md;
}

// 딥링크
function go(hash){
  const m = String(hash).match(/^#?([PM]\d{2})(?:-([A-Z]\d{2}(?:#\d+)?))?$/);
  if (!m) return;
  const [, cid, leaf] = m;
  showScreen(cid);                                   // 모달이면 기저 화면 후 openModal
  if (!leaf) return;
  const full = `${cid}-${leaf}`;
  let tries = 0;
  (function seek(){
    const el = document.querySelector(`[data-uid="${full.split('#')[0]}"]`
      + (full.includes('#') ? `[data-uid-index="${full.split('#')[1]}"]` : ''));
    if (!el) return (++tries < 10) && requestAnimationFrame(seek), tries >= 10 && toast('A92', full);
    el.scrollIntoView({block:'center', behavior:'smooth'});
    el.classList.remove('uid-flash'); void el.offsetWidth; el.classList.add('uid-flash');
  })();
}
addEventListener('hashchange', () => go(location.hash));

// 레지스트리 드리프트 감사
function audit(){
  const dom = [...document.querySelectorAll('[data-uid]')].map(e => e.dataset.uid);
  const dupes   = [...new Set(dom.filter((v,i) => dom.indexOf(v) !== i))];
  const unreg   = [...new Set(dom.filter(id => !UID.BY_ID[id]))];
  const missing = UID.REG.items
    .filter(i => i.status === 'active' && !dom.includes(i.id))
    .map(i => i.id);
  if (dupes.length || unreg.length || missing.length)
    console.warn('[UID drift]', {dupes, unreg, missing});
  return {dupes, unreg, missing, total: UID.REG.items.length, inDom: new Set(dom).size};
}

addEventListener('DOMContentLoaded', () => {
  UID.decorate();
  let on = true; try{ on = localStorage.getItem('mybody.uid.badges.v1') !== '0'; }catch(_){}
  toggleBadges(on);
  audit();
  if (location.hash) go(location.hash);
});
addEventListener('resize', () => requestAnimationFrame(fitBadges), {passive:true});
```

### 6.7 왜 이 구조인가 (요약)

- **레지스트리는 JS 리터럴**: `file://`에서 `fetch('*.json')`은 CORS로 실패한다. 빌드 없는 환경의 유일한 정답.
- **전 화면 상시 DOM + `hidden`**: 감사·딥링크·배지 사전주입이 전부 공짜로 해결된다. 프로토타입 규모(200 ID)에서 성능 문제 없음.
- **캡처 단계 클릭 가로채기**: 피드백 모드에서 버튼을 눌러도 화면이 안 넘어가야 한다. 버블링 단계로는 이미 늦다.
- **MutationObserver**: 리스트 행이 나중에 그려져도 배지가 자동으로 붙는다.
- **`execCommand` 폴백**: 소유자가 `index.html`을 더블클릭해서 열 가능성이 매우 높다. 이게 없으면 "복사" 기능 전체가 죽는다.
- **`overflow-x: clip` + `fitBadges()`**: 배지가 레이아웃을 건드리지 않는다는 약속을 실제로 지키는 두 장치.