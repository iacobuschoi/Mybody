/* =============================================================================
 * estimate_ui_test.dart — 「인바디 없이 시작」 이 화면에서 실제로 되는가
 *
 * 주인: "인바디 사진 없으면 샘플 데이터로 시작해보기 만들어서 키/체중만으로
 * 추정하고 나중에 제대로된 사진 넣으면 업데이트되는거로 하자".
 *
 * 계산(Gallagher 2000 · Lee 2000)과 실측으로 바꾸기는 estimate.dart ·
 * estimate_upgrade.dart 의 시험이 봅니다. 여기서 보는 것은 화면입니다:
 *
 *   1. 길 — 홈 빈 화면 · 추이 빈 화면 · 업로드 화면에서 시트를 열고, 체중 한
 *      칸을 넣고, 저장하면 목표 화면으로 갑니다. 프로필이 비었으면 그 칸들을
 *      묻습니다.
 *   2. 표시 — 숫자가 나오는 곳마다 「추정」 이 붙고(홈 요약 · 목표 카드 ·
 *      플랜 탭 · 측정 자세히 · 기록 · 추이), 추정이 낀 차이(±)는 안 찍힙니다.
 *   3. 선 — 추이 그래프는 실측이 있으면 실측만 그립니다. 추정 → 실측의 선은
 *      몸의 변화가 아니라 공식의 오차입니다.
 *   4. 알림 — 실측으로 바뀐 뒤 홈 맨 위 카드가 한 번 뜨고, 닫으면 'seen'.
 *   5. 폭 — 360px · 글자 1.3배 · 어두운 테마에서 넘치지 않습니다.
 *
 * 추정과 실측이 섞인 상태는 replaceState 로 만듭니다 — addScan 으로 넣으면
 * 앱의 정리(needsEstimateUpgrade → upgradeEstimates)가 곧바로 추정을 지워서
 * 그 상태를 볼 수 없습니다. 섞인 상태는 동기화가 늦은 기기에서 잠깐 생깁니다.
 * ========================================================================== */
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mybody/src/api.dart';
import 'package:mybody/src/app_state.dart';
import 'package:mybody/src/estimate.dart';
import 'package:mybody/src/scope.dart';
import 'package:mybody/src/screens/estimate_sheet.dart';
import 'package:mybody/src/screens/goal.dart';
import 'package:mybody/src/screens/history.dart';
import 'package:mybody/src/screens/home.dart';
import 'package:mybody/src/screens/plan.dart';
import 'package:mybody/src/screens/progress.dart';
import 'package:mybody/src/screens/scandetail.dart';
import 'package:mybody/src/screens/upload.dart';
import 'package:mybody/src/theme.dart';
import 'package:mybody/src/ui/charts.dart';
import 'package:mybody/src/ui/widgets.dart';
import 'package:mybody_core/mybody_core.dart' as core;
import 'package:shared_preferences/shared_preferences.dart';

/// 주인의 실제 결과지(남 · 187cm · 22세). 추정은 같은 체중에서 골격근 35.7 · 체지방률 22.1.
const _real = {
  'id': 'r1', 'weightKg': 86.7, 'smmKg': 38.0, 'bfmKg': 20.0,
  'pbfPct': 23.1, 'ffmKg': 66.7, 'bmi': 24.8, 'bmrKcal': 1810,
  'measuredAt': '2026-03-01T00:00:00.000Z',
};
const _profile = {
  'sex': 'male', 'age': 22, 'heightCm': 187, 'activityLevel': 'moderate',
  'trainingAge': 'novice', 'daysPerWeek': 4, 'mealsPerDay': 3,
};

const _weightKey = ValueKey('estimate-weight');
const _saveKey = ValueKey('estimate-save');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<AppState> seeded({bool withProfile = true}) async {
    SharedPreferences.setMockInitialValues({});
    final app = await AppState.boot();
    app.store.set({if (withProfile) 'profile': _profile, 'onboarded': true});
    return app;
  }

  /// 추정 하나를 저장합니다(남 · 22세 · 187cm · 86.7kg).
  Map<String, Object?> addEstimate(AppState app, {DateTime? at}) {
    final r = saveEstimate(app.store,
        sex: 'male', age: 22, heightCm: 187, weightKg: 86.7,
        now: at ?? DateTime.utc(2026, 9, 20, 9));
    expect(r, isNotNull);
    return r!;
  }

  /// [scan] 위에 목표 · 계획(중간 강도)을 세웁니다. 기본은 추정 위에 세운 계획 —
  /// 목표 81.6 / 36.7 / 12.2 에 도장 fromEstimate. 실측 위라면 도장 없이.
  Map<String, Object?> estimatePlan(AppState app, Map<String, Object?> scan,
      {String? day, Map<String, Object?>? goal, bool stamp = true}) {
    final g = goal ?? {'weightKg': 81.6, 'smmKg': 36.7, 'bfmKg': 12.2};
    final cmp = core.compareLevels({...scan}, _profile, g, day ?? '2026-09-20', null, null);
    final plan = core.buildPlan(cmp, 'mid', {...scan}, _profile)!;
    if (stamp) plan['fromEstimate'] = true;
    app.store.setGoal(g);
    app.store.setPlan(plan);
    return plan;
  }

  /// 추정과 실측이 같이 있는 상태 — 정리(upgrade)를 부르지 않고 통째로 바꿉니다.
  void mixed(AppState app, List<Map<String, Object?>> scans) =>
      app.store.replaceState({...app.state, 'scans': scans});

  Api api() {
    final a = Api(
        baseUrl: '', client: MockClient((_) async => http.Response('{"ok":false}', 404)));
    a.setToken('tok');
    return a;
  }

  Widget host(AppState app, Widget child, {ThemeData? theme}) => Scope(
        state: app,
        api: api(),
        onServerChange: (_) async {},
        child: MaterialApp(theme: theme ?? mbLight(), home: child),
      );

  void size(WidgetTester t, Size s) {
    t.view.physicalSize = s;
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
  }

  Future<void> settle(WidgetTester t) async {
    await t.pump(const Duration(milliseconds: 100));
    await t.pumpAndSettle();
  }

  bool saveEnabled(WidgetTester t) => t.widget<FilledButton>(find.byKey(_saveKey)).onPressed != null;

  Finder pill(String text) => find.widgetWithText(Pill, text);

  /* --- 1. 길 ----------------------------------------------------------------- */

  testWidgets('홈 · 인바디 없음 → 「인바디 없이 시작」 → 체중만 넣고 저장 → 목표 화면으로', (t) async {
    size(t, const Size(400, 1400));
    final app = await seeded();
    final calls = <String>[];
    await t.pumpWidget(host(app, Scaffold(body: HomeScreen(go: (r, [_]) => calls.add(r)))));
    await settle(t);

    await t.tap(find.widgetWithText(FilledButton, '인바디 없이 시작'));
    await settle(t);
    expect(find.byType(EstimateSheet), findsOneWidget);
    expect(find.text('키·체중으로 시작'), findsOneWidget);
    /* 온보딩에서 받은 셋은 한 줄로 — 또 묻지 않습니다. */
    expect(find.text('남성 · 22세 · 187cm'), findsOneWidget);
    expect(find.byKey(const ValueKey('estimate-height')), findsNothing);
    expect(saveEnabled(t), isFalse);

    await t.enterText(find.byKey(_weightKey), '86.7');
    await t.pump();
    /* 저장 전에 무엇이 저장될지 — 추정이라는 것과 오차까지. */
    expect(find.textContaining('골격근 35.7kg'), findsOneWidget);
    expect(find.textContaining('체지방률 22.1%'), findsOneWidget);
    expect(find.descendant(of: find.byType(EstimateSheet), matching: pill('추정')), findsOneWidget);
    expect(find.text(kEstimateCaveat), findsOneWidget);
    expect(saveEnabled(t), isTrue);

    await t.tap(find.byKey(_saveKey));
    await settle(t);
    final scans = app.store.sortedScans();
    expect(scans, hasLength(1));
    expect(scans.single['source'], 'estimate');
    expect(scans.single['smmKg'], 35.7);
    expect(find.byType(EstimateSheet), findsNothing);
    /* 곧장 목표 화면 — 시작하는 이유가 계획입니다. */
    expect(calls, ['goal']);
    expect(t.takeException(), isNull);
  });

  testWidgets('추이 · 빈 화면 — 부담 없는 한 줄, 「인바디 올리기」 · 「인바디 없이 시작」 → 시트 → 목표 화면으로',
      (t) async {
    size(t, const Size(400, 1400));
    final app = await seeded();
    final calls = <String>[];
    await t.pumpWidget(host(app, Scaffold(body: ProgressScreen(go: (r, [_]) => calls.add(r)))));
    await settle(t);
    /* 피드백 51 — 「두 번 이상 넣으면」 은 한 번도 안 넣은 사람에게 짐이었습니다. */
    expect(find.text('인바디를 올리고 확인해보세요!'), findsOneWidget);
    expect(find.textContaining('두 번'), findsNothing);
    /* 홈처럼 주 버튼(올리기)이 먼저, 「없이 시작」 은 보조(tonal). 둘 다 FilledButton
       이라 모양은 칠해진 색으로 가립니다. */
    final cs = Theme.of(t.element(find.byType(ProgressScreen))).colorScheme;
    Color fill(String label) => t
        .widget<Material>(find
            .descendant(of: find.widgetWithText(FilledButton, label), matching: find.byType(Material))
            .first)
        .color!;
    expect(fill('인바디 올리기'), cs.primary, reason: '주 버튼');
    expect(fill('인바디 없이 시작'), cs.secondaryContainer, reason: '보조 버튼(tonal)');
    final up = t.getRect(find.widgetWithText(FilledButton, '인바디 올리기'));
    final est = t.getRect(find.widgetWithText(FilledButton, '인바디 없이 시작'));
    expect(up.top < est.top || (up.top == est.top && up.left < est.left), isTrue, reason: '올리기가 먼저');

    await t.tap(find.widgetWithText(FilledButton, '인바디 올리기'));
    await settle(t);
    expect(calls, ['upload']);

    await t.tap(find.widgetWithText(FilledButton, '인바디 없이 시작'));
    await settle(t);
    expect(find.byType(EstimateSheet), findsOneWidget, reason: '홈과 같은 시트');
    await t.enterText(find.byKey(_weightKey), '86.7');
    await t.pump();
    await t.tap(find.byKey(_saveKey));
    await settle(t);
    expect(app.store.sortedScans().single['source'], 'estimate');
    expect(find.byType(EstimateSheet), findsNothing);
    expect(calls, ['upload', 'goal']);
    /* 저장하면 빈 화면이 추정 한 점으로 바뀝니다. */
    expect(find.textContaining('추정치로 시작했어요.'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('추이 · 빈 화면 — 시트를 그냥 닫으면 아무 데도 안 간다', (t) async {
    size(t, const Size(400, 1400));
    final app = await seeded();
    final calls = <String>[];
    await t.pumpWidget(host(app, Scaffold(body: ProgressScreen(go: (r, [_]) => calls.add(r)))));
    await settle(t);
    await t.tap(find.widgetWithText(FilledButton, '인바디 없이 시작'));
    await settle(t);
    expect(find.byType(EstimateSheet), findsOneWidget);
    await t.tapAt(const Offset(200, 20));
    await settle(t);
    expect(find.byType(EstimateSheet), findsNothing);
    expect(calls, isEmpty);
    expect(app.store.sortedScans(), isEmpty);
  });

  testWidgets('시트 · 완료 키 — 체중이 맞으면 그 자리에서 저장', (t) async {
    size(t, const Size(400, 1400));
    final app = await seeded();
    final calls = <String>[];
    await t.pumpWidget(host(app, Scaffold(body: HomeScreen(go: (r, [_]) => calls.add(r)))));
    await settle(t);
    await t.tap(find.widgetWithText(FilledButton, '인바디 없이 시작'));
    await settle(t);
    await t.enterText(find.byKey(_weightKey), '86.7');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await settle(t);
    expect(app.store.sortedScans(), hasLength(1));
    expect(calls, ['goal']);
  });

  testWidgets('시트 · 프로필이 없으면 성별 · 키 · 나이를 펼쳐 묻고, 다 채워야 저장된다', (t) async {
    size(t, const Size(400, 1400));
    final app = await seeded(withProfile: false);
    final calls = <String>[];
    await t.pumpWidget(host(app, Scaffold(body: HomeScreen(go: (r, [_]) => calls.add(r)))));
    await settle(t);
    await t.tap(find.widgetWithText(FilledButton, '인바디 없이 시작'));
    await settle(t);

    expect(find.byKey(const ValueKey('estimate-basics')), findsNothing);
    expect(find.byKey(const ValueKey('estimate-height')), findsOneWidget);
    expect(find.byKey(const ValueKey('estimate-age')), findsOneWidget);
    expect(find.byType(SegmentedButton<String>), findsOneWidget);

    await t.enterText(find.byKey(_weightKey), '58');
    await t.pump();
    expect(saveEnabled(t), isFalse, reason: '성별 · 키 · 나이 없이 추정하면 안 됩니다');

    await t.tap(find.text('여성'));
    await t.pump();
    await t.enterText(find.byKey(const ValueKey('estimate-height')), '162');
    await t.pump();
    expect(saveEnabled(t), isFalse);
    await t.enterText(find.byKey(const ValueKey('estimate-age')), '25');
    await t.pump();
    expect(saveEnabled(t), isTrue);
    expect(find.textContaining('골격근 19.8kg'), findsOneWidget);
    expect(find.textContaining('체지방률 30.9%'), findsOneWidget);

    await t.tap(find.byKey(_saveKey));
    await settle(t);
    final p = app.profile!;
    expect(p['sex'], 'female');
    expect(core.jsToNumber(p['heightCm']), 162);
    expect(core.jsToNumber(p['age']), 25);
    expect(app.store.sortedScans().single['source'], 'estimate');
    expect(calls, ['goal']);
  });

  testWidgets('시트 · 「바꾸기」 로 기본 정보를 고치면 추정도 · 프로필도 따라간다', (t) async {
    size(t, const Size(400, 1400));
    final app = await seeded();
    await t.pumpWidget(host(app, Scaffold(body: HomeScreen(go: (_, [__]) {}))));
    await settle(t);
    await t.tap(find.widgetWithText(FilledButton, '인바디 없이 시작'));
    await settle(t);
    await t.tap(find.widgetWithText(TextButton, '바꾸기'));
    await t.pump();
    expect(find.byKey(const ValueKey('estimate-basics')), findsNothing);
    /* 펼친 칸은 프로필 값으로 채워져 있습니다. */
    expect(find.widgetWithText(TextField, '187'), findsOneWidget);
    expect(find.widgetWithText(TextField, '22'), findsOneWidget);
    await t.enterText(find.byKey(const ValueKey('estimate-height')), '180');
    await t.enterText(find.byKey(_weightKey), '86.7');
    await t.pump();
    expect(find.textContaining('골격근 35.7kg'), findsNothing);
    await t.tap(find.byKey(_saveKey));
    await settle(t);
    expect(core.jsToNumber(app.profile!['heightCm']), 180);
    /* 다른 칸(활동량 등)은 그대로 */
    expect(app.profile!['activityLevel'], 'moderate');
  });

  testWidgets('업로드 · 측정이 없으면 「키·체중으로 시작」 → 저장하면 목표 화면으로 바뀐다', (t) async {
    size(t, const Size(400, 1400));
    final app = await seeded();
    await t.pumpWidget(host(app, const UploadScreen()));
    await settle(t);
    expect(find.byKey(const ValueKey('upload-estimate')), findsOneWidget);
    expect(find.text('인바디가 없어요 · 키·체중으로 시작'), findsOneWidget);

    await t.tap(find.byKey(const ValueKey('upload-estimate')));
    await settle(t);
    await t.enterText(find.byKey(_weightKey), '86.7');
    await t.pump();
    await t.tap(find.byKey(_saveKey));
    await settle(t);
    expect(t.takeException(), isNull);
    expect(find.byType(GoalScreen), findsOneWidget);
    /* 바꿔 끼웠으니 뒤로 가도 빈 업로드 화면이 아닙니다. */
    expect(find.byType(UploadScreen), findsNothing);
    expect(app.store.sortedScans().single['source'], 'estimate');
  });

  testWidgets('업로드 · 측정(추정이라도)이 있으면 그 버튼은 없다', (t) async {
    size(t, const Size(400, 1400));
    final app = await seeded();
    addEstimate(app);
    await t.pumpWidget(host(app, const UploadScreen()));
    await settle(t);
    expect(find.byKey(const ValueKey('upload-estimate')), findsNothing);
    expect(find.text('숫자 세 개만 넣으면 됩니다 — 나머지는 자동으로 계산합니다'), findsOneWidget);
  });

  /* --- 2. 표시 --------------------------------------------------------------- */

  testWidgets('홈 · 추정 하나 — 「키·체중 추정」 · 「추정」 알약 · 한 줄 안내, 차이 없음', (t) async {
    size(t, const Size(400, 2000));
    final app = await seeded();
    addEstimate(app);
    await t.pumpWidget(host(app, Scaffold(body: HomeScreen(go: (_, [__]) {}))));
    await settle(t);
    expect(find.text('키·체중 추정'), findsOneWidget);
    expect(find.text('최신 인바디'), findsNothing);
    expect(pill('추정'), findsOneWidget);
    expect(find.text(kEstimateHint), findsOneWidget);
    /* 결과지가 아니니 InBody 점수 칸도 없습니다. */
    expect(find.text('InBody 점수'), findsNothing);
    expect(t.widgetList<Stat>(find.byType(Stat)).every((s) => s.delta == null), isTrue);
    expect(t.takeException(), isNull);
  });

  testWidgets('홈 · 실측 뒤에 추정이 섞여 있으면 차이(±)를 안 찍는다', (t) async {
    size(t, const Size(400, 2000));
    final app = await seeded();
    final est = addEstimate(app);
    mixed(app, [{..._real}, est]);                  // 실측 3월 → 추정 9월
    await t.pumpWidget(host(app, Scaffold(body: HomeScreen(go: (_, [__]) {}))));
    await settle(t);
    expect(find.text('키·체중 추정'), findsOneWidget);
    expect(find.text('−2.3'), findsNothing);       // 35.7 − 38.0 은 공식의 오차
    expect(t.widgetList<Stat>(find.byType(Stat)).every((s) => s.delta == null), isTrue);

    /* 반대 — 추정 뒤에 실측: 제목은 「최신 인바디」, 그래도 차이는 없습니다. */
    mixed(app, [{...est, 'measuredAt': '2026-02-01T00:00:00.000Z'}, {..._real}]);
    await t.pumpWidget(host(app, Scaffold(body: HomeScreen(go: (_, [__]) {}))));
    await settle(t);
    expect(find.text('최신 인바디'), findsOneWidget);
    expect(pill('추정'), findsNothing);
    expect(t.widgetList<Stat>(find.byType(Stat)).every((s) => s.delta == null), isTrue);
  });

  testWidgets('측정 자세히 · 추정 — 「추정치예요」 · 「추정값」 · 「이 추정 지우기」, 검산 없음', (t) async {
    size(t, const Size(400, 1600));
    final app = await seeded();
    final est = addEstimate(app);
    await t.pumpWidget(host(app, ScanDetailScreen(scanId: est['id'])));
    await settle(t);
    expect(find.textContaining('추정치예요.'), findsOneWidget);
    expect(find.textContaining(kEstimateCaveat), findsOneWidget);
    expect(find.text('추정값'), findsOneWidget);
    expect(pill('추정'), findsOneWidget);
    expect(find.text('결과지 값'), findsNothing);
    expect(find.text('계산값'), findsNothing);
    expect(find.text('이 추정 지우기'), findsOneWidget);
    /* 추정을 실측으로 바꾸는 길이 숫자 바로 위에 */
    await t.tap(find.widgetWithText(FilledButton, '인바디 올리기'));
    await settle(t);
    expect(find.byType(UploadScreen), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('측정 자세히 · 추정에서 「인바디 올리기」 → 실측 저장 뒤 「찾지 못했습니다」 로 안 돌아온다', (t) async {
    size(t, const Size(400, 1600));
    final app = await seeded();
    addEstimate(app);
    await t.pumpWidget(host(app, const HistoryScreen()));
    await settle(t);
    await t.tap(find.byType(ListTile));
    await settle(t);
    expect(find.byType(ScanDetailScreen), findsOneWidget);

    await t.tap(find.widgetWithText(FilledButton, '인바디 올리기'));
    await settle(t);
    expect(find.byType(UploadScreen), findsOneWidget);
    /* 업로드 화면이 자세히 화면을 바꿔 끼웠습니다 — 밑에 깔려 있지 않습니다. */
    expect(find.byType(ScanDetailScreen, skipOffstage: false), findsNothing);

    /* 검수 화면이 실측을 저장하고(정리가 추정을 지움) 닫히는 것과 같은 일 */
    app.store.addScan({..._real, 'measuredAt': DateTime.now().toUtc().toIso8601String()});
    await settle(t);
    expect(app.store.sortedScans().where(isEstimate), isEmpty);
    Navigator.of(t.element(find.byType(UploadScreen))).pop();
    await settle(t);
    expect(find.text('그 측정을 찾지 못했습니다'), findsNothing);
    expect(find.byType(HistoryScreen), findsOneWidget);
    expect(pill('추정'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('측정 자세히 · 실측은 그대로 — 「결과지 값」 · 「이 측정 지우기」', (t) async {
    size(t, const Size(400, 1600));
    final app = await seeded();
    app.store.addScan({..._real});
    await t.pumpWidget(host(app, const ScanDetailScreen(scanId: 'r1')));
    await settle(t);
    expect(find.text('결과지 값'), findsOneWidget);
    expect(find.text('이 측정 지우기'), findsOneWidget);
    expect(find.textContaining('추정치예요.'), findsNothing);
    expect(pill('추정'), findsNothing);
  });

  testWidgets('기록 · 추정 줄에만 「추정」', (t) async {
    size(t, const Size(400, 1000));
    final app = await seeded();
    final est = addEstimate(app);
    mixed(app, [{..._real}, est]);
    await t.pumpWidget(host(app, const HistoryScreen()));
    await settle(t);
    expect(find.byType(ListTile), findsNWidgets(2));
    expect(pill('추정'), findsOneWidget);
    final estRow = find.ancestor(of: pill('추정'), matching: find.byType(ListTile));
    expect(find.descendant(of: estRow, matching: find.textContaining('근 35.7')), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('플랜 탭 · 홈 목표 카드 — 추정 위에 세운 계획에 「추정 기준」', (t) async {
    size(t, const Size(400, 3000));
    final app = await seeded();
    final est = addEstimate(app);
    final plan = estimatePlan(app, est);
    expect(planFromEstimate(app.state['plan']), isTrue, reason: '저장소가 도장을 지우면 안 됩니다');

    await t.pumpWidget(host(app, Scaffold(body: PlanScreen(go: (_, [__]) {}, today: DateTime(2026, 9, 21)))));
    await settle(t);
    expect(pill('추정 기준'), findsOneWidget);
    expect(find.text(kEstimateHint), findsOneWidget);
    expect(t.takeException(), isNull);

    await t.pumpWidget(host(app, Scaffold(body: HomeScreen(go: (_, [__]) {}))));
    await settle(t);
    expect(find.text('목표까지'), findsOneWidget);
    expect(pill('추정 기준'), findsOneWidget);
    expect(t.takeException(), isNull);

    /* 도장이 없는 계획(실측 · 옛 계획)에는 없습니다. */
    app.store.setPlan({...plan}..remove('fromEstimate'));
    await t.pumpWidget(host(app, Scaffold(body: PlanScreen(go: (_, [__]) {}, today: DateTime(2026, 9, 21)))));
    await settle(t);
    expect(pill('추정 기준'), findsNothing);
  });

  /* --- 3. 추이 --------------------------------------------------------------- */

  testWidgets('추이 · 추정뿐 — 「추정치로 시작했어요」, 골격근 · 체지방률에만 「추정」', (t) async {
    size(t, const Size(400, 3000));
    final app = await seeded();
    addEstimate(app);
    await t.pumpWidget(host(app, Scaffold(body: ProgressScreen(go: (_, [__]) {}))));
    await settle(t);
    expect(find.textContaining('추정치로 시작했어요.'), findsOneWidget);
    expect(find.textContaining('첫 측정이에요'), findsNothing);
    expect(find.text('처음부터 지금까지'), findsNothing);
    expect(pill('추정'), findsNWidgets(2));
    Finder card(String title) =>
        find.ancestor(of: find.widgetWithText(SectionTitle, title), matching: find.byType(MbCard));
    /* 체중은 저울 값 — 알약이 없습니다. */
    expect(find.descendant(of: card('체중'), matching: find.byType(Pill)), findsNothing);
    expect(find.descendant(of: card('골격근'), matching: pill('추정')), findsOneWidget);
    expect(find.descendant(of: card('체지방률'), matching: pill('추정')), findsOneWidget);
    expect(find.text('측정 기록 1건'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('추이 · 추정과 실측이 섞이면 선은 실측만 — 추정 → 실측의 선은 없다', (t) async {
    size(t, const Size(400, 3000));
    final app = await seeded();
    final est = addEstimate(app);
    mixed(app, [{...est, 'measuredAt': '2026-02-01T00:00:00.000Z'}, {..._real}]);
    await t.pumpWidget(host(app, Scaffold(body: ProgressScreen(go: (_, [__]) {}))));
    await settle(t);
    final charts = t.widgetList<LineChart>(find.byType(LineChart)).toList();
    expect(charts, hasLength(3));
    for (final c in charts) {
      expect(c.series.first.points, hasLength(1), reason: '${c.series.first.label} 에 추정 점이 섞임');
    }
    expect(charts[0].series.first.points.single.y, 86.7);
    expect(charts[1].series.first.points.single.y, 38.0);
    expect(charts[2].series.first.points.single.y, closeTo(23.1, 0.05));
    expect(pill('추정'), findsNothing);
    expect(find.textContaining('추정치로 시작했어요.'), findsNothing);
    expect(find.textContaining('첫 측정이에요'), findsOneWidget);
    /* 기록 수는 전부 — 추정도 기록 화면에서 보고 지울 수 있습니다. */
    expect(find.text('측정 기록 2건'), findsOneWidget);
  });

  /* --- 4. 실측으로 바뀐 알림 ------------------------------------------------- */

  Map<String, Object?> record(String plan, {Duration ago = Duration.zero}) => {
        'at': DateTime.now().subtract(ago).toUtc().toIso8601String(),
        'before': {'weightKg': 86.7, 'smmKg': 35.7, 'bfmKg': 19.2, 'pbfPct': 22.1},
        'after': {'weightKg': 86.7, 'smmKg': 38.0, 'bfmKg': 20.0, 'pbfPct': 23.1},
        'plan': plan,
        'goalBefore': plan == 'none' ? null : {'weightKg': 81.6, 'smmKg': 36.7, 'bfmKg': 12.2},
        'goalAfter': plan == 'none' ? null : {'weightKg': 81.6, 'smmKg': 39.0, 'bfmKg': 13.1},
        'weeksBefore': plan == 'none' ? null : 30,
        'weeksAfter': plan == 'rebuilt' ? 27 : null,
        'reason': plan == 'needsGoal' ? '체지방률 하한' : null,
      };

  Future<AppState> upgraded(String plan, {Duration ago = Duration.zero}) async {
    final app = await seeded();
    app.store.addScan({..._real});
    app.store.set({kEstimateUpgradeKey: record(plan, ago: ago)});
    return app;
  }

  const cardKey = ValueKey('estimate-upgrade-card');

  testWidgets('홈 · 실측으로 바뀌면 맨 위 카드 — 전후 숫자와 다시 세운 목표 · 닫으면 seen', (t) async {
    size(t, const Size(400, 2400));
    final app = await upgraded('rebuilt');
    await t.pumpWidget(host(app, Scaffold(body: HomeScreen(go: (_, [__]) {}))));
    await settle(t);
    expect(find.byKey(cardKey), findsOneWidget);
    expect(find.text('실측으로 바꿨어요'), findsOneWidget);
    expect(find.textContaining('35.7 → 38.0kg'), findsOneWidget);
    expect(find.textContaining('22.1 → 23.1%'), findsOneWidget);
    expect(find.textContaining('목표도 실측에 맞췄어요'), findsOneWidget);
    expect(find.textContaining('36.7 → 39.0kg'), findsOneWidget);
    expect(find.textContaining('30 → 27주'), findsOneWidget);
    /* 브리핑보다 위 */
    expect(t.getTopLeft(find.byKey(cardKey)).dy,
        lessThan(t.getTopLeft(find.byType(BriefingCard)).dy));

    await t.tap(find.byKey(const ValueKey('estimate-upgrade-close')));
    await settle(t);
    expect(find.byKey(cardKey), findsNothing);
    expect((app.state[kEstimateUpgradeKey] as Map)['seen'], isTrue);
    expect(t.takeException(), isNull);
  });

  testWidgets('홈 · 실측 기준으로 원래 목표가 무리면 「목표 다시 정하기」 → go(goal)', (t) async {
    size(t, const Size(400, 2400));
    final app = await upgraded('needsGoal');
    final calls = <String>[];
    await t.pumpWidget(host(app, Scaffold(body: HomeScreen(go: (r, [_]) => calls.add(r)))));
    await settle(t);
    expect(find.textContaining('원래 목표가 무리예요'), findsOneWidget);
    expect(find.textContaining('목표도 실측에 맞췄어요'), findsNothing);
    await t.tap(find.widgetWithText(FilledButton, '목표 다시 정하기'));
    await t.pump();
    expect(calls, contains('goal'));
  });

  testWidgets('홈 · 「다시 정해 주세요」 는 새 계획을 세우면 사라지고 숫자 한 줄만 남는다', (t) async {
    size(t, const Size(400, 2400));
    final app = await upgraded('needsGoal');
    /* 버튼으로 목표 화면에 가서 새 계획을 세우고 돌아온 상태 */
    estimatePlan(app, {..._real}, day: app.store.dayKey(), stamp: false,
        goal: {'weightKg': 81.6, 'smmKg': 39.0, 'bfmKg': 13.1});
    await t.pumpWidget(host(app, Scaffold(body: HomeScreen(go: (_, [__]) {}))));
    await settle(t);
    expect(find.byKey(cardKey), findsOneWidget);
    expect(find.textContaining('35.7 → 38.0kg'), findsOneWidget);
    expect(find.textContaining('원래 목표가 무리예요'), findsNothing);
    expect(find.text('목표 다시 정하기'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('홈 · 계획이 없던 사람(plan none) — 숫자 한 줄만', (t) async {
    size(t, const Size(400, 2400));
    final app = await upgraded('none');
    await t.pumpWidget(host(app, Scaffold(body: HomeScreen(go: (_, [__]) {}))));
    await settle(t);
    expect(find.byKey(cardKey), findsOneWidget);
    expect(find.textContaining('35.7 → 38.0kg'), findsOneWidget);
    expect(find.textContaining('목표도 실측에 맞췄어요'), findsNothing);
    expect(find.textContaining('원래 목표가 무리예요'), findsNothing);
    expect(find.text('목표 다시 정하기'), findsNothing);
  });

  testWidgets('끝까지 — 추정으로 세운 계획 → 실측이 들어오면 추정은 사라지고 홈에 알림 한 번', (t) async {
    size(t, const Size(400, 2600));
    final app = await seeded();
    final est = addEstimate(app, at: DateTime.now().toUtc().subtract(const Duration(days: 3)));
    estimatePlan(app, est, day: app.store.dayKey());

    /* 실측이 들어옵니다(동기화 · 다른 기기처럼 — 검수 화면을 안 거치는 길). 앱의
       정리(AppState 의 onChange)가 한 박자 뒤에 돕니다. */
    app.store.addScan({..._real, 'measuredAt': DateTime.now().toUtc().toIso8601String()});
    await t.pumpWidget(host(app, Scaffold(body: HomeScreen(go: (_, [__]) {}))));
    await settle(t);

    expect(app.store.sortedScans().where(isEstimate), isEmpty);
    expect(find.byKey(cardKey), findsOneWidget);
    expect(find.textContaining('35.7 → 38.0kg'), findsOneWidget);
    expect(find.textContaining('22.1 → 23.1%'), findsOneWidget);
    /* 목표는 골격근 변화량(+1.0kg)을 옮겨 다시 섰고, 새 계획이 목표 카드에 나옵니다. */
    expect((app.state[kEstimateUpgradeKey] as Map)['plan'], 'rebuilt');
    expect(find.textContaining('목표도 실측에 맞췄어요 · 골격근 36.7 → 39.0kg'), findsOneWidget);
    expect(find.text('목표까지'), findsOneWidget);
    /* 추정 표시는 전부 사라집니다. */
    expect(find.text('최신 인바디'), findsOneWidget);
    expect(find.text('키·체중 추정'), findsNothing);
    expect(pill('추정'), findsNothing);
    expect(pill('추정 기준'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('홈 · 8일 지난 알림은 안 뜬다', (t) async {
    size(t, const Size(400, 2400));
    final app = await upgraded('rebuilt', ago: const Duration(days: 8));
    await t.pumpWidget(host(app, Scaffold(body: HomeScreen(go: (_, [__]) {}))));
    await settle(t);
    expect(find.byKey(cardKey), findsNothing);
    expect(find.text('실측으로 바꿨어요'), findsNothing);
  });

  /* --- 5. 키보드 · 폭 ----------------------------------------------------------- */

  testWidgets('시트 · 키보드(300px)가 올라와도 「추정치로 시작」 이 그 위에 보인다', (t) async {
    const phone = Size(360, 740);
    size(t, phone);
    final app = await seeded();
    await t.pumpWidget(host(app, Scaffold(body: HomeScreen(go: (_, [__]) {}))));
    await settle(t);
    await t.tap(find.widgetWithText(FilledButton, '인바디 없이 시작'));
    await settle(t);
    t.view.viewInsets = const FakeViewPadding(bottom: 300);
    await t.enterText(find.byKey(_weightKey), '86.7');
    await settle(t);
    final r = t.getRect(find.byKey(_saveKey));
    expect(r.bottom, lessThanOrEqualTo(phone.height - 300), reason: '키보드 뒤에 깔림: $r');
    expect(r.top, greaterThanOrEqualTo(0));
    expect(t.takeException(), isNull);
  });

  for (final v in [
    (name: '밝은 테마', theme: mbLight()),
    (name: '어두운 테마', theme: mbDark()),
  ]) {
    group('360px · 글자 1.3배 · ${v.name}', () {
      Future<void> narrow(WidgetTester t) async {
        size(t, const Size(360, 800));
        t.platformDispatcher.textScaleFactorTestValue = 1.3;
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      }

      Future<void> clean(WidgetTester t) async {
        expect(t.takeException(), isNull);
        expect(find.byType(ErrorWidget), findsNothing);
      }

      testWidgets('홈 · 빈 화면', (t) async {
        await narrow(t);
        final app = await seeded();
        await t.pumpWidget(host(app, Scaffold(body: HomeScreen(go: (_, [__]) {})), theme: v.theme));
        await settle(t);
        await clean(t);
        expect(find.widgetWithText(FilledButton, '인바디 없이 시작'), findsOneWidget);
      });

      /* 폭이 좁으면 두 번째 버튼이 다음 줄로 — 높이까지 모자라면(분할 화면 · 낮은 창)
         넘치지 않고 밀려야 합니다. 셸처럼 제목줄 · 아래 탭까지 두고 봅니다. */
      for (final h in [800.0, 400.0]) {
        testWidgets('추이 · 빈 화면 — 360×${h.round()} 에서도 두 버튼이 넘치지 않고 눌린다', (t) async {
          await narrow(t);
          size(t, Size(360, h));
          final app = await seeded();
          await t.pumpWidget(host(
              app,
              Scaffold(
                appBar: AppBar(title: const Text('추이')),
                body: SafeArea(child: ProgressScreen(go: (_, [__]) {})),
                bottomNavigationBar: NavigationBar(destinations: const [
                  NavigationDestination(icon: Icon(Icons.home), label: '홈'),
                  NavigationDestination(icon: Icon(Icons.show_chart), label: '추이'),
                ]),
              ),
              theme: v.theme));
          await settle(t);
          await clean(t);
          for (final label in ['인바디 올리기', '인바디 없이 시작']) {
            final b = find.widgetWithText(FilledButton, label);
            expect(b, findsOneWidget);
            await t.ensureVisible(b);
            await settle(t);
            expect(b.hitTestable(), findsOneWidget, reason: '「$label」 이 가려지거나 잘림');
            final r = t.getRect(b);
            expect(r.left >= 0 && r.right <= 360, isTrue, reason: '「$label」 이 화면 밖: $r');
          }
        });
      }

      testWidgets('시트 · 접힌 기본 정보 + 미리보기, 그리고 펼친 칸', (t) async {
        await narrow(t);
        final app = await seeded();
        await t.pumpWidget(host(app, Scaffold(body: HomeScreen(go: (_, [__]) {})), theme: v.theme));
        await settle(t);
        await t.tap(find.widgetWithText(FilledButton, '인바디 없이 시작'));
        await settle(t);
        await t.enterText(find.byKey(_weightKey), '86.7');
        await settle(t);
        await clean(t);
        expect(find.byKey(const ValueKey('estimate-basics')), findsOneWidget);
        expect(find.textContaining('골격근 35.7kg'), findsOneWidget);

        await t.tap(find.widgetWithText(TextButton, '바꾸기'));
        await settle(t);
        await clean(t);
        expect(find.byKey(const ValueKey('estimate-height')), findsOneWidget);
        await t.ensureVisible(find.byKey(_saveKey));
        await settle(t);
        await clean(t);
      });

      testWidgets('시트 · 프로필 없음(펼친 채로 시작)', (t) async {
        await narrow(t);
        final app = await seeded(withProfile: false);
        await t.pumpWidget(host(app, Scaffold(body: HomeScreen(go: (_, [__]) {})), theme: v.theme));
        await settle(t);
        await t.tap(find.widgetWithText(FilledButton, '인바디 없이 시작'));
        await settle(t);
        await clean(t);
        expect(find.byKey(const ValueKey('estimate-age')), findsOneWidget);
      });

      testWidgets('홈 · 추정 하나', (t) async {
        await narrow(t);
        final app = await seeded();
        addEstimate(app);
        await t.pumpWidget(host(app, Scaffold(body: HomeScreen(go: (_, [__]) {})), theme: v.theme));
        await settle(t);
        await clean(t);
        expect(find.text('키·체중 추정'), findsOneWidget);
      });

      for (final plan in ['rebuilt', 'needsGoal']) {
        testWidgets('홈 · 실측으로 바뀐 카드 ($plan)', (t) async {
          await narrow(t);
          final app = await upgraded(plan);
          await t.pumpWidget(host(app, Scaffold(body: HomeScreen(go: (_, [__]) {})), theme: v.theme));
          await settle(t);
          await clean(t);
          expect(find.byKey(cardKey), findsOneWidget);
        });
      }

      testWidgets('추이 · 추정뿐', (t) async {
        await narrow(t);
        final app = await seeded();
        addEstimate(app);
        await t.pumpWidget(host(app, Scaffold(body: ProgressScreen(go: (_, [__]) {})), theme: v.theme));
        await settle(t);
        await clean(t);
        expect(pill('추정'), findsNWidgets(2));
      });

      testWidgets('측정 자세히 · 추정', (t) async {
        await narrow(t);
        final app = await seeded();
        final est = addEstimate(app);
        await t.pumpWidget(host(app, ScanDetailScreen(scanId: est['id']), theme: v.theme));
        await settle(t);
        await clean(t);
      });

      testWidgets('업로드 · 「인바디가 없어요 · 키·체중으로 시작」', (t) async {
        await narrow(t);
        final app = await seeded();
        await t.pumpWidget(host(app, const UploadScreen(), theme: v.theme));
        await settle(t);
        await clean(t);
        expect(find.byKey(const ValueKey('upload-estimate')), findsOneWidget);
      });

      testWidgets('기록 · 추정 줄', (t) async {
        await narrow(t);
        final app = await seeded();
        final est = addEstimate(app);
        mixed(app, [{..._real}, est]);
        await t.pumpWidget(host(app, const HistoryScreen(), theme: v.theme));
        await settle(t);
        await clean(t);
        expect(pill('추정'), findsOneWidget);
      });

      testWidgets('플랜 탭 · 홈 목표 카드 — 「추정 기준」', (t) async {
        await narrow(t);
        final app = await seeded();
        estimatePlan(app, addEstimate(app));
        await t.pumpWidget(host(
            app, Scaffold(body: PlanScreen(go: (_, [__]) {}, today: DateTime(2026, 9, 21))),
            theme: v.theme));
        await settle(t);
        await clean(t);
        expect(pill('추정 기준'), findsOneWidget);
        await t.pumpWidget(host(app, Scaffold(body: HomeScreen(go: (_, [__]) {})), theme: v.theme));
        await settle(t);
        await clean(t);
        expect(pill('추정 기준'), findsOneWidget);
      });
    });
  }
}
