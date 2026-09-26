/* =============================================================================
 * onboarding_test.dart — 첫 설정 화면과 키보드
 *
 * 아이폰에서 키·나이를 넣고 나면 「다음」 을 누를 수 없었습니다. 숫자 패드에는
 * 완료 키가 없어 키보드를 내릴 길이 없고, Scaffold 는 bottomNavigationBar 를
 * 늘 화면 맨 아래에 두어(본문만 키보드만큼 줄임) 단추가 키보드 뒤에 깔렸습니다.
 * 안드로이드는 Done 키가 있어 드러나지 않았습니다.
 *
 * 키보드는 viewInsets 300px 로 흉내 냅니다. 시험에는 진짜 키보드가 없어 탭은
 * 어디든 닿으니, 단추의 자리(rect)가 키보드 위인지를 따로 봅니다.
 * 앱이 실제로 가는 길(MaterialApp.builder = edgeSafe)로 세웁니다 — 바깥 탭으로
 * 키보드를 내리는 것이 거기 걸려 있습니다.
 * ========================================================================== */
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mybody/src/api.dart';
import 'package:mybody/src/app_state.dart';
import 'package:mybody/src/scope.dart';
import 'package:mybody/src/screens/onboarding.dart';
import 'package:mybody/src/theme.dart';
import 'package:mybody/src/ui/edge.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _sizes = [Size(360, 740), Size(390, 844)];
const _kb = 300.0;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<AppState> fresh() async {
    SharedPreferences.setMockInitialValues({});
    return AppState.boot();
  }

  /// [key] — 한 시험에서 두 크기를 이어 세울 때 화면의 State(단계)가 남지 않게.
  Widget host(AppState app, {Key? key}) => Scope(
        state: app,
        api: Api(baseUrl: '', client: MockClient((_) async => http.Response('{"ok":false}', 404))),
        onServerChange: (_) async {},
        child: MaterialApp(theme: mbLight(), builder: edgeSafe, home: OnboardingScreen(key: key)),
      );

  void phone(WidgetTester t, Size size) {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
  }

  /// 키보드가 뜬 것처럼 — 아래 300px 이 가려집니다.
  Future<void> keyboard(WidgetTester t, {bool up = true}) async {
    t.view.viewInsets = FakeViewPadding(bottom: up ? _kb : 0);
    await t.pumpAndSettle();
  }

  FocusNode focusOf(WidgetTester t, String label) => t
      .widget<EditableText>(find.descendant(
          of: find.widgetWithText(TextField, label), matching: find.byType(EditableText)))
      .focusNode;

  testWidgets('키·나이 — 키보드가 떠 있어도 「다음」 이 키보드 위에 보이고 눌린다', (t) async {
    for (final size in _sizes) {
      phone(t, size);
      final app = await fresh();
      await t.pumpWidget(host(app, key: ValueKey(size)));
      await t.pump();
      await t.enterText(find.widgetWithText(TextField, '키'), '175');
      await t.enterText(find.widgetWithText(TextField, '나이'), '30');
      await keyboard(t);

      final button = find.widgetWithText(FilledButton, '다음');
      expect(t.widget<FilledButton>(button).onPressed, isNotNull, reason: '$size 값이 맞으니 열려야 합니다');
      final r = t.getRect(button);
      expect(r.bottom, lessThanOrEqualTo(size.height - _kb),
          reason: '$size 단추가 키보드(아래 ${_kb}px) 뒤에 깔리면 못 누릅니다: $r');
      expect(r.top, greaterThanOrEqualTo(0));

      await t.tap(button);
      await t.pumpAndSettle();
      expect(find.text('2/3 · 활동 · 운동'), findsOneWidget, reason: '$size 탭이 다음 단계로 가야 합니다');
      expect(t.takeException(), isNull);
    }
  });

  testWidgets('키·나이 — 입력칸 밖(안내문)을 탭하면 키보드가 내려간다', (t) async {
    for (final size in _sizes) {
      phone(t, size);
      final app = await fresh();
      await t.pumpWidget(host(app, key: ValueKey(size)));
      await t.pump();
      await t.showKeyboard(find.widgetWithText(TextField, '키'));
      await keyboard(t);
      expect(focusOf(t, '키').hasFocus, isTrue);

      await t.tap(find.text('기초대사량 계산에 씁니다'));
      await t.pumpAndSettle();
      expect(focusOf(t, '키').hasFocus, isFalse, reason: '$size 바깥 탭에 포커스가 풀려야 합니다');
      expect(FocusManager.instance.primaryFocus?.context?.widget, isNot(isA<EditableText>()));

      /* 입력칸 자체를 탭하면 그대로 — 바깥 탭 인식기가 칸의 탭을 가로채면 안 됩니다. */
      await t.tap(find.widgetWithText(TextField, '나이'));
      await t.pumpAndSettle();
      expect(focusOf(t, '나이').hasFocus, isTrue, reason: '$size 칸 탭은 칸이 받아야 합니다');
    }
  });

  testWidgets('키·나이 — 목록을 끌면 키보드가 내려간다', (t) async {
    phone(t, _sizes.first);
    final app = await fresh();
    await t.pumpWidget(host(app));
    await t.pump();
    await t.showKeyboard(find.widgetWithText(TextField, '키'));
    await keyboard(t);
    expect(focusOf(t, '키').hasFocus, isTrue);

    await t.drag(find.byType(ListView), const Offset(0, -60));
    await t.pumpAndSettle();
    expect(focusOf(t, '키').hasFocus, isFalse, reason: '끌기(onDrag)로도 내려가야 합니다');
  });

  testWidgets('키 — 다음 키로 나이 칸으로 옮기고, 나이 — 완료 키로 다음 단계로 간다', (t) async {
    phone(t, _sizes.first);
    final app = await fresh();
    await t.pumpWidget(host(app));
    await t.pump();

    await t.enterText(find.widgetWithText(TextField, '키'), '175');
    /* 옮기기는 onEditingComplete 로 기본 동작(읽기 순서 nextFocus)을 대신해야 합니다 —
       onSubmitted 에 두면 기본 이동이 먼저 돌고 한 번 더 옮겨 포커스가 두 번 움직입니다. */
    expect(t.widget<TextField>(find.widgetWithText(TextField, '키')).onEditingComplete, isNotNull);
    await t.testTextInput.receiveAction(TextInputAction.next);
    await t.pumpAndSettle();
    expect(focusOf(t, '나이').hasFocus, isTrue, reason: '안드로이드 「다음」 키는 나이 칸으로');

    await t.enterText(find.widgetWithText(TextField, '나이'), '30');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pumpAndSettle();
    expect(find.text('2/3 · 활동 · 운동'), findsOneWidget, reason: '값이 맞으면 「완료」 가 곧 「다음」');
  });

  testWidgets('나이 — 값이 안 맞으면 완료 키는 키보드만 내리고 단계는 그대로', (t) async {
    phone(t, _sizes.first);
    final app = await fresh();
    await t.pumpWidget(host(app));
    await t.pump();
    await t.enterText(find.widgetWithText(TextField, '나이'), '5');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pumpAndSettle();
    expect(find.text('1/3 · 기본 정보'), findsOneWidget);
    expect(focusOf(t, '나이').hasFocus, isFalse);
    expect(t.widget<FilledButton>(find.widgetWithText(FilledButton, '다음')).onPressed, isNull);
  });
}
