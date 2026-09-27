/* =============================================================================
 * gym_settings_test.dart — 「운동 장소와 기구」 카드
 *
 * workout_screens_test.dart 에 있던 묶음을 따로 뗐습니다 — 헬스 화면과 기구 설정
 * 화면을 서로 다른 사람이 동시에 고칠 때 한 파일을 같이 만지지 않기 위해서입니다.
 *
 * 전부 360px 폭에서 돕니다 — 넘치면 Flutter 가 예외를 던져 테스트가 깨집니다.
 * 보는 것: 장소 카드 → 프리셋, 기구 타일 토글(맨몸은 잠김), 머신 수 세그먼트 →
 * machineCount, 익숙한 종목은 고르기 시트를 거쳐 id 로 남고 부위별 칩이 되는가,
 * 초보 프리셋 표와 되돌리기.
 *
 * 익숙한 종목 칩은 접힌 채 시작합니다(피드백 39: "설정에서 익숙한 종목은 펼치기
 * 버튼 만들어서 펼쳐야 보이게"). 그래서 칩을 보는 시험은 먼저 머리글을 눌러
 * 펼칩니다(expandFamiliar). 접힘 자체는 맨 아래 묶음이 봅니다 — 처음엔 접힘 ·
 * 머리글 어디를 눌러도 펼침/접힘 · 목록 끝 「접기」 가 화면 밖 머리글을 되돌림 ·
 * 「추가」 는 접힌 채 개수만 · 빈 목록은 「없음」 뿐 · 360px 에 글자 1.3배, 밝게 ·
 * 어둡게 둘 다 넘치지 않음.
 * ========================================================================== */
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mybody/src/api.dart';
import 'package:mybody/src/app_state.dart';
import 'package:mybody/src/scope.dart';
import 'package:mybody/src/screens/gym_settings.dart';
import 'package:mybody/src/theme.dart';
import 'package:mybody/src/ui/widgets.dart';
import 'package:mybody/src/workout/exercises.dart';
import 'package:mybody/src/workout/prefs.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<AppState> seeded() async {
    SharedPreferences.setMockInitialValues({});
    final app = await AppState.boot();
    app.store.set({'profile': _profile, 'onboarded': true});
    app.store.addScan({..._scan});
    return app;
  }

  Api api() {
    final a = Api(baseUrl: '', client: MockClient((_) async => http.Response('{"ok":false}', 404)));
    a.setToken('tok');
    return a;
  }

  Widget host(AppState app, Widget child, {ThemeData? theme}) => Scope(
        state: app,
        api: api(),
        onServerChange: (_) async {},
        child: MaterialApp(theme: theme ?? mbLight(), home: child),
      );

  /// 360px 폰. 높이는 넉넉히 — 카드가 한 화면에 다 그려져야 찾을 수 있습니다.
  /// [below] 는 카드 아래 자리 — 설정 화면처럼 밑에 다른 카드가 이어지는 모양.
  Future<AppState> open(WidgetTester t, {double height = 1600, List<Widget> below = const []}) async {
    final app = await seeded();
    t.view.physicalSize = Size(360, height);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(host(app, Scaffold(body: ListView(children: [const GymSettingsCard(), ...below]))));
    await t.pump();
    return app;
  }

  final famToggle = find.byKey(const Key('gym-fam-toggle'));
  final famCollapse = find.byKey(const Key('gym-fam-collapse'));
  final famAdd = find.byKey(const Key('gym-fam-add'));
  String? famCount(WidgetTester t) => t.widget<Text>(find.byKey(const Key('gym-fam-count'))).data;

  /// 익숙한 종목 칩을 펼칩니다 — 칩은 접힌 채 시작합니다(피드백 39).
  Future<void> expandFamiliar(WidgetTester t) async {
    await t.ensureVisible(famToggle);
    await t.pumpAndSettle();
    await t.tap(famToggle);
    await t.pumpAndSettle();
  }

  Map<String, Object?> saved(AppState app) =>
      ((app.state['settings'] as Map)['gym'] as Map).cast<String, Object?>();
  GymPrefs prefs(AppState app) =>
      GymPrefs.fromSettings((app.state['settings'] as Map?)?.cast<String, Object?>());

  Finder tile(String key) => find.byKey(Key('gym-equip-$key'));

  /// 글이 잘리거나(…) 칸보다 넓지 않은가 — 넘침은 예외로 잡히지만 잘림은 조용해서 따로 봅니다.
  void fits(WidgetTester t, String text) {
    final rp = t.renderObject<RenderParagraph>(find.text(text).last);
    expect(rp.didExceedMaxLines, isFalse, reason: '「$text」 이 잘렸습니다');
    expect(rp.getMaxIntrinsicWidth(double.infinity), lessThanOrEqualTo(rp.size.width + 0.01),
        reason: '「$text」 이 칸보다 넓습니다');
  }

  group('설정 — 운동 장소와 기구', () {
    testWidgets('처음은 초보 프리셋 — 「초보 기본」 표 · 요약 한 줄 · 머신 4', (t) async {
      final app = await open(t);
      expect(find.text('운동 장소와 기구'), findsOneWidget);
      expect(find.widgetWithText(Pill, '초보 기본'), findsOneWidget);
      expect(find.byKey(const Key('gym-reset')), findsNothing, reason: '이미 기본이면 되돌릴 것이 없습니다');
      /* '머신 4대' 는 헬스장에 있는 머신 수로 읽혔습니다(피드백 13) — '하루 머신 4대'. */
      expect(find.text('헬스장 · 기구 3종 · 하루 머신 4대 · 익숙한 종목 없음'), findsOneWidget);
      expect(prefs(app).isBeginnerPreset, isTrue);
      expect(app.state['settings'] is Map && (app.state['settings'] as Map)['gym'] != null, isFalse,
          reason: '보기만 해서는 저장하지 않습니다');
      /* 세그먼트는 4 가 골라져 있습니다. */
      final seg = t.widget<SegmentedButton<int>>(find.byKey(const Key('gym-machines')));
      expect(seg.selected, {kMachineStops.indexOf(4)});
      expect(t.takeException(), isNull);
    });

    testWidgets('장소 카드 — 집을 누르면 home · 집 기구 · 머신 수 없음, 헬스장은 초보 프리셋', (t) async {
      final app = await open(t);
      expect(find.text('하루에 쓸 머신 수'), findsOneWidget);
      await t.tap(find.byKey(const Key('gym-place-home')));
      await t.pump();
      expect(saved(app)['place'], 'home');
      expect(prefs(app).equipment, kHomeEquipment);
      expect(saved(app)['machineCount'], isNull);
      expect(find.text('하루에 쓸 머신 수'), findsNothing);
      expect(find.textContaining('집 · 기구 2종'), findsOneWidget);

      /* 집에서 바벨을 켜 두고 헬스장으로 — 헬스장의 프리셋(초보)으로 갑니다. */
      await t.tap(tile('barbell'));
      await t.pump();
      expect(prefs(app).equipment, contains('barbell'));
      await t.tap(find.byKey(const Key('gym-place-gym')));
      await t.pump();
      expect(saved(app)['place'], 'gym');
      expect(prefs(app).equipment, kBeginnerEquipment);
      expect(saved(app)['machineCount'], kBeginnerMachineCount);
      expect(find.text('하루에 쓸 머신 수'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('옛 판의 machineCount 0 — 세그먼트 · 요약 · 규칙이 전부 첫 눈금(2)으로 같다', (t) async {
      final app = await open(t);
      app.store.set({'settings': {...(app.state['settings'] as Map? ?? const {}), 'gym': {
        'place': 'gym', 'equipment': ['machine', 'cable', 'dumbbell', 'bodyweight'], 'machineCount': 0, 'familiar': <String>[],
      }}});
      await t.pump();
      expect(prefs(app).machineCount, kMachineCountMin);
      final seg = t.widget<SegmentedButton<int>>(find.byKey(const Key('gym-machines')));
      expect(seg.selected, {0});
      expect(find.textContaining('하루 머신 $kMachineCountMin대'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('이미 고른 「헬스장」 을 다시 눌러도 기구 · 머신 수가 초보 프리셋으로 돌아가지 않는다', (t) async {
      final app = await open(t);
      await t.tap(tile('barbell'));
      await t.pump();
      await t.tap(find.text('무제한'));
      await t.pump();
      expect(prefs(app).equipment, contains('barbell'));
      expect(saved(app)['machineCount'], isNull);

      await t.tap(find.byKey(const Key('gym-place-gym')));     // 확인 삼아 한 번 더
      await t.pump();
      expect(prefs(app).equipment, contains('barbell'), reason: '바벨이 꺼지면 안 됩니다');
      expect(saved(app)['machineCount'], isNull, reason: '머신 4 로 돌아가면 안 됩니다');
      expect(find.widgetWithText(Pill, '초보 기본'), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('기구 타일 — 켜고 끄면 settings[gym] 에 남고, 맨몸은 잠겨 있다', (t) async {
      final app = await open(t);
      for (final k in kEquipLabel.keys) {
        expect(tile(k), findsOneWidget, reason: k);
      }
      expect(prefs(app).equipment, isNot(contains('barbell')), reason: '초보 프리셋에 바벨은 없습니다');

      await t.tap(tile('barbell'));
      await t.pump();
      expect(prefs(app).equipment, contains('barbell'));
      expect(saved(app)['equipment'], contains('barbell'));
      expect(find.widgetWithText(Pill, '초보 기본'), findsNothing, reason: '프리셋에서 벗어났습니다');
      expect(find.byKey(const Key('gym-reset')), findsOneWidget);

      await t.tap(tile('barbell'));
      await t.pump();
      expect(prefs(app).equipment, isNot(contains('barbell')));
      expect(find.widgetWithText(Pill, '초보 기본'), findsOneWidget, reason: '돌아오면 표도 돌아옵니다');

      /* 맨몸은 눌러도 그대로 — 저장도 안 합니다. */
      await t.tap(tile('bodyweight'));
      await t.pump();
      expect(prefs(app).equipment, contains('bodyweight'));
      expect(find.widgetWithText(Pill, '초보 기본'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('하루에 쓸 머신 수 — 세그먼트가 machineCount 가 되고, 머신·케이블을 다 끄면 숨는다', (t) async {
      final app = await open(t);
      await t.tap(find.text('무제한'));
      await t.pump();
      expect(saved(app)['machineCount'], isNull);
      expect(find.textContaining('머신 제한 없음'), findsOneWidget, reason: '요약에서는 「제한 없음」');
      expect(machineLabel(null), '무제한', reason: '세그먼트 칸은 「무제한」');
      expect(machineSummary(4), '하루 머신 4대');

      await t.tap(find.descendant(of: find.byKey(const Key('gym-machines')), matching: find.text('2')));
      await t.pump();
      expect(saved(app)['machineCount'], 2);
      expect(find.textContaining('하루 머신 2대'), findsOneWidget);

      /* 눈금 사이 · 눈금 아래 값은 그 아래 눈금(첫 눈금)으로 보입니다. */
      expect(machineStopIndex(3), kMachineStops.indexOf(2), reason: '3 은 2 눈금');
      expect(machineStopIndex(0), 0, reason: '0 은 첫 눈금');
      expect(kMachineStops.first, kMachineCountMin, reason: '첫 눈금 = fromSettings 가 옛 0·1 을 올리는 값');
      expect(machineStopIndex(6), kMachineStops.indexOf(6));
      expect(machineStopIndex(null), kMachineStops.length - 1);

      await t.tap(tile('machine'));
      await t.pump();
      expect(find.byKey(const Key('gym-machines')), findsOneWidget, reason: '케이블이 남아 있습니다');
      await t.tap(tile('cable'));
      await t.pump();
      expect(find.byKey(const Key('gym-machines')), findsNothing);
      expect(find.text('하루에 쓸 머신 수'), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('익숙한 종목 — 시트에서 부위 → 종목 → 완료, id 가 남고 부위 아래 칩 · x 로 뺀다', (t) async {
      final app = await open(t, height: 2400);
      expect(find.text('없음'), findsOneWidget);
      await t.tap(find.byKey(const Key('gym-fam-add')));
      await t.pumpAndSettle();
      expect(find.text('익숙한 종목'), findsWidgets, reason: '시트 제목');
      await t.tap(find.byKey(const ValueKey('pick-group-chest')));                 // 터치 1
      await t.pumpAndSettle();
      /* 모든 기구가 보이되 바벨은 「내 기구 아님」 표 + 흐리게(3차 피드백 32) — 머신 · 덤벨은 내 기구. */
      expect(find.byKey(const ValueKey('pick-notmine-barbell')), findsOneWidget);
      expect(find.byKey(const ValueKey('pick-dim-barbell')), findsOneWidget);
      expect(find.byKey(const ValueKey('pick-notmine-machine')), findsNothing);
      expect(find.byKey(const ValueKey('pick-chest-press-machine')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('pick-chest-press-machine')));         // 터치 2
      await t.pump();
      await t.tap(find.byKey(const ValueKey('pick-done')));                        // 터치 3
      await t.pumpAndSettle();
      expect(saved(app)['familiar'], ['chest-press-machine']);
      expect(find.textContaining('익숙한 종목 1개'), findsOneWidget);
      /* 칩은 접힌 채(피드백 39) — 펼쳐야 보입니다. */
      expect(find.byType(InputChip), findsNothing);
      await expandFamiliar(t);
      expect(find.widgetWithText(InputChip, '체스트 프레스 머신'), findsOneWidget);
      expect(find.text('가슴'), findsOneWidget, reason: '부위 머리글');

      /* 다시 열면 체크된 채 — 하나 더 고르면 둘, 순서는 먼저 고른 것이 앞. */
      await t.tap(find.byKey(const Key('gym-fam-add')));
      await t.pumpAndSettle();
      expect(find.text('완료 1'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('pick-group-quads')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('pick-leg-press')));
      await t.pump();
      await t.tap(find.byKey(const ValueKey('pick-done')));
      await t.pumpAndSettle();
      expect(saved(app)['familiar'], ['chest-press-machine', 'leg-press']);
      expect(find.text('허벅지 앞'), findsOneWidget);

      /* 칩의 x 로 뺍니다. */
      await t.tap(find.descendant(
          of: find.byKey(const Key('gym-fam-chest-press-machine')), matching: find.byType(Icon)));
      await t.pumpAndSettle();
      expect(saved(app)['familiar'], ['leg-press']);
      expect(find.text('가슴'), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('익숙한 종목 — 사전에 없는 번호(다른 기기의 새 사전)는 「완료」 를 눌러도 지워지지 않는다', (t) async {
      final app = await open(t, height: 2400);
      updateGymPrefs(app, (p) => p.copyWith(familiar: ['plank', 'future-machine-x', 'old-id-y']));
      await t.pump();
      await expandFamiliar(t);
      expect(find.text('기타'), findsOneWidget);
      await t.tap(find.byKey(const Key('gym-fam-add')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('pick-group-chest')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('pick-chest-press-machine')));
      await t.pump();
      await t.tap(find.byKey(const ValueKey('pick-done')));
      await t.pumpAndSettle();
      expect(saved(app)['familiar'], ['plank', 'chest-press-machine', 'future-machine-x', 'old-id-y']);
      expect(find.text('기타'), findsOneWidget);
      expect(find.widgetWithText(InputChip, 'future-machine-x'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('익숙한 종목 — 시트를 그냥 내리면 아무것도 안 바뀐다', (t) async {
      final app = await open(t, height: 2400);
      updateGymPrefs(app, (p) => p.copyWith(familiar: ['plank']));
      await t.pump();
      await expandFamiliar(t);
      await t.tap(find.byKey(const Key('gym-fam-add')));
      await t.pumpAndSettle();
      await t.tapAt(const Offset(180, 20));                                          // 시트 밖
      await t.pumpAndSettle();
      expect(saved(app)['familiar'], ['plank']);
      expect(find.widgetWithText(InputChip, '플랭크'), findsOneWidget);
    });

    testWidgets('「초보 기본으로」 — 확인하면 프리셋으로, 취소하면 그대로', (t) async {
      final app = await open(t);
      updateGymPrefs(app, (p) => p.copyWith(
          place: 'home', equipment: {'bodyweight', 'band'}, machineCount: null, familiar: ['plank']));
      await t.pump();
      expect(find.widgetWithText(Pill, '초보 기본'), findsNothing);

      await t.tap(find.byKey(const Key('gym-reset')));
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await t.tap(find.text('취소'));
      await t.pumpAndSettle();
      expect(saved(app)['place'], 'home');
      expect(saved(app)['familiar'], ['plank']);

      await t.tap(find.byKey(const Key('gym-reset')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('gym-reset-ok')));
      await t.pumpAndSettle();
      expect(saved(app), const GymPrefs.beginner().toJson());
      expect(find.widgetWithText(Pill, '초보 기본'), findsOneWidget);
      expect(find.byKey(const Key('gym-reset')), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('360px — 부위 여덟 개에 긴 이름 칩이 가득해도 넘치지 않는다', (t) async {
      final app = await open(t, height: 2400);
      /* 부위마다 가장 긴 이름의 종목 셋씩 + 사전에 없는 번호 하나. */
      final ids = <String>[];
      for (final g in kGroupLabel.keys) {
        final xs = exercisesFor(g).toList()..sort((a, b) => b.name.length.compareTo(a.name.length));
        ids.addAll(xs.take(3).map((e) => e.id));
      }
      ids.add('unknown-exercise-id');
      updateGymPrefs(app, (p) => p.copyWith(equipment: {...kGymEquipment, 'band', 'kettlebell'}, familiar: ids));
      await t.pump();
      await expandFamiliar(t);
      for (final g in kGroupLabel.values) {
        expect(find.text(g), findsOneWidget, reason: g);
      }
      expect(find.text('기타'), findsOneWidget);
      expect(find.widgetWithText(InputChip, 'unknown-exercise-id'), findsOneWidget);
      expect(find.textContaining('익숙한 종목 ${ids.length}개'), findsOneWidget);
      expect(t.takeException(), isNull);

      /* 화면(Scaffold + AppBar, 16px 여백 → 카드 안 294px)으로도 — 세그먼트 · 힌트 ·
         장소 카드 · 타일의 글이 잘리지 않아야 합니다. 요약은 두 줄까지 허용. */
      await t.pumpWidget(host(app, const GymSettingsScreen()));
      await t.pump();
      expect(find.byType(GymSettingsCard), findsOneWidget);
      expect(find.byType(InputChip), findsNothing, reason: '플랜 탭에서 연 화면도 접힌 채');
      await expandFamiliar(t);
      for (final s in ['무제한', '2', '초보 기본으로', '머신은 이만큼만, 나머지는 프리웨이트·맨몸',
          '머신·프리웨이트', '맨몸·소도구', ...kEquipLabel.values, ...kGroupLabel.values]) {
        fits(t, s);
      }
      final summary = t.renderObject<RenderParagraph>(find.byKey(const Key('gym-summary')));
      expect(summary.didExceedMaxLines, isFalse, reason: '요약이 잘렸습니다');
      expect(t.takeException(), isNull);
    });
  });

  /* --- 익숙한 종목 — 접어 두기(피드백 39) ------------------------------------
   * "설정에서 익숙한 종목은 펼치기 버튼 만들어서 펼쳐야 보이게" — 칩이 17개를 넘으면
   * 설정이 끝없이 길어졌습니다. 머리글 한 줄(「익숙한 종목 n개 ⌄」 + 「추가」)이 전부. */
  group('설정 — 익숙한 종목은 접힌 채(피드백 39)', () {
    /// 부위마다 이름이 가장 긴 종목 셋씩 + 사전에 없는 번호 하나 — 긴 목록.
    List<String> longList() {
      final ids = <String>[];
      for (final g in kGroupLabel.keys) {
        final xs = exercisesFor(g).toList()..sort((a, b) => b.name.length.compareTo(a.name.length));
        ids.addAll(xs.take(3).map((e) => e.id));
      }
      return ids..add('unknown-exercise-id');
    }

    testWidgets('처음은 접힘 — 칩 없이 개수만, 머리글 어디를 눌러도 펼치고 다시 누르면 접는다', (t) async {
      final app = await open(t, height: 2400);
      const ids = ['plank', 'leg-press', 'chest-press-machine'];
      updateGymPrefs(app, (p) => p.copyWith(familiar: ids));
      await t.pump();
      expect(famToggle, findsOneWidget);
      expect(famCount(t), '3개');
      expect(find.byType(InputChip), findsNothing);
      for (final id in ids) {
        expect(find.byKey(Key('gym-fam-$id')), findsNothing, reason: id);
      }
      expect(find.text('가슴'), findsNothing, reason: '부위 머리글도 같이 접힙니다');
      expect(famCollapse, findsNothing);
      expect(famAdd, findsOneWidget, reason: '「추가」 는 접힌 채로도 보입니다');

      /* 글자(왼쪽 끝)를 눌러도 펼칩니다. */
      await t.tap(find.text('익숙한 종목'));
      await t.pumpAndSettle();
      for (final id in ids) {
        expect(find.byKey(Key('gym-fam-$id')), findsOneWidget, reason: id);
      }
      expect(find.text('가슴'), findsOneWidget);
      expect(famCollapse, findsOneWidget, reason: '목록 끝의 「접기」');

      /* 「추가」 바로 왼쪽 빈자리(⌄ 에서 먼 곳)를 눌러도 접힙니다 — 머리글 줄 전체가 단추. */
      final r = t.getRect(famToggle);
      expect(t.getRect(famAdd).left, greaterThanOrEqualTo(r.right - 0.01), reason: '「추가」 는 따로');
      await t.tapAt(Offset(r.right - 4, r.center.dy));
      await t.pumpAndSettle();
      expect(find.byType(InputChip), findsNothing);
      expect(famCollapse, findsNothing);
      expect(saved(app)['familiar'], ids, reason: '펼치고 접는 것은 저장된 값을 건드리지 않습니다');
      expect(t.takeException(), isNull);
    });

    testWidgets('목록 끝의 「접기」 — 접히고, 화면 위로 나간 머리글이 다시 보인다', (t) async {
      /* 설정처럼 카드 밑에 다른 것이 길게 이어지는 700px 화면. */
      const height = 700.0;
      final app = await open(t, height: height, below: const [SizedBox(height: 1600)]);
      final ids = longList();
      updateGymPrefs(app, (p) => p.copyWith(familiar: ids));
      await t.pump();
      await expandFamiliar(t);
      await t.scrollUntilVisible(famCollapse, 200);
      await t.pumpAndSettle();
      expect(t.getRect(famToggle).bottom, lessThan(0), reason: '긴 목록 끝에서는 머리글이 화면 밖입니다');

      await t.tap(famCollapse);
      await t.pumpAndSettle();
      expect(find.byType(InputChip), findsNothing);
      expect(famCollapse, findsNothing);
      final r = t.getRect(famToggle);
      expect(r.top, greaterThanOrEqualTo(0), reason: '접은 뒤 머리글이 보여야 무엇을 접었는지 압니다');
      expect(r.bottom, lessThanOrEqualTo(height));
      expect(famCount(t), '${ids.length}개');
      expect(t.takeException(), isNull);
    });

    testWidgets('「추가」 는 접힌 채로 된다 — 칩은 안 펼쳐지고 개수만 는다', (t) async {
      final app = await open(t, height: 2400);
      updateGymPrefs(app, (p) => p.copyWith(familiar: ['plank']));
      await t.pump();
      expect(famCount(t), '1개');
      await t.tap(famAdd);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('pick-group-chest')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('pick-chest-press-machine')));
      await t.pump();
      await t.tap(find.byKey(const ValueKey('pick-done')));
      await t.pumpAndSettle();
      expect(saved(app)['familiar'], unorderedEquals(['plank', 'chest-press-machine']));
      expect(famCount(t), '2개');
      expect(find.textContaining('익숙한 종목 2개'), findsOneWidget, reason: '맨 위 요약도');
      expect(find.byType(InputChip), findsNothing, reason: '접힌 채 그대로');
      expect(t.takeException(), isNull);
    });

    testWidgets('비어 있으면 「없음」 뿐 — ⌄ 도 개수도 없다. 마지막 칩을 빼면 「없음」 으로', (t) async {
      final app = await open(t, height: 2400);
      expect(find.text('없음'), findsOneWidget);
      expect(famToggle, findsNothing);
      expect(find.byKey(const Key('gym-fam-count')), findsNothing);
      expect(find.text('익숙한 종목'), findsOneWidget, reason: '머리글 글자는 남습니다');
      expect(famAdd, findsOneWidget);

      updateGymPrefs(app, (p) => p.copyWith(familiar: ['plank']));
      await t.pump();
      expect(find.text('없음'), findsNothing);
      await expandFamiliar(t);
      await t.tap(find.descendant(of: find.byKey(const Key('gym-fam-plank')), matching: find.byType(Icon)));
      await t.pumpAndSettle();
      expect(saved(app)['familiar'], isEmpty);
      expect(find.text('없음'), findsOneWidget);
      expect(famToggle, findsNothing);
      expect(famCollapse, findsNothing);

      /* 다시 채우면 처음처럼 접힌 채 — 빈 목록에는 펼침이라는 상태가 없습니다. */
      updateGymPrefs(app, (p) => p.copyWith(familiar: ['leg-press']));
      await t.pumpAndSettle();
      expect(famToggle, findsOneWidget);
      expect(find.byType(InputChip), findsNothing);
      expect(t.takeException(), isNull);
    });

    for (final (name, theme) in [('밝게', mbLight), ('어둡게', mbDark)]) {
      testWidgets('360px · 글자 1.3배 · $name — 머리글 · 칩 · 「접기」 가 넘치거나 잘리지 않는다', (t) async {
        t.platformDispatcher.textScaleFactorTestValue = 1.3;
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        final app = await seeded();
        t.view.physicalSize = const Size(360, 3200);
        t.view.devicePixelRatio = 1.0;
        addTearDown(t.view.reset);
        final ids = longList();
        updateGymPrefs(app, (p) => p.copyWith(equipment: {...kGymEquipment, 'band', 'kettlebell'}, familiar: ids));
        /* 설정 화면과 같은 폭 — Scaffold + AppBar, 16px 여백 → 카드 안 294px. */
        await t.pumpWidget(host(app, const GymSettingsScreen(), theme: theme()));
        await t.pump();
        expect(t.takeException(), isNull);
        for (final s in ['익숙한 종목', '${ids.length}개', '추가']) {
          fits(t, s);
        }
        /* 머리글 줄은 「추가」 와 같은 높이 한 줄 — 1.3배에도 두 줄로 접히지 않습니다. */
        expect(t.getRect(famToggle).height, lessThanOrEqualTo(t.getRect(famAdd).height + 0.01));

        await expandFamiliar(t);
        expect(t.takeException(), isNull);
        for (final s in ['접기', ...kGroupLabel.values]) {
          fits(t, s);
        }
        expect(find.byType(InputChip), findsNWidgets(ids.length));
        await t.tap(famCollapse);
        await t.pumpAndSettle();
        expect(find.byType(InputChip), findsNothing);
        expect(t.takeException(), isNull);
      });
    }
  });
}
