/* =============================================================================
 * theme.dart — 지금 앱과 **같은 색**을 씁니다
 *
 * 값은 prototype/css/base.css 의 토큰에서 그대로 가져왔습니다. 베껴 쓰는
 * 것이 아니라 옮기는 것이라, 색이 달라지면 두 앱이 서로 다른 제품처럼
 * 보입니다 — 친구들은 같은 앱의 새 버전이라고 생각하고 받을 텐데요.
 *
 * 다크 모드 값도 같이 들고 있습니다. 지금 앱이 그걸 지원하고, 폰에서
 * 다크로 쓰던 사람이 옮겨 오면 갑자기 눈이 부시면 안 됩니다.
 * ========================================================================== */
import 'package:flutter/material.dart';

class MbColors extends ThemeExtension<MbColors> {
  final Color ok, okBg, warn, warnBg, bad, badBg, fat, muscle, weight, accentSub;
  const MbColors({
    required this.ok, required this.okBg,
    required this.warn, required this.warnBg,
    required this.bad, required this.badBg,
    required this.fat, required this.muscle, required this.weight,
    required this.accentSub,
  });

  static const light = MbColors(
    ok: Color(0xFF15803D), okBg: Color(0xFFE8F6EC),
    warn: Color(0xFFB45309), warnBg: Color(0xFFFDF3E3),
    bad: Color(0xFFB91C1C), badBg: Color(0xFFFDECEB),
    fat: Color(0xFFE0703A), muscle: Color(0xFF2F7DE1), weight: Color(0xFF6B7280),
    accentSub: Color(0xFFEEF0FF),
  );

  /* 어두운 배경에서는 같은 색이 안 읽힙니다. 지금 앱의 다크 토큰과
     같은 자리를 씁니다 — 색만 밝게 올린 것이 아니라 대비를 맞춘 값입니다. */
  static const dark = MbColors(
    ok: Color(0xFF4ADE80), okBg: Color(0xFF14301F),
    warn: Color(0xFFFBBF24), warnBg: Color(0xFF332412),
    bad: Color(0xFFF87171), badBg: Color(0xFF3A1A1A),
    fat: Color(0xFFF08A54), muscle: Color(0xFF5FA0F0), weight: Color(0xFF9AA2AE),
    accentSub: Color(0xFF232842),
  );

  @override
  MbColors copyWith({Color? ok, Color? okBg, Color? warn, Color? warnBg,
      Color? bad, Color? badBg, Color? fat, Color? muscle, Color? weight,
      Color? accentSub}) =>
      MbColors(
        ok: ok ?? this.ok, okBg: okBg ?? this.okBg,
        warn: warn ?? this.warn, warnBg: warnBg ?? this.warnBg,
        bad: bad ?? this.bad, badBg: badBg ?? this.badBg,
        fat: fat ?? this.fat, muscle: muscle ?? this.muscle,
        weight: weight ?? this.weight, accentSub: accentSub ?? this.accentSub,
      );

  @override
  MbColors lerp(ThemeExtension<MbColors>? other, double t) {
    if (other is! MbColors) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return MbColors(
      ok: c(ok, other.ok), okBg: c(okBg, other.okBg),
      warn: c(warn, other.warn), warnBg: c(warnBg, other.warnBg),
      bad: c(bad, other.bad), badBg: c(badBg, other.badBg),
      fat: c(fat, other.fat), muscle: c(muscle, other.muscle),
      weight: c(weight, other.weight), accentSub: c(accentSub, other.accentSub),
    );
  }
}

const _accent = Color(0xFF4F46E5);

ThemeData _base(Brightness b) {
  final dark = b == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: _accent,
    brightness: b,
    primary: _accent,
    onPrimary: Colors.white,
    surface: dark ? const Color(0xFF171A20) : Colors.white,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    /* 한글은 앱에 넣어 둔 글꼴로 그립니다. 시스템 글꼴에 기대면
       CanvasKit 이 못 찾아서 네모로 나옵니다. */
    fontFamily: 'NotoSansKR',
    scaffoldBackgroundColor: dark ? const Color(0xFF0E1014) : const Color(0xFFF6F7F9),
    dividerColor: dark ? const Color(0xFF2A2F39) : const Color(0xFFE2E5EA),
    extensions: [dark ? MbColors.dark : MbColors.light],
    appBarTheme: AppBarTheme(
      backgroundColor: dark ? const Color(0xFF171A20) : Colors.white,
      foregroundColor: dark ? const Color(0xFFE9ECF1) : const Color(0xFF16181D),
      elevation: 0,
      scrolledUnderElevation: 0.5,
      centerTitle: false,
    ),
  );
}

ThemeData mbLight() => _base(Brightness.light);
ThemeData mbDark() => _base(Brightness.dark);
