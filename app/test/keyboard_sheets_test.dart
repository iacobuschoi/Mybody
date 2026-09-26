/* =============================================================================
 * keyboard_sheets_test.dart — 시트 · 다이얼로그 · 검색 화면에서 키보드가 길을 막지 않는가
 *
 * 주인이 아이폰에서 잡은 버그(숫자 키보드가 안 사라져 확인을 못 누름)를 앱 전체로
 * 넓혀 봅니다. 여기서 보는 화면: 식단의 「끼니에 추가」 검색과 직접 입력 다이얼로그,
 * 종목 고르기 시트(기구 설정 → 익숙한 종목), 헬스 · 유산소 종료 시트, 친구의 초대
 * 코드 다이얼로그. 화면마다 셋을 봅니다:
 *
 *   1. 키보드 300px 을 흉내(viewInsets) 낸 채로 확인 · 저장 버튼이 키보드 위 보이는
 *      영역에 통째로 있고 실제로 눌리는가.
 *   2. 칸 밖(빈 곳 · 제목 · 행)을 탭하거나 목록을 끌면 키보드가 내려가는가 — 전역
 *      「바깥 탭」 제스처(ui/edge.dart)와 화면의 버튼 · 행 · 칩이 부딪히지 않는가.
 *   3. 「다음」 키가 다음 칸으로, 마지막 칸의 완료가 제출로 가는가.
 *
 * 360×740(안드로이드 기본) · 390×844(아이폰) 둘 다.
 * ========================================================================== */
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mybody/src/api.dart';
import 'package:mybody/src/app_state.dart';
import 'package:mybody/src/scope.dart';
import 'package:mybody/src/screens/exercise_picker.dart';
import 'package:mybody/src/screens/food.dart';
import 'package:mybody/src/screens/gym_settings.dart';
import 'package:mybody/src/screens/social.dart';
import 'package:mybody/src/screens/workout_session.dart';
import 'package:mybody/src/screens/workout_tutorial.dart';
import 'package:mybody/src/theme.dart';
import 'package:mybody/src/ui/edge.dart';
import 'package:mybody/src/workout/prefs.dart';
import 'package:mybody_core/mybody_core.dart' as core;
import 'package:shared_preferences/shared_preferences.dart';

/// 흉내 내는 키보드 높이(논리 px · dpr 1.0).
const double _kb = 300;

/// 두 폰 크기. 아이폰은 390×844 — 주인이 버그를 본 크기대입니다.
const _phones = <String, Size>{
  '360×740': Size(360, 740),
  '390×844 아이폰': Size(390, 844),
};

const _scan = {
  'id': 's1', 'weightKg': 86.7, 'smmKg': 38.0, 'bfmKg': 20.0,
  'pbfPct': 23.1, 'ffmKg': 66.7, 'bmi': 24.8, 'bmrKcal': 1810,
  'measuredAt': '2026-03-01T00:00:00.000Z',
};
const _profile = {
  'sex': 'male', 'age': 22, 'heightCm': 187, 'activityLevel': 'moderate',
  'trainingAge': 'novice', 'daysPerWeek': 4, 'mealsPerDay': 3,
};

/// 시험의 오늘 — 운동 화면은 앞날이면 저장을 막으므로 시계와 날짜를 같이 세웁니다.
final _today = DateTime(2026, 9, 27, 18, 0);
const _todayKey = '2026-09-27';

/// 서버 흉내. [routes] 에 있는 길은 200 + 그 몸, 나머지는 404. 나간 요청을 전부
/// [sent] 에 남겨 무엇이 나갔는지 봅니다 — 요청 뒤에 화면이 목록을 다시 읽으므로
/// 「마지막 요청」 만 보면 안 됩니다.
class _Server {
  _Server(this.routes);
  final Map<String, Object> routes;
  final sent = <(String path, Map<String, dynamic>? body)>[];

  Api api() {
    http.Response json(Object body, int status) => http.Response.bytes(
          utf8.encode(jsonEncode(body)), status,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
    final a = Api(
      baseUrl: 'https://x.test',
      client: MockClient((req) async {
        final path = req.url.path.replaceFirst('/api', '');
        sent.add((path, req.body.isEmpty ? null : (jsonDecode(req.body) as Map).cast<String, dynamic>()));
        final v = routes[path];
        return v == null ? json({'ok': false, 'reason': '없는 길'}, 404) : json(v, 200);
      }),
    );
    a.setToken('tok');
    return a;
  }
}

Future<AppState> _seeded() async {
  SharedPreferences.setMockInitialValues({});
  final app = await AppState.boot();
  app.store.now = () => _today;
  app.store.set({
    'profile': _profile,
    'onboarded': true,
    /* 헬스 화면의 튜토리얼 · 첫 줄 힌트는 본 것으로 — 이 시험의 관심사가 아닙니다. */
    'settings': {kGymTutorialSeenKey: true, kGymSwipeHintSeenKey: true},
  });
  app.store.addScan({..._scan});
  return app;
}

void _phone(WidgetTester t, Size size) {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
}

/// 앱과 같은 겹: Scope > MaterialApp(builder: edgeSafe — 바깥 탭 닫기) > [home].
/// [push] 를 주면 첫 화면의 「열기」 로 밀어 올립니다 — 저장하면 pop 하는 화면은
/// 돌아갈 자리가 있어야 합니다.
Future<void> _host(WidgetTester t, {required AppState app, Api? api, Widget? home, Widget? push}) async {
  await t.pumpWidget(Scope(
    state: app,
    api: api ?? _Server(const {}).api(),
    onServerChange: (_) async {},
    child: MaterialApp(
      theme: mbLight(),
      builder: edgeSafe,
      home: home ??
          Builder(
            builder: (c) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(c).push(MaterialPageRoute(builder: (_) => push!)),
                  child: const Text('열기'),
                ),
              ),
            ),
          ),
    ),
  ));
  if (push != null) {
    await t.tap(find.text('열기'));
    await t.pumpAndSettle();
  } else {
    await t.pumpAndSettle();
  }
}

/// 키보드가 올라온 것처럼 — 실제 폰에서 키보드가 뜨면 viewInsets.bottom 이 이만큼 됩니다.
Future<void> _keyboardUp(WidgetTester t) async {
  t.view.viewInsets = const FakeViewPadding(bottom: _kb);
  await t.pumpAndSettle();
}

/// 어느 칸이 시스템 키보드에 붙어 있는가 — 실제 폰에서 키보드가 떠 있는 것과 같습니다.
bool _typing(WidgetTester t) => t.testTextInput.hasAnyClients;

Finder _field(String label) => find.widgetWithText(TextField, label);

bool _focused(WidgetTester t, Finder field) => t
    .widget<EditableText>(find.descendant(of: field, matching: find.byType(EditableText)))
    .focusNode
    .hasPrimaryFocus;

Future<void> _focus(WidgetTester t, Finder field) async {
  await t.tap(field);
  await t.pumpAndSettle();
  expect(_typing(t), isTrue, reason: '$field 칸을 탭했는데 키보드가 안 붙음');
}

Future<void> _key(WidgetTester t, TextInputAction a) async {
  await t.testTextInput.receiveAction(a);
  await t.pumpAndSettle();
}

/// 버튼이 키보드(아래 [_kb]px) 위 보이는 영역 안에 통째로 있는가.
void _aboveKeyboard(WidgetTester t, Finder button, Size size) {
  expect(button, findsOneWidget);
  final r = t.getRect(button);
  expect(r.bottom, lessThanOrEqualTo(size.height - _kb), reason: '키보드 뒤에 깔림: $r');
  expect(r.top, greaterThanOrEqualTo(0), reason: '화면 위로 나감: $r');
}

Finder _save(String text) => find.widgetWithText(FilledButton, text);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /* --- 식단 › 끼니에 추가 -------------------------------------------------
   * 저장 바는 본문 Column 끝이라 Scaffold 가 키보드 위로 올려 줍니다. 여기서 보는 건
   * 행 · 칩 · 세그먼트를 누르면 키보드가 내려가고(시트가 닫혀도 다시 안 뜨고),
   * 목록 끌기 · 빈 곳 탭도 내리며, 그 뒤 「저장」 이 눌려 기록이 남는가. */
  group('식단 — 끼니에 추가', () {
    final search = find.byType(TextField);
    Finder chip(String s) => find.widgetWithText(InputChip, s);

    for (final MapEntry(key: name, value: size) in _phones.entries) {
      testWidgets('$name — 행을 누르면 키보드가 내려가고 시트가 닫혀도 다시 안 뜬다 · 저장이 키보드 위에서 눌린다',
          (t) async {
        _phone(t, size);
        final app = await _seeded();
        await _host(t, app: app, push: FoodSearchScreen(date: _todayKey, meal: '저녁'));

        await _focus(t, search);
        await _keyboardUp(t);
        await t.enterText(search, '김치찌개');
        await t.pumpAndSettle();
        /* find.text 는 검색 칸에 친 글자도 잡습니다 — 행(InkWell)으로 잡습니다. */
        await t.tap(find.widgetWithText(InkWell, '김치찌개').first);
        await t.pumpAndSettle();
        expect(find.text('얼마나?'), findsOneWidget, reason: '양 시트');
        expect(_typing(t), isFalse, reason: '행을 누르면 키보드가 내려갑니다');
        await t.tap(find.textContaining('1인분  ·'));
        await t.pumpAndSettle();
        expect(chip('김치찌개 · 280kcal'), findsOneWidget);
        expect(_typing(t), isFalse, reason: '시트가 닫혀도 검색 칸으로 포커스가 돌아오지 않습니다');

        /* 다시 칸을 잡은 채(키보드 떠 있음) — 저장 바가 키보드 위에 보이고 눌립니다. */
        await _focus(t, search);
        final save = find.ancestor(of: find.textContaining('저녁에 1개 저장 · 280kcal'), matching: find.byType(FilledButton));
        _aboveKeyboard(t, save, size);
        await t.tap(save);
        await t.pumpAndSettle();
        expect(find.byType(FoodSearchScreen), findsNothing, reason: '저장하면 닫힙니다');
        final logs = (app.state['foodLogs'] as List).cast<Map>();
        expect(logs, hasLength(1));
        expect(logs.single['meal'], '저녁');
        expect((logs.single['items'] as List).single['name'], '김치찌개');
        expect(t.takeException(), isNull);
      });

      testWidgets('$name — 빈 곳 탭 · 목록 끌기 · 끼니 · 분류를 누르면 키보드가 내려간다', (t) async {
        _phone(t, size);
        await _host(t, app: await _seeded(), push: FoodSearchScreen(date: _todayKey, meal: '저녁'));

        await _focus(t, search);
        await _keyboardUp(t);
        await t.tap(find.text('목록'));
        await t.pumpAndSettle();
        expect(_typing(t), isFalse, reason: '목록 머리글(빈 곳) 탭 → 키보드 내려감');

        await _focus(t, search);
        final list = find.descendant(of: find.byType(Expanded), matching: find.byType(ListView));
        await t.drag(list, const Offset(0, -200));
        await t.pumpAndSettle();
        expect(_typing(t), isFalse, reason: '목록 끌기 → 키보드 내려감(onDrag)');

        await _focus(t, search);
        await t.tap(find.text('아침'));
        await t.pumpAndSettle();
        expect(_typing(t), isFalse, reason: '끼니 세그먼트 → 키보드 내려감');
        expect(find.widgetWithText(AppBar, '아침에 추가'), findsOneWidget);

        await _focus(t, search);
        /* 첫 분류 칩 — 뒤쪽 칩은 360 폭에서 가로 목록 밖입니다. */
        final cat = core.kFoodCats.first;
        await t.tap(find.widgetWithText(ChoiceChip, cat));
        await t.pumpAndSettle();
        expect(_typing(t), isFalse, reason: '분류 칩 → 키보드 내려감');
        expect(find.text(cat), findsWidgets, reason: '분류 머리글');

        /* 검색 키(돋보기)로도 내려갑니다 — 글자 키보드에는 그 키가 있습니다. */
        await _focus(t, search);
        await _key(t, TextInputAction.search);
        expect(_typing(t), isFalse);
        expect(t.takeException(), isNull);
      });
    }
  });

  /* --- 식단 › 직접 입력 다이얼로그 ------------------------------------------
   * 다이얼로그는 스스로 키보드 위로 올라가니 「추가」 는 보입니다. 보는 건 이름에
   * 곧바로 커서가 서고, 「다음」 이 칸을 차례로 옮기고, 마지막 완료가 곧 「추가」 인 것. */
  group('식단 — 직접 입력', () {
    for (final MapEntry(key: name, value: size) in _phones.entries) {
      testWidgets('$name — 이름 → 다음 ×4 → 완료 = 추가, 「추가」 는 키보드 위', (t) async {
        _phone(t, size);
        await _host(t, app: await _seeded(), push: FoodSearchScreen(date: _todayKey, meal: '저녁'));

        /* 검색 칸에 키보드가 뜬 채로 「직접 입력」 — 다이얼로그가 닫힌 뒤 검색 칸의
           키보드가 다시 튀어 오르면 안 됩니다. */
        await _focus(t, find.byType(TextField));
        await _keyboardUp(t);
        await t.tap(find.widgetWithText(TextButton, '직접 입력'));
        await t.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(_focused(t, _field('이름')), isTrue, reason: '이름에 곧바로 커서');
        expect(_typing(t), isTrue);

        await t.enterText(_field('이름'), '구내식당 점심');
        await _key(t, TextInputAction.next);
        expect(_focused(t, _field('칼로리 (kcal)')), isTrue);
        await t.enterText(_field('칼로리 (kcal)'), '650');
        await _key(t, TextInputAction.next);
        expect(_focused(t, _field('단백질 (g)')), isTrue);
        await t.enterText(_field('단백질 (g)'), '30.5');
        await _key(t, TextInputAction.next);
        expect(_focused(t, _field('탄수화물 (g)')), isTrue);
        await _key(t, TextInputAction.next);
        expect(_focused(t, _field('지방 (g)')), isTrue);
        for (final label in ['칼로리 (kcal)', '단백질 (g)', '탄수화물 (g)', '지방 (g)']) {
          expect(t.widget<TextField>(_field(label)).keyboardType,
              const TextInputType.numberWithOptions(decimal: true),
              reason: '$label — 아이폰 숫자 패드에는 소수점이 없습니다');
        }
        _aboveKeyboard(t, _save('추가'), size);

        await _key(t, TextInputAction.done);
        expect(find.byType(AlertDialog), findsNothing, reason: '마지막 칸의 완료 = 추가');
        expect(find.widgetWithText(InputChip, '구내식당 점심 · 650kcal'), findsOneWidget);
        expect(_typing(t), isFalse, reason: '검색 칸의 키보드가 다시 뜨지 않습니다');
        expect(t.takeException(), isNull);
      });
    }
  });

  /* --- 종목 고르기 시트 (기구 설정 → 익숙한 종목) -------------------------------
   * 시트는 viewInsets 만큼 밀려 올라가 「완료」 가 보입니다. 보는 건 그것과, 시트 안
   * 빈 곳 탭 · 목록 끌기 · 돋보기 키로 키보드가 내려가고, 「완료」 가 눌려 저장되는가. */
  group('종목 고르기 시트 — 기구 설정의 익숙한 종목', () {
    final searchField = find.byKey(const ValueKey('pick-search'));
    final done = find.byKey(const ValueKey('pick-done'));
    final add = find.byKey(const Key('gym-fam-add'));
    Map<String, Object?> saved(AppState app) =>
        GymPrefs.fromSettings(((app.state['settings'] as Map?) ?? const {}).cast<String, Object?>()).toJson();

    Future<void> openSheet(WidgetTester t) async {
      await t.ensureVisible(add);
      await t.pumpAndSettle();
      await t.tap(add);
      await t.pumpAndSettle();
      expect(find.byType(ExercisePicker), findsOneWidget);
    }

    for (final MapEntry(key: name, value: size) in _phones.entries) {
      testWidgets('$name — 키보드 위에서 검색 → 체크 → 「완료」 가 눌려 저장된다', (t) async {
        _phone(t, size);
        final app = await _seeded();
        await _host(t, app: app, home: const GymSettingsScreen());
        await openSheet(t);

        await _focus(t, searchField);
        await _keyboardUp(t);
        await t.enterText(searchField, '프레스');
        await t.pumpAndSettle();
        expect(find.byKey(const ValueKey('pick-chest-press-machine')), findsOneWidget);
        await t.tap(find.byKey(const ValueKey('pick-chest-press-machine')));
        await t.pumpAndSettle();
        expect(find.text('완료 1'), findsOneWidget);
        _aboveKeyboard(t, done, size);
        await t.tap(done);
        await t.pumpAndSettle();
        expect(find.byType(ExercisePicker), findsNothing, reason: '완료가 눌려 시트가 닫혀야');
        expect(saved(app)['familiar'], ['chest-press-machine']);
        expect(t.takeException(), isNull);
      });

      testWidgets('$name — 시트 제목 탭 · 목록 끌기 · 돋보기 키로 키보드가 내려가고 시트는 남는다', (t) async {
        _phone(t, size);
        await _host(t, app: await _seeded(), home: const GymSettingsScreen());
        await openSheet(t);
        final sheet = find.byType(ExercisePicker);

        await _focus(t, searchField);
        await _keyboardUp(t);
        await t.tap(find.descendant(of: sheet, matching: find.text('익숙한 종목')));
        await t.pumpAndSettle();
        expect(_typing(t), isFalse, reason: '시트 제목(빈 곳) 탭 → 키보드 내려감');
        expect(sheet, findsOneWidget, reason: '시트 안 탭은 시트를 닫지 않습니다');

        /* 부위 목록(가슴)은 어느 크기에서도 한 화면을 넘습니다 — 첫 화면은 아이폰
           크기에서 다 보여 끌 것이 없습니다(끌 것이 없으면 내릴 일도 없습니다). */
        await t.tap(find.byKey(const ValueKey('pick-group-chest')));
        await t.pumpAndSettle();
        await _focus(t, searchField);
        await t.drag(find.byKey(const ValueKey('pick-group-list-chest')), const Offset(0, -200));
        await t.pumpAndSettle();
        expect(_typing(t), isFalse, reason: '부위 목록 끌기 → 키보드 내려감(onDrag)');

        await _focus(t, searchField);
        await t.enterText(searchField, '로우');
        await t.pumpAndSettle();
        await t.drag(find.byKey(const ValueKey('pick-search-list')), const Offset(0, -200));
        await t.pumpAndSettle();
        expect(_typing(t), isFalse, reason: '검색 결과 끌기 → 키보드 내려감(onDrag)');

        await _focus(t, searchField);
        await _key(t, TextInputAction.search);
        expect(_typing(t), isFalse, reason: '돋보기 키 → 키보드 내려감');
        expect(sheet, findsOneWidget);
        expect(t.takeException(), isNull);
      });
    }
  });

  /* --- 헬스 · 유산소 종료 시트 -----------------------------------------------
   * _Sheet 가 viewInsets 만큼 밀어 올려 「저장」 이 보입니다. 보는 건 그것과, 시트
   * 제목 탭으로 키보드가 내려가는 것, 유산소의 분 → 「다음」 → 거리 → 완료. */
  group('운동 — 종료 시트', () {
    setUp(() => WorkoutSessionScreen.clock = () => _today);
    tearDown(() => WorkoutSessionScreen.clock = DateTime.now);

    Map<String, Object?> logOf(AppState app, String type) =>
        ((app.store.scheduleDay(_todayKey)['log'] as Map)[type] as Map).cast<String, Object?>();

    for (final MapEntry(key: name, value: size) in _phones.entries) {
      testWidgets('$name — 헬스: 분 칸에 커서가 서고 「저장」 이 키보드 위, 제목 탭으로 키보드가 내려간다',
          (t) async {
        _phone(t, size);
        final app = await _seeded();
        await _host(t, app: app, push: const WorkoutSessionScreen(dateKey: _todayKey, type: 'gym'));

        await t.tap(find.text('종료'));
        await t.pumpAndSettle();
        final minutes = _field('운동 시간');
        expect(_focused(t, minutes), isTrue, reason: '시계를 안 켰으면 분 칸에 곧바로 커서');
        await _keyboardUp(t);
        await t.ensureVisible(_save('저장'));
        await t.pumpAndSettle();
        _aboveKeyboard(t, _save('저장'), size);

        await t.tap(find.text('오늘 헬스'));
        await t.pumpAndSettle();
        expect(_typing(t), isFalse, reason: '시트 제목(빈 곳) 탭 → 키보드 내려감');
        expect(find.text('오늘 헬스'), findsOneWidget, reason: '시트는 그대로');

        await _focus(t, minutes);
        await t.enterText(minutes, '35');
        await _key(t, TextInputAction.done);
        expect(_typing(t), isFalse, reason: '완료 키(안드로이드) → 키보드 내려감');
        await t.tap(_save('저장'));
        await t.pumpAndSettle();
        expect(logOf(app, 'gym')['minutes'], 35);
        await t.tap(find.text('닫기'));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      });

      testWidgets('$name — 유산소: 분 → 다음 → 거리 → 완료, 「저장」 이 키보드 위에서 눌린다', (t) async {
        _phone(t, size);
        final app = await _seeded();
        await _host(t, app: app, push: const WorkoutSessionScreen(dateKey: _todayKey, type: 'cardio'));

        await t.tap(find.text('시간을 직접 넣기'));
        await t.pumpAndSettle();
        final minutes = _field('시간');
        final km = _field('거리');
        expect(_focused(t, minutes), isTrue, reason: '분 칸에 곧바로 커서');
        await _keyboardUp(t);
        await t.ensureVisible(_save('저장'));
        await t.pumpAndSettle();
        _aboveKeyboard(t, _save('저장'), size);

        await t.enterText(minutes, '30');
        /* 「다음」 은 onEditingComplete 로 — 기본 nextFocus 뒤에 한 번 더 옮기지 않게. */
        expect(t.widget<TextField>(minutes).onEditingComplete, isNotNull);
        await _key(t, TextInputAction.next);
        expect(_focused(t, km), isTrue, reason: '분 → 다음 → 거리');
        await t.enterText(km, '5');
        await _key(t, TextInputAction.done);
        expect(_typing(t), isFalse, reason: '마지막 칸의 완료 → 키보드 내려감');

        await t.tap(_save('저장'));
        await t.pumpAndSettle();
        final log = logOf(app, 'cardio');
        expect(log['minutes'], 30);
        expect(log['km'], 5.0);
        await t.tap(find.text('닫기'));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      });
    }
  });

  /* --- 친구 › 초대 코드 다이얼로그 -------------------------------------------
   * 다이얼로그는 키보드 위로 올라가 「요청 보내기」 가 보입니다. 보는 건 그것과,
   * 코드 칸에 자동 교정이 꺼져 있고 완료 키가 곧 「요청 보내기」 인 것. */
  group('친구 — 초대 코드', () {
    _Server server() => _Server({
          '/me': {'ok': true, 'user': {'id': 'me', 'displayName': '나', 'inviteCode': 'me1234'}},
          '/friends': {'ok': true, 'friends': {'accepted': [], 'incoming': [], 'outgoing': []}},
          '/pokes': {'ok': true, 'pokes': []},
          '/friends/request': {'ok': true},
        });

    for (final MapEntry(key: name, value: size) in _phones.entries) {
      testWidgets('$name — 코드 칸에 곧바로 커서, 「요청 보내기」 가 키보드 위, 완료 키로 보낸다', (t) async {
        _phone(t, size);
        final s = server();
        await _host(t, app: await _seeded(), api: s.api(), home: Scaffold(body: SocialScreen(go: (_, [__]) {})));
        await t.tap(find.text('친구 추가'));
        await t.pumpAndSettle();

        final code = find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField));
        expect(_focused(t, code), isTrue, reason: '코드 칸에 곧바로 커서');
        final field = t.widget<TextField>(code);
        expect(field.autocorrect, isFalse, reason: '코드는 낱말이 아닙니다');
        expect(field.enableSuggestions, isFalse);
        await _keyboardUp(t);
        _aboveKeyboard(t, _save('요청 보내기'), size);

        await t.enterText(code, ' ab12cd ');
        await _key(t, TextInputAction.done);
        expect(find.byType(AlertDialog), findsNothing, reason: '완료 키 = 요청 보내기');
        final sent = s.sent.where((r) => r.$1 == '/friends/request').toList();
        expect(sent, hasLength(1));
        expect(sent.single.$2, {'inviteCode': 'ab12cd'}, reason: '양끝 공백은 잘라서 보냅니다');
        expect(find.text('요청을 보냈습니다'), findsOneWidget);
        expect(t.takeException(), isNull);
      });
    }
  });
}
