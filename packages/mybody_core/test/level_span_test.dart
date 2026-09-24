/* 상 · 중 · 하가 같은 계획일 때 엔진이 하는 말.
 *
 * 「감량모드」에서 세 강도가 모두 모드의 가장 느린 속도(공격성 0.35)로 모이자 앱은 똑같은
 * 카드 세 장을 보여 주고, 엔진은 "이 목표가 25~25주입니다 · 위로는 에너지 상한에 걸립니다"
 * 라고 했습니다 — 이 경우 기간을 정하는 것은 근육이 붙는 속도였습니다. 경고도 "중·하가 같은
 * 계획" 이라고 해서, 상까지 셋 다 같은 것과 맞지 않았습니다.
 * JS 원본과 같은 답인지는 tools/difftest.js 가 봅니다. */
import 'package:mybody_core/engine.dart';
import 'package:mybody_core/mybody_core.dart' show modeById;
import 'package:test/test.dart';

const scan53 = {
  'weightKg': 78.0, 'smmKg': 37.3, 'bfmKg': 12.1, 'pbfPct': 15.5, 'ffmKg': 65.9,
  'bmrKcal': 1794, 'measuredAt': '2026-09-18T11:11:00.000Z',
};
const prof53 = {
  'sex': 'male', 'age': 53, 'heightCm': 186, 'activityLevel': 'moderate',
  'trainingAge': 'intermediate', 'daysPerWeek': 4, 'mealsPerDay': 3,
};
const scanOwner = {
  'weightKg': 86.7, 'smmKg': 38.0, 'bfmKg': 20.0, 'pbfPct': 23.1, 'ffmKg': 66.7,
  'bmrKcal': 1810, 'measuredAt': '2026-03-01T00:00:00.000Z',
};
const profOwner = {
  'sex': 'male', 'age': 22, 'heightCm': 187, 'activityLevel': 'moderate',
  'trainingAge': 'novice', 'daysPerWeek': 4, 'mealsPerDay': 3,
};

List<Map> resultsOf(Map<String, Object?> c) => (c['results'] as List).cast<Map>();

void main() {
  test('셋이 같은 계획이면 "N주 하나" 라고 말하고, 이유는 근육 속도 — "N~N주" · "에너지 상한" 이 아니라', () {
    final c = compareLevels({...scan53}, {...prof53},
        {'weightKg': 75.1, 'smmKg': 37.9, 'bfmKg': 8.1}, '2026-09-24', null, modeById('fatLoss'));
    final rs = resultsOf(c);
    expect({for (final r in rs) r['a']}.length, 1, reason: '세 강도가 같은 공격성');
    final w = rs.first['weeks'];
    expect(c['spanWeeks'], [w, w]);
    final text = '${(c['spanNote'] as Map)['text']}';
    expect(text, contains('$w주 하나'));
    expect(text, isNot(contains('$w~$w')));
    expect(text, contains('상·중·하가 같은 계획'));
    expect(text, contains('근육이 붙는 속도'));
    expect(text, isNot(contains('에너지 상한')));
    expect(text, contains('공격성 0.35'));
    /* spanNote 가 설명하므로 같은 말을 경고로 또 하지 않습니다(「주의」 숫자만 늘었음). */
    for (final warn in (c['warnings'] as List)) {
      expect('$warn', isNot(contains('같은 계획')));
    }
  });

  test('폭은 실제로 고를 수 있는 카드의 기간 — 곡선의 가장 느린 점이 아니라', () {
    final c = compareLevels({...scan53}, {...prof53},
        {'weightKg': 74.0, 'smmKg': 37.3, 'bfmKg': 8.1}, '2026-09-24', null, null);
    final ws = [for (final r in resultsOf(c)) r['weeks'] as num];
    final hi = ws.reduce((a, b) => a > b ? a : b);
    expect((c['spanWeeks'] as List).last, hi);
    expect('${(c['spanNote'] as Map)['text']}', contains('${ws.first}~$hi주'));
  });

  test('폭이 좁은 이유는 그 계획에서 읽는다 — 하 카드가 모드 하한이면 "하한에 닿았고"', () {
    final c = compareLevels({...scanOwner}, {...profOwner},
        {'weightKg': 80.5, 'smmKg': 39.0, 'bfmKg': 12.0}, '2026-03-01', null, modeById('cutting'));
    final text = '${(c['spanNote'] as Map)['text']}';
    expect(text, contains('폭이 좁은 이유'));
    expect(text, contains('가장 느린 속도(공격성 0.4)에 이미 닿았고'));
    expect(resultsOf(c).last['a'], closeTo(0.4, 0.005));
  });

  test('"N주 하나" 는 셋이 모두 같을 때만 — 하나라도 다르면 "N~M주"', () {
    var sawOne = false, sawMany = false;
    for (final ds in [0.5, 1.0, 1.5, 2.0]) {
      for (final df in [-6.0, -4.0, -2.0]) {
        final smm = 38.0 + ds, bfm = 20.0 + df;
        final c = compareLevels({...scanOwner}, {...profOwner},
            {'weightKg': double.parse((smm / (38 / 66.7) + bfm).toStringAsFixed(1)), 'smmKg': smm, 'bfmKg': bfm},
            '2026-03-01', null, modeById('fatLoss'));
        if (c['impossible'] == true) continue;
        final distinct = {for (final r in resultsOf(c)) r['a']}.length;
        final text = '${(c['spanNote'] as Map)['text']}';
        if (distinct == 1) {
          expect(text, contains('주 하나'));
          sawOne = true;
        } else {
          expect(text, isNot(contains('주 하나')));
          sawMany = true;
        }
      }
    }
    expect(sawOne && sawMany, isTrue, reason: '두 경우를 다 밟아야 이 시험이 뭔가를 봅니다');
  });
}
