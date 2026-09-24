/* 주간 체크인 판정 — 흔들림에 반응하지 않는가, 방향을 맞게 잡는가.
 *
 * 예전 판정은 계획 다음 날 집 체중계 값(86.2)이 인바디(86.7)와 0.5kg
 * 다르다는 이유로 "빠릅니다 · 하루 150kcal 늘리기" 를 냈습니다. 여기 사례는
 * 그 일이 다시 안 나는지, 그리고 제안이 나올 때는 계획의 방향(감량 · 증량)에
 * 맞는지 봅니다. JS 원본과 같은 답인지는 tools/difftest.js 가 봅니다. */
import 'package:mybody_core/engine.dart';
import 'package:test/test.dart';

Map<String, Object?> planOf(List<double> weights, {Map<String, Object?>? extra}) => {
      'startDate': '2026-09-22',
      'trajectory': [
        for (var i = 0; i < weights.length; i++) {'week': i, 'weightKg': weights[i], 'ffmKg': 66.0},
      ],
      'macros': {'intakeKcal': 2200, 'proteinG': 160, 'carbG': 220, 'fatG': 70, 'deficitKcal': 500},
      'workout': {'cardioMinPerWeek': 60},
      ...?extra,
    };

/// 감량: 주마다 0.4kg.
final cut = planOf([86.7, 86.3, 85.9, 85.5, 85.1, 84.7]);
/// 증량: 주마다 0.25kg.
final gain = planOf([70.0, 70.25, 70.5, 70.75, 71.0, 71.25]);

List<Map<String, Object?>> rd(List<List<num>> xs) =>
    [for (final x in xs) {'week': x[0], 'weightKg': x[1]}];

void main() {
  test('첫 체크인은 판정하지 않는다 — 0주차에 인바디와 0.5kg 달라도', () {
    final r = checkinReview(cut, rd([[0, 86.2]]), null);
    expect(r['status'], 'early');
    expect(r['apply'], isNull);
    expect((r['suggestions'] as List).first['title'], '기준 체중을 잡았습니다');
  });

  test('같은 주에 두 번 넣어도 기준점 하나다 (그 주의 마지막 값)', () {
    final r = checkinReview(cut, rd([[0, 86.2], [0, 86.0]]), null);
    expect(r['status'], 'early');
    expect(r['weeks'], 1);
  });

  test('계획선과 같은 속도면 계획대로 — 체중계가 인바디보다 0.5kg 낮아도', () {
    /* 기준 86.2(인바디보다 0.5 낮음), 그다음 주 85.8 = 계획처럼 0.4 빠짐. */
    final r = checkinReview(cut, rd([[0, 86.2], [1, 85.8]]), null);
    expect(r['status'], 'onTrack');
    expect(r['devKg'], 0);
  });

  test('한 번 벗어나면 지켜본다 — 조정 제안 없음', () {
    final r = checkinReview(cut, rd([[0, 86.2], [1, 86.4]]), null);   // 0.6 느림
    expect(r['status'], 'watch');
    expect(r['devKg'], 0.6);
    expect(r['apply'], isNull);
  });

  test('0.5kg 경계 안쪽은 흔들림이다', () {
    final r = checkinReview(cut, rd([[0, 86.2], [1, 86.2]]), null);   // 0.4 느림
    expect(r['status'], 'onTrack');
  });

  test('감량인데 두 번 연속 느리면 — 150kcal 줄이고 유산소 40분', () {
    final r = checkinReview(cut, rd([[0, 86.2], [1, 86.4], [2, 86.1]]), null);
    expect(r['status'], 'slow');
    expect(r['apply'], {'kcalDelta': -150, 'cardioMinDelta': 40});
  });

  test('감량인데 두 번 연속 빠르면 — 150kcal 늘리기', () {
    final r = checkinReview(cut, rd([[0, 86.2], [1, 85.1], [2, 84.6]]), null);
    expect(r['status'], 'fast');
    expect(r['apply'], {'kcalDelta': 150, 'cardioMinDelta': 0});
  });

  test('벗어난 방향이 바뀌면 연속이 아니다', () {
    final r = checkinReview(cut, rd([[0, 86.2], [1, 86.5], [2, 84.9]]), null);   // +0.7 → −0.5
    expect(r['status'], 'watch');
  });

  test('증량인데 덜 늘면 느린 것이고, 그때는 더 먹는다', () {
    /* 예전엔 "느림" 이면 계획과 상관없이 줄이라고 했습니다. */
    final r = checkinReview(gain, rd([[0, 70.0], [1, 69.6], [2, 69.8]]), null);
    expect(r['gaining'], isTrue);
    expect(r['status'], 'slow');
    expect(r['apply'], {'kcalDelta': 150, 'cardioMinDelta': 0});
  });

  test('증량인데 너무 빨리 늘면 줄인다', () {
    final r = checkinReview(gain, rd([[0, 70.0], [1, 71.0], [2, 71.3]]), null);
    expect(r['status'], 'fast');
    expect(r['apply'], {'kcalDelta': -150, 'cardioMinDelta': 0});
  });

  test('식단을 70% 미만으로 지켰으면 숫자를 건드리지 않는다 (먼저 봄)', () {
    final r = checkinReview(cut, rd([[0, 86.2], [1, 86.4], [2, 86.1]]), {'dietPct': 40});
    expect(r['status'], 'adherence');
    expect(r['apply'], isNull);
  });

  test('조정한 뒤에는 그때 체크인을 새 기준점으로 — 같은 차이로 또 줄이지 않는다', () {
    final adjusted = {
      ...cut,
      'adjustments': [
        {'at': '2026-10-06T00:00:00.000Z', 'kcalDelta': -150},
      ],
    };
    final readings = [
      {'week': 0, 'weightKg': 86.2, 'at': '2026-09-22T00:00:00.000Z'},
      {'week': 1, 'weightKg': 86.4, 'at': '2026-09-29T00:00:00.000Z'},
      {'week': 2, 'weightKg': 86.1, 'at': '2026-10-06T00:00:00.000Z'},   // 조정하며 저장
      {'week': 3, 'weightKg': 85.7, 'at': '2026-10-13T00:00:00.000Z'},   // 그 뒤로 계획 속도
    ];
    final r = checkinReview(adjusted, readings, null);
    expect(r['baseWeek'], 2);
    expect(r['status'], 'onTrack', reason: '기준점부터 쌓인 0.9kg 로 또 줄이라고 하면 매주 내려갑니다');
    final only = checkinReview(adjusted, readings.take(3).toList(), null);
    expect(only['status'], 'early');
    expect((only['suggestions'] as List).first['title'], '조정 뒤 기준을 새로 잡았습니다');
  });

  test('이상한 값은 건너뛴다', () {
    final r = checkinReview(cut, [
      null, {'week': '1', 'weightKg': 80}, {'week': 1, 'weightKg': 0},
      {'week': 1, 'weightKg': '80'}, {'week': 0, 'weightKg': 86.2},
    ], null);
    expect(r['weeks'], 1);
    expect(r['status'], 'early');
  });

  group('적용', () {
    final slow = checkinReview(cut, rd([[0, 86.2], [1, 86.4], [2, 86.1]]), null);
    const male = {'sex': 'male', 'mealsPerDay': 3};

    test('칼로리를 탄수로 맞춰 줄이고, 유산소를 더하고, 기록을 남긴다 — 원래 계획은 그대로', () {
      final res = applyCheckinAdvice(cut, slow, male, 2, '2026-10-06T00:00:00.000Z')!;
      final p = (res['plan'] as Map).cast<String, Object?>();
      final m = p['macros'] as Map;
      expect(m['intakeKcal'], 2050);
      expect(m['carbG'], 183);                     // 220 − 37.5 → 반올림
      expect(m['deficitKcal'], 650);
      expect((p['workout'] as Map)['cardioMinPerWeek'], 100);
      expect(p['diet'], isNotNull);
      expect((p['adjustments'] as List).single['at'], '2026-10-06T00:00:00.000Z');
      expect(res['floored'], isFalse);
      expect((cut['macros'] as Map)['intakeKcal'], 2200, reason: '원래 계획을 고치면 안 됩니다');
    });

    test('하한(남성 1500 · BMR×1.1) 밑으로는 안 내린다', () {
      final low = {...cut, 'macros': {'intakeKcal': 1600, 'proteinG': 150, 'carbG': 120, 'fatG': 50}};
      final res = applyCheckinAdvice(low, slow, male, 2, 'x')!;
      /* ffm 66 → BMR 1795.6 → ×1.1 = 1975 > 1500. 이미 하한 밑이라 그대로. */
      expect(res['kcalDelta'], 0);
      expect(res['floored'], isTrue);
      expect(((res['plan'] as Map)['macros'] as Map)['intakeKcal'], 1600);
    });

    test('적용할 제안이 없으면 null', () {
      final ok = checkinReview(cut, rd([[0, 86.2], [1, 85.8]]), null);
      expect(applyCheckinAdvice(cut, ok, male, 1, 'x'), isNull);
      expect(applyCheckinAdvice(null, slow, male, 1, 'x'), isNull);
    });
  });

  test('계획 주차 — 시작일부터 7일마다, 시작 전은 0', () {
    expect(planWeekOf('2026-09-22', '2026-09-22'), 0);
    expect(planWeekOf('2026-09-22', '2026-09-28'), 0);
    expect(planWeekOf('2026-09-22', '2026-09-29'), 1);
    expect(planWeekOf('2026-09-22', '2026-09-01'), 0);
    expect(planWeekOf(null, '2026-09-29'), 0);
  });
}
