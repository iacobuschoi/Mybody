/* =============================================================================
 * charts_test.dart — 범례가 선 모양을 따라가는가
 *
 * 추이 탭의 「체크인 체중」 은 「체중」 과 같은 색의 점선인데, 범례는 둘 다
 * 같은 실선이라 구분이 안 됐습니다(노트북 에뮬레이터에서 확인).
 * ========================================================================== */
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mybody/src/ui/charts.dart';

void main() {
  Widget host(List<Series> series) => MaterialApp(
        home: Scaffold(body: LineChart(series: series)),
      );

  testWidgets('점선으로 그리는 선은 범례도 점선', (tester) async {
    await tester.pumpWidget(host([
      Series(label: '체중', color: Colors.grey, points: [Pt(1, 80), Pt(2, 79)]),
      Series(label: '체크인 체중', color: Colors.grey, dashed: true, points: [Pt(2, 79.5)]),
    ]));
    expect(find.text('체중'), findsOneWidget);
    expect(find.text('체크인 체중'), findsOneWidget);
    expect(find.byKey(const ValueKey('legend-dashed')), findsOneWidget);
  });

  testWidgets('점선이 없으면 점선 범례도 없다', (tester) async {
    await tester.pumpWidget(host([
      Series(label: '체중', color: Colors.grey, points: [Pt(1, 80), Pt(2, 79)]),
    ]));
    expect(find.byKey(const ValueKey('legend-dashed')), findsNothing);
  });
}
