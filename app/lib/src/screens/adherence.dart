/* =============================================================================
 * adherence.dart — P21 달성률 (플랜 탭 위의 「달성률」)
 *
 * 운동과 식단을 한 자리에서 봅니다. 운동은 홈에서 체크한 일정에서, 식단은
 * 끼니 기록에서 셉니다. 계산은 ../adherence.dart 가 하고 — 주간 체크인도
 * 같은 숫자를 씁니다 — 여기는 그리기만 합니다.
 *
 * 분모를 반드시 씁니다. "3일" 이 아니라 "계획한 5일 중 3일" 입니다.
 * ========================================================================== */
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mybody_core/mybody_core.dart' as core;

import '../adherence.dart';
import '../scope.dart';
import '../ui/fmt.dart';
import '../theme.dart' show MbColors;
import '../ui/widgets.dart';

Map<String, Object?>? _targetOf(BuildContext context) {
  final plan = Scope.of(context).state['plan'];
  if (plan is! Map) return null;
  final m = plan['macros'];
  return m is Map ? m.cast<String, Object?>() : null;
}

String _dowOf(String key) {
  final d = DateTime.tryParse('${key}T00:00:00');
  return d == null ? '' : core.kDow[(d.weekday - 1) % 7];
}

class AdherenceScreen extends StatelessWidget {
  const AdherenceScreen({super.key, required this.go});
  final void Function(String route, [Object? arg]) go;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('달성률')),
        body: ListView(padding: const EdgeInsets.all(16), children: [AdherenceBody(go: go)]),
      );
}

/// 플랜 탭 위의 「달성률」이 보여 주는 것. 스크롤은 밖에서 맡습니다.
class AdherenceBody extends StatefulWidget {
  const AdherenceBody({super.key, required this.go});
  final void Function(String route, [Object? arg]) go;

  @override
  State<AdherenceBody> createState() => _AdherenceBodyState();
}

class _AdherenceBodyState extends State<AdherenceBody> {
  String _tab = 'week';

  @override
  Widget build(BuildContext context) {
    final app = Scope.of(context);
    final t = Theme.of(context);
    final target = _targetOf(context);
    final hint = t.textTheme.bodySmall?.copyWith(color: t.hintColor, height: 1.5);
    final n = _tab == 'week' ? 7 : 30;
    final label = _tab == 'week' ? '최근 7일' : '최근 30일';

    final tabs = SegmentedButton<String>(
      showSelectedIcon: false,
      segments: const [
        ButtonSegment(value: 'week', label: Text('주간')),
        ButtonSegment(value: 'month', label: Text('월간')),
      ],
      selected: {_tab},
      onSelectionChanged: (s) => setState(() => _tab = s.first),
    );

    final w = workoutAdherence(app.store, n);
    final streak = app.schedule.workoutStreak();

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      tabs,
      const SizedBox(height: 12),

      /* --- 운동 ------------------------------------------------------------ */
      _WorkoutCard(w: w, streak: streak, label: label, week: _tab == 'week'),

      /* --- 식단 ------------------------------------------------------------ */
      if (target == null)
        MbCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SectionTitle('식단 · $label'),
            Text('플랜을 만들면 칼로리·단백질 목표가 생기고, 기록을 거기에 대조해서 보여드립니다.',
                style: hint),
            const SizedBox(height: 10),
            FilledButton(onPressed: () => widget.go('goal'), child: const Text('플랜 만들기')),
          ]),
        )
      else
        ..._diet(context, target, n, label, hint),
    ]);
  }

  List<Widget> _diet(BuildContext context, Map<String, Object?> target, int n, String label,
      TextStyle? hint) {
    final app = Scope.of(context);
    final days = dietDays(app.store, n);
    final adh = core.dietAdherence(days, target)!;
    final loggedDays = core.jsToNumber(adh['loggedDays']);
    final missedDays = core.jsToNumber(adh['missedDays']);
    final totalDays = core.jsToNumber(adh['totalDays']);
    final avg = (adh['avg'] as Map?)?.cast<String, Object?>();
    final pct = (adh['pct'] as Map?)?.cast<String, Object?>();

    return [
      /* 요약 — 분모를 반드시 명시합니다. */
      MbCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SectionTitle('식단 · $label',
              trailing: Pill('기록 ${n0(loggedDays)}/${n0(totalDays)}일',
                  tone: core.jsToNumber(adh['logRatePct']) >= 70 ? Tone.ok : Tone.none)),
          if (loggedDays == 0)
            Text('이 기간에 기록이 없습니다.', style: hint)
          else ...[
            Row(children: [
              Expanded(child: Stat(label: '칼로리 평균', value: n0(avg?['kcal']), unit: 'kcal',
                  delta: '${n0(pct?['kcal'])}%')),
              Expanded(child: Stat(label: '단백질 평균', value: n0(avg?['p']), unit: 'g',
                  delta: '${n0(pct?['p'])}%')),
            ]),
            Row(children: [
              Expanded(child: Stat(label: '범위 안', value: n0(adh['inBandDays']), unit: '일',
                  delta: '${n0(adh['inBandPct'])}%')),
              Expanded(child: Stat(label: '단백질 달성', value: n0(adh['proteinHitDays']), unit: '일',
                  delta: '${n0(adh['proteinHitPct'])}%')),
            ]),
            const SizedBox(height: 6),
            Text(
                '평균은 기록한 ${n0(loggedDays)}일만으로 냈습니다. '
                '${missedDays > 0 ? '기록 없는 ${n0(missedDays)}일은 0으로 치지 않고 분모에서 뺐습니다.' : ''}',
                style: hint),
          ],
        ]),
      ),
      if (missedDays >= (totalDays * 0.5).ceil())
        const Note(
            text: '절반 이상 안 적으셨습니다. 매 끼니를 다 적을 필요는 없고, '
                '단백질 들어간 것만 적어도 이 화면은 쓸모가 있습니다.'),
      if (_tab == 'week')
        ..._week(context, days, target, adh)
      else
        _month(context, days, target, adh),
      const Note(
          text: '하루 값이 아니라 주 평균으로 보세요. 기록 오차와 TDEE 추정 오차가 겹쳐서, '
              '하루치 숫자는 원래 흔들립니다. 계획은 체중 변화를 보고 조정됩니다.'),
    ];
  }

  /* 주간 — 일별 막대 + 목표선. 단일 숫자만 보면 "평균은 맞는데 널뛰기" 를 놓칩니다. */
  List<Widget> _week(BuildContext context, List<Map<String, Object?>> days,
      Map<String, Object?> target, Map<String, Object?> adh) {
    final t = Theme.of(context);
    final c = mb(context);
    final avg = (adh['avg'] as Map?)?.cast<String, Object?>();
    final pct = (adh['pct'] as Map?)?.cast<String, Object?>();
    final loggedDays = core.jsToNumber(adh['loggedDays']);
    final specs = [
      ('단백질', 'p', core.jsToNumber(target['proteinG']), c.muscle, 'g'),
      ('칼로리', 'kcal', core.jsToNumber(target['intakeKcal']), t.colorScheme.primary, 'kcal'),
      ('탄수화물', 'c', core.jsToNumber(target['carbG']), t.hintColor, 'g'),
      ('지방', 'f', core.jsToNumber(target['fatG']), c.fat, 'g'),
    ];
    return [
      for (final s in specs)
        MbCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SectionTitle(s.$1,
                trailing: Text('목표 ${n0(s.$3)}${s.$5}',
                    style: t.textTheme.labelSmall?.copyWith(color: t.hintColor))),
            Builder(builder: (_) {
              final vals = [for (final d in days) core.jsToNumber(d[s.$2] ?? 0)];
              final maxV = [s.$3 * 1.4, vals.reduce(math.max) * 1.1, 1.0].reduce(math.max);
              return SizedBox(
                height: 90,
                child: Stack(children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    for (var i = 0; i < days.length; i++)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: Container(
                            height: core.jsTruthy(days[i]['logged'])
                                ? math.max(3.0, vals[i] / maxV * 70)
                                : 3,
                            decoration: BoxDecoration(
                              color: core.jsTruthy(days[i]['logged'])
                                  ? s.$4.withValues(alpha: vals[i] >= s.$3 * 0.9 ? 1 : 0.55)
                                  : t.dividerColor,
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                            ),
                          ),
                        ),
                      ),
                  ]),
                  /* 목표선 */
                  Positioned(
                    left: 0, right: 0, bottom: (70 * s.$3 / maxV).clamp(0.0, 90.0),
                    child: Container(height: 1, color: t.hintColor.withValues(alpha: 0.4)),
                  ),
                ]),
              );
            }),
            Row(children: [
              for (final d in days)
                Expanded(
                  child: Text(core.jsTruthy(d['logged']) ? _dowOf('${d['date']}') : '·',
                      textAlign: TextAlign.center,
                      style: t.textTheme.labelSmall?.copyWith(color: t.hintColor, fontSize: 10)),
                ),
            ]),
            const SizedBox(height: 6),
            Text(
                loggedDays > 0
                    ? '기록한 ${n0(loggedDays)}일 평균 ${n0(avg?[s.$2])}${s.$5} (목표의 ${n0(pct?[s.$2])}%)'
                    : '기록 없음',
                style: t.textTheme.bodySmall?.copyWith(color: t.hintColor)),
          ]),
        ),
    ];
  }

  /* 월간 — 패턴을 봅니다. 미기록일은 0이 아니라 "없음" 으로 그립니다. */
  Widget _month(BuildContext context, List<Map<String, Object?>> days,
      Map<String, Object?> target, Map<String, Object?> adh) {
    final t = Theme.of(context);
    final c = mb(context);
    final band = (adh['band'] as Map?)?.cast<String, Object?>();
    final lo = core.jsToNumber(band?['lo']), hi = core.jsToNumber(band?['hi']);
    final tp = core.jsToNumber(target['proteinG']);
    return MbCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionTitle('식단 30일',
            trailing: Text('칸 하나 = 하루', style: t.textTheme.labelSmall?.copyWith(color: t.hintColor))),
        GridView.count(
          crossAxisCount: 7, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 4, crossAxisSpacing: 4,
          children: [
            for (final d in days)
              Builder(builder: (_) {
                final logged = core.jsTruthy(d['logged']);
                final kcal = core.jsToNumber(d['kcal']);
                Color bg = t.scaffoldBackgroundColor;
                if (logged) {
                  bg = kcal < lo
                      ? t.colorScheme.primary.withValues(alpha: 0.25)
                      : (kcal > hi ? c.warn.withValues(alpha: 0.35) : c.ok.withValues(alpha: 0.35));
                }
                final hit = logged && core.jsToNumber(d['p']) >= tp * 0.9;
                return Container(
                  decoration: BoxDecoration(
                      color: bg, borderRadius: BorderRadius.circular(6),
                      border: logged ? null : Border.all(color: t.dividerColor)),
                  alignment: Alignment.center,
                  child: hit ? Text('•', style: TextStyle(color: c.muscle, fontSize: 14)) : null,
                );
              }),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 10, runSpacing: 6, children: [
          _Legend('범위 안', c.ok.withValues(alpha: 0.35)),
          _Legend('범위 위', c.warn.withValues(alpha: 0.35)),
          _Legend('범위 아래', t.colorScheme.primary.withValues(alpha: 0.25)),
          _Legend('기록 없음', t.scaffoldBackgroundColor, dashed: true),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Text('•', style: TextStyle(color: c.muscle)),
            const SizedBox(width: 3),
            Text('단백질 달성', style: t.textTheme.labelSmall?.copyWith(color: t.hintColor)),
          ]),
        ]),
        const SizedBox(height: 8),
        Text('여기서 볼 건 정확한 값이 아니라 패턴입니다 — 주말에 무너지는지, 바쁜 주에 끊기는지.',
            style: t.textTheme.bodySmall?.copyWith(color: t.hintColor, height: 1.5)),
      ]),
    );
  }
}

/* --- 운동 ------------------------------------------------------------------
   "지킨 날 / 계획한 날". 오늘 아직 안 한 것은 놓친 게 아니라 열린 것이라
   분모에 안 넣습니다 — 아침에 열어 보고 0% 를 맞으면 안 됩니다. */
class _WorkoutCard extends StatelessWidget {
  const _WorkoutCard({required this.w, required this.streak, required this.label, required this.week});
  final Map<String, Object?> w;
  final Map<String, Object?> streak;
  final String label;
  final bool week;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = mb(context);
    final hint = t.textTheme.bodySmall?.copyWith(color: t.hintColor, height: 1.5);
    final planned = core.jsToNumber(w['plannedDays']);
    final kept = core.jsToNumber(w['keptDays']);
    final missed = core.jsToNumber(w['missedDays']);
    final open = core.jsToNumber(w['openDays']);
    final pct = w['pct'];
    final byType = (w['byType'] as Map?)?.cast<String, Map<String, int>>() ?? const {};
    final days = ((w['days'] as List?) ?? const []).cast<Map<String, Object?>>();
    final types = [
      for (final st in core.kSchedTypes)
        if (byType.containsKey(st['id']))
          '${st['label']} ${byType[st['id']]!['done']}/${byType[st['id']]!['planned']}',
    ];

    return MbCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionTitle('운동 · $label',
            trailing: Pill('계획 ${n0(planned)}일', tone: planned > 0 ? Tone.ok : Tone.none)),
        if (planned == 0)
          Text('이 기간에 계획한 운동이 없습니다. 홈에서 요일을 켜 두면 여기서 셉니다.', style: hint)
        else ...[
          Row(children: [
            Expanded(child: Stat(label: '지킨 날', value: n0(kept), unit: '일',
                delta: pct == null ? '오늘만 남음' : '${n0(pct)}%')),
            Expanded(child: Stat(label: '놓친 날', value: n0(missed), unit: '일',
                delta: open > 0 ? '오늘 ${n0(open)}일 남음' : null)),
          ]),
          const SizedBox(height: 6),
          if (types.isNotEmpty) Text(types.join(' · '), style: hint),
          Text(
              '연속 ${n0(streak['days'])}일 · 최근 28일 중 ${n0(streak['last28'])}일. '
              '계획한 날만 세고, 쉬는 날은 끊지 않습니다.',
              style: hint),
        ],
        const SizedBox(height: 10),
        if (week) _WeekStrip(days: days, c: c) else _MonthGrid(days: days, c: c),
      ]),
    );
  }
}

/// 7칸 — 요일 + 동그라미. 지킴 = 채움, 놓침 = 경고색 테두리, 오늘(열림) = 점선, 쉼 = 점.
class _WeekStrip extends StatelessWidget {
  const _WeekStrip({required this.days, required this.c});
  final List<Map<String, Object?>> days;
  final MbColors c;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Row(children: [
      for (final d in days)
        Expanded(
          child: Column(children: [
            Text('${d['dow']}',
                style: t.textTheme.labelSmall?.copyWith(
                    color: core.jsTruthy(d['isToday']) ? t.colorScheme.primary : t.hintColor)),
            const SizedBox(height: 4),
            _Cell(d: d, c: c, size: 22),
          ]),
        ),
    ]);
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({required this.days, required this.c});
  final List<Map<String, Object?>> days;
  final MbColors c;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      GridView.count(
        crossAxisCount: 10, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 4, crossAxisSpacing: 4,
        children: [for (final d in days) _Cell(d: d, c: c)],
      ),
      const SizedBox(height: 8),
      Wrap(spacing: 10, runSpacing: 6, children: [
        _Legend('지킴', t.colorScheme.primary),
        _Legend('놓침', c.warn.withValues(alpha: 0.35)),
        _Legend('쉬는 날', t.scaffoldBackgroundColor, dashed: true),
      ]),
    ]);
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.d, required this.c, this.size});
  final Map<String, Object?> d;
  final MbColors c;
  final double? size;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final kept = core.jsTruthy(d['kept']);
    final missed = core.jsTruthy(d['missed']);
    final open = core.jsTruthy(d['open']);
    final rest = (d['plan'] as List? ?? const []).isEmpty;
    final bg = kept
        ? t.colorScheme.primary
        : missed
            ? c.warn.withValues(alpha: 0.35)
            : t.scaffoldBackgroundColor;
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(size == null ? 6 : size! / 2),
        border: kept || missed
            ? null
            : Border.all(
                color: open ? t.colorScheme.primary : t.dividerColor,
                width: open ? 1.5 : 1),
      ),
      alignment: Alignment.center,
      child: rest && size != null
          ? Text('·', style: TextStyle(color: t.hintColor, fontSize: 12, height: 1))
          : null,
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend(this.label, this.color, {this.dashed = false});
  final String label;
  final Color color;
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 11, height: 11,
        decoration: BoxDecoration(
            color: color, borderRadius: BorderRadius.circular(3),
            border: dashed ? Border.all(color: t.dividerColor) : null),
      ),
      const SizedBox(width: 4),
      Text(label, style: t.textTheme.labelSmall?.copyWith(color: t.hintColor)),
    ]);
  }
}
