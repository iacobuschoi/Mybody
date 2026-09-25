/* =============================================================================
 * adherence.dart — P21 달성률 (플랜 탭 위의 「달성률」)
 *
 * 운동과 식단을 한 자리에서 봅니다. 운동은 홈에서 체크한 일정에서, 식단은
 * 끼니 기록에서 셉니다. 계산은 ../adherence.dart 가 하고 — 주간 체크인도
 * 같은 숫자를 씁니다 — 여기는 그리기만 합니다.
 *
 * 분모를 반드시 씁니다. "3일" 이 아니라 "계획한 5일 중 3일" 입니다.
 *
 * 요일 동그라미(DayMark)는 여기서 정의하고 홈의 이번 주 카드·친구 주간
 * 카드가 같은 것을 씁니다 — 세 화면이 같은 그림을 다르게 그리면 색이
 * 무슨 뜻인지 매번 다시 배워야 합니다.
 * ========================================================================== */
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:mybody_core/mybody_core.dart' as core;

import '../adherence.dart';
import '../scope.dart';
import '../ui/fmt.dart';
import '../ui/widgets.dart';

Map<String, Object?>? _targetOf(BuildContext context) {
  final plan = Scope.of(context).state['plan'];
  if (plan is! Map) return null;
  final m = plan['macros'];
  return m is Map ? m.cast<String, Object?>() : null;
}

String _dowOf(String key) {
  final d = DateTime.tryParse('${key}T00:00:00');
  return d == null ? '' : core.kDow[(d.weekday - 1) % 7];
}

/* --- 요일 표시 ---------------------------------------------------------------
 *
 * 색만으로는 못 읽습니다(보라 채움이 지킴인지, 살구가 놓침인지). 그래서
 * 상태마다 모양이 다릅니다: 지킴은 체크, 놓침은 ×, 오늘은 점, 앞날은 빈
 * 테두리, 쉬는 날은 옅은 점. 범례(DayMarkLegend)도 같은 위젯으로 그립니다. */

enum DayMarkState { kept, missed, today, future, rest }

/// 일정 하루의 맵에서 표시 상태를 정합니다. 달성률(workoutAdherence)·홈
/// (schedule.week)·친구 공유(store.share) 세 곳의 맵을 다 받습니다 — 셋 다
/// `plan`·`key` 는 있고 `kept`·`missed` 는 있으면 믿고, 없으면(옛 공유)
/// `done` 에서 셉니다. 계획이 없는 날은 언제나 쉬는 날입니다.
DayMarkState dayMarkState(Map d, {required String today}) {
  final plan = d['plan'] as List? ?? const [];
  if (plan.isEmpty) return DayMarkState.rest;
  final done = d['done'];
  final kept = d.containsKey('kept')
      ? core.jsTruthy(d['kept'])
      : done is Map
          ? plan.every((t) => core.jsTruthy(done[t]))
          : done is List && plan.every(done.contains);
  if (kept) return DayMarkState.kept;
  if (core.jsTruthy(d['missed'])) return DayMarkState.missed;
  final key = '${d['key']}';
  if (key == today) return DayMarkState.today;
  if (key.compareTo(today) > 0) return DayMarkState.future;
  return DayMarkState.missed;   // 지난 날인데 다 못 했으면 놓친 것
}

class DayMark extends StatelessWidget {
  /// [tagged] 가 참이면 상태 이름의 키(`daymark-kept` 등)를 답니다 — 범례의
  /// 작은 것에는 안 달아서 테스트가 실제 칸만 셀 수 있게 합니다.
  const DayMark(this.state, {super.key, this.size = 22, this.tagged = true});
  final DayMarkState state;
  final double size;
  final bool tagged;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = mb(context);
    final primary = t.colorScheme.primary;
    final (Color? fill, Color? border, double bw) = switch (state) {
      DayMarkState.kept => (primary, null, 0.0),
      DayMarkState.missed => (null, c.warn, 1.5),
      DayMarkState.today => (null, primary, 1.5),
      DayMarkState.future => (null, t.dividerColor, 1.0),
      DayMarkState.rest => (null, null, 0.0),
    };
    Widget? inner;
    final iconSize = size * 0.62;
    final dot = size * 0.28;
    switch (state) {
      case DayMarkState.kept:
        inner = Icon(LucideIcons.check, size: iconSize, color: t.colorScheme.onPrimary);
      case DayMarkState.missed:
        inner = Icon(LucideIcons.x, size: iconSize, color: c.warn);
      case DayMarkState.today:
        inner = _Dot(dot, primary);
      case DayMarkState.rest:
        inner = _Dot(dot, t.hintColor.withValues(alpha: 0.4));
      case DayMarkState.future:
        inner = null;
    }
    return Container(
      key: tagged ? ValueKey('daymark-${state.name}') : null,
      width: size, height: size,
      decoration: BoxDecoration(
        color: fill,
        shape: BoxShape.circle,
        border: border == null ? null : Border.all(color: border, width: bw),
      ),
      alignment: Alignment.center,
      child: inner,
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot(this.size, this.color);
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: size, height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}

/// 한 줄 범례 — 지킴 · 놓침 · 오늘 · 쉬는 날. 작게, 카드 아래에 둡니다.
class DayMarkLegend extends StatelessWidget {
  const DayMarkLegend({super.key});

  static const items = [
    (DayMarkState.kept, '지킴'),
    (DayMarkState.missed, '놓침'),
    (DayMarkState.today, '오늘'),
    (DayMarkState.rest, '쉬는 날'),
  ];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final style = t.textTheme.labelSmall?.copyWith(color: t.hintColor, fontSize: 10, height: 1);
    return Wrap(
      key: const ValueKey('daymark-legend'),
      spacing: 10, runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final (s, label) in items)
          Row(mainAxisSize: MainAxisSize.min, children: [
            DayMark(s, size: 13, tagged: false),
            const SizedBox(width: 3),
            /* 글자는 RichText 로 — 범례는 내용이 아니라 설명이라, 화면의 「오늘」
               같은 제목을 세는 테스트(find.text)에 안 잡히게 둡니다. */
            RichText(
                text: TextSpan(text: label, style: style),
                textScaler: MediaQuery.textScalerOf(context)),
          ]),
      ],
    );
  }
}

/* --- 화면 ------------------------------------------------------------------ */

class AdherenceScreen extends StatelessWidget {
  const AdherenceScreen({super.key, required this.go});
  final void Function(String route, [Object? arg]) go;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('달성률')),
        body: ListView(padding: const EdgeInsets.all(16), children: [AdherenceBody(go: go)]),
      );
}

/// 플랜 탭 위의 「달성률」이 보여 주는 것. 스크롤은 밖에서 맡습니다.
class AdherenceBody extends StatefulWidget {
  const AdherenceBody({super.key, required this.go});
  final void Function(String route, [Object? arg]) go;

  @override
  State<AdherenceBody> createState() => _AdherenceBodyState();
}

class _AdherenceBodyState extends State<AdherenceBody> {
  String _tab = 'week';

  @override
  Widget build(BuildContext context) {
    final app = Scope.of(context);
    final t = Theme.of(context);
    final target = _targetOf(context);
    final hint = t.textTheme.bodySmall?.copyWith(color: t.hintColor, height: 1.5);
    final n = _tab == 'week' ? 7 : 30;
    final label = _tab == 'week' ? '최근 7일' : '최근 30일';

    final tabs = SegmentedButton<String>(
      showSelectedIcon: false,
      segments: const [
        ButtonSegment(value: 'week', label: Text('주간')),
        ButtonSegment(value: 'month', label: Text('월간')),
      ],
      selected: {_tab},
      onSelectionChanged: (s) => setState(() => _tab = s.first),
    );

    final w = workoutAdherence(app.store, n);
    final streak = app.schedule.workoutStreak();

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      tabs,
      const SizedBox(height: 12),

      /* --- 운동 ------------------------------------------------------------ */
      _WorkoutCard(w: w, streak: streak, label: label, week: _tab == 'week',
          today: app.store.dayKey()),

      /* --- 식단 ------------------------------------------------------------ */
      if (target == null)
        MbCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SectionTitle('식단 · $label'),
            Text('플랜이 하루 칼로리·단백질 목표를 정합니다',
                style: hint),
            const SizedBox(height: 10),
            FilledButton(onPressed: () => widget.go('goal'), child: const Text('플랜 만들기')),
          ]),
        )
      else
        ..._diet(context, target, n, label, hint),
    ]);
  }

  List<Widget> _diet(BuildContext context, Map<String, Object?> target, int n, String label,
      TextStyle? hint) {
    final app = Scope.of(context);
    final days = dietDays(app.store, n);
    final adh = core.dietAdherence(days, target)!;
    final loggedDays = core.jsToNumber(adh['loggedDays']);
    final missedDays = core.jsToNumber(adh['missedDays']);
    final totalDays = core.jsToNumber(adh['totalDays']);
    final avg = (adh['avg'] as Map?)?.cast<String, Object?>();
    final pct = (adh['pct'] as Map?)?.cast<String, Object?>();

    return [
      /* 요약 — 분모를 반드시 명시합니다. */
      MbCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SectionTitle('식단 · $label',
              trailing: Pill('기록 ${n0(loggedDays)}/${n0(totalDays)}일',
                  tone: core.jsToNumber(adh['logRatePct']) >= 70 ? Tone.ok : Tone.none)),
          if (loggedDays == 0)
            Text('이 기간에 기록이 없습니다.', style: hint)
          else ...[
            Row(children: [
              Expanded(child: Stat(label: '칼로리 평균', value: n0(avg?['kcal']), unit: 'kcal',
                  delta: '${n0(pct?['kcal'])}%')),
              Expanded(child: Stat(label: '단백질 평균', value: n0(avg?['p']), unit: 'g',
                  delta: '${n0(pct?['p'])}%')),
            ]),
            Row(children: [
              Expanded(child: Stat(label: '범위 안', value: n0(adh['inBandDays']), unit: '일',
                  delta: '${n0(adh['inBandPct'])}%')),
              Expanded(child: Stat(label: '단백질 달성', value: n0(adh['proteinHitDays']), unit: '일',
                  delta: '${n0(adh['proteinHitPct'])}%')),
            ]),
            const SizedBox(height: 6),
            /* 한 줄 — "0으로 치지 않고 분모에서 뺐다" 는 설명은 "안 적은 날은 뺐다" 로 족합니다. */
            Text(
                '기록한 ${n0(loggedDays)}일 평균'
                '${missedDays > 0 ? ' — 안 적은 ${n0(missedDays)}일은 뺐습니다' : ''}',
                style: hint),
          ],
        ]),
      ),
      if (missedDays >= (totalDays * 0.5).ceil())
        const Note(text: '절반 넘게 안 적었습니다 — 단백질 든 것만 적어도 됩니다'),
      if (_tab == 'week')
        ..._week(context, days, target, adh)
      else
        _month(context, days, target, adh),
      /* 맨 밑의 "하루 값이 아니라 주 평균으로 보세요 · TDEE 추정 오차…" 상자는 뺐습니다 —
         카드가 이미 「평균」 이라고 쓰고 있습니다. */
    ];
  }

  /* 주간 — 일별 막대 + 목표선. 단일 숫자만 보면 "평균은 맞는데 널뛰기" 를 놓칩니다. */
  List<Widget> _week(BuildContext context, List<Map<String, Object?>> days,
      Map<String, Object?> target, Map<String, Object?> adh) {
    final t = Theme.of(context);
    final c = mb(context);
    final avg = (adh['avg'] as Map?)?.cast<String, Object?>();
    final pct = (adh['pct'] as Map?)?.cast<String, Object?>();
    final loggedDays = core.jsToNumber(adh['loggedDays']);
    final specs = [
      ('단백질', 'p', core.jsToNumber(target['proteinG']), c.muscle, 'g'),
      ('칼로리', 'kcal', core.jsToNumber(target['intakeKcal']), t.colorScheme.primary, 'kcal'),
      ('탄수화물', 'c', core.jsToNumber(target['carbG']), t.hintColor, 'g'),
      ('지방', 'f', core.jsToNumber(target['fatG']), c.fat, 'g'),
    ];
    return [
      for (final s in specs)
        MbCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SectionTitle(s.$1),
            _DayBars(days: days, field: s.$2, target: s.$3, color: s.$4, unit: s.$5),
            const SizedBox(height: 6),
            Text(
                loggedDays > 0
                    ? '평균 ${n0(avg?[s.$2])}${s.$5} · 목표의 ${n0(pct?[s.$2])}%'
                    : '기록 없음',
                style: t.textTheme.bodySmall?.copyWith(color: t.hintColor)),
          ]),
        ),
    ];
  }

  /* 월간 — 패턴을 봅니다. 미기록일은 0이 아니라 "없음" 으로 그립니다. */
  Widget _month(BuildContext context, List<Map<String, Object?>> days,
      Map<String, Object?> target, Map<String, Object?> adh) {
    final t = Theme.of(context);
    final c = mb(context);
    final band = (adh['band'] as Map?)?.cast<String, Object?>();
    final lo = core.jsToNumber(band?['lo']), hi = core.jsToNumber(band?['hi']);
    final tp = core.jsToNumber(target['proteinG']);
    return MbCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionTitle('식단 30일',
            trailing: Text('칸 하나 = 하루', style: t.textTheme.labelSmall?.copyWith(color: t.hintColor))),
        GridView.count(
          crossAxisCount: 7, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 4, crossAxisSpacing: 4,
          children: [
            for (final d in days)
              Builder(builder: (_) {
                final logged = core.jsTruthy(d['logged']);
                final kcal = core.jsToNumber(d['kcal']);
                Color bg = t.scaffoldBackgroundColor;
                if (logged) {
                  bg = kcal < lo
                      ? t.colorScheme.primary.withValues(alpha: 0.25)
                      : (kcal > hi ? c.warn.withValues(alpha: 0.35) : c.ok.withValues(alpha: 0.35));
                }
                final hit = logged && core.jsToNumber(d['p']) >= tp * 0.9;
                return Container(
                  decoration: BoxDecoration(
                      color: bg, borderRadius: BorderRadius.circular(6),
                      border: logged ? null : Border.all(color: t.dividerColor)),
                  alignment: Alignment.center,
                  child: hit ? Text('•', style: TextStyle(color: c.muscle, fontSize: 14)) : null,
                );
              }),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 10, runSpacing: 6, children: [
          _Legend('범위 안', c.ok.withValues(alpha: 0.35)),
          _Legend('범위 위', c.warn.withValues(alpha: 0.35)),
          _Legend('범위 아래', t.colorScheme.primary.withValues(alpha: 0.25)),
          _Legend('기록 없음', t.scaffoldBackgroundColor, dashed: true),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Text('•', style: TextStyle(color: c.muscle)),
            const SizedBox(width: 3),
            Text('단백질 달성', style: t.textTheme.labelSmall?.copyWith(color: t.hintColor)),
          ]),
        ]),
        /* "정확한 값이 아니라 패턴을 보라" 는 한 줄은 뺐습니다 — 범례가 있는 격자는
           그 자체로 패턴입니다. */
      ]),
    );
  }
}

/* --- 일별 막대 ---------------------------------------------------------------
 *
 * 축선은 바닥에 하나, 막대는 거기서 위로. 목표선은 축선에서 70% 높이의
 * **점선** + 오른쪽 끝 「목표 149g」 라벨이고, 막대 높이 = min(값/목표, 1.4)
 * × 목표선 높이 — 목표를 넘으면 그만큼 더 솟되 카드 밖으로는 안 나갑니다
 * (1.4 × 0.7 = 0.98). 요일 글자는 막대 바로 밑, 기록 없는 날은 막대 없이
 * 글자만 흐리게 — "·" 는 무슨 뜻인지 물어보게 만듭니다.
 *
 * 0.2.12 버그(피드백 35)의 원인: 막대 Row 가 Stack 의 Positioned 가 아닌
 * 자식이었습니다. Stack 은 그런 자식에 느슨한 제약을 주고 기본 정렬
 * (topStart)로 놓기 때문에, Row 높이가 가장 큰 막대만큼으로 줄고 그 Row 가
 * Stack **꼭대기**에 붙었습니다 — 높이(0.39 × 0.7 × 84 = 23px)는 맞았는데
 * 시작점이 축선이 아니라 위였던 것. 그래서 막대가 목표 점선 위에 매달리고
 * 축선까지 비었습니다. 지금은 Positioned.fill 로 Stack 을 꽉 채우고
 * CrossAxisAlignment.end 로 바닥에 붙입니다. 기하는 week_marks_test 가
 * RenderBox 로 잽니다(막대 bottom == 축선, 높이 비율, 목표 초과). */
class _DayBars extends StatelessWidget {
  const _DayBars({required this.days, required this.field, required this.target,
      required this.color, required this.unit});
  final List<Map<String, Object?>> days;
  final String field;
  final double target;
  final Color color;
  final String unit;

  static const double height = 84;
  static const double targetFrac = 0.7;
  static const double maxRatio = 1.4;
  static const double gap = 3, dowHeight = 10;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final labelStyle = t.textTheme.labelSmall?.copyWith(color: t.hintColor, fontSize: 10, height: 1);
    final lineColor = t.hintColor.withValues(alpha: 0.6);

    final bars = SizedBox(
      key: ValueKey('daybars-chart-$field'),
      height: height,
      child: Stack(children: [
        /* 막대 — Positioned.fill 이라 Row 가 Stack 높이를 다 차지하고, end 정렬로
           막대가 바닥에 섭니다. 이걸 빼면 위의 버그가 돌아옵니다. */
        Positioned.fill(
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (final d in days)
              Expanded(
                child: Builder(builder: (_) {
                  if (!core.jsTruthy(d['logged'])) return const SizedBox.shrink();
                  final v = core.jsToNumber(d[field] ?? 0);
                  final ratio = target > 0 ? v / target : 0.0;
                  final frac = math.min(ratio, maxRatio) * targetFrac;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Container(
                      key: ValueKey('daybar-$field-${d['date']}'),
                      height: math.max(2.0, frac * height),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: v >= target * 0.9 ? 1 : 0.55),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                      ),
                    ),
                  );
                }),
              ),
          ]),
        ),
        /* 목표선 — 축선에서 70% 높이의 점선. 막대와 같은 스케일이라 "넘었나" 가
           바로 보입니다. */
        Positioned(
          left: 0, right: 0, bottom: height * targetFrac,
          child: CustomPaint(
              key: ValueKey('daybars-target-$field'),
              size: const Size(double.infinity, 1), painter: _DashPainter(lineColor)),
        ),
        /* 축선 — 바닥에. */
        Positioned(
          left: 0, right: 0, bottom: 0,
          child: Container(
              key: ValueKey('daybars-axis-$field'), height: 1, color: t.dividerColor),
        ),
      ]),
    );

    /* 요일 줄 — 막대 바로 밑에 붙입니다. 글자 높이는 height:1 로 고정해서
       (fontSize 10 = 10px) 오른쪽 라벨 칸이 같은 만큼 비울 수 있습니다. */
    final dows = Row(children: [
      for (final d in days)
        Expanded(
          child: Text(_dowOf('${d['date']}'),
              textAlign: TextAlign.center,
              style: labelStyle?.copyWith(
                  color: core.jsTruthy(d['logged'])
                      ? t.hintColor
                      : t.hintColor.withValues(alpha: 0.35))),
        ),
    ]);

    return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          bars, const SizedBox(height: gap), dows,
        ]),
      ),
      /* 라벨은 선의 오른쪽 끝, 자기 칸에 — 막대를 가리지 않습니다. 세로 자리는
         목표선과 같은 비율(위에서 30%)에 가운데를 맞춥니다. */
      Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          height: height,
          child: Align(
            alignment: const Alignment(0, 1 - 2 * targetFrac),
            child: Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Text('목표 ${n0(target)}$unit', style: labelStyle),
            ),
          ),
        ),
        const SizedBox(height: gap + dowHeight),
      ]),
    ]);
  }
}

class _DashPainter extends CustomPainter {
  const _DashPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color..strokeWidth = 1;
    const on = 4.0, off = 3.0;
    for (var x = 0.0; x < size.width; x += on + off) {
      canvas.drawLine(Offset(x, 0.5), Offset(math.min(x + on, size.width), 0.5), p);
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => old.color != color;
}

/* --- 운동 ------------------------------------------------------------------
   "지킨 날 / 계획한 날". 오늘 아직 안 한 것은 놓친 게 아니라 열린 것이라
   분모에 안 넣습니다 — 아침에 열어 보고 0% 를 맞으면 안 됩니다. */
class _WorkoutCard extends StatelessWidget {
  const _WorkoutCard({required this.w, required this.streak, required this.label,
      required this.week, required this.today});
  final Map<String, Object?> w;
  final Map<String, Object?> streak;
  final String label;
  final bool week;
  final String today;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final hint = t.textTheme.bodySmall?.copyWith(color: t.hintColor, height: 1.5);
    final planned = core.jsToNumber(w['plannedDays']);
    final kept = core.jsToNumber(w['keptDays']);
    final missed = core.jsToNumber(w['missedDays']);
    final open = core.jsToNumber(w['openDays']);
    final pct = w['pct'];
    final byType = (w['byType'] as Map?)?.cast<String, Map<String, int>>() ?? const {};
    final days = ((w['days'] as List?) ?? const []).cast<Map<String, Object?>>();
    final types = [
      for (final st in core.kSchedTypes)
        if (byType.containsKey(st['id']))
          '${st['label']} ${byType[st['id']]!['done']}/${byType[st['id']]!['planned']}',
    ];

    return MbCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionTitle('운동 · $label',
            trailing: Pill('계획 ${n0(planned)}일', tone: planned > 0 ? Tone.ok : Tone.none)),
        if (planned == 0)
          Text('계획한 운동이 없습니다 — 홈에서 요일을 켜 두세요', style: hint)
        else ...[
          Row(children: [
            Expanded(child: Stat(label: '지킨 날', value: n0(kept), unit: '일',
                delta: pct == null ? '오늘만 남음' : '${n0(pct)}%')),
            Expanded(child: Stat(label: '놓친 날', value: n0(missed), unit: '일',
                delta: open > 0 ? '오늘 ${n0(open)}일 남음' : null)),
          ]),
          const SizedBox(height: 6),
          if (types.isNotEmpty) Text(types.join(' · '), style: hint),
          /* "계획한 날만 세고 쉬는 날은 끊지 않는다" 는 규칙 설명은 뺐습니다 — 숫자 둘이면 됩니다. */
          Text('연속 ${n0(streak['days'])}일 · 최근 28일 중 ${n0(streak['last28'])}일', style: hint),
        ],
        const SizedBox(height: 10),
        if (week) _WeekStrip(days: days, today: today) else _MonthGrid(days: days, today: today),
        const SizedBox(height: 8),
        const DayMarkLegend(),
      ]),
    );
  }
}

/// 7칸 — 요일 + DayMark.
class _WeekStrip extends StatelessWidget {
  const _WeekStrip({required this.days, required this.today});
  final List<Map<String, Object?>> days;
  final String today;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Row(children: [
      for (final d in days)
        Expanded(
          child: Column(children: [
            Text('${d['dow']}',
                style: t.textTheme.labelSmall?.copyWith(
                    color: core.jsTruthy(d['isToday']) ? t.colorScheme.primary : t.hintColor)),
            const SizedBox(height: 4),
            DayMark(dayMarkState(d, today: today)),
          ]),
        ),
    ]);
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({required this.days, required this.today});
  final List<Map<String, Object?>> days;
  final String today;

  @override
  Widget build(BuildContext context) => GridView.count(
        crossAxisCount: 10, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 4, crossAxisSpacing: 4,
        children: [
          for (final d in days) Center(child: DayMark(dayMarkState(d, today: today), size: 20)),
        ],
      );
}

class _Legend extends StatelessWidget {
  const _Legend(this.label, this.color, {this.dashed = false});
  final String label;
  final Color color;
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 11, height: 11,
        decoration: BoxDecoration(
            color: color, borderRadius: BorderRadius.circular(3),
            border: dashed ? Border.all(color: t.dividerColor) : null),
      ),
      const SizedBox(width: 4),
      Text(label, style: t.textTheme.labelSmall?.copyWith(color: t.hintColor)),
    ]);
  }
}
