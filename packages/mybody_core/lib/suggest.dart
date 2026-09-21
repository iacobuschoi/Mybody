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
  final x = '× ${mult % 1 == 0 ? jsNumToString(mult) : toFixed(mult, 1)}';
  return base.isNotEmpty ? '$base $x' : x;
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
double _score(double totalP, double totalKcal, double needP, double aim) {
  final gap = needP - totalP;
  final pPenalty = gap > 0 ? gap * 10 : -gap * 0.5;
  final kPenalty = (totalKcal - aim).abs() / 100 * 3;
  return pPenalty + kPenalty;
}

/// 조합에서 단백질을 가장 많이 내는 품목 — 이 끼니의 주인공.
Object? _mainOf(List<Map<String, Object?>> items) {
  var best = items[0];
  for (final x in items) {
    if (jsToNumber(x['p']) > jsToNumber(best['p'])) best = x;
  }
  return best['name'];
}

List<Map<String, Object?>> _finish(
    List<Map<String, Object?>> cands, double needP, int limit, double aim) {
  for (final c in cands) {
    c['score'] = _score(jsToNumber(c['totalP']), jsToNumber(c['totalKcal']), needP, aim) +
        (jsTruthy(c['extra']) ? jsToNumber(c['extra']) : 0);
    c['coversPct'] =
        needP > 0 ? jsRound(jsToNumber(c['totalP']) / needP * 100) : 100;
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
     조합이 나란히 뜨면 선택지가 아니라 한 가지입니다. */
  final seenMain = <String>{};
  final out = <Map<String, Object?>>[];
  for (var i = 0; i < order.length && out.length < limit; i++) {
    final c = cands[order[i]];
    final m = '${_mainOf((c['items'] as List).cast<Map<String, Object?>>())}';
    if (!seenMain.add(m)) continue;
    c['main'] = m;
    out.add(c);
  }
  return out;
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
      final s1 = _scale(items[i], m);
      if (jsToNumber(s1['kcal']) > budget) continue;
      cands.add({'items': [s1], 'totalP': s1['p'], 'totalKcal': s1['kcal']});
    }
  }
  for (var i = 0; i < items.length; i++) {
    for (var j = i + 1; j < items.length; j++) {
      for (final a in kMults) {
        for (final b in kMults) {
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
  final out = _finish(cands, needP, limit, aim);
  return {
    'options': out, 'needP': needP, 'dayP': dayP, 'budget': budget, 'aim': aim,
    'ceiling': ceilingProtein(budget, opts['avoid']),
    'feasible': out.isNotEmpty && jsToNumber(out[0]['totalP']) >= needP * 0.9,
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
  final out = _finish(cands, needP, limit, aim);
  return {
    'options': out, 'needP': needP, 'dayP': dayP, 'budget': budget, 'aim': aim,
    'ceiling': ceilingProtein(budget, opts['avoid']),
    'feasible': out.isNotEmpty && jsToNumber(out[0]['totalP']) >= needP * 0.9,
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
  final out = _finish(cands, needP, limit, aim);
  return {
    'options': out, 'needP': needP, 'dayP': dayP, 'budget': budget, 'aim': aim,
    'ceiling': ceilingProtein(budget, opts['avoid']),
    'feasible': out.isNotEmpty && jsToNumber(out[0]['totalP']) >= needP * 0.9,
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
