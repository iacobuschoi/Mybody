/* =============================================================================
 * crosscheck.dart — 결과지 검산 (prototype/js/crosscheck.js 의 이식)
 *
 * **원본과 글자 단위로 같은 답을 내야 합니다.** 이 파일이 원본과 갈리면
 * 두 앱이 같은 결과지를 놓고 다른 말을 하게 되고, 그때 사용자는 어느
 * 쪽을 믿어야 할지 알 수 없습니다. 그래서 "잘 옮겼다" 로는 부족하고,
 * tools/difftest.js 가 수천 개의 입력을 양쪽에 넣어 답을 비교합니다.
 *
 * 규칙과 그 이유(왜 0.5kg 인지, 왜 용의자가 하나일 때만 고침을 내놓는지)는
 * 원본 주석에 있습니다. 여기서는 되풀이하지 않고, **옮기면서 달라질 뻔한
 * 곳**만 적습니다 — 그게 이 파일에서 위험한 부분입니다.
 *
 * 옮기면서 달라질 뻔한 것들:
 *   · Math.round 의 음수 처리가 Dart 와 다릅니다 → js_num.dart 의 jsRound
 *   · String(1.0) 이 JS 는 "1", Dart 는 "1.0" → jsNumToString
 *   · Date.parse 는 못 읽으면 NaN, Dart 는 null → gapKnown 으로 통일
 *   · failCount 는 run 과 **다른 ctx** 를 만듭니다 (gapKnown 없음, 절댓값,
 *     간격 0 이면 prev 를 버림). 실수로 통일하면 안 됩니다 — 원본이
 *     그렇게 돼 있고, 바꾸면 복구 제안의 결과가 달라집니다.
 * ========================================================================== */
library;

import 'dart:math' as math;
import 'js_num.dart';

class _Range {
  final double hardLo, hardHi, softLo, softHi;
  final String label, unit;
  const _Range(this.hardLo, this.hardHi, this.softLo, this.softHi, this.label, this.unit);
}

/// 순서가 중요합니다 — 범위 경고가 이 순서로 화면에 나갑니다.
const Map<String, _Range> kRange = {
  'weightKg': _Range(25, 250, 40, 120, '체중', 'kg'),
  'smmKg': _Range(8, 60, 18, 45, '골격근량', 'kg'),
  'bfmKg': _Range(1, 120, 3, 50, '체지방량', 'kg'),
  'pbfPct': _Range(2, 65, 5, 45, '체지방률', '%'),
  'ffmKg': _Range(20, 130, 35, 75, '제지방량', 'kg'),
  'bmi': _Range(10, 55, 16, 38, 'BMI', ''),
  'tbwL': _Range(15, 90, 25, 55, '체수분', 'L'),
  'proteinKg': _Range(3, 25, 7, 16, '단백질', 'kg'),
  'mineralKg': _Range(1, 10, 2.5, 5.5, '무기질', 'kg'),
  'bmrKcal': _Range(700, 3500, 1100, 2200, '기초대사량', 'kcal'),
  'visceralFatLevel': _Range(1, 30, 1, 20, '내장지방 레벨', ''),
  'whr': _Range(0.55, 1.30, 0.70, 1.05, '복부지방률', ''),
  'inbodyScore': _Range(0, 100, 40, 100, 'InBody 점수', '점'),
  'idealWeightKg': _Range(25, 200, 40, 110, '적정체중', 'kg'),
};

class _Delta {
  final double warn, bad;
  final String label, unit;
  const _Delta(this.warn, this.bad, this.label, this.unit);
}

const Map<String, _Delta> kDelta = {
  'weightKg': _Delta(2.0, 5.0, '체중', 'kg'),
  'smmKg': _Delta(0.5, 2.0, '골격근량', 'kg'),
  'bfmKg': _Delta(1.5, 4.0, '체지방량', 'kg'),
  'pbfPct': _Delta(2.0, 6.0, '체지방률', '%p'),
};

/// 앱의 오차 상수. 원본은 window.MB_MODES.NOISE 에서 읽고, 없으면 이 값입니다.
/// 베껴 쓰면 어긋나므로 한 군데서만 정합니다.
class Noise {
  final double weight, smm, bfm;
  const Noise({this.weight = 1.0, this.smm = 0.6, this.bfm = 1.0});
}

Noise _noise = const Noise();
set crosscheckNoise(Noise n) => _noise = n;

double _floorOf(String key) {
  if (key == 'weightKg') return _noise.weight * math.sqrt2;
  if (key == 'smmKg') return _noise.smm * math.sqrt2;
  if (key == 'bfmKg') return _noise.bfm * math.sqrt2;
  return 2.0;
}

/// 원본 JS: `fmt(x, d) { return (...).toFixed(d || 1); }`
///
/// **`d || 1` 이 함정입니다.** 자바스크립트에서 0 은 거짓이라, `fmt(x, 0)`
/// 은 소수점 0자리가 아니라 **1자리**로 찍힙니다. 그래서 _dec() 가
/// 기초대사량·InBody 점수·내장지방에 0 을 돌려줘도 화면에는
/// "1072.0kcal" 로 나갑니다 — 원래 의도는 "1072kcal" 이었을 것입니다.
///
/// 여기서 고치지 않습니다. 지금 쓰는 앱이 그렇게 찍고 있고, 옮기는
/// 쪽이 말없이 다르게 찍으면 같은 결과지를 놓고 두 앱이 다른 말을
/// 합니다. 고칠지 말지는 제품의 결정이라 주인에게 물어볼 일입니다.
/// (차이 검사가 이걸 첫 판에 잡았습니다.)
String _fmt(num x, [int d = 1]) => toFixed(x, d == 0 ? 1 : d);

int _dec(String k) => k == 'whr'
    ? 2
    : (k == 'bmrKcal' || k == 'inbodyScore' || k == 'visceralFatLevel' ? 0 : 1);

/// 값 + "실제로 인쇄된 칸인가" 를 같이 들고 다닙니다.
class _Filled {
  final Map<String, double?> v = {};
  final Map<String, bool> printed = {};
  double? operator [](String k) => v[k];
  void operator []=(String k, double? x) => v[k] = x;
}

_Filled _fill(Map<String, Object?> s) {
  final o = _Filled();
  for (final k in kRange.keys) {
    o[k] = num_(s[k]);
    o.printed[k] = num_(s[k]) != null;
  }
  if (o['bfmKg'] == null && o['weightKg'] != null && o['pbfPct'] != null) {
    o['bfmKg'] = r1(o['weightKg']! * o['pbfPct']! / 100);
  }
  if (o['ffmKg'] == null && o['weightKg'] != null && o['bfmKg'] != null) {
    o['ffmKg'] = r1(o['weightKg']! - o['bfmKg']!);
  }
  return o;
}

class _Ctx {
  double heightM = 0;
  String? sex;
  _Filled? prev;
  double gapDays = 0;
  double signedDays = 0;
  bool gapKnown = false;
}

class _Fix {
  final String field;
  final num value;
  const _Fix(this.field, this.value);
  Map<String, Object?> toJson() => {'field': field, 'value': value};
}

class _Result {
  final bool ok;
  final String why;
  final _Fix? fix;
  const _Result(this.ok, this.why, this.fix);
}

class _Rule {
  final String id;
  final bool tight;
  final String label;
  final List<String> fields;
  final _Result? Function(_Filled v, _Ctx ctx) run;
  const _Rule(this.id, this.tight, this.label, this.fields, this.run);
}

final List<_Rule> kRules = [
  _Rule('C1', true, '제지방 = 체중 − 체지방', ['ffmKg', 'weightKg', 'bfmKg'], (v, ctx) {
    if (!(v.printed['ffmKg'] ?? false) || v['weightKg'] == null || v['bfmKg'] == null) return null;
    final calc = v['weightKg']! - v['bfmKg']!;
    final gap = (v['ffmKg']! - calc).abs();
    return _Result(
      gap <= 0.5,
      '체중 ${_fmt(v['weightKg']!)} − 체지방 ${_fmt(v['bfmKg']!)} = ${_fmt(calc)}'
      'kg, 결과지의 제지방 ${_fmt(v['ffmKg']!)}kg'
      '${gap <= 0.5 ? '' : ' (${_fmt(gap)}kg 차이)'}',
      gap <= 0.5 ? null : _Fix('ffmKg', r1(calc)),
    );
  }),
  _Rule('C2', true, '체지방률 = 체지방 ÷ 체중', ['pbfPct', 'bfmKg', 'weightKg'], (v, ctx) {
    if (!(v.printed['pbfPct'] ?? false) ||
        !(v.printed['bfmKg'] ?? false) ||
        !((v['weightKg'] ?? 0) > 0)) return null;
    final calc = v['bfmKg']! / v['weightKg']! * 100;
    final gap = (v['pbfPct']! - calc).abs();
    return _Result(
      gap <= 0.8,
      '체지방 ${_fmt(v['bfmKg']!)} ÷ 체중 ${_fmt(v['weightKg']!)} = ${_fmt(calc)}'
      '%, 결과지의 체지방률 ${_fmt(v['pbfPct']!)}%'
      '${gap <= 0.8 ? '' : ' (${_fmt(gap)}%p 차이)'}',
      gap <= 0.8 ? null : _Fix('pbfPct', r1(calc)),
    );
  }),
  _Rule('C3', true, 'BMI = 체중 ÷ 키²', ['bmi', 'weightKg'], (v, ctx) {
    if (!(v.printed['bmi'] ?? false) || v['weightKg'] == null || !(ctx.heightM > 0)) return null;
    final calc = v['weightKg']! / (ctx.heightM * ctx.heightM);
    final gap = (v['bmi']! - calc).abs();
    return _Result(
      gap <= 0.5,
      '키 ${jsRound(ctx.heightM * 100).toInt()}cm · 체중 ${_fmt(v['weightKg']!)}'
      'kg 이면 BMI ${_fmt(calc)}, 결과지는 ${_fmt(v['bmi']!)}'
      '${gap <= 0.5 ? '' : ' (프로필의 키가 맞는지도 확인해 주세요)'}',
      gap <= 0.5 ? null : _Fix('bmi', r1(calc)),
    );
  }),
  _Rule('C4', true, '체수분 + 단백질 + 무기질 + 체지방 = 체중',
      ['tbwL', 'proteinKg', 'mineralKg', 'bfmKg', 'weightKg'], (v, ctx) {
    if (v['tbwL'] == null || v['proteinKg'] == null || v['mineralKg'] == null ||
        v['bfmKg'] == null || v['weightKg'] == null) return null;
    final sum = v['tbwL']! + v['proteinKg']! + v['mineralKg']! + v['bfmKg']!;
    final gap = (sum - v['weightKg']!).abs();
    return _Result(
      gap <= 0.8,
      '${_fmt(v['tbwL']!)} + ${_fmt(v['proteinKg']!)} + ${_fmt(v['mineralKg']!)} + '
      '${_fmt(v['bfmKg']!)} = ${_fmt(sum)}, 체중 ${_fmt(v['weightKg']!)}kg'
      '${gap <= 0.8 ? '' : ' (${_fmt(gap)}kg 차이)'}',
      null, // 넷 중 어느 칸이 틀렸는지 이 규칙만으로는 모릅니다
    );
  }),
  _Rule('C5', false, '체수분 ≈ 제지방의 73%', ['tbwL', 'ffmKg'], (v, ctx) {
    if (v['tbwL'] == null || !((v['ffmKg'] ?? 0) > 0)) return null;
    final ratio = v['tbwL']! / v['ffmKg']!;
    return _Result(
      ratio >= 0.66 && ratio <= 0.80,
      '체수분 ${_fmt(v['tbwL']!)}L ÷ 제지방 ${_fmt(v['ffmKg']!)}kg = '
      '${jsRound(ratio * 100).toInt()}% (보통 70~76%)',
      null,
    );
  }),
  _Rule('C6', false, '골격근은 제지방 안에 있다', ['smmKg', 'ffmKg'], (v, ctx) {
    if (v['smmKg'] == null || !((v['ffmKg'] ?? 0) > 0)) return null;
    final k = v['smmKg']! / v['ffmKg']!;
    return _Result(
      k >= 0.45 && k <= 0.65,
      '골격근 ${_fmt(v['smmKg']!)} ÷ 제지방 ${_fmt(v['ffmKg']!)} = '
      '${jsRound(k * 100).toInt()}% (사람은 45~65% 안에 들어옵니다)'
      '${k > 1 ? ' — 골격근이 제지방보다 클 수는 없습니다' : ''}',
      null,
    );
  }),
  _Rule('C9', false, '기초대사량 ≈ 370 + 21.6 × 제지방', ['bmrKcal', 'ffmKg'], (v, ctx) {
    if (v['bmrKcal'] == null || !((v['ffmKg'] ?? 0) > 0)) return null;
    final calc = 370 + 21.6 * v['ffmKg']!;
    final off = (v['bmrKcal']! - calc).abs() / calc;
    return _Result(
      off <= 0.12,
      '제지방 ${_fmt(v['ffmKg']!)}kg 이면 ${jsRound(calc).toInt()}kcal 근처, 결과지는 '
      '${jsRound(v['bmrKcal']!).toInt()}kcal',
      off <= 0.12 ? null : _Fix('bmrKcal', jsRound(calc).toInt()),
    );
  }),
  _Rule('CK', false, '골격근 비율이 지난 측정과 이어진다', ['smmKg'], (v, ctx) {
    final p = ctx.prev;
    if (p == null || v['smmKg'] == null || !((v['ffmKg'] ?? 0) > 0)) return null;
    if (!((p['ffmKg'] ?? 0) > 0) || !((p['smmKg'] ?? 0) > 0)) return null;
    final expect = p['smmKg']! / p['ffmKg']! * v['ffmKg']!;
    final tol = ctx.gapKnown ? math.min(3.0, 1.2 + (ctx.gapDays / 30) * 0.25) : 3.0;
    final gap = (v['smmKg']! - expect).abs();
    return _Result(
      gap <= tol,
      '지난 측정(${ctx.gapKnown ? _gapWord(ctx.signedDays) : '날짜 모름'})의 비율로 보면 '
      '${_fmt(expect)}kg 근처, 이번 판독은 ${_fmt(v['smmKg']!)}kg'
      '${gap <= tol ? '' : ' (${_fmt(gap)}kg 차이)'}',
      gap <= tol ? null : _Fix('smmKg', r1(expect)),
    );
  }),
];

/* --- 자릿수 복구 제안 ------------------------------------------------------ */

List<double> repairCandidates(double x) {
  final out = <double>[];
  final seen = <String>{};
  void add(num y) {
    if (!y.isFinite || y <= 0) return;
    final k = jsNumToString(r2(y));
    if (k == jsNumToString(r2(x)) || seen.contains(k)) return;
    seen.add(k);
    out.add(r2(y));
  }

  add(x / 10);
  add(x * 10);
  final xs = jsNumToString(x);
  final s = xs.replaceFirst('.', '');
  if (s.length >= 2) {
    final sw = '${s[1]}${s[0]}${s.substring(2)}';
    final dot = xs.indexOf('.');
    final cand = dot < 0 ? sw : '${sw.substring(0, dot)}.${sw.substring(dot)}';
    final p = _parseFloat(cand);
    if (p != null) add(p);
  }
  const swaps = [
    ['8', '3'], ['3', '8'], ['5', '6'], ['6', '5'],
    ['1', '7'], ['7', '1'], ['0', '8'], ['8', '0'],
    ['4', '9'], ['9', '4'],
  ];
  for (final p in swaps) {
    final t = xs.split(p[0]).join(p[1]);
    if (t != xs) {
      final f = _parseFloat(t);
      if (f != null) add(f);
    }
  }
  return out;
}

/// JS 의 parseFloat — 앞쪽에서 읽을 수 있는 만큼만 읽습니다.
/// Dart 의 double.tryParse 는 "12abc" 에 null 을 주지만 JS 는 12 를 줍니다.
double? _parseFloat(String s) {
  final m = RegExp(r'^[\s]*[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?').firstMatch(s);
  if (m == null) return null;
  return double.tryParse(m.group(0)!.trim());
}

/* --- 본체 ------------------------------------------------------------------ */

Map<String, Object?> run(
  Map<String, Object?>? scan,
  Map<String, Object?>? profile,
  Map<String, Object?>? prevScan,
) {
  scan ??= {};
  profile ??= {};
  final v = _fill(scan);
  final ctx = _Ctx();
  final hc = num_(profile['heightCm']);
  ctx.heightM = (hc != null && hc > 0) ? hc / 100 : 0;
  ctx.sex = profile['sex'] as String?;
  ctx.prev = prevScan != null ? _fill(prevScan) : null;

  if (prevScan != null && scan['measuredAt'] != null && prevScan['measuredAt'] != null) {
    final g = _dateDiffDays(scan['measuredAt'], prevScan['measuredAt']);
    ctx.gapKnown = g != null && g.isFinite;
    ctx.signedDays = ctx.gapKnown ? g! : 0;
    ctx.gapDays = ctx.signedDays.abs();
  }

  final checks = <Map<String, Object?>>[];
  final fields = <String, String>{};
  final counts = {'pass': 0, 'fail': 0, 'skip': 0};

  final raw = <MapEntry<_Rule, _Result>>[];
  for (final rule in kRules) {
    final r = rule.run(v, ctx);
    if (r == null) {
      counts['skip'] = counts['skip']! + 1;
      continue;
    }
    raw.add(MapEntry(rule, r));
  }
  final suspect = _blame(raw.map((e) => _BlameIn(e.value.ok, e.key.tight, e.key.fields)).toList(), v);

  for (final e in raw) {
    final rule = e.key;
    final r = e.value;
    checks.add({
      'id': rule.id,
      'label': rule.label,
      'ok': r.ok,
      'why': r.why,
      'fields': List<String>.from(rule.fields),
      'fix': _usableFix(rule, r.fix, v, suspect)?.toJson(),
      'suspect': suspect,
    });
    if (r.ok) {
      counts['pass'] = counts['pass']! + 1;
    } else {
      counts['fail'] = counts['fail']! + 1;
    }
    final marked = r.ok ? rule.fields : _realFields(rule.fields, v);
    for (final f in marked) {
      if (v[f] == null || !(v.printed[f] ?? false)) continue;
      if (!r.ok) {
        fields[f] = 'conflict';
      } else if (fields[f] != 'conflict') {
        fields[f] = 'verified';
      }
    }
  }

  final rangeIssues = <Map<String, Object?>>[];
  for (final k in kRange.keys) {
    final x = num_(scan[k]);
    if (x == null) continue;
    final R = kRange[k]!;
    if (x < R.hardLo || x > R.hardHi) {
      rangeIssues.add({
        'field': k,
        'level': 'bad',
        'why': '${R.label} ${_fmt(x, _dec(k))}${R.unit} 은 사람의 값이 아닙니다 '
            '(${jsNumToString(R.hardLo)}~${jsNumToString(R.hardHi)}${R.unit}).'
      });
      fields[k] = 'conflict';
    } else if (x < R.softLo || x > R.softHi) {
      rangeIssues.add({
        'field': k,
        'level': 'warn',
        'why': '${R.label} ${_fmt(x, _dec(k))}${R.unit} 은 흔한 구간('
            '${jsNumToString(R.softLo)}~${jsNumToString(R.softHi)}${R.unit}) 밖입니다. 맞으면 그대로 두세요.'
      });
    }
  }

  if (ctx.sex != null && v['pbfPct'] != null) {
    final lim = ctx.sex == 'female' ? [10.0, 55.0] : [3.0, 45.0];
    if (v['pbfPct']! < lim[0] || v['pbfPct']! > lim[1]) {
      rangeIssues.add({
        'field': 'pbfPct',
        'level': 'bad',
        'why': '체지방률 ${_fmt(v['pbfPct']!)}% 는 '
            '${ctx.sex == 'female' ? '여성' : '남성'}에게 나올 수 없는 값입니다. '
            '프로필의 성별이 맞는지도 확인해 주세요.'
      });
      fields['pbfPct'] = 'conflict';
    }
  }

  final deltaIssues = <Map<String, Object?>>[];
  if (ctx.prev != null && ctx.gapKnown) {
    final weeks = math.max(ctx.gapDays / 7, 0.15);
    for (final k in kDelta.keys) {
      final a = ctx.prev![k], b = v[k];
      if (a == null || b == null) continue;
      final d = b - a, ad = d.abs();
      final D = kDelta[k]!;
      final fl = _floorOf(k);
      final warnAt = math.max(fl, D.warn * weeks);
      final badAt = math.max(fl * 2.5, D.bad * weeks);
      if (ad > badAt) {
        deltaIssues.add({
          'field': k,
          'level': 'bad',
          'why': '${D.label}이 ${_spanWord(ctx.gapDays)} '
              '${d > 0 ? '+' : '−'}${_fmt(ad, _dec(k))}${D.unit} 움직였습니다. '
              '몸이 이 속도로 변하지는 않습니다 — 판독 오류이거나 다른 사람의 결과지입니다.'
        });
        fields[k] = 'conflict';
      } else if (ad > warnAt) {
        deltaIssues.add({
          'field': k,
          'level': 'warn',
          'why': '${D.label} ${d > 0 ? '+' : '−'}${_fmt(ad, _dec(k))}${D.unit}'
              ' (${jsRound(ctx.gapDays) >= 1 ? '${jsRound(ctx.gapDays).toInt()}일' : '같은 날'})'
              '. 빠른 편입니다 — 맞는지 한 번 보세요.'
        });
      }
    }
  }

  final suggestions = <Map<String, Object?>>[];
  for (final k in fields.keys.toList()) {
    if (fields[k] != 'conflict') continue;
    final x = num_(scan[k]);
    if (x == null) continue;
    final before = _failCount(scan, profile, prevScan, null, null);
    final good = <double>[];
    for (final cand in repairCandidates(x)) {
      if (_failCount(scan, profile, prevScan, k, cand) == 0 && before > 0) good.add(cand);
    }
    if (good.length == 1) {
      final R = kRange[k];
      suggestions.add({
        'field': k,
        'from': x,
        'to': good[0],
        'why': '${obj(R != null ? R.label : k)} ${_fmt(good[0], _dec(k))}'
            '${R != null ? R.unit : ''} 로 보면 검산이 전부 맞아떨어집니다.'
      });
    }
  }

  final anyBadRange = rangeIssues.any((x) => x['level'] == 'bad');
  final anyBadDelta = deltaIssues.any((x) => x['level'] == 'bad');
  final status = (counts['fail']! > 0 || anyBadRange || anyBadDelta)
      ? 'conflict'
      : (rangeIssues.isNotEmpty || deltaIssues.isNotEmpty)
          ? 'review'
          : counts['pass']! > 0
              ? 'ok'
              : 'review';

  List<String>? involved;
  if (suspect == null && counts['fail']! > 0) {
    final seen = <String>{};
    final list = <String>[];
    for (final c in checks) {
      if (c['ok'] == true) continue;
      for (final f in _realFields((c['fields'] as List).cast<String>(), v)) {
        if (v[f] == null || !(v.printed[f] ?? false) || seen.contains(f)) continue;
        seen.add(f);
        list.add(f);
      }
    }
    if (list.length > 1) involved = list;
  }

  return {
    'checks': checks,
    'fields': fields,
    'counts': counts,
    'status': status,
    'suspect': suspect,
    'involved': involved,
    'rangeIssues': rangeIssues,
    'deltaIssues': deltaIssues,
    'suggestions': suggestions,
  };
}

/* --- 도우미 ---------------------------------------------------------------- */

_Fix? _usableFix(_Rule rule, _Fix? fix, _Filled v, String? suspect) {
  if (fix == null) return null;
  if (fix.field != suspect) return null;
  final R = kRange[fix.field];
  if (R != null && (fix.value < R.hardLo || fix.value > R.hardHi)) return null;
  final sane = rule.fields.every((f) {
    if (f == fix.field) return true;
    final x = v[f];
    if (x == null) return true;
    final F = kRange[f];
    return F == null || (x >= F.hardLo && x <= F.hardHi);
  });
  return sane ? fix : null;
}

List<String> _sourcesOf(String f, _Filled v) {
  if (f == 'ffmKg' && !(v.printed['ffmKg'] ?? false)) {
    return ['weightKg', 'bfmKg'].where((k) => v[k] != null).toList();
  }
  if (f == 'bfmKg' && !(v.printed['bfmKg'] ?? false)) {
    return ['weightKg', 'pbfPct'].where((k) => v[k] != null).toList();
  }
  return [f];
}

List<String> _realFields(List<String> fields, _Filled v) {
  final out = <String>[];
  final seen = <String>{};
  for (final f in fields) {
    for (final k in _sourcesOf(f, v)) {
      if (seen.add(k)) out.add(k);
    }
  }
  return out;
}

class _BlameIn {
  final bool ok;
  final bool tight;
  final List<String> fields;
  const _BlameIn(this.ok, this.tight, this.fields);
}

String? _blame(List<_BlameIn> checks, _Filled v) {
  final broke = <String, int>{}, ok = <String, int>{};
  for (final c in checks) {
    for (final f in _realFields(c.fields, v)) {
      if (v[f] == null) continue;
      if (c.ok) {
        if (c.tight) ok[f] = (ok[f] ?? 0) + 1;
      } else {
        broke[f] = (broke[f] ?? 0) + 1;
      }
    }
  }
  String? best;
  var bestN = 0;
  var tie = false;
  for (final f in broke.keys) {
    if (ok.containsKey(f)) continue;
    if (broke[f]! > bestN) {
      best = f;
      bestN = broke[f]!;
      tie = false;
    } else if (broke[f] == bestN) {
      tie = true;
    }
  }
  return tie ? null : best;
}

/// 받침 있으면 '을', 없으면 '를'.
const Map<String, String> _objLatin = {
  'BMI': '를', 'WHR': '을', 'SMM': '을', 'BFM': '을',
  'FFM': '을', 'TBW': '를', 'BMR': '을',
};

String obj(String word) {
  if (_objLatin.containsKey(word)) return word + _objLatin[word]!;
  final c = word.codeUnitAt(word.length - 1);
  if (c < 0xAC00 || c > 0xD7A3) return '$word을';
  return word + (((c - 0xAC00) % 28) != 0 ? '을' : '를');
}

String _spanWord(double days) {
  final d = jsRound(days.abs()).toInt();
  return d >= 1 ? '$d일 만에' : '같은 날에';
}

String _gapWord(double signed) {
  final d = jsRound(signed).toInt();
  if (d >= 1) return '$d일 전';
  if (d <= -1) return '${d.abs()}일 뒤';
  return '같은 날';
}

/// JS: (Date.parse(a) - Date.parse(b)) / 86400000. 못 읽으면 null(=NaN).
double? _dateDiffDays(Object? a, Object? b) {
  final ta = _parseDate(a), tb = _parseDate(b);
  if (ta == null || tb == null) return null;
  return (ta - tb) / 86400000;
}

int? _parseDate(Object? x) {
  if (x is! String) return null;
  final d = DateTime.tryParse(x);
  return d?.millisecondsSinceEpoch;
}

/// 한 칸을 바꿔 끼우고 검산이 몇 개 깨지는지.
///
/// **run() 과 ctx 구성이 다릅니다.** gapKnown 을 안 만들고(그래서 CK 의
/// 허용치가 항상 3.0), 간격은 절댓값이고, 간격이 0 이면 prev 를 버립니다.
/// 원본이 그렇게 돼 있습니다. 통일하면 복구 제안의 결과가 달라집니다.
int _failCount(
  Map<String, Object?> scan,
  Map<String, Object?>? profile,
  Map<String, Object?>? prevScan,
  String? field,
  double? value,
) {
  final s2 = Map<String, Object?>.from(scan);
  if (field != null) s2[field] = value;
  final v = _fill(s2);
  final ctx = _Ctx();
  final hc = profile == null ? null : num_(profile['heightCm']);
  ctx.heightM = (hc != null && hc > 0) ? hc / 100 : 0;
  ctx.sex = profile?['sex'] as String?;
  ctx.prev = prevScan != null ? _fill(prevScan) : null;
  ctx.gapDays = 0;
  if (prevScan != null && s2['measuredAt'] != null && prevScan['measuredAt'] != null) {
    final g = _dateDiffDays(s2['measuredAt'], prevScan['measuredAt']);
    ctx.gapDays = (g != null && g.isFinite) ? g.abs() : 0;
  }
  if (ctx.prev != null && !(ctx.gapDays > 0)) ctx.prev = null;

  var bad = 0;
  for (final rule in kRules) {
    final r = rule.run(v, ctx);
    if (r != null && !r.ok) bad++;
  }
  for (final k in kRange.keys) {
    final x = num_(s2[k]);
    if (x == null) continue;
    if (x < kRange[k]!.hardLo || x > kRange[k]!.hardHi) bad++;
  }
  return bad;
}

String stateLabel(String? state) =>
    state == 'verified' ? '검산됨' : state == 'conflict' ? '모순' : '미검산';
