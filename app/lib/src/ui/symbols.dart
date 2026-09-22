/* =============================================================================
 * symbols.dart — 이모지와 별표를 **글꼴에 기대지 않고** 그립니다
 *
 * 코어(엔진·모드)는 문구 안에 기호를 섞어 내보냅니다:
 *   feasibility.badge   ⛔ 🟢 🟡 🔴
 *   difficultyLabel     ★☆☆ 낮음
 *   일정 종목           🏋️ 🏃
 *
 * 웹 앱에서는 브라우저가 알아서 그려 줬습니다. 그런데 Flutter 는 글꼴에
 * 없는 글자를 만나면 **구글에서 받아 오려고 합니다.** 우리가 넣어 둔
 * 한글 글꼴에는 한글 12,239자가 다 있지만 ★ 과 이모지는 없습니다.
 *
 * 그래서 실제로 이런 일이 일어났습니다 — 화면 한 번 도는 동안
 * fonts.gstatic.com 으로 요청이 **1,900건** 나갔습니다. 망이 막힌 곳에서는
 * 그 자리가 네모가 되고, 안 막힌 곳에서는 몸 관리 앱을 켤 때마다
 * 구글에 신호가 갑니다. 둘 다 안 됩니다.
 *
 * 코어의 문자열은 **안 고칩니다** — 웹 앱과 같은 값이어야 하고, 그쪽에서는
 * 잘 보입니다. 대신 화면에서 그 기호를 알아보고 Flutter 가 이미 들고 있는
 * 것(Material 아이콘, 색칠한 원)으로 그립니다.
 * ========================================================================== */
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'widgets.dart';

/// 실현가능성 배지(⛔🟢🟡🔴) → 색칠한 동그라미.
class VerdictDot extends StatelessWidget {
  const VerdictDot(this.verdict, {super.key, this.size = 10});
  final Object? verdict;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = mb(context);
    final (color, icon) = switch ('$verdict') {
      'blocked' => (c.bad, LucideIcons.ban),
      'ok' => (c.ok, null),
      'tough' => (c.warn, null),
      'unrealistic' => (c.bad, null),
      _ => (Theme.of(context).hintColor, null),
    };
    if (icon != null) return Icon(icon, size: size + 4, color: color);
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

/// 강도(1~3) → 별 세 개. 코어의 '★☆☆ 낮음' 과 같은 뜻입니다.
class DifficultyStars extends StatelessWidget {
  const DifficultyStars(this.level, {super.key, this.size = 13});
  final int level;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = mb(context);
    final color = switch (level) {
      1 => c.ok,
      2 => c.warn,
      _ => c.bad,
    };
    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (var i = 1; i <= 3; i++)
        Icon(i <= level ? Icons.star : Icons.star_outline,
            size: size, color: i <= level ? color : Theme.of(context).hintColor),
    ]);
  }
}

/// 코어가 붙여 보낸 라벨에서 별표를 떼어 냅니다 ('★☆☆ 낮음' → '낮음').
String withoutStars(Object? label) =>
    '${label ?? ''}'.replaceAll(RegExp(r'[★☆]'), '').trim();

/// 일정 종목(gym·cardio) → Material 아이콘.
IconData schedIcon(Object? typeId) =>
    typeId == 'cardio' ? LucideIcons.footprints : LucideIcons.dumbbell;

/* --- 한국어 조사 -------------------------------------------------------------
 *
 * "친구은 로그인해야" 를 실제로 화면에 띄웠습니다. 받침 있는 말과 없는 말에
 * 붙는 조사가 다른데, 문자열에 하나를 박아 두면 다른 말이 들어오는 순간
 * 틀립니다. 코어의 modes.dart 에 이미 같은 판정이 있지만(거부 문구용),
 * 화면 쪽에서도 쓸 수 있게 여기 둡니다.
 * -------------------------------------------------------------------------- */

final RegExp _endsDigit = RegExp(r'[0-9]$');
final RegExp _endsConsonantDigit = RegExp(r'[0136780]$');

bool hasFinalConsonant(String s) {
  if (s.isEmpty) return false;
  final c = s.codeUnitAt(s.length - 1);
  if (c < 0xAC00 || c > 0xD7A3) {
    return _endsDigit.hasMatch(s) ? _endsConsonantDigit.hasMatch(s) : true;
  }
  return (c - 0xAC00) % 28 != 0;
}

/// `josa('친구', '은', '는')` → '친구는'
String josa(String word, String withBatchim, String without) =>
    word + (hasFinalConsonant(word) ? withBatchim : without);
