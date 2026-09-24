/* =============================================================================
 * data.dart — prototype/js/data.js 를 그대로 옮긴 씨앗 데이터
 *
 * **손으로 옮기지 않았습니다.** data.js 를 읽어서 찍어낸 것입니다
 * (tools/gen-data-dart.js). 운동 종목 40개와 식품 23개를 눈으로 옮기면
 * 반드시 한 글자가 틀리고, 틀린 자리는 "닭가슴살 단백질 23g" 같은
 * 사용자가 그대로 믿는 숫자입니다.
 *
 * 정수도 전부 소수(22.0)로 찍습니다. 자바스크립트에는 정수형이 따로 없고
 * 우리는 그 산수를 흉내 내는 중이라, Dart 쪽에서만 int 로 들어가면
 * 나눗셈과 비교가 갈리는 자리가 생깁니다. 값은 같습니다 — 22.0 == 22.
 *
 * 원본이 바뀌면 다시 찍어내세요:  node tools/gen-data-dart.js
 * ========================================================================== */
library;

const Map<String, Object?> kSeedProfile = {
  'sex': 'male',
  'age': 22.0,
  'heightCm': 187.0,
  'activityLevel': 'moderate',
  'trainingAge': 'novice',
  'daysPerWeek': 4.0,
  'sessionMinutes': 60.0,
  'environment': 'gym',
  'injuries': '',
  'dietFlags': <Object?>[],
  'mealsPerDay': 3.0,
  'cookingLevel': 'simple',
  'hadPriorPeak': false,
};

const List<Object?> kSeedScans = [
  {
    'id': 'scan-20260630',
    'measuredAt': '2026-06-30T07:36:00+09:00',
    'source': 'chart',
    'device': 'InBody270',
    'weightKg': 89.0,
    'smmKg': 36.2,
    'pbfPct': 28.4,
    'bfmKg': 25.3,
    'ffmKg': 63.7,
    'partial': true,
  },
  {
    'id': 'scan-20260831',
    'measuredAt': '2026-08-31T08:35:00+09:00',
    'source': 'chart',
    'device': 'InBody270',
    'weightKg': 86.9,
    'smmKg': 37.4,
    'pbfPct': 24.2,
    'bfmKg': 21.0,
    'ffmKg': 65.9,
    'partial': true,
  },
  {
    'id': 'scan-20260919',
    'measuredAt': '2026-09-19T11:09:00+09:00',
    'source': 'sheet',
    'device': 'InBody270',
    'partial': false,
    'tbwL': 48.7,
    'tbwRange': [
      43.3,
      52.9,
    ],
    'proteinKg': 13.3,
    'proteinRange': [
      11.6,
      14.2,
    ],
    'mineralKg': 4.7,
    'mineralRange': [
      4.0,
      4.89,
    ],
    'bfmKg': 20.0,
    'bfmRange': [
      9.2,
      18.5,
    ],
    'weightKg': 86.7,
    'weightRange': [
      65.4,
      88.4,
    ],
    'smmKg': 37.9,
    'bmi': 24.8,
    'pbfPct': 23.1,
    'inbodyScore': 73.0,
    'idealWeightKg': 78.4,
    'weightControlKg': -8.3,
    'fatControlKg': -8.3,
    'muscleControlKg': 0.0,
    'bmiGrade': '과체중',
    'pbfGrade': '경도비만',
    'whr': 0.94,
    'visceralFatLevel': 8.0,
    'ffmKg': 66.7,
    'ffmRange': [
      58.9,
      71.9,
    ],
    'bmrKcal': 1810.0,
    'bmrRange': [
      1803.0,
      2121.0,
    ],
    'obesityDegreePct': 113.0,
    'recommendedIntakeKcal': 3104.0,
    'segmentalLean': {
      'rightArm': '표준',
      'leftArm': '표준',
      'trunk': '표준',
      'rightLeg': '표준',
      'leftLeg': '표준',
    },
    'segmentalFat': {
      'rightArm': '표준이상',
      'leftArm': '표준이상',
      'trunk': '표준이상',
      'rightLeg': '표준',
      'leftLeg': '표준',
    },
    'impedance': {
      'khz20': {
        'RA': 326.0,
        'LA': 335.4,
        'TR': 25.7,
        'RL': 270.8,
        'LL': 276.5,
      },
      'khz100': {
        'RA': 293.0,
        'LA': 302.6,
        'TR': 22.5,
        'RL': 236.5,
        'LL': 242.8,
      },
    },
  },
];

const Map<String, Object?> kStubOcrResult = {
  'fields': {
    'measuredAt': {
      'value': '2026-09-19T11:09:00+09:00',
      'confidence': 0.99,
    },
    'weightKg': {
      'value': 86.7,
      'confidence': 0.98,
    },
    'smmKg': {
      'value': 37.9,
      'confidence': 0.96,
    },
    'bfmKg': {
      'value': 20.0,
      'confidence': 0.94,
    },
    'pbfPct': {
      'value': 23.1,
      'confidence': 0.91,
    },
    'bmi': {
      'value': 24.8,
      'confidence': 0.88,
    },
    'ffmKg': {
      'value': 66.7,
      'confidence': 0.83,
    },
    'bmrKcal': {
      'value': 1810.0,
      'confidence': 0.79,
    },
    'visceralFatLevel': {
      'value': 8.0,
      'confidence': 0.61,
    },
    'whr': {
      'value': 0.34,
      'confidence': 0.38,
    },
    'inbodyScore': {
      'value': 73.0,
      'confidence': 0.72,
    },
    'tbwL': {
      'value': 48.7,
      'confidence': 0.86,
    },
    'proteinKg': {
      'value': 13.3,
      'confidence': 0.84,
    },
    'mineralKg': {
      'value': null,
      'confidence': 0.0,
    },
    'idealWeightKg': {
      'value': 78.4,
      'confidence': 0.77,
    },
  },
  'rawText': 'InBody270 / 187cm / 22 / 남성 / 2026.09.19. 11:09 ...',
  'parseMs': 3200.0,
};

/// 운동 종목 풀 — 부위 → 종목 목록
const Map<String, Object?> kExercises = {
  'chest': [
    {
      'name': '바벨 벤치프레스',
      'equip': 'barbell',
      'pattern': 'push',
      'note': '견갑 고정, 바가 명치 아래',
    },
    {
      'name': '인클라인 덤벨프레스',
      'equip': 'dumbbell',
      'pattern': 'push',
      'note': '30~40도, 상부 자극',
    },
    {
      'name': '딥스',
      'equip': 'bodyweight',
      'pattern': 'push',
      'note': '몸 앞으로 기울이면 가슴',
    },
    {
      'name': '체스트 프레스 머신',
      'equip': 'machine',
      'pattern': 'push',
      'note': '등을 패드에 붙이고 손잡이는 가슴 높이',
    },
    {
      'name': '푸시업',
      'equip': 'bodyweight',
      'pattern': 'push',
      'note': '손은 어깨 너비, 몸은 일직선',
    },
  ],
  'back': [
    {
      'name': '풀업 / 랫풀다운',
      'equip': 'machine',
      'pattern': 'pull',
      'note': '견갑 하강 먼저',
    },
    {
      'name': '바벨 로우',
      'equip': 'barbell',
      'pattern': 'pull',
      'note': '허리 중립 유지',
    },
    {
      'name': '시티드 케이블로우',
      'equip': 'machine',
      'pattern': 'pull',
      'note': '반동 금지',
    },
    {
      'name': '원암 덤벨로우',
      'equip': 'dumbbell',
      'pattern': 'pull',
      'note': '좌우 불균형 교정에 유리',
    },
  ],
  'shoulder': [
    {
      'name': '오버헤드 프레스',
      'equip': 'barbell',
      'pattern': 'push',
      'note': '갈비뼈 들리지 않게',
    },
    {
      'name': '사이드 레터럴레이즈',
      'equip': 'dumbbell',
      'pattern': 'push',
      'note': '가볍게 고반복',
    },
    {
      'name': '페이스풀',
      'equip': 'machine',
      'pattern': 'pull',
      'note': '어깨 건강 필수',
    },
  ],
  'arms': [
    {
      'name': '바벨 컬',
      'equip': 'barbell',
      'pattern': 'pull',
      'note': '',
    },
    {
      'name': '인클라인 덤벨컬',
      'equip': 'dumbbell',
      'pattern': 'pull',
      'note': '',
    },
    {
      'name': '케이블 푸시다운',
      'equip': 'machine',
      'pattern': 'push',
      'note': '',
    },
    {
      'name': '오버헤드 익스텐션',
      'equip': 'dumbbell',
      'pattern': 'push',
      'note': '',
    },
  ],
  'quads': [
    {
      'name': '바벨 스쿼트',
      'equip': 'barbell',
      'pattern': 'squat',
      'note': '무릎 발끝 방향',
    },
    {
      'name': '레그프레스',
      'equip': 'machine',
      'pattern': 'squat',
      'note': '허리 뜨지 않게',
    },
    {
      'name': '불가리안 스플릿스쿼트',
      'equip': 'dumbbell',
      'pattern': 'lunge',
      'note': '좌우 불균형 교정',
    },
    {
      'name': '레그 익스텐션',
      'equip': 'machine',
      'pattern': 'isolation',
      'note': '',
    },
  ],
  'hamsGlutes': [
    {
      'name': '루마니안 데드리프트',
      'equip': 'barbell',
      'pattern': 'hinge',
      'note': '햄스트링 신장 느끼기',
    },
    {
      'name': '힙 쓰러스트',
      'equip': 'barbell',
      'pattern': 'hinge',
      'note': '',
    },
    {
      'name': '레그 컬',
      'equip': 'machine',
      'pattern': 'isolation',
      'note': '',
    },
  ],
  'core': [
    {
      'name': '행잉 레그레이즈',
      'equip': 'bodyweight',
      'pattern': 'core',
      'note': '',
    },
    {
      'name': '케이블 크런치',
      'equip': 'machine',
      'pattern': 'core',
      'note': '',
    },
    {
      'name': '플랭크',
      'equip': 'bodyweight',
      'pattern': 'core',
      'note': '',
    },
  ],
};

/// 한식 기반 식품 DB (100g 또는 1인분 기준)
const List<Object?> kFoods = [
  {
    'name': '닭가슴살(생)',
    'unit': '100g',
    'kcal': 109.0,
    'p': 23.0,
    'c': 0.0,
    'f': 1.4,
    'tags': [
      'protein',
    ],
  },
  {
    'name': '소고기 우둔',
    'unit': '100g',
    'kcal': 130.0,
    'p': 21.0,
    'c': 0.0,
    'f': 4.6,
    'tags': [
      'protein',
    ],
  },
  {
    'name': '돼지 뒷다리살',
    'unit': '100g',
    'kcal': 128.0,
    'p': 21.0,
    'c': 0.0,
    'f': 4.4,
    'tags': [
      'protein',
    ],
  },
  {
    'name': '고등어구이',
    'unit': '100g',
    'kcal': 183.0,
    'p': 20.0,
    'c': 0.0,
    'f': 11.0,
    'tags': [
      'protein',
      'omega3',
    ],
  },
  {
    'name': '연어',
    'unit': '100g',
    'kcal': 208.0,
    'p': 20.0,
    'c': 0.0,
    'f': 13.0,
    'tags': [
      'protein',
      'omega3',
    ],
  },
  {
    'name': '계란(1개)',
    'unit': '1개',
    'kcal': 72.0,
    'p': 6.3,
    'c': 0.4,
    'f': 4.8,
    'tags': [
      'protein',
    ],
  },
  {
    'name': '두부(부침용)',
    'unit': '100g',
    'kcal': 97.0,
    'p': 9.6,
    'c': 2.6,
    'f': 5.4,
    'tags': [
      'protein',
      'vegetarian',
    ],
  },
  {
    'name': '그릭요거트 무가당',
    'unit': '100g',
    'kcal': 59.0,
    'p': 10.0,
    'c': 3.6,
    'f': 0.4,
    'tags': [
      'protein',
      'dairy',
    ],
  },
  {
    'name': '유청단백 1스쿱',
    'unit': '30g',
    'kcal': 120.0,
    'p': 24.0,
    'c': 2.0,
    'f': 1.5,
    'tags': [
      'protein',
      'supplement',
    ],
  },
  {
    'name': '현미밥',
    'unit': '210g(1공기)',
    'kcal': 310.0,
    'p': 6.0,
    'c': 66.0,
    'f': 2.0,
    'tags': [
      'carb',
    ],
  },
  {
    'name': '백미밥',
    'unit': '210g(1공기)',
    'kcal': 313.0,
    'p': 5.5,
    'c': 69.0,
    'f': 0.6,
    'tags': [
      'carb',
    ],
  },
  {
    'name': '고구마',
    'unit': '150g',
    'kcal': 193.0,
    'p': 2.0,
    'c': 45.0,
    'f': 0.3,
    'tags': [
      'carb',
    ],
  },
  {
    'name': '귀리(오트밀)',
    'unit': '60g',
    'kcal': 228.0,
    'p': 8.0,
    'c': 39.0,
    'f': 4.0,
    'tags': [
      'carb',
    ],
  },
  {
    'name': '통밀식빵',
    'unit': '2쪽',
    'kcal': 160.0,
    'p': 6.0,
    'c': 28.0,
    'f': 2.4,
    'tags': [
      'carb',
    ],
  },
  {
    'name': '아몬드',
    'unit': '20g',
    'kcal': 116.0,
    'p': 4.2,
    'c': 4.4,
    'f': 10.0,
    'tags': [
      'fat',
      'nuts',
    ],
  },
  {
    'name': '올리브유',
    'unit': '1큰술',
    'kcal': 119.0,
    'p': 0.0,
    'c': 0.0,
    'f': 13.5,
    'tags': [
      'fat',
    ],
  },
  {
    'name': '아보카도',
    'unit': '1/2개',
    'kcal': 160.0,
    'p': 2.0,
    'c': 8.5,
    'f': 14.7,
    'tags': [
      'fat',
    ],
  },
  {
    'name': '된장국(건더기)',
    'unit': '1그릇',
    'kcal': 65.0,
    'p': 4.5,
    'c': 6.0,
    'f': 2.5,
    'tags': [
      'soup',
    ],
  },
  {
    'name': '미역국',
    'unit': '1그릇',
    'kcal': 80.0,
    'p': 6.0,
    'c': 4.0,
    'f': 4.0,
    'tags': [
      'soup',
    ],
  },
  {
    'name': '배추김치',
    'unit': '50g',
    'kcal': 16.0,
    'p': 1.0,
    'c': 2.4,
    'f': 0.3,
    'tags': [
      'side',
    ],
  },
  {
    'name': '시금치나물',
    'unit': '70g',
    'kcal': 45.0,
    'p': 2.5,
    'c': 3.0,
    'f': 2.5,
    'tags': [
      'side',
    ],
  },
  {
    'name': '브로콜리 데침',
    'unit': '100g',
    'kcal': 34.0,
    'p': 2.8,
    'c': 6.6,
    'f': 0.4,
    'tags': [
      'side',
    ],
  },
  {
    'name': '샐러드채소',
    'unit': '100g',
    'kcal': 20.0,
    'p': 1.5,
    'c': 3.0,
    'f': 0.2,
    'tags': [
      'side',
    ],
  },
];

/// 외식·편의점 가이드
const List<Object?> kEatingOut = [
  {
    'name': '백반 (생선구이정식)',
    'kcal': 700.0,
    'p': 40.0,
    'tip': '밥 2/3공기, 국물 적게',
  },
  {
    'name': '삼겹살 200g + 밥',
    'kcal': 1100.0,
    'p': 45.0,
    'tip': '상추쌈 위주, 밥 1/2',
  },
  {
    'name': '순대국밥',
    'kcal': 700.0,
    'p': 35.0,
    'tip': '건더기 위주, 국물 남기기',
  },
  {
    'name': '편의점 닭가슴살+삶은계란2+바나나',
    'kcal': 380.0,
    'p': 38.0,
    'tip': '급할 때 최적',
  },
  {
    'name': '서브웨이 로티세리치킨 15cm',
    'kcal': 350.0,
    'p': 27.0,
    'tip': '소스 머스타드/할라피뇨',
  },
  {
    'name': '김밥 1줄',
    'kcal': 480.0,
    'p': 12.0,
    'tip': '단백질 따로 추가 필요',
  },
];
