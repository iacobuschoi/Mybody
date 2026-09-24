/* =============================================================================
 * theme_test.dart — 글자 색이 비어 있는 스타일이 없는가
 *
 * `Typography.englishLike2021` 을 바탕으로 깔았을 때 `titleSmall`·`label*` 의
 * 색이 비어(inherit: false) 흰 글자로 나갔습니다 — 밝은 배경에서 친구 화면
 * 제목과 강도 카드 제목이 안 보였습니다. 스타일마다 색이 있는지 봅니다.
 * ========================================================================== */
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mybody/src/theme.dart';

/// WCAG 대비 — (밝은 쪽 + 0.05) / (어두운 쪽 + 0.05).
double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  test('강조색은 바탕 위에서 작은 글자로도 읽힌다 — 다크 4.5:1 이상, 라이트도', () {
    /* 다크의 #4F46E5 는 #171A20 위에서 2.8:1 이었습니다 — '4/3' · 링크 · TextButton 이 흐렸습니다. */
    final dark = mbDark().colorScheme, light = mbLight().colorScheme;
    expect(_contrast(dark.primary, dark.surface), greaterThanOrEqualTo(4.5));
    expect(_contrast(light.primary, light.surface), greaterThanOrEqualTo(4.5));
    /* 단추(흰 글자) 위에서는 큰 글자 기준 3:1 — 웹의 다크 토큰과 같은 조합입니다. */
    expect(_contrast(dark.onPrimary, dark.primary), greaterThanOrEqualTo(3.0));
  });

  for (final (name, theme) in [('밝음', mbLight()), ('어둠', mbDark())]) {
    test('$name 테마 — 모든 글자 스타일에 색이 있고 이어받는다', () {
      final tt = theme.textTheme;
      final styles = <String, TextStyle?>{
        'displayLarge': tt.displayLarge, 'headlineLarge': tt.headlineLarge,
        'headlineMedium': tt.headlineMedium, 'titleLarge': tt.titleLarge,
        'titleMedium': tt.titleMedium, 'titleSmall': tt.titleSmall,
        'bodyLarge': tt.bodyLarge, 'bodyMedium': tt.bodyMedium, 'bodySmall': tt.bodySmall,
        'labelLarge': tt.labelLarge, 'labelMedium': tt.labelMedium, 'labelSmall': tt.labelSmall,
      };
      styles.forEach((k, s) {
        expect(s, isNotNull, reason: '$k 가 없습니다');
        expect(s!.inherit, isTrue, reason: '$k 가 색을 이어받지 않습니다 — 흰 글자가 됩니다');
        expect(s.color, isNotNull, reason: '$k 에 색이 없습니다');
        expect(s.fontFamily, 'Pretendard', reason: '$k 글꼴');
      });
    });
  }
}
