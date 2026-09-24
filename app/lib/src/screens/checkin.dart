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
 * checkinReview 가: 체크인마다 그날 자리의 계획선과의 차이를 구해 **추세**를 맞추고,
 * 3주 이상 · 4번 이상에서 추세가 1kg 넘게 · 흔들림보다 확실하게 벗어나는 일이 두 번
 * 연속일 때만 조정을 제안합니다(한 번이면 지켜봄). 추세는 지금 단계(감량 · 유지 ·
 * 증량) 안에서만 봅니다. 그때만 「저장하고 제안 적용」이 나옵니다.
 *
 * 저장한 체크인이 어디에 쓰이는가: 다음 판정(기준점 · 연속 여부), 이 화면의
 * 그래프와 「지난 체크인」, 홈 「이번 주 체크인」의 완료 표시, 추이 탭 체중
 * 그래프의 점, 친구에게 보이는 「이번 주 기록」. 조정을 적용하면 계획의
 * 하루 칼로리(plan.macros)가 바뀌어 식단 탭 목표 · 플랜 탭에 바로 반영됩니다.
 * ========================================================================== */
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
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
    final todayDay = core.planDayOf(startDate, app.store.dayKey());
    final weeksIn = (todayDay / 7).floor();
    /* 계획선은 판정과 같은 자리(오늘)에서 읽습니다. */
    final expected = core.planWeightAt(plan, todayDay) ?? double.nan;
    final typed = double.tryParse(_weight.text.trim());
    /* 소수점을 빠뜨린 862 같은 값은 기준점으로 들어가면 그 뒤 판정이 다 틀어집니다. */
    final problem = checkinWeightProblem(app.store, typed);
    final actual = problem == null ? typed : null;

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
            [
              ...past,
              {'week': weeksIn, 'day': todayDay, 'weightKg': actual,
               'at': DateTime.now().toUtc().toIso8601String()},
            ],
            dietPct == null ? null : {'dietPct': dietPct},
          );
    /* 적용하면 실제로 무엇이 바뀌는지 — 하한에 막히면 −150 이 아닐 수 있고,
       운동 계획이 없으면 유산소는 안 더해집니다. 버튼을 누르기 전에 보여 줍니다. */
    final preview = review != null && review['apply'] is Map
        ? core.applyCheckinAdvice(plan, review, app.profile ?? core.kSeedProfile, weeksIn, 'preview')
        : null;
    final canApply = preview != null &&
        (core.jsToNumber(preview['kcalDelta']) != 0 || core.jsToNumber(preview['cardioMinDelta']) != 0);

    return Scaffold(
      appBar: AppBar(title: const Text('주간 체크인')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        MbCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SectionTitle('계획 ${n0(weeksIn + 1)}주차',
                trailing: Text('시작 ${dateK(startDate)}',
                    style: t.textTheme.labelSmall?.copyWith(color: t.hintColor))),
            Text('계획상 오늘 체중은 ${n1(expected)}kg 입니다.',
                style: t.textTheme.bodySmall),
            if (thisWeek != null) ...[
              const SizedBox(height: 8),
              Note(
                text: '이번 주에 이미 체크인했습니다 (${dateShort(thisWeek['at'])} · '
                    '${n1(thisWeek['weightKg'])}kg). '
                    '${_sameWeek(app) != null ? '다시 저장하면 이번 주 값을 새 값으로 바꿉니다.' : '5일 안이라 판정에는 새 값만 씁니다.'}',
              ),
            ],
            const SizedBox(height: 14),
            TextField(
              controller: _weight,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: '지금 체중',
                suffixText: 'kg',
                border: const OutlineInputBorder(),
                helperText: '아침 공복, 화장실 다녀와서 잰 값이 가장 덜 흔들립니다',
                helperMaxLines: 2,
                errorText: problem,
                errorMaxLines: 2,
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
                  /* 점은 판정이 계획선을 읽는 자리(그날)에 찍습니다. */
                  if (past.any((r) => r['weightKg'] is num))
                    Series(label: '체크인', color: c.weight,
                        points: [for (final r in past)
                          if (r['weightKg'] is num)
                            Pt(core.jsToNumber(r['day']) / 7, core.jsToNumber(r['weightKg']))]),
                  if (actual != null)
                    Series(label: '지금', color: c.fat,
                        points: [Pt(todayDay / 7, actual)]),
                ],
                markers: [Marker(x: todayDay / 7, label: '지금')],
                xTickFmt: (v) => '${v.round()}주',
              ),
              const SizedBox(height: 6),
              Text('점은 집 체중계로 넣은 체크인입니다. 인바디와 0.5~1kg 다를 수 있어서, '
                  '판정은 계획선과의 거리가 아니라 점들의 추세가 계획선과 얼마나 다르게 '
                  '가는지로 합니다. 같은 주(또는 5일 안)에 다시 잰 값은 앞의 값을 대신합니다.',
                  style: hint),
            ]),
          ),

        if (review != null)
          _AdviceCard(
            review: review,
            preview: preview,
            before: plan,
            caveat: dietPct == null &&
                    core.jsTruthy(ex['hasTarget']) &&
                    !const {'early', 'collecting', 'adherence'}.contains(review['status'])
                ? '식단 기록이 ${n0(logged)}일뿐이라 실행 여부는 반영하지 못했습니다. 체중만 보고 낸 판정입니다.'
                : null,
          ),

        if (review != null && canApply) ...[
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
        _PastCard(list: checkinsOf(st), onDelete: (c) => _delete(app, c)),
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

  /// 이번 **계획 주**에 한 체크인 — 다시 저장하면 이걸 새 값으로 바꿉니다. 판정(코어)도
  /// 계획 주마다 마지막 값만 쓰므로 같은 칸입니다. 목록에 둘 다 남으면 틀린 값이
  /// 「지난 체크인」에 계속 보였습니다. (5일 묶음을 바뀐 값부터 세던 판은 3~4일마다
  /// 재는 사람의 기록을 계속 덮어써 하나만 남겼습니다 — 주 칸은 고정이라 그러지 않습니다.)
  Map<String, Object?>? _sameWeek(app) {
    final all = _sameWeekAll(app);
    return all.isEmpty ? null : all.last;
  }

  /// 이번 계획 주의 체크인 전부 — 0.2.6 까지는 저장할 때마다 더해서 한 주에 여럿일 수 있습니다.
  List<Map<String, Object?>> _sameWeekAll(app) {
    final plan = app.state['plan'];
    if (plan is! Map) return const [];
    final p = plan.cast<String, Object?>();
    final now = core.planWeekOf(p['startDate'], app.store.dayKey());
    return [
      for (final c in checkinsInPlan(app.store, p))
        if (planWeekAt(app.store, p, c['at']) == now) c,
    ];
  }

  /// 새 체크인을 넣거나, 이번 계획 주의 것(여럿이면 전부)을 바꿉니다. 바꿀 때 시각은
  /// **새 시각**(잰 날이 그대로 보이게), 「조정함」 표시는 남깁니다.
  List<Object?> _withEntry(app, Map<String, Object?> entry) {
    final same = _sameWeekAll(app);
    final ats = {for (final c in same) '${c['at']}'};
    final applied = entry['applied'] == true || same.any((c) => c['applied'] == true);
    final list = [
      for (final x in ((app.state['checkins'] as List?) ?? const []))
        if (!(x is Map && ats.contains('${x['at']}'))) x,
    ];
    return list..add({...entry, 'applied': applied});
  }

  void _save(app, double actual, Map<String, Object?> ex, Map<String, Object?>? review) {
    final list = _withEntry(app, _entry(DateTime.now().toUtc().toIso8601String(), actual, ex, review, false));
    app.store.set({'checkins': list});
    if (!app.store.saved()) {
      toast(context, '기기에 저장하지 못했습니다 — 체크인이 남지 않습니다');
      return;
    }
    Navigator.of(context).pop();
    toast(context, '체크인을 저장했습니다');
  }

  /* 잘못 넣은 체크인을 지웁니다. 예전엔 지울 길이 없어서 한 번 잘못 넣은 값이
     기준점으로 남아 그 뒤 판정을 계속 틀었습니다. 계획을 조정한 체크인을 지워도
     조정은 그대로 남습니다 — 그렇다고 말합니다. */
  Future<void> _delete(app, Map<String, Object?> c) async {
    final plan = app.state['plan'];
    final adjs = plan is Map && plan['adjustments'] is List ? plan['adjustments'] as List : const [];
    final tied = c['applied'] == true || adjs.any((a) => a is Map && a['at'] == c['at']);
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('이 체크인을 지울까요?'),
        content: Text('${dateShort(c['at'])} · ${n1(c['weightKg'])}kg'
            '${tied ? '\n\n이 체크인으로 계획을 조정했습니다. 지워도 바뀐 계획은 그대로 남습니다.' : ''}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('지우기')),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    final list = [
      for (final x in (app.state['checkins'] as List?) ?? const [])
        if (!(x is Map && x['at'] == c['at'])) x,
    ];
    app.store.set({'checkins': list});
    toast(context, '지웠습니다');
    setState(() {});
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
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('적용')),
        ],
      ),
    );
    if (yes != true || !mounted) return;

    /* 조정과 체크인은 같은 시각 — 이번 주 것을 바꿔 넣는 경우에도 새 시각으로(새 조정이 기준). */
    final list = _withEntry(app, _entry(at, actual, ex, review, true));
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
  const _AdviceCard({required this.review, this.preview, required this.before, this.caveat});
  final Map<String, Object?> review;
  /// applyCheckinAdvice 의 결과 — 적용하면 실제로 바뀌는 숫자.
  final Map<String, Object?>? preview;
  final Map<String, Object?> before;
  final String? caveat;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final status = '${review['status']}';
    final tone = switch (status) {
      'onTrack' => Tone.ok,
      'slow' || 'fast' || 'heavy' || 'light' => Tone.warn,
      _ => Tone.none,
    };
    /* 추세를 말합니다 — 몇 번 · 몇 주의 체크인으로 본 것인지까지. 모으는 중에는
       숫자가 흔들림 그 자체라 안 보여 줍니다. */
    final dev = review['devKg'];
    final span = review['spanWeeks'];
    final shown = dev is num && !const {'adherence', 'early', 'collecting'}.contains(status);
    final from = review['phaseFrom'] != null
        ? '이번 단계에서 '
        : (review['since'] != null ? '조정한 뒤 ' : '');
    final lead = '$from체크인 ${n0(review['weeks'])}번 · ${n1(span)}주의 추세로 보면';
    final devText = !shown
        ? null
        : dev.abs() < 0.05
            ? '$lead 계획선과 같이 가고 있습니다.'
            : review['held'] == true || review['rawOpposite'] == true
                ? '$lead 계획선보다 ${n2(dev.abs())}kg ${dev > 0 ? '무겁지만' : '가볍지만'}, '
                    '체중 자체는 ${review['held'] == true ? '그대로입니다' : (dev > 0 ? '오히려 줄었습니다' : '오히려 늘었습니다')}.'
                : '$lead 그 기간에 계획선보다 ${n2(dev.abs())}kg ${dev > 0 ? '무거워졌습니다' : '가벼워졌습니다'} '
                    '(1kg 까지는 흔들림으로 봅니다).';

    String? previewText;
    final pv = preview;
    if (pv != null) {
      final m0 = (before['macros'] as Map?) ?? const {};
      final m1 = ((pv['plan'] as Map)['macros'] as Map?) ?? const {};
      final kcal = core.jsToNumber(pv['kcalDelta']);
      final cardio = core.jsToNumber(pv['cardioMinDelta']);
      final w0 = before['workout'] is Map ? (before['workout'] as Map)['cardioMinPerWeek'] : null;
      previewText = [
        if (kcal != 0) '하루 ${n0(m0['intakeKcal'])} → ${n0(m1['intakeKcal'])}kcal',
        if (cardio != 0) '유산소 주 ${n0(w0 ?? 0)} → ${n0(core.jsToNumber(w0 ?? 0) + cardio)}분',
        if (pv['floored'] == true)
          kcal == 0 ? '칼로리는 이미 하루 하한이라 더 줄이지 않습니다' : '하한 때문에 ${n0(kcal.abs())}kcal 만 줄입니다',
      ].join(' · ');
    }

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
        if (previewText != null && previewText.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Note(title: '적용하면', text: ' $previewText'),
          ),
        if (caveat != null)
          Text(caveat!, style: t.textTheme.labelSmall?.copyWith(color: t.hintColor, height: 1.5)),
      ]),
    );
  }
}

/* --- 지난 체크인 ---------------------------------------------------------------
   예전엔 저장하고 나면 어디에도 안 보였습니다. 최근 다섯 개를 판정과 함께. */
class _PastCard extends StatelessWidget {
  const _PastCard({required this.list, required this.onDelete});
  final List<Map<String, Object?>> list;
  final void Function(Map<String, Object?>) onDelete;

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
          Text('아직 없습니다. 주 1회 같은 조건(아침 공복)으로 재면, 3주에 걸쳐 4번째 체크인부터 판정이 나옵니다.',
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
                IconButton(
                  tooltip: '지우기',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(LucideIcons.trash2, size: 16, color: t.hintColor),
                  onPressed: () => onDelete(c),
                ),
              ]),
            ),
      ]),
    );
  }
}
