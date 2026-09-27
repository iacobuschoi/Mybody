/* =============================================================================
 * friend_add_test.dart — 친구 탭의 「친구 추가」 다이얼로그
 *
 * 주인 의견 43: "여기서도 친구추가 코드 보내기 만들어서 링크 받으면 코드 보내지게". 예전
 * 다이얼로그는 「친구의 초대 코드」 칸 하나(예시 「ab12cd」 — 실제 코드와 다른 모양)뿐이었습니다.
 *
 *   · 위에 내 코드(크게) · 「보내기」(초대 링크가 든 글) · 코드를 누르면 복사(「복사했어요」).
 *   · 내 코드를 아직 모르면(/me 실패) 다이얼로그가 받아 온다 — 작은 원, 못 받으면 「다시」.
 *   · 아래 친구 코드 칸 — 대문자 · 여덟 글자 · 예시는 실제 모양 · 글자 수 표시 없음.
 *   · 모양이 틀리면 서버에 안 묻고 칸 밑에, 서버가 거절하면 그 까닭을 칸 밑에 — 다이얼로그는
 *     그대로(고쳐 넣게). 보냈으면 닫고 한 줄, 목록을 다시 받는다.
 *   · 360 폭 · 글자 1.3배 · 밝은/어두운 테마에서 넘치지 않는다.
 *   · 「초대 코드 붙여넣기」(주인 의견 45) — 클립보드에 글이 있을 때만 칩이 보이고, 누를 때만
 *     읽는다(아이폰은 읽는 순간 「붙여넣기 허용」 창). 코드만 칸에 채우고, 보내는 것은 「요청
 *     보내기」. 코드가 없으면 칸 밑에 한 줄. 칩이 떠도 360 폭 · 1.3배에서 넘치지 않는다.
 * ========================================================================== */
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mybody/src/api.dart';
import 'package:mybody/src/app_state.dart';
import 'package:mybody/src/scope.dart';
import 'package:mybody/src/screens/social.dart';
import 'package:mybody/src/theme.dart';
import 'package:mybody/src/ui/edge.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _profile = {
  'sex': 'male', 'age': 22, 'heightCm': 187, 'activityLevel': 'moderate',
  'trainingAge': 'novice', 'daysPerWeek': 4, 'mealsPerDay': 3,
};

const _me = {
  'ok': true,
  'user': {'id': 'me', 'displayName': '나', 'inviteCode': 'ABCD2345'},
};

const _noFriends = {'ok': true, 'friends': {'accepted': [], 'incoming': [], 'outgoing': []}};

class _Server {
  _Server([Map<String, Object>? routes]) : routes = {...?routes};
  final Map<String, Object> routes;
  final sent = <(String path, Map<String, dynamic>? body)>[];

  /// 있으면 그 길은 이게 풀릴 때까지 답하지 않습니다(느린 서버).
  final gates = <String, Completer<void>>{};

  Api api() {
    http.Response json(Object body, int status) => http.Response.bytes(
          utf8.encode(jsonEncode(body)), status,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
    final a = Api(
      baseUrl: 'https://x.test',
      client: MockClient((req) async {
        final path = req.url.path.replaceFirst('/api', '');
        sent.add((path, req.body.isEmpty ? null : (jsonDecode(req.body) as Map).cast<String, dynamic>()));
        final gate = gates[path];
        if (gate != null) await gate.future;
        final v = routes[path];
        if (v is Map) return json(v, 200);
        if (v is int) return json({'ok': false}, v);
        return json({'ok': false, 'reason': '없는 길'}, 404);
      }),
    );
    a.setToken('tok');
    return a;
  }

  List<Map<String, dynamic>?> bodiesTo(String path) =>
      [for (final r in sent) if (r.$1 == path) r.$2];
}

void _phone(WidgetTester t, Size size, {double text = 1.0}) {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1.0;
  t.platformDispatcher.textScaleFactorTestValue = text;
  addTearDown(t.view.reset);
  addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
}

Future<void> _host(WidgetTester t, _Server s, {bool dark = false}) async {
  SharedPreferences.setMockInitialValues({});
  final app = await AppState.boot();
  app.store.set({'profile': _profile, 'onboarded': true});
  await t.pumpWidget(Scope(
    state: app,
    api: s.api(),
    onServerChange: (_) async {},
    child: MaterialApp(
      theme: dark ? mbDark() : mbLight(),
      builder: edgeSafe,
      home: Scaffold(body: SocialScreen(go: (_, [__]) {})),
    ),
  ));
  await t.pumpAndSettle();
}

Future<void> _openDialog(WidgetTester t) async {
  await t.tap(find.widgetWithText(OutlinedButton, '친구 추가'));
  await t.pumpAndSettle();
  expect(find.byType(AlertDialog), findsOneWidget);
}

ValueNotifier<String?> _clipboard(WidgetTester t) {
  final clip = ValueNotifier<String?>(null);
  final m = t.binding.defaultBinaryMessenger;
  m.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'Clipboard.setData') clip.value = (call.arguments as Map)['text'] as String?;
    if (call.method == 'Clipboard.getData') return {'text': clip.value};
    return null;
  });
  addTearDown(() => m.setMockMethodCallHandler(SystemChannels.platform, null));
  return clip;
}

final _input = find.byKey(const Key('add-friend-input'));
Finder get _request => find.widgetWithText(FilledButton, '요청 보내기');
final _paste = find.byKey(const Key('invite-paste'));

/// 「초대 코드 붙여넣기」 가 보는 클립보드 — 글이 있는가([has]) · 읽은 횟수(reads).
class _Clip {
  _Clip(this.text, {this.has = true});
  String? text;
  bool has;
  int reads = 0;
  int checks = 0;
}

_Clip _pasteClip(String? text, {bool has = true}) {
  final c = _Clip(text, has: has);
  final hasBefore = invitePasteHasStrings, readBefore = invitePasteRead;
  invitePasteHasStrings = () async {
    c.checks++;
    return c.has;
  };
  invitePasteRead = () async {
    c.reads++;
    return c.text;
  };
  addTearDown(() {
    invitePasteHasStrings = hasBefore;
    invitePasteRead = readBefore;
  });
  return c;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('내 코드 · 보내기(초대 링크) · 누르면 복사 — 아래에 친구 코드 칸', (t) async {
    _phone(t, const Size(390, 844));
    final clip = _clipboard(t);
    final shared = <String>[];
    final before = inviteShareOut;
    inviteShareOut = (text, origin) async => shared.add(text);
    addTearDown(() => inviteShareOut = before);

    await _host(t, _Server({'/me': _me, '/friends': _noFriends}));
    expect(find.text('내 코드 ABCD2345'), findsOneWidget, reason: '카드의 이름도 「내 코드」');
    await _openDialog(t);

    final dialog = find.byType(AlertDialog);
    expect(find.descendant(of: dialog, matching: find.text('친구 추가')), findsOneWidget, reason: '제목');
    expect(find.text('친구의 초대 코드'), findsNothing);
    expect(find.text('내 코드'), findsOneWidget);
    expect(find.descendant(of: dialog, matching: find.text('ABCD2345')), findsOneWidget);
    expect(find.text('친구 코드'), findsOneWidget);
    expect(find.text('예: $kInviteCodeExample'), findsOneWidget);
    expect(find.text('예: ab12cd'), findsNothing);
    /* 내 코드 칸이 친구 코드 칸보다 위. */
    expect(t.getRect(find.byKey(const Key('add-friend-code'))).bottom,
        lessThan(t.getRect(_input).top));

    await t.tap(find.byKey(const Key('add-friend-share')));
    await t.pumpAndSettle();
    expect(shared, [inviteShareText('ABCD2345', 'https://x.test')]);
    expect(shared.single, contains('https://x.test/i/ABCD2345'));
    expect((await SharedPreferences.getInstance()).getString(kMyInviteCodeKey), 'ABCD2345',
        reason: '보낸 내 코드는 적어 둡니다 — 클립보드에 남은 내 글을 친구의 초대로 묻지 않게');

    await t.tap(find.byKey(const Key('add-friend-code')));
    await t.pump();
    expect(clip.value, 'ABCD2345');
    expect(find.text('복사했어요'), findsOneWidget, reason: '다이얼로그 안에서 보여야 합니다');
    expect(find.text('내 코드'), findsNothing);
    await t.pump(const Duration(seconds: 3));
    expect(find.text('내 코드'), findsOneWidget, reason: '잠깐 뒤 돌아옵니다');
    expect(find.byType(AlertDialog), findsOneWidget, reason: '복사 · 보내기로 닫히지 않습니다');
    expect(t.takeException(), isNull);
  });

  testWidgets('공유 시트가 실패하면 보낼 글을 복사해 두고 그렇다고 말한다', (t) async {
    _phone(t, const Size(390, 844));
    final clip = _clipboard(t);
    final before = inviteShareOut;
    inviteShareOut = (text, origin) async => throw StateError('공유 없음');
    addTearDown(() => inviteShareOut = before);
    await _host(t, _Server({'/me': _me, '/friends': _noFriends}));
    await _openDialog(t);
    await t.tap(find.byKey(const Key('add-friend-share')));
    await t.pump();
    expect(clip.value, inviteShareText('ABCD2345', 'https://x.test'));
    expect(find.text('보낼 글을 복사했어요'), findsOneWidget);
    await t.pump(const Duration(seconds: 3));
  });

  testWidgets('내 코드를 아직 모르면(/me 실패) 다이얼로그가 받아 온다 — 원 · 「다시」', (t) async {
    _phone(t, const Size(390, 844));
    final s = _Server({'/friends': _noFriends});   // /me 가 404
    await _host(t, s);
    expect(find.text('내 코드 ABCD2345'), findsNothing);
    /* 카드가 없어도 「친구 추가」 는 있습니다. */
    await _openDialog(t);
    expect(find.text('못 불러왔어요'), findsOneWidget);
    expect(t.widget<FilledButton>(find.byKey(const Key('add-friend-share'))).onPressed, isNull,
        reason: '코드가 없으면 보낼 것도 없습니다');

    s.routes['/me'] = _me;
    final slow = s.gates['/me'] = Completer<void>();
    await t.tap(find.byKey(const Key('add-friend-code-retry')));
    await t.pump();
    expect(find.descendant(of: find.byType(AlertDialog), matching: find.byType(CircularProgressIndicator)),
        findsOneWidget, reason: '받는 동안 작은 원');
    slow.complete();
    await t.pumpAndSettle();
    expect(find.descendant(of: find.byType(AlertDialog), matching: find.text('ABCD2345')), findsOneWidget);
    expect(t.widget<FilledButton>(find.byKey(const Key('add-friend-share'))).onPressed, isNotNull);

    /* 닫으면 카드에도 — 같은 /me 를 또 묻지 않게 다이얼로그가 받은 것을 넘깁니다. */
    await t.tap(find.text('취소'));
    await t.pumpAndSettle();
    expect(find.text('내 코드 ABCD2345'), findsOneWidget);
  });

  testWidgets('코드 칸 — 대문자로, 붙여 넣으면 코드만, 여덟 글자, 글자 수 표시 없음', (t) async {
    _phone(t, const Size(390, 844));
    await _host(t, _Server({'/me': _me, '/friends': _noFriends}));
    await _openDialog(t);
    final tf = t.widget<TextField>(_input);
    expect(tf.textCapitalization, TextCapitalization.characters);
    expect(tf.maxLength, 8);
    expect(tf.autocorrect, isFalse);
    expect(tf.enableSuggestions, isFalse);
    expect(t.widget<FilledButton>(_request).onPressed, isNull, reason: '빈 칸이면 못 누릅니다');

    await t.tap(_input);
    await t.enterText(_input, 'k7m2qx9d');
    await t.pump();
    expect(tf.controller!.text, 'K7M2QX9D');
    expect(find.text('8/8'), findsNothing);
    await t.enterText(_input, inviteShareText('WXYZ2345', 'https://x.test'));
    await t.pump();
    expect(tf.controller!.text, 'WXYZ2345', reason: '글의 앞머리(「MYBODY…」)가 아니라 코드');
  });

  testWidgets('모양이 틀리면 서버에 안 묻고, 서버가 거절하면 그 까닭 — 다이얼로그는 그대로', (t) async {
    _phone(t, const Size(390, 844));
    final s = _Server({
      '/me': _me,
      '/friends': _noFriends,
      '/friends/request': {'ok': false, 'reason': '자기 자신은 추가할 수 없습니다'},
    });
    await _host(t, s);
    await _openDialog(t);

    await t.enterText(_input, 'NOPE0000');
    await t.pump();
    await t.tap(_request);
    await t.pumpAndSettle();
    expect(find.text(kInviteCodeInvalid), findsOneWidget);
    expect(s.bodiesTo('/friends/request'), isEmpty);
    expect(find.byType(AlertDialog), findsOneWidget);

    /* 고치기 시작하면 빨간 줄은 걷힙니다. */
    await t.enterText(_input, 'ABCD234');
    await t.pump();
    expect(find.text(kInviteCodeInvalid), findsNothing);

    await t.enterText(_input, 'ABCD2345');
    await t.pump();
    await t.tap(_request);
    await t.pumpAndSettle();
    expect(s.bodiesTo('/friends/request'), [
      {'inviteCode': 'ABCD2345'}
    ]);
    expect(find.text('내 코드예요'), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(t.widget<TextField>(_input).controller!.text, 'ABCD2345', reason: '고쳐 넣게 그대로');
  });

  testWidgets('보냈으면 닫고 한 줄, 목록을 다시 받는다', (t) async {
    _phone(t, const Size(390, 844));
    final s = _Server({
      '/me': _me,
      '/friends': _noFriends,
      '/friends/request': {'ok': true, 'status': 'pending', 'otherId': 'u_2'},
    });
    await _host(t, s);
    final before = s.bodiesTo('/friends').length;
    await _openDialog(t);
    await t.enterText(_input, 'wxyz2345');
    await t.pump();
    await t.tap(_request);
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(s.bodiesTo('/friends/request'), [
      {'inviteCode': 'WXYZ2345'}
    ]);
    expect(find.text('친구 요청을 보냈어요'), findsOneWidget);
    expect(s.bodiesTo('/friends').length, before + 1, reason: '「보낸 요청」 에 뜨게 다시 받습니다');
  });

  /* 초대 페이지의 설치 단추는 누르는 순간 「Mybody 초대 <코드> https://<서버>/i/<코드>」 를
     클립보드에 넣습니다. 아이폰은 앱이 클립보드를 읽으면 「붙여넣기 허용」 창이 뜨므로, 칩을 눌렀을
     때만 읽습니다. */
  group('「초대 코드 붙여넣기」', () {
    testWidgets('아이폰 — 칩은 있는지만 보고, 누를 때 읽어 칸에 코드만 · 「요청 보내기」 로 보낸다',
        (t) async {
      _phone(t, const Size(390, 844));
      final clip = _pasteClip('Mybody 초대 K7M2QX9D https://x.test/i/K7M2QX9D');
      final s = _Server({
        '/me': _me,
        '/friends': _noFriends,
        '/friends/request': {'ok': true, 'status': 'pending', 'otherId': 'u_2'},
      });
      await _host(t, s);
      await _openDialog(t);
      expect(_paste, findsOneWidget);
      expect(find.text('초대 코드 붙여넣기'), findsOneWidget);
      expect(clip.checks, greaterThanOrEqualTo(1));
      expect(clip.reads, 0, reason: '누르기 전에는 읽지 않습니다 — 아이폰은 읽는 순간 창이 뜹니다');

      await t.tap(_paste);
      await t.pumpAndSettle();
      expect(clip.reads, 1);
      expect(t.widget<TextField>(_input).controller!.text, 'K7M2QX9D');
      expect(s.bodiesTo('/friends/request'), isEmpty, reason: '보내는 것은 「요청 보내기」');
      await t.tap(_request);
      await t.pumpAndSettle();
      expect(s.bodiesTo('/friends/request'), [
        {'inviteCode': 'K7M2QX9D'}
      ]);
      expect(find.byType(AlertDialog), findsNothing);
      expect(clip.reads, 1, reason: '더 읽지 않습니다');
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    testWidgets('클립보드가 비었으면 칩이 없다 — 읽지도 않는다', (t) async {
      _phone(t, const Size(390, 844));
      final clip = _pasteClip(null, has: false);
      await _host(t, _Server({'/me': _me, '/friends': _noFriends}));
      await _openDialog(t);
      expect(_paste, findsNothing);
      expect(clip.reads, 0);
    });

    testWidgets('앱으로 돌아오면 다시 본다(카톡에서 복사하고 옴)', (t) async {
      _phone(t, const Size(390, 844));
      final clip = _pasteClip('초대 K7M2QX9D', has: false);
      await _host(t, _Server({'/me': _me, '/friends': _noFriends}));
      await _openDialog(t);
      expect(_paste, findsNothing);
      clip.has = true;
      for (final st in const [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        t.binding.handleAppLifecycleStateChanged(st);
      }
      await t.pumpAndSettle();
      expect(_paste, findsOneWidget);
      expect(clip.reads, 0);
    });

    testWidgets('복사한 글에 코드가 없으면 칸 밑에 한 줄 — 서버에 묻지 않는다', (t) async {
      _phone(t, const Size(390, 844));
      _pasteClip('오늘 저녁 7시에 만나');
      final s = _Server({'/me': _me, '/friends': _noFriends, '/friends/request': {'ok': true}});
      await _host(t, s);
      await _openDialog(t);
      await t.tap(_paste);
      await t.pumpAndSettle();
      expect(find.text(kInvitePasteNone), findsOneWidget);
      expect(t.widget<TextField>(_input).controller!.text, isEmpty);
      expect(s.bodiesTo('/friends/request'), isEmpty);
      await t.enterText(_input, 'K7M2');
      await t.pump();
      expect(find.text(kInvitePasteNone), findsNothing, reason: '고치기 시작하면 걷힙니다');
    });

    testWidgets('360 폭 · 글자 1.3배 — 칩이 떠도 넘치지 않고, 키보드가 올라와도 「요청 보내기」 가 보인다',
        (t) async {
      const size = Size(360, 640);
      _phone(t, size, text: 1.3);
      _pasteClip('초대 K7M2QX9D');
      await _host(t, _Server({'/me': _me, '/friends': _noFriends}));
      await _openDialog(t);
      expect(_paste, findsOneWidget);
      expect(t.takeException(), isNull);
      final chip = t.getRect(_paste);
      final dialog = t.getRect(find.byType(AlertDialog));
      expect(chip.left, greaterThanOrEqualTo(dialog.left));
      expect(chip.right, lessThanOrEqualTo(dialog.right));
      await t.tap(_input);
      await t.pumpAndSettle();
      t.view.viewInsets = const FakeViewPadding(bottom: 300);
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      final r = t.getRect(_request);
      expect(r.bottom, lessThanOrEqualTo(size.height - 300), reason: '키보드 뒤에 깔림: $r');
    });
  });

  group('360 폭 · 글자 1.3배', () {
    for (final dark in [false, true]) {
      testWidgets('${dark ? '어두운' : '밝은'} 테마 — 넘치지 않고, 키보드가 올라와도 「요청 보내기」 가 보인다',
          (t) async {
        const size = Size(360, 640);
        _phone(t, size, text: 1.3);
        await _host(t, _Server({'/me': _me, '/friends': _noFriends}), dark: dark);
        await _openDialog(t);
        expect(t.takeException(), isNull);
        final dialog = t.getRect(find.byType(AlertDialog));
        expect(dialog.left, greaterThanOrEqualTo(0));
        expect(dialog.right, lessThanOrEqualTo(size.width));

        await t.tap(_input);
        await t.pumpAndSettle();
        t.view.viewInsets = const FakeViewPadding(bottom: 300);
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        for (final f in [_input, _request]) {
          final r = t.getRect(f);
          expect(r.bottom, lessThanOrEqualTo(size.height - 300), reason: '키보드 뒤에 깔림: $r');
          expect(r.top, greaterThanOrEqualTo(0), reason: '화면 위로 나감: $r');
        }

      });
    }

    testWidgets('못 받은 코드(「다시」)도 넘치지 않는다', (t) async {
      _phone(t, const Size(360, 640), text: 1.3);
      await _host(t, _Server({'/friends': _noFriends}));
      await _openDialog(t);
      expect(find.text('못 불러왔어요'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });
}
