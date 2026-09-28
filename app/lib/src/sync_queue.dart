/* =============================================================================
 * sync_queue.dart — 서버에 못 보낸 일을 들고 있다가 나중에 보냅니다
 *
 * 폰은 늘 지하철에 있습니다. 친구를 수락하고, 공유를 끄고, 체크를 누르는
 * 일이 그 순간 서버에 닿지 않아도 **없던 일이 되면 안 됩니다.**
 *
 * 웹 앱 sync.js 의 큐를 옮긴 것입니다. 거기 주석에 적힌 두 고장을 그대로
 * 피하도록 옮겼습니다 — 둘 다 실제로 일어났던 것입니다:
 *
 *   (가) 일정을 네 칸 연달아 누르면 서버에는 첫 번째 것만 남았습니다.
 *        보내는 중인 맨 앞 작업을 다른 코드가 빼 버리는데, 응답이 온 뒤
 *        맨 앞을 지우니 엉뚱한 것이 지워졌습니다.
 *        → **자리가 아니라 그 작업 자체**로 지웁니다.
 *
 *   (나) 한도(429)에 걸린 상태에서 공유를 끄면, 앱은 껐다고 하고 서버는
 *        계속 보냈습니다. 4xx 를 전부 "다시 보내도 소용없다" 로 버린
 *        탓입니다.
 *        → **429·408 은 큐에 남깁니다.** 껐다고 믿는 사람은 다시 확인하지
 *          않습니다. 프라이버시 스위치가 조용히 안 먹는 것이 이 앱에서
 *          제일 나쁜 고장입니다.
 *
 * 그리고 셋째(피드백 52): **작업마다 누구의 일인지 적습니다.** 예전엔 "로그인돼 있나" 만 봐서,
 * 계정 A 가 오프라인에서 로그아웃하고 B 가 가입하는 순간 A 가 남긴 기록 사본 · 주간 요약 ·
 * 친구 작업이 B 의 토큰으로 나갔습니다. 이제는 지금 로그인의 일만 보내고, 로그아웃하면 그 계정의
 * 일은 계정 칸에 치워 두었다가(local_owner.dart) 그 계정으로 돌아오면 다시 싣습니다.
 * ========================================================================== */
import 'dart:async';
import 'dart:convert';

import 'api.dart';

const int _queueMax = 500;
const Duration _retryStart = Duration(seconds: 2);
const Duration _retryMax = Duration(minutes: 5);

/// 큐에 담기는 한 건.
class SyncJob {
  SyncJob(this.op, this.args, this.at, {this.owner, this.sess});
  final String op;
  final Map<String, Object?> args;
  final int at;

  /// 이 일을 맡긴 계정 id(모르면 null)와 그 로그인의 표시([Api.sessionTag]). 보낼 때 지금 로그인과
  /// 견줍니다 — 다른 계정의 토큰으로 나가지 않게(피드백 52). 둘 다 없으면 0.2.19 가 남긴 옛 작업이고,
  /// 첫 실행의 이관(local_owner.dart)이 주인에 붙이거나 버립니다. 그때까지는 안 보냅니다.
  String? owner;
  String? sess;

  /// 이 로그인([uid] · [sess])의 일인가.
  bool isFor({String? uid, String? sess}) =>
      (this.sess != null && this.sess == sess) || (owner != null && owner == uid);

  bool get legacy => owner == null && sess == null;

  Map<String, Object?> toJson() => {
        'op': op, 'args': args, 'at': at,
        if (owner != null) 'owner': owner,
        if (sess != null) 'sess': sess,
      };
  static SyncJob? fromJson(Object? o) {
    if (o is! Map) return null;
    final op = o['op'];
    if (op is! String) return null;
    return SyncJob(op, (o['args'] as Map?)?.cast<String, Object?>() ?? {},
        (o['at'] as num?)?.toInt() ?? 0,
        owner: o['owner'] is String ? o['owner'] as String : null,
        sess: o['sess'] is String ? o['sess'] as String : null);
  }
}

/// 큐를 어디에 적어 둘지는 앱이 정합니다.
abstract class QueueStorage {
  String? read();
  void write(String raw);
}

class SyncQueue {
  SyncQueue({required this.api, required this.storage}) {
    _load();
    _authSeen = api.token;
    /* 로그인하면 그 계정 몫을 밀어 봅니다 — 로그아웃할 때 치워 두었던 일이 계정 칸과 함께
       돌아왔을 수 있습니다(local_owner.dart). 다른 계정 몫은 [_mine] 이 거릅니다. */
    api.addListener(_onAuth);
  }

  final Api api;
  final QueueStorage storage;

  final List<SyncJob> _queue = [];
  Timer? _retry;
  Duration _retryIn = _retryStart;
  String? lastError;

  /// 지금 로그인의 일인가. 로그아웃했으면 아무것도 아닙니다.
  bool _mine(SyncJob j) => api.signedIn && j.isFor(uid: api.userId, sess: api.sessionTag);

  SyncJob? _firstMine() {
    for (final j in _queue) {
      if (_mine(j)) return j;
    }
    return null;
  }

  /// 지금 로그인이 아직 못 보낸 개수. 화면이 이걸 보여 줍니다.
  int get pending => _queue.where(_mine).length;

  /// 그 종류([op])의 일 중 아직 못 보낸 개수. 「모두에게 적용」 은 친구별
  /// 공유 변경(setShare)이 남아 있으면 적용하지 않습니다 — 나중에 도착한
  /// 옛 변경이 방금 적용한 값을 조용히 되돌립니다(share_defaults.dart).
  int pendingOf(String op) => _queue.where((j) => j.op == op && _mine(j)).length;

  String? _authSeen;
  void _onAuth() {
    final t = api.token;
    if (t == _authSeen) return;
    _authSeen = t;
    if (api.signedIn) unawaited(flush());
  }

  final _changed = StreamController<void>.broadcast();
  Stream<void> get changes => _changed.stream;
  void _emit() { if (!_changed.isClosed) _changed.add(null); }

  void _load() {
    try {
      final raw = storage.read();
      if (raw == null || raw.isEmpty) return;
      for (final o in (jsonDecode(raw) as List?) ?? const []) {
        final j = SyncJob.fromJson(o);
        if (j != null) _queue.add(j);
      }
    } catch (_) {/* 못 읽으면 빈 큐로 시작합니다 */}
  }

  void _save() {
    try {
      storage.write(jsonEncode(_queue.map((j) => j.toJson()).toList()));
    } catch (_) {}
  }

  /// 서버에 보낼 일을 맡깁니다.
  void add(String op, Map<String, Object?> args) {
    if (!api.signedIn) {
      /* 한 번도 로그인한 적이 없으면 보낼 것이 정말로 없습니다 — 이 앱은
         혼자서도 그대로 돌아갑니다. 조용히 돌아가는 게 맞습니다. */
      return;
    }
    if (!_ops.containsKey(op)) return;

    /* 같은 주 스냅샷은 겹쳐 쌓지 않습니다.
     *
     * 저장할 때마다 스냅샷이 큐에 들어갑니다. 검수 화면에서 숫자 몇 개를
     * 고치면 같은 주에 대한 똑같은 작업이 수십 개 쌓였습니다. 서버는 같은
     * weekStart 를 덮어쓰므로 마지막 하나만 의미가 있습니다.
     *
     * 오프라인에서 이게 왜 위험했냐면 — 큐가 넘치면 제일 오래된 것부터
     * 버렸습니다. 제일 오래된 것은 사용자가 실제로 한 일(친구 수락 ·
     * 공유 끄기)이고, 쌓인 쪽은 전부 같은 스냅샷의 복사본이었습니다.
     * 중요한 걸 버리고 쓸모없는 걸 지킨 셈입니다. */
    if (op == 'snapshot') {
      _queue.removeWhere(
          (j) => j.op == 'snapshot' && j.args['weekStart'] == args['weekStart'] && _mine(j));
    }
    /* 기록 전체도 마지막 것 하나만 — 서버는 같은 레코드를 덮어씁니다. */
    if (op == 'syncState') _queue.removeWhere((j) => j.op == 'syncState' && _mine(j));

    /* 누구의 일인지 적어 둡니다 — 보낼 때 그 로그인일 때만 나갑니다. */
    _queue.add(SyncJob(op, args, DateTime.now().millisecondsSinceEpoch,
        owner: api.userId, sess: api.sessionTag));

    /* 그래도 넘치면 버리는 순서를 정합니다. 스냅샷은 다음 저장 때 다시
       만들어지지만 친구 수락은 안 그렇습니다. */
    while (_queue.length > _queueMax) {
      var drop = -1;
      for (var k = 0; k < _queue.length - 1; k++) {
        if (_queue[k].op == 'snapshot' || _queue[k].op == 'syncState') { drop = k; break; }
      }
      _queue.removeAt(drop >= 0 ? drop : 0);
    }
    _save();
    _emit();
    unawaited(flush());
  }

  /// 못 보낸 일을 **전부 버립니다.** 「이 기기에서 전부 지우기」만 씁니다.
  ///
  /// 큐에는 기록 사본(syncState)이 통째로 들어 있을 수 있습니다. 남겨 두면
  /// 이 기기를 넘겨받은 사람이 로그인하는 순간 **지운 사람의 기록이 그
  /// 계정으로 올라갑니다.** 보내는 중인 일은 자리가 아니라 그 일 자체로
  /// 지우므로(위 (가)), 도중에 비워도 엉뚱한 것이 지워지지 않습니다.
  void clear() {
    _retry?.cancel();
    _retry = null;
    _retryIn = _retryStart;
    _queue.clear();
    _save();
    _emit();
  }

  /* --- 계정 칸(local_owner.dart) ------------------------------------------------ */

  /// 그 로그인([uid] · [sess])의 일 — 빼지 않고 보여만 줍니다. 로그아웃할 때 그 계정 칸에 **먼저 적고**
  /// 나서 [removeJobs] 로 뺍니다(적다가 멈춰도 잃지 않게). 계정 id 를 알면 적어서 줍니다: 다시
  /// 로그인하면 토큰(sess)이 바뀌어 id 로만 알아봅니다.
  List<SyncJob> jobsFor({String? uid, String? sess}) {
    final out = [for (final j in _queue) if (j.isFor(uid: uid, sess: sess)) j];
    for (final j in out) {
      j.owner ??= uid;
    }
    return out;
  }

  /// [jobsFor] 로 받아 칸에 적은 일을 큐에서 뺍니다.
  void removeJobs(List<SyncJob> jobs) {
    if (jobs.isEmpty) return;
    _queue.removeWhere(jobs.contains);
    _save();
    _emit();
  }

  /// 그 로그인의 일을 꺼내 줍니다(버리거나 곧바로 다시 실을 때).
  List<SyncJob> takeFor({String? uid, String? sess}) {
    final out = jobsFor(uid: uid, sess: sess);
    removeJobs(out);
    return out;
  }

  /// 같은 일은 하나만 — 칸에 적다 멈춘 뒤 다시 적으면 칸과 큐에 같은 일이 둘 있을 수 있습니다.
  static List<SyncJob> dedupe(Iterable<SyncJob> jobs) {
    final seen = <String>{};
    return [
      for (final j in jobs)
        if (seen.add('${j.op}|${j.at}|${jsonEncode(j.args)}')) j,
    ];
  }

  /// 칸에서 돌아온 일을 다시 싣습니다. 보내는 것은 그 계정으로 로그인한 뒤입니다. 이미 실린 것은
  /// 또 싣지 않습니다([dedupe]).
  void putBack(List<SyncJob> jobs) {
    if (jobs.isEmpty) return;
    final all = dedupe([..._queue, ...jobs])..sort((a, b) => a.at.compareTo(b.at));
    _queue
      ..clear()
      ..addAll(all);
    _save();
    _emit();
  }

  /// 계정 id 를 끝내 모른 채 끝난 로그인의 일(주인 id 없음) — 그 로그인의 기록(주인 모름)을 어느
  /// 계정에 [합치기] 하면 그 계정의 일로 붙입니다(local_owner.dart). 그 전에는 아무에게도 안 나갑니다.
  void adoptOrphans({String? uid, required String sess}) {
    var n = 0;
    for (final j in _queue) {
      if (j.owner == null && j.sess != null && j.sess != sess) {
        j
          ..owner = uid
          ..sess = sess;
        n++;
      }
    }
    if (n == 0) return;
    _save();
    _emit();
  }

  /// 그 종류의 일을 다 버립니다 — 동기화를 끄면 못 보낸 기록 사본(syncState)도 치웁니다.
  /// 끈 사람의 기록이 나중에 망이 돌아왔다고 올라가면 안 됩니다.
  void dropOp(String op) {
    final before = _queue.length;
    _queue.removeWhere((j) => j.op == op);
    if (_queue.length == before) return;
    _save();
    _emit();
  }

  /// 0.2.19 가 남긴 주인 없는 옛 작업 — 주인을 알면 붙이고([uid] · [sess]), 모르면 버립니다.
  /// 버리는 것은 기록 사본 · 주간 요약(다시 만들어짐)과 친구 작업(누구의 수락인지 모름)입니다.
  void adoptLegacy({String? uid, String? sess}) {
    if (!_queue.any((j) => j.legacy)) return;
    if (uid == null && sess == null) {
      _queue.removeWhere((j) => j.legacy);
    } else {
      for (final j in _queue.where((j) => j.legacy)) {
        j
          ..owner = uid
          ..sess = sess;
      }
    }
    _save();
    _emit();
  }

  /// 다시 보내면 될 수도 있는 거절. **큐에서 버리면 안 됩니다.**
  static bool _retryable(int status) => status == 429 || status == 408;

  /* 이미 보내는 중이면 **그 일이 끝나기를 같이 기다립니다.**
   *
   * 예전에는 그냥 돌아갔습니다. 그러면 `await flush()` 가 "다 보냈다" 가
   * 아니라 "누가 보내고 있더라" 를 뜻하게 됩니다 — 기다린 쪽은 끝난 줄
   * 알고 다음으로 넘어갑니다. */
  Future<void>? _inFlight;

  Future<void> flush() {
    if (_inFlight != null) return _inFlight!;
    if (!api.signedIn || _firstMine() == null) return Future.value();
    return _inFlight = _flush().whenComplete(() => _inFlight = null);
  }

  Future<void> _flush() async {
    final refused = <String>[];

    try {
      /* 지금 로그인의 일만 앞에서부터. 다른 계정의 일(이관 전 옛 작업 등)은 건너뜁니다 —
         보내는 사이 로그아웃하면 다음 차례가 없어 멈춥니다. */
      while (true) {
        final job = _firstMine();
        if (job == null) break;
        final r = await _ops[job.op]!(api, job.args);

        if (r.ok) {
          /* **자리가 아니라 그 작업 자체로** 뺍니다. 보내는 동안 다른
             코드가 큐를 흔들어도 내가 보낸 것만 빠집니다. */
          _queue.remove(job);
          _save();
          _retryIn = _retryStart;   // 한 번이라도 통했으면 간격을 되돌립니다
          continue;
        }
        if (_retryable(r.status)) break;          // 큐에 남겨 두고 나중에
        if (r.status >= 400 && r.status < 500) {
          // 서버가 거절했습니다. 다시 보내도 같은 답이 옵니다.
          _queue.remove(job);
          _save();
          refused.add('${job.op}(${r.reason})');
          continue;
        }
        break;   // 망 문제 — 큐를 남기고 멈춥니다
      }
      lastError = refused.isEmpty
          ? null
          : '서버가 거절한 작업 ${refused.length}건: ${refused.join(', ')}';
    } catch (e) {
      lastError = '$e';
    } finally {
      _emit();
      /* 큐가 안 비었으면 **스스로** 다시 시도합니다. 예전엔 다시 보낼
         계기가 "저장을 또 한다" 와 "온라인이 됐다" 뿐이었습니다. 공유를
         끄고 앱을 닫으면 그 둘이 안 일어나고, 끄기가 서버에 영영 안
         닿았습니다. */
      _scheduleRetry();
    }
  }

  /* 2초 → 4초 → … → 5분. 성공하면 되돌립니다. 화면은 pending 으로 못 올린
     개수를 이미 보여 주므로 여기서는 조용히 다시 시도만 합니다. */
  void _scheduleRetry() {
    if (_retry != null) return;
    if (!api.signedIn || _firstMine() == null) { _retryIn = _retryStart; return; }
    _retry = Timer(_retryIn, () {
      _retry = null;
      final next = _retryIn * 2;
      _retryIn = next > _retryMax ? _retryMax : next;
      unawaited(flush());
    });
  }

  void dispose() {
    _retry?.cancel();
    api.removeListener(_onAuth);
    _changed.close();
  }

  /* 큐에 담을 수 있는 일들. 웹 앱의 OPS 와 같은 이름을 씁니다. */
  static final Map<String, Future<ApiResult> Function(Api, Map<String, Object?>)>
      _ops = {
    'sendRequest': (a, x) => a.requestFriend('${x['inviteCode']}'),
    'accept': (a, x) => a.acceptFriend('${x['userId']}'),
    'decline': (a, x) => a.declineFriend('${x['userId']}'),
    'removeFriend': (a, x) => a.removeFriend('${x['userId']}'),
    'block': (a, x) => a.blockFriend('${x['userId']}'),
    'unblock': (a, x) => a.unblockFriend('${x['userId']}'),
    'setShare': (a, x) => a.setShare('${x['userId']}',
        (x['patch'] as Map?)?.cast<String, Object?>() ?? const {}),
    'snapshot': (a, x) => a.publishSnapshot('${x['weekStart']}',
        (x['payload'] as Map?)?.cast<String, Object?>() ?? const {}),
    'syncState': (a, x) => a.pushRecords([
          {
            'kind': 'state', 'id': 'main', 'updatedAt': '${x['updatedAt']}',
            'payload': (x['payload'] as Map?)?.cast<String, Object?>() ?? const {},
          },
        ]),
  };
}
