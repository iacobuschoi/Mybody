/* =============================================================================
 * user_list.dart — 「가입자 목록」: 운영자가 앱 안에서 가입한 계정을 보는 곳
 *
 * 왜 있나 — 비밀번호를 잊은 친구를 풀어 주려면 그 사람의 아이디가 필요합니다. 지금까지는
 * 노트북에서 node tools/reset-password.js 를 인자 없이 돌려야 보였습니다. 이제 운영자 폰의
 * 설정 → 도움말 「의견함」 바로 아래 줄로 옵니다. 줄을 누르면 아이디가 복사됩니다 — 노트북의
 * reset-password.js <아이디> 에 그대로 붙여 넣으라고.
 *
 * 누가 보나 — 의견함과 같습니다(feedback_inbox.dart): /me 의 isOperator 가 참인 계정에만 줄이
 * 서고(다른 사람에게는 자리표시도 없음), 판정은 언제나 서버가 합니다 — 다른 계정이 닿아도
 * 403 이고 화면은 「운영자 계정으로 로그인하면 볼 수 있어요」 만 말합니다. 앱이 서버보다 먼저
 * 새 판이면(이 길이 없음 · 404) 줄은 서지 않고, 그래도 닿으면 「서버를 새 판으로 올리면 볼 수 있어요」.
 *
 * 무엇을 보여 주나 — 위에 「가입자 N명」, 새 가입부터 한 줄씩: 이름(굵게) · 아이디(흐리게) ·
 * 가입일(2026.09.28), 내 줄에는 작은 「나」. 서버는 1000명까지 싣고(server/db.js
 * USERS_LIST_MAX) 넘으면 「최근 1000명만 보여요」 한 줄. 끌어 내리면 새로 받습니다.
 * 실패는 의견함처럼 — 처음이면 가운데에 까닭과 「다시 시도」, 새로 고침이면 보던 목록 위에 한 줄.
 * ========================================================================== */
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../api.dart';
import '../scope.dart';
import '../ui/widgets.dart';
import 'feedback_inbox.dart' show ErrorRetryBox;

/// 화면 제목 · 설정의 줄 이름 — 같아야 헷갈리지 않습니다.
const kUsersTitle = '가입자 목록';

/// 가입일 — 이 폰의 날짜로 「2026.09.28」.
String userJoinedLabel(DateTime at) {
  final l = at.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${l.year}.${two(l.month)}.${two(l.day)}';
}

class OperatorUsersScreen extends StatefulWidget {
  const OperatorUsersScreen({super.key});

  @override
  State<OperatorUsersScreen> createState() => _OperatorUsersScreenState();
}

class _OperatorUsersScreenState extends State<OperatorUsersScreen> {
  List<OperatorUser> _users = const [];
  int _total = 0;

  /// 한 번이라도 받았나 — 못 받았으면 실패를 가운데에, 받았으면 맨 위에 한 줄로.
  bool _loaded = false;
  bool _loading = false;
  String? _error;

  /// 다시 해 봐도 같은 답 — 운영자가 아님(403) · 로그인 없음(401) · 이 길이 없는 옛 서버(404).
  /// 「다시 시도」 없이 무엇을 하면 되는지만.
  ({String text, String key})? _blocked;

  /// 새로 고침마다 하나씩 — 늦게 온 앞 답이 새 목록을 덮지 않게.
  int _gen = 0;
  Api? _api;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    /* Scope 는 기록이 바뀔 때마다 알립니다 — Api 가 바뀐 때(서버 주소)만 새로 받습니다. */
    final api = Scope.apiOf(context);
    if (identical(api, _api)) return;
    _api = api;
    _users = const [];
    _loaded = false;
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    final api = _api;
    if (api == null) return;
    final gen = ++_gen;
    setState(() => _loading = true);
    final p = await api.fetchOperatorUsers();
    if (!mounted || gen != _gen) return;
    setState(() {
      _loading = false;
      if (p.ok) {
        _users = p.users;
        _total = p.total;
        _loaded = true;
        _error = null;
        _blocked = null;
      } else if (p.denied || p.missing) {
        _blocked = p.missing
            ? (text: '서버를 새 판으로 올리면 볼 수 있어요', key: 'users-missing')
            : (text: p.reason, key: 'users-denied');
        _users = const [];
      } else {
        _error = p.reason;
      }
    });
  }

  Future<void> _copy(OperatorUser u) async {
    try {
      await Clipboard.setData(ClipboardData(text: u.handle));
    } catch (_) {
      if (mounted) toast(context, '복사하지 못했어요');
      return;
    }
    if (mounted) toast(context, '아이디를 복사했어요');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(kUsersTitle)),
      /* 비었을 때 · 실패했을 때도 끌어 내려 새로 받을 수 있게 늘 스크롤되는 목록입니다. */
      body: RefreshIndicator(onRefresh: _refresh, child: _body(context)),
    );
  }

  Widget _body(BuildContext context) {
    const physics = AlwaysScrollableScrollPhysics();
    if (_blocked case final b?) {
      return ListView(key: Key(b.key), physics: physics, children: [
        const SizedBox(height: 48),
        EmptyState(title: b.text),
      ]);
    }
    if (!_loaded) {
      final err = _error;
      return ListView(physics: physics, padding: const EdgeInsets.all(16), children: [
        const SizedBox(height: 48),
        if (err != null && !_loading)
          ErrorRetryBox(key: const Key('users-error'), message: err, retryKey: 'users-retry', onRetry: _refresh)
        else
          const Center(child: CircularProgressIndicator()),
      ]);
    }
    final t = Theme.of(context);
    final head = <Widget>[
      if (_error case final err?)
        ErrorRetryBox(key: const Key('users-error'), message: err, retryKey: 'users-retry', onRetry: _refresh),
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
        child: Text('가입자 $_total명',
            key: const Key('users-count'),
            style: t.textTheme.labelLarge?.copyWith(color: t.colorScheme.primary)),
      ),
      if (_total > _users.length)
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
          child: Text('최근 ${_users.length}명만 보여요',
              key: const Key('users-capped'), style: t.textTheme.labelSmall?.copyWith(color: t.hintColor)),
        ),
    ];
    if (_users.isEmpty) {
      return ListView(physics: physics, padding: const EdgeInsets.all(16), children: [
        ...head,
        const SizedBox(height: 32),
        const EmptyState(key: Key('users-empty'), title: '아직 가입자가 없어요'),
      ]);
    }
    return ListView.builder(
      key: const Key('users-list'),
      physics: physics,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: head.length + _users.length,
      itemBuilder: (context, i) {
        if (i < head.length) return head[i];
        final k = i - head.length;
        final u = _users[k];
        return _UserRow(
            key: ValueKey('users-row-${u.handle}'), user: u, last: k == _users.length - 1, onTap: () => _copy(u));
      },
    );
  }
}

/// 한 사람 — 이름(굵게) · 「나」 · 아이디(흐리게) · 가입일. 누르면 아이디 복사.
class _UserRow extends StatelessWidget {
  const _UserRow({super.key, required this.user, required this.last, required this.onTap});
  final OperatorUser user;
  final bool last;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final u = user;
    final at = u.createdAt;
    return Semantics(
      button: true,
      onTapHint: '아이디 복사',
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 11),
          decoration: BoxDecoration(
            border: last ? null : Border(bottom: BorderSide(color: t.dividerColor.withValues(alpha: 0.5))),
          ),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(
                    child: Text(u.displayName.isEmpty ? '이름 없음' : u.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                  if (u.me) ...[const SizedBox(width: 6), const _MeTag()],
                ]),
                const SizedBox(height: 2),
                /* 아이디는 32자까지 — 한 줄에 안 들어가면 두 줄로(복사는 늘 전부). */
                Text(u.handle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: t.textTheme.bodySmall?.copyWith(color: t.hintColor)),
              ]),
            ),
            const SizedBox(width: 12),
            if (at != null)
              Text(userJoinedLabel(at),
                  style: t.textTheme.labelSmall
                      ?.copyWith(color: t.hintColor, fontFeatures: const [FontFeature.tabularFigures()])),
            const SizedBox(width: 8),
            Icon(LucideIcons.copy, size: 14, color: t.hintColor),
          ]),
        ),
      ),
    );
  }
}

/// 운영자 본인 줄의 작은 「나」.
class _MeTag extends StatelessWidget {
  const _MeTag();

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Container(
      key: const Key('users-me'),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(color: c.primary.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(999)),
      child: Text('나', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c.primary)),
    );
  }
}

/* --- 설정의 줄 ------------------------------------------------------------------- */

/// 설정 → 도움말 「의견함」 바로 아래 「가입자 목록」 줄. **운영자에게만** 섭니다 —
/// FeedbackInboxRow 와 같은 규칙(아니면 아무것도 안 그림, 자리표시도 없이). 옆의 수는 목록을
/// 한 명만(limit=1) 받아 온 total 이고, 목록에서 돌아오면 다시 받습니다.
///
/// 줄은 그 길이 **답한 뒤에** 섭니다 — /me 가 운영자라고 해도 앱이 먼저 나가고 서버는 아직 옛 판
/// (이 길이 없음 · 404)일 수 있어서, 먼저 세우면 섰다가 사라지고(아래 스위치 · 버튼이 튐) 그 틈에
/// 누르면 빈 화면으로 갑니다. 403(설정이 바뀐 직후) · 404 면 서지 않습니다. 못 닿음 · 5xx 는 길이
/// 있는지 모르니 세웁니다(들어가서 까닭과 「다시 시도」 를 보게 — 의견함 줄과 같이). 한 번 받은 답은
/// Api 가 기억해서([ApiOperatorUsers.operatorUsersSeen]) 다음에 설정을 열 때는 기다리지 않습니다.
class OperatorUsersRow extends StatefulWidget {
  const OperatorUsersRow({super.key});

  @override
  State<OperatorUsersRow> createState() => _OperatorUsersRowState();
}

class _OperatorUsersRowState extends State<OperatorUsersRow> {
  /// 이 길이 답은 했는데 열렸는지 말해 주지 않는 실패(못 닿음 · 5xx)였음 — 앞 답이 없으면 세웁니다.
  bool _unsure = false;

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
      await api.askOperator();
      if (!mounted) return;
      setState(() {});
    }
    if (api.isOperator == true) await _count();
  }

  Future<void> _count() async {
    /* 열림 · 닫힘과 수는 Api 가 적어 둡니다(operatorUsersSeen) — 여기서는 다시 그리기만. */
    final p = await Scope.apiOf(context).fetchOperatorUsers(limit: 1);
    if (!mounted) return;
    setState(() => _unsure = !p.ok && !p.denied && !p.missing);
  }

  Future<void> _open() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OperatorUsersScreen()));
    if (mounted) await _count();
  }

  @override
  Widget build(BuildContext context) {
    final api = Scope.apiOf(context);
    final seen = api.operatorUsersSeen;
    if (!api.signedIn || api.isOperator != true || !(seen?.open ?? _unsure)) return const SizedBox.shrink();
    final total = seen?.total ?? 0;
    final t = Theme.of(context);
    return ListTile(
      key: const Key('settings-operator-users'),
      contentPadding: EdgeInsets.zero,
      leading: const Icon(LucideIcons.users),
      title: const Text(kUsersTitle),
      subtitle: Text('아이디 · 가입일 · 운영자에게만 보여요', style: t.textTheme.labelSmall),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (total > 0)
          Text('$total명',
              key: const Key('settings-operator-users-count'),
              style: t.textTheme.labelMedium?.copyWith(color: t.hintColor)),
        const SizedBox(width: 4),
        const Icon(LucideIcons.chevronRight, size: 18),
      ]),
      onTap: () => unawaited(_open()),
    );
  }
}
