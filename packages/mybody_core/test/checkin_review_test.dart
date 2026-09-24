/* 주간 체크인 판정 — 흔들림에 반응하지 않는가, 방향을 맞게 잡는가.
 *
 * 예전 판정은 계획 다음 날 집 체중계 값(86.2)이 인바디(86.7)와 0.5kg
 * 다르다는 이유로 "빠릅니다 · 하루 150kcal 늘리기" 를 냈습니다. 여기 사례는
 * 그 일이 다시 안 나는지, 검토에서 짚힌 세 가지(요일 차이 · 하루치 기준의
 * 흔들림 · 단계가 바뀌는 계획의 방향)가 고쳐졌는지, 그리고 제안이 나올 때
 * 방향이 맞는지 봅니다. JS 원본과 같은 답인지는 tools/difftest.js 가 봅니다. */
import 'package:mybody_core/engine.dart';
import 'package:test/test.dart';

Map<String, Object?> planOf(List<double> weights, {String? phase, List<String>? phases}) => {
      'startDate': '2026-09-22',
      'trajectory': [
        for (var i = 0; i < weights.length; i++)
          {
            'week': i, 'weightKg': weights[i], 'ffmKg': 66.0,
            if (phases != null) 'phase': phases[i] else if (phase != null) 'phase': phase,
          },
      ],
      'macros': {'intakeKcal': 2200, 'proteinG': 160, 'carbG': 220, 'fatG': 70, 'deficitKcal': 500},
      'workout': {'cardioMinPerWeek': 60, 'cardioPlan': 'Z2 저강도 40분 × 2회'},
    };

/// 감량: 주마다 0.4kg.
final cut = planOf([86.7, 86.3, 85.9, 85.5, 85.1, 84.7, 84.3], phase: 'cut');
/// 증량: 주마다 0.25kg.
final gain = planOf([70.0, 70.25, 70.5, 70.75, 71.0, 71.25, 71.5], phase: 'bulk');

/// [날, 체중] — 주차는 날에서 셉니다.
List<Map<String, Object?>> rd(List<List<num>> xs) =>
    [for (final x in xs) {'week': (x[0] / 7).floor(), 'day': x[0], 'weightKg': x[1]}];

void main() {
  test('첫 체크인은 판정하지 않는다 — 0주차에 인바디와 0.5kg 달라도', () {
    final r = checkinReview(cut, rd([[1, 86.2]]), null);
    expect(r['status'], 'early');
    expect(r['apply'], isNull);
    expect((r['suggestions'] as List).first['title'], '기준 체중을 잡았습니다');
  });

  test('같은 주에 두 번 넣어도 기준점 하나다 (그 주의 마지막 값)', () {
    final r = checkinReview(cut, rd([[0, 86.2], [3, 86.0]]), null);
    expect(r['status'], 'early');
    expect(r['weeks'], 1);
  });

  test('계획선과 같은 속도면 계획대로 — 체중계가 인바디보다 0.5kg 낮아도', () {
    final r = checkinReview(cut, rd([[0, 86.2], [7, 85.8]]), null);
    expect(r['status'], 'onTrack');
    expect(r['devKg'], 0);
  });

  test('요일이 달라도 계획선 위면 계획대로 — 월요일 기준, 일요일 체크인', () {
    /* 예전엔 주 단위로 잘라 읽어서 13일째를 1주차(=7일째 계획값)와 견줬고,
       한 주 감량분의 6/7 만큼 "빠릅니다" 쪽으로 밀렸습니다. */
    double line(num d) => 86.7 - 0.4 * d / 7;
    final r = checkinReview(cut, rd([
      [0, line(0)], [13, line(13)], [20, line(20)], [27, line(27)],
    ]), null);
    expect(r['status'], 'onTrack');
  });

  test('한 번 벗어나면 지켜본다 — 조정 제안 없음', () {
    final r = checkinReview(cut, rd([[0, 86.2], [7, 86.4]]), null);   // 0.6 무거움
    expect(r['status'], 'watch');
    expect(r['devKg'], 0.6);
    expect(r['apply'], isNull);
  });

  test('0.5kg 경계 안쪽은 흔들림이다', () {
    final r = checkinReview(cut, rd([[0, 86.2], [7, 86.2]]), null);   // 0.4 무거움
    expect(r['status'], 'onTrack');
  });

  test('기준이 하루치 하나면 두 번 벗어나도 지켜본다 — 그날이 흔들린 날일 수 있어서', () {
    /* 기준 날 0.6 낮게 나오고 그 뒤 두 번은 정확히 계획선 위. 예전엔 "두 번 연속
       느림" 으로 150kcal 을 줄였습니다. */
    final r = checkinReview(cut, rd([[0, 86.1], [7, 86.3], [14, 85.9]]), null);
    expect(r['status'], 'watch');
    expect(r['apply'], isNull);
    expect(r['baseCount'], 1);
  });

  test('감량인데 정체가 이어지면(기준 두 번 + 두 번 연속) — 150kcal 줄이고 유산소 40분', () {
    final r = checkinReview(cut, rd([[0, 86.2], [7, 86.2], [14, 86.2], [21, 86.2]]), null);
    expect(r['status'], 'slow');
    expect(r['direction'], 'cut');
    expect(r['apply'], {'kcalDelta': -150, 'cardioMinDelta': 40});
  });

  test('감량인데 두 번 연속 빠르면 — 150kcal 늘리기', () {
    final r = checkinReview(cut, rd([[0, 86.2], [7, 85.8], [14, 84.8], [21, 84.3]]), null);
    expect(r['status'], 'fast');
    expect(r['apply'], {'kcalDelta': 150, 'cardioMinDelta': 0});
  });

  test('벗어난 방향이 바뀌면 연속이 아니다', () {
    final r = checkinReview(cut, rd([[0, 86.2], [7, 85.8], [14, 86.5], [21, 84.4]]), null);
    expect(r['status'], 'watch');
  });

  test('증량인데 덜 늘면 느린 것이고, 그때는 더 먹는다', () {
    final r = checkinReview(gain, rd([[0, 70.0], [7, 70.2], [14, 69.8], [21, 69.9]]), null);
    expect(r['direction'], 'gain');
    expect(r['status'], 'slow');
    expect(r['apply'], {'kcalDelta': 150, 'cardioMinDelta': 0});
  });

  test('증량인데 너무 빨리 늘면 줄인다', () {
    final r = checkinReview(gain, rd([[0, 70.0], [7, 70.3], [14, 71.3], [21, 71.6]]), null);
    expect(r['status'], 'fast');
    expect(r['apply'], {'kcalDelta': -150, 'cardioMinDelta': 0});
  });

  test('감량 → 증량 계획의 감량 구간에서 정체하면 "느림 · 줄이기" (끝점으로 방향을 정하지 않는다)', () {
    /* 끝이 시작보다 무거운 계획(감량 뒤 증량). 예전엔 전체를 증량 계획으로 봐서
       감량 중 정체를 "빨리 늘었습니다" 로 말했습니다. */
    final split = planOf([60.0, 59.6, 59.2, 58.8, 59.2, 59.8, 60.6, 61.4],
        phases: ['cut', 'cut', 'cut', 'cut', 'bulk', 'bulk', 'bulk', 'bulk']);
    final r = checkinReview(split, rd([[0, 60.0], [7, 60.0], [14, 60.0], [21, 60.0]]), null);
    expect(r['direction'], 'cut');
    expect(r['status'], 'slow');
    expect(r['apply'], {'kcalDelta': -150, 'cardioMinDelta': 40});
  });

  test('유지 단계는 무거움 · 가벼움으로 말하고 유산소를 더하지 않는다', () {
    final keep = planOf([80, 80, 80, 80, 80, 80], phase: 'maintain');
    final r = checkinReview(keep, rd([[0, 80.0], [7, 80.1], [14, 80.8], [21, 80.9]]), null);
    expect(r['direction'], 'maintain');
    expect(r['status'], 'heavy');
    expect(r['apply'], {'kcalDelta': -150, 'cardioMinDelta': 0});
  });

  test('식단을 70% 미만으로 지켰으면 숫자를 건드리지 않는다 (먼저 봄)', () {
    final r = checkinReview(cut, rd([[0, 86.2], [7, 86.2], [14, 86.2], [21, 86.2]]), {'dietPct': 40});
    expect(r['status'], 'adherence');
    expect(r['apply'], isNull);
  });

  test('조정한 뒤에는 그때 체크인부터 다시 — 같은 차이로 또 줄이지 않는다', () {
    final adjusted = {
      ...cut,
      'adjustments': [
        {'at': '2026-10-13T00:00:00.000Z', 'kcalDelta': -150},
      ],
    };
    final readings = [
      {'week': 0, 'day': 0, 'weightKg': 86.2, 'at': '2026-09-22T00:00:00.000Z'},
      {'week': 1, 'day': 7, 'weightKg': 86.2, 'at': '2026-09-29T00:00:00.000Z'},
      {'week': 2, 'day': 14, 'weightKg': 86.2, 'at': '2026-10-06T00:00:00.000Z'},
      {'week': 3, 'day': 21, 'weightKg': 86.2, 'at': '2026-10-13T00:00:00.000Z'},   // 조정하며 저장
      {'week': 4, 'day': 28, 'weightKg': 85.8, 'at': '2026-10-20T00:00:00.000Z'},   // 그 뒤 계획 속도
    ];
    final r = checkinReview(adjusted, readings, null);
    expect(r['baseWeek'], 3);
    expect(r['status'], 'onTrack', reason: '쌓인 1kg 로 또 줄이라고 하면 매주 내려갑니다');
    final only = checkinReview(adjusted, readings.take(4).toList(), null);
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
    final slow = checkinReview(cut, rd([[0, 86.2], [7, 86.2], [14, 86.2], [21, 86.2]]), null);
    const male = {'sex': 'male', 'mealsPerDay': 3};

    test('칼로리를 탄수로 맞춰 줄이고, 유산소를 더하고(글도), 기록을 남긴다 — 원래 계획은 그대로', () {
      final res = applyCheckinAdvice(cut, slow, male, 3, '2026-10-13T00:00:00.000Z')!;
      final p = (res['plan'] as Map).cast<String, Object?>();
      final m = p['macros'] as Map;
      expect(m['intakeKcal'], 2050);
      expect(m['carbG'], 183);                     // 220 − 37.5 → 반올림
      expect(m['deficitKcal'], 650);
      final w = p['workout'] as Map;
      expect(w['cardioMinPerWeek'], 100);
      expect(w['cardioPlan'], 'Z2 저강도 40분 × 2회 + 추가 유산소 주 40분 (체크인 조정)');
      expect(p['diet'], isNotNull);
      expect((p['adjustments'] as List).single['at'], '2026-10-13T00:00:00.000Z');
      expect(res['floored'], isFalse);
      expect((cut['macros'] as Map)['intakeKcal'], 2200, reason: '원래 계획을 고치면 안 됩니다');

      /* 두 번째 조정은 더한 분을 합쳐서 한 번만 적습니다. */
      final res2 = applyCheckinAdvice(p, slow, male, 7, '2026-11-10T00:00:00.000Z')!;
      expect(((res2['plan'] as Map)['workout'] as Map)['cardioPlan'],
          'Z2 저강도 40분 × 2회 + 추가 유산소 주 80분 (체크인 조정)');
    });

    test('하한(남성 1500 · BMR×1.1) 밑으로는 안 내린다', () {
      final low = {...cut, 'macros': {'intakeKcal': 1600, 'proteinG': 150, 'carbG': 120, 'fatG': 50}};
      final res = applyCheckinAdvice(low, slow, male, 3, 'x')!;
      /* ffm 66 → BMR 1795.6 → ×1.1 = 1975 > 1500. 이미 하한 밑이라 그대로. */
      expect(res['kcalDelta'], 0);
      expect(res['floored'], isTrue);
      expect(((res['plan'] as Map)['macros'] as Map)['intakeKcal'], 1600);
    });

    test('적용할 제안이 없으면 null', () {
      final ok = checkinReview(cut, rd([[0, 86.2], [7, 85.8]]), null);
      expect(applyCheckinAdvice(cut, ok, male, 1, 'x'), isNull);
      expect(applyCheckinAdvice(null, slow, male, 1, 'x'), isNull);
    });
  });

  test('계획 날 수 · 주차 — 시작일부터, 시작 전은 0', () {
    expect(planDayOf('2026-09-22', '2026-09-22'), 0);
    expect(planDayOf('2026-09-22', '2026-10-05'), 13);
    expect(planWeekOf('2026-09-22', '2026-09-28'), 0);
    expect(planWeekOf('2026-09-22', '2026-09-29'), 1);
    expect(planWeekOf('2026-09-22', '2026-09-01'), 0);
    expect(planWeekOf(null, '2026-09-29'), 0);
  });
}
