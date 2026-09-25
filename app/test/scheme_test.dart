/* =============================================================================
 * scheme_test.dart — 종목별 세트 · 횟수 · 쉬는 시간 규칙
 *
 * 3차 피드백 31: 맨몸 스쿼트에 바벨 복합의 5-8 이, 플랭크에 「10-15회」 가 붙어 있었습니다.
 * 여기서 보는 것:
 *   · 맨몸 스쿼트 15-20(초보) · 플랭크 30초 · 바벨 스쿼트 초보 8-12 · 머신 8-12 · 컬 12-15
 *   · 편측(런지 · 원암)은 perSide · 엔진이 4세트를 줬으면 유지
 *   · 사전의 모든 종목이 어느 부류든 받고, 맨몸에는 바벨 규칙이 절대 안 붙는다
 *   · 분류표의 id 가 사전에 실제로 있다(오타 방지)
 * ========================================================================== */
import 'package:flutter_test/flutter_test.dart';
import 'package:mybody/src/workout/exercises.dart';
import 'package:mybody/src/workout/scheme.dart';

/// 사전 이름으로 스킴을 — 화면이 planner 를 거쳐 받는 것과 같은 입력.
Scheme of(String name,
    {String age = 'novice', String goal = '', int? engineSets, String? engineReps, int? engineRest}) {
  final e = exerciseByName(name);
  return schemeFor(
    exercise: e,
    name: e?.name ?? name,
    equip: e?.equip ?? 'bodyweight',
    pattern: e?.pattern ?? '',
    goalKind: goal,
    trainingAge: age,
    isCompound: engineReps == '5-8',
    engineSets: engineSets,
    engineReps: engineReps,
    engineRestSec: engineRest,
  );
}

void main() {
  group('맨몸', () {
    test('맨몸 스쿼트 — 초보 15-20 · 중급 20-25 · 고급 25-30, 휴식 60, 초 단위 아님', () {
      final n = of('맨몸 스쿼트');
      expect(n.reps, '15-20');
      expect(n.seconds, isNull);
      expect(n.restSec, 60);
      expect(n.sets, 3);
      expect(n.perSide, isFalse);
      expect(n.amount, '15-20');
      expect(of('맨몸 스쿼트', age: 'intermediate').reps, '20-25');
      expect(of('맨몸 스쿼트', age: 'advanced').reps, '25-30');
      expect(of('맨몸 스쿼트', age: 'advanced').sets, 4);
    });

    test('플랭크 — 초 단위: 초보 30 · 중급 45 · 고급 60, reps 는 빈 글, 3세트, 휴식 45', () {
      final n = of('플랭크');
      expect(n.seconds, 30);
      expect(n.reps, '');
      expect(n.sets, 3);
      expect(n.restSec, 45);
      expect(n.amount, '30초');
      expect(of('플랭크', age: 'intermediate').seconds, 45);
      expect(of('플랭크', age: 'advanced').seconds, 60);
      expect(of('플랭크', age: 'advanced').sets, 3, reason: '버티기는 고급도 3세트');
      /* 사이드 플랭크는 한쪽씩 · 짧게. 월 싯 · 할로우 홀드도 초. */
      final side = of('사이드 플랭크');
      expect(side.seconds, 20);
      expect(side.perSide, isTrue);
      expect(side.amount, '20초 한쪽씩');
      expect(of('월 싯').seconds, 30);
      expect(of('할로우 홀드').seconds, 20);
    });

    test('글루트 브릿지 15-20 · 푸시업 8-12 → 12-20 → 20-30 · 카프 15-20', () {
      expect(of('글루트 브릿지').reps, '15-20');
      expect(of('푸시업').reps, '8-12');
      expect(of('푸시업', age: 'intermediate').reps, '12-20');
      expect(of('푸시업', age: 'advanced').reps, '20-30');
      expect(of('카프 레이즈').reps, '15-20');
      expect(of('인클라인 푸시업').reps, '12-15');
    });

    test('고난도 맨몸 — 풀업 3-6 · 딥스 3-6 · 행잉 레그레이즈 5-8, 휴식 90 · 중급은 4세트', () {
      expect(of('풀업').reps, '3-6');
      expect(of('풀업', age: 'intermediate').reps, '6-10');
      expect(of('딥스').reps, '3-6');
      expect(of('딥스', age: 'intermediate').reps, '6-10');
      final hlr = of('행잉 레그레이즈');
      expect(hlr.reps, '5-8');
      expect(hlr.restSec, 90);
      expect(of('행잉 레그레이즈', age: 'intermediate').sets, 4);
    });

    test('코어 반복은 짧게 쉬고 · 유산소성은 초 단위로 한 만큼 쉬고 · 점프는 적게 길게 쉬고', () {
      final crunch = of('크런치');
      expect(crunch.reps, '12-15');
      expect(crunch.restSec, 45);
      final burpee = of('버피');
      expect(burpee.seconds, 30);
      expect(burpee.restSec, 30);
      expect(burpee.reps, '');
      expect(of('마운틴 클라이머', age: 'advanced').seconds, 45);
      final jump = of('점프 스쿼트', engineReps: '5-8', engineRest: 150);
      expect(jump.reps, '5-6', reason: '이름에 스쿼트가 있어도 바벨이 아닙니다');
      expect(jump.restSec, 90);
      expect(of('박스 점프').reps, '5-6');
      expect(of('파머스 워크').seconds, 30);
    });
  });

  group('바벨 복합', () {
    test('바벨 스쿼트 — 초보 8-12 · 휴식 120, 목표와 상관없이', () {
      for (final goal in ['', 'cut', 'bulk', 'recomp']) {
        final s = of('바벨 스쿼트', goal: goal, engineReps: '5-8', engineRest: 150);
        expect(s.reps, '8-12', reason: goal);
        expect(s.restSec, 120, reason: goal);
        expect(s.sets, 3, reason: goal);
        expect(s.why, contains('자세'));
      }
      expect(of('바벨 벤치프레스').reps, '8-12');
      expect(of('데드리프트').reps, '8-12');
      expect(of('오버헤드 프레스').reps, '8-12');
      expect(of('바벨 로우').reps, '8-12');
    });

    test('중급은 6-10 · 증량(근력)이면 5-8 · 고급 증량은 4-6, 휴식 150-180, 4세트', () {
      final mid = of('바벨 스쿼트', age: 'intermediate');
      expect(mid.reps, '6-10');
      expect(mid.restSec, 150);
      expect(mid.sets, 4);
      final bulk = of('바벨 스쿼트', age: 'intermediate', goal: 'bulk', engineReps: '5-8');
      expect(bulk.reps, '5-8');
      expect(bulk.restSec, 180);
      expect(of('바벨 스쿼트', age: 'advanced', goal: 'bulk').reps, '4-6');
      expect(of('바벨 스쿼트', age: 'advanced', goal: 'cut').reps, '6-10');
      expect(of('바벨 스쿼트', age: 'advanced').sets, 4);
    });

    test('랜드마인 프레스는 바벨이라도 머신 · 덤벨 규칙', () {
      expect(of('랜드마인 프레스', age: 'intermediate').reps, '8-12');
    });
  });

  group('머신 · 덤벨 · 고립', () {
    test('머신 · 덤벨 · 케이블 복합은 8-12 · 휴식 90', () {
      for (final name in ['레그프레스', '체스트 프레스 머신', '덤벨 숄더프레스', '시티드 케이블로우', '고블릿 스쿼트', '핵 스쿼트']) {
        final s = of(name, engineReps: '5-8', engineRest: 150);
        expect(s.reps, '8-12', reason: name);
        expect(s.restSec, 90, reason: name);
        expect(s.seconds, isNull, reason: name);
      }
      expect(of('레그프레스', age: 'intermediate').sets, 4, reason: '중급 복합은 4세트');
      expect(of('레그프레스', age: 'advanced').reps, '8-12');
    });

    test('컬 · 익스텐션 · 레이즈 · 플라이 · 카프 · 어브덕션은 12-15 · 휴식 60, 중급부터 10-15', () {
      for (final name in ['바벨 컬', '덤벨 컬', '케이블 푸시다운', '레그 익스텐션', '사이드 레터럴레이즈', '케이블 플라이',
          '시티드 카프 레이즈', '힙 어브덕션', '레그 컬', '페이스풀', '덤벨 슈러그']) {
        final s = of(name);
        expect(s.reps, '12-15', reason: name);
        expect(s.restSec, 60, reason: name);
        expect(s.sets, 3, reason: name);
      }
      expect(of('바벨 컬', age: 'intermediate').reps, '10-15');
      expect(of('바벨 컬', age: 'intermediate').sets, 3, reason: '고립은 중급도 3세트');
      expect(of('바벨 컬', age: 'advanced').sets, 4);
    });
  });

  group('편측 · 세트 · 표시', () {
    test('런지 · 스플릿 · 원암 · 싱글레그는 perSide — 「8-12 한쪽씩」', () {
      final lunge = of('런지');
      expect(lunge.perSide, isTrue);
      expect(lunge.reps, '8-12');
      expect(lunge.amount, '8-12 한쪽씩');
      expect(lunge.why, contains('양쪽'));
      expect(of('불가리안 스플릿스쿼트').perSide, isTrue);
      expect(of('불가리안 스플릿스쿼트').reps, '8-12', reason: '덤벨 복합');
      expect(of('원암 덤벨로우').perSide, isTrue);
      expect(of('싱글레그 글루트브릿지').perSide, isTrue);
      expect(of('버드독').perSide, isTrue);
      expect(of('맨몸 스쿼트').perSide, isFalse);
      expect(of('플랭크').perSide, isFalse);
    });

    test('엔진이 4세트를 줬으면 유지 · 5 넘게는 안 · 적게 줬으면 표대로', () {
      expect(of('바벨 스쿼트', engineSets: 4, engineReps: '5-8').sets, 4);
      expect(of('맨몸 스쿼트', engineSets: 4, engineReps: '5-8').sets, 4, reason: '볼륨은 기구와 무관');
      expect(of('바벨 스쿼트', engineSets: 6).sets, 5);
      expect(of('바벨 스쿼트', engineSets: 2).sets, 3);
      expect(of('바벨 컬', engineSets: 3).sets, 3);
    });

    test('amountLabel · workSecondsOf — 계획 줄(Map)에서', () {
      expect(amountLabel({'reps': '15-20'}), '15-20');
      expect(amountLabel({'reps': '', 'seconds': 30}), '30초');
      expect(amountLabel({'reps': '10-15', 'seconds': 30}), '30초', reason: 'seconds 가 이깁니다');
      expect(amountLabel({'reps': '8-12', 'perSide': true}), '8-12 한쪽씩');
      expect(amountLabel({}), '');
      expect(workSecondsOf({'reps': '15-20'}), 60);
      expect(workSecondsOf({'reps': '', 'seconds': 30}), 30);
      expect(workSecondsOf({'reps': '8-12', 'perSide': true}), 72);
      expect(workSecondsOf({}), 36, reason: '모르면 12회');
    });

    test('Scheme.copyWith 는 세트 · 휴식만 바꾼다', () {
      final s = of('플랭크').copyWith(sets: 4, restSec: 30);
      expect(s.sets, 4);
      expect(s.restSec, 30);
      expect(s.seconds, 30);
      expect(s.reps, '');
    });
  });

  group('사전에 없는 종목', () {
    test('낱말로 — 홀드는 초 · 런지는 한쪽씩 · 컬은 고립 · 엔진이 복합이라 하면 기구로', () {
      final hold = schemeFor(exercise: null, name: '벽 홀드', equip: 'bodyweight', pattern: '',
          goalKind: '', trainingAge: 'novice', isCompound: false);
      expect(hold.seconds, 30);
      final lunge = schemeFor(exercise: null, name: '커튼시 런지', equip: 'bodyweight', pattern: '',
          goalKind: '', trainingAge: 'novice', isCompound: false);
      expect(lunge.perSide, isTrue);
      expect(lunge.reps, '12-15', reason: '맨몸 기본값');
      final curl = schemeFor(exercise: null, name: '외계 컬', equip: 'machine', pattern: '',
          goalKind: '', trainingAge: 'novice', isCompound: false);
      expect(curl.reps, '12-15');
      final press = schemeFor(exercise: null, name: '외계 프레스', equip: 'barbell', pattern: '',
          goalKind: '', trainingAge: 'intermediate', isCompound: true);
      expect(press.reps, '6-10');
      expect(press.restSec, 150);
    });

    test('아무 단서가 없으면 엔진(루틴)이 준 숫자를 그대로 · 그것도 없으면 8-12 · 90', () {
      final kept = schemeFor(exercise: null, name: '외계 운동', equip: 'machine', pattern: '',
          goalKind: '', trainingAge: 'advanced', isCompound: false,
          engineSets: 2, engineReps: '10-15', engineRestSec: 75);
      expect(kept.sets, 2);
      expect(kept.reps, '10-15');
      expect(kept.restSec, 75);
      final blank = schemeFor(exercise: null, name: '외계 운동', equip: 'machine', pattern: '',
          goalKind: '', trainingAge: 'novice', isCompound: false);
      expect(blank.sets, 3);
      expect(blank.reps, '8-12');
      expect(blank.restSec, 90);
    });
  });

  group('why', () {
    test('why 에 휴식 초 · 분을 적지 않는다 — 예산 규칙이 restSec 만 깎아 글과 숫자가 어긋나니까', () {
      for (final ta in ['novice', 'intermediate', 'advanced']) {
        for (final goal in ['', 'cut', 'bulk']) {
          for (final e in kExerciseLibrary) {
            final s = schemeFor(exercise: e, name: e.name, equip: e.equip, pattern: e.pattern,
                goalKind: goal, trainingAge: ta, isCompound: false);
            expect(s.why, isNot(matches(RegExp(r'\d+\s*(초|분)\s*쉬'))), reason: '${e.name} $ta $goal: ${s.why}');
          }
        }
      }
    });
  });

  group('사전 전체', () {
    test('모든 종목이 부류를 받고 · 세트 3-5 · 반복 아니면 초 · 맨몸에는 바벨 · 머신 규칙이 안 붙는다', () {
      for (final e in kExerciseLibrary) {
        for (final age in ['novice', 'intermediate', 'advanced']) {
          final kind = schemeKindOf(
              exercise: e, name: e.name, equip: e.equip, pattern: e.pattern, isCompound: false);
          expect(kind, isNotNull, reason: e.name);
          final s = schemeFor(exercise: e, name: e.name, equip: e.equip, pattern: e.pattern,
              goalKind: '', trainingAge: age, isCompound: false);
          expect(s.sets, inInclusiveRange(3, 5), reason: '${e.name} $age');
          expect(s.reps.isEmpty != (s.seconds == null), isTrue, reason: '${e.name} — 반복 아니면 초');
          expect(s.restSec, inInclusiveRange(30, 180), reason: e.name);
          expect(s.why, isNotEmpty, reason: e.name);
          expect(s.why, isNot(contains('\n')), reason: e.name);
          if (e.equip == 'bodyweight') {
            expect(kind, isNot(SchemeKind.barbell), reason: e.name);
            expect(kind, isNot(SchemeKind.machine), reason: e.name);
            expect(kind, isNot(SchemeKind.isolation), reason: e.name);
            expect(s.restSec, isNot(inInclusiveRange(120, 180)), reason: '${e.name} 에 바벨 휴식');
          }
          if (e.pattern == 'hold') expect(s.seconds, isNotNull, reason: e.name);
        }
      }
    });

    test('분류표의 id 는 전부 사전에 있다 — 오타는 조용히 규칙을 빠뜨립니다', () {
      final all = {for (final e in kExerciseLibrary) e.id};
      for (final table in [
        kIsometricIds, kCardioIds, kPlyoIds, kHardBodyweightIds, kPerSideIds,
        kBodyweightReps.keys.toSet(), kHoldSec.keys.toSet(),
      ]) {
        for (final id in table) {
          expect(all, contains(id));
        }
      }
      for (final table in [kBodyweightReps.values, kHoldSec.values]) {
        for (final row in table) {
          expect(row.length, 3, reason: '초보 · 중급 · 고급');
        }
      }
    });

    test('같은 입력이면 같은 답', () {
      expect(of('바벨 스쿼트', age: 'intermediate', goal: 'bulk').toString(),
          of('바벨 스쿼트', age: 'intermediate', goal: 'bulk').toString());
      expect(of('플랭크').toString(), 'Scheme(3 × 30초 · rest 45)');
    });
  });
}
