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
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mybody/src/api.dart';
import 'package:mybody/src/app_state.dart';
import 'package:mybody/src/scope.dart';
import 'package:mybody/src/screens/goal.dart';
import 'package:mybody/src/screens/review.dart';
import 'package:mybody/src/screens/social.dart';
import 'package:mybody/src/screens/upload.dart';
import 'package:mybody/src/sheet_history.dart';
import 'package:mybody/src/shell.dart';
import 'package:mybody/src/theme.dart';
import 'package:mybody/src/ui/edge.dart';
import 'package:mybody_core/mybody_core.dart' as core;
import 'package:shared_preferences/shared_preferences.dart';

const _out = 'build/shots';
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

void restore() => debugDisableShadows = true;

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
  // 흔한 폰: 1080×2400, 배율 3 → 논리 360×800.
  t.view.physicalSize = const Size(1080, 2400);
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

/// 주인의 실제 인바디 세 장(6/30 · 8/31 · 9/19) + 목표 · 계획 · 이번 주 운동 · 오늘 식단.
Future<AppState> rich() async {
  SharedPreferences.setMockInitialValues({});
  final app = await AppState.boot();
  app.store.seed();
  final scans = app.store.sortedScans();
  final latest = scans.last;
  final profile = ((app.state['profile'] as Map).cast<String, Object?>());
  // 지금 골격근/제지방 비율(0.568)에 맞춘 목표 — 세 값이 서로 맞고, 중 강도로 반년 안.
  final goal = <String, Object?>{'weightKg': 82.9, 'smmKg': 38.6, 'bfmKg': 15.0};
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

  testWidgets('탭 다섯 — 홈 · 식단 · 플랜 · 추이 · 친구', (t) async {
    phone(t);
    final app = await rich();
    final api = await signedIn(friendsClient());
    await t.pumpWidget(host(app, api, const Shell()));
    await settle(t);
    expect(find.byType(ErrorWidget), findsNothing);
    await shot(t, '01-home');
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
    app.store.set({'profile': core.kSeedProfile, 'onboarded': true});
    final api = await signedIn(friendsClient());
    final history = sheetHistory([
      {'measuredAt': '2026-06-30T03:00:00.000Z', 'weightKg': 89.0, 'smmKg': 36.2, 'pbfPct': 28.4},
      {'measuredAt': '2026-08-31T03:00:00.000Z', 'weightKg': 86.9, 'smmKg': 37.4, 'pbfPct': 24.2},
    ], currentAt: '2026-09-19T02:09:00.000Z', scans: const []);
    await t.pumpWidget(host(app, api, ReviewScreen(draft: const {
      'id': 'scan-x', 'measuredAt': '2026-09-19T02:09:00.000Z', 'source': 'ocr',
      'weightKg': 86.7, 'smmKg': 37.9, 'bfmKg': 20.0, 'pbfPct': 23.1, 'ffmKg': 66.7,
      'bmi': 24.8, 'tbwL': 48.7, 'proteinKg': 13.3, 'mineralKg': 4.7, 'bmrKcal': 1810,
      'visceralFatLevel': 8, 'whr': 0.94, 'inbodyScore': 73,
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
    await t.enterText(find.widgetWithText(TextField, '체중'), '86.7');
    await t.enterText(find.widgetWithText(TextField, '골격근량'), '37.9');
    await t.enterText(find.widgetWithText(TextField, '체지방률'), '23.1');
    await settle(t);
    await shot(t, '02-upload');
    restore();
  });
}
