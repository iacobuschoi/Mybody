/* =============================================================================
 * edge.dart — 화면 아래 시스템 막대(뒤로·홈 버튼) 밑으로 내용이 들어가지 않게
 *
 * 안드로이드 15부터 앱은 화면 끝까지 그립니다(edge-to-edge). 그러면 밀어
 * 올린 화면(목표 · 강도 · 검수 …)의 맨 아래 버튼이 시스템 막대 **뒤에**
 * 깔립니다 — 끝까지 내려도 반쯤 가려져서 못 누릅니다. 실제 폰에서 그렇게
 * 나왔습니다. 탭 화면은 셸이 SafeArea 로 감싸서 멀쩡했고, 밀어 올린
 * 화면들이 문제였습니다.
 *
 * 화면마다 SafeArea 를 넣는 대신 MaterialApp 의 builder 에서 한 번에 —
 * 빠뜨릴 화면이 없습니다. 위쪽은 AppBar 가 알아서 하니 아래만.
 * ========================================================================== */
import 'package:flutter/material.dart';

Widget edgeSafe(BuildContext context, Widget? child) => ColoredBox(
      /* 막대 뒤 띠는 화면 바탕색으로 — 안 칠하면 창 바탕(흰색)이 비쳐서
         어두운 테마에서 흰 줄이 생깁니다. */
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(top: false, child: child ?? const SizedBox.shrink()),
    );
