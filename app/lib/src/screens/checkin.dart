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
 *
 * **판정은 흔들림보다 커야 합니다.** 예전엔 이번 주 체중 하나를 계획선에 대
 * 보고 0.15kg 만 달라도 "빠릅니다 · 하루 150kcal 늘리기" 를 냈습니다 — 계획
 * 다음 날 집 체중계 값이 인바디와 0.5kg 다르다는 이유로요. 지금은 코어의
 * checkinReview 가: 첫 체크인은 기준점(판정 없음), 그 뒤 **변화량**을 계획선과
 * 견줘 ±0.5kg 안이면 계획대로, 한 번 벗어나면 지켜봄, 두 번 연속일 때만
 * 조정을 제안합니다. 그때만 「저장하고 제안 적용」이 나옵니다.
 *
 * 저장한 체크인이 어디에 쓰이는가: 다음 판정(기준점 · 연속 여부), 이 화면의
 * 그래프와 「지난 체크인」, 홈 「이번 주 체크인」의 완료 표시, 추이 탭 체중
 * 그래프의 점, 친구에게 보이는 「이번 주 기록」. 조정을 적용하면 계획의
 * 하루 칼로리(plan.macros)가 바뀌어 식단 탭 목표 · 플랜 탭에 바로 반영됩니다.
 * ========================================================================== */
import 'package:flutter/material.dart';
import 'package:mybody_core/mybody_core.dart' as core;

import '../adherence.dart';
import '../checkins.dart';
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

  /// 계획선에서 그 주에 가장 가까운 점의 체중 (코어의 판정과 같은 방식).
  static double _expectedAt(List<Map<String, Object?>> traj, int wk) {
    double? best;
    var bestD = double.infinity;
    for (var i = 0; i < traj.length; i++) {
      final w = traj[i]['week'] is num ? traj[i]['week'] as num : i;
      final d = (w - wk).abs().toDouble();
      if (d < bestD) {
        bestD = d;
        best = core.jsToNumber(traj[i]['weightKg']);
      }
    }
    return best ?? double.nan;
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
    final weeksIn = core.planWeekOf(startDate, app.store.dayKey());
    final expected = traj.isEmpty ? double.nan : _expectedAt(traj, weeksIn);
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

    /* 판정 — 이번 계획의 체크인들 + 지금 넣는 값. 코어가 주별로 모으고,
       첫 체크인(또는 마지막 조정)을 기준점으로 변화량을 계획선과 견줍니다. */
    final past = readingsFor(app.store, plan);
    final thisWeek = checkinThisWeek(app.store);
    final review = actual == null
        ? null
        : core.checkinReview(
            plan,
            [...past, {'week': weeksIn, 'weightKg': actual, 'at': DateTime.now().toUtc().toIso8601String()}],
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
            if (thisWeek != null) ...[
              const SizedBox(height: 8),
              Note(
                text: '이번 주에 이미 체크인했습니다 (${dateShort(thisWeek['at'])} · '
                    '${n1(thisWeek['weightKg'])}kg). 다시 저장하면 이번 주 값이 새 값으로 바뀝니다.',
              ),
            ],
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
              const SectionTitle('계획선과 체크인'),
              LineChart(
                height: 150,
                series: [
                  Series(label: '계획', color: t.colorScheme.primary, dots: false,
                      points: [for (var i = 0; i < traj.length; i++)
                        Pt((traj[i]['week'] is num ? traj[i]['week'] as num : i).toDouble(),
                            core.jsToNumber(traj[i]['weightKg']))]),
                  if (past.any((r) => r['weightKg'] is num))
                    Series(label: '체크인', color: c.weight,
                        points: [for (final r in past)
                          if (r['weightKg'] is num)
                            Pt(core.jsToNumber(r['week']), core.jsToNumber(r['weightKg']))]),
                  if (actual != null)
                    Series(label: '지금', color: c.fat,
                        points: [Pt(weeksIn.toDouble(), actual)]),
                ],
                markers: [Marker(x: weeksIn.toDouble(), label: '지금')],
                xTickFmt: (v) => '${v.round()}주',
              ),
              const SizedBox(height: 6),
              Text('점은 집 체중계로 넣은 체크인입니다. 인바디와 0.5~1kg 다를 수 있어서, '
                  '판정은 계획선과의 거리가 아니라 첫 체크인 이후의 변화로 합니다.',
                  style: hint),
            ]),
          ),

        if (review != null)
          _AdviceCard(
            review: review,
            caveat: dietPct == null &&
                    core.jsTruthy(ex['hasTarget']) &&
                    review['status'] != 'early'
                ? '식단 기록이 ${n0(logged)}일뿐이라 실행 여부는 반영하지 못했습니다. 체중만 보고 낸 판정입니다.'
                : null,
          ),

        if (review != null && review['apply'] is Map) ...[
          FilledButton(
            onPressed: () => _saveAndApply(app, actual!, ex, review, weeksIn),
            child: const Text('저장하고 제안 적용'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => _save(app, actual!, ex, review),
            child: const Text('저장만 하기 — 계획은 그대로'),
          ),
        ] else
          FilledButton(
            onPressed: actual == null ? null : () => _save(app, actual, ex, review),
            child: const Text('체크인 저장'),
          ),

        const SizedBox(height: 12),
        _PastCard(list: checkinsOf(st)),
      ]),
    );
  }

  Map<String, Object?> _entry(String at, double actual, Map<String, Object?> ex,
          Map<String, Object?>? review, bool applied) =>
      {
        'at': at,
        'weightKg': actual,
        /* 기록에서 센 값입니다. 없으면 null — 0 이 아닙니다. */
        'workoutPct': ex['workoutPct'],
        'dietPct': ex['dietPct'],
        'derived': true,
        'status': review?['status'],
        'devKg': review?['devKg'],
        'applied': applied,
      };

  void _save(app, double actual, Map<String, Object?> ex, Map<String, Object?>? review) {
    final list = [...((app.state['checkins'] as List?) ?? const [])];
    list.add(_entry(DateTime.now().toUtc().toIso8601String(), actual, ex, review, false));
    app.store.set({'checkins': list});
    if (!app.store.saved()) {
      toast(context, '기기에 저장하지 못했습니다 — 체크인이 남지 않습니다');
      return;
    }
    Navigator.of(context).pop();
    toast(context, '체크인을 저장했습니다');
  }

  /* 「제안 적용」 — 두 번 연속 같은 쪽으로 벗어났을 때만 나옵니다.
     무엇이 어떻게 바뀌는지 숫자로 보여 주고 한 번 더 묻습니다. 체크인과
     조정은 **같은 시각**으로 남깁니다 — 코어가 그 체크인을 새 기준점으로
     잡아서, 조정한 다음 주에 같은 차이로 또 줄이라는 말이 안 나옵니다. */
  Future<void> _saveAndApply(app, double actual, Map<String, Object?> ex,
      Map<String, Object?> review, int weeksIn) async {
    final plan = (app.state['plan'] as Map).cast<String, Object?>();
    final at = DateTime.now().toUtc().toIso8601String();
    final res = core.applyCheckinAdvice(
        plan, review, app.profile ?? core.kSeedProfile, weeksIn, at);
    if (res == null) {
      _save(app, actual, ex, review);
      return;
    }
    final before = (plan['macros'] as Map).cast<String, Object?>();
    final after = ((res['plan'] as Map)['macros'] as Map).cast<String, Object?>();
    final kcal = core.jsToNumber(res['kcalDelta']);
    final cardio = core.jsToNumber(res['cardioMinDelta']);
    final w0 = plan['workout'] is Map ? (plan['workout'] as Map)['cardioMinPerWeek'] : null;
    final lines = [
      if (kcal != 0) '하루 ${n0(before['intakeKcal'])} → ${n0(after['intakeKcal'])}kcal (탄수화물로 맞춥니다)',
      if (cardio != 0) '유산소 주 ${n0(w0 ?? 0)} → ${n0(core.jsToNumber(w0 ?? 0) + cardio)}분',
      if (res['floored'] == true)
        kcal == 0
            ? '이미 하루 하한에 닿아 칼로리는 더 줄이지 않습니다.'
            : '하루 하한 때문에 ${n0(kcal.abs())}kcal 만 줄입니다.',
    ];
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('계획을 이렇게 바꿀까요?'),
        content: Text([
          ...lines,
          '',
          '다음 체크인부터는 오늘 값을 새 기준으로 다시 봅니다.',
        ].join('\n')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('그대로 두기')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('적용')),
        ],
      ),
    );
    if (yes != true || !mounted) return;

    final list = [...((app.state['checkins'] as List?) ?? const [])];
    list.add(_entry(at, actual, ex, review, true));
    app.store.set({'checkins': list});
    app.store.setPlan((res['plan'] as Map).cast<String, Object?>());
    if (!app.store.saved()) {
      toast(context, '기기에 저장하지 못했습니다 — 체크인과 조정이 남지 않습니다');
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop();
    toast(context, '체크인을 저장하고 계획을 바꿨습니다 · 하루 ${n0(after['intakeKcal'])}kcal');
  }
}

class _AdviceCard extends StatelessWidget {
  const _AdviceCard({required this.review, this.caveat});
  final Map<String, Object?> review;
  final String? caveat;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final status = '${review['status']}';
    final tone = switch (status) {
      'onTrack' => Tone.ok,
      'slow' || 'fast' => Tone.warn,
      _ => Tone.none,
    };
    final dev = review['devKg'];
    /* 기준점 이후 계획보다 얼마나 — devKg 는 + 가 느림입니다. */
    final devText = dev is num && status != 'adherence'
        ? (dev.abs() < 0.05
            ? '첫 체크인 이후 계획선과 거의 같습니다.'
            : '첫 체크인 이후 계획보다 ${n1(dev.abs())}kg ${dev > 0 ? '느립니다' : '빠릅니다'} '
                '(±0.5kg 까지는 흔들림으로 봅니다).')
        : null;
    return MbCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionTitle('이번 주 제안', trailing: Pill(checkinStatusLabel(status), tone: tone)),
        if (devText != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(devText, style: t.textTheme.bodySmall?.copyWith(height: 1.5)),
          ),
        for (final s0 in ((review['suggestions'] as List?) ?? const []))
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

/* --- 지난 체크인 ---------------------------------------------------------------
   예전엔 저장하고 나면 어디에도 안 보였습니다. 최근 다섯 개를 판정과 함께. */
class _PastCard extends StatelessWidget {
  const _PastCard({required this.list});
  final List<Map<String, Object?>> list;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final recent = list.reversed.take(5).toList();
    return MbCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionTitle('지난 체크인',
            trailing: Text(list.isEmpty ? '' : '최근 ${recent.length}건',
                style: t.textTheme.labelSmall?.copyWith(color: t.hintColor))),
        if (recent.isEmpty)
          Text('아직 없습니다. 주 1회 같은 조건(아침 공복)으로 재면 둘째 주부터 판정이 나옵니다.',
              style: t.textTheme.bodySmall?.copyWith(color: t.hintColor, height: 1.5))
        else
          for (final c in recent)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                Expanded(child: Text(dateShort(c['at']), style: t.textTheme.bodySmall)),
                Text(c['weightKg'] is num ? '${n1(c['weightKg'])}kg' : '—',
                    style: t.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(width: 12),
                SizedBox(
                  width: 110,
                  child: Text(
                    [
                      checkinStatusLabel(c['status']),
                      if (c['applied'] == true) '조정함',
                    ].where((x) => x.isNotEmpty).join(' · '),
                    textAlign: TextAlign.right,
                    style: t.textTheme.labelSmall?.copyWith(color: t.hintColor),
                  ),
                ),
              ]),
            ),
      ]),
    );
  }
}
