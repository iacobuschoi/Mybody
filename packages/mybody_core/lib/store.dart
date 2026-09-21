/* =============================================================================
 * store.dart — 앱의 상태 저장소 (prototype/js/store.js 의 이식)
 *
 * 무엇이 기기 밖으로 나가고 무엇이 안 나가는지는 원본 주석에 길게 있습니다.
 * 한 줄로: **몸 숫자와 기록은 기기에만 있고, 친구에게는 주간 요약만 나갑니다.**
 *
 * 옮기면서 정한 것 두 가지:
 *
 *  1. 상태를 클래스 필드가 아니라 **Map 그대로** 들고 있습니다.
 *     보기에는 타입이 없어서 나쁜 설계 같지만, 이 Map 이 그대로
 *     exportJSON() 의 내용이고 사용자의 백업 파일입니다. 웹에서 받은
 *     백업을 앱에서 열 수 있어야 하고, 그 반대도 돼야 합니다. 중간에
 *     클래스를 끼우면 모르는 칸이 조용히 사라집니다 — 백업에서 칸이
 *     사라지는 것은 데이터가 사라지는 것입니다.
 *
 *  2. 저장소·사진·소식·백엔드는 **꽂아 넣습니다**(hook). 원본이
 *     `global.MB_PHOTO` 가 있으면 쓰고 없으면 넘어가는 것과 같은 모양입니다.
 *     여기(코어)는 localStorage 도 파일 시스템도 모릅니다.
 * ========================================================================== */
library;

import 'dart:convert';

import 'data.dart';
import 'engine.dart' as engine;
import 'js_num.dart';

const String storeKey = 'mybody.state.v1';
const int storeVersion = 1;

/// 기기에 글자를 넣고 빼는 자리. 웹은 localStorage, 앱은 파일입니다.
abstract class StateStorage {
  String? read();
  /// 못 쓰면 false. **던지지 말고 false 를 주세요** — 자리가 없는 것은
  /// 예외 상황이 아니라 흔한 일이고, 저장소가 그걸 알려 줘야 합니다.
  bool write(String value);
}

/// 아무 데도 안 쓰는 저장소. 시험과 "저장이 안 되는 기기" 를 흉내 낼 때.
class MemoryStorage implements StateStorage {
  String? _v;
  final bool readOnly;
  MemoryStorage({this.readOnly = false});
  @override
  String? read() => _v;
  @override
  bool write(String value) {
    if (readOnly) return false;
    _v = value;
    return true;
  }
}

/// 사진 보관함(원본의 global.MB_PHOTO). 없으면 그냥 넘어갑니다.
abstract class PhotoHost {
  Map<String, Object?> list();
  void remove(String id);
  void clearAll();
}

/// 친구 소식(global.MB_NEWS) · 일정 요약(global.MB_SCHED) · 서버(global.MB_BACKEND).
typedef NewsReset = void Function();
typedef WeekSummary = Map<String, Object?> Function(String weekStart);
typedef CurrentUser = Object? Function();
typedef PublishSnapshot = Map<String, Object?> Function(String weekStart, Map<String, Object?> snap);

class Store {
  Store({StateStorage? storage, this.now}) : storage = storage ?? MemoryStorage();

  StateStorage storage;

  /// 시계. 시험에서 세워 두려고 뚫어 놓은 구멍입니다.
  DateTime Function()? now;
  DateTime _now() => (now ?? DateTime.now)();

  PhotoHost? photos;
  NewsReset? newsReset;
  WeekSummary? weekSummaryOf;
  CurrentUser? currentUser;
  PublishSnapshot? publishSnapshot;

  Map<String, Object?> _state = blank();
  final List<void Function(Map<String, Object?>)> _listeners = [];
  bool _lastSaveOk = true;
  bool _publishing = false;

  /* 읽지 못한 이유. 한 번 물어보면 지웁니다 — 화면이 같은 말을
     새로고침마다 되풀이하지 않게. */
  Map<String, Object?>? _loadProblem;

  static Map<String, Object?> blank() => {
        'version': storeVersion,
        'profile': null,
        'scans': <Object?>[],
        'goal': null,
        'goalHistory': <Object?>[],
        'comparison': null,
        'plan': null,
        'baselinePlan': null,
        'checkins': <Object?>[],
        'foodLogs': <Object?>[],
        'schedule': <String, Object?>{},
        'foodFavorites': <Object?>[],
        'settings': {
          'theme': 'auto', 'units': 'metric',
          'checkinEveryWeeks': 1, 'defaultLevel': 'mid',
        },
        'onboarded': false,
        'disclaimerAccepted': false,
      };

  /* --- 읽기 ---------------------------------------------------------------
   *
   * **못 읽었을 때가 이 함수의 전부입니다.**
   *
   * 손상·버전 불일치를 조용히 삼키고 빈 상태로 시작하면, 앱이 온보딩을
   * 띄우고 사용자가 한 걸음 넘어가는 순간 **첫 저장이 깨진 원본을
   * 덮어씁니다.** 손으로 복구할 재료까지 그때 사라집니다.
   * 측정 기록은 서버에 안 올라가는 유일본입니다.
   * ---------------------------------------------------------------------- */
  Map<String, Object?> load() {
    String? raw;
    try {
      raw = storage.read();
    } catch (_) {
      raw = null;
    }
    if (raw == null || raw.isEmpty) return _state;

    Map<String, Object?>? parsed;
    String? why;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        why = '내용이 비어 있거나 모양이 다릅니다';
      } else {
        parsed = decoded.cast<String, Object?>();
        if (parsed['version'] != storeVersion) {
          why = '저장된 판(${_s(parsed['version'])})이 이 앱($storeVersion)과 다릅니다';
        }
      }
    } catch (e) {
      why = '내용이 깨져 있습니다 ($e)';
    }

    if (why != null) {
      /* 원본을 옆으로 치워 둡니다. 자리가 없어서 그것마저 실패하면
         **그 사실도 기록합니다** — 못 지킨 것을 지켰다고 하지 않습니다. */
      final backupKey = '$storeKey.broken.${_now().millisecondsSinceEpoch}';
      var kept = false;
      try {
        kept = storage.write('$backupKey\u0000$raw');
      } catch (_) {
        kept = false;
      }
      _loadProblem = {'why': why, 'kept': kept, 'backupKey': kept ? backupKey : null};
      return _state;
    }
    _state = {...blank(), ...?parsed};
    return _state;
  }

  /// 읽기 실패 사유를 **한 번만** 돌려줍니다.
  Map<String, Object?>? takeLoadProblem() {
    final p = _loadProblem;
    _loadProblem = null;
    return p;
  }

  bool _writeState() {
    try {
      if (storage.write(jsonEncode(_state))) return true;
    } catch (_) {/* 아래에서 사진을 버려 봅니다 */}
    // 사진을 버려서 자리를 만들어 봅니다 (오래된 것부터)
    try {
      final p = photos;
      if (p != null) {
        final map = p.list();
        final ids = map.keys.toList()
          ..sort((a, b) {
            final ta = '${(map[a] as Map?)?['at'] ?? ''}';
            final tb = '${(map[b] as Map?)?['at'] ?? ''}';
            return ta.compareTo(tb);
          });
        while (ids.isNotEmpty) {
          p.remove(ids.removeAt(0));
          try {
            if (storage.write(jsonEncode(_state))) return true;
          } catch (_) {/* 계속 버립니다 */}
        }
      }
    } catch (_) {}
    return false;
  }

  bool save() {
    _lastSaveOk = _writeState();
    /* 기기에 못 썼으면 친구에게도 올리지 않습니다. 올려 버리면 이 기기에서는
       사라진 체크가 친구 화면에는 남습니다 — 어느 쪽이 사실인지 알 수 없게
       됩니다. 못 지킨 약속을 밖으로 내보내지 않습니다. */
    if (!_lastSaveOk) {
      _notify();
      return false;
    }
    /* 저장하면 올라갑니다 — **빠뜨릴 수가 없는 자리**에 둡니다.
       이 기능이 망가져 있던 이유가 정확히 "호출을 한 군데도 안 넣었다"
       였습니다. 같은 주는 덮어쓰므로 멱등입니다. */
    if (!_publishing) {
      _publishing = true;
      try {
        publishWeekly();
      } catch (_) {
      } finally {
        _publishing = false;
      }
    }
    _notify();
    return _lastSaveOk;
  }

  void _notify() {
    for (final f in _listeners) {
      try {
        f(_state);
      } catch (_) {}
    }
  }

  /// 마지막 저장이 실제로 기기에 쓰였는가.
  bool saved() => _lastSaveOk;

  Map<String, Object?> get() => _state;

  Map<String, Object?> set(Map<String, Object?> patch) {
    _state.addAll(patch);
    save();
    return _state;
  }

  void onChange(void Function(Map<String, Object?>) fn) => _listeners.add(fn);

  void reset() {
    /* "모든 데이터를 지울까요?" 에 사진이 안 들어 있었습니다. 결과지 사진에는
       보통 이름·나이·성별이 같이 인쇄돼 있습니다 — 전부 지웠다고 믿고 폰을
       넘긴 사람에게는 그게 전부입니다. */
    try {
      photos?.clearAll();
    } catch (_) {}
    /* 친구 소식도 같은 이유로 지웁니다 — 누가 언제 운동했는지가 이름째로
       적혀 있고, 그건 내 데이터가 아니라 친구 데이터입니다. */
    try {
      newsReset?.call();
    } catch (_) {}
    _state = blank();
    save();
  }

  /// 오너의 실제 인바디 데이터로 채웁니다 (검증용 한 방 버튼).
  Map<String, Object?> seed() {
    _state = blank();
    _state['profile'] = jsonDecode(jsonEncode(kSeedProfile));
    _state['scans'] = jsonDecode(jsonEncode(kSeedScans));
    _state['onboarded'] = true;
    _state['disclaimerAccepted'] = true;
    save();
    return _state;
  }

  /* --- 측정 -------------------------------------------------------------- */

  List<Map<String, Object?>> get _scans =>
      (_state['scans'] as List? ?? const []).map((x) => (x as Map).cast<String, Object?>()).toList();

  Map<String, Object?>? latestScan() {
    final s = sortedScans();
    return s.isEmpty ? null : s[s.length - 1];
  }

  /// 측정 시각 오름차순. 못 읽는 날짜는 NaN 이라 JS 의 정렬이 **자리를
  /// 그대로 둡니다** — 그 동작을 맞추려고 안정 정렬을 씁니다.
  List<Map<String, Object?>> sortedScans() {
    final list = _scans;
    final order = List<int>.generate(list.length, (i) => i);
    order.sort((a, b) {
      final ta = _msOf(list[a]['measuredAt']);
      final tb = _msOf(list[b]['measuredAt']);
      final c = ta - tb;
      if (c < 0) return -1;
      if (c > 0) return 1;
      return a - b;
    });
    return [for (final i in order) list[i]];
  }

  void addScan(Map<String, Object?> scan) {
    final list = _state['scans'] as List;
    final i = list.indexWhere((s) => (s as Map)['id'] == scan['id']);
    if (i >= 0) {
      list[i] = scan;
    } else {
      list.add(scan);
    }
    save();
  }

  /// 딸린 사진도 같이 지웁니다. 다른 측정이 같은 사진을 가리키면 남겨 둡니다.
  void removeScan(Object? id) {
    final list = _state['scans'] as List;
    Map<String, Object?>? gone;
    for (final s in list) {
      if ((s as Map)['id'] == id) {
        gone = s.cast<String, Object?>();
        break;
      }
    }
    _state['scans'] = list.where((s) => (s as Map)['id'] != id).toList();
    if (gone != null && jsTruthy(gone['photoId']) && photos != null) {
      final stillUsed =
          (_state['scans'] as List).any((s) => (s as Map)['photoId'] == gone!['photoId']);
      if (!stillUsed) {
        try {
          photos!.remove('${gone['photoId']}');
        } catch (_) {}
      }
    }
    save();
  }

  Map<String, Object?>? scanById(Object? id) {
    for (final s in _scans) {
      if (s['id'] == id) return s;
    }
    return null;
  }

  /* --- 목표 · 계획 -------------------------------------------------------- */

  /// 목표를 바꿉니다. **이전 목표는 이력에 남깁니다** — 사라지면
  /// 추이 화면의 목표선이 언제 왜 움직였는지 설명할 수 없습니다.
  Map<String, Object?> setGoal(Map<String, Object?> goal, [Object? reason]) {
    final cur = _mapOrNull(_state['goal']);
    if (cur != null) {
      final hist = (_state['goalHistory'] as List?) ?? <Object?>[];
      final plan = _mapOrNull(_state['plan']);
      hist.add({
        'goal': jsonDecode(jsonEncode(cur)),
        'setAt': cur['setAt'],
        'replacedAt': _now().toUtc().toIso8601String(),
        'reason': reason,
        'planLevel': plan != null ? plan['level'] : null,
        'planTargetDate': plan != null ? plan['targetDate'] : null,
      });
      if (hist.length > 30) hist.removeAt(0);
      _state['goalHistory'] = hist;
    }
    final next = (jsonDecode(jsonEncode(goal)) as Map).cast<String, Object?>();
    next['setAt'] = _now().toUtc().toIso8601String();
    _state['goal'] = next;
    save();
    return next;
  }

  static bool sameGoal(Map<String, Object?>? a, Map<String, Object?>? b) {
    if (a == null || b == null) return false;
    bool near(Object? x, Object? y) =>
        ((jsTruthy(x) ? jsToNumber(x) : 0) - (jsTruthy(y) ? jsToNumber(y) : 0)).abs() < 0.05;
    return near(a['weightKg'], b['weightKg']) &&
        near(a['smmKg'], b['smmKg']) &&
        near(a['bfmKg'], b['bfmKg']);
  }

  /// 목표가 그대로인 채 다시 만든 계획이면 "원래 계획" 은 건드리지 않습니다 —
  /// 갱신할 때마다 원본이 사라지면 "계획보다 빠른가" 를 영영 말할 수 없습니다.
  Map<String, Object?> setPlan(Map<String, Object?> plan) {
    final baseline = _mapOrNull(_state['baselinePlan']);
    final freshGoal =
        baseline == null || !sameGoal(_mapOrNull(baseline['goal']), _mapOrNull(plan['goal']));
    _state['plan'] = plan;
    if (freshGoal) {
      final copy = (jsonDecode(jsonEncode(plan)) as Map).cast<String, Object?>();
      copy['isBaseline'] = true;
      _state['baselinePlan'] = copy;
    }
    save();
    return plan;
  }

  /// 지금 계획이 지금 목표로 만들어진 것인가.
  bool planMatchesGoal() {
    final plan = _mapOrNull(_state['plan']);
    final goal = _mapOrNull(_state['goal']);
    if (plan == null || goal == null) return true;
    final g = _mapOrNull(plan['goal']);
    if (g == null) return false;
    bool near(Object? a, Object? b) =>
        ((jsTruthy(a) ? jsToNumber(a) : 0) - (jsTruthy(b) ? jsToNumber(b) : 0)).abs() < 0.05;
    return near(g['weightKg'], goal['weightKg']) &&
        near(g['smmKg'], goal['smmKg']) &&
        near(g['bfmKg'], goal['bfmKg']) &&
        (jsTruthy(g['modeId']) ? g['modeId'] : null) ==
            (jsTruthy(goal['modeId']) ? goal['modeId'] : null);
  }

  /* --- 식단 기록 ----------------------------------------------------------
   * 핵심 규칙: **기록하지 않은 날을 0으로 치환하지 않습니다.**
   * 0 으로 채우면 주 평균이 폭락하고, 엔진은 "이 사람 대사가 예상보다 낮다"
   * 고 판단해 칼로리를 더 깎습니다. 실제로는 목표치를 먹고 있었는데도요.
   * ---------------------------------------------------------------------- */

  /// 'YYYY-MM-DD' 는 이미 날짜 키입니다. **그대로 돌려줍니다.**
  ///
  /// `new Date('2026-09-14')` 는 UTC 자정으로 읽힙니다. 한국(UTC+9)에서는
  /// 같은 날 오전 9시라 티가 안 나는데, 미국 서부(UTC-7)에서는 전날 오후
  /// 5시가 됩니다 — 하루가 밀립니다. 쓸 때와 읽을 때가 똑같이 밀리므로
  /// 화면은 멀쩡해 보이는데, 스트릭이 오늘 것을 영영 못 찾습니다.
  /// (원본에서 TZ=America/Los_Angeles 로 돌리니 42개 중 7개가 깨졌습니다.)
  String dayKey([Object? d]) {
    if (d is String && _dateOnlyKey.hasMatch(d)) return d;
    final x = d == null ? _now() : (jsParseLocal(d) ?? _now());
    final l = x.toLocal();
    return '${l.year}-${l.month.toString().padLeft(2, '0')}-'
        '${l.day.toString().padLeft(2, '0')}';
  }

  List<Map<String, Object?>> get _logs => (_state['foodLogs'] as List? ?? const [])
      .map((x) => (x as Map).cast<String, Object?>())
      .toList();

  Map<String, Object?> addFoodLog(Map<String, Object?> entry) {
    final logs = (_state['foodLogs'] as List?) ?? <Object?>[];
    final row = <String, Object?>{
      'id': jsTruthy(entry['id'])
          ? entry['id']
          : 'f${_now().millisecondsSinceEpoch}_${logs.length}',
      'date': jsTruthy(entry['date']) ? entry['date'] : dayKey(),
      'meal': jsTruthy(entry['meal']) ? entry['meal'] : '간식',
      'items': entry['items'] ?? <Object?>[],
      'source': jsTruthy(entry['source']) ? entry['source'] : 'manual',
      'at': jsTruthy(entry['at']) ? entry['at'] : _now().toUtc().toIso8601String(),
    };
    logs.add(row);
    if (logs.length > 20000) logs.removeAt(0);
    _state['foodLogs'] = logs;
    save();
    return row;
  }

  void removeFoodLog(Object? id) {
    _state['foodLogs'] =
        (_state['foodLogs'] as List? ?? const []).where((x) => (x as Map)['id'] != id).toList();
    save();
  }

  List<Map<String, Object?>> logsForDate([Object? date]) {
    final k = dayKey(date);
    return _logs.where((x) => x['date'] == k).toList();
  }

  static Map<String, Object?> sumItems(Object? items) {
    var kcal = 0.0, p = 0.0, c = 0.0, f = 0.0;
    if (items is List) {
      for (final i0 in items) {
        final i = (i0 as Map).cast<String, Object?>();
        /* `i.kcal || 0` — 없거나 0 이면 0. 문자열이 들어오면 그대로 더해져
           합계가 NaN 이 됩니다(원본과 같습니다). */
        kcal += jsTruthy(i['kcal']) ? jsToNumber(i['kcal']) : 0;
        p += jsTruthy(i['p']) ? jsToNumber(i['p']) : 0;
        c += jsTruthy(i['c']) ? jsToNumber(i['c']) : 0;
        f += jsTruthy(i['f']) ? jsToNumber(i['f']) : 0;
      }
    }
    return {
      'kcal': jsRound(kcal),
      'p': jsRound(p * 10) / 10,
      'c': jsRound(c * 10) / 10,
      'f': jsRound(f * 10) / 10,
    };
  }

  Map<String, Object?> dayTotals([Object? date]) {
    final logs = logsForDate(date);
    final all = <Object?>[];
    for (final l in logs) {
      final items = l['items'];
      if (items is List) all.addAll(items);
    }
    final t = sumItems(all);
    t['logged'] = logs.isNotEmpty;
    t['entries'] = logs.length;
    return t;
  }

  /// 기록이 하나라도 있는 날짜 목록 (미기록일 판정의 기준).
  List<String> loggedDates() {
    final set = <String>{};
    for (final x in _logs) {
      set.add('${x['date']}');
    }
    final out = set.toList()..sort();
    return out;
  }

  /// 최근에 먹은 것 — 마찰을 줄이는 가장 효과적인 장치입니다.
  List<Map<String, Object?>> recentFoods([Object? limit]) {
    final cap = jsTruthy(limit) ? jsToNumber(limit).toInt() : 12;
    final seen = <String>{};
    final out = <Map<String, Object?>>[];
    final logs = _logs.reversed.toList();
    for (var i = 0; i < logs.length && out.length < cap; i++) {
      final items = logs[i]['items'];
      if (items is! List) continue;
      for (final it0 in items) {
        if (out.length >= cap) break;
        final it = (it0 as Map).cast<String, Object?>();
        if (!seen.add('${it['name']}')) continue;
        out.add(it);
      }
    }
    return out;
  }

  /// 특정 끼니를 통째로 복사합니다. 중요한 건 절대 정확도가 아니라
  /// **편향이 흔들리지 않는 것**입니다 — 이유는 원본 주석에.
  Map<String, Object?>? lastMealLike(Object? meal, [Object? beforeDate]) {
    final before = jsTruthy(beforeDate) ? '$beforeDate' : dayKey();
    final rows = _logs.where((x) {
      final items = x['items'];
      return x['meal'] == meal &&
          '${x['date']}'.compareTo(before) < 0 &&
          items is List &&
          items.isNotEmpty;
    }).toList();
    /* 같은 날짜가 여러 개면 **나중에 적은 것**을 씁니다. 원본은 여기서
       정렬을 썼는데, 그 비교 함수가 날짜가 같을 때도 −1 을 돌려줘서
       결과가 엔진에 달려 있었습니다 (원본 주석 참고). 둘 다 이제 그냥
       적어 둡니다 — 정렬에 맡길 만큼 미묘한 일이 아니었습니다. */
    Map<String, Object?>? best;
    for (final r in rows) {
      if (best == null || '${r['date']}'.compareTo('${best['date']}') >= 0) best = r;
    }
    return best;
  }

  Map<String, Object?>? copyMeal(Map<String, Object?>? sourceLog, [Object? toDate, Object? meal]) {
    if (sourceLog == null) return null;
    return addFoodLog({
      'date': jsTruthy(toDate) ? toDate : dayKey(),
      'meal': jsTruthy(meal) ? meal : sourceLog['meal'],
      'items': jsonDecode(jsonEncode(sourceLog['items'] ?? <Object?>[])),
      'source': 'repeat',
    });
  }

  List<Map<String, Object?>> yesterdayLogs([Object? fromDate]) {
    final from = jsTruthy(fromDate) ? '$fromDate' : dayKey();
    final d = DateTime.tryParse('${from}T00:00:00');
    if (d == null) return logsForDate(dayKey(from));
    final prev = DateTime(d.year, d.month, d.day - 1);
    return logsForDate(dayKey(prev));
  }

  bool toggleFavorite(Object? name) {
    final favs = (_state['foodFavorites'] as List?) ?? <Object?>[];
    final i = favs.indexOf(name);
    if (i >= 0) {
      favs.removeAt(i);
    } else {
      favs.add(name);
    }
    _state['foodFavorites'] = favs;
    save();
    return favs.contains(name);
  }

  bool isFavorite(Object? name) =>
      (_state['foodFavorites'] as List? ?? const []).contains(name);

  /* --- 주간 운동 일정 ------------------------------------------------------
   * "월요일에 헬스" 같은 약속을 요일이 아니라 **날짜**로 저장합니다.
   * 요일 인덱스로 저장하면 주가 넘어가는 순간 지난주 체크가 이번주 칸에
   * 그대로 남습니다 — 스트릭이 영원히 안 끊기고 화면이 거짓말을 합니다.
   * ---------------------------------------------------------------------- */

  static const List<String> schedTypes = ['gym', 'cardio'];

  Map<String, Object?> scheduleDay([Object? date]) {
    final sch = (_state['schedule'] as Map?) ?? <String, Object?>{};
    final e = _mapOrNull(sch[dayKey(date)]);
    return {
      'plan': [...(e?['plan'] as List? ?? const [])],
      'done': {...?_mapOrNull(e?['done'])},
    };
  }

  void _writeDay(String k, Map<String, Object?> e) {
    final sch = ((_state['schedule'] as Map?) ?? <String, Object?>{}).cast<String, Object?>();
    final plan = (e['plan'] as List? ?? const []);
    final done = _mapOrNull(e['done']) ?? const <String, Object?>{};
    /* 둘 다 비면 그 날 칸을 지웁니다 — 안 그러면 넘긴 날마다 빈 칸이 쌓여서
       백업 파일이 계속 커집니다. */
    if (plan.isEmpty && done.isEmpty) {
      sch.remove(k);
    } else {
      sch[k] = {'plan': plan, 'done': done};
    }
    _state['schedule'] = sch;
    save();
  }

  /// 그 날 그 운동을 하기로 한다 / 안 하기로 한다.
  Map<String, Object?>? setSchedulePlan(Object? date, Object? type, bool on) {
    if (!schedTypes.contains(type)) return null;
    final k = dayKey(date);
    final e = scheduleDay(k);
    final plan = e['plan'] as List;
    final done = e['done'] as Map;
    final i = plan.indexOf(type);
    if (on && i < 0) plan.add(type);
    if (!on && i >= 0) {
      plan.removeAt(i);
      /* 계획을 지우면 그 날의 체크도 같이 지웁니다. "안 하기로 한 운동을
         했다" 는 상태는 화면에 그릴 자리가 없고, 다시 계획을 켰을 때 예전
         체크가 살아나면 안 갔는데 간 것이 됩니다. */
      done.remove(type);
    }
    _writeDay(k, e);
    return scheduleDay(k);
  }

  /// 그 날 그 운동을 했다고 체크한다 / 체크를 푼다.
  ///
  /// **아직 오지 않은 날은 체크할 수 없습니다** — 내일 갈 헬스를 오늘
  /// 체크하는 건 기록이 아니라 소원입니다. 지나간 날은 나중에라도 체크할
  /// 수 있게 둡니다 — 갔는데 누르는 걸 잊은 쪽이 훨씬 흔합니다.
  Map<String, Object?>? setScheduleDone(Object? date, Object? type, bool on) {
    if (!schedTypes.contains(type)) return null;
    final k = dayKey(date);
    if (k.compareTo(dayKey()) > 0) return scheduleDay(k);
    final e = scheduleDay(k);
    final plan = e['plan'] as List;
    final done = e['done'] as Map;
    if (on) {
      if (!plan.contains(type)) plan.add(type);   // 계획에 없이 한 것도 기록은 남깁니다
      done[type] = _now().toUtc().toIso8601String();
    } else {
      done.remove(type);
    }
    _writeDay(k, e);
    return scheduleDay(k);
  }

  /* --- 주간 스냅샷 — 친구에게 나가는 값 ------------------------------------ */

  /// 그 날짜가 속한 주의 **월요일**.
  ///
  /// 'YYYY-MM-DD' 를 그대로 Date 에 넣으면 UTC 자정으로 읽혀서, 시차가
  /// 음수인 곳에서는 전날이 되고 그 전날이 일요일이면 한 주가 통째로
  /// 밀립니다. dayKey 와 같은 가드를 둡니다.
  String weekStartOf([Object? date]) {
    DateTime d;
    if (date is String && _dateOnlyKey.hasMatch(date)) {
      final p = date.split('-');
      d = DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
    } else {
      d = date == null ? _now() : (jsParseLocal(date) ?? _now());
    }
    final l = d.toLocal();
    final midnight = DateTime(l.year, l.month, l.day);
    final dow = (midnight.weekday - 1) % 7;          // 월=0
    final mon = DateTime(midnight.year, midnight.month, midnight.day - dow);
    return '${mon.year}-${mon.month.toString().padLeft(2, '0')}-'
        '${mon.day.toString().padLeft(2, '0')}';
  }

  /// 이번 주에 친구에게 나갈 수 있는 값 **전부**를 담은 꾸러미.
  /// 무엇이 실제로 나가는지는 읽는 쪽에서 친구별 공유 설정으로 거릅니다 —
  /// 한 사람이 친구마다 다른 항목을 공유하기 때문입니다.
  Map<String, Object?> weeklySnapshot() {
    final prof = _mapOrNull(_state['profile']) ?? kSeedProfile;
    final scans = sortedScans();
    final out = <String, Object?>{
      'dWeightKg': null, 'dSmmKg': null, 'dBfmKg': null,
      'progressPct': null, 'checkedIn': false,
    };

    /* 이번 주 운동 일정 — 숫자 네 개. 엔진도 프로필도 없어도 셀 수 있는
       값이라 아래의 early return 보다 먼저 넣습니다. 인바디를 한 번도 안
       올린 사람도 운동 일정은 쓰고, 그 친구는 그걸 볼 수 있어야 합니다. */
    final ws = weekSummaryOf;
    if (ws != null) {
      final sum = ws(weekStartOf());
      if (jsNum(sum, 'plannedDays') > 0) {
        out['plannedDays'] = sum['plannedDays'];
        out['keptDays'] = sum['keptDays'];
        out['missedDays'] = sum['missedDays'];
        out['openDays'] = sum['openDays'];
      }
      /* 계획이 0일이면 키를 아예 안 넣습니다. 0 을 보내면 친구 화면에
         "계획 0일 · 지킴 0일" 이 뜨고, 그건 "안 했다" 로 읽힙니다.
         실제로는 앱에 안 적었다는 뜻일 뿐입니다 — 다른 말입니다. */
    }

    /* "이번 주에 기록했는가" 도 몸이 아니라 행동입니다. 주간 체크인만 보면,
       홈에서 매일 칸을 체크하는 사람이 친구 화면에서는 영원히 "이번 주
       아직" 으로 남습니다. 계획만 세운 주는 안 칩니다 — 하기로 한 것은
       기록이 아닙니다. */
    final wk = weekStartOf();
    final checkins = (_state['checkins'] as List? ?? const []);
    out['checkedIn'] = checkins.any((c) => weekStartOf((c as Map)['at']) == wk) ||
        jsNum(out, 'keptDays') > 0;

    if (scans.isEmpty && _state['profile'] == null) return out;

    // 변화량은 직전 측정 대비. 측정이 한 번뿐이면 변화량은 "없음" 이지 0 이 아닙니다.
    if (scans.length >= 2) {
      final a = engine.derive(scans[scans.length - 2], prof);
      final b = engine.derive(scans[scans.length - 1], prof);
      out['dWeightKg'] = jsRound((jsNum(b, 'weightKg') - jsNum(a, 'weightKg')) * 10) / 10;
      out['dSmmKg'] = jsRound((jsNum(b, 'smmKg') - jsNum(a, 'smmKg')) * 100) / 100;
      out['dBfmKg'] = jsRound((jsNum(b, 'bfmKg') - jsNum(a, 'bfmKg')) * 100) / 100;
    }
    if (scans.isNotEmpty) {
      final last = engine.derive(scans[scans.length - 1], prof);
      out['weightKg'] = last['weightKg'];
      out['smmKg'] = last['smmKg'];
      out['bfmKg'] = last['bfmKg'];
      out['pbfPct'] = last['pbfPct'];
    }
    final plan = _mapOrNull(_state['plan']);
    final goal = _mapOrNull(_state['goal']);
    if (plan != null && goal != null && scans.isNotEmpty && jsTruthy(plan['trajectory'])) {
      final cur = engine.derive(scans[scans.length - 1], prof);
      final traj = plan['trajectory'] as List;
      final s0 = jsNum((traj[0] as Map).cast<String, Object?>(), 'bfmKg');
      final t0 = jsNum(goal, 'bfmKg');
      if ((s0 - t0).abs() > 0.01) {
        final pct = jsRound((s0 - jsNum(cur, 'bfmKg')) / (s0 - t0) * 100);
        out['progressPct'] = pct.isNaN ? pct : (pct < 0 ? 0 : (pct > 100 ? 100 : pct));
      }
    }
    return out;
  }

  /// 스냅샷에 친구에게 보여 줄 것이 하나라도 들어 있는가.
  static bool hasAnything(Map<String, Object?>? snap) {
    if (snap == null) return false;
    if (jsTruthy(snap['checkedIn'])) return true;
    if (snap.containsKey('plannedDays') && snap['plannedDays'] != null) return true;
    const keys = ['dWeightKg', 'dSmmKg', 'dBfmKg', 'progressPct',
                  'weightKg', 'smmKg', 'bfmKg', 'pbfPct'];
    for (final k in keys) {
      if (snap[k] != null) return true;
    }
    return false;
  }

  /// 이번 주 스냅샷을 서버에 올립니다. 로그인 안 했으면 조용히 아무것도 안 합니다.
  Map<String, Object?> publishWeekly() {
    final who = currentUser;
    if (who == null || who() == null) return {'ok': false, 'reason': '로그인 안 함'};
    /* **빈 스냅샷은 안 올립니다.** 서버는 같은 주를 덮어쓰므로, 앱을 지웠다
       다시 깔고 로그인하면 온보딩의 첫 저장이 서버에 멀쩡히 남아 있던
       이번 주 기록을 덮어썼습니다. 기기를 정리한 것이 남의 화면에서 내
       기록을 지우는 일이 되면 안 됩니다. */
    final snap = weeklySnapshot();
    if (!hasAnything(snap)) return {'ok': false, 'reason': '올릴 것 없음'};
    if (!jsTruthy(_state['onboarded']) && (_state['scans'] as List? ?? const []).isEmpty) {
      return {'ok': false, 'reason': '설치 직후 · 측정 없음'};
    }
    try {
      final pub = publishSnapshot;
      if (pub == null) return {'ok': false, 'reason': '로그인 안 함'};
      return pub(weekStartOf(), snap);
    } catch (e) {
      return {'ok': false, 'reason': '$e'};
    }
  }

  /* --- 백업 --------------------------------------------------------------- */

  String exportJSON() => const JsonEncoder.withIndent('  ').convert(_state);

  /// 저장이 실패하면 **던집니다.** 조용히 넘어가면 화면이 "가져왔습니다" 라고
  /// 말하고, 그 말을 믿은 사람이 원본 백업 파일을 지웁니다. 가져오기는 그게
  /// 마지막 복사본인 경우가 많습니다.
  void importJSON(String text) {
    final parsed = jsonDecode(text);
    if (parsed is! Map || parsed['version'] != storeVersion) {
      throw const FormatException('버전이 맞지 않는 데이터입니다');
    }
    _state = {...blank(), ...parsed.cast<String, Object?>()};
    if (!save()) {
      throw StateError('이 기기에 자리가 없어 저장하지 못했습니다 — '
          '원본 파일을 지우지 마세요. 설정에서 사진을 지우고 다시 해 보세요');
    }
  }

  /// 시험에서만 씁니다 — 저장을 거치지 않고 상태를 통째로 바꿉니다.
  void replaceState(Map<String, Object?> next) {
    _state = {...blank(), ...next};
  }
}

final RegExp _dateOnlyKey = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// `new Date(x)` — 날짜만 있는 문자열은 UTC 로 읽힙니다(JS 명세).
DateTime? jsParseLocal(Object? x) {
  if (x is DateTime) return x;
  if (x is! String) return null;
  final t = x.trim();
  if (_dateOnlyKey.hasMatch(t)) return DateTime.tryParse('${t}T00:00:00Z');
  return DateTime.tryParse(t);
}

/* --- 작은 도우미 ------------------------------------------------------------ */

Map<String, Object?>? _mapOrNull(Object? x) =>
    x == null ? null : (x as Map).cast<String, Object?>();

String _s(Object? x) {
  if (x == null) return 'null';
  if (x is num) return jsNumToString(x);
  return '$x';
}

/// `new Date(x).getTime()` — 못 읽으면 NaN.
double _msOf(Object? x) {
  if (x is! String) return double.nan;
  final d = DateTime.tryParse(x);
  return d == null ? double.nan : d.millisecondsSinceEpoch.toDouble();
}
