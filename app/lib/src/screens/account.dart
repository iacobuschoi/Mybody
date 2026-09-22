/* =============================================================================
 * account.dart — 서버 주소 · 로그인 · 가입 · 내 계정 (P14)
 *
 * **서버는 친구 기능에만 씁니다.** 몸 숫자는 주소를 넣어도, 로그인해도
 * 서버로 안 올라갑니다. 그래서 이 화면들은 앱의 입구가 아니라 곁길입니다 —
 * 인바디를 넣고 계획을 세우는 데는 하나도 필요 없습니다.
 * ========================================================================== */
import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';

/* --- 서버 주소 -------------------------------------------------------------
 * 서버가 주인 노트북이라, 앱이 어디를 봐야 하는지 알려 줘야 합니다.
 * 지금 쓰는 웹 앱은 자기가 올라간 주소를 그냥 쓰면 됐지만, 설치하는 앱은
 * 그게 없습니다. 그래서 이 화면이 필요합니다.
 * -------------------------------------------------------------------------- */
/// 붙여넣은 주소를 **쓸 수 있는 꼴로 다듬습니다.**
///
/// 친구는 이 주소를 카톡으로 받아서 붙여넣습니다. 그때 딸려 오는 것들이
/// 있습니다 — 문장 끝 마침표, 감싼 따옴표, `tailscale status` 가 내주는
/// 끝점(`mypc.tail1234.ts.net.`), 그리고 무엇보다 **https:// 가 없는 맨
/// 주소**. 예전에는 이걸 전부 거부하고 "https:// 로 시작하는 주소를 넣어
/// 주세요" 라고만 했습니다. 폰 키보드로 주소 앞에 글자를 끼워 넣는 일은
/// 거기서 그만두게 만드는 종류의 일입니다.
String normalizeServerUrl(String raw) {
  var s = raw.trim();
  s = s.replaceAll(RegExp('^[\'"`<]+'), '').replaceAll(RegExp('[\'"`>]+\$'), '');
  s = s.replaceAll(RegExp(r'[.,]+$'), '').trim();
  if (s.isEmpty) return s;
  final lower = s.toLowerCase();
  if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
    s = 'https://$s';
  }
  return s.replaceAll(RegExp(r'/+$'), '');
}

class ServerScreen extends StatefulWidget {
  const ServerScreen({super.key, required this.onSet, this.initial = ''});
  final Future<void> Function(String) onSet;
  /// 이미 넣어 둔 주소를 고치러 들어올 때 채워 줍니다.
  final String initial;
  @override
  State<ServerScreen> createState() => _ServerScreenState();
}

class _ServerScreenState extends State<ServerScreen> {
  late final _c = TextEditingController(text: widget.initial);
  String? _err;
  bool _busy = false;

  Future<void> _go() async {
    final url = normalizeServerUrl(_c.text);
    /* **http 는 받지 않습니다.**
     *
     * 예전에는 http 도 통과시켰는데, 말과 코드가 달랐습니다 — 안내문은
     * https 를 넣으라고 하면서 http 를 받았습니다. 그런데 안드로이드는
     * 9 버전부터 http 를 기본으로 막습니다. 그래서 http 주소를 넣으면
     * 저장은 되고 연결만 조용히 실패하고, 화면에는 "컴퓨터가 꺼져 있을 수
     * 있습니다" 가 뜹니다. 켜져 있는데도요.
     *
     * 여기서 막고 이유를 말해 주는 편이 낫습니다. 터널 주소(*.ts.net)는
     * 원래 https 라 실제로 쓰는 데 불편이 없습니다. */
    if (url.startsWith('http://')) {
      setState(() => _err = '안드로이드가 http 주소를 막습니다 — https 주소를 넣어 주세요');
      return;
    }
    final parsed = Uri.tryParse(url);
    if (url.contains(' ') || parsed == null || parsed.host.isEmpty) {
      setState(() => _err = '주소 같지 않습니다 — 받은 주소를 통째로 붙여넣어 주세요');
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
              hintText: '받은 주소를 붙여넣으세요',
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
