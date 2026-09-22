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
 * ========================================================================== */
import 'dart:async';
import 'dart:convert';

import 'api.dart';

const int _queueMax = 500;
const Duration _retryStart = Duration(seconds: 2);
const Duration _retryMax = Duration(minutes: 5);

/// 큐에 담기는 한 건.
class SyncJob {
  SyncJob(this.op, this.args, this.at);
  final String op;
  final Map<String, Object?> args;
  final int at;

  Map<String, Object?> toJson() => {'op': op, 'args': args, 'at': at};
  static SyncJob? fromJson(Object? o) {
    if (o is! Map) return null;
    final op = o['op'];
    if (op is! String) return null;
    return SyncJob(op, (o['args'] as Map?)?.cast<String, Object?>() ?? {},
        (o['at'] as num?)?.toInt() ?? 0);
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
  }

  final Api api;
  final QueueStorage storage;

  final List<SyncJob> _queue = [];
  Timer? _retry;
  Duration _retryIn = _retryStart;
  String? lastError;

  /// 아직 못 보낸 개수. 화면이 이걸 보여 줍니다.
  int get pending => _queue.length;

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
          (j) => j.op == 'snapshot' && j.args['weekStart'] == args['weekStart']);
    }
    /* 기록 전체도 마지막 것 하나만 — 서버는 같은 레코드를 덮어씁니다. */
    if (op == 'syncState') _queue.removeWhere((j) => j.op == 'syncState');

    _queue.add(SyncJob(op, args, DateTime.now().millisecondsSinceEpoch));

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
    if (!api.signedIn || _queue.isEmpty) return Future.value();
    return _inFlight = _flush().whenComplete(() => _inFlight = null);
  }

  Future<void> _flush() async {
    final refused = <String>[];

    try {
      while (_queue.isNotEmpty) {
        final job = _queue.first;
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
    if (!api.signedIn || _queue.isEmpty) { _retryIn = _retryStart; return; }
    _retry = Timer(_retryIn, () {
      _retry = null;
      final next = _retryIn * 2;
      _retryIn = next > _retryMax ? _retryMax : next;
      unawaited(flush());
    });
  }

  void dispose() {
    _retry?.cancel();
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
