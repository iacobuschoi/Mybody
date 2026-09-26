/* =============================================================================
 * keyboard_forms_test.dart — 키보드가 떠 있어도 확인 버튼에 닿고, 바깥을 탭하면 내려간다
 *
 * 주인이 아이폰에서 잡은 버그: 숫자 키보드가 안 사라져 확인을 못 눌렀습니다.
 * 아이폰의 숫자 패드(number · decimal)에는 완료 키가 없습니다 — 안드로이드
 * (Done 키 있음)에서는 드러나지 않던 문제. 그래서 화면마다 둘을 봅니다:
 *
 *   1. 키보드 300px 을 흉내(viewInsets) 낸 채로 확인 · 저장 버튼이 **키보드 위
 *      보이는 영역** 에 있고 실제로 눌리는가.
 *   2. 칸 바깥(빈 곳 · 제목)을 탭하거나 목록을 끌면 키보드가 내려가는가, 그리고
 *      「다음」 키가 바로 아래 칸으로 가는가.
 *
 * 360×740(안드로이드 기본) · 390×844(아이폰) 둘 다. 여기서 보는 화면: 설정의
 * 「내 몸 정보」 시트 · 인바디 올리기 · 판독 결과 확인 · 로그인 · 서버 주소.
 * ========================================================================== */
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mybody/src/api.dart';
import 'package:mybody/src/app_state.dart';
import 'package:mybody/src/scope.dart';
import 'package:mybody/src/screens/account.dart';
import 'package:mybody/src/screens/review.dart';
import 'package:mybody/src/screens/settings.dart';
import 'package:mybody/src/screens/upload.dart';
import 'package:mybody/src/theme.dart';
import 'package:mybody/src/ui/edge.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 흉내 내는 키보드 높이(논리 px · dpr 1.0).
const double _kb = 300;

/// 두 폰 크기. 아이폰은 390×844 — 주인이 버그를 본 크기대입니다.
const _phones = <String, Size>{
  '360×740': Size(360, 740),
  '390×844 아이폰': Size(390, 844),
};

const _profile = {
  'sex': 'male', 'age': 22, 'heightCm': 187, 'activityLevel': 'moderate',
  'trainingAge': 'novice', 'daysPerWeek': 4, 'mealsPerDay': 3,
};

/* 앱이 MaterialApp 의 builder 에 거는 것 그대로(edge.dart) — 입력칸 밖을 탭하면
   포커스를 풀어 키보드를 내리는 전역 제스처가 여기 들어 있습니다. 이 시험은 그
   제스처 아래에서 이 화면들의 버튼 · 칸 · 목록이 그것과 부딪히지 않는지(버튼은
   여전히 눌리고, 빈 곳 탭은 키보드를 내리는지)를 봅니다. */
const TransitionBuilder _tapOutsideDismisses = edgeSafe;

Api _api({Map<String, Object> routes = const {}, bool signedIn = false}) {
  http.Response json(Object body, int status) => http.Response.bytes(
        utf8.encode(jsonEncode(body)), status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
  final api = Api(
    baseUrl: 'https://x.test',
    client: MockClient((req) async {
      final v = routes[req.url.path.replaceFirst('/api', '')];
      return v == null ? json({'ok': false, 'reason': '없는 길'}, 404) : json(v, 200);
    }),
  );
  if (signedIn) api.setToken('tok');
  return api;
}

Future<AppState> _seeded() async {
  SharedPreferences.setMockInitialValues({});
  final app = await AppState.boot();
  app.store.set({'profile': _profile, 'onboarded': true});
  return app;
}

/// 앱과 같은 겹: Scope > MaterialApp(builder) > 첫 화면 위에 [screen] 을 밀어 올림.
/// 밀어 올려야 검수 화면의 저장(pop)이 갈 곳이 있습니다.
Future<void> _host(WidgetTester t, Widget screen, {AppState? app, Api? api}) async {
  final state = app ?? await _seeded();
  await t.pumpWidget(Scope(
    state: state,
    api: api ?? _api(signedIn: true),
    onServerChange: (_) async {},
    child: MaterialApp(
      theme: mbLight(),
      builder: _tapOutsideDismisses,
      home: Builder(builder: (c) => Scaffold(body: Center(child: TextButton(
        onPressed: () => Navigator.of(c).push(MaterialPageRoute(builder: (_) => screen)),
        child: const Text('열기'),
      )))),
    ),
  ));
  await t.tap(find.text('열기'));
  await t.pumpAndSettle();
}

void _phone(WidgetTester t, Size size) {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
}

/// 키보드가 올라온 것처럼 — 실제 폰에서 키보드가 뜨면 viewInsets.bottom 이 이만큼 됩니다.
Future<void> _keyboardUp(WidgetTester t) async {
  t.view.viewInsets = const FakeViewPadding(bottom: _kb);
  await t.pumpAndSettle();
}

/// 어느 칸이 시스템 키보드에 붙어 있는가 — 실제 폰에서 키보드가 떠 있는 것과 같습니다.
bool _typing(WidgetTester t) => t.testTextInput.hasAnyClients;

Finder _field(String label) => find.widgetWithText(TextField, label);

/// 화면의 세로 목록(ListView). 글자 칸(EditableText)마다 가로 Scrollable 이 하나씩
/// 있어서 byType(Scrollable) 로는 하나로 안 잡힙니다.
Finder _list([Finder? within]) {
  final vertical = find.byWidgetPredicate(
      (w) => w is Scrollable && axisDirectionToAxis(w.axisDirection) == Axis.vertical);
  return within == null ? vertical : find.descendant(of: within, matching: vertical);
}

bool _focused(WidgetTester t, String label) => t
    .widget<EditableText>(find.descendant(of: _field(label), matching: find.byType(EditableText)))
    .focusNode
    .hasPrimaryFocus;

Future<void> _focusOn(WidgetTester t, Finder field) async {
  await t.ensureVisible(field);
  await t.tap(field);
  await t.pumpAndSettle();
  expect(_typing(t), isTrue, reason: '$field 칸을 탭했는데 키보드가 안 붙음');
}

Future<void> _focus(WidgetTester t, String label) => _focusOn(t, _field(label));

Future<void> _key(WidgetTester t, TextInputAction a) async {
  await t.testTextInput.receiveAction(a);
  await t.pumpAndSettle();
}

/// 버튼이 키보드(아래 [_kb]px) 위 보이는 영역 안에 통째로 있는가.
void _aboveKeyboard(WidgetTester t, Finder button, Size size) {
  final r = t.getRect(button);
  expect(r.bottom, lessThanOrEqualTo(size.height - _kb), reason: '키보드 뒤에 깔림: $r');
  expect(r.top, greaterThanOrEqualTo(0), reason: '화면 위로 나감: $r');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /* --- 설정 › 내 몸 정보 시트 ---------------------------------------------
   * 모달 시트는 스스로 키보드를 피하지 않아, 끝까지 스크롤해도 「저장」 이
   * 키보드 뒤에 깔렸습니다(두 크기 모두 완전히). 시트를 viewInsets 만큼 밀어
   * 올려서 고쳤습니다. */
  group('설정 — 내 몸 정보 시트', () {
    final sheetList = _list(find.byType(DraggableScrollableSheet));

    Future<void> openSheet(WidgetTester t) async {
      await t.tap(find.text('고치기'));
      await t.pumpAndSettle();
      expect(find.text('내 몸 정보'), findsWidgets);
    }

    for (final MapEntry(key: name, value: size) in _phones.entries) {
      testWidgets('$name — 키보드 위에서 「저장」 이 보이고 눌린다 · 다음 키가 나이로', (t) async {
        _phone(t, size);
        final app = await _seeded();
        await _host(t, const SettingsScreen(), app: app);
        await openSheet(t);
        /* 360 폭에서 활동량 드롭다운이 오른쪽으로 넘쳤습니다(isExpanded 없음).
           넘치면 여기서 예외로 잡힙니다. */
        expect(t.takeException(), isNull);

        await _focus(t, '키');
        await _keyboardUp(t);
        await t.enterText(_field('키'), '180');
        await _key(t, TextInputAction.next);
        expect(_focused(t, '나이'), isTrue, reason: '키 → 다음 → 나이');
        await t.enterText(_field('나이'), '30');
        await _key(t, TextInputAction.done);
        expect(_typing(t), isFalse, reason: '완료 키로 키보드가 내려가야');

        /* 다시 칸을 잡은 채(키보드 떠 있음) 저장으로 — 아이폰에서는 이 상태에서
           키보드를 내릴 키가 없으니, 그대로 저장에 닿아야 합니다. */
        await _focus(t, '나이');
        final save = find.widgetWithText(FilledButton, '저장');
        await t.scrollUntilVisible(save, 80, scrollable: sheetList);
        await t.pumpAndSettle();
        _aboveKeyboard(t, save, size);
        await t.tap(save);
        await t.pumpAndSettle();
        expect(find.byType(DraggableScrollableSheet), findsNothing, reason: '저장이 눌려 시트가 닫혀야');
        expect(app.profile?['heightCm'], 180.0);
        expect(app.profile?['age'], 30.0);
        expect(t.takeException(), isNull);
      });

      testWidgets('$name — 시트 안 빈 곳 탭 · 목록 끌기로 키보드가 내려간다', (t) async {
        _phone(t, size);
        await _host(t, const SettingsScreen());
        await openSheet(t);
        await _focus(t, '키');
        await _keyboardUp(t);
        await t.tap(find.text('내 몸 정보').last);
        await t.pumpAndSettle();
        expect(_typing(t), isFalse, reason: '시트 제목(빈 곳) 탭 → 키보드 내려감');

        await _focus(t, '키');
        await _keyboardUp(t);
        expect(_typing(t), isTrue, reason: '키보드가 올라와 시트가 밀리는 것은 끌기가 아닙니다 — 그대로 떠 있어야');
        /* 시트는 끝까지 펴진 뒤부터 목록이 스크롤됩니다(그 전에는 끌기가 시트를
           키우는 데 쓰임). 첫 끌기 — 짧게, 시트가 다 펴지기 전 — 에서도 내려가야
           「끌면 닫힌다」 가 참입니다. */
        await t.drag(sheetList, const Offset(0, -30));
        await t.pumpAndSettle();
        expect(_typing(t), isFalse, reason: '시트가 펴지는 첫 끌기(30px)에도 키보드 내려감');
        expect(find.byType(DraggableScrollableSheet), findsOneWidget, reason: '시트는 그대로');

        /* 다 펴진 뒤의 끌기(목록 스크롤 · onDrag)도 여전히. */
        await _focus(t, '키');
        await t.drag(sheetList, const Offset(0, -400));
        await t.pumpAndSettle();
        expect(_typing(t), isFalse, reason: '목록 끌기 → 키보드 내려감(onDrag)');
        expect(find.byType(DraggableScrollableSheet), findsOneWidget, reason: '시트는 그대로');
      });
    }
  });

  /* --- 인바디 올리기 -------------------------------------------------------
   * 버튼이 본문 끝이라 스크롤하면 닿습니다(Scaffold 가 본문을 줄임). 여기서
   * 보는 건 그것과, 다음/완료 키 · 바깥 탭 · 끌기로 키보드가 내려가는 것. */
  group('인바디 올리기', () {
    final next = find.widgetWithText(FilledButton, '다음 — 검산하기');

    for (final MapEntry(key: name, value: size) in _phones.entries) {
      testWidgets('$name — 다음 키로 칸을 옮기고, 키보드 위에서 검산 버튼이 눌린다', (t) async {
        _phone(t, size);
        await _host(t, const UploadScreen());
        await _focus(t, '체중');
        await _keyboardUp(t);
        await t.enterText(_field('체중'), '86.7');
        await _key(t, TextInputAction.next);
        expect(_focused(t, '골격근량'), isTrue);
        await t.enterText(_field('골격근량'), '38');
        await _key(t, TextInputAction.next);
        expect(_focused(t, '체지방률'), isTrue);
        await t.enterText(_field('체지방률'), '23.1');
        await t.pumpAndSettle();

        await t.scrollUntilVisible(next, 80, scrollable: _list());
        await t.pumpAndSettle();
        _aboveKeyboard(t, next, size);
        expect(t.widget<FilledButton>(next).enabled, isTrue);
        await t.tap(next);
        await t.pumpAndSettle();
        expect(find.byType(ReviewScreen), findsOneWidget);
      });
    }

    testWidgets('마지막 칸의 완료 키가 곧 검산으로 — 세 칸이 다 찼을 때만', (t) async {
      _phone(t, _phones.values.first);
      await _host(t, const UploadScreen());
      await _focus(t, '체지방률');
      await _keyboardUp(t);
      await t.enterText(_field('체지방률'), '23.1');
      await _key(t, TextInputAction.done);
      expect(find.byType(ReviewScreen), findsNothing, reason: '두 칸이 비었으면 넘어가지 않음');
      expect(_typing(t), isFalse, reason: '키보드는 내려감');

      await t.enterText(_field('체중'), '86.7');
      await t.enterText(_field('골격근량'), '38');
      await _focus(t, '체지방률');
      await _key(t, TextInputAction.done);
      expect(find.byType(ReviewScreen), findsOneWidget);
    });

    testWidgets('빈 곳 탭 · 목록 끌기로 키보드가 내려가고, 버튼은 여전히 눌린다', (t) async {
      _phone(t, _phones.values.last);
      await _host(t, const UploadScreen());
      await _focus(t, '체중');
      await _keyboardUp(t);
      await t.tap(find.text('측정일'));
      await t.pumpAndSettle();
      expect(_typing(t), isFalse, reason: '구역 제목(빈 곳) 탭 → 키보드 내려감');

      /* 칸을 잡으면(ensureVisible) 목록이 그 칸을 맨 위로 올려 둔 상태 — 아래로 끌어
         되돌립니다. 목록이 **실제로 움직여야** 키보드가 내려갑니다: 안드로이드의
         clamping 물리에서 끝에서 더 끄는 건 스크롤이 아니라 overscroll 이라
         onDrag 가 반응하지 않습니다(아이폰의 bouncing 물리는 끝에서도 움직임). */
      await _focus(t, '체중');
      await t.drag(_list(), const Offset(0, 80));
      await t.pumpAndSettle();
      expect(_typing(t), isFalse, reason: '목록 끌기 → 키보드 내려감(onDrag)');

      /* 전역 탭 제스처가 있어도 버튼의 onTap 이 이깁니다. */
      await t.enterText(_field('체중'), '86.7');
      await t.enterText(_field('골격근량'), '38');
      await t.enterText(_field('체지방률'), '23.1');
      await t.pumpAndSettle();
      await t.scrollUntilVisible(next, 80, scrollable: _list());
      await t.tap(next);
      await t.pumpAndSettle();
      expect(find.byType(ReviewScreen), findsOneWidget);
    });
  });

  /* --- 판독 결과 확인 -------------------------------------------------------
   * 칸이 열 개 안팎. 「다음」 은 보이는 칸 순서대로, 마지막 칸만 「완료」 —
   * 핵심 세 칸과 나머지 사이의 「펼치기/접기」 버튼으로 새지 않아야 합니다.
   * 완료는 저장이 아닙니다(검산 결과를 읽고 사람이 저장). */
  group('판독 결과 확인', () {
    const draft = {
      'id': 'draft', 'measuredAt': '2026-09-21T00:00:00.000Z',
      'weightKg': 86.7, 'smmKg': 38.0, 'bfmKg': 20.0,
    };
    final save = find.widgetWithText(FilledButton, '저장하기');

    for (final MapEntry(key: name, value: size) in _phones.entries) {
      testWidgets('$name — 키보드 위에서 「저장하기」 가 보이고 눌린다', (t) async {
        _phone(t, size);
        final app = await _seeded();
        await _host(t, const ReviewScreen(draft: draft), app: app);
        await _focus(t, '체중');
        await _keyboardUp(t);
        await t.scrollUntilVisible(save, 80, scrollable: _list());
        await t.pumpAndSettle();
        _aboveKeyboard(t, save, size);
        await t.tap(save);
        await t.pumpAndSettle();
        expect(app.store.sortedScans(), hasLength(1));
        expect(find.byType(ReviewScreen), findsNothing);
      });
    }

    testWidgets('다음 키 — 핵심 세 칸에서는 셋째가 완료, 펼치면 나머지 칸으로 순서대로', (t) async {
      _phone(t, _phones.values.last);
      await _host(t, const ReviewScreen(draft: draft));
      await _focus(t, '체중');
      await _keyboardUp(t);
      await _key(t, TextInputAction.next);
      expect(_focused(t, '골격근량 (SMM)'), isTrue);
      await _key(t, TextInputAction.next);
      expect(_focused(t, '체지방량 (BFM)'), isTrue);
      await _key(t, TextInputAction.done);
      expect(_typing(t), isFalse, reason: '접힌 상태에서 셋째 칸은 완료');
      expect(find.byType(ReviewScreen), findsOneWidget, reason: '완료가 저장은 아님');

      await t.tap(find.text('펼치기'));
      await t.pumpAndSettle();
      await _focus(t, '체지방량 (BFM)');
      const rest = [
        '체지방률 (PBF)', 'BMI', '제지방량 (FFM)', '내장지방 레벨', '기초대사량 (BMR)',
        '복부지방률 (WHR)', 'InBody 점수', '체수분 (TBW)', '단백질', '무기질',
      ];
      for (final label in rest) {
        await _key(t, TextInputAction.next);
        expect(_focused(t, label), isTrue, reason: '「다음」 이 $label 로 가야(「접기」 버튼으로 새지 않고)');
      }
      await _key(t, TextInputAction.done);
      expect(_typing(t), isFalse);
    });

    testWidgets('빈 곳 탭 · 목록 끌기로 키보드가 내려간다', (t) async {
      _phone(t, _phones.values.first);
      await _host(t, const ReviewScreen(draft: draft));
      await _focus(t, '체중');
      await _keyboardUp(t);
      await t.tap(find.text('핵심 세 칸'));
      await t.pumpAndSettle();
      expect(_typing(t), isFalse);

      await _focus(t, '체중');
      await t.drag(_list(), const Offset(0, -80));
      await t.pumpAndSettle();
      expect(_typing(t), isFalse);
    });
  });

  /* --- 로그인 · 가입 --------------------------------------------------------
   * 글자 자판이라 return 키로 닫히긴 했습니다. 여기서 보는 건 「다음」 이 아래
   * 칸으로 가고, 로그인에서는 「완료」 가 곧 제출이며, 가입에서는 제출이 아닌 것. */
  group('로그인 화면', () {
    Future<void> open(WidgetTester t, {required Api api, VoidCallback? onDone}) async {
      await t.pumpWidget(MaterialApp(
        theme: mbLight(),
        builder: _tapOutsideDismisses,
        home: SignInScreen(api: api, onDone: onDone ?? () {}, onServerChange: (_) async {}),
      ));
      await t.pumpAndSettle();
    }

    for (final MapEntry(key: name, value: size) in _phones.entries) {
      testWidgets('$name — 아이디 → 다음 → 비밀번호 → 완료 = 로그인, 버튼은 키보드 위', (t) async {
        _phone(t, size);
        var done = false;
        await open(t, onDone: () => done = true, api: _api(routes: {
          '/health': {'ok': true, 'openSignup': true},
          '/auth/signin': {'ok': true, 'token': 'tok'},
        }));
        await _focus(t, '아이디');
        await _keyboardUp(t);
        await t.enterText(_field('아이디'), 'chulsoo');
        await _key(t, TextInputAction.next);
        expect(_focused(t, '비밀번호'), isTrue);
        _aboveKeyboard(t, find.widgetWithText(FilledButton, '로그인'), size);
        await t.enterText(_field('비밀번호'), 'pw12345678');
        await _key(t, TextInputAction.done);
        expect(done, isTrue, reason: '비밀번호 칸의 완료 키가 로그인을 보내야');
      });
    }

    testWidgets('가입 — 다음 키가 이름 · 비밀번호로, 완료는 제출이 아니다(동의 상자가 아래)', (t) async {
      _phone(t, _phones.values.last);
      await open(t, api: _api(routes: {'/health': {'ok': true, 'openSignup': true}}));
      await t.tap(find.text('처음이에요'));
      await t.pumpAndSettle();
      await _focus(t, '아이디');
      await _keyboardUp(t);
      await t.enterText(_field('아이디'), 'chulsoo');
      await _key(t, TextInputAction.next);
      expect(_focused(t, '친구에게 보일 이름'), isTrue);
      await _key(t, TextInputAction.next);
      expect(_focused(t, '비밀번호'), isTrue);
      await _key(t, TextInputAction.done);
      expect(_typing(t), isFalse);
      expect(find.textContaining('동의해야'), findsNothing,
          reason: '키보드를 내리려던 사람에게 동의 오류를 띄우면 안 됨');
    });

    testWidgets('가입 코드가 있으면 비밀번호 → 다음 → 가입 코드 → 완료', (t) async {
      _phone(t, _phones.values.first);
      await open(t, api: _api(routes: {'/health': {'ok': true, 'openSignup': false}}));
      await t.tap(find.text('처음이에요'));
      await t.pumpAndSettle();
      await _focus(t, '비밀번호');
      expect(t.widget<TextField>(_field('비밀번호')).autofillHints, [AutofillHints.newPassword],
          reason: '가입 칸만 새 비밀번호 힌트(아이폰 강력한 암호 제안)');
      await _keyboardUp(t);
      await _key(t, TextInputAction.next);
      expect(_focused(t, '가입 코드'), isTrue);
      await _key(t, TextInputAction.done);
      expect(_typing(t), isFalse);
    });

    testWidgets('복구 — 아이디 → 복구 코드 → 새 비밀번호 → 완료 = 제출', (t) async {
      _phone(t, _phones.values.first);
      var done = false;
      await open(t, onDone: () => done = true, api: _api(routes: {
        '/health': {'ok': true},
        '/auth/recover': {'ok': true, 'token': 'tok'},
      }));
      await t.tap(find.text('비밀번호 잊음'));
      await t.pumpAndSettle();
      await _focus(t, '아이디');
      await _keyboardUp(t);
      await t.enterText(_field('아이디'), 'chulsoo');
      await _key(t, TextInputAction.next);
      expect(_focused(t, '복구 코드'), isTrue);
      await _key(t, TextInputAction.next);
      expect(_focused(t, '새 비밀번호'), isTrue);
      /* 아이폰은 newPassword 힌트가 있는 칸에 「강력한 암호」 제안 시트를 덮습니다 —
         복구 칸은 보통 비밀번호 칸이어야 그 한 겹이 없습니다(가입 칸에만). */
      expect(t.widget<TextField>(_field('새 비밀번호')).autofillHints, [AutofillHints.password]);
      await _key(t, TextInputAction.done);
      expect(done, isTrue);
    });

    testWidgets('빈 곳 탭 · 목록 끌기로 키보드가 내려간다', (t) async {
      _phone(t, _phones.values.last);
      await open(t, api: _api(routes: {'/health': {'ok': true}}));
      await _focus(t, '아이디');
      await _keyboardUp(t);
      await t.tap(find.textContaining('복구 코드가 없으면'));
      await t.pumpAndSettle();
      expect(_typing(t), isFalse);

      /* 끌기는 목록이 실제로 움직여야 먹습니다 — 로그인 모드는 내용이 짧아 스크롤이
         없으니, 동의 카드로 긴 가입 모드에서 봅니다. 칸을 잡으면 그 칸이 맨 위로
         올라가 있으니 아래로 끌어 되돌립니다. */
      await t.tap(find.text('처음이에요'));
      await t.pumpAndSettle();
      await _focus(t, '아이디');
      await t.drag(_list(), const Offset(0, 80));
      await t.pumpAndSettle();
      expect(_typing(t), isFalse);
    });
  });

  /* --- 서버 주소 ------------------------------------------------------------- */
  group('서버 주소 화면', () {
    testWidgets('이동 키가 「연결」 과 같고, 버튼은 키보드 위, 빈 곳 탭으로 키보드가 내려간다', (t) async {
      _phone(t, _phones.values.first);
      await t.pumpWidget(MaterialApp(
        theme: mbLight(),
        builder: _tapOutsideDismisses,
        home: ServerScreen(onSet: (_) async {}),
      ));
      await _focusOn(t, find.byType(TextField));
      await _keyboardUp(t);
      _aboveKeyboard(t, find.widgetWithText(FilledButton, '연결'), _phones.values.first);
      /* http 는 그물에 안 나가고 바로 거절됩니다 — 이동 키가 _go 를 부르는지 보는 데 충분. */
      await t.enterText(find.byType(TextField), 'http://192.168.0.10:8080');
      await _key(t, TextInputAction.go);
      expect(find.textContaining('http 주소는 폰이 막습니다'), findsOneWidget);

      await _focusOn(t, find.byType(TextField));
      await t.tap(find.textContaining('이 앱은 주인의 컴퓨터'));
      await t.pumpAndSettle();
      expect(_typing(t), isFalse);
    });
  });
}
