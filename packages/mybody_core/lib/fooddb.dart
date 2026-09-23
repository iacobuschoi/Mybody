/* =============================================================================
 * fooddb.dart — 식품 검색과 배수 계산 (prototype/js/fooddb.js 의 이식)
 *
 * 식품표 자체는 fooddb_data.dart 에 찍혀 있습니다. 여기에는 찾는 방법과
 * "1.5인분" 을 실제 숫자로 바꾸는 계산만 있습니다.
 * ========================================================================== */
library;

import 'fooddb_data.dart';
import 'js_num.dart';

export 'fooddb_data.dart';

/// 이름·별명·분류를 한 줄로 이어 붙여 **부분 일치**로 찾습니다.
/// 이름의 맨 앞에서 걸리면 먼저 보여 줍니다.
List<Map<String, Object?>> search(Object? q, [Object? limit]) {
  final needle = '${q ?? ''}'.trim().toLowerCase();
  if (needle.isEmpty) return [];
  final hits = <Map<String, Object?>>[];
  final scores = <double>[];
  for (final x0 in kFoodDb) {
    final x = (x0 as Map).cast<String, Object?>();
    final hay = '${x['name']} ${x['alias']} ${x['cat']}'.toLowerCase();
    final idx = hay.indexOf(needle);
    if (idx >= 0) {
      hits.add(x);
      scores.add(('${x['name']}'.toLowerCase().indexOf(needle) == 0 ? 0 : 1) + idx * 0.001);
    }
  }
  /* JS 의 sort 는 안정 정렬입니다. 점수가 같은 식품(예: 같은 자리에서 걸린
     '프로틴 쉐이크' 세 종류)의 순서가 화면에서 뒤바뀌지 않게 맞춥니다. */
  final order = List<int>.generate(hits.length, (i) => i);
  order.sort((a, b) {
    final c = scores[a] - scores[b];
    if (c < 0) return -1;
    if (c > 0) return 1;
    return a - b;
  });
  final n = jsTruthy(limit) ? jsToNumber(limit).toInt() : 30;
  final out = [for (final i in order) hits[i]];
  return out.length > n ? out.sublist(0, n) : out;
}

/* --- 비슷한 이름 찾기 -----------------------------------------------------
 *
 * search() 가 한 개도 못 찾았을 때 부릅니다. 오타('김치찌게')·초성('ㄷㄱㅅㅅ')·
 * 한/영 전환을 잊은 입력('ekfrktmatkf')을 **자모 단위**로 견줍니다.
 * 글자 단위로 견주면 '찌게'와 '찌개'는 완전히 다른 글자지만, 자모로 풀면
 * 모음 하나 차이라서 오타로 잡힙니다.
 *
 * 점수는 정수만 씁니다. 부동소수점을 쓰면 두 언어의 반올림이 갈릴 자리가
 * 생기고, 그러면 순서가 뒤바뀝니다. 정렬도 3단 비교를 명시합니다 —
 * 언어의 기본 정렬이 안정적이라는 데 기대지 않습니다.
 * -------------------------------------------------------------------------- */

const _cho = [
  'ㄱ', 'ㄲ', 'ㄴ', 'ㄷ', 'ㄸ', 'ㄹ', 'ㅁ', 'ㅂ', 'ㅃ', 'ㅅ',
  'ㅆ', 'ㅇ', 'ㅈ', 'ㅉ', 'ㅊ', 'ㅋ', 'ㅌ', 'ㅍ', 'ㅎ',
];
/// 겹모음(ㅘ ㅙ ㅚ ㅝ ㅞ ㅟ ㅢ)은 두 글자로 풉니다 — 자판에서도 두 번 쳐집니다.
const _vow = [
  'ㅏ', 'ㅐ', 'ㅑ', 'ㅒ', 'ㅓ', 'ㅔ', 'ㅕ', 'ㅖ', 'ㅗ', 'ㅗㅏ', 'ㅗㅐ',
  'ㅗㅣ', 'ㅛ', 'ㅜ', 'ㅜㅓ', 'ㅜㅔ', 'ㅜㅣ', 'ㅠ', 'ㅡ', 'ㅡㅣ', 'ㅣ',
];
/// 겹받침(ㄳ ㄵ … ㅄ)도 두 글자로. 첫 칸은 받침 없음.
const _jong = [
  '', 'ㄱ', 'ㄲ', 'ㄱㅅ', 'ㄴ', 'ㄴㅈ', 'ㄴㅎ', 'ㄷ', 'ㄹ', 'ㄹㄱ',
  'ㄹㅁ', 'ㄹㅂ', 'ㄹㅅ', 'ㄹㅌ', 'ㄹㅍ', 'ㄹㅎ', 'ㅁ', 'ㅂ', 'ㅂㅅ', 'ㅅ',
  'ㅆ', 'ㅇ', 'ㅈ', 'ㅊ', 'ㅋ', 'ㅌ', 'ㅍ', 'ㅎ',
];
/// 호환 자모 하나로 들어온 겹자음·겹모음을 위 표와 같은 모양으로 풉니다.
const _splitJamo = {
  'ㅘ': 'ㅗㅏ', 'ㅙ': 'ㅗㅐ', 'ㅚ': 'ㅗㅣ', 'ㅝ': 'ㅜㅓ', 'ㅞ': 'ㅜㅔ', 'ㅟ': 'ㅜㅣ', 'ㅢ': 'ㅡㅣ',
  'ㄳ': 'ㄱㅅ', 'ㄵ': 'ㄴㅈ', 'ㄶ': 'ㄴㅎ', 'ㄺ': 'ㄹㄱ', 'ㄻ': 'ㄹㅁ', 'ㄼ': 'ㄹㅂ',
  'ㄽ': 'ㄹㅅ', 'ㄾ': 'ㄹㅌ', 'ㄿ': 'ㄹㅍ', 'ㅀ': 'ㄹㅎ', 'ㅄ': 'ㅂㅅ',
};
/// 두벌식 자판. 대문자는 쌍자음과 ㅒ·ㅖ 만 다르고 나머지는 소문자와 같습니다.
const _qwerty = {
  'r': 'ㄱ', 's': 'ㄴ', 'e': 'ㄷ', 'f': 'ㄹ', 'a': 'ㅁ', 'q': 'ㅂ', 't': 'ㅅ',
  'd': 'ㅇ', 'w': 'ㅈ', 'c': 'ㅊ', 'z': 'ㅋ', 'x': 'ㅌ', 'v': 'ㅍ', 'g': 'ㅎ',
  'k': 'ㅏ', 'o': 'ㅐ', 'i': 'ㅑ', 'j': 'ㅓ', 'p': 'ㅔ', 'u': 'ㅕ', 'h': 'ㅗ',
  'y': 'ㅛ', 'n': 'ㅜ', 'b': 'ㅠ', 'm': 'ㅡ', 'l': 'ㅣ',
  'R': 'ㄲ', 'E': 'ㄸ', 'Q': 'ㅃ', 'T': 'ㅆ', 'W': 'ㅉ', 'O': 'ㅒ', 'P': 'ㅖ',
};

/// 원본의 /[\s·()\/,.\-+&'"]/g — 괄호·가운뎃점·공백은 이름 장식이라 뺍니다.
final _strip = RegExp(r'''[\s·()/,.\-+&'"]''');
final _latinOnly = RegExp(r'^[A-Za-z]+$');

String _normalize(String s) => s.toLowerCase().replaceAll(_strip, '');

/// 정규화한 글자열을 자모로 풉니다. 한글이 아닌 글자는 그대로 둡니다.
String _jamo(String s) {
  final b = StringBuffer();
  for (final ch in _normalize(s).codeUnits) {
    if (ch >= 0xAC00 && ch <= 0xD7A3) {
      final idx = ch - 0xAC00;
      b.write(_cho[idx ~/ 588]);
      b.write(_vow[(idx % 588) ~/ 28]);
      b.write(_jong[idx % 28]);
    } else if (ch >= 0x3131 && ch <= 0x3163) {
      final c = String.fromCharCode(ch);
      b.write(_splitJamo[c] ?? c);
    } else {
      b.writeCharCode(ch);
    }
  }
  return b.toString();
}

/// 영문만 들어왔을 때 "한/영 키를 안 누른 것" 으로 보고 자판대로 자모를 만듭니다.
/// 대소문자를 살려야 하므로 normalize 를 거치지 않고 trim 만 합니다.
String _qwertyJamo(String s) {
  final b = StringBuffer();
  for (final ch in s.trim().codeUnits) {
    final k = String.fromCharCode(ch);
    final j = _qwerty[k] ?? _qwerty[k.toLowerCase()];
    if (j != null) b.write(j);
  }
  return b.toString();
}

/// 초성만 친 것인가 — 모두 초성 자음이고 두 자 이상.
bool _isChosung(String q) {
  final n = _normalize(q);
  if (n.length < 2) return false;
  for (final ch in n.codeUnits) {
    if (!_cho.contains(String.fromCharCode(ch))) return false;
  }
  return true;
}

String _chosung(String text) {
  final b = StringBuffer();
  for (final ch in _normalize(text).codeUnits) {
    if (ch >= 0xAC00 && ch <= 0xD7A3) {
      b.write(_cho[(ch - 0xAC00) ~/ 588]);
    } else {
      b.writeCharCode(ch);
    }
  }
  return b.toString();
}

/// a 를 b 의 **부분 문자열**에 맞추는 편집 거리 (Sellers). 인접한 두 글자를
/// 바꿔 친 것은 한 번으로 셉니다. b 의 어디서든 시작할 수 있어야 하므로
/// 첫 행이 전부 0 이고, 마지막 행의 최솟값을 돌려줍니다.
int _dist(String a, String b) {
  final au = a.codeUnits, bu = b.codeUnits;
  final m = au.length, n = bu.length;
  final d = List.generate(m + 1, (i) => List<int>.filled(n + 1, 0));
  for (var i = 1; i <= m; i++) d[i][0] = i;
  for (var i = 1; i <= m; i++) {
    for (var j = 1; j <= n; j++) {
      var v = d[i - 1][j] + 1;
      if (d[i][j - 1] + 1 < v) v = d[i][j - 1] + 1;
      final sub = d[i - 1][j - 1] + (au[i - 1] == bu[j - 1] ? 0 : 1);
      if (sub < v) v = sub;
      if (i >= 2 && j >= 2 && au[i - 1] == bu[j - 2] && au[i - 2] == bu[j - 1]) {
        final tr = d[i - 2][j - 2] + 1;
        if (tr < v) v = tr;
      }
      d[i][j] = v;
    }
  }
  var best = d[m][0];
  for (var j = 1; j <= n; j++) {
    if (d[m][j] < best) best = d[m][j];
  }
  return best;
}

/// 이름 하나(또는 별명 토큰 하나)의 점수. 자모열을 통째로 품으면 90,
/// 아니면 자모 넷마다 오타 하나까지 봐주고 오타 하나에 10점씩 뺍니다.
({int s, String why}) _scoreText(String qj, String text) {
  final tj = _jamo(text);
  if (tj.contains(qj)) return (s: 90, why: 'partial');
  if (qj.length >= 4) {
    final d = _dist(qj, tj);
    var maxD = qj.length ~/ 4;
    if (maxD < 1) maxD = 1;
    if (d <= maxD) return (s: 80 - d * 10, why: 'typo');
  }
  return (s: 0, why: '');
}

/// 정확히 겹치는 게 없을 때 비슷한 이름. `[{name, score, why}]` 를 점수 높은
/// 순으로, 최대 limit(기본 8)개. why 는 partial·typo·chosung·qwerty 중 하나.
List<Map<String, Object?>> similar(Object? q, [Object? limit]) {
  final qs = '${q ?? ''}';
  final qn = _normalize(qs);
  final qj = _jamo(qs);
  final cands = <({String j, String? tag})>[(j: qj, tag: null)];
  if (_latinOnly.hasMatch(qs.trim())) {
    final qq = _qwertyJamo(qs);
    if (qq.length >= 2) cands.add((j: qq, tag: 'qwerty'));
  }
  if (qj.length < 2 && cands.length == 1) return [];
  final cho = _isChosung(qs);

  final rows = <({String name, int score, String why, int i})>[];
  for (var i = 0; i < kFoodDb.length; i++) {
    final x = (kFoodDb[i] as Map).cast<String, Object?>();
    final name = '${x['name']}';
    /* 이름은 별명보다 2점 더 — 같은 점수면 이름이 맞은 쪽이 먼저 보이게. */
    final texts = <({String t, int bonus})>[(t: name, bonus: 2)];
    for (final tok in '${x['alias'] ?? ''}'.split(RegExp(r'\s+'))) {
      if (tok.isNotEmpty) texts.add((t: tok, bonus: 0));
    }
    var best = 0;
    var why = '';
    for (final c in cands) {
      for (final t in texts) {
        final r = _scoreText(c.j, t.t);
        if (r.s > 0) {
          final v = r.s + t.bonus;
          if (v > best) {
            best = v;
            why = c.tag != null ? 'qwerty' : r.why;
          }
        }
      }
    }
    if (cho) {
      for (final t in texts) {
        if (_chosung(t.t).contains(qn)) {
          final v = 85 + t.bonus;
          if (v > best) {
            best = v;
            why = 'chosung';
          }
        }
      }
    }
    if (best >= 50) rows.add((name: name, score: best, why: why, i: i));
  }
  /* 점수 → 짧은 이름 → 표의 순서. 마지막 단이 있어야 같은 점수의 순서가
     두 언어에서 같습니다. */
  rows.sort((a, b) {
    if (a.score != b.score) return b.score - a.score;
    final la = _normalize(a.name).length, lb = _normalize(b.name).length;
    if (la != lb) return la - lb;
    return a.i - b.i;
  });
  final n = jsTruthy(limit) ? jsToNumber(limit).toInt() : 8;
  final out = [
    for (final r in rows) {'name': r.name, 'score': r.score, 'why': r.why}
  ];
  return out.length > n ? out.sublist(0, n) : out;
}

List<Map<String, Object?>> byCat(Object? cat) => [
      for (final x0 in kFoodDb)
        if ((x0 as Map)['cat'] == cat) x0.cast<String, Object?>()
    ];

Map<String, Object?>? byName(Object? name) {
  for (final x0 in kFoodDb) {
    final x = (x0 as Map).cast<String, Object?>();
    if (x['name'] == name) return x;
  }
  return null;
}

/// 배수를 적용한 실제 섭취값. `mult || 1` 이라 0 은 1 이 됩니다.
Map<String, Object?> scaled(Map<String, Object?> food, [Object? mult]) {
  final m = jsTruthy(mult) ? jsToNumber(mult) : 1.0;
  return {
    'name': food['name'], 'unit': food['unit'], 'mult': m,
    'g': jsRound(jsToNumber(food['g']) * m),
    'kcal': jsRound(jsToNumber(food['kcal']) * m),
    'p': jsRound(jsToNumber(food['p']) * m * 10) / 10,
    'c': jsRound(jsToNumber(food['c']) * m * 10) / 10,
    'f': jsRound(jsToNumber(food['f']) * m * 10) / 10,
    'conf': food['conf'],
  };
}
