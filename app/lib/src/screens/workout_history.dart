/* =============================================================================
 * workout_history.dart — 지난 운동 기록
 *
 * 헬스 · 맨몸 · 유산소 기록은 코어의 일정(state['schedule'][날짜]['log'])에 쌓이는데,
 * 0.2.21 까지는 그걸 **다시 볼 화면이 없었습니다** — 무게 단추의 「지난번 55kg」 (30일 안의
 * 마지막 한 번)과 홈 · 친구의 주간 요약뿐. 헬스장에서 「지난주에 몇 kg 몇 개 했더라」 를
 * 보는 길이 이 화면입니다.
 *
 *   날짜별  최근 날부터. 날마다 헬스(종목 · 세트별 무게 × 횟수 · 시간 · kcal) · 맨몸 · 유산소.
 *   종목별  종목마다 몇 번 · 마지막 날 · 최고 무게 → 누르면 그 종목의 날짜별 세트.
 *   달력    한 달씩 넘겨 처음 기록까지(workout_calendar.dart). 홈 「이번 주 운동」 에서 열면 이것부터.
 *
 * 세트별 무게 · 횟수는 setLog(workout/sets.dart)에서 읽고, 그 칸이 없는 옛 기록은
 * 「60kg ×3세트」 처럼 횟수 없이 보입니다 — 지어내지 않습니다. 이 화면은 읽기만 합니다.
 * ========================================================================== */
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:mybody_core/mybody_core.dart' as core;

import '../app_state.dart';
import '../scope.dart';
import '../ui/fmt.dart';
import '../ui/widgets.dart';
import '../workout/kcal.dart';
import '../workout/sets.dart';
import 'workout_calendar.dart';

/// 하루의 기록 — 그 날짜에 헬스(또는 맨몸) · 유산소 중 있는 것.
class HistoryDay {
  const HistoryDay({required this.key, this.gym, this.cardio});
  final String key;
  final Map<String, Object?>? gym;
  final Map<String, Object?>? cardio;
}

/// 종목 하나의 어느 날 기록.
class ExerciseDay {
  const ExerciseDay({required this.key, required this.sets, required this.planned});
  final String key;
  final List<SetEntry> sets;
  /// 계획 세트 × 반복 — '3세트 × 8-12'. 옛 기록의 맥락.
  final String planned;
  double get volume => setLogVolume(sets);
  double? get maxKg => setLogMaxKg(sets);
}

/// 종목별 묶음.
class ExerciseHistory {
  ExerciseHistory(this.name);
  final String name;
  final List<ExerciseDay> days = [];
  int get times => days.length;
  String get lastKey => days.first.key;
  double? get bestKg {
    double? m;
    for (final d in days) {
      final k = d.maxKg;
      if (k != null && (m == null || k > m)) m = k;
    }
    return m;
  }
}

/// 일정에서 기록이 있는 날들 — 최근 날부터. 순수 함수라 시험이 바로 부릅니다.
List<HistoryDay> historyDays(Map<String, Object?> state) {
  final sch = state['schedule'];
  if (sch is! Map) return const [];
  final out = <HistoryDay>[];
  for (final k in sch.keys) {
    final day = sch[k];
    final log = day is Map ? day['log'] : null;
    if (log is! Map) continue;
    final gym = log['gym'], cardio = log['cardio'];
    if (gym is! Map && cardio is! Map) continue;
    out.add(HistoryDay(
      key: '$k',
      gym: gym is Map ? gym.cast<String, Object?>() : null,
      cardio: cardio is Map ? cardio.cast<String, Object?>() : null,
    ));
  }
  out.sort((a, b) => b.key.compareTo(a.key));
  return out;
}

/// 헬스 기록(kind 'gym')의 종목별 묶음 — 최근 날부터, 많이 한 종목부터.
List<ExerciseHistory> exerciseHistories(Map<String, Object?> state) {
  final by = <String, ExerciseHistory>{};
  for (final d in historyDays(state)) {
    final g = d.gym;
    if (g == null || g['kind'] != 'gym') continue;
    final xs = g['exercises'];
    if (xs is! List) continue;
    for (final x in xs) {
      if (x is! Map) continue;
      final name = '${x['name'] ?? ''}';
      if (name.isEmpty) continue;
      final sets = setLogOf(x);
      if (sets.isEmpty) continue;
      final of = x['of'], reps = x['reps'];
      (by[name] ??= ExerciseHistory(name)).days.add(ExerciseDay(
            key: d.key,
            sets: sets,
            planned: of is num && of > 0 ? '${of.round()}세트 × ${reps ?? ''}'.trim() : '',
          ));
    }
  }
  final out = by.values.toList()
    ..sort((a, b) {
      final c = b.times.compareTo(a.times);
      return c != 0 ? c : b.lastKey.compareTo(a.lastKey);
    });
  return out;
}

const _weekdays = ['월', '화', '수', '목', '금', '토', '일'];

/// '2026-09-27' → '9/27 (일)'.
String historyDate(String key) {
  final d = DateTime.tryParse('${key}T00:00:00');
  if (d == null) return key;
  return '${d.month}/${d.day} (${_weekdays[d.weekday - 1]})';
}

/// 지난 운동 기록 화면. [type] 은 연 화면의 종류 — 유산소에서 열면 유산소 날을 먼저 펼칠 뿐,
/// 어느 쪽이든 전부 보입니다. [calendar] 면 달력부터 — 홈의 요일 칸에서 온 사람은 "지난주 ·
/// 지난달 그 칸" 을 찾습니다.
class WorkoutHistoryScreen extends StatefulWidget {
  const WorkoutHistoryScreen({super.key, this.type = 'gym', this.calendar = false});
  final String type;
  final bool calendar;

  @override
  State<WorkoutHistoryScreen> createState() => _WorkoutHistoryScreenState();
}

class _WorkoutHistoryScreenState extends State<WorkoutHistoryScreen> {
  /* 'calendar' · 'date' · 'exercise' */
  late String _mode = widget.calendar ? 'calendar' : 'date';

  @override
  Widget build(BuildContext context) {
    final app = Scope.of(context);
    final days = historyDays(app.state);
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('지난 운동 기록')),
      /* 달력은 기록(log) 없이 체크만 한 날도 그리므로 빈 안내보다 먼저 — 목록 둘만 기록이 없으면 비어 있습니다. */
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: SegmentedButton<String>(
              key: const ValueKey('history-mode'),
              segments: const [
                ButtonSegment(value: 'calendar', label: Text('달력'), icon: Icon(LucideIcons.calendarDays, size: 16)),
                ButtonSegment(value: 'date', label: Text('날짜별'), icon: Icon(LucideIcons.list, size: 16)),
                ButtonSegment(value: 'exercise', label: Text('종목별'), icon: Icon(LucideIcons.dumbbell, size: 16)),
              ],
              selected: {_mode},
              onSelectionChanged: (s) => setState(() => _mode = s.first),
              showSelectedIcon: false,
            ),
          ),
          Expanded(
            child: _mode == 'calendar'
                ? WorkoutCalendar(detail: (key) => _DayCard(day: days.firstWhere((d) => d.key == key)))
                : days.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: EmptyState(
                            title: '아직 운동 기록이 없습니다',
                            detail: '헬스 · 맨몸 · 유산소 화면에서 저장하면 여기에 날짜별로 쌓입니다',
                          ),
                        ),
                      )
                    : _mode == 'exercise'
                        ? _ByExercise(app: app)
                        : _ByDate(days: days, weightKg: _weightKg(app)),
          ),
          if (_mode != 'calendar' && days.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
              child: Text('기록은 이 기기에만 있습니다. 세트별 무게 · 횟수는 0.2.22 부터 남습니다 — 그 전 기록은 세트 수와 무게만 보입니다.',
                  style: t.textTheme.labelSmall?.copyWith(color: t.hintColor, height: 1.4)),
            ),
        ]),
      ),
    );
  }

  double? _weightKg(AppState app) {
    final scans = app.state['scans'];
    if (scans is List && scans.isNotEmpty) {
      final last = scans.last;
      if (last is Map) {
        final w = core.jsToNumber(last['weightKg']);
        if (!w.isNaN && w > 0) return w;
      }
    }
    return null;
  }
}

/* --- 날짜별 -------------------------------------------------------------- */

class _ByDate extends StatelessWidget {
  const _ByDate({required this.days, this.weightKg});
  final List<HistoryDay> days;
  final double? weightKg;

  @override
  Widget build(BuildContext context) => ListView.builder(
        key: const ValueKey('history-days'),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        itemCount: days.length,
        itemBuilder: (context, i) => _DayCard(day: days[i]),
      );
}

class _DayCard extends StatelessWidget {
  const _DayCard({required this.day});
  final HistoryDay day;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final g = day.gym, c = day.cardio;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: MbCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(historyDate(day.key), style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(width: 8),
            /* 360 폭 · 글자 1.3배에서 넘쳤습니다 — 덧붙인 날짜는 줄어들어도 됩니다. */
            Flexible(
              child: Text(dateK(day.key),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: t.textTheme.labelSmall?.copyWith(color: t.hintColor)),
            ),
          ]),
          if (g != null) ...[
            const SizedBox(height: 8),
            _GymBlock(gym: g),
          ],
          if (c != null) ...[
            const SizedBox(height: 8),
            _CardioLine(cardio: c),
          ],
        ]),
      ),
    );
  }
}

/// 헬스(또는 맨몸) 하루 — 머리 한 줄(종류 · 시간 · 세트 · kcal)과 종목 줄들.
class _GymBlock extends StatelessWidget {
  const _GymBlock({required this.gym});
  final Map<String, Object?> gym;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final bw = gym['kind'] == 'bodyweight';
    final minutes = core.jsToNumber(gym['minutes']);
    final kcal = core.jsToNumber(gym['kcal']);
    final sets = core.jsToNumber(gym['sets']);
    final xs = gym['exercises'];
    final head = <String>[
      if (!minutes.isNaN && minutes > 0) '${n0(minutes)}분',
      if (!sets.isNaN && sets > 0) '${n0(sets)}세트',
      if (!kcal.isNaN && kcal > 0) '${n0(kcal)} kcal',
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(bw ? LucideIcons.home : LucideIcons.dumbbell, size: 16, color: t.colorScheme.primary),
        const SizedBox(width: 6),
        Text(bw ? '집에서 맨몸' : '헬스', style: t.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(width: 8),
        Expanded(child: Text(head.join(' · '), style: t.textTheme.labelSmall?.copyWith(color: t.hintColor))),
      ]),
      if (xs is List && xs.isNotEmpty) ...[
        const SizedBox(height: 6),
        for (final x in xs)
          if (x is Map)
            _ExerciseLine(name: '${x['name'] ?? ''}', detail: setLogSummary(setLogOf(x)))
          else
            _ExerciseLine(name: '$x', detail: ''),
      ],
    ]);
  }
}

class _ExerciseLine extends StatelessWidget {
  const _ExerciseLine({required this.name, required this.detail});
  final String name;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 22, bottom: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(flex: 5, child: Text(name, style: t.textTheme.bodyMedium)),
        if (detail.isNotEmpty)
          Expanded(
            flex: 6,
            child: Text(detail,
                textAlign: TextAlign.right,
                style: t.textTheme.bodySmall?.copyWith(
                    color: t.hintColor, fontFeatures: const [FontFeature.tabularFigures()])),
          ),
      ]),
    );
  }
}

class _CardioLine extends StatelessWidget {
  const _CardioLine({required this.cardio});
  final Map<String, Object?> cardio;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final kind = '${cardio['kind'] ?? 'cardio'}';
    final label = sportOf(kind)?.label ?? '유산소';
    final minutes = core.jsToNumber(cardio['minutes']);
    final km = core.jsToNumber(cardio['km']);
    final kcal = core.jsToNumber(cardio['kcal']);
    final parts = <String>[
      if (!minutes.isNaN && minutes > 0) '${n0(minutes)}분',
      if (!km.isNaN && km > 0) '${n1(km)} km',
      if (!kcal.isNaN && kcal > 0) '${n0(kcal)} kcal',
    ];
    return Row(children: [
      Icon(LucideIcons.footprints, size: 16, color: t.colorScheme.primary),
      const SizedBox(width: 6),
      Text(label, style: t.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(width: 8),
      Expanded(child: Text(parts.join(' · '), style: t.textTheme.labelSmall?.copyWith(color: t.hintColor))),
    ]);
  }
}

/* --- 종목별 -------------------------------------------------------------- */

class _ByExercise extends StatelessWidget {
  const _ByExercise({required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final list = exerciseHistories(app.state);
    if (list.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: EmptyState(title: '종목별로 볼 헬스 기록이 없습니다', detail: '헬스 화면에서 세트를 저장하면 종목마다 모입니다'),
        ),
      );
    }
    return ListView.builder(
      key: const ValueKey('history-exercises'),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      itemCount: list.length,
      itemBuilder: (context, i) {
        final h = list[i];
        final best = h.bestKg;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: MbCard(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => _ExerciseScreen(history: h))),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(h.name, style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text('${h.times}번 · 마지막 ${historyDate(h.lastKey)}${best == null ? '' : ' · 최고 ${SetEntry.kgLabel(best)}kg'}',
                      style: t.textTheme.bodySmall?.copyWith(color: t.hintColor)),
                ]),
              ),
              Icon(LucideIcons.chevronRight, size: 18, color: t.hintColor),
            ]),
          ),
        );
      },
    );
  }
}

/// 한 종목의 날짜별 세트.
class _ExerciseScreen extends StatelessWidget {
  const _ExerciseScreen({required this.history});
  final ExerciseHistory history;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final best = history.bestKg;
    return Scaffold(
      appBar: AppBar(title: Text(history.name)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          children: [
            /* Stat 은 안에 Expanded 가 있어 폭이 정해져야 합니다 — 줄마다 Expanded 로. */
            Row(children: [
              Expanded(child: Stat(label: '한 날', value: '${history.times}', unit: '번')),
              const SizedBox(width: 16),
              Expanded(
                  child: Stat(
                      label: '최고', value: best == null ? '맨몸' : SetEntry.kgLabel(best), unit: best == null ? null : 'kg')),
            ]),
            const SizedBox(height: 12),
            for (final d in history.days)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: MbCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Text(historyDate(d.key), style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                      const Spacer(),
                      if (d.volume > 0)
                        Text('볼륨 ${n0(d.volume)}kg', style: t.textTheme.labelSmall?.copyWith(color: t.hintColor)),
                    ]),
                    const SizedBox(height: 6),
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      for (var i = 0; i < d.sets.length; i++)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: t.colorScheme.secondaryContainer.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text('${i + 1}  ${d.sets[i].label}',
                              style: t.textTheme.labelMedium?.copyWith(
                                  fontWeight: FontWeight.w700, fontFeatures: const [FontFeature.tabularFigures()])),
                        ),
                    ]),
                    if (d.planned.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text('계획 ${d.planned}', style: t.textTheme.labelSmall?.copyWith(color: t.hintColor)),
                    ],
                  ]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
