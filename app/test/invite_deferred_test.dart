/* =============================================================================
 * invite_deferred_test.dart — 링크만 누르면 친구 요청이 가게(주인 의견 45)
 *
 * 주인 의견 45: "친추 링크 보내면 링크만 누르면 바로 친추되게해 / 앱이 안깔려있으면 스토어로
 * 이어지게하고 / 테스트기간에는 테스트플라이트/구글그룹으로 안내해 / 모든걸 자동으로 해야해".
 *
 *   · https 링크   https://<서버>/i/<코드> 가 앱을 곧바로 열면(App Links · Universal Links) 그
 *                 주소도 초대 — **이 앱의 서버와 호스트가 같을 때만**. 끝의 / · ?noapp=1 은
 *                 봐주고, 다른 호스트 · 포트 · 스킴 · 경로 · 틀린 코드는 버린다. 앱을 연 https
 *                 링크(차갑게 켬)도, 쓰는 중에 누른 것(따뜻하게)도 한 번 보낸다.
 *   · 설치 referrer 앱이 없던 친구가 플레이에서 깔면 referrer=invite%3D<코드> — 처음 켤 때 한 번
 *                 물어 링크와 같이 쥔다(묻지 않고 보냄). 다시 켜도 다시 안 묻고, 못 물었으면
 *                 세 번까지.
 *   · 클립보드     안드로이드는 탭 화면이 처음 설 때 한 번 읽어 초대가 있으면 위의 띠로 묻고
 *                 「요청」 → 보냄. 아이폰은 **스스로 읽지 않는다**(붙여넣기 허용 창) — 칩을
 *                 눌렀을 때만(friend_add_test · tester_welcome_test).
 *   · 링크 · 요청   주인 의견 48 — https 링크 · 설치 referrer 로 온 코드는 via:'link'(곧바로
 *                 친구), 클립보드에서 고른 코드는 via 없이(코드 주인이 수락하는 요청).
 *   · 띠 · 말풍선   누를 것이 있는 안내(「로그인」 · 「요청」)는 위의 띠 — 의견 말풍선의 처음
 *                 자리와 겹치지 않는다(360×640 · 390×844, 「인바디」 단추가 있는 홈 · 없는 탭).
 * ========================================================================== */
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mybody/src/api.dart';
import 'package:mybody/src/app_state.dart';
import 'package:mybody/src/install_referrer.dart';
import 'package:mybody/src/invite_link.dart';
import 'package:mybody/src/scope.dart';
import 'package:mybody/src/screens/feedback_bubble.dart' show appFrame, feedbackBubbleHome;
import 'package:mybody/src/screens/social.dart' show inviteShareOut, inviteShareText, kMyInviteCodeKey;
import 'package:mybody/src/screens/tester_welcome.dart';
import 'package:mybody/src/shell.dart';
import 'package:mybody/src/theme.dart';
import 'package:mybody/src/ui/edge.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _server = 'https://desk.example.ts.net';

const _profile = {
  'sex': 'male', 'age': 22, 'heightCm': 187, 'activityLevel': 'moderate',
  'trainingAge': 'novice', 'daysPerWeek': 4, 'mealsPerDay': 3,
};

const _me = {
  'ok': true,
  'user': {'id': 'me', 'displayName': '나', 'inviteCode': 'ABCD2345'},
};

const _sent = {'ok': true, 'status': 'pending', 'otherId': 'u_1'};

/// 초대 페이지의 설치 단추가 클립보드에 넣는 글(서버와 같은 모양).
String _landingClip(String code) => 'Mybody 초대 $code $_server/i/$code';

/// 서버 흉내 — invite_link_test 와 같은 것. 나간 요청을 [sent] 에.
class _Server {
  _Server([Map<String, Object>? routes]) : routes = {...?routes};
  final Map<String, Object> routes;
  final sent = <(String path, Map<String, dynamic>? body)>[];

  Api api({bool signedIn = true}) {
    http.Response json(Object body, int status) => http.Response.bytes(
          utf8.encode(jsonEncode(body)), status,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
    final a = Api(
      baseUrl: _server,
      client: MockClient((req) async {
        final path = req.url.path.replaceFirst('/api', '');
        sent.add((path, req.body.isEmpty ? null : (jsonDecode(req.body) as Map).cast<String, dynamic>()));
        final v = routes[path];
        if (v is Map) return json(v, 200);
        if (v is int) return json({'ok': false}, v);
        return json({'ok': false, 'reason': '없는 길'}, 404);
      }),
    );
    if (signedIn) a.setToken('tok');
    return a;
  }

  List<Map<String, dynamic>?> bodiesTo(String path) =>
      [for (final r in sent) if (r.$1 == path) r.$2];
}

/// 가짜 기기 — 링크 길(앱을 연 링크는 흐름을 들을 때 한 번 더), 설치 referrer, 클립보드, 기종.
class _Device {
  _Device({
    this.initial,
    this.referrer,
    this.clip,
    this.platform = TargetPlatform.android,
  }) {
    ctrl = StreamController<Uri>.broadcast(onListen: () {
      final u = initial;
      if (u != null) ctrl.add(u);
    });
  }
  final Uri? initial;
  late final StreamController<Uri> ctrl;
  DateTime clock = DateTime(2026, 9, 27, 12);

  /// 설치 referrer 의 답. null 이면 referrer 길을 넘기지 않습니다(아이폰 · 옛 설치).
  String? referrer;
  bool referrerThrows = false;
  int referrerReads = 0;

  /// 클립보드의 글. null 이면 클립보드 길을 넘기지 않습니다.
  String? clip;
  int clipReads = 0;
  TargetPlatform platform;

  InviteInbox inbox() => InviteInbox(
        links: () => ctrl.stream,
        initialLink: () async => initial,
        now: () => clock,
        serverBase: () => _server,
        installReferrer: referrer == null && !referrerThrows
            ? null
            : () async {
                referrerReads++;
                if (referrerThrows) throw Exception('SERVICE_UNAVAILABLE');
                return referrer;
              },
        clipboard: clip == null
            ? null
            : () async {
                clipReads++;
                return clip;
              },
        platform: () => platform,
      );
}

Uri _https(String code, [String rest = '']) => Uri.parse('$_server/i/$code$rest');

Future<AppState> _app({bool guest = false, bool seen = true, bool scans = false, Map<String, Object> prefs = const {}}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final app = await AppState.boot();
  app.store.set({'profile': _profile, 'onboarded': true});
  if (guest) app.store.set({'guest': true});
  if (seen) markTesterWelcomeSeen(app);
  if (scans) {
    /* 측정이 있어야 홈에 「인바디」 단추(FAB)가 섭니다 — 단추가 있는 홈 · 없는 탭 둘 다에서 띠와
       말풍선을 봅니다(스낵바였을 때는 단추 위에 떠서 높이가 달랐습니다). */
    app.store.addScan({'id': 's1', 'weightKg': 86.7, 'smmKg': 38.0, 'bfmKg': 20.0,
        'pbfPct': 23.1, 'measuredAt': '2026-03-01T00:00:00.000Z'});
  }
  return app;
}

void _phone(WidgetTester t, Size size, {double text = 1.0}) {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1.0;
  t.platformDispatcher.textScaleFactorTestValue = text;
  addTearDown(t.view.reset);
  addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
}

/// 셸만(invite_link_test 와 같은 겹). [framed] 면 앱과 같은 맨 위(appFrame — 의견 말풍선 포함).
Future<void> _host(WidgetTester t,
    {required AppState app, required Api api, required InviteInbox inbox, bool framed = false}) async {
  await t.pumpWidget(Scope(
    state: app,
    api: api,
    onServerChange: (_) async {},
    child: MaterialApp(
        theme: mbLight(), builder: framed ? appFrame : edgeSafe, home: Shell(invites: inbox)),
  ));
  await t.pumpAndSettle();
}

Future<void> _settle() async {
  for (var i = 0; i < 6; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

final _prompt = find.byKey(const Key('invite-prompt'));
final _promptAction = find.byKey(const Key('invite-prompt-action'));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /* --- https 링크 — 모양 ------------------------------------------------------------- */
  group('inviteCodeFromUri — https://<서버>/i/<코드>', () {
    String? code(String link, [String? base = _server]) =>
        inviteCodeFromUri(Uri.parse(link), serverBase: base);

    test('이 앱의 서버면 받는다 — 소문자 코드 · 끝의 / · 물음표 · # · 대문자 호스트', () {
      expect(code('$_server/i/K7M2QX9D'), 'K7M2QX9D');
      expect(code('$_server/i/k7m2qx9d'), 'K7M2QX9D');
      expect(code('$_server/i/K7M2QX9D/'), 'K7M2QX9D');
      expect(code('$_server/i/K7M2QX9D?noapp=1'), 'K7M2QX9D', reason: '페이지의 「앱 없이 보기」');
      expect(code('$_server/i/K7M2QX9D#x'), 'K7M2QX9D');
      expect(code('HTTPS://DESK.EXAMPLE.TS.NET/i/K7M2QX9D'), 'K7M2QX9D');
      expect(code('$_server:443/i/K7M2QX9D'), 'K7M2QX9D', reason: 'https 의 기본 포트');
      expect(code('$_server/i/K7M2QX9D', '$_server/'), 'K7M2QX9D', reason: '서버 주소 끝의 /');
      expect(code('$_server/i/K7M2QX9D', '$_server.'), 'K7M2QX9D',
          reason: '끝에 점이 붙은 주소(tailscale status 의 꼴) — 같은 호스트');
      expect(code('https://desk.example.ts.net./i/K7M2QX9D'), 'K7M2QX9D');
    });

    test('서버 주소에 경로가 붙어 있으면 그 뒤의 /i/<코드>', () {
      const base = 'https://example.com/mybody';
      expect(code('https://example.com/mybody/i/K7M2QX9D', base), 'K7M2QX9D');
      expect(code('https://example.com/i/K7M2QX9D', base), isNull);
      expect(code('https://example.com/other/i/K7M2QX9D', base), isNull);
    });

    test('다른 호스트 · 포트 · 스킴은 버린다(다른 서버의 사람)', () {
      for (final s in [
        'https://other.example.ts.net/i/K7M2QX9D',
        'https://evil.desk.example.ts.net/i/K7M2QX9D',
        'https://desk.example.ts.net.evil.com/i/K7M2QX9D',
        'https://desk.example.ts.net:8443/i/K7M2QX9D',
        'http://desk.example.ts.net/i/K7M2QX9D',
        'ftp://desk.example.ts.net/i/K7M2QX9D',
      ]) {
        expect(code(s), isNull, reason: s);
      }
    });

    test('경로 · 코드가 틀리면 버린다', () {
      for (final s in [
        '$_server/i/',
        '$_server/i',
        '$_server/I/K7M2QX9D',
        '$_server/x/i/K7M2QX9D',
        '$_server/i/K7M2QX9D/extra',
        '$_server/invite/K7M2QX9D',
        '$_server/i/NOPE0000',
        '$_server/i/ABCD1234',
        '$_server/i/ABCD234',
        '$_server/i/ABCD23456',
        '$_server/?i=K7M2QX9D',
      ]) {
        expect(code(s), isNull, reason: s);
      }
    });

    test('서버 주소를 모르면(없음 · 빈칸 · 이상한 값) https 는 초대가 아니다 — mybody:// 는 그대로', () {
      for (final base in [null, '', '   ', 'not a url', 'mybody://invite']) {
        expect(code('$_server/i/K7M2QX9D', base), isNull, reason: '$base');
      }
      expect(code('mybody://invite/K7M2QX9D', null), 'K7M2QX9D');
    });
  });

  /* --- 클립보드 글 --------------------------------------------------------------------- */
  group('inviteCodeFromClipboard', () {
    String? code(String? text) => inviteCodeFromClipboard(text, serverBase: _server);

    test('초대 페이지가 넣은 글 · 보내기 글 · 이 서버의 초대 주소 · 「초대 <코드>」', () {
      expect(code(_landingClip('K7M2QX9D')), 'K7M2QX9D');
      expect(code(inviteShareText('K7M2QX9D', _server)), 'K7M2QX9D', reason: '카톡으로 받은 글을 통째로 복사');
      expect(code('$_server/i/k7m2qx9d'), 'K7M2QX9D');
      expect(code('이거 눌러 $_server/i/K7M2QX9D를 눌러 봐'), 'K7M2QX9D', reason: '주소 뒤에 붙은 한글');
      expect(code('($_server/i/K7M2QX9D).'), 'K7M2QX9D', reason: '괄호 · 마침표');
      expect(code('초대 K7M2QX9D'), 'K7M2QX9D');
      expect(code('초대 코드: k7m2qx9d'), 'K7M2QX9D');
      expect(code('mybody://invite/K7M2QX9D'), 'K7M2QX9D');
    });

    test('초대가 아니면 null — 다른 서버 주소 · 이름표 없는 여덟 글자 · 틀린 코드 · 빈 것', () {
      for (final s in [
        null,
        '',
        '   ',
        'https://other.example/i/K7M2QX9D',
        'K7M2QX9D 이거야',
        '주문번호 K7M2QX9D',
        '초대 NOPE0000',
        '초대 ABCD1234',
        '오늘 저녁 7시에 만나',
      ]) {
        expect(code(s), isNull, reason: '$s');
      }
    });
  });

  /* --- 설치 referrer — 모양 ------------------------------------------------------------ */
  group('inviteCodeFromReferrer', () {
    test('invite=<코드> — 한 번 더 싸인 것 · 다른 값 사이 · 소문자도', () {
      expect(inviteCodeFromReferrer('invite=K7M2QX9D'), 'K7M2QX9D');
      expect(inviteCodeFromReferrer('invite%3DK7M2QX9D'), 'K7M2QX9D', reason: '한 번 더 싸임');
      expect(inviteCodeFromReferrer('utm_source=x&invite=k7m2qx9d'), 'K7M2QX9D');
      expect(inviteCodeFromReferrer(' invite=K7M2QX9D '), 'K7M2QX9D');
    });

    test('초대가 없거나 틀리면 null', () {
      for (final r in [
        null,
        '',
        'utm_source=google-play&utm_medium=organic',
        'invite=NOPE0000',
        'invite=',
        'invite=K7M2QX9D0',
        '%E0%A4%A',
        'referrer=K7M2QX9D',
      ]) {
        expect(inviteCodeFromReferrer(r), isNull, reason: '$r');
      }
    });
  });

  /* --- 설치 referrer — 한 번 ----------------------------------------------------------- */
  group('설치 referrer', () {
    test('처음 켤 때 한 번 물어 쥔다 — 다시 켜면 다시 묻지 않는다', () async {
      SharedPreferences.setMockInitialValues({});
      final d = _Device(referrer: 'invite=K7M2QX9D');
      final a = d.inbox();
      var told = 0;
      a.addListener(() => told++);
      await a.start();
      expect(d.referrerReads, 1);
      expect(a.pending?.code, 'K7M2QX9D', reason: '묻지 않고 쥡니다 — 셸이 보냅니다');
      expect(told, 1);
      final sp = await SharedPreferences.getInstance();
      expect(sp.get(kInstallReferrerKey), 'done');
      expect(a.take(), 'K7M2QX9D');
      a.dispose();
      await _settle();

      /* 다시 켬 — referrer 는 설치에 붙은 값이라 켤 때마다 같은 것이 옵니다. */
      final b = d.inbox();
      await b.start();
      expect(d.referrerReads, 1, reason: '다시 묻지 않습니다');
      expect(b.pending, isNull);
      b.dispose();
    });

    test('초대가 없는 설치(organic)도 답을 받았으면 끝', () async {
      SharedPreferences.setMockInitialValues({});
      final d = _Device(referrer: 'utm_source=google-play&utm_medium=organic');
      final a = d.inbox();
      await a.start();
      expect(a.pending, isNull);
      expect((await SharedPreferences.getInstance()).get(kInstallReferrerKey), 'done');
      await d.inbox().start();
      expect(d.referrerReads, 1);
    });

    test('못 물었으면 다음에 켤 때 다시 — 세 번까지', () async {
      SharedPreferences.setMockInitialValues({});
      final d = _Device()..referrerThrows = true;
      for (var i = 0; i < 5; i++) {
        final a = d.inbox();
        await a.start();
        expect(a.pending, isNull);
        a.dispose();
      }
      expect(d.referrerReads, kInstallReferrerTries);
    });

    test('링크로도 같은 코드가 왔으면 한 번 — 이미 보낸 코드면 referrer 로 다시 쥐지 않는다', () async {
      SharedPreferences.setMockInitialValues({});
      final d = _Device(initial: _https('K7M2QX9D'), referrer: 'invite=K7M2QX9D');
      final a = d.inbox();
      var told = 0;
      a.addListener(() => told++);
      await a.start();
      await _settle();
      expect(a.pending?.code, 'K7M2QX9D');
      expect(told, 1);

      /* 링크로 받아 보낸 뒤 처음 묻는 referrer(업데이트 뒤 처음 켬 등) — 다시 안 쥡니다. */
      SharedPreferences.setMockInitialValues({
        'mybody.invite.handled.v1': jsonEncode(['WXYZ2345']),
      });
      final e = _Device(referrer: 'invite=WXYZ2345');
      final b = e.inbox();
      await b.start();
      expect(e.referrerReads, 1);
      expect(b.pending, isNull);
    });

    test('referrer 길을 안 넘기면(아이폰 · 시험) 묻지도 적지도 않는다', () async {
      SharedPreferences.setMockInitialValues({});
      final a = _Device().inbox();
      await a.start();
      expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
    });

    testWidgets('셸 — 깔고 처음 켜서 탭 화면이 서면 묻지 않고 보낸다, 다시 켜면 안 보낸다', (t) async {
      _phone(t, const Size(390, 844));
      final s = _Server({'/me': _me, '/friends/request': _sent});
      final app = await _app();
      final api = s.api();
      final d = _Device(referrer: 'invite=K7M2QX9D');
      final a = d.inbox();
      await a.start();
      await _host(t, app: app, api: api, inbox: a);
      expect(s.bodiesTo('/friends/request'), [
        {'inviteCode': 'K7M2QX9D', 'via': 'link'}
      ], reason: '설치 referrer 는 링크를 누르고 깐 것 — 링크와 같이 곧바로 친구');
      expect(find.text('친구 요청을 보냈어요'), findsOneWidget, reason: '말은 서버의 답대로(이 흉내 서버는 요청으로 받음)');
      expect(_prompt, findsNothing, reason: 'referrer 는 묻지 않습니다');

      await t.pumpWidget(const SizedBox());
      a.dispose();
      final b = d.inbox();
      await b.start();
      await _host(t, app: app, api: api, inbox: b);
      expect(s.bodiesTo('/friends/request'), hasLength(1));
      b.dispose();
    });
  });

  /* --- https 링크 — 셸까지 ------------------------------------------------------------- */
  group('셸 — https 초대 링크', () {
    testWidgets('앱을 연 https 링크(차갑게) — 두 길 · mybody 모양으로 겹쳐 와도 한 번, 다시 켜도 한 번', (t) async {
      _phone(t, const Size(390, 844));
      final s = _Server({'/me': _me, '/friends/request': _sent});
      final app = await _app();
      final api = s.api();
      final d = _Device(initial: _https('k7m2qx9d', '?noapp=1'));
      final a = d.inbox();
      await a.start();
      d.ctrl.add(Uri.parse('mybody://invite/K7M2QX9D'));   // 같은 코드가 다른 모양으로
      await _host(t, app: app, api: api, inbox: a);
      expect(s.bodiesTo('/friends/request'), [
        {'inviteCode': 'K7M2QX9D', 'via': 'link'}
      ]);
      expect(find.text('친구 요청을 보냈어요'), findsOneWidget);

      /* 앱이 꺼졌다 같은 링크로 다시 만들어짐(갤럭시) — 다시 안 보냅니다. */
      await t.pumpWidget(const SizedBox());
      a.dispose();
      d.clock = d.clock.add(const Duration(hours: 5));
      final b = d.inbox();
      await b.start();
      await _host(t, app: app, api: api, inbox: b);
      expect(s.bodiesTo('/friends/request'), hasLength(1));
      expect(find.byType(SnackBar), findsNothing);
      b.dispose();
    });

    testWidgets('쓰는 중에 누른 https 링크(따뜻하게)는 보내고, 다른 서버의 링크는 버린다', (t) async {
      _phone(t, const Size(390, 844));
      final s = _Server({'/me': _me, '/friends/request': _sent});
      final app = await _app();
      final d = _Device();
      final a = d.inbox();
      await a.start();
      await _host(t, app: app, api: s.api(), inbox: a);

      d.ctrl.add(Uri.parse('https://other.example.ts.net/i/WXYZ2345'));
      await t.pumpAndSettle();
      expect(s.bodiesTo('/friends/request'), isEmpty, reason: '다른 서버의 사람');
      expect(a.pending, isNull);
      expect(find.byType(SnackBar), findsNothing);

      d.ctrl.add(_https('WXYZ2345'));
      await t.pumpAndSettle();
      expect(s.bodiesTo('/friends/request'), [
        {'inviteCode': 'WXYZ2345', 'via': 'link'}
      ], reason: '다른 서버 링크로 겹침 표시가 남아 진짜 링크를 거르면 안 됩니다');
      expect(find.text('친구 요청을 보냈어요'), findsOneWidget);
    });
  });

  /* --- 클립보드 — 안드로이드는 한 번 읽고 묻는다 ------------------------------------------ */
  group('클립보드 — 안드로이드', () {
    testWidgets('탭 화면이 처음 서면 한 번 읽어 위의 띠로 묻고, 「요청」 → 보낸다', (t) async {
      _phone(t, const Size(390, 844));
      final s = _Server({'/me': _me, '/friends/request': _sent});
      final app = await _app();
      final api = s.api();
      final d = _Device(clip: _landingClip('K7M2QX9D'));
      final a = d.inbox();
      await a.start();
      await _host(t, app: app, api: api, inbox: a);

      expect(d.clipReads, 1);
      expect(_prompt, findsOneWidget);
      expect(find.text('초대 코드 K7M2QX9D 로 친구 요청할까요?'), findsOneWidget);
      expect(s.bodiesTo('/friends/request'), isEmpty, reason: '클립보드는 남의 글일 수도 — 묻고 보냅니다');

      await t.tap(_promptAction);
      await t.pumpAndSettle();
      expect(s.bodiesTo('/friends/request'), [
        {'inviteCode': 'K7M2QX9D'}
      ], reason: '클립보드의 코드는 via 없이 — 곧바로 친구가 아니라 코드 주인이 수락하는 요청(주인 의견 48)');
      expect(find.text('친구 요청을 보냈어요'), findsOneWidget);
      expect(_prompt, findsNothing);

      /* 다시 그리기 · 탭 이동 · 다시 켜기에도 다시 안 읽습니다. */
      app.store.set({'foodFavorites': ['밥']});
      await t.tap(find.widgetWithText(NavigationDestination, '친구'));
      await t.pumpAndSettle();
      await t.pumpWidget(const SizedBox());
      a.dispose();
      final b = d.inbox();
      await b.start();
      await _host(t, app: app, api: api, inbox: b);
      expect(d.clipReads, 1, reason: '이 기기에서 한 번');
      expect(_prompt, findsNothing);
      expect(s.bodiesTo('/friends/request'), hasLength(1));
      b.dispose();
    });

    testWidgets('「괜찮아요」 면 보내지 않고, 다시 묻지 않는다 · 누르지 않으면 저절로 걷힌다', (t) async {
      _phone(t, const Size(390, 844));
      final s = _Server({'/me': _me, '/friends/request': _sent});
      final app = await _app();
      final d = _Device(clip: _landingClip('K7M2QX9D'));
      final a = d.inbox();
      await a.start();
      await _host(t, app: app, api: s.api(), inbox: a);
      expect(_prompt, findsOneWidget);
      await t.tap(find.byKey(const Key('invite-prompt-dismiss')));
      await t.pumpAndSettle();
      expect(_prompt, findsNothing);
      expect(s.bodiesTo('/friends/request'), isEmpty);
      expect(a.pending, isNull);

      /* 저절로 걷히기 — 새 기기에서 다시. */
      await t.pumpWidget(const SizedBox());
      final app2 = await _app();
      final d2 = _Device(clip: _landingClip('WXYZ2345'));
      final b = d2.inbox();
      await b.start();
      await _host(t, app: app2, api: s.api(), inbox: b);
      expect(_prompt, findsOneWidget);
      await t.pump(const Duration(seconds: 16));
      await t.pumpAndSettle();
      expect(_prompt, findsNothing, reason: '쓰던 화면을 계속 가리지 않게');
      expect(s.bodiesTo('/friends/request'), isEmpty);
    });

    testWidgets('초대가 아닌 글이면 묻지 않는다 — 그래도 읽는 것은 한 번', (t) async {
      _phone(t, const Size(390, 844));
      final s = _Server({'/me': _me, '/friends/request': _sent});
      final app = await _app();
      final d = _Device(clip: '주문번호 K7M2QX9D');
      final a = d.inbox();
      await a.start();
      await _host(t, app: app, api: s.api(), inbox: a);
      expect(d.clipReads, 1);
      expect(_prompt, findsNothing);
      final sp = await SharedPreferences.getInstance();
      expect(sp.getBool(kInviteClipboardKey), isTrue);
    });

    testWidgets('referrer · 링크로 이미 받은 코드면 묻지 않는다 — 요청은 한 번', (t) async {
      _phone(t, const Size(390, 844));
      final s = _Server({'/me': _me, '/friends/request': _sent});
      final app = await _app();
      final d = _Device(referrer: 'invite=K7M2QX9D', clip: _landingClip('K7M2QX9D'));
      final a = d.inbox();
      await a.start();
      await _host(t, app: app, api: s.api(), inbox: a);
      expect(s.bodiesTo('/friends/request'), hasLength(1));
      expect(d.clipReads, 1);
      expect(_prompt, findsNothing, reason: '같은 요청을 두 번 권하지 않습니다');
    });

    testWidgets('테스터 인사가 뜨는 차례면 닫힌 뒤에 묻는다', (t) async {
      _phone(t, const Size(390, 844));
      final s = _Server({'/me': _me, '/friends/request': _sent});
      final app = await _app(seen: false);
      final d = _Device(clip: _landingClip('K7M2QX9D'));
      final a = d.inbox();
      await a.start();
      await _host(t, app: app, api: s.api(), inbox: a);
      expect(find.byType(TesterWelcomeSheet), findsOneWidget);
      expect(d.clipReads, 0, reason: '인사가 떠 있는 동안은 기다립니다');
      expect(_prompt, findsNothing);

      await t.tap(find.byKey(const Key('welcome-skip')));
      await t.pumpAndSettle();
      expect(d.clipReads, 1);
      expect(_prompt, findsOneWidget);
    });

    /* 인사 3쪽 「카톡 등으로 보내기」 → 공유 시트의 「복사」 로 **내** 초대 글이 클립보드에 남은 채
       인사를 닫으면, 바로 그때가 클립보드를 읽는 한 번입니다. 내 코드는 친구의 초대가 아닙니다. */
    testWidgets('인사에서 내 초대 글을 보내고(복사) 닫으면 — 내 코드는 묻지 않는다', (t) async {
      _phone(t, const Size(390, 844));
      final s = _Server({'/me': _me, '/friends/request': _sent});
      final app = await _app(seen: false);
      final d = _Device(clip: '');
      final before = inviteShareOut;
      inviteShareOut = (text, origin) async => d.clip = text;   // 공유 시트의 「복사」
      addTearDown(() => inviteShareOut = before);
      final a = d.inbox();
      await a.start();
      await _host(t, app: app, api: s.api(), inbox: a);
      expect(find.byType(TesterWelcomeSheet), findsOneWidget);
      final primary = find.byKey(const Key('welcome-primary'));
      for (var i = 0; i < 2; i++) {
        await t.tap(primary);
        await t.pumpAndSettle();
      }
      await t.tap(find.byKey(const Key('welcome-share')));
      await t.pumpAndSettle();
      expect(d.clip, inviteShareText('ABCD2345', _server), reason: '내 초대 글이 클립보드에');
      expect(inviteCodeFromClipboard(d.clip, serverBase: _server), 'ABCD2345',
          reason: '글만 보면 초대입니다 — 내 것인지는 적어 둔 코드로 가립니다');
      expect((await SharedPreferences.getInstance()).getString(kMyInviteCodeKey), 'ABCD2345');

      await t.tap(primary);   // 「시작하기」 — 인사를 닫음
      await t.pumpAndSettle();
      expect(find.byType(TesterWelcomeSheet), findsNothing);
      expect(d.clipReads, 1, reason: '읽는 한 번은 이때');
      expect(_prompt, findsNothing, reason: '「초대 코드 <내 코드> 로 친구 요청할까요?」 를 묻지 않습니다');
      expect(s.bodiesTo('/friends/request'), isEmpty);
    });

    testWidgets('내 코드는 빼도 친구의 초대는 묻는다(적어 둔 내 코드와 다르면)', (t) async {
      _phone(t, const Size(390, 844));
      final s = _Server({'/me': _me, '/friends/request': _sent});
      final app = await _app(prefs: {kMyInviteCodeKey: 'ABCD2345'});
      final d = _Device(clip: _landingClip('K7M2QX9D'));
      final a = d.inbox();
      await a.start();
      await _host(t, app: app, api: s.api(), inbox: a);
      expect(find.text('초대 코드 K7M2QX9D 로 친구 요청할까요?'), findsOneWidget);
    });

    testWidgets('로그인 없이 쓰는 중에 「요청」 → 「로그인하면 친구 요청이 가요」 → 로그인하면 보낸다', (t) async {
      _phone(t, const Size(390, 844));
      final s = _Server({'/me': _me, '/friends/request': _sent});
      final app = await _app(guest: true);
      final api = s.api(signedIn: false);
      final d = _Device(clip: _landingClip('K7M2QX9D'));
      final a = d.inbox();
      await a.start();
      await _host(t, app: app, api: api, inbox: a);
      await t.tap(_promptAction);
      await t.pumpAndSettle();
      expect(find.text('로그인하면 친구 요청이 가요'), findsOneWidget);
      expect(a.pending?.code, 'K7M2QX9D');
      expect(s.bodiesTo('/friends/request'), isEmpty);

      await api.setToken('tok');
      await t.pumpAndSettle();
      expect(s.bodiesTo('/friends/request'), [
        {'inviteCode': 'K7M2QX9D'}
      ]);
    });
  });

  /* --- 클립보드 — 아이폰은 스스로 읽지 않는다 ---------------------------------------------- */
  testWidgets('아이폰 — 탭 화면이 서도 클립보드를 읽지 않고, 묻지도 적지도 않는다', (t) async {
    _phone(t, const Size(390, 844));
    final s = _Server({'/me': _me, '/friends/request': _sent});
    final app = await _app();
    final d = _Device(clip: _landingClip('K7M2QX9D'), platform: TargetPlatform.iOS);
    final a = d.inbox();
    await a.start();
    await _host(t, app: app, api: s.api(), inbox: a);
    await t.tap(find.widgetWithText(NavigationDestination, '친구'));
    await t.pumpAndSettle();
    expect(d.clipReads, 0, reason: '읽는 순간 「붙여넣기 허용」 창이 뜹니다');
    expect(_prompt, findsNothing);
    expect(s.bodiesTo('/friends/request'), isEmpty);
    final sp = await SharedPreferences.getInstance();
    expect(sp.containsKey(kInviteClipboardKey), isFalse);
    expect(await a.clipboardInviteOnce(), isNull);
    expect(d.clipReads, 0);
  });

  /* --- 누를 것이 있는 안내 vs 의견 말풍선 --------------------------------------------------
     예전엔 「로그인하면 친구 요청이 가요」(지금은 링크면 「로그인하면 바로 친구가 돼요」)가 스낵바였고, 스낵바는 「인바디」 단추 위에 떠서
     오른쪽 끝의 「로그인」 을 그 바로 위의 말풍선(그때의 처음 자리 — 「인바디」 단추 바로 위)이 덮었습니다.
     처음 자리는 이제 오른쪽 가장자리, 앱바 밑 ~ 탭바 위의 한가운데(feedback_bubble.dart)라 앱바 바로 밑의
     띠와 가장 가깝습니다 — 띠가 가장 두꺼워지는 360×640 · 글자 1.3배에서도 띠 아래 끝이 말풍선보다 위입니다. */
  group('위의 띠는 의견 말풍선의 처음 자리와 겹치지 않는다', () {
    for (final (size, text) in const [
      (Size(360, 640), 1.0),
      (Size(390, 844), 1.0),
      (Size(360, 640), 1.3),
    ]) {
      final name = '${size.width.toInt()}×${size.height.toInt()}${text == 1.0 ? '' : ' · 글자 $text배'}';

      void clear(WidgetTester t, String where) {
        final hit = t.getRect(find.byKey(const Key('feedback-bubble')));
        final home = feedbackBubbleHome(size, EdgeInsets.zero);
        expect(hit, Rect.fromCenter(center: home, width: 48, height: 48), reason: '말풍선은 처음 자리');
        final action = t.getRect(_promptAction);
        expect(action.overlaps(hit), isFalse, reason: '$where: 단추 $action · 말풍선 $hit');
        final banner = t.getRect(_prompt);
        expect(banner.overlaps(hit), isFalse, reason: '$where: 띠 $banner · 말풍선 $hit');
        expect(action.bottom, lessThanOrEqualTo(size.height));
        expect(action.right, lessThanOrEqualTo(size.width));
      }

      testWidgets('$name — 「로그인」(로그인 없이 쓰는 중)', (t) async {
        _phone(t, size, text: text);
        final s = _Server({'/me': _me, '/friends/request': _sent});
        final app = await _app(guest: true, scans: true);
        final d = _Device(initial: _https('K7M2QX9D'));
        final a = d.inbox();
        await a.start();
        await _host(t, app: app, api: s.api(signedIn: false), inbox: a, framed: true);
        expect(find.byType(FloatingActionButton), findsOneWidget, reason: '「인바디」 단추가 있는 홈 — 스낵바였다면 그 위');
        expect(find.text('로그인하면 바로 친구가 돼요'), findsOneWidget, reason: 'https 링크로 온 초대');
        clear(t, '홈');
        await t.tap(find.widgetWithText(NavigationDestination, '식단'));
        await t.pumpAndSettle();
        expect(find.byType(FloatingActionButton), findsNothing);
        clear(t, '단추 없는 탭');
        expect(t.takeException(), isNull);
      });

      testWidgets('$name — 「요청」(클립보드의 초대)', (t) async {
        _phone(t, size, text: text);
        final s = _Server({'/me': _me, '/friends/request': _sent});
        final app = await _app(scans: true);
        final d = _Device(clip: _landingClip('K7M2QX9D'));
        final a = d.inbox();
        await a.start();
        await _host(t, app: app, api: s.api(), inbox: a, framed: true);
        expect(find.byType(FloatingActionButton), findsOneWidget);
        clear(t, '홈');
        await t.tap(_promptAction);
        await t.pumpAndSettle();
        expect(s.bodiesTo('/friends/request'), hasLength(1), reason: '말풍선이 아니라 「요청」 이 눌립니다');
        expect(t.takeException(), isNull);
      });
    }
  });
}
