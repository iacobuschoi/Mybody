/* =============================================================================
 * loads.dart — 오늘 들 무게 추천
 *
 * 헬스장에 처음 온 사람이 종목 이름을 봐도 "몇 kg 을 걸어야 하나" 를 모릅니다.
 * 2차 피드백 18: "체성분 보고 무게도 추천해 줘. 안 되면 몇 kg 씩 줄여 보세요
 * 같은 문구". 인바디 숫자(체중 · 골격근)와 프로필(성별 · 경력)에서 **시작
 * 무게**를 어림하고, 그 종목의 지난 기록이 있으면 그걸 우선합니다 — 몸이 이미
 * 답한 값이 계산보다 낫습니다.
 *
 * 계산 (전부 어림 — 시작점일 뿐이고, 화면이 "안 되면 줄여 보세요" 를 같이 말합니다):
 *   1RM ≈ 체중 × 움직임별 초보 비율(kRatioByPattern, 남/여)
 *          × 골격근 계수(내 골격근/체중 ÷ 기준 남 0.42 · 여 0.34, 0.8~1.2 로 클램프)
 *          × 경력 계수(novice 1.0 · intermediate 1.35 · advanced 1.7)
 *   무게  = 1RM × 반복 구간의 %1RM(5-8 → 78% · 8-12 → 70% · 10-15 → 62% · 15+ → 55%)
 *   덤벨은 한 손 무게(절반), 기구별 단위(kStepOf)로 반올림하고 빈 봉 20kg 아래로는
 *   안 내려갑니다.
 *
 * 근거:
 *   · 초보 비율은 체중 대비 1RM 표준(ExRx · Strength Level "beginner" 남/여)을
 *     보수적으로 낮춘 값입니다 — 첫날은 가볍게 시작해서 올리는 편이 안전합니다.
 *   · 골격근/체중 기준 0.42 · 0.34 는 인바디의 20~30대 평균 골격근률(남 40~44% ·
 *     여 32~36%)의 가운데입니다. 근육이 많으면 같은 체중이라도 더 듭니다.
 *   · 경력 계수는 Strength Level 의 beginner → intermediate(약 +35%) →
 *     advanced(약 +70%) 단계 차이입니다.
 *   · %1RM 은 Epley/Brzycki 반복-1RM 표(5회 87% · 8회 78% · 10회 72% · 12회 68% ·
 *     15회 62% · 20회 55%)에서 각 구간의 **윗쪽 반복수**에 맞춘 값입니다 — 구간
 *     끝까지 채울 수 있어야 하니까요.
 * ========================================================================== */
library;

import 'exercises.dart';

/// 추천 무게 하나.
class Load {
  const Load({required this.kg, required this.step, required this.source, required this.hint, this.prevKg});

  /// 오늘 걸 무게. null 은 맨몸(무게 없음).
  final double? kg;
  /// 지난 기록의 무게(source 'last' 일 때). kg 이 이보다 크면 "다 채워서 한 단위 위" 입니다.
  final double? prevKg;
  /// 올리고 내리는 단위 — 스테퍼와 반올림이 같이 씁니다. 맨몸이면 0.
  final double step;
  /// 'body'(체성분으로 계산) · 'last'(지난 기록) · 'none'(무게 없는 종목).
  final String source;
  /// 한 줄 안내 — '안 되면 2.5~5kg 씩 줄여 보세요' · '지난번 40kg · 다 채워서 +2.5kg'.
  final String hint;

  static const none = Load(kg: null, step: 0, source: 'none', hint: '');

  @override
  String toString() => 'Load($kg, step $step, $source, "$hint")';
}

/// 움직임별 초보 1RM ÷ 체중 — (남, 여). 레그프레스는 따로(kLegPressRatio).
/// 고립 종목은 0.15~0.4 — 팔 · 어깨(0.15~0.25)보다 다리 머신(레그 익스텐션 ·
/// 레그 컬 · 카프)이 같은 "고립" 이라도 훨씬 무겁습니다.
const Map<String, (double, double)> kRatioByPattern = {
  'squat': (1.0, 0.7),
  'hinge': (1.2, 0.8),
  'push-h': (0.75, 0.45),
  'push-v': (0.5, 0.3),
  'pull-h': (0.65, 0.4),
  'pull-v': (0.7, 0.45),
  'lunge': (0.5, 0.35),
  'isolation': (0.4, 0.28),
  'abduction': (0.4, 0.3),
  'adduction': (0.4, 0.3),
  'curl': (0.25, 0.15),
  'extension': (0.25, 0.15),
  'fly': (0.3, 0.2),
  'raise': (0.15, 0.1),
  'core': (0.25, 0.18),
  'rotation': (0.2, 0.15),
  'carry': (0.6, 0.4),
  'full': (0.4, 0.3),
};

/// 레그프레스 계열 — 썰매가 무게를 받쳐 주어 스쿼트보다 훨씬 무겁게 듭니다.
const (double, double) kLegPressRatio = (1.8, 1.2);

/// 골격근/체중 기준 (남, 여).
const (double, double) kSmmRatioBase = (0.42, 0.34);

/// 경력 계수.
const Map<String, double> kTrainingMult = {'novice': 1.0, 'intermediate': 1.35, 'advanced': 1.7};

/// 빈 봉. 바벨 종목은 이 아래로 추천하지 않습니다.
const double kEmptyBarKg = 20;

/// 반복 구간 → %1RM. 구간의 앞 숫자로 고릅니다('5-8' → 5 · '15+' → 15).
/// 숫자가 없으면('30초') 가벼운 쪽(0.55) — 시간으로 하는 종목은 오래 버텨야 합니다.
double pctOneRm(String reps) {
  final m = RegExp(r'\d+').firstMatch(reps);
  if (m == null) return 0.55;
  final lo = int.parse(m.group(0)!);
  if (lo <= 6) return 0.78;
  if (lo <= 9) return 0.70;
  if (lo <= 12) return 0.62;
  return 0.55;
}

/// 기구별 올리고 내리는 단위. 덤벨은 10kg 아래 1kg 씩, 그 위는 2kg 씩(헬스장
/// 덤벨이 그렇게 놓여 있습니다). 무게 없는 종목(맨몸 · 밴드)은 0.
double stepFor(String equip, double kg) => switch (equip) {
      'barbell' => 2.5,
      'cable' => 2.5,
      'machine' => 5,
      'dumbbell' => kg < 10 ? 1 : 2,
      'kettlebell' => 4,
      _ => 0,
    };

/// 힌트의 "몇 kg 씩" — 단위의 1~2배.
String _stepRange(String equip) => switch (equip) {
      'barbell' || 'cable' => '2.5~5',
      'machine' => '5',
      'dumbbell' => '1~2',
      'kettlebell' => '4',
      _ => '',
    };

/// 단위로 반올림. 바벨은 빈 봉(20) · 나머지는 한 단위 아래로 안 내려갑니다.
double roundLoad(String equip, double raw) {
  final step = stepFor(equip, raw);
  if (step <= 0) return raw;
  var kg = (raw / step).round() * step;
  final floor = equip == 'barbell' ? kEmptyBarKg : step;
  if (kg < floor) kg = floor;
  return kg;
}

/// '37.5' · '40' — 소수점은 필요할 때만.
String kgText(double kg) => kg == kg.roundToDouble() ? '${kg.toInt()}' : kg.toStringAsFixed(1);

/// 무게가 없는 기구인가 — 맨몸 · 밴드(그리고 모르는 것).
bool _weightless(String equip) => stepFor(equip, 1) <= 0;

/// 어시스트 풀업 · 딥 머신인가. 스택의 kg 은 **보조** 무게라 클수록 쉽습니다 —
/// 체중 비율로 계산한 "들 무게" 도, 다 채우면 +5kg 하는 진행 규칙도 거꾸로
/// 갑니다. 무게 없는 종목으로 둡니다(스테퍼로 스택 무게를 적는 건 됩니다).
bool _assisted(Exercise? e) => e != null && e.id.startsWith('assisted-');

/// 오늘 들 무게.
///
/// [last] 는 지난 기록의 그 종목 `{kg, sets, of, reps?}` (lastLoadsFrom 이 만듭니다).
/// 지난 kg 이 있으면 그것이 답이고, 지난번에 세트를 다 채웠으면 한 단위 올립니다.
/// 없으면 체성분으로 계산합니다. [exercise] 를 안 주면 이름으로 사전에서 찾고,
/// 사전에 없으면 맨몸으로 봅니다(무게 없음).
Load recommendLoad({
  required String name,
  Exercise? exercise,
  required String reps,
  required Map<String, Object?> profile,
  double? weightKg,
  double? smmKg,
  Map<String, Object?>? last,
}) {
  final e = exercise ?? exerciseByName(name);
  final equip = e?.equip ?? 'bodyweight';
  if (_weightless(equip) || _assisted(e)) return Load.none;

  /* 지난 기록이 먼저 — 몸이 이미 답한 값입니다. */
  final lastKg = last?['kg'];
  if (lastKg is num && lastKg > 0) {
    final prev = lastKg.toDouble();
    final step = stepFor(equip, prev);
    final of = last?['of'], sets = last?['sets'];
    final filled = of is num && of > 0 && sets is num && sets >= of;
    return Load(
      kg: filled ? prev + step : prev,
      prevKg: prev,
      step: step,
      source: 'last',
      hint: filled ? '지난번 ${kgText(prev)}kg · 다 채워서 +${kgText(step)}kg' : '지난번 그대로',
    );
  }

  if (weightKg == null || !weightKg.isFinite || weightKg <= 0) return Load.none;

  final female = profile['sex'] == 'female';
  final pattern = e?.pattern ?? '';
  /* 레그프레스 계열은 스쿼트 움직임일 때만 — '레그프레스 카프 레이즈' 는 종아리
     고립이라 1.8배가 아니라 isolation 비율입니다. */
  final isLegPress = e != null && e.equip == 'machine' && e.pattern == 'squat' && e.id.contains('leg-press');
  final ratioPair = isLegPress ? kLegPressRatio : kRatioByPattern[pattern];
  if (ratioPair == null) return Load.none;   // hold 같은 무게 없는 움직임
  final ratio = female ? ratioPair.$2 : ratioPair.$1;

  var smmFactor = 1.0;
  if (smmKg != null && smmKg.isFinite && smmKg > 0) {
    final base = female ? kSmmRatioBase.$2 : kSmmRatioBase.$1;
    smmFactor = ((smmKg / weightKg) / base).clamp(0.8, 1.2);
  }
  final train = kTrainingMult['${profile['trainingAge']}'] ?? 1.0;

  var raw = weightKg * ratio * smmFactor * train * pctOneRm(reps);
  if (equip == 'dumbbell') raw /= 2;   // 한 손 무게
  final kg = roundLoad(equip, raw);
  return Load(
    kg: kg,
    step: stepFor(equip, kg),
    source: 'body',
    hint: '안 되면 ${_stepRange(equip)}kg 씩 줄여 보세요',
  );
}

/// 최근 [days]일의 헬스 기록에서 종목 이름 → 마지막 기록 `{kg, sets, of, reps, date}`.
/// [dateKey] 그 날은 빼고 전날부터 거슬러 봅니다. [schedule] 은 state['schedule'].
Map<String, Map<String, Object?>> lastLoadsFrom(Map<String, Object?> schedule, String dateKey,
    {int days = 30}) {
  final out = <String, Map<String, Object?>>{};
  final start = DateTime.tryParse('${dateKey}T00:00:00');
  if (start == null) return out;
  for (var i = 1; i <= days; i++) {
    /* 달력 산수로 — Duration 으로 빼면 서머타임 날(23시간) 다음에 하루가 건너뜁니다. */
    final d = DateTime(start.year, start.month, start.day - i);
    final k = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final day = schedule[k];
    final log = day is Map ? day['log'] : null;
    final gym = log is Map ? log['gym'] : null;
    if (gym is! Map || gym['kind'] != 'gym') continue;
    final xs = gym['exercises'];
    if (xs is! List) continue;
    for (final x in xs) {
      if (x is! Map) continue;
      final name = '${x['name'] ?? ''}';
      if (name.isEmpty || out.containsKey(name)) continue;
      out[name] = {
        'kg': x['kg'] is num ? x['kg'] : null,
        'sets': x['sets'],
        'of': x['of'],
        'reps': x['reps'],
        'date': k,
      };
    }
  }
  return out;
}
