/* =============================================================================
 * data.js — 시드 데이터
 * 오너의 실제 InBody270 결과지에서 추출한 값 + 프로토타입용 운동/식품 DB
 * (회원번호는 휴대폰 번호이므로 의도적으로 제외함)
 * ========================================================================== */
(function (global) {
  'use strict';

  /* --- 오너 프로필 (실제 시트 기준) -------------------------------------- */
  var SEED_PROFILE = {
    sex: 'male',
    age: 22,
    heightCm: 187,
    activityLevel: 'moderate',   // sedentary|light|moderate|active|veryActive
    trainingAge: 'novice',       // 첫 측정이 2026-06-30 이므로 6개월 미만 (novice|intermediate|advanced|elite)
    daysPerWeek: 4,
    sessionMinutes: 60,
    environment: 'gym',          // gym|home|hybrid
    injuries: '',
    dietFlags: [],               // vegetarian|lactoseFree|shellfish|nuts|halal
    mealsPerDay: 3,
    cookingLevel: 'simple',      // none|simple|free
    hadPriorPeak: false
  };

  /* --- 실측 스캔 3건 ------------------------------------------------------ */
  // 2026-09-19 건은 전체 시트, 앞의 2건은 '신체변화' 그래프에서 읽은 부분 데이터
  var SEED_SCANS = [
    {
      id: 'scan-20260630',
      measuredAt: '2026-06-30T07:36:00+09:00',
      source: 'chart',           // 신체변화 그래프에서 복원
      device: 'InBody270',
      weightKg: 89.0, smmKg: 36.2, pbfPct: 28.4,
      bfmKg: 25.3,               // 89.0 × 28.4% (파생)
      ffmKg: 63.7,
      partial: true
    },
    {
      id: 'scan-20260831',
      measuredAt: '2026-08-31T08:35:00+09:00',
      source: 'chart',
      device: 'InBody270',
      weightKg: 86.9, smmKg: 37.4, pbfPct: 24.2,
      bfmKg: 21.0,
      ffmKg: 65.9,
      partial: true
    },
    {
      id: 'scan-20260919',
      measuredAt: '2026-09-19T11:09:00+09:00',
      source: 'sheet',           // 전체 결과지
      device: 'InBody270',
      partial: false,
      // 체성분분석
      tbwL: 48.7,      tbwRange: [43.3, 52.9],
      proteinKg: 13.3, proteinRange: [11.6, 14.2],
      mineralKg: 4.70, mineralRange: [4.00, 4.89],
      bfmKg: 20.0,     bfmRange: [9.2, 18.5],
      weightKg: 86.7,  weightRange: [65.4, 88.4],
      // 골격근·지방분석
      smmKg: 37.9,
      // 비만분석
      bmi: 24.8,
      pbfPct: 23.1,
      // 우측 패널
      inbodyScore: 73,
      idealWeightKg: 78.4,
      weightControlKg: -8.3,
      fatControlKg: -8.3,
      muscleControlKg: 0.0,
      bmiGrade: '과체중',
      pbfGrade: '경도비만',
      whr: 0.94,
      visceralFatLevel: 8,
      ffmKg: 66.7,     ffmRange: [58.9, 71.9],
      bmrKcal: 1810,   bmrRange: [1803, 2121],
      obesityDegreePct: 113,
      recommendedIntakeKcal: 3104,
      // 부위별
      segmentalLean: { rightArm: '표준', leftArm: '표준', trunk: '표준', rightLeg: '표준', leftLeg: '표준' },
      segmentalFat:  { rightArm: '표준이상', leftArm: '표준이상', trunk: '표준이상', rightLeg: '표준', leftLeg: '표준' },
      // 임피던스
      impedance: {
        khz20:  { RA: 326.0, LA: 335.4, TR: 25.7, RL: 270.8, LL: 276.5 },
        khz100: { RA: 293.0, LA: 302.6, TR: 22.5, RL: 236.5, LL: 242.8 }
      }
    }
  ];

  /* --- 판독(OCR) 스텁: 신뢰도 시뮬레이션 ----------------------------------
   * 실제 OCR은 아직 없다. 프로토타입은 '판독된 척' 하면서 일부 필드를
   * 일부러 낮은 신뢰도 / 틀린 값으로 만들어, P05 검수 화면이 실제로
   * 쓸모 있는지 오너가 확인할 수 있게 한다.                                */
  var STUB_OCR_RESULT = {
    fields: {
      measuredAt: { value: '2026-09-19T11:09:00+09:00', confidence: 0.99 },
      weightKg:   { value: 86.7, confidence: 0.98 },
      smmKg:      { value: 37.9, confidence: 0.96 },
      bfmKg:      { value: 20.0, confidence: 0.94 },
      pbfPct:     { value: 23.1, confidence: 0.91 },
      bmi:        { value: 24.8, confidence: 0.88 },
      ffmKg:      { value: 66.7, confidence: 0.83 },
      bmrKcal:    { value: 1810, confidence: 0.79 },
      visceralFatLevel: { value: 8,    confidence: 0.61 },  // 🟡 중간
      whr:        { value: 0.34, confidence: 0.38 },        // 🔴 일부러 오독 (실제 0.94)
      inbodyScore:{ value: 73,   confidence: 0.72 },
      tbwL:       { value: 48.7, confidence: 0.86 },
      proteinKg:  { value: 13.3, confidence: 0.84 },
      mineralKg:  { value: null, confidence: 0.0 },         // 🔴 미검출
      idealWeightKg: { value: 78.4, confidence: 0.77 }
    },
    rawText: 'InBody270 / 187cm / 22 / 남성 / 2026.09.19. 11:09 ...',
    parseMs: 3200
  };

  /* --- 운동 종목 풀 ------------------------------------------------------- */
  var EXERCISES = {
    chest: [
      { name: '바벨 벤치프레스',   equip: 'barbell', pattern: 'push', note: '견갑 고정, 바가 명치 아래' },
      { name: '인클라인 덤벨프레스', equip: 'dumbbell', pattern: 'push', note: '30~40도, 상부 자극' },
      { name: '딥스',             equip: 'bodyweight', pattern: 'push', note: '몸 앞으로 기울이면 가슴' },
      { name: '체스트 프레스 머신', equip: 'machine', pattern: 'push', note: '초보/마무리용' },
      { name: '푸시업',            equip: 'bodyweight', pattern: 'push', note: '홈트 대체' }
    ],
    back: [
      { name: '풀업 / 랫풀다운',   equip: 'machine', pattern: 'pull', note: '견갑 하강 먼저' },
      { name: '바벨 로우',         equip: 'barbell', pattern: 'pull', note: '허리 중립 유지' },
      { name: '시티드 케이블로우', equip: 'machine', pattern: 'pull', note: '반동 금지' },
      { name: '원암 덤벨로우',     equip: 'dumbbell', pattern: 'pull', note: '좌우 불균형 교정에 유리' }
    ],
    shoulder: [
      { name: '오버헤드 프레스',   equip: 'barbell', pattern: 'push', note: '갈비뼈 들리지 않게' },
      { name: '사이드 레터럴레이즈', equip: 'dumbbell', pattern: 'push', note: '가볍게 고반복' },
      { name: '페이스풀',          equip: 'machine', pattern: 'pull', note: '어깨 건강 필수' }
    ],
    arms: [
      { name: '바벨 컬',           equip: 'barbell', pattern: 'pull', note: '' },
      { name: '인클라인 덤벨컬',   equip: 'dumbbell', pattern: 'pull', note: '' },
      { name: '케이블 푸시다운',   equip: 'machine', pattern: 'push', note: '' },
      { name: '오버헤드 익스텐션', equip: 'dumbbell', pattern: 'push', note: '' }
    ],
    quads: [
      { name: '바벨 스쿼트',       equip: 'barbell', pattern: 'squat', note: '무릎 발끝 방향' },
      { name: '레그프레스',        equip: 'machine', pattern: 'squat', note: '허리 뜨지 않게' },
      { name: '불가리안 스플릿스쿼트', equip: 'dumbbell', pattern: 'lunge', note: '좌우 불균형 교정' },
      { name: '레그 익스텐션',     equip: 'machine', pattern: 'isolation', note: '' }
    ],
    hamsGlutes: [
      { name: '루마니안 데드리프트', equip: 'barbell', pattern: 'hinge', note: '햄스트링 신장 느끼기' },
      { name: '힙 쓰러스트',       equip: 'barbell', pattern: 'hinge', note: '' },
      { name: '레그 컬',           equip: 'machine', pattern: 'isolation', note: '' }
    ],
    core: [
      { name: '행잉 레그레이즈',   equip: 'bodyweight', pattern: 'core', note: '' },
      { name: '케이블 크런치',     equip: 'machine', pattern: 'core', note: '' },
      { name: '플랭크',            equip: 'bodyweight', pattern: 'core', note: '' }
    ]
  };

  /* --- 한식 기반 식품 DB (100g 또는 1인분 기준) ---------------------------- */
  var FOODS = [
    // 단백질
    { name: '닭가슴살(생)',   unit: '100g', kcal: 109, p: 23.0, c: 0,    f: 1.4, tags: ['protein'] },
    { name: '소고기 우둔',    unit: '100g', kcal: 130, p: 21.0, c: 0,    f: 4.6, tags: ['protein'] },
    { name: '돼지 뒷다리살',  unit: '100g', kcal: 128, p: 21.0, c: 0,    f: 4.4, tags: ['protein'] },
    { name: '고등어구이',     unit: '100g', kcal: 183, p: 20.0, c: 0,    f: 11.0, tags: ['protein','omega3'] },
    { name: '연어',          unit: '100g', kcal: 208, p: 20.0, c: 0,    f: 13.0, tags: ['protein','omega3'] },
    { name: '계란(1개)',      unit: '1개',  kcal: 72,  p: 6.3,  c: 0.4,  f: 4.8, tags: ['protein'] },
    { name: '두부(부침용)',   unit: '100g', kcal: 97,  p: 9.6,  c: 2.6,  f: 5.4, tags: ['protein','vegetarian'] },
    { name: '그릭요거트 무가당', unit: '100g', kcal: 59, p: 10.0, c: 3.6, f: 0.4, tags: ['protein','dairy'] },
    { name: '유청단백 1스쿱',  unit: '30g',  kcal: 120, p: 24.0, c: 2.0,  f: 1.5, tags: ['protein','supplement'] },
    // 탄수화물
    { name: '현미밥',        unit: '210g(1공기)', kcal: 310, p: 6.0, c: 66.0, f: 2.0, tags: ['carb'] },
    { name: '백미밥',        unit: '210g(1공기)', kcal: 313, p: 5.5, c: 69.0, f: 0.6, tags: ['carb'] },
    { name: '고구마',        unit: '150g', kcal: 193, p: 2.0,  c: 45.0, f: 0.3, tags: ['carb'] },
    { name: '귀리(오트밀)',   unit: '60g',  kcal: 228, p: 8.0,  c: 39.0, f: 4.0, tags: ['carb'] },
    { name: '통밀식빵',      unit: '2쪽',  kcal: 160, p: 6.0,  c: 28.0, f: 2.4, tags: ['carb'] },
    // 지방
    { name: '아몬드',        unit: '20g',  kcal: 116, p: 4.2,  c: 4.4,  f: 10.0, tags: ['fat','nuts'] },
    { name: '올리브유',      unit: '1큰술', kcal: 119, p: 0,    c: 0,    f: 13.5, tags: ['fat'] },
    { name: '아보카도',      unit: '1/2개', kcal: 160, p: 2.0,  c: 8.5,  f: 14.7, tags: ['fat'] },
    // 채소/국
    { name: '된장국(건더기)', unit: '1그릇', kcal: 65,  p: 4.5,  c: 6.0,  f: 2.5, tags: ['soup'] },
    { name: '미역국',        unit: '1그릇', kcal: 80,  p: 6.0,  c: 4.0,  f: 4.0, tags: ['soup'] },
    { name: '배추김치',      unit: '50g',  kcal: 16,  p: 1.0,  c: 2.4,  f: 0.3, tags: ['side'] },
    { name: '시금치나물',    unit: '70g',  kcal: 45,  p: 2.5,  c: 3.0,  f: 2.5, tags: ['side'] },
    { name: '브로콜리 데침',  unit: '100g', kcal: 34,  p: 2.8,  c: 6.6,  f: 0.4, tags: ['side'] },
    { name: '샐러드채소',    unit: '100g', kcal: 20,  p: 1.5,  c: 3.0,  f: 0.2, tags: ['side'] }
  ];

  /* --- 외식/편의점 가이드 -------------------------------------------------- */
  var EATING_OUT = [
    { name: '백반 (생선구이정식)', kcal: 700,  p: 40, tip: '밥 2/3공기, 국물 적게' },
    { name: '삼겹살 200g + 밥',   kcal: 1100, p: 45, tip: '상추쌈 위주, 밥 1/2' },
    { name: '순대국밥',           kcal: 700,  p: 35, tip: '건더기 위주, 국물 남기기' },
    { name: '편의점 닭가슴살+삶은계란2+바나나', kcal: 380, p: 38, tip: '급할 때 최적' },
    { name: '서브웨이 로티세리치킨 15cm', kcal: 350, p: 27, tip: '소스 머스타드/할라피뇨' },
    { name: '김밥 1줄',           kcal: 480,  p: 12, tip: '단백질 따로 추가 필요' }
  ];

  global.MB_DATA = {
    SEED_PROFILE: SEED_PROFILE,
    SEED_SCANS: SEED_SCANS,
    STUB_OCR_RESULT: STUB_OCR_RESULT,
    EXERCISES: EXERCISES,
    FOODS: FOODS,
    EATING_OUT: EATING_OUT
  };
})(window);
