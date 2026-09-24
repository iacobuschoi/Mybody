/* =============================================================================
 * duration.dart — 기간으로 목표 정하기
 *
 * 목표 화면(P05)은 "어떤 몸" 을 먼저 받고 거기까지 얼마나 걸리는지 계산합니다.
 * 이 화면은 반대입니다. **기간을 먼저 받고**, 그 안에 갈 수 있는 몸을
 * 방향별(감량 · 증량)로 보여 줍니다. 여섯 달 뒤의 숫자를 지금 고르라고
 * 하면 사람은 너무 먼 숫자를 고르고, 그 계획은 두 달을 못 넘깁니다.
 * "12주면 여기까지" 를 보고 고르는 편이 지키는 계획이 됩니다.
 *
 * 숫자를 늘어놓지 않습니다. 카드마다 지금 → 그때 막대 두 줄(체지방 · 골격근)
 * 이 먼저이고, 숫자는 그 밑에 작게 둡니다. 옵션들의 체지방 궤적은 차트 한
 * 장에 겹쳐서 어느 것이 얼마나 다른지 눈으로 비교하게 합니다.
 *
 * 고르고 나면 기존 흐름(IntensityScreen → compareLevels → buildPlan → 저장)을
 * 그대로 탑니다 — 목표 세 숫자와 마감 주수만 넘깁니다. 계획을 만드는 길이
 * 둘이 되면 둘 중 하나는 반드시 뒤처집니다.
 * ========================================================================== */
import 'dart:math' as math;

import 'package:flutter/material.dart';
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

/// 기간 고르기 → 옵션 보기 → 하나 고르기. 목록(ListView) 안에 한 덩이로 들어갑니다.
class DurationPanel extends StatefulWidget {
  const DurationPanel({super.key, this.compute, this.initialWeeks = kDurationDefault, this.onPick});
  final DurationCompute? compute;
  final int initialWeeks;

  /// 고른 목표를 받을 곳. 없으면 [IntensityScreen] 을 밀어 올립니다.
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
      return const EmptyState(
          title: '먼저 인바디를 넣어야 합니다',
          detail: '지금 어디에 있는지를 알아야 어디로 갈지 정할 수 있습니다.');
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

    /* 막대의 자는 모든 카드가 같이 씁니다 — 카드마다 따로 재면 "더 긴 막대 =
       더 많이" 가 카드 사이에서 안 통합니다. */
    final fatMax = _maxOf(cur, options, 'bfmKg');
    final smmMax = _maxOf(cur, options, 'smmKg');

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _WeeksCard(weeks: _weeks, onChanged: (w) => setState(() => _weeks = w)),
      for (final w in warnings) Note(tone: Tone.warn, text: w),
      if (options.isEmpty)
        (warnings.isEmpty
            ? const Note(
                text: '이 기간에는 만들 수 있는 계획이 없습니다. 기간을 늘리거나 줄여 보세요.')
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
          child: Text('카드의 막대는 연한 줄이 지금, 진한 줄이 그때입니다. 눌러서 고릅니다.',
              style: t.textTheme.labelSmall?.copyWith(color: t.hintColor, height: 1.5)),
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
              onTap: () => setState(() => _selectedId = '${o['id']}'),
            ),
        ],
      ],
      FilledButton(
        onPressed: selected == null ? null : () => _go(res, selected),
        child: const Text('이 목표로 기간 고르기'),
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
    /* 옵션의 공격성도 넘깁니다 — 강도 화면이 마감 ±1주 안의 카드 중 이 값에 가장
       가까운 것을 골라 둡니다. 여기서 본 식단과 같은 카드여야 합니다. */
    final a = o['a'];
    /* 마감은 엔진이 실제로 계산한 주수로 — 엔진이 값을 다듬었으면 그쪽이
       맞습니다. 세 숫자는 엔진이 준 그대로 넘깁니다(반올림하면 셋이 서로
       어긋납니다). */
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
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => IntensityScreen(
            goal: goal, fromDuration: true, preferA: a is num ? a.toDouble() : null)));
  }
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

class _WeeksCard extends StatelessWidget {
  const _WeeksCard({required this.weeks, required this.onChanged});
  final int weeks;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return MbCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionTitle('기간',
            trailing: Text('$weeks주',
                key: const Key('duration-weeks'),
                style: t.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()]))),
        Text('이 기간 안에 갈 수 있는 몸을 방향별로 보여 줍니다.',
            style: t.textTheme.bodySmall?.copyWith(color: t.hintColor, height: 1.5)),
        const SizedBox(height: 10),
        Wrap(spacing: 8, children: [
          for (final w in kDurationChips)
            ChoiceChip(
              label: Text('$w주'),
              selected: weeks == w,
              onSelected: (_) => onChanged(w),
            ),
        ]),
        Slider(
          value: weeks.toDouble(),
          min: kDurationMin.toDouble(),
          max: kDurationMax.toDouble(),
          divisions: kDurationMax - kDurationMin,
          label: '$weeks주',
          onChanged: (v) => onChanged(v.round()),
        ),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('$kDurationMin주', style: t.textTheme.labelSmall?.copyWith(color: t.hintColor)),
          Text('$kDurationMax주', style: t.textTheme.labelSmall?.copyWith(color: t.hintColor)),
        ]),
      ]),
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

class _OptionCard extends StatelessWidget {
  const _OptionCard({
    super.key,
    required this.o,
    required this.cur,
    required this.fatMax,
    required this.smmMax,
    required this.selected,
    required this.recommended,
    required this.onTap,
  });
  final Map<String, Object?> o;
  final Map<String, Object?> cur;
  final double fatMax, smmMax;
  final bool selected, recommended;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = mb(context);
    final goal = ((o['goal'] as Map?) ?? const {}).cast<String, Object?>();
    final delta = ((o['delta'] as Map?) ?? const {}).cast<String, Object?>();
    final stoppedAt = o['stoppedAt'];
    final note = o['note'] == null || '${o['note']}'.isEmpty ? null : '${o['note']}';
    final noteText = note ??
        (stoppedAt == null ? null : '${n0(stoppedAt)}주째에 멈춥니다 — 그 뒤로는 더 못 갑니다.');
    final small = t.textTheme.labelSmall?.copyWith(
        color: t.hintColor, height: 1.5, fontFeatures: const [FontFeature.tabularFigures()]);

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
              Text('체중 ${n1(cur['weightKg'])} → ${n1(goal['weightKg'])}kg', style: small),
            ]),
            const SizedBox(height: 10),
            _NowThen(
                label: '체지방',
                now: core.jsToNumber(cur['bfmKg']),
                then: core.jsToNumber(goal['bfmKg']),
                max: fatMax,
                color: c.fat),
            const SizedBox(height: 6),
            _NowThen(
                label: '골격근',
                now: core.jsToNumber(cur['smmKg']),
                then: core.jsToNumber(goal['smmKg']),
                max: smmMax,
                color: c.muscle),
            const SizedBox(height: 8),
            Text(
                'Δ체지방 ${signed(delta['bfmKg'])}kg · Δ근육 ${signed(delta['smmKg'])}kg · '
                '체지방률 ${n1(cur['pbfPct'])}→${n1(goal['pbfPct'])}%',
                style: small),
            Text(
                '하루 ${n0(o['intakeKcal'])} kcal · 단백질 ${n0(o['proteinG'])} g · '
                '주 ${n0(o['daysPerWeek'])}회',
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

/// 지금 → 그때 막대 두 줄. 연한 줄이 지금, 진한 줄이 그때입니다.
class _NowThen extends StatelessWidget {
  const _NowThen({
    required this.label,
    required this.now,
    required this.then,
    required this.max,
    required this.color,
  });
  final String label;
  final double now, then, max;
  final Color color;

  double _frac(double v) =>
      (max > 0 && v.isFinite) ? (v / max).clamp(0.0, 1.0).toDouble() : 0.0;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
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
    return Row(children: [
      SizedBox(
          width: 40,
          child: Text(label, style: t.textTheme.labelSmall?.copyWith(color: t.hintColor))),
      Expanded(
        child: Column(children: [
          bar(_frac(now), color.withValues(alpha: 0.35)),
          const SizedBox(height: 3),
          bar(_frac(then), color),
        ]),
      ),
      const SizedBox(width: 8),
      SizedBox(
        width: 96,
        child: Text('${n1(now)} → ${n1(then)}',
            textAlign: TextAlign.right,
            style: t.textTheme.labelSmall?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()])),
      ),
    ]);
  }
}
