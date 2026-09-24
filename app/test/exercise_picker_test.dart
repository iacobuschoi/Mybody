/* =============================================================================
 * exercise_picker_test.dart — 종목 고르기 시트
 *
 * 약속은 하나입니다: 부위 한 번, 종목 한 번 — 두 번 터치로 끝. 나머지(검색 ·
 * 기구 필터 · 여러 개 고르기)는 그 약속을 깨지 않는지 봅니다. 폭은 360px —
 * 넘치면 Flutter 가 예외를 던져 테스트가 깨집니다.
 * ========================================================================== */
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mybody/src/screens/exercise_picker.dart';
import 'package:mybody/src/theme.dart';
import 'package:mybody/src/ui/widgets.dart';
import 'package:mybody/src/workout/exercises.dart';

void main() {
  /// 360px 폭. 높이는 넉넉히 — 목록이 한 화면에 다 그려져야 찾을 수 있습니다.
  void phone(WidgetTester t, {double height = 2400}) {
    t.view.physicalSize = Size(360, height);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
  }

  /// 버튼 하나짜리 화면 — 누르면 [open] 이 시트를 열고, 닫힌 값을 돌려줍니다.
  Future<void> launch<T>(WidgetTester t, Future<T> Function(BuildContext) open, void Function(T) got) async {
    await t.pumpWidget(MaterialApp(
      theme: mbLight(),
      home: Scaffold(
        body: Builder(
          builder: (ctx) => TextButton(
            onPressed: () async => got(await open(ctx)),
            child: const Text('열기'),
          ),
        ),
      ),
    ));
    await t.tap(find.text('열기'));
    await t.pumpAndSettle();
  }

  Finder row(String id) => find.byKey(ValueKey('pick-$id'));
  Finder tile(String g) => find.byKey(ValueKey('pick-group-$g'));

  group('종목 고르기 시트', () {
    testWidgets('부위 → 종목, 두 번 터치로 끝', (t) async {
      phone(t);
      Exercise? got;
      var closed = false;
      await launch<Exercise?>(t, (ctx) => pickExercise(ctx), (e) {
        got = e;
        closed = true;
      });
      /* 첫 화면: 영역 세 줄에 부위 여덟 개가 한 화면에. */
      for (final area in ['상체', '하체', '코어·전신']) {
        expect(find.text(area), findsOneWidget);
      }
      for (final g in kGroupLabel.keys) {
        expect(tile(g), findsOneWidget, reason: g);
      }
      expect(find.text('최근'), findsNothing, reason: '최근이 없으면 줄도 없습니다');

      await t.tap(tile('chest'));                                        // 터치 1
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('pick-sec-machine')), findsOneWidget);
      expect(find.byKey(const ValueKey('pick-sec-bodyweight')), findsOneWidget);
      expect(find.byKey(const ValueKey('pick-all-equip')), findsNothing, reason: 'equip 을 안 주면 토글도 없습니다');
      expect(find.text('팔꿈치 살짝 굽혀 고정'), findsOneWidget, reason: '한 줄 요령');

      await t.tap(row('pec-deck'));                                       // 터치 2
      await t.pumpAndSettle();
      expect(closed, isTrue);
      expect(got?.id, 'pec-deck');
      expect(find.byKey(const ValueKey('pick-search')), findsNothing, reason: '시트가 닫혔습니다');
    });

    testWidgets('뒤로 가면 부위 목록', (t) async {
      phone(t);
      await launch<Exercise?>(t, (ctx) => pickExercise(ctx), (_) {});
      await t.tap(tile('back'));
      await t.pumpAndSettle();
      expect(find.text('등'), findsOneWidget);
      expect(tile('chest'), findsNothing);
      await t.tap(find.byKey(const ValueKey('pick-back')));
      await t.pumpAndSettle();
      expect(tile('chest'), findsOneWidget);
    });

    testWidgets('검색은 별칭도 찾고, 탭하면 그 종목', (t) async {
      phone(t);
      Exercise? got;
      await launch<Exercise?>(t, (ctx) => pickExercise(ctx, equip: {'dumbbell', 'bodyweight'}), (e) => got = e);
      await t.enterText(find.byKey(const ValueKey('pick-search')), '아웃싸이');
      await t.pumpAndSettle();
      expect(row('hip-abduction-machine'), findsOneWidget, reason: '기구 필터와 상관없이 찾습니다');
      expect(find.textContaining('허벅지 뒤·엉덩이'), findsWidgets, reason: '검색 줄에는 부위가 붙습니다');
      expect(row('bench-press'), findsNothing);
      await t.tap(row('hip-abduction-machine'));
      await t.pumpAndSettle();
      expect(got?.id, 'hip-abduction-machine');
    });

    testWidgets('없는 말은 빈 화면', (t) async {
      phone(t);
      await launch<Exercise?>(t, (ctx) => pickExercise(ctx), (_) {});
      await t.enterText(find.byKey(const ValueKey('pick-search')), 'zzzz없는종목');
      await t.pumpAndSettle();
      expect(find.text('맞는 종목이 없습니다'), findsOneWidget);
    });

    testWidgets('exclude 는 안 보인다 — 목록에서도 최근 줄에서도', (t) async {
      phone(t);
      await launch<Exercise?>(
          t, (ctx) => pickExercise(ctx, exclude: {'bench-press', 'plank'}, recent: ['plank', 'crunch']), (_) {});
      expect(find.byKey(const ValueKey('pick-quick-plank')), findsNothing);
      expect(find.byKey(const ValueKey('pick-quick-crunch')), findsOneWidget);
      await t.tap(tile('chest'));
      await t.pumpAndSettle();
      expect(row('bench-press'), findsNothing);
      expect(row('db-fly'), findsOneWidget);
    });

    testWidgets('equip 필터 — 내 기구만, 토글로 전부', (t) async {
      phone(t);
      await launch<Exercise?>(t, (ctx) => pickExercise(ctx, equip: {'dumbbell', 'bodyweight'}), (_) {});
      await t.tap(tile('chest'));
      await t.pumpAndSettle();
      expect(row('chest-press-machine'), findsNothing);
      expect(row('bench-press'), findsNothing);
      expect(row('db-fly'), findsOneWidget);
      expect(row('push-up'), findsOneWidget);
      expect(find.byKey(const ValueKey('pick-sec-machine')), findsNothing);

      await t.tap(find.byKey(const ValueKey('pick-all-equip')));
      await t.pumpAndSettle();
      expect(row('chest-press-machine'), findsOneWidget);
      expect(row('bench-press'), findsOneWidget);
      expect(find.byKey(const ValueKey('pick-sec-machine')), findsOneWidget);
    });

    testWidgets('맨몸은 기구 목록에 없어도 보인다', (t) async {
      phone(t);
      await launch<Exercise?>(t, (ctx) => pickExercise(ctx, equip: {'machine'}), (_) {});
      await t.tap(tile('core'));
      await t.pumpAndSettle();
      expect(row('plank'), findsOneWidget);
      expect(row('cable-crunch'), findsNothing);
    });

    testWidgets('최근 · 익숙한 종목은 맨 위, 한 번에', (t) async {
      phone(t);
      Exercise? got;
      await launch<Exercise?>(
          t, (ctx) => pickExercise(ctx, recent: ['plank', 'nope-id'], familiar: ['leg-press']), (e) => got = e);
      expect(find.text('최근'), findsOneWidget);
      expect(find.text('익숙한 종목'), findsOneWidget);
      expect(find.byKey(const ValueKey('pick-quick-nope-id')), findsNothing, reason: '모르는 id 는 조용히 뺍니다');
      await t.tap(find.byKey(const ValueKey('pick-quick-plank')));
      await t.pumpAndSettle();
      expect(got?.id, 'plank');
    });

    testWidgets('여러 개 — 체크 토글 · 완료 · 순서', (t) async {
      phone(t);
      List<Exercise>? got;
      var done = false;
      await launch<List<Exercise>?>(t, (ctx) => pickExercises(ctx, selected: {'bench-press'}, title: '종목 추가'),
          (xs) {
        got = xs;
        done = true;
      });
      expect(find.text('종목 추가'), findsOneWidget);
      expect(find.text('완료 1'), findsOneWidget);
      await t.tap(tile('chest'));
      await t.pumpAndSettle();
      expect(t.widget<CheckboxListTile>(row('bench-press')).value, isTrue);
      await t.tap(row('db-fly'));
      await t.pump();
      await t.tap(row('push-up'));
      await t.pump();
      await t.tap(row('db-fly'));                                         // 다시 눌러 뺌
      await t.pump();
      expect(find.text('완료 2'), findsOneWidget);
      expect(done, isFalse, reason: '체크만으로는 안 닫힙니다');
      await t.tap(find.byKey(const ValueKey('pick-done')));
      await t.pumpAndSettle();
      expect(done, isTrue);
      expect(got?.map((e) => e.id).toList(), ['bench-press', 'push-up']);
    });

    testWidgets('여러 개 — 그냥 내리면 null', (t) async {
      phone(t);
      List<Exercise>? got = const [];
      await launch<List<Exercise>?>(t, (ctx) => pickExercises(ctx), (xs) => got = xs);
      await t.tapAt(const Offset(180, 20));                               // 시트 밖
      await t.pumpAndSettle();
      expect(got, isNull);
    });

    testWidgets('첫 화면을 내린 뒤 부위를 눌러도 부위 목록은 맨 위부터 — 스크롤 위치를 물려받지 않는다', (t) async {
      /* 최근 · 익숙한 종목이 많으면 첫 화면이 길어집니다. 700px 높이에서 내렸다가 부위를 누르면
         「다른 기구도 보기」(목록 첫 줄)가 보여야 합니다 — 세 ListView 의 키가 다르지 않으면
         Flutter 가 스크롤 위치를 재사용해 목록이 끝부터 열렸습니다. */
      phone(t, height: 700);
      final ids = [for (final e in kExerciseLibrary.take(60)) e.id];
      await launch<Exercise?>(t, (ctx) => pickExercise(ctx,
          equip: {'machine', 'cable', 'dumbbell', 'bodyweight'}, recent: ids.sublist(0, 30), familiar: ids.sublist(30)), (_) {});
      ScrollPosition posOf(Finder list) =>
          t.state<ScrollableState>(find.descendant(of: list, matching: find.byType(Scrollable))).position;
      final home = find.byKey(const ValueKey('pick-home'));
      expect(home, findsOneWidget);
      /* 칩 60개 아래에 있는 「가슴」 까지 내립니다 — 첫 화면이 실제로 내려가 있어야 시험이 뜻이 있습니다. */
      await t.scrollUntilVisible(tile('chest'), 150,
          scrollable: find.descendant(of: home, matching: find.byType(Scrollable)));
      await t.pumpAndSettle();
      expect(posOf(home).pixels, greaterThan(100));
      await t.tap(tile('chest'));
      await t.pumpAndSettle();
      final list = find.byKey(const ValueKey('pick-group-list-chest'));
      expect(list, findsOneWidget);
      expect(posOf(list).pixels, 0);
      expect(find.byKey(const ValueKey('pick-all-equip')).hitTestable(), findsOneWidget);
      /* 돌아와도 첫 화면은 맨 위. */
      await t.tap(find.byKey(const ValueKey('pick-back')));
      await t.pumpAndSettle();
      expect(posOf(home).pixels, 0);
      expect(t.takeException(), isNull);
    });

    testWidgets('기구별 섹션 안 줄에는 기구 표를 또 달지 않고, 검색 줄에만 단다', (t) async {
      phone(t);
      await launch<Exercise?>(t, (ctx) => pickExercise(ctx), (_) {});
      await t.tap(tile('back'));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('pick-sec-machine')), findsOneWidget);
      expect(find.widgetWithText(Pill, '머신'), findsNothing, reason: '머리글이 이미 「머신」 입니다');
      await t.enterText(find.byKey(const ValueKey('pick-search')), '로우');
      await t.pumpAndSettle();
      expect(find.widgetWithText(Pill, '머신'), findsWidgets, reason: '검색 결과는 섹션이 없으니 줄마다');
    });

    testWidgets('「다른 기구도 보기」 는 부위 화면을 나가면 꺼진다 — 부위 칩의 숫자가 바뀌지 않는다', (t) async {
      phone(t);
      await launch<Exercise?>(t, (ctx) => pickExercise(ctx, equip: {'dumbbell', 'bodyweight'}), (_) {});
      final before = find.descendant(of: tile('chest'), matching: find.byType(Text)).evaluate()
          .map((e) => (e.widget as Text).data).toList();
      await t.tap(tile('chest'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('pick-all-equip')));
      await t.pumpAndSettle();
      expect(row('chest-press-machine'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('pick-back')));
      await t.pumpAndSettle();
      final after = find.descendant(of: tile('chest'), matching: find.byType(Text)).evaluate()
          .map((e) => (e.widget as Text).data).toList();
      expect(after, before);
      await t.tap(tile('chest'));
      await t.pumpAndSettle();
      expect(row('chest-press-machine'), findsNothing, reason: '다시 들어가면 내 기구만');
    });

    testWidgets('360px · 글자 1.3배 — 여러 개 고르기 줄의 긴 이름과 요령이 잘리지 않는다', (t) async {
      phone(t);
      t.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      await launch<List<Exercise>?>(t, (ctx) => pickExercises(ctx, equip: {'machine', 'cable', 'dumbbell', 'bodyweight'}), (_) {});
      await t.enterText(find.byKey(const ValueKey('pick-search')), '프레스');
      await t.pumpAndSettle();
      for (final text in ['인클라인 체스트 프레스 머신', '디클라인 체스트 프레스 머신', '가슴 · 벤치가 없을 때 바닥에 누워서']) {
        final rp = t.renderObject<RenderParagraph>(find.text(text).first);
        expect(rp.didExceedMaxLines, isFalse, reason: '「$text」 이 잘렸습니다');
      }
      expect(t.takeException(), isNull);
    });

    testWidgets('360 × 800 에서 긴 이름 부위도 넘치지 않는다', (t) async {
      phone(t, height: 800);
      await launch<Exercise?>(t, (ctx) => pickExercise(ctx, equip: {'machine', 'cable', 'barbell', 'dumbbell', 'bodyweight'}, familiar: ['single-leg-rdl']), (_) {});
      await t.tap(tile('hamsGlutes'));
      await t.pumpAndSettle();
      expect(find.text('허벅지 뒤·엉덩이'), findsOneWidget);
      await t.drag(find.byType(ListView), const Offset(0, -1500));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const ValueKey('pick-search')), '데드');
      await t.pumpAndSettle();
      expect(row('single-leg-rdl'), findsOneWidget);
    });
  });
}
