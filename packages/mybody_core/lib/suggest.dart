/* =============================================================================
 * suggest.dart — "단백질 N그램 남았는데 뭘 먹지" (prototype/js/suggest.js 의 이식)
 *
 * 설계 원칙(왜 칼로리를 같이 보는지, 왜 못 채우면 못 채운다고 말하는지)은
 * 원본 주석에 있습니다. 여기서는 **옮기면서 달라질 뻔한 곳**만 적습니다.
 *
 *   · 후보를 만드는 **순서**가 결과의 일부입니다. 점수가 같은 조합이 흔한데,
 *     자바스크립트의 sort 는 안정 정렬이라 먼저 만든 것이 먼저 나옵니다.
 *     Dart 의 sort 는 그 보장이 없어서 같은 점수의 조합이 뒤바뀝니다 —
 *     화면에 다른 메뉴가 뜹니다. 그래서 명시적으로 안정화합니다.
 *   · 남은 칼로리가 없는 채로 부르면(undefined) 원본은 예산 검사를 전부
 *     통과시킵니다(NaN 비교는 거짓). 그 동작까지 옮깁니다 — 고치면 호출부가
 *     모르는 사이에 결과가 달라집니다.
 * ========================================================================== */
library;

import 'dart:math' as math;

import 'fooddb_data.dart';
import 'js_num.dart';

/// 1회 제공량에 단백질이 이보다 적으면 "목표를 채우는 수단" 이 아닙니다.
const double kMinProteinG = 5;

/// 한 품목을 몇 배까지 먹는다고 볼 것인가. 3배는 조합이 아니라 폭식입니다.
const List<double> kMults = [1, 1.5, 2];

const List<String> kSnackable = [
  '그릭요거트 무가당', '편의점 닭가슴살', '닭가슴살(조리·시판)',
  '참치캔(기름뺀)', '계란(삶음)', '두부(연두부)', '두유(무가당)', '우유', '저지방우유', '라떼',
  '아몬드', '땅콩버터', '바나나', '사과', '고구마(찐)', '삼각김밥', '통밀식빵',
  '프로틴 쉐이크(물)', '프로틴 쉐이크(우유)', '프로틴 쉐이크(저지방우유)',
  '프로틴 쉐이크(신타6·블렌드)',
  // 2026-09 추가 — 편의점에서 집어 먹는 단백질. "프로틴바가 없다" 는 말에서 시작했습니다.
  '프로틴바(일반) 1개', '프로틴바(저당) 1개', '프로틴바(고단백 20g) 1개',
  '단백질 음료(셀렉스) 1병', '단백질 음료(하이뮨) 1병',
  '스트링치즈 1개', '훈제란 1개', '닭가슴살 소시지 1개', '닭가슴살 스테이크(시판) 1팩', '코티지치즈 100g',
];

const List<String> kBase = [
  '공기밥(백미)', '현미밥', '잡곡밥', '반공기', '고구마(찐)', '감자(찐)',
  '통밀식빵', '오트밀(건조)',
];

const List<String> kMain = [
  '닭가슴살(생)', '닭가슴살(조리·시판)', '닭안심', '닭다리살 구이',
  '삼겹살 구이', '목살 구이', '소고기 등심', '소고기 우둔(살코기)', '돼지 뒷다리살',
  '계란(삶음)', '계란후라이', '고등어구이', '연어(생)',
  '두부(부침)', '두부(연두부)', '참치캔(기름뺀)', '회(광어) 1인분', '편의점 닭가슴살',
];

const List<String> kSide = [
  '배추김치', '시금치나물', '콩나물무침', '브로콜리 데침', '샐러드채소',
  '계란말이', '멸치볶음', '장조림', '어묵볶음', '미역국', '된장국',
];

/// 찌개는 밥 없이 나온 값입니다. 사먹기 추천에서는 공기밥을 같이 올립니다.
const List<String> kNeedsRice = ['김치찌개', '된장찌개', '순두부찌개', '부대찌개', '설렁탕', '갈비탕'];

const List<String> kAddOn = [
  '계란(삶음)', '편의점 닭가슴살', '두유(무가당)', '우유', '저지방우유',
  '그릭요거트 무가당', '프로틴 쉐이크(물)', '참치캔(기름뺀)',
];

const List<String> kOneDish = [
  '비빔밥', '제육덮밥', '돈까스덮밥', '김치볶음밥', '김밥', '참치김밥',
  '라면', '라면+계란', '짜장면', '짬뽕', '냉면(물)', '칼국수', '파스타(크림)', '파스타(오일)',
  '김치찌개', '된장찌개', '순두부찌개', '부대찌개', '설렁탕', '순대국밥', '갈비탕', '삼계탕',
  '편의점 도시락(일반)', '컵라면(소)', '서브웨이 15cm(치킨)', '백반(생선구이)',
  '치킨(후라이드) 반마리', '치킨(양념) 반마리', '피자 1조각', '햄버거(불고기)',
  '떡볶이 1인분', '만두(고기) 5개', '족발 1인분',
];

/* 빵·오트밀 바탕에 장조림·미역국을 붙이면 산술은 맞아도 아무도 그렇게 안 먹습니다. */
const List<String> kWesternBase = ['통밀식빵', '오트밀(건조)'];
const List<String> kKoreanSide = [
  '배추김치', '시금치나물', '콩나물무침', '계란말이',
  '멸치볶음', '장조림', '어묵볶음', '미역국', '된장국',
];

bool _pairs(Object? baseName, Object? sideName) =>
    !(kWesternBase.contains(baseName) && kKoreanSide.contains(sideName));

/// 100kcal 당 단백질. 이 값이 이 모듈의 핵심 지표입니다.
double density(Map<String, Object?> food) {
  final kcal = jsToNumber(food['kcal']);
  return kcal > 0 ? jsToNumber(food['p']) / kcal * 100 : 0;
}

/* --- 기름진 것과 담백한 것 --------------------------------------------------
 *
 * 2026-09 피드백: "족발·갈비탕이 뜬다". 조합의 지방 칼로리 비율(f×9/kcal)이
 * 상한을 넘거나 이름에 기름진 말이 있으면 뒤로 뺍니다 — 담백한 후보가 모자랄
 * 때만 뒤에 붙이고 shape 에 '지방 많음' 을 답니다. 담백한 이름에는 가산점.
 * 목록·상수는 원본(suggest.js)과 글자 단위로 같아야 합니다.
 * -------------------------------------------------------------------------- */

/// 조합 전체의 지방 칼로리 비율 상한. 1/3 을 넘으면 기름진 한 끼입니다.
const double kFatKcalMax = 0.33;

/// 이름에 이게 들어가면 숫자와 상관없이 기름진 것으로 봅니다(kFoodDb 이름 기준).
/// '치킨(' 은 후라이드·양념만 잡고 서브웨이(치킨)은 남깁니다.
const List<String> kGreasy = [
  '족발', '보쌈', '갈비', '삼겹살', '치킨(', '돈까스', '피자', '햄버거', '라면',
  '곱창', '튀김', '마요', '크림', '설렁탕', '순대', '부대', '제육', '후라이',
  '베이컨', '핫도그',
];

/// 담백한 조리·재료. 품목마다 kHealthyBonus 만큼 점수를 깎습니다(낮을수록 좋음).
const List<String> kHealthy = [
  '구이', '찜', '샐러드', '잡곡', '현미', '생선', '닭가슴살', '닭안심', '두부',
  '계란', '그릭', '고구마', '나물', '비빔밥', '회(', '오트밀', '참치캔',
  '살코기', '뒷다리', '연어', '브로콜리', '단백질 음료', '훈제란',
];
const double kHealthyBonus = 3;

/// 담백한 말이 붙어도 그 자체가 기름지면(계란후라이 0.74 · 계란말이 0.67 ·
/// 목살 구이 0.64) 가산점이 없습니다. 삶은 계란이 0.60 이라 그 바로 위에 선을 긋습니다.
const double kHealthyOwnFatMax = 0.62;

/// 회전용으로 모아 두는 상위 후보 수의 하한. 실제로는 max(이 값, limit×kRotateDays).
const int kRotatePoolMin = 8;

/// 며칠 만에 같은 세 줄이 돌아오는가. limit×3 이면 사흘째에 첫날 메뉴가 그대로
/// 돌아왔습니다(일·수·토 가 같은 세 줄). 한 주면 "매일 다른 것" 으로 읽힙니다.
const int kRotateDays = 7;

/// JS 의 `(x || 0)` — NaN·0·없음은 0 입니다.
double _num0(Object? v) {
  final n = jsToNumber(v);
  return (n.isNaN || n == 0) ? 0 : n;
}

bool _hasKw(Object? name, List<String> list) {
  final s = '$name';
  for (final k in list) {
    if (s.contains(k)) return true;
  }
  return false;
}

double _fatRatio(double f, double kcal) => kcal > 0 ? f * 9 / kcal : 0;

/// 이 조합이 기름진가 — 이름으로든 합계 숫자로든.
bool suggestIsGreasy(List<Map<String, Object?>> items) {
  var kc = 0.0, fat = 0.0;
  for (final x in items) {
    if (_hasKw(x['name'], kGreasy)) return true;
    kc += _num0(x['kcal']);
    fat += _num0(x['f']);
  }
  return _fatRatio(fat, kc) > kFatKcalMax;
}

int _healthyCount(List<Map<String, Object?>> items) {
  var n = 0;
  for (final x in items) {
    if (_hasKw(x['name'], kHealthy) &&
        _fatRatio(_num0(x['f']), _num0(x['kcal'])) <= kHealthyOwnFatMax) {
      n++;
    }
  }
  return n;
}

/* --- 회전 — 매일 다른 것을 ----------------------------------------------------
 *
 * 날짜(opts['seed'] = 'YYYY-MM-DD')를 씨앗으로 상위 후보 안에서 시작점만
 * 옮깁니다. DateTime 을 안 씁니다 — 원본과 정수 연산으로 똑같이 맞추려면
 * 산수만 남기는 게 안전합니다. 나누기는 원본의 Math.floor 와 같게 floor 로.
 * -------------------------------------------------------------------------- */

int? _intOf(String s) {
  if (s.isEmpty || s.length > 9) return null;
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    if (c < 0x30 || c > 0x39) return null;
  }
  return int.parse(s);
}

/// 'YYYY-MM-DD' → 1970-01-01 부터 센 날 수(days_from_civil). 모양이 아니면 null.
int? suggestDayNumber(Object? seed) {
  if (seed is! String) return null;
  final parts = seed.split('-');
  if (parts.length != 3) return null;
  final y0 = _intOf(parts[0]), m = _intOf(parts[1]), d = _intOf(parts[2]);
  if (y0 == null || m == null || d == null || m < 1 || m > 12 || d < 1 || d > 31) return null;
  final y = m <= 2 ? y0 - 1 : y0;
  final era = (y / 400).floor();
  final yoe = y - era * 400;
  final doy = ((153 * (m + (m > 2 ? -3 : 9)) + 2) / 5).floor() + d - 1;
  final doe = yoe * 365 + (yoe / 4).floor() - (yoe / 100).floor() + doy;
  return era * 146097 + doe - 719468;
}

int _gcd(int a, int b) {
  while (b != 0) {
    final t = a % b;
    a = b;
    b = t;
  }
  return a;
}

/// 날짜로 정한 자리에서 limit 개를 돌려 가며 고릅니다. 한 묶음(limit 개)씩
/// 건너뛰어서 어제 본 메뉴가 오늘 또 첫 줄에 서지 않습니다. 후보가 한 묶음
/// 이하면 한 칸씩만 밉니다. day 가 없으면 점수순 그대로입니다.
/// 보폭은 후보 수와 서로소로 잡습니다 — 후보가 9개에 보폭 3이면 시작점이
/// 0·3·6 세 자리뿐이라 사흘마다 같은 세 줄이었습니다. 서로소면 n 일 동안
/// 첫 줄이 전부 다릅니다.
List<Map<String, Object?>> _rotate(List<Map<String, Object?>> top, int limit, int? day) {
  final n = top.length, take = math.min(limit, n);
  if (day == null || n < 2) return top.sublist(0, take);
  var step = n > limit ? limit : 1;
  while (_gcd(step, n) != 1) step++;
  final start = ((day * step) % n + n) % n;
  return [for (var i = 0; i < take; i++) top[(start + i) % n]];
}

/* --- 분량 표기 — '1개 × 2' 는 '2개' ------------------------------------------ */

bool _isDigit(int c) => c >= 0x30 && c <= 0x39;
bool _isHangul(int c) => c >= 0xAC00 && c <= 0xD7A3;
bool _isLatin(int c) => (c >= 0x61 && c <= 0x7A) || (c >= 0x41 && c <= 0x5A);
bool _isQtyPrev(int c) => c == 0x20 || c == 0x2B || c == 0x28 || _isHangul(c);
bool _isQtyWord(String w) {
  if (w == 'g' || w == 'ml' || w == 'kg' || w == 'L') return true;
  for (var i = 0; i < w.length; i++) {
    if (!_isHangul(w.codeUnitAt(i))) return false;
  }
  return true;
}

/// '1개' × 2 → '2개', '100g' × 1.5 → '150g', '1팩100g' × 2 → '2팩200g'.
/// 단위 속 숫자 중 뒤에 셀 수 있는 말(개·컵·장·팩… 또는 g·ml·kg·L)이 붙은
/// 것만 곱합니다. '15cm' 같은 크기는 두고, '1/2모' 처럼 분수가 낀 것은 손대지
/// 않습니다. 하나라도 정수가 안 되면('1개' × 1.5) 빈 문자열 — 호출부가
/// '× 1.5' 로 돌아갑니다.
String suggestScaleUnit(String unit, double mult) {
  if (unit.isEmpty || unit.contains('/') || !(mult > 0)) return '';
  final sb = StringBuffer();
  var any = false, i = 0;
  final n = unit.length;
  while (i < n) {
    final c = unit.codeUnitAt(i);
    if (_isDigit(c) && (i == 0 || _isQtyPrev(unit.codeUnitAt(i - 1)))) {
      var j = i;
      while (j < n && _isDigit(unit.codeUnitAt(j))) j++;
      var k = j;
      while (k < n && (_isHangul(unit.codeUnitAt(k)) || _isLatin(unit.codeUnitAt(k)))) k++;
      if (k > j && _isQtyWord(unit.substring(j, k))) {
        final v = int.parse(unit.substring(i, j)) * mult;
        if (v % 1 != 0) return '';
        sb.write(jsNumToString(v));
        any = true;
        i = j;
        continue;
      }
    }
    sb.writeCharCode(c);
    i++;
  }
  return any ? sb.toString() : '';
}

/// 단위의 첫 수량 토큰 — '1팩 100g' → '1팩', '1개' → '1개', '100g' → ''(셀 수 없음).
String suggestCountToken(String unit) {
  var i = 0;
  final n = unit.length;
  while (i < n) {
    final c = unit.codeUnitAt(i);
    if (_isDigit(c) && (i == 0 || _isQtyPrev(unit.codeUnitAt(i - 1)))) {
      var j = i;
      while (j < n && _isDigit(unit.codeUnitAt(j))) j++;
      var k = j;
      while (k < n && _isHangul(unit.codeUnitAt(k))) k++;
      if (k > j) return unit.substring(i, k);
      i = j;
      continue;
    }
    i++;
  }
  return '';
}

/// 이 배수로 먹는다고 볼 수 있는가. 정수가 아닌 배수는 단위의 말로 적을 수 있을 때만
/// ('100g' → '150g', '2쪽' → '3쪽'). '계란 1개 × 1.5' · '1/2모 × 1.5' 는 먹는 양이
/// 아닙니다 — 말할 수 없는 분량은 권하지 않습니다.
bool _multOk(Map<String, Object?> food, double mult) {
  if (mult % 1 == 0) return true;
  return suggestScaleUnit(food['unit'] == null ? '' : '${food['unit']}', mult).isNotEmpty;
}

Map<String, Object?> _scale(Map<String, Object?> food, double mult) {
  return {
    'name': food['name'], 'unit': food['unit'], 'cat': food['cat'],
    'conf': food['conf'], 'mult': mult,
    'g': jsRound(jsToNumber(food['g']) * mult),
    'kcal': jsRound(jsToNumber(food['kcal']) * mult),
    'p': jsRound(jsToNumber(food['p']) * mult * 10) / 10,
    'c': jsRound(jsToNumber(food['c']) * mult * 10) / 10,
    'f': jsRound(jsToNumber(food['f']) * mult * 10) / 10,
  };
}

/// 사람이 읽는 분량 표기. "1.5배" 가 아니라 단위로 풀어씁니다.
String portionText(Map<String, Object?> item) {
  final name = '${item['name']}';
  final unit = '${item['unit']}';
  // 이름이 이미 분량을 품고 있으면(만두(고기) 5개) 또 붙이지 않습니다.
  final dup = jsTruthy(item['name']) && name.contains(unit);
  final base = dup ? '' : unit;
  final mult = jsToNumber(item['mult']);
  if (item['mult'] == 1) return base;
  if (item['mult'] == 0.5) return (base.isNotEmpty ? '$base ' : '') + '반';
  // '1개 × 2' 보다 '2개' 가 사람 말입니다 — 단위가 셀 수 있는 것일 때만.
  final scaled = base.isNotEmpty ? suggestScaleUnit(base, mult) : '';
  if (scaled.isNotEmpty) return scaled;
  final x = '× ${mult % 1 == 0 ? jsNumToString(mult) : toFixed(mult, 1)}';
  return base.isNotEmpty ? '$base $x' : x;
}

/// 화면에 쓰는 한 품목의 글 — 이름 + 분량. 이름 끝이 단위의 수량('훈제란 1개' 의
/// '1개' · '닭가슴살 스테이크(시판) 1팩' 의 '1팩')이면 그 수량을 이름에서 떼고 단위로
/// 다시 말합니다: '훈제란 1개 55g', ×2 는 '훈제란 2개 110g'. 안 떼면 '훈제란 1개 1개 55g'
/// 이나 '훈제란 1개 2개 110g' 처럼 두 숫자가 한 줄에 섭니다. 이름이 단위 전체로
/// 끝나면(코티지치즈 100g) 그것도 떼어 '코티지치즈 200g'.
String itemText(Map<String, Object?> item) {
  final name = item['name'] == null ? '' : '${item['name']}';
  final unit = item['unit'] == null ? '' : '${item['unit']}';
  var suffix = '';
  if (unit.isNotEmpty && name.length > unit.length && name.endsWith(unit)) {
    suffix = unit;
  } else {
    final tok = suggestCountToken(unit);
    if (tok.isNotEmpty && name.length > tok.length && name.endsWith(tok)) suffix = tok;
  }
  if (suffix.isEmpty) return '$name ${portionText(item)}'.trim();
  final head = name.substring(0, name.length - suffix.length).replaceFirst(RegExp(r'\s+$'), '');
  final pt = portionText({'name': head, 'unit': unit, 'mult': item['mult']});
  return '$head $pt'.trim();
}

List<Map<String, Object?>> _pool(List<String> role, Object? avoid) {
  final skip = <String>{};
  if (avoid is List) {
    for (final n in avoid) skip.add('$n');
  }
  return [
    for (final x0 in kFoodDb)
      if (!skip.contains('${(x0 as Map)['name']}') && role.contains(x0['name']))
        x0.cast<String, Object?>()
  ];
}

/// 남은 칼로리로 이론상 채울 수 있는 단백질 상한.
/// 가장 밀도 높은 음식만 먹었다는 가정입니다.
num ceilingProtein(double remainKcal, Object? avoid) {
  if (remainKcal <= 0) return 0;
  var best = 0.0;
  for (final x in _pool([...kMain, ...kSnackable], avoid)) {
    if (jsToNumber(x['p']) >= kMinProteinG) {
      final d = density(x);
      if (d > best) best = d;
    }
  }
  return jsRound(remainKcal * best / 100);
}

/// 조합 점수. **낮을수록 좋습니다.**
///
/// 칼로리는 "적을수록 좋은 것" 이 아니라 "맞출 것" 입니다 — 이유는 원본 주석에.
double _score(double totalP, double totalKcal, double needP, double aim, [double over = 0]) {
  final gap = needP - totalP;
  final pPenalty = gap > 0 ? gap * 10 : -gap * 0.5;
  final kPenalty = (totalKcal - aim).abs() / 100 * 3;
  /* 탄수·지방은 오늘 남은 양을 **넘긴 만큼만** 벌줍니다(g당 0.5). 남은 양
     안에 드는 조합을 앞에 세우려는 것이지, 탄수를 적게 먹으라는 게
     아닙니다. 예산을 안 주면 예전과 같습니다. */
  final cfPenalty = over * 0.5;
  return pPenalty + kPenalty + cfPenalty;
}

/// 오늘 남은 탄수·지방(opts['remainC'] / ['remainF'])을 이 조합이 얼마나 넘기는가(g).
double _overBudget(List<Map<String, Object?>> items, Map<String, Object?>? opts) {
  if (opts == null) return 0;
  var over = 0.0;
  double g(Object? v) {
    final n = jsToNumber(v);
    return (n.isNaN || n == 0) ? 0 : n;   // JS 의 (x.c || 0) 와 같습니다
  }
  if (opts['remainC'] != null) {
    var sc = 0.0;
    for (final x in items) {
      sc += g(x['c']);
    }
    over += math.max(0.0, sc - jsToNumber(opts['remainC']));
  }
  if (opts['remainF'] != null) {
    var sf = 0.0;
    for (final x in items) {
      sf += g(x['f']);
    }
    over += math.max(0.0, sf - jsToNumber(opts['remainF']));
  }
  return over;
}

/// 조합에서 단백질을 가장 많이 내는 품목 — 이 끼니의 주인공.
Object? _mainOf(List<Map<String, Object?>> items) {
  var best = items[0];
  for (final x in items) {
    if (jsToNumber(x['p']) > jsToNumber(best['p'])) best = x;
  }
  return best['name'];
}

/// 사먹기의 주인공은 메뉴판의 단품(첫 품목)입니다 — 단백질이 제일 많은 것으로 고르면
/// 편의점 닭가슴살 · 참치캔이 주인공이 되어 '순두부찌개+닭가슴살' 과 '순두부찌개+참치캔'
/// 이 서로 다른 선택지로 통과합니다. 한 날 세 줄 중 둘이 순두부찌개였습니다.
Object? _dishOf(List<Map<String, Object?>> items) => items[0]['name'];

/// [mainKey] 는 조합의 주인공 이름 — 같은 주인공은 한 번만 보입니다(기본 _mainOf).
List<Map<String, Object?>> _finish(
    List<Map<String, Object?>> cands, double needP, int limit, double aim,
    [Map<String, Object?>? opts, Object? Function(List<Map<String, Object?>>)? mainKey]) {
  final keyOf = mainKey ?? _mainOf;
  for (final c in cands) {
    final items = (c['items'] as List).cast<Map<String, Object?>>();
    c['score'] = _score(jsToNumber(c['totalP']), jsToNumber(c['totalKcal']), needP, aim,
            _overBudget(items, opts)) +
        (jsTruthy(c['extra']) ? jsToNumber(c['extra']) : 0) -
        _healthyCount(items) * kHealthyBonus;
    c['coversPct'] =
        needP > 0 ? jsRound(jsToNumber(c['totalP']) / needP * 100) : 100;
    c['greasy'] = suggestIsGreasy(items);
  }
  /* **안정 정렬.** 점수가 같은 조합이 흔한데(같은 반찬만 바뀐 것들),
     순서가 바뀌면 화면에 다른 메뉴가 뜹니다. */
  final order = List<int>.generate(cands.length, (i) => i);
  order.sort((a, b) {
    final c = jsToNumber(cands[a]['score']) - jsToNumber(cands[b]['score']);
    if (c < 0) return -1;
    if (c > 0) return 1;
    return a - b;       // NaN 도 여기로 옵니다 — JS 가 순서를 지키는 것과 같습니다
  });

  /* 주요리가 서로 다른 것만 고릅니다. 같은 음식의 배수 차이나 반찬만 바꾼
     조합이 나란히 뜨면 선택지가 아니라 한 가지입니다.
     담백한 것부터, 회전할 수 있게 넉넉히 모읍니다. */
  final poolSize = math.max(kRotatePoolMin, limit * kRotateDays);
  final seenMain = <String>{};
  final top = <Map<String, Object?>>[];
  for (var i = 0; i < order.length && top.length < poolSize; i++) {
    final c = cands[order[i]];
    if (c['greasy'] == true) continue;
    final m = '${keyOf((c['items'] as List).cast<Map<String, Object?>>())}';
    if (!seenMain.add(m)) continue;
    c['main'] = m;
    top.add(c);
  }
  /* 회전은 "충분히 좋은 것" 안에서만 돕니다. 아홉째 후보가 단백질을 반만
     채우면 그날은 추천이 나쁜 날이 됩니다. 이번 몫의 90% 를 채우는 것이
     한 묶음 이상이면 그 안에서 돌고, 아니면 점수순 그대로입니다. */
  final good = [for (final c in top) if (jsToNumber(c['totalP']) >= needP * 0.9) c];
  final out = good.length >= limit
      ? _rotate(good, limit, suggestDayNumber(opts?['seed']))
      : top.sublist(0, math.min(limit, top.length));

  // 담백한 후보가 모자랄 때만 기름진 것을 뒤에 붙입니다 — 표시를 달고.
  for (var i = 0; i < order.length && out.length < limit; i++) {
    final c = cands[order[i]];
    if (c['greasy'] != true) continue;
    final m = '${keyOf((c['items'] as List).cast<Map<String, Object?>>())}';
    if (!seenMain.add(m)) continue;
    c['main'] = m;
    c['shape'] = jsTruthy(c['shape']) ? '${c['shape']} · 지방 많음' : '지방 많음';
    out.add(c);
  }
  return out;
}

/// 보이는 것 중 하나라도 이번 몫의 90% 를 채우면 "채울 수 있다" 입니다.
/// (회전하면 첫 줄이 최고점이 아니라서 첫 줄만 볼 수 없습니다.)
bool _feasible(List<Map<String, Object?>> out, double needP) {
  for (final o in out) {
    if (jsToNumber(o['totalP']) >= needP * 0.9) return true;
  }
  return false;
}

double _optNum(Map<String, Object?> o, String k) => jsNum(o, k);
int _limitOf(Map<String, Object?> o) =>
    jsTruthy(o['limit']) ? jsToNumber(o['limit']).toInt() : 3;

/* --- 간식 — 조리 없이, 한두 가지로 --------------------------------------- */

Map<String, Object?> suggestSnack(Map<String, Object?> opts) {
  final dayP = math.max(0.0, jsTruthy(opts['remainP']) ? jsToNumber(opts['remainP']) : 0.0);
  final budget = _optNum(opts, 'remainKcal');
  final limit = _limitOf(opts);
  if (dayP <= 0) return {'done': true, 'options': <Object?>[]};
  if (budget <= 0) return {'overBudget': true, 'needP': dayP, 'options': <Object?>[]};
  /* 간식 하나가 하루치 단백질을 다 짊어질 수는 없습니다. */
  final needP = math.min(dayP, jsTruthy(opts['aimP']) ? jsToNumber(opts['aimP']) : 30.0);

  final items = _pool(kSnackable, opts['avoid'])
      .where((x) => jsToNumber(x['p']) >= kMinProteinG)
      .toList();
  final cands = <Map<String, Object?>>[];

  for (var i = 0; i < items.length; i++) {
    for (final m in kMults) {
      if (!_multOk(items[i], m)) continue;
      final s1 = _scale(items[i], m);
      if (jsToNumber(s1['kcal']) > budget) continue;
      cands.add({'items': [s1], 'totalP': s1['p'], 'totalKcal': s1['kcal']});
    }
  }
  for (var i = 0; i < items.length; i++) {
    for (var j = i + 1; j < items.length; j++) {
      for (final a in kMults) {
        if (!_multOk(items[i], a)) continue;
        for (final b in kMults) {
          if (!_multOk(items[j], b)) continue;
          final x1 = _scale(items[i], a), x2 = _scale(items[j], b);
          final kc = jsToNumber(x1['kcal']) + jsToNumber(x2['kcal']);
          if (kc > budget) continue;
          final p = jsRound((jsToNumber(x1['p']) + jsToNumber(x2['p'])) * 10) / 10;
          if (p < needP * 0.4) continue;
          cands.add({'items': [x1, x2], 'totalP': p, 'totalKcal': kc});
        }
      }
    }
  }
  // 간식은 하루의 일부입니다. 남은 예산을 다 쓰면 끼니가 없어집니다.
  final aim = math.min(budget, 250.0);
  final out = _finish(cands, needP, limit, aim, opts);
  return {
    'options': out, 'needP': needP, 'dayP': dayP, 'budget': budget, 'aim': aim,
    'ceiling': ceilingProtein(budget, opts['avoid']),
    'feasible': _feasible(out, needP),
  };
}

/* --- 사먹기 — 점심·저녁은 대개 밖에서 먹습니다 --------------------------- */

Map<String, Object?> suggestEatOut(Map<String, Object?> opts) {
  final dayP = math.max(0.0, jsTruthy(opts['remainP']) ? jsToNumber(opts['remainP']) : 0.0);
  final budget = _optNum(opts, 'remainKcal');
  final limit = _limitOf(opts);
  if (dayP <= 0) return {'done': true, 'options': <Object?>[]};
  if (budget <= 0) return {'overBudget': true, 'needP': dayP, 'options': <Object?>[]};
  final mealsLeft = math.max(1.0, jsTruthy(opts['mealsLeft']) ? jsToNumber(opts['mealsLeft']) : 1.0);
  final needP = jsTruthy(opts['aimP']) ? jsToNumber(opts['aimP']) : jsRound(dayP / mealsLeft).toDouble();

  Map<String, Object?>? rice;
  for (final x0 in kFoodDb) {
    if ((x0 as Map)['name'] == '공기밥(백미)') {
      rice = x0.cast<String, Object?>();
      break;
    }
  }

  final dishes = _pool(kOneDish, opts['avoid']);
  final addons = _pool(kAddOn, opts['avoid']);
  final cands = <Map<String, Object?>>[];

  for (final d in dishes) {
    final items = <Map<String, Object?>>[_scale(d, 1)];
    if (kNeedsRice.contains(d['name']) && rice != null) items.add(_scale(rice, 1));
    var kc = 0.0, pSum = 0.0;
    for (final x in items) {
      kc += jsToNumber(x['kcal']);
      pSum += jsToNumber(x['p']);
    }
    final pp = jsRound(pSum * 10) / 10;
    if (kc > budget) continue;
    /* 사먹을 때는 "숫자를 맞췄는가" 보다 "메뉴가 단백질이 좋은가" 가 중요합니다.
       이게 없으면 파스타에 프로틴 쉐이크를 얹는 조합이 갈비탕을 이깁니다. */
    final dishPenalty = math.max(0.0, 8 - density(d)) * 3;
    cands.add({'items': items, 'totalP': pp, 'totalKcal': kc,
               'shape': '단품', 'extra': dishPenalty});

    // 단품 하나로 모자라면 옆에 하나 더. 두 개까지만.
    if (pp >= needP * 0.95) continue;
    for (final a in addons) {
      for (final m in kMults) {
        if (!_multOk(a, m)) continue;
        final ad = _scale(a, m);
        final kc2 = kc + jsToNumber(ad['kcal']);
        if (kc2 > budget) continue;
        final p2 = jsRound((pp + jsToNumber(ad['p'])) * 10) / 10;
        cands.add({'items': [...items, ad], 'totalP': p2, 'totalKcal': kc2,
                   'shape': '단품 + 추가', 'extra': dishPenalty + 8});
      }
    }
  }

  var aim = jsTruthy(opts['aimKcal'])
      ? jsToNumber(opts['aimKcal'])
      : math.min<num>(budget, jsRound(budget / mealsLeft)).toDouble();
  if (aim > 900) aim = 900;
  final out = _finish(cands, needP, limit, aim, opts, _dishOf);
  return {
    'options': out, 'needP': needP, 'dayP': dayP, 'budget': budget, 'aim': aim,
    'ceiling': ceilingProtein(budget, opts['avoid']),
    'feasible': _feasible(out, needP),
  };
}

/* --- 집밥 한 끼 — 실제 상차림 형태로 ------------------------------------- */

Map<String, Object?> suggestMeal(Map<String, Object?> opts) {
  final dayP = math.max(0.0, jsTruthy(opts['remainP']) ? jsToNumber(opts['remainP']) : 0.0);
  final budget = _optNum(opts, 'remainKcal');
  final limit = _limitOf(opts);
  if (dayP <= 0) return {'done': true, 'options': <Object?>[]};
  if (budget <= 0) return {'overBudget': true, 'needP': dayP, 'options': <Object?>[]};
  final mealsLeft = math.max(1.0, jsTruthy(opts['mealsLeft']) ? jsToNumber(opts['mealsLeft']) : 1.0);
  final needP = jsTruthy(opts['aimP']) ? jsToNumber(opts['aimP']) : jsRound(dayP / mealsLeft).toDouble();

  final bases = _pool(kBase, opts['avoid']);
  final mains = _pool(kMain, opts['avoid']);
  final sides = _pool(kSide, opts['avoid']);
  final cands = <Map<String, Object?>>[];

  // 밥 + 주요리 (+ 반찬 하나)
  for (var bi = 0; bi < bases.length; bi++) {
    for (var mi = 0; mi < mains.length; mi++) {
      for (final mult in kMults) {
        if (!_multOk(mains[mi], mult)) continue;
        final base = _scale(bases[bi], 1);
        final main = _scale(mains[mi], mult);
        final kc2 = jsToNumber(base['kcal']) + jsToNumber(main['kcal']);
        if (kc2 > budget) continue;
        final p2 = jsRound((jsToNumber(base['p']) + jsToNumber(main['p'])) * 10) / 10;
        cands.add({'items': [base, main], 'totalP': p2, 'totalKcal': kc2, 'shape': '밥+주요리'});

        for (var si = 0; si < sides.length; si++) {
          if (!_pairs(base['name'], sides[si]['name'])) continue;
          final side = _scale(sides[si], 1);
          final kc3 = kc2 + jsToNumber(side['kcal']);
          if (kc3 > budget) continue;
          final p3 = jsRound((p2 + jsToNumber(side['p'])) * 10) / 10;
          cands.add({'items': [base, main, side], 'totalP': p3, 'totalKcal': kc3,
                     'shape': '밥+주요리+반찬'});
        }
      }
    }
  }

  var aim = jsTruthy(opts['aimKcal'])
      ? jsToNumber(opts['aimKcal'])
      : math.min<num>(budget, jsRound(budget / mealsLeft)).toDouble();
  if (aim > 900) aim = 900;
  final out = _finish(cands, needP, limit, aim, opts);
  return {
    'options': out, 'needP': needP, 'dayP': dayP, 'budget': budget, 'aim': aim,
    'ceiling': ceilingProtein(budget, opts['avoid']),
    'feasible': _feasible(out, needP),
  };
}

/// 화면에 쓸 한 줄. **상태를 말할 뿐 명령하지 않습니다.**
Map<String, Object?> summaryText(Map<String, Object?> res) {
  if (jsTruthy(res['done'])) return {'tone': 'ok', 'text': '오늘 단백질 목표를 다 채웠습니다.'};
  if (jsTruthy(res['overBudget'])) {
    return {
      'tone': 'warn',
      'text': '단백질은 ${jsNumToString(jsRound(jsNum(res, 'needP')))}g 남았지만 칼로리는 다 썼습니다.',
      'detail': '오늘은 여기까지 두는 편이 낫습니다. 내일은 아침부터 나눠 담으면 수월합니다.',
    };
  }
  final options = res['options'] as List;
  if (options.isEmpty) {
    return {
      'tone': 'warn', 'text': '남은 칼로리로 만들 조합이 없습니다.',
      'detail': '남은 ${jsNumToString(jsRound(jsNum(res, 'budget')))}kcal 로는 단백질 '
          '${jsNumToString(jsRound(jsNum(res, 'ceiling')))}g 정도가 한계입니다.',
    };
  }
  if (!jsTruthy(res['feasible'])) {
    /* 왜 못 채우는지를 구분합니다. 칼로리가 모자란 것과 한 끼로는 담을 수 없는
       것은 다른 문제이고, 사용자가 할 일도 다릅니다. */
    if (jsNum(res, 'ceiling') < jsNum(res, 'needP')) {
      return {
        'tone': 'warn',
        'text': '남은 칼로리로는 단백질 ${jsNumToString(jsRound(jsNum(res, 'ceiling')))}g 까지가 한계입니다.',
        'detail': '아래는 칼로리를 넘기지 않는 선에서 가장 많이 채우는 조합입니다.',
      };
    }
    return {
      'tone': '', 'text': '한 번에 다 채우기는 어렵습니다.',
      'detail': '아래는 이번에 채울 수 있는 만큼입니다. 나머지는 다음 끼니로 넘기면 됩니다.',
    };
  }
  final dayP = res['dayP'], needP = jsNum(res, 'needP');
  final restNote = (jsTruthy(dayP) && jsToNumber(dayP) > needP)
      ? '하루 남은 ${jsNumToString(jsRound(jsToNumber(dayP)))}g 중 이번 몫 '
          '${jsNumToString(jsRound(needP))}g 기준입니다.'
      : '남은 ${jsNumToString(jsRound(needP))}g · '
          '${jsNumToString(jsRound(jsNum(res, 'budget')))}kcal 안에서 골랐습니다.';
  return {'tone': '', 'text': '이렇게 채울 수 있습니다.', 'detail': restNote};
}
