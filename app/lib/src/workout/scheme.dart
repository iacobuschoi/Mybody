/* =============================================================================
 * scheme.dart — 종목마다 세트 · 횟수 · 쉬는 시간을 정합니다
 *
 * 엔진(mybody_core engine.workoutFor)은 이름에 '스쿼트|데드|벤치|프레스|로우|풀업|딥스'
 * 가 있으면 5-8회 · 150초, 아니면 10-15회 · 75초 — 두 칸뿐입니다. 그래서 맨몸
 * 스쿼트에 바벨 규칙이 붙고("누가 스쿼트를 8개씩 세 세트 해", 3차 피드백 31) 플랭크에
 * 「10-15회」 가 붙었습니다. 여기서는 기구 · 움직임 · 경력 · 목표 네 축으로 다시
 * 정합니다. planner 는 종목만 바꾸고, 숫자를 바꾸는 곳은 여기 하나입니다.
 *
 * 규칙표 (횟수는 초보 / 중급 / 고급 · 휴식은 초)
 *   바벨 복합(스쿼트 · 데드 · 벤치 · 오버헤드 · 로우)
 *     근비대(감량 · 유지 · 목표 없음)  8-12 / 6-10 / 6-10   휴식 120 / 150 / 150
 *     근력(증량)                        8-12 / 5-8  / 4-6    휴식 120 / 180 / 180
 *     초보는 목표와 상관없이 8-12 — 기술 습득이 먼저입니다(ACSM 2009 "novice 8-12RM").
 *   머신 · 덤벨 · 케이블 · 케틀벨 복합    8-12                 휴식 90
 *   고립(컬 · 익스텐션 · 레이즈 · 플라이 · 카프 · 어브덕션 · 코어 머신)
 *                                        12-15 / 10-15 / 10-15  휴식 60
 *   맨몸 기본(맨몸 스쿼트 · 브릿지 · 카프 · 푸시업류 · 인버티드 로우)
 *                                        종목표 (예: 스쿼트 15-20 / 20-25 / 25-30) 휴식 60
 *   맨몸 코어 반복(크런치 · 레그레이즈 · 버드독 · 데드버그)     종목표  휴식 45
 *   고난도 맨몸(풀업 · 딥스 · 행잉 레그레이즈 · 노르딕 · GHR · 파이크 · 롤아웃)
 *                                        종목표 (예: 풀업 3-6 / 6-10 / 10-15) 휴식 90
 *   편측(런지 · 스플릿 · 스텝업 · 싱글레그 · 원암 · 킥백)        한쪽당 · 양쪽이 1세트
 *   등척성(플랭크 · 사이드 플랭크 · 월 싯 · 할로우 홀드 · 데드행)
 *                                        30 / 45 / 60초 (사이드 · 할로우 20 / 30 / 45) 휴식 45
 *   유산소성 맨몸(버피 · 마운틴 클라이머 · 점핑잭 · 하이니 · 줄넘기 · 베어 크롤)
 *                                        30 / 40 / 45초, 휴식은 한 만큼(1:1)
 *   플라이오(점프 스쿼트 · 박스 점프)     5-6 / 6-8 / 8-10     휴식 90
 *   캐리(파머스 워크 · 수트케이스 · 슬레드) 30 / 40 / 45초     휴식 60
 *   세트: 초보 3 · 중급 3(복합 4) · 고급 4 · 등척성 · 유산소성은 3.
 *         엔진이 더 많이 줬으면(setsPerMuscle >= 16 → 4) 그 수를 둡니다(최대 5).
 *
 * 출처 (수치는 검색 스니펫으로 교차 확인)
 *   ACSM 2009 Progression Models  https://pubmed.ncbi.nlm.nih.gov/19204579/
 *   ACSM 2011 Quantity and Quality https://pubmed.ncbi.nlm.nih.gov/21694556/
 *   ACSM 2026 저항운동 포지션 스탠드 https://acsm.org/resistance-training-guidelines-update-2026/
 *   NSCA Essentials 17장 표(2차)   https://www.ptpioneer.com/personal-training/certifications/nsca-cscs/cscs-chapter-17/
 *   Schoenfeld 2016 휴식 3분>1분   https://pubmed.ncbi.nlm.nih.gov/26605807/
 *   Schoenfeld 2017 주 10세트      https://pubmed.ncbi.nlm.nih.gov/27433992/
 *   NASM OPT · RIR                 https://blog.nasm.org/nasm-optimum-performance-training
 *   맨몸 스쿼트 12-20              https://www.eosfitness.com/blog/how-many-squats-should-i-do
 *   런지 8-12/한쪽                 https://www.acefitness.org/resources/everyone/blog/6971/5-lunge-variations-for-leaner-legs/
 *   푸시업 진행                    https://www.odin.fitness/blog/push-up-progression-beginner-to-advanced
 *   글루트 브릿지 3×15-20          https://www.onepeloton.com/blog/glute-bridge
 *   플랭크 20-60초                 https://www.endomondo.com/training/how-long-you-should-hold-a-plank
 *   월 싯 20-30/45-60/60-90초      https://www.eatthis.com/wall-sit-fitness-test/
 *   행잉 레그레이즈 5-8→12-15      https://barbend.com/hanging-leg-raises/
 *   딥스 3-5→6-8→8-12              https://calisteniapp.com/articles/how-to-do-parallel-bar-dips
 *   풀업 기준                      https://denstarfitness.com/how-many-pull-ups-should-i-be-able-to-do/
 *   인버티드 로우 3×8-15           https://bodytree.app/exercises/inverted-rows
 *   코어 초보 3×8-15               https://www.crunch.com/thehub/best-core-muscle-workout-for-beginners/
 *   버피 3×5→8-12                  https://repfitness.com/blogs/training/how-to-do-burpee-exercise
 *   점프 스쿼트 3×8-10             https://www.nasm.org/resource-center/exercise-library/squat-jump
 *   60분 = 종목 5-7 · 15-22세트    https://www.aworkoutroutine.com/how-long-should-my-workout-be/
 *   노르딕 · 할로우 · 줄넘기 · 베어 크롤 · 슈퍼맨 · 캐리 수치는 같은 부류 규칙에서 유추.
 * ========================================================================== */
library;

import 'exercises.dart';

/// 한 종목의 세트 · 횟수 · 쉬는 시간. [reps] 가 비어 있으면 [seconds] 로 하는 종목입니다.
class Scheme {
  const Scheme({
    required this.sets,
    required this.reps,
    this.seconds,
    required this.restSec,
    this.perSide = false,
    this.why = '',
  });

  final int sets;
  /// '8-12' 처럼 구간. 초 단위 종목이면 ''.
  final String reps;
  /// 등척성 · 유산소성 · 캐리처럼 시간으로 하는 종목의 초. 반복 종목이면 null.
  final int? seconds;
  final int restSec;
  /// 한쪽씩 하는 종목 — 표시는 「10-12 한쪽씩」, 양쪽을 다 하면 1세트.
  final bool perSide;
  /// 왜 이 숫자인지 한 줄. 화면이 요령 줄 밑에 흐리게 둘 수 있습니다. 휴식 초는 적지
  /// 않습니다 — planner.fitRestToBudget 이 restSec 만 깎아서 글과 숫자가 어긋납니다.
  final String why;

  bool get timed => seconds != null;

  /// 화면 문자열 — '15-20' · '30초' · '10-12 한쪽씩'.
  String get amount => _amount(reps, seconds, perSide);

  Scheme copyWith({int? sets, int? restSec}) => Scheme(
        sets: sets ?? this.sets,
        reps: reps,
        seconds: seconds,
        restSec: restSec ?? this.restSec,
        perSide: perSide,
        why: why,
      );

  @override
  String toString() => 'Scheme($sets × $amount · rest $restSec)';
}

/// 계획 줄(Map)의 「몇 번」 — 'seconds' 가 있으면 초, 아니면 'reps', 편측이면 「한쪽씩」.
/// planner 가 남긴 줄 · 루틴 · 기록 어디에서나 같은 글자가 나오게 여기 한 곳에 둡니다.
String amountLabel(Map<String, Object?> e) {
  final sec = e['seconds'];
  final seconds = sec is num && sec > 0 ? sec.round() : null;
  return _amount('${e['reps'] ?? ''}', seconds, e['perSide'] == true);
}

String _amount(String reps, int? seconds, bool perSide) {
  final base = seconds != null ? '$seconds초' : reps;
  if (base.isEmpty) return '';
  return perSide ? '$base 한쪽씩' : base;
}

/// 반복 한 번에 걸리는 시간 어림 — bodyweight.dart 와 같은 3초(내렸다 올리기).
const int kSecPerRep = 3;

/// 계획 줄 한 세트의 동작 시간(초). 초 단위 종목은 그 초, 반복 종목은 구간의 위 숫자 × 3초,
/// 편측이면 양쪽이라 두 배. 세션 예산(planner) 과 시간 어림이 같은 값을 쓰게.
int workSecondsOf(Map<String, Object?> e) {
  final sec = e['seconds'];
  if (sec is num && sec > 0) return sec.round();
  final high = RegExp(r'\d+').allMatches('${e['reps'] ?? ''}').map((m) => int.parse(m.group(0)!));
  final reps = high.isEmpty ? 12 : high.last;
  return reps * kSecPerRep * (e['perSide'] == true ? 2 : 1);
}

/* --- 분류표 -----------------------------------------------------------------
 *
 * 사전(exercises.dart)의 id 로 셉니다 — 이름 정규식이 '맨몸 스쿼트' 를 바벨로
 * 잡은 것이 엔진의 버그였습니다. 사전에 없는 종목(사용자가 적은 이름)만 아래
 * 낱말표로 봅니다.
 * -------------------------------------------------------------------------- */

/// 버티는 종목 — 초 단위.
const Set<String> kIsometricIds = {'plank', 'side-plank', 'wall-sit', 'hollow-hold'};
const List<String> _isometricWords = ['플랭크', '월 싯', '월싯', '홀드', '데드행', '데드 행', '버티기'];

/// 유산소성 맨몸 — 초 단위, 한 만큼 쉽니다.
const Set<String> kCardioIds = {
  'burpee', 'jumping-jack', 'high-knees', 'jump-rope', 'bear-crawl', 'mountain-climber',
};
const List<String> _cardioWords = ['버피', '점핑잭', '하이니', '줄넘기', '베어 크롤', '마운틴 클라이머', '스케이터'];

/// 들고 걷는 종목 — 초 단위.
const List<String> _carryWords = ['워크', '캐리', '슬레드'];

/// 뛰는 종목 — 신경 부담이 커서 적게, 길게 쉬고.
const Set<String> kPlyoIds = {'jump-squat', 'box-jump'};
const List<String> _plyoWords = ['점프'];

/// 체중이 곧 무게인 맨몸 — 복합 근력 규칙(긴 휴식).
const Set<String> kHardBodyweightIds = {
  'pull-up', 'dips', 'hanging-leg-raise', 'nordic-curl', 'glute-ham-raise', 'pike-push-up', 'ab-rollout',
};

/// 반복형 코어 · 등 아래 맨몸 — 짧게 쉽니다.
const Set<String> _coreRepsIds = {
  'crunch', 'lying-leg-raise', 'dead-bug', 'bird-dog', 'plank-shoulder-tap', 'decline-sit-up',
  'bicycle-crunch', 'russian-twist', 'superman', 'prone-y-raise', 'reverse-snow-angel',
  'captains-chair-knee-raise',
};

/// 한쪽씩 하는 종목.
const Set<String> kPerSideIds = {
  'lunge', 'split-squat', 'step-up', 'bulgarian-split-squat', 'walking-lunge', 'reverse-lunge',
  'smith-lunge', 'single-leg-glute-bridge', 'single-leg-rdl', 'clamshell', 'donkey-kick',
  'bird-dog', 'dead-bug', 'bicycle-crunch', 'russian-twist', 'plank-shoulder-tap', 'side-plank',
  'one-arm-db-row', 'suitcase-carry', 'concentration-curl', 'db-kickback', 'cable-triceps-kickback',
  'cable-glute-kickback', 'glute-kickback-machine', 'cable-hip-abduction', 'cable-woodchop',
  'pallof-press', 'multi-hip-machine', 'standing-leg-curl', 'band-lateral-walk', 'cable-lateral-raise',
};
const List<String> _perSideWords = [
  '런지', '스플릿', '스텝업', '싱글레그', '원암', '한 발', '한쪽', '한 팔', '사이드 플랭크', '킥백',
  '클램쉘', '덩키', '버드독', '데드버그', '바이시클', '러시안', '숄더탭', '수트케이스', '컨센트레이션',
  '우드찹', '팔로프', '사이드 워크', '원레그',
];

/// 이름으로는 복합 같지만 한 관절만 쓰는 것 — 고립 규칙.
const Set<String> _isolationOverrideIds = {
  'db-shrug', 'smith-shrug', 'pullover-machine', 'straight-arm-pulldown', 'face-pull', 'band-face-pull',
};
/// 바벨이지만 큰 세 가지 리프트가 아닌 것 — 머신 · 덤벨 규칙.
const Set<String> _lightBarbellIds = {'landmine-press'};
const List<String> _isolationWords = [
  '컬', '익스텐션', '레이즈', '플라이', '카프', '어브덕션', '어덕션', '킥백', '슈러그', '크런치', '푸시다운',
  '페이스풀', '토르소', '우드찹', '팔로프',
];

const Set<String> _compoundPatterns = {'squat', 'hinge', 'lunge', 'push-h', 'push-v', 'pull-h', 'pull-v', 'full'};
const Set<String> _isolationPatterns = {
  'isolation', 'curl', 'extension', 'raise', 'fly', 'abduction', 'adduction', 'rotation', 'core',
};

/* --- 숫자표 (초보 / 중급 / 고급) ------------------------------------------------ */

/// 맨몸 종목의 반복 구간. 없는 맨몸 종목은 [kBodyweightDefaultReps].
const Map<String, List<String>> kBodyweightReps = {
  'bodyweight-squat': ['15-20', '20-25', '25-30'],
  'lunge': ['8-12', '12-15', '15-20'],
  'split-squat': ['8-12', '12-15', '15-20'],
  'step-up': ['10-12', '12-15', '15-20'],
  'glute-bridge': ['15-20', '20-25', '20-25'],
  'single-leg-glute-bridge': ['8-12', '12-15', '15-20'],
  'calf-raise': ['15-20', '20-25', '25-30'],
  'push-up': ['8-12', '12-20', '20-30'],
  'incline-push-up': ['12-15', '15-20', '15-20'],
  'decline-push-up': ['8-12', '12-15', '15-20'],
  'diamond-push-up': ['6-10', '10-15', '15-20'],
  'pike-push-up': ['6-10', '10-15', '15-20'],
  'dips': ['3-6', '6-10', '10-15'],
  'bench-dips': ['8-12', '12-15', '15-20'],
  'pull-up': ['3-6', '6-10', '10-15'],
  'inverted-row': ['8-12', '12-15', '12-15'],
  'superman': ['10-15', '15-20', '20-25'],
  'prone-y-raise': ['10-15', '15-20', '15-20'],
  'reverse-snow-angel': ['10-15', '15-20', '15-20'],
  'hanging-leg-raise': ['5-8', '8-12', '12-15'],
  'captains-chair-knee-raise': ['8-12', '12-15', '15-20'],
  'lying-leg-raise': ['10-12', '12-15', '15-20'],
  'crunch': ['12-15', '15-20', '20-25'],
  'decline-sit-up': ['8-12', '12-15', '15-20'],
  'bicycle-crunch': ['10-12', '12-15', '15-20'],
  'russian-twist': ['10-12', '12-15', '15-20'],
  'dead-bug': ['8-10', '10-12', '12-15'],
  'bird-dog': ['8-10', '10-12', '12-15'],
  'plank-shoulder-tap': ['8-10', '10-15', '15-20'],
  'ab-rollout': ['5-8', '8-12', '12-15'],
  'nordic-curl': ['3-5', '5-8', '8-12'],
  'glute-ham-raise': ['5-8', '8-12', '12-15'],
  'clamshell': ['12-15', '15-20', '20-25'],
  'donkey-kick': ['12-15', '15-20', '20-25'],
  'back-extension-45': ['10-15', '15-20', '15-20'],
  'jump-squat': ['5-6', '6-8', '8-10'],
  'box-jump': ['5-6', '6-8', '8-10'],
  'kettlebell-swing': ['10-15', '15-20', '15-20'],
  'band-lateral-walk': ['10-12', '12-15', '15-20'],
};
const List<String> kBodyweightDefaultReps = ['12-15', '15-20', '20-25'];
const List<String> kPlyoDefaultReps = ['5-6', '6-8', '8-10'];

/// 버티는 초. 없는 등척성 종목은 [kHoldSecDefault].
const Map<String, List<int>> kHoldSec = {
  'plank': [30, 45, 60],
  'wall-sit': [30, 45, 60],
  'side-plank': [20, 30, 45],
  'hollow-hold': [20, 30, 45],
};
const List<int> kHoldSecDefault = [30, 45, 60];
const List<int> kCardioSec = [30, 40, 45];
const List<int> kCarrySec = [30, 40, 45];

const List<String> kBarbellHypertrophyReps = ['8-12', '6-10', '6-10'];
const List<String> kBarbellStrengthReps = ['8-12', '5-8', '4-6'];
const List<int> kBarbellHypertrophyRest = [120, 150, 150];
const List<int> kBarbellStrengthRest = [120, 180, 180];
const String kMachineReps = '8-12';
const int kMachineRest = 90;
const List<String> kIsolationReps = ['12-15', '10-15', '10-15'];
const int kIsolationRest = 60;
const int kBodyweightRest = 60;
const int kCoreRest = 45;
const int kHardBodyweightRest = 90;
const int kIsometricRest = 45;
const int kPlyoRest = 90;
const int kCarryRest = 60;
/// 종목당 세트 상한 — 더 필요하면 세트가 아니라 종목을 늘립니다.
const int kMaxSets = 5;

/// 종목의 부류. 숫자표를 고르는 열쇠입니다.
enum SchemeKind { isometric, cardio, carry, plyo, hardBodyweight, core, bodyweight, barbell, machine, isolation }

/// 경력 → 표의 칸. 모르면 초보.
int _levelOf(String trainingAge) => switch (trainingAge) {
      'advanced' => 2,
      'intermediate' => 1,
      _ => 0,
    };

bool _has(String name, List<String> words) => words.any(name.contains);

/// 종목이 어느 부류인가. 사전에 있으면 id · pattern 으로, 없으면 이름 낱말과
/// 엔진의 판단([isCompound])으로. 사전에도 없고 낱말도 안 걸리고 엔진도 복합이
/// 아니라 했으면 null — 그때는 엔진이 준 숫자를 그대로 둡니다(모르는 종목은 엔진 말).
SchemeKind? schemeKindOf({
  required Exercise? exercise,
  required String name,
  required String equip,
  required String pattern,
  required bool isCompound,
}) {
  final id = exercise?.id ?? '';
  final known = exercise != null;
  if (known) {
    if (pattern == 'hold' || kIsometricIds.contains(id)) return SchemeKind.isometric;
    if (kCardioIds.contains(id)) return SchemeKind.cardio;
    if (pattern == 'carry') return SchemeKind.carry;
    if (kPlyoIds.contains(id)) return SchemeKind.plyo;
    if (kHardBodyweightIds.contains(id)) return SchemeKind.hardBodyweight;
    if (equip == 'bodyweight') {
      return pattern == 'core' || _coreRepsIds.contains(id) ? SchemeKind.core : SchemeKind.bodyweight;
    }
    if (_isolationOverrideIds.contains(id) || _isolationPatterns.contains(pattern)) return SchemeKind.isolation;
    if (_compoundPatterns.contains(pattern)) {
      return equip == 'barbell' && !_lightBarbellIds.contains(id) ? SchemeKind.barbell : SchemeKind.machine;
    }
    return isCompound ? SchemeKind.machine : SchemeKind.isolation;
  }
  if (_has(name, _isometricWords)) return SchemeKind.isometric;
  if (_has(name, _cardioWords)) return SchemeKind.cardio;
  if (_has(name, _carryWords)) return SchemeKind.carry;
  if (_has(name, _plyoWords)) return SchemeKind.plyo;
  if (equip == 'bodyweight') return SchemeKind.bodyweight;
  if (_has(name, _isolationWords)) return SchemeKind.isolation;
  if (isCompound) return equip == 'barbell' ? SchemeKind.barbell : SchemeKind.machine;
  return null;
}

/// 한쪽씩 하는 종목인가.
bool isPerSide({required Exercise? exercise, required String name}) =>
    exercise != null ? kPerSideIds.contains(exercise.id) : _has(name, _perSideWords);

/// 종목 하나의 세트 · 횟수 · 휴식.
///
/// [goalKind] 는 'cut' · 'bulk' · 'recomp' · '' — 증량(bulk)만 바벨 복합을 근력 구간으로
/// 내립니다(중급 5-8 · 고급 4-6). 나머지는 근비대 구간. [trainingAge] 는 프로필의
/// 경력(novice · intermediate · advanced). [isCompound] 는 엔진의 판단(5-8 을 줬는가) —
/// 사전에 없는 종목에서만 씁니다. [engineSets] 가 표보다 많으면 그대로 둡니다 —
/// setsPerMuscle 로 정한 볼륨이고, 기구가 바뀌어도 몸이 필요한 양은 같습니다.
Scheme schemeFor({
  required Exercise? exercise,
  required String name,
  required String equip,
  required String pattern,
  required String goalKind,
  required String trainingAge,
  required bool isCompound,
  int? engineSets,
  String? engineReps,
  int? engineRestSec,
}) {
  final level = _levelOf(trainingAge);
  final id = exercise?.id ?? '';
  final perSide = isPerSide(exercise: exercise, name: name);
  final kind = schemeKindOf(
      exercise: exercise, name: name, equip: equip, pattern: pattern, isCompound: isCompound);
  if (kind == null) {
    /* 사전에 없는 종목 — 사용자가 적은 이름 · 다른 앱에서 온 루틴. 엔진(또는 루틴)이 준
       숫자가 있으면 그것이 답이고, 그것도 없으면 대부분의 성인에게 맞는 8-12 입니다. */
    final engine = engineReps ?? '';
    return Scheme(
      sets: engineSets == null || engineSets < 1 ? 3 : (engineSets > kMaxSets ? kMaxSets : engineSets),
      reps: engine.isEmpty ? kMachineReps : engine,
      restSec: engineRestSec == null || engineRestSec < 0 ? kMachineRest : engineRestSec,
      perSide: perSide,
    );
  }
  final strength = goalKind == 'bulk';

  String reps = '';
  int? seconds;
  int rest;
  String why;
  switch (kind) {
    case SchemeKind.isometric:
      seconds = (kHoldSec[id] ?? kHoldSecDefault)[level];
      rest = kIsometricRest;
      why = '$seconds초 버티기 · 되면 5초씩 더';
    case SchemeKind.cardio:
      seconds = kCardioSec[level];
      rest = seconds;
      why = '$seconds초 힘껏 하고 쉬기';
    case SchemeKind.carry:
      seconds = kCarrySec[level];
      rest = kCarryRest;
      why = '$seconds초 걷기 · 허리 곧게';
    case SchemeKind.plyo:
      reps = (kBodyweightReps[id] ?? kPlyoDefaultReps)[level];
      rest = kPlyoRest;
      why = '착지는 조용히 · 충분히 쉬고 다음';
    case SchemeKind.hardBodyweight:
      reps = (kBodyweightReps[id] ?? kBodyweightDefaultReps)[level];
      rest = kHardBodyweightRest;
      why = '체중이 곧 무게 · 길게 쉬기';
    case SchemeKind.core:
      reps = (kBodyweightReps[id] ?? kBodyweightDefaultReps)[level];
      rest = kCoreRest;
      why = perSide ? '$reps회 한쪽씩 · 양쪽이 1세트' : '$reps회 · 허리 아프면 플랭크로';
    case SchemeKind.bodyweight:
      reps = (kBodyweightReps[id] ?? kBodyweightDefaultReps)[level];
      rest = kBodyweightRest;
      why = perSide ? '$reps회 한쪽씩 · 양쪽이 1세트' : '맨몸은 $reps회 · 쉬우면 다음 변형';
    case SchemeKind.barbell:
      reps = (strength ? kBarbellStrengthReps : kBarbellHypertrophyReps)[level];
      rest = (strength ? kBarbellStrengthRest : kBarbellHypertrophyRest)[level];
      why = level == 0
          ? '초보는 8-12회로 자세부터'
          : (strength ? '근력은 $reps회 · 길게 쉬기' : '큰 운동은 $reps회 · 충분히 쉬기');
    case SchemeKind.machine:
      reps = kMachineReps;
      rest = kMachineRest;
      why = perSide ? '$reps회 한쪽씩 · 12회 되면 무게 올리기' : '$reps회 · 12회 되면 무게 올리기';
    case SchemeKind.isolation:
      reps = kIsolationReps[level];
      rest = kIsolationRest;
      why = '가볍게 $reps회 · 관절 보호';
  }

  /* 세트 — 초보 3 · 중급 3(복합 4) · 고급 4. 시간 종목은 3. */
  final compoundLike =
      kind == SchemeKind.barbell || kind == SchemeKind.machine || kind == SchemeKind.hardBodyweight;
  final timed = kind == SchemeKind.isometric || kind == SchemeKind.cardio || kind == SchemeKind.carry;
  var sets = switch (level) {
    0 => 3,
    1 => compoundLike ? 4 : 3,
    _ => timed || kind == SchemeKind.plyo ? 3 : 4,
  };
  if (engineSets != null && engineSets > sets) sets = engineSets < kMaxSets ? engineSets : kMaxSets;

  return Scheme(sets: sets, reps: reps, seconds: seconds, restSec: rest, perSide: perSide, why: why);
}
