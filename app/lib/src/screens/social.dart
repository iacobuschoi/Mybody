/* =============================================================================
 * social.dart — P15 친구 · P16 친구 상세
 *
 * **친구에게 무엇이 보이는지는 각자의 「기본 공유」 가 정합니다.** 친구를 맺는
 * 순간 서버가 그 값을 복사하고(처음 값은 몸 숫자 꺼짐), 그 뒤로는 친구마다
 * 따로 켜고 끕니다. 그래서 화면은 "몸 숫자는 기본 비공개" 라고 단정하지 않고,
 * 수락 버튼 옆에 내 기본값으로 실제로 나갈 것을 보여 줍니다.
 * 켜고 끄는 것은 화면에서 가리는 것이 아니라 **서버가 안 보내는** 것입니다 —
 * 권한 판정은 언제나 서버가 합니다.
 *
 * 점(배지)은 두 가지에만 켭니다: 받은 친구 요청(내가 답해야 하는 일)과
 * 친구 소식(친구가 운동했다는 좋은 소식). **안 한 것에는 절대 안 켭니다** —
 * 친구가 이번 주에 운동을 안 했다는 것은 알림이 되지 않습니다.
 * 이 구분이 이 앱이 두는 압박의 상한선입니다.
 *
 * 친구 코드에 관한 것은 전부 이 파일에 한 벌만 있습니다 — 코드 모양([isInviteCode] ·
 * [cleanInviteCode]), 보내는 글과 초대 링크([inviteShareText]), 요청([requestFriendByCode])과
 * 그 답의 한 줄([friendRequestMessage]). 친구 탭의 「친구 추가」, 테스터 인사(3쪽), 초대
 * 링크를 눌러 앱이 열렸을 때(invite_link.dart)가 같은 함수로 보내고 같은 말을 합니다 —
 * 같은 일을 두 군데서 따로 짜면 한쪽만 고쳐집니다.
 *
 * 「친구 추가」 다이얼로그에는 **내 코드와 「보내기」 가 먼저** 있습니다(주인 의견: "여기서도
 * 코드 보내기를 만들어서 링크 받으면 요청이 가게"). 친구를 부르는 쪽이 할 일은 링크 하나
 * 보내기이고, 받은 쪽은 그 링크를 누르면 끝입니다 — 여덟 글자를 옮겨 치는 칸은 그 밑의
 * 예비 길입니다. 그래서 다이얼로그를 열자마자 키보드를 올리지 않습니다. 그 칸도 옮겨 칠
 * 일이 없게 「초대 코드 붙여넣기」([InvitePasteChip])를 둡니다 — 앱이 없던 친구는 초대
 * 페이지의 설치 단추가 클립보드에 초대 글을 넣어 둡니다(주인 의견 45 "모든걸 자동으로").
 * ========================================================================== */
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mybody_core/mybody_core.dart' as core;

import '../api.dart';
import '../pokes.dart';
import '../scope.dart';
import '../shell.dart';
import '../ui/fmt.dart';
import '../ui/symbols.dart';
import '../ui/widgets.dart';
import 'adherence.dart' show DayMark, DayMarkLegend, dayMarkState;
import 'news.dart';
import 'share_defaults.dart';

class SocialScreen extends StatefulWidget {
  const SocialScreen({super.key, required this.go});
  final void Function(String route, [Object? arg]) go;

  @override
  State<SocialScreen> createState() => _SocialScreenState();
}

class _SocialScreenState extends State<SocialScreen> {
  static const _cacheKey = 'mybody.friends.cache.v1';
  Map<String, dynamic>? _friends;
  Map<String, dynamic>? _me;
  String? _error;
  bool _busy = false;
  /// 서버에 못 닿아서 마지막으로 본 목록을 보여 주는 중인가.
  bool _fromCache = false;
  /// 내 「기본 공유」 — 받은 요청의 수락 버튼 옆에 "수락하면 보여 줄 것" 으로.
  /// 못 받았으면(옛 서버 · 오프라인) null 이고, 그때는 그 줄이 없습니다.
  Map<String, bool>? _myDefaults;

  Future<void> _remember(Map<String, dynamic> friends) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_cacheKey, jsonEncode(friends));
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> _recall() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final s = sp.getString(_cacheKey);
      if (s == null) return null;
      return (jsonDecode(s) as Map).cast<String, dynamic>();
    } catch (_) {
      return null;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_friends == null && !_busy) _load();
  }

  Future<void> _load() async {
    /* 요청 줄의 [수락] · [거절] 이 끝난 뒤 부릅니다 — 그 사이 로그아웃으로 이 탭이 내려갔을 수 있습니다. */
    if (!mounted) return;
    final api = Scope.apiOf(context);
    if (!api.signedIn) return;
    setState(() => _busy = true);
    /* 캐시가 있으면 **먼저** 보여 줍니다. 서버가 5초 걸리는 동안 빈 스피너만
       보면 사람들은 탭이 고장났다고 생각하고 눌러 댑니다. */
    if (_friends == null) {
      final cached = await _recall();
      if (!mounted) return;
      if (cached != null) setState(() { _friends = cached; _fromCache = true; });
    }
    final both = await Future.wait([api.me(), api.friends(), api.getShareDefaults()]);
    final me = both[0];
    final f = both[1];
    final d = both[2];
    if (!mounted) return;
    var friends = f.ok ? (f.body['friends'] as Map?)?.cast<String, dynamic>() : null;
    var fromCache = false;
    if (friends != null) {
      await _remember(friends);
    } else {
      /* 서버에 못 닿았다고 목록을 비우지 않습니다. 비행기 모드에서 친구
         상세에 들어가 스위치를 바꾸고 "나중에 보냅니다" 가 되려면 목록이
         있어야 합니다. 마지막으로 본 목록을 그대로 둡니다 — 스냅샷은 그때
         것이라 오래됐을 수 있고, 그건 위에 적어 둡니다. */
      friends = await _recall();
      fromCache = friends != null;
    }
    if (!mounted) return;
    await _refreshNews(api, f);
    if (!mounted) return;
    /* 친구가 보낸 독촉도 여기서 한 번 더 — 켜 둔 채로 탭에 들어오는 사람. */
    unawaited(Scope.of(context).pokes?.fetch(api));
    if (!mounted) return;
    setState(() {
      _busy = false;
      _me = me.ok ? (me.body['user'] as Map?)?.cast<String, dynamic>() : null;
      _friends = friends;
      _fromCache = fromCache;
      _error = f.ok ? null : f.reason;
      if (d.ok && d.body['defaults'] is Map) _myDefaults = shareFlagsFrom(d.body['defaults']);
    });
  }

  /* 소식은 **기기 안에서** 계산합니다. 서버에 새 경로를 만들지 않습니다 —
     이미 공유 설정으로 걸러져 온 주간 요약을 지난번 본 값과 견줄 뿐이라,
     새로 나가는 정보가 하나도 없습니다. */
  Future<void> _refreshNews(Api api, ApiResult f) async {
    final news = Scope.of(context).news;
    if (news == null || !f.ok) return;
    final friends = ((f.body['friends'] as Map?)?['accepted'] as List?) ?? const [];
    /* 친구마다 한 번씩 — 차례로 기다리면 친구 수만큼 느려집니다. 한꺼번에. */
    final people = [for (final p in friends) if ((p as Map)['id'] is String) p];
    final asked = api.token;
    final results = await Future.wait([for (final p in people) api.friendSnapshots('${p['id']}')]);
    /* 기다리는 사이 계정이 바뀌었으면 앞 계정 친구들의 소식 — 새 칸에 적지 않습니다(local_owner.dart). */
    if (asked != api.token) return;
    final snaps = <Object?>[];
    for (var i = 0; i < people.length; i++) {
      final p = people[i];
      final r = results[i];
      /* 못 받아온 것과 공유를 끈 것은 다릅니다 — 실패는 rows 를 아예
         안 실어 보냅니다. 코어가 그 차이를 압니다. */
      final rows = r.ok ? ((r.body['rows'] as List?) ?? const []) : null;
      snaps.add({'id': p['id'], if (rows != null) 'rows': rows});
      /* 목록과 상세가 보는 최신 주. 이게 빠져 있어서 친구 화면이 늘
         "공유한 것이 없습니다" 였습니다 — 서버는 주고 있었는데요. */
      if (rows != null && rows.isNotEmpty) p['snapshot'] = rows.first;
    }
    news.apply(snaps, friends);
  }

  @override
  Widget build(BuildContext context) {
    final api = Scope.apiOf(context);
    if (!api.signedIn) return NeedsSignIn(what: '친구', go: widget.go);
    if (_busy && _friends == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final accepted = ((_friends?['accepted'] as List?) ?? const []);
    final incoming = ((_friends?['incoming'] as List?) ?? const []);
    final outgoing = ((_friends?['outgoing'] as List?) ?? const []);
    final t = Theme.of(context);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        if (_error != null)
          Note(
              tone: Tone.warn,
              text: _fromCache
                  ? '$_error — 마지막으로 본 목록입니다 · 바꾼 것은 나중에 보냅니다'
                  : _error!),
        /* 나를 찌른 친구들 — 맨 위에. 치울 때까지 남습니다. */
        Builder(builder: (_) {
          final box = Scope.of(context).pokes;
          if (box == null) return const SizedBox.shrink();
          return ListenableBuilder(
            listenable: box,
            builder: (_, __) => Column(children: [
              for (final p in box.items)
                _PokeBanner(poke: p, onDismiss: () => box.dismiss(p['id'])),
            ]),
          );
        }),

        /* 소식으로 가는 문. 안 읽은 게 있으면 숫자를 답니다.
           **좋은 소식만** 여기 쌓입니다 — 안 한 것은 안 올라옵니다. */
        Builder(builder: (_) {
          final news = Scope.of(context).news;
          if (news == null) return const SizedBox.shrink();
          final unread = news.unread();
          final names = <String, String>{
            for (final p in accepted)
              '${(p as Map)['id']}': '${p['displayName']}',
          };
          return MbCard(
            onTap: () async {
              await Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => NewsScreen(names: names)));
              if (mounted) setState(() {});
            },
            child: Row(children: [
              const Icon(LucideIcons.bell, size: 20),
              const SizedBox(width: 10),
              const Expanded(child: Text('소식')),
              if (unread > 0) Pill('$unread', tone: Tone.ok),
              const SizedBox(width: 6),
              Icon(LucideIcons.chevronRight, size: 18, color: t.hintColor),
            ]),
          );
        }),

        if (_me != null)
          MbCard(
            child: Row(children: [
              Avatar(displayName: '${_me!['displayName']}', id: '${_me!['id']}',
                  avatarUrl: _me!['avatar'] as String?, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${_me!['displayName']}', style: t.textTheme.titleSmall),
                  Text('내 코드 ${_myCode ?? '—'}',
                      style: t.textTheme.labelSmall?.copyWith(color: t.hintColor)),
                ]),
              ),
              OutlinedButton(
                onPressed: () => _addFriend(context),
                child: const Text('친구 추가'),
              ),
              IconButton(
                tooltip: '내 계정',
                icon: const Icon(LucideIcons.userCog),
                onPressed: () => widget.go('account'),
              ),
            ]),
          )
        else
          /* 내 정보를 아직 못 받았어도(캐시를 먼저 보여 주는 중 · /me 실패) 「친구 추가」 는
             둡니다 — 내 코드는 다이얼로그가 스스로 받아 옵니다. */
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: OutlinedButton(
                onPressed: () => _addFriend(context),
                child: const Text('친구 추가'),
              ),
            ),
          ),

        if (incoming.isNotEmpty) ...[
          const SectionTitle('받은 요청'),
          for (final p in incoming) _RequestRow(person: p, onDone: _load, defaults: _myDefaults),
        ],
        if (outgoing.isNotEmpty) ...[
          const SectionTitle('보낸 요청'),
          for (final p in outgoing)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Avatar(displayName: '${p['displayName']}', id: '${p['id']}',
                  avatarUrl: p['avatar'] as String?, size: 36),
              title: Text('${p['displayName']}'),
              subtitle: Text('수락을 기다리는 중입니다', style: t.textTheme.labelSmall),
            ),
        ],

        /* 새 친구에게 기본으로 보여 줄 것 — 설정의 카드와 같은 것을 여기서도.
           친구 목록 바로 위라 "누구에게 무엇이 나가나" 를 찾는 사람이 닿습니다.
           돌아오면 목록을 다시 받습니다 — 「모두에게 적용」 이 목록의 공유
           요약(iShare)을 바꿨을 수 있습니다. */
        SectionTitle('친구',
            trailing: TextButton.icon(
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              onPressed: () async {
                await Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ShareDefaultsScreen()));
                if (mounted) unawaited(_load());
              },
              icon: const Icon(LucideIcons.slidersHorizontal, size: 16),
              label: const Text('기본 공유'),
            )),
        if (accepted.isEmpty)
          const EmptyState(
            title: '아직 친구가 없습니다',
            detail: '무엇이 보일지는 「기본 공유」에서 정합니다',
          )
        else
          for (final p in accepted)
            MbCard(
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => FriendDetailScreen(person: p.cast<String, dynamic>()))),
              child: _FriendRow(person: p.cast<String, dynamic>()),
            ),
      ]),
    );
  }

  /// /me 가 준 내 친구 코드. 아직 못 받았거나 비었으면 null.
  String? get _myCode {
    final c = _me?['inviteCode'];
    return c is String && c.trim().isNotEmpty ? c.trim() : null;
  }

  /* 요청은 다이얼로그 안에서 보냅니다 — 틀린 코드 · 없는 코드면 다이얼로그가 그대로 남아
     그 자리에서 고쳐 넣습니다(닫고 다시 열어 다시 치게 하지 않습니다). 보냈으면 닫고 여기서
     한 줄 알린 뒤 목록을 다시 받습니다 — 「보낸 요청」 에 그 사람이 뜹니다. */
  Future<void> _addFriend(BuildContext context) async {
    final r = await showDialog<ApiResult>(
      context: context,
      builder: (_) => _AddFriendDialog(
        api: Scope.apiOf(context),
        myCode: _myCode,
        /* 다이얼로그가 내 코드를 받아 왔으면 카드에도 — 같은 /me 를 두 번 묻지 않게. */
        onMe: (user) {
          if (mounted && _me == null) setState(() => _me = user);
        },
      ),
    );
    if (r == null || !context.mounted) return;
    toast(context, friendRequestMessage(r));
    if (r.ok) _load();
  }
}

/* --- 「친구 추가」 다이얼로그 -------------------------------------------------
 *
 * 위: 내 코드(크게 — 누르면 복사) · 「보내기」(초대 링크가 든 글을 공유 시트로).
 * 아래: 친구 코드 칸 · 「요청 보내기」. 클립보드에 글이 있으면 칸 밑에 「초대 코드 붙여넣기」
 * ([InvitePasteChip]) — 누르면 코드만 칸에 채웁니다(없으면 칸 밑에 「복사한 글에 초대 코드가
 * 없어요」).
 * 내 코드를 아직 모르면(친구 탭이 /me 를 못 받았으면) 여기서 받아 옵니다 — 그동안 작은
 * 원이 돌고, 못 받으면 「다시」. 「복사했어요」 는 다이얼로그 **안의** 한 줄로 알립니다 —
 * 앱의 스낵바는 다이얼로그의 어두운 막 밑에 깔려 잘 안 보입니다.
 * 키보드가 올라오면 다이얼로그가 그 위로 줄어들고 내용은 스크롤됩니다(scrollable) —
 * 360 폭 폰에서도 「요청 보내기」 는 늘 키보드 위에 있습니다.
 * -------------------------------------------------------------------------- */
class _AddFriendDialog extends StatefulWidget {
  const _AddFriendDialog({required this.api, this.myCode, this.onMe});
  final Api api;
  final String? myCode;
  final void Function(Map<String, dynamic> user)? onMe;

  @override
  State<_AddFriendDialog> createState() => _AddFriendDialogState();
}

class _AddFriendDialogState extends State<_AddFriendDialog> {
  final _input = TextEditingController();
  String? _code;
  bool _codeFailed = false;
  bool _sending = false;
  String? _error;
  /// 「내 코드」 자리에 잠깐 뜨는 한 줄(복사했어요 등). 2초 뒤 돌아갑니다.
  String? _flash;
  Timer? _flashTimer;

  @override
  void initState() {
    super.initState();
    _code = widget.myCode;
    if (_code == null) unawaited(_loadCode());
  }

  @override
  void dispose() {
    _flashTimer?.cancel();
    _input.dispose();
    super.dispose();
  }

  /* 친구 탭이 _me 를 받는 그 /me 로. */
  Future<void> _loadCode() async {
    if (_codeFailed) setState(() => _codeFailed = false);
    final r = await widget.api.me();
    if (!mounted) return;
    final u = r.ok ? (r.body['user'] as Map?)?.cast<String, dynamic>() : null;
    final c = u?['inviteCode'];
    setState(() {
      _code = c is String && c.trim().isNotEmpty ? c.trim() : null;
      _codeFailed = _code == null;
    });
    if (u != null && _code != null) widget.onMe?.call(u);
  }

  void _say(String message) {
    _flashTimer?.cancel();
    setState(() => _flash = message);
    _flashTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _flash = null);
    });
  }

  Future<void> _copy() async {
    final code = _code;
    if (code == null) return;
    await Clipboard.setData(ClipboardData(text: code));
    if (mounted) _say('복사했어요');
  }

  Future<void> _share(BuildContext anchor) async {
    final code = _code;
    if (code == null) return;
    final opened = await shareInviteText(anchor, code, widget.api.baseUrl);
    if (!opened && mounted) _say('보낼 글을 복사했어요');
  }

  Future<void> _submit() async {
    if (_sending || _input.text.trim().isEmpty) return;
    /* 모양이 틀린 코드는 서버에 묻지 않습니다 — 칸 밑에 바로. */
    if (!isInviteCode(cleanInviteCode(_input.text))) {
      setState(() => _error = kInviteCodeInvalid);
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    final r = await requestFriendByCode(widget.api, _input.text);
    if (!mounted) return;
    if (r != null && r.ok) {
      Navigator.of(context).pop(r);
      return;
    }
    setState(() {
      _sending = false;
      _error = r == null ? null : friendRequestMessage(r);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    /* 키보드가 올라오는 만큼 **같은 프레임에** 줄입니다. 다이얼로그는 원래 키보드 높이를
       100ms 뒤따라 줄어드는데, 칸은 그보다 먼저(키보드가 뜬 프레임에) 커서가 보이게 스크롤을
       끝냅니다 — 그 뒤에 다이얼로그가 줄어서 작은 폰에서는 코드 칸이 「요청 보내기」 밑으로
       숨었습니다. 키보드 몫은 여기서 빼고 다이얼로그에는 없는 것으로 넘깁니다(테스터 인사
       시트와 같은 방식). */
    final kb = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: kb),
      child: MediaQuery.removeViewInsets(
        context: context,
        removeBottom: true,
        child: _dialog(t),
      ),
    );
  }

  Widget _dialog(ThemeData t) {
    return AlertDialog(
      title: const Text('친구 추가'),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _mine(t),
          const SizedBox(height: 18),
          Text('친구 코드', style: t.textTheme.labelMedium?.copyWith(color: t.hintColor)),
          const SizedBox(height: 6),
          TextField(
            key: const Key('add-friend-input'),
            controller: _input,
            /* 코드(K7M2QX9D)는 낱말이 아닙니다 — 자동 교정 · 추천이 켜져 있으면 키보드가
               멋대로 고쳐 보냅니다. 대문자 키보드로 열고, 소문자로 쳐도 대문자로 바꿉니다.
               받은 글을 통째로 붙여 넣으면 그 안의 코드만 남깁니다([InviteCodeFormatter]).
               완료 키는 곧 「요청 보내기」. */
            autocorrect: false,
            enableSuggestions: false,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: const [InviteCodeFormatter()],
            maxLength: kInviteCodeLength,
            buildCounter: _noCounter,
            textInputAction: TextInputAction.done,
            /* 칸 밑의 빨간 줄(틀린 코드 · 서버의 까닭)까지 키보드 위에 보이게. */
            scrollPadding: const EdgeInsets.fromLTRB(20, 20, 20, 56),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              hintText: '예: $kInviteCodeExample',
              border: const OutlineInputBorder(),
              isDense: true,
              errorText: _error,
              errorMaxLines: 3,
            ),
          ),
          /* 클립보드에 글이 있으면 「초대 코드 붙여넣기」 — 누르면 코드만 칸에(아이폰은 이때만
             클립보드를 읽습니다). 보내는 것은 여전히 「요청 보내기」. */
          InvitePasteChip(
            onCode: (code) {
              _input.value = TextEditingValue(
                  text: code, selection: TextSelection.collapsed(offset: code.length));
              setState(() => _error = null);
            },
            onNone: () => setState(() => _error = kInvitePasteNone),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('취소')),
        ListenableBuilder(
          listenable: _input,
          builder: (_, __) => FilledButton(
            onPressed: _sending || _input.text.trim().isEmpty ? null : _submit,
            child: _sending
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('요청 보내기'),
          ),
        ),
      ],
    );
  }

  /* 내 코드 칸 — 이름표(잠깐 「복사했어요」 로 바뀜) · 큰 코드 · 「보내기」. */
  Widget _mine(ThemeData t) {
    final c = mb(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(color: c.accentSub, borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(_flash ?? '내 코드',
            key: const Key('add-friend-label'),
            style: t.textTheme.labelMedium?.copyWith(
                color: _flash != null ? c.ok : t.hintColor,
                fontWeight: _flash != null ? FontWeight.w700 : null)),
        const SizedBox(height: 2),
        SizedBox(height: 44, child: _codeView(t)),
        const SizedBox(height: 8),
        Builder(
          builder: (anchor) => FilledButton.tonalIcon(
            key: const Key('add-friend-share'),
            onPressed: _code == null ? null : () => _share(anchor),
            icon: const Icon(LucideIcons.share2, size: 18),
            label: const Text('보내기'),
          ),
        ),
      ]),
    );
  }

  Widget _codeView(ThemeData t) {
    final code = _code;
    if (code != null) {
      /* 크게 · 자간을 벌려 — 불러 주거나 보고 옮겨 적을 수 있게. 좁은 폰 · 큰 글씨에서도
         한 줄에 들어가게 줄여 맞춥니다. 누르면 복사 — 옆의 작은 아이콘이 그 표시입니다. */
      return InkWell(
        key: const Key('add-friend-code'),
        borderRadius: BorderRadius.circular(8),
        onTap: _copy,
        child: Row(children: [
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(code,
                  style: t.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 3,
                      fontFeatures: const [FontFeature.tabularFigures()])),
            ),
          ),
          const SizedBox(width: 6),
          Icon(_flash == '복사했어요' ? LucideIcons.check : LucideIcons.copy,
              size: 18, color: t.hintColor, semanticLabel: '복사'),
        ]),
      );
    }
    if (_codeFailed) {
      return Row(children: [
        Flexible(
            child: Text('못 불러왔어요', style: t.textTheme.bodySmall?.copyWith(color: t.hintColor))),
        TextButton(
            key: const Key('add-friend-code-retry'), onPressed: _loadCode, child: const Text('다시')),
      ]);
    }
    return const Align(
      alignment: Alignment.centerLeft,
      child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
    );
  }
}

/// 글자 수 표시(0/8)를 안 그립니다 — 여덟 칸이 다 차면 코드도 끝이라 셀 것이 없습니다.
Widget? _noCounter(BuildContext _, {required int currentLength, required bool isFocused, int? maxLength}) =>
    null;

/* --- 친구 코드 — 모양 · 다듬기 ------------------------------------------------
 *
 * 코드는 서버가 만듭니다(server/db.js inviteCode()): **여덟 글자**, 글자판
 * 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789' — 헷갈리는 I · O · 0 · 1 이 없습니다. 서버의 초대
 * 페이지(server.js 의 INVITE_ALPHABET)도 같은 글자판입니다. 셋 중 하나만 바뀌면 멀쩡한
 * 코드가 "틀린 코드" 가 됩니다.
 *
 * 칸의 예시가 「예: ab12cd」(여섯 글자 · 소문자 · 1)였습니다 — 실제 코드와 모양이 달라서
 * 예시를 보고 따라 친 사람이 헷갈렸습니다. 예시도 실제 모양으로 둡니다(지어낸 코드).
 *
 * 모양이 틀린 코드는 **서버에 묻지 않습니다.** 서버의 「그런 코드를 가진 사람이 없습니다」 는
 * 오타인지 없는 사람인지 가려 주지 못합니다 — 모양이 틀렸으면 "다시 확인" 이 맞는 말입니다.
 * 소문자는 틀린 것이 아닙니다 — 대문자로 바꿉니다(서버도 그렇게 찾습니다).
 * -------------------------------------------------------------------------- */

/// 친구 코드 글자판 — server/db.js inviteCode() 와 같아야 합니다.
const String kInviteCodeAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

/// 친구 코드 길이.
const int kInviteCodeLength = 8;

/// 칸의 예시 — 실제 모양의 지어낸 코드.
const String kInviteCodeExample = 'K7M2QX9D';

/// 모양이 틀린 코드를 넣었을 때.
const String kInviteCodeInvalid = '코드를 다시 확인해 주세요 — 영문·숫자 8자예요';

final RegExp _inviteCodeRe = RegExp('^[$kInviteCodeAlphabet]{$kInviteCodeLength}\$');

/* 글 속에서 코드를 찾는 자리 셋 — 초대 링크(…/i/코드), 「코드: …」 · 「코드 …」 이름표,
   그리고 앞뒤가 영문 · 숫자가 아닌 여덟 글자 토막. 앞의 것일수록 확실합니다. */
final RegExp _codeInLink = RegExp(r'/i/([A-Za-z0-9]{8})(?![A-Za-z0-9])');
final RegExp _codeAfterLabel = RegExp(r'코드\s*[:：]?\s*([A-Za-z0-9]{8})(?![A-Za-z0-9])');
final RegExp _codeAlone = RegExp(r'(?<![A-Za-z0-9])([A-Za-z0-9]{8})(?![A-Za-z0-9])');

/// 서버가 만드는 모양의 코드인가 — 대문자 여덟 글자, 글자판 안의 글자만.
bool isInviteCode(String code) => _inviteCodeRe.hasMatch(code);

/// 넣은 글에서 친구 코드를 골라 대문자로 돌려줍니다.
///
/// 코드만 넣었으면 사이의 빈칸 · 줄표만 뺍니다(「abcd 2345」 → 「ABCD2345」). 「보내기」 로 받은
/// 글을 통째로 붙여 넣으면 그 안의 초대 링크(…/i/코드)나 「코드 …」 에서 코드만 꺼냅니다 —
/// 폰에서 글 한가운데 여덟 글자만 골라 복사하기는 어렵습니다. 옛 글(「내 친구 코드: …」)도
/// 됩니다. 아무것도 못 찾으면 빈칸 · 줄표만 뺀 대문자 글을 그대로 돌려줍니다 — 모양이
/// 맞는지는 [isInviteCode] 로 따로 봅니다.
String cleanInviteCode(String input) {
  final whole = input.replaceAll(RegExp(r'[\s\-]'), '').toUpperCase();
  if (isInviteCode(whole)) return whole;
  String? pick(RegExp re) {
    for (final m in re.allMatches(input)) {
      final c = m[1]!.toUpperCase();
      if (isInviteCode(c)) return c;
    }
    return null;
  }

  return pick(_codeInLink) ?? pick(_codeAfterLabel) ?? pick(_codeAlone) ?? whole;
}

/// 친구 코드 칸의 입력 다듬기 — 대문자로, 영문 · 숫자만, 여덟 글자까지.
///
/// 칸은 여덟 글자로 막혀 있어서(maxLength) 그냥 두면 받은 글을 통째로 붙여 넣었을 때 글의
/// **앞머리 여덟 글자**가 남습니다. 그래서 길이를 자르기 전에 이 다듬기가 먼저 글 속의 코드를
/// 찾아 그것만 남깁니다([cleanInviteCode]). 키보드가 글자를 조합하는 중(밑줄)에는 손대지
/// 않습니다 — 조합 중인 글자를 바꾸면 안드로이드 키보드가 글자를 두 번 넣기도 합니다.
class InviteCodeFormatter extends TextInputFormatter {
  const InviteCodeFormatter();

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final raw = newValue.text;
    final composing = newValue.composing.isValid && !newValue.composing.isCollapsed;
    if (composing && raw.length <= kInviteCodeLength) return newValue;
    final found = cleanInviteCode(raw);
    var next = isInviteCode(found) ? found : raw.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');
    if (next.length > kInviteCodeLength) next = next.substring(0, kInviteCodeLength);
    if (next == raw) return newValue;
    /* 대문자로만 바뀌었으면 커서는 그 자리, 글자가 빠지거나 바뀌었으면 끝으로. */
    return TextEditingValue(
      text: next,
      selection: next.length == raw.length
          ? newValue.selection
          : TextSelection.collapsed(offset: next.length),
    );
  }
}

/* --- 「초대 코드 붙여넣기」 ---------------------------------------------------------
 *
 * 앱이 없던 친구가 초대 페이지의 설치 단추를 누르면, 페이지가 그 순간 「Mybody 초대 <코드>
 * https://<서버>/i/<코드>」 를 클립보드에 넣어 둡니다(서버 — 누른 손길이라 브라우저가 허락합니다).
 * 깔고 연 앱이 그것을 받으면 코드를 옮겨 칠 일이 없습니다.
 *
 * 아이폰은 앱이 클립보드를 **읽는 순간** 「붙여넣기 허용」 창을 띄웁니다 — 켜자마자 그 창이
 * 뜨면 무슨 앱인지도 모르고 거절합니다. 그래서 스스로 읽지 않고, 클립보드에 글이 **있는지만**
 * 봅니다(Clipboard.hasStrings — 내용은 안 읽어서 창이 안 뜸). 있으면 코드 칸 밑에 작은 칩 하나,
 * 누르면 그때 읽어 코드만 칸에 채웁니다 — 보내는 것은 그 옆의 「요청」 입니다(사람이 봅니다).
 * 안드로이드도 같은 칩을 둡니다 — 탭 화면이 처음 설 때 한 번 묻는 것(셸)을 넘겼거나, 뒤에
 * 코드를 받은 사람도 같은 한 번으로 채웁니다. 앱으로 돌아올 때마다(카톡에서 복사하고 오면)
 * 있는지 다시 봅니다. 친구 탭의 「친구 추가」 와 테스터 인사 3쪽이 같이 씁니다.
 * -------------------------------------------------------------------------- */

/// 클립보드에 글이 있는가 · 그 글 — 시험은 바꿔 끼웁니다(플랫폼 채널 대신).
@visibleForTesting
Future<bool> Function() invitePasteHasStrings = Clipboard.hasStrings;

/// 클립보드의 글(누른 순간에만 읽습니다).
@visibleForTesting
Future<String?> Function() invitePasteRead =
    () async => (await Clipboard.getData(Clipboard.kTextPlain))?.text;

/// 클립보드에 초대 코드가 없을 때.
const String kInvitePasteNone = '복사한 글에 초대 코드가 없어요';

/// 「초대 코드 붙여넣기」 칩. 클립보드에 글이 있을 때만 보이고, 누르면 읽어서 코드를
/// [onCode] 로(대문자 여덟 글자). 코드가 없으면 [onNone].
class InvitePasteChip extends StatefulWidget {
  const InvitePasteChip({super.key, required this.onCode, this.onNone});
  final ValueChanged<String> onCode;
  final VoidCallback? onNone;

  @override
  State<InvitePasteChip> createState() => _InvitePasteChipState();
}

class _InvitePasteChipState extends State<InvitePasteChip> with WidgetsBindingObserver {
  bool _has = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_check());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_check());
  }

  /* 있는지만 — 읽지 않습니다(머리 주석). 못 물으면 없는 것으로(칩이 안 보일 뿐). */
  Future<void> _check() async {
    var has = false;
    try {
      has = await invitePasteHasStrings();
    } catch (_) {}
    if (mounted && has != _has) setState(() => _has = has);
  }

  Future<void> _paste() async {
    String? text;
    try {
      text = await invitePasteRead();
    } catch (_) {}
    if (!mounted) return;
    final code = cleanInviteCode(text ?? '');
    if (isInviteCode(code)) {
      widget.onCode(code);
    } else {
      widget.onNone?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_has) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerLeft,
      child: ActionChip(
        key: const Key('invite-paste'),
        avatar: const Icon(LucideIcons.clipboardPaste, size: 16),
        label: const Text('초대 코드 붙여넣기'),
        visualDensity: VisualDensity.compact,
        onPressed: _paste,
      ),
    );
  }
}

/* --- 보내는 글 · 초대 링크 ------------------------------------------------------
 *
 * 친구에게 보내는 것은 **링크 하나**입니다 — <서버 주소>/i/<코드>. 앱이 있으면 이 주소가
 * 곧바로 앱을 엽니다(안드로이드 App Links · 아이폰 연결된 도메인 — invite_link.dart). 아직
 * 확인이 안 된 폰이면 서버의 초대 페이지(server.js)가 뜨고 그 단추가 앱을 엽니다
 * (mybody://invite/<코드>). 어느 길이든 앱이 보내고, 링크로 온 코드라 곧바로 친구가 됩니다(주인
 * 의견 48 — 코드 주인의 수락 없이, 아래 requestFriendByCode). 앱이 없으면 **받는 사람의
 * 기기에 맞는** 설치 안내가 나오고, 깔고 나면 코드가 따라옵니다(플레이 설치 referrer ·
 * 클립보드 — install_referrer.dart · [InvitePasteChip]).
 *
 * 예전 글에는 아이폰 · 안드로이드 설치 주소를 둘 다 실었습니다. 그런데 주인이 갤럭시에서
 * 아이폰 친구가 보낸 초대를 받았더니 TestFlight 가 먼저 떴습니다 — 보내는 사람이 받는
 * 사람의 기기를 모릅니다. 그래서 글에는 설치 주소를 싣지 않고, 기기는 페이지가 가립니다.
 * 링크가 안 열리는 사람을 위해 코드와 넣을 곳을 한 줄 덧붙입니다.
 * -------------------------------------------------------------------------- */

/// 초대 링크 — <서버 주소>/i/<코드>. 주소 끝의 / 는 뗍니다.
String inviteUrl(String base, String code) =>
    '${base.trim().replaceAll(RegExp(r'/+$'), '')}/i/${code.trim().toUpperCase()}';

/// 「보내기」 로 나가는 글. [base] 는 이 앱이 쓰는 서버 주소(Api.baseUrl).
///
/// 서버 주소가 없으면(서버 없이 쓰는 중) 링크를 만들 수 없어 코드와 넣을 곳만 보냅니다.
String inviteShareText(String code, String base) {
  final c = code.trim().toUpperCase();
  if (base.trim().isEmpty) {
    return 'Mybody 같이 해요!\n앱에서 친구 탭 → 친구 추가에 코드 $c 를 넣어 주세요';
  }
  return 'Mybody 같이 해요! 링크를 누르면 바로 친구가 돼요\n'
      '${inviteUrl(base, c)}\n'
      '(앱에서 친구 탭 → 친구 추가에 코드 $c 를 넣어도 돼요)';
}

/// 공유 시트를 여는 길. 시험에서는 바꿔 끼웁니다 — 진짜 공유 시트는 플랫폼 채널이라
/// 시험 안에서는 열리지 않습니다. [origin] 은 아이패드에서 말풍선이 나올 자리.
@visibleForTesting
Future<void> Function(String text, Rect? origin) inviteShareOut = _shareOut;

Future<void> _shareOut(String text, Rect? origin) async {
  await SharePlus.instance.share(ShareParams(text: text, sharePositionOrigin: origin));
}

/// 이 기기에서 「보내기」 로 내보낸 **내** 코드(마지막 것). 셸이 탭 화면에서 클립보드를 한 번
/// 읽을 때(안드로이드 — invite_link.dart clipboardInviteOnce) 이 코드는 친구의 초대로 보지
/// 않습니다. 공유 시트의 「복사」 나 공유가 안 돼 복사해 둔 글은 **내** 초대 링크라, 테스터 인사
/// 3쪽에서 보내고 닫은 바로 그때 클립보드를 읽으면 「초대 코드 <내 코드> 로 친구 요청할까요?」 를
/// 묻게 됩니다.
const String kMyInviteCodeKey = 'mybody.invite.mine.v1';

/// [kMyInviteCodeKey] 에 적습니다. 모양이 틀리면 안 적습니다. 못 적어도 조용히 — 한 번 더
/// 묻게 될 뿐입니다.
Future<void> rememberMyInviteCode(String code) async {
  final c = code.trim().toUpperCase();
  if (!isInviteCode(c)) return;
  try {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(kMyInviteCodeKey, c);
  } catch (_) {}
}

/// 내 코드([code])로 만든 보낼 글([inviteShareText] — [base] 는 Api.baseUrl)을 공유 시트로
/// 엽니다. [anchor] 는 누른 단추(아이패드의 말풍선 자리). 내 코드는 이 기기에 적어 둡니다
/// ([rememberMyInviteCode] — 그 글이 클립보드에 남아도 친구의 초대로 묻지 않게).
/// 공유 시트가 없거나 실패하면 글을 복사해 두고 false — 부른 쪽이 "복사했어요" 를 알립니다.
Future<bool> shareInviteText(BuildContext anchor, String code, String base) async {
  final text = inviteShareText(code, base);
  final box = anchor.findRenderObject();
  final origin =
      box is RenderBox && box.hasSize ? box.localToGlobal(Offset.zero) & box.size : null;
  await rememberMyInviteCode(code);
  try {
    await inviteShareOut(text, origin);
    return true;
  } catch (_) {
    await Clipboard.setData(ClipboardData(text: text));
    return false;
  }
}

/* --- 친구 코드로 요청 ---------------------------------------------------------
 *
 * 친구 탭의 「친구 추가」 다이얼로그, 테스터 인사 3쪽의 코드 칸, 초대 링크가 **이 함수
 * 하나**로 보냅니다. 요청 필드 이름을 틀려서(inviteCode 가 아니라 code) 앱에서 친구 추가가
 * 한 번도 안 된 적이 있습니다 — 길이 둘이면 그런 것이 한쪽에만 남습니다.
 *
 * 실패 문구는 서버가 준 까닭입니다(「그런 코드를 가진 사람이 없습니다」 · 못 닿으면
 * 「서버에 닿지 못했습니다」). 흔한 셋만 앱의 말투로 바꿉니다([friendRequestMessage]) —
 * 초대 링크를 두 번 누른 사람 · 내 링크를 눌러 본 사람에게 "자기 자신은 추가할 수 없습니다"
 * 는 꾸중처럼 읽힙니다. **큐에 담지 않습니다** — 수락 · 거절과 달리 요청은 서버가 코드를
 * 봐야 되는지가 정해지고, 그 답을 지금 보여 줘야 합니다. 나중에 조용히 보냈다가 "없는
 * 코드" 로 실패하면 알릴 곳이 없습니다. 그래서 못 닿으면 그 자리에서 실패로 보이고, 다시
 * 누르면 됩니다.
 *
 * **초대 링크로 온 코드는 곧바로 친구입니다**(주인 의견 48 "초대 링크로 오면 바로 친구되게 해").
 * [viaLink] 를 켜면 서버가 요청이 아니라 그 자리에서 맺습니다 — 코드 주인이 링크를 골라 보낸
 * 것이 이미 초대라서, 한 번 더 수락을 기다리게 하지 않습니다. 켜는 곳은 셸 하나이고, 그것도
 * 링크(mybody:// · https 앱 링크)와 설치 추천인(플레이)으로 받은 코드뿐입니다. 손으로 친 코드 ·
 * 클립보드에서 찾아 「요청」 을 누른 코드는 예전처럼 요청 → 수락입니다 — 클립보드의 여덟
 * 글자는 누가 넣었는지 모릅니다(invite_link.dart PendingInvite.link).
 * 링크여도 코드 주인이 나를 거절 · 끊기 · 차단한 적이 있으면 서버가 요청으로 받습니다(server/db.js
 * friend_refusals — 옛 링크로 곧바로 되돌아오지 못하게). 그래서 말은 언제나 서버의 답대로입니다.
 * -------------------------------------------------------------------------- */

/// 친구 코드로 친구 요청을 보냅니다. 코드가 비었으면 보내지 않고 null. 모양이 틀리면
/// 서버에 묻지 않고 실패(까닭 [kInviteCodeInvalid])를 돌려줍니다. [viaLink] 면 초대 링크로 온
/// 코드라고 알려 곧바로 친구가 됩니다(위 주석).
Future<ApiResult?> requestFriendByCode(Api api, String input, {bool viaLink = false}) async {
  final code = cleanInviteCode(input);
  if (code.isEmpty) return null;
  if (!isInviteCode(code)) {
    return const ApiResult(400, {'ok': false, 'reason': kInviteCodeInvalid});
  }
  return api.requestFriend(code, viaLink: viaLink);
}

/// 요청이 곧바로 친구가 됐나 — 초대 링크로 왔거나, 상대가 먼저 나에게 요청해 둔 사이면 서버가
/// 그 자리에서 맺습니다(`status: 'accepted'`). 그때 "수락을 기다려요" 라고 하면 틀린 말입니다.
bool becameFriends(ApiResult r) => r.ok && r.body['status'] == 'accepted';

/// 친구 요청의 답을 한 줄로 — 친구 탭 · 초대 링크가 같은 말을 합니다(테스터 인사는 실패
/// 문구만 같이 씁니다). 이름은 서버가 **친구가 됐을 때만** 실어 줍니다(`friend: {name}` —
/// server.js POST /friends/request). 요청만 간 때는 이름 없는 말이 나갑니다. 옛 모양
/// (displayName · other.displayName)도 읽습니다. 링크를 또 누른 사람(이미 친구 — `already`)에게는
/// 「이미 친구예요」 — 실패가 아니라 이미 된 일입니다.
String friendRequestMessage(ApiResult r) {
  if (!r.ok) {
    return switch (r.body['reason']) {
      '이미 친구입니다' => '이미 친구예요',
      '자기 자신은 추가할 수 없습니다' => '내 코드예요',
      '이미 보낸 요청입니다' => '이미 요청을 보냈어요',
      _ => r.reason,
    };
  }
  final friend = r.body['friend'];
  final other = r.body['other'];
  final n = (friend is Map ? friend['name'] : null) ??
      r.body['displayName'] ??
      (other is Map ? other['displayName'] : null);
  final name = n is String && n.trim().isNotEmpty ? n.trim() : null;
  if (becameFriends(r)) {
    if (r.body['already'] == true) return name == null ? '이미 친구예요' : '이미 $name님과 친구예요';
    return name == null ? '친구가 됐어요' : '$name님과 친구가 됐어요';
  }
  return name == null ? '친구 요청을 보냈어요' : '$name님에게 친구 요청을 보냈어요';
}

class _RequestRow extends StatelessWidget {
  const _RequestRow({required this.person, required this.onDone, this.defaults});
  final dynamic person;
  final Future<void> Function() onDone;
  /// 내 기본 공유 — 수락하면 이 값이 그대로 그 친구에게 가는 쪽이 됩니다.
  final Map<String, bool>? defaults;

  @override
  Widget build(BuildContext context) {
    final api = Scope.apiOf(context);
    final t = Theme.of(context);
    return MbCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Avatar(displayName: '${person['displayName']}', id: '${person['id']}',
              avatarUrl: person['avatar'] as String?, size: 36),
          const SizedBox(width: 10),
          Expanded(child: Text('${person['displayName']}')),
          /* 못 닿으면 큐에 맡기되 **누른 순간의 로그인**으로(4차 검토) — 서버를 기다리는 사이(최대 20초)
             로그아웃 → 다른 계정 가입이 끼면, 맡기는 순간의 로그인으로 적힌 A 의 수락이 B 명의로
             나갔습니다(u_f 가 B 에게도 요청해 두었으면 B 가 모르는 사이 친구가 맺어짐). 누른 계정의 일로
             남아 그 계정으로 돌아올 때 나갑니다(sync_queue.dart). */
          TextButton(
            onPressed: () async {
              final id = '${person['id']}';
              final q = Scope.queueOf(context);
              final by = q?.signer;
              final r = await api.declineFriend(id);
              if (!r.ok && q != null && by != null && _worthRetrying(r)) {
                q.add('decline', {'userId': id}, by: by);
              }
              if (context.mounted) await onDone();
            },
            child: const Text('거절'),
          ),
          FilledButton(
            onPressed: () async {
              final id2 = '${person['id']}';
              final q2 = Scope.queueOf(context);
              final by = q2?.signer;
              final r = await api.acceptFriend(id2);
              if (!r.ok && q2 != null && by != null && _worthRetrying(r)) {
                q2.add('accept', {'userId': id2}, by: by);
              }
              if (context.mounted && !r.ok) toast(context, r.reason);
              if (context.mounted) await onDone();
            },
            child: const Text('수락'),
          ),
        ]),
        /* 수락을 누르는 그 순간에 무엇이 나가는지 — 기본 공유에서 몸 숫자를 켜
           둔 사람이 "기본 비공개" 를 믿고 누르면 곧바로 체중이 나갑니다. */
        if (defaults != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: ShareReach(
                flags: defaults!,
                lead: '수락하면 보여 줄 것',
                style: t.textTheme.labelSmall?.copyWith(color: t.hintColor)),
          ),
      ]),
    );
  }
}

class _FriendRow extends StatelessWidget {
  const _FriendRow({required this.person});
  final Map<String, dynamic> person;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final snap = (person['snapshot'] as Map?)?.cast<String, dynamic>();
    final planned = snap?['plannedDays'];
    final kept = snap?['keptDays'];
    /* 오늘 할 일 — 상세의 오늘 카드와 **같은 함수**로 만듭니다. 목록에서
       "헬스 했네" 하고 들어갔는데 상세가 다른 말을 하면 어느 쪽을 믿어야
       할지 모릅니다. 공유한 것이 없으면 줄 자체가 없습니다. */
    final items = snap == null
        ? const <TodayItem>[]
        : friendTodayItems(snap, Scope.of(context).store.dayKey());

    return Row(children: [
      Avatar(displayName: '${person['displayName']}', id: '${person['id']}',
          avatarUrl: person['avatar'] as String?, size: 40),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${person['displayName']}', style: t.textTheme.titleSmall),
          if (items.isNotEmpty) _TodayStrip(items: items),
          /* 친구가 **안 한 것**은 말하지 않습니다. 공유가 꺼져 있거나
             아직 안 올린 것도 "안 했다" 가 아닙니다. */
          Text(
            planned == null
                ? '이번 주 공유한 것이 없습니다'
                : '이번 주 ${n0(kept)}/${n0(planned)}일 운동',
            style: t.textTheme.labelSmall?.copyWith(color: t.hintColor),
          ),
          if (snap?['streaks'] is Map)
            Text('운동 ${n0((snap!['streaks'] as Map)['workoutDays'])}일째 · '
                '식단 ${n0((snap['streaks'] as Map)['foodDays'])}일째',
                style: t.textTheme.labelSmall?.copyWith(color: t.hintColor)),
          if (snap != null && snap['weightKg'] != null)
            Text('${n1(snap['weightKg'])}kg · 근 ${n1(snap['smmKg'])} · 지 ${n1(snap['bfmKg'])}',
                style: t.textTheme.labelSmall?.copyWith(color: t.hintColor)),
        ]),
      ),
      if (core.jsTruthy(snap?['checkedIn']))
        const Pill('이번 주 기록', tone: Tone.ok),
      if (needsNudge(snap)) _PokeButton(person: person, compact: true),
      const Icon(LucideIcons.chevronRight),
    ]);
  }
}

/* 독촉 띠 — "OO님이 운동하라고 콕 찔렀어요". */
class _PokeBanner extends StatelessWidget {
  const _PokeBanner({required this.poke, required this.onDismiss});
  final Map<String, dynamic> poke;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = mb(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      decoration: BoxDecoration(
          color: c.okBg, borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.ok.withValues(alpha: 0.35))),
      child: Row(children: [
        Icon(LucideIcons.bellRing, size: 18, color: c.ok),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(PokeBox.title(poke),
                style: t.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
            Text('${PokeBox.body(poke)} · ${dateK(poke['at'])}',
                style: t.textTheme.labelSmall?.copyWith(color: t.hintColor)),
          ]),
        ),
        IconButton(
          tooltip: '치우기',
          iconSize: 18,
          visualDensity: VisualDensity.compact,
          onPressed: onDismiss,
          icon: const Icon(LucideIcons.x),
        ),
      ]),
    );
  }
}

/* 독촉 버튼 — 목록에선 아이콘만, 상세에선 글자와 함께.
   주인의 말: "하루한번가능>1초에 한번으로 · '1분에 한사람에게 10번 이상이면 30분 제한'으로 ·
   사람마다 카운팅". 세는 것은 서버입니다(server/db.js poke) — 여기서는 보내고 나서도 단추를
   그대로 두고, 서버가 쉬라고 하면(limited · until) 그때까지만 끕니다. 친구마다 따로입니다. */
class _PokeButton extends StatefulWidget {
  const _PokeButton({required this.person, this.compact = false});
  final Map<String, dynamic> person;
  final bool compact;

  @override
  State<_PokeButton> createState() => _PokeButtonState();
}

class _PokeButtonState extends State<_PokeButton> {
  bool _busy = false;
  DateTime? _restUntil;
  Timer? _restTimer;

  bool get _resting => _restUntil != null && DateTime.now().isBefore(_restUntil!);

  @override
  void dispose() {
    _restTimer?.cancel();
    super.dispose();
  }

  /* 서버가 쉬라고 했으면 그때까지 단추를 끄고, 끝나면 저절로 다시 켭니다. until 을 못 읽으면
     30분(서버 규칙과 같게). */
  void _restFrom(ApiResult r) {
    if (r.body['limited'] != true) return;
    final until = DateTime.tryParse('${r.body['until'] ?? ''}')?.toLocal() ??
        DateTime.now().add(const Duration(minutes: 30));
    final left = until.difference(DateTime.now());
    if (left <= Duration.zero) return;
    _restUntil = until;
    _restTimer?.cancel();
    _restTimer = Timer(left, () {
      if (mounted) setState(() => _restUntil = null);
    });
  }

  Future<void> _send() async {
    if (_busy || _resting) return;
    setState(() => _busy = true);
    final api = Scope.apiOf(context);
    final name = '${widget.person['displayName']}';
    final r = await api.poke('${widget.person['id']}');
    if (!mounted) return;
    setState(() {
      _busy = false;
      _restFrom(r);
    });
    if (r.ok) {
      toast(context, _resting ? '$name님에게 보냈어요 — 이제 30분 쉬어요' : '$name님에게 운동 독촉을 보냈습니다');
    } else {
      toast(context, r.reason);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final off = _resting;
    if (widget.compact) {
      return IconButton(
        tooltip: off ? '잠시 쉬는 중' : '운동 독촉',
        visualDensity: VisualDensity.compact,
        onPressed: off ? null : _send,
        icon: Icon(LucideIcons.bellRing, size: 20,
            color: off ? t.hintColor : t.colorScheme.primary),
      );
    }
    return OutlinedButton.icon(
      onPressed: off ? null : _send,
      icon: const Icon(LucideIcons.bellRing, size: 18),
      label: Text(off ? '잠시 쉬는 중' : '운동 독촉하기'),
    );
  }
}

/* --- P16 친구 상세 ---------------------------------------------------------- */

/* 공유 스위치 이름은 share_defaults.dart 의 kShareFields — 「기본으로 보여
   주는 것」 카드와 같은 상수를 씁니다. 두 화면에서 같은 스위치가 다른
   이름이면 다른 것으로 읽힙니다. */

/// 친구 한 사람. **친구에 대한 것**이 먼저입니다 — 스트릭, 오늘 할 일,
/// 오늘 식단, 이번 주 운동. 내가 뭘 보여 주는지는 아래에 접어 둡니다.
class FriendDetailScreen extends StatefulWidget {
  const FriendDetailScreen({super.key, required this.person});
  final Map<String, dynamic> person;

  @override
  State<FriendDetailScreen> createState() => _FriendDetailScreenState();
}

class _FriendDetailScreenState extends State<FriendDetailScreen> {
  Map<String, dynamic>? _share;
  Map<String, dynamic>? _snap;
  bool _busy = true;
  bool _started = false;
  /// 서버에 못 닿아 마지막으로 본 공유 설정을 보여 주는 중인가.
  bool _shareFromCache = false;
  /// 스위치를 빨리 여럿 누르면 답이 뒤바뀌어 올 수 있습니다 — 마지막 것의 답만 씁니다.
  int _shareSeq = 0;

  String get _shareKey => shareCacheKey('${widget.person['id']}');

  /* 공유 설정도 캐시합니다. 비행기 모드에서 "0개 켜짐" 에 스위치가 전부
     꺼진 채로 보이면, 사람은 "다 꺼졌네" 하고 다시 켭니다 — 실제로는 셋이
     켜져 있었는데요. 여기서 바꾼 것도 같이 기억해 둡니다. */
  Future<void> _rememberShare(Map<String, dynamic> share) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_shareKey, jsonEncode(share));
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> _recallShare() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final s = sp.getString(_shareKey);
      return s == null ? null : (jsonDecode(s) as Map).cast<String, dynamic>();
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _snap = (widget.person['snapshot'] as Map?)?.cast<String, dynamic>();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _load();
    }
  }

  Future<void> _load() async {
    final api = Scope.apiOf(context);
    final id = '${widget.person['id']}';
    final both = await Future.wait([api.getShare(id), api.friendSnapshots(id, limit: 1)]);
    final r = both[0];
    final sn = both[1];
    var share = r.ok ? (r.body['share'] as Map?)?.cast<String, dynamic>() : null;
    var fromCache = false;
    if (share != null) {
      await _rememberShare(share);
    } else {
      share = await _recallShare();
      fromCache = share != null;
    }
    if (!mounted) return;
    setState(() {
      _share = share ?? {};
      _shareFromCache = fromCache;
      final rows = sn.ok ? (sn.body['rows'] as List?) : null;
      if (rows != null && rows.isNotEmpty) _snap = (rows.first as Map).cast<String, dynamic>();
      _busy = false;
    });
  }

  static bool _hasBody(Map<String, dynamic> s) => const [
        'weightKg', 'smmKg', 'bfmKg', 'dWeightKg', 'dSmmKg', 'dBfmKg', 'progressPct'
      ].any((k) => s[k] != null);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final snap = _snap ?? const <String, dynamic>{};
    final streaks = (snap['streaks'] as Map?)?.cast<String, dynamic>();
    final today = (snap['today'] as Map?)?.cast<String, dynamic>();
    final week = (snap['week'] as Map?)?.cast<String, dynamic>();
    final onCount = kShareFields.where((f) => core.jsTruthy(_share?[f.$1])).length;

    return Scaffold(
      appBar: AppBar(title: Text('${widget.person['displayName']}')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        _FriendHeader(person: widget.person, snap: snap, streaks: streaks),
        _FriendTodayCard(snap: snap),
        _FriendDietCard(today: today),
        _FriendWeekCard(snap: snap, week: week),
        if (_hasBody(snap)) _FriendBodyCard(snap: snap),

        /* 내가 보여 주는 것 — 접어 둡니다. 여기 오는 사람은 친구를 보러
           온 것이지 설정을 만지러 온 것이 아닙니다. */
        MbCard(
          child: Theme(
            data: t.copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              title: Text('내가 이 친구에게 보여 주는 것',
                  style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              subtitle: Text(
                  _busy
                      ? '불러오는 중'
                      : '$onCount개 켜짐${_shareFromCache ? ' · 서버에 못 닿아 마지막으로 본 설정' : ''}',
                  style: t.textTheme.labelSmall?.copyWith(color: t.hintColor)),
              children: [
                RichishText(
                  '끄면 **서버가 안 보냅니다**',
                  style: t.textTheme.bodySmall?.copyWith(color: t.hintColor, height: 1.5),
                ),
                const SizedBox(height: 8),
                if (_busy)
                  const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator())
                else
                  for (final f in kShareFields)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(f.$2),
                      value: core.jsTruthy(_share?[f.$1]),
                      onChanged: (on) async {
                        final next = <String, dynamic>{...?_share, f.$1: on};
                        /* 서버와 같은 규칙 — 몸 항목이 하나도 없으면 「실제 수치까지」 는 꺼짐. */
                        if (!const ['weightTrend', 'smmTrend', 'bfmTrend']
                            .any((k) => core.jsTruthy(next[k]))) {
                          next['absolute'] = false;
                        }
                        setState(() => _share = next);
                        unawaited(_rememberShare(next));
                        final id = '${widget.person['id']}';
                        final queue = Scope.queueOf(context);
                        /* **바꾼 스위치 하나만** 보냅니다. 화면의 _share 는 캐시에서 온
                           옛 값일 수 있고, 통째로 보내면(특히 큐에 남았다가 나중에
                           가면) 그 사이 「모두에게 적용」 한 값을 옛 값으로 되돌립니다 —
                           껐던 체중이 다시 켜집니다. 웹 앱(backend.js)도 patch 만 보냅니다. */
                        final patch = <String, Object?>{f.$1: on};
                        final seq = ++_shareSeq;
                        /* 누른 순간의 로그인 — 못 닿아 큐에 맡길 때 이 계정의 일로(4차 검토 · 요청 줄의
                           [수락] 과 같은 까닭). 화면이 내려갔어도 맡깁니다: 예전엔 그때 아무것도 안 맡겨
                           끈 스위치가 서버에 영영 안 갔습니다. */
                        final by = queue?.signer;
                        final r = await Scope.apiOf(context).setShare(id, patch);
                        if (!r.ok && queue != null && by != null && _worthRetrying(r)) {
                          queue.add('setShare', {'userId': id, 'patch': patch}, by: by);
                          if (context.mounted) toast(context, '지금 서버에 못 닿아서 나중에 보냅니다.');
                          return;
                        }
                        if (!context.mounted) return;
                        if (r.ok) {
                          /* 서버가 합친 결과가 답입니다 — 캐시에서 본 나머지를 바로잡습니다. */
                          final got = (r.body['share'] as Map?)?.cast<String, dynamic>();
                          if (got != null && seq == _shareSeq) {
                            setState(() { _share = got; _shareFromCache = false; });
                            unawaited(_rememberShare(got));
                          }
                          return;
                        }

                        /* **껐는데 계속 나가는 것**이 이 앱에서 제일 나쁜
                           고장입니다. 껐다고 믿는 사람은 다시 확인하지
                           않습니다. 그래서 지금 못 닿았으면 되돌리지 않고
                           큐에 맡깁니다(위) — 망이 돌아오면 알아서 갑니다. */
                        toast(context, r.reason);
                        _load();
                      },
                    ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        OutlinedButton(
          onPressed: () async {
            final yes = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('친구를 끊을까요?'),
                content: const Text('서로의 기록이 더는 보이지 않습니다. 다시 추가할 수 있습니다.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('그대로')),
                  FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('끊기')),
                ],
              ),
            );
            if (yes != true || !context.mounted) return;
            await Scope.apiOf(context).removeFriend('${widget.person['id']}');
            if (context.mounted) Navigator.of(context).pop();
          },
          child: const Text('친구 끊기'),
        ),
      ]),
    );
  }
}

/* 이름 + 스트릭 둘. 스트릭은 행동에만 답니다 — 몸무게에는 달지 않습니다. */
class _FriendHeader extends StatelessWidget {
  const _FriendHeader({required this.person, required this.snap, required this.streaks});
  final Map<String, dynamic> person, snap;
  final Map<String, dynamic>? streaks;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = mb(context);
    return MbCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Avatar(displayName: '${person['displayName']}', id: '${person['id']}',
              avatarUrl: person['avatar'] as String?, size: 48),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${person['displayName']}',
                  style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              if (person['handle'] != null)
                Text('@${person['handle']}',
                    style: t.textTheme.labelSmall?.copyWith(color: t.hintColor)),
            ]),
          ),
          if (core.jsTruthy(snap['checkedIn'])) const Pill('이번 주 기록', tone: Tone.ok),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
              child: _StreakTile(
                  icon: LucideIcons.dumbbell, label: '운동',
                  days: streaks?['workoutDays'], color: c.muscle)),
          const SizedBox(width: 10),
          Expanded(
              child: _StreakTile(
                  icon: LucideIcons.utensils, label: '식단',
                  days: streaks?['foodDays'], color: c.ok)),
        ]),
        /* 운동 안 한 친구면 — 콕. 한 친구는 안 찌릅니다. */
        if (needsNudge(snap.isEmpty ? null : snap)) ...[
          const SizedBox(height: 12),
          _PokeButton(person: person),
        ],
      ]),
    );
  }
}

class _StreakTile extends StatelessWidget {
  const _StreakTile({required this.icon, required this.label, required this.days, required this.color});
  final IconData icon;
  final String label;
  final Object? days;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final n = days == null ? null : core.jsToNumber(days);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.18), shape: BoxShape.circle),
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$label 스트릭', style: t.textTheme.labelSmall?.copyWith(color: t.hintColor)),
            Text(n == null ? '—' : '${n0(n)}일째',
                style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: color)),
            if (n == null)
              Text('공유 안 함', style: t.textTheme.labelSmall?.copyWith(color: t.hintColor)),
          ]),
        ),
      ]),
    );
  }
}

/* --- 오늘 할 일 — 친구 상세와 친구 목록이 같은 줄을 봅니다 ------------------
 *
 * 주인이 v0.2.9 를 써 보고 말했습니다: "친구 탭에도 친구의 오늘 할 일
 * 대시보드를 보여 주고, 한 것은 했다고 표시되게." 이번 주 띠(요일별 점)는
 * 한 주를 한눈에 보는 그림이지 오늘의 목록이 아니라서, "오늘 헬스 갔나" 를
 * 읽으려면 점을 세어야 했습니다. 그래서 오늘 것만 줄로 폅니다.
 *
 * 여기서 **새로 나가는 정보는 하나도 없습니다.** 스냅샷은 이미 서버가 그
 * 친구의 공유 스위치로 걸러서 보낸 것이고(server/db.js friendSnapshots —
 * 허용 안 된 키는 응답에 존재하지 않습니다), 이 함수는 그 안에 든 것을 줄로
 * 펼 뿐입니다. week 가 없으면 운동 줄이 없고, today 가 없으면 식단 줄이
 * 없고, checkedIn 이 없으면 체크인 줄이 없습니다. **안 보낸 것을 "안 했다"
 * 로 그리지 않습니다** — 빈 동그라미는 "보냈는데 아직" 에만 붙습니다.
 * -------------------------------------------------------------------------- */

/// 오늘 할 일 한 줄. id 는 'gym' · 'cardio' · 'diet' · 'checkin'.
typedef TodayItem = ({String id, String label, bool done, String? detail});

List<TodayItem> friendTodayItems(Map<String, dynamic> snap, String todayKey) {
  final out = <TodayItem>[];

  /* 운동 — 이번 주 요일별 계획에서 오늘 칸만. 종목 순서는 kSchedTypes
     (헬스 다음 유산소) 그대로라, 계획 목록이 어떤 순서로 왔든 화면은 같습니다. */
  final day = friendTodayDay(snap, todayKey);
  if (day != null) {
    final plan = (day['plan'] as List?) ?? const [];
    final done = (day['done'] as List?) ?? const [];
    for (final ty in core.kSchedTypes) {
      final id = ty['id']!;
      if (!plan.contains(id)) continue;
      out.add((id: id, label: ty['label']!, done: done.contains(id), detail: null));
    }
  }

  /* 식단 — today 는 친구 기기가 마지막으로 올린 **그 사람의 오늘**입니다.
     어제 올리고 오늘 아직 앱을 안 열었으면 date 가 어제라, 그걸 그대로
     그리면 어제 먹은 1800kcal 이 오늘 한 일로 둔갑합니다. 날짜가 다르면
     "아직" 으로 둡니다 — 오늘 것은 아직 안 올라온 것이니까요. (date 가 없는
     옛 꾸러미는 logged 를 그대로 믿습니다.) */
  final today = (snap['today'] as Map?)?.cast<String, dynamic>();
  if (today != null) {
    final sameDay = today['date'] == null || '${today['date']}' == todayKey;
    final logged = sameDay && core.jsTruthy(today['logged']);
    out.add((
      id: 'diet',
      label: '식단 기록',
      done: logged,
      detail: logged && today['kcal'] != null ? '${n0(today['kcal'])} kcal' : null,
    ));
  }

  /* 이번 주 체크인 — 주 단위지만 오늘 할 일에 넣습니다. 이번 주에 아직이면
     오늘 하면 되는 일이고, 했으면 이번 주는 끝난 일이라 체크가 남습니다. */
  if (snap['checkedIn'] != null) {
    out.add((
      id: 'checkin',
      label: '이번 주 체크인',
      done: core.jsTruthy(snap['checkedIn']),
      detail: null,
    ));
  }
  return out;
}

/// 이번 주 요일별 목록에서 오늘 칸. 일정을 공유하지 않으면(week 없음) null,
/// 공유는 하는데 오늘 칸이 없어도(지난주에 올린 스냅샷) null — 둘 다
/// "오늘 것은 모른다" 입니다. 쉬는 날(계획이 빈 칸)과는 다릅니다.
Map<String, dynamic>? friendTodayDay(Map<String, dynamic> snap, String todayKey) {
  final days = ((snap['week'] as Map?)?['days'] as List?) ?? const [];
  for (final d in days) {
    if (d is Map && '${d['key']}' == todayKey) return d.cast<String, dynamic>();
  }
  return null;
}

/// 오늘 줄 하나의 종목 아이콘 — 운동은 종목대로, 식단은 포크, 체크인은 클립보드.
IconData _todayIcon(String id) => switch (id) {
      'diet' => LucideIcons.utensils,
      'checkin' => LucideIcons.clipboardCheck,
      _ => schedIcon(id),
    };

/* 오늘 — 친구가 오늘 하기로 한 것과 한 것. 한 줄에 하나, 한 것은 초록 체크,
   아직인 것은 빈 동그라미. 이번 주 띠는 그대로 두고 그 위에 얹습니다 —
   띠는 한 주의 그림이고, 이건 오늘의 목록입니다. */
class _FriendTodayCard extends StatelessWidget {
  const _FriendTodayCard({required this.snap});
  final Map<String, dynamic> snap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final hint = t.textTheme.bodySmall?.copyWith(color: t.hintColor, height: 1.5);
    final todayKey = Scope.of(context).store.dayKey();
    final items = friendTodayItems(snap, todayKey);
    final weekShared = snap['week'] is Map;
    final shared = weekShared || snap['today'] != null || snap['checkedIn'] != null;
    final hasWorkout = items.any((i) => core.kSchedTypes.any((ty) => ty['id'] == i.id));
    final done = items.where((i) => i.done).length;
    final title = t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700);

    /* 아무것도 공유 안 하는 친구 — 제목 옆에 작게, 한 줄짜리 카드. 바로 밑의
       식단·일정 카드가 각자 "공유하지 않습니다" 를 이미 말하고 있어서, 여기까지
       제목 밑에 한 줄을 더 달면 화면이 "안 보여 줌" 으로 도배됩니다. 접힌 공유
       설정이 그만큼 아래로 밀리는 것도 싫습니다 — 그게 이 화면에서 켜고 끄는
       자리니까요. */
    if (!shared) {
      return MbCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          Text('오늘', style: title),
          const SizedBox(width: 12),
          Expanded(
            child: Text('이 친구가 오늘 할 일을 공유하지 않습니다.',
                textAlign: TextAlign.right, style: hint),
          ),
        ]),
      );
    }

    return MbCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionTitle('오늘',
            trailing: items.isEmpty
                ? null
                : Text('$done/${items.length} 완료',
                    style: t.textTheme.labelSmall?.copyWith(color: t.hintColor))),
        /* 일정은 공유하는데 오늘 칸이 비었으면 — 쉬는 날입니다. 줄 하나로
           조용히. 오늘 칸 자체가 없으면(지난주에 올린 스냅샷) 쉬는 날이라고
           단정하지 않습니다 — 아직 안 올라온 것입니다. */
        if (weekShared && !hasWorkout)
          Text(
              friendTodayDay(snap, todayKey) == null
                  ? '오늘 계획은 아직 안 올라왔어요'
                  : '오늘은 운동 계획이 없어요',
              style: hint),
        for (final it in items) _TodayLine(item: it),
      ]),
    );
  }
}

/* 줄 하나 — 체크(했음) 또는 빈 동그라미(아직), 이름, 오른쪽에 작은 덧말. */
class _TodayLine extends StatelessWidget {
  const _TodayLine({required this.item});
  final TodayItem item;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = mb(context);
    final color = item.done ? c.ok : t.hintColor;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(children: [
        Icon(item.done ? LucideIcons.checkCircle2 : LucideIcons.circle, size: 18, color: color),
        const SizedBox(width: 10),
        Icon(_todayIcon(item.id), size: 16, color: t.hintColor),
        const SizedBox(width: 8),
        Expanded(
          child: Text(item.label,
              style: t.textTheme.bodyMedium
                  ?.copyWith(fontWeight: item.done ? FontWeight.w600 : FontWeight.w400)),
        ),
        if (item.detail != null)
          Text(item.detail!, style: t.textTheme.labelSmall?.copyWith(color: t.hintColor)),
      ]),
    );
  }
}

/* 친구 목록의 오늘 한 줄 — 상세의 오늘 카드를 아이콘으로 줄인 것.
   종목 아이콘 · 체크(했음)/빈 동그라미(아직) · 짧은 이름. 좁은 폰에서 넷이
   한 줄에 안 들어가면 다음 줄로 흘립니다 — 잘라 먹는 것보다 낫습니다. */
class _TodayStrip extends StatelessWidget {
  const _TodayStrip({required this.items});
  final List<TodayItem> items;

  /// 목록에선 짧게 — '식단 기록' 은 '식단', '이번 주 체크인' 은 '체크인'.
  static String _short(TodayItem it) => switch (it.id) {
        'diet' => '식단',
        'checkin' => '체크인',
        _ => it.label,
      };

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = mb(context);
    final small = t.textTheme.labelSmall?.copyWith(color: t.hintColor);
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 2),
      child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, runSpacing: 2, children: [
        for (var i = 0; i < items.length; i++)
          Row(mainAxisSize: MainAxisSize.min, children: [
            if (i > 0) Text(' · ', style: small),
            Icon(_todayIcon(items[i].id), size: 13, color: items[i].done ? c.ok : t.hintColor),
            const SizedBox(width: 2),
            Icon(items[i].done ? LucideIcons.checkCircle2 : LucideIcons.circle,
                size: 12, color: items[i].done ? c.ok : t.hintColor),
            const SizedBox(width: 2),
            /* 이름 칸은 오른쪽의 「이번 주 기록」 · 독촉 단추에 밀려 360px 폰에서 70px 남짓까지
               좁아집니다. 글자가 줄어들 수 있어야 한 줄이 칸을 넘치지 않습니다. */
            Flexible(
              child: Text(_short(items[i]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: small?.copyWith(
                      color: items[i].done ? c.ok : t.hintColor,
                      fontWeight: items[i].done ? FontWeight.w600 : FontWeight.w400)),
            ),
          ]),
      ]),
    );
  }
}

/* 오늘 식단 — 먹은 것 / 목표. 친구가 **안 한 것**은 말하지 않습니다:
   공유를 껐거나 아직 안 적은 것은 "안 먹었다" 가 아닙니다. */
class _FriendDietCard extends StatelessWidget {
  const _FriendDietCard({required this.today});
  final Map<String, dynamic>? today;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = mb(context);
    final td = today;
    final logged = td != null && core.jsTruthy(td['logged']);
    final target = (td?['target'] as Map?)?.cast<String, dynamic>();
    final hint = t.textTheme.bodySmall?.copyWith(color: t.hintColor, height: 1.5);
    return MbCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionTitle('오늘 식단',
            trailing: !logged
                ? null
                : Text(
                    target == null
                        ? '${n0(td['kcal'])} kcal'
                        : '${n0(td['kcal'])} / ${n0(target['intakeKcal'])} kcal · ${_pctOf(td['kcal'], target['intakeKcal'])}',
                    style: t.textTheme.labelSmall?.copyWith(color: t.hintColor))),
        /* "먹어야 하는 것 중 칼로리 …% · 단백질 …% 먹었습니다" 한 줄은 뺐습니다 —
           제목 옆 kcal 퍼센트와 아래 막대가 같은 숫자를 이미 보여 줍니다. */
        if (td == null)
          Text('이 친구가 식단을 공유하지 않습니다.', style: hint)
        else if (!logged)
          Text('오늘은 아직 기록이 없습니다.', style: hint)
        else ...[
          _MacroBar(label: '탄수화물', got: td['c'], want: target?['carbG'], color: c.weight),
          _MacroBar(label: '단백질', got: td['p'], want: target?['proteinG'], color: c.muscle),
          _MacroBar(label: '지방', got: td['f'], want: target?['fatG'], color: c.fat),
        ],
      ]),
    );
  }
}

/// "먹은 것 / 먹어야 하는 것" 을 퍼센트로. 목표가 없으면 '—'.
String _pctOf(Object? got, Object? want) {
  final g = core.jsToNumber(got ?? 0), w = core.jsToNumber(want);
  if (!w.isFinite || w <= 0) return '—';
  return '${n0(core.jsRound(g / w * 100))}%';
}

class _MacroBar extends StatelessWidget {
  const _MacroBar({required this.label, required this.got, required this.want, required this.color});
  final String label;
  final Object? got, want;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final g = core.jsToNumber(got ?? 0);
    final w = want == null ? double.nan : core.jsToNumber(want);
    final ratio = (w.isFinite && w > 0) ? (g / w).clamp(0.0, 1.0) : 0.0;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label, style: t.textTheme.bodySmall?.copyWith(color: t.hintColor)),
          Text(w.isFinite ? '${n0(g)} / ${n0(w)} g · ${_pctOf(g, w)}' : '${n0(g)} g',
              style: t.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
              value: ratio, minHeight: 8, color: color,
              backgroundColor: color.withValues(alpha: 0.15)),
        ),
      ]),
    );
  }
}

/* 이번 주 운동 — 홈의 이번 주 카드와 같은 그림, 누를 수는 없습니다. */
class _FriendWeekCard extends StatelessWidget {
  const _FriendWeekCard({required this.snap, required this.week});
  final Map<String, dynamic> snap;
  final Map<String, dynamic>? week;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final hint = t.textTheme.bodySmall?.copyWith(color: t.hintColor, height: 1.5);
    final days = ((week?['days'] as List?) ?? const [])
        .map((d) => (d as Map).cast<String, dynamic>())
        .toList();
    final planned = snap['plannedDays'];
    final today = Scope.of(context).store.dayKey();
    final missed = core.jsToNumber(snap['missedDays'] ?? 0);
    final open = core.jsToNumber(snap['openDays'] ?? 0);
    return MbCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        /* 하기로 한 날이 없으면 오른쪽은 비웁니다. 예전엔 '정한 날 없음' 을
           달았는데, 바로 위 오늘 카드가 이미 "오늘은 운동 계획이 없어요" 라고
           말합니다 — 같은 말을 두 번 하면 잔소리가 됩니다. */
        SectionTitle('이번 주 운동',
            trailing: Text(
                planned != null ? '${n0(snap['keptDays'])}/${n0(planned)}일 완료' : '',
                style: t.textTheme.labelSmall?.copyWith(color: t.hintColor))),
        if (week == null || days.isEmpty)
          Text('이 친구가 운동 일정을 공유하지 않습니다.', style: hint)
        else ...[
          Row(children: [
            for (final d in days) Expanded(child: _FriendDayCell(day: d, today: today)),
          ]),
          const SizedBox(height: 6),
          const DayMarkLegend(),
          if (planned != null && (missed > 0 || open > 0)) ...[
            const SizedBox(height: 10),
            Text('지나간 날 중 체크 없음 ${n0(missed)} · 남은 날 ${n0(open)}', style: hint),
          ],
        ],
      ]),
    );
  }
}

/* 홈의 요일 칸과 같은 그림(DayMark + 종류 점) — 친구 것이라 누를 수 없습니다. */
class _FriendDayCell extends StatelessWidget {
  const _FriendDayCell({required this.day, required this.today});
  final Map<String, dynamic> day;
  final String today;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = mb(context);
    final plan = (day['plan'] as List?) ?? const [];
    final done = (day['done'] as List?) ?? const [];
    final isToday = '${day['key']}' == today;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 1),
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: isToday ? c.accentSub : null,
      ),
      child: Column(children: [
        Text('${day['dow']}', style: t.textTheme.labelSmall?.copyWith(color: t.hintColor)),
        Text(n0(day['dayNum']),
            style: t.textTheme.bodySmall?.copyWith(
                fontWeight: isToday ? FontWeight.w800 : FontWeight.w500)),
        const SizedBox(height: 3),
        DayMark(dayMarkState(day, today: today), size: 20),
        const SizedBox(height: 3),
        SizedBox(
          height: 6,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (final ty in core.kSchedTypes)
              if (plan.contains(ty['id']))
                Container(
                  width: 5, height: 5,
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: done.contains(ty['id'])
                        ? (ty['id'] == 'gym' ? c.muscle : c.ok)
                        : t.dividerColor,
                    border: done.contains(ty['id'])
                        ? null
                        : Border.all(color: t.hintColor.withValues(alpha: 0.5), width: 1),
                  ),
                ),
          ]),
        ),
      ]),
    );
  }
}

/* 몸 — 친구가 켠 것만. 변화량만 켰으면 변화량만, 실제 수치까지 켰으면 둘 다. */
class _FriendBodyCard extends StatelessWidget {
  const _FriendBodyCard({required this.snap});
  final Map<String, dynamic> snap;

  @override
  Widget build(BuildContext context) {
    final c = mb(context);
    Widget stat(String label, String absKey, String dKey, Color color) {
      final a = snap[absKey];
      final d = snap[dKey];
      if (a == null && d == null) return const SizedBox.shrink();
      return Expanded(
        child: Stat(
          label: label,
          value: a != null ? n1(a) : signed(d),
          unit: 'kg',
          delta: (a != null && d != null) ? signed(d) : null,
          color: color,
        ),
      );
    }
    return MbCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionTitle('몸',
            trailing: snap['progressPct'] == null
                ? null
                : Pill('목표 ${n0(snap['progressPct'])}%', tone: Tone.ok)),
        Row(children: [
          stat('체중', 'weightKg', 'dWeightKg', c.weight),
          stat('골격근', 'smmKg', 'dSmmKg', c.muscle),
          stat('체지방', 'bfmKg', 'dBfmKg', c.fat),
        ]),
      ]),
    );
  }
}

/* 다시 보내 볼 만한 실패인가.
 *
 *   0    서버에 아예 못 닿음 (지하철 · 노트북이 꺼짐)
 *   408  시간 초과
 *   429  지금은 너무 잦음
 *   5xx  서버가 잠깐 삐끗함
 *
 * 나머지 4xx 는 다시 보내도 같은 답입니다 — 그건 그 자리에서 말해 줍니다. */
bool _worthRetrying(ApiResult r) =>
    r.status == 0 || r.status == 408 || r.status == 429 || r.status >= 500;
