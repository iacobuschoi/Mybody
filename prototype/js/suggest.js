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
  /* 한 끼의 몫 — 예산과 단백질                                              */
  /*                                                                         */
  /* 2026-09 피드백 36: "여전히 다 고열량". 참치김밥+참치캔 2캔(658) ·        */
  /* 짜장면+참치캔 2캔(1037) 이 떴습니다. 원인 셋: 한 끼 상한이 없었고,      */
  /* 단백질 몫이 하루 남은 양을 끼니 수로만 나눈 큰 값이었고, 그걸 맞추려고  */
  /* 편의점 품목을 2단위까지 붙였습니다. 단백질은 간식으로 채워도 되니       */
  /* 끼니는 **건강식으로 깔끔한 한 상**이면 됩니다.                          */
  /* ---------------------------------------------------------------------- */

  /** 한 끼 열량 상한 = 남은 kcal ÷ 남은 끼니 × 이 값. 넘는 조합은 후보가 모자랄 때만 뒤에. */
  var MEAL_CAP_RATIO = 1.15;

  /** 한 끼 단백질 몫의 범위(g). 남은 단백질을 남은 끼니(+간식 1)로 나눈 값을 여기 맞춥니다. */
  var MEAL_PROTEIN_MIN = 30, MEAL_PROTEIN_MAX = 50;

  /** 끼니 몫을 다 배정하고도 남는 단백질을 간식으로 넘기라는 한 줄의 꼬리. */
  var SNACK_HINT_TAIL = ' — 그릭요거트 · 단백질 음료 · 훈제란';

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
    '그릭요거트 무가당', '편의점 닭가슴살', '닭가슴살(조리·시판)',
    '참치캔(기름뺀)', '계란(삶음)', '두부(연두부)', '두유(무가당)', '우유', '저지방우유', '라떼',
    '아몬드', '땅콩버터', '바나나', '사과', '고구마(찐)', '삼각김밥', '통밀식빵',
    // 쉐이크는 실제로 마시는 형태입니다. 분말 '프로틴 1스쿱'은 여기 넣지 않습니다 —
    // 물에 탄 쉐이크와 영양값이 같아서, 둘 다 넣으면 같은 숫자의 선택지가 두 개 뜹니다.
    '프로틴 쉐이크(물)', '프로틴 쉐이크(우유)', '프로틴 쉐이크(저지방우유)',
    '프로틴 쉐이크(신타6·블렌드)',
    // 2026-09 추가 — 편의점에서 집어 먹는 단백질. "프로틴바가 없다" 는 말에서 시작했습니다.
    '프로틴바(일반) 1개', '프로틴바(저당) 1개', '프로틴바(고단백 20g) 1개',
    '단백질 음료(셀렉스) 1병', '단백질 음료(하이뮨) 1병',
    '스트링치즈 1개', '훈제란 1개', '닭가슴살 소시지 1개', '닭가슴살 스테이크(시판) 1팩', '코티지치즈 100g'
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

  /* 찌개는 밥 없이 나온 값입니다. 식당에서 김치찌개만 먹지 않으므로
   * 사먹기 추천에서는 공기밥을 같이 올립니다.
   * (순대국밥은 이름 그대로 밥이 들어 있고, 삼계탕은 안에 찹쌀이 있습니다) */
  var NEEDS_RICE = ['김치찌개', '된장찌개', '순두부찌개', '부대찌개', '설렁탕', '갈비탕',
                    // 백반집 메뉴 — 국·찜·구이·조림은 밥과 같이 나옵니다.
                    '황태해장국', '북엇국', '매운탕', '동태찌개', '알탕', '추어탕', '육개장', '청국장',
                    '뚝배기불고기', '닭볶음탕', '아귀찜', '해물찜', '불고기(소)',
                    '오징어볶음', '낙지볶음', '쭈꾸미볶음', '갈매기살 구이 1인분',
                    '돼지 앞다리살 구이 1인분', '고등어조림', '코다리조림', '두부조림', '모둠회 1인분'];

  /* 사먹을 때 옆에 하나 더 붙일 수 있는 것. 편의점에서 집어 드는 것들입니다.
   * 김밥에 계란 하나, 도시락에 닭가슴살 한 팩 같은 실제 행동입니다. 하나만, 한 단위만.
   * 참치캔은 뺐습니다 — 샌드위치 옆에 캔을 따는 사람은 없습니다(3차 36-보강). */
  var ADD_ON = ['계란(삶음)', '편의점 닭가슴살', '두유(무가당)', '우유', '저지방우유',
                '그릭요거트 무가당', '프로틴 쉐이크(물)'];

  /* 추가를 붙여도 되는 단품 — 편의점 · 분식 · 패스트푸드. 김밥에 계란 하나, 도시락에 두유는
   * 사먹는 모습이지만 순두부찌개 백반에 참치캔은 아닙니다(3차 36-보강: "깔끔한 한 상").
   * 식당 상(백반 · 국 · 찜 · 구이 · 조림 · 덮밥 · 초밥 · 면)은 단품 그대로 — 모자란 단백질은
   * snackHint 가 간식으로 넘깁니다. */
  var ADD_ON_DISHES = [
    '김밥', '참치김밥', '편의점 도시락(일반)', '컵라면(소)', '라면', '라면+계란',
    '서브웨이 15cm(치킨)', '서브웨이 15cm(터키)', '샐러드(닭가슴살) 1볼',
    '떡볶이 1인분', '만두(고기) 5개', '햄버거(불고기)', '피자 1조각'
  ];

  /** 그 자체로 한 끼가 되는 것. 다른 것과 묶지 않습니다. */
  var ONE_DISH = [
    '비빔밥', '제육덮밥', '돈까스덮밥', '김치볶음밥', '김밥', '참치김밥',
    '라면', '라면+계란', '짜장면', '짬뽕', '냉면(물)', '칼국수', '파스타(크림)', '파스타(오일)',
    '김치찌개', '된장찌개', '순두부찌개', '부대찌개', '설렁탕', '순대국밥', '갈비탕', '삼계탕',
    '편의점 도시락(일반)', '컵라면(소)', '서브웨이 15cm(치킨)', '백반(생선구이)',
    '치킨(후라이드) 반마리', '치킨(양념) 반마리', '피자 1조각', '햄버거(불고기)',
    '떡볶이 1인분', '만두(고기) 5개', '족발 1인분',
    // 2026-09 피드백 36 — 메뉴판에 원래 있던 건강식들. 없으니 김밥에 참치캔을 얹었습니다.
    '회덮밥', '포케', '연어덮밥', '오야코동(닭고기계란덮밥)', '규동(소고기덮밥)', '불고기덮밥',
    '낙지볶음덮밥', '오징어덮밥', '산채비빔밥', '돌솥비빔밥',
    '초밥(광어) 10개', '초밥(새우) 10개', '초밥(모둠) 10개', '전복죽', '닭죽',
    '콩나물국밥', '황태해장국', '북엇국', '매운탕', '동태찌개', '알탕', '추어탕', '육개장', '청국장',
    '뚝배기불고기', '닭볶음탕', '아귀찜', '해물찜', '불고기(소)', '오징어볶음', '낙지볶음', '쭈꾸미볶음',
    '갈매기살 구이 1인분', '돼지 앞다리살 구이 1인분', '고등어조림', '코다리조림', '두부조림', '모둠회 1인분',
    '쌀국수(소고기)', '콩국수', '라멘(쇼유)',
    '샐러드(닭가슴살) 1볼', '서브웨이 15cm(터키)'
  ];

  /** 사먹기의 건강식 화이트리스트 — 백반 · 구이 · 찜 · 조림 · 비빔밥 · 회 · 초밥 · 샐러드 ·
   *  포케 · 샌드위치 · 쌀국수 · 맑은 국·탕 · 죽 · 두부. 이 단품은 점수에서 CLEAN_BONUS 를 빼고,
   *  드레싱·양념 지방까지 숫자로 벌주지 않습니다(닭가슴살 샐러드의 지방 비율 0.39). */
  var CLEAN_DISH = [
    '백반(생선구이)', '비빔밥', '산채비빔밥', '돌솥비빔밥', '회덮밥', '포케', '연어덮밥',
    '오야코동(닭고기계란덮밥)', '초밥(광어) 10개', '초밥(새우) 10개', '초밥(모둠) 10개',
    '전복죽', '닭죽', '콩나물국밥', '황태해장국', '북엇국', '매운탕', '동태찌개', '알탕', '추어탕',
    '청국장', '된장찌개', '순두부찌개', '아귀찜', '해물찜',
    '갈매기살 구이 1인분', '돼지 앞다리살 구이 1인분', '고등어조림', '코다리조림', '두부조림',
    '모둠회 1인분', '쌀국수(소고기)', '샐러드(닭가슴살) 1볼', '서브웨이 15cm(터키)', '서브웨이 15cm(치킨)'
  ];
  var CLEAN_BONUS = 6;

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

  /* ---------------------------------------------------------------------- */
  /* 기름진 것과 담백한 것                                                   */
  /*                                                                         */
  /* 2026-09 피드백: "족발·갈비탕이 뜬다". 단백질 밀도만 보면 족발은 좋은     */
  /* 답입니다(40g/480kcal) — 지방이 34g 인 것을 안 봤을 뿐입니다. 그래서      */
  /* 조합의 지방 칼로리 비율(f×9/kcal)이 상한을 넘거나 이름에 기름진 말이     */
  /* 있으면 **뒤로 뺍니다**. 버리지는 않습니다 — 담백한 후보가 모자랄 때만    */
  /* 뒤에 붙이고 shape 에 '지방 많음' 을 답니다. 담백한 이름(구이·찜·샐러드·  */
  /* 잡곡·생선·닭가슴살·두부…)에는 가산점을 줘서 값이 비슷하면 앞에 섭니다.   */
  /* ---------------------------------------------------------------------- */

  /** 조합 전체의 지방 칼로리 비율 상한. 1/3 을 넘으면 기름진 한 끼입니다. */
  var FAT_KCAL_MAX = 0.33;

  /** 이름에 이게 들어가면 숫자와 상관없이 기름진 것으로 봅니다(fooddb 이름 기준).
   *  '치킨(' 은 후라이드·양념만 잡고 서브웨이(치킨)은 남깁니다. */
  var GREASY = ['족발', '보쌈', '갈비', '삼겹살', '치킨(', '돈까스', '피자', '햄버거', '라면',
                '곱창', '튀김', '마요', '크림', '설렁탕', '순대', '부대', '제육', '후라이',
                '베이컨', '핫도그'];

  /** 기름에 볶은 정제 탄수 — 짜장면 · 김치볶음밥 · 짬뽕 · 떡볶이. 지방 비율은 상한 아래라
   *  숫자로는 안 걸리는데(짜장면 0.23) "밥은 건강식으로" 라는 말에는 안 맞습니다.
   *  GREASY 와 같이 뒤로 빼고 shape 에 '정제 탄수' 를 답니다. */
  var REFINED = ['볶음밥', '짜장', '짬뽕', '떡볶이', '파스타'];

  /** 담백한 조리·재료. 품목마다 HEALTHY_BONUS 만큼 점수를 깎습니다(낮을수록 좋음). */
  var HEALTHY = ['구이', '찜', '샐러드', '잡곡', '현미', '생선', '닭가슴살', '닭안심', '두부',
                 '계란', '그릭', '고구마', '나물', '비빔밥', '회(', '오트밀', '참치캔',
                 '살코기', '뒷다리', '연어', '브로콜리', '단백질 음료', '훈제란'];
  var HEALTHY_BONUS = 3;
  /* 담백한 말이 붙어도 그 자체가 기름지면(계란후라이 0.74 · 계란말이 0.67 · 목살 구이 0.64)
     가산점이 없습니다. 삶은 계란이 0.60 이라 그 바로 위에 선을 긋습니다. */
  var HEALTHY_OWN_FAT_MAX = 0.62;

  /** 회전용으로 모아 두는 상위 후보 수의 하한. 실제로는 max(이 값, limit×ROTATE_DAYS). */
  var ROTATE_POOL_MIN = 8;

  /** 며칠 만에 같은 세 줄이 돌아오는가. limit×3 이면 사흘째에 첫날 메뉴가 그대로
   *  돌아왔습니다(일·수·토 가 같은 세 줄). 한 주면 "매일 다른 것" 으로 읽힙니다. */
  var ROTATE_DAYS = 7;

  function hasKw(name, list) {
    var s = String(name || '');
    for (var i = 0; i < list.length; i++) if (s.indexOf(list[i]) >= 0) return true;
    return false;
  }
  function fatRatio(f, kcal) { return kcal > 0 ? (f || 0) * 9 / kcal : 0; }

  /** 이 조합이 기름진가 — 이름으로든 합계 숫자로든.
   *  첫 품목이 화이트리스트 단품이면 숫자는 안 봅니다 — 이름으로 담백하다고 정한 것입니다. */
  function isGreasy(items) {
    var kc = 0, fat = 0;
    for (var i = 0; i < items.length; i++) {
      if (hasKw(items[i].name, GREASY)) return true;
      kc += (items[i].kcal || 0);
      fat += (items[i].f || 0);
    }
    if (inList(CLEAN_DISH, items[0].name)) return false;
    return fatRatio(fat, kc) > FAT_KCAL_MAX;
  }

  /** 이 조합에 정제 탄수 단품이 있는가 — 이름으로만. */
  function isRefined(items) {
    for (var i = 0; i < items.length; i++) if (hasKw(items[i].name, REFINED)) return true;
    return false;
  }
  function healthyCount(items) {
    var n = 0;
    for (var i = 0; i < items.length; i++) {
      var x = items[i];
      if (hasKw(x.name, HEALTHY) && fatRatio(x.f, x.kcal) <= HEALTHY_OWN_FAT_MAX) n++;
    }
    return n;
  }

  /* ---------------------------------------------------------------------- */
  /* 회전 — 매일 다른 것을                                                   */
  /*                                                                         */
  /* 같은 입력이면 같은 답이 나오는 게 이 모듈의 미덕인데, 사용자 입장에서는  */
  /* 사흘 내리 설렁탕입니다. 그래서 날짜(opts.seed = 'YYYY-MM-DD')를 씨앗으로 */
  /* 상위 후보 안에서 시작점만 옮깁니다. 같은 날은 같은 답, 다음 날은 다른   */
  /* 첫 줄. Date 를 안 씁니다 — 시간대에 따라 하루가 밀리고, Dart 쪽과       */
  /* 정수 연산으로 똑같이 맞추려면 산수만 남기는 게 안전합니다.             */
  /* ---------------------------------------------------------------------- */

  function intOf(s) {
    if (typeof s !== 'string' || !/^\d{1,9}$/.test(s)) return null;
    return parseInt(s, 10);
  }

  /** 'YYYY-MM-DD' → 1970-01-01 부터 센 날 수(days_from_civil). 모양이 아니면 null. */
  function dayNumber(seed) {
    if (typeof seed !== 'string') return null;
    var parts = seed.split('-');
    if (parts.length !== 3) return null;
    var y = intOf(parts[0]), m = intOf(parts[1]), d = intOf(parts[2]);
    if (y === null || m === null || d === null || m < 1 || m > 12 || d < 1 || d > 31) return null;
    if (m <= 2) y -= 1;
    var era = Math.floor(y / 400);
    var yoe = y - era * 400;
    var doy = Math.floor((153 * (m + (m > 2 ? -3 : 9)) + 2) / 5) + d - 1;
    var doe = yoe * 365 + Math.floor(yoe / 4) - Math.floor(yoe / 100) + doy;
    return era * 146097 + doe - 719468;
  }

  function gcd(a, b) { while (b) { var t = a % b; a = b; b = t; } return a; }

  /**
   * 날짜로 정한 자리에서 limit 개를 돌려 가며 고릅니다. 한 묶음(limit 개)씩
   * 건너뛰어서 어제 본 메뉴가 오늘 또 첫 줄에 서지 않습니다. 후보가 한 묶음
   * 이하면 한 칸씩만 밉니다. day 가 없으면 점수순 그대로입니다.
   * 보폭은 후보 수와 서로소로 잡습니다 — 후보가 9개에 보폭 3이면 시작점이
   * 0·3·6 세 자리뿐이라 사흘마다 같은 세 줄이었습니다. 서로소면 n 일 동안
   * 첫 줄이 전부 다릅니다.
   */
  function rotate(top, limit, day) {
    var n = top.length, take = Math.min(limit, n);
    if (day === null || n < 2) return top.slice(0, take);
    var step = n > limit ? limit : 1;
    while (gcd(step, n) !== 1) step++;
    var start = ((day * step) % n + n) % n;
    var out = [];
    for (var i = 0; i < take; i++) out.push(top[(start + i) % n]);
    return out;
  }

  /* ---------------------------------------------------------------------- */
  /* 분량 표기 — '1개 × 2' 는 '2개'                                          */
  /* ---------------------------------------------------------------------- */

  function isDigit(ch) { return ch >= '0' && ch <= '9'; }
  function isHangul(ch) { return ch >= '가' && ch <= '힣'; }
  function isLatin(ch) { return (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z'); }
  function isQtyPrev(ch) { return ch === ' ' || ch === '+' || ch === '(' || isHangul(ch); }
  function isQtyWord(w) {
    if (w === 'g' || w === 'ml' || w === 'kg' || w === 'L') return true;
    for (var i = 0; i < w.length; i++) if (!isHangul(w.charAt(i))) return false;
    return true;
  }

  /**
   * '1개' × 2 → '2개', '100g' × 1.5 → '150g', '1팩100g' × 2 → '2팩200g'.
   * 단위 속 숫자 중 뒤에 셀 수 있는 말(개·컵·장·팩… 또는 g·ml·kg·L)이 붙은
   * 것만 곱합니다. '15cm' 같은 크기는 두고, '1/2모' 처럼 분수가 낀 것은 손대지
   * 않습니다. 하나라도 정수가 안 되면('1개' × 1.5) 빈 문자열 — 호출부가
   * '× 1.5' 로 돌아갑니다.
   */
  function scaleUnit(unit, mult) {
    if (!unit || unit.indexOf('/') >= 0 || !(mult > 0)) return '';
    var out = '', any = false, i = 0, n = unit.length;
    while (i < n) {
      var ch = unit.charAt(i);
      if (isDigit(ch) && (i === 0 || isQtyPrev(unit.charAt(i - 1)))) {
        var j = i;
        while (j < n && isDigit(unit.charAt(j))) j++;
        var k = j;
        while (k < n && (isHangul(unit.charAt(k)) || isLatin(unit.charAt(k)))) k++;
        if (k > j && isQtyWord(unit.slice(j, k))) {
          var v = parseInt(unit.slice(i, j), 10) * mult;
          if (v % 1 !== 0) return '';
          out += String(v);
          any = true;
          i = j;
          continue;
        }
      }
      out += ch;
      i++;
    }
    return any ? out : '';
  }

  /** 단위의 첫 수량 토큰 — '1팩 100g' → '1팩', '1개' → '1개', '100g' → ''(셀 수 없음). */
  function countToken(unit) {
    var s = String(unit || ''), i = 0, n = s.length;
    while (i < n) {
      var ch = s.charAt(i);
      if (isDigit(ch) && (i === 0 || isQtyPrev(s.charAt(i - 1)))) {
        var j = i;
        while (j < n && isDigit(s.charAt(j))) j++;
        var k = j;
        while (k < n && isHangul(s.charAt(k))) k++;
        if (k > j) return s.slice(i, k);
        i = j;
        continue;
      }
      i++;
    }
    return '';
  }

  /** 이 배수로 먹는다고 볼 수 있는가. 정수가 아닌 배수는 단위의 말로 적을 수 있을 때만
   *  ('100g' → '150g', '2쪽' → '3쪽'). '계란 1개 × 1.5' · '1/2모 × 1.5' 는 먹는 양이
   *  아닙니다 — 말할 수 없는 분량은 권하지 않습니다. */
  function multOk(food, mult) {
    if (mult % 1 === 0) return true;
    return scaleUnit(String(food.unit || ''), mult) !== '';
  }

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
    // 이름이 이미 분량을 품고 있으면(만두(고기) 5개, 삼겹살 1인분) 또 붙이지 않습니다.
    var dup = item.name && item.name.indexOf(item.unit) >= 0;
    var base = dup ? '' : item.unit;
    if (item.mult === 1) return base;
    if (item.mult === 0.5) return (base ? base + ' ' : '') + '반';
    // '1개 × 2' 보다 '2개' 가 사람 말입니다 — 단위가 셀 수 있는 것일 때만.
    var scaled = base ? scaleUnit(base, item.mult) : '';
    if (scaled) return scaled;
    var x = '× ' + (item.mult % 1 === 0 ? item.mult : item.mult.toFixed(1));
    return base ? base + ' ' + x : x;
  }

  /**
   * 화면에 쓰는 한 품목의 글 — 이름 + 분량. 이름 끝이 단위의 수량('훈제란 1개' 의
   * '1개' · '닭가슴살 스테이크(시판) 1팩' 의 '1팩')이면 그 수량을 이름에서 떼고 단위로
   * 다시 말합니다: '훈제란 1개 55g', ×2 는 '훈제란 2개 110g'. 안 떼면 '훈제란 1개 1개 55g'
   * 이나 '훈제란 1개 2개 110g' 처럼 두 숫자가 한 줄에 섭니다. 이름이 단위 전체로
   * 끝나면(코티지치즈 100g) 그것도 떼어 '코티지치즈 200g'.
   */
  function itemText(item) {
    var name = String(item.name || ''), unit = String(item.unit || '');
    var suffix = '';
    if (unit && name.length > unit.length && name.slice(name.length - unit.length) === unit) {
      suffix = unit;
    } else {
      var tok = countToken(unit);
      if (tok && name.length > tok.length && name.slice(name.length - tok.length) === tok) suffix = tok;
    }
    if (!suffix) return (name + ' ' + portionText(item)).trim();
    var head = name.slice(0, name.length - suffix.length).replace(/\s+$/, '');
    var pt = portionText({ name: head, unit: unit, mult: item.mult });
    return (head + ' ' + pt).trim();
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
  function score(totalP, totalKcal, needP, aim, over) {
    var gap = needP - totalP;
    // 모자란 건 크게 벌줍니다. 넘치는 건 거의 벌주지 않습니다 —
    // 칼로리 안에서 단백질이 좀 넘치는 건 나쁜 일이 아닌데, 예전엔 2배로 벌줘서
    // 삼계탕·설렁탕 같은 단품 한 끼가 한 번도 추천되지 않았습니다.
    var pPenalty = gap > 0 ? gap * 10 : -gap * 0.5;
    var kPenalty = Math.abs(totalKcal - aim) / 100 * 3;
    /* 탄수·지방은 오늘 남은 양을 **넘긴 만큼만** 벌줍니다(g당 0.5). 남은 양
       안에 드는 조합을 앞에 세우려는 것이지, 탄수를 적게 먹으라는 게
       아닙니다. 예산을 안 주면 예전과 같습니다. */
    var cfPenalty = (over || 0) * 0.5;
    return pPenalty + kPenalty + cfPenalty;
  }

  /** 오늘 남은 탄수·지방(opts.remainC / remainF)을 이 조합이 얼마나 넘기는가(g). */
  function overBudget(items, opts) {
    if (!opts) return 0;
    var over = 0;
    if (opts.remainC != null) {
      var sc = 0;
      items.forEach(function (x) { sc += (x.c || 0); });
      over += Math.max(0, sc - opts.remainC);
    }
    if (opts.remainF != null) {
      var sf = 0;
      items.forEach(function (x) { sf += (x.f || 0); });
      over += Math.max(0, sf - opts.remainF);
    }
    return over;
  }

  /** 조합에서 단백질을 가장 많이 내는 품목 — 이 끼니의 주인공 */
  function mainOf(items) {
    var best = items[0];
    items.forEach(function (x) { if (x.p > best.p) best = x; });
    return best.name;
  }

  /** 사먹기의 주인공은 메뉴판의 단품(첫 품목)입니다 — 단백질이 제일 많은 것으로 고르면
   *  편의점 닭가슴살 · 참치캔이 주인공이 되어 '순두부찌개+닭가슴살' 과 '순두부찌개+참치캔'
   *  이 서로 다른 선택지로 통과합니다. 한 날 세 줄 중 둘이 순두부찌개였습니다. */
  function dishOf(items) { return items[0].name; }

  /** 뒤로 뺀 이유를 shape 에 답니다 — 사용자가 왜 뒤에 있는지 알아야 고를 수 있습니다. */
  function tagShape(c, tag) { c.shape = c.shape ? c.shape + ' · ' + tag : tag; }

  /**
   * @param mainKey 조합의 주인공 이름 — 같은 주인공은 한 번만 보입니다(기본 mainOf).
   * @param cap 한 끼 열량 상한. 없으면(undefined·NaN) 상한 검사가 전부 통과합니다.
   */
  function finish(cands, needP, limit, aim, opts, mainKey, cap) {
    var keyOf = mainKey || mainOf;
    cands.forEach(function (c) {
      c.score = score(c.totalP, c.totalKcal, needP, aim, overBudget(c.items, opts)) + (c.extra || 0)
              - healthyCount(c.items) * HEALTHY_BONUS;
      c.coversPct = needP > 0 ? Math.round(c.totalP / needP * 100) : 100;
      c.greasy = isGreasy(c.items);
      c.refined = isRefined(c.items);
      c.overCap = c.totalKcal > cap;
    });
    cands.sort(function (a, b) { return a.score - b.score; });

    // 주요리가 서로 다른 것만 고릅니다.
    // 같은 음식의 배수 차이나 반찬만 바꾼 조합이 나란히 뜨면 선택지가 아니라 한 가지입니다.
    // 담백하고 한 끼 예산 안에 드는 것부터, 회전할 수 있게 넉넉히 모읍니다.
    var poolSize = Math.max(ROTATE_POOL_MIN, limit * ROTATE_DAYS);
    var seenMain = {}, top = [], i, m;
    /* 차선(fallback) — 사먹기의 「단품 + 추가」. 단품만으로 한 묶음이 안 될 때만 뒤에 붙습니다 —
       회전 묶음에 들어가면 「순두부찌개 백반」 옆에 「참치김밥 + 닭가슴살」 이 서는 날이 생깁니다. */
    for (i = 0; i < cands.length && top.length < poolSize; i++) {
      if (cands[i].greasy || cands[i].refined || cands[i].overCap || cands[i].fallback) continue;
      m = keyOf(cands[i].items);
      if (seenMain[m]) continue;
      seenMain[m] = true;
      cands[i].main = m;
      top.push(cands[i]);
    }
    /* 회전은 "충분히 좋은 것" 안에서만 돕니다. 아홉째 후보가 단백질을 반만
       채우면 그날은 추천이 나쁜 날이 됩니다. 이번 몫의 90% 를 채우는 것이
       한 묶음 이상이면 그 안에서 돌고, 아니면 점수순 그대로입니다. */
    var good = top.filter(function (c) { return c.totalP >= needP * 0.9; });
    var out = good.length >= limit ? rotate(good, limit, dayNumber(opts && opts.seed))
                                   : top.slice(0, limit);

    // 담백한 후보가 모자랄 때만 차선 · 기름진 것 · 정제 탄수 · 예산 넘는 것을 뒤에 붙입니다 — 표시를 달고.
    for (i = 0; i < cands.length && out.length < limit; i++) {
      if (!cands[i].greasy && !cands[i].refined && !cands[i].overCap && !cands[i].fallback) continue;
      m = keyOf(cands[i].items);
      if (seenMain[m]) continue;
      seenMain[m] = true;
      cands[i].main = m;
      if (cands[i].greasy) tagShape(cands[i], '지방 많음');
      if (cands[i].refined) tagShape(cands[i], '정제 탄수');
      if (cands[i].overCap) tagShape(cands[i], '열량 높음');
      out.push(cands[i]);
    }
    return out;
  }

  /* ---------------------------------------------------------------------- */
  /* 한 끼의 몫                                                              */
  /* ---------------------------------------------------------------------- */

  /** 남은 끼니 수 — 없으면 1. */
  function mealsLeftOf(opts) { return Math.max(1, opts.mealsLeft || 1); }

  /** 이번 끼니의 단백질 몫(g). 남은 단백질을 남은 끼니(+간식 1)로 나눠 30~50g 에 맞추되,
   *  남은 것보다 많이 잡지는 않습니다. 호출부가 aimP 를 주면 그대로입니다. */
  function mealProtein(dayP, opts) {
    if (opts.aimP) return opts.aimP;
    var share = dayP / (mealsLeftOf(opts) + 1);
    return Math.round(Math.min(dayP, Math.max(MEAL_PROTEIN_MIN, Math.min(MEAL_PROTEIN_MAX, share))));
  }

  /** 한 끼 열량 상한. 예산이 없으면 NaN — 비교가 전부 거짓이라 상한이 없는 것과 같습니다. */
  function mealCap(budget, opts) { return budget / mealsLeftOf(opts) * MEAL_CAP_RATIO; }

  /** 이번 끼니가 겨냥하는 칼로리. 호출부가 주면 그걸, 없으면 남은 끼니로 나눈 몫(최대 900). */
  function mealAim(budget, opts) {
    var aim = opts.aimKcal || Math.min(budget, Math.round(budget / mealsLeftOf(opts)));
    return aim > 900 ? 900 : aim;
  }

  /** 끼니 몫을 남은 끼니에 다 배정하고도 남는 단백질(g) — 간식 몫입니다. */
  function snackShare(dayP, needP, opts) {
    return Math.max(0, Math.round(dayP - needP * mealsLeftOf(opts)));
  }

  /** '단백질 40g 은 간식으로 — 그릭요거트 · 단백질 음료 · 훈제란'. 몫이 작으면 빈 문자열. */
  function snackHint(gap) {
    return gap >= MIN_PROTEIN_G ? '단백질 ' + gap + 'g 은 간식으로' + SNACK_HINT_TAIL : '';
  }

  function mealResult(out, needP, dayP, budget, aim, cap, opts) {
    var gap = snackShare(dayP, needP, opts);
    return { options: out, needP: needP, dayP: dayP, budget: budget, aim: aim, mealKcalCap: cap,
             ceiling: ceilingProtein(budget, opts.avoid),
             feasible: feasible(out, needP),
             proteinGapG: gap, snackHint: snackHint(gap) };
  }

  /** 보이는 것 중 하나라도 이번 몫의 90% 를 채우면 "채울 수 있다" 입니다.
   *  (회전하면 첫 줄이 최고점이 아니라서 첫 줄만 볼 수 없습니다.) */
  function feasible(out, needP) {
    for (var i = 0; i < out.length; i++) if (out[i].totalP >= needP * 0.9) return true;
    return false;
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
        if (!multOk(items[i], MULTS[a])) continue;
        var s1 = scale(items[i], MULTS[a]);
        if (s1.kcal > budget) continue;
        cands.push({ items: [s1], totalP: s1.p, totalKcal: s1.kcal });
      }
    }
    for (i = 0; i < items.length; i++) {
      for (j = i + 1; j < items.length; j++) {
        for (a = 0; a < MULTS.length; a++) {
          if (!multOk(items[i], MULTS[a])) continue;
          for (b = 0; b < MULTS.length; b++) {
            if (!multOk(items[j], MULTS[b])) continue;
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
    var out = finish(cands, needP, limit, aim, opts);
    return { options: out, needP: needP, dayP: dayP, budget: budget, aim: aim,
             ceiling: ceilingProtein(budget, opts.avoid),
             feasible: feasible(out, needP) };
  }

  /* ---------------------------------------------------------------------- */
  /* 사먹기 — 점심·저녁은 대개 밖에서 먹습니다                               */
  /*                                                                         */
  /* 집밥 추천(밥+주요리+반찬)은 식당에서 시킬 수 있는 형태가 아닙니다.      */
  /* 여기서는 메뉴판에 있는 단품 하나를 고르고, 모자라면 편의점에서 하나     */
  /* 더 집는 실제 행동을 모델로 합니다.                                       */
  /* ---------------------------------------------------------------------- */
  function suggestEatOut(opts) {
    var F = global.MB_FOOD;
    var dayP = Math.max(0, opts.remainP || 0);
    var budget = opts.remainKcal;
    var limit = opts.limit || 3;
    if (dayP <= 0) return { done: true, options: [] };
    if (budget <= 0) return { overBudget: true, needP: dayP, options: [] };
    var needP = mealProtein(dayP, opts);

    var rice = F.byName ? F.byName('공기밥(백미)') : null;
    if (!rice) F.FOODS.forEach(function (x) { if (x.name === '공기밥(백미)') rice = x; });

    var dishes = pool(ONE_DISH, opts.avoid);
    var addons = pool(ADD_ON, opts.avoid);
    var cands = [];

    dishes.forEach(function (d) {
      var items = [scale(d, 1)];
      if (inList(NEEDS_RICE, d.name) && rice) items.push(scale(rice, 1));
      var kc = items.reduce(function (t, x) { return t + x.kcal; }, 0);
      var pp = Math.round(items.reduce(function (t, x) { return t + x.p; }, 0) * 10) / 10;
      if (kc > budget) return;
      // 사먹을 때는 "숫자를 맞췄는가"보다 "메뉴가 단백질이 좋은가"가 중요합니다.
      // 이게 없으면 파스타에 프로틴 쉐이크를 얹는 조합이 갈비탕을 이깁니다.
      // 건강식 화이트리스트는 그 위에 가산점 — 값이 비슷하면 백반이 김밥보다 앞에 섭니다.
      var dishPenalty = Math.max(0, 8 - density(d)) * 3 - (inList(CLEAN_DISH, d.name) ? CLEAN_BONUS : 0);
      cands.push({ items: items, totalP: pp, totalKcal: kc, shape: '단품', extra: dishPenalty });

      // 단품 하나로 모자라면 옆에 하나 더. 하나만, 한 단위만 — '참치캔 2캔' 은 사먹는 모습이 아닙니다.
      // 편의점 · 분식 · 패스트푸드 단품(ADD_ON_DISHES)에만 — 식당 상에 참치캔은 「깔끔한 한 상」 이
      // 아닙니다(3차 36-보강). 모자란 단백질은 snackHint 가 간식으로 넘깁니다. 붙여도 차선(fallback) —
      // 단품만으로 한 묶음이 안 될 때만 보입니다.
      if (pp >= needP * 0.95) return;
      if (!inList(ADD_ON_DISHES, d.name)) return;
      addons.forEach(function (a) {
        var ad = scale(a, 1);
        var kc2 = kc + ad.kcal;
        if (kc2 > budget) return;
        var p2 = Math.round((pp + ad.p) * 10) / 10;
        // 옆에 하나 더 붙이는 건 차선책입니다. 단품 하나로 되면 그게 낫습니다.
        cands.push({ items: items.concat([ad]), totalP: p2, totalKcal: kc2,
                     shape: '단품 + 추가', extra: dishPenalty + 8, fallback: true });
      });
    });

    var aim = mealAim(budget, opts), cap = mealCap(budget, opts);
    var out = finish(cands, needP, limit, aim, opts, dishOf, cap);
    return mealResult(out, needP, dayP, budget, aim, cap, opts);
  }

  /* ---------------------------------------------------------------------- */
  /* 집밥 한 끼 — 실제 상차림 형태로                                          */
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
    // 남은 끼니(+간식)로 나눕니다. 아침에 하루치를 한 끼에 몰면 현실적인 답이 없습니다.
    var needP = mealProtein(dayP, opts);

    var bases = pool(BASE, opts.avoid);
    var mains = pool(MAIN, opts.avoid);
    var sides = pool(SIDE, opts.avoid);
    var cands = [], bi, mi, si, a;

    // 밥 + 주요리 (+ 반찬 하나)
    for (bi = 0; bi < bases.length; bi++) {
      for (mi = 0; mi < mains.length; mi++) {
        for (a = 0; a < MULTS.length; a++) {
          if (!multOk(mains[mi], MULTS[a])) continue;
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

    // 남은 예산이 하루치면 한 끼가 그걸 다 쓰면 안 됩니다 — 겨냥은 끼니 몫, 상한은 그 1.15배.
    var aim = mealAim(budget, opts), cap = mealCap(budget, opts);
    var out = finish(cands, needP, limit, aim, opts, undefined, cap);
    return mealResult(out, needP, dayP, budget, aim, cap, opts);
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
    suggestSnack: suggestSnack, suggestMeal: suggestMeal, suggestEatOut: suggestEatOut,
    summaryText: summaryText, portionText: portionText, itemText: itemText, density: density,
    dayNumber: dayNumber, scaleUnit: scaleUnit, countToken: countToken, isGreasy: isGreasy,
    isRefined: isRefined,
    SNACKABLE: SNACKABLE, BASE: BASE, MAIN: MAIN, SIDE: SIDE, ONE_DISH: ONE_DISH,
    NEEDS_RICE: NEEDS_RICE, ADD_ON: ADD_ON, ADD_ON_DISHES: ADD_ON_DISHES, GREASY: GREASY, REFINED: REFINED, HEALTHY: HEALTHY,
    CLEAN_DISH: CLEAN_DISH, MIN_PROTEIN_G: MIN_PROTEIN_G, FAT_KCAL_MAX: FAT_KCAL_MAX,
    MEAL_CAP_RATIO: MEAL_CAP_RATIO, MEAL_PROTEIN_MIN: MEAL_PROTEIN_MIN, MEAL_PROTEIN_MAX: MEAL_PROTEIN_MAX
  };
})(window);
