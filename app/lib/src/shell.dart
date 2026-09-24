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
 * ========================================================================== */
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

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
import 'screens/onboarding.dart';
import 'screens/scandetail.dart';
import 'screens/workout_session.dart';

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _tab = 0;

  /* 알림을 누르면 그 알림이 가리키는 곳으로(끼니 · 간식 알림은 식단 탭).
     알림으로 앱이 새로 켜졌으면 셸이 뜨기 전에 값이 와 있을 수 있어 처음에도 봅니다. */
  @override
  void initState() {
    super.initState();
    notificationRoute.addListener(_onRoute);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onRoute());
  }

  @override
  void dispose() {
    notificationRoute.removeListener(_onRoute);
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
           동의하지 않으면 로그아웃하고 「로그인 없이 쓰기」로 이어 갑니다 —
           기기의 기록은 그대로입니다. */
        return ConsentGate(
          key: ValueKey(api.token),
          api: api,
          onDecline: () => app.store.set({'guest': true}),
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
      _ => SocialScreen(go: _go),
    };

    /* **다른 탭에서 뒤로 가기는 홈입니다.** 폰의 뒤로 가기가 식단 탭에서
       앱을 통째로 닫았습니다 — 셸은 화면 하나라 Navigator 에 뺄 것이 없어서.
       홈에서만 앱이 닫힙니다. */
    return PopScope(
      canPop: _tab == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _tab = 0);
      },
      child: Scaffold(
      appBar: AppBar(
        title: Text(_tabs[_tab].label),
        actions: [
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
    ));
  }
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
