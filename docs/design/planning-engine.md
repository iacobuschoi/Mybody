# Mybody 플래닝 엔진 명세 (Planning Engine Spec) v0.1

> 이 문서는 **엔진 사양서**다. 프로토타입 단계에서는 이 문서의 수식/표를 `engine.js` 하나에 순수 함수로 구현하고, UI는 그 출력만 렌더한다.
> 모든 상수는 §11의 단일 상수 테이블(`ENGINE_CONSTANTS`)에서만 읽는다. 하드코딩 금지 — 검증 단계에서 오너가 숫자를 바꿔보며 피드백할 수 있어야 하기 때문이다.

**증거 수준 표기 규칙**: 각 수치 옆에 `[A]` = 메타분석/RCT 다수 지지, `[B]` = 단일 RCT·리뷰 또는 널리 쓰이는 실무 모델, `[C]` = 실무 관행·추정치(근거 약함, 튜닝 대상). 연구 인용은 기억 기반이므로 **저자/연도만 근거의 출처로 적고, 숫자는 우리 쪽 추정 범위로 표기**한다. 가짜 DOI·페이지 번호는 넣지 않는다.

---

## 0. 입력 정규화 (Input Normalization)

### 0.1 InBody 원시 필드 → 내부 스키마

OCR은 프로토타입에서 **스텁**이다(사진 업로드 → 파싱된 척 mock JSON 반환 → 사용자가 수정 가능한 폼에 프리필). 엔진은 OCR을 신뢰하지 않고 아래 스키마만 받는다.

| 내부 키 | InBody 인쇄 라벨 | 단위 | 필수 | 비고 |
|---|---|---|---|---|
| `weight` | 체중 | kg | ✅ | |
| `smm` | 골격근량 (SMM) | kg | ✅ | 사용자가 말한 "근력량" = 이 필드 |
| `bfm` | 체지방량 (BFM) | kg | ✅ | |
| `pbf` | 체지방률 (PBF) | % | ⬜ | 없으면 `bfm/weight×100` |
| `ffm` | 제지방량 (FFM) | kg | ⬜ | 없으면 `weight − bfm` |
| `bmi` | BMI | kg/m² | ⬜ | 없으면 `weight/height²` |
| `bmr_printed` | 기초대사량 | kcal | ⬜ | **검증용으로만 사용, 계산에는 미사용** (§1.4) |
| `vfl` | 내장지방레벨 | level | ⬜ | 안전 경고 트리거 |
| `whr` | 복부지방률 | ratio | ⬜ | |
| `tbw` | 체수분 | L | ⬜ | 수분 이상 감지 |
| `seg_lean[5]` | 부위별 근육분석 (우팔/좌팔/몸통/우다리/좌다리) | kg + %표준 | ⬜ | §6.5 비대칭 보정 |
| `seg_fat[5]` | 부위별 지방분석 | kg + %표준 | ⬜ | |
| `inbody_score` | InBody 점수 | 점 | ⬜ | 표시만 |

**엔진 외부 입력(사용자 폼):**
`sex`(M/F), `age`(y), `height`(cm), `training_age`(months, 주 2회 이상 웨이트 지속 기간), `job_activity`(4단계), `steps_per_day`(선택), `deadline_weeks`(목표 기간, 선택), `intensity`(상/중/하), `equipment`(헬스장/홈/맨몸), `dietary_flags`(채식/유당불내/알러지), `medical_flags`(§9).

### 0.2 측정 노이즈 바닥 (Noise Floor) — 이후 모든 판정의 전제

BIA(InBody)는 수분 상태·식사·운동 직후에 민감하다. 동일인 당일 재측정 변동폭 실무 관측치 `[C]`:

| 지표 | 단기 변동(동일 개인) | 엔진 dead-zone `ε` |
|---|---|---|
| 체중 | ±1.0 kg | `ε_W = 1.0 kg` |
| 골격근량 SMM | ±0.5 kg | `ε_SMM = 0.5 kg` |
| 체지방량 BFM | ±1.0 kg | `ε_BFM = 1.0 kg` |
| PBF | ±1.5 %p | — |

**엔진 규칙:** `|Δ| < ε` 인 목표는 "변화 없음"으로 취급한다. 그리고 **2주 미만 구간의 InBody 재측정은 추세 판단에 쓰지 않는다** (§8). UI에는 항상 이 문구를 노출:
> "InBody 수치는 수분 상태에 따라 하루에도 ±1kg 가까이 움직입니다. 일주일 단위 추세만 믿으세요."

### 0.3 파생 상수

```
FFM   = weight − bfm                       // 제지방량 (≈ LBM)
PBF   = bfm / weight × 100
SMM_ratio = smm / FFM                      // 정상 성인 ≈ 0.50–0.57
```
`SMM_ratio`가 0.45~0.60 밖이면 OCR 오독으로 간주하고 재입력 요구(`E-INPUT-01`).

**핵심 변환 계수 (문서 전체에서 재사용):**
```
k_SMM→FFM = 1.75     // 제지방 1kg 변화 시 InBody SMM은 약 0.57kg만 움직인다 [C]
                     // 즉 ΔFFM ≈ 1.75 × ΔSMM  (범위 1.4–2.0, 튜닝 대상)
```
> ⚠️ **정직한 고지**: 이 계수는 엔진 전체에서 가장 불확실한 숫자다. 근성장 속도 문헌은 대부분 **LBM/FFM** 기준인데 사용자는 **SMM** 목표를 입력한다. 변환 없이 쓰면 근성장 속도를 약 1.75배 과대평가하게 된다(대부분의 피트니스 앱이 여기서 거짓말한다). 우리는 보수적으로 변환한다.

---

## 1. 에너지 모델

### 1.1 BMR — Katch-McArdle 우선

InBody가 FFM을 직접 주므로 체성분 기반 식이 인구평균식보다 정확하다(특히 고근육/고체지방 극단 케이스) `[B]`.

```
BMR_KM = 370 + 21.6 × FFM            [kcal/day]   (Katch-McArdle)
```

보조(교차검증용):
```
BMR_CUN = 500 + 22 × FFM                          (Cunningham 1980)
```
Cunningham은 KM보다 체계적으로 높게 나온다(FFM 60kg에서 1820 vs 1666, +9%). **KM을 기본으로 쓰고 Cunningham은 상한 참고치로만 표시.**

### 1.2 Fallback — Mifflin-St Jeor (FFM 없거나 §0.3 검증 실패 시)

```
남: BMR_MSJ = 10×W + 6.25×H − 5×A + 5
여: BMR_MSJ = 10×W + 6.25×H − 5×A − 161
   W: kg, H: cm, A: years
```

### 1.3 선택 규칙

```
if (ffm 유효 && 0.45 ≤ SMM_ratio ≤ 0.60)  BMR = BMR_KM
else                                       BMR = BMR_MSJ
```
추가 안전: `BMR = clamp(BMR, 0.85×BMR_MSJ, 1.25×BMR_MSJ)` — 체성분 오독이 BMR을 터무니없이 만드는 것을 막는다.

### 1.4 InBody 인쇄 BMR 처리

InBody 기기도 FFM 기반 회귀식으로 BMR을 찍어주지만 **모델/펌웨어마다 계수가 다르다**(대체로 Cunningham 또는 Katch-McArdle 계열). 엔진은 이를 계산에 쓰지 않고, `|BMR_printed − BMR| / BMR > 0.10` 이면 배지로 표시:
> "InBody 인쇄 기초대사량(1,820kcal)과 계산값(1,709kcal) 차이가 6% 이상입니다. 계산값을 기준으로 진행합니다."

### 1.5 TDEE — 두 갈래

**(A) 빠른 경로: 활동계수(PAL) 곱**

```
TDEE_fast = BMR × PAL
```

| PAL | 라벨(UI) | 설명 |
|---|---|---|
| 1.20 | 거의 안 움직임 | 사무직 + 운동 없음, 5,000보 미만 |
| 1.375 | 가볍게 활동 | 주 1–3회 운동, 5–8천 보 |
| 1.55 | 보통 활동 | 주 3–5회 운동, 8–12천 보 |
| 1.725 | 많이 활동 | 주 6–7회 운동 또는 육체노동 |
| 1.90 | 매우 많이 활동 | 하루 2회 훈련 / 고강도 육체노동 |

> ⚠️ **정직한 고지**: PAL 곱은 개인차 ±20%가 흔하고, 대중적으로 **과대추정**되는 경향이 있다(사람들이 자기 활동량을 과대평가). 엔진은 최초 2주간 이 값을 **가설**로만 쓰고, §8의 적응형 TDEE로 즉시 교정한다. UI에도 "첫 2주는 추정치입니다"를 명시.

**(B) 정밀 경로: 성분 합산 (권장, 걸음수 있을 때)**

```
RMR   = BMR
NEAT  = steps_per_day × 0.00045 × weight        // ≈ 0.45 kcal per 1,000보·kg [C]
                                                 // 예: 8,000보 × 82kg → 295 kcal
BASE  = RMR × 1.10                              // 수면·기립·소화 외 기본 대사 여유 [C]
EAT   = Σ(session_MET × 3.5 × weight / 200 × minutes) / 7    // 일평균 운동 소비
TEF   = 0.10 × intake_kcal                      // 혼합식 식이유발열생성 10% [A]
                                                 // (고단백 계획이면 0.12 사용)
TDEE_component = BASE + NEAT + EAT
TDEE           = TDEE_component / (1 − TEF_ratio)   // TEF를 섭취량에 비례시켜 자기일관 해
                                                     // = TDEE_component / 0.90
```

MET 참조값 `[B]`: 웨이트 트레이닝(보통 강도) 5.0, 고강도 서킷 8.0, 걷기 5km/h 3.5, 조깅 8km/h 8.3, 자전거(보통) 7.0, 수영 7.0.

**엔진 기본값**: `steps_per_day`가 있으면 (B), 없으면 (A). 두 값이 15% 이상 벌어지면 낮은 쪽을 채택(보수적).

### 1.6 조직 에너지 밀도 — 목표→칼로리 변환의 근간

| 조직 | kcal/kg | 근거 |
|---|---|---|
| 지방조직(adipose) | **7,700** | 지방 87% × 9.4 kcal/g `[A]` — Wishnofsky 규칙 |
| 제지방(수분 포함) | **1,800** | 단백질 4 kcal/g × ~22% + 글리코겐/수분 `[B]` |
| 근조직 **합성 비용**(잉여 필요량) | **2,200** | 저장 에너지 1,800 + 합성 비효율 `[C]` |

> ⚠️ Wishnofsky의 7,700 kcal/kg 선형 규칙은 **장기(>3개월) 예측에서 감량을 과대추정**한다(대사적응·활동량 감소 때문). Hall의 동적 모델이 정확하지만 프로토타입에는 과하다. 대신 §8의 주간 재조정으로 오차를 흡수하고, 12주 초과 계획에는 **적응 감쇠**를 적용한다:
> ```
> 대사적응 보정:  TDEE_week(n) = TDEE_0 × (1 − 0.0025×n)   // 주당 −0.25%, 최대 −10%까지 [C]
> ```
> (감량 구간에만 적용. 증량/유지에는 미적용.)

---

## 2. 실현 강도 상 / 중 / 하 — 파라미터 표

### 2.1 설계 철학

`하`는 "평생 유지 가능", `중`은 "3~6개월 프로젝트", `상`은 "8~12주 단기 집중, 이후 반드시 회복기". **상은 기본값이 아니며, 선택 시 §9의 경고 팝업을 통과해야 한다.**

### 2.2 감량(Cut) 파라미터

| 항목 | 하 (지속형) | 중 (표준) | 상 (집중형) |
|---|---|---|---|
| 주간 체중 변화율 (%BW/wk) | **0.25–0.40%** | **0.50–0.75%** | **0.75–1.00%** |
| 〃 (kg/wk, 82kg 기준) | 0.21–0.33 kg | 0.41–0.62 kg | 0.62–0.82 kg |
| 목표 설정값(중앙) | 0.33 %BW | 0.60 %BW | 0.90 %BW |
| 칼로리 적자 (% TDEE) | **10–15%** | **18–22%** | **25–30%** |
| 〃 (kcal/day, TDEE 2,350) | 235–350 | 420–520 | 590–700 |
| 단백질 (g/kg **FFM**) | **1.8** | **2.2** | **2.6** (최대 3.0) |
| 〃 (g/kg BW 환산, PBF 24%) | ≈1.36 | ≈1.66 | ≈1.97 |
| 지방 (g/kg BW) | 0.8–1.0 | 0.7–0.9 | 0.5–0.7 (하한) |
| 웨이트 일수/주 | **3** | **4** | **5–6** |
| 세션 길이 | 40–50분 | 55–70분 | 70–90분 |
| 유산소 (분/주) | **60–90** (Z2 2회) | **120–150** (3–4회) | **180–300** (4–6회, HIIT ≤2) |
| 주당 근육군 세트 수 | 8–10 | 12–16 | 16–22 |
| 디로드 주기 | 8–10주 | 6주 | 4주 |
| 식사 기록 요구 | 단백질만 | 칼로리+단백질 | 4대 매크로 전부 + 주 4회 체중 |
| 순응 난이도 | ★☆☆ | ★★☆ | ★★★ |
| **근손실 위험** | **매우 낮음** | **낮음** | **중간–높음** |
| 권장 최대 지속 | 무기한 | 16–20주 | **10–12주 (하드캡)** |

**근거 정리 (수치의 출처 논리):**
- **0.5–1.0 %BW/주 상한**: Garthe 등(2011)이 엘리트 선수에서 느린 감량(주 ~0.7%)과 빠른 감량(주 ~1.4%)을 비교했을 때, 빠른 쪽이 제지방 보존에 불리했다. Helms 등(2014)의 자연 보디빌딩 리뷰도 0.5–1.0 %BW/주 범위를 권고한다. → **1.0%를 상한으로, 1.2% 초과는 엔진이 거부.**
- **단백질 2.3–3.1 g/kg FFM**: Helms 등(2014)이 감량 중 제지방 유지를 위해 제시한 범위. Morton 등(2018) 메타분석은 총 단백질 ~1.6 g/kg BW에서 근비대 효과가 정체되지만 신뢰구간 상한이 2.2 g/kg BW까지 열려 있다고 보고. **감량 적자가 클수록 단백질을 올린다**는 것이 두 근거의 교집합 → 하/중/상에 1.8/2.2/2.6 g/kg FFM.
- **고단백 + 대적자 + 저항운동에서도 제지방 증가 가능**: Longland 등(2016)이 큰 적자에서 2.4 g/kg BW 고단백군이 제지방을 늘린 결과. 단, 대상은 **훈련 경험 적은 젊은 남성**이었다 — 숙련자에게 일반화 금지(§4).
- **체지방률이 높을수록 공격적 적자가 안전**: Forbes의 p-ratio 개념 — 초기 체지방이 많을수록 에너지 결손의 더 큰 비율을 지방에서 충당한다. → §2.4의 PBF 게이트.

### 2.3 증량(Bulk) 파라미터

| 항목 | 하 (린벌크) | 중 | 상 |
|---|---|---|---|
| 주간 체중 변화율 (%BW/wk) | **+0.10–0.20%** | **+0.20–0.35%** | **+0.35–0.50%** |
| 〃 (kg/wk, 82kg) | +0.08–0.16 | +0.16–0.29 | +0.29–0.41 |
| 칼로리 잉여 (% TDEE) | **+5–8%** | **+10–15%** | **+15–20%** |
| 〃 (kcal/day) | +120–190 | +235–350 | +350–470 |
| 단백질 (g/kg FFM) | 2.0 | 2.2 | 2.2 |
| 지방 (% kcal) | 25–30% | 25% | 20–25% |
| 웨이트 일수/주 | 3 | 4 | 5–6 |
| 유산소 (분/주) | 90 (심폐 유지) | 90–120 | 60–90 (간섭효과 회피) |
| 주당 근육군 세트 수 | 10–12 | 14–18 | 18–24 |
| **예상 지방 동반 증가율** | ~30% | ~40–50% | **~55–65%** |
| 순응 난이도 | ★☆☆ | ★★☆ | ★★★ (소화 부담) |

> **정직한 고지**: 증량에서 "상" 강도는 **근육이 더 빨리 붙는 게 아니라 지방이 더 빨리 붙는다.** 근성장 속도는 §4의 생리적 상한에 걸려 있고, 잉여를 키운다고 그 상한이 올라가지 않는다. 상 강도 증량은 **저체중(BMI<20) 또는 명백한 하드게이너**에게만 권장하도록 UI에서 유도한다.

### 2.4 강도 게이트 (사용자가 고른 강도를 엔진이 강등하는 조건)

```
상 선택 거부/강등 조건:
  PBF < 12% (남) 또는 < 20% (여)        → 중으로 강등, 사유 표시
  BMI < 20                              → 중으로 강등
  training_age < 3개월                  → 중으로 강등 ("몸이 적응할 시간 필요")
  age < 18 또는 > 65                    → 중으로 강등
  medical_flags 존재                    → 하로 강등 + 의료 상담 배너
  최근 16주 내 '상' 감량 이력            → 하 권고 (누적 대사적응)

중/상 공통 클램프:
  일일 적자 ≤ min(0.30×TDEE, MAX_FAT_MOBILIZATION)
```

### 2.5 지방 동원 속도 상한 (Max Fat Mobilization Cap) — 상 강도의 진짜 천장

체지방이 적은 사람에게 큰 적자를 주면 **부족분은 지방이 아니라 근육과 대사율에서 나온다.** Alpert(2005)는 저식이 상태에서 체지방 저장고로부터의 에너지 전달률에 상한이 있음을 모델링했다(대략 290 kJ·kg FM⁻¹·day⁻¹ ≈ **69 kcal/kg FM/day** 수준의 생리적 천장; 다만 이는 고도비만 데이터 기반이라 마른 사람에게 그대로 쓰면 안 된다).

**엔진은 보수적 실무 상한을 쓴다** `[C]`:
```
MAX_FAT_MOBILIZATION = 31 × BFM          [kcal/day]     // 설계 상한 (기본)
HARD_PHYSIO_CEILING  = 69 × BFM          [kcal/day]     // 절대 금지선, 넘으면 즉시 거부
```

**작동 예시 (82kg, BFM 20kg, TDEE 2,350):**
- 상 강도 30% 적자 = 705 kcal/day
- 상한 = 31 × 20 = **620 kcal/day**
- → 엔진이 620으로 클램프하고 UI에 표시:
  > "요청하신 강도의 적자(705kcal)는 현재 체지방량(20.0kg)이 안정적으로 공급할 수 있는 한계(620kcal)를 넘습니다. 620kcal로 조정했습니다. 감량 속도는 주 0.79%가 됩니다."

이 캡이 바로 **체지방률이 낮아질수록 자동으로 적자가 줄어드는** 메커니즘이다. BFM 10kg인 사람은 캡이 310 kcal/day라서 아무리 "상"을 골라도 공격적 감량이 불가능해진다 — 이게 생리적으로 맞다.

---

## 3. 목표 분류 (Goal Classification)

### 3.1 입력 델타 정의

사용자는 **목표값** 또는 **변화량** 중 하나로 입력한다. 엔진은 변화량으로 정규화:
```
ΔW    = target_weight − current_weight        // 음수 = 감량
ΔSMM  = target_smm    − current_smm           // 양수 = 근육 증가
ΔBFM  = target_bfm    − current_bfm           // 음수 = 체지방 감소
```
목표 3개 중 **2개만 입력해도 세 번째를 추정**한다(§3.3).

### 3.2 분류 규칙 (순서대로 평가, 첫 매치 채택)

`ε_W=1.0`, `ε_SMM=0.5`, `ε_BFM=1.0` (§0.2)

```
R0  CONTRADICTORY : 일관성 검사 실패 (§3.3)          → 사용자에게 우선순위 질의
R1  MAINTAIN      : |ΔW|<ε_W ∧ |ΔSMM|<ε_SMM ∧ |ΔBFM|<ε_BFM
R2  RECOMP        : ΔSMM ≥ +ε_SMM ∧ ΔBFM ≤ −ε_BFM
R3  CUT           : ΔBFM ≤ −ε_BFM ∧ ΔSMM < +ε_SMM
                    └ 하위유형 CUT_PRESERVE : ΔSMM ≥ −ε_SMM (근육 유지하며 감량, 기본)
                    └ 하위유형 CUT_AGGRESSIVE : ΔSMM < −ε_SMM (근손실 감수 — 경고 후 진행)
R4  BULK          : ΔSMM ≥ +ε_SMM ∧ ΔBFM > −ε_BFM
                    └ 하위유형 BULK_LEAN  : ΔBFM ≤ +ε_BFM
                    └ 하위유형 BULK_DIRTY : ΔBFM > +ε_BFM (지방 증가 수용)
R5  FAT_GAIN_ONLY : ΔBFM ≥ +ε_BFM ∧ ΔSMM < ε_SMM     → 이상 입력, 재확인 팝업
R6  UNKNOWN       : 그 외                             → 재입력
```

### 3.3 일관성 검사 (Over-determination Check)

세 값은 독립이 아니다:
```
잔차 r = ΔW − ( k_SMM→FFM × ΔSMM + ΔBFM )
        = ΔW − ( 1.75 × ΔSMM + ΔBFM )

허용 오차 τ = max(1.5 kg, 0.03 × current_weight)
```

**`|r| > τ` 이면 모순 입력** → 팝업으로 우선순위를 묻는다. 우선순위 기본 정책:
> **BFM > SMM > W** (체중은 파생값이다. 사용자가 진짜 원하는 건 몸 구성이지 저울 숫자가 아니다.)

채택된 두 값으로 세 번째를 **재계산**하고 UI에 알린다:
> "입력하신 목표 체중(70kg)과 체지방/근육 목표가 서로 맞지 않습니다(차이 4.2kg).
> 체지방 −8kg, 골격근 +2kg을 달성하면 체중은 약 **77.5kg**이 됩니다. 목표 체중을 77.5kg으로 조정할까요?"
> `[체성분 기준으로 조정]` `[체중 기준으로 조정]` `[직접 수정]`

### 3.4 모순 목표의 대표 케이스 처리

**"8주에 근육 +5kg, 체지방 −10kg"**
1. R2 RECOMP로 분류됨 → §4 실현가능성 검사로 넘어감
2. 근성장: ΔFFM 필요량 = 1.75 × 5 = **8.75 kg**. 중급자 리컴프 상한(§4.2)으로 8.75 / 0.15 kg/wk ≈ **58주**
3. 지방감량: 10 kg / (0.5%BW/wk 리컴프 캡 = 0.41 kg/wk) ≈ **24주**
4. 결속 조건(binding) = 근성장 58주 ≫ 8주 → **비현실적**
5. 엔진은 **거부하지 않고 3개의 대안을 제시** (§4.5):
   - **A. 기간 연장**: 같은 목표, 58주 계획
   - **B. 목표 축소**: 8주에 달성 가능한 실제치 = 체지방 −3.3kg, 골격근 +0.5kg
   - **C. 단계 분할(권장)**: 12주 감량(−6kg 지방, 근육 유지) → 2주 유지 → 16주 린벌크(+1.5kg SMM) → 재평가

---

## 4. 실현가능성 검사 (Feasibility)

### 4.1 근성장 속도 상한 — 여기가 대부분의 앱이 거짓말하는 지점

**훈련연령별 최대 제지방(LBM) 증가율** — Aragon의 실무 모델 계열 `[B/C]`. **약물 미사용, 최적 조건(잉여·수면·프로그램 순응) 전제의 상한**이며 평균이 아니다.

| 훈련연령 | 남성 (%BW/월) | 여성 (%BW/월) | 남 82kg → kg FFM/주 | 남 82kg → **kg SMM/주** |
|---|---|---|---|---|
| 초급 (0–12개월) | 1.0–1.5% | 0.5–0.75% | 0.19–0.28 | **0.11–0.16** |
| 중급 (12–36개월) | 0.5–1.0% | 0.25–0.5% | 0.09–0.19 | **0.05–0.11** |
| 고급 (36개월+) | 0.25–0.5% | 0.125–0.25% | 0.05–0.09 | **0.03–0.05** |
| 상급자 정체 (5년+) | 0.1–0.25% | 0.05–0.125% | 0.02–0.05 | **0.01–0.03** |

엔진 기본값은 각 구간의 **중앙값**을 쓴다(상한이 아니라). 연간 환산 `[B]`:
- 남 초급 ≈ 8–11 kg FFM/년 → **SMM 기준 4.5–6.3 kg/년**
- 남 중급 ≈ 4–5 kg → SMM 2.3–2.9 kg/년
- 남 고급 ≈ 2 kg → SMM 1.1 kg/년

> ⚠️ **정직한 고지 3가지**
> 1. 이 표는 **관찰 기반 실무 모델**이지 RCT 메타분석이 아니다. 개인 편차가 크다(반응자/비반응자).
> 2. **InBody가 보여주는 초기 SMM 증가분의 상당 부분은 근육이 아니라 글리코겐+수분**이다. 훈련 시작 2–4주에 SMM이 +1kg 뛰는 건 흔하며 진짜 근육이 아니다. 엔진은 **첫 4주의 SMM 증가를 신뢰 구간에서 제외**한다.
> 3. 나이 보정: 40세 이상은 위 값에 ×0.8, 50세 이상 ×0.65를 적용 `[C]`.

```
muscle_rate_smm_per_week(sex, training_age, age) =
    BASE[training_age][sex] × weight / 100 / 4.345 / k_SMM→FFM × age_factor(age)
```

### 4.2 상황별 속도 배율

| 상황 | 근성장 배율 | 지방감량 배율 | 비고 |
|---|---|---|---|
| 증량(잉여) | ×1.00 | — | 기준 |
| 유지(TDEE±5%) | ×0.50 | ×0.15 | 느린 리컴프 |
| 리컴프(경미한 적자 ≤15%) | 초급 ×0.70 / 중급 ×0.35 / 고급 ×0.15 | ×0.80 (상한 0.5%BW/wk) | §4.3 |
| 감량 중(적자 >15%) | 초급 ×0.30 / 중급 ×0.05 / 고급 **×0.00** | ×1.00 | 고급자는 감량 중 근성장 **0으로 계획**한다 |
| 훈련 재개(과거 최고치 이하) | ×2.0–3.0 (머슬메모리) | — | `had_prior_peak=true`일 때만 |

**리컴프 타당성 규칙** — 리컴프가 현실적인 대상 `[B]`:
- 훈련 초급자 (training_age < 12개월) ✅
- 오래 쉬었다 복귀 (머슬메모리) ✅
- 체지방률 높음 (남 >20%, 여 >28%) ✅
- 위 셋 중 **하나도 해당 안 되는 중/고급 + 저체지방** → 리컴프는 사실상 불가능. UI 경고:
  > "훈련 경력 3년 이상, 체지방률 15%대에서 동시에 근육을 늘리고 지방을 빼는 건 현실적으로 매우 느립니다. **감량 후 증량**으로 나누는 편이 총 소요 기간이 짧습니다."

### 4.3 지방감량 속도 상한

```
fat_rate_max_per_week = min(
    INTENSITY_RATE[level].max × weight,              // 예: 상 1.0%BW
    MAX_FAT_MOBILIZATION / 7700,                      // 31×BFM/7700 kg/wk
    (recomp ? 0.005 × weight : ∞),                    // 리컴프는 0.5%BW/wk로 캡
    (intake_floor_binding ? 계산된 최대치 : ∞)         // §9 칼로리 바닥에 걸린 경우
)
```

### 4.4 필요 기간 계산

```
D_fat_weeks    = |ΔBFM| / fat_rate_per_week          (ΔBFM<0일 때)
D_muscle_weeks = ΔSMM   / muscle_rate_smm_per_week   (ΔSMM>0일 때, §4.2 배율 적용)

목표 유형별 결속 기간:
  CUT     → D_req = D_fat
  BULK    → D_req = D_muscle
  RECOMP  → D_req = max(D_fat, D_muscle)      // 동시 진행이므로 max
  MAINTAIN→ D_req = 0
```

### 4.5 판정 및 메시지

`T` = 사용자 희망 기간(`deadline_weeks`). 미입력 시 `T = D_req`로 두고 무조건 **실현가능**.

| 판정 | 조건 | 배지 | UI 메시지 (한국어) |
|---|---|---|---|
| **실현가능** | `D_req ≤ T` | 🟢 | "현재 계획으로 **{T}주** 안에 목표 달성이 가능합니다. 예상 소요: 약 {D_req}주." |
| **도전적** | `T < D_req ≤ 1.5×T` | 🟡 | "목표는 가능하지만 **{D_req}주**가 필요합니다({T}주보다 {D_req−T}주 깁니다). 순응도가 완벽해야 하고, 한 주만 흐트러져도 밀립니다. 기간을 늘리거나 강도를 한 단계 올리는 방법이 있습니다." |
| **비현실적** | `D_req > 1.5×T` | 🔴 | "죄송하지만 **{T}주 안에는 불가능합니다.** 생리적으로 근육은 주당 최대 {rate}kg까지만 늘어납니다(훈련경력 {ta}개월 기준). 정직하게 말씀드리면 이 목표엔 약 **{D_req}주**가 필요합니다." + 대안 3종 |
| **위험/거부** | §9 안전 조건 위반 | ⛔ | §9 문구 |

**비현실적일 때 반드시 함께 제시하는 대안 3종 (엔진이 계산해서 채운다):**
```
A. 기간을 {D_req}주로 늘리기          → 동일 목표, 동일 강도
B. {T}주에 맞춰 목표를 조정하기        → ΔBFM' = −fat_rate×T, ΔSMM' = muscle_rate×T
C. 단계를 나누기 (권장)               → Phase1 감량 {w1}주 → 유지 2주 → Phase2 증량 {w2}주
```

### 4.6 절대 거부 조건 (강도/기간과 무관)

```
target_pbf < ESSENTIAL_FAT[sex] + 3        // 남 8%, 여 15% 미만 목표 → 거부
target_bmi < 18.5                          // 저체중 목표 → 거부
|ΔW| / T > 0.015 × weight                  // 주 1.5%BW 초과 → 거부
required_intake < KCAL_FLOOR (§9)          // 칼로리 바닥 미달 → 거부
ΔSMM > 0 && required_surplus > 0.25×TDEE   // 과도 증량 → 거부
```

---

## 5. 매크로 분배 (Macro Split)

### 5.1 연산 순서 (반드시 이 순서)

```
STEP 1  목표 칼로리
    target_kcal = TDEE + energy_delta
      where  energy_delta = −min(deficit_pct×TDEE, MAX_FAT_MOBILIZATION)   (감량)
                          = +surplus_pct × TDEE                             (증량)
                          = 0                                               (유지/리컴프 기본)
      리컴프는 target_kcal = TDEE − 0.10×TDEE 를 기본(경미 적자), 초급자는 TDEE 그대로.

STEP 2  단백질 (최우선 — 고정)
    protein_g = P_PER_KG_FFM[level] × FFM
    protein_g = clamp(protein_g, 1.6×weight, min(3.2×FFM, 0.40×target_kcal/4))
    protein_kcal = protein_g × 4

STEP 3  지방 (하한 방어)
    fat_g_target = FAT_PCT[level] × target_kcal / 9
    fat_g_floor  = max(0.5 × weight, 0.15 × target_kcal / 9)     // 호르몬/지용성비타민 하한
    fat_g        = max(fat_g_target, fat_g_floor)
    fat_kcal     = fat_g × 9

STEP 4  탄수화물 (나머지)
    carb_kcal = target_kcal − protein_kcal − fat_kcal
    carb_g    = carb_kcal / 4

STEP 5  탄수 하한 검사 및 재분배
    carb_g_floor = (training_days ≥ 4 ? 2.0 : 1.5) × weight     // 훈련 수행 유지 하한
    if (carb_g < carb_g_floor):
        (a) 지방을 fat_g_floor까지 내려 탄수로 이전
        (b) 그래도 부족하면 단백질을 1.8 g/kg FFM까지 내림
        (c) 그래도 부족하면 → 적자를 줄인다 (강도 강등, 사용자 고지)
        (d) 그래도 부족 → 목표 비현실 판정으로 회귀

STEP 6  부가 목표
    fiber_g  = 14 × target_kcal / 1000        // 최소 25g(여)/30g(남)
    water_ml = 35 × weight  + 500×(훈련일)
    sodium   ≤ 2,300 mg 권고 (한식 특성상 별도 경고 §7.6)
    alcohol  = 0 (계획 내 미배정)
```

### 5.2 훈련일/비훈련일 칼로리 사이클링 (중·상 강도만)

주간 총량은 고정하고 배분만 바꾼다(순응도↑, 훈련 수행↑) `[B]`:
```
훈련일   = weekly_kcal × (1 + 0.10) / 7 배분
비훈련일 = weekly_kcal × (1 − 0.10×training_days/(7−training_days)) / 7
단백질·지방은 고정, 차이는 전량 탄수화물로 조정.
```

### 5.3 계산 예시 (82kg 남, FFM 62kg, PBF 24.4%, TDEE 2,350, **중** 강도 감량)

```
STEP1  적자 20% = 470 kcal (캡 620 미만 OK)  → target_kcal = 1,880
STEP2  단백질 2.2 × 62 = 136 g → 546 kcal   (BW 기준 1.66 g/kg, 하한 1.6×82=131 충족)
STEP3  지방 25% × 1880 / 9 = 52 g; 하한 max(41, 31) = 41 → fat_g = 52 g → 470 kcal
STEP4  탄수 = 1880 − 546 − 470 = 864 kcal → 216 g
STEP5  탄수 하한 2.0×82 = 164 g < 216 ✅ 통과
STEP6  식이섬유 26 g, 물 2,870 mL + 훈련일 500

최종: 1,880 kcal / P 136g / F 52g / C 216g  (P29% F25% C46%)
예상 감량 속도: 470 × 7 / 7700 = 0.43 kg/주 = 0.52 %BW/주 ✅ 중 강도 밴드 내
```

---

## 6. 운동 프로그램 생성

### 6.1 분할(Split) 선택 — 주당 훈련일수로 결정

| 일수 | 분할 | 구성 | 근육군당 주간 빈도 |
|---|---|---|---|
| 2 | 전신 A/B | FB-A, FB-B | 2회 |
| 3 | 전신 A/B/C | FB-A, FB-B, FB-C | 3회 |
| 4 | 상하체 2회전 | U-A, L-A, U-B, L-B | 2회 |
| 5 | 상하체 + PPL 혼합 | U, L, Push, Pull, Legs | 2–2.5회 |
| 6 | PPL 2회전 | P/P/L × 2 | 2회 |

근육군당 **주 2회 이상 자극**이 주 1회보다 비대에 유리하다는 Schoenfeld 등(2016)의 빈도 메타분석 결과를 기본 제약으로 둔다 `[A]`. 총 볼륨이 같으면 빈도 효과는 작지만, 고볼륨을 소화하려면 분산이 필요하다.

### 6.2 볼륨 랜드마크 (주당 직접 세트 수 / 근육군)

Israetel의 MV/MEV/MAV/MRV 프레임 `[C]` + Schoenfeld 등(2017)의 용량-반응 메타분석(주 10세트 이상에서 이득 증가, 상한은 불명확) `[B]`.

| 근육군 | MV(유지) | MEV(최소효과) | MAV(최적대) | MRV(회복한계) |
|---|---|---|---|---|
| 가슴 | 4 | 8 | 12–20 | 22 |
| 등 | 6 | 10 | 14–22 | 25 |
| 어깨(측면) | 4 | 8 | 16–22 | 26 |
| 이두 | 4 | 8 | 14–20 | 26 |
| 삼두 | 4 | 6 | 10–18 | 22 |
| 대퇴사두 | 6 | 8 | 12–18 | 20 |
| 햄스트링 | 3 | 6 | 10–16 | 20 |
| 둔근 | 0 | 4 | 8–16 | 16 |
| 종아리 | 6 | 8 | 12–16 | 20 |
| 복부 | 0 | 6 | 12–16 | 20 |

**강도별 배정:**
```
하  → MEV 밴드 (각 근육 MEV ± 1세트)
중  → MAV 하단 (MEV + (MAV_low−MEV)×0.6)
상  → MAV 상단 (MAV_high), 단 MRV의 85% 초과 금지

감량 적자 중 보정:  volume × (1 − 0.5 × deficit_pct)
   예: 25% 적자 → 볼륨 ×0.875  (회복력 저하 반영)
증량 잉여 중 보정:  volume × 1.0 (그대로)
```

### 6.3 세트/반복/강도 처방

| 역할 | 반복 범위 | RPE(하) | RPE(중) | RPE(상) | 휴식 |
|---|---|---|---|---|---|
| 주요 복합(스쿼트/데드/벤치/로우) | 4–8 | 6–7 | 7–8 | 8–9 | 3–5분 |
| 보조 복합(런지/딥스/친업) | 6–12 | 6–7 | 7–8 | 8–9 | 2–3분 |
| 고립(사이드레터럴/컬/익스텐션) | 10–20 | 7–8 | 8–9 | 9–10 | 60–90초 |

> 반복 범위 자체보다 **충분한 자극(세트당 실패까지 0–3회 여유)**이 비대 결정 요인 — 저반복/고반복 모두 유사한 비대를 낸다는 것이 Schoenfeld 등의 반복범위 메타분석 결론 `[A]`. 따라서 엔진은 범위를 넓게 주고 RPE로 조인다.

### 6.4 점진적 과부하 (Double Progression)

```
for each exercise:
  if (모든 세트가 반복범위 상단 도달 && 마지막 세트 RPE ≤ 목표RPE):
      상체: +2.5 kg  /  하체: +5 kg  /  고립: +1.25~2.5 kg
      반복은 범위 하단으로 리셋
  elif (2주 연속 동일 무게·반복 정체):
      (감량기) → "유지 = 성공"으로 표시, 무게 유지
      (증량기) → 세트 1개 추가 또는 종목 변형

디로드 트리거 (자동, OR 조건):
  - 계획 주기 도달 (하 8–10주 / 중 6주 / 상 4주)
  - 주요 종목 수행 2주 연속 하락
  - 동일 무게에서 RPE가 1.5 이상 상승
  - 자가보고 수면·통증 점수 2주 연속 저하
디로드 내용: 볼륨 −50%, 강도 −10%, 기간 1주
```

**감량기 프로그램 목표 재정의(중요, UI 문구):**
> "감량 중에는 기록이 안 늘어도 정상입니다. **기존 무게·반복을 유지하는 것 자체가 성공**이며, 그게 근육이 빠지지 않았다는 가장 좋은 증거입니다."

### 6.5 부위별 InBody 데이터 → 종목 선택 편향

InBody 부위별 근육분석은 5개 세그먼트를 **kg + 표준대비%**로 준다.

```
좌우 비대칭 지수:
  ASI_arm = (RA − LA) / ((RA + LA)/2) × 100    [%]
  ASI_leg = (RL − LL) / ((RL + LL)/2) × 100

상하체 균형 지수:
  ULI = (평균 팔 표준대비% ) − (평균 다리 표준대비%)

몸통 대비 사지:
  TRUNK_GAP = 몸통 표준대비% − 사지 평균 표준대비%
```

| 조건 | 임계 | 엔진 처방 |
|---|---|---|
| `|ASI| ≥ 10%` | 명백한 비대칭 | 해당 부위 **일측성 종목 필수 편성**(덤벨/유니래터럴 머신). 약측 먼저 수행, 약측 세트 +1~2, 강측은 약측이 수행한 반복수에 맞춤. 재평가까지 8주. 경고 배지 표시. |
| `5% ≤ |ASI| < 10%` | 경미 | 일측성 종목 1개 삽입, 약측 우선 수행. 세트 추가 없음. |
| `|ASI| < 5%` | 정상 범위 | 조치 없음 (측정 오차 수준) |
| `ULI ≥ +15%p` | 하체 미달 | 하체 볼륨을 MAV 상단으로, 상체는 MEV~MAV 하단. 스쿼트/힌지 주 2회 이상. |
| `ULI ≤ −15%p` | 상체 미달 | 상체 볼륨 우선, 등>가슴 비율 1.2:1(자세 교정 목적). |
| `TRUNK_GAP ≥ +10%p` | 사지 미달 | 고립 볼륨 비중↑ |
| 부위별 **지방** 편중(복부) or `VFL ≥ 10` | 내장지방 | 유산소 하한을 한 단계 올림 + §9 경고 |

> ⚠️ **정직한 고지**: BIA 부위별 값은 임피던스 기반 추정이며 좌우 5% 내외 차이는 **측정 오차와 구분되지 않는다.** 그래서 임계를 10%로 잡고, 5–10%는 "무해한 보정"만 넣는다. 부위별 수치로 "왼팔에 근육을 몇 kg 붙이자" 같은 목표는 엔진이 절대 만들지 않는다.

### 6.6 종목 풀과 장비 필터

각 종목은 `{name_ko, pattern, primary[], secondary[], equipment[], unilateral, skill_level, kcal_MET}` 로 태깅. 패턴 커버리지 제약(모든 프로그램이 만족해야 함):
```
필수 패턴: 스쿼트계, 힌지계, 수평 밀기, 수평 당기기, 수직 밀기, 수직 당기기, 코어
주 4일 이상: 각 패턴 주 1회 이상
주 3일(전신): 각 패턴 주 1회 이상을 3일에 분산
equipment 필터로 풀을 좁힌 뒤, 커버리지 미충족 패턴은 대체 종목(맨몸/밴드)으로 채움
```

---

## 7. 식단 생성

### 7.1 식사 횟수

| 강도/상황 | 식사 수 | 근거 |
|---|---|---|
| 하 | 3식 (+간식 1) | 순응 우선 |
| 중 | 4식 | 단백질 분배 최적 |
| 상 (감량) | 4–5식 (포만감 분산) | 큰 적자에서 배고픔 관리 |
| 상 (증량) | 5–6식 | 총량 소화 문제 |

### 7.2 끼니별 단백질 분배

Schoenfeld & Aragon(2018)의 분배 리뷰: 총량이 우선이지만, **끼니당 0.4 g/kg BW를 3–5회**가 실무 최적 `[B]`. 류신 역치 ~2.5–3 g.

```
protein_per_meal = protein_g / meal_count
제약: protein_per_meal ≥ 0.35 × weight  (못 맞추면 meal_count를 줄인다)
      protein_per_meal ≤ 60 g            (초과분은 다른 끼니로 이월)
취침 전 마지막 끼니: 카제인성 단백(그릭요거트/코티지치즈/두부) 우선 배치
훈련 전후 ±2시간 내 끼니에 탄수 배분 가중치 1.3
```

### 7.3 한식 기반 템플릿 — 식품교환표 방식

한국인에게 "닭가슴살 150g + 브로콜리" 식단은 순응도가 낮다. 대신 **대한당뇨병학회 식품교환표**(한국 임상·급식에서 표준)를 단위로 쓴다 `[B]`.

| 교환군 | 1교환 kcal | 탄수(g) | 단백(g) | 지방(g) | 대표 1교환 분량 |
|---|---|---|---|---|---|
| 곡류군 | 100 | 23 | 2 | — | 밥 70g(1/3공기), 식빵 1쪽, 고구마 70g |
| 어육류군 – 저지방 | 50 | — | 8 | 2 | 닭가슴살 40g, 흰살생선 50g, 새우 50g |
| 어육류군 – 중지방 | 75 | — | 8 | 5 | 삼겹 제외 돼지 40g, 계란 1개, 두부 80g |
| 어육류군 – 고지방 | 100 | — | 8 | 8 | 삼겹살 40g, 갈비, 치즈 30g |
| 채소군 | 20 | 3 | 2 | — | 나물 70g, 김치 50g, 쌈채소 |
| 지방군 | 45 | — | — | 5 | 식용유 1작은술, 견과 8g, 참기름 1작은술 |
| 우유군 – 일반 | 125 | 10 | 6 | 7 | 우유 200mL |
| 우유군 – 저지방 | 80 | 10 | 6 | 2 | 저지방우유 200mL |
| 과일군 | 50 | 12 | — | — | 사과 1/3개, 바나나 1/2개, 귤 1개 |

참고 환산: **밥 1공기(210g) = 곡류군 3교환 = 300 kcal / 탄수 69g**

### 7.4 교환단위 배정 알고리즘

```
ALLOCATE_EXCHANGES(target P, F, C, kcal):
  1) 채소군 = 7교환/일 고정          → C 21g, P 14g, 140 kcal   (식이섬유·포만감 확보)
  2) 과일군 = (감량 1 / 유지 2 / 증량 2) 교환
  3) 우유군 = 1교환 (감량은 저지방, 증량은 일반)
  4) 남은 단백질 → 어육류군으로 충당
       저지방:중지방 = (감량 7:3 / 증량 5:5)
       n_meat = ceil(remaining_P / 8)
  5) 남은 탄수 → 곡류군 = round(remaining_C / 23)
  6) 남은 지방 → 지방군 = round(remaining_F / 5)
  7) 총 kcal 오차 ±5% 이내가 될 때까지 곡류군↔지방군 미세조정
  8) 끼니별 분배: 곡류군은 훈련일 전후 끼니에 가중, 어육류군은 균등
```

### 7.5 끼니 템플릿 (생성 규칙 — 레시피가 아니라 슬롯)

```
[한식 기본 슬롯]  밥(곡류 n) + 국/찌개(채소 1, 저염) + 단백질 주찬(어육류 n) + 나물·김치(채소 2)
[아침 간편]       계란 2–3개 + 통곡물빵 or 오트밀(곡류 n) + 우유/요거트 + 과일
[외식 대응]       백반정식 / 생선구이 / 수육(비계 제거) / 샤브샤브 / 닭한마리
[회식 대응]       고기 = 어육류 고지방 교환으로 치환, 밥·면 생략, 술 1잔 = 곡류 1교환으로 차감
[편의점 대응]     닭가슴살·삶은계란·그릭요거트·우유·바나나·샐러드 조합표
[홈트/자취]       밀프렙: 밥 소분 냉동, 닭/돼지 앞다리 대량 조리
```

**금지 규칙(엔진):** 특정 브랜드 제품 추천 금지, 보충제 강제 금지(선택 항목으로만), 특정 식품 "절대 금지" 표현 금지 — 교환 단위로 치환 가능함을 항상 제시.

### 7.6 한식 특유의 경고

```
나트륨: 한국인 평균 섭취는 WHO 권고(나트륨 2,000mg = 소금 5g)의 1.5–1.8배 수준이다.
        국·찌개·김치가 주 공급원.
   → 국물은 건더기 위주, 찌개는 주 3회 이하, 라면 국물 금지 배너
   → 감량기 마지막 주에 나트륨 급변은 체중 2kg 수준의 수분 변동을 만든다 (측정 혼란 경고)

음주:  1잔(소주 50mL) ≈ 70 kcal, 단백질 합성 억제 + 다음날 훈련 수행 저하
   → 주간 허용량을 곡류군 교환으로 차감해 명시적으로 '비용'을 보여준다
```

### 7.7 리피드 / 다이어트 브레이크

| 강도 | 리피드 | 다이어트 브레이크 |
|---|---|---|
| 하 | 불필요 (주말 자연 변동 허용) | 불필요 |
| 중 | 주 1회, 탄수 +1.5 g/kg BW, 지방 고정 → 당일만 유지칼로리 | 10–12주마다 1주 유지 |
| 상 | 주 1–2회 (훈련 고강도일에 배치) | **6–8주마다 1–2주 유지 칼로리** |

근거: Byrne 등(2018, MATADOR)이 간헐적 에너지 제한(2주 감량 / 2주 유지 반복)이 연속 제한보다 대사적응을 줄이고 지방감량 효율이 나았다고 보고 `[B]`. 다만 총 기간이 길어지므로, 엔진은 **상 강도에서만 필수**로 넣고 중은 선택, 하는 미적용.

---

## 8. 주간 재조정 규칙

### 8.1 신호 처리 (노이즈 제거가 전부다)

```
입력: 일일 체중(가능하면 매일 아침 공복·배뇨후), 주 1회 이상 InBody(선택), 섭취 기록

평활: EWMA(α=0.25)  또는  주간 이동평균(최소 4회 측정)
      W_smooth(t) = α·W(t) + (1−α)·W_smooth(t−1)

관측 속도: rate_obs = (W_smooth(주n) − W_smooth(주n−1))     [kg/week]
           rate_obs_pct = rate_obs / weight × 100

적응형 TDEE (2주 이상 데이터 확보 후, 가장 중요한 교정):
   ΔE = rate_obs × ENERGY_DENSITY_MIXED     // 감량기 7,000 / 증량기 6,000 kcal/kg [C]
   TDEE_est = mean_intake_kcal − ΔE
   TDEE ← 0.6 × TDEE_est + 0.4 × TDEE_prev    // 급변 방지 스무딩
```

### 8.2 조정 결정 테이블

`dev = (rate_obs − rate_target) / |rate_target|`

| 상황 | 조건 | 조치 | 쿨다운 |
|---|---|---|---|
| **정상** | `|dev| ≤ 0.25` | 변경 없음 | — |
| **느림(감량)** | `dev > +0.25` (덜 빠짐) | 2주 연속 시에만 조정: `Δkcal = −(rate_target − rate_obs) × 7700/7`, **최대 −250 kcal 또는 현재 섭취의 −10%** 중 작은 쪽. 칼로리 대신 **NEAT(+1,500보) 또는 유산소 +30분/주**를 1순위로 제안 | 2주 |
| **빠름(감량)** | `dev < −0.25` (너무 빠짐) | 즉시 조정: `Δkcal = +...`, 최대 +250 kcal. 근손실 위험 배너 | 1주 |
| **정체(≥3주)** | `|rate_obs| < 0.1%BW` 3주 연속 | ① 섭취 기록 정확도 점검(과소보고가 원인 1순위) → ② 1주 유지칼로리 다이어트 브레이크 → ③ 그 후에도 정체면 TDEE 재추정 후 −150 kcal | 3주 |
| **근육 손실 의심** | `ΔSMM ≤ −0.5kg` (2회 연속 측정) **또는** 주요 종목 수행 2주 연속 −5% | 적자 −30% 축소, 단백질 +0.2 g/kg FFM, 유산소 −25%, 강도 한 단계 강등 제안 | 즉시 |
| **증량 지방 과다** | 증량 중 `ΔBFM/ΔW > 0.6` (2회 측정) | 잉여 −100 kcal, 유산소 +60분/주 | 2주 |
| **주말 반등** | 주중 감소 / 주말 반등 패턴 3주 연속 | 칼로리 조정 금지. **주말 기록 습관 개입**(행동 문제이지 칼로리 문제가 아님) | — |

### 8.3 조정 상한 (폭주 방지)

```
한 번에 변경 ≤ min(250 kcal, 0.10 × current_intake)
4주 누적 변경 ≤ 0.20 × 초기 섭취
섭취는 언제나 KCAL_FLOOR(§9) 이상
연속 3회 하향 조정 후에도 정체 → 칼로리 하향 중단, 유지기 강제 진입 (배너 고지)
```

### 8.4 측정 왜곡 자동 감지 (조정 보류 조건)

다음 중 하나라도 해당하면 **그 주의 데이터로는 칼로리를 조정하지 않는다:**
- 여성 사용자 + 월경 주기 관련 수분 변동 구간 (사용자 선택 입력 시)
- 직전 3일 내 고탄수/고나트륨 이벤트(회식·여행) 기록
- 측정 횟수 < 4회/주
- InBody 측정 조건 불일치(식후/운동직후/다른 기기)
- 훈련 프로그램 변경 후 첫 2주 (글리코겐 리로딩)

---

## 9. 안전장치 (Safety Rails)

### 9.1 칼로리 바닥

```
KCAL_FLOOR = max( 1.10 × BMR,  SEX_FLOOR[sex] )
   SEX_FLOOR = { M: 1,500,  F: 1,200 }     [kcal/day]

target_kcal < KCAL_FLOOR 이면:
   1) 적자를 줄여 KCAL_FLOOR에 맞춘다 (감량 속도 자동 하향)
   2) 그래도 목표 속도가 안 나오면 → §4.5 '비현실적' 경로로
   3) 절대 KCAL_FLOOR 미만 계획을 출력하지 않는다
```

### 9.2 경고 / 거부 트리거

| 코드 | 조건 | 수준 | 동작 |
|---|---|---|---|
| `S-01` | BMI < 18.5 (현재 또는 목표) | 거부 | 계획 생성 중단, 전문가 상담 안내 |
| `S-02` | 목표 PBF < 남 8% / 여 15% | 거부 | 계획 생성 중단 |
| `S-03` | 요구 감량 속도 > 1.5 %BW/주 | 거부 | 최대 1.0%로 재계산 제안 |
| `S-04` | `target_kcal < KCAL_FLOOR` | 자동보정 | 바닥값으로 상향 + 고지 |
| `S-05` | 18세 미만 / 65세 초과 | 경고+강등 | 성장기·노년기 배너, 하 강도 고정, 단백질 하한 상향(노년 1.2→2.0 g/kg BW) |
| `S-06` | 임신·수유 | 거부 | 감량 계획 생성 불가 |
| `S-07` | 당뇨·신장질환·심혈관질환·갑상선·섭식장애 이력 체크 | 거부 또는 잠금 | 의료진 승인 전까지 계획 잠금 |
| `S-08` | VFL ≥ 15 또는 BMI ≥ 30 | 경고 | 건강검진 권고 배너, 유산소 우선 |
| `S-09` | 섭식장애 스크리닝(SCOFF 2점 이상) | 거부 | 칼로리·체중 숫자 숨김 모드 전환 + 상담 안내 |
| `S-10` | 8주 이상 연속 '상' 강도 | 강제 | 다이어트 브레이크 2주 강제 삽입 |
| `S-11` | 4주간 체중 −5% 초과 | 경고 | 강도 자동 강등 + 근손실 경고 |
| `S-12` | 단백질 > 3.2 g/kg FFM 요청 | 자동보정 | 상한으로 클램프 |

### 9.3 면책 고지 문구 (한국어, 최종본)

**앱 최초 실행 시 모달 `M-00` — 동의 체크 필수:**

> **⚠️ 반드시 읽어주세요**
>
> Mybody가 제공하는 운동·식단 계획은 **일반적인 건강 정보이며 의학적 진단·치료·처방이 아닙니다.**
> 이 앱은 의료기기가 아니며, 의사·영양사·전문 트레이너의 상담을 대체할 수 없습니다.
>
> - 계산된 기초대사량·소비 칼로리는 **통계적 추정치**로, 개인에 따라 20% 이상 차이날 수 있습니다.
> - InBody를 포함한 체성분 측정기의 값은 수분 상태·식사·운동에 따라 변동하며, 절대적인 값이 아닙니다.
> - 다음에 해당하시면 **반드시 의료진과 먼저 상담하세요**: 당뇨, 신장·간 질환, 심혈관 질환, 고혈압, 갑상선 질환, 섭식장애 이력, 임신·수유 중, 정기 복약 중, 최근 수술.
> - 운동 중 흉통·어지러움·심한 호흡곤란·실신이 발생하면 **즉시 중단하고 의료기관을 방문하세요.**
> - 극단적인 저칼로리 식단이나 급격한 체중 감량은 근손실, 골밀도 감소, 호르몬 이상, 담석, 심장 문제를 유발할 수 있습니다.
>
> 본 앱의 이용으로 발생한 어떠한 결과에 대해서도 제작자는 책임지지 않습니다.
>
> ☐ 위 내용을 모두 읽고 이해했습니다.  `[동의하고 시작]`

**계획 화면 하단 상시 노출 (작은 글씨):**
> 본 계획은 참고용 추정치입니다. 몸의 신호가 계획보다 우선합니다.

**'상' 강도 선택 시 모달:**
> **'상' 강도를 선택하셨습니다**
> 이 강도는 **10–12주 단기 집중용**입니다. 그 이상 지속하면 근손실, 대사 저하, 호르몬 이상, 폭식 위험이 커집니다.
> 하루 {kcal}kcal, 주 {days}회 웨이트, 주 {cardio}분 유산소를 **거의 매일 지켜야** 합니다. 한두 주 흐트러지면 '중' 강도보다 결과가 나쁩니다.
> 권장: 대부분의 경우 **'중' 강도가 총 소요 기간과 결과 모두에서 낫습니다.**
> `[그래도 상으로 진행]` `[중으로 변경]`

### 9.4 절대 하지 않는 것 (엔진 금지 목록)
- 특정 보충제·약물·다이어트 제품 추천
- "○○일 만에 −○kg" 형태의 보증성 표현
- 질병 진단·치료 효과 주장
- 사용자 체형에 대한 가치판단 언어
- 안전장치를 우회하는 "전문가 모드"

---

## 10. 전체 파이프라인 의사코드

```pseudo
function GENERATE_PLAN(inbody_raw, profile, goals, intensity_choice):

  // ─── 1. 정규화 ───────────────────────────────────────────────
  m = NORMALIZE_INBODY(inbody_raw)              // §0.1
  if (!VALIDATE(m))            return ERROR("E-INPUT-01", 재입력 필요 필드)
  m.ffm = m.ffm ?? (m.weight - m.bfm)
  m.pbf = m.pbf ?? (m.bfm / m.weight * 100)
  if (m.smm / m.ffm ∉ [0.45, 0.60]) return ERROR("E-INPUT-01")

  // ─── 2. 안전 사전검사 ────────────────────────────────────────
  safety = SAFETY_PRECHECK(m, profile)          // §9.2  S-01,02,05,06,07,09
  if (safety.level == REJECT) return SAFETY_BLOCK(safety)

  // ─── 3. 에너지 모델 ──────────────────────────────────────────
  bmr  = (valid_ffm) ? 370 + 21.6*m.ffm                       // §1.1
                     : MIFFLIN(profile.sex, m.weight, profile.height, profile.age)
  bmr  = clamp(bmr, 0.85*MIFFLIN(...), 1.25*MIFFLIN(...))
  tdee = profile.steps ? COMPONENT_TDEE(bmr, profile) : bmr * PAL[profile.activity]   // §1.5
  if (m.bmr_printed && |m.bmr_printed - bmr|/bmr > 0.10) warn("W-BMR-DIFF")

  // ─── 4. 목표 정규화 및 분류 ──────────────────────────────────
  d = { dW: goals.tW - m.weight, dSMM: goals.tSMM - m.smm, dBFM: goals.tBFM - m.bfm }
  r = d.dW - (K_SMM_TO_FFM * d.dSMM + d.dBFM)                  // §3.3
  if (|r| > max(1.5, 0.03*m.weight)):
        return NEEDS_USER_DECISION("M-CONFLICT", 재계산된_대안들)
  goal_type = CLASSIFY(d, ε)                                   // §3.2 → CUT/BULK/RECOMP/MAINTAIN

  // ─── 5. 강도 확정 (게이트 통과 후) ───────────────────────────
  level = APPLY_INTENSITY_GATES(intensity_choice, m, profile)  // §2.4, 강등 사유 기록

  // ─── 6. 속도 상한 산출 ───────────────────────────────────────
  tclass   = TRAINING_CLASS(profile.training_age)              // 초/중/고급
  ctx      = (goal_type == BULK) ? 'surplus'
           : (goal_type == RECOMP) ? 'recomp'
           : (goal_type == CUT) ? 'deficit' : 'maintain'
  muscle_rate = MUSCLE_RATE_TABLE[tclass][profile.sex] * m.weight/100/4.345
                  / K_SMM_TO_FFM
                  * CONTEXT_MULT[ctx][tclass] * AGE_FACTOR(profile.age)   // §4.1–4.2
  fat_rate    = min( INTENSITY_RATE[level].mid * m.weight,
                     (31 * m.bfm * 7) / 7700,
                     (goal_type==RECOMP ? 0.005*m.weight : ∞) )           // §4.3

  // ─── 7. 실현가능성 ──────────────────────────────────────────
  D_fat    = (d.dBFM < 0) ? |d.dBFM| / fat_rate    : 0
  D_muscle = (d.dSMM > 0) ? d.dSMM   / muscle_rate : 0
  D_req    = (goal_type==CUT)  ? D_fat
           : (goal_type==BULK) ? D_muscle
           : max(D_fat, D_muscle)
  T        = goals.deadline_weeks ?? D_req
  verdict  = D_req <= T        ? FEASIBLE
           : D_req <= 1.5*T    ? CHALLENGING
           :                     UNREALISTIC                              // §4.5
  if (verdict == UNREALISTIC):
        alternatives = [ EXTEND(D_req), SHRINK_GOAL(T, fat_rate, muscle_rate),
                         PHASE_SPLIT(d, T, tclass) ]
        // 계속 진행하되, 화면 상단에 🔴 + 대안 카드 노출

  // ─── 8. 칼로리 & 매크로 ─────────────────────────────────────
  Δ = ENERGY_DELTA(goal_type, level, tdee, m.bfm)              // §5.1 STEP1 + §2.5 캡
  kcal = tdee + Δ
  if (kcal < KCAL_FLOOR(bmr, sex)):                            // §9.1
        kcal = KCAL_FLOOR; Δ = kcal - tdee
        fat_rate = |Δ| * 7 / 7700                              // 속도 재산출
        recompute D_fat, verdict
        warn("S-04")
  macros = SPLIT_MACROS(kcal, m, level, goal_type)             // §5.1 STEP2–6
  if (macros.needs_relaxation) { level = DOWNGRADE(level); goto 8 }        // 최대 2회

  // ─── 9. 운동 프로그램 ───────────────────────────────────────
  days   = TRAINING_DAYS[level][goal_type]
  split  = SPLIT_BY_DAYS(days)                                 // §6.1
  volume = VOLUME_LANDMARKS(level) * DEFICIT_ADJUST(Δ, tdee)   // §6.2
  bias   = SEGMENTAL_BIAS(m.seg_lean, m.seg_fat)               // §6.5
  program = BUILD_PROGRAM(split, volume, bias, profile.equipment, tclass)  // §6.3–6.6
  program.progression = DOUBLE_PROGRESSION_RULES(level, goal_type)         // §6.4
  program.cardio      = CARDIO_PRESCRIPTION(level, goal_type, m.vfl)

  // ─── 10. 식단 ───────────────────────────────────────────────
  meals   = MEAL_COUNT(level, goal_type)
  per_meal= DISTRIBUTE(macros, meals, program.schedule)        // §7.2
  exch    = ALLOCATE_EXCHANGES(macros)                         // §7.4
  diet    = BUILD_KOREAN_TEMPLATES(exch, per_meal, profile.dietary_flags) // §7.5
  diet.refeed = REFEED_RULES(level, D_req)                     // §7.7
  diet.warnings = [SODIUM_WARNING, ALCOHOL_COST]               // §7.6

  // ─── 11. 추적 계획 ──────────────────────────────────────────
  tracking = {
     weigh_in: "매일 아침 공복·배뇨 후, 최소 주 4회",
     inbody:   (level=='상' ? "2주마다" : "4주마다"),
     smoothing: EWMA(0.25),
     review_rules: WEEKLY_ADJUSTMENT_TABLE                     // §8.2
  }

  // ─── 12. 출력 ───────────────────────────────────────────────
  return {
     meta:      { engine_version, generated_at, constants_hash },
     energy:    { bmr, bmr_method, tdee, tdee_method, confidence: "±15%" },
     goal:      { type: goal_type, deltas: d, residual: r, adjusted: bool },
     intensity: { requested: intensity_choice, applied: level, downgrade_reasons: [] },
     feasibility:{ verdict, D_req, T, muscle_rate, fat_rate, alternatives },
     nutrition: { kcal, macros, exchanges: exch, meals: diet, cycling },
     training:  { split, days, program, volume_summary, cardio, deload_week },
     tracking,
     projection: WEEKLY_PROJECTION(d, fat_rate, muscle_rate, D_req),  // 그래프용 주차별 예측
     warnings:  [...safety.warnings, ...engine_warnings],
     disclaimer: DISCLAIMER_KO
  }
```

---

## 11. 상수 테이블 (`ENGINE_CONSTANTS` — 단일 진실 공급원)

```js
const ENGINE_CONSTANTS = {
  version: "0.1.0",

  noise:      { W: 1.0, SMM: 0.5, BFM: 1.0 },             // kg, §0.2
  k_smm_ffm:  1.75,                                        // §0.3  ← 최우선 튜닝 대상
  energy_density: { fat: 7700, lean: 1800, synth: 2200, mixed_cut: 7000, mixed_bulk: 6000 },

  bmr: { katch: [370, 21.6], cunningham: [500, 22],
         mifflin_m: [10, 6.25, -5, 5], mifflin_f: [10, 6.25, -5, -161] },
  pal: { sedentary: 1.20, light: 1.375, moderate: 1.55, high: 1.725, athlete: 1.90 },
  neat_per_1000steps_per_kg: 0.45,
  tef_ratio: 0.10,
  adaptation_per_week: 0.0025, adaptation_max: 0.10,

  fat_mobilization: { design_cap: 31, hard_ceiling: 69 },   // kcal/kg FM/day, §2.5

  cut: {
    하: { rate_pct:[0.25,0.40], rate_mid:0.33, deficit_pct:[0.10,0.15], deficit_mid:0.125,
          protein_ffm:1.8, fat_pct:0.30, days:3, session_min:[40,50], cardio_min:[60,90],
          deload_weeks:9,  max_duration:null },
    중: { rate_pct:[0.50,0.75], rate_mid:0.60, deficit_pct:[0.18,0.22], deficit_mid:0.20,
          protein_ffm:2.2, fat_pct:0.25, days:4, session_min:[55,70], cardio_min:[120,150],
          deload_weeks:6,  max_duration:20 },
    상: { rate_pct:[0.75,1.00], rate_mid:0.90, deficit_pct:[0.25,0.30], deficit_mid:0.275,
          protein_ffm:2.6, fat_pct:0.22, days:5, session_min:[70,90], cardio_min:[180,300],
          deload_weeks:4,  max_duration:12 }
  },
  bulk: {
    하: { rate_pct:[0.10,0.20], surplus_pct:0.065, protein_ffm:2.0, fat_pct:0.28, days:3, cardio_min:90 },
    중: { rate_pct:[0.20,0.35], surplus_pct:0.125, protein_ffm:2.2, fat_pct:0.25, days:4, cardio_min:105 },
    상: { rate_pct:[0.35,0.50], surplus_pct:0.175, protein_ffm:2.2, fat_pct:0.22, days:5, cardio_min:75 }
  },

  muscle_rate_pct_bw_per_month: {          // §4.1 (LBM 기준, SMM 변환 전)
    beginner:     { M:[1.00,1.50], F:[0.50,0.75] },
    intermediate: { M:[0.50,1.00], F:[0.25,0.50] },
    advanced:     { M:[0.25,0.50], F:[0.125,0.25] },
    elite:        { M:[0.10,0.25], F:[0.05,0.125] }
  },
  age_factor: [[40,1.0],[50,0.80],[200,0.65]],
  context_mult: {
    surplus:  { beginner:1.00, intermediate:1.00, advanced:1.00 },
    maintain: { beginner:0.50, intermediate:0.50, advanced:0.50 },
    recomp:   { beginner:0.70, intermediate:0.35, advanced:0.15 },
    deficit:  { beginner:0.30, intermediate:0.05, advanced:0.00 }
  },
  recomp_fat_rate_cap_pct: 0.5,

  macro: { protein_min_bw:1.6, protein_max_ffm:3.2, protein_max_kcal_pct:0.40,
           fat_min_g_per_kg:0.5, fat_min_kcal_pct:0.15,
           carb_min_g_per_kg:{ low_days:1.5, high_days:2.0 },
           fiber_per_1000kcal:14, water_ml_per_kg:35 },

  volume: { /* §6.2 표 */ }, split_by_days: { /* §6.1 */ },
  asymmetry: { minor:5, major:10 }, uli_threshold:15,

  exchange: { grain:[100,23,2,0], meat_low:[50,0,8,2], meat_mid:[75,0,8,5], meat_high:[100,0,8,8],
              veg:[20,3,2,0], fat:[45,0,0,5], milk:[125,10,6,7], milk_low:[80,10,6,2], fruit:[50,12,0,0] },
  daily_fixed_exchanges: { veg:7, fruit:{cut:1,maintain:2,bulk:2}, milk:1 },

  adjust: { deadband:0.25, max_step_kcal:250, max_step_pct:0.10,
            cooldown_slow:2, cooldown_fast:1, plateau_weeks:3, cumulative_cap_pct:0.20 },

  safety: { kcal_floor_mult:1.10, kcal_floor_abs:{M:1500,F:1200},
            essential_fat:{M:5,F:12}, practical_fat_floor:{M:8,F:15},
            bmi_floor:18.5, max_weekly_pct:1.5, vfl_warn:10, vfl_alarm:15 },

  feasibility: { challenging_mult:1.5 }
};
```

---

## 12. 엔진 I/O 계약 & 프로토타입 연결

### 12.1 순수 함수 시그니처 (프로토타입 `engine.js`)

```js
normalizeInbody(raw)                  → Measurement | InputError
computeEnergy(m, profile)             → { bmr, bmrMethod, tdee, tdeeMethod, confidence }
classifyGoal(m, goals)                → { type, deltas, residual, conflict? }
checkFeasibility(m, profile, goal, level) → { verdict, D_req, rates, alternatives[] }
buildNutrition(m, profile, energy, goal, level) → Nutrition
buildTraining(m, profile, goal, level) → Training
generatePlan(raw, profile, goals, level) → Plan     // 위 전부를 오케스트레이션
reviewWeek(plan, log)                 → { action, deltaKcal, reason, code }
```
모두 **부작용 없음**. 저장은 UI 레이어(`localStorage`)가 담당.

### 12.2 검증 단계에서 오너가 보게 될 것 (UI 고유번호 부착 대상 후보)

엔진 출력 중 **번호를 붙여 피드백받아야 할 블록** — UI 담당이 아래 키에 배지를 달면 된다.

| 엔진 출력 키 | 화면 블록(예시 ID) | 오너가 판단할 것 |
|---|---|---|
| `energy.bmr / tdee` | `C-01` 에너지 카드 | 숫자가 자기 체감과 맞는가 |
| `goal.type` + `goal.residual` | `C-02` 목표 요약 / `M-01` 모순 팝업 | 분류가 납득되는가 |
| `feasibility.verdict` | `C-03` 실현가능성 배지 / `M-02` 비현실 경고 팝업 | 문구 톤이 과한가/약한가 |
| `feasibility.alternatives` | `C-04` 대안 3카드 | 대안이 실제로 매력적인가 |
| `nutrition.kcal/macros` | `C-05` 매크로 카드 | |
| `nutrition.exchanges` | `C-06` 교환단위 카드 | 한식 단위가 이해되는가 |
| `nutrition.meals[]` | `C-07` 끼니 카드 ×N | 실제로 먹을 만한가 |
| `training.program[]` | `C-08` 주간 루틴 표 | |
| `training.segmentalBias` | `C-09` 부위 불균형 알림 | 유용한가 노이즈인가 |
| `projection[]` | `C-10` 주차별 예측 그래프 | |
| `warnings[] / disclaimer` | `C-11` 경고 스택 / `M-00` 면책 모달 | 문구 수위 |

### 12.3 워크드 예시 (프로토타입 기본 시드 데이터로 사용 권장)

**입력**: 남 35세, 175cm / 체중 82.0kg, SMM 32.0kg, BFM 20.0kg, PBF 24.4%, FFM 62.0kg / 훈련경력 18개월(중급) / 활동 light / 목표: 체지방 −8kg, 골격근 +2kg, 기간 12주 / 강도 **중**

| 단계 | 결과 |
|---|---|
| BMR (Katch-McArdle) | 370 + 21.6×62 = **1,709 kcal** |
| Mifflin 교차검증 | 1,744 kcal (차이 2%, OK) |
| TDEE (PAL 1.375) | **2,350 kcal** |
| 일관성 잔차 `r` | 목표 체중 미입력 → 파생: ΔW = 1.75×2 + (−8) = **−4.5kg** → 목표 체중 77.5kg |
| 분류 | ΔSMM +2 ≥ 0.5, ΔBFM −8 ≤ −1.0 → **RECOMP** |
| 리컴프 타당성 | 중급 + PBF 24.4%(>20%) → 부분 타당 ⚠️ |
| 근성장 속도 | 중급 0.75%BW/월 × 82 /100 /4.345 = 0.142 kg FFM/wk → 리컴프 ×0.35 = 0.0496 → **SMM 0.028 kg/주** |
| 지방감량 속도 | min(0.60%×82=0.49, 31×20×7/7700=0.56, 리컴프캡 0.41) = **0.41 kg/주** |
| 필요 기간 | D_fat = 8/0.41 = **19.5주**, D_muscle = 2/0.028 = **71주** → D_req = **71주** |
| 판정 (T=12) | 71 > 18 → 🔴 **비현실적** |
| 대안 A | 71주(약 16개월)로 연장 |
| 대안 B | 12주 목표 축소 → 체지방 **−4.9kg**, 골격근 **+0.34kg** |
| 대안 C (권장) | ①감량 16주(중, −7kg 지방, SMM 유지) → ②유지 2주 → ③린벌크 24주(+0.9kg SMM, +2kg 지방) → ④미니컷 8주 → 총 50주, 순 결과 체지방 −6.8kg / SMM +0.9kg |
| 칼로리(대안 B 진행 시) | 2,350 − 470 = **1,880 kcal** (바닥 1,880 vs floor max(1.10×1709=1,880, 1500) = 1,880 → **정확히 바닥에 접함** ⚠️ 배너 표시) |
| 매크로 | P 136g / F 52g / C 216g |
| 운동 | 4일 상하체 분할, 근육군당 12–16세트, RPE 7–8, 6주 디로드, 유산소 135분/주 |

> 이 예시가 중요한 이유: **가장 흔한 사용자 입력(−8kg 지방 +2kg 근육, 3개월)이 정직한 엔진에서는 빨간불이 뜬다.** 프로토타입 검증에서 오너가 확인해야 할 1순위는 "이 빨간불과 대안 카드가 납득되는가, 아니면 짜증나는가"다. 그 피드백에 따라 `challenging_mult`와 메시지 톤을 조정한다.

---

## 13. 알려진 한계 (Known Limitations — 의도적으로 문서에 남김)

1. **`k_SMM→FFM = 1.75`** 가 근성장 판정 전체를 좌우한다. 실제 InBody 추적 데이터로 보정 전까지 모든 근성장 기간 추정에 ±40% 불확실성이 있다.
2. **BIA의 절대 정확도**: InBody는 재현성은 좋지만 DXA 대비 체지방률에 체계적 편의가 있을 수 있다. 우리는 **절대값이 아니라 같은 기기·같은 조건의 변화량**만 신뢰한다. UI에도 "항상 같은 기기, 같은 시간대"를 강제 안내.
3. **선형 에너지 모델(7,700 kcal/kg)**은 장기에서 감량을 과대추정한다. §8의 적응형 TDEE가 이를 흡수하지만, 첫 계획의 예측 그래프는 낙관적으로 나온다 → 그래프에 신뢰구간 밴드(±20%) 표시 권장.
4. **근성장 속도표는 관찰 기반 모델**이며 RCT 근거가 약하다. 개인 반응 편차가 크다.
5. **순응도는 모델에 없다.** 엔진은 "완벽히 지켰을 때"를 계산한다. 실제 결과는 §8의 관측값이 유일한 진실이다.
6. 부위별 BIA로 "국소 지방 감소"는 계획하지 않는다 — 부위별 감량(spot reduction)은 근거가 없다.
7. 여성 사용자의 월경 주기에 따른 체중·수분 변동, 경구피임약 영향은 v0.1에서 모델링하지 않는다(측정 보류 규칙으로만 대응).