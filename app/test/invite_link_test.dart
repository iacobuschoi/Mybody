/* =============================================================================
 * invite_link_test.dart — 친구 코드 모양 · 보내는 글 · 초대 링크로 앱이 열렸을 때
 *
 * 주인 의견 두 가지를 못 박습니다.
 *   43 "친구 탭에서도 코드 보내기를 만들어서 링크 받으면 요청이 가게" — 링크(mybody://invite/
 *      <코드>)를 받으면 앱이 **한 번** 요청을 보내고 결과를 한 줄로 알린다.
 *   44 "갤럭시인데 아이폰 친구가 보낸 초대가 TestFlight 로 뜸" — 보내는 글에 설치 주소가 없다
 *      (기기는 링크의 페이지가 가린다).
 *
 *   · 코드 모양   cleanInviteCode · isInviteCode — 서버와 같은 글자판(I · O · 0 · 1 없음) 여덟
 *                글자, 소문자는 대문자로, 받은 글(링크 · 「코드: …」)에서 코드만, 틀린 것은 틀림.
 *                입력 칸 다듬기(InviteCodeFormatter) — 붙여 넣으면 코드만, 여덟 글자까지.
 *   · 보내는 글   inviteShareText — 링크 한 줄과 코드 한 줄, 설치 주소 없음.
 *   · 요청 · 답   requestFriendByCode 는 틀린 모양을 서버에 안 묻는다 · friendRequestMessage.
 *   · 링크 받기   inviteCodeFromUri · InviteInbox — 저장 · 7일 · 겹침 거르기 · 꺼내면 비움.
 *                https://<서버>/i/<코드> 는 이 앱의 서버와 호스트가 같을 때만(자세한 것은
 *                invite_deferred_test.dart — 주인 의견 45).
 *   · 셸         로그인 · 탭 화면이면 한 번 보내고 스낵바 · 로그인 없이면 안내 한 번(위의 띠 ·
 *                「로그인」) → 로그인하면 보냄 · 지난 것은 버림 · 겹친 링크 · 다시 그리기 ·
 *                돌아오기에도 한 번 · 서버의 까닭 · 테스터 인사가 뜨면 닫힌 뒤에.
 *   · 설정 파일   AndroidManifest · Info.plist 에 mybody 스킴이 있고 Flutter 딥링크는 꺼짐.
 *   · main.dart  넘긴 링크 길이 셸까지 간다.
 * ========================================================================== */
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mybody/main.dart' show MyBodyApp;
import 'package:mybody/src/api.dart';
import 'package:mybody/src/app_state.dart';
import 'package:mybody/src/invite_link.dart';
import 'package:mybody/src/scope.dart';
import 'package:mybody/src/screens/account.dart' show SignInScreen;
import 'package:mybody/src/screens/social.dart';
import 'package:mybody/src/screens/tester_welcome.dart';
import 'package:mybody/src/shell.dart';
import 'package:mybody/src/theme.dart';
import 'package:mybody/src/ui/edge.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _profile = {
  'sex': 'male', 'age': 22, 'heightCm': 187, 'activityLevel': 'moderate',
  'trainingAge': 'novice', 'daysPerWeek': 4, 'mealsPerDay': 3,
};

const _me = {
  'ok': true,
  'user': {'id': 'me', 'displayName': '나', 'inviteCode': 'ABCD2345'},
};

const _pendingKey = 'mybody.invite.pending.v1';

/// 서버 흉내. [routes] 의 값이 Map 이면 200 + 그 몸, 없으면 404. 나간 요청을 [sent] 에.
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
      baseUrl: 'https://x.test',
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

/// 가짜 링크 길 — app_links 대신. [initial] 은 앱을 연 링크.
///
/// 진짜 app_links 처럼 흐름을 듣기 시작하면 앱을 연 링크를 **흐름으로도 한 번** 줍니다
/// (안드로이드 · 아이폰 플러그인의 onListen). 받는 곳이 흐름부터 들으면 그쪽이 먼저 와서
/// "앱을 연 링크" 인지 모르고 받습니다 — 그 차례를 시험이 봐야 합니다.
class _Links {
  _Links({this.initial}) {
    ctrl = StreamController<Uri>.broadcast(onListen: () {
      final u = initial;
      if (u != null) ctrl.add(u);
    });
  }
  final Uri? initial;

  /// 이 앱의 서버 주소 — https 초대 링크의 호스트를 견줍니다(시험 서버와 같은 주소).
  static const server = 'https://x.test';
  late final StreamController<Uri> ctrl;
  DateTime clock = DateTime(2026, 9, 27, 12);

  InviteInbox inbox() => InviteInbox(
        links: () => ctrl.stream,
        initialLink: () async => initial,
        now: () => clock,
        serverBase: () => server,
      );
}

Uri _link(String code) => Uri.parse('mybody://invite/$code');

Future<AppState> _app({bool guest = false, bool seen = true, Map<String, Object> prefs = const {}}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final app = await AppState.boot();
  app.store.set({'profile': _profile, 'onboarded': true});
  if (guest) app.store.set({'guest': true});
  if (seen) markTesterWelcomeSeen(app);
  return app;
}

void _phone(WidgetTester t, Size size, {double text = 1.0}) {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1.0;
  t.platformDispatcher.textScaleFactorTestValue = text;
  addTearDown(t.view.reset);
  addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
}

Future<void> _host(WidgetTester t, {required AppState app, required Api api, required InviteInbox inbox}) async {
  await t.pumpWidget(Scope(
    state: app,
    api: api,
    onServerChange: (_) async {},
    child: MaterialApp(theme: mbLight(), builder: edgeSafe, home: Shell(invites: inbox)),
  ));
  await t.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /* --- 코드 모양 ---------------------------------------------------------------- */
  group('친구 코드 모양', () {
    test('isInviteCode — 서버의 글자판 여덟 글자만(I · O · 0 · 1 없음, 대문자)', () {
      expect(kInviteCodeAlphabet, 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789', reason: 'server/db.js inviteCode()');
      expect(kInviteCodeAlphabet.length, 32);
      for (final ok in ['ABCD2345', 'K7M2QX9D', 'ZZZZ9999', kInviteCodeExample]) {
        expect(isInviteCode(ok), isTrue, reason: ok);
      }
      for (final bad in ['', 'ab12cd', 'ABCD234', 'ABCD23456', 'abcd2345', 'NOPE0000', 'ABCDI234',
          'ABCD1234', 'ABCD 234', 'ABCD-234', '가나다라마바사아']) {
        expect(isInviteCode(bad), isFalse, reason: bad);
      }
    });

    test('칸의 예시는 실제 모양 — 옛 「ab12cd」 가 아니다', () {
      expect(isInviteCode(kInviteCodeExample), isTrue);
      expect(kInviteCodeExample, isNot('AB12CD'));
    });

    test('cleanInviteCode — 코드만 넣으면 빈칸 · 줄표를 빼고 대문자로', () {
      expect(cleanInviteCode('K7M2QX9D'), 'K7M2QX9D');
      expect(cleanInviteCode(' k7m2qx9d '), 'K7M2QX9D', reason: '소문자는 대문자로');
      expect(cleanInviteCode('K7M2 QX9D'), 'K7M2QX9D');
      expect(cleanInviteCode('k7m2-qx9d'), 'K7M2QX9D');
      expect(cleanInviteCode('   '), '');
    });

    test('cleanInviteCode — 받은 글을 통째로 붙여도 코드만(링크 · 「코드 …」 · 옛 「코드: …」)', () {
      const base = 'https://desk.example.ts.net';
      expect(cleanInviteCode(inviteShareText('K7M2QX9D', base)), 'K7M2QX9D', reason: '지금 보내는 글');
      expect(cleanInviteCode('이거 눌러 https://desk.example.ts.net/i/k7m2qx9d ㅎㅎ'), 'K7M2QX9D',
          reason: '링크만 · 소문자');
      expect(cleanInviteCode('https://desk.example.ts.net/i/K7M2QX9D?noapp=1'), 'K7M2QX9D');
      expect(cleanInviteCode('친구 추가에 코드 K7M2QX9D 를 넣어도 돼요'), 'K7M2QX9D');
      expect(cleanInviteCode('Mybody 같이 해요! 내 친구 코드: WXYZ2345\n아이폰: https://testflight.apple.com/join/abc'),
          'WXYZ2345', reason: '옛 글');
      expect(cleanInviteCode('내 코드：wxyz2345'), 'WXYZ2345', reason: '전각 쌍점');
      expect(cleanInviteCode('K7M2QX9D 이거야'), 'K7M2QX9D', reason: '이름표 없이 코드 토막만');
    });

    test('cleanInviteCode — 못 찾으면 다듬은 글 그대로(틀린 모양)', () {
      expect(cleanInviteCode(' ab12cd '), 'AB12CD');
      expect(isInviteCode(cleanInviteCode(' ab12cd ')), isFalse);
      expect(isInviteCode(cleanInviteCode('NOPE0000')), isFalse);
      expect(isInviteCode(cleanInviteCode('https://x.test/i/NOPE0000')), isFalse,
          reason: '링크 속이어도 글자판 밖이면 틀림');
    });

    group('InviteCodeFormatter — 입력 칸', () {
      const f = InviteCodeFormatter();
      TextEditingValue typed(String s, {TextRange composing = TextRange.empty}) => f.formatEditUpdate(
          TextEditingValue.empty,
          TextEditingValue(text: s, selection: TextSelection.collapsed(offset: s.length), composing: composing));

      test('소문자는 대문자로, 빈칸 · 줄표 · 한글은 빼고, 여덟 글자까지', () {
        expect(typed('k7m').text, 'K7M');
        expect(typed('k7m2 qx-9').text, 'K7M2QX9');
        expect(typed('K7M2QX9DZ').text, 'K7M2QX9D');
        expect(typed('K7M2QX9D').text, 'K7M2QX9D');
      });

      test('받은 글을 붙여 넣으면 앞머리가 아니라 코드만', () {
        expect(typed(inviteShareText('K7M2QX9D', 'https://x.test')).text, 'K7M2QX9D');
        expect(typed('Mybody 같이 해요! 내 친구 코드: QRST6789').text, 'QRST6789');
      });

      test('대문자로만 바뀌면 커서는 그 자리 · 조합 중에는 손대지 않는다', () {
        final v = f.formatEditUpdate(TextEditingValue.empty,
            const TextEditingValue(text: 'k7m2', selection: TextSelection.collapsed(offset: 1)));
        expect(v.text, 'K7M2');
        expect(v.selection.baseOffset, 1);
        final c = typed('k7', composing: const TextRange(start: 1, end: 2));
        expect(c.text, 'k7', reason: '조합 중(밑줄)인 글자를 바꾸면 키보드가 글자를 두 번 넣기도 합니다');
      });
    });
  });

  /* --- 보내는 글 --------------------------------------------------------------- */
  group('보내는 글', () {
    test('링크 한 줄과 코드 한 줄 — 설치 주소는 없다(주인 의견 44)', () {
      expect(inviteShareText('K7M2QX9D', 'https://desk.example.ts.net'),
          'Mybody 같이 해요! 링크를 누르면 친구 요청이 가요\n'
          'https://desk.example.ts.net/i/K7M2QX9D\n'
          '(앱에서 친구 탭 → 친구 추가에 코드 K7M2QX9D 를 넣어도 돼요)');
      final s = inviteShareText('K7M2QX9D', 'https://desk.example.ts.net');
      for (final w in ['testflight', 'play.google', 'groups.google', '아이폰:', '안드로이드:']) {
        expect(s, isNot(contains(w)), reason: w);
      }
    });

    test('주소 끝 / 는 떼고, 코드는 대문자로', () {
      expect(inviteUrl('https://x.test/', 'k7m2qx9d'), 'https://x.test/i/K7M2QX9D');
      expect(inviteShareText('k7m2qx9d', 'https://x.test//').split('\n')[1], 'https://x.test/i/K7M2QX9D');
    });

    test('서버 주소가 없으면 링크 없이 코드와 넣을 곳', () {
      final s = inviteShareText('K7M2QX9D', '');
      expect(s, isNot(contains('/i/')));
      expect(s, contains('K7M2QX9D'));
      expect(cleanInviteCode(s), 'K7M2QX9D');
    });
  });

  /* --- 요청 · 답 ---------------------------------------------------------------- */
  group('요청 · 답', () {
    test('requestFriendByCode — 틀린 모양은 서버에 묻지 않고, 맞으면 대문자로 보낸다', () async {
      final s = _Server({'/friends/request': {'ok': true, 'status': 'pending'}});
      final api = s.api();
      expect(await requestFriendByCode(api, '  '), isNull, reason: '빈 칸은 취소와 같음');
      final bad = await requestFriendByCode(api, 'ab12cd');
      expect(bad!.ok, isFalse);
      expect(bad.reason, kInviteCodeInvalid);
      expect(s.bodiesTo('/friends/request'), isEmpty);
      final ok = await requestFriendByCode(api, 'https://x.test/i/k7m2qx9d');
      expect(ok!.ok, isTrue);
      expect(s.bodiesTo('/friends/request'), [
        {'inviteCode': 'K7M2QX9D'}
      ]);
    });

    test('friendRequestMessage — 보냄 · 맺어짐 · 이름 · 흔한 실패 셋은 앱 말투, 나머지는 서버의 까닭', () {
      ApiResult ok(Map<String, dynamic> b) => ApiResult(200, {'ok': true, ...b});
      ApiResult no(String reason) => ApiResult(200, {'ok': false, 'reason': reason});
      expect(friendRequestMessage(ok({'status': 'pending', 'otherId': 'u_1'})), '친구 요청을 보냈어요');
      expect(friendRequestMessage(ok({'status': 'accepted'})), '친구가 됐어요');
      expect(friendRequestMessage(ok({'status': 'pending', 'displayName': '민수'})), '민수님에게 친구 요청을 보냈어요');
      expect(friendRequestMessage(ok({'status': 'accepted', 'other': {'displayName': '민수'}})), '민수님과 친구가 됐어요');
      expect(friendRequestMessage(no('이미 친구입니다')), '이미 친구예요');
      expect(friendRequestMessage(no('자기 자신은 추가할 수 없습니다')), '내 코드예요');
      expect(friendRequestMessage(no('이미 보낸 요청입니다')), '이미 요청을 보냈어요');
      expect(friendRequestMessage(no('그런 코드를 가진 사람이 없습니다')), '그런 코드를 가진 사람이 없습니다');
      expect(friendRequestMessage(const ApiResult(0, {})), '서버에 닿지 못했습니다 — 컴퓨터가 꺼져 있을 수 있습니다');
    });
  });

  /* --- 링크 받기 ---------------------------------------------------------------- */
  group('inviteCodeFromUri', () {
    test('mybody://invite/<코드> — 소문자 · 끝의 / 는 괜찮고, 모양이 틀리면 null', () {
      expect(inviteCodeFromUri(_link('K7M2QX9D')), 'K7M2QX9D');
      expect(inviteCodeFromUri(Uri.parse('mybody://invite/k7m2qx9d/')), 'K7M2QX9D');
      expect(inviteCodeFromUri(Uri.parse('MYBODY://INVITE/K7M2QX9D')), 'K7M2QX9D');
      for (final s in [
        'mybody://invite/',
        'mybody://invite/NOPE0000',
        'mybody://invite/K7M2QX9D/extra',
        'mybody://other/K7M2QX9D',
        'https://x.test/i/K7M2QX9D',   // 서버 주소를 안 주면 https 는 초대가 아님
        'otherapp://invite/K7M2QX9D',
      ]) {
        expect(inviteCodeFromUri(Uri.parse(s)), isNull, reason: s);
      }
      expect(inviteCodeFromUri(null), isNull);
    });

    test('https://<서버>/i/<코드> — 이 앱의 서버 주소를 주면 받는다', () {
      expect(inviteCodeFromUri(Uri.parse('https://x.test/i/K7M2QX9D'), serverBase: 'https://x.test'),
          'K7M2QX9D');
      expect(inviteCodeFromUri(Uri.parse('https://x.test/i/K7M2QX9D'), serverBase: 'https://other.test'),
          isNull, reason: '다른 서버');
    });
  });

  group('InviteInbox', () {
    test('받은 코드를 받은 시각과 함께 적어 두고, 다시 켜도 남는다', () async {
      SharedPreferences.setMockInitialValues({});
      final l = _Links();
      final a = l.inbox();
      await a.start();
      expect(a.pending, isNull);
      var told = 0;
      a.addListener(() => told++);
      expect(await a.receive(_link('k7m2qx9d')), isTrue);
      expect(told, 1);
      expect(a.pending!.code, 'K7M2QX9D');
      expect(a.pending!.at, l.clock);
      final sp = await SharedPreferences.getInstance();
      expect(jsonDecode(sp.getString(_pendingKey)!), {'code': 'K7M2QX9D', 'at': l.clock.millisecondsSinceEpoch});

      /* 다시 켠 것처럼 — 새 받는 곳이 저장된 것을 읽습니다. */
      final b = l.inbox();
      await b.start();
      expect(b.pending?.code, 'K7M2QX9D');
      expect(await b.receive(Uri.parse('https://other.test/i/WXYZ2345')), isFalse, reason: '다른 서버의 링크');
      expect(await b.receive(Uri.parse('https://x.test/about')), isFalse, reason: '초대 링크가 아님');
      expect(await b.receive(_link('NOPE0000')), isFalse, reason: '모양이 틀림');
      expect(b.pending?.code, 'K7M2QX9D');
    });

    test('꺼내면 비운다 — 두 번 꺼낼 수 없다', () async {
      SharedPreferences.setMockInitialValues({});
      final a = _Links().inbox();
      await a.start();
      await a.receive(_link('K7M2QX9D'));
      expect(a.take(), 'K7M2QX9D');
      expect(a.take(), isNull);
      expect(a.pending, isNull);
      final sp = await SharedPreferences.getInstance();
      await Future<void>.delayed(Duration.zero);
      expect(sp.getString(_pendingKey), isNull, reason: '다시 켜도 또 안 보내게 저장소에서도');
    });

    test('7일이 지나면 버린다 — 저장된 것도, 쥐고 있던 것도', () async {
      final l = _Links();
      final old = l.clock.subtract(const Duration(days: 7, minutes: 1));
      SharedPreferences.setMockInitialValues({
        _pendingKey: jsonEncode({'code': 'K7M2QX9D', 'at': old.millisecondsSinceEpoch}),
      });
      final a = l.inbox();
      await a.start();
      expect(a.pending, isNull);
      expect(a.take(), isNull);

      await a.receive(_link('WXYZ2345'));
      l.clock = l.clock.add(const Duration(days: 6, hours: 23));
      expect(a.pending?.code, 'WXYZ2345', reason: '아직 7일 안');
      l.clock = l.clock.add(const Duration(hours: 2));
      expect(a.pending, isNull);
    });

    test('앱을 연 링크가 두 길(getInitialLink · uriLinkStream)로 와도 하나', () async {
      SharedPreferences.setMockInitialValues({});
      final l = _Links(initial: _link('K7M2QX9D'));
      final a = l.inbox();
      var told = 0;
      a.addListener(() => told++);
      await a.start();
      l.ctrl.add(_link('K7M2QX9D'));   // 듣기 시작할 때 스트림이 한 번 더 주는 것
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(a.pending?.code, 'K7M2QX9D');
      expect(told, 1);
      /* 한참 뒤에 같은 링크를 다시 누른 것은 새로 누른 것입니다. */
      l.clock = l.clock.add(const Duration(minutes: 1));
      l.ctrl.add(_link('K7M2QX9D'));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(told, 2);
    });

    test('로그인 안내는 한 번 — 적어 두어 다시 켜도, 새로 누르면 다시', () async {
      SharedPreferences.setMockInitialValues({});
      final l = _Links();
      final a = l.inbox();
      await a.start();
      await a.receive(_link('K7M2QX9D'));
      expect(a.pending!.prompted, isFalse);
      a.markPrompted();
      expect(a.pending!.prompted, isTrue);
      await Future<void>.delayed(Duration.zero);
      final b = l.inbox();
      await b.start();
      expect(b.pending!.prompted, isTrue);
      l.clock = l.clock.add(const Duration(minutes: 1));
      await b.receive(_link('K7M2QX9D'));
      expect(b.pending!.prompted, isFalse);
    });

    /* 링크로 켜진 앱이 뒤에서 꺼졌다가(갤럭시는 자주 끕니다) 아이콘으로 열리면, 안드로이드는
       화면을 그 링크로 다시 만들고 app_links 는 그것을 또 "앱을 연 링크" 로 줍니다. */
    Future<void> settle() async {
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    test('되살아난 앱 여는 링크 — 이미 꺼내 간 코드면 다시 안 받고, 쓰는 중에 누른 것은 받는다', () async {
      SharedPreferences.setMockInitialValues({});
      final l = _Links(initial: _link('K7M2QX9D'));
      final a = l.inbox();
      await a.start();
      await settle();
      expect(a.pending?.code, 'K7M2QX9D');
      expect(a.take(), 'K7M2QX9D');
      a.dispose();
      await settle();

      /* 몇 시간 뒤, 앱이 꺼졌다가 같은 링크로 다시 만들어짐 — 두 길(처음 링크 · 흐름) 다. */
      l.clock = l.clock.add(const Duration(hours: 5));
      final b = l.inbox();
      var told = 0;
      b.addListener(() => told++);
      await b.start();
      l.ctrl.add(_link('K7M2QX9D'));
      await settle();
      expect(b.pending, isNull, reason: '켤 때마다 요청이 또 가면 「이미 요청을 보냈어요」 가 뜹니다');
      expect(told, 0);

      /* 앱을 쓰는 중에 같은 링크를 다시 누른 것은 받습니다 — 누른 사람은 답을 봐야 합니다. */
      l.clock = l.clock.add(const Duration(minutes: 1));
      l.ctrl.add(_link('K7M2QX9D'));
      await settle();
      expect(b.pending?.code, 'K7M2QX9D');
      expect(told, 1);
      b.dispose();
    });

    test('서버에 못 닿아 못 보냈으면(unsent) 되살아난 링크로 다시 받는다', () async {
      SharedPreferences.setMockInitialValues({});
      final l = _Links(initial: _link('K7M2QX9D'));
      final a = l.inbox();
      await a.start();
      await settle();
      expect(a.take(), 'K7M2QX9D');
      a.unsent('K7M2QX9D');
      a.dispose();
      await settle();

      final b = l.inbox();
      await b.start();
      await settle();
      expect(b.pending?.code, 'K7M2QX9D');
      b.dispose();
    });

    test('쥐고 있던 코드(로그인 전)가 되살아나도 그대로 — 안내를 다시 하지 않고 받은 시각도 그대로', () async {
      SharedPreferences.setMockInitialValues({});
      final l = _Links(initial: _link('K7M2QX9D'));
      final first = l.clock;
      final a = l.inbox();
      await a.start();
      await settle();
      a.markPrompted();
      a.dispose();
      await settle();

      l.clock = l.clock.add(const Duration(hours: 3));
      final b = l.inbox();
      await b.start();
      await settle();
      expect(b.pending?.code, 'K7M2QX9D');
      expect(b.pending!.prompted, isTrue);
      expect(b.pending!.at, first);
      b.dispose();
    });

    test('꺼내 간 코드는 최근 20개까지만 적어 둔다', () async {
      SharedPreferences.setMockInitialValues({});
      final codes = [for (var i = 0; i < 21; i++) 'ABCDEF${kInviteCodeAlphabet[i]}2'];
      final l = _Links();
      final a = l.inbox();
      await a.start();
      for (final c in codes) {
        await a.receive(_link(c));
        expect(a.take(), c);
      }
      a.dispose();
      await settle();
      final sp = await SharedPreferences.getInstance();
      expect(jsonDecode(sp.getString('mybody.invite.handled.v1')!), codes.sublist(1));

      Future<bool> relaunch(String code) async {
        final b = _Links(initial: _link(code)).inbox();
        await b.start();
        await settle();
        final got = b.take() != null;
        b.dispose();
        return got;
      }

      expect(await relaunch(codes.first), isTrue, reason: '밀려난 것은 새것');
      expect(await relaunch(codes.last), isFalse);
    });

    test('저장소의 값이 깨져 있으면 없는 것으로(엉뚱한 요청을 안 보냄)', () async {
      for (final bad in ['{', jsonEncode({'code': 'NOPE0000', 'at': 1}), jsonEncode({'code': 'K7M2QX9D'})]) {
        SharedPreferences.setMockInitialValues({_pendingKey: bad});
        final a = _Links().inbox();
        await a.start();
        expect(a.pending, isNull, reason: bad);
      }
    });
  });

  /* --- 셸 — 링크로 앱이 열렸을 때 --------------------------------------------------- */
  group('셸 — 초대 링크', () {
    testWidgets('로그인 · 탭 화면이면 한 번 보내고 한 줄 — 겹친 링크 · 다시 그리기 · 돌아오기에도 한 번',
        (t) async {
      _phone(t, const Size(390, 844));
      final l = _Links(initial: _link('k7m2qx9d'));
      final s = _Server({'/me': _me, '/friends/request': {'ok': true, 'status': 'pending', 'otherId': 'u_1'}});
      final app = await _app();
      final inbox = l.inbox();
      await inbox.start();
      l.ctrl.add(_link('k7m2qx9d'));   // 같은 링크가 스트림으로 한 번 더
      await _host(t, app: app, api: s.api(), inbox: inbox);

      expect(s.bodiesTo('/friends/request'), [
        {'inviteCode': 'K7M2QX9D'}
      ]);
      expect(find.text('친구 요청을 보냈어요'), findsOneWidget);
      expect(inbox.pending, isNull, reason: '보냈으면 비웁니다');

      /* 다시 그려지고(상태 바뀜 · 탭 이동) · 앱으로 돌아오고 · 로그인 알림이 또 와도 그대로. */
      app.store.set({'foodFavorites': ['밥']});
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(NavigationDestination, '친구'));
      await t.pumpAndSettle();
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await Scope.apiOf(t.element(find.byType(Shell))).setToken('tok');
      await t.pumpAndSettle();
      expect(s.bodiesTo('/friends/request'), hasLength(1), reason: '두 번 보내면 「이미 보낸 요청」 이 뜹니다');
      expect(t.takeException(), isNull);
    });

    testWidgets('앱을 쓰는 중에 링크가 오면 그 자리에서 보낸다 — 서버의 까닭은 그대로', (t) async {
      _phone(t, const Size(390, 844));
      final l = _Links();
      final s = _Server({
        '/me': _me,
        '/friends/request': {'ok': false, 'reason': '그런 코드를 가진 사람이 없습니다'},
      });
      final inbox = l.inbox();
      final app = await _app();   // 저장소를 먼저 비웁니다 — 받는 곳이 시작하며 읽습니다
      await inbox.start();
      await _host(t, app: app, api: s.api(), inbox: inbox);
      expect(s.bodiesTo('/friends/request'), isEmpty);

      l.ctrl.add(_link('ZZZZ9999'));
      await t.pumpAndSettle();
      expect(s.bodiesTo('/friends/request'), [
        {'inviteCode': 'ZZZZ9999'}
      ]);
      expect(find.text('그런 코드를 가진 사람이 없습니다'), findsOneWidget);
      expect(inbox.pending, isNull, reason: '실패해도 한 번 — 다시 누르면 다시 갑니다');
    });

    for (final (reason, said) in const [
      ('이미 친구입니다', '이미 친구예요'),
      ('자기 자신은 추가할 수 없습니다', '내 코드예요'),
    ]) {
      testWidgets('「$reason」 → 「$said」', (t) async {
        _phone(t, const Size(390, 844));
        final l = _Links(initial: _link('ABCD2345'));
        final s = _Server({'/me': _me, '/friends/request': {'ok': false, 'reason': reason}});
        final inbox = l.inbox();
        final app = await _app();   // 저장소를 먼저 비웁니다 — 받는 곳이 시작하며 읽습니다
        await inbox.start();
        await _host(t, app: app, api: s.api(), inbox: inbox);
        expect(find.text(said), findsOneWidget);
      });
    }

    testWidgets('맞요청이면 「친구가 됐어요」', (t) async {
      _phone(t, const Size(390, 844));
      final l = _Links(initial: _link('WXYZ2345'));
      final s = _Server({'/me': _me, '/friends/request': {'ok': true, 'status': 'accepted'}});
      final inbox = l.inbox();
      final app = await _app();   // 저장소를 먼저 비웁니다 — 받는 곳이 시작하며 읽습니다
      await inbox.start();
      await _host(t, app: app, api: s.api(), inbox: inbox);
      expect(find.text('친구가 됐어요'), findsOneWidget);
    });

    testWidgets('로그인 없이 쓰는 중 — 코드는 쥐고 안내 한 번(위의 띠 · 「로그인」), 로그인하면 보낸다', (t) async {
      _phone(t, const Size(390, 844));
      final l = _Links(initial: _link('K7M2QX9D'));
      final s = _Server({'/me': _me, '/friends/request': {'ok': true, 'status': 'pending'}});
      final api = s.api(signedIn: false);
      final app = await _app(guest: true);
      final inbox = l.inbox();
      await inbox.start();
      await _host(t, app: app, api: api, inbox: inbox);

      expect(s.bodiesTo('/friends/request'), isEmpty, reason: '로그인 없이는 못 보냅니다');
      expect(find.text('로그인하면 친구 요청이 가요'), findsOneWidget);
      expect(find.byType(MaterialBanner), findsOneWidget, reason: '누를 것이 있는 안내는 위의 띠로');
      expect(find.byType(SnackBar), findsNothing);
      expect(inbox.pending?.code, 'K7M2QX9D', reason: '버리지 않고 쥡니다');
      expect(inbox.pending?.prompted, isTrue);

      /* 안내는 한 번 — 다시 그려지거나 탭을 옮겨도 또 안 뜹니다. */
      await t.pump(const Duration(seconds: 7));
      await t.pumpAndSettle();
      expect(find.text('로그인하면 친구 요청이 가요'), findsNothing, reason: '저절로 사라짐');
      await t.tap(find.widgetWithText(NavigationDestination, '식단'));
      await t.pumpAndSettle();
      app.store.set({'foodFavorites': ['밥']});
      await t.pumpAndSettle();
      expect(find.text('로그인하면 친구 요청이 가요'), findsNothing);

      /* 새로 누르면 다시 알리고, 이번엔 「로그인」 을 눌러 로그인합니다. */
      l.clock = l.clock.add(const Duration(minutes: 1));
      l.ctrl.add(_link('K7M2QX9D'));
      await t.pumpAndSettle();
      expect(find.text('로그인하면 친구 요청이 가요'), findsOneWidget);
      await t.tap(find.widgetWithText(TextButton, '로그인'));
      await t.pumpAndSettle();
      expect(find.byType(MaterialBanner), findsNothing, reason: '누르면 띠는 걷힙니다');
      expect(find.byType(SignInScreen), findsOneWidget);
      expect(s.bodiesTo('/friends/request'), isEmpty);

      await api.setToken('tok');   // 로그인이 되면
      t.widget<SignInScreen>(find.byType(SignInScreen)).onDone();
      await t.pumpAndSettle();
      expect(find.byType(SignInScreen), findsNothing);
      expect(s.bodiesTo('/friends/request'), [
        {'inviteCode': 'K7M2QX9D'}
      ]);
      expect(find.text('친구 요청을 보냈어요'), findsOneWidget);
      expect(inbox.pending, isNull);
      expect(t.takeException(), isNull);
    });

    testWidgets('7일 지난 코드는 보내지 않는다', (t) async {
      _phone(t, const Size(390, 844));
      final l = _Links();
      final old = l.clock.subtract(const Duration(days: 8));
      final s = _Server({'/me': _me, '/friends/request': {'ok': true}});
      final app = await _app(prefs: {
        _pendingKey: jsonEncode({'code': 'K7M2QX9D', 'at': old.millisecondsSinceEpoch}),
      });
      final inbox = l.inbox();
      await inbox.start();
      await _host(t, app: app, api: s.api(), inbox: inbox);
      expect(s.bodiesTo('/friends/request'), isEmpty);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byType(MaterialBanner), findsNothing);
    });

    testWidgets('지난번에 못 보낸 코드(저장됨)는 켜서 탭 화면이 서면 보낸다', (t) async {
      _phone(t, const Size(390, 844));
      final l = _Links();
      final s = _Server({'/me': _me, '/friends/request': {'ok': true}});
      final app = await _app(prefs: {
        _pendingKey: jsonEncode({'code': 'K7M2QX9D', 'at': l.clock.millisecondsSinceEpoch, 'prompted': true}),
      });
      final inbox = l.inbox();
      await inbox.start();
      await _host(t, app: app, api: s.api(), inbox: inbox);
      expect(s.bodiesTo('/friends/request'), [
        {'inviteCode': 'K7M2QX9D'}
      ]);
    });

    /* 링크로 켜진 앱이 뒤에서 꺼졌다가 아이콘으로 열리면 안드로이드가 그 링크로 화면을 다시
       만듭니다 — 켤 때마다 요청이 또 가면 안 됩니다. 서버에 못 닿았던 것은 다시 갑니다. */
    for (final (label, answer, resent) in const [
      ('보냈으면', {'ok': true, 'status': 'pending'} as Object, false),
      ('서버가 503 이었으면', 503 as Object, true),
    ]) {
      testWidgets('앱이 꺼졌다 같은 링크로 다시 만들어지면 — $label ${resent ? '다시 보낸다' : '다시 안 보낸다'}',
          (t) async {
        _phone(t, const Size(390, 844));
        final s = _Server({'/me': _me, '/friends/request': answer});
        final app = await _app();
        final api = s.api();
        final l = _Links(initial: _link('K7M2QX9D'));
        final a = l.inbox();
        await a.start();
        await _host(t, app: app, api: api, inbox: a);
        expect(s.bodiesTo('/friends/request'), hasLength(1));

        await t.pumpWidget(const SizedBox());
        a.dispose();
        l.clock = l.clock.add(const Duration(hours: 5));
        final b = l.inbox();
        await b.start();
        await _host(t, app: app, api: api, inbox: b);
        expect(s.bodiesTo('/friends/request'), hasLength(resent ? 2 : 1));
        expect(find.byType(SnackBar), resent ? findsOneWidget : findsNothing);
        b.dispose();
      });
    }

    /* 업데이트 뒤 처음 켠 사람에게는 테스터 인사가 뜹니다. 결과 스낵바가 그 시트 밑에 깔리면
       요청이 갔는지 모릅니다 — 인사가 닫힌 뒤에 보내고 알립니다. */
    testWidgets('테스터 인사가 뜨는 차례면 닫힌 뒤에 보내고 알린다', (t) async {
      _phone(t, const Size(390, 844));
      final l = _Links(initial: _link('K7M2QX9D'));
      final s = _Server({'/me': _me, '/friends/request': {'ok': true, 'status': 'pending'}});
      final inbox = l.inbox();
      final app = await _app(seen: false);
      await inbox.start();
      await _host(t, app: app, api: s.api(), inbox: inbox);
      expect(find.byType(TesterWelcomeSheet), findsOneWidget);
      expect(s.bodiesTo('/friends/request'), isEmpty, reason: '인사가 떠 있는 동안은 기다립니다');

      await t.tap(find.byKey(const Key('welcome-skip')));
      await t.pumpAndSettle();
      expect(find.byType(TesterWelcomeSheet), findsNothing);
      expect(s.bodiesTo('/friends/request'), hasLength(1));
      expect(find.text('친구 요청을 보냈어요'), findsOneWidget);
    });

    testWidgets('로그인 화면(처음 켬)에서는 쥐고만 있다가, 로그인 → 탭 화면이 서면 보낸다', (t) async {
      _phone(t, const Size(390, 844));
      final l = _Links(initial: _link('K7M2QX9D'));
      final s = _Server({'/me': _me, '/friends/request': {'ok': true}});
      SharedPreferences.setMockInitialValues({});
      final app = await AppState.boot();
      app.store.set({'profile': _profile, 'onboarded': true});
      markTesterWelcomeSeen(app);
      final api = s.api(signedIn: false);
      final inbox = l.inbox();
      await inbox.start();
      await _host(t, app: app, api: api, inbox: inbox);
      expect(find.byType(SignInScreen), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing, reason: '탭 화면이 아니면 알리지 않습니다');
      expect(inbox.pending?.code, 'K7M2QX9D');

      await api.setToken('tok');
      await t.pumpAndSettle();
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(s.bodiesTo('/friends/request'), hasLength(1));
      expect(find.text('친구 요청을 보냈어요'), findsOneWidget);
    });
  });

  /* --- main.dart ---------------------------------------------------------------- */
  testWidgets('main.dart — 넘긴 링크 받는 곳을 시작하고 셸까지 넘긴다', (t) async {
    _phone(t, const Size(390, 844));
    SharedPreferences.setMockInitialValues({'mybody.server.v1': 'https://x.test'});
    PackageInfo.setMockInitialValues(
        appName: 'Mybody', packageName: 'test.mybody', version: '0.2.17',
        buildNumber: '310', buildSignature: '');
    final l = _Links();
    final inbox = l.inbox();
    await t.pumpWidget(MyBodyApp(invites: inbox));
    for (var i = 0; i < 30 && find.byType(Shell).evaluate().isEmpty; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(Shell), findsOneWidget);
    expect(t.widget<Shell>(find.byType(Shell)).invites, same(inbox));
    expect(l.ctrl.hasListener, isTrue, reason: '링크를 듣고 있어야 합니다');
    l.ctrl.add(_link('K7M2QX9D'));
    await t.pump();
    await t.pump();
    expect(inbox.pending?.code, 'K7M2QX9D');
  });

  /* --- 설정 파일 ---------------------------------------------------------------- */
  group('설정 파일 — mybody:// 스킴', () {
    test('AndroidManifest — MainActivity 가 mybody://invite 를 받고, Flutter 딥링크는 꺼짐', () {
      final xml = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      final activity = RegExp(r'<activity[\s\S]*?</activity>').firstMatch(xml)![0]!;
      expect(activity, contains('android:name=".MainActivity"'));
      final filters = RegExp(r'<intent-filter>[\s\S]*?</intent-filter>').allMatches(activity).map((m) => m[0]!);
      final invite = filters.where((f) => f.contains('android:scheme="mybody"')).toList();
      expect(invite, hasLength(1));
      for (final s in [
        'android.intent.action.VIEW',
        'android.intent.category.DEFAULT',
        'android.intent.category.BROWSABLE',
        'android:host="invite"',
      ]) {
        expect(invite.single, contains(s), reason: s);
      }
      expect(
          RegExp(r'<meta-data\s+android:name="flutter_deeplinking_enabled"\s+android:value="false"\s*/>')
              .hasMatch(activity),
          isTrue);
      expect(xml, contains('android:exported="true"'));
    });

    test('Info.plist — CFBundleURLTypes 에 mybody, Flutter 딥링크는 꺼짐', () {
      final plist = File('ios/Runner/Info.plist').readAsStringSync();
      final types = RegExp(r'<key>CFBundleURLTypes</key>\s*<array>\s*<dict>([\s\S]*?)</dict>\s*</array>')
          .firstMatch(plist);
      expect(types, isNotNull);
      final body = types![1]!;
      expect(body, contains('<string>io.github.iacobuschoi.mybody.invite</string>'));
      expect(RegExp(r'<key>CFBundleURLSchemes</key>\s*<array>\s*<string>mybody</string>').hasMatch(body), isTrue);
      expect(RegExp(r'<key>FlutterDeepLinkingEnabled</key>\s*<false/>').hasMatch(plist), isTrue);
    });
  });
}
