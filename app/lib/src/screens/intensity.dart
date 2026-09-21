/* =============================================================================
 * intensity.dart — P06 강도 선택
 *
 * **강도는 난이도 라벨이 아니라 기간입니다.** 상/중/하는 "얼마나 빡세게"
 * 가 아니라 "얼마나 빨리 갈 것인가" 이고, 세 장의 카드는 세 개의 날짜입니다.
 *
 * 그리고 빡셀수록 빠른 게 아닙니다. 적자가 크면 근육이 거의 안 늘어서
 * 근육 목표가 있을 때는 **가장 공격적인 계획이 오히려 더 걸립니다.**
 * 엔진이 그 역설을 찾으면 여기서 그대로 보여 줍니다 — 숨기면 사용자는
 * 무작정 상을 고르고, 그게 제일 느린 길입니다.
 * ========================================================================== */
import 'package:flutter/material.dart';
import 'package:mybody_core/mybody_core.dart' as core;

import '../scope.dart';
import '../ui/charts.dart';
import '../ui/fmt.dart';
import '../ui/symbols.dart';
import '../ui/widgets.dart';

class IntensityScreen extends StatefulWidget {
  const IntensityScreen({super.key, required this.goal, this.modeId});
  final Map<String, Object?> goal;
  /// 앱이 고른 모드이거나 사용자가 직접 고른 모드. 이 모드의 속도 상한과
  /// 단백질 하한이 계획에 그대로 걸립니다 — 그게 모드를 두는 이유입니다.
  final String? modeId;

  @override
  State<IntensityScreen> createState() => _IntensityScreenState();
}

class _IntensityScreenState extends State<IntensityScreen> {
  Map<String, Object?>? _cmp;
  String? _level;
  bool _busy = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_cmp != null) return;
    final app = Scope.of(context);
    final scans = app.store.sortedScans();
    if (scans.isEmpty) {
      setState(() => _busy = false);
      return;
    }
    final profile = app.profile ?? core.kSeedProfile;
    final modeDef = widget.modeId == null ? null : core.modeById(widget.modeId);
    final cmp = core.compareLevels(
      scans.last, profile, widget.goal,
      app.store.dayKey(),
      widget.goal['deadlineWeeks'],
      modeDef,
    );
    setState(() {
      _cmp = cmp;
      _level = '${cmp['recommended'] ?? 'mid'}';
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_busy) {
      return Scaffold(
        appBar: AppBar(title: const Text('기간 고르기')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final cmp = _cmp;
    if (cmp == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('기간 고르기')),
        body: const EmptyState(title: '먼저 인바디를 넣어야 합니다'),
      );
    }
    if (cmp['impossible'] == true) {
      return Scaffold(
        appBar: AppBar(title: const Text('기간 고르기')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          for (final w in (cmp['warnings'] as List)) Note(tone: Tone.bad, text: '$w'),
          const Note(
            text: '목표를 조금 낮추거나 마감을 늘리면 계산이 됩니다. '
                '거짓 날짜를 만들어 드리지는 않습니다.',
          ),
        ]),
      );
    }

    final results = (cmp['results'] as List).cast<Map<String, Object?>>();
    final c = mb(context);

    return Scaffold(
      appBar: AppBar(title: const Text('기간 고르기')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (cmp['spanNote'] != null)
          Note(text: '${(cmp['spanNote'] as Map)['text']}'),
        for (final w in ((cmp['warnings'] as List?) ?? const []))
          Note(tone: Tone.warn, text: '$w'),
        if (cmp['bottleneckNote'] != null)
          Note(
              title: '병목',
              text: ' ${(cmp['bottleneckNote'] as Map)['text']}'),

        for (final r in results) _LevelCard(
          r: r,
          selected: _level == r['level'],
          recommended: cmp['recommended'] == r['level'],
          onTap: () => setState(() => _level = '${r['level']}'),
        ),

        MbCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SectionTitle('주차별 궤적'),
            LineChart(
              height: 170,
              series: [
                Series(
                  label: '체지방',
                  color: c.fat,
                  dots: false,
                  points: _pts(_selected(results), 'bfmKg'),
                ),
                Series(
                  label: '골격근',
                  color: c.muscle,
                  dots: false,
                  points: _pts(_selected(results), 'smmKg'),
                ),
              ],
              goals: [
                GoalLine(y: core.jsToNumber(widget.goal['bfmKg']), color: c.fat, label: '목표 지방'),
                GoalLine(y: core.jsToNumber(widget.goal['smmKg']), color: c.muscle, label: '목표 근육'),
              ],
              xTickFmt: (v) => '${v.round()}주',
            ),
          ]),
        ),

        FilledButton(
          onPressed: _level == null ? null : () => _commit(cmp),
          child: const Text('이 계획으로 시작하기'),
        ),
      ]),
    );
  }

  Map<String, Object?> _selected(List<Map<String, Object?>> results) =>
      results.firstWhere((r) => r['level'] == _level, orElse: () => results.first);

  static List<Pt> _pts(Map<String, Object?> r, String key) {
    final traj = ((r['sim'] as Map)['trajectory'] as List).cast<Map<String, Object?>>();
    return [
      for (final t in traj)
        Pt(core.jsToNumber(t['week']), core.jsToNumber(t[key])),
    ];
  }

  void _commit(Map<String, Object?> cmp) {
    final app = Scope.of(context);
    final scans = app.store.sortedScans();
    final profile = app.profile ?? core.kSeedProfile;
    final plan = core.buildPlan(cmp, _level, scans.isEmpty ? null : scans.last, profile);
    if (plan == null) {
      toast(context, '계획을 만들지 못했습니다');
      return;
    }
    app.store.setGoal(widget.goal);
    app.store.setPlan(plan);
    if (!app.store.saved()) {
      toast(context, '기기에 저장하지 못했습니다 — 계획이 남지 않습니다');
      return;
    }
    Navigator.of(context)
      ..pop()
      ..pop();
    toast(context, '계획을 세웠습니다');
  }
}

class _LevelCard extends StatelessWidget {
  const _LevelCard({required this.r, required this.selected, required this.recommended,
      required this.onTap});
  final Map<String, Object?> r;
  final bool selected, recommended;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = mb(context);
    final feas = (r['feasibility'] as Map).cast<String, Object?>();
    final macros = (r['macros'] as Map).cast<String, Object?>();
    final sim = (r['sim'] as Map).cast<String, Object?>();
    final blocked = feas['verdict'] == 'blocked';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: t.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: selected ? t.colorScheme.primary : t.dividerColor,
            width: selected ? 2 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: blocked ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('${r['label']} · ${r['title']}',
                  style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(width: 8),
              if (recommended) const Pill('추천', tone: Tone.ok),
              const Spacer(),
              /* 코어가 보내는 ⛔🟢🟡🔴 를 글자로 안 찍습니다 — 우리 글꼴에
                 이모지가 없어서 구글에서 받아 오려 합니다. */
              VerdictDot(feas['verdict']),
            ]),
            const SizedBox(height: 6),
            Row(children: [
              DifficultyStars(core.jsToNumber(r['difficulty']).toInt()),
              const SizedBox(width: 6),
              Text(withoutStars(r['difficultyLabel']),
                  style: t.textTheme.labelSmall?.copyWith(color: t.hintColor)),
            ]),
            const SizedBox(height: 6),
            Text('${r['blurb']}',
                style: t.textTheme.bodySmall?.copyWith(color: t.hintColor, height: 1.5)),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: Stat(label: '기간', value: n0(r['weeks']), unit: '주')),
              Expanded(child: Stat(label: '목표일', value: dateK(r['targetDate']))),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: Stat(label: '섭취', value: n0(macros['intakeKcal']), unit: 'kcal')),
              Expanded(child: Stat(label: '단백질', value: n0(macros['proteinG']), unit: 'g')),
              Expanded(child: Stat(label: '운동', value: n0(r['daysPerWeek']), unit: '일/주')),
            ]),
            const SizedBox(height: 10),
            Text('${feas['message']}',
                style: t.textTheme.bodySmall?.copyWith(
                    color: blocked ? c.bad : t.hintColor, height: 1.5)),
            if (r['capWarning'] != null) ...[
              const SizedBox(height: 8),
              Text('${r['capWarning']}',
                  style: t.textTheme.labelSmall?.copyWith(color: c.warn, height: 1.5)),
            ],
            if (r['leanLossWarning'] != null) ...[
              const SizedBox(height: 6),
              Text('${r['leanLossWarning']}',
                  style: t.textTheme.labelSmall?.copyWith(color: c.warn, height: 1.5)),
            ],
            if (sim['alternative'] != null) ...[
              const SizedBox(height: 6),
              Text(
                  '다른 전략(${(sim['alternative'] as Map)['strategyLabel']})으로는 '
                  '${n0((sim['alternative'] as Map)['weeks'])}주입니다.',
                  style: t.textTheme.labelSmall?.copyWith(color: t.hintColor)),
            ],
          ]),
        ),
      ),
    );
  }
}
