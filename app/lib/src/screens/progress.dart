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

      MbCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SectionTitle('체중 · 골격근 · 체지방'),
          LineChart(
            height: 180,
            series: [
              Series(label: '체중', color: c.weight,
                  points: [for (var i = 0; i < derived.length; i++)
                    Pt(times[i], core.jsToNumber(derived[i]['weightKg']))]),
              Series(label: '골격근', color: c.muscle,
                  points: [for (var i = 0; i < derived.length; i++)
                    Pt(times[i], core.jsToNumber(derived[i]['smmKg']))]),
              Series(label: '체지방', color: c.fat,
                  points: [for (var i = 0; i < derived.length; i++)
                    Pt(times[i], core.jsToNumber(derived[i]['bfmKg']))]),
              if (checkinPts.isNotEmpty)
                Series(label: '체크인 체중', color: c.weight, dashed: true, width: 1.2,
                    points: checkinPts),
            ],
            goals: [
              if (goal != null)
                GoalLine(y: core.jsToNumber(goal['bfmKg']), color: c.fat, label: '목표 지방'),
              if (goal != null)
                GoalLine(y: core.jsToNumber(goal['smmKg']), color: c.muscle, label: '목표 근육'),
            ],
            xTickFmt: (v) => dateShort(
                DateTime.fromMillisecondsSinceEpoch((v * 86400000).round()).toIso8601String()),
          ),
          if (checkinPts.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('점선은 주간 체크인에 넣은 집 체중계 값입니다. 인바디와 0.5~1kg 다를 수 있어서 '
                '인바디 선과 잇지 않습니다.',
                style: t.textTheme.labelSmall?.copyWith(color: t.hintColor, height: 1.5)),
          ],
        ]),
      ),

      MbCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SectionTitle('체지방률'),
          LineChart(
            height: 130,
            legend: false,
            series: [
              Series(label: '체지방률', color: c.fat,
                  points: [for (var i = 0; i < derived.length; i++)
                    Pt(times[i], core.jsToNumber(derived[i]['pbfPct']))]),
            ],
            xTickFmt: (v) => dateShort(
                DateTime.fromMillisecondsSinceEpoch((v * 86400000).round()).toIso8601String()),
          ),
        ]),
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
