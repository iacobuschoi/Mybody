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
