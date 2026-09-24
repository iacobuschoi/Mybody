/* 목표 도달 계산 — 지방을 "거의 그대로" 두는 목표가 막히지 않는가.
 *
 * 53세 남성 · 186cm · 78.0kg · 골격근 37.3 · 체지방 12.1 인 사람이 골격근 38.3 · 체지방률
 * 14.9%(체지방 11.9)를 넣자 "어떤 강도로도 4년 안에 목표에 도달하지 않습니다" 가 나왔습니다.
 * 지방 −1kg · −0.5kg 목표는 되고, +1kg 도 되는데, −0.3 ~ +0.9kg 사이만 안 됐습니다:
 *  · 0.05~0.3kg 줄이기는 "지방 목표 없음" 으로 증량을 시작하는데, 끝의 지방은 목표 + 0.05
 *    안이어야 해서 시작부터 이미 넘은 상태였고,
 *  · 증량이 지방을 목표 위로 올린 **뒤에** 멈춰서, 그 한 주 몫만큼 넘은 채로 끝났습니다.
 * JS 원본과 같은 답인지는 tools/difftest.js 가 봅니다. */
import 'package:mybody_core/engine.dart';
import 'package:test/test.dart';

const scan = {
  'weightKg': 78.0, 'smmKg': 37.3, 'bfmKg': 12.1, 'pbfPct': 15.5, 'ffmKg': 65.9,
  'bmrKcal': 1794, 'measuredAt': '2026-09-18T11:11:00.000Z',
};
const profile = {
  'sex': 'male', 'age': 53, 'heightCm': 186, 'activityLevel': 'moderate',
  'trainingAge': 'novice', 'daysPerWeek': 4, 'mealsPerDay': 3,
};

Map<String, Object?> run(double smm, double bfm) {
  final ffm = 65.9 * smm / 37.3;
  return compareLevels({...scan}, {...profile},
      {'weightKg': double.parse((ffm + bfm).toStringAsFixed(1)), 'smmKg': smm, 'bfmKg': bfm},
      '2026-09-24', null, null);
}

void main() {
  test('근육 +1kg · 체지방 −0.2kg 목표에 계획이 나온다 — 끝의 체지방이 목표 안', () {
    final c = run(38.3, 11.9);
    expect(c['impossible'], isNot(true));
    final results = (c['results'] as List).cast<Map>();
    expect(results, isNotEmpty);
    for (final r in results) {
      final tr = ((r['sim'] as Map)['trajectory'] as List).cast<Map>();
      expect(tr.last['smmKg'] as num, greaterThanOrEqualTo(38.3 - 0.005));
      expect(tr.last['bfmKg'] as num, lessThanOrEqualTo(11.9 + 0.05));
      expect(r['weeks'] as num, lessThan(60));
    }
  });

  test('근육 +1kg 이면 체지방 목표를 −1 ~ +1kg 어디에 두어도 계획이 나온다 (구멍이 없다)', () {
    for (final d in [-1.0, -0.5, -0.3, -0.2, -0.1, 0.0, 0.2, 0.5, 0.9, 1.0]) {
      final c = run(38.3, double.parse((12.1 + d).toStringAsFixed(1)));
      expect(c['impossible'], isNot(true), reason: '체지방 ${d >= 0 ? '+' : ''}$d kg');
    }
  });

  test('지방 목표가 빠듯한 증량은 분할(증량 → 미니컷)과 견줘 빠른 쪽 — 경력자가 1년 넘게 걸리지 않게', () {
    /* 동시 진행은 유지 칼로리로만 근육을 붙여 중급 64주 · 숙련 148주였습니다. */
    for (final e in {'intermediate': 30, 'advanced': 50}.entries) {
      final c = compareLevels({...scan}, {...profile, 'trainingAge': e.key},
          {'weightKg': 79.6, 'smmKg': 38.3, 'bfmKg': 11.9}, '2026-09-24', null, null);
      final hi = (c['results'] as List).first as Map;
      expect(hi['weeks'] as num, lessThanOrEqualTo(e.value), reason: e.key);
      expect((hi['sim'] as Map)['strategy'], 'split', reason: e.key);
    }
  });

  test('지방 여유가 넉넉한 증량은 그대로 동시 진행', () {
    final c = run(38.3, 14.1);
    for (final r in (c['results'] as List).cast<Map>()) {
      expect((r['sim'] as Map)['strategy'], 'simultaneous');
    }
  });

  test('증량은 체지방을 목표 위로 올리기 전에 멈춘다 — 끝의 체지방이 목표 + 0.05 안', () {
    final c = run(38.3, 12.6);
    for (final r in (c['results'] as List).cast<Map>()) {
      final tr = ((r['sim'] as Map)['trajectory'] as List).cast<Map>();
      for (final p in tr) {
        expect(p['bfmKg'] as num, lessThanOrEqualTo(12.6 + 0.05), reason: '${p['week']}주');
      }
    }
  });
}
