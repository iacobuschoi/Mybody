/* =============================================================================
 * charts.dart — 추이선 · 스파크라인 · 도넛 · 타임라인
 *
 * 지금 앱은 SVG 로 그립니다. 여기서는 CustomPainter 로 같은 그림을 그립니다 —
 * 축 여백, 격자 3줄, 목표선의 점선 간격까지 같은 값입니다. 차트는 사람이
 * 눈으로 비교하는 것이라, 눈금이 조금만 달라져도 "다르게 갔다" 로 읽힙니다.
 * ========================================================================== */
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'fmt.dart';

class Pt {
  const Pt(this.x, this.y);
  final double x, y;
}

class Series {
  const Series({required this.label, required this.points, required this.color,
      this.dashed = false, this.width = 1.8, this.dots = true});
  final String label;
  final List<Pt> points;
  final Color color;
  final bool dashed;
  final double width;
  final bool dots;
}

class GoalLine {
  const GoalLine({required this.y, required this.color, this.label});
  final double y;
  final Color color;
  final String? label;
}

class Marker {
  const Marker({required this.x, this.label});
  final double x;
  final String? label;
}

/// 추이선. 값이 없으면 **없다고 말합니다** — 빈 네모를 그리지 않습니다.
class LineChart extends StatelessWidget {
  const LineChart({
    super.key,
    required this.series,
    this.height = 150,
    this.goals = const [],
    this.markers = const [],
    this.legend = true,
    this.xTickFmt,
  });

  final List<Series> series;
  final double height;
  final List<GoalLine> goals;
  final List<Marker> markers;
  final bool legend;
  final String Function(double)? xTickFmt;

  @override
  Widget build(BuildContext context) {
    final live = series.where((s) => s.points.isNotEmpty).toList();
    if (live.isEmpty) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text('표시할 데이터가 없습니다',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).hintColor)),
        ),
      );
    }
    final fg = Theme.of(context).colorScheme.onSurface;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: _LinePainter(
            series: live, goals: goals, markers: markers,
            fg: fg, surface: Theme.of(context).colorScheme.surface,
            xTickFmt: xTickFmt ?? (v) => '${v.round()}',
            /* **글꼴을 넘겨줍니다.** CustomPainter 안의 TextPainter 는 테마를
               모릅니다. 글꼴을 안 주면 기본값(Roboto)을 쓰는데, 우리는 그걸
               앱에 안 넣었습니다 — 웹에서는 축 숫자가 **통째로 안 보였고**
               구글에 Roboto 를 받으러 갔습니다. 눈금 없는 그래프는 그림일
               뿐이라 수치를 읽을 수가 없습니다. */
            fontFamily: Theme.of(context).textTheme.bodySmall?.fontFamily,
          ),
        ),
      ),
      if (legend)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Wrap(spacing: 12, runSpacing: 4, children: [
            for (final s in live)
              Row(mainAxisSize: MainAxisSize.min, children: [
                /* 점선으로 그리는 선은 범례도 점선으로 — 같은 색 실선이면 「체중」과
                   「체크인 체중」이 범례에서 구분되지 않았습니다(노트북 확인). */
                if (s.dashed)
                  SizedBox(
                    key: const ValueKey('legend-dashed'),
                    width: 10,
                    height: 2.5,
                    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      for (var i = 0; i < 2; i++)
                        Container(width: 4, height: 2.5,
                            decoration: BoxDecoration(color: s.color, borderRadius: BorderRadius.circular(2))),
                    ]),
                  )
                else
                  Container(width: 10, height: 2.5,
                      decoration: BoxDecoration(color: s.color, borderRadius: BorderRadius.circular(2))),
                const SizedBox(width: 4),
                Text(s.label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                    color: Theme.of(context).hintColor)),
              ]),
          ]),
        ),
    ]);
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter({required this.series, required this.goals, required this.markers,
      required this.fg, required this.surface, required this.xTickFmt,
      required this.fontFamily});
  final List<Series> series;
  final List<GoalLine> goals;
  final List<Marker> markers;
  final Color fg, surface;
  final String Function(double) xTickFmt;
  final String? fontFamily;

  static const padL = 34.0, padR = 12.0, padT = 12.0, padB = 22.0;

  @override
  void paint(Canvas canvas, Size size) {
    final xs = <double>[], ys = <double>[];
    for (final s in series) {
      for (final p in s.points) {
        if (p.x.isFinite) xs.add(p.x);
        if (p.y.isFinite) ys.add(p.y);
      }
    }
    for (final g in goals) {
      if (g.y.isFinite) ys.add(g.y);
    }
    if (xs.isEmpty || ys.isEmpty) return;

    var xmin = xs.reduce(math.min), xmax = xs.reduce(math.max);
    var ymin = ys.reduce(math.min), ymax = ys.reduce(math.max);
    final yPad = (ymax - ymin) * 0.15 == 0 ? 1.0 : (ymax - ymin) * 0.15;
    ymin -= yPad;
    ymax += yPad;
    if (xmax == xmin) xmax = xmin + 1;

    double sx(double x) => padL + (x - xmin) / (xmax - xmin) * (size.width - padL - padR);
    double sy(double y) => padT + (1 - (y - ymin) / (ymax - ymin)) * (size.height - padT - padB);

    void label(String text, Offset at, {TextAlign align = TextAlign.left, Color? color, double fontSize = 8}) {
      final tp = TextPainter(
        text: TextSpan(
            text: text,
            style: TextStyle(
                fontFamily: fontFamily,
                fontSize: fontSize,
                color: color ?? fg.withValues(alpha: 0.55))),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      var dx = at.dx;
      if (align == TextAlign.center) dx -= tp.width / 2;
      if (align == TextAlign.right) dx -= tp.width;
      tp.paint(canvas, Offset(dx, at.dy));
    }

    // y 격자 3줄
    final grid = Paint()..color = fg.withValues(alpha: 0.10)..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final yv = ymin + (ymax - ymin) * i / 3;
      canvas.drawLine(Offset(padL, sy(yv)), Offset(size.width - padR, sy(yv)), grid);
      label(yv.toStringAsFixed(1), Offset(2, sy(yv) - 5));
    }

    // 목표선 (점선)
    for (final g in goals) {
      if (!g.y.isFinite) continue;
      _dashed(canvas, Offset(padL, sy(g.y)), Offset(size.width - padR, sy(g.y)),
          Paint()..color = g.color.withValues(alpha: 0.8)..strokeWidth = 1.2, 4, 3);
      if (g.label != null) {
        label(g.label!, Offset(size.width - padR, sy(g.y) - 11),
            align: TextAlign.right, color: g.color);
      }
    }

    // 구간 마커 (단계 전환)
    for (final m in markers) {
      if (!m.x.isFinite) continue;
      _dashed(canvas, Offset(sx(m.x), padT), Offset(sx(m.x), size.height - padB),
          Paint()..color = fg.withValues(alpha: 0.18)..strokeWidth = 1, 2, 3);
      if (m.label != null) label(m.label!, Offset(sx(m.x) + 2, padT), fontSize: 7.5);
    }

    // 선
    for (final s in series) {
      final pts = s.points.where((p) => p.x.isFinite && p.y.isFinite).toList();
      if (pts.isEmpty) continue;
      final path = Path();
      for (var i = 0; i < pts.length; i++) {
        final o = Offset(sx(pts[i].x), sy(pts[i].y));
        if (i == 0) {
          path.moveTo(o.dx, o.dy);
        } else {
          path.lineTo(o.dx, o.dy);
        }
      }
      final stroke = Paint()
        ..color = s.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = s.width
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round;
      if (s.dashed) {
        _dashedPath(canvas, pts.map((p) => Offset(sx(p.x), sy(p.y))).toList(), stroke, 4, 3);
      } else {
        canvas.drawPath(path, stroke);
      }
      if (s.dots && pts.length <= 24) {
        for (final p in pts) {
          canvas.drawCircle(Offset(sx(p.x), sy(p.y)), 2.4, Paint()..color = s.color);
        }
      }
      final last = pts.last;
      canvas.drawCircle(Offset(sx(last.x), sy(last.y)), 3.2, Paint()..color = s.color);
      canvas.drawCircle(Offset(sx(last.x), sy(last.y)), 3.2,
          Paint()..color = surface..style = PaintingStyle.stroke..strokeWidth = 1.5);
    }

    // x축 라벨 셋
    final xls = [xmin, (xmin + xmax) / 2, xmax];
    for (var i = 0; i < 3; i++) {
      label(xTickFmt(xls[i]), Offset(sx(xls[i]), size.height - 14),
          align: i == 0 ? TextAlign.left : (i == 2 ? TextAlign.right : TextAlign.center));
    }
  }

  void _dashed(Canvas c, Offset a, Offset b, Paint p, double on, double off) =>
      _dashedPath(c, [a, b], p, on, off);

  void _dashedPath(Canvas c, List<Offset> pts, Paint p, double on, double off) {
    for (var i = 1; i < pts.length; i++) {
      final a = pts[i - 1], b = pts[i];
      final len = (b - a).distance;
      if (len == 0) continue;
      final dir = (b - a) / len;
      var t = 0.0;
      while (t < len) {
        final e = math.min(t + on, len);
        c.drawLine(a + dir * t, a + dir * e, p);
        t = e + off;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _LinePainter old) => true;
}

/// 작은 추이선. 값이 둘 미만이면 **아무것도 안 그립니다** —
/// 점 하나로 선을 그리면 없는 추세를 보여주게 됩니다.
class Sparkline extends StatelessWidget {
  const Sparkline(this.values, {super.key, this.color, this.height = 28});
  final List<double> values;
  final Color? color;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (values.length < 2) return SizedBox(height: height);
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
          painter: _SparkPainter(values, color ?? Theme.of(context).colorScheme.primary)),
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.values, this.color);
  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    var min = values.reduce(math.min), max = values.reduce(math.max);
    if (max == min) max = min + 1;
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = i / (values.length - 1) * size.width;
      final y = size.height - 3 - (values[i] - min) / (max - min) * (size.height - 6);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(covariant _SparkPainter old) => old.values != values;
}

/// 도넛. 진행률을 그리되 **100%를 넘겨 그리지 않습니다** —
/// 넘긴 것을 넘겼다고 말하는 건 숫자가 할 일이고, 그림이 할 일이 아닙니다.
class Donut extends StatelessWidget {
  const Donut({super.key, required this.pct, this.color, this.size = 92, this.center});
  final double? pct;
  final Color? color;
  final double size;
  final Widget? center;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return SizedBox(
      width: size, height: size,
      child: Stack(alignment: Alignment.center, children: [
        CustomPaint(
          size: Size(size, size),
          painter: _DonutPainter(
            pct: pct == null || !pct!.isFinite ? null : pct!.clamp(0, 100).toDouble(),
            color: c,
            track: Theme.of(context).dividerColor,
          ),
        ),
        center ??
            Text(pct == null || !pct!.isFinite ? '—' : '${n0(pct)}%',
                style: TextStyle(fontSize: size * 0.22, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({required this.pct, required this.color, required this.track});
  final double? pct;
  final Color color, track;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width * 0.11;
    final rect = Offset(w / 2, w / 2) & Size(size.width - w, size.height - w);
    canvas.drawArc(rect, 0, math.pi * 2, false,
        Paint()..color = track..style = PaintingStyle.stroke..strokeWidth = w);
    if (pct == null) return;
    canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * (pct! / 100), false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = w
          ..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) => old.pct != pct;
}

/// 단계 막대 — 감량 → 유지 → 증량처럼 계획이 몇 토막인지 보여줍니다.
class PhaseBar extends StatelessWidget {
  const PhaseBar({super.key, required this.phases, required this.totalWeeks});
  final List<Map<String, Object?>> phases;
  final double totalWeeks;

  @override
  Widget build(BuildContext context) {
    if (phases.isEmpty || !totalWeeks.isFinite || totalWeeks <= 0) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        height: 10,
        child: Row(children: [
          for (final p in phases)
            Expanded(
              flex: math.max(1,
                  (((p['weeks'] ?? ((p['to'] as num? ?? 0) - (p['from'] as num? ?? 0))) as num)
                          .toDouble() *
                      100).round()),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 1),
                decoration: BoxDecoration(
                  color: _phaseColor(context, '${p['phase']}'),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
        ]),
      ),
      const SizedBox(height: 6),
      Wrap(spacing: 10, runSpacing: 2, children: [
        for (final p in phases)
          Text('${p['name']}', style: TextStyle(fontSize: 11, color: _phaseColor(context, '${p['phase']}'),
              fontWeight: FontWeight.w600)),
      ]),
    ]);
  }

  static Color _phaseColor(BuildContext context, String phase) {
    final t = Theme.of(context);
    return switch (phase) {
      'cut' => const Color(0xFFE0703A),
      'bulk' => const Color(0xFF2F7DE1),
      _ => t.hintColor,
    };
  }
}
