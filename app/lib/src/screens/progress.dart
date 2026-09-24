/* =============================================================================
 * progress.dart — P09 추이
 *
 * **이 화면의 규칙 하나: 오차보다 작은 변화에는 퍼센트를 안 붙입니다.**
 *
 * 인바디가 실제로 재는 것은 체수분 하나뿐이고 나머지는 산수입니다.
 * 체수분이 1L 틀리면 제지방 1.37kg, 체지방 1.37kg(반대 부호)이 틀립니다 —
 * 물 한 병 분량입니다. 그래서 두 측정의 차이가 체중 ±1.0kg · 근육 ±0.6kg ·
 * 지방 ±1.0kg 안이면, 변했는지 아닌지 **이 두 번으로는 알 수 없습니다.**
 *
 * 그 자리에 숫자를 찍으면 사람은 그걸 믿고 행동을 바꿉니다. 별표를 달고
 * 흐리게 두는 편이 정직합니다.
 *
 * **그래프는 셋으로 나눕니다** — 체중 · 골격근 · 체지방률. 한 장에 체중(80대)과
 * 골격근(30대)을 같이 그리면 y축이 50kg 을 덮어서 1kg 변화가 선의 떨림으로
 * 보입니다. 체지방은 kg 대신 %로 그립니다 — 체중이 같이 빠질 때 kg 은 줄어도
 * 비율은 그대로일 수 있고, 사람이 궁금한 것은 뒤쪽입니다. kg 은 위 카드에 남습니다.
 *
 * **플랜의 예상 변화를 같은 그래프에 점선으로 얹습니다.** 0.2.9 를 써 본 뒤
 * "플랜의 예상 변화 그래프랑 중첩해서 비교가능하게 해줘" — 계획 탭의 궤적은 x 가
 * 주차라 측정 위에 놓을 수 없었습니다. 여기서는 시작일 + 주차×7일을 측정과 같은
 * "에포크 이후 일수" 로 바꿔 카드마다 그 항목의 계획선을 겹칩니다. 계획선은 목표일까지
 * 이어지므로 x축이 미래로 늘어납니다 — 그래야 "지금 어디쯤인가" 가 한눈에 보입니다.
 * ========================================================================== */
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:mybody_core/mybody_core.dart' as core;

import '../checkins.dart';
import '../scope.dart';
import '../ui/charts.dart';
import '../ui/fmt.dart';
import '../ui/widgets.dart';

class ProgressScreen extends StatelessWidget {
  const ProgressScreen({super.key, required this.go});
  final void Function(String route, [Object? arg]) go;

  @override
  Widget build(BuildContext context) {
    final app = Scope.of(context);
    final scans = app.store.sortedScans();
    if (scans.isEmpty) {
      return EmptyState(
        title: '아직 측정이 없습니다',
        detail: '인바디를 두 번 이상 넣으면 추이를 그립니다.',
        action: FilledButton(onPressed: () => go('upload'), child: const Text('인바디 올리기')),
      );
    }

    final profile = app.profile ?? core.kSeedProfile;
    final c = mb(context);
    final t = Theme.of(context);
    final derived = [for (final s in scans) core.derive(s, profile)];
    final times = [
      for (final s in scans)
        (DateTime.tryParse('${s['measuredAt']}')?.millisecondsSinceEpoch ?? 0) / 86400000.0
    ];

    /* 주간 체크인 체중 — 집 체중계 값이라 인바디 선과 따로 점선으로 둡니다.
       예전엔 체크인을 저장해도 여기 안 나왔습니다. */
    final checkinPts = [
      for (final c in checkinsOf(app.state))
        if (c['weightKg'] is num && DateTime.tryParse('${c['at']}') != null)
          Pt(DateTime.parse('${c['at']}').millisecondsSinceEpoch / 86400000.0,
              core.jsToNumber(c['weightKg'])),
    ];

    final goal = app.state['goal'] == null
        ? null
        : (app.state['goal'] as Map).cast<String, Object?>();

    /* 플랜의 예상 변화 — 카드마다 그 항목의 계획선을 점선으로. 세 카드가 같은 계획의
       같은 주차를 그리니 설명은 첫 카드에 한 줄이면 됩니다. */
    final plan = app.state['plan'] is Map
        ? (app.state['plan'] as Map).cast<String, Object?>()
        : null;
    final planWeight = _planSeries(plan, 'weightKg', c.weight);
    final planSmm = _planSeries(plan, 'smmKg', c.muscle);
    final planPbf = _planSeries(plan, 'pbfPct', c.fat);
    final hasPlanLine = planWeight != null || planSmm != null || planPbf != null;

    /* 체중 카드 밑의 설명은 짧게 — 예전 세 문장짜리는 그래프보다 글이 길었습니다.
       있는 선만 한 문장씩, 없으면 아무 말도 안 합니다. */
    final weightNote = [
      if (hasPlanLine) '「플랜」 점선은 계획의 예상 변화입니다.',
      if (checkinPts.isNotEmpty)
        '「체크인 체중」(점선)은 주간 체크인의 집 체중계 값 — 인바디와 0.5~1kg 다를 수 있어 잇지 않습니다.',
    ];

    final first = derived.first, last = derived.last;
    final noise = core.kNoise;

    return ListView(padding: const EdgeInsets.all(16), children: [
      if (scans.length < 2)
        const Note(
          text: '측정이 한 번뿐이라 아직 추세를 말할 수 없습니다. '
              '변화는 두 점 사이에서만 보입니다 — 4주 이상 간격을 두고 한 번 더 재세요.',
        )
      else
        MbCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SectionTitle('처음부터 지금까지',
                trailing: Text('${dateShort(scans.first['measuredAt'])} → ${dateShort(scans.last['measuredAt'])}',
                    style: t.textTheme.labelSmall?.copyWith(color: t.hintColor))),
            _DeltaRow(label: '체중', from: first['weightKg'], to: last['weightKg'],
                floor: core.jsToNumber(noise['weight']), color: c.weight),
            _DeltaRow(label: '골격근', from: first['smmKg'], to: last['smmKg'],
                floor: core.jsToNumber(noise['smm']), color: c.muscle),
            _DeltaRow(label: '체지방', from: first['bfmKg'], to: last['bfmKg'],
                floor: core.jsToNumber(noise['bfm']), color: c.fat),
            const SizedBox(height: 8),
            Text(
              '별표(*)는 두 측정의 차이가 인바디 오차 안이라는 뜻입니다. '
              '그 항목은 변했는지 아닌지 이 두 번의 측정으로는 알 수 없습니다.',
              style: t.textTheme.labelSmall?.copyWith(color: t.hintColor, height: 1.5),
            ),
          ]),
        ),

      _TrendCard(
        title: '체중', unit: 'kg', color: c.weight, times: times,
        values: [for (final d in derived) core.jsToNumber(d['weightKg'])],
        floor: core.jsToNumber(noise['weight']),
        /* 주간 체크인 체중 — 집 체중계 값이라 인바디 선과 따로 점선으로. */
        extra: checkinPts.isEmpty
            ? null
            : Series(label: '체크인 체중', color: c.weight, dashed: true, width: 1.2,
                points: checkinPts),
        plan: planWeight,
        goal: goal == null || !core.jsTruthy(goal['weightKg'])
            ? null
            : GoalLine(y: core.jsToNumber(goal['weightKg']), color: c.weight, label: '목표'),
        note: weightNote.isEmpty ? null : weightNote.join(' '),
      ),

      _TrendCard(
        title: '골격근', unit: 'kg', color: c.muscle, times: times,
        values: [for (final d in derived) core.jsToNumber(d['smmKg'])],
        floor: core.jsToNumber(noise['smm']),
        plan: planSmm,
        goal: goal == null || !core.jsTruthy(goal['smmKg'])
            ? null
            : GoalLine(y: core.jsToNumber(goal['smmKg']), color: c.muscle, label: '목표'),
      ),

      _TrendCard(
        title: '체지방률', unit: '%', color: c.fat, times: times,
        values: [for (final d in derived) core.jsToNumber(d['pbfPct'])],
        /* %의 오차 폭은 따로 없습니다 — 지방 ±1.0kg 을 지금 체중으로 나눈 값,
           같은 규칙의 다른 단위입니다. */
        floor: core.jsToNumber(noise['bfm']) / core.jsToNumber(last['weightKg']) * 100,
        plan: planPbf,
        /* 목표 체지방률은 목표 지방(kg) ÷ 목표 체중 — 목표 화면은 kg 으로만 받습니다. */
        goal: _goalPbf(goal) == null
            ? null
            : GoalLine(y: _goalPbf(goal)!, color: c.fat, label: '목표'),
      ),

      MbCard(
        onTap: () => go('history'),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('측정 기록 ${scans.length}건', style: t.textTheme.titleSmall),
              Text('하나하나 다시 보거나 지울 수 있습니다',
                  style: t.textTheme.labelSmall?.copyWith(color: t.hintColor)),
            ]),
          ),
          const Icon(LucideIcons.chevronRight),
        ]),
      ),
    ]);
  }
}

/// 목표 체지방률(%) — 목표에 지방 kg 과 체중이 둘 다 있을 때만.
double? _goalPbf(Map<String, Object?>? goal) {
  if (goal == null) return null;
  final w = core.jsToNumber(goal['weightKg']);
  final f = core.jsToNumber(goal['bfmKg']);
  if (!(w > 0) || !(f >= 0)) return null;
  return f / w * 100;
}

/// 플랜의 예상 변화를 그래프 점으로. x 는 시작일 + 주차×7일을 측정과 같은
/// "에포크 이후 일수" 로 — 계획 탭의 궤적은 x 가 주차라 측정 위에 못 얹었습니다.
/// y 는 궤적 칸 [key] ('weightKg' · 'smmKg' · 'pbfPct'). 숫자가 아닌 칸은 건너뜁니다 —
/// 오래된 플랜에 그 칸이 없다고 0 을 그리면 없는 추락을 보여 주게 됩니다.
/// week 칸이 없으면 코어(_trajWeek)처럼 자리 번호를 주차로 봅니다. 시작일이 없으면 빈 목록.
List<Pt> planSeriesPoints(Map<String, Object?> plan, String key) {
  final start = DateTime.tryParse('${plan['startDate']}');
  final traj = plan['trajectory'];
  if (start == null || traj is! List) return const [];
  final x0 = start.millisecondsSinceEpoch / 86400000.0;
  final out = <Pt>[];
  for (var i = 0; i < traj.length; i++) {
    final t = traj[i];
    if (t is! Map) continue;
    final wk = t['week'] is num ? (t['week'] as num).toDouble() : i.toDouble();
    final v = t[key];
    final y = v == null ? double.nan : core.jsToNumber(v);
    if (!wk.isFinite || !y.isFinite) continue;
    out.add(Pt(x0 + wk * 7, y));
  }
  return out;
}

/// 카드 하나의 플랜 점선. 점이 둘 미만이면 선이 안 되니 null — 범례에 「플랜」 만 남기지
/// 않습니다. 카드 색을 옅게(55%) 씁니다: 체중 카드에는 「체크인 체중」 점선이 같은 색으로
/// 이미 있어서, 같은 진하기면 그래프에서도 범례에서도 둘이 구분되지 않습니다.
/// 옅은 점선 = 예상, 진한 선 = 실제 — 세 카드가 같은 규칙입니다.
Series? _planSeries(Map<String, Object?>? plan, String key, Color color) {
  if (plan == null) return null;
  final pts = planSeriesPoints(plan, key);
  if (pts.length < 2) return null;
  return Series(label: '플랜', color: color.withValues(alpha: 0.55), dashed: true,
      dots: false, width: 1.4, points: pts);
}

String _dateTick(double v) =>
    dateShort(DateTime.fromMillisecondsSinceEpoch((v * 86400000).round()).toIso8601String());

/// 그래프 한 장. 제목 옆에 처음 → 지금과 그 차이 — 차이가 오차 안이면 별표(*).
/// 위 카드와 같은 규칙입니다. 그래프의 기울기만 보고 "빠졌다" 고 읽는 것을 막습니다.
class _TrendCard extends StatelessWidget {
  const _TrendCard({
    required this.title, required this.unit, required this.color,
    required this.times, required this.values, required this.floor,
    this.extra, this.plan, this.goal, this.note,
  });
  final String title, unit;
  final Color color;
  final List<double> times, values;
  final double floor;
  final Series? extra;
  /// 플랜의 예상 변화(점선). 측정 뒤로 목표일까지 이어지므로 x축이 미래까지 늘어납니다 —
  /// LineChart 가 모든 선의 x·y 로 범위를 잡으니 여기서 따로 할 일은 없습니다.
  final Series? plan;
  final GoalLine? goal;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final first = values.first, last = values.last;
    final d = last - first;
    final under = d.abs() < floor;
    final trailing = values.length < 2
        ? '${n1(last)} $unit'
        : '${n1(first)} → ${n1(last)} $unit · ${signed(d)}${under ? '*' : ''}';
    return MbCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionTitle(title,
            trailing: Text(trailing,
                style: t.textTheme.labelSmall?.copyWith(color: t.hintColor))),
        LineChart(
          height: 150,
          /* 범례는 선이 둘 이상일 때만 — 하나뿐이면 제목이 범례입니다. */
          legend: extra != null || plan != null,
          series: [
            Series(label: title, color: color,
                points: [for (var i = 0; i < values.length; i++) Pt(times[i], values[i])]),
            if (extra != null) extra!,
            if (plan != null) plan!,
          ],
          goals: [if (goal != null) goal!],
          xTickFmt: _dateTick,
        ),
        if (note != null) ...[
          const SizedBox(height: 6),
          Text(note!, style: t.textTheme.labelSmall?.copyWith(color: t.hintColor, height: 1.5)),
        ],
      ]),
    );
  }
}

class _DeltaRow extends StatelessWidget {
  const _DeltaRow({required this.label, required this.from, required this.to,
      required this.floor, required this.color});
  final String label;
  final Object? from, to;
  final double floor;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final d = core.jsToNumber(to) - core.jsToNumber(from);
    /* 오차 안이면 흐리게 + 별표. 숫자는 지우지 않습니다 — 지우면
       "안 쟀다" 가 되고, 그건 사실이 아닙니다. */
    final under = d.abs() < floor;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        SizedBox(width: 54,
            child: Text(label, style: t.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600))),
        Expanded(
          child: Text('${n1(from)} → ${n1(to)} kg',
              style: t.textTheme.bodySmall?.copyWith(color: t.hintColor)),
        ),
        Text('${signed(d)}${under ? '*' : ''}',
            style: t.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: under ? t.hintColor : color)),
      ]),
    );
  }
}
