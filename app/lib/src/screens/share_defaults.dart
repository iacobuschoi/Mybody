/* =============================================================================
 * share_defaults.dart — 「친구에게 기본으로 보여 주는 것」 카드
 *
 * 친구를 맺는 순간 서버가 이 값을 그 관계로 복사합니다(server/db.js accept).
 * 그래서 여기서 바꾸는 것은 **앞으로 맺을 친구**에 대한 것이고, 이미 맺은
 * 친구는 「지금 친구 모두에게 적용」 을 눌렀을 때만 바뀝니다 — 한 번 더 묻고.
 *
 * 주인의 규칙(피드백 40): 체성분은 기본 꺼짐, 나머지는 기본 켜짐. 그 처음
 * 값은 서버가 들고 있고(blankShare), 앱은 서버가 준 값만 그립니다 — 앱이
 * 따로 기본값을 들고 있으면 둘이 어긋나는 날이 옵니다.
 *
 * 설정 화면과 친구 탭이 같은 카드를 씁니다. 스위치 이름(kShareFields)도
 * 친구 상세와 같은 상수 하나 — 같은 스위치가 두 곳에서 다른 이름이면
 * 다른 것으로 읽힙니다.
 * ========================================================================== */
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api.dart';
import '../scope.dart';
import '../ui/widgets.dart';

/// 공유 스위치 — **서버가 아는 이름 그대로** (server/db.js 의 SHARE_FIELDS).
/// 예전엔 weight·smm 같은 다른 이름으로 보내서, 켜도 서버가 버렸습니다 —
/// 스위치는 켜졌는데 나가는 건 없었습니다. 친구 상세와 이 카드가 같이 씁니다.
const kShareFields = [
  ('streak', '기록 여부 · 스트릭'),
  ('schedule', '이번 주 운동 (요일별 계획·체크)'),
  ('diet', '오늘 식단 (칼로리·탄단지)'),
  ('weightTrend', '체중 변화'),
  ('smmTrend', '골격근 변화'),
  ('bfmTrend', '체지방 변화'),
  ('absolute', '변화량이 아니라 실제 수치까지'),
  ('planProgress', '목표 진행률'),
];

/// 「실제 수치까지」 는 켠 몸 항목을 숫자로 여는 스위치라, 몸 항목이 하나도
/// 없으면 뜻이 없습니다. 서버(patchShare)와 같은 규칙 — 화면이 먼저 알면
/// 켰다가 튕겨 나가는 스위치를 안 봅니다.
const _bodyKeys = ['weightTrend', 'smmTrend', 'bfmTrend'];

/// 짧은 이름 — 확인 창 · 받은 요청 줄처럼 한 줄에 여럿을 늘어놓는 곳에서.
const _shortLabel = {
  'streak': '스트릭', 'schedule': '이번 주 운동', 'diet': '오늘 식단',
  'weightTrend': '체중 변화', 'smmTrend': '골격근 변화', 'bfmTrend': '체지방 변화',
  'planProgress': '목표 진행률', 'absolute': '실제 수치',
};

/// 몸 쪽 — 체성분 셋 · 목표 진행률(체지방으로 계산) · 실제 수치. 서버 blankShare 가
/// 기본 꺼짐으로 두는 묶음과 같습니다. 이게 켜진 채로 나가는지는 따로 눈에 띄게 말합니다.
const _bodyish = ['weightTrend', 'smmTrend', 'bfmTrend', 'planProgress', 'absolute'];

/// 켜진 항목의 짧은 이름 — 몸 쪽(body)과 나머지(rest)를 나눠서, kShareFields 순서로.
({List<String> body, List<String> rest}) shareOnLabels(Map<String, bool> flags) {
  final body = <String>[], rest = <String>[];
  for (final f in kShareFields) {
    if (flags[f.$1] != true) continue;
    (_bodyish.contains(f.$1) ? body : rest).add(_shortLabel[f.$1] ?? f.$2);
  }
  return (body: body, rest: rest);
}

/// 「무엇이 보이나」 한 줄 — `lead: 스트릭 · 오늘 식단 · 체중 변화`. 몸 쪽은 경고색
/// 굵게. 수락 버튼 옆과 「모두에게 적용」 확인 창이 씁니다 — 동의는 읽은 문장에
/// 대해 하는 것이라, 누르기 직전에 실제로 나갈 것을 보여 줍니다.
class ShareReach extends StatelessWidget {
  const ShareReach({super.key, required this.flags, required this.lead, this.style});
  final Map<String, bool> flags;
  final String lead;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final on = shareOnLabels(flags);
    final base = style ?? Theme.of(context).textTheme.bodySmall;
    return Text.rich(
      TextSpan(style: base, children: [
        TextSpan(text: '$lead: '),
        if (on.rest.isEmpty && on.body.isEmpty) const TextSpan(text: '없음'),
        TextSpan(text: on.rest.join(' · ')),
        if (on.rest.isNotEmpty && on.body.isNotEmpty) const TextSpan(text: ' · '),
        if (on.body.isNotEmpty)
          TextSpan(
              text: on.body.join(' · '),
              style: TextStyle(color: mb(context).warn, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

/// `/friends` 응답의 수락된 친구 id — 못 받았으면 null.
List<String>? acceptedFriendIds(ApiResult r) {
  final f = r.ok ? r.body['friends'] : null;
  final list = f is Map ? f['accepted'] : null;
  if (list is! List) return null;
  return [for (final p in list) if (p is Map && p['id'] != null) '${p['id']}'];
}

/// 친구 한 사람의 공유 설정 캐시 열쇠 — 친구 상세가 쓰고, 「모두에게 적용」
/// 뒤에 이 카드가 고쳐 씁니다. 안 고치면 비행기 모드의 친구 상세가 적용 전
/// 값을 보여 주고, 사람은 그걸 믿고 다시 바꿉니다.
const kShareCachePrefix = 'mybody.share.cache.v1.';
String shareCacheKey(String friendId) => '$kShareCachePrefix$friendId';

/// 서버가 준 맵에서 스위치 값만. 모르는 이름 · 참/거짓이 아닌 값은 버리고,
/// 없는 이름은 꺼짐 — 서버의 읽기 규칙(shareFields)과 같습니다.
Map<String, bool> shareFlagsFrom(Object? raw) {
  final m = raw is Map ? raw : const {};
  return {for (final f in kShareFields) f.$1: m[f.$1] == true};
}

/// 친구 탭에서 여는 화면 — 설정의 카드와 같은 것을 펼친 채로.
class ShareDefaultsScreen extends StatelessWidget {
  const ShareDefaultsScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('기본 공유')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: const [ShareDefaultsCard(expanded: true)],
        ),
      );
}

class ShareDefaultsCard extends StatefulWidget {
  const ShareDefaultsCard({super.key, this.expanded = false});

  /// 설정에서는 접어 둡니다(친구 상세의 「내가 이 친구에게 보여 주는 것」 과
  /// 같은 모양). 친구 탭에서 일부러 들어온 화면은 펼친 채로.
  final bool expanded;

  @override
  State<ShareDefaultsCard> createState() => _ShareDefaultsCardState();
}

class _ShareDefaultsCardState extends State<ShareDefaultsCard> {
  static const _cacheKey = 'mybody.share.defaults.cache.v1';

  /// 화면에 보이는 값 — 누른 스위치가 서버 답보다 먼저 반영됩니다.
  Map<String, bool>? _flags;
  /// 서버가 마지막으로 확인해 준 값(GET · PUT 응답, 못 닿았으면 그 값을 적어 둔
  /// 캐시). 실패하면 **여기로** 되돌립니다. 누르기 직전 값으로 되돌리면, 앞서
  /// 누른 스위치가 아직 가는 중일 때 그 스위치가 서버와 다른 채로 남습니다 —
  /// 화면은 체중 꺼짐, 서버는 켜짐.
  Map<String, bool>? _confirmed;
  /// _confirmed 가 몇 번째 요청 뒤의 값인가 — 늦게 온 옛 응답이 새 값을 덮지 않게.
  int _confirmedSeq = 0;
  bool _loading = true;
  bool _started = false;
  /// 옛 서버(이 길이 없음) — 카드는 한 줄로 줄어듭니다.
  bool _unsupported = false;
  /// 서버에 못 닿아 마지막으로 본 값을 보여 주는 중.
  bool _fromCache = false;
  String? _error;
  bool _applying = false;
  /// 스위치를 빨리 여러 번 누르면 요청이 겹칩니다. 전부 끝난 뒤에 한 번에
  /// 서버가 확인한 값으로 맞춥니다.
  int _seq = 0;
  int _inflight = 0;
  /// 가는 중에 실패 · 겹침 · 알 수 없는 답이 있었다 — 다 끝나면 서버 값을 다시 읽습니다.
  bool _recheck = false;
  String? _failReason;
  /// 수락된 친구 수. 0 이면 「모두에게 적용」 을 안 보입니다. 모르면 null.
  int? _friendCount;

  void _remember(Map<String, bool> flags) {
    unawaited(() async {
      try {
        final sp = await SharedPreferences.getInstance();
        await sp.setString(_cacheKey, jsonEncode(flags));
      } catch (_) {}
    }());
  }

  Future<Map<String, bool>?> _recall() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final s = sp.getString(_cacheKey);
      return s == null ? null : shareFlagsFrom(jsonDecode(s));
    } catch (_) {
      return null;
    }
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
    final seq = _seq;
    final both = await Future.wait([api.getShareDefaults(), api.friends()]);
    if (!mounted) return;
    final r = both[0];
    final ids = acceptedFriendIds(both[1]);
    if (ids != null) _friendCount = ids.length;
    if (r.status == 404) {
      setState(() { _unsupported = true; _loading = false; });
      return;
    }
    /* 읽는 동안 스위치를 또 눌렀으면 이 값은 이미 옛것입니다 — 그 요청의 답이
       더 새 값을 가져옵니다. */
    if (seq != _seq || _inflight > 0) {
      setState(() => _loading = false);
      return;
    }
    if (r.ok && r.body['defaults'] is Map) {
      final flags = shareFlagsFrom(r.body['defaults']);
      _remember(flags);
      setState(() {
        _flags = flags;
        _confirmed = flags;
        _confirmedSeq = seq;
        _fromCache = false;
        _error = null;
        _loading = false;
      });
      return;
    }
    /* 못 닿았다고 스위치를 전부 꺼진 채로 그리지 않습니다 — 그러면 사람은
       "다 꺼졌네" 하고 다시 켭니다. 마지막으로 본 값이 있으면 그걸, 없으면
       모른다고만. */
    final cached = await _recall();
    if (!mounted) return;
    setState(() {
      _flags = cached ?? _confirmed ?? _flags;
      _confirmed = _flags;
      _fromCache = _flags != null;
      _error = _flags == null ? r.reason : null;
      _loading = false;
    });
  }

  Future<void> _toggle(String key, bool on) async {
    final cur = _flags;
    if (cur == null) return;
    final next = {...cur, key: on};
    if (!_bodyKeys.any((k) => next[k] == true)) next['absolute'] = false;
    final seq = ++_seq;
    /* 겹친 요청은 서버에 닿는 순서가 보장되지 않습니다 — 끝나면 한 번 더 읽습니다. */
    if (_inflight > 0) _recheck = true;
    _inflight++;
    setState(() => _flags = next);
    final r = await Scope.apiOf(context).setShareDefaults({key: on});
    if (!mounted) return;
    if (r.status == 404) {
      _inflight--;
      setState(() => _unsupported = true);
      return;
    }
    if (r.ok && r.body['defaults'] is Map) {
      if (seq > _confirmedSeq) {
        final flags = shareFlagsFrom(r.body['defaults']);
        _confirmed = flags;
        _confirmedSeq = seq;
        _fromCache = false;
        _remember(flags);
      }
    } else {
      /* 실패 — 시간 초과면 서버가 저장했는데 답만 잃었을 수도 있습니다. 모르는
         채로 두지 않고 다 끝나면 다시 읽습니다. */
      _recheck = true;
      if (!r.ok) _failReason = r.reason;
    }
    _inflight--;
    if (_inflight > 0) return;       // 가는 중인 것이 남았으면 그게 끝날 때 한 번에

    final reason = _failReason, recheck = _recheck;
    _failReason = null;
    _recheck = false;
    /* 서버가 확인한 값으로 맞춥니다. 기본값은 친구를 맺는 순간 서버에서 쓰이는
       값이라, 화면만 바뀌고 서버가 모르면 새 친구에게 다른 것이 나갑니다. */
    setState(() => _flags = _confirmed ?? _flags);
    if (reason != null) toast(context, reason);
    if (recheck) await _load();
  }

  Future<void> _applyAll() async {
    final api = Scope.apiOf(context);
    final queue = Scope.queueOf(context);
    setState(() => _applying = true);
    void stop([String? why]) {
      if (!mounted) return;
      setState(() => _applying = false);
      if (why != null) toast(context, why);
    }

    /* 친구 상세에서 바꾸고 못 보낸 것(큐)부터. 남긴 채로 적용하면, 나중에
       도착한 옛 변경이 방금 적용한 값을 조용히 되돌립니다. */
    if (queue != null && queue.pendingOf('setShare') > 0) {
      try {
        await queue.flush().timeout(const Duration(seconds: 25));
      } catch (_) {}
      if (!mounted) return;
      if (queue.pendingOf('setShare') > 0) {
        return stop('친구별로 바꾼 공유가 아직 서버에 안 갔습니다 — 잠시 뒤 다시 해 주세요');
      }
    }

    /* 화면의 값은 캐시에서 온 옛 값일 수 있습니다. 서버의 지금 값과 친구 수를
       다시 받아 그걸 보여 주고 묻습니다. */
    final both = await Future.wait([api.getShareDefaults(), api.friends()]);
    if (!mounted) return;
    final g = both[0];
    if (!g.ok || g.body['defaults'] is! Map) {
      if (g.status == 404) setState(() => _unsupported = true);
      return stop(g.reason);
    }
    final flags = shareFlagsFrom(g.body['defaults']);
    final ids = acceptedFriendIds(both[1]);
    _remember(flags);
    setState(() {
      _flags = flags;
      _confirmed = flags;
      _confirmedSeq = _seq;
      _fromCache = false;
      if (ids != null) _friendCount = ids.length;
    });
    if (ids != null && ids.isEmpty) return stop('아직 친구가 없습니다');
    /* 묻는 동안은 도는 원을 멈춥니다(창 뒤에서 계속 돌면 아직 뭔가 가는 줄
       압니다). 창이 모달이라 그 사이 스위치는 못 누릅니다. */
    stop();

    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final t = Theme.of(ctx);
        return AlertDialog(
          title: Text(ids == null ? '친구 모두에게 적용할까요?' : '친구 ${ids.length}명에게 적용할까요?'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            ShareReach(flags: flags, lead: '보여 줄 것', style: t.textTheme.bodyMedium),
            const SizedBox(height: 8),
            Text('친구마다 따로 정한 것도 덮어씁니다',
                style: t.textTheme.bodySmall?.copyWith(color: t.hintColor)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('그대로')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('적용')),
          ],
        );
      },
    );
    if (yes != true || !mounted) return;
    setState(() => _applying = true);
    /* 본 값을 같이 보냅니다 — 그 사이 다른 기기에서 바뀌었으면 서버가 409 로
       돌려보내고 아무것도 안 바꿉니다. */
    final r = await api.applyShareDefaults(expect: flags);
    if (!mounted) return;
    if (r.status == 409 && r.body['defaults'] is Map) {
      final now = shareFlagsFrom(r.body['defaults']);
      _remember(now);
      setState(() { _flags = now; _confirmed = now; _confirmedSeq = _seq; });
      return stop(r.reason);
    }
    if (!r.ok) {
      if (r.status == 404) setState(() => _unsupported = true);
      return stop(r.reason);
    }
    final n = (r.body['applied'] as num?)?.toInt() ?? 0;
    stop(n == 0 ? '아직 친구가 없습니다' : '친구 $n명에게 적용했습니다');
    await _rewriteFriendCaches(flags, ids);
  }

  /* 친구 상세의 캐시도 방금 적용한 값으로 — 안 고치면 비행기 모드의 친구
     상세가 적용 전 값을 보여 주고, 사람은 그걸 믿고 다시 바꿉니다. 서버는
     expect 와 같을 때만 적용하므로 쓴 값은 [flags] 그대로입니다. 수락된
     친구만 고칩니다 — 대기 · 차단 · 끊은 사람의 캐시에 "적용됨" 을 쓰지
     않습니다. 친구 목록을 못 받았으면 이 계정의 캐시 전부(로그아웃하면 지워져
     다른 계정 것은 없습니다). */
  Future<void> _rewriteFriendCaches(Map<String, bool> flags, List<String>? ids) async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = jsonEncode(flags);
      final keys = ids != null
          ? ids.map(shareCacheKey)
          : sp.getKeys().where((k) => k.startsWith(kShareCachePrefix)).toList();
      for (final k in keys) {
        await sp.setString(k, raw);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final hint = t.textTheme.labelSmall?.copyWith(color: t.hintColor);
    final title = Text('친구에게 기본으로 보여 주는 것',
        style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700));

    if (_unsupported || (_flags == null && !_loading)) {
      return MbCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SectionTitle('친구에게 기본으로 보여 주는 것',
              trailing: _unsupported
                  ? null
                  : IconButton(
                      tooltip: '다시',
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        setState(() => _loading = true);
                        _load();
                      },
                      icon: const Icon(LucideIcons.refreshCw, size: 18))),
          Text(_unsupported ? '서버를 업데이트하면 쓸 수 있습니다' : (_error ?? ''), style: hint),
        ]),
      );
    }

    final flags = _flags ?? const <String, bool>{};
    final on = kShareFields.where((f) => flags[f.$1] == true).length;
    final bodyOn = _bodyKeys.any((k) => flags[k] == true);

    return MbCard(
      child: Theme(
        data: t.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: EdgeInsets.zero,
          initiallyExpanded: widget.expanded,
          title: title,
          subtitle: Text(
              _loading
                  ? '불러오는 중'
                  : '$on개 켜짐 · 새 친구에게 자동으로 적용'
                      '${_fromCache ? ' · 서버에 못 닿아 마지막으로 본 설정' : ''}',
              style: hint),
          children: [
            if (_loading)
              const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator())
            else ...[
              for (final f in kShareFields)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(f.$2),
                  value: flags[f.$1] == true,
                  /* 몸 항목이 하나도 없으면 「실제 수치까지」 는 뜻이 없어 잠급니다.
                     적용하는 동안에도 — 확인 창에 보인 값이 보낸 값이어야 합니다. */
                  onChanged: _applying || (f.$1 == 'absolute' && !bodyOn)
                      ? null
                      : (v) => _toggle(f.$1, v),
                ),
              /* 친구가 없으면 적용할 사람도 없습니다. 스위치가 가는 중이면 잠급니다 —
                 서버에 아직 없는 값을 친구 전원에게 쓰는 버튼이 되면 안 됩니다. */
              if (_friendCount != 0) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _applying || _inflight > 0 ? null : _applyAll,
                    icon: _applying
                        ? const SizedBox(
                            width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(LucideIcons.users, size: 18),
                    label: const Text('지금 친구 모두에게 적용'),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
