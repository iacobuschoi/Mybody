/* =============================================================================
 * main.dart — 앱 껍데기
 *
 * 지금은 첫 조각입니다: 서버 주소를 정하고, 로그인하고, 서버가 뭐라고
 * 하는지 보여 주는 데까지. 화면 21개는 아직 안 옮겼습니다.
 *
 * 이 조각을 먼저 세우는 이유는 **파이프라인이 실제로 도는지**를 확인하기
 * 위해서입니다 — Flutter 가 한글을 그리는가, 서버에 닿는가, 폰 뒤로가기가
 * 먹는가. 여기서 막히면 화면을 아무리 옮겨도 소용이 없습니다.
 *
 * 폰 뒤로가기는 여기서 **공짜입니다.** 지금 쓰는 웹 앱에서는 popstate 를
 * 직접 엮어야 했는데(그게 없어서 앱이 통째로 닫혔습니다), Flutter 의
 * Navigator 는 안드로이드 뒤로가기를 원래 받습니다.
 * ========================================================================== */
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'src/api.dart';
import 'src/theme.dart';

void main() => runApp(const MyBodyApp());

const _serverKey = 'mybody.server.v1';

class MyBodyApp extends StatefulWidget {
  const MyBodyApp({super.key});
  @override
  State<MyBodyApp> createState() => _MyBodyAppState();
}

class _MyBodyAppState extends State<MyBodyApp> {
  Api? _api;
  bool _ready = false;
  String _server = '';

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    String s = '';
    try {
      final sp = await SharedPreferences.getInstance();
      s = sp.getString(_serverKey) ?? '';
    } catch (_) {}
    final api = Api(baseUrl: s);
    await api.loadToken();
    if (!mounted) return;
    setState(() {
      _server = s;
      _api = api;
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
    setState(() {
      _server = clean;
      _api = api;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mybody',
      theme: mbLight(),
      darkTheme: mbDark(),
      debugShowCheckedModeBanner: false,
      home: !_ready
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : _server.isEmpty
              ? ServerScreen(onSet: _setServer)
              : (_api!.signedIn
                  ? HomeScreen(api: _api!, onServerChange: _setServer)
                  : SignInScreen(api: _api!, onDone: () => setState(() {}),
                                 onServerChange: _setServer)),
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

/* --- 홈 (첫 조각) ---------------------------------------------------------- */
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.api, required this.onServerChange});
  final Api api;
  final Future<void> Function(String) onServerChange;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
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
                  '여기까지가 옮긴 첫 조각입니다.\n\n'
                  '서버 연결 · 로그인 · 한글 · 폰 뒤로가기가 되는지 확인하는 것이 '
                  '목적이고, 측정 · 계획 · 친구 화면은 아직 옮기는 중입니다. '
                  '그동안 쓰던 앱은 그대로 쓸 수 있습니다.',
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
