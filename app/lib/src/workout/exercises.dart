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
 *
 * 헬스장 머신은 2차 피드백(12 · 21)으로 크게 늘렸습니다 — Life Fitness ·
 * Hammer Strength · Technogym · Cybex · Precor · Matrix · Nautilus · Hoist ·
 * Panatta · gym80 · Keiser · Atlantis · Prime · DRAX · 뉴텍 제품군 조사. 규칙:
 *  - 원래 있던 항목의 id · 이름 · 순서는 **그대로**입니다. 엔진 이름 1:1,
 *    tailorSession 의 대체 우선순위(앞이 이김), 저장된 익숙한 종목 id 가
 *    전부 여기에 걸려 있습니다. 새 항목은 부위 블록의 **뒤**에만 붙입니다.
 *  - 같은 종목의 다른 표기는 새 항목이 아니라 그 항목의 aliases 입니다.
 *  - 스미스 머신 종목은 equip 'machine' 입니다 — 기구 목록에 칸을 하나 더
 *    만들지 않으려고요. '스미스 머신 …' 별칭으로 찾습니다.
 *  - pattern 은 한 어휘로 씁니다: push-h · push-v · pull-h · pull-v · fly ·
 *    raise · curl · extension · squat · lunge · hinge · isolation · hold ·
 *    core · full, 새로 abduction · adduction · rotation · carry. 힙 쓰러스트
 *    머신 같은 고관절 신전은 hinge 로 묶어 바벨 힙 쓰러스트와 서로 대체됩니다.
 *  - 무게를 걸 곳이 없는 고정 스테이션(캡틴스 체어 · 싯업 벤치 · 45도 백
 *    익스텐션 · GHR)은 equip 'bodyweight' + needsBar 입니다 — 'machine' 으로
 *    두면 무게 추천이 붙고 「하루에 쓸 머신 수」 를 하나 잡아먹습니다.
 *  - 별칭은 한 종목에만 답니다. '스미스' 처럼 여럿에 걸리는 말은 exerciseByAlias
 *    가 사전 순서에 좌우되어 뺐습니다(검색은 이름으로 여전히 찾습니다).
 *  - 새 항목끼리의 순서도 대체 우선순위입니다. 허벅지 뒤·엉덩이의 머신은
 *    힙 쓰러스트 머신 · 케이블 풀스루가 킥백류보다 앞 — 바벨 RDL · 힙
 *    쓰러스트를 머신으로 바꿀 때 초보에게 먼저 권할 것이 그것입니다.
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
  /// 같은 종목의 다른 이름 — 영문 이름, 헬스장 통칭(이너싸이 = 힙 어덕션),
  /// 브랜드 제품명(Hammer Strength Iso-Lateral Row). 검색에만 쓰고 화면에는
  /// 안 보입니다. 사람마다 부르는 말이 달라서, 이게 없으면 있는 종목을 못 찾고
  /// "없다" 고 새로 적습니다.
  final List<String> aliases;

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
    this.aliases = const [],
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
      muscles: ['가슴', '삼두', '어깨 앞'],
      aliases: ['Barbell Bench Press', '벤치프레스', '플랫 벤치프레스', '바벨 벤치']),
  Exercise(id: 'incline-db-press', name: '인클라인 덤벨프레스', group: 'chest', equip: 'dumbbell',
      pattern: 'push-h', met: 5.0, note: '30~40도, 상부 자극',
      muscles: ['가슴 위쪽', '어깨 앞', '삼두'],
      aliases: ['Incline Dumbbell Press', '인클라인 덤벨 벤치프레스']),
  Exercise(id: 'dips', name: '딥스', group: 'chest', equip: 'bodyweight',
      pattern: 'push-v', met: 5.0, note: '몸 앞으로 기울이면 가슴',
      muscles: ['가슴 아래쪽', '삼두'], needsBar: true,
      aliases: ['Dips', '딥스 바', '평행봉 딥스', '체스트 딥스']),
  Exercise(id: 'chest-press-machine', name: '체스트 프레스 머신', group: 'chest', equip: 'machine',
      pattern: 'push-h', met: 3.5, note: '등을 패드에 붙이고 손잡이는 가슴 높이', muscles: ['가슴', '삼두'],
      aliases: ['Chest Press Machine', '아이소 체스트 프레스', '와이드 체스트 프레스', '해머 체스트프레스', '플레이트 체스트프레스',
          'Hammer Strength Iso-Lateral Chest Press', 'Iso-Lateral Wide Chest',
          'Technogym Pure Wide Chest Press MG1000', 'DRAX Pure Plate Chest Press PPCP-105',
          'Atlantis P-140 Seated Converging Chest Press', '뉴텍 토크라인 와이드 체스트 프레스']),
  Exercise(id: 'push-up', name: '푸시업', group: 'chest', equip: 'bodyweight',
      pattern: 'push-h', met: 3.8, note: '손은 어깨 너비, 몸은 일직선', muscles: ['가슴', '삼두', '코어'],
      aliases: ['Push-Up', '푸쉬업', '팔굽혀펴기']),
  Exercise(id: 'incline-push-up', name: '인클라인 푸시업', group: 'chest', equip: 'bodyweight',
      pattern: 'push-h', met: 3.5, note: '손을 의자·탁자에 올려 부담을 줄임',
      muscles: ['가슴', '삼두'],
      aliases: ['Incline Push-Up', '인클라인 푸쉬업']),
  Exercise(id: 'decline-push-up', name: '디클라인 푸시업', group: 'chest', equip: 'bodyweight',
      pattern: 'push-h', met: 4.5, note: '발을 의자에 올려 더 어렵게',
      muscles: ['가슴 위쪽', '어깨 앞', '삼두'],
      aliases: ['Decline Push-Up', '디클라인 푸쉬업']),
  Exercise(id: 'db-floor-press', name: '덤벨 플로어프레스', group: 'chest', equip: 'dumbbell',
      pattern: 'push-h', met: 4.5, note: '벤치가 없을 때 바닥에 누워서',
      muscles: ['가슴', '삼두'],
      aliases: ['Dumbbell Floor Press', '플로어 프레스']),
  Exercise(id: 'band-chest-press', name: '밴드 체스트프레스', group: 'chest', equip: 'band',
      pattern: 'push-h', met: 3.5, note: '밴드를 등 뒤로 걸고', muscles: ['가슴', '삼두'],
      aliases: ['Band Chest Press']),
  Exercise(id: 'cable-fly', name: '케이블 플라이', group: 'chest', equip: 'cable',
      pattern: 'fly', met: 3.5, note: '팔꿈치 살짝 굽힌 채 고정', muscles: ['가슴'],
      aliases: ['Cable Fly', 'Cable Crossover', '케이블 크로스오버', '하이 케이블 플라이', '로우 케이블 플라이',
          '로우 풀리 플라이', '뉴텍 어드반스 케이블 크로스오버']),
  Exercise(id: 'db-fly', name: '덤벨 플라이', group: 'chest', equip: 'dumbbell',
      pattern: 'fly', met: 3.5, note: '가볍게 · 어깨가 아프면 중단', muscles: ['가슴'],
      aliases: ['Dumbbell Fly', '인클라인 덤벨 플라이']),
  /* 확장 — 헬스장 · 머신 브랜드 조사(2차 피드백 12). 앞 항목이 대체 우선순위에서 이깁니다. */
  Exercise(id: 'pec-deck', name: '펙덱 플라이', group: 'chest', equip: 'machine',
      pattern: 'fly', met: 3.5, note: '팔꿈치 살짝 굽혀 고정', muscles: ['가슴'],
      aliases: ['Pec Deck Fly', '펙덱', '버터플라이', '펙 플라이 머신', '체스트 플라이 머신', 'Pectoral Fly',
          'Butterfly', 'Technogym Pectoral Machine', 'Life Fitness Pec Fly',
          'Keiser A300 Seated Butterfly']),
  Exercise(id: 'incline-chest-press-machine', name: '인클라인 체스트 프레스 머신', group: 'chest', equip: 'machine',
      pattern: 'push-h', met: 4.0, note: '손잡이는 가슴 위쪽 높이', muscles: ['가슴 위쪽', '어깨 앞', '삼두'],
      aliases: ['Incline Chest Press Machine', '인클라인 프레스 머신', '아이소 인클라인 프레스', '해머 인클라인',
          'Hammer Strength Iso-Lateral Incline Press', 'Technogym Pure Incline Chest Press',
          'Atlantis P-143 Incline Converging Chest Press', '뉴텍 토크라인 인클라인 체스트 프레스']),
  Exercise(id: 'decline-chest-press-machine', name: '디클라인 체스트 프레스 머신', group: 'chest', equip: 'machine',
      pattern: 'push-h', met: 4.0, note: '아래로 밀며 가슴 아래 자극', muscles: ['가슴 아래쪽', '삼두'],
      aliases: ['Decline Chest Press Machine', '디클라인 프레스 머신', '아이소 디클라인 프레스',
          'Hammer Strength Iso-Lateral Decline Press', 'Panatta Super Decline Press']),
  Exercise(id: 'smith-bench-press', name: '스미스 벤치프레스', group: 'chest', equip: 'machine',
      pattern: 'push-h', met: 5.0, note: '바가 명치 위에 오게 눕기', muscles: ['가슴', '삼두', '어깨 앞'],
      aliases: ['Smith Machine Bench Press', '스미스 머신 벤치프레스', '스미스 플랫 벤치',
          'Smith Bench Press', '이고진 스미스머신', 'DRAX 7 Degree Smith Machine TWF-701']),
  Exercise(id: 'smith-incline-press', name: '스미스 인클라인 프레스', group: 'chest', equip: 'machine',
      pattern: 'push-h', met: 4.5, note: '벤치 30도, 바는 쇄골 위', muscles: ['가슴 위쪽', '어깨 앞', '삼두'],
      aliases: ['Smith Machine Incline Press', '스미스 인클라인 벤치', '스미스 인클라인 벤치프레스',
          'Smith Incline Bench Press', '스미스 머신 인클라인 프레스']),
  Exercise(id: 'db-bench-press', name: '덤벨 벤치프레스', group: 'chest', equip: 'dumbbell',
      pattern: 'push-h', met: 5.0, note: '팔꿈치 45도, 가슴 위로', muscles: ['가슴', '삼두', '어깨 앞'],
      aliases: ['Dumbbell Bench Press', '플랫 덤벨프레스', '덤벨 체스트프레스', '덤벨 프레스', 'DB Bench Press']),
  Exercise(id: 'incline-barbell-press', name: '인클라인 바벨 벤치프레스', group: 'chest', equip: 'barbell',
      pattern: 'push-h', met: 5.5, note: '벤치 30도, 바는 쇄골 쪽', muscles: ['가슴 위쪽', '어깨 앞', '삼두'],
      aliases: ['Incline Barbell Bench Press', '인클라인 벤치프레스', '인클라인 프레스', 'Incline Bench Press']),
  Exercise(id: 'assisted-dip', name: '어시스트 딥', group: 'chest', equip: 'machine',
      pattern: 'push-v', met: 4.0, note: '무릎 패드에 올리고 몸 기울여', muscles: ['가슴 아래쪽', '삼두'],
      aliases: ['Assisted Dip Machine', '어시스티드 딥', '딥 어시스트', '친딥 어시스트', '어시스트 딥스']),

  // --- 등 -------------------------------------------------------------------
  Exercise(id: 'pullup-latpulldown', name: '풀업 / 랫풀다운', group: 'back', equip: 'machine',
      pattern: 'pull-v', met: 4.0, note: '견갑 하강 먼저', muscles: ['광배근', '이두'],
      aliases: ['Lat Pulldown', 'Wide Grip Pulldown', '랫풀다운', '와이드 그립 랫풀다운', '와이드 풀다운', '랫 머신',
          'Technogym Lat Machine', 'Atlantis D-138 Lat Pulldown/Low Row Combo']),
  Exercise(id: 'barbell-row', name: '바벨 로우', group: 'back', equip: 'barbell',
      pattern: 'pull-h', met: 5.0, note: '허리 중립 유지', muscles: ['광배근', '승모근', '허리'],
      aliases: ['Barbell Row', '벤트오버 로우', '바벨 벤트오버 로우', '펜들레이 로우']),
  Exercise(id: 'seated-cable-row', name: '시티드 케이블로우', group: 'back', equip: 'cable',
      pattern: 'pull-h', met: 3.5, note: '반동 금지', muscles: ['광배근', '능형근'],
      aliases: ['Seated Cable Row', '시티드 로우', '케이블 로우', '로우 풀리 로우', 'V바 시티드 로우',
          'Precor Vitality Pulldown/Mid-Row']),
  Exercise(id: 'one-arm-db-row', name: '원암 덤벨로우', group: 'back', equip: 'dumbbell',
      pattern: 'pull-h', met: 4.5, note: '좌우 불균형 교정에 유리', muscles: ['광배근', '이두'],
      aliases: ['One-Arm Dumbbell Row', '원암 로우', '덤벨 로우']),
  Exercise(id: 'pull-up', name: '풀업', group: 'back', equip: 'bodyweight',
      pattern: 'pull-v', met: 6.0, note: '철봉이 있을 때 · 안 되면 밴드 풀다운',
      muscles: ['광배근', '이두'], needsBar: true,
      aliases: ['Pull-Up', 'Chin-Up', '턱걸이', '친업']),
  Exercise(id: 'band-pulldown', name: '밴드 풀다운', group: 'back', equip: 'band',
      pattern: 'pull-v', met: 3.5, note: '문 위에 걸고 당김', muscles: ['광배근'],
      aliases: ['Band Pulldown']),
  Exercise(id: 'inverted-row', name: '인버티드 로우', group: 'back', equip: 'bodyweight',
      pattern: 'pull-h', met: 3.8, note: '튼튼한 책상 밑에서 몸을 당김',
      muscles: ['등 위쪽', '이두'],
      aliases: ['Inverted Row', '바디 로우', '오스트레일리안 풀업']),
  Exercise(id: 'band-row', name: '밴드 로우', group: 'back', equip: 'band',
      pattern: 'pull-h', met: 3.5, note: '앉아서 발에 걸고', muscles: ['광배근', '능형근'],
      aliases: ['Band Row']),
  Exercise(id: 'superman', name: '슈퍼맨', group: 'back', equip: 'bodyweight',
      pattern: 'extension', met: 2.8, note: '엎드려 팔다리 들기 · 허리 과신전 금지',
      muscles: ['허리', '엉덩이', '등'],
      aliases: ['Superman']),
  Exercise(id: 'prone-y-raise', name: '프론 Y레이즈', group: 'back', equip: 'bodyweight',
      pattern: 'pull-v', met: 2.8, note: '엎드려 팔을 Y자로 들기', muscles: ['등 위쪽', '어깨 뒤'],
      aliases: ['Prone Y Raise', 'Y레이즈']),
  Exercise(id: 'reverse-snow-angel', name: '리버스 스노우엔젤', group: 'back', equip: 'bodyweight',
      pattern: 'pull-h', met: 2.8, note: '엎드려 팔을 천천히 반원으로',
      muscles: ['등 위쪽', '어깨 뒤'],
      aliases: ['Reverse Snow Angel']),
  /* 확장 — 헬스장 · 머신 브랜드 조사(2차 피드백 12). 앞 항목이 대체 우선순위에서 이깁니다. */
  Exercise(id: 'lat-pulldown-close-grip', name: '내로우 그립 랫풀다운', group: 'back', equip: 'cable',
      pattern: 'pull-v', met: 4.0, note: '팔꿈치를 옆구리로 당김', muscles: ['광배근', '이두'],
      aliases: ['Close-Grip Lat Pulldown', '뉴트럴 그립 랫풀다운', 'V바 풀다운', '클로즈 그립 풀다운', '내로우 풀다운',
          '브이바 랫풀다운', 'Neutral Grip Pulldown', 'Close Grip Pulldown']),
  Exercise(id: 'lat-pulldown-reverse-grip', name: '언더그립 랫풀다운', group: 'back', equip: 'cable',
      pattern: 'pull-v', met: 4.0, note: '손바닥 나를 보게 잡고 당김', muscles: ['광배근', '이두'],
      aliases: ['Reverse-Grip Lat Pulldown', '리버스 그립 풀다운', '언더핸드 풀다운', '언더그립 풀다운',
          'Underhand Pulldown', 'Supinated Pulldown']),
  Exercise(id: 'iso-lateral-pulldown', name: '아이소 랫풀다운', group: 'back', equip: 'machine',
      pattern: 'pull-v', met: 4.0, note: '가슴 펴고 팔꿈치 아래로', muscles: ['광배근', '이두'],
      aliases: ['Iso-Lateral Front Lat Pulldown', '플레이트 랫풀다운', '해머 풀다운', '로터리 풀다운', '플레이트 로디드 풀다운',
          'Hammer Strength Iso-Lateral Front Lat Pulldown', 'Iso-Lateral Wide Pulldown',
          'DRAX Pure Plate Rotary Pulldown PPRP-101', 'Technogym Pure Strength Pulldown MG2000',
          'Prime Plate Loaded Lat Pulldown P-104', '뉴텍 토크라인 와이드 풀다운']),
  Exercise(id: 'vertical-traction', name: '버티컬 트랙션', group: 'back', equip: 'machine',
      pattern: 'pull-v', met: 4.0, note: '팔꿈치를 뒤로 모으며 당김', muscles: ['광배근', '등 위쪽'],
      aliases: ['Vertical Traction', '버티컬 트렉션', '버티컬 풀', 'Technogym Vertical Traction',
          'Technogym Selection 700 Vertical Traction']),
  Exercise(id: 'seated-row-machine', name: '시티드 로우 머신', group: 'back', equip: 'machine',
      pattern: 'pull-h', met: 4.0, note: '가슴 패드에 대고 팔꿈치 뒤로', muscles: ['광배근', '능형근'],
      aliases: ['Seated Row Machine', '로우 머신', '머신 로우', '체스트 서포티드 로우', '아이소 로우', '해머 로우', '프론트 로우',
          'Hammer Strength Iso-Lateral Row', 'Cybex Eagle NX Row',
          'DRAX Pure Plate Front Row PPFR-103', 'Prime Plate Loaded Extreme Row', '뉴텍 토크라인 시티드 로우',
          '뉴텍 토크라인 프론트 로우']),
  Exercise(id: 'high-row', name: '하이 로우', group: 'back', equip: 'machine',
      pattern: 'pull-v', met: 4.0, note: '위에서 가슴 쪽으로 당김', muscles: ['광배근', '등 위쪽'],
      aliases: ['High Row', '하이 로우 머신', '아이소 하이 로우', '해머 하이로우',
          'Hammer Strength Iso-Lateral High Row', 'Plate Loaded High Row',
          'DRAX Pure Plate High Row PPLR-102', '뉴텍 하이 로우']),
  Exercise(id: 'low-row', name: '로우 로우', group: 'back', equip: 'machine',
      pattern: 'pull-h', met: 4.0, note: '아래에서 골반 쪽으로 당김', muscles: ['광배근', '등 아래쪽'],
      aliases: ['Low Row', '로우 로우 머신', '아이소 로우 로우', '해머 로우로우',
          'Hammer Strength Iso-Lateral Low Row', 'Technogym Selection Low Row',
          'DRAX Pure Plate Low Row PPLR-104', 'Precor Discovery Low Row', '뉴텍 토크라인 로우 로우']),
  Exercise(id: 't-bar-row', name: '티바 로우', group: 'back', equip: 'machine',
      pattern: 'pull-h', met: 5.0, note: '허리 중립, 가슴으로 당김', muscles: ['광배근', '능형근', '허리'],
      aliases: ['T-Bar Row', 'T바 로우', '티바로우 머신', '랜드마인 로우', '체스트 서포티드 티바로우',
          'Hammer Strength Iso-Lateral T-Bar Row', 'DRAX T-Bar Row TWF-214',
          'Precor Incline Lever Row']),
  Exercise(id: 'pullover-machine', name: '풀오버 머신', group: 'back', equip: 'machine',
      pattern: 'pull-v', met: 3.5, note: '팔꿈치로 아래로 누르듯', muscles: ['광배근', '가슴'],
      aliases: ['Pullover Machine', '노틸러스 풀오버', '랫 풀오버 머신', '머신 풀오버',
          'Nautilus Inspiration Pull Over', 'Nautilus Pullover IPPO3', 'Panatta Pullover',
          'gym80 Pullover']),
  Exercise(id: 'straight-arm-pulldown', name: '스트레이트암 풀다운', group: 'back', equip: 'cable',
      pattern: 'pull-v', met: 3.5, note: '팔 편 채 허벅지까지', muscles: ['광배근'],
      aliases: ['Straight-Arm Pulldown', '케이블 풀오버', '랫 푸시다운', '암 풀다운', '스트레이트 암 랫 풀다운',
          'Cable Pullover']),
  Exercise(id: 'assisted-pullup', name: '어시스트 풀업', group: 'back', equip: 'machine',
      pattern: 'pull-v', met: 4.0, note: '무릎 패드에 올리고 가슴 세워', muscles: ['광배근', '이두'],
      aliases: ['Assisted Pull-Up Machine', '어시스티드 풀업', '친업 어시스트', '풀업 머신', '어시스트 친업',
          'Assisted Chin/Dip', 'Chin Dip Assist', 'Atlantis D-131',
          'Cybex Prestige Assisted Chin/Dip', '뉴텍 어드반스 어시스트 친업 딥']),
  Exercise(id: 'back-extension-machine', name: '백 익스텐션 머신', group: 'back', equip: 'machine',
      pattern: 'hinge', met: 3.5, note: '등 패드를 천천히 밀어 젖힘', muscles: ['허리'],
      aliases: ['Back Extension Machine', '로워백 머신', '로우어 백', '시티드 백익스텐션', 'Lower Back',
          'Technogym Lower Back', 'Cybex Eagle NX Back Extension', 'Life Fitness Back Extension',
          'Keiser A300 Lower Back']),
  Exercise(id: 'chest-supported-db-row', name: '체스트 서포티드 덤벨 로우', group: 'back', equip: 'dumbbell',
      pattern: 'pull-h', met: 4.5, note: '벤치에 엎드려 팔꿈치 뒤로', muscles: ['광배근', '능형근'],
      aliases: ['Chest-Supported Dumbbell Row', '인클라인 덤벨 로우', '씰 로우', '벤치 덤벨 로우',
          'Incline Dumbbell Row', 'Seal Row']),
  Exercise(id: 'smith-row', name: '스미스 로우', group: 'back', equip: 'machine',
      pattern: 'pull-h', met: 4.5, note: '허리 중립, 배꼽 쪽으로', muscles: ['광배근', '능형근'],
      aliases: ['Smith Machine Row', '스미스 머신 로우', '스미스 벤트오버 로우', 'Smith Bent-Over Row']),

  // --- 어깨 -----------------------------------------------------------------
  Exercise(id: 'overhead-press', name: '오버헤드 프레스', group: 'shoulder', equip: 'barbell',
      pattern: 'push-v', met: 5.0, note: '갈비뼈 들리지 않게', muscles: ['어깨', '삼두'],
      aliases: ['Overhead Press', 'OHP', '밀리터리 프레스', '바벨 숄더프레스', '바벨 오버헤드 프레스']),
  Exercise(id: 'lateral-raise', name: '사이드 레터럴레이즈', group: 'shoulder', equip: 'dumbbell',
      pattern: 'raise', met: 3.5, note: '가볍게 고반복', muscles: ['어깨 옆'],
      aliases: ['Lateral Raise', '레터럴 레이즈', '덤벨 레터럴 레이즈', '사이드 레터럴', '사이드 레이즈']),
  Exercise(id: 'face-pull', name: '페이스풀', group: 'shoulder', equip: 'cable',
      pattern: 'pull-h', met: 3.5, note: '어깨 건강 필수', muscles: ['어깨 뒤', '능형근'],
      aliases: ['Face Pull', '케이블 페이스풀', '로프 페이스풀']),
  Exercise(id: 'db-shoulder-press', name: '덤벨 숄더프레스', group: 'shoulder', equip: 'dumbbell',
      pattern: 'push-v', met: 4.5, note: '앉아서 하면 허리 부담이 줄어듦', muscles: ['어깨', '삼두'],
      aliases: ['Dumbbell Shoulder Press', '시티드 덤벨 숄더프레스', '덤벨 오버헤드 프레스']),
  Exercise(id: 'pike-push-up', name: '파이크 푸시업', group: 'shoulder', equip: 'bodyweight',
      pattern: 'push-v', met: 4.0, note: '엉덩이를 높이 들고 머리를 바닥 쪽으로',
      muscles: ['어깨', '삼두'],
      aliases: ['Pike Push-Up']),
  Exercise(id: 'band-face-pull', name: '밴드 페이스풀', group: 'shoulder', equip: 'band',
      pattern: 'pull-h', met: 3.5, note: '문에 걸고 얼굴 쪽으로', muscles: ['어깨 뒤', '능형근'],
      aliases: ['Band Face Pull']),
  Exercise(id: 'rear-delt-raise', name: '덤벨 리어델트 레이즈', group: 'shoulder', equip: 'dumbbell',
      pattern: 'raise', met: 3.5, note: '상체 숙이고 가볍게', muscles: ['어깨 뒤'],
      aliases: ['Rear Delt Raise', '벤트오버 레터럴 레이즈', '리어 레터럴 레이즈', '덤벨 리버스 플라이']),
  Exercise(id: 'band-lateral-raise', name: '밴드 레터럴레이즈', group: 'shoulder', equip: 'band',
      pattern: 'raise', met: 3.5, note: '발로 밟고 옆으로', muscles: ['어깨 옆'],
      aliases: ['Band Lateral Raise']),
  /* 확장 — 헬스장 · 머신 브랜드 조사(2차 피드백 12). 앞 항목이 대체 우선순위에서 이깁니다. */
  Exercise(id: 'shoulder-press-machine', name: '숄더 프레스 머신', group: 'shoulder', equip: 'machine',
      pattern: 'push-v', met: 4.0, note: '손잡이가 어깨 높이에서 시작', muscles: ['어깨', '삼두'],
      aliases: ['Shoulder Press Machine', '머신 숄더프레스', '오버헤드 프레스 머신', '아이소 숄더 프레스', '해머 숄더프레스',
          'Hammer Strength Iso-Lateral Shoulder Press', 'Cybex Eagle NX Overhead Press',
          'Keiser A300 Military Press', 'DRAX Pure Plate Shoulder Press PPSP-106',
          'Life Fitness Insignia Shoulder Press']),
  Exercise(id: 'lateral-raise-machine', name: '래터럴 레이즈 머신', group: 'shoulder', equip: 'machine',
      pattern: 'raise', met: 3.5, note: '팔꿈치로 옆으로 들기', muscles: ['어깨 옆'],
      aliases: ['Lateral Raise Machine', '사이드 레터럴 머신', '레터럴 레이즈 머신', '델츠 머신', '숄더 레이즈 머신',
          'Technogym Delts Machine', 'Life Fitness Insignia Lateral Raise',
          'Cybex Prestige Lateral Raise', 'Atlantis E-157 Seated Lateral Raise',
          'DRAX Pure Plate Lateral Raise PPLR-110']),
  Exercise(id: 'rear-delt-fly-machine', name: '리어델트 플라이 머신', group: 'shoulder', equip: 'machine',
      pattern: 'raise', met: 3.5, note: '팔을 뒤로 벌리며 견갑 모으기', muscles: ['어깨 뒤', '능형근'],
      aliases: ['Rear Delt Fly Machine', '리버스 펙덱', '리어델트 머신', '리버스 플라이 머신', '리어 델트',
          'Reverse Pec Deck', 'Pec Fly/Rear Delt', 'Technogym Dual Pectoral/Reverse Fly',
          'Life Fitness Row/Rear Delt', 'gym80 Reverse Butterfly',
          'Atlantis E-352 Seated Side/Rear Deltoid']),
  Exercise(id: 'cable-lateral-raise', name: '케이블 래터럴 레이즈', group: 'shoulder', equip: 'cable',
      pattern: 'raise', met: 3.5, note: '낮은 도르래, 몸 앞에서 교차', muscles: ['어깨 옆'],
      aliases: ['Cable Lateral Raise', '케이블 사이드 레터럴', '원암 케이블 레터럴 레이즈', '케이블 레터럴']),
  Exercise(id: 'cable-rear-delt-fly', name: '케이블 리어델트 플라이', group: 'shoulder', equip: 'cable',
      pattern: 'raise', met: 3.5, note: '팔 교차해 뒤로 벌리기', muscles: ['어깨 뒤'],
      aliases: ['Cable Rear Delt Fly', '케이블 리버스 플라이', '케이블 크로스 리어델트', '케이블 리어델트',
          'Cable Reverse Fly']),
  Exercise(id: 'smith-shoulder-press', name: '스미스 숄더 프레스', group: 'shoulder', equip: 'machine',
      pattern: 'push-v', met: 4.5, note: '바가 턱 앞을 지나게', muscles: ['어깨', '삼두'],
      aliases: ['Smith Machine Shoulder Press', '스미스 오버헤드 프레스', '스미스 밀리터리 프레스',
          'Smith Overhead Press', '스미스 머신 숄더 프레스']),
  Exercise(id: 'cable-upright-row', name: '케이블 업라이트 로우', group: 'shoulder', equip: 'cable',
      pattern: 'pull-v', met: 3.5, note: '팔꿈치가 손보다 높게', muscles: ['어깨 옆', '승모근'],
      aliases: ['Cable Upright Row', '업라이트 로우', '바벨 업라이트 로우', '덤벨 업라이트 로우', 'Upright Row']),
  Exercise(id: 'front-raise', name: '덤벨 프론트 레이즈', group: 'shoulder', equip: 'dumbbell',
      pattern: 'raise', met: 3.5, note: '어깨 높이까지만', muscles: ['어깨 앞'],
      aliases: ['Dumbbell Front Raise', '프론트 레이즈', '플레이트 프론트 레이즈', 'Front Raise']),
  Exercise(id: 'arnold-press', name: '아놀드 프레스', group: 'shoulder', equip: 'dumbbell',
      pattern: 'push-v', met: 4.5, note: '손바닥 돌리며 밀기', muscles: ['어깨', '어깨 앞', '삼두'],
      aliases: ['Arnold Press', '덤벨 아놀드 프레스']),
  Exercise(id: 'landmine-press', name: '랜드마인 프레스', group: 'shoulder', equip: 'barbell',
      pattern: 'push-v', met: 4.5, note: '바 끝을 잡고 비스듬히 위로', muscles: ['어깨 앞', '가슴 위쪽', '삼두'],
      aliases: ['Landmine Press', '랜드마인 숄더프레스', 'Landmine Shoulder Press']),
  Exercise(id: 'db-shrug', name: '덤벨 슈러그', group: 'shoulder', equip: 'dumbbell',
      pattern: 'pull-v', met: 3.5, note: '어깨를 귀 쪽으로 으쓱', muscles: ['승모근'],
      aliases: ['Dumbbell Shrug', '슈러그', '슈러그 덤벨', 'Shrug']),
  Exercise(id: 'smith-shrug', name: '스미스 슈러그', group: 'shoulder', equip: 'machine',
      pattern: 'pull-v', met: 3.5, note: '팔은 펴고 어깨만 올리기', muscles: ['승모근'],
      aliases: ['Smith Machine Shrug', '스미스 머신 슈러그', '바벨 슈러그', 'Smith Shrug']),

  // --- 팔 -------------------------------------------------------------------
  Exercise(id: 'barbell-curl', name: '바벨 컬', group: 'arms', equip: 'barbell',
      pattern: 'curl', met: 3.5, note: '', muscles: ['이두'],
      aliases: ['Barbell Curl', '스탠딩 바벨 컬', '바벨 바이셉 컬']),
  Exercise(id: 'incline-db-curl', name: '인클라인 덤벨컬', group: 'arms', equip: 'dumbbell',
      pattern: 'curl', met: 3.5, note: '', muscles: ['이두'],
      aliases: ['Incline Dumbbell Curl']),
  Exercise(id: 'cable-pushdown', name: '케이블 푸시다운', group: 'arms', equip: 'cable',
      pattern: 'extension', met: 3.5, note: '', muscles: ['삼두'],
      aliases: ['Cable Pushdown', 'Triceps Pushdown', 'Rope Pushdown', '로프 푸시다운', '바 푸시다운',
          '트라이셉 푸시다운', '케이블 프레스다운']),
  Exercise(id: 'overhead-extension', name: '오버헤드 익스텐션', group: 'arms', equip: 'dumbbell',
      pattern: 'extension', met: 3.5, note: '', muscles: ['삼두'],
      aliases: ['Overhead Triceps Extension', '덤벨 오버헤드 익스텐션', '원암 오버헤드 익스텐션']),
  Exercise(id: 'db-curl', name: '덤벨 컬', group: 'arms', equip: 'dumbbell',
      pattern: 'curl', met: 3.5, note: '반동 없이', muscles: ['이두'],
      aliases: ['Dumbbell Curl', '얼터네이트 덤벨컬', '스탠딩 덤벨컬']),
  Exercise(id: 'band-curl', name: '밴드 컬', group: 'arms', equip: 'band',
      pattern: 'curl', met: 3.5, note: '발로 밟고', muscles: ['이두'],
      aliases: ['Band Curl']),
  Exercise(id: 'db-kickback', name: '덤벨 킥백', group: 'arms', equip: 'dumbbell',
      pattern: 'extension', met: 3.5, note: '팔꿈치 고정', muscles: ['삼두'],
      aliases: ['Dumbbell Kickback', '트라이셉 킥백']),
  Exercise(id: 'diamond-push-up', name: '다이아몬드 푸시업', group: 'arms', equip: 'bodyweight',
      pattern: 'extension', met: 4.5, note: '손을 모아 삼두 자극', muscles: ['삼두', '가슴'],
      aliases: ['Diamond Push-Up']),
  Exercise(id: 'bench-dips', name: '벤치 딥스', group: 'arms', equip: 'bodyweight',
      pattern: 'extension', met: 4.0, note: '의자 끝을 잡고 · 어깨가 아프면 중단',
      muscles: ['삼두', '가슴 아래쪽'],
      aliases: ['Bench Dips', '의자 딥스']),
  /* 확장 — 헬스장 · 머신 브랜드 조사(2차 피드백 12). 앞 항목이 대체 우선순위에서 이깁니다. */
  Exercise(id: 'preacher-curl-machine', name: '프리처 컬 머신', group: 'arms', equip: 'machine',
      pattern: 'curl', met: 3.5, note: '팔꿈치를 패드에 고정', muscles: ['이두'],
      aliases: ['Preacher Curl Machine', '암 컬 머신', '바이셉 컬 머신', '머신 컬', '이두 머신', 'Arm Curl',
          'Biceps Curl', 'Technogym Arm Curl', 'Cybex Prestige Arm Curl',
          'Life Fitness Signature Bicep Curl', 'Precor Discovery Biceps Curl']),
  Exercise(id: 'preacher-curl', name: '프리처 컬', group: 'arms', equip: 'barbell',
      pattern: 'curl', met: 3.5, note: '팔꿈치 패드, 끝까지 펴지 않기', muscles: ['이두'],
      aliases: ['EZ-Bar Preacher Curl', '이지바 프리처 컬', '덤벨 프리처 컬', '프리쳐 컬', 'Preacher Curl']),
  Exercise(id: 'hammer-curl', name: '해머 컬', group: 'arms', equip: 'dumbbell',
      pattern: 'curl', met: 3.5, note: '손바닥 마주 본 채', muscles: ['이두', '전완'],
      aliases: ['Hammer Curl', '덤벨 해머컬']),
  Exercise(id: 'ez-bar-curl', name: '이지바 컬', group: 'arms', equip: 'barbell',
      pattern: 'curl', met: 3.5, note: '손목 편한 각도로 잡기', muscles: ['이두'],
      aliases: ['EZ-Bar Curl', 'EZ바 컬', '이지 바벨 컬', 'EZ Bar Curl']),
  Exercise(id: 'cable-curl', name: '케이블 컬', group: 'arms', equip: 'cable',
      pattern: 'curl', met: 3.5, note: '팔꿈치 고정, 반동 없이', muscles: ['이두'],
      aliases: ['Cable Curl', '케이블 바이셉 컬', '로우 풀리 컬', '케이블 로프 해머컬', 'Cable Biceps Curl']),
  Exercise(id: 'concentration-curl', name: '컨센트레이션 컬', group: 'arms', equip: 'dumbbell',
      pattern: 'curl', met: 3.5, note: '허벅지 안쪽에 팔꿈치 대고', muscles: ['이두'],
      aliases: ['Concentration Curl', '집중 컬', '덤벨 컨센트레이션 컬']),
  Exercise(id: 'wrist-curl', name: '리스트 컬', group: 'arms', equip: 'dumbbell',
      pattern: 'curl', met: 3.5, note: '손목만 말아 올리기', muscles: ['전완'],
      aliases: ['Wrist Curl', '손목 컬', '덤벨 리스트 컬', '바벨 리스트 컬']),
  Exercise(id: 'reverse-curl', name: '리버스 컬', group: 'arms', equip: 'barbell',
      pattern: 'curl', met: 3.5, note: '손등이 위로 가게 잡기', muscles: ['전완', '이두'],
      aliases: ['Reverse Curl', '역수 컬', '이지바 리버스 컬', 'Reverse Barbell Curl']),
  Exercise(id: 'triceps-extension-machine', name: '트라이셉 익스텐션 머신', group: 'arms', equip: 'machine',
      pattern: 'extension', met: 3.5, note: '팔꿈치 패드에 대고 펴기', muscles: ['삼두'],
      aliases: ['Triceps Extension Machine', '암 익스텐션 머신', '트라이셉스 머신', '삼두 머신', 'Arm Extension',
          'Technogym Arm Extension', 'Cybex Eagle NX Arm Extension',
          'Life Fitness Signature Tricep Press', 'Precor Vitality Triceps Extension']),
  Exercise(id: 'dip-machine', name: '딥 머신', group: 'arms', equip: 'machine',
      pattern: 'extension', met: 4.0, note: '손잡이를 아래로 눌러 내림', muscles: ['삼두', '가슴 아래쪽'],
      aliases: ['Seated Dip Machine', '시티드 딥', '딥스 머신', '트라이셉 프레스', '시티드 딥 머신', 'Triceps Press',
          'Precor Discovery Seated Dip', 'Star Trac Impact Dip Machine', '뉴텍 어드반스 시티드 딥']),
  Exercise(id: 'cable-overhead-extension', name: '케이블 오버헤드 익스텐션', group: 'arms', equip: 'cable',
      pattern: 'extension', met: 3.5, note: '팔꿈치 귀 옆, 앞으로 펴기', muscles: ['삼두'],
      aliases: ['Cable Overhead Triceps Extension', '로프 오버헤드 익스텐션', '케이블 트라이셉 오버헤드',
          '케이블 오버헤드 트라이셉', 'Rope Overhead Extension']),
  Exercise(id: 'cable-triceps-kickback', name: '케이블 트라이셉 킥백', group: 'arms', equip: 'cable',
      pattern: 'extension', met: 3.5, note: '팔꿈치 고정, 뒤로 펴기', muscles: ['삼두'],
      aliases: ['Cable Triceps Kickback', '케이블 삼두 킥백', '케이블 트라이셉스 킥백']),
  Exercise(id: 'skull-crusher', name: '스컬 크러셔', group: 'arms', equip: 'barbell',
      pattern: 'extension', met: 3.5, note: '팔꿈치 고정, 이마 쪽으로', muscles: ['삼두'],
      aliases: ['Skull Crusher', '라잉 트라이셉 익스텐션', '이지바 스컬크러셔', '라잉 트라이셉스 익스텐션',
          'Lying Triceps Extension']),
  Exercise(id: 'close-grip-bench-press', name: '클로즈 그립 벤치프레스', group: 'arms', equip: 'barbell',
      pattern: 'push-h', met: 5.0, note: '어깨 너비로 잡고 팔꿈치 붙여', muscles: ['삼두', '가슴'],
      aliases: ['Close-Grip Bench Press', '내로우 벤치프레스', '클로즈그립 벤치', '좁은 그립 벤치프레스', 'Close Grip Bench']),

  // --- 허벅지 앞 -------------------------------------------------------------
  Exercise(id: 'barbell-squat', name: '바벨 스쿼트', group: 'quads', equip: 'barbell',
      pattern: 'squat', met: 6.0, note: '무릎 발끝 방향', muscles: ['허벅지 앞', '엉덩이', '코어'],
      aliases: ['Barbell Squat', 'Back Squat', '백 스쿼트', '바벨 백스쿼트']),
  Exercise(id: 'leg-press', name: '레그프레스', group: 'quads', equip: 'machine',
      pattern: 'squat', met: 4.0, note: '허리 뜨지 않게', muscles: ['허벅지 앞', '엉덩이'],
      aliases: ['Leg Press', '45도 레그프레스', '리니어 레그프레스', '앵글드 레그프레스', '플레이트 레그프레스',
          'Hammer Strength Linear Leg Press', 'Iso-Lateral Leg Press',
          'DRAX Pure Plate Power Leg Press PPLP-108', 'Precor Discovery Angled Leg Press DPL0601',
          'Prime Plate Loaded Leg Press P-108']),
  Exercise(id: 'bulgarian-split-squat', name: '불가리안 스플릿스쿼트', group: 'quads', equip: 'dumbbell',
      pattern: 'lunge', met: 5.0, note: '좌우 불균형 교정', muscles: ['허벅지 앞', '엉덩이'],
      aliases: ['Bulgarian Split Squat', '불가리안']),
  Exercise(id: 'leg-extension', name: '레그 익스텐션', group: 'quads', equip: 'machine',
      pattern: 'isolation', met: 3.5, note: '', muscles: ['허벅지 앞'],
      aliases: ['Leg Extension', '레그 익스텐션 머신', 'Hammer Strength Iso-Lateral Leg Extension',
          'Prime Hybrid Leg Extension H-105', 'Hoist ROC-IT Leg Extension RS-1401',
          'DRAX Welliv Pro Leg Extension TWMA-102']),
  Exercise(id: 'goblet-squat', name: '고블릿 스쿼트', group: 'quads', equip: 'dumbbell',
      pattern: 'squat', met: 5.0, note: '덤벨을 가슴 앞에 안고', muscles: ['허벅지 앞', '엉덩이'],
      aliases: ['Goblet Squat', '케틀벨 고블릿 스쿼트']),
  Exercise(id: 'bodyweight-squat', name: '맨몸 스쿼트', group: 'quads', equip: 'bodyweight',
      pattern: 'squat', met: 3.8, note: '발뒤꿈치 붙이고 천천히', muscles: ['허벅지 앞', '엉덩이'],
      aliases: ['Bodyweight Squat', 'Air Squat', '에어 스쿼트']),
  Exercise(id: 'jump-squat', name: '점프 스쿼트', group: 'quads', equip: 'bodyweight',
      pattern: 'squat', met: 8.0, note: '착지는 조용히', muscles: ['허벅지 앞', '엉덩이', '심폐'],
      aliases: ['Jump Squat']),
  Exercise(id: 'lunge', name: '런지', group: 'quads', equip: 'bodyweight',
      pattern: 'lunge', met: 3.8, note: '앞 무릎이 발끝을 넘지 않게', muscles: ['허벅지 앞', '엉덩이'],
      aliases: ['Lunge', 'Forward Lunge', '덤벨 런지', '포워드 런지']),
  Exercise(id: 'split-squat', name: '스플릿 스쿼트', group: 'quads', equip: 'bodyweight',
      pattern: 'lunge', met: 4.0, note: '제자리에서 한 발을 앞에 두고', muscles: ['허벅지 앞', '엉덩이'],
      aliases: ['Split Squat']),
  Exercise(id: 'step-up', name: '스텝업', group: 'quads', equip: 'bodyweight',
      pattern: 'lunge', met: 5.0, note: '의자·계단에 올라섰다 내려오기', muscles: ['허벅지 앞', '엉덩이'],
      aliases: ['Step-Up', '덤벨 스텝업', '박스 스텝업']),
  Exercise(id: 'wall-sit', name: '월 싯', group: 'quads', equip: 'bodyweight',
      pattern: 'hold', met: 3.5, note: '벽에 등을 대고 앉은 자세 유지', muscles: ['허벅지 앞'],
      aliases: ['Wall Sit']),
  /* 확장 — 헬스장 · 머신 브랜드 조사(2차 피드백 12). 앞 항목이 대체 우선순위에서 이깁니다. */
  Exercise(id: 'hack-squat', name: '핵 스쿼트', group: 'quads', equip: 'machine',
      pattern: 'squat', met: 5.0, note: '등을 패드에 붙이고 깊게', muscles: ['허벅지 앞', '엉덩이'],
      aliases: ['Hack Squat', '핵 스쿼트 머신', '해머 핵스쿼트', 'Hack Squat Machine',
          'Hammer Strength Plate Loaded Hack Squat', 'DRAX Pure Plate Hack Squat PPHS-109',
          'Precor Discovery Hack Squat', 'Hoist ROC-IT Hack Squat']),
  Exercise(id: 'pendulum-squat', name: '펜듈럼 스쿼트', group: 'quads', equip: 'machine',
      pattern: 'squat', met: 5.0, note: '발판 낮게, 무릎 앞으로', muscles: ['허벅지 앞', '엉덩이'],
      aliases: ['Pendulum Squat', '펜듈럼 스쿼트 머신', '펜듈럼', 'Panatta Super Pendulum Squat',
          'Matrix Magnum Pendulum Squat MG-PL80', 'Atlantis Pendulum Squat Pro PW212']),
  Exercise(id: 'belt-squat', name: '벨트 스쿼트', group: 'quads', equip: 'machine',
      pattern: 'squat', met: 5.0, note: '벨트를 골반에, 허리 편하게', muscles: ['허벅지 앞', '엉덩이'],
      aliases: ['Belt Squat', '벨트 스쿼트 머신', '힙 벨트 스쿼트', 'Hammer Strength Belt Squat',
          'Matrix Magnum Belt Squat MG-PL81']),
  Exercise(id: 'v-squat', name: 'V-스쿼트', group: 'quads', equip: 'machine',
      pattern: 'squat', met: 5.0, note: '어깨 패드 밑에, 발은 앞쪽', muscles: ['허벅지 앞', '엉덩이'],
      aliases: ['V-Squat', '브이 스쿼트', 'V스쿼트', '스쿼트 머신', '리니어 스쿼트', 'Hammer Strength V-Squat',
          'DRAX Pure Plate V-Squat PPVS-107', 'Precor Discovery Squat Machine',
          'Panatta Super Squat Machine', 'Matrix Varsity Perfect Squat']),
  Exercise(id: 'smith-squat', name: '스미스 스쿼트', group: 'quads', equip: 'machine',
      pattern: 'squat', met: 5.0, note: '발을 조금 앞에 두고 앉기', muscles: ['허벅지 앞', '엉덩이'],
      aliases: ['Smith Machine Squat', '스미스 머신 스쿼트', 'Smith Squat', '이고진 스미스머신 3022SM']),
  Exercise(id: 'seated-leg-press', name: '시티드 레그프레스', group: 'quads', equip: 'machine',
      pattern: 'squat', met: 4.0, note: '무릎 90도에서 밀기', muscles: ['허벅지 앞', '엉덩이'],
      aliases: ['Seated Leg Press', '수평 레그프레스', '호리즌탈 레그프레스', '머신 레그프레스', 'Horizontal Leg Press',
          'Life Fitness Signature Seated Leg Press', 'Technogym Selection Leg Press',
          'DRAX Welliv Pro Seated Leg Press TWMA-101', 'Hoist ROC-IT Leg Press RS-1403',
          '뉴텍 어드반스 시티드 레그프레스']),
  Exercise(id: 'smith-lunge', name: '스미스 런지', group: 'quads', equip: 'machine',
      pattern: 'lunge', met: 4.5, note: '앞발에 체중, 뒷무릎 아래로', muscles: ['허벅지 앞', '엉덩이'],
      aliases: ['Smith Machine Lunge', '스미스 스플릿 스쿼트', '스미스 리버스 런지', 'Smith Split Squat',
          '스미스 머신 런지']),
  Exercise(id: 'front-squat', name: '프론트 스쿼트', group: 'quads', equip: 'barbell',
      pattern: 'squat', met: 6.0, note: '팔꿈치 높게, 가슴 세우기', muscles: ['허벅지 앞', '코어', '엉덩이'],
      aliases: ['Front Squat', '바벨 프론트 스쿼트', 'Barbell Front Squat']),
  Exercise(id: 'walking-lunge', name: '워킹 런지', group: 'quads', equip: 'dumbbell',
      pattern: 'lunge', met: 4.5, note: '무릎이 발끝 넘지 않게', muscles: ['허벅지 앞', '엉덩이'],
      aliases: ['Walking Lunge', '덤벨 워킹 런지', 'Dumbbell Walking Lunge']),
  Exercise(id: 'reverse-lunge', name: '리버스 런지', group: 'quads', equip: 'dumbbell',
      pattern: 'lunge', met: 4.0, note: '뒤로 빼고 앞발로 일어남', muscles: ['허벅지 앞', '엉덩이'],
      aliases: ['Reverse Lunge', '백 런지', '덤벨 리버스 런지', 'Back Lunge']),

  // --- 허벅지 뒤·엉덩이 -------------------------------------------------------
  Exercise(id: 'rdl', name: '루마니안 데드리프트', group: 'hamsGlutes', equip: 'barbell',
      pattern: 'hinge', met: 6.0, note: '햄스트링 신장 느끼기', muscles: ['허벅지 뒤', '엉덩이', '허리'],
      aliases: ['Romanian Deadlift', 'RDL', '루마니안 데드', '바벨 RDL', '바벨 루마니안 데드리프트']),
  Exercise(id: 'hip-thrust', name: '힙 쓰러스트', group: 'hamsGlutes', equip: 'barbell',
      pattern: 'hinge', met: 5.0, note: '', muscles: ['엉덩이', '허벅지 뒤'],
      aliases: ['Hip Thrust', '바벨 힙쓰러스트']),
  Exercise(id: 'leg-curl', name: '레그 컬', group: 'hamsGlutes', equip: 'machine',
      pattern: 'isolation', met: 3.5, note: '', muscles: ['허벅지 뒤'],
      aliases: ['Leg Curl', 'Seated Leg Curl', '시티드 레그컬', '햄스트링 컬', '레그컬 머신',
          'Hoist ROC-IT Leg Curl RS-1402', 'Cybex Eagle NX Seated Leg Curl',
          'Keiser A300 Seated Leg Curl']),
  Exercise(id: 'db-rdl', name: '덤벨 루마니안 데드리프트', group: 'hamsGlutes', equip: 'dumbbell',
      pattern: 'hinge', met: 5.0, note: '무릎 살짝 굽히고 엉덩이를 뒤로', muscles: ['허벅지 뒤', '엉덩이'],
      aliases: ['Dumbbell Romanian Deadlift', '덤벨 RDL', '덤벨 루마니안 데드']),
  Exercise(id: 'kettlebell-swing', name: '케틀벨 스윙', group: 'hamsGlutes', equip: 'kettlebell',
      pattern: 'hinge', met: 8.0, note: '팔이 아니라 엉덩이로 던짐', muscles: ['엉덩이', '허벅지 뒤', '심폐'],
      aliases: ['Kettlebell Swing']),
  Exercise(id: 'glute-bridge', name: '글루트 브릿지', group: 'hamsGlutes', equip: 'bodyweight',
      pattern: 'hinge', met: 3.5, note: '누워서 엉덩이 들기 · 위에서 1초', muscles: ['엉덩이', '허벅지 뒤'],
      aliases: ['Glute Bridge', '힙 브릿지', '브릿지']),
  Exercise(id: 'single-leg-glute-bridge', name: '싱글레그 글루트브릿지', group: 'hamsGlutes',
      equip: 'bodyweight', pattern: 'hinge', met: 4.0, note: '한 발로 · 골반 수평',
      muscles: ['엉덩이', '허벅지 뒤'],
      aliases: ['Single-Leg Glute Bridge', '원레그 글루트 브릿지']),
  Exercise(id: 'calf-raise', name: '카프 레이즈', group: 'hamsGlutes', equip: 'bodyweight',
      pattern: 'isolation', met: 3.5, note: '계단 끝에 서서', muscles: ['종아리'],
      aliases: ['Calf Raise', '스탠딩 카프 레이즈', '맨몸 카프레이즈', '종아리 운동']),
  /* 확장 — 헬스장 · 머신 브랜드 조사(2차 피드백 12). 앞 항목이 대체 우선순위에서 이깁니다. */
  Exercise(id: 'lying-leg-curl', name: '라잉 레그 컬', group: 'hamsGlutes', equip: 'machine',
      pattern: 'isolation', met: 3.5, note: '골반 패드에 붙이고 당김', muscles: ['허벅지 뒤'],
      aliases: ['Lying Leg Curl', '프론 레그컬', '라잉 햄스트링 컬', '엎드려 레그컬', 'Prone Leg Curl',
          'Hammer Strength Iso-Lateral Leg Curl', 'Life Fitness Insignia Prone Leg Curl',
          'Hoist ROC-IT Prone Leg Curl RS-1408', 'Prime Hybrid Lying Leg Curl']),
  Exercise(id: 'standing-leg-curl', name: '스탠딩 레그 컬', group: 'hamsGlutes', equip: 'machine',
      pattern: 'isolation', met: 3.5, note: '한 발씩, 상체 고정', muscles: ['허벅지 뒤'],
      aliases: ['Standing Leg Curl', '스탠딩 햄스트링 컬', '원레그 스탠딩 컬', '니링 레그컬', '한 발 레그컬',
          'gym80 Pure Kraft Standing Leg Curl 4373', 'Atlantis Precision Standing Leg Curl C107',
          'Hammer Strength Iso-Lateral Kneeling Leg Curl']),
  Exercise(id: 'nordic-curl', name: '노르딕 컬', group: 'hamsGlutes', equip: 'bodyweight',
      pattern: 'isolation', met: 4.5, note: '발목 고정, 천천히 앞으로', muscles: ['허벅지 뒤'],
      aliases: ['Nordic Hamstring Curl', '노르딕 햄스트링 컬', 'Nordic Curl']),
  Exercise(id: 'glute-ham-raise', name: '글루트 햄 레이즈', group: 'hamsGlutes', equip: 'bodyweight',
      pattern: 'isolation', met: 4.5, note: '몸을 일직선으로 천천히 내림', muscles: ['허벅지 뒤', '엉덩이'], needsBar: true,
      aliases: ['Glute-Ham Raise', 'GHR', 'GHD', '글루트 햄 디벨로퍼', 'Glute Ham Developer',
          'Atlantis Glute & Ham Developer D-227']),
  Exercise(id: 'hip-abduction-machine', name: '힙 어브덕션', group: 'hamsGlutes', equip: 'machine',
      pattern: 'abduction', met: 3.5, note: '상체 살짝 숙이면 엉덩이 옆', muscles: ['엉덩이 옆'],
      aliases: ['Hip Abduction Machine', '아웃싸이', '아웃타이', '힙 어브덕터', '어브덕션 머신', '힙 어브덕션 머신',
          'Outer Thigh', 'Hip Abductor', 'Hoist ROC-IT Outer Thigh RS-1407',
          'Technogym Dual Abductor/Adductor', '뉴텍 어드반스 힙 어덕션 어브덕션 콤보']),
  Exercise(id: 'hip-adduction-machine', name: '힙 어덕션', group: 'hamsGlutes', equip: 'machine',
      pattern: 'adduction', met: 3.5, note: '천천히 모으고 천천히 벌림', muscles: ['허벅지 안쪽'],
      aliases: ['Hip Adduction Machine', '이너싸이', '이너타이', '힙 어덕터', '어덕션 머신', '힙 어덕션 머신',
          'Inner Thigh', 'Hip Adductor', 'Hoist ROC-IT Inner Thigh RS-1406']),
  Exercise(id: 'cable-hip-abduction', name: '케이블 힙 어브덕션', group: 'hamsGlutes', equip: 'cable',
      pattern: 'abduction', met: 3.5, note: '발목 스트랩, 옆으로 들기', muscles: ['엉덩이 옆'],
      aliases: ['Cable Hip Abduction', '케이블 어브덕션', '케이블 사이드 레그 레이즈']),
  Exercise(id: 'band-lateral-walk', name: '밴드 사이드 워크', group: 'hamsGlutes', equip: 'band',
      pattern: 'abduction', met: 3.5, note: '무릎 위 밴드, 옆으로 걷기', muscles: ['엉덩이 옆'],
      aliases: ['Banded Lateral Walk', '밴드 게걸음', '몬스터 워크', '밴드 레터럴 워크', 'Monster Walk']),
  Exercise(id: 'clamshell', name: '클램쉘', group: 'hamsGlutes', equip: 'bodyweight',
      pattern: 'abduction', met: 2.8, note: '옆으로 누워 무릎만 벌리기', muscles: ['엉덩이 옆'],
      aliases: ['Clamshell', '조개 운동', '밴드 클램쉘']),
  Exercise(id: 'hip-thrust-machine', name: '힙 쓰러스트 머신', group: 'hamsGlutes', equip: 'machine',
      pattern: 'hinge', met: 4.5, note: '턱 당기고 엉덩이로 밀어 올림', muscles: ['엉덩이', '허벅지 뒤'],
      aliases: ['Hip Thrust Machine', '글루트 드라이브', '글루트 트레이너', '힙 프레스', 'Glute Drive',
          'Nautilus Glute Drive', 'Matrix Magnum Glute Trainer MG-PL78',
          'DRAX Pure Plate Hip Thrust PPHT-111', 'Panatta Hip Thrust']),
  Exercise(id: 'cable-pull-through', name: '케이블 풀스루', group: 'hamsGlutes', equip: 'cable',
      pattern: 'hinge', met: 4.0, note: '로프 다리 사이로, 엉덩이 뒤로', muscles: ['엉덩이', '허벅지 뒤'],
      aliases: ['Cable Pull-Through', '풀 스루', '로프 풀스루', 'Pull Through']),
  Exercise(id: 'glute-kickback-machine', name: '글루트 킥백 머신', group: 'hamsGlutes', equip: 'machine',
      pattern: 'hinge', met: 3.5, note: '발판을 뒤로 밀며 엉덩이 조임', muscles: ['엉덩이', '허벅지 뒤'],
      aliases: ['Glute Kickback Machine', '글루트 머신', '킥백 머신', '힙 익스텐션 머신', '스탠딩 글루트', '글루트 마스터',
          'Glute Master', 'Life Fitness Signature Glute', 'Hoist ROC-IT Glute Master RS-1412',
          'Atlantis Glute Machine C-122', 'Precor Vitality Glute Extension', 'Cybex Eagle NX Glute']),
  Exercise(id: 'cable-glute-kickback', name: '케이블 글루트 킥백', group: 'hamsGlutes', equip: 'cable',
      pattern: 'hinge', met: 3.5, note: '발목 스트랩, 뒤로 차기', muscles: ['엉덩이'],
      aliases: ['Cable Glute Kickback', '케이블 킥백', '케이블 힙 익스텐션', '케이블 백 킥']),
  Exercise(id: 'donkey-kick', name: '덩키 킥', group: 'hamsGlutes', equip: 'bodyweight',
      pattern: 'hinge', met: 3.5, note: '네발 자세, 발바닥을 천장으로', muscles: ['엉덩이'],
      aliases: ['Donkey Kick', '당나귀 킥', '네발 킥백', 'Quadruped Hip Extension']),
  Exercise(id: 'smith-hip-thrust', name: '스미스 힙 쓰러스트', group: 'hamsGlutes', equip: 'machine',
      pattern: 'hinge', met: 4.5, note: '견갑을 벤치에, 정강이 수직', muscles: ['엉덩이', '허벅지 뒤'],
      aliases: ['Smith Machine Hip Thrust', 'Smith Hip Thrust', '스미스 머신 힙 쓰러스트']),
  Exercise(id: 'multi-hip-machine', name: '멀티 힙 머신', group: 'hamsGlutes', equip: 'machine',
      pattern: 'hinge', met: 3.5, note: '패드 위치 맞추고 한 발씩', muscles: ['엉덩이', '허벅지 안쪽'],
      aliases: ['Multi-Hip Machine', '멀티힙', '로터리 힙', '4웨이 힙', '힙 머신', 'Technogym Multi Hip',
          'Keiser A300 Standing Hip', 'DRAX Welliv Pro Rotary Hip & Glute TWMA-105']),
  Exercise(id: 'back-extension-45', name: '백 익스텐션 (45°)', group: 'hamsGlutes', equip: 'bodyweight',
      pattern: 'hinge', met: 3.5, note: '엉덩이 힘으로 올라오기', muscles: ['허리', '엉덩이', '허벅지 뒤'], needsBar: true,
      aliases: ['45-Degree Back Extension', '하이퍼 익스텐션', '로만 체어', '45도 백익스텐션', '백 익스텐션 벤치',
          'Hyperextension', 'Roman Chair']),
  Exercise(id: 'reverse-hyper', name: '리버스 하이퍼', group: 'hamsGlutes', equip: 'machine',
      pattern: 'hinge', met: 3.5, note: '다리를 뒤로 들며 엉덩이 조임', muscles: ['엉덩이', '허리'],
      aliases: ['Reverse Hyperextension', '리버스 하이퍼익스텐션', '리버스 하이퍼 머신', 'Reverse Hyper']),
  Exercise(id: 'deadlift', name: '데드리프트', group: 'hamsGlutes', equip: 'barbell',
      pattern: 'hinge', met: 6.0, note: '바를 정강이에 붙여 올림', muscles: ['허벅지 뒤', '엉덩이', '허리'],
      aliases: ['Conventional Deadlift', '컨벤셔널 데드리프트', '바벨 데드리프트', '데드', 'Deadlift']),
  Exercise(id: 'sumo-deadlift', name: '스모 데드리프트', group: 'hamsGlutes', equip: 'barbell',
      pattern: 'hinge', met: 6.0, note: '발 넓게, 무릎 발끝 방향', muscles: ['엉덩이', '허벅지 안쪽', '허벅지 뒤'],
      aliases: ['Sumo Deadlift', '스모 데드']),
  Exercise(id: 'trap-bar-deadlift', name: '트랩바 데드리프트', group: 'hamsGlutes', equip: 'barbell',
      pattern: 'hinge', met: 6.0, note: '가슴 들고 다리로 밀기', muscles: ['허벅지 뒤', '엉덩이', '허벅지 앞'],
      aliases: ['Trap Bar Deadlift', '헥스바 데드리프트', '트랩바 데드', 'Hex Bar Deadlift',
          'Keiser A300 Deadlift']),
  Exercise(id: 'single-leg-rdl', name: '싱글레그 루마니안 데드리프트', group: 'hamsGlutes', equip: 'dumbbell',
      pattern: 'hinge', met: 4.0, note: '골반 수평, 뒷다리 일직선', muscles: ['허벅지 뒤', '엉덩이'],
      aliases: ['Single-Leg Romanian Deadlift', '원레그 데드리프트', '싱글레그 RDL', '한 발 데드리프트',
          'Single Leg RDL']),
  Exercise(id: 'good-morning', name: '굿모닝', group: 'hamsGlutes', equip: 'barbell',
      pattern: 'hinge', met: 4.0, note: '가볍게, 엉덩이 뒤로', muscles: ['허벅지 뒤', '허리'],
      aliases: ['Good Morning', '바벨 굿모닝']),
  Exercise(id: 'seated-calf-raise', name: '시티드 카프 레이즈', group: 'hamsGlutes', equip: 'machine',
      pattern: 'isolation', met: 3.5, note: '뒤꿈치 최대한 내렸다 올림', muscles: ['종아리'],
      aliases: ['Seated Calf Raise', '시티드 카프', '앉아서 카프레이즈', '시티드 카프 머신', 'Seated Calf',
          'Hammer Strength Seated Calf', 'Keiser A300 Seated Calf', 'gym80 Seated Calf']),
  Exercise(id: 'standing-calf-raise-machine', name: '스탠딩 카프 레이즈 머신', group: 'hamsGlutes', equip: 'machine',
      pattern: 'isolation', met: 3.5, note: '무릎 펴고 천천히', muscles: ['종아리'],
      aliases: ['Standing Calf Raise Machine', '스탠딩 카프', '카프 머신', '카프 익스텐션', '스탠딩 카프 머신',
          'Calf Extension', 'Precor Vitality Calf Extension', 'Hoist ROC-IT Rotary Calf RS-1415',
          'Atlantis Precision Standing Calf M-118', 'Cybex Eagle NX Calf']),
  Exercise(id: 'leg-press-calf-raise', name: '레그프레스 카프 레이즈', group: 'hamsGlutes', equip: 'machine',
      pattern: 'isolation', met: 3.5, note: '발끝만 발판 끝에 걸고', muscles: ['종아리'],
      aliases: ['Leg Press Calf Raise', '레그프레스 카프', '카프 프레스', '레그프레스 종아리', 'Calf Press']),
  Exercise(id: 'smith-calf-raise', name: '스미스 카프 레이즈', group: 'hamsGlutes', equip: 'machine',
      pattern: 'isolation', met: 3.5, note: '발판 위에 발끝, 위에서 멈춤', muscles: ['종아리'],
      aliases: ['Smith Machine Calf Raise', '스미스 스탠딩 카프', 'Smith Calf Raise', '스미스 머신 카프 레이즈']),
  Exercise(id: 'db-calf-raise', name: '덤벨 카프 레이즈', group: 'hamsGlutes', equip: 'dumbbell',
      pattern: 'isolation', met: 3.5, note: '계단 끝, 한 발씩도 가능', muscles: ['종아리'],
      aliases: ['Dumbbell Calf Raise', '덤벨 스탠딩 카프', '한 발 카프 레이즈', 'Dumbbell Standing Calf Raise']),

  // --- 코어 -----------------------------------------------------------------
  Exercise(id: 'hanging-leg-raise', name: '행잉 레그레이즈', group: 'core', equip: 'bodyweight',
      pattern: 'core', met: 3.8, note: '', muscles: ['복근'], needsBar: true,
      aliases: ['Hanging Leg Raise', '행잉 니 레이즈', '철봉 레그레이즈']),
  Exercise(id: 'cable-crunch', name: '케이블 크런치', group: 'core', equip: 'cable',
      pattern: 'core', met: 3.5, note: '', muscles: ['복근'],
      aliases: ['Cable Crunch', '니링 케이블 크런치', '로프 크런치']),
  Exercise(id: 'plank', name: '플랭크', group: 'core', equip: 'bodyweight',
      pattern: 'hold', met: 3.3, note: '엉덩이가 처지지 않게', muscles: ['복근', '코어'],
      aliases: ['Plank']),
  Exercise(id: 'lying-leg-raise', name: '라잉 레그레이즈', group: 'core', equip: 'bodyweight',
      pattern: 'core', met: 3.8, note: '허리가 뜨면 무릎을 굽히기', muscles: ['복근 아래쪽'],
      aliases: ['Lying Leg Raise', '레그레이즈', '누워서 다리 들기']),
  Exercise(id: 'dead-bug', name: '데드버그', group: 'core', equip: 'bodyweight',
      pattern: 'core', met: 2.8, note: '허리를 바닥에 붙이고 반대 팔다리', muscles: ['복근', '코어'],
      aliases: ['Dead Bug']),
  Exercise(id: 'bird-dog', name: '버드독', group: 'core', equip: 'bodyweight',
      pattern: 'core', met: 2.8, note: '네발 자세에서 반대 팔다리', muscles: ['허리', '코어'],
      aliases: ['Bird Dog']),
  Exercise(id: 'side-plank', name: '사이드 플랭크', group: 'core', equip: 'bodyweight',
      pattern: 'hold', met: 3.3, note: '골반 들고 좌우 각각', muscles: ['옆구리', '코어'],
      aliases: ['Side Plank']),
  Exercise(id: 'hollow-hold', name: '할로우 홀드', group: 'core', equip: 'bodyweight',
      pattern: 'hold', met: 3.5, note: '허리를 바닥에 붙이고', muscles: ['복근'],
      aliases: ['Hollow Hold', '할로우 바디 홀드']),
  Exercise(id: 'crunch', name: '크런치', group: 'core', equip: 'bodyweight',
      pattern: 'core', met: 2.8, note: '목을 당기지 않기', muscles: ['복근'],
      aliases: ['Crunch', 'Sit-Up', '싯업', '윗몸일으키기']),
  Exercise(id: 'plank-shoulder-tap', name: '플랭크 숄더탭', group: 'core', equip: 'bodyweight',
      pattern: 'core', met: 3.8, note: '골반이 흔들리지 않게', muscles: ['코어', '어깨'],
      aliases: ['Plank Shoulder Tap']),
  Exercise(id: 'mountain-climber', name: '마운틴 클라이머', group: 'core', equip: 'bodyweight',
      pattern: 'core', met: 8.0, note: '빠르게 무릎 당기기', muscles: ['코어', '심폐'],
      aliases: ['Mountain Climber']),
  /* 확장 — 헬스장 · 머신 브랜드 조사(2차 피드백 12). 앞 항목이 대체 우선순위에서 이깁니다. */
  Exercise(id: 'ab-crunch-machine', name: '앱 크런치 머신', group: 'core', equip: 'machine',
      pattern: 'core', met: 3.5, note: '갈비뼈를 골반 쪽으로 말기', muscles: ['복근'],
      aliases: ['Ab Crunch Machine', '앱도미널 머신', '복근 머신', '시티드 크런치 머신', '앱 머신', 'Abdominal',
          'Abdominal Crunch', 'Technogym Total Abdominal', 'Life Fitness Insignia Abdominal',
          'Cybex Eagle NX Abdominal', 'Atlantis A-301 Dual Seated Crunch', 'Keiser A300 Abdominal']),
  Exercise(id: 'rotary-torso', name: '로터리 토르소', group: 'core', equip: 'machine',
      pattern: 'rotation', met: 3.5, note: '골반 고정, 상체만 돌리기', muscles: ['옆구리', '복근'],
      aliases: ['Rotary Torso', '토르소 로테이션', '로터리 토르소 머신', '트위스트 머신', '옆구리 머신', 'Torso Rotation',
          'Technogym Rotary Torso', 'Cybex Eagle NX Torso Rotation', 'Precor Rotary Torso',
          'DRAX Rotary Torso']),
  Exercise(id: 'captains-chair-knee-raise', name: '캡틴스 체어 니 레이즈', group: 'core', equip: 'bodyweight',
      pattern: 'core', met: 3.8, note: '팔꿈치 패드에 기대 무릎 당김', muscles: ['복근 아래쪽'], needsBar: true,
      aliases: ['Captain\'s Chair Knee Raise', '캡틴 체어', '니 레이즈', '딥스바 레그레이즈', '버티컬 니 레이즈', 'VKR',
          'Vertical Knee Raise']),
  Exercise(id: 'decline-sit-up', name: '디클라인 싯업', group: 'core', equip: 'bodyweight',
      pattern: 'core', met: 3.8, note: '허리 둥글게 말며 올라오기', muscles: ['복근'], needsBar: true,
      aliases: ['Decline Sit-Up', '디클라인 크런치', '싯업 벤치', '앱 벤치', '윗몸일으키기 벤치', 'Ab Bench']),
  Exercise(id: 'cable-woodchop', name: '케이블 우드찹', group: 'core', equip: 'cable',
      pattern: 'rotation', met: 3.8, note: '팔 펴고 몸통으로 돌리기', muscles: ['옆구리', '복근'],
      aliases: ['Cable Woodchop', '우드찹', '케이블 로테이션', '하이 투 로우 우드찹', '케이블 트위스트', 'Woodchopper']),
  Exercise(id: 'pallof-press', name: '팔로프 프레스', group: 'core', equip: 'cable',
      pattern: 'rotation', met: 3.3, note: '몸이 돌아가지 않게 버티기', muscles: ['코어', '옆구리'],
      aliases: ['Pallof Press', '케이블 팔로프 프레스', '밴드 팔로프 프레스', '안티 로테이션 프레스']),
  Exercise(id: 'ab-rollout', name: '앱 롤아웃', group: 'core', equip: 'bodyweight',
      pattern: 'core', met: 3.8, note: '허리 꺾지 않고 갈 만큼만', muscles: ['복근', '코어'],
      aliases: ['Ab Wheel Rollout', '앱 휠', '앱 롤러', 'AB 슬라이드', '복근 바퀴', 'Ab Wheel']),
  Exercise(id: 'russian-twist', name: '러시안 트위스트', group: 'core', equip: 'bodyweight',
      pattern: 'rotation', met: 3.8, note: '가슴 들고 몸통을 좌우로', muscles: ['옆구리', '복근'],
      aliases: ['Russian Twist', '덤벨 러시안 트위스트', '메디신볼 트위스트']),
  Exercise(id: 'bicycle-crunch', name: '바이시클 크런치', group: 'core', equip: 'bodyweight',
      pattern: 'core', met: 3.8, note: '반대 팔꿈치와 무릎 맞대기', muscles: ['복근', '옆구리'],
      aliases: ['Bicycle Crunch', '자전거 크런치', '바이시클']),

  // --- 전신 (맨몸 서킷) -------------------------------------------------------
  Exercise(id: 'burpee', name: '버피', group: 'full', equip: 'bodyweight',
      pattern: 'full', met: 8.0, note: '힘들면 점프 생략', muscles: ['전신', '심폐'],
      aliases: ['Burpee']),
  Exercise(id: 'jumping-jack', name: '점핑잭', group: 'full', equip: 'bodyweight',
      pattern: 'full', met: 8.0, note: '', muscles: ['전신', '심폐'],
      aliases: ['Jumping Jack', '팔벌려뛰기']),
  Exercise(id: 'high-knees', name: '하이니', group: 'full', equip: 'bodyweight',
      pattern: 'full', met: 8.0, note: '제자리에서 무릎 높이', muscles: ['심폐', '코어'],
      aliases: ['High Knees']),
  Exercise(id: 'jump-rope', name: '줄넘기', group: 'full', equip: 'bodyweight',
      pattern: 'full', met: 11.0, note: '', muscles: ['종아리', '심폐'],
      aliases: ['Jump Rope', '스킵핑']),
  Exercise(id: 'bear-crawl', name: '베어 크롤', group: 'full', equip: 'bodyweight',
      pattern: 'full', met: 5.0, note: '무릎을 살짝 띄우고 기어가기', muscles: ['전신', '코어'],
      aliases: ['Bear Crawl']),
  /* 확장 — 헬스장 · 머신 브랜드 조사(2차 피드백 12). 앞 항목이 대체 우선순위에서 이깁니다. */
  Exercise(id: 'farmers-walk', name: '파머스 워크', group: 'full', equip: 'dumbbell',
      pattern: 'carry', met: 5.0, note: '어깨 내리고 똑바로 걷기', muscles: ['전완', '승모근', '코어'],
      aliases: ['Farmer\'s Carry', '파머스 캐리', '덤벨 파머스 워크', '케틀벨 파머스 워크', 'Farmers Walk']),
  Exercise(id: 'suitcase-carry', name: '수트케이스 캐리', group: 'full', equip: 'dumbbell',
      pattern: 'carry', met: 4.5, note: '한 손만 들고 몸 기울지 않게', muscles: ['옆구리', '코어', '전완'],
      aliases: ['Suitcase Carry', '원핸드 캐리', '한 손 파머스 워크', 'Suitcase Walk']),
  Exercise(id: 'sled-push', name: '슬레드 푸시', group: 'full', equip: 'machine',
      pattern: 'carry', met: 6.0, note: '팔 펴고 낮게 밀기', muscles: ['허벅지 앞', '엉덩이', '심폐'],
      aliases: ['Sled Push', '프라울러 푸시', '썰매 밀기', '슬레드', 'Prowler Push',
          'Hammer Strength HD Athletic Sled', 'Technogym Sled']),
  Exercise(id: 'db-thruster', name: '덤벨 쓰러스터', group: 'full', equip: 'dumbbell',
      pattern: 'squat', met: 6.0, note: '스쿼트 반동으로 머리 위로', muscles: ['허벅지 앞', '어깨', '심폐'],
      aliases: ['Dumbbell Thruster', '쓰러스터', '케틀벨 쓰러스터', 'Thruster']),
  Exercise(id: 'box-jump', name: '박스 점프', group: 'full', equip: 'bodyweight',
      pattern: 'squat', met: 8.0, note: '착지는 조용히, 내려올 땐 걸어서', muscles: ['허벅지 앞', '엉덩이', '심폐'],
      aliases: ['Box Jump', '플라이오 박스 점프', 'Plyo Box Jump']),
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

/// 이름이나 **별칭**으로 찾기 — 글자 그대로 → 띄어쓰기·대소문자 무시.
/// 부분 일치는 안 합니다(그건 searchExercises). exerciseByName 은 엔진 이름
/// 전용이라 손대지 않고, 사람이 부르는 말('이너싸이' · 'Smith Squat')은 여기로.
Exercise? exerciseByAlias(String q) {
  final byName = exerciseByName(q);
  if (byName != null) return byName;
  final qn = _loose(q);
  if (qn.isEmpty) return null;
  for (final e in kExerciseLibrary) {
    for (final a in e.aliases) {
      if (_loose(a) == qn) return e;
    }
  }
  return null;
}

/// 검색 — 이름 · 별칭(영문 포함)에 부분 일치, 공백·대소문자 무시. 이름이 맞은
/// 것이 별칭만 맞은 것보다 앞이고, 그 안에서는 사전 순서입니다. equip 을 주면
/// 그 기구의 종목만. 빈 검색어는 빈 목록 — "전부" 는 exercisesFor 로.
List<Exercise> searchExercises(String q, {Set<String>? equip}) {
  final qn = _loose(q);
  if (qn.isEmpty) return const [];
  final byName = <Exercise>[];
  final byAlias = <Exercise>[];
  for (final e in kExerciseLibrary) {
    if (equip != null && !equip.contains(e.equip)) continue;
    if (_loose(e.name).contains(qn)) {
      byName.add(e);
    } else if (e.aliases.any((a) => _loose(a).contains(qn))) {
      byAlias.add(e);
    }
  }
  return [...byName, ...byAlias];
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
