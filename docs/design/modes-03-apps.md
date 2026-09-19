# 앱 랜드스케이프 스윕 — 실제 피트니스/영양 앱들은 "목표 모드"를 어떻게 제시하는가

**조사자 노트 / 방법론 및 신뢰도 (먼저 읽을 것)**

이 환경의 **WebFetch는 egress proxy에 의해 전면 차단**되어 있습니다. `macrofactor.com`, `help.macrofactorapp.com`, `help.joincarbon.com`, `rpstrength.com`, `myinbody.com`, 심지어 `en.wikipedia.org`까지 모두 `EGRESS_BLOCKED`로 반려됐습니다. 따라서 **원문 페이지를 직접 읽은 것이 아니라, 검색 엔진이 그 페이지들로부터 합성해 준 발췌(snippet/summary)에만 근거**합니다.

표기 규칙:
- **[V]** = 복수 검색 결과에서 일관되게 확인됨, 1차 소스(해당 앱의 공식 도움말/블로그)가 결과에 포함됨
- **[V-partial]** = 1차 소스가 결과에 있었으나 발췌만 확보, 수치 일부는 미확인
- **[unverified]** = 확인 실패 또는 3자 블로그 단일 출처. 그때의 내 추론을 명시함
- 스크린샷은 확보 불가(WebFetch 차단). "화면 묘사"는 도움말 문서 발췌로부터 재구성한 것이며, 그렇게 표시합니다.

---

## 0. 한 문장 요약

> **업계 표준은 "모드"가 아니라 "방향(direction) + 속도(rate)"다.** 진지한 앱일수록 모드 개수가 적고(3~4개), 대신 *속도를 %체중/주 단위 연속값*으로 준다. `감량/리컴프/근성장/커팅` 같은 4분할을 **1급 개념으로 노출하는 메이저 영양 앱은 사실상 없다**. 그 4분할은 *코칭 언어*이지 *앱 UI 언어*가 아니었다. 단, 최근(2025~2026) 체성분 AI 앱들(GainFrame, LeanLens)이 정확히 오너가 원하는 것 — **데이터로부터 모드를 자동 추천** — 을 하기 시작했고, 이쪽이 우리의 진짜 선행 사례다.

---

## 1. MacroFactor — 가장 정교한 "모드 없는" 모델

출처: [macrofactor.com/goal-features](https://macrofactor.com/goal-features/), [MacroFactor's Algorithms and Core Philosophy](https://macrofactor.com/macrofactors-algorithms-and-core-philosophy/), [help: Set a New Goal](https://help.macrofactorapp.com/en/articles/90-set-a-new-goal), [help: Program Styles](https://help.macrofactorapp.com/macro_program/program_styles), [help: Dynamic Maintenance](https://help.macrofactorapp.com/en/articles/125-how-does-dynamic-maintenance-work-in-macrofactor), [FeastGood 튜토리얼](https://feastgood.com/macrofactor-guide/)

### 1.1 노출하는 목표 타입 — **정확히 3개** [V]

`Lose weight` / `Maintain weight` / `Gain weight`.

그게 전부입니다. **cut / bulk / recomp / mini-cut 같은 이름은 앱 안에 없습니다.** 증거 기반 피트니스 커뮤니티에서 가장 존경받는 트래커가 의도적으로 그 어휘를 UI에서 뺐다는 사실 자체가 설계 시그널입니다.

### 1.2 속도 선택 방식 — %체중/주 슬라이더 + "green range" [V]

- 목표 설정 마법사: ① 방향 선택 → ② 목표 체중 입력 → ③ **변화 속도를 "체중의 %/주"로 지정** → ④ 개인화된 일일 칼로리 예산 산출. [V]
- **절대값(kg/주)이 아니라 상대값(%BW/주)** 을 씁니다. 공식 설명의 예시 그대로: "주 0.5% 감량 목표라면, 체중이 줄면서 **절대 감량 속도도 함께 줄어든다**". [V]
- 슬라이더에 **녹색 권장 구간(green range)** 이 그려져 있고, "대부분의 사람은 **0.25–1 %BW/주**"를 권장. [V]
- 이 속도는 곧바로 "해당 칼로리 적자/잉여 크기"로 변환되어 소비량(expenditure)에서 가감됩니다. [V]

> **우리 엔진과의 대응**: MacroFactor의 `%BW/주 슬라이더` ≈ 우리의 `공격성 스칼라 a`. 다만 **MF는 그 슬라이더가 단백질·지방·유산소까지 함께 움직이지는 않습니다**(그건 프로그램 스타일이 따로 처리). 우리 `a`가 식단 파라미터 전체를 보간하는 건 MF보다 더 야심찬 설계입니다 — 그만큼 설명 책임도 큽니다.

### 1.3 Dynamic Maintenance — 유지도 "정적"이 아니다 [V]

`Maintain` 을 고르면 유지할 목표 체중을 지정하고, 주간 체크인마다 알고리즘이 추세 체중과 대사를 보고 **매크로 플랜을 미세 조정**합니다. 그래프도 하향 목표선이 아니라 **목표 체중 주변의 밴드(band)** 로 그려집니다. [V]

> **우리에게 직접 적용 가능한 아이디어**: 리컴프 모드의 진행 차트는 "선"이 아니라 **밴드**로 그려야 합니다. 체중이 안 변하는 게 성공인 모드에서 단일 목표선은 사용자에게 실패처럼 보입니다.

### 1.4 Program Styles — 모드 대신 "자율성 레벨" 3단계 [V]

| 스타일 | 주간 칼로리 조정 | 일일 매크로 결정 | 안전장치 |
|---|---|---|---|
| **Coached** | MF가 전담 | MF가 결정 | **일일 칼로리 하한(floor) 있음**, 지방 섭취 하한 보장 |
| **Collaborative** | MF가 전담 | 사용자가 결정 | **칼로리 floor 없음**, 지방 하한 보장 **없음** |
| **Manual** | 사용자 | 사용자 | 없음 |

[V] — "coached 프로그램에서는 일일 칼로리가 너무 낮아지지 않도록 floor를 설정할 수 있고, collaborative에는 daily calorie floor가 없다. 마찬가지로 정상적 호르몬·대사 기능에 일정 수준의 지방 섭취가 필요하므로 coached에서는 지방 섭취를 합리적 수준으로 유지하지만, collaborative를 고르면 그 안전망이 없다."

> **이건 "모드"의 또 다른 축입니다**: *얼마나 공격적인가*와 별개로 *얼마나 사용자에게 맡기는가*. 우리 앱은 1인용이므로 이 축은 접어도 됩니다. 다만 **"안전장치를 끌 수 있게 하되, 끄면 끈다고 명시적으로 말한다"** 는 패턴은 훔칠 가치가 있습니다.

### 1.5 자동 선택? — **앱 안에는 없고, 웹에 별도 퀴즈로 존재** [V-partial]

MacroFactor는 [Should I Bulk or Cut? (무료 퀴즈)](https://macrofactor.com/bulk-or-cut/) 를 **웹사이트에** 따로 운영합니다. 앱 온보딩에 통합되어 있지 않습니다. [V]

퀴즈의 전제와 결론 중 검색으로 확보한 것:
- 전제: **"당신이 웨이트 트레이닝(또는 구조화된 저항운동)을 하고 있다는 가정 하에 만들어졌다"** — 'bulk/cut' 어휘 자체가 저항운동 서브컬처 전용이라는 이유로 명시. [V]
- 결론: **"대부분의 사람에게 MacroFactor의 실제 조언은, 둘 중 더 설레는 쪽을 고르라는 것이다."** [V]

> 이건 냉소가 아니라 중요한 데이터입니다. **업계 최고 수준의 증거 기반 팀이, 자동 추천의 한계를 스스로 인정하고 "동기(motivation)"를 최종 tie-breaker로 둡니다.** 우리 자동 선택기도 마지막에 "둘 다 성립합니다 — 어느 쪽이 더 하고 싶으세요?" 를 말할 수 있어야 합니다. 침묵하는 자동 선택보다 정직합니다.

### 1.6 리컴프에 대한 MF의 입장 — "모드가 아니라 알고리즘이 견뎌야 할 노이즈" [V]

전용 도움말이 있습니다: [How do MacroFactor's Algorithms Respond to Body Recomposition](https://help.macrofactorapp.com/en/articles/220-how-do-macrofactor-s-algorithms-respond-to-body-recomposition)

확보한 수치 [V]:
- 리컴프 중이면 **체중이 안 변해도 실제로는 유의미한 적자** 상태일 수 있고, 체중계는 이를 감지 못 함.
- 극단적 리컴프 엣지 케이스에서 MF 소비량 추정 오차 **약 347 kcal/day (약 10%)**.
- 전형적 리컴프 속도에서는 오차 **약 108 kcal/day (약 3.5%)**.
- 비교군: 웨어러블은 **82%의 경우 10% 이상** 오차, 정적 공식은 평균 **약 325 kcal/day** 오차.

> **핵심 함의**: MF는 리컴프를 *모드*로 만들지 않고, *자기 추정기가 견뎌야 할 오차원*으로 취급합니다. **우리는 InBody로 SMM/BFM을 직접 관측하므로 이 문제가 없습니다** — 이게 우리 앱의 구조적 우위이고, 리컴프를 1급 모드로 둘 수 있는 근거입니다. 체중계만 있는 앱은 리컴프 모드를 만들어도 **진척을 측정할 수단이 없습니다.**

### 1.7 ⚠️ MF가 우리 앱의 전제를 정면으로 공격하는 글이 있음

[Body Composition Assessments are Less Useful Than You Think](https://macrofactor.com/body-composition/) — 제목 그대로입니다. 본문 확보 실패 [unverified 본문], 그러나 **제목과 MF의 일관된 논조로 볼 때, BIA/InBody 측정치를 목표 설정의 기준으로 삼는 것에 대한 반론**입니다.

> **정직한 보고**: 우리 앱의 전제(= InBody 수치를 목표로 받는다)는 업계 최고 수준 팀이 명시적으로 회의하는 접근입니다. 이미 `planning-engine.md §0.2`가 노이즈 바닥(±1.0kg 체중 / ±0.5kg SMM / ±1.0kg BFM)을 두고 "2주 미만 재측정은 추세 판단에 쓰지 않는다"고 한 것은 **정확히 옳은 방어**입니다. 모드 자동 선택기도 **같은 dead-zone을 반드시 통과시켜야 합니다** — 아니면 측정 노이즈가 모드를 뒤집습니다(§7.2 참조).

---

## 2. Renaissance Periodization — **유일하게 진짜 "페이즈 모델"을 파는 앱**

출처: [RP: Why Massing is Beneficial](https://rpstrength.com/blogs/articles/why-massing-is-beneficial), [RP: Tips for a Productive Mass Phase](https://rpstrength.com/blogs/articles/tips-productive-mass-phase), [RP Hypertrophy App](https://rpstrength.com/pages/hypertrophy-app), [BodySpec: RP Principles and Guide](https://www.bodyspec.com/blog/post/renaissance_periodization_principles_and_guide), [RP Facebook: maintenance periods](https://www.facebook.com/RenaissancePeriodization/posts/1999459866737860/), [RP Diet Coach on Google Play](https://play.google.com/store/apps/details?id=com.rp.rpdiet)

### 2.1 페이즈 3종 [V]

`Cut (fat loss)` / `Maintenance` / `Mass (massing / muscle gain)`. **각각 플랜 구조 자체가 다릅니다** — 같은 알고리즘에 부호만 바꾼 게 아니라, 식사 구성 템플릿이 다릅니다. [V]

추가로 RP의 플랜은 **훈련일 / 휴식일 식단이 다르고, 그날 어떤 종류의 훈련을 했는지에 따라 조정**됩니다. [V]

### 2.2 기간(duration) — **이게 RP 모델의 핵심이고, 우리가 가장 크게 배울 부분** [V]

검색으로 확보한 수치:

| 항목 | RP 권장 |
|---|---|
| massing / cutting 다이어트 1회 | **약 3~6개월** |
| 3개월 구간 기대 변화량 | **5~25 lb (2.3~11.3 kg)** — 체격·소비량·목표에 따라 |
| **cut 최대 연속 기간** | **12주를 넘기지 말 것** |
| cut 12주 후에도 더 빼야 하면 | **12주 maintenance** 로 대사·NEAT 회복 → 더 높은 섭취량에서 새 감량기 시작 |
| mass phase 직후 | **1~3개월 maintenance** (mass 길이에 비례) |
| maintenance 다음 | cut — 늘린 근육을 지키며 불필요한 지방 제거 |
| 컷 직후 권장 massing 속도 | **약 0.5 %BW/주, 약 2개월** |

### 2.3 조정 알고리즘 [V]

**점진적(progressive)**. 주 단위로 식사량을 조금씩 조정 — 컷에서는 대사 둔화 위험을 낮추고, mass에서는 과도한 잉여를 방지. [V]

### 2.4 자동 선택? — **없음. 사용자가 페이즈를 고르고, 앱은 그 안에서 코칭** [V-partial]

RP Hypertrophy 앱의 "Maintenance Phase" 운용은 공식 기능이 아니라 **커뮤니티 포럼 질문으로 존재**합니다([hypertrophy.zendesk.com 커뮤니티 포스트](https://hypertrophy.zendesk.com/hc/en-us/community/posts/22316645578007-Maintenance-Phase-using-Hypertrophy-App)) — 즉 **훈련 앱 쪽에서는 maintenance가 1급 시민이 아닙니다.** [V-partial]

> **우리에게 주는 3가지 교훈**
> 1. **모드에는 반드시 "최대 지속 기간"이 있어야 한다.** cut 12주 상한은 업계에서 가장 널리 인용되는 실무 규칙입니다. 우리 엔진은 `T_min × 2.0`(하 강도)이 12주를 넘을 수 있는데, 그때 **"이건 한 번의 컷이 아니라 컷→유지→컷 두 블록입니다"** 라고 말해야 합니다. 이미 `split` 전략이 있으니 자연스럽게 연결됩니다.
> 2. **maintenance는 "아무것도 안 하는 상태"가 아니라 처방된 페이즈다.** 우리 split 전략의 "유지 2주"는 RP 기준으로는 **너무 짧습니다**(RP는 mass 후 1~3개월, cut 12주 후 12주). 2주는 MATADOR류 diet break 근거에 가깝고, RP의 phase-transition maintenance와는 다른 물건입니다. **두 가지를 구분해서 이름 붙이세요.**
> 3. **RP는 "비율"로 말한다** — Legion도 같은 규칙을 씁니다: **벌크:컷 = 3~4 : 1** (예: 3~4개월 벌크 후 1개월 컷). 이건 자동 선택기의 훌륭한 sanity check입니다.

---

## 3. 나머지 앱들

### 3.1 Carbon Diet Coach (Layne Norton) — **4개 모드, 그리고 유일한 "reverse diet" 1급 모드**

출처: [joincarbon.com/how-it-works](https://www.joincarbon.com/how-it-works), [help: How to Create your Initial goal](https://help.joincarbon.com/en/articles/6040890-how-to-create-your-initial-goal), [help: What is a Reverse Diet?](https://help.joincarbon.com/en/articles/6004560-what-is-a-reverse-diet), [help: change to a reverse dieting goal](https://help.joincarbon.com/en/articles/6029884-how-to-change-to-a-reverse-dieting-goal), [help: change to a maintain weight goal](https://help.joincarbon.com/en/articles/6029883-how-to-change-to-a-maintain-weight-goal), [help: change to a weight loss goal](https://help.joincarbon.com/en/articles/6029872-how-to-change-to-a-weight-loss-goal), [help: change to a weight gain goal](https://help.joincarbon.com/en/articles/6029882-how-to-change-to-a-weight-gain-goal)

**모드 4종** [V]: `Lose weight` / `Gain weight` / `Maintain weight` / `Reverse diet`.

Carbon 자체 도움말이 위 네 개에 각각 별도 문서를 두고 있다는 점이 강한 증거입니다 (recomp 전용 문서는 검색 결과에 없음).

**결정적 사실**: **네 모드가 각각 다른 알고리즘을 씁니다.** [V] — 부호만 바뀌는 게 아닙니다.

각 모드의 성격 [V-partial, 3자 요약 경유]:
- **Fat Loss**: 지속 가능한 적자 + 단백질 최적화로 제지방 보존
- **Muscle Gain**: *통제된* 잉여 — 과잉 지방 축적 최소화
- **Maintenance**: 현 체성분 유지 + 장기 습관 형성
- **Reverse Diet**: **장기 칼로리 제한에서 회복 중인 사람 전용.** 빠른 지방 재증가 없이 점진적으로 칼로리를 올려 대사를 회복

> **⚠️ 확인 실패 항목**: 한 3자 블로그([nutrola.app](https://nutrola.app/en/blog/8-best-body-recomposition-apps-2026))가 "Carbon은 recomposition도 goal option으로 제공한다"고 주장하나, **Carbon 공식 도움말에는 recomp 전용 문서가 없고 위 4개만 확인됩니다**. → **[unverified]**. 내 판단: 3자 블로그의 오기이거나, "maintain" 모드를 recomp로 의역한 것으로 봅니다.
>
> **우리에게 주는 교훈 — 이게 오너의 4분할에 대한 가장 중요한 반례입니다.** Carbon은 4개 모드를 두되 그 4번째가 `커팅`이 아니라 **`reverse diet`** 입니다. 즉 업계가 실제로 "네 번째 모드"를 만들 가치가 있다고 판단한 지점은 **"감량과 커팅의 구분"이 아니라 "다이어트에서 빠져나오는 길"** 이었습니다. 오너의 4분할에는 **출구(exit)가 없습니다.** 이게 가장 큰 구멍입니다.

### 3.2 Stronger by Science / 관련 계산기 — 모드 없음, 속도 권고만

출처: [BarBend: Best Macros Calculator](https://barbend.com/best-macros-calculator/), [RippedBody Macro Calculator](https://rippedbody.com/macro-calculator/), [Macros Inc: Cut or Bulk](https://macrosinc.net/nutriwiki/cut-or-bulk/)

- **Eric Trexler (SbS)**: 근성장 시 **0.25–0.5 %BW/주** 증가 권장 (200 lb이면 주 0.5~1 lb). [V]
- 감량: **0.5–1 %BW/주** 가 안전·지속 가능. 그보다 빠르면 근손실 위험 + 유지 난이도. [V]
- 근성장 잉여: **+200~500 kcal** 이 최적. 더 큰 잉여는 지방만 더 붙음. [V]
- RippedBody 계산기는 Helms의 *The Muscle and Strength Pyramid: Nutrition* 의 매크로 설정 권고를 채택. [V]
- [unverified] 검색 결과가 "Greg Nuckols' MacroFactor BMR formulas"라고 썼는데 이건 문장이 뭉개진 것으로 보입니다. Nuckols는 SbS/MacroFactor 공동 인물이므로 "MacroFactor(=SbS 팀)가 쓰는 BMR 공식"이라는 뜻으로 읽는 게 타당하나, 어떤 공식인지는 확인 못 했습니다.

**모드 자동 선택: 없음.** 계산기는 입력을 받아 숫자를 뱉을 뿐입니다.

### 3.3 MyFitnessPal — 가장 단순하고, 가장 많이 쓰이고, 가장 거짓말하는 쪽

출처: [MFP help: How does MyFitnessPal calculate my initial goals?](https://support.myfitnesspal.com/hc/en-us/articles/360032625391-How-does-MyFitnessPal-calculate-my-initial-goals), [MFP help: A Message about updated nutrition goals](https://support.myfitnesspal.com/hc/en-us/articles/360032626031-A-Message-about-MyFitnessPal-s-updated-nutrition-goals), [MFP help: Customize your nutritional goals](https://support.myfitnesspal.com/hc/en-us/articles/360032274432-Customize-your-nutritional-goals)

- **모드 3종** [V]: `Lose weight` / `Maintain weight` / `Gain weight`.
- **속도**: "주당 몇 kg(lb) 감량/증량하고 싶은가"를 묻고, 그만큼을 칼로리에서 **정액 가감**. [V] — **%체중이 아니라 절대값**. 이게 MF와의 결정적 차이입니다.
- **칼로리 하한** [V]: 여성 **1,200 kcal**, 남성 **1,500 kcal** (과거엔 남녀 모두 1,200이었다가 남성만 1,500으로 상향). 이 아래는 권장하지 않음.
- **초기 목표 산출**: 나이·키·체중·성별·일상 활동 수준 → 유지 칼로리 → 주간 목표만큼 가감. [V]
- [unverified, 일반 지식] 선택지가 0.5 / 1 / 1.5 / 2 lb per week 로 제시되는 것으로 알고 있으나, 이번 검색으로는 증분값을 확정하지 못했습니다.
- **자동 선택: 없음.** 체성분 개념 자체가 없음.

> **MFP의 구조적 거짓말**: 절대값 속도(2 lb/주)를 고정하면 체중이 줄어도 적자 크기가 그대로라 **적자 비율이 계속 커집니다.** 100kg에서 -1000 kcal은 TDEE의 ~35%지만, 70kg에서 -1000 kcal은 ~48%입니다. 우리 엔진이 `%TDEE 적자`로 파라미터화하고 주차별로 TDEE를 갱신하는 건 **정확히 MFP가 틀린 지점을 고친 것**입니다. 이 점을 UI에서 한 줄로 자랑해도 됩니다.

### 3.4 Cronometer — 모드 없음, "타겟 편집기"

출처: [Cronometer help: Targets + Profile](https://support.cronometer.com/hc/en-us/articles/31308427612180-Targets-Profile), [Mobile - Macro & Energy Targets](https://support.cronometer.com/hc/en-us/articles/33113157685652-Mobile-Macro-Energy-Targets), [Macro Ratios](https://support.cronometer.com/hc/en-us/articles/360020446112-Macro-Ratios), [블로그: 매크로/미량영양 타겟 설정법](https://cronometer.com/blog/how-to-set-your-macro-and-micronutrient-targets/)

- **목표 모드 없음.** `More > Targets > Weight Goal` 에서 **목표 체중 + 원하는 증감 속도**만 지정. [V]
- 매크로 설정 3방식 [V]: **Macro Ratios**(기본 25:45:30 P:C:F, 에너지 타겟이 바뀌면 비율 유지하며 자동 갱신) / **Fixed Targets**(그램 고정) / **Keto Calculator**(제지방량 기반 단백질 상한 + 탄수 상한 + 나머지 지방).
- **체성분 반영** [V]: 프로필에 **체지방률**을 입력하면 에너지 요구량·영양 타겟 추정에 사용. **단백질 타겟을 제지방량(LBM) 기반으로 동적 계산 가능.**
- **자동 선택: 없음.**

> **주목**: Cronometer는 메이저 앱 중 **제지방량 기반 단백질 처방을 명시적으로 지원하는 드문 앱**입니다. 우리 엔진의 `단백질 g/kg FFM` 파라미터화는 업계 소수파이지만 **Helms 2014 (2.3–3.1 g/kg LBM)** 와 일치하는 올바른 쪽입니다.

### 3.5 Fitbod — 훈련 앱. "목표"가 식단이 아니라 **운동 처방**을 바꿈

출처: [Fitbod help: Getting Started](https://help.fitbod.me/hc/en-us/articles/30721771750039-Getting-Started-with-Fitbod-A-New-User-s-Guide), [Fitbod blog: How Fitbod Adapts to Any Goal](https://fitbod.me/blog/what-fitness-app-is-best-for-you-how-fitbod-adapts-to-any-fitness-level-goal-or-gym-setup/), [Fitbod 온보딩 플로우 (App Fuel)](https://www.theappfuel.com/examples/fitbod_onboarding)

- 온보딩 퀴즈에서 **주 목표 1개** 선택 [V-partial, 정확한 라벨 목록은 미확정]: 근육량(hypertrophy) / 근력(strength) / 지구력(endurance) / 체지방 감소(fat loss) / 새로운 것 시도 / 파워리프팅 / 올림픽 리프팅.
- 추가 온보딩: **경력 수준(초급/중급/고급)**, 운동 장소·장비, 주당 빈도·요일. [V]
- 목표가 바꾸는 것: **운동 선택, 반복수, 세트, 휴식 시간** (근육 신선도 및 부위 로테이션 고려). [V]
- **자동 선택: 없음.**

> **우리 모드가 반드시 가져가야 할 것**: 오너의 4분할은 전부 *식단* 언어입니다. 하지만 `근성장 모드`와 `커팅 모드`는 **운동 처방이 달라야 합니다**(볼륨/강도/유산소량). Fitbod는 목표 → 운동 파라미터 매핑을 실제로 하는 레퍼런스입니다. 우리 엔진의 `a`가 이미 유산소 분(minutes)을 보간하므로 절반은 되어 있고, **세트/렙/볼륨 정책**을 모드 정의에 넣으면 완성됩니다.

### 3.6 Hevy — 목표는 **필터**일 뿐

출처: [Hevy: Workout Plan Generator](https://www.hevyapp.com/features/workout-plan-generator/), [Hevy: Gym Workout Routines](https://www.hevyapp.com/features/gym-workout-routines/), [Hevy 튜토리얼](https://www.hevyapp.com/hevy-tutorial/)

- 프로그램 라이브러리를 **Level / Goal / Equipment** 세 필터로 탐색. Goal 값: **muscle gain / strength / weight loss**. [V]
- 식단·칼로리 기능 없음. 목표는 프로그램을 고르는 태그일 뿐, 상태를 가진 "페이즈"가 아님.
- **자동 선택: 없음.**

### 3.7 Ladder — **확인 실패**

[unverified] 검색이 Ladder 앱의 목표 모드 구조를 전혀 반환하지 못했습니다("Ladder app training goal selection" 쿼리에서 관련 결과 0건). 내 추론: Ladder는 팀/코치 주도 프로그램 구독 모델이라 **"목표 모드"라는 개념 자체가 없고 "어떤 팀/프로그램을 구독하는가"로 대체**될 가능성이 높습니다. 다만 이는 **검증되지 않은 추정**이며, 필요하면 직접 앱스토어 리스팅 확인이 필요합니다.

### 3.8 한국 앱들

출처: [다이어트신 (Google Play)](https://play.google.com/store/apps/details?id=com.diet.calorie160105), [다이어트신 (App Store)](https://apps.apple.com/kr/app/%EB%8B%A4%EC%9D%B4%EC%96%B4%ED%8A%B8%EC%8B%A0/id981460948), [밀리그램 (App Store)](https://apps.apple.com/kr/app/id1514163957), [밀리그램 (Google Play)](https://play.google.com/store/apps/details?id=com.lefal.mealligram), [핏데이 (App Store)](https://apps.apple.com/kr/app/fitday/id1060335034), [Noom: Maintenance Mode](https://www.noom.com/support/faqs/using-the-app/daily-features/2026/03/maintenance-mode/), [Noom: Dynamic Calorie Goals](https://www.noom.com/support/faqs/using-the-app/logging-and-tracking/food-and-water/2025/10/how-to-use-dynamic-calorie-goals/), [Noom: Weight Loss Zone](https://www.noom.com/support/faqs/using-the-app/logging-and-tracking/biometrics/2025/10/how-noom-sets-your-weight-loss-zone-and-tracks-your-progress/)

#### 다이어트신 [V]
- 입력 모델이 **우리와 거의 동일**: **"목표 감량 체중 + 기간"만 입력하면 하루 필요한 음식·운동 칼로리를 처방.**
- 추적 지표: 음식/운동 칼로리, 영양소, **몸무게 · 골격근량 · 체지방량** — 즉 **InBody 3지표를 이미 추적**합니다.
- **모드 개념 없음.** 방향은 "감량" 하나로 고정.
- **자동 선택: 없음.**

> **가장 중요한 한국 경쟁 레퍼런스입니다.** 우리와의 차이는 단 하나: **다이어트신은 "감량"만 있고 방향 선택이 없다**는 것. 우리가 모드를 도입하면 이 앱이 못 하는 걸 하게 됩니다. 반대로 말하면, **한국 시장에서 "감량"이 기본값이라는 강한 신호**이기도 합니다 — 모드 목록의 기본 선택은 감량이어야 합니다.

#### 밀리그램 [V]
- **AI 코치가 "추천 목표"를 제시** + 식단 분석. 현재 상황에 맞춘 맞춤 식단·운동·생활습관 목표 + 실시간 피드백.
- 기록 범위: 식단·운동·신체·물·수면·컨디션·생리 여부.
- **자동 선택: 부분적으로 있음(AI 추천 목표)** — 단 그 추천 로직은 공개되어 있지 않음 [unverified 내부 로직].

#### 핏데이 [V-partial, 동일성 불확실]
- 검색이 찾은 `핏데이(FitDay)`는 **"7분 풀보이스 근력운동 코칭 PT 앱"** 입니다 — 성우 코칭 기반 단시간 운동 앱이며, **칼로리/목표 모드 앱이 아닙니다.**
- [unverified] 오너가 의도한 "핏데이"가 이 앱인지, 동명의 다른 앱(미국 FitDay 칼로리 트래커 등)인지 불확실합니다. **모드 설계에 참고할 것이 없습니다.**

#### 눔 Noom Korea [V]
- **모드 2종을 탭으로 제공**: `체중 감량` ↔ `유지(Maintenance Mode)`. **Weight and Calorie Settings 에서 탭을 눌러 양방향 전환** 가능. [V]
- **감량 존(Weight Loss Zone)**: 단일 숫자가 아니라 **칼로리 범위(range)**. 진행 기록에 따라 조정.
- **유지 존(Maintenance Zone)**: 목표 체중 주변의 **밴드**로 그래프에 표시 (MF의 Dynamic Maintenance와 같은 시각 언어). **Harris-Benedict** 식으로 계산. [V]
- **Dynamic Calorie Goals**: 체성분·운동량·생활방식에 따라 일일 칼로리 목표를 조정. [V]
- **증량 모드 없음.** [V] — 눔은 감량 앱이라 방향이 반쪽입니다.

> **눔에서 훔칠 것 2가지**: ① **목표를 점이 아니라 범위/밴드로 표시**. ② **모드 전환이 탭 하나** — 페이즈 전환을 "새 목표 만들기"가 아니라 "탭 전환"으로 만들면 사용자가 실제로 전환합니다. RP가 그렇게 강조하는 maintenance가 현실에서 안 지켜지는 이유는 **전환 비용**입니다.

---

## 4. InBody — 결과지와 앱

### 4.1 인쇄 결과지의 `체중조절 / 지방조절 / 근육조절` [V]

출처: [InBody Results Interpretation (공식)](https://qr.inbody.com/ri/570/adult/en-US), [myinbody.com 성인 결과 해설](http://www.myinbody.com/web_resultinfoadult.htm), [KB손해보험 인사이트: 인바디 결과지 보는 방법](https://insight.kbinsure.co.kr/%EC%9E%90%EC%84%B8%ED%9E%88-%EB%B3%B4%EC%95%84%EC%95%BC-%EB%B9%A0%EC%A7%84%EB%8B%A4-%EC%9D%B8%EB%B0%94%EB%94%94-%EA%B2%B0%EA%B3%BC%EC%A7%80-%EB%B3%B4%EB%8A%94-%EB%B0%A9%EB%B2%95/), [Palo Alto Fit InBody Guide (PDF)](https://paloaltofit.com/wp-content/uploads/2022/05/Palo-Alto-Fit-InBody-Guide.pdf), [Field of Fitness: InBody 270 결과 해설](https://fieldoffitness.com/inbody-results/)

확인된 정의 [V]:
- **체중조절 / 지방조절 / 근육조절의 `+`/`−` 는 "현재 몸을 가장 최적의 체성분 상태로 만들기 위해 변화시켜야 할 조절량"**. `+`는 늘려야 할 양, `−`는 줄여야 할 양.
- **Fat Control** = 최적 건강을 위해 늘리거나 줄여야 할 지방량. **Muscle Control** = 최적 건강을 위해 **늘려야 할** 근육량.
- **적정체중(Target Weight)** = *검사자의 체성분을 고려하여* 근육량과 체지방량이 이상치가 되었을 때의 체중. **표준체중(Ideal Weight, BMI 기반 신장만 고려)과 다릅니다.** 근육량이 많은 과체중이면 근육을 줄일 필요가 없으므로 **적정체중이 표준체중보다 높게** 나옵니다. [V]
- InBody의 이상 체지방률 기준: **남 15% / 여 23%** (나머지 85% / 77%가 제지방). [V]
- 골격근량 정상 범위: **표준 SMM의 90~110%**. [V]

### 4.2 오너 결과지와의 정합 — **이게 이번 조사에서 가장 실무적으로 중요한 발견입니다**

오너 결과지: **적정체중 78.4 kg / 체중조절 −8.3 / 지방조절 −8.3 / 근육조절 0.0**

두 가지가 즉시 따라옵니다:

**(1) 산술 항등식이 성립합니다.**
```
체중조절(−8.3) = 지방조절(−8.3) + 근육조절(0.0)   ✅
```
이건 우연이 아니라 InBody의 정의입니다. **앱은 이 항등식을 화면에 그대로 보여줘야 합니다.** 사용자가 목표를 직접 입력할 때도 같은 항등식(`Δ체중 = ΔBFM + ΔFFM`)이 성립해야 하고, 우리 엔진은 `ΔFFM = k_SMM→FFM × ΔSMM` 변환을 쓰므로 **사용자 입력 3개가 서로 모순될 수 있습니다.** 모드 자동 선택기 이전에 **정합성 검사가 먼저** 와야 합니다. (`P04` 판독 검수와 같은 종류의 검사를 `P05` 목표 설정에도.)

**(2) InBody 자신이 이미 모드를 처방하고 있습니다.**

`지방 −8.3 / 근육 0.0` = **"지방만 빼고 근육은 그대로"** = **한국 헬스 용어로 정확히 `커팅`** (§6.2 참조). 즉:

> **InBody 결과지는 이미 "커팅"을 권하고 있습니다.** 앱이 모드를 자동 선택했을 때 이것과 다른 답이 나온다면, **왜 다른지 반드시 한 줄로 설명해야 합니다.** 예: *"인바디는 지방 −8.3 / 근육 0.0(커팅)을 제안했지만, 회원님이 입력한 목표는 근육 +2.0이라 리컴프 모드로 판정했습니다."*

**(3) InBody가 절대 제안하지 않는 것도 알아두세요.** InBody의 조절량은 **항상 자기 기준(남 15% / 여 23% 체지방)으로 가는 최단 경로**이고, **근육조절은 음수가 되지 않습니다**(늘리라고만 함). 따라서 InBody는 **증량(벌크)·리컴프·리버스 다이어트를 제안할 수 없습니다.** 우리 앱이 InBody를 "무시"하는 게 아니라 **"InBody가 말할 수 없는 영역을 채운다"** 는 프레이밍이 정직합니다.

### 4.3 InBody 앱 / InBody+ 앱 [V]

출처: [LookinBody FAQ: How do I set goals and create diet guide from the InBody app](https://lbwebfaq.inbodyusa.com/support/solutions/articles/69000804868-how-do-i-set-goals-and-create-diet-guide-from-the-inbody-app), [InBody+ (App Store)](https://apps.apple.com/us/app/inbody/id6450072536?l=ko), [InBody HQ 보도자료](https://inbody.co.kr/press_release/contents/view/90/), [백록담한의원: 인바디 연동 어플](https://www.baekrokdam.com/blog/%EC%9D%B8%EB%B0%94%EB%94%94-%EC%97%B0%EB%8F%99-%EC%96%B4%ED%94%8C), [InBody+ (Google Play)](https://play.google.com/store/apps/details?id=com.inbody.inbodyhealth)

**두 개의 다른 앱입니다** [V]:
- **InBody 앱** — 헬스장/검진센터의 인바디 본체에서 잰 결과를 폰으로 불러오는 앱 ← **오너의 사용 시나리오는 이쪽**
- **InBody+ 앱** — 가정용 인바디(Fit, H30, H40)와 페어링하는 앱

**목표 설정** [V]:
- InBody 임상연구팀이 만든 과학적 데이터에 기반해 **근육·지방 목표를 설정**. "Clinical recommendations를 근육·지방 목표 설정의 레퍼런스로 사용 가능."
- 목표를 추가하면(예: "체지방 몇 % 감소", "근육량 증가", **기간 지정**) 앱이 제안·액션플랜을 그에 맞게 조정.
- 대시보드: 최근 측정, 혈압, 일일 활동량, **체성분 목표**, 영양 진행률.
- 내장지방 과다 등을 감지하면 운동/식단 변경을 제안 (규칙 기반 힌트).

**InBody+ 의 `패스파인더(PathFinder)`** [V-partial, 한국 보도자료 경유]:
- **월 단위로 갱신되는 "클러스터(cluster)"** 를 통해 체성분 변화를 확인하고, **원하는 목표까지 가장 효율적인 경로**를 안내.
- 목표를 시작하면 **목표 달성률 + 체성분 항목별 달성률**을 PathFinder 화면에서 확인.
- 목표 달성 시 → 체성분과 난이도를 분석해 **초기 설정 경로 상의 다음 클러스터**를 부여하고, **최종 인생 목표에 도달할 때까지 마일스톤을 이어서 안내**.
- 미달성 시 → 같은 목표로 재시작하거나 새 최종 목표 클러스터를 설정.
- AI는 체성분 측정 결과 + 걸음수 + 운동 기록 + **110종 설문 데이터**를 학습해 맞춤 목표·솔루션 제안.

> **PathFinder가 우리 설계에 주는 가장 큰 시사점**: InBody는 **"하나의 큰 목표"가 아니라 "클러스터 사슬(milestone chain)"** 로 모델링합니다. 목표를 달성하면 **다음 클러스터를 새로 계산**합니다. 이건 사실상 **페이즈 전환의 UI화**입니다 — RP의 cut→maintenance→mass 사슬과 구조가 같고, 이름만 "클러스터"입니다.
>
> 우리 엔진은 이미 `split` 전략(컷 → 유지 2주 → 벌크 → 미니컷)에서 사슬을 만들고 있습니다. **`split`이 선택됐을 때 그 사슬의 각 구간에 모드 이름을 붙여 표시**하면 (예: `커팅 8주 → 유지 2주 → 린매스업 12주 → 미니컷 4주`), PathFinder와 RP 양쪽의 좋은 점을 동시에 가져갑니다. 그리고 그게 **"모드가 하나가 아니라 순서일 수 있다"** 는 걸 정직하게 보여주는 유일한 방법입니다.

---

## 5. 비교표

### 5.1 메인 비교표

| 앱 | 모드 이름 (앱 안 실제 라벨) | 개수 | 속도/강도 선택 방식 | 모드 자동 선택? | 체성분 인식 |
|---|---|---|---|---|---|
| **MacroFactor** | Lose / Maintain / Gain | 3 | **%BW/주 슬라이더**, 녹색 권장구간 0.25–1%/주. 별도로 프로그램 스타일(Coached/Collaborative/Manual)이 자율성 축 | ❌ 앱 내 없음. **웹에 별도 "Bulk or Cut?" 퀴즈** 존재 | 간접 — 리컴프를 *오차원*으로 취급(전형 ~108 kcal/d, 극단 ~347 kcal/d) |
| **RP Diet** | Cut / Maintenance / Mass | 3 | 페이즈 길이로. **cut ≤12주**, massing/cut 1회 3–6개월, mass 후 유지 1–3개월, 컷 후 massing ~0.5%BW/주 | ❌ 사용자가 페이즈 선택 | 체중 추세 + 순응도 기반 주간 점진 조정 |
| **Carbon** | Lose / Gain / Maintain / **Reverse diet** | 4 | 모드마다 **다른 알고리즘**. 속도는 목표 설정 시 지정 | ❌ | 체중 추세 기반 |
| **SbS 계산기류** | (모드 없음) | 0 | 권고 수치만: 증량 0.25–0.5%BW/주, 감량 0.5–1%BW/주, 잉여 +200~500 kcal | ❌ | LBM 기반 단백질 권고 |
| **MyFitnessPal** | Lose / Maintain / Gain | 3 | **절대값 (kg 또는 lb)/주**. 칼로리 하한 여 1,200 / 남 1,500 | ❌ | ❌ 없음 |
| **Cronometer** | (모드 없음, Weight Goal 하나) | 0 | 목표 체중 + 증감 속도. 매크로는 Ratios / Fixed / Keto 중 택1 | ❌ | ✅ 프로필 체지방률 → 에너지 추정, **LBM 기반 단백질 타겟** |
| **Fitbod** | strength / muscle size / fat loss / endurance / powerlifting / oly | 6+ | 목표가 **운동 변수**(종목·렙·세트·휴식)를 바꿈. 경력 3단계 별도 입력 | ❌ | ❌ (훈련 앱) |
| **Hevy** | muscle gain / strength / weight loss (**프로그램 필터**) | 3 | 필터일 뿐, 상태 없음 | ❌ | ❌ |
| **Ladder** | **[unverified — 자료 확보 실패]** | ? | ? | ? | ? |
| **다이어트신** | (모드 없음 — 감량 고정) | 0 | **목표 감량 체중 + 기간 입력 → 일일 음식·운동 칼로리 처방** | ❌ | ✅ **몸무게·골격근량·체지방량 추적** |
| **밀리그램** | (모드 라벨 미확인) | ? | **AI 코치가 "추천 목표" 제시** | ⚠️ **부분적 — 로직 비공개** | 신체 기록 포함 |
| **핏데이** | (해당 없음 — 7분 음성코칭 운동앱) | – | – | – | ❌ |
| **눔 Noom** | 체중 감량 / **유지(Maintenance Mode)** — **탭 전환** | 2 | **칼로리 존(범위)**. Dynamic Calorie Goals가 체성분·활동·생활방식으로 조정. 유지 존은 Harris-Benedict | ❌ | 부분 (Dynamic Calorie Goals) |
| **InBody 앱** | (모드 아님) 근육 목표 / 지방 목표 + 기간 | – | 임상 권고치를 레퍼런스로 목표량 지정 | ⚠️ **결과지가 사실상 처방**(체중·지방·근육 조절량) | ✅✅ 원본 측정 |
| **InBody+ PathFinder** | 클러스터 사슬(마일스톤) | – | **월 갱신 클러스터**, 달성 시 다음 클러스터 자동 산출 | ⚠️ **AI가 목표·솔루션 제안** (측정+걸음수+운동+설문 110종) | ✅✅ |
| **GainFrame** | (Deep Dive의 **trajectory 분류**) recomp / fat loss / muscle gain | 3 | – | ✅ **관측 데이터의 패턴을 모드로 분류** ("Recomp On Track" = FFMI↑ & 체지방↓/유지) | ✅ 사진 기반 추정(체지방·FFMI·12부위 근육 점수) |
| **LeanLens** | Cut / Recomp / Lean bulk | 3 | – | ✅ **체지방 추정 + 훈련 경력 + 목표 + 체중 추세 → 보수적 시작 페이즈 제안 + "무엇이 바뀌면 추천이 달라지는지" 설명** | ✅ 사진 기반 추정 |

출처(자동선택 2종): [GainFrame: Best Body Recomposition Apps](https://gainframe.app/blog/best-body-recomposition-apps/), [GainFrame: Bulk, Cut, or Recomp](https://gainframe.app/blog/bulk-cut-or-recomp/), [LeanLens: Should I Cut, Bulk, or Recomp?](https://leanlens.ai/cut-or-bulk), [LeanLens: Bulk, Cut, or Recomp: Which Should You Choose?](https://leanlens.ai/blog/bulk-cut-recomp-which-to-choose)

### 5.2 모드 개수 분포 — 세어보면 놀랍습니다

| 모드 개수 | 앱 |
|---|---|
| 0 (모드 개념 없음) | Cronometer, SbS 계산기, 다이어트신 |
| 2 | 눔 |
| **3** | **MacroFactor, RP, MyFitnessPal, Hevy, GainFrame, LeanLens** ← **압도적 최빈값** |
| 4 | Carbon (4번째는 `reverse diet`) |
| 6+ | Fitbod (단, 식단이 아니라 **운동** 목표) |

> **결론: 식단 방향 모드의 업계 표준 개수는 3입니다.** 그리고 4번째를 만든 유일한 진지한 앱(Carbon)은 그 4번째를 **`커팅`이 아니라 `리버스 다이어트`** 로 썼습니다.

### 5.3 "속도"를 표현하는 3가지 방식 — 우리가 이미 고른 길

| 방식 | 쓰는 앱 | 문제 |
|---|---|---|
| **절대값 (kg/주)** | MyFitnessPal | 체중이 줄수록 적자 **비율**이 커져 자동으로 위험해짐 |
| **상대값 (%BW/주)** | **MacroFactor**, RP, SbS 권고 | 업계 정답. 체중 감소에 따라 절대 속도가 자동으로 완만해짐 |
| **기간 (duration)** | **RP** (페이즈 길이), InBody 앱(기간 지정), 다이어트신(기간 입력) | 사용자 직관에 가장 가까움. 단 **생리적 가능 범위를 넘을 수 있어 검증 필요** |

> **우리 앱은 `상/중/하 = 기간`을 택했습니다.** 이건 RP·InBody·다이어트신과 같은 계열이고, **한국 사용자 직관에 맞는 선택**입니다(다이어트신이 "기간" 입력을 쓴다는 게 그 증거). 그리고 `T_min`을 먼저 구해 **불가능한 기간을 아예 제시하지 않는다**는 점에서 다이어트신보다 정직합니다. 이 설계를 바꿀 이유를 조사에서 찾지 못했습니다.

---

## 6. 오너의 4분할에 대한 판정 (앱 랜드스케이프 근거)

### 6.1 모드 이름을 한국어 실사용 어휘와 대조

출처: [메일리: #3 벌크, 다이어트, 리컴프 어떤 것 부터?](https://maily.so/fitnessfreedom/posts/xyowd791z28), [몬스터짐: 린매스업·근매스업·벌크업의 차이](https://www.monsterzym.com/index.php?dispatch=community.view&community_code=coach&community_data_idx=8410696), [몬스터짐: 린매스업 vs 벌크업](https://talk.monsterzym.com/nutrition_community/5913955), [브런치: 다이어트는 그만하고 바디 리컴포지션하세요](https://brunch.co.kr/@minker/18), [나무위키: 벌크업](https://namu.wiki/w/%EB%B2%8C%ED%81%AC%EC%97%85), [블라인드: 벌크업? 살크업? 린매스업? 상승다이어트?](https://www.teamblind.com/kr/post/%EB%B2%8C%ED%81%AC%EC%97%85-%EC%82%B4%ED%81%AC%EC%97%85-%EB%A6%B0%EB%A7%A4%EC%8A%A4%EC%97%85-%EC%83%81%EC%8A%B9%EB%8B%A4%EC%9D%B4%EC%96%B4%ED%8A%B8-r6J8hd5b)

확보된 한국 실사용 어휘와 칼로리 포지션 [V]:

| 한국어 | 영어 | 칼로리 | 비고 |
|---|---|---|---|
| **벌크업 / 벌킹** | bulking | **유지 +500~** | "살크업"은 지방만 찌는 실패 벌크를 놀리는 말 |
| **린매스업** | lean bulk | **유지 +250~300** | "지방 제외 제지방량(대표적으로 골격근량)을 늘리겠다" |
| **다이어트 / 컷 / 커팅** | cutting | 유지 미만 | |
| **리컴프 = 상승 다이어트** | recomposition | **유지 ±0 (최대한 가깝게)** | "국내에서 익숙한 표현은 **상승 다이어트**" |
| **유지어터 / 유지어트** | maintenance dieter | 유지 | "유지 + 다이어트의 합성. 다이어트 이후 빠진 체중을 유지하기 위한 식습관·생활습관" |
| **다이어트 브레이크** | diet break | 유지 | "극단적으로 음식 섭취량을 줄이고 배고픔을 느끼는 시점에 도달했을 때 대사 회복을 위해 다이어트를 일시 중단" |
| **미니컷** | mini cut | 유지 −25~30% | 한국 커뮤니티에서도 "일반 다이어트와 구분되는 단기 체지방 감량 방식"으로 통용 |
| **바디프로필** | (한국 고유) | 극단 감량 + 수분조절 | 초급 6개월~1년 / 중급 3~6개월 / 고급 2~3개월 준비 |

> **오너의 4개 이름 중 2개가 한국 실사용 어휘와 어긋납니다.**
> - `근성장모드` — **한국 헬스장에서 이 단어를 쓰지 않습니다.** 실제로 쓰는 말은 **`벌크업`**(공격적) 또는 **`린매스업`**(보수적)이고, **그 둘은 칼로리 잉여 크기가 명확히 다릅니다** (+500 vs +250~300). 오너가 "이 업계를 잘 모른다"고 한 바로 그 지점입니다. `근성장`이라는 중립어를 쓰면 **사용자가 자기 헬스장 언어로 인식하지 못합니다.**
> - `리컴프모드` — 정확한 용어지만, **한국에서 더 널리 통하는 말은 `상승 다이어트`** 입니다. 병기가 안전합니다: **`리컴프(상승 다이어트)`**.

### 6.2 `감량` vs `커팅` — 결론: **엔진 방향은 하나, UI 모드는 둘, 그리고 그 사실을 말할 것**

출처: [브런치: 근손실 없는 체지방 감량은 kg를 %로 바꿔야 가능](https://brunch.co.kr/@habitdesign/254), [틸노트: 벌크업과 커팅 (헬스 문해력)](https://tilnote.io/en/books/6a0af304feaf255d2099bb3c/6a0af303feaf255d2099bb08), [건강덕후: "커팅 식단"으로 살 빼는 다이어트 시작가이드](https://healduck.com/info-cutting/), [블라인드: 커팅하면 근육이 무조건 빠져?](https://www.teamblind.com/kr/post/%EC%BB%A4%ED%8C%85%ED%95%98%EB%A9%B4-%EA%B7%BC%EC%9C%A1%EC%9D%B4-%EB%AC%B4%EC%A1%B0%EA%B1%B4-%EB%B9%A0%EC%A0%B8-3kyen2dv)

한국 소스가 실제로 구분하고 있습니다 [V], 원문 표현 그대로:
- **"커팅은 … 수분, 글리코겐, 근육 등의 감소는 최소화하고 지방만 줄이는 체중 감소를 의미"**
- **"커팅의 목표는 체중 감량이 아니라 체지방 감량이며, 이 차이를 이해해야 한다"**
- **"다이어트와 체지방 커팅은 다르다"**
- 일반 다이어트의 문제: **"굶으면 체중은 빠르게 줄 수 있지만, 그 안에는 수분, 근육, 운동 능력, 컨디션이 함께 포함될 수 있다"**

**판정:**

1. **엔진 관점에서는 같은 것입니다.** 둘 다 `방향 = BFM↓`. 별도의 방향이 아닙니다. → 업계(MacroFactor/MFP/Carbon/눔)가 전부 이걸 하나로 묶는 이유입니다.

2. **하지만 제약(constraint)은 다릅니다.** 이건 우리 엔진에서 **실제로 표현 가능**합니다:
   - **감량 모드**: `ΔSMM ≤ 0 허용`. 목표는 체중. 근손실을 *받아들인다*. → `a` 상한 높음, 단백질 중간, 적자 >15% TDEE 허용.
   - **커팅 모드**: `ΔSMM ≈ 0을 하드 제약`. 목표는 체지방. → `a` 상한이 **근손실 제약에 의해 자동으로 잘림**, 단백질 최대(Helms 2.3–3.1 g/kg LBM), 저항운동 필수, 적자 상한 보수적.

   즉 **커팅은 "감량 + SMM 보존 하드 제약"** 입니다. 우리 엔진은 시뮬레이션 상태에 SMM을 갖고 있으므로 **이 제약을 진짜로 강제할 수 있습니다** — 체중계만 있는 앱은 못 합니다.

3. **권고: 두 개로 노출하되, 화면에서 같은 것임을 밝힐 것.**
   - 근거 ①: 오너의 헬스장 언어가 실제로 둘을 구분합니다(위 인용).
   - 근거 ②: 제약이 다르면 계산 결과(기간·칼로리·단백질)가 실제로 달라집니다 — 이름만 다른 게 아닙니다.
   - 근거 ③: **다만 침묵하면 안 됩니다.** UI 카피 제안:
     > **감량 (체중 중심)** — 체중을 줄이는 게 목표. 근육이 좀 빠져도 괜찮다면 더 빠릅니다.
     > **커팅 (체지방 중심)** — 같은 "살 빼기"지만, **근육을 지키는 걸 조건으로 겁니다.** 그래서 더 느리고, 단백질이 더 높고, 근력운동이 필수입니다.
     > *두 모드는 방향이 같습니다. 다른 건 "근육을 얼마나 지킬 것인가"뿐입니다.*

4. **오너 결과지에는 `커팅`이 정답입니다** (§4.2): 지방 −8.3 / 근육 0.0.

### 6.3 4분할에서 **빠진 것** — 앱 랜드스케이프가 지목하는 구멍

| 빠진 것 | 누가 갖고 있나 | 왜 필요한가 |
|---|---|---|
| **유지 / 유지어터** | MacroFactor(Dynamic Maintenance), RP(Maintenance phase), Carbon, 눔(Maintenance Mode 탭) | **조사한 진지한 앱 전부가 갖고 있습니다.** 오너의 4개에는 없습니다. RP는 mass 후 1~3개월, cut 12주 후 12주를 *처방*합니다. 목표 달성 후 앱이 "끝"이라고만 하면 요요로 끝납니다 |
| **리버스 다이어트 / 다이어트 브레이크** | Carbon (4번째 모드) | **다이어트에서 빠져나오는 길.** 한국에도 `다이어트 브레이크` 어휘가 이미 있습니다. 단, 근거는 약합니다(§6.4) |
| **미니컷** | RP·Legion (벌크:컷 = 3~4:1), 한국 커뮤니티에도 어휘 존재 | **우리 엔진의 `split` 전략이 이미 미니컷을 실행하고 있는데 이름이 없습니다.** 사용자에게 보이지 않습니다 |
| **바디프로필(데드라인 컷)** | ❌ 어떤 서구 앱에도 없음 — **한국 고유** | 한국 사용자의 가장 흔한 "마감 있는 목표". 준비기간이 경력별로 알려져 있음(초급 6~12개월 / 중급 3~6개월 / 고급 2~3개월). **`deadline_weeks` 가 이미 엔진 입력에 있으므로 구현 비용이 낮습니다** |

### 6.4 ⚠️ `리버스 다이어트`를 넣을 거면 정직하게 넣어야 합니다

출처: [MacroFactor: Reverse Dieting — Hype Versus Evidence](https://macrofactor.com/reverse-dieting/), [Precision Nutrition: Reverse dieting](https://www.precisionnutrition.com/reverse-dieting), [Physiqonomics: Reverse Dieting — Metabolic Magic or Another Diet Fairytale?](https://physiqonomics.com/reverse-dieting-metabolism/), [ClinicalTrials NCT03434431](https://clinicaltrials.gov/study/NCT03434431), [PMC8196522: Metabolic adaptation](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC8196522/)

확보된 증거 [V]:
- **대사 적응은 실재**합니다 (Trexler et al. 2014): BMR 저하, NEAT 감소, 호르몬 변화.
- **그러나 크기가 작습니다.** 한 연구(Nunes)에서 대사 적응은 **30~100 kcal 범위**. 대부분의 연구에서 유지 칼로리로 돌아오면 **유의하지 않거나 완전히 소실**.
- **리버스 다이어팅 자체의 근거는 훨씬 얇습니다.** "체중 재증가를 막는 효과적 수단이라는 과학적 근거가 거의 없음." 원래 **과학이 아니라 업계 마케팅**에서 나왔음.
- **"리버스 다이어팅이 정상 회복을 넘어 대사를 '부스트'한다는 증거는 없음."**
- 실제 가치: **순응도(adherence)와 심리적 회복**.

> Carbon이 4번째 모드로 쓰는 것과, MacroFactor가 "Hype Versus Evidence"라는 제목으로 쓰는 것이 같은 대상입니다. **넣어도 되지만, 배지는 `[C]` 이고 UI는 "대사를 되살린다"가 아니라 "다이어트에서 안전하게 빠져나온다"로 써야 합니다.**
>
> 반면 **MATADOR 연구는 유지 기간(diet break)에 대해 더 나은 근거를 줍니다** ([Nature IJO: MATADOR](https://www.nature.com/articles/ijo2017206), [PubMed 28925405](https://pubmed.ncbi.nlm.nih.gov/28925405/)): 비만 남성 51명, 8×2주 제한 블록 사이에 **에너지 균형 '휴식기'** 를 넣은 간헐적 제한군이 연속 제한군보다 **체중·체지방 감소가 더 컸습니다.** 결정적 조건: **"단순히 섭취량을 오르내리는 게 아니라, 통제된 에너지 균형(energy balance) 상태를 실제로 만드는 것이 핵심"**. → **우리 `split` 전략의 "유지 2주"는 MATADOR 블록(2주)과 정확히 일치합니다. 이건 근거 등급을 올려 붙여도 됩니다.**

---

## 7. 이 앱들이 **틀리거나 지나치게 단순화한** 것 — 1인용 앱이 더 잘할 수 있는 지점

출처: [Fitness Mentors: TDEE Calculator — Why Most Calorie Calculations Are Wrong](https://www.fitnessmentors.com/tdee-calculator-total-daily-energy-expenditure/), [Omnio: Your Calorie Target Is Wrong](https://getomn.io/blog/posts/your-calorie-target-is-wrong-heres-how-we-fix-it/), [Fitia: TDEE, Activity & Calorie Budget Guide](https://fitia.app/learn/article/why-calorie-target-keeps-changing-tdee/), [Calorie Apps: Top TDEE Calculator Apps 2026](https://calorie-apps.com/articles/top-tdee-calculator-apps-2026), [MacroFactor: Algorithms and Core Philosophy](https://macrofactor.com/macrofactors-algorithms-and-core-philosophy/)

### 7.1 정적 TDEE — 거의 모든 앱의 원죄 [V]

- **Mifflin-St Jeor(1990)** 는 나이·성별·키·체중 4개 변수만 봅니다. **실제 체성분을 모릅니다.** 훈련 볼륨도, 그 훈련의 칼로리 비용도, 장기 감량 중 대사 적응도, 개인별 흡수·NEAT 변화·영양소 분배율(P-ratio)도 모릅니다. [V]
- **12주 다이어트 후 정적 TDEE 추정은 초기 계산 대비 10~25% 표류**합니다. [V]
- 웨어러블 칼로리 추정 오차는 검증 연구에서 **27~93%**. [V]
- 정적 공식의 평균 오차 **~325 kcal/day** (MacroFactor 자체 비교). [V]

> **우리가 이미 이긴 것**: Katch-McArdle(FFM 기반) + 주차별 시뮬레이션 + 적응형 TDEE 교정. **FFM을 InBody로 직접 측정하므로 "체성분을 모른다"는 원죄가 없습니다.** 이건 자랑해도 되는 실제 우위입니다.

### 7.2 모드 자동 선택에서 **아무도 노이즈를 처리하지 않습니다** — 우리가 가장 조심해야 할 지점

GainFrame과 LeanLens 둘 다 **사진 기반 AI 추정**으로 모드를 고릅니다. 사진 AI 체지방 추정 오차는 **DEXA 대비 통상 2~4%p** [V, GainFrame/Bodilab 주장]. InBody도 [V] "DEXA와 밀접한 상관, 비임상 환경에서 가장 정확한 옵션"이라지만, **동일인 당일 재측정 변동은 여전히 큽니다** (우리 `planning-engine.md §0.2`의 ε_W=1.0kg / ε_SMM=0.5kg / ε_BFM=1.0kg).

> **치명적 위험**: 사용자가 입력한 `ΔSMM = +0.4kg` 는 **측정 노이즈(ε_SMM=0.5kg)보다 작습니다.** 그걸로 "근성장 모드"를 자동 선택하면 **노이즈가 모드를 결정합니다.**
>
> **반드시 해야 할 것**: 자동 선택기는 원시 Δ가 아니라 **dead-zone 통과 후의 Δ**로 판정해야 합니다.
> ```
> ΔSMM_eff = |ΔSMM| < ε_SMM ? 0 : ΔSMM
> ΔBFM_eff = |ΔBFM| < ε_BFM ? 0 : ΔBFM
> ΔW_eff   = |ΔW|   < ε_W   ? 0 : ΔW
> ```
> 그리고 **셋 다 0이면 모드는 `유지`이고, 그 사실을 말해야 합니다**: *"입력하신 변화량이 인바디 측정 오차(±0.5kg 근육 / ±1kg 지방) 안쪽입니다. 지금 몸을 유지하는 계획을 제안합니다."* — **어떤 앱도 이걸 하지 않습니다.** 우리가 InBody 기반이기 때문에 할 수 있고, 안 하면 거짓말이 됩니다.

### 7.3 "목표 = 체중 하나" 라는 축소 [V]

MFP·눔·Cronometer 모두 목표가 **체중 한 축**입니다. 그래서 리컴프를 **표현할 수도, 측정할 수도** 없습니다. MacroFactor조차 리컴프를 "모드"가 아니라 "우리 추정기의 오차원"으로만 다룹니다(§1.6).

> **우리 앱의 존재 이유가 정확히 여기입니다.** 목표가 `{체중, SMM, BFM}` 3축이므로, **리컴프는 우리에게 "특수 케이스"가 아니라 그냥 1급 모드**입니다. 그리고 진척을 **실제로 측정할 수 있습니다.**

### 7.4 "빠를수록 좋다"는 암묵적 전제 [V, 반례: 우리 엔진]

MFP는 2 lb/주까지 슬라이더를 열어두고, 그게 왜 나쁜지 말하지 않습니다. 눔은 증량 모드가 아예 없습니다.

> **README §2("강도를 올리면 오히려 느려질 수 있다 — 숨기지 않는다")는 조사 범위 안의 어떤 앱에도 없는 기능입니다.** 적자 >15% TDEE에서 근육 증가율이 0으로 떨어지므로 근육 목표가 병목이면 공격적 계획이 **전체 기간을 늘립니다.** `a`를 51개 지점에서 스캔해 이 역설을 찾아 경고하는 건 **조사 전체에서 유일한 구현**입니다. **모드 설계가 이 기능을 죽이면 안 됩니다** — 오히려 모드가 이 역설의 *원인*을 이름으로 설명해 줍니다: *"커팅 모드에서 근육 +2kg는 모순입니다. 리컴프 모드나 분할 전략이 필요합니다."*

### 7.5 페이즈 전환의 마찰 [V]

RP는 cut 12주 상한, mass 후 유지 1~3개월을 *처방*하지만 **앱이 전환을 강제하지 않습니다.** 사용자가 새 다이어트를 직접 만들어야 합니다. 반면 **눔은 탭 하나로 전환**하고, **InBody+ PathFinder는 달성 시 다음 클러스터를 자동 산출**합니다.

> **1인용 앱의 이점**: 우리는 멀티테넌트 온보딩 퍼널을 지킬 필요가 없습니다. **모드를 "목표 하나 = 사슬 하나"로 만들 수 있습니다.** `split` 전략이 선택되면 사슬이 이미 존재하므로, 그걸 **이름 붙인 구간으로 표시**하고 `P08 주간 체크인`에서 **"이번 주부터 유지 구간입니다"** 라고 자동 전환하면 됩니다. RP가 코칭으로 하는 걸 앱이 합니다.

### 7.6 이탈/중단을 계획에 넣지 않음

조사한 어떤 앱도 "이 계획을 끝까지 갈 확률"을 말하지 않습니다.

> README §1이 이미 **"하 = 중도 포기 확률 최저"** 라고 쓰고 있습니다. 이건 업계에 없는 축입니다. **모드마다 "전형적 지속 기간"과 "이 모드를 포기하는 흔한 이유"를 넣으면** 조사 범위 안에서 유일해집니다. (RP의 "cut 12주 넘기지 말 것"이 사실상 같은 이야기를 *코칭*으로 하는 것입니다.)

### 7.7 InBody 결과지와 앱이 서로 다른 말을 하는 문제 — **아무도 안 풀었습니다**

InBody 앱조차 자기 결과지의 `체중조절/지방조절/근육조절`을 **목표 설정 화면과 명시적으로 연결하지 않습니다** [V-partial — 도움말은 "임상 권고를 레퍼런스로 쓸 수 있다"고만 함].

> **오너가 정확히 이 문제를 지적했습니다.** 해결책은 간단합니다 — `P05 목표 설정` 화면 상단에 고정 카드:
> ```
> 인바디가 제안한 방향
>   적정체중 78.4kg  ·  체중 −8.3  =  지방 −8.3  +  근육 0.0
>   → 이 방향은 [커팅] 모드입니다.            [이대로 시작]
>
> 회원님이 입력한 목표
>   체중 −5.0  =  지방 −7.0  +  근육 +2.0
>   → [리컴프(상승 다이어트)] 모드            [왜 다른가요?]
> ```
> **조사 범위 안에서 이걸 하는 앱은 없습니다.**

---

## 8. 조사 결과가 모드 설계에 주는 구체적 제약 (엔진 대응표)

| 랜드스케이프 사실 | 근거 | 우리 모드 정의에 넣어야 할 필드 |
|---|---|---|
| 방향 모드는 3개가 표준, 4번째는 `reverse diet` | §5.2 | 모드를 4개로 늘릴 거면 **`커팅`이 아니라 `유지/리버스`를 4번째로 고려**. 감량/커팅은 같은 방향의 두 프리셋 |
| 속도는 %BW/주, 권장 감량 0.25–1%, 증량 0.25–0.5% | MacroFactor [V], Helms 2014 (0.5–1%/주) [V], Iraki 2019 (0.25–0.5%/주) [V], Trexler (0.25–0.5%/주) [V] | 각 모드의 **`a` 범위**를 이 %BW/주로 역산해 bound |
| cut ≤ 12주, 그 후 유지 12주 | RP [V] | 각 모드의 **`max_duration_weeks`**. 초과 시 자동 분할 |
| mass 후 유지 1–3개월 | RP [V] | **`exit_to`** 필드 (다음 모드) |
| 벌크:컷 = 3~4 : 1 | RP/Legion [V] | `split` 전략의 구간 비율 sanity check |
| 미니컷 = 2~6주, 적자 25~30% TDEE, 1–1.25 %BW/주 | [Built with Science](https://builtwithscience.com/diet/lose-fat-fast-mini-cut/), [Revive Stronger: Mini Cut Manual](https://revivestronger.com/the-mini-cut-manual/), [Legion](https://legionathletics.com/mini-cuts/), [BarBend](https://barbend.com/mini-cuts/) [V] | `split` 말단 미니컷 구간의 파라미터 |
| 커팅 단백질 2.3–3.1 g/kg **LBM**, 지방 칼로리의 15–30% | Helms/Aragon/Fitschen 2014 [V] | 커팅 모드의 **단백질 정책 상한** |
| 증량 단백질 1.6–2.2 g/kg, 지방 0.5–1.5 g/kg, 잉여 10–20% | Iraki et al. 2019 [V] | 근성장/린매스업 모드 파라미터 |
| 벌크 진입 체지방 남 10–15% / 여 20–25%, 컷 진입 남 18–20% / 여 28–32%, 중간지대 남 15–18% / 여 25–28% | Helms/Aragon/Fitschen 2014 경유 [V-partial] | **모드 entry criteria의 PBF 게이트** |
| 리컴프는 초보·재개자·고체지방 미훈련자에서 가장 신뢰성 있게 발생, 단 훈련자에서도 **점진적 저항운동 + 고단백** 조건 하에 문헌상 관찰됨. 마르고 숙련될수록 느리고 미미함 | Barakat et al. 2020, *Strength & Conditioning Journal* [V] — [Semantic Scholar](https://www.semanticscholar.org/paper/fa40632e786fa5a9b0409993ca8455cd53c8fc16), [LWW 전문](https://journals.lww.com/nsca-scj/Fulltext/2020/10000/Body_Recomposition__Can_Trained_Individuals_Build.3.aspx) | 리컴프 모드의 **entry criteria**(훈련 연차 + PBF) 및 **거부 조건** |
| 근성장 상한: Aragon 모델 초보 1–1.5 %BW/월, 중급 0.5–1%, 고급 <0.5%. 여성 약 1/2 | [bodyrecomposition.com](https://bodyrecomposition.com/muscle-gain/genetic-muscular-potential), [Syatt Fitness](https://www.syattfitness.com/fat-loss/a-realistic-look-at-progress-fat-loss-and-mass-gain/) [V] | **엔진의 기존 ceiling(1.25/0.75/0.375/0.175 %BW/월, 여성 ×0.5)이 Aragon 모델의 보수적 하단과 일치** — 바꿀 이유 없음 ✅ |
| MATADOR: 2주 에너지 균형 블록이 효과적, 단 **진짜 균형**이어야 함 | [Nature IJO](https://www.nature.com/articles/ijo2017206) [V] | `split`의 "유지 2주"에 근거 등급 상향, 그리고 **그 2주가 진짜 유지여야 함**(살짝 적자면 효과 없음) |
| 리컴프 진척은 체중계로 측정 불가 | MacroFactor [V] | 리컴프 모드의 성공 지표는 **체중이 아니라 SMM/BFM**. 차트를 밴드로 |
| 측정 노이즈가 모드를 뒤집을 수 있음 | 우리 `§0.2` + BIA 특성 | **자동 선택기는 dead-zone 통과 후 Δ로만 판정** (§7.2) |

---

## 9. 자동 선택기 설계에 대한 랜드스케이프 기반 권고 (5줄 요약)

1. **LeanLens 패턴을 그대로 채택**: 입력 = `체지방 추정 + 훈련 경력 + 목표 + 체중 추세` → 출력 = **보수적 시작 페이즈 + "무엇이 바뀌면 추천이 달라지는가"**. 오너가 요청한 "runner-up + 이유"와 정확히 같습니다. [V]
2. **GainFrame 패턴을 두 번째 화면에 채택**: *처방*된 모드(P05)와 *관측*된 궤적(P08/P09)을 **둘 다 분류**하고 어긋나면 알립니다. GainFrame의 "Recomp On Track = FFMI↑ & 체지방↓/유지" 규칙이 그대로 쓸 만합니다. [V]
3. **MacroFactor의 겸손을 채택**: 두 모드가 근소하면 자동 선택하지 말고 **"둘 다 됩니다. 어느 쪽이 더 하고 싶으세요?"** 로 넘깁니다. MF 자신이 그렇게 합니다. [V]
4. **InBody 결과지를 "0번 후보"로 항상 표시** (§7.7). 우리 앱만 할 수 있는 일이고, 오너가 명시적으로 요구한 정합성입니다.
5. **dead-zone을 자동 선택기의 첫 번째 게이트로** (§7.2). 조사한 어떤 앱도 안 하지만, InBody 기반 앱이 이걸 안 하면 노이즈가 모드를 고릅니다.

---

## 10. 확인하지 못한 것 (정직한 공백)

| 항목 | 상태 | 대안 |
|---|---|---|
| 모든 1차 소스 원문 | **WebFetch 전면 차단** — 검색 요약만 확보 | 프록시 허용 도메인 설정 후 재조사, 또는 오너가 직접 앱 설치 확인 |
| Ladder 앱 목표 모드 | **검색 0건** | 앱스토어 리스팅 직접 확인 필요 |
| Carbon의 recomp 모드 존재 여부 | **3자 블로그 1건만 주장, 공식 도움말에는 없음** | Carbon 도움말 직접 확인 필요 |
| MacroFactor 속도 슬라이더의 실제 min/max | 녹색 구간 0.25–1%만 확보 | 앱 스크린샷 필요 |
| MyFitnessPal 속도 증분값 (0.5/1/1.5/2 lb) | **[unverified — 일반 지식]** | 앱 확인 필요 |
| "핏데이"의 동일성 | 검색된 것은 7분 음성코칭 운동앱 | 오너에게 어느 앱인지 확인 요청 |
| 밀리그램 AI 코치의 목표 추천 로직 | **비공개** | 앱 설치 후 온보딩 관찰 |
| MacroFactor "Body Composition Assessments are Less Useful Than You Think" 본문 | **제목만 확보** | 우리 앱 전제에 대한 가장 중요한 반론이므로 **재조사 우선순위 1순위** |
| InBody+ PathFinder의 "클러스터" 정확한 정의 | 한국 보도자료 요약만 | InBody+ 앱 직접 확인 |
| RP 앱 내 페이즈 설정 UI의 실제 옵션 | 기사·커뮤니티 경유 | 앱 스크린샷 필요 |

---

## 관련 파일 (절대 경로)

- `/home/user/Mybody/README.md` — 상/중/하 = 기간 설계, split 전략, `a` 스캔 역설 경고
- `/home/user/Mybody/docs/design/planning-engine.md` — §0.2 노이즈 바닥(자동 선택기의 필수 게이트), §0.3 `k_SMM→FFM = 1.75` 변환, §1 에너지 모델(Katch-McArdle / PAL / 성분 합산)
- `/home/user/Mybody/docs/design/00-owner-requirements.md`, `/home/user/Mybody/docs/design/domain-model.md`, `/home/user/Mybody/docs/design/ia-screens.md` — 미열람 (이번 스윕 범위 밖)
- `/home/user/Mybody/prototype/js/engine.js` — 모드 정의가 들어갈 위치

**Sources:**
[MacroFactor — Ready, Set, Goal!](https://macrofactor.com/goal-features/) · [MacroFactor — Algorithms and Core Philosophy](https://macrofactor.com/macrofactors-algorithms-and-core-philosophy/) · [MacroFactor — Should I Bulk or Cut?](https://macrofactor.com/bulk-or-cut/) · [MacroFactor — Reverse Dieting: Hype Versus Evidence](https://macrofactor.com/reverse-dieting/) · [MacroFactor — Body Composition Assessments are Less Useful Than You Think](https://macrofactor.com/body-composition/) · [MacroFactor Help — Set a New Goal](https://help.macrofactorapp.com/en/articles/90-set-a-new-goal) · [MacroFactor Help — Weight Gain/Loss Adjustments](https://help.macrofactorapp.com/en/articles/222-how-does-macrofactor-make-adjustments-for-a-weight-gain-or-weight-loss-goal) · [MacroFactor Help — Dynamic Maintenance](https://help.macrofactorapp.com/en/articles/125-how-does-dynamic-maintenance-work-in-macrofactor) · [MacroFactor Help — Program Styles](https://help.macrofactorapp.com/macro_program/program_styles) · [MacroFactor Help — Algorithms and Body Recomposition](https://help.macrofactorapp.com/en/articles/220-how-do-macrofactor-s-algorithms-respond-to-body-recomposition) · [FeastGood — Beginner's Guide to MacroFactor](https://feastgood.com/macrofactor-guide/) · [RP — Why Massing is Beneficial](https://rpstrength.com/blogs/articles/why-massing-is-beneficial) · [RP — Tips for a Productive Mass Phase](https://rpstrength.com/blogs/articles/tips-productive-mass-phase) · [RP Hypertrophy App](https://rpstrength.com/pages/hypertrophy-app) · [BodySpec — Renaissance Periodization: Principles and Guide](https://www.bodyspec.com/blog/post/renaissance_periodization_principles_and_guide) · [Carbon — How It Works](https://www.joincarbon.com/how-it-works) · [Carbon Help — Create your Initial goal](https://help.joincarbon.com/en/articles/6040890-how-to-create-your-initial-goal) · [Carbon Help — What is a Reverse Diet?](https://help.joincarbon.com/en/articles/6004560-what-is-a-reverse-diet) · [BarBend — Best Macros Calculator](https://barbend.com/best-macros-calculator/) · [RippedBody Macro Calculator](https://rippedbody.com/macro-calculator/) · [MyFitnessPal Help — How initial goals are calculated](https://support.myfitnesspal.com/hc/en-us/articles/360032625391-How-does-MyFitnessPal-calculate-my-initial-goals) · [MyFitnessPal Help — Updated nutrition goals](https://support.myfitnesspal.com/hc/en-us/articles/360032626031-A-Message-about-MyFitnessPal-s-updated-nutrition-goals) · [Cronometer Help — Targets + Profile](https://support.cronometer.com/hc/en-us/articles/31308427612180-Targets-Profile) · [Cronometer Help — Macro Ratios](https://support.cronometer.com/hc/en-us/articles/360020446112-Macro-Ratios) · [Fitbod Help — Getting Started](https://help.fitbod.me/hc/en-us/articles/30721771750039-Getting-Started-with-Fitbod-A-New-User-s-Guide) · [Hevy — Workout Plan Generator](https://www.hevyapp.com/features/workout-plan-generator/) · [다이어트신 (Google Play)](https://play.google.com/store/apps/details?id=com.diet.calorie160105) · [밀리그램 (App Store)](https://apps.apple.com/kr/app/id1514163957) · [핏데이 (App Store)](https://apps.apple.com/kr/app/fitday/id1060335034) · [Noom — Maintenance Mode](https://www.noom.com/support/faqs/using-the-app/daily-features/2026/03/maintenance-mode/) · [Noom — Dynamic Calorie Goals](https://www.noom.com/support/faqs/using-the-app/logging-and-tracking/food-and-water/2025/10/how-to-use-dynamic-calorie-goals/) · [InBody Results Interpretation](https://qr.inbody.com/ri/570/adult/en-US) · [myinbody.com 성인 결과 해설](http://www.myinbody.com/web_resultinfoadult.htm) · [LookinBody FAQ — Set goals from the InBody app](https://lbwebfaq.inbodyusa.com/support/solutions/articles/69000804868-how-do-i-set-goals-and-create-diet-guide-from-the-inbody-app) · [InBody HQ 보도자료](https://inbody.co.kr/press_release/contents/view/90/) · [KB손해보험 — 인바디 결과지 보는 방법](https://insight.kbinsure.co.kr/%EC%9E%90%EC%84%B8%ED%9E%88-%EB%B3%B4%EC%95%84%EC%95%BC-%EB%B9%A0%EC%A7%84%EB%8B%A4-%EC%9D%B8%EB%B0%94%EB%94%94-%EA%B2%B0%EA%B3%BC%EC%A7%80-%EB%B3%B4%EB%8A%94-%EB%B0%A9%EB%B2%95/) · [GainFrame — Bulk, Cut, or Recomp](https://gainframe.app/blog/bulk-cut-or-recomp/) · [GainFrame — Best Body Recomposition Apps](https://gainframe.app/blog/best-body-recomposition-apps/) · [LeanLens — Should I Cut, Bulk, or Recomp?](https://leanlens.ai/cut-or-bulk) · [메일리 — 벌크, 다이어트, 리컴프 어떤 것 부터?](https://maily.so/fitnessfreedom/posts/xyowd791z28) · [몬스터짐 — 린매스업·근매스업·벌크업의 차이](https://www.monsterzym.com/index.php?dispatch=community.view&community_code=coach&community_data_idx=8410696) · [브런치 — 다이어트는 그만하고 바디 리컴포지션하세요](https://brunch.co.kr/@minker/18) · [브런치 — 근손실 없는 체지방 감량](https://brunch.co.kr/@habitdesign/254) · [틸노트 — 벌크업과 커팅](https://tilnote.io/en/books/6a0af304feaf255d2099bb3c/6a0af303feaf255d2099bb08) · [Helms, Aragon & Fitschen 2014 (JISSN, PMC4033492)](https://pmc.ncbi.nlm.nih.gov/articles/PMC4033492/) · [Iraki et al. 2019 — Off-Season Nutrition (Sports, MDPI)](https://www.mdpi.com/2075-4663/7/7/154) · [Barakat et al. 2020 — Body Recomposition (S&C Journal)](https://journals.lww.com/nsca-scj/Fulltext/2020/10000/Body_Recomposition__Can_Trained_Individuals_Build.3.aspx) · [MATADOR study (Nature IJO)](https://www.nature.com/articles/ijo2017206) · [Revive Stronger — The Mini Cut Manual](https://revivestronger.com/the-mini-cut-manual/) · [Legion — Mini Cuts](https://legionathletics.com/mini-cuts/) · [Fitness Mentors — Why Most TDEE Calculations Are Wrong](https://www.fitnessmentors.com/tdee-calculator-total-daily-energy-expenditure/) · [바디프로필 준비의 기본 원칙](https://www.gazilab.co/wellness-curation/contents/TxHbTtq7XWOPVZVr5zPX/)