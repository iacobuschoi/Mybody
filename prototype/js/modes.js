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
    rationale: "인바디가 실제로 '재는' 것은 임피던스에서 추정한 체수분(TBW) 하나뿐이고, 나머지는 전부 산수입니다 — 오너의 결과지로 검증하면 FFM = TBW/0.73, BFM = 체중 − FFM, BMR = 370 + 21.6×FFM이 전부 정확히 재현됩니다. 그래서 TBW가 1L 틀리면 FFM이 1.37kg, BFM이 1.37kg(반대 부호), PBF가 1.58%p 틀립니다. 물 한 병 분량입니다.\n\n체중 1.0kg: 설계 문서 §0.2의 기존 값을 유지했습니다. 실측 재현성만 보면 0.7~0.8kg이 더 정확하지만, UI가 이미 '하루에도 ±1kg 가까이 움직입니다'라고 말하고 있어 숫자와 카피를 일치시키는 쪽을 택했습니다.\n\n골격근량 0.6kg: 설계 문서는 0.5kg, 현재 engine.js의 classifyGoal은 0.3kg을 쓰고 있는데 둘 다 너무 낮습니다. 엄격 표준화 조건(Frontiers in Nutrition 2024, InBody 770) 일간 변동이 질량 지표 0.1~0.7kg인데, 오너는 실험실이 아니라 헬스장에서 07:36 / 08:35 / 11:09에 쟀습니다. 측정 시각이 3.5시간 벌어진 것만으로 FFM이 약 1kg 움직입니다. 실사용 팽창계수를 적용해 0.6kg으로 올립니다. ★engine.js의 NOISE = 0.3 은 반드시 고쳐야 합니다 — 지금은 목표 +0.4kg 근육으로도 '근성장모드'가 켜지고, 그건 잡음이 모드를 고르는 겁니다.\n\n체지방량 1.0kg: 설계 문서 값 유지. BFM은 체중과 FFM에서 뺄셈으로 나오므로 두 오차를 모두 물려받습니다.\n\n중요한 구조적 단서: ΔBFM = Δ체중 − ΔFFM 이므로 Δ근육과 Δ지방은 독립적인 두 증거가 아닙니다. 모드 판정에서 둘을 같은 비중으로 세면 같은 오차를 두 번 세는 것입니다. 신뢰도 순서는 체중 > 체지방률 > 체지방량 > 골격근량입니다.\n\n이 노이즈 바닥과 별개로 엔진에 두 개의 시간 게이트가 필요합니다: ① 최근 두 스캔 간격이 28일 미만이면 recentTrend를 판정에 쓰지 않습니다 ② 훈련 시작 8주 미만이면 ΔSMM을 판정 입력에서 아예 제거합니다(0 처리가 아니라 제거). 운동 초기 SMM 증가는 부종과 글리코겐이고(Damas 2016: 3주차 CSA 증가는 대부분 손상성 종창), 그 크기가 1~2kg이라 임계값으로는 절대 막을 수 없습니다."
  };

  var MODES = [
    {
      id: "fatLoss",
      nameKo: "감량모드",
      aliasKo: "다이어트 / 체중감량 / 감량기",
      nameEn: "Fat-Loss Phase",
      oneLiner: "체중과 체지방을 함께 줄이는 가장 기본 모드. 근육은 '지키는 것'이 목표지 늘리는 게 목표가 아닙니다.",
      whoFor: "체지방률이 아직 높은 사람(남 18%↑ / 여 26%↑), 근육 목표 없이 일단 살을 빼야 하는 사람, 벌크업 후 체지방이 올라간 사람.",
      notFor: "이미 마른 사람(BMI 20 미만), 근육 증가가 진짜 목표인 사람, 남 18% / 여 26% 아래에서 선명도를 원하는 사람(→ 커팅모드).",
      direction: "deficit",
      aMin: 0.35, aMax: 0.9,
      strategy: "auto",
      proteinPerFfmMin: 2.2, proteinPerFfmMax: 2.8,
      typicalWeeksMin: 8, typicalWeeksMax: 20,
      maxContinuousWeeks: 20,
      trainingPolicyKo: "웨이트 주 3~5회, 근육군당 주 10~16세트를 '유지'합니다. 볼륨을 늘려서 근손실을 막는 게 아닙니다 — Roth 2023 RCT는 적자 상태에서 웨이트 볼륨이 제지방 보존에 영향을 주지 않는다고 결론냈습니다. 근육을 지키는 진짜 지렛대는 단백질과 감량 속도입니다. 유산소는 주 60~240분 범위에서 a에 따라 붙습니다.",
      expectedKo: "주 0.41~0.83%BW 감소(엔진 CUT_RANGE 상한이 0.90%/주라 그 위는 물리적으로 안 나옵니다). 86.7kg 기준 주 0.36~0.72kg. 근육은 대부분 '제자리'가 성공입니다. 단, 체지방률이 높고 운동경력이 짧으면 적자 중에도 근육이 붙습니다(엔진 novice×0.30) — 그건 계획에 이미 반영돼 있습니다.",
      risksKo: "a를 0.45 위로 올리면 적자가 TDEE 15%를 넘어 엔진의 근성장 배율이 novice 0.70→0.30, intermediate 0.35→0.05로 떨어집니다. 즉 '빨리 빼기'를 선택하는 순간 근육 목표는 사실상 포기됩니다. Garthe 2011: 주 1.4% 감량군은 제지방 −0.2%, 테스토스테론 감소, SHBG 증가. 20주를 넘기면 T3/T4/렙틴 억제가 몇 달 남습니다.",
      exitCriteriaKo: "① 목표 체지방량 도달 ② 20주 연속 경과 → 유지모드 4~10주 강제 ③ SMM이 2회 연속 측정에서 노이즈 바닥을 넘어 하락 ④ 체지방률이 남 18% / 여 26%에 도달 → 커팅모드로 전환 제안.",
      evidence: "a범위: 엔진 CUT_RANGE를 역산 — a=0.35→0.413%BW/주·적자 12.9%TDEE, a=0.90→0.825%BW/주·적자 25.3%TDEE. Helms/Aragon/Fitschen 2014(JISSN 11:20)의 0.5~1.0%BW/주 권장 구간을 엔진이 표현 가능한 범위로 자른 것. 단백질 2.2~2.8 g/kg FFM: Helms·Zinn 2014(IJSNEM 24:127) 2.3~3.1 g/kg LBM의 하단(엔진 CUT_RANGE proteinPerFFM 상한이 2.8이라 잘림 — 엔진 상수를 3.1까지 올릴 것을 권고). 20주 상한: 자연 선수 시합준비 20~30주에서 내분비 이상이 문서화된다는 점 + RP의 '컷 12주 후 유지' 실무 규칙 사이의 절충 — 내 판단이며 직접 인용 아님. 볼륨 주장: Roth et al. 2023(Scand J Med Sci Sports) 제목 수준 확인."
    },
    {
      id: "cutting",
      nameKo: "커팅모드",
      aliasKo: "컷팅 / 시즌 / 바디프로필 준비 / 데피니션",
      nameEn: "Physique Cut",
      oneLiner: "이미 있는 근육을 드러내는 단계. 감량과 같은 방향이지만, '근육을 1g도 안 잃는다'를 조건으로 겁니다.",
      whoFor: "체지방률 남 18% 이하 / 여 26% 이하이면서 운동경력 6개월 이상, 지킬 근육 기반이 이미 있는 사람. 나무위키 「커팅」 정의 그대로 — '근 손실을 최소화하며 지방을 걷어내는 행위'.",
      notFor: "체지방률이 게이트 위인 사람 — 그건 커팅이 아니라 감량입니다. 운동경력 6개월 미만(지킬 근육이 아직 없음). 19세 미만. 목표 체지방률이 남 8% / 여 15% 아래인 사람.",
      direction: "deficit",
      aMin: 0.4, aMax: 0.75,
      strategy: "simultaneous",
      proteinPerFfmMin: 2.4, proteinPerFfmMax: 3.1,
      typicalWeeksMin: 8, typicalWeeksMax: 16,
      maxContinuousWeeks: 16,
      trainingPolicyKo: "웨이트는 중량을 지키는 것이 최우선 — 복합운동은 1RM 80% 이상을 유지하고 세트 수만 조절합니다. '가볍게 여러 번'으로 바꾸지 않습니다. 유산소는 마지막 수단으로 점증. 촬영 전 마지막 주의 수분조절·단수·나트륨 조작은 이 앱이 계획하지 않습니다(저나트륨혈증 위험, 감독 없이 할 일 아님).",
      expectedKo: "주 0.45~0.71%BW 감소. 근육은 유지가 정답이고, 숙련자일수록 '유지'조차 성공입니다. 엔진 기준 적자가 15%TDEE를 넘는 순간(a>0.444) advanced/elite의 근성장 배율은 0.00입니다 — 커팅 중 근육이 는다는 약속은 하지 않습니다.",
      risksKo: "감량모드보다 a 상한을 낮게 잡은 이유는 마를수록 p-ratio가 불리해지기 때문입니다(ISSN position stand: 체지방 기저치가 높을수록 적자를 공격적으로 부과 가능, 마른 대상은 반대). 16주를 넘기면 테스토스테론·수면·기분 저하가 문서화된 구간으로 들어갑니다. 그리고 커팅 종료 직후 4~6주는 체지방이 우선적으로 재축적되는 구간입니다 — 계획 없이 끝내면 요요는 사고가 아니라 예정된 결과입니다.",
      exitCriteriaKo: "목표 체지방률 도달 또는 16주 경과 — 둘 중 먼저 오는 쪽에서 무조건 종료하고 회복모드로 강제 전이합니다. 커팅은 끝이 아니라 반환점입니다.",
      evidence: "a범위: 엔진 CUT_RANGE 역산 — a=0.40→0.450%BW/주·적자 14.0%, a=0.75→0.712%BW/주·적자 21.9%. Garthe et al. 2011(IJSNEM 21:97)이 검증한 0.7%BW/주가 a=0.733으로 범위 안에 들어옵니다. 단백질 2.4~3.1: Helms·Zinn 2014의 상단, '적자 깊이와 마른 정도에 비례해 올린다'는 원문 권고 그대로(※엔진 CUT_RANGE 상한 2.8을 3.1로 올려야 구현 가능). 진입 체지방률 남 18/여 26: 한국 린매스업·커팅 실사용 밴드(얼루어 코리아 남 13~18%, 뷰티쁠) 채택 — Helms/3DMJ의 남 10~15%보다 관대한 쪽을 고른 것은 오너가 한국 사용자이기 때문이며, 이건 내 선택임을 밝힙니다. 16주 상한 + 회복기 강제: 시합준비 20~30주 내분비 이상 문헌에서 역산한 내 판단."
    },
    {
      id: "recomp",
      nameKo: "리컴프 (상승다이어트)",
      aliasKo: "동시개선 / 바디 리컴포지션 / 상승 다이어트",
      nameEn: "Body Recomposition",
      oneLiner: "체중은 거의 그대로 두고 근육은 올리고 지방은 내리는 모드. 느리지만, 지금의 오너에게 가장 잘 맞습니다.",
      whoFor: "Barakat 2020이 지목한 세 집단 — ① 운동 입문자 ② 쉬었다 복귀한 사람(머슬메모리) ③ 체지방이 있는데 웨이트를 안 해본 사람. 마른비만도 여기입니다.",
      notFor: "숙련자(3년+)이면서 이미 마른 사람 — 예상 월간 SMM 변화가 인바디 측정 오차보다 작아서 '틀린 게 아니라 측정이 안 됩니다'. 그리고 급한 사람. 리컴프는 중급자의 증량 대비 근성장 속도를 70~80% 깎는 거래입니다.",
      direction: "mixed",
      aMin: 0.05, aMax: 0.44,
      strategy: "auto",
      proteinPerFfmMin: 2.4, proteinPerFfmMax: 2.8,
      typicalWeeksMin: 16, typicalWeeksMax: 32,
      maxContinuousWeeks: null,
      trainingPolicyKo: "이 모드에서 훈련은 옵션이 아니라 전제입니다. Barakat 2020이 리컴프 성립 조건으로 꼽은 두 가지가 '진짜 점진적 과부하'와 '고단백'입니다. 근육군당 주 12~20세트, 주 4회, 매주 중량 또는 반복수가 올라가야 합니다. 유산소는 주 90~150분으로 제한 — 유산소를 늘려서 적자를 만들면 이 모드의 보호 구간이 깨집니다.",
      expectedKo: "3~6개월에 근육 +0.5~1.5kg, 지방 −3~6kg, 체중은 거의 제자리. 진행 차트는 '선'이 아니라 '밴드'로 봐야 합니다 — 체중이 안 변하는 게 성공인 모드에서 목표선은 실패처럼 보입니다. 그리고 운동 시작 8주 안의 SMM 증가는 절반쯤 글리코겐·부종입니다(Damas 2016).",
      risksKo: "가장 큰 위험은 '안 되는 게 아니라 안 보이는 것'입니다. 인바디 SMM의 실사용 노이즈가 ±0.6kg인데 리컴프 월간 기대치가 0.1~0.3kg입니다. 그래서 최소 16주, 측정 간격 최소 4주가 아니면 판정 자체를 하면 안 됩니다. 또 하나 — a를 0.44 위로 올리면 적자가 15%TDEE를 넘어 엔진의 근성장 배율이 무너지고, 리컴프는 그냥 감량이 됩니다. 이 모드의 a 상한은 장식이 아니라 잠금장치입니다.",
      exitCriteriaKo: "① 목표 도달 ② 8주 연속 SMM·BFM 둘 다 노이즈 바닥 안에서 무변화 → 근성장모드 또는 감량모드로 전환 제안 ③ 체지방률이 남 13% / 여 21% 아래로 내려가 더 뺄 지방이 없어짐 → 근성장모드.",
      evidence: "a상한 0.44가 이 모드의 핵심 숫자이고 완전히 추적 가능합니다: 엔진 CUT_RANGE deficitPct를 역산하면 적자 15%TDEE = a 0.444이고, 엔진 MUSCLE_SITUATION이 recomp(novice 0.70 / intermediate 0.35) 배율을 주는 경계가 정확히 '적자 ≤15%'입니다. 즉 a=0.44는 문헌이 아니라 엔진 자신의 보호 구간 경계입니다. a하한 0.05 = 적자 6.1%TDEE(사실상 유지 근처). 세 집단: Barakat et al. 2020(Strength Cond J 42:5). 단백질 2.4~2.8: Longland 2016(AJCN) 고단백군 2.4 g/kg BW + Barakat의 '>2.0 g/kg' 조건. 흔히 도는 '−100~200 kcal/day' 수치는 Barakat 원문에서 확인되지 않아 하드코딩하지 않고 a로만 표현했습니다. 70~80% 속도 손실은 코칭 합의 수준(중급 증량 0.45~0.7kg/월 vs 리컴프 0.1~0.2kg/월)."
    },
    {
      id: "muscleGain",
      nameKo: "근성장모드 (린매스업)",
      aliasKo: "린매스업 / 벌크업 / 클린벌크 / 증량기",
      nameEn: "Muscle-Gain Phase",
      oneLiner: "근육을 늘리는 단계. a를 낮추면 린매스업, 올리면 벌크업 — 이름만 다른 게 아니라 붙는 지방의 양이 다릅니다.",
      whoFor: "체지방률이 남 18% / 여 26% 이하이고 근육이 병목인 사람. BMI 20 미만이거나 하드게이너면 a를 높게(벌크업) 써도 됩니다.",
      notFor: "체지방률이 게이트 위인 사람 — 지금 증량하면 지방만 붙습니다(속칭 살크업). 그리고 '빨리 많이 먹으면 근육이 빨리 붙는다'고 믿는 사람 — 근성장 상한은 훈련연령이 정하고, 잉여를 키운다고 그 상한이 올라가지 않습니다.",
      direction: "surplus",
      aMin: 0.2, aMax: 0.75,
      strategy: "auto",
      proteinPerFfmMin: 1.9, proteinPerFfmMax: 2.4,
      typicalWeeksMin: 12, typicalWeeksMax: 24,
      maxContinuousWeeks: 32,
      trainingPolicyKo: "근육군당 주 12~22세트, 주 4~6회, 4~10주마다 디로드. 훈련이 계획대로 진행되지 않으면 잉여는 근섬유가 아니라 지방세포로 갑니다. 유산소는 주 75~90분 정도로 최소만 유지(간섭효과 회피 + 심폐 유지).",
      expectedKo: "주 +0.25~0.50%BW 증가가 문헌 권장치인데, 엔진의 생리적 상한(입문 1.25 / 중급 0.75 / 숙련 0.375 %BW/월 FFM)에 걸리면 실제로는 그보다 느리게 나옵니다. 한국 린매스업 콘텐츠가 말하는 '월 1kg'은 입문자 아니면 안 나오는 숫자입니다. 앱이 그 기사보다 느린 숫자를 줘도 고장난 게 아닙니다.",
      risksKo: "a=0.20이면 늘어난 체중의 68%가 제지방, a=0.75면 49%입니다(엔진 leanFraction). 즉 공격적으로 갈수록 '증량 1kg당 지방 0.5kg'에 가까워집니다. 그래서 a 상한을 1.0이 아니라 0.75로 잘랐습니다 — a=1.0의 leanFraction 0.40은 한국 헬스 커뮤니티가 더티벌크/살크업이라 부르는 구간입니다. 숙련·엘리트는 a≤0.45로 추가 클램프(Iraki가 '고급자는 더 보수적으로'라고 명시).",
      exitCriteriaKo: "① 목표 골격근량 도달 ② 체지방률이 남 18% / 여 26% 도달 → 단기커팅 삽입 제안 ③ 32주 경과 → 유지모드 또는 감량모드로 재평가. 4주간 체중 +1.5% 이상인데 SMM 증가가 노이즈 바닥 이하면 '살크업' 경고를 띄우고 잉여를 하루 200kcal 낮춥니다.",
      evidence: "a범위: 엔진 BULK_RANGE 역산 — a=0.20→잉여 6.7%TDEE·leanFraction 0.68, a=0.75→잉여 14.1%·leanFraction 0.49. Iraki·Fitschen·Espinar·Helms 2019(Sports 7:154)의 10~20% 잉여 중 하단~중단(잉여 10% = a 0.444). 한국 린매스업 관행 +200~300kcal는 TDEE 2800 기준 7~11% = a 0.22~0.52로 이 범위 안에 정확히 들어옵니다. 단백질 1.9~2.4 g/kg FFM: Iraki의 1.6~2.2 g/kg BW를 체지방률 20% 기준 FFM으로 환산(÷0.80)한 값. ★벌크업을 별도 모드로 만들지 않은 이유: 문헌상 공격적 증량이 우월하다는 근거가 사실상 없고(엔진에서도 근성장 상한은 훈련연령만 봄), 린매스업과 벌크업의 차이가 a 하나로 완전히 표현되기 때문입니다. '별개 라벨'이지 '별개 계획'이 아닙니다. 진입 체지방률로 p-ratio 보너스를 주지 않는 것도 의도적 — Nuckols/Trexler vs Henselmans 논쟁이 진행 중이고 Henselmans 본인이 입장을 철회했습니다."
    },
    {
      id: "maintain",
      nameKo: "유지모드",
      aliasKo: "유지어트 / 유지칼로리 / 유지기",
      nameEn: "Maintenance",
      oneLiner: "지금 몸을 지키는 계획. '아무것도 안 하는 것'이 아니라 처방된 국면입니다.",
      whoFor: "목표 변화량이 인바디 측정 오차 안쪽인 사람, 감량이나 증량을 막 끝낸 사람, 목표를 달성한 사람. 그리고 지금 당장은 몸을 바꿀 때가 아닌 모든 사람.",
      notFor: "없습니다. 이 모드는 거의 모든 상태에서 안전하고, 그래서 다른 모드가 거부될 때 돌아오는 종착지입니다.",
      direction: "maintenance",
      aMin: 0, aMax: 0.08,
      strategy: "simultaneous",
      proteinPerFfmMin: 1.6, proteinPerFfmMax: 2,
      typicalWeeksMin: 4, typicalWeeksMax: 12,
      maxContinuousWeeks: null,
      trainingPolicyKo: "웨이트 주 3회, 근육군당 주 8~12세트. 근육을 '늘리는' 볼륨이 아니라 '지키는' 최소 볼륨입니다. 유산소 주 90~120분. 유지기의 목적은 훈련 수행력, 수면, 호르몬, 그리고 식사에 대한 심리적 여유를 회복하는 것입니다.",
      expectedKo: "체중은 목표 주변 ±1kg 밴드 안에서 움직입니다. 그래프는 목표선이 아니라 밴드로 그려야 합니다. 직전 국면이 감량이었다면 첫 1~2주에 글리코겐·수분으로 +0.5~1.5kg이 올라옵니다 — 지방이 아닙니다.",
      risksKo: "거의 없습니다. 유일한 위험은 오너가 '아무것도 안 하고 있다'고 느껴서 성급하게 다음 국면으로 넘어가는 것입니다. 감량 직후의 유지기는 다음 감량을 더 높은 섭취량에서 시작하게 해주는 투자입니다.",
      exitCriteriaKo: "직전 감량기 길이의 절반~동일 기간이 지나면 다음 국면 선택 프롬프트. 또는 사용자가 새 목표를 입력할 때. 12주 경과 시 재평가.",
      evidence: "a범위 0~0.08은 엔진의 한계를 드러내는 숫자입니다: 엔진 CUT_RANGE deficitPct 하한이 0.050이라 a=0에서도 적자 5%TDEE가 걸리고, 진짜 에너지 균형(0%)을 표현할 수 없습니다. ★엔진 수정 권고 — 유지모드용으로 deficitPct 범위를 [−0.02, +0.05]로 확장해야 합니다. 기간 4~12주 및 '직전 감량의 절반~2배' 규칙: RP Strength·3DMJ 코칭 합의 수준이고 RCT 근거는 약합니다. 단백질 1.6~2.0 g/kg FFM: Iraki 2019 증량기 권장치 유지. ★오너가 요청한 네 개에는 이 모드가 없었는데, 조사한 진지한 앱(MacroFactor·RP·Carbon·Noom) 전부가 가지고 있고, 엔진의 split 전략이 이미 '유지 2주'를 내부에서 쓰고 있습니다."
    },
    {
      id: "recovery",
      nameKo: "회복모드",
      aliasKo: "리버스 다이어트 / 회복식 / 다이어트 탈출",
      nameEn: "Recovery Diet",
      oneLiner: "감량을 끝내고 정상 섭취로 안전하게 돌아가는 단계. 대사를 '고치는' 게 아니라 되돌아오는 구간을 통제하는 겁니다.",
      whoFor: "커팅을 막 끝낸 사람(강제 진입), 12주 이상 감량한 사람, 바디프로필 촬영이 끝난 사람. 최근 8주 이상에 걸쳐 체중이 6% 이상 빠진 사람.",
      notFor: "감량을 더 해야 하는 사람. 그리고 '더 먹으면서 더 빠진다'를 기대하는 사람 — 그런 일은 일어나지 않습니다.",
      direction: "surplus",
      aMin: 0, aMax: 0.25,
      strategy: "simultaneous",
      proteinPerFfmMin: 2, proteinPerFfmMax: 2.4,
      typicalWeeksMin: 4, typicalWeeksMax: 8,
      maxContinuousWeeks: 12,
      trainingPolicyKo: "웨이트 볼륨을 점진 복구하고 유산소는 줄입니다. 감량기에 깎아둔 세트 수를 먼저 되돌리는 것이 칼로리를 올리는 것보다 우선입니다. 성공 지표를 체중으로 두지 않습니다 — 수면의 질, 폭식 충동, 훈련 수행력, (여성) 생리주기 복귀로 봅니다.",
      expectedKo: "주 +100kcal(1~4주차) → +150kcal(5주차~)로 올려 유지칼로리에 복귀. 체중은 월 0.5~1.5%BW 정도 올라올 수 있고 그중 상당량이 글리코겐·수분입니다. 기간은 max(4주, 직전 감량 주수의 절반)을 4~12주로 클램프.",
      risksKo: "정직하게 말하면 — 이 모드의 근거는 얇습니다. '리버스 다이어트가 대사를 부스팅한다'는 주장을 지지하는 증거는 없고, 2025년 첫 RCT(JISSN 22 sup2)에서 확인된 신호는 오히려 '초반 배고픔이 더 심하다'였습니다. 이 모드가 하는 일은 대사 수리가 아니라 ① 폭식 없이 복귀 ② 지방이 우선 재축적되는 4~6주를 통제 ③ 호르몬·수면·수행력 회복, 이 셋입니다. UI에 '대사 회복' 같은 말을 쓰면 안 됩니다.",
      exitCriteriaKo: "유지칼로리 도달 또는 12주 경과 → 유지모드로 자동 전이. 폭식 삽화가 반복되면 즉시 유지모드로 넘기고 상담 안내를 띄웁니다.",
      evidence: "주 +100/+150 kcal 프로토콜: ClinicalTrials NCT03434431 프로토콜 요약(단일 출처). 기간 공식 clamp(max(4, 0.5×감량주수), 4, 12): 실무 합의를 내가 공식화한 것이며 직접 인용 아님. '대사 부스팅 근거 없음': MacroFactor 'Reverse Dieting: Hype Versus Evidence', Cleveland Clinic 2024, 그리고 Trexler 2014 본인의 '대사는 망가지지 않는다' 결론. 시합 후 RMR 92%→105%→4~6주 정상화 및 지방 우선 재축적: 자연 선수 회복 문헌. ★이 모드를 넣은 이유 — Carbon Diet Coach가 실제로 만든 '네 번째 모드'가 커팅이 아니라 reverse diet였습니다. 오너의 네 개짜리 안에는 '다이어트에서 빠져나오는 길'이 없고, 그게 가장 큰 구멍입니다. 이름은 '리버스 다이어트' 대신 '회복모드'를 씁니다 — 전자는 근거보다 마케팅에 가깝습니다."
    },
    {
      id: "miniCut",
      nameKo: "단기커팅",
      aliasKo: "미니컷 / 단기 감량 / 마감 커팅",
      nameEn: "Mini-Cut",
      oneLiner: "증량 중간에 끼워 넣는 3~5주짜리 짧고 강한 감량. 단독으로 고르는 모드가 아닙니다.",
      whoFor: "증량 중 체지방률이 상한에 닿은 사람, 마감(촬영·시합·행사)이 6주 안인 사람. 운동경력 6개월 이상, 체지방률 남 13% / 여 21% 이상, 19세 이상일 때만 열립니다.",
      notFor: "증량 이력 없이 이 모드부터 시작하려는 사람 — 미니컷은 '진행 중인 증량에 대해서만' 의미가 있습니다. 그리고 감량할 양이 체중의 4%를 넘는 사람(그건 감량모드입니다).",
      direction: "deficit",
      aMin: 0.85, aMax: 1,
      strategy: "simultaneous",
      proteinPerFfmMin: 2.6, proteinPerFfmMax: 3.1,
      typicalWeeksMin: 3, typicalWeeksMax: 5,
      maxContinuousWeeks: 6,
      trainingPolicyKo: "증량기 볼륨을 그대로 끌고 가지 않습니다 — 근육군당 주 8~12세트의 유지 볼륨까지 낮추고, 중량만 지킵니다. 회복 자원이 없는 구간에서 볼륨을 유지하면 수행력이 먼저 무너집니다. 유산소는 최소.",
      expectedKo: "3~5주에 체중 −2~4%. 엔진 상한상 주 0.79~0.90%BW가 최대이고, 체지방량이 적으면 지방동원 상한(31×BFM kcal/day)이 먼저 걸려 그보다 느려집니다. 그게 맞는 동작입니다.",
      risksKo: "앱 전체에서 가장 공격적인 모드입니다. 6주 하드캡을 넘기면 안 되고, 감량 주수 : 증량 주수 = 1 : 4 비율을 지켜야 합니다(4주 미니컷 뒤에는 최소 16주의 증량/유지). 종료 후 즉시 증량 재개 — 기간이 짧아서 회복모드는 불필요합니다. 마감 때문에 이 모드가 선택됐다면, 앱의 가장 중요한 역할은 '그 날짜엔 산술적으로 불가능합니다'라고 말해주는 것입니다.",
      exitCriteriaKo: "3~5주 경과(하드캡 6주) 또는 체지방률 하한(남 11% / 여 19%) 도달 → 직전 증량 모드로 자동 복귀. 마감 기반 진입이었다면 마감일 다음날부터 회복모드/유지모드가 캘린더에 이미 찍혀 있어야 합니다.",
      evidence: "a범위: 엔진 CUT_RANGE 역산 — a=0.85→0.787%BW/주·적자 24.1%, a=1.00→0.900%BW/주·적자 27.5%. 미니컷 코칭 합의치(적자 25~30%, 주 1.0~1.25%BW)와 적자는 일치하고 속도는 엔진 상한 0.90%/주에 막혀 더 보수적으로 나옵니다 — 그대로 두는 게 맞습니다. 기간 3~5주·하드캡 6주, 1:4 비율: RP Strength / Legion 계열 실무 합의이며 RCT는 없습니다(미니컷 단독 임상시험을 찾지 못했습니다). 단백질 2.6~3.1: Helms·Zinn 2014 상단(적자가 깊을수록 올린다) — ★엔진 CUT_RANGE proteinPerFFM 상한 2.8을 3.1로 올려야 구현됩니다. ★한국어 이름: 조사 결과 '미니컷'은 한국 헬스장 용어가 아니고(검색 시 성형외과 페이지가 나옴) 실제로 쓰이는 말은 '단기 커팅'입니다(몬스터짐 스레드 제목 「단기 커팅중인데 잠깐 봐주시겠어요?」). 그래서 주 이름을 단기커팅으로, 미니컷은 별칭으로 뒀습니다."
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
        var sex = i.sex;
        var age = i.age;
        var trainingAge = i.trainingAge;
        var hadPriorPeak = i.hadPriorPeak;
        var deadlineWeeks = i.deadlineWeeks;
        var recentTrend = i.recentTrend;
        var targetPbfPct = i.targetPbfPct;
        return (curBmi < 18.5 || ((curWeightKg + dWeightKg) / curWeightKg) * curBmi < 18.5);
      },
      message: "현재 또는 목표 BMI가 18.5 미만(저체중)입니다. 이 앱은 저체중에서 더 빼는 계획을 만들지 않습니다. 목표를 다시 입력하시거나, 체중을 늘리는 방향으로 바꿔 주세요."
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
        var sex = i.sex;
        var age = i.age;
        var trainingAge = i.trainingAge;
        var hadPriorPeak = i.hadPriorPeak;
        var deadlineWeeks = i.deadlineWeeks;
        var recentTrend = i.recentTrend;
        var targetPbfPct = i.targetPbfPct;
        return (((curBfmKg + dBfmKg) / (curWeightKg + dWeightKg)) * 100 < (sex === 'male' ? 8 : 15));
      },
      message: "목표 체지방률이 {targetPbf}%입니다. 필수 체지방(남 2~5% / 여 10~13%)에 너무 가까워서 계획을 만들지 않습니다. 남성은 10%, 여성은 18% 이상으로 다시 잡아 주세요. 그 아래는 감독 없이 할 일이 아닙니다."
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
        var sex = i.sex;
        var age = i.age;
        var trainingAge = i.trainingAge;
        var hadPriorPeak = i.hadPriorPeak;
        var deadlineWeeks = i.deadlineWeeks;
        var recentTrend = i.recentTrend;
        var targetPbfPct = i.targetPbfPct;
        return (dBfmKg > NOISE.bfm && dSmmKg < -NOISE.smm);
      },
      message: "체지방은 늘리고 근육은 줄이는 목표입니다. 이건 계획이 아니라 방치의 결과라서, 앱이 만들어 드릴 수 있는 게 없습니다. 목표 숫자를 잘못 입력하신 건 아닌지 확인해 주세요."
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
        var sex = i.sex;
        var age = i.age;
        var trainingAge = i.trainingAge;
        var hadPriorPeak = i.hadPriorPeak;
        var deadlineWeeks = i.deadlineWeeks;
        var recentTrend = i.recentTrend;
        var targetPbfPct = i.targetPbfPct;
        return (deadlineWeeks !== null && deadlineWeeks > 0 && (Math.abs(dWeightKg) / curWeightKg) / deadlineWeeks > 0.0125);
      },
      message: "{deadlineWeeks}주 안에 체중 {dWeightKg}kg 변화는 주당 {ratePct}%입니다. 안전하게 가능한 상한(주 1.25%)을 넘습니다. 기간을 늘리거나 목표를 줄여 주세요. 지금 이 숫자는 몸이 아니라 물과 근육이 빠지는 속도입니다."
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
        var sex = i.sex;
        var age = i.age;
        var trainingAge = i.trainingAge;
        var hadPriorPeak = i.hadPriorPeak;
        var deadlineWeeks = i.deadlineWeeks;
        var recentTrend = i.recentTrend;
        var targetPbfPct = i.targetPbfPct;
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
        var sex = i.sex;
        var age = i.age;
        var trainingAge = i.trainingAge;
        var hadPriorPeak = i.hadPriorPeak;
        var deadlineWeeks = i.deadlineWeeks;
        var recentTrend = i.recentTrend;
        var targetPbfPct = i.targetPbfPct;
        return (Math.abs(dWeightKg - (dBfmKg + 1.75 * dSmmKg)) > 2.5);
      },
      message: "입력하신 세 숫자가 서로 맞지 않습니다. 체중 변화 = 체지방 변화 + 제지방 변화인데, 근육 {dSmmKg}kg · 지방 {dBfmKg}kg이면 체중은 약 {impliedWeight}kg 변해야 합니다(입력값 {dWeightKg}kg). 인바디 결과지의 체중조절 = 지방조절 + 근육조절도 같은 항등식입니다. 셋 중 하나를 고쳐 주세요."
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
        var sex = i.sex;
        var age = i.age;
        var trainingAge = i.trainingAge;
        var hadPriorPeak = i.hadPriorPeak;
        var deadlineWeeks = i.deadlineWeeks;
        var recentTrend = i.recentTrend;
        var targetPbfPct = i.targetPbfPct;
        return (deadlineWeeks !== null && deadlineWeeks < 4);
      },
      message: "목표 기간이 4주 미만입니다. 인바디로 확인 가능한 변화가 나오는 최소 단위가 4주라서, 그보다 짧은 계획은 만들어도 진행 여부를 판정할 수 없습니다."
    }
  ];

  /* 순서대로 평가해 처음 맞는 것을 쓴다. 마지막은 반드시 catch-all. */
  var RULES = [
    {
      order: 1,
      modeId: "maintain",
      reason: "입력하신 변화량이 인바디 측정 오차(체중 ±1kg · 근육 ±0.6kg · 지방 ±1kg) 안쪽입니다. 기계가 구분할 수 없는 크기라서, 지금 몸을 지키는 계획을 제안합니다.",
      source: "Math.abs(dWeightKg) < NOISE.weight && Math.abs(dSmmKg) < NOISE.smm && Math.abs(dBfmKg) < NOISE.bfm",
      test: function (i) {
        var dWeightKg = i.dWeightKg;
        var dSmmKg = i.dSmmKg;
        var dBfmKg = i.dBfmKg;
        var curPbfPct = i.curPbfPct;
        var curBmi = i.curBmi;
        var curSmmKg = i.curSmmKg;
        var curBfmKg = i.curBfmKg;
        var curWeightKg = i.curWeightKg;
        var sex = i.sex;
        var age = i.age;
        var trainingAge = i.trainingAge;
        var hadPriorPeak = i.hadPriorPeak;
        var deadlineWeeks = i.deadlineWeeks;
        var recentTrend = i.recentTrend;
        var targetPbfPct = i.targetPbfPct;
        return (Math.abs(dWeightKg) < NOISE.weight && Math.abs(dSmmKg) < NOISE.smm && Math.abs(dBfmKg) < NOISE.bfm);
      }
    },
    {
      order: 2,
      modeId: "recovery",
      reason: "최근 {weeksSpan}주 동안 체중이 {pct}% 빠졌고, 이번 목표에는 추가 감량이 없습니다. 감량을 막 끝낸 상태로 판단해 회복 계획을 먼저 제안합니다. 이 구간은 체지방이 가장 빨리 다시 붙는 4~6주입니다.",
      source: "recentTrend !== null && recentTrend.weeksSpan >= 8 && (recentTrend.dWeightKg / curWeightKg) <= -0.06 && dBfmKg > -NOISE.bfm && dSmmKg < NOISE.smm",
      test: function (i) {
        var dWeightKg = i.dWeightKg;
        var dSmmKg = i.dSmmKg;
        var dBfmKg = i.dBfmKg;
        var curPbfPct = i.curPbfPct;
        var curBmi = i.curBmi;
        var curSmmKg = i.curSmmKg;
        var curBfmKg = i.curBfmKg;
        var curWeightKg = i.curWeightKg;
        var sex = i.sex;
        var age = i.age;
        var trainingAge = i.trainingAge;
        var hadPriorPeak = i.hadPriorPeak;
        var deadlineWeeks = i.deadlineWeeks;
        var recentTrend = i.recentTrend;
        var targetPbfPct = i.targetPbfPct;
        return (recentTrend !== null && recentTrend.weeksSpan >= 8 && (recentTrend.dWeightKg / curWeightKg) <= -0.06 && dBfmKg > -NOISE.bfm && dSmmKg < NOISE.smm);
      }
    },
    {
      order: 3,
      modeId: "miniCut",
      reason: "마감이 {deadlineWeeks}주 남았고, 빼야 할 지방이 체중의 4% 이내입니다. 짧고 강한 단기커팅이 맞는 상황입니다. 다만 6주를 넘기지 않고, 끝난 다음 날부터 복귀 계획이 함께 잡힙니다.",
      source: "dBfmKg < -NOISE.bfm && dSmmKg > -NOISE.smm && dSmmKg < NOISE.smm && Math.abs(dBfmKg) <= 0.04 * curWeightKg && deadlineWeeks !== null && deadlineWeeks <= 6 && curPbfPct >= (sex === 'male' ? 13 : 21) && trainingAge !== 'novice' && age >= 19",
      test: function (i) {
        var dWeightKg = i.dWeightKg;
        var dSmmKg = i.dSmmKg;
        var dBfmKg = i.dBfmKg;
        var curPbfPct = i.curPbfPct;
        var curBmi = i.curBmi;
        var curSmmKg = i.curSmmKg;
        var curBfmKg = i.curBfmKg;
        var curWeightKg = i.curWeightKg;
        var sex = i.sex;
        var age = i.age;
        var trainingAge = i.trainingAge;
        var hadPriorPeak = i.hadPriorPeak;
        var deadlineWeeks = i.deadlineWeeks;
        var recentTrend = i.recentTrend;
        var targetPbfPct = i.targetPbfPct;
        return (dBfmKg < -NOISE.bfm && dSmmKg > -NOISE.smm && dSmmKg < NOISE.smm && Math.abs(dBfmKg) <= 0.04 * curWeightKg && deadlineWeeks !== null && deadlineWeeks <= 6 && curPbfPct >= (sex === 'male' ? 13 : 21) && trainingAge !== 'novice' && age >= 19);
      }
    },
    {
      order: 4,
      modeId: "cutting",
      reason: "체지방률 {curPbfPct}%에 운동경력이 이미 쌓였고, 근육은 그대로 두고 지방만 걷어내는 목표입니다. 이게 헬스장에서 말하는 '커팅'입니다. 감량모드보다 속도 상한을 낮게 잡고 단백질을 더 올립니다.",
      source: "dBfmKg < -NOISE.bfm && dSmmKg > -NOISE.smm && dSmmKg < NOISE.smm && curPbfPct <= (sex === 'male' ? 18 : 26) && trainingAge !== 'novice' && age >= 19",
      test: function (i) {
        var dWeightKg = i.dWeightKg;
        var dSmmKg = i.dSmmKg;
        var dBfmKg = i.dBfmKg;
        var curPbfPct = i.curPbfPct;
        var curBmi = i.curBmi;
        var curSmmKg = i.curSmmKg;
        var curBfmKg = i.curBfmKg;
        var curWeightKg = i.curWeightKg;
        var sex = i.sex;
        var age = i.age;
        var trainingAge = i.trainingAge;
        var hadPriorPeak = i.hadPriorPeak;
        var deadlineWeeks = i.deadlineWeeks;
        var recentTrend = i.recentTrend;
        var targetPbfPct = i.targetPbfPct;
        return (dBfmKg < -NOISE.bfm && dSmmKg > -NOISE.smm && dSmmKg < NOISE.smm && curPbfPct <= (sex === 'male' ? 18 : 26) && trainingAge !== 'novice' && age >= 19);
      }
    },
    {
      order: 5,
      modeId: "recomp",
      reason: "지방은 빼고 근육은 늘리는 목표인데, {reason}이라서 동시에 진행하는 게 실제로 가능한 구간입니다. 대신 적자를 TDEE의 15% 아래로 묶습니다 — 그 선을 넘는 순간 근육 증가율이 무너지기 때문입니다.",
      source: "dBfmKg < -NOISE.bfm && dSmmKg > NOISE.smm && curPbfPct >= (sex === 'male' ? 13 : 21) && (hadPriorPeak === true || trainingAge === 'novice' || trainingAge === 'intermediate')",
      test: function (i) {
        var dWeightKg = i.dWeightKg;
        var dSmmKg = i.dSmmKg;
        var dBfmKg = i.dBfmKg;
        var curPbfPct = i.curPbfPct;
        var curBmi = i.curBmi;
        var curSmmKg = i.curSmmKg;
        var curBfmKg = i.curBfmKg;
        var curWeightKg = i.curWeightKg;
        var sex = i.sex;
        var age = i.age;
        var trainingAge = i.trainingAge;
        var hadPriorPeak = i.hadPriorPeak;
        var deadlineWeeks = i.deadlineWeeks;
        var recentTrend = i.recentTrend;
        var targetPbfPct = i.targetPbfPct;
        return (dBfmKg < -NOISE.bfm && dSmmKg > NOISE.smm && curPbfPct >= (sex === 'male' ? 13 : 21) && (hadPriorPeak === true || trainingAge === 'novice' || trainingAge === 'intermediate'));
      }
    },
    {
      order: 6,
      modeId: "muscleGain",
      reason: "지방도 빼고 근육도 늘리고 싶으시지만, 훈련경력과 체지방률로 보면 동시 진행은 인바디로 측정도 안 될 만큼 느립니다. 그리고 근육 목표(제지방 환산 {ffmKg}kg)가 지방 목표({fatKg}kg)보다 큽니다. 근성장을 먼저 두고, 엔진이 '증량 → 단기커팅' 순서와 동시 진행 중 빠른 쪽을 골라줍니다.",
      source: "dBfmKg < -NOISE.bfm && dSmmKg > NOISE.smm && 1.75 * dSmmKg > Math.abs(dBfmKg)",
      test: function (i) {
        var dWeightKg = i.dWeightKg;
        var dSmmKg = i.dSmmKg;
        var dBfmKg = i.dBfmKg;
        var curPbfPct = i.curPbfPct;
        var curBmi = i.curBmi;
        var curSmmKg = i.curSmmKg;
        var curBfmKg = i.curBfmKg;
        var curWeightKg = i.curWeightKg;
        var sex = i.sex;
        var age = i.age;
        var trainingAge = i.trainingAge;
        var hadPriorPeak = i.hadPriorPeak;
        var deadlineWeeks = i.deadlineWeeks;
        var recentTrend = i.recentTrend;
        var targetPbfPct = i.targetPbfPct;
        return (dBfmKg < -NOISE.bfm && dSmmKg > NOISE.smm && 1.75 * dSmmKg > Math.abs(dBfmKg));
      }
    },
    {
      order: 7,
      modeId: "fatLoss",
      reason: "지방도 빼고 근육도 늘리고 싶으시지만, 동시 진행이 성립하는 구간(입문/복귀/체지방 여유)에서 벗어나 있고 지방 목표가 더 큽니다. 감량을 먼저 두고, 엔진이 '감량 → 유지 2주 → 증량' 분할과 동시 진행 중 빠른 쪽을 골라줍니다.",
      source: "dBfmKg < -NOISE.bfm && dSmmKg > NOISE.smm",
      test: function (i) {
        var dWeightKg = i.dWeightKg;
        var dSmmKg = i.dSmmKg;
        var dBfmKg = i.dBfmKg;
        var curPbfPct = i.curPbfPct;
        var curBmi = i.curBmi;
        var curSmmKg = i.curSmmKg;
        var curBfmKg = i.curBfmKg;
        var curWeightKg = i.curWeightKg;
        var sex = i.sex;
        var age = i.age;
        var trainingAge = i.trainingAge;
        var hadPriorPeak = i.hadPriorPeak;
        var deadlineWeeks = i.deadlineWeeks;
        var recentTrend = i.recentTrend;
        var targetPbfPct = i.targetPbfPct;
        return (dBfmKg < -NOISE.bfm && dSmmKg > NOISE.smm);
      }
    },
    {
      order: 8,
      modeId: "muscleGain",
      reason: "근육을 늘리는 게 목표이고 체지방률 {curPbfPct}%는 증량을 시작해도 되는 구간입니다. a를 낮추면 린매스업, 올리면 벌크업 — 붙는 지방의 양이 달라집니다.",
      source: "dSmmKg > NOISE.smm && dBfmKg >= -NOISE.bfm && curPbfPct <= (sex === 'male' ? 18 : 26)",
      test: function (i) {
        var dWeightKg = i.dWeightKg;
        var dSmmKg = i.dSmmKg;
        var dBfmKg = i.dBfmKg;
        var curPbfPct = i.curPbfPct;
        var curBmi = i.curBmi;
        var curSmmKg = i.curSmmKg;
        var curBfmKg = i.curBfmKg;
        var curWeightKg = i.curWeightKg;
        var sex = i.sex;
        var age = i.age;
        var trainingAge = i.trainingAge;
        var hadPriorPeak = i.hadPriorPeak;
        var deadlineWeeks = i.deadlineWeeks;
        var recentTrend = i.recentTrend;
        var targetPbfPct = i.targetPbfPct;
        return (dSmmKg > NOISE.smm && dBfmKg >= -NOISE.bfm && curPbfPct <= (sex === 'male' ? 18 : 26));
      }
    },
    {
      order: 9,
      modeId: "recomp",
      reason: "근육을 늘리는 게 목표지만 체지방률 {curPbfPct}%에서 바로 증량하면 지방이 먼저 붙습니다(속칭 살크업). 체지방 여유가 있다는 건 리컴프가 잘 먹히는 조건이기도 해서, 지방을 조금 내리면서 근육을 올리는 쪽으로 잡았습니다.",
      source: "dSmmKg > NOISE.smm && dBfmKg >= -NOISE.bfm && curPbfPct > (sex === 'male' ? 18 : 26)",
      test: function (i) {
        var dWeightKg = i.dWeightKg;
        var dSmmKg = i.dSmmKg;
        var dBfmKg = i.dBfmKg;
        var curPbfPct = i.curPbfPct;
        var curBmi = i.curBmi;
        var curSmmKg = i.curSmmKg;
        var curBfmKg = i.curBfmKg;
        var curWeightKg = i.curWeightKg;
        var sex = i.sex;
        var age = i.age;
        var trainingAge = i.trainingAge;
        var hadPriorPeak = i.hadPriorPeak;
        var deadlineWeeks = i.deadlineWeeks;
        var recentTrend = i.recentTrend;
        var targetPbfPct = i.targetPbfPct;
        return (dSmmKg > NOISE.smm && dBfmKg >= -NOISE.bfm && curPbfPct > (sex === 'male' ? 18 : 26));
      }
    },
    {
      order: 10,
      modeId: "muscleGain",
      reason: "BMI {curBmi}로 저체중 구간이고 체중을 늘리는 목표입니다. 지방만 늘리는 계획은 만들지 않으므로, 늘어나는 체중의 절반 이상이 제지방이 되도록 근성장 계획으로 잡았습니다.",
      source: "dWeightKg > NOISE.weight && dSmmKg <= NOISE.smm && curBmi < 20",
      test: function (i) {
        var dWeightKg = i.dWeightKg;
        var dSmmKg = i.dSmmKg;
        var dBfmKg = i.dBfmKg;
        var curPbfPct = i.curPbfPct;
        var curBmi = i.curBmi;
        var curSmmKg = i.curSmmKg;
        var curBfmKg = i.curBfmKg;
        var curWeightKg = i.curWeightKg;
        var sex = i.sex;
        var age = i.age;
        var trainingAge = i.trainingAge;
        var hadPriorPeak = i.hadPriorPeak;
        var deadlineWeeks = i.deadlineWeeks;
        var recentTrend = i.recentTrend;
        var targetPbfPct = i.targetPbfPct;
        return (dWeightKg > NOISE.weight && dSmmKg <= NOISE.smm && curBmi < 20);
      }
    },
    {
      order: 11,
      modeId: "maintain",
      reason: "체지방만 늘리는 목표는 이 앱이 계획하지 않습니다. 입력값이 잘못됐는지 먼저 확인해 주세요. 그동안은 지금 몸을 유지하는 계획을 보여드립니다.",
      source: "dBfmKg > NOISE.bfm && dSmmKg < NOISE.smm",
      test: function (i) {
        var dWeightKg = i.dWeightKg;
        var dSmmKg = i.dSmmKg;
        var dBfmKg = i.dBfmKg;
        var curPbfPct = i.curPbfPct;
        var curBmi = i.curBmi;
        var curSmmKg = i.curSmmKg;
        var curBfmKg = i.curBfmKg;
        var curWeightKg = i.curWeightKg;
        var sex = i.sex;
        var age = i.age;
        var trainingAge = i.trainingAge;
        var hadPriorPeak = i.hadPriorPeak;
        var deadlineWeeks = i.deadlineWeeks;
        var recentTrend = i.recentTrend;
        var targetPbfPct = i.targetPbfPct;
        return (dBfmKg > NOISE.bfm && dSmmKg < NOISE.smm);
      }
    },
    {
      order: 12,
      modeId: "fatLoss",
      reason: "지방과 근육을 함께 줄이는 목표입니다. 근육 감소는 목표가 아니라 비용이라는 점만 알아두세요 — 계획은 근손실을 최소화하는 쪽으로 잡았고, 근육이 예상보다 빨리 빠지면 강도를 자동으로 낮춥니다.",
      source: "dBfmKg < -NOISE.bfm && dSmmKg <= -NOISE.smm",
      test: function (i) {
        var dWeightKg = i.dWeightKg;
        var dSmmKg = i.dSmmKg;
        var dBfmKg = i.dBfmKg;
        var curPbfPct = i.curPbfPct;
        var curBmi = i.curBmi;
        var curSmmKg = i.curSmmKg;
        var curBfmKg = i.curBfmKg;
        var curWeightKg = i.curWeightKg;
        var sex = i.sex;
        var age = i.age;
        var trainingAge = i.trainingAge;
        var hadPriorPeak = i.hadPriorPeak;
        var deadlineWeeks = i.deadlineWeeks;
        var recentTrend = i.recentTrend;
        var targetPbfPct = i.targetPbfPct;
        return (dBfmKg < -NOISE.bfm && dSmmKg <= -NOISE.smm);
      }
    },
    {
      order: 13,
      modeId: "fatLoss",
      reason: "체지방을 줄이는 게 목표입니다. 체지방률 {curPbfPct}% 또는 운동경력 기준으로 커팅 조건(남 18% 이하 · 경력 6개월 이상)에는 아직 닿지 않아서, 같은 방향이지만 더 넓은 속도 범위를 쓰는 감량으로 잡았습니다.",
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
        var sex = i.sex;
        var age = i.age;
        var trainingAge = i.trainingAge;
        var hadPriorPeak = i.hadPriorPeak;
        var deadlineWeeks = i.deadlineWeeks;
        var recentTrend = i.recentTrend;
        var targetPbfPct = i.targetPbfPct;
        return (dBfmKg < -NOISE.bfm);
      }
    },
    {
      order: 14,
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
        var sex = i.sex;
        var age = i.age;
        var trainingAge = i.trainingAge;
        var hadPriorPeak = i.hadPriorPeak;
        var deadlineWeeks = i.deadlineWeeks;
        var recentTrend = i.recentTrend;
        var targetPbfPct = i.targetPbfPct;
        return (dWeightKg < -NOISE.weight);
      }
    },
    {
      order: 15,
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
        var sex = i.sex;
        var age = i.age;
        var trainingAge = i.trainingAge;
        var hadPriorPeak = i.hadPriorPeak;
        var deadlineWeeks = i.deadlineWeeks;
        var recentTrend = i.recentTrend;
        var targetPbfPct = i.targetPbfPct;
        return (dWeightKg > NOISE.weight && curPbfPct <= (sex === 'male' ? 18 : 26));
      }
    },
    {
      order: 16,
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
        var sex = i.sex;
        var age = i.age;
        var trainingAge = i.trainingAge;
        var hadPriorPeak = i.hadPriorPeak;
        var deadlineWeeks = i.deadlineWeeks;
        var recentTrend = i.recentTrend;
        var targetPbfPct = i.targetPbfPct;
        return (true);
      }
    }
  ];

  var OWNER_VERDICT = "오너는 지금 **리컴프(상승다이어트)를 하고 있고, 그게 맞는 선택입니다.** 다만 실행값이 리컴프가 성립하는 보호 구간을 살짝 벗어나 있고, 인바디가 보여주는 성과의 절반쯤은 물입니다.\n\n**1) 앱이 추천해야 할 모드: 리컴프 (상승다이어트)**\n선택 규칙 5번에 걸립니다 — 지방을 더 빼고 싶고(ΔBFM < −1.0), 근육도 더 늘리고 싶고(ΔSMM > 0.6), 체지방률 23.1%는 남성 리컴프 하한 13%를 훨씬 넘고, 운동 시작이 6월 말이라 novice입니다. Barakat 2020이 말한 \"리컴프가 가장 확실하게 나타나는 세 집단\" 중 ①과 ③에 동시에 들어갑니다. 22세 남성, 시작 PBF 28.4% — 교과서적인 responder입니다.\n\n**커팅모드는 열리지 않습니다.** 체지방률 23.1%가 커팅 게이트(남 18%)보다 위입니다. 오너가 \"커팅모드\"를 직접 누르면 앱은 이렇게 말해야 합니다: *\"지금은 커팅이 아니라 감량입니다. 커팅은 이미 있는 근육을 드러내는 작업이라 18% 아래에서 의미가 생깁니다. 18%에 도달하면 자동으로 열립니다.\"* — 이게 감량/커팅을 두 개로 나눈 실제 가치입니다.\n\n**2) 가장 실행 가치가 큰 조정: 하루 80~100kcal 더 드세요.**\nFFM 66.7kg → BMR 1,811(인바디 인쇄값 1,810과 정확히 일치, Katch-McArdle) → TDEE@PAL1.55 = 2,807kcal. 81일간 지방 5.3kg 감소를 에너지로 환산하면 **하루 504kcal 적자 = TDEE의 18.0%**입니다. 엔진의 보호 경계는 15%(= 421kcal, = a 0.444)입니다. 즉 오너는 리컴프 보호 구간을 **83kcal/day 차이로 벗어나** 달리고 있고, 그 대가로 엔진 기준 근성장 배율이 novice 0.70 → 0.30으로 떨어져 있습니다. 하루 100kcal만 더 먹으면 감량 속도는 거의 그대로인데 근육 증가율이 두 배 이상으로 뜁니다. README §2의 \"강도를 올리면 오히려 느려질 수 있다\"가 실제 오너 데이터에서 그대로 나타난 사례입니다.\n\n**3) \"근육 +1.7kg\"은 절반만 믿으세요 — 앱이 이걸 말해야 합니다.**\n81일간 FFM +3.0kg인데, 엔진 자신의 생리적 상한으로는 novice + 실적자(>15%) 조건에서 최대 +0.87kg입니다. 관측치가 상한의 3.4배 — intermediate로 보면 33배입니다. 즉 **상당 부분이 조직이 아닙니다.** 분해하면: 측정 시각 이동(07:36 → 11:09, 오후일수록 FFM 약 +1kg) +0.5~1.0kg, 글리코겐·훈련성 부종(Damas 2016) +0.5~1.5kg, 실제 제지방 +0.5~2.0kg. 그리고 결정적으로 — 체중은 −2.3kg만 움직였는데 결과지는 지방 −5.3kg을 주장합니다. **그 차액 3.0kg 전부가 \"근육이 늘었다\"는 주장에서 나옵니다. 하나가 무너지면 둘 다 무너집니다.** 방향은 진짜고(PBF 28.4 → 24.2 → 23.1, 3회 연속 단조 감소는 우연이 아닙니다) 크기가 40~60% 과장된 겁니다.\n\n**4) 최근 스캔(9/19)은 판정에 쓰면 안 됩니다.**\n8/31 → 9/19는 19일로 28일 게이트 미달이고, 네 지표(Δ체중 −0.2, ΔSMM +0.5, ΔBFM −1.0, ΔPBF −1.1%p) 전부가 실사용 노이즈 바닥 이하거나 경계입니다. 게다가 측정 시각이 11:09로 이전보다 2.5시간 늦습니다. 앱 문구: *\"간격이 19일이라 판정하지 않습니다. 이번엔 오전 11시에 재셨는데, 그것만으로 근육 0.5kg쯤은 달라 보입니다. 다음 인바디는 10월 17일 이후, 오전 7~8시, 공복으로.\"*\n\n**5) 인바디가 제안한 78.4kg은 목표로 쓰면 안 됩니다.**\n역산해 보면 적정체중 = 현재 FFM / 0.85 입니다. FFM을 상수로 박고 푼 식이라 **근육조절이 구조적으로 항상 0.0이 나옵니다.** 인바디가 \"근육은 지금으로 충분하다\"고 말한 적이 없다는 뜻입니다. 더 나쁜 건 목표가 움직인다는 겁니다 — 근육 +2kg 성공하면 적정체중은 80.8kg으로 올라가고, **근육을 2kg 잃으면 76.1kg으로 내려가 목표에 \"가까워집니다\".** 이 숫자에 앵커링하면 앱이 근손실을 진전으로 보상합니다. 오너의 목표는 체중 숫자가 아니라 **체지방률 15%**로 잡아야 합니다. 그리고 인쇄된 권장섭취칼로리 3,104kcal은 PAL 1.715 가정치(역산 3104/1810 = 1.715)라 앱의 2,807kcal과 하루 298kcal 차이 — 3개월이면 지방 3.5kg 분량의 계획 오차입니다. 쓰지 마세요.\n\n**한 줄 요약: 리컴프 유지 + 하루 100kcal 증량 + 다음 측정은 10월 17일 이후 오전 공복. 체지방률 18%에 닿으면 그때 커팅모드가 열립니다.**";


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
    i.ratePct = (i.deadlineWeeks && i.curWeightKg)
      ? Math.abs(i.dWeightKg) / i.curWeightKg / i.deadlineWeeks * 100 : null;
    i.targetPbf = i.targetPbfPct;
    // 문구 치환용 파생값
    i.ffmKg = (i.dSmmKg || 0) * 1.75;          // 골격근 변화가 함의하는 제지방 변화
    i.fatKg = Math.abs(i.dBfmKg || 0);
    i.weeksSpan = i.recentTrend ? i.recentTrend.weeksSpan : null;
    i.pct = (i.recentTrend && i.curWeightKg)
      ? Math.abs(i.recentTrend.dWeightKg / i.curWeightKg * 100) : null;
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
      var hit = false;
      try { hit = !!ref.test(i); } catch (e) { hit = false; }
      if (hit) {
        return { refused: true, message: fill(ref.message, i), mode: null, trendNote: trendNote };
      }
    }

    for (var n = 0; n < RULES.length; n++) {
      var rule = RULES[n];
      var ok = false;
      try { ok = !!rule.test(i); } catch (e) { ok = false; }
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

  global.MB_MODES = {
    NOISE: NOISE, MODES: MODES, RULES: RULES, REFUSALS: REFUSALS,
    OWNER_VERDICT: OWNER_VERDICT,
    select: select, byId: byId, whyNot: whyNot
  };
})(window);