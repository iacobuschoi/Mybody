/* =============================================================================
 * home.dart — P02 홈
 *
 * 이 화면이 지키는 약속 셋 (전부 지금 앱에서 한 번씩 어겼다가 고친 것들):
 *
 *  1. **갈 거리가 없는 축은 평균에서 뺍니다.** "체지방은 빼고 근육은 유지"
 *     가 제일 흔한 목표인데, 근육 축을 "이미 도착 = 100" 으로 치면 평균이
 *     50% 에서 시작합니다. 하루도 안 지났는데 큰 고리가 절반을 가리킵니다.
 *
 *  2. **오차보다 작은 변화에는 달성률을 안 붙입니다.** 계획 −0.9kg 에
 *     −0.4kg 를 재고 44% 라고 찍으면, 잴 수 없는 것에 숫자를 붙이는
 *     것입니다. 그 숫자를 보고 사람은 행동을 바꿉니다.
 *
 *  3. **저장이 실패했는데 "체크했습니다" 라고 하지 않습니다.** 새로고침하면
 *     그 체크가 없고, 사람은 앱을 의심하기 전에 자기 기억을 의심합니다.
 * ========================================================================== */
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:mybody_core/mybody_core.dart' as core;

import '../scope.dart';
import '../ui/charts.dart';
import '../ui/fmt.dart';
import '../ui/symbols.dart';
import '../ui/widgets.dart';

/* 아래쪽에 자리를 둡니다 — 떠 있는 "인바디" 버튼이 마지막 줄을 가렸습니다.
   실제로 "칸을 눌러서 정하세요" 의 뒷부분이 버튼에 덮여 있었습니다. */
const _pad = EdgeInsets.fromLTRB(16, 16, 16, 96);

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.go});
  final void Function(String route, [Object? arg]) go;

  @override
  Widget build(BuildContext context) {
    final app = Scope.of(context);
    final st = app.state;
    final scans = app.store.sortedScans();
    final profile = app.profile ?? core.kSeedProfile;

    if (scans.isEmpty) {
      return ListView(padding: _pad, children: [
        EmptyState(
          title: '인바디 결과지를 올려주세요',
          detail: '사진 한 장이면 현재 상태를 읽고 계획을 만듭니다.',
          action: FilledButton(onPressed: () => go('upload'), child: const Text('인바디 올리기')),
        ),
        /* 인바디가 없어도 운동 일정은 쓸 수 있습니다 — 체중을 모른다고
           월요일에 헬스 가기로 못 정할 이유가 없습니다. */
        _WeekCard(go: go),
      ]);
    }

    final scan = scans.last;
    final d = core.derive(scan, profile);
    final prev = scans.length > 1 ? scans[scans.length - 2] : null;
    final pd = prev == null ? null : core.derive(prev, profile);

    return ListView(padding: _pad, children: [
      _SummaryCard(d: d, pd: pd, scan: scan, onTap: () => go('scan', scan['id'])),
      if (st['goal'] != null && st['plan'] != null && !app.store.planMatchesGoal())
        Note(
          tone: Tone.warn,
          title: '목표가 바뀌었습니다.',
          text: '플랜을 다시 만들어야 아래 숫자가 맞습니다.',
        ),
      if (st['goal'] != null && st['plan'] != null)
        _GoalCard(go: go)
      else
        MbCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SectionTitle('목표를 정하면 계획이 나옵니다'),
            Text('언제까지 어디로 갈지 정하면, 주차별 궤적과 식단·운동 처방을 만듭니다.',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            FilledButton(onPressed: () => go('goal'), child: const Text('목표 정하기')),
          ]),
        ),
      _WeekCard(go: go),
      /* 플랜 카드(오늘/이번주/한달)는 뺐습니다 — 같은 내용이 플랜 탭에
         있고, 홈에서 한 번 더 보여 줘도 하는 일이 달라지지 않았습니다. */
      _NextCard(go: go, hasPlan: st['plan'] != null),
    ]);
  }
}

/* --- 다음에 할 일 --------------------------------------------------------
   원본에는 「인바디 새로 올리기」도 있는데, 앱은 그 자리에 떠 있는 버튼이
   이미 있습니다. 같은 일을 하는 버튼이 한 화면에 둘이면 어느 쪽이
   진짜인지 묻게 되니 여기엔 안 둡니다. */
class _NextCard extends StatelessWidget {
  const _NextCard({required this.go, required this.hasPlan});
  final void Function(String route, [Object? arg]) go;
  final bool hasPlan;
  @override
  Widget build(BuildContext context) {
    return MbCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SectionTitle('다음에 할 일'),
        if (hasPlan) ...[
          OutlinedButton.icon(
            onPressed: () => go('checkin'),
            icon: const Icon(LucideIcons.checkCircle2),
            label: const Text('이번 주 체크인'),
          ),
          const SizedBox(height: 8),
        ],
        OutlinedButton.icon(
          onPressed: () => go('history'),
          icon: const Icon(LucideIcons.history),
          label: const Text('측정 기록 보기'),
        ),
      ]),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.d, required this.pd, required this.scan, this.onTap});
  final Map<String, Object?> d;
  final Map<String, Object?>? pd;
  final Map<String, Object?> scan;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = mb(context);
    double? delta(String k) => pd == null
        ? null
        : core.jsToNumber(d[k]) - core.jsToNumber(pd![k]);

    return MbCard(
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionTitle('최신 인바디',
            trailing: Text(dateK(scan['measuredAt']),
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: Theme.of(context).hintColor))),
        Row(children: [
          Expanded(child: Stat(label: '체중', value: n1(d['weightKg']), unit: 'kg',
              delta: pd == null ? null : signed(delta('weightKg')), color: c.weight)),
          Expanded(child: Stat(label: '골격근량', value: n1(d['smmKg']), unit: 'kg',
              delta: pd == null ? null : signed(delta('smmKg')), color: c.muscle)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: Stat(label: '체지방량', value: n1(d['bfmKg']), unit: 'kg',
              delta: pd == null ? null : signed(delta('bfmKg')), color: c.fat)),
          Expanded(child: Stat(label: '체지방률', value: n1(d['pbfPct']), unit: '%',
              delta: pd == null ? null : signed(delta('pbfPct')), color: c.fat)),
        ]),
        if (core.jsTruthy(scan['inbodyScore'])) ...[
          const Divider(height: 24),
          _Kv('InBody 점수', '${n0(scan['inbodyScore'])} / 100'),
          _Kv('기초대사량', '${n0(d['bmrKcal'])} kcal'),
          _Kv('내장지방 레벨', scan['visceralFatLevel'] == null ? '—' : n0(scan['visceralFatLevel'])),
        ],
      ]),
    );
  }
}

class _Kv extends StatelessWidget {
  const _Kv(this.k, this.v);
  final String k, v;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(k, style: t.textTheme.bodySmall?.copyWith(color: t.hintColor)),
        Text(v, style: t.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

class _GoalCard extends StatelessWidget {
  const _GoalCard({required this.go});
  final void Function(String route, [Object? arg]) go;

  @override
  Widget build(BuildContext context) {
    final app = Scope.of(context);
    final st = app.state;
    final c = mb(context);
    final profile = app.profile ?? core.kSeedProfile;
    final scans = app.store.sortedScans();
    final plan = (st['plan'] as Map).cast<String, Object?>();
    final base = st['baselinePlan'] == null
        ? plan
        : (st['baselinePlan'] as Map).cast<String, Object?>();
    final goal = (st['goal'] as Map).cast<String, Object?>();
    final d = core.derive(scans.last, profile);
    final drift = core.planDrift(plan, scans, profile);

    final projected = (drift?['projectedDate'] ?? plan['targetDate']);
    final dday = core.daysUntil(projected);
    final baseDelta = core.daysUntil(base['targetDate'], projected);  // 양수 = 당겨짐

    final traj = (plan['trajectory'] as List).cast<Map<String, Object?>>();
    final startBfm = core.jsToNumber(traj.first['bfmKg']);
    final startSmm = core.jsToNumber(traj.first['smmKg']);
    final targetBfm = core.jsToNumber(goal['bfmKg']);
    final targetSmm = core.jsToNumber(goal['smmKg']);
    final fatSpan = startBfm - targetBfm;
    final smmSpan = targetSmm - startSmm;

    /* **갈 거리가 있는 축만 셉니다.** 없는 축을 100 으로 채우면 평균이
       50 에서 시작합니다 — 파일 머리의 약속 1. */
    final axes = <double>[];
    if (fatSpan.abs() >= 0.05) {
      axes.add(_clamp((startBfm - core.jsToNumber(d['bfmKg'])) / fatSpan * 100));
    }
    if (smmSpan > 0.05) {
      axes.add(_clamp((core.jsToNumber(d['smmKg']) - startSmm) / smmSpan * 100));
    }
    final overall = axes.isEmpty
        ? 100.0
        : core.jsRound(axes.reduce((a, b) => a + b) / axes.length).toDouble();

    final doneFat = fatSpan.abs() < 0.05
        ? 100.0
        : _clamp((startBfm - core.jsToNumber(d['bfmKg'])) / fatSpan * 100);
    final doneSmm = smmSpan > 0.05
        ? _clamp((core.jsToNumber(d['smmKg']) - startSmm) / smmSpan * 100)
        : 100.0;

    final mode = plan['mode'] == null ? null : (plan['mode'] as Map).cast<String, Object?>();

    return MbCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionTitle('목표까지',
            trailing: Wrap(spacing: 4, children: [
              if (mode != null) Pill('${mode['nameKo']}'),
              Pill('${plan['label']} 강도', tone: Tone.none),
            ])),
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Donut(pct: overall, size: 62),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic, children: [
                  Text(_dday(dday),
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.4)),
                  const SizedBox(width: 6),
                  if (core.jsToNumber(baseDelta).abs() >= 3)
                    Pill(
                        '${core.jsToNumber(baseDelta) > 0 ? '−' : '+'}${n0(core.jsToNumber(baseDelta).abs())}일',
                        tone: core.jsToNumber(baseDelta) > 0 ? Tone.ok : Tone.warn),
                ]),
              Text('${dateK(projected)} 도착 예정',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: Theme.of(context).hintColor)),
            ]),
          ),
        ]),
        if (drift != null) ...[
          const SizedBox(height: 12),
          Note(
            tone: drift['status'] == 'ahead'
                ? Tone.ok
                : (drift['status'] == 'onTrack' ? Tone.none : Tone.warn),
            title: '${drift['headline']}',
            text: drift['status'] == 'onTrack'
                ? ''
                : ' 계획상 오늘 체지방 ${n1((drift['expected'] as Map)['bfmKg'])}kg, '
                    '실제 ${n1((drift['actual'] as Map)['bfmKg'])}kg.',
          ),
          if (drift['muscleWarning'] != null)
            Note(tone: Tone.warn, text: '${drift['muscleWarning']}'),
          if (drift['recommendChange'] == true)
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonal(
                  onPressed: () => go('plan'), child: const Text('계획 다시 세우기')),
            ),
        ],
        const Divider(height: 24),
        _ProgressRow(label: '체지방', cur: core.jsToNumber(d['bfmKg']), target: targetBfm,
            pct: doneFat, color: c.fat),
        const SizedBox(height: 10),
        _ProgressRow(label: '골격근', cur: core.jsToNumber(d['smmKg']), target: targetSmm,
            pct: doneSmm, color: c.muscle),
        const SizedBox(height: 14),
        Row(children: [
          OutlinedButton(onPressed: () => go('plan'), child: const Text('플랜 보기')),
          const SizedBox(width: 8),
          OutlinedButton(onPressed: () => go('goal'), child: const Text('목표 변경')),
        ]),
      ]),
    );
  }

  static String _dday(num d) {
    if (!d.isFinite) return 'D−?';
    if (d > 0) return 'D−${d.round()}';
    if (d == 0) return 'D−DAY';
    return 'D+${d.abs().round()}';
  }

  static double _clamp(double x) => x.isFinite ? x.clamp(0, 100).toDouble() : 0;
}

class _ProgressRow extends StatelessWidget {
  const _ProgressRow({required this.label, required this.cur, required this.target,
      required this.pct, required this.color});
  final String label;
  final double cur, target, pct;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: t.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
        Text('${n1(cur)}kg → ${n1(target)}kg',
            style: t.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700)),
      ]),
      const SizedBox(height: 4),
      ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: LinearProgressIndicator(
          value: pct.isFinite ? (pct / 100).clamp(0, 1) : 0,
          minHeight: 8,
          backgroundColor: t.dividerColor,
          valueColor: AlwaysStoppedAnimation(color),
        ),
      ),
    ]);
  }
}

/* --- 이번 주 운동 ----------------------------------------------------------- */

class _WeekCard extends StatelessWidget {
  const _WeekCard({required this.go});
  final void Function(String route, [Object? arg]) go;

  @override
  Widget build(BuildContext context) {
    final app = Scope.of(context);
    final sum = app.schedule.weekSummary();
    final days = (sum['days'] as List).cast<Map<String, Object?>>();
    final planned = core.jsToNumber(sum['plannedDays']);
    final kept = core.jsToNumber(sum['keptDays']);

    Map<String, Object?>? today;
    for (final d in days) {
      if (d['isToday'] == true) today = d;
    }

    return MbCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionTitle('이번 주 운동',
            trailing: Text(
                planned > 0 ? '${n0(kept)}/${n0(planned)}일 완료' : '아직 정한 날이 없습니다',
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: Theme.of(context).hintColor))),
        Row(children: [
          for (final d in days) Expanded(child: _DayCell(day: d)),
        ]),
        const SizedBox(height: 12),
        if (today == null || (today['plan'] as List).isEmpty)
          Text('오늘은 정해 둔 운동이 없습니다. 칸을 눌러서 정하세요.',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: Theme.of(context).hintColor))
        else
          _TodayRow(day: today),
        ..._fillFromPlan(context, app, days),
        ..._cardioNote(context, app, days),
        _StreakRow(),
      ]),
    );
  }
}

/* "플랜대로 채우기" — 엔진이 만든 주간 분할을 이번 주 칸에 깔아 줍니다.

   두 가지를 지킵니다.
     (가) 이미 정해 둔 날은 건드리지 않습니다. 엔진의 배치는 제안이고,
          사람이 고른 것이 언제나 이깁니다.
     (나) **지나간 날은 채우지 않습니다.** 금요일에 눌렀는데 월·수가
          헬스로 채워지면, 안 간 날이 그 자리에서 "못 지킨 날" 이 됩니다.
          하지도 않은 실패를 앱이 만들어 주는 셈입니다. 오늘부터 채웁니다.

   유산소는 안 채웁니다. 엔진에는 요일 개념이 없고 주당 분(分)만 있습니다.
   없는 정보를 있는 척 배치하지 않습니다. */
List<Widget> _fillFromPlan(BuildContext context, app, List<Map<String, Object?>> days) {
  final plan = app.state['plan'];
  final w = plan is Map ? plan['workout'] : null;
  final sessions = w is Map ? w['sessions'] : null;
  if (sessions is! List || sessions.length != 7) return const [];

  final today = app.store.dayKey();
  final targets = <String>[];
  for (var i = 0; i < days.length && i < 7; i++) {
    final key = '${days[i]['key']}';
    if (key.compareTo(today) < 0) continue;              // 지나간 날은 건드리지 않습니다
    if ((days[i]['plan'] as List).isNotEmpty) continue;  // 이미 정해 둔 날도
    final sess = sessions[i];
    if (sess is! Map || sess['rest'] == true) continue;
    targets.add(key);
  }
  if (targets.isEmpty) return const [];

  final t = Theme.of(context);
  return [
    const SizedBox(height: 10),
    FilledButton.tonal(
      onPressed: () {
        for (final k in targets) {
          app.store.setSchedulePlan(k, 'gym', true);
        }
        if (!app.store.saved()) {
          toast(context, '기기에 저장하지 못했습니다 — 설정에서 사진을 지우고 다시 해 보세요');
          return;
        }
        toast(context, '${targets.length}일을 헬스로 채웠습니다');
      },
      child: Text('플랜대로 채우기 (${(w as Map)['splitName']} · 남은 ${targets.length}일)'),
    ),
    const SizedBox(height: 5),
    Text('오늘부터 채웁니다. 이미 정한 날은 그대로 둡니다.',
        style: t.textTheme.bodySmall?.copyWith(color: t.hintColor)),
  ];
}

/* 유산소 안내는 채우기 버튼과 따로 둡니다. 버튼 밑에 붙이면 누르는 순간
   버튼이 사라지면서 설명도 같이 사라집니다 — 하필 "유산소는 왜 안
   채워졌지?" 가 생기는 바로 그 순간에 답이 없어집니다. */
List<Widget> _cardioNote(BuildContext context, app, List<Map<String, Object?>> days) {
  final plan = app.state['plan'];
  final w = plan is Map ? plan['workout'] : null;
  if (w is! Map || !(core.jsToNumber(w['cardioMinPerWeek']) > 0)) return const [];
  if (days.any((d) => (d['plan'] as List).contains('cardio'))) return const [];
  final t = Theme.of(context);
  return [
    const SizedBox(height: 8),
    Text('유산소는 플랜에 주 ${n0(w['cardioMinPerWeek'])}분만 있고 요일이 없습니다. '
        '직접 고르셔야 합니다 (${w['cardioPlan'] ?? ''}).',
        style: t.textTheme.bodySmall?.copyWith(color: t.hintColor, height: 1.5)),
  ];
}

class _DayCell extends StatelessWidget {
  const _DayCell({required this.day});
  final Map<String, Object?> day;

  @override
  Widget build(BuildContext context) {
    final app = Scope.of(context);
    final t = Theme.of(context);
    final c = mb(context);
    final plan = (day['plan'] as List);
    final done = (day['done'] as Map);
    final isToday = day['isToday'] == true;
    final missed = day['missed'] == true;

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _openDay(context, app, '${day['key']}'),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 1),
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: isToday ? c.accentSub : null,
          border: missed ? Border.all(color: c.warn.withValues(alpha: 0.5)) : null,
        ),
        child: Column(children: [
          Text('${day['dow']}', style: t.textTheme.labelSmall?.copyWith(color: t.hintColor)),
          Text(n0(day['dayNum']),
              style: t.textTheme.bodySmall?.copyWith(
                  fontWeight: isToday ? FontWeight.w800 : FontWeight.w500)),
          const SizedBox(height: 3),
          SizedBox(
            height: 6,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (final ty in core.kSchedTypes)
                if (plan.contains(ty['id']))
                  Container(
                    width: 5, height: 5,
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: core.jsTruthy(done[ty['id']])
                          ? (ty['id'] == 'gym' ? c.muscle : c.ok)
                          : t.dividerColor,
                      border: core.jsTruthy(done[ty['id']])
                          ? null
                          : Border.all(color: t.hintColor.withValues(alpha: 0.5), width: 1),
                    ),
                  ),
            ]),
          ),
        ]),
      ),
    );
  }
}

Future<void> _openDay(BuildContext context, app, String key) async {
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
      final e = app.store.scheduleDay(key);
      final plan = (e['plan'] as List);
      final done = (e['done'] as Map);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(dateK(key), style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: 12),
              for (final ty in core.kSchedTypes) ...[
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: Icon(schedIcon(ty['id'])),
                  title: Text('${ty['label']} 하기로'),
                  value: plan.contains(ty['id']),
                  onChanged: (on) {
                    app.store.setSchedulePlan(key, ty['id'], on);
                    setSheet(() {});
                  },
                ),
                if (plan.contains(ty['id']))
                  CheckboxListTile(
                    contentPadding: const EdgeInsets.only(left: 16),
                    title: Text('했습니다',
                        style: Theme.of(ctx).textTheme.bodySmall),
                    value: core.jsTruthy(done[ty['id']]),
                    onChanged: (on) {
                      final r = app.store.setScheduleDone(key, ty['id'], on ?? false);
                      if (r == null) return;
                      /* 아직 오지 않은 날은 체크가 안 됩니다 —
                         내일 갈 헬스를 오늘 체크하는 건 기록이 아니라 소원입니다. */
                      if (!app.store.saved()) {
                        toast(ctx, '기기에 저장하지 못했습니다 — 체크가 남지 않습니다');
                      } else if (core.jsTruthy((r['done'] as Map)[ty['id']]) != (on ?? false)) {
                        toast(ctx, '아직 오지 않은 날은 체크할 수 없습니다');
                      }
                      setSheet(() {});
                    },
                  ),
              ],
            ]),
        ),
      );
    }),
  );
}

class _TodayRow extends StatelessWidget {
  const _TodayRow({required this.day});
  final Map<String, Object?> day;

  @override
  Widget build(BuildContext context) {
    final app = Scope.of(context);
    final plan = (day['plan'] as List);
    final done = (day['done'] as Map);
    final left = plan.where((t) => !core.jsTruthy(done[t])).toList();
    if (left.isEmpty) {
      return Note(
          tone: Tone.ok,
          text: '오늘 할 것 다 했습니다 — '
              '${plan.map((t) => core.kSchedTypes.firstWhere((x) => x['id'] == t)['label']).join(' · ')}');
    }
    return Wrap(spacing: 8, children: [
      for (final t in left)
        FilledButton.icon(
          icon: Icon(schedIcon(t), size: 18),
          onPressed: () {
            app.store.setScheduleDone(day['key'], t, true);
            /* **저장이 실패했는데 "체크했습니다" 라고 하지 않습니다.** */
            if (!app.store.saved()) {
              toast(context, '기기에 저장하지 못했습니다 — 설정에서 사진을 지워 보세요');
              return;
            }
            final ty = core.kSchedTypes.firstWhere((x) => x['id'] == t);
            toast(context, '${ty['label']} 체크했습니다');
          },
          label: Text(
              '${core.kSchedTypes.firstWhere((x) => x['id'] == t)['label']} 했어요'),
        ),
    ]);
  }
}

/// 스트릭은 **행동에만** 답니다. 몸무게에는 절대 달지 않습니다.
class _StreakRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final app = Scope.of(context);
    final settings = (app.state['settings'] as Map?) ?? const {};
    if (core.jsTruthy(settings['hideStreaks'])) return const SizedBox.shrink();

    final w = app.schedule.workoutStreak();
    final f = app.schedule.foodStreak();

    /* **아직 시작도 안 한 사람에게 "0일 연속" 을 보여주지 않습니다.**
       사실이긴 한데 첫 화면에서 0 을 두 개 보는 것은 격려가 아니라 채점입니다.
       셀 것이 생기면 그때 나타납니다 — 계획한 날이 하나라도 있거나,
       식단을 한 번이라도 적었을 때. */
    final counted = core.jsTruthy(w['everPlanned']) ||
        core.jsToNumber(f['last7']) > 0 ||
        core.jsToNumber(f['days']) > 0;
    if (!counted) return const SizedBox.shrink();

    final stale = core.jsTruthy(w['stale']);

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(children: [
        Expanded(
          child: _Streak(
            icon: LucideIcons.dumbbell,
            /* 오래된 기록은 숫자를 지우지 않고 **과거형으로** 말합니다 —
               지우면 "네 기록은 없다" 가 되고, 그건 사실이 아닙니다. */
            title: stale
                ? '${n0(w['days'])}일 연속이었습니다'
                : '운동 ${n0(w['days'])}일 연속',
            sub: stale
                ? '마지막이 ${n0(w['staleDays'])}일 전입니다'
                : '최근 28일 중 ${n0(w['last28'])}일',
          ),
        ),
        Expanded(
          child: _Streak(
            icon: LucideIcons.utensils,
            title: '식단 ${n0(f['days'])}일 연속',
            sub: '최근 7일 중 ${n0(f['last7'])}일',
          ),
        ),
      ]),
    );
  }
}

class _Streak extends StatelessWidget {
  const _Streak({required this.icon, required this.title, required this.sub});
  final IconData icon;
  final String title, sub;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Row(children: [
      Icon(icon, size: 18, color: t.hintColor),
      const SizedBox(width: 8),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: t.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700)),
          Text(sub, style: t.textTheme.labelSmall?.copyWith(color: t.hintColor)),
        ]),
      ),
    ]);
  }
}
