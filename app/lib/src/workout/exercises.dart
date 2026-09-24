/* =============================================================================
 * exercises.dart — 운동 종목 사전
 *
 * 엔진(packages/mybody_core/lib/data.dart 의 kExercises)이 고르는 26개 종목에
 * 집·맨몸·밴드 대체 종목을 더한 것입니다. 엔진은 "무엇을 할지" 만 정하고,
 * 그 종목이 **내 헬스장에 있는지, 집에서 되는지** 는 모릅니다. 그 빈 자리를
 * 여기서 메웁니다 — 같은 부위·같은 움직임의 다른 종목을 찾을 수 있게
 * 부위(group)·기구(equip)·움직임(pattern)을 하나하나 답니다.
 *
 * 엔진 종목의 이름·메모는 data.dart 와 **글자 그대로** 같아야 합니다.
 * 한 글자라도 다르면 exerciseByName 이 못 찾고, 못 찾으면 대체가 안 됩니다.
 *
 * MET 는 2011 Compendium of Physical Activities 를 따릅니다
 * (Ainsworth 등, MSSE 2011): 근력운동 격렬 6.0 · 보통 3.5, 맨몸 서킷 8.0,
 * 줄넘기 11.0, 플랭크 같은 정적 코어 2.8~3.8. 종목마다 그 범위 안에서
 * 무게·관절 수에 따라 매겼습니다. 세트 사이 쉬는 시간이 섞인 값이라
 * "이 종목 10분 = 이만큼" 의 어림일 뿐입니다.
 * ========================================================================== */
library;

/// 종목 하나.
class Exercise {
  final String id;
  final String name;
  /// 부위 — chest · back · shoulder · arms · quads · hamsGlutes · core · full.
  final String group;
  /// 기구 — kEquipLabel 의 키 중 하나.
  final String equip;
  /// 움직임. 대체 종목을 고를 때 "같은 부위" 다음으로 봅니다 —
  /// 벤치프레스를 빼면 플라이보다 푸시업이 더 가깝습니다.
  final String pattern;
  final double met;
  final String? note;
  final List<String> muscles;
  /// 철봉·평행봉처럼 매달리거나 짚을 **고정 기구**가 있어야 하는가.
  /// 맨몸 종목이지만 집에서는 대개 못 합니다.
  final bool needsBar;

  const Exercise({
    required this.id,
    required this.name,
    required this.group,
    required this.equip,
    this.pattern = '',
    required this.met,
    this.note,
    this.muscles = const [],
    this.needsBar = false,
  });

  /// 머신·케이블은 "헬스장 기구 몇 개까지" 셀 때 한 묶음입니다.
  bool get isMachine => equip == 'machine' || equip == 'cable';
}

/// 기구 이름표. 설정 화면의 체크 목록이 이 순서로 그립니다.
const Map<String, String> kEquipLabel = {
  'barbell': '바벨',
  'dumbbell': '덤벨',
  'machine': '머신',
  'cable': '케이블',
  'bodyweight': '맨몸',
  'band': '밴드',
  'kettlebell': '케틀벨',
};

/// 부위 이름표.
const Map<String, String> kGroupLabel = {
  'chest': '가슴',
  'back': '등',
  'shoulder': '어깨',
  'arms': '팔',
  'quads': '허벅지 앞',
  'hamsGlutes': '허벅지 뒤·엉덩이',
  'core': '코어',
  'full': '전신',
};

/// 종목 사전. 부위별로 엔진 종목이 먼저, 대체 종목이 뒤에 옵니다 —
/// 대체를 고를 때 앞에 있는 것부터 보므로 순서가 곧 우선순위입니다.
const List<Exercise> kExerciseLibrary = [
  // --- 가슴 -----------------------------------------------------------------
  Exercise(id: 'bench-press', name: '바벨 벤치프레스', group: 'chest', equip: 'barbell',
      pattern: 'push-h', met: 6.0, note: '견갑 고정, 바가 명치 아래',
      muscles: ['가슴', '삼두', '어깨 앞']),
  Exercise(id: 'incline-db-press', name: '인클라인 덤벨프레스', group: 'chest', equip: 'dumbbell',
      pattern: 'push-h', met: 5.0, note: '30~40도, 상부 자극',
      muscles: ['가슴 위쪽', '어깨 앞', '삼두']),
  Exercise(id: 'dips', name: '딥스', group: 'chest', equip: 'bodyweight',
      pattern: 'push-v', met: 5.0, note: '몸 앞으로 기울이면 가슴',
      muscles: ['가슴 아래쪽', '삼두'], needsBar: true),
  Exercise(id: 'chest-press-machine', name: '체스트 프레스 머신', group: 'chest', equip: 'machine',
      pattern: 'push-h', met: 3.5, note: '초보/마무리용', muscles: ['가슴', '삼두']),
  Exercise(id: 'push-up', name: '푸시업', group: 'chest', equip: 'bodyweight',
      pattern: 'push-h', met: 3.8, note: '홈트 대체', muscles: ['가슴', '삼두', '코어']),
  Exercise(id: 'incline-push-up', name: '인클라인 푸시업', group: 'chest', equip: 'bodyweight',
      pattern: 'push-h', met: 3.5, note: '손을 의자·탁자에 올려 부담을 줄임',
      muscles: ['가슴', '삼두']),
  Exercise(id: 'decline-push-up', name: '디클라인 푸시업', group: 'chest', equip: 'bodyweight',
      pattern: 'push-h', met: 4.5, note: '발을 의자에 올려 더 어렵게',
      muscles: ['가슴 위쪽', '어깨 앞', '삼두']),
  Exercise(id: 'db-floor-press', name: '덤벨 플로어프레스', group: 'chest', equip: 'dumbbell',
      pattern: 'push-h', met: 4.5, note: '벤치가 없을 때 바닥에 누워서',
      muscles: ['가슴', '삼두']),
  Exercise(id: 'band-chest-press', name: '밴드 체스트프레스', group: 'chest', equip: 'band',
      pattern: 'push-h', met: 3.5, note: '밴드를 등 뒤로 걸고', muscles: ['가슴', '삼두']),
  Exercise(id: 'cable-fly', name: '케이블 플라이', group: 'chest', equip: 'cable',
      pattern: 'fly', met: 3.5, note: '팔꿈치 살짝 굽힌 채 고정', muscles: ['가슴']),
  Exercise(id: 'db-fly', name: '덤벨 플라이', group: 'chest', equip: 'dumbbell',
      pattern: 'fly', met: 3.5, note: '가볍게 · 어깨가 아프면 중단', muscles: ['가슴']),

  // --- 등 -------------------------------------------------------------------
  Exercise(id: 'pullup-latpulldown', name: '풀업 / 랫풀다운', group: 'back', equip: 'machine',
      pattern: 'pull-v', met: 4.0, note: '견갑 하강 먼저', muscles: ['광배근', '이두']),
  Exercise(id: 'barbell-row', name: '바벨 로우', group: 'back', equip: 'barbell',
      pattern: 'pull-h', met: 5.0, note: '허리 중립 유지', muscles: ['광배근', '승모근', '허리']),
  Exercise(id: 'seated-cable-row', name: '시티드 케이블로우', group: 'back', equip: 'cable',
      pattern: 'pull-h', met: 3.5, note: '반동 금지', muscles: ['광배근', '능형근']),
  Exercise(id: 'one-arm-db-row', name: '원암 덤벨로우', group: 'back', equip: 'dumbbell',
      pattern: 'pull-h', met: 4.5, note: '좌우 불균형 교정에 유리', muscles: ['광배근', '이두']),
  Exercise(id: 'pull-up', name: '풀업', group: 'back', equip: 'bodyweight',
      pattern: 'pull-v', met: 6.0, note: '철봉이 있을 때 · 안 되면 밴드 풀다운',
      muscles: ['광배근', '이두'], needsBar: true),
  Exercise(id: 'band-pulldown', name: '밴드 풀다운', group: 'back', equip: 'band',
      pattern: 'pull-v', met: 3.5, note: '문 위에 걸고 당김', muscles: ['광배근']),
  Exercise(id: 'inverted-row', name: '인버티드 로우', group: 'back', equip: 'bodyweight',
      pattern: 'pull-h', met: 3.8, note: '튼튼한 책상 밑에서 몸을 당김',
      muscles: ['등 위쪽', '이두']),
  Exercise(id: 'band-row', name: '밴드 로우', group: 'back', equip: 'band',
      pattern: 'pull-h', met: 3.5, note: '앉아서 발에 걸고', muscles: ['광배근', '능형근']),
  Exercise(id: 'superman', name: '슈퍼맨', group: 'back', equip: 'bodyweight',
      pattern: 'extension', met: 2.8, note: '엎드려 팔다리 들기 · 허리 과신전 금지',
      muscles: ['허리', '엉덩이', '등']),
  Exercise(id: 'prone-y-raise', name: '프론 Y레이즈', group: 'back', equip: 'bodyweight',
      pattern: 'pull-v', met: 2.8, note: '엎드려 팔을 Y자로 들기', muscles: ['등 위쪽', '어깨 뒤']),
  Exercise(id: 'reverse-snow-angel', name: '리버스 스노우엔젤', group: 'back', equip: 'bodyweight',
      pattern: 'pull-h', met: 2.8, note: '엎드려 팔을 천천히 반원으로',
      muscles: ['등 위쪽', '어깨 뒤']),

  // --- 어깨 -----------------------------------------------------------------
  Exercise(id: 'overhead-press', name: '오버헤드 프레스', group: 'shoulder', equip: 'barbell',
      pattern: 'push-v', met: 5.0, note: '갈비뼈 들리지 않게', muscles: ['어깨', '삼두']),
  Exercise(id: 'lateral-raise', name: '사이드 레터럴레이즈', group: 'shoulder', equip: 'dumbbell',
      pattern: 'raise', met: 3.5, note: '가볍게 고반복', muscles: ['어깨 옆']),
  Exercise(id: 'face-pull', name: '페이스풀', group: 'shoulder', equip: 'cable',
      pattern: 'pull-h', met: 3.5, note: '어깨 건강 필수', muscles: ['어깨 뒤', '능형근']),
  Exercise(id: 'db-shoulder-press', name: '덤벨 숄더프레스', group: 'shoulder', equip: 'dumbbell',
      pattern: 'push-v', met: 4.5, note: '앉아서 하면 허리 부담이 줄어듦', muscles: ['어깨', '삼두']),
  Exercise(id: 'pike-push-up', name: '파이크 푸시업', group: 'shoulder', equip: 'bodyweight',
      pattern: 'push-v', met: 4.0, note: '엉덩이를 높이 들고 머리를 바닥 쪽으로',
      muscles: ['어깨', '삼두']),
  Exercise(id: 'band-face-pull', name: '밴드 페이스풀', group: 'shoulder', equip: 'band',
      pattern: 'pull-h', met: 3.5, note: '문에 걸고 얼굴 쪽으로', muscles: ['어깨 뒤', '능형근']),
  Exercise(id: 'rear-delt-raise', name: '덤벨 리어델트 레이즈', group: 'shoulder', equip: 'dumbbell',
      pattern: 'raise', met: 3.5, note: '상체 숙이고 가볍게', muscles: ['어깨 뒤']),
  Exercise(id: 'band-lateral-raise', name: '밴드 레터럴레이즈', group: 'shoulder', equip: 'band',
      pattern: 'raise', met: 3.5, note: '발로 밟고 옆으로', muscles: ['어깨 옆']),

  // --- 팔 -------------------------------------------------------------------
  Exercise(id: 'barbell-curl', name: '바벨 컬', group: 'arms', equip: 'barbell',
      pattern: 'curl', met: 3.5, note: '', muscles: ['이두']),
  Exercise(id: 'incline-db-curl', name: '인클라인 덤벨컬', group: 'arms', equip: 'dumbbell',
      pattern: 'curl', met: 3.5, note: '', muscles: ['이두']),
  Exercise(id: 'cable-pushdown', name: '케이블 푸시다운', group: 'arms', equip: 'cable',
      pattern: 'extension', met: 3.5, note: '', muscles: ['삼두']),
  Exercise(id: 'overhead-extension', name: '오버헤드 익스텐션', group: 'arms', equip: 'dumbbell',
      pattern: 'extension', met: 3.5, note: '', muscles: ['삼두']),
  Exercise(id: 'db-curl', name: '덤벨 컬', group: 'arms', equip: 'dumbbell',
      pattern: 'curl', met: 3.5, note: '반동 없이', muscles: ['이두']),
  Exercise(id: 'band-curl', name: '밴드 컬', group: 'arms', equip: 'band',
      pattern: 'curl', met: 3.5, note: '발로 밟고', muscles: ['이두']),
  Exercise(id: 'db-kickback', name: '덤벨 킥백', group: 'arms', equip: 'dumbbell',
      pattern: 'extension', met: 3.5, note: '팔꿈치 고정', muscles: ['삼두']),
  Exercise(id: 'diamond-push-up', name: '다이아몬드 푸시업', group: 'arms', equip: 'bodyweight',
      pattern: 'extension', met: 4.5, note: '손을 모아 삼두 자극', muscles: ['삼두', '가슴']),
  Exercise(id: 'bench-dips', name: '벤치 딥스', group: 'arms', equip: 'bodyweight',
      pattern: 'extension', met: 4.0, note: '의자 끝을 잡고 · 어깨가 아프면 중단',
      muscles: ['삼두', '가슴 아래쪽']),

  // --- 허벅지 앞 -------------------------------------------------------------
  Exercise(id: 'barbell-squat', name: '바벨 스쿼트', group: 'quads', equip: 'barbell',
      pattern: 'squat', met: 6.0, note: '무릎 발끝 방향', muscles: ['허벅지 앞', '엉덩이', '코어']),
  Exercise(id: 'leg-press', name: '레그프레스', group: 'quads', equip: 'machine',
      pattern: 'squat', met: 4.0, note: '허리 뜨지 않게', muscles: ['허벅지 앞', '엉덩이']),
  Exercise(id: 'bulgarian-split-squat', name: '불가리안 스플릿스쿼트', group: 'quads', equip: 'dumbbell',
      pattern: 'lunge', met: 5.0, note: '좌우 불균형 교정', muscles: ['허벅지 앞', '엉덩이']),
  Exercise(id: 'leg-extension', name: '레그 익스텐션', group: 'quads', equip: 'machine',
      pattern: 'isolation', met: 3.5, note: '', muscles: ['허벅지 앞']),
  Exercise(id: 'goblet-squat', name: '고블릿 스쿼트', group: 'quads', equip: 'dumbbell',
      pattern: 'squat', met: 5.0, note: '덤벨을 가슴 앞에 안고', muscles: ['허벅지 앞', '엉덩이']),
  Exercise(id: 'bodyweight-squat', name: '맨몸 스쿼트', group: 'quads', equip: 'bodyweight',
      pattern: 'squat', met: 3.8, note: '발뒤꿈치 붙이고 천천히', muscles: ['허벅지 앞', '엉덩이']),
  Exercise(id: 'jump-squat', name: '점프 스쿼트', group: 'quads', equip: 'bodyweight',
      pattern: 'squat', met: 8.0, note: '착지는 조용히', muscles: ['허벅지 앞', '엉덩이', '심폐']),
  Exercise(id: 'lunge', name: '런지', group: 'quads', equip: 'bodyweight',
      pattern: 'lunge', met: 3.8, note: '앞 무릎이 발끝을 넘지 않게', muscles: ['허벅지 앞', '엉덩이']),
  Exercise(id: 'split-squat', name: '스플릿 스쿼트', group: 'quads', equip: 'bodyweight',
      pattern: 'lunge', met: 4.0, note: '제자리에서 한 발을 앞에 두고', muscles: ['허벅지 앞', '엉덩이']),
  Exercise(id: 'step-up', name: '스텝업', group: 'quads', equip: 'bodyweight',
      pattern: 'lunge', met: 5.0, note: '의자·계단에 올라섰다 내려오기', muscles: ['허벅지 앞', '엉덩이']),
  Exercise(id: 'wall-sit', name: '월 싯', group: 'quads', equip: 'bodyweight',
      pattern: 'hold', met: 3.5, note: '벽에 등을 대고 앉은 자세 유지', muscles: ['허벅지 앞']),

  // --- 허벅지 뒤·엉덩이 -------------------------------------------------------
  Exercise(id: 'rdl', name: '루마니안 데드리프트', group: 'hamsGlutes', equip: 'barbell',
      pattern: 'hinge', met: 6.0, note: '햄스트링 신장 느끼기', muscles: ['허벅지 뒤', '엉덩이', '허리']),
  Exercise(id: 'hip-thrust', name: '힙 쓰러스트', group: 'hamsGlutes', equip: 'barbell',
      pattern: 'hinge', met: 5.0, note: '', muscles: ['엉덩이', '허벅지 뒤']),
  Exercise(id: 'leg-curl', name: '레그 컬', group: 'hamsGlutes', equip: 'machine',
      pattern: 'isolation', met: 3.5, note: '', muscles: ['허벅지 뒤']),
  Exercise(id: 'db-rdl', name: '덤벨 루마니안 데드리프트', group: 'hamsGlutes', equip: 'dumbbell',
      pattern: 'hinge', met: 5.0, note: '무릎 살짝 굽히고 엉덩이를 뒤로', muscles: ['허벅지 뒤', '엉덩이']),
  Exercise(id: 'kettlebell-swing', name: '케틀벨 스윙', group: 'hamsGlutes', equip: 'kettlebell',
      pattern: 'hinge', met: 8.0, note: '팔이 아니라 엉덩이로 던짐', muscles: ['엉덩이', '허벅지 뒤', '심폐']),
  Exercise(id: 'glute-bridge', name: '글루트 브릿지', group: 'hamsGlutes', equip: 'bodyweight',
      pattern: 'hinge', met: 3.5, note: '누워서 엉덩이 들기 · 위에서 1초', muscles: ['엉덩이', '허벅지 뒤']),
  Exercise(id: 'single-leg-glute-bridge', name: '싱글레그 글루트브릿지', group: 'hamsGlutes',
      equip: 'bodyweight', pattern: 'hinge', met: 4.0, note: '한 발로 · 골반 수평',
      muscles: ['엉덩이', '허벅지 뒤']),
  Exercise(id: 'calf-raise', name: '카프 레이즈', group: 'hamsGlutes', equip: 'bodyweight',
      pattern: 'isolation', met: 3.5, note: '계단 끝에 서서', muscles: ['종아리']),

  // --- 코어 -----------------------------------------------------------------
  Exercise(id: 'hanging-leg-raise', name: '행잉 레그레이즈', group: 'core', equip: 'bodyweight',
      pattern: 'core', met: 3.8, note: '', muscles: ['복근'], needsBar: true),
  Exercise(id: 'cable-crunch', name: '케이블 크런치', group: 'core', equip: 'cable',
      pattern: 'core', met: 3.5, note: '', muscles: ['복근']),
  Exercise(id: 'plank', name: '플랭크', group: 'core', equip: 'bodyweight',
      pattern: 'hold', met: 3.3, note: '엉덩이가 처지지 않게', muscles: ['복근', '코어']),
  Exercise(id: 'lying-leg-raise', name: '라잉 레그레이즈', group: 'core', equip: 'bodyweight',
      pattern: 'core', met: 3.8, note: '허리가 뜨면 무릎을 굽히기', muscles: ['복근 아래쪽']),
  Exercise(id: 'dead-bug', name: '데드버그', group: 'core', equip: 'bodyweight',
      pattern: 'core', met: 2.8, note: '허리를 바닥에 붙이고 반대 팔다리', muscles: ['복근', '코어']),
  Exercise(id: 'bird-dog', name: '버드독', group: 'core', equip: 'bodyweight',
      pattern: 'core', met: 2.8, note: '네발 자세에서 반대 팔다리', muscles: ['허리', '코어']),
  Exercise(id: 'side-plank', name: '사이드 플랭크', group: 'core', equip: 'bodyweight',
      pattern: 'hold', met: 3.3, note: '골반 들고 좌우 각각', muscles: ['옆구리', '코어']),
  Exercise(id: 'hollow-hold', name: '할로우 홀드', group: 'core', equip: 'bodyweight',
      pattern: 'hold', met: 3.5, note: '허리를 바닥에 붙이고', muscles: ['복근']),
  Exercise(id: 'crunch', name: '크런치', group: 'core', equip: 'bodyweight',
      pattern: 'core', met: 2.8, note: '목을 당기지 않기', muscles: ['복근']),
  Exercise(id: 'plank-shoulder-tap', name: '플랭크 숄더탭', group: 'core', equip: 'bodyweight',
      pattern: 'core', met: 3.8, note: '골반이 흔들리지 않게', muscles: ['코어', '어깨']),
  Exercise(id: 'mountain-climber', name: '마운틴 클라이머', group: 'core', equip: 'bodyweight',
      pattern: 'core', met: 8.0, note: '빠르게 무릎 당기기', muscles: ['코어', '심폐']),

  // --- 전신 (맨몸 서킷) -------------------------------------------------------
  Exercise(id: 'burpee', name: '버피', group: 'full', equip: 'bodyweight',
      pattern: 'full', met: 8.0, note: '힘들면 점프 생략', muscles: ['전신', '심폐']),
  Exercise(id: 'jumping-jack', name: '점핑잭', group: 'full', equip: 'bodyweight',
      pattern: 'full', met: 8.0, note: '', muscles: ['전신', '심폐']),
  Exercise(id: 'high-knees', name: '하이니', group: 'full', equip: 'bodyweight',
      pattern: 'full', met: 8.0, note: '제자리에서 무릎 높이', muscles: ['심폐', '코어']),
  Exercise(id: 'jump-rope', name: '줄넘기', group: 'full', equip: 'bodyweight',
      pattern: 'full', met: 11.0, note: '', muscles: ['종아리', '심폐']),
  Exercise(id: 'bear-crawl', name: '베어 크롤', group: 'full', equip: 'bodyweight',
      pattern: 'full', met: 5.0, note: '무릎을 살짝 띄우고 기어가기', muscles: ['전신', '코어']),
];

/// 고유번호로 찾기.
Exercise? exerciseById(String id) {
  for (final e in kExerciseLibrary) {
    if (e.id == id) return e;
  }
  return null;
}

/// 이름으로 찾기. 글자 그대로 먼저, 없으면 느슨하게 —
/// 띄어쓰기를 무시하고, '풀업 / 랫풀다운' 처럼 '/' 로 묶인 이름은 어느 쪽으로
/// 불러도 찾습니다. 엔진 종목은 전부 글자 그대로 있어서 첫 단계에서 끝납니다.
Exercise? exerciseByName(String name) {
  final q = name.trim();
  if (q.isEmpty) return null;
  for (final e in kExerciseLibrary) {
    if (e.name == q) return e;
  }
  final qn = _loose(q);
  for (final e in kExerciseLibrary) {
    if (_loose(e.name) == qn) return e;
  }
  final qParts = _parts(q);
  for (final e in kExerciseLibrary) {
    final parts = _parts(e.name);
    for (final p in qParts) {
      if (parts.contains(p)) return e;
    }
  }
  return null;
}

/// 부위별 종목. equip 을 주면 그 기구로 되는 것만.
List<Exercise> exercisesFor(String group, {Set<String>? equip}) => [
      for (final e in kExerciseLibrary)
        if (e.group == group && (equip == null || equip.contains(e.equip))) e,
    ];

/// 사전에 없는 이름에 붙일 고유번호. 같은 이름이면 언제나 같은 값입니다 —
/// 화면의 체크 상태가 이 값에 매달리므로 흔들리면 안 됩니다.
String slugOf(String name) {
  final s = name.trim().toLowerCase()
      .replaceAll(RegExp(r'[^0-9a-z가-힣]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return s.isEmpty ? 'exercise' : s;
}

String _loose(String s) => s.replaceAll(RegExp(r'\s+'), '').toLowerCase();

List<String> _parts(String s) => [
      for (final p in s.split('/'))
        if (_loose(p).isNotEmpty) _loose(p),
    ];
