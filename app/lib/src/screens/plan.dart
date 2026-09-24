/* =============================================================================
 * plan.dart — P07 플랜 (위에서 플랜 / 달성률 을 고릅니다)
 *
 * 계획 한 벌을 펼쳐 보여 줍니다: 기간과 목표일, 주차별 궤적, 매크로,
 * 운동 분할, 식단 예시, 마일스톤.
 *
 * **글은 적게, 숫자와 표로.** 0.2.11 의 운동 카드는 「근육군당 주 12세트 ·
 * Z2 저강도 · 더블 프로그레션 · RPE」 를 그대로 내보냈고, 주인은 "텍스트
 * 너무 많음 — 초보자는 무슨 운동을 해야 하는지 모름" 이라고 했습니다.
 * 그래서 용어는 걷어내고 숫자 타일 셋, 세션은 따라 하기 카드(순서 · 종목 ·
 * 기구 · 세트 × 반복 · 휴식 · 요령 한 줄), 엔진의 근거 메모는 접어 둡니다.
 *
 * **운동 카드에서 조심하는 것 하나** — 부위별 근육/지방 값이 없으면
 * "뚜렷한 약점 없음" 이라고 말하지 않습니다. 그 값은 앱에 들어오는 길이
 * 아직 없습니다. 본 적도 없으면서 "당신의 인바디를 봤더니 괜찮더라" 고
 * 말하면, 진짜 불균형이 있는 사람이 확인받았다고 믿고 넘어갑니다.
 * ========================================================================== */
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:mybody_core/mybody_core.dart' as core;

import '../scope.dart';
import 'adherence.dart';
import '../ui/charts.dart';
import '../ui/fmt.dart';
import '../ui/symbols.dart';
import '../ui/widgets.dart';
import '../workout/exercises.dart';
import '../workout/planner.dart';
import '../workout/prefs.dart';
import 'gym_settings.dart';

/// 진행 규칙 한 줄. 엔진의 「더블 프로그레션 — 목표 반복 상단에 도달하면 다음
/// 세션에 중량 2.5~5kg 증가」 는 맞는 말이지만 용어부터 배워야 읽힙니다.
/// 뜻은 같고 말만 쉽게.
const String kProgressionHint = '반복을 다 채우면 다음엔 무게를 2.5~5kg 올리세요';

final RegExp _cardioRe = RegExp(r'(\d+)분\s*×\s*(\d+)회');
/* 엔진(applyCheckinAdvice)은 소수도 허용해 적습니다 — 정수만 받으면 '7.5분' 에서 조용히 빠집니다. */
final RegExp _cardioAddedRe = RegExp(r'추가 유산소 주 (-?\d+(?:\.\d+)?)분');

/// 유산소 타일에 쓸 값 · 단위 · 보조 줄. cardioPlan(「Z2 저강도 40분 × 2회」)에서
/// 분과 회를 읽어 「40분」「× 2회」 — "주 96분" 보다 "40분 두 번" 이 할 일로 읽힙니다.
/// 두 가지가 섞였거나(Z2 + HIIT) 못 읽으면 주당 분으로. 체크인 조정으로 더한
/// 분은 보조 줄에 「+N분/주」.
({String value, String unit, String? delta}) cardioStat(Map<String, Object?> workout) {
  final plan = '${workout['cardioPlan'] ?? ''}';
  final added = _cardioAddedRe.firstMatch(plan)?.group(1);
  final delta = added == null ? null : '${added.startsWith('-') ? '' : '+'}$added분/주';
  final m = _cardioRe.allMatches(plan).toList();
  if (m.length == 1) {
    return (value: '${m.first.group(1)}분', unit: '× ${m.first.group(2)}회', delta: delta);
  }
  return (value: n0(workout['cardioMinPerWeek']), unit: '분/주', delta: null);
}

/// 세트 사이 쉬는 시간. 「150초」 는 시계를 보며 세야 합니다 — 「2분 30초」.
/// 90초 미만은 초 그대로(75초). 값이 없거나 0 이면 빈 글자.
String restLabel(Object? sec) {
  final s = core.jsToNumber(sec);
  if (s.isNaN || s <= 0) return '';
  final n = s.round();
  if (n < 90) return '$n초';
  final m = n ~/ 60, r = n % 60;
  return r == 0 ? '$m분' : '$m분 $r초';
}

/// 첫 진입에 펼쳐 둘 세션의 자리(sessions 의 index). 오늘 요일(월=0)의 세션,
/// 오늘이 쉬는 날이면 그다음 운동 날. 운동 세션이 하나도 없으면 null.
/// 세션의 'day' 가 요일 칸이고(엔진이 월요일부터 채웁니다), 없으면 목록 순서.
int? openSessionIndex(List<Map<String, Object?>> sessions, int todayIdx) {
  int dayOf(int i) {
    final d = sessions[i]['day'];
    return d is num && d.isFinite ? d.toInt() : i;
  }

  for (var k = 0; k < 7; k++) {
    final want = (todayIdx + k) % 7;
    for (var i = 0; i < sessions.length; i++) {
      if (sessions[i]['rest'] != true && dayOf(i) == want) return i;
    }
  }
  return null;
}

/* 종목의 「대체」「익숙」 표와 메모 읽기(tailorTag · tailorNote)는 workout/planner.dart
   에 있습니다 — 헬스 화면과 같은 규칙이어야 합니다. */

/// 기구 이름표(머신 · 덤벨 · …). 사전에 있는 종목은 사전의 기구, 없으면 엔진이 준 것.
String? equipTag(Map<String, Object?> e) {
  final id = '${e['id'] ?? ''}';
  final equip = exerciseById(id)?.equip ?? '${e['equip'] ?? ''}';
  if (equip.isEmpty) return null;
  return kEquipLabel[equip] ?? equip;
}

/// 목표 체지방률(%) = 목표 지방 kg ÷ 목표 체중 — 목표 화면은 kg 으로만 받습니다.
double? goalPbfPct(Map<String, Object?>? goal) {
  if (goal == null) return null;
  final w = core.jsToNumber(goal['weightKg']), f = core.jsToNumber(goal['bfmKg']);
  if (!w.isFinite || w <= 0 || !f.isFinite) return null;
  return f / w * 100;
}

class PlanScreen extends StatefulWidget {
  const PlanScreen({super.key, required this.go, this.today});
  final void Function(String route, [Object? arg]) go;

  /// 오늘. 오늘 요일의 세션을 펼쳐 두는 데 씁니다 — 시험이 요일을 고정하려고
  /// 넣고, 안 주면 지금입니다.
  final DateTime? today;

  @override
  State<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends State<PlanScreen> {
  /// 위에서 고릅니다: 플랜 / 달성률. 달성률은 식단 탭에 있었는데, 운동
  /// 달성률까지 같이 보려면 "계획 대비" 를 말하는 이 탭이 맞는 자리입니다.
  String _view = 'plan';

  @override
  Widget build(BuildContext context) {
    final app = Scope.of(context);
    final st = app.state;
    final go = widget.go;
    if (st['plan'] == null) {
      return EmptyState(
        title: '아직 계획이 없습니다',
        detail: '목표를 정하면 식단·운동 계획을 만듭니다',
        action: FilledButton(onPressed: () => go('goal'), child: const Text('목표 정하기')),
      );
    }

    final picker = Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SegmentedButton<String>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: 'plan', label: Text('플랜')),
          ButtonSegment(value: 'adherence', label: Text('달성률')),
        ],
        selected: {_view},
        onSelectionChanged: (s) => setState(() => _view = s.first),
      ),
    );

    if (_view == 'adherence') {
      return ListView(padding: const EdgeInsets.all(16), children: [
        picker,
        AdherenceBody(go: go),
      ]);
    }
    final plan = (st['plan'] as Map).cast<String, Object?>();
    final traj = ((plan['trajectory'] as List?) ?? const []).cast<Map<String, Object?>>();
    final macros = (plan['macros'] as Map?)?.cast<String, Object?>();
    final workout = (plan['workout'] as Map?)?.cast<String, Object?>();
    final diet = (plan['diet'] as Map?)?.cast<String, Object?>();
    final feas = (plan['feasibility'] as Map?)?.cast<String, Object?>();
    final goal = (plan['goal'] as Map?)?.cast<String, Object?>();
    final todayIdx = (widget.today ?? DateTime.now()).weekday - 1;

    return ListView(padding: const EdgeInsets.all(16), children: [
      picker,
      MbCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SectionTitle('${plan['label']} · ${plan['title']}',
              trailing: Text('${plan['strategyLabel']}',
                  style: Theme.of(context).textTheme.labelSmall
                      ?.copyWith(color: Theme.of(context).hintColor))),
          Text('${plan['strategyDesc']}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.5)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: Stat(label: '기간', value: n0(plan['weeks']), unit: '주')),
            Expanded(child: Stat(label: '목표일', value: dateK(plan['targetDate']))),
          ]),
          if (feas != null) ...[
            const SizedBox(height: 10),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.only(top: 4, right: 6),
                child: VerdictDot(feas['verdict']),
              ),
              Expanded(
                child: Text('${feas['message']}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.5)),
              ),
            ]),
          ],
          if (plan['capWarning'] != null) ...[
            const SizedBox(height: 8),
            Note(tone: Tone.warn, text: '${plan['capWarning']}'),
          ],
          if (plan['phases'] != null) ...[
            const SizedBox(height: 14),
            PhaseBar(
              phases: ((plan['phases'] as List).cast<Map<String, Object?>>()),
              totalWeeks: core.jsToNumber(plan['weeks']),
            ),
          ],
        ]),
      ),

      if (traj.length > 1) _TrajectoryCard(traj: traj, goal: goal),

      if (macros != null)
        MbCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SectionTitle('하루 식단 목표',
                trailing: Text('하루 소모 ${n0(macros['tdeeKcal'])}kcal',
                    style: Theme.of(context).textTheme.labelSmall
                        ?.copyWith(color: Theme.of(context).hintColor))),
            Row(children: [
              Expanded(child: Stat(label: '섭취', value: n0(macros['intakeKcal']), unit: 'kcal')),
              Expanded(child: Stat(label: '적자', value: n0(macros['deficitKcal']), unit: 'kcal')),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: Stat(label: '단백질', value: n0(macros['proteinG']), unit: 'g')),
              Expanded(child: Stat(label: '탄수', value: n0(macros['carbG']), unit: 'g')),
              Expanded(child: Stat(label: '지방', value: n0(macros['fatG']), unit: 'g')),
            ]),
            const SizedBox(height: 8),
            /* "g/kg FFM" 은 전문용어라 뺐습니다 — 체중당 한 숫자만. */
            Text(
                '체중 1kg당 단백질 ${n1(macros['proteinPerBW'])}g',
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: Theme.of(context).hintColor)),
          ]),
        ),

      if (workout != null)
        _WorkoutCard(
            workout: workout,
            prefs: GymPrefs.fromSettings((st['settings'] as Map?)?.cast<String, Object?>()),
            todayIdx: todayIdx),
      if (diet != null) _DietCard(diet: diet),
      if (plan['milestones'] != null) _MilestoneCard(
          milestones: (plan['milestones'] as List).cast<Map<String, Object?>>()),

      Row(children: [
        Expanded(
          child: FilledButton.tonal(
              onPressed: () => go('checkin'), child: const Text('주간 체크인')),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton(
              onPressed: () => go('goal'), child: const Text('목표 바꾸기')),
        ),
      ]),
    ]);
  }
}

/// 주차별 궤적 — 체중 · 골격근 · 체지방률 을 **따로** 그립니다. 한 장에 지방(20kg 대)과
/// 골격근(38kg 대)을 겹치면 y축이 둘을 다 덮어서 12주 동안의 1kg 변화가 선의
/// 떨림으로 보였습니다(주인 피드백 25). 추이 탭의 세 카드와 같은 나눔입니다.
class _TrajectoryCard extends StatelessWidget {
  const _TrajectoryCard({required this.traj, required this.goal});
  final List<Map<String, Object?>> traj;
  final Map<String, Object?>? goal;

  List<Pt> _pts(String key) => [
        for (final t in traj)
          Pt(core.jsToNumber(t['week']), core.jsToNumber(t[key])),
      ];

  /// 체지방률. 궤적 줄에 pbfPct 가 없으면 지방 ÷ 체중으로.
  List<Pt> _pbf() => [
        for (final t in traj)
          Pt(
              core.jsToNumber(t['week']),
              t['pbfPct'] != null
                  ? core.jsToNumber(t['pbfPct'])
                  : core.jsToNumber(t['bfmKg']) / core.jsToNumber(t['weightKg']) * 100),
      ];

  @override
  Widget build(BuildContext context) {
    final c = mb(context);
    return MbCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SectionTitle('주차별 궤적'),
        _TrajChart(title: '체중', unit: 'kg', color: c.weight, points: _pts('weightKg'),
            goalY: goal == null ? null : core.jsToNumber(goal!['weightKg'])),
        _TrajChart(title: '골격근', unit: 'kg', color: c.muscle, points: _pts('smmKg'),
            goalY: goal == null ? null : core.jsToNumber(goal!['smmKg'])),
        _TrajChart(title: '체지방률', unit: '%', color: c.fat, points: _pbf(),
            goalY: goalPbfPct(goal)),
      ]),
    );
  }
}

/// 그래프 한 장 — 소제목이 범례입니다(선이 하나뿐이라 범례는 끕니다). 오른쪽에
/// 처음 → 끝.
class _TrajChart extends StatelessWidget {
  const _TrajChart({
    required this.title, required this.unit, required this.color,
    required this.points, required this.goalY,
  });
  final String title, unit;
  final Color color;
  final List<Pt> points;
  final double? goalY;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final live = points.where((p) => p.y.isFinite).toList();
    final range = live.isEmpty
        ? ''
        : '${n1(live.first.y)} → ${n1(live.last.y)} $unit';
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 8, height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(title, style: t.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
          const Spacer(),
          Text(range, style: t.textTheme.labelSmall?.copyWith(color: t.hintColor)),
        ]),
        LineChart(
          height: 120,
          legend: false,
          series: [Series(label: title, color: color, dots: false, points: live)],
          goals: [
            if (goalY != null && goalY!.isFinite) GoalLine(y: goalY!, color: color, label: '목표'),
          ],
          xTickFmt: (v) => '${v.round()}주',
        ),
      ]),
    );
  }
}

class _WorkoutCard extends StatelessWidget {
  const _WorkoutCard({required this.workout, required this.prefs, required this.todayIdx});
  final Map<String, Object?> workout;

  /// 운동 장소 · 기구 · 익숙한 종목. 종목 목록은 이 설정을 거쳐서 보입니다.
  final GymPrefs prefs;

  /// 오늘 요일(월=0). 그 날의 세션만 펼쳐 둡니다.
  final int todayIdx;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = mb(context);
    final sessions = ((workout['sessions'] as List?) ?? const []).cast<Map<String, Object?>>();
    final small = t.textTheme.labelSmall?.copyWith(color: t.hintColor);
    final cardio = cardioStat(workout);
    final bias = ((workout['inbodyBias'] as List?) ?? const []).map((b) => '$b').toList();
    final open = openSessionIndex(sessions, todayIdx);
    return MbCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionTitle('${workout['splitName']}',
            trailing: Text('주 ${n0(workout['daysPerWeek'])}회 · ${n0(workout['sessionMinutes'])}분',
                style: small)),
        /* 숫자 셋이 「근육군당 주 12세트 · 유산소 주 96분 · Z2 저강도」 를 대신합니다 —
           할 일은 "몇 번, 몇 분, 유산소 몇 분씩 몇 번" 입니다. */
        Row(children: [
          Expanded(child: Stat(label: '주 횟수', value: n0(workout['daysPerWeek']), unit: '회')),
          Expanded(child: Stat(label: '회당', value: n0(workout['sessionMinutes']), unit: '분')),
          Expanded(
              child: Stat(label: '유산소', value: cardio.value, unit: cardio.unit, delta: cardio.delta)),
        ]),
        const SizedBox(height: 12),

        /* 기구 · 익숙한 종목 — 종목 목록은 이 설정을 거쳐서 보입니다. 설정 화면
           깊숙이에만 있으면 "전혀 반영 안 됐다" 가 됩니다(주인이 0.2.9 를 써 보고
           그렇게 말했습니다). 요약 한 줄과 여는 단추를 종목 바로 위에 둡니다.
           안내문은 없습니다 — 바뀐 종목에 붙는 「대체」「익숙」 표가 그 말을 합니다. */
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
          decoration: BoxDecoration(color: c.accentSub, borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            Icon(LucideIcons.dumbbell, size: 16, color: t.hintColor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(gymPrefsSummary(prefs),
                  style: t.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
            ),
            TextButton(
              key: const Key('open-gym-settings'),
              onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const GymSettingsScreen())),
              child: const Text('기구 설정'),
            ),
          ]),
        ),

        for (var i = 0; i < sessions.length; i++)
          if (sessions[i]['rest'] != true)
            _SessionCard(
              key: ValueKey('session-${sessions[i]['day'] ?? i}'),
              session: sessions[i],
              prefs: prefs,
              initiallyOpen: i == open,
              isToday: _dayOf(sessions[i], i) == todayIdx,
            ),

        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(LucideIcons.trendingUp, size: 14, color: t.hintColor),
            ),
            const SizedBox(width: 6),
            Expanded(child: Text(kProgressionHint, style: small?.copyWith(height: 1.4))),
          ]),
        ),

        /* 엔진의 근거 메모(부위별 분석 · 목표 · 감량 중 볼륨)는 접어 둡니다 —
           읽고 싶은 사람만. 펼치기 전엔 제목 한 줄이 전부입니다. */
        if (bias.isNotEmpty)
          ExpansionTile(
            key: const Key('workout-why'),
            dense: true,
            tilePadding: EdgeInsets.zero,
            shape: const Border(),
            collapsedShape: const Border(),
            childrenPadding: const EdgeInsets.only(bottom: 4),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            title: Text('왜 이렇게 짰나요?',
                style: t.textTheme.labelMedium?.copyWith(color: t.hintColor, fontWeight: FontWeight.w600)),
            children: [
              for (final b in bias)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('· $b', style: t.textTheme.labelSmall?.copyWith(height: 1.5)),
                ),
            ],
          ),
      ]),
    );
  }

  static int _dayOf(Map<String, Object?> s, int i) {
    final d = s['day'];
    return d is num && d.isFinite ? d.toInt() : i;
  }
}

/// 세션 하나 — 따라 하기 카드. 머리에 「상체 A · 7종목 · 60분」, 펼치면 순서대로
/// 종목 · 기구 · 세트 × 반복 · 휴식 · 요령 한 줄. 오늘 세션은 펼쳐진 채로 시작하고
/// 나머지는 접혀 있습니다 — 오늘 할 것이 첫 화면에 보여야 합니다.
class _SessionCard extends StatefulWidget {
  const _SessionCard({
    super.key,
    required this.session,
    required this.prefs,
    required this.initiallyOpen,
    required this.isToday,
  });
  final Map<String, Object?> session;
  final GymPrefs prefs;
  final bool initiallyOpen;
  final bool isToday;

  @override
  State<_SessionCard> createState() => _SessionCardState();
}

class _SessionCardState extends State<_SessionCard> {
  late bool _open = widget.initiallyOpen;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final exercises = tailorSession(widget.session, widget.prefs);
    /* 설정을 한 번도 안 만진 사람(초보 프리셋)에게 「4종목 바꿈」「대체」「원래 바벨 …」 은
       앱 내부 사정이지 정보가 아닙니다 — 고른 적 없는 사람에게 "원래" 는 없습니다.
       표는 사용자가 기구를 바꾼 뒤에만 뜻이 있습니다. */
    final showTags = !widget.prefs.isBeginnerPreset;
    final changed = showTags ? exercises.where((e) => tailorTag(e) != null).length : 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        border: Border.all(color: t.dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Flexible(
                      child: Text('${widget.session['label']}',
                          style: t.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                    ),
                    if (widget.isToday) ...[
                      const SizedBox(width: 6),
                      const _Tag('오늘', tone: Tone.ok),
                    ],
                  ]),
                  Text(
                      '${exercises.length}종목 · ${n0(widget.session['minutes'])}분'
                      '${changed > 0 ? ' · $changed종목 바꿈' : ''}',
                      style: t.textTheme.labelSmall?.copyWith(color: t.hintColor)),
                ]),
              ),
              Icon(_open ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                  size: 18, color: t.hintColor),
            ]),
          ),
        ),
        if (_open)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (var i = 0; i < exercises.length; i++)
                _ExerciseRow(index: i + 1, exercise: exercises[i], showTags: showTags),
            ]),
          ),
      ]),
    );
  }
}

/// 종목 한 줄(~두 줄): 「1  바벨 벤치프레스 [바벨] [대체]」 그 밑에
/// 「3세트 × 5-8 · 휴식 2분 30초」, 요령은 한 줄 더(길면 줄임 — 자세한 건 헬스 화면).
/// RPE 는 없습니다 — 초보자에게 숫자 하나 더는 물음표 하나 더입니다.
class _ExerciseRow extends StatelessWidget {
  const _ExerciseRow({required this.index, required this.exercise, this.showTags = true});
  final int index;
  final Map<String, Object?> exercise;
  /// 「대체」「익숙」 표와 「원래 X」 를 보일까 — 초보 프리셋에서는 끕니다.
  final bool showTags;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = mb(context);
    final e = exercise;
    final tag = showTags ? tailorTag(e) : null;
    final equip = equipTag(e);
    final note = tailorNote(e, original: showTags);
    final rest = restLabel(e['restSec']);
    /* 건너뛸 수도 있는 종목은 경고색 — 기구가 없으면 없는 것입니다. */
    final skip = '${e['note'] ?? ''}'.contains(kSkipNote);
    final detail = [
      '${n0(e['sets'])}세트 × ${e['reps']}',
      if (rest.isNotEmpty) '휴식 $rest',
    ].join(' · ');
    final small = t.textTheme.labelSmall?.copyWith(color: skip ? c.warn : t.hintColor, height: 1.4);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 20,
          height: 20,
          margin: const EdgeInsets.only(top: 1),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: c.accentSub, shape: BoxShape.circle),
          /* 글자를 키우면(1.3배 이상) 20px 동그라미가 숫자를 잘라 냅니다 — 줄여서 넣습니다. */
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text('$index',
                maxLines: 1,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: t.colorScheme.onSurface)),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              Flexible(
                child: Text('${e['name']}',
                    style: t.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600, color: skip ? c.warn : null)),
              ),
              if (equip != null) ...[const SizedBox(width: 6), _Tag(equip)],
              if (tag != null) ...[
                const SizedBox(width: 4),
                _Tag(tag, tone: tag == '익숙' ? Tone.ok : Tone.none),
              ],
            ]),
            const SizedBox(height: 2),
            Text(detail, style: small),
            if (note != null) Text(note, maxLines: 1, overflow: TextOverflow.ellipsis, style: small),
          ]),
        ),
      ]),
    );
  }
}

/// 작은 표. Pill 보다 한 단계 작습니다 — 종목 이름 옆에 둘씩 붙어도 360px 한 줄에 듭니다.
class _Tag extends StatelessWidget {
  const _Tag(this.text, {this.tone = Tone.none});
  final String text;
  final Tone tone;

  @override
  Widget build(BuildContext context) {
    final c = mb(context);
    final t = Theme.of(context);
    final (fg, bg) = switch (tone) {
      Tone.ok => (c.ok, c.okBg),
      Tone.warn => (c.warn, c.warnBg),
      Tone.bad => (c.bad, c.badBg),
      Tone.none => (t.hintColor, c.accentSub),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(text, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: fg)),
    );
  }
}

class _DietCard extends StatelessWidget {
  const _DietCard({required this.diet});
  final Map<String, Object?> diet;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final meals = ((diet['meals'] as List?) ?? const []).cast<Map<String, Object?>>();
    final notes = ((diet['notes'] as List?) ?? const []).map((n) => '$n').toList();
    return MbCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionTitle('하루 ${n0(diet['mealsPerDay'])}끼 예시',
            trailing: Text('끼니당 단백질 ${n0(diet['proteinPerMeal'])}g',
                style: t.textTheme.labelSmall?.copyWith(color: t.hintColor))),
        for (final m in meals)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text('${m['name']}', style: t.textTheme.bodyMedium),
            subtitle: Text(
                '${n0(m['kcal'])}kcal · 단 ${n0(m['proteinG'])}g · 탄 ${n0(m['carbG'])}g · 지 ${n0(m['fatG'])}g',
                style: t.textTheme.labelSmall?.copyWith(color: t.hintColor)),
            children: [
              for (final o0 in ((m['options'] as List?) ?? const []))
                Builder(builder: (_) {
                  final o = (o0 as Map).cast<String, Object?>();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${o['label']}',
                          style: t.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
                      for (final it in ((o['items'] as List?) ?? const []))
                        Text('· $it', style: t.textTheme.bodySmall),
                    ]),
                  );
                }),
            ],
          ),
        /* 메모 세 줄(단백질 나누기 · 국물 나트륨 · 체중 ±1kg)은 접어 둡니다 —
           끼니 예시가 주인공이고, 메모는 읽고 싶을 때. */
        if (notes.isNotEmpty)
          ExpansionTile(
            key: const Key('diet-notes'),
            dense: true,
            tilePadding: EdgeInsets.zero,
            shape: const Border(),
            collapsedShape: const Border(),
            childrenPadding: const EdgeInsets.only(bottom: 4),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            title: Text('먹을 때 요령 ${notes.length}',
                style: t.textTheme.labelMedium?.copyWith(color: t.hintColor, fontWeight: FontWeight.w600)),
            children: [
              for (final n in notes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('· $n', style: t.textTheme.labelSmall?.copyWith(height: 1.5)),
                ),
            ],
          ),
      ]),
    );
  }
}

class _MilestoneCard extends StatelessWidget {
  const _MilestoneCard({required this.milestones});
  final List<Map<String, Object?>> milestones;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return MbCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SectionTitle('4주마다 이쯤'),
        for (final m in milestones)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              SizedBox(width: 52,
                  child: Text('${n0(m['week'])}주',
                      style: t.textTheme.labelSmall?.copyWith(
                          color: t.hintColor,
                          fontWeight: m['final'] == true ? FontWeight.w800 : null))),
              SizedBox(width: 82, child: Text(dateShort(m['date']), style: t.textTheme.labelSmall)),
              Expanded(
                child: Text(
                    '${n1(m['weightKg'])}kg · 근 ${n1(m['smmKg'])} · 지 ${n1(m['bfmKg'])} '
                    '(${n1(m['pbfPct'])}%)',
                    style: t.textTheme.bodySmall),
              ),
            ]),
          ),
      ]),
    );
  }
}
