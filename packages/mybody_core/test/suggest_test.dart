/* 「뭘 먹을까」 추천이 지켜야 하는 성질들.
 *
 * 2026-09 피드백: "족발·갈비탕이 뜬다, 매일 똑같다, '1개 × 2' 가 뭐냐", 그리고
 * 3차 36: "여전히 다 고열량 — 참치김밥+참치캔 2캔(658) · 짜장면+참치캔 2캔(1037)".
 * 숫자(단백질 밀도)만 보면 족발은 좋은 답이라, 이 시험들은 "무엇이 첫 줄에
 * 보이는가" 를 검사합니다. 원본(prototype/js/suggest.js)과의 일치는
 * tools/difftest.js 가 맡고, 여기서는 사람이 보는 결과만 봅니다. */
import 'package:mybody_core/suggest.dart';
import 'package:test/test.dart';

List<Map<String, Object?>> optionsOf(Map<String, Object?> res) =>
    ((res['options'] as List?) ?? const []).map((o) => (o as Map).cast<String, Object?>()).toList();

List<Map<String, Object?>> itemsOf(Map<String, Object?> option) =>
    (option['items'] as List).cast<Map<String, Object?>>();

String firstMain(Map<String, Object?> res) => '${optionsOf(res).first['main']}';

String sentence(Map<String, Object?> option) =>
    itemsOf(option).map((x) => '${x['name']} ${portionText(x)}'.trim()).join(' + ');

/// 화면에 뜬 조합이 기름진가 — 이름(kGreasy) 또는 합계 지방 kcal 비율.
/// 첫 품목이 화이트리스트 단품이면 모듈과 같이 숫자는 안 봅니다.
bool greasyShown(Map<String, Object?> option) {
  var kc = 0.0, f = 0.0;
  for (final x in itemsOf(option)) {
    for (final k in kGreasy) {
      if ('${x['name']}'.contains(k)) return true;
    }
    kc += (x['kcal'] as num).toDouble();
    f += (x['f'] as num).toDouble();
  }
  if (kCleanDish.contains(itemsOf(option).first['name'])) return false;
  return kc > 0 && f * 9 / kc > kFatKcalMax;
}

bool refinedShown(Map<String, Object?> option) =>
    itemsOf(option).any((x) => kRefined.any((k) => '${x['name']}'.contains(k)));

/// 사먹기 조합에서 단품(과 같이 나오는 공기밥)을 뺀 추가 품목들.
List<Map<String, Object?>> addOnsOf(Map<String, Object?> option) {
  final items = itemsOf(option);
  return [
    for (var i = 1; i < items.length; i++)
      if (!(i == 1 && items[i]['name'] == '공기밥(백미)' && kNeedsRice.contains(items[0]['name'])))
        items[i],
  ];
}

void main() {
  group('지방 필터', () {
    /* 남은 양을 넓게 흔들어 후보가 많이 생기는 구간과 적게 생기는 구간을 다 밟습니다. */
    final inputs = [
      for (final p in [20, 40, 60, 90])
        for (final k in [400, 700, 900, 1400])
          {'remainP': p, 'remainKcal': k, 'mealsLeft': 1, 'seed': '2026-09-24'},
    ];

    test('사먹기 · 집밥 · 간식 — 「지방 많음」 표시 없는 조합은 기름지지 않다', () {
      for (final opts in inputs) {
        for (final res in [suggestEatOut(opts), suggestMeal(opts), suggestSnack(opts)]) {
          for (final o in optionsOf(res)) {
            final flagged = '${o['shape'] ?? ''}'.contains('지방 많음');
            expect(greasyShown(o), flagged,
                reason: '${sentence(o)} — shape=${o['shape']} 는 표시와 실제가 맞아야 합니다');
          }
        }
      }
    });

    test('「정제 탄수」 표시 없는 조합에는 짜장면·볶음밥·짬뽕·떡볶이가 없다', () {
      for (final opts in inputs) {
        for (final res in [suggestEatOut(opts), suggestMeal(opts), suggestSnack(opts)]) {
          for (final o in optionsOf(res)) {
            final flagged = '${o['shape'] ?? ''}'.contains('정제 탄수');
            expect(refinedShown(o), flagged, reason: '${sentence(o)} — shape=${o['shape']}');
          }
        }
      }
    });

    test('피드백 캡처의 족발·갈비탕·설렁탕은 사먹기 첫 화면에 안 뜬다', () {
      final res = suggestEatOut({'remainP': 60, 'remainKcal': 900, 'mealsLeft': 1});
      final all = optionsOf(res).map(sentence).join(' / ');
      expect(all, isNot(contains('족발')));
      expect(all, isNot(contains('갈비탕')));
      expect(all, isNot(contains('설렁탕')));
      expect(res['feasible'], isTrue);
    });

    test('담백한 후보가 모자랄 때만 기름진 것을 뒤에 붙이고 표시한다', () {
      // 300kcal 아래 단품은 서브웨이(터키) 289 · 피자 한 조각 290 · 컵라면 300 뿐입니다(김밥 323).
      final res = suggestEatOut({'remainP': 30, 'remainKcal': 300, 'mealsLeft': 1});
      final opts = optionsOf(res);
      expect(opts, hasLength(3));
      expect(itemsOf(opts[0]).first['name'], '서브웨이 15cm(터키)', reason: '담백한 것이 먼저');
      expect('${opts[0]['shape']}', isNot(contains('지방 많음')));
      for (final o in opts.skip(1)) {
        expect('${o['shape']}', contains('지방 많음'), reason: sentence(o));
        expect(o['greasy'], isTrue);
      }
    });

    test('집밥 첫 화면은 담백한 이름(잡곡·닭가슴살·구이…)이 든 조합이다', () {
      for (final seed in ['2026-09-24', '2026-09-25', '2026-09-26']) {
        final res = suggestMeal({'remainP': 60, 'remainKcal': 900, 'mealsLeft': 1, 'seed': seed});
        for (final o in optionsOf(res)) {
          final healthy = itemsOf(o).any((x) => kHealthy.any((k) => '${x['name']}'.contains(k)));
          expect(healthy, isTrue, reason: sentence(o));
        }
      }
    });
  });

  group('한 끼 예산 (피드백 36)', () {
    /* 캡처: 남은 1,530kcal · 단백질 109g · 2끼 남음에 참치김밥+참치캔 2캔(658) ·
       김치볶음밥+닭가슴살 2팩(850) · 짜장면+참치캔 2캔(1037) 이 떴습니다. */
    const capture = {'remainP': 109, 'remainKcal': 1530, 'mealsLeft': 2};
    final week = [for (var d = 20; d <= 27; d++) '2026-09-$d'];

    test('상한 = 남은 kcal ÷ 남은 끼니 × 1.15 — 1,500kcal · 2끼면 862.5', () {
      final res = suggestEatOut({'remainP': 100, 'remainKcal': 1500, 'mealsLeft': 2});
      expect(res['mealKcalCap'], closeTo(862.5, 1e-6));
      expect(kMealCapRatio, 1.15);
      expect(suggestMeal({'remainP': 100, 'remainKcal': 1500, 'mealsLeft': 2})['mealKcalCap'],
          closeTo(862.5, 1e-6));
    });

    test('1,500kcal · 2끼 → 사먹기·집밥 옵션마다 ≤ 863kcal, 추가는 1개·1단위, 짜장면 없음', () {
      for (final seed in week) {
        final opts = {'remainP': 100, 'remainKcal': 1500, 'mealsLeft': 2, 'seed': seed};
        for (final res in [suggestEatOut(opts), suggestMeal(opts)]) {
          final shown = optionsOf(res);
          expect(shown, hasLength(3), reason: seed);
          for (final o in shown) {
            expect((o['totalKcal'] as num) <= 863, isTrue, reason: '$seed ${sentence(o)} ${o['totalKcal']}kcal');
            expect('${o['shape']}', isNot(contains('열량 높음')), reason: '후보가 넉넉하면 예산 넘는 것은 안 보입니다');
            expect(sentence(o), isNot(contains('짜장면')));
            expect(sentence(o), isNot(contains('김치볶음밥')));
          }
        }
        for (final o in optionsOf(suggestEatOut(opts))) {
          final adds = addOnsOf(o);
          expect(adds.length <= 1, isTrue, reason: '추가는 하나만: ${sentence(o)}');
          for (final a in adds) {
            expect(a['mult'], 1, reason: '추가는 한 단위만: ${sentence(o)}');
          }
        }
      }
    });

    test('캡처 시나리오 — 참치캔 2캔 · 닭가슴살 2팩 같은 2단위 추가가 사먹기에 없다', () {
      for (final seed in week) {
        final res = suggestEatOut({...capture, 'seed': seed});
        for (final o in optionsOf(res)) {
          final s = sentence(o);
          expect(s, isNot(contains('2캔')), reason: s);
          expect(s, isNot(contains('2팩')), reason: s);
          expect((o['totalKcal'] as num) <= (res['mealKcalCap'] as num), isTrue, reason: s);
        }
      }
    });

    test('캡처 시나리오 — 사먹기 첫 화면은 건강식 화이트리스트 단품이 주인공(하루 셋 중 둘 이상)', () {
      for (final seed in week) {
        final res = suggestEatOut({...capture, 'seed': seed});
        final shown = optionsOf(res);
        expect(shown, hasLength(3), reason: seed);
        final clean = shown.where((o) => kCleanDish.contains(itemsOf(o).first['name'])).length;
        expect(clean >= 2, isTrue, reason: '$seed: ${shown.map(sentence).join(' / ')}');
        for (final o in shown) {
          expect(o['greasy'], isFalse, reason: sentence(o));
          expect(o['refined'], isFalse, reason: sentence(o));
        }
      }
    });

    test('식당 상(백반 · 국 · 찜 · 덮밥 · 초밥)에는 추가를 안 붙인다 — 「순두부찌개 + 공기밥 + 참치캔」 은 없다 (36-보강)', () {
      for (final seed in week) {
        for (final opts in [
          {...capture, 'seed': seed},
          {'remainP': 60, 'remainKcal': 900, 'mealsLeft': 1, 'seed': seed},
          {'remainP': 90, 'remainKcal': 1800, 'mealsLeft': 3, 'seed': seed},
          {'remainP': 40, 'remainKcal': 450, 'mealsLeft': 1, 'seed': seed},
        ]) {
          for (final o in optionsOf(suggestEatOut(opts))) {
            final first = '${itemsOf(o).first['name']}';
            if (addOnsOf(o).isNotEmpty) {
              expect(kAddOnDishes, contains(first), reason: '추가는 편의점 · 분식 단품에만: ${sentence(o)}');
            }
            expect(sentence(o), isNot(contains('참치캔')), reason: '참치캔은 추가 목록에서 뺐습니다: ${sentence(o)}');
          }
        }
      }
      expect(kAddOn, isNot(contains('참치캔(기름뺀)')));
      for (final n in kAddOnDishes) {
        expect(kOneDish, contains(n), reason: '$n 은 사먹기 메뉴에 있어야 합니다');
        expect(kNeedsRice, isNot(contains(n)), reason: '$n — 공기밥이 같이 나오는 식당 상은 추가 없이');
      }
    });

    test('「단품 + 추가」 는 차선 — 단품만으로 한 묶음이 되면 안 보인다', () {
      for (final seed in week) {
        for (final o in optionsOf(suggestEatOut({...capture, 'seed': seed}))) {
          expect(addOnsOf(o), isEmpty, reason: '$seed ${sentence(o)}');
          expect('${o['shape']}', '단품', reason: sentence(o));
        }
      }
    });

    test('예산을 넘는 것은 후보가 모자랄 때만 뒤에 붙고 「열량 높음」 을 단다', () {
      // 하루치 예산 900 을 셋으로 나누면 한 끼 345 — 단품은 거의 다 넘습니다.
      final res = suggestEatOut({'remainP': 90, 'remainKcal': 900, 'mealsLeft': 3, 'seed': '2026-09-25'});
      final cap = res['mealKcalCap'] as num;
      expect(cap, closeTo(345, 1e-6));
      for (final o in optionsOf(res)) {
        final over = (o['totalKcal'] as num) > cap;
        expect('${o['shape']}'.contains('열량 높음'), over, reason: '${sentence(o)} ${o['totalKcal']}kcal');
      }
    });

    test('화이트리스트 단품은 이름으로 정한 것 — 실제 kFoodDb 이름이고 사먹기 메뉴에 있다', () {
      for (final n in kCleanDish) {
        expect(kOneDish, contains(n));
      }
      expect(kCleanDish, contains('백반(생선구이)'));
      expect(kCleanDish, contains('샐러드(닭가슴살) 1볼'));
      expect(kCleanDish, isNot(contains('짜장면')));
      for (final n in ['짜장면', '김치볶음밥', '짬뽕', '떡볶이 1인분', '볶음밥(중식)']) {
        expect(suggestIsRefined([{'name': n}]), isTrue, reason: n);
      }
      expect(suggestIsRefined([{'name': '회덮밥'}]), isFalse);
    });
  });

  group('단백질 몫 — 끼니는 30~50g, 나머지는 간식으로', () {
    test('남은 단백질을 남은 끼니(+간식 1)로 나눠 30~50g 에 맞춘다', () {
      expect(kMealProteinMin, 30);
      expect(kMealProteinMax, 50);
      // 109 / (2+1) = 36.3 → 36. 두 끼 72 를 빼면 간식 몫 37.
      final a = suggestEatOut({'remainP': 109, 'remainKcal': 1530, 'mealsLeft': 2});
      expect(a['needP'], 36);
      expect(a['proteinGapG'], 37);
      expect(a['snackHint'], '단백질 37g 은 간식으로 — 그릭요거트 · 단백질 음료 · 훈제란');
      // 200 / 2 = 100 → 상한 50. 간식 몫 150 — 못 채우는 건 못 채운다고 말합니다.
      final b = suggestMeal({'remainP': 200, 'remainKcal': 2000, 'mealsLeft': 1});
      expect(b['needP'], 50);
      expect(b['proteinGapG'], 150);
      // 20 / 2 = 10 → 하한 30 이지만 남은 게 20 이라 20. 간식 몫 없음.
      final c = suggestEatOut({'remainP': 20, 'remainKcal': 900, 'mealsLeft': 1});
      expect(c['needP'], 20);
      expect(c['proteinGapG'], 0);
      expect(c['snackHint'], '');
      // 40 / 4 = 10 → 하한 30. 세 끼 90 > 40 이라 간식 몫 0.
      final d = suggestMeal({'remainP': 40, 'remainKcal': 1800, 'mealsLeft': 3});
      expect(d['needP'], 30);
      expect(d['proteinGapG'], 0);
    });

    test('간식 몫이 5g 미만이면 말하지 않는다', () {
      // 64 / 2 = 32 → 32. 한 끼 32 를 빼면 32 남는데 그건 간식 몫... 아니, 끼니 1 → 64-32 = 32.
      // 5g 미만을 보려면 68/(1+1)=34, 68-34 = 34 — 대신 몫이 딱 맞는 사례를 씁니다: 60/2 = 30 → 60-30 = 30.
      final res = suggestEatOut({'remainP': 33, 'remainKcal': 900, 'mealsLeft': 1});
      expect(res['needP'], 30, reason: '33/2 = 16.5 → 하한 30');
      expect(res['proteinGapG'], 3);
      expect(res['snackHint'], '', reason: '3g 을 간식으로 채우라는 말은 소음입니다');
    });

    test('aimP 를 주면 그대로 쓴다(호출부 재량)', () {
      final res = suggestEatOut({'remainP': 109, 'remainKcal': 1530, 'mealsLeft': 2, 'aimP': 60});
      expect(res['needP'], 60);
      expect(res['proteinGapG'], 0, reason: '60 × 2 > 109');
    });

    test('간식 추천에는 간식 안내가 없다 — 그 자체가 간식이라서', () {
      final res = suggestSnack({'remainP': 109, 'remainKcal': 1530, 'mealsLeft': 2});
      expect(res.containsKey('snackHint'), isFalse);
      expect(res.containsKey('proteinGapG'), isFalse);
      expect(res.containsKey('mealKcalCap'), isFalse);
    });

    test('집밥도 끼니 몫이 30~50g — 하루치 150g 을 한 끼에 몰지 않는다', () {
      final res = suggestMeal({'remainP': 150, 'remainKcal': 2200, 'mealsLeft': 3, 'seed': '2026-09-25'});
      expect(res['needP'], 38, reason: '150/4 = 37.5 → 38');
      for (final o in optionsOf(res)) {
        expect((o['totalP'] as num) < 60, isTrue, reason: sentence(o));
        expect((o['totalKcal'] as num) <= (res['mealKcalCap'] as num), isTrue, reason: sentence(o));
      }
    });
  });

  group('회전', () {
    const base = {'remainP': 60, 'remainKcal': 900, 'mealsLeft': 1};

    test('같은 날은 같은 답', () {
      final a = suggestEatOut({...base, 'seed': '2026-09-24'});
      final b = suggestEatOut({...base, 'seed': '2026-09-24'});
      expect(optionsOf(a).map(sentence).toList(), optionsOf(b).map(sentence).toList());
    });

    test('다음 날은 다른 첫 줄 — 사먹기·집밥·간식 모두', () {
      final days = ['2026-09-24', '2026-09-25', '2026-09-26', '2026-09-27'];
      for (final fn in [suggestEatOut, suggestMeal, suggestSnack]) {
        for (var i = 1; i < days.length; i++) {
          final prev = fn({...base, 'seed': days[i - 1]});
          final next = fn({...base, 'seed': days[i]});
          expect(firstMain(next), isNot(firstMain(prev)),
              reason: '${days[i]}: ${sentence(optionsOf(next).first)}');
        }
      }
    });

    test('돌려도 보이는 것은 이번 몫을 채우는 것들 — 아홉째 후보로 밀리지 않는다', () {
      for (var d = 1; d <= 28; d++) {
        final seed = '2026-09-${d.toString().padLeft(2, '0')}';
        final res = suggestEatOut({...base, 'seed': seed});
        expect(res['feasible'], isTrue, reason: seed);
        final needP = res['needP'] as num;
        for (final o in optionsOf(res)) {
          expect((o['totalP'] as num) >= needP * 0.9, isTrue, reason: '$seed ${sentence(o)}');
        }
      }
    });

    test('사흘 주기가 아니다 — 세 줄 묶음이 한 주 안에 그대로 돌아오지 않는다', () {
      /* 예전엔 풀 9개에 보폭 3이라 시작점이 0·3·6 세 자리뿐이었습니다(9/20 = 9/23 = 9/26). */
      for (final fn in [suggestEatOut, suggestMeal, suggestSnack]) {
        final rows = <String>[];
        for (var d = 20; d <= 26; d++) {
          final res = fn({...base, 'seed': '2026-09-$d'});
          rows.add(optionsOf(res).map(sentence).join(' | '));
        }
        expect(rows.toSet().length, rows.length, reason: '7일 안에 같은 세 줄이 돌아왔습니다: $rows');
      }
    });

    test('사먹기 — 한 날 세 줄에 같은 단품이 두 번 서지 않는다', () {
      for (var d = 1; d <= 28; d++) {
        for (final p in [30, 60, 90]) {
          final res = suggestEatOut({'remainP': p, 'remainKcal': 900, 'mealsLeft': 1, 'seed': '2026-09-${d.toString().padLeft(2, '0')}'});
          final dishes = [for (final o in optionsOf(res)) '${itemsOf(o).first['name']}'];
          expect(dishes.toSet().length, dishes.length, reason: '$d일 P$p: $dishes');
          for (final o in optionsOf(res)) {
            expect(o['main'], itemsOf(o).first['name'], reason: '사먹기의 주인공은 단품');
          }
        }
      }
    });

    test('씨앗이 없거나 모양이 아니면 점수순 그대로', () {
      for (final seed in [null, '', 'abc', '2026-13-01', 42]) {
        final res = suggestEatOut({...base, if (seed != null) 'seed': seed});
        final scores = optionsOf(res).map((o) => (o['score'] as num).toDouble()).toList();
        for (var i = 1; i < scores.length; i++) {
          expect(scores[i] >= scores[i - 1], isTrue, reason: 'seed=$seed $scores');
        }
      }
    });

    test('날짜 → 일수는 정수 산수로(원본과 같은 값)', () {
      expect(suggestDayNumber('1970-01-01'), 0);
      expect(suggestDayNumber('2000-02-29'), 11016);
      expect(suggestDayNumber('2026-09-24'), 20720);
      expect(suggestDayNumber('2026-09-25'), 20721);
      expect(suggestDayNumber('2026-9-5'), 20701, reason: '0 을 안 채워도 날짜입니다');
      // DateTime 과도 맞아야 합니다 — 시간대가 안 끼는 UTC 기준.
      for (final s in ['2024-02-28', '2024-02-29', '2024-03-01', '2027-12-31', '2028-01-01']) {
        final dt = DateTime.parse('${s}T00:00:00Z');
        expect(suggestDayNumber(s), dt.millisecondsSinceEpoch ~/ 86400000, reason: s);
      }
      for (final bad in ['', 'abc', '2026-13-01', '2026-00-10', '2026-09-32', '20260924', 42, null]) {
        expect(suggestDayNumber(bad), isNull, reason: '$bad');
      }
    });
  });

  group('분량 표기', () {
    String pt(String unit, num mult, [String name = 'x']) =>
        portionText({'name': name, 'unit': unit, 'mult': mult});

    test("'1개 × 2' 는 '2개', '100g × 2' 는 '200g'", () {
      expect(pt('1개', 2), '2개');
      expect(pt('100g', 2), '200g');
      expect(pt('100g', 1.5), '150g');
      expect(pt('200ml', 2), '400ml');
      expect(pt('2쪽', 1.5), '3쪽');
      expect(pt('1팩100g', 2), '2팩200g');
      expect(pt('1컵100g', 2), '2컵200g');
      expect(pt('1스쿱30g+물250ml', 2), '2스쿱60g+물500ml');
      expect(pt('5개(가식 140g)', 2), '10개(가식 280g)');
      expect(pt('미디엄 1개', 2), '미디엄 2개');
    });

    test('정수가 안 되면 예전 표기로 돌아간다', () {
      expect(pt('1개', 1.5), '1개 × 1.5');
      expect(pt('1스쿱30g+물250ml', 1.5), '1스쿱30g+물250ml × 1.5');
    });

    test('크기·분수·이름에 든 분량은 건드리지 않는다', () {
      expect(pt('1개 15cm', 2), '2개 15cm', reason: '15cm 는 개수가 아닙니다');
      expect(pt('1/2모150g', 2), '1/2모150g × 2');
      expect(pt('반마리', 2), '반마리 × 2');
      expect(pt('5개', 2, '만두(고기) 5개'), '× 2', reason: '이름이 분량을 품으면 단위는 비웁니다');
    });

    test('1배와 반은 예전과 같다', () {
      expect(pt('1개', 1), '1개');
      expect(pt('1개', 0.5), '1개 반');
    });

    String it(String name, String unit, num mult) => itemText({'name': name, 'unit': unit, 'mult': mult});

    test('itemText — 이름 끝의 수량은 단위로 다시 말한다: 「훈제란 1개 1개 55g」 이 아니라 「훈제란 1개 55g」', () {
      expect(it('훈제란 1개', '1개 55g', 1), '훈제란 1개 55g');
      expect(it('훈제란 1개', '1개 55g', 2), '훈제란 2개 110g');
      expect(it('닭가슴살 스테이크(시판) 1팩', '1팩 100g', 1), '닭가슴살 스테이크(시판) 1팩 100g');
      expect(it('닭가슴살 스테이크(시판) 1팩', '1팩 100g', 2), '닭가슴살 스테이크(시판) 2팩 200g');
      expect(it('단백질 음료(하이뮨) 1병', '1병 190ml', 2), '단백질 음료(하이뮨) 2병 380ml');
      expect(it('만두(고기) 5개', '5개', 2), '만두(고기) 10개');
      expect(it('코티지치즈 100g', '100g', 2), '코티지치즈 200g');
      expect(it('코티지치즈 100g', '100g', 1), '코티지치즈 100g');
      /* 이름에 수량이 없으면 예전 그대로. */
      expect(it('계란(삶음)', '1개', 2), '계란(삶음) 2개');
      expect(it('참치캔(기름뺀)', '1캔100g', 1.5), '참치캔(기름뺀) 1캔100g × 1.5');
      expect(it('족발 1인분', '200g', 1), '족발 1인분 200g', reason: '1인분은 단위(200g)의 수량이 아닙니다');
      /* 새로 들어온 백반집 메뉴 — '갈매기살 구이 1인분' 의 1인분은 단위 '1인분 150g' 의 수량입니다. */
      expect(it('갈매기살 구이 1인분', '1인분 150g', 1), '갈매기살 구이 1인분 150g');
      expect(it('모둠회 1인분', '1인분 200g', 1), '모둠회 1인분 200g');
      expect(suggestCountToken('1팩 100g'), '1팩');
      expect(suggestCountToken('100g'), '');
      expect(suggestCountToken('1/2모150g'), '');
      expect(suggestCountToken('미디엄 1개'), '1개');
    });

    test('셀 수 있는 단위에 1.5배는 없다 — 「계란 1개 × 1.5」 가 추천에 안 뜬다', () {
      final inputs = [
        for (final p in [20, 40, 60, 90])
          for (final k in [300, 500, 900, 1400])
            for (final d in ['2026-09-20', '2026-09-24'])
              {'remainP': p, 'remainKcal': k, 'mealsLeft': 1, 'seed': d},
      ];
      var seen = 0;
      for (final opts in inputs) {
        for (final res in [suggestEatOut(opts), suggestMeal(opts), suggestSnack(opts)]) {
          for (final o in optionsOf(res)) {
            for (final x in itemsOf(o)) {
              seen++;
              final unit = '${x['unit']}';
              expect(portionText(x), isNot(contains('× 1.5')), reason: '${x['name']} $unit');
              expect(itemText(x), isNot(contains('×')), reason: '${x['name']} $unit — 말로 적히는 분량만');
            }
          }
        }
      }
      expect(seen, greaterThan(50));
    });
  });
}
