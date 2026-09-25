/* =============================================================================
 * exercise_picker_test.dart — 종목 고르기 시트
 *
 * 약속은 하나입니다: 부위 한 번, 종목 한 번 — 두 번 터치로 끝. 나머지(검색 ·
 * 기구 표시 · 여러 개 고르기)는 그 약속을 깨지 않는지 봅니다. 폭은 360px —
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
  Finder sec(String k) => find.byKey(ValueKey('pick-sec-$k'));
  Finder notMine(String k) => find.byKey(ValueKey('pick-notmine-$k'));
  Finder dim(String k) => find.byKey(ValueKey('pick-dim-$k'));
  final mineOnly = find.byKey(const ValueKey('pick-mine-only'));

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
      expect(sec('machine'), findsOneWidget);
      expect(sec('bodyweight'), findsOneWidget);
      expect(mineOnly, findsNothing, reason: 'equip 을 안 주면 토글도 없습니다');
      expect(find.byType(Opacity), findsNothing, reason: 'equip 을 안 주면 전부 내 기구 — 흐린 섹션이 없습니다');
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
      expect(row('hip-abduction-machine'), findsOneWidget, reason: '기구와 상관없이 찾습니다');
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

    testWidgets('기본은 모든 기구 — 덤벨·맨몸뿐이어도 머신 섹션이 바로 보이고, 「내 기구만」 을 켜면 사라진다', (t) async {
      phone(t);
      await launch<Exercise?>(t, (ctx) => pickExercise(ctx, equip: {'dumbbell', 'bodyweight'}), (_) {});
      await t.tap(tile('chest'));
      await t.pumpAndSettle();
      expect(sec('machine'), findsOneWidget, reason: '머신은 토글 뒤에 숨지 않습니다');
      expect(row('chest-press-machine'), findsOneWidget);
      expect(row('bench-press'), findsOneWidget);
      expect(row('db-fly'), findsOneWidget);
      expect(row('push-up'), findsOneWidget);
      expect(t.widget<FilterChip>(mineOnly).selected, isFalse, reason: '기본은 꺼짐');

      await t.tap(mineOnly);
      await t.pumpAndSettle();
      expect(t.widget<FilterChip>(mineOnly).selected, isTrue);
      expect(sec('machine'), findsNothing);
      expect(sec('barbell'), findsNothing);
      expect(row('chest-press-machine'), findsNothing);
      expect(row('bench-press'), findsNothing);
      expect(row('db-fly'), findsOneWidget);
      expect(row('push-up'), findsOneWidget);
      expect(find.byType(Opacity), findsNothing, reason: '남은 섹션은 전부 내 기구 — 흐린 것이 없습니다');
    });

    testWidgets('내 기구가 아닌 섹션은 「내 기구 아님」 표 + 흐리게, 순서는 내 기구(덤벨 → 맨몸) 먼저 · 그 뒤 머신 → 케이블 → 바벨 → 밴드', (t) async {
      phone(t);
      await launch<Exercise?>(t, (ctx) => pickExercise(ctx, equip: {'dumbbell', 'bodyweight'}), (_) {});
      await t.tap(tile('chest'));
      await t.pumpAndSettle();
      for (final k in ['machine', 'cable', 'barbell', 'band']) {
        expect(notMine(k), findsOneWidget, reason: '$k 는 내 기구가 아닙니다');
        expect(t.widget<Opacity>(dim(k)).opacity, lessThan(1), reason: '$k 는 흐리게');
      }
      for (final k in ['dumbbell', 'bodyweight']) {
        expect(notMine(k), findsNothing, reason: '$k 는 내 기구');
        expect(dim(k), findsNothing);
      }
      expect(find.text('내 기구 아님'), findsNWidgets(4));
      /* 순서 — 화면 위에서부터. 내 기구가 먼저 — 집 사용자가 흐린 스무 줄을 넘기지 않게. */
      final order = ['dumbbell', 'bodyweight', 'machine', 'cable', 'barbell', 'band'];
      final ys = [for (final k in order) t.getTopLeft(sec(k)).dy];
      for (var i = 1; i < ys.length; i++) {
        expect(ys[i], greaterThan(ys[i - 1]), reason: '${order[i]} 는 ${order[i - 1]} 아래');
      }
      expect(t.takeException(), isNull);
    });

    testWidgets('헬스장(초보 프리셋 기구)에서는 머신이 여전히 첫 섹션 — 머신 → 케이블 → 덤벨 → 맨몸, 바벨은 뒤', (t) async {
      phone(t);
      await launch<Exercise?>(t, (ctx) => pickExercise(ctx, equip: {'machine', 'cable', 'dumbbell', 'bodyweight'}), (_) {});
      await t.tap(tile('chest'));
      await t.pumpAndSettle();
      final order = ['machine', 'cable', 'dumbbell', 'bodyweight', 'barbell'];
      final ys = [for (final k in order) t.getTopLeft(sec(k)).dy];
      for (var i = 1; i < ys.length; i++) {
        expect(ys[i], greaterThan(ys[i - 1]), reason: '${order[i]} 는 ${order[i - 1]} 아래');
      }
      expect(notMine('barbell'), findsOneWidget);
      expect(notMine('machine'), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('흐린 섹션에서도 고를 수 있다 — 하나 고르기', (t) async {
      phone(t);
      Exercise? got;
      await launch<Exercise?>(t, (ctx) => pickExercise(ctx, equip: {'dumbbell', 'bodyweight'}), (e) => got = e);
      await t.tap(tile('chest'));
      await t.pumpAndSettle();
      expect(dim('machine'), findsOneWidget);
      await t.tap(row('chest-press-machine'));
      await t.pumpAndSettle();
      expect(got?.id, 'chest-press-machine');
    });

    testWidgets('흐린 섹션에서도 고를 수 있다 — 여러 개 고르기', (t) async {
      phone(t);
      List<Exercise>? got;
      await launch<List<Exercise>?>(
          t, (ctx) => pickExercises(ctx, equip: {'dumbbell', 'bodyweight'}), (xs) => got = xs);
      await t.tap(tile('chest'));
      await t.pumpAndSettle();
      await t.tap(row('chest-press-machine'));
      await t.pump();
      expect(t.widget<CheckboxListTile>(row('chest-press-machine')).value, isTrue);
      expect(find.text('완료 1'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('pick-done')));
      await t.pumpAndSettle();
      expect(got?.map((e) => e.id).toList(), ['chest-press-machine']);
    });

    testWidgets('맨몸은 기구 목록에 없어도 내 기구 — 「내 기구만」 을 켜도 남는다', (t) async {
      phone(t);
      await launch<Exercise?>(t, (ctx) => pickExercise(ctx, equip: {'machine'}), (_) {});
      await t.tap(tile('core'));
      await t.pumpAndSettle();
      expect(row('plank'), findsOneWidget);
      expect(notMine('bodyweight'), findsNothing, reason: '맨몸은 언제나 내 기구');
      expect(notMine('cable'), findsOneWidget);
      expect(row('cable-crunch'), findsOneWidget, reason: '기본은 전부 보임');
      await t.tap(mineOnly);
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
         「내 기구만」(목록 첫 줄)이 보여야 합니다 — 세 ListView 의 키가 다르지 않으면
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
      expect(mineOnly.hitTestable(), findsOneWidget);
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
      expect(sec('machine'), findsOneWidget);
      expect(find.widgetWithText(Pill, '머신'), findsNothing, reason: '머리글이 이미 「머신」 입니다');
      await t.enterText(find.byKey(const ValueKey('pick-search')), '로우');
      await t.pumpAndSettle();
      expect(find.widgetWithText(Pill, '머신'), findsWidgets, reason: '검색 결과는 섹션이 없으니 줄마다');
    });

    testWidgets('부위 칩의 숫자는 전체 종목 수 — 「내 기구만」 을 켜고 오가도 그대로, 토글은 시트 안에서 유지', (t) async {
      phone(t);
      await launch<Exercise?>(t, (ctx) => pickExercise(ctx, equip: {'dumbbell', 'bodyweight'}), (_) {});
      List<String?> badge() => find.descendant(of: tile('chest'), matching: find.byType(Text)).evaluate()
          .map((e) => (e.widget as Text).data).toList();
      final before = badge();
      expect(before, contains('${exercisesFor('chest').length}'), reason: '내 기구 수(8)가 아니라 전체 수');
      await t.tap(tile('chest'));
      await t.pumpAndSettle();
      await t.tap(mineOnly);
      await t.pumpAndSettle();
      expect(row('chest-press-machine'), findsNothing);
      await t.tap(find.byKey(const ValueKey('pick-back')));
      await t.pumpAndSettle();
      expect(badge(), before);
      await t.tap(tile('back'));
      await t.pumpAndSettle();
      expect(t.widget<FilterChip>(mineOnly).selected, isTrue, reason: '다른 부위에서도 켜진 채 — 한 번 덜 누릅니다');
      expect(sec('machine'), findsNothing);
      expect(sec('dumbbell'), findsOneWidget);
    });

    testWidgets('「내 기구만」 을 켜고 내 기구 종목이 없는 부위는 빈 화면 — 끄라고 말한다', (t) async {
      phone(t);
      /* 맨몸은 언제나 내 기구라 어느 부위든 뭔가 남습니다 — 어깨의 맨몸 · 케틀벨 종목을 exclude 로
         빼서(이미 세션에 있는 셈) 케틀벨만 가진 사람의 빈 화면을 만듭니다. */
      final gone = {for (final e in exercisesFor('shoulder')) if (e.equip == 'bodyweight' || e.equip == 'kettlebell') e.id};
      expect(gone, isNotEmpty);
      await launch<Exercise?>(t, (ctx) => pickExercise(ctx, equip: {'kettlebell'}, exclude: gone), (_) {});
      await t.tap(tile('shoulder'));
      await t.pumpAndSettle();
      expect(sec('machine'), findsOneWidget, reason: '끄면 전부 보입니다');
      await t.tap(mineOnly);
      await t.pumpAndSettle();
      expect(sec('machine'), findsNothing);
      expect(find.text('내 기구로 되는 종목이 없습니다'), findsOneWidget);
      expect(find.text('「내 기구만」 을 꺼 보세요.'), findsOneWidget);
    });

    testWidgets('토글이 꺼진 채 부위 종목이 전부 세션에 있으면 — 「꺼 보세요」 가 아니라 「이미 다 들어 있습니다」', (t) async {
      phone(t);
      final gone = {for (final e in exercisesFor('shoulder')) e.id};
      await launch<Exercise?>(t, (ctx) => pickExercise(ctx, equip: {'dumbbell'}, exclude: gone), (_) {});
      await t.tap(tile('shoulder'));
      await t.pumpAndSettle();
      expect(t.widget<FilterChip>(mineOnly).selected, isFalse);
      expect(find.text('이 부위 종목은 이미 다 들어 있습니다'), findsOneWidget);
      expect(find.textContaining('꺼 보세요'), findsNothing, reason: '꺼져 있는 것을 끄라고 하면 안 됩니다');
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

    testWidgets('360px · 글자 1.3배 — 「내 기구 아님」 표가 붙은 머리글도 넘치지 않는다', (t) async {
      phone(t);
      t.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      await launch<Exercise?>(t, (ctx) => pickExercise(ctx, equip: {'bodyweight'}), (_) {});
      await t.tap(tile('hamsGlutes'));
      await t.pumpAndSettle();
      expect(notMine('machine'), findsOneWidget);
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
