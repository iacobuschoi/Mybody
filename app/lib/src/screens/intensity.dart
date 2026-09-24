/* =============================================================================
 * intensity.dart — P06 강도 선택
 *
 * **강도는 난이도 라벨이 아니라 기간입니다.** 상/중/하는 "얼마나 빡세게"
 * 가 아니라 "얼마나 빨리 갈 것인가" 이고, 세 장의 카드는 세 개의 날짜입니다.
 *
 * 그리고 빡셀수록 빠른 게 아닙니다. 적자가 크면 근육이 거의 안 늘어서
 * 근육 목표가 있을 때는 **가장 공격적인 계획이 오히려 더 걸립니다.**
 * 엔진이 그 역설을 찾으면 여기서 그대로 보여 줍니다 — 숨기면 사용자는
 * 무작정 상을 고르고, 그게 제일 느린 길입니다.
 *
 * **같은 계획이 되는 강도는 한 장으로 합칩니다.** 모드의 속도 하한에 붙거나
 * 근육이 기간을 정하는 목표에서는 상 · 중 · 하가 공격성 · 기간 · 식단까지 똑같은
 * 계획이 됩니다. 똑같은 카드 세 장은 고를 것이 있는 척을 합니다(웹 P06 과 같은 규칙).
 *
 * **26주(여섯 달)를 넘는 계획은 시작 전에 한 번 더 묻습니다.** 긴 계획은 첫 두
 * 달의 열의로 시작해서 다음 두 달에 사라집니다. 막지는 않습니다 — 「그대로
 * 가기」가 늘 열려 있습니다. 대신 기간을 먼저 정하고 그 안에 되는 몸을 고르는
 * 길(duration.dart)이 있다고 말하고, 그쪽을 고르면 목표 화면으로 돌아갑니다.
 * 기간 화면에서 온 목표는 이미 기간을 골랐으니 다시 묻지 않습니다.
 *
 * **막힌(blocked) 계획은 저장하지 않습니다.** 필수지방 아래로 내려가거나 근육 상한을
 * 넘는 목표는 카드에 빨간 판정이 붙는데, 예전에는 그 카드가 추천이면 그대로 골라져
 * 있어서 「시작하기」 한 번에 저장됐습니다. 처음 골라 두는 카드도, 시작 단추도 막힌
 * 카드를 거릅니다 — 고를 수 있는 카드가 없으면 단추가 닫힙니다.
 *
 * **기간 화면에서 온 목표는 고른 주수에 가장 가까운 카드를 먼저 골라 둡니다.** 그쪽에서
 * "12주" 를 고르고 왔는데 추천이 18주 카드면 고른 것과 다른 계획이 골라져 있는 셈입니다.
 * 마감 ±1주 안에 카드가 여럿이면 그 옵션의 공격성(a)이 가장 가까운 카드입니다.
 * ========================================================================== */
import 'package:flutter/material.dart';
import 'package:mybody_core/mybody_core.dart' as core;

import '../scope.dart';
import '../ui/charts.dart';
import '../ui/fmt.dart';
import '../ui/symbols.dart';
import '../ui/widgets.dart';

/// 강도 표(compareLevels 의 답)를 만드는 자리. 앱은 엔진을 쓰고, 시험은 손으로
/// 만든 표를 넣어 고르는 규칙만 따로 봅니다(기간 판의 DurationCompute 와 같은 이유).
typedef IntensityCompute = Map<String, Object?> Function(Map<String, Object?> goal);

class IntensityScreen extends StatefulWidget {
  const IntensityScreen({
    super.key,
    required this.goal,
    this.modeId,
    this.fromDuration = false,
    this.preferA,
    this.compute,
  });
  final Map<String, Object?> goal;
  /// 앱이 고른 모드이거나 사용자가 직접 고른 모드. 이 모드의 속도 상한과
  /// 단백질 하한이 계획에 그대로 걸립니다 — 그게 모드를 두는 이유입니다.
  final String? modeId;

  /// 기간 화면(duration.dart)에서 기간을 이미 골라 온 목표. 여섯 달 규칙을
  /// 다시 묻지 않습니다. 목표 표 안에 표시를 넣지 않고 여기 두는 이유는,
  /// 저장되는 목표에 화면 사정이 섞이면 안 되기 때문입니다.
  final bool fromDuration;

  /// 기간 화면에서 고른 옵션의 공격성(a). 마감 ±1주 안에 카드가 여럿이면 이 값에
  /// 가장 가까운 카드를 먼저 골라 둡니다 — 같은 주수라도 식단이 다른 카드가 있습니다.
  final double? preferA;

  /// 강도 표를 만드는 자리. 없으면 엔진(compareLevels).
  final IntensityCompute? compute;

  /// 「기간으로 정하기」를 고르면 이 값을 들고 뒤로 갑니다. 목표 화면은
  /// 이걸 받으면 기간 모드로 바뀝니다.
  static const String pickDuration = 'pickDuration';

  @override
  State<IntensityScreen> createState() => _IntensityScreenState();
}

class _IntensityScreenState extends State<IntensityScreen> {
  Map<String, Object?>? _cmp;
  String? _level;
  bool _busy = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_cmp != null) return;
    final app = Scope.of(context);
    final scans = app.store.sortedScans();
    if (scans.isEmpty) {
      setState(() => _busy = false);
      return;
    }
    final profile = app.profile ?? core.kSeedProfile;
    final modeDef = widget.modeId == null ? null : core.modeById(widget.modeId);
    final compute = widget.compute;
    final cmp = compute != null
        ? compute(widget.goal)
        : core.compareLevels(
            scans.last, profile, widget.goal,
            app.store.dayKey(),
            widget.goal['deadlineWeeks'],
            modeDef,
          );
    setState(() {
      _cmp = cmp;
      _level = initialLevel(
        resultsOf(cmp),
        cmp['recommended'],
        deadlineWeeks: widget.fromDuration ? widget.goal['deadlineWeeks'] : null,
        preferA: widget.preferA,
      );
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_busy) {
      return Scaffold(
        appBar: AppBar(title: const Text('기간 고르기')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final cmp = _cmp;
    if (cmp == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('기간 고르기')),
        body: const EmptyState(title: '먼저 인바디를 넣어야 합니다'),
      );
    }
    if (cmp['impossible'] == true) {
      return Scaffold(
        appBar: AppBar(title: const Text('기간 고르기')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          for (final w in (cmp['warnings'] as List)) Note(tone: Tone.bad, text: '$w'),
          const Note(
            text: '목표를 조금 낮추거나 마감을 늘리면 계산이 됩니다. '
                '거짓 날짜를 만들어 드리지는 않습니다.',
          ),
        ]),
      );
    }

    final results = resultsOf(cmp);
    final groups = levelGroups(results, cmp['recommended']);
    final c = mb(context);
    final t = Theme.of(context);
    final small = t.textTheme.bodySmall?.copyWith(color: t.hintColor, height: 1.5);
    final noneOpen = results.isNotEmpty && results.every(isBlocked);
    /* 기간 화면에서 온 목표인데 고른 주수 ±1주 안에 카드가 없으면 그렇다고 말합니다 —
       "12주로 골랐는데 왜 15주짜리가 골라져 있지" 를 화면이 먼저 답해야 합니다. */
    final offDeadline = widget.fromDuration &&
        results.isNotEmpty &&
        closestToDeadline(results, widget.goal['deadlineWeeks']) != null &&
        !results.any((r) => isNearDeadline(r, widget.goal['deadlineWeeks']));

    return Scaffold(
      appBar: AppBar(title: const Text('기간 고르기')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        _NotesCard(cmp: cmp),
        if (noneOpen)
          const Note(
            key: Key('all-blocked'),
            tone: Tone.bad,
            text: '고를 수 있는 계획이 없습니다 — 세 강도 모두 필수지방 아래이거나 근육 상한 '
                '너머입니다. 목표를 조금 올리거나 낮추면 계산이 됩니다.',
          ),
        if (offDeadline)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text('기간으로 고른 계획입니다 — 카드의 기간이 고른 주수와 조금 다를 수 있습니다',
                key: const Key('duration-note'), style: small),
          ),

        for (final g in groups) _LevelCard(
          r: g.rep,
          levels: g.levels,
          selected: g.levels.any((r) => r['level'] == _level),
          recommended: g.levels.any((r) => cmp['recommended'] == r['level']),
          onTap: () => setState(() => _level = '${g.rep['level']}'),
        ),
        if (groups.length < results.length)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            /* 셋이 다 합쳐졌을 때만 "강도를 바꿔도 같다" — 둘만 합쳐졌으면 바로 위 두 카드가
               서로 다른데 그렇게 말했습니다. */
            child: Text(
              groups.length == 1
                  ? '같은 계획이 되는 강도는 한 장으로 합쳤습니다. 이 목표에서는 강도를 바꿔도 '
                      '기간 · 식단 · 운동이 같습니다.'
                  : '같은 계획이 되는 강도는 한 장으로 합쳤습니다. 이 목표에서는 '
                      '${groups.firstWhere((g) => g.levels.length > 1).subject} 같은 계획입니다.',
              style: small,
            ),
          ),

        MbCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SectionTitle('주차별 궤적'),
            LineChart(
              height: 170,
              series: [
                Series(
                  label: '체지방',
                  color: c.fat,
                  dots: false,
                  points: _pts(_shown(results), 'bfmKg'),
                ),
                Series(
                  label: '골격근',
                  color: c.muscle,
                  dots: false,
                  points: _pts(_shown(results), 'smmKg'),
                ),
              ],
              goals: [
                GoalLine(y: core.jsToNumber(widget.goal['bfmKg']), color: c.fat, label: '목표 지방'),
                GoalLine(y: core.jsToNumber(widget.goal['smmKg']), color: c.muscle, label: '목표 근육'),
              ],
              xTickFmt: (v) => '${v.round()}주',
            ),
          ]),
        ),

        FilledButton(
          onPressed: _level == null ? null : () => _start(cmp),
          child: const Text('이 계획으로 시작하기'),
        ),
      ]),
    );
  }

  /// 고른 카드. 아무것도 안 골랐으면(고를 수 있는 카드가 없을 때) null.
  Map<String, Object?>? _selected(List<Map<String, Object?>> results) {
    for (final r in results) {
      if (r['level'] == _level) return r;
    }
    return null;
  }

  /// 궤적 그래프가 그릴 카드 — 고른 것이 없어도 그래프는 비워 두지 않습니다.
  Map<String, Object?> _shown(List<Map<String, Object?>> results) =>
      _selected(results) ?? results.first;

  static List<Pt> _pts(Map<String, Object?> r, String key) {
    final traj = ((r['sim'] as Map)['trajectory'] as List).cast<Map<String, Object?>>();
    return [
      for (final t in traj)
        Pt(core.jsToNumber(t['week']), core.jsToNumber(t[key])),
    ];
  }

  /// 시작 전 여섯 달 규칙. 긴 계획이면 묻고, 「기간으로 정하기」면 답을 들고
  /// 목표 화면으로 돌아갑니다 — 기간 판은 그쪽이 엽니다. 막힌 카드는 묻기 전에
  /// 거릅니다 — 물어 놓고 「그대로 가기」에서 거절하면 두 번 말하는 셈입니다.
  Future<void> _start(Map<String, Object?> cmp) async {
    final results = resultsOf(cmp);
    final sel = _selected(results);
    if (sel == null || isBlocked(sel)) {
      toast(context, sel == null ? kNoOpenLevelMessage : blockedMessage(sel));
      return;
    }
    final weeks = sel['weeks'];
    if (!widget.fromDuration && isLongGoal(weeks)) {
      final choice = await showLongGoalDialog(context, weeks);
      if (!mounted || choice == null) return;
      if (choice == LongGoalChoice.pickDuration) {
        Navigator.of(context).pop(IntensityScreen.pickDuration);
        return;
      }
    }
    _commit(cmp);
  }

  void _commit(Map<String, Object?> cmp) {
    /* _start 가 이미 걸렀지만 여기서 한 번 더 — 저장하는 자리가 마지막 문입니다. */
    final sel = _selected(resultsOf(cmp));
    if (sel == null || isBlocked(sel)) {
      toast(context, sel == null ? kNoOpenLevelMessage : blockedMessage(sel));
      return;
    }
    final app = Scope.of(context);
    final scans = app.store.sortedScans();
    final profile = app.profile ?? core.kSeedProfile;
    final plan = core.buildPlan(cmp, _level, scans.isEmpty ? null : scans.last, profile);
    if (plan == null) {
      toast(context, '계획을 만들지 못했습니다');
      return;
    }
    app.store.setGoal(widget.goal);
    app.store.setPlan(plan);
    if (!app.store.saved()) {
      toast(context, '기기에 저장하지 못했습니다 — 계획이 남지 않습니다');
      return;
    }
    Navigator.of(context)
      ..pop()
      ..pop();
    toast(context, '계획을 세웠습니다');
  }
}

/// 여섯 달. 이보다 긴 계획은 시작 전에 한 번 더 묻습니다.
const int kLongGoalWeeks = 26;

/// 26주가 여섯 달입니다(26 / 4.345 = 5.98). 27 · 28주는 달로 반올림하면 도로 6개월이라
/// "26주를 넘어서 묻는데 약 6개월" 이 되므로, 그때는 「6개월을 넘깁니다」 로 말합니다.
const int kLongGoalMonths = 6;

bool isLongGoal(Object? weeks) =>
    weeks != null && core.jsToNumber(weeks) > kLongGoalWeeks;

/// 마감 근처로 치는 폭 — 고른 주수 ±1주.
const int kDeadlineSlackWeeks = 1;

/// 막힌 카드를 시작하려 할 때의 말(고를 수 있는 카드가 하나도 없을 때).
const String kNoOpenLevelMessage = '고를 수 있는 계획이 없습니다 — 목표를 조금 올리세요';

/// compareLevels 의 results. 없으면 빈 목록(impossible 일 때도 이 모양입니다).
List<Map<String, Object?>> resultsOf(Map<String, Object?> cmp) => [
      for (final r in (cmp['results'] as List?) ?? const [])
        if (r is Map) r.cast<String, Object?>(),
    ];

/// 엔진이 막은 카드 — 필수지방 아래이거나 근육 상한 너머. 고르지도, 저장하지도 않습니다.
bool isBlocked(Map<String, Object?> r) =>
    (r['feasibility'] is Map) && (r['feasibility'] as Map)['verdict'] == 'blocked';

/// 막힌 카드를 시작하려 할 때의 말. 막히는 이유는 둘(필수지방 아래 · 근육 상한 너머)이고,
/// 거의 언제나 앞의 것입니다 — 근육 상한은 목표 화면이 먼저 거르니까요.
String blockedMessage(Map<String, Object?> r) {
  final feas = r['feasibility'];
  final why = feas is Map ? '${feas['message'] ?? ''}' : '';
  if (why.contains('골격근') || why.contains('상한')) {
    return '이 계획은 목표 골격근량이 약물 없이 닿는 상한을 넘어서 만들 수 없습니다 — 근육 목표를 조금 낮추세요';
  }
  return '이 계획은 필수지방 아래로 내려가서 만들 수 없습니다 — 목표를 조금 올리세요';
}

/// 그 카드의 기간이 고른 주수 ±1주 안인가.
bool isNearDeadline(Map<String, Object?> r, Object? deadlineWeeks) {
  final dl = core.jsToNumber(deadlineWeeks);
  return dl.isFinite && dl > 0 &&
      (core.jsToNumber(r['weeks']) - dl).abs() <= kDeadlineSlackWeeks;
}

/// 고른 주수에 가장 가까운 카드. 같은 거리면 더 긴(여유로운) 쪽, 그것도 같으면 a 가
/// 작은 쪽. 마감 ±1주 안에 카드가 있고 [preferA] 가 있으면, 그 안에서 a 가 가장
/// 가까운 카드입니다 — 기간 화면이 보여 준 식단과 같은 카드를 고르려는 것입니다.
/// 마감이 없거나(0 · null) 카드가 없으면 null.
Map<String, Object?>? closestToDeadline(
    List<Map<String, Object?>> results, Object? deadlineWeeks, {double? preferA}) {
  final dl = core.jsToNumber(deadlineWeeks);
  if (results.isEmpty || !dl.isFinite || dl <= 0) return null;
  double w(Map<String, Object?> r) => core.jsToNumber(r['weeks']);
  double a(Map<String, Object?> r) => core.jsToNumber(r['a']);
  final near = [for (final r in results) if (isNearDeadline(r, dl)) r];
  final byA = near.isNotEmpty && preferA != null;
  final pool = byA ? near : results;
  double score(Map<String, Object?> r) => byA ? (a(r) - preferA).abs() : (w(r) - dl).abs();
  Map<String, Object?>? best;
  for (final r in pool) {
    if (best == null) {
      best = r;
      continue;
    }
    final d = score(r) - score(best);
    final tie = d.abs() < 1e-9;
    if (d < -1e-9 || (tie && (w(r) > w(best) || (w(r) == w(best) && a(r) < a(best))))) {
      best = r;
    }
  }
  return best;
}

/// 처음 골라 둘 강도. 막힌 카드는 고르지 않습니다 — 고를 수 있는 카드가 없으면 null
/// (시작 단추가 닫힙니다). [deadlineWeeks] 가 있으면(기간 화면에서 온 목표) 추천이
/// 아니라 그 주수에 가장 가까운 카드([closestToDeadline]), 아니면 추천, 추천이 막혔으면
/// 첫 번째 열린 카드.
String? initialLevel(List<Map<String, Object?>> results, Object? recommended,
    {Object? deadlineWeeks, double? preferA}) {
  final open = [for (final r in results) if (!isBlocked(r)) r];
  if (open.isEmpty) return null;
  final near = closestToDeadline(open, deadlineWeeks, preferA: preferA);
  if (near != null) return '${near['level']}';
  for (final r in open) {
    if (recommended != null && r['level'] == recommended) return '${r['level']}';
  }
  return '${open.first['level']}';
}

enum LongGoalChoice { proceed, pickDuration }

/// 긴 계획 앞의 물음. 닫으면(null) 아무것도 하지 않습니다 — 저장도, 이동도.
Future<LongGoalChoice?> showLongGoalDialog(BuildContext context, Object? weeks) {
  final w = core.jsToNumber(weeks);
  return showDialog<LongGoalChoice>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('장기 목표는 동기를 잃기 쉬워요!'),
      content: Text('이 계획은 ${longGoalSpan(w)}. '
          '기간별로 가능한 계획을 추천해 드릴까요?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(LongGoalChoice.proceed),
          child: const Text('그대로 가기'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(LongGoalChoice.pickDuration),
          child: const Text('기간으로 정하기'),
        ),
      ],
    ),
  );
}

/// 물음 속 기간 — '30주(약 7개월)입니다' 또는, 달로 반올림하면 도로 6개월이 되는
/// 27 · 28주에는 '27주로 6개월을 넘깁니다'. 제목이 "장기" 라는데 본문이 "약 6개월" 이면
/// 여섯 달 규칙과 어긋나 보입니다.
String longGoalSpan(num weeks) {
  final months = (weeks / 4.345).round();
  return months <= kLongGoalMonths
      ? '${n0(weeks)}주로 $kLongGoalMonths개월을 넘깁니다'
      : '${n0(weeks)}주(약 $months개월)입니다';
}

/// 같은 계획이 되는 강도 묶음. [rep] 은 추천이 들어 있으면 추천, 아니면 첫 강도.
class LevelGroup {
  LevelGroup(this.levels, this.rep);
  final List<Map<String, Object?>> levels;
  final Map<String, Object?> rep;

  /// '상·중·하'
  String get names => levels.map((r) => '${r['label']}').join('·');

  /// 조사까지 — '상·중·하가', '상·중이'
  String get subject => '$names${names.endsWith('하') ? '가' : '이'}';
}

/// 공격성 a 와 기간이 같으면 같은 계획입니다(엔진이 같은 점을 고른 것). 유지 계획은
/// a 가 모두 0 이어도 기간이 4 · 8 · 12주로 달라서 안 묶입니다. 웹 UI.levelGroups 와 같은 규칙.
List<LevelGroup> levelGroups(List<Map<String, Object?>> results, Object? recommended) {
  final raw = <List<Map<String, Object?>>>[];
  for (final r in results) {
    List<Map<String, Object?>>? hit;
    for (final g in raw) {
      if ((core.jsToNumber(g.first['a']) - core.jsToNumber(r['a'])).abs() < 0.005 &&
          core.jsToNumber(g.first['weeks']) == core.jsToNumber(r['weeks'])) {
        hit = g;
        break;
      }
    }
    if (hit != null) {
      hit.add(r);
    } else {
      raw.add([r]);
    }
  }
  return [
    for (final g in raw)
      LevelGroup(g, g.firstWhere((r) => r['level'] == recommended, orElse: () => g.first)),
  ];
}

/* 위쪽 설명 세 덩이(구간 · 주의 · 병목)를 한 장으로. 첫 문장만 두고
   나머지는 「자세히」. 화면을 열자마자 글 세 덩이를 읽게 하면 정작
   골라야 할 카드가 화면 밖으로 밀립니다. */
class _NotesCard extends StatefulWidget {
  const _NotesCard({required this.cmp});
  final Map<String, Object?> cmp;
  @override
  State<_NotesCard> createState() => _NotesCardState();
}

class _NotesCardState extends State<_NotesCard> {
  bool _open = false;

  /// 첫 문장. 소수점("0.35")은 문장 끝이 아닙니다 — 뒤에 빈칸이 와야 끝입니다.
  static String firstSentence(String s) {
    final m = RegExp(r'^.*?[.!?](?=\s|$)').firstMatch(s.trim());
    return m?.group(0) ?? s.trim();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cmp = widget.cmp;
    final span = cmp['spanNote'] is Map ? '${(cmp['spanNote'] as Map)['text']}' : null;
    final warnings = ((cmp['warnings'] as List?) ?? const []).map((w) => '$w').toList();
    final bottle = cmp['bottleneckNote'] is Map ? '${(cmp['bottleneckNote'] as Map)['text']}' : null;
    if (span == null && warnings.isEmpty && bottle == null) return const SizedBox.shrink();

    final head = [
      if (span != null) firstSentence(span),
      if (bottle != null) firstSentence(bottle),
    ].join(' ');

    return MbCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionTitle('이 목표는',
            trailing: warnings.isEmpty ? null : Pill('주의 ${warnings.length}', tone: Tone.warn)),
        Text(head, style: t.textTheme.bodySmall?.copyWith(height: 1.5)),
        if (_open) ...[
          const SizedBox(height: 10),
          if (span != null) Note(text: span),
          for (final w in warnings) Note(tone: Tone.warn, text: w),
          if (bottle != null) Note(title: '병목', text: ' $bottle'),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => setState(() => _open = !_open),
            child: Text(_open ? '접기' : '자세히'),
          ),
        ),
      ]),
    );
  }
}

class _LevelCard extends StatelessWidget {
  const _LevelCard({required this.r, required this.levels, required this.selected,
      required this.recommended, required this.onTap});
  final Map<String, Object?> r;
  /// 이 카드가 나타내는 강도들 — 둘 이상이면 같은 계획을 합친 카드입니다.
  final List<Map<String, Object?>> levels;
  final bool selected, recommended;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = mb(context);
    final feas = (r['feasibility'] as Map).cast<String, Object?>();
    final macros = (r['macros'] as Map).cast<String, Object?>();
    final sim = (r['sim'] as Map).cast<String, Object?>();
    final blocked = feas['verdict'] == 'blocked';
    final group = LevelGroup(levels, r);
    final merged = levels.length > 1;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: t.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: selected ? t.colorScheme.primary : t.dividerColor,
            width: selected ? 2 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: blocked ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(
                child: Text(merged ? '${group.names} · 같은 계획' : '${r['label']} · ${r['title']}',
                    style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 8),
              if (recommended) const Pill('추천', tone: Tone.ok),
              const Spacer(),
              /* 코어가 보내는 ⛔🟢🟡🔴 를 글자로 안 찍습니다 — 우리 글꼴에
                 이모지가 없어서 구글에서 받아 오려 합니다. */
              VerdictDot(feas['verdict']),
            ]),
            const SizedBox(height: 6),
            Row(children: [
              DifficultyStars(core.jsToNumber(r['difficulty']).toInt()),
              const SizedBox(width: 6),
              Text(withoutStars(r['difficultyLabel']),
                  style: t.textTheme.labelSmall?.copyWith(color: t.hintColor)),
            ]),
            const SizedBox(height: 6),
            /* 합친 카드에 대표(상)의 설명("가장 빠르게 · 식단이 가장 빡빡")을 달면 틀립니다. */
            Text(
                merged
                    ? '이 목표에서는 ${group.subject} 같은 계획입니다. '
                        '기간 · 식단 · 운동이 모두 같아서 한 장으로 합쳤습니다.'
                    : '${r['blurb']}',
                style: t.textTheme.bodySmall?.copyWith(color: t.hintColor, height: 1.5)),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: Stat(label: '기간', value: n0(r['weeks']), unit: '주')),
              Expanded(child: Stat(label: '목표일', value: dateK(r['targetDate']))),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: Stat(label: '섭취', value: n0(macros['intakeKcal']), unit: 'kcal')),
              Expanded(child: Stat(label: '단백질', value: n0(macros['proteinG']), unit: 'g')),
              Expanded(child: Stat(label: '운동', value: n0(r['daysPerWeek']), unit: '일/주')),
            ]),
            const SizedBox(height: 10),
            Text('${feas['message']}',
                style: t.textTheme.bodySmall?.copyWith(
                    color: blocked ? c.bad : t.hintColor, height: 1.5)),
            if (r['capWarning'] != null) ...[
              const SizedBox(height: 8),
              Text('${r['capWarning']}',
                  style: t.textTheme.labelSmall?.copyWith(color: c.warn, height: 1.5)),
            ],
            if (r['leanLossWarning'] != null) ...[
              const SizedBox(height: 6),
              Text('${r['leanLossWarning']}',
                  style: t.textTheme.labelSmall?.copyWith(color: c.warn, height: 1.5)),
            ],
            if (sim['alternative'] != null) ...[
              const SizedBox(height: 6),
              Text(
                  '다른 전략(${(sim['alternative'] as Map)['strategyLabel']})으로는 '
                  '${n0((sim['alternative'] as Map)['weeks'])}주입니다.',
                  style: t.textTheme.labelSmall?.copyWith(color: t.hintColor)),
            ],
          ]),
        ),
      ),
    );
  }
}
