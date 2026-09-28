/* =============================================================================
 * account_switch_test.dart — 계정이 바뀌어도 기록이 다른 계정으로 새지 않는가 (피드백 52)
 *
 * 주인 폰: 계정 A 로 쓰다 로그아웃 → 새 계정 B 가입 → A 의 기록(9/19 86.7kg · D-81 · 상체 A)이
 * B 의 화면에 뜨고 B 의 서버 사본(records state/main)과 주간 요약(snapshots)으로 올라갔습니다.
 * 여기서 지키는 것(local_owner.dart 머리 주석):
 *   · 로그아웃하면 그 계정의 칸을 치워 두고, 다른 계정은 빈 기록(새 계정은 온보딩)에서 시작한다.
 *   · 로그인 · 가입의 알림을 듣는 쪽(주간 요약 · 동기화 · 셸)은 앞 계정의 칸을 한 번도 못 본다.
 *   · 같은 계정으로 돌아오면 치워 둔 칸(사진 id · 못 보낸 일까지)이 그대로 돌아온다.
 *   · 오프라인에서 쌓인 일 · 동기화를 끈 계정의 옛 사본도 다른 계정 토큰으로 안 나간다.
 *   · 로그아웃하는 다섯 길(설정 · 계정 관리 · 동의 거절 · 계정 지우기 · 전부 지우기) 모두.
 *   · 0.2.19 에서 올라온 첫 실행(이관) · 독촉 · 소식 · 알림 예약.
 * ========================================================================== */
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mybody/src/api.dart' show Api, LocalRecords, MergeAsk;
import 'package:mybody/src/local_owner.dart';
import 'package:mybody/src/photos.dart';
import 'package:mybody/src/screens/account.dart';
import 'package:mybody/src/screens/onboarding.dart';
import 'package:mybody/src/screens/settings.dart';
import 'package:mybody/src/shell.dart';
import 'package:mybody_core/mybody_core.dart' as core;
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_accounts.dart';

const _server = 'https://x.test';
String _slot(String uid, String part) => '$kSlotPrefix$_server|$uid.$part';

/// A 가 로그인해 쓰던 기기(0.2.20 모양 — 주인이 적혀 있음).
Map<String, Object> _deviceOfA({String? photoId}) => {
      'mybody.state.v1': jsonEncode({...core.Store.blank(), ...recordsOfA(photoId: photoId)}),
      kOwnerKey: jsonEncode({'server': _server, 'uid': 'u_a'}),
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeAccounts server;
  setUp(() {
    server = FakeAccounts()..add('a');
    Api.clientVersion = '0.2.20-test';
  });
  tearDown(() => Api.clientVersion = '');

  group('로그아웃 → 다른 계정', () {
    test('A 로그아웃 → 새 계정 B 가입: B 서버에 기록 · 요약 0건, 기기는 빈 기록, 알림 때 A 를 못 봄', () async {
      final r = await Rig.boot(server, prefs: _deviceOfA(), signedInAs: 'a');
      addTearDown(r.dispose);
      expect(await r.cloud.syncNow(), 'pushed');
      expect(server.user('a').scanIds, ['scan-1758240000000']);

      /* 로그인 · 로그아웃을 알리는 순간 기기의 기록 — 듣는 쪽이 보는 것과 같습니다. */
      final seen = <(String?, List<Object?>)>[];
      r.api.addListener(() => seen.add((r.api.token, r.scanIds)));

      await r.api.signOut();
      expect(r.api.signedIn, isFalse);
      expect(r.scanIds, isEmpty, reason: '로그아웃하면 이 계정의 칸은 치워집니다');
      expect(r.app.onboarded, isFalse);
      expect(r.app.owner.current, isNull);

      await r.api.signUp(handle: 'b', password: 'pw12345678', displayName: 'b',
          healthConsent: kHealthConsentVersion,
          askMerge: (_) async => fail('빈 기록이면 묻지 않습니다'));
      await settle();
      expect(r.api.signedIn, isTrue);
      expect(r.app.owner.current?.uid, 'u_b');
      expect(r.scanIds, isEmpty);
      expect(r.app.onboarded, isFalse, reason: '새 계정은 온보딩부터');
      expect(server.user('b').state, isNull, reason: 'B 의 서버 사본에 A 의 기록이 올라가면 안 됩니다');
      expect(server.user('b').snapshots, isEmpty, reason: 'A 의 주간 요약이 B 이름으로 나가면 안 됩니다');
      expect(server.writesTo('b'), isEmpty);
      for (final (tok, ids) in seen) {
        expect(ids, isNot(contains('scan-1758240000000')), reason: '알림($tok) 때 A 의 기록이 보였습니다');
      }
      final sp = await SharedPreferences.getInstance();
      expect(sp.getString(_slot('u_a', 'state')), contains('86.7'), reason: 'A 의 칸은 이 기기에 보관');
    });

    test('기록이 있는 기존 계정 B 로그인: 기기엔 B 것만, B 서버에 A 의 측정 없음, A 의 시각이 B 값을 못 이김', () async {
      final b = server.add('b')
        ..state = {
          ...core.Store.blank(),
          'profile': {'sex': 'female', 'age': 30, 'heightCm': 165},
          'goal': {'weightKg': 55.0, 'smmKg': 22.0, 'bfmKg': 12.0},
          'onboarded': true,
          'scans': [{'id': 'b1', 'weightKg': 60.0, 'smmKg': 22.0, 'bfmKg': 16.0,
                     'measuredAt': '2026-09-01T00:00:00.000Z'}],
        }
        ..at = '2026-09-02T00:00:00.000Z';
      final r = await Rig.boot(server, prefs: {
        ..._deviceOfA(),
        /* A 가 방금 바꾼 것 — B 서버 기록보다 늦습니다. 예전엔 이게 B 의 프로필 · 목표를 이겼습니다. */
        'mybody.cloud.localChangedAt.v1': isoNow(),
      }, signedInAs: 'a');
      addTearDown(r.dispose);

      await r.api.signOut();
      await r.api.signIn(handle: 'b', password: 'pw');
      await settle();
      expect(r.scanIds, ['b1']);
      expect(r.app.profile?['heightCm'], 165);
      expect((r.app.state['goal'] as Map)['weightKg'], 55.0);
      expect(b.scanIds, ['b1'], reason: 'B 서버에 A 의 측정이 섞이면 안 됩니다');
      expect(b.snapshots.where((s) => s['weightKg'] == 86.7), isEmpty);
    });

    test('B 로그아웃 → A 다시 로그인: 치워 둔 A 칸(사진 id 포함)이 돌아오고 사진 파일도 그대로, 잃은 것 0', () async {
      final dir = Directory.systemTemp.createTempSync('mybody-photos-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final photos = FilePhotos.at(dir);
      final r = await Rig.boot(server, prefs: _deviceOfA(photoId: 'p1'), signedInAs: 'a');
      addTearDown(r.dispose);
      r.app.photos = photos;
      r.app.store.photos = photos;
      final pid = await photos.save([1, 2, 3]);
      expect(r.cloud.enabled, isTrue);
      await r.cloud.syncNow();
      /* A 서버에는 다른 기기에서 넣은 측정이 하나 더 — 돌아올 때 합쳐져야 합니다. */
      server.user('a').state = {
        ...server.user('a').state!,
        'scans': [...(server.user('a').state!['scans'] as List),
          {'id': 'a2', 'weightKg': 85.9, 'smmKg': 38.2, 'bfmKg': 19.0, 'measuredAt': '2026-09-26T00:00:00.000Z'}],
      };
      server.user('a').at = isoNow(minutes: 1);

      await r.api.signOut();
      server.add('b');
      await r.api.signIn(handle: 'b', password: 'pw');
      await settle();
      expect(r.scanIds, isEmpty);
      r.app.store.addScan({'id': 'bx', 'weightKg': 70.0, 'smmKg': 30.0, 'bfmKg': 15.0,
          'measuredAt': '2026-09-27T00:00:00.000Z'});
      await settle();
      expect(server.user('b').scanIds, ['bx']);

      await r.api.signOut();
      await r.api.signIn(handle: 'a', password: 'pw');
      await settle();
      expect(r.scanIds, ['scan-1758240000000', 'a2'], reason: 'A 의 칸 + 다른 기기에서 넣은 것');
      expect(r.scanIds, isNot(contains('bx')));
      expect(r.app.store.scanById('scan-1758240000000')?['photoId'], 'p1');
      expect(photos.has(pid), isTrue, reason: '로그아웃 · 칸 바꾸기는 사진을 안 지웁니다');
      expect(server.user('a').scanIds, ['scan-1758240000000', 'a2']);
      expect(server.user('a').scanIds, isNot(contains('bx')));
      expect(server.user('b').scanIds, ['bx'], reason: 'B 칸에 A 것이 안 섞였습니다');
    });

    test('로그아웃 직전 3초 안에 바꾼 것도 A 로 간다 — 로그아웃이 먼저 보내 본다', () async {
      final r = await Rig.boot(server, prefs: _deviceOfA(), signedInAs: 'a',
          debounce: const Duration(seconds: 3));
      addTearDown(r.dispose);
      await r.cloud.syncNow();
      r.app.store.addScan({'id': 'late', 'weightKg': 86.0, 'smmKg': 38.0, 'bfmKg': 19.5,
          'measuredAt': '2026-09-27T00:00:00.000Z'});
      await settle(20);
      expect(server.user('a').scanIds, isNot(contains('late')), reason: '아직 모으는 중');
      await r.api.signOut();
      expect(server.user('a').scanIds, contains('late'));
    });
  });

  group('큐 · 동기화 스위치', () {
    test('오프라인에서 쌓인 A 의 일은 B 토큰으로 안 나가고, A 로 돌아오면 나간다', () async {
      final r = await Rig.boot(server, prefs: _deviceOfA(), signedInAs: 'a');
      addTearDown(r.dispose);
      server.failWrites = true;
      r.app.store.setSchedulePlan(r.app.store.dayKey(), 'gym', true);   // 요약 · 사본이 큐로
      r.queue.add('setShare', {'userId': 'f1', 'patch': {'diet': false}});
      r.queue.add('block', {'userId': 'f2'});
      await settle();
      expect(r.queue.pendingOf('syncState'), 1);
      expect(r.queue.pendingOf('snapshot'), 1);
      server.down = true;
      await r.api.signOut();                  // 오프라인 로그아웃
      server
        ..down = false
        ..failWrites = false;
      server.add('b');
      server.calls.clear();
      await r.api.signIn(handle: 'b', password: 'pw');
      await settle();
      final asB = [for (final c in server.calls) if (c.endsWith('@u_b')) c];
      expect(asB.where((c) => c.contains('/friends/block') || c.contains('/share/f1') ||
          c.contains('/sync/push') || c.contains('/snapshots')), isEmpty,
          reason: 'A 가 남긴 일이 B 토큰으로 나갔습니다: $asB');
      expect(server.user('b').state, isNull);

      await r.api.signOut();
      server.calls.clear();
      await r.api.signIn(handle: 'a', password: 'pw');
      await settle();
      expect(server.calls, containsAll(['POST /friends/block @u_a', 'PUT /share/f1 @u_a']));
      expect(server.calls.where((c) => c.startsWith('POST /snapshots @u_a')), isNotEmpty);
      expect(server.user('a').state, isNotNull);
      expect(r.queue.pending, 0);
    });

    test('동기화를 끄면 큐의 못 보낸 사본을 치운다 — 끈 계정의 옛 사본이 B 로 안 나간다', () async {
      final r = await Rig.boot(server, prefs: _deviceOfA(), signedInAs: 'a');
      addTearDown(r.dispose);
      server.failWrites = true;
      r.app.store.addScan({'id': 's9', 'weightKg': 86.1, 'smmKg': 38.0, 'bfmKg': 19.8,
          'measuredAt': '2026-09-27T00:00:00.000Z'});
      await settle();
      expect(r.queue.pendingOf('syncState'), 1);
      final settings = (r.app.state['settings'] as Map).cast<String, Object?>();
      r.app.store.set({'settings': {...settings, 'cloudSync': false}});
      await settle();
      expect(r.queue.pendingOf('syncState'), 0);
      await r.api.signOut();
      server.failWrites = false;
      await r.api.signUp(handle: 'b', password: 'pw12345678', displayName: 'b',
          healthConsent: kHealthConsentVersion);
      await settle();
      expect(server.user('b').state, isNull);
      expect(server.user('b').snapshots, isEmpty);
      /* A 칸은 동기화가 꺼진 채 보관 — 지우지 않습니다(이 기기가 유일본). */
      final sp = await SharedPreferences.getInstance();
      expect(sp.getString(_slot('u_a', 'state')), contains('s9'));
    });

    test('주인이 다른 칸이면 동기화 · 주간 요약이 아무것도 안 보낸다 (칸을 못 바꾼 날의 두 번째 잠금)', () async {
      final r = await Rig.boot(server, prefs: _deviceOfA(), signedInAs: 'a');
      addTearDown(r.dispose);
      server.add('b');
      /* 칸을 거치지 않고 토큰만 B 로 — 앱에는 없는 길이지만, 있어도 새지 않아야 합니다. */
      await r.api.setToken(server.login('b'), uid: 'u_b');
      await settle();
      expect(await r.cloud.syncNow(), 'owner');
      r.app.store.setSchedulePlan(r.app.store.dayKey(), 'cardio', true);
      await settle();
      expect(server.user('b').state, isNull);
      expect(server.user('b').snapshots, isEmpty);
      expect(server.writesTo('b'), isEmpty);
      /* 그 채로 로그아웃해도 A 의 기록은 A 의 칸으로 — 화면에 남지 않습니다. */
      await r.api.signOut();
      expect(r.scanIds, isEmpty);
      final sp = await SharedPreferences.getInstance();
      expect(sp.getString(_slot('u_a', 'state')), contains('86.7'));
    });
  });

  group('0.2.19 에서 올라온 첫 실행', () {
    test('(a) 토큰이 있으면 주인 = 지금 로그인 — /me 로 id 를 채우고 옛 큐 작업도 그 계정으로', () async {
      final r = await Rig.boot(server, prefs: {
        'mybody.state.v1': jsonEncode({...core.Store.blank(), ...recordsOfA()}),
        'mybody.sync.queue.v1': jsonEncode([
          {'op': 'accept', 'args': {'userId': 'f9'}, 'at': 1},
        ]),
      }, signedInAs: 'a', withUid: false);
      addTearDown(r.dispose);
      expect(r.app.owner.current?.sess, r.api.sessionTag, reason: '토큰의 로그인으로 묶어 둡니다');
      expect(await r.cloud.syncNow(), 'pushed');
      expect(r.app.owner.current?.uid, 'u_a', reason: '/me 로 알게 된 id — 로그아웃할 때 칸 이름');
      expect(server.calls, contains('POST /friends/accept @u_a'));
      final sp = await SharedPreferences.getInstance();
      expect(sp.getString(kOwnerKey), contains('u_a'));
      expect(sp.getString('mybody.token.uid.v1'), 'u_a');
    });

    test('(c) 토큰 없이 기록만 있으면 주인 모름 — 옛 작업 · 기준본은 버리고, 로그인해도 아무것도 안 올라간다', () async {
      final r = await Rig.boot(server, prefs: {
        'mybody.state.v1': jsonEncode({...core.Store.blank(), ...recordsOfA()}),
        'mybody.cloud.base.v1': jsonEncode({'server': _server, 'updatedAt': 'x', 'payload': {}}),
        'mybody.pokes.v1': jsonEncode([{'id': 1, 'name': '나린'}]),
        'mybody.sync.queue.v1': jsonEncode([
          {'op': 'syncState', 'args': {'updatedAt': '2026-09-20T00:00:00.000Z', 'payload': {}}, 'at': 1},
          {'op': 'accept', 'args': {'userId': 'f9'}, 'at': 2},
        ]),
      });
      addTearDown(r.dispose);
      expect(r.app.owner.current?.unknown, isTrue);
      final sp = await SharedPreferences.getInstance();
      expect(sp.getString('mybody.sync.queue.v1'), '[]');
      expect(sp.getString('mybody.cloud.base.v1'), isNull);
      expect(r.app.pokes!.items, isEmpty);

      server.add('b');
      LocalRecords? asked;
      await r.api.signIn(handle: 'b', password: 'pw', askMerge: (s) async {
        asked = s;
        return false;
      });
      await settle();
      expect(asked?.unknown, isTrue, reason: '「다른 계정의 기록일 수 있어요」 를 더해 묻습니다');
      expect(asked?.scans, 1);
      expect(r.scanIds, isEmpty);
      expect(server.user('b').state, isNull);
      expect(server.writesTo('b'), isEmpty);
      expect(sp.getString('${kSlotPrefix}guest.state'), contains('86.7'), reason: '합치지 않아도 기기에 보관');
    });
  });

  group('독촉 · 소식 · 알림 예약', () {
    test('A 가 받은 독촉 · 소식 안 읽음은 B 에게 안 보이고(오프라인이어도), A 로 돌아오면 다시 보인다', () async {
      final r = await Rig.boot(server, prefs: {
        ..._deviceOfA(),
        'mybody.pokes.v1': jsonEncode([{'id': 7, 'name': 'A친구', 'kind': 'workout'}]),
        'mybody.news.v1': jsonEncode({'seen': {}, 'items': [{'seq': 1, 'id': 'x', 'friendId': 'f1',
            'at': '2026-09-27T00:00:00.000Z', 'weekStart': '2026-09-21', 'keptDays': 2}],
            'readSeq': 0, 'seq': 1}),
      }, signedInAs: 'a');
      addTearDown(r.dispose);
      expect(r.app.pokes!.items, hasLength(1));
      expect(r.app.news!.unread(), 1);

      await r.api.signOut();
      server.add('b');
      await r.api.signIn(handle: 'b', password: 'pw');
      server.down = true;          // B 로 들어와 친구 목록을 못 받는 때(소식은 친구 목록으로 걸러짐)
      await settle();
      expect(r.app.pokes!.items, isEmpty, reason: 'A 친구의 독촉 띠가 B 의 친구 탭에 남으면 안 됩니다');
      expect(r.app.news!.unread(), 0);

      server.down = false;
      await r.api.signOut();
      await r.api.signIn(handle: 'a', password: 'pw');
      await settle();
      expect(r.app.pokes!.items.single['name'], 'A친구');
      expect(r.app.news!.unread(), 1);
    });

    test('로그아웃 · 계정 전환 뒤 알림 예약은 새 칸 기준 — 알리고, 빈 칸이면 끼니 · 운동 알림이 꺼진다', () async {
      final r = await Rig.boot(server, prefs: _deviceOfA(), signedInAs: 'a');
      addTearDown(r.dispose);
      r.app.store.setSchedulePlan(r.app.store.dayKey(DateTime.now().add(const Duration(days: 1))), 'gym', true);
      var notified = 0;
      r.app.addListener(() => notified++);
      await r.api.signOut();
      expect(notified, greaterThan(0), reason: 'main.dart 의 듣는 쪽이 알림을 다시 겁니다');
      /* nudge.dart 가 보는 것 — 온보딩 전이면 끼니 · 운동 알림을 다 지우고, 계획이 없으면 간식도. */
      expect(r.app.state['onboarded'], isNot(true));
      expect(r.app.state['schedule'], isEmpty);
      expect(r.app.state['plan'], isNull);
    });
  });

  group('이 기기에서 전부 지우기', () {
    test('모든 칸 · 사진 · 독촉 · 소식 · 초대 표시 · 큐를 지운다', () async {
      final dir = Directory.systemTemp.createTempSync('mybody-photos-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final photos = FilePhotos.at(dir);
      final r = await Rig.boot(server, prefs: {
        ..._deviceOfA(),
        _slot('u_b', 'state'): '{"scans":[{"id":"b1"}]}',
        _slot('u_b', 'queue'): '[]',
        '${kSlotPrefix}guest.state': '{"scans":[{"id":"g1"}]}',
        kGuestDeclinedKey: '{}',
        'mybody.pokes.v1': '[{"id":1}]',
        'mybody.news.v1': '{"items":[]}',
        'mybody.invite.mine.v1': 'ABCDEFGH',
        'mybody.invite.handled.v1': '["ABCDEFGH"]',
        'mybody.invite.clipboard.v1': true,
        'mybody.invite.pending.v1': '{"code":"ZZZZZZZZ"}',
      }, signedInAs: 'a');
      addTearDown(r.dispose);
      r.app.photos = photos;
      r.app.store.photos = photos;
      await photos.save([1]);
      server.down = true;
      r.queue.add('block', {'userId': 'f2'});
      await r.api.signOut();
      await wipeDevice(app: r.app, queue: r.queue, cloud: r.cloud);
      final sp = await SharedPreferences.getInstance();
      final left = sp.getKeys().where((k) => k.startsWith('mybody.') && k != 'mybody.state.v1').toList();
      expect(left.where((k) => k.startsWith(kSlotPrefix) || k.startsWith('mybody.invite.') ||
          k == 'mybody.pokes.v1' || k == 'mybody.news.v1' ||
          k.startsWith('mybody.cloud.')), isEmpty, reason: '남은 것: $left');
      expect(sp.getString(kOwnerKey) ?? '{}', '{}', reason: '주인 없음만 남습니다');
      expect(photos.list(), isEmpty);
      expect(r.queue.pending, 0);
      expect(sp.getString('mybody.sync.queue.v1'), '[]');
      expect(r.scanIds, isEmpty);
      expect(r.app.pokes!.items, isEmpty);
    });
  });

  /* --- 화면에서 누르는 길 --------------------------------------------------------- */
  group('화면 길', () {
    void phone(WidgetTester t) {
      t.view.physicalSize = const Size(1000, 3200);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      /* 복구 코드 창의 「복사하고 닫기」 — 시험에는 클립보드가 없어 대답을 흉내 냅니다. */
      final m = t.binding.defaultBinaryMessenger;
      m.setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
      addTearDown(() => m.setMockMethodCallHandler(SystemChannels.platform, null));
    }

    Future<void> signUpOnScreen(WidgetTester t, String handle) async {
      await t.tap(find.text('처음이에요'));
      await t.pumpAndSettle();
      await t.enterText(find.widgetWithText(TextField, '아이디'), handle);
      await t.enterText(find.widgetWithText(TextField, '비밀번호'), 'pw12345678');
      await t.tap(find.text('동의합니다'));
      await t.pumpAndSettle();
      await t.tap(find.text('계정 만들기'));
      await t.pumpAndSettle();
    }

    Future<void> signUpB(WidgetTester t, Rig r, {MergeAsk? ask}) async {
      await r.api.signUp(handle: 'b', password: 'pw12345678', displayName: 'b',
          healthConsent: kHealthConsentVersion, askMerge: ask);
      await t.pumpAndSettle();
    }

    void noLeakToB() {
      expect(server.user('b').state, isNull, reason: 'B 의 서버 사본에 A 의 기록');
      expect(server.user('b').snapshots, isEmpty, reason: 'B 이름으로 A 의 주간 요약');
      expect(server.writesTo('b'), isEmpty);
    }

    Future<Rig> guestDevice({bool unknown = false}) => Rig.boot(server, prefs: {
          'mybody.state.v1': jsonEncode({...core.Store.blank(), ...recordsOfA(), 'guest': true}),
          if (!unknown) kOwnerKey: '{}',
        });

    Widget signInScreen(Rig r) =>
        r.host(SignInScreen(api: r.api, onDone: () {}, onServerChange: (_) async {}));

    testWidgets('셸: 설정 「로그아웃」 → 첫 화면 「처음이에요」 로 B 가입 → 복구 코드 창 → 온보딩, 86.7kg 없음', (t) async {
      phone(t);
      final r = await Rig.boot(server, prefs: _deviceOfA(), signedInAs: 'a');
      await t.pumpWidget(r.host(const Shell()));
      await t.pumpAndSettle();
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.textContaining('86.7'), findsWidgets, reason: '시험의 전제 — A 의 홈');

      await t.tap(find.byTooltip('설정'));
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const Key('settings-logout')));
      await t.tap(find.byKey(const Key('settings-logout')));
      await t.pumpAndSettle();
      expect(find.text('이 계정의 기록은 이 기기에 따로 보관돼, 다시 로그인하면 돌아와요.'), findsOneWidget);
      await t.tap(find.byKey(const Key('settings-logout-confirm')));
      await t.pumpAndSettle();
      expect(find.byType(SignInScreen), findsOneWidget);

      await signUpOnScreen(t, 'b');
      expect(find.text('RC-b'), findsOneWidget, reason: '셸 첫 화면에서 가입해도 한 번뿐인 복구 코드 창이 떠야 합니다');
      /* 창이 떠 있는 동안은 토큰을 알리기 전 — 셸이 아직 이 화면(첫 화면)을 들고 있습니다. 알린 뒤에
         띄우면 셸이 첫 화면을 내리는 틈에 창을 띄울 자리가 사라질 수 있었습니다(시험의 저장소는 그
         틈이 안 생겨 창이 떠도, 이 둘로 순서를 지킵니다). */
      expect(r.api.signedIn, isFalse, reason: '토큰은 창을 닫은 뒤에 알립니다');
      expect(find.byType(SignInScreen), findsOneWidget);
      await t.tap(find.text('복사하고 닫기'));
      await t.pumpAndSettle();
      expect(find.byType(OnboardingScreen), findsOneWidget);
      expect(find.textContaining('86.7'), findsNothing);
      noLeakToB();
      expect(server.appHeaders, isNotEmpty);
      expect(server.appHeaders, everyElement('0.2.20-test'), reason: '모든 요청에 이 앱의 판(X-Mybody-App)');
      r.dispose();
    });

    testWidgets('로그아웃하면 「로그인 없이 쓰기」 표시가 있었어도 로그인 화면부터 — 로그인 없이 쓰기는 빈 기록', (t) async {
      phone(t);
      final r = await Rig.boot(server, prefs: {
        ..._deviceOfA(),
        /* 0.2.19 는 로그인해도 이 표시를 안 지웠습니다 — 로그아웃하면 로그인 화면 없이 A 의 탭이 떴습니다. */
        'mybody.state.v1': jsonEncode({...core.Store.blank(), ...recordsOfA(), 'guest': true}),
      }, signedInAs: 'a');
      await t.pumpWidget(r.host(const Shell()));
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('설정'));
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const Key('settings-logout')));
      await t.tap(find.byKey(const Key('settings-logout')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('settings-logout-confirm')));
      await t.pumpAndSettle();
      expect(find.byType(SignInScreen), findsOneWidget, reason: '탭 화면으로 곧장 가면 안 됩니다');
      await t.ensureVisible(find.text('로그인 없이 쓰기'));
      await t.tap(find.text('로그인 없이 쓰기'));
      await t.pumpAndSettle();
      expect(find.byType(OnboardingScreen), findsOneWidget, reason: '빈 기록 — 온보딩부터');
      expect(find.textContaining('86.7'), findsNothing);
      r.dispose();
    });

    testWidgets('계정 관리 앱바 아이콘 — 같은 창으로 묻고, A 칸을 치운다 · 다음 가입 0건', (t) async {
      phone(t);
      final r = await Rig.boot(server, prefs: _deviceOfA(), signedInAs: 'a');
      await t.pumpWidget(r.host(AccountScreen(api: r.api, onServerChange: (_) async {})));
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('로그아웃'));
      await t.pumpAndSettle();
      expect(find.text('로그아웃할까요?'), findsOneWidget);
      await t.tap(find.byKey(const Key('settings-logout-confirm')));
      await t.pumpAndSettle();
      expect(r.api.signedIn, isFalse);
      expect(r.scanIds, isEmpty);
      await signUpB(t, r, ask: (_) async => fail('빈 기록이면 묻지 않습니다'));
      noLeakToB();
      r.dispose();
    });

    testWidgets('동의 거절 — 로그인 없이 쓰기로 가되 A 의 기록은 칸에 보관 · 다음 가입 0건', (t) async {
      phone(t);
      server.user('a').oldConsent = true;
      final r = await Rig.boot(server, prefs: _deviceOfA(), signedInAs: 'a');
      /* 셸처럼 onDecline 없이 — 「로그인 없이 쓰기」 표시는 로그아웃이 다음 칸에 세웁니다. */
      await t.pumpWidget(r.host(ConsentGate(api: r.api, child: const Text('앱 본체'))));
      await t.pumpAndSettle();
      expect(find.text('동의 문구가 바뀌었습니다'), findsOneWidget);
      expect(find.textContaining('이 기기에 따로 보관돼'), findsOneWidget);
      await t.ensureVisible(find.text('동의하지 않고 로그인 없이 쓰기'));
      await t.tap(find.text('동의하지 않고 로그인 없이 쓰기'));
      await t.pumpAndSettle();
      expect(r.api.signedIn, isFalse);
      expect(r.app.state['guest'], isTrue, reason: '셸은 곧바로 「로그인 없이 쓰기」');
      expect(r.scanIds, isEmpty);
      final sp = await SharedPreferences.getInstance();
      expect(sp.getString(_slot('u_a', 'state')), contains('86.7'));
      await signUpB(t, r);
      noLeakToB();
      r.dispose();
    });

    testWidgets('계정 지우기 — 이 기기의 기록은 남되 주인 없는 기록, 다음 가입은 합칠지 먼저 묻는다', (t) async {
      phone(t);
      final r = await Rig.boot(server, prefs: _deviceOfA(), signedInAs: 'a');
      await t.pumpWidget(r.host(const SettingsScreen()));
      await t.pumpAndSettle();
      await t.ensureVisible(find.widgetWithText(OutlinedButton, '계정 지우기'));
      await t.tap(find.widgetWithText(OutlinedButton, '계정 지우기'));
      await t.pumpAndSettle();
      expect(find.textContaining('합칠지 먼저 물어요'), findsOneWidget);
      await t.tap(find.widgetWithText(FilledButton, '계정 지우기'));
      await t.pumpAndSettle();
      expect(r.api.signedIn, isFalse);
      expect(server.byHandle('a'), isNull);
      expect(r.scanIds, ['scan-1758240000000'], reason: '「이 기기의 기록은 그대로 남습니다」');
      expect(r.app.owner.current?.unknown, isTrue,
          reason: '지운 계정의 기록 — 로그인 없이 쓴 기록(주인 없음)과 달리 누구 것이었는지 압니다');
      LocalRecords? asked;
      await signUpB(t, r, ask: (s) async {
        asked = s;
        return false;
      });
      expect(asked?.scans, 1, reason: '말없이 합치지 않고 묻습니다');
      expect(asked?.unknown, isTrue, reason: '「다른 계정의 기록일 수 있어요」 와 함께 — 기본은 [합치지 않기]');
      noLeakToB();
      expect(r.scanIds, isEmpty);
      r.dispose();
    });

    testWidgets('계정 지우기 뒤 첫 화면 가입 — 창에 경고가 붙고 강조 버튼은 [합치지 않기]', (t) async {
      phone(t);
      final r = await Rig.boot(server, prefs: _deviceOfA(), signedInAs: 'a');
      await r.api.deleteAccount();
      await t.pumpWidget(signInScreen(r));
      await t.pumpAndSettle();
      await signUpOnScreen(t, 'b');
      await t.tap(find.text('복사하고 닫기'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('merge-local-warn')), findsOneWidget);
      expect(t.widget(find.byKey(const Key('merge-local-no'))), isA<FilledButton>());
      await t.tap(find.byKey(const Key('merge-local-no')));
      await t.pumpAndSettle();
      noLeakToB();
      r.dispose();
    });

    testWidgets('이 기기에서 전부 지우기 — 다음 가입 0건', (t) async {
      phone(t);
      final r = await Rig.boot(server, prefs: _deviceOfA(), signedInAs: 'a');
      await t.pumpWidget(r.host(const SettingsScreen()));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('이 기기에서 전부 지우기'));
      await t.tap(find.text('이 기기에서 전부 지우기'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, '전부 지우기'));
      await t.pumpAndSettle();
      expect(r.api.signedIn, isFalse);
      expect(r.scanIds, isEmpty);
      final sp = await SharedPreferences.getInstance();
      expect(sp.getKeys().where((k) => k.startsWith(kSlotPrefix)), isEmpty);
      await signUpB(t, r, ask: (_) async => fail('지웠으니 물을 것도 없습니다'));
      noLeakToB();
      r.dispose();
    });

    testWidgets('로그인 없이 쓴 기록으로 가입 — 「합칠까요?」, 고르기 전엔 아무것도 안 나가고 [합치기]면 올라간다', (t) async {
      phone(t);
      final r = await guestDevice();
      await t.pumpWidget(signInScreen(r));
      await t.pumpAndSettle();
      await signUpOnScreen(t, 'b');
      await t.tap(find.text('복사하고 닫기'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('merge-local')), findsOneWidget);
      expect(find.textContaining('로그인 없이 쓴 기록(측정 1건 · 최근 '), findsOneWidget);
      expect(find.textContaining('86.7kg)을 이 계정에 합칠까요?'), findsOneWidget);
      expect(find.byKey(const Key('merge-local-warn')), findsNothing);
      /* 고르기 전 — 토큰이 없어 주간 요약 · 동기화 · 큐가 아무것도 못 보냅니다. 큐는 저장된 것을 곧장
         봅니다(pending 은 로그인한 계정 몫만 세서 여기선 늘 0). */
      expect(r.api.signedIn, isFalse);
      final sp = await SharedPreferences.getInstance();
      expect(sp.getString('mybody.sync.queue.v1') ?? '[]', '[]');
      expect(server.writesTo('b'), isEmpty);
      expect(t.widget(find.byKey(const Key('merge-local-yes'))), isA<FilledButton>());

      await t.tap(find.byKey(const Key('merge-local-yes')));
      await t.pumpAndSettle();
      expect(r.api.signedIn, isTrue);
      expect(server.user('b').scanIds, ['scan-1758240000000'], reason: '합치기를 골랐으니 이 계정의 기록');
      expect(r.app.owner.current?.uid, 'u_b');
      expect(r.app.state['guest'], isNot(true));
      r.dispose();
    });

    testWidgets('[합치지 않기] — 안 올라가고 손님 칸에 보관, 로그아웃하면 돌아오고 같은 기록으로는 다시 안 묻는다', (t) async {
      phone(t);
      final r = await guestDevice();
      await t.pumpWidget(signInScreen(r));
      await t.pumpAndSettle();
      await signUpOnScreen(t, 'b');
      await t.tap(find.text('복사하고 닫기'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('merge-local-no')));
      await t.pumpAndSettle();
      expect(r.api.signedIn, isTrue);
      expect(r.scanIds, isEmpty);
      noLeakToB();
      final sp = await SharedPreferences.getInstance();
      expect(sp.getString('${kSlotPrefix}guest.state'), contains('86.7'));

      await r.api.signOut();
      await t.pumpAndSettle();
      expect(r.scanIds, ['scan-1758240000000'], reason: '「로그인 없이 쓰기」 의 기록이 돌아옵니다');
      await r.api.signIn(handle: 'b', password: 'pw', askMerge: (_) async => fail('같은 기록으로 또 묻지 않습니다'));
      await t.pumpAndSettle();
      expect(r.scanIds, isEmpty);
      noLeakToB();
      r.dispose();
    });

    testWidgets('0.2.19 에서 올라온 주인 모르는 기록 — 「다른 계정의 기록일 수 있어요」, 기본은 [합치지 않기]', (t) async {
      phone(t);
      server.add('b');
      final r = await guestDevice(unknown: true);
      expect(r.app.owner.current?.unknown, isTrue);
      await t.pumpWidget(signInScreen(r));
      await t.pumpAndSettle();
      await t.enterText(find.widgetWithText(TextField, '아이디'), 'b');
      await t.enterText(find.widgetWithText(TextField, '비밀번호'), 'pw');
      await t.tap(find.widgetWithText(FilledButton, '로그인'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('merge-local-warn')), findsOneWidget);
      expect(find.text('다른 계정의 기록일 수 있어요'), findsOneWidget);
      expect(t.widget(find.byKey(const Key('merge-local-no'))), isA<FilledButton>(),
          reason: '기본(강조)은 합치지 않기');
      expect(t.widget(find.byKey(const Key('merge-local-yes'))), isA<TextButton>());
      await t.tap(find.byKey(const Key('merge-local-no')));
      await t.pumpAndSettle();
      expect(r.scanIds, isEmpty);
      noLeakToB();
      r.dispose();
    });
  });

  /* --- 2차 검토에서 찾은 것 -------------------------------------------------------- */
  group('2차 검토', () {
    void phone(WidgetTester t) {
      t.view.physicalSize = const Size(1000, 3200);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      final m = t.binding.defaultBinaryMessenger;
      m.setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
      addTearDown(() => m.setMockMethodCallHandler(SystemChannels.platform, null));
    }

    testWidgets('동의 거절(셸) — 못 보낸 사본 · 요약을 그 자리에서 올리지 않고 A 칸에 둔다', (t) async {
      phone(t);
      server.user('a').oldConsent = true;
      final r = await Rig.boot(server, prefs: {
        ..._deviceOfA(),
        'mybody.sync.queue.v1': jsonEncode([
          {'op': 'syncState', 'at': 1, 'owner': 'u_a',
           'args': {'updatedAt': '2026-09-27T00:00:00.000Z', 'payload': {'scans': [{'id': 'new1'}]}}},
        ]),
      }, signedInAs: 'a');
      await t.pumpWidget(r.host(const Shell()));
      await t.pumpAndSettle();
      expect(find.text('동의 문구가 바뀌었습니다'), findsOneWidget);
      server.calls.clear();
      await t.ensureVisible(find.text('동의하지 않고 로그인 없이 쓰기'));
      await t.tap(find.text('동의하지 않고 로그인 없이 쓰기'));
      await t.pumpAndSettle();
      expect(r.api.signedIn, isFalse);
      expect(server.calls.where((c) => c.startsWith('POST /sync/push') || c.startsWith('POST /snapshots')),
          isEmpty, reason: '${server.calls}');
      expect(server.user('a').scanIds, isNot(contains('new1')));
      final sp = await SharedPreferences.getInstance();
      expect(sp.getString(_slot('u_a', 'queue')), contains('new1'), reason: 'A 로 돌아오면 갑니다');
      r.dispose();
    });

    test('치워 둔 칸이 가리키는 결과지 사진은 다른 칸에서 측정을 지워도 남는다', () async {
      final dir = Directory.systemTemp.createTempSync('mybody-photos-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final photos = FilePhotos.at(dir);
      final shared = await photos.save([1, 2, 3]);
      final own = await photos.save([4, 5, 6]);
      final r = await Rig.boot(server, prefs: {
        'mybody.state.v1': jsonEncode({...core.Store.blank(), 'onboarded': true, 'scans': [
          {'id': 'g1', 'weightKg': 86.7, 'smmKg': 38.0, 'bfmKg': 20.0,
           'measuredAt': '2026-09-19T00:00:00.000Z', 'photoId': shared},
          {'id': 'g2', 'weightKg': 86.0, 'smmKg': 38.0, 'bfmKg': 20.0,
           'measuredAt': '2026-09-20T00:00:00.000Z', 'photoId': own},
        ]}),
        kOwnerKey: '{"unknown":true}',
        _slot('u_a', 'state'): jsonEncode({...core.Store.blank(), ...recordsOfA(photoId: shared)}),
        _slot('u_a', 'owner'): jsonEncode({'server': _server, 'uid': 'u_a'}),
      });
      addTearDown(r.dispose);
      r.app.photos = photos;
      r.app.store.photos = photos;
      r.app.store.removeScan('g1');
      expect(photos.has(shared), isTrue, reason: 'A 칸의 측정이 가리킵니다 — 서버에도 없는 유일본');
      r.app.store.removeScan('g2');
      expect(photos.has(own), isFalse, reason: '아무도 안 가리키는 사진은 전처럼 지웁니다');
    });

    test('고르지 않고 끝난 합칠까요(null) — 합치지 않되 적지 않아, 다음 로그인에 다시 묻는다', () async {
      server.add('b');
      final r = await Rig.boot(server, prefs: {
        'mybody.state.v1': jsonEncode({...core.Store.blank(), ...recordsOfA(), 'guest': true}),
        kOwnerKey: '{}',
      });
      addTearDown(r.dispose);
      var asked = 0;
      await r.api.signIn(handle: 'b', password: 'pw', askMerge: (_) async {
        asked++;
        return null;   // 화면이 내려가 고르지 못함
      });
      await settle();
      expect(r.scanIds, isEmpty);
      expect(server.user('b').state, isNull);
      await r.api.signOut();
      expect(r.scanIds, ['scan-1758240000000']);
      await r.api.signIn(handle: 'b', password: 'pw', askMerge: (_) async {
        asked++;
        return true;
      });
      await settle();
      expect(asked, 2, reason: '고르지 않았으니 다시 묻습니다');
      expect(server.user('b').scanIds, ['scan-1758240000000']);
    });

    testWidgets('합칠까요 창은 뒤로 가기로 안 닫힌다 — 고르지 않은 것을 [합치지 않기] 로 적지 않는다', (t) async {
      phone(t);
      server.add('b');
      final r = await Rig.boot(server, prefs: {
        'mybody.state.v1': jsonEncode({...core.Store.blank(), ...recordsOfA(), 'guest': true}),
        kOwnerKey: '{}',
      });
      await t.pumpWidget(r.host(SignInScreen(api: r.api, onDone: () {}, onServerChange: (_) async {})));
      await t.pumpAndSettle();
      await t.enterText(find.widgetWithText(TextField, '아이디'), 'b');
      await t.enterText(find.widgetWithText(TextField, '비밀번호'), 'pw');
      await t.tap(find.widgetWithText(FilledButton, '로그인'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('merge-local')), findsOneWidget);
      await t.binding.handlePopRoute();   // 안드로이드 뒤로 가기
      await t.pumpAndSettle();
      expect(find.byKey(const Key('merge-local')), findsOneWidget, reason: '고르기 전엔 닫히지 않습니다');
      expect(r.api.signedIn, isFalse);
      await t.tap(find.byKey(const Key('merge-local-no')));
      await t.pumpAndSettle();
      r.dispose();
    });

    test('이 기기에서 전부 지우기 확인창 — 따로 보관된 다른 기록이 있으면 그것도 지워진다고 말한다', () async {
      /* 아래 위젯 시험의 셈 — 보관된 칸 수(다른 계정 · 로그인 없이 쓴 것). */
      final r = await Rig.boot(server, prefs: {
        ..._deviceOfA(),
        _slot('u_b', 'state'): '{"scans":[{"id":"b1"}]}',
        '${kSlotPrefix}guest.state': '{"scans":[{"id":"g1"}]}',
        kGuestDeclinedKey: '{}',
      }, signedInAs: 'a');
      addTearDown(r.dispose);
      expect(await parkedSlots(), (accounts: 1, guest: true));
    });

    testWidgets('이 기기에서 전부 지우기 확인창에 보관된 기록 수', (t) async {
      phone(t);
      final r = await Rig.boot(server, prefs: {
        ..._deviceOfA(),
        _slot('u_b', 'state'): '{"scans":[{"id":"b1"}]}',
      }, signedInAs: 'a');
      await t.pumpWidget(r.host(const SettingsScreen()));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('이 기기에서 전부 지우기'));
      await t.tap(find.text('이 기기에서 전부 지우기'));
      await t.pumpAndSettle();
      expect(find.text('이 기기에 따로 보관된 다른 계정 1개의 기록도 지워져요.'), findsOneWidget);
      await t.tap(find.text('그대로 두기'));
      await t.pumpAndSettle();
      r.dispose();
    });

    test('0.2.19 에서 올라와 id 를 끝내 모른 채 로그아웃 — 못 보낸 공유 끄기를 버리지 않고, 그 기록을 합친 계정으로 보낸다', () async {
      server.down = true;
      final r = await Rig.boot(server, prefs: {
        'mybody.state.v1': jsonEncode({...core.Store.blank(), ...recordsOfA()}),
        'mybody.sync.queue.v1': jsonEncode([
          {'op': 'setShare', 'args': {'userId': 'f1', 'patch': {'diet': false}}, 'at': 1},
        ]),
      }, signedInAs: 'a', withUid: false);
      addTearDown(r.dispose);
      await settle();
      await r.api.signOut();
      expect(r.app.owner.current?.unknown, isTrue);
      server.down = false;
      server.add('b');
      server.calls.clear();
      await r.api.signIn(handle: 'b', password: 'pw', askMerge: (s) async => false);
      await settle();
      expect(server.calls.where((c) => c.contains('/share/f1')), isEmpty, reason: '고르지 않은 계정으로는 안 갑니다');
      await r.api.signOut();
      await r.api.signIn(handle: 'a', password: 'pw', askMerge: (s) async {
        expect(s.unknown, isTrue);
        return true;
      });
      await settle();
      expect(server.calls, contains('PUT /share/f1 @u_a'));
    });

    test('서버가 409(다른 계정의 기록)로 거절하면 — 한 번만 보내고 큐에서 빼고, 다시 보내지 않는다', () async {
      final r = await Rig.boot(server, prefs: {
        ..._deviceOfA(),
        'mybody.sync.queue.v1': jsonEncode([
          {'op': 'syncState', 'at': 1, 'owner': 'u_a',
           'args': {'updatedAt': isoNow(), 'payload': {'syncMeta': {'owner': 'u_zzz'}, 'scans': []}}},
        ]),
      }, signedInAs: 'a');
      addTearDown(r.dispose);
      await r.queue.flush();
      final pushes = server.calls.where((c) => c.startsWith('POST /sync/push')).length;
      expect(pushes, 1);
      expect(r.queue.pending, 0);
      expect(r.queue.lastError, contains('다른 계정의 기록입니다'));
      await Future<void>.delayed(const Duration(milliseconds: 2500));   // 다시 보내기 첫 간격(2초)을 넘김
      expect(server.calls.where((c) => c.startsWith('POST /sync/push')).length, 1);
      expect(server.user('a').state, isNull);
    });

    test('동기화가 409 를 받으면 — rejected, 기준본은 안 올리고 이 기기 기록은 그대로', () async {
      final r = await Rig.boot(server, prefs: _deviceOfA(), signedInAs: 'a');
      addTearDown(r.dispose);
      server.conflictAll = true;
      expect(await r.cloud.syncNow(), 'rejected');
      expect(r.cloud.lastError, contains('다른 계정의 기록입니다'));
      final sp = await SharedPreferences.getInstance();
      expect(sp.getString('mybody.cloud.base.v1'), isNull);
      expect(r.scanIds, ['scan-1758240000000']);
      final n = server.calls.where((c) => c.startsWith('POST /sync/push')).length;
      await Future<void>.delayed(const Duration(milliseconds: 2500));
      expect(server.calls.where((c) => c.startsWith('POST /sync/push')).length, n, reason: '같은 것을 계속 보내지 않습니다');
    });

    test('요약에 싣는 주인은 칸의 주인 — 토큰과 어긋나면 서버가 409 로 막는다(두 번째 잠금)', () async {
      final r = await Rig.boot(server, prefs: _deviceOfA(), signedInAs: 'a');
      addTearDown(r.dispose);
      server.add('b');
      await r.api.setToken(server.login('b'), uid: 'u_b');
      /* 첫 잠금(mayLeave)을 건너뛰어 요약 고리를 곧바로 부릅니다 — 서버 잠금만 봅니다. */
      final res = r.app.store.publishSnapshot!(r.app.store.weekStartOf(), r.app.store.weeklySnapshot());
      expect(res['ok'], isTrue);
      await r.queue.flush();
      expect(server.calls, contains('POST /snapshots @u_b'));
      expect(server.user('b').snapshots, isEmpty, reason: 'A 의 요약이 B 로 들어가면 안 됩니다');
      /* 기록 사본도 같은 규칙 — 칸의 주인(u_a)을 싣습니다. */
      expect((r.cloud.stampOwner({'scans': []})['syncMeta'] as Map)['owner'], 'u_a');
    });

    testWidgets('A 에서 인사를 본 셸 — 로그아웃 뒤 다른 계정(기록 있음)으로 들어오면 그 계정에 테스터 인사', (t) async {
      phone(t);
      server.add('b')
        ..state = {...core.Store.blank(), ...recordsOfA(scanId: 'b1'),
            'settings': {'theme': 'auto', 'units': 'metric', 'checkinEveryWeeks': 1, 'defaultLevel': 'mid'}}
        ..at = '2026-09-02T00:00:00.000Z';
      final r = await Rig.boot(server, prefs: _deviceOfA(), signedInAs: 'a');
      await t.pumpWidget(r.host(const Shell()));
      await t.pumpAndSettle();
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byKey(const Key('welcome-primary')), findsNothing, reason: 'A 는 본 적이 있습니다');
      await r.api.signOut();
      await t.pumpAndSettle();
      await r.api.signIn(handle: 'b', password: 'pw');
      await t.pumpAndSettle();
      await t.pump(const Duration(seconds: 1));
      await t.pumpAndSettle();
      expect(find.byType(NavigationBar), findsOneWidget, reason: 'B 의 기록(온보딩 끝)이 들어왔습니다');
      expect(find.byKey(const Key('welcome-primary')), findsOneWidget, reason: 'B 는 처음 — 인사를 봅니다');
      r.dispose();
    });

    test('계정 지우기 뒤 · 손님 칸이 이미 있을 때 — 합치지 않기를 골라도 둘 다 잃지 않고, 섞인 칸은 주인 모름', () async {
      final r = await Rig.boot(server, prefs: {
        ..._deviceOfA(),
        '${kSlotPrefix}guest.state': jsonEncode({...core.Store.blank(), 'onboarded': true, 'scans': [
          {'id': 'scan-1700000000000', 'weightKg': 70.0, 'smmKg': 30.0, 'bfmKg': 15.0,
           'measuredAt': '2023-11-14T00:00:00.000Z'}]}),
        '${kSlotPrefix}guest.owner': '{}',
      }, signedInAs: 'a');
      addTearDown(r.dispose);
      await r.api.deleteAccount();
      expect(r.scanIds, ['scan-1758240000000'], reason: '「이 기기의 기록은 그대로」');
      server.add('b');
      await r.api.signIn(handle: 'b', password: 'pw', askMerge: (s) async {
        expect(s.unknown, isTrue, reason: '지운 계정의 기록 — 경고와 함께');
        return false;
      });
      await settle();
      expect(server.user('b').state, isNull);
      await r.api.signOut();
      expect(r.scanIds, containsAll(['scan-1700000000000', 'scan-1758240000000']));
      expect(r.app.owner.current?.unknown, isTrue, reason: '섞였으니 다음에 합칠 때도 경고');
    });
  });
}
