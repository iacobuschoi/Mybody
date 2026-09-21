/* =============================================================================
 * checkin.dart — P08 주간 체크인
 *
 * 한 주에 한 번, 계획이 맞게 가고 있는지 맞춰 봅니다.
 *
 * **이 화면이 묻는 것은 몸무게만이 아닙니다.** 얼마나 지켰는지도 같이
 * 묻습니다 — 안 지킨 주에 "계획이 틀렸다" 고 판단해서 칼로리를 더 깎으면
 * 실제로 사람을 굶기게 되기 때문입니다. 순응도가 낮으면 엔진은 계획을
 * 건드리지 말라고 답합니다. 그게 맞는 답입니다.
 * ========================================================================== */
import 'package:flutter/material.dart';
import 'package:mybody_core/mybody_core.dart' as core;

import '../scope.dart';
import '../ui/charts.dart';
import '../ui/fmt.dart';
import '../ui/widgets.dart';

/* 식단 준수도 — 상/중/하를 숫자로 바꿔 엔진에 넘깁니다. */
const _dietLevels = [
  (key: 'high', label: '상', pct: 90, desc: '거의 계획대로 먹었다'),
  (key: 'mid', label: '중', pct: 70, desc: '절반 이상은 지켰다'),
  (key: 'low', label: '하', pct: 45, desc: '거의 못 지켰다'),
];

const _conditions = [
  (key: 'good', label: '좋음', desc: '잘 잤고 몸이 가볍다'),
  (key: 'normal', label: '보통', desc: '평소와 비슷하다'),
  (key: 'bad', label: '나쁨', desc: '수면 부족 · 피로 누적'),
];

class CheckinScreen extends StatefulWidget {
  const CheckinScreen({super.key});
  @override
  State<CheckinScreen> createState() => _CheckinScreenState();
}

class _CheckinScreenState extends State<CheckinScreen> {
  final _weight = TextEditingController();
  final _memo = TextEditingController();
  double _workoutPct = 70;
  String _dietKey = 'mid';
  String _condition = 'normal';

  @override
  void dispose() {
    _weight.dispose();
    _memo.dispose();
    super.dispose();
  }

  int get _dietPct => _dietLevels.firstWhere((d) => d.key == _dietKey).pct;

  @override
  Widget build(BuildContext context) {
    final app = Scope.of(context);
    final st = app.state;
    final t = Theme.of(context);
    final c = mb(context);

    if (st['plan'] == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('주간 체크인')),
        body: const EmptyState(
          title: '아직 계획이 없습니다',
          detail: '체크인은 계획 대비 어디쯤인지를 보는 자리라, 먼저 목표를 정해야 합니다.',
        ),
      );
    }

    final plan = (st['plan'] as Map).cast<String, Object?>();
    final traj = ((plan['trajectory'] as List?) ?? const []).cast<Map<String, Object?>>();
    final startDate = '${plan['startDate']}';
    final weeksIn = _weeksSince(startDate, app.store.dayKey());
    final at = weeksIn.clamp(0, traj.isEmpty ? 0 : traj.length - 1).toInt();
    final expected = traj.isEmpty ? double.nan : core.jsToNumber(traj[at]['weightKg']);
    final prevW = (at > 0 && traj.isNotEmpty)
        ? core.jsToNumber(traj[at - 1]['weightKg'])
        : expected;
    final actual = double.tryParse(_weight.text.trim());

    final advice = actual == null
        ? null
        : core.checkinAdvice(
            plan,
            {'weightKg': expected, 'prevWeightKg': prevW},
            {'weightKg': actual},
            {'dietPct': _dietPct},
          );

    return Scaffold(
      appBar: AppBar(title: const Text('주간 체크인')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        MbCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SectionTitle('계획 ${n0(weeksIn)}주차',
                trailing: Text('시작 ${dateK(startDate)}',
                    style: t.textTheme.labelSmall?.copyWith(color: t.hintColor))),
            Text('계획상 이번 주 체중은 ${n1(expected)}kg 입니다.',
                style: t.textTheme.bodySmall),
            const SizedBox(height: 14),
            TextField(
              controller: _weight,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: '지금 체중',
                suffixText: 'kg',
                border: OutlineInputBorder(),
                helperText: '아침 공복, 화장실 다녀와서 잰 값이 가장 덜 흔들립니다',
                helperMaxLines: 2,
              ),
            ),
          ]),
        ),

        MbCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SectionTitle('얼마나 지켰나'),
            Text(
              /* 솔직하게 답하는 편이 이득이라는 것을 먼저 말합니다 —
                 안 그러면 사람은 잘 보이려고 높게 찍고, 그러면 앱이
                 "계획이 틀렸다" 고 판단해 칼로리를 더 깎습니다. */
              '낮게 적어도 혼나지 않습니다. 오히려 덜 지킨 주에 칼로리를 더 깎으면 '
              '굶게 되기 때문에, 앱은 그때 계획을 그대로 두라고 답합니다.',
              style: t.textTheme.labelSmall?.copyWith(color: t.hintColor, height: 1.5),
            ),
            const SizedBox(height: 14),
            Text('운동 ${n0(_workoutPct)}%', style: t.textTheme.bodySmall),
            Slider(
              value: _workoutPct, min: 0, max: 100, divisions: 20,
              label: '${_workoutPct.round()}%',
              onChanged: (v) => setState(() => _workoutPct = v),
            ),
            const SizedBox(height: 6),
            Text('식단', style: t.textTheme.bodySmall),
            const SizedBox(height: 6),
            for (final d in _dietLevels)
              RadioGroup<String>(
                groupValue: _dietKey,
                onChanged: (v) => setState(() => _dietKey = v ?? _dietKey),
                child: RadioListTile<String>(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: d.key,
                  title: Text('${d.label} — ${d.desc}', style: t.textTheme.bodySmall),
                ),
              ),
            const SizedBox(height: 6),
            Text('컨디션', style: t.textTheme.bodySmall),
            const SizedBox(height: 6),
            Wrap(spacing: 8, children: [
              for (final cd in _conditions)
                ChoiceChip(
                  label: Text(cd.label),
                  selected: _condition == cd.key,
                  onSelected: (_) => setState(() => _condition = cd.key),
                ),
            ]),
            const SizedBox(height: 12),
            TextField(
              controller: _memo,
              maxLines: 2,
              decoration: const InputDecoration(
                  labelText: '메모 (선택)', border: OutlineInputBorder()),
            ),
          ]),
        ),

        if (traj.length > 1)
          MbCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SectionTitle('계획선과 지금'),
              LineChart(
                height: 150,
                legend: false,
                series: [
                  Series(label: '계획', color: t.colorScheme.primary, dots: false,
                      points: [for (final x in traj)
                        Pt(core.jsToNumber(x['week']), core.jsToNumber(x['weightKg']))]),
                  if (actual != null)
                    Series(label: '지금', color: c.fat,
                        points: [Pt(weeksIn.toDouble(), actual)]),
                ],
                markers: [Marker(x: weeksIn.toDouble(), label: '지금')],
                xTickFmt: (v) => '${v.round()}주',
              ),
            ]),
          ),

        if (advice != null) _AdviceCard(advice: advice),

        FilledButton(
          onPressed: actual == null ? null : () => _save(app, actual),
          child: const Text('체크인 저장'),
        ),
      ]),
    );
  }

  void _save(app, double actual) {
    final list = [...((app.state['checkins'] as List?) ?? const [])];
    list.add({
      'at': DateTime.now().toUtc().toIso8601String(),
      'weightKg': actual,
      'workoutPct': _workoutPct.round(),
      'dietPct': _dietPct,
      'condition': _condition,
      'memo': _memo.text.trim(),
    });
    app.store.set({'checkins': list});
    if (!app.store.saved()) {
      toast(context, '기기에 저장하지 못했습니다 — 체크인이 남지 않습니다');
      return;
    }
    Navigator.of(context).pop();
    toast(context, '체크인을 저장했습니다');
  }

  static int _weeksSince(String startISO, String todayKey) {
    final a = DateTime.tryParse('${startISO}T00:00:00');
    final b = DateTime.tryParse('${todayKey}T00:00:00');
    if (a == null || b == null) return 0;
    final d = b.difference(a).inDays;
    return d <= 0 ? 0 : (d / 7).floor();
  }
}

class _AdviceCard extends StatelessWidget {
  const _AdviceCard({required this.advice});
  final Map<String, Object?> advice;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final (label, tone) = switch ('${advice['status']}') {
      'onTrack' => ('계획대로', Tone.ok),
      'slow' => ('덜 빠졌습니다', Tone.warn),
      'fast' => ('빠릅니다', Tone.warn),
      'adherence' => ('실행이 덜 됐습니다', Tone.none),
      _ => ('', Tone.none),
    };
    return MbCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionTitle('이번 주 제안', trailing: Pill(label, tone: tone)),
        for (final s0 in ((advice['suggestions'] as List?) ?? const []))
          Builder(builder: (_) {
            final s = (s0 as Map).cast<String, Object?>();
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${s['title']}',
                    style: t.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                Text('${s['detail']}',
                    style: t.textTheme.bodySmall?.copyWith(color: t.hintColor, height: 1.5)),
              ]),
            );
          }),
      ]),
    );
  }
}
