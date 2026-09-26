/* =============================================================================
 * native_push_test.dart — 앱 알림(FCM): 없을 때 조용한가, 있을 때 서버에 제대로 말하는가
 *
 * Firebase 는 폰 없이 못 돌리므로 [PushPlatform] 자리에 가짜를 넣습니다. 여기서 보는 것:
 *   · 설정 파일이 없는 빌드 — 아무 요청도 안 하고, 설정 화면은 「꺼짐」.
 *   · 등록 · 토큰 갱신 · 로그아웃(서버에서 빼기 → 토큰 폐기) · 다시 로그인.
 *   · 아이폰 권한은 한 번만 묻는다. 거절해도 등록은 한다(서버가 크롬으로 대신 보냄).
 *   · 알림의 갈 곳(route) — 모르는 값은 버린다. 앞에 떠 있을 때 안드로이드만 직접 띄운다.
 *   · 앱으로 돌아올 때 독촉을 가져온다(푸시가 없는 사람의 안전망).
 *   · 설정 화면의 「푸시 알림」 줄과 「크롬(웹) 알림 끄기」.
 *   · 구글 등록(FCM 자동 초기화)은 로그인한 뒤에만 · 서버마다 다른 설치 비밀.
 *   · 서버를 바꾸면 옛 서버에서 빼고 토큰을 새로 받는다.
 *   · 같은 독촉이 앱 알림과 가져오기 두 길로 와도 한 번만 띄운다.
 * ========================================================================== */
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mybody/src/api.dart';
import 'package:mybody/src/app_state.dart';
import 'package:mybody/src/native_push.dart';
import 'package:mybody/src/nudge.dart' show notificationRoute;
import 'package:mybody/src/pokes.dart';
import 'package:mybody/src/scope.dart';
import 'package:mybody/src/screens/settings.dart';
import 'package:mybody/src/shell.dart';
import 'package:mybody/src/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Firebase 대신. 토큰은 폐기할 때마다 새 번호가 됩니다.
class FakePush implements PushPlatform {
  FakePush({this.platform = 'android', this.initOk = true, this.perm = PushPermission.granted});

  @override
  final String platform;
  bool initOk;
  PushPermission perm;
  int serial = 1;
  bool noToken = false;
  final asks = <bool>[];
  int deletes = 0;
  /// 자동 초기화를 켜고 끈 차례. 토큰을 받은 때는 'token' 으로 끼워 넣습니다.
  final autoInit = <Object>[];
  final shown = <({int id, String title, String body, String? payload, String? tag})>[];
  final refresh = StreamController<String>.broadcast();
  final fg = StreamController<PushMessage>.broadcast();
  final opened = StreamController<PushMessage>.broadcast();
  PushMessage? initial;

  @override
  bool get systemShowsForeground => platform == 'ios';
  @override
  bool get asksPermission => platform == 'ios';
  @override
  Future<bool> init() async => initOk;
  @override
  Future<PushPermission> permission({required bool ask}) async {
    asks.add(ask);
    return perm;
  }

  @override
  Future<String?> token() async {
    autoInit.add('token');
    return noToken ? null : 'fcm-token-$serial';
  }

  @override
  Future<void> setAutoInit(bool on) async => autoInit.add(on);
  @override
  Future<void> deleteToken() async {
    deletes++;
    serial++;
  }

  @override
  Stream<String> get onTokenRefresh => refresh.stream;
  @override
  Stream<PushMessage> get onForeground => fg.stream;
  @override
  Stream<PushMessage> get onOpened => opened.stream;
  @override
  Future<PushMessage?> initialMessage() async => initial;
  @override
  Future<void> showLocal({required int id, required String title, required String body, String? payload,
      String? tag}) async {
    shown.add((id: id, title: title, body: body, payload: payload, tag: tag));
  }
}

http.Response _json(Object body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status,
        headers: {'content-type': 'application/json; charset=utf-8'});

/// 서버 흉내 — 새 길(/push/*)을 아는 서버와 모르는 옛 서버 둘 다.
class _Server {
  final calls = <String>[];
  final devices = <Map<String, dynamic>>[];
  final deletes = <Map<String, dynamic>>[];
  bool knowsPush = true;
  bool fcm = true;
  int webSubs = 2;
  /// 크롬 구독 지우기가 /push/web 이 아니라 /push/web-subscriptions 인 서버.
  bool webSubscriptionsName = false;

  MockClient get client => MockClient((req) async {
        final p = req.url.path.replaceFirst('/api', '');
        calls.add('${req.method} $p');
        final b = req.body.isEmpty ? <String, dynamic>{} : (jsonDecode(req.body) as Map).cast<String, dynamic>();
        if (p == '/auth/signout' || p == '/auth/signin') return _json({'ok': true, 'token': 'tok2'});
        if (!knowsPush) return _json({'ok': false, 'reason': '없는 길'}, 404);
        if (p == '/push/device' && req.method == 'POST') {
          devices.add(b);
          return _json({'ok': true, 'fcm': fcm});
        }
        if (p == '/push/device' && req.method == 'DELETE') {
          deletes.add(b);
          return _json({'ok': true});
        }
        if (p == '/push/status') {
          return _json({'ok': true, 'fcm': fcm, 'web': true, 'devices': devices.length,
              'webSubs': webSubs, 'webMuted': fcm});
        }
        final webPath = webSubscriptionsName ? '/push/web-subscriptions' : '/push/web';
        if (p == webPath && req.method == 'DELETE') {
          final n = webSubs;
          webSubs = 0;
          return _json({'ok': true, 'removed': n});
        }
        return _json({'ok': false, 'reason': '없는 길'}, 404);
      });
}

Future<String> _version() async => '0.2.14+300';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => NativePush.instance = NativePush());

  group('알림의 갈 곳', () {
    test('아는 route 만 따라간다 — 모르는 값 · 빈 값은 버린다', () {
      expect(pushRoute({'route': 'pokes'}), 'pokes');
      expect(pushRoute({'route': 'social', 'kind': 'news'}), 'social');
      expect(pushRoute({'route': 'admin'}), isNull, reason: '새 서버가 보낸 모르는 값으로 엉뚱한 곳에 가면 안 됩니다');
      expect(pushRoute({}), isNull);
      expect(const PushMessage(data: {'route': 'pokes'}).route, 'pokes');
    });
  });

  group('설정 파일이 없는 빌드', () {
    test('초기화가 실패하면 아무 요청도 안 하고 「꺼짐」', () async {
      final s = _Server();
      final api = PushAwareApi(baseUrl: 'https://x.test', client: s.client);
      await api.setToken('tok');
      final fake = FakePush(initOk: false);
      final push = NativePush(platform: () => fake, appVersion: _version);
      await push.start(api: api);
      await push.idle;
      expect(push.available, isFalse);
      expect(s.calls.where((c) => c.contains('/push/')), isEmpty);
      expect(describePush(push).label, '꺼짐');
      /* 로그아웃도 예전처럼 — 서버에서 뺄 기기가 없으니 DELETE 없이. */
      NativePush.instance = push;
      await api.signOut();
      await push.idle;
      expect(s.calls, ['POST /auth/signout']);
      expect(fake.deletes, 0);
    });

    test('웹 · 데스크톱(플랫폼 없음) · 초기화가 던져도 조용히 꺼짐', () async {
      final api = Api(baseUrl: 'https://x.test', client: _Server().client);
      final none = NativePush(platform: () => null);
      await none.start(api: api);
      expect(none.available, isFalse);
      final throwing = NativePush(platform: () => throw StateError('no firebase'));
      await throwing.start(api: api);
      expect(throwing.available, isFalse);
      expect(describePush(throwing).label, '꺼짐');
    });

    test('진짜 Firebase 도 설정이 없으면 false 로 끝난다(던지지 않음)', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      expect(await FirebasePushPlatform('android').init(), isFalse);
    });
  });

  group('등록 · 갱신 · 로그아웃', () {
    test('로그인돼 있으면 토큰 · 플랫폼 · 판 · 권한을 한 번 보낸다', () async {
      final s = _Server();
      final api = PushAwareApi(baseUrl: 'https://x.test', client: s.client);
      await api.setToken('tok');
      final fake = FakePush();
      final push = NativePush(platform: () => fake, appVersion: _version);
      await push.start(api: api);
      await push.idle;
      expect(s.devices, [
        {'token': 'fcm-token-1', 'platform': 'android', 'appVersion': '0.2.14+300', 'permission': 'granted',
          'secret': matches(RegExp(r'^[A-Za-z0-9_-]{43}$'))},
      ]);
      expect(push.registered, isTrue);
      expect(describePush(push).label, '켜짐');
      expect(fake.asks, [false], reason: '안드로이드는 SnackNudge 가 묻습니다 — 여기서 또 물으면 창이 두 번');

      await push.register();
      await push.idle;
      expect(s.devices, hasLength(1), reason: '같은 것은 두 번 안 보냅니다');
    });

    test('로그인 전에는 안 보내고, 로그인하는 순간 보낸다', () async {
      final s = _Server();
      final api = PushAwareApi(baseUrl: 'https://x.test', client: s.client);
      final push = NativePush(platform: FakePush.new, appVersion: _version);
      await push.start(api: api);
      await push.idle;
      expect(s.devices, isEmpty);
      await api.signIn(handle: 'a', password: 'b');
      await Future<void>.delayed(Duration.zero);
      await push.idle;
      expect(s.devices.single['token'], 'fcm-token-1');
    });

    test('토큰이 바뀌면 새 토큰으로 다시 등록한다', () async {
      final s = _Server();
      final api = PushAwareApi(baseUrl: 'https://x.test', client: s.client);
      await api.setToken('tok');
      final fake = FakePush();
      final push = NativePush(platform: () => fake, appVersion: _version);
      await push.start(api: api);
      await push.idle;
      fake.refresh.add('fcm-token-new');
      await Future<void>.delayed(Duration.zero);
      await push.idle;
      expect(s.devices.map((d) => d['token']), ['fcm-token-1', 'fcm-token-new']);
    });

    test('로그아웃: 서버에서 먼저 빼고(로그인이 살아 있을 때) → 로그아웃 → 토큰 폐기 → 다시 로그인하면 새 토큰', () async {
      final s = _Server();
      final fake = FakePush();
      final push = NativePush(platform: () => fake, appVersion: _version);
      final api = PushAwareApi(baseUrl: 'https://x.test', client: s.client, push: push);
      await api.setToken('tok');
      await push.start(api: api);
      await push.idle;

      await api.signOut();
      await push.idle;
      expect(s.deletes, [{'token': 'fcm-token-1'}]);
      expect(s.calls.indexOf('DELETE /push/device'), lessThan(s.calls.indexOf('POST /auth/signout')),
          reason: '로그아웃한 뒤에는 토큰이 없어 서버에 말을 못 합니다');
      expect(fake.deletes, 1, reason: '로그아웃 요청이 실패했어도 이 폰으로 그 계정의 알림이 안 오게');
      expect(push.registered, isFalse);

      await api.signIn(handle: 'a', password: 'b');
      await Future<void>.delayed(Duration.zero);
      await push.idle;
      expect(s.devices.last['token'], 'fcm-token-2');
    });

    test('옛 서버(404) — 「서버 미지원」, 로그아웃 때 DELETE 도 안 한다', () async {
      final s = _Server()..knowsPush = false;
      final fake = FakePush();
      final push = NativePush(platform: () => fake, appVersion: _version);
      final api = PushAwareApi(baseUrl: 'https://x.test', client: s.client, push: push);
      await api.setToken('tok');
      await push.start(api: api);
      await push.idle;
      expect(push.serverSupports, isFalse);
      expect(describePush(push).label, '서버 미지원');
      await api.signOut();
      expect(s.calls.where((c) => c == 'DELETE /push/device'), isEmpty);
    });

    test('서버에 FCM 설정이 없으면 등록은 하되 「서버 미지원」', () async {
      final s = _Server()..fcm = false;
      final api = Api(baseUrl: 'https://x.test', client: s.client);
      await api.setToken('tok');
      final push = NativePush(platform: FakePush.new, appVersion: _version);
      await push.start(api: api);
      await push.idle;
      expect(s.devices, hasLength(1), reason: '서버가 나중에 켜면 바로 쓰게 저장은 해 둡니다');
      expect(describePush(push).label, '서버 미지원');
    });

    test('서버 주소가 바뀌면 옛 서버에서 빼고, 토큰을 새로 받아 새 서버에만 등록한다', () async {
      final a = _Server(), b = _Server();
      final api1 = Api(baseUrl: 'https://a.test', client: a.client);
      await api1.setToken('tok');
      final fake = FakePush();
      final push = NativePush(platform: () => fake, appVersion: _version);
      await push.start(api: api1);
      await push.idle;
      final api2 = Api(baseUrl: 'https://b.test', client: b.client);
      await api2.loadToken();
      push.attach(api2);
      await Future<void>.delayed(Duration.zero);
      await push.idle;
      expect(a.devices.single['token'], 'fcm-token-1');
      expect(a.deletes, [{'token': 'fcm-token-1'}],
          reason: '옛 서버의 세션은 살아 있어서, 안 빼면 옛 계정의 알림이 이 폰으로 계속 옵니다');
      expect(fake.deletes, 1, reason: '옛 서버가 꺼져 있어 말이 못 닿아도 옛 토큰은 죽어야 합니다');
      expect(b.devices.single['token'], 'fcm-token-2');
      expect(b.devices.single['secret'], isNot(a.devices.single['secret']),
          reason: '서버마다 다른 비밀 — 한 서버가 받은 비밀로 다른 서버의 등록을 옮길 수 없게');
    });

    test('같은 주소로 다시 붙으면(로그아웃 뒤 등) 토큰을 버리지 않는다', () async {
      final a = _Server();
      final api1 = Api(baseUrl: 'https://a.test', client: a.client);
      await api1.setToken('tok');
      final fake = FakePush();
      final push = NativePush(platform: () => fake, appVersion: _version);
      await push.start(api: api1);
      await push.idle;
      final again = Api(baseUrl: 'https://a.test', client: a.client);
      await again.loadToken();
      push.attach(again);
      await Future<void>.delayed(Duration.zero);
      await push.idle;
      expect(a.deletes, isEmpty);
      expect(fake.deletes, 0);
    });

    test('설치 비밀은 같은 서버면 다음 실행에도 같다', () async {
      final s = _Server();
      final api = Api(baseUrl: 'https://x.test', client: s.client);
      await api.setToken('tok');
      final p1 = NativePush(platform: FakePush.new, appVersion: _version);
      await p1.start(api: api);
      await p1.idle;
      final p2 = NativePush(platform: FakePush.new, appVersion: _version);
      await p2.start(api: api);
      await p2.idle;
      await p2.register(force: true);
      await p2.idle;
      expect(s.devices.map((d) => d['secret']).toSet(), hasLength(1));
    });
  });

  group('구글 등록은 로그인한 뒤에만 (FCM 자동 초기화)', () {
    test('로그인 전: 켤 때 끈 채로 두고 토큰도 안 받는다 → 로그인: 켜고 받는다 → 로그아웃: 끄고 폐기', () async {
      final s = _Server();
      final fake = FakePush();
      final push = NativePush(platform: () => fake, appVersion: _version);
      final api = PushAwareApi(baseUrl: 'https://x.test', client: s.client, push: push);
      await push.start(api: api);
      await push.idle;
      expect(fake.autoInit, [false], reason: '지난 실행이 켠 채로 끝났어도 로그인 전에는 끕니다');

      await api.signIn(handle: 'a', password: 'b');
      await Future<void>.delayed(Duration.zero);
      await push.idle;
      expect(fake.autoInit, [false, true, 'token'], reason: '켜고 나서 토큰');

      await api.signOut();
      await push.idle;
      expect(fake.autoInit.last, false);
      expect(fake.deletes, 1);
    });

    test('로그인한 채로 켜면 끄지 않는다', () async {
      final s = _Server();
      final api = Api(baseUrl: 'https://x.test', client: s.client);
      await api.setToken('tok');
      final fake = FakePush();
      final push = NativePush(platform: () => fake, appVersion: _version);
      await push.start(api: api);
      await push.idle;
      expect(fake.autoInit, [true, 'token']);
    });
  });

  group('아이폰 권한', () {
    test('첫 로그인 뒤 한 번만 시스템 창 — 다음 실행에서는 다시 안 묻는다', () async {
      final s = _Server();
      final api = Api(baseUrl: 'https://x.test', client: s.client);
      await api.setToken('tok');
      final first = FakePush(platform: 'ios');
      final p1 = NativePush(platform: () => first, appVersion: _version);
      await p1.start(api: api);
      await p1.idle;
      expect(first.asks, [true]);
      expect(s.devices.single['platform'], 'ios');

      final again = FakePush(platform: 'ios');
      final p2 = NativePush(platform: () => again, appVersion: _version);
      await p2.start(api: api);
      await p2.idle;
      expect(again.asks, [false], reason: '거절한 사람을 조르지 않습니다');
    });

    test('거절해도 등록은 한다(permission: denied) — 서버가 크롬으로 대신 보내게. 줄은 「꺼짐」', () async {
      final s = _Server();
      final api = Api(baseUrl: 'https://x.test', client: s.client);
      await api.setToken('tok');
      final push = NativePush(platform: () => FakePush(platform: 'ios', perm: PushPermission.denied),
          appVersion: _version);
      await push.start(api: api);
      await push.idle;
      expect(s.devices.single['permission'], 'denied');
      final d = describePush(push);
      expect(d.label, '꺼짐');
      expect(d.hint, contains('폰 설정'));
    });

    test('돌아왔을 때 권한이 바뀌었으면 다시 알린다', () async {
      final s = _Server();
      final api = Api(baseUrl: 'https://x.test', client: s.client);
      await api.setToken('tok');
      final fake = FakePush(perm: PushPermission.denied);
      final push = NativePush(platform: () => fake, appVersion: _version);
      await push.start(api: api);
      await push.idle;
      await push.resumed();
      expect(s.devices, hasLength(1), reason: '바뀐 게 없으면 안 보냅니다');
      fake.perm = PushPermission.granted;
      await push.resumed();
      expect(s.devices.map((d) => d['permission']), ['denied', 'granted']);
    });
  });

  group('앱을 쓰는 중 · 알림을 눌렀을 때', () {
    test('안드로이드: 앞에 떠 있을 때는 앱이 직접 띄우고(payload = route), 독촉이면 콜백', () async {
      final api = Api(baseUrl: 'https://x.test', client: _Server().client);
      await api.setToken('tok');
      final fake = FakePush();
      final push = NativePush(platform: () => fake, appVersion: _version);
      final got = <String?>[];
      await push.start(api: api, onMessage: (m, route) async => got.add(route));
      fake.fg.add(const PushMessage(title: '나린님이 운동하라고 콕 찔렀어요', body: '오늘 운동 어때요?',
          data: {'route': 'pokes', 'kind': 'poke'}, id: 'm1'));
      await Future<void>.delayed(Duration.zero);
      expect(fake.shown.single.payload, 'pokes');
      expect(fake.shown.single.id, inInclusiveRange(kPushIdBase, kPushIdBase + 999));
      expect(fake.shown.single.tag, isNull);
      expect(got, ['pokes']);
    });

    test('안드로이드: 서버가 준 tag 가 있으면 FCM 이 뒤에서 띄웠을 칸(tag, 번호 0)에 띄운다', () async {
      final api = Api(baseUrl: 'https://x.test', client: _Server().client);
      await api.setToken('tok');
      final fake = FakePush();
      final push = NativePush(platform: () => fake, appVersion: _version);
      await push.start(api: api);
      fake.fg.add(const PushMessage(title: '친구가 운동하라고 콕 찔렀어요', body: '오늘 운동 어때요?',
          data: {'route': 'pokes', 'kind': 'poke', 'pokeId': '7', 'tag': 'poke-7'}));
      await Future<void>.delayed(Duration.zero);
      expect(fake.shown.single.id, 0);
      expect(fake.shown.single.tag, 'poke-7');
      expect(pokeSlot(7, android: true), (id: 0, tag: 'poke-7'), reason: '가져와서 띄우는 것도 같은 칸');
      expect(pokeSlot(7, android: false), (id: 1007, tag: null), reason: '아이폰 로컬 알림에는 tag 가 없음');
    });

    test('같은 독촉이 두 길로 와도 한 번만 — 가져오기가 먼저 띄웠으면 앱 알림은 안 띄운다', () async {
      final api = Api(baseUrl: 'https://x.test', client: _Server().client);
      await api.setToken('tok');
      final fake = FakePush();
      final push = NativePush(platform: () => fake, appVersion: _version);
      await push.start(api: api);
      expect(push.claimPoke(8), isTrue, reason: '가져오기가 먼저 잡음(서버 pushed 가 아직 안 적힌 사이)');
      fake.fg.add(const PushMessage(title: 't', body: 'b', data: {'route': 'pokes', 'pokeId': '8', 'tag': 'poke-8'}));
      await Future<void>.delayed(Duration.zero);
      expect(fake.shown, isEmpty);

      fake.fg.add(const PushMessage(title: 't', body: 'b', data: {'route': 'pokes', 'pokeId': '9'}));
      await Future<void>.delayed(Duration.zero);
      expect(fake.shown, hasLength(1));
      expect(push.claimPoke(9), isFalse, reason: '앱 알림이 먼저 띄웠으면 가져오기는 안 띄움');

      fake.opened.add(const PushMessage(data: {'route': 'pokes', 'pokeId': '10'}));
      await Future<void>.delayed(Duration.zero);
      expect(push.claimPoke('10'), isFalse, reason: '눌러서 열었으면 이미 본 것');
      expect(push.claimPoke(null), isTrue, reason: '번호 없는 알림은 거를 수 없음');
    });

    test('아이폰: 시스템이 띄우므로 또 띄우지 않는다. 로그아웃 뒤 늦게 온 것도 안 띄운다', () async {
      final api = Api(baseUrl: 'https://x.test', client: _Server().client);
      await api.setToken('tok');
      final ios = FakePush(platform: 'ios');
      final p1 = NativePush(platform: () => ios, appVersion: _version);
      await p1.start(api: api);
      ios.fg.add(const PushMessage(title: 't', body: 'b', data: {'route': 'pokes'}));
      await Future<void>.delayed(Duration.zero);
      expect(ios.shown, isEmpty);

      final out = Api(baseUrl: 'https://x.test', client: _Server().client);
      final android = FakePush();
      final p2 = NativePush(platform: () => android, appVersion: _version);
      await p2.start(api: out);
      android.fg.add(const PushMessage(title: 't', body: 'b', data: {'route': 'pokes'}));
      await Future<void>.delayed(Duration.zero);
      expect(android.shown, isEmpty);
    });

    test('누르면 route 로 — 꺼져 있던 앱(initialMessage)도, 모르는 route 는 무시', () async {
      final api = Api(baseUrl: 'https://x.test', client: _Server().client);
      final fake = FakePush()..initial = const PushMessage(data: {'route': 'social'});
      final push = NativePush(platform: () => fake, appVersion: _version);
      final opened = <String>[];
      await push.start(api: api, onOpen: opened.add);
      fake.opened.add(const PushMessage(data: {'route': 'pokes'}));
      fake.opened.add(const PushMessage(data: {'route': 'nowhere'}));
      await Future<void>.delayed(Duration.zero);
      expect(opened, ['social', 'pokes']);
    });

    testWidgets('notificationRoute 가 pokes · social 이면 친구 탭으로(위에 뜬 화면은 닫고)', (t) async {
      t.view.physicalSize = const Size(1000, 2400);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      final app = await AppState.boot();
      app.store.set({
        'guest': true,
        'onboarded': true,
        'profile': {'sex': 'male', 'age': 30, 'heightCm': 175, 'activityLevel': 'moderate',
            'trainingAge': 'novice', 'daysPerWeek': 3, 'mealsPerDay': 3},
      });
      final api = Api(baseUrl: '', client: MockClient((_) async => http.Response('{"ok":false}', 404)));
      await t.pumpWidget(Scope(
          state: app, api: api, onServerChange: (_) async {},
          child: MaterialApp(theme: mbLight(), home: const Shell())));
      await t.pumpAndSettle();
      NavigationBar bar() => t.widget<NavigationBar>(find.byType(NavigationBar));
      expect(bar().selectedIndex, 0);
      Navigator.of(t.element(find.byType(NavigationBar)))
          .push(MaterialPageRoute(builder: (_) => const Scaffold(body: Text('위에 뜬 화면'))));
      await t.pumpAndSettle();
      notificationRoute.value = 'pokes';
      await t.pumpAndSettle();
      expect(find.text('위에 뜬 화면'), findsNothing);
      expect(bar().selectedIndex, 4);
      expect(notificationRoute.value, isNull);

      await t.tap(find.text('홈'));
      await t.pumpAndSettle();
      notificationRoute.value = 'social';
      await t.pumpAndSettle();
      expect(bar().selectedIndex, 4);
    });
  });

  group('독촉 가져오기', () {
    testWidgets('앱으로 돌아올 때 가져온다 — 알림 창을 잠깐 내렸다 올린 것은 한 번으로', (t) async {
      var clock = DateTime(2026, 9, 26, 9);
      var fetched = 0;
      final r = PokeResume(() async => fetched++, now: () => clock)..wire();
      addTearDown(r.dispose);
      Future<void> leaveAndComeBack() async {
        for (final s in [AppLifecycleState.inactive, AppLifecycleState.hidden,
            AppLifecycleState.paused, AppLifecycleState.hidden,
            AppLifecycleState.inactive, AppLifecycleState.resumed]) {
          t.binding.handleAppLifecycleStateChanged(s);
        }
        await t.pump();
      }

      await leaveAndComeBack();
      expect(fetched, 1);
      clock = clock.add(const Duration(seconds: 5));
      await leaveAndComeBack();
      expect(fetched, 1, reason: '30초 안에는 다시 묻지 않습니다');
      clock = clock.add(const Duration(minutes: 5));
      await leaveAndComeBack();
      expect(fetched, 2);
    });

    test('서버가 앱 알림으로 이미 보낸 독촉은 pushed 로 표시된다(폰 알림을 또 안 띄우게)', () async {
      final sp = await SharedPreferences.getInstance();
      final api = Api(baseUrl: 'https://x.test', client: MockClient((req) async => _json({
            'ok': true,
            'pokes': [
              {'id': 1, 'kind': 'workout', 'at': '2026-09-26T00:00:00Z', 'from': {'id': 'f', 'displayName': '나린'}, 'pushed': true},
              {'id': 2, 'kind': 'workout', 'at': '2026-09-26T00:00:00Z', 'from': {'id': 'g', 'displayName': '도윤'}},
            ],
          })));
      await api.setToken('tok');
      final fresh = await PokeBox(sp).fetch(api);
      expect(fresh.map((p) => p['pushed']), [true, false], reason: '옛 서버(표시 없음)는 예전처럼 띄웁니다');
    });
  });

  group('설정 화면', () {
    Future<({_Server s, Api api})> open(WidgetTester t, {bool knowsPush = true, bool webName = false,
        int webSubs = 2, bool firebase = true}) async {
      t.view.physicalSize = const Size(1000, 3000);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      final s = _Server()
        ..knowsPush = knowsPush
        ..webSubscriptionsName = webName
        ..webSubs = webSubs;
      final api = Api(baseUrl: 'https://x.test', client: s.client);
      await api.setToken('tok');
      final push = NativePush(platform: () => FakePush(initOk: firebase), appVersion: _version);
      NativePush.instance = push;
      /* runAsync 로 감싸지 않습니다 — 가짜 시계 안에서 만든 Future 에 진짜 시계 쪽에서 이어 붙이면
         그 이음이 가짜 쪽 대기열에 들어가 영영 안 돕니다. 여기는 전부 마이크로태스크라 그냥 기다립니다. */
      await push.start(api: api);
      await push.idle;
      final app = await AppState.boot();
      await t.pumpWidget(Scope(
          state: app, api: api, onServerChange: (_) async {},
          child: MaterialApp(theme: mbLight(), home: const SettingsScreen())));
      await t.pumpAndSettle();
      return (s: s, api: api);
    }

    testWidgets('켜짐 + 크롬 알림이 남아 있으면 「끄기」 — 누르면 지우고 줄이 사라진다', (t) async {
      final o = await open(t);
      expect(find.text('푸시 알림'), findsOneWidget);
      expect(find.text('켜짐'), findsOneWidget);
      expect(find.text('크롬(웹) 알림 끄기'), findsOneWidget);
      expect(find.textContaining('2곳'), findsOneWidget);
      await t.tap(find.widgetWithText(OutlinedButton, '끄기'));
      await t.pumpAndSettle();
      expect(o.s.calls, contains('DELETE /push/web'));
      expect(o.s.webSubs, 0);
      expect(find.text('크롬(웹) 알림 끄기'), findsNothing);
      expect(t.takeException(), isNull);
      await t.pump(const Duration(seconds: 5));   // 토스트가 사라질 때까지
    });

    testWidgets('서버가 다른 이름(/push/web-subscriptions)이어도 끈다', (t) async {
      final o = await open(t, webName: true);
      await t.tap(find.widgetWithText(OutlinedButton, '끄기'));
      await t.pumpAndSettle();
      expect(o.s.calls, containsAllInOrder(['DELETE /push/web', 'DELETE /push/web-subscriptions']));
      expect(o.s.webSubs, 0);
      expect(find.text('크롬(웹) 알림 끄기'), findsNothing);
      await t.pump(const Duration(seconds: 5));
    });

    testWidgets('옛 서버(404) — 「서버 미지원」, 크롬 줄은 숨긴다', (t) async {
      await open(t, knowsPush: false);
      expect(find.text('서버 미지원'), findsOneWidget);
      expect(find.text('크롬(웹) 알림 끄기'), findsNothing);
    });

    testWidgets('크롬 구독이 없으면 크롬 줄을 숨긴다 · 설정 파일 없는 빌드는 「꺼짐」', (t) async {
      await open(t, webSubs: 0, firebase: false);
      expect(find.text('꺼짐'), findsOneWidget);
      expect(find.textContaining('이 판은 앱 알림을 받지 못합니다'), findsOneWidget);
      expect(find.text('크롬(웹) 알림 끄기'), findsNothing);
    });

    testWidgets('360px 에서도 넘치지 않는다', (t) async {
      await open(t);
      t.view.physicalSize = const Size(360, 3000);
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(find.text('크롬(웹) 알림 끄기'), findsOneWidget);
    });
  });
}
