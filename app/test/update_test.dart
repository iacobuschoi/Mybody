/* =============================================================================
 * update_test.dart — 새 판 안내가 **맞는 때에만** 뜨는가
 *
 * 틀리게 뜨면 둘 중 하나입니다. 이미 최신인 사람에게 "업데이트하세요" 를
 * 띄우면 스토어에 가서 없는 판을 찾다가 앱을 의심합니다. 떠야 할 때 안
 * 뜨면 APK 로 깐 친구는 옛 판에 계속 남습니다 — 그게 이 기능이 생긴 이유입니다.
 *
 * 서버는 없습니다. 답은 가짜 클라이언트가 하고, 앱의 판은
 * PackageInfo.setMockInitialValues 나 직접 만든 PackageInfo 로 넣습니다.
 * ========================================================================== */
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mybody/src/api.dart';
import 'package:mybody/src/app_state.dart';
import 'package:mybody/src/scope.dart';
import 'package:mybody/src/screens/account.dart';
import 'package:mybody/src/screens/home.dart';
import 'package:mybody/src/screens/onboarding.dart';
import 'package:mybody/src/screens/settings.dart';
import 'package:mybody/src/screens/update_banner.dart';
import 'package:mybody/src/theme.dart';
import 'package:mybody/src/update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _play = 'https://play.google.com/store/apps/details?id=io.github.iacobuschoi.mybody';
const _apk = 'https://github.com/iacobuschoi/Mybody/releases/latest';
const _appstore = 'https://apps.apple.com/kr/app/id6815144446';

Map<String, Object?> _server({
  String appstore = '',
  String play = '',
  String apk = '',
  String min = '',
}) =>
    {
      'ok': true,
      'latest': {'appstore': appstore, 'play': play, 'apk': apk},
      'min': min,
      'urls': {'appstore': _appstore, 'play': _play, 'apk': _apk},
    };

VersionInfo _info({String appstore = '', String play = '', String apk = '', String min = ''}) =>
    VersionInfo.fromJson(_server(appstore: appstore, play: play, apk: apk, min: min));

PackageInfo _pkg(String version, {String build = '262', String? installer}) => PackageInfo(
    appName: 'Mybody', packageName: 'io.github.iacobuschoi.mybody',
    version: version, buildNumber: build, installerStore: installer);

/// 서버 대신. `answer` 를 바꾸면 다음 요청부터 그 답이 나갑니다.
class _FakeServer {
  _FakeServer([this.base = 'https://x.test']);

  /// 서버 주소. 확인기는 주소가 바뀌어야 "서버를 옮겼다" 로 봅니다.
  final String base;
  Object answer = 404;   // Map 이면 200 + 그 JSON, int 면 그 상태, 그 밖(글자)이면 못 닿음
  int hits = 0;

  /// 답하기 전에 기다리는 시간 — 묻는 사이 서버를 옮기는 경우를 만듭니다.
  Duration delay = Duration.zero;

  Api api() => Api(
      baseUrl: base,
      client: MockClient((req) async {
        if (req.url.path != '/api/version') {
          return http.Response('{"ok":false}', 404);
        }
        hits++;
        final a = answer;
        if (delay > Duration.zero) await Future<void>.delayed(delay);
        if (a is Map) {
          return http.Response.bytes(utf8.encode(jsonEncode(a)), 200,
              headers: {'content-type': 'application/json; charset=utf-8'});
        }
        if (a is int) return http.Response('{"ok":false}', a);
        throw http.ClientException('닿지 않음');
      }));
}

void main() {
  /* --- 판 견주기 ----------------------------------------------------------- */
  group('판 견주기', () {
    test('같으면 0, 앞이면 음수, 뒤면 양수', () {
      expect(compareVersions('0.2.8', '0.2.8'), 0);
      expect(compareVersions('0.2.7', '0.2.8'), lessThan(0));
      expect(compareVersions('0.3.0', '0.2.9'), greaterThan(0));
      expect(compareVersions('1.0.0', '0.99.99'), greaterThan(0));
    });

    test('숫자로 견준다 — 0.2.10 이 0.2.9 보다 뒤', () {
      expect(compareVersions('0.2.10', '0.2.9'), greaterThan(0));
      expect(compareVersions('0.10.0', '0.9.9'), greaterThan(0));
    });

    test('빌드 꼬리(+262)와 시험판 꼬리(-beta)는 뗀다', () {
      expect(compareVersions('0.2.8+262', '0.2.8'), 0);
      expect(compareVersions('0.2.8-beta.1', '0.2.8'), 0);
      expect(compareVersions('0.2.7+999', '0.2.8+1'), lessThan(0));
      expect(cleanVersion(' 0.2.08 '), '0.2.8');
    });

    test('모양이 틀리면 모른다(null) — 던지지 않는다', () {
      for (final bad in <Object?>[null, '', '0.2', '0.2.8.1', 'v0.2.8', 'abc', '0.2.x',
          '-1.0.0', 28, 0.28, '9999999999.0.0', '٠.٢.٨']) {
        expect(compareVersions(bad, '0.2.8'), isNull, reason: '넣은 것: $bad');
        expect(compareVersions('0.2.8', bad), isNull, reason: '넣은 것: $bad');
        expect(cleanVersion(bad), '', reason: '넣은 것: $bad');
      }
    });
  });

  /* --- 받은 곳 ------------------------------------------------------------- */
  group('받은 곳', () {
    test('안드로이드: 플레이가 깔았으면 play, 아니면 전부 apk', () {
      expect(channelOf(TargetPlatform.android, 'com.android.vending'), UpdateChannel.play);
      expect(channelOf(TargetPlatform.android, null), UpdateChannel.apk);
      expect(channelOf(TargetPlatform.android, ''), UpdateChannel.apk);
      /* 파일 관리자 · 브라우저로 깐 것, adb 로 깐 것 */
      expect(channelOf(TargetPlatform.android, 'com.google.android.packageinstaller'),
          UpdateChannel.apk);
      expect(channelOf(TargetPlatform.android, 'com.android.chrome'), UpdateChannel.apk);
      expect(channelOf(TargetPlatform.android, 'com.android.shell'), UpdateChannel.apk);
    });

    test('플레이용으로 만든 앱은 누가 깔았든 play — 출시 전 보고서(adb)가 GitHub 을 안 본다', () {
      for (final who in <String?>[null, '', 'com.android.shell', 'com.android.vending',
          'com.google.android.packageinstaller']) {
        expect(channelOf(TargetPlatform.android, who, playBuild: true), UpdateChannel.play,
            reason: '설치 주체: $who');
      }
      /* 아이폰 · 웹에는 상관없습니다 */
      expect(channelOf(TargetPlatform.iOS, 'com.apple', playBuild: true), UpdateChannel.appstore);
      expect(channelOf(TargetPlatform.android, null, web: true, playBuild: true),
          UpdateChannel.none);
      /* 시험은 플레이용 빌드가 아닙니다 */
      expect(kPlayBuild, isFalse);
    });

    test('아이폰: TestFlight 면 testflight, 아니면 appstore', () {
      expect(channelOf(TargetPlatform.iOS, 'com.apple.testflight'), UpdateChannel.testflight);
      expect(channelOf(TargetPlatform.iOS, 'com.apple'), UpdateChannel.appstore);
      expect(channelOf(TargetPlatform.iOS, 'com.apple.simulator'), UpdateChannel.appstore);
      expect(channelOf(TargetPlatform.iOS, null), UpdateChannel.appstore);
    });

    test('웹 · 데스크톱은 알릴 곳이 없다', () {
      for (final p in [TargetPlatform.macOS, TargetPlatform.windows,
          TargetPlatform.linux, TargetPlatform.fuchsia]) {
        expect(channelOf(p, null), UpdateChannel.none);
      }
      expect(channelOf(TargetPlatform.android, 'com.android.vending', web: true),
          UpdateChannel.none);
    });

    test('설정에 쓰는 이름 — TestFlight 는 안 붙인다(앱스토어 심사도 같은 모양)', () {
      expect(channelLabel(UpdateChannel.appstore), '앱스토어');
      expect(channelLabel(UpdateChannel.testflight), '');
      expect(channelLabel(UpdateChannel.play), '플레이 스토어');
      expect(channelLabel(UpdateChannel.apk), '직접 설치한 APK');
      expect(channelLabel(UpdateChannel.none), '');
    });
  });

  /* --- 서버 값 읽기 -------------------------------------------------------- */
  group('서버 값 읽기', () {
    test('약속한 모양을 그대로 읽는다', () {
      final i = _info(appstore: '0.2.8', play: '0.2.9', apk: '0.2.10', min: '0.2.6');
      expect(i.latestFor(UpdateChannel.appstore), '0.2.8');
      expect(i.latestFor(UpdateChannel.testflight), '0.2.8');
      expect(i.latestFor(UpdateChannel.play), '0.2.9');
      expect(i.latestFor(UpdateChannel.apk), '0.2.10');
      expect(i.min, '0.2.6');
      expect(i.urlFor(UpdateChannel.play), _play);
      expect(i.urlFor(UpdateChannel.testflight), _appstore);
    });

    test('틀린 값은 버리고, 주소가 없거나 https 가 아니면 기본 주소', () {
      final i = VersionInfo.fromJson({
        'ok': true,
        'latest': {'appstore': 28, 'play': '0.2', 'apk': ['0.2.9']},
        'min': 'soon',
        'urls': {'play': 'javascript:alert(1)', 'apk': 'http://evil.test/a.apk'},
      });
      expect(i.latestFor(UpdateChannel.appstore), '');
      expect(i.latestFor(UpdateChannel.play), '');
      expect(i.latestFor(UpdateChannel.apk), '');
      expect(i.min, '');
      expect(i.urlFor(UpdateChannel.play), kUpdateUrls['play']);
      expect(i.urlFor(UpdateChannel.apk), kUpdateUrls['apk']);
      expect(i.urlFor(UpdateChannel.appstore), kUpdateUrls['appstore']);
    });

    test('맵이 아니거나 칸이 없어도 던지지 않는다', () {
      for (final j in <Object?>[null, 'x', 3, [], {}, {'latest': 'x', 'urls': 1}]) {
        final i = VersionInfo.fromJson(j);
        expect(i.min, '');
        expect(i.latestFor(UpdateChannel.play), '');
      }
    });

    test('저장했다 다시 읽어도 같다', () {
      final i = _info(appstore: '0.2.8', play: '0.2.9', apk: '0.2.9', min: '0.2.6');
      final back = VersionInfo.fromJson(jsonDecode(jsonEncode(i.toJson())));
      expect(back.toJson(), i.toJson());
    });
  });

  /* --- 무엇을 띄울까 ------------------------------------------------------- */
  group('무엇을 띄울까', () {
    UpdateNotice? decide(String current, UpdateChannel ch, VersionInfo? info,
            [String dismissed = '']) =>
        decideUpdate(current: current, channel: ch, info: info, dismissed: dismissed);

    test('서버 값이 없으면 아무것도 안 띄운다', () {
      expect(decide('0.2.7', UpdateChannel.play, null), isNull);
      expect(decide('0.2.7', UpdateChannel.play, const VersionInfo()), isNull);
      expect(decide('0.2.7', UpdateChannel.play, _info()), isNull);
    });

    test('새 판이 있으면 available — 그 채널의 값으로', () {
      final i = _info(appstore: '0.2.7', play: '0.2.8', apk: '0.2.9');
      final n = decide('0.2.7', UpdateChannel.play, i)!;
      expect(n.kind, UpdateKind.available);
      expect(n.version, '0.2.8');
      expect(n.current, '0.2.7');
      expect(n.url, _play);
      expect(n.dismissable, isTrue);
      expect(decide('0.2.7', UpdateChannel.apk, i)!.version, '0.2.9');
      expect(decide('0.2.7', UpdateChannel.apk, i)!.url, _apk);
      /* 앱스토어는 아직 0.2.7 — 심사를 기다리는 중이면 스토어에 없는 판을 알리지 않습니다 */
      expect(decide('0.2.7', UpdateChannel.appstore, i), isNull);
    });

    test('최신이거나 더 새 판이면 안 띄운다', () {
      final i = _info(play: '0.2.8');
      expect(decide('0.2.8', UpdateChannel.play, i), isNull);
      expect(decide('0.2.9', UpdateChannel.play, i), isNull);
      expect(decide('0.2.8+300', UpdateChannel.play, i), isNull);
    });

    test('「나중에」는 그 판만 접는다 — 더 새 판은 다시 뜬다', () {
      expect(decide('0.2.7', UpdateChannel.apk, _info(apk: '0.2.8'), '0.2.8'), isNull);
      final again = decide('0.2.7', UpdateChannel.apk, _info(apk: '0.2.9'), '0.2.8');
      expect(again?.version, '0.2.9');
    });

    test('최소 판보다 낮으면 required — 접을 수 없고, 접어 둔 것도 무시한다', () {
      final i = _info(play: '0.2.8', min: '0.2.8');
      final n = decide('0.2.7', UpdateChannel.play, i, '0.2.8')!;
      expect(n.kind, UpdateKind.required);
      expect(n.version, '0.2.8');
      expect(n.dismissable, isFalse);
      expect(n.url, _play);
    });

    test('required 가 available 보다 먼저', () {
      final i = _info(apk: '0.3.0', min: '0.2.8');
      expect(decide('0.2.7', UpdateChannel.apk, i)!.kind, UpdateKind.required);
      expect(decide('0.2.8', UpdateChannel.apk, i)!.kind, UpdateKind.available);
    });

    test('최소 판만 있고 최신이 비어도 required 는 뜬다', () {
      final n = decide('0.2.5', UpdateChannel.apk, _info(min: '0.2.6'))!;
      expect(n.kind, UpdateKind.required);
      expect(n.url, _apk);
    });

    test('TestFlight: 앱스토어 값을 보되 required 만 띄운다', () {
      final i = _info(appstore: '0.2.9', min: '0.2.8');
      expect(decide('0.2.8', UpdateChannel.testflight, i), isNull,
          reason: '새 빌드는 TestFlight 가 스스로 알립니다');
      final n = decide('0.2.7', UpdateChannel.testflight, i)!;
      expect(n.kind, UpdateKind.required);
      expect(n.url, _appstore);
    });

    test('지금 판을 모르면 아무것도 안 띄운다', () {
      final i = _info(play: '0.2.9', min: '0.2.8');
      for (final bad in ['', 'dev', '0.2']) {
        expect(decide(bad, UpdateChannel.play, i), isNull, reason: '지금 판: $bad');
      }
    });

    test('웹 · 데스크톱은 아무것도 안 띄운다', () {
      final i = _info(appstore: '0.2.9', play: '0.2.9', apk: '0.2.9', min: '0.2.8');
      expect(decide('0.2.7', UpdateChannel.none, i), isNull);
    });
  });

  /* --- 확인기 -------------------------------------------------------------- */
  group('확인기', () {
    late _FakeServer server;
    late DateTime clock;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      server = _FakeServer();
      clock = DateTime.utc(2026, 9, 24, 9);
    });

    UpdateCheck make({String version = '0.2.7', String? installer = 'com.android.vending',
            TargetPlatform platform = TargetPlatform.android, Api? api}) =>
        UpdateCheck(
          api: api ?? server.api(),
          packageInfo: () async => _pkg(version, installer: installer),
          platform: platform,
          web: false,
          now: () => clock,
        );

    test('켤 때 한 번 묻고, 6시간 안에는 다시 묻지 않는다', () async {
      server.answer = _server(play: '0.2.8');
      final c = make();
      await c.start();
      expect(server.hits, 1);
      expect(c.channel, UpdateChannel.play);
      expect(c.notice?.kind, UpdateKind.available);

      clock = clock.add(const Duration(hours: 5, minutes: 59));
      await c.check();
      expect(server.hits, 1);

      clock = clock.add(const Duration(minutes: 2));
      await c.check();
      expect(server.hits, 2);
    });

    test('서버에 못 닿으면 물은 것으로 치지 않는다 — 다음에 다시 묻는다', () async {
      server.answer = 'offline';
      final c = make();
      await c.start();
      expect(server.hits, 1);
      expect(c.checkedAt, isNull);
      expect(c.notice, isNull);

      server.answer = _server(play: '0.2.8');
      await c.check();
      expect(server.hits, 2);
      expect(c.notice?.version, '0.2.8');
    });

    test('이 길이 없는 옛 서버(404)는 조용히 — 안내 없음, 6시간 쉰다', () async {
      server.answer = 404;
      final c = make();
      await c.start();
      expect(c.notice, isNull);
      expect(c.checkedAt, clock);
      await c.check();
      expect(server.hits, 1);
    });

    test('서버가 틀린 값을 주면 안내 없음 (던지지 않는다)', () async {
      server.answer = {'ok': true, 'latest': {'play': '곧'}, 'min': 7, 'urls': null};
      final c = make();
      await c.start();
      expect(c.notice, isNull);
    });

    test('지난 답은 이 기기에 남는다 — 서버가 꺼져 있어도 required 는 계속 뜬다', () async {
      server.answer = _server(play: '0.2.8', min: '0.2.8');
      await make().start();

      server.answer = 'offline';
      clock = clock.add(const Duration(days: 1));
      final c = make();
      await c.start();
      expect(c.notice?.kind, UpdateKind.required);
    });

    test('실패한 확인이 지난 답을 지우지 않는다', () async {
      server.answer = _server(apk: '0.2.8');
      final c = make(installer: null);
      await c.start();
      expect(c.notice?.version, '0.2.8');
      server.answer = 500;
      await c.check(force: true);
      expect(c.notice?.version, '0.2.8');
    });

    test('터널이 대신 답한 5xx · 너무 잦음(429)은 물은 것으로 치지 않는다', () async {
      for (final status in [500, 502, 503, 530, 429, 408]) {
        SharedPreferences.setMockInitialValues({});
        final s = _FakeServer()..answer = status;
        final c = make(api: s.api(), installer: null);
        await c.start();
        expect(c.checkedAt, isNull, reason: '$status');
        /* 6시간을 안 기다리고 다음 확인에서 다시 묻습니다 */
        s.answer = _server(apk: '0.2.8');
        await c.check();
        expect(s.hits, 2, reason: '$status');
        expect(c.notice?.version, '0.2.8', reason: '$status');
      }
    });

    test('「나중에」는 이 기기에 남고, 더 새 판이 나오면 다시 뜬다', () async {
      server.answer = _server(apk: '0.2.8');
      final c = make(installer: null);
      await c.start();
      await c.dismiss();
      expect(c.notice, isNull);

      final again = make(installer: null);
      await again.start();
      expect(again.dismissed, '0.2.8');
      expect(again.notice, isNull);

      server.answer = _server(apk: '0.2.9');
      await again.check(force: true);
      expect(again.notice?.version, '0.2.9');
    });

    test('required 는 「나중에」로 접히지 않는다', () async {
      server.answer = _server(apk: '0.2.8', min: '0.2.8');
      final c = make(installer: null);
      await c.start();
      await c.dismiss();
      expect(c.notice?.kind, UpdateKind.required);
      expect(c.dismissed, '');
    });

    test('동기화되는 상태에 안 들어간다 — 따로 한 칸', () async {
      final app = await AppState.boot();
      app.store.set({'onboarded': true});
      server.answer = _server(apk: '0.2.9');
      final c = make(installer: null);
      await c.start();
      await c.dismiss();

      final sp = await SharedPreferences.getInstance();
      expect(sp.getString(UpdateCheck.storageKey), contains('0.2.9'));
      /* CloudSync 가 올리는 것은 store.exportJSON() 입니다. */
      final synced = app.store.exportJSON();
      expect(synced, isNot(contains('0.2.9')));
      expect(synced, isNot(contains('dismissed')));
      expect(UpdateCheck.storageKey, isNot('mybody.state.v1'));
    });

    test('웹 · 데스크톱은 서버에 묻지도 않는다', () async {
      server.answer = _server(apk: '0.2.9');
      final c = make(platform: TargetPlatform.linux);
      await c.start();
      expect(server.hits, 0);
      expect(c.notice, isNull);
    });

    test('판을 못 읽으면 조용히 — 안내 없음', () async {
      server.answer = _server(apk: '0.2.9', min: '0.2.8');
      final c = UpdateCheck(
          api: server.api(),
          packageInfo: () async => throw StateError('플러그인 없음'),
          platform: TargetPlatform.android, web: false, now: () => clock);
      await c.start();
      expect(c.package, isNull);
      expect(c.notice, isNull);
    });

    test('서버를 옮기면 6시간을 안 기다리고 새 서버에 묻는다', () async {
      server.answer = _server(play: '0.2.8');
      final c = make();
      await c.start();
      final other = _FakeServer('https://y.test')..answer = _server(play: '0.2.9');
      c.api = other.api();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(other.hits, 1);
      expect(c.notice?.version, '0.2.9');
    });

    test('옮긴 서버가 이 길이 없는 옛 서버면(404) 옛 서버의 답을 버린다 — 껐다 켜도', () async {
      server.answer = _server(play: '0.2.9', min: '0.2.8');
      final c = make();
      await c.start();
      expect(c.notice?.kind, UpdateKind.required);

      final old = _FakeServer('https://old.test')..answer = 404;
      c.api = old.api();
      /* 옮기는 순간 내립니다 — 새 서버의 답을 기다리지 않습니다 */
      expect(c.notice, isNull);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(old.hits, 1);
      expect(c.notice, isNull);

      /* 껐다 켜면 새 서버로 뜹니다. 저장된 것은 새 서버의 404 뿐입니다 */
      final again = make(api: old.api());
      await again.start();
      expect(again.notice, isNull);
      expect(old.hits, 1, reason: '404 도 대답이라 6시간 쉽니다');
    });

    test('옮긴 서버가 꺼져 있어도 옛 서버의 답을 버리고, 켜지면 바로 묻는다', () async {
      server.answer = _server(apk: '0.2.9', min: '0.2.8');
      final c = make(installer: null);
      await c.start();
      final down = _FakeServer('https://down.test')..answer = 'offline';
      c.api = down.api();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(c.notice, isNull);
      expect(c.checkedAt, isNull);
      down.answer = _server(apk: '0.2.9');
      await c.check();
      expect(down.hits, 2);
      expect(c.notice?.kind, UpdateKind.available);
    });

    test('묻는 사이 서버를 옮기면 옛 답은 버리고 새 서버에 다시 묻는다', () async {
      server
        ..answer = _server(play: '0.2.9', min: '0.2.8')
        ..delay = const Duration(milliseconds: 100);
      final c = make();
      final starting = c.start();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(server.hits, 1, reason: '옛 서버에 묻는 중');

      final next = _FakeServer('https://y.test')..answer = _server();
      c.api = next.api();
      await starting;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(next.hits, 1, reason: '끝난 뒤 새 서버에 다시 물었습니다');
      expect(c.notice, isNull, reason: '옛 서버의 최소 판이 들어앉지 않습니다');
      expect(c.checkedAt, clock);
    });

    test('로그아웃처럼 같은 서버에 Api 만 새로 만들면 지난 답을 그대로 둔다', () async {
      server.answer = _server(play: '0.2.9', min: '0.2.8');
      final c = make();
      await c.start();
      server.answer = 'offline';
      c.api = server.api();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(server.hits, 1, reason: '같은 서버라 다시 묻지 않습니다');
      expect(c.notice?.kind, UpdateKind.required);
    });

    test('다른 서버에서 받아 둔 답은 켤 때 안 쓴다', () async {
      SharedPreferences.setMockInitialValues({
        UpdateCheck.storageKey: jsonEncode({
          'from': 'https://old.test',
          'info': _info(play: '0.2.9', min: '0.2.8').toJson(),
          'at': clock.toIso8601String(),
          'dismissed': '0.2.9',
        }),
      });
      server.answer = 'offline';
      final c = make();
      await c.start();
      expect(c.notice, isNull);
      expect(server.hits, 1, reason: '옛 서버의 "물은 시각" 도 안 씁니다');
      expect(c.dismissed, '0.2.9', reason: '「나중에」 는 판 이야기라 그대로 둡니다');
    });
  });

  /* --- 앱으로 돌아올 때 ---------------------------------------------------- */
  testWidgets('앱으로 돌아오면 다시 묻는다 — 6시간이 지났을 때만', (t) async {
    SharedPreferences.setMockInitialValues({});
    final server = _FakeServer()..answer = _server(play: '0.2.8');
    var clock = DateTime.utc(2026, 9, 24, 9);
    final check = UpdateCheck(
        api: server.api(),
        packageInfo: () async => _pkg('0.2.7', installer: 'com.android.vending'),
        platform: TargetPlatform.android, web: false, now: () => clock)
      ..wire();
    addTearDown(check.dispose);
    await t.runAsync(check.start);
    expect(server.hits, 1);

    /* 폰이 실제로 거치는 순서대로 — 건너뛰면 AppLifecycleListener 가 막습니다 */
    Future<void> leaveAndComeBack() async {
      for (final s in [AppLifecycleState.inactive, AppLifecycleState.hidden,
          AppLifecycleState.paused, AppLifecycleState.hidden,
          AppLifecycleState.inactive, AppLifecycleState.resumed]) {
        t.binding.handleAppLifecycleStateChanged(s);
      }
      await t.pump();
      await t.pump();
    }

    await leaveAndComeBack();
    expect(server.hits, 1, reason: '6시간 안에는 다시 묻지 않습니다');

    clock = clock.add(const Duration(hours: 7));
    await leaveAndComeBack();
    expect(server.hits, 2);
  });

  /* --- 홈 안내 ------------------------------------------------------------- */
  group('홈 안내', () {
    late _FakeServer server;
    late List<Uri> opened;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      server = _FakeServer();
      opened = [];
    });

    /* 앱의 판은 플러그인의 시험용 값으로 넣습니다 — 실제 앱이 쓰는 길
       (PackageInfo.fromPlatform)을 그대로 밟습니다. */
    void installed(String version, {String? installer}) =>
        PackageInfo.setMockInitialValues(
            appName: 'Mybody', packageName: 'io.github.iacobuschoi.mybody',
            version: version, buildNumber: '262', buildSignature: '',
            installerStore: installer);

    Future<(AppState, UpdateCheck)> ready(WidgetTester t, {TargetPlatform platform = TargetPlatform.android}) async {
      final app = await AppState.boot();
      final check = UpdateCheck(
        api: server.api(),
        platform: platform,
        web: false,
        launch: (u) async {
          opened.add(u);
          return true;
        },
      );
      await t.runAsync(check.start);
      return (app, check);
    }

    Widget host(AppState app, UpdateCheck check, Widget child) => Scope(
          state: app,
          api: check.api,
          update: check,
          onServerChange: (_) async {},
          child: MaterialApp(theme: mbLight(), home: child),
        );

    void noop(String route, [Object? arg]) {}

    testWidgets('새 판: 뜨고, 업데이트는 그 채널 주소를 열고, 나중에는 접는다', (t) async {
      installed('0.2.7', installer: 'com.android.vending');
      server.answer = _server(play: '0.2.8');
      final (app, check) = await ready(t);
      await t.pumpWidget(host(app, check, Scaffold(body: HomeScreen(go: noop))));
      await t.pump();

      /* 0.2.8 은 "팔" 로 끝나 받침이 있습니다 — "0.2.8가" 가 아닙니다. */
      expect(find.text('새 버전 0.2.8이 나왔습니다'), findsOneWidget);
      expect(find.textContaining('플레이 스토어에서 업데이트합니다'), findsOneWidget);
      /* 안내가 홈을 막지 않습니다 — 아래 카드는 그대로 */
      expect(find.text('인바디 결과지를 올려주세요'), findsOneWidget);

      await t.tap(find.widgetWithText(FilledButton, '업데이트'));
      await t.pump();
      expect(opened, [Uri.parse(_play)]);

      await t.tap(find.widgetWithText(TextButton, '나중에'));
      await t.pump();
      expect(find.textContaining('새 버전'), findsNothing);
      expect(check.dismissed, '0.2.8');
    });

    testWidgets('접은 뒤 더 새 판이 나오면 다시 뜬다 (받침 없는 판은 "가")', (t) async {
      installed('0.2.7');
      server.answer = _server(apk: '0.2.8');
      final (app, check) = await ready(t);
      await t.pumpWidget(host(app, check, Scaffold(body: HomeScreen(go: noop))));
      await t.pump();
      await t.tap(find.widgetWithText(TextButton, '나중에'));
      await t.pump();
      expect(find.textContaining('새 버전'), findsNothing);

      server.answer = _server(apk: '0.2.9');
      await t.runAsync(() => check.check(force: true));
      await t.pump();
      expect(find.text('새 버전 0.2.9가 나왔습니다'), findsOneWidget);
      /* 직접 깐 APK 는 "지우지 말고" 를 말합니다 — 지우면 기기의 기록이 사라집니다 */
      expect(find.textContaining('지금 앱을 지우지 말고 그 위에 설치해야', findRichText: true),
          findsOneWidget);
      await t.tap(find.widgetWithText(FilledButton, '업데이트'));
      await t.pump();
      expect(opened, [Uri.parse(_apk)]);
    });

    testWidgets('서버와 안 맞는 판: 뜨고, 접을 수 없고, 앱은 그대로 쓴다', (t) async {
      installed('0.2.5', installer: 'com.android.vending');
      server.answer = _server(play: '0.2.8', min: '0.2.6');
      final (app, check) = await ready(t);
      await t.pumpWidget(host(app, check, Scaffold(body: HomeScreen(go: noop))));
      await t.pump();

      expect(find.textContaining('이 버전은 이제 서버와 맞지 않습니다', findRichText: true),
          findsOneWidget);
      expect(find.textContaining('0.2.6 이상으로 업데이트해 주세요', findRichText: true),
          findsOneWidget);
      expect(find.text('나중에'), findsNothing);
      expect(find.text('인바디 결과지를 올려주세요'), findsOneWidget);
      expect(find.text('이번 주 운동'), findsOneWidget);

      await check.dismiss();
      await t.pump();
      expect(find.textContaining('이 버전은 이제 서버와 맞지 않습니다', findRichText: true),
          findsOneWidget);

      await t.tap(find.widgetWithText(FilledButton, '업데이트'));
      await t.pump();
      expect(opened, [Uri.parse(_play)]);
    });

    testWidgets('서버 값이 없으면(옛 서버 404) 아무것도 안 뜬다', (t) async {
      installed('0.2.5', installer: 'com.android.vending');
      server.answer = 404;
      final (app, check) = await ready(t);
      await t.pumpWidget(host(app, check, Scaffold(body: HomeScreen(go: noop))));
      await t.pump();
      /* 자리는 있되 높이가 0 이라 화면 밖으로 칩니다 */
      expect(find.byType(UpdateBanner, skipOffstage: false), findsOneWidget);
      expect(find.textContaining('새 버전'), findsNothing);
      expect(find.textContaining('서버와 맞지 않습니다', findRichText: true), findsNothing);
      expect(find.text('업데이트'), findsNothing);
    });

    testWidgets('TestFlight: 새 빌드는 안 알리고, 서버와 안 맞을 때만', (t) async {
      installed('0.2.7', installer: 'com.apple.testflight');
      server.answer = _server(appstore: '0.2.9');
      final (app, check) = await ready(t, platform: TargetPlatform.iOS);
      await t.pumpWidget(host(app, check, Scaffold(body: HomeScreen(go: noop))));
      await t.pump();
      expect(find.textContaining('새 버전'), findsNothing);

      server.answer = _server(appstore: '0.2.9', min: '0.2.8');
      await t.runAsync(() => check.check(force: true));
      await t.pump();
      expect(find.textContaining('TestFlight 에서 새 빌드를', findRichText: true), findsOneWidget);
      /* 아이폰에서는 안드로이드 쪽 이름이 안 나옵니다 (앱스토어 심사 2.3.10) */
      expect(find.textContaining('플레이', findRichText: true), findsNothing);
      expect(find.textContaining('APK', findRichText: true), findsNothing);
    });

    testWidgets('설정: 앱 판 · 빌드 번호 · 받은 곳', (t) async {
      installed('0.2.8', installer: null);
      server.answer = 404;
      final (app, check) = await ready(t);
      await t.pumpWidget(host(app, check, const SettingsScreen()));
      await t.pump();
      await t.scrollUntilVisible(find.textContaining('앱 버전'), 200);
      expect(find.text('앱 버전 0.2.8 (빌드 262) · 직접 설치한 APK'), findsOneWidget);
    });

    testWidgets('설정: 아이폰 sandbox 영수증(TestFlight · 심사)이면 받은 곳을 안 적는다', (t) async {
      installed('0.2.8', installer: 'com.apple.testflight');
      server.answer = 404;
      final (app, check) = await ready(t, platform: TargetPlatform.iOS);
      await t.pumpWidget(host(app, check, const SettingsScreen()));
      await t.pump();
      await t.scrollUntilVisible(find.textContaining('앱 버전'), 200);
      expect(find.text('앱 버전 0.2.8 (빌드 262)'), findsOneWidget);
      expect(find.textContaining('TestFlight'), findsNothing);
    });

    /* 로그인 · 첫 설정 화면은 홈보다 먼저 옵니다. 서버가 옛 앱을 안 받으면
       가입 · 로그인이 거기서 먼저 막히니 「서버와 안 맞음」 은 거기도 뜹니다. */
    Widget signIn(UpdateCheck check) => SignInScreen(
        api: check.api, onDone: () {}, onServerChange: (_) async {}, onSkip: () {});

    testWidgets('로그인 화면: 서버와 안 맞으면 뜨고, 새 판 소식은 안 뜬다', (t) async {
      installed('0.2.8', installer: 'com.android.vending');
      server.answer = _server(play: '0.2.9');
      final (app, check) = await ready(t);
      await t.pumpWidget(host(app, check, signIn(check)));
      await t.pump();
      expect(find.byType(UpdateBanner, skipOffstage: false), findsOneWidget);
      expect(find.textContaining('새 버전'), findsNothing);
      expect(find.text('로그인'), findsWidgets);

      server.answer = _server(play: '0.2.10', min: '0.2.9');
      await t.runAsync(() => check.check(force: true));
      await t.pump();
      expect(find.textContaining('이 버전은 이제 서버와 맞지 않습니다', findRichText: true),
          findsOneWidget);
      expect(find.text('나중에'), findsNothing);
      /* 막지 않습니다 — 로그인 없이 쓰기는 그대로 */
      await t.scrollUntilVisible(find.text('로그인 없이 쓰기'), 200,
          scrollable: find.descendant(
              of: find.byType(ListView), matching: find.byType(Scrollable)).first);
      expect(find.text('로그인 없이 쓰기'), findsOneWidget);
    });

    testWidgets('첫 설정 화면: 서버와 안 맞으면 뜬다', (t) async {
      installed('0.2.8', installer: null);
      server.answer = _server(apk: '0.2.10', min: '0.2.9');
      final (app, check) = await ready(t);
      await t.pumpWidget(host(app, check, const OnboardingScreen()));
      await t.pump();
      expect(find.textContaining('이 버전은 이제 서버와 맞지 않습니다', findRichText: true),
          findsOneWidget);
      expect(find.text('다음'), findsOneWidget);
    });
  });
}
