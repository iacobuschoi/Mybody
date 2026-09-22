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
import 'package:flutter/material.dart';
import 'package:mybody_core/mybody_core.dart' as core;

import '../api.dart';
import '../scope.dart';
import '../shell.dart';
import '../ui/fmt.dart';
import '../ui/widgets.dart';
import 'news.dart';

class SocialScreen extends StatefulWidget {
  const SocialScreen({super.key, required this.go});
  final void Function(String route, [Object? arg]) go;

  @override
  State<SocialScreen> createState() => _SocialScreenState();
}

class _SocialScreenState extends State<SocialScreen> {
  Map<String, dynamic>? _friends;
  Map<String, dynamic>? _me;
  String? _error;
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_friends == null && !_busy) _load();
  }

  Future<void> _load() async {
    final api = Scope.apiOf(context);
    if (!api.signedIn) return;
    setState(() => _busy = true);
    final me = await api.me();
    final f = await api.friends();
    if (!mounted) return;
    await _refreshNews(api, f);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _me = me.ok ? (me.body['user'] as Map?)?.cast<String, dynamic>() : null;
      _friends = f.ok ? (f.body['friends'] as Map?)?.cast<String, dynamic>() : null;
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
    final snaps = <Object?>[];
    for (final p in friends) {
      final id = (p as Map)['id'];
      if (id is! String) continue;
      final r = await api.friendSnapshots(id);
      /* 못 받아온 것과 공유를 끈 것은 다릅니다 — 실패는 rows 를 아예
         안 실어 보냅니다. 코어가 그 차이를 압니다. */
      snaps.add({'id': id, if (r.ok) 'rows': (r.body['rows'] as List?) ?? const []});
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
        if (_error != null) Note(tone: Tone.warn, text: _error!),

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
              const Icon(Icons.notifications_none, size: 20),
              const SizedBox(width: 10),
              const Expanded(child: Text('소식')),
              if (unread > 0) Pill('$unread', tone: Tone.ok),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right, size: 18, color: t.hintColor),
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
                icon: const Icon(Icons.manage_accounts_outlined),
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

    return Row(children: [
      Avatar(displayName: '${person['displayName']}', id: '${person['id']}',
          avatarUrl: person['avatar'] as String?, size: 40),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${person['displayName']}', style: t.textTheme.titleSmall),
          /* 친구가 **안 한 것**은 말하지 않습니다. 공유가 꺼져 있거나
             아직 안 올린 것도 "안 했다" 가 아닙니다. */
          Text(
            planned == null
                ? '이번 주 공유한 것이 없습니다'
                : '이번 주 ${n0(kept)}/${n0(planned)}일 운동',
            style: t.textTheme.labelSmall?.copyWith(color: t.hintColor),
          ),
          if (snap != null && snap['weightKg'] != null)
            Text('${n1(snap['weightKg'])}kg · 근 ${n1(snap['smmKg'])} · 지 ${n1(snap['bfmKg'])}',
                style: t.textTheme.labelSmall?.copyWith(color: t.hintColor)),
        ]),
      ),
      if (core.jsTruthy(snap?['checkedIn']))
        const Pill('이번 주 기록', tone: Tone.ok),
      const Icon(Icons.chevron_right),
    ]);
  }
}

/* --- P16 친구 상세 ---------------------------------------------------------- */

const _shareFields = [
  ('weight', '체중'),
  ('smm', '골격근량'),
  ('bfm', '체지방량'),
  ('pbf', '체지방률'),
  ('progress', '목표 진행률'),
  ('schedule', '주간 운동 일정'),
];

class FriendDetailScreen extends StatefulWidget {
  const FriendDetailScreen({super.key, required this.person});
  final Map<String, dynamic> person;

  @override
  State<FriendDetailScreen> createState() => _FriendDetailScreenState();
}

class _FriendDetailScreenState extends State<FriendDetailScreen> {
  Map<String, dynamic>? _share;
  bool _busy = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_share == null) _load();
  }

  Future<void> _load() async {
    final r = await Scope.apiOf(context).getShare('${widget.person['id']}');
    if (!mounted) return;
    setState(() {
      _share = r.ok ? (r.body['share'] as Map?)?.cast<String, dynamic>() : {};
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final snap = (widget.person['snapshot'] as Map?)?.cast<String, dynamic>();

    return Scaffold(
      appBar: AppBar(title: Text('${widget.person['displayName']}')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        MbCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SectionTitle('이번 주'),
            if (snap == null || snap.isEmpty)
              Text('아직 공유한 것이 없습니다',
                  style: t.textTheme.bodySmall?.copyWith(color: t.hintColor))
            else ...[
              if (snap['plannedDays'] != null)
                Text('운동 ${n0(snap['keptDays'])}/${n0(snap['plannedDays'])}일',
                    style: t.textTheme.bodyMedium),
              if (snap['weightKg'] != null)
                Row(children: [
                  Expanded(child: Stat(label: '체중', value: n1(snap['weightKg']), unit: 'kg',
                      delta: snap['dWeightKg'] == null ? null : signed(snap['dWeightKg']))),
                  Expanded(child: Stat(label: '골격근', value: n1(snap['smmKg']), unit: 'kg',
                      delta: snap['dSmmKg'] == null ? null : signed(snap['dSmmKg'], 2))),
                  Expanded(child: Stat(label: '체지방', value: n1(snap['bfmKg']), unit: 'kg',
                      delta: snap['dBfmKg'] == null ? null : signed(snap['dBfmKg'], 2))),
                ]),
            ],
          ]),
        ),
        MbCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SectionTitle('이 친구에게 보여 줄 것'),
            RichishText(
              '끄면 화면에서 가리는 게 아니라 **서버가 안 보냅니다.** '
              '기본은 전부 꺼져 있고, 운동 체크만 보입니다.',
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
                      toast(context, '지금 서버에 못 닿아서 **나중에 보냅니다.**');
                      return;
                    }
                    toast(context, r.reason);
                    _load();
                  },
                ),
          ]),
        ),
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
