/* =============================================================================
 * engine.dart — 계획 엔진 (prototype/js/engine.js 의 이식)
 *
 * **원본과 같은 답을 내야 합니다.** 이 엔진이 목표일과 주간 궤적을
 * 만들고, 화면은 그걸 그대로 보여 줍니다. 여기가 갈리면 두 앱이 같은
 * 사람에게 다른 목표일을 말합니다.
 *
 * tools/difftest.js 가 수천 개의 입력을 양쪽에 넣어 답을 비교합니다.
 * 규칙의 **이유**(왜 k 가 0.35~0.65 인지, 왜 골격근만 따로 보는지)는
 * 원본 주석에 있습니다. 여기서는 **옮기면서 달라질 뻔한 곳**만 적습니다.
 *
 * 자바스크립트라서 조심해야 하는 것들:
 *   · `undefined` 로 산수하면 NaN 이 됩니다. Dart 는 null 이면 던집니다.
 *     그래서 없는 값은 double.nan 으로 받아 같은 길을 가게 합니다.
 *   · `scan.bmrKcal || bmrKatch` 에서 **0 은 거짓**입니다. 0 이 들어오면
 *     인쇄값이 아니라 계산값을 씁니다. `?? ` 로 옮기면 0 을 살려서
 *     BMR 0 짜리 계획이 나옵니다.
 *   · `x > 0` 에서 x 가 null/undefined 면 false 입니다. Dart 에서는
 *     null 비교가 오류라 따로 감쌉니다.
 *   · Math.round 의 음수 처리가 다릅니다 → js_num.dart 의 jsRound.
 * ========================================================================== */
library;

import 'dart:math' as math;
import 'data.dart';
import 'js_date.dart';
import 'js_num.dart';

const double kcalPerKgFat = 7700;
const int maxWeeks = 208;

class Pal {
  final double mult;
  final String label;
  const Pal(this.mult, this.label);
}

const Map<String, Pal> kPal = {
  'sedentary': Pal(1.20, '좌식 (거의 앉아서 생활)'),
  'light': Pal(1.375, '가벼움 (주 1~3회 운동)'),
  'moderate': Pal(1.55, '보통 (주 3~5회 운동)'),
  'active': Pal(1.725, '활동적 (주 6~7회 운동)'),
  'veryActive': Pal(1.90, '매우 활동적 (육체노동/2회 운동)'),
};

/* --- 자바스크립트 흉내 ------------------------------------------------------ */

/// 값 하나를 JS 처럼 숫자로. (키 유무를 아는 자리에서는 jsNum 을 쓰세요 —
/// `null` 은 0 이고 `undefined` 는 NaN 이라 둘을 갈라야 합니다.)
double _n(Object? x) => jsToNumber(x);

/// 맵에서 JS 처럼 읽습니다: 키가 없으면 NaN, 값이 null 이면 0.
double _f(Map<String, Object?> m, String k) => jsNum(m, k);

/// JS 의 `x != null` (undefined 와 null 둘 다 거짓). 숫자가 아닌 것도 값으로는 셉니다.
bool _has(Object? x) => x != null;

/// JS 의 느슨한 비교 `a > b` — 한쪽이 없으면 false.
bool _gt(Object? a, num b) => a is num && a > b;
bool _gte(Object? a, num b) => a is num && a >= b;

/* --- 1. 파생값 -------------------------------------------------------------- */

/// 물리적으로 불가능한 스캔을 걸러냅니다.
/// null 이면 정상, 아니면 {invalid: [...], reasons: [...]}.
Map<String, Object?>? validateScan(
    Map<String, Object?>? scan, Map<String, Object?>? prevScan) {
  if (scan == null) {
    return {'invalid': ['스캔'], 'reasons': ['측정 기록이 없습니다.']};
  }
  final bad = <String>[];
  final why = <String>[];
  final wRaw = scan['weightKg'];
  final w = _n(wRaw);
  // b = bfmKg ?? (weightKg 과 pbfPct 가 둘 다 있을 때 계산)
  final Object? bRaw = _has(scan['bfmKg'])
      ? scan['bfmKg']
      : (_has(wRaw) && _has(scan['pbfPct'])
          ? w * _n(scan['pbfPct']) / 100
          : null);
  final smmRaw = scan['smmKg'];

  if (!(_gte(wRaw, 25) && wRaw is num && wRaw <= 300)) {
    bad.add('체중');
    why.add('체중이 25~300kg 범위를 벗어났습니다.');
  }
  if (bRaw == null || !_gte(bRaw, 0)) {
    bad.add('체지방량');
    why.add('체지방량을 읽지 못했습니다.');
  } else if (_gte(wRaw, 25) && _n(bRaw) > 0.65 * w) {
    bad.add('체지방량');
    why.add('체지방량이 체중의 65%를 넘습니다. 체중과 체지방 칸이 바뀌지 않았는지 확인해 주세요.');
  }

  final Object? ffmRaw = (_has(wRaw) && bRaw != null) ? w - _n(bRaw) : null;
  if (ffmRaw != null && !_gt(ffmRaw, 0)) {
    bad.add('제지방량');
    why.add('체지방량이 체중보다 큽니다.');
  }

  if (smmRaw == null || !_gte(smmRaw, 0)) {
    bad.add('골격근량');
    why.add('골격근량을 읽지 못했습니다.');
  } else if (ffmRaw != null && _gt(ffmRaw, 0)) {
    final k = _n(smmRaw) / _n(ffmRaw);
    if (k < 0.35 || k > 0.65) {
      bad.add('골격근량');
      why.add('골격근량이 제지방량의 ${jsRound(k * 100).toInt()}% 입니다. 보통 40~60% 입니다 — '
          '근육과 지방 칸이 바뀌지 않았는지 확인해 주세요.');
    }
  }

  /* 골격근량은 결과지 안에 짝이 없어서, 이전 측정의 k 로 대조합니다.
     이유는 원본 주석에 길게 있습니다. */
  if (prevScan != null && _gt(wRaw, 0) && bRaw != null && _gt(smmRaw, 0)) {
    final pwRaw = prevScan['weightKg'];
    final pw = _n(pwRaw);
    final Object? pbRaw = _has(prevScan['bfmKg'])
        ? prevScan['bfmKg']
        : (_has(pwRaw) && _has(prevScan['pbfPct'])
            ? pw * _n(prevScan['pbfPct']) / 100
            : null);
    final Object? pffmRaw = _has(prevScan['ffmKg'])
        ? prevScan['ffmKg']
        : (_has(pwRaw) && pbRaw != null ? pw - _n(pbRaw) : null);
    final ffmNow = w - _n(bRaw);
    if (_gt(pffmRaw, 0) && _gt(prevScan['smmKg'], 0) && ffmNow > 0) {
      final kPrev = _n(prevScan['smmKg']) / _n(pffmRaw);
      final expect = kPrev * ffmNow;
      final gapDays = _absDiffDays(scan['measuredAt'], prevScan['measuredAt']);
      if (gapDays != null && gapDays.isFinite) {
        final tol = math.min(3.0, 1.2 + (gapDays / 30) * 0.25);
        if ((_n(smmRaw) - expect).abs() > tol) {
          bad.add('골격근량');
          why.add('이전 측정으로 보면 골격근량이 ${jsNumToString(jsRound(expect * 10) / 10)}'
              'kg 근처여야 하는데 ${jsNumToString(smmRaw as num)}kg 입니다. '
              '자릿수나 자리를 잘못 읽지 않았는지 확인해 주세요.');
        }
      }
    }
  }

  if (bad.isEmpty) return null;
  final seen = <String>{};
  final uniq = <String>[];
  for (final x in bad) {
    if (seen.add(x)) uniq.add(x);
  }
  return {'invalid': uniq, 'reasons': why};
}

Map<String, Object?> derive(Map<String, Object?> scan, Map<String, Object?> profile) {
  final w = _f(scan, 'weightKg');
  final bfm = _has(scan['bfmKg']) ? _f(scan, 'bfmKg') : w * (_f(scan, 'pbfPct') / 100);
  final ffm = _has(scan['ffmKg']) ? _f(scan, 'ffmKg') : w - bfm;
  final smm = _f(scan, 'smmKg');
  final h = _f(profile, 'heightCm') / 100;

  final bmrKatch = 370 + 21.6 * ffm;
  final bmrMifflin = profile['sex'] == 'male'
      ? (10 * w + 6.25 * _f(profile, 'heightCm') - 5 * _f(profile, 'age') + 5)
      : (10 * w + 6.25 * _f(profile, 'heightCm') - 5 * _f(profile, 'age') - 161);
  /* **`scan.bmrKcal || bmrKatch`** 를 글자 그대로 옮깁니다.
     0 은 거짓이라 계산값으로 떨어지고, **문자열 "abc" 는 참**이라 그게
     그대로 쓰여서 뒤의 산수가 NaN 이 됩니다. "숫자가 아니면 계산값" 으로
     읽으면 더 올바르게 도는데, 그건 **다른 동작**입니다 — 두 앱이 같은
     결과지에서 다른 BMR 을 말하게 됩니다. */
  final printed = scan['bmrKcal'];
  final bool printedTruthy = jsTruthy(printed);
  final bmr = printedTruthy ? _n(printed) : bmrKatch;
  final pal = (kPal[profile['activityLevel']] ?? kPal['moderate']!).mult;

  return {
    'weightKg': r1(w),
    'smmKg': r1(smm),
    'bfmKg': r1(bfm),
    'ffmKg': r1(ffm),
    'pbfPct': r1(bfm / w * 100),
    'bmi': r1(w / (h * h)),
    'smmToFfm': smm / ffm,
    'bmrKcal': jsRound(bmr),
    'bmrKatch': jsRound(bmrKatch),
    'bmrMifflin': jsRound(bmrMifflin),
    'bmrSource': printedTruthy ? 'InBody 인쇄값' : 'Katch-McArdle 계산값',
    'pal': pal,
    'tdeeKcal': jsRound(bmr * pal),
  };
}

/// JS: Math.abs(Date.parse(a) - Date.parse(b)) / 86400000. 못 읽으면 null(=NaN).
double? _absDiffDays(Object? a, Object? b) {
  final ta = _parseDate(a), tb = _parseDate(b);
  if (ta == null || tb == null) return null;
  return ((ta - tb) / 86400000).abs();
}

int? _parseDate(Object? x) {
  if (x is! String) return null;
  return DateTime.tryParse(x)?.millisecondsSinceEpoch;
}

/* --- 2. 목표 분류 ----------------------------------------------------------- */

/* 측정 노이즈 바닥. 원본은 `global.MB_MODES ? global.MB_MODES.NOISE : {…}` 입니다.
 *
 * **맵 통째로** 들고 있어야 합니다. classifyGoal 은 이 객체를 `noise:` 칸에
 * 그대로 실어 내보내는데, modes.js 의 NOISE 에는 세 숫자 말고 근거를 적은
 * 긴 `rationale` 문자열도 들어 있습니다. 숫자 세 개만 들고 있으면 계산은
 * 맞는데 내보내는 값이 달라집니다 — 차이 검사가 바로 이걸 잡았습니다.
 * 화면이 그 근거를 읽는 날이 오면 옮긴 앱에서는 비어 있게 됩니다. */
const Map<String, Object?> kNoiseFallback = {'weight': 1.0, 'smm': 0.6, 'bfm': 1.0};

Map<String, Object?> _noise = kNoiseFallback;

/// modes 쪽에서 실제 NOISE 를 넣어 줍니다. 안 넣으면 원본의 대체값과 같습니다.
set engineNoise(Map<String, Object?> n) => _noise = n;
Map<String, Object?> get engineNoise => _noise;

Map<String, Object?> classifyGoal(Map<String, Object?> cur, Map<String, Object?> goal) {
  final dW = _f(goal, 'weightKg') - _f(cur, 'weightKg');
  final dSMM = _f(goal, 'smmKg') - _f(cur, 'smmKg');
  final dBFM = _f(goal, 'bfmKg') - _f(cur, 'bfmKg');

  final impliedFfm = _f(goal, 'smmKg') / _f(cur, 'smmToFfm');
  final impliedWeight = impliedFfm + _f(goal, 'bfmKg');
  final mismatchKg = _f(goal, 'weightKg') - impliedWeight;

  final nf = _noise;
  final nBfm = _f(nf, 'bfm'), nSmm = _f(nf, 'smm'), nWeight = _f(nf, 'weight');
  final wantsFatLoss = dBFM < -nBfm;
  final wantsFatGain = dBFM > nBfm;
  final wantsMuscle = dSMM > nSmm;
  final losesMuscle = dSMM < -nSmm;

  String type, typeLabel;
  if (wantsFatLoss && wantsMuscle) {
    type = 'recomp';
    typeLabel = '리컴프 (지방↓ + 근육↑ 동시)';
  } else if (wantsFatLoss) {
    type = 'cut';
    typeLabel = '감량';
  } else if (wantsMuscle && !wantsFatLoss) {
    type = 'bulk';
    typeLabel = '증량';
  } else if (wantsFatGain && losesMuscle) {
    type = 'contrary';
    typeLabel = '방향이 반대인 목표';
  } else {
    type = 'maintain';
    typeLabel = '유지';
  }

  return {
    'type': type,
    'typeLabel': typeLabel,
    'dWeightKg': r1(dW),
    'dSmmKg': r1(dSMM),
    'dBfmKg': r1(dBFM),
    'targetPbfPct': r1(_f(goal, 'bfmKg') / _f(goal, 'weightKg') * 100),
    'impliedWeightKg': r1(impliedWeight),
    'mismatchKg': r1(mismatchKg),
    'isConsistent': mismatchKg.abs() <= 1.0,
    'noise': nf,
    'subNoise': {
      'weight': dW.abs() < nWeight,
      'smm': dSMM.abs() < nSmm,
      'bfm': dBFM.abs() < nBfm,
    },
  };
}

/* --- 3. 속도 모델 ----------------------------------------------------------- */

class _Muscle {
  final double pct;
  final String label;
  const _Muscle(this.pct, this.label);
}

const Map<String, _Muscle> kMuscleBase = {
  'novice': _Muscle(1.44, '입문 (6개월 미만)'),
  'intermediate': _Muscle(0.86, '중급 (6개월~3년)'),
  'advanced': _Muscle(0.43, '숙련 (3년 이상)'),
  'elite': _Muscle(0.20, '상급 정체기 (5년+)'),
};

const Map<String, Map<String, double>> kMuscleSituation = {
  'surplus': {'novice': 1.00, 'intermediate': 1.00, 'advanced': 1.00, 'elite': 1.00},
  'maintain': {'novice': 0.50, 'intermediate': 0.50, 'advanced': 0.50, 'elite': 0.50},
  'recomp': {'novice': 0.70, 'intermediate': 0.35, 'advanced': 0.15, 'elite': 0.10},
  'cut': {'novice': 0.30, 'intermediate': 0.05, 'advanced': 0.00, 'elite': 0.00},
};

double ffmiOf(double ffmKg, Object? heightCm) {
  /* `heightCm || 175` — 0 도 거짓이라 175 로 떨어집니다. */
  final h = (jsTruthy(heightCm) ? jsToNumber(heightCm) : 175) / 100;
  return ffmKg / (h * h);
}

double ffmiCeiling(Object? sex) => sex == 'female' ? 22.0 : 25.0;

double ffmiFactor(double ffmKg, Map<String, Object?> profile) {
  final ceil = ffmiCeiling(profile['sex']);
  final cur = ffmiOf(ffmKg, profile['heightCm']);
  final taper = ceil - 2.0;
  if (cur <= taper) return 1;
  if (cur >= ceil) return 0;
  return (ceil - cur) / (ceil - taper);
}

/// 나이 계수. **없는 나이와 null 인 나이는 다릅니다.**
///
/// JS 에서 `undefined < 18` 은 NaN 비교라 거짓이고, 세 조건이 전부 빠지면
/// 1.00 으로 떨어집니다. 그런데 `null < 18` 은 `0 < 18` 이라 **참**이고
/// 0.90 이 나옵니다. 처음 옮길 때 둘을 합쳐 놓아서, 나이를 안 적은 사람의
/// 근성장 속도가 전부 10% 깎였습니다 — 차이 검사가 400건 중 5건에서 정확히
/// 0.9 배로 갈리는 것을 잡았습니다.
///
/// 그래서 호출하는 쪽에서 `jsNum(profile, 'age')` 로 넘깁니다. 키가 없으면
/// NaN, 값이 null 이면 0 입니다.
double ageFactor(Object? age) {
  final a = jsToNumber(age);
  if (a >= 50) return 0.65;
  if (a >= 40) return 0.80;
  if (a < 18) return 0.90;     // NaN 이면 여기도 거짓 → 1.00
  return 1.00;
}

double baseSmmRatePerWeek(double weightKg, Map<String, Object?> profile,
    double smmToFfm, double? ffmKg, [Object? weekIndex]) {
  final base = (kMuscleBase[profile['trainingAge']] ?? kMuscleBase['intermediate']!).pct;
  final sexFactor = profile['sex'] == 'male' ? 1.0 : 0.5;
  final anchor = ffmKg ?? weightKg * 0.80;
  final ffmPerMonth = anchor * (base / 100) * sexFactor;
  final smmPerMonth = ffmPerMonth * smmToFfm;
  var rate = smmPerMonth / 4.345 * ageFactor(_f(profile, 'age'));

  /* **null 과 undefined 를 구분합니다.**
       null      = "보고되지 않음" → 게이트 1.0 (건드리지 않음)
       undefined = 필드가 아예 없음 → 프로필의 운동일수를 씀
     Dart Map 에서는 둘 다 null 로 보이므로 containsKey 로 가릅니다. */
  Object? rt;
  if (profile.containsKey('resistanceDaysPerWeek')) {
    rt = profile['resistanceDaysPerWeek'];
  } else {
    rt = profile['daysPerWeek'];
  }
  if (rt != null && jsToNumber(rt).isFinite) {
    rate *= math.max(0, math.min(1, jsToNumber(rt) / 4));
  }

  if (weekIndex != null && jsToNumber(weekIndex) > 0) {
    const ladder = ['novice', 'intermediate', 'advanced', 'elite'];
    final at = ladder.indexOf('${profile['trainingAge']}');
    if (at >= 0) {
      final steps = (jsToNumber(weekIndex) / 26).floor();
      final eff = ladder[math.min(ladder.length - 1, at + steps)];
      final effPct = kMuscleBase[eff]!.pct;
      if (effPct < base) rate *= effPct / base;
    }
  }

  if (jsTruthy(profile['hadPriorPeak'])) rate *= 2.5;
  if (ffmKg != null) rate *= ffmiFactor(ffmKg, profile);
  return rate;
}

String muscleSituation(double deficitRatio) {
  if (deficitRatio < -0.02) return 'surplus';
  if (deficitRatio.abs() <= 0.05) return 'maintain';
  if (deficitRatio <= 0.15) return 'recomp';
  return 'cut';
}

double leanLossPerWeek(double deficitRatio, Object? proteinPerFFM, double pbfPct,
    Object? sex, double ffm) {
  final lean = pbfPct < (sex == 'male' ? 10 : 18);
  final deep = deficitRatio > 0.20;
  final lowP = proteinPerFFM != null && jsToNumber(proteinPerFFM) < 2.0;
  if (!deep && !lowP && !lean) return 0;
  var frac = 0.0;
  if (deep) frac += math.min(0.0010, (deficitRatio - 0.20) * 0.01);
  if (lowP) frac += 0.0005;
  if (lean) frac += 0.0005;
  return math.min(0.0015, frac) * ffm;
}

double kcalFloor(Map<String, Object?> profile, double bmr) {
  return math.max(jsRound(bmr * 1.1), profile['sex'] == 'male' ? 1500 : 1200).toDouble();
}

/* --- 4. 주차별 시뮬레이션 --------------------------------------------------- */

/// 한 주를 전진시킵니다. phase: 'cut' | 'bulk' | 'maintain'
Map<String, Object?> stepWeek(Map<String, Object?> st, String phase,
    Map<String, Object?> params, Map<String, Object?> profile, double k,
    [Object? weekIndex]) {
  final stSmm = _f(st, 'smmKg');
  final stBfm = _f(st, 'bfmKg');
  final ffm = stSmm / k;
  final w = ffm + stBfm;
  final bmr = 370 + 21.6 * ffm;
  final pal = (kPal[profile['activityLevel']] ?? kPal['moderate']!).mult;
  final tdee = bmr * pal;

  double intake = double.nan, deficit = 0, fatDelta = 0, smmDelta = 0;
  bool capped = false, floored = false, hitFatFloor = false;

  if (phase == 'cut') {
    final want = _f(params, 'deficitPct') * tdee;
    final cap = 31 * stBfm;
    deficit = math.min(want, cap);
    if (deficit < want - 1) capped = true;
    intake = tdee - deficit;
    final floor = kcalFloor(profile, bmr);
    if (intake < floor) {
      intake = floor;
      deficit = tdee - intake;
      floored = true;
    }
    final fatFromKcal = deficit * 7 / kcalPerKgFat;
    final fatFromRate = _f(params, 'ratePct') * w;
    fatDelta = -math.min(fatFromKcal, fatFromRate);
  } else if (phase == 'bulk') {
    final surplus = _f(params, 'surplusPct') * tdee;
    intake = tdee + surplus;
    deficit = -surplus;
    smmDelta = baseSmmRatePerWeek(w, profile, k, ffm);
    final ffmGain = smmDelta / k;
    final totalGain = ffmGain / _f(params, 'leanFraction');
    fatDelta = math.max(0, totalGain - ffmGain);
  } else {
    intake = tdee;
    deficit = 0;
  }

  double leanLoss = 0;
  if (phase != 'bulk') {
    final deficitRatio = deficit / tdee;
    final situation = muscleSituation(deficitRatio);
    final table = kMuscleSituation[situation]!;
    final mult = table['${profile['trainingAge']}'] ?? table['intermediate']!;
    smmDelta = baseSmmRatePerWeek(w, profile, k, ffm, weekIndex) * mult;
    if (phase == 'cut') {
      final ffmNow = stSmm / k;
      leanLoss = leanLossPerWeek(deficitRatio, params['proteinPerFFM'],
          stBfm / w * 100, profile['sex'], ffmNow);
      smmDelta -= leanLoss * k;
    }
  }

  final nextSmm = math.max(1.0, stSmm + smmDelta);
  var nextBfm = math.max(0.5, stBfm + fatDelta);
  final nextFfm = nextSmm / k;
  final essentialPct = profile['sex'] == 'female' ? 12 : 5;
  final floorFat = nextFfm * essentialPct / (100 - essentialPct);
  if (nextBfm < floorFat) {
    nextBfm = floorFat;
    hitFatFloor = true;
  }

  return {
    'state': {
      'smmKg': nextSmm,
      'bfmKg': nextBfm,
      'ffmKg': nextFfm,
      'weightKg': nextFfm + nextBfm,
    },
    'fatFloor': hitFatFloor,
    'tdee': jsRound(tdee),
    'bmr': jsRound(bmr),
    'intake': jsRound(intake),
    'deficit': jsRound(deficit),
    'capped': capped,
    'floored': floored,
    'fatDelta': fatDelta,
    'smmDelta': smmDelta,
    'leanLoss': leanLoss,
  };
}

/* --- 5. 강도 파라미터 ------------------------------------------------------- */

/* 강도는 이산 3단계가 아니라 연속 변수 a ∈ [0,1] 입니다. 이유는 원본 주석에
   있습니다. 여기서 옮기며 조심한 것은 두 가지뿐입니다:
     · `Object.keys(R).forEach` 의 **순서**를 그대로 둡니다. Dart 의 맵
       리터럴도 넣은 순서를 지키므로 그대로 씁니다.
     · `Math.round` 로 정수화하는 칸이 정해져 있습니다. 나머지는 실수 그대로
       나갑니다 — 반올림해 버리면 단백질 g/kg 이 2.0 과 3.0 뿐이 됩니다. */

const Map<String, List<double>> kCutRange = {
  'ratePct': [0.0015, 0.0090],
  'deficitPct': [0.050, 0.275],
  'proteinPerFFM': [2.0, 3.1],
  'fatPerKg': [0.95, 0.60],
  'days': [3, 6],
  'sessionMin': [40, 85],
  'cardioMin': [60, 240],
  'setsPerMuscle': [8, 20],
  'deloadEvery': [10, 4],
};

const Map<String, List<double>> kBulkRange = {
  'surplusPct': [0.040, 0.175],
  'leanFraction': [0.75, 0.40],
  'proteinPerFFM': [1.9, 2.2],
  'fatPctKcal': [0.30, 0.22],
  'days': [3, 6],
  'sessionMin': [45, 80],
  'cardioMin': [90, 75],
  'setsPerMuscle': [10, 22],
  'deloadEvery': [10, 4],
};

const Set<String> _roundedParams = {
  'days', 'sessionMin', 'cardioMin', 'setsPerMuscle', 'deloadEvery'
};

double lerp(List<double> range, double a) => range[0] + (range[1] - range[0]) * a;

/// @param a    공격성 0..1   @param mode 'cut'|'bulk'
/// @param con  몸만들기 모드의 제약 {aMin,aMax,proteinPerFfmMin,proteinPerFfmMax}
Map<String, Object?> paramsAt(Object? aRaw, Object? mode, [Map<String, Object?>? con]) {
  final a = math.max(0.0, math.min(1.0, jsToNumber(aRaw)));
  final r = mode == 'bulk' ? kBulkRange : kCutRange;
  final p = <String, Object?>{'a': a, 'mode': mode};
  r.forEach((k, v) {
    final x = lerp(v, a);
    p[k] = _roundedParams.contains(k) ? jsRound(x) : x;
  });
  /* NaN 은 어느 비교에서도 거짓이라 마지막 가지로 떨어집니다 — JS 와 같습니다. */
  final difficulty = a < 0.34 ? 1 : (a < 0.7 ? 2 : 3);
  p['difficulty'] = difficulty;
  p['difficultyLabel'] = ['', '★☆☆ 낮음', '★★☆ 보통', '★★★ 높음'][difficulty];
  p['cheatMealsPerWeek'] = a < 0.34 ? 2 : (a < 0.7 ? 1 : 0);
  p['tracking'] = a < 0.34
      ? '단백질만 대충 기록'
      : (a < 0.7 ? '칼로리 + 단백질 기록' : '4대 매크로 전부 + 주 4회 체중');
  p['maxContinuousWeeks'] =
      mode == 'cut' ? (a >= 0.7 ? 12 : (a >= 0.45 ? 20 : 24)) : null;
  p['muscleLossRisk'] = mode == 'cut'
      ? (a >= 0.7 ? '중간~높음' : (a >= 0.45 ? '낮음' : '매우 낮음'))
      : '해당 없음';

  if (con != null && con['proteinPerFfmMin'] != null && con['proteinPerFfmMax'] != null) {
    /* `con.aMax != null && con.aMax > con.aMin` — aMin 이 아예 없으면 NaN 과의
       비교라 거짓이고 span 은 1 이 됩니다. Dart Map 은 "없음" 과 "null" 이
       같아 보이므로 jsNum 으로 가릅니다. (con 은 modes.js 가 만들고 값은
       전부 숫자입니다 — 문자열끼리의 사전순 비교까지는 흉내 내지 않습니다.) */
    final aMax = jsNum(con, 'aMax');
    final aMin = jsNum(con, 'aMin');
    final span = (con['aMax'] != null && aMax > aMin) ? (aMax - aMin) : 1.0;
    final aMinOr0 = jsTruthy(con['aMin']) ? jsToNumber(con['aMin']) : 0.0;
    final t = math.max(0.0, math.min(1.0, (a - aMinOr0) / span));
    final lo = jsToNumber(con['proteinPerFfmMin']);
    final hi = jsToNumber(con['proteinPerFfmMax']);
    p['proteinPerFFM'] = lo + (hi - lo) * t;
  }
  return p;
}

/// 운동 처방. 식단 공격성이 아니라 "낼 수 있는 시간"과 목표가 정합니다.
Map<String, Object?> resolveTraining(Map<String, Object?> profile,
    Map<String, Object?> params, Map<String, Object?>? goalInfo) {
  /* `profile.daysPerWeek || params.days` — 0 도 거짓이라 params 로 떨어집니다. */
  final pick = jsTruthy(profile['daysPerWeek']) ? profile['daysPerWeek'] : params['days'];
  final days = math.min(6.0, math.max(3.0, jsToNumber(pick)));
  /* sessionMinutes 는 숫자로 강제되지 않고 **그대로** 나갑니다. */
  final sessionMin =
      jsTruthy(profile['sessionMinutes']) ? profile['sessionMinutes'] : params['sessionMin'];
  var sets = jsToNumber(params['setsPerMuscle']);
  final reason = <String>[];
  if (goalInfo != null && _gt(goalInfo['dSmmKg'], 0.3)) {
    sets = math.max(sets, 12.0);
    reason.add('근육 증가가 목표라 근육군당 주 ${jsNumToString(sets)}세트를 유지합니다');
  }
  if (goalInfo != null && goalInfo['dBfmKg'] is num && (goalInfo['dBfmKg'] as num) < -0.3) {
    reason.add('감량 중에는 볼륨을 유지하는 것이 근손실을 막는 가장 강력한 수단입니다');
  }
  return {
    'days': days,
    'sessionMin': sessionMin,
    'setsPerMuscle': sets,
    'cardioMin': params['cardioMin'],
    'reason': reason,
  };
}

/* --- 6. 전략 시뮬레이션 ----------------------------------------------------- */

Map<String, Object?> snapshot(
    Map<String, Object?> st, int week, String phase, Map<String, Object?>? meta) {
  final w = _f(st, 'weightKg');
  return {
    'week': week,
    'phase': phase,
    'weightKg': r1(w),
    'smmKg': r2(_f(st, 'smmKg')),
    'bfmKg': r2(_f(st, 'bfmKg')),
    'ffmKg': r1(_f(st, 'ffmKg')),
    'pbfPct': r1(_f(st, 'bfmKg') / w * 100),
    'intake': meta != null ? meta['intake'] : null,
    'tdee': meta != null ? meta['tdee'] : null,
    'deficit': meta != null ? meta['deficit'] : null,
  };
}

/// 전략 A — 동시 진행 (리컴프 / 단순감량 / 단순증량)
Map<String, Object?> simulateSimultaneous(
    Map<String, Object?> cur,
    Map<String, Object?> goal,
    Map<String, Object?> profile,
    Object? a,
    Map<String, Object?> goalInfo,
    Map<String, Object?>? con) {
  final k = _f(cur, 'smmToFfm');
  final isCutting = goalInfo['dBfmKg'] is num && (goalInfo['dBfmKg'] as num) < -0.3;
  final mode = isCutting ? 'cut' : (_gt(goalInfo['dSmmKg'], 0.3) ? 'bulk' : 'maintain');
  final params = paramsAt(a, mode == 'bulk' ? 'bulk' : 'cut', con);
  var phase = mode;

  var st = <String, Object?>{
    'smmKg': cur['smmKg'],
    'bfmKg': cur['bfmKg'],
    'ffmKg': cur['ffmKg'],
    'weightKg': cur['weightKg'],
  };
  final traj = <Map<String, Object?>>[snapshot(st, 0, phase, null)];
  /* 목표 지방을 넘긴 채 끝나도 "도달"로 표시되던 버그가 여기 있었습니다. */
  int? fatWeek = _gte(goalInfo['dBfmKg'], -0.3) ? 0 : null;
  int? smmWeek = (goalInfo['dSmmKg'] is num && (goalInfo['dSmmKg'] as num) <= 0.3) ? 0 : null;
  var anyCapped = false, anyFloored = false;
  var cutWeeks = 0;
  var leanLossTotal = 0.0;
  var fatBreached = false, anyFatFloor = false;

  final goalBfm = _f(goal, 'bfmKg');
  final goalSmm = _f(goal, 'smmKg');

  for (var wk = 1; wk <= maxWeeks; wk++) {
    final r = stepWeek(st, phase, params, profile, k, wk);
    st = (r['state'] as Map).cast<String, Object?>();
    if (phase == 'cut') cutWeeks++;
    if (r['capped'] == true) anyCapped = true;
    if (r['floored'] == true) anyFloored = true;
    if (r['fatFloor'] == true) {
      anyFatFloor = true;
      break;
    }
    if (_gt(r['leanLoss'], 0)) leanLossTotal += _f(r, 'leanLoss');
    traj.add(snapshot(st, wk, phase, r));

    final bfm = _f(st, 'bfmKg');
    final smm = _f(st, 'smmKg');
    if (fatWeek == null && bfm <= goalBfm + 0.05) fatWeek = wk;
    if (smmWeek == null && smm >= goalSmm - 0.005) smmWeek = wk;

    if (phase == 'bulk' && bfm > goalBfm + 0.05) {
      phase = 'maintain';
      fatBreached = true;
    }
    if (fatWeek != null && smmWeek != null && bfm <= goalBfm + 0.05) break;
    if (phase == 'cut' && fatWeek != null && smmWeek == null) phase = 'maintain';
  }

  final fatOk = _f(st, 'bfmKg') <= goalBfm + 0.05;
  final reached = fatWeek != null && smmWeek != null && fatOk;
  final weeks = reached ? math.max(fatWeek, smmWeek) : null;
  final bottleneck = !reached
      ? ((fatBreached || !fatOk) ? 'fatOvershoot' : 'unreachable')
      : (smmWeek > fatWeek ? 'muscle' : (fatWeek > smmWeek ? 'fat' : 'both'));

  return {
    'strategy': 'simultaneous',
    'strategyLabel': '동시 진행',
    'strategyDesc': isCutting && _gt(goalInfo['dSmmKg'], 0.3)
        ? '체지방을 줄이면서 동시에 근육을 늘립니다 (리컴프)'
        : (isCutting ? '체지방 감량에 집중합니다' : '근육 증가에 집중합니다'),
    'a': a,
    'params': params,
    'mode': mode,
    'weeks': weeks,
    'reached': reached,
    'fatWeek': fatWeek,
    'smmWeek': smmWeek,
    'fatOvershootKg': fatOk ? 0 : r2(_f(st, 'bfmKg') - goalBfm),
    'bottleneck': bottleneck,
    'trajectory': traj,
    'capped': anyCapped,
    'floored': anyFloored,
    'fatFloorReached': anyFatFloor,
    'continuousCutWeeks': cutWeeks,
    'leanLossKg': r2(leanLossTotal),
    'phases': [
      {
        'name': mode == 'cut' ? '감량' : (mode == 'bulk' ? '증량' : '유지'),
        'from': 0,
        'to': weeks,
        'phase': mode,
      }
    ],
  };
}

/// 전략 B — 분할 (감량 → 유지 2주 → 증량 → 미니컷)
Map<String, Object?> simulateSplit(
    Map<String, Object?> cur,
    Map<String, Object?> goal,
    Map<String, Object?> profile,
    Object? a,
    Map<String, Object?> goalInfo,
    Map<String, Object?>? con) {
  final k = _f(cur, 'smmToFfm');
  final cutP = paramsAt(a, 'cut', con);
  final bulkP = paramsAt(a, 'bulk', con);
  var st = <String, Object?>{
    'smmKg': cur['smmKg'],
    'bfmKg': cur['bfmKg'],
    'ffmKg': cur['ffmKg'],
    'weightKg': cur['weightKg'],
  };
  final traj = <Map<String, Object?>>[snapshot(st, 0, 'cut', null)];
  var wk = 0, guard = 0;
  final phaseMarks = <Map<String, Object?>>[];
  var anyCapped = false, anyFloored = false;
  var longestCut = 0;
  var leanLossTotal = 0.0;

  final goalBfm = _f(goal, 'bfmKg');
  final goalSmm = _f(goal, 'smmKg');

  void run(String phase, Map<String, Object?> params,
      bool Function(Map<String, Object?>) stop, String label, int? maxLen) {
    final start = wk;
    var len = 0;
    /* `guard++ < MAX_WEEKS` — 먼저 비교하고 나서 늘립니다. */
    while (guard++ < maxWeeks && (maxLen == null || len < maxLen)) {
      if (stop(st)) break;
      final r = stepWeek(st, phase, params, profile, k, wk);
      st = (r['state'] as Map).cast<String, Object?>();
      wk++;
      len++;
      if (r['capped'] == true) anyCapped = true;
      if (r['floored'] == true) anyFloored = true;
      if (_gt(r['leanLoss'], 0)) leanLossTotal += _f(r, 'leanLoss');
      traj.add(snapshot(st, wk, phase, r));
    }
    if (len > 0) {
      phaseMarks.add(
          {'name': label, 'from': start, 'to': wk, 'phase': phase, 'weeks': len});
      if (phase == 'cut') longestCut = math.max(longestCut, len);
    }
  }

  run('cut', cutP, (s) => _f(s, 'bfmKg') <= goalBfm + 0.05, '1단계 · 감량', null);
  run('maintain', cutP, (s) => false, '2단계 · 유지 (대사 회복)', 2);
  run('bulk', bulkP, (s) => _f(s, 'smmKg') >= goalSmm - 0.005, '3단계 · 증량', null);
  run('cut', cutP, (s) => _f(s, 'bfmKg') <= goalBfm + 0.05, '4단계 · 미니컷', null);

  final reached = _f(st, 'bfmKg') <= goalBfm + 0.1 && _f(st, 'smmKg') >= goalSmm - 0.02;
  return {
    'strategy': 'split',
    'strategyLabel': '분할 (감량 → 증량)',
    'strategyDesc': '먼저 체지방을 빼고, 유지기를 거쳐 근육을 올린 뒤, 붙은 지방을 다시 정리합니다',
    'a': a,
    'params': cutP,
    'bulkParams': bulkP,
    'mode': 'split',
    'weeks': reached ? wk : null,
    'reached': reached,
    'bottleneck': 'sequence',
    'trajectory': traj,
    'capped': anyCapped,
    'floored': anyFloored,
    'continuousCutWeeks': longestCut,
    'leanLossKg': r2(leanLossTotal),
    'phases': phaseMarks,
  };
}

/// 주어진 공격성 a 에서 더 빠른 전략을 고릅니다.
Map<String, Object?> bestAt(
    Map<String, Object?> cur,
    Map<String, Object?> goal,
    Map<String, Object?> profile,
    Object? a,
    Map<String, Object?> goalInfo,
    Map<String, Object?>? con) {
  final force = (con != null && jsTruthy(con['strategy']) && con['strategy'] != 'auto')
      ? con['strategy']
      : null;
  final sim = simulateSimultaneous(cur, goal, profile, a, goalInfo, con);
  if (force == 'simultaneous') {
    sim['alternative'] = null;
    return sim;
  }
  if (goalInfo['type'] != 'recomp' && force != 'split') {
    sim['alternative'] = null;
    return sim;
  }
  final split = simulateSplit(cur, goal, profile, a, goalInfo, con);
  if (force == 'split' && split['reached'] == true) {
    split['alternative'] = null;
    return split;
  }
  Map<String, Object?> best, alt;
  if (split['reached'] == true &&
      (sim['reached'] != true || _f(split, 'weeks') < _f(sim, 'weeks'))) {
    best = split;
    alt = sim;
  } else {
    best = sim;
    alt = split;
  }
  best['alternative'] = alt['reached'] == true
      ? {
          'strategy': alt['strategy'],
          'strategyLabel': alt['strategyLabel'],
          'weeks': alt['weeks'],
        }
      : null;
  return best;
}

/* --- 7. 강도 = 기간 — 역산 -------------------------------------------------- */

final List<double> aGrid =
    List<double>.generate(51, (i) => i / 50, growable: false);

/// a 를 0→1 로 훑어 (공격성, 소요기간) 곡선을 만듭니다. 이 곡선이 단조가
/// 아니라는 것이 핵심입니다 — 너무 공격적이면 근육이 안 늘어 오히려 길어집니다.
List<Map<String, Object?>> scanCurve(
    Map<String, Object?> cur,
    Map<String, Object?> goal,
    Map<String, Object?> profile,
    Map<String, Object?> goalInfo,
    Map<String, Object?>? con) {
  final lo = (con != null && con['aMin'] != null) ? jsToNumber(con['aMin']) : 0.0;
  var hi = (con != null && con['aMax'] != null) ? jsToNumber(con['aMax']) : 1.0;
  if (hi <= lo) hi = math.min(1.0, lo + 0.05);
  return aGrid.map((t) {
    final a = lo + (hi - lo) * t;
    final sim = bestAt(cur, goal, profile, a, goalInfo, con);
    return <String, Object?>{
      'a': a,
      'weeks': sim['reached'] == true ? sim['weeks'] : null,
      'sim': sim,
    };
  }).toList();
}

/* --- 8. 세 강도 비교 -------------------------------------------------------- */

class LevelSpec {
  final String key, label, title, blurb;
  final double durationMult;
  const LevelSpec(this.key, this.label, this.title, this.durationMult, this.blurb);
}

const List<LevelSpec> kLevelSpec = [
  LevelSpec('high', '상', '최단', 1.0, '가능한 가장 빠르게. 식단 제약이 가장 빡빡합니다.'),
  LevelSpec('mid', '중', '표준', 1.4, '여유를 조금 두고. 근육 보존과 지속성의 균형점입니다.'),
  LevelSpec('low', '하', '여유', 2.0, '생활을 크게 바꾸지 않고. 중도 포기 확률이 가장 낮습니다.'),
];

/* JS 의 Array.prototype.sort 는 **안정** 정렬입니다(ES2019 부터 명세).
   Dart 의 List.sort 는 길이가 짧을 때만 우연히 안정적이라 보장이 없습니다.
   여기서 정렬하는 것은 세 장의 카드뿐이지만, 동점일 때 어느 쪽이 추천으로
   뽑히느냐가 사용자에게 보이는 답이라 명시적으로 안정화합니다. */
List<T> _sortedStable<T>(List<T> list, num Function(T, T) cmp) {
  final order = List<int>.generate(list.length, (i) => i);
  order.sort((i, j) {
    final c = cmp(list[i], list[j]);
    if (c < 0) return -1;
    if (c > 0) return 1;
    return i - j;          // NaN 도 여기로 옵니다 — JS 가 순서를 지키는 것과 같습니다
  });
  return [for (final i in order) list[i]];
}

double avgWeeklyRate(List<Map<String, Object?>> traj, int n) {
  final end = math.min(n, traj.length - 1);
  if (end < 1) return 0;
  return r2((_f(traj[end], 'weightKg') - _f(traj[0], 'weightKg')) / end);
}

double avgWeeklyFat(List<Map<String, Object?>> traj, int n) {
  final end = math.min(n, traj.length - 1);
  if (end < 1) return 0;
  return r2((_f(traj[end], 'bfmKg') - _f(traj[0], 'bfmKg')) / end);
}

double avgWeeklySmm(List<Map<String, Object?>> traj, int n) {
  final end = math.min(n, traj.length - 1);
  if (end < 1) return 0;
  return jsRound((_f(traj[end], 'smmKg') - _f(traj[0], 'smmKg')) / end * 1000) / 1000;
}

List<Map<String, Object?>> _traj(Map<String, Object?> sim) =>
    (sim['trajectory'] as List).cast<Map<String, Object?>>();

/// 계획 1주차 기준 매크로. 체크인마다 다시 계산되는 값입니다.
Map<String, Object?> macrosFor(
    Map<String, Object?> sim, Map<String, Object?> cur, Map<String, Object?> profile) {
  final traj = _traj(sim);
  final t = traj.length > 1 ? traj[1] : traj[0];
  /* `t.intake || cur.tdeeKcal` — 0 도 거짓이라 TDEE 로 떨어집니다. */
  final intake = jsTruthy(t['intake']) ? _f(t, 'intake') : _f(cur, 'tdeeKcal');
  final ffm = _f(t, 'ffmKg'), bw = _f(t, 'weightKg');
  final phases = (sim['phases'] as List);
  final firstPhase = (phases.isNotEmpty &&
          jsTruthy((phases[0] as Map)['phase']))
      ? '${(phases[0] as Map)['phase']}'
      : 'cut';
  final isBulk = firstPhase == 'bulk';
  final p = isBulk
      ? ((sim['bulkParams'] as Map<String, Object?>?) ?? paramsAt(sim['a'], 'bulk'))
      : sim['params'] as Map<String, Object?>;

  // 체중 기준 하한도 함께 겁니다 — 단백질이 모자라면 계획 자체가 무의미합니다.
  final proteinG = jsRound(math.max(ffm * _f(p, 'proteinPerFFM'), bw * 1.6));
  var fatG = isBulk
      ? jsRound(intake * _f(p, 'fatPctKcal') / 9)
      : jsRound(bw * _f(p, 'fatPerKg'));
  var carbKcal = intake - proteinG * 4 - fatG * 9;
  if (carbKcal < 200) {                       // 탄수 바닥 — 지방부터 줄입니다
    final need = 200 - carbKcal;
    fatG = math.max(jsRound(bw * 0.4), fatG - (need / 9).ceilToDouble());
    carbKcal = intake - proteinG * 4 - fatG * 9;
  }
  final carbG = math.max(50, jsRound(carbKcal / 4));

  return {
    'intakeKcal': jsRound(intake),
    'tdeeKcal': jsTruthy(t['tdee']) ? t['tdee'] : cur['tdeeKcal'],
    'deficitKcal': jsTruthy(t['deficit']) ? t['deficit'] : 0,
    'proteinG': proteinG,
    'carbG': carbG,
    'fatG': fatG,
    'proteinPerFFM': r1(_f(p, 'proteinPerFFM')),
    'proteinPerBW': r1(proteinG / bw),
    'pctProtein': jsRound(proteinG * 4 / intake * 100),
    'pctCarb': jsRound(carbG * 4 / intake * 100),
    'pctFat': jsRound(fatG * 9 / intake * 100),
  };
}

Map<String, Object?> feasibility(Map<String, Object?> sim, Map<String, Object?> goalInfo,
    Map<String, Object?> cur, Map<String, Object?> profile, Object? deadlineWeeks) {
  final blockers = <String>[];
  final essentialFat = profile['sex'] == 'male' ? 8 : 15;
  final goalFfm = (_f(cur, 'smmKg') + _f(goalInfo, 'dSmmKg')) / _f(cur, 'smmToFfm');
  final goalFfmi = ffmiOf(goalFfm, profile['heightCm']);
  final ceil = ffmiCeiling(profile['sex']);
  if (goalFfmi > ceil) {
    blockers.add('목표 골격근량이 약물 없이 도달 가능한 상한을 넘습니다 (제지방량지수 '
        '${jsNumToString(r1(goalFfmi))}, 상한 약 ${jsNumToString(ceil)}).');
  }
  if (_f(goalInfo, 'targetPbfPct') < essentialFat) {
    blockers.add('목표 체지방률 ${jsNumToString(_f(goalInfo, 'targetPbfPct'))}%는 '
        '필수지방($essentialFat%) 아래입니다.');
  }
  if (sim['reached'] != true) blockers.add('이 설정으로는 4년 안에도 목표에 도달하지 않습니다.');

  final weeks = sim['weeks'];
  final dw = jsToNumber(deadlineWeeks);
  String verdict, badge, message;
  if (blockers.isNotEmpty) {
    verdict = 'blocked';
    badge = '⛔';
    message = blockers[0];
  } else if (!jsTruthy(deadlineWeeks)) {
    verdict = 'ok';
    badge = '🟢';
    message = '이 강도로 약 ${_s(weeks)}주 걸립니다.';
  } else if (jsToNumber(weeks) <= dw) {
    verdict = 'ok';
    badge = '🟢';
    message = '희망하신 ${_s(deadlineWeeks)}주 안에 가능합니다 (예상 ${_s(weeks)}주).';
  } else if (jsToNumber(weeks) <= dw * 1.5) {
    verdict = 'tough';
    badge = '🟡';
    message = '가능은 하지만 ${_s(weeks)}주가 필요합니다 '
        '(희망보다 ${jsNumToString(jsToNumber(weeks) - dw)}주 김).';
  } else {
    verdict = 'unrealistic';
    badge = '🔴';
    message = '${_s(deadlineWeeks)}주 안에는 어렵습니다. 정직하게 약 ${_s(weeks)}주가 필요합니다.';
  }
  return {
    'verdict': verdict, 'badge': badge, 'message': message,
    'blockers': blockers, 'weeks': weeks,
  };
}

/// JS 의 문자열 붙이기(`'' + x`). null 은 "null", 숫자는 정수면 소수점 없이.
String _s(Object? x) {
  if (x == null) return 'null';
  if (x is num) return jsNumToString(x);
  if (x is bool) return x ? 'true' : 'false';
  return '$x';
}

/// 이 모드에서 고를 수 있는 기간 폭이 **왜** 이만큼인지 설명합니다.
/// 좁으면 좁은 이유를 말해야지, 세 장의 카드로 넓은 척하면 안 됩니다.
Map<String, Object?> spanNote(num minW, num maxW, Map<String, Object?>? modeDef) {
  final spread = maxW - minW;
  final ratio = minW > 0 ? maxW / minW : 1;
  if (modeDef == null) {
    return {
      'spread': spread,
      'tight': ratio < 1.35,
      'text': '이 목표는 ${_s(minW)}~${_s(maxW)}주 사이에서 고를 수 있습니다.',
    };
  }
  var text = '「${_s(modeDef['nameKo'])}」 안에서는 이 목표가 ${_s(minW)}~${_s(maxW)}주입니다.';
  if (ratio < 1.35) {
    text += ' 폭이 좁은 이유는 두 가지입니다 — 아래로는 이 모드가 허용하는 가장 느린 속도(공격성 '
        '${_s(modeDef['aMin'])})에 이미 닿았고, 위로는 체지방이 하루에 안전하게 내놓을 수 있는 '
        '에너지 상한에 걸립니다. 더 여유롭게 가고 싶으면 강도가 아니라 모드를 바꿔야 합니다.';
  }
  return {'spread': spread, 'tight': ratio < 1.35, 'text': text};
}

Map<String, Object?>? bottleneckNote(
    List<Map<String, Object?>> results, Map<String, Object?> goalInfo) {
  Map<String, Object?>? r;
  for (final x in results) {
    if ((x['sim'] as Map)['reached'] == true) {
      r = x;
      break;
    }
  }
  if (r == null) return null;
  final b = (r['sim'] as Map)['bottleneck'];
  if (b == 'muscle') {
    return {'key': 'muscle', 'text': '병목은 근육 목표입니다. 체지방은 훨씬 먼저 도달하지만, 근육은 생리적 속도 상한 때문에 기다려야 합니다.'};
  }
  if (b == 'fat') return {'key': 'fat', 'text': '병목은 체지방 목표입니다. 근육 목표는 먼저 달성됩니다.'};
  if (b == 'sequence') {
    return {'key': 'sequence', 'text': '감량과 증량을 순서대로 나누는 전략이 더 빠릅니다. 동시에 하면 근육 증가가 거의 멈추기 때문입니다.'};
  }
  return {'key': 'both', 'text': '체지방과 근육 목표가 비슷한 시점에 도달합니다.'};
}

/// 유지 계획 — 상/중/하가 "얼마나 오래 유지할까" 가 됩니다.
Map<String, Object?> maintenancePlan(
    Map<String, Object?> cur,
    Map<String, Object?> goal,
    Map<String, Object?> goalInfo,
    Map<String, Object?> profile,
    Object? start,
    Map<String, Object?>? modeDef,
    Object? deadlineWeeks) {
  var span = <String, int>{'high': 4, 'mid': 8, 'low': 12};
  if (jsTruthy(deadlineWeeks)) {
    final d = jsToNumber(deadlineWeeks);
    span = {
      'high': math.max(2, jsRound(d * 0.5)).toInt(),
      'mid': math.max(3, d).toInt(),
      'low': math.max(4, jsRound(d * 1.5)).toInt(),
    };
  }
  final k = _f(cur, 'smmToFfm');
  final params = paramsAt(0, 'cut',
      modeDef == null
          ? null
          : {
              'aMin': modeDef['aMin'], 'aMax': modeDef['aMax'],
              'proteinPerFfmMin': modeDef['proteinPerFfmMin'],
              'proteinPerFfmMax': modeDef['proteinPerFfmMax'],
            });

  const titles = {'high': '짧게', 'mid': '표준', 'low': '길게'};
  const blurbs = {
    'high': '4주만 굳히고 다음 단계로',
    'mid': '8주 — 대사 회복에 보통 권하는 길이',
    'low': '12주 — 습관이 자리 잡을 때까지',
  };

  final results = kLevelSpec.map((spec) {
    final weeks = span[spec.key]!;
    var st = <String, Object?>{
      'smmKg': cur['smmKg'], 'bfmKg': cur['bfmKg'],
      'ffmKg': cur['ffmKg'], 'weightKg': cur['weightKg'],
    };
    final traj = <Map<String, Object?>>[snapshot(st, 0, 'maintain', null)];
    for (var w = 1; w <= weeks; w++) {
      final r = stepWeek(st, 'maintain', params, profile, k, w);
      st = (r['state'] as Map).cast<String, Object?>();
      traj.add(snapshot(st, w, 'maintain', r));
    }
    final sim = <String, Object?>{
      'strategy': 'maintain', 'strategyLabel': '유지',
      'strategyDesc': '지금 몸을 지키면서 대사와 습관을 안정시킵니다',
      'a': 0, 'params': params, 'mode': 'maintain',
      'weeks': weeks, 'reached': true, 'bottleneck': 'none',
      'trajectory': traj, 'capped': false, 'floored': false,
      'continuousCutWeeks': 0, 'leanLossKg': 0, 'alternative': null,
      'phases': [
        {'name': '유지', 'from': 0, 'to': weeks, 'phase': 'maintain', 'weeks': weeks}
      ],
    };
    final macros = macrosFor(sim, cur, profile);
    final training = resolveTraining(profile, params, goalInfo);
    return <String, Object?>{
      'level': spec.key, 'label': spec.label,
      'title': titles[spec.key], 'blurb': blurbs[spec.key],
      'targetWeeks': weeks, 'weeks': weeks, 'months': r1(weeks / 4.345),
      'targetDate': addWeeks(start, weeks), 'a': 0,
      'sim': sim, 'macros': macros,
      'feasibility': {
        'verdict': 'ok', 'badge': '🟢',
        'message': '$weeks주 동안 지금 몸을 지킵니다.', 'blockers': <String>[], 'weeks': weeks,
      },
      'difficulty': 1, 'difficultyLabel': '★☆☆ 낮음',
      'training': training,
      'daysPerWeek': training['days'], 'sessionMin': training['sessionMin'],
      'cardioMin': training['cardioMin'], 'setsPerMuscle': training['setsPerMuscle'],
      'cheatMeals': 2, 'tracking': '무게만 주 2~3회',
      'muscleLossRisk': '매우 낮음',
      'weeklyRateKg': 0, 'weeklyRatePct': 0, 'weeklyFatKg': 0,
      'weeklySmmKg': avgWeeklySmm(traj, 8),
    };
  }).toList();

  return {
    'current': cur, 'goal': goal, 'goalInfo': goalInfo, 'mode': modeDef,
    'startDate': toISODate(start),
    'minWeeks': span['high'], 'maxWeeks': span['low'],
    'spanWeeks': [span['high'], span['low']],
    'spanNote': {
      'spread': span['low']! - span['high']!, 'tight': false,
      'text': '유지는 도달할 목표가 아니라 지켜낼 기간입니다. 얼마나 오래 유지할지를 고릅니다.',
    },
    'curve': <Object?>[], 'results': results, 'recommended': 'mid',
    'warnings': <String>[],
    'bottleneckNote': {'key': 'none', 'text': '유지 구간입니다. 체중이 ±1kg 안에서 움직이면 성공입니다.'},
    'isMaintenance': true,
  };
}

/// 세 강도(상=최단 / 중=×1.4 / 하=×2.0)를 계산합니다.
Map<String, Object?> compareLevels(
    Map<String, Object?> scan,
    Map<String, Object?> profile,
    Map<String, Object?> goal,
    Object? startDateISO,
    Object? deadlineWeeks,
    Map<String, Object?>? modeDef) {
  final cur = derive(scan, profile);
  final goalInfo = classifyGoal(cur, goal);
  final start = jsTruthy(startDateISO) ? jsParseDate(startDateISO) : DateTime.now();
  final con = modeDef == null
      ? null
      : <String, Object?>{
          'aMin': modeDef['aMin'], 'aMax': modeDef['aMax'],
          'strategy': modeDef['strategy'],
          'proteinPerFfmMin': modeDef['proteinPerFfmMin'],
          'proteinPerFfmMax': modeDef['proteinPerFfmMax'],
        };
  if (goalInfo['type'] == 'maintain') {
    return maintenancePlan(cur, goal, goalInfo, profile, start, modeDef, deadlineWeeks);
  }

  final curve = scanCurve(cur, goal, profile, goalInfo, con);
  final reachable = curve.where((c) => c['weeks'] != null).toList();

  if (reachable.isEmpty) {
    return {
      'current': cur, 'goal': goal, 'goalInfo': goalInfo, 'curve': curve,
      'mode': modeDef, 'startDate': toISODate(start),
      'results': <Object?>[], 'recommended': null,
      'warnings': ['어떤 강도로도 4년 안에 목표에 도달하지 않습니다. 목표치를 조정해 주세요.'],
      'bottleneckNote': null, 'impossible': true,
    };
  }

  final weeksOf = (Map<String, Object?> c) => jsToNumber(c['weeks']);
  var minWeeks = weeksOf(reachable[0]);
  var maxW = weeksOf(reachable[0]);
  for (final c in reachable) {
    minWeeks = math.min(minWeeks, weeksOf(c));
    maxW = math.max(maxW, weeksOf(c));
  }
  // 동률이면 가장 여유로운(a 작은) 쪽 — 같은 기간이면 쉬운 게 낫습니다.
  final fastest = reachable.firstWhere((c) => weeksOf(c) == minWeeks);

  /* 고정 배수로 목표를 잡으면 모드가 a 하한을 걸어 둔 경우 중·하가 둘 다
     하한에 붙어 같은 계획이 됩니다. 그래서 "갈 수 있는 범위" 안으로 접습니다. */
  var gentlePool =
      reachable.where((c) => jsToNumber(c['a']) <= jsToNumber(fastest['a'])).toList();
  if (gentlePool.isEmpty) gentlePool = reachable;
  var slowest = gentlePool[0];
  for (final c in gentlePool) {
    if (weeksOf(c) > weeksOf(slowest)) slowest = c;
  }
  final slowWeeks = math.min(weeksOf(slowest), jsRound(minWeeks * 2.0));
  final target = <String, num>{
    'high': minWeeks,
    'mid': jsRound((minWeeks + slowWeeks) / 2),
    'low': slowWeeks,
  };

  final results = kLevelSpec.map((spec) {
    final targetWeeks = target[spec.key]!;
    var chosen = gentlePool[0];
    if (spec.key == 'high') {
      chosen = fastest;
    } else {
      for (final c in gentlePool) {
        if ((weeksOf(c) - targetWeeks).abs() < (weeksOf(chosen) - targetWeeks).abs()) {
          chosen = c;
        }
      }
    }
    final sim = chosen['sim'] as Map<String, Object?>;
    final macros = macrosFor(sim, cur, profile);
    final params = sim['params'] as Map<String, Object?>;
    final training = resolveTraining(profile, params, goalInfo);
    final feas = feasibility(sim, goalInfo, cur, profile, deadlineWeeks);
    final traj = _traj(sim);
    return <String, Object?>{
      'level': spec.key, 'label': spec.label, 'title': spec.title, 'blurb': spec.blurb,
      'targetWeeks': targetWeeks,
      'weeks': sim['weeks'],
      'months': r1(jsToNumber(sim['weeks']) / 4.345),
      'targetDate': addWeeks(start, jsToNumber(sim['weeks'])),
      'a': chosen['a'],
      'sim': sim, 'macros': macros, 'feasibility': feas,
      'difficulty': params['difficulty'],
      'difficultyLabel': params['difficultyLabel'],
      'training': training,
      'daysPerWeek': training['days'],
      'sessionMin': training['sessionMin'],
      'cardioMin': training['cardioMin'],
      'setsPerMuscle': training['setsPerMuscle'],
      'cheatMeals': params['cheatMealsPerWeek'],
      'tracking': params['tracking'],
      'muscleLossRisk': params['muscleLossRisk'],
      'weeklyRateKg': avgWeeklyRate(traj, 8),
      'weeklyRatePct': r2(avgWeeklyRate(traj, 8).abs() / _f(cur, 'weightKg') * 100),
      'weeklyFatKg': avgWeeklyFat(traj, 8),
      'weeklySmmKg': avgWeeklySmm(traj, 8),
    };
  }).toList();

  // 중복 제거: 세 강도가 같은 a 로 수렴하면 표시로 알립니다.
  final warnings = <String>[];
  /* JS 객체의 키는 문자열이라 `uniqueA[r.a]` 는 String(a) 로 묶입니다. */
  final uniqueA = <String>{for (final r in results) _s(r['a'])};
  if (uniqueA.length < 3) {
    if (modeDef != null) {
      final atFloor = results
              .where((r) => (jsToNumber(r['a']) - jsToNumber(modeDef['aMin'])).abs() < 0.005)
              .length >= 2;
      final atCeil = results
              .where((r) => (jsToNumber(r['a']) - jsToNumber(modeDef['aMax'])).abs() < 0.005)
              .length >= 2;
      if (atFloor) {
        warnings.add('「${_s(modeDef['nameKo'])}」는 이보다 느리게 가지 않습니다. 이 모드가 허용하는 '
            '가장 여유로운 속도에 이미 닿아 있어서, 중·하가 같은 계획이 됩니다. '
            '더 천천히 가고 싶으면 모드를 바꿔야 합니다.');
      } else if (atCeil) {
        warnings.add('「${_s(modeDef['nameKo'])}」는 이보다 빠르게 가지 않습니다. 이 모드의 속도 상한은 '
            '장식이 아니라 근육을 지키기 위한 잠금장치입니다.');
      } else {
        warnings.add('일부 강도가 같은 계획으로 수렴했습니다. 체지방이 줄면서 안전하게 쓸 수 있는 '
            '에너지 상한에 먼저 걸려서, 강도를 올려도 속도가 더 나오지 않는 구간입니다.');
      }
    } else {
      warnings.add('일부 강도가 같은 계획으로 수렴했습니다. 목표 변화량이 작아 속도를 더 낮출 여지가 없다는 뜻입니다.');
    }
  }

  // 역설 탐지 — 제일 빡센 계획이 오히려 더 걸리는 구간
  final aggressive = curve[curve.length - 1];
  if (aggressive['weeks'] != null && weeksOf(aggressive) > minWeeks * 1.1) {
    warnings.add('가장 공격적인 계획(a=1.0)은 ${_s(aggressive['weeks'])}주로, 최단(${_s(minWeeks)}'
        '주)보다 오히려 깁니다. 적자가 크면 근육이 거의 늘지 않아서입니다 — 근육 목표가 있을 때는 무작정 빡세게가 답이 아닙니다.');
  }

  for (final r in results) {
    final sim = r['sim'] as Map<String, Object?>;
    final params = sim['params'] as Map<String, Object?>;
    if (jsTruthy(params['maxContinuousWeeks']) &&
        jsToNumber(sim['continuousCutWeeks']) > jsToNumber(params['maxContinuousWeeks'])) {
      r['capWarning'] = '이 강도의 감량은 연속 ${_s(params['maxContinuousWeeks'])}'
          '주가 한계인데 계획상 ${_s(sim['continuousCutWeeks'])}주 연속입니다. 중간에 2주 유지기를 넣으세요.';
    }
    if (jsToNumber(sim['leanLossKg']) > 0.3) {
      r['leanLossWarning'] = '이 속도로 가면 계획 기간 동안 제지방이 약 '
          '${jsNumToString(r1(jsToNumber(sim['leanLossKg'])))}kg 빠질 것으로 계산됩니다. 적자가 깊거나 단백질이 부족하거나 '
          '체지방이 이미 낮을 때 생깁니다.';
    }
    if (sim['capped'] == true) {
      r['capNote'] = '체지방이 줄면서 안전하게 동원 가능한 에너지 상한에 걸려, 후반부에는 계획보다 적자가 자동으로 작아집니다.';
    }
    if (sim['floored'] == true) {
      r['floorNote'] = '계산상 섭취량이 최소 섭취 기준 아래로 내려가 바닥값으로 올렸습니다.';
    }
  }

  // 추천: 기간 차이가 15% 이내면 더 쉬운 쪽
  final ok = results.where((r) => (r['sim'] as Map)['reached'] == true).toList();
  Object? recommended;
  if (ok.isNotEmpty) {
    final best = _sortedStable(ok, (x, y) => jsToNumber(x['weeks']) - jsToNumber(y['weeks']))[0];
    final near = ok
        .where((r) => jsToNumber(r['weeks']) <= jsToNumber(best['weeks']) * 1.15)
        .toList();
    final sorted = _sortedStable(
        near, (x, y) => jsToNumber(x['difficulty']) - jsToNumber(y['difficulty']));
    recommended = sorted[0]['level'];
  }

  return {
    'current': cur, 'goal': goal, 'goalInfo': goalInfo, 'mode': modeDef,
    'startDate': toISODate(start),
    'minWeeks': minWeeks, 'maxWeeks': maxW,
    'spanWeeks': [minWeeks, slowest['weeks']],
    'spanNote': spanNote(minWeeks, weeksOf(slowest), modeDef),
    'curve': [for (final c in curve) {'a': c['a'], 'weeks': c['weeks']}],
    'results': results, 'recommended': recommended, 'warnings': warnings,
    'bottleneckNote': bottleneckNote(results, goalInfo),
  };
}

/* --- 9. 매크로 / 운동 / 식단 ------------------------------------------------ */

const Map<String, Map<String, Object?>> kSplits = {
  '3': {'name': '전신 3분할', 'days': ['전신 A', '휴식', '전신 B', '휴식', '전신 C', '휴식', '휴식']},
  '4': {'name': '상하체 4분할', 'days': ['상체 A', '하체 A', '휴식', '상체 B', '하체 B', '휴식', '휴식']},
  '5': {'name': 'PPL + 상하체', 'days': ['가슴·어깨·삼두', '등·이두', '하체', '휴식', '상체 전체', '하체·코어', '휴식']},
  '6': {'name': 'PPL 2회전', 'days': ['푸시 A', '풀 A', '레그 A', '푸시 B', '풀 B', '레그 B', '휴식']},
};

final RegExp _reFullBody = RegExp('전신');
final RegExp _reUpper = RegExp('상체');
final RegExp _reLower = RegExp('하체|레그');
final RegExp _rePush = RegExp('푸시|가슴');
final RegExp _rePull = RegExp('풀|등');
final RegExp _reCompound = RegExp('스쿼트|데드|벤치|프레스|로우|풀업|딥스');

Map<String, Object?> workoutFor(Map<String, Object?> sim, Map<String, Object?> cur,
    Map<String, Object?> profile, Map<String, Object?>? scan, Map<String, Object?>? goalInfo) {
  final p = sim['params'] as Map<String, Object?>;
  final tr = resolveTraining(profile, p, goalInfo);
  final days = tr['days'];
  /* JS 객체의 키는 문자열이라 `SPLITS[days]` 는 String(days) 로 찾습니다 —
     4.5 나 NaN 이면 없어서 4분할로 떨어집니다. */
  final split = kSplits[_s(days)] ?? kSplits['4']!;

  // 인바디 부위별 분석 → 종목 편향
  final bias = <String>[];
  final segLean = scan == null ? null : scan['segmentalLean'];
  if (segLean is Map) {
    if (segLean['rightArm'] == '표준이하' || segLean['leftArm'] == '표준이하') {
      bias.add('팔 근육 표준 이하 → 팔 보조 볼륨 주 +2세트');
    }
    if (segLean['trunk'] == '표준이하') bias.add('몸통 근육 표준 이하 → 코어·척추기립근 보강');
    if (segLean['rightLeg'] == '표준이하' || segLean['leftLeg'] == '표준이하') {
      bias.add('하체 근육 표준 이하 → 하체 볼륨 주 +3세트');
    }
    if (segLean['rightArm'] != segLean['leftArm']) bias.add('좌우 팔 불균형 → 원암(편측) 종목 우선');
    if (segLean['rightLeg'] != segLean['leftLeg']) bias.add('좌우 다리 불균형 → 불가리안 스플릿스쿼트 필수');
  }
  final segFat = scan == null ? null : scan['segmentalFat'];
  if (segFat is Map) {
    if (segFat['trunk'] == '표준이상') bias.add('몸통 지방 표준 이상 → 내장지방 우선, Z2 유산소 비중 ↑');
    if (segFat['rightArm'] == '표준이상' && segFat['rightLeg'] == '표준') {
      bias.add('상체에 지방이 몰린 패턴 → 상체 볼륨보다 전신 에너지 소모 우선');
    }
  }
  /* 부위별 값이 없으면 "약점 없음" 이라고 말하지 않습니다 — 본 적이 없으니까요.
     이유는 원본 주석에 길게 있습니다. */
  final hasSegmental = scan != null && (jsTruthy(scan['segmentalLean']) || jsTruthy(scan['segmentalFat']));
  if (bias.isEmpty) {
    bias.add(hasSegmental
        ? '부위별 분석상 뚜렷한 약점 없음 → 균형 프로그램'
        : '부위별 분석은 아직 넣을 수 없습니다 → 지금은 균형 배분입니다');
  }

  List<Object?> pick(String group, int n) {
    final pool = (kExercises[group] as List?) ?? const <Object?>[];
    return pool.sublist(0, math.min(n, pool.length));
  }

  final setsPerMuscle = jsToNumber(tr['setsPerMuscle']);
  final difficulty = jsToNumber(p['difficulty']);
  final labels = (split['days'] as List).cast<String>();
  final sessions = <Map<String, Object?>>[];
  for (var i = 0; i < labels.length; i++) {
    final label = labels[i];
    if (label == '휴식') {
      sessions.add({'day': i, 'label': label, 'rest': true, 'exercises': <Object?>[]});
      continue;
    }
    List<List<Object>> groups;
    if (_reFullBody.hasMatch(label)) {
      groups = [['quads', 1], ['back', 1], ['chest', 1], ['shoulder', 1], ['core', 1]];
    } else if (_reUpper.hasMatch(label)) {
      groups = [['chest', 2], ['back', 2], ['shoulder', 1], ['arms', 2]];
    } else if (_reLower.hasMatch(label)) {
      groups = [['quads', 2], ['hamsGlutes', 2], ['core', 1]];
    } else if (_rePush.hasMatch(label)) {
      groups = [['chest', 2], ['shoulder', 2], ['arms', 1]];
    } else if (_rePull.hasMatch(label)) {
      groups = [['back', 3], ['arms', 1]];
    } else {
      groups = [['chest', 1], ['back', 1], ['quads', 1], ['core', 1]];
    }

    final ex = <Map<String, Object?>>[];
    for (final g in groups) {
      for (final item0 in pick(g[0] as String, g[1] as int)) {
        final item = (item0 as Map).cast<String, Object?>();
        final isCompound = _reCompound.hasMatch('${item['name']}');
        ex.add({
          'name': item['name'], 'equip': item['equip'], 'note': item['note'], 'group': g[0],
          'sets': isCompound ? (setsPerMuscle >= 16 ? 4 : 3) : 3,
          'reps': isCompound ? '5-8' : '10-15',
          'restSec': isCompound ? 150 : 75,
          'rpe': difficulty >= 3 ? '8-9' : (p['difficulty'] == 2 ? '7-8' : '6-8'),
        });
      }
    }
    sessions.add({
      'day': i, 'label': label, 'rest': false, 'exercises': ex, 'minutes': tr['sessionMin'],
    });
  }

  bias.addAll((tr['reason'] as List).cast<String>());

  final cardioMin = jsToNumber(tr['cardioMin']);
  return {
    'splitName': split['name'],
    'daysPerWeek': days,
    'sessionMinutes': tr['sessionMin'],
    'setsPerMuscle': tr['setsPerMuscle'],
    'cardioMinPerWeek': tr['cardioMin'],
    'cardioPlan': cardioMin >= 180
        ? 'Z2 저강도 40분 × 4회 + HIIT 15분 × 2회'
        : (cardioMin >= 120 ? 'Z2 저강도 45분 × 3회' : 'Z2 저강도 40분 × 2회'),
    'deloadEvery': p['deloadEvery'],
    'progression': '더블 프로그레션 — 목표 반복 상단에 도달하면 다음 세션에 중량 2.5~5kg 증가',
    'inbodyBias': bias,
    'hasSegmental': hasSegmental,
    'sessions': sessions,
  };
}

Map<String, Object?> dietFor(Map<String, Object?> macros, Map<String, Object?> profile) {
  final mpd = profile['mealsPerDay'];
  final meals = mpd == 2 ? 2 : (mpd == 4 ? 4 : 3);
  final names = meals == 2
      ? ['점심', '저녁']
      : (meals == 4 ? ['아침', '점심', '간식', '저녁'] : ['아침', '점심', '저녁']);
  final weights = meals == 2
      ? [0.5, 0.5]
      : (meals == 4 ? [0.25, 0.30, 0.15, 0.30] : [0.30, 0.35, 0.35]);

  List<Map<String, Object?>> byTag(String t) => [
        for (final x0 in kFoods)
          if (((x0 as Map)['tags'] as List).contains(t)) x0.cast<String, Object?>()
      ];
  final proteins = byTag('protein'), carbs = byTag('carb'),
      sides = byTag('side'), soups = byTag('soup');

  final mealPlan = <Map<String, Object?>>[];
  for (var i = 0; i < names.length; i++) {
    final kcal = jsRound(_f(macros, 'intakeKcal') * weights[i]);
    final protein = jsRound(_f(macros, 'proteinG') * weights[i]);
    final carb = jsRound(_f(macros, 'carbG') * weights[i]);
    final fat = jsRound(_f(macros, 'fatG') * weights[i]);
    final pf = proteins[i % proteins.length];
    final cf = carbs[i % carbs.length];
    final sf = sides[i % sides.length];
    final soup = soups[i % soups.length];
    /* `cf.c || 60` — 탄수 0 인 식품이 들어와도 0 으로 나누지 않게 하는 방어입니다. */
    final riceG = jsRound(carb / (jsTruthy(cf['c']) ? jsToNumber(cf['c']) : 60) * 100);
    final meatG = jsRound(protein / (jsTruthy(pf['p']) ? jsToNumber(pf['p']) : 20) * 100);
    mealPlan.add({
      'name': names[i], 'kcal': kcal, 'proteinG': protein, 'carbG': carb, 'fatG': fat,
      'options': [
        {
          'label': '한식 A',
          'items': [
            '${cf['name']} 약 ${_s(riceG)}g',
            '${pf['name']} ${_s(meatG)}g',
            '${soup['name']} (국물 남기기)',
            sf['name'],
          ],
        },
        {
          'label': '간편 B',
          'items': ['유청단백 1스쿱', '고구마 150g', '삶은계란 2개', '샐러드채소 100g'],
        },
      ],
    });
  }

  return {
    'mealsPerDay': meals,
    'meals': mealPlan,
    'proteinPerMeal': jsRound(_f(macros, 'proteinG') / meals),
    'hydrationL': 2.5,
    'eatingOut': kEatingOut,
    'notes': [
      '단백질은 끼니당 30~40g씩 고르게 나누는 편이 근단백 합성에 유리합니다.',
      '한식은 국·찌개의 나트륨이 높아 체중계 숫자를 며칠씩 흔듭니다. 국물은 남기세요.',
      '체중은 수분·나트륨 때문에 하루 ±1kg 흔들립니다. 하루 값이 아니라 주 평균으로 보세요.',
    ],
  };
}

/// 선택된 강도로 최종 플랜을 조립합니다.
Map<String, Object?>? buildPlan(Map<String, Object?> comparison, Object? level,
    Map<String, Object?>? scan, Map<String, Object?> profile) {
  Map<String, Object?>? r;
  for (final x0 in (comparison['results'] as List)) {
    final x = (x0 as Map).cast<String, Object?>();
    if (x['level'] == level) {
      r = x;
      break;
    }
  }
  if (r == null) return null;
  final sim = r['sim'] as Map<String, Object?>;
  final goal = (comparison['goal'] as Map).cast<String, Object?>();
  final macros = r['macros'] as Map<String, Object?>;
  return {
    'level': level,
    'mode': comparison['mode'],
    'goal': {
      'weightKg': goal['weightKg'],
      'smmKg': goal['smmKg'],
      'bfmKg': goal['bfmKg'],
      'modeId': goal.containsKey('modeId') && goal['modeId'] != null ? goal['modeId'] : null,
    },
    'label': r['label'],
    'title': r['title'],
    'weeks': r['weeks'],
    'targetDate': r['targetDate'],
    'startDate': comparison['startDate'],
    'strategy': sim['strategy'],
    'strategyLabel': sim['strategyLabel'],
    'strategyDesc': sim['strategyDesc'],
    'phases': sim['phases'],
    'trajectory': sim['trajectory'],
    'bottleneck': comparison['bottleneckNote'],
    'macros': macros,
    'workout': workoutFor(sim, (comparison['current'] as Map).cast<String, Object?>(),
        profile, scan, _mapOrNull(comparison['goalInfo'])),
    'diet': dietFor(macros, profile),
    'feasibility': r['feasibility'],
    'capWarning': r['capWarning'],
    'milestones': milestonesFrom(_traj(sim), comparison['startDate']),
  };
}

Map<String, Object?>? _mapOrNull(Object? x) =>
    x == null ? null : (x as Map).cast<String, Object?>();

List<Map<String, Object?>> milestonesFrom(List<Map<String, Object?>> traj, Object? startISO) {
  final out = <Map<String, Object?>>[];
  for (var i = 4; i < traj.length; i += 4) {
    final t = traj[i];
    out.add({
      'week': t['week'], 'date': addWeeks(startISO, jsToNumber(t['week'])),
      'weightKg': t['weightKg'], 'smmKg': t['smmKg'], 'bfmKg': t['bfmKg'], 'pbfPct': t['pbfPct'],
    });
  }
  final last = traj[traj.length - 1];
  if (out.isEmpty || out[out.length - 1]['week'] != last['week']) {
    out.add({
      'week': last['week'], 'date': addWeeks(startISO, jsToNumber(last['week'])),
      'weightKg': last['weightKg'], 'smmKg': last['smmKg'], 'bfmKg': last['bfmKg'],
      'pbfPct': last['pbfPct'], 'final': true,
    });
  } else {
    out[out.length - 1]['final'] = true;
  }
  return out;
}

/* --- 10. 식단 기록 / 체크인 ------------------------------------------------- */

/// 식단 달성률. **미기록일은 분모에서 뺍니다** — 0 으로 치환하면 평균이
/// 폭락하고, 그 값을 보고 칼로리를 더 깎으면 실제로 사람을 굶깁니다.
Map<String, Object?>? dietAdherence(List<Map<String, Object?>> days, Map<String, Object?>? target) {
  if (target == null) return null;
  final logged = days.where((d) => jsTruthy(d['logged'])).toList();
  final n = logged.length;
  final intake = _f(target, 'intakeKcal');
  final out = <String, Object?>{
    'totalDays': days.length, 'loggedDays': n, 'missedDays': days.length - n,
    'logRatePct': days.isNotEmpty ? jsRound(n / days.length * 100) : 0,
    'avg': null, 'pct': null, 'inBandDays': 0, 'proteinHitDays': 0, 'band': null,
  };
  /* 칼로리는 점이 아니라 밴드입니다. 2,400 목표에 2,500 먹고 빨간불이 켜지는
     앱은 없는 정밀도를 파는 것입니다. */
  final band = {'lo': jsRound(intake * 0.9), 'hi': jsRound(intake * 1.1)};
  out['band'] = band;
  if (n == 0) return out;

  var sumKcal = 0.0, sumP = 0.0, sumC = 0.0, sumF = 0.0;
  var inBand = 0, proteinHit = 0;
  final lo = jsToNumber(band['lo']), hi = jsToNumber(band['hi']);
  for (final d in logged) {
    /* `d.kcal || 0` — 없거나 0 이면 0. 문자열이 들어오면 그대로 쓰이고
       합계가 NaN 이 됩니다(원본과 같습니다). */
    final kcal = jsTruthy(d['kcal']) ? jsToNumber(d['kcal']) : 0;
    final p = jsTruthy(d['p']) ? jsToNumber(d['p']) : 0;
    sumKcal += kcal;
    sumP += p;
    sumC += jsTruthy(d['c']) ? jsToNumber(d['c']) : 0;
    sumF += jsTruthy(d['f']) ? jsToNumber(d['f']) : 0;
    if (kcal >= lo && kcal <= hi) inBand++;
    if (p >= _f(target, 'proteinG') * 0.9) proteinHit++;
  }
  out['inBandDays'] = inBand;
  out['proteinHitDays'] = proteinHit;
  final avg = {
    'kcal': jsRound(sumKcal / n),
    'p': jsRound(sumP / n * 10) / 10,
    'c': jsRound(sumC / n * 10) / 10,
    'f': jsRound(sumF / n * 10) / 10,
  };
  out['avg'] = avg;
  out['pct'] = {
    'kcal': jsRound(jsToNumber(avg['kcal']) / intake * 100),
    'p': jsRound(jsToNumber(avg['p']) / _f(target, 'proteinG') * 100),
    'c': jsTruthy(target['carbG']) ? jsRound(jsToNumber(avg['c']) / _f(target, 'carbG') * 100) : null,
    'f': jsTruthy(target['fatG']) ? jsRound(jsToNumber(avg['f']) / _f(target, 'fatG') * 100) : null,
  };
  out['inBandPct'] = jsRound(inBand / n * 100);
  out['proteinHitPct'] = jsRound(proteinHit / n * 100);
  return out;
}

/// 오늘 상태에 대한 한 줄. **명령이 아니라 상태 보고**입니다 —
/// "그만 드세요" 는 앱이 내리는 지시이고, "다 채웠습니다" 는 정보입니다.
///
/// [now] 는 시험을 위해 시계를 고정할 때만 씁니다 (원본은 `new Date()`).
Map<String, Object?>? dietNudge(Map<String, Object?> today, Map<String, Object?>? target,
    {DateTime? now}) {
  if (target == null) return null;
  final kcal = jsTruthy(today['kcal']) ? jsToNumber(today['kcal']) : 0;
  final p = jsTruthy(today['p']) ? jsToNumber(today['p']) : 0;
  final intake = _f(target, 'intakeKcal');
  final proteinG = _f(target, 'proteinG');
  final remainKcal = intake - kcal;
  final remainP = math.max(0.0, proteinG - p);
  final bandLo = intake * 0.9, bandHi = intake * 1.1;
  final hour = (now ?? DateTime.now()).toLocal().hour;

  if (!jsTruthy(today['logged'])) {
    return {'kind': 'none', 'tone': '', 'text': '오늘은 아직 기록이 없습니다.',
            'detail': '한 끼만 적어도 주 평균이 살아납니다.'};
  }
  if (remainP > 25 && hour >= 19) {
    return {'kind': 'protein', 'tone': 'warn',
            'text': '단백질이 ${_s(jsRound(remainP))}g 남았습니다.',
            'detail': '닭가슴살 한 팩이 약 23g, 계란 두 개가 약 12g입니다.'};
  }
  if (kcal > bandHi) {
    return {'kind': 'over', 'tone': 'warn',
            'text': '오늘 목표 범위를 넘었습니다 (${_s(jsRound(kcal))} / ${_s(jsRound(intake))}kcal).',
            'detail': '하루로 계획이 무너지지 않습니다. 내일 목표대로 돌아오면 주 평균은 유지됩니다.'};
  }
  if (kcal >= bandLo && kcal <= bandHi && remainP <= 10) {
    return {'kind': 'done', 'tone': 'ok', 'text': '오늘 목표치를 다 채웠습니다.',
            'detail': '칼로리도 단백질도 범위 안입니다.'};
  }
  if (remainP > 25) {
    return {'kind': 'protein', 'tone': '',
            'text': '단백질이 ${_s(jsRound(remainP))}g 남았습니다.',
            'detail': '남은 끼니에 단백질 반찬을 하나 더 넣으면 채워집니다.'};
  }
  return {
    'kind': 'ok', 'tone': '',
    'text': remainKcal > 0 ? '${_s(jsRound(remainKcal))}kcal 남았습니다.' : '목표 범위 안입니다.',
    'detail': '단백질 ${_s(jsRound(p))} / ${_s(target['proteinG'])}g',
  };
}

/// 주간 체크인 → 재조정 제안
Map<String, Object?> checkinAdvice(Map<String, Object?>? plan, Map<String, Object?> expected,
    Map<String, Object?> actual, Map<String, Object?>? adherence) {
  final dExp = _f(expected, 'weightKg') - _f(actual, 'weightKg');
  final dAct = _f(expected, 'prevWeightKg') - _f(actual, 'weightKg');
  final gap = dAct - dExp;
  final suggestions = <Map<String, Object?>>[];

  if (adherence != null && _lt(adherence['dietPct'], 70)) {
    suggestions.add({
      'kind': 'adherence', 'title': '칼로리는 그대로 두고 순응도부터',
      'detail': '식단 준수도가 ${_s(adherence['dietPct'])}%입니다. 계획이 틀린 게 아니라 실행이 덜 된 '
          '상태라 칼로리를 더 줄이면 역효과입니다.',
    });
    return {'status': 'adherence', 'suggestions': suggestions};
  }
  if (gap.abs() < 0.15) {
    suggestions.add({'kind': 'hold', 'title': '계획 유지', 'detail': '예상 범위 안입니다. 바꾸지 마세요.'});
    return {'status': 'onTrack', 'suggestions': suggestions};
  }
  if (gap < -0.15) {  // 덜 빠짐
    suggestions.add({'kind': 'kcal', 'title': '하루 150kcal 줄이기', 'detail': '2주 연속 정체일 때만 적용하세요.'});
    suggestions.add({'kind': 'cardio', 'title': '유산소 주 1회 추가', 'detail': '칼로리를 더 줄이는 것보다 근육 보존에 유리합니다.'});
    return {'status': 'slow', 'suggestions': suggestions};
  }
  suggestions.add({'kind': 'kcal', 'title': '하루 150kcal 늘리기', 'detail': '너무 빠르면 근손실 위험이 올라갑니다.'});
  return {'status': 'fast', 'suggestions': suggestions};
}

/// JS 의 `a < b` — 한쪽이 없으면 false.
bool _lt(Object? a, num b) => a is num && a < b;
