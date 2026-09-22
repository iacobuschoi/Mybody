/* =============================================================================
 * cloud.dart — 기록을 내 계정에 보관하고, 새 기기에서 로그인하면 따라오게
 *
 * 예전엔 "몸 숫자는 이 기기에만" 이었고 내보내기가 유일한 백업이었습니다.
 * 주인이 바꿨습니다: 기록 전체(측정·프로필·목표·계획·식단·일정·설정)를
 * 내 계정에 저장하고, 기기를 바꿔 로그인하면 자동으로 받아 옵니다.
 *
 * 방식은 단순합니다 — 상태 통째로 한 레코드(kind 'state', id 'main').
 * 저장할 때마다(3초 모아서) 올리고, 켤 때와 로그인할 때 받아 봅니다.
 * 누가 이기는가: **마지막에 바꾼 쪽.** 이 기기가 마지막으로 바꾼 시각과
 * 서버 레코드의 시각을 견줍니다. 막 깐 기기(기록 없음)는 무조건 받습니다.
 *
 * 사진은 안 갑니다 — 파일이고 크고, 판독에 보낼 때 말고는 기기 밖으로
 * 안 나가는 것이 약속입니다. 새 기기에서는 사진 없이 숫자만 옵니다.
 * ========================================================================== */
import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'app_state.dart';
import 'sync_queue.dart';

class CloudSync {
  CloudSync({required this.app, required this.api, required this.queue,
             this.debounce = const Duration(seconds: 3)});
  final AppState app;
  final Api api;
  final SyncQueue? queue;
  final Duration debounce;

  static const kind = 'state';
  static const id = 'main';
  static const _key = 'mybody.cloud.localChangedAt.v1';

  String? _localChangedAt;
  bool _loaded = false;
  bool _importing = false;
  Timer? _timer;

  void wire() {
    app.addListener(_onChange);
    api.addListener(_onAuth);
  }

  void dispose() {
    _timer?.cancel();
    app.removeListener(_onChange);
    api.removeListener(_onAuth);
  }

  Future<void> _load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final sp = await SharedPreferences.getInstance();
      _localChangedAt = sp.getString(_key);
    } catch (_) {}
  }

  Future<void> _stamp(String at) async {
    _localChangedAt = at;
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_key, at);
    } catch (_) {}
  }

  static bool isFresh(AppState app) {
    final st = app.state;
    return st['onboarded'] != true &&
        ((st['scans'] as List?) ?? const []).isEmpty &&
        ((st['foodLogs'] as List?) ?? const []).isEmpty;
  }

  Map<String, Object?> _payload() =>
      (jsonDecode(app.store.exportJSON()) as Map).cast<String, Object?>();

  /* 저장이 바뀌었다 → 이 기기가 마지막으로 바꾼 시각을 찍고, 잠시 모았다가
     올립니다. 가져오는 중에 나는 저장은 바꾼 게 아닙니다. */
  void _onChange() {
    if (_importing) return;
    unawaited(_stamp(DateTime.now().toUtc().toIso8601String()));
    _timer?.cancel();
    _timer = Timer(debounce, () => unawaited(push()));
  }

  void _onAuth() {
    if (!api.signedIn) return;
    /* 이 기기에서 로그인했다 — 먼저 받아 보고(새 기기면 여기서 다 옵니다),
       그 다음 이 기기 것이 더 새로우면 올립니다. */
    unawaited(pull());
  }

  /// 지금 상태를 큐에 넣습니다. 큐가 같은 일을 하나로 겹칩니다.
  Future<void> push() async {
    if (!api.signedIn) return;
    await _load();
    final q = queue;
    if (q == null) return;
    if (isFresh(app)) return;   // 빈 기기가 서버의 기록을 빈 것으로 덮으면 안 됩니다
    final at = _localChangedAt ?? DateTime.now().toUtc().toIso8601String();
    if (_localChangedAt == null) await _stamp(at);
    q.add('syncState', {'updatedAt': at, 'payload': _payload()});
  }

  /// 서버의 기록을 받아 보고, 누가 이기는지 정합니다.
  /// 돌려주는 값은 무엇을 했는지 — 'imported' · 'pushed' · 'same' · 'offline' · 'none'.
  Future<String> pull() async {
    if (!api.signedIn) return 'none';
    await _load();
    final r = await api.pullRecords(limit: 200);
    if (!r.ok) return 'offline';
    Map<String, Object?>? server;
    for (final rec in ((r.body['records'] as List?) ?? const [])) {
      if (rec is Map && rec['kind'] == kind && rec['id'] == id && rec['deleted'] != true) {
        server = rec.cast<String, Object?>();
      }
    }
    if (server == null) {
      await push();
      return isFresh(app) ? 'none' : 'pushed';
    }
    final serverAt = '${server['updatedAt']}';
    final payload = (server['payload'] as Map?)?.cast<String, Object?>();
    if (payload == null) return 'none';

    final fresh = isFresh(app);
    final serverNewer = _localChangedAt != null && serverAt.compareTo(_localChangedAt!) > 0;
    if (fresh || serverNewer) {
      _importing = true;
      try {
        app.store.importJSON(jsonEncode(payload));
      } catch (_) {
        _importing = false;
        return 'none';   // 판이 다르거나 자리가 없으면 그대로 둡니다
      }
      _importing = false;
      await _stamp(serverAt);
      return 'imported';
    }
    if (_localChangedAt != null && serverAt == _localChangedAt) return 'same';
    await push();
    return 'pushed';
  }
}
