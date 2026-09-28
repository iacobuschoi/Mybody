/* =============================================================================
 * feedback_inbox.dart — 「의견함」: 운영자가 앱 안에서 의견을 읽는 곳
 *
 * 왜 있나 — 주인의 물음 "의견 어디서 봐". 지금까지 의견은 노트북에서 도구
 * (tools/feedback.js)를 돌려야 보였고, 폰에 온 「새 의견이 왔어요」 알림은 "노트북에서
 * 확인하세요" 로 끝났습니다. 알림을 본 그 자리(폰)에서 바로 읽게 합니다 — 알림을 누르면
 * 이 화면이 열리고(셸이 route 'feedback' 을 받음), 설정 → 도움말 맨 위의 「의견함」 줄로도
 * 옵니다.
 *
 * 누가 보나 — 운영자 한 사람. 서버 설정(feedbackNotify)에 적힌 아이디로 로그인한 계정만
 * /me 에 isOperator 가 참으로 오고, 그때만 설정에 줄이 섭니다(다른 사람에게는 자리표시도
 * 없음). 판정은 언제나 서버가 합니다 — 다른 계정이 이 화면에 닿아도(알림 길 등) 서버가
 * 403 을 주고, 화면은 「운영자 계정으로 로그인하면 볼 수 있어요」 만 말합니다.
 *
 * 무엇을 보여 주나 — 새것부터 한 장씩: 보낸 때(한 시간 안이면 「방금」 · 「N분 전」) · 안 읽음
 * 점 · 보낸 사람(표시 이름, 로그인 없이 보냈으면 「익명」) · 판 · 기종 · 보던 화면 · 글 세 줄 ·
 * 캡처 세 장까지. 누르면 글 전체(길게 눌러 복사)와 캡처를 폭 가득, 캡처를 누르면 검은 전체
 * 화면에서 두 손가락으로 키우고(두 번 톡 = 2.5배) 옆으로 넘깁니다.
 *
 * 보낸 사람은 **표시 이름만**. 아이디 · 이메일은 서버가 싣지 않습니다 — 노트북 도구가
 * 가명 6자만 찍는 것과 같은 까닭입니다: 운영자에게 필요한 것은 "누가 또 보냈나" 까지이고,
 * 로그인 아이디는 거기 필요 없습니다.
 *
 * 읽음 — 여는 순간 읽은 것으로. 화면을 먼저 바꾸고 서버에 알리며, 못 닿으면 되돌립니다
 * (서버와 다른 점이 남으면 다음에 열 때 "읽었는데 또 안 읽음" 이 됩니다). 「모두 읽음」 은
 * 앱바에. 지우기는 상세에서만, 한 번 묻고 — 목록에서 밀어서 지우게 하면 스크롤하던 손이
 * 미끄러져 읽지도 않은 의견이 사라집니다.
 *
 * 사진 — 목록이 그 장을 지을 때 그 장의 것만 받습니다(ListView.builder 는 보이는 근처만
 * 짓습니다). 받은 것은 Api 가 메모리에 30장까지 들고 있어 목록 → 상세 → 전체 화면으로 가도
 * 다시 받지 않습니다. 디스크에는 안 남깁니다 — 캡처에 몸 숫자가 찍혀 있을 수 있어, 서버에서
 * 지워지면(1년 · 탈퇴 · 여기서 지우기) 폰에도 없어야 합니다(api.dart [ApiFeedbackInbox]).
 *
 * 쪽 넘기기 — 30건씩. 목록 끝의 「더 가져오는 중」 칸이 지어지면(끝에 가까워지면) 다음 쪽
 * (nextBefore)을 부릅니다. 스크롤 위치를 재는 것보다 이쪽이 목록이 화면보다 짧을 때도 맞습니다.
 * 끌어 내리면 처음부터 새로 받습니다.
 *
 * 실패는 그 자리에서 — 첫 쪽을 못 받으면 가운데에 까닭과 「다시 시도」, 새로 고침이 실패하면
 * 보던 목록은 그대로 두고 맨 위에 한 줄, 다음 쪽이 실패하면 목록 끝에 한 줄. 도는 원은 받는
 * 동안에만 돕니다(끝없이 도는 것이 화면에 남지 않게 — 받기는 20초면 끝납니다).
 * ========================================================================== */
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../api.dart';
import '../scope.dart';
import '../ui/widgets.dart';

/// 화면 제목 · 설정의 줄 이름 — 줄을 눌러 열리는 화면의 제목이 같아야 헷갈리지 않습니다.
const kInboxTitle = '의견함';

/// 보낸 때 한 마디.
///
/// 목록([relative] 참): 한 시간 안이면 「방금」 · 「N분 전」, 그 밖은 「9월 28일 04:12」 — 연도는
/// 안 붙입니다. 서버가 의견을 1년만 두므로(server/feedback.js KEEP_DAYS) 목록에는 1년 안의 것만
/// 있고, 새것부터라 차례가 연도를 말해 줍니다. 붙이면 360px · 큰 글자에서 이름 칸을 다 먹습니다.
/// 상세([relative] 거짓): 언제나 날짜와 시각, 올해가 아니면 앞에 연도.
/// 서버 시계가 조금 앞서 있어도(5분까지) 「방금」 — 음수 「-2분 전」 을 보이지 않게.
String inboxTimeLabel(DateTime at, DateTime now, {bool relative = true}) {
  final d = now.difference(at);
  if (relative && d < const Duration(hours: 1) && d > const Duration(minutes: -5)) {
    return d < const Duration(minutes: 1) ? '방금' : '${d.inMinutes}분 전';
  }
  final l = at.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  final day = '${l.month}월 ${l.day}일 ${two(l.hour)}:${two(l.minute)}';
  return relative || l.year == now.toLocal().year ? day : '${l.year}년 $day';
}

/// 보낸 사람 한 마디 — 로그인 없이 보냈으면 「익명」, 이름이 비어 있으면 「이름 없음」.
String inboxFrom(InboxItem it) => it.anonymous ? '익명' : (it.fromName ?? '이름 없음');

/// 기종 칸의 아이콘과 이름. 앱이 보내는 값은 'android' · 'ios' 둘이고, 모르는 값은 그대로.
({IconData icon, String label}) inboxPlatform(String p) => switch (p.toLowerCase()) {
      'android' => (icon: LucideIcons.smartphone, label: 'Android'),
      'ios' => (icon: LucideIcons.apple, label: 'iOS'),
      _ => (icon: LucideIcons.monitor, label: p),
    };

/* --- 목록 ----------------------------------------------------------------------- */

class FeedbackInboxScreen extends StatefulWidget {
  const FeedbackInboxScreen({super.key, this.now});

  /// 「N분 전」 의 기준 시각 — 시험이 시계를 고정합니다.
  final DateTime Function()? now;

  @override
  State<FeedbackInboxScreen> createState() => _FeedbackInboxScreenState();
}

class _FeedbackInboxScreenState extends State<FeedbackInboxScreen> {
  final _items = <InboxItem>[];
  int _unread = 0;
  int? _nextBefore;

  /// 첫 쪽을 한 번이라도 받았나 — 못 받았으면 실패를 가운데에, 받았으면 맨 위에 한 줄로.
  bool _loaded = false;
  bool _loading = false;
  bool _loadingMore = false;

  /// 첫 쪽 · 새로 고침의 실패 까닭.
  String? _error;

  /// 다음 쪽의 실패 까닭. 있으면 「다시 시도」 를 누를 때까지 다음 쪽을 저절로 안 부릅니다
  /// (끝 칸이 지어질 때마다 실패를 되풀이하지 않게).
  String? _moreError;

  /// 운영자가 아님(403) · 로그인 없음(401).
  bool _denied = false;
  bool _readingAll = false;

  /// 새로 고침마다 하나씩 올립니다 — 그 전에 떠난 다음 쪽 · 되돌리기가 새 목록을 덮지 않게.
  int _gen = 0;
  Api? _api;

  DateTime _now() => (widget.now ?? DateTime.now)();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    /* Scope 는 기록이 바뀔 때마다 알립니다 — Api 가 바뀐 때(서버 주소)만 새로 받습니다. */
    final api = Scope.apiOf(context);
    if (identical(api, _api)) return;
    _api = api;
    _items.clear();
    _loaded = false;
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    final api = _api;
    if (api == null) return;
    final gen = ++_gen;
    setState(() {
      _loading = true;
      _loadingMore = false;
    });
    final p = await api.fetchInbox();
    if (!mounted || gen != _gen) return;
    setState(() {
      _loading = false;
      if (p.ok) {
        _items
          ..clear()
          ..addAll(p.items);
        _unread = p.unread;
        /* 빈 쪽인데 다음이 있다는 답은 믿지 않습니다 — 끝 칸이 지어질 때마다 부르는 고리가 됩니다. */
        _nextBefore = p.items.isEmpty ? null : p.nextBefore;
        _loaded = true;
        _error = null;
        _moreError = null;
        _denied = false;
      } else if (p.denied) {
        _denied = true;
        _items.clear();
        _nextBefore = null;
      } else {
        _error = p.reason;
      }
    });
  }

  Future<void> _more() async {
    final api = _api;
    final before = _nextBefore;
    if (api == null || before == null || _loading || _loadingMore || _moreError != null) return;
    final gen = _gen;
    setState(() => _loadingMore = true);
    final p = await api.fetchInbox(before: before);
    if (!mounted || gen != _gen) return;
    setState(() {
      _loadingMore = false;
      if (p.ok) {
        final have = {for (final i in _items) i.id};
        _items.addAll(p.items.where((i) => !have.contains(i.id)));
        _unread = p.unread;
        /* 다음 번호는 이번 것보다 작아야 합니다 — 같거나 크면(서버의 실수) 같은 쪽을 끝없이 다시
           받는 고리가 되니 거기서 멈춥니다. 빈 쪽도 마찬가지. */
        final next = p.nextBefore;
        _nextBefore = p.items.isEmpty || next == null || next >= before ? null : next;
      } else if (p.denied) {
        _denied = true;
      } else {
        _moreError = p.reason;
      }
    });
  }

  void _setRead(int id, bool read) {
    final i = _items.indexWhere((x) => x.id == id);
    if (i < 0 || _items[i].read == read) return;
    setState(() {
      _items[i] = _items[i].copyWith(read: read);
      _unread = math.max(0, _unread + (read ? -1 : 1));
    });
  }

  /* 여는 순간 읽음 — 화면 먼저, 서버에 못 닿으면 되돌립니다(머리 주석). 404 는 그사이
     지워진 것(노트북 도구 · 다른 기기)이라 되돌릴 것이 없습니다. */
  void _markRead(InboxItem it) {
    final api = _api;
    if (api == null) return;
    _setRead(it.id, true);
    final gen = _gen;
    unawaited(api.markRead(it.id).then((r) {
      if (!mounted || gen != _gen || r.ok || r.status == 404) return;
      _setRead(it.id, false);
    }));
  }

  Future<void> _readAll() async {
    final api = _api;
    if (api == null) return;
    final before = List.of(_items);
    final unread = _unread;
    final gen = _gen;
    setState(() {
      _readingAll = true;
      for (var i = 0; i < _items.length; i++) {
        _items[i] = _items[i].copyWith(read: true);
      }
      _unread = 0;
    });
    /* 받아 둔 것 중 가장 새 번호까지만 — 이 목록을 받은 뒤에 온 의견은 본 적이 없습니다. */
    final newest = before.isEmpty ? null : before.map((i) => i.id).reduce(math.max);
    final r = await api.markAllRead(upTo: newest);
    if (!mounted) return;
    setState(() {
      _readingAll = false;
      if (!r.ok && gen == _gen) {
        _items
          ..clear()
          ..addAll(before);
        _unread = unread;
      }
    });
    if (!r.ok) toast(context, inboxReason(r));
  }

  Future<void> _open(InboxItem it) async {
    if (!it.read) _markRead(it);
    final deleted = await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) => FeedbackDetailScreen(item: it.copyWith(read: true), now: widget.now)));
    if (deleted != true || !mounted) return;
    setState(() {
      final i = _items.indexWhere((x) => x.id == it.id);
      if (i < 0) return;
      if (!_items[i].read) _unread = math.max(0, _unread - 1);
      _items.removeAt(i);
    });
    toast(context, '지웠어요');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(kInboxTitle),
        actions: [
          TextButton(
            key: const Key('inbox-read-all'),
            onPressed: _unread > 0 && !_readingAll && !_denied ? _readAll : null,
            child: const Text('모두 읽음'),
          ),
          const SizedBox(width: 4),
        ],
      ),
      /* 비었을 때 · 실패했을 때도 끌어 내려 새로 받을 수 있게 늘 스크롤되는 목록입니다. */
      body: RefreshIndicator(onRefresh: _refresh, child: _body(context)),
    );
  }

  Widget _body(BuildContext context) {
    const physics = AlwaysScrollableScrollPhysics();
    if (_denied) {
      return ListView(key: const Key('inbox-denied'), physics: physics, children: const [
        SizedBox(height: 48),
        EmptyState(
          title: '운영자 계정으로 로그인하면 볼 수 있어요',
          detail: '의견함은 서버에 운영자로 적힌 계정에만 열려요.',
        ),
      ]);
    }
    if (!_loaded) {
      final err = _error;
      return ListView(physics: physics, padding: const EdgeInsets.all(16), children: [
        const SizedBox(height: 48),
        if (err != null && !_loading)
          _ErrorBox(key: const Key('inbox-error'), message: err, retryKey: 'inbox-retry', onRetry: _refresh)
        else
          const Center(child: CircularProgressIndicator()),
      ]);
    }
    final t = Theme.of(context);
    final head = <Widget>[
      if (_error case final err?)
        _ErrorBox(key: const Key('inbox-error'), message: err, retryKey: 'inbox-retry', onRetry: _refresh),
      if (_unread > 0)
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 0, 2, 10),
          child: Text('안 읽은 의견 $_unread개',
              key: const Key('inbox-unread-count'),
              style: t.textTheme.labelLarge?.copyWith(color: t.colorScheme.primary)),
        ),
    ];
    if (_items.isEmpty) {
      return ListView(physics: physics, padding: const EdgeInsets.all(16), children: [
        ...head,
        const SizedBox(height: 32),
        const EmptyState(
          key: Key('inbox-empty'),
          title: '아직 의견이 없어요',
          detail: '앱 안 「의견 보내기」 로 온 의견이 여기 모여요.',
        ),
      ]);
    }
    final more = _nextBefore != null;
    return ListView.builder(
      key: const Key('inbox-list'),
      physics: physics,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: head.length + _items.length + (more ? 1 : 0),
      itemBuilder: (context, i) {
        if (i < head.length) return head[i];
        final k = i - head.length;
        if (k < _items.length) {
          final it = _items[k];
          return _InboxCard(key: ValueKey('inbox-item-${it.id}'), item: it, now: _now(), api: _api!,
              onTap: () => unawaited(_open(it)));
        }
        /* 끝 칸 — 지어지면(끝에 가까워지면) 다음 쪽을 부릅니다(머리 주석). 짓는 중에는 화면을
           못 바꾸므로 다음 틈에. */
        if (_moreError case final err?) {
          return _ErrorBox(
            key: const Key('inbox-more-error'),
            message: err,
            retryKey: 'inbox-more-retry',
            onRetry: () async {
              setState(() => _moreError = null);
              await _more();
            },
          );
        }
        if (!_loadingMore) WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_more()));
        return const Padding(
          key: Key('inbox-more'),
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Center(child: SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2.5))),
        );
      },
    );
  }
}

/// 실패 한 줄과 「다시 시도」.
class _ErrorBox extends StatelessWidget {
  const _ErrorBox({super.key, required this.message, required this.retryKey, required this.onRetry});
  final String message;
  final String retryKey;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final c = mb(context);
    final t = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: c.badBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.bad.withValues(alpha: 0.25)),
      ),
      child: Row(children: [
        Icon(LucideIcons.alertCircle, size: 18, color: c.bad),
        const SizedBox(width: 8),
        Expanded(
          child: Text(message, style: t.textTheme.bodySmall?.copyWith(color: c.bad, height: 1.4)),
        ),
        const SizedBox(width: 4),
        TextButton(
          key: Key(retryKey),
          onPressed: () => unawaited(onRetry()),
          child: const Text('다시 시도'),
        ),
      ]),
    );
  }
}

/// 목록의 한 장.
class _InboxCard extends StatelessWidget {
  const _InboxCard({super.key, required this.item, required this.now, required this.api, required this.onTap});
  final InboxItem item;
  final DateTime now;
  final Api api;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final it = item;
    final at = it.createdAt;
    return MbCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        /* 이름은 남는 폭을 다 쓰고, 때는 제 폭만 — 다만 한 줄의 6할까지(아주 큰 글자에서 이름 칸이
           0 이 되어 넘치지 않게). */
        LayoutBuilder(builder: (context, c) => Row(children: [
          if (!it.read)
            Semantics(
              label: '안 읽음',
              child: Container(
                key: ValueKey('inbox-unread-${it.id}'),
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(color: t.colorScheme.primary, shape: BoxShape.circle),
              ),
            ),
          Expanded(
            child: Text(inboxFrom(it),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.textTheme.titleSmall
                    ?.copyWith(fontWeight: it.read ? FontWeight.w500 : FontWeight.w700)),
          ),
          if (at != null) ...[
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: c.maxWidth * 0.6),
              child: Text(inboxTimeLabel(at, now),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.textTheme.labelSmall?.copyWith(color: t.hintColor)),
            ),
          ],
        ])),
        if (_MetaChips.has(it)) ...[const SizedBox(height: 8), _MetaChips(it)],
        const SizedBox(height: 8),
        if (it.text.trim().isEmpty)
          Text('글 없이 캡처만 보냈어요',
              style: t.textTheme.bodySmall?.copyWith(color: t.hintColor, fontStyle: FontStyle.italic))
        else
          Text(it.text.trim(),
              key: ValueKey('inbox-text-${it.id}'),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: t.textTheme.bodyMedium?.copyWith(height: 1.45)),
        if (it.images.isNotEmpty) ...[
          const SizedBox(height: 10),
          Row(children: [
            for (final img in it.images.take(3))
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _Thumb(api: api, id: it.id, n: img.n),
              ),
            if (it.images.length > 3)
              Text('+${it.images.length - 3}', style: t.textTheme.labelMedium?.copyWith(color: t.hintColor)),
          ]),
        ],
      ]),
    );
  }
}

/// 판 · 기종 · 보던 화면 — 있는 것만, 좁으면 다음 줄로.
class _MetaChips extends StatelessWidget {
  const _MetaChips(this.item);
  final InboxItem item;

  static bool has(InboxItem it) => it.appVersion != null || it.platform != null || it.screen != null;

  @override
  Widget build(BuildContext context) {
    final it = item;
    return Wrap(spacing: 6, runSpacing: 6, children: [
      if (it.appVersion case final v?) _Chip(key: const Key('inbox-chip-version'), icon: LucideIcons.tag, label: v),
      if (it.platform case final p?)
        _Chip(key: const Key('inbox-chip-platform'), icon: inboxPlatform(p).icon, label: inboxPlatform(p).label),
      if (it.screen case final s?) _Chip(key: const Key('inbox-chip-screen'), icon: LucideIcons.appWindow, label: s),
    ]);
  }
}

class _Chip extends StatelessWidget {
  const _Chip({super.key, required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final fg = t.colorScheme.onSurface.withValues(alpha: 0.8);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: mb(context).accentSub, borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: fg),
        const SizedBox(width: 4),
        Flexible(
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: fg)),
        ),
      ]),
    );
  }
}

/// 목록의 작은 캡처. 세로 화면 캡처라 세로로 긴 칸에 가운데를 잘라 넣습니다.
class _Thumb extends StatelessWidget {
  const _Thumb({required this.api, required this.id, required this.n});
  final Api api;
  final int id;
  final int n;

  static const w = 64.0, h = 88.0;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: ValueKey('inbox-thumb-$id-$n'),
      width: w,
      height: h,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        /* 작게 풀어 둡니다 — 1080×2400 캡처를 그대로 풀면 한 장에 10MB 가 메모리에 올라갑니다. */
        child: _Picture(api: api, id: id, n: n, decodeWidth: (w * MediaQuery.devicePixelRatioOf(context)).round()),
      ),
    );
  }
}

/// 캡처 한 장 — 받아 둔 것이 있으면 바로, 없으면 자리표시를 두고 받습니다. 못 받거나 못 풀면
/// 깨진 그림 아이콘. 목록 · 상세 · 전체 화면이 같이 씁니다.
class _Picture extends StatefulWidget {
  const _Picture({
    required this.api,
    required this.id,
    required this.n,
    this.fit = BoxFit.cover,
    this.decodeWidth,
    this.boxHeight,
    this.onDark = false,
  });
  final Api api;
  final int id;
  final int n;
  final BoxFit fit;

  /// 이 폭으로 줄여 풉니다(작은 그림). null 이면 원래 크기.
  final int? decodeWidth;

  /// 자리표시 · 깨짐 칸의 높이. null 이면 부모가 주는 크기 그대로.
  final double? boxHeight;

  /// 검은 전체 화면 위 — 자리표시를 어둡게.
  final bool onDark;

  @override
  State<_Picture> createState() => _PictureState();
}

class _PictureState extends State<_Picture> {
  Uint8List? _bytes;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  /* 같은 자리에 다른 장이 오면(열쇠 없이 다시 지어질 때) 앞 장을 그대로 두지 않고 새로 받습니다. */
  @override
  void didUpdateWidget(_Picture old) {
    super.didUpdateWidget(old);
    if (old.id != widget.id || old.n != widget.n || !identical(old.api, widget.api)) {
      _failed = false;
      _start();
    }
  }

  void _start() {
    _bytes = widget.api.cachedInboxImage(widget.id, widget.n);
    if (_bytes == null) unawaited(_load());
  }

  Future<void> _load() async {
    final want = (widget.api, widget.id, widget.n);
    final b = await widget.api.inboxImage(widget.id, widget.n);
    /* 기다리는 사이 이 자리의 장이 바뀌었으면 늦게 온 앞 장은 버립니다. */
    if (!mounted || want != (widget.api, widget.id, widget.n)) return;
    setState(() {
      _bytes = b;
      _failed = b == null;
    });
  }

  Widget _box(BuildContext context, {required bool broken}) {
    final t = Theme.of(context);
    final bg = widget.onDark ? Colors.white10 : t.colorScheme.surfaceContainerHighest;
    final fg = widget.onDark ? Colors.white54 : t.hintColor;
    return Container(
      key: ValueKey(broken ? 'inbox-img-broken-${widget.id}-${widget.n}' : 'inbox-img-wait-${widget.id}-${widget.n}'),
      height: widget.boxHeight,
      width: double.infinity,
      color: bg,
      alignment: Alignment.center,
      child: Icon(broken ? LucideIcons.imageOff : LucideIcons.image, size: 20, color: fg),
    );
  }

  @override
  Widget build(BuildContext context) {
    final b = _bytes;
    if (b == null) return _box(context, broken: _failed);
    return Image.memory(
      b,
      key: ValueKey('inbox-img-${widget.id}-${widget.n}'),
      fit: widget.fit,
      width: widget.fit == BoxFit.contain ? null : double.infinity,
      cacheWidth: widget.decodeWidth,
      gaplessPlayback: true,
      semanticLabel: '캡처 ${widget.n}',
      /* 바이트는 왔어도 풀기 전까지는 크기를 모릅니다 — 그동안 높이 0 으로 두면 상세의 캡처가
         보이지도 눌리지도 않다가 풀리는 순간 글 밑이 툭 밀립니다. 풀릴 때까지 자리표시. */
      frameBuilder: (context, child, frame, sync) =>
          sync || frame != null ? child : _box(context, broken: false),
      errorBuilder: (context, _, __) => _box(context, broken: true),
    );
  }
}

/* --- 상세 ----------------------------------------------------------------------- */

/// 의견 한 건 — 글 전체 · 판 · 캡처. 지우면 true 로 닫힙니다(목록이 그 장을 뺌).
class FeedbackDetailScreen extends StatefulWidget {
  const FeedbackDetailScreen({super.key, required this.item, this.now});
  final InboxItem item;
  final DateTime Function()? now;

  @override
  State<FeedbackDetailScreen> createState() => _FeedbackDetailScreenState();
}

class _FeedbackDetailScreenState extends State<FeedbackDetailScreen> {
  bool _deleting = false;

  Future<void> _delete() async {
    final api = Scope.apiOf(context);
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('이 의견을 지울까요?'),
        content: const Text('붙은 캡처도 같이 지워지고, 되돌릴 수 없어요.'),
        actions: [
          TextButton(
            key: const Key('inbox-delete-cancel'),
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          /* 설정의 「전부 지우기」 확인과 같은 모양(보통 FilledButton) — 빨강 바탕에 흰 글자는
             어두운 화면의 밝은 빨강 위에서 읽히지 않습니다. 무게는 제목 「지울까요?」 가 집니다. */
          FilledButton(
            key: const Key('inbox-delete-confirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('지우기'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() => _deleting = true);
    final r = await api.deleteFeedback(widget.item.id);
    if (!mounted) return;
    /* 404 는 그사이 이미 지워진 것(노트북 도구 · 1년) — 바란 대로 없어졌으니 같은 결과입니다. */
    if (r.ok || r.status == 404) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() => _deleting = false);
    toast(context, inboxReason(r));
  }

  void _view(int index) {
    final it = widget.item;
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => FeedbackImageViewer(
            api: Scope.apiOf(context), id: it.id, images: it.images, initial: index)));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final it = widget.item;
    final api = Scope.apiOf(context);
    final at = it.createdAt;
    final now = (widget.now ?? DateTime.now)();
    return Scaffold(
      appBar: AppBar(
        title: const Text('의견'),
        actions: [
          IconButton(
            key: const Key('inbox-delete'),
            tooltip: '지우기',
            icon: const Icon(LucideIcons.trash2),
            onPressed: _deleting ? null : () => unawaited(_delete()),
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 32), children: [
        Text(inboxFrom(it), style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        if (at != null) ...[
          const SizedBox(height: 4),
          Text(inboxTimeLabel(at, now, relative: false),
              key: const Key('inbox-detail-time'),
              style: t.textTheme.bodySmall?.copyWith(color: t.hintColor)),
        ],
        if (_MetaChips.has(it)) ...[const SizedBox(height: 10), _MetaChips(it)],
        const SizedBox(height: 16),
        /* 길게 눌러 고를 수 있게 — 버그 설명을 이슈나 메모로 옮기는 일이 잦습니다. */
        if (it.text.trim().isEmpty)
          Text('글 없이 캡처만 보냈어요',
              style: t.textTheme.bodyMedium?.copyWith(color: t.hintColor, fontStyle: FontStyle.italic))
        else
          SelectableText(it.text.trim(),
              key: const Key('inbox-detail-text'),
              style: t.textTheme.bodyLarge?.copyWith(height: 1.55)),
        for (var i = 0; i < it.images.length; i++)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Semantics(
              button: true,
              label: '캡처 ${i + 1} 크게 보기',
              child: GestureDetector(
                key: ValueKey('inbox-detail-img-$i'),
                onTap: () => _view(i),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: _Picture(api: api, id: it.id, n: it.images[i].n, fit: BoxFit.fitWidth, boxHeight: 240),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

/* --- 전체 화면 -------------------------------------------------------------------- */

/// 캡처를 검은 바탕 전체 화면으로 — 두 손가락으로 키우고(두 번 톡 하면 2.5배 · 다시 톡 하면
/// 원래대로), 옆으로 밀어 다음 장. 키운 동안에는 옆으로 밀기가 넘기기 대신 그림을 옮깁니다 —
/// 둘이 같은 손짓을 두고 다투면 키운 그림의 가장자리를 보려다 다음 장으로 넘어갑니다.
class FeedbackImageViewer extends StatefulWidget {
  const FeedbackImageViewer({super.key, required this.api, required this.id, required this.images, this.initial = 0});
  final Api api;
  final int id;
  final List<InboxImage> images;
  final int initial;

  @override
  State<FeedbackImageViewer> createState() => _FeedbackImageViewerState();
}

class _FeedbackImageViewerState extends State<FeedbackImageViewer> {
  late final PageController _pages = PageController(initialPage: widget.initial);
  late int _at = widget.initial;
  bool _zoomed = false;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.images.length;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(n > 1 ? '${_at + 1} / $n' : '캡처', key: const Key('inbox-viewer-count')),
      ),
      body: PageView.builder(
        key: const Key('inbox-viewer'),
        controller: _pages,
        physics: _zoomed ? const NeverScrollableScrollPhysics() : null,
        itemCount: n,
        onPageChanged: (i) => setState(() {
          _at = i;
          _zoomed = false;
        }),
        itemBuilder: (context, i) => _ZoomPage(
          key: ValueKey('inbox-zoom-${widget.id}-${widget.images[i].n}'),
          api: widget.api,
          id: widget.id,
          n: widget.images[i].n,
          onZoom: (z) {
            if (z != _zoomed && mounted) setState(() => _zoomed = z);
          },
        ),
      ),
    );
  }
}

class _ZoomPage extends StatefulWidget {
  const _ZoomPage({super.key, required this.api, required this.id, required this.n, required this.onZoom});
  final Api api;
  final int id;
  final int n;
  final ValueChanged<bool> onZoom;

  @override
  State<_ZoomPage> createState() => _ZoomPageState();
}

class _ZoomPageState extends State<_ZoomPage> {
  final _t = TransformationController();
  Offset? _tapAt;
  bool _zoomed = false;

  static const _doubleTapScale = 2.5;

  @override
  void initState() {
    super.initState();
    _t.addListener(_onTransform);
  }

  void _onTransform() {
    final z = _t.value.getMaxScaleOnAxis() > 1.01;
    if (z == _zoomed) return;
    _zoomed = z;
    widget.onZoom(z);
  }

  /* 두 번 톡 — 키웠으면 원래대로, 아니면 누른 자리를 중심으로 2.5배. 바로 바꿉니다(움직임 없이)
     — 끝나는 애니메이션이라도 이 화면의 일은 "보기" 라 기다릴 까닭이 없습니다. */
  void _toggle() {
    if (_zoomed) {
      _t.value = Matrix4.identity();
      return;
    }
    final p = _tapAt ?? Offset.zero;
    const s = _doubleTapScale;
    _t.value = Matrix4.diagonal3Values(s, s, 1)..setTranslationRaw(-p.dx * (s - 1), -p.dy * (s - 1), 0);
  }

  @override
  void dispose() {
    _t.removeListener(_onTransform);
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTapDown: (d) => _tapAt = d.localPosition,
      onDoubleTap: _toggle,
      child: InteractiveViewer(
        transformationController: _t,
        minScale: 1,
        maxScale: 5,
        child: Center(
          child: _Picture(api: widget.api, id: widget.id, n: widget.n, fit: BoxFit.contain, boxHeight: 240, onDark: true),
        ),
      ),
    );
  }
}

/* --- 설정의 줄 ------------------------------------------------------------------- */

/// 설정 → 도움말 맨 위 「의견함」 줄. **운영자에게만** 섭니다(아니면 아무것도 안 그림 —
/// 자리표시도 없이). 운영자인지는 /me 의 isOperator — 셸 · 친구 탭이 이미 받은 값이 Api 에
/// 있으면 그것을 쓰고, 아직 모르면 여기서 한 번 묻습니다. 안 읽은 개수는 의견함 첫 쪽(1건)의
/// unread 로 받아 옆에 띄우고, 의견함에서 돌아오면 다시 받습니다.
class FeedbackInboxRow extends StatefulWidget {
  const FeedbackInboxRow({super.key});

  @override
  State<FeedbackInboxRow> createState() => _FeedbackInboxRowState();
}

class _FeedbackInboxRowState extends State<FeedbackInboxRow> {
  int _unread = 0;

  /// 의견함이 403 을 줬음 — /me 가 참이어도(서버 설정이 바뀐 직후) 줄을 거둡니다.
  bool _refused = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_load()));
  }

  Future<void> _load() async {
    if (!mounted) return;
    final api = Scope.apiOf(context);
    if (!api.signedIn) return;
    if (api.isOperator == null) {
      await api.me();
      if (!mounted) return;
      setState(() {});
    }
    if (api.isOperator == true) await _count();
  }

  Future<void> _count() async {
    final p = await Scope.apiOf(context).fetchInbox(limit: 1);
    if (!mounted) return;
    if (p.denied) {
      setState(() => _refused = true);
    } else if (p.ok) {
      setState(() => _unread = p.unread);
    }
  }

  Future<void> _open() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FeedbackInboxScreen()));
    if (mounted) await _count();
  }

  @override
  Widget build(BuildContext context) {
    final api = Scope.apiOf(context);
    if (!api.signedIn || api.isOperator != true || _refused) return const SizedBox.shrink();
    final t = Theme.of(context);
    return ListTile(
      key: const Key('settings-feedback-inbox'),
      contentPadding: EdgeInsets.zero,
      leading: const Icon(LucideIcons.inbox),
      title: const Text(kInboxTitle),
      subtitle: Text('앱으로 온 의견 · 운영자에게만 보여요', style: t.textTheme.labelSmall),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (_unread > 0)
          Container(
            key: const Key('settings-feedback-inbox-unread'),
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(color: t.colorScheme.primary, borderRadius: BorderRadius.circular(999)),
            child: Text(_unread > 99 ? '99+' : '$_unread',
                semanticsLabel: '안 읽은 의견 $_unread개',
                style: TextStyle(
                    fontSize: 11.5, fontWeight: FontWeight.w700, color: t.colorScheme.onPrimary)),
          ),
        const SizedBox(width: 4),
        const Icon(LucideIcons.chevronRight, size: 18),
      ]),
      onTap: () => unawaited(_open()),
    );
  }
}
