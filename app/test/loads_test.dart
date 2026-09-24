/* =============================================================================
 * loads_test.dart — 시작 무게 추천(workout/loads.dart)이 규칙대로 계산되는가
 *
 * 숫자를 손으로 다시 계산해 둡니다 — 같은 식을 시험에 베끼면 식이 틀려도 통과합니다.
 *   남 86.7kg · 골격근 38kg → 골격근 계수 (38/86.7)/0.42 = 1.0435
 *   여 60kg · 골격근 22kg  → (22/60)/0.34 = 1.0784
 * ========================================================================== */
import 'package:flutter_test/flutter_test.dart';
import 'package:mybody/src/workout/exercises.dart';
import 'package:mybody/src/workout/loads.dart';

const _male = {'sex': 'male', 'trainingAge': 'novice'};
const _female = {'sex': 'female', 'trainingAge': 'novice'};

Load rec(String name, String reps,
        {Map<String, Object?> profile = _male, double? w = 86.7, double? smm = 38, Map<String, Object?>? last}) =>
    recommendLoad(name: name, reps: reps, profile: profile, weightKg: w, smmKg: smm, last: last);

void main() {
  group('체성분으로 계산', () {
    test('바벨 벤치프레스 5-8 · 남 86.7kg — 86.7×0.75×1.0435×0.78 = 52.9 → 52.5kg', () {
      final l = rec('바벨 벤치프레스', '5-8');
      expect(l.kg, 52.5);
      expect(l.step, 2.5);
      expect(l.source, 'body');
      expect(l.hint, '안 되면 2.5~5kg 씩 줄여 보세요');
    });

    test('여자는 비율이 다르다 — 바벨 스쿼트 5-8 · 여 60kg: 60×0.7×1.0784×0.78 = 35.3 → 35kg', () {
      expect(rec('바벨 스쿼트', '5-8', profile: _female, w: 60, smm: 22).kg, 35);
      expect(rec('바벨 스쿼트', '5-8').kg, 70, reason: '남 86.7kg: 86.7×1.0×1.0435×0.78 = 70.6 → 70');
    });

    test('경력 — intermediate 는 ×1.35, advanced 는 ×1.7', () {
      expect(rec('바벨 벤치프레스', '5-8', profile: {'sex': 'male', 'trainingAge': 'intermediate'}).kg, 72.5,
          reason: '52.9×1.35 = 71.5 → 72.5');
      expect(rec('바벨 벤치프레스', '5-8', profile: {'sex': 'male', 'trainingAge': 'advanced'}).kg, 90,
          reason: '52.9×1.7 = 90.0 → 90');
      expect(rec('바벨 벤치프레스', '5-8', profile: {'sex': 'male'}).kg, 52.5, reason: '모르면 novice');
    });

    test('반복 구간 — 5-8 78% · 8-12 70% · 10-15 62% · 15+ 55%', () {
      expect(pctOneRm('5-8'), 0.78);
      expect(pctOneRm('6-10'), 0.78);
      expect(pctOneRm('8-12'), 0.70);
      expect(pctOneRm('10-15'), 0.62);
      expect(pctOneRm('12-15'), 0.62);
      expect(pctOneRm('15+'), 0.55);
      expect(pctOneRm('20'), 0.55);
      expect(pctOneRm('30초'), 0.55, reason: '숫자 없는 반복(시간)은 가벼운 쪽');
      /* 같은 1RM(67.9) 에 구간만 다르게 */
      expect(rec('바벨 벤치프레스', '8-12').kg, 47.5);
      expect(rec('바벨 벤치프레스', '10-15').kg, 42.5);
      expect(rec('바벨 벤치프레스', '15+').kg, 37.5);
    });

    test('덤벨은 한 손 무게(절반), 10kg 위는 2kg 단위 — 덤벨 숄더프레스 10-15 → 14kg', () {
      final l = rec('덤벨 숄더프레스', '10-15');
      expect(l.kg, 14, reason: '86.7×0.5×1.0435×0.62 = 28.0 → 한 손 14.0 → 14');
      expect(l.step, 2);
      expect(l.hint, '안 되면 1~2kg 씩 줄여 보세요');
      final small = rec('사이드 레터럴레이즈', '10-15');
      expect(small.kg, 4, reason: '86.7×0.15×1.0435×0.62 = 8.4 → 한 손 4.2 → 4');
      expect(small.step, 1);
    });

    test('머신은 5kg 단위 · 레그프레스는 스쿼트의 1.8배 — 레그프레스 10-15 → 100kg', () {
      final l = rec('레그프레스', '10-15');
      expect(l.kg, 100, reason: '86.7×1.8×1.0435×0.62 = 101.0 → 100');
      expect(l.step, 5);
      expect(l.hint, '안 되면 5kg 씩 줄여 보세요');
      expect(rec('핵 스쿼트', '10-15').kg, 55, reason: '머신이라도 레그프레스가 아니면 스쿼트 비율: 56.1 → 55');
    });

    test('레그프레스 비율은 스쿼트 움직임일 때만 — 레그프레스 카프 레이즈는 고립 비율', () {
      expect(rec('레그프레스 카프 레이즈', '10-15').kg, 20, reason: '86.7×0.4×1.0435×0.62 = 22.4 → 20');
      expect(rec('시티드 레그프레스', '10-15').kg, 100, reason: '앉는 레그프레스도 썰매가 받칩니다');
    });

    test('어시스트 풀업 · 딥은 무게 없음 — 스택은 보조 무게라 규칙이 거꾸로 갑니다', () {
      for (final name in ['어시스트 풀업', '어시스트 딥']) {
        final l = rec(name, '10-15');
        expect(l.source, 'none', reason: name);
        expect(l.kg, isNull);
        /* 지난 기록에 kg 이 있어도 "+5kg 진행" 을 권하지 않습니다. */
        expect(rec(name, '10-15', last: {'kg': 30, 'sets': 3, 'of': 3}).source, 'none');
      }
    });

    test('케이블은 2.5kg 단위', () {
      final l = rec('케이블 푸시다운', '10-15');
      expect(l.step, 2.5);
      expect(l.kg, 15, reason: '86.7×0.25×1.0435×0.62 = 14.0 → 15');
    });

    test('바벨은 빈 봉 20kg 아래로 안 내려간다 — 여 50kg 바벨 컬', () {
      final l = rec('바벨 컬', '10-15', profile: _female, w: 50, smm: 18);
      expect(l.kg, 20, reason: '50×0.15×1.0588×0.62 = 4.9 → 5 → 빈 봉 20');
    });

    test('골격근 계수는 0.8~1.2 로 클램프, 골격근을 모르면 1', () {
      expect(rec('바벨 벤치프레스', '5-8', smm: 60).kg, 60, reason: '65.0×1.2×0.78 = 60.9 → 60');
      expect(rec('바벨 벤치프레스', '5-8', smm: 20).kg, 40, reason: '65.0×0.8×0.78 = 40.6 → 40');
      expect(rec('바벨 벤치프레스', '5-8', smm: null).kg, 50, reason: '65.0×0.78 = 50.7 → 50');
    });

    test('맨몸 · 밴드 · 모르는 종목 · 체중 없음은 무게 없음', () {
      for (final l in [
        rec('푸시업', '10-15'),
        rec('밴드 로우', '10-15'),
        rec('플랭크', '30초'),
        rec('이런 종목 없음', '10-15'),
        rec('바벨 벤치프레스', '5-8', w: null),
      ]) {
        expect(l.kg, isNull);
        expect(l.source, 'none');
        expect(l.step, 0);
        expect(l.hint, '');
      }
    });

    test('exercise 를 직접 주면 이름 대신 그것', () {
      final e = exerciseById('leg-press')!;
      expect(recommendLoad(name: '아무 이름', exercise: e, reps: '10-15', profile: _male, weightKg: 86.7, smmKg: 38).kg, 100);
    });
  });

  group('지난 기록', () {
    test('지난 kg 이 있으면 그것 — 세트를 다 채웠으면 한 단위 위', () {
      final l = rec('바벨 벤치프레스', '5-8', last: {'kg': 40, 'sets': 3, 'of': 3});
      expect(l.kg, 42.5);
      expect(l.prevKg, 40);
      expect(l.source, 'last');
      expect(l.step, 2.5);
      expect(l.hint, '지난번 40kg · 다 채워서 +2.5kg');
      expect(rec('바벨 벤치프레스', '5-8').prevKg, isNull, reason: '체성분 계산에는 지난 값이 없습니다');
    });

    test('못 채웠으면 그대로', () {
      final l = rec('바벨 벤치프레스', '5-8', last: {'kg': 40, 'sets': 2, 'of': 3});
      expect(l.kg, 40);
      expect(l.source, 'last');
      expect(l.hint, '지난번 그대로');
    });

    test('단위는 기구를 따른다 — 덤벨 10kg 은 +2, 8kg 은 +1, 머신 60 은 +5', () {
      expect(rec('덤벨 숄더프레스', '10-15', last: {'kg': 10, 'sets': 3, 'of': 3}).kg, 12);
      expect(rec('덤벨 숄더프레스', '10-15', last: {'kg': 8, 'sets': 3, 'of': 3}).kg, 9);
      expect(rec('레그프레스', '10-15', last: {'kg': 60, 'sets': 3, 'of': 3}).kg, 65);
    });

    test('지난 기록에 kg 이 없으면(맨몸으로 했거나 옛 기록) 체성분으로', () {
      final l = rec('바벨 벤치프레스', '5-8', last: {'kg': null, 'sets': 3, 'of': 3});
      expect(l.source, 'body');
      expect(l.kg, 52.5);
      expect(rec('푸시업', '10-15', last: {'kg': 10, 'sets': 3, 'of': 3}).source, 'none',
          reason: '맨몸 종목은 지난 kg 이 있어도 무게 없음');
    });
  });

  group('lastLoadsFrom — 최근 30일 헬스 기록에서 종목별 마지막 무게', () {
    final schedule = <String, Object?>{
      '2026-09-27': {'log': {'gym': {'kind': 'gym', 'exercises': [{'name': '바벨 스쿼트', 'kg': 99, 'sets': 3, 'of': 3}]}}},   // 오늘 — 안 봄
      '2026-09-20': {'log': {'gym': {'kind': 'gym', 'exercises': [
        {'name': '바벨 스쿼트', 'kg': 60, 'sets': 3, 'of': 3, 'reps': '5-8'},
        {'name': '푸시업', 'kg': null, 'sets': 3, 'of': 3},
      ]}}},
      '2026-09-15': {'log': {'gym': {'kind': 'gym', 'exercises': [
        {'name': '바벨 스쿼트', 'kg': 55, 'sets': 2, 'of': 3},
        {'name': '레그프레스', 'kg': 100, 'sets': 3, 'of': 3},
      ]}}},
      '2026-09-10': {'log': {'gym': {'kind': 'bodyweight', 'exercises': ['맨몸 스쿼트']}}},   // 맨몸 운동은 무게가 없음
      '2026-08-10': {'log': {'gym': {'kind': 'gym', 'exercises': [{'name': '데드리프트', 'kg': 80, 'sets': 3, 'of': 3}]}}},   // 30일 밖
      '2026-09-18': {'plan': ['gym'], 'done': {}},
    };

    test('종목마다 가장 최근 것, 오늘 것과 30일 밖은 빼고', () {
      final m = lastLoadsFrom(schedule, '2026-09-27');
      expect(m.keys, containsAll(['바벨 스쿼트', '푸시업', '레그프레스']));
      expect(m.containsKey('데드리프트'), isFalse);
      expect(m['바벨 스쿼트'], {'kg': 60, 'sets': 3, 'of': 3, 'reps': '5-8', 'date': '2026-09-20'});
      expect(m['레그프레스']!['kg'], 100);
      expect(m['레그프레스']!['date'], '2026-09-15');
      expect(m['푸시업']!['kg'], isNull);
      /* 최근 것이 앞 — 종목 고르기의 「최근」 줄이 이 순서를 씁니다. */
      expect(m.keys.first, '바벨 스쿼트');
      expect(m.keys.last, '레그프레스');
    });

    test('days 를 줄이면 그만큼만, 이상한 날짜면 빈 것', () {
      expect(lastLoadsFrom(schedule, '2026-09-27', days: 7).keys.toList(), ['바벨 스쿼트', '푸시업'],
          reason: '7일 전(9/20)까지만 — 9/15 는 안 봅니다');
      expect(lastLoadsFrom(schedule, '2026-09-27', days: 5), isEmpty);
      expect(lastLoadsFrom(schedule, 'nope'), isEmpty);
      expect(lastLoadsFrom(const {}, '2026-09-27'), isEmpty);
    });

    test('달을 넘어서도 하루씩 — 9/1 에서 보면 8/31 · 8/2(30일 전) 가 나온다 (달력 산수)', () {
      final sched = <String, Object?>{
        '2026-08-31': {'log': {'gym': {'kind': 'gym', 'exercises': [{'name': '바벨 스쿼트', 'kg': 60, 'sets': 3, 'of': 3}]}}},
        '2026-08-02': {'log': {'gym': {'kind': 'gym', 'exercises': [{'name': '레그프레스', 'kg': 100, 'sets': 3, 'of': 3}]}}},
        '2026-08-01': {'log': {'gym': {'kind': 'gym', 'exercises': [{'name': '데드리프트', 'kg': 80, 'sets': 3, 'of': 3}]}}},
      };
      final m = lastLoadsFrom(sched, '2026-09-01');
      expect(m['바벨 스쿼트']!['date'], '2026-08-31');
      expect(m['레그프레스']!['date'], '2026-08-02', reason: '30일 전이 마지막 날');
      expect(m.containsKey('데드리프트'), isFalse, reason: '31일 전은 안 봅니다');
      expect(lastLoadsFrom(sched, '2026-03-01', days: 1).keys, isEmpty);
      /* 윤년 2월 끝 — 3/1 의 전날은 2/29. */
      final leap = <String, Object?>{
        '2028-02-29': {'log': {'gym': {'kind': 'gym', 'exercises': [{'name': '바벨 스쿼트', 'kg': 60, 'sets': 3, 'of': 3}]}}},
      };
      expect(lastLoadsFrom(leap, '2028-03-01', days: 1)['바벨 스쿼트']!['date'], '2028-02-29');
    });

    test('recommendLoad 와 이어진다 — 스쿼트는 지난 60kg 다 채워서 62.5', () {
      final m = lastLoadsFrom(schedule, '2026-09-27');
      expect(rec('바벨 스쿼트', '5-8', last: m['바벨 스쿼트']).kg, 62.5);
    });
  });

  group('조각', () {
    test('kgText — 소수점은 필요할 때만', () {
      expect(kgText(40), '40');
      expect(kgText(37.5), '37.5');
      expect(kgText(2.5), '2.5');
      expect(kgText(100), '100');
    });

    test('roundLoad — 기구 단위 · 바닥', () {
      expect(roundLoad('barbell', 52.93), 52.5);
      expect(roundLoad('barbell', 10), 20);
      expect(roundLoad('machine', 3), 5);
      expect(roundLoad('machine', 101), 100);
      expect(roundLoad('cable', 1), 2.5);
      expect(roundLoad('dumbbell', 7.6), 8);
      expect(roundLoad('dumbbell', 13), 14);
      expect(roundLoad('kettlebell', 10), 12);
      expect(roundLoad('bodyweight', 7.7), 7.7, reason: '단위가 없으면 그대로');
    });

    test('stepFor', () {
      expect(stepFor('barbell', 40), 2.5);
      expect(stepFor('cable', 40), 2.5);
      expect(stepFor('machine', 40), 5);
      expect(stepFor('dumbbell', 8), 1);
      expect(stepFor('dumbbell', 10), 2);
      expect(stepFor('kettlebell', 12), 4);
      expect(stepFor('bodyweight', 0), 0);
      expect(stepFor('band', 0), 0);
    });
  });
}
