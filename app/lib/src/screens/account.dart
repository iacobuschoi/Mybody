/* =============================================================================
 * account.dart — 서버 주소 · 로그인 · 가입 · 내 계정 (P14)
 *
 * **계정은 기록 동기화 · 사진 판독 · 친구에 씁니다.** 로그인하면 기록 전체
 * (측정 · 프로필 · 목표 · 계획 · 식단)가 내 계정에도 저장됩니다(cloud.dart).
 * 로그인 없이도 숫자를 넣고 계획을 세우는 데는 문제가 없습니다 — 그때 기록은
 * 기기에만 있습니다. 가입 동의 문구는 이 둘을 그대로 말해야 합니다.
 * ========================================================================== */
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../theme.dart';
import '../ui/widgets.dart';

/// 서버가 받아 주는 건강정보 동의 판. 서버의 `HEALTH_CONSENT_VERSION` 과
/// **글자까지 같아야** 합니다 — 다르면 가입이 400 으로 거부됩니다.
/// (server/db.js 의 같은 이름 상수. 웹 앱도 sync.js 에 같은 값을 들고 있습니다.)
const String kHealthConsentVersion = '2026-09-22';

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
      setState(() => _err = 'http 주소는 폰이 막습니다 — https 주소를 넣어 주세요');
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

/* --- 로그인 · 가입 · 비밀번호 잊음 ---------------------------------------
 *
 * 한 화면에서 세 갈래입니다. 웹 앱이 그렇게 돼 있고(M29), 그게 맞습니다 —
 * 로그인하러 왔는데 계정이 없다는 걸 그 자리에서 알게 되는 사람이 대부분이라
 * 화면을 옮겨 다니게 하면 거기서 끝납니다.
 *
 * 예전에는 **로그인만 있었습니다.** 가입도 복구도 없었습니다. 기존 친구들은
 * 웹에서 만든 계정이 있어서 티가 안 났지만, 새로 들어오는 친구는 계정을 만들
 * 길이 없었고, 비밀번호를 잊은 사람은 화면이 "복구 코드가 필요합니다" 라고
 * 말하는 걸 읽고도 넣을 데가 없었습니다.
 * -------------------------------------------------------------------------- */
enum _AuthMode { signIn, signUp, recover }

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key, required this.api, required this.onDone,
                      required this.onServerChange, this.intro, this.onSkip});
  final Api api;
  final VoidCallback onDone;
  final Future<void> Function(String) onServerChange;
  /// 첫 실행처럼 왜 이 화면이 먼저 뜨는지 말해 줘야 할 때 한 줄.
  final String? intro;
  /// 첫 실행에서만 줍니다 — 있으면 「로그인 없이 쓰기」가 보입니다.
  final VoidCallback? onSkip;
  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  _AuthMode _mode = _AuthMode.signIn;

  final _handle = TextEditingController();
  final _pw = TextEditingController();
  final _name = TextEditingController();
  final _pair = TextEditingController();
  final _code = TextEditingController();

  String? _err;
  bool _busy = false;
  bool _consent = false;

  /// 서버가 가입 코드를 요구하는지. null 이면 아직 안 물어봤습니다.
  bool? _openSignup;

  @override
  void initState() {
    super.initState();
    _askServer();
  }

  /* 가입 코드 칸을 **필요할 때만** 보여 줍니다. 서버가 아무나 받는 설정이면
     그 칸은 물어볼 이유가 없고, 빈 칸 하나가 "나는 이걸 모르는데" 를 만듭니다. */
  Future<void> _askServer() async {
    final r = await widget.api.health();
    if (!mounted) return;
    setState(() => _openSignup = r.ok ? r.body['openSignup'] == true : null);
  }

  Future<void> _go() async {
    final handle = _handle.text.trim();
    if (handle.isEmpty) {
      setState(() => _err = '아이디를 넣어 주세요');
      return;
    }
    if (_mode == _AuthMode.signUp && !_consent) {
      setState(() => _err = '내 기록을 계정에 저장하는 것에 동의해야 계정을 만들 수 있습니다');
      return;
    }
    setState(() { _busy = true; _err = null; });

    final ApiResult r;
    switch (_mode) {
      case _AuthMode.signIn:
        r = await widget.api.signIn(handle: handle, password: _pw.text);
      case _AuthMode.signUp:
        r = await widget.api.signUp(
          handle: handle,
          password: _pw.text,
          displayName: _name.text.trim().isEmpty ? handle : _name.text.trim(),
          pairSecret: _pair.text.trim(),
          healthConsent: kHealthConsentVersion,
        );
      case _AuthMode.recover:
        r = await widget.api.recover(
            handle: handle, code: _code.text.trim(), password: _pw.text);
    }
    if (!mounted) return;
    if (!r.ok) {
      setState(() { _busy = false; _err = r.reason; });
      return;
    }
    /* 복구 코드는 **이때 한 번만** 보여 줍니다. 서버는 해시만 들고 있어서
       다시 꺼내 줄 수 없습니다. 놓치면 비밀번호를 잊었을 때 길이 없습니다. */
    final code = r.body['recoveryCode'];
    if (code is String && code.isNotEmpty) {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('복구 코드'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text(
              '비밀번호를 잊으면 이 코드로만 되돌릴 수 있습니다. '
              '지금 어딘가에 적어 두세요 — 다시 보여 드릴 수 없습니다.',
              style: TextStyle(fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 14),
            SelectableText(code,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ]),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: code));
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('복사하고 닫기'),
            ),
          ],
        ),
      );
    }
    if (!mounted) return;
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final signUp = _mode == _AuthMode.signUp;
    final recover = _mode == _AuthMode.recover;
    final needPair = signUp && _openSignup == false;

    return Scaffold(
      appBar: AppBar(title: const Text('계정')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.intro != null) ...[
            Text(widget.intro!, style: t.textTheme.bodyMedium),
            const SizedBox(height: 12),
          ],
          SegmentedButton<_AuthMode>(
            segments: const [
              ButtonSegment(value: _AuthMode.signIn, label: Text('로그인')),
              ButtonSegment(value: _AuthMode.signUp, label: Text('처음이에요')),
              ButtonSegment(value: _AuthMode.recover, label: Text('비밀번호 잊음')),
            ],
            selected: {_mode},
            onSelectionChanged: (v) => setState(() {
              _mode = v.first;
              _err = null;
            }),
          ),
          const SizedBox(height: 18),

          TextField(
            controller: _handle,
            autocorrect: false,
            decoration: const InputDecoration(
                labelText: '아이디', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 10),

          if (signUp) ...[
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                  labelText: '친구에게 보일 이름',
                  hintText: '비워 두면 아이디를 씁니다',
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
          ],

          if (recover) ...[
            TextField(
              controller: _code,
              autocorrect: false,
              decoration: const InputDecoration(
                  labelText: '복구 코드',
                  hintText: '가입할 때 받은 코드',
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
          ],

          TextField(
            controller: _pw,
            obscureText: true,
            decoration: InputDecoration(
                labelText: recover ? '새 비밀번호' : '비밀번호',
                border: const OutlineInputBorder()),
          ),

          if (needPair) ...[
            const SizedBox(height: 10),
            TextField(
              controller: _pair,
              autocorrect: false,
              decoration: const InputDecoration(
                  labelText: '가입 코드',
                  hintText: '이 서버를 띄운 사람에게 받으세요',
                  border: OutlineInputBorder()),
            ),
          ],

          if (_err != null) ...[
            const SizedBox(height: 12),
            Text(_err!, style: TextStyle(color: t.colorScheme.error)),
          ],

          /* 건강정보 동의는 **계정 만들기와 따로** 받습니다.
             체성분은 민감정보입니다. 로그인하면 기록 전체가 내 계정에
             동기화되고(cloud.dart), 친구가 하나도 없어도 주간 요약이
             올라가므로, 가입이 곧 업로드 동의가 됩니다. 다른 것과 섞어
             받으면 안 읽히고, 안 읽힌 동의는 동의가 아닙니다.

             **문구는 실제로 올라가는 것과 같아야 합니다.** 예전 문구는
             "가장 최근 측정만 · 52주까지만" 이었는데, 동기화가 생긴 뒤로는
             기록 전체가 계정을 지울 때까지 남습니다. 52주는 주간 요약
             (server/db.js SNAPSHOT_WEEKS)에만 맞는 숫자입니다. */
          if (signUp) ...[
            const SizedBox(height: 16),
            MbCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('내 기록을 서버(내 계정)에 저장하는 것에 동의가 필요합니다',
                    style: t.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ...[
                  '무엇을 — 측정 기록(체중 · 골격근량 · 체지방량 · 체지방률 등), '
                      '프로필(키 · 나이 · 성별), 목표 · 계획 · 식단 · 운동 기록. '
                      '결과지 사진은 올라가지 않습니다.',
                  '왜 — 기기를 바꿔 로그인해도 기록이 그대로 따라오게 하고, 친구에게 '
                      '보여 줄 주간 요약을 만들기 위해서. 친구 화면에 실제로 보이는 것은 '
                      '친구마다 켠 항목뿐입니다.',
                  '얼마나 — 계정을 지울 때까지(설정 → 지우기 → 계정 지우기). '
                      '주간 요약은 최근 52주만 두고, 그보다 오래된 것은 서버가 지웁니다.',
                  '거부하면 — 계정을 못 만들지만, 로그인 없이 계속 쓸 수 있습니다. '
                      '그때 기록은 이 기기에만 남고, 측정 · 목표 · 계획 · 식단은 다 되며 '
                      '사진 판독과 친구 기능만 못 씁니다.',
                ].map((line) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text('· $line',
                          style: t.textTheme.bodySmall?.copyWith(height: 1.5)),
                    )),
                const SizedBox(height: 4),
                CheckboxListTile(
                  value: _consent,
                  onChanged: (v) => setState(() => _consent = v ?? false),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('동의합니다'),
                ),
              ]),
            ),
          ],

          const SizedBox(height: 18),
          FilledButton(
            onPressed: _busy ? null : _go,
            child: Text(_busy
                ? '하는 중…'
                : switch (_mode) {
                    _AuthMode.signIn => '로그인',
                    _AuthMode.signUp => '계정 만들기',
                    _AuthMode.recover => '비밀번호 바꾸기',
                  }),
          ),

          const SizedBox(height: 16),
          if (_mode == _AuthMode.signIn)
            Text(
              '계정이 없으면 위에서 「처음이에요」를 누르세요.\n'
              '비밀번호를 잊었다면 가입할 때 받은 복구 코드가 필요합니다. '
              '그것도 없으면 이 서버를 띄운 사람에게 말하면 풀어 줄 수 있습니다.',
              style: t.textTheme.bodySmall?.copyWith(color: t.hintColor, height: 1.5),
            ),

          /* 계정 없이도 앱의 기본은 다 됩니다 — 그 길을 여기서 보여 줍니다.
             무엇이 안 되는지도 같이 말합니다. 나중에 판독을 누르고서야
             알게 되면 그게 더 나쁜 첫인상입니다. */
          if (widget.onSkip != null) ...[
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _busy ? null : widget.onSkip,
              child: const Text('로그인 없이 쓰기'),
            ),
            const SizedBox(height: 8),
            Text(
              '기록은 이 기기에만 저장됩니다. 숫자를 직접 넣어 기록 · 목표 · 계획 · 식단을 '
              '다 쓸 수 있고, 사진 판독 · 친구 · 기기 옮기기는 나중에 설정에서 로그인하면 됩니다.',
              style: t.textTheme.bodySmall?.copyWith(color: t.hintColor, height: 1.5),
            ),
          ],
        ],
      ),
    );
  }
}

/* --- P14 계정 --------------------------------------------------------------
 * 서버에 있는 내 계정을 보여 줍니다. 몸 숫자는 이 화면에 띄우지 않습니다 —
 * 동기화 사본은 본인 기기로 내려받는 용도이고, 여기는 계정 이름과 친구 수만.
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
    /* 서버는 **한 겹 더 감싸서** 줍니다:
     *   { ok: true, friends: { accepted: [], incoming: [], outgoing: [], blocked: [] } }
     *
     * 여기서는 `body['accepted']` 를 읽고 있었습니다. 서버가 보내지 않는
     * 이름이라 언제나 null 이었고, 친구가 몇이든 **0명**이라고 나왔습니다.
     * 친구 목록 화면(social.dart)은 처음부터 맞게 읽고 있어서, 목록에는
     * 친구가 보이는데 이 화면만 0명이라고 우기는 모양이 됐습니다. */
    final friends = (f.body['friends'] as Map?)?.cast<String, dynamic>();
    final accepted = (friends?['accepted'] as List?) ?? const [];
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
            icon: const Icon(LucideIcons.logOut),
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
                  '기록은 내 계정에도 저장됩니다.\n\n'
                  '측정 기록·목표·계획·식단이 이 기기와 내 계정에 같이 있습니다 — 기기를 바꿔 '
                  '로그인하면 그대로 따라옵니다. 친구가 보는 것은 친구에게 보여 주기로 켠 것뿐입니다.',
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
