/* =============================================================================
 * edge_test.dart — 맨 아래 버튼이 시스템 막대 뒤로 안 들어가는가
 *
 * 실제 폰에서 목표 화면의 「기간 계산하기」가 뒤로·홈 버튼 막대에 반쯤
 * 가려져 못 눌렀습니다. 아래 여백을 48px 로 두고, 밀어 올린 화면의 맨
 * 아래 버튼이 그 위에 있는지 봅니다.
 * ========================================================================== */
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mybody/src/ui/edge.dart';

void main() {
  testWidgets('밀어 올린 화면의 맨 아래 버튼이 시스템 막대 위에 있다', (t) async {
    await t.pumpWidget(MediaQuery(
      data: const MediaQueryData(size: Size(400, 800), padding: EdgeInsets.only(bottom: 48)),
      child: MaterialApp(
        builder: edgeSafe,
        home: Scaffold(
          body: ListView(padding: const EdgeInsets.all(16), children: [
            const SizedBox(height: 600),
            FilledButton(onPressed: () {}, child: const Text('기간 계산하기')),
          ]),
        ),
      ),
    ));
    await t.pump();
    await t.scrollUntilVisible(find.text('기간 계산하기'), 300);
    await t.pumpAndSettle();
    final bottom = t.getBottomLeft(find.byType(FilledButton)).dy;
    expect(bottom, lessThanOrEqualTo(800 - 48), reason: '버튼이 막대(아래 48px) 뒤로 들어가면 못 누릅니다');
  });
}
