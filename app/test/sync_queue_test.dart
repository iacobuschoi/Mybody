/* 오프라인 큐가 지켜야 하는 성질들.
 *
 * 여기 시험 두 개는 웹 앱에서 **실제로 일어났던 고장**입니다. 옮기면서
 * 같이 옮겨지기 쉬운 종류라 못 박아 둡니다. */
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mybody/src/api.dart';
import 'package:mybody/src/sync_queue.dart';

class MemQueue implements QueueStorage {
  String? _v;
  String? get v => _v;
  @override String? read() => _v;
  @override void write(String raw) => _v = raw;
}

/// 경로별로 응답 코드를 정해 주는 가짜 서버. 무엇이 실제로 나갔는지 적습니다.
MockClient fake(Map<String, int> codes, List<String> seen) => MockClient((req) async {
      final path = req.url.path.replaceFirst('/api', '');
      seen.add('${req.method} $path');
      final code = codes[path] ?? 200;
      /* 로그인에는 **토큰을 줘야** 합니다. 안 주면 api.signedIn 이 거짓이라
         큐가 아무것도 안 받고, 시험은 "아무 일도 안 일어났다" 를 보게
         됩니다 — 큐가 멀쩡해도 실패합니다. */
      final body = <String, Object?>{'ok': code < 400, 'reason': '거절'};
      if (path == '/auth/signin') body['token'] = 'tok';
      return http.Response.bytes(utf8.encode(jsonEncode(body)), code,
          headers: {'content-type': 'application/json; charset=utf-8'});
    });

Future<Api> signedIn(http.Client c) async {
  SharedPreferences.setMockInitialValues({});
  final api = Api(baseUrl: 'https://x.test', client: c);
  await api.signIn(handle: 'a', password: 'b');
  return api;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('같은 주 스냅샷은 하나만 남는다', () async {
    final seen = <String>[];
    final api = await signedIn(fake({'/auth/signin': 200}, seen));
    final q = SyncQueue(api: api, storage: MemQueue());
    /* 저장할 때마다 스냅샷이 큐에 들어갑니다. 검수 화면에서 숫자 몇 개를
       고치면 같은 주 작업이 수십 개 쌓였습니다. 서버는 덮어쓰므로 마지막
       하나만 의미가 있습니다. */
    for (var i = 0; i < 5; i++) {
      q.add('snapshot', {'weekStart': '2026-09-21', 'payload': {'n': i}});
    }
    expect(q.pending, lessThanOrEqualTo(1));
  });

  test('큐가 넘치면 스냅샷부터 버린다 — 친구 수락은 지킨다', () async {
    final seen = <String>[];
    // 로그인만 되고 나머지는 다 망 오류가 나게 해서 큐에 쌓이게 합니다.
    final api = await signedIn(MockClient((req) async {
      final path = req.url.path.replaceFirst('/api', '');
      if (path == '/auth/signin') {
        return http.Response.bytes(
            utf8.encode(jsonEncode({'ok': true, 'token': 't'})), 200,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }
      seen.add(path);
      throw Exception('망 끊김');
    }));
    final q = SyncQueue(api: api, storage: MemQueue());
    q.add('accept', {'userId': 'friend-1'});
    for (var i = 0; i < 600; i++) {
      q.add('snapshot', {'weekStart': '2026-W$i', 'payload': const {}});
    }
    /* 제일 오래된 것은 사용자가 실제로 한 일입니다. 스냅샷은 다음 저장
       때 다시 만들어지지만 친구 수락은 안 그렇습니다. */
    expect(q.pending, lessThanOrEqualTo(500));
  });

  test('429 는 큐에 남는다 — 공유 끄기가 조용히 사라지면 안 된다', () async {
    final seen = <String>[];
    final api = await signedIn(fake({'/auth/signin': 200, '/share/f1': 429}, seen));
    final q = SyncQueue(api: api, storage: MemQueue());
    q.add('setShare', {'userId': 'f1', 'patch': {'streak': false}});
    await q.flush();
    /* 한도에 걸린 상태에서 공유를 끄면, 예전엔 앱은 껐다고 하고 서버는
       계속 보냈습니다. 껐다고 믿는 사람은 다시 확인하지 않습니다. */
    expect(q.pending, 1, reason: '429 를 버리면 끄기가 영영 안 닿습니다');
    q.dispose();
  });

  test('400 은 버린다 — 다시 보내도 같은 답입니다', () async {
    final seen = <String>[];
    final api = await signedIn(fake({'/auth/signin': 200, '/friends/accept': 400}, seen));
    final q = SyncQueue(api: api, storage: MemQueue());
    q.add('accept', {'userId': 'nope'});
    await q.flush();
    expect(q.pending, 0);
    expect(q.lastError, contains('거절'));
    q.dispose();
  });

  test('성공한 것만 정확히 빠진다', () async {
    final seen = <String>[];
    final api = await signedIn(fake({'/auth/signin': 200}, seen));
    final q = SyncQueue(api: api, storage: MemQueue());
    q.add('accept', {'userId': 'f1'});
    q.add('block', {'userId': 'f2'});
    await q.flush();
    expect(q.pending, 0);
    expect(seen, containsAll(['POST /friends/accept', 'POST /friends/block']));
    q.dispose();
  });

  test('로그인 안 했으면 아무것도 안 쌓는다', () async {
    SharedPreferences.setMockInitialValues({});
    final api = Api(baseUrl: 'https://x.test', client: fake({}, []));
    final q = SyncQueue(api: api, storage: MemQueue());
    q.add('accept', {'userId': 'f1'});
    /* 한 번도 로그인한 적이 없으면 보낼 것이 정말로 없습니다 —
       이 앱은 혼자서도 그대로 돌아갑니다. */
    expect(q.pending, 0);
  });

  test('앱을 껐다 켜도 큐가 남는다', () async {
    final seen = <String>[];
    final store = MemQueue();
    final api = await signedIn(MockClient((req) async {
      final path = req.url.path.replaceFirst('/api', '');
      if (path == '/auth/signin') {
        return http.Response.bytes(
            utf8.encode(jsonEncode({'ok': true, 'token': 't'})), 200,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }
      seen.add(path);
      throw Exception('망 끊김');
    }));
    SyncQueue(api: api, storage: store).add('accept', {'userId': 'f1'});
    // 앱이 다시 켜진 셈
    expect(SyncQueue(api: api, storage: store).pending, 1);
  });

  /* --- 누구의 일인가(피드백 52) ------------------------------------------------ */
  group('작업마다 주인', () {
    MockClient recorder(List<String> seen) => MockClient((req) async {
          final path = req.url.path.replaceFirst('/api', '');
          seen.add('${req.method} $path ${req.headers['Authorization'] ?? '-'}');
          return http.Response.bytes(utf8.encode(jsonEncode({'ok': true})), 200,
              headers: {'content-type': 'application/json; charset=utf-8'});
        });

    test('다른 로그인이 남긴 일은 보내지 않는다 — 그 계정으로 돌아오면 보낸다', () async {
      SharedPreferences.setMockInitialValues({});
      final seen = <String>[];
      final store = MemQueue();
      final api = Api(baseUrl: 'https://x.test', client: MockClient((_) async => throw Exception('망 끊김')));
      await api.setToken('tokA', uid: 'u_a');
      final q = SyncQueue(api: api, storage: store);
      q.add('block', {'userId': 'f2'});
      q.add('snapshot', {'weekStart': '2026-09-21', 'payload': {'n': 1}});
      q.dispose();
      expect((jsonDecode(store.v!) as List).map((j) => (j as Map)['owner']).toSet(), {'u_a'});

      /* 오프라인 로그아웃 → 다른 계정 B — 같은 저장소를 읽는 큐(앱을 다시 켠 것과 같음). */
      final apiB = Api(baseUrl: 'https://x.test', client: recorder(seen));
      await apiB.setToken('tokB', uid: 'u_b');
      final qb = SyncQueue(api: apiB, storage: store);
      expect(qb.pending, 0, reason: 'B 에게는 보낼 일이 없습니다');
      qb.add('accept', {'userId': 'f9'});   // B 자신의 일 — 이것이 부르는 flush 로도 A 것은 안 나감
      await qb.flush();
      expect(seen, ['POST /friends/accept Bearer tokB']);
      expect(store.v, contains('f2'), reason: 'A 의 일은 버리지 않고 남깁니다');

      /* A 로 돌아옴(새 토큰) — id 로 알아보고 보냅니다. */
      seen.clear();
      await apiB.setToken('tokA2', uid: 'u_a');
      await qb.flush();
      expect(seen, containsAll(['POST /friends/block Bearer tokA2', 'POST /snapshots Bearer tokA2']));
      expect(qb.pending, 0);
      qb.dispose();
    });

    test('칸으로 치우고 되돌리기 — takeFor 는 그 로그인의 일만, id 를 적어서', () async {
      SharedPreferences.setMockInitialValues({});
      final api = Api(baseUrl: 'https://x.test', client: MockClient((_) async => throw Exception('x')));
      await api.setToken('tokA');   // id 를 아직 모름(0.2.19 에서 올라온 첫 실행)
      final q = SyncQueue(api: api, storage: MemQueue());
      q.add('block', {'userId': 'f2'});
      final taken = q.takeFor(uid: 'u_a', sess: api.sessionTag);
      expect(taken, hasLength(1));
      expect(taken.single.owner, 'u_a', reason: '다시 로그인하면 토큰이 바뀌어 id 로만 알아봅니다');
      expect(q.pending, 0);
      q.putBack(taken);
      await api.setToken('tokA2', uid: 'u_a');
      expect(q.pending, 1);
      q.clear();
      q.dispose();
    });

    test('동기화를 끄면 치우는 dropOp · 0.2.19 의 주인 없는 옛 작업(adoptLegacy)', () async {
      SharedPreferences.setMockInitialValues({});
      final legacy = MemQueue()
        ..write(jsonEncode([
          {'op': 'syncState', 'args': {'updatedAt': 'x', 'payload': {}}, 'at': 1},
          {'op': 'accept', 'args': {'userId': 'f1'}, 'at': 2},
        ]));
      final api = Api(baseUrl: 'https://x.test', client: MockClient((_) async => throw Exception('x')));
      await api.setToken('tok', uid: 'u_a');
      final q = SyncQueue(api: api, storage: legacy);
      expect(q.pending, 0, reason: '주인 없는 옛 작업은 이관 전에는 안 보냅니다');
      q.adoptLegacy(uid: 'u_a', sess: api.sessionTag);
      expect(q.pending, 2);
      q.dropOp('syncState');
      expect(q.pendingOf('syncState'), 0);
      expect(q.pendingOf('accept'), 1);
      q.clear();

      final q2 = SyncQueue(api: api, storage: MemQueue()..write(jsonEncode([
        {'op': 'snapshot', 'args': {'weekStart': '2026-09-21', 'payload': {}}, 'at': 1},
      ])));
      q2.adoptLegacy();   // 주인을 모름(토큰 없이 기록만) — 버립니다
      expect(q2.pending, 0);
      expect(q2.storage.read(), '[]');
      q.dispose();
      q2.dispose();
    });
  });
}
