/* 「뭘 먹을까」 카드 — 피드백 36 뒤의 모양.
 *
 * 오른쪽 위에 남은 kcal 와 단백질, 옵션 줄은 kcal 먼저, 카드 아래에 "단백질 N g 은
 * 간식으로" 한 줄(누르면 간식 모드). 360px 폭에서 넘치지 않아야 합니다. */
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:mybody/src/api.dart';
import 'package:mybody/src/app_state.dart';
import 'package:mybody/src/scope.dart';
import 'package:mybody/src/screens/food.dart';
import 'package:mybody/src/theme.dart';
import 'package:mybody_core/mybody_core.dart' as core;
import 'package:shared_preferences/shared_preferences.dart';

const _scan = {
  'id': 's1', 'weightKg': 86.7, 'smmKg': 38.0, 'bfmKg': 20.0,
  'pbfPct': 23.1, 'ffmKg': 66.7, 'bmi': 24.8, 'bmrKcal': 1810,
  'measuredAt': '2026-03-01T00:00:00.000Z',
};
const _profile = {
  'sex': 'male', 'age': 22, 'heightCm': 187, 'activityLevel': 'moderate',
  'trainingAge': 'novice', 'daysPerWeek': 4, 'mealsPerDay': 3,
};

/* 서버는 없습니다 — 모든 요청에 404. */
Widget host(AppState app, Widget child) {
  final api = Api(baseUrl: '', client: MockClient((_) async => http.Response('{"ok":false}', 404)));
  api.setToken('tok');
  return Scope(
      state: app, api: api, onServerChange: (_) async {},
      child: MaterialApp(theme: mbLight(), home: child));
}

Future<AppState> seeded() async {
  SharedPreferences.setMockInitialValues({});
  final app = await AppState.boot();
  app.store.set({'profile': _profile, 'onboarded': true});
  app.store.addScan({..._scan});
  final goal = {'weightKg': 80.5, 'smmKg': 39.0, 'bfmKg': 12.0};
  final cmp = core.compareLevels({..._scan}, _profile, goal, '2026-03-01', null, null);
  final plan = core.buildPlan(cmp, 'mid', {..._scan}, _profile);
  app.store.setGoal(goal);
  if (plan != null) app.store.setPlan(plan);
  return app;
}

void noop(String route, [Object? arg]) {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> openSheet(WidgetTester t, AppState app, {double width = 360}) async {
    t.view.physicalSize = Size(width, 1400);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(host(app, Scaffold(body: FoodScreen(go: noop))));
    await t.pump(const Duration(milliseconds: 200));
    await t.tap(find.textContaining('뭘 먹을까'));
    await t.pumpAndSettle();
    // 시각에 따라 첫 모드가 다릅니다(점심·저녁이면 사먹기). 시험은 사먹기로 고정합니다.
    await t.tap(find.text('사먹기'));
    await t.pumpAndSettle();
  }

  testWidgets('카드 오른쪽 위에 남은 kcal · 단백질, 옵션 줄은 kcal 먼저 — 360px 에서 안 넘친다', (t) async {
    final app = await seeded();
    await openSheet(t, app);
    expect(t.takeException(), isNull, reason: '넘침(overflow)도 예외로 잡힙니다');
    expect(find.byType(ErrorWidget), findsNothing);

    final trailing = find.textContaining(RegExp(r'^남은 \d+kcal · 단백질 \d+g$'));
    expect(trailing, findsOneWidget, reason: '단백질만이 아니라 남은 kcal 도 보여야 맥락이 읽힙니다');

    final lines = find.textContaining(RegExp(r'^\d+kcal · 단백질 \d+g'));
    expect(lines, findsWidgets, reason: '옵션 줄은 kcal 먼저');
    expect(find.textContaining(RegExp(r'^단백질 \d+g · \d+kcal')), findsNothing, reason: '예전 순서가 남으면 안 됩니다');
    expect(find.text('기록에 담기'), findsWidgets);
  });

  testWidgets('한 끼 예산 — 보이는 옵션은 남은 kcal ÷ 남은 끼니 × 1.15 안이다', (t) async {
    final app = await seeded();
    await openSheet(t, app);
    final trailing = t.widget<Text>(find.textContaining(RegExp(r'^남은 \d+kcal'))).data!;
    final remainK = int.parse(RegExp(r'남은 (\d+)kcal').firstMatch(trailing)!.group(1)!);
    // 아무것도 안 먹은 날 — 세 끼가 남았습니다.
    final cap = remainK / 3 * core.kMealCapRatio;
    final kcals = [
      for (final e in find.textContaining(RegExp(r'^\d+kcal · 단백질')).evaluate())
        int.parse(RegExp(r'^(\d+)kcal').firstMatch((e.widget as Text).data!)!.group(1)!),
    ];
    expect(kcals, isNotEmpty);
    for (final k in kcals) {
      expect(k <= cap + 0.5, isTrue, reason: '$k kcal > 상한 ${cap.round()} (남은 $remainK)');
    }
  });

  testWidgets('"단백질 N g 은 간식으로" 한 줄 — 누르면 간식 모드로 넘어가고 줄은 사라진다', (t) async {
    final app = await seeded();
    await openSheet(t, app);
    final hint = find.byKey(const Key('suggest-snack-hint'));
    expect(hint, findsOneWidget, reason: '아무것도 안 먹은 날은 끼니 몫을 빼고도 단백질이 남습니다');
    expect(find.textContaining('간식으로 — 그릭요거트'), findsOneWidget);
    expect(find.byIcon(LucideIcons.cookie), findsOneWidget);

    await t.tap(hint);
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    final snackChip = t.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '간식'));
    expect(snackChip.selected, isTrue, reason: '간식 모드로 전환');
    expect(find.byKey(const Key('suggest-snack-hint')), findsNothing, reason: '간식 모드에는 안내가 없습니다');
    expect(find.text('기록에 담기'), findsWidgets, reason: '간식 추천이 뜬다');
  });

  testWidgets('글자 1.3배 · 360px — 남은 kcal 줄은 한 줄(줄임표), 제목 「뭘 먹을까」 는 두 줄로 접히지 않는다', (t) async {
    final app = await seeded();
    t.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    /* 식단 탭 자체는 1.3배 · 360px 에서 카드 밖 어딘가가 60px 넘칩니다(기존 · 이 카드와 무관).
       여기서 보는 것은 「뭘 먹을까」 카드라 그 예외는 비우고 시작합니다. */
    t.view.physicalSize = const Size(360, 1400);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(host(app, Scaffold(body: FoodScreen(go: noop))));
    await t.pump(const Duration(milliseconds: 200));
    t.takeException();
    await t.tap(find.textContaining('뭘 먹을까'));
    await t.pumpAndSettle();
    await t.tap(find.text('사먹기'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull, reason: '카드는 1.3배에서도 넘치지 않습니다');
    final remain = t.renderObject<RenderParagraph>(find.byKey(const Key('suggest-remain')));
    final oneLine = remain.getMinIntrinsicHeight(double.infinity);
    expect(remain.size.height, lessThanOrEqualTo(oneLine + 0.01), reason: '한 줄 — 넘치면 줄임표');
    final title = t.renderObject<RenderParagraph>(find.text('뭘 먹을까').last);
    expect(title.didExceedMaxLines, isFalse);
    expect(title.size.height, lessThan(title.getMinIntrinsicHeight(double.infinity) * 2), reason: '제목은 한 줄');
  });

  testWidgets('집밥 모드에도 남은 kcal 와 간식 안내가 있고 412px 에서도 선다', (t) async {
    final app = await seeded();
    await openSheet(t, app, width: 412);
    await t.tap(find.text('집밥'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(find.textContaining(RegExp(r'^남은 \d+kcal · 단백질 \d+g$')), findsOneWidget);
    expect(find.byKey(const Key('suggest-snack-hint')), findsOneWidget);
    expect(find.textContaining(RegExp(r'^\d+kcal · 단백질 \d+g')), findsWidgets);
  });
}
