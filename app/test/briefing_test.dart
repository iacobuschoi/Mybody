/* =============================================================================
 * briefing_test.dart — 홈 맨 위 「오늘 브리핑」 이 시각과 상태에 맞는 말을 하는가
 *
 * 규칙은 lib/src/briefing.dart 머리에 있습니다. 여기서는 시계를 세워 두고
 * (store.now — 브리핑과 저장소가 같은 "오늘" 을 봅니다) 아침 8시 · 저녁 6시 ·
 * 밤 9시 반을 하나씩 봅니다.
 *
 * 요일은 박아 두지 않습니다. 플랜의 분할표에서 운동 날과 쉬는 날을 찾습니다 —
 * 엔진의 분할이 바뀌면 요일을 박은 시험은 거짓으로 깨집니다.
 * ========================================================================== */
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mybody/src/api.dart';
import 'package:mybody/src/app_state.dart';
import 'package:mybody/src/briefing.dart';
import 'package:mybody/src/scope.dart';
import 'package:mybody/src/screens/home.dart';
import 'package:mybody/src/screens/progress.dart';
import 'package:mybody/src/theme.dart';
import 'package:mybody/src/ui/charts.dart';
import 'package:mybody/src/ui/widgets.dart';
import 'package:mybody_core/mybody_core.dart' as core;
import 'package:shared_preferences/shared_preferences.dart';

const _scan = {
  'id': 's1', 'weightKg': 86.7, 'smmKg': 38.0, 'bfmKg': 20.0,
  'pbfPct': 23.1, 'ffmKg': 66.7, 'bmi': 24.8, 'bmrKcal': 1810,
  'measuredAt': '2026-03-01T00:00:00.000Z',
};
const _scan2 = {
  'id': 's2', 'weightKg': 84.4, 'smmKg': 38.6, 'bfmKg': 17.5,
  'pbfPct': 20.7, 'measuredAt': '2026-05-20T00:00:00.000Z',
};
const _profile = {
  'sex': 'male', 'age': 22, 'heightCm': 187, 'activityLevel': 'moderate',
  'trainingAge': 'novice', 'daysPerWeek': 4, 'mealsPerDay': 3,
};

/// 시험이 사는 주의 월요일. 계획은 그 2주 전 월요일에 시작한 것으로 둡니다 —
/// 체크인 주(계획 주)가 오늘을 포함해야 "이번 주 체크인" 판정이 됩니다.
final DateTime _monday = DateTime(2026, 9, 21);
const _planStart = '2026-09-07';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<AppState> seeded({bool withPlan = true, bool withScan = true, bool twoScans = false}) async {
    SharedPreferences.setMockInitialValues({});
    final app = await AppState.boot();
    app.store.set({'profile': _profile, 'onboarded': true});
    if (withScan) app.store.addScan({..._scan});
    if (twoScans) app.store.addScan({..._scan2});
    if (withPlan) {
      final goal = {'weightKg': 80.5, 'smmKg': 39.0, 'bfmKg': 12.0};
      final cmp = core.compareLevels({..._scan}, _profile, goal, '2026-03-01', null, null);
      final plan = core.buildPlan(cmp, 'mid', {..._scan}, _profile)!;
      plan['startDate'] = _planStart;
      app.store.setGoal(goal);
      app.store.setPlan(plan);
    }
    return app;
  }

  /// 시계를 세웁니다 — 브리핑(now)과 저장소(dayKey · 체크인 주)가 같은 날을 봅니다.
  void clock(AppState app, DateTime at) => app.store.now = () => at;

  DateTime at(int dow, int hour, [int minute = 0]) =>
      DateTime(_monday.year, _monday.month, _monday.day + dow, hour, minute);

  String iso(DateTime d) => d.toUtc().toIso8601String();

  List<Map> sessionsOf(AppState app) =>
      (((app.state['plan'] as Map)['workout'] as Map)['sessions'] as List).cast<Map>();

  /// 플랜의 첫 운동 날 — (요일 월=0, 이름).
  (int, String) gymDay(AppState app) {
    final s = sessionsOf(app);
    for (var i = 0; i < 7; i++) {
      if (s[i]['rest'] != true) return (i, '${s[i]['label']}');
    }
    throw StateError('운동 날이 없는 분할');
  }

  /// 플랜의 첫 쉬는 날. 없으면 null.
  int? restDay(AppState app) {
    final s = sessionsOf(app);
    for (var i = 0; i < 7; i++) {
      if (s[i]['rest'] == true) return i;
    }
    return null;
  }

  List<String> labels(List<BriefAction> a) => [for (final x in a) x.label];
  List<String> texts(Briefing b) => [for (final l in b.lines) l.text];

  Api api() {
    final a = Api(
        baseUrl: '', client: MockClient((_) async => http.Response('{"ok":false}', 404)));
    a.setToken('tok');
    return a;
  }

  Widget host(AppState app, Widget child) => Scope(
        state: app,
        api: api(),
        onServerChange: (_) async {},
        child: MaterialApp(theme: mbLight(), home: child),
      );

  test('끼니 경계 — 11시 전 아침, 15시 전 점심, 17시 전 간식, 그 뒤는 저녁', () {
    expect(mealNow(0), '아침');
    expect(mealNow(10), '아침');
    expect(mealNow(11), '점심');
    expect(mealNow(14), '점심');
    expect(mealNow(15), '간식');
    expect(mealNow(16), '간식');
    expect(mealNow(17), '저녁');
    expect(mealNow(23), '저녁');
  });

  test('아침 8시 · 헬스 날 · 아무것도 안 함 → 머리글은 운동 이름, 주 버튼은 아침 기록', () async {
    final app = await seeded();
    final (dow, label) = gymDay(app);
    final now = at(dow, 8);
    clock(app, now);
    final key = app.store.dayKey(now);
    app.store.setSchedulePlan(key, 'gym', true);

    final b = buildBriefing(app, now: now);
    expect(b.headline, '오늘은 $label 하는 날');
    expect(texts(b), anyElement(startsWith('오늘은 $label 하는 날 · ')));
    expect(texts(b), anyElement(contains('아침 기록할 시간')));
    expect(texts(b), contains('이번 주 체크인 아직'));
    /* 15시 전엔 밥부터. 운동과 체크인은 보조 버튼 — 둘까지. */
    expect(b.primary?.label, '아침 기록');
    expect(b.primary?.route, 'food');
    expect(labels(b.secondary), ['이번 주 체크인', '운동 시작']);
    expect(b.allDone, isFalse);
  });

  test('아침에 아침을 적었으면 체크인이 주 버튼 (12시 전)', () async {
    final app = await seeded();
    final (dow, _) = gymDay(app);
    final now = at(dow, 9, 30);
    clock(app, now);
    final key = app.store.dayKey(now);
    app.store.setSchedulePlan(key, 'gym', true);
    app.store.addFoodLog({'date': key, 'meal': '아침',
        'items': [{'name': '계란', 'kcal': 150, 'p': 12, 'c': 1, 'f': 10}]});

    final b = buildBriefing(app, now: now);
    expect(b.primary?.label, '이번 주 체크인');
    expect(b.primary?.route, 'checkin');
    expect(labels(b.secondary), ['운동 시작']);
    expect(texts(b), anyElement(contains('아침 적었어요')));
  });

  test('저녁 6시 · 헬스 안 함 → 주 버튼 「운동 시작」 → workout {date, type: gym}', () async {
    final app = await seeded();
    final (dow, label) = gymDay(app);
    final now = at(dow, 18);
    clock(app, now);
    final key = app.store.dayKey(now);
    app.store.setSchedulePlan(key, 'gym', true);

    final b = buildBriefing(app, now: now);
    expect(b.headline, '오늘은 $label 하는 날');
    expect(b.primary?.label, '운동 시작');
    expect(b.primary?.route, 'workout');
    expect(b.primary?.arg, {'date': key, 'type': 'gym'});
    /* 저녁은 아직 안 적었고 체크인도 아직 — 오후라 둘 다 보조. */
    expect(labels(b.secondary), ['저녁 기록', '이번 주 체크인']);
  });

  test('밤 9시 반 · 헬스 안 함 → 「15분 맨몸 운동」 → type: bodyweight', () async {
    final app = await seeded();
    final (dow, _) = gymDay(app);
    final now = at(dow, 21, 30);
    clock(app, now);
    final key = app.store.dayKey(now);
    app.store.setSchedulePlan(key, 'gym', true);

    final b = buildBriefing(app, now: now);
    expect(b.primary?.label, '15분 맨몸 운동');
    expect(b.primary?.route, 'workout');
    expect(b.primary?.arg, {'date': key, 'type': 'bodyweight'});
  });

  test('유산소 회당 분 — 적어 둔 날이 하루뿐이어도 주 분량을 통째로 주지 않는다', () {
    /* 주 96분(a=0.2)을 유산소 한 날에 다 몰면 96분 — 엔진 처방은 "40분 × 2회" 입니다. */
    expect(cardioSessionMinutes(96, 1), 48);
    expect(cardioSessionMinutes(96, 2), 48);
    /* 날을 더 적어 두면 그만큼 나눕니다. */
    expect(cardioSessionMinutes(96, 4), 24);
    /* 120분부터 3회, 180분부터 6회(Z2 4 + HIIT 2). */
    expect(cardioSessionMinutes(150, 1), 50);
    expect(cardioSessionMinutes(240, 1), 40);
    expect(cardioSessionMinutes(0, 1), isNull);
  });

  test('유산소 — 헬스가 주 버튼이면 보조, 헬스를 마쳤으면 주 버튼', () async {
    final app = await seeded();
    final (dow, label) = gymDay(app);
    final now = at(dow, 17);
    clock(app, now);
    final key = app.store.dayKey(now);
    app.store.setSchedulePlan(key, 'gym', true);
    app.store.setSchedulePlan(key, 'cardio', true);

    var b = buildBriefing(app, now: now);
    expect(b.primary?.label, '운동 시작');
    expect(labels(b.secondary).first, '유산소 시작');
    expect(b.secondary.first.arg, {'date': key, 'type': 'cardio'});
    /* 한 줄에 접습니다 — "오늘은 하체 A 하는 날 · 60분 · 유산소 N분". */
    expect(texts(b), anyElement(allOf(startsWith('오늘은 $label 하는 날'), contains('유산소'))));

    app.store.setScheduleDone(key, 'gym', true);
    b = buildBriefing(app, now: now);
    expect(b.headline, '유산소만 남았어요');
    expect(b.primary?.label, '유산소 시작');
    expect(b.lines.first.text, '$label 완료');
    expect(b.lines.first.done, isTrue);
    expect(b.lines.first.icon, 'done');
  });

  /// 그 날의 끼니 하나를 적습니다.
  void eat(AppState app, String key, String meal) => app.store.addFoodLog({
        'date': key, 'meal': meal,
        'items': [{'name': '닭가슴살', 'kcal': 300, 'p': 40, 'c': 0, 'f': 5}],
      });

  test('다 했으면 「오늘 할 일 끝」 · 내일 운동 · 주 버튼 없음', () async {
    final app = await seeded();
    final (dow, label) = gymDay(app);
    final now = at(dow, 18);
    clock(app, now);
    final key = app.store.dayKey(now);
    app.store.setSchedulePlan(key, 'gym', true);
    app.store.setScheduleDone(key, 'gym', true);
    /* 끝이려면 저녁뿐 아니라 지나간 아침 · 점심도 적혀 있어야 합니다. */
    for (final m in ['아침', '점심', '저녁']) {
      eat(app, key, m);
    }
    app.store.set({'checkins': [{'at': iso(now), 'weightKg': 85.0}]});

    final b = buildBriefing(app, now: now);
    expect(b.headline, '오늘 할 일 끝');
    expect(b.allDone, isTrue);
    expect(b.primary, isNull);
    expect(b.secondary, isEmpty);
    expect(b.sub, startsWith('내일은 '));
    expect(b.lines.first.text, '$label 완료');
    expect(texts(b), anyElement(contains('저녁 적었어요')));
    expect(texts(b), isNot(contains('이번 주 체크인 아직')));
    /* 스트릭은 어제도 지켰을 때부터 — 하루로 "1일 연속" 은 축하가 아닙니다. */
    expect(b.celebrate, isNull);
    final yesterday = app.store.dayKey(at(dow - 1, 12));
    app.store.setSchedulePlan(yesterday, 'gym', true);
    app.store.setScheduleDone(yesterday, 'gym', true);
    expect(buildBriefing(app, now: now).celebrate, '운동 2일 연속');
  });

  test('끼니 경계 — 이 시각까지 적었어야 할 끼니', () {
    expect(mealsDueBy(8), isEmpty);
    expect(mealsDueBy(10), isEmpty);
    expect(mealsDueBy(11), ['아침']);
    expect(mealsDueBy(14), ['아침']);
    expect(mealsDueBy(15), ['아침', '점심']);
    expect(mealsDueBy(19), ['아침', '점심']);
    expect(mealsDueBy(20), ['아침', '점심', '저녁']);
    expect(mealsDueBy(23), ['아침', '점심', '저녁']);
  });

  /* 저녁을 적었어도 점심이 비어 있으면 끝이 아닙니다 — 있는 것을 다 했다고 하지 않습니다. */
  test('지나간 끼니가 비어 있으면 「끝」 이 아니라 그 끼니를 묻는다', () async {
    final app = await seeded();
    final (dow, _) = gymDay(app);
    final now = at(dow, 18);
    clock(app, now);
    final key = app.store.dayKey(now);
    app.store.setSchedulePlan(key, 'gym', true);
    app.store.setScheduleDone(key, 'gym', true);
    eat(app, key, '아침');
    eat(app, key, '저녁');
    app.store.set({'checkins': [{'at': iso(now), 'weightKg': 85.0}]});

    var b = buildBriefing(app, now: now);
    expect(b.headline, '점심 아직 안 적었어요');
    expect(b.allDone, isFalse);
    expect(b.primary?.label, '점심 기록');
    expect(b.primary?.route, 'food');
    expect(b.secondary, isEmpty);

    /* 점심까지 적으면 끝. */
    eat(app, key, '점심');
    b = buildBriefing(app, now: now);
    expect(b.headline, '오늘 할 일 끝');
    expect(b.allDone, isTrue);
    expect(b.primary, isNull);
  });

  test('정오 · 다 했는데 아침이 비어 있으면 「아침 아직 안 적었어요」, 10시엔 아직 안 묻는다', () async {
    final app = await seeded();
    final rest = restDay(app) ?? 0;
    final key = app.store.dayKey(at(rest, 12));
    if (restDay(app) == null) {
      app.store.setSchedulePlan(key, 'gym', true);
      app.store.setScheduleDone(key, 'gym', true);
    }
    eat(app, key, '점심');
    app.store.set({'checkins': [{'at': iso(at(rest, 9)), 'weightKg': 85.0}]});

    clock(app, at(rest, 12));
    var b = buildBriefing(app, now: at(rest, 12));
    expect(b.headline, '아침 아직 안 적었어요');
    expect(b.allDone, isFalse);
    expect(b.primary?.label, '아침 기록');

    /* 10시에는 아직 아침 시간 — 점심을 적었어도 아침 기록할 시간이 주 버튼. */
    clock(app, at(rest, 10));
    b = buildBriefing(app, now: at(rest, 10));
    expect(b.headline, '아침 기록할 시간');
    expect(b.allDone, isFalse);
  });

  /* 15~17시는 간식 시간 — 오늘 몫을 다 했어도 저녁이 남았으니 「끝」 이 아닙니다. */
  test('16시 쉬는 날 · 다 했어도 「저녁까지 쉬어요」, 끝이 아니다', () async {
    final app = await seeded();
    final rest = restDay(app) ?? 0;
    final now = at(rest, 16);
    clock(app, now);
    final key = app.store.dayKey(now);
    if (restDay(app) == null) {
      app.store.setSchedulePlan(key, 'gym', true);
      app.store.setScheduleDone(key, 'gym', true);
    }
    eat(app, key, '아침');
    eat(app, key, '점심');
    app.store.set({'checkins': [{'at': iso(now), 'weightKg': 85.0}]});

    final b = buildBriefing(app, now: now);
    expect(b.headline, '저녁까지 쉬어요');
    expect(b.headline, isNot('오늘 할 일 끝'));
    expect(b.allDone, isFalse);
    expect(b.sub, startsWith('남은 '));
    expect(b.sub, contains('kcal'));
    expect(b.primary, isNull);
    expect(b.secondary, isEmpty);
    expect(texts(b), isNot(anyElement(contains('기록할 시간'))), reason: '간식은 의무가 아닙니다');

    /* 16시에 아무것도 안 적었으면 — 끝도, 쉬어요도 아니라 빈 끼니를 묻습니다. */
    final app2 = await seeded();
    clock(app2, now);
    if (restDay(app2) == null) {
      app2.store.setSchedulePlan(key, 'gym', true);
      app2.store.setScheduleDone(key, 'gym', true);
    }
    app2.store.set({'checkins': [{'at': iso(now), 'weightKg': 85.0}]});
    final b2 = buildBriefing(app2, now: now);
    expect(b2.headline, '아침 · 점심 아직 안 적었어요');
    expect(b2.allDone, isFalse);
    expect(b2.primary?.label, '아침 기록');
  });

  test('밤에 맨몸 운동으로 체크했으면 완료 줄은 분할 이름이 아니라 「맨몸 운동 완료」', () async {
    final app = await seeded();
    final (dow, label) = gymDay(app);
    final now = at(dow, 22);
    clock(app, now);
    final key = app.store.dayKey(now);
    app.store.setSchedulePlan(key, 'gym', true);
    app.store.setScheduleLog(key, 'gym', {'kind': 'bodyweight', 'minutes': 15, 'kcal': 90});
    final b = buildBriefing(app, now: now);
    expect(b.lines.first.text, '맨몸 운동 완료 · 15분 · 약 90kcal');
    expect(b.lines.first.text, isNot(contains(label)));
    expect(b.lines.first.done, isTrue);
    expect(b.lines.first.icon, 'done');

    /* 헬스장에서 한 기록은 분할 이름 그대로. */
    app.store.setScheduleLog(key, 'gym', {'kind': 'gym', 'minutes': 58, 'kcal': 410});
    expect(buildBriefing(app, now: now).lines.first.text, '$label 완료 · 58분 · 약 410kcal');
  });

  /* 규칙 3 — 체크인 주도 브리핑이 받은 now 의 날짜에서 셉니다. 저장소의 시계가 다른
     날을 가리켜도 "이번 주" 는 now 의 주입니다. */
  test('체크인 주는 저장소 시계가 아니라 now 의 날짜로 센다', () async {
    final app = await seeded();
    final (dow, _) = gymDay(app);
    final thisWeek = at(dow, 9);
    final nextWeek = at(dow + 14, 9);
    app.store.set({'checkins': [{'at': iso(thisWeek), 'weightKg': 85.0}]});

    clock(app, thisWeek);
    expect(texts(buildBriefing(app, now: thisWeek)), isNot(contains('이번 주 체크인 아직')));
    /* 저장소 시계는 그대로 이번 주 — now 만 두 주 뒤 */
    expect(texts(buildBriefing(app, now: nextWeek)), contains('이번 주 체크인 아직'));
    expect(checkinOfDay(app.store, app.store.dayKey(thisWeek)), isNotNull);
    expect(checkinOfDay(app.store, app.store.dayKey(nextWeek)), isNull);

    /* 반대로 — 저장소 시계는 두 주 뒤인데 now 는 체크인한 그 주 */
    clock(app, nextWeek);
    expect(texts(buildBriefing(app, now: thisWeek)), isNot(contains('이번 주 체크인 아직')));
  });

  test('운동 기록이 있으면 분 · kcal 를 붙인다 — 일정 칸의 log 를 방어적으로 읽음', () async {
    final app = await seeded();
    final (dow, label) = gymDay(app);
    final now = at(dow, 20);
    clock(app, now);
    final key = app.store.dayKey(now);
    app.store.set({'schedule': {
      key: {
        'plan': ['gym'],
        'done': {'gym': iso(now)},
        'log': {'gym': {'kind': 'gym', 'minutes': 58, 'kcal': 410}},
      },
    }});
    final b = buildBriefing(app, now: now);
    expect(b.lines.first.text, '$label 완료 · 58분 · 약 410kcal');
  });

  test('쉬는 날 → 단백질 챙기기 · 운동 버튼 없음', () async {
    final app = await seeded();
    final rest = restDay(app);
    if (rest == null) return;                         // 매일 운동하는 분할이면 볼 것이 없습니다
    final now = at(rest, 13);
    clock(app, now);
    final macros = ((app.state['plan'] as Map)['macros'] as Map);
    final b = buildBriefing(app, now: now);
    expect(b.lines.first.icon, 'rest');
    expect(b.lines.first.text, '오늘은 쉬는 날 — 단백질 ${core.jsNumToString(core.jsRound(core.jsToNumber(macros['proteinG'])))}g 챙기기');
    expect(b.headline, '점심 기록할 시간');
    expect(b.primary?.label, '점심 기록');
    expect(labels(b.secondary), isNot(contains('운동 시작')));
  });

  test('일정 칸이 비어 있으면 플랜의 분할표대로 — 첫 주에 매일 "쉬는 날" 이라고 하지 않는다', () async {
    final app = await seeded();
    final (dow, label) = gymDay(app);
    final now = at(dow, 16);
    clock(app, now);
    final b = buildBriefing(app, now: now);
    expect(b.headline, '오늘은 $label 하는 날');
    expect(b.primary?.label, '운동 시작');
  });

  test('계획 없음 → "계획이 아직 없어요" 와 목표 정하기; 다 적었으면 목표가 주 버튼', () async {
    final app = await seeded(withPlan: false);
    final now = at(1, 13);
    clock(app, now);
    final key = app.store.dayKey(now);

    var b = buildBriefing(app, now: now);
    expect(texts(b), contains('운동 계획이 아직 없어요'));
    expect(texts(b), contains('식단 목표는 계획을 세우면 나옵니다'));
    expect(texts(b), isNot(contains('이번 주 체크인 아직')));   // 계획 없이는 체크인도 없습니다
    expect(b.headline, '점심 기록할 시간');
    expect(b.primary?.label, '점심 기록');
    expect(labels(b.secondary), ['목표 정하기']);
    expect(b.sub, isNotNull);

    app.store.addFoodLog({'date': key, 'meal': '점심',
        'items': [{'name': '김밥', 'kcal': 500, 'p': 15, 'c': 70, 'f': 15}]});
    b = buildBriefing(app, now: now);
    expect(b.headline, isNot('오늘 할 일 끝'));       // 계획이 없는데 "끝" 은 거짓말입니다
    expect(b.primary?.label, '목표 정하기');
    expect(b.primary?.route, 'goal');
  });

  test('넘게 먹었으면 「넘었어요」 — 음수 남은 양은 안 찍는다', () async {
    final app = await seeded();
    final rest = restDay(app) ?? 0;
    final now = at(rest, 13);
    clock(app, now);
    final key = app.store.dayKey(now);
    app.store.addFoodLog({'date': key, 'meal': '점심',
        'items': [{'name': '뷔페', 'kcal': 5000, 'p': 100, 'c': 500, 'f': 200}]});
    final b = buildBriefing(app, now: now);
    final food = texts(b).firstWhere((s) => s.contains('kcal'));
    expect(food, contains('넘었어요'));
    expect(food, contains('저녁은 가볍게'));
    expect(food, contains('점심 적었어요'));
    expect(food, isNot(contains('남은')));
    expect(food, isNot(contains('-')));
  });

  test('인바디 없음 → 인바디 올리기; 일정에 헬스가 있으면 그 줄은 보여 준다', () async {
    final app = await seeded(withPlan: false, withScan: false);
    final now = at(2, 18);
    clock(app, now);
    final key = app.store.dayKey(now);
    app.store.setSchedulePlan(key, 'gym', true);

    final b = buildBriefing(app, now: now);
    expect(b.headline, '인바디 결과지를 올려주세요');
    expect(b.primary?.label, '인바디 올리기');
    expect(b.primary?.route, 'upload');
    expect(b.lines.first.icon, 'scan');
    expect(b.lines.first.text, '사진 한 장이면 오늘 할 일이 나옵니다');
    expect(texts(b), contains('오늘은 헬스 하는 날'));
    expect(labels(b.secondary), ['운동 시작']);
    /* 계획도 목표도 없으니 식단 · 체크인 줄은 없습니다 */
    expect(texts(b).where((s) => s.contains('kcal')), isEmpty);
    expect(texts(b), isNot(contains('이번 주 체크인 아직')));
  });

  /* --- 화면 ------------------------------------------------------------------ */

  testWidgets('홈 — 브리핑 카드가 맨 위, 주 버튼이 보이고 셸로 workout 을 부른다', (t) async {
    t.view.physicalSize = const Size(1000, 5000);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final app = await seeded(twoScans: true);
    final (dow, label) = gymDay(app);
    final now = at(dow, 18);
    clock(app, now);
    final key = app.store.dayKey(now);
    app.store.setSchedulePlan(key, 'gym', true);

    final calls = <(String, Object?)>[];
    void go(String route, [Object? arg]) => calls.add((route, arg));
    await t.pumpWidget(host(app, Scaffold(body: HomeScreen(go: go))));
    await t.pump(const Duration(milliseconds: 200));
    expect(t.takeException(), isNull);

    expect(find.byType(BriefingCard), findsOneWidget);
    /* 첫 카드가 브리핑입니다 — 위치로도, 순서로도. */
    final firstCard = find.byType(MbCard).evaluate().first.widget;
    final briefCard = find
        .descendant(of: find.byType(BriefingCard), matching: find.byType(MbCard))
        .evaluate()
        .single
        .widget;
    expect(identical(firstCard, briefCard), isTrue);
    expect(t.getTopLeft(find.byType(BriefingCard)).dy,
        lessThan(t.getTopLeft(find.text('최신 인바디')).dy));

    expect(find.text('오늘은 $label 하는 날'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '운동 시작'), findsOneWidget);
    /* 같은 버튼이 한 화면에 둘이면 안 됩니다 — 체크인은 브리핑에만. */
    expect(find.text('이번 주 체크인'), findsOneWidget);
    expect(find.text('목표 정하기'), findsNothing);

    await t.tap(find.widgetWithText(FilledButton, '운동 시작'));
    await t.pump();
    expect(calls, hasLength(1));
    expect(calls.single.$1, 'workout');
    expect(calls.single.$2, {'date': key, 'type': 'gym'});

    /* 이번 주 카드의 오늘 줄 — 종목 이름으로 같은 화면에 갑니다. 글자는 다릅니다
       (「운동 시작」 이 화면에 둘이면 안 됩니다). */
    expect(find.text('헬스 했어요'), findsNothing);
    await t.tap(find.widgetWithText(OutlinedButton, '헬스 하러 가기'));
    await t.pump();
    expect(calls, hasLength(2));
    expect(calls.last.$1, 'workout');
    expect(calls.last.$2, {'date': key, 'type': 'gym'});

    /* 「그냥 체크만」 — 화면 없이 오늘 헬스를 체크. 브리핑이 곧바로 완료를 말합니다. */
    await t.tap(find.widgetWithText(TextButton, '그냥 체크만'));
    await t.pump();
    expect(core.jsTruthy((app.store.scheduleDay(key)['done'] as Map)['gym']), isTrue);
    expect(find.text('$label 완료'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '운동 시작'), findsNothing);
    expect(find.text('그냥 체크만'), findsNothing);
  });

  testWidgets('홈 — 360px 폭에서도 잘리지 않는다', (t) async {
    t.view.physicalSize = const Size(360, 1600);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final app = await seeded();
    final (dow, _) = gymDay(app);
    final now = at(dow, 18);
    clock(app, now);
    app.store.setSchedulePlan(app.store.dayKey(now), 'gym', true);
    app.store.setSchedulePlan(app.store.dayKey(now), 'cardio', true);
    await t.pumpWidget(host(app, Scaffold(body: HomeScreen(go: (_, [__]) {}))));
    await t.pump(const Duration(milliseconds: 200));
    expect(t.takeException(), isNull);
    expect(find.byType(ErrorWidget), findsNothing);
    expect(find.widgetWithText(FilledButton, '운동 시작'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '유산소 시작'), findsOneWidget);
  });

  testWidgets('홈 — 인바디 없음: 브리핑이 올리기 버튼 하나만 든다', (t) async {
    t.view.physicalSize = const Size(1000, 3000);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final app = await seeded(withPlan: false, withScan: false);
    await t.pumpWidget(host(app, Scaffold(body: HomeScreen(go: (_, [__]) {}))));
    await t.pump(const Duration(milliseconds: 200));
    expect(t.takeException(), isNull);
    expect(find.byType(BriefingCard), findsOneWidget);
    expect(find.text('인바디 결과지를 올려주세요'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '인바디 올리기'), findsOneWidget);
    expect(find.text('이번 주 운동'), findsOneWidget);
  });

  testWidgets('추이 — 체중 · 골격근 · 체지방률 카드 셋, 그래프 셋', (t) async {
    t.view.physicalSize = const Size(1000, 4200);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final app = await seeded(twoScans: true);
    await t.pumpWidget(host(app, Scaffold(body: ProgressScreen(go: (_, [__]) {}))));
    await t.pump(const Duration(milliseconds: 200));
    expect(t.takeException(), isNull);

    expect(find.widgetWithText(SectionTitle, '체중'), findsOneWidget);
    expect(find.widgetWithText(SectionTitle, '골격근'), findsOneWidget);
    expect(find.widgetWithText(SectionTitle, '체지방률'), findsOneWidget);
    expect(find.byType(LineChart), findsNWidgets(3));
    expect(find.text('체중 · 골격근 · 체지방'), findsNothing);
    /* 제목 옆에 처음 → 지금 (n1) */
    expect(find.text('86.7 → 84.4 kg · −2.3'), findsOneWidget);
    expect(find.text('23.1 → 20.7 % · −2.4'), findsOneWidget);
    /* 골격근 +0.6 은 오차 폭(0.6kg) 의 정확히 경계 — 별표 없음. 위 카드의
       '38.0 → 38.6 kg' 행과는 다른 글자입니다(그쪽엔 차이가 따로 붙습니다). */
    expect(find.text('38.0 → 38.6 kg · +0.6'), findsOneWidget);
    /* 노이즈 규칙 문장은 그대로 위에 */
    expect(find.text('처음부터 지금까지'), findsOneWidget);
  });
}
