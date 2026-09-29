/* =============================================================================
 * shell.dart — 앱 셸: 탭 다섯 개와 앱바
 *
 * 탭이 다섯인 이유가 있습니다. 여섯 번째를 넣으면 안드로이드에서 탭바가
 * 두 줄로 접혀 높이가 두 배가 되고, iOS 는 5개를 넘기면 뒤쪽을 More 로
 * 숨깁니다. 그래서 설정은 탭이 아니라 앱바의 톱니입니다.
 *
 * **폰 뒤로가기는 여기서 공짜입니다.** 지금 쓰는 웹 앱에서는 popstate 를
 * 직접 엮어야 했고(그게 없어서 뒤로가기가 앱을 통째로 닫았습니다),
 * Flutter 의 Navigator 는 안드로이드 뒤로가기를 원래 받습니다.
 *
 * **의견 보내기는 앱바에 없습니다.** 앱바의 말풍선은 탭 화면에만 있어서 밀어 올린
 * 화면 · 로그인 · 첫 설정에서는 못 눌렀습니다. 이제 앱 맨 위에 늘 떠 있는 말풍선이
 * 모든 화면에서 같은 일을 합니다(screens/feedback_bubble.dart) — 같은 일을 하는
 * 단추가 한 화면에 둘이면 어느 쪽이 진짜인지 묻게 되어 여기서는 뺐습니다. 앱바에는
 * 톱니 하나만 남습니다.
 *
 * **테스터 인사**(screens/tester_welcome.dart)는 탭 화면이 처음 **보일 때** 한 번
 * 띄웁니다 — 로그인 · 온보딩 화면 위에는 안 뜨고(거기선 탭이 안 서니까), 이미 쓰던
 * 사람도 업데이트 뒤 한 번 봅니다(주인이 정한 것). 셸이 다시 그려질 때마다 부르지
 * 않게 이 상태에 한 번 묻고, 다시 켠 뒤에는 settings 의 표가 막습니다. 옛 동의로
 * 로그인한 사람은 동의 화면이 탭보다 늦게 뜨므로, /me 로 먼저 보고 동의를 마친 뒤
 * 탭이 다시 설 때 띄웁니다 — 동의 화면을 인사가 덮지 않게.
 *
 * **초대 링크**(invite_link.dart)로 받은 코드도 여기서 보냅니다 — 보낼 수 있는 때를 셸만
 * 압니다: 탭 화면이 서 있고(로그인 · 첫 설정 · 동의 화면이 아님), 로그인돼 있을 때. 그때
 * 받은 코드를 **꺼내서 비우고** 한 번 보내고, 결과를 스낵바 한 줄로 알립니다. 링크 · 설치
 * referrer 로 온 코드는 **곧바로 친구**입니다(주인 의견 48 — via:'link', 「○○님과 친구가
 * 됐어요」 · 이미 친구면 「이미 ○○님과 친구예요」). 그 밖의 결과는 「친구 요청을 보냈어요」 ·
 * 「내 코드예요」 · 서버의 까닭입니다 — 서버에 못 닿았으면 보낸 것으로 치지 않아서, 같은 링크를
 * 다시 누르면 다시 갑니다. 로그인 없이 쓰는 중이면 코드는 쥔 채로 「로그인하면 바로 친구가
 * 돼요」(클립보드에서 고른 코드면 「로그인하면 친구 요청이 가요」)를 한 번 알리고 「로그인」 을
 * 붙입니다. 부르는 때는 셋 — 탭 화면이 설 때, 새 링크가 올 때, 로그인할 때. 테스터 인사가 뜨는
 * 차례면 인사가 닫힌 뒤에 보냅니다 — 결과 스낵바가 인사 시트 밑에 깔려 안 보이면 요청이 갔는지
 * 모릅니다. 친구가 됐거나 요청이 갔으면 친구 탭을 새로 그립니다(_socialEpoch) — 보고 있던
 * 친구 목록에 새 친구가 바로 뜨게.
 *
 * **클립보드의 초대**(안드로이드, 탭 화면이 처음 설 때 한 번 — invite_link.dart 머리 주석):
 * 앱이 없던 친구가 초대 페이지의 설치 단추를 누르면 초대 글이 클립보드에 남습니다. 보낼 것이
 * 없을 때 한 번 읽어 초대가 있으면 「초대 코드 <코드> 로 친구 요청할까요?」 를 묻고, 「요청」 을
 * 누르면 링크로 받은 것과 같은 길로 — 다만 **요청으로**(via 없이) 보냅니다. 이것만은 묻고, 곧바로
 * 친구로 맺지도 않습니다 — 클립보드는 남의 글일 수도 있습니다(설치 referrer 로 온 코드는 묻지
 * 않고 링크처럼 보냅니다).
 *
 * **누를 것이 있는 안내는 위의 띠(MaterialBanner)로.** 「로그인」 · 「요청」 을 스낵바에 달았더니,
 * 그때 의견 말풍선의 처음 자리(「인바디」 단추 바로 위)가 떠 있는 스낵바의 오른쪽 끝 — 바로 그
 * 단추 자리를 덮었습니다(스낵바는 「인바디」 단추 위에 뜹니다). 아래 여백으로 비키려니 단추가
 * 있는 홈과 없는 탭에서 스낵바 높이가 72px 달라, 한쪽에서 비키면 다른 쪽에서 덮습니다. 위의
 * 띠는 앱바 바로 밑이라 단추 · 탭바와 안 만나고, 세로 화면에서는 말풍선의 지금 처음 자리(오른쪽
 * 가장자리, 앱바 밑 ~ 탭바 위의 한가운데 — feedback_bubble.dart)보다도 위에서 끝납니다(360×640 ·
 * 글자 1.3배까지 invite_deferred_test 가 봅니다). 가로 창에서는 앱바와 탭바 사이가 200px 안팎이라
 * 띠가 말풍선 높이까지 내려올 수 있습니다 — 그래도 띠는 화면을 밀지 않고 얹히고(elevation),
 * 누르지 않으면 저절로 걷혀서 그대로 둡니다 — 쓰던 화면을 오래 가리지 않게. 탭 화면이
 * 내려가면(로그아웃 · 동의 화면) 같이 걷습니다. 결과 한 줄(누를 것 없음)은 그대로 스낵바입니다.
 * ========================================================================== */
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'api.dart' show Api, ApiResult;
import 'invite_link.dart';
import 'nudge.dart' show notificationRoute, tappedMealReminder, parseWorkoutPayload;
import 'scope.dart';
import 'ui/symbols.dart';
import 'screens/food.dart';
import 'screens/home.dart';
import 'screens/plan.dart';
import 'screens/progress.dart';
import 'screens/settings.dart';
import 'screens/social.dart';
import 'screens/upload.dart';
import 'screens/goal.dart';
import 'screens/history.dart';
import 'screens/account.dart';
import 'screens/checkin.dart';
import 'screens/feedback_inbox.dart';
import 'screens/onboarding.dart';
import 'screens/scandetail.dart';
import 'screens/tester_welcome.dart';
import 'screens/workout_session.dart';

class Shell extends StatefulWidget {
  const Shell({super.key, this.invites});

  /// 초대 링크 받는 곳(main.dart 가 만듭니다). 없으면 링크로 온 요청을 안 봅니다.
  final InviteInbox? invites;

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _tab = 0;

  /// 이 셸에서 테스터 인사를 이미 물었나. 셸은 로그인 · 동의 · 앱 상태가 바뀔 때마다
  /// 다시 그려지고 탭 화면이 새로 서기도 합니다 — 그때마다 묻지 않게.
  bool _welcomeAsked = false;

  /// 탭 화면([_Shown])이 지금 몇 개 붙어 있나. 동의 게이트가 탭 대신 동의 화면을
  /// 세우면 0 이 됩니다 — 인사를 띄우기 직전에 이것을 봅니다.
  int _tabsUp = 0;

  /// 테스터 인사를 묻는 중이거나 떠 있는 동안 — 초대 링크의 결과는 그 뒤에 알립니다.
  bool _welcomeBusy = false;

  /// 초대 링크로 받은 요청을 보내는 중인가.
  bool _inviteBusy = false;

  /// 이 셸에서 클립보드의 초대를 이미 물었나(이 기기에서 한 번인지는 InviteInbox 가 적습니다).
  bool _clipboardAsked = false;

  /* 지금 떠 있는 위의 띠(누를 것이 있는 안내)와 그것을 띄운 곳 · 저절로 걷는 시계. */
  ScaffoldFeatureController<MaterialBanner, MaterialBannerClosedReason>? _prompt;
  ScaffoldMessengerState? _promptMessenger;
  Timer? _promptTimer;

  /// 로그인 · 로그아웃을 듣는 Api — 서버를 옮기면 새것이 됩니다.
  Api? _api;

  /// 친구 탭을 새로 세우는 번호 — 초대 링크로 요청이 가면 목록을 다시 받게.
  int _socialEpoch = 0;

  /* 알림을 누르면 그 알림이 가리키는 곳으로(끼니 · 간식 알림은 식단 탭).
     알림으로 앱이 새로 켜졌으면 셸이 뜨기 전에 값이 와 있을 수 있어 처음에도 봅니다. */
  @override
  void initState() {
    super.initState();
    notificationRoute.addListener(_onRoute);
    widget.invites?.addListener(_onInvite);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onRoute());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final api = Scope.apiOf(context);
    if (!identical(api, _api)) {
      _api?.removeListener(_onInvite);
      _api?.removeListener(_onAccount);
      _seenToken = api.token;
      _api = api
        ..addListener(_onInvite)
        ..addListener(_onAccount);
    }
  }

  /* 계정이 바뀌면 기록 칸도 바뀝니다(local_owner.dart) — 새 계정의 빈 칸에는 테스터 인사를 다시
     묻습니다. 본 적이 있는 칸(같은 계정으로 돌아옴)이면 showTesterWelcome 이 그냥 돌아옵니다. */
  String? _seenToken;
  void _onAccount() {
    final t = _api?.token;
    if (t == _seenToken) return;
    _seenToken = t;
    _welcomeAsked = false;
  }

  @override
  void didUpdateWidget(Shell old) {
    super.didUpdateWidget(old);
    if (!identical(old.invites, widget.invites)) {
      old.invites?.removeListener(_onInvite);
      widget.invites?.addListener(_onInvite);
      _onInvite();
    }
  }

  @override
  void dispose() {
    notificationRoute.removeListener(_onRoute);
    widget.invites?.removeListener(_onInvite);
    _api?.removeListener(_onInvite);
    _api?.removeListener(_onAccount);
    _closePrompt(later: true);
    super.dispose();
  }

  void _onRoute() {
    final r = notificationRoute.value;
    if (r == null || !mounted) return;
    notificationRoute.value = null;
    /* 저녁 운동 알림('workout:bodyweight:날짜')은 그 날의 맨몸 운동 화면으로 — 홈 위에 띄워서
       저장하고 나오면 홈의 브리핑이 바로 바뀝니다. */
    final w = parseWorkoutPayload(r);
    if (w != null) {
      Navigator.of(context).popUntil((route) => route.isFirst);
      _go('home');
      _go('workout', (dateKey: w.dateKey, type: w.type));
      return;
    }
    if (r == 'food' || r.startsWith('food:')) {
      /* 끼니 알림이면 그 끼니를 식단 화면의 기본값으로(10시 5분에 적어도 아침). */
      if (r.startsWith('food:')) tappedMealReminder = (meal: r.substring(5), at: DateTime.now());
      /* 설정 · 음식 찾기 같은 화면이 위에 떠 있으면 탭을 바꿔도 안 보입니다. */
      Navigator.of(context).popUntil((route) => route.isFirst);
      _go('food');
    }
    /* 친구 알림(앱 알림의 data.route — 독촉 · 운동 소식 · 친구 요청)은 친구 탭으로.
       독촉은 그 탭 맨 위의 띠에 있습니다. */
    if (r == 'social' || r == 'pokes') {
      Navigator.of(context).popUntil((route) => route.isFirst);
      _go('social');
    }
    /* 「새 의견이 왔어요」(운영자 한 사람에게만 가는 앱 알림)는 의견함으로 — 위에 뜬 화면은
       닫고 셸 위에 엽니다. 로그인하지 않았으면 아무것도 안 합니다: 로그아웃하면 서버가 이
       기기를 알림 받는 곳에서 빼므로, 늦게 온 한 통입니다. 로그인한 사람이 운영자가 아니면
       의견함이 서버의 403 을 받아 「운영자 계정으로 로그인하면 볼 수 있어요」 만 보입니다.
       로그인 여부는 **닫기 전에** 봅니다 — 열 것도 없는데 보던 화면(쓰던 기록 등)만 닫히면 안 됩니다. */
    if (r == 'feedback') {
      if (!Scope.apiOf(context).signedIn) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
      _go('feedback');
    }
  }

  static const _tabs = [
    (icon: LucideIcons.home, on: LucideIcons.home, label: '홈'),
    (icon: LucideIcons.utensils, on: LucideIcons.utensils, label: '식단'),
    (icon: LucideIcons.clipboardList, on: LucideIcons.clipboardList, label: '플랜'),
    (icon: LucideIcons.trendingUp, on: LucideIcons.trendingUp, label: '추이'),
    (icon: LucideIcons.users, on: LucideIcons.users, label: '친구'),
  ];

  void _go(String route, [Object? arg]) {
    switch (route) {
      case 'home':
        setState(() => _tab = 0);
      case 'food':
        setState(() => _tab = 1);
      case 'plan':
        setState(() => _tab = 2);
      case 'progress':
        setState(() => _tab = 3);
      case 'social':
        setState(() => _tab = 4);
      case 'upload':
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const UploadScreen()));
      case 'goal':
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GoalScreen()));
      case 'history':
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HistoryScreen()));
      case 'scan':
        Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => ScanDetailScreen(scanId: arg)));
      case 'checkin':
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CheckinScreen()));
      /* 운동 기록 화면 — 홈 브리핑 · 이번 주 카드 · 알림이 같은 길로 옵니다.
         arg 는 (dateKey, type) 레코드이거나 {'date','type'} 맵(브리핑이 쓰는 꼴). */
      case 'workout':
        final (dateKey, type) = _workoutArg(arg);
        Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => WorkoutSessionScreen(dateKey: dateKey, type: type)));
      case 'settings':
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
      /* 의견함(운영자) — 알림 · 설정 → 도움말의 줄이 여는 곳. */
      case 'feedback':
        if (!Scope.apiOf(context).signedIn) return;
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FeedbackInboxScreen()));
      case 'signin':
        Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => SignInScreen(
                  api: Scope.apiOf(context),
                  onDone: () {
                    Navigator.of(context).pop();
                    setState(() {});
                  },
                  onServerChange: Scope.serverSetterOf(context),
                )));
      case 'server':
        Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => ServerScreen(onSet: (u) async {
                  await Scope.serverSetterOf(context)(u);
                  if (mounted) Navigator.of(context).pop();
                })));
      case 'account':
        Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => AccountScreen(
                  api: Scope.apiOf(context),
                  onServerChange: Scope.serverSetterOf(context),
                )));
    }
  }

  /* 탭 화면이 처음 선 뒤(그린 다음 프레임)에 한 번. 본 적이 있으면 showTesterWelcome 이
     그냥 돌아옵니다 — 본 것으로 적는 것도, 두 장이 겹치지 않게 막는 것도 그쪽 일입니다.
     위에 다른 화면(알림을 눌러 열린 운동 화면 등)이 떠 있어도 그 위에 띄웁니다 —
     한 번뿐이고, 닫으면 그 화면 그대로입니다. */
  void _tabsShown() {
    _tabsUp++;
    if (_welcomeAsked) {
      _onInvite();
      return;
    }
    _welcomeAsked = true;
    _welcomeBusy = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_welcome()));
  }

  /* 탭 화면이 내려가면(로그아웃 · 동의 화면) 위의 띠도 걷습니다 — 로그인 화면 위에 「로그인하면
     친구 요청이 가요」 가 남으면 이상합니다. 떨어지는 중(dispose)이라 다음 틈에 걷습니다. */
  void _tabsGone() {
    _tabsUp--;
    if (_tabsUp <= 0) _closePrompt(later: true);
  }

  /* **동의 화면 위에는 안 띄웁니다.** 동의 게이트는 /me 를 받기 전까지 탭을 세워 두었다가
     옛 동의면 그제야 동의 화면으로 바꿉니다 — 그 사이에 띄우면 인사가 동의 화면을 덮고,
     닫으면 갑자기 다른 화면이 나옵니다. 그래서 로그인했으면 같은 /me 를 먼저 봅니다
     (아직 안 봤을 때만 — 본 사람은 켤 때마다 묻지 않습니다). 서버가 늦으면 4초만
     기다립니다 — 게이트도 서버가 안 닿으면 막지 않고, 20초 뒤에 불쑥 뜨는 인사는
     쓰던 손을 가로챕니다. 옛 동의였거나 그사이 탭 화면이 내려갔으면(로그아웃 · 동의
     화면) 물은 것을 되돌려, 탭 화면이 다시 설 때 묻습니다. */
  Future<void> _welcome() async {
    /* 인사를 다시 물어야 하면(옛 동의 · 탭이 내려감) 초대 링크도 그때까지 기다립니다 —
       탭이 다시 서면 인사부터 다시 묻고, 그 뒤에 보냅니다. */
    var again = false;
    try {
      if (!mounted || testerWelcomeSeen(Scope.of(context).state)) return;
      final api = Scope.apiOf(context);
      if (api.signedIn) {
        final r = await api.me().timeout(const Duration(seconds: 4),
            onTimeout: () => const ApiResult(0, {}));
        if (!mounted) return;
        final u = r.body['user'];
        if (r.ok && u is Map && needsReconsent(u)) {
          again = true;
          _welcomeAsked = false;
          return;
        }
      }
      if (_tabsUp <= 0) {
        again = true;
        _welcomeAsked = false;
        return;
      }
      /* 닫힐 때까지 기다립니다 — 초대 링크의 결과를 인사 시트 밑에 깔지 않게. */
      await showTesterWelcome(context);
    } finally {
      if (!again) {
        _welcomeBusy = false;
        if (mounted) _onInvite();
      }
    }
  }

  /* --- 초대 링크 -------------------------------------------------------------
     알림(링크가 옴 · 로그인 · 탭이 섬)은 빌드 도중일 수 있어 다음 프레임에 봅니다. 프레임이
     예정돼 있지 않을 수 있으니(링크는 화면이 가만히 있을 때도 옵니다) 하나 청합니다. */
  void _onInvite() {
    if (!mounted || widget.invites == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_deliverInvite()));
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _deliverInvite() async {
    final inbox = widget.invites;
    if (!mounted || inbox == null || _inviteBusy || _welcomeBusy || _tabsUp <= 0) return;
    final p = inbox.pending;
    if (p == null) {
      /* 보낼 것이 없으면 — 탭 화면이 처음 섰을 때 한 번, 클립보드의 초대를 봅니다. */
      unawaited(_askClipboard());
      return;
    }
    final api = Scope.apiOf(context);
    if (!api.signedIn) {
      /* 로그인 없이 쓰는 중 — 코드는 쥔 채로, 안내는 한 번만. */
      if (p.prompted) return;
      inbox.markPrompted();
      _invitePrompt(p.link ? '로그인하면 바로 친구가 돼요' : '로그인하면 친구 요청이 가요',
          action: '로그인', dismiss: '닫기', onAction: () => _go('signin'));
      return;
    }
    final taken = inbox.takeInvite();
    if (taken == null) return;
    final code = taken.code;
    _inviteBusy = true;
    try {
      /* 링크 · 설치 referrer 로 온 코드면 곧바로 친구(via:'link'), 클립보드에서 고른 것은 요청. */
      final r = await requestFriendByCode(api, code, viaLink: taken.link);
      /* 서버에 못 닿았으면(0 · 5xx) 보낸 것으로 치지 않습니다 — 같은 링크를 다시 누르면 앱이
         꺼져 있다 켜지는 길이어도 다시 갑니다(invite_link.dart 「되살아난 링크」). */
      if (r == null || r.status == 0 || r.status >= 500) inbox.unsent(code);
      if (!mounted || r == null) return;
      _inviteSnack(friendRequestMessage(r));
      if (r.ok) setState(() => _socialEpoch++);
    } finally {
      _inviteBusy = false;
    }
    /* 보내는 사이 또 다른 링크가 왔으면 이어서. 아니면 클립보드를 한 번 봅니다 — referrer ·
       링크로 받은 그 코드가 클립보드에도 있을 테니 대개 묻지 않고 끝나지만(InviteInbox 가
       거릅니다), 읽는 한 번을 여기서 써 두어 다음에 켤 때 괜히 읽지 않게. */
    if (!mounted) return;
    if (inbox.pending != null) {
      _onInvite();
    } else {
      unawaited(_askClipboard());
    }
  }

  /* 클립보드의 초대(머리 주석) — 이 셸에서 한 번 묻고, 이 기기에서 한 번인지는 InviteInbox 가
     적습니다(아이폰은 읽지 않고 null). 읽는 사이 탭 화면이 내려갔으면 묻지 않습니다. 「요청」 을
     누르면 링크로 받은 것처럼 쥐고(offer — 다만 요청으로, 곧바로 친구는 아님) — 쥐면 알림이 와서
     위의 _deliverInvite 가 보냅니다(로그인 없이 쓰는 중이면 「로그인하면 친구 요청이 가요」). */
  Future<void> _askClipboard() async {
    final inbox = widget.invites;
    if (_clipboardAsked || inbox == null) return;
    _clipboardAsked = true;
    final code = await inbox.clipboardInviteOnce();
    if (code == null || !mounted || _tabsUp <= 0 || inbox.pending != null) return;
    _invitePrompt('초대 코드 $code 로 친구 요청할까요?',
        action: '요청',
        dismiss: '괜찮아요',
        stay: const Duration(seconds: 15),
        onAction: () => unawaited(inbox.offer(code)));
  }

  /* 결과 한 줄 — 누를 것이 없는 스낵바. */
  void _inviteSnack(String message) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ));
  }

  /* 누를 것이 있는 안내 — 앱바 밑의 띠(머리 주석). [stay] 가 지나도록 안 누르면 저절로 걷힙니다
     — 쓰던 화면을 계속 가리지 않게. 새 띠는 옛 띠를 바로 치우고 뜹니다(두 장이 줄 서지 않게). */
  void _invitePrompt(String message,
      {required String action,
      required String dismiss,
      required VoidCallback onAction,
      Duration stay = const Duration(seconds: 6)}) {
    final m = ScaffoldMessenger.maybeOf(context);
    if (m == null) return;
    _promptTimer?.cancel();
    if (_prompt != null) _promptMessenger?.removeCurrentMaterialBanner();
    final t = Theme.of(context);
    final c = m.showMaterialBanner(MaterialBanner(
      key: const Key('invite-prompt'),
      content: Text(message),
      leading: Icon(LucideIcons.userPlus, color: t.colorScheme.primary),
      /* 얹히게 — 0 이면 탭 화면의 내용이 띠 높이만큼 내려갔다가 걷힐 때 도로 올라옵니다. */
      elevation: 2,
      actions: [
        TextButton(
            key: const Key('invite-prompt-dismiss'), onPressed: _closePrompt, child: Text(dismiss)),
        TextButton(
          key: const Key('invite-prompt-action'),
          onPressed: () {
            _closePrompt();
            onAction();
          },
          child: Text(action),
        ),
      ],
    ));
    _prompt = c;
    _promptMessenger = m;
    _promptTimer = Timer(stay, _closePrompt);
    unawaited(c.closed.then((_) {
      if (!identical(_prompt, c)) return;
      _prompt = null;
      _promptTimer?.cancel();
      _promptTimer = null;
    }));
  }

  /* 띠를 걷습니다(떠 있을 때만 — 앱의 다른 띠는 없지만 남의 것을 걷지 않게). [later] 는 화면이
     떨어지는 중(dispose)일 때 — 그 틈에는 위(ScaffoldMessenger)를 고칠 수 없어 다음 틈에. */
  void _closePrompt({bool later = false}) {
    _promptTimer?.cancel();
    _promptTimer = null;
    final c = _prompt, m = _promptMessenger;
    if (c == null || m == null) return;
    _prompt = null;
    void close() {
      if (m.mounted) m.hideCurrentMaterialBanner();
    }

    later ? scheduleMicrotask(close) : close();
  }

  (String, String) _workoutArg(Object? arg) {
    if (arg is ({String dateKey, String type})) return (arg.dateKey, arg.type);
    if (arg is Map) {
      final d = arg['date'] ?? arg['dateKey'];
      final t = arg['type'];
      return ('${d ?? Scope.of(context).store.dayKey()}', '${t ?? 'gym'}');
    }
    return (Scope.of(context).store.dayKey(), 'gym');
  }

  @override
  Widget build(BuildContext context) {
    final api = Scope.apiOf(context);
    final app = Scope.of(context);
    /* **계정을 먼저 권하되, 막지는 않습니다.** 사진 판독과 친구는 계정으로
       되는 일입니다(서버가 판독 횟수를 사람마다 셉니다). 그래서 첫 화면은
       로그인/가입입니다. 토큰이 생기면 api 가 알리고 여기가 다시 그려져
       온보딩으로 넘어갑니다. 서버가 안 닿으면 같은 화면에서 주소를 고칩니다.

       그런데 숫자 세 개로 기록하고 계획을 세우는 일은 계정이 필요 없습니다.
       그걸 가입 뒤에 가두면 애플 심사 5.1.1(v) — "계정 기반 기능이 아니면
       로그인 없이 쓰게 하라" — 에 걸립니다. 그래서 「로그인 없이 쓰기」가
       있고, 고르면 `guest` 가 남아 다음부터는 이 화면을 건너뜁니다.
       기록은 기기에만 있고, 판독·친구는 그 자리에서 로그인을 안내합니다. */
    return ListenableBuilder(
      listenable: api,
      builder: (context, _) {
        if (!api.signedIn && app.state['guest'] != true) {
          return SignInScreen(
            api: api,
            onDone: () {},   // 토큰이 생기는 순간 위에서 다시 그립니다
            onServerChange: Scope.serverSetterOf(context),
            intro: '처음이면 「처음이에요」로 가입하세요 — 사진 판독 · 친구 · 기기 옮기기는 계정으로 됩니다',
            onSkip: () => app.store.set({'guest': true}),
          );
        }
        if (!api.signedIn) return _shell(context);   // 로그인 없이 쓰기
        /* 옛 판으로 동의한 계정이면 새 문구로 한 번 다시 묻습니다. 토큰을
           열쇠로 둡니다 — 다른 계정으로 들어오면 그 계정 것을 새로 봅니다.
           동의하지 않으면 로그아웃하고 「로그인 없이 쓰기」로 갑니다 — 이 계정의
           기록은 이 기기에 따로 보관되고(local_owner.dart), 「로그인 없이 쓰기」 표시는
           로그아웃이 다음 칸에 세웁니다. 여기서 기록을 저장(store.set)하면 로그인이
           살아 있는 채 주간 요약 · 못 보낸 사본이 나갑니다(2차 검토). */
        return ConsentGate(
          key: ValueKey(api.token),
          api: api,
          child: _shell(context),
        );
      },
    );
  }

  Widget _shell(BuildContext context) {
    /* **프로필이 없으면 먼저 받습니다.**
       없으면 코어가 씨앗 프로필(주인의 몸: 187cm · 22세)로 계산합니다.
       숫자는 그럴듯하게 나오고, 틀렸다는 표시는 어디에도 없습니다. */
    if (!Scope.of(context).onboarded) return const OnboardingScreen();

    final body = switch (_tab) {
      0 => HomeScreen(go: _go),
      1 => FoodScreen(go: _go),
      2 => PlanScreen(go: _go),
      3 => ProgressScreen(go: _go),
      _ => SocialScreen(key: ValueKey(_socialEpoch), go: _go),
    };

    /* **다른 탭에서 뒤로 가기는 홈입니다.** 폰의 뒤로 가기가 식단 탭에서
       앱을 통째로 닫았습니다 — 셸은 화면 하나라 Navigator 에 뺄 것이 없어서.
       홈에서만 앱이 닫힙니다.
       _Shown 은 탭 화면이 **실제로 섰을 때** 테스터 인사를 부릅니다. 여기(빌드)서
       바로 부르지 않는 까닭: 동의 게이트는 child 를 만들어 두고도 옛 동의면 대신
       동의 화면을 세웁니다 — 만들어진 것과 보이는 것이 다릅니다. */
    return _Shown(
      onShown: _tabsShown,
      onGone: _tabsGone,
      child: PopScope(
      canPop: _tab == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _tab = 0);
      },
      child: Scaffold(
      appBar: AppBar(
        title: Text(_tabs[_tab].label),
        actions: [
          /* 의견 보내기는 화면 옆 말풍선으로 옮겼습니다(머리 주석). */
          IconButton(
            tooltip: '설정',
            icon: const Icon(LucideIcons.settings),
            onPressed: () => _go('settings'),
          ),
        ],
      ),
      body: SafeArea(child: body),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          for (final t in _tabs)
            NavigationDestination(
                icon: Icon(t.icon), selectedIcon: Icon(t.on), label: t.label),
        ],
      ),
      /* 측정이 하나도 없을 때는 안 답니다 — 빈 화면에 이미 "인바디 올리기"
         버튼이 있고, 같은 일을 하는 버튼이 한 화면에 둘이면 어느 쪽이
         진짜인지 묻게 됩니다. */
      floatingActionButton: (_tab == 0 && Scope.of(context).store.sortedScans().isNotEmpty)
          ? FloatingActionButton.extended(
              onPressed: () => _go('upload'),
              icon: const Icon(LucideIcons.imagePlus),
              label: const Text('인바디'),
            )
          : null,
    )));
  }
}

/// 처음 붙을 때 [onShown], 떨어질 때 [onGone] 을 한 번씩 부릅니다. 셸의 빌드 안에서
/// 부르면 "만들어졌다" 이지 "보인다" 가 아닙니다 — 동의 게이트가 만들어 둔 탭 대신
/// 동의 화면을 세우면 여기가 떨어집니다.
class _Shown extends StatefulWidget {
  const _Shown({required this.onShown, required this.onGone, required this.child});
  final VoidCallback onShown;
  final VoidCallback onGone;
  final Widget child;

  @override
  State<_Shown> createState() => _ShownState();
}

class _ShownState extends State<_Shown> {
  @override
  void initState() {
    super.initState();
    widget.onShown();
  }

  @override
  void dispose() {
    widget.onGone();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// 화면들이 같이 쓰는 "로그인이 필요합니다" 안내.
class NeedsSignIn extends StatelessWidget {
  const NeedsSignIn({super.key, required this.what, this.go});
  final String what;
  final void Function(String route, [Object? arg])? go;

  @override
  Widget build(BuildContext context) {
    final api = Scope.apiOf(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          /* "친구은 로그인해야" 를 실제로 띄웠습니다 — 받침을 보고 붙입니다. */
          Text('${josa(what, '은', '는')} 로그인해야 쓸 수 있습니다',
              textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          Text(
            api.baseUrl.isEmpty
                ? '먼저 서버 주소를 넣어야 합니다 — 설정에서 넣을 수 있습니다.'
                : '로그인하면 기록이 내 계정에 저장돼, 기기를 바꿔도 그대로 따라옵니다.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: Theme.of(context).hintColor, height: 1.5),
          ),
          if (go != null) ...[
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => go!(api.baseUrl.isEmpty ? 'server' : 'signin'),
              child: Text(api.baseUrl.isEmpty ? '서버 주소 넣기' : '로그인'),
            ),
          ],
        ]),
      ),
    );
  }
}
