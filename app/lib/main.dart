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

  Future<void> _boot() async {
    String base = '';
    try {
      final sp = await SharedPreferences.getInstance();
      base = sp.getString(_serverKey) ?? '';
    } catch (_) {}
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

/* --- 서버 주소 -------------------------------------------------------------
 * 서버가 주인 노트북이라, 앱이 어디를 봐야 하는지 알려 줘야 합니다.
 * 지금 쓰는 웹 앱은 자기가 올라간 주소를 그냥 쓰면 됐지만, 설치하는 앱은
 * 그게 없습니다. 그래서 이 화면이 필요합니다.
 * -------------------------------------------------------------------------- */
class ServerScreen extends StatefulWidget {
  const ServerScreen({super.key, required this.onSet});
  final Future<void> Function(String) onSet;
  @override
  State<ServerScreen> createState() => _ServerScreenState();
}

class _ServerScreenState extends State<ServerScreen> {
  final _c = TextEditingController();
  String? _err;
  bool _busy = false;

  Future<void> _go() async {
    final url = _c.text.trim();
    if (!url.startsWith('https://') && !url.startsWith('http://')) {
      setState(() => _err = 'https:// 로 시작하는 주소를 넣어 주세요');
      return;
    }
    setState(() { _busy = true; _err = null; });
    /* 저장하기 전에 **실제로 닿는지 봅니다.** 오타 난 주소를 저장해 두면
       다음 화면부터 전부 "서버에 닿지 못했습니다" 가 되고, 사용자는
       어디가 틀렸는지 모릅니다. */
    final probe = Api(baseUrl: url.replaceAll(RegExp(r'/+$'), ''));
    final r = await probe.health();
    if (!mounted) return;
    if (!r.ok) {
      setState(() { _busy = false; _err = '그 주소에서 응답이 없습니다 — ${r.reason}'; });
      return;
    }
    await widget.onSet(url);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('서버 주소')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('이 앱은 주인의 컴퓨터에 있는 서버를 봅니다.\n'
              '주소를 받으셨으면 여기에 넣어 주세요.'),
          const SizedBox(height: 16),
          TextField(
            controller: _c,
            autocorrect: false,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              hintText: 'https://…',
              errorText: _err,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _go,
            child: Text(_busy ? '확인하는 중…' : '연결'),
          ),
        ]),
      ),
    );
  }
}

/* --- 로그인 ---------------------------------------------------------------- */
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key, required this.api, required this.onDone,
                      required this.onServerChange});
  final Api api;
  final VoidCallback onDone;
  final Future<void> Function(String) onServerChange;
  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _handle = TextEditingController();
  final _pw = TextEditingController();
  String? _err;
  bool _busy = false;

  Future<void> _go() async {
    setState(() { _busy = true; _err = null; });
    final r = await widget.api.signIn(handle: _handle.text.trim(), password: _pw.text);
    if (!mounted) return;
    if (!r.ok) {
      setState(() { _busy = false; _err = r.reason; });
      return;
    }
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('로그인'),
        actions: [
          IconButton(
            tooltip: '서버 주소 바꾸기',
            icon: const Icon(Icons.dns_outlined),
            onPressed: () => widget.onServerChange(''),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(
            controller: _handle,
            autocorrect: false,
            decoration: const InputDecoration(labelText: '아이디', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pw,
            obscureText: true,
            onSubmitted: (_) => _go(),
            decoration: InputDecoration(
              labelText: '비밀번호',
              border: const OutlineInputBorder(),
              errorText: _err,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _go,
            child: Text(_busy ? '들어가는 중…' : '로그인'),
          ),
          const SizedBox(height: 8),
          /* 비밀번호를 잊었을 때 갈 곳을 여기서 말해 둡니다.
             이 서버는 메일을 안 보내서, 복구 코드가 없으면 주인에게
             말하는 것이 유일한 길입니다. 그 사실을 숨기면 사람들은
             새 계정을 만듭니다 — 실제로 그렇게 되고 있었습니다. */
          const Text(
            '비밀번호를 잊었다면 가입할 때 받은 복구 코드가 필요합니다.\n'
            '그것도 없으면 이 서버를 띄운 사람에게 말하면 풀어 줄 수 있습니다.',
            style: TextStyle(fontSize: 12, height: 1.5),
          ),
        ]),
      ),
    );
  }
}

/* --- P14 계정 --------------------------------------------------------------
 * 서버에 있는 내 계정을 보여 줍니다. 몸 숫자는 여기 없습니다 — 그건 기기에만
 * 있고 서버는 모릅니다.
 * -------------------------------------------------------------------------- */
class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key, required this.api, required this.onServerChange});
  final Api api;
  final Future<void> Function(String) onServerChange;
  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  Map<String, dynamic>? _me;
  int _friendCount = 0;
  String? _err;
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _busy = true; _err = null; });
    final r = await widget.api.me();
    if (!mounted) return;
    if (!r.ok) {
      setState(() { _busy = false; _err = r.reason; });
      return;
    }
    final f = await widget.api.friends();
    if (!mounted) return;
    final accepted = (f.body['accepted'] as List?) ?? const [];
    setState(() {
      _me = (r.body['user'] as Map?)?.cast<String, dynamic>();
      _friendCount = accepted.length;
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final mb = Theme.of(context).extension<MbColors>()!;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mybody'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: '로그아웃',
            onPressed: () async {
              await widget.api.signOut();
              if (context.mounted) widget.onServerChange(widget.api.baseUrl);
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_busy) const Center(child: Padding(
              padding: EdgeInsets.all(32), child: CircularProgressIndicator())),
            if (_err != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: mb.badBg, borderRadius: BorderRadius.circular(10)),
                child: Text(_err!, style: TextStyle(color: mb.bad)),
              ),
            if (_me != null) ...[
              Text('${_me!['displayName'] ?? _me!['handle']}님',
                   style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text('친구 $_friendCount명'),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: mb.accentSub, borderRadius: BorderRadius.circular(12)),
                child: const Text(
                  '몸 숫자는 여기 없습니다.\n\n'
                  '측정 기록·목표·계획은 이 기기에만 있고 서버로 올라가지 않습니다. '
                  '서버가 아는 것은 친구 관계와, 친구에게 보여 주기로 켠 주간 요약뿐입니다.',
                  style: TextStyle(height: 1.6),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
