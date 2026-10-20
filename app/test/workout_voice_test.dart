/* =============================================================================
 * workout_voice_test.dart — 누르고 말하기 · 세트별 무게 · 횟수 · 지난 기록 화면
 *
 * 받아쓰기 플러그인은 시험에 없습니다. 두 길로 봅니다:
 *   · 글로 넣기(짧게 누름) — 받아쓴 글이 들어오는 자리와 같은 함수(_onSpokenText)로 갑니다.
 *   · 가짜 인식기(VoiceSetButton.speechFactory) — 꾹 누르고 떼면 정해 둔 글을 내놓습니다.
 * 그 뒤는 같습니다: 확인 시트 → 「기록」 → 줄에 세트 칩 → 종료 · 저장 → 기록의 setLog.
 * ========================================================================== */
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:mybody/src/api.dart';
import 'package:mybody/src/app_state.dart';
import 'package:mybody/src/scope.dart';
import 'package:mybody/src/screens/workout_history.dart';
import 'package:mybody/src/screens/workout_session.dart';
import 'package:mybody/src/screens/workout_tutorial.dart';
import 'package:mybody/src/screens/workout_voice.dart';
import 'package:mybody/src/theme.dart';
import 'package:mybody/src/workout/exercises.dart';
import 'package:mybody/src/workout/sets.dart';
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

final _today = DateTime(2026, 9, 27, 18, 0);
const _todayKey = '2026-09-27';

/// 가짜 인식기 — 떼면 [text] 를 최종 결과로.
class FakeSpeech implements SpeechInput {
  FakeSpeech(this.text, {this.available = true});
  final String text;
  final bool available;
  void Function(String, bool)? _cb;
  bool _on = false;
  @override
  Future<bool> init() async => available;
  @override
  Future<void> start(void Function(String text, bool isFinal) onResult, {void Function(String? error)? onEnd}) async {
    _on = true;
    _cb = onResult;
    onResult(text.split(' ').first, false);
  }
  @override
  Future<void> stop() async {
    _on = false;
    _cb?.call(text, true);
  }
  @override
  Future<void> cancel() async => _on = false;
  @override
  bool get listening => _on;
}

/// init 이 늦게 끝나는(권한 창) 인식기 — 시험이 [ready] 를 완료시킵니다. 듣기는 결과를 안 내고,
/// [end] 로 "기기가 먼저 끝냈다" 를 흉내 냅니다.
class _SlowSpeech implements SpeechInput {
  final ready = Completer<bool>();
  int started = 0;
  void Function(String? error)? end;
  bool _on = false;
  @override
  Future<bool> init() => ready.isCompleted ? Future.value(true) : ready.future;
  @override
  Future<void> start(void Function(String text, bool isFinal) onResult, {void Function(String? error)? onEnd}) async {
    started++;
    _on = true;
    end = onEnd;
  }
  @override
  Future<void> stop() async => _on = false;
  @override
  Future<void> cancel() async => _on = false;
  @override
  bool get listening => _on;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  DateTime now = _today;
  setUp(() {
    now = _today;
    WorkoutSessionScreen.clock = () => now;
    VoiceSetButton.speechFactory = null;
  });
  tearDown(() {
    WorkoutSessionScreen.clock = DateTime.now;
    VoiceSetButton.speechFactory = null;
  });

  Future<AppState> seeded() async {
    SharedPreferences.setMockInitialValues({});
    final app = await AppState.boot();
    app.store.now = () => now;
    app.store.set({
      'profile': _profile,
      'onboarded': true,
      'settings': {kGymTutorialSeenKey: true, kGymSwipeHintSeenKey: true},
    });
    app.store.addScan({..._scan});
    return app;
  }

  Api api() {
    final a = Api(baseUrl: '', client: MockClient((_) async => http.Response('{"ok":false}', 404)));
    a.setToken('tok');
    return a;
  }

  Widget host(AppState app, Widget child) => Scope(
        state: app,
        api: api(),
        onServerChange: (_) async {},
        child: MaterialApp(theme: mbLight(), home: child),
      );

  Future<void> open(WidgetTester t, AppState app, Widget screen, {Size size = const Size(1000, 4000)}) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(host(app, _Launch(child: screen)));
    await t.tap(find.text('열기'));
    await t.pumpAndSettle();
    expect(find.byType(ErrorWidget), findsNothing);
    expect(t.takeException(), isNull);
  }

  Map<String, Object?> gymLog(AppState app, String dateKey) {
    final day = app.store.scheduleDay(dateKey);
    final log = (day['log'] as Map?)?['gym'];
    expect(log, isA<Map>(), reason: '$dateKey 의 헬스 기록이 없습니다: $day');
    return (log as Map).cast<String, Object?>();
  }

  /// 글로 넣기 → 확인 시트까지.
  Future<void> typeSpoken(WidgetTester t, String text) async {
    await t.tap(find.byKey(const ValueKey('voice-set')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('voice-typed')), findsOneWidget, reason: '짧게 누르면 글로 넣는 칸');
    await t.enterText(find.byKey(const ValueKey('voice-typed')), text);
    await t.tap(find.byKey(const ValueKey('voice-typed-ok')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('voice-transcript')), findsOneWidget, reason: '확인 시트가 떠야 합니다');
  }

  /// 종료 → 분 넣기 → 저장 → 축하 닫기.
  Future<void> finish(WidgetTester t, {String minutes = '40'}) async {
    await t.tap(find.text('종료'));
    await t.pumpAndSettle();
    final field = find.widgetWithText(TextField, '운동 시간');
    if (field.evaluate().isNotEmpty) {
      await t.enterText(field, minutes);
      await t.pumpAndSettle();
    }
    await t.tap(find.text('저장'));
    await t.pumpAndSettle();
    for (var i = 0; i < 40 && find.text('열기').evaluate().isEmpty; i++) {
      await t.pump(const Duration(milliseconds: 250));
    }
    await t.pumpAndSettle();
  }

  group('누르고 말하기', () {
    testWidgets('글로 「벤치 80키로 4개」 → 확인 시트 → 기록 → 줄에 세트 칩 → 저장하면 setLog 가 남는다', (t) async {
      final app = await seeded();
      await open(t, app, const WorkoutSessionScreen(dateKey: _todayKey, type: 'gym'));
      expect(find.byKey(const ValueKey('voice-set')), findsOneWidget);
      expect(find.text('꾹 누르고 말하기'), findsOneWidget);

      await typeSpoken(t, '벤치 80키로 4개');
      expect(find.text('"벤치 80키로 4개"'), findsOneWidget);
      expect(find.byKey(const ValueKey('spoken-kg-0')), findsOneWidget);
      expect(find.text('80kg'), findsWidgets);
      expect(find.text('4회'), findsWidgets);
      final ok = t.widget<FilledButton>(find.byKey(const ValueKey('spoken-ok')));
      expect(ok.onPressed, isNotNull, reason: '종목 · 숫자가 다 있으면 바로 기록할 수 있어야 합니다');
      expect(find.text('1세트 기록'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('spoken-ok')));
      await t.pumpAndSettle();

      /* 벤치프레스 줄이 (없었으면 더해져) 있고, 세트 칩 「1 80×4」 에 마이크가 붙습니다. */
      final chip = find.byKey(ValueKey('setchip-${slugOf('바벨 벤치프레스')}-0'));
      expect(chip, findsOneWidget, reason: '말로 넣은 세트가 칩으로 보여야 합니다');
      expect(find.descendant(of: chip, matching: find.text('80×4')), findsOneWidget);
      expect(find.descendant(of: chip, matching: find.byIcon(LucideIcons.mic)), findsOneWidget);
      expect(find.textContaining('1세트 기록했습니다'), findsOneWidget);

      await finish(t);
      final log = gymLog(app, _todayKey);
      final xs = (log['exercises'] as List).cast<Map>();
      final bench = xs.firstWhere((x) => x['name'] == '바벨 벤치프레스');
      expect(bench['sets'], 1);
      expect(bench['kg'], 80);
      final setLog = (bench['setLog'] as List).cast<Map>();
      expect(setLog, hasLength(1));
      expect(setLog.first['kg'], 80);
      expect(setLog.first['reps'], 4);
      expect(setLog.first['src'], 'voice');
      /* 기록 화면이 그대로 읽습니다. */
      expect(setLogSummary(setLogOf(bench)), '80×4');
    });

    testWidgets('「스쿼트 100키로 5개씩 3세트」 → 칩 셋 · 머리글 세트 수', (t) async {
      final app = await seeded();
      await open(t, app, const WorkoutSessionScreen(dateKey: _todayKey, type: 'gym'));
      await typeSpoken(t, '스쿼트 100키로 5개씩 3세트');
      expect(find.text('3세트 기록'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('spoken-ok')));
      await t.pumpAndSettle();
      final slug = slugOf('바벨 스쿼트');
      for (var i = 0; i < 3; i++) {
        expect(find.byKey(ValueKey('setchip-$slug-$i')), findsOneWidget, reason: '${i + 1}번째 칩');
      }
      expect(find.text('100×5'), findsNWidgets(3));
    });

    testWidgets('여러 세트 한 마디 — 「벤치 80키로 5개 85키로 3개」 → 세트마다 다른 무게', (t) async {
      final app = await seeded();
      await open(t, app, const WorkoutSessionScreen(dateKey: _todayKey, type: 'gym'));
      await typeSpoken(t, '벤치 80키로 5개 85키로 3개');
      expect(find.byKey(const ValueKey('spoken-1')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('spoken-ok')));
      await t.pumpAndSettle();
      expect(find.text('80×5'), findsOneWidget);
      expect(find.text('85×3'), findsOneWidget);
      await finish(t);
      final xs = (gymLog(app, _todayKey)['exercises'] as List).cast<Map>();
      final bench = xs.firstWhere((x) => x['name'] == '바벨 벤치프레스');
      expect((bench['setLog'] as List).map((m) => (m as Map)['kg']), [80, 85]);
      expect(bench['kg'], 85, reason: '마지막에 쓴 무게가 줄의 무게 — 다음에 열면 lastLoadsFrom 이 이걸 읽습니다');
    });

    testWidgets('종목을 못 찾으면 「기록」 이 꺼지고, 고르면 켜진다 · 취소하면 아무것도 안 남는다', (t) async {
      final app = await seeded();
      await open(t, app, const WorkoutSessionScreen(dateKey: _todayKey, type: 'gym'));
      await typeSpoken(t, '뿡뿡이 80키로 4개');
      expect(t.widget<FilledButton>(find.byKey(const ValueKey('spoken-ok'))).onPressed, isNull);
      expect(find.text('종목을 골라 주세요'), findsOneWidget);
      expect(find.textContaining('"뿡뿡이"'), findsWidgets);
      await t.tap(find.byKey(const ValueKey('spoken-cancel')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('voice-transcript')), findsNothing);
      expect(find.textContaining('기록했습니다'), findsNothing);
    });

    testWidgets('잘 못 알아들으면 그렇게 말하고, 숫자를 고쳐 넣을 수 있다', (t) async {
      final app = await seeded();
      await open(t, app, const WorkoutSessionScreen(dateKey: _todayKey, type: 'gym'));
      await typeSpoken(t, '음 그러니까');
      expect(find.text('잘 못 알아들었어요'), findsOneWidget);
      expect(t.widget<FilledButton>(find.byKey(const ValueKey('spoken-ok'))).onPressed, isNull);
    });

    testWidgets('꾹 누르고 떼면(가짜 인식기) 받아쓴 글로 확인 시트가 뜬다', (t) async {
      VoiceSetButton.speechFactory = () => FakeSpeech('벤치 80키로 4개');
      final app = await seeded();
      await open(t, app, const WorkoutSessionScreen(dateKey: _todayKey, type: 'gym'));
      await t.longPress(find.byKey(const ValueKey('voice-set')));
      await t.pumpAndSettle();
      expect(find.text('"벤치 80키로 4개"'), findsOneWidget);
      expect(find.text('1세트 기록'), findsOneWidget);
    });

    testWidgets('이 기기에서 음성 인식이 안 되면 글로 넣는 칸으로 간다', (t) async {
      VoiceSetButton.speechFactory = () => FakeSpeech('', available: false);
      final app = await seeded();
      await open(t, app, const WorkoutSessionScreen(dateKey: _todayKey, type: 'gym'));
      await t.longPress(find.byKey(const ValueKey('voice-set')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('voice-typed')), findsOneWidget);
      expect(find.textContaining('음성 인식을 쓸 수 없어요'), findsOneWidget);
    });

    testWidgets('앞날에는 말하기 단추가 없다', (t) async {
      final app = await seeded();
      await open(t, app, const WorkoutSessionScreen(dateKey: '2026-09-28', type: 'gym'));
      expect(find.byKey(const ValueKey('voice-set')), findsNothing);
    });

    for (final scale in [1.3, 2.0]) {
      testWidgets('360px · 글자 $scale배에서 말하기 줄이 넘치지 않고, 스크롤 없이 늘 보인다', (t) async {
        final app = await seeded();
        t.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        await open(t, app, const WorkoutSessionScreen(dateKey: _todayKey, type: 'gym'), size: const Size(360, 780));
        expect(t.takeException(), isNull, reason: '글자 $scale배');
        /* 목록 끝이 아니라 화면 아래 — 종목이 다섯이어도 스크롤 없이 보입니다. */
        final r = t.getRect(find.byKey(const ValueKey('voice-set')));
        expect(r.bottom, lessThanOrEqualTo(780), reason: '글자 $scale배 — 화면 안에 있어야 합니다');
        expect(r.top, greaterThan(400), reason: '아래쪽에 있어야 합니다');
      });
    }

    testWidgets('권한 창이 뜨는 사이 손을 떼면 듣기를 시작하지 않는다 · 기기가 먼저 끝내면 갇히지 않는다', (t) async {
      final slow = _SlowSpeech();
      VoiceSetButton.speechFactory = () => slow;
      final app = await seeded();
      await open(t, app, const WorkoutSessionScreen(dateKey: _todayKey, type: 'gym'));
      /* 꾹 눌렀다 뗐는데 init(권한 창)이 그 뒤에 끝나는 경우. */
      final g = await t.startGesture(t.getCenter(find.byKey(const ValueKey('voice-set'))));
      await t.pump(const Duration(milliseconds: 600));   // 긴 누름 인식 → _begin → init 대기
      await g.up();
      await t.pump();
      slow.ready.complete(true);
      await t.pumpAndSettle();
      expect(slow.started, 0, reason: '손을 뗀 뒤에는 듣기를 시작하면 안 됩니다');
      expect(find.text('꾹 누르고 말하기'), findsOneWidget);

      /* 이번엔 누른 채로 — 듣기 시작 → 기기가 먼저 끝냄(소리 없음) → 단추가 돌아오고 안내. */
      final g2 = await t.startGesture(t.getCenter(find.byKey(const ValueKey('voice-set'))));
      await t.pump(const Duration(milliseconds: 600));
      await t.pumpAndSettle();
      expect(slow.started, 1);
      expect(find.text('듣는 중…'), findsOneWidget);
      slow.end?.call('error_no_match');
      await t.pumpAndSettle();
      expect(find.text('꾹 누르고 말하기'), findsOneWidget, reason: '「듣는 중」 에 갇히면 안 됩니다');
      expect(find.textContaining('말소리를 못 찾았어요'), findsOneWidget);
      await g2.up();
      await t.pumpAndSettle();
      expect(slow.started, 1, reason: '떼도 다시 시작하지 않습니다');
    });
  });

  group('말하기 막대 · 추천 종목 비우기', () {
    testWidgets('말하기 단추는 화면 아래 폭 가득한 큰 막대 — 들을 때 위로 커진다', (t) async {
      final slow = _SlowSpeech()..ready.complete(true);
      VoiceSetButton.speechFactory = () => slow;
      final app = await seeded();
      await open(t, app, const WorkoutSessionScreen(dateKey: _todayKey, type: 'gym'), size: const Size(390, 844));
      final idle = t.getRect(find.byKey(const ValueKey('voice-set')));
      expect(idle.width, greaterThan(390 - 40), reason: '폭 가득');
      expect(idle.height, greaterThanOrEqualTo(88), reason: '땀 난 엄지로도 대충 닿게');
      expect(idle.bottom, greaterThan(844 - 40), reason: '엄지 닿는 아래');
      final g = await t.startGesture(t.getCenter(find.byKey(const ValueKey('voice-set'))));
      await t.pump(const Duration(milliseconds: 400));
      await t.pumpAndSettle();
      expect(slow.started, 1);
      expect(find.text('듣는 중…'), findsOneWidget);
      final on = t.getRect(find.byKey(const ValueKey('voice-set')));
      expect(on.height, greaterThan(idle.height + 30), reason: '듣는 중엔 위로 커집니다');
      expect(on.bottom, closeTo(idle.bottom, 1));
      await g.up();
      await t.pumpAndSettle();
    });

    testWidgets('추천 종목 비우기 — 한 세트 한 줄은 남고, 되돌리기로 원래 자리에', (t) async {
      final app = await seeded();
      await open(t, app, const WorkoutSessionScreen(dateKey: _todayKey, type: 'gym'));
      final plan = [for (final m in gymExercisesFor(app.state, _todayKey)) '${m['name']}'];
      expect(plan.length, greaterThan(2));
      final kept = slugOf(plan[1]);
      await t.tap(find.byKey(ValueKey('set-$kept')));
      await t.pumpAndSettle();
      expect(find.text('추천 종목 비우기 (${plan.length - 1})'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('clear-suggested')));
      await t.pumpAndSettle();
      expect(find.byKey(ValueKey('ex-$kept')), findsOneWidget, reason: '이미 한 세트는 지우지 않습니다');
      for (final n in [plan[0], ...plan.skip(2)]) {
        expect(find.byKey(ValueKey('ex-${slugOf(n)}')), findsNothing, reason: n);
      }
      expect(find.byKey(const ValueKey('clear-suggested')), findsNothing, reason: '더 뺄 것이 없으면 칩도 없습니다');
      expect(find.text('추천 종목 ${plan.length - 1}개를 뺐습니다'), findsOneWidget);
      await t.tap(find.text('되돌리기'));
      await t.pumpAndSettle();
      final ys = [for (final n in plan) t.getTopLeft(find.byKey(ValueKey('ex-${slugOf(n)}'))).dy];
      expect(ys, orderedEquals([...ys]..sort()), reason: '원래 순서 그대로');
    });

    testWidgets('말로 새로 넣은 종목은 비우기에서 남는다', (t) async {
      final app = await seeded();
      await open(t, app, const WorkoutSessionScreen(dateKey: _todayKey, type: 'gym'));
      final plan = {for (final m in gymExercisesFor(app.state, _todayKey)) '${m['name']}'};
      final (said, extra) = [('벤치', '바벨 벤치프레스'), ('스쿼트', '바벨 스쿼트')].firstWhere((p) => !plan.contains(p.$2));
      await typeSpoken(t, '$said 60키로 5개');
      await t.tap(find.byKey(const ValueKey('spoken-ok')));
      await t.pumpAndSettle();
      expect(find.byKey(ValueKey('ex-${slugOf(extra)}')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('clear-suggested')));
      await t.pumpAndSettle();
      expect(find.byKey(ValueKey('ex-${slugOf(extra)}')), findsOneWidget);
      for (final n in plan) {
        expect(find.byKey(ValueKey('ex-${slugOf(n)}')), findsNothing, reason: n);
      }
    });
  });

  group('세트별 무게 · 횟수', () {
    testWidgets('「세트」 길게 → 무게 · 횟수 넣고 완료 → 칩 · 다음 세트는 그 무게로', (t) async {
      final app = await seeded();
      await open(t, app, const WorkoutSessionScreen(dateKey: _todayKey, type: 'gym'));
      /* 무게 있는 첫 줄. */
      final list = gymExercisesFor(app.state, _todayKey);
      final weighted = list.firstWhere((m) => exerciseByName('${m['name']}')?.equip != 'bodyweight');
      final name = '${weighted['name']}';
      final slug = slugOf(name);
      await t.longPress(find.byKey(ValueKey('set-$slug')));
      await t.pumpAndSettle();
      expect(find.text('$name · 새 세트'), findsOneWidget);
      expect(find.byKey(const ValueKey('set-kg-value')), findsOneWidget);
      /* 횟수 — 빠른 칩 중 하나. */
      final quick = find.byWidgetPredicate((w) => w is ChoiceChip && (w.key as ValueKey?)?.value.toString().startsWith('set-reps-') == true);
      expect(quick, findsWidgets);
      await t.tap(quick.first);
      await t.pump();
      await t.tap(find.byKey(const ValueKey('set-kg-plus')));
      await t.pump();
      final kgText = (t.widget<Text>(find.byKey(const ValueKey('set-kg-value'))).data ?? '').replaceAll(' kg', '');
      final repsText = (t.widget<Text>(find.byKey(const ValueKey('set-reps-value'))).data ?? '').replaceAll('회', '');
      await t.tap(find.byKey(const ValueKey('set-ok')));
      await t.pumpAndSettle();
      final chip0 = find.byKey(ValueKey('setchip-$slug-0'));
      expect(chip0, findsOneWidget);
      expect(find.descendant(of: chip0, matching: find.text('$kgText×$repsText')), findsOneWidget);
      /* 짧게 누르면 같은 무게로 한 세트 더 — 횟수는 안 적습니다(「${kg}kg」). */
      await t.tap(find.byKey(ValueKey('set-$slug')));
      await t.pumpAndSettle();
      final chip1 = find.byKey(ValueKey('setchip-$slug-1'));
      expect(chip1, findsOneWidget);
      expect(find.descendant(of: chip1, matching: find.text('${kgText}kg')), findsOneWidget);
    });

    testWidgets('칩을 누르면 그 세트를 고치고, 지울 수 있다', (t) async {
      final app = await seeded();
      await open(t, app, const WorkoutSessionScreen(dateKey: _todayKey, type: 'gym'));
      final list = gymExercisesFor(app.state, _todayKey);
      final name = '${list.first['name']}';
      final slug = slugOf(name);
      await t.tap(find.byKey(ValueKey('set-$slug')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(ValueKey('set-$slug')));
      await t.pumpAndSettle();
      expect(find.byKey(ValueKey('setchip-$slug-1')), findsOneWidget);
      await t.tap(find.byKey(ValueKey('setchip-$slug-0')));
      await t.pumpAndSettle();
      expect(find.text('$name · 1세트'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('set-reps-plus')));
      await t.tap(find.byKey(const ValueKey('set-reps-plus')));
      await t.pump();
      expect(find.text('2회'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('set-ok')));
      await t.pumpAndSettle();
      expect(find.descendant(of: find.byKey(ValueKey('setchip-$slug-0')), matching: find.textContaining('×2')), findsOneWidget);
      /* 지우기 — 둘째가 첫째로 당겨집니다. */
      await t.tap(find.byKey(ValueKey('setchip-$slug-0')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('set-delete')));
      await t.pumpAndSettle();
      expect(find.byKey(ValueKey('setchip-$slug-1')), findsNothing);
      expect(find.byKey(ValueKey('setchip-$slug-0')), findsOneWidget);
      expect(find.text('1/${list.fold<int>(0, (a, m) => a + core.jsToNumber(m['sets']).round())} 세트'), findsOneWidget);
    });

    test('setLogSummary · 옛 기록(setLog 없음)', () {
      expect(setLogSummary([SetEntry(kg: 80, reps: 5), SetEntry(kg: 80, reps: 5), SetEntry(kg: 85, reps: 3)]),
          '80×5 ×2 · 85×3');
      expect(setLogSummary(setLogOf({'sets': 3, 'kg': 60})), '60kg ×3세트');
      expect(setLogSummary(setLogOf({'sets': 2, 'kg': null})), '맨몸 ×2세트');
      expect(setLogVolume([SetEntry(kg: 80, reps: 5), SetEntry(kg: 80)]), 400);
      expect(setLogMaxKg([SetEntry(kg: 80), SetEntry(kg: 82.5)]), 82.5);
      expect(SetEntry(kg: 82.5, reps: 3).label, '82.5×3');
    });
  });

  group('지난 운동 기록', () {
    Future<AppState> withLogs() async {
      final app = await seeded();
      app.store.setScheduleLog('2026-09-25', 'gym', {
        'kind': 'gym', 'minutes': 50, 'seconds': 3000, 'kcal': 260, 'sets': 5,
        'exercises': [
          {
            'name': '바벨 벤치프레스', 'sets': 3, 'of': 3, 'reps': '5-8', 'restSec': 150, 'kg': 85,
            'setLog': [
              {'kg': 80, 'reps': 5, 'src': 'voice'}, {'kg': 80, 'reps': 5}, {'kg': 85, 'reps': 3, 'src': 'edit'},
            ],
          },
          {'name': '레그프레스', 'sets': 2, 'of': 3, 'reps': '8-12', 'restSec': 90, 'kg': 120},
        ],
      });
      app.store.setScheduleLog('2026-09-23', 'gym', {
        'kind': 'gym', 'minutes': 40, 'seconds': 2400, 'kcal': 200, 'sets': 3,
        'exercises': [
          {'name': '바벨 벤치프레스', 'sets': 3, 'of': 3, 'reps': '5-8', 'restSec': 150, 'kg': 75},
        ],
      });
      app.store.setScheduleLog('2026-09-24', 'cardio', {'kind': 'run', 'minutes': 30, 'km': 5.0, 'kcal': 320});
      app.store.setScheduleLog('2026-09-22', 'gym', {
        'kind': 'bodyweight', 'minutes': 15, 'seconds': 900, 'kcal': 90, 'sets': 6,
        'exercises': ['맨몸 스쿼트', '푸시업'],
      });
      return app;
    }

    test('historyDays · exerciseHistories', () async {
      final app = await withLogs();
      final days = historyDays(app.state);
      expect(days.map((d) => d.key), ['2026-09-25', '2026-09-24', '2026-09-23', '2026-09-22']);
      expect(days[1].cardio?['kind'], 'run');
      final ex = exerciseHistories(app.state);
      expect(ex.first.name, '바벨 벤치프레스');
      expect(ex.first.times, 2);
      expect(ex.first.bestKg, 85);
      expect(ex.first.days.first.volume, 80 * 5 + 80 * 5 + 85 * 3);
      expect(ex[1].name, '레그프레스');
      expect(historyDate('2026-09-27'), '9/27 (일)');
    });

    testWidgets('날짜별 — 날마다 헬스 · 유산소 · 맨몸이 보이고 세트별 무게 × 횟수가 읽힌다', (t) async {
      final app = await withLogs();
      await open(t, app, const WorkoutHistoryScreen());
      expect(find.text('지난 운동 기록'), findsOneWidget);
      expect(find.text('9/25 (금)'), findsOneWidget);
      expect(find.text('80×5 ×2 · 85×3'), findsOneWidget);
      expect(find.text('120kg ×2세트'), findsOneWidget, reason: '옛 기록은 세트 수와 무게만');
      expect(find.text('달리기'), findsOneWidget);
      expect(find.textContaining('5.0 km'), findsOneWidget);
      expect(find.text('집에서 맨몸'), findsOneWidget);
      expect(find.text('푸시업'), findsOneWidget);
    });

    testWidgets('종목별 — 몇 번 · 최고 무게 → 누르면 날짜별 세트와 볼륨', (t) async {
      final app = await withLogs();
      await open(t, app, const WorkoutHistoryScreen());
      await t.tap(find.text('종목별'));
      await t.pumpAndSettle();
      expect(find.textContaining('2번 · 마지막 9/25 (금) · 최고 85kg'), findsOneWidget);
      await t.tap(find.text('바벨 벤치프레스'));
      await t.pumpAndSettle();
      expect(find.text('볼륨 1055kg'), findsOneWidget);
      expect(find.text('1  80×5'), findsOneWidget);
      expect(find.text('3  85×3'), findsOneWidget);
      expect(find.text('9/23 (수)'), findsOneWidget);
    });

    testWidgets('기록이 없으면 빈 안내', (t) async {
      final app = await seeded();
      await open(t, app, const WorkoutHistoryScreen());
      expect(find.text('아직 운동 기록이 없습니다'), findsOneWidget);
    });

    testWidgets('헬스 화면 상단의 시계 아이콘이 기록 화면을 연다', (t) async {
      final app = await withLogs();
      await open(t, app, const WorkoutSessionScreen(dateKey: _todayKey, type: 'gym'));
      await t.tap(find.byKey(const ValueKey('workout-history')));
      await t.pumpAndSettle();
      expect(find.text('지난 운동 기록'), findsOneWidget);
      expect(find.text('9/25 (금)'), findsOneWidget);
    });
  });
}

class _Launch extends StatelessWidget {
  const _Launch({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: FilledButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => child)),
            child: const Text('열기'),
          ),
        ),
      );
}
