/* =============================================================================
 * bodyweight.dart — 자기 전 15분 맨몸 운동
 *
 * 헬스장에 못 간 날에도 몸을 한 번 쓰게 하는 짧은 루틴입니다. 기구 없이,
 * 방 안에서, 15분. 사람마다 다르게 짭니다:
 *
 *   · 경력(trainingAge)으로 세트·반복을 — 초보 3×10, 중급 3×14, 상급 4×15.
 *   · 체중 95kg 초과 또는 체지방률 30% 초과면 점프·버피를 뺍니다. 무릎에
 *     체중의 몇 배가 실리는 동작이라, 그 사람에게는 운동이 아니라 부상입니다.
 *   · 오늘 분할(하체·상체·등)을 따라갑니다 — 헬스장 계획과 같은 결을 타야
 *     "오늘은 하체" 가 하나의 말로 남습니다. 계획이 없으면 전신.
 *   · 마지막은 늘 코어 하나.
 *
 * 시간은 세트 × (동작 + 휴식) 으로 셉니다. 동작은 반복당 3초, 버티기는 초로.
 * 휴식을 15~60초 사이에서 맞춰 전체가 요청한 분에 맞게 합니다.
 * ========================================================================== */
library;

import 'exercises.dart';
import 'kcal.dart';

/// 반복당 대략 걸리는 시간. 내렸다 올리는 한 번입니다.
const int _secPerRep = 3;

class _Level {
  const _Level(this.key, this.label, this.sets, this.reps, this.holdSec, this.restSec);
  final String key;
  final String label;
  final int sets;
  final int reps;
  final int holdSec;
  final int restSec;
}

const _novice = _Level('novice', '초보', 3, 10, 30, 30);
const _intermediate = _Level('intermediate', '중급', 3, 14, 40, 25);
const _advanced = _Level('advanced', '상급', 4, 15, 50, 20);

_Level _levelOf(Map<String, Object?> profile) {
  switch ('${profile['trainingAge']}') {
    case 'advanced':
      return _advanced;
    case 'intermediate':
      return _intermediate;
    default:
      return _novice;
  }
}

final RegExp _reLower = RegExp('하체|레그');
final RegExp _reUpper = RegExp('상체|푸시|가슴');
final RegExp _rePull = RegExp('풀|등');

/// 오늘 분할 이름 → 초점. 엔진의 라벨 규칙과 같은 순서로 봅니다.
String focusOf(String todayLabel) {
  if (_reLower.hasMatch(todayLabel)) return 'lower';
  if (_reUpper.hasMatch(todayLabel)) return 'upper';
  if (_rePull.hasMatch(todayLabel)) return 'pull';
  return 'full';
}

const Map<String, String> _focusLabel = {
  'lower': '하체', 'upper': '상체', 'pull': '등', 'full': '전신',
};

/// 초점별 종목 목록 (사전의 id). 앞에서부터 시간이 허락하는 만큼 씁니다.
/// normal 은 보통, hard 는 상급의 어려운 변형, low 는 점프 없는 판입니다.
const Map<String, Map<String, List<String>>> _moves = {
  'lower': {
    'normal': ['bodyweight-squat', 'lunge', 'glute-bridge', 'wall-sit', 'calf-raise', 'split-squat'],
    'hard': ['jump-squat', 'lunge', 'single-leg-glute-bridge', 'split-squat', 'wall-sit', 'calf-raise'],
    'low': ['bodyweight-squat', 'glute-bridge', 'step-up', 'wall-sit', 'calf-raise', 'split-squat'],
  },
  'upper': {
    'normal': ['push-up', 'pike-push-up', 'bench-dips', 'superman', 'plank-shoulder-tap', 'diamond-push-up'],
    'hard': ['decline-push-up', 'pike-push-up', 'diamond-push-up', 'bench-dips', 'superman', 'plank-shoulder-tap'],
    'low': ['incline-push-up', 'bench-dips', 'superman', 'plank-shoulder-tap', 'reverse-snow-angel', 'prone-y-raise'],
  },
  'pull': {
    'normal': ['superman', 'inverted-row', 'prone-y-raise', 'reverse-snow-angel', 'glute-bridge', 'bird-dog'],
    'hard': ['inverted-row', 'superman', 'prone-y-raise', 'reverse-snow-angel', 'single-leg-glute-bridge', 'bird-dog'],
    'low': ['superman', 'inverted-row', 'prone-y-raise', 'reverse-snow-angel', 'glute-bridge', 'bird-dog'],
  },
  'full': {
    'normal': ['bodyweight-squat', 'push-up', 'lunge', 'glute-bridge', 'mountain-climber', 'superman'],
    'hard': ['jump-squat', 'push-up', 'burpee', 'lunge', 'mountain-climber', 'single-leg-glute-bridge'],
    'low': ['bodyweight-squat', 'incline-push-up', 'step-up', 'glute-bridge', 'wall-sit', 'superman'],
  },
};

/// 마무리 코어. 초점마다 다르게 — 하체 날에 또 다리를 드는 건 피합니다.
const Map<String, String> _finisher = {
  'lower': 'lying-leg-raise', 'upper': 'plank', 'pull': 'dead-bug', 'full': 'plank',
};

/// 자기 전 15분 맨몸 운동 — 몸 상태(체중·체지방률·경력)와 오늘 분할에 맞춤.
///
/// → {title, focus ('lower'|'upper'|'pull'|'full'), minutes, plannedSec, kcal,
///    exercises: [{id, name, sets, reps 또는 seconds, restSec, note}], why}
Map<String, Object?> bodyweightRoutine({
  required Map<String, Object?> profile,
  required double weightKg,
  double? pbfPct,
  String todayLabel = '',
  int minutes = 15,
}) {
  final level = _levelOf(profile);
  final focus = focusOf(todayLabel);
  final budgetMin = minutes.clamp(5, 60);
  final budget = budgetMin * 60;

  final heavy = weightKg.isFinite && weightKg > 95;
  final fat = pbfPct != null && pbfPct.isFinite && pbfPct > 30;
  final lowImpact = heavy || fat;

  final variant = lowImpact ? 'low' : (level.key == 'advanced' ? 'hard' : 'normal');
  final pool = <Exercise>[
    for (final id in _moves[focus]![variant]!) exerciseById(id)!,
  ];
  final core = exerciseById(_finisher[focus]!)!;

  /* 몇 종목을 넣을지 — 전체 시간이 요청한 분에 가장 가까워지는 개수.
     휴식은 15~60초 사이에서 남는 시간에 맞춥니다. */
  int workOf(Exercise e) => e.pattern == 'hold' ? level.holdSec : level.reps * _secPerRep;
  final coreWork = workOf(core);
  var bestN = 1;
  var bestRest = level.restSec;
  int? bestGap;
  for (var n = 1; n <= pool.length; n++) {
    var work = coreWork;
    for (var i = 0; i < n; i++) {
      work += workOf(pool[i]);
    }
    final slots = level.sets * (n + 1);
    final rest = ((budget - level.sets * work) / slots).round().clamp(15, 60);
    final total = level.sets * work + slots * rest;
    final gap = (total - budget).abs();
    if (bestGap == null || gap < bestGap ||
        (gap == bestGap && (rest - level.restSec).abs() < (bestRest - level.restSec).abs())) {
      bestGap = gap;
      bestN = n;
      bestRest = rest;
    }
  }

  final chosen = [...pool.take(bestN), core];
  var plannedSec = 0;
  final exercises = <Map<String, Object?>>[];
  for (final e in chosen) {
    final hold = e.pattern == 'hold';
    final work = workOf(e);
    plannedSec += level.sets * (work + bestRest);
    exercises.add({
      'id': e.id,
      'name': e.name,
      'sets': level.sets,
      if (hold) 'seconds': level.holdSec else 'reps': level.reps,
      'restSec': bestRest,
      'note': e.note ?? '',
    });
  }

  final why = <String>[];
  if (todayLabel.trim().isEmpty) {
    why.add('오늘 계획한 분할이 없어 전신으로 짰습니다');
  } else if (todayLabel.contains('휴식')) {
    why.add('오늘은 쉬는 날이라 가볍게 전신으로 짰습니다');
  } else if (focus == 'full') {
    why.add('오늘 분할($todayLabel)에 맞춰 전신으로 짰습니다');
  } else {
    why.add('오늘 분할($todayLabel)에 맞춰 ${_focusLabel[focus]} 위주입니다');
  }
  if (lowImpact) {
    final reasons = <String>[
      if (heavy) '체중 95kg 초과',
      if (fat) '체지방률 30% 초과',
    ];
    why.add('무릎 부담을 줄이려고 점프 동작은 뺐습니다 (${reasons.join(' · ')})');
  }
  why.add('${level.label} 기준 ${level.sets}세트 × ${level.reps}회'
      '${variant == 'hard' ? ' · 어려운 변형' : ''}');

  return {
    'title': '${_focusLabel[focus]} $budgetMin분 맨몸',
    'focus': focus,
    'focusLabel': _focusLabel[focus],
    'level': level.key,
    'lowImpact': lowImpact,
    'minutes': budgetMin,
    'plannedSec': plannedSec,
    'kcal': workoutKcal(
        weightKg: weightKg, duration: Duration(seconds: plannedSec), kind: 'bodyweight'),
    'exercises': exercises,
    'why': why.join(' · '),
  };
}
