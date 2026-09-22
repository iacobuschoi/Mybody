/* =============================================================================
 * screens_smoke_test.dart — **화면이 실제로 그려지는가**
 *
 * 릴리스 빌드에서 build() 가 던지면 Flutter 는 조용히 **회색 네모**를
 * 그립니다. 오류도 안 찍힙니다. 실제로 그걸 봤습니다 — 검수 화면이
 * 통째로 회색이었고 콘솔은 깨끗했습니다.
 *
 * 그래서 화면마다 한 번씩 세워 보고 예외가 나는지 봅니다. 예쁜지는
 * 스크린샷이 보고, 여기서는 **서는지**만 봅니다.
 * ========================================================================== */
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:mybody/src/api.dart';
import 'package:mybody/src/screens/account.dart';
import 'package:mybody/src/app_state.dart';
import 'package:mybody/src/scope.dart';
import 'package:mybody/src/screens/food.dart';
import 'package:mybody/src/screens/goal.dart';
import 'package:mybody/src/screens/history.dart';
import 'package:mybody/src/screens/home.dart';
import 'package:mybody/src/screens/onboarding.dart';
import 'package:mybody/src/screens/intensity.dart';
import 'package:mybody/src/screens/plan.dart';
import 'package:mybody/src/screens/progress.dart';
import 'package:mybody/src/screens/review.dart';
import 'package:mybody/src/screens/scandetail.dart';
import 'package:mybody/src/screens/settings.dart';
import 'package:mybody/src/screens/social.dart';
import 'package:mybody/src/screens/upload.dart';
import 'package:mybody/src/shell.dart';
import 'package:mybody/src/theme.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<AppState> seeded({bool withPlan = false, bool twoScans = false}) async {
    SharedPreferences.setMockInitialValues({});
    final app = await AppState.boot();
    app.store.set({'profile': _profile, 'onboarded': true});
    app.store.addScan({..._scan});
    if (twoScans) app.store.addScan({..._scan2});
    if (withPlan) {
      final goal = {'weightKg': 80.5, 'smmKg': 39.0, 'bfmKg': 12.0};
      final cmp = core.compareLevels(
          {..._scan}, _profile, goal, '2026-03-01', null, null);
      final plan = core.buildPlan(cmp, 'mid', {..._scan}, _profile);
      app.store.setGoal(goal);
      if (plan != null) app.store.setPlan(plan);
    }
    return app;
  }

  /* **Scope 를 MaterialApp 위에 둡니다 — 앱이 실제로 그렇게 두기 때문입니다.**
     안에 두면 밀어 올린 화면(push)에서 Scope 가 안 보이는데, 시험은
     화면을 home 자리에 직접 세워서 그 차이를 못 봅니다. 실제로 그래서
     검수 화면이 릴리스에서 회색 네모가 됐는데 시험 열아홉 개가 전부
     통과했습니다. */
  /* 서버는 없습니다 — 모든 요청에 404. 화면이 서는지만 보는 시험이라
     그걸로 충분하고, 진짜 소켓을 열지 않으니 시험이 밖으로 나가지 않습니다. */
  Api api({bool signedIn = true}) {
    final a = Api(
        baseUrl: '',
        client: MockClient((_) async => http.Response('{"ok":false}', 404)));
    if (signedIn) a.setToken('tok');
    return a;
  }

  /* **로그인된 채로 세웁니다.** 셸이 로그인을 먼저 요구하므로, 로그인
     안 된 상태는 그걸 보는 시험에서만 따로 만듭니다. */
  Widget host(AppState app, Widget child, {Api? api_}) => Scope(
        state: app,
        api: api_ ?? api(),
        onServerChange: (_) async {},
        child: MaterialApp(theme: mbLight(), home: child),
      );

  void noop(String route, [Object? arg]) {}

  Future<void> standsUp(WidgetTester t, AppState app, Widget child) async {
    await t.pumpWidget(host(app, child));
    await t.pump(const Duration(milliseconds: 200));
    /* **회색 네모가 안 나와야 합니다.** ErrorWidget 이 하나라도 있으면
       그 화면은 릴리스에서 통째로 회색입니다. */
    expect(find.byType(ErrorWidget), findsNothing);
    expect(t.takeException(), isNull);
  }

  testWidgets('홈 — 측정 없음', (t) async {
    SharedPreferences.setMockInitialValues({});
    final app = await AppState.boot();
    await standsUp(t, app, Scaffold(body: HomeScreen(go: noop)));
  });

  testWidgets('홈 — 측정만', (t) async {
    final app = await seeded();
    await standsUp(t, app, Scaffold(body: HomeScreen(go: noop)));
  });

  testWidgets('홈 — 계획까지', (t) async {
    final app = await seeded(withPlan: true, twoScans: true);
    await standsUp(t, app, Scaffold(body: HomeScreen(go: noop)));
  });

  /* 원본 홈에 있던 플랜 카드(오늘/이번주/한달)와 「플랜대로 채우기」. */
  testWidgets('홈 — 플랜 카드 세 탭이 다 서고, 플랜대로 채우기가 이번 주를 채운다', (t) async {
    t.view.physicalSize = const Size(1000, 5000);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final app = await seeded(withPlan: true);
    await t.pumpWidget(host(app, Scaffold(body: HomeScreen(go: noop))));
    await t.pump(const Duration(milliseconds: 200));
    expect(find.text('플랜'), findsOneWidget);
    expect(find.text('다음에 할 일'), findsOneWidget);
    for (final s in ['이번주', '한달', '오늘']) {
      await t.tap(find.text(s));
      await t.pump();
      expect(find.byType(ErrorWidget), findsNothing, reason: '$s 탭');
      expect(t.takeException(), isNull, reason: '$s 탭');
    }

    final sessions = ((app.state['plan'] as Map)['workout'] as Map)['sessions'] as List;
    final days = (app.schedule.week()['days'] as List).cast<Map<String, Object?>>();
    final today = app.store.dayKey();
    final expectKeys = [
      for (var i = 0; i < 7; i++)
        if ('${days[i]['key']}'.compareTo(today) >= 0 && (sessions[i] as Map)['rest'] != true)
          '${days[i]['key']}',
    ];
    final btn = find.textContaining('플랜대로 채우기');
    if (expectKeys.isEmpty) {
      expect(btn, findsNothing, reason: '채울 날이 없으면 버튼도 없습니다');
      return;
    }
    expect(btn, findsOneWidget);
    await t.tap(btn);
    await t.pump();
    for (final k in expectKeys) {
      expect(app.store.scheduleDay(k)['plan'], contains('gym'), reason: k);
    }
    expect(btn, findsNothing, reason: '채우고 나면 버튼이 사라집니다');
    /* 지나간 날은 건드리지 않았는지 */
    for (final d in days) {
      if ('${d['key']}'.compareTo(today) < 0) {
        expect(app.store.scheduleDay('${d['key']}')['plan'], isEmpty, reason: '지난 날 ${d['key']}');
      }
    }
  });

  testWidgets('인바디 넣기', (t) async {
    final app = await seeded();
    await standsUp(t, app, const UploadScreen());
  });

  /* **프로필도 측정도 없는 막 깐 앱.** 웹 빌드에서 검수 화면이 통째로
     회색이 된 것이 정확히 이 상태였습니다 — 시험은 전부 프로필을 넣고
     시작해서 그 길을 한 번도 안 밟았습니다. */
  testWidgets('판독 검수 — 막 깐 앱 (프로필 없음)', (t) async {
    SharedPreferences.setMockInitialValues({});
    final app = await AppState.boot();
    await standsUp(t, app, const ReviewScreen(draft: {
      'id': 'draft', 'measuredAt': '2026-09-21T00:00:00.000Z',
      'weightKg': 86.7, 'smmKg': 38.0, 'bfmKg': 20.0,
    }));
  });

  /* 체지방은 %로 받고, 검수로 넘길 때 kg 도 같이 — 엔진과 검산이 보는 것. */
  testWidgets('인바디 넣기 — 체지방률(%)로 받고 kg 를 계산해 넘긴다', (t) async {
    t.view.physicalSize = const Size(1000, 3000);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    SharedPreferences.setMockInitialValues({});
    final app = await AppState.boot();
    app.store.set({'profile': _profile, 'onboarded': true});
    await t.pumpWidget(host(app, const UploadScreen()));
    await t.pump(const Duration(milliseconds: 200));
    expect(find.widgetWithText(TextField, '체지방량'), findsNothing, reason: 'kg 칸은 없어야 합니다');
    expect(find.widgetWithText(TextField, '체지방률'), findsOneWidget);

    await t.enterText(find.widgetWithText(TextField, '체중'), '86.7');
    await t.enterText(find.widgetWithText(TextField, '골격근량'), '38');
    await t.enterText(find.widgetWithText(TextField, '체지방률'), '23.1');
    await t.pump();
    await t.tap(find.text('다음 — 검산하기'));
    await t.pumpAndSettle();
    expect(find.byType(ReviewScreen), findsOneWidget);
    final review = t.widget<ReviewScreen>(find.byType(ReviewScreen));
    expect(review.draft['pbfPct'], 23.1);
    expect(review.draft['bfmKg'], 20.0, reason: '86.7 × 23.1% = 20.0kg');
    expect(review.draft['weightKg'], 86.7);
  });

  test('bfmFrom — 인쇄된 kg 가 계산과 반올림 안에서 같으면 인쇄값', () {
    expect(bfmFrom(86.7, 23.1), 20.0);
    expect(bfmFrom(86.7, 23.1, printed: 20.1), 20.1);
    expect(bfmFrom(86.7, 23.1, printed: 25.0), 20.0, reason: '많이 다르면 사용자의 %가 이깁니다');
  });

  testWidgets('인바디 넣기 — 막 깐 앱', (t) async {
    SharedPreferences.setMockInitialValues({});
    final app = await AppState.boot();
    await standsUp(t, app, const UploadScreen());
  });

  testWidgets('목표 설정 — 막 깐 앱', (t) async {
    SharedPreferences.setMockInitialValues({});
    final app = await AppState.boot();
    await standsUp(t, app, const GoalScreen());
  });

  testWidgets('판독 검수 — 첫 측정', (t) async {
    SharedPreferences.setMockInitialValues({});
    final app = await AppState.boot();
    app.store.set({'profile': _profile});
    await standsUp(t, app, const ReviewScreen(draft: {
      'id': 'draft', 'measuredAt': '2026-06-01T00:00:00.000Z',
      'weightKg': 86.7, 'smmKg': 38.0, 'bfmKg': 20.0,
    }));
  });

  /* **사진 이름이 저장까지 갑니다.** 초안엔 있었는데 검수가 숫자만 옮겨서
     붙인 사진이 측정 상세에 안 나왔습니다 — 에뮬레이터에서 잡은 것. */
  testWidgets('판독 검수 — 붙인 사진이 측정에 남는다', (t) async {
    t.view.physicalSize = const Size(1000, 4000);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    SharedPreferences.setMockInitialValues({});
    final app = await AppState.boot();
    app.store.set({'profile': _profile, 'onboarded': true});
    await t.pumpWidget(host(app, const _PushReview()));
    await t.tap(find.text('열기'));
    await t.pumpAndSettle();
    await t.tap(find.text('저장하기'));
    await t.pumpAndSettle();
    final scans = app.store.sortedScans();
    expect(scans, hasLength(1));
    expect(scans.last['photoId'], 'p1');
    expect(scans.last['source'], 'ocr');
    expect(scans.last['pbfPct'], 23.1, reason: '판독이 준 값이 계산값으로 바뀌면 안 됩니다');
  });

  testWidgets('판독 검수 — 이전 측정이 있을 때', (t) async {
    final app = await seeded();
    await standsUp(t, app, const ReviewScreen(draft: {
      'id': 'draft', 'measuredAt': '2026-06-01T00:00:00.000Z',
      'weightKg': 86.7, 'smmKg': 38.0, 'bfmKg': 20.0,
    }));
  });

  testWidgets('판독 검수 — 값이 서로 안 맞을 때', (t) async {
    final app = await seeded();
    await standsUp(t, app, const ReviewScreen(draft: {
      'id': 'draft', 'measuredAt': '2026-06-01T00:00:00.000Z',
      'weightKg': 867.0, 'smmKg': 38.0, 'bfmKg': 20.0,
    }));
  });

  testWidgets('목표 설정', (t) async {
    final app = await seeded();
    await standsUp(t, app, const GoalScreen());
  });

  /* **셋 중 둘을 정하면 나머지가 따라옵니다.** 셋을 다 손으로 넣으면
     서로 안 맞기 마련이고, 그때 앱은 계획을 안 만듭니다 — 에뮬레이터에서
     골격근을 40 으로 바꾸자 바로 그렇게 됐습니다. */
  testWidgets('목표 — 체지방률로 받고, 두 칸을 정하면 나머지가 따라온다', (t) async {
    t.view.physicalSize = const Size(1000, 4000);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final app = await seeded();
    await t.pumpWidget(host(app, const GoalScreen()));
    await t.pump(const Duration(milliseconds: 200));

    expect(find.widgetWithText(TextField, '목표 체지방량'), findsNothing, reason: 'kg 칸은 없어야 합니다');
    expect(find.widgetWithText(TextField, '목표 체지방률 (자동)'), findsOneWidget);
    expect(find.textContaining('두 칸을 정하면 나머지 한 칸은 자동'), findsOneWidget);

    final pctBefore = t.widget<TextField>(find.widgetWithText(TextField, '목표 체지방률 (자동)')).controller!.text;
    await t.enterText(find.widgetWithText(TextField, '목표 골격근량'), '40');
    await t.pump();
    final pctAfter = t.widget<TextField>(find.widgetWithText(TextField, '목표 체지방률 (자동)')).controller!.text;
    expect(pctAfter, isNot(pctBefore), reason: '골격근을 바꾸면 체지방률이 따라와야 합니다');
    expect(find.text('세 숫자가 서로 안 맞습니다.'), findsNothing);

    /* 체지방률을 직접 고치면 그 칸은 손 칸이 되고, 가장 오래된 체중이 자동이 됩니다. */
    await t.enterText(find.widgetWithText(TextField, '목표 체지방률 (자동)'), '15');
    await t.pump();
    expect(find.widgetWithText(TextField, '목표 체중 (자동)'), findsOneWidget);
    final w = t.widget<TextField>(find.widgetWithText(TextField, '목표 체중 (자동)')).controller!.text;
    expect(w, isNot('80.5'));
    expect(find.text('세 숫자가 서로 안 맞습니다.'), findsNothing);
  });

  testWidgets('목표 — 모드 설명은 접혀 있고 「자세히」로 펼친다', (t) async {
    t.view.physicalSize = const Size(1000, 4000);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final app = await seeded();
    await t.pumpWidget(host(app, const GoalScreen()));
    await t.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const Key('mode-reason')), findsNothing);
    await t.tap(find.text('자세히'));
    await t.pump();
    expect(find.byKey(const Key('mode-reason')), findsOneWidget);
    expect(find.text('접기'), findsOneWidget);
  });

  testWidgets('플랜 — 계획 없음', (t) async {
    final app = await seeded();
    await standsUp(t, app, Scaffold(body: PlanScreen(go: noop)));
  });

  testWidgets('플랜 — 계획 있음', (t) async {
    final app = await seeded(withPlan: true);
    await standsUp(t, app, Scaffold(body: PlanScreen(go: noop)));
  });

  testWidgets('추이 — 측정 하나', (t) async {
    final app = await seeded();
    await standsUp(t, app, Scaffold(body: ProgressScreen(go: noop)));
  });

  testWidgets('추이 — 측정 둘', (t) async {
    final app = await seeded(twoScans: true, withPlan: true);
    await standsUp(t, app, Scaffold(body: ProgressScreen(go: noop)));
  });

  testWidgets('식단', (t) async {
    final app = await seeded(withPlan: true);
    await standsUp(t, app, Scaffold(body: FoodScreen(go: noop)));
  });

  /* 원본 식단 화면의 카드들: 남은 양 · 뭘 먹을까 · 끼니별 · 최근 · 어제 · 달성률 */
  testWidgets('식단 — 남은 양·끼니 카드·지난번과 같이·어제와 같이·최근 먹은 것', (t) async {
    t.view.physicalSize = const Size(1000, 6000);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final app = await seeded(withPlan: true);
    final today = app.store.dayKey();
    final d = DateTime.parse('${today}T00:00:00');
    final yesterday = app.store.dayKey(DateTime(d.year, d.month, d.day - 1));
    app.store.addFoodLog({
      'date': yesterday, 'meal': '점심', 'source': 'manual',
      'items': [{'name': '닭가슴살', 'unit': '1팩', 'g': 100, 'mult': 1, 'kcal': 165, 'p': 31, 'c': 0, 'f': 3.6}],
    });
    await t.pumpWidget(host(app, Scaffold(body: FoodScreen(go: noop))));
    await t.pump(const Duration(milliseconds: 200));
    expect(find.byType(ErrorWidget), findsNothing);

    expect(find.text('단백질 남음'), findsOneWidget, reason: '남은 양 카드');
    expect(find.textContaining('목표 범위'), findsWidgets);
    /* 뭘 먹을까는 작은 버튼 — 누르면 추천이 튀어나오고, 담으면 끼니에 들어갑니다. */
    expect(find.textContaining('뭘 먹을까'), findsOneWidget);
    expect(find.byIcon(LucideIcons.wand2), findsOneWidget);
    await t.tap(find.textContaining('뭘 먹을까'));
    await t.pumpAndSettle();
    expect(find.text('사먹기'), findsOneWidget);
    expect(find.text('기록에 담기'), findsWidgets);
    await t.tap(find.text('기록에 담기').first);
    await t.pumpAndSettle();
    expect(find.text('사먹기'), findsNothing, reason: '담으면 시트가 닫힙니다');
    expect(app.store.logsForDate(today), hasLength(1), reason: '추천이 끼니에 들어갑니다');
    app.store.removeFoodLog(app.store.logsForDate(today).first['id']);
    await t.pump();
    for (final m in ['아침', '점심', '저녁', '간식']) {
      expect(find.text(m), findsWidgets, reason: '$m 카드');
    }
    expect(find.text('어제 것 그대로 가져오기'), findsOneWidget);
    expect(find.text('지난번과 같이'), findsOneWidget, reason: '어제 점심이 있으니 점심 카드에만');
    expect(find.widgetWithText(ActionChip, '닭가슴살'), findsOneWidget, reason: '최근 먹은 것');

    await t.tap(find.text('지난번과 같이'));
    await t.pump();
    expect(app.store.logsForDate(today), hasLength(1));
    expect(app.store.logsForDate(today).first['meal'], '점심');
    expect(find.text('어제 것 그대로 가져오기'), findsNothing, reason: '오늘 기록이 생기면 사라집니다');

    /* 항목 하나를 지우면 빈 기록은 통째로 사라집니다. */
    await t.tap(find.byTooltip('항목 삭제').first);
    await t.pump();
    expect(app.store.logsForDate(today), isEmpty);

    await t.tap(find.widgetWithText(ActionChip, '닭가슴살'));
    await t.pump();
    expect(app.store.logsForDate(today), hasLength(1));
    expect(find.text('지난번과 같이'), findsWidgets);
  });

  testWidgets('식단 — 목표가 없으면 플랜 만들기로 보낸다', (t) async {
    final app = await seeded();
    String? went;
    await t.pumpWidget(host(app, Scaffold(body: FoodScreen(go: (r, [_]) => went = r))));
    await t.pump(const Duration(milliseconds: 200));
    expect(find.text('아직 하루 목표가 없습니다'), findsOneWidget);
    expect(find.text('단백질 남음'), findsNothing);
    await t.tap(find.text('플랜 만들기'));
    expect(went, 'goal');
  });

  testWidgets('식단 달성률 — 주간·월간이 선다', (t) async {
    t.view.physicalSize = const Size(1000, 5000);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final app = await seeded(withPlan: true);
    app.store.addFoodLog({
      'date': app.store.dayKey(), 'meal': '아침', 'source': 'manual',
      'items': [{'name': '계란', 'g': 50, 'kcal': 72, 'p': 6.3, 'c': 0.4, 'f': 5}],
    });
    await t.pumpWidget(host(app, DietAdherenceScreen(go: noop)));
    await t.pump(const Duration(milliseconds: 200));
    expect(find.text('최근 7일'), findsOneWidget);
    expect(find.byType(ErrorWidget), findsNothing);
    await t.tap(find.text('월간'));
    await t.pump(const Duration(milliseconds: 200));
    expect(find.text('최근 30일'), findsWidgets);
    expect(find.byType(ErrorWidget), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('음식 검색 — 분류 필터와 직접 입력', (t) async {
    t.view.physicalSize = const Size(1000, 4000);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final app = await seeded();
    await t.pumpWidget(host(app, FoodSearchScreen(date: app.store.dayKey(), meal: '저녁')));
    await t.pump(const Duration(milliseconds: 200));
    expect(find.widgetWithText(AppBar, '저녁에 추가'), findsOneWidget);
    await t.tap(find.widgetWithText(FilterChip, '단백질'));
    await t.pump();
    final tiles = find.byType(ListTile).evaluate().length;
    expect(tiles, greaterThan(0));

    await t.tap(find.text('목록에 없어요 · 직접 입력'));
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextField, '이름'), '구내식당 점심');
    await t.enterText(find.widgetWithText(TextField, '칼로리 (kcal)'), '650');
    await t.enterText(find.widgetWithText(TextField, '단백질 (g)'), '30');
    await t.tap(find.text('추가'));
    await t.pumpAndSettle();
    expect(find.text('1개 저장'), findsOneWidget);
  });

  testWidgets('음식 검색', (t) async {
    final app = await seeded();
    await standsUp(t, app, const FoodSearchScreen(date: '2026-06-01'));
  });

  testWidgets('측정 기록', (t) async {
    final app = await seeded(twoScans: true);
    await standsUp(t, app, const HistoryScreen());
  });

  testWidgets('측정 상세', (t) async {
    final app = await seeded(twoScans: true);
    await standsUp(t, app, const ScanDetailScreen(scanId: 's2'));
  });

  testWidgets('설정', (t) async {
    final app = await seeded();
    await standsUp(t, app, const SettingsScreen());
  });

  testWidgets('친구 — 로그인 안 함', (t) async {
    final app = await seeded();
    await t.pumpWidget(host(app, Scaffold(body: SocialScreen(go: noop)),
        api_: api(signedIn: false)));
    await t.pump(const Duration(milliseconds: 200));
    expect(find.byType(ErrorWidget), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('친구 — 로그인 됨 (서버 없음)', (t) async {
    final app = await seeded();
    await standsUp(t, app, Scaffold(body: SocialScreen(go: noop)));
  });

  /* **밀어 올린 화면도 섭니다.**
     이 시험이 없어서 릴리스에서만 회색이 되는 것을 못 잡았습니다.
     화면을 직접 세우는 것과, 앱처럼 밀어 올리는 것은 다른 일입니다. */
  testWidgets('밀어 올린 화면이 상태를 본다 (push 경로)', (t) async {
    final app = await seeded(twoScans: true);
    await t.pumpWidget(host(app, const _Pusher()));
    await t.pump();
    await t.tap(find.text('열기'));
    await t.pumpAndSettle();
    expect(find.byType(ErrorWidget), findsNothing,
        reason: 'Scope 가 MaterialApp 아래에 있으면 여기서 회색 네모가 됩니다');
    expect(t.takeException(), isNull);
    expect(find.text('측정 기록'), findsWidgets);
  });

  /* **프로필 없이 홈으로 못 들어갑니다.**
     들어가면 코어가 씨앗 프로필(주인의 몸: 187cm · 22세 · 남성)로
     계산합니다 — 키 155cm 인 사람에게 187cm 기준 식단이 나가고,
     틀렸다는 표시는 어디에도 없습니다. */
  /* **막 깐 앱은 로그인이 먼저입니다.** 사진 판독은 계정으로 되는 일이라,
     계정 없이 들어가면 첫 판독이 실패합니다 — 그게 첫인상이면 안 됩니다. */
  testWidgets('막 깐 앱은 로그인을 먼저 세운다', (t) async {
    SharedPreferences.setMockInitialValues({});
    final app = await AppState.boot();
    await t.pumpWidget(host(app, const Shell(), api_: api(signedIn: false)));
    await t.pump();
    expect(find.byType(SignInScreen), findsOneWidget);
    expect(find.byType(OnboardingScreen), findsNothing, reason: '로그인 전에 온보딩이 보이면 안 됩니다');
    expect(find.text('홈'), findsNothing, reason: '로그인 없이 홈이 보이면 안 됩니다');
    expect(find.text('처음이에요'), findsOneWidget, reason: '가입 길이 보여야 합니다');
  });

  testWidgets('로그인이 되면 온보딩으로 넘어간다', (t) async {
    SharedPreferences.setMockInitialValues({});
    final app = await AppState.boot();
    final a = api(signedIn: false);
    await t.pumpWidget(host(app, const Shell(), api_: a));
    await t.pump();
    expect(find.byType(SignInScreen), findsOneWidget);

    await a.setToken('tok');   // 로그인 성공이 하는 일과 같습니다
    await t.pump();
    expect(find.byType(SignInScreen), findsNothing);
    expect(find.byType(OnboardingScreen), findsOneWidget);
  });

  testWidgets('로그인은 됐고 프로필이 없으면 온보딩을 세운다', (t) async {
    SharedPreferences.setMockInitialValues({});
    final app = await AppState.boot();
    await t.pumpWidget(host(app, const Shell()));
    await t.pump();
    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(find.text('홈'), findsNothing, reason: '프로필 없이 홈이 보이면 안 됩니다');
  });

  testWidgets('온보딩을 마치면 프로필이 남고 홈이 열린다', (t) async {
    SharedPreferences.setMockInitialValues({});
    final app = await AppState.boot();
    await t.pumpWidget(host(app, const Shell()));
    await t.pump();

    await t.enterText(find.widgetWithText(TextField, '키'), '155');
    await t.enterText(find.widgetWithText(TextField, '나이'), '34');
    await t.pump();
    await t.tap(find.text('다음'));
    await t.pumpAndSettle();
    await t.tap(find.text('다음'));
    await t.pumpAndSettle();
    await t.tap(find.text('읽었고 이해했습니다'));
    await t.pump();
    await t.tap(find.text('시작하기'));
    await t.pumpAndSettle();

    expect(app.onboarded, isTrue);
    expect(app.profile?['heightCm'], 155.0);
    expect(app.profile?['age'], 34.0);
    expect(find.byType(OnboardingScreen), findsNothing);
    /* 씨앗 프로필(주인 키 187)이 새어 들어오지 않았는지 못 박습니다. */
    expect(app.profile?['heightCm'], isNot(187));
  });

  /* **별표가 화면에 나가면 안 됩니다.**
     문구 안의 `**굵게**` 표시를 Flutter 의 Text 는 모릅니다 — 그대로 찍습니다.
     실제로 온보딩 고지에 "측정 기록은 **이 기기에만** 저장됩니다" 가
     별표째로 나갔습니다. 제일 중요한 문장이 제일 어설퍼 보이는 자리였습니다. */
  testWidgets('화면에 마크다운 별표가 안 나온다', (t) async {
    SharedPreferences.setMockInitialValues({});
    final fresh = await AppState.boot();
    final planned = await seeded(withPlan: true, twoScans: true);

    for (final (name, app, screen) in <(String, AppState, Widget)>[
      ('온보딩', fresh, const OnboardingScreen()),
      ('설정', planned, const SettingsScreen()),
      ('홈', planned, Scaffold(body: HomeScreen(go: noop))),
      ('플랜', planned, Scaffold(body: PlanScreen(go: noop))),
      ('추이', planned, Scaffold(body: ProgressScreen(go: noop))),
    ]) {
      await t.pumpWidget(host(app, screen));
      await t.pump(const Duration(milliseconds: 200));
      final stars = <String>[];
      for (final w in t.widgetList<Text>(find.byType(Text))) {
        final s = w.data ?? w.textSpan?.toPlainText() ?? '';
        if (s.contains('**')) stars.add(s);
      }
      expect(stars, isEmpty, reason: '$name 화면에 별표가 그대로 나갑니다: $stars');
    }
  });

  /* **앱이 고른 모드가 계획까지 가야 합니다.**
     모드를 보여 주는 이유는 그 모드의 속도 상한과 단백질 하한 때문입니다.
     화면에는 "감량모드" 라고 써 놓고 계획은 아무 제약 없이 만들면,
     그 글자는 장식이 됩니다. */
  /* 위쪽 설명 세 덩이는 한 장에 첫 문장만. 화면을 열자마자 글을 읽게
     하면 골라야 할 카드가 화면 밖으로 밀립니다. */
  testWidgets('기간 고르기 — 설명은 한 장에 첫 문장만, 「자세히」로 펼친다', (t) async {
    t.view.physicalSize = const Size(1000, 5000);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final app = await seeded();
    await t.pumpWidget(host(app, const IntensityScreen(
        goal: {'weightKg': 80.5, 'smmKg': 39.0, 'bfmKg': 12.0}, modeId: 'cutting')));
    await t.pumpAndSettle();
    expect(find.text('이 목표는'), findsOneWidget);
    final before = find.byType(Note).evaluate().length;
    expect(find.text('자세히'), findsOneWidget);
    await t.tap(find.text('자세히'));
    await t.pump();
    expect(find.text('접기'), findsOneWidget);
    expect(find.byType(Note).evaluate().length, greaterThan(before));
    expect(find.byType(ErrorWidget), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('고른 모드의 제약이 계획에 실제로 걸린다', (t) async {
    final app = await seeded();
    await t.pumpWidget(host(app, const IntensityScreen(
        goal: {'weightKg': 80.5, 'smmKg': 39.0, 'bfmKg': 12.0}, modeId: 'cutting')));
    await t.pumpAndSettle();
    expect(find.byType(ErrorWidget), findsNothing);

    /* 커팅모드는 공격성 a 를 0.4~0.75 로 묶고 단백질 하한을 2.4 g/kg FFM
       으로 올립니다(modes.js). 모드가 안 걸리면 a 가 0~1 전체에서 뽑힙니다.
       **속도 상한이 장식이 아니라 잠금장치**라는 것이 이 시험의 전부입니다. */
    final cmp = core.compareLevels({..._scan}, _profile,
        {'weightKg': 80.5, 'smmKg': 39.0, 'bfmKg': 12.0},
        '2026-03-01', null, core.modeById('cutting'));
    final free = core.compareLevels({..._scan}, _profile,
        {'weightKg': 80.5, 'smmKg': 39.0, 'bfmKg': 12.0},
        '2026-03-01', null, null);

    for (final r0 in (cmp['results'] as List)) {
      final r = (r0 as Map).cast<String, Object?>();
      final a = core.jsToNumber(r['a']);
      expect(a >= 0.4 && a <= 0.75, isTrue,
          reason: '커팅모드인데 공격성이 ${a.toStringAsFixed(2)} 입니다 (0.40~0.75 여야 합니다)');
      final protein = core.jsToNumber((r['macros'] as Map)['proteinPerFFM']);
      expect(protein >= 2.4, isTrue,
          reason: '커팅모드인데 단백질 하한이 안 걸렸습니다 ($protein)');
    }

    /* 안 건 쪽은 그 범위 밖으로 나갑니다 — 안 나가면 이 시험이 아무것도
       구분하지 못하는 것이라 그것도 잡습니다. */
    final freeAs = [
      for (final r in (free['results'] as List)) core.jsToNumber((r as Map)['a'])
    ];
    expect(freeAs.any((a) => a < 0.4 || a > 0.75), isTrue,
        reason: '모드를 안 걸었는데도 같은 범위 안에 있습니다 — 시험이 구분을 못 합니다');
  });

  /* 폰의 뒤로 가기가 식단 탭에서 앱을 닫았습니다. 홈으로 가야 합니다. */
  testWidgets('셸 — 다른 탭에서 뒤로 가기는 홈으로 간다', (t) async {
    final app = await seeded(withPlan: true, twoScans: true);
    await t.pumpWidget(host(app, const Shell()));
    await t.pump(const Duration(milliseconds: 200));
    await t.tap(find.text('식단'));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.widgetWithText(AppBar, '식단'), findsOneWidget);

    await t.binding.handlePopRoute();   // 폰의 뒤로 가기
    await t.pump(const Duration(milliseconds: 300));
    expect(find.widgetWithText(AppBar, '홈'), findsOneWidget);
    expect(find.byType(Shell), findsOneWidget, reason: '앱이 닫히면 안 됩니다');
  });

  testWidgets('셸 — 탭 다섯 개가 다 선다', (t) async {
    final app = await seeded(withPlan: true, twoScans: true);
    await t.pumpWidget(host(app, const Shell()));
    await t.pump(const Duration(milliseconds: 200));
    for (final label in ['식단', '플랜', '추이', '친구', '홈']) {
      await t.tap(find.text(label));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.byType(ErrorWidget), findsNothing, reason: '$label 탭이 회색 네모가 됩니다');
      expect(t.takeException(), isNull, reason: '$label 탭에서 예외');
    }
  });
}

/// 검수 화면을 밀어 올립니다 — 저장하면 pop 하므로 home 자리엔 못 둡니다.
class _PushReview extends StatelessWidget {
  const _PushReview();
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const ReviewScreen(draft: {
                      'id': 'd1', 'measuredAt': '2026-06-01T00:00:00.000Z',
                      'weightKg': 86.7, 'smmKg': 38.0, 'bfmKg': 20.0,
                      'pbfPct': 23.1, 'photoId': 'p1', 'source': 'ocr',
                    }))),
            child: const Text('열기'),
          ),
        ),
      );
}

/// 진짜 앱처럼 화면을 **밀어 올려** 봅니다.
class _Pusher extends StatelessWidget {
  const _Pusher();
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const HistoryScreen())),
            child: const Text('열기'),
          ),
        ),
      );
}
