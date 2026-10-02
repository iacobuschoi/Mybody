/* =============================================================================
 * citations.dart — 앱이 보여 주는 권장값의 출처
 *
 * 애플 심사(가이드라인 1.4.1)가 0.2.20 (347) 을 거절한 이유: 건강 · 영양 · 운동
 * 권장값을 보여 주면서 **출처(링크)** 를 앱 안에 안 뒀습니다. 여기 있는 것이
 * 그 출처 목록이고, 화면마다 붙은 작은 「출처」 링크(ui/source_link.dart)와
 * 설정 → 「근거 · 출처」 화면(screens/sources.dart)이 이 목록을 읽습니다.
 *
 * **여기 적는 것은 확인된 문헌 · 지침뿐입니다.** 새 숫자를 화면에 올리면 그 숫자의
 * 주제(topic)를 [kSourceTopics] 에 두고, 그 주제를 뒷받침하는 문헌을 아래에 답니다.
 * 직접 뒷받침하는 문헌이 없는 주제(앱이 정한 기준 · 설계 값)는 [kTopicRelated] 로
 * 가까운 근거를 보여 주고, 문헌이 있다고 말하지 않습니다 — 시트와 목록 머리에
 * 「… 기준은 앱이 정한 값입니다 — 아래는 관련 근거입니다」 를 한 줄 밝힙니다
 * ([appSetNote]). 문헌이 있어도 앱의 숫자가 그 문헌의 숫자와 다르면(예: 유산소 주 80분
 * vs WHO 150분) 제목에 그 차이를 그대로 적습니다 — 출처를 눌러 본 사람이 앱 숫자와
 * 다른 숫자를 먼저 보게 하면 안 됩니다.
 *
 * 엔진(packages/mybody_core)의 글은 웹 프로토타입과 같아야 해서(difftest) 거기서는
 * 못 고칩니다. 문헌과 어긋나거나 문헌이 없는 엔진 문장은 화면에 그릴 때
 * [reworded] 로 바꿉니다([kClaimReword]).
 *
 * 링크는 올리기 전에 인터넷이 되는 컴퓨터에서 `node tools/check-citations.js` 로 열어 보고,
 * DOI 가 아닌 주소(정부 게시판 · 포털 · 블로그)는 아이폰 · 아이패드 Safari 에서 손으로
 * 엽니다 — 심사관이 누른 출처가 404 면 출처가 없는 것과 같습니다.
 *
 * 묶음 넷: 에너지·칼로리 / 영양·단백질 / 운동 / 체성분.
 * ========================================================================== */

/// 출처 한 건.
class Citation {
  const Citation({
    required this.id,
    required this.group,
    required this.topics,
    required this.title,
    required this.reference,
    required this.url,
  });

  /// 바뀌지 않는 이름 — 시험과 화면의 열쇠.
  final String id;

  /// [kCitationGroups] 중 하나.
  final String group;

  /// 이 문헌이 뒷받침하는 주제들([kSourceTopics] 의 열쇠).
  final List<String> topics;

  /// 무엇의 근거인지 — 짧은 한국어 한 줄.
  final String title;

  /// 서지 정보 그대로(저자 · 제목 · 학술지 · 연도).
  final String reference;

  /// 원문 링크(https).
  final String url;
}

const String kGroupEnergy = '에너지·칼로리';
const String kGroupNutrition = '영양·단백질';
const String kGroupExercise = '운동';
const String kGroupBody = '체성분';

/// 화면에 보이는 묶음 순서.
const List<String> kCitationGroups = [kGroupEnergy, kGroupNutrition, kGroupExercise, kGroupBody];

/// 앱이 보여 주는 권장값의 주제와 그 한국어 이름. 「출처」 링크는 이 열쇠로 묻습니다.
const Map<String, String> kSourceTopics = {
  // 에너지 · 칼로리
  'bmr': '기초대사량',
  'tdee_activity': '활동계수 · 하루 소모',
  'daily_kcal_target': '하루 섭취 목표',
  'kcal_floor': '하루 섭취 하한',
  'fat_mobilization_cap': '체지방 에너지 상한',
  'energy_per_kg_fat': '감량 1kg당 열량(어림)',
  'weekly_loss_rate': '주당 감량 속도',
  'plan_timeline_prediction': '기간 · 목표일 예측',
  'strategy_description': '감량 · 유지 · 증량 단계',
  'intensity_notes': '강도별 기간',
  'continuous_cut_limit': '연속 감량 · 유지기',
  'duration_options': '기간으로 정하기',
  'checkin_adjustment': '주간 체크인 조정',
  // 영양 · 단백질
  'protein_target': '단백질 목표',
  'fat_carb_split': '탄수화물 · 지방 배분',
  'protein_per_meal_and_diet_notes': '끼니당 단백질 · 식단 요령',
  'meal_plan_examples': '끼니 예시',
  'food_composition': '음식 영양성분',
  'food_suggestions': '음식 추천',
  'diet_status_nudge': '식단 메모',
  'diet_adherence': '식단 달성률',
  // 운동
  'resistance_volume_split': '근력운동 횟수 · 볼륨',
  'sets_reps_rest': '세트 · 반복 · 휴식',
  'progression_rule': '무게 올리기',
  'load_recommendation': '추천 무게',
  'cardio_minutes': '유산소 시간',
  'exercise_kcal': '운동 소모 칼로리',
  'bodyweight_routine': '맨몸 운동',
  'muscle_gain_rate': '근육 증가 속도',
  'activity_onboarding_inputs': '나이 · 운동 경력',
  // 체성분
  'body_fat_estimate': '키·체중 추정',
  'estimate_upgrade': '추정 → 실측',
  'recommended_goal_default': '추천 목표 체지방률',
  'body_fat_lower_limit': '체지방률 하한',
  'ffmi_muscle_ceiling': '근육량 상한',
  'lean_mass_loss_warning': '근손실 경고',
  'goal_mode_selection': '모드 고르기',
  'goal_refusals_safety': '계획을 만들지 않는 경우',
  'goal_consistency': '목표 숫자 맞추기',
  'measurement_noise': '인바디 오차',
  'plan_drift_progress': '진행 · 계획 비교',
  'scan_crosscheck': '결과지 검산',
};

/* 「출처」 링크의 주제 묶음 — 같은 숫자를 보여 주는 화면(플랜 · 홈 · 강도 · 기간 · 식단)이
   같은 묶음을 씁니다. */

/// 기간 · 목표일 · 주차별 궤적(시뮬레이션의 계수들).
const List<String> kPlanTimelineSources = [
  'plan_timeline_prediction', 'weekly_loss_rate', 'energy_per_kg_fat', 'fat_mobilization_cap',
  'muscle_gain_rate', 'ffmi_muscle_ceiling', 'strategy_description',
];

/// 하루 식단 목표 — 하루 소모 · 섭취 · 적자 · 하한 · 단백질 · 탄수 · 지방.
const List<String> kDietTargetSources = [
  'tdee_activity', 'bmr', 'daily_kcal_target', 'kcal_floor', 'protein_target', 'fat_carb_split',
];

/// 운동 처방 — 횟수 · 볼륨 · 세트 × 반복 · 휴식 · 유산소.
const List<String> kWorkoutSources = [
  'resistance_volume_split', 'sets_reps_rest', 'progression_rule', 'cardio_minutes',
];

/// 기간으로 정하기 카드 — 그 기간의 체지방 · 골격근 변화와 하루 kcal · 단백질.
const List<String> kDurationOptionSources = [
  'duration_options', 'daily_kcal_target', 'protein_target', 'weekly_loss_rate',
  'muscle_gain_rate',
];

/// 직접 뒷받침하는 문헌이 없는 주제(앱이 정한 기준 · 설계 값) → 가까운 근거의 주제.
/// 「출처」 를 누르면 이 주제들의 문헌을 보여 주고, 머리에 [appSetNote] 를 밝힙니다.
const Map<String, List<String>> kTopicRelated = {
  'intensity_notes': ['plan_timeline_prediction', 'fat_mobilization_cap', 'muscle_gain_rate', 'weekly_loss_rate'],
  'duration_options': ['plan_timeline_prediction', 'weekly_loss_rate', 'measurement_noise'],
  'diet_adherence': ['daily_kcal_target', 'protein_target'],
  'goal_mode_selection': ['weekly_loss_rate', 'daily_kcal_target', 'protein_target', 'recommended_goal_default'],
  'goal_refusals_safety': ['weekly_loss_rate', 'body_fat_lower_limit', 'measurement_noise'],
  'goal_consistency': ['measurement_noise'],
  'estimate_upgrade': ['body_fat_estimate', 'measurement_noise'],
};

/// 문헌은 있지만 앱이 쓰는 **구체적인 값은 앱이 정한** 주제 — 문헌은 방향 · 범위만 줍니다.
///   · continuous_cut_limit — 연속 감량 12 · 20 · 24주 한도는 어느 문헌에도 그 숫자로 없습니다.
///   · tdee_activity — 활동계수 1.20 · 1.375 · 1.55 · 1.725 · 1.90 은 FAO · NASEM 표의 값이 아닙니다.
///   · muscle_gain_rate — 경력별 근육 증가 계수(제지방의 월 1.44 · 0.86 · 0.43 · 0.20%)는 앱의 보정값.
///   · progression_rule — 「다 채우면 한 단계」 는 ACSM(1~2회 더 되는 날이 두 번 → 2~10%)보다 빠릅니다.
///   · cardio_minutes — 유산소 처방(주 60~240분)은 체성분 계획용 값이고 WHO 150분과 다릅니다.
const Set<String> kAppSetTopics = {
  'continuous_cut_limit', 'tdee_activity', 'muscle_gain_rate', 'progression_rule', 'cardio_minutes',
};

/// [topics] 중 앱이 정한 기준(직접 문헌 없음 · 또는 문헌과 다른 앱 값)인 것.
List<String> appSetTopics(Iterable<String> topics) => [
      for (final t in topics)
        if (kTopicRelated.containsKey(t) || kAppSetTopics.contains(t)) t,
    ];

/// 시트 · 목록 머리에 보일 한 줄 — 아래 문헌이 그 숫자의 직접 출처가 아니라 관련 근거라는 것.
/// 해당 주제가 없으면 null.
String? appSetNote(Iterable<String> topics) {
  final own = appSetTopics(topics);
  if (own.isEmpty) return null;
  return '「${topicLabels(own)}」 기준은 앱이 정한 값입니다 — 아래는 관련 근거입니다.';
}

/// 엔진(웹과 같은 글 — difftest 로 묶여 있어 거기서는 못 고칩니다)의 문장 중 바로 옆
/// 「출처」 와 어긋나거나 출처가 없는 의학 · 안전 주장 → 출처에 맞춘 말. 화면에 그릴 때만
/// [reworded] 로 바꿉니다.
const Map<String, String> kClaimReword = {
  /* Roth 2023 — 감량 중 세트 5 vs 3, 제지방 보존에 차이 없음. */
  '감량 중에는 볼륨을 유지하는 것이 근손실을 막는 가장 강력한 수단입니다':
      '감량 중에도 근력운동을 이어 가는 것이 근손실을 줄입니다',
  /* 청소년 감량의 구체적 건강 위험을 직접 뒷받침하는 문헌이 목록에 없습니다 — 주장 대신 상담 안내. */
  '성장기에는 체중을 줄이는 것보다 생활습관과 운동 습관을 잡는 게 우선이고, 급격한 감량은 성장 지연·빈혈·생리불순과 연결됩니다.':
      '성장기에는 체중을 줄이는 것보다 생활습관과 운동 습관을 잡는 게 우선입니다(이 앱의 기준). '
          '체중 조절이 필요하다면 소아청소년과 의사와 먼저 상의하세요.',
  /* 「안전」 한 상한이라는 문헌은 없습니다 — Helms 2014 · 대한비만학회는 주 0.5~1%(0.5~1kg),
     Garthe 2011 은 주 1.4% 에서 근육을 덜 지켰습니다. */
  '안전하게 가능한 상한(주 1.5%)을 넘습니다.':
      '이 앱이 계획을 만드는 상한(주 1.5%)을 넘습니다 — 권장 감량 속도는 주 0.5~1%입니다.',
  '지금 이 숫자는 몸이 아니라 물과 근육이 빠지는 속도입니다.':
      '이렇게 빠르면 지방보다 근육을 잃기 쉽습니다.',
  /* 「대사 회복에 보통 권하는 길이」 를 뒷받침하는 문헌이 없습니다. */
  '8주 — 대사 회복에 보통 권하는 길이': '8주 — 표준 유지 기간',
  /* Areta 2013 은 40g×2회가 20g×4회보다 낮았습니다. 한 끼 20~40g(Jäger 2017),
     체중 1kg당 약 0.4g(Schoenfeld · Aragon 2018). 하루 목표 ÷ 끼니가 40g 을 넘는 사람도
     흔해서(160g ÷ 3끼 = 53g) 나눠 먹는 길을 같이 적습니다. */
  '단백질은 끼니당 30~40g씩 고르게 나누는 편이 근단백 합성에 유리합니다.':
      '단백질은 끼니마다 고르게 — 한 끼 20~40g(체중 1kg당 약 0.4g)씩. '
          '하루 목표가 커서 끼니당 40g을 넘으면 간식으로 한 번 더 나누세요.',
};

/// 엔진 문장을 화면에 그리기 전에 [kClaimReword] 로 바꿉니다.
String reworded(String s) {
  var out = s;
  for (final e in kClaimReword.entries) {
    out = out.replaceAll(e.key, e.value);
  }
  return out;
}

const List<Citation> kCitations = [
  /* --- 에너지 · 칼로리 --------------------------------------------------- */
  Citation(
    id: 'cunningham_1991',
    group: kGroupEnergy,
    topics: ['bmr', 'scan_crosscheck'],
    title: '기초대사량 = 370 + 21.6 × 제지방(kg) 식의 원 출처',
    reference: 'Cunningham JJ. Body composition as a determinant of energy expenditure: '
        'a synthetic review and a proposed general prediction equation. '
        'Am J Clin Nutr. 1991;54(6):963-969.',
    url: 'https://doi.org/10.1093/ajcn/54.6.963',
  ),
  Citation(
    id: 'tenhaaf_weijs_2014',
    group: kGroupEnergy,
    topics: ['bmr'],
    title: '운동하는 18~35세 성인에서 제지방 기반 Cunningham 식이 실측 기초대사량과 잘 맞았다 '
        '(이 연구가 쓴 식은 1980년판 500 + 22×제지방 — 앱이 쓰는 1991년판은 조금 낮게 나옵니다)',
    reference: 'ten Haaf T, Weijs PJM. Resting energy expenditure prediction in recreational '
        'athletes of 18-35 years: confirmation of Cunningham equation and an improved '
        'weight-based alternative. PLoS One. 2014;9(10):e108460.',
    url: 'https://doi.org/10.1371/journal.pone.0108460',
  ),
  Citation(
    id: 'inbody_bmr_cunningham',
    group: kGroupEnergy,
    topics: ['bmr'],
    title: '인바디 결과지의 기초대사량도 같은 식으로 계산한다는 제조사 설명',
    reference: 'InBody USA Help Center. How is BMR measured? How precise is BMR measured by '
        'InBody? (제조사 안내, 동료 심사 문헌 아님)',
    url: 'https://inbodyusa.zendesk.com/hc/en-us/articles/32680724662420-How-is-BMR-measured-How-precise-is-BMR-measured-by-InBody',
  ),
  Citation(
    id: 'nasem_2023_dri_energy',
    group: kGroupEnergy,
    topics: ['tdee_activity'],
    title: '하루 소모 = 기초대사량 × 활동계수(PAL)라는 정의와 활동 수준 구분 — '
        '앱의 단계별 계수(1.20~1.90)는 이 보고서의 값이 아닙니다',
    reference: 'National Academies of Sciences, Engineering, and Medicine. '
        'Dietary Reference Intakes for Energy. Washington, DC: The National Academies Press; 2023.',
    url: 'https://doi.org/10.17226/26818',
  ),
  Citation(
    id: 'fao_who_unu_2004',
    group: kGroupEnergy,
    topics: ['tdee_activity'],
    title: 'FAO 활동 수준(PAL): 좌식·가벼운 생활 1.40~1.69 · 활동적 1.70~1.99 · '
        '매우 활동적 2.00~2.40 — 앱의 좌식 1.20 · 가벼움 1.375 는 이보다 낮게(보수적으로) 잡은 값',
    reference: 'FAO/WHO/UNU. Human energy requirements: Report of a Joint FAO/WHO/UNU Expert '
        'Consultation. FAO Food and Nutrition Technical Report Series No. 1. Rome: FAO; 2004. '
        'Chapter 5, Energy requirements of adults.',
    url: 'https://www.fao.org/4/y5686e/y5686e07.htm',
  ),
  Citation(
    id: 'jensen_2013_aha_acc_tos',
    group: kGroupEnergy,
    topics: ['kcal_floor', 'daily_kcal_target'],
    title: '감량 시 하루 섭취(여 1,200~1,500 · 남 1,500~1,800kcal)와 적자 크기',
    reference: 'Jensen MD, Ryan DH, Apovian CM, et al. 2013 AHA/ACC/TOS Guideline for the '
        'Management of Overweight and Obesity in Adults. Circulation. 2014;129(25 Suppl 2):S102-S138.',
    url: 'https://doi.org/10.1161/01.cir.0000437739.71477.ee',
  ),
  Citation(
    id: 'ksso_2022_guideline',
    group: kGroupEnergy,
    topics: ['daily_kcal_target', 'weekly_loss_rate', 'kcal_floor', 'goal_refusals_safety'],
    title: '하루 적자 500~1,000kcal · 주 0.5~1kg 감량 · BMI 18.5 미만은 저체중(대한비만학회 진료지침)',
    reference: 'Kim KK, Haam JH, et al. Evaluation and Treatment of Obesity and Its Comorbidities: '
        '2022 Update of Clinical Practice Guidelines for Obesity by the Korean Society for the '
        'Study of Obesity. J Obes Metab Syndr. 2023;32(1):1-24.',
    url: 'https://doi.org/10.7570/jomes23016',
  ),
  Citation(
    id: 'helms_aragon_fitschen_2014',
    group: kGroupEnergy,
    topics: ['weekly_loss_rate', 'daily_kcal_target', 'fat_carb_split'],
    title: '감량 속도 주 체중의 0.5~1% · 지방 총열량의 15~30% · 나머지는 탄수화물',
    reference: 'Helms ER, Aragon AA, Fitschen PJ. Evidence-based recommendations for natural '
        'bodybuilding contest preparation: nutrition and supplementation. '
        'J Int Soc Sports Nutr. 2014;11:20.',
    url: 'https://doi.org/10.1186/1550-2783-11-20',
  ),
  Citation(
    id: 'garthe_2011',
    group: kGroupEnergy,
    topics: ['weekly_loss_rate', 'lean_mass_loss_warning'],
    title: '빠른 감량(주 1.4%)은 느린 감량(주 0.7%)보다 근육을 덜 지킨다',
    reference: 'Garthe I, Raastad T, Refsnes PE, Koivisto A, Sundgot-Borgen J. Effect of two '
        'different weight-loss rates on body composition and strength and power-related '
        'performance in elite athletes. Int J Sport Nutr Exerc Metab. 2011;21(2):97-104.',
    url: 'https://doi.org/10.1123/ijsnem.21.2.97',
  ),
  Citation(
    id: 'alpert_2005',
    group: kGroupEnergy,
    topics: ['fat_mobilization_cap'],
    title: '체지방이 하루에 내놓을 수 있는 에너지의 상한(앱 값은 이보다 보수적)',
    reference: 'Alpert SS. A limit on the energy transfer rate from the human fat store in '
        'hypophagia. J Theor Biol. 2005;233(1):1-13.',
    url: 'https://doi.org/10.1016/j.jtbi.2004.08.029',
  ),
  Citation(
    id: 'hall_2008_energy_deficit',
    group: kGroupEnergy,
    topics: ['energy_per_kg_fat', 'plan_timeline_prediction'],
    title: '「체중 1kg ≈ 7,700kcal」 은 어림 규칙 — 순수 체지방 1kg 은 약 9,400kcal. '
        '앱은 7,700 을 써서 지방이 실제보다 빨리 빠지는 것으로(기간을 짧게) 계산할 수 있습니다',
    reference: 'Hall KD. What is the required energy deficit per unit weight loss? '
        'Int J Obes (Lond). 2008;32(3):573-576.',
    url: 'https://doi.org/10.1038/sj.ijo.0803720',
  ),
  Citation(
    id: 'hall_2011_lancet',
    group: kGroupEnergy,
    topics: ['plan_timeline_prediction', 'energy_per_kg_fat', 'checkin_adjustment'],
    title: '체중이 줄면 소모량도 줄어 예측은 주기적으로 다시 맞춰야 한다',
    reference: 'Hall KD, Sacks G, Chandramohan D, et al. Quantification of the effect of energy '
        'imbalance on bodyweight. Lancet. 2011;378(9793):826-837.',
    url: 'https://doi.org/10.1016/S0140-6736(11)60812-X',
  ),
  Citation(
    id: 'byrne_2018_matador',
    group: kGroupEnergy,
    topics: ['continuous_cut_limit', 'strategy_description'],
    title: '감량 중간에 2주 유지기를 넣는 방식(MATADOR 연구)',
    reference: 'Byrne NM, Sainsbury A, King NA, Hills AP, Wood RE. Intermittent energy restriction '
        'improves weight loss efficiency in obese men: the MATADOR study. '
        'Int J Obes (Lond). 2018;42(2):129-138.',
    url: 'https://doi.org/10.1038/ijo.2017.206',
  ),
  Citation(
    id: 'peos_2021_icecap',
    group: kGroupEnergy,
    topics: ['continuous_cut_limit'],
    title: '근력운동하는 사람의 유지기(다이어트 브레이크) — 체성분 차이는 없었음',
    reference: 'Peos JJ, Helms ER, Fournier PA, et al. Continuous versus Intermittent Dieting for '
        'Fat Loss and Fat-Free Mass Retention in Resistance-trained Adults: The ICECAP Trial. '
        'Med Sci Sports Exerc. 2021;53(8):1685-1698.',
    url: 'https://doi.org/10.1249/MSS.0000000000002636',
  ),
  Citation(
    id: 'rossow_2013',
    group: kGroupEnergy,
    topics: ['continuous_cut_limit'],
    title: '오랜 연속 감량 뒤 호르몬 · 대사 지표가 떨어진 사례(1명)',
    reference: 'Rossow LM, Fukuda DH, Fahs CA, Loenneke JP, Stout JR. Natural bodybuilding '
        'competition preparation and recovery: a 12-month case study. '
        'Int J Sports Physiol Perform. 2013;8(5):582-592.',
    url: 'https://doi.org/10.1123/ijspp.8.5.582',
  ),
  Citation(
    id: 'trexler_2014',
    group: kGroupEnergy,
    topics: ['strategy_description', 'checkin_adjustment'],
    title: '감량 중 소모량이 줄어드는 현상(대사 적응)과 유지기',
    reference: 'Trexler ET, Smith-Ryan AE, Norton LE. Metabolic adaptation to weight loss: '
        'implications for the athlete. J Int Soc Sports Nutr. 2014;11:7.',
    url: 'https://doi.org/10.1186/1550-2783-11-7',
  ),
  Citation(
    id: 'thomas_2014_adherence',
    group: kGroupEnergy,
    topics: ['checkin_adjustment'],
    title: '정체기는 대사보다 식단 순응도 때문인 경우가 많다',
    reference: 'Thomas DM, Martin CK, Redman LM, et al. Effect of dietary adherence on the body '
        'weight plateau: a mathematical model incorporating intermittent compliance with energy '
        'intake prescription. Am J Clin Nutr. 2014;100(3):787-795.',
    url: 'https://doi.org/10.3945/ajcn.113.079822',
  ),
  Citation(
    id: 'schneditz_2023',
    group: kGroupEnergy,
    topics: ['checkin_adjustment', 'protein_per_meal_and_diet_notes'],
    title: '아침 공복 체중도 날마다 흔들린다 — 한 번 값보다 추세로',
    reference: 'Schneditz D, Hofmann P, Krenn S, Waller M, Mussnig S, Hecking M. '
        'Day-to-day variability in euvolemic body mass. Ren Fail. 2023;45(2):2273421.',
    url: 'https://doi.org/10.1080/0886022X.2023.2273421',
  ),

  /* --- 영양 · 단백질 ----------------------------------------------------- */
  Citation(
    id: 'helms_zinn_2014_protein_cut',
    group: kGroupNutrition,
    topics: ['protein_target', 'lean_mass_loss_warning'],
    title: '감량 중 단백질 제지방 1kg당 2.3~3.1g',
    reference: 'Helms ER, Zinn C, Rowlands DS, Brown SR. A systematic review of dietary protein '
        'during caloric restriction in resistance trained lean athletes: a case for higher '
        'intakes. Int J Sport Nutr Exerc Metab. 2014;24(2):127-138.',
    url: 'https://doi.org/10.1123/ijsnem.2013-0054',
  ),
  Citation(
    id: 'morton_2018_protein_meta',
    group: kGroupNutrition,
    topics: ['protein_target'],
    title: '근력운동 중 제지방 증가는 하루 단백질 체중 1kg당 약 1.6g(95% CI 1.0~2.2)에서 더 늘지 '
        '않았다 — 저자들은 최대로는 약 2.2g 을 권함',
    reference: 'Morton RW, Murphy KT, McKellar SR, et al. A systematic review, meta-analysis and '
        'meta-regression of the effect of protein supplementation on resistance '
        'training-induced gains in muscle mass and strength in healthy adults. '
        'Br J Sports Med. 2018;52(6):376-384.',
    url: 'https://doi.org/10.1136/bjsports-2017-097608',
  ),
  Citation(
    id: 'jager_2017_issn_protein',
    group: kGroupNutrition,
    topics: ['protein_target', 'protein_per_meal_and_diet_notes', 'food_suggestions'],
    title: '운동하는 사람의 하루 단백질(체중 1kg당 1.4~2.0g)과 한 끼 20~40g',
    reference: 'Jäger R, Kerksick CM, Campbell BI, et al. International Society of Sports '
        'Nutrition Position Stand: protein and exercise. J Int Soc Sports Nutr. 2017;14:20.',
    url: 'https://doi.org/10.1186/s12970-017-0177-8',
  ),
  Citation(
    id: 'iraki_2019_offseason',
    group: kGroupNutrition,
    topics: ['daily_kcal_target', 'protein_target', 'fat_carb_split', 'muscle_gain_rate'],
    title: '증량기 칼로리 잉여 10~20% · 체중 증가 주 0.25~0.5%(경력이 길수록 낮게) · 단백질 · 지방 배분',
    reference: 'Iraki J, Fitschen P, Espinar S, Helms E. Nutrition Recommendations for '
        'Bodybuilders in the Off-Season: A Narrative Review. Sports (Basel). 2019;7(7):154.',
    url: 'https://doi.org/10.3390/sports7070154',
  ),
  Citation(
    id: 'schoenfeld_aragon_2018_per_meal',
    group: kGroupNutrition,
    topics: ['protein_per_meal_and_diet_notes', 'food_suggestions'],
    title: '단백질은 끼니마다 고르게(한 끼 체중 1kg당 약 0.4g)',
    reference: 'Schoenfeld BJ, Aragon AA. How much protein can the body use in a single meal for '
        'muscle-building? Implications for daily protein distribution. '
        'J Int Soc Sports Nutr. 2018;15:10.',
    url: 'https://doi.org/10.1186/s12970-018-0215-1',
  ),
  Citation(
    id: 'areta_2013_distribution',
    group: kGroupNutrition,
    topics: ['protein_per_meal_and_diet_notes'],
    title: '운동 후 12시간 동안 단백질 20g씩 3시간마다(4회)가 10g×8회나 40g×2회보다 '
        '근단백 합성이 높았다',
    reference: 'Areta JL, Burke LM, Ross ML, et al. Timing and distribution of protein ingestion '
        'during prolonged recovery from resistance exercise alters myofibrillar protein '
        'synthesis. J Physiol. 2013;591(9):2319-2331.',
    url: 'https://doi.org/10.1113/jphysiol.2012.244897',
  ),
  Citation(
    id: 'kdri_2025',
    group: kGroupNutrition,
    topics: ['fat_carb_split'],
    title: '일반 성인 기준(2025 한국인 영양소 섭취기준): 탄수 50~65% · 단백질 10~20% · 지방 15~30% '
        '— 감량 중에는 근육을 지키려 단백질을 이보다 높게, 탄수화물은 낮게 잡을 수 있습니다'
        '(Helms 2014 · Jäger 2017)',
    reference: '보건복지부 · 한국영양학회. 2025 한국인 영양소 섭취기준(Dietary Reference Intakes '
        'for Koreans 2025). 보건복지부 보도자료 「영양소 적정 섭취기준 개정」, 2025년 12월.',
    url: 'https://www.mohw.go.kr/board.es?mid=a10503010100&bid=0027&act=view&list_no=1488441',
  ),
  Citation(
    id: 'kdri_2025_carb',
    group: kGroupNutrition,
    topics: ['fat_carb_split'],
    title: '탄수화물 권장섭취량 하루 130g(2025 한국인 영양소 섭취기준) — 일반 성인 기준이며, '
        '감량 중 앱의 탄수 목표는 이보다 낮을 수 있습니다(앱의 하한 50g)',
    reference: '보건복지부 · 한국영양학회. 2025 한국인 영양소 섭취기준 국문 요약본(탄수화물 '
        '평균필요량 100g · 권장섭취량 130g). 한국영양학회 KDRIs 자료실, 2025.',
    url: 'https://www.kns.or.kr/FileRoom/FileRoom_view.asp?idx=167&BoardID=Kdr',
  ),
  Citation(
    id: 'fao_2003_atwater',
    group: kGroupNutrition,
    topics: ['fat_carb_split'],
    title: '단백질 · 탄수화물 1g = 4kcal, 지방 1g = 9kcal',
    reference: 'FAO. Food energy – methods of analysis and conversion factors. FAO Food and '
        'Nutrition Paper 77. Rome: FAO; 2003. Chapter 3.',
    url: 'https://www.fao.org/4/y5022e/y5022e04.htm',
  ),
  Citation(
    id: 'mfds_food_nutrient_db',
    group: kGroupNutrition,
    topics: ['food_composition', 'meal_plan_examples', 'diet_status_nudge'],
    title: '음식 칼로리 · 영양성분 값(식약처 식품영양성분 데이터베이스)',
    reference: '식품의약품안전처. 식품영양성분 데이터베이스(식품안전나라).',
    url: 'https://various.foodsafetykorea.go.kr/nutrient/',
  ),
  Citation(
    id: 'rda_korean_food_composition_table',
    group: kGroupNutrition,
    topics: ['food_composition', 'meal_plan_examples', 'diet_status_nudge'],
    title: '원재료 식품 100g당 영양성분(국가표준식품성분표)',
    reference: '농촌진흥청 국립농업과학원. 국가표준식품성분표 제10개정판 / 국가표준식품성분 DB 10.3.',
    url: 'https://koreanfood.rda.go.kr/kfi/fct/fctIntro/list?menuId=PS03562',
  ),
  Citation(
    id: 'usda_fdc_egg_171287',
    group: kGroupNutrition,
    topics: ['diet_status_nudge', 'food_composition'],
    title: '계란 1개 단백질 약 6.3g',
    reference: 'U.S. Department of Agriculture, Agricultural Research Service. FoodData Central '
        '(SR Legacy): Egg, whole, raw, fresh. FDC ID 171287.',
    url: 'https://fdc.nal.usda.gov/fdc-app.html#/food-details/171287/nutrients',
  ),
  Citation(
    id: 'urban_2010_stated_energy',
    group: kGroupNutrition,
    topics: ['food_composition'],
    title: '식당 음식 열량은 표시값과 평균 20% 안팎 다르다',
    reference: 'Urban LE, Dallal GE, Robinson LM, et al. The accuracy of stated energy contents of '
        'reduced-energy, commercially prepared foods. J Am Diet Assoc. 2010;110(1):116-123.',
    url: 'https://doi.org/10.1016/j.jada.2009.10.003',
  ),
  Citation(
    id: 'urban_2016_restaurant_vs_db',
    group: kGroupNutrition,
    topics: ['food_composition'],
    title: '식당 음식은 DB 대표값보다 열량이 높은 경우가 흔하다',
    reference: 'Urban LE, Weber JL, Heyman MB, et al. Energy Contents of Frequently Ordered '
        'Restaurant Meals and Comparison with Human Energy Requirements and U.S. Department of '
        'Agriculture Database Information. J Acad Nutr Diet. 2016;116(4):590-598.e6.',
    url: 'https://doi.org/10.1016/j.jand.2015.11.009',
  ),
  Citation(
    id: 'nrp_2021_korean_sodium_sources',
    group: kGroupNutrition,
    topics: ['protein_per_meal_and_diet_notes'],
    title: '한국인 나트륨의 주요 공급원은 국 · 찌개 · 김치 · 면',
    reference: 'Jeong Y, Kim ES, Lee J, Kim Y. Trends in sodium intake and major contributing food '
        'groups and dishes in Korea: the Korea National Health and Nutrition Examination Survey '
        '2013–2017. Nutr Res Pract. 2021;15(3):382-395.',
    url: 'https://doi.org/10.4162/nrp.2021.15.3.382',
  ),

  /* --- 운동 -------------------------------------------------------------- */
  Citation(
    id: 'acsm_2009_progression',
    group: kGroupExercise,
    topics: [
      'sets_reps_rest', 'progression_rule', 'load_recommendation', 'bodyweight_routine',
      'muscle_gain_rate', 'activity_onboarding_inputs',
    ],
    title: '세트 · 반복(초보 8~12회) · 휴식 1~3분 · 운동 경력 구분 · 무게 올리기(목표보다 1~2회 '
        '더 되는 날이 두 번 이어지면 2~10%)',
    reference: 'Ratamess NA, Alvar BA, Evetoch TK, et al. American College of Sports Medicine '
        'position stand. Progression models in resistance training for healthy adults. '
        'Med Sci Sports Exerc. 2009;41(3):687-708.',
    url: 'https://doi.org/10.1249/MSS.0b013e3181915670',
  ),
  Citation(
    id: 'currier_2026_acsm',
    group: kGroupExercise,
    topics: ['resistance_volume_split', 'sets_reps_rest'],
    title: '근육군당 주 10세트 이상 · 세트 · 반복 · 강도 처방(ACSM 2026)',
    reference: 'Currier BS, et al. American College of Sports Medicine Position Stand. Resistance '
        'Training Prescription for Muscle Function, Hypertrophy, and Physical Performance in '
        'Healthy Adults: An Overview of Reviews. Med Sci Sports Exerc. 2026;58(4):851-872.',
    url: 'https://doi.org/10.1249/MSS.0000000000003897',
  ),
  Citation(
    id: 'schoenfeld_2017_volume',
    group: kGroupExercise,
    topics: ['resistance_volume_split'],
    title: '주간 세트 수가 많을수록 근육이 더 는다(주 10세트 이상)',
    reference: 'Schoenfeld BJ, Ogborn D, Krieger JW. Dose-response relationship between weekly '
        'resistance training volume and increases in muscle mass: A systematic review and '
        'meta-analysis. J Sports Sci. 2017;35(11):1073-1082.',
    url: 'https://doi.org/10.1080/02640414.2016.1210197',
  ),
  Citation(
    id: 'schoenfeld_2016_rest',
    group: kGroupExercise,
    topics: ['sets_reps_rest'],
    title: '세트 사이 3분 휴식이 1분보다 근력 · 근비대에 유리했다(훈련된 남성, 8주)',
    reference: 'Schoenfeld BJ, Pope ZK, Benik FM, et al. Longer interset rest periods enhance '
        'muscle strength and hypertrophy in resistance-trained men. '
        'J Strength Cond Res. 2016;30(7):1805-1812.',
    url: 'https://doi.org/10.1519/JSC.0000000000001272',
  ),
  Citation(
    id: 'roth_2023_volume_deficit',
    group: kGroupExercise,
    topics: ['resistance_volume_split'],
    title: '감량 중에도 근력운동을 이어 가기 — 볼륨을 더 늘릴 필요는 없음',
    reference: 'Roth C, Schwiete C, Happ K, et al. Resistance training volume does not influence '
        'lean mass preservation during energy restriction in trained males. '
        'Scand J Med Sci Sports. 2023;33(1):20-35.',
    url: 'https://doi.org/10.1111/sms.14237',
  ),
  Citation(
    id: 'brzycki_1993_1rm',
    group: kGroupExercise,
    topics: ['load_recommendation'],
    title: '반복 횟수로 최대 무게(1RM)의 몇 %인지 계산',
    reference: 'Brzycki M. Strength testing—predicting a one-rep max from reps-to-fatigue. '
        'J Phys Educ Recreat Dance. 1993;64(1):88-90.',
    url: 'https://doi.org/10.1080/07303084.1993.10606684',
  ),
  Citation(
    id: 'bull_2020_who',
    group: kGroupExercise,
    topics: ['cardio_minutes', 'bodyweight_routine', 'resistance_volume_split'],
    title: '건강 기준: 중강도 유산소 주 150~300분(고강도면 75~150분) · 근력운동 주 2회 이상'
        '(WHO 2020) — 앱의 유산소 처방이 이보다 적으면 걷기 등 일상 활동으로 채웁니다',
    reference: 'Bull FC, Al-Ansari SS, Biddle S, et al. World Health Organization 2020 guidelines '
        'on physical activity and sedentary behaviour. Br J Sports Med. 2020;54(24):1451-1462.',
    url: 'https://doi.org/10.1136/bjsports-2020-102955',
  ),
  Citation(
    id: 'mohw_2023_korean_pa_guide',
    group: kGroupExercise,
    topics: ['cardio_minutes', 'bodyweight_routine'],
    title: '한국인을 위한 신체활동 지침 — 중강도 유산소 주 150~300분(고강도면 75~150분) · '
        '근력운동 주 2일 이상',
    reference: '보건복지부 · 한국건강증진개발원. 한국인을 위한 신체활동 지침서(2023) 개정판. '
        '2023년 12월(보건복지부 누리집 게시).',
    url: 'https://www.mohw.go.kr/board.es?mid=a10411010100&bid=0019&act=view&list_no=1479208',
  ),
  Citation(
    id: 'jakicic_2024_acsm_weight',
    group: kGroupExercise,
    topics: ['cardio_minutes'],
    title: '감량 효과는 중강도 활동 주 150분 이상부터 뚜렷하고, 많을수록 크다(ACSM 2024)',
    reference: 'Jakicic JM, et al. Physical Activity and Excess Body Weight and Adiposity for '
        'Adults. American College of Sports Medicine Consensus Statement. '
        'Med Sci Sports Exerc. 2024;56(10):2076-2091.',
    url: 'https://doi.org/10.1249/MSS.0000000000003520',
  ),
  Citation(
    id: 'ainsworth_2011_compendium',
    group: kGroupExercise,
    topics: ['exercise_kcal'],
    title: '운동 종류별 강도(MET) 값 — 헬스는 「여러 종목 8~15회」 3.5, 맨몸은 「보통 강도」 3.8',
    reference: 'Ainsworth BE, Haskell WL, Herrmann SD, et al. 2011 Compendium of Physical '
        'Activities: a second update of codes and MET values. '
        'Med Sci Sports Exerc. 2011;43(8):1575-1581.',
    url: 'https://doi.org/10.1249/MSS.0b013e31821ece12',
  ),
  Citation(
    id: 'jette_1990_met',
    group: kGroupExercise,
    topics: ['exercise_kcal'],
    title: '운동 소모 칼로리 = MET × 3.5 × 체중 ÷ 200 × 분',
    reference: 'Jetté M, Sidney K, Blümchen G. Metabolic equivalents (METS) in exercise testing, '
        'exercise prescription, and evaluation of functional capacity. '
        'Clin Cardiol. 1990;13(8):555-565.',
    url: 'https://doi.org/10.1002/clc.4960130809',
  ),
  Citation(
    id: 'peterson_2011_aging',
    group: kGroupExercise,
    topics: ['muscle_gain_rate', 'activity_onboarding_inputs'],
    title: '근육 증가 속도는 나이가 많을수록 느려진다',
    reference: 'Peterson MD, Sen A, Gordon PM. Influence of resistance exercise on lean body mass '
        'in aging adults: a meta-analysis. Med Sci Sports Exerc. 2011;43(2):249-258.',
    url: 'https://doi.org/10.1249/MSS.0b013e3181eb6265',
  ),

  /* --- 체성분 ------------------------------------------------------------ */
  Citation(
    id: 'gallagher_2000_pbf',
    group: kGroupBody,
    topics: ['body_fat_estimate', 'recommended_goal_default'],
    title: '키 · 체중 · 나이 · 성별로 체지방률 추정, 건강 체지방률 범위',
    reference: 'Gallagher D, Heymsfield SB, Heo M, et al. Healthy percentage body fat ranges: an '
        'approach for developing guidelines based on body mass index. '
        'Am J Clin Nutr. 2000;72(3):694-701.',
    url: 'https://doi.org/10.1093/ajcn/72.3.694',
  ),
  Citation(
    id: 'lee_2000_smm',
    group: kGroupBody,
    topics: ['body_fat_estimate'],
    title: '키 · 체중으로 골격근량 추정(오차 약 2.8kg)',
    reference: 'Lee RC, Wang Z, Heo M, Ross R, Janssen I, Heymsfield SB. Total-body skeletal muscle '
        'mass: development and cross-validation of anthropometric prediction models. '
        'Am J Clin Nutr. 2000;72(3):796-803.',
    url: 'https://doi.org/10.1093/ajcn/72.3.796',
  ),
  Citation(
    id: 'ace_body_fat_chart',
    group: kGroupBody,
    topics: ['body_fat_lower_limit', 'recommended_goal_default'],
    title: '체지방률 구간 — 필수 체지방 남 2~5% · 여 10~13% '
        '(앱의 하한 남 8% · 여 15% 는 이보다 여유 있게 잡은 값)',
    reference: 'American Council on Exercise (ACE). What are the guidelines for percentage of body '
        'fat loss? ACE Lifestyle Blog #112.',
    url: 'https://www.acefitness.org/education-and-resources/lifestyle/blog/112/what-are-the-guidelines-for-percentage-of-body-fat-loss/',
  ),
  Citation(
    id: 'kouri_1995_ffmi',
    group: kGroupBody,
    topics: ['ffmi_muscle_ceiling'],
    title: '남성: 약물 없이 닿는 제지방량지수 상한 약 25(남성 운동선수 조사) — '
        '여성 상한 22 는 이 연구에 없는 앱 설정값',
    reference: 'Kouri EM, Pope HG Jr, Katz DL, Oliva P. Fat-free mass index in users and nonusers of '
        'anabolic-androgenic steroids. Clin J Sport Med. 1995;5(4):223-228.',
    url: 'https://doi.org/10.1097/00042752-199510000-00003',
  ),
  Citation(
    id: 'looney_2024_inbody770',
    group: kGroupBody,
    topics: ['measurement_noise', 'plan_drift_progress'],
    title: '인바디 값은 날마다 0.1~0.7kg 흔들린다',
    reference: 'Looney DP, Schafer EA, Chapman CL, et al. Reliability, biological variability, and '
        'accuracy of multi-frequency bioelectrical impedance analysis for measuring body '
        'composition components. Front Nutr. 2024;11:1491931.',
    url: 'https://doi.org/10.3389/fnut.2024.1491931',
  ),
  Citation(
    id: 'mclester_2020_inbody',
    group: kGroupBody,
    topics: ['measurement_noise'],
    title: '인바디 반복 측정 오차(체지방 약 0.5~0.9kg)',
    reference: 'McLester CN, Nickerson BS, Kliszczewicz BM, McLester JR. Reliability and Agreement '
        'of Various InBody Body Composition Analyzers as Compared to Dual-Energy X-Ray '
        'Absorptiometry in Healthy Men and Women. J Clin Densitom. 2020;23(3):443-450.',
    url: 'https://doi.org/10.1016/j.jocd.2018.10.008',
  ),
  Citation(
    id: 'kyle_2004_espen_bia',
    group: kGroupBody,
    topics: ['measurement_noise'],
    title: '생체전기임피던스(인바디)는 수분 상태에 민감하다',
    reference: 'Kyle UG, Bosaeus I, De Lorenzo AD, et al. (ESPEN). Bioelectrical impedance '
        'analysis—part II: utilization in clinical practice. Clin Nutr. 2004;23(6):1430-1453.',
    url: 'https://doi.org/10.1016/j.clnu.2004.09.012',
  ),
  Citation(
    id: 'wang_1999_ffm_hydration',
    group: kGroupBody,
    topics: ['scan_crosscheck'],
    title: '체수분은 제지방의 약 73%',
    reference: 'Wang Z, Deurenberg P, Wang W, et al. Hydration of fat-free body mass: review and '
        'critique of a classic body-composition constant. Am J Clin Nutr. 1999;69(5):833-841.',
    url: 'https://doi.org/10.1093/ajcn/69.5.833',
  ),
];

/// [topics] 를 뒷받침하는 출처(직접 + [kTopicRelated] 의 가까운 근거). 묶음 순서 → 목록 순서.
List<Citation> citationsFor(Iterable<String> topics) {
  final want = <String>{};
  for (final t in topics) {
    want.add(t);
    want.addAll(kTopicRelated[t] ?? const []);
  }
  return [
    for (final g in kCitationGroups)
      for (final c in kCitations)
        if (c.group == g && c.topics.any(want.contains)) c,
  ];
}

/// 주제들의 한국어 이름 — 시트 머리에 「기초대사량 · 활동계수 · 하루 소모」.
String topicLabels(Iterable<String> topics) =>
    [for (final t in topics) kSourceTopics[t] ?? t].join(' · ');
