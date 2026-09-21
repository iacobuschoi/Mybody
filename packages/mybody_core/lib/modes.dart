/* =============================================================================
 * modes.dart — 몸만들기 모드 선택 (prototype/js/modes.js 의 이식)
 *
 * 이 파일이 하는 일은 하나입니다: 사용자가 넣은 현재 몸과 목표를 보고
 * **계획을 만들어도 되는지**, 만든다면 **어느 모드인지**를 고릅니다.
 * 거부가 먼저이고 선택이 나중입니다 — 순서가 곧 심각도입니다.
 *
 * 산문(모드 설명·거부 문구·선택 이유)은 modes_data.dart 에 찍혀 있습니다.
 * 여기에는 **판정식**만 있습니다. 판정식 하나하나 위에 원문(source)을
 * 그대로 붙여 두었습니다 — 옮긴 것과 원문을 나란히 못 보면 맞는지 볼
 * 방법이 없습니다.
 *
 * 자바스크립트라서 조심한 것들 (여기서는 특히 많습니다):
 *
 *   · `age < 19` 에서 age 가 **없으면** false(NaN 비교), **null 이면**
 *     `0 < 19` 이라 true 입니다. 안전 게이트가 이 차이로 뒤집힙니다.
 *     그래서 전부 jsNum(키가 없으면 NaN, null 이면 0) 으로 읽습니다.
 *   · `deadlineWeeks !== null` 은 **undefined 일 때 참**입니다.
 *     `=== null` 과 `!= null` 을 헷갈리면 마감 없는 사용자가 마감 규칙에
 *     걸립니다.
 *   · `recentTrend !== null && recentTrend.weeksSpan >= 8` 에서
 *     recentTrend 가 undefined 면 첫 비교는 통과하고 다음 줄에서
 *     **TypeError 가 납니다.** 원본은 거부 규칙에서 예외를 '걸림' 으로,
 *     선택 규칙에서는 '안 걸림' 으로 처리합니다. 그 동작까지 옮깁니다 —
 *     누락된 입력이 가드를 약화시키는 쪽으로만 작동하면 안 되니까요.
 * ========================================================================== */
library;

import 'dart:math' as math;
import 'engine.dart' as engine;
import 'js_num.dart';
import 'modes_data.dart';

export 'modes_data.dart';

Map<String, Object?>? byId(Object? id) {
  for (final m0 in kModes) {
    final m = (m0 as Map).cast<String, Object?>();
    if (m['id'] == id) return m;
  }
  return null;
}

/* --- 한국어 조사 교정 -------------------------------------------------------
 * 치환한 자리 **바로 뒤**에 붙은 조사만 손댑니다. 본문 전체를 훑으면
 * '증가' 같은 단어의 끝 글자를 조사로 오인합니다.
 * -------------------------------------------------------------------------- */

const Map<String, List<String>> _josa = {
  '이라서': ['이라서', '라서'], '라서': ['이라서', '라서'],
  '은': ['은', '는'], '는': ['은', '는'],
  '이': ['이', '가'], '가': ['이', '가'],
  '을': ['을', '를'], '를': ['을', '를'],
  '과': ['과', '와'], '와': ['과', '와'],
  '으로': ['으로', '로'], '로': ['으로', '로'],
};

final RegExp _endsDigit = RegExp(r'[0-9]$');
final RegExp _endsConsonantDigit = RegExp(r'[0136780]$');

bool hasFinalConsonant(String s) {
  if (s.isEmpty) return false;
  final c = s.codeUnitAt(s.length - 1);
  if (c < 0xAC00 || c > 0xD7A3) {
    return _endsDigit.hasMatch(s) ? _endsConsonantDigit.hasMatch(s) : true;
  }
  return (c - 0xAC00) % 28 != 0;
}

final RegExp _slot = RegExp(r'\{(\w+)\}(이라서|라서|으로|로|은|는|이|가|을|를|과|와)?');

/// `{weeksSpan}주` 같은 자리를 채웁니다. 값이 없으면 '—'.
String fill(Object? tpl, Map<String, Object?> i) {
  return '$tpl'.replaceAllMapped(_slot, (m) {
    final k = m.group(1)!;
    final josa = m.group(2);
    final v = i[k];
    /* `v == null` 은 undefined 와 null 을 둘 다 잡습니다 (원본의 `v == null`). */
    final s = v == null
        ? '—'
        : (v is num ? jsNumToString(jsRound(v * 10) / 10) : '$v');
    if (josa == null) return s;
    final pair = _josa[josa];
    return s + (pair != null ? pair[hasFinalConsonant(s) ? 0 : 1] : josa);
  });
}

/// ★ 뒤는 구현 노트라 화면에 내보내지 않습니다.
String forDisplay(Object? text) {
  if (!jsTruthy(text)) return '';
  final cut = '$text'.split('★')[0];
  return cut.replaceAll(RegExp(r'\n{2,}'), '\n').trim();
}

/* --- 판정식이 읽는 값들 ------------------------------------------------------
 * `i` 는 select() 가 만든 파생값 꾸러미입니다. 아래 도우미는 전부
 * 자바스크립트가 그 값을 읽는 방식 그대로입니다.
 * -------------------------------------------------------------------------- */

class _I {
  final Map<String, Object?> m;
  _I(this.m);

  /// 숫자로. **키가 없으면 NaN, 값이 null 이면 0** — JS 의 산술 강제입니다.
  double n(String k) => jsNum(m, k);

  /// JS 의 `x === null` — undefined 는 **거짓**입니다.
  bool isNull(String k) => m.containsKey(k) && m[k] == null;

  /// JS 의 `x !== null` — undefined 는 **참**입니다.
  bool notNull(String k) => !isNull(k);

  bool truthy(String k) => jsTruthy(m[k]);
  Object? raw(String k) => m[k];

  /// `recentTrend.weeksSpan` — 없는 것의 속성을 읽으면 JS 는 던집니다.
  /// 그 예외가 거부/선택에서 서로 다르게 처리되므로 그대로 던집니다.
  double rt(String k) {
    if (!m.containsKey('recentTrend')) {
      throw StateError("Cannot read properties of undefined (reading '$k')");
    }
    final v = m['recentTrend'];
    if (v == null) throw StateError("Cannot read properties of null (reading '$k')");
    return jsNum((v as Map).cast<String, Object?>(), k);
  }
}

double get _nWeight => jsToNumber(kNoise['weight']);
double get _nSmm => jsToNumber(kNoise['smm']);
double get _nBfm => jsToNumber(kNoise['bfm']);

const List<String> _required = [
  'curWeightKg', 'curSmmKg', 'curBfmKg', 'heightCm', 'age',
  'dWeightKg', 'dSmmKg', 'dBfmKg'
];

const Map<String, String> _label = {
  'curWeightKg': '현재 체중', 'curSmmKg': '현재 골격근량', 'curBfmKg': '현재 체지방량',
  'heightCm': '키', 'age': '나이', 'dWeightKg': '체중 목표',
  'dSmmKg': '근육 목표', 'dBfmKg': '지방 목표', 'sex': '성별',
};

/* --- 거부 규칙 10개 ---------------------------------------------------------
 * 각 항목 위의 주석이 modes.js 안의 판정식 **원문**입니다.
 * -------------------------------------------------------------------------- */

final List<bool Function(_I)> refusalTests = [
  // ['curWeightKg',…].some(f => input[f] == null || !isFinite(input[f])) || (sex !== 'male' && sex !== 'female')
  (i) {
    final input = (i.raw('input') as Map).cast<String, Object?>();
    final missing = _required.any((f) {
      final v = input[f];
      return v == null || !(v is num && v.isFinite);
    });
    return missing || (i.raw('sex') != 'male' && i.raw('sex') != 'female');
  },

  // age < 19 && (dWeightKg < -NOISE.weight || dBfmKg < -NOISE.bfm)
  (i) => i.n('age') < 19 &&
      (i.n('dWeightKg') < -_nWeight || i.n('dBfmKg') < -_nBfm),

  // (sex === 'male' ? (curPbfPct < 15 && targetPbfPct < 10) : (curPbfPct < 23 && targetPbfPct < 18))
  //   && dWeightKg < -0.05 * curWeightKg
  (i) => (i.raw('sex') == 'male'
          ? (i.n('curPbfPct') < 15 && i.n('targetPbfPct') < 10)
          : (i.n('curPbfPct') < 23 && i.n('targetPbfPct') < 18)) &&
      i.n('dWeightKg') < -0.05 * i.n('curWeightKg'),

  // targetPbfPct < (sex === 'male' ? 8 : 15)
  (i) => i.n('targetPbfPct') < (i.raw('sex') == 'male' ? 8 : 15),

  // curBmi < 18.5 || targetBmi < 18.5
  (i) => i.n('curBmi') < 18.5 || i.n('targetBmi') < 18.5,

  // Math.abs(dWeightKg - (dBfmKg + dSmmKg / k)) > 1.5
  (i) => (i.n('dWeightKg') - (i.n('dBfmKg') + i.n('dSmmKg') / i.n('k'))).abs() > 1.5,

  // dBfmKg >= NOISE.bfm && dSmmKg <= -NOISE.smm
  (i) => i.n('dBfmKg') >= _nBfm && i.n('dSmmKg') <= -_nSmm,

  // dBfmKg >= NOISE.bfm && Math.abs(dSmmKg) <= NOISE.smm
  (i) => i.n('dBfmKg') >= _nBfm && i.n('dSmmKg').abs() <= _nSmm,

  // deadlineWeeks !== null && deadlineWeeks > 0 && (Math.abs(dWeightKg) / curWeightKg) / deadlineWeeks > 0.015
  (i) => i.notNull('deadlineWeeks') &&
      i.n('deadlineWeeks') > 0 &&
      (i.n('dWeightKg').abs() / i.n('curWeightKg')) / i.n('deadlineWeeks') > 0.015,

  // deadlineWeeks !== null && deadlineWeeks < 4
  (i) => i.notNull('deadlineWeeks') && i.n('deadlineWeeks') < 4,
];

/* --- 선택 규칙 23개 --------------------------------------------------------- */

final List<bool Function(_I)> ruleTests = [
  // recentTrend !== null && recentTrend.weeksSpan >= 8 && (recentTrend.dWeightKg / curWeightKg) <= -0.06
  //   && dWeightKg > -NOISE.weight && dBfmKg > -NOISE.bfm && smmFlat
  (i) => i.notNull('recentTrend') &&
      i.rt('weeksSpan') >= 8 &&
      (i.rt('dWeightKg') / i.n('curWeightKg')) <= -0.06 &&
      i.n('dWeightKg') > -_nWeight &&
      i.n('dBfmKg') > -_nBfm &&
      i.truthy('smmFlat'),

  // subNoiseAll && dSmmKg > 0 && dBfmKg < 0
  (i) => i.truthy('subNoiseAll') && i.n('dSmmKg') > 0 && i.n('dBfmKg') < 0,

  // subNoiseAll
  (i) => i.truthy('subNoiseAll'),

  // currentPhase === 'bulk' && dBfmKg < -NOISE.bfm && !smmDown && Math.abs(dBfmKg) <= 0.04 * curWeightKg
  //   && curPbfPct >= (sex === 'male' ? 18 : 26) && taExp && age >= 19
  (i) => i.raw('currentPhase') == 'bulk' &&
      i.n('dBfmKg') < -_nBfm &&
      !i.truthy('smmDown') &&
      i.n('dBfmKg').abs() <= 0.04 * i.n('curWeightKg') &&
      i.n('curPbfPct') >= (i.raw('sex') == 'male' ? 18 : 26) &&
      i.truthy('taExp') &&
      i.n('age') >= 19,

  // deadlineWeeks !== null && deadlineWeeks <= 6 && dBfmKg < -NOISE.bfm && !smmDown
  //   && (smmFlat || dFfmKg < 0.5 * Math.abs(dBfmKg)) && Math.abs(dBfmKg) <= 0.04 * curWeightKg
  //   && curPbfPct >= (sex === 'male' ? 13 : 21) && taExp && age >= 19
  (i) => i.notNull('deadlineWeeks') &&
      i.n('deadlineWeeks') <= 6 &&
      i.n('dBfmKg') < -_nBfm &&
      !i.truthy('smmDown') &&
      (i.truthy('smmFlat') || i.n('dFfmKg') < 0.5 * i.n('dBfmKg').abs()) &&
      i.n('dBfmKg').abs() <= 0.04 * i.n('curWeightKg') &&
      i.n('curPbfPct') >= (i.raw('sex') == 'male' ? 13 : 21) &&
      i.truthy('taExp') &&
      i.n('age') >= 19,

  // dBfmKg < -NOISE.bfm && !smmDown && (smmFlat || dFfmKg < 0.5 * Math.abs(dBfmKg))
  //   && curPbfPct <= (sex === 'male' ? 18 : 26) && taExp && age >= 19
  (i) => i.n('dBfmKg') < -_nBfm &&
      !i.truthy('smmDown') &&
      (i.truthy('smmFlat') || i.n('dFfmKg') < 0.5 * i.n('dBfmKg').abs()) &&
      i.n('curPbfPct') <= (i.raw('sex') == 'male' ? 18 : 26) &&
      i.truthy('taExp') &&
      i.n('age') >= 19,

  // dBfmKg < -NOISE.bfm && !smmDown && curPbfPct < (sex === 'male' ? 15 : 23) && age >= 19
  (i) => i.n('dBfmKg') < -_nBfm &&
      !i.truthy('smmDown') &&
      i.n('curPbfPct') < (i.raw('sex') == 'male' ? 15 : 23) &&
      i.n('age') >= 19,

  // deadlineWeeks !== null && dBfmKg < -NOISE.bfm && (Math.abs(dWeightKg) / curWeightKg) / deadlineWeeks > 0.009
  (i) => i.notNull('deadlineWeeks') &&
      i.n('dBfmKg') < -_nBfm &&
      (i.n('dWeightKg').abs() / i.n('curWeightKg')) / i.n('deadlineWeeks') > 0.009,

  // dBfmKg < -NOISE.bfm && smmKnown && dSmmKg >= 1.5 * NOISE.smm
  //   && Math.abs(dBfmKg) <= Math.max(6.5, 0.085 * curWeightKg)
  //   && curPbfPct >= (sex === 'male' ? 14.5 : 22.5) && currentPhase !== 'bulk'
  //   && (deadlineWeeks === null || deadlineWeeks >= 16)
  //   && (trainingAge === 'novice' || hadPriorPeak === true
  //        || (trainingAge === 'intermediate' && curPbfPct >= (sex === 'male' ? 22 : 30)))
  /* 마지막 괄호는 'intermediate' **한 값만** 봅니다 — taExp(숙련 화이트리스트)가
     아닙니다. advanced·elite 는 여기서 리컴프로 들어오지 않습니다.
     그리고 `hadPriorPeak === true` 는 엄격 비교라 1 이나 'yes' 는 안 통합니다. */
  (i) => i.n('dBfmKg') < -_nBfm &&
      i.truthy('smmKnown') &&
      i.n('dSmmKg') >= 1.5 * _nSmm &&
      i.n('dBfmKg').abs() <= math.max(6.5, 0.085 * i.n('curWeightKg')) &&
      i.n('curPbfPct') >= (i.raw('sex') == 'male' ? 14.5 : 22.5) &&
      i.raw('currentPhase') != 'bulk' &&
      (i.isNull('deadlineWeeks') || i.n('deadlineWeeks') >= 16) &&
      (i.raw('trainingAge') == 'novice' ||
          i.raw('hadPriorPeak') == true ||
          (i.raw('trainingAge') == 'intermediate' &&
              i.n('curPbfPct') >= (i.raw('sex') == 'male' ? 22 : 30))),

  // dBfmKg < -NOISE.bfm && smmUp && dFfmKg > Math.abs(dBfmKg)
  (i) => i.n('dBfmKg') < -_nBfm && i.truthy('smmUp') && i.n('dFfmKg') > i.n('dBfmKg').abs(),

  // dBfmKg < -NOISE.bfm && smmUp
  (i) => i.n('dBfmKg') < -_nBfm && i.truthy('smmUp'),

  // dBfmKg < -NOISE.bfm && !smmDown && trainingAge === 'novice' && curPbfPct >= (sex === 'male' ? 25 : 32)
  (i) => i.n('dBfmKg') < -_nBfm &&
      !i.truthy('smmDown') &&
      i.raw('trainingAge') == 'novice' &&
      i.n('curPbfPct') >= (i.raw('sex') == 'male' ? 25 : 32),

  // dBfmKg < -NOISE.bfm && smmDown
  (i) => i.n('dBfmKg') < -_nBfm && i.truthy('smmDown'),

  // dBfmKg < -NOISE.bfm
  (i) => i.n('dBfmKg') < -_nBfm,

  // currentPhase === 'bulk' && smmUp && dBfmKg >= -NOISE.bfm && curPbfPct > (sex === 'male' ? 18 : 26)
  //   && taExp && age >= 19
  (i) => i.raw('currentPhase') == 'bulk' &&
      i.truthy('smmUp') &&
      i.n('dBfmKg') >= -_nBfm &&
      i.n('curPbfPct') > (i.raw('sex') == 'male' ? 18 : 26) &&
      i.truthy('taExp') &&
      i.n('age') >= 19,

  // smmUp && dBfmKg >= -NOISE.bfm && curPbfPct <= (sex === 'male' ? 18 : 26) && dWeightKg > 0
  //   && (dFfmKg / dWeightKg) > 0.75
  (i) => i.truthy('smmUp') &&
      i.n('dBfmKg') >= -_nBfm &&
      i.n('curPbfPct') <= (i.raw('sex') == 'male' ? 18 : 26) &&
      i.n('dWeightKg') > 0 &&
      (i.n('dFfmKg') / i.n('dWeightKg')) > 0.75,

  // smmUp && dBfmKg >= -NOISE.bfm && curPbfPct <= (sex === 'male' ? 18 : 26)
  //   && dBfmKg <= Math.max(NOISE.bfm, dFfmKg / 3)
  (i) => i.truthy('smmUp') &&
      i.n('dBfmKg') >= -_nBfm &&
      i.n('curPbfPct') <= (i.raw('sex') == 'male' ? 18 : 26) &&
      i.n('dBfmKg') <= math.max(_nBfm, i.n('dFfmKg') / 3),

  // smmUp && dBfmKg >= -NOISE.bfm && curPbfPct <= (sex === 'male' ? 18 : 26)
  (i) => i.truthy('smmUp') &&
      i.n('dBfmKg') >= -_nBfm &&
      i.n('curPbfPct') <= (i.raw('sex') == 'male' ? 18 : 26),

  // smmUp && dBfmKg >= -NOISE.bfm && curPbfPct > (sex === 'male' ? 18 : 26) && currentPhase !== 'bulk'
  (i) => i.truthy('smmUp') &&
      i.n('dBfmKg') >= -_nBfm &&
      i.n('curPbfPct') > (i.raw('sex') == 'male' ? 18 : 26) &&
      i.raw('currentPhase') != 'bulk',

  // dWeightKg > NOISE.weight && smmFlat && curBmi < 20
  (i) => i.n('dWeightKg') > _nWeight && i.truthy('smmFlat') && i.n('curBmi') < 20,

  // dWeightKg < -NOISE.weight
  (i) => i.n('dWeightKg') < -_nWeight,

  // dWeightKg > NOISE.weight && curPbfPct <= (sex === 'male' ? 18 : 26)
  (i) => i.n('dWeightKg') > _nWeight &&
      i.n('curPbfPct') <= (i.raw('sex') == 'male' ? 18 : 26),

  // true
  (i) => true,
];

/* --- 선택 --------------------------------------------------------------------
 *
 * 입력에서 모드를 고릅니다. 거부가 먼저이고, 거부 배열의 순서가 곧
 * 심각도입니다(안전 > 산술 정합성 > 일정).
 * -------------------------------------------------------------------------- */

Map<String, Object?> select(Map<String, Object?> input) {
  final i = <String, Object?>{...input};
  i['NOISE'] = kNoise;

  double n(String k) => jsNum(i, k);
  /* `x || 0` — 없거나 null 이거나 0 이면 0. 문자열이면 그대로 쓰여 NaN 이 됩니다. */
  double or0(String k) => jsTruthy(i[k]) ? jsToNumber(i[k]) : 0;

  if (i['targetPbfPct'] == null && i['curBfmKg'] != null && i['curWeightKg'] != null) {
    i['targetPbfPct'] = (n('curBfmKg') + or0('dBfmKg')) / (n('curWeightKg') + or0('dWeightKg')) * 100;
  }
  // 규칙이 쓰는 파생값 — 여기서 한 번만 계산합니다.
  final Object? ffm = (i['curWeightKg'] != null && i['curBfmKg'] != null)
      ? (n('curWeightKg') - n('curBfmKg'))
      : null;
  i['k'] = (ffm != null && jsTruthy(ffm) && (ffm as double) > 0 && i['curSmmKg'] != null)
      ? (n('curSmmKg') / ffm)
      : 0.57;
  i['dFfmKg'] = or0('dSmmKg') / n('k');
  if (i['targetPbfPct'] == null && i['curBfmKg'] != null && i['curWeightKg'] != null) {
    i['targetPbfPct'] = (n('curBfmKg') + or0('dBfmKg')) / (n('curWeightKg') + or0('dWeightKg')) * 100;
  }
  if (i['targetBmi'] == null && jsTruthy(i['heightCm'])) {
    i['targetBmi'] = (n('curWeightKg') + or0('dWeightKg')) / math.pow(n('heightCm') / 100, 2);
  }
  i['smmKnown'] = i['dSmmKg'] != null && (i['dSmmKg'] is num) && (i['dSmmKg'] as num).isFinite;
  i['smmUp'] = i['smmKnown'] == true && n('dSmmKg') > _nSmm;
  i['smmDown'] = i['smmKnown'] == true && n('dSmmKg') < -_nSmm;
  /* 미지를 "변화 없음" 으로 봅니다. smmKnown 을 곱하면 미지일 때 세 플래그가
     모두 false 가 되어 어떤 규칙에도 안 걸립니다 — 전수 분할이 깨집니다. */
  i['smmFlat'] = i['smmKnown'] != true || n('dSmmKg').abs() <= _nSmm;
  i['subNoiseAll'] = or0('dWeightKg').abs() < _nWeight &&
      or0('dSmmKg').abs() < _nSmm &&
      or0('dBfmKg').abs() < _nBfm;
  /* 화이트리스트입니다. 예전엔 `!== 'novice'` 라 값이 없거나 오타면 숙련자
     게이트가 열렸습니다 — 누락된 입력이 가드를 약화시키는 쪽으로만 작동했습니다. */
  i['taExp'] = const ['intermediate', 'advanced', 'elite'].contains(i['trainingAge']);
  if (!i.containsKey('currentPhase')) i['currentPhase'] = null;
  i['input'] = i;

  /* 거부 문구가 이름으로 요구하는 파생값들. 없으면 fill() 이 '—' 를 찍습니다.
     실제로 이런 문장이 나갔습니다: "필요한 값이 빠져 있습니다: —." */
  final miss = <String>[];
  for (final f in _required) {
    final v = i[f];
    if (v == null || !(v is num && v.isFinite)) miss.add(_label[f] ?? f);
  }
  if (i['sex'] != 'male' && i['sex'] != 'female') miss.add(_label['sex']!);
  i['missingFields'] = miss.isNotEmpty ? miss.join(', ') : '없음';

  i['absDSmmKg'] = or0('dSmmKg').abs();
  i['absDBfmKg'] = or0('dBfmKg').abs();
  // 근육·지방 목표가 함의하는 체중 변화
  i['impliedDWeightKg'] =
      or0('dBfmKg') + (i['dFfmKg'] != null ? n('dFfmKg') : or0('dSmmKg') / 0.55);
  i['impliedWeightKg'] = or0('curWeightKg') + n('impliedDWeightKg');

  i['ratePct'] = (jsTruthy(i['deadlineWeeks']) && jsTruthy(i['curWeightKg']))
      ? n('dWeightKg').abs() / n('curWeightKg') / n('deadlineWeeks') * 100
      : null;
  i['targetPbf'] = i['targetPbfPct'];
  // 문구 치환용 파생값
  i['ffmKg'] = or0('dSmmKg') * 1.75;
  i['fatKg'] = or0('dBfmKg').abs();
  i['weeksSpan'] = jsTruthy(i['recentTrend'])
      ? (i['recentTrend'] as Map)['weeksSpan']
      : null;
  i['pct'] = (jsTruthy(i['recentTrend']) && jsTruthy(i['curWeightKg']))
      ? (jsToNumber((i['recentTrend'] as Map)['dWeightKg']) / n('curWeightKg') * 100).abs()
      : null;

  final maleGate = i['sex'] == 'male';
  i['cuttingGate'] = maleGate ? 18 : 26;
  i['bulkGate'] = maleGate ? 18 : 26;
  i['recompFatCapKg'] = jsRound(math.max(6.5, 0.085 * or0('curWeightKg')) * 10) / 10;
  i['fatCapKcal'] = jsRound(31 * or0('curBfmKg'));
  i['targetWeightKg'] = jsRound((or0('curWeightKg') + or0('dWeightKg')) * 10) / 10;
  i['targetBfmKg'] = jsRound((or0('curBfmKg') + or0('dBfmKg')) * 10) / 10;
  i['targetSmmKg'] = jsRound((or0('curSmmKg') + or0('dSmmKg')) * 10) / 10;
  i['bulkFatCapKg'] = jsRound(math.max(_nBfm, n('dFfmKg') / 3) * 10) / 10;
  // 증량으로 근육 목표를 채울 때 따라붙는 체중·지방 (제지방 비율 0.6 가정)
  i['cleanBulkWeightKg'] = n('dFfmKg') > 0 ? jsRound(n('dFfmKg') / 0.6 * 10) / 10 : 0;
  i['cleanBulkFatKg'] =
      n('dFfmKg') > 0 ? jsRound((n('cleanBulkWeightKg') - n('dFfmKg')) * 10) / 10 : 0;

  // 근성장 속도 — 엔진과 **같은 모델**을 씁니다.
  double? monthly;
  if (jsTruthy(i['curWeightKg'])) {
    monthly = engine.baseSmmRatePerWeek(n('curWeightKg'), {
          'trainingAge': i['trainingAge'],
          'sex': i['sex'],
          'age': i['age'],
          'hadPriorPeak': i['hadPriorPeak'],
        }, n('k'), null) *
        4.345;
  }
  if (monthly != null && jsTruthy(monthly) && monthly > 0) {
    i['expectedMonthlySmmKg'] = jsRound(monthly * 100) / 100;
    i['smmVisibleMonths'] = (_nSmm / monthly).ceilToDouble();
    i['bulkWeeks'] = n('dSmmKg') > 0 ? (n('dSmmKg') / (monthly / 4.345)).ceilToDouble() : 0;
  } else {
    i['expectedMonthlySmmKg'] = null;
    i['smmVisibleMonths'] = null;
    i['bulkWeeks'] = null;
  }

  // 완만한 적자(TDEE 15%)로 갈 때와 공격적으로 갈 때의 도착 차이 (주)
  if (jsTruthy(i['tdeeKcal']) && n('dBfmKg') < 0) {
    final mild = 0.15 * n('tdeeKcal') * 7 / 7700;
    final hard = 0.25 * n('tdeeKcal') * 7 / 7700;
    i['mildDeficitKcal'] = jsRound(0.15 * n('tdeeKcal'));
    i['etaDiffWeeks'] =
        math.max(0, jsRound(n('dBfmKg').abs() / mild - n('dBfmKg').abs() / hard));
  } else {
    i['mildDeficitKcal'] = null;
    i['etaDiffWeeks'] = null;
  }

  i['reason'] = jsTruthy(i['hadPriorPeak'])
      ? '쉬었다 복귀한 경우'
      : (i['trainingAge'] == 'novice'
          ? '운동 입문 단계'
          : (n('curPbfPct') >= (i['sex'] == 'male' ? 18 : 26)
              ? '체지방이 아직 남아 있는 상태'
              : '지금 구간'));

  /* 시간 게이트: 간격이 4주 미만인 추세는 판정에 쓰지 않습니다 —
     수분·측정 시각 변동이 신호를 덮습니다. */
  Object? trendNote;
  if (jsTruthy(i['recentTrend'])) {
    final tr = (i['recentTrend'] as Map).cast<String, Object?>();
    if (tr['weeksSpan'] != null && jsNum(tr, 'weeksSpan') < 4) {
      trendNote = '최근 두 측정 간격이 ${jsNumToString(jsRound(jsNum(tr, 'weeksSpan') * 7))}'
          '일이라 추세로 쓰지 않았습니다. 변화 판정은 4주 이상 간격이 필요합니다.';
      i['recentTrend'] = null;
    }
  }

  final wrapped = _I(i);
  for (var r = 0; r < refusalTests.length; r++) {
    /* 예외를 '해당 없음' 으로 삼키면 누락된 입력이 언제나 가드를 약화시키는
       쪽으로만 작동합니다. **안전 거부에서는 예외를 '걸림' 으로 봅니다.** */
    bool hit;
    try {
      hit = refusalTests[r](wrapped);
    } catch (_) {
      hit = true;
    }
    if (hit) {
      final ref = (kRefusals[r] as Map).cast<String, Object?>();
      return {
        'refused': true, 'message': fill(ref['message'], i),
        'mode': null, 'trendNote': trendNote,
      };
    }
  }

  for (var idx = 0; idx < ruleTests.length; idx++) {
    // 선택 규칙은 반대입니다 — 평가 실패한 규칙은 고르지 않습니다.
    bool ok;
    try {
      ok = ruleTests[idx](wrapped);
    } catch (_) {
      ok = false;
    }
    if (ok) {
      final rule = (kRules[idx] as Map).cast<String, Object?>();
      return {
        'refused': false,
        'mode': byId(rule['modeId']),
        'modeId': rule['modeId'],
        'reason': fill(rule['reason'], i),
        'ruleOrder': rule['order'],
        'ruleSource': rule['source'],
        'alternatives': alternativesFor(rule['modeId'], i),
        'trendNote': trendNote,
        'subNoise': {
          'weight': or0('dWeightKg').abs() < _nWeight,
          'smm': or0('dSmmKg').abs() < _nSmm,
          'bfm': or0('dBfmKg').abs() < _nBfm,
        },
      };
    }
  }
  return {
    'refused': false, 'mode': byId('maintain'), 'modeId': 'maintain',
    'reason': '해당하는 규칙이 없어 유지로 둡니다.', 'ruleOrder': null,
    'alternatives': <Object?>[], 'trendNote': trendNote,
  };
}

/// 선택되지 않았지만 "왜 이건 아닌가" 를 설명해 줄 만한 모드들.
List<Map<String, Object?>> alternativesFor(Object? chosenId, Map<String, Object?> i) {
  final out = <Map<String, Object?>>[];
  for (final m0 in kModes) {
    final m = (m0 as Map).cast<String, Object?>();
    if (m['id'] == chosenId) continue;
    final why = whyNot(m, i);
    if (why != null) out.add({'id': m['id'], 'nameKo': m['nameKo'], 'why': why});
  }
  return out;
}

String? whyNot(Map<String, Object?> m, Map<String, Object?> i) {
  final maleGate = i['sex'] == 'male';
  final gate = maleGate ? 18 : 26;
  final pbf = jsNum(i, 'curPbfPct');
  if (m['id'] == 'cutting' && pbf > gate) {
    return '체지방률 ${jsNumToString(jsRound(pbf * 10) / 10)}% 는 커팅 기준($gate%)보다 높습니다. '
        '지금은 커팅이 아니라 감량입니다. $gate% 에 닿으면 자동으로 열립니다.';
  }
  if (m['id'] == 'muscleGain' && pbf > gate) {
    return '체지방률이 높은 상태에서 증량하면 늘어나는 대부분이 지방입니다. 먼저 '
        '$gate% 아래로 내려가는 편이 결과가 좋습니다.';
  }
  if (m['id'] == 'recomp' &&
      i['trainingAge'] == 'advanced' &&
      pbf < (maleGate ? 15 : 23)) {
    return '훈련 경력이 길고 이미 마른 상태에서는 리컴프 속도가 인바디 측정 오차보다 느립니다.';
  }
  if (m['id'] == 'miniCut' &&
      (i['deadlineWeeks'] == null || jsNum(i, 'deadlineWeeks') > 6)) {
    return '단기커팅은 6주 안에 마감이 있을 때만 의미가 있습니다.';
  }
  if (m['id'] == 'recovery' &&
      !(jsTruthy(i['recentTrend']) &&
          jsNum((i['recentTrend'] as Map).cast<String, Object?>(), 'weeksSpan') >= 8)) {
    return '최근에 긴 감량을 끝낸 기록이 없습니다. 회복모드는 감량 뒤에 오는 단계입니다.';
  }
  return null;
}
