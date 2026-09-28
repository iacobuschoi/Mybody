/* =============================================================================
 * cloud_test.dart — 기록이 내 계정에 저장되고, 어느 기기에서 넣든 다 따라오는가
 *
 * 서버는 없습니다. 가짜 클라이언트가 레코드 하나(state/main)를 db.js 와
 * 같은 규칙으로 듭니다 — 옛 시각으로 올린 것은 안 받습니다. 기기 여럿은
 * CloudSync 여럿입니다. SharedPreferences 흉내는 하나뿐이라, 두 번째 기기를
 * 세우기 전에 비웁니다(먼저 세운 기기는 이미 자기 것을 메모리에 들고 있습니다).
 * ========================================================================== */
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mybody/src/api.dart';
import 'package:mybody/src/app_state.dart';
import 'package:mybody/src/cloud.dart';
import 'package:mybody/src/news_store.dart';
import 'package:mybody/src/scope.dart';
import 'package:mybody/src/screens/onboarding.dart';
import 'package:mybody/src/screens/sync_settings.dart';
import 'package:mybody/src/sync_queue.dart';
import 'package:mybody/src/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_accounts.dart' show FakeAccounts, Rig, recordsOfA;

const _profile = {
  'sex': 'male', 'age': 22, 'heightCm': 187, 'activityLevel': 'moderate',
  'trainingAge': 'novice', 'daysPerWeek': 4, 'mealsPerDay': 3,
};
const _scan = {
  'id': 's1', 'weightKg': 86.7, 'smmKg': 38.0, 'bfmKg': 20.0,
  'measuredAt': '2026-03-01T00:00:00.000Z',
};
const _scan2 = {
  'id': 's2', 'weightKg': 84.4, 'smmKg': 38.6, 'bfmKg': 17.5,
  'measuredAt': '2026-05-01T00:00:00.000Z',
};
const _goal = {'weightKg': 80.5, 'smmKg': 39.0, 'bfmKg': 12.0};

/// 서버 대신. 레코드 하나를 db.js 의 upsertRecord 와 같은 규칙으로 듭니다.
class _Server {
  Map<String, Object?>? state;
  String at = '';
  int pulls = 0, pushes = 0;
  bool down = false;
  final pushed = <Map<String, dynamic>>[];

  /* 서버는 시각을 자바스크립트의 toISOString() 으로 다듬습니다 — 밀리초까지. */
  static String _iso(String s) => CloudSync.isoMs(DateTime.parse(s));

  http.Response _json(Object body, [int status = 200]) => http.Response.bytes(
      utf8.encode(jsonEncode(body)), status,
      headers: {'content-type': 'application/json; charset=utf-8'});

  MockClient client() => MockClient((req) async {
        if (down) return http.Response('', 503);   // 터널이 대신 답하는 502·530 처럼
        final p = req.url.path;
        if (p.endsWith('/sync/push') && req.method == 'POST') {
          pushes++;
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          pushed.add(body);
          final rec = (body['records'] as List).first as Map;
          final up = _iso('${rec['updatedAt']}');
          if (at.isEmpty || up.compareTo(at) >= 0) {
            state = (rec['payload'] as Map).cast<String, Object?>();
            at = up;
          }
          return _json({'ok': true, 'accepted': 1, 'rejected': []});
        }
        if (p.endsWith('/sync/pull')) {
          pulls++;
          final recs = state == null
              ? []
              : [{'kind': 'state', 'id': 'main', 'updatedAt': at, 'deleted': false, 'payload': state}];
          return _json({'ok': true, 'records': recs, 'cursor': '', 'hasMore': false});
        }
        if (p.endsWith('/auth/signout')) return _json({'ok': true});
        return _json({'ok': false, 'reason': '그런 경로가 없습니다'}, 404);
      });

  int get requests => pulls + pushes;
  List<Object?> get scanIds => [for (final s in (state?['scans'] as List?) ?? const []) (s as Map)['id']];
  Map<String, Object?> day(String key) =>
      (((state?['schedule'] as Map?) ?? const {})[key] as Map?)?.cast<String, Object?>() ?? const {};
}

List<Object?> ids(AppState app) => app.store.sortedScans().map((s) => s['id']).toList();

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 120));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Server server;

  /// 기기 하나. 두 번째 기기는 [fresh] 로 저장소를 비우고 세웁니다.
  Future<(AppState, CloudSync, Api)> device({
    bool signedIn = true,
    bool fresh = false,
    DateTime Function()? now,
  }) async {
    if (fresh) SharedPreferences.setMockInitialValues({});
    final api = Api(baseUrl: 'https://x.test', client: server.client());
    if (signedIn) await api.setToken('tok');
    final sp = await SharedPreferences.getInstance();
    final q = SyncQueue(api: api, storage: PrefsQueue(sp));
    final app = await AppState.boot();
    final cloud = CloudSync(app: app, api: api, queue: q, debounce: Duration.zero, now: now)..wire();
    addTearDown(cloud.dispose);
    addTearDown(q.clear);   // 다시 보내기 타이머를 남기지 않습니다
    return (app, cloud, api);
  }

  setUp(() {
    server = _Server();
    SharedPreferences.setMockInitialValues({});
  });

  test('저장하면 기록 전체가 내 계정에 올라간다 (사진은 빼고)', () async {
    final (app, _, _) = await device();
    app.store.set({'profile': _profile, 'onboarded': true});
    app.store.addScan({..._scan});
    await settle();
    expect(server.pushed, isNotEmpty);
    final rec = (server.pushed.last['records'] as List).first as Map;
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
    await settle();
    expect(server.state, isNotNull);
    server.pushed.clear();

    /* 새 기기 — 저장소가 비어 있고, 로그인만 합니다. */
    final (b, cloud, api) = await device(signedIn: false, fresh: true);
    expect(CloudSync.isFresh(b), isTrue);
    await api.setToken('tok');          // 로그인 성공이 하는 일
    await settle();
    expect(b.store.sortedScans(), hasLength(1), reason: '기록이 따라와야 합니다');
    expect(b.onboarded, isTrue);
    expect(b.profile?['heightCm'], 187);
    expect(server.pushed, isEmpty, reason: '받아 온 것을 그대로 되올리면 안 됩니다');
    expect(await cloud.pull(), 'same');
    expect(cloud.lastSyncedAt, isNotNull);
    expect(cloud.lastResult, 'same');
  });

  test('서버에서 바뀐 것은 받고 이 기기에서 바뀐 것은 올린다 — 어느 쪽도 통째로 덮지 않는다', () async {
    final (a, cloud, _) = await device();
    a.store.set({'profile': _profile, 'onboarded': true});
    a.store.addScan({..._scan});
    await settle();

    /* 서버가 (다른 기기에서) 목표를 받았다고 칩니다. */
    server.state = {...server.state!, 'goal': _goal};
    server.at = CloudSync.isoMs(DateTime.now().add(const Duration(minutes: 1)));
    expect(await cloud.pull(), 'imported');
    expect(a.state['goal'], isNotNull);

    /* 이제 이 기기에서 측정을 넣습니다 → 서버는 목표를 지키고 측정을 더 받습니다. */
    server.pushed.clear();
    a.store.addScan({..._scan2});
    await settle();
    expect(server.pushed, isNotEmpty);
    expect(server.scanIds, ['s1', 's2']);
    expect(server.state!['goal'], isNotNull);
  });

  test('빈 기기는 서버의 기록을 빈 것으로 덮지 않는다', () async {
    final (b, cloud, _) = await device();
    expect(CloudSync.isFresh(b), isTrue);
    await cloud.push();
    expect(server.pushed, isEmpty);
    expect(await cloud.pull(), 'none');
  });

  /* --- 여기부터 0.2.9: 합치기 ---------------------------------------------- */

  test('두 기기 — 서로 넣은 측정이 합쳐진다, 어느 쪽도 다른 쪽 것을 지우지 않는다', () async {
    final (a, ca, _) = await device();
    a.store.set({'profile': _profile, 'onboarded': true});
    a.store.addScan({..._scan});
    await settle();
    expect(server.scanIds, ['s1']);

    /* 두 번째 기기 — 같은 계정으로 로그인해 자기 측정(s2)을 넣습니다(아직 한 번도 못
       맞춘 채). 예전에는 이 기기가 더 새로워서 s1 이 서버에서 사라졌습니다. */
    final (b, _, _) = await device(fresh: true);
    b.store.set({'profile': _profile, 'onboarded': true});
    b.store.addScan({..._scan2});
    await settle();
    expect(ids(b), ['s1', 's2'], reason: '서버 것을 받아 합칩니다');
    expect(server.scanIds, containsAll(['s1', 's2']), reason: '합친 것을 올립니다');

    /* 첫 기기가 다시 받아 보면 s2 가 옵니다. */
    expect(await ca.pull(), 'imported');
    expect(ids(a), ['s1', 's2']);
    /* 그 뒤로는 서로 같음 — 주고받기가 멈춥니다. */
    expect(await ca.pull(), 'same');
  });

  /* 로그인 없이 쓰던 기록은 로그인하는 문에서 「이 계정에 합칠까요?」 를 고른 때만 합칩니다
     (피드백 52 · local_owner.dart). 합치면 예전처럼 둘 다 안 잃고, 안 합치면 아무것도 안 갑니다. */
  test('로그인 없이 쓰던 기기가 로그인하며 [합치기] — 기기 것과 계정 것이 합쳐진다, 둘 다 안 잃는다', () async {
    final accounts = FakeAccounts();
    final a = accounts.add('a')
      ..state = {'version': 1, 'profile': _profile, 'onboarded': true, 'goal': _goal, 'scans': [{..._scan}]}
      ..at = '2026-09-01T00:00:00.000Z';
    final g = await Rig.boot(accounts, prefs: {'mybody.owner.v1': '{}'});
    addTearDown(g.dispose);
    g.app.store.set({'profile': {..._profile, 'heightCm': 170}, 'onboarded': true, 'guest': true});
    g.app.store.addScan({..._scan2});
    await settle();
    expect(accounts.calls.where((c) => c.contains('/sync/')), isEmpty, reason: '로그인 전에는 서버에 가지 않습니다');

    await g.api.signIn(handle: 'a', password: 'pw', askMerge: (_) async => true);
    await settle();
    expect(g.scanIds, ['s1', 's2']);
    expect(g.app.state['goal'], isNotNull, reason: '계정의 목표를 잃으면 안 됩니다');
    expect(g.app.profile?['heightCm'], 170, reason: '더 나중에 넣은 프로필');
    expect(a.scanIds, containsAll(['s1', 's2']));
    expect(a.state!['goal'], isNotNull);
  });

  test('로그인 없이 쓰던 기기가 로그인하며 [합치지 않기] — 계정 것만 받고, 기기 것은 안 올라간다', () async {
    final accounts = FakeAccounts();
    final a = accounts.add('a')
      ..state = {'version': 1, 'profile': _profile, 'onboarded': true, 'goal': _goal, 'scans': [{..._scan}]}
      ..at = '2026-09-01T00:00:00.000Z';
    final g = await Rig.boot(accounts, prefs: {'mybody.owner.v1': '{}'});
    addTearDown(g.dispose);
    g.app.store.set({'profile': {..._profile, 'heightCm': 170}, 'onboarded': true, 'guest': true});
    g.app.store.addScan({..._scan2});
    await settle();

    await g.api.signIn(handle: 'a', password: 'pw', askMerge: (_) async => false);
    await settle();
    expect(g.scanIds, ['s1']);
    expect(g.app.profile?['heightCm'], 187);
    expect(a.scanIds, ['s1'], reason: '고르지 않은 기록은 계정으로 안 갑니다');
  });

  test('로그인 문을 거치지 않고 토큰만 생겨도 — 주인 없는 기록은 안 올라간다(owner)', () async {
    final (g, cloud, api) = await device(signedIn: false, fresh: true);
    g.store.set({'profile': _profile, 'onboarded': true});
    g.store.addScan({..._scan2});
    await api.setToken('tok');
    await settle();
    expect(server.pushed, isEmpty);
    expect(cloud.lastResult, 'owner');
  });

  test('동기화를 끄면 올리지도 받지도 않는다 — 켜면 바로 맞춘다', () async {
    final (a, cloud, _) = await device();
    final settings = (a.state['settings'] as Map).cast<String, Object?>();
    a.store.set({'settings': {...settings, 'cloudSync': false}, 'profile': _profile, 'onboarded': true});
    a.store.addScan({..._scan});
    await settle();
    expect(server.requests, 0);
    expect(cloud.enabled, isFalse);
    expect(await cloud.pull(), 'off');
    expect(await cloud.syncNow(), 'off');
    await cloud.onResume();
    expect(server.requests, 0);

    a.store.set({'settings': {...settings, 'cloudSync': true}});
    await settle();
    expect(cloud.enabled, isTrue);
    expect(server.scanIds, ['s1']);
  });

  test('앱으로 돌아오면 받아 본다 — 2분에 한 번까지', () async {
    final (a, _, _) = await device();
    a.store.set({'profile': _profile, 'onboarded': true});
    a.store.addScan({..._scan});
    await settle();

    var clock = DateTime.utc(2026, 9, 24, 9);
    final (b, cb, _) = await device(fresh: true, now: () => clock);
    expect(await cb.pull(), 'imported');
    final n = server.pulls;

    await cb.onResume();
    expect(server.pulls, n, reason: '2분 안에는 다시 받아 보지 않습니다');
    clock = clock.add(const Duration(minutes: 3));
    await cb.onResume();
    expect(server.pulls, n + 1);
    expect(cb.lastResult, 'same');
    expect(ids(b), ['s1']);

    /* 그 사이 다른 기기가 올린 것이 돌아올 때 옵니다. */
    a.store.addScan({..._scan2});
    await settle();
    clock = clock.add(const Duration(minutes: 3));
    await cb.onResume();
    expect(ids(b), ['s1', 's2']);
  });

  test('체크를 풀면 서버에 남아 있던 체크가 되살아나지 않는다 (한 기기)', () async {
    final (a, _, _) = await device();
    a.store.set({'profile': _profile, 'onboarded': true});
    final today = a.store.dayKey();
    a.store.setSchedulePlan(today, 'gym', true);
    a.store.setScheduleDone(today, 'gym', true);
    await settle();
    expect(server.day(today)['done'], contains('gym'));

    a.store.setScheduleDone(today, 'gym', false);
    await settle();
    expect(a.store.scheduleDay(today)['done'], isEmpty, reason: '푼 체크가 다시 켜지면 안 됩니다');
    expect(server.day(today)['done'], isEmpty);

    a.store.setSchedulePlan(today, 'gym', false);
    await settle();
    expect(a.store.scheduleDay(today)['plan'], isEmpty, reason: '지운 계획이 다시 생기면 안 됩니다');
    expect(server.day(today), isEmpty);
  });

  test('두 기기가 같은 날 일정을 각각 바꿔도 둘 다 남는다', () async {
    final (a, ca, _) = await device();
    a.store.set({'profile': _profile, 'onboarded': true});
    final today = a.store.dayKey();
    a.store.setSchedulePlan(today, 'gym', true);
    await settle();

    final (b, cb, _) = await device(fresh: true);
    expect(await cb.pull(), 'imported');
    expect(b.store.scheduleDay(today)['plan'], ['gym']);

    /* 첫 기기는 체크하고, 두 번째 기기는 (그걸 못 본 채) 유산소를 더합니다. */
    a.store.setScheduleDone(today, 'gym', true);
    await settle();
    b.store.setSchedulePlan(today, 'cardio', true);
    await settle();
    final onB = b.store.scheduleDay(today);
    expect(onB['plan'], ['gym', 'cardio']);
    expect(onB['done'], contains('gym'));

    await ca.pull();
    final onA = a.store.scheduleDay(today);
    expect(onA['plan'], ['gym', 'cardio']);
    expect(onA['done'], contains('gym'));
    expect(await cb.pull(), 'same');
  });

  test('한 기기에서 지운 측정은 다른 기기에서도 지워진다', () async {
    final (a, _, _) = await device();
    a.store.set({'profile': _profile, 'onboarded': true});
    a.store.addScan({..._scan});
    a.store.addScan({..._scan2});
    await settle();

    final (b, cb, _) = await device(fresh: true);
    expect(await cb.pull(), 'imported');
    expect(ids(b), ['s1', 's2']);

    a.store.removeScan('s1');
    await settle();
    expect(server.scanIds, ['s2']);
    expect(((server.state!['tombstones'] as Map)['scans'] as Map).keys, contains('s1'));

    expect(await cb.pull(), 'imported');
    expect(ids(b), ['s2'], reason: '지운 것이 다른 기기에 남아 있으면 안 됩니다');
    /* 다시 올려도 안 살아납니다 */
    expect(await cb.pull(), 'same');
    expect(server.scanIds, ['s2']);
  });

  test('서버에 못 닿으면 offline 이고, 망이 돌아오면 그때 맞춘다', () async {
    final (a, cloud, _) = await device();
    server.down = true;
    a.store.set({'profile': _profile, 'onboarded': true});
    a.store.addScan({..._scan});
    await settle();
    expect(server.state, isNull);
    expect(cloud.lastResult, 'offline');
    expect(cloud.lastSyncedAt, isNull);
    expect(await cloud.syncNow(), 'offline');

    server.down = false;
    expect(await cloud.syncNow(), 'pushed');
    expect(server.scanIds, ['s1']);
    expect(cloud.lastSyncedAt, isNotNull);
  });

  test('서버가 내가 올린 것보다 옛것이면 합치지 않고 다시 올린다', () async {
    final (a, cloud, _) = await device();
    a.store.set({'profile': _profile, 'onboarded': true});
    a.store.addScan({..._scan});
    await settle();
    /* 서버가 되돌아갔습니다(복원 등) — 내가 올린 측정이 없습니다. 그 서버와
       합치면 s1 을 "저쪽이 지운 것" 으로 읽게 됩니다. */
    server.state = {...server.state!, 'scans': <Object?>[]};
    server.at = '2026-01-01T00:00:00.000Z';
    expect(await cloud.pull(), 'stale');
    expect(ids(a), ['s1']);
    expect(server.scanIds, ['s1'], reason: '다시 올립니다');
    expect(await cloud.pull(), 'same');
  });

  /* 예전 이 자리의 시험은 "로그아웃 → 다른 계정(tok2)으로 들어오면 이 기기 것(s1)과 그 계정 것(s2)이
     합쳐지고 서버에도 둘 다 올라간다" 를 기대값으로 굳혀 두었습니다 — 그게 피드백 52 의 새는 길이었습니다.
     이제는 뒤집어서: 다른 계정에는 그 계정 것만, A 로 돌아오면 A 의 것(로그아웃 전에 못 보낸 것까지). */
  test('로그아웃하면 이 계정의 칸을 치운다 — 다른 계정에는 그 계정 것만, A 로 돌아오면 A 의 것 그대로', () async {
    final accounts = FakeAccounts();
    final a = accounts.add('a');
    final b = accounts.add('b')
      ..state = {'version': 1, 'profile': _profile, 'onboarded': true, 'scans': [{..._scan2}]}
      ..at = '2026-09-01T00:00:00.000Z';
    final r = await Rig.boot(accounts, prefs: {
      'mybody.state.v1': jsonEncode({'version': 1, ...recordsOfA(scanId: 's1')}),
      'mybody.owner.v1': jsonEncode({'server': 'https://x.test', 'uid': 'u_a'}),
    }, signedInAs: 'a');
    addTearDown(r.dispose);
    expect(await r.cloud.syncNow(), 'pushed');
    final sp = await SharedPreferences.getInstance();
    expect(sp.getString('mybody.cloud.base.v1'), isNotNull);

    /* 로그아웃 직전, 아직 못 보낸 변경 — 오프라인이라 큐에 남습니다. */
    accounts.failWrites = true;
    r.app.store.addScan({'id': 's3', 'weightKg': 86.0, 'smmKg': 38.1, 'bfmKg': 19.6,
        'measuredAt': '2026-09-27T00:00:00.000Z'});
    await settle();
    accounts.down = true;
    await r.api.signOut();
    accounts
      ..down = false
      ..failWrites = false;
    expect(sp.getString('mybody.cloud.base.v1'), isNull, reason: 'A 의 기준본은 A 칸으로');
    expect(sp.getString('mybody.cloud.localChangedAt.v1'), isNull, reason: 'A 의 시각이 다음 계정의 값을 이기지 않게');
    expect(r.cloud.lastSyncedAt, isNull);

    await r.api.signIn(handle: 'b', password: 'pw');
    await settle();
    expect(r.scanIds, ['s2'], reason: '이 기기에 s1 이 보이면 안 됩니다');
    expect(b.scanIds, ['s2'], reason: 'B 서버에 A 의 측정이 올라가면 안 됩니다');

    await r.api.signOut();
    await r.api.signIn(handle: 'a', password: 'pw');
    await settle();
    expect(r.scanIds, ['s1', 's3'], reason: 'A 칸이 로그아웃 전에 못 보낸 변경까지 돌아옵니다');
    expect(a.scanIds, containsAll(['s1', 's3']));
    expect(a.scanIds, isNot(contains('s2')));
  });

  /* --- 화면 ---------------------------------------------------------------- */

  Widget host(AppState app, Api api, Widget child) => Scope(
        state: app,
        api: api,
        onServerChange: (_) async {},
        child: MaterialApp(theme: mbLight(), home: child),
      );

  testWidgets('설정 카드 — 상태를 보여 주고, 스위치가 settings.cloudSync 를 바꾼다', (t) async {
    final api = Api(baseUrl: 'https://x.test', client: server.client());
    await api.setToken('tok');
    final app = await AppState.boot();
    /* 로그인한 채 빈 칸에서 쓰기 시작한 기록 — 이 계정의 칸입니다(동기화가 켤 때 적습니다). */
    final cloud = CloudSync(app: app, api: api, queue: null, debounce: const Duration(days: 1))..wire();
    app.store.set({'profile': _profile, 'onboarded': true});
    app.store.addScan({..._scan});
    final clock = DateTime(2026, 9, 24, 9);
    await t.pumpWidget(host(app, api,
        Scaffold(body: SyncSettingsCard(cloud: cloud, api: api, now: () => clock))));
    await t.pump();
    expect(find.text('내 계정에 기록 동기화'), findsOneWidget);
    expect(find.text('아직 동기화하지 않았습니다'), findsOneWidget);
    expect(find.text('지금 동기화'), findsOneWidget);

    await t.runAsync(() => cloud.syncNow());
    await t.pump();
    expect(server.scanIds, ['s1']);
    expect(find.textContaining('마지막 동기화'), findsOneWidget);
    expect(find.textContaining('합침'), findsOneWidget);

    await t.tap(find.byType(Switch));
    await t.pump();
    expect((app.state['settings'] as Map)['cloudSync'], isFalse);
    expect(find.textContaining('꺼져 있습니다'), findsOneWidget);
    expect(find.text('지금 동기화'), findsNothing);
    cloud.dispose();
  });

  testWidgets('설정 카드 — 로그인 전에는 로그인이 필요하다고 말한다', (t) async {
    final api = Api(baseUrl: 'https://x.test', client: server.client());
    final app = await AppState.boot();
    await t.pumpWidget(host(app, api, Scaffold(body: SyncSettingsCard(cloud: null, api: api))));
    await t.pump();
    expect(find.textContaining('로그인하면'), findsOneWidget);
    expect(find.text('지금 동기화'), findsNothing);
    expect(CloudSync.enabledIn(app.state), isTrue, reason: '칸이 없으면 켠 것');
  });

  Future<void> finishOnboarding(WidgetTester t, {bool syncOff = false}) async {
    await t.enterText(find.widgetWithText(TextField, '키'), '155');
    await t.enterText(find.widgetWithText(TextField, '나이'), '34');
    await t.pump();
    await t.tap(find.text('다음'));
    await t.pumpAndSettle();
    await t.tap(find.text('다음'));
    await t.pumpAndSettle();
    await t.tap(find.text('읽었고 이해했습니다'));
    await t.pump();
    if (syncOff) {
      /* 스위치는 동의 칸 아래라 작은 화면에서는 단추 밑에 있습니다 — 올려서 누릅니다. */
      await t.ensureVisible(find.text('기록을 내 계정에 동기화'));
      await t.pumpAndSettle();
      await t.tap(find.text('기록을 내 계정에 동기화'));
      await t.pump();
    }
    await t.tap(find.text('시작하기'));
    await t.pumpAndSettle();
  }

  testWidgets('온보딩 — 동기화 스위치는 켜진 채로 시작하고 settings.cloudSync 에 남는다', (t) async {
    final api = Api(baseUrl: 'https://x.test', client: server.client());
    final app = await AppState.boot();
    await t.pumpWidget(host(app, api, const OnboardingScreen()));
    await t.pump();
    expect(find.text('기록을 내 계정에 동기화'), findsNothing, reason: '마지막 단계에만');
    await finishOnboarding(t);
    expect(app.onboarded, isTrue);
    expect((app.state['settings'] as Map)['cloudSync'], isTrue);
    expect((app.state['settings'] as Map)['theme'], 'auto', reason: '다른 설정은 그대로');
  });

  testWidgets('온보딩 — 스위치를 끄면 settings.cloudSync 가 false 로 남는다', (t) async {
    final api = Api(baseUrl: 'https://x.test', client: server.client());
    final app = await AppState.boot();
    await t.pumpWidget(host(app, api, const OnboardingScreen()));
    await t.pump();
    await finishOnboarding(t, syncOff: true);
    expect(app.onboarded, isTrue);
    expect((app.state['settings'] as Map)['cloudSync'], isFalse);
    expect(CloudSync.enabledIn(app.state), isFalse);
  });
}
