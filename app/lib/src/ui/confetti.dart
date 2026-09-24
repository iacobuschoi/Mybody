/* =============================================================================
 * confetti.dart — 폭죽
 *
 * 운동을 마친 사람에게 검은 스낵바 한 줄("수고했어요")은 모자랍니다 — 주인이
 * 실기기에서 보고 "못생겼다" 고 했습니다. 색종이 백여 장이 위에서 쏟아지고
 * 천천히 흩어집니다. 패키지는 안 씁니다: CustomPainter 하나면 되고, 의존성
 * 하나가 늘면 빌드가 하나 더 깨질 자리가 생깁니다.
 *
 * 그리는 규칙
 *   · 조각마다 시작 x · 옆으로 흐르는 속도 · 떨어지는 속도 · 크기 · 회전 ·
 *     지연이 있습니다. 지연은 0~0.35 — 한꺼번에 떨어지면 커튼처럼 보입니다.
 *   · 위치는 t 의 이차식(중력)입니다. 마지막 25% 에서 투명해집니다.
 *   · 시험에서 같은 그림을 얻으려면 seed 를 넣습니다.
 *
 * 입력은 막지 않습니다(IgnorePointer) — 폭죽 밑의 「닫기」 를 눌러야 합니다.
 * ========================================================================== */
import 'dart:math' as math;

import 'package:flutter/material.dart';

class Confetti extends StatefulWidget {
  const Confetti({
    super.key,
    this.count = 140,
    this.duration = const Duration(milliseconds: 2800),
    this.colors,
    this.seed,
  });

  final int count;
  final Duration duration;

  /// 없으면 테마 색(주 색 · 삼차 색 · 지방색 · 근육색 · 초록) 다섯.
  final List<Color>? colors;
  final int? seed;

  @override
  State<Confetti> createState() => _ConfettiState();
}

class _ConfettiState extends State<Confetti> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: widget.duration)..forward();
  late final List<_Piece> _pieces = _make(widget.count, math.Random(widget.seed));

  static List<_Piece> _make(int n, math.Random r) => [
        for (var i = 0; i < n; i++)
          _Piece(
            x0: r.nextDouble(),
            vx: (r.nextDouble() - 0.5) * 0.5,
            vy: 0.55 + r.nextDouble() * 0.55,
            size: 6 + r.nextDouble() * 8,
            rot: r.nextDouble() * math.pi,
            rotV: (r.nextDouble() - 0.5) * 8,
            delay: r.nextDouble() * 0.35,
            color: i % 5,
            round: r.nextInt(4) == 0,
          ),
      ];

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = widget.colors ??
        [
          scheme.primary,
          scheme.tertiary,
          const Color(0xFFE8703A),
          const Color(0xFF2F7BE8),
          const Color(0xFF2E9E5B),
        ];
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) => CustomPaint(
          painter: _ConfettiPainter(_pieces, _c.value, colors),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _Piece {
  const _Piece({
    required this.x0,
    required this.vx,
    required this.vy,
    required this.size,
    required this.rot,
    required this.rotV,
    required this.delay,
    required this.color,
    required this.round,
  });
  final double x0, vx, vy, size, rot, rotV, delay;
  final int color;
  final bool round;
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.pieces, this.progress, this.colors);
  final List<_Piece> pieces;
  final double progress;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (final p in pieces) {
      final t = ((progress - p.delay) / (1 - p.delay)).clamp(0.0, 1.0);
      if (t <= 0) continue;
      /* 위에서 떨어집니다 — 이차식이라 처음엔 천천히, 갈수록 빨리. */
      final x = (p.x0 + p.vx * t) * size.width;
      final y = -p.size + (p.vy * t + 0.9 * t * t) * size.height;
      if (y > size.height + p.size) continue;
      final fade = t > 0.75 ? (1 - (t - 0.75) / 0.25) : 1.0;
      paint.color = colors[p.color % colors.length].withValues(alpha: fade.clamp(0.0, 1.0));
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p.rot + p.rotV * t);
      /* 회전하며 납작해 보이는 종이 — 폭을 cos 로 줄입니다. */
      final w = p.size * (0.35 + 0.65 * math.cos(p.rotV * t * 1.7).abs());
      final rect = Rect.fromCenter(center: Offset.zero, width: w, height: p.size * 0.6);
      if (p.round) {
        canvas.drawOval(rect, paint);
      } else {
        canvas.drawRect(rect, paint);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.progress != progress || old.pieces != pieces;
}
