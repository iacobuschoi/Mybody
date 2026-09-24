/* =============================================================================
 * nudge_test.dart — 간식 단백질 알림은 언제, 무슨 말로 우는가
 * ========================================================================== */
import 'package:flutter_test/flutter_test.dart';
import 'package:mybody/src/nudge.dart';
import 'package:mybody/src/screens/food.dart' show guessMeal;

void main() {
  final morning = DateTime(2026, 9, 22, 10, 0);

  test('단백질이 15g 안 남았으면 안 운다', () {
    expect(planSnackNudge(remainP: 12, remainKcal: 600, remainC: 80, remainF: 20, now: morning), isNull);
    expect(planSnackNudge(remainP: 0, remainKcal: 600, remainC: 80, remainF: 20, now: morning), isNull);
  });

  test('오전이면 오후 3시 반, 오후면 저녁 8시 반, 밤이면 오늘은 없음', () {
    final a = planSnackNudge(remainP: 42, remainKcal: 700, remainC: 90, remainF: 25, now: morning)!;
    expect(a.at, DateTime(2026, 9, 22, 15, 30));
    final b = planSnackNudge(remainP: 42, remainKcal: 700, remainC: 90, remainF: 25,
        now: DateTime(2026, 9, 22, 16, 0))!;
    expect(b.at, DateTime(2026, 9, 22, 20, 30));
    expect(planSnackNudge(remainP: 42, remainKcal: 700, remainC: 90, remainF: 25,
        now: DateTime(2026, 9, 22, 21, 0)), isNull);
  });

  test('문구에 남은 단백질과 먹을 것이 있다', () {
    final n = planSnackNudge(remainP: 42, remainKcal: 700, remainC: 90, remainF: 25, now: morning)!;
    expect(n.title, '간식으로 단백질 채우기');
    expect(n.body, contains('단백질 42g 남았어요'));
    expect(n.body, contains('간식으로'));
    expect(n.body, contains('어때요?'));
  });

  test('칼로리가 없으면 먹을 것 대신 일반 안내', () {
    final n = planSnackNudge(remainP: 42, remainKcal: 0, remainC: 0, remainF: 0, now: morning)!;
    expect(n.body, contains('단백질 42g 남았어요'));
  });

  group('끼니 기록 알림 — 10시 아침 · 13시 점심 · 19시 저녁', () {
    test('아침 9시, 아직 아무것도 안 적었으면 오늘 세 번부터 14일치', () {
      final r = planMealReminders(now: DateTime(2026, 9, 24, 9, 0));
      expect(r, hasLength(kMealDays * 3));
      expect([for (final x in r.take(3)) x.at], [
        DateTime(2026, 9, 24, 10), DateTime(2026, 9, 24, 13), DateTime(2026, 9, 24, 19),
      ]);
      expect([for (final x in r.take(3)) x.title],
          ['아침 메뉴를 기록해주세요!', '점심 메뉴를 기록해주세요!', '저녁 메뉴를 기록해주세요!']);
      expect(r.last.at, DateTime(2026, 10, 7, 19));
    });

    test('이미 지난 시각은 오늘 빼고, 내일부터는 그대로', () {
      final r = planMealReminders(now: DateTime(2026, 9, 24, 13, 0));
      expect(r.first.at, DateTime(2026, 9, 24, 19), reason: '13시 정각은 이미 지난 것으로 봅니다');
      expect(r[1].at, DateTime(2026, 9, 25, 10));
    });

    test('오늘 이미 적은 끼니는 안 울린다 — 오늘만', () {
      final r = planMealReminders(now: DateTime(2026, 9, 24, 8, 0), loggedToday: {'아침', '간식'});
      expect(r.where((x) => x.at.day == 24).map((x) => x.meal), ['점심', '저녁']);
      expect(r.where((x) => x.at.day == 25).map((x) => x.meal), ['아침', '점심', '저녁']);
    });

    test('밤에는 오늘 것이 없고, 달이 바뀌어도 다음 날 10시', () {
      final r = planMealReminders(now: DateTime(2026, 9, 30, 20, 0));
      expect(r.first.at, DateTime(2026, 10, 1, 10));
      expect(r, hasLength((kMealDays - 1) * 3));
    });

    test('알림 번호는 겹치지 않고, 간식(7) · 운동 독촉(1000~) 과도 안 겹친다', () {
      final r = planMealReminders(now: DateTime(2026, 9, 24, 0, 0));
      final ids = [for (final x in r) x.id];
      expect(ids.toSet(), hasLength(ids.length));
      expect(ids.every((id) => id >= kMealIdBase && id < kMealIdBase + kMealDays * 3), isTrue);
      expect(ids.contains(7), isFalse);
      expect(kMealIdBase + kMealDays * 3 <= 1000, isTrue);
    });
  });

  group('끼니 알림을 누르고 적으면 그 끼니로', () {
    tearDown(() => tappedMealReminder = null);

    test('아침 알림을 누른 뒤 3시간 동안은 아침 — 시각으로는 점심이어도', () {
      tappedMealReminder = (meal: '아침', at: DateTime(2026, 9, 24, 10, 2));
      expect(mealFromReminder(DateTime(2026, 9, 24, 10, 5)), '아침');
      expect(guessMeal(DateTime(2026, 9, 24, 12, 30)), '아침');
      expect(mealFromReminder(DateTime(2026, 9, 24, 13, 5)), isNull, reason: '3시간이 지나면 시각대로');
      expect(guessMeal(DateTime(2026, 9, 24, 13, 5)), '점심');
    });

    test('알림을 안 눌러도 10시대는 아침 — 10시 알림을 보고 앱을 직접 열어 적는 경우', () {
      expect(guessMeal(DateTime(2026, 9, 24, 9, 59)), '아침');
      expect(guessMeal(DateTime(2026, 9, 24, 10, 30)), '아침');
      expect(guessMeal(DateTime(2026, 9, 24, 11, 0)), '점심');
      /* 그래서 10시대에 적은 아침이 13시 점심 알림을 지우지 않습니다. */
      final r = planMealReminders(now: DateTime(2026, 9, 24, 10, 30),
          loggedToday: {guessMeal(DateTime(2026, 9, 24, 10, 30))});
      expect(r.where((x) => x.at.day == 24).map((x) => x.meal), ['점심', '저녁']);
    });
  });
}
