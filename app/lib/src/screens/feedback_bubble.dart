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
 * 처음 자리 — 홈 「인바디」 단추 바로 위
 *   오른쪽 가장자리, 동그라미 아래 끝이 「인바디」 단추(확장 FAB) 위 끝보다 12px 위.
 *   탭바(80) + 단추 여백(16) + 단추(56) + 틈(12) + 아래 안전 영역에서 셉니다 — 단추와 같은
 *   16px 가장자리라 오른쪽 끝이 단추와 나란합니다. 엄지가 이미 가 있는 자리이고, 「인바디」
 *   를 누르려는 손이 말풍선을 누르지 않게 틈을 둡니다. 밀어 올린 화면에는 탭바가 없지만
 *   맨 아래 큰 단추(저장 · 다음)가 대개 그 높이라 같은 자리가 맞습니다.
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
   그래야 처음 자리의 오른쪽 끝이 단추와 나란합니다. */
const double _inset = 16;
const double _navBar = 80; // 탭바(Material 3 NavigationBar)
const double _fabMargin = 16; // 탭바와 「인바디」 단추 사이
const double _fab = 56; // 「인바디」 단추 높이
const double _fabGap = 12; // 단추 위 끝과 말풍선 아래 끝 사이
const double _bin = 56; // X 동그라미
const double _binLift = 24; // 아래 안전 영역에서 X 아래 끝까지
const double _binReach = 64; // 말풍선 가운데가 이 안이면 "X 위"
/* 아래 가장자리에 붙을 때 X 가운데에서 가로로 이만큼은 비킵니다 — X 위(64)도, X 와 겹치는
   자리도 아니게. */
const double _binClear = _binReach + 8;

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

/// 처음 자리 — 오른쪽 가장자리, 「인바디」 단추 바로 위(머리 주석).
Offset feedbackBubbleHome(Size size, EdgeInsets pad) {
  final r = feedbackBubbleTrack(size, pad);
  final y = size.height - pad.bottom - _navBar - _fabMargin - _fab - _fabGap - _dot / 2;
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
const Duration _fade = Duration(milliseconds: 180);
const Duration _quick = Duration(milliseconds: 120);

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

  /// 붙어 있는 자리. null 이면 처음 자리(「인바디」 단추 위).
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
    final pos = await loadFeedbackBubblePos(
        size: mq?.size ?? Size.zero, padding: mq?.viewPadding ?? EdgeInsets.zero);
    if (!mounted) return;
    setState(() {
      _pos = pos;
      _ready = true;
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
    _snap.dispose();
    super.dispose();
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
    setState(() {
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
     자리를 새로 적으면 처음 자리(「인바디」 위)가 비율로 굳습니다. */
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
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      excludeFromSemantics: true,
                      onTap: _open,
                      /* 꾹 눌러야 들립니다(머리 주석). 끌기(pan)는 걸지 않습니다 — 그냥 끄는
                         손가락에는 아무 일도 없습니다. */
                      onLongPressStart: _lift,
                      onLongPressMoveUpdate: _move,
                      onLongPressEnd: (_) => _drop(),
                      onLongPressCancel: () => _drop(cancelled: true),
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
