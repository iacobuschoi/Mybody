/* 주간 체크인 판정 — 흔들림에 반응하지 않는가, 방향을 맞게 잡는가.
 *
 * 예전 판정은 계획 다음 날 집 체중계 값(86.2)이 인바디(86.7)와 0.5kg
 * 다르다는 이유로 "빠릅니다 · 하루 150kcal 늘리기" 를 냈습니다. 여기 사례는
 * 그 일이 다시 안 나는지, 두 차례 검토에서 짚힌 것들(요일 차이 · 하루치 기준 ·
 * 이틀 연속을 두 주로 세기 · 단계 방향 · 유지 계획 · 지킬 수 없는 약속 문구)이
 * 고쳐졌는지, 그리고 제안이 나올 때 방향이 맞는지 봅니다.
 * JS 원본과 같은 답인지는 tools/difftest.js 가 봅니다. 흔들림이 섞인 경우의
 * 가짜 조정 비율은 engine.js 주석의 모의실험 숫자를 보세요. */
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
final cut = planOf([86.7, 86.3, 85.9, 85.5, 85.1, 84.7, 84.3, 83.9, 83.5], phase: 'cut');
/// 증량: 주마다 0.25kg.
final gain = planOf([70.0, 70.25, 70.5, 70.75, 71.0, 71.25, 71.5, 71.75, 72.0], phase: 'bulk');

/// [날, 체중] — 주차는 날에서 셉니다.
List<Map<String, Object?>> rd(List<List<num>> xs) =>
    [for (final x in xs) {'week': (x[0] / 7).floor(), 'day': x[0], 'weightKg': x[1]}];

/// 매주 같은 요일, i 번째 체중 = f(i).
List<Map<String, Object?>> weekly(int n, num Function(int) f) =>
    rd([for (var i = 0; i < n; i++) [i * 7, f(i)]]);

void main() {
  test('첫 체크인은 판정하지 않는다 — 0주차에 인바디와 0.5kg 달라도', () {
    final r = checkinReview(cut, rd([[1, 86.2]]), null);
    expect(r['status'], 'early');
    expect(r['apply'], isNull);
    expect((r['suggestions'] as List).first['title'], '기준 체중을 잡았습니다');
  });

  test('5일 안에 다시 잰 값은 앞의 값을 대신한다 — "첫 체크인" 이라고 하지 않는다', () {
    final r = checkinReview(cut, rd([[0, 86.2], [3, 86.0]]), null);
    expect(r['status'], 'early');
    expect(r['weeks'], 1);
    expect(r['merged'], 1);
    expect((r['suggestions'] as List).first['title'], '기준 체중을 다시 잡았습니다');
  });

  test('일요일 · 월요일 이틀 연속은 두 번이 아니다', () {
    /* 예전엔 20일째(2주차) · 21일째(3주차)를 "두 주 연속" 으로 세서 조정했습니다. */
    final r = checkinReview(cut, rd([[0, 86.7], [7, 86.3], [20, 86.7], [21, 86.6]]), null);
    expect(r['weeks'], 3);
    expect(r['status'], 'collecting');
  });

  test('4번 · 3주 전에는 모으기만 한다 — 다음에 조정한다고 약속하지 않는다', () {
    for (final n in [2, 3]) {
      final r = checkinReview(cut, weekly(n, (_) => 86.2), null);
      expect(r['status'], 'collecting', reason: '$n번');
      expect(r['apply'], isNull);
      expect('${(r['suggestions'] as List).first['detail']}', contains('4번부터'));
    }
  });

  test('계획선과 같은 속도면 계획대로 — 체중계가 인바디보다 0.5kg 낮고, 요일이 달라도', () {
    double line(num d) => 86.7 - 0.4 * d / 7;
    final r = checkinReview(cut, rd([
      for (final d in [0, 13, 20, 27, 34]) [d, line(d) - 0.5],
    ]), null);
    expect(r['status'], 'onTrack');
    expect((r['devKg'] as num).abs(), lessThan(0.05));
  });

  test('감량인데 정체 — 처음 벗어나면 지켜보고, 한 번 더 같으면 150kcal 줄이고 유산소 40분', () {
    expect(checkinReview(cut, weekly(4, (_) => 86.2), null)['status'], 'watch');
    final r = checkinReview(cut, weekly(5, (_) => 86.2), null);
    expect(r['status'], 'slow');
    expect(r['direction'], 'cut');
    expect(r['apply'], {'kcalDelta': -150, 'cardioMinDelta': 40});
    expect((r['devKg'] as num), greaterThan(1));
  });

  test('감량인데 너무 빠르면 — 150kcal 늘리기', () {
    expect(checkinReview(cut, weekly(4, (i) => 86.2 - 1.0 * i), null)['status'], 'watch');
    final r = checkinReview(cut, weekly(5, (i) => 86.2 - 1.0 * i), null);
    expect(r['status'], 'fast');
    expect(r['apply'], {'kcalDelta': 150, 'cardioMinDelta': 0});
  });

  test('벗어나 보여도 많이 흔들리면 확실하지 않다고 말한다 — 조정 없음', () {
    final r = checkinReview(cut, rd([[0, 86.2], [7, 87.4], [14, 85.3], [21, 86.9], [28, 85.9]]), null);
    expect(r['status'], 'watch');
    expect((r['suggestions'] as List).first['title'], '아직 확실하지 않습니다');
    expect(r['apply'], isNull);
  });

  test('증량인데 안 늘면 느린 것이고, 그때는 더 먹는다', () {
    final r = checkinReview(gain, weekly(8, (_) => 70.0), null);
    expect(r['direction'], 'gain');
    expect(r['status'], 'slow');
    expect(r['apply'], {'kcalDelta': 150, 'cardioMinDelta': 0});
  });

  test('증량인데 너무 빨리 늘면 줄인다', () {
    final r = checkinReview(gain, weekly(5, (i) => 70.0 + 0.9 * i), null);
    expect(r['status'], 'fast');
    expect(r['apply'], {'kcalDelta': -150, 'cardioMinDelta': 0});
  });

  test('감량 → 증량 계획의 감량 구간에서 정체하면 "느림 · 줄이기" (끝점으로 방향을 정하지 않는다)', () {
    final split = planOf([60.0, 59.6, 59.2, 58.8, 58.4, 58.0, 58.4, 59.0, 59.8, 60.6, 61.4],
        phases: ['cut', 'cut', 'cut', 'cut', 'cut', 'cut', 'bulk', 'bulk', 'bulk', 'bulk', 'bulk']);
    final r = checkinReview(split, weekly(5, (_) => 60.0), null);
    expect(r['direction'], 'cut');
    expect(r['status'], 'slow');
    expect(r['apply'], {'kcalDelta': -150, 'cardioMinDelta': 40});
  });

  test('단계는 그 자리를 포함하는 구간의 것 — 점 k 의 단계는 k−1 → k 구간', () {
    final split = planOf([60.0, 59.6, 59.2, 58.8, 58.4, 58.9, 59.4],
        phases: ['cut', 'cut', 'cut', 'cut', 'cut', 'bulk', 'bulk']);
    expect(checkinReview(split, rd([[0, 60], [31, 60]]), null)['direction'], 'gain');   // 4.4주 → 4→5 구간
    expect(checkinReview(split, rd([[0, 60], [24, 60]]), null)['direction'], 'cut');    // 3.4주 → 3→4 구간
  });

  test('유지 계획선이 조금씩 올라도, 체중을 지키는 사람에게 "더 드세요" 를 하지 않는다', () {
    final rising = planOf([for (var i = 0; i < 14; i++) 86.7 + 0.06 * i], phase: 'maintain');
    final r = checkinReview(rising, weekly(12, (_) => 86.7), null);
    expect(r['status'], 'onTrack');
  });

  test('유지인데 체중이 실제로 늘면 무겁다고 말한다 — 유산소는 안 더함', () {
    final keep = planOf([for (var i = 0; i < 10; i++) 80.0], phase: 'maintain');
    final r = checkinReview(keep, weekly(5, (i) => 80.0 + 0.5 * i), null);
    expect(r['status'], 'heavy');
    expect(r['apply'], {'kcalDelta': -150, 'cardioMinDelta': 0});
  });

  test('식단을 70% 미만으로 지켰으면 숫자를 건드리지 않는다 (먼저 봄)', () {
    final r = checkinReview(cut, weekly(5, (_) => 86.2), {'dietPct': 40});
    expect(r['status'], 'adherence');
    expect(r['apply'], isNull);
  });

  test('조정한 뒤에는 그때 체크인부터 다시', () {
    final adjusted = {
      ...cut,
      'adjustments': [
        {'at': '2026-10-20T00:00:00.000Z', 'kcalDelta': -150},
      ],
    };
    final readings = [
      for (var i = 0; i < 6; i++)
        {'week': i, 'day': i * 7, 'weightKg': 86.2,
         'at': DateTime.utc(2026, 9, 22).add(Duration(days: i * 7)).toIso8601String()},
    ];
    /* 조정은 4주차(10/20) 체크인과 같은 시각. 그 뒤는 4 · 5주차 두 번뿐. */
    final r = checkinReview(adjusted, readings, null);
    expect(r['weeks'], 2);
    expect(r['status'], 'collecting', reason: '쌓인 정체로 또 줄이라고 하면 매주 내려갑니다');
    final only = checkinReview(adjusted, readings.take(5).toList(), null);
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
    final slow = checkinReview(cut, weekly(5, (_) => 86.2), null);
    const male = {'sex': 'male', 'mealsPerDay': 3};

    test('칼로리를 탄수로 맞춰 줄이고, 유산소를 더하고(글도), 기록을 남긴다 — 원래 계획은 그대로', () {
      final res = applyCheckinAdvice(cut, slow, male, 4, '2026-10-20T00:00:00.000Z')!;
      final p = (res['plan'] as Map).cast<String, Object?>();
      final m = p['macros'] as Map;
      expect(m['intakeKcal'], 2050);
      expect(m['carbG'], 183);                     // 220 − 37.5 → 반올림
      expect(m['deficitKcal'], 650);
      final w = p['workout'] as Map;
      expect(w['cardioMinPerWeek'], 100);
      expect(w['cardioPlan'], 'Z2 저강도 40분 × 2회 + 추가 유산소 주 40분 (체크인 조정)');
      expect(p['diet'], isNotNull);
      expect((p['adjustments'] as List).single['at'], '2026-10-20T00:00:00.000Z');
      expect(res['floored'], isFalse);
      expect((cut['macros'] as Map)['intakeKcal'], 2200, reason: '원래 계획을 고치면 안 됩니다');

      /* 두 번째 조정은 더한 분을 합쳐서 한 번만 적습니다. */
      final res2 = applyCheckinAdvice(p, slow, male, 8, '2026-11-17T00:00:00.000Z')!;
      expect(((res2['plan'] as Map)['workout'] as Map)['cardioPlan'],
          'Z2 저강도 40분 × 2회 + 추가 유산소 주 80분 (체크인 조정)');
    });

    test('하한(남성 1500 · BMR×1.1) 밑으로는 안 내린다', () {
      final low = {...cut, 'macros': {'intakeKcal': 1600, 'proteinG': 150, 'carbG': 120, 'fatG': 50}};
      final res = applyCheckinAdvice(low, slow, male, 4, 'x')!;
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

  test('계획 날 수 · 주차 · 계획선 — 시작일부터', () {
    expect(planDayOf('2026-09-22', '2026-09-22'), 0);
    expect(planDayOf('2026-09-22', '2026-10-05'), 13);
    expect(planWeekOf('2026-09-22', '2026-09-28'), 0);
    expect(planWeekOf('2026-09-22', '2026-09-29'), 1);
    expect(planWeekOf('2026-09-22', '2026-09-01'), 0);
    expect(planWeekOf(null, '2026-09-29'), 0);
    expect(planWeightAt(cut, 7), 86.3);
    expect(planWeightAt(cut, 3.5), closeTo(86.5, 1e-9));
    expect(planWeightAt(null, 7), isNull);
  });
}
