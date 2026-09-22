/* =============================================================================
 * nudge_test.dart — 간식 단백질 알림은 언제, 무슨 말로 우는가
 * ========================================================================== */
import 'package:flutter_test/flutter_test.dart';
import 'package:mybody/src/nudge.dart';

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
}
