/* =============================================================================
 * core_wiring_test.dart — **코어가 앱 안에서 실제로 도는가**
 *
 * 차이 검사(tools/difftest.js)는 코어가 원본 자바스크립트와 같은 답을 내는지
 * 봅니다. 그런데 그건 코어를 `dart run` 으로 직접 부를 때 얘기입니다.
 * 앱 안에서도 같은 답이 나오는지는 다른 문제입니다 — 저장소를 잘못 꽂거나
 * 고리(modes·noise·일정 요약)를 안 꽂으면 조용히 다른 답이 나옵니다.
 *
 * 그래서 앱이 실제로 쓰는 길로 한 번 통과시켜 봅니다.
 * ========================================================================== */
import 'package:flutter_test/flutter_test.dart';
import 'package:mybody/src/app_state.dart';
import 'package:mybody_core/mybody_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('저장한 것이 다시 읽힌다 — 웹 앱과 같은 칸, 같은 모양', () async {
    final app = await AppState.boot();
    app.store.set({'onboarded': true});
    app.store.addScan({
      'id': 's1', 'weightKg': 70.0, 'smmKg': 31.0, 'bfmKg': 14.0,
      'measuredAt': '2026-03-01T00:00:00.000Z',
    });

    // 같은 칸을 새로 읽습니다 (앱을 다시 켠 셈).
    final again = await AppState.boot();
    expect(again.onboarded, isTrue);
    expect(again.store.sortedScans().length, 1);
    expect(again.store.sortedScans().first['weightKg'], 70.0);
  });

  test('백업 파일이 웹 앱과 같은 판(version 1)이다', () async {
    final app = await AppState.boot();
    final text = app.store.exportJSON();
    expect(text.contains('"version": 1'), isTrue,
        reason: '판이 다르면 웹에서 받은 백업을 앱에서 못 엽니다');
  });

  test('엔진이 modes 의 노이즈 바닥을 실제로 읽는다', () async {
    await AppState.boot();      // 여기서 고리를 꽂습니다
    /* 목표 변화가 노이즈 바닥(지방 1.0kg) 안이면 "유지" 여야 합니다.
       고리를 안 꽂으면 코어의 기본값으로 돌아서 같은 답이 나오므로,
       바닥보다 **조금 큰** 값으로 경계를 밟습니다. */
    final cur = {'weightKg': 70.0, 'smmKg': 31.0, 'bfmKg': 14.0, 'smmToFfm': 0.55};
    final flat = classifyGoal(cur, {'weightKg': 70.0, 'smmKg': 31.0, 'bfmKg': 13.5});
    final cut = classifyGoal(cur, {'weightKg': 68.0, 'smmKg': 31.0, 'bfmKg': 12.0});
    expect(flat['type'], 'maintain');
    expect(cut['type'], 'cut');
    expect((flat['noise'] as Map)['bfm'], 1.0);
  });

  test('일정 요약이 주간 스냅샷에 실제로 들어간다', () async {
    final app = await AppState.boot();
    app.store.set({'onboarded': true});
    final today = app.store.dayKey();
    app.store.setSchedulePlan(today, 'gym', true);
    app.store.setScheduleDone(today, 'gym', true);

    final snap = app.store.weeklySnapshot();
    expect(snap['plannedDays'], 1, reason: '고리를 안 꽂으면 이 칸이 통째로 빕니다');
    expect(snap['keptDays'], 1);
    expect(snap['checkedIn'], isTrue);
  });

  test('계획 한 벌이 앱 안에서 끝까지 만들어진다', () async {
    await AppState.boot();
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
    final results = cmp['results'] as List;
    expect(results.length, 3, reason: '상·중·하 세 장이 나와야 합니다');

    final plan = buildPlan(cmp, 'mid', scan, profile);
    expect(plan, isNotNull);
    expect(plan!['targetDate'], isA<String>());
    expect((plan['workout'] as Map)['sessions'], isA<List>());
    expect((plan['diet'] as Map)['meals'], isA<List>());
    // 부위별 값이 없으면 "약점 없음" 이라고 말하지 않습니다.
    expect((plan['workout'] as Map)['hasSegmental'], isFalse);
  });

  test('식단 추천이 앱 안에서 실제 음식을 내놓는다', () async {
    await AppState.boot();
    final res = suggestMeal({'remainP': 60, 'remainKcal': 900, 'mealsLeft': 1});
    expect((res['options'] as List), isNotEmpty);
    final first = ((res['options'] as List).first as Map)['items'] as List;
    expect(first, isNotEmpty);
    expect((first.first as Map)['name'], isA<String>());
  });
}
