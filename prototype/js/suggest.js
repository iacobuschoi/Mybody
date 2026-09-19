/* =============================================================================
 * suggest.js — "단백질 N그램 남았는데 뭘 먹지"에 답하는 모듈
 *
 * 식단 탭은 "단백질 40g 남음"까지만 알려주고 끝났습니다. 그런데 초보자에게
 * 어려운 건 남은 양을 아는 게 아니라 그걸 음식으로 번역하는 일입니다.
 * 40g 을 채우려면 닭가슴살 한 팩 반인지 계란 여섯 개인지 계산해야 하는데,
 * 그 계산이 하루 세 번 필요하니까 사람들이 포기합니다.
 *
 * 설계 원칙
 *  1. 칼로리를 같이 본다. 단백질만 보면 삼겹살 2인분(단백 34g / 780kcal)이
 *     정답이 되는데, 하루 예산을 통째로 날리는 답입니다.
 *     핵심 지표는 "100kcal 당 단백질"입니다.
 *  2. 못 채우면 못 채운다고 말한다. 남은 칼로리로 도달 불가능하면 억지 조합을
 *     지어내지 않고 얼마까지 가능한지를 말합니다. 이 앱의 다른 부분(플랜 거부,
 *     노이즈 플로어)과 같은 규칙입니다.
 *  3. 사람이 실제로 먹는 양과 형태만. 한 품목 2배까지, 그리고 한 끼는
 *     밥+단백질+반찬처럼 실제 상차림이어야 합니다. "닭안심 2인분 + 요거트"는
 *     산술적으로는 최적이지만 끼니가 아닙니다.
 *  4. 간식과 한 끼는 칼로리가 아니라 형태로 나눈다. 고등어구이 183kcal 은
 *     칼로리는 간식이지만 구워야 하는 끼니입니다.
 *  5. 명령하지 않는다. "이걸 드세요"가 아니라 "이렇게 채울 수 있습니다"입니다.
 * ========================================================================== */
(function (global) {
  'use strict';

  /* 1회 제공량에 단백질이 이보다 적으면 "목표를 채우는 수단"이 아닙니다. */
  var MIN_PROTEIN_G = 5;

  /* 한 품목을 몇 배까지 먹는다고 볼 것인가. 3배는 조합이 아니라 폭식입니다. */
  var MULTS = [1, 1.5, 2];

  /* ---------------------------------------------------------------------- */
  /* 음식의 역할                                                             */
  /*                                                                         */
  /* 이름으로 추론하지 않고 명시적으로 적습니다. "구이가 들어가면 메인" 같은  */
  /* 규칙은 새 음식이 들어올 때마다 조용히 틀리기 때문입니다.                */
  /* 새 음식을 추가하면 여기에도 한 줄 넣어야 합니다 — 안 넣으면 추천에      */
  /* 안 나오지 기록이 막히지는 않습니다.                                      */
  /* ---------------------------------------------------------------------- */

  /** 조리 없이 집어 먹을 수 있는 것. 간식 추천은 여기서만 고릅니다. */
  var SNACKABLE = [
    '그릭요거트 무가당', '프로틴 1스쿱', '편의점 닭가슴살', '닭가슴살(조리·시판)',
    '참치캔(기름뺀)', '계란(삶음)', '두부(연두부)', '두유(무가당)', '우유', '라떼',
    '아몬드', '땅콩버터', '바나나', '사과', '고구마(찐)', '삼각김밥', '통밀식빵'
  ];

  /** 밥·빵 같은 탄수 바탕. 한 끼의 기초가 됩니다. */
  var BASE = ['공기밥(백미)', '현미밥', '잡곡밥', '반공기', '고구마(찐)', '감자(찐)',
              '통밀식빵', '오트밀(건조)'];

  /** 한 끼의 주요리. 단백질을 실어 나르는 자리입니다. */
  var MAIN = [
    '닭가슴살(생)', '닭가슴살(조리·시판)', '닭안심', '닭다리살 구이',
    '삼겹살 구이', '목살 구이', '소고기 등심', '소고기 우둔(살코기)', '돼지 뒷다리살',
    '계란(삶음)', '계란후라이', '고등어구이', '연어(생)',
    '두부(부침)', '두부(연두부)', '참치캔(기름뺀)', '회(광어) 1인분', '편의점 닭가슴살'
  ];

  /** 곁들이는 것. 칼로리를 크게 안 쓰면서 상을 완성합니다. */
  var SIDE = ['배추김치', '시금치나물', '콩나물무침', '브로콜리 데침', '샐러드채소',
              '계란말이', '멸치볶음', '장조림', '어묵볶음', '미역국', '된장국'];

  /** 그 자체로 한 끼가 되는 것. 다른 것과 묶지 않습니다. */
  var ONE_DISH = [
    '비빔밥', '제육덮밥', '돈까스덮밥', '김치볶음밥', '김밥', '참치김밥',
    '라면', '라면+계란', '짜장면', '짬뽕', '냉면(물)', '칼국수', '파스타(크림)', '파스타(오일)',
    '김치찌개', '된장찌개', '순두부찌개', '부대찌개', '설렁탕', '순대국밥', '갈비탕', '삼계탕',
    '편의점 도시락(일반)', '컵라면(소)', '서브웨이 15cm(치킨)', '백반(생선구이)',
    '치킨(후라이드) 반마리', '치킨(양념) 반마리', '피자 1조각', '햄버거(불고기)',
    '떡볶이 1인분', '만두(고기) 5개', '족발 1인분'
  ];

  /* 빵·오트밀 바탕에 장조림·미역국을 붙이면 산술은 맞아도 아무도 그렇게 안 먹습니다.
   * 문화적 제약은 점수로 표현하기 어려워서 그냥 못 붙이게 합니다. */
  var WESTERN_BASE = ['통밀식빵', '오트밀(건조)'];
  var KOREAN_SIDE = ['배추김치', '시금치나물', '콩나물무침', '계란말이',
                     '멸치볶음', '장조림', '어묵볶음', '미역국', '된장국'];

  function inList(list, name) { return list.indexOf(name) >= 0; }

  function pairs(baseName, sideName) {
    if (inList(WESTERN_BASE, baseName) && inList(KOREAN_SIDE, sideName)) return false;
    return true;
  }
  function density(food) { return food.kcal > 0 ? food.p / food.kcal * 100 : 0; }

  function scale(food, mult) {
    return {
      name: food.name, unit: food.unit, cat: food.cat, conf: food.conf, mult: mult,
      g: Math.round(food.g * mult),
      kcal: Math.round(food.kcal * mult),
      p: Math.round(food.p * mult * 10) / 10,
      c: Math.round(food.c * mult * 10) / 10,
      f: Math.round(food.f * mult * 10) / 10
    };
  }

  /** 사람이 읽는 분량 표기. "1.5배"가 아니라 단위로 풀어씁니다. */
  function portionText(item) {
    if (item.mult === 1) return item.unit;
    if (item.mult === 0.5) return item.unit + ' 반';
    return item.unit + ' × ' + (item.mult % 1 === 0 ? item.mult : item.mult.toFixed(1));
  }

  function pool(role, avoid) {
    var F = global.MB_FOOD;
    var skip = {};
    (avoid || []).forEach(function (n) { skip[n] = true; });
    return F.FOODS.filter(function (x) {
      if (skip[x.name]) return false;          // 오늘 이미 먹은 건 또 권하지 않습니다
      return inList(role, x.name);
    });
  }

  /** 남은 칼로리로 이론상 채울 수 있는 단백질 상한. 가장 밀도 높은 음식만 먹었다는 가정. */
  function ceilingProtein(remainKcal, avoid) {
    if (remainKcal <= 0) return 0;
    var best = 0;
    pool(MAIN.concat(SNACKABLE), avoid).forEach(function (x) {
      if (x.p >= MIN_PROTEIN_G) { var d = density(x); if (d > best) best = d; }
    });
    return Math.round(remainKcal * best / 100);
  }

  /**
   * 조합 점수. 낮을수록 좋습니다.
   *
   * 칼로리는 "적을수록 좋은 것"이 아니라 "맞출 것"입니다. 줄이는 쪽으로만 점수를
   * 주면 단백질만 맞춘 뒤 제일 싼 탄수를 고르게 되어, 모든 한 끼 추천이
   * 감자 + 참치캔이 됩니다. 한국 저녁상이 아닙니다. 그리고 계획은 사용자가
   * 목표 칼로리를 먹는다고 가정하므로, 덜 먹는 것도 계획에서 벗어나는 일입니다.
   *
   * @param aim 이번 끼니가 겨냥하는 칼로리
   */
  function score(totalP, totalKcal, needP, aim) {
    var gap = needP - totalP;
    // 모자란 건 크게 벌줍니다. 넘치는 건 거의 벌주지 않습니다 —
    // 칼로리 안에서 단백질이 좀 넘치는 건 나쁜 일이 아닌데, 예전엔 2배로 벌줘서
    // 삼계탕·설렁탕 같은 단품 한 끼가 한 번도 추천되지 않았습니다.
    var pPenalty = gap > 0 ? gap * 10 : -gap * 0.5;
    var kPenalty = Math.abs(totalKcal - aim) / 100 * 3;
    return pPenalty + kPenalty;
  }

  /** 조합에서 단백질을 가장 많이 내는 품목 — 이 끼니의 주인공 */
  function mainOf(items) {
    var best = items[0];
    items.forEach(function (x) { if (x.p > best.p) best = x; });
    return best.name;
  }

  function finish(cands, needP, limit, aim) {
    cands.forEach(function (c) {
      c.score = score(c.totalP, c.totalKcal, needP, aim);
      c.coversPct = needP > 0 ? Math.round(c.totalP / needP * 100) : 100;
    });
    cands.sort(function (a, b) { return a.score - b.score; });

    // 주요리가 서로 다른 것만 고릅니다.
    // 같은 음식의 배수 차이나 반찬만 바꾼 조합이 나란히 뜨면 선택지가 아니라 한 가지입니다.
    var seenMain = {}, out = [];
    for (var i = 0; i < cands.length && out.length < limit; i++) {
      var m = mainOf(cands[i].items);
      if (seenMain[m]) continue;
      seenMain[m] = true;
      cands[i].main = m;
      out.push(cands[i]);
    }
    return out;
  }

  /* ---------------------------------------------------------------------- */
  /* 간식 — 조리 없이, 한두 가지로                                           */
  /* ---------------------------------------------------------------------- */
  function suggestSnack(opts) {
    var dayP = Math.max(0, opts.remainP || 0);
    var budget = opts.remainKcal;
    var limit = opts.limit || 3;
    if (dayP <= 0) return { done: true, options: [] };
    if (budget <= 0) return { overBudget: true, needP: dayP, options: [] };
    // 간식 하나가 하루치 단백질을 다 짊어질 수는 없습니다.
    // 아침에 160g 이 남았다고 160g 짜리 간식을 찾으면 답이 없다고 나옵니다.
    var needP = Math.min(dayP, opts.aimP || 30);

    var items = pool(SNACKABLE, opts.avoid).filter(function (x) { return x.p >= MIN_PROTEIN_G; });
    var cands = [], i, j, a, b;

    for (i = 0; i < items.length; i++) {
      for (a = 0; a < MULTS.length; a++) {
        var s1 = scale(items[i], MULTS[a]);
        if (s1.kcal > budget) continue;
        cands.push({ items: [s1], totalP: s1.p, totalKcal: s1.kcal });
      }
    }
    for (i = 0; i < items.length; i++) {
      for (j = i + 1; j < items.length; j++) {
        for (a = 0; a < MULTS.length; a++) {
          for (b = 0; b < MULTS.length; b++) {
            var x1 = scale(items[i], MULTS[a]), x2 = scale(items[j], MULTS[b]);
            var kc = x1.kcal + x2.kcal;
            if (kc > budget) continue;
            var p = Math.round((x1.p + x2.p) * 10) / 10;
            if (p < needP * 0.4) continue;
            cands.push({ items: [x1, x2], totalP: p, totalKcal: kc });
          }
        }
      }
    }
    // 간식은 하루의 일부입니다. 남은 예산을 다 쓰면 끼니가 없어집니다.
    var aim = Math.min(budget, 250);
    var out = finish(cands, needP, limit, aim);
    return { options: out, needP: needP, dayP: dayP, budget: budget, aim: aim,
             ceiling: ceilingProtein(budget, opts.avoid),
             feasible: out.length > 0 && out[0].totalP >= needP * 0.9 };
  }

  /* ---------------------------------------------------------------------- */
  /* 한 끼 — 실제 상차림 형태로                                              */
  /*                                                                         */
  /* 밥 + 주요리 (+ 반찬) 이거나, 그 자체로 한 끼인 단품입니다.              */
  /* 주요리 두 개를 겹쳐 놓는 조합은 만들지 않습니다 — 산술은 맞아도         */
  /* 사람이 그렇게 먹지 않습니다.                                            */
  /* ---------------------------------------------------------------------- */
  function suggestMeal(opts) {
    var dayP = Math.max(0, opts.remainP || 0);
    var budget = opts.remainKcal;
    var limit = opts.limit || 3;
    if (dayP <= 0) return { done: true, options: [] };
    if (budget <= 0) return { overBudget: true, needP: dayP, options: [] };
    // 남은 끼니 수로 나눕니다. 아침에 하루치를 한 끼에 몰면 현실적인 답이 없습니다.
    var needP = opts.aimP || Math.round(dayP / Math.max(1, opts.mealsLeft || 1));

    var bases = pool(BASE, opts.avoid);
    var mains = pool(MAIN, opts.avoid);
    var sides = pool(SIDE, opts.avoid);
    var singles = pool(ONE_DISH, opts.avoid);
    var cands = [], bi, mi, si, a;

    // 단품 한 끼
    singles.forEach(function (x) {
      var s = scale(x, 1);
      if (s.kcal > budget) return;
      cands.push({ items: [s], totalP: s.p, totalKcal: s.kcal, shape: '단품' });
    });

    // 밥 + 주요리 (+ 반찬 하나)
    for (bi = 0; bi < bases.length; bi++) {
      for (mi = 0; mi < mains.length; mi++) {
        for (a = 0; a < MULTS.length; a++) {
          var base = scale(bases[bi], 1);
          var main = scale(mains[mi], MULTS[a]);
          var kc2 = base.kcal + main.kcal;
          if (kc2 > budget) continue;
          var p2 = Math.round((base.p + main.p) * 10) / 10;
          cands.push({ items: [base, main], totalP: p2, totalKcal: kc2, shape: '밥+주요리' });

          for (si = 0; si < sides.length; si++) {
            if (!pairs(base.name, sides[si].name)) continue;
            var side = scale(sides[si], 1);
            var kc3 = kc2 + side.kcal;
            if (kc3 > budget) continue;
            var p3 = Math.round((p2 + side.p) * 10) / 10;
            cands.push({ items: [base, main, side], totalP: p3, totalKcal: kc3,
                         shape: '밥+주요리+반찬' });
          }
        }
      }
    }

    // 남은 예산이 하루치면 한 끼가 그걸 다 쓰면 안 됩니다.
    // 호출부가 이번 끼니의 몫을 알려주면 그걸 쓰고, 없으면 700kcal 로 봅니다.
    var aim = opts.aimKcal || Math.min(budget, Math.round(budget / Math.max(1, opts.mealsLeft || 1)));
    if (aim > 900) aim = 900;
    var out = finish(cands, needP, limit, aim);
    return { options: out, needP: needP, dayP: dayP, budget: budget, aim: aim,
             ceiling: ceilingProtein(budget, opts.avoid),
             feasible: out.length > 0 && out[0].totalP >= needP * 0.9 };
  }

  /** 화면에 쓸 한 줄. 상태를 말할 뿐 명령하지 않습니다. */
  function summaryText(res) {
    if (res.done) return { tone: 'ok', text: '오늘 단백질 목표를 다 채웠습니다.' };
    if (res.overBudget) {
      return { tone: 'warn',
        text: '단백질은 ' + Math.round(res.needP) + 'g 남았지만 칼로리는 다 썼습니다.',
        detail: '오늘은 여기까지 두는 편이 낫습니다. 내일은 아침부터 나눠 담으면 수월합니다.' };
    }
    if (!res.options.length) {
      return { tone: 'warn', text: '남은 칼로리로 만들 조합이 없습니다.',
        detail: '남은 ' + Math.round(res.budget) + 'kcal 로는 단백질 ' +
                Math.round(res.ceiling) + 'g 정도가 한계입니다.' };
    }
    if (!res.feasible) {
      // 왜 못 채우는지를 구분합니다. 칼로리가 모자란 것과
      // 한 끼로는 담을 수 없는 것은 다른 문제이고, 사용자가 할 일도 다릅니다.
      if (res.ceiling < res.needP) {
        return { tone: 'warn',
          text: '남은 칼로리로는 단백질 ' + Math.round(res.ceiling) + 'g 까지가 한계입니다.',
          detail: '아래는 칼로리를 넘기지 않는 선에서 가장 많이 채우는 조합입니다.' };
      }
      return { tone: '', text: '한 번에 다 채우기는 어렵습니다.',
        detail: '아래는 이번에 채울 수 있는 만큼입니다. 나머지는 다음 끼니로 넘기면 됩니다.' };
    }
    var restNote = (res.dayP && res.dayP > res.needP)
      ? '하루 남은 ' + Math.round(res.dayP) + 'g 중 이번 몫 ' + Math.round(res.needP) + 'g 기준입니다.'
      : '남은 ' + Math.round(res.needP) + 'g · ' + Math.round(res.budget) + 'kcal 안에서 골랐습니다.';
    return { tone: '', text: '이렇게 채울 수 있습니다.', detail: restNote };
  }

  global.MB_SUGGEST = {
    suggestSnack: suggestSnack, suggestMeal: suggestMeal,
    summaryText: summaryText, portionText: portionText, density: density,
    SNACKABLE: SNACKABLE, BASE: BASE, MAIN: MAIN, SIDE: SIDE, ONE_DISH: ONE_DISH,
    MIN_PROTEIN_G: MIN_PROTEIN_G
  };
})(window);
