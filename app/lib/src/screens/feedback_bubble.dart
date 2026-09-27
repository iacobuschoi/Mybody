/* =============================================================================
 * feedback_bubble.dart — 화면 옆에 늘 떠 있는 「의견 보내기」 말풍선
 *
 * 왜 있나
 *   주인의 말: "의견보내기는 설정 드가서 하는게 아니라 앱 어딘가에 상시 떠있는 버튼으로".
 *   앱바의 말풍선은 탭 화면에만 있었고, 밀어 올린 화면(목표 · 검수 · 운동 기록 …)과
 *   로그인 · 첫 설정 화면에는 없었습니다. 이상한 것은 대개 그런 화면에서 보입니다 —
 *   거기서 설정까지 찾아가면 이상했던 화면은 이미 사라져 있습니다. 그래서 앱 맨 위에
 *   말풍선 하나를 띄워 **어느 화면에서든 한 번 누르면** 그 화면이 붙은 시트가 뜹니다.
 *
 * 어디에 · 얼마나 크게
 *   · 오른쪽 가장자리(8px 안쪽), 가운데가 쓸 수 있는 높이의 58% 쯤. 위로는 앱바,
 *     아래로는 탭바(80)와 홈의 「인바디」 단추(16 + 56)가 있어 그 사이의 조금 아래입니다 —
 *     엄지가 닿고, 목록의 첫 줄 · 맨 아래 큰 단추를 가리지 않는 자리.
 *   · 동그라미 40px(누르는 칸은 48px). 표면색을 조금 비치게(0.9) · 가는 테두리 · 옅은
 *     그림자 — 화면 위에 "얹힌 것" 으로 읽히되 내용보다 튀지 않게. 색은 전부 테마에서라
 *     어두운 테마에서도 같은 대비입니다.
 *   · 끌어서 옮기고, 놓으면 가까운 쪽 가장자리(왼쪽 · 오른쪽)로 붙습니다. 위아래는 앱바
 *     밑 ~ 탭바 · 「인바디」 단추 위 사이로만 — 어디로 끌어도 그 둘을 덮지 않습니다.
 *     옮긴 자리({쪽, 높이 비율})는 이 기기에 둡니다(SharedPreferences). 손 크기 · 화면은
 *     폰마다 다르니 동기화하는 settings 에 넣지 않습니다.
 *
 * 찍히지 않게
 *   말풍선은 캡처 경계([appCaptureBoundary]) **바깥**, 그 형제로 섭니다([appFrame]).
 *   경계 안에 있으면 보낸 화면마다 말풍선이 찍혀 그 밑의 내용을 가립니다.
 *
 * 숨는 때(짧게 흐려지며 — 끝이 있는 애니메이션)
 *   · 키보드가 올라와 있을 때 — 입력칸 오른쪽 끝을 덮고, 그때는 쓰는 중입니다.
 *   · 의견 시트가 뜨는 중(찍는 중 포함)이거나 떠 있을 때 — 두 번 누를 일이 없습니다.
 *   · 설정에서 껐거나, 길게 눌러 「의견 버튼 숨기기」 를 골랐을 때([feedbackBubbleOn]).
 *     숨기면 "설정 → 도움말에서 다시 켤 수 있어요" 한 줄 — 사라진 것을 되찾는 길을 그 자리에서.
 *   · 앱이 켜지는 중(Scope 가 아직 없을 때) — 보낼 곳(Api)이 없어 눌러도 못 보냅니다.
 *
 * 누르면 — Navigator 위에서 Navigator 에 닿기
 *   말풍선은 Navigator **위**(MaterialApp.builder)에 있어서 자기 context 로는 시트를
 *   띄울 수 없습니다(Navigator · Overlay 가 아래에 있음). 그래서 [FeedbackRoutes] 가
 *   Navigator 를 지켜보다가(navigatorObservers) 지금 맨 위의 **화면**(PageRoute —
 *   시트 · 다이얼로그는 건너뜀)의 context 를 건넵니다. 의견 시트는 그 context 로
 *   앱바 제목(홈 · 식단 · 설정 …)을 읽어 "어느 화면" 칸을 채웁니다 — 셸의 앱바 단추가
 *   하던 그대로입니다.
 *   navigatorKey(GlobalKey) 대신 이것을 쓰는 까닭: 앱은 켜는 동안 MaterialApp 을 바로
 *   내놓고, 준비되면 그 위에 Scope 를 씌웁니다(main.dart). GlobalKey 를 단 Navigator 는
 *   그때 **옮겨 붙어** 켜는 중의 화면(도는 원)을 경로로 쥔 채 남습니다 — 셸이 영영 안
 *   뜹니다. 지켜보는 쪽은 옛 Navigator 에서 떨어지고 새 Navigator 에 붙기만 합니다.
 *   · 막 뜨는 중인 화면(인사 시트가 올라오는 첫 프레임 등)이면 다 뜰 때까지 잠깐
 *     기다렸다 찍습니다([FeedbackRoutes.settled]) — 반쯤 올라온 시트가 찍히면 이상합니다.
 *
 * 스크린리더
 *   「의견 보내기」 단추 하나. 길게 누르기(숨기기 메뉴)는 힌트로 알립니다. 숨어 있을 때는
 *   트리에서 빠집니다 — 안 보이는 단추를 짚으면 안 됩니다.
 * ========================================================================== */
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../scope.dart';
import '../ui/edge.dart' show edgeSafe;
import '../ui/widgets.dart' show toast;
import 'feedback.dart';

/* --- 자리 저장 ---------------------------------------------------------------- */

/// 붙은 쪽 — 'left' · 'right'.
const String kFeedbackBubbleSideKey = 'mybody.feedbackBubble.side.v1';

/// 가운데 높이 — 안전 영역 안 쓸 수 있는 높이에서의 비율(0 = 맨 위, 1 = 맨 아래).
/// 화면 크기 · 방향이 바뀌어도 같은 느낌의 자리가 되게 픽셀이 아니라 비율로 둡니다.
const String kFeedbackBubbleYKey = 'mybody.feedbackBubble.y.v1';

/// 처음 자리 — 쓸 수 있는 높이의 58%(머리 주석).
const double kFeedbackBubbleDefaultY = 0.58;

/// 저장된 자리. 없거나 못 읽으면 오른쪽 · 58%.
Future<({bool right, double y})> loadFeedbackBubblePos() async {
  try {
    final sp = await SharedPreferences.getInstance();
    final y = sp.getDouble(kFeedbackBubbleYKey);
    return (
      right: sp.getString(kFeedbackBubbleSideKey) != 'left',
      y: y == null || !y.isFinite ? kFeedbackBubbleDefaultY : y.clamp(0.0, 1.0).toDouble(),
    );
  } catch (_) {
    return (right: true, y: kFeedbackBubbleDefaultY);
  }
}

Future<void> _savePos(bool right, double y) async {
  try {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(kFeedbackBubbleSideKey, right ? 'right' : 'left');
    await sp.setDouble(kFeedbackBubbleYKey, y);
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

/// [child](앱 전체) 위에 말풍선을 얹습니다. 말풍선 칸(48px) 밖의 누름은 그대로 앱으로 갑니다.
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

/* 크기 · 자리(머리 주석). */
const double _dot = 40; // 보이는 동그라미
const double _hit = 48; // 누르는 칸
const double _inset = 8; // 가장자리에서 동그라미까지
const double _gap = 8; // 앱바 · 아래 단추들과 띄우는 틈
/* 아래로 비워 두는 몫: 탭바(80) + 「인바디」 단추의 여백(16)과 높이(56) + 틈. 밀어 올린
   화면에는 탭바가 없지만 맨 아래 큰 단추(저장 · 다음)가 대개 그 높이에 있습니다. */
const double _bottomClear = 80 + 16 + 56 + _gap;

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
  bool _right = true;
  double _y = kFeedbackBubbleDefaultY;

  /// 끄는 중인 가운데(화면 좌표). 놓으면 비웁니다.
  Offset? _drag;

  /// 놓은 자리 → 붙을 자리. 짧게(0.22초) 미끄러집니다.
  late final AnimationController _snap =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
  Animation<Offset>? _snapTo;

  /// 누른 뒤 시트가 뜰 때까지 — 그 사이 또 눌러도 한 번만.
  bool _opening = false;

  /// 길게 눌러 연 「숨기기」 메뉴가 떠 있나. 말풍선은 Navigator **위**라 메뉴의 가림막이
  /// 말풍선을 덮지 못합니다 — 그대로 두면 메뉴가 떠 있는 채로 눌러 의견 시트가 메뉴 위에
  /// 쌓이고, 또 길게 누르면 메뉴가 두 장이 되고, 끌면 메뉴만 옛 자리에 남습니다. 메뉴가
  /// 떠 있는 동안은 말풍선이 아무것도 안 합니다(메뉴 밖을 누르면 닫힘).
  bool _menuOpen = false;

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
    final pos = await loadFeedbackBubblePos();
    if (!mounted) return;
    setState(() {
      _right = pos.right;
      _y = pos.y;
      _ready = true;
    });
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    feedbackBubbleOn.removeListener(_changed);
    feedbackBusy.removeListener(_changed);
    _snap.dispose();
    super.dispose();
  }

  /* --- 자리 계산 — 모두 화면(창) 좌표, 기준은 동그라미의 가운데 --- */

  /// 위아래로 갈 수 있는 가운데의 범위 — 앱바 밑 ~ 아래 단추들 위.
  /// 화면이 아주 낮아 범위가 뒤집히면 그 가운데 한 점.
  (double, double) _band(MediaQueryData mq) {
    final pad = mq.viewPadding;
    final lo = pad.top + kToolbarHeight + _gap + _hit / 2;
    final hi = mq.size.height - pad.bottom - _bottomClear - _hit / 2;
    if (lo <= hi) return (lo, hi);
    final mid = (lo + hi) / 2;
    return (mid, mid);
  }

  double _usable(MediaQueryData mq) =>
      math.max(1.0, mq.size.height - mq.viewPadding.top - mq.viewPadding.bottom);

  /// 쪽 · 높이 비율로 붙어 있는 자리.
  Offset _center(MediaQueryData mq, bool right, double y) {
    final pad = mq.viewPadding;
    final x = right ? mq.size.width - pad.right - _inset - _dot / 2 : pad.left + _inset + _dot / 2;
    final (lo, hi) = _band(mq);
    return Offset(x, (pad.top + y * _usable(mq)).clamp(lo, hi).toDouble());
  }

  /// 끄는 중에는 화면 안 · 위아래 범위 안에서만.
  Offset _clamp(MediaQueryData mq, Offset p) {
    final pad = mq.viewPadding;
    final (lo, hi) = _band(mq);
    final l = pad.left + _hit / 2, r = mq.size.width - pad.right - _hit / 2;
    return Offset(l <= r ? p.dx.clamp(l, r).toDouble() : mq.size.width / 2, p.dy.clamp(lo, hi).toDouble());
  }

  Offset _now(MediaQueryData mq) {
    if (_drag case final d?) return d;
    if (_snap.isAnimating && _snapTo != null) return _snapTo!.value;
    return _center(mq, _right, _y);
  }

  /* --- 끌기 --- */

  void _start(DragStartDetails _) {
    if (_menuOpen) return; // 메뉴가 옛 자리에 남지 않게(_menuOpen)
    final mq = MediaQuery.of(context);
    final at = _now(mq);
    _snap.stop();
    setState(() => _drag = at);
  }

  void _move(DragUpdateDetails d) {
    final at = _drag;
    if (at == null) return;
    setState(() => _drag = _clamp(MediaQuery.of(context), at + d.delta));
  }

  /* 놓으면 가까운 쪽 가장자리로. 높이는 놓은 그 높이(범위 안) — 비율로 적어 둡니다. */
  void _release() {
    final from = _drag;
    if (from == null) return;
    final mq = MediaQuery.of(context);
    final right = from.dx >= mq.size.width / 2;
    final y = ((from.dy - mq.viewPadding.top) / _usable(mq)).clamp(0.0, 1.0).toDouble();
    final to = _center(mq, right, y);
    setState(() {
      _drag = null;
      _right = right;
      _y = y;
      _snapTo = Tween<Offset>(begin: from, end: to)
          .animate(CurvedAnimation(parent: _snap, curve: Curves.easeOutCubic));
    });
    _snap.forward(from: 0);
    unawaited(_savePos(right, y));
  }

  /* --- 누르기 · 길게 누르기 --- */

  Future<void> _open() async {
    if (_opening || _menuOpen || feedbackBusy.value) return;
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

  /* 작은 메뉴 하나 — 말풍선 **옆**에(붙은 쪽의 안쪽으로) 펼칩니다. 메뉴는 Navigator 안에
     그려지고 말풍선은 그 위에 있어서, 겹쳐 펼치면 말풍선이 메뉴 귀퉁이를 가립니다. */
  Future<void> _menu() async {
    if (_menuOpen || _opening || feedbackBusy.value) return;
    final nav = widget.routes.navigator;
    final box = context.findRenderObject();
    final overlay = nav?.overlay?.context.findRenderObject();
    if (nav == null || box is! RenderBox || !box.hasSize || overlay is! RenderBox) return;
    final tl = overlay.globalToLocal(box.localToGlobal(Offset.zero));
    final r = tl & box.size;
    final w = overlay.size.width, h = overlay.size.height;
    final at = _right
        ? RelativeRect.fromLTRB(r.left - 4, r.top, w - (r.left - 4), h - r.bottom)
        : RelativeRect.fromLTRB(r.right + 4, r.top, w - (r.right + 4), h - r.bottom);
    _menuOpen = true;
    final String? pick;
    try {
      pick = await showMenu<String>(
        context: nav.context,
        position: at,
        items: [
          PopupMenuItem<String>(
            key: const Key('feedback-bubble-hide'),
            value: 'hide',
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(LucideIcons.eyeOff, size: 18, color: Theme.of(nav.context).hintColor),
              const SizedBox(width: 10),
              const Text('의견 버튼 숨기기'),
            ]),
          ),
        ],
      );
    } finally {
      _menuOpen = false;
    }
    if (pick != 'hide') return;
    await setFeedbackBubbleOn(false);
    if (nav.mounted) toast(nav.context, '설정 → 도움말에서 다시 켤 수 있어요');
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final t = Theme.of(context);
    final scheme = t.colorScheme;
    /* Scope 가 아직 없으면(앱이 켜지는 중) 보낼 곳이 없습니다 — 그때는 안 보입니다.
       있고 없음만 보면 되므로 기대지(depend) 않습니다: 기대면 기록이 바뀔 때마다 다시 그립니다. */
    final hasScope = context.getElementForInheritedWidgetOfExactType<Scope>() != null;
    final shown = _ready &&
        hasScope &&
        feedbackBubbleOn.value &&
        !feedbackBusy.value &&
        mq.viewInsets.bottom <= 0;
    final c = _now(mq);
    final dark = t.brightness == Brightness.dark;
    return Positioned(
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
            duration: const Duration(milliseconds: 180),
            child: Semantics(
              key: const Key('feedback-bubble'),
              container: true,
              button: true,
              label: '의견 보내기',
              onTap: _open,
              onLongPress: _menu,
              onLongPressHint: '의견 버튼 숨기기',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                excludeFromSemantics: true,
                onTap: _open,
                onLongPress: _menu,
                /* 누른 자리부터 따라오게 — 기본(start)은 손이 18px 쯤 움직인 뒤부터 세어서
                   말풍선이 손가락보다 한 박자 뒤처집니다. */
                dragStartBehavior: DragStartBehavior.down,
                onPanStart: _start,
                onPanUpdate: _move,
                onPanEnd: (_) => _release(),
                onPanCancel: _release,
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
                          blurRadius: 10,
                          offset: const Offset(0, 2),
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
    );
  }
}
