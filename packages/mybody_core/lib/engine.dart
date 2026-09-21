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

/// 측정 노이즈 바닥. 원본은 window.MB_MODES.NOISE 를 읽습니다.
class EngineNoise {
  final double weight, smm, bfm;
  const EngineNoise({this.weight = 1.0, this.smm = 0.6, this.bfm = 1.0});
}

EngineNoise _noise = const EngineNoise();
set engineNoise(EngineNoise n) => _noise = n;

Map<String, Object?> classifyGoal(Map<String, Object?> cur, Map<String, Object?> goal) {
  final dW = _f(goal, 'weightKg') - _f(cur, 'weightKg');
  final dSMM = _f(goal, 'smmKg') - _f(cur, 'smmKg');
  final dBFM = _f(goal, 'bfmKg') - _f(cur, 'bfmKg');

  final impliedFfm = _f(goal, 'smmKg') / _f(cur, 'smmToFfm');
  final impliedWeight = impliedFfm + _f(goal, 'bfmKg');
  final mismatchKg = _f(goal, 'weightKg') - impliedWeight;

  final nf = _noise;
  final wantsFatLoss = dBFM < -nf.bfm;
  final wantsFatGain = dBFM > nf.bfm;
  final wantsMuscle = dSMM > nf.smm;
  final losesMuscle = dSMM < -nf.smm;

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
    'noise': {'weight': nf.weight, 'smm': nf.smm, 'bfm': nf.bfm},
    'subNoise': {
      'weight': dW.abs() < nf.weight,
      'smm': dSMM.abs() < nf.smm,
      'bfm': dBFM.abs() < nf.bfm,
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
