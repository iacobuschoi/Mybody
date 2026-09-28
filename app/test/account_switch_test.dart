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
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mybody/src/api.dart' show Api, LocalRecords, MergeAsk;
import 'package:mybody/src/app_state.dart';
import 'package:mybody/src/cloud.dart';
import 'package:mybody/src/local_owner.dart';
import 'package:mybody/src/news_store.dart';
import 'package:mybody/src/photos.dart';
import 'package:mybody/src/publish.dart';
import 'package:mybody/src/screens/account.dart';
import 'package:mybody/src/screens/onboarding.dart';
import 'package:mybody/src/screens/settings.dart';
import 'package:mybody/src/screens/social.dart' show FriendDetailScreen, SocialScreen, kMyInviteCodeKey;
import 'package:mybody/src/shell.dart';
import 'package:mybody/src/sync_queue.dart';
import 'package:mybody_core/mybody_core.dart' as core;
import 'package:shared_preferences/shared_preferences.dart';
// 저장이 느린 기기를 흉내 내려면 플랫폼 쪽 틀이 필요합니다(shared_preferences 가 딸고 오는 것).
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'fake_accounts.dart';

const _server = 'https://x.test';
String _slot(String uid, String part) => '$kSlotPrefix$_server|$uid.$part';
String _slot2(String server, String uid, String part) => '$kSlotPrefix$server|$uid.$part';

/// A 가 로그인해 쓰던 기기(0.2.20 모양 — 주인이 적혀 있음). [syncOff] 면 동기화를 꺼 둔 A — 이 기기가 유일본.
Map<String, Object> _deviceOfA({String? photoId, bool syncOff = false}) {
  final a = recordsOfA(photoId: photoId);
  return {
    'mybody.state.v1': jsonEncode({
      ...core.Store.blank(), ...a,
      if (syncOff) 'settings': {...(a['settings'] as Map), 'cloudSync': false},
    }),
    kOwnerKey: jsonEncode({'server': _server, 'uid': 'u_a'}),
  };
}

/// 한 열쇠의 쓰기를 붙잡아 두는 기기 저장소 — 동기화가 그 칸을 적는 사이(저장이 느린 폰)에 로그아웃 ·
/// 다른 계정 가입을 끼워 넣습니다.
class _GateDisk extends InMemorySharedPreferencesStore {
  _GateDisk(super.data) : super.withData();
  String? gateKey;
  final hit = Completer<void>();
  final release = Completer<void>();

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (gateKey != null && key == 'flutter.$gateKey') {
      gateKey = null;
      hit.complete();
      await release.future;
    }
    return super.setValue(valueType, key, value);
  }
}

/// 한 열쇠의 다음 쓰기 한 번을 실패시키는 기기 저장소 — 저장 공간이 꽉 찬 순간.
class _FailOnceDisk extends InMemorySharedPreferencesStore {
  _FailOnceDisk(super.data) : super.withData();
  String? failKey;
  bool failed = false;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (failKey != null && key == 'flutter.$failKey') {
      failKey = null;
      failed = true;
      return false;
    }
    return super.setValue(valueType, key, value);
  }
}

/// 켜 둔 기기의 저장소를 [_GateDisk] 로 바꿉니다 — [key] 의 다음 쓰기가 붙잡힙니다.
Future<_GateDisk> _gate(String key) async {
  final now = await SharedPreferencesStorePlatform.instance.getAll();
  final disk = _GateDisk(Map<String, Object>.of(now))..gateKey = key;
  SharedPreferencesStorePlatform.instance = disk;
  return disk;
}

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
      expect(sp.getString('mybody.token.uid.v1'), Api.uidRecordOf(r.api.token!, 'u_a'),
          reason: '토큰 곁에 — 어느 토큰의 id 인지 같이');
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

    /* 3차 검토(공격 N1)에서 기대를 바로잡았습니다 — 예전 기대는 "그 기록을 합친 계정으로 보낸다" 였고,
       그래서 A 의 차단 · 친구 요청이 [합치기] 를 고른 B 명의로 나갔습니다. 기록을 합치는 것은 사람이
       고른 일이지만, 친구 일은 누구의 것인지 다시는 알 길이 없습니다. */
    test('0.2.19 에서 올라와 id 를 끝내 모른 채 로그아웃 — 그 로그인의 못 보낸 일은 버린다: 어느 계정으로도(합친 계정이어도) 안 나간다', () async {
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
      final sp = await SharedPreferences.getInstance();
      expect(sp.getString('mybody.sync.queue.v1'), '[]', reason: '주인 id 를 끝내 모른 로그인의 일은 로그아웃할 때 버립니다');
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
      expect(server.calls.where((c) => c.contains('/share/f1')), isEmpty,
          reason: '기록을 합친 계정이 그 일의 주인이라는 보장이 없습니다 — 친구 일은 붙이지 않습니다');
      expect(server.user('a').scanIds, ['scan-1758240000000'], reason: '기록은 [합치기] 를 고른 계정으로 갑니다(동기화가 다시 만듦)');
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

  /* --- 3차 검토(공격 검증)에서 뚫린 것 ----------------------------------------------------- */
  group('3차 검토', () {
    const aScan = 'scan-1758240000000';
    const other = 'scan-a2-other-device';

    Future<void> signUpB(Rig r, {MergeAsk? ask}) async {
      final res = await r.api.signUp(handle: 'b', password: 'pw12345678', displayName: 'b',
          healthConsent: kHealthConsentVersion, askMerge: ask ?? (_) async => fail('빈 기록이면 묻지 않습니다'));
      expect(res.ok, isTrue, reason: res.reason);
      await settle();
    }

    test('N1 · 0.2.19(id 모름) · 오프라인 친구 일 → 오프라인 로그아웃 → B 가입 [합치기] — A 의 친구 일이 B 명의로 안 나간다', () async {
      server.down = true;
      final r = await Rig.boot(server, prefs: {
        'mybody.state.v1': jsonEncode({...core.Store.blank(), ...recordsOfA()}),
      }, signedInAs: 'a', withUid: false);
      addTearDown(r.dispose);
      await settle();
      r.queue
        ..add('block', {'userId': 'f-of-a'})
        ..add('sendRequest', {'inviteCode': 'A-FRIEND'})
        ..add('setShare', {'userId': 'f1', 'patch': {'diet': false}});
      await settle();
      await r.api.signOut();
      expect(r.app.owner.current?.unknown, isTrue);
      server.down = false;
      server.calls.clear();
      await signUpB(r, ask: (s) async {
        expect(s.unknown, isTrue, reason: '「다른 계정의 기록일 수 있어요」');
        return true;   // 경고를 보고도 합침
      });
      await settle(300);
      final asB = [
        for (final c in server.calls)
          if (c.endsWith('@u_b') && (c.contains('/friends/') || c.contains('/share/'))) c
      ];
      expect(asB, isEmpty, reason: 'A 의 친구 일이 B 명의로 나갔습니다: $asB');
      expect(server.user('b').scanIds, [aScan], reason: '기록은 [합치기] 를 골랐으니 B 의 것');
    });

    /* 동기화가 서버 것과 합친 뒤 이 기기 칸(시각 · 기준본)을 적는 사이 — 저장이 느린 폰 — 로그아웃하고
       다른 계정으로 가입하면, 그 맞춤이 기다림에서 깨어나 앞 계정의 합친 사본을 새 토큰 · 새 주인
       이름으로 올리거나(409 도 통과) 새 칸에 기준본으로 적었습니다. 두 갈래(올릴 때 · 받기만 할 때). */
    for (final (name, serverHas) in [
      ('올리는 갈래(서버에 없는 측정이 기기에)', [other]),
      ('받기만 하는 갈래(서버가 기기 것을 다 가짐)', [aScan, other]),
    ]) {
      test('N5 · 맞추다 이 기기 칸을 적는 사이 로그아웃 → B 가입 — 앞 맞춤이 A 의 기록을 B 로 올리거나 B 칸에 적지 않는다: $name', () async {
        server.user('a')
          ..state = {...core.Store.blank(), ...recordsOfA(), 'scans': [
            for (final id in serverHas)
              {'id': id, 'weightKg': id == aScan ? 86.7 : 85.9, 'smmKg': 38.2, 'bfmKg': 19.0,
               'measuredAt': id == aScan ? '2026-09-19T00:00:00.000Z' : '2026-09-26T00:00:00.000Z'},
          ]}
          ..at = isoNow(minutes: -5);
        final r = await Rig.boot(server, prefs: _deviceOfA(), signedInAs: 'a');
        addTearDown(r.dispose);
        final disk = await _gate(CloudSync.keyAt);
        final sync = r.cloud.syncNow();
        await disk.hit.future.timeout(const Duration(seconds: 3));
        await r.api.signOut();   // 보내 보기는 flushLimit(2초)만 기다리고 넘어갑니다
        await signUpB(r);
        disk.release.complete();
        await sync;
        await settle(300);
        String leak(Object? o) => [aScan, other].where(jsonEncode(o).contains).join(', ');
        expect(leak(server.user('b').state), isEmpty, reason: 'A 의 기록이 B 서버 사본에');
        expect(server.writesTo('b'), isEmpty);
        final sp = await SharedPreferences.getInstance();
        expect(leak(sp.getString(CloudSync.keyBase)), isEmpty, reason: 'A 의 합친 사본이 B 칸의 기준본으로');
        expect(r.scanIds, isEmpty);
        /* B 가 쓰기 시작해도 — 더럽혀진 기준본이 있었다면 A 의 측정이 "지웠다"(묘비)로 B 에 올라갔습니다. */
        r.app.store.set({'onboarded': true});
        r.app.store.addScan({'id': 'bx', 'weightKg': 60.0, 'smmKg': 25.0, 'bfmKg': 15.0,
            'measuredAt': '2026-09-27T00:00:00.000Z'});
        await r.cloud.syncNow();
        await settle();
        expect(server.user('b').scanIds, ['bx']);
        expect(leak(server.user('b').state), isEmpty, reason: 'A 의 측정 id 가 B 의 묘비로');
        /* A 로 돌아오면 A 의 기록 그대로 */
        await r.api.signOut();
        await r.api.signIn(handle: 'a', password: 'pw');
        await settle();
        expect(r.scanIds, containsAll([aScan, other]));
        expect(server.user('a').scanIds, containsAll([aScan, other]));
      });
    }

    test('N4b · 앱에 박힌 서버 주소만 바뀐 판(같은 서버 · 토큰 살아 있음) — 서버가 같은 계정이라 말하면 주인의 주소를 옮기고 동기화 · 요약이 돈다', () async {
      const moved = 'https://new-host.test';
      final r = await Rig.boot(server, prefs: _deviceOfA(), signedInAs: 'a', base: moved);
      addTearDown(r.dispose);
      expect(await r.cloud.syncNow(), 'pushed');
      expect(r.app.owner.current?.server, moved, reason: '주인의 서버 주소를 새 주소로');
      expect(r.app.owner.current?.uid, 'u_a');
      expect(server.user('a').scanIds, [aScan]);
      r.app.store.setSchedulePlan(r.app.store.dayKey(), 'gym', true);
      await settle();
      expect(server.user('a').snapshots, isNotEmpty, reason: '주간 요약도 다시 나갑니다');
      /* 로그아웃 → 다른 계정 → 돌아오기도 새 주소 이름의 칸으로 */
      await r.api.signOut();
      expect(r.scanIds, isEmpty);
      await r.api.signIn(handle: 'a', password: 'pw');
      await settle();
      expect(r.scanIds, contains(aScan));
    });

    test('N4b · 주소가 바뀐 곳이 다른 서버면(그 서버가 이 토큰을 모름) — 멈추고 아무것도 안 보낸다', () async {
      final elsewhere = FakeAccounts()..add('a');   // 같은 아이디가 있어도 다른 서버
      final r = await Rig.boot(elsewhere, prefs: {
        ..._deviceOfA(),
        'mybody.token.v1': 'tok-from-x-test',
        'mybody.token.uid.v1': Api.uidRecordOf('tok-from-x-test', 'u_a'),
      }, base: 'https://elsewhere.test');
      addTearDown(r.dispose);
      expect(await r.cloud.syncNow(), 'owner');
      r.app.store.setSchedulePlan(r.app.store.dayKey(), 'gym', true);
      await settle();
      expect(elsewhere.calls.where((c) => c.startsWith('POST /sync/push') || c.startsWith('POST /snapshots')), isEmpty);
      expect(r.app.owner.current?.server, _server, reason: '주인의 주소는 그대로');
    });

    test('N4 · 서버 주소를 바꿨다(로그인 채) 로그아웃 → 원래 주소로 A 로그인 — 동기화 끈 A 의 기록(유일본)을 찾는다', () async {
      final r = await Rig.boot(server, prefs: _deviceOfA(syncOff: true), signedInAs: 'a');
      final sp = await SharedPreferences.getInstance();
      final queues = <SyncQueue>[r.queue];
      var cloud = r.cloud;
      addTearDown(() {
        for (final q in queues) {
          q
            ..clear()
            ..dispose();
        }
        cloud.dispose();
      });
      /* main.dart _setServer 처럼 — 같은 칸에 새 주소의 Api · 큐 · 동기화를 꽂습니다. */
      Future<Api> setServer(String base) async {
        final api = Api(baseUrl: base, client: server.client);
        await api.loadToken();
        api.accounts = r.slots;
        final q = SyncQueue(api: api, storage: PrefsQueue(sp));
        queues.add(q);
        r.slots.queue = q;
        wirePublishing(r.app, api, q);
        cloud.dispose();
        cloud = CloudSync(app: r.app, api: api, queue: q)..wire();
        r.slots.cloud = cloud;
        return api;
      }

      final api2 = await setServer('https://y.test');
      await api2.signOut();
      final api3 = await setServer(_server);
      await api3.signIn(handle: 'a', password: 'pw');
      await settle();
      final keys = sp.getKeys().where((k) => k.startsWith(kSlotPrefix)).toList();
      expect(r.scanIds, contains(aScan), reason: 'A 의 기록(동기화 꺼짐 — 유일본)이 안 돌아옴. 칸: $keys');
    });

    test('N4 · 다른 서버 주소 이름으로 치워 둔 칸도 계정 id 로 찾는다(주소를 바꿨다 되돌린 기기)', () async {
      final r = await Rig.boot(server, prefs: {
        _slot2('https://y.test', 'u_a', 'state'): jsonEncode({...core.Store.blank(), ...recordsOfA(), 'settings': {
          ...(recordsOfA()['settings'] as Map), 'cloudSync': false}}),
        _slot2('https://y.test', 'u_a', 'owner'): jsonEncode({'server': 'https://y.test', 'uid': 'u_a'}),
        kOwnerKey: '{}',
      });
      addTearDown(r.dispose);
      await r.api.signIn(handle: 'a', password: 'pw', askMerge: (_) async => fail('빈 기록이면 묻지 않습니다'));
      await settle();
      expect(r.scanIds, [aScan]);
      final sp = await SharedPreferences.getInstance();
      expect(sp.getKeys().where((k) => k.startsWith(kSlotPrefix)), isEmpty, reason: '되돌린 칸은 지웁니다');
      /* 로그아웃하면 그 계정 칸 하나로(같은 id 의 칸이 둘로 갈라지지 않게) */
      await r.api.signOut();
      expect(sp.getKeys().where((k) => k.startsWith(kSlotPrefix) && k.endsWith('.state')).toList(),
          ['$kSlotPrefix$_server|u_a.state']);
    });

    test('N9 · 기록 칸의 주인 서명 — 떼면 기록이 글자 그대로이고, 기록 · 내보내기 · 동기화 사본에는 안 들어간다', () async {
      final r = await Rig.boot(server, prefs: _deviceOfA(), signedInAs: 'a');
      addTearDown(r.dispose);
      r.app.store.addScan({'id': 'scan-1759000000000', 'weightKg': 86.0, 'smmKg': 38.0, 'bfmKg': 19.5,
          'measuredAt': '2026-09-27T00:00:00.000Z'});
      await settle();
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString('mybody.state.v1')!;
      expect(raw, contains(',"$kStateOwnerField":{'), reason: '기록과 한 번의 쓰기로');
      expect(r.app.state.containsKey(kStateOwnerField), isFalse);
      expect(r.app.store.exportJSON(), isNot(contains(kStateOwnerField)));
      final again = PrefsStorage(sp);
      expect(again.read(), jsonEncode(r.app.store.get()), reason: '떼면 코어가 적은 글자 그대로');
      expect((again.stampedOwner as Map)['uid'], 'u_a');
      await r.cloud.syncNow();
      expect(jsonEncode(server.user('a').state), isNot(contains(kStateOwnerField)));
      /* 서명처럼 보이는 안쪽 칸은 건드리지 않습니다. */
      const nested = '{"version":1,"a":{"x":1,"$kStateOwnerField":{"uid":"u_z"}}}';
      await sp.setString('mybody.state.v1', nested);
      final odd = PrefsStorage(sp);
      expect(odd.read(), nested);
      expect(odd.stampedOwner, isNull);
    });

    test('N9 · 서명과 주인 칸이 어긋난 채 로그아웃돼 있으면 — 서명의 계정 칸으로 치우지 않고 「모름」(계정 지우기 도중 멈춘 기기도 이 모양)', () async {
      final st = jsonEncode({...core.Store.blank(), ...recordsOfA()});
      final stamped = '${st.substring(0, st.length - 1)},"$kStateOwnerField":{"server":"$_server","uid":"u_a"}}';
      final r = await Rig.boot(server, prefs: {'mybody.state.v1': stamped, kOwnerKey: '{}'});
      addTearDown(r.dispose);
      expect(r.app.owner.current?.unknown, isTrue, reason: '「로그인 없이 쓴 기록」 으로 묻지 않고 경고와 함께');
      expect(r.scanIds, [aScan], reason: '기록은 그대로 — 없는 계정일 수 있는 칸으로 치우지 않음');
      final sp = await SharedPreferences.getInstance();
      expect(sp.getKeys().where((k) => k.startsWith(kSlotPrefix)), isEmpty);
      server.add('b');
      LocalRecords? asked;
      await r.api.signIn(handle: 'b', password: 'pw', askMerge: (s) async {
        asked = s;
        return false;
      });
      await settle();
      expect(asked?.unknown, isTrue);
      expect(server.writesTo('b'), isEmpty);
    });

    test('N9 · 웹 두 탭 — 탭2 가 A→B 로 바꾼 뒤 탭1(A 를 든 채)이 저장해도, 다시 켜면 A 의 기록은 A 칸으로 · B 로 안 샌다', () async {
      final r = await Rig.boot(server, prefs: _deviceOfA(), signedInAs: 'a');
      /* 탭1 — 같은 저장소(localStorage)를 보는 또 한 벌. A 의 기록과 주인을 메모리에 든 채 남습니다. */
      final tab1 = await AppState.boot();
      expect(tab1.owner.current?.uid, 'u_a');
      await r.api.signOut();
      await signUpB(r);
      expect(r.app.owner.current?.uid, 'u_b');
      /* 탭1 이 A 의 기록에 하나 더 적고 저장 — 같은 칸('mybody.state.v1')에. */
      tab1.store.addScan({'id': 'scan-tab1', 'weightKg': 86.2, 'smmKg': 38.0, 'bfmKg': 19.9,
          'measuredAt': '2026-09-27T00:00:00.000Z'});
      await settle();
      final sp = await SharedPreferences.getInstance();
      final prefs = <String, Object>{for (final k in sp.getKeys()) k: sp.get(k)!};
      r.dispose();
      /* 탭2 를 다시 켬 — 토큰 · 주인 칸은 B, 기록 칸은 탭1 이 쓴 A 의 것. */
      final r2 = await Rig.boot(server, prefs: prefs);
      addTearDown(r2.dispose);
      expect(r2.api.signedIn, isTrue);
      await r2.cloud.syncNow();
      r2.app.store.setSchedulePlan(r2.app.store.dayKey(), 'gym', true);
      await settle();
      expect(server.user('b').scanIds, isNot(contains(aScan)), reason: 'A 의 기록이 B 서버로');
      expect(server.user('b').snapshots.where((s) => '$s'.contains('86.')), isEmpty, reason: 'A 의 요약이 B 로');
      expect(r2.scanIds, isNot(contains(aScan)), reason: 'B 의 화면에 A 의 기록');
      /* A 로 돌아오면 탭1 이 마지막에 쓴 것까지 */
      await r2.api.signOut();
      await r2.api.signIn(handle: 'a', password: 'pw');
      await settle();
      expect(r2.scanIds, containsAll([aScan, 'scan-tab1']));
    });
  });

  /* 4차 검토 — 2차 수정(3차 검토 N1 · N5 · N4b · N4 · N9)을 검토한 지적. */
  group('4차 검토', () {
    const aScan = 'scan-1758240000000';

    void phone(WidgetTester t) {
      t.view.physicalSize = const Size(1000, 3200);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
    }

    Future<void> signUpB(Rig r) async {
      final res = await r.api.signUp(handle: 'b', password: 'pw12345678', displayName: 'b',
          healthConsent: kHealthConsentVersion, askMerge: (_) async => fail('빈 기록이면 묻지 않습니다'));
      expect(res.ok, isTrue, reason: res.reason);
    }

    /* 친구 탭의 [수락] · [거절] 은 서버에 먼저 보내 보고(기다림 — 최대 20초) 못 닿으면 큐에 맡깁니다.
       예전엔 맡기는 순간의 로그인으로 주인을 적어, 그 기다림 사이 로그아웃 → B 가입이 끼면 A 의 수락이
       B 명의로 나갔습니다 — u_f 가 B 에게도 요청해 두었으면 B 가 모르는 사이 친구가 맺어지고 B 의 기본
       공유가 나갑니다. */
    for (final (label, path) in [('수락', '/friends/accept'), ('거절', '/friends/decline')]) {
      testWidgets('친구 요청 [$label] 이 느린 망에 걸린 사이 로그아웃 → B 가입 — 실패해 큐에 실려도 B 명의로 안 나가고, A 로 돌아오면 A 로 나간다', (t) async {
        phone(t);
        server.user('a').incoming.add({'id': 'u_f', 'displayName': '에프'});
        final r = await Rig.boot(server, prefs: _deviceOfA(), signedInAs: 'a');
        await t.pumpWidget(r.host(Scaffold(body: SocialScreen(go: (_, [__]) {}))));
        await t.pumpAndSettle();
        final held = server.holds['POST $path'] = Completer<int?>();
        await t.tap(find.text(label));
        await t.pump();
        /* 셸이 로그인 화면으로 바꾸듯 친구 탭을 내립니다. */
        await t.pumpWidget(r.host(const SizedBox()));
        await r.api.signOut();
        await signUpB(r);
        await t.pumpAndSettle();
        held.complete(503);   // 느린 망 끝에 실패 — 다시 보낼 만한 실패라 큐에 맡깁니다
        await t.pumpAndSettle();
        expect([for (final c in server.calls) if (c.startsWith('POST $path') && c.endsWith('@u_b')) c], isEmpty,
            reason: 'A 의 [$label] 이 B 명의로');
        server.calls.clear();
        await r.api.signOut();
        await r.api.signIn(handle: 'a', password: 'pw');
        await t.pumpAndSettle();
        expect(server.calls, contains('POST $path @u_a'), reason: 'A 의 일은 A 로 돌아왔을 때');
        r.dispose();
      });
    }

    /* 친구 상세의 공유 스위치도 같은 길. 예전엔 화면이 떠 있으면 맡기는 순간의 로그인(B)으로 적혔고,
       화면이 내려갔으면 아예 맡기지 않아 A 의 공유 끄기가 사라졌습니다(큐 머리 주석: 프라이버시
       스위치가 조용히 안 먹는 것이 제일 나쁜 고장). */
    for (final stays in [true, false]) {
      testWidgets('친구 상세 공유 스위치가 느린 망에 걸린 사이 로그아웃 → B 가입(화면 ${stays ? '떠 있음' : '내려감'}) — B 명의로 안 나가고, A 로 돌아오면 A 로 나간다', (t) async {
        phone(t);
        final r = await Rig.boot(server, prefs: _deviceOfA(), signedInAs: 'a');
        await t.pumpWidget(r.host(const FriendDetailScreen(person: {'id': 'f1', 'displayName': '나린'})));
        await t.pumpAndSettle();
        await t.tap(find.text('내가 이 친구에게 보여 주는 것'));
        await t.pumpAndSettle();
        final held = server.holds['PUT /share/f1'] = Completer<int?>();
        await t.tap(find.widgetWithText(SwitchListTile, '오늘 식단 (칼로리·탄단지)'));
        await t.pump();
        if (!stays) await t.pumpWidget(r.host(const SizedBox()));
        await r.api.signOut();
        await signUpB(r);
        await t.pumpAndSettle();
        held.complete(503);
        await t.pumpAndSettle();
        expect([for (final c in server.calls) if (c.startsWith('PUT /share/') && c.endsWith('@u_b')) c], isEmpty,
            reason: 'A 의 공유 스위치가 B 명의로');
        server.calls.clear();
        await r.api.signOut();
        await r.api.signIn(handle: 'a', password: 'pw');
        await t.pumpAndSettle();
        expect(server.calls, contains('PUT /share/f1 @u_a'), reason: 'A 의 공유 스위치가 사라짐');
        r.dispose();
      });
    }

    /* 설정에서 서버 주소를 다른 서버로 바꾸면(main.dart _setServer — 새 Api 가 같은 토큰으로) 새 큐가 곧
       밀어 봅니다. 예전엔 큐가 일을 맡긴 서버를 안 봐서 A 의 기록 사본(본문째)과 공유 끄기가 그 서버로
       갔고, 그 서버의 401 을 "다시 보내도 같은 답" 으로 보고 버렸습니다 — 공유 끄기는 원래 서버에
       영영 안 감. */
    test('서버 주소를 다른 서버로 바꾸면 — 큐의 A 일(기록 사본 · 공유 끄기)을 그 서버로 안 보내고 버리지도 않는다 · 원래 주소로 돌아오면 A 로 나간다', () async {
      final r = await Rig.boot(server, prefs: _deviceOfA(), signedInAs: 'a');
      final sp = await SharedPreferences.getInstance();
      server.failWrites = true;
      r.queue.add('setShare', {'userId': 'f1', 'patch': {'diet': false}});
      r.app.store.addScan({'id': 'scan-new', 'weightKg': 86.0, 'smmKg': 38.0, 'bfmKg': 19.5,
          'measuredAt': '2026-09-27T00:00:00.000Z'});
      await r.cloud.syncNow();
      await settle();
      List<String> ops() => [
            for (final j in jsonDecode(sp.getString('mybody.sync.queue.v1') ?? '[]') as List) '${(j as Map)['op']}'
          ];
      expect(ops(), containsAll(['setShare', 'syncState']), reason: '시험의 전제 — 못 보낸 A 의 일');
      server.failWrites = false;
      /* main.dart _setServer 처럼 — 옛 큐 · 동기화는 내리고 새 주소의 것을 꽂습니다. */
      var queue = r.queue;
      var cloud = r.cloud;
      addTearDown(() {
        queue
          ..clear()
          ..dispose();
        cloud.dispose();
      });
      Future<void> setServer(String base, FakeAccounts srv) async {
        queue.dispose();
        cloud.dispose();
        final api = Api(baseUrl: base, client: srv.client);
        await api.loadToken();
        api.accounts = r.slots;
        queue = SyncQueue(api: api, storage: PrefsQueue(sp));
        r.slots.queue = queue;
        wirePublishing(r.app, api, queue);
        cloud = CloudSync(app: r.app, api: api, queue: queue)..wire();
        r.slots.cloud = cloud;
        unawaited(queue.flush());
        unawaited(cloud.pull());
        await settle(300);
      }

      final elsewhere = FakeAccounts()..add('a');   // 같은 아이디가 있어도 다른 서버 — 이 토큰을 모름
      await setServer('https://elsewhere.test', elsewhere);
      expect([for (final c in elsewhere.calls) if (!c.startsWith('GET ')) c], isEmpty,
          reason: 'A 의 일이 다른 서버로');
      expect(ops(), containsAll(['setShare', 'syncState']), reason: '401 이라고 버리면 원래 서버에 영영 안 감');
      await setServer(_server, server);
      expect(server.calls, contains('PUT /share/f1 @u_a'));
      expect(server.user('a').scanIds, contains('scan-new'));
    });

    test('앱에 박힌 주소만 바뀐 판(같은 서버)이면 — 큐의 앞 주소 일도 이 주소의 서버에 계정을 확인한 뒤 나간다', () async {
      const moved = 'https://new-host.test';
      final tok = server.login('a');
      final r = await Rig.boot(server, prefs: {
        ..._deviceOfA(),
        'mybody.token.v1': tok,
        'mybody.sync.queue.v1': jsonEncode([
          {'op': 'setShare', 'args': {'userId': 'f1', 'patch': {'diet': false}}, 'at': 1,
           'owner': 'u_a', 'sess': Api.sessionTagOf(tok), 'srv': _server},
        ]),
      }, base: moved);
      addTearDown(r.dispose);
      await r.queue.flush();
      await settle();
      expect(server.calls, containsAllInOrder(['GET /me @u_a', 'PUT /share/f1 @u_a']));
    });

    /* 3차 검토 N9 의 되돌리기(켤 때 서명으로 주인이 A 로 갈린 기록을 A 칸으로)가 곁의 기기 칸(기준본 · 시각 ·
       독촉 · 소식 · 초대 표시)까지 A 칸에 실었습니다. 그 칸들은 지금 로그인 B 의 탭이 적은 것이라, B 의 독촉 ·
       초대 코드가 A 로 가고(A 로 돌아오면 A 의 초대 링크로 B 의 코드가 나감), A 칸의 기준본이 B 의 것으로
       덮여 A 의 다른 기기가 서버에서 고친 값이 되돌아갔습니다. B 는 곁의 칸을 다 잃었습니다. */
    test('N9 되돌리기 — 곁의 기기 칸은 A 칸에 안 싣는다: A 의 기준본이 남아 서버에서 고친 값이 안 되돌아가고, B 의 독촉 · 초대 표시는 B 에게', () async {
      final r = await Rig.boot(server, prefs: _deviceOfA(), signedInAs: 'a');
      expect(await r.cloud.syncNow(), 'pushed', reason: '시험의 전제 — A 의 기준본');
      final tab1 = await AppState.boot();
      /* A 의 다른 기기가 서버의 값을 고침 — (1) 키: 탭2 가 로그아웃하며 받아 옴(탭1 의 메모리는 옛 값),
         (2) 목표: 로그아웃한 뒤(A 칸의 기준본만이 "A 는 안 바꿨다" 를 압니다). */
      Future<void> onServer(String field, String key, Object value) async {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        final a = server.user('a');
        a
          ..state = {...a.state!, field: {...(a.state![field] as Map), key: value}}
          ..at = isoNow();
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      await onServer('profile', 'heightCm', 180);
      await r.api.signOut();
      await onServer('goal', 'weightKg', 78.0);
      await signUpB(r);
      await settle();
      final sp = await SharedPreferences.getInstance();
      /* B 가 쓰기 시작 — 기록 · 동기화(B 의 기준본) · 초대 코드 · 친구의 독촉 */
      r.app.store.set({'onboarded': true});
      r.app.store.addScan({'id': 'bx', 'weightKg': 60.0, 'smmKg': 25.0, 'bfmKg': 15.0,
          'measuredAt': '2026-09-27T00:00:00.000Z'});
      expect(await r.cloud.syncNow(), 'pushed');
      await sp.setString(kMyInviteCodeKey, 'CODE-OF-B');
      server.user('b').pokes.add({'id': 9, 'kind': 'workout', 'at': isoNow(),
          'from': {'id': 'u_bf', 'displayName': 'B친구'}});
      await r.app.pokes!.fetch(r.api);
      /* 탭1(A 를 든 채)이 저장 */
      tab1.store.addScan({'id': 'scan-tab1', 'weightKg': 86.2, 'smmKg': 38.0, 'bfmKg': 19.9,
          'measuredAt': '2026-09-27T00:00:00.000Z'});
      await settle();
      final prefs = <String, Object>{for (final k in sp.getKeys()) k: sp.get(k)!};
      r.dispose();
      final r2 = await Rig.boot(server, prefs: prefs);
      addTearDown(r2.dispose);
      final sp2 = await SharedPreferences.getInstance();
      final aBase = jsonDecode(sp2.getString(_slot('u_a', 'cloud.base')) ?? '{}') as Map;
      expect(aBase['uid'], 'u_a', reason: 'A 칸의 기준본이 B 의 것으로');
      expect(sp2.getString(_slot('u_a', 'invite.mine')), isNot('CODE-OF-B'));
      expect(sp2.getString(_slot('u_a', 'pokes')) ?? '', isNot(contains('B친구')));
      /* B 는 제 것을 잃지 않음. 기준본만 버림 — 빈 기록에 B 의 기준본이면 B 서버 사본을 "다 지움" 으로 읽음. */
      expect(sp2.getString(kMyInviteCodeKey), 'CODE-OF-B');
      expect(r2.app.pokes!.items.single['name'], 'B친구');
      expect(sp2.getString(CloudSync.keyBase), isNull);
      await r2.cloud.syncNow();
      expect(r2.scanIds, ['bx'], reason: 'B 의 기록은 B 서버 사본에서');
      expect(server.user('b').scanIds, ['bx']);
      /* A 로 돌아오면 — 탭1 이 마지막에 쓴 것까지, B 의 것은 없이 */
      await r2.api.signOut();
      await r2.api.signIn(handle: 'a', password: 'pw');
      await settle();
      expect(r2.scanIds, containsAll([aScan, 'scan-tab1']));
      expect(sp2.getString(kMyInviteCodeKey), isNot('CODE-OF-B'), reason: 'A 의 초대 링크로 B 의 코드가');
      expect(r2.app.pokes!.items.where((p) => p['name'] == 'B친구'), isEmpty);
      await r2.cloud.syncNow();
      expect((server.user('a').state!['profile'] as Map)['heightCm'], 180,
          reason: '탭1 메모리의 옛 키가 로그아웃 때 받아 둔 값을 이김');
      expect((server.user('a').state!['goal'] as Map)['weightKg'], 78.0,
          reason: 'A 칸의 기준본이 B 의 것으로 덮여, A 의 다른 기기가 고친 목표가 되돌아감');
      expect(server.user('a').scanIds, containsAll([aScan, 'scan-tab1']));
    });

    /* 3차 검토 N4b 는 동기화가 /me 로 서버에 계정을 확인했는데, 동기화를 끈 사람은 그 앞에서 'off' 로
       돌아가 확인이 없었습니다 — 앱에 박힌 주소만 바뀐 판에서 그 사람의 주간 요약이 조용히 멈춤. */
    test('N4b · 동기화를 끈 사람도 — 앱에 박힌 주소만 바뀐 판에서 주간 요약이 다시 나간다(기록 사본은 안 나감)', () async {
      const moved = 'https://new-host.test';
      final r = await Rig.boot(server, prefs: _deviceOfA(syncOff: true), signedInAs: 'a', base: moved);
      addTearDown(r.dispose);
      expect(await r.cloud.syncNow(), 'off');
      r.app.store.setSchedulePlan(r.app.store.dayKey(), 'gym', true);
      await settle();
      expect(server.user('a').snapshots, isNotEmpty, reason: '주간 요약이 멈춤');
      expect(r.app.owner.current?.server, moved);
      expect(server.user('a').state, isNull, reason: '동기화를 끈 사람의 기록 사본');
    });

    /* 로그아웃이 토큰과 계정 id 열쇠를 지우는 사이, 다음 로그인이 토큰과 id 를 적는 사이 앱이 죽으면(두 번)
       토큰은 B · id 열쇠는 A 로 남습니다. 예전엔 켤 때 그 낡은 id 를 믿어, B 의 칸을 치우고 A 의 치워 둔
       칸을 B 토큰 아래 열었고 — A 의 공유 끄기가 B 명의로 나갔습니다. */
    test('id 열쇠만 낡은 기기(토큰은 B · id 는 A) — A 의 칸을 B 토큰 아래 열지 않고, A 의 일 · B 의 기록이 섞이지 않는다', () async {
      server.add('b');
      final tokB = server.login('b');
      final ownerB = LocalOwner(server: _server, uid: 'u_b', sess: Api.sessionTagOf(tokB));
      final bState = jsonEncode({...core.Store.blank(), 'onboarded': true, 'scans': [
        {'id': 'bscan', 'weightKg': 60.0, 'smmKg': 25.0, 'bfmKg': 15.0, 'measuredAt': '2026-09-27T00:00:00.000Z'},
      ]});
      final r = await Rig.boot(server, prefs: {
        'mybody.token.v1': tokB,
        'mybody.token.uid.v1': 'u_a',
        'mybody.state.v1': withOwnerStamp(bState, ownerB),
        kOwnerKey: jsonEncode(ownerB.toJson()),
        _slot('u_a', 'state'): jsonEncode({...core.Store.blank(), ...recordsOfA()}),
        _slot('u_a', 'owner'): jsonEncode({'server': _server, 'uid': 'u_a'}),
        _slot('u_a', 'queue'): jsonEncode([
          {'op': 'setShare', 'args': {'userId': 'f1', 'patch': {'diet': false}}, 'at': 1, 'owner': 'u_a'},
        ]),
      });
      addTearDown(r.dispose);
      await r.queue.flush();
      await settle();
      expect(r.scanIds, ['bscan'], reason: 'B 토큰 아래 A 의 칸이 열림');
      expect([for (final c in server.calls) if (c.contains('/share/') && c.endsWith('@u_b')) c], isEmpty);
      expect(await r.cloud.syncNow(), isNot('owner'), reason: 'B 의 기록은 B 의 것 — 멈추면 안 됨');
      expect(server.user('b').scanIds, ['bscan']);
      await r.api.signOut();
      final sp = await SharedPreferences.getInstance();
      expect(sp.getString(_slot('u_b', 'state')) ?? '', contains('bscan'), reason: 'B 의 기록은 B 의 칸으로');
      expect(sp.getString(_slot('u_a', 'state')) ?? '', isNot(contains('bscan')), reason: 'B 의 기록이 A 의 칸으로');
      await r.api.signIn(handle: 'a', password: 'pw');
      await settle();
      expect(r.scanIds, [aScan]);
      expect(server.calls, contains('PUT /share/f1 @u_a'));
    });

    /* 공격(4차): 서버 주소를 바꾼 곳의 서버가 이 토큰을 **다른 계정**이라 말하면(다른 서버가 같은 토큰
       글자를 받아 줌 · 흉내 내는 서버) 지금 Api 의 id 가 그 계정이 됩니다. 예전엔 로그아웃이 그 id 로
       칸 이름을 지어, 이 기록(B)이 그 계정(A)의 치워 둔 칸에 합쳐져 A 가 로그인하면 B 의 측정이 보였습니다. */
    test('주소를 바꾼 곳의 서버가 이 토큰을 다른 계정(A)이라 말해도 — 로그아웃은 칸 주인(B)의 칸으로 치운다', () async {
      const tok = 'tok-of-b-at-other';
      server.tokens[tok] = 'u_a';   // 이 주소의 서버는 이 토큰을 A 로 앎
      final ownerB = LocalOwner(server: 'https://other.test', uid: 'u_b', sess: Api.sessionTagOf(tok));
      final bState = jsonEncode({...core.Store.blank(), 'onboarded': true, 'scans': [
        {'id': 'bscan', 'weightKg': 60.0, 'smmKg': 25.0, 'bfmKg': 15.0, 'measuredAt': '2026-09-27T00:00:00.000Z'},
      ]});
      final r = await Rig.boot(server, prefs: {
        'mybody.token.v1': tok,
        'mybody.token.uid.v1': Api.uidRecordOf(tok, 'u_b'),
        'mybody.state.v1': withOwnerStamp(bState, ownerB),
        kOwnerKey: jsonEncode(ownerB.toJson()),
        _slot('u_a', 'state'): jsonEncode({...core.Store.blank(), ...recordsOfA()}),
        _slot('u_a', 'owner'): jsonEncode({'server': _server, 'uid': 'u_a'}),
      });
      addTearDown(r.dispose);
      await r.api.me();
      expect(r.api.userId, 'u_a', reason: '시험의 전제 — 이 주소의 서버가 A 라 말함');
      expect(await r.cloud.syncNow(), 'owner', reason: 'B 의 기록을 A 로 올리지 않음');
      await r.api.signOut();
      final sp = await SharedPreferences.getInstance();
      expect(sp.getString(_slot('u_a', 'state')) ?? '', isNot(contains('bscan')), reason: 'B 의 기록이 A 의 칸으로');
      expect(sp.getString(_slot2('https://other.test', 'u_b', 'state')) ?? '', contains('bscan'));
      await r.api.signIn(handle: 'a', password: 'pw');
      await settle();
      expect(r.scanIds, [aScan]);
      expect(jsonEncode(server.user('a').state), isNot(contains('bscan')));
    });

    /* 3차 검토 N1 의 대가 — 계정 id 를 끝내 모른 채 로그아웃하면 그 로그인의 못 보낸 일은 버립니다(누구의
       일인지 다시는 모름). 예전엔 창이 「다시 로그인할 때 보내요」 라고만 말해, 공유 끄기가 사라져도
       껐다고 믿었습니다. */
    testWidgets('계정 id 를 모르는 로그인(0.2.19 에서 올라와 서버에 못 닿음)의 로그아웃 창 — 못 보낸 일이 사라질 수 있다고 말한다', (t) async {
      phone(t);
      server.down = true;
      final r = await Rig.boot(server, prefs: {
        'mybody.state.v1': jsonEncode({...core.Store.blank(), ...recordsOfA()}),
      }, signedInAs: 'a', withUid: false);
      r.queue.add('setShare', {'userId': 'f1', 'patch': {'diet': false}});
      await t.pumpWidget(r.host(AccountScreen(api: r.api, onServerChange: (_) async {})));
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('로그아웃'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('settings-logout-unsent-lost')), findsOneWidget);
      await t.tap(find.byKey(const Key('settings-logout-cancel')));
      await t.pumpAndSettle();
      r.dispose();
    });

    testWidgets('계정 id 를 아는 로그인의 로그아웃 창 — 사라진다고 겁주지 않는다', (t) async {
      phone(t);
      server.failWrites = true;
      final r = await Rig.boot(server, prefs: _deviceOfA(), signedInAs: 'a');
      r.queue.add('setShare', {'userId': 'f1', 'patch': {'diet': false}});
      await t.pumpWidget(r.host(AccountScreen(api: r.api, onServerChange: (_) async {})));
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('로그아웃'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('settings-logout-unsent')), findsOneWidget);
      expect(find.byKey(const Key('settings-logout-unsent-lost')), findsNothing);
      await t.tap(find.byKey(const Key('settings-logout-cancel')));
      await t.pumpAndSettle();
      r.dispose();
    });

    /* 주인이 바뀌면 기록 칸의 서명만 다시 적습니다(3차 검토 N9). 그 쓰기가 한 번 실패하면(저장 공간) 예전엔
       '마지막 쓰기 실패' 가 영영 켜져, 다음 저장부터 모두 실패했고 — 코어는 자리를 만든다며 결과지 사진을
       하나씩 지웠습니다. 서명만 못 적은 것은 기록을 못 적은 것이 아닙니다. */
    test('주인 서명만 다시 적다 실패해도(저장 공간) — 다음 저장은 그대로 된다', () async {
      final r = await Rig.boot(server, prefs: _deviceOfA(), signedInAs: 'a');
      addTearDown(r.dispose);
      final now = await SharedPreferencesStorePlatform.instance.getAll();
      final disk = _FailOnceDisk(Map<String, Object>.of(now))..failKey = core.storeKey;
      SharedPreferencesStorePlatform.instance = disk;
      r.app.owner.set(r.app.owner.current!.copyWith(handle: 'a2'));   // 서명만 다시 적음
      await settle();
      expect(disk.failed, isTrue, reason: '시험의 전제 — 서명 쓰기가 실패');
      r.app.store.addScan({'id': 'scan-after', 'weightKg': 86.0, 'smmKg': 38.0, 'bfmKg': 19.5,
          'measuredAt': '2026-09-27T00:00:00.000Z'});
      expect(r.app.store.saved(), isTrue);
      await settle();
      final all = await SharedPreferencesStorePlatform.instance.getAll();
      expect('${all['flutter.${core.storeKey}']}', contains('scan-after'));
    });
  });
}
