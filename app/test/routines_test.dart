/* =============================================================================
 * routines_test.dart — 내 루틴(workout/routines.dart)의 읽기 · 쓰기
 *
 * 저장소(SharedPreferences 흉내)에 실제로 남는지, JSON 으로 그대로 적히는 모양인지,
 * 같은 이름을 두 번 저장하면 하나로 남는지.
 * ========================================================================== */
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mybody/src/app_state.dart';
import 'package:mybody/src/workout/routines.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  DateTime now = DateTime.utc(2026, 9, 27, 9, 0);

  Future<AppState> seeded() async {
    SharedPreferences.setMockInitialValues({});
    final app = await AppState.boot();
    app.store.now = () => now;
    app.store.set({'onboarded': true});
    return app;
  }

  const exercises = [
    {'name': '바벨 스쿼트', 'sets': 3, 'reps': '5-8', 'restSec': 150, 'kg': 60.0},
    {'name': '레그 컬', 'sets': 3, 'reps': '10-15', 'restSec': 75, 'kg': null},
    {'name': '플랭크', 'sets': 3, 'reps': '30초', 'restSec': 60},
  ];

  test('저장하면 state[routines] 에 남고, 모양은 JSON 으로 그대로', () async {
    final app = await seeded();
    expect(routinesOf(app), isEmpty);

    final r = saveRoutine(app, name: '하체 B 내 버전', label: '하체 B', exercises: exercises);
    expect(r['id'], startsWith('r-'));
    expect(r['name'], '하체 B 내 버전');
    expect(r['label'], '하체 B');
    expect(r['createdAt'], '2026-09-27T09:00:00.000Z');
    expect(r['updatedAt'], '2026-09-27T09:00:00.000Z');
    expect(r['exercises'], [
      {'name': '바벨 스쿼트', 'sets': 3, 'reps': '5-8', 'restSec': 150, 'kg': 60.0},
      {'name': '레그 컬', 'sets': 3, 'reps': '10-15', 'restSec': 75},   // 맨몸(kg null)은 칸 없음
      {'name': '플랭크', 'sets': 3, 'reps': '30초', 'restSec': 60},
    ]);

    final list = routinesOf(app);
    expect(list, hasLength(1));
    expect(list.single['id'], r['id']);
    expect(app.state[kRoutinesKey], isA<List>());
    expect(() => jsonEncode(app.state[kRoutinesKey]), returnsNormally);
    expect(routineExercises(r), hasLength(3));
  });

  test('같은 이름을 다시 저장하면 그 루틴이 고쳐진다 — createdAt 은 그대로, updatedAt 은 새로', () async {
    final app = await seeded();
    final a = saveRoutine(app, name: '상체 A 내 루틴', label: '상체 A', exercises: exercises);
    now = now.add(const Duration(days: 1));
    final b = saveRoutine(app, name: '상체 A 내 루틴', label: '상체 A', exercises: exercises.sublist(0, 1));
    expect(b['id'], a['id']);
    expect(b['createdAt'], a['createdAt']);
    expect(b['updatedAt'], '2026-09-28T09:00:00.000Z');
    expect(routinesOf(app), hasLength(1));
    expect(routineExercises(routinesOf(app).single), hasLength(1));
  });

  test('id 로 저장하면 이름을 바꿔도 같은 루틴', () async {
    final app = await seeded();
    final a = saveRoutine(app, name: '가', label: 'L', exercises: exercises);
    final b = saveRoutine(app, id: '${a['id']}', name: '나', label: 'L', exercises: exercises);
    expect(b['id'], a['id']);
    expect(routinesOf(app).single['name'], '나');
    expect(routineById(app, '${a['id']}')!['name'], '나');
    expect(routineById(app, '없음'), isNull);
  });

  test('routinesOf 는 최근에 고친 것이 앞, routineForLabel 은 그 라벨의 가장 최근 것', () async {
    final app = await seeded();
    saveRoutine(app, name: '첫째', label: '하체 A', exercises: exercises);
    now = now.add(const Duration(hours: 1));
    saveRoutine(app, name: '둘째', label: '상체 A', exercises: exercises);
    now = now.add(const Duration(hours: 1));
    saveRoutine(app, name: '셋째', label: '하체 A', exercises: exercises);
    expect([for (final r in routinesOf(app)) r['name']], ['셋째', '둘째', '첫째']);
    expect(routineForLabel(app, '하체 A')!['name'], '셋째');
    expect(routineForLabel(app, ' 상체 A ')!['name'], '둘째', reason: '앞뒤 공백은 무시');
    expect(routineForLabel(app, '없는 라벨'), isNull);
    expect(routineForLabel(app, ''), isNull);
  });

  test('지우기 — 있었으면 true, 없으면 false, 묘비가 남는다', () async {
    final app = await seeded();
    final a = saveRoutine(app, name: '가', exercises: exercises);
    saveRoutine(app, name: '나', exercises: exercises);
    expect(deleteRoutine(app, '${a['id']}'), isTrue);
    expect([for (final r in routinesOf(app)) r['name']], ['나']);
    expect(deleteRoutine(app, '${a['id']}'), isFalse);
    expect(routinesOf(app), hasLength(1));
    /* 기준본 없는 동기화(새 기기 · 재로그인)가 지운 것을 알아보는 단서 — merge.dart 가 같은 칸을 읽습니다. */
    final tomb = ((app.state['tombstones'] as Map)[kRoutinesKey] as Map);
    expect(tomb['${a['id']}'], now.toUtc().toIso8601String());
  });

  test('같은 종목이 두 번 든 루틴은 첫 것만 — 헬스 화면의 줄 키가 종목 id 라 겹치면 깨진다', () async {
    final app = await seeded();
    app.store.set({kRoutinesKey: [
      {'id': 'r-dup', 'name': '겹침', 'label': '', 'exercises': [
        {'name': '바벨 스쿼트', 'sets': 3, 'reps': '5-8', 'restSec': 150},
        {'name': '레그 컬', 'sets': 3, 'reps': '10-15', 'restSec': 75},
        {'name': '바벨스쿼트', 'sets': 4, 'reps': '5-8', 'restSec': 150},      // 띄어쓰기만 다른 같은 종목
        {'name': '동네 체조', 'sets': 2, 'reps': '10', 'restSec': 60},
        {'name': '동네 체조', 'sets': 2, 'reps': '10', 'restSec': 60},        // 사전에 없는 이름도 같은 slug
      ], 'createdAt': 'x', 'updatedAt': 'x'},
    ]});
    final xs = routineExercises(routineById(app, 'r-dup')!);
    expect([for (final x in xs) x['name']], ['바벨 스쿼트', '레그 컬', '동네 체조']);
    expect(xs.first['sets'], 3, reason: '첫 것이 남습니다');
  });

  test('편측(perSide) 과 초(seconds) 는 저장해도 남는다 — 다시 연 루틴의 런지가 「한쪽씩」 을 잃지 않게', () async {
    final app = await seeded();
    final r = saveRoutine(app, name: '하체', exercises: [
      {'name': '런지', 'sets': 3, 'reps': '8-12', 'restSec': 60, 'perSide': true},
      {'name': '플랭크', 'sets': 3, 'reps': '30초', 'restSec': 45, 'seconds': 30},
      {'name': '레그 컬', 'sets': 3, 'reps': '10-15', 'restSec': 60, 'perSide': false, 'seconds': 0},
    ]);
    expect(r['exercises'], [
      {'name': '런지', 'sets': 3, 'reps': '8-12', 'restSec': 60, 'perSide': true},
      {'name': '플랭크', 'sets': 3, 'reps': '30초', 'restSec': 45, 'seconds': 30},
      {'name': '레그 컬', 'sets': 3, 'reps': '10-15', 'restSec': 60},     // 거짓 · 0 은 칸 없음
    ]);
    expect(() => jsonEncode(app.state[kRoutinesKey]), returnsNormally);
  });

  test('빈 이름은 기본 이름, 이상한 값은 기본값 — 저장 모양이 흔들리지 않는다', () async {
    final app = await seeded();
    expect(defaultRoutineName('하체 B'), '하체 B 내 루틴');
    expect(defaultRoutineName(''), '내 루틴');
    expect(defaultRoutineName('  '), '내 루틴');
    final r = saveRoutine(app, name: '  ', label: '전신', exercises: [
      {'name': '푸시업', 'sets': 0, 'reps': null, 'restSec': -5, 'kg': 0},
    ]);
    expect(r['name'], '전신 내 루틴');
    expect(r['exercises'], [{'name': '푸시업', 'sets': 3, 'reps': '10-15', 'restSec': 75}]);
    /* 깨진 항목(id 없음)은 routinesOf 가 거릅니다. */
    app.store.set({kRoutinesKey: [...routinesOf(app), {'name': 'id 없음'}, 'string']});
    expect(routinesOf(app), hasLength(1));
  });
}
