/* =============================================================================
 * workout_logic_test.dart — 운동 계획 손질 · 칼로리 · 맨몸 루틴의 순수 논리
 *
 * 화면 없이 돕니다. 여기서 보는 것:
 *   · 사전이 엔진 종목을 하나도 안 빠뜨리는가 (빠지면 대체가 조용히 안 됩니다)
 *   · 기구가 없을 때 같은 부위·같은 움직임으로 바꾸는가, 머신 개수를 지키는가,
 *     잘 아는 종목을 하나만 넣는가, 같은 종목이 두 번 안 나오는가
 *   · 칼로리 공식이 손으로 계산한 값과 같은가 (80kg · 30분 · MET 5 = 210)
 *   · 맨몸 루틴이 경력·체중·오늘 분할에 따라 모양을 바꾸는가
 * ========================================================================== */
import 'package:flutter_test/flutter_test.dart';
import 'package:mybody/src/workout/bodyweight.dart';
import 'package:mybody/src/workout/exercises.dart';
import 'package:mybody/src/workout/kcal.dart';
import 'package:mybody/src/workout/planner.dart';
import 'package:mybody/src/workout/prefs.dart';
import 'package:mybody_core/mybody_core.dart' show kExercises, compareLevels, buildPlan;

/// 엔진이 만든 것과 같은 모양의 세션 — 종목 이름은 data.dart 그대로.
Map<String, Object?> session(String label, List<List<String>> rows) => {
      'day': 0,
      'label': label,
      'rest': false,
      'minutes': 60,
      'exercises': [
        for (final r in rows)
          {
            'name': r[0], 'equip': r[1], 'note': '', 'group': r[2],
            'sets': 3, 'reps': '10-15', 'restSec': 75, 'rpe': '7-8',
          },
      ],
    };

final upperA = session('상체 A', [
  ['바벨 벤치프레스', 'barbell', 'chest'],
  ['인클라인 덤벨프레스', 'dumbbell', 'chest'],
  ['풀업 / 랫풀다운', 'machine', 'back'],
  ['바벨 로우', 'barbell', 'back'],
  ['오버헤드 프레스', 'barbell', 'shoulder'],
  ['바벨 컬', 'barbell', 'arms'],
  ['인클라인 덤벨컬', 'dumbbell', 'arms'],
]);

final lowerA = session('하체 A', [
  ['바벨 스쿼트', 'barbell', 'quads'],
  ['레그프레스', 'machine', 'quads'],
  ['루마니안 데드리프트', 'barbell', 'hamsGlutes'],
  ['힙 쓰러스트', 'barbell', 'hamsGlutes'],
  ['행잉 레그레이즈', 'bodyweight', 'core'],
]);

final pullA = session('풀 A', [
  ['풀업 / 랫풀다운', 'machine', 'back'],
  ['바벨 로우', 'barbell', 'back'],
  ['시티드 케이블로우', 'machine', 'back'],
  ['바벨 컬', 'barbell', 'arms'],
]);

List<String> names(List<Map<String, Object?>> xs) => [for (final x in xs) '${x['name']}'];
List<String> ids(List<Map<String, Object?>> xs) => [for (final x in xs) '${x['id']}'];

void main() {
  group('종목 사전', () {
    test('엔진 종목은 전부, 글자 그대로 있다', () {
      for (final entry in kExercises.entries) {
        for (final x in (entry.value as List)) {
          final name = '${(x as Map)['name']}';
          final e = exerciseByName(name);
          expect(e, isNotNull, reason: name);
          expect(e!.name, name);
          expect(e.group, entry.key, reason: name);
        }
      }
    });

    test('45개 이상 · 번호와 이름이 겹치지 않고 · 기구와 부위가 아는 값이다', () {
      expect(kExerciseLibrary.length, greaterThanOrEqualTo(45));
      expect(kExerciseLibrary.map((e) => e.id).toSet().length, kExerciseLibrary.length);
      expect(kExerciseLibrary.map((e) => e.name).toSet().length, kExerciseLibrary.length);
      for (final e in kExerciseLibrary) {
        expect(kEquipLabel.containsKey(e.equip), isTrue, reason: e.name);
        expect(kGroupLabel.containsKey(e.group), isTrue, reason: e.name);
        expect(e.met, inInclusiveRange(2.8, 11.0), reason: e.name);
      }
    });

    test('부위마다 집에서 되는 맨몸 대체가 있다', () {
      for (final g in ['chest', 'back', 'shoulder', 'arms', 'quads', 'hamsGlutes', 'core']) {
        final home = exercisesFor(g, equip: {'bodyweight'}).where((e) => !e.needsBar);
        expect(home, isNotEmpty, reason: g);
      }
    });

    test('느슨하게 찾기 — 띄어쓰기 · "/" 로 묶인 이름', () {
      expect(exerciseByName('바벨벤치프레스')?.id, 'bench-press');
      expect(exerciseByName('랫풀다운')?.id, 'pullup-latpulldown');
      expect(exerciseByName('풀업')?.id, 'pull-up', reason: '따로 있는 이름은 그것부터');
      expect(exerciseByName(' 플랭크 ')?.id, 'plank');
      expect(exerciseByName('없는 종목'), isNull);
      expect(exerciseByName(''), isNull);
    });

    test('exercisesFor 는 기구로 거른다', () {
      final all = exercisesFor('chest');
      final db = exercisesFor('chest', equip: {'dumbbell'});
      expect(db, isNotEmpty);
      expect(db.length, lessThan(all.length));
      expect(db.every((e) => e.equip == 'dumbbell'), isTrue);
    });
  });

  group('GymPrefs', () {
    test('없거나 깨진 설정은 헬스장 기본값', () {
      expect(GymPrefs.fromSettings(null).equipment, kGymEquipment);
      expect(GymPrefs.fromSettings({'gym': 'garbage'}).place, 'gym');
      expect(GymPrefs.fromSettings({'gym': {'place': 'moon', 'machineCount': -3}}).machineCount, isNull);
    });

    test('집은 맨몸·덤벨·밴드가 기본 · 모르는 기구는 버리고 맨몸은 언제나', () {
      final p = GymPrefs.fromSettings({
        'gym': {'place': 'home', 'equipment': ['band', 'laser', 3], 'familiar': ['push-up', 'push-up', 7]},
      });
      expect(p.isHome, isTrue);
      expect(p.equipment, {'band', 'bodyweight'});
      expect(p.familiar, ['push-up']);
      expect(const GymPrefs(place: 'home').equipment, kHomeEquipment);
    });

    test('toJson 은 JSON 그대로 적히고 다시 읽힌다', () {
      const p = GymPrefs(place: 'home', equipment: {'dumbbell', 'bodyweight'}, machineCount: 2,
          familiar: ['db-curl']);
      final back = GymPrefs.fromSettings({'gym': p.toJson()});
      expect(back.toJson(), p.toJson());
      expect(p.toJson()['equipment'], ['bodyweight', 'dumbbell'], reason: '정렬');
    });

    test('copyWith — machineCount 를 null 로 지울 수 있다', () {
      const p = GymPrefs(machineCount: 2);
      expect(p.copyWith().machineCount, 2);
      expect(p.copyWith(machineCount: null).machineCount, isNull);
      expect(p.copyWith(machineCount: 5).machineCount, 5);
      expect(p.copyWith(place: 'home').equipment, kGymEquipment, reason: '기구는 스스로 안 바뀝니다');
    });
  });

  group('tailorSession', () {
    test('기구가 다 있는 헬스장은 엔진 그대로 · 번호만 붙는다', () {
      final out = tailorSession(upperA, const GymPrefs());
      expect(names(out), names(withIds(upperA['exercises'] as List)));
      expect(ids(out), ['bench-press', 'incline-db-press', 'pullup-latpulldown', 'barbell-row',
        'overhead-press', 'barbell-curl', 'incline-db-curl']);
      for (final x in out) {
        expect(x['sets'], 3);
        expect(x['reps'], '10-15');
        expect(x['restSec'], 75);
        expect(x['rpe'], '7-8');
        expect(x['note'], '');
      }
    });

    test('집 — 바벨·머신은 같은 부위·같은 움직임의 덤벨·밴드·맨몸으로', () {
      final out = tailorSession(upperA, const GymPrefs(place: 'home'));
      final original = withIds(upperA['exercises'] as List);
      expect(out.length, original.length);
      final byOriginal = {for (var i = 0; i < out.length; i++) '${original[i]['name']}': out[i]};

      expect(byOriginal['바벨 벤치프레스']!['name'], '푸시업');
      expect('${byOriginal['바벨 벤치프레스']!['note']}', startsWith('대체: 원래 바벨 벤치프레스'));
      expect(byOriginal['인클라인 덤벨프레스']!['name'], '인클라인 덤벨프레스', reason: '덤벨은 있습니다');
      expect(byOriginal['풀업 / 랫풀다운']!['name'], '밴드 풀다운', reason: '집에는 철봉이 없습니다');
      expect(byOriginal['바벨 로우']!['name'], '원암 덤벨로우', reason: '덤벨이 있으면 책상 로우보다 덤벨');
      expect(byOriginal['오버헤드 프레스']!['name'], '덤벨 숄더프레스');
      expect(byOriginal['바벨 컬']!['name'], '덤벨 컬', reason: '인클라인 덤벨컬은 이미 있습니다');

      for (final x in out) {
        expect(kHomeEquipment.contains(x['equip']), isTrue, reason: '${x['name']}');
        expect(x['sets'], 3);
        expect(x['restSec'], 75);
      }
      expect(names(out).toSet().length, out.length, reason: '겹치지 않습니다');
    });

    test('집 · 하체 — 철봉이 필요한 맨몸 종목도 바꾼다', () {
      final out = tailorSession(lowerA, const GymPrefs(place: 'home'));
      expect(names(out), ['고블릿 스쿼트', '맨몸 스쿼트', '덤벨 루마니안 데드리프트', '글루트 브릿지', '라잉 레그레이즈']);
      expect(names(out).toSet().length, 5);
    });

    test('맨몸만 있으면 전부 맨몸 · 순서는 그대로', () {
      final out = tailorSession(upperA, const GymPrefs(place: 'home', equipment: {'bodyweight'}));
      expect(out.every((x) => x['equip'] == 'bodyweight'), isTrue);
      expect(out.map((x) => x['group']).toList(),
          ['chest', 'chest', 'back', 'back', 'shoulder', 'arms', 'arms']);
      expect(names(out).toSet().length, out.length);
    });

    test('머신 개수 제한 — 앞에서부터 그 개수만 두고 나머지는 프리웨이트로', () {
      final out = tailorSession(pullA, const GymPrefs(machineCount: 1));
      final machines = out.where((x) => x['equip'] == 'machine' || x['equip'] == 'cable').toList();
      expect(machines.length, 1);
      expect(machines.first['name'], '풀업 / 랫풀다운');
      expect(out[2]['name'], '원암 덤벨로우');
      expect('${out[2]['note']}', startsWith('대체: 원래 시티드 케이블로우'));
      expect(names(out).toSet().length, out.length);

      final none = tailorSession(pullA, const GymPrefs(machineCount: 0));
      expect(none.any((x) => x['equip'] == 'machine' || x['equip'] == 'cable'), isFalse);
    });

    test('잘 아는 종목은 같은 부위에 하나만 바꿔 넣는다', () {
      final out = tailorSession(lowerA, const GymPrefs(familiar: ['goblet-squat', 'bodyweight-squat']));
      expect(names(out), ['바벨 스쿼트', '고블릿 스쿼트', '루마니안 데드리프트', '힙 쓰러스트', '행잉 레그레이즈'],
          reason: '같은 움직임(스쿼트)인 뒤쪽 종목을 바꿉니다 · 두 번째 아는 종목은 안 넣습니다');
      expect('${out[1]['note']}', startsWith('익숙한 종목: 원래 레그프레스'));
      expect(out[1]['sets'], 3);
    });

    test('아는 종목이 이미 있으면 안 바꾼다 · 없는 번호는 무시한다', () {
      final out = tailorSession(lowerA, const GymPrefs(familiar: ['barbell-squat', 'nope']));
      expect(names(out), names(withIds(lowerA['exercises'] as List)));
    });

    test('아는 종목이 머신이고 자리가 없으면 안 넣는다 · 머신 자리를 이어받는 건 된다', () {
      final out = tailorSession(pullA, const GymPrefs(machineCount: 1, familiar: ['band-row']));
      /* 밴드는 헬스장 기본 기구가 아닙니다 — 못 넣습니다. */
      expect(names(out), isNot(contains('밴드 로우')));

      /* 머신 하나(레그프레스)가 이미 자리를 쓰고, 바꿀 자리는 바벨 스쿼트 —
         넣으면 머신이 둘이 되므로 안 넣습니다. */
      final s = session('하체 A', [
        ['레그프레스', 'machine', 'quads'],
        ['바벨 스쿼트', 'barbell', 'quads'],
      ]);
      final out2 = tailorSession(s, const GymPrefs(machineCount: 1, familiar: ['leg-extension']));
      expect(names(out2), ['레그프레스', '바벨 스쿼트']);

      /* 바꿀 자리가 머신이면 머신 수가 안 늘어나니 됩니다. */
      final out3 = tailorSession(
          lowerA, const GymPrefs(machineCount: 1, familiar: ['leg-extension']));
      expect(names(out3)[1], '레그 익스텐션');
      expect(out3.where((x) => x['equip'] == 'machine').length, 1);
    });

    test('대체할 것이 없으면 그대로 두고 건너뛰라고 적는다', () {
      final s = session('상체 A', [['외계 프레스', 'machine', 'alien']]);
      final out = tailorSession(s, const GymPrefs(place: 'home'));
      expect(out.single['name'], '외계 프레스');
      expect(out.single['note'], '기구가 없으면 건너뛰기');
      expect(out.single['id'], '외계-프레스');
    });

    test('쉬는 날과 빈 세션은 빈 목록', () {
      expect(tailorSession({'label': '휴식', 'rest': true, 'exercises': []}, const GymPrefs()), isEmpty);
      expect(tailorSession({'label': '상체 A'}, const GymPrefs()), isEmpty);
    });

    test('같은 입력이면 같은 답', () {
      const p = GymPrefs(place: 'home', machineCount: 1, familiar: ['push-up', 'inverted-row']);
      expect(tailorSession(upperA, p), tailorSession(upperA, p));
    });

    test('withIds — 사전 번호, 없으면 이름에서, 이미 있으면 그대로', () {
      final out = withIds([
        {'name': '플랭크'},
        {'name': '동네 체조 A'},
        {'name': '플랭크', 'id': 'custom-1'},
        'garbage',
      ]);
      expect(ids(out), ['plank', '동네-체조-a', 'custom-1']);
      expect(out.first['name'], '플랭크');
    });

    test('엔진이 실제로 만든 계획도 집에 맞게 고쳐진다', () {
      final scan = {
        'weightKg': 86.7, 'smmKg': 38.0, 'bfmKg': 20.0, 'pbfPct': 23.1,
        'bmrKcal': 1810, 'measuredAt': '2026-03-01T00:00:00.000Z',
      };
      final profile = {
        'sex': 'male', 'age': 22, 'heightCm': 187, 'activityLevel': 'moderate',
        'trainingAge': 'novice', 'daysPerWeek': 4,
      };
      final cmp = compareLevels(scan, profile,
          {'weightKg': 80.5, 'smmKg': 39.0, 'bfmKg': 12.0}, '2026-03-15', null, null);
      final plan = buildPlan(cmp, 'mid', scan, profile)!;
      final sessions = ((plan['workout'] as Map)['sessions'] as List)
          .map((s) => (s as Map).cast<String, Object?>())
          .toList();
      var tailored = 0;
      for (final s in sessions) {
        final out = tailorSession(s, const GymPrefs(place: 'home'));
        if (s['rest'] == true) {
          expect(out, isEmpty);
          continue;
        }
        expect(out.length, (s['exercises'] as List).length);
        expect(names(out).toSet().length, out.length, reason: '${s['label']}');
        for (final x in out) {
          expect(kHomeEquipment.contains(x['equip']), isTrue, reason: '${s['label']} ${x['name']}');
          expect(x['id'], isNotNull);
        }
        tailored++;
      }
      expect(tailored, greaterThan(0));
    });
  });

  group('workoutKcal', () {
    test('80kg · 30분 헬스 = 210 kcal (MET 5)', () {
      expect(workoutKcal(weightKg: 80, duration: const Duration(minutes: 30), kind: 'gym'),
          closeTo(210, 0.001));
    });

    test('80kg · 30분에 5km 달리기 = 시속 10km → MET 9.8~11', () {
      final kcal = workoutKcal(
          weightKg: 80, duration: const Duration(minutes: 30), kind: 'run', km: 5);
      expect(kcal, inInclusiveRange(9.8 * 42, 11.0 * 42));
      expect(workoutMet(kind: 'run', kmh: 10), inInclusiveRange(9.8, 11.0));
      expect(workoutMet(kind: 'run', kmh: 9.7), closeTo(9.8, 0.001));
      expect(workoutMet(kind: 'run', kmh: 14.5), closeTo(12.8, 0.001));
      expect(workoutMet(kind: 'run', kmh: 40), 16.0, reason: '표 끝에서 멈춥니다');
    });

    test('걷기는 속도 구간으로 · 거리가 없으면 3.5', () {
      expect(workoutKcal(weightKg: 80, duration: const Duration(hours: 1), kind: 'walk', km: 3),
          closeTo(2.8 * 84, 0.001));
      expect(workoutKcal(weightKg: 80, duration: const Duration(hours: 1), kind: 'walk', km: 6),
          closeTo(4.3 * 84, 0.001));
      expect(workoutKcal(weightKg: 80, duration: const Duration(hours: 1), kind: 'walk', km: 7),
          closeTo(5.0 * 84, 0.001));
      expect(workoutKcal(weightKg: 80, duration: const Duration(hours: 1), kind: 'walk'),
          closeTo(3.5 * 84, 0.001));
    });

    test('기본 MET — 자전거 6.8 · 유산소 6.0 · 맨몸 8.0 · 모르는 것은 6.0', () {
      expect(workoutMet(kind: 'bike'), 6.8);
      expect(workoutMet(kind: 'cardio'), 6.0);
      expect(workoutMet(kind: 'bodyweight'), 8.0);
      expect(workoutMet(kind: 'zumba'), 6.0);
    });

    test('말이 안 되는 입력은 잘라 낸다', () {
      final big = workoutKcal(weightKg: 634, duration: const Duration(minutes: 30), kind: 'gym');
      expect(big, closeTo(workoutKcal(weightKg: 250, duration: const Duration(minutes: 30), kind: 'gym'), 0.001));
      expect(workoutKcal(weightKg: double.nan, duration: const Duration(minutes: 30), kind: 'gym'),
          closeTo(5 * 3.5 * 70 / 200 * 30, 0.001));
      expect(workoutKcal(weightKg: 80, duration: const Duration(minutes: -5), kind: 'gym'), 0);
      expect(workoutKcal(weightKg: 80, duration: const Duration(hours: 20), kind: 'gym'),
          closeTo(workoutKcal(weightKg: 80, duration: const Duration(hours: 6), kind: 'gym'), 0.001));
      expect(workoutKcal(weightKg: 80, duration: const Duration(minutes: 30), kind: 'run', km: -1),
          closeTo(9.8 * 42, 0.001), reason: '음수 거리는 없는 것');
    });

    test('이름표', () {
      expect(kCardioKinds.map(cardioKindLabel), ['걷기', '달리기', '자전거', '유산소']);
      expect(cardioKindLabel('gym'), '헬스');
      expect(cardioKindLabel('???'), '유산소');
    });
  });

  group('bodyweightRoutine', () {
    const novice = {'trainingAge': 'novice'};
    const inter = {'trainingAge': 'intermediate'};
    const adv = {'trainingAge': 'advanced'};

    void checkShape(Map<String, Object?> r, {required int minutes, double weightKg = 75}) {
      final ex = (r['exercises'] as List).cast<Map<String, Object?>>();
      expect(ex.length, greaterThanOrEqualTo(2));
      for (final x in ex) {
        final e = exerciseById('${x['id']}');
        expect(e, isNotNull, reason: '${x['name']}');
        expect(e!.equip, 'bodyweight');
        expect(e.needsBar, isFalse, reason: '방 안에서 하는 운동입니다');
        expect(x['name'], e.name);
        expect(x['sets'], isA<int>());
        expect(x['restSec'], isA<int>());
        expect(x.containsKey('reps') != x.containsKey('seconds'), isTrue, reason: '반복 아니면 초');
        expect(x['note'], isA<String>());
      }
      expect(exerciseById('${ex.last['id']}')!.group, 'core', reason: '마지막은 코어');
      expect(ex.map((x) => x['id']).toSet().length, ex.length);
      expect(r['minutes'], minutes);
      expect((r['plannedSec'] as int).abs() - minutes * 60, inInclusiveRange(-90, 90));
      expect(r['kcal'], closeTo(
          workoutKcal(weightKg: weightKg, duration: Duration(seconds: r['plannedSec'] as int),
              kind: 'bodyweight'),
          0.001));
      expect('${r['why']}', isNotEmpty);
    }

    test('초보 · 하체 날 — 3세트 × 10회, 하체 위주, 마지막은 코어', () {
      final r = bodyweightRoutine(profile: novice, weightKg: 75, pbfPct: 20, todayLabel: '하체 A');
      expect(r['focus'], 'lower');
      expect(r['title'], '하체 15분 맨몸');
      expect(r['lowImpact'], isFalse);
      checkShape(r, minutes: 15);
      final ex = (r['exercises'] as List).cast<Map<String, Object?>>();
      expect(ex.length, 5);
      for (final x in ex) {
        expect(x['sets'], 3);
        if (x.containsKey('reps')) expect(x['reps'], 10);
      }
      expect(ex.first['name'], '맨몸 스쿼트');
      expect(ex.last['id'], 'lying-leg-raise');
      expect('${r['why']}', contains('하체'));
      expect('${r['why']}', contains('초보'));
    });

    test('체중 95kg 초과 — 점프 없이, 이유를 말한다', () {
      for (final label in ['하체 A', '상체 A', '풀 A', '']) {
        final r = bodyweightRoutine(profile: adv, weightKg: 100, pbfPct: 20, todayLabel: label);
        expect(r['lowImpact'], isTrue, reason: label);
        final got = (r['exercises'] as List).map((x) => (x as Map)['id']).toSet();
        expect(got.intersection({'jump-squat', 'burpee', 'jumping-jack', 'mountain-climber', 'high-knees', 'jump-rope'}),
            isEmpty, reason: label);
        expect('${r['why']}', contains('점프 동작은 뺐습니다'));
        expect('${r['why']}', contains('95kg'));
      }
      final r = bodyweightRoutine(profile: adv, weightKg: 100, todayLabel: '하체 A');
      expect((r['exercises'] as List).map((x) => (x as Map)['id']),
          containsAll(['bodyweight-squat', 'glute-bridge']));
    });

    test('체지방률 30% 초과도 같은 이유로 · 둘 다면 둘 다 말한다', () {
      final r = bodyweightRoutine(profile: novice, weightKg: 60, pbfPct: 33, todayLabel: '전신 A');
      expect(r['lowImpact'], isTrue);
      expect('${r['why']}', contains('30%'));
      expect('${r['why']}', isNot(contains('95kg')));
      final both = bodyweightRoutine(profile: novice, weightKg: 120, pbfPct: 40);
      expect('${both['why']}', contains('95kg'));
      expect('${both['why']}', contains('30%'));
      final fine = bodyweightRoutine(profile: novice, weightKg: 95, pbfPct: 30);
      expect(fine['lowImpact'], isFalse, reason: '경계값은 넘은 것이 아닙니다');
    });

    test('상체 날 — 푸시업 계열, 플랭크로 마무리 (초 단위)', () {
      final r = bodyweightRoutine(profile: inter, weightKg: 75, todayLabel: '가슴·어깨·삼두');
      expect(r['focus'], 'upper');
      expect(r['title'], '상체 15분 맨몸');
      checkShape(r, minutes: 15);
      final ex = (r['exercises'] as List).cast<Map<String, Object?>>();
      expect(ex.first['id'], 'push-up');
      expect(ex.last['id'], 'plank');
      expect(ex.last['seconds'], 40);
      expect(ex.last.containsKey('reps'), isFalse);
      for (final x in ex) {
        expect(x['sets'], 3);
        if (x.containsKey('reps')) expect(x['reps'], 14);
      }
      expect('${r['why']}', contains('중급'));
    });

    test('분할 이름 → 초점', () {
      expect(focusOf('하체 A'), 'lower');
      expect(focusOf('레그 B'), 'lower');
      expect(focusOf('하체·코어'), 'lower');
      expect(focusOf('상체 전체'), 'upper');
      expect(focusOf('푸시 A'), 'upper');
      expect(focusOf('가슴·어깨·삼두'), 'upper');
      expect(focusOf('풀 A'), 'pull');
      expect(focusOf('등·이두'), 'pull');
      expect(focusOf('전신 A'), 'full');
      expect(focusOf('휴식'), 'full');
      expect(focusOf(''), 'full');
    });

    test('계획이 없거나 쉬는 날은 전신 · 이유가 다르다', () {
      final none = bodyweightRoutine(profile: novice, weightKg: 75);
      expect(none['focus'], 'full');
      expect(none['title'], '전신 15분 맨몸');
      expect('${none['why']}', contains('계획한 분할이 없어'));
      final rest = bodyweightRoutine(profile: novice, weightKg: 75, todayLabel: '휴식');
      expect(rest['focus'], 'full');
      expect('${rest['why']}', contains('쉬는 날'));
      checkShape(rest, minutes: 15);
      expect(((rest['exercises'] as List).last as Map)['id'], 'plank');
    });

    test('등 날 — 당기는 맨몸 종목, 데드버그로 마무리', () {
      final r = bodyweightRoutine(profile: novice, weightKg: 75, todayLabel: '등·이두');
      expect(r['focus'], 'pull');
      checkShape(r, minutes: 15);
      final ex = (r['exercises'] as List).cast<Map<String, Object?>>();
      expect(ex.first['id'], 'superman');
      expect(ex.last['id'], 'dead-bug');
    });

    test('상급 — 4세트 × 15회, 어려운 변형 (점프 스쿼트)', () {
      final r = bodyweightRoutine(profile: adv, weightKg: 70, pbfPct: 12, todayLabel: '레그 A');
      checkShape(r, minutes: 15, weightKg: 70);
      final ex = (r['exercises'] as List).cast<Map<String, Object?>>();
      expect(ex.first['id'], 'jump-squat');
      for (final x in ex) {
        expect(x['sets'], 4);
        if (x.containsKey('reps')) expect(x['reps'], 15);
      }
      expect('${r['why']}', contains('상급'));
      expect('${r['why']}', contains('어려운 변형'));
      expect(bodyweightRoutine(profile: const {}, weightKg: 70)['level'], 'novice',
          reason: '경력을 모르면 초보로');
    });

    test('시간을 바꾸면 종목 수와 휴식이 따라온다', () {
      for (final m in [5, 10, 15, 20, 30]) {
        final r = bodyweightRoutine(profile: novice, weightKg: 75, todayLabel: '하체 A', minutes: m);
        expect(r['minutes'], m);
        expect((r['plannedSec'] as int) - m * 60, inInclusiveRange(-120, 120), reason: '$m분');
        final ex = (r['exercises'] as List).cast<Map<String, Object?>>();
        expect(ex.last['id'], 'lying-leg-raise', reason: '$m분');
        for (final x in ex) {
          expect(x['restSec'], inInclusiveRange(15, 60));
        }
      }
      expect(bodyweightRoutine(profile: novice, weightKg: 75, minutes: 0)['minutes'], 5,
          reason: '5분 아래는 5분');
    });

    test('같은 입력이면 같은 답', () {
      final a = bodyweightRoutine(profile: inter, weightKg: 82.3, pbfPct: 24, todayLabel: '푸시 B');
      final b = bodyweightRoutine(profile: inter, weightKg: 82.3, pbfPct: 24, todayLabel: '푸시 B');
      expect(a, b);
    });
  });
}
