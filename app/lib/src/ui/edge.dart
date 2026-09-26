/* =============================================================================
 * edge.dart — 모든 화면에 한 번에 거는 두 가지: 시스템 막대 · 키보드 닫기
 *
 * 1. 화면 아래 시스템 막대(뒤로·홈 버튼) 밑으로 내용이 들어가지 않게.
 *    안드로이드 15부터 앱은 화면 끝까지 그립니다(edge-to-edge). 그러면 밀어
 *    올린 화면(목표 · 강도 · 검수 …)의 맨 아래 버튼이 시스템 막대 **뒤에**
 *    깔립니다 — 끝까지 내려도 반쯤 가려져서 못 누릅니다. 실제 폰에서 그렇게
 *    나왔습니다. 탭 화면은 셸이 SafeArea 로 감싸서 멀쩡했고, 밀어 올린
 *    화면들이 문제였습니다. 위쪽은 AppBar 가 알아서 하니 아래만.
 *
 * 2. 키보드가 떠 있을 때 입력칸 밖을 탭하면 키보드가 내려가게.
 *    아이폰의 숫자 패드(키 · 나이 · 체중 …)에는 완료 키가 없습니다. 바깥 탭으로도
 *    안 내려가면 키보드를 닫을 길이 아예 없어서, 첫 설정에서 키·나이를 넣고 나면
 *    「다음」 에 영영 못 닿았습니다(안드로이드는 Done 키가 있어 드러나지 않았습니다).
 *
 * 화면마다 넣는 대신 MaterialApp 의 builder 에서 한 번에 — 빠뜨릴 화면이 없습니다.
 * Navigator 를 감싸므로 밀어 올린 화면 · 시트 · 다이얼로그(Overlay 도 Navigator
 * 안)에 다 걸립니다.
 * ========================================================================== */
import 'package:flutter/material.dart';

Widget edgeSafe(BuildContext context, Widget? child) => GestureDetector(
      /* 버튼 · 입력칸 · 목록 행 · 칩은 자기 탭 인식기가 더 안쪽이라 아레나에서
         먼저 이기고, 여기 onTap 은 빈 곳 · 글자 · 카드 여백을 탭했을 때만 옵니다.
         스크롤은 끌기(드래그)라 여기 안 오니, 끌어서 닫기는 목록마다
         keyboardDismissBehavior 로 따로 겁니다. */
      behavior: HitTestBehavior.translucent,
      onTap: dismissKeyboard,
      /* 시맨틱 트리에는 넣지 않습니다 — 안 그러면 화면 전체 크기의 이름 없는
         「두 번 탭하여 활성화」 요소가 하나 더 생겨 TalkBack · VoiceOver 가 모든
         화면에서 그것을 먼저 짚습니다. 키보드 닫기는 손가락용 편의라 스크린리더에
         알릴 것이 아닙니다. */
      excludeFromSemantics: true,
      child: ColoredBox(
        /* 막대 뒤 띠는 화면 바탕색으로 — 안 칠하면 창 바탕(흰색)이 비쳐서
           어두운 테마에서 흰 줄이 생깁니다. */
        color: Theme.of(context).scaffoldBackgroundColor,
        child: SafeArea(top: false, child: child ?? const SizedBox.shrink()),
      ),
    );

/// 지금 포커스를 가진 입력칸의 포커스를 풀어 키보드를 내립니다.
/// 아무 칸도 포커스가 없을 때(포커스가 화면의 스코프에 있을 때)는 건드리지
/// 않습니다 — 스코프를 풀면 포커스가 바깥 스코프로 옮겨 가기만 하고 얻는 게 없습니다.
void dismissKeyboard() {
  final f = FocusManager.instance.primaryFocus;
  if (f == null || f is FocusScopeNode) return;
  f.unfocus();
}
