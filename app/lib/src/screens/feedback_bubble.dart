/* =============================================================================
 * feedback_bubble.dart — 화면 가장자리에 늘 떠 있는 「의견 보내기」 말풍선
 *
 * 왜 있나
 *   주인의 말: "의견보내기는 설정 드가서 하는게 아니라 앱 어딘가에 상시 떠있는 버튼으로".
 *   앱바의 말풍선은 탭 화면에만 있었고, 밀어 올린 화면(목표 · 검수 · 운동 기록 …)과
 *   로그인 · 첫 설정 화면에는 없었습니다. 이상한 것은 대개 그런 화면에서 보입니다 —
 *   거기서 설정까지 찾아가면 이상했던 화면은 이미 사라져 있습니다. 그래서 앱 맨 위에
 *   말풍선 하나를 띄워 **어느 화면에서든 한 번 누르면** 그 화면이 붙은 시트가 뜹니다.
 *
 * 옮기기 · 치우기 — 주인의 말(피드백 42):
 *   "말풍선은 꾹 누르면 드래그로 위치 바꿀 수 있게해 / 화면 가장자리 아무데로나 옮겨지게하고 /
 *    디폴트 위치를 인바디 사진올리기 버튼 바로위로ㄱㄱ / 꾹 눌렀을때 화면 하단 중앙에 x아이콘
 *    만들어서 글로 갖다대면 없어지게 하고 / 테스트기간에는 X표시에 갖다대면 '테스트 기간에는
 *    없앨수없어요'같은 메세지 띄우고 / 이후에는 '다시 키려면 설정탭에서 해라'같은 메세지 띄워줘"
 *   · **꾹 눌러야 들립니다.** 그냥 끌면 아무 일도 없습니다 — 말풍선은 목록 위에 떠 있어서,
 *     스크롤하려던 엄지가 말풍선에 걸릴 때마다 말풍선이 따라 움직이면 안 됩니다(예전엔
 *     그랬습니다). 들리면 살짝 커지고(1.15배) 폰이 한 번 떨립니다 — "잡았다" 는 신호.
 *   · 들린 동안만 화면 아래 가운데에 X(56px 동그라미, 아래 안전 영역 위)가 떠오릅니다.
 *     말풍선 가운데가 X 에서 64px 안으로 들어오면 X 가 커지고 붉어지며 한 번 더 떨립니다.
 *     거기서 놓으면
 *       - 비공개 시험 기간(GET /api/version 의 testing, update.dart)이면 「테스트 기간에는
 *         없앨 수 없어요」 와 함께 들기 전 자리로 돌아갑니다. 시험판의 의견이 시험의 전부입니다.
 *       - 시험이 끝났으면 사라지고(feedbackBubbleOn = 꺼짐) 「다시 켜려면 설정 → 도움말에서
 *         켜세요」 — 사라진 것을 되찾는 길을 그 자리에서 알려 줍니다.
 *   · 다른 데서 놓으면 **네 가장자리(왼 · 오른 · 위 · 아래) 중 가장 가까운 곳**에 붙습니다.
 *     그 가장자리를 따라서는 놓은 자리 그대로 — "아무데로나". 가장자리는 안전 영역(상태
 *     막대 · 아래 제스처 띠 · 노치) 안쪽 16px 입니다. 앱바 · 탭바 위에도 붙을 수 있습니다 —
 *     그 자리를 고른 것은 쓰는 사람입니다. 다만 아래 가장자리 가운데(X 가 뜨는 곳)에는
 *     비켜서 붙습니다: 거기 붙어 있으면 다음에 들 때마다 X 위에서 시작하고, 조금만 옮겨
 *     놓아도 치워집니다. 비키기는 그릴 때마다 다시 셉니다 — 가로 화면에서 비켜 둔 비율이
 *     세로로 돌리면 X 가까이 올 수 있습니다(안드로이드는 돌아갑니다).
 *   · 옮긴 자리는 {가장자리, 그 가장자리를 따라 간 비율 t} 로 이 기기에 둡니다
 *     (SharedPreferences). 픽셀이 아니라 비율이라 화면을 돌려도 같은 가장자리 · 같은 느낌의
 *     자리입니다. 손 크기 · 화면은 폰마다 다르니 동기화하는 settings 에 넣지 않습니다.
 *     옛 판의 {쪽, 높이 비율}은 처음 읽을 때 그 화면에서 **같은 높이**가 되게 옮겨 적습니다.
 *
 * 처음 자리 — 오른쪽 가장자리, 앱바 밑 ~ 탭바 위의 한가운데
 *   오른쪽 가장자리(「인바디」 단추와 같은 16px 안쪽 — 오른쪽 끝이 단추와 한 세로줄), 높이는
 *   앱바 아래 끝(위 안전 영역 + 56)과 탭바 위 끝(아래 안전 영역 위 80) 사이의 **가운데**.
 *   다만 옛 자리(「인바디」 단추 위 끝에서 12px 위)보다 아래로는 안 내려갑니다 — 세로 화면에서는
 *   가운데가 늘 그보다 위라 걸리지 않고, 낮은 가로 창(안전 영역을 뺀 높이 344 밑)에서 가운데가
 *   단추를 덮지 않게 막습니다. 그러고 가장자리 네모([feedbackBubbleTrack]) 안으로 당깁니다.
 *   예전엔 「인바디」 단추 바로 위(피드백 42 의 "디폴트 위치를 인바디 사진올리기 버튼 바로위로")
 *   였는데, 시험판 의견 — 첫 설정 3/3 「시작하기 전에」 에서 "채팅이랑 체크박스가 같은위치에
 *   있어 누르기 불편합니다" — 과 주인의 말("의견박스 디폴트위치 수정하고")로 옮겼습니다.
 *   맨 아래에 큰 단추를 박아 둔 화면(첫 설정의 「다음」 · 「시작하기」)이나 목록 끝에 저장 단추가
 *   오는 화면(목표 · 검수)을 끝까지 내리면(또는 다 들어가면) 마지막 줄들이 **옛 자리** 에 섭니다.
 *   Material 은 줄 끝의 체크박스 · 스위치(CheckboxListTile · SwitchListTile 의 기본 자리)와
 *   친구 목록의 종 · 꺾쇠를 오른쪽 끝에 두어서 말풍선이 그것을 덮었습니다(첫 설정 3/3 은
 *   360×640 · 390×844 둘 다 — feedback_bubble_test 가 대조로 봅니다). 굴러가는 목록의 맨 끝
 *   줄(고정 단추 바로 위)과 맨 위 줄은 더 굴려도 말풍선 밑에서 못 빠져나오지만, **가운데 줄은
 *   굴리면 언제든 비켜 납니다.** 굴릴 것이 없는 짧은 화면은 예외입니다 — 로그인 화면의
 *   「로그인」(360×800 · 390×844 등 요즘 폰 대부분)과 첫 설정 1/3 의 「나이」 칸(「세」 글자)처럼
 *   가로로 꽉 찬 것은 오른쪽 끝이 말풍선 밑에 듭니다(옛 자리에서는 「로그인 없이 쓰기」 였습니다).
 *   둘 다 넓어서 가운데 · 글자 · 입력 자리는 비어 있습니다(feedback_bubble_test 가 봅니다). 화면마다
 *   높이를 달리하지 않고 하나의 규칙으로 두되, 누를 곳이 끝에만 있는 좁은 것(체크박스 · 스위치)을
 *   비키는 쪽을 골랐습니다. 오른쪽은
 *   그대로 — 주인이 전에 고른 엄지 닿는 쪽이고, 왼쪽에서 시작하는 스낵바 글자를 덮지 않습니다.
 *   세로 화면에서는 위의 띠(MaterialBanner, shell.dart — 앱바 바로 밑)보다도 아래라 「로그인」 ·
 *   「요청」 을 덮지 않습니다(360×640 · 글자 1.3배까지, invite_deferred_test). 가로 창에서는
 *   앱바와 탭바 사이가 200px 안팎이라 띠가 말풍선 높이까지 내려올 수 있습니다 — 띠는 화면을 밀지
 *   않고 얹히고 저절로 걷혀서 그대로 둡니다. 옮긴 적 없는 사람은 적힌 자리가 없어(처음 자리는
 *   적지 않음) 새 자리로 가고, 옮긴 사람은 옮긴 자리 그대로입니다.
 *
 * 한 번 알림 — 「꾹 눌러 옮길 수 있어요」
 *   주인의 말: "의견박스 꾹누르면 움직일수있는거 알려줘". 말풍선 옆(화면 가운데 쪽)에 작은
 *   알약 한 줄 — **이 기기에서 한 번**(SharedPreferences [kFeedbackBubbleHintKey]).
 *   · 이번 실행에서 말풍선이 처음 보이고 1.2초 뒤, 맨 위가 **화면**(PageRoute)이고 앱이 앞에
 *     있을 때(resumed)만 — 다이얼로그 · 시트(테스터 인사 등)가 위에 있거나 시스템 창(「알림을
 *     허용할까요?」)이 덮었거나 앱이 뒤로 갔으면 1초마다 다시 봅니다(말풍선이 보이는 동안).
 *     알림은 그 뒤의 화면이 아니라 말풍선에 붙은 말인데, 다이얼로그를 읽는 눈을 뺏으면 안 되고,
 *     아무도 못 보는 때 떠서 본 것으로 적히면 안 됩니다.
 *   · **뜨는 순간** 본 것으로 적습니다 — 떠 있는 동안 앱이 꺼져도 두 번 뜨지 않습니다.
 *   · 4초 머물고 흐려지며 걷힙니다. 말풍선을 들거나(꾹 누르기 시작) · 말풍선이 숨거나(키보드 ·
 *     의견 시트 · 치우기) 하면 곧바로 걷히고, 다시 뜨지 않습니다.
 *   · 꾹 눌러 옮겨 둔 자리가 있으면 이미 아는 사람이라 띄우지 않고 본 것으로 적습니다. 뜨기 전에
 *     스스로 꾹 눌러 든 사람도 그렇습니다. 옛 판(0.2.17 — 그냥 끌면 움직였음)의 자리에서 옮겨
 *     적는 사람에게는 띄웁니다 — 아는 것이 "끌기" 인데 이제 끌면 아무 일도 없습니다
 *     ([loadFeedbackBubbleMovedByLongPress]).
 *   · 반대색(inverseSurface) 알약 · bodySmall. 말풍선이 오른쪽 반이면 그 왼쪽에, 왼쪽 반이면
 *     오른쪽에 — 동그라미 끝에서 8px, 높이는 동그라미 가운데. 폭은 화면 가장자리(16px)까지
 *     남은 만큼만이라 글자가 커도 화면 밖으로 안 나갑니다.
 *   · 누름은 받지 않고(IgnorePointer) 스크린리더에도 알리지 않습니다 — X 처럼 손가락용 안내이고,
 *     말풍선과 같은 층이라 캡처 경계 밖입니다(찍히지 않음).
 *
 * 크기 · 색
 *   동그라미 40px(누르는 칸은 48px). 표면색을 조금 비치게(0.9) · 가는 테두리 · 옅은 그림자 —
 *   화면 위에 "얹힌 것" 으로 읽히되 내용보다 튀지 않게. X 는 반대색(inverseSurface) 동그라미,
 *   닿으면 error 색. 색은 전부 테마에서라 어두운 테마에서도 같은 대비입니다.
 *
 * 찍히지 않게
 *   말풍선(과 X)은 캡처 경계([appCaptureBoundary]) **바깥**, 그 형제로 섭니다([appFrame]).
 *   경계 안에 있으면 보낸 화면마다 말풍선이 찍혀 그 밑의 내용을 가립니다.
 *
 * 숨는 때(짧게 흐려지며 — 끝이 있는 애니메이션)
 *   · 키보드가 올라와 있을 때 — 입력칸 오른쪽 끝을 덮고, 그때는 쓰는 중입니다.
 *   · 의견 시트가 뜨는 중(찍는 중 포함)이거나 떠 있을 때 — 두 번 누를 일이 없습니다.
 *   · X 로 치웠거나 설정에서 껐을 때([feedbackBubbleOn]) — **시험 기간이 아닐 때만**. 시험
 *     기간에는 옛 판에서 꺼 둔 기기에도 뜹니다([feedbackBubbleLocked]). 시험이 끝났는지
 *     아직 모르면(확인기가 이 기기의 지난 답을 읽기 전) 꺼 둔 기기에서는 잠깐 기다립니다 —
 *     켤 때마다 한 번씩 번쩍이면 안 됩니다.
 *   · 앱이 켜지는 중(Scope 가 아직 없을 때) — 보낼 곳(Api)이 없어 눌러도 못 보냅니다.
 *
 * 누르면 — Navigator 위에서 Navigator 에 닿기
 *   말풍선은 Navigator **위**(MaterialApp.builder)에 있어서 자기 context 로는 시트를
 *   띄울 수 없습니다(Navigator · Overlay 가 아래에 있음). 그래서 [FeedbackRoutes] 가
 *   Navigator 를 지켜보다가(navigatorObservers) 지금 맨 위의 **화면**(PageRoute —
 *   시트 · 다이얼로그는 건너뜀)의 context 를 건넵니다. 의견 시트는 그 context 로
 *   앱바 제목(홈 · 식단 · 설정 …)을 읽어 "어느 화면" 칸을 채웁니다 — 셸의 앱바 단추가
 *   하던 그대로입니다. 안내 한 줄(스낵바)은 Navigator 위에서도 닿습니다 — MaterialApp 의
 *   ScaffoldMessenger 가 builder 바깥에 있습니다.
 *   navigatorKey(GlobalKey) 대신 이것을 쓰는 까닭: 앱은 켜는 동안 MaterialApp 을 바로
 *   내놓고, 준비되면 그 위에 Scope 를 씌웁니다(main.dart). GlobalKey 를 단 Navigator 는
 *   그때 **옮겨 붙어** 켜는 중의 화면(도는 원)을 경로로 쥔 채 남습니다 — 셸이 영영 안
 *   뜹니다. 지켜보는 쪽은 옛 Navigator 에서 떨어지고 새 Navigator 에 붙기만 합니다.
 *   · 막 뜨는 중인 화면(인사 시트가 올라오는 첫 프레임 등)이면 다 뜰 때까지 잠깐
 *     기다렸다 찍습니다([FeedbackRoutes.settled]) — 반쯤 올라온 시트가 찍히면 이상합니다.
 *
 * 예전의 「길게 눌러 → 의견 버튼 숨기기」 메뉴는 뺐습니다 — 꾹 누르기는 이제 옮기기입니다.
 *
 * 스크린리더
 *   「의견 보내기」 단추 하나(누르기만). 옮기기 · X 는 손가락용이라 알리지 않습니다 —
 *   끄는 길은 설정의 스위치입니다. 숨어 있을 때는 트리에서 빠집니다 — 안 보이는 단추를
 *   짚으면 안 됩니다.
 * ========================================================================== */
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:lucide_icons/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../scope.dart';
import '../ui/edge.dart' show edgeSafe;
import '../ui/widgets.dart' show toast;
import '../update.dart' show UpdateCheck;
import 'feedback.dart';

/* --- 크기 · 자리(머리 주석) ------------------------------------------------------ */

const double _dot = 40; // 보이는 동그라미
const double _hit = 48; // 누르는 칸
/* 가장자리에서 동그라미까지 — 「인바디」 단추의 여백(kFloatingActionButtonMargin)과 같게.
   그래야 오른쪽 가장자리의 말풍선이 단추와 한 세로줄(오른쪽 끝 나란히)에 섭니다. */
const double _inset = 16;
/* 처음 자리의 높이를 재는 두 끝 — 앱바(kToolbarHeight, 위 안전 영역 밑)와 탭바(Material 3
   NavigationBar, 아래 안전 영역 위). 탭바 없는 밀어 올린 화면에서도 같은 자리 — 거기 맨 아래
   고정 단추(56 ~ 80)도 이 높이 안입니다. */
const double _navBar = 80;
/* 처음 자리의 아래 한계 — 홈 「인바디」 단추(확장 FAB): 탭바 위 여백 16 · 높이 56, 그 위 끝에서
   동그라미 아래 끝까지 틈 12(옛 처음 자리 그대로). 세로 화면에서는 가운데가 늘 이보다 위라
   걸리지 않고, 낮은 가로 창(위아래 안전 영역을 뺀 높이 344 밑 — 안드로이드는 돌아가고 창 나누기도
   됩니다)에서만 가운데가 단추 위로 내려앉지 않게 막습니다. */
const double _fabMargin = 16;
const double _fab = 56;
const double _fabGap = 12;
const double _bin = 56; // X 동그라미
const double _binLift = 24; // 아래 안전 영역에서 X 아래 끝까지
const double _binReach = 64; // 말풍선 가운데가 이 안이면 "X 위"
/* 아래 가장자리에 붙을 때 X 가운데에서 가로로 이만큼은 비킵니다 — X 위(64)도, X 와 겹치는
   자리도 아니게. */
const double _binClear = _binReach + 8;
const double _hintGap = 8; // 동그라미 끝과 알림 알약 사이

/// 말풍선이 붙는 가장자리.
enum FeedbackEdge { left, right, top, bottom }

/// 옮겨 둔 자리 — 가장자리와 그 가장자리를 따라 간 비율(0 = 위 · 왼쪽 끝, 1 = 아래 · 오른쪽 끝).
@immutable
class FeedbackBubblePos {
  const FeedbackBubblePos(this.edge, this.t);
  final FeedbackEdge edge;
  final double t;

  Map<String, Object> toJson() => {'edge': edge.name, 't': t};

  /// 모양이 틀리면 null — 처음 자리로 갑니다(던지지 않습니다).
  static FeedbackBubblePos? fromJson(Object? j) {
    if (j is! Map) return null;
    final e = FeedbackEdge.values.where((v) => v.name == j['edge']).firstOrNull;
    final t = j['t'];
    if (e == null || t is! num || !t.isFinite) return null;
    return FeedbackBubblePos(e, t.clamp(0.0, 1.0).toDouble());
  }

  @override
  bool operator ==(Object other) => other is FeedbackBubblePos && other.edge == edge && other.t == t;

  @override
  int get hashCode => Object.hash(edge, t);

  @override
  String toString() => 'FeedbackBubblePos(${edge.name}, $t)';
}

/* --- 자리 계산 — 모두 화면(창) 좌표, 기준은 동그라미의 가운데 ------------------------- */

/// 말풍선 가운데가 설 수 있는 네모 — 안전 영역 안쪽으로 가장자리에서 16px(동그라미 끝 기준).
/// 네 변이 곧 네 가장자리입니다. 화면이 아주 작아 뒤집히면 그 가운데 한 줄.
Rect feedbackBubbleTrack(Size size, EdgeInsets pad) {
  const m = _inset + _dot / 2;
  var l = pad.left + m, r = size.width - pad.right - m;
  var t = pad.top + m, b = size.height - pad.bottom - m;
  if (l > r) l = r = (l + r) / 2;
  if (t > b) t = b = (t + b) / 2;
  return Rect.fromLTRB(l, t, r, b);
}

/// 처음 자리 — 오른쪽 가장자리, 앱바 아래 끝과 탭바 위 끝의 한가운데(머리 주석).
/// 가운데 = ((위 안전 영역 + 56) + (높이 − 아래 안전 영역 − 80)) / 2. 다만 「인바디」 단추 위
/// 12px(탭바 위 16 + 56 + 12 + 반지름 20)보다 아래로는 안 내려가고 — 낮은 가로 창 — 가장자리
/// 네모 안으로 당깁니다.
Offset feedbackBubbleHome(Size size, EdgeInsets pad) {
  final r = feedbackBubbleTrack(size, pad);
  final top = pad.top + kToolbarHeight, bottom = size.height - pad.bottom - _navBar;
  final aboveFab = bottom - _fabMargin - _fab - _fabGap - _dot / 2;
  final y = math.min((top + bottom) / 2, aboveFab);
  return Offset(r.right, y.clamp(r.top, r.bottom).toDouble());
}

/// X 의 가운데 — 아래 가운데, 아래 안전 영역 위.
Offset feedbackBubbleBinCenter(Size size, EdgeInsets pad) =>
    Offset(size.width / 2, size.height - pad.bottom - _binLift - _bin / 2);

/// 말풍선 가운데 [c] 가 X 위인가(64px 안).
bool feedbackBubbleOverBin(Offset c, Size size, EdgeInsets pad) =>
    (c - feedbackBubbleBinCenter(size, pad)).distance <= _binReach;

/* 아래 가장자리의 가로 자리 [x] 를 X 자리에서 비킵니다 — X 가운데에서 [_binClear] 안이면
   놓은 쪽(가운데와 같으면 오른쪽)으로 그만큼 밀고, 가장자리 네모 [r] 안으로 당깁니다. */
double _besideBin(double x, Size size, EdgeInsets pad, Rect r) {
  final mid = feedbackBubbleBinCenter(size, pad).dx;
  if ((x - mid).abs() >= _binClear) return x;
  return (mid + (x >= mid ? _binClear : -_binClear)).clamp(r.left, r.right).toDouble();
}

/// 붙어 있는 자리. [p] 가 없으면 처음 자리.
///
/// 아래 가장자리면 그릴 때마다 X 자리를 비킵니다([_besideBin]) — 비율은 화면마다 다른 픽셀이
/// 되어서, 가로 화면에서 비켜 둔 자리가 세로로 돌리면 X 가운데 가까이 올 수 있습니다.
Offset feedbackBubbleCenter(FeedbackBubblePos? p, Size size, EdgeInsets pad) {
  if (p == null) return feedbackBubbleHome(size, pad);
  final r = feedbackBubbleTrack(size, pad);
  double along(double lo, double hi) => lo + (hi - lo) * p.t;
  return switch (p.edge) {
    FeedbackEdge.left => Offset(r.left, along(r.top, r.bottom)),
    FeedbackEdge.right => Offset(r.right, along(r.top, r.bottom)),
    FeedbackEdge.top => Offset(along(r.left, r.right), r.top),
    FeedbackEdge.bottom => Offset(_besideBin(along(r.left, r.right), size, pad, r), r.bottom),
  };
}

double _frac(double v, double lo, double hi) =>
    hi - lo <= 0 ? 0.5 : ((v - lo) / (hi - lo)).clamp(0.0, 1.0).toDouble();

/// 놓은 자리 [c] → 가장 가까운 가장자리, 그 가장자리를 따라서는 놓은 그대로.
/// 거리가 같으면 옆(왼 · 오른)이 먼저입니다 — 세로 화면에서 엄지가 닿는 쪽.
FeedbackBubblePos feedbackBubbleSnap(Offset c, Size size, EdgeInsets pad) {
  final r = feedbackBubbleTrack(size, pad);
  final x = c.dx.clamp(r.left, r.right).toDouble(), y = c.dy.clamp(r.top, r.bottom).toDouble();
  var edge = FeedbackEdge.left;
  var best = x - r.left;
  for (final (e, d) in [
    (FeedbackEdge.right, r.right - x),
    (FeedbackEdge.top, y - r.top),
    (FeedbackEdge.bottom, r.bottom - y),
  ]) {
    if (d < best) {
      edge = e;
      best = d;
    }
  }
  switch (edge) {
    case FeedbackEdge.left:
    case FeedbackEdge.right:
      return FeedbackBubblePos(edge, _frac(y, r.top, r.bottom));
    case FeedbackEdge.top:
      return FeedbackBubblePos(edge, _frac(x, r.left, r.right));
    case FeedbackEdge.bottom:
      /* X 가 뜨는 자리는 비킵니다(머리 주석) — 놓은 쪽으로. 비킨 자리를 적어 둡니다. */
      return FeedbackBubblePos(edge, _frac(_besideBin(x, size, pad, r), r.left, r.right));
  }
}

/// 옛 판의 자리({쪽, 높이 비율 y}) → 새 자리. 그 화면에서 **같은 높이**가 되게 옛 규칙
/// 그대로 셉니다: 가운데 = 위 안전 영역 + y × (위아래 안전 영역을 뺀 높이), 앱바 밑 ~
/// 탭바 · 「인바디」 단추 위 사이로 당김. 화면 크기를 아직 모르면 y 를 그대로 t 로(비슷한 자리).
FeedbackBubblePos feedbackBubbleFromLegacy(
    {required bool right, required double y, required Size size, required EdgeInsets pad}) {
  final edge = right ? FeedbackEdge.right : FeedbackEdge.left;
  final yy = y.isFinite ? y.clamp(0.0, 1.0).toDouble() : 0.58;
  if (size.isEmpty) return FeedbackBubblePos(edge, yy);
  final usable = math.max(1.0, size.height - pad.top - pad.bottom);
  var lo = pad.top + kToolbarHeight + 8 + _hit / 2;
  var hi = size.height - pad.bottom - (80 + 16 + 56 + 8) - _hit / 2;
  if (lo > hi) lo = hi = (lo + hi) / 2;
  final cy = (pad.top + yy * usable).clamp(lo, hi).toDouble();
  final r = feedbackBubbleTrack(size, pad);
  return FeedbackBubblePos(edge, _frac(cy, r.top, r.bottom));
}

/* --- 자리 저장 ---------------------------------------------------------------- */

/// 옮겨 둔 자리 — {"edge": "right", "t": 0.62}. 없으면 처음 자리.
const String kFeedbackBubblePosKey = 'mybody.feedbackBubble.pos.v2';

/// 옛 판의 붙은 쪽('left' · 'right'). 읽으면 [kFeedbackBubblePosKey] 로 옮기고 지웁니다.
const String kFeedbackBubbleSideKey = 'mybody.feedbackBubble.side.v1';

/// 옛 판의 가운데 높이 비율. 읽으면 옮기고 지웁니다.
const String kFeedbackBubbleYKey = 'mybody.feedbackBubble.y.v1';

/// 저장된 자리. 없거나 못 읽으면 null(처음 자리). 옛 모양만 있으면 이 화면([size] ·
/// [padding] = viewPadding)에서 같은 높이가 되게 옮겨 적고 옛 칸을 지웁니다.
Future<FeedbackBubblePos?> loadFeedbackBubblePos(
    {Size size = Size.zero, EdgeInsets padding = EdgeInsets.zero}) async {
  try {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(kFeedbackBubblePosKey);
    if (raw != null) {
      Object? j;
      try {
        j = jsonDecode(raw);
      } catch (_) {}
      final p = FeedbackBubblePos.fromJson(j);
      if (p != null) return p;
    }
    final side = sp.get(kFeedbackBubbleSideKey), y = sp.get(kFeedbackBubbleYKey);
    if (side == null && y == null) return null;
    final p = feedbackBubbleFromLegacy(
        right: side != 'left', y: y is num ? y.toDouble() : 0.58, size: size, pad: padding);
    await sp.setString(kFeedbackBubblePosKey, jsonEncode(p.toJson()));
    await sp.remove(kFeedbackBubbleSideKey);
    await sp.remove(kFeedbackBubbleYKey);
    return p;
  } catch (_) {
    return null;
  }
}

Future<void> _savePos(FeedbackBubblePos p) async {
  try {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(kFeedbackBubblePosKey, jsonEncode(p.toJson()));
  } catch (_) {
    // 못 적어도 이번 실행 동안은 옮긴 자리 그대로입니다.
  }
}

/// 「꾹 눌러 옮길 수 있어요」 를 이 기기에서 이미 띄웠나(또는 알 사람인가) — true 면 다시 안 띄웁니다.
/// 자리처럼 이 기기에만 둡니다 — 기기마다 처음 한 번.
const String kFeedbackBubbleHintKey = 'mybody.feedbackBubble.hint.v1';

/// 꾹 눌러 옮긴 자리(새 칸 [kFeedbackBubblePosKey])가 **읽기 전부터** 있나 — 있으면 꾹 누르기를
/// 아는 사람입니다. [loadFeedbackBubblePos] 보다 먼저 부릅니다: 그것이 옛 칸({쪽, 높이})에서 방금
/// 옮겨 적은 자리는 세지 않습니다. 옛 칸은 그냥 끌면 움직이던 판(0.2.17)이 적었고 — 스크롤하던
/// 엄지에 끌려간 자리도 있습니다 — 그 사람들이 아는 "끌기" 는 이제 아무 일도 안 합니다. 알림이
/// 바로 그 사람들 몫입니다. 0.2.18 ~ 0.2.20 이 이미 새 칸으로 옮겨 적은 옛 자리는 가려낼 수
/// 없어 아는 사람으로 칩니다. 못 읽으면 없는 것으로(알림이 한 번 뜰 뿐).
Future<bool> loadFeedbackBubbleMovedByLongPress() async {
  try {
    final raw = (await SharedPreferences.getInstance()).getString(kFeedbackBubblePosKey);
    return raw != null && FeedbackBubblePos.fromJson(jsonDecode(raw)) != null;
  } catch (_) {
    return false;
  }
}

/// 알림을 이미 봤나. 못 읽으면 본 것으로 칩니다 — 매번 뜨는 것보다 한 번도 안 뜨는 쪽이 낫습니다.
Future<bool> loadFeedbackBubbleHintSeen() async {
  try {
    return (await SharedPreferences.getInstance()).getBool(kFeedbackBubbleHintKey) ?? false;
  } catch (_) {
    return true;
  }
}

Future<void> _markHintSeen() async {
  try {
    await (await SharedPreferences.getInstance()).setBool(kFeedbackBubbleHintKey, true);
  } catch (_) {
    // 못 적으면 다음 실행에 한 번 더 뜰 뿐입니다.
  }
}

/* --- Navigator 지켜보기 ---------------------------------------------------------- */

/// 앱의 Navigator 에 쌓인 경로를 지켜봅니다 — 말풍선이 "지금 맨 위 화면" 을 알려고.
/// main.dart 의 MaterialApp 에 `navigatorObservers: [feedbackRoutes]` 로 겁니다.
class FeedbackRoutes extends NavigatorObserver {
  final List<Route<dynamic>> _stack = [];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => _stack.add(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _stack.remove(route);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => _stack.remove(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final i = oldRoute == null ? -1 : _stack.indexOf(oldRoute);
    if (newRoute == null) {
      if (i >= 0) _stack.removeAt(i);
    } else if (i >= 0) {
      _stack[i] = newRoute;
    } else {
      _stack.add(newRoute);
    }
  }

  /* 위에서부터, 지금 이 Navigator 에 살아 있는 경로만. 앱이 켜지며 MaterialApp 이 새로
     서면 옛 Navigator 의 경로는 pop 알림 없이 버려집니다 — 그런 것(navigator 가 비었거나
     다른 것)은 여기서 걸러 내고 목록에서도 뺍니다. */
  Iterable<Route<dynamic>> get _live {
    final nav = navigator;
    _stack.removeWhere((r) => r.navigator == null);
    return _stack.reversed.where((r) => identical(r.navigator, nav) && r.isActive);
  }

  /// 맨 위 경로(시트 · 다이얼로그 포함).
  Route<dynamic>? get top => _live.firstOrNull;

  /// 맨 위 **화면**(PageRoute)의 안쪽 context — 시트 · 다이얼로그 · 메뉴는 건너뜁니다.
  /// 의견 시트가 이것으로 앱바 제목(화면 이름)을 읽고 시트를 띄웁니다. 화면이 없으면
  /// Navigator 자신(Navigator.of 가 그대로 받음) — 화면 이름만 빠집니다.
  BuildContext? get pageContext {
    for (final r in _live) {
      if (r is PageRoute) {
        final c = r.subtreeContext;
        if (c != null && c.mounted) return c;
      }
    }
    final nav = navigator;
    return nav != null && nav.mounted ? nav.context : null;
  }

  /// 맨 위 경로가 들어오는(또는 나가는) 중이면 끝날 때까지 — 한 번에 [max] 까지만 기다립니다.
  ///
  /// 기다리는 사이 **다른 경로가 새로 올라왔으면**(셸이 /me 를 기다렸다 띄운 테스터 인사 등)
  /// 그것도 다 뜰 때까지 다시 봅니다 — 처음 본 경로만 기다리면, 막 올라오기 시작한 인사
  /// 시트의 첫 프레임을 찍고 그 위에 의견 시트를 띄웁니다. 끝없이 이어지지 않게 세 번까지.
  /// 다 뜬 것을 보면 곧바로 의견 시트가 feedbackBusy 를 켜서, 그다음에 오는 인사는 기다립니다.
  Future<void> settled({Duration max = const Duration(milliseconds: 600)}) async {
    for (var round = 0; round < 3; round++) {
      final r = top;
      final a = r is TransitionRoute ? r.animation : null;
      if (a == null || !a.isAnimating) return;
      final done = Completer<void>();
      void check(AnimationStatus s) {
        if (!s.isAnimating && !done.isCompleted) done.complete();
      }
      a.addStatusListener(check);
      try {
        await done.future.timeout(max, onTimeout: () {});
      } finally {
        a.removeStatusListener(check);
      }
    }
  }
}

/// 앱에 하나 — main.dart 가 MaterialApp.navigatorObservers 에 겁니다.
final FeedbackRoutes feedbackRoutes = FeedbackRoutes();

/* --- 앱 맨 위 ---------------------------------------------------------------- */

/// main.dart 의 MaterialApp.builder 전부 — 바깥부터 말풍선 층 · 캡처 경계 · edgeSafe.
/// 말풍선은 캡처 경계의 **형제**라 찍히지 않고, 경계는 여전히 창 전체(막대 뒤 띠까지)를 찍습니다.
Widget appFrame(BuildContext context, Widget? child) =>
    FeedbackBubbleLayer(child: appCaptureBoundary(edgeSafe(context, child)));

/// [child](앱 전체) 위에 말풍선(과 들린 동안의 X)을 얹습니다. 말풍선 칸(48px) 밖의 누름은
/// 그대로 앱으로 갑니다 — X 는 누름을 받지 않습니다.
class FeedbackBubbleLayer extends StatelessWidget {
  const FeedbackBubbleLayer({super.key, required this.child, this.routes});
  final Widget child;

  /// 지켜보는 쪽 — 없으면 앱의 [feedbackRoutes].
  final FeedbackRoutes? routes;

  @override
  Widget build(BuildContext context) => Stack(
        fit: StackFit.expand,
        children: [child, _Bubble(routes: routes ?? feedbackRoutes)],
      );
}

/* 흐려지기 · 떠오르기 · 들리기 — 모두 끝이 있는 짧은 애니메이션. */
/// 말풍선을 들어 올리는 꾹 누르기 시간. 기본(0.5초)은 길다는 주인 말(피드백 46: "꾹누르기 시간을
/// 살짝만 줄여봐") — 0.35초. 더 줄이면 탭하려던 손가락이 들어 올리기로 잡힙니다.
const Duration kBubbleLongPress = Duration(milliseconds: 350);

const Duration _fade = Duration(milliseconds: 180);
const Duration _quick = Duration(milliseconds: 120);

/// 한 번 알림(머리 주석) — 말풍선이 보이고 이만큼 뒤에 뜹니다. 곧바로 뜨면 화면이 막 바뀌는
/// 중이라 눈이 거기 있고, 너무 늦으면 이미 다른 데를 누르고 있습니다.
const Duration kBubbleHintDelay = Duration(milliseconds: 1200);

/// 한 번 알림이 머무는 시간 — 짧은 한 줄을 읽기에 넉넉하되 화면을 오래 가리지 않게.
const Duration kBubbleHintStay = Duration(seconds: 4);

/// 맨 위가 다이얼로그 · 시트라 못 띄웠으면 이만큼 뒤에 다시 봅니다.
const Duration _hintRetry = Duration(seconds: 1);

/* 한 번 알림의 차례 — 없음(이미 봤거나 끝남, 트리에 없음) · 기다림(투명하게 트리에, 1.2초
   시계) · 떠 있음 · 걷히는 중(흐려짐이 끝나면 없음). */
enum _Hint { none, waiting, up, fading }

class _Bubble extends StatefulWidget {
  const _Bubble({required this.routes});
  final FeedbackRoutes routes;

  @override
  State<_Bubble> createState() => _BubbleState();
}

class _BubbleState extends State<_Bubble> with SingleTickerProviderStateMixin {
  /// 저장된 켜짐 · 자리를 읽었나. 읽기 전에는 안 보입니다 — 숨겨 둔 사람에게 켤 때마다
  /// 한 번씩 번쩍이면 안 됩니다.
  bool _ready = false;

  /// 붙어 있는 자리. null 이면 처음 자리(오른쪽 가장자리 가운데).
  FeedbackBubblePos? _pos;

  /// 들렸을 때의 가운데(화면 좌표) — 손가락이 움직인 만큼 여기서 옮깁니다. 놓으면 비웁니다.
  Offset? _liftedAt;

  /// 들린 채 따라오는 가운데. 놓으면 비웁니다.
  Offset? _drag;

  /// 지금 X 위인가 — X 가 커지고 붉어집니다. 들어설 때 한 번 떨립니다.
  bool _hot = false;

  /// 놓은 자리 → 갈 자리(붙을 가장자리 · 들기 전 자리 · X). 짧게(0.22초) 미끄러집니다.
  late final AnimationController _snap =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
  Animation<Offset>? _flight;

  /// 누른 뒤 시트가 뜰 때까지 — 그 사이 또 눌러도 한 번만.
  bool _opening = false;

  /// 듣고 있는 새 판 확인기(Scope.update) — 시험 기간이 바뀌면 곧바로 다시 그립니다.
  UpdateCheck? _update;

  /// 「꾹 눌러 옮길 수 있어요」 의 차례(머리 주석). 저장된 값을 읽기 전에는 없음.
  _Hint _hint = _Hint.none;

  /// 알림을 띄울 시계(1.2초 · 다시 보기 1초)와 걷을 시계(4초 · 흐려짐이 끝날 때).
  Timer? _hintWait, _hintEnd;

  /// 지난 그리기에서 말풍선이 보였나(들린 동안은 아님) — 띄울 시계가 울릴 때 봅니다.
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    feedbackBubbleOn.addListener(_changed);
    feedbackBusy.addListener(_changed);
    _snap.addListener(_changed);
    unawaited(_load());
  }

  Future<void> _load() async {
    await loadFeedbackBubbleOn();
    if (!mounted) return;
    /* 옛 모양의 자리를 옮기려면 화면 크기가 있어야 합니다 — 첫 프레임은 이미 그려졌습니다. */
    final mq = MediaQuery.maybeOf(context);
    /* 꾹 눌러 옮겨 둔 자리가 있으면 옮길 줄 아는 사람 — 알림은 띄우지 않고 본 것으로 적습니다.
       옛 칸에서 옮겨 적힐 자리(그냥 끌던 판)는 아닙니다 — 그래서 자리를 읽기 **전에** 봅니다. */
    final knows = await loadFeedbackBubbleMovedByLongPress();
    final pos = await loadFeedbackBubblePos(
        size: mq?.size ?? Size.zero, padding: mq?.viewPadding ?? EdgeInsets.zero);
    final seen = await loadFeedbackBubbleHintSeen();
    if (!seen && knows) unawaited(_markHintSeen());
    if (!mounted) return;
    setState(() {
      _pos = pos;
      _ready = true;
      if (!seen && !knows) _hint = _Hint.waiting;
    });
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  /* Scope 의 확인기를 듣습니다. Scope 에 기대지(depend) 않고 찾기만 합니다 — 기대면 기록이
     바뀔 때마다 다시 그립니다. 확인기는 앱에 하나라 서버를 옮겨도 같은 것입니다. */
  void _watch(UpdateCheck? u) {
    if (identical(u, _update)) return;
    _update?.removeListener(_changed);
    _update = u?..addListener(_changed);
  }

  @override
  void dispose() {
    feedbackBubbleOn.removeListener(_changed);
    feedbackBusy.removeListener(_changed);
    _update?.removeListener(_changed);
    _hintWait?.cancel();
    _hintEnd?.cancel();
    _snap.dispose();
    super.dispose();
  }

  /* --- 한 번 알림 --- */

  /* 그릴 때마다 — 말풍선이 보이면 1.2초 시계를 걸고(걸려 있으면 그대로), 숨으면 풀어서 다시
     보일 때 처음부터 셉니다. 떠 있는 알림은 말풍선이 숨거나 들리면 곧바로 걷습니다. 그리는
     중에 부르므로 setState 없이 값만 바꿉니다(바뀐 값으로 바로 그립니다). */
  void _hintWatch(bool visible) {
    _visible = visible;
    switch (_hint) {
      case _Hint.waiting:
        if (visible) {
          _hintWait ??= Timer(kBubbleHintDelay, _hintTry);
        } else {
          _hintWait?.cancel();
          _hintWait = null;
        }
      case _Hint.up:
        if (!visible) _hintOff();
      case _Hint.none:
      case _Hint.fading:
        break;
    }
  }

  /* 띄울 시계가 울림 — 아직 보이고 맨 위가 화면(PageRoute)이면 띄우고, 다이얼로그 · 시트가
     위면(또는 시트를 여는 중이면) 1초 뒤 다시 봅니다. 앱이 앞에 없어도(resumed 가 아님) 다시
     봅니다 — 새로 깐 안드로이드 13+ 의 첫 실행은 말풍선이 뜨고 곧 「알림을 허용할까요?」
     (nudge.dart, 시스템 창이라 경로가 아님)가 가운데를 덮고 앱은 inactive 입니다. 그 뒤에서
     띄우면 아무도 못 본 채 본 것으로 적힙니다. 뒤로 보낸 동안에도 시계는 웁니다. */
  void _hintTry() {
    _hintWait = null;
    if (!mounted || _hint != _Hint.waiting || !_visible) return;
    final life = WidgetsBinding.instance.lifecycleState;
    if (_opening ||
        (life != null && life != AppLifecycleState.resumed) ||
        widget.routes.top is! PageRoute) {
      _hintWait = Timer(_hintRetry, _hintTry);
      return;
    }
    /* 뜨는 순간 적습니다 — 떠 있는 동안 앱이 꺼져도 두 번 뜨지 않습니다. */
    unawaited(_markHintSeen());
    setState(() => _hint = _Hint.up);
    _hintEnd = Timer(kBubbleHintStay, () {
      if (mounted) setState(_hintOff);
    });
  }

  /* 걷기 — 떠 있었으면 흐려지고(흐려짐이 끝나면 트리에서 뺌), 아직 기다리던 중이면 곧바로
     끝. 어느 쪽이든 이번 실행에서 다시 뜨지 않습니다. setState 는 부르는 쪽이 합니다.
     이미 없거나 걷히는 중이면 손대지 않습니다 — 걷히는 중의 시계는 「없음」 으로 가는 시계라,
     그것을 끄면 투명한 알약이 이번 실행 내내 트리에 남습니다(흐려지는 0.36초 사이에 들 때). */
  void _hintOff() {
    if (_hint == _Hint.none || _hint == _Hint.fading) return;
    _hintWait?.cancel();
    _hintWait = null;
    _hintEnd?.cancel();
    _hintEnd = null;
    if (_hint == _Hint.up) {
      _hint = _Hint.fading;
      _hintEnd = Timer(_fade * 2, () {
        if (mounted) setState(() => _hint = _Hint.none);
      });
    } else if (_hint == _Hint.waiting) {
      _hint = _Hint.none;
    }
  }

  Offset _now(MediaQueryData mq) {
    if (_drag case final d?) return d;
    if (_snap.isAnimating && _flight != null) return _flight!.value;
    return feedbackBubbleCenter(_pos, mq.size, mq.viewPadding);
  }

  /* --- 꾹 눌러 옮기기 --- */

  void _lift(LongPressStartDetails _) {
    if (_opening || feedbackBusy.value || _drag != null) return;
    final at = _now(MediaQuery.of(context));
    _snap.stop();
    unawaited(HapticFeedback.mediumImpact());
    /* 스스로 든 사람은 옮길 줄 압니다 — 알림은 걷고(뜨기 전이었으면 본 것으로 적고) 다시 안 띄웁니다. */
    if (_hint == _Hint.waiting) unawaited(_markHintSeen());
    setState(() {
      _hintOff();
      _liftedAt = at;
      _drag = at;
      _hot = false;
    });
  }

  /* 손가락이 누른 자리에서 움직인 만큼. 들린 동안은 안전 영역 안(가장자리 네모)에서만. */
  void _move(LongPressMoveUpdateDetails d) {
    final from = _liftedAt;
    if (from == null || _drag == null) return;
    final mq = MediaQuery.of(context);
    final r = feedbackBubbleTrack(mq.size, mq.viewPadding);
    final p = from + d.offsetFromOrigin;
    final at = Offset(p.dx.clamp(r.left, r.right).toDouble(), p.dy.clamp(r.top, r.bottom).toDouble());
    final hot = feedbackBubbleOverBin(at, mq.size, mq.viewPadding);
    if (hot && !_hot) unawaited(HapticFeedback.heavyImpact());
    setState(() {
      _drag = at;
      _hot = hot;
    });
  }

  /* 놓으면 — X 위면 치우거나(시험 기간이면 안내하고 제자리로), 아니면 가장 가까운 가장자리로.
     거의 안 움직였거나 손가락이 취소되면(전화가 옴 등) 들기 전 자리로 돌아갑니다 — 그때
     자리를 새로 적으면 처음 자리(오른쪽 가장자리 가운데)가 비율로 굳습니다. */
  void _drop({bool cancelled = false}) {
    final at = _drag, from = _liftedAt;
    if (at == null) return;
    final mq = MediaQuery.of(context);
    final size = mq.size, pad = mq.viewPadding;
    var to = feedbackBubbleCenter(_pos, size, pad);
    FeedbackBubblePos? moved;
    var remove = false;
    String? say;
    if (cancelled || from == null || (at - from).distance < 4) {
      // 제자리
    } else if (feedbackBubbleOverBin(at, size, pad)) {
      if (feedbackBubbleLocked(_update)) {
        say = '테스트 기간에는 없앨 수 없어요';
      } else {
        remove = true;
        to = feedbackBubbleBinCenter(size, pad);
        say = '다시 켜려면 설정 → 도움말에서 켜세요';
      }
    } else {
      moved = feedbackBubbleSnap(at, size, pad);
      to = feedbackBubbleCenter(moved, size, pad);
    }
    setState(() {
      _drag = null;
      _liftedAt = null;
      _hot = false;
      if (moved != null) _pos = moved;
      _flight = Tween<Offset>(begin: at, end: to)
          .animate(CurvedAnimation(parent: _snap, curve: Curves.easeOutCubic));
    });
    _snap.forward(from: 0);
    if (moved != null) unawaited(_savePos(moved));
    /* 치우면 X 로 빨려 들어가며 흐려집니다. 자리(_pos)는 그대로 — 다시 켜면 옮겨 둔 자리에. */
    if (remove) unawaited(setFeedbackBubbleOn(false));
    if (say != null) toast(context, say);
  }

  /* --- 누르기 --- */

  Future<void> _open() async {
    if (_opening || _drag != null || feedbackBusy.value) return;
    _opening = true;
    try {
      await widget.routes.settled();
      if (!mounted) return;
      final ctx = widget.routes.pageContext;
      if (ctx == null || !ctx.mounted) return;
      await openFeedback(ctx, captureScreen: true);
    } finally {
      _opening = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final t = Theme.of(context);
    final scheme = t.colorScheme;
    /* Scope 가 아직 없으면(앱이 켜지는 중) 보낼 곳이 없습니다 — 그때는 안 보입니다.
       있고 없음만 보면 되므로 기대지(depend) 않습니다: 기대면 기록이 바뀔 때마다 다시 그립니다. */
    final scope = context.getElementForInheritedWidgetOfExactType<Scope>()?.widget as Scope?;
    _watch(scope?.update);
    final update = _update;
    /* 시험 기간이면 꺼 두었어도 보입니다. 꺼 둔 기기에서 시험이 끝났는지 아직 모르면(확인기가
       지난 답을 읽기 전) 기다립니다 — 머리 주석. */
    final on = feedbackBubbleOn.value ||
        (feedbackBubbleLocked(update) && (update == null || update.loaded));
    final shown = _ready &&
        scope != null &&
        on &&
        !feedbackBusy.value &&
        mq.viewInsets.bottom <= 0;
    final lifted = _drag != null;
    _hintWatch(shown && !lifted);
    final c = _now(mq);
    final dark = t.brightness == Brightness.dark;
    final bin = feedbackBubbleBinCenter(mq.size, mq.viewPadding);
    return Positioned.fill(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          /* X — 들린 동안만 아래 가운데에 떠오릅니다. 누름은 받지 않습니다(말풍선을 쥔 손가락이
             그대로 끌고 옵니다). */
          Positioned(
            left: bin.dx - _bin / 2,
            top: bin.dy - _bin / 2,
            width: _bin,
            height: _bin,
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: AnimatedSlide(
                  offset: lifted ? Offset.zero : const Offset(0, 0.6),
                  duration: _fade,
                  curve: Curves.easeOutCubic,
                  child: AnimatedOpacity(
                    opacity: lifted ? 1 : 0,
                    duration: _fade,
                    child: AnimatedScale(
                      scale: _hot ? 1.2 : 1.0,
                      duration: _quick,
                      child: AnimatedContainer(
                        key: const Key('feedback-bubble-bin'),
                        duration: _quick,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _hot ? scheme.error : scheme.inverseSurface.withValues(alpha: 0.88),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: dark ? 0.45 : 0.18),
                              blurRadius: 12,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Icon(LucideIcons.x,
                            size: 26, color: _hot ? scheme.onError : scheme.onInverseSurface),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          /* 한 번 알림 — 말풍선 옆(화면 가운데 쪽) 알약. 누름 · 스크린리더 모두 받지 않습니다(머리 주석).
             기다리는 동안 투명하게 트리에 두어야 뜰 때 흐려지며 나타납니다. **열쇠(key)가 있어야
             합니다** — 없으면 이 칸이 들고 날 때 뒤의 말풍선 칸이 한 칸 밀려 알림 칸의 요소를
             물려받고, 꾹 누르는 중이던 손가락의 인식기가 새로 만들어져 들린 말풍선이 멈춥니다. */
          if (_hint != _Hint.none)
            Positioned.fill(
              key: const ValueKey('feedback-bubble-hint-slot'),
              child: IgnorePointer(
                child: ExcludeSemantics(
                  child: CustomSingleChildLayout(
                    delegate: _HintSpot(c, mq.viewPadding),
                    child: AnimatedOpacity(
                      opacity: _hint == _Hint.up ? 1 : 0,
                      duration: _fade,
                      child: DecoratedBox(
                        key: const Key('feedback-bubble-hint'),
                        decoration: BoxDecoration(
                          color: scheme.inverseSurface,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: dark ? 0.35 : 0.12),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          /* 말풍선 층은 Navigator 위라 Material 밑이 아닙니다 — 글자 모양을 직접 줍니다
                             (안 주면 MaterialApp 의 "Material 없음" 표시 글꼴이 붙습니다). */
                          child: DefaultTextStyle(
                            style: (t.textTheme.bodySmall ?? const TextStyle(fontSize: 12))
                                .copyWith(color: scheme.onInverseSurface),
                            child: const Text('꾹 눌러 옮길 수 있어요'),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            left: c.dx - _hit / 2,
            top: c.dy - _hit / 2,
            width: _hit,
            height: _hit,
            child: IgnorePointer(
              ignoring: !shown,
              child: ExcludeSemantics(
                excluding: !shown,
                child: AnimatedOpacity(
                  opacity: shown ? 1 : 0,
                  duration: _fade,
                  child: Semantics(
                    key: const Key('feedback-bubble'),
                    container: true,
                    button: true,
                    label: '의견 보내기',
                    onTap: _open,
                    /* GestureDetector 대신 RawGestureDetector — 꾹 누르기 시간을 정하려면
                       인식기를 직접 만들어야 합니다(GestureDetector 는 0.5초 고정). 탭과 꾹
                       누르기가 같은 경기장에서 겨루는 것은 GestureDetector 와 같습니다. */
                    child: RawGestureDetector(
                      behavior: HitTestBehavior.opaque,
                      excludeFromSemantics: true,
                      gestures: <Type, GestureRecognizerFactory>{
                        TapGestureRecognizer:
                            GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
                          () => TapGestureRecognizer(debugOwner: this),
                          (r) => r.onTap = _open,
                        ),
                        /* 꾹 눌러야 들립니다(머리 주석). 끌기(pan)는 걸지 않습니다 — 그냥 끄는
                           손가락에는 아무 일도 없습니다. */
                        LongPressGestureRecognizer:
                            GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
                          () => LongPressGestureRecognizer(
                              duration: kBubbleLongPress, debugOwner: this),
                          (r) => r
                            ..onLongPressStart = _lift
                            ..onLongPressMoveUpdate = _move
                            ..onLongPressEnd = ((_) => _drop())
                            ..onLongPressCancel = (() => _drop(cancelled: true)),
                        ),
                      },
                      child: AnimatedScale(
                        scale: lifted ? 1.15 : 1.0,
                        duration: _quick,
                        child: Center(
                          child: DecoratedBox(
                            key: const Key('feedback-bubble-dot'),
                            decoration: BoxDecoration(
                              color: scheme.surface.withValues(alpha: 0.9),
                              shape: BoxShape.circle,
                              /* 가는 선 — 물리 픽셀 한 줄. 밝은 화면의 흰 바탕 위에서도 테두리가 보이게. */
                              border: Border.all(
                                  color: scheme.outlineVariant, width: 1 / mq.devicePixelRatio),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: dark ? 0.45 : 0.14),
                                  blurRadius: lifted ? 16 : 10,
                                  offset: Offset(0, lifted ? 4 : 2),
                                ),
                              ],
                            ),
                            child: SizedBox(
                              width: _dot,
                              height: _dot,
                              child: Icon(LucideIcons.messageSquare, size: 20, color: scheme.primary),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/* 한 번 알림 알약의 자리 — 동그라미([c] 가 가운데) 옆, 화면 가운데 쪽으로 8px 떼고 높이는
   동그라미 가운데. 폭은 그쪽 가장자리(안전 영역 안 16px)까지 남은 만큼만이라 글자가 커도 화면
   밖으로 안 나가고(넘치면 줄을 바꿈), 위아래는 안전 영역 안으로 당깁니다. */
class _HintSpot extends SingleChildLayoutDelegate {
  const _HintSpot(this.c, this.pad);
  final Offset c;
  final EdgeInsets pad;

  /// 말풍선이 오른쪽 반(한가운데 포함)이면 알약은 그 왼쪽, 아니면 오른쪽.
  bool _toLeft(double width) => c.dx >= width / 2;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final w = constraints.maxWidth;
    final room = _toLeft(w)
        ? c.dx - _dot / 2 - _hintGap - (pad.left + _inset)
        : (w - pad.right - _inset) - (c.dx + _dot / 2 + _hintGap);
    return BoxConstraints(
        maxWidth: math.max(0.0, room), maxHeight: math.max(0.0, constraints.maxHeight - pad.vertical));
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final x = _toLeft(size.width) ? c.dx - _dot / 2 - _hintGap - childSize.width : c.dx + _dot / 2 + _hintGap;
    final lo = pad.top, hi = math.max(lo, size.height - pad.bottom - childSize.height);
    return Offset(x, (c.dy - childSize.height / 2).clamp(lo, hi).toDouble());
  }

  @override
  bool shouldRelayout(_HintSpot oldDelegate) => oldDelegate.c != c || oldDelegate.pad != pad;
}
