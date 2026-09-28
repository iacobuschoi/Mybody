/* =============================================================================
 * cloud.dart — 기록을 내 계정에 보관하고, 어느 기기에서 넣든 다 따라오게
 *
 * 예전엔 "몸 숫자는 이 기기에만" 이었고 내보내기가 유일한 백업이었습니다.
 * 주인이 바꿨습니다: 기록 전체(측정·프로필·목표·계획·식단·일정·설정)를
 * 내 계정에 저장하고, 기기를 바꿔 로그인하면 자동으로 받아 옵니다.
 *
 * 0.2.8 까지는 **마지막에 바꾼 기기가 통째로 이겼습니다.** 상태 하나가
 * 레코드 하나(kind 'state', id 'main')이고, 이 기기가 마지막으로 바꾼 시각과
 * 서버 레코드의 시각을 견줘 새 쪽이 옛 쪽을 덮었습니다. 그래서 폰에서 넣은
 * 식단이 태블릿에서 저장 한 번 하면 사라졌고(태블릿이 더 새로우니), 받아
 * 보는 것도 켤 때와 로그인할 때뿐이라 옆에 켜 둔 기기는 영영 몰랐습니다.
 * 주인이 그걸 겪었습니다 — "다른 기기에서 넣은 게 안 보인다".
 *
 * 지금은 **받아서 · 합쳐서 · 올립니다** (merge.dart):
 *   · 저장할 때(3초 모아서), 앱으로 돌아올 때(2분에 한 번까지), 켤 때,
 *     로그인할 때 — 먼저 서버 것을 받아 이 기기 것과 합칩니다. 합친 것이
 *     이 기기와 다르면 들이고, 서버와 다르면 올립니다.
 *   · 합칠 때 "누가 바꿨나" 를 알려고 지난번에 맞춰 둔 상태(기준본)를 이
 *     기기에 따로 둡니다. 그게 없으면(처음, 로그인 직후) 합집합입니다.
 *   · 한 번에 하나만 합니다. 하는 중에 또 요청이 오면 끝나고 한 번 더.
 *   · 설정의 cloudSync 를 끄면 올리지도 받지도 않습니다. 설치할 때 묻습니다.
 *
 * 올리는 것은 큐(sync_queue.dart)를 지나갑니다 — 지하철에서 저장한 것이
 * 없던 일이 되지 않게. 다만 합치기 전에 큐를 먼저 비웁니다: 지난번에 못
 * 보낸 것이 서버에 닿은 뒤에 받아야 그게 서버의 최신입니다.
 *
 * 사진은 안 갑니다 — 파일이고 크고, 판독에 보낼 때 말고는 기기 밖으로
 * 안 나가는 것이 약속입니다. 새 기기에서는 사진 없이 숫자만 옵니다.
 *
 * **이 기기의 기록이 지금 로그인한 계정의 것일 때만** 맞춥니다(피드백 52). 예전엔 로그인하면
 * 무조건 "이 기기 기록 = 방금 들어온 계정의 기록" 으로 보고 합쳐 올려서, 계정 A 의 기록이 새로
 * 가입한 B 의 사본이 됐습니다. 이제 기록 칸에는 주인이 있고(local_owner.dart), 계정이 바뀌면
 * 로그인 · 로그아웃이 토큰을 알리기 전에 칸을 갈아 끼웁니다. 여기서는 한 번 더 봅니다 — 주인이
 * 지금 로그인과 다르거나 모르면 'owner' 로 멈추고 아무것도 올리지 않습니다. 기준본에도 계정 id 를
 * 적고, 읽을 때 서버와 id 가 둘 다 맞아야 씁니다. 칸이 바뀌면(slotChanged) 하던 맞춤은 버립니다
 * — 앞 칸의 결과를 새 칸에 들이거나 적으면 안 됩니다.
 * ========================================================================== */
import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'app_state.dart';
import 'local_owner.dart';
import 'merge.dart';
import 'sync_queue.dart';

const Duration _retryStart = Duration(seconds: 30);
const Duration _retryMax = Duration(minutes: 5);

/// 지난번에 서버와 맞춰 둔 상태 — 합칠 때의 기준본.
/// [updatedAt] 는 그때 서버에 있(게 되)었던 시각 — 받은 것이면 서버의
/// 시각, 올린 것이면 올린 시각.
class _Base {
  const _Base(this.updatedAt, this.payload);
  final String updatedAt;
  final Map<String, Object?> payload;
}

class CloudSync extends ChangeNotifier {
  CloudSync({
    required this.app,
    required this.api,
    required this.queue,
    this.debounce = const Duration(seconds: 3),
    this.resumeEvery = const Duration(minutes: 2),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final AppState app;
  final Api api;
  final SyncQueue? queue;

  /// 저장이 잇달아 나면 이만큼 모았다가 한 번에.
  final Duration debounce;

  /// 앱으로 돌아올 때 다시 받아 보는 간격. 그 안이면 건너뜁니다.
  final Duration resumeEvery;

  final DateTime Function() _now;

  static const kind = 'state';
  static const id = 'main';
  /* 셋 다 기록 칸의 일부입니다 — 계정이 바뀌면 local_owner.dart 가 그 계정 칸으로 옮깁니다. */
  static const keyAt = 'mybody.cloud.localChangedAt.v1';
  static const keyBase = 'mybody.cloud.base.v1';
  static const keyLast = 'mybody.cloud.last.v1';
  static const _keyAt = keyAt;
  static const _keyBase = keyBase;
  static const _keyLast = keyLast;

  /// 계정 칸을 local_owner.dart 가 맡는가. 그러면 로그아웃 때 이 기기 칸을 지우지 않습니다 —
  /// 그 계정 칸으로 이미 옮겨 갔고, 지금 칸은 다음 칸(로그인 없이 쓰던 기록)의 것입니다.
  bool slotsManaged = false;

  /* 칸이 바뀐 횟수. 맞추는 중에 바뀌면 그 맞춤은 앞 칸의 것이라 버립니다. */
  int _epoch = 0;

  String? _localChangedAt;
  _Base? _base;
  String? _baseWritten;
  DateTime? _lastSyncedAt;
  DateTime? _lastAttemptAt;
  String? _lastResult;
  String? _lastError;
  bool _loaded = false;
  Future<void>? _loading;
  bool _importing = false;
  bool _disposed = false;
  bool _again = false;
  Future<String>? _inFlight;
  Timer? _timer;
  Timer? _retry;
  Duration _retryIn = _retryStart;
  Map<String, Object?>? _seen;
  String? _token;
  AppLifecycleListener? _life;
  StreamSubscription<void>? _queueSub;

  /* --- 화면이 보는 것 ------------------------------------------------------- */

  /// 설정에서 동기화를 켜 두었는가. 칸이 없으면 켠 것입니다.
  bool get enabled => enabledIn(app.state);

  static bool enabledIn(Map<String, Object?> state) {
    final s = state['settings'];
    return s is! Map || s['cloudSync'] != false;
  }

  /// 마지막으로 서버와 맞춘 시각. 한 번도 안 됐으면 null.
  DateTime? get lastSyncedAt => _lastSyncedAt;

  /// 마지막 시도의 결과 — 'merged' · 'imported' · 'pushed' · 'same' ·
  /// 'offline' · 'rejected' · 'stale' · 'off' · 'owner' · 'none'. 'owner' 는 이 기기의 기록이
  /// 지금 계정의 것인지 몰라 멈춘 것입니다.
  String? get lastResult => _lastResult;

  /// 결과에 붙는 말(서버가 거절한 이유 같은 것). 없으면 null.
  String? get lastError => _lastError;

  /// 지금 하는 중인가.
  bool get busy => _inFlight != null;

  /* --- 연결 ---------------------------------------------------------------- */

  void wire() {
    _seen = app.state;
    _token = api.token;
    /* 로그인한 채 빈 칸이면 이 로그인의 칸입니다(시험 · 이관 뒤의 빈 기기). */
    if (api.signedIn) claimIfBlank(app, api);
    /* 저장소의 save() 만 듣습니다. AppState 는 사진 보관소가 열릴 때도 알리는데,
       그건 기록이 바뀐 게 아닙니다 — 켤 때마다 "이 기기가 방금 바꿨다" 로 찍히면
       기준본이 없는 첫 맞춤에서 빈 기본값이 계정의 값을 이겼습니다. Store 에는
       듣기를 푸는 길이 없어 _onChange 가 _disposed 를 봅니다. */
    app.store.onChange((_) => _onChange());
    api.addListener(_onAuth);
    /* 앱으로 돌아올 때 — update.dart 와 같은 방식. 바인딩이 없는 시험에서는
       돌아올 때 확인이 없을 뿐입니다 (onResume 을 직접 부릅니다). */
    try {
      _life ??= AppLifecycleListener(onResume: () => unawaited(onResume()));
    } catch (_) {}
    _queueSub ??= queue?.changes.listen((_) => _changed());
    unawaited(_load());
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _retry?.cancel();
    app.removeListener(_onChange);
    api.removeListener(_onAuth);
    _life?.dispose();
    _life = null;
    _queueSub?.cancel();
    super.dispose();
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  /* --- 기기에 적어 두는 것 --------------------------------------------------- */

  String get _server => api.baseUrl.trim().replaceAll(RegExp(r'/+$'), '');

  Future<void> _load() {
    if (_loaded) return Future.value();
    final e = _epoch;
    return _loading ??= _doLoad(e).whenComplete(() {
      if (e != _epoch) return;
      _loaded = true;
      _loading = null;
    });
  }

  /// 기준본은 누구 것이어야 하나 — 이 칸의 주인, 모르면 지금 로그인.
  String? _whose() => app.owner.current?.uid ?? api.userId;

  Future<void> _doLoad(int e) async {
    try {
      final sp = await SharedPreferences.getInstance();
      if (e != _epoch) return;
      /* 읽는 사이에 저장이 나서 이미 시각이 찍혔을 수 있습니다 — 그걸 지난
         값으로 덮으면 이 기기가 방금 바꾼 것이 옛것이 됩니다. 나중 것을 둡니다. */
      final stored = sp.getString(_keyAt);
      if (stored != null && (_localChangedAt == null || stored.compareTo(_localChangedAt!) > 0)) {
        _localChangedAt = stored;
      }
      final raw = sp.getString(_keyBase);
      if (raw != null) {
        final j = jsonDecode(raw);
        /* 기준본은 그 서버, 그 계정의 것입니다. 서버를 옮겼거나 다른 계정 것이면 버립니다 —
           다른 기록과 견줘 "지웠다" 고 읽으면 안 됩니다. 계정 id 가 없는 것은 0.2.19 가 적은
           것(그때 로그인한 계정의 것 — 이관이 주인을 모르면 지웁니다). */
        final bu = j is Map ? j['uid'] : null;
        final who = _whose();
        if (j is Map && j['server'] == _server && j['payload'] is Map &&
            (bu == null || (who != null && bu == who))) {
          _base = _Base('${j['updatedAt'] ?? ''}', (j['payload'] as Map).cast<String, Object?>());
          _baseWritten = raw;
        }
      }
      final last = sp.getString(_keyLast);
      if (last != null) {
        final j = jsonDecode(last);
        if (j is Map) {
          _lastSyncedAt = DateTime.tryParse('${j['at'] ?? ''}')?.toLocal();
          if (j['result'] is String) _lastResult = j['result'] as String;
        }
      }
    } catch (_) {
      /* 못 읽으면 처음처럼 — 기준본 없이 합집합으로 갑니다. */
    }
    _changed();
  }

  /* 기기 칸에 적는 것들은 저장소를 받아 온 사이 칸이 바뀌었으면 적지 않습니다 — 앞 칸의 시각 ·
     기준본이 새 칸에 적히면 새 칸의 합치기가 틀어집니다. */
  Future<void> _stamp(String at) async {
    final e = _epoch;
    _localChangedAt = at;
    try {
      final sp = await SharedPreferences.getInstance();
      if (e != _epoch) return;
      await sp.setString(_keyAt, at);
    } catch (_) {}
  }

  Future<void> _setBase(String updatedAt, Map<String, Object?> payload) async {
    final e = _epoch;
    _base = _Base(updatedAt, payload);
    final raw = jsonEncode(
        {'server': _server, 'uid': _whose(), 'updatedAt': updatedAt, 'payload': payload});
    if (raw == _baseWritten) return;
    _baseWritten = raw;
    try {
      final sp = await SharedPreferences.getInstance();
      if (e != _epoch) return;
      await sp.setString(_keyBase, raw);
    } catch (_) {/* 못 적으면 다음에 켤 때 합집합으로 한 번 더 — 잃는 것은 없습니다 */}
  }

  Future<void> _dropBase() async {
    await _load();
    final e = _epoch;
    if (_base == null && _baseWritten == null) return;
    _base = null;
    _baseWritten = null;
    try {
      final sp = await SharedPreferences.getInstance();
      if (e != _epoch) return;
      await sp.remove(_keyBase);
    } catch (_) {}
  }

  Future<String> _finish(String result, {String? error}) async {
    final e = _epoch;
    _lastResult = result;
    _lastError = error;
    if (const {'same', 'imported', 'pushed', 'merged'}.contains(result)) {
      _lastSyncedAt = _now();
      _retryIn = _retryStart;
      _retry?.cancel();
      _retry = null;
      try {
        final sp = await SharedPreferences.getInstance();
        if (e == _epoch) {
          await sp.setString(_keyLast,
              jsonEncode({'at': _lastSyncedAt!.toUtc().toIso8601String(), 'result': result}));
        }
      } catch (_) {}
    } else if (result == 'offline' || result == 'stale') {
      /* 서버에 못 닿았거나 올린 것이 아직 안 닿았습니다. 앱을 켜 둔 채로
         망이 돌아오면 다시 해 봅니다 — 30초 → 1분 → … → 5분. */
      _scheduleRetry();
    }
    _changed();
    return result;
  }

  void _scheduleRetry() {
    if (_retry != null || _disposed) return;
    _retry = Timer(_retryIn, () {
      _retry = null;
      final next = _retryIn * 2;
      _retryIn = next > _retryMax ? _retryMax : next;
      unawaited(_run());
    });
  }

  /* --- 계기 ---------------------------------------------------------------- */

  /* 저장이 바뀌었다 → 이 기기가 마지막으로 바꾼 시각을 찍고, 잠시 모았다가
     맞춥니다. 가져오는 중에 나는 저장은 바꾼 게 아닙니다. */
  void _onChange() {
    if (_importing || _disposed) return;
    /* 계정 칸을 갈아 끼운 것(Store.swap)은 이 기기가 바꾼 게 아닙니다 — 시각을 찍으면 새 칸의
       기록이 "방금 바꿨다" 가 되어 계정의 값을 이깁니다. 칸의 시각은 칸이 들고 옵니다. */
    if (app.store.swapping) {
      _seen = app.state;
      return;
    }
    final st = app.state;
    if (!identical(st, _seen)) {
      _seen = st;
      /* 상태가 통째로 바뀌었습니다 — 백업 가져오기 · 전부 지우기 · 씨앗.
         기준본과 견줘 "이 기기가 지웠다" 로 읽으면 옛 백업을 들인 것이
         계정의 기록을 지웁니다. 다음 맞춤은 합집합으로 갑니다. */
      unawaited(_dropBase());
    }
    unawaited(_stamp(_nowIso()));
    _timer?.cancel();
    _timer = Timer(debounce, () {
      _timer = null;
      unawaited(_run());
    });
  }

  /* 로그인 · 로그아웃. Api 는 토큰을 적을 때마다 알리므로 바뀐 때만 봅니다. */
  void _onAuth() {
    final t = api.token;
    if (t == _token) return;
    _token = t;
    if (api.signedIn) {
      /* 이 기기에서 로그인했다 — 받아서 합칩니다. 새 기기면 여기서 다 오고, 로그인 없이 쓰던
         기록은 로그인하는 문(account.dart)에서 합치기로 고른 때만 이 계정의 칸이 되어 여기서
         계정 것과 합쳐집니다. 어느 쪽도 다른 쪽을 통째로 덮지 않습니다. 칸의 주인이 이 계정이
         아니면 _sync 가 멈춥니다. */
      claimIfBlank(app, api);
      unawaited(_run());
    } else {
      unawaited(_forget());
    }
  }

  /* 로그아웃 — 기준본 · 마지막 시각 · 이 기기가 바꾼 시각은 그 계정의 것입니다. 칸을 맡는 쪽이
     있으면(앱) 이미 그 계정 칸으로 옮겨 갔으니 메모리만 비웁니다(slotChanged 가 했습니다). 없으면
     (시험) 여기서 버립니다 — 남긴 시각이 다음 계정의 값을 이기면 안 됩니다. */
  Future<void> _forget() async {
    _timer?.cancel();
    _timer = null;
    if (slotsManaged) {
      _changed();
      return;
    }
    await _dropBase();
    final e = _epoch;
    _lastSyncedAt = null;
    _lastResult = null;
    _lastError = null;
    _localChangedAt = null;
    try {
      final sp = await SharedPreferences.getInstance();
      if (e == _epoch) {
        await sp.remove(_keyLast);
        await sp.remove(_keyAt);
      }
    } catch (_) {}
    _changed();
  }

  /// 계정 칸이 바뀝니다(local_owner.dart) — 하던 맞춤은 앞 칸의 것이라 버리고, 메모리에 든 칸
  /// (기준본 · 시각 · 마지막 결과)을 비웁니다. [reload] 면 기기에서 새 칸의 것을 다시 읽습니다.
  /// 칸을 옮기기 **전에** reload 없이 한 번, 옮긴 **뒤에** 한 번 부릅니다.
  void slotChanged({bool reload = true}) {
    _epoch++;
    _timer?.cancel();
    _timer = null;
    _retry?.cancel();
    _retry = null;
    _retryIn = _retryStart;
    _again = false;
    _base = null;
    _baseWritten = null;
    _localChangedAt = null;
    _lastSyncedAt = null;
    _lastResult = null;
    _lastError = null;
    _lastAttemptAt = null;
    _loaded = false;
    _loading = null;
    _seen = app.state;
    if (reload && !_disposed) unawaited(_load());
    _changed();
  }

  /// 앱으로 돌아왔을 때. [resumeEvery] 안에 이미 해 봤으면 건너뜁니다.
  Future<void> onResume() async {
    if (_disposed) return;
    final last = _lastAttemptAt;
    if (last != null) {
      final age = _now().difference(last);
      /* 시계를 뒤로 돌린 기기(나이가 음수)는 오래된 것으로 봅니다. */
      if (!age.isNegative && age < resumeEvery) return;
    }
    await _run();
  }

  /// 「지금 동기화」 단추. 결과는 [lastResult] 와 같은 말입니다.
  Future<String> syncNow() => _run();

  /// 서버 것을 받아 합치고, 다를 때 올립니다. 켤 때(main.dart)와 시험이 부릅니다.
  Future<String> pull() => _run();

  /// 예전 이름 — 지금은 받아서 합친 뒤에 올립니다. 빈 기기는 올리지 않습니다.
  Future<void> push() => _run();

  /* --- 한 번 맞추기 ----------------------------------------------------------- */

  Future<String> _run() {
    final cur = _inFlight;
    if (cur != null) {
      /* 하는 중에 또 요청이 왔다 — 끝나고 한 번 더. 그냥 버리면 그 사이의
         변경이 다음 저장 때까지 안 올라갑니다. */
      _again = true;
      return cur;
    }
    if (_disposed) return Future.value('none');
    final f = _sync().catchError((Object e) => _finish('none', error: '$e'));
    return _inFlight = f.whenComplete(() {
      _inFlight = null;
      if (_again && !_disposed) {
        _again = false;
        unawaited(_run());
      }
    });
  }

  static bool isFresh(AppState app) => isBlankState(app.state);

  /* 밀리초까지만. 서버(db.js)는 updatedAt 을 자바스크립트의 toISOString() 으로
     다듬어 돌려주는데 그게 밀리초 세 자리입니다. 여기서 마이크로초까지 찍으면
     올린 시각과 받은 시각이 글자로 안 맞아, 내가 올린 것을 남이 올린 것으로
     읽습니다. */
  String _nowIso() => isoMs(_now());

  static String isoMs(DateTime d) =>
      DateTime.fromMillisecondsSinceEpoch(d.millisecondsSinceEpoch, isUtc: true).toIso8601String();

  static String _laterOf(String a, String b) => a.compareTo(b) >= 0 ? a : b;

  Map<String, Object?> _payload() {
    final m = (jsonDecode(app.store.exportJSON()) as Map).cast<String, Object?>();
    m.remove(syncMetaKey);   // 옛 백업에 실려 들어온 것이 있어도 저장소 것은 안 씁니다
    m.remove('guest');       // 「로그인 없이 쓰기」 는 이 기기의 일 — 계정에 실리면 다른 기기가 로그인 화면을 건너뜁니다
    return m;
  }

  /* 맞추는 사이 칸이 바뀌었거나(로그아웃 · 다른 계정) 로그인이 바뀌었으면 이 맞춤은 앞 칸의
     것입니다 — 결과를 들이지도, 기준본을 적지도 않고 그만둡니다. */
  bool _gone(int e, String? tok) => _disposed || e != _epoch || tok != api.token;

  Future<String> _sync() async {
    if (!api.signedIn) return _finish('none');
    final e = _epoch;
    final tok = api.token;
    await _load();
    if (_gone(e, tok)) return 'none';
    if (!enabled) {
      /* 끈 사람의 못 보낸 기록 사본이 망이 돌아왔다고 올라가면 안 됩니다. */
      queue?.dropOp('syncState');
      return _finish('off');
    }
    /* 이 기기의 기록이 이 계정의 것인가 — 아니면 아무것도 안 보냅니다(머리 주석). 계정 id 를
       아직 모르면(0.2.19 에서 올라온 첫 실행) 한 번 물어 알아 둡니다 — 로그아웃할 때 칸 이름입니다. */
    if (api.userId == null) {
      await api.me();
      if (_gone(e, tok)) return 'none';
    }
    if (!mayLeave(app, api)) {
      return _finish('owner', error: '이 기기의 기록이 이 계정 것인지 몰라 멈췄어요');
    }
    _lastAttemptAt = _now();
    _changed();

    /* 지난번에 못 보낸 것이 있으면 먼저 — 그게 닿은 뒤의 서버가 최신입니다. */
    final q = queue;
    if (q != null) {
      try {
        await q.flush();
      } catch (_) {}
    }
    if (_gone(e, tok)) return 'none';

    final r = await api.pullRecords(limit: 200);
    if (_gone(e, tok)) return 'none';
    if (!r.ok) return _finish('offline', error: r.reason);
    Map<String, Object?>? server;
    for (final rec in ((r.body['records'] as List?) ?? const [])) {
      if (rec is Map && rec['kind'] == kind && rec['id'] == id && rec['deleted'] != true) {
        server = rec.cast<String, Object?>();
      }
    }

    final localBody = _payload();
    final localAt = _localChangedAt ?? '';
    final base = _base;

    if (server == null) {
      /* 서버에 아무것도 없다. 빈 기기는 올릴 것이 없고 — 빈 것을 올리면
         나중에 다른 기기가 그걸 받습니다 — 기록이 있으면 이 기기 것이 곧
         계정의 기록입니다. */
      if (isFresh(app)) return _finish('none');
      final pushAt = _laterOf(_nowIso(), localAt);
      final payload = stampLocalChanges(localBody, base?.payload,
          at: localAt.isEmpty ? pushAt : localAt, from: '');
      return _pushOut(payload, pushAt, changedLocal: false);
    }

    final serverAt = '${server['updatedAt'] ?? ''}';
    final remote = (server['payload'] as Map?)?.cast<String, Object?>();
    if (remote == null) return _finish('none', error: '서버 레코드가 비어 있습니다');
    if (remote['version'] != localBody['version']) {
      /* 판이 다른 기록은 합칠 수 없고, 옛 판이 새 판을 덮어도 안 됩니다. */
      return _finish('none',
          error: '서버 기록의 판(${remote['version']})이 이 앱(${localBody['version']})과 '
              '다릅니다 — 앱을 업데이트해 주세요');
    }

    if (base != null && serverAt.compareTo(base.updatedAt) < 0) {
      /* 서버가 내가 마지막으로 올린 것보다 옛것 — 내 올리기가 아직 안 닿았거나
         거절됐습니다. 그 서버 것과 합치면 내가 올린 것이 되돌아갑니다. 합치지
         않고 이 기기 것을 다시 올립니다. 빈 기기는 올리지 않습니다 — 빈 것을
         올리면 그게 계정의 기록이 됩니다. */
      if (isFresh(app)) return _finish('none');
      final pushAt = _laterOf(_nowIso(), serverAt);
      final payload = stampLocalChanges(localBody, base.payload,
          at: localAt.isEmpty ? pushAt : localAt, from: syncFromOf(base.payload) ?? '');
      return _pushOut(payload, pushAt, changedLocal: false, result: 'stale');
    }

    /* 기준본이 없는 빈 기기는 "언제 바꿨는지" 를 내세우지 않습니다 — 켜면서 찍힌
       시각이 서버 기록보다 늦어 빈 칸이 계정의 값을 이기는 일이 있었습니다. */
    final effLocalAt = (base == null && isFresh(app)) ? '' : localAt;
    final local = stampLocalChanges(localBody, base?.payload,
        at: effLocalAt.isEmpty ? serverAt : effLocalAt,
        from: base == null ? '' : (syncFromOf(base.payload) ?? ''));
    final merged = mergeStates(local, remote,
        localAt: effLocalAt, remoteAt: serverAt, base: base?.payload, baseAt: base?.updatedAt);
    final body = withoutSyncMeta(merged);
    final changedLocal = !sameState(body, localBody);
    final changedRemote = !sameState(body, withoutSyncMeta(remote));

    if (_gone(e, tok)) return 'none';
    if (changedLocal && !_import(body)) {
      return _finish('none', error: '이 기기에 저장하지 못했습니다 — 자리가 없을 수 있습니다');
    }
    if (!changedRemote) {
      if (changedLocal) await _stamp(_laterOf(_nowIso(), serverAt));
      await _setBase(serverAt, merged);
      return _finish(changedLocal ? 'imported' : 'same');
    }
    final pushAt = _laterOf(_nowIso(), serverAt);
    await _stamp(pushAt);
    return _pushOut(merged, pushAt, changedLocal: changedLocal);
  }

  bool _import(Map<String, Object?> body) {
    _importing = true;
    try {
      app.store.importJSON(jsonEncode(body));
      return true;
    } catch (_) {
      return false;   // 판이 다르거나 자리가 없으면 그대로 둡니다
    } finally {
      _importing = false;
      _seen = app.state;
    }
  }

  /* 올리고, 올린 것을 기준본으로 삼습니다 — 닿았든 못 닿았든. 못 닿았으면
     큐가 나중에 보내고, 그 사이 서버가 이보다 옛것이면 위의 'stale' 길이
     합치지 않고 기다립니다. */
  Future<String> _pushOut(Map<String, Object?> payload, String pushAt,
      {required bool changedLocal, String? result}) async {
    final e = _epoch;
    final tok = api.token;
    final delivered = await _deliver(_owned(payload), pushAt);
    if (_gone(e, tok)) return 'none';
    if (!delivered) {
      final err = queue?.lastError;
      /* 서버가 거절한 것(4xx)은 기준본을 올리지 않습니다 — 올리면 다음 맞춤이
         "서버가 내 것보다 옛것" 으로 읽고 합치지 않은 채 같은 것을 또 보내 영영
         돕니다. 망 문제(offline)는 큐가 다시 보내니 기준본을 올려 둡니다. */
      if (err == null) await _setBase(pushAt, payload);
      return _finish(err == null ? 'offline' : 'rejected',
          error: err ?? '서버에 닿지 못했습니다 — 큐에 남겨 두고 다시 보냅니다');
    }
    await _setBase(pushAt, payload);
    return _finish(result ?? (changedLocal ? 'merged' : 'pushed'));
  }

  /* 올리는 사본에 **이 기록 칸의 주인** id 를 싣습니다(syncMeta.owner) — 토큰의 계정과 다르면 서버가
     409 로 거절합니다(server/db.js push). 토큰의 id 를 먼저 실으면 늘 토큰과 같아서 서버 잠금이
     아무것도 못 막습니다(2차 검토). 정상일 때는 [mayLeave] 를 지났으니 둘이 같습니다. 칸의 주인
     id 를 아직 모를 때만(이관) 토큰의 것. 합치기는 syncMeta 의 changedAt · from 만 봅니다. */
  @visibleForTesting
  Map<String, Object?> stampOwner(Map<String, Object?> payload) => _owned(payload);

  Map<String, Object?> _owned(Map<String, Object?> payload) {
    final uid = app.owner.current?.uid ?? api.userId;
    if (uid == null) return payload;
    final meta = payload[syncMetaKey];
    return {
      ...payload,
      syncMetaKey: {if (meta is Map) ...meta.cast<String, Object?>(), 'owner': uid},
    };
  }

  Future<bool> _deliver(Map<String, Object?> payload, String pushAt) async {
    final q = queue;
    final rec = {'kind': kind, 'id': id, 'updatedAt': pushAt, 'payload': payload};
    if (q == null) {
      final r = await api.pushRecords([rec]);
      return r.ok;
    }
    /* 큐는 같은 레코드를 하나로 겹칩니다 — 못 보낸 옛 사본이 있으면 이것이
       대신합니다. 다 나갔으면 이것도 나간 것입니다. */
    q.add('syncState', {'updatedAt': pushAt, 'payload': payload});
    try {
      await q.flush();
    } catch (_) {}
    /* 큐가 비었어도 서버가 이 레코드를 거절(4xx)해서 버린 것이면 나간 게 아닙니다. */
    final err = q.lastError ?? '';
    return q.pending == 0 && !err.contains('syncState(');
  }
}
