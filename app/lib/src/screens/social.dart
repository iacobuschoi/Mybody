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
import 'package:lucide_icons/lucide_icons.dart';
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
      final rows = r.ok ? ((r.body['rows'] as List?) ?? const []) : null;
      snaps.add({'id': id, if (rows != null) 'rows': rows});
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
      const Icon(LucideIcons.chevronRight),
    ]);
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

/// 친구 한 사람. **친구에 대한 것**이 먼저입니다 — 스트릭, 오늘 식단,
/// 이번 주 운동. 내가 뭘 보여 주는지는 아래에 접어 둡니다.
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
    final r = await api.getShare(id);
    final sn = await api.friendSnapshots(id, limit: 1);
    if (!mounted) return;
    setState(() {
      _share = r.ok ? (r.body['share'] as Map?)?.cast<String, dynamic>() : {};
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
              subtitle: Text(_busy ? '불러오는 중' : '$onCount개 켜짐',
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
                        : '${n0(td['kcal'])} / ${n0(target['intakeKcal'])} kcal',
                    style: t.textTheme.labelSmall?.copyWith(color: t.hintColor))),
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
          Text(w.isFinite ? '${n0(g)} / ${n0(w)} g' : '${n0(g)} g',
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
        SectionTitle('이번 주 운동',
            trailing: Text(
                planned != null
                    ? '${n0(snap['keptDays'])}/${n0(planned)}일 완료'
                    : (week == null ? '' : '정한 날 없음'),
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
