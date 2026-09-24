/* =============================================================================
 * workout_session.dart — 헬스장에서 쓰는 운동 화면 (헬스 · 유산소 · 집에서 맨몸)
 *
 * 홈의 「헬스 했어요」 는 체크 하나였습니다. 체크는 남는데 **얼마나** 했는지는
 * 안 남았습니다 — 40분을 했는지, 세트를 몇 개 했는지, 그래서 몇 kcal 을
 * 썼는지. 이 화면은 그걸 남깁니다. 다만 헬스장에서 쓰는 화면이라 규칙이
 * 있습니다:
 *
 *   · 글자는 적게, 버튼은 크게. 땀 난 손으로, 한 손으로 누릅니다.
 *   · 시간은 시계가 잽니다. 화면이 다시 그려지든 말든 `_startedAt` 과 쌓인
 *     시간으로 계산하고, 주기 타이머는 숫자를 다시 그리는 용도뿐입니다.
 *     시계는 [WorkoutSessionScreen.clock] 으로 뚫어 두어 시험이 세울 수 있습니다.
 *   · 시작을 잊는 사람이 많습니다. 세트를 누르면 시간이 알아서 갑니다.
 *     끝낼 때 분을 고칠 수 있게 두어, 기록이 0분으로 남지 않습니다.
 *   · 아직 오지 않은 날은 저장을 막습니다(코어도 거부합니다) — 내일 할 운동을
 *     오늘 적는 건 기록이 아니라 소원입니다.
 *
 * 기록은 코어의 setScheduleLog 로 갑니다 — 그 날의 체크(done)까지 같이 남습니다.
 *   헬스   log['gym']    = {kind:'gym', startedAt, minutes, kcal, sets, exercises:[{name, sets, of}]}
 *   맨몸   log['gym']    = {kind:'bodyweight', minutes, kcal, exercises:[이름…]}
 *   유산소 log['cardio'] = {kind:'walk'|'run'|'bike'|'cardio', startedAt, minutes, km, kcal}
 * ========================================================================== */
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:mybody_core/mybody_core.dart' as core;

import '../app_state.dart';
import '../scope.dart';
import '../ui/fmt.dart';
import '../ui/widgets.dart';
import '../workout/bodyweight.dart';
import '../workout/exercises.dart';
import '../workout/kcal.dart';
import '../workout/planner.dart';
import '../workout/prefs.dart';

/// 화면 종류. 셸이 `go('workout', (dateKey: …, type: …))` 로 넘깁니다.
const kWorkoutTypes = ['gym', 'cardio', 'bodyweight'];

/// 체중을 모를 때(측정이 없을 때) 쓰는 값. 화면이 그 사실을 같이 말합니다.
const kFallbackWeightKg = 70.0;

/// 이만큼 했으면 나머지는 다음에 — 확인만 받고 기록합니다.
const kBodyweightEnoughRatio = 0.6;

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
/// 빈 화면이면 안 됩니다.
List<Map<String, Object?>> gymExercisesFor(Map<String, Object?> state, String dateKey) {
  final settings = (state['settings'] as Map?)?.cast<String, Object?>();
  final prefs = GymPrefs.fromSettings(settings);
  final session = planSessionFor(state, dateKey);
  if (session != null) {
    final out = tailorSession(session, prefs);
    if (out.isNotEmpty) return out;
  }
  /* 부위마다 하나 — 전신. 기구 제한은 그대로 지킵니다. */
  const groups = ['chest', 'back', 'quads', 'shoulder', 'core'];
  final out = <Map<String, Object?>>[];
  for (final g in groups) {
    /* 집이면 철봉 · 평행봉이 필요한 종목은 뺍니다 — tailorSession 과 같은 규칙. */
    final pool = exercisesFor(g, equip: prefs.equipment.isEmpty ? null : prefs.equipment)
        .where((e) => !(e.needsBar && prefs.isHome))
        .toList();
    if (pool.isEmpty) continue;
    final e = pool.first;
    out.add({
      'id': e.id, 'name': e.name, 'group': e.group, 'equip': e.equip, 'note': e.note,
      'sets': 3, 'reps': '10-15', 'restSec': 75,
    });
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

/// 종목 한 줄의 진행 상태.
class _Ex {
  _Ex({required this.name, required this.sets, required this.reps, required this.restSec, this.note});

  final String name;
  final int sets;
  final String reps;
  final int restSec;
  final String? note;
  int done = 0;

  bool get complete => done >= sets;

  /// planner · exercisesFor 가 주는 모양에서. 빈 값은 엔진의 기본(3세트 · 10-15 · 75초)으로.
  static _Ex from(Map<String, Object?> m) {
    final sets = core.jsToNumber(m['sets']);
    final rest = core.jsToNumber(m['restSec']);
    final reps = m['reps'] != null && '${m['reps']}'.isNotEmpty
        ? '${m['reps']}'
        : (m['seconds'] != null ? '${n0(m['seconds'])}초' : '10-15');
    final note = m['note'] == null ? '' : '${m['note']}';
    return _Ex(
      name: '${m['name'] ?? ''}',
      sets: sets.isNaN || sets < 1 ? 3 : sets.round(),
      reps: reps,
      restSec: rest.isNaN || rest < 0 ? 75 : rest.round(),
      note: note.isEmpty ? null : note,
    );
  }
}

class _WorkoutSessionScreenState extends State<WorkoutSessionScreen> {
  /* --- 시계 -------------------------------------------------------------- */
  DateTime? _startedAt;                    // 지금 도는 구간의 시작. null 이면 멈춤
  Duration _accumulated = Duration.zero;   // 멈추기 전까지 쌓인 시간
  DateTime? _firstStartedAt;               // 기록에 남기는 시작 시각
  Timer? _tick;                            // 숫자를 다시 그리는 용도뿐

  /* --- 헬스 -------------------------------------------------------------- */
  List<_Ex>? _gym;
  DateTime? _restEndsAt;
  int _restTotalSec = 0;

  /* --- 집에서 맨몸 ---------------------------------------------------------- */
  Map<String, Object?>? _routine;
  List<bool> _checked = const [];

  static DateTime _now() => WorkoutSessionScreen.clock();

  bool get _running => _startedAt != null;
  Duration get _elapsed =>
      _accumulated + (_startedAt == null ? Duration.zero : _now().difference(_startedAt!));
  int get _elapsedMinutes => (_elapsed.inSeconds / 60).round();
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
    super.dispose();
  }

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

  void _completeSet(_Ex e) {
    if (e.complete) return;
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

  void _undoSet(_Ex e) {
    if (e.done <= 0) return;
    setState(() => e.done--);
  }

  void _skipRest() {
    setState(() => _restEndsAt = null);
    _syncTick();
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
        content: const Text('지금까지 잰 시간과 세트는 남지 않습니다. 「종료」 를 누르면 저장할 수 있습니다.'),
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
        text: '그날이 되면 기록할 수 있습니다 — 내일 할 운동을 오늘 적는 건 기록이 아니라 소원입니다.',
      );

  /* --- 헬스 -------------------------------------------------------------- */

  Widget _gymBody(BuildContext context, AppState app, bool future) {
    final list = _gym ??= [for (final m in gymExercisesFor(app.state, widget.dateKey)) _Ex.from(m)];
    final t = Theme.of(context);
    final doneSets = list.fold<int>(0, (a, e) => a + e.done);
    final totalSets = list.fold<int>(0, (a, e) => a + e.sets);
    final session = planSessionFor(app.state, widget.dateKey);

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
        child: list.isEmpty
            ? const EmptyState(
                title: '오늘 할 종목이 없습니다',
                detail: '설정의 「운동 장소와 기구」 에서 있는 기구를 켜 두면 여기에 종목이 나옵니다.',
              )
            : ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
                if (future) _futureNote(),
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(children: [
                    Expanded(
                      child: Text(
                        session == null ? '오늘 플랜에 없는 날 — 전신 기본 종목' : '${session['label']}',
                        style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    Text('$doneSets/$totalSets 세트',
                        style: t.textTheme.labelSmall?.copyWith(color: t.hintColor)),
                  ]),
                ),
                for (final e in list)
                  _ExerciseRow(ex: e, onSet: () => _completeSet(e), onUndo: () => _undoSet(e)),
              ]),
      ),
    ]);
  }

  Future<void> _finishGym(AppState app, bool future) async {
    final wasRunning = _running;
    _pause();
    final list = _gym ?? const <_Ex>[];
    final doneSets = list.fold<int>(0, (a, e) => a + e.done);
    final weight = latestWeightKg(app);
    final minutesCtl = TextEditingController(text: _elapsedMinutes > 0 ? '$_elapsedMinutes' : '');

    final minutes = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        final m = int.tryParse(minutesCtl.text.trim()) ?? 0;
        final kcal = m > 0
            ? workoutKcal(weightKg: weight ?? kFallbackWeightKg, duration: Duration(minutes: m), kind: 'gym')
            : 0.0;
        return _Sheet(children: [
          Text('오늘 헬스', style: Theme.of(ctx).textTheme.titleMedium),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: Stat(label: '경과', value: '$m', unit: '분')),
            Expanded(child: Stat(label: '완료 세트', value: '$doneSets')),
            Expanded(child: Stat(label: '추정', value: n0(kcal), unit: 'kcal')),
          ]),
          const SizedBox(height: 14),
          TextField(
            controller: minutesCtl,
            keyboardType: TextInputType.number,
            onChanged: (_) => setSheet(() {}),
            decoration: const InputDecoration(
                labelText: '운동 시간', suffixText: '분', border: OutlineInputBorder(),
                helperText: '시작을 안 눌렀으면 여기에 넣으세요'),
          ),
          if (weight == null) ...[
            const SizedBox(height: 8),
            Text('측정이 없어 체중 ${n0(kFallbackWeightKg)}kg 기준으로 계산했습니다.',
                style: Theme.of(ctx).textTheme.labelSmall?.copyWith(color: Theme.of(ctx).hintColor)),
          ],
          const SizedBox(height: 14),
          if (future) _futureNote(),
          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: m > 0 && !future ? () => Navigator.pop(ctx, m) : null,
              child: const Text('저장'),
            ),
          ),
        ]);
      }),
    );
    if (minutes == null || !mounted) {
      /* 창을 그냥 닫았으면 시계를 도로 돌립니다 — 실수로 누른 「종료」가 시간을 멈춰 두면 안 됩니다. */
      if (minutes == null && wasRunning && mounted) _start();
      return;
    }

    final kcal = workoutKcal(
            weightKg: weight ?? kFallbackWeightKg, duration: Duration(minutes: minutes), kind: 'gym')
        .round();
    final ok = _saveLog(app, 'gym', {
      'kind': 'gym',
      'startedAt': (_firstStartedAt ?? _now()).toUtc().toIso8601String(),
      'minutes': minutes,
      'kcal': kcal,
      'sets': doneSets,
      'exercises': [
        for (final e in list)
          if (e.done > 0) {'name': e.name, 'sets': e.done, 'of': e.sets},
      ],
    });
    if (!ok || !mounted) return;
    toast(context, '헬스 $minutes분 · 약 $kcal kcal 소모! 수고했어요');
    Navigator.of(context).pop();
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
          Text('끝나면 「종료」 — 걷기 · 달리기 · 자전거 중 고르고 거리를 적으면 kcal 을 셉니다.',
              style: t.textTheme.bodySmall?.copyWith(color: t.hintColor, height: 1.5)),
          const SizedBox(height: 12),
          /* 이미 하고 온 사람 — 시계 없이 분만 넣습니다. */
          OutlinedButton.icon(
            onPressed: () => _finishCardio(app, future),
            icon: const Icon(LucideIcons.timer, size: 18),
            label: const Text('시간을 직접 넣기'),
          ),
        ]),
      ),
    ]);
  }

  Future<void> _finishCardio(AppState app, bool future) async {
    final wasRunning = _running;
    _pause();
    final weight = latestWeightKg(app);
    final minutesCtl = TextEditingController(text: _elapsedMinutes > 0 ? '$_elapsedMinutes' : '');
    final kmCtl = TextEditingController();
    var kind = kCardioKinds.first;

    final r = await showModalBottomSheet<({String kind, int minutes, double? km})>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        final m = int.tryParse(minutesCtl.text.trim()) ?? 0;
        final km = double.tryParse(kmCtl.text.trim());
        final kcal = m > 0
            ? workoutKcal(
                weightKg: weight ?? kFallbackWeightKg,
                duration: Duration(minutes: m),
                kind: kind,
                km: km != null && km > 0 ? km : null)
            : 0.0;
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
          Row(children: [
            Expanded(
              child: TextField(
                controller: minutesCtl,
                keyboardType: TextInputType.number,
                onChanged: (_) => setSheet(() {}),
                decoration: const InputDecoration(
                    labelText: '시간', suffixText: '분', border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: kmCtl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setSheet(() {}),
                decoration: const InputDecoration(
                    labelText: '거리', suffixText: 'km', border: OutlineInputBorder(),
                    helperText: '몰라도 됩니다'),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          Stat(label: '추정', value: n0(kcal), unit: 'kcal'),
          if (weight == null)
            Text('측정이 없어 체중 ${n0(kFallbackWeightKg)}kg 기준으로 계산했습니다.',
                style: Theme.of(ctx).textTheme.labelSmall?.copyWith(color: Theme.of(ctx).hintColor)),
          const SizedBox(height: 14),
          if (future) _futureNote(),
          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: m > 0 && !future
                  ? () => Navigator.pop(ctx, (kind: kind, minutes: m, km: km != null && km > 0 ? km : null))
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
            duration: Duration(minutes: r.minutes),
            kind: r.kind,
            km: r.km)
        .round();
    final ok = _saveLog(app, 'cardio', {
      'kind': r.kind,
      'startedAt': (_firstStartedAt ?? _now()).toUtc().toIso8601String(),
      'minutes': r.minutes,
      'km': r.km,
      'kcal': kcal,
    });
    if (!ok || !mounted) return;
    toast(context, '${cardioKindLabel(r.kind)} ${r.minutes}분 · 약 $kcal kcal 소모! 수고했어요');
    Navigator.of(context).pop();
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
              text: '오늘은 이미 헬스 기록이 있습니다. 맨몸 운동은 따로 기록하지 않습니다 — 하는 건 자유예요.',
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
    await _celebrate(kcal);
    if (mounted) Navigator.of(context).pop();
  }

  /// 화면 가득한 축하. 헬스를 못 간 날 집에서 15분을 채운 사람에게 주는 것 —
  /// 토스트 한 줄로는 모자랍니다.
  Future<void> _celebrate(int kcal) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final t = Theme.of(ctx);
        final c = mb(ctx);
        return Dialog.fullscreen(
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                /* 이모지는 안 씁니다 — 앱에 넣은 글꼴에 없어서 구글에서 받아 오려 합니다(ui/symbols.dart). */
                Icon(LucideIcons.partyPopper, size: 84, color: c.ok),
                const SizedBox(height: 24),
                Text('약 $kcal kcal 소모했어요! 축하합니다',
                    textAlign: TextAlign.center,
                    style: t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                Text('오늘 계획을 지켰습니다 — 내일도 만나요',
                    textAlign: TextAlign.center,
                    style: t.textTheme.bodyLarge?.copyWith(color: t.hintColor)),
                const SizedBox(height: 36),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('닫기')),
                ),
              ]),
            ),
          ),
        );
      },
    );
  }
}

/* --- 조각들 ------------------------------------------------------------------ */

/// 큰 시계와 버튼 셋. 글자보다 버튼이 큽니다 — 한 손, 땀 난 손.
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

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(children: [
        Text(clockText(elapsed),
            style: t.textTheme.displayLarge?.copyWith(
                fontSize: 64,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()])),
        Text(running ? '운동 중' : (started ? '일시정지' : '시작을 누르면 시간이 갑니다'),
            style: t.textTheme.labelSmall?.copyWith(color: t.hintColor)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: SizedBox(
              height: 56,
              child: running
                  ? FilledButton.tonalIcon(
                      onPressed: onPause,
                      icon: const Icon(LucideIcons.pause),
                      label: const Text('일시정지', style: TextStyle(fontSize: 17)))
                  : FilledButton.icon(
                      onPressed: onStart,
                      icon: const Icon(LucideIcons.play),
                      label: Text(started ? '계속' : '시작', style: const TextStyle(fontSize: 17))),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SizedBox(
              height: 56,
              child: OutlinedButton.icon(
                onPressed: onFinish,
                icon: const Icon(LucideIcons.square),
                label: const Text('종료', style: TextStyle(fontSize: 17)),
              ),
            ),
          ),
        ]),
      ]),
    );
  }
}

/// 세트 사이 휴식. 큰 숫자 하나와 건너뛰기 — 폰을 보는 시간은 이 정도면 됩니다.
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
      padding: const EdgeInsets.fromLTRB(16, 10, 10, 12),
      decoration: BoxDecoration(color: c.accentSub, borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('휴식', style: t.textTheme.labelSmall?.copyWith(color: t.hintColor)),
          const SizedBox(width: 10),
          Text(clockText(left),
              style: t.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800, fontFeatures: const [FontFeature.tabularFigures()])),
          const Spacer(),
          TextButton(onPressed: onSkip, child: const Text('건너뛰기')),
        ]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(value: progress, minHeight: 6),
        ),
      ]),
    );
  }
}

/// 종목 한 줄 — 이름 · 세트×횟수 · 큰 세트 버튼. 다 하면 체크.
class _ExerciseRow extends StatelessWidget {
  const _ExerciseRow({required this.ex, required this.onSet, required this.onUndo});
  final _Ex ex;
  final VoidCallback onSet;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = mb(context);
    return MbCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (ex.complete)
            Padding(
              padding: const EdgeInsets.only(right: 6, top: 2),
              child: Icon(LucideIcons.checkCircle2, size: 18, color: c.ok),
            ),
          Expanded(
            child: Text(ex.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          ),
          Text('${ex.sets}세트 × ${ex.reps}',
              style: t.textTheme.bodySmall?.copyWith(color: t.hintColor)),
        ]),
        if (ex.note != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(ex.note!, style: t.textTheme.labelSmall?.copyWith(color: t.hintColor)),
          ),
        const SizedBox(height: 10),
        Row(children: [
          if (ex.done > 0)
            IconButton(
              tooltip: '한 세트 빼기',
              onPressed: onUndo,
              icon: const Icon(LucideIcons.minus),
            ),
          Expanded(
            child: SizedBox(
              height: 56,
              child: ex.complete
                  ? Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                          color: c.okBg, borderRadius: BorderRadius.circular(999)),
                      child: Text('완료',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.ok)),
                    )
                  : FilledButton(
                      onPressed: onSet,
                      child: Text('세트 완료 (${ex.done}/${ex.sets})',
                          style: const TextStyle(fontSize: 17)),
                    ),
            ),
          ),
        ]),
      ]),
    );
  }
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
    final amount = ex['seconds'] != null ? '${n0(ex['seconds'])}초' : '${ex['reps'] ?? ''}';
    final note = '${ex['note'] ?? ''}';
    return MbCard(
      padding: EdgeInsets.zero,
      child: CheckboxListTile(
        contentPadding: const EdgeInsets.fromLTRB(8, 2, 16, 2),
        controlAffinity: ListTileControlAffinity.leading,
        value: checked,
        onChanged: (v) => onChanged(v ?? false),
        title: Text('${ex['name'] ?? ''}',
            style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        subtitle: Text(
          '$sets세트 × $amount${note.isEmpty ? '' : ' · $note'}',
          style: t.textTheme.bodySmall?.copyWith(color: t.hintColor),
        ),
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
