/* 「뭘 먹을까」 추천이 지켜야 하는 성질들.
 *
 * 2026-09 피드백: "족발·갈비탕이 뜬다, 매일 똑같다, '1개 × 2' 가 뭐냐".
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
bool greasyShown(Map<String, Object?> option) {
  var kc = 0.0, f = 0.0;
  for (final x in itemsOf(option)) {
    for (final k in kGreasy) {
      if ('${x['name']}'.contains(k)) return true;
    }
    kc += (x['kcal'] as num).toDouble();
    f += (x['f'] as num).toDouble();
  }
  return kc > 0 && f * 9 / kc > kFatKcalMax;
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

    test('피드백 캡처의 족발·갈비탕·설렁탕은 사먹기 첫 화면에 안 뜬다', () {
      final res = suggestEatOut({'remainP': 60, 'remainKcal': 900, 'mealsLeft': 1});
      final all = optionsOf(res).map(sentence).join(' / ');
      expect(all, isNot(contains('족발')));
      expect(all, isNot(contains('갈비탕')));
      expect(all, isNot(contains('설렁탕')));
      expect(res['feasible'], isTrue);
    });

    test('담백한 후보가 모자랄 때만 기름진 것을 뒤에 붙이고 표시한다', () {
      // 300kcal 아래 단품은 피자 한 조각·컵라면뿐입니다(김밥 323).
      final res = suggestEatOut({'remainP': 30, 'remainKcal': 300, 'mealsLeft': 1});
      final opts = optionsOf(res);
      expect(opts, isNotEmpty);
      for (final o in opts) {
        expect('${o['shape']}', contains('지방 많음'));
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
        for (final o in optionsOf(res)) {
          expect((o['totalP'] as num) >= 60 * 0.9, isTrue, reason: '$seed ${sentence(o)}');
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
