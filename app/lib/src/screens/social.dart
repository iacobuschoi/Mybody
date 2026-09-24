/* =============================================================================
 * social.dart — P15 친구 · P16 친구 상세
 *
 * **몸 숫자는 기본이 비공개입니다.** 친구가 되어도 서로 보이는 것은 "이번 주에
 * 운동했는가" 뿐이고, 체중·근육·체지방은 그 친구에게 따로 켜야 나갑니다.
 * 그리고 켜고 끄는 것은 화면에서 가리는 것이 아니라 **서버가 안 보내는**
 * 것입니다 — 권한 판정은 언제나 서버가 합니다.
 *
 * 점(배지)은 두 가지에만 켭니다: 받은 친구 요청(내가 답해야 하는 일)과
 * 친구 소식(친구가 운동했다는 좋은 소식). **안 한 것에는 절대 안 켭니다** —
 * 친구가 이번 주에 운동을 안 했다는 것은 알림이 되지 않습니다.
 * 이 구분이 이 앱이 두는 압박의 상한선입니다.
 * ========================================================================== */
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mybody_core/mybody_core.dart' as core;

import '../api.dart';
import '../pokes.dart';
import '../scope.dart';
import '../shell.dart';
import '../ui/fmt.dart';
import '../ui/symbols.dart';
import '../ui/widgets.dart';
import 'news.dart';

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
    final both = await Future.wait([api.me(), api.friends()]);
    final me = both[0];
    final f = both[1];
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
    final results = await Future.wait([for (final p in people) api.friendSnapshots('${p['id']}')]);
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
                  ? '$_error — 마지막으로 본 목록입니다. 여기서 바꾼 것은 망이 돌아오면 보냅니다.'
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
                  Text('초대 코드 ${_me!['inviteCode'] ?? '—'}',
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
          ),

        if (incoming.isNotEmpty) ...[
          const SectionTitle('받은 요청'),
          for (final p in incoming) _RequestRow(person: p, onDone: _load),
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

        const SectionTitle('친구'),
        if (accepted.isEmpty)
          const EmptyState(
            title: '아직 친구가 없습니다',
            detail: '초대 코드를 주고받으면 서로의 운동 체크가 보입니다. '
                '몸 숫자는 기본이 비공개이고, 친구마다 따로 켤 수 있습니다.',
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

  Future<void> _addFriend(BuildContext context) async {
    final ctrl = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('친구의 초대 코드'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: '예: ab12cd', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('요청 보내기')),
        ],
      ),
    );
    if (code == null || code.isEmpty || !context.mounted) return;
    final r = await Scope.apiOf(context).requestFriend(code);
    if (!context.mounted) return;
    toast(context, r.ok ? '요청을 보냈습니다' : r.reason);
    if (r.ok) _load();
  }
}

class _RequestRow extends StatelessWidget {
  const _RequestRow({required this.person, required this.onDone});
  final dynamic person;
  final Future<void> Function() onDone;

  @override
  Widget build(BuildContext context) {
    final api = Scope.apiOf(context);
    return MbCard(
      child: Row(children: [
        Avatar(displayName: '${person['displayName']}', id: '${person['id']}',
            avatarUrl: person['avatar'] as String?, size: 36),
        const SizedBox(width: 10),
        Expanded(child: Text('${person['displayName']}')),
        TextButton(
          onPressed: () async {
            final id = '${person['id']}';
            final q = Scope.queueOf(context);
            final r = await api.declineFriend(id);
            if (!r.ok && q != null && _worthRetrying(r)) {
              q.add('decline', {'userId': id});
            }
            await onDone();
          },
          child: const Text('거절'),
        ),
        FilledButton(
          onPressed: () async {
            final id2 = '${person['id']}';
            final q2 = Scope.queueOf(context);
            final r = await api.acceptFriend(id2);
            if (!r.ok && q2 != null && _worthRetrying(r)) {
              q2.add('accept', {'userId': id2});
            }
            if (context.mounted && !r.ok) toast(context, r.reason);
            await onDone();
          },
          child: const Text('수락'),
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

/* 독촉 버튼 — 목록에선 아이콘만, 상세에선 글자와 함께. 보내면 하루 동안 "보냄". */
class _PokeButton extends StatefulWidget {
  const _PokeButton({required this.person, this.compact = false});
  final Map<String, dynamic> person;
  final bool compact;

  @override
  State<_PokeButton> createState() => _PokeButtonState();
}

class _PokeButtonState extends State<_PokeButton> {
  bool _sent = false;
  bool _busy = false;

  Future<void> _send() async {
    if (_busy) return;
    setState(() => _busy = true);
    final api = Scope.apiOf(context);
    final name = '${widget.person['displayName']}';
    final r = await api.poke('${widget.person['id']}');
    if (!mounted) return;
    setState(() { _busy = false; _sent = r.ok || r.body['already'] == true; });
    if (r.ok) {
      toast(context, '$name님에게 운동 독촉을 보냈습니다 💪');
    } else {
      toast(context, r.reason);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    if (widget.compact) {
      return IconButton(
        tooltip: _sent ? '오늘 보냄' : '운동 독촉',
        visualDensity: VisualDensity.compact,
        onPressed: _sent ? null : _send,
        icon: Icon(LucideIcons.bellRing, size: 20,
            color: _sent ? t.hintColor : t.colorScheme.primary),
      );
    }
    return OutlinedButton.icon(
      onPressed: _sent ? null : _send,
      icon: const Icon(LucideIcons.bellRing, size: 18),
      label: Text(_sent ? '오늘 독촉 보냄' : '운동 독촉하기'),
    );
  }
}

/* --- P16 친구 상세 ---------------------------------------------------------- */

/// 공유 스위치 — **서버가 아는 이름 그대로** (server/db.js 의 SHARE_FIELDS).
/// 예전엔 weight·smm 같은 다른 이름으로 보내서, 켜도 서버가 버렸습니다 —
/// 스위치는 켜졌는데 나가는 건 없었습니다.
const _shareFields = [
  ('streak', '기록 여부 · 스트릭'),
  ('schedule', '이번 주 운동 (요일별 계획·체크)'),
  ('diet', '오늘 식단 (칼로리·탄단지)'),
  ('weightTrend', '체중 변화'),
  ('smmTrend', '골격근 변화'),
  ('bfmTrend', '체지방 변화'),
  ('absolute', '변화량이 아니라 실제 수치까지'),
  ('planProgress', '목표 진행률'),
];

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

  String get _shareKey => 'mybody.share.cache.v1.${widget.person['id']}';

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
    final onCount = _shareFields.where((f) => core.jsTruthy(_share?[f.$1])).length;

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
                  '끄면 화면에서 가리는 게 아니라 **서버가 안 보냅니다.** '
                  '몸 숫자는 기본으로 꺼져 있고, 행동(기록·운동·식단)만 보입니다.',
                  style: t.textTheme.bodySmall?.copyWith(color: t.hintColor, height: 1.5),
                ),
                const SizedBox(height: 8),
                if (_busy)
                  const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator())
                else
                  for (final f in _shareFields)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(f.$2),
                      value: core.jsTruthy(_share?[f.$1]),
                      onChanged: (on) async {
                        final next = {...?_share, f.$1: on};
                        setState(() => _share = next.cast<String, dynamic>());
                        unawaited(_rememberShare(next.cast<String, dynamic>()));
                        final id = '${widget.person['id']}';
                        final queue = Scope.queueOf(context);
                        final r = await Scope.apiOf(context)
                            .setShare(id, next.cast<String, dynamic>());
                        if (!context.mounted) return;
                        if (r.ok) return;

                        /* **껐는데 계속 나가는 것**이 이 앱에서 제일 나쁜
                           고장입니다. 껐다고 믿는 사람은 다시 확인하지
                           않습니다. 그래서 지금 못 닿았으면 되돌리지 않고
                           큐에 맡깁니다 — 망이 돌아오면 알아서 갑니다. */
                        if (queue != null && _worthRetrying(r)) {
                          queue.add('setShare',
                              {'userId': id, 'patch': next.cast<String, Object?>()});
                          toast(context, '지금 서버에 못 닿아서 나중에 보냅니다.');
                          return;
                        }
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
        /* 먹어야 하는 것 중 얼마나 먹었나 — 한 줄로. */
        if (logged && target != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
                '먹어야 하는 것 중 칼로리 ${_pctOf(td['kcal'], target['intakeKcal'])} · '
                '단백질 ${_pctOf(td['p'], target['proteinG'])} 먹었습니다.',
                style: hint),
          ),
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
            for (final d in days)
              Expanded(child: _FriendDayCell(day: d, isToday: '${d['key']}' == today)),
          ]),
          if (planned != null && (missed > 0 || open > 0)) ...[
            const SizedBox(height: 10),
            Text('지나간 날 중 체크 없음 ${n0(missed)} · 남은 날 ${n0(open)}', style: hint),
          ],
        ],
      ]),
    );
  }
}

class _FriendDayCell extends StatelessWidget {
  const _FriendDayCell({required this.day, required this.isToday});
  final Map<String, dynamic> day;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = mb(context);
    final plan = (day['plan'] as List?) ?? const [];
    final done = (day['done'] as List?) ?? const [];
    final missed = day['missed'] == true;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 1),
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: isToday ? c.accentSub : null,
        border: missed ? Border.all(color: c.warn.withValues(alpha: 0.5)) : null,
      ),
      child: Column(children: [
        Text('${day['dow']}', style: t.textTheme.labelSmall?.copyWith(color: t.hintColor)),
        Text(n0(day['dayNum']),
            style: t.textTheme.bodySmall?.copyWith(
                fontWeight: isToday ? FontWeight.w800 : FontWeight.w500)),
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
