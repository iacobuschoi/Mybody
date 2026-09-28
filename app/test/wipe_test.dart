/* 「이 기기에서 전부 지우기」와 「계정 지우기」 — 지운 뒤에 무엇이 남는가.
 *
 * 예전엔 기기 저장만 비우고 로그인은 그대로 뒀습니다. 다음에 켜면 동기화가
 * "막 깐 기기" 로 보고 계정 사본을 받아 와 **지운 기록이 되살아났고**, 그
 * 전에 온보딩을 다시 하면 빈 것에 가까운 기록이 **계정 사본을 덮어썼습니다.**
 * 설정 화면도 안 닫혀서, 지웠는데 지운 화면 위에 그대로 서 있었습니다. */
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dart:io';

import 'package:mybody/src/api.dart';
import 'package:mybody/src/app_state.dart';
import 'package:mybody/src/local_owner.dart';
import 'package:mybody/src/photos.dart';
import 'package:mybody/src/scope.dart';
import 'package:mybody/src/screens/settings.dart';
import 'package:mybody/src/sync_queue.dart';
import 'package:mybody/src/theme.dart';
import 'package:mybody_core/mybody_core.dart' as core;

import 'fake_accounts.dart' show FakeAccounts, Rig, recordsOfA;

class MemQueue implements QueueStorage {
  String? _v;
  @override String? read() => _v;
  @override void write(String raw) => _v = raw;
}

/// 로그인 · 로그아웃 · 계정 지우기는 받고, 기록 올리기는 망 오류(503)로
/// 막아서 큐에 남게 합니다 — "못 보낸 기록 사본" 이 있는 상태를 만듭니다.
MockClient fake(List<String> seen) => MockClient((req) async {
      final path = req.url.path.replaceFirst('/api', '');
      seen.add('${req.method} $path');
      final ok = path.startsWith('/auth/') || path == '/me';
      final body = <String, Object?>{'ok': ok, 'reason': '망 오류'};
      if (path == '/auth/signin') body['token'] = 'tok';
      return http.Response.bytes(utf8.encode(jsonEncode(body)), ok ? 200 : 503,
          headers: {'content-type': 'application/json; charset=utf-8'});
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    final v = TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher.views.first;
    v.physicalSize = const Size(1000, 4000);
    v.devicePixelRatio = 1.0;
    addTearDown(() { v.resetPhysicalSize(); v.resetDevicePixelRatio(); });
  });

  /// 셸 자리(첫 화면) 위에 설정을 밀어 올린 상태 — 앱에서 실제로 그렇게 엽니다.
  Future<({AppState app, Api api, SyncQueue queue, List<String> seen})> open(
      WidgetTester t) async {
    SharedPreferences.setMockInitialValues({});
    final seen = <String>[];
    final api = Api(baseUrl: 'https://x.test', client: fake(seen));
    await api.signIn(handle: 'a', password: 'b');
    final app = await AppState.boot();
    app.store.set({'onboarded': true, 'profile': {'sex': 'male', 'age': 30, 'heightCm': 175}});
    app.store.addScan({'id': 's1', 'weightKg': 80.0, 'smmKg': 35.0, 'bfmKg': 18.0,
        'pbfPct': 22.5, 'measuredAt': '2026-09-01T00:00:00.000Z'});
    final queue = SyncQueue(api: api, storage: MemQueue());
    queue.add('syncState', {'updatedAt': '2026-09-23T00:00:00.000Z', 'payload': {'n': 1}});

    await t.pumpWidget(Scope(
      state: app,
      api: api,
      queue: queue,
      onServerChange: (_) async {},
      child: MaterialApp(
        theme: mbLight(),
        home: Builder(builder: (context) => Scaffold(
              body: Center(child: TextButton(
                onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsScreen())),
                child: const Text('첫 화면'),
              )),
            )),
      ),
    ));
    await t.tap(find.text('첫 화면'));
    await t.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
    return (app: app, api: api, queue: queue, seen: seen);
  }

  testWidgets('전부 지우면 로그아웃까지 하고, 못 보낸 사본은 버리고, 설정을 닫는다', (t) async {
    final s = await open(t);
    expect(s.queue.pending, 1, reason: '못 보낸 기록 사본이 하나 있는 상태에서 시작');

    await t.tap(find.text('이 기기에서 전부 지우기'));
    await t.pumpAndSettle();
    /* 계정 사본이 남는다는 걸 누르기 전에 말해야 합니다. */
    expect(find.textContaining('다시 로그인하면 돌아옵니다'), findsWidgets);
    await t.tap(find.widgetWithText(FilledButton, '전부 지우기'));
    await t.pumpAndSettle();

    expect(s.api.signedIn, isFalse,
        reason: '로그인이 남으면 다음에 켤 때 계정 사본이 되살아납니다');
    expect(s.seen, contains('POST /auth/signout'));
    expect(s.app.state['onboarded'], isNot(true));
    expect((s.app.state['scans'] as List?) ?? const [], isEmpty);
    expect(s.queue.pending, 0,
        reason: '남기면 이 기기에 다음에 로그인한 계정으로 지운 사람의 기록이 올라갑니다');
    expect(find.byType(SettingsScreen), findsNothing, reason: '지웠으면 설정을 닫습니다');
    expect(find.text('첫 화면'), findsOneWidget);
  });

  testWidgets('그대로 두기를 누르면 아무것도 안 한다', (t) async {
    final s = await open(t);
    await t.tap(find.text('이 기기에서 전부 지우기'));
    await t.pumpAndSettle();
    await t.tap(find.text('그대로 두기'));
    await t.pumpAndSettle();
    expect(s.api.signedIn, isTrue);
    expect((s.app.state['scans'] as List?) ?? const [], hasLength(1));
    expect(find.byType(SettingsScreen), findsOneWidget);
    s.queue.clear();   // 다시 보내기 타이머를 남기지 않습니다
  });

  testWidgets('계정을 지우면 로그아웃하고 설정을 닫는다 — 기기 기록은 남는다', (t) async {
    final s = await open(t);
    await t.tap(find.text('계정 지우기'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, '계정 지우기'));
    await t.pumpAndSettle();
    expect(s.seen, contains('DELETE /me'));
    expect(s.api.signedIn, isFalse);
    expect((s.app.state['scans'] as List?) ?? const [], hasLength(1),
        reason: '계정 지우기는 기기 기록을 안 건드린다고 말했습니다');
    expect(find.byType(SettingsScreen), findsNothing);
    s.queue.clear();
  });

  /* 이 기기에는 치워 둔 칸이 있을 수 있습니다 — 로그아웃한 다른 계정, 로그인 없이 쓴 기록(local_owner.dart).
     "전부 지웠다" 고 믿고 폰을 넘긴 사람에게 누군가의 기록 · 친구 이름이 남아 있으면 안 됩니다. */
  testWidgets('전부 지우면 치워 둔 모든 칸 · 사진 · 독촉 · 소식 · 초대 표시 · 큐까지', (t) async {
    final dir = Directory.systemTemp.createTempSync('mybody-wipe-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final server = FakeAccounts()..add('a');
    final r = await Rig.boot(server, prefs: {
      'mybody.state.v1': jsonEncode({...core.Store.blank(), ...recordsOfA(photoId: 'p1')}),
      kOwnerKey: jsonEncode({'server': 'https://x.test', 'uid': 'u_a'}),
      '${kSlotPrefix}https://x.test|u_b.state': '{"scans":[{"id":"b1"}]}',
      '${kSlotPrefix}https://x.test|u_b.pokes': '[{"id":2}]',
      '${kSlotPrefix}guest.state': '{"scans":[{"id":"g1"}]}',
      'mybody.pokes.v1': '[{"id":1,"name":"나린"}]',
      'mybody.news.v1': '{"items":[]}',
      'mybody.invite.mine.v1': 'ABCDEFGH',
      'mybody.invite.handled.v1': '["ABCDEFGH"]',
      'mybody.invite.clipboard.v1': true,
    }, signedInAs: 'a');
    final photos = FilePhotos.at(dir);
    r.app.photos = photos;
    r.app.store.photos = photos;
    await t.runAsync(() => photos.save([1, 2]));   // 진짜 파일 — 가짜 시계 밖에서
    server.failWrites = true;
    r.queue.add('block', {'userId': 'f2'});

    await t.pumpWidget(r.host(const SettingsScreen()));
    await t.pumpAndSettle();
    await t.tap(find.text('이 기기에서 전부 지우기'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, '전부 지우기'));
    await t.pumpAndSettle();

    final sp = await SharedPreferences.getInstance();
    final left = sp.getKeys().where((k) =>
        k.startsWith(kSlotPrefix) || k.startsWith('mybody.invite.') || k == 'mybody.pokes.v1' ||
        k == 'mybody.news.v1' || k.startsWith('mybody.cloud.')).toList();
    expect(left, isEmpty, reason: '남은 것: $left');
    expect(photos.list(), isEmpty, reason: '결과지 사진(치워 둔 칸의 것까지 한 폴더)');
    expect(r.queue.pending, 0);
    expect(sp.getString('mybody.sync.queue.v1'), '[]');
    expect(r.app.pokes!.items, isEmpty);
    expect(r.app.store.sortedScans(), isEmpty);
    expect(r.api.signedIn, isFalse);
    r.dispose();
  });
}
