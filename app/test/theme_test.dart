/* =============================================================================
 * theme_test.dart — 글자 색이 비어 있는 스타일이 없는가
 *
 * `Typography.englishLike2021` 을 바탕으로 깔았을 때 `titleSmall`·`label*` 의
 * 색이 비어(inherit: false) 흰 글자로 나갔습니다 — 밝은 배경에서 친구 화면
 * 제목과 강도 카드 제목이 안 보였습니다. 스타일마다 색이 있는지 봅니다.
 * ========================================================================== */
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mybody/src/theme.dart';

void main() {
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
