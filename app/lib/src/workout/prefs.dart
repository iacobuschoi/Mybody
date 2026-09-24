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

import 'exercises.dart';

/// 헬스장이면 기본으로 다 있다고 봅니다 — 없는 것을 빼는 쪽이 빠릅니다.
const Set<String> kGymEquipment = {'barbell', 'dumbbell', 'machine', 'cable', 'bodyweight'};

/// 집은 반대로, 흔히 있는 것만.
const Set<String> kHomeEquipment = {'bodyweight', 'dumbbell', 'band'};

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

  bool get isHome => place == 'home';

  /// 그 자리의 기본 기구.
  static Set<String> defaultEquipment(String place) =>
      place == 'home' ? {...kHomeEquipment} : {...kGymEquipment};

  /// settings['gym'] 에서 읽습니다. 없거나 깨져 있으면 헬스장 기본값 —
  /// 설정을 한 번도 안 만진 사람이 대부분이고, 그 사람의 계획은 엔진 그대로여야 합니다.
  static GymPrefs fromSettings(Map<String, Object?>? settings) {
    final raw = settings?['gym'];
    if (raw is! Map) return const GymPrefs();
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
    if (mc is num && mc.isFinite && mc >= 0) machineCount = mc.toInt();

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
