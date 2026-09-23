/* =============================================================================
 * checkin.dart — P08 주간 체크인
 *
 * 한 주에 한 번, 계획이 맞게 가고 있는지 맞춰 봅니다.
 *
 * **이 화면이 보는 것은 몸무게만이 아닙니다.** 얼마나 지켰는지도 같이
 * 봅니다 — 안 지킨 주에 "계획이 틀렸다" 고 판단해서 칼로리를 더 깎으면
 * 실제로 사람을 굶기게 되기 때문입니다. 순응도가 낮으면 엔진은 계획을
 * 건드리지 말라고 답합니다. 그게 맞는 답입니다.
 *
 * 예전에는 그걸 여기서 슬라이더로 물었습니다. 지금은 **안 묻습니다** —
 * 운동은 홈에서 매일 체크하고 식단은 끼니마다 적으니, 거기서 셉니다
 * (../adherence.dart, 플랜 탭의 「달성률」 과 같은 숫자). 잘 보이려고
 * 높게 찍을 일도, 같은 걸 두 번 적을 일도 없습니다. 식단 기록이 3일이
 * 안 되면 "모른다" 고 두고 체중만으로 봅니다.
 * ========================================================================== */
import 'package:flutter/material.dart';
import 'package:mybody_core/mybody_core.dart' as core;

import '../adherence.dart';
import '../scope.dart';
import '../ui/charts.dart';
import '../ui/fmt.dart';
import '../ui/widgets.dart';

class CheckinScreen extends StatefulWidget {
  const CheckinScreen({super.key});
  @override
  State<CheckinScreen> createState() => _CheckinScreenState();
}

class _CheckinScreenState extends State<CheckinScreen> {
  final _weight = TextEditingController();

  @override
  void dispose() {
    _weight.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = Scope.of(context);
    final st = app.state;
    final t = Theme.of(context);
    final c = mb(context);
    final hint = t.textTheme.labelSmall?.copyWith(color: t.hintColor, height: 1.5);

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

    /* 지난 7일 실행 — 기록에서 셉니다. */
    final ex = weekExecution(app.store);
    final workoutPct = ex['workoutPct'];
    final dietPct = ex['dietPct'];
    final planned = core.jsToNumber(ex['plannedDays']);
    final kept = core.jsToNumber(ex['keptDays']);
    final missed = core.jsToNumber(ex['missedDays']);
    final logged = core.jsToNumber(ex['loggedDays']);
    final inBand = core.jsToNumber(ex['inBandDays']);

    final advice = actual == null
        ? null
        : core.checkinAdvice(
            plan,
            {'weightKg': expected, 'prevWeightKg': prevW},
            {'weightKg': actual},
            dietPct == null ? null : {'dietPct': dietPct},
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
            const SizedBox(height: 16),
            Text('지난 7일 실행', style: t.textTheme.bodySmall),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(
                child: Stat(
                  label: '운동',
                  value: planned == 0 ? '일정 없음' : '${n0(kept)}/${n0(kept + missed)}일',
                  delta: workoutPct == null
                      ? (planned == 0 ? '홈에서 요일을 켜면 셉니다' : '오늘만 남음')
                      : '${n0(workoutPct)}%',
                  color: workoutPct == null ? null : (core.jsToNumber(workoutPct) >= 70 ? c.ok : c.warn),
                ),
              ),
              Expanded(
                child: Stat(
                  label: '식단',
                  value: logged == 0 ? '기록 없음' : '${n0(inBand)}/${n0(logged)}일',
                  delta: dietPct == null
                      ? (core.jsTruthy(ex['hasTarget'])
                          ? '기록 ${n0(logged)}일 — ${n0(ex['minLoggedDays'])}일은 있어야 봅니다'
                          : '하루 목표가 없습니다')
                      : '${n0(dietPct)}% 범위 안',
                  color: dietPct == null ? null : (core.jsToNumber(dietPct) >= 70 ? c.ok : c.warn),
                ),
              ),
            ]),
            const SizedBox(height: 6),
            Text(
                /* 왜 안 묻는지를 한 줄로. 낮게 나와도 혼나지 않는다는 말은
                   그대로 둡니다 — 덜 지킨 주에 칼로리를 더 깎으면 굶게 되므로
                   앱은 그때 계획을 그대로 두라고 답합니다. */
                '홈의 운동 체크와 식단 기록에서 셉니다 (플랜 탭 「달성률」 과 같은 숫자). '
                '낮아도 혼나지 않습니다 — 덜 지킨 주에 칼로리를 더 깎으면 굶게 되기 때문에, '
                '앱은 그때 계획을 그대로 두라고 답합니다.',
                style: hint),
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

        if (advice != null)
          _AdviceCard(
            advice: advice,
            caveat: dietPct == null && core.jsTruthy(ex['hasTarget'])
                ? '식단 기록이 ${n0(logged)}일뿐이라 실행 여부는 반영하지 못했습니다. 체중만 보고 낸 제안입니다.'
                : null,
          ),

        FilledButton(
          onPressed: actual == null ? null : () => _save(app, actual, ex),
          child: const Text('체크인 저장'),
        ),
      ]),
    );
  }

  void _save(app, double actual, Map<String, Object?> ex) {
    final list = [...((app.state['checkins'] as List?) ?? const [])];
    list.add({
      'at': DateTime.now().toUtc().toIso8601String(),
      'weightKg': actual,
      /* 기록에서 센 값입니다. 없으면 null — 0 이 아닙니다. */
      'workoutPct': ex['workoutPct'],
      'dietPct': ex['dietPct'],
      'derived': true,
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
  const _AdviceCard({required this.advice, this.caveat});
  final Map<String, Object?> advice;
  final String? caveat;

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
        if (caveat != null)
          Text(caveat!, style: t.textTheme.labelSmall?.copyWith(color: t.hintColor, height: 1.5)),
      ]),
    );
  }
}
