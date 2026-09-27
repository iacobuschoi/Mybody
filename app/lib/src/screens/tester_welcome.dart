/* =============================================================================
 * tester_welcome.dart — 비공개 테스트에 들어온 사람에게 한 번 드리는 인사
 *
 * 테스터는 초대 링크 하나 누르고 들어온 친구들입니다. 앱을 깔고 나서 "이게
 * 뭐 하는 앱이지", "불편하면 어디에 말하지", "친구랑 같이 하라던데 어떻게
 * 하지" 를 스스로 찾아야 했습니다. 셋 다 앱 안에 길은 있었는데 아무도 가리키지
 * 않았습니다. 그래서 탭 화면이 처음 뜰 때 시트 한 장으로 세 쪽을 넘깁니다 —
 * 주인이 목업(아래에서 올라오는 시트 · 세 쪽 넘기기 · 오른쪽 위 「건너뛰기」 ·
 * 쪽 점 · 아래 큰 단추)으로 고른 모양입니다.
 *
 *   1쪽 인사   폭죽 한 번, 고맙다는 말, 새 판 알림과 의견 버튼(화면 옆 말풍선 —
 *              feedback_bubble.dart)이 어디 있는지 두 줄. 말풍선은 이 시트 위에도 떠
 *              있어서 "화면 옆" 이 무엇인지 그 자리에서 보입니다.
 *              큰 제목은 **기종마다 다릅니다**([welcomeTitle]) — 아이폰 판은 앱스토어
 *              심사에도 그대로 들어가서 "테스트" 라는 말을 뺍니다(아래 함수 주석).
 *   2쪽 쓰는 법  결과지 찍기 → 목표 → 매일 기록 → 변화 보기, 네 장. 한 줄씩만 —
 *              읽게 하지 않고 훑게 합니다.
 *   3쪽 친구   내 친구 코드와 「복사」 · 「카톡 등으로 보내기」, 받은 코드를 넣는 칸.
 *              시트를 떠나지 않고 요청까지 끝납니다 — 친구 탭으로 보내면 거기서
 *              「친구 추가」 를 또 찾아야 합니다. 로그인 안 한 사람에게는 코드 대신
 *              「로그인 · 가입」 을 두고, 로그인하고 돌아오면 그 자리에 코드가 뜹니다.
 *
 * 지키는 것
 *   · **한 번만.** settings 의 testerWelcomeSeen 에 적습니다 — 띄우기 **전에**
 *     적어서, 건너뛰어도 · 시트 밖을 눌러 닫아도 · 앱이 도중에 꺼져도 본 것입니다.
 *     다시 올리면 안내가 아니라 방해입니다. 다시 보려면 설정의 「앱 안내 다시
 *     보기」(force). 헬스 튜토리얼(kGymTutorialSeenKey)과 같은 자리 · 같은 방식입니다.
 *   · **겹쳐 뜨지 않게.** 떠 있는 동안 [_live] 가 그 시트를 쥐고 있어, 설정의
 *     「다시 보기」 가 같이 와도 두 장이 쌓이지 않습니다. 의견 시트가 떠 있으면(찍는 중
 *     포함 — feedbackBusy) 그 위에 덮지 않고 기다렸다가, 의견 시트가 닫히면 한 번
 *     띄웁니다. 셸은 로그인한 사람의 /me 를 4초까지 기다린 뒤 인사를 부르는데, 그 사이
 *     말풍선을 누른 사람의 의견 시트를 인사가 덮으면 쓰던 글 · 붙인 화면이 가려집니다.
 *   · 친구 요청은 친구 탭과 **같은 함수**([requestFriendByCode])로 보냅니다. 실패
 *     문구도 서버가 준 까닭 그대로라 두 곳이 다른 말을 하지 않습니다.
 *   · 보내는 글([inviteShareText])은 순수 함수입니다 — 받은 친구가 그 글 하나로
 *     앱을 깔고 코드를 넣을 수 있어야 해서 시험으로 못 박습니다. 테스트 참여 주소는
 *     서버의 /api/version 이 주는 것([JoinLinks])만 싣습니다 — 주인이 서버에서 바꾸면
 *     앱을 다시 내지 않아도 따라옵니다.
 *   · 키보드가 올라오면 시트가 그만큼 위로 밀리고, 쪽 점과 아래 단추는 잠시
 *     접힙니다 — 작은 폰에서 코드 칸과 「요청」 이 키보드 위에 남을 자리를 만들려고.
 *     「복사했어요」 같은 짧은 알림은 시트 **안의** 스낵바로 — 앱의 스낵바는 시트
 *     밑에 깔려 안 보입니다.
 *   · 색은 전부 테마에서 — 어두운 테마에서도 같은 대비로 보여야 합니다.
 *   · 가운데 맞춘 큰 글은 **빈칸에서만** 줄을 바꿉니다([keepWords]). 한글은 글자마다
 *     줄이 바뀔 수 있어 360 폭에서 「감사합 / 니다!」 로 끊겼습니다 — 인사의 첫 줄이
 *     제일 어설퍼 보이는 자리였습니다.
 * ========================================================================== */
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:mybody_core/mybody_core.dart' as core;
import 'package:share_plus/share_plus.dart';

import '../api.dart';
import '../app_state.dart';
import '../scope.dart';
import '../ui/confetti.dart';
import '../ui/edge.dart' show dismissKeyboard;
import '../ui/widgets.dart';
import '../update.dart' show JoinLinks;
import 'account.dart' show SignInScreen;
import 'feedback.dart' show feedbackBusy, feedbackClosed;
import 'social.dart' show requestFriendByCode, becameFriends;

/// settings 의 표 — 테스터 인사를 한 번 봤는가(건너뛴 것도 본 것).
const String kTesterWelcomeSeenKey = 'testerWelcomeSeen';

/// 한 번 봤는가(건너뛴 것 · 밖을 눌러 닫은 것도 본 것).
bool testerWelcomeSeen(Map<String, Object?> state) =>
    core.jsTruthy(((state['settings'] as Map?) ?? const {})[kTesterWelcomeSeenKey]);

/// 본 것으로 적습니다. 이미 적혀 있으면 저장을 건드리지 않습니다 — 괜히 적으면
/// 동기화가 바뀐 것으로 알고 올립니다.
void markTesterWelcomeSeen(AppState app) {
  final settings = ((app.state['settings'] as Map?) ?? const {}).cast<String, Object?>();
  if (core.jsTruthy(settings[kTesterWelcomeSeenKey])) return;
  app.store.set({'settings': {...settings, kTesterWelcomeSeenKey: true}});
}

/* 지금 떠 있는 인사 시트. 닫히면(dispose) 비웁니다 — 여기가 차 있으면 새로 안 띄웁니다. */
State<TesterWelcomeSheet>? _live;

/* 의견 시트가 닫히기를 기다리는 중인가 — 기다리는 동안 또 불려도 한 번만 띄웁니다. */
bool _waiting = false;

/// 1쪽의 큰 제목 — 기종마다 다릅니다.
///
/// 안드로이드는 플레이 비공개 테스트로만 나가서 "비공개 테스트" 가 사실 그대로입니다.
/// 아이폰 판은 같은 빌드가 TestFlight 에도, **앱스토어 심사**에도 들어갑니다. 심사하는
/// 사람 화면에 "테스트 · 베타" 가 뜨면 시험판을 냈다고 보고 거절할 수 있습니다(App Review
/// 지침 2.2 — 베타 · 데모 · 시험판은 앱스토어가 아니라 TestFlight 로). 그런데 앱 안에서는
/// TestFlight 와 심사를 가를 수 없습니다 — 둘 다 샌드박스 영수증이라 앱이 받는 단서가
/// 같습니다(update.dart 의 channelLabel 주석). 그래서 아이폰에서는 늘 테스트라는 말이
/// 없는 인사를 씁니다. 나머지 글은 두 기종이 같습니다.
String welcomeTitle([TargetPlatform? platform]) =>
    (platform ?? defaultTargetPlatform) == TargetPlatform.iOS
        ? '함께해 주셔서 고마워요!'
        : '비공개 테스트에 참여해 주셔서 감사합니다!';

/// 테스터 인사 팝업. [force] 면 본 적이 있어도 띄웁니다(설정 「앱 안내 다시 보기」).
Future<void> showTesterWelcome(BuildContext context, {bool force = false}) async {
  if (_live != null || _waiting) return;
  /* 의견 시트가 떠 있으면(찍는 중 포함) 닫힐 때까지 기다렸다가 처음부터 다시 봅니다 —
     그 사이 화면이 내려갔거나(context) 다른 길로 이미 떴으면(_live) 안 띄웁니다. */
  if (feedbackBusy.value) {
    _waiting = true;
    try {
      await feedbackClosed();
    } finally {
      _waiting = false;
    }
    if (!context.mounted) return;
    return showTesterWelcome(context, force: force);
  }
  final app = Scope.of(context);
  if (!force && testerWelcomeSeen(app.state)) return;
  /* **띄우기 전에** 적습니다 — 닫는 길(건너뛰기 · 바깥 탭 · 끌어 내리기 · 뒤로 ·
     앱 종료)이 여럿이라 닫힐 때 적으면 한 길은 꼭 빠집니다. */
  markTesterWelcomeSeen(app);
  dismissKeyboard();
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    /* 손잡이는 시트가 직접 그립니다 — 기본 손잡이는 한 줄(48px)을 따로 먹어서
       「건너뛰기」 줄과 합치면 작은 폰에서 3쪽이 한 줄 더 밀립니다. */
    showDragHandle: false,
    builder: (_) => const TesterWelcomeSheet(),
  );
}

/// 「카톡 등으로 보내기」 로 나가는 글.
///
/// 첫 줄은 코드, 그 밑에 서버가 알려 준 테스트 참여 주소가 **있는 것만**. 안드로이드
/// 비공개 테스트는 구글 그룹에 먼저 들어야 참여 주소가 열려서 ① 가입 ② 참여 차례로
/// 씁니다(그룹 주소만 있고 참여 주소가 없으면 반쪽 길이라 안 싣습니다). 주소가 하나도
/// 없으면(이미 앱이 있는 친구에게 보내는 경우) 코드를 어디에 넣는지 한 줄.
String inviteShareText(String code, JoinLinks join) {
  final links = <String>[
    if (join.ios.isNotEmpty) '아이폰: ${join.ios}',
    if (join.android.isNotEmpty)
      join.androidGroup.isNotEmpty
          ? '안드로이드: ① ${join.androidGroup} 가입 ② ${join.android} 에서 참여'
          : '안드로이드: ${join.android}',
  ];
  return [
    'Mybody 같이 해요! 내 친구 코드: $code',
    if (links.isEmpty) '앱에서 친구 탭 → 친구 추가에 넣어 주세요' else ...links,
  ].join('\n');
}

/// 낱말 안에서는 줄을 안 바꾸게 — 글자 사이에 단어 잇기(U+2060, 폭 없음)를 넣습니다.
/// 줄은 빈칸에서만 바뀝니다. 한 낱말이 한 줄보다 길면 그때는 글자에서 끊깁니다.
String keepWords(String s) =>
    s.split(' ').map((w) => w.characters.join('\u2060')).join(' ');

/// 공유 시트를 여는 길. 시험에서는 바꿔 끼웁니다 — 진짜 공유 시트는 플랫폼 채널이라
/// 시험 안에서는 열리지 않습니다. [origin] 은 아이패드에서 말풍선이 나올 자리.
@visibleForTesting
Future<void> Function(String text, Rect? origin) testerWelcomeShare = _shareOut;

Future<void> _shareOut(String text, Rect? origin) async {
  await SharePlus.instance.share(ShareParams(text: text, sharePositionOrigin: origin));
}

/// 인사 시트 — [showTesterWelcome] 이 띄웁니다. 시험이 직접 세울 수 있게 공개합니다.
class TesterWelcomeSheet extends StatefulWidget {
  const TesterWelcomeSheet({super.key});

  @override
  State<TesterWelcomeSheet> createState() => _TesterWelcomeSheetState();
}

class _TesterWelcomeSheetState extends State<TesterWelcomeSheet> {
  static const _count = 3;

  final _pages = PageController();
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  int _page = 0;

  /* --- 3쪽: 내 친구 코드 ---
     쪽(PageView 의 자식)은 넘기면 버려지므로 코드 · 입력 · 결과는 시트가 쥡니다 —
     2쪽에 갔다 오면 넣던 코드가 사라지면 안 됩니다. */
  Api? _api;
  String? _code;
  bool _codeBusy = false;
  bool _codeFailed = false;
  /// 코드를 받아 온 로그인(토큰). 다른 계정으로 들어오면 새로 받습니다.
  String? _codeFor;

  final _input = TextEditingController();
  bool _sending = false;
  String? _result;
  bool _resultOk = false;

  @override
  void initState() {
    super.initState();
    _live = this;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    /* 로그인은 Api 가 알립니다(Scope 는 앱 상태만 알림). 서버를 옮기면 Api 가 새것이
       되므로 그때마다 듣는 곳을 옮깁니다. */
    final api = Scope.apiOf(context);
    if (!identical(api, _api)) {
      _api?.removeListener(_onApi);
      _api = api..addListener(_onApi);
      _syncCode();
    }
  }

  @override
  void dispose() {
    if (identical(_live, this)) _live = null;
    _api?.removeListener(_onApi);
    _pages.dispose();
    _input.dispose();
    super.dispose();
  }

  void _onApi() {
    if (mounted) setState(_syncCode);
  }

  /* 로그인돼 있고 이 계정의 코드를 아직 안 받았으면 받습니다. 로그아웃이면 비웁니다.
     필드만 바꾸고 다시 그리기는 부른 쪽이 합니다(didChangeDependencies · setState). */
  void _syncCode() {
    final api = _api;
    if (api == null) return;
    if (!api.signedIn) {
      _code = null;
      _codeFor = null;
      _codeBusy = false;
      _codeFailed = false;
      return;
    }
    if (_codeFor == api.token && (_code != null || _codeBusy)) return;
    unawaited(_loadCode(api));
  }

  /* 코드는 /me 의 user.inviteCode — 친구 탭이 「초대 코드」 줄에 쓰는 그 값입니다. */
  Future<void> _loadCode(Api api) async {
    final token = api.token;
    _codeFor = token;
    _codeBusy = true;
    _codeFailed = false;
    final r = await api.me();
    /* 기다리는 사이 로그아웃했거나 다른 계정이 됐으면 이 답은 버립니다. */
    if (!mounted || !identical(api, _api) || api.token != token) return;
    final u = r.body['user'];
    final code = u is Map ? u['inviteCode'] : r.body['inviteCode'];
    setState(() {
      _codeBusy = false;
      _code = r.ok && code is String && code.trim().isNotEmpty ? code.trim() : null;
      /* 못 받으면 조용히 「다시」 하나 — 오류 문구로 인사를 망치지 않습니다. */
      _codeFailed = _code == null;
    });
  }

  void _retryCode() {
    final api = _api;
    if (api == null || !api.signedIn) return;
    unawaited(_loadCode(api));
    setState(() {});   // 「다시」 자리에 곧바로 도는 표시
  }

  void _snack(String message) {
    _messenger.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ));
  }

  Future<void> _copy() async {
    final code = _code;
    if (code == null) return;
    await Clipboard.setData(ClipboardData(text: code));
    if (mounted) _snack('복사했어요');
  }

  Future<void> _share(BuildContext button) async {
    final code = _code;
    if (code == null) return;
    /* 참여 주소는 새 판 확인기가 마지막으로 받은 /api/version 에서. 아직 못 받았으면
       코드만 나갑니다 — 공유를 서버 답에 묶어 기다리게 하지 않습니다. */
    final join = Scope.updateOf(context)?.info?.join ?? const JoinLinks();
    final text = inviteShareText(code, join);
    final box = button.findRenderObject();
    final origin =
        box is RenderBox && box.hasSize ? box.localToGlobal(Offset.zero) & box.size : null;
    try {
      await testerWelcomeShare(text, origin);
    } catch (_) {
      /* 공유 시트가 없는 기기 · 실패 — 글을 복사해 두면 붙여 넣기로 이어집니다. */
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) _snack('보낼 글을 복사했어요 — 붙여 넣어 보내 주세요');
    }
  }

  Future<void> _request() async {
    final api = _api;
    if (api == null || _sending || _input.text.trim().isEmpty) return;
    setState(() {
      _sending = true;
      _result = null;
    });
    final r = await requestFriendByCode(api, _input.text);
    if (!mounted) return;
    setState(() {
      _sending = false;
      if (r == null) return;
      _resultOk = r.ok;
      _result = !r.ok
          ? r.reason
          : becameFriends(r)
              ? '친구가 됐어요 — 친구 탭에서 볼 수 있어요'
              : '요청을 보냈어요 — 친구가 수락하면 친구 탭에 떠요';
      if (r.ok) _input.clear();
    });
    /* 보냈으면 키보드를 내려 결과와 「시작하기」 가 보이게. 실패면 고쳐 넣을 수 있게 둡니다. */
    if (r != null && r.ok) dismissKeyboard();
  }

  /* 로그인 화면을 시트 **위에** 올립니다(설정의 「로그인」 과 같은 길). 로그인되면 닫고
     시트로 돌아오고, Api 가 알려서 그 자리에 코드가 뜹니다. */
  void _signIn() {
    dismissKeyboard();
    final nav = Navigator.of(context);
    final api = Scope.apiOf(context);
    final setServer = Scope.serverSetterOf(context);
    nav.push(MaterialPageRoute(
        builder: (_) => SignInScreen(api: api, onDone: () => nav.pop(), onServerChange: setServer)));
  }

  void _close() => Navigator.of(context).maybePop();

  void _next() {
    _pages.nextPage(duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final signedIn = _api?.signedIn ?? false;
    final last = _page == _count - 1;
    /* 키보드가 올라온 만큼 시트를 밀어 올립니다 — 모달 시트는 스스로 키보드를 피하지
       않습니다(설정 · 종목 고르기 시트와 같은 방식). 안쪽에서는 그 몫을 지워, 시트
       안의 Scaffold 가 한 번 더 빼지 않게 합니다. */
    final kb = MediaQuery.viewInsetsOf(context).bottom;
    final typing = kb > 0;

    return Padding(
      padding: EdgeInsets.only(bottom: kb),
      child: MediaQuery.removeViewInsets(
        context: context,
        removeBottom: true,
        child: FractionallySizedBox(
          heightFactor: 0.92,
          /* 스낵바를 시트 안에 — 앱의 스낵바는 시트 밑의 화면에 떠서 안 보입니다. */
          child: ScaffoldMessenger(
            key: _messenger,
            child: Scaffold(
              backgroundColor: Colors.transparent,
              body: Stack(children: [
                Column(children: [
                  _Header(showSkip: !last, onSkip: _close),
                  Expanded(
                    child: PageView(
                      controller: _pages,
                      onPageChanged: (i) {
                        dismissKeyboard();
                        setState(() => _page = i);
                      },
                      children: [
                        _page1(t),
                        _page2(t),
                        _page3(t, signedIn),
                      ],
                    ),
                  ),
                  /* 키보드가 떠 있는 동안은 점과 큰 단추를 접습니다 — 360 폭 폰에서
                     키보드를 빼고 남는 높이가 코드 칸 하나 겨우입니다. 키보드를
                     내리면(바깥 탭 · 요청 성공) 돌아옵니다. */
                  if (!typing) _bottom(last: last, signedIn: signedIn),
                ]),
                /* 폭죽은 시트가 뜰 때 한 번(2.8초) — 끝이 있어야 화면이 쉽니다.
                   입력은 안 막습니다(Confetti 안의 IgnorePointer). */
                const Positioned.fill(child: Confetti(count: 90)),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  /* 쪽 점과 큰 단추. 마지막 쪽에서 로그인 안 한 사람에게는 테두리 단추 — 주된 길은
     카드의 「로그인 · 가입」 이고, 끝내기는 한 발 물러서 있어야 어느 쪽이 먼저인지 보입니다. */
  Widget _bottom({required bool last, required bool signedIn}) {
    const tall = Size.fromHeight(52);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _Dots(count: _count, index: _page),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: last && !signedIn
                ? OutlinedButton(
                    key: const Key('welcome-primary'),
                    style: OutlinedButton.styleFrom(minimumSize: tall),
                    onPressed: _close,
                    child: const Text('나중에 하고 시작하기'),
                  )
                : FilledButton(
                    key: const Key('welcome-primary'),
                    style: FilledButton.styleFrom(minimumSize: tall),
                    onPressed: last ? _close : _next,
                    child: Text(last ? '시작하기' : '다음'),
                  ),
          ),
        ]),
      ),
    );
  }

  /* 쪽마다 스크롤 — 360 폭 · 글자 1.3배에서도 넘치지 않게. 끌면 키보드가 내려갑니다. */
  Widget _scroll(List<Widget> children) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      );

  Widget _title(ThemeData t, String title, String sub) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(keepWords(title),
              textAlign: TextAlign.center,
              style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(keepWords(sub),
              textAlign: TextAlign.center,
              style: t.textTheme.bodyMedium?.copyWith(color: t.hintColor)),
          const SizedBox(height: 18),
        ],
      );

  Widget _page1(ThemeData t) => _scroll([
        const SizedBox(height: 8),
        Center(
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(color: t.colorScheme.primaryContainer, shape: BoxShape.circle),
            child: Icon(LucideIcons.partyPopper, size: 34, color: t.colorScheme.onPrimaryContainer),
          ),
        ),
        const SizedBox(height: 16),
        _title(t, welcomeTitle(),
            'Mybody 를 가장 먼저 써 보는 분이에요. 불편한 점은 뭐든 알려 주세요 — 바로 고칩니다.'),
        const _InfoRow(icon: LucideIcons.bell, text: '새 버전이 나오면 앱이 알려 드려요'),
        const _InfoRow(icon: LucideIcons.messageSquare, text: '의견은 화면 옆 말풍선으로 — 화면이 같이 붙어요'),
      ]);

  Widget _page2(ThemeData t) => _scroll([
        const SizedBox(height: 8),
        _title(t, '이렇게 써요', '네 가지면 끝이에요'),
        const _StepCard(icon: LucideIcons.camera, title: '인바디 결과지 찍기', line: '숫자는 앱이 읽어요'),
        const _StepCard(icon: LucideIcons.target, title: '목표 고르기', line: '주차별 운동·식단 플랜이 나와요'),
        const _StepCard(
            icon: LucideIcons.calendarCheck, title: '매일 기록', line: '헬스·유산소·식단, 누르기만 하면 돼요'),
        const _StepCard(icon: LucideIcons.trendingUp, title: '변화 보기', line: '체지방·골격근이 그래프로'),
      ]);

  Widget _page3(ThemeData t, bool signedIn) {
    final hint = t.textTheme.bodySmall?.copyWith(color: t.hintColor);
    return _scroll([
      const SizedBox(height: 8),
      _title(t, '친구랑 같이 해요', '오늘 한 운동을 서로 보고, 안 한 친구는 콕 찔러요'),
      if (!signedIn)
        MbCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('로그인하면 내 친구 코드가 생겨요',
                style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text('기록은 이 폰에 그대로 있어요', style: hint),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const Key('welcome-signin'),
              onPressed: _signIn,
              icon: const Icon(LucideIcons.logIn, size: 18),
              label: const Text('로그인 · 가입'),
            ),
          ]),
        )
      else ...[
        MbCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('내 친구 코드', style: t.textTheme.labelMedium?.copyWith(color: t.hintColor)),
            const SizedBox(height: 4),
            Row(children: [
              Expanded(child: _codeView(t)),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                key: const Key('welcome-copy'),
                onPressed: _code == null ? null : _copy,
                icon: const Icon(LucideIcons.copy, size: 16),
                label: const Text('복사'),
              ),
            ]),
            const SizedBox(height: 10),
            Builder(
              builder: (button) => FilledButton.tonalIcon(
                key: const Key('welcome-share'),
                onPressed: _code == null ? null : () => _share(button),
                icon: const Icon(LucideIcons.share2, size: 18),
                label: const Text('카톡 등으로 보내기'),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 6),
        Text('친구 코드가 있나요?',
            style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: TextField(
              key: const Key('welcome-code-input'),
              controller: _input,
              /* 코드(ABCD2345)는 낱말이 아닙니다 — 자동 교정 · 추천이 켜져 있으면
                 키보드가 멋대로 고쳐 보냅니다. 완료 키는 곧 「요청」. 친구 탭의
                 「친구 추가」 칸과 같습니다. */
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: TextCapitalization.characters,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _request(),
              /* 칸이 키보드 바로 위에 붙으면 결과 줄이 가려집니다 — 조금 더 올립니다. */
              scrollPadding: const EdgeInsets.fromLTRB(20, 20, 20, 64),
              decoration: const InputDecoration(
                hintText: '친구 코드',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          ListenableBuilder(
            listenable: _input,
            builder: (_, __) => FilledButton(
              key: const Key('welcome-request'),
              style: FilledButton.styleFrom(minimumSize: const Size(64, 48)),
              onPressed: _sending || _input.text.trim().isEmpty ? null : _request,
              child: _sending
                  ? const SizedBox(
                      width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('요청'),
            ),
          ),
        ]),
        if (_result != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _result!,
              key: const Key('welcome-result'),
              style: t.textTheme.bodySmall?.copyWith(
                  color: _resultOk ? mb(context).ok : t.colorScheme.error,
                  fontWeight: FontWeight.w600),
            ),
          ),
        const SizedBox(height: 8),
        Text('받은 요청은 친구 탭에서 수락해요', style: hint),
      ],
    ]);
  }

  Widget _codeView(ThemeData t) {
    final code = _code;
    if (code != null) {
      /* 크게 · 자간을 벌려 — 소리 내어 불러 주거나 보고 옮겨 적을 수 있게. 긴 코드나
         큰 글씨에서도 한 줄에 들어가도록 줄여 맞춥니다. */
      return FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(code,
            key: const Key('welcome-code'),
            style: t.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: 3,
                fontFeatures: const [FontFeature.tabularFigures()])),
      );
    }
    if (_codeFailed) {
      return Row(children: [
        Flexible(child: Text('못 불러왔어요', style: t.textTheme.bodySmall?.copyWith(color: t.hintColor))),
        TextButton(key: const Key('welcome-code-retry'), onPressed: _retryCode, child: const Text('다시')),
      ]);
    }
    return const Align(
      alignment: Alignment.centerLeft,
      child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
    );
  }
}

/// 손잡이와 「건너뛰기」 한 줄. 마지막 쪽에서는 「건너뛰기」 를 숨기되 자리는 둡니다 —
/// 쪽을 넘길 때 아래 내용이 들썩이지 않게. 거기서는 「시작하기」 가 같은 일을 합니다.
class _Header extends StatelessWidget {
  const _Header({required this.showSkip, required this.onSkip});
  final bool showSkip;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return SizedBox(
      height: 48,
      child: Stack(children: [
        Align(
          alignment: Alignment.topCenter,
          child: Container(
            margin: const EdgeInsets.only(top: 10),
            width: 32,
            height: 4,
            decoration: BoxDecoration(
              color: t.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Visibility(
              visible: showSkip,
              maintainSize: true,
              maintainAnimation: true,
              maintainState: true,
              child: TextButton(
                key: const Key('welcome-skip'),
                onPressed: onSkip,
                style: TextButton.styleFrom(foregroundColor: t.hintColor),
                child: const Text('건너뛰기'),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

/// 쪽 점 — 지금 쪽은 길게.
class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.index});
  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: '${index + 1} / $count 쪽',
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == index ? 18 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: i == index ? scheme.primary : scheme.outlineVariant,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
      ]),
    );
  }
}

/// 1쪽의 안내 줄 — 아이콘 하나, 글 한 줄.
class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: mb(context).accentSub,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        Icon(icon, size: 20, color: t.colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(child: Text(keepWords(text), style: t.textTheme.bodyMedium)),
      ]),
    );
  }
}

/// 2쪽의 한 장 — 아이콘 · 굵은 제목 · 회색 한 줄.
class _StepCard extends StatelessWidget {
  const _StepCard({required this.icon, required this.title, required this.line});
  final IconData icon;
  final String title;
  final String line;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return MbCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: mb(context).accentSub,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 20, color: t.colorScheme.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            Text(line, style: t.textTheme.bodySmall?.copyWith(color: t.hintColor)),
          ]),
        ),
      ]),
    );
  }
}
