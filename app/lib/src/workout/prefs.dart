/* =============================================================================
 * prefs.dart — 내 운동 환경 (state['settings']['gym'])
 *
 * 헬스장인지 집인지, 어떤 기구가 있는지, 머신은 몇 개까지 쓸지, 잘 아는
 * 종목은 무엇인지. 엔진이 짠 계획을 이 사람 자리에 맞게 고치는 재료입니다.
 *
 * settings 안에 두는 이유: settings 는 기기 사이에 동기화되는 칸입니다.
 * 헬스장 기구 목록은 폰을 바꿔도 같아야 하고, 몸 숫자처럼 숨길 것도
 * 아닙니다. 그래서 값은 전부 **JSON 으로 그대로 적히는 것**만 씁니다
 * (문자열 · 정수 · 문자열 목록). Set 은 저장할 때 정렬한 목록이 됩니다.
 * ========================================================================== */
library;

import 'dart:math' as math;

import 'exercises.dart';

/// 헬스장에 있는 것 전부 — 「기구가 다 있는 헬스장」 의 뜻입니다(const GymPrefs()).
const Set<String> kGymEquipment = {'barbell', 'dumbbell', 'machine', 'cable', 'bodyweight'};

/// 집은 반대로, 흔히 있는 것만.
const Set<String> kHomeEquipment = {'bodyweight', 'dumbbell', 'band'};

/// 초보 프리셋의 기구 — 머신 · 케이블 · 덤벨(+맨몸). 바벨은 뺍니다: 무슨 운동을
/// 할지 모르는 사람에게 바벨 벤치 · 스쿼트부터 주면 첫날 헬스장에서 멈춥니다.
/// 머신은 자리에 앉아 손잡이를 밀면 되고, 덤벨은 무게를 고르기 쉽습니다.
const Set<String> kBeginnerEquipment = {'machine', 'cable', 'dumbbell', 'bodyweight'};

/// 초보 프리셋의 「하루에 쓸 머신 수」 — 한 시간 루틴에 머신 4개 + 덤벨.
const int kBeginnerMachineCount = 4;

/// 「하루에 쓸 머신 수」 의 가장 작은 눈금. 0 · 1 은 눈금에 없습니다 — 머신을
/// 안 쓰는 사람은 머신 · 케이블 타일을 끕니다. 옛 판(0 눈금이 있던 0.2.11)의
/// 저장값은 읽을 때 여기로 올립니다. 그래야 세그먼트가 켜 보이는 값과 실제
/// 규칙이 같습니다.
const int kMachineCountMin = 2;

const Object _keep = Object();

class GymPrefs {
  /// 'gym' | 'home'
  final String place;
  /// 있는 기구 (kEquipLabel 의 키).
  final Set<String> equipment;
  /// 한 세션에 머신·케이블 종목을 몇 개까지. null 이면 제한 없음.
  /// 붐비는 헬스장에서 머신 다섯 개를 돌아다니는 건 계획이 아니라 대기입니다.
  final int? machineCount;
  /// 잘 아는 종목의 고유번호. 계획에 같은 부위가 있으면 이걸 우선 넣습니다.
  final List<String> familiar;

  const GymPrefs({
    this.place = 'gym',
    Set<String>? equipment,
    this.machineCount,
    this.familiar = const [],
  }) : equipment = equipment ?? (place == 'home' ? kHomeEquipment : kGymEquipment);

  /// 초보 프리셋 — 헬스장 · 머신 4개 + 덤벨 · 익숙한 종목 없음. 설정을 한 번도
  /// 안 만진 사람의 값입니다(2차 피드백 15: "초보자는 무슨 운동을 해야 하는지
  /// 모른다"). 저장된 설정이 있으면 그 사람 것이 이깁니다.
  const GymPrefs.beginner()
      : this(place: 'gym', equipment: kBeginnerEquipment, machineCount: kBeginnerMachineCount);

  bool get isHome => place == 'home';

  /// 지금 값이 초보 프리셋 그대로인가 — 화면이 「초보 기본」 표를 붙이는 기준.
  bool get isBeginnerPreset =>
      !isHome &&
      machineCount == kBeginnerMachineCount &&
      familiar.isEmpty &&
      equipment.length == kBeginnerEquipment.length &&
      equipment.containsAll(kBeginnerEquipment);

  /// 그 자리의 기본 기구 — 헬스장은 "다 있음" 입니다(있는 것을 빼는 쪽이 빠릅니다).
  static Set<String> defaultEquipment(String place) =>
      place == 'home' ? {...kHomeEquipment} : {...kGymEquipment};

  /// 장소를 고를 때 그 자리의 프리셋 — 헬스장은 초보 프리셋, 집은 집 기본.
  /// 화면이 장소 카드를 누르면 기구와 머신 수를 여기서 받고 익숙한 종목은 지킵니다.
  static GymPrefs presetFor(String place) =>
      place == 'home' ? const GymPrefs(place: 'home') : const GymPrefs.beginner();

  /// settings['gym'] 에서 읽습니다. 없거나 깨져 있으면 초보 프리셋 —
  /// 설정을 한 번도 안 만진 사람이 대부분이고, 그 사람에게는 머신 4개 + 덤벨
  /// 한 시간 루틴이 엔진의 바벨 계획보다 낫습니다.
  static GymPrefs fromSettings(Map<String, Object?>? settings) {
    final raw = settings?['gym'];
    if (raw is! Map) return const GymPrefs.beginner();
    final g = raw;

    final place = g['place'] == 'home' ? 'home' : 'gym';

    Set<String>? equipment;
    final eq = g['equipment'];
    if (eq is List) {
      equipment = {
        for (final x in eq)
          if (x is String && kEquipLabel.containsKey(x)) x,
      };
      /* 몸은 언제나 있습니다. 전부 지운 목록은 "아무것도 못 한다" 가 아니라
         "기구가 없다" 는 뜻입니다. */
      equipment.add('bodyweight');
    }

    int? machineCount;
    final mc = g['machineCount'];
    if (mc is num && mc.isFinite && mc >= 0) machineCount = math.max(kMachineCountMin, mc.toInt());

    final fam = <String>[];
    final f = g['familiar'];
    if (f is List) {
      for (final x in f) {
        if (x is String && x.isNotEmpty && !fam.contains(x)) fam.add(x);
      }
    }

    return GymPrefs(
      place: place,
      equipment: equipment ?? defaultEquipment(place),
      machineCount: machineCount,
      familiar: fam,
    );
  }

  /// settings['gym'] 에 넣을 모양. 정렬해 두면 같은 설정은 같은 글자가 됩니다 —
  /// 동기화가 "바뀌었나" 를 글자로 비교하기 때문입니다.
  Map<String, Object?> toJson() => {
        'place': place,
        'equipment': equipment.toList()..sort(),
        'machineCount': machineCount,
        'familiar': List<String>.of(familiar),
      };

  /// machineCount 는 null 로 지울 수 있어야 해서 "안 줌" 과 "null" 을 구분합니다.
  GymPrefs copyWith({
    String? place,
    Set<String>? equipment,
    Object? machineCount = _keep,
    List<String>? familiar,
  }) =>
      GymPrefs(
        place: place ?? this.place,
        equipment: equipment ?? this.equipment,
        machineCount: identical(machineCount, _keep) ? this.machineCount : machineCount as int?,
        familiar: familiar ?? this.familiar,
      );

  @override
  String toString() => 'GymPrefs(${toJson()})';
}
