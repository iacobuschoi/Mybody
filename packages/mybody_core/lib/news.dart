/* =============================================================================
 * news.dart — 친구 소식 (news.js 를 그대로 옮긴 것)
 *
 * **기기 안에서만 계산합니다.** 서버는 한 줄도 안 씁니다. 이미 공유 설정으로
 * 걸러져 온 주간 스냅샷을, 내 기기가 지난번 본 값과 견줄 뿐입니다.
 *
 * 이 구조라서 **나쁜 소식이 흐를 수 없습니다.** 늘어난 것만 소식이 되므로
 * "안 했다" 는 구조적으로 알림이 될 수 없습니다. 줄어든 것도, 0 인 것도,
 * 주가 바뀌어 초기화된 것도 조용합니다.
 *
 * 원본과 **같은 답**을 내야 합니다 — tools/difftest.js 가 글자 단위로 봅니다.
 * ========================================================================== */
import 'dart:convert';

import 'js_num.dart';

const int kNewsMax = 40;

/// JS 의 `new Date().toISOString()` 과 **같은 글자**를 냅니다 —
/// UTC, 밀리초 세 자리, 끝에 Z. 소식 줄의 `at` 이 이 꼴로 비교되므로
/// 한 글자라도 다르면 오래된 것 걸러 내기가 달라집니다.
String _isoNow(DateTime d) {
  final u = d.toUtc();
  String p(int v, int w) => v.toString().padLeft(w, '0');
  return '${p(u.year, 4)}-${p(u.month, 2)}-${p(u.day, 2)}T'
      '${p(u.hour, 2)}:${p(u.minute, 2)}:${p(u.second, 2)}.'
      '${p(u.millisecond, 3)}Z';
}
const int _maxAgeDays = 21;

/// 소식 저장소. 앱이 어디에 담을지는 앱이 정합니다.
abstract class NewsStorage {
  String? read();
  void write(String raw);
  void clear();
}

Map<String, Object?> _blank() =>
    {'seen': <String, Object?>{}, 'items': <Object?>[], 'readSeq': 0, 'seq': 0};

class News {
  News(this.storage);
  final NewsStorage storage;

  Map<String, Object?> _load() {
    try {
      final raw = storage.read();
      if (raw == null || raw.isEmpty) return _blank();
      final o = jsonDecode(raw);
      if (o is! Map) return _blank();
      final m = o.cast<String, Object?>();
      return {
        'seen': (m['seen'] as Map?)?.cast<String, Object?>() ?? <String, Object?>{},
        'items': (m['items'] as List?) ?? <Object?>[],
        'readSeq': m['readSeq'] ?? 0,
        'seq': m['seq'] ?? 0,
      };
    } catch (_) {
      return _blank();
    }
  }

  void _save(Map<String, Object?> db) {
    try {
      storage.write(jsonEncode(db));
    } catch (_) {/* 저장 못 해도 화면은 돕니다 */}
  }

  /// 받아온 친구 스냅샷을 지난번 본 것과 견줍니다.
  ///
  /// [snaps]   `[{id, rows}]` — rows[0] 이 가장 최근 주
  /// [friends] `[{id, displayName}]`
  /// 돌려주는 값: 이번에 새로 생긴 소식 개수
  int apply(List<Object?>? snaps, List<Object?>? friends, [String? nowISO]) {
    final db = _load();
    final now = nowISO ?? _isoNow(DateTime.now());
    var added = 0;

    /* 지금 친구가 아닌 사람, 그리고 일정 공유를 끈 친구의 소식은 지웁니다.
       끈 사람 쪽에서는 사라진 줄 아는데, 여기 남아 있으면 안 됩니다. */
    final known = <String, bool>{};
    for (final f in friends ?? const []) {
      final id = (f as Map?)?['id'];
      if (id is String) known[id] = true;
    }

    /* "공유를 껐다" 와 "이번엔 못 받아왔다" 는 다릅니다.
       행이 아예 없는 것은 못 받아온 것입니다 — 기준선을 건드리면
       한 번 깜빡인 네트워크가 소식 기능을 꺼 버립니다.
       껐다고 단정하는 것은 **행은 왔는데 일정 숫자가 없을 때**뿐입니다. */
    final stopped = <String, bool>{};
    for (final s in snaps ?? const []) {
      final m = (s as Map?)?.cast<String, Object?>();
      final rows = (m?['rows'] as List?) ?? const [];
      if (rows.isNotEmpty && (rows[0] as Map?)?['keptDays'] == null) {
        final id = m?['id'];
        if (id is String) stopped[id] = true;
      }
    }

    var items = ((db['items'] as List?) ?? const []).where((it) {
      final fid = (it as Map?)?['friendId'];
      return known[fid] == true && stopped[fid] != true;
    }).toList();

    final seen = (db['seen'] as Map).cast<String, Object?>();
    for (final id in seen.keys.toList()) {
      if (known[id] != true || stopped[id] == true) seen.remove(id);
    }

    for (final s in snaps ?? const []) {
      final m = (s as Map?)?.cast<String, Object?>();
      final id = m?['id'];
      if (id is! String) continue;
      final rows = (m?['rows'] as List?) ?? const [];
      final row = rows.isEmpty ? null : (rows[0] as Map?)?.cast<String, Object?>();
      /* 행이 아예 없으면 이번엔 모르는 것뿐입니다 — 그냥 넘어갑니다. */
      if (row == null || row['keptDays'] == null) continue;

      final prev = (seen[id] as Map?)?.cast<String, Object?>();
      final cur = <String, Object?>{
        'weekStart': row['weekStart'],
        'keptDays': row['keptDays'],
        'plannedDays': row['plannedDays'],
      };

      /* 처음 보는 친구는 조용히 적어만 둡니다. 안 그러면 친구를 맺은
         첫 pull 에서 지난 일이 방금 일어난 것처럼 쏟아집니다. */
      final quiet = prev == null || prev['weekStart'] != cur['weekStart'];

      if (!quiet && jsToNumber(cur['keptDays']) > jsToNumber(prev['keptDays'])) {
        db['seq'] = jsToNumber(db['seq']).toInt() + 1;
        items.insert(0, <String, Object?>{
          'seq': db['seq'],
          'id': '$id|${cur['weekStart']}|${cur['keptDays']}',
          'friendId': id,
          /* 이름은 그릴 때 친구 목록에서 찾습니다. 여기 박아 두면
             친구가 이름을 바꾼 뒤에도 옛 이름이 계속 남습니다. */
          'at': now,
          'weekStart': cur['weekStart'],
          'keptDays': cur['keptDays'],
          'plannedDays': cur['plannedDays'],
        });
        added++;
      }

      /* 줄어들었으면 **그 소식을 거둬들입니다.** 새 소식을 만들지는
         않습니다. 근거가 사라진 줄을 들고 있는 쪽이 더 나쁩니다.
         지금 값보다 큰 숫자를 주장하던 줄만 지웁니다. */
      if (prev != null &&
          prev['weekStart'] == cur['weekStart'] &&
          jsToNumber(cur['keptDays']) < jsToNumber(prev['keptDays'])) {
        items = items.where((it) {
          final m2 = (it as Map).cast<String, Object?>();
          return !(m2['friendId'] == id &&
              m2['weekStart'] == cur['weekStart'] &&
              jsToNumber(m2['keptDays']) > jsToNumber(cur['keptDays']));
        }).toList();
      }
      seen[id] = cur;
    }

    if (added > 0) {
      final got = <String, bool>{};
      items = items.where((it) {
        final k = (it as Map)['id'];
        if (got['$k'] == true) return false;
        got['$k'] = true;
        return true;
      }).toList();
      if (items.length > kNewsMax) items = items.sublist(0, kNewsMax);
    }

    /* 오래된 소식은 버립니다. 개수 상한만 있으면 석 달 전 "운동했습니다"
       가 계속 첫 줄에 앉아 있습니다 — 소식이 아니라 화석입니다. */
    final cut = _isoNow(DateTime.fromMillisecondsSinceEpoch(
        DateTime.parse(now).millisecondsSinceEpoch - _maxAgeDays * 86400000,
        isUtc: true));
    items = items.where((it) {
      final at = (it as Map)['at'];
      return (at is String ? at : '').compareTo(cut) >= 0;
    }).toList();

    db['items'] = items;
    db['seen'] = seen;
    _save(db);
    return added;
  }

  List<Object?> list([int? limit]) {
    final items = (_load()['items'] as List?) ?? const [];
    final n = limit ?? kNewsMax;
    return items.length > n ? items.sublist(0, n) : items;
  }

  /// 아직 안 읽은 소식 개수
  int unread() {
    final db = _load();
    final items = (db['items'] as List?) ?? const [];
    final readSeq = jsToNumber(db['readSeq']);
    var n = 0;
    for (final it in items) {
      // items 는 최신순이라, 읽은 것을 만나면 그 뒤는 볼 필요가 없습니다.
      if (jsToNumber((it as Map)['seq']) > readSeq) {
        n++;
      } else {
        break;
      }
    }
    return n;
  }

  void markRead() {
    final db = _load();
    final items = (db['items'] as List?) ?? const [];
    db['readSeq'] = items.isNotEmpty
        ? ((items[0] as Map)['seq'] ?? 0)
        : (db['seq'] ?? 0);
    _save(db);
  }

  /// 계정을 바꾸거나 지울 때. 남의 소식이 새 계정 화면에 남으면 안 됩니다.
  void reset() {
    try {
      storage.clear();
    } catch (_) {}
  }
}
