/* =============================================================================
 * schedule_log_test.dart — 운동 기록(log)과 묘비(tombstones)
 *
 * 일정 칸에 "무엇을 했는지" 가 붙었습니다. 여기서 보는 것:
 *   · 적으면 체크도 되고, 지우면 기록만 사라지고, 체크를 풀면 기록도 간다
 *   · 아직 안 온 날은 못 적는다 (체크와 같은 규칙)
 *   · 셋(계획·체크·기록) 다 비면 그 날 칸이 사라진다 — 백업이 안 커진다
 *   · 옛 백업(log 칸이 없는 것)도 그대로 읽힌다
 *   · 측정·식단 기록을 지우면 묘비가 남고, 90일 지난 묘비는 버린다
 *   · 내보낸 것을 다시 들이면 같은 모양이다
 * ========================================================================== */
import 'dart:convert';

import 'package:mybody_core/mybody_core.dart';
import 'package:test/test.dart';

final t0 = DateTime(2026, 9, 24, 12);          // 오늘 정오 (기기 시각)

Store make({DateTime? now}) {
  final s = Store(storage: MemoryStorage());
  var clock = now ?? t0;
  s.now = () => clock;
  s.load();
  return s;
}

String iso(DateTime d) => d.toUtc().toIso8601String();

void main() {
  const today = '2026-09-24';
  const tomorrow = '2026-09-25';
  const yesterday = '2026-09-23';
  final gymLog = <String, Object?>{
    'exercises': ['bench-press', 'barbell-row'], 'minutes': 40, 'kcal': 280.5,
  };

  test('빈 상태에 새 칸이 있다 — tombstones · 일정의 log', () {
    final b = Store.blank();
    expect(b['tombstones'], {'scans': {}, 'foodLogs': {}});
    final s = make();
    expect(s.scheduleDay(today), {'plan': [], 'done': {}});
  });

  test('기록을 적으면 체크도 되고, 계획에도 들어간다', () {
    final s = make();
    final r = s.setScheduleLog(today, 'gym', gymLog)!;
    expect(r['plan'], ['gym']);
    expect((r['done'] as Map)['gym'], iso(t0));
    final log = (r['log'] as Map)['gym'] as Map;
    expect(log['exercises'], ['bench-press', 'barbell-row']);
    expect(log['minutes'], 40);
    expect(log['kcal'], 280.5);
    expect(log['at'], iso(t0), reason: '언제 적었는지가 붙습니다');
    expect(s.scheduleDay(today), r, reason: '다시 읽어도 같습니다');
  });

  test('이미 체크한 시각은 그대로 두고, 준 at 도 그대로 둔다', () {
    var clock = t0;
    final s = Store(storage: MemoryStorage())..now = () => clock;
    s.setScheduleDone(today, 'gym', true);
    clock = t0.add(const Duration(hours: 3));
    s.setScheduleLog(today, 'gym', {...gymLog, 'at': '2026-09-24T01:00:00.000Z'});
    final d = s.scheduleDay(today);
    expect((d['done'] as Map)['gym'], iso(t0));
    expect(((d['log'] as Map)['gym'] as Map)['at'], '2026-09-24T01:00:00.000Z');
  });

  test('null 이면 기록만 지우고 체크는 남는다', () {
    final s = make();
    s.setScheduleLog(today, 'gym', gymLog);
    final r = s.setScheduleLog(today, 'gym', null)!;
    expect(r['log'] ?? const {}, isEmpty);
    expect((r['done'] as Map).containsKey('gym'), isTrue);
    expect(r['plan'], ['gym']);
  });

  test('체크를 풀면 기록도 간다', () {
    final s = make();
    s.setScheduleLog(today, 'gym', gymLog);
    s.setScheduleLog(today, 'cardio', {'kind': 'run', 'km': 5});
    final r = s.setScheduleDone(today, 'gym', false)!;
    expect((r['log'] as Map).keys, ['cardio'], reason: '다른 운동의 기록은 남습니다');
    expect((r['done'] as Map).keys, ['cardio']);
  });

  test('계획을 지우면 체크와 기록이 같이 간다', () {
    final s = make();
    s.setScheduleLog(today, 'gym', gymLog);
    final r = s.setSchedulePlan(today, 'gym', false)!;
    expect(r, {'plan': [], 'done': {}});
    expect((s.get()['schedule'] as Map).containsKey(today), isFalse, reason: '빈 날은 칸째 사라집니다');
  });

  test('아직 안 온 날은 못 적는다 · 모르는 종류는 null', () {
    final s = make();
    final r = s.setScheduleLog(tomorrow, 'gym', gymLog)!;
    expect(r, {'plan': [], 'done': {}});
    expect((s.get()['schedule'] as Map).containsKey(tomorrow), isFalse);
    expect(s.setScheduleLog(today, 'yoga', gymLog), isNull);
    expect(s.setScheduleLog(yesterday, 'gym', gymLog), isNotNull, reason: '지난 날은 됩니다');
    expect(((s.scheduleDay(yesterday)['log'] as Map)['gym'] as Map)['minutes'], 40);
  });

  test('셋 다 비어야 칸이 사라진다 — 기록만 있는 날도 남는다', () {
    final s = make();
    s.replaceState({
      'schedule': {
        today: {'plan': [], 'done': {}, 'log': {'gym': {'minutes': 10}}},
      },
    });
    expect((s.scheduleDay(today)['log'] as Map)['gym'], {'minutes': 10});
    s.setScheduleLog(today, 'gym', null);
    expect((s.get()['schedule'] as Map).containsKey(today), isFalse);
  });

  test('돌려준 것과 넣은 것은 복사본이다 — 고쳐도 저장된 것은 안 바뀐다', () {
    final s = make();
    final input = <String, Object?>{'exercises': <Object?>['a'], 'minutes': 10};
    s.setScheduleLog(today, 'gym', input);
    (input['exercises'] as List).add('b');
    input['minutes'] = 99;
    final got = (s.scheduleDay(today)['log'] as Map)['gym'] as Map;
    expect(got['exercises'], ['a']);
    expect(got['minutes'], 10);
    (got['exercises'] as List).add('c');
    expect(((s.scheduleDay(today)['log'] as Map)['gym'] as Map)['exercises'], ['a']);
  });

  test('JSON 이 못 담는 값은 글자가 된다 — 저장이 터지지 않는다', () {
    final s = make();
    s.setScheduleLog(today, 'gym', {'when': DateTime.utc(2026, 9, 24, 3)});
    final got = (s.scheduleDay(today)['log'] as Map)['gym'] as Map;
    expect(got['when'], '2026-09-24 03:00:00.000Z');
    expect(() => jsonDecode(s.exportJSON()), returnsNormally);
  });

  test('옛 모양(log 칸 없음)도 읽히고, 기록이 없으면 log 칸을 안 만든다', () {
    final s = make();
    s.replaceState({
      'schedule': {
        yesterday: {'plan': ['gym'], 'done': {'gym': '2026-09-23T10:00:00.000Z'}},
      },
    });
    expect(s.scheduleDay(yesterday)['log'], isNull);
    s.setScheduleDone(today, 'gym', true);
    final raw = (s.get()['schedule'] as Map)[today] as Map;
    expect(raw.containsKey('log'), isFalse, reason: '웹(원본)이 모르는 칸을 빈 채로 만들지 않습니다');
    expect(s.scheduleDay(today)['log'], isNull);
  });

  test('일정 요약과 스트릭은 기록으로 적은 날도 지킨 날로 센다', () {
    final s = make();
    final sch = Schedule(s);
    s.weekSummaryOf = (ws) => sch.weekSummary(ws);
    s.setSchedulePlan(today, 'gym', true);
    s.setScheduleLog(today, 'gym', gymLog);
    expect(sch.weekSummary()['keptDays'], 1);
    expect(sch.workoutStreak()['days'], 1);
  });

  group('묘비', () {
    test('측정을 지우면 묘비가 남는다', () {
      final s = make();
      s.addScan({'id': 's1', 'weightKg': 70.0, 'measuredAt': '2026-09-01T00:00:00.000Z'});
      s.addScan({'id': 's2', 'weightKg': 71.0, 'measuredAt': '2026-09-02T00:00:00.000Z'});
      s.removeScan('s1');
      expect(s.sortedScans().map((x) => x['id']), ['s2']);
      expect((s.get()['tombstones'] as Map)['scans'], {'s1': iso(t0)});
      expect((s.get()['tombstones'] as Map)['foodLogs'], {});
    });

    test('식단 기록을 지우면 묘비가 남는다', () {
      final s = make();
      final row = s.addFoodLog({'items': [{'name': '밥', 'kcal': 300}]});
      s.removeFoodLog(row['id']);
      expect(s.logsForDate(today), isEmpty);
      expect((s.get()['tombstones'] as Map)['foodLogs'], {row['id']: iso(t0)});
    });

    test('없는 id 도 적고, 빈 id 는 안 적는다', () {
      final s = make();
      s.removeScan('ghost');
      s.removeScan(null);
      s.removeScan('');
      expect((s.get()['tombstones'] as Map)['scans'], {'ghost': iso(t0)});
    });

    test('90일 지난 묘비는 다음에 쓸 때 버린다 · 읽을 수 없는 시각도', () {
      var clock = t0;
      final s = Store(storage: MemoryStorage())..now = () => clock;
      s.replaceState({
        'tombstones': {'scans': {'junk': 'not a date'}},
      });
      s.removeScan('a');
      clock = t0.add(const Duration(days: 80));
      s.removeScan('b');
      var m = (s.get()['tombstones'] as Map)['scans'] as Map;
      expect(m.keys, ['a', 'b'], reason: '80일은 아직입니다 · 깨진 시각은 버립니다');
      clock = t0.add(const Duration(days: 100));
      s.removeScan('c');
      m = (s.get()['tombstones'] as Map)['scans'] as Map;
      expect(m.keys, ['b', 'c']);
      expect(m['c'], iso(t0.add(const Duration(days: 100))));
    });

    test('tombstones 칸이 통째로 없어도 (옛 백업) 쓴다', () {
      final s = make();
      s.replaceState({'scans': []});
      (s.get()).remove('tombstones');
      s.removeScan('x');
      expect((s.get()['tombstones'] as Map)['scans'], {'x': iso(t0)});
    });
  });

  test('내보낸 것을 다시 들이면 기록과 묘비가 같은 모양이다', () {
    final a = make();
    a.setScheduleLog(today, 'gym', gymLog);
    a.setScheduleLog(today, 'cardio', {'kind': 'walk', 'minutes': 30});
    a.addScan({'id': 's1', 'weightKg': 70.0, 'measuredAt': '2026-09-01T00:00:00.000Z'});
    a.removeScan('s1');
    final text = a.exportJSON();

    final b = make();
    b.importJSON(text);
    expect(b.scheduleDay(today), a.scheduleDay(today));
    expect(b.get()['tombstones'], a.get()['tombstones']);
    expect(b.exportJSON(), text);
  });

  test('옛 백업(새 칸 없음)을 들이면 새 칸이 빈 채로 생긴다', () {
    final s = make();
    final old = jsonEncode({
      'version': storeVersion,
      'schedule': {yesterday: {'plan': ['gym'], 'done': {}}},
    });
    s.importJSON(old);
    expect(s.get()['tombstones'], {'scans': {}, 'foodLogs': {}});
    expect(s.scheduleDay(yesterday), {'plan': ['gym'], 'done': {}});
  });
}
