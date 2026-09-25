/* =============================================================================
 * workout_session.dart — 헬스장에서 쓰는 운동 화면 (헬스 · 유산소 · 집에서 맨몸)
 *
 * 홈의 「헬스 했어요」 는 체크 하나였습니다. 체크는 남는데 **얼마나** 했는지는
 * 안 남았습니다 — 40분을 했는지, 세트를 몇 개 했는지, 그래서 몇 kcal 을
 * 썼는지. 이 화면은 그걸 남깁니다. 다만 헬스장에서 쓰는 화면이라 규칙이
 * 있습니다:
 *
 *   · 종목 목록이 주인공입니다. 줄 어디를 눌러도 한 세트가 올라가므로 표적은
 *     여전히 크고(땀 난 손, 한 손), 시계와 시작 · 종료는 위에 한 줄로 작게 둡니다.
 *     0.2.9 는 64px 시계 밑에 큰 버튼 둘, 줄마다 폭 가득한 보라색 「세트 완료」
 *     버튼이었고 주인이 실기기에서 "UI 너무 못생겼어" 라고 했습니다 — 헬스장에서
 *     보는 건 종목 이름이지 버튼이 아닙니다.
 *   · 시간은 시계가 잽니다. 화면이 다시 그려지든 말든 `_startedAt` 과 쌓인
 *     시간으로 계산하고, 주기 타이머는 숫자를 다시 그리는 용도뿐입니다.
 *     시계는 [WorkoutSessionScreen.clock] 으로 뚫어 두어 시험이 세울 수 있습니다.
 *   · 시작을 잊는 사람이 많습니다. 세트를 누르면 시간이 알아서 갑니다.
 *     시계를 켰으면 잰 시간(초)이 기록이고 종료 시트는 다시 묻지 않습니다 —
 *     분 칸은 시계를 안 켠 사람(이미 하고 온 사람)에게만 보입니다.
 *   · 아직 오지 않은 날은 저장을 막습니다(코어도 거부합니다) — 내일 할 운동을
 *     오늘 적는 건 기록이 아니라 소원입니다.
 *   · 이 화면에서 바로 고칩니다(2차 피드백 18~21). 종목 줄의 무게 칩은 체성분으로
 *     어림한 시작 무게(workout/loads.dart)이고 지난 30일 기록이 있으면 그 무게 —
 *     누르면 스테퍼로 오늘 쓸 무게를 정합니다. 세트를 다 채운 뒤에도 「+」 로
 *     더 할 수 있고(4/3), 목록 끝의 「종목 추가」 는 두 번 터치(부위 → 종목)로
 *     끝나며, 줄을 왼쪽으로 밀면 빠집니다(5초 안에 되돌리기). 오늘 바꾼 구성은
 *     그 날 기록에 그대로 남고, 종료 시트에서 「내 루틴으로 저장」 을 켜면
 *     workout/routines.dart 에 남아 같은 라벨의 날에 자동으로 다시 씁니다.
 *   · 줄을 꾹 누르면 끌어서 순서를 바꿉니다(3차 피드백 33) — 목록이
 *     ReorderableListView 이고 줄마다 Dismissible 안에 드래그 손잡이(줄 전체)가
 *     있습니다. 바뀐 순서가 곧 기록과 루틴의 순서입니다.
 *   · 처음 온 사람에게는 「따라 해 보기」(workout_tutorial.dart) 를 한 번 띄우고,
 *     그걸 건너뛴 사람에게는 첫 줄이 살짝 밀렸다 돌아오는 힌트를 한 번 보여 줍니다 —
 *     밀어서 빼는 길은 눈에 안 보여서 주인이 실기기에서 못 찾았습니다(3차 29).
 *     둘 다 settings 에 본 것으로 적어 다시 안 뜹니다.
 *
 * 기록은 코어의 setScheduleLog 로 갑니다 — 그 날의 체크(done)까지 같이 남습니다.
 *   헬스   log['gym']    = {kind:'gym', startedAt, minutes, kcal, sets,
 *                           exercises:[{name, sets(한 것), of(계획), reps, restSec, kg(맨몸 null)}]}
 *   맨몸   log['gym']    = {kind:'bodyweight', minutes, kcal, exercises:[이름…]}
 *   유산소 log['cardio'] = {kind:'walk'|'run'|'bike'|'cardio', startedAt, minutes, km, kcal}
 * ========================================================================== */
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:mybody_core/mybody_core.dart' as core;

import '../app_state.dart';
import '../scope.dart';
import '../ui/confetti.dart';
import '../ui/fmt.dart';
import '../ui/widgets.dart';
import '../workout/bodyweight.dart';
import '../workout/exercises.dart';
import '../workout/kcal.dart';
import '../workout/loads.dart';
import '../workout/planner.dart';
import '../workout/prefs.dart';
import '../workout/routines.dart';
import '../workout/scheme.dart';
import 'exercise_picker.dart';
import 'workout_tutorial.dart';

/// 화면 종류. 셸이 `go('workout', (dateKey: …, type: …))` 로 넘깁니다.
const kWorkoutTypes = ['gym', 'cardio', 'bodyweight'];

/// 체중을 모를 때(측정이 없을 때) 쓰는 값. 화면이 그 사실을 같이 말합니다.
const kFallbackWeightKg = 70.0;

/// 이만큼 했으면 나머지는 다음에 — 확인만 받고 기록합니다.
const kBodyweightEnoughRatio = 0.6;

/* 휴식 표기(restText)는 ui/fmt.dart 에 — 플랜 탭의 restLabel 과 같은 함수여야 합니다.
   스와이프 힌트 표(kGymSwipeHintSeenKey)는 workout_tutorial.dart 에 — 튜토리얼 완주가 적습니다. */

/// 'YYYY-MM-DD' → 플랜 세션 칸(월=0). 못 읽으면 null.
int? weekdayIndexOf(String dateKey) {
  final d = DateTime.tryParse('${dateKey}T00:00:00');
  return d == null ? null : d.weekday - 1;
}

/// 플랜에서 그 날짜 요일의 세션. 플랜이 없거나 쉬는 날이면 null.
Map<String, Object?>? planSessionFor(Map<String, Object?> state, String dateKey) {
  final plan = state['plan'];
  final w = plan is Map ? plan['workout'] : null;
  final sessions = w is Map ? w['sessions'] : null;
  final i = weekdayIndexOf(dateKey);
  if (sessions is! List || i == null || i < 0 || i >= sessions.length) return null;
  final s = sessions[i];
  if (s is! Map || s['rest'] == true) return null;
  return s.cast<String, Object?>();
}

/// 오늘 할 헬스 종목. 플랜 세션을 헬스장 기구에 맞춘 것이고, 플랜이 없거나
/// 쉬는 날이면 부위별 기본 종목 하나씩(같은 모양)입니다 — 헬스장에 왔는데
/// 빈 화면이면 안 됩니다. 세트 · 횟수 · 휴식은 어느 길이든 scheme.dart 가 매깁니다 —
/// 프로필의 경력과 플랜의 국면을 planner 가 읽어 넘기므로 플랜 탭과 같은 숫자입니다.
List<Map<String, Object?>> gymExercisesFor(Map<String, Object?> state, String dateKey) {
  final settings = (state['settings'] as Map?)?.cast<String, Object?>();
  final prefs = GymPrefs.fromSettings(settings);
  final session = planSessionFor(state, dateKey);
  if (session != null) {
    final out = tailorSessionFor(state, session, prefs, dateKey: dateKey);
    if (out.isNotEmpty) return out;
  }
  /* 부위마다 하나 — 전신. 기구 제한은 그대로 지킵니다. 숫자는 「종목 추가」 와 같은 길 —
     예전엔 3 × 10-15 · 75초 고정이라 집 프리셋의 플랭크가 「10-15회」 였습니다(3차 31 재발). */
  const groups = ['chest', 'back', 'quads', 'shoulder', 'core'];
  final trainingAge = trainingAgeOf(state), goalKind = goalKindOf(state, dateKey);
  final out = <Map<String, Object?>>[];
  for (final g in groups) {
    /* 집이면 철봉 · 평행봉이 필요한 종목은 뺍니다 — tailorSession 과 같은 규칙. */
    final pool = exercisesFor(g, equip: prefs.equipment.isEmpty ? null : prefs.equipment)
        .where((e) => !(e.needsBar && prefs.isHome))
        .toList();
    if (pool.isEmpty) continue;
    out.add(schemeRowFor(pool.first, trainingAge: trainingAge, goalKind: goalKind));
  }
  return withIds(out);
}

/// 마지막 인바디의 체중. 측정이 없으면 null — 화면이 [kFallbackWeightKg] 로
/// 대신하고 그렇게 했다고 말합니다.
double? latestWeightKg(AppState app) {
  final scans = app.store.sortedScans();
  if (scans.isEmpty) return null;
  try {
    final d = core.derive(scans.last, app.profile ?? core.kSeedProfile);
    final w = core.jsToNumber(d['weightKg']);
    return w.isNaN || w <= 0 ? null : w;
  } catch (_) {
    return null;
  }
}

/// 마지막 인바디의 골격근량. 없으면 null — 무게 추천이 체중만으로 계산합니다.
double? latestSmmKg(AppState app) {
  final scans = app.store.sortedScans();
  if (scans.isEmpty) return null;
  try {
    final d = core.derive(scans.last, app.profile ?? core.kSeedProfile);
    final s = core.jsToNumber(d['smmKg']);
    return s.isNaN || s <= 0 ? null : s;
  } catch (_) {
    return null;
  }
}

/// 마지막 인바디의 체지방률. 없으면 null.
double? latestPbfPct(AppState app) {
  final scans = app.store.sortedScans();
  if (scans.isEmpty) return null;
  try {
    final d = core.derive(scans.last, app.profile ?? core.kSeedProfile);
    final p = core.jsToNumber(d['pbfPct']);
    return p.isNaN || p <= 0 ? null : p;
  } catch (_) {
    return null;
  }
}

/// 'mm:ss'. 한 시간을 넘으면 분이 세 자리가 됩니다 — 헬스장에서 시(時)는 안 씁니다.
String clockText(Duration d) {
  final s = d.isNegative ? 0 : d.inSeconds;
  return '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
}

/// 헬스 · 유산소 · 맨몸 운동 한 번. [type] 은 'gym' | 'cardio' | 'bodyweight'.
class WorkoutSessionScreen extends StatefulWidget {
  const WorkoutSessionScreen({super.key, required this.dateKey, required this.type});

  /// 'YYYY-MM-DD'. 지난 날도 됩니다(갔는데 적는 걸 잊은 쪽이 흔합니다). 앞날은 안 됩니다.
  final String dateKey;
  final String type;

  /// 시계. 시험에서 세워 두려고 뚫어 놓은 구멍입니다 — 경과 시간과 휴식은 전부
  /// 이 시계로 잽니다.
  static DateTime Function() clock = DateTime.now;

  @override
  State<WorkoutSessionScreen> createState() => _WorkoutSessionScreenState();
}

/// 무게 추천의 재료 — 한 번 열 때 한 번만 모읍니다(프로필 · 마지막 인바디 ·
/// 최근 30일의 종목별 마지막 기록).
class _LoadCtx {
  _LoadCtx(AppState app, String dateKey)
      : profile = app.profile ?? core.kSeedProfile,
        /* 측정이 없으면 체중 70kg 기준 — 칩이 아예 없는 것보다 "안 되면 줄여 보세요"
           가 붙은 어림값이 낫습니다. */
        weightKg = latestWeightKg(app) ?? kFallbackWeightKg,
        smmKg = latestSmmKg(app),
        last = lastLoadsFrom(
            ((app.state['schedule'] as Map?) ?? const {}).cast<String, Object?>(), dateKey);

  final Map<String, Object?> profile;
  final double weightKg;
  final double? smmKg;
  final Map<String, Map<String, Object?>> last;

  Load of(String name, Exercise? e, String reps) => recommendLoad(
      name: name, exercise: e, reps: reps, profile: profile,
      weightKg: weightKg, smmKg: smmKg, last: last[name]);

  /// 최근에 한 종목의 고유번호(최근 것부터) — 종목 고르기의 「최근」 줄.
  List<String> get recentIds {
    final out = <String>[];
    for (final name in last.keys) {
      final e = exerciseByName(name);
      if (e != null && !out.contains(e.id)) out.add(e.id);
      if (out.length >= 8) break;
    }
    return out;
  }
}

/// 종목 한 줄의 진행 상태. 화면(ExerciseRow)과 튜토리얼의 연습 줄이 같이 씁니다 —
/// 공개인 이유는 그것뿐이고, 만드는 곳은 이 파일과 workout_tutorial.dart 입니다.
class GymExercise {
  GymExercise({
    required this.id,
    required this.name,
    required this.sets,
    required this.reps,
    required this.restSec,
    this.note,
    this.equip = 'bodyweight',
    this.load = Load.none,
    this.perSide = false,
    this.seconds,
    double? kg,
    this.kgSet = false,
  }) : kg = kg ?? load.kg;

  final String id;
  final String name;
  /// 계획한 세트. done 이 이보다 커질 수 있습니다(4/3) — 기록엔 sets: done, of: sets.
  final int sets;
  /// '5-8' · '10-15' 같은 반복 구간, 시간으로 하는 종목(플랭크)이면 '30초'.
  final String reps;
  final int restSec;
  final String? note;
  final String equip;
  /// 한쪽씩 하는 종목(런지 · 원암 로우) — 줄에 '10-12 한쪽씩' 으로 씁니다.
  final bool perSide;
  /// 시간으로 하는 종목의 초(플랭크 30). 반복 종목이면 null. reps 에 '30초' 로도 있지만
  /// 루틴 · 기록에는 숫자로도 남겨야 다음에 읽는 쪽이 문자열을 풀지 않습니다.
  final int? seconds;
  /// 추천(또는 지난 기록) — 칩의 글자와 힌트, 스테퍼의 단위.
  final Load load;
  /// 오늘 쓰는 무게. null 은 맨몸.
  double? kg;
  /// 사용자가 스테퍼로 정했는가 — 정했으면 '추천' 을 떼고 숫자만 보여 줍니다.
  bool kgSet;
  int done = 0;

  bool get complete => done >= sets;

  /// 무게가 있는 기구인가 — 맨몸 · 밴드 줄에는 칩이 없습니다.
  bool get weighted => load.source != 'none';

  String get kgLabel {
    final k = kg;
    if (k == null) return '맨몸';
    return !kgSet && load.source == 'body' ? '추천 ${kgText(k)}kg' : '${kgText(k)}kg';
  }

  /// 줄에 쓰는 '몇 번' — '5-8' · '30초' · '10-12 한쪽씩'.
  String get amount => perSide ? '$reps 한쪽씩' : reps;

  /// 줄의 첫 줄 — '3세트 × 5-8 · 휴식 2분 30초'. 요령은 그 밑 줄(note)에 따로 —
  /// 한 줄에 이어 붙였더니 세트 수와 요령이 섞여 읽기 어려웠습니다(3차 피드백 30).
  String get planLine => '$sets세트 × $amount${restSec > 0 ? ' · 휴식 ${restText(restSec)}' : ''}';

  /// 계획의 '몇 번'. 초 단위 종목(seconds > 0)이면 '30초' — reps 가 같이 있어도
  /// 시간이 답입니다(플랭크에 '10-15' 가 붙어 있던 것이 3차 피드백 31). 없으면 reps,
  /// 그것도 없으면 엔진 기본 10-15.
  static String repsOf(Map<String, Object?> m) {
    final sec = core.jsToNumber(m['seconds']);
    if (!sec.isNaN && sec > 0) return '${n0(sec)}초';
    final r = '${m['reps'] ?? ''}';
    return r.isEmpty ? '10-15' : r;
  }

  /// planner · exercisesFor · 루틴이 주는 모양에서. 빈 값은 엔진의 기본(3세트 ·
  /// 10-15 · 75초)으로. [load] 는 추천 무게(화면이 _LoadCtx 로 구합니다) — 루틴에
  /// 저장된 kg 은 지난 기록이 없을 때만 씁니다. 몸이 더 최근에 답한 값이 우선입니다.
  /// 편측은 줄의 perSide 가 없어도 사전(kPerSideIds)이 답입니다 — 0.2.12 에 저장한
  /// 루틴에는 그 칸이 없어서 런지가 양쪽 합산 횟수처럼 보였습니다.
  factory GymExercise.fromMap(Map<String, Object?> m, {Load load = Load.none}) {
    final name = '${m['name'] ?? ''}';
    final rawId = m['id'];
    final lib = (rawId is String && rawId.isNotEmpty ? exerciseById(rawId) : null) ?? exerciseByName(name);
    final sets = core.jsToNumber(m['sets']);
    final rest = core.jsToNumber(m['restSec']);
    /* 엔진 내부 접두어(「대체: 원래 바벨 벤치프레스 · 요령」)는 여기서 걷어냅니다 —
       헬스장에서 보는 건 요령이지 플랜의 사정이 아닙니다. 플랜 탭이 「대체」 표를 답니다. */
    final note = tailorNote(m, original: false) ?? '';
    final saved = m['kg'];
    final useSaved = saved is num && saved > 0 && load.source == 'body';
    final sec = core.jsToNumber(m['seconds']);
    return GymExercise(
      id: rawId is String && rawId.isNotEmpty ? rawId : (lib?.id ?? slugOf(name)),
      name: name,
      sets: sets.isNaN || sets < 1 ? 3 : sets.round(),
      reps: repsOf(m),
      restSec: rest.isNaN || rest < 0 ? 75 : rest.round(),
      note: note.isEmpty ? null : note,
      equip: lib?.equip ?? '${m['equip'] ?? 'bodyweight'}',
      perSide: core.jsTruthy(m['perSide']) || isPerSide(exercise: lib, name: name),
      seconds: sec.isNaN || sec <= 0 ? null : sec.round(),
      load: load,
      kg: useSaved ? saved.toDouble() : load.kg,
      kgSet: useSaved,
    );
  }

  /// 루틴 · 기록에 남기는 모양. 세트는 계획보다 더 했으면 한 만큼.
  Map<String, Object?> toRoutineRow() => {
        'name': name,
        'sets': done > sets ? done : sets,
        'reps': reps,
        'restSec': restSec,
        'kg': kg,
        if (seconds != null) 'seconds': seconds,
        if (perSide) 'perSide': true,
      };
}

/// 화면이 목록을 만들 때 — 추천 무게까지 붙여서.
GymExercise _exOf(Map<String, Object?> m, _LoadCtx ctx) {
  final name = '${m['name'] ?? ''}';
  final rawId = m['id'];
  final lib = (rawId is String && rawId.isNotEmpty ? exerciseById(rawId) : null) ?? exerciseByName(name);
  return GymExercise.fromMap(m, load: ctx.of(name, lib, GymExercise.repsOf(m)));
}

/// 스테퍼 시트의 답. null 을 "취소" 와 구분하려고 상자에 담습니다.
class KgPick {
  const KgPick(this.kg);
  final double? kg;
}

/// 무게 칩 → 스테퍼. − · 숫자 · +, 「맨몸」 과 「추천」 한 번에. 답은 [KgPick] —
/// null 은 "닫았다". 헬스 화면과 튜토리얼의 연습 줄이 같은 시트를 씁니다.
Future<KgPick?> showKgStepper(BuildContext context, GymExercise e) async {
  final step = e.load.step > 0 ? e.load.step : 2.5;
  var kg = e.kg;
  return showModalBottomSheet<KgPick>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
      final t = Theme.of(ctx);
      final stepNow = kg == null ? step : (stepFor(e.equip, kg!) > 0 ? stepFor(e.equip, kg!) : step);
      return _Sheet(children: [
        Text(e.name, style: t.textTheme.titleMedium),
        if (e.load.hint.isNotEmpty)
          Text(e.load.hint, style: t.textTheme.labelSmall?.copyWith(color: t.hintColor)),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          IconButton.filledTonal(
            key: const ValueKey('kg-minus'),
            tooltip: '${kgText(stepNow)}kg 내리기',
            onPressed: kg == null
                ? null
                : () => setSheet(() {
                      /* 내려서 0 이 되면 맨몸. 단위보다 작은 값(1.25kg)은 헬스장에 없습니다. */
                      final s = stepFor(e.equip, kg! - 0.001) > 0 ? stepFor(e.equip, kg! - 0.001) : step;
                      final next = kg! - s;
                      kg = next <= 0 ? null : next;
                    }),
            icon: const Icon(LucideIcons.minus),
          ),
          /* 글자 1.3배에서 '117.5 kg' 이 150px 을 넘어 두 줄로 접혔습니다 — 줄여서 한 줄에. */
          SizedBox(
            width: 150,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                kg == null ? '맨몸' : '${kgText(kg!)} kg',
                key: const ValueKey('kg-value'),
                maxLines: 1,
                textAlign: TextAlign.center,
                style: t.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800, fontFeatures: const [FontFeature.tabularFigures()]),
              ),
            ),
          ),
          IconButton.filledTonal(
            key: const ValueKey('kg-plus'),
            tooltip: '${kgText(stepNow)}kg 올리기',
            onPressed: () => setSheet(() => kg = (kg ?? 0) + stepNow),
            icon: const Icon(LucideIcons.plus),
          ),
        ]),
        const SizedBox(height: 12),
        Wrap(spacing: 8, alignment: WrapAlignment.center, children: [
          ChoiceChip(
            key: const ValueKey('kg-none'),
            label: const Text('맨몸'),
            selected: kg == null,
            onSelected: (_) => setSheet(() => kg = null),
          ),
          /* 지난 기록 그대로면 「지난번 55kg」, 다 채워서 올린 값이면 「추천 60kg」 — 60 은 지난번이 아닙니다. */
          if (e.load.kg != null)
            ChoiceChip(
              key: const ValueKey('kg-reco'),
              label: Text('${e.load.source == 'last' && e.load.kg == e.load.prevKg ? '지난번' : '추천'} ${kgText(e.load.kg!)}kg'),
              selected: kg == e.load.kg,
              onSelected: (_) => setSheet(() => kg = e.load.kg),
            ),
        ]),
        const SizedBox(height: 14),
        SizedBox(
          height: 52,
          child: FilledButton(
            key: const ValueKey('kg-ok'),
            onPressed: () => Navigator.pop(ctx, KgPick(kg)),
            child: const Text('확인'),
          ),
        ),
      ]);
    }),
  );
}

class _WorkoutSessionScreenState extends State<WorkoutSessionScreen> {
  /* --- 시계 -------------------------------------------------------------- */
  DateTime? _startedAt;                    // 지금 도는 구간의 시작. null 이면 멈춤
  Duration _accumulated = Duration.zero;   // 멈추기 전까지 쌓인 시간
  DateTime? _firstStartedAt;               // 기록에 남기는 시작 시각
  Timer? _tick;                            // 숫자를 다시 그리는 용도뿐

  /* --- 헬스 -------------------------------------------------------------- */
  List<GymExercise>? _gym;
  DateTime? _restEndsAt;
  int _restTotalSec = 0;
  _LoadCtx? _loads;
  /// 지금 목록이 어느 내 루틴에서 왔는가. null 이면 플랜(또는 기본) 종목.
  String? _routineName;
  String? _routineId;

  /* --- 집에서 맨몸 ---------------------------------------------------------- */
  Map<String, Object?>? _routine;
  List<bool> _checked = const [];

  /* --- 종료 시트의 입력칸 ------------------------------------------------------
     시트를 열 때마다 새로 만들면 닫힌 뒤 dispose 할 자리가 없습니다 — 시트가 사라지는
     애니메이션 동안 칸이 아직 컨트롤러를 붙들고 있어서, await 직후에 지우면 터집니다.
     화면과 같이 살고 같이 죽습니다. 열 때 비웁니다. */
  final _minutesCtl = TextEditingController();
  final _kmCtl = TextEditingController();
  final _nameCtl = TextEditingController();

  static DateTime _now() => WorkoutSessionScreen.clock();

  bool get _running => _startedAt != null;
  Duration get _elapsed =>
      _accumulated + (_startedAt == null ? Duration.zero : _now().difference(_startedAt!));
  int get _elapsedSeconds => _elapsed.inSeconds;
  /// 시계를 한 번이라도 켰는가. 켰으면 잰 시간이 답이고, 종료 시트는 다시 묻지 않습니다.
  bool get _timed => _firstStartedAt != null;
  bool get _resting => _restEndsAt != null && _restEndsAt!.isAfter(_now());
  Duration get _restLeft => _resting ? _restEndsAt!.difference(_now()) : Duration.zero;

  /// 뭔가 했는가 — 뒤로 가기 전에 물어볼 만한 상태.
  bool get _dirty =>
      _firstStartedAt != null ||
      (_gym?.any((e) => e.done > 0) ?? false) ||
      _checked.any((c) => c);

  @override
  void dispose() {
    _tick?.cancel();
    _minutesCtl.dispose();
    _kmCtl.dispose();
    _nameCtl.dispose();
    super.dispose();
  }

  /* --- 처음 온 사람 ----------------------------------------------------------
     initState 에서는 Scope 를 못 읽습니다(InheritedWidget 은 그 뒤에 닿습니다).
     한 번만 보고, 첫 프레임이 그려진 뒤 튜토리얼을 올립니다 — 화면이 서기도 전에
     길을 올리면 돌아올 자리가 없습니다. */
  bool _tutorialChecked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_tutorialChecked) return;
    _tutorialChecked = true;
    final app = Scope.of(context);
    if (widget.type != 'gym' || WorkoutTutorial.seen(app.state)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _showTutorial(app);
    });
  }

  /// 본 것 · 완주(→ 힌트도 본 것)를 적는 일은 WorkoutTutorial.show 가 합니다 — 설정에서
  /// 열어 완주한 사람에게 첫 헬스 진입 때 힌트가 또 뜨지 않게, 여는 곳이 어디든 같습니다.
  Future<void> _showTutorial(AppState app) => WorkoutTutorial.show(context);

  bool _swipeHintDue(AppState app) => WorkoutTutorial.seen(app.state) && !WorkoutTutorial.swipeHintSeen(app.state);

  void _markSwipeHintSeen(AppState app) => WorkoutTutorial.markSwipeHintSeen(app);

  void _start() {
    if (_running) return;
    setState(() {
      _startedAt = _now();
      _firstStartedAt ??= _startedAt;
    });
    _syncTick();
  }

  void _pause() {
    if (!_running) return;
    setState(() {
      _accumulated += _now().difference(_startedAt!);
      _startedAt = null;
    });
    _syncTick();
  }

  /// 돌고 있거나 쉬는 중일 때만 초마다 다시 그립니다. 시간은 시계가 잽니다.
  void _syncTick() {
    final need = _running || _resting;
    if (need && _tick == null) {
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        if (_restEndsAt != null && !_resting) _restEndsAt = null;   // 휴식 끝
        setState(() {});
        if (!_running && !_resting) _syncTick();
      });
    } else if (!need && _tick != null) {
      _tick!.cancel();
      _tick = null;
    }
  }

  /// 한 세트. 계획을 다 채운 뒤에도 됩니다(4/3) — 더 한 것도 기록입니다.
  void _completeSet(GymExercise e) {
    _start();   // 시작을 잊었어도 세트를 누르면 시간이 갑니다
    setState(() {
      e.done++;
      final allDone = _gym!.every((x) => x.complete);
      if (!allDone && e.restSec > 0) {
        _restEndsAt = _now().add(Duration(seconds: e.restSec));
        _restTotalSec = e.restSec;
      } else {
        _restEndsAt = null;
      }
    });
    _syncTick();
  }

  void _undoSet(GymExercise e) {
    if (e.done <= 0) return;
    setState(() => e.done--);
  }

  void _skipRest() {
    setState(() => _restEndsAt = null);
    _syncTick();
  }

  /* --- 헬스 목록 고치기 ---------------------------------------------------- */

  /// 꾹 눌러 끌어다 놓은 뒤 — ReorderableListView 의 newIndex 는 "빼기 전" 자리라
  /// 아래로 옮기면 하나 당깁니다. 목록의 순서가 곧 기록 · 루틴의 순서입니다.
  void _reorder(int oldIndex, int newIndex) {
    final list = _gym;
    if (list == null || oldIndex < 0 || oldIndex >= list.length) return;
    final to = (newIndex > oldIndex ? newIndex - 1 : newIndex).clamp(0, list.length - 1);
    if (to == oldIndex) return;
    setState(() => list.insert(to, list.removeAt(oldIndex)));
  }

  _LoadCtx _loadsOf(AppState app) => _loads ??= _LoadCtx(app, widget.dateKey);

  String _sessionLabel(AppState app) {
    final s = planSessionFor(app.state, widget.dateKey);
    return s == null ? '' : '${s['label'] ?? ''}';
  }

  /// 처음 열 때의 목록. 같은 라벨로 저장한 내 루틴이 있으면 그것 — 저장한 사람은
  /// 다음에 그걸 쓰려고 저장한 것이니 묻지 않습니다(「플랜 종목으로」 가 되돌립니다).
  List<GymExercise> _initialGym(AppState app) {
    final ctx = _loadsOf(app);
    final r = routineForLabel(app, _sessionLabel(app));
    if (r != null) {
      _routineName = '${r['name'] ?? ''}';
      _routineId = '${r['id'] ?? ''}';
      return [for (final m in routineExercises(r)) _exOf(m, ctx)];
    }
    return [for (final m in gymExercisesFor(app.state, widget.dateKey)) _exOf(m, ctx)];
  }

  /// 목록을 바꿉니다 — 같은 종목의 한 세트 수와 정한 무게는 이어받습니다.
  /// 두 세트 하고 루틴을 바꿨다고 그 두 세트가 사라지면 안 됩니다.
  void _swapList(List<GymExercise> next, {String? routineName, String? routineId}) {
    final old = {for (final e in _gym ?? const <GymExercise>[]) e.id: e};
    for (final e in next) {
      final o = old[e.id];
      if (o == null) continue;
      e.done = o.done;
      if (o.kgSet) {
        e.kg = o.kg;
        e.kgSet = true;
      }
    }
    /* 「되돌리기」 스낵바는 옛 목록의 것입니다 — 목록이 바뀌면 되돌릴 자리가 없습니다. */
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    setState(() {
      _gym = next;
      _routineName = routineName;
      _routineId = routineId;
    });
  }

  void _applyRoutine(AppState app, Map<String, Object?> r) {
    final ctx = _loadsOf(app);
    _swapList([for (final m in routineExercises(r)) _exOf(m, ctx)],
        routineName: '${r['name'] ?? ''}', routineId: '${r['id'] ?? ''}');
  }

  void _resetToPlan(AppState app) {
    final ctx = _loadsOf(app);
    _swapList([for (final m in gymExercisesFor(app.state, widget.dateKey)) _exOf(m, ctx)]);
  }

  /// 「루틴 불러오기」 — 고르면 그 구성으로, 길게 누르면 지웁니다.
  Future<void> _pickRoutine(AppState app) async {
    final r = await showModalBottomSheet<Map<String, Object?>>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        final list = routinesOf(app);
        return _Sheet(children: [
          Text('내 루틴', style: Theme.of(ctx).textTheme.titleMedium),
          Text('길게 누르면 지웁니다',
              style: Theme.of(ctx).textTheme.labelSmall?.copyWith(color: Theme.of(ctx).hintColor)),
          const SizedBox(height: 6),
          if (list.isEmpty) const EmptyState(title: '저장한 루틴이 없습니다'),
          for (final r in list)
            ListTile(
              key: ValueKey('routine-${r['id']}'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(LucideIcons.bookmark, size: 20),
              title: Text('${r['name'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                  '${routineExercises(r).length}종목'
                  '${'${r['label'] ?? ''}'.isEmpty ? '' : ' · ${r['label']}'}',
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(color: Theme.of(ctx).hintColor)),
              onTap: () => Navigator.pop(ctx, r),
              onLongPress: () async {
                final yes = await showDialog<bool>(
                  context: ctx,
                  builder: (d) => AlertDialog(
                    title: Text('「${r['name']}」 을 지울까요?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('취소')),
                      FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('지우기')),
                    ],
                  ),
                );
                if (yes == true) {
                  deleteRoutine(app, '${r['id']}');
                  /* 지금 쓰는 루틴을 지웠으면 머리글의 이름도 내립니다 — 종료 시트가
                     그 이름으로 다시 저장해 지운 루틴을 되살리면 안 됩니다. 종목은 그대로. */
                  if (r['id'] == _routineId && mounted) {
                    setState(() {
                      _routineName = null;
                      _routineId = null;
                    });
                  }
                  setSheet(() {});
                }
              },
            ),
        ]);
      }),
    );
    if (r == null || !mounted) return;
    _applyRoutine(app, r);
  }

  /// 「종목 추가」 — 부위 → 종목, 두 번 터치. 세트 · 횟수 · 휴식은 스킴(플랭크는 초 · 런지는
  /// 한쪽씩), 무게는 추천으로 붙습니다 — 3 × 10-15 · 75초 고정이었을 때 플랭크에 「10-15회」
  /// 가 다시 붙었습니다(3차 31).
  Future<void> _addExercise(AppState app) async {
    final prefs = GymPrefs.fromSettings((app.state['settings'] as Map?)?.cast<String, Object?>());
    final ctx = _loadsOf(app);
    final e = await pickExercise(
      context,
      equip: prefs.equipment,
      exclude: {for (final x in _gym ?? const <GymExercise>[]) x.id},
      familiar: prefs.familiar,
      recent: ctx.recentIds,
      title: '종목 추가',
    );
    if (e == null || !mounted) return;
    final row = schemeRowFor(e,
        trainingAge: trainingAgeOf(app.state), goalKind: goalKindOf(app.state, widget.dateKey));
    setState(() => (_gym ??= []).add(_exOf(row, ctx)));
  }

  /// 줄을 밀어서 뺐을 때 — 5초 안에 되돌릴 수 있습니다. 잘못 민 손가락은 흔합니다.
  void _removeExercise(GymExercise e) {
    final list = _gym!;
    final at = list.indexOf(e);
    if (at < 0) return;
    setState(() => list.removeAt(at));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('${e.name} 뺐습니다'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: '되돌리기',
          onPressed: () {
            /* 그 사이 목록이 바뀌었을 수 있습니다 — 지금 목록에 같은 종목이 없을 때만. */
            final cur = _gym;
            if (!mounted || cur == null || cur.any((x) => x.id == e.id)) return;
            setState(() => cur.insert(at > cur.length ? cur.length : at, e));
          },
        ),
      ));
  }

  /// 무게 칩 → 스테퍼(showKgStepper). 정하면 '추천' 이 떨어지고 숫자만 남습니다.
  Future<void> _editKg(GymExercise e) async {
    final r = await showKgStepper(context, e);
    if (r == null || !mounted) return;
    setState(() {
      e.kg = r.kg;
      e.kgSet = true;
    });
  }

  /* --- 저장 -------------------------------------------------------------- */

  /// 코어에 기록하고, **실제로 남았는지** 확인합니다. 저장이 실패했는데
  /// "수고했어요" 라고 하지 않습니다. 앞날이면 코어가 거부합니다.
  bool _saveLog(AppState app, String type, Map<String, Object?> log) {
    final r = app.store.setScheduleLog(widget.dateKey, type, log);
    if (!app.store.saved()) {
      toast(context, '기기에 저장하지 못했습니다 — 설정에서 사진을 지워 보세요');
      return false;
    }
    final done = (r?['done'] as Map?) ?? const {};
    if (!core.jsTruthy(done[type])) {
      toast(context, '아직 오지 않은 날은 기록할 수 없습니다');
      return false;
    }
    return true;
  }

  Future<bool> _confirmLeave() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('기록하지 않고 나갈까요?'),
        content: const Text('잰 시간과 세트가 남지 않습니다 — 저장하려면 「종료」'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('계속하기')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('나가기')),
        ],
      ),
    );
    return yes == true;
  }

  @override
  Widget build(BuildContext context) {
    final app = Scope.of(context);
    final future = widget.dateKey.compareTo(app.store.dayKey()) > 0;
    final title = switch (widget.type) {
      'cardio' => '유산소',
      'bodyweight' => '집에서 맨몸 운동',
      _ => '헬스',
    };
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await _confirmLeave();
        if (leave && mounted) Navigator.of(this.context).pop();
      },
      child: Scaffold(
        /* 날짜는 작은 줄로 — 한 줄에 붙이면 360px 폰에서 날짜가 잘렸습니다. */
        appBar: AppBar(
          title: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title),
            Text(dateK(widget.dateKey),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).hintColor)),
          ]),
        ),
        body: SafeArea(
          child: switch (widget.type) {
            'cardio' => _cardioBody(context, app, future),
            'bodyweight' => _bodyweightBody(context, app, future),
            _ => _gymBody(context, app, future),
          },
        ),
      ),
    );
  }

  Widget _futureNote() => const Note(
        tone: Tone.warn,
        title: '아직 오지 않은 날입니다.',
        text: '그날이 되면 기록할 수 있습니다.',
      );

  /* --- 헬스 -------------------------------------------------------------- */

  Widget _gymBody(BuildContext context, AppState app, bool future) {
    final list = _gym ??= _initialGym(app);
    final t = Theme.of(context);
    final doneSets = list.fold<int>(0, (a, e) => a + e.done);
    final totalSets = list.fold<int>(0, (a, e) => a + e.sets);
    final session = planSessionFor(app.state, widget.dateKey);
    final routines = routinesOf(app);

    return Column(children: [
      _TimerPanel(
        elapsed: _elapsed,
        running: _running,
        started: _firstStartedAt != null,
        onStart: _start,
        onPause: _pause,
        onFinish: () => _finishGym(app, future),
      ),
      if (_resting) _RestBanner(left: _restLeft, totalSec: _restTotalSec, onSkip: _skipRest),
      Expanded(
        /* 목록은 ReorderableListView — 줄을 꾹 누르면 끌어서 순서를 바꿉니다. 기본
           손잡이(buildDefaultDragHandles)는 끄고 줄 전체를 손잡이로 씁니다: 기본값은
           데스크톱에서 ≡ 아이콘을 붙이고 폰에서는 긴 누름인데, 어느 쪽이든 Dismissible
           바깥에 감겨서 밀어 빼기와 겹칩니다. 머리글과 「종목 추가」 는 header · footer. */
        child: ReorderableListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          buildDefaultDragHandles: false,
          onReorder: _reorder,
          proxyDecorator: gymDragProxy,
          itemCount: list.length,
          itemBuilder: (context, i) => _gymRow(app, list[i], i, hint: i == 0 && _swipeHintDue(app)),
          footer: Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: const ValueKey('ex-add'),
              onPressed: () => _addExercise(app),
              icon: const Icon(LucideIcons.plus, size: 18),
              label: const Text('종목 추가'),
            ),
          ),
          header: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (future) _futureNote(),
            /* 머리글 — 세션 이름, 몇 세트 했는지, 그 밑에 얇은 진행 막대. 종목이
               대여섯이면 스크롤하는 동안 전체가 안 보이므로 여기서 한눈에 잡습니다.
               그 밑 줄은 내 루틴 — 지금 목록이 어느 루틴인지, 다른 루틴 불러오기. */
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Text(
                      session == null ? '오늘 플랜에 없는 날 — 전신 기본 종목' : '${session['label']}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Text('$doneSets/$totalSets 세트',
                      style: t.textTheme.labelSmall?.copyWith(color: t.hintColor)),
                ]),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                      value: totalSets == 0 ? 0 : (doneSets / totalSets).clamp(0.0, 1.0), minHeight: 4),
                ),
                if (_routineName != null || routines.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      if (_routineName != null) ...[
                        Pill('내 루틴: $_routineName', key: const ValueKey('routine-current'), tone: Tone.ok),
                        InkWell(
                          key: const ValueKey('routine-reset'),
                          borderRadius: BorderRadius.circular(6),
                          onTap: () => _resetToPlan(app),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                            child: Text('플랜 종목으로',
                                style: t.textTheme.labelSmall?.copyWith(
                                    color: t.colorScheme.primary, decoration: TextDecoration.underline)),
                          ),
                        ),
                      ],
                      if (routines.isNotEmpty)
                        ActionChip(
                          key: const ValueKey('routine-load'),
                          avatar: const Icon(LucideIcons.bookmark, size: 16),
                          label: const Text('루틴 불러오기'),
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _pickRoutine(app),
                        ),
                    ]),
                  ),
              ]),
            ),
            if (list.isEmpty)
              const EmptyState(
                title: '오늘 할 종목이 없습니다',
                detail: '「종목 추가」 로 넣거나 설정에서 기구를 켜 두세요',
              ),
          ]),
        ),
      ),
    ]);
  }

  /// 종목 한 줄 — 왼쪽으로 밀면 빠지고(Dismissible), 꾹 누르면 끕니다(줄 전체가
  /// 손잡이). 키는 종목 id — 되돌리면 같은 줄이 다시 섭니다. [hint] 면 첫 줄이 살짝
  /// 밀렸다 돌아옵니다(한 번) — 그림만 움직이고 실제로 빼지는 않습니다.
  Widget _gymRow(AppState app, GymExercise e, int index, {bool hint = false}) {
    final c = mb(context);
    final row = ExerciseRow(
      ex: e,
      onSet: () => _completeSet(e),
      onUndo: () => _undoSet(e),
      onKg: () => _editKg(e),
    );
    return Dismissible(
      key: ValueKey('dismiss-${e.id}'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => _removeExercise(e),
      background: Container(
        alignment: Alignment.centerRight,
        margin: const EdgeInsets.only(bottom: ExerciseRow.gap),
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(color: c.badBg, borderRadius: BorderRadius.circular(14)),
        child: Icon(LucideIcons.trash2, color: c.bad),
      ),
      child: ReorderableDelayedDragStartListener(
        index: index,
        child: hint
            ? SwipeHint(bottomGap: ExerciseRow.gap, onShown: () => _markSwipeHintSeen(app), child: row)
            : row,
      ),
    );
  }

  Future<void> _finishGym(AppState app, bool future) async {
    final wasRunning = _running;
    _pause();
    final list = _gym ?? const <GymExercise>[];
    final doneSets = list.fold<int>(0, (a, e) => a + e.done);
    final weight = latestWeightKg(app);
    /* 시계를 켰으면 잰 시간이 답입니다 — 초 단위 그대로 쓰고 다시 묻지 않습니다.
       처음엔 잰 분을 입력칸에 미리 넣어 줬는데, 1분 미만이면 칸이 비어서
       "측정했는데 또 넣으라 한다" 가 됐습니다. 칸은 시계를 안 켠 사람(이미
       하고 온 사람)에게만 보입니다. */
    /* 세트를 누르고 같은 초에 「종료」 를 누르면 잰 시간이 0초입니다 — 그대로면 분 칸도
       없이 「저장」 만 꺼진 채 갇힙니다. 0초는 "안 쟀다" 로 보고 분 칸을 냅니다. */
    final timed = _timed && _elapsedSeconds > 0;
    final minutesCtl = _minutesCtl..clear();
    /* 「내 루틴으로 저장」 — 이름은 지금 쓰는 루틴이 있으면 그 이름(같은 이름으로
       저장하면 그 루틴이 고쳐집니다), 없으면 '(세션 라벨) 내 루틴'. */
    final label = _sessionLabel(app);
    var keepRoutine = false;
    final nameCtl = _nameCtl..text = _routineName ?? defaultRoutineName(label);

    final r = await showModalBottomSheet<({int seconds, String? routine})>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        final sec = timed ? _elapsedSeconds : (int.tryParse(minutesCtl.text.trim()) ?? 0) * 60;
        final kcal = sec > 0
            ? workoutKcal(weightKg: weight ?? kFallbackWeightKg, duration: Duration(seconds: sec), kind: 'gym')
            : 0.0;
        return _Sheet(children: [
          Text('오늘 헬스', style: Theme.of(ctx).textTheme.titleMedium),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
                child: Stat(
                    label: '운동 시간',
                    value: timed ? clockText(Duration(seconds: sec)) : '${sec ~/ 60}',
                    unit: timed ? null : '분')),
            Expanded(child: Stat(label: '완료 세트', value: '$doneSets')),
            Expanded(child: Stat(label: '추정', value: n0(kcal), unit: 'kcal')),
          ]),
          if (!timed) ...[
            const SizedBox(height: 14),
            TextField(
              controller: minutesCtl,
              keyboardType: TextInputType.number,
              autofocus: true,
              onChanged: (_) => setSheet(() {}),
              decoration: const InputDecoration(
                  labelText: '운동 시간', suffixText: '분', border: OutlineInputBorder(),
                  helperText: '몇 분 했는지 넣어 주세요'),
            ),
          ],
          if (weight == null) ...[
            const SizedBox(height: 8),
            Text('측정이 없어 체중 ${n0(kFallbackWeightKg)}kg 기준으로 계산했습니다.',
                style: Theme.of(ctx).textTheme.labelSmall?.copyWith(color: Theme.of(ctx).hintColor)),
          ],
          if (list.isNotEmpty) ...[
            const SizedBox(height: 6),
            SwitchListTile(
              key: const ValueKey('routine-save'),
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('내 루틴으로 저장'),
              secondary: const Icon(LucideIcons.bookmark, size: 20),
              value: keepRoutine,
              onChanged: (v) => setSheet(() => keepRoutine = v),
            ),
            if (keepRoutine)
              TextField(
                key: const ValueKey('routine-name'),
                controller: nameCtl,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                    labelText: '루틴 이름', isDense: true, border: OutlineInputBorder()),
              ),
          ],
          const SizedBox(height: 14),
          if (future) _futureNote(),
          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: sec > 0 && !future
                  ? () => Navigator.pop(ctx, (seconds: sec, routine: keepRoutine ? nameCtl.text : null))
                  : null,
              child: const Text('저장'),
            ),
          ),
        ]);
      }),
    );
    if (r == null || !mounted) {
      /* 창을 그냥 닫았으면 시계를 도로 돌립니다 — 실수로 누른 「종료」가 시간을 멈춰 두면 안 됩니다. */
      if (r == null && wasRunning && mounted) _start();
      return;
    }
    final seconds = r.seconds;

    final kcal = workoutKcal(
            weightKg: weight ?? kFallbackWeightKg, duration: Duration(seconds: seconds), kind: 'gym')
        .round();
    final ok = _saveLog(app, 'gym', {
      'kind': 'gym',
      'startedAt': (_firstStartedAt ?? _now()).toUtc().toIso8601String(),
      'minutes': minutesOfSeconds(seconds),
      'seconds': seconds,
      'kcal': kcal,
      'sets': doneSets,
      /* 한 종목만 — 세트(한 것) · of(계획) · 반복 · 쉬는 시간 · 무게 · (시간 종목) 초 · 편측.
         다음에 같은 종목을 열면 lastLoadsFrom 이 이 kg 을 읽습니다. 루틴 줄(toRoutineRow)과
         같은 칸을 남깁니다 — 기록만 초 · 편측을 잃으면 안 됩니다. */
      'exercises': [
        for (final e in list)
          if (e.done > 0)
            {
              'name': e.name, 'sets': e.done, 'of': e.sets, 'reps': e.reps, 'restSec': e.restSec, 'kg': e.kg,
              if (e.seconds != null) 'seconds': e.seconds,
              if (e.perSide) 'perSide': true,
            },
      ],
    });
    if (!ok || !mounted) return;
    var detail = '헬스 ${timeText(seconds, timed: timed)} · 완료 세트 $doneSets';
    if (r.routine != null) {
      /* 루틴은 오늘 목록 전부 — 한 세트도 안 한 종목도 구성의 일부입니다. */
      final saved = saveRoutine(app,
          name: r.routine!, label: label, exercises: [for (final e in list) e.toRoutineRow()]);
      detail = '$detail · 내 루틴 「${saved['name']}」';
    }
    await _celebrate(kcal, detail: detail);
    if (mounted) Navigator.of(context).pop();
  }

  /* --- 유산소 -------------------------------------------------------------- */

  Widget _cardioBody(BuildContext context, AppState app, bool future) {
    final t = Theme.of(context);
    return Column(children: [
      _TimerPanel(
        elapsed: _elapsed,
        running: _running,
        started: _firstStartedAt != null,
        onStart: _start,
        onPause: _pause,
        onFinish: () => _finishCardio(app, future),
      ),
      Expanded(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
          if (future) _futureNote(),
          /* 한 줄로 — 종류(걷기 · 달리기 · 자전거)와 거리는 종료 시트가 물으니 여기서
             미리 설명하지 않습니다. 360px 폰에서 두 줄로 접히던 문장이었습니다. */
          Text('끝나면 「종료」 — 종류와 거리는 그때 적습니다.',
              style: t.textTheme.bodySmall?.copyWith(color: t.hintColor, height: 1.5)),
          const SizedBox(height: 10),
          /* 이미 하고 온 사람 — 시계 없이 분만 넣습니다. 목록 폭을 다 채우는 버튼은
             무거워서(헬스 화면에서 주인이 그렇게 봤습니다) 글 밑에 작게 둡니다.
             시계를 켠 뒤에는 숨깁니다 — 종료 시트가 잰 시간을 쓰고 분 칸이 없으니,
             이 단추는 약속("직접 넣기")을 못 지킵니다. */
          if (!_timed)
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => _finishCardio(app, future),
                icon: const Icon(LucideIcons.timer, size: 18),
                label: const Text('시간을 직접 넣기'),
              ),
            ),
        ]),
      ),
    ]);
  }

  Future<void> _finishCardio(AppState app, bool future) async {
    final wasRunning = _running;
    _pause();
    final weight = latestWeightKg(app);
    /* 헬스와 같은 규칙 — 시계를 켰으면 잰 시간(초)이 답이고, 「시간을 직접 넣기」로 온
       사람에게만 분 칸이 보입니다. 0초는 "안 쟀다" — 헬스와 같은 규칙. */
    final timed = _timed && _elapsedSeconds > 0;
    final minutesCtl = _minutesCtl..clear();
    final kmCtl = _kmCtl..clear();
    var kind = kCardioKinds.first;

    final r = await showModalBottomSheet<({String kind, int seconds, double? km})>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        final sec = timed ? _elapsedSeconds : (int.tryParse(minutesCtl.text.trim()) ?? 0) * 60;
        final km = double.tryParse(kmCtl.text.trim());
        final kcal = sec > 0
            ? workoutKcal(
                weightKg: weight ?? kFallbackWeightKg,
                duration: Duration(seconds: sec),
                kind: kind,
                km: km != null && km > 0 ? km : null)
            : 0.0;
        final kmField = TextField(
          controller: kmCtl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => setSheet(() {}),
          decoration: const InputDecoration(
              labelText: '거리', suffixText: 'km', border: OutlineInputBorder(),
              helperText: '몰라도 됩니다'),
        );
        return _Sheet(children: [
          Text('오늘 유산소', style: Theme.of(ctx).textTheme.titleMedium),
          const SizedBox(height: 12),
          Wrap(spacing: 8, children: [
            for (final k in kCardioKinds)
              ChoiceChip(
                label: Text(cardioKindLabel(k)),
                selected: kind == k,
                onSelected: (_) => setSheet(() => kind = k),
              ),
          ]),
          const SizedBox(height: 14),
          if (timed)
            Row(children: [
              Expanded(child: Stat(label: '시간', value: clockText(Duration(seconds: sec)))),
              Expanded(child: Stat(label: '추정', value: n0(kcal), unit: 'kcal')),
            ])
          else
            Row(children: [
              Expanded(
                child: TextField(
                  controller: minutesCtl,
                  keyboardType: TextInputType.number,
                  autofocus: true,
                  onChanged: (_) => setSheet(() {}),
                  decoration: const InputDecoration(
                      labelText: '시간', suffixText: '분', border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: Stat(label: '추정', value: n0(kcal), unit: 'kcal')),
            ]),
          const SizedBox(height: 12),
          kmField,
          if (weight == null)
            Text('측정이 없어 체중 ${n0(kFallbackWeightKg)}kg 기준으로 계산했습니다.',
                style: Theme.of(ctx).textTheme.labelSmall?.copyWith(color: Theme.of(ctx).hintColor)),
          const SizedBox(height: 14),
          if (future) _futureNote(),
          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: sec > 0 && !future
                  ? () => Navigator.pop(ctx, (kind: kind, seconds: sec, km: km != null && km > 0 ? km : null))
                  : null,
              child: const Text('저장'),
            ),
          ),
        ]);
      }),
    );
    if (r == null || !mounted) {
      if (r == null && wasRunning && mounted) _start();
      return;
    }

    final kcal = workoutKcal(
            weightKg: weight ?? kFallbackWeightKg,
            duration: Duration(seconds: r.seconds),
            kind: r.kind,
            km: r.km)
        .round();
    final ok = _saveLog(app, 'cardio', {
      'kind': r.kind,
      'startedAt': (_firstStartedAt ?? _now()).toUtc().toIso8601String(),
      'minutes': minutesOfSeconds(r.seconds),
      'seconds': r.seconds,
      'km': r.km,
      'kcal': kcal,
    });
    if (!ok || !mounted) return;
    await _celebrate(kcal,
        detail: '${cardioKindLabel(r.kind)} ${timeText(r.seconds, timed: timed)}'
            '${r.km == null ? '' : ' · ${n1(r.km)}km'}');
    if (mounted) Navigator.of(context).pop();
  }

  /* --- 집에서 맨몸 ---------------------------------------------------------- */

  Map<String, Object?> _routineFor(AppState app) {
    return _routine ??= () {
      final session = planSessionFor(app.state, widget.dateKey);
      final r = bodyweightRoutine(
        profile: app.profile ?? core.kSeedProfile,
        weightKg: latestWeightKg(app) ?? kFallbackWeightKg,
        pbfPct: latestPbfPct(app),
        todayLabel: session == null ? '' : '${session['label'] ?? ''}',
      );
      _checked = List<bool>.filled(((r['exercises'] as List?) ?? const []).length, false);
      return r;
    }();
  }

  Widget _bodyweightBody(BuildContext context, AppState app, bool future) {
    final r = _routineFor(app);
    final exercises = ((r['exercises'] as List?) ?? const []).cast<Map>();
    final t = Theme.of(context);
    final c = mb(context);
    final done = _checked.where((x) => x).length;
    final all = exercises.isNotEmpty && done == exercises.length;
    final enough = exercises.isNotEmpty && done / exercises.length >= kBodyweightEnoughRatio;
    final why = '${r['why'] ?? ''}';
    final existing = (app.store.scheduleDay(widget.dateKey)['log'] as Map?)?['gym'];
    final hasGymLog = existing is Map && existing['kind'] == 'gym';

    return Column(children: [
      Expanded(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 12), children: [
          Text('${r['title'] ?? '집에서 맨몸 운동'}',
              style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          if (why.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(why, style: t.textTheme.bodySmall?.copyWith(color: t.hintColor, height: 1.5)),
          ],
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            if ('${r['focusLabel'] ?? ''}'.isNotEmpty) Pill('${r['focusLabel']}'),
            Text('${n0(r['minutes'])}분 · 약 ${n0(r['kcal'])} kcal',
                style: t.textTheme.labelSmall?.copyWith(color: t.hintColor)),
          ]),
          const SizedBox(height: 12),
          if (future) _futureNote(),
          /* 헬스를 이미 기록한 날은 맨몸 운동으로 그 기록을 덮지 않습니다 — 알림을 늦게 누른 경우. */
          if (hasGymLog)
            const Note(
              tone: Tone.warn,
              text: '오늘은 헬스 기록이 있어 맨몸 운동은 따로 기록하지 않습니다',
            ),
          if (exercises.isEmpty)
            const EmptyState(title: '오늘 할 종목이 없습니다', detail: '내 몸 정보를 넣으면 종목을 골라 둡니다.'),
          for (var i = 0; i < exercises.length; i++)
            _BodyweightRow(
              ex: exercises[i].cast<String, Object?>(),
              checked: _checked[i],
              onChanged: (on) => setState(() => _checked[i] = on),
            ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (!all && exercises.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                enough ? '$done/${exercises.length} 했습니다 — 여기까지로 기록할 수 있습니다' : '$done/${exercises.length} 했습니다',
                textAlign: TextAlign.center,
                style: t.textTheme.labelSmall?.copyWith(color: enough ? c.ok : t.hintColor),
              ),
            ),
          SizedBox(
            height: 56,
            child: FilledButton.icon(
              onPressed: (all || enough) && !future && !hasGymLog ? () => _finishBodyweight(app, r) : null,
              icon: const Icon(LucideIcons.check),
              label: const Text('전체 완료', style: TextStyle(fontSize: 17)),
            ),
          ),
        ]),
      ),
    ]);
  }

  Future<void> _finishBodyweight(AppState app, Map<String, Object?> r) async {
    final exercises = ((r['exercises'] as List?) ?? const []).cast<Map>();
    final done = _checked.where((x) => x).length;
    if (done < exercises.length) {
      final yes = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('$done/${exercises.length} 했습니다'),
          content: const Text('남은 종목은 다음에 — 지금까지 한 것으로 오늘을 기록할까요?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('더 하기')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('기록하기')),
          ],
        ),
      );
      if (yes != true || !mounted) return;
    }
    /* 한 만큼만 셉니다 — 60% 했는데 100% 의 kcal 을 적으면 기록이 거짓말을 합니다. */
    final ratio = exercises.isEmpty ? 0.0 : done / exercises.length;
    final minutes = (core.jsToNumber(r['minutes']) * ratio).round();
    final kcal = (core.jsToNumber(r['kcal']) * ratio).round();
    final ok = _saveLog(app, 'gym', {
      'kind': 'bodyweight',
      'minutes': minutes < 1 ? 1 : minutes,
      'kcal': kcal,
      'exercises': [
        for (var i = 0; i < exercises.length; i++)
          if (_checked[i]) '${exercises[i]['name']}',
      ],
    });
    if (!ok || !mounted) return;
    await _celebrate(kcal, detail: '${r['title'] ?? '맨몸 운동'} · $done/${exercises.length} 종목');
    if (mounted) Navigator.of(context).pop();
  }

  /// 화면 가득한 축하 — 폭죽이 쏟아지고 폰이 세 번 울립니다. 운동을 마친 사람에게
  /// 검은 스낵바 한 줄은 모자랍니다(주인이 실기기에서 보고 "못생겼다" 고 했습니다).
  /// 헬스 · 유산소 · 맨몸 모두 여기로 옵니다. [detail] 은 무엇을 얼마나 했는지 한 줄.
  Future<void> _celebrate(int kcal, {String? detail}) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => CelebrationScreen(kcal: kcal, detail: detail),
    );
  }
}

/// 초 → 기록의 분. 1분 미만도 1분 — 기록의 분은 "했다" 의 단위지 정밀도가 아닙니다
/// (정밀한 값은 seconds 에 따로 남습니다).
int minutesOfSeconds(int seconds) {
  final m = (seconds / 60).round();
  return m < 1 ? 1 : m;
}

/// 사람에게 보여 주는 시간. 시계로 쟀으면 'mm:ss', 손으로 넣었으면 'N분'.
String timeText(int seconds, {required bool timed}) =>
    timed ? clockText(Duration(seconds: seconds)) : '${minutesOfSeconds(seconds)}분';

/// 축하 화면. 폭죽은 입력을 막지 않고 「닫기」 위로 떨어집니다.
class CelebrationScreen extends StatefulWidget {
  const CelebrationScreen({super.key, required this.kcal, this.detail});
  final int kcal;
  final String? detail;

  @override
  State<CelebrationScreen> createState() => _CelebrationScreenState();
}

class _CelebrationScreenState extends State<CelebrationScreen> {
  @override
  void initState() {
    super.initState();
    /* 진동 세 번 — 폭죽 터지는 박자. 기기가 못 하면 조용히 넘어갑니다. */
    unawaited(_buzz());
  }

  Future<void> _buzz() async {
    try {
      await HapticFeedback.heavyImpact();
      await Future<void>.delayed(const Duration(milliseconds: 140));
      await HapticFeedback.mediumImpact();
      await Future<void>.delayed(const Duration(milliseconds: 140));
      await HapticFeedback.heavyImpact();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = mb(context);
    return Dialog.fullscreen(
      child: Stack(children: [
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              /* 이모지는 안 씁니다 — 앱에 넣은 글꼴에 없어서 구글에서 받아 오려 합니다(ui/symbols.dart). */
              Icon(LucideIcons.partyPopper, size: 84, color: c.ok),
              const SizedBox(height: 24),
              Text('약 ${widget.kcal} kcal 소모했어요! 축하합니다',
                  textAlign: TextAlign.center,
                  style: t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              Text('오늘 계획을 지켰습니다 — 내일도 만나요',
                  textAlign: TextAlign.center,
                  style: t.textTheme.bodyLarge?.copyWith(color: t.hintColor)),
              if (widget.detail != null) ...[
                const SizedBox(height: 8),
                Text(widget.detail!,
                    textAlign: TextAlign.center,
                    style: t.textTheme.bodyMedium?.copyWith(color: t.hintColor)),
              ],
              const SizedBox(height: 36),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton(
                    onPressed: () => Navigator.pop(context), child: const Text('닫기')),
              ),
            ]),
          ),
        ),
        const Positioned.fill(child: Confetti()),
      ]),
    );
  }
}

/* --- 조각들 ------------------------------------------------------------------ */

/// 시계 카드 한 줄 — 왼쪽에 시간과 짧은 상태, 오른쪽에 시작(일시정지) · 종료.
///
/// 0.2.9 는 64px 시계 밑에 '시작을 누르면 시간이 갑니다' 한 문장, 그 밑에 56px
/// 알약 버튼 둘이 나란히 — 화면 위 3분의 1이 시계였습니다. 시계는 보는 것이지
/// 누르는 것이 아니고, 헬스장에서 실제로 누르는 건 종목 줄이라 그쪽에 자리를
/// 넘깁니다. 버튼의 글자('시작' · '계속' · '종료')는 남깁니다 — 아이콘만 있으면
/// ▶ 가 시작인지 계속인지 다시 물어보게 되고, 시험도 이 글자로 누릅니다. 상태는
/// 두 글자씩('시작 전' · '운동 중' · '일시정지'), 문장은 안 씁니다.
///
/// 일시정지만은 아이콘입니다. 글자 '일시정지' 가 도는 시계 옆에 단추로 붙어 있으니
/// 캡처에서 "시계가 00:02 에 일시정지됐다" 로 읽혔습니다(3차 피드백 33) — 시계는
/// 잘 가고 있었고, 그 글자는 상태가 아니라 단추였습니다. 이제 '일시정지' 는 정말
/// 멈췄을 때만 상태 줄에 뜨고, 도는 동안은 '운동 중' 이 초록으로 보입니다.
class _TimerPanel extends StatelessWidget {
  const _TimerPanel({
    required this.elapsed,
    required this.running,
    required this.started,
    required this.onStart,
    required this.onPause,
    required this.onFinish,
  });

  final Duration elapsed;
  final bool running;
  final bool started;
  final VoidCallback onStart;
  final VoidCallback onPause;
  final VoidCallback onFinish;

  /* 기본 여백(16 · 24)이면 360px 폰에서 '일시정지' 와 '종료' 가 시계를 밀어냅니다. */
  static const _tight = ButtonStyle(
      padding: WidgetStatePropertyAll(EdgeInsets.fromLTRB(14, 0, 16, 0)));

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = mb(context);
    final status = running ? '운동 중' : (started ? '일시정지' : '시작 전');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: MbCard(
        padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
        child: Row(children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                /* 폭이 모자라면(좁은 폰에 큰 글꼴) 시계가 줄어듭니다 — 버튼이 잘리는 것보다 낫습니다. */
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(clockText(elapsed),
                      style: t.textTheme.headlineMedium?.copyWith(
                          fontSize: 34,
                          height: 1.1,
                          fontWeight: FontWeight.w800,
                          fontFeatures: const [FontFeature.tabularFigures()])),
                ),
                Text(status,
                    key: const ValueKey('clock-status'),
                    style: t.textTheme.labelSmall?.copyWith(
                        color: running ? c.ok : (started ? c.warn : t.hintColor),
                        fontWeight: running || started ? FontWeight.w700 : null)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 48,
            child: running
                ? IconButton.filledTonal(
                    tooltip: '일시정지',
                    onPressed: onPause,
                    style: IconButton.styleFrom(fixedSize: const Size(48, 48)),
                    icon: const Icon(LucideIcons.pause, size: 20))
                : FilledButton.icon(
                    onPressed: onStart,
                    style: _tight,
                    icon: const Icon(LucideIcons.play, size: 18),
                    label: Text(started ? '계속' : '시작')),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 48,
            child: OutlinedButton.icon(
              onPressed: onFinish,
              style: _tight,
              icon: const Icon(LucideIcons.square, size: 18),
              label: const Text('종료'),
            ),
          ),
        ]),
      ),
    );
  }
}

/// 세트 사이 휴식. 숫자 하나와 건너뛰기 — 폰을 보는 시간은 이 정도면 됩니다.
/// 시계 카드(모서리 14)와 같은 모양에 강조색 바탕이라 "지금은 쉬는 중" 이 한눈에
/// 구분되고, 숫자는 시계보다 한 단계 작게 — 휴식이 운동 시간보다 크게 보이면 안 됩니다.
class _RestBanner extends StatelessWidget {
  const _RestBanner({required this.left, required this.totalSec, required this.onSkip});
  final Duration left;
  final int totalSec;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = mb(context);
    final progress = totalSec <= 0 ? 0.0 : (1 - left.inSeconds / totalSec).clamp(0.0, 1.0);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
      decoration: BoxDecoration(color: c.accentSub, borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(LucideIcons.timer, size: 16, color: t.hintColor),
          const SizedBox(width: 6),
          Text('휴식', style: t.textTheme.labelSmall?.copyWith(color: t.hintColor)),
          const SizedBox(width: 10),
          Text(clockText(left),
              style: t.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800, fontFeatures: const [FontFeature.tabularFigures()])),
          const Spacer(),
          TextButton(onPressed: onSkip, child: const Text('건너뛰기')),
        ]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(value: progress, minHeight: 4),
        ),
      ]),
    );
  }
}

/// 종목 한 줄 — 왼쪽 동그라미(다 하면 초록 체크), 이름, 그 밑에 '3세트 × 5-8 · 휴식
/// 2분 30초' 한 줄과 요령 한 줄(흐리게), 오른쪽에 세트 점과 작은 「세트」 단추.
/// 세트 수와 요령을 한 줄에 이어 붙였더니("3세트 × 5-8 · 발뒤꿈치 붙이고 천천히")
/// 어디까지가 계획인지 읽기 어려웠습니다(3차 피드백 30) — 줄을 나눕니다.
///
/// 튜토리얼(workout_tutorial.dart)의 연습 줄도 이 위젯입니다 — 배우는 줄과 실제 줄이
/// 같아야 "저 줄이었구나" 가 됩니다. 콜백만 연습용입니다.
///
/// 0.2.9 는 줄마다 두 층짜리 카드에 폭 가득한 보라색 '세트 완료 (0/3)' 버튼이
/// 있어 목록이 버튼 더미로 보였습니다. 헬스장에서 보는 건 종목 이름과 "몇 세트
/// 남았나" 지 버튼이 아닙니다. 그래도 표적은 커야 하므로 줄 어디를 눌러도 한
/// 세트가 올라갑니다 — 단추는 "여기가 눌리는 곳" 이라는 표시에 가깝습니다.
/// 「−」 는 뺄 세트가 있을 때만 나옵니다. 잘못 누른 손가락을 위한 것이지 늘 보일
/// 것은 아닙니다. 다 한 줄은 연한 초록으로 물들고 점 밑에 '완료' 가 붙지만 「+」 는
/// 작게 남습니다 — 계획보다 더 한 세트도 기록입니다(4/3). 줄 자체는 다 한 뒤에는
/// 안 눌립니다. 초과는 일부러 누르는 것이어야지 스치는 손가락이 아닙니다.
///
/// 이름 밑의 무게 칩('추천 40kg' · 지난 기록이면 '40kg' · '맨몸')은 누르면 스테퍼.
/// 힌트('안 되면 2.5~5kg 씩 줄여 보세요')는 스테퍼 시트에만 — 줄마다 붙이면 상체
/// 일곱 줄에 같은 문장 일곱 개입니다. 맨몸 · 밴드 줄에는 칩이 없습니다.
///
/// 키(ex-… · set-… · kg-…)는 종목 이름의 slug — 시험이 줄과 단추를 찾는 손잡이입니다.
/// 같은 종목은 한 세션에 두 번 안 나오므로(planner 규칙 4) 이름이면 충분합니다.
class ExerciseRow extends StatelessWidget {
  const ExerciseRow({super.key, required this.ex, required this.onSet, required this.onUndo, required this.onKg});
  final GymExercise ex;
  final VoidCallback onSet;
  final VoidCallback onUndo;
  final VoidCallback onKg;

  /// 줄 사이 틈(줄 자신의 아래 여백). 밀어 빼는 바탕과 힌트의 빨간 띠가 같은 높이여야 합니다.
  static const double gap = 10;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = mb(context);
    final slug = slugOf(ex.name);
    final done = ex.complete;
    return Padding(
      padding: const EdgeInsets.only(bottom: gap),
      /* MbCard 는 바탕색을 못 바꿉니다 — 다 한 줄을 물들여야 해서 같은 모양(모서리
         14 · 테두리)을 여기서 그립니다. Material 이라야 줄을 누를 때 잉크가 보입니다. */
      child: Material(
        key: ValueKey('ex-$slug'),
        color: done ? c.okBg : t.colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: done ? c.ok.withValues(alpha: 0.25) : t.dividerColor),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: done ? null : onSet,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            child: Row(children: [
              Icon(done ? LucideIcons.checkCircle2 : LucideIcons.circle,
                  size: 22, color: done ? c.ok : t.hintColor),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(ex.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  /* 계획 한 줄 — 좁은 폰에서 넘치면 뒤(휴식)부터 줄임표. 세트 × 횟수가 앞입니다. */
                  Text(ex.planLine,
                      key: ValueKey('plan-$slug'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.textTheme.bodySmall?.copyWith(color: t.hintColor)),
                  if (ex.note != null)
                    Text(ex.note!,
                        key: ValueKey('note-$slug'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: t.textTheme.labelSmall
                            ?.copyWith(color: t.hintColor.withValues(alpha: t.hintColor.a * 0.7))),
                  if (ex.weighted)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Pill(ex.kgLabel, key: ValueKey('kg-$slug'), onTap: onKg,
                            tone: ex.kg == null ? Tone.none : Tone.ok),
                      ),
                    ),
                ]),
              ),
              const SizedBox(width: 8),
              Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
                _SetDots(done: ex.done, total: ex.sets),
                if (done)
                  Text('완료',
                      style: t.textTheme.labelSmall?.copyWith(color: c.ok, fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(width: 6),
              if (ex.done > 0)
                IconButton(
                  tooltip: '한 세트 빼기',
                  onPressed: onUndo,
                  /* 48px 표적 여백을 끄지 않으면 줄에서 48px 을 차지해 이름 자리가 줄어듭니다. */
                  style: IconButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(36, 36),
                      fixedSize: const Size(36, 36),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                  icon: const Icon(LucideIcons.minus, size: 18),
                ),
              if (done)
                IconButton.filledTonal(
                  key: ValueKey('set-$slug'),
                  tooltip: '세트 추가',
                  onPressed: onSet,
                  style: IconButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(36, 36),
                      fixedSize: const Size(36, 36),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                  icon: const Icon(LucideIcons.plus, size: 18),
                )
              else
                SizedBox(
                  height: 40,
                  child: FilledButton.tonalIcon(
                    key: ValueKey('set-$slug'),
                    onPressed: onSet,
                    style: FilledButton.styleFrom(
                        padding: const EdgeInsets.fromLTRB(12, 0, 14, 0),
                        minimumSize: const Size(0, 40)),
                    icon: const Icon(LucideIcons.plus, size: 16),
                    label: const Text('세트'),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// 세트 점 — 세트 하나에 점 하나, 한 점씩 채웁니다. '1/3' 보다 빨리 읽히고 줄 높이를
/// 안 잡아먹습니다. 점이 여섯을 넘으면 이름 자리를 밀어내므로 그때는 숫자로 쓰고,
/// 계획보다 더 했으면('4/3') 점으로는 못 그리니 강조색 숫자로 씁니다.
class _SetDots extends StatelessWidget {
  const _SetDots({required this.done, required this.total});
  final int done;
  final int total;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final on = t.colorScheme.primary;
    if (total > 6 || done > total) {
      final over = done > total;
      return Text('$done/$total',
          style: t.textTheme.labelMedium?.copyWith(
              color: over ? on : t.hintColor,
              fontWeight: over ? FontWeight.w700 : null,
              fontFeatures: const [FontFeature.tabularFigures()]));
    }
    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (var i = 0; i < total; i++)
        Container(
          width: 8,
          height: 8,
          margin: EdgeInsets.only(left: i == 0 ? 0 : 4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: i < done ? on : null,
            border: Border.all(color: i < done ? on : t.hintColor, width: 1.5),
          ),
        ),
    ]);
  }
}

/// 끌고 있는 줄 — 살짝 커지고 그림자 없이. 기본 장식은 네모난 Material 그림자라
/// 둥근 카드 밖으로 각진 그늘이 비칩니다. 튜토리얼의 연습 목록도 이걸 씁니다 —
/// 배우는 줄과 실제 줄이 같아야 합니다.
Widget gymDragProxy(Widget child, int index, Animation<double> animation) {
  return AnimatedBuilder(
    animation: animation,
    builder: (context, child) => Transform.scale(
      scale: 1 + 0.03 * Curves.easeInOut.transform(animation.value),
      child: child,
    ),
    child: Material(type: MaterialType.transparency, child: child),
  );
}

/// 맨몸 종목 한 줄 — 체크 하나.
class _BodyweightRow extends StatelessWidget {
  const _BodyweightRow({required this.ex, required this.checked, required this.onChanged});
  final Map<String, Object?> ex;
  final bool checked;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final sets = n0(ex['sets'] ?? 1);
    final amount = amountLabel(ex);
    final note = '${ex['note'] ?? ''}';
    final slug = slugOf('${ex['name'] ?? ''}');
    final hint = t.textTheme.bodySmall?.copyWith(color: t.hintColor);
    return MbCard(
      padding: EdgeInsets.zero,
      child: CheckboxListTile(
        contentPadding: const EdgeInsets.fromLTRB(8, 2, 16, 2),
        controlAffinity: ListTileControlAffinity.leading,
        value: checked,
        onChanged: (v) => onChanged(v ?? false),
        title: Text('${ex['name'] ?? ''}',
            style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        /* 헬스 줄(ExerciseRow)과 같은 문법 — 계획 한 줄, 요령은 그 밑 흐리게. 한 줄에 이어 붙이면
           「3세트 × 30초 · 엉덩이가 처지지 않게」 가 한 문장으로 읽힙니다(3차 피드백 30). */
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(amount.isEmpty ? '$sets세트' : '$sets세트 × $amount',
              key: ValueKey('bw-plan-$slug'), maxLines: 1, overflow: TextOverflow.ellipsis, style: hint),
          if (note.isNotEmpty)
            Text(note,
                key: ValueKey('bw-note-$slug'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: t.textTheme.labelSmall
                    ?.copyWith(color: t.hintColor.withValues(alpha: t.hintColor.a * 0.7))),
        ]),
      ),
    );
  }
}

/// 바닥 시트의 공통 여백. 키보드가 올라오면 그만큼 밀어 올립니다 — 분 칸이
/// 키보드 밑에 숨으면 저장 버튼도 같이 숨습니다.
class _Sheet extends StatelessWidget {
  const _Sheet({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}
