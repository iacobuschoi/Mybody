/* =============================================================================
 * cloud_test.dart — 기록이 내 계정에 저장되고, 새 기기에서 로그인하면 따라오는가
 * ========================================================================== */
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mybody/src/api.dart';
import 'package:mybody/src/app_state.dart';
import 'package:mybody/src/cloud.dart';
import 'package:mybody/src/news_store.dart';
import 'package:mybody/src/sync_queue.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _profile = {
  'sex': 'male', 'age': 22, 'heightCm': 187, 'activityLevel': 'moderate',
  'trainingAge': 'novice', 'daysPerWeek': 4, 'mealsPerDay': 3,
};
const _scan = {
  'id': 's1', 'weightKg': 86.7, 'smmKg': 38.0, 'bfmKg': 20.0,
  'measuredAt': '2026-03-01T00:00:00.000Z',
};

void main() {
  late List<Map<String, dynamic>> pushed;
  late Map<String, Object?>? serverState;
  late String serverAt;

  MockClient client() => MockClient((req) async {
        final p = req.url.path;
        if (p.endsWith('/sync/push') && req.method == 'POST') {
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          pushed.add(body);
          final rec = (body['records'] as List).first as Map;
          serverState = (rec['payload'] as Map).cast<String, Object?>();
          serverAt = '${rec['updatedAt']}';
          return http.Response('{"ok":true,"accepted":1}', 200);
        }
        if (p.endsWith('/sync/pull')) {
          final recs = serverState == null
              ? []
              : [{'kind': 'state', 'id': 'main', 'updatedAt': serverAt, 'deleted': false, 'payload': serverState}];
          return http.Response.bytes(utf8.encode(jsonEncode({'ok': true, 'records': recs, 'cursor': '', 'hasMore': false})), 200,
              headers: {'content-type': 'application/json; charset=utf-8'});
        }
        return http.Response('{"ok":false}', 404);
      });

  Future<(AppState, CloudSync, Api)> device({bool signedIn = true}) async {
    final api = Api(baseUrl: 'https://x.test', client: client());
    if (signedIn) await api.setToken('tok');
    final sp = await SharedPreferences.getInstance();
    final q = SyncQueue(api: api, storage: PrefsQueue(sp));
    final app = await AppState.boot();
    final cloud = CloudSync(app: app, api: api, queue: q, debounce: Duration.zero)..wire();
    return (app, cloud, api);
  }

  setUp(() {
    pushed = [];
    serverState = null;
    serverAt = '';
    SharedPreferences.setMockInitialValues({});
  });

  test('저장하면 기록 전체가 내 계정에 올라간다 (사진은 빼고)', () async {
    final (app, _, _) = await device();
    app.store.set({'profile': _profile, 'onboarded': true});
    app.store.addScan({..._scan});
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(pushed, isNotEmpty);
    final rec = (pushed.last['records'] as List).first as Map;
    expect(rec['kind'], 'state');
    expect(rec['id'], 'main');
    expect((rec['payload'] as Map)['scans'], hasLength(1));
    expect((rec['payload'] as Map).containsKey('photos'), isFalse);
  });

  test('새 기기: 서버에 기록이 있으면 로그인하자마자 받아 온다 — 되올리지 않는다', () async {
    /* 서버에 이미 기록이 있는 상태를 만듭니다. */
    final (a, _, _) = await device();
    a.store.set({'profile': _profile, 'onboarded': true});
    a.store.addScan({..._scan});
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(serverState, isNotNull);
    pushed.clear();

    /* 새 기기 — 저장소가 비어 있고, 로그인만 합니다. */
    SharedPreferences.setMockInitialValues({});
    final (b, cloud, api) = await device(signedIn: false);
    expect(CloudSync.isFresh(b), isTrue);
    await api.setToken('tok');          // 로그인 성공이 하는 일
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(b.store.sortedScans(), hasLength(1), reason: '기록이 따라와야 합니다');
    expect(b.onboarded, isTrue);
    expect(b.profile?['heightCm'], 187);
    expect(pushed, isEmpty, reason: '받아 온 것을 그대로 되올리면 안 됩니다');
    expect(await cloud.pull(), 'same');
  });

  test('이 기기가 더 새로우면 서버를 덮는다, 서버가 더 새로우면 받는다', () async {
    final (a, cloud, _) = await device();
    a.store.set({'profile': _profile, 'onboarded': true});
    a.store.addScan({..._scan});
    await Future<void>.delayed(const Duration(milliseconds: 80));

    /* 서버가 (다른 기기에서) 더 새로운 기록을 가졌다고 칩니다. */
    serverState = {...serverState!, 'goal': {'weightKg': 80.5, 'smmKg': 39.0, 'bfmKg': 12.0}};
    serverAt = DateTime.now().toUtc().add(const Duration(minutes: 1)).toIso8601String();
    expect(await cloud.pull(), 'imported');
    expect(a.state['goal'], isNotNull);

    /* 이제 이 기기에서 바꿉니다 → 이 기기가 더 새롭습니다. */
    pushed.clear();
    a.store.addScan({..._scan, 'id': 's2', 'measuredAt': '2026-05-01T00:00:00.000Z'});
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(pushed, isNotEmpty);
    expect((serverState!['scans'] as List), hasLength(2));
  });

  test('빈 기기는 서버의 기록을 빈 것으로 덮지 않는다', () async {
    final (b, cloud, _) = await device();
    expect(CloudSync.isFresh(b), isTrue);
    serverState = null;
    await cloud.push();
    expect(pushed, isEmpty);
  });
}
