/* =============================================================================
 * ocr_merge_test.dart — 판독이 읽어 준 나머지 칸이 검수로 넘어가는가
 *
 * 세 칸만 넘기면 검수 화면이 나머지를 계산해 채우고, 검산은 계산값끼리
 * 대조해서 언제나 통과합니다. 결과지가 준 값이 그대로 실려야 합니다.
 * ========================================================================== */
import 'package:flutter_test/flutter_test.dart';
import 'package:mybody/src/screens/upload.dart';

void main() {
  test('나머지 칸은 싣고, 사용자 값은 안 건드리고, 모르는 칸은 버린다', () {
    final out = mergeOcrExtras(
      {'id': 'x', 'weightKg': 86.7, 'smmKg': 38.0, 'bfmKg': 20.0},
      {
        'weightKg': 90, // 사용자가 고친 값이 이깁니다
        'pbfPct': 23.1, 'bmi': 24.8, 'bmrKcal': 1810, 'tbwL': 48.2,
        'measuredAt': '2026-03-01T09:30:00', // 숫자 칸이 아닙니다
        'junk': 1, 'inbodyScore': '82', // 모르는 칸 · 숫자가 아닌 값
      },
    );
    expect(out['weightKg'], 86.7);
    expect(out['pbfPct'], 23.1);
    expect(out['bmi'], 24.8);
    expect(out['bmrKcal'], 1810);
    expect(out['tbwL'], 48.2);
    expect(out.containsKey('measuredAt'), isFalse);
    expect(out.containsKey('junk'), isFalse);
    expect(out.containsKey('inbodyScore'), isFalse);
    expect(out['source'], 'ocr');
  });

  test('판독이 없으면 초안 그대로', () {
    final d = {'weightKg': 1.0};
    expect(identical(mergeOcrExtras(d, null), d), isTrue);
  });
}
