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

import '../briefing.dart';
import '../checkins.dart';
import '../scope.dart';
import '../ui/charts.dart';
import '../ui/fmt.dart';
import '../ui/symbols.dart';
import '../ui/widgets.dart';
import 'adherence.dart' show DayMark, DayMarkLegend, dayMarkState;
import 'plan.dart' show cardioStat;
import 'update_banner.dart';

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
        const UpdateBanner(),
        /* 브리핑이 "인바디부터" 를 말하고 올리기 버튼을 듭니다. 예전의 빈
           화면 안내는 뺐습니다 — 같은 말을 두 카드가 하면 어느 쪽 버튼이
           진짜인지 묻게 됩니다. */
        BriefingCard(go: go),
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
      /* 맨 위에 둡니다 — 서버와 안 맞는 판이면 아래 무엇보다 먼저 알아야
         로그인 · 동기화가 왜 안 되는지 헤매지 않습니다. */
      const UpdateBanner(),
      /* 그다음이 브리핑 — 오늘 무엇을 하는 날인지 · 어떻게 먹을지 · 지금
         당장 무엇을 할지. 숫자(최신 인바디)보다 할 일이 먼저입니다. 숫자는
         읽는 것이고 할 일은 하는 것이라, 앱을 연 사람이 찾는 쪽은 뒤쪽입니다. */
      BriefingCard(go: go),
      _SummaryCard(d: d, pd: pd, scan: scan, onTap: () => go('scan', scan['id'])),
      if (st['goal'] != null && st['plan'] != null && !app.store.planMatchesGoal())
        const Note(tone: Tone.warn, text: '목표가 바뀌었습니다 — 플랜을 다시 만드세요'),
      /* 계획이 없을 때의 「목표 정하기」 카드는 뺐습니다 — 브리핑이 같은
         말을 하고 같은 버튼을 듭니다. */
      if (st['goal'] != null && st['plan'] != null) _GoalCard(go: go),
      _WeekCard(go: go),
      /* 플랜 카드(오늘/이번주/한달)는 뺐습니다 — 같은 내용이 플랜 탭에
         있고, 홈에서 한 번 더 보여 줘도 하는 일이 달라지지 않았습니다. */
      _NextCard(go: go, hasPlan: st['plan'] != null, doneThisWeek: checkinThisWeek(app.store)),
    ]);
  }
}

/* --- 오늘 브리핑 ------------------------------------------------------------
   홈의 첫 카드. 무엇을 말할지는 전부 briefing.dart 가 정하고, 여기는 그리기만
   합니다 — 규칙이 위젯 안에 있으면 아침 8시와 밤 9시 반을 시험으로 세워 볼
   수 없습니다.

   버튼은 주 버튼 하나(FilledButton)에 보조 둘까지(tonal). 360px 폭에서 셋이
   한 줄에 안 들어가면 Wrap 이 다음 줄로 내립니다 — 잘리지 않습니다. */
class BriefingCard extends StatelessWidget {
  const BriefingCard({super.key, required this.go, this.now});
  final void Function(String route, [Object? arg]) go;

  /// 시험용 시계. 없으면 저장소의 시계 — 그게 "오늘" 의 기준입니다.
  final DateTime? now;

  static IconData _icon(String key) => switch (key) {
        'cardio' => LucideIcons.footprints,
        'food' => LucideIcons.utensils,
        'checkin' => LucideIcons.clipboardCheck,
        'rest' => LucideIcons.coffee,
        'done' => LucideIcons.checkCircle2,
        'scan' => LucideIcons.imagePlus,
        _ => LucideIcons.dumbbell,
      };

  @override
  Widget build(BuildContext context) {
    final app = Scope.of(context);
    final b = buildBriefing(app, now: now);
    final t = Theme.of(context);
    final c = mb(context);

    return MbCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Text(b.headline,
                style: t.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800, letterSpacing: -0.4, height: 1.25)),
          ),
          /* 폭죽은 글자가 아니라 아이콘입니다 — 이모지는 글꼴에 없습니다. */
          if (b.allDone)
            Padding(
              padding: const EdgeInsets.only(left: 8, top: 2),
              child: Icon(LucideIcons.partyPopper, color: c.ok, size: 22),
            ),
        ]),
        if (b.sub != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(b.sub!,
                style: t.textTheme.bodySmall?.copyWith(color: t.hintColor, height: 1.5)),
          ),
        if (b.celebrate != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Pill(b.celebrate!, tone: Tone.ok),
          ),
        const SizedBox(height: 12),
        for (final l in b.lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(_icon(l.icon), size: 18, color: l.done ? c.ok : t.hintColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(l.text,
                    style: t.textTheme.bodyMedium?.copyWith(
                        height: 1.4, color: l.done ? t.hintColor : null)),
              ),
            ]),
          ),
        if (b.primary != null || b.secondary.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (b.primary != null)
              FilledButton(
                  onPressed: () => go(b.primary!.route, b.primary!.arg),
                  child: Text(b.primary!.label)),
            for (final a in b.secondary)
              FilledButton.tonal(onPressed: () => go(a.route, a.arg), child: Text(a.label)),
          ]),
        ],
      ]),
    );
  }
}

/* --- 다음에 할 일 --------------------------------------------------------
   원본에는 「인바디 새로 올리기」도 있는데, 앱은 그 자리에 떠 있는 버튼이
   이미 있습니다. 같은 일을 하는 버튼이 한 화면에 둘이면 어느 쪽이
   진짜인지 묻게 되니 여기엔 안 둡니다. 「이번 주 체크인」 도 같은 이유로
   브리핑으로 올라갔습니다 — 여기는 **한 뒤에** 그 사실만 말합니다. */
class _NextCard extends StatelessWidget {
  const _NextCard({required this.go, required this.hasPlan, this.doneThisWeek});
  final void Function(String route, [Object? arg]) go;
  final bool hasPlan;
  /// 이번 계획 주에 한 체크인. 했으면 버튼이 그걸 말합니다 — 예전엔 했는지
  /// 안 했는지 홈 어디에도 안 보여서, 같은 주에 두 번 하거나 잊었습니다.
  final Map<String, Object?>? doneThisWeek;
  @override
  Widget build(BuildContext context) {
    return MbCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SectionTitle('다음에 할 일'),
        if (hasPlan && doneThisWeek != null) ...[
          OutlinedButton.icon(
            onPressed: () => go('checkin'),
            icon: Icon(LucideIcons.checkCircle2, color: mb(context).ok),
            label: Text('이번 주 체크인 완료 · ${n1(doneThisWeek!['weightKg'])}kg'),
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
            /* 숫자 둘만 — "계획상 오늘 체지방 …kg, 실제 …kg." 문장은 같은 말을 길게 했습니다. */
            text: drift['status'] == 'onTrack'
                ? ''
                : ' 체지방 계획 ${n1((drift['expected'] as Map)['bfmKg'])}kg · '
                    '실제 ${n1((drift['actual'] as Map)['bfmKg'])}kg',
          ),
          if (drift['muscleWarning'] != null)
            Note(tone: Tone.warn, text: '${drift['muscleWarning']}'),
          /* 예전엔 플랜 탭으로 갔습니다 — 거기엔 다시 세우는 기능이 없어서,
             누른 사람은 같은 계획을 한 번 더 읽고 끝났습니다. 다시 세우는
             길은 목표 화면입니다(저장된 목표로 미리 채워 두고, 기간 고르기로
             이어집니다). 강도 화면을 바로 열면 안 됩니다 — 그 화면의 저장은
             목표 → 기간 순서로 쌓였다고 보고 두 번 닫습니다. */
          if (drift['recommendChange'] == true)
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonal(
                  onPressed: () => go('goal'), child: const Text('목표·기간 다시 정하기')),
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
    /* 오늘 할 것이 무엇인지는 맨 위 브리핑이 말합니다. 여기는 오늘 칸에서
       바로 운동 화면으로 가는 길과, 작게 「그냥 체크만」 — 다 했으면
       아무것도 안 그립니다(브리핑이 완료를 말합니다). */
    final td = today;
    final left = td == null
        ? const <Object?>[]
        : (td['plan'] as List).where((ty) => !core.jsTruthy((td['done'] as Map)[ty])).toList();

    return MbCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionTitle('이번 주 운동',
            trailing: Text(
                planned > 0 ? '${n0(kept)}/${n0(planned)}일 완료' : '아직 정한 날이 없습니다',
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: Theme.of(context).hintColor))),
        Row(children: [
          for (final d in days) Expanded(child: _DayCell(day: d, today: app.store.dayKey())),
        ]),
        const SizedBox(height: 6),
        const DayMarkLegend(),
        if (td != null && left.isNotEmpty) ...[
          const SizedBox(height: 12),
          _TodayRow(day: td, left: left, go: go),
        ] else if (planned == 0) ...[
          const SizedBox(height: 12),
          Text('칸을 눌러서 운동할 날을 정하세요.',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: Theme.of(context).hintColor)),
        ],
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
    Text('오늘부터 · 이미 정한 날은 그대로',
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
  /* 「40분 × 2회」 는 플랜 탭과 같은 조각(cardioStat)으로 읽습니다 — 엔진 문구의
     "Z2 저강도" 같은 말은 여기서 걷어냅니다. 못 읽으면 주당 분. */
  final cs = cardioStat(w.cast<String, Object?>());
  final what = cs.unit.startsWith('×') ? '${cs.value} ${cs.unit}' : '주 ${cs.value}분';
  return [
    const SizedBox(height: 8),
    Text('유산소 $what — 요일은 칸을 눌러 고르세요',
        style: t.textTheme.bodySmall?.copyWith(color: t.hintColor, height: 1.5)),
  ];
}

/* 요일 칸 — 요일 · 날짜 · DayMark(지킴/놓침/오늘/쉬는 날, 달성률과 같은 그림)
   · 그 아래 운동 종류 점. 종류 점은 "무엇을" 했는지, DayMark 는 "다 했는지"
   입니다. */
class _DayCell extends StatelessWidget {
  const _DayCell({required this.day, required this.today});
  final Map<String, Object?> day;
  final String today;

  @override
  Widget build(BuildContext context) {
    final app = Scope.of(context);
    final t = Theme.of(context);
    final c = mb(context);
    final plan = (day['plan'] as List);
    final done = (day['done'] as Map);
    final isToday = day['isToday'] == true;

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _openDay(context, app, '${day['key']}'),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 1),
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: isToday ? c.accentSub : null,
        ),
        child: Column(children: [
          Text('${day['dow']}', style: t.textTheme.labelSmall?.copyWith(color: t.hintColor)),
          Text(n0(day['dayNum']),
              style: t.textTheme.bodySmall?.copyWith(
                  fontWeight: isToday ? FontWeight.w800 : FontWeight.w500)),
          const SizedBox(height: 3),
          DayMark(dayMarkState(day, today: today), size: 20),
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

/// 일정 종목 id → 이름('헬스' · '유산소'). 코어 barrel 이 labelOf 를 내보내지 않아 여기서 찾습니다.
String _schedLabel(Object? id) =>
    core.kSchedTypes.firstWhere((x) => x['id'] == id, orElse: () => const {})['label'] ?? '$id';

/// 오늘 아직 안 한 운동 — 종목마다 운동 화면으로 가는 버튼과, 작게 「그냥 체크만」.
///
/// 브리핑의 주 버튼(「운동 시작」)과 같은 화면으로 가지만 글자는 다르게 둡니다 —
/// 같은 글자의 버튼이 한 화면에 둘이면 어느 쪽이 진짜인지 묻게 됩니다.
/// 여기 것은 오늘 칸(헬 · 유) 바로 밑이라 종목 이름으로 부릅니다.
class _TodayRow extends StatelessWidget {
  const _TodayRow({required this.day, required this.left, required this.go});
  final Map<String, Object?> day;
  final List<Object?> left;
  final void Function(String route, [Object? arg]) go;

  @override
  Widget build(BuildContext context) {
    final app = Scope.of(context);
    final key = '${day['key']}';
    return Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final t in left)
            OutlinedButton.icon(
              icon: Icon(schedIcon(t), size: 18),
              onPressed: () => go('workout', {'date': key, 'type': t}),
              label: Text('${_schedLabel(t)} 하러 가기'),
            ),
          /* 화면 없이 체크만 — 갔다 왔는데 적기는 귀찮은 날. 남은 것이 둘이면
             어느 쪽인지 물어야 하니 날짜 시트를 엽니다(종목별 체크가 거기 있습니다).
             안 한 것까지 한꺼번에 체크하면 기록이 아니라 소원입니다. */
          TextButton(
            onPressed: () {
              if (left.length != 1) {
                _openDay(context, app, key);
                return;
              }
              final t = left.single;
              app.store.setScheduleDone(key, t, true);
              /* **저장이 실패했는데 "체크했습니다" 라고 하지 않습니다.** */
              if (!app.store.saved()) {
                toast(context, '기기에 저장하지 못했습니다 — 설정에서 사진을 지워 보세요');
                return;
              }
              toast(context, '${_schedLabel(t)} 체크했습니다');
            },
            child: const Text('그냥 체크만'),
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
