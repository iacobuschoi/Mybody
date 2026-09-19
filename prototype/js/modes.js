/* =============================================================================
 * modes.js — 몸 만들기 모드 레지스트리 + 자동 선택
 *
 * 이 파일은 tools/gen-modes.js 가 생성합니다. 손으로 고치지 마세요.
 *
 * 모드는 "이름만 다른 라벨"이 아니라 서로 다른 계획이다. 각 모드는
 * 방향(적자/잉여/유지), 공격성 a 의 허용 범위, 단백질 정책, 전략 선호,
 * 전형적 기간, 연속 지속 한계, 그리고 "이 모드가 거절하는 것"을 갖는다.
 * 상/중/하는 모드가 아니라 모드 안에서의 속도(기간) 손잡이다.
 * ========================================================================== */
(function (global) {
  'use strict';

  /* 인바디 측정 노이즈 바닥 — 이보다 작은 변화는 "변화가 있었다"고 말하지 않는다 */
  var NOISE = {
    weight: 1,
    smm: 0.6,
    bfm: 1,
    rationale: "═══ A. 입력 계약 (requiredInputs / optionalInputs / derived) ═══\n이전 레지스트리의 가장 큰 기계적 결함은 조건식이 선언되지 않은 필드(curBmi, hadPriorPeak, recentTrend, deadlineWeeks)를 읽고, 없으면 `undefined < 18.5 === false`로 조용히 통과했다는 것입니다. 안전 게이트가 필드 누락으로 약해지는 일은 없어야 합니다.\n\nrequiredInputs: curWeightKg, curSmmKg, curBfmKg, heightCm, sex('male'|'female'), age, dWeightKg, dSmmKg, dBfmKg\noptionalInputs(명시적 기본값): trainingAge(기본 'novice'), hadPriorPeak(기본 false), deadlineWeeks(기본 null), currentPhase('bulk'|'cut'|'maintain'|null, 기본 null), recentTrend({weeksSpan,gapDays,dWeightKg,dSmmKg,dBfmKg}|null, 기본 null), weeksTrainingConsistent(주 2회 이상 저항운동을 연속 수행한 주수, 기본 null)\n\n미충족 정책: required 중 하나라도 null/undefined/비유한수이면 **계획을 만들지 않고 그 필드를 요구하는 화면을 띄웁니다.** 그리고 select() 내부의 `try{...}catch(e){hit=false}`를 전부 제거합니다 — 예외가 '해당 없음'으로 삼켜지면 누락된 입력은 언제나 가드를 약화시키는 쪽으로만 작동합니다.\n\nderived (조건식은 아래 이름을 그대로 씁니다):\n  curPbfPct  = curBfmKg / curWeightKg * 100\n  curBmi     = curWeightKg / (heightCm/100)^2\n  targetBmi  = (curWeightKg + dWeightKg) / (heightCm/100)^2\n  targetPbfPct = (curBfmKg + dBfmKg) / (curWeightKg + dWeightKg) * 100\n  k (=smmToFfm) = curSmmKg / (curWeightKg − curBfmKg)     ※ engine.derive()와 동일 정의\n  dFfmKg     = dSmmKg / k                                  ※ 하드코딩 1.75 전면 폐기\n  ffmKg      = curWeightKg − curBfmKg\n  bmr        = 370 + 21.6 * ffmKg  (Katch-McArdle, 인바디 인쇄값과 일치)\n  tdee       = bmr * PAL           (PAL 기본 1.55)\n  fatCapKcal = 31 * curBfmKg       (지방 동원 상한, kcal/day)\n  taExp      = ['intermediate','advanced','elite'].includes(trainingAge)\n\n★k가 0.40~0.60 범위를 벗어나면 입력 오류로 안내합니다.\n\n═══ B. 전역 전처리 (모든 거부·규칙 평가 이전에 1회) ═══\n① recentTrend.gapDays < 28 이면 recentTrend = null. (오너 8/31→9/19의 19일 간격이 여기서 걸립니다. 이전에는 문서에만 있고 조건식에는 없었습니다.)\n② recentTrend는 '판정 가능한 마지막 두 스캔'으로 고정합니다 — 81일 같은 장기 구간 전체를 쓰지 않습니다.\n③ weeksTrainingConsistent != null && < 8 이면 ΔSMM을 판정 입력에서 **제거**합니다(0 대입이 아님). 구현: smmKnown = (weeksTrainingConsistent == null || >= 8).\n④ 파생 부호 플래그 3종을 만들고 모든 규칙은 이것만 씁니다(상호배타·전수):\n   smmUp   = smmKnown && dSmmKg >  NOISE.smm\n   smmDown = smmKnown && dSmmKg < -NOISE.smm\n   smmFlat = !smmKnown || Math.abs(dSmmKg) <= NOISE.smm\n   subNoiseAll = |dWeightKg|<NOISE.weight && |dSmmKg|<NOISE.smm && |dBfmKg|<NOISE.bfm\n⑤ 경계값 규약(레지스트리 전역): 노이즈 바닥과의 비교는 **초과/미만(strict)**이고, 정확히 바닥값이면 '변화 없음(flat)'으로 취급합니다. 체지방 증가 방향만 예외로 `>=`를 써서 보수적으로 잡습니다.\n\n═══ C. 노이즈 바닥 근거 ═══\n인바디가 실제로 '재는' 것은 임피던스에서 추정한 체수분(TBW) 하나뿐이고 나머지는 전부 산수입니다 — 오너의 결과지로 FFM = TBW/0.73, BFM = 체중 − FFM, BMR = 370 + 21.6×FFM이 전부 정확히 재현됩니다. TBW가 1L 틀리면 FFM 1.37kg, BFM 1.37kg(반대 부호), PBF 1.58%p가 틀립니다. 물 한 병 분량입니다.\n\n체중 1.0kg — 실측 재현성만 보면 0.7~0.8kg이 더 정확하지만 UI가 이미 '하루에도 ±1kg 가까이 움직입니다'라고 말하고 있어 숫자와 카피를 맞췄습니다.\n골격근량 0.6kg — 엄격 표준화 조건(Frontiers in Nutrition 2024, InBody 770)의 일간 변동이 0.1~0.7kg인데 오너는 실험실이 아니라 헬스장에서 07:36 / 08:35 / 11:09에 쟀습니다. 측정 시각이 3.5시간 벌어진 것만으로 FFM이 약 1kg 움직입니다.\n체지방량 1.0kg — BFM은 체중과 FFM에서 뺄셈으로 나오므로 두 오차를 모두 물려받습니다.\n\n★구조적 단서: ΔBFM = Δ체중 − ΔFFM 이므로 Δ근육과 Δ지방은 독립적인 두 증거가 아닙니다. 신뢰도 순서는 체중 > 체지방률 > 체지방량 > 골격근량입니다. **그래서 이번 개정에서 ΔSMM이 단독으로 모드를 뒤집는 자리를 전부 없앴습니다** — 리컴프 진입은 ΔSMM ≥ 1.5×NOISE.smm(0.9kg)을 요구하고, 커팅/단기커팅은 'ΔSMM이 노이즈 안'이라는 요구를 버리고 '제지방 환산 근육 목표 < 지방 목표의 0.5배'라는 우세 판정으로 바꿨습니다. 이전 규칙에서는 목표를 0.6kg에서 0.5kg으로 고쳐 적는 것만으로 모드가 바뀌었습니다.\n\n항등식 검사 허용오차 1.5kg의 근거: 세 입력의 오차가 독립이라고 보면 전파 오차는 √(1.0² + 1.0² + (0.6/k)²) ≈ 1.79kg(k≈0.55)입니다. 1.5는 그보다 약간 엄격한 값이고, 엔진의 1.0(너무 엄격: 정상 목표를 거부)과 구 레지스트리의 2.5(너무 관대: 물리적으로 불가능한 삼중항 통과) 사이입니다. ★engine.js classifyGoal의 `isConsistent: Math.abs(mismatchKg) <= 1.0`을 삭제하고 이 공유 함수를 호출하게 해서 항등식 검사를 앱 전체에 하나만 두어야 합니다.\n\n═══ D. 거부 처리 규약 ═══\n거부는 선택 규칙보다 **먼저 하드스톱**합니다(구현이 아니라 스펙 수준의 보장). 그리고 첫 일치에서 반환하지 않고 **일치하는 거부를 전부 수집해 배열 순서대로 함께 표시**합니다 — 배열 순서가 곧 심각도(안전 > 산술 정합성 > 일정)입니다. 이전 구현은 첫 거부만 반환해서, 목표를 고칠 때마다 새 벽이 하나씩 나타나는 경험을 만들었습니다(목표 체지방률을 올리면 그제서야 항등식 오류가 나오는 식).\n모든 거부는 fallbackModeId='maintain'을 가지며, 그 유지 계획의 기준점은 **반려된 목표가 아니라 현재 체성분(curWeightKg/curSmmKg/curBfmKg)**입니다. goal.commit()이 direction이 모순되는 modeId를 저장하는 일이 없어야 합니다.\n부호 뒤바꿈 탐지: 입력이 거부됐는데 (−dSmmKg, −dBfmKg) 또는 (dBfmKg, dSmmKg) 스왑이 모든 거부를 통과한다면 \"혹시 근육 +{|dSmm|}kg · 지방 −{|dBfm|}kg을 입력하려던 건 아닌가요?\"를 원탭 적용 버튼과 함께 띄웁니다. 인바디 결과지의 근육조절/지방조절 칸을 바꿔 읽는 것이 이 입력의 가장 흔한 실제 원인입니다.\n\n═══ E. 모드 공통 규칙 (모든 모드에 적용) ═══\n① 기간 캡은 문구가 아니라 계획 변환입니다. etaWeeks > mode.maxContinuousWeeks이면 블록으로 분할하고 블록 사이에 유지모드 2~4주를 삽입한 뒤, **그 유지 주수를 포함한 총 기간**을 '언제 도달'로 표시합니다. capWarning 문자열만 붙이고 타임라인을 바꾸지 않는 현재 동작(engine.js ~533행)은 앱의 핵심 약속을 어깁니다.\n② direction이 'mixed'여도 실현 적자가 TDEE 10%를 넘는 주가 누적 20주면 유지/회복으로 강제 전이합니다. 적자 모드의 캡은 라벨이 아니라 실행값을 따릅니다.\n③ 모드 선택 직후 실현가능성 사전 시뮬레이션을 1회 돌립니다. weeksNeeded > mode.maxContinuousWeeks이면 (i) 브레이크 포함 계획으로 재구성, (ii) 그래도 넘으면 split이 가능한 모드(fatLoss 또는 muscleGain)로 강등하고 그 사실을 화면에 씁니다. 모드를 고른 뒤 나중에 하드캡을 만나 미달 종료되는 순서는 안 됩니다.\n④ 세 속도안(상/중/하)의 예상 기간이 서로 5% 이내로 수렴하면 속도 선택 UI를 숨기고 한 안만 보여줍니다(지방동원 상한이 a를 무력화한 경우).\n⑤ 근육이 병목인 케이스에서는 상/중/하 카드에 \"이 목표는 식단 속도가 아니라 근성장 상한이 기간을 정합니다 — 상을 골라도 {n}주밖에 안 줄어듭니다\"를 표시합니다.\n\n═══ F. trainingAge 판정 기준 (레지스트리에 명문화) ═══\n이전에는 규칙 4·5·6이 전부 이 값에 의존하는데 산출 규칙이 없었고, 같은 사람(오너)이 테스트에서는 intermediate, ownerVerdict에서는 novice로 분류됐습니다.\n  주 2회 이상 저항운동 지속 개월 수 기준 — 6개월 미만 novice / 6~36개월 intermediate / 36개월 이상 advanced / 60개월 이상이면서 최근 12개월 SMM 증가가 노이즈 바닥 이하면 elite.\n  복귀자: hadPriorPeak이고 공백이 6개월을 넘었으면 **intermediate로 분류하고 머슬메모리 효과는 hadPriorPeak(×2.5)가 담당**합니다. novice 천장과 hadPriorPeak을 동시에 주면 같은 사실을 두 번 세는 겁니다.\n  ★trainingAge가 없으면 기본값 'novice'(보수적)로 박고 그 사실을 reason에 적습니다. 이전 규칙은 같은 미지값이 게이트마다 정반대로 작동했습니다 — `trainingAge !== 'novice'`는 미지를 '숙련'으로 읽어 커팅/단기커팅을 열었고, `=== 'novice' || === 'intermediate'`는 미지를 '숙련'으로 읽어 리컴프를 닫았습니다. 이번 개정은 전부 화이트리스트(taExp)로 통일했습니다.\n\n═══ G. hadPriorPeak 정의 ═══\n'과거 최고 SMM − 현재 SMM ≥ 1.0kg이고, 그 기록이 최근 60개월 이내이며, 이후 8주 이상 훈련 공백이 있었을 것'. 기본값 false(명시적 boolean). 데이터로 산출 불가면 규칙에서 빼야 합니다 — undefined가 falsy로 조용히 통과/탈락하는 상태를 남기지 않습니다.\n★엔진 쪽 요구: engine.js의 ×2.5 보너스는 감쇠도 상한도 없어서 이 불리언 하나가 계획 길이를 45주와 110주 사이에서 갈라놓습니다. SMM이 기록된 과거 최고치에 접근할수록 1.0으로 테이퍼시키고, 보너스가 그 최고치를 넘겨 밀어올리지 못하도록 상한을 걸어야 합니다.\n\n═══ H. engine.js 동기화 체크리스트 (이게 안 되면 레지스트리는 문서로만 존재합니다) ═══\n1. engine.js:152 `var NOISE = 0.3` → 레지스트리 noiseFloor {weight 1.0, smm 0.6, bfm 1.0}를 읽도록 교체. 지금은 목표 +0.4kg 근육으로도 근성장 분기가 켜집니다.\n2. classifyGoal의 5종 분류를 modeId 7종 + selectionRules로 대체.\n3. CUT_RANGE.proteinPerFFM 상한 2.8 → 3.1 (cutting·miniCut 구현 조건).\n4. MAINT_RANGE = { deficitPct: [−0.020, 0.050], proteinPerFFM: [1.6, 2.0], … } 신설 + paramsAt(a,'maintain'). ★CUT_RANGE.deficitPct 하한을 건드려 해결하면 안 됩니다 — 다른 모든 감량 a값이 재척도됩니다.\n5. engine.js:85 감량 캡의 else-branch `null` → `24`. 저속(a<0.45) 계획이 40주 무제한 적자를 도는 것을 막습니다.\n6. muscleSituation(engine.js:279)의 비단조 절벽 제거 — maintain 배율 0.50 → 0.70으로 올리거나 적자 0~15% 구간을 선형 보간. 지금은 '더 여유롭게'를 고르면 근성장이 23주 느려집니다.\n7. muscleSituation을 **캡 적용 후 실제 적자가 아니라 params.deficitPct(의도한 적자)**로 판정. 지금은 a=1.00 숙련자 커팅이 지방동원 상한에 눌린 뒤 'recomp'로 분류돼 근육이 는다고 출력됩니다.\n8. stepWeek에 제지방 손실 경로 추가(적자>20%TDEE 또는 단백질<2.0 g/kg FFM 또는 PBF 남10%/여18% 미만 → 주당 FFM −0.05~0.15%). 없으면 커팅모드의 'SMM 하락' 종료 기준은 죽은 코드입니다.\n9. LEVEL_SPEC의 durationMult를 증량 국면에 적용하지 않도록 분기(증량에서는 기간의 역함수가 존재하지 않음).\n10. 모든 SMM↔FFM 환산에서 하드코딩 1.75 제거 → cur.smmToFfm 사용(modes.js select()의 `i.ffmKg = dSmmKg * 1.75` 포함).\n11. 목표 입력 폼에 '목표 날짜(선택)'와 '직전 국면(currentPhase)' 추가. 전자가 없으면 마감 기반 단기커팅과 일정 거부가, 후자가 없으면 단기커팅의 1차 진입 경로가 도달 불가 코드입니다."
  };

  var MODES = [
    {
      id: "fatLoss",
      nameKo: "감량모드",
      aliasKo: "다이어트 / 체중감량 / 감량기",
      nameEn: "Fat-Loss Phase",
      oneLiner: "체중과 체지방을 함께 줄이는 가장 기본 모드. 근육은 '지키는 것'이 목표지 늘리는 게 목표가 아닙니다.",
      whoFor: "체지방률이 아직 높은 사람(남 18%↑ / 여 26%↑), 근육 목표 없이 일단 살을 빼야 하는 사람, 벌크업 후 체지방이 올라간 사람. 그리고 지방 목표가 리컴프 커버 범위(max(6.5kg, 체중의 8.5%))를 넘는 사람 — 방향은 리컴프여도 크기가 감량입니다.",
      notFor: "체지방률이 남 15% / 여 23% 미만인 사람 — 이 구간에서 감량모드는 절대 선택되지 않고 커팅모드로 강등됩니다(마를수록 p-ratio가 불리해지는데 감량모드가 커팅보다 공격적이라 안전 역전이 생깁니다). BMI 20 미만, 19세 미만.",
      direction: "deficit",
      aMin: 0.35, aMax: 0.9,
      strategy: "auto",
      proteinPerFfmMin: 2.2, proteinPerFfmMax: 2.8,
      typicalWeeksMin: 8, typicalWeeksMax: 20,
      maxContinuousWeeks: 20,
      trainingPolicyKo: "웨이트 주 3~5회, 근육군당 주 10~16세트를 '유지'합니다. 볼륨을 늘려서 근손실을 막는 게 아닙니다 — Roth 2023 RCT는 적자 상태에서 웨이트 볼륨이 제지방 보존에 영향을 주지 않는다고 결론냈습니다. 근육을 지키는 진짜 지렛대는 단백질과 감량 속도입니다. 유산소는 주 60~240분 범위에서 a에 따라 붙습니다.\n\n★입문자 보호 기본값: trainingAge='novice'이고 체지방률이 남 25% / 여 32% 이상이면 추천 기본 속도를 '적자 ≤ TDEE 15%를 만족하는 가장 빠른 a'(= a 0.444)로 잡고 이렇게 고지합니다 — \"지금은 적자를 TDEE 15%(약 하루 {410}kcal) 아래로 묶으면 감량 중에도 근육이 붙는 구간입니다(엔진 novice 배율 0.70 vs 0.30). 더 빠른 '상'을 고르면 그 이득을 포기하는 거고, 도착 예정일 차이는 {N}주입니다.\" 상/중/하는 그대로 선택 가능하되 거래 조건을 먼저 보여줍니다.",
      expectedKo: "주 0.41~0.83%BW 감소(엔진 CUT_RANGE 상한이 0.90%/주라 그 위는 물리적으로 안 나옵니다). 근육은 대부분 '제자리'가 성공입니다. 단, 체지방률이 높고 운동경력이 짧으면 적자 중에도 근육이 붙습니다(엔진 novice×0.30, 완만적자면 ×0.70).\n\n★기간이 maxContinuousWeeks를 넘으면 단일 막대로 그리지 않습니다. capWeeks = paramsAt(a).maxContinuousWeeks(a≥0.7 → 12 / a≥0.45 → 20 / 그 외 → 24)로 블록을 나누고 블록 사이에 유지모드 2~4주를 끼워 넣은 뒤, 그 유지 주수까지 포함한 총 기간을 '언제 도달'로 표시합니다. 예: 40주짜리 '하' 계획 → 24주 적자 + 3주 유지 + 16주 적자 = 총 43주.\n\n★지방동원 상한(31×BFM kcal/day)이 적자보다 먼저 걸리면 상/중/하가 같은 궤적으로 수렴합니다. 세 안의 예상 기간이 서로 5% 이내면 속도 선택 UI를 숨기고 한 안만 보여줍니다.",
      risksKo: "a를 0.45 위로 올리면 적자가 TDEE 15%를 넘어 엔진의 근성장 배율이 novice 0.70→0.30, intermediate 0.35→0.05로 떨어집니다. 즉 '빨리 빼기'를 선택하는 순간 근육 목표는 사실상 포기됩니다. Garthe 2011: 주 1.4% 감량군은 제지방 −0.2%, 테스토스테론 감소, SHBG 증가. 20주를 넘기면 T3/T4/렙틴 억제가 몇 달 남습니다.\n\n★안전 역전 경고: 이 모드는 커팅모드보다 a 상한이 높고(0.90 vs 0.75) 단백질 하한이 낮습니다(2.2 vs 2.4). 그래서 체지방률이 낮은 사용자가 여기로 떨어지면 더 위험한 처방을 받습니다. 선택 규칙 7(린 가드)이 남 15% / 여 23% 미만을 무조건 커팅모드로 보내는 이유가 이것입니다.",
      exitCriteriaKo: "① 목표 체지방량 도달 ② 연속 적자 20주(또는 paramsAt(a).maxContinuousWeeks) 경과 → 유지모드 2~4주 자동 삽입 후 같은 모드 재개 ③ SMM이 2회 연속 측정(간격 4주 이상)에서 노이즈 바닥을 넘어 하락 → a를 한 단계 낮추고 단백질 상한으로 ④ 체지방률이 남 18% / 여 26%에 도달 → 커팅모드로 전환 제안 ⑤ 누적 12주 이상 감량 후 종료 시 회복모드로 핸드오프.",
      evidence: "a범위: 엔진 CUT_RANGE를 역산 — a=0.35→0.413%BW/주·적자 12.9%TDEE, a=0.90→0.825%BW/주·적자 25.3%TDEE. Helms/Aragon/Fitschen 2014(JISSN 11:20)의 0.5~1.0%BW/주 권장 구간을 엔진이 표현 가능한 범위로 자른 것. 단백질 2.2~2.8 g/kg FFM: Helms·Zinn 2014(IJSNEM 24:127) 2.3~3.1의 하단(★엔진 CUT_RANGE.proteinPerFFM 상한 2.8 → 3.1 상향 필요). 20주 상한: 자연 선수 시합준비 20~30주 내분비 이상 문헌 + RP의 '컷 12주 후 유지' 실무 규칙 사이의 절충이며 내 판단. 볼륨 주장: Roth et al. 2023(Scand J Med Sci Sports).\n\n★이번 수정 사유: (i) 하드캡 20주가 세 속도 모두에서 위반되던 문제 → 캡을 '계획 변환(블록 분할 + 유지 삽입)'으로 정의하고 엔진 paramsAt의 캡을 단일 진실원으로 삼음. engine.js:85의 else-branch를 null → 24로 바꿔야 저속 계획이 무제한 적자를 돌지 않습니다. (ii) 린 사용자가 이 모드로 떨어지던 안전 역전 → 린 가드 규칙 신설. (iii) 입문자 보호 기본값 신설 — 레지스트리가 오너에게만 적용하던 '하루 100kcal 더' 논리를 같은 조건의 모든 사용자에게 적용."
    },
    {
      id: "cutting",
      nameKo: "커팅모드",
      aliasKo: "컷팅 / 시즌 / 바디프로필 준비 / 데피니션",
      nameEn: "Physique Cut",
      oneLiner: "이미 있는 근육을 드러내는 단계. 감량과 같은 방향이지만, 근손실을 최소화하는 것을 조건으로 겁니다.",
      whoFor: "체지방률 남 18% 이하 / 여 26% 이하이면서 운동경력 6개월 이상, 지킬 근육 기반이 이미 있는 사람. 그리고 체지방률 남 15% / 여 23% 미만인 모든 감량 요청 — 훈련경력과 무관하게 여기로 옵니다. 근육 목표를 적었더라도 그 크기가 지방 목표의 절반(제지방 환산) 미만이면 여전히 커팅입니다.",
      notFor: "체지방률이 게이트 위인 사람 — 그건 커팅이 아니라 감량입니다. 19세 미만. 목표 체지방률이 남 8% / 여 15% 아래인 사람. 남 15% / 여 23% 미만에서 목표를 남 10% / 여 18% 아래로 잡은 사람 — 이건 모드가 아니라 상담이 필요한 신호입니다.",
      direction: "deficit",
      aMin: 0.4, aMax: 0.75,
      strategy: "simultaneous",
      proteinPerFfmMin: 2.4, proteinPerFfmMax: 3.1,
      typicalWeeksMin: 8, typicalWeeksMax: 20,
      maxContinuousWeeks: 12,
      trainingPolicyKo: "웨이트는 중량을 지키는 것이 최우선 — 복합운동은 1RM 80% 이상을 유지하고 세트 수만 조절합니다. '가볍게 여러 번'으로 바꾸지 않습니다. 유산소는 마지막 수단으로 점증. 촬영 전 마지막 주의 수분조절·단수·나트륨 조작은 이 앱이 계획하지 않습니다(저나트륨혈증 위험, 감독 없이 할 일 아님).",
      expectedKo: "주 0.45~0.71%BW 감소. 근육은 유지가 정답이고, 숙련자일수록 '유지'조차 성공입니다. **커팅 중 근육 증가는 약속하지 않습니다.**\n\n★구조 변경: 연속 12주가 하드캡이고, 12주에 닿으면 유지모드 2주(다이어트 브레이크)를 자동 삽입한 뒤 재개합니다. 총 허용 20주 = 커팅 12 + 유지 2 + 커팅 6. 이전 버전은 '16주 하드캡' 하나뿐이라 16주 안에 못 끝나는 목표가 전부 미달 종료됐고, 역설적으로 덜 적합한 감량모드(20주 허용)만 완주하는 역전이 있었습니다.\n\n★체지방량이 적으면 지방동원 상한(31×BFM kcal/day)이 a보다 먼저 걸립니다. aEffMax = min(aMax, ((31×curBfmKg)/TDEE − 0.050)/0.225)로 런타임 클램프하고, 세 속도안의 기간이 5% 이내로 붙으면 \"체지방량이 {BFM}kg이라 하루 {31×BFM}kcal 이상의 적자는 지방에서 나오지 않습니다. 상/중/하가 같은 계획이 되므로 하나만 보여드립니다\"라고 말한 뒤 한 안만 표시합니다. 그리고 적자가 캡에 눌리면 처방 섭취량이 컷 내내 '올라갑니다' — 고장이 아니라는 설명을 함께 띄워야 합니다.",
      risksKo: "감량모드보다 a 상한을 낮게 잡은 이유는 마를수록 p-ratio가 불리해지기 때문입니다(ISSN position stand: 체지방 기저치가 높을수록 적자를 공격적으로 부과 가능, 마른 대상은 반대). 16~20주를 넘기면 테스토스테론·수면·기분 저하가 문서화된 구간입니다. 커팅 종료 직후 4~6주는 체지방이 우선적으로 재축적되는 구간입니다 — 계획 없이 끝내면 요요는 사고가 아니라 예정된 결과입니다.\n\n★모델 한계 고지: 현재 engine.js stepWeek에는 제지방 손실 경로가 아예 없습니다(smmDelta ≥ 0). 그래서 '근육이 유지된다'는 출력은 예측이 아니라 모델의 산물이고, 이 모드의 'SMM 하락 감지' 종료 기준은 시뮬레이션상 절대 발동하지 않는 죽은 코드입니다. 적자>20%TDEE 또는 단백질<2.0 g/kg FFM 또는 PBF 남10%/여18% 미만에서 주당 FFM −0.05~0.15% 손실 경로를 넣어야 이 문구가 정직해집니다.",
      exitCriteriaKo: "① 목표 체지방률 도달 ② 연속 12주 → 유지 2주 강제 삽입 후 재개 ③ 총 20주 경과 → 무조건 종료하고 회복모드로 강제 전이 ④ SMM이 2회 연속 측정에서 노이즈 바닥을 넘어 하락 → 즉시 a 하향. 커팅은 끝이 아니라 반환점입니다.",
      evidence: "a범위: 엔진 CUT_RANGE 역산 — a=0.40→0.450%BW/주·적자 14.0%, a=0.75→0.712%BW/주·적자 21.9%. Garthe et al. 2011(IJSNEM 21:97)이 검증한 0.7%BW/주가 a=0.733으로 범위 안에 들어옵니다. 단백질 2.4~3.1: Helms·Zinn 2014 상단(※엔진 CUT_RANGE 상한 2.8을 3.1로 올려야 구현 가능). 진입 체지방률 남 18/여 26: 한국 린매스업·커팅 실사용 밴드 채택, Helms/3DMJ의 남 10~15%보다 관대한 쪽을 고른 것은 오너가 한국 사용자이기 때문이며 내 선택임을 밝힙니다. 12+2+6 구조: 엔진 split 전략이 이미 '유지 2주'를 내부에서 쓰고 있어 재사용 가능.\n\n★이번 수정 사유: (i) 진입 조건에서 'ΔSMM이 노이즈 안'이라는 요구를 제거했습니다. 실사용자는 거의 전부 '지방 빼고 근육 조금'을 입력하는데, 그 한 줄 때문에 커팅모드가 거의 열리지 않았고 감량/커팅을 나눈 설계 가치가 통째로 사라졌습니다. 대신 '제지방 환산 근육 목표 < 지방 목표의 0.5배'라는 우세 판정으로 바꿨습니다. (ii) 린 가드(남 15%/여 23% 미만) 신설 — 마른 사람이 더 공격적인 감량모드로 떨어지던 안전 역전을 차단. (iii) 16주 → 12주 연속 + 브레이크 + 총 20주로 재구조화."
    },
    {
      id: "recomp",
      nameKo: "리컴프 (상승다이어트)",
      aliasKo: "동시개선 / 바디 리컴포지션 / 상승 다이어트",
      nameEn: "Body Recomposition",
      oneLiner: "체중을 크게 흔들지 않으면서 근육은 올리고 지방은 내리는 모드. 느리지만, 조건이 맞는 사람에게는 분할보다 빠릅니다.",
      whoFor: "Barakat 2020이 지목한 세 집단 — ① 운동 입문자 ② 쉬었다 복귀한 사람(머슬메모리) ③ 체지방이 있는데 웨이트를 안 해본 사람. 마른비만도 여기입니다. 중급자는 체지방 여유가 뚜렷할 때만(남 22%↑ / 여 30%↑) 열립니다.",
      notFor: "★빼야 할 지방이 max(6.5kg, 체중의 8.5%)를 넘는 사람 — 방향이 맞아도 크기가 안 맞습니다. 리컴프의 적자 상한(TDEE 15%)으로 그만큼을 빼면 중단 없는 적자가 6개월을 넘어가고, 그건 이 모드의 보호 논리 자체를 배신합니다. 마감이 16주 미만인 사람(이 모드의 최소 판정 기간이 16주입니다). 증량 중인 사람(currentPhase='bulk'). 숙련자(3년+)이면서 이미 마른 사람 — 예상 월간 SMM 변화가 인바디 측정 오차보다 작아서 '틀린 게 아니라 측정이 안 됩니다'. 그리고 급한 사람.",
      direction: "mixed",
      aMin: 0.05, aMax: 0.44,
      strategy: "simultaneous",
      proteinPerFfmMin: 2.4, proteinPerFfmMax: 2.8,
      typicalWeeksMin: 16, typicalWeeksMax: 36,
      maxContinuousWeeks: 24,
      trainingPolicyKo: "이 모드에서 훈련은 옵션이 아니라 전제입니다. Barakat 2020이 리컴프 성립 조건으로 꼽은 두 가지가 '진짜 점진적 과부하'와 '고단백'입니다. 근육군당 주 12~20세트, 주 4회, 매주 중량 또는 반복수가 올라가야 합니다. 유산소는 주 90~150분으로 제한 — 유산소를 늘려서 적자를 만들면 이 모드의 보호 구간이 깨집니다.\n\n★내부 튜닝(모드 스위치가 아님): 제지방 환산 근육 목표(dSmmKg / k) ÷ |지방 목표| 비율로 a 초기값을 잡습니다. 비율 ≥ 0.5 → '균형형 리컴프'(a 0.20~0.35), 비율 < 0.5 → '감량 주도 리컴프'(a 0.38~0.44). 문헌상 p-ratio를 모드 스위치로 쓸 근거가 없고 엔진에서도 근성장 상한은 훈련연령만 보므로, 크기비는 선택이 아니라 튜닝에 씁니다.",
      expectedKo: "3~6개월에 근육 +0.5~1.5kg, 지방 −3~6kg. **체중 변화 목표는 이 모드 안에서 월 0~1 %BW까지 허용됩니다 — 목표가 −4kg이어도 리컴프입니다.** 진행 차트는 '선'이 아니라 '밴드'로 봐야 합니다. 운동 시작 8주 안의 SMM 증가는 절반쯤 글리코겐·부종입니다(Damas 2016).\n\n★측정 가능성 고지(자동 삽입, 필수): 모드 확정 직후 expectedMonthlySmmKg = curWeightKg × MUSCLE_BASE[trainingAge].pct/100 × (남1.0/여0.5) × ageFactor × k × 0.70(novice) 또는 0.35(intermediate)를 계산하고, 이 값이 NOISE.smm(0.6kg)보다 작으면 반드시 붙입니다: \"근육 {X}kg 증가는 지금 속도로 월 {Y}kg이라, 인바디 오차(±0.6kg)를 넘어 눈에 보이기까지 약 {Z}개월 걸립니다. 그 전에는 체중·체지방률로만 판정합니다.\" 여성은 ×0.5 보정 때문에 이 시점이 정확히 2배 뒤이므로 여성 최소 관찰 기간은 20주로 잡습니다(남 16주).\n\n★두 다리의 기간이 다르면 단일 모드로 끝내지 않습니다. 지방 다리와 근육 다리를 따로 시뮬레이션해서 먼저 도달하는 쪽에서 다음 모드를 자동 예약합니다(예: 리컴프 0~22주 지방 목표 도달 → 근성장모드 22주~ 근육 목표). 반환값은 단일 modeId가 아니라 {primary, runnerUp, phasePlan:[{modeId, untilCondition}]}이어야 합니다.",
      risksKo: "가장 큰 위험은 '안 되는 게 아니라 안 보이는 것'입니다. 인바디 SMM의 실사용 노이즈가 ±0.6kg인데 리컴프 월간 기대치가 0.1~0.3kg입니다. 최소 16주(여 20주), 측정 간격 최소 4주가 아니면 판정 자체를 하면 안 됩니다.\n\n★a 상한 0.44는 장식이 아니라 잠금장치입니다. 그 위로 가면 적자가 15%TDEE를 넘고 엔진의 근성장 배율이 무너져 리컴프는 그냥 감량이 됩니다. 그런데 이 숫자에는 알려진 구멍이 있습니다 — a는 deficitPct와 ratePct 두 파라미터를 동시에 움직이는데, a=0.44의 ratePct(0.480 %BW/주)가 만드는 실제 적자는 사용자에 따라 16~18%TDEE가 되어 보호선을 넘습니다. **엔진 수정 전까지는 a = min(aMax, solveAForDeficitPct(0.15, tdee))로 런타임 클램프해야 합니다.** 상수 0.44를 그대로 쓰면 이 모드가 자기 존재 이유를 배신합니다.\n\n★여성: 7개월 연속 적자는 RED-S·무월경 위험 구간입니다. 생리 불순·무월경이 발생하면 즉시 유지모드로 전이하고 상담 안내를 띄웁니다.",
      exitCriteriaKo: "① 세 목표 중 먼저 도달한 목표 기준으로 남은 다리의 모드로 전이(지방 먼저 → 근성장모드, 근육 먼저 → 감량/커팅) ② 8주 연속 SMM·BFM 둘 다 노이즈 바닥 안에서 무변화 → 근성장모드 또는 감량모드로 전환 제안 ③ 체지방률이 남 13% / 여 21% 아래로 내려가거나 목표 BFM에 도달 → 근성장모드 ④ **연속 적자 24주 경과 → 유지모드 4주 강제 후 재평가** ⑤ (여성) 생리 불순·무월경 → 즉시 유지모드 + 상담 안내.",
      evidence: "a상한 0.44: 엔진 CUT_RANGE deficitPct 역산으로 적자 15%TDEE = a 0.444이고, 엔진 MUSCLE_SITUATION이 recomp 배율(novice 0.70 / intermediate 0.35)을 주는 경계가 정확히 '적자 ≤15%'입니다. 즉 문헌이 아니라 엔진 자신의 보호 구간 경계입니다. a하한 0.05 = 적자 6.1%TDEE. ★a=0으로 못 내리는 이유: engine.js muscleSituation이 |적자|≤5%를 'maintain'으로 분류하고 그 배율이 0.50으로 recomp의 0.70보다 낮아, a=0이 a=0.05보다 근성장이 느려지는 비단조 절벽이 있습니다(오너 케이스 기준 57주 → 80주). maintain 배율을 0.70으로 올리거나 0~15% 구간을 선형 보간으로 바꾸면 aMin을 0으로 내릴 수 있습니다. 세 집단: Barakat et al. 2020(Strength Cond J 42:5). 단백질 2.4~2.8: Longland 2016(AJCN) + Barakat의 '>2.0 g/kg'.\n\n★이번 수정 사유: (i) strategy 'auto' → 'simultaneous'. 이 모드의 정체성과 a≤0.44 잠금장치의 정당화가 전부 '동시 진행 + 완만 적자' 구간에 묶여 있는데 auto는 조용히 분할(감량→유지→증량)을 내놓았습니다. 산문이 서술하지 않는 계획을 모드가 배달하면 안 됩니다. (ii) maxContinuousWeeks null → 24. 전체 모드 중 가장 오래 적자에 머무는 모드에만 상한이 없었습니다. (iii) 크기 게이트 max(6.5kg, 8.5%BW) 신설 — 오너(지방 8.0kg/86.7kg)와 복귀자(9.0kg/82kg)를 걸러내고, 여성 리컴프(6.0kg/60kg)와 스키니팻(6.0kg/68kg)은 통과시키는 경계로 보정했습니다. 근거는 '완만 적자(≈TDEE 15%)로 18~22주 안에 제거 가능한 지방량'이고, 체지방 총량이 작은 가벼운 사용자를 위해 6.5kg 하한을 둡니다. (iv) responder 절을 좁혔습니다 — 'intermediate' 단독은 리컴프 반응성의 증거가 아니라서 체지방 여유(남22%/여30%) 조건을 함께 걸었습니다. (v) 마감 16주 미만 차단, 증량 중(currentPhase='bulk') 차단, ΔSMM ≥ 1.5×NOISE(0.9kg) 요구 — 잡음 근처의 근육 목표가 모드를 뒤집지 못하게. (vi) 카피 수정: '체중은 거의 그대로'가 −4kg 목표를 입력한 사용자의 목표를 부정하던 문제."
    },
    {
      id: "muscleGain",
      nameKo: "근성장모드 (린매스업)",
      aliasKo: "린매스업 / 벌크업 / 클린벌크 / 증량기",
      nameEn: "Muscle-Gain Phase",
      oneLiner: "근육을 늘리는 단계. a를 낮추면 린매스업, 올리면 벌크업 — 이름만 다른 게 아니라 붙는 지방의 양이 다릅니다.",
      whoFor: "체지방률이 남 18% / 여 26% 이하이고 근육이 병목인 사람. BMI 20 미만이거나 하드게이너면 a를 높게(벌크업) 써도 됩니다. 지방도 빼고 근육도 늘리고 싶은데 제지방 환산 근육 목표가 지방 목표보다 큰 사람 — 엔진이 '증량 → 단기커팅' 순서와 동시 진행 중 빠른 쪽을 고릅니다.",
      notFor: "체지방률이 게이트 위인 사람 — 지금 증량하면 지방만 붙습니다(속칭 살크업). 그리고 '빨리 많이 먹으면 근육이 빨리 붙는다'고 믿는 사람 — 근성장 상한은 훈련연령이 정하고, 잉여를 키운다고 그 상한이 올라가지 않습니다.",
      direction: "surplus",
      aMin: 0.2, aMax: 0.75,
      strategy: "auto",
      proteinPerFfmMin: 1.9, proteinPerFfmMax: 2.4,
      typicalWeeksMin: 12, typicalWeeksMax: 24,
      maxContinuousWeeks: 32,
      trainingPolicyKo: "근육군당 주 12~22세트, 주 4~6회, 4~10주마다 디로드. 훈련이 계획대로 진행되지 않으면 잉여는 근섬유가 아니라 지방세포로 갑니다. 유산소는 주 75~90분 정도로 최소만 유지(간섭효과 회피 + 심폐 유지).",
      expectedKo: "주 +0.25~0.50%BW 증가가 문헌 권장치인데, 엔진의 생리적 상한(입문 1.25 / 중급 0.75 / 숙련 0.375 %BW/월 FFM)에 걸리면 실제로는 그보다 느리게 나옵니다. 한국 린매스업 콘텐츠의 '월 1kg'은 입문자 아니면 안 나오는 숫자입니다.\n\n★증량에서 상/중/하는 '기간'이 아니라 '지방' 축입니다. engine.js stepWeek의 bulk 분기에서 smmDelta는 params와 완전히 무관하고 a는 leanFraction만 건드립니다. 그래서 a를 0.20→0.75로 올려도 기간은 거의 그대로이고(예: 50주 → 48주) 최종 체지방만 +7kg 벌어집니다. LEVEL_SPEC의 durationMult(1.0/1.4/2.0)를 증량에 적용하면 안 되고(역함수가 존재하지 않음), 라벨을 이렇게 바꿔야 합니다 — 하=린매스업(a 0.20, 제지방비율 0.68) / 중=(a 0.45, 0.59) / 상=벌크업(a 0.75, 0.49), \"기간은 셋 다 약 {N}주로 같고, 붙는 지방이 +{x}kg / +{y}kg / +{z}kg 다릅니다\".\n\n★구성비 타당성(모드 선택 직후, 거부가 아니라 목표 자동 재작성): requiredLean = (dSmmKg / k) / dWeightKg. 이 값이 BULK_RANGE.leanFraction 최선값 0.75를 넘으면 목표를 2단계로 다시 씁니다 — \"근육 +{a}kg을 만들려면 가장 깨끗한 증량에서도 체중은 +{b}kg, 체지방은 +{c}kg 늘어납니다. {목표체중}kg / 체지방 {목표지방}kg을 한 번에 지나가는 경로는 없습니다. 증량으로 SMM을 먼저 만들고, 그다음 단기 감량으로 체지방을 내리는 2단계로 계획합니다.\"\n\n★etaWeeks > maxContinuousWeeks(32)면 자동 블록 분할로 렌더링합니다: 증량 32주 → 유지 4주 → 증량 잔여. 32주 캡을 가진 모드가 50주짜리 단일 막대를 그리는 일이 없어야 합니다.",
      risksKo: "a=0.20이면 늘어난 체중의 68%가 제지방, a=0.75면 49%입니다(엔진 leanFraction). 그래서 a 상한을 1.0이 아니라 0.75로 잘랐습니다 — a=1.0의 leanFraction 0.40은 더티벌크/살크업 구간입니다. 숙련·엘리트는 a≤0.45로 추가 클램프(Iraki '고급자는 더 보수적으로').\n\n★요청한 지방 증가량이 max(NOISE.bfm, (dSmmKg/k)/3)를 넘으면 그건 가장 공격적인 벌크업보다도 많은 지방입니다. 모드는 그대로 주되 \"요청하신 지방 증가량은 가장 공격적인 벌크업보다도 많습니다(살크업). 지방 목표를 {cap}kg으로 잘라 계획합니다\"를 띄우고 자동 보정합니다.",
      exitCriteriaKo: "① 목표 골격근량 도달 ② 체지방률이 남 18% / 여 26% 도달 → 단기커팅 삽입 제안. **단, trainingAge='novice'이면 단기커팅은 잠겨 있으므로 감량모드 4~6주를 대신 삽입합니다**(이전 버전은 입문자에게 진입 불가 모드를 가리켰습니다) ③ 32주 경과 → 유지모드 4주 삽입 후 재개, 또는 감량모드로 재평가 ④ 4주간 체중 +1.5% 이상인데 SMM 증가가 노이즈 바닥 이하면 '살크업' 경고를 띄우고 잉여를 하루 200kcal 낮춥니다.",
      evidence: "a범위: 엔진 BULK_RANGE 역산 — a=0.20→잉여 6.7%TDEE·leanFraction 0.68, a=0.75→잉여 14.1%·0.49. Iraki·Fitschen·Espinar·Helms 2019(Sports 7:154)의 10~20% 잉여 중 하단~중단. 한국 린매스업 관행 +200~300kcal는 TDEE 2800 기준 7~11% = a 0.22~0.52로 범위 안. 단백질 1.9~2.4 g/kg FFM: Iraki의 1.6~2.2 g/kg BW를 체지방률 20% 기준 FFM으로 환산. ★벌크업을 별도 모드로 만들지 않은 이유: 문헌상 공격적 증량이 우월하다는 근거가 사실상 없고, 엔진에서도 근성장 상한은 훈련연령만 보며, 린매스업과 벌크업의 차이가 a 하나로 완전히 표현됩니다. '별개 라벨'이지 '별개 계획'이 아닙니다.\n\n★이번 수정 사유: (i) 선택 규칙에 지방 증가 상한을 추가해 '살크업은 계획하지 않는다'는 산문을 실제 게이트로 만들었습니다. (ii) requiredLean > 0.75 구성비 불가 케이스를 별도 규칙으로 분리해 2단계 계획을 강제합니다. (iii) 입문자에게 잠긴 단기커팅을 가리키던 종료 기준을 고쳤습니다. (iv) 증량에서 상/중/하의 의미를 기간 축에서 지방 축으로 재정의."
    },
    {
      id: "maintain",
      nameKo: "유지모드",
      aliasKo: "유지어트 / 유지칼로리 / 유지기",
      nameEn: "Maintenance",
      oneLiner: "지금 몸을 지키는 계획. '아무것도 안 하는 것'이 아니라 처방된 국면입니다.",
      whoFor: "목표 변화량이 인바디 측정 오차 안쪽인 사람, 감량이나 증량을 막 끝낸 사람, 목표를 달성한 사람. 다른 모드의 블록 사이에 끼워 넣는 브레이크 구간. 그리고 지금 당장은 몸을 바꿀 때가 아닌 모든 사람.",
      notFor: "없습니다. 이 모드는 거의 모든 상태에서 안전하고, 그래서 다른 모드가 거부될 때 돌아오는 종착지입니다. 단, 거부된 목표를 향해 유지 계획을 만들지는 않습니다 — 유지의 기준점은 언제나 '현재 체성분'이지 반려된 목표값이 아닙니다.",
      direction: "maintenance",
      aMin: 0, aMax: 0.08,
      strategy: "simultaneous",
      proteinPerFfmMin: 1.6, proteinPerFfmMax: 2,
      typicalWeeksMin: 4, typicalWeeksMax: 12,
      maxContinuousWeeks: null,
      trainingPolicyKo: "기본: 웨이트 주 3회, 근육군당 주 8~12세트. 근육을 '늘리는' 볼륨이 아니라 '지키는' 최소 볼륨입니다. 유산소 주 90~120분.\n\n★리컴프 훈련 오버레이(중요): 입력 방향이 '체중 그대로 · 근육↑ · 지방↓'인데 크기만 노이즈 안쪽이면(선택 규칙 2), 칼로리는 유지로 두되 **훈련만 리컴프 강도로 올립니다 — 근육군당 주 12~20세트, 주 4회, 점진적 과부하**. 방향이 명확한 사용자에게 볼륨을 절반으로 깎아 응답하는 건 영양 판단은 맞고 훈련 판단은 정반대인 처방입니다.\n\n유지기의 목적은 훈련 수행력, 수면, 호르몬, 그리고 식사에 대한 심리적 여유를 회복하는 것입니다.",
      expectedKo: "체중은 목표 주변 ±1kg 밴드 안에서 움직입니다. 그래프는 목표선이 아니라 밴드로 그려야 합니다. 직전 국면이 감량이었다면 첫 1~2주에 글리코겐·수분으로 +0.5~1.5kg이 올라옵니다 — 지방이 아닙니다.",
      risksKo: "거의 없습니다. 유일한 위험은 오너가 '아무것도 안 하고 있다'고 느껴서 성급하게 다음 국면으로 넘어가는 것입니다. 감량 직후의 유지기는 다음 감량을 더 높은 섭취량에서 시작하게 해주는 투자입니다.\n\n★★구현 차단 사항(이 모드는 현재 엔진에서 실행 불가): engine.js CUT_RANGE.deficitPct 하한이 0.050이라 paramsAt(0,'cut')이 이미 5.0% 적자, paramsAt(0.08)이 6.8% 적자를 냅니다. TDEE 2,700 기준 하루 135~182kcal 적자 = 12주에 1.4~2.0kg 감량 — 자기가 선언한 ±1kg 밴드와 사용자 요청을 모두 위반하는 '진짜 감량'입니다. 단백질 하한 1.6도 CUT_RANGE의 2.0 아래라 장식입니다. **CUT_RANGE를 재조정하지 말고(다른 모든 감량 a값이 재척도됩니다) 별도 MAINT_RANGE = { deficitPct: [−0.020, 0.050], proteinPerFFM: [1.6, 2.0], ... }를 추가하고 paramsAt(a,'maintain')이 이걸 쓰도록 해야 합니다.** 그 전까지 유지모드 카드에 칼로리 목표를 표시하면 안 됩니다.",
      exitCriteriaKo: "직전 국면이 있으면 그 길이의 절반~동일 기간이 지난 뒤 다음 국면 선택 프롬프트, **직전 국면이 없으면 12주 후 재평가**(이전 버전은 첫 사용자에게 계산 불가능한 종료 기준만 있었습니다). 또는 사용자가 새 목표를 입력할 때 즉시 종료.",
      evidence: "a범위 0~0.08은 엔진의 한계를 드러내는 숫자입니다(위 risksKo의 ★★ 참조). 기간 4~12주 및 '직전 감량의 절반~2배' 규칙: RP Strength·3DMJ 코칭 합의 수준이고 RCT 근거는 약합니다. 단백질 1.6~2.0 g/kg FFM: Iraki 2019 증량기 권장치 유지. ★오너가 요청한 네 개에는 이 모드가 없었는데, 조사한 진지한 앱(MacroFactor·RP·Carbon·Noom) 전부가 가지고 있고, 엔진의 split 전략이 이미 '유지 2주'를 내부에서 쓰고 있습니다.\n\n★이번 수정 사유: (i) 리컴프 훈련 오버레이 신설 — 노이즈 안쪽이지만 방향이 뚜렷한 입력(선택 규칙 2)에 훈련 볼륨을 깎아 응답하던 문제. (ii) 첫 사용자용 종료 기준 추가. (iii) 거부된 목표가 아니라 현재 체성분을 기준점으로 삼는다는 규칙 명문화 — 이전에는 '지방을 늘리는 목표'를 반려한다고 말한 뒤 그 목표를 저장한 채 유지 계획을 시뮬레이션했습니다. (iv) 블록 사이 브레이크 구간으로서의 역할을 whoFor에 명시."
    },
    {
      id: "recovery",
      nameKo: "회복모드",
      aliasKo: "리버스 다이어트 / 회복식 / 다이어트 탈출",
      nameEn: "Recovery Diet",
      oneLiner: "감량을 끝내고 정상 섭취로 안전하게 돌아가는 단계. 대사를 '고치는' 게 아니라 되돌아오는 구간을 통제하는 겁니다.",
      whoFor: "커팅을 막 끝낸 사람(강제 진입), 12주 이상 감량한 사람, 바디프로필 촬영이 끝난 사람. 최근 8주 이상에 걸쳐 체중이 6% 이상 빠졌고 **이번 목표에는 추가 감량이 없는** 사람.",
      notFor: "감량을 더 해야 하는 사람 — 목표 체중이 현재보다 노이즈 바닥을 넘어 낮으면 이 모드는 절대 선택되지 않습니다(direction이 surplus인 모드를 감량 목표에 붙이는 건 그 자체로 오작동입니다). 그리고 '더 먹으면서 더 빠진다'를 기대하는 사람 — 그런 일은 일어나지 않습니다.",
      direction: "surplus",
      aMin: 0, aMax: 0.25,
      strategy: "simultaneous",
      proteinPerFfmMin: 2, proteinPerFfmMax: 2.4,
      typicalWeeksMin: 4, typicalWeeksMax: 8,
      maxContinuousWeeks: 12,
      trainingPolicyKo: "웨이트 볼륨을 점진 복구하고 유산소는 줄입니다. 감량기에 깎아둔 세트 수를 먼저 되돌리는 것이 칼로리를 올리는 것보다 우선입니다. 성공 지표를 체중으로 두지 않습니다 — 수면의 질, 폭식 충동, 훈련 수행력, (여성) 생리주기 복귀로 봅니다.",
      expectedKo: "주 +100kcal(1~4주차) → +150kcal(5주차~)로 올려 유지칼로리에 복귀. 체중은 월 0.5~1.5%BW 정도 올라올 수 있고 그중 상당량이 글리코겐·수분입니다. 기간은 clamp(max(4, 직전 감량 주수의 절반), 4, 12).",
      risksKo: "정직하게 말하면 — 이 모드의 근거는 얇습니다. '리버스 다이어트가 대사를 부스팅한다'는 주장을 지지하는 증거는 없고, 2025년 첫 RCT(JISSN 22 sup2)에서 확인된 신호는 오히려 '초반 배고픔이 더 심하다'였습니다. 이 모드가 하는 일은 대사 수리가 아니라 ① 폭식 없이 복귀 ② 지방이 우선 재축적되는 4~6주를 통제 ③ 호르몬·수면·수행력 회복, 이 셋입니다. UI에 '대사 회복' 같은 말을 쓰면 안 됩니다.",
      exitCriteriaKo: "유지칼로리 도달 또는 12주 경과 → 유지모드로 자동 전이. 폭식 삽화가 반복되면 즉시 유지모드로 넘기고 상담 안내를 띄웁니다.",
      evidence: "주 +100/+150 kcal 프로토콜: ClinicalTrials NCT03434431 프로토콜 요약(단일 출처). 기간 공식: 실무 합의를 내가 공식화한 것이며 직접 인용 아님. '대사 부스팅 근거 없음': MacroFactor 'Reverse Dieting: Hype Versus Evidence', Cleveland Clinic 2024, Trexler 2014. ★이 모드를 넣은 이유 — Carbon Diet Coach가 실제로 만든 '네 번째 모드'가 커팅이 아니라 reverse diet였습니다. 오너의 네 개짜리 안에는 '다이어트에서 빠져나오는 길'이 없고, 그게 가장 큰 구멍입니다. 이름은 '리버스 다이어트' 대신 '회복모드'를 씁니다 — 전자는 근거보다 마케팅에 가깝습니다.\n\n★이번 수정 사유: (i) 이 모드는 **도달 불가능했습니다.** 감량을 막 끝낸 사람의 전형적 입력은 '더 바꿀 게 없다'인데, 그건 노이즈 바닥 규칙(구 order 1)에 먼저 걸려 유지모드로 흡수됐습니다. 그래서 회복 규칙을 order 1로 올렸습니다. (ii) 동시에 **오발동**하고 있었습니다 — 8,125개 조합 브루트포스에서 555번 발동했는데 그 대부분이 'Δ체중 −6kg'처럼 더 빼겠다는 입력이었습니다. `dWeightKg > -NOISE.weight` 가드를 추가해 감량 목표에는 절대 붙지 않게 했습니다. (iii) recentTrend는 '판정 가능한 마지막 두 스캔'으로 고정하고 간격 28일 미만이면 무효화합니다 — 이전에는 문서에만 있던 게이트입니다."
    },
    {
      id: "miniCut",
      nameKo: "단기커팅",
      aliasKo: "미니컷 / 단기 감량 / 마감 커팅",
      nameEn: "Mini-Cut",
      oneLiner: "증량 중간에 끼워 넣는 3~5주짜리 짧고 강한 감량. 단독으로 고르는 모드가 아닙니다.",
      whoFor: "★1차 진입: **증량 중(currentPhase='bulk')인데 체지방률이 상한(남 18% / 여 26%)에 닿았고 빼야 할 지방이 체중의 4% 이내인 사람.** 마감이 없어도 열립니다 — 이게 이 모드의 원래 용도입니다. ★2차 진입: 마감(촬영·시합·행사)이 6주 안이고 빼야 할 지방이 체중의 4% 이내인 사람. 두 경로 모두 운동경력 6개월 이상, 19세 이상.",
      notFor: "증량 이력도 마감도 없이 이 모드부터 시작하려는 사람. 감량할 양이 체중의 4%를 넘는 사람(그건 감량모드입니다). 근육이 줄어드는 목표(ΔSMM < −0.6). ★단, 근성장모드가 체지방 상한에 닿아 엔진이 자동 삽입하는 경우에는 trainingAge='novice'도 허용합니다(그때 삽입할 다른 모드가 없기 때문 — 입문자는 대신 감량모드 4~6주를 씁니다).",
      direction: "deficit",
      aMin: 0.85, aMax: 1,
      strategy: "simultaneous",
      proteinPerFfmMin: 2.6, proteinPerFfmMax: 3.1,
      typicalWeeksMin: 3, typicalWeeksMax: 5,
      maxContinuousWeeks: 6,
      trainingPolicyKo: "증량기 볼륨을 그대로 끌고 가지 않습니다 — 근육군당 주 8~12세트의 유지 볼륨까지 낮추고, 중량만 지킵니다. 회복 자원이 없는 구간에서 볼륨을 유지하면 수행력이 먼저 무너집니다. 유산소는 최소.",
      expectedKo: "3~5주에 체중 −2~4%. 엔진 상한상 주 0.79~0.90%BW가 최대이고, 체지방량이 적으면 지방동원 상한(31×BFM kcal/day)이 먼저 걸려 그보다 느려집니다. 그게 맞는 동작입니다. 근육 목표가 함께 입력돼 있으면 이 모드에서 채우지 않고 **커팅 직후 재개되는 증량 구간에서 채웁니다** — 그 순서가 리컴프보다 빠릅니다(같은 목표를 약 절반 시간에).",
      risksKo: "앱 전체에서 가장 공격적인 모드입니다. 6주 하드캡을 넘기면 안 되고, 감량 주수 : 증량 주수 = 1 : 4 비율을 지켜야 합니다(4주 미니컷 뒤에는 최소 16주의 증량/유지). 종료 후 즉시 증량 재개 — 기간이 짧아서 회복모드는 불필요합니다. 마감 때문에 이 모드가 선택됐다면, 앱의 가장 중요한 역할은 '그 날짜엔 산술적으로 불가능합니다'라고 말해주는 것입니다.",
      exitCriteriaKo: "3~5주 경과(하드캡 6주) 또는 체지방률 하한(남 11% / 여 19%) 도달 → 직전 증량 모드로 자동 복귀. 마감 기반 진입이었다면 마감일 다음날부터 회복모드/유지모드가 캘린더에 이미 찍혀 있어야 합니다.",
      evidence: "a범위: 엔진 CUT_RANGE 역산 — a=0.85→0.787%BW/주·적자 24.1%, a=1.00→0.900%BW/주·적자 27.5%. 미니컷 코칭 합의치(적자 25~30%, 주 1.0~1.25%BW)와 적자는 일치하고 속도는 엔진 상한 0.90%/주에 막혀 더 보수적으로 나옵니다. 기간 3~5주·하드캡 6주, 1:4 비율: RP Strength / Legion 계열 실무 합의이며 RCT는 없습니다. 단백질 2.6~3.1: Helms·Zinn 2014 상단(★엔진 CUT_RANGE.proteinPerFFM 상한 2.8 → 3.1 필요). ★한국어 이름: '미니컷'은 한국 헬스장 용어가 아니고(검색 시 성형외과 페이지가 나옴) 실제로 쓰이는 말은 '단기 커팅'입니다.\n\n★이번 수정 사유: 이 모드는 **문서상 1차 진입 경로가 구현돼 있지 않았습니다.** whoFor가 '증량 중 체지방률이 상한에 닿은 사람'을 먼저 적어두고 근성장모드의 종료 기준도 '18% 도달 → 단기커팅 삽입'이라고 적어뒀는데, 선택 규칙은 `deadlineWeeks !== null && deadlineWeeks <= 6`만 읽었습니다. 목표 입력 폼에 마감일 칸이 없으면 단기커팅은 영구 도달 불가 코드였습니다. currentPhase 기반 진입 규칙(order 4)을 신설하고, 입력 스키마에 currentPhase를 정식 추가했습니다. 또 `dSmmKg < NOISE.smm` 요구를 제거했습니다 — 증량 중인 사람이 '근육도 더'라고 적는 건 당연하고, 그게 모드를 잠글 이유가 아닙니다."
    }
  ];

  /* 계획을 만들지 않고 막는 조건. 선택 규칙보다 먼저 평가된다. */
  var REFUSALS = [
    {
      test: function (i) {
        var dWeightKg = i.dWeightKg;
        var dSmmKg = i.dSmmKg;
        var dBfmKg = i.dBfmKg;
        var curPbfPct = i.curPbfPct;
        var curBmi = i.curBmi;
        var curSmmKg = i.curSmmKg;
        var curBfmKg = i.curBfmKg;
        var curWeightKg = i.curWeightKg;
        var heightCm = i.heightCm;
        var sex = i.sex;
        var age = i.age;
        var trainingAge = i.trainingAge;
        var hadPriorPeak = i.hadPriorPeak;
        var deadlineWeeks = i.deadlineWeeks;
        var recentTrend = i.recentTrend;
        var currentPhase = i.currentPhase;
        var tdeeKcal = i.tdeeKcal;
        var targetPbfPct = i.targetPbfPct;
        var targetBmi = i.targetBmi;
        var dFfmKg = i.dFfmKg;
        var k = i.k;
        var smmUp = i.smmUp;
        var smmDown = i.smmDown;
        var smmFlat = i.smmFlat;
        var smmKnown = i.smmKnown;
        var subNoiseAll = i.subNoiseAll;
        var taExp = i.taExp;
        var input = i.input;
        return (['curWeightKg','curSmmKg','curBfmKg','heightCm','age','dWeightKg','dSmmKg','dBfmKg'].some(function(f){ return input[f] == null || !isFinite(input[f]); }) || (sex !== 'male' && sex !== 'female'));
      },
      message: "계획을 만들기 전에 필요한 값이 빠져 있습니다: {missingFields}. 특히 키가 없으면 저체중 여부를 확인할 수 없어서 안전 검사를 건너뛰게 됩니다 — 그건 하지 않습니다. 값을 채워 주시면 바로 계산합니다."
    },
    {
      test: function (i) {
        var dWeightKg = i.dWeightKg;
        var dSmmKg = i.dSmmKg;
        var dBfmKg = i.dBfmKg;
        var curPbfPct = i.curPbfPct;
        var curBmi = i.curBmi;
        var curSmmKg = i.curSmmKg;
        var curBfmKg = i.curBfmKg;
        var curWeightKg = i.curWeightKg;
        var heightCm = i.heightCm;
        var sex = i.sex;
        var age = i.age;
        var trainingAge = i.trainingAge;
        var hadPriorPeak = i.hadPriorPeak;
        var deadlineWeeks = i.deadlineWeeks;
        var recentTrend = i.recentTrend;
        var currentPhase = i.currentPhase;
        var tdeeKcal = i.tdeeKcal;
        var targetPbfPct = i.targetPbfPct;
        var targetBmi = i.targetBmi;
        var dFfmKg = i.dFfmKg;
        var k = i.k;
        var smmUp = i.smmUp;
        var smmDown = i.smmDown;
        var smmFlat = i.smmFlat;
        var smmKnown = i.smmKnown;
        var subNoiseAll = i.subNoiseAll;
        var taExp = i.taExp;
        var input = i.input;
        return (age < 19 && (dWeightKg < -NOISE.weight || dBfmKg < -NOISE.bfm));
      },
      message: "만 19세 미만에게는 감량 계획을 만들지 않습니다. 성장기에는 체중을 줄이는 것보다 생활습관과 운동 습관을 잡는 게 우선이고, 급격한 감량은 성장 지연·빈혈·생리불순과 연결됩니다. 유지 계획과 운동 계획만 보여드립니다."
    },
    {
      test: function (i) {
        var dWeightKg = i.dWeightKg;
        var dSmmKg = i.dSmmKg;
        var dBfmKg = i.dBfmKg;
        var curPbfPct = i.curPbfPct;
        var curBmi = i.curBmi;
        var curSmmKg = i.curSmmKg;
        var curBfmKg = i.curBfmKg;
        var curWeightKg = i.curWeightKg;
        var heightCm = i.heightCm;
        var sex = i.sex;
        var age = i.age;
        var trainingAge = i.trainingAge;
        var hadPriorPeak = i.hadPriorPeak;
        var deadlineWeeks = i.deadlineWeeks;
        var recentTrend = i.recentTrend;
        var currentPhase = i.currentPhase;
        var tdeeKcal = i.tdeeKcal;
        var targetPbfPct = i.targetPbfPct;
        var targetBmi = i.targetBmi;
        var dFfmKg = i.dFfmKg;
        var k = i.k;
        var smmUp = i.smmUp;
        var smmDown = i.smmDown;
        var smmFlat = i.smmFlat;
        var smmKnown = i.smmKnown;
        var subNoiseAll = i.subNoiseAll;
        var taExp = i.taExp;
        var input = i.input;
        return ((sex === 'male' ? (curPbfPct < 15 && targetPbfPct < 10) : (curPbfPct < 23 && targetPbfPct < 18)) && dWeightKg < -0.05 * curWeightKg);
      },
      message: "지금 체지방률 {curPbfPct}%는 이미 건강 범위 안이고, 목표는 {targetPbfPct}%입니다. 이 조합에서는 목표 숫자를 조금 올려 다시 잡으시라고 안내하지 않겠습니다 — 그건 '조금 덜 극단적인 극단'을 앱이 제안하는 셈이기 때문입니다. 지금 필요한 건 더 빠른 감량 계획이 아니라, 몸에 대한 지금의 기준을 한 번 같이 살펴보는 일일 수 있습니다. 전문가(스포츠영양사 또는 의료진) 상담을 권해 드리고, 그동안은 유지 계획과 훈련 계획만 보여드립니다. 원하시면 체지방률이 아니라 수행력(3대 중량·달리기 기록) 기준 목표로 바꿔 드릴 수 있습니다."
    },
    {
      test: function (i) {
        var dWeightKg = i.dWeightKg;
        var dSmmKg = i.dSmmKg;
        var dBfmKg = i.dBfmKg;
        var curPbfPct = i.curPbfPct;
        var curBmi = i.curBmi;
        var curSmmKg = i.curSmmKg;
        var curBfmKg = i.curBfmKg;
        var curWeightKg = i.curWeightKg;
        var heightCm = i.heightCm;
        var sex = i.sex;
        var age = i.age;
        var trainingAge = i.trainingAge;
        var hadPriorPeak = i.hadPriorPeak;
        var deadlineWeeks = i.deadlineWeeks;
        var recentTrend = i.recentTrend;
        var currentPhase = i.currentPhase;
        var tdeeKcal = i.tdeeKcal;
        var targetPbfPct = i.targetPbfPct;
        var targetBmi = i.targetBmi;
        var dFfmKg = i.dFfmKg;
        var k = i.k;
        var smmUp = i.smmUp;
        var smmDown = i.smmDown;
        var smmFlat = i.smmFlat;
        var smmKnown = i.smmKnown;
        var subNoiseAll = i.subNoiseAll;
        var taExp = i.taExp;
        var input = i.input;
        return (targetPbfPct < (sex === 'male' ? 8 : 15));
      },
      message: "목표 체지방률이 {targetPbfPct}%입니다. 필수 체지방(남 2~5% / 여 10~13%)에 너무 가까워서 계획을 만들지 않습니다. 이 앱의 하한은 남성 8%, 여성 15%입니다. 참고로 남성 10% / 여성 18% 아래는 감독 없이 유지할 구간이 아니라는 점도 같이 알아두세요."
    },
    {
      test: function (i) {
        var dWeightKg = i.dWeightKg;
        var dSmmKg = i.dSmmKg;
        var dBfmKg = i.dBfmKg;
        var curPbfPct = i.curPbfPct;
        var curBmi = i.curBmi;
        var curSmmKg = i.curSmmKg;
        var curBfmKg = i.curBfmKg;
        var curWeightKg = i.curWeightKg;
        var heightCm = i.heightCm;
        var sex = i.sex;
        var age = i.age;
        var trainingAge = i.trainingAge;
        var hadPriorPeak = i.hadPriorPeak;
        var deadlineWeeks = i.deadlineWeeks;
        var recentTrend = i.recentTrend;
        var currentPhase = i.currentPhase;
        var tdeeKcal = i.tdeeKcal;
        var targetPbfPct = i.targetPbfPct;
        var targetBmi = i.targetBmi;
        var dFfmKg = i.dFfmKg;
        var k = i.k;
        var smmUp = i.smmUp;
        var smmDown = i.smmDown;
        var smmFlat = i.smmFlat;
        var smmKnown = i.smmKnown;
        var subNoiseAll = i.subNoiseAll;
        var taExp = i.taExp;
        var input = i.input;
        return (curBmi < 18.5 || targetBmi < 18.5);
      },
      message: "현재 BMI {curBmi} 또는 목표 BMI {targetBmi}가 18.5 미만(저체중)입니다. 이 앱은 저체중에서 더 빼는 계획을 만들지 않습니다. 목표를 다시 입력하시거나, 체중을 늘리는 방향으로 바꿔 주세요."
    },
    {
      test: function (i) {
        var dWeightKg = i.dWeightKg;
        var dSmmKg = i.dSmmKg;
        var dBfmKg = i.dBfmKg;
        var curPbfPct = i.curPbfPct;
        var curBmi = i.curBmi;
        var curSmmKg = i.curSmmKg;
        var curBfmKg = i.curBfmKg;
        var curWeightKg = i.curWeightKg;
        var heightCm = i.heightCm;
        var sex = i.sex;
        var age = i.age;
        var trainingAge = i.trainingAge;
        var hadPriorPeak = i.hadPriorPeak;
        var deadlineWeeks = i.deadlineWeeks;
        var recentTrend = i.recentTrend;
        var currentPhase = i.currentPhase;
        var tdeeKcal = i.tdeeKcal;
        var targetPbfPct = i.targetPbfPct;
        var targetBmi = i.targetBmi;
        var dFfmKg = i.dFfmKg;
        var k = i.k;
        var smmUp = i.smmUp;
        var smmDown = i.smmDown;
        var smmFlat = i.smmFlat;
        var smmKnown = i.smmKnown;
        var subNoiseAll = i.subNoiseAll;
        var taExp = i.taExp;
        var input = i.input;
        return (Math.abs(dWeightKg - (dBfmKg + dSmmKg / k)) > 1.5);
      },
      message: "입력하신 세 숫자가 서로 맞지 않습니다. 체중 변화 = 체지방 변화 + 제지방 변화인데, 근육 {dSmmKg}kg · 지방 {dBfmKg}kg이면 체중은 약 {impliedDWeightKg}kg 변해야 합니다(입력값 {dWeightKg}kg). 인바디 결과지의 체중조절 = 지방조절 + 근육조절도 같은 항등식입니다. 셋 중 하나를 고쳐 주세요 — 체중 쪽이 가장 믿을 만한 숫자라서, 보통은 근육이나 지방 칸이 잘못 옮겨 적힌 경우입니다."
    },
    {
      test: function (i) {
        var dWeightKg = i.dWeightKg;
        var dSmmKg = i.dSmmKg;
        var dBfmKg = i.dBfmKg;
        var curPbfPct = i.curPbfPct;
        var curBmi = i.curBmi;
        var curSmmKg = i.curSmmKg;
        var curBfmKg = i.curBfmKg;
        var curWeightKg = i.curWeightKg;
        var heightCm = i.heightCm;
        var sex = i.sex;
        var age = i.age;
        var trainingAge = i.trainingAge;
        var hadPriorPeak = i.hadPriorPeak;
        var deadlineWeeks = i.deadlineWeeks;
        var recentTrend = i.recentTrend;
        var currentPhase = i.currentPhase;
        var tdeeKcal = i.tdeeKcal;
        var targetPbfPct = i.targetPbfPct;
        var targetBmi = i.targetBmi;
        var dFfmKg = i.dFfmKg;
        var k = i.k;
        var smmUp = i.smmUp;
        var smmDown = i.smmDown;
        var smmFlat = i.smmFlat;
        var smmKnown = i.smmKnown;
        var subNoiseAll = i.subNoiseAll;
        var taExp = i.taExp;
        var input = i.input;
        return (dBfmKg >= NOISE.bfm && dSmmKg <= -NOISE.smm);
      },
      message: "체지방은 늘리고 근육은 줄이는 목표입니다. 이건 계획이 아니라 방치의 결과라서, 앱이 만들어 드릴 수 있는 게 없습니다. 혹시 근육 +{absDSmmKg}kg · 지방 −{absDBfmKg}kg을 입력하려던 건 아닌가요? (인바디 결과지의 근육조절·지방조절 칸을 바꿔 읽는 일이 가장 흔합니다.) 참고로 체중 = 체지방 + 제지방 기준으로 입력하신 두 숫자가 함의하는 체중은 {impliedWeightKg}kg입니다. 그동안은 지금 몸을 유지하는 계획을 보여드립니다."
    },
    {
      test: function (i) {
        var dWeightKg = i.dWeightKg;
        var dSmmKg = i.dSmmKg;
        var dBfmKg = i.dBfmKg;
        var curPbfPct = i.curPbfPct;
        var curBmi = i.curBmi;
        var curSmmKg = i.curSmmKg;
        var curBfmKg = i.curBfmKg;
        var curWeightKg = i.curWeightKg;
        var heightCm = i.heightCm;
        var sex = i.sex;
        var age = i.age;
        var trainingAge = i.trainingAge;
        var hadPriorPeak = i.hadPriorPeak;
        var deadlineWeeks = i.deadlineWeeks;
        var recentTrend = i.recentTrend;
        var currentPhase = i.currentPhase;
        var tdeeKcal = i.tdeeKcal;
        var targetPbfPct = i.targetPbfPct;
        var targetBmi = i.targetBmi;
        var dFfmKg = i.dFfmKg;
        var k = i.k;
        var smmUp = i.smmUp;
        var smmDown = i.smmDown;
        var smmFlat = i.smmFlat;
        var smmKnown = i.smmKnown;
        var subNoiseAll = i.subNoiseAll;
        var taExp = i.taExp;
        var input = i.input;
        return (dBfmKg >= NOISE.bfm && Math.abs(dSmmKg) <= NOISE.smm);
      },
      message: "체지방만 늘리는 목표는 이 앱이 계획하지 않습니다. 입력값이 잘못됐는지 먼저 확인해 주세요 — 부호가 반대로 들어갔을 수 있습니다. 그동안은 **지금 체성분({curWeightKg}kg / 근육 {curSmmKg}kg / 지방 {curBfmKg}kg)을 기준으로** 유지하는 계획을 보여드립니다. 입력하신 목표값으로 계획을 돌리지는 않습니다."
    },
    {
      test: function (i) {
        var dWeightKg = i.dWeightKg;
        var dSmmKg = i.dSmmKg;
        var dBfmKg = i.dBfmKg;
        var curPbfPct = i.curPbfPct;
        var curBmi = i.curBmi;
        var curSmmKg = i.curSmmKg;
        var curBfmKg = i.curBfmKg;
        var curWeightKg = i.curWeightKg;
        var heightCm = i.heightCm;
        var sex = i.sex;
        var age = i.age;
        var trainingAge = i.trainingAge;
        var hadPriorPeak = i.hadPriorPeak;
        var deadlineWeeks = i.deadlineWeeks;
        var recentTrend = i.recentTrend;
        var currentPhase = i.currentPhase;
        var tdeeKcal = i.tdeeKcal;
        var targetPbfPct = i.targetPbfPct;
        var targetBmi = i.targetBmi;
        var dFfmKg = i.dFfmKg;
        var k = i.k;
        var smmUp = i.smmUp;
        var smmDown = i.smmDown;
        var smmFlat = i.smmFlat;
        var smmKnown = i.smmKnown;
        var subNoiseAll = i.subNoiseAll;
        var taExp = i.taExp;
        var input = i.input;
        return (deadlineWeeks !== null && deadlineWeeks > 0 && (Math.abs(dWeightKg) / curWeightKg) / deadlineWeeks > 0.015);
      },
      message: "{deadlineWeeks}주 안에 체중 {dWeightKg}kg 변화는 주당 {ratePct}%입니다. 안전하게 가능한 상한(주 1.5%)을 넘습니다. 기간을 늘리거나 목표를 줄여 주세요. 지금 이 숫자는 몸이 아니라 물과 근육이 빠지는 속도입니다. (참고: 주 0.9%~1.5% 구간은 거부하지 않고, 대신 그 날짜에 실제로 도달하는 지점을 계산해서 보여드립니다.)"
    },
    {
      test: function (i) {
        var dWeightKg = i.dWeightKg;
        var dSmmKg = i.dSmmKg;
        var dBfmKg = i.dBfmKg;
        var curPbfPct = i.curPbfPct;
        var curBmi = i.curBmi;
        var curSmmKg = i.curSmmKg;
        var curBfmKg = i.curBfmKg;
        var curWeightKg = i.curWeightKg;
        var heightCm = i.heightCm;
        var sex = i.sex;
        var age = i.age;
        var trainingAge = i.trainingAge;
        var hadPriorPeak = i.hadPriorPeak;
        var deadlineWeeks = i.deadlineWeeks;
        var recentTrend = i.recentTrend;
        var currentPhase = i.currentPhase;
        var tdeeKcal = i.tdeeKcal;
        var targetPbfPct = i.targetPbfPct;
        var targetBmi = i.targetBmi;
        var dFfmKg = i.dFfmKg;
        var k = i.k;
        var smmUp = i.smmUp;
        var smmDown = i.smmDown;
        var smmFlat = i.smmFlat;
        var smmKnown = i.smmKnown;
        var subNoiseAll = i.subNoiseAll;
        var taExp = i.taExp;
        var input = i.input;
        return (deadlineWeeks !== null && deadlineWeeks < 4);
      },
      message: "목표 기간이 4주 미만입니다. 인바디로 확인 가능한 변화가 나오는 최소 단위가 4주라서, 그보다 짧은 계획은 만들어도 진행 여부를 판정할 수 없습니다."
    }
  ];

  /* 순서대로 평가해 처음 맞는 것을 쓴다. 마지막은 반드시 catch-all. */
  var RULES = [
    {
      order: 1,
      modeId: "recovery",
      reason: "최근 {weeksSpan}주 동안 체중이 {pct}% 빠졌고, 이번 목표에는 추가 감량이 없습니다. 감량을 막 끝낸 상태로 판단해 회복 계획을 먼저 제안합니다. 이 구간은 체지방이 가장 빨리 다시 붙는 4~6주입니다.",
      source: "recentTrend !== null && recentTrend.weeksSpan >= 8 && (recentTrend.dWeightKg / curWeightKg) <= -0.06 && dWeightKg > -NOISE.weight && dBfmKg > -NOISE.bfm && smmFlat",
      test: function (i) {
        var dWeightKg = i.dWeightKg;
        var dSmmKg = i.dSmmKg;
        var dBfmKg = i.dBfmKg;
        var curPbfPct = i.curPbfPct;
        var curBmi = i.curBmi;
        var curSmmKg = i.curSmmKg;
        var curBfmKg = i.curBfmKg;
        var curWeightKg = i.curWeightKg;
        var heightCm = i.heightCm;
        var sex = i.sex;
        var age = i.age;
        var trainingAge = i.trainingAge;
        var hadPriorPeak = i.hadPriorPeak;
        var deadlineWeeks = i.deadlineWeeks;
        var recentTrend = i.recentTrend;
        var currentPhase = i.currentPhase;
        var tdeeKcal = i.tdeeKcal;
        var targetPbfPct = i.targetPbfPct;
        var targetBmi = i.targetBmi;
        var dFfmKg = i.dFfmKg;
        var k = i.k;
        var smmUp = i.smmUp;
        var smmDown = i.smmDown;
        var smmFlat = i.smmFlat;
        var smmKnown = i.smmKnown;
        var subNoiseAll = i.subNoiseAll;
        var taExp = i.taExp;
        var input = i.input;
        return (recentTrend !== null && recentTrend.weeksSpan >= 8 && (recentTrend.dWeightKg / curWeightKg) <= -0.06 && dWeightKg > -NOISE.weight && dBfmKg > -NOISE.bfm && smmFlat);
      }
    },
    {
      order: 2,
      modeId: "maintain",
      reason: "입력하신 변화량은 인바디가 구분할 수 없는 크기입니다(체중 ±1kg · 근육 ±0.6kg · 지방 ±1kg). 다만 방향은 '체중 그대로, 근육↑ 지방↓' — 리컴프입니다. 칼로리는 유지로 두고 훈련만 리컴프 강도(근육군당 주 12~20세트, 점진적 과부하)로 가져갑니다. 이 방향을 진짜로 추적하시려면 최소 16주, 측정 간격 4주 이상이 필요하고, 목표를 근육 +1.0kg 이상으로 다시 잡으셔야 앱이 '진행 중'이라고 말할 수 있습니다.",
      source: "subNoiseAll && dSmmKg > 0 && dBfmKg < 0",
      test: function (i) {
        var dWeightKg = i.dWeightKg;
        var dSmmKg = i.dSmmKg;
        var dBfmKg = i.dBfmKg;
        var curPbfPct = i.curPbfPct;
        var curBmi = i.curBmi;
        var curSmmKg = i.curSmmKg;
        var curBfmKg = i.curBfmKg;
        var curWeightKg = i.curWeightKg;
        var heightCm = i.heightCm;
        var sex = i.sex;
        var age = i.age;
        var trainingAge = i.trainingAge;
        var hadPriorPeak = i.hadPriorPeak;
        var deadlineWeeks = i.deadlineWeeks;
        var recentTrend = i.recentTrend;
        var currentPhase = i.currentPhase;
        var tdeeKcal = i.tdeeKcal;
        var targetPbfPct = i.targetPbfPct;
        var targetBmi = i.targetBmi;
        var dFfmKg = i.dFfmKg;
        var k = i.k;
        var smmUp = i.smmUp;
        var smmDown = i.smmDown;
        var smmFlat = i.smmFlat;
        var smmKnown = i.smmKnown;
        var subNoiseAll = i.subNoiseAll;
        var taExp = i.taExp;
        var input = i.input;
        return (subNoiseAll && dSmmKg > 0 && dBfmKg < 0);
      }
    },
    {
      order: 3,
      modeId: "maintain",
      reason: "입력하신 변화량이 인바디 측정 오차(체중 ±1kg · 근육 ±0.6kg · 지방 ±1kg) 안쪽입니다. 기계가 구분할 수 없는 크기라서, 지금 몸을 지키는 계획을 제안합니다.",
      source: "subNoiseAll",
      test: function (i) {
        var dWeightKg = i.dWeightKg;
        var dSmmKg = i.dSmmKg;
        var dBfmKg = i.dBfmKg;
        var curPbfPct = i.curPbfPct;
        var curBmi = i.curBmi;
        var curSmmKg = i.curSmmKg;
        var curBfmKg = i.curBfmKg;
        var curWeightKg = i.curWeightKg;
        var heightCm = i.heightCm;
        var sex = i.sex;
        var age = i.age;
        var trainingAge = i.trainingAge;
        var hadPriorPeak = i.hadPriorPeak;
        var deadlineWeeks = i.deadlineWeeks;
        var recentTrend = i.recentTrend;
        var currentPhase = i.currentPhase;
        var tdeeKcal = i.tdeeKcal;
        var targetPbfPct = i.targetPbfPct;
        var targetBmi = i.targetBmi;
        var dFfmKg = i.dFfmKg;
        var k = i.k;
        var smmUp = i.smmUp;
        var smmDown = i.smmDown;
        var smmFlat = i.smmFlat;
        var smmKnown = i.smmKnown;
        var subNoiseAll = i.subNoiseAll;
        var taExp = i.taExp;
        var input = i.input;
        return (subNoiseAll);
      }
    },
    {
      order: 4,
      modeId: "miniCut",
      reason: "증량 중이신데 체지방률이 {curPbfPct}%로 증량 상한에 닿았습니다. 빼야 할 지방이 체중의 4% 이내라, 3~5주 단기커팅으로 정리하고 증량을 이어가는 쪽이 빠릅니다. 근육 목표는 커팅 다음 증량 구간에서 채웁니다 — 리컴프로 끌고 가면 같은 목표에 두 배 가까운 시간이 걸립니다.",
      source: "currentPhase === 'bulk' && dBfmKg < -NOISE.bfm && !smmDown && Math.abs(dBfmKg) <= 0.04 * curWeightKg && curPbfPct >= (sex === 'male' ? 18 : 26) && taExp && age >= 19",
      test: function (i) {
        var dWeightKg = i.dWeightKg;
        var dSmmKg = i.dSmmKg;
        var dBfmKg = i.dBfmKg;
        var curPbfPct = i.curPbfPct;
        var curBmi = i.curBmi;
        var curSmmKg = i.curSmmKg;
        var curBfmKg = i.curBfmKg;
        var curWeightKg = i.curWeightKg;
        var heightCm = i.heightCm;
        var sex = i.sex;
        var age = i.age;
        var trainingAge = i.trainingAge;
        var hadPriorPeak = i.hadPriorPeak;
        var deadlineWeeks = i.deadlineWeeks;
        var recentTrend = i.recentTrend;
        var currentPhase = i.currentPhase;
        var tdeeKcal = i.tdeeKcal;
        var targetPbfPct = i.targetPbfPct;
        var targetBmi = i.targetBmi;
        var dFfmKg = i.dFfmKg;
        var k = i.k;
        var smmUp = i.smmUp;
        var smmDown = i.smmDown;
        var smmFlat = i.smmFlat;
        var smmKnown = i.smmKnown;
        var subNoiseAll = i.subNoiseAll;
        var taExp = i.taExp;
        var input = i.input;
        return (currentPhase === 'bulk' && dBfmKg < -NOISE.bfm && !smmDown && Math.abs(dBfmKg) <= 0.04 * curWeightKg && curPbfPct >= (sex === 'male' ? 18 : 26) && taExp && age >= 19);
      }
    },
    {
      order: 5,
      modeId: "miniCut",
      reason: "마감이 {deadlineWeeks}주 남았고, 빼야 할 지방이 체중의 4% 이내입니다. 짧고 강한 단기커팅이 맞는 상황입니다. 다만 6주를 넘기지 않고, 끝난 다음 날부터 복귀 계획이 함께 잡힙니다.",
      source: "deadlineWeeks !== null && deadlineWeeks <= 6 && dBfmKg < -NOISE.bfm && !smmDown && (smmFlat || dFfmKg < 0.5 * Math.abs(dBfmKg)) && Math.abs(dBfmKg) <= 0.04 * curWeightKg && curPbfPct >= (sex === 'male' ? 13 : 21) && taExp && age >= 19",
      test: function (i) {
        var dWeightKg = i.dWeightKg;
        var dSmmKg = i.dSmmKg;
        var dBfmKg = i.dBfmKg;
        var curPbfPct = i.curPbfPct;
        var curBmi = i.curBmi;
        var curSmmKg = i.curSmmKg;
        var curBfmKg = i.curBfmKg;
        var curWeightKg = i.curWeightKg;
        var heightCm = i.heightCm;
        var sex = i.sex;
        var age = i.age;
        var trainingAge = i.trainingAge;
        var hadPriorPeak = i.hadPriorPeak;
        var deadlineWeeks = i.deadlineWeeks;
        var recentTrend = i.recentTrend;
        var currentPhase = i.currentPhase;
        var tdeeKcal = i.tdeeKcal;
        var targetPbfPct = i.targetPbfPct;
        var targetBmi = i.targetBmi;
        var dFfmKg = i.dFfmKg;
        var k = i.k;
        var smmUp = i.smmUp;
        var smmDown = i.smmDown;
        var smmFlat = i.smmFlat;
        var smmKnown = i.smmKnown;
        var subNoiseAll = i.subNoiseAll;
        var taExp = i.taExp;
        var input = i.input;
        return (deadlineWeeks !== null && deadlineWeeks <= 6 && dBfmKg < -NOISE.bfm && !smmDown && (smmFlat || dFfmKg < 0.5 * Math.abs(dBfmKg)) && Math.abs(dBfmKg) <= 0.04 * curWeightKg && curPbfPct >= (sex === 'male' ? 13 : 21) && taExp && age >= 19);
      }
    },
    {
      order: 6,
      modeId: "cutting",
      reason: "체지방률 {curPbfPct}%에 운동경력이 이미 쌓였고, 근육은 지키면서 지방만 걷어내는 목표입니다. 이게 헬스장에서 말하는 '커팅'입니다. 감량모드보다 속도 상한을 낮게 잡고 단백질을 더 올립니다. 근육 목표를 함께 적으셨다면 이 구간에서는 '유지가 성공'으로 다시 읽어주세요 — 커팅 중 근육 증가는 약속하지 않습니다.",
      source: "dBfmKg < -NOISE.bfm && !smmDown && (smmFlat || dFfmKg < 0.5 * Math.abs(dBfmKg)) && curPbfPct <= (sex === 'male' ? 18 : 26) && taExp && age >= 19",
      test: function (i) {
        var dWeightKg = i.dWeightKg;
        var dSmmKg = i.dSmmKg;
        var dBfmKg = i.dBfmKg;
        var curPbfPct = i.curPbfPct;
        var curBmi = i.curBmi;
        var curSmmKg = i.curSmmKg;
        var curBfmKg = i.curBfmKg;
        var curWeightKg = i.curWeightKg;
        var heightCm = i.heightCm;
        var sex = i.sex;
        var age = i.age;
        var trainingAge = i.trainingAge;
        var hadPriorPeak = i.hadPriorPeak;
        var deadlineWeeks = i.deadlineWeeks;
        var recentTrend = i.recentTrend;
        var currentPhase = i.currentPhase;
        var tdeeKcal = i.tdeeKcal;
        var targetPbfPct = i.targetPbfPct;
        var targetBmi = i.targetBmi;
        var dFfmKg = i.dFfmKg;
        var k = i.k;
        var smmUp = i.smmUp;
        var smmDown = i.smmDown;
        var smmFlat = i.smmFlat;
        var smmKnown = i.smmKnown;
        var subNoiseAll = i.subNoiseAll;
        var taExp = i.taExp;
        var input = i.input;
        return (dBfmKg < -NOISE.bfm && !smmDown && (smmFlat || dFfmKg < 0.5 * Math.abs(dBfmKg)) && curPbfPct <= (sex === 'male' ? 18 : 26) && taExp && age >= 19);
      }
    },
    {
      order: 7,
      modeId: "cutting",
      reason: "체지방률 {curPbfPct}%는 이미 낮습니다. 이 구간에서는 감량모드의 공격적 범위(주 0.83%BW · 적자 25%)를 열지 않습니다 — 마를수록 같은 적자에서 근육이 더 나가기 때문입니다. 속도 상한이 낮고 단백질 하한이 높은 커팅으로 잡았습니다.",
      source: "dBfmKg < -NOISE.bfm && !smmDown && curPbfPct < (sex === 'male' ? 15 : 23) && age >= 19",
      test: function (i) {
        var dWeightKg = i.dWeightKg;
        var dSmmKg = i.dSmmKg;
        var dBfmKg = i.dBfmKg;
        var curPbfPct = i.curPbfPct;
        var curBmi = i.curBmi;
        var curSmmKg = i.curSmmKg;
        var curBfmKg = i.curBfmKg;
        var curWeightKg = i.curWeightKg;
        var heightCm = i.heightCm;
        var sex = i.sex;
        var age = i.age;
        var trainingAge = i.trainingAge;
        var hadPriorPeak = i.hadPriorPeak;
        var deadlineWeeks = i.deadlineWeeks;
        var recentTrend = i.recentTrend;
        var currentPhase = i.currentPhase;
        var tdeeKcal = i.tdeeKcal;
        var targetPbfPct = i.targetPbfPct;
        var targetBmi = i.targetBmi;
        var dFfmKg = i.dFfmKg;
        var k = i.k;
        var smmUp = i.smmUp;
        var smmDown = i.smmDown;
        var smmFlat = i.smmFlat;
        var smmKnown = i.smmKnown;
        var subNoiseAll = i.subNoiseAll;
        var taExp = i.taExp;
        var input = i.input;
        return (dBfmKg < -NOISE.bfm && !smmDown && curPbfPct < (sex === 'male' ? 15 : 23) && age >= 19);
      }
    },
    {
      order: 8,
      modeId: "fatLoss",
      reason: "{deadlineWeeks}주 안에 체중 {dWeightKg}kg은 주당 {ratePct}%인데, 이 엔진이 물리적으로 낼 수 있는 최대는 주 0.90%입니다. 그래서 목표를 그대로 약속하지 않고, 가장 빠른 감량 계획(a≈0.85)과 함께 **그 날짜에 실제로 도달하는 지점**을 계산해 보여드립니다. 지방 동원 상한(31 × 현재 체지방 {curBfmKg}kg = 하루 {fatCapKcal}kcal)이 먼저 걸리기 때문에 목표 지방까지는 가지 못합니다. 목표일을 뒤로 미루시거나, 기준을 체중이 아니라 체지방률로 바꾸시는 쪽을 권합니다. 근육 목표는 이 기간 동안 '유지'로 다시 읽어주세요.",
      source: "deadlineWeeks !== null && dBfmKg < -NOISE.bfm && (Math.abs(dWeightKg) / curWeightKg) / deadlineWeeks > 0.009",
      test: function (i) {
        var dWeightKg = i.dWeightKg;
        var dSmmKg = i.dSmmKg;
        var dBfmKg = i.dBfmKg;
        var curPbfPct = i.curPbfPct;
        var curBmi = i.curBmi;
        var curSmmKg = i.curSmmKg;
        var curBfmKg = i.curBfmKg;
        var curWeightKg = i.curWeightKg;
        var heightCm = i.heightCm;
        var sex = i.sex;
        var age = i.age;
        var trainingAge = i.trainingAge;
        var hadPriorPeak = i.hadPriorPeak;
        var deadlineWeeks = i.deadlineWeeks;
        var recentTrend = i.recentTrend;
        var currentPhase = i.currentPhase;
        var tdeeKcal = i.tdeeKcal;
        var targetPbfPct = i.targetPbfPct;
        var targetBmi = i.targetBmi;
        var dFfmKg = i.dFfmKg;
        var k = i.k;
        var smmUp = i.smmUp;
        var smmDown = i.smmDown;
        var smmFlat = i.smmFlat;
        var smmKnown = i.smmKnown;
        var subNoiseAll = i.subNoiseAll;
        var taExp = i.taExp;
        var input = i.input;
        return (deadlineWeeks !== null && dBfmKg < -NOISE.bfm && (Math.abs(dWeightKg) / curWeightKg) / deadlineWeeks > 0.009);
      }
    },
    {
      order: 9,
      modeId: "recomp",
      reason: "지방은 빼고 근육은 늘리는 목표인데, {reason}이라서 동시에 진행하는 게 실제로 가능한 구간입니다. 빼야 할 지방 {fatKg}kg도 리컴프가 커버하는 범위 안입니다. 적자는 TDEE의 15% 아래로 묶습니다 — 그 선을 넘는 순간 근육 증가율이 무너지기 때문입니다. 근육 {dSmmKg}kg 증가는 지금 속도로 월 {expectedMonthlySmmKg}kg이라, 인바디 오차(±0.6kg)를 넘어 눈에 보이기까지 약 {smmVisibleMonths}개월 걸립니다. 그 전에는 체중·체지방률로만 판정합니다.",
      source: "dBfmKg < -NOISE.bfm && smmKnown && dSmmKg >= 1.5 * NOISE.smm && Math.abs(dBfmKg) <= Math.max(6.5, 0.085 * curWeightKg) && curPbfPct >= (sex === 'male' ? 14.5 : 22.5) && currentPhase !== 'bulk' && (deadlineWeeks === null || deadlineWeeks >= 16) && (trainingAge === 'novice' || hadPriorPeak === true || (trainingAge === 'intermediate' && curPbfPct >= (sex === 'male' ? 22 : 30)))",
      test: function (i) {
        var dWeightKg = i.dWeightKg;
        var dSmmKg = i.dSmmKg;
        var dBfmKg = i.dBfmKg;
        var curPbfPct = i.curPbfPct;
        var curBmi = i.curBmi;
        var curSmmKg = i.curSmmKg;
        var curBfmKg = i.curBfmKg;
        var curWeightKg = i.curWeightKg;
        var heightCm = i.heightCm;
        var sex = i.sex;
        var age = i.age;
        var trainingAge = i.trainingAge;
        var hadPriorPeak = i.hadPriorPeak;
        var deadlineWeeks = i.deadlineWeeks;
        var recentTrend = i.recentTrend;
        var currentPhase = i.currentPhase;
        var tdeeKcal = i.tdeeKcal;
        var targetPbfPct = i.targetPbfPct;
        var targetBmi = i.targetBmi;
        var dFfmKg = i.dFfmKg;
        var k = i.k;
        var smmUp = i.smmUp;
        var smmDown = i.smmDown;
        var smmFlat = i.smmFlat;
        var smmKnown = i.smmKnown;
        var subNoiseAll = i.subNoiseAll;
        var taExp = i.taExp;
        var input = i.input;
        return (dBfmKg < -NOISE.bfm && smmKnown && dSmmKg >= 1.5 * NOISE.smm && Math.abs(dBfmKg) <= Math.max(6.5, 0.085 * curWeightKg) && curPbfPct >= (sex === 'male' ? 14.5 : 22.5) && currentPhase !== 'bulk' && (deadlineWeeks === null || deadlineWeeks >= 16) && (trainingAge === 'novice' || hadPriorPeak === true || (trainingAge === 'intermediate' && curPbfPct >= (sex === 'male' ? 22 : 30))));
      }
    },
    {
      order: 10,
      modeId: "muscleGain",
      reason: "지방도 빼고 근육도 늘리고 싶으시지만, 근육 목표(제지방 환산 {ffmKg}kg)가 지방 목표({fatKg}kg)보다 큽니다. 근성장을 먼저 두고, 엔진이 '증량 → 단기커팅' 순서와 동시 진행 중 빠른 쪽을 골라줍니다.",
      source: "dBfmKg < -NOISE.bfm && smmUp && dFfmKg > Math.abs(dBfmKg)",
      test: function (i) {
        var dWeightKg = i.dWeightKg;
        var dSmmKg = i.dSmmKg;
        var dBfmKg = i.dBfmKg;
        var curPbfPct = i.curPbfPct;
        var curBmi = i.curBmi;
        var curSmmKg = i.curSmmKg;
        var curBfmKg = i.curBfmKg;
        var curWeightKg = i.curWeightKg;
        var heightCm = i.heightCm;
        var sex = i.sex;
        var age = i.age;
        var trainingAge = i.trainingAge;
        var hadPriorPeak = i.hadPriorPeak;
        var deadlineWeeks = i.deadlineWeeks;
        var recentTrend = i.recentTrend;
        var currentPhase = i.currentPhase;
        var tdeeKcal = i.tdeeKcal;
        var targetPbfPct = i.targetPbfPct;
        var targetBmi = i.targetBmi;
        var dFfmKg = i.dFfmKg;
        var k = i.k;
        var smmUp = i.smmUp;
        var smmDown = i.smmDown;
        var smmFlat = i.smmFlat;
        var smmKnown = i.smmKnown;
        var subNoiseAll = i.subNoiseAll;
        var taExp = i.taExp;
        var input = i.input;
        return (dBfmKg < -NOISE.bfm && smmUp && dFfmKg > Math.abs(dBfmKg));
      }
    },
    {
      order: 11,
      modeId: "fatLoss",
      reason: "지방도 빼고 근육도 늘리고 싶으시고, 체지방률 {curPbfPct}% · 운동경력상 동시 진행이 가능한 구간은 맞습니다. 다만 빼야 할 지방 {fatKg}kg이 리컴프가 커버하는 범위(체중의 8.5%, 약 {recompFatCapKg}kg)를 넘습니다. 리컴프로 가면 중단 없는 적자가 6개월을 넘어갑니다. 그래서 감량을 먼저 두고, 엔진이 '감량 → 유지 2주 → 증량' 분할과 동시 진행 중 빠른 쪽을 고릅니다. 리컴프를 원하시면 직접 고르실 수 있고, 그때 걸리는 기간을 함께 보여드립니다.",
      source: "dBfmKg < -NOISE.bfm && smmUp",
      test: function (i) {
        var dWeightKg = i.dWeightKg;
        var dSmmKg = i.dSmmKg;
        var dBfmKg = i.dBfmKg;
        var curPbfPct = i.curPbfPct;
        var curBmi = i.curBmi;
        var curSmmKg = i.curSmmKg;
        var curBfmKg = i.curBfmKg;
        var curWeightKg = i.curWeightKg;
        var heightCm = i.heightCm;
        var sex = i.sex;
        var age = i.age;
        var trainingAge = i.trainingAge;
        var hadPriorPeak = i.hadPriorPeak;
        var deadlineWeeks = i.deadlineWeeks;
        var recentTrend = i.recentTrend;
        var currentPhase = i.currentPhase;
        var tdeeKcal = i.tdeeKcal;
        var targetPbfPct = i.targetPbfPct;
        var targetBmi = i.targetBmi;
        var dFfmKg = i.dFfmKg;
        var k = i.k;
        var smmUp = i.smmUp;
        var smmDown = i.smmDown;
        var smmFlat = i.smmFlat;
        var smmKnown = i.smmKnown;
        var subNoiseAll = i.subNoiseAll;
        var taExp = i.taExp;
        var input = i.input;
        return (dBfmKg < -NOISE.bfm && smmUp);
      }
    },
    {
      order: 12,
      modeId: "fatLoss",
      reason: "체지방률 {curPbfPct}%에 웨이트 경력이 아직 짧습니다. 이 조합은 감량 중에도 근육이 붙는 드문 구간이라, 기본 속도를 '적자 TDEE 15% 이하'(하루 약 {mildDeficitKcal}kcal)로 잡았습니다. 더 빠른 '상'도 고르실 수 있지만, 그 순간 근성장 배율이 0.70에서 0.30으로 떨어집니다 — 도착 예정일은 {etaDiffWeeks}주 빨라지고 근육은 그만큼 포기하는 거래입니다.",
      source: "dBfmKg < -NOISE.bfm && !smmDown && trainingAge === 'novice' && curPbfPct >= (sex === 'male' ? 25 : 32)",
      test: function (i) {
        var dWeightKg = i.dWeightKg;
        var dSmmKg = i.dSmmKg;
        var dBfmKg = i.dBfmKg;
        var curPbfPct = i.curPbfPct;
        var curBmi = i.curBmi;
        var curSmmKg = i.curSmmKg;
        var curBfmKg = i.curBfmKg;
        var curWeightKg = i.curWeightKg;
        var heightCm = i.heightCm;
        var sex = i.sex;
        var age = i.age;
        var trainingAge = i.trainingAge;
        var hadPriorPeak = i.hadPriorPeak;
        var deadlineWeeks = i.deadlineWeeks;
        var recentTrend = i.recentTrend;
        var currentPhase = i.currentPhase;
        var tdeeKcal = i.tdeeKcal;
        var targetPbfPct = i.targetPbfPct;
        var targetBmi = i.targetBmi;
        var dFfmKg = i.dFfmKg;
        var k = i.k;
        var smmUp = i.smmUp;
        var smmDown = i.smmDown;
        var smmFlat = i.smmFlat;
        var smmKnown = i.smmKnown;
        var subNoiseAll = i.subNoiseAll;
        var taExp = i.taExp;
        var input = i.input;
        return (dBfmKg < -NOISE.bfm && !smmDown && trainingAge === 'novice' && curPbfPct >= (sex === 'male' ? 25 : 32));
      }
    },
    {
      order: 13,
      modeId: "fatLoss",
      reason: "지방과 근육을 함께 줄이는 목표입니다. 근육 감소는 목표가 아니라 비용이라는 점만 알아두세요 — 계획은 근손실을 최소화하는 쪽으로 잡았고, 근육이 예상보다 빨리 빠지면 강도를 자동으로 낮춥니다.",
      source: "dBfmKg < -NOISE.bfm && smmDown",
      test: function (i) {
        var dWeightKg = i.dWeightKg;
        var dSmmKg = i.dSmmKg;
        var dBfmKg = i.dBfmKg;
        var curPbfPct = i.curPbfPct;
        var curBmi = i.curBmi;
        var curSmmKg = i.curSmmKg;
        var curBfmKg = i.curBfmKg;
        var curWeightKg = i.curWeightKg;
        var heightCm = i.heightCm;
        var sex = i.sex;
        var age = i.age;
        var trainingAge = i.trainingAge;
        var hadPriorPeak = i.hadPriorPeak;
        var deadlineWeeks = i.deadlineWeeks;
        var recentTrend = i.recentTrend;
        var currentPhase = i.currentPhase;
        var tdeeKcal = i.tdeeKcal;
        var targetPbfPct = i.targetPbfPct;
        var targetBmi = i.targetBmi;
        var dFfmKg = i.dFfmKg;
        var k = i.k;
        var smmUp = i.smmUp;
        var smmDown = i.smmDown;
        var smmFlat = i.smmFlat;
        var smmKnown = i.smmKnown;
        var subNoiseAll = i.subNoiseAll;
        var taExp = i.taExp;
        var input = i.input;
        return (dBfmKg < -NOISE.bfm && smmDown);
      }
    },
    {
      order: 14,
      modeId: "fatLoss",
      reason: "체지방을 줄이는 게 목표입니다. 체지방률 {curPbfPct}% 또는 운동경력 기준으로 커팅 조건(남 18% 이하 · 경력 6개월 이상)에는 아직 닿지 않아서, 같은 방향이지만 더 넓은 속도 범위를 쓰는 감량으로 잡았습니다. 체지방률이 {cuttingGate}%에 닿으면 커팅모드가 자동으로 열립니다.",
      source: "dBfmKg < -NOISE.bfm",
      test: function (i) {
        var dWeightKg = i.dWeightKg;
        var dSmmKg = i.dSmmKg;
        var dBfmKg = i.dBfmKg;
        var curPbfPct = i.curPbfPct;
        var curBmi = i.curBmi;
        var curSmmKg = i.curSmmKg;
        var curBfmKg = i.curBfmKg;
        var curWeightKg = i.curWeightKg;
        var heightCm = i.heightCm;
        var sex = i.sex;
        var age = i.age;
        var trainingAge = i.trainingAge;
        var hadPriorPeak = i.hadPriorPeak;
        var deadlineWeeks = i.deadlineWeeks;
        var recentTrend = i.recentTrend;
        var currentPhase = i.currentPhase;
        var tdeeKcal = i.tdeeKcal;
        var targetPbfPct = i.targetPbfPct;
        var targetBmi = i.targetBmi;
        var dFfmKg = i.dFfmKg;
        var k = i.k;
        var smmUp = i.smmUp;
        var smmDown = i.smmDown;
        var smmFlat = i.smmFlat;
        var smmKnown = i.smmKnown;
        var subNoiseAll = i.subNoiseAll;
        var taExp = i.taExp;
        var input = i.input;
        return (dBfmKg < -NOISE.bfm);
      }
    },
    {
      order: 15,
      modeId: "miniCut",
      reason: "증량 중이신데 체지방률이 {curPbfPct}%로 이미 증량 상한을 넘었습니다. 여기서 더 먹으면 늘어나는 대부분이 지방입니다(속칭 살크업). 3~5주 단기커팅으로 체지방을 먼저 정리하고 증량을 재개하는 순서로 잡았습니다.",
      source: "currentPhase === 'bulk' && smmUp && dBfmKg >= -NOISE.bfm && curPbfPct > (sex === 'male' ? 18 : 26) && taExp && age >= 19",
      test: function (i) {
        var dWeightKg = i.dWeightKg;
        var dSmmKg = i.dSmmKg;
        var dBfmKg = i.dBfmKg;
        var curPbfPct = i.curPbfPct;
        var curBmi = i.curBmi;
        var curSmmKg = i.curSmmKg;
        var curBfmKg = i.curBfmKg;
        var curWeightKg = i.curWeightKg;
        var heightCm = i.heightCm;
        var sex = i.sex;
        var age = i.age;
        var trainingAge = i.trainingAge;
        var hadPriorPeak = i.hadPriorPeak;
        var deadlineWeeks = i.deadlineWeeks;
        var recentTrend = i.recentTrend;
        var currentPhase = i.currentPhase;
        var tdeeKcal = i.tdeeKcal;
        var targetPbfPct = i.targetPbfPct;
        var targetBmi = i.targetBmi;
        var dFfmKg = i.dFfmKg;
        var k = i.k;
        var smmUp = i.smmUp;
        var smmDown = i.smmDown;
        var smmFlat = i.smmFlat;
        var smmKnown = i.smmKnown;
        var subNoiseAll = i.subNoiseAll;
        var taExp = i.taExp;
        var input = i.input;
        return (currentPhase === 'bulk' && smmUp && dBfmKg >= -NOISE.bfm && curPbfPct > (sex === 'male' ? 18 : 26) && taExp && age >= 19);
      }
    },
    {
      order: 16,
      modeId: "muscleGain",
      reason: "근육 {dSmmKg}kg을 만들려면 가장 깨끗한 증량(제지방비율 0.75)에서도 체중은 +{cleanBulkWeightKg}kg, 체지방은 +{cleanBulkFatKg}kg 늘어납니다. 입력하신 체중 {targetWeightKg}kg · 체지방 {targetBfmKg}kg을 한 번에 지나가는 경로는 존재하지 않습니다. 그래서 2단계로 계획합니다 — ① 증량으로 골격근 {targetSmmKg}kg을 먼저 만들고(약 {bulkWeeks}주) ② 그다음 4~6주 감량으로 체지방을 {targetBfmKg}kg까지 내립니다. 증량 구간이 32주를 넘으면 중간에 유지 4주가 자동으로 들어갑니다.",
      source: "smmUp && dBfmKg >= -NOISE.bfm && curPbfPct <= (sex === 'male' ? 18 : 26) && dWeightKg > 0 && (dFfmKg / dWeightKg) > 0.75",
      test: function (i) {
        var dWeightKg = i.dWeightKg;
        var dSmmKg = i.dSmmKg;
        var dBfmKg = i.dBfmKg;
        var curPbfPct = i.curPbfPct;
        var curBmi = i.curBmi;
        var curSmmKg = i.curSmmKg;
        var curBfmKg = i.curBfmKg;
        var curWeightKg = i.curWeightKg;
        var heightCm = i.heightCm;
        var sex = i.sex;
        var age = i.age;
        var trainingAge = i.trainingAge;
        var hadPriorPeak = i.hadPriorPeak;
        var deadlineWeeks = i.deadlineWeeks;
        var recentTrend = i.recentTrend;
        var currentPhase = i.currentPhase;
        var tdeeKcal = i.tdeeKcal;
        var targetPbfPct = i.targetPbfPct;
        var targetBmi = i.targetBmi;
        var dFfmKg = i.dFfmKg;
        var k = i.k;
        var smmUp = i.smmUp;
        var smmDown = i.smmDown;
        var smmFlat = i.smmFlat;
        var smmKnown = i.smmKnown;
        var subNoiseAll = i.subNoiseAll;
        var taExp = i.taExp;
        var input = i.input;
        return (smmUp && dBfmKg >= -NOISE.bfm && curPbfPct <= (sex === 'male' ? 18 : 26) && dWeightKg > 0 && (dFfmKg / dWeightKg) > 0.75);
      }
    },
    {
      order: 17,
      modeId: "muscleGain",
      reason: "근육을 늘리는 게 목표이고 체지방률 {curPbfPct}%는 증량을 시작해도 되는 구간입니다. a를 낮추면 린매스업, 올리면 벌크업 — 기간은 거의 같고 붙는 지방의 양이 달라집니다. 그래서 이 모드에서 상/중/하는 '빠르기'가 아니라 '붙는 지방'으로 표시됩니다.",
      source: "smmUp && dBfmKg >= -NOISE.bfm && curPbfPct <= (sex === 'male' ? 18 : 26) && dBfmKg <= Math.max(NOISE.bfm, dFfmKg / 3)",
      test: function (i) {
        var dWeightKg = i.dWeightKg;
        var dSmmKg = i.dSmmKg;
        var dBfmKg = i.dBfmKg;
        var curPbfPct = i.curPbfPct;
        var curBmi = i.curBmi;
        var curSmmKg = i.curSmmKg;
        var curBfmKg = i.curBfmKg;
        var curWeightKg = i.curWeightKg;
        var heightCm = i.heightCm;
        var sex = i.sex;
        var age = i.age;
        var trainingAge = i.trainingAge;
        var hadPriorPeak = i.hadPriorPeak;
        var deadlineWeeks = i.deadlineWeeks;
        var recentTrend = i.recentTrend;
        var currentPhase = i.currentPhase;
        var tdeeKcal = i.tdeeKcal;
        var targetPbfPct = i.targetPbfPct;
        var targetBmi = i.targetBmi;
        var dFfmKg = i.dFfmKg;
        var k = i.k;
        var smmUp = i.smmUp;
        var smmDown = i.smmDown;
        var smmFlat = i.smmFlat;
        var smmKnown = i.smmKnown;
        var subNoiseAll = i.subNoiseAll;
        var taExp = i.taExp;
        var input = i.input;
        return (smmUp && dBfmKg >= -NOISE.bfm && curPbfPct <= (sex === 'male' ? 18 : 26) && dBfmKg <= Math.max(NOISE.bfm, dFfmKg / 3));
      }
    },
    {
      order: 18,
      modeId: "muscleGain",
      reason: "근육을 늘리는 목표는 맞지만, 요청하신 체지방 증가 {dBfmKg}kg은 가장 공격적인 벌크업(제지방비율 0.40)보다도 많습니다 — 한국 헬스 커뮤니티가 살크업이라 부르는 구간입니다. 지방 목표를 {bulkFatCapKg}kg으로 잘라 계획했습니다. 근성장 상한은 훈련연령이 정하고, 잉여를 키운다고 그 상한이 올라가지 않습니다.",
      source: "smmUp && dBfmKg >= -NOISE.bfm && curPbfPct <= (sex === 'male' ? 18 : 26)",
      test: function (i) {
        var dWeightKg = i.dWeightKg;
        var dSmmKg = i.dSmmKg;
        var dBfmKg = i.dBfmKg;
        var curPbfPct = i.curPbfPct;
        var curBmi = i.curBmi;
        var curSmmKg = i.curSmmKg;
        var curBfmKg = i.curBfmKg;
        var curWeightKg = i.curWeightKg;
        var heightCm = i.heightCm;
        var sex = i.sex;
        var age = i.age;
        var trainingAge = i.trainingAge;
        var hadPriorPeak = i.hadPriorPeak;
        var deadlineWeeks = i.deadlineWeeks;
        var recentTrend = i.recentTrend;
        var currentPhase = i.currentPhase;
        var tdeeKcal = i.tdeeKcal;
        var targetPbfPct = i.targetPbfPct;
        var targetBmi = i.targetBmi;
        var dFfmKg = i.dFfmKg;
        var k = i.k;
        var smmUp = i.smmUp;
        var smmDown = i.smmDown;
        var smmFlat = i.smmFlat;
        var smmKnown = i.smmKnown;
        var subNoiseAll = i.subNoiseAll;
        var taExp = i.taExp;
        var input = i.input;
        return (smmUp && dBfmKg >= -NOISE.bfm && curPbfPct <= (sex === 'male' ? 18 : 26));
      }
    },
    {
      order: 19,
      modeId: "recomp",
      reason: "근육을 늘리는 게 목표지만 체지방률 {curPbfPct}%에서 바로 증량하면 지방이 먼저 붙습니다(속칭 살크업). 체지방 여유가 있다는 건 리컴프가 잘 먹히는 조건이기도 해서, 지방을 조금 내리면서 근육을 올리는 쪽으로 잡았습니다. 체지방률이 {bulkGate}% 아래로 내려가면 근성장모드가 열립니다.",
      source: "smmUp && dBfmKg >= -NOISE.bfm && curPbfPct > (sex === 'male' ? 18 : 26) && currentPhase !== 'bulk'",
      test: function (i) {
        var dWeightKg = i.dWeightKg;
        var dSmmKg = i.dSmmKg;
        var dBfmKg = i.dBfmKg;
        var curPbfPct = i.curPbfPct;
        var curBmi = i.curBmi;
        var curSmmKg = i.curSmmKg;
        var curBfmKg = i.curBfmKg;
        var curWeightKg = i.curWeightKg;
        var heightCm = i.heightCm;
        var sex = i.sex;
        var age = i.age;
        var trainingAge = i.trainingAge;
        var hadPriorPeak = i.hadPriorPeak;
        var deadlineWeeks = i.deadlineWeeks;
        var recentTrend = i.recentTrend;
        var currentPhase = i.currentPhase;
        var tdeeKcal = i.tdeeKcal;
        var targetPbfPct = i.targetPbfPct;
        var targetBmi = i.targetBmi;
        var dFfmKg = i.dFfmKg;
        var k = i.k;
        var smmUp = i.smmUp;
        var smmDown = i.smmDown;
        var smmFlat = i.smmFlat;
        var smmKnown = i.smmKnown;
        var subNoiseAll = i.subNoiseAll;
        var taExp = i.taExp;
        var input = i.input;
        return (smmUp && dBfmKg >= -NOISE.bfm && curPbfPct > (sex === 'male' ? 18 : 26) && currentPhase !== 'bulk');
      }
    },
    {
      order: 20,
      modeId: "muscleGain",
      reason: "BMI {curBmi}로 저체중 구간이고 체중을 늘리는 목표입니다. 지방만 늘리는 계획은 만들지 않으므로, 늘어나는 체중의 절반 이상이 제지방이 되도록 근성장 계획으로 잡았습니다.",
      source: "dWeightKg > NOISE.weight && smmFlat && curBmi < 20",
      test: function (i) {
        var dWeightKg = i.dWeightKg;
        var dSmmKg = i.dSmmKg;
        var dBfmKg = i.dBfmKg;
        var curPbfPct = i.curPbfPct;
        var curBmi = i.curBmi;
        var curSmmKg = i.curSmmKg;
        var curBfmKg = i.curBfmKg;
        var curWeightKg = i.curWeightKg;
        var heightCm = i.heightCm;
        var sex = i.sex;
        var age = i.age;
        var trainingAge = i.trainingAge;
        var hadPriorPeak = i.hadPriorPeak;
        var deadlineWeeks = i.deadlineWeeks;
        var recentTrend = i.recentTrend;
        var currentPhase = i.currentPhase;
        var tdeeKcal = i.tdeeKcal;
        var targetPbfPct = i.targetPbfPct;
        var targetBmi = i.targetBmi;
        var dFfmKg = i.dFfmKg;
        var k = i.k;
        var smmUp = i.smmUp;
        var smmDown = i.smmDown;
        var smmFlat = i.smmFlat;
        var smmKnown = i.smmKnown;
        var subNoiseAll = i.subNoiseAll;
        var taExp = i.taExp;
        var input = i.input;
        return (dWeightKg > NOISE.weight && smmFlat && curBmi < 20);
      }
    },
    {
      order: 21,
      modeId: "fatLoss",
      reason: "체지방·근육 목표는 측정 오차 안쪽이지만 체중을 {dWeightKg}kg 줄이는 목표가 있습니다. 줄어드는 체중이 최대한 지방이 되도록 감량 계획으로 잡았습니다.",
      source: "dWeightKg < -NOISE.weight",
      test: function (i) {
        var dWeightKg = i.dWeightKg;
        var dSmmKg = i.dSmmKg;
        var dBfmKg = i.dBfmKg;
        var curPbfPct = i.curPbfPct;
        var curBmi = i.curBmi;
        var curSmmKg = i.curSmmKg;
        var curBfmKg = i.curBfmKg;
        var curWeightKg = i.curWeightKg;
        var heightCm = i.heightCm;
        var sex = i.sex;
        var age = i.age;
        var trainingAge = i.trainingAge;
        var hadPriorPeak = i.hadPriorPeak;
        var deadlineWeeks = i.deadlineWeeks;
        var recentTrend = i.recentTrend;
        var currentPhase = i.currentPhase;
        var tdeeKcal = i.tdeeKcal;
        var targetPbfPct = i.targetPbfPct;
        var targetBmi = i.targetBmi;
        var dFfmKg = i.dFfmKg;
        var k = i.k;
        var smmUp = i.smmUp;
        var smmDown = i.smmDown;
        var smmFlat = i.smmFlat;
        var smmKnown = i.smmKnown;
        var subNoiseAll = i.subNoiseAll;
        var taExp = i.taExp;
        var input = i.input;
        return (dWeightKg < -NOISE.weight);
      }
    },
    {
      order: 22,
      modeId: "muscleGain",
      reason: "체중을 늘리는 목표이고 체지방률에 여유가 있습니다. 늘어나는 체중이 최대한 근육이 되도록 근성장 계획으로 잡았습니다.",
      source: "dWeightKg > NOISE.weight && curPbfPct <= (sex === 'male' ? 18 : 26)",
      test: function (i) {
        var dWeightKg = i.dWeightKg;
        var dSmmKg = i.dSmmKg;
        var dBfmKg = i.dBfmKg;
        var curPbfPct = i.curPbfPct;
        var curBmi = i.curBmi;
        var curSmmKg = i.curSmmKg;
        var curBfmKg = i.curBfmKg;
        var curWeightKg = i.curWeightKg;
        var heightCm = i.heightCm;
        var sex = i.sex;
        var age = i.age;
        var trainingAge = i.trainingAge;
        var hadPriorPeak = i.hadPriorPeak;
        var deadlineWeeks = i.deadlineWeeks;
        var recentTrend = i.recentTrend;
        var currentPhase = i.currentPhase;
        var tdeeKcal = i.tdeeKcal;
        var targetPbfPct = i.targetPbfPct;
        var targetBmi = i.targetBmi;
        var dFfmKg = i.dFfmKg;
        var k = i.k;
        var smmUp = i.smmUp;
        var smmDown = i.smmDown;
        var smmFlat = i.smmFlat;
        var smmKnown = i.smmKnown;
        var subNoiseAll = i.subNoiseAll;
        var taExp = i.taExp;
        var input = i.input;
        return (dWeightKg > NOISE.weight && curPbfPct <= (sex === 'male' ? 18 : 26));
      }
    },
    {
      order: 23,
      modeId: "maintain",
      reason: "입력하신 목표 조합으로는 방향이 뚜렷하게 잡히지 않습니다. 지금 몸을 유지하는 계획을 기본으로 보여드리고, 목표를 다시 입력하시면 바로 다시 계산합니다.",
      source: "true",
      test: function (i) {
        var dWeightKg = i.dWeightKg;
        var dSmmKg = i.dSmmKg;
        var dBfmKg = i.dBfmKg;
        var curPbfPct = i.curPbfPct;
        var curBmi = i.curBmi;
        var curSmmKg = i.curSmmKg;
        var curBfmKg = i.curBfmKg;
        var curWeightKg = i.curWeightKg;
        var heightCm = i.heightCm;
        var sex = i.sex;
        var age = i.age;
        var trainingAge = i.trainingAge;
        var hadPriorPeak = i.hadPriorPeak;
        var deadlineWeeks = i.deadlineWeeks;
        var recentTrend = i.recentTrend;
        var currentPhase = i.currentPhase;
        var tdeeKcal = i.tdeeKcal;
        var targetPbfPct = i.targetPbfPct;
        var targetBmi = i.targetBmi;
        var dFfmKg = i.dFfmKg;
        var k = i.k;
        var smmUp = i.smmUp;
        var smmDown = i.smmDown;
        var smmFlat = i.smmFlat;
        var smmKnown = i.smmKnown;
        var subNoiseAll = i.subNoiseAll;
        var taExp = i.taExp;
        var input = i.input;
        return (true);
      }
    }
  ];

  var OWNER_VERDICT = "오너에 대한 답은 두 개로 나뉘고, 이전 버전은 그 둘을 섞어서 틀렸습니다. **지금 하고 있는 것**은 리컴프가 맞습니다. 그러나 **입력한 목표(80.5kg / SMM 38.9 / BFM 12.0)**가 앱에 들어오면 정답은 리컴프가 아니라 **감량모드**입니다.\n\n**1) 앱이 추천해야 할 모드: 감량모드 (리컴프는 차선으로 비용과 함께 제시)**\n선택 규칙 11에 걸립니다. 방향(지방↓ + 근육↑)은 리컴프이고 체질 조건(체지방률 23.1%, 22세, 운동 시작 6월 말)도 리컴프 responder가 맞습니다 — 규칙 9가 탈락하는 이유는 오직 **크기**입니다. 빼야 할 지방 8.0kg이 리컴프 커버 범위 max(6.5kg, 체중의 8.5% = 7.37kg)를 넘습니다. 리컴프의 적자 상한(TDEE 15% = 421kcal/day = 주 0.383kg)으로 8kg을 빼면 21주, TDEE 하락까지 반영하면 24~26주가 **중단 없는 적자**입니다. 이전 레지스트리는 이걸 \"더 안전한 모드로 라우팅\"이라고 불렀지만, recomp의 maxContinuousWeeks가 null이었기 때문에 실제로 한 일은 '속도 상한 인하 + 20주 캡 제거'였습니다 — 같은 목표가 감량모드로 갔으면 20주에서 유지 2~4주가 강제됐을 겁니다. 이번 개정에서 recomp에 24주 캡을 넣었고, 크기 게이트로 이 케이스를 감량모드로 보냅니다.\n\n앱이 띄워야 할 문구: *\"리컴프를 원하시면 직접 고르실 수 있습니다. 다만 8kg 감량에 24~26주가 걸리고 그 전 구간이 쉬지 않는 적자입니다. 감량으로 잡으면 20주에서 유지기가 한 번 들어가고, 근육 +1.0kg은 그 뒤 증량 다리에서 회수합니다.\"*\n\n**커팅모드는 열리지 않습니다.** 체지방률 23.1%가 커팅 게이트(남 18%)보다 위입니다. 오너가 \"커팅모드\"를 직접 누르면: *\"지금은 커팅이 아니라 감량입니다. 커팅은 이미 있는 근육을 드러내는 작업이라 18% 아래에서 의미가 생깁니다. 18%에 도달하면 자동으로 열립니다.\"* — 감량/커팅을 두 개로 나눈 실제 가치가 이것입니다. 두 모드는 같은 방향이지만 커팅이 **더 보수적**입니다(a 상한 0.75 vs 0.90, 단백질 하한 2.4 vs 2.2). 그래서 합치면 안 됩니다. 다만 이번 개정에서 린 가드(남 15% / 여 23% 미만은 감량모드 선택 불가 → 커팅으로 강등)를 넣기 전까지는, 마른 사람일수록 더 공격적인 모드를 받는 안전 역전이 실제로 존재했습니다.\n\n**2) trainingAge를 먼저 확정하세요 — 이 케이스는 그 한 값이 전부를 결정합니다.**\n새 기준(주 2회 이상 저항운동 지속 개월: <6개월 novice)으로 오너는 6월 말 시작 → **novice**입니다. 테스트 케이스가 intermediate로 돌린 것은 분류 기준이 레지스트리에 없었기 때문입니다. 차이가 작지 않습니다 — 목표 근육 +1.0kg(제지방 환산 +1.76kg)을 24주에 달성 가능한지가 뒤집힙니다: intermediate × recomp 배율 0.35면 24주에 ΔSMM +0.71kg으로 **미달**, novice × 0.70이면 크게 초과. 앱은 선택된 trainingAge 기준의 예상 ΔSMM을 화면에 계산해 보여줘야 하고, 지금은 말해주지 않습니다.\n\n**3) 가장 실행 가치가 큰 조정: 하루 80~100kcal 더 드세요.**\nFFM 66.7kg → BMR 1,811(인바디 인쇄값 1,810과 일치) → TDEE@PAL1.55 = 2,807kcal. 81일간 지방 5.3kg 감소를 에너지로 환산하면 **하루 504kcal 적자 = TDEE의 18.0%**입니다. 엔진의 보호 경계는 15%(421kcal)입니다. 즉 지금 리컴프 보호 구간을 **83kcal/day 차이로** 벗어나 달리고 있고, 그 대가로 근성장 배율이 novice 0.70 → 0.30으로 떨어져 있습니다. 하루 100kcal만 더 먹으면 감량 속도는 거의 그대로인데 근육 증가율이 두 배 이상으로 뜁니다. 이건 오너 개인의 팁이 아니라 규칙입니다 — 이번 개정에서 선택 규칙 12(입문자 보호)로 같은 조건의 모든 사용자에게 적용됩니다.\n\n**4) \"근육 +1.7kg\"은 절반만 믿으세요.**\n81일간 FFM +3.0kg인데, 엔진 자신의 생리적 상한으로는 novice + 실적자(>15%)에서 최대 +0.87kg입니다. 관측치가 상한의 3.4배입니다. 분해하면 측정 시각 이동(07:36 → 11:09) +0.5~1.0kg, 글리코겐·훈련성 부종(Damas 2016) +0.5~1.5kg, 실제 제지방 +0.5~2.0kg. 결정적으로 — 체중은 −2.3kg만 움직였는데 결과지는 지방 −5.3kg을 주장합니다. **그 차액 3.0kg 전부가 \"근육이 늘었다\"는 주장에서 나옵니다. 하나가 무너지면 둘 다 무너집니다.** 방향은 진짜고(PBF 28.4 → 24.2 → 23.1) 크기가 40~60% 과장된 겁니다.\n\n**5) 최근 스캔(9/19)은 판정에 쓰면 안 되고, 이제 규칙이 그걸 강제합니다.**\n8/31 → 9/19는 19일로 28일 게이트 미달입니다. 이전에는 이 게이트가 noiseFloor 산문에만 있고 조건식에는 없어서 규칙은 81일 전체를 썼고, 문서와 규칙이 서로 다른 답을 냈습니다. 이번 개정에서 전역 전처리 ①로 구현했습니다. 앱 문구: *\"간격이 19일이라 판정하지 않습니다. 이번엔 오전 11시에 재셨는데, 그것만으로 근육 0.5kg쯤은 달라 보입니다. 다음 인바디는 10월 17일 이후, 오전 7~8시, 공복으로.\"*\n\n**6) 인바디가 제안한 78.4kg은 목표로 쓰면 안 됩니다.**\n역산하면 적정체중 = 현재 FFM / 0.85입니다. FFM을 상수로 박고 푼 식이라 **근육조절이 구조적으로 항상 0.0**이 나옵니다. 더 나쁜 건 목표가 움직인다는 것 — 근육 +2kg이면 적정체중이 80.8kg으로 올라가고, **근육을 2kg 잃으면 76.1kg으로 내려가 목표에 \"가까워집니다\".** 이 숫자에 앵커링하면 앱이 근손실을 진전으로 보상합니다. 오너의 목표는 체중이 아니라 **체지방률 15%**로 잡아야 합니다. 인쇄된 권장섭취칼로리 3,104kcal도 PAL 1.715 가정치(3104/1810 = 1.715)라 앱의 2,807kcal과 하루 298kcal 차이 — 3개월이면 지방 3.5kg 분량의 계획 오차입니다. 쓰지 마세요.\n\n**한 줄 요약: 입력한 목표로는 감량모드(리컴프는 24~26주 비용과 함께 차선 제시) + 하루 100kcal 증량 + trainingAge를 novice로 확정 + 다음 측정은 10월 17일 이후 오전 공복. 체지방률 18%에 닿으면 그때 커팅모드가 열립니다.**";


  function byId(id) {
    for (var i = 0; i < MODES.length; i++) if (MODES[i].id === id) return MODES[i];
    return null;
  }

  /* 한국어 조사 교정 — 치환한 자리 바로 뒤에 붙은 조사만 손댄다.
     본문 전체를 훑으면 '증가' 같은 단어의 끝 글자를 조사로 오인한다. */
  var JOSA = {
    '이라서': ['이라서', '라서'], '라서': ['이라서', '라서'],
    '은': ['은', '는'], '는': ['은', '는'],
    '이': ['이', '가'], '가': ['이', '가'],
    '을': ['을', '를'], '를': ['을', '를'],
    '과': ['과', '와'], '와': ['과', '와'],
    '으로': ['으로', '로'], '로': ['으로', '로']
  };
  function hasFinalConsonant(s) {
    if (!s) return false;
    var c = s.charCodeAt(s.length - 1);
    if (c < 0xAC00 || c > 0xD7A3) return /[0-9]$/.test(s) ? /[0136780]$/.test(s) : true;
    return (c - 0xAC00) % 28 !== 0;
  }
  function fill(tpl, i) {
    return String(tpl).replace(/\{(\w+)\}(이라서|라서|으로|로|은|는|이|가|을|를|과|와)?/g,
      function (_, k, josa) {
        var v = i[k];
        var s = (v == null) ? '—'
              : (typeof v === 'number' ? String(Math.round(v * 10) / 10) : String(v));
        if (!josa) return s;
        var pair = JOSA[josa];
        return s + (pair ? pair[hasFinalConsonant(s) ? 0 : 1] : josa);
      });
  }

  /**
   * 입력에서 모드를 고른다.
   * i = { dWeightKg, dSmmKg, dBfmKg, curWeightKg, curSmmKg, curBfmKg, curPbfPct, curBmi,
   *       sex, age, trainingAge, hadPriorPeak, deadlineWeeks, recentTrend }
   * recentTrend = { weeksSpan, dWeightKg, dSmmKg, dBfmKg } | null
   */
  function select(input) {
    var i = {};
    for (var k in input) if (Object.prototype.hasOwnProperty.call(input, k)) i[k] = input[k];
    i.NOISE = NOISE;
    if (i.targetPbfPct == null && i.curBfmKg != null && i.curWeightKg != null) {
      i.targetPbfPct = (i.curBfmKg + (i.dBfmKg || 0)) / (i.curWeightKg + (i.dWeightKg || 0)) * 100;
    }
    // 규칙이 쓰는 파생값 — 여기서 한 번만 계산한다
    var ffm = (i.curWeightKg != null && i.curBfmKg != null) ? (i.curWeightKg - i.curBfmKg) : null;
    i.k = (ffm && ffm > 0 && i.curSmmKg != null) ? (i.curSmmKg / ffm) : 0.57;
    i.dFfmKg = (i.dSmmKg || 0) / i.k;
    if (i.targetPbfPct == null && i.curBfmKg != null && i.curWeightKg != null) {
      i.targetPbfPct = (i.curBfmKg + (i.dBfmKg || 0)) / (i.curWeightKg + (i.dWeightKg || 0)) * 100;
    }
    if (i.targetBmi == null && i.heightCm) {
      i.targetBmi = (i.curWeightKg + (i.dWeightKg || 0)) / Math.pow(i.heightCm / 100, 2);
    }
    i.smmKnown = (i.dSmmKg != null && isFinite(i.dSmmKg));
    i.smmUp    = i.smmKnown && i.dSmmKg > NOISE.smm;
    i.smmDown  = i.smmKnown && i.dSmmKg < -NOISE.smm;
    // 미지를 "변화 없음"으로 봅니다. smmKnown 을 곱하면 미지일 때 세 플래그가
    // 모두 false 가 되어 어떤 규칙에도 안 걸립니다 — 전수 분할이 깨집니다.
    i.smmFlat  = !i.smmKnown || Math.abs(i.dSmmKg) <= NOISE.smm;
    i.subNoiseAll = Math.abs(i.dWeightKg || 0) < NOISE.weight &&
                    Math.abs(i.dSmmKg || 0) < NOISE.smm &&
                    Math.abs(i.dBfmKg || 0) < NOISE.bfm;
    // 화이트리스트입니다. 예전엔 !== 'novice' 라 값이 없거나 오타이면
    // 숙련자 게이트가 열렸습니다 — 누락된 입력이 가드를 약화시키는 쪽으로만
    // 작동했습니다. 레지스트리 F절이 이걸 이미 문장으로 요구하고 있었습니다.
    i.taExp = ['intermediate', 'advanced', 'elite'].indexOf(i.trainingAge) >= 0;
    if (i.currentPhase === undefined) i.currentPhase = null;
    i.input = i;

    /* 거부 문구가 이름으로 요구하는 파생값들.
       없으면 fill() 이 '—' 를 찍습니다. 실제로 이런 문장이 나갔습니다:
         "계획을 만들기 전에 필요한 값이 빠져 있습니다: —."
         "혹시 근육 +—kg · 지방 −—kg을 입력하려던 건 아닌가요?"
       계획을 거부해 놓고 무엇이 빠졌는지 말하지 않는 것이 가장 나쁩니다. */
    var REQUIRED = ['curWeightKg', 'curSmmKg', 'curBfmKg', 'heightCm', 'age',
                    'dWeightKg', 'dSmmKg', 'dBfmKg'];
    var LABEL = { curWeightKg: '현재 체중', curSmmKg: '현재 골격근량', curBfmKg: '현재 체지방량',
                  heightCm: '키', age: '나이', dWeightKg: '체중 목표',
                  dSmmKg: '근육 목표', dBfmKg: '지방 목표', sex: '성별' };
    var miss = REQUIRED.filter(function (f) { return i[f] == null || !isFinite(i[f]); })
                       .map(function (f) { return LABEL[f] || f; });
    if (i.sex !== 'male' && i.sex !== 'female') miss.push(LABEL.sex);
    i.missingFields = miss.length ? miss.join(', ') : '없음';

    i.absDSmmKg = Math.abs(i.dSmmKg || 0);
    i.absDBfmKg = Math.abs(i.dBfmKg || 0);
    // 근육·지방 목표가 함의하는 체중 변화 (제지방 환산은 아래 k 기반 dFfmKg 사용)
    i.impliedDWeightKg = (i.dBfmKg || 0) + (i.dFfmKg != null ? i.dFfmKg : (i.dSmmKg || 0) / 0.55);
    i.impliedWeightKg = (i.curWeightKg || 0) + i.impliedDWeightKg;

    i.ratePct = (i.deadlineWeeks && i.curWeightKg)
      ? Math.abs(i.dWeightKg) / i.curWeightKg / i.deadlineWeeks * 100 : null;
    i.targetPbf = i.targetPbfPct;
    // 문구 치환용 파생값
    i.ffmKg = (i.dSmmKg || 0) * 1.75;          // 골격근 변화가 함의하는 제지방 변화
    i.fatKg = Math.abs(i.dBfmKg || 0);
    i.weeksSpan = i.recentTrend ? i.recentTrend.weeksSpan : null;
    i.pct = (i.recentTrend && i.curWeightKg)
      ? Math.abs(i.recentTrend.dWeightKg / i.curWeightKg * 100) : null;
    // 문구 치환에 쓰는 파생값 — 규칙 문구가 요구하는 이름 그대로 맞춘다
    var maleGate = i.sex === 'male';
    i.cuttingGate = maleGate ? 18 : 26;
    i.bulkGate = maleGate ? 18 : 26;
    i.recompFatCapKg = Math.round(Math.max(6.5, 0.085 * (i.curWeightKg || 0)) * 10) / 10;
    i.fatCapKcal = Math.round(31 * (i.curBfmKg || 0));
    i.targetWeightKg = Math.round(((i.curWeightKg || 0) + (i.dWeightKg || 0)) * 10) / 10;
    i.targetBfmKg = Math.round(((i.curBfmKg || 0) + (i.dBfmKg || 0)) * 10) / 10;
    i.targetSmmKg = Math.round(((i.curSmmKg || 0) + (i.dSmmKg || 0)) * 10) / 10;
    i.bulkFatCapKg = Math.round(Math.max(NOISE.bfm, i.dFfmKg / 3) * 10) / 10;
    // 증량으로 근육 목표를 채울 때 따라붙는 체중·지방 (제지방 비율 0.6 가정)
    i.cleanBulkWeightKg = i.dFfmKg > 0 ? Math.round(i.dFfmKg / 0.6 * 10) / 10 : 0;
    i.cleanBulkFatKg = i.dFfmKg > 0 ? Math.round((i.cleanBulkWeightKg - i.dFfmKg) * 10) / 10 : 0;
    // 근성장 속도 — 엔진이 있으면 같은 모델을 쓴다
    var monthly = null;
    if (global.MB_ENGINE && global.MB_ENGINE.baseSmmRatePerWeek && i.curWeightKg) {
      monthly = global.MB_ENGINE.baseSmmRatePerWeek(i.curWeightKg,
        { trainingAge: i.trainingAge, sex: i.sex, age: i.age, hadPriorPeak: i.hadPriorPeak },
        i.k) * 4.345;
    }
    if (monthly && monthly > 0) {
      i.expectedMonthlySmmKg = Math.round(monthly * 100) / 100;
      i.smmVisibleMonths = Math.ceil(NOISE.smm / monthly);
      i.bulkWeeks = i.dSmmKg > 0 ? Math.ceil(i.dSmmKg / (monthly / 4.345)) : 0;
    } else {
      i.expectedMonthlySmmKg = null; i.smmVisibleMonths = null; i.bulkWeeks = null;
    }
    // 완만한 적자(TDEE 15%)로 갈 때와 공격적으로 갈 때의 도착 차이 (주)
    if (i.tdeeKcal && i.dBfmKg < 0) {
      var mild = 0.15 * i.tdeeKcal * 7 / 7700;
      var hard = 0.25 * i.tdeeKcal * 7 / 7700;
      i.mildDeficitKcal = Math.round(0.15 * i.tdeeKcal);
      i.etaDiffWeeks = Math.max(0, Math.round(Math.abs(i.dBfmKg) / mild - Math.abs(i.dBfmKg) / hard));
    } else { i.mildDeficitKcal = null; i.etaDiffWeeks = null; }

    i.reason = i.hadPriorPeak ? '쉬었다 복귀한 경우'
             : (i.trainingAge === 'novice' ? '운동 입문 단계'
             : (i.curPbfPct >= (i.sex === 'male' ? 18 : 26) ? '체지방이 아직 남아 있는 상태'
             : '지금 구간'));

    // 시간 게이트: 간격이 4주 미만인 추세는 판정에 쓰지 않는다 (수분·시각 변동이 신호를 덮는다)
    var trendNote = null;
    if (i.recentTrend && i.recentTrend.weeksSpan != null && i.recentTrend.weeksSpan < 4) {
      trendNote = '최근 두 측정 간격이 ' + Math.round(i.recentTrend.weeksSpan * 7) +
                  '일이라 추세로 쓰지 않았습니다. 변화 판정은 4주 이상 간격이 필요합니다.';
      i.recentTrend = null;
    }

    for (var r = 0; r < REFUSALS.length; r++) {
      var ref = REFUSALS[r];
      // 예외를 '해당 없음'으로 삼키면 누락된 입력이 언제나 가드를 약화시키는
      // 쪽으로만 작동합니다. 안전 거부에서는 예외를 '걸림'으로 취급합니다.
      var hit = false;
      try { hit = !!ref.test(i); }
      catch (e) { hit = true; if (typeof console !== 'undefined') console.warn('거부 규칙 평가 실패', r, e); }
      if (hit) {
        return { refused: true, message: fill(ref.message, i), mode: null, trendNote: trendNote };
      }
    }

    for (var n = 0; n < RULES.length; n++) {
      var rule = RULES[n];
      // 선택 규칙은 반대입니다 — 평가 실패한 규칙은 고르지 않습니다.
      // 다만 조용히 넘어가지 않고 남깁니다.
      var ok = false;
      try { ok = !!rule.test(i); }
      catch (e) { ok = false; if (typeof console !== 'undefined') console.warn('선택 규칙 평가 실패', n, e); }
      if (ok) {
        var mode = byId(rule.modeId);
        return {
          refused: false, mode: mode, modeId: rule.modeId,
          reason: fill(rule.reason, i), ruleOrder: rule.order, ruleSource: rule.source,
          alternatives: alternativesFor(rule.modeId, i),
          trendNote: trendNote,
          subNoise: {
            weight: Math.abs(i.dWeightKg || 0) < NOISE.weight,
            smm: Math.abs(i.dSmmKg || 0) < NOISE.smm,
            bfm: Math.abs(i.dBfmKg || 0) < NOISE.bfm
          }
        };
      }
    }
    return { refused: false, mode: byId('maintain'), modeId: 'maintain',
             reason: '해당하는 규칙이 없어 유지로 둡니다.', ruleOrder: null,
             alternatives: [], trendNote: trendNote };
  }

  /** 선택되지 않았지만 "왜 이건 아닌가"를 설명해 줄 만한 모드들 */
  function alternativesFor(chosenId, i) {
    var out = [];
    MODES.forEach(function (m) {
      if (m.id === chosenId) return;
      var why = whyNot(m, i);
      if (why) out.push({ id: m.id, nameKo: m.nameKo, why: why });
    });
    return out;
  }

  function whyNot(m, i) {
    var maleGate = i.sex === 'male';
    if (m.id === 'cutting' && i.curPbfPct > (maleGate ? 18 : 26)) {
      return '체지방률 ' + Math.round(i.curPbfPct * 10) / 10 + '% 는 커팅 기준(' +
             (maleGate ? 18 : 26) + '%)보다 높습니다. 지금은 커팅이 아니라 감량입니다. ' +
             (maleGate ? 18 : 26) + '% 에 닿으면 자동으로 열립니다.';
    }
    if (m.id === 'muscleGain' && i.curPbfPct > (maleGate ? 18 : 26)) {
      return '체지방률이 높은 상태에서 증량하면 늘어나는 대부분이 지방입니다. 먼저 ' +
             (maleGate ? 18 : 26) + '% 아래로 내려가는 편이 결과가 좋습니다.';
    }
    if (m.id === 'recomp' && i.trainingAge === 'advanced' && i.curPbfPct < (maleGate ? 15 : 23)) {
      return '훈련 경력이 길고 이미 마른 상태에서는 리컴프 속도가 인바디 측정 오차보다 느립니다.';
    }
    if (m.id === 'miniCut' && (i.deadlineWeeks == null || i.deadlineWeeks > 6)) {
      return '단기커팅은 6주 안에 마감이 있을 때만 의미가 있습니다.';
    }
    if (m.id === 'recovery' && !(i.recentTrend && i.recentTrend.weeksSpan >= 8)) {
      return '최근에 긴 감량을 끝낸 기록이 없습니다. 회복모드는 감량 뒤에 오는 단계입니다.';
    }
    return null;
  }

  /** ★ 뒤는 구현 노트라 화면에 내보내지 않는다 */
  function forDisplay(text) {
    if (!text) return '';
    var cut = String(text).split('★')[0];
    return cut.replace(/\n{2,}/g, '\n').trim();
  }

  global.MB_MODES = {
    forDisplay: forDisplay,
    NOISE: NOISE, MODES: MODES, RULES: RULES, REFUSALS: REFUSALS,
    OWNER_VERDICT: OWNER_VERDICT,
    select: select, byId: byId, whyNot: whyNot
  };
})(window);