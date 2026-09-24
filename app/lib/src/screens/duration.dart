/* =============================================================================
 * duration.dart — 기간으로 목표 정하기
 *
 * 목표 화면(P05)은 "어떤 몸" 을 먼저 받고 거기까지 얼마나 걸리는지 계산합니다.
 * 이 화면은 반대입니다. **기간을 먼저 받고**, 그 안에 갈 수 있는 몸을
 * 방향별(감량 · 증량)로 보여 줍니다. 여섯 달 뒤의 숫자를 지금 고르라고
 * 하면 사람은 너무 먼 숫자를 고르고, 그 계획은 두 달을 못 넘깁니다.
 * "12주면 여기까지" 를 보고 고르는 편이 지키는 계획이 됩니다.
 *
 * 숫자를 늘어놓지 않습니다. 카드마다 체지방 · 골격근 두 줄이고, 줄에서 가장 큰
 * 숫자는 **변화량**('−2.9 kg', 방향의 색)입니다. 지금 → 그때는 그 옆에 작게,
 * 막대 두 줄은 그 밑에. 0.2.9 를 폰에서 써 본 첫 반응이 "텍스트를 줄이고 체지방 ·
 * 골격근 변화를 확실히 보이게" 였습니다 — 숫자 여섯 개를 작은 두 줄에 늘어놓으니
 * 정작 봐야 할 변화가 그 사이에 묻혔습니다. 다음 반응은 "그 변화량 글씨가 너무
 * 크다" 여서 22px 에서 18px 로 살짝만 내렸습니다 — 여전히 줄에서 가장 큰 글자입니다.
 * 옵션들의 체지방 궤적은 차트 한 장에 겹쳐서 어느 것이 얼마나 다른지 눈으로 비교하게
 * 합니다.
 *
 * 설명문은 한 줄을 넘기지 않습니다. 기간 카드는 제목 · 주수 · 칩 · 자(− +)뿐이고,
 * 카드와 판의 나머지 글도 숫자 몇 개와 짧은 한 줄입니다 — 화면에 글이 많을수록
 * 정작 골라야 할 카드가 아래로 밀립니다.
 *
 * 고르면 **여기서 바로 계획을 세웁니다** (compareLevels → buildPlan → 저장). 예전에는
 * 고른 뒤 강도 화면(intensity.dart)을 한 번 더 밀어 12 · 18 · 23주 카드를 다시
 * 고르게 했는데, "이미 앞에서 기간 골랐는데 또 기간을 고를 필요 없어" 가 맞는
 * 말입니다. 강도 화면이 그때 하던 일은 고른 주수 ±1주 안에서 이 옵션과 같은
 * 공격성의 카드를 골라 두는 것(initialLevel)뿐이라, 그 고르기만 가져와 사람 없이
 * 돌립니다. 계산은 강도 화면의 _commit 과 같은 식입니다 — 계획을 만드는 길이
 * 둘이어도 계산이 둘이면 둘 중 하나는 반드시 뒤처집니다.
 * ========================================================================== */
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:mybody_core/mybody_core.dart' as core;

import '../scope.dart';
import '../theme.dart';
import '../ui/charts.dart';
import '../ui/fmt.dart';
import '../ui/widgets.dart';
import 'intensity.dart';

/// 빠르게 고르는 칩. 그 사이 값은 슬라이더로.
const List<int> kDurationChips = [8, 12, 16, 24];

/// 8주 아래는 안 내줍니다 — 4주 계획은 인바디 오차보다 작은 변화만 기대할 수 있어서
/// 엔진이 경고를 붙이던 구간입니다. 고를 수 없는 것을 고르게 두고 경고로 막는 것보다
/// 자를 그만큼만 두는 편이 낫습니다.
const int kDurationMin = 8;
const int kDurationMax = 52;
const int kDurationDefault = 12;

/// 주수를 받아 옵션 표를 주는 자리. 앱은 엔진(`core.durationOptions`)을 쓰고,
/// 시험은 손으로 만든 표를 넣어 그림만 따로 봅니다.
typedef DurationCompute = Map<String, Object?> Function(int weeks);

/// 혼자 밀어 올려 쓰는 화면. 목표 화면 안에서는 [DurationPanel] 을 바로 씁니다.
class DurationScreen extends StatelessWidget {
  const DurationScreen({super.key, this.compute, this.initialWeeks = kDurationDefault});
  final DurationCompute? compute;
  final int initialWeeks;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('기간으로 정하기')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        DurationPanel(compute: compute, initialWeeks: initialWeeks),
      ]),
    );
  }
}

/// 기간 고르기 → 옵션 보기 → 하나 고르기 → 계획 저장. 목록(ListView) 안에 한 덩이로 들어갑니다.
class DurationPanel extends StatefulWidget {
  const DurationPanel({super.key, this.compute, this.initialWeeks = kDurationDefault, this.onPick});
  final DurationCompute? compute;
  final int initialWeeks;

  /// 고른 목표를 받을 곳(시험이 목표 표만 받아 볼 때). 없으면 여기서 바로 계획을
  /// 세워 저장하고, 이 판이 선 화면을 닫습니다.
  final void Function(Map<String, Object?> goal)? onPick;

  @override
  State<DurationPanel> createState() => _DurationPanelState();
}

class _DurationPanelState extends State<DurationPanel> {
  late int _weeks = widget.initialWeeks.clamp(kDurationMin, kDurationMax).toInt();
  String? _selectedId;

  /* 슬라이더는 한 번 끌면 값이 수십 번 바뀝니다. 같은 주수를 두 번 계산하지
     않도록 결과를 들고 있습니다. 측정이 바뀌면 다른 표라서 열쇠에 측정 id 를
     같이 넣습니다. */
  final _cache = <String, Map<String, Object?>>{};

  @override
  void didUpdateWidget(DurationPanel old) {
    super.didUpdateWidget(old);
    /* 표를 만드는 자리가 바뀌면 들고 있던 결과는 다른 표입니다. */
    if (old.compute != widget.compute) _cache.clear();
  }

  Map<String, Object?> _options(
      Map<String, Object?> scan, Map<String, Object?> profile, String today) {
    return _cache.putIfAbsent('${scan['id']}:$_weeks', () {
      final compute = widget.compute;
      if (compute != null) return compute(_weeks);
      return core.durationOptions(scan, profile, _weeks, today, null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = Scope.of(context);
    final scans = app.store.sortedScans();
    if (scans.isEmpty) {
      return const EmptyState(title: '먼저 인바디를 넣어야 합니다');
    }
    final profile = app.profile ?? core.kSeedProfile;
    final cur = core.derive(scans.last, profile);
    final res = _options(scans.last, profile, app.store.dayKey());
    final options = [
      for (final o in (res['options'] as List?) ?? const [])
        (o as Map).cast<String, Object?>(),
    ];
    final warnings = [for (final w in (res['warnings'] as List?) ?? const []) '$w'];
    final recommended = res['recommended'];
    final selected = _find(options, _selectedId);
    final t = Theme.of(context);
    final c = mb(context);
    final hint = t.textTheme.labelSmall?.copyWith(color: t.hintColor, height: 1.5);

    /* 막대의 자는 모든 카드가 같이 씁니다 — 카드마다 따로 재면 "더 긴 막대 =
       더 많이" 가 카드 사이에서 안 통합니다. */
    final fatMax = _maxOf(cur, options, 'bfmKg');
    final smmMax = _maxOf(cur, options, 'smmKg');
    /* 운동 횟수는 카드마다가 아니라 위에 한 번 — 모든 카드가 같은 값일 때만. 다르면
       (null) 카드가 각자 적습니다. 왜 늘 같은지는 [trainingLine] 에. */
    final training = trainingLine(options, profile);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _WeeksCard(weeks: _weeks, onChanged: (w) => setState(() => _weeks = w)),
      for (final w in warnings) Note(tone: Tone.warn, text: w),
      if (options.isEmpty)
        (warnings.isEmpty
            ? const Note(text: '이 기간에는 계획이 없습니다 — 기간을 바꿔 보세요')
            : const SizedBox.shrink())
      else ...[
        MbCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SectionTitle('$_weeks주 동안의 체지방'),
            LineChart(
              height: 170,
              series: _series(options, c),
              xTickFmt: (v) => '${v.round()}주',
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (training != null)
              Text(training, key: const Key('training-line'), style: hint),
            /* 막대 읽는 법은 이 한마디면 됩니다 — 긴 문장은 카드보다 먼저 읽히면서
               정작 카드를 화면 아래로 밀었습니다. */
            Text('연한 줄 지금 · 진한 줄 그때', style: hint),
          ]),
        ),
        for (final g in groupByDirection(options)) ...[
          _DirectionHeader(label: g.label, color: g.direction == 'bulk' ? c.muscle : c.fat),
          for (final o in g.options)
            _OptionCard(
              key: ValueKey('option-${o['id']}'),
              o: o,
              cur: cur,
              fatMax: fatMax,
              smmMax: smmMax,
              selected: o['id'] == _selectedId,
              recommended: recommended != null && o['id'] == recommended,
              showDays: training == null,
              onTap: () => setState(() => _selectedId = '${o['id']}'),
            ),
        ],
      ],
      FilledButton(
        onPressed: selected == null ? null : () => _go(res, selected),
        child: const Text('이 계획으로 시작하기'),
      ),
    ]);
  }

  static Map<String, Object?>? _find(List<Map<String, Object?>> options, String? id) {
    if (id == null) return null;
    for (final o in options) {
      if (o['id'] == id) return o;
    }
    return null;
  }

  static double _maxOf(Map<String, Object?> cur, List<Map<String, Object?>> options, String key) {
    var m = core.jsToNumber(cur[key]);
    for (final o in options) {
      final g = (o['goal'] as Map?)?.cast<String, Object?>();
      if (g == null) continue;
      final v = core.jsToNumber(g[key]);
      if (v.isFinite) m = math.max(m, v);
    }
    return m.isFinite ? m : 0;
  }

  /* 옵션마다 선 하나. 색은 방향(감량 = 지방색, 증량 = 근육색 — 단계 막대와
     같은 약속)이고 강도는 진하기, 고른 것은 굵기로 구분합니다. */
  List<Series> _series(List<Map<String, Object?>> options, MbColors c) {
    return [
      for (final o in options)
        Series(
          label: seriesLabel(o),
          color: (o['direction'] == 'bulk' ? c.muscle : c.fat)
              .withValues(alpha: _alphaOf(o['level'])),
          width: o['id'] == _selectedId ? 3.2 : 1.4,
          dots: false,
          points: [
            for (final s in (o['trajectory'] as List?) ?? const [])
              Pt(core.jsToNumber((s as Map)['week']), core.jsToNumber(s['bfmKg'])),
          ],
        ),
    ];
  }

  static double _alphaOf(Object? level) => switch ('$level') {
        'high' => 1.0,
        'mid' => 0.75,
        _ => 0.5,
      };

  void _go(Map<String, Object?> res, Map<String, Object?> o) {
    final g = (o['goal'] as Map).cast<String, Object?>();
    /* 옵션의 공격성도 — 마감 ±1주 안의 카드 중 이 값에 가장 가까운 것을 고릅니다.
       여기서 본 식단과 같은 카드여야 합니다. */
    final a = o['a'];
    /* 마감은 엔진이 실제로 계산한 주수로 — 엔진이 값을 다듬었으면 그쪽이
       맞습니다. 세 숫자는 엔진이 준 그대로 넘깁니다(반올림하면 셋이 서로
       어긋납니다). 화면 사정(공격성)은 표에 안 섞습니다 — 저장되는 목표입니다. */
    final weeks = res['weeks'] == null ? _weeks : core.jsToNumber(res['weeks']).round();
    final goal = <String, Object?>{
      'weightKg': core.jsToNumber(g['weightKg']),
      'smmKg': core.jsToNumber(g['smmKg']),
      'bfmKg': core.jsToNumber(g['bfmKg']),
      'deadlineWeeks': weeks,
    };
    final onPick = widget.onPick;
    if (onPick != null) {
      onPick(goal);
      return;
    }
    _start(goal, weeks, a is num ? a.toDouble() : null);
  }

  /* 계획을 세우고 저장하는 자리. 강도 화면의 _commit 과 같은 순서입니다 — compareLevels
     로 세 강도를 세우고, 고른 주수 ±1주 안에서 이 옵션과 같은 공격성의 카드(없으면
     가장 가까운 카드)를 골라(initialLevel) buildPlan. 이 판은 기간을 두고 몸을 찾고
     compareLevels 는 몸을 두고 기간을 찾아서, 같은 몸이라도 카드의 주수가 고른 주수와
     한두 주 어긋날 수 있습니다 — 그래서 ±1주입니다. 막힌 카드는 initialLevel 이 안
     고르지만, 저장하는 자리가 마지막 문이라 한 번 더 거릅니다. */
  void _start(Map<String, Object?> goal, int weeks, double? preferA) {
    final app = Scope.of(context);
    final scans = app.store.sortedScans();
    if (scans.isEmpty) return; // build 가 먼저 막습니다 — 측정 없이는 카드도 없습니다
    final profile = app.profile ?? core.kSeedProfile;
    final cmp = core.compareLevels(scans.last, profile, goal, app.store.dayKey(), weeks, null);
    if (cmp['impossible'] == true) {
      /* 이 판이 그 주수 안에 닿는다고 계산한 몸이라 실제로는 안 옵니다만, 오면 엔진의
         말(왜 못 가는지)을 그대로 — 우리 말로 바꾸면 이유가 빠집니다. */
      final w = (cmp['warnings'] as List?) ?? const [];
      toast(context, w.isEmpty ? kNoOpenLevelMessage : '${w.first}');
      return;
    }
    final results = resultsOf(cmp);
    final level =
        initialLevel(results, cmp['recommended'], deadlineWeeks: weeks, preferA: preferA);
    Map<String, Object?>? sel;
    for (final r in results) {
      if (level != null && r['level'] == level) sel = r;
    }
    if (sel == null || isBlocked(sel)) {
      toast(context, sel == null ? kNoOpenLevelMessage : blockedMessage(sel));
      return;
    }
    final plan = core.buildPlan(cmp, level, scans.last, profile);
    if (plan == null) {
      toast(context, '계획을 만들지 못했습니다');
      return;
    }
    app.store.setGoal(goal);
    app.store.setPlan(plan);
    if (!app.store.saved()) {
      toast(context, '기기에 저장하지 못했습니다 — 계획이 남지 않습니다');
      return;
    }
    /* 이 판은 목표 화면(또는 혼자 선 DurationScreen) 안에 있으니 한 번 pop 이면 그
       화면이 닫히고 셸로 돌아갑니다. 강도 화면은 목표 화면 위에 밀려 있어서 두 번이었습니다. */
    Navigator.of(context).pop();
    toast(context, '계획을 세웠습니다');
  }
}

/// 카드 위에 한 번 두는 운동 처방 — '운동 주 4회 · 회당 60분 — 내 몸 정보 기준'.
/// 모든 카드가 같은 횟수일 때만 그 줄이고, 카드마다 다르면 null(그때는 카드가 각자 적습니다).
///
/// 0.2.9 폰 시험에서 "왜 다 주 4회지?" 를 들었습니다. 엔진의 resolveTraining 은 어느
/// 강도든 profile.daysPerWeek — 내 몸 정보에서 "주에 며칠 운동할 수 있는지" 로 받은
/// 값 — 를 그대로 쓰므로(운동 처방은 식단 공격성이 아니라 낼 수 있는 시간이 정합니다)
/// 카드마다 같은 숫자가 찍히고, 같은 숫자를 네 번 보면 카드가 그걸로 갈리는 줄 읽힙니다.
/// 그래서 카드에서 빼고 위에 한 번만, 어디서 온 값인지와 함께 둡니다. 내 몸 정보에 횟수가
/// 없으면 엔진이 강도마다 다르게 잡으므로(params.days) 그때는 카드마다 다를 수 있습니다.
///
/// 회당 시간도 같은 규칙 — 내 몸 정보에 있으면 모든 카드가 같고, 없으면 강도마다 달라서
/// 같을 때만 붙입니다. 출처("내 몸 정보 기준")는 정말 거기서 왔을 때만, 폰 너비에서 한
/// 줄에 들어가게 짧게 말합니다.
String? trainingLine(List<Map<String, Object?>> options, Map<String, Object?> profile) {
  if (options.isEmpty) return null;
  /* 모든 카드가 같은 값을 들고 있을 때만 그 값. 하나라도 없거나 다르면 null.
     엔진은 숫자로 주지만 손으로 만든 표나 옛 저장본은 "4" 일 수 있어 숫자로 읽습니다. */
  double? shared(String key) {
    double? v;
    for (final o in options) {
      if (o[key] == null) return null;
      final n = core.jsToNumber(o[key]);
      if (!n.isFinite) return null;
      if (v == null) {
        v = n;
      } else if (v != n) {
        return null;
      }
    }
    return v;
  }

  final days = shared('daysPerWeek');
  if (days == null) return null;
  final minutes = shared('sessionMinutes');
  final from = core.jsTruthy(profile['daysPerWeek']) ? ' — 내 몸 정보 기준' : '';
  return '운동 주 ${n0(days)}회${minutes == null ? '' : ' · 회당 ${n0(minutes)}분'}$from';
}

/// 차트 범례 — '감량 중'. 엔진이 방향 이름 그대로 한 장('증량')으로 준 카드는
/// '증량 증량' 이 아니라 '증량' 입니다.
String seriesLabel(Map<String, Object?> o) {
  final dir = '${o['directionLabel'] ?? ''}';
  final label = '${o['label'] ?? ''}';
  if (label.isEmpty || label == dir) return dir;
  return '$dir $label'.trim();
}

/// 방향(감량 · 증량)별 묶음. 감량이 먼저, 그다음 증량, 나머지는 온 순서대로.
class DirectionGroup {
  DirectionGroup(this.direction, this.label);
  final String direction;
  final String label;
  final List<Map<String, Object?>> options = [];
}

List<DirectionGroup> groupByDirection(List<Map<String, Object?>> options) {
  final groups = <DirectionGroup>[];
  for (final o in options) {
    final dir = '${o['direction'] ?? ''}';
    DirectionGroup? hit;
    for (final g in groups) {
      if (g.direction == dir) {
        hit = g;
        break;
      }
    }
    if (hit == null) {
      hit = DirectionGroup(dir, '${o['directionLabel'] ?? _labelOf(dir)}');
      groups.add(hit);
    }
    hit.options.add(o);
  }
  return [
    for (final d in const ['cut', 'bulk']) ...groups.where((g) => g.direction == d),
    ...groups.where((g) => g.direction != 'cut' && g.direction != 'bulk'),
  ];
}

String _labelOf(String direction) => switch (direction) {
      'cut' => '감량',
      'bulk' => '증량',
      _ => direction,
    };

/// 강도 이름표 — 이것이 아니면(예: '증량') 엔진이 강도 없이 한 장으로 준 카드입니다.
const Set<String> kLevelLabels = {'상', '중', '하'};

/// 카드 제목 — 강도 이름에 한마디. 기간이 정해져 있으니 '상' 은 "그 안에 더 많이
/// 바꾼다(식단이 더 빡빡)" 이고 '하' 는 "덜 바꾼다(여유)" 입니다.
///
/// 엔진이 증량을 강도 없이 한 장(label '증량', levels [low, mid, high])으로 주면
/// '증량 · 표준' 한 장입니다 — 셋으로 쪼개 보이려 하지 않습니다. 증량은 근육이 붙는
/// 속도가 기간을 정해서 강도를 바꿔도 같은 계획입니다.
String optionTitle(Map<String, Object?> o) {
  final label = '${o['label'] ?? ''}';
  if (label.contains('·')) return '$label · 같은 계획';
  final levels = o['levels'];
  final allLevels = levels is List && levels.length >= 3;
  if (label.isNotEmpty && (allLevels || !kLevelLabels.contains(label))) return '$label · 표준';
  final sub = switch ('${o['level']}') {
    'high' => '크게',
    'mid' => '표준',
    'low' => '여유',
    _ => '',
  };
  if (label.isEmpty) return sub;
  return sub.isEmpty ? label : '$label · $sub';
}

/// 기간 카드 — 제목 · 주수 · 칩(8/12/16/24) · 자. 자의 양옆에 「−」「+」 가 있어
/// 1주씩 맞출 수 있습니다: 칩은 빠르고 자는 대충이라, 15주 · 20주처럼 그 사이의
/// 딱 한 주수는 엄지로 자를 끌어 맞추기가 어렵습니다(폰에서 "슬라이더 옆에 − + 를"
/// 이라고 들었습니다). 끝(8 · 52주)에서는 그쪽 단추가 닫힙니다 — 눌러도 안 움직이는
/// 단추는 고장으로 보입니다. 설명문은 없습니다: "이 기간 안에 갈 수 있는 몸" 은 밑의
/// 카드가 보여 주는 것이라 글로 한 번 더 말할 것이 없습니다.
class _WeeksCard extends StatelessWidget {
  const _WeeksCard({required this.weeks, required this.onChanged});
  final int weeks;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final hint = t.textTheme.labelSmall?.copyWith(color: t.hintColor);
    return MbCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionTitle('기간',
            trailing: Text('$weeks주',
                key: const Key('duration-weeks'),
                style: t.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()]))),
        Wrap(spacing: 8, children: [
          for (final w in kDurationChips)
            ChoiceChip(
              label: Text('$w주'),
              selected: weeks == w,
              onSelected: (_) => onChanged(w),
            ),
        ]),
        const SizedBox(height: 4),
        Row(children: [
          _StepButton(
            buttonKey: const Key('duration-minus'),
            icon: LucideIcons.minus,
            tooltip: '1주 줄이기',
            onPressed: weeks > kDurationMin ? () => onChanged(weeks - 1) : null,
          ),
          Expanded(
            child: Slider(
              value: weeks.toDouble(),
              min: kDurationMin.toDouble(),
              max: kDurationMax.toDouble(),
              divisions: kDurationMax - kDurationMin,
              label: '$weeks주',
              onChanged: (v) => onChanged(v.round()),
            ),
          ),
          _StepButton(
            buttonKey: const Key('duration-plus'),
            icon: LucideIcons.plus,
            tooltip: '1주 늘리기',
            onPressed: weeks < kDurationMax ? () => onChanged(weeks + 1) : null,
          ),
        ]),
        /* 자의 양 끝 숫자 — 단추가 차지하는 폭(그림은 40 이지만 표적 여백까지 48)만큼
           들여서 자 밑에 놓습니다. */
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: kMinInteractiveDimension),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('$kDurationMin주', style: hint),
            Text('$kDurationMax주', style: hint),
          ]),
        ),
      ]),
    );
  }
}

/// 자 옆의 동그란 − / + 단추. 닫히면(onPressed null) 테마가 흐리게 그립니다.
/// 열쇠([buttonKey])는 이 껍데기가 아니라 안의 IconButton 에 답니다 — 시험이
/// 열쇠로 찾아 onPressed 를 읽는 것이 그 단추입니다.
class _StepButton extends StatelessWidget {
  const _StepButton(
      {required this.buttonKey,
      required this.icon,
      required this.tooltip,
      required this.onPressed});
  final Key buttonKey;
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  /// 단추 한 변. 자의 줄 높이(48)보다 작게 두어 줄이 단추 때문에 커지지 않습니다.
  static const double size = 40;

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      key: buttonKey,
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
          padding: EdgeInsets.zero,
          minimumSize: const Size(size, size),
          fixedSize: const Size(size, size)),
      icon: Icon(icon, size: 18),
    );
  }
}

class _DirectionHeader extends StatelessWidget {
  const _DirectionHeader({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 4, 0, 8),
      child: Row(children: [
        Container(
            width: 8, height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: t.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

/// 옵션 한 장. 제목 줄(강도 · 추천 · 체중), 체지방 줄, 골격근 줄, 식단 한 줄 — 그게
/// 전부입니다. 줄마다 변화량이 주인공이고 나머지는 작습니다.
class _OptionCard extends StatelessWidget {
  const _OptionCard({
    super.key,
    required this.o,
    required this.cur,
    required this.fatMax,
    required this.smmMax,
    required this.selected,
    required this.recommended,
    required this.showDays,
    required this.onTap,
  });
  final Map<String, Object?> o;
  final Map<String, Object?> cur;
  final double fatMax, smmMax;
  final bool selected, recommended;

  /// 운동 횟수를 이 카드에 적을지. 보통은 위의 한 줄([trainingLine])이 대신하고,
  /// 카드마다 횟수가 다를 때만 카드가 각자 적습니다.
  final bool showDays;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = mb(context);
    final goal = ((o['goal'] as Map?) ?? const {}).cast<String, Object?>();
    final delta = ((o['delta'] as Map?) ?? const {}).cast<String, Object?>();
    final stoppedAt = o['stoppedAt'];
    final note = o['note'] == null || '${o['note']}'.isEmpty ? null : '${o['note']}';
    /* 멈춤 안내는 한 줄 — "그 뒤로는 더 못 갑니다" 는 "멈춥니다" 가 이미 말한 것입니다. */
    final noteText = note ?? (stoppedAt == null ? null : '${n0(stoppedAt)}주째에 멈춥니다');
    final small = t.textTheme.labelSmall?.copyWith(
        color: t.hintColor, height: 1.5, fontFeatures: const [FontFeature.tabularFigures()]);

    final fatNow = core.jsToNumber(cur['bfmKg']), fatThen = core.jsToNumber(goal['bfmKg']);
    final smmNow = core.jsToNumber(cur['smmKg']), smmThen = core.jsToNumber(goal['smmKg']);
    /* 변화량은 엔진이 r1 로 다듬어 보낸 값(delta)을 그대로 — 화면에서 다시 빼면 그때 −
       지금이 카드의 세 숫자와 0.1 어긋나 보일 수 있습니다. 없을 때만 여기서 뺍니다. */
    double changeOf(String key, double now, double then) =>
        delta[key] == null ? then - now : core.jsToNumber(delta[key]);
    /* 체지방률은 엔진이 궤적에서 준 값. 없으면 목표 화면과 같은 식(체지방 / 체중)으로. */
    final weightThen = core.jsToNumber(goal['weightKg']);
    final pbfThen = goal['pbfPct'] ?? (weightThen > 0 ? fatThen / weightThen * 100 : null);

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
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(
                child: Text(optionTitle(o),
                    style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 8),
              if (recommended) const Pill('추천', tone: Tone.ok),
              const Spacer(),
              Text('체중 ${n1(cur['weightKg'])} → ${n1(weightThen)}', style: small),
            ]),
            const SizedBox(height: 10),
            _NowThen(
                label: '체지방',
                now: fatNow,
                then: fatThen,
                change: changeOf('bfmKg', fatNow, fatThen),
                max: fatMax,
                color: c.fat,
                extra: '${n1(cur['pbfPct'])} → ${n1(pbfThen)}%'),
            const SizedBox(height: 10),
            _NowThen(
                label: '골격근',
                now: smmNow,
                then: smmThen,
                change: changeOf('smmKg', smmNow, smmThen),
                max: smmMax,
                color: c.muscle),
            const SizedBox(height: 10),
            /* 식단은 한 줄. 운동 횟수는 위의 한 줄이 맡고, 카드마다 다를 때만 여기에. */
            Text(
                '하루 ${n0(o['intakeKcal'])} kcal · 단백질 ${n0(o['proteinG'])} g'
                '${showDays ? ' · 주 ${n0(o['daysPerWeek'])}회' : ''}',
                style: small),
            if (noteText != null) ...[
              const SizedBox(height: 6),
              /* 엔진이 도중에 멈춘 옵션 — 그 주부터는 몸이 더 안 바뀝니다.
                 막대는 그때 값이라 멀쩡해 보여서, 글로 짚어 줘야 합니다.
                 엔진이 이유를 적어 보냈으면 그 말을 쓰고, 없을 때만 우리 말로. */
              Text(noteText,
                  style: stoppedAt != null
                      ? t.textTheme.labelSmall?.copyWith(color: c.warn, height: 1.5)
                      : small),
            ],
          ]),
        ),
      ),
    );
  }
}

/// 한 줄 — 이름표, **변화량**(줄에서 가장 큰 숫자, 방향의 색), 작은 지금 → 그때, 그 밑에
/// 막대 두 줄(연한 줄이 지금, 진한 줄이 그때). 막대가 줄 너비를 다 쓰는 이유는 카드
/// 사이의 "더 긴 막대 = 더 많이" 비교가 그림의 요점이라서 — 숫자 칸에 자리를 내주면
/// 막대가 짧아져 그 차이가 안 보입니다.
///
/// 변화량은 [kChangeFontSize](18px) 굵게. 처음엔 titleLarge(22px)였는데 폰에서 "너무
/// 크다, 살짝만 줄여라" 였습니다. Material 3 의 titleMedium 은 16px 이라 그걸 그대로
/// 쓰면 살짝이 아니라 한참 줄어서, titleMedium 바탕에 크기만 18 로 둡니다 — 카드
/// 제목(titleSmall 14px)보다는 여전히 큽니다.
/// 변화량 글자 크기(px). 카드 제목(14)보다 크고 옛 값(22)보다 작게.
const double kChangeFontSize = 18;

class _NowThen extends StatelessWidget {
  const _NowThen({
    required this.label,
    required this.now,
    required this.then,
    required this.change,
    required this.max,
    required this.color,
    this.extra,
  });
  final String label;
  final double now, then, change, max;
  final Color color;

  /// 작은 글 뒤에 덧붙일 것 — 체지방 줄의 체지방률('23.1 → 19.9%').
  final String? extra;

  double _frac(double v) =>
      (max > 0 && v.isFinite) ? (v / max).clamp(0.0, 1.0).toDouble() : 0.0;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    const tabular = [FontFeature.tabularFigures()];
    Widget bar(double f, Color fill) => Container(
          height: 6,
          decoration: BoxDecoration(
              color: t.dividerColor.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(3)),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: f,
            child: DecoratedBox(
                decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(3))),
          ),
        );
    final detail = '${n1(now)} → ${n1(then)}${extra == null ? '' : ' · $extra'}';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(label, style: t.textTheme.labelSmall?.copyWith(color: t.hintColor)),
          const SizedBox(width: 8),
          Text('${signed(change)} kg',
              style: t.textTheme.titleMedium?.copyWith(
                  fontSize: kChangeFontSize,
                  fontWeight: FontWeight.w800,
                  color: color,
                  fontFeatures: tabular)),
          const SizedBox(width: 10),
          /* 좁은 폰에서는 줄여서라도 한 줄에 — 변화량 옆에서 두 줄로 꺾이면 무엇의
             지금 → 그때인지 흐려집니다(Stat 과 같은 이유). */
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(detail,
                  maxLines: 1,
                  style: t.textTheme.labelSmall
                      ?.copyWith(color: t.hintColor, fontFeatures: tabular)),
            ),
          ),
        ],
      ),
      const SizedBox(height: 5),
      bar(_frac(now), color.withValues(alpha: 0.35)),
      const SizedBox(height: 3),
      bar(_frac(then), color),
    ]);
  }
}
