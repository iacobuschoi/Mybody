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

import 'scope.dart';
import 'screens/food.dart';
import 'screens/home.dart';
import 'screens/plan.dart';
import 'screens/progress.dart';
import 'screens/settings.dart';
import 'screens/social.dart';
import 'screens/upload.dart';
import 'screens/goal.dart';
import 'screens/history.dart';
import 'screens/scandetail.dart';

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _tab = 0;

  static const _tabs = [
    (icon: Icons.home_outlined, on: Icons.home, label: '홈'),
    (icon: Icons.rice_bowl_outlined, on: Icons.rice_bowl, label: '식단'),
    (icon: Icons.assignment_outlined, on: Icons.assignment, label: '플랜'),
    (icon: Icons.show_chart_outlined, on: Icons.show_chart, label: '추이'),
    (icon: Icons.group_outlined, on: Icons.group, label: '친구'),
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
      case 'settings':
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = switch (_tab) {
      0 => HomeScreen(go: _go),
      1 => FoodScreen(go: _go),
      2 => PlanScreen(go: _go),
      3 => ProgressScreen(go: _go),
      _ => SocialScreen(go: _go),
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(_tabs[_tab].label),
        actions: [
          IconButton(
            tooltip: '설정',
            icon: const Icon(Icons.settings_outlined),
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
              icon: const Icon(Icons.add_a_photo_outlined),
              label: const Text('인바디'),
            )
          : null,
    );
  }
}

/// 화면들이 같이 쓰는 "로그인이 필요합니다" 안내.
class NeedsSignIn extends StatelessWidget {
  const NeedsSignIn({super.key, required this.what});
  final String what;

  @override
  Widget build(BuildContext context) {
    final api = Scope.apiOf(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('$what은 로그인해야 쓸 수 있습니다',
              textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          Text(
            api.baseUrl.isEmpty
                ? '먼저 서버 주소를 넣어야 합니다 — 설정에서 넣을 수 있습니다.'
                : '몸 숫자는 기기에만 있습니다. 로그인해도 서버로 올라가지 않습니다.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: Theme.of(context).hintColor, height: 1.5),
          ),
        ]),
      ),
    );
  }
}
