/* =============================================================================
 * account_switch_crash_test.dart — 칸을 갈아 끼우는 **도중에** 앱이 죽거나 저장이 실패하면 (피드백 52)
 *
 * 칸 바꾸기는 기기 저장소(SharedPreferences)에 여러 번 나눠 씁니다 — 주인 · 기록 · 기준본 · 큐 ·
 * 토큰. 한 번에 끝나지 않으니, 그 사이 어디서 앱이 죽어도(배터리 · 강제 종료) 다음에 켰을 때
 * 두 가지가 지켜져야 합니다(local_owner.dart 「칸 바꾸기의 차례」):
 *   · 다른 계정으로 새지 않는다 — 누구 것인지 모르게 된 기록은 경고와 함께 묻고, 말없이 안 올린다.
 *   · 잃지 않는다 — 치워 둔 칸 · 못 보낸 변경이 어느 칸에든 남는다.
 *
 * 방법: 기기 저장소를 흉내 낸 것([_Disk])이 쓰기를 차례로 적습니다. 한 번 끝까지 돌려 쓰기 수를
 * 센 뒤, 매 자리(0 ~ 끝)에서 "여기까지만 적히고 죽었다" 를 만들어 새로 켜고, 사람이 할 법한 다음
 * 일(다른 계정 가입 · 원래 계정으로 다시 로그인)을 해 봅니다. 저장소가 어느 칸 쓰기에서 실패하는
 * 경우(웹의 저장 공간이 꽉 참)도 따로 봅니다 — 로그인을 멈추고 치워 둔 칸을 그대로 둬야 합니다.
 * ========================================================================== */
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mybody/src/local_owner.dart';
import 'package:mybody/src/screens/account.dart' show kHealthConsentVersion;
import 'package:mybody_core/mybody_core.dart' as core;
import 'package:shared_preferences/shared_preferences.dart';
// 기기 저장소를 흉내 내려면 플랫폼 쪽 틀이 필요합니다(shared_preferences 가 딸고 오는 것).
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'fake_accounts.dart';

const _server = 'https://x.test';
const _aScan = 'scan-1758240000000';
const _p = 'flutter.';

/// 쓰기를 차례로 적는 기기 저장소. [failOn] 이 참인 열쇠는 쓰다 실패합니다(자리가 없음).
class _Disk extends InMemorySharedPreferencesStore {
  _Disk(super.data) : super.withData();
  final log = <(String, Object?)>[];
  bool Function(String key)? failOn;

  @override
  Future<bool> setValue(String valueType, String key, Object value) {
    if (failOn?.call(key.substring(_p.length)) ?? false) {
      return Future.error(StateError('저장 공간이 없습니다: $key'));
    }
    log.add((key, value));
    return super.setValue(valueType, key, value);
  }

  @override
  Future<bool> remove(String key) {
    log.add((key, null));
    return super.remove(key);
  }
}

/// 켜 둔 기기의 저장소를 [_Disk] 로 바꿉니다(지금 들어 있는 것 그대로). 돌려주는 것은 그때의 모습.
Future<(_Disk, Map<String, Object>)> _record() async {
  final now = await SharedPreferencesStorePlatform.instance.getAll();
  final disk = _Disk(Map<String, Object>.of(now));
  SharedPreferencesStorePlatform.instance = disk;
  return (disk, Map<String, Object>.of(now));
}

/// [before] 에 쓰기 [n] 개만 적힌 기기 — 앞머리('flutter.')는 떼서 [Rig.boot] 에 넘깁니다.
Map<String, Object> _cut(Map<String, Object> before, List<(String, Object?)> log, int n) {
  final d = Map<String, Object>.of(before);
  for (final (k, v) in log.take(n)) {
    if (v == null) {
      d.remove(k);
    } else {
      d[k] = v;
    }
  }
  return {for (final e in d.entries) e.key.substring(_p.length): e.value};
}

/// A 가 쓰던 기기 — **동기화를 꺼 둬서** 이 기기가 유일본입니다(잃으면 되찾을 곳이 없음).
Map<String, Object> _deviceOfA() {
  final a = recordsOfA();
  return {
    'mybody.state.v1': jsonEncode({
      ...core.Store.blank(), ...a,
      'settings': {...(a['settings'] as Map), 'cloudSync': false},
    }),
    kOwnerKey: jsonEncode({'server': _server, 'uid': 'u_a'}),
  };
}

bool _hasA(Rig r) => r.scanIds.contains(_aScan);

/// 켠 뒤 사람이 할 법한 다음 일 — 로그인돼 있으면 로그아웃, 다른 계정 B 가입(A 의 기록을 경고 없이
/// 묻거나 B 로 올리면 실패), B 로그아웃, A 로그인(묻거나 말거나 내 것이면 합침) → A 의 측정이 있어야 함.
Future<void> _nextDay(FakeAccounts server, Rig r, String at) async {
  if (r.api.signedIn) {
    await r.api.signOut();
    await settle(20);
  }
  final b = await r.api.signUp(handle: 'b', password: 'pw12345678', displayName: 'b',
      healthConsent: kHealthConsentVersion, askMerge: (s) async {
    expect(!_hasA(r) || s.unknown, isTrue, reason: '$at: A 의 기록을 경고 없이 「로그인 없이 쓴 기록」 으로 물었습니다');
    return false;
  });
  expect(b.ok, isTrue, reason: '$at: ${b.reason}');
  await settle(20);
  expect(server.user('b').scanIds, isNot(contains(_aScan)), reason: '$at: A 의 측정이 B 로 올라갔습니다');
  expect(server.user('b').snapshots.where((s) => s['weightKg'] == 86.7), isEmpty,
      reason: '$at: A 의 요약이 B 로 올라갔습니다');
  await r.api.signOut();
  await settle(20);
  final a = await r.api.signIn(handle: 'a', password: 'pw', askMerge: (_) async => true);
  expect(a.ok, isTrue, reason: '$at: ${a.reason}');
  await settle(20);
  if (!_hasA(r)) {
    /* 경고와 함께 [합치지 않기] 로 손님 칸에 들어갔을 수 있습니다 — 로그아웃하면 돌아옵니다. */
    await r.api.signOut();
    await settle(20);
  }
  expect(_hasA(r), isTrue, reason: '$at: A 의 기록을 잃었습니다');
}

/// 한 번 끝까지 돌려 쓰기를 적고, 매 자리에서 죽은 기기로 [_nextDay].
Future<void> _sweep(String name, Future<(FakeAccounts, Rig)> Function() setup,
    Future<void> Function(FakeAccounts s, Rig r) op) async {
  Future<(Map<String, Object>, List<(String, Object?)>, FakeAccounts)> once() async {
    final (server, r) = await setup();
    final (disk, before) = await _record();
    await op(server, r);
    await settle(20);
    r.dispose();
    await settle(20);
    return (before, List.of(disk.log), server);
  }

  final (_, log, _) = await once();
  expect(log, isNotEmpty);
  for (var n = 0; n <= log.length; n++) {
    final (before, l, server) = await once();
    final at = '$name — 쓰기 $n/${l.length}번째에서 멈춤${n < l.length ? ' (${l[n].$1})' : ''}';
    final r = await Rig.boot(server, prefs: _cut(before, l, n));
    try {
      await _nextDay(server, r, at);
    } finally {
      r.dispose();
      await settle(20);
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('로그아웃하는 도중에 죽어도 — 새지 않고 잃지 않는다', () async {
    await _sweep('로그아웃', () async {
      final server = FakeAccounts()..add('a');
      final r = await Rig.boot(server, prefs: _deviceOfA(), signedInAs: 'a');
      return (server, r);
    }, (_, r) => r.api.signOut());
  });

  test('치워 둔 A 칸을 되돌리는(로그인) 도중에 죽어도', () async {
    await _sweep('A 로그인', () async {
      final server = FakeAccounts()..add('a');
      final r = await Rig.boot(server, prefs: _deviceOfA(), signedInAs: 'a');
      await r.api.signOut();
      await settle(20);
      return (server, r);
    }, (_, r) => r.api.signIn(handle: 'a', password: 'pw'));
  });

  test('주인 모르는 기록으로 다른 계정에 들어가며 [합치지 않기] 하는 도중에 죽어도', () async {
    await _sweep('모르는 기록 → C [합치지 않기]', () async {
      final server = FakeAccounts()
        ..add('a')
        ..add('c');
      final r = await Rig.boot(server, prefs: {
        ..._deviceOfA(),
        kOwnerKey: jsonEncode({'unknown': true}),
      });
      return (server, r);
    }, (_, r) => r.api.signIn(handle: 'c', password: 'pw', askMerge: (_) async => false));
  });

  test('로그인 없이 쓴 기록을 치워 둔 A 칸과 합치는([합치기]) 도중에 죽어도', () async {
    await _sweep('손님 기록 → A [합치기]', () async {
      final server = FakeAccounts()..add('a');
      final r = await Rig.boot(server, prefs: _deviceOfA(), signedInAs: 'a');
      await r.api.signOut();
      await settle(20);
      r.app.store.set({'onboarded': true, 'guest': true});
      r.app.store.addScan({'id': 'scan-1759000000000', 'weightKg': 70.0, 'smmKg': 30.0, 'bfmKg': 15.0,
          'measuredAt': '2026-09-27T00:00:00.000Z'});
      await settle(20);
      return (server, r);
    }, (_, r) => r.api.signIn(handle: 'a', password: 'pw', askMerge: (_) async => true));
  });

  test('되돌리다 저장이 실패하면(자리 없음) 로그인을 멈춘다 — 치워 둔 A 칸 · A 의 서버 사본은 그대로', () async {
    /* 동기화를 켠 A — 서버에 사본이 있습니다. 예전엔 기준본만 못 적힌 채 로그인이 진행돼, 빈 칸이
       A 의 칸이 되고 3-way 합치기가 "전부 지웠다" 로 읽어 A 의 서버 사본까지 비웠습니다. */
    final server = FakeAccounts()..add('a');
    final r = await Rig.boot(server, prefs: {
      'mybody.state.v1': jsonEncode({...core.Store.blank(), ...recordsOfA()}),
      kOwnerKey: jsonEncode({'server': _server, 'uid': 'u_a'}),
    }, signedInAs: 'a');
    addTearDown(r.dispose);
    expect(await r.cloud.syncNow(), 'pushed');
    await r.api.signOut();
    await settle(20);
    final (disk, _) = await _record();
    disk.failOn = (k) => k == 'mybody.cloud.base.v1';
    final res = await r.api.signIn(handle: 'a', password: 'pw');
    await settle();
    expect(res.ok, isFalse, reason: '이 기기에 못 적었으면 로그인을 멈춥니다');
    expect(res.reason, contains('저장'));
    expect(r.api.signedIn, isFalse);
    expect(server.user('a').scanIds, [_aScan], reason: 'A 의 서버 사본을 비우면 안 됩니다');
    final sp = await SharedPreferences.getInstance();
    expect(sp.getString('$kSlotPrefix$_server|u_a.state'), contains('86.7'), reason: '치워 둔 칸은 그대로');

    disk.failOn = null;
    final again = await r.api.signIn(handle: 'a', password: 'pw');
    await settle();
    expect(again.ok, isTrue);
    expect(r.scanIds, [_aScan]);
    expect(server.user('a').scanIds, [_aScan]);
  });
}
