/* =============================================================================
 * keyboard_global_test.dart — 입력칸 밖을 탭하면 키보드가 내려가는가 (앱 전체)
 *
 * 아이폰 숫자 패드에는 완료 키가 없습니다. 바깥 탭으로 안 내려가면 키·나이 ·
 * 체중 같은 숫자 칸의 키보드를 닫을 길이 없어서, 첫 설정에서 「다음」 에 영영
 * 못 닿았습니다. 화면마다 거는 대신 MaterialApp.builder(ui/edge.dart) 에 한 번
 * 걸었으니, 여기서는 그 한 곳이 모든 자리에서 맞게 동작하는지 봅니다:
 *
 *   · 빈 곳(글자)을 탭하면 포커스가 풀린다 — 첫 화면 · 밀어 올린 화면 · 시트 · 다이얼로그
 *   · 버튼 · 입력칸 · 목록 행의 탭은 가로채지 않는다(자기 탭 인식기가 먼저 이긴다)
 *   · 목록 끌기(스크롤)는 그대로 된다
 *   · 아무 칸도 포커스가 없으면 아무 일도 없다
 *   · 스크린리더에는 보이지 않는다 — 화면 전체 크기의 이름 없는 탭 요소가 생기면 안 된다
 *
 * 키보드는 viewInsets 300px 로 흉내 내고, 360×740 · 아이폰(390×844) 둘 다 봅니다.
 * ========================================================================== */
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mybody/src/theme.dart';
import 'package:mybody/src/ui/edge.dart';

const _sizes = [Size(360, 740), Size(390, 844)];
const _kb = 300.0;

void main() {
  void phone(WidgetTester t, Size size, {double keyboard = _kb}) {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1.0;
    t.view.viewInsets = FakeViewPadding(bottom: keyboard);
    addTearDown(t.view.reset);
  }

  /// 앱이 실제로 가는 길 — MaterialApp.builder 에 edgeSafe.
  Widget app(Widget home) => MaterialApp(theme: mbLight(), builder: edgeSafe, home: home);

  /// 글자 · 입력칸 · 버튼 · 목록 행 · 긴 여백을 가진 화면 하나.
  Widget page({VoidCallback? onSave, VoidCallback? onRow, String field = 'f'}) => Scaffold(
        appBar: AppBar(title: const Text('시험')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          const Text('안내문'),
          TextField(key: Key(field), decoration: const InputDecoration(labelText: '값')),
          const SizedBox(height: 8),
          FilledButton(onPressed: onSave ?? () {}, child: const Text('저장')),
          ListTile(title: const Text('행'), onTap: onRow ?? () {}),
          const SizedBox(height: 1200),
          const Text('끝'),
        ]),
      );

  FocusNode focusOf(WidgetTester t, [String field = 'f']) => t
      .widget<EditableText>(
          find.descendant(of: find.byKey(Key(field)), matching: find.byType(EditableText)))
      .focusNode;

  testWidgets('빈 곳(글자)을 탭하면 포커스가 풀리고, 입력칸을 탭하면 다시 잡힌다', (t) async {
    for (final size in _sizes) {
      phone(t, size);
      await t.pumpWidget(app(page()));
      await t.showKeyboard(find.byKey(const Key('f')));
      await t.pumpAndSettle();
      expect(focusOf(t).hasFocus, isTrue);

      await t.tap(find.text('안내문'));
      await t.pumpAndSettle();
      expect(focusOf(t).hasFocus, isFalse, reason: '$size 바깥 탭에 풀려야 합니다');
      expect(FocusManager.instance.primaryFocus?.context?.widget, isNot(isA<EditableText>()));

      await t.tap(find.byKey(const Key('f')));
      await t.pumpAndSettle();
      expect(focusOf(t).hasFocus, isTrue, reason: '$size 칸 탭은 칸이 받아야 합니다');
      await t.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('버튼 · 목록 행의 탭은 가로채지 않는다', (t) async {
    phone(t, _sizes.first);
    var saved = 0, rows = 0;
    await t.pumpWidget(app(page(onSave: () => saved++, onRow: () => rows++)));
    await t.showKeyboard(find.byKey(const Key('f')));
    await t.pumpAndSettle();

    await t.tap(find.text('저장'));
    await t.pumpAndSettle();
    expect(saved, 1, reason: '버튼의 onPressed 가 그대로 와야 합니다');
    await t.tap(find.text('행'));
    await t.pumpAndSettle();
    expect(rows, 1, reason: 'ListTile 의 onTap 이 그대로 와야 합니다');
  });

  testWidgets('목록 끌기(스크롤)는 그대로 된다', (t) async {
    phone(t, _sizes.first);
    await t.pumpWidget(app(page()));
    final before = t.state<ScrollableState>(find.byType(Scrollable).first).position.pixels;
    await t.drag(find.byType(ListView), const Offset(0, -300));
    await t.pumpAndSettle();
    final after = t.state<ScrollableState>(find.byType(Scrollable).first).position.pixels;
    expect(after, greaterThan(before + 100), reason: '바깥 탭 인식기가 스크롤을 막으면 안 됩니다');
  });

  testWidgets('아무 칸도 포커스가 없으면 바깥 탭은 아무 일도 하지 않는다', (t) async {
    phone(t, _sizes.first, keyboard: 0);
    await t.pumpWidget(app(page()));
    final before = FocusManager.instance.primaryFocus;
    await t.tap(find.text('안내문'));
    await t.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus, same(before), reason: '스코프의 포커스를 옮기면 안 됩니다');
    expect(t.takeException(), isNull);
  });

  testWidgets('시맨틱 트리에 화면 전체 크기의 이름 없는 탭 요소를 만들지 않는다', (t) async {
    /* GestureDetector 는 기본으로 자기 onTap 을 시맨틱 tap 액션으로도 냅니다. 그러면
       TalkBack · VoiceOver 가 모든 화면에서 「레이블 없음, 두 번 탭하여 활성화」 를
       하나 더 짚습니다 — excludeFromSemantics 로 빼 두었는지 트리를 훑어 봅니다. */
    for (final size in _sizes) {
      phone(t, size, keyboard: 0);
      final handle = t.ensureSemantics();
      await t.pumpWidget(app(page()));
      await t.pumpAndSettle();

      final taps = <SemanticsNode>[];
      void walk(SemanticsNode n) {
        if (n.getSemanticsData().hasAction(SemanticsAction.tap)) taps.add(n);
        n.visitChildren((c) {
          walk(c);
          return true;
        });
      }
      // ignore: deprecated_member_use
      walk(t.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!);

      expect(taps, isNotEmpty, reason: '버튼 · 행은 여전히 탭 액션을 가져야 합니다');
      final fullScreen = taps.where((n) {
        final d = n.getSemanticsData();
        return d.label.isEmpty &&
            n.rect.width >= size.width &&
            n.rect.height >= size.height;
      });
      expect(fullScreen, isEmpty,
          reason: '$size 화면 전체를 덮는 이름 없는 탭 요소(키보드 닫기 인식기)가 스크린리더에 노출됨');
      handle.dispose();
      await t.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('밀어 올린 화면에서도 바깥 탭에 풀린다', (t) async {
    for (final size in _sizes) {
      phone(t, size);
      await t.pumpWidget(app(page()));
      Navigator.of(t.element(find.text('안내문')))
          .push(MaterialPageRoute(builder: (_) => page(field: 'g')));
      await t.pumpAndSettle();
      await t.showKeyboard(find.byKey(const Key('g')));
      await t.pumpAndSettle();
      expect(focusOf(t, 'g').hasFocus, isTrue);

      await t.tap(find.text('안내문'));
      await t.pumpAndSettle();
      expect(focusOf(t, 'g').hasFocus, isFalse, reason: '$size 밀어 올린 화면도 Navigator 안입니다');
      await t.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('바텀시트 안 빈 곳을 탭하면 시트는 남고 키보드만 내려간다', (t) async {
    for (final size in _sizes) {
      phone(t, size);
      await t.pumpWidget(app(page()));
      showModalBottomSheet<void>(
        context: t.element(find.text('안내문')),
        isScrollControlled: true,
        builder: (ctx) => Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.viewInsetsOf(ctx).bottom),
          child: Column(mainAxisSize: MainAxisSize.min, children: const [
            Text('시트 제목'),
            TextField(key: Key('s'), decoration: InputDecoration(labelText: '시트 값')),
          ]),
        ),
      );
      await t.pumpAndSettle();
      await t.showKeyboard(find.byKey(const Key('s')));
      await t.pumpAndSettle();
      expect(focusOf(t, 's').hasFocus, isTrue);

      await t.tap(find.text('시트 제목'));
      await t.pumpAndSettle();
      expect(focusOf(t, 's').hasFocus, isFalse, reason: '$size 시트(Overlay)도 Navigator 안입니다');
      expect(find.text('시트 제목'), findsOneWidget, reason: '시트 안 탭은 시트를 닫지 않습니다');
      await t.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('다이얼로그 안 빈 곳을 탭하면 다이얼로그는 남고 키보드만 내려간다', (t) async {
    phone(t, _sizes.last);
    await t.pumpWidget(app(page()));
    showDialog<void>(
      context: t.element(find.text('안내문')),
      builder: (_) => const AlertDialog(
        title: Text('물음'),
        content: TextField(key: Key('d'), decoration: InputDecoration(labelText: '답')),
      ),
    );
    await t.pumpAndSettle();
    await t.showKeyboard(find.byKey(const Key('d')));
    await t.pumpAndSettle();
    expect(focusOf(t, 'd').hasFocus, isTrue);

    await t.tap(find.text('물음'));
    await t.pumpAndSettle();
    expect(focusOf(t, 'd').hasFocus, isFalse);
    expect(find.byType(AlertDialog), findsOneWidget, reason: '다이얼로그 안 탭은 배리어가 아닙니다');
  });
}
