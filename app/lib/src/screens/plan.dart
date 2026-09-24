/* =============================================================================
 * plan.dart — P07 플랜 (위에서 플랜 / 달성률 을 고릅니다)
 *
 * 계획 한 벌을 펼쳐 보여 줍니다: 기간과 목표일, 주차별 궤적, 매크로,
 * 운동 분할, 식단 예시, 마일스톤.
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
import '../workout/planner.dart';
import '../workout/prefs.dart';
import 'gym_settings.dart';

class PlanScreen extends StatefulWidget {
  const PlanScreen({super.key, required this.go});
  final void Function(String route, [Object? arg]) go;

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
        detail: '목표를 정하면 주차별 궤적과 식단·운동 처방을 만듭니다.',
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
    final c = mb(context);
    final traj = ((plan['trajectory'] as List?) ?? const []).cast<Map<String, Object?>>();
    final macros = (plan['macros'] as Map?)?.cast<String, Object?>();
    final workout = (plan['workout'] as Map?)?.cast<String, Object?>();
    final diet = (plan['diet'] as Map?)?.cast<String, Object?>();
    final feas = (plan['feasibility'] as Map?)?.cast<String, Object?>();
    final goal = (plan['goal'] as Map?)?.cast<String, Object?>();

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

      if (traj.length > 1)
        MbCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SectionTitle('주차별 궤적'),
            LineChart(
              height: 170,
              series: [
                Series(label: '체지방', color: c.fat, dots: false,
                    points: [for (final t in traj) Pt(core.jsToNumber(t['week']), core.jsToNumber(t['bfmKg']))]),
                Series(label: '골격근', color: c.muscle, dots: false,
                    points: [for (final t in traj) Pt(core.jsToNumber(t['week']), core.jsToNumber(t['smmKg']))]),
              ],
              goals: [
                if (goal != null)
                  GoalLine(y: core.jsToNumber(goal['bfmKg']), color: c.fat, label: '목표 지방'),
                if (goal != null)
                  GoalLine(y: core.jsToNumber(goal['smmKg']), color: c.muscle, label: '목표 근육'),
              ],
              xTickFmt: (v) => '${v.round()}주',
            ),
          ]),
        ),

      if (macros != null)
        MbCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SectionTitle('하루 식단 목표',
                trailing: Text('TDEE ${n0(macros['tdeeKcal'])}kcal',
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
            Text(
                '단백질 ${n1(macros['proteinPerFFM'])} g/kg FFM · '
                '체중당 ${n1(macros['proteinPerBW'])} g/kg',
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: Theme.of(context).hintColor)),
          ]),
        ),

      if (workout != null)
        _WorkoutCard(
            workout: workout,
            prefs: GymPrefs.fromSettings((st['settings'] as Map?)?.cast<String, Object?>())),
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

class _WorkoutCard extends StatelessWidget {
  const _WorkoutCard({required this.workout, required this.prefs});
  final Map<String, Object?> workout;

  /// 운동 장소 · 기구 · 익숙한 종목. 종목 목록은 이 설정을 거쳐서 보입니다.
  final GymPrefs prefs;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = mb(context);
    final sessions = ((workout['sessions'] as List?) ?? const []).cast<Map<String, Object?>>();
    final small = t.textTheme.labelSmall?.copyWith(color: t.hintColor);
    return MbCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionTitle('${workout['splitName']}',
            trailing: Text('주 ${n0(workout['daysPerWeek'])}회 · ${n0(workout['sessionMinutes'])}분',
                style: small)),
        Text('근육군당 주 ${n0(workout['setsPerMuscle'])}세트 · 유산소 주 ${n0(workout['cardioMinPerWeek'])}분',
            style: t.textTheme.bodySmall?.copyWith(color: t.hintColor)),
        const SizedBox(height: 4),
        Text('${workout['cardioPlan']}', style: t.textTheme.bodySmall),
        const SizedBox(height: 10),
        for (final b in ((workout['inbodyBias'] as List?) ?? const []))
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('· $b', style: t.textTheme.labelSmall?.copyWith(height: 1.5)),
          ),
        const SizedBox(height: 8),

        /* 기구 · 익숙한 종목 — 종목 목록은 이 설정을 거쳐서 보입니다. 설정 화면
           깊숙이에만 있으면 "전혀 반영 안 됐다" 가 됩니다(주인이 0.2.9 를 써 보고
           그렇게 말했습니다). 요약 한 줄과 여는 단추를 종목 바로 위에 둡니다. */
        Container(
          margin: const EdgeInsets.only(bottom: 4),
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
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text('아래 종목은 이 설정에 맞춘 것입니다 — 바꾼 종목에는 원래 종목을 적어 둡니다.',
              style: small?.copyWith(height: 1.5)),
        ),

        for (final s in sessions)
          if (s['rest'] != true) _SessionTile(session: s, prefs: prefs),
        Text('${workout['progression']}',
            style: t.textTheme.labelSmall?.copyWith(color: t.hintColor, height: 1.5)),
      ]),
    );
  }
}

/// 세션 하나 — 접혀 있고, 펼치면 기구에 맞춘 종목들. 바꾼 종목에는 「대체」 · 「익숙」
/// 표를 붙입니다. 표시 규칙은 tailorSession 의 메모 접두어를 그대로 읽습니다.
class _SessionTile extends StatelessWidget {
  const _SessionTile({required this.session, required this.prefs});
  final Map<String, Object?> session;
  final GymPrefs prefs;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = mb(context);
    final exercises = tailorSession(session, prefs);
    final changed = exercises.where((e) => tailorTag(e) != null).length;
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 8),
      title: Text('${session['label']}', style: t.textTheme.bodyMedium),
      subtitle: Text(
          '${exercises.length}종목 · ${n0(session['minutes'])}분'
          '${changed > 0 ? ' · $changed종목 바꿈' : ''}',
          style: t.textTheme.labelSmall?.copyWith(color: t.hintColor)),
      children: [
        for (final e in exercises)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Row(children: [
              Flexible(child: Text('${e['name']}', style: t.textTheme.bodySmall)),
              if (tailorTag(e) != null) ...[
                const SizedBox(width: 6),
                Pill(tailorTag(e)!, tone: tailorTag(e) == '익숙' ? Tone.ok : Tone.none),
              ],
            ]),
            subtitle: Text(
                '${n0(e['sets'])}세트 × ${e['reps']} · 휴식 ${n0(e['restSec'])}초 · RPE ${e['rpe']}'
                '${core.jsTruthy(e['note']) ? ' · ${e['note']}' : ''}',
                style: t.textTheme.labelSmall?.copyWith(color: t.hintColor)),
            /* 건너뛸 수도 있는 종목은 흐리게 — 기구가 없으면 없는 것입니다. */
            textColor: '${e['note'] ?? ''}'.contains(kSkipNote) ? c.warn : null,
          ),
      ],
    );
  }
}

/// 종목에 붙는 표. 대체됐으면 '대체', 잘 아는 종목으로 바꿨으면 '익숙', 아니면 null.
String? tailorTag(Map<String, Object?> e) {
  final note = '${e['note'] ?? ''}';
  if (note.startsWith(kFamiliarPrefix)) return '익숙';
  if (note.startsWith(kSubstitutePrefix)) return '대체';
  return null;
}
class _DietCard extends StatelessWidget {
  const _DietCard({required this.diet});
  final Map<String, Object?> diet;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final meals = ((diet['meals'] as List?) ?? const []).cast<Map<String, Object?>>();
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
        const SizedBox(height: 8),
        for (final n in ((diet['notes'] as List?) ?? const []))
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('· $n', style: t.textTheme.labelSmall?.copyWith(height: 1.5)),
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
