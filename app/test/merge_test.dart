/* =============================================================================
 * merge_test.dart — 두 기기의 기록이 **하나도 잃지 않고** 합쳐지는가
 *
 * 순수 함수라 서버도 저장소도 없이 봅니다. 같은 입력이면 같은 답이어야 하고,
 * 합친 것을 서버 것과 다시 합치면 더 바뀌는 게 없어야 합니다(그래야 두
 * 기기가 서로 올리기를 주고받다 멈춥니다).
 * ========================================================================== */
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mybody/src/merge.dart';
import 'package:mybody_core/mybody_core.dart' as core;

const t1 = '2026-09-01T00:00:00.000Z';
const t2 = '2026-09-02T00:00:00.000Z';
const t3 = '2026-09-03T00:00:00.000Z';
const t4 = '2026-09-04T00:00:00.000Z';
const t5 = '2026-09-05T00:00:00.000Z';

/// 빈 상태에 덮어 만든, JSON 을 한 번 거친(순수 Map/List) 상태.
Map<String, Object?> st([Map<String, Object?> over = const {}]) =>
    (jsonDecode(jsonEncode({...core.Store.blank(), ...over})) as Map).cast<String, Object?>();

Map<String, Object?> scan(String id, {double w = 80, String? updatedAt}) => {
      'id': id, 'measuredAt': '2026-0${id.codeUnitAt(1) - 48}-01T00:00:00.000Z',
      'weightKg': w, 'smmKg': 38.0, 'bfmKg': 20.0,
      if (updatedAt != null) 'updatedAt': updatedAt,
    };

Map<String, Object?> food(String id) =>
    {'id': id, 'date': '2026-09-01', 'meal': '점심', 'items': <Object?>[], 'source': 'manual', 'at': t1};

List<Object?> ids(Object? list, [String key = 'id']) => [for (final x in list as List) (x as Map)[key]];

Map<String, Object?> body(Map<String, Object?> m) => withoutSyncMeta(m);

Map<String, Object?> meta({Map<String, String> changedAt = const {}, String from = ''}) =>
    {'changedAt': changedAt, 'from': from};

void main() {
  group('목록 — 합집합', () {
    test('양쪽이 각각 넣은 측정·식단·체크인은 다 남는다, 서버 순서 먼저', () {
      final local = st({
        'scans': [scan('s2')], 'foodLogs': [food('f2')],
        'checkins': [{'at': t2, 'weightKg': 79.5}],
      });
      final remote = st({
        'scans': [scan('s1')], 'foodLogs': [food('f1')],
        'checkins': [{'at': t1, 'weightKg': 80.0}],
      });
      final m = mergeStates(local, remote, localAt: t2, remoteAt: t1);
      expect(ids(m['scans']), ['s1', 's2']);
      expect(ids(m['foodLogs']), ['f1', 'f2']);
      expect(ids(m['checkins'], 'at'), [t1, t2]);
      /* 입력은 그대로 */
      expect(ids(local['scans']), ['s2']);
      expect(ids(remote['scans']), ['s1']);
    });

    test('내 루틴도 합집합 — 각 기기가 만든 것은 다 남고, 같은 id 는 updatedAt 이 나중인 쪽', () {
      expect(mergedLists['routines'], 'id');
      Map<String, Object?> routine(String id, String name, String updatedAt) => {
            'id': id, 'name': name, 'label': '하체 B',
            'exercises': [{'name': '바벨 스쿼트', 'sets': 3, 'reps': '5-8', 'restSec': 150, 'kg': 60}],
            'createdAt': t1, 'updatedAt': updatedAt,
          };
      final m = mergeStates(
        st({'routines': [routine('r1', '하체 B 내 버전', t3), routine('r2', '폰에서 만든 것', t2)]}),
        st({'routines': [routine('r1', '하체 B', t2), routine('r3', '태블릿에서 만든 것', t2)]}),
        localAt: t1, remoteAt: t4,
      );
      expect(ids(m['routines']), ['r1', 'r3', 'r2'], reason: '서버 순서 먼저, 이 기기 것은 뒤에');
      final r1 = (m['routines'] as List).firstWhere((r) => (r as Map)['id'] == 'r1') as Map;
      expect(r1['name'], '하체 B 내 버전', reason: '레코드 전체는 서버가 새로워도 항목의 updatedAt 이 이깁니다');
      /* 한 바퀴 더 돌아도 그대로 */
      final again = mergeStates(body(m), body(m), localAt: t4, remoteAt: t4);
      expect(ids(again['routines']), ['r1', 'r3', 'r2']);
    });

    test('같은 항목을 둘 다 고쳤으면 updatedAt 이 나중인 쪽, 없으면 레코드가 나중인 쪽', () {
      /* updatedAt 이 있으면 레코드 전체 시각은 안 봅니다 — 서버가 더 새로워도. */
      var m = mergeStates(
        st({'scans': [scan('s1', w: 80, updatedAt: t3)]}),
        st({'scans': [scan('s1', w: 81, updatedAt: t2)]}),
        localAt: t1, remoteAt: t4,
      );
      expect((m['scans'] as List).single, containsPair('weightKg', 80));

      m = mergeStates(st({'scans': [scan('s1', w: 80)]}), st({'scans': [scan('s1', w: 81)]}),
          localAt: t2, remoteAt: t1);
      expect((m['scans'] as List).single, containsPair('weightKg', 80));
      m = mergeStates(st({'scans': [scan('s1', w: 80)]}), st({'scans': [scan('s1', w: 81)]}),
          localAt: t1, remoteAt: t2);
      expect((m['scans'] as List).single, containsPair('weightKg', 81));
      /* 같으면 서버 */
      m = mergeStates(st({'scans': [scan('s1', w: 80)]}), st({'scans': [scan('s1', w: 81)]}),
          localAt: t1, remoteAt: t1);
      expect((m['scans'] as List).single, containsPair('weightKg', 81));
    });

    test('어느 쪽 묘비든 지운 것은 지운 것 — 묘비도 합쳐진다', () {
      final local = st({
        'scans': [scan('s1'), scan('s2')], 'foodLogs': [food('f1')],
        'tombstones': {'scans': {'s1': t3}, 'foodLogs': <String, Object?>{}},
      });
      final remote = st({
        'scans': [scan('s1'), scan('s3')], 'foodLogs': [food('f1'), food('f2')],
        'tombstones': {'scans': <String, Object?>{}, 'foodLogs': {'f1': t2}},
      });
      final m = mergeStates(local, remote, localAt: t3, remoteAt: t4);
      expect(ids(m['scans']), ['s3', 's2']);
      expect(ids(m['foodLogs']), ['f2']);
      expect(m['tombstones'], {'scans': {'s1': t3}, 'foodLogs': {'f1': t2}});
    });

    test('기준본이 있으면 — 여기서 지운 것은 묘비를 세워 전하고, 저쪽이 지운 것은 여기서도 지운다', () {
      final base = st({'scans': [scan('s1'), scan('s2'), scan('s3')]});
      final local = st({'scans': [scan('s2'), scan('s3')]});            // s1 을 지웠다
      final remote = st({'scans': [scan('s1'), scan('s2')]});           // 저쪽은 s3 을 지웠다
      remote[syncMetaKey] = meta(from: t3);                             // 내 기준본(t3)을 본 레코드
      final m = mergeStates(local, remote, localAt: t4, remoteAt: t5, base: base, baseAt: t3);
      expect(ids(m['scans']), ['s2']);
      final tomb = (m['tombstones'] as Map)['scans'] as Map;
      expect(tomb['s1'], t4, reason: '이 기기가 마지막으로 바꾼 시각');
      expect(tomb['s3'], t5, reason: '서버 레코드의 시각');
    });

    test('내 올리기를 못 본 레코드에 없는 것은 지운 것이 아니다', () {
      /* 기준본 = 내가 s2 를 넣어 올린 것(t3). 서버 레코드는 그보다 옛 서버
         상태(t1)를 보고 만든 것 — s2 를 아직 못 받았을 뿐입니다. */
      final base = st({'scans': [scan('s1'), scan('s2')]});
      final local = st({'scans': [scan('s1'), scan('s2')]});
      final remote = st({'scans': [scan('s1'), scan('s3')]});
      remote[syncMetaKey] = meta(from: t1);
      var m = mergeStates(local, remote, localAt: t3, remoteAt: t4, base: base, baseAt: t3);
      expect(ids(m['scans']), ['s1', 's3', 's2']);

      /* 동기화 칸이 아예 없는 레코드(옛 앱 · 웹)도 같습니다. */
      remote.remove(syncMetaKey);
      m = mergeStates(local, remote, localAt: t3, remoteAt: t4, base: base, baseAt: t3);
      expect(ids(m['scans']), ['s1', 's3', 's2']);

      /* 내가 올린 것 그대로(시각이 같음)면 믿습니다 — 없는 것은 지운 것. */
      final mine = st({'scans': [scan('s1')]});
      m = mergeStates(local, mine, localAt: t3, remoteAt: t3, base: base, baseAt: t3);
      expect(ids(m['scans']), ['s1'], reason: 's2 는 저쪽에서 지운 것입니다');
    });
  });

  group('운동 일정', () {
    const d = '2026-09-22';

    test('둘 다 바꾼 날 — 계획은 합집합(헬스 먼저), 체크는 먼저 누른 시각, 기록은 더 많이 한 쪽', () {
      final local = st({
        'schedule': {
          d: {
            'plan': ['cardio'],
            'done': {'cardio': '2026-09-22T10:00:00.000Z'},
            'log': {'cardio': {'minutes': 30, 'at': t3}},
          },
        },
      });
      final remote = st({
        'schedule': {
          d: {
            'plan': ['gym', 'cardio'],
            'done': {'gym': '2026-09-22T09:00:00.000Z', 'cardio': '2026-09-22T08:00:00.000Z'},
            'log': {'cardio': {'minutes': 45, 'at': t2}, 'gym': {'minutes': 50}},
          },
        },
      });
      final m = mergeStates(local, remote, localAt: t3, remoteAt: t2);
      final day = ((m['schedule'] as Map)[d] as Map).cast<String, Object?>();
      expect(day['plan'], ['gym', 'cardio']);
      expect(day['done'], {'gym': '2026-09-22T09:00:00.000Z', 'cardio': '2026-09-22T08:00:00.000Z'});
      expect(((day['log'] as Map)['cardio'] as Map)['minutes'], 45);
      expect(((day['log'] as Map)['gym'] as Map)['minutes'], 50);

      /* 계획 순서는 종목의 고유 순서 — 이 기기가 유산소를 먼저 적었어도. */
      final m2 = mergeStates(
        st({'schedule': {d: {'plan': ['cardio', 'gym'], 'done': {}}}}),
        st({'schedule': {d: {'plan': ['cardio'], 'done': {}}}}),
        localAt: t2, remoteAt: t1,
      );
      expect(((m2['schedule'] as Map)[d] as Map)['plan'], ['gym', 'cardio']);
    });

    test('한쪽만 바꾼 날은 그쪽 — 체크를 풀면 서버에 남아 있어도 안 살아난다, 지운 날도 그대로', () {
      const d2 = '2026-09-23';
      final base = st({
        'schedule': {
          d: {'plan': ['gym'], 'done': {'gym': '2026-09-22T09:00:00.000Z'}},
          d2: {'plan': ['cardio'], 'done': {}},
        },
      });
      final local = st({
        'schedule': {d: {'plan': ['gym'], 'done': {}}},                 // 체크를 풀고 d2 는 지웠다
      });
      final remote = st({
        'schedule': {
          d: {'plan': ['gym'], 'done': {'gym': '2026-09-22T09:00:00.000Z'}},
          d2: {'plan': ['cardio'], 'done': {}},
        },
      });
      /* 저쪽은 안 바꿨습니다(내가 올린 것 그대로) — 서버 시각 == 기준본 시각. */
      final stamped = stampLocalChanges(local, base, at: t4);
      final m = mergeStates(stamped, remote, localAt: t4, remoteAt: t3, base: base, baseAt: t3);
      final sch = m['schedule'] as Map;
      expect((sch[d] as Map)['done'], isEmpty, reason: '푼 체크가 되살아나면 안 됩니다');
      expect(sch.containsKey(d2), isFalse, reason: '지운 날이 되살아나면 안 됩니다');
      /* 지운 날에도 시각이 남아, 다른 기기가 옛 사본으로 되살리지 못합니다. */
      expect(stampsOf(m)['schedule.$d2'], t4);

      /* 반대로 저쪽만 바꿨으면(체크) 저쪽 것 — 이 기기가 다른 걸 더 나중에 바꿨어도. */
      final remote2 = st({'schedule': {d: {'plan': ['gym'], 'done': {'gym': '2026-09-22T09:00:00.000Z'}}}});
      remote2[syncMetaKey] = meta(from: t3, changedAt: {'schedule.$d': t4});
      final base2 = st({'schedule': {d: {'plan': ['gym'], 'done': {}}}});
      final local2 = st({'schedule': {d: {'plan': ['gym'], 'done': {}}}, 'goal': {'weightKg': 70}});
      final m2 = mergeStates(stampLocalChanges(local2, base2, at: t5), remote2,
          localAt: t5, remoteAt: t4, base: base2, baseAt: t3);
      expect(((m2['schedule'] as Map)[d] as Map)['done'], {'gym': '2026-09-22T09:00:00.000Z'});
      expect(m2['goal'], {'weightKg': 70});
    });

    test('기준본 없이 한쪽에 날이 없으면 — 지운 시각이 더 나중일 때만 지운 것', () {
      final remote = st({'schedule': {d: {'plan': ['gym'], 'done': {}}}});
      remote[syncMetaKey] = meta(changedAt: {'schedule.$d': t2});
      final local = st();
      local[syncMetaKey] = meta(changedAt: {'schedule.$d': t3});
      var m = mergeStates(local, remote, localAt: t3, remoteAt: t2);
      expect((m['schedule'] as Map).containsKey(d), isFalse);
      local[syncMetaKey] = meta(changedAt: {'schedule.$d': t1});
      m = mergeStates(local, remote, localAt: t3, remoteAt: t2);
      expect((m['schedule'] as Map).containsKey(d), isTrue);
      /* 시각을 모르면 있는 쪽 — 잃는 것보다 되살아나는 것이 낫습니다. */
      m = mergeStates(st(), remote, localAt: t3, remoteAt: t2);
      expect((m['schedule'] as Map).containsKey(d), isTrue);
    });
  });

  group('하나짜리 값', () {
    test('기준본이 없으면 더 나중에 바꾼 쪽', () {
      final local = st({'goal': {'weightKg': 80}, 'plan': {'level': 'mid'}});
      final remote = st({'goal': {'weightKg': 82}, 'plan': {'level': 'low'}});
      var m = mergeStates(local, remote, localAt: t2, remoteAt: t1);
      expect(m['goal'], {'weightKg': 80});
      expect(m['plan'], {'level': 'mid'});
      m = mergeStates(local, remote, localAt: t1, remoteAt: t2);
      expect(m['goal'], {'weightKg': 82});
      expect(m['plan'], {'level': 'low'});
    });

    test('기준본이 있으면 바꾼 쪽 — 다른 쪽 레코드가 더 새로워도', () {
      final base = st({'goal': {'weightKg': 82}, 'profile': {'age': 22}});
      /* 이 기기는 목표를 안 바꾸고 식단만 적었다(레코드는 더 새롭다).
         저쪽은 목표를 바꿨다. */
      final local = st({'goal': {'weightKg': 82}, 'profile': {'age': 23}, 'foodLogs': [food('f1')]});
      final remote = st({'goal': {'weightKg': 79}, 'profile': {'age': 22}});
      remote[syncMetaKey] = meta(from: t3);
      final m = mergeStates(stampLocalChanges(local, base, at: t5), remote,
          localAt: t5, remoteAt: t4, base: base, baseAt: t3);
      expect(m['goal'], {'weightKg': 79}, reason: '저쪽만 바꾼 값');
      expect(m['profile'], {'age': 23}, reason: '이쪽만 바꾼 값');
      expect(ids(m['foodLogs']), ['f1']);
    });

    test('칸마다 붙은 시각이 레코드 전체 시각을 이긴다', () {
      final local = st({'goal': {'weightKg': 80}});
      final remote = st({'goal': {'weightKg': 82}});
      remote[syncMetaKey] = meta(changedAt: {'goal': t4});
      /* 이 기기 레코드가 더 새롭지만(t3) 저쪽은 목표를 t4 에 바꿨습니다. */
      final m = mergeStates(local, remote, localAt: t3, remoteAt: t2);
      expect(m['goal'], {'weightKg': 82});
      expect(stampsOf(m)['goal'], t4);
    });

    test('설정은 항목마다 — 나중 쪽이 이기고, 한쪽에만 있는 항목은 남는다', () {
      final local = st({'settings': {'theme': 'dark', 'units': 'metric', 'cloudSync': false}});
      final remote = st({'settings': {'theme': 'auto', 'units': 'metric', 'hideStreaks': true}});
      var m = mergeStates(local, remote, localAt: t2, remoteAt: t1);
      expect(m['settings'], {'theme': 'dark', 'units': 'metric', 'cloudSync': false, 'hideStreaks': true});

      /* 항목의 시각이 있으면 그걸로 */
      remote[syncMetaKey] = meta(changedAt: {'settings.theme': t3});
      m = mergeStates(local, remote, localAt: t2, remoteAt: t1);
      expect((m['settings'] as Map)['theme'], 'auto');
      expect((m['settings'] as Map)['cloudSync'], false);
    });

    test('온보딩 · 고지 동의는 어느 쪽이든 했으면 한 것', () {
      final m = mergeStates(st({'onboarded': true}), st({'disclaimerAccepted': true}),
          localAt: t1, remoteAt: t2);
      expect(m['onboarded'], isTrue);
      expect(m['disclaimerAccepted'], isTrue);
      final n = mergeStates(st(), st(), localAt: t1, remoteAt: t2);
      expect(n['onboarded'], isFalse);
    });

    test('모르는 칸은 어느 쪽에 있든 남는다', () {
      final local = st({'guest': true, 'both': {'v': 1}});
      final remote = st({'foo': {'x': 1}, 'both': {'v': 2}});
      final m = mergeStates(local, remote, localAt: t1, remoteAt: t2);
      expect(m['guest'], isTrue);
      expect(m['foo'], {'x': 1});
      expect(m['both'], {'v': 2}, reason: '둘 다 있으면 나중 쪽');
      expect(m['version'], core.storeVersion);
    });
  });

  group('전체', () {
    test('엇갈린 올리기 — 상대가 내 것을 못 보고 올렸어도 내가 바꾼 값이 되돌아가지 않는다', () {
      const mineAt = '2026-09-10T09:00:00.000Z';
      const pushAt = '2026-09-10T10:00:00.000Z';
      /* 기준본 = 내가 올린 것: s2 를 넣고 목표를 09:00 에 바꿨다. */
      final mine = st({'scans': [scan('s1'), scan('s2')], 'goal': {'weightKg': 80}});
      mine[syncMetaKey] = meta(changedAt: {'goal': mineAt}, from: '2026-09-09T00:00:00.000Z');
      /* 저쪽은 내 올리기 전의 서버(09-09)를 보고 s3 을 넣어 올렸다 — 목표는
         그때 서버에 있던 옛 값이고, 시각도 옛것. 프로필은 저쪽이 09:30 에 바꿨다. */
      final theirs = st({'scans': [scan('s1'), scan('s3')], 'goal': {'weightKg': 85}, 'profile': {'age': 30}});
      theirs[syncMetaKey] = meta(
        changedAt: {'goal': '2026-09-01T00:00:00.000Z', 'profile': '2026-09-10T09:30:00.000Z'},
        from: '2026-09-09T00:00:00.000Z',
      );
      final local = stampLocalChanges(withoutSyncMeta(mine), mine, at: pushAt, from: '');
      final m = mergeStates(local, theirs,
          localAt: pushAt, remoteAt: '2026-09-10T10:00:05.000Z', base: mine, baseAt: pushAt);
      expect(ids(m['scans']), ['s1', 's3', 's2'], reason: '양쪽이 넣은 것 다');
      expect(m['goal'], {'weightKg': 80}, reason: '내 목표(09:00)가 옛 값(09-01)에 밀리면 안 됩니다');
      expect(m['profile'], {'age': 30}, reason: '저쪽이 바꾼 프로필은 받습니다');
    });

    test('한 바퀴 돌면 더 합칠 것이 없다 — 합친 것과 서버 것을 다시 합치면 같다', () {
      final local = st({
        'scans': [scan('s2')], 'goal': {'weightKg': 80},
        'schedule': {'2026-09-22': {'plan': ['cardio'], 'done': {}}},
        'settings': {'theme': 'dark'},
      });
      final remote = st({
        'scans': [scan('s1')], 'goal': {'weightKg': 82},
        'schedule': {'2026-09-22': {'plan': ['gym'], 'done': {'gym': t2}}},
      });
      final m = mergeStates(local, remote, localAt: t3, remoteAt: t2);
      final again = mergeStates(m, remote, localAt: t3, remoteAt: t2, base: m, baseAt: t3);
      expect(sameState(body(again), body(m)), isTrue);
      /* 같은 입력이면 같은 답 */
      expect(canonicalJson(mergeStates(local, remote, localAt: t3, remoteAt: t2)), canonicalJson(m));
      /* 서버가 합친 것을 받아 든 뒤에는 '같음' */
      final settled = mergeStates(m, m, localAt: t3, remoteAt: t3, base: m, baseAt: t3);
      expect(sameState(body(settled), body(m)), isTrue);
    });

    test('합친 것은 그대로 저장소에 들일 수 있다', () {
      final m = mergeStates(
        st({'scans': [scan('s2')], 'onboarded': true, 'profile': {'sex': 'male', 'heightCm': 187, 'age': 22}}),
        st({'scans': [scan('s1')], 'goal': {'weightKg': 80.5, 'smmKg': 39.0, 'bfmKg': 12.0}}),
        localAt: t2, remoteAt: t1,
      );
      final store = core.Store(storage: core.MemoryStorage());
      store.importJSON(jsonEncode(withoutSyncMeta(m)));
      expect(store.sortedScans().map((s) => s['id']), ['s1', 's2']);
      expect(store.get()['onboarded'], isTrue);
      expect(store.get()['goal'], isNotNull);
      expect(store.get().containsKey(syncMetaKey), isFalse);
      /* 동기화 칸이 붙은 채로 들여도 깨지지 않습니다 (옛 백업 파일). */
      core.Store(storage: core.MemoryStorage()).importJSON(jsonEncode(m));
    });

    test('sameState — 키 순서와 187/187.0 에 흔들리지 않는다', () {
      expect(sameState({'a': 1, 'b': [1.0, {'c': 2}]}, {'b': [1, {'c': 2.0}], 'a': 1}), isTrue);
      expect(sameState({'a': 1}, {'a': 2}), isFalse);
      expect(sameState({'a': null}, {}), isFalse);
      expect(sameState({'a': 1.5}, {'a': 1}), isFalse);
    });

    test('stampLocalChanges — 기준본과 다른 칸에만 시각이 붙고, 기준본의 시각은 이어받는다', () {
      const d = '2026-09-22';
      final base = st({
        'goal': {'weightKg': 82}, 'profile': {'age': 22},
        'settings': {'theme': 'auto'},
        'schedule': {d: {'plan': ['gym'], 'done': {}}},
      });
      base[syncMetaKey] = meta(changedAt: {'profile': t1, 'goal': t1});
      final state = st({
        'goal': {'weightKg': 80}, 'profile': {'age': 22},
        'settings': {'theme': 'dark'},
        'scans': [scan('s1')],
      });
      final s = stampsOf(stampLocalChanges(state, base, at: t3, from: t2));
      expect(s['goal'], t3);
      expect(s['profile'], t1, reason: '안 바꾼 칸은 기준본의 시각 그대로');
      expect(s['settings.theme'], t3);
      expect(s['schedule.$d'], t3, reason: '지운 날에도 시각이 붙습니다');
      expect(s.containsKey('scans'), isFalse, reason: '목록은 항목마다 합치므로 시각이 없습니다');
      expect(syncFromOf(stampLocalChanges(state, base, at: t3, from: t2)), t2);
      /* 기준본이 없으면 붙일 것이 없습니다 */
      expect(stampsOf(stampLocalChanges(state, null, at: t3)), isEmpty);
    });
  });
}
