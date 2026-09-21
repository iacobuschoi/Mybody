/* =============================================================================
 * goal.dart — P05 목표 설정 + P06 강도 선택
 *
 * 이 화면이 하는 일은 셋입니다:
 *   1. 목표 세 숫자를 받는다 (체중 · 골격근 · 체지방)
 *   2. **그 목표가 만들어도 되는 목표인지** 먼저 따진다 (modes.select)
 *   3. 된다면 상·중·하 세 기간을 계산해서 고르게 한다 (compareLevels)
 *
 * 2번이 이 앱의 성격입니다. 필수지방 아래를 목표로 잡거나, 미성년이
 * 감량을 넣거나, 세 숫자가 서로 안 맞으면 **계획을 안 만듭니다.**
 * 거부할 때는 왜 거부하는지, 그리고 무엇을 고치면 되는지 같이 말합니다.
 *
 * 체지방률 하한과 생리적 필수지방은 **다른 숫자**입니다. 필수지방은
 * "이 밑으로는 살 수 없다", 하한은 "이 앱은 여기까지만 도와준다" 입니다.
 * 섞어 쓰다가 여성 사용자에게 "남성 필수지방은…" 이라고 말한 적이
 * 있습니다. 앱에서 유일하게 "그건 몸에 해롭습니다" 라고 말하는 자리라,
 * 여기서 신뢰를 잃으면 그 말을 지킬 방법이 없습니다.
 * ========================================================================== */
import 'package:flutter/material.dart';
import 'package:mybody_core/mybody_core.dart' as core;

import '../scope.dart';
import '../ui/fmt.dart';
import '../ui/widgets.dart';
import 'intensity.dart';

class GoalScreen extends StatefulWidget {
  const GoalScreen({super.key});
  @override
  State<GoalScreen> createState() => _GoalScreenState();
}

class _GoalScreenState extends State<GoalScreen> {
  final _w = TextEditingController();
  final _s = TextEditingController();
  final _b = TextEditingController();
  int? _deadlineWeeks;
  String? _manualModeId;
  bool _seeded = false;

  @override
  void dispose() {
    _w.dispose();
    _s.dispose();
    _b.dispose();
    super.dispose();
  }

  void _seed(Map<String, Object?> cur, Map<String, Object?> profile, Map<String, Object?>? goal) {
    if (_seeded) return;
    _seeded = true;
    final g = goal ?? _recommend(cur, profile);
    _w.text = core.toFixed(core.jsToNumber(g['weightKg']), 1);
    _s.text = core.toFixed(core.jsToNumber(g['smmKg']), 1);
    _b.text = core.toFixed(core.jsToNumber(g['bfmKg']), 1);
    _deadlineWeeks = goal?['deadlineWeeks'] == null ? null : core.jsToNumber(goal!['deadlineWeeks']).toInt();
    _manualModeId = goal?['manualModeId'] as String?;
  }

  /// 추천 목표 — 체지방률 15%(여 24%) 기준에 근육은 소폭 증가.
  static Map<String, Object?> _recommend(Map<String, Object?> cur, Map<String, Object?> profile) {
    final targetPbf = profile['sex'] == 'male' ? 15.0 : 24.0;
    final smm = core.r1(core.jsToNumber(cur['smmKg']) + 1.0);
    final ffm = smm / core.jsToNumber(cur['smmToFfm']);
    final weight = core.r1(ffm / (1 - targetPbf / 100));
    return {'weightKg': weight, 'smmKg': smm, 'bfmKg': core.r1(weight - ffm)};
  }

  Map<String, Object?> get _goal => {
        'weightKg': double.tryParse(_w.text.trim()),
        'smmKg': double.tryParse(_s.text.trim()),
        'bfmKg': double.tryParse(_b.text.trim()),
        if (_deadlineWeeks != null) 'deadlineWeeks': _deadlineWeeks,
        if (_manualModeId != null) 'manualModeId': _manualModeId,
      };

  @override
  Widget build(BuildContext context) {
    final app = Scope.of(context);
    final scans = app.store.sortedScans();
    if (scans.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('목표 설정')),
        body: const EmptyState(
            title: '먼저 인바디를 넣어야 합니다',
            detail: '지금 어디에 있는지를 알아야 어디로 갈지 정할 수 있습니다.'),
      );
    }

    final profile = app.profile ?? core.kSeedProfile;
    final cur = core.derive(scans.last, profile);
    final saved = app.state['goal'] == null
        ? null
        : (app.state['goal'] as Map).cast<String, Object?>();
    _seed(cur, profile, saved);

    final isMale = profile['sex'] == 'male';
    final floorPct = isMale ? 8 : 15;            // 이 앱이 허용하는 하한
    final essentialPct = isMale ? '2~5' : '10~13'; // 생리적 필수 체지방

    final g = _goal;
    final complete = g['weightKg'] != null && g['smmKg'] != null && g['bfmKg'] != null;
    final sel = complete ? _select(app, cur, g, profile) : null;
    final refused = sel?['refused'] == true;
    final mode = sel?['mode'] == null ? null : (sel!['mode'] as Map).cast<String, Object?>();
    final goalInfo = complete ? core.classifyGoal(cur, g) : null;

    final targetPbf = complete
        ? core.jsToNumber(g['bfmKg']) / core.jsToNumber(g['weightKg']) * 100
        : double.nan;

    return Scaffold(
      appBar: AppBar(title: Text(saved == null ? '목표 설정' : '목표 변경')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        MbCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SectionTitle('현재 (${dateK(scans.last['measuredAt'])})'),
            Row(children: [
              Expanded(child: Stat(label: '체중', value: n1(cur['weightKg']), unit: 'kg')),
              Expanded(child: Stat(label: '골격근', value: n1(cur['smmKg']), unit: 'kg')),
              Expanded(child: Stat(label: '체지방', value: n1(cur['bfmKg']), unit: 'kg')),
              Expanded(child: Stat(label: '체지방률', value: n1(cur['pbfPct']), unit: '%')),
            ]),
          ]),
        ),
        MbCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SectionTitle('목표'),
            _num(_w, '목표 체중', 'kg'),
            _num(_s, '목표 골격근량', 'kg'),
            _num(_b, '목표 체지방량', 'kg'),
            if (goalInfo != null) ...[
              Wrap(spacing: 6, runSpacing: 6, children: [
                Pill('${goalInfo['typeLabel']}'),
                Pill('체중 ${signed(goalInfo['dWeightKg'])}kg'),
                Pill('근육 ${signed(goalInfo['dSmmKg'])}kg'),
                Pill('지방 ${signed(goalInfo['dBfmKg'])}kg'),
              ]),
              if (goalInfo['isConsistent'] != true)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Note(
                    tone: Tone.warn,
                    title: '세 숫자가 서로 안 맞습니다.',
                    /* 체중 = 제지방 + 체지방입니다. 셋을 다 넣으면
                       과결정이라 어긋날 수 있고, 얼마나 어긋났는지를
                       말해 주는 편이 "틀렸습니다" 보다 낫습니다. */
                    text: ' 근육·지방으로 계산한 체중은 '
                        '${n1(goalInfo['impliedWeightKg'])}kg 입니다 '
                        '(${signed(goalInfo['mismatchKg'])}kg 차이).',
                  ),
                ),
            ],
          ]),
        ),
        if (complete && targetPbf.isFinite && targetPbf < floorPct)
          Note(
            tone: Tone.bad,
            title: '목표 체지방률 ${n1(targetPbf)}% 는 이 앱이 도와주는 하한($floorPct%)보다 낮습니다.',
            text: ' 생리적 필수 체지방이 $essentialPct% 이고, 그 근처는 '
                '경기 직전 선수가 짧게만 머무는 구간입니다. 계획을 만들지 않습니다.',
          ),
        MbCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SectionTitle('마감 (선택)'),
            Text('정해 두면 그 안에 되는지 따져 봅니다. 안 되면 안 된다고 말합니다.',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: Theme.of(context).hintColor)),
            const SizedBox(height: 10),
            Wrap(spacing: 8, children: [
              for (final w in [null, 8, 12, 16, 24, 40])
                ChoiceChip(
                  label: Text(w == null ? '없음' : '$w주'),
                  selected: _deadlineWeeks == w,
                  onSelected: (_) => setState(() => _deadlineWeeks = w),
                ),
            ]),
          ]),
        ),
        if (sel != null) ...[
          if (refused)
            Note(tone: Tone.bad, title: '이 목표로는 계획을 만들지 않습니다.', text: ' ${sel['message']}')
          else if (mode != null)
            MbCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SectionTitle('모드 — ${mode['nameKo']}',
                    trailing: sel['manual'] == true ? const Pill('직접 고름') : null),
                Text('${mode['oneLiner']}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.5)),
                const SizedBox(height: 8),
                Text('${sel['reason']}',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: Theme.of(context).hintColor, height: 1.5)),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () => _pickMode(context, sel),
                  child: const Text('다른 모드로 바꾸기'),
                ),
              ]),
            ),
          if (sel['trendNote'] != null)
            Note(tone: Tone.warn, text: '${sel['trendNote']}'),
        ],
        FilledButton(
          onPressed: (!complete || refused || (targetPbf.isFinite && targetPbf < floorPct))
              ? null
              /* **앱이 고른 모드도 같이 넘깁니다.**
                 예전에는 직접 고른 모드만 넘겨서, 앱이 "감량모드" 라고
                 말해 놓고 계획은 아무 제약 없이 만들었습니다 — 그 모드의
                 속도 상한도 단백질 하한도 안 걸렸습니다. 모드를 보여 주는
                 이유가 그 제약 때문인데요. */
              : () => _next(app, g, '${sel?['modeId'] ?? ''}'),
          child: const Text('기간 계산하기'),
        ),
      ]),
    );
  }

  Widget _num(TextEditingController c, String label, String unit) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
              labelText: label, suffixText: unit, border: const OutlineInputBorder()),
        ),
      );

  Map<String, Object?> _select(app, Map<String, Object?> cur, Map<String, Object?> g,
      Map<String, Object?> profile) {
    final gi = core.classifyGoal(cur, g);
    final scans = app.store.sortedScans() as List<Map<String, Object?>>;
    Map<String, Object?>? trend;
    if (scans.length >= 2) {
      final a = core.derive(scans.first, profile);
      final b = core.derive(scans.last, profile);
      final da = DateTime.tryParse('${scans.first['measuredAt']}');
      final db = DateTime.tryParse('${scans.last['measuredAt']}');
      if (da != null && db != null) {
        final days = db.difference(da).inMilliseconds / 86400000;
        trend = {
          'weeksSpan': days / 7,
          'gapDays': days,
          'dWeightKg': core.jsToNumber(b['weightKg']) - core.jsToNumber(a['weightKg']),
          'dSmmKg': core.jsToNumber(b['smmKg']) - core.jsToNumber(a['smmKg']),
          'dBfmKg': core.jsToNumber(b['bfmKg']) - core.jsToNumber(a['bfmKg']),
        };
      }
    }
    final input = <String, Object?>{
      'dWeightKg': gi['dWeightKg'], 'dSmmKg': gi['dSmmKg'], 'dBfmKg': gi['dBfmKg'],
      'curWeightKg': cur['weightKg'], 'curSmmKg': cur['smmKg'], 'curBfmKg': cur['bfmKg'],
      'curPbfPct': cur['pbfPct'], 'curBmi': cur['bmi'],
      'heightCm': profile['heightCm'], 'tdeeKcal': cur['tdeeKcal'],
      'sex': profile['sex'], 'age': profile['age'], 'trainingAge': profile['trainingAge'],
      'hadPriorPeak': core.jsTruthy(profile['hadPriorPeak']),
      'deadlineWeeks': _deadlineWeeks,
      'recentTrend': trend,
      'currentPhase': _phaseFrom(trend),
    };
    final r = core.modeSelect(input);
    if (r['refused'] != true && _manualModeId != null) {
      final m = core.modeById(_manualModeId);
      if (m != null) {
        r['mode'] = m;
        r['modeId'] = m['id'];
        r['manual'] = true;
      }
    }
    return r;
  }

  /// 최근 추세로 지금 어느 국면인지 — 증량 중이면 미니컷 규칙이 열립니다.
  static String? _phaseFrom(Map<String, Object?>? trend) {
    if (trend == null || core.jsToNumber(trend['weeksSpan']) < 4) {
      return null;
    }
    final nw = core.jsToNumber(core.kNoise['weight']);
    final ns = core.jsToNumber(core.kNoise['smm']);
    if (core.jsToNumber(trend['dWeightKg']) > nw &&
        core.jsToNumber(trend['dSmmKg']) > -ns) {
      return 'bulk';
    }
    if (core.jsToNumber(trend['dWeightKg']) < -nw) return 'cut';
    return null;
  }

  Future<void> _pickMode(BuildContext context, Map<String, Object?> sel) async {
    final chosen = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        builder: (ctx, sc) => ListView(controller: sc, padding: const EdgeInsets.all(20), children: [
          Text('모드 고르기', style: Theme.of(ctx).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text('앱이 고른 것이 기본입니다. 바꾸면 그 모드의 속도 상한과 단백질 하한을 따릅니다.',
              style: Theme.of(ctx).textTheme.bodySmall
                  ?.copyWith(color: Theme.of(ctx).hintColor, height: 1.5)),
          const SizedBox(height: 14),
          for (final m0 in core.kModes)
            Builder(builder: (_) {
              final m = (m0 as Map).cast<String, Object?>();
              final why = _whyNot(sel, m);
              return MbCard(
                onTap: () => Navigator.of(ctx).pop('${m['id']}'),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                        child: Text('${m['nameKo']}',
                            style: Theme.of(ctx).textTheme.titleSmall)),
                    if (m['id'] == sel['modeId']) const Pill('앱의 선택', tone: Tone.ok),
                  ]),
                  const SizedBox(height: 4),
                  Text('${m['oneLiner']}',
                      style: Theme.of(ctx).textTheme.bodySmall?.copyWith(height: 1.5)),
                  if (why != null) ...[
                    const SizedBox(height: 8),
                    /* **왜 이건 아닌지**를 같이 말합니다. 고를 수는 있지만,
                       앱이 왜 안 골랐는지 모른 채 고르면 안 됩니다. */
                    Text(why,
                        style: Theme.of(ctx).textTheme.labelSmall
                            ?.copyWith(color: mb(ctx).warn, height: 1.5)),
                  ],
                ]),
              );
            }),
        ]),
      ),
    );
    if (chosen != null) setState(() => _manualModeId = chosen);
  }

  static String? _whyNot(Map<String, Object?> sel, Map<String, Object?> m) {
    for (final a0 in ((sel['alternatives'] as List?) ?? const [])) {
      final a = (a0 as Map).cast<String, Object?>();
      if (a['id'] == m['id']) {
        return '${a['why']}';
      }
    }
    return null;
  }

  void _next(app, Map<String, Object?> g, String modeId) {
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => IntensityScreen(
              goal: g,
              modeId: _manualModeId ?? (modeId.isEmpty ? null : modeId),
            )));
  }
}
