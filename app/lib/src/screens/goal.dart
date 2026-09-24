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
 *
 * 0.2.9 부터 목표를 정하는 길이 둘입니다. 맨 위 두 갈래 버튼으로 고릅니다:
 *   · 체성분으로 정하기 — 위의 1·2·3 (이 파일)
 *   · 기간으로 정하기 — 기간을 먼저 받고 그 안에 되는 몸을 고르는 길 (duration.dart)
 * 체성분 길의 끝은 강도 화면(intensity.dart) — 상·중·하 세 기간 중 하나를 고르는
 * 자리입니다. 기간 길은 주수를 이미 골랐으니 강도 화면을 거치지 않고 기간 판이
 * 그 자리에서 바로 계획을 세워 저장합니다(예전에는 이 길도 강도 화면을 거쳐 기간을
 * 두 번 고르게 했고, 폰에서 첫 반응이 "이미 골랐는데 또 고르라니" 였습니다).
 * 강도 화면이 여섯 달을 넘는 계획 앞에서 「기간으로 정하기」를 권하고 사용자가
 * 그걸 고르면, 그 답을 들고 여기로 돌아와 기간 모드로 바뀝니다.
 * ========================================================================== */
import 'package:flutter/material.dart';
import 'package:mybody_core/mybody_core.dart' as core;

import '../app_state.dart';
import '../scope.dart';
import '../ui/fmt.dart';
import '../ui/widgets.dart';
import 'duration.dart';
import 'intensity.dart';

/// 목표를 정하는 두 길.
enum GoalHow { body, duration }

class GoalScreen extends StatefulWidget {
  const GoalScreen({super.key});
  @override
  State<GoalScreen> createState() => _GoalScreenState();
}

class _GoalScreenState extends State<GoalScreen> {
  final _w = TextEditingController();
  final _s = TextEditingController();
  /// 체지방**률**(%)로 받습니다. 사람은 "15%" 로 생각하지 "12.1kg" 으로
  /// 생각하지 않습니다. 저장은 여전히 kg 입니다 — 엔진과 백업 판이 그걸 봅니다.
  final _p = TextEditingController();
  int? _deadlineWeeks;
  String? _manualModeId;
  bool _seeded = false;
  bool _showWhy = false;
  GoalHow _how = GoalHow.body;

  /* **세 칸 중 둘을 정하면 나머지 하나는 따라옵니다.**
     체중 = 제지방 + 체지방이고 제지방은 골격근에 비례하니(지금 몸의 비율),
     셋을 다 손으로 넣으면 서로 안 맞기 마련이고 앱은 그때 계획을 안
     만듭니다. 마지막에 만진 두 칸을 남기고 나머지를 계산합니다. */
  final _recent = <String>['w', 's'];
  double _k = double.nan; // 지금 몸의 골격근/제지방 비율

  String get _auto =>
      (['w', 's', 'p']..removeWhere(_recent.contains)).single;

  void _edited(String key) {
    _recent.remove(key);
    _recent.add(key);
    if (_recent.length > 2) _recent.removeAt(0);
    _recalc();
    setState(() {});
  }

  void _recalc() {
    final w = double.tryParse(_w.text.trim());
    final sm = double.tryParse(_s.text.trim());
    final pct = double.tryParse(_p.text.trim());
    if (!_k.isFinite || _k <= 0) return;
    switch (_auto) {
      case 'w':
        if (sm == null || pct == null || pct <= 0 || pct >= 100) return;
        _w.text = core.toFixed(sm / _k / (1 - pct / 100), 1);
      case 's':
        if (w == null || pct == null || w <= 0 || pct <= 0 || pct >= 100) return;
        _s.text = core.toFixed(w * (1 - pct / 100) * _k, 1);
      default:
        if (w == null || sm == null || w <= 0) return;
        _p.text = core.toFixed((w - sm / _k) / w * 100, 1);
    }
  }

  @override
  void dispose() {
    _w.dispose();
    _s.dispose();
    _p.dispose();
    super.dispose();
  }

  void _seed(Map<String, Object?> cur, Map<String, Object?> profile, Map<String, Object?>? goal) {
    if (_seeded) return;
    _seeded = true;
    final g = goal ?? _recommend(cur, profile);
    _k = core.jsToNumber(cur['smmToFfm']);
    _w.text = core.toFixed(core.jsToNumber(g['weightKg']), 1);
    _s.text = core.toFixed(core.jsToNumber(g['smmKg']), 1);
    _p.text = core.toFixed(
        core.jsToNumber(g['bfmKg']) / core.jsToNumber(g['weightKg']) * 100, 1);
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

  /// 마감 칩. 기간 화면에서 온 목표의 주수(예: 20주)는 칩에 없을 수 있어서
  /// 그 값도 한 칸 넣습니다 — 안 넣으면 골라져 있는데 안 보입니다.
  List<int?> get _deadlineChoices {
    const base = [8, 12, 16, 24, 40];
    final d = _deadlineWeeks;
    final all = [...base, if (d != null && !base.contains(d)) d]..sort();
    return [null, ...all];
  }

  Map<String, Object?> get _goal {
    final w = double.tryParse(_w.text.trim());
    final pct = double.tryParse(_p.text.trim());
    return {
        'weightKg': w,
        'smmKg': double.tryParse(_s.text.trim()),
        'bfmKg': (w == null || pct == null) ? null : core.r1(w * pct / 100),
        if (_deadlineWeeks != null) 'deadlineWeeks': _deadlineWeeks,
        if (_manualModeId != null) 'manualModeId': _manualModeId,
      };
  }

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

    return Scaffold(
      appBar: AppBar(title: Text(saved == null ? '목표 설정' : '목표 변경')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        _chooser(),
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
        if (_how == GoalHow.duration)
          /* 마감 칩을 골라 뒀으면 기간 판도 그 주수에서 엽니다 — 강도 화면이 「기간으로
             정하기」를 권해서 돌아온 사람은 방금 그 마감으로 계산해 보고 온 것입니다. */
          DurationPanel(
              key: const Key('duration-panel'),
              initialWeeks: _deadlineWeeks ?? kDurationDefault)
        else
          ..._bodyForm(context, app, cur, profile),
      ]),
    );
  }

  /* 두 갈래. 몸의 숫자를 먼저 정하는 원래 길과, 기간을 먼저 정하고 그 안에
     되는 몸을 고르는 길. 처음 여는 사람에게는 "12.1kg" 보다 "석 달" 이 더
     잡히는 말입니다. 기간 판은 화면을 하나 더 밀지 않고 이 자리에 대신
     섭니다 — 판이 계획을 세우면 한 번 pop 해서 자기가 선 화면을 닫고 셸로
     돌아가는데, 그 화면이 이 화면이어야 합니다. 판을 따로 밀어 올렸다면 판만
     닫히고 목표 화면이 남습니다(체성분 길의 강도 화면은 이 화면 위에 밀려
     있어서 두 번 pop 합니다 — 그쪽은 그대로입니다). */
  Widget _chooser() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SegmentedButton<GoalHow>(
        segments: const [
          ButtonSegment(value: GoalHow.body, label: Text('체성분으로 정하기')),
          ButtonSegment(value: GoalHow.duration, label: Text('기간으로 정하기')),
        ],
        selected: {_how},
        showSelectedIcon: false,
        expandedInsets: EdgeInsets.zero,
        onSelectionChanged: (s) => setState(() => _how = s.first),
      ),
    );
  }

  /// 체성분으로 정하기 — 세 숫자를 받고, 모드를 따지고, 기간을 계산하러 갑니다.
  List<Widget> _bodyForm(BuildContext context, AppState app, Map<String, Object?> cur,
      Map<String, Object?> profile) {
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

    return [
      MbCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SectionTitle('목표'),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text('세 칸 중 두 칸을 정하면 나머지 한 칸은 자동으로 맞춥니다. '
                '자동 칸은 (자동) 으로 표시됩니다.',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: Theme.of(context).hintColor, height: 1.5)),
          ),
          _num(_w, 'w', '목표 체중', 'kg'),
          _num(_s, 's', '목표 골격근량', 'kg'),
          _num(_p, 'p', '목표 체지방률', '%'),
          if (goalInfo != null) ...[
            Wrap(spacing: 6, runSpacing: 6, children: [
              /* 이건 숫자가 가리키는 **방향**이고, 아래 모드는 규칙이 고른
                 것이라 둘이 다를 수 있습니다(리컴프 방향인데 감량모드).
                 이름표 없이 두면 한 화면이 두 말을 하는 것처럼 보입니다. */
              Pill('목표 방향 · ${goalInfo['typeLabel']}'),
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
            for (final w in _deadlineChoices)
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
              /* 왜 이 모드인지는 길고 숫자가 많습니다. 한 줄만 두고,
                 궁금하면 「자세히」. */
              if (_showWhy) ...[
                const SizedBox(height: 8),
                Text('${sel['reason']}',
                    key: const Key('mode-reason'),
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: Theme.of(context).hintColor, height: 1.5)),
              ],
              const SizedBox(height: 6),
              Row(children: [
                TextButton(
                  onPressed: () => setState(() => _showWhy = !_showWhy),
                  child: Text(_showWhy ? '접기' : '자세히'),
                ),
                TextButton(
                  onPressed: () => _pickMode(context, sel),
                  child: const Text('다른 모드로 바꾸기'),
                ),
              ]),
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
    ];
  }

  Widget _num(TextEditingController c, String key, String label, String unit) {
    final auto = _auto == key;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onChanged: (_) => _edited(key),
        decoration: InputDecoration(
          labelText: auto ? '$label (자동)' : label,
          suffixText: unit,
          helperText: auto ? '나머지 두 칸으로 계산됩니다 — 직접 고치면 다른 칸이 자동이 됩니다' : null,
          border: const OutlineInputBorder(),
          filled: auto,
        ),
      ),
    );
  }

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

  Future<void> _next(app, Map<String, Object?> g, String modeId) async {
    final answer = await Navigator.of(context).push<Object?>(MaterialPageRoute(
        builder: (_) => IntensityScreen(
              goal: g,
              modeId: _manualModeId ?? (modeId.isEmpty ? null : modeId),
            )));
    /* 강도 화면이 「기간으로 정하기」를 들고 돌아오면 기간 모드로. 계획을
       세우고 돌아온 길(두 번 pop)에서는 이 화면도 같이 내려가서 여기 안 옵니다. */
    if (!mounted || answer != IntensityScreen.pickDuration) return;
    setState(() => _how = GoalHow.duration);
  }
}
