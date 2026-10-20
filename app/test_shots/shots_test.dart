/* =============================================================================
 * test_shots/shots_test.dart — 스토어 스크린샷을 앱 위젯으로 직접 그려 뽑기
 *
 *   cd app && flutter test test_shots/            (test/ 와 따로 — CI 는 안 돕니다)
 *
 * 에뮬레이터 없이, 지금 코드 그대로, 실제 글꼴(Pretendard · Lucide)로 그립니다.
 * 가짜 서버 응답으로 상태를 마음대로 꾸밀 수 있어 "28일 스트릭인 친구" 같은
 * 장면을 만들 수 있습니다. 결과는 build/shots/ 의 png (1080×2400, 폰 한 화면).
 * 그다음 python3 play/make-shots.py build/shots play/그림/스크린샷.
 * ========================================================================== */
// ignore_for_file: invalid_use_of_visible_for_testing_member, depend_on_referenced_packages

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:mybody/src/photos.dart';
import 'package:mybody/src/api.dart';
import 'package:mybody/src/app_state.dart';
import 'package:mybody/src/scope.dart';
import 'package:mybody/src/screens/goal.dart';
import 'package:mybody/src/screens/review.dart';
import 'package:mybody/src/screens/social.dart';
import 'package:mybody/src/screens/tester_welcome.dart' show markTesterWelcomeSeen;
import 'package:mybody/src/screens/upload.dart';
import 'package:mybody/src/screens/workout_history.dart';
import 'package:mybody/src/screens/workout_session.dart';
import 'package:mybody/src/screens/workout_tutorial.dart';
import 'package:mybody/src/sheet_history.dart';
import 'package:mybody/src/shell.dart';
import 'package:mybody/src/theme.dart';
import 'package:mybody/src/ui/edge.dart';
import 'package:mybody_core/mybody_core.dart' as core;
import 'package:shared_preferences/shared_preferences.dart';

/// 어느 폰 크기로 찍을지 — SHOT_SIZE=가로x세로(물리 픽셀). 기본은 안드로이드 흔한 폰.
///   플레이:   flutter test test_shots/                              → 1080×2400
///   앱스토어: flutter test test_shots/ --dart-define=SHOT_SIZE=1320x2868   (아이폰 6.9″)
const _sizeSpec = String.fromEnvironment('SHOT_SIZE', defaultValue: '1080x2400');
final _physical = Size(double.parse(_sizeSpec.split('x')[0]), double.parse(_sizeSpec.split('x')[1]));
final _out = _sizeSpec == '1080x2400' ? 'build/shots' : 'build/shots-$_sizeSpec';
const _shotKey = Key('shot');

/// 시험 환경은 글꼴을 안 싣습니다 — 전부 네모로 나옵니다. 앱이 선언한 글꼴
/// (FontManifest.json: Pretendard · Roboto 조각 · 패키지 아이콘 글꼴)을 그대로 싣습니다.
Future<void> loadAppFonts() async {
  final manifest = jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
  for (final entry in manifest) {
    final m = (entry as Map).cast<String, dynamic>();
    final loader = FontLoader(m['family'] as String);
    for (final f in (m['fonts'] as List)) {
      loader.addFont(rootBundle.load((f as Map)['asset'] as String));
    }
    try {
      await loader.load();
    } catch (_) {
      // MaterialIcons 처럼 시험 묶음에 없는 것은 건너뜁니다.
    }
  }
}

http.Response _json(Object body) => http.Response.bytes(
    utf8.encode(jsonEncode(body)), 200,
    headers: {'content-type': 'application/json; charset=utf-8'});

void restore() {
  debugDisableShadows = true;
  debugDefaultTargetPlatformOverride = null;
}

/// 사진 고르기를 가짜로: 무엇을 누르든 이 파일을 고른 것으로 칩니다.
class _FakePicker extends ImagePickerPlatform {
  _FakePicker(this.path);
  final String path;
  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async => XFile(path);
}

/// 가짜 결과지 그림(실제 사람의 결과지가 아닙니다 — play/make-demo-sheet.py 가 그립니다).
/// 없으면 사진 없이 찍습니다.
const _sheet = 'test_shots/demo-sheet.png';

/// 아이폰 크기로 찍을 때는 화면도 iOS 로 그립니다(스크롤 · 「테스트 기간」 문구 등).
final _ios = _sizeSpec != '1080x2400';

Future<void> shot(WidgetTester t, String name) async {
  final boundary = t.renderObject<RenderRepaintBoundary>(find.byKey(_shotKey));
  final image = await t.runAsync(() => boundary.toImage(pixelRatio: 3.0));
  final bytes = await t.runAsync(() => image!.toByteData(format: ui.ImageByteFormat.png));
  Directory(_out).createSync(recursive: true);
  File('$_out/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
}

Widget host(AppState app, Api api, Widget child) => RepaintBoundary(
      key: _shotKey,
      child: Scope(
        state: app,
        api: api,
        onServerChange: (_) async {},
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: mbLight(),
          builder: edgeSafe,
          home: child,
        ),
      ),
    );

void phone(WidgetTester t) {
  /* 시험 환경은 그림자를 검은 테두리로 그립니다(골든을 결정적으로 만들려고).
     스크린샷엔 진짜 그림자가 필요합니다. 시험이 끝날 때는 되돌려야 합니다 —
     틀이 "디버그 변수를 바꿨다" 고 막습니다. 그래서 각 시험 끝에 restore(). */
  debugDisableShadows = false;
  if (_ios) debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  // 흔한 폰: 1080×2400, 배율 3 → 논리 360×800. 아이폰 6.9″: 1320×2868 → 논리 440×956.
  t.view.physicalSize = _physical;
  t.view.devicePixelRatio = 3.0;
  addTearDown(t.view.reset);
}

Map<String, Object?> _day(String key, String dow, int n, List<String> plan, List<String> done) => {
      'key': key, 'dow': dow, 'dayNum': n, 'plan': plan, 'done': done,
      'kept': plan.isNotEmpty && plan.every(done.contains), 'missed': false,
    };

/// 28일째 운동을 이어 가는 친구. 이번 주는 5일 계획 중 3일 끝(오늘까지).
final _mallang = <String, Object?>{
  'weekStart': '2026-09-21', 'checkedIn': true,
  'plannedDays': 5, 'keptDays': 3, 'missedDays': 0, 'openDays': 2,
  'streaks': {'workoutDays': 28, 'foodDays': 26},
  'week': {'start': '2026-09-21', 'days': [
    _day('2026-09-21', '월', 21, ['gym'], ['gym']),
    _day('2026-09-22', '화', 22, ['cardio'], ['cardio']),
    _day('2026-09-23', '수', 23, ['gym'], ['gym']),
    _day('2026-09-24', '목', 24, [], []),
    _day('2026-09-25', '금', 25, ['gym'], []),
    _day('2026-09-26', '토', 26, ['cardio'], []),
    _day('2026-09-27', '일', 27, [], []),
  ]},
  'today': {'date': '2026-09-23', 'logged': true, 'kcal': 1650, 'p': 118, 'c': 190, 'f': 48,
            'target': {'intakeKcal': 2200, 'proteinG': 150, 'carbG': 240, 'fatG': 65}},
  'weightKg': 63.2, 'dWeightKg': -0.7, 'smmKg': 27.1, 'dSmmKg': 0.3, 'bfmKg': 15.2, 'dBfmKg': -0.9,
  'progressPct': 42,
};


/// 화면이 계속 움직이면(진행 표시 등) pumpAndSettle 이 안 끝납니다 — 그때는 잠깐 기다리고 찍습니다.
Future<void> settle(WidgetTester t) async {
  try {
    await t.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 5));
  } catch (_) {
    await t.pump(const Duration(seconds: 1));
  }
}

String _k(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/* --- 스크린샷용 가짜 사람 -------------------------------------------------------
 * 스토어 스크린샷에 실제 사람의 기록이 들어가면 안 됩니다(코어의 kSeedProfile · kSeedScans 는
 * 주인의 실측입니다 — 여기서는 쓰지 않습니다). 아래는 지어낸 31세 · 176cm 남성의 석 달.
 * 숫자끼리는 맞춥니다: 체중 = 제지방 + 체지방, 제지방 = 체수분 + 단백질 + 무기질. */
const Map<String, Object?> kDemoProfile = {
  'sex': 'male', 'age': 31.0, 'heightCm': 176.0, 'activityLevel': 'moderate',
  'trainingAge': 'novice', 'daysPerWeek': 4.0, 'sessionMinutes': 60.0, 'environment': 'gym',
  'injuries': '', 'dietFlags': <Object?>[], 'mealsPerDay': 3.0, 'cookingLevel': 'simple',
  'hadPriorPeak': false,
};

/// 오늘에서 [daysAgo] 일 전 아침 8시 20분(한국) — 언제 찍어도 최근 석 달로 보이게.
String _ago(int daysAgo) {
  final d = DateTime.now().subtract(Duration(days: daysAgo));
  return '${_k(d)}T08:20:00+09:00';
}

/// 가장 최근 결과지 한 장(모든 칸) — 홈 · 검수 화면이 씁니다.
Map<String, Object?> demoSheet(String measuredAt) => {
      'id': 'demo-sheet', 'measuredAt': measuredAt, 'source': 'sheet', 'device': 'InBody270',
      'partial': false,
      'weightKg': 74.3, 'weightRange': [57.4, 77.6],
      'smmKg': 32.3, 'bfmKg': 14.8, 'bfmRange': [7.4, 14.8], 'pbfPct': 19.9,
      'ffmKg': 59.5, 'ffmRange': [52.0, 63.6],
      'tbwL': 43.6, 'tbwRange': [38.2, 46.6], 'proteinKg': 11.8, 'proteinRange': [10.2, 12.5],
      'mineralKg': 4.1, 'mineralRange': [3.5, 4.3],
      'bmi': 24.0, 'inbodyScore': 78.0, 'idealWeightKg': 68.1, 'weightControlKg': -6.2,
      'fatControlKg': -5.1, 'muscleControlKg': 0.0, 'bmiGrade': '표준', 'pbfGrade': '표준',
      'whr': 0.88, 'visceralFatLevel': 6.0, 'bmrKcal': 1655.0, 'bmrRange': [1520.0, 1780.0],
      'obesityDegreePct': 109.0, 'recommendedIntakeKcal': 2480.0,
    };

/// 석 달 전 · 여섯 주 전(결과지 아래 그래프에서 읽은 지난 측정) + 사흘 전 결과지.
List<Map<String, Object?>> demoScans() => [
      {'id': 'demo-1', 'measuredAt': _ago(84), 'source': 'chart', 'device': 'InBody270',
       'weightKg': 78.6, 'smmKg': 31.2, 'pbfPct': 24.8, 'bfmKg': 19.5, 'ffmKg': 59.1, 'partial': true},
      {'id': 'demo-2', 'measuredAt': _ago(42), 'source': 'chart', 'device': 'InBody270',
       'weightKg': 76.1, 'smmKg': 31.8, 'pbfPct': 22.0, 'bfmKg': 16.7, 'ffmKg': 59.4, 'partial': true},
      demoSheet(_ago(3)),
    ];

/// 지난 헬스 기록 — 지난 운동 기록 화면이 읽습니다. 세트마다 무게 · 횟수(음성으로 넣은 세트는 🎤).
void seedWorkouts(AppState app) {
  Map<String, Object?> ex(String name, int of, String reps, List<List<num>> sets, {bool voice = false}) => {
        'name': name, 'sets': sets.length, 'of': of, 'reps': reps, 'restSec': 120, 'kg': sets.last[0],
        'setLog': [for (final s in sets) {'kg': s[0], 'reps': s[1], if (voice) 'src': 'voice'}],
      };
  final now = DateTime.now();
  final days = <int, List<Map<String, Object?>>>{
    9: [ex('바벨 벤치프레스', 3, '8-12', [[60, 10], [62.5, 8], [62.5, 8]]),
        ex('랫 풀다운', 3, '10-12', [[45, 12], [50, 10], [50, 10]])],
    6: [ex('바벨 백스쿼트', 3, '8-10', [[70, 10], [75, 8], [75, 8]]),
        ex('루마니안 데드리프트', 3, '8-10', [[60, 10], [60, 10], [65, 8]])],
    4: [ex('바벨 벤치프레스', 3, '8-12', [[62.5, 10], [65, 8], [65, 8]], voice: true),
        ex('시티드 케이블 로우', 3, '10-12', [[45, 12], [50, 10], [50, 10]], voice: true),
        ex('덤벨 숄더프레스', 3, '10-12', [[14, 12], [16, 10], [16, 9]])],
    2: [ex('바벨 백스쿼트', 3, '8-10', [[75, 10], [77.5, 8], [80, 6]], voice: true),
        ex('레그 프레스', 3, '10-12', [[120, 12], [130, 10], [130, 10]], voice: true)],
  };
  days.forEach((ago, xs) {
    final d = DateTime(now.year, now.month, now.day - ago);
    final sets = xs.fold<int>(0, (n, x) => n + (x['sets'] as int));
    app.store.setScheduleLog(_k(d), 'gym', {
      'kind': 'gym', 'startedAt': DateTime(d.year, d.month, d.day, 19, 10).toUtc().toIso8601String(),
      'minutes': 48 + ago, 'seconds': (48 + ago) * 60, 'kcal': 210 + ago * 4, 'sets': sets,
      'exercises': xs,
    });
  });
}

/// 가짜 사람의 인바디 세 장 + 목표 · 계획 · 이번 주 운동 · 오늘 식단.
/// [lunch] 가 false 면 오늘은 아침만 적은 상태 — 홈 첫 장의 「점심 기록할 시간」.
Future<AppState> rich({bool lunch = true}) async {
  SharedPreferences.setMockInitialValues({});
  final app = await AppState.boot();
  app.store.set({'profile': kDemoProfile, 'scans': demoScans(), 'onboarded': true, 'disclaimerAccepted': true});
  markTesterWelcomeSeen(app);   // 스크린샷 위에 테스터 인사 시트가 덮이지 않게
  final scans = app.store.sortedScans();
  final latest = scans.last;
  final profile = ((app.state['profile'] as Map).cast<String, Object?>());
  // 지금 골격근/제지방 비율(0.543)에 맞춘 목표 — 세 값이 서로 맞고, 중 강도로 반년 안.
  final goal = <String, Object?>{'weightKg': 71.0, 'smmKg': 33.0, 'bfmKg': 11.0};
  final cmp = core.compareLevels(latest, profile, goal, '${latest['measuredAt']}'.substring(0, 10), null, null);
  final plan = core.buildPlan(cmp, 'mid', latest, profile);
  app.store.setGoal(goal);
  if (plan != null) app.store.setPlan(plan);

  final now = DateTime.now();
  final mon = DateTime(now.year, now.month, now.day - (now.weekday - 1));
  for (final off in [0, 2, 4, 5]) {
    app.store.setSchedulePlan(_k(mon.add(Duration(days: off))), off == 5 ? 'cardio' : 'gym', true);
  }
  for (final off in [0, 2]) {
    if (mon.add(Duration(days: off)).isBefore(now.add(const Duration(days: 1)))) {
      app.store.setSchedulePlan(_k(mon.add(Duration(days: off))), 'gym', true);
      app.store.setScheduleDone(_k(mon.add(Duration(days: off))), 'gym', true);
    }
  }
  final today = app.store.dayKey();
  Map<String, Object?> item(String n, String u, num kcal, num p, num c, num f) =>
      {'name': n, 'unit': u, 'g': 100, 'mult': 1, 'kcal': kcal, 'p': p, 'c': c, 'f': f};
  app.store.addFoodLog({'date': today, 'meal': '아침', 'source': 'manual', 'items': [
    item('오트밀', '1그릇', 310, 11, 54, 6), item('삶은 계란', '2개', 155, 13, 1, 11)]});
  if (!lunch) return app;
  app.store.addFoodLog({'date': today, 'meal': '점심', 'source': 'manual', 'items': [
    item('닭가슴살', '1팩', 165, 31, 0, 3.6), item('현미밥', '1공기', 330, 7, 72, 2), item('김치', '1접시', 20, 1, 3, 0)]});
  app.store.addFoodLog({'date': today, 'meal': '간식', 'source': 'manual', 'items': [
    item('그릭요거트', '1개', 120, 10, 6, 6)]});
  return app;
}

Map<String, Object?> _snap(int workout, int food, bool checkedIn, int planned, int kept,
    double w, double smm, double bfm) => {
  ..._mallang,
  'checkedIn': checkedIn, 'plannedDays': planned, 'keptDays': kept,
  'streaks': {'workoutDays': workout, 'foodDays': food},
  'weightKg': w, 'dWeightKg': -0.3, 'smmKg': smm, 'dSmmKg': 0.1, 'bfmKg': bfm, 'dBfmKg': -0.4,
};

MockClient friendsClient() => MockClient((req) async {
  final p = req.url.path;
  if (p.endsWith('/me')) {
    return _json({'ok': true, 'user': {'id': 'me', 'handle': 'me', 'displayName': '나', 'inviteCode': 'MB-7Q2K'}});
  }
  if (p.endsWith('/friends')) {
    return _json({'ok': true, 'friends': {
      'accepted': [
        {'id': 'f1', 'displayName': '말랑쫀득이', 'handle': 'mallang'},
        {'id': 'f2', 'displayName': '곰돌이', 'handle': 'gomdol'},
        {'id': 'f3', 'displayName': '달리는감자', 'handle': 'potato'},
      ], 'incoming': [], 'outgoing': [],
    }});
  }
  if (p.contains('/snapshots/f1')) return _json({'ok': true, 'rows': [_mallang]});
  if (p.contains('/snapshots/f2')) return _json({'ok': true, 'rows': [_snap(5, 3, false, 4, 1, 78.4, 33.0, 18.1)]});
  if (p.contains('/snapshots/f3')) return _json({'ok': true, 'rows': [_snap(12, 12, true, 3, 3, 55.8, 24.2, 12.4)]});
  if (p.endsWith('/pokes')) return _json({'ok': true, 'pokes': []});
  if (p.contains('/share/')) {
    return _json({'ok': true, 'share': {
      'streak': true, 'schedule': true, 'diet': true, 'weightTrend': true,
      'smmTrend': true, 'bfmTrend': true, 'absolute': false, 'planProgress': true,
    }});
  }
  return http.Response('{"ok":false}', 404);
});

Future<Api> signedIn(MockClient client) async {
  final api = Api(baseUrl: 'https://x.test', client: client);
  await api.setToken('tok');
  return api;
}

void main() {
  setUpAll(() async {
    await loadAppFonts();
  });

  testWidgets('친구 상세 — 말랑쫀득이, 28일 스트릭', (t) async {
    phone(t);
    SharedPreferences.setMockInitialValues({});
    final app = await AppState.boot();
    final api = await signedIn(friendsClient());
    await t.pumpWidget(host(app, api, const FriendDetailScreen(
        person: {'id': 'f1', 'displayName': '말랑쫀득이', 'handle': 'mallang'})));
    await settle(t);
    expect(find.byType(ErrorWidget), findsNothing);
    expect(find.text('28일째'), findsOneWidget);
    await shot(t, '09-friend');
    restore();
  });

  /* 스토어 첫 장 — 홈 맨 위 브리핑(체크인 카드)에 「오늘 운동」 과 「밥 기록」 알림이 같이 뜬 모습.
     시계를 오늘 낮 12시 30분에 세우고, 오늘을 헬스 날(아직 안 함) · 아침만 적은 날로 둡니다. */
  testWidgets('홈 — 오늘 운동 · 점심 기록 알림', (t) async {
    phone(t);
    final app = await rich(lunch: false);
    final d = DateTime.now();
    app.store.now = () => DateTime(d.year, d.month, d.day, 12, 30);
    final today = app.store.dayKey();
    app.store.setSchedulePlan(today, 'gym', true);
    app.store.setScheduleDone(today, 'gym', false);
    final api = await signedIn(friendsClient());
    await t.pumpWidget(host(app, api, const Shell()));
    await settle(t);
    expect(find.byType(ErrorWidget), findsNothing);
    expect(find.textContaining('하는 날'), findsWidgets);
    expect(find.textContaining('점심 기록할 시간'), findsOneWidget);
    await shot(t, '01-home');
    restore();
  });

  testWidgets('탭 넷 — 식단 · 플랜 · 추이 · 친구', (t) async {
    phone(t);
    final app = await rich();
    final api = await signedIn(friendsClient());
    await t.pumpWidget(host(app, api, const Shell()));
    await settle(t);
    expect(find.byType(ErrorWidget), findsNothing);
    for (final (label, name) in [('식단', '06-food'), ('플랜', '05-plan'), ('추이', '07-progress'), ('친구', '08-social')]) {
      await t.tap(find.text(label).last);
      await settle(t);
      expect(find.byType(ErrorWidget), findsNothing, reason: label);
      await shot(t, name);
    }
    restore();
  });

  testWidgets('목표', (t) async {
    phone(t);
    final app = await rich();
    final api = await signedIn(friendsClient());
    await t.pumpWidget(host(app, api, const GoalScreen()));
    await settle(t);
    await shot(t, '04-goal');
    restore();
  });

  testWidgets('검수 — 결과지 값과 아래 그래프의 지난 측정', (t) async {
    phone(t);
    SharedPreferences.setMockInitialValues({});
    final app = await AppState.boot();
    app.store.set({'profile': kDemoProfile, 'onboarded': true});
    final api = await signedIn(friendsClient());
    final past = demoScans();
    final now = DateTime.parse(_ago(0)).toUtc().toIso8601String();
    final history = sheetHistory([
      for (final s in past.take(2))
        {'measuredAt': DateTime.parse('${s['measuredAt']}').toUtc().toIso8601String(),
         'weightKg': s['weightKg'], 'smmKg': s['smmKg'], 'pbfPct': s['pbfPct']},
    ], currentAt: now, scans: const []);
    final sheet = demoSheet(now);
    await t.pumpWidget(host(app, api, ReviewScreen(draft: {
      for (final k in ['weightKg', 'smmKg', 'bfmKg', 'pbfPct', 'ffmKg', 'bmi', 'tbwL', 'proteinKg',
          'mineralKg', 'bmrKcal', 'visceralFatLevel', 'whr', 'inbodyScore']) k: sheet[k],
      'id': 'scan-x', 'measuredAt': now, 'source': 'ocr',
    }, history: history)));
    await settle(t);
    await shot(t, '03-review');
    restore();
  });

  testWidgets('인바디 올리기 — 세 칸', (t) async {
    phone(t);
    final app = await rich();
    final api = await signedIn(friendsClient());
    await t.pumpWidget(host(app, api, const UploadScreen()));
    await settle(t);
    if (File(_sheet).existsSync()) {
      /* 사진을 붙인 상태. 사진 보관소는 임시 폴더에 열고, 고르기는 가짜로.
         파일 읽기와 그림 풀기는 진짜 비동기라 runAsync 안에서 돌립니다. */
      final dir = Directory.systemTemp.createTempSync('mybody-shots-');
      app.photos = FilePhotos.at(dir);
      app.store.photos = app.photos;
      ImagePickerPlatform.instance = _FakePicker(_sheet);
      await t.runAsync(() async {
        await t.tap(find.text('앨범에서'));
        await t.pump();
        await Future<void>.delayed(const Duration(milliseconds: 800));
        await t.pump();
        await Future<void>.delayed(const Duration(milliseconds: 800));
      });
      await t.pump();
      expect(find.text('사진에서 읽기'), findsOneWidget);
    }
    await t.enterText(find.widgetWithText(TextField, '체중'), '74.3');
    await t.enterText(find.widgetWithText(TextField, '골격근량'), '32.3');
    await t.enterText(find.widgetWithText(TextField, '체지방률'), '19.9');
    await settle(t);
    // 글자를 넣느라 내려간 목록을 맨 위로 — 사진이 첫 화면에 보여야 합니다.
    await t.drag(find.byType(ListView), const Offset(0, 1200));
    await settle(t);
    await shot(t, '02-upload');
    restore();
  });

  testWidgets('헬스 — 누르고 말하기(0.2.22)', (t) async {
    phone(t);
    final app = await rich();
    seedWorkouts(app);
    WorkoutTutorial.markSeen(app);        // 처음 한 번 뜨는 「따라 해 보기」 대신 실제 화면
    WorkoutTutorial.markSwipeHintSeen(app);
    final api = await signedIn(friendsClient());
    await t.pumpWidget(host(app, api, WorkoutSessionScreen(dateKey: app.store.dayKey(), type: 'gym')));
    await settle(t);
    expect(find.byType(ErrorWidget), findsNothing);
    // 첫 종목 두 세트 — 세트 점과 「2/21」 이 찬 모습. 시계가 돌아 settle 은 잠깐 기다리고 끝납니다.
    for (var i = 0; i < 2; i++) {
      await t.tap(find.text('세트').first);
      await t.pump(const Duration(milliseconds: 600));
    }
    await settle(t);
    await shot(t, '10-workout');
    restore();
  });

  testWidgets('지난 운동 기록 — 날짜별(0.2.22)', (t) async {
    phone(t);
    final app = await rich();
    seedWorkouts(app);
    final api = await signedIn(friendsClient());
    await t.pumpWidget(host(app, api, const WorkoutHistoryScreen()));
    await settle(t);
    expect(find.byType(ErrorWidget), findsNothing);
    await shot(t, '11-history');
    restore();
  });
}
