/* =============================================================================
 * merge.dart — 두 기기의 기록을 하나로 합칩니다 (cloud.dart 가 씁니다)
 *
 * 예전에는 "마지막에 바꾼 기기가 통째로 이긴다" 였습니다. 폰에서 식단을
 * 적고 태블릿에서 측정을 넣으면, 나중에 저장한 쪽이 다른 쪽이 넣은 것을
 * 조용히 지웠습니다. 주인이 그걸 겪었습니다 — "다른 기기에서 넣은 게 안
 * 보인다".
 *
 * 그래서 통째로가 아니라 **칸마다** 합칩니다:
 *   · 측정·식단·체크인처럼 항목이 쌓이는 목록은 **합집합**. 같은 항목이
 *     양쪽에 있으면 나중에 고친 쪽. 어느 한쪽에서 지운 것은 지운 것으로
 *     (tombstones — 지운 항목의 번호와 시각. store.dart 가 남깁니다).
 *   · 운동 일정은 날짜마다. 한쪽만 바꾼 날은 그쪽, 둘 다 바꾼 날은 합집합
 *     (계획은 둘 다, 체크는 먼저 누른 시각, 기록은 더 많이 한 쪽).
 *   · 프로필·목표·계획·설정 같은 하나짜리 값은 **더 나중에 바꾼 쪽**.
 *     설정은 항목마다 따로 봅니다. 온보딩·고지 동의는 어느 쪽이든 했으면
 *     한 것입니다.
 *   · 모르는 칸은 버리지 않습니다 — 백업에서 칸이 사라지는 것은 데이터가
 *     사라지는 것입니다.
 *
 * "어느 쪽이 바꿨나" 를 알려면 **지난번에 맞춰 둔 상태(기준본)** 가 있어야
 * 합니다. 양쪽만 놓고 보면 "여기 없고 저기 있는 것" 이 저쪽이 넣은 건지
 * 이쪽이 지운 건지 알 수 없습니다. 그걸 모르고 합집합으로만 가면 **한
 * 기기에서도** 체크를 풀 수가 없습니다 — 풀고 3초 뒤에 서버 것과 합쳐지며
 * 다시 켜집니다. 기준본이 없으면(처음 맞출 때, 로그인 직후) 합집합으로
 * 갑니다 — 잃는 것보다 되살아나는 것이 낫습니다.
 *
 * 값마다 마지막으로 바뀐 시각(syncMeta.changedAt)을 레코드에 같이 실어
 * 둡니다. 두 기기가 같은 칸을 서로 다르게 바꿨을 때 그걸로 가리고, 올리기가
 * 엇갈렸을 때(상대가 내 것을 못 보고 올림) 내 것이 되돌아가지 않게 막습니다.
 * syncMeta.from 은 그 레코드가 어느 서버 상태를 보고 만들어졌는지 — 내
 * 기준본보다 옛것을 보고 만든 레코드에 없는 항목은 지운 것이 아닙니다.
 *
 * 여기는 순수 함수만 있습니다 — 같은 입력이면 같은 답. 시험이 그걸 봅니다.
 * ========================================================================== */
library;

import 'dart:convert';

/// 레코드에 같이 실리는 동기화용 칸. 저장소에는 안 남습니다 — cloud.dart 가
/// 들이기 전에 떼어 내고, 올릴 때 다시 붙입니다.
const String syncMetaKey = 'syncMeta';

/// 지운 것의 묘비가 사는 칸 — {scans: {id: 시각}, foodLogs: {id: 시각}, …}.
/// mybody_core 의 store.dart 가 지울 때 적고, 여기서는 양쪽 것을 합칩니다.
const String tombstonesKey = 'tombstones';

/// 항목이 쌓이는 목록과, 같은 항목을 알아보는 칸.
const Map<String, String> mergedLists = {
  'scans': 'id', 'foodLogs': 'id', 'checkins': 'at',
  /* 즐겨찾기 · 목표 이력도 쌓이는 목록입니다 — 통째로 이기고 지면 한쪽이 더한 것을 잃습니다.
     id 가 없으면 내용 자체가 id 입니다(_byId). */
  'foodFavorites': 'id', 'goalHistory': 'at',
};

/// 따로 규칙이 있는 칸들. 나머지는 전부 "하나짜리 값" 입니다.
final Set<String> _special = {
  'version', syncMetaKey, tombstonesKey, 'schedule', 'settings',
  ...mergedLists.keys,
};

/// 어느 쪽이든 참이면 참. 한 기기에서 온보딩을 마쳤으면 마친 것입니다.
const Set<String> _orFlags = {'onboarded', 'disclaimerAccepted'};

/// 계획 목록의 순서 — 헬스 다음 유산소 (schedule.dart 의 kSchedTypes 순서).
const List<String> _planOrder = ['gym', 'cardio'];

/* --- 같은가 ------------------------------------------------------------------ */

/// 키 순서와 숫자 표기(187 과 187.0)에 흔들리지 않는 JSON. 같은 내용이면
/// 같은 글자입니다 — 두 상태가 같은지는 이걸로 봅니다.
String canonicalJson(Object? v) => jsonEncode(_canon(v), toEncodable: (o) => '$o');

Object? _canon(Object? v) {
  if (v is Map) {
    final entries = [for (final e in v.entries) MapEntry('${e.key}', e.value)]
      ..sort((a, b) => a.key.compareTo(b.key));
    return {for (final e in entries) e.key: _canon(e.value)};
  }
  if (v is List) return [for (final e in v) _canon(e)];
  if (v is double) {
    if (!v.isFinite) return null;
    /* 웹(자바스크립트)은 187.0 을 187 로 적습니다. 같은 값입니다. */
    if (v == v.roundToDouble() && v.abs() < 9007199254740992) return v.toInt();
  }
  return v;
}

/// 두 상태가 내용으로 같은가 (깊은 비교).
bool sameState(Map<String, Object?> a, Map<String, Object?> b) =>
    canonicalJson(a) == canonicalJson(b);

/// "그 칸이 없다" 를 null 과 구분하는 표시. goal 은 null 일 수 있으니까요.
final Object _absent = Object();

bool _eq(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (identical(a, _absent) || identical(b, _absent)) return false;
  return canonicalJson(a) == canonicalJson(b);
}

Map<String, Object?> _mapOf(Object? v) =>
    v is Map ? v.cast<String, Object?>() : const <String, Object?>{};

Object? _slot(Map<String, Object?> m, String k) => m.containsKey(k) ? m[k] : _absent;

String _later(String a, String b) => a.compareTo(b) >= 0 ? a : b;

/* --- 동기화용 칸 -------------------------------------------------------------- */

/// 칸마다 마지막으로 바뀐 시각 — {'goal': iso, 'settings.theme': iso,
/// 'schedule.2026-09-24': iso, …}. 없는 칸은 레코드 전체의 시각으로 칩니다.
Map<String, String> stampsOf(Map<String, Object?> state) {
  final m = state[syncMetaKey];
  final c = m is Map ? m['changedAt'] : null;
  if (c is! Map) return const {};
  return {for (final e in c.entries) if (e.value is String) '${e.key}': e.value as String};
}

/// 그 레코드가 어느 서버 상태(updatedAt)를 보고 만들어졌는가. 모르면 null —
/// 옛 앱과 웹은 이 칸이 없습니다.
String? syncFromOf(Map<String, Object?> state) {
  final m = state[syncMetaKey];
  final f = m is Map ? m['from'] : null;
  return f is String ? f : null;
}

/// 동기화용 칸을 뗀 복사본 — 저장소에 들이는 것은 이것입니다.
Map<String, Object?> withoutSyncMeta(Map<String, Object?> state) =>
    {for (final e in state.entries) if (e.key != syncMetaKey) e.key: e.value};

/// 이 기기의 상태에 시각을 붙입니다: 기준본의 시각을 이어받고, 기준본과 다른
/// 칸은 [at](이 기기가 마지막으로 바꾼 시각)으로 찍습니다. 기준본이 없으면
/// 찍을 것이 없습니다 — 그때는 레코드 전체의 시각으로 견줍니다.
Map<String, Object?> stampLocalChanges(Map<String, Object?> state, Map<String, Object?>? base,
    {required String at, String from = ''}) {
  final out = withoutSyncMeta(state);
  final stamps = <String, String>{if (base != null) ...stampsOf(base)};
  if (base != null) {
    for (final k in {...state.keys, ...base.keys}) {
      if (_special.contains(k)) continue;
      if (!_eq(_slot(state, k), _slot(base, k))) stamps[k] = at;
    }
    final ss = _mapOf(state['settings']), bs = _mapOf(base['settings']);
    for (final k in {...ss.keys, ...bs.keys}) {
      if (!_eq(_slot(ss, k), _slot(bs, k))) stamps['settings.$k'] = at;
    }
    final sd = _mapOf(state['schedule']), bd = _mapOf(base['schedule']);
    for (final d in {...sd.keys, ...bd.keys}) {
      if (!_eq(_slot(sd, d), _slot(bd, d))) stamps['schedule.$d'] = at;
    }
  }
  out[syncMetaKey] = {'changedAt': stamps, 'from': from};
  return out;
}

/* --- 누가 이기나 --------------------------------------------------------------- */

enum _Who { same, local, remote, both }

class _Ctx {
  _Ctx({
    required this.localAt,
    required this.remoteAt,
    required this.sl,
    required this.sr,
    required this.hasBase,
    required this.trustRemote,
    required String? baseAt,
    required String? baseFrom,
    required String? remoteFrom,
  })  : _localFallback = !hasBase
            ? localAt
            : (baseFrom != null && baseFrom.isNotEmpty)
                ? baseFrom
                : (baseAt != null && baseAt.isNotEmpty ? baseAt : localAt),
        _remoteFallback = remoteFrom != null && remoteFrom.isNotEmpty ? remoteFrom : remoteAt;

  final String localAt, remoteAt;
  final Map<String, String> sl, sr;

  /// 기준본이 있어 "누가 바꿨나" 를 볼 수 있는가.
  final bool hasBase;

  /// 서버 레코드가 내 기준본을 본 뒤에 만들어진 것인가. 아니면 거기 없는
  /// 것을 "지웠다" 로 읽으면 안 됩니다 — 아직 못 본 것일 뿐입니다.
  final bool trustRemote;

  /* 시각이 안 붙은 칸을 언제 것으로 칠까. 기준본이 있으면 그 뒤로 안 바꾼
     칸이고(바꿨으면 시각이 붙습니다), 기준본에도 시각이 없다는 것은 기준본을
     만들 때 본 서버 상태(from)에 이미 그 값이 있었다는 뜻이라 그 시각이
     상한입니다. 서버 쪽도 같은 이유로 그 레코드의 from 이 상한입니다. 둘 다
     모르면 레코드 전체의 시각입니다. 상한을 실제보다 늦게 잡으면 아무도 안
     바꾼 값이 남이 진짜로 바꾼 값을 이깁니다. */
  final String _localFallback, _remoteFallback;

  String effL(String slot) => sl[slot] ?? _localFallback;
  String effR(String slot) => sr[slot] ?? _remoteFallback;

  /// 값이 같은 칸의 시각 — 있는 것 중 나중 것. 둘 다 없으면 없습니다.
  String? stampSame(String slot) {
    final a = sl[slot], b = sr[slot];
    if (a == null) return b;
    if (b == null) return a;
    return _later(a, b);
  }

  _Who who(String slot, Object? l, Object? r, Object? b) {
    if (_eq(l, r)) return _Who.same;
    if (hasBase && trustRemote) {
      final lc = !_eq(l, b), rc = !_eq(r, b);
      final a = sl[slot], z = sr[slot];
      /* 한쪽만 바꿨으면 그쪽. 다만 시각이 둘 다 있고 저쪽 것이 내 것보다
         **옛것**이면 — 저쪽이 내 올리기를 못 본 채 올린 것이라 — 내 것. */
      if (!lc && rc) return (a != null && z != null && a.compareTo(z) > 0) ? _Who.local : _Who.remote;
      if (lc && !rc) return (a != null && z != null && z.compareTo(a) > 0) ? _Who.remote : _Who.local;
    }
    return _Who.both;
  }

  /// 둘 다 바꿨거나 누가 바꿨는지 모를 때 — 더 나중에 바꾼 쪽. 같으면 서버.
  /// 한쪽에만 있거나 한쪽이 비어(null) 있으면 있는 쪽 — 누가 바꿨는지 모르는
  /// 채로 값을 비우는 것은 잃는 쪽이고, 일부러 비운 것은 기준본이 있으면
  /// [who] 가 먼저 가립니다.
  Object? lww(String slot, Object? l, Object? r) {
    if (identical(l, _absent) || l == null) return r;
    if (identical(r, _absent) || r == null) return l;
    /* 빈 목록 · 빈 Map 은 "없음" 과 같게 봅니다 — 막 깐 기기의 빈 기본값이 시각만
       늦다는 이유로 계정의 즐겨찾기 · 목표 이력을 비운 적이 있습니다. 일부러 비운
       것은 기준본이 있으면 who 가 먼저 가립니다. */
    final le = _emptyColl(l), re = _emptyColl(r);
    if (le && !re) return r;
    if (re && !le) return l;
    return effL(slot).compareTo(effR(slot)) > 0 ? l : r;
  }

  static bool _emptyColl(Object? v) => (v is List && v.isEmpty) || (v is Map && v.isEmpty);

  String? stampFor(String slot, _Who who) => switch (who) {
        _Who.same => stampSame(slot),
        _Who.local => effL(slot),
        _Who.remote => effR(slot),
        _Who.both => _later(effL(slot), effR(slot)),
      };
}

/* --- 합치기 ------------------------------------------------------------------- */

/// 이 기기의 상태([local])와 서버의 상태([remote])를 합칩니다.
///
/// [localAt] · [remoteAt] 는 각각을 마지막으로 바꾼 시각(ISO). 칸마다 시각이
/// 없을 때 그걸로 견줍니다. [base] 는 지난번에 맞춰 둔 상태, [baseAt] 는 그때
/// 서버에 있(게 되)었던 시각 — 있으면 "누가 바꿨나" 를 알 수 있습니다.
///
/// 돌아오는 것은 저장소에 그대로 들일 수 있는 상태에 [syncMetaKey] 가 붙은
/// 것입니다. 입력은 건드리지 않습니다.
Map<String, Object?> mergeStates(Map<String, Object?> local, Map<String, Object?> remote,
    {required String localAt, required String remoteAt, Map<String, Object?>? base, String? baseAt}) {
  final hasBase = base != null;
  final from = syncFromOf(remote);
  final trustRemote = !hasBase ||
      baseAt == null || baseAt.isEmpty ||
      remoteAt == baseAt ||
      (from != null && from.compareTo(baseAt) >= 0);
  final c = _Ctx(
    localAt: localAt, remoteAt: remoteAt,
    sl: stampsOf(local), sr: stampsOf(remote),
    hasBase: hasBase, trustRemote: trustRemote,
    baseAt: baseAt, baseFrom: hasBase ? syncFromOf(base) : null, remoteFrom: from,
  );
  final b = base ?? const <String, Object?>{};
  final out = <String, Object?>{};
  final stamps = <String, String>{};
  final tomb = _tombstones(local, remote);

  /* 판은 이 기기 것. 다르면 cloud.dart 가 여기 오기 전에 멈춥니다. */
  if (local.containsKey('version') || remote.containsKey('version')) {
    out['version'] = local.containsKey('version') ? local['version'] : remote['version'];
  }

  final keys = [...local.keys, for (final k in remote.keys) if (!local.containsKey(k)) k];
  for (final k in keys) {
    if (k == 'version' || k == syncMetaKey || k == tombstonesKey) continue;
    if (mergedLists.containsKey(k)) {
      final dead = tomb[k] ?? <String, String>{};
      out[k] = _mergeList(k, mergedLists[k]!, local, remote, b, c, dead);
      /* 묘비 칸은 세울 것이 있을 때만 — 빈 칸을 새로 만들면 그것만으로
         "서버와 다르다" 가 되어 올릴 것도 없는데 올립니다. */
      if (dead.isNotEmpty) tomb[k] = dead;
      continue;
    }
    if (k == 'schedule') {
      out[k] = _mergeSchedule(local, remote, b, c, stamps);
      continue;
    }
    if (k == 'settings') {
      out[k] = _mergeSettings(local, remote, b, c, stamps);
      continue;
    }
    if (_orFlags.contains(k)) {
      out[k] = local[k] == true || remote[k] == true;
      final s = _eq(local[k], remote[k]) ? c.stampSame(k) : _later(c.effL(k), c.effR(k));
      if (s != null) stamps[k] = s;
      continue;
    }
    final l = _slot(local, k), r = _slot(remote, k), bb = _slot(b, k);
    final who = c.who(k, l, r, bb);
    final v = switch (who) {
      _Who.same || _Who.local => l,
      _Who.remote => r,
      _Who.both => c.lww(k, l, r),
    };
    if (!identical(v, _absent)) out[k] = v;
    final s = c.stampFor(k, who);
    if (s != null) stamps[k] = s;
  }

  /* 묘비 — 양쪽 것에 이번에 알아낸 것을 더해서. 비어 있어도 어느 쪽에 칸이
     있었으면 둡니다. */
  if (local.containsKey(tombstonesKey) || remote.containsKey(tombstonesKey) || tomb.isNotEmpty) {
    out[tombstonesKey] = {
      for (final e in tomb.entries) e.key: <String, Object?>{...e.value},
    };
  }

  out[syncMetaKey] = {'changedAt': stamps, 'from': remoteAt};
  return out;
}

/// 양쪽 묘비의 합 — 같은 id 는 나중 시각. 칸 이름은 그대로 둡니다(모르는
/// 칸도).
Map<String, Map<String, String>> _tombstones(Map<String, Object?> local, Map<String, Object?> remote) {
  final out = <String, Map<String, String>>{};
  void add(Object? t) {
    if (t is! Map) return;
    for (final e in t.entries) {
      final m = e.value;
      if (m is! Map) continue;
      final bucket = out.putIfAbsent('${e.key}', () => {});
      for (final x in m.entries) {
        final at = x.value is String ? x.value as String : '';
        final id = '${x.key}';
        final cur = bucket[id];
        bucket[id] = cur == null ? at : _later(cur, at);
      }
    }
  }
  add(local[tombstonesKey]);
  add(remote[tombstonesKey]);
  return out;
}

/// 목록을 id → 항목으로. 순서는 그대로. id 가 없는 항목은 내용 자체가 id 입니다.
Map<String, Object?> _byId(Object? v, String idKey) {
  final out = <String, Object?>{};
  if (v is! List) return out;
  for (final x in v) {
    final raw = x is Map ? x[idKey] : null;
    final id = raw != null && '$raw'.isNotEmpty ? '$raw' : '#${canonicalJson(x)}';
    out.putIfAbsent(id, () => x);
  }
  return out;
}

List<Object?> _mergeList(String key, String idKey, Map<String, Object?> local,
    Map<String, Object?> remote, Map<String, Object?> base, _Ctx c, Map<String, String> dead) {
  final ls = _byId(local[key], idKey), rs = _byId(remote[key], idKey);
  final bs = c.hasBase ? _byId(base[key], idKey) : null;

  /* 기준본에 있었는데 지금 없는 것 — 그쪽이 지운 것입니다. 묘비를 세워서
     상대 기기에도 전해집니다. 서버 쪽은 내 기준본을 본 레코드일 때만 —
     못 본 레코드에 없는 것은 아직 못 받은 것입니다. */
  if (bs != null) {
    for (final id in bs.keys) {
      if (dead.containsKey(id)) continue;
      if (!ls.containsKey(id)) {
        dead[id] = c.localAt.isEmpty ? c.remoteAt : c.localAt;
      } else if (c.trustRemote && !rs.containsKey(id)) {
        dead[id] = c.remoteAt;
      }
    }
  }

  /* 서버 순서 먼저, 이 기기에만 있는 것은 뒤에 — 그래야 한 바퀴 돌면 양쪽
     순서까지 같아져서 더 올릴 것이 없습니다. */
  final order = [...rs.keys, for (final id in ls.keys) if (!rs.containsKey(id)) id];
  final out = <Object?>[];
  for (final id in order) {
    if (dead.containsKey(id)) continue;
    final l = ls[id], r = rs[id];
    if (!ls.containsKey(id)) {
      out.add(r);
      continue;
    }
    if (!rs.containsKey(id)) {
      out.add(l);
      continue;
    }
    if (_eq(l, r)) {
      out.add(r);
      continue;
    }
    if (bs != null && c.trustRemote) {
      final bb = bs[id];
      final lc = !bs.containsKey(id) || !_eq(l, bb);
      final rc = !bs.containsKey(id) || !_eq(r, bb);
      if (!lc && rc) {
        out.add(r);
        continue;
      }
      if (lc && !rc) {
        out.add(l);
        continue;
      }
    }
    out.add(_newerRecord(l, r, c));
  }
  return out;
}

/// 같은 항목을 둘 다 고쳤을 때 — 항목의 updatedAt 이 둘 다 있으면 그걸로,
/// 없으면 레코드 전체의 시각으로. 같으면 서버.
Object? _newerRecord(Object? l, Object? r, _Ctx c) {
  final ul = l is Map ? l['updatedAt'] : null;
  final ur = r is Map ? r['updatedAt'] : null;
  if (ul is String && ur is String && ul != ur) return ul.compareTo(ur) > 0 ? l : r;
  return c.localAt.compareTo(c.remoteAt) > 0 ? l : r;
}

/* --- 운동 일정 ----------------------------------------------------------------- */

Map<String, Object?> _mergeSchedule(Map<String, Object?> local, Map<String, Object?> remote,
    Map<String, Object?> base, _Ctx c, Map<String, String> stamps) {
  final ls = _mapOf(local['schedule']), rs = _mapOf(remote['schedule']), bs = _mapOf(base['schedule']);
  final days = [...rs.keys, for (final d in ls.keys) if (!rs.containsKey(d)) d];
  final out = <String, Object?>{};
  for (final d in days) {
    final slot = 'schedule.$d';
    final l = _slot(ls, d), r = _slot(rs, d), bb = _slot(bs, d);
    final who = c.who(slot, l, r, bb);
    Object? v;
    switch (who) {
      case _Who.same:
      case _Who.local:
        v = l;
      case _Who.remote:
        v = r;
      case _Who.both:
        if (identical(l, _absent)) {
          /* 이 기기에 그 날이 없다. 지운 시각이 저쪽이 바꾼 시각보다 나중이면
             지운 것이 맞고, 아니면(또는 모르면) 저쪽 것을 받습니다. */
          final s = c.sl[slot];
          v = (s != null && s.compareTo(c.effR(slot)) > 0) ? _absent : r;
        } else if (identical(r, _absent)) {
          final s = c.sr[slot];
          v = (s != null && s.compareTo(c.effL(slot)) > 0) ? _absent : l;
        } else {
          v = _unionDay(_mapOf(l), _mapOf(r), c.effL(slot), c.effR(slot));
        }
    }
    /* 빈 날은 칸을 지웁니다 — store.dart 의 _writeDay 와 같은 규칙. */
    if (v is Map && _emptyDay(v.cast<String, Object?>())) v = _absent;
    if (!identical(v, _absent)) out[d] = v;
    final s = c.stampFor(slot, who);
    if (s != null) stamps[slot] = s;
  }
  return out;
}

bool _emptyDay(Map<String, Object?> e) {
  for (final v in e.values) {
    if (v == null) continue;
    if (v is List && v.isEmpty) continue;
    if (v is Map && v.isEmpty) continue;
    return false;
  }
  return true;
}

/// 둘 다 바꾼 날 — 계획은 합집합, 체크는 먼저 누른 시각, 기록은 더 많이 한 쪽.
Map<String, Object?> _unionDay(Map<String, Object?> l, Map<String, Object?> r, String el, String er) {
  final out = <String, Object?>{};
  final keys = [...l.keys, for (final k in r.keys) if (!l.containsKey(k)) k];
  for (final k in keys) {
    switch (k) {
      case 'plan':
        out[k] = _unionPlan(l[k], r[k]);
      case 'done':
        out[k] = _unionDone(l[k], r[k]);
      case 'log':
        out[k] = _unionLog(l[k], r[k], el, er);
      default:
        out[k] = !l.containsKey(k)
            ? r[k]
            : !r.containsKey(k)
                ? l[k]
                : (el.compareTo(er) > 0 ? l[k] : r[k]);
    }
  }
  return out;
}

List<Object?> _unionPlan(Object? a, Object? b) {
  final out = <Object?>[];
  void add(Object? x) {
    if (!out.contains(x)) out.add(x);
  }
  for (final t in _planOrder) {
    if ((a is List && a.contains(t)) || (b is List && b.contains(t))) add(t);
  }
  if (b is List) b.forEach(add);
  if (a is List) a.forEach(add);
  return out;
}

Map<String, Object?> _unionDone(Object? a, Object? b) {
  final la = _mapOf(a), lb = _mapOf(b);
  final out = <String, Object?>{};
  for (final k in [...lb.keys, for (final k in la.keys) if (!lb.containsKey(k)) k]) {
    if (!la.containsKey(k)) {
      out[k] = lb[k];
    } else if (!lb.containsKey(k)) {
      out[k] = la[k];
    } else {
      final x = la[k], y = lb[k];
      /* 먼저 누른 시각. 시각이 아닌 값(옛 웹의 true 같은 것)보다 시각을 칩니다. */
      if (x is String && y is String) {
        out[k] = x.compareTo(y) <= 0 ? x : y;
      } else {
        out[k] = x is String ? x : y;
      }
    }
  }
  return out;
}

double _minutes(Object? row) {
  final v = row is Map ? row['minutes'] : null;
  if (v is num) return v.toDouble();
  return double.tryParse('$v') ?? -1;
}

Map<String, Object?> _unionLog(Object? a, Object? b, String el, String er) {
  final la = _mapOf(a), lb = _mapOf(b);
  final out = <String, Object?>{};
  for (final k in [...lb.keys, for (final k in la.keys) if (!lb.containsKey(k)) k]) {
    if (!la.containsKey(k)) {
      out[k] = lb[k];
    } else if (!lb.containsKey(k)) {
      out[k] = la[k];
    } else {
      final x = la[k], y = lb[k];
      final mx = _minutes(x), my = _minutes(y);
      if (mx != my) {
        out[k] = mx > my ? x : y;
        continue;
      }
      /* 시간이 같으면 나중에 적은 것 — 기록에 적힌 시각으로, 없으면 레코드로. */
      final ax = x is Map ? x['at'] : null, ay = y is Map ? y['at'] : null;
      if (ax is String && ay is String && ax != ay) {
        out[k] = ax.compareTo(ay) > 0 ? x : y;
      } else {
        out[k] = el.compareTo(er) > 0 ? x : y;
      }
    }
  }
  return out;
}

/* --- 설정 ---------------------------------------------------------------------- */

Map<String, Object?> _mergeSettings(Map<String, Object?> local, Map<String, Object?> remote,
    Map<String, Object?> base, _Ctx c, Map<String, String> stamps) {
  final ls = _mapOf(local['settings']), rs = _mapOf(remote['settings']), bs = _mapOf(base['settings']);
  final keys = [...ls.keys, for (final k in rs.keys) if (!ls.containsKey(k)) k];
  final out = <String, Object?>{};
  for (final k in keys) {
    final slot = 'settings.$k';
    final l = _slot(ls, k), r = _slot(rs, k), bb = _slot(bs, k);
    final who = c.who(slot, l, r, bb);
    final v = switch (who) {
      _Who.same || _Who.local => l,
      _Who.remote => r,
      _Who.both => c.lww(slot, l, r),
    };
    if (!identical(v, _absent)) out[k] = v;
    final s = c.stampFor(slot, who);
    if (s != null) stamps[slot] = s;
  }
  return out;
}
