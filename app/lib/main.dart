/* =============================================================================
 * main.dart — 앱 껍데기
 *
 * **서버 없이도 앱이 삽니다.** 측정·목표·계획·식단·일정은 전부 이 기기에만
 * 있고, 서버는 친구 기능에만 필요합니다. 그래서 첫 화면이 "서버 주소를
 * 넣으세요" 이면 안 됩니다 — 인바디를 넣고 계획을 세우는 데는 서버가
 * 아무 역할도 하지 않으니까요. 주소와 로그인은 친구 탭과 설정에 둡니다.
 *
 * 폰 뒤로가기는 여기서 **공짜입니다.** 지금 쓰는 웹 앱에서는 popstate 를
 * 직접 엮어야 했는데(그게 없어서 뒤로가기가 앱을 통째로 닫았습니다),
 * Flutter 의 Navigator 는 안드로이드 뒤로가기를 원래 받습니다.
 * ========================================================================== */
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'src/api.dart';
import 'src/app_state.dart';
import 'src/scope.dart';
import 'src/shell.dart';
import 'src/theme.dart';

void main() {
  /* **회색 네모를 없앱니다.**
   *
   * 릴리스 빌드에서 화면을 그리다가 예외가 나면 Flutter 는 그 자리에
   * 아무 글자도 없는 회색 네모를 그립니다. 콘솔에도 안 찍힙니다.
   * 실제로 검수 화면이 통째로 회색이었는데 오류가 0건이었습니다 —
   * 무엇이 잘못됐는지 알 방법이 없었습니다.
   *
   * 사용자에게도 회색 네모보다는 "여기서 막혔습니다" 가 낫습니다.
   * 적어도 화면 이름과 함께 말해 줄 수 있으면 고칠 수 있습니다. */
  ErrorWidget.builder = (FlutterErrorDetails details) {
    debugPrint('화면을 그리다 막혔습니다: ${details.exception}');
    return _Stuck(details: details);
  };
  runApp(const MyBodyApp());
}

class _Stuck extends StatelessWidget {
  const _Stuck({required this.details});
  final FlutterErrorDetails details;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFFDECEB),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('이 화면을 그리다 막혔습니다',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFFB91C1C))),
            const SizedBox(height: 8),
            const Text('다른 화면은 그대로 씁니다. 기록은 안 사라집니다.',
                style: TextStyle(fontSize: 13, height: 1.5)),
            const SizedBox(height: 12),
            Text('${details.exception}',
                maxLines: 8, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, height: 1.5, color: Color(0xFF8A1C1C))),
          ],
        ),
      ),
    );
  }
}

const _serverKey = 'mybody.server.v1';

class MyBodyApp extends StatefulWidget {
  const MyBodyApp({super.key});
  @override
  State<MyBodyApp> createState() => _MyBodyAppState();
}

class _MyBodyAppState extends State<MyBodyApp> {
  Api? _api;
  AppState? _app;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  /* **주소를 앱에 넣어 둡니다.**
   *
   * 안 넣어 두면 친구는 깔자마자 빈 칸 앞에 섭니다 — 카톡으로 받은 주소를
   * 찾아 와서 폰 키보드로 붙여넣어야 합니다. 거기서 그만두는 사람이 나옵니다.
   *
   * 값은 빌드할 때 `--dart-define=SERVER_URL=...` 로 들어갑니다. 저장소에는
   * 안 적습니다 — 깃허브 Secrets 에 두고 빌드가 꺼내 씁니다
   * (.github/workflows/apk.yml).
   *
   * **다만 APK 안에는 남습니다.** 파일을 뜯으면 주소가 보입니다. 공개된
   * 곳에 앱을 두는 이상 주소도 공개된 셈이라고 보셔야 합니다 — 계정과
   * 가입 코드가 그 뒤를 막습니다.
   *
   * 한 번이라도 직접 넣은 주소가 있으면 그걸 씁니다. 주인이 주소를 바꿨을
   * 때 앱에 박힌 옛 주소가 그걸 덮어쓰면 안 됩니다. */
  static const String _builtInServer =
      String.fromEnvironment('SERVER_URL', defaultValue: '');

  Future<void> _boot() async {
    String base = '';
    try {
      final sp = await SharedPreferences.getInstance();
      base = sp.getString(_serverKey) ?? '';
    } catch (_) {}
    if (base.isEmpty) base = _builtInServer.trim();
    final api = Api(baseUrl: base);
    await api.loadToken();
    final app = await AppState.boot();
    if (!mounted) return;
    setState(() {
      _api = api;
      _app = app;
      _ready = true;
    });
  }

  Future<void> _setServer(String url) async {
    final clean = url.trim().replaceAll(RegExp(r'/+$'), '');
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_serverKey, clean);
    } catch (_) {}
    final api = Api(baseUrl: clean);
    await api.loadToken();
    if (!mounted) return;
    setState(() => _api = api);
  }

  @override
  Widget build(BuildContext context) {
    final app = MaterialApp(
      title: 'Mybody',
      theme: mbLight(),
      darkTheme: mbDark(),
      debugShowCheckedModeBanner: false,
      /* 서버가 없어도 바로 들어갑니다 — 주소와 로그인은 나중 일입니다. */
      home: !_ready
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : const Shell(),
    );
    if (!_ready) return app;

    /* **Scope 는 MaterialApp 위에 있어야 합니다.**
     *
     * home 안에 두면 Navigator 보다 아래에 놓입니다. 그러면 첫 화면은
     * 멀쩡히 보이는데 **밀어 올린 화면(push)** 에서는 안 보입니다 —
     * 그쪽은 home 의 자손이 아니라 형제이기 때문입니다.
     *
     * 실제로 그렇게 두고 릴리스로 빌드했더니, 검수 화면이 통째로
     * 회색 네모가 됐습니다. 오류는 0건이었습니다(릴리스는 그리다 난
     * 예외를 조용히 회색으로 덮습니다). 위젯 시험은 화면을 home 자리에
     * 직접 세워서 보기 때문에 열아홉 개가 전부 통과했습니다 —
     * 시험이 실제로 앱이 가는 길을 안 밟고 있었습니다. */
    return Scope(
      state: _app!,
      api: _api!,
      onServerChange: _setServer,
      child: app,
    );
  }
}
