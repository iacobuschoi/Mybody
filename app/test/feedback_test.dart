/* =============================================================================
 * feedback_test.dart — 앱 안 「의견 보내기」: 화면 먼저, 글은 안 써도
 *
 * 주인의 말: "앱 안 의견보내기는 텍스트도 쓸수있게 해줘(안쓰고 그냥 보내도 됨)".
 * 그래서 여기서 못 박는 것:
 *
 *   · 보내기     사진 한 장이나 글 한 글자가 있어야 켜진다. 글만 · 화면만 둘 다 간다.
 *   · 화면       말풍선으로 열면 여는 순간의 화면이 이미 붙어 있다(시트가 뜨기 **전에**
 *                찍음). X 로 뺄 수 있고, 갤러리로 더 붙이되 모두 3장까지.
 *   · 보낸 몸    서버 약속 그대로 — text · images[{type, data(base64)}] · appVersion
 *                (0.2.17+310) · platform · screen(앱바 제목). 빈 칸은 안 싣는다.
 *                로그아웃 상태면 토큰 없이, 로그인했으면 토큰과 함께.
 *   · 결과       성공이면 닫히고 「보냈어요 — 고마워요!」. 실패면 글 · 사진이 그대로
 *                남고 까닭이 시트 안에 — 다시 누르면 간다. 429 는 "내일 다시".
 *                보내는 동안 단추가 막혀 두 번 안 간다. 보내는 사이에 시트를 닫아도
 *                결과는 연 화면에 한 줄로. 401 · 404 는 "옛 서버".
 *   · 키보드     올라와도 「보내기」 가 키보드 위에서 보이고 눌린다(360 · 390 폭).
 *   · 360px · 글자 1.3배 · 밝게/어둡게 — 넘치지 않는다.
 *   · 설정       「도움말」 카드 — 「의견 버튼 보이기」 스위치(말풍선과 같은 값) · 앱 안내 다시
 *                보기. 「의견 보내기」 줄은 없다(화면 옆 말풍선이 설정 화면에도 떠 있음).
 *                스위치는 비공개 시험 기간(서버 testing · 모르면 시험 중)에는 켜진 채 잠기고
 *                (「테스트 기간에는 켜 둡니다」), 시험이 끝나면 평소처럼 켜고 끈다.
 *   · 셸         앱바에 의견 단추가 없고, 화면 옆 말풍선으로 탭마다 그 탭 이름이 간다.
 *                (말풍선 자체는 feedback_bubble_test.dart)
 *   · 캡처       앱 맨 위 경계를 실제로 PNG 로 굽는다(진짜 앱 main.dart 에서도, 켜는
 *                중 · 준비된 뒤 모두) · 너무 크면 안 붙인다 · 3초에 안 끝나면 없이 연다.
 *   · 사진 손질   PNG · JPEG 은 그대로, 다른 형식 · 큰 것은 다시 그려 PNG 로,
 *                JPEG 의 GPS · XMP 는 지우고 방향 · 그림은 그대로.
 * ========================================================================== */
import 'dart:async';
import 'dart:convert';
import 'dart:io' show GZipCodec, ZLibEncoder;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:mybody/main.dart' show MyBodyApp;
import 'package:mybody/src/api.dart';
import 'package:mybody/src/app_state.dart';
import 'package:mybody/src/scope.dart';
import 'package:mybody/src/screens/feedback.dart';
import 'package:mybody/src/screens/feedback_bubble.dart';
import 'package:mybody/src/screens/settings.dart';
import 'package:mybody/src/screens/sync_settings.dart';
import 'package:mybody/src/screens/tester_welcome.dart' show markTesterWelcomeSeen;
import 'package:mybody/src/shell.dart';
import 'package:mybody/src/theme.dart';
import 'package:mybody/src/ui/edge.dart';
import 'package:mybody/src/ui/widgets.dart';
import 'package:mybody/src/update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/* --- 그림 조각 ------------------------------------------------------------------ */

/// 1×1 PNG — 진짜로 열리는 가장 작은 그림.
final _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==');

/// 앞머리만 JPEG 인 작은 조각(APP0 · SOS · EOI). 서버는 앞머리만 보고, 앱은 위치 지우기만 합니다.
final _jpeg = Uint8List.fromList([
  0xFF, 0xD8,
  0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01, 0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00,
  0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01, 0x00, 0x00, 0x3F, 0x00,
  0x12, 0x34, 0x56,
  0xFF, 0xD9,
]);

/* --- 서버 흉내 ------------------------------------------------------------------ */

/// 나간 의견 요청 하나.
class _Sent {
  _Sent(this.headers, this.body);
  final Map<String, String> headers;
  final Map<String, dynamic> body;
  bool get hasToken => headers.keys.any((k) => k.toLowerCase() == 'authorization');
  String? get token => headers.entries
      .where((e) => e.key.toLowerCase() == 'authorization')
      .map((e) => e.value)
      .firstOrNull;
  List<Map<String, dynamic>> get images =>
      ((body['images'] as List?) ?? const []).cast<Map>().map((m) => m.cast<String, dynamic>()).toList();
}

class _Server {
  /// /feedback 이 돌려줄 상태와 몸. 시험 중에 바꿀 수 있습니다(실패 → 다시 누르면 성공).
  int status = 200;
  Map<String, Object?> reply = {'ok': true, 'id': 7};

  /// 있으면 /feedback 은 이게 풀릴 때까지 답하지 않습니다(느린 서버).
  Completer<void>? gate;

  /// 서버에 못 닿음(status 0).
  bool offline = false;

  /// GET /api/version 의 testing(비공개 시험 기간). null 이면 칸을 안 싣습니다(옛 서버).
  Object? testing;

  final feedback = <_Sent>[];

  Api api() => Api(
        baseUrl: 'https://x.test',
        client: MockClient((req) async {
          http.Response json(Object body, int status) => http.Response.bytes(
              utf8.encode(jsonEncode(body)), status,
              headers: {'content-type': 'application/json; charset=utf-8'});
          final path = req.url.path.replaceFirst('/api', '');
          if (path == '/version') {
            return json({'ok': true, 'latest': {}, 'min': '', if (testing != null) 'testing': testing}, 200);
          }
          if (path != '/feedback') return json({'ok': true}, 200);
          feedback.add(_Sent(Map.of(req.headers), (jsonDecode(req.body) as Map).cast<String, dynamic>()));
          if (gate != null) await gate!.future;
          if (offline) throw http.ClientException('없음');
          return json(reply, status);
        }),
      );
}

/* --- 여는 곳 -------------------------------------------------------------------- */

final _send = find.byKey(const Key('feedback-send'));
final _add = find.byKey(const Key('feedback-add'));
final _text = find.byKey(const Key('feedback-text'));
final _error = find.byKey(const Key('feedback-error'));
final _open = find.byKey(const Key('open-feedback'));
Finder _thumb(int i) => find.byKey(Key('feedback-thumb-$i'));
Finder _remove(int i) => find.byKey(Key('feedback-remove-$i'));
final _thumbs = find.byWidgetPredicate(
    (w) => w.key is ValueKey<String> && (w.key as ValueKey<String>).value.startsWith('feedback-thumb-'));

bool _enabled(WidgetTester t) => t.widget<FilledButton>(_send).onPressed != null;

/// 이번 시험의 캡처 · 갤러리 흉내.
class _Fakes {
  int captures = 0;
  Uint8List? shot = _png;
  final picks = <int>[];
  List<Uint8List> gallery = [];
  Object? pickError;
}

void _phone(WidgetTester t, Size size) {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
}

/// 앱과 같은 겹(Scope > MaterialApp(builder: edgeSafe)) 위에, 셸처럼 앱바 제목이 「홈」 인
/// 화면. 화면 옆 말풍선처럼 Scaffold **위** 의 context 로 openFeedback 을 부릅니다(말풍선은
/// 맨 위 화면의 경로 context — Scaffold 위 — 를 건넵니다).
Future<({_Server server, Api api, _Fakes fakes})> _host(
  WidgetTester t, {
  bool signedIn = false,
  bool capture = true,
  Size size = const Size(390, 844),
  ThemeData? theme,
}) async {
  _phone(t, size);
  SharedPreferences.setMockInitialValues({});
  PackageInfo.setMockInitialValues(
      appName: 'Mybody', packageName: 'test.mybody', version: '0.2.17',
      buildNumber: '310', buildSignature: '');
  final server = _Server();
  final api = server.api();
  if (signedIn) await api.setToken('tok');
  final app = await AppState.boot();
  final fakes = _Fakes();
  feedbackCapture = () async {
    fakes.captures++;
    return fakes.shot;
  };
  feedbackPick = (max) async {
    fakes.picks.add(max);
    if (fakes.pickError != null) throw fakes.pickError!;
    return fakes.gallery;
  };
  await t.pumpWidget(Scope(
    state: app,
    api: api,
    onServerChange: (_) async {},
    child: MaterialApp(
      theme: theme ?? mbLight(),
      builder: edgeSafe,
      home: Builder(
        builder: (c) => Scaffold(
          appBar: AppBar(title: const Text('홈'), actions: [
            IconButton(
              key: const Key('open-feedback'),
              icon: const Icon(Icons.chat_bubble_outline),
              onPressed: () => openFeedback(c, captureScreen: capture),
            ),
          ]),
          body: const Center(child: Text('첫 화면')),
        ),
      ),
    ),
  ));
  return (server: server, api: api, fakes: fakes);
}

Future<void> _openSheet(WidgetTester t) async {
  await t.tap(_open);
  await t.pumpAndSettle();
  expect(_send, findsOneWidget, reason: '의견 시트가 떠야 합니다');
}

void main() {
  final origCapture = feedbackCapture;
  final origPick = feedbackPick;
  tearDown(() {
    feedbackCapture = origCapture;
    feedbackPick = origPick;
  });

  group('보내기가 켜지는 때', () {
    testWidgets('캡처 없이 열면 비어 있고 꺼져 있다 — 글 한 글자면 켜지고, 지우면 다시 꺼진다', (t) async {
      final s = await _host(t, capture: false);
      await _openSheet(t);
      expect(s.fakes.captures, 0, reason: '화면을 찍으라고 안 했습니다');
      expect(_thumbs, findsNothing);
      expect(find.text('의견 보내기'), findsOneWidget);
      expect(find.text('사진이나 글, 하나만 있어도 돼요'), findsOneWidget);
      expect(find.byKey(const Key('feedback-privacy')), findsNothing, reason: '사진이 없으면 할 말이 아닙니다');
      expect(_enabled(t), isFalse);

      await t.enterText(_text, '   ');
      await t.pump();
      expect(_enabled(t), isFalse, reason: '빈칸만은 글이 아닙니다');
      await t.enterText(_text, '홈 숫자가 이상해요');
      await t.pump();
      expect(_enabled(t), isTrue);
      await t.enterText(_text, '');
      await t.pump();
      expect(_enabled(t), isFalse);
    });

    testWidgets('말풍선으로 열면 화면이 이미 붙어 있고 보내기가 켜져 있다 — 글 칸에 커서를 먼저 두지 않는다', (t) async {
      final s = await _host(t);
      await _openSheet(t);
      expect(s.fakes.captures, 1);
      expect(_thumb(0), findsOneWidget);
      expect(find.text('화면이 같이 가요 · 글은 안 써도 돼요'), findsOneWidget);
      expect(find.byKey(const Key('feedback-privacy')), findsOneWidget);
      expect(find.text('붙인 화면에는 몸 수치가 보일 수 있어요 — 운영자만 봅니다'), findsOneWidget);
      expect(_enabled(t), isTrue, reason: '화면 한 장이면 바로 보낼 수 있어야 합니다');
      expect(t.testTextInput.hasAnyClients, isFalse, reason: '키보드가 먼저 올라오면 붙인 화면을 가립니다');
    });

    testWidgets('캡처가 실패하면(null) 캡처 없이 연다', (t) async {
      final s = await _host(t);
      s.fakes.shot = null;
      await _openSheet(t);
      expect(_thumbs, findsNothing);
      expect(_enabled(t), isFalse);
    });

    testWidgets('두 번 눌러도 시트는 한 장 — 찍는 동안 한 번 더 눌러도', (t) async {
      final s = await _host(t);
      final slow = Completer<Uint8List?>();
      feedbackCapture = () {
        s.fakes.captures++;
        return slow.future;
      };
      await t.tap(_open);
      await t.pump();
      await t.tap(_open);
      await t.pump();
      slow.complete(_png);
      await t.pumpAndSettle();
      expect(s.fakes.captures, 1);
      expect(_send, findsOneWidget);
      expect(find.byType(BottomSheet), findsOneWidget);
    });

    testWidgets('찍기가 끝나지 않으면 3초 뒤 캡처 없이 연다 — 말풍선이 먹통으로 남지 않는다', (t) async {
      final s = await _host(t);
      feedbackCapture = () {
        s.fakes.captures++;
        return Completer<Uint8List?>().future;   // 영영 안 끝남
      };
      await t.tap(_open);
      await t.pump();
      expect(_send, findsNothing);
      await t.pump(const Duration(seconds: 3));
      await t.pumpAndSettle();
      expect(_send, findsOneWidget, reason: '3초 뒤에는 캡처 없이라도 떠야 합니다');
      expect(_thumbs, findsNothing);

      /* 닫고 다시 누르면 또 열립니다 — 찍는 중 표시가 남아 있지 않습니다. */
      await t.tapAt(const Offset(20, 20));
      await t.pumpAndSettle();
      expect(_send, findsNothing);
      /* 넘겨받는 Future 가 Future<Uint8List>(null 불가)여도 — 시간 제한의 null 이 형식
         오류로 던져져 찍힌 화면을 버리면 안 됩니다. */
      feedbackCapture = () async => _png;
      await _openSheet(t);
      expect(_thumbs, findsOneWidget);
    });
  });

  group('보낸 몸', () {
    testWidgets('글만 — 로그아웃 상태면 토큰 없이, 판 · 기종 · 화면 이름이 같이 간다', (t) async {
      final s = await _host(t, capture: false);
      await _openSheet(t);
      await t.enterText(_text, '  식단 탭에서 저장이 안 돼요  ');
      await t.pump();
      await t.tap(_send);
      await t.pumpAndSettle();

      expect(s.server.feedback, hasLength(1));
      final sent = s.server.feedback.single;
      expect(sent.hasToken, isFalse, reason: '로그인 안 했으면 토큰 없이 — 서버가 익명으로 받습니다');
      expect(sent.body, {
        'text': '식단 탭에서 저장이 안 돼요',
        'appVersion': '0.2.17+310',
        'platform': 'android',
        'screen': '홈',
      }, reason: '사진이 없으면 images 칸은 아예 안 싣습니다');
    });

    testWidgets('화면만 — 글 없이 바로 보낸다: PNG · base64 · text 칸 없음', (t) async {
      final s = await _host(t);
      await _openSheet(t);
      await t.tap(_send);
      await t.pumpAndSettle();

      final sent = s.server.feedback.single;
      expect(sent.body.containsKey('text'), isFalse, reason: '안 쓴 글은 안 싣습니다');
      expect(sent.images, hasLength(1));
      expect(sent.images.single['type'], 'image/png');
      expect(base64Decode(sent.images.single['data'] as String), _png);
      expect(sent.body['screen'], '홈');
      expect(sent.body['appVersion'], '0.2.17+310');
      expect(sent.body['platform'], 'android');
    });

    testWidgets('로그인했으면 토큰이 같이 간다', (t) async {
      final s = await _host(t, signedIn: true);
      await _openSheet(t);
      await t.tap(_send);
      await t.pumpAndSettle();
      expect(s.server.feedback.single.token, 'Bearer tok');
    });

    testWidgets('글과 사진 둘 다 — 화면 · 갤러리 JPEG 차례대로', (t) async {
      final s = await _host(t);
      s.fakes.gallery = [_jpeg];
      await _openSheet(t);
      await t.tap(_add);
      await t.pumpAndSettle();
      await t.enterText(_text, '두 장 같이');
      await t.pump();
      await t.tap(_send);
      await t.pumpAndSettle();
      final sent = s.server.feedback.single;
      expect(sent.body['text'], '두 장 같이');
      expect([for (final i in sent.images) i['type']], ['image/png', 'image/jpeg']);
      expect(base64Decode(sent.images[1]['data'] as String), _jpeg);
    });
  });

  group('사진', () {
    testWidgets('3장까지 — 남은 칸만큼만 고르고, 3장이면 「사진 추가」 가 사라진다', (t) async {
      final s = await _host(t);
      s.fakes.gallery = [_jpeg, _png, _jpeg, _png, _jpeg];
      await _openSheet(t);
      expect(_add, findsOneWidget);
      await t.tap(_add);
      await t.pumpAndSettle();
      expect(s.fakes.picks, [2], reason: '화면 한 장이 있으니 남은 칸은 둘');
      expect(_thumbs, findsNWidgets(3), reason: '갤러리가 더 돌려줘도 3장까지');
      expect(_add, findsNothing);
      expect(find.text('화면이 같이 가요 · 글은 안 써도 돼요'), findsOneWidget);

      /* X 로 빼면 칸이 다시 생깁니다. 화면을 빼면 머리말이 「사진」 으로. */
      await t.tap(_remove(0));
      await t.pumpAndSettle();
      expect(_thumbs, findsNWidgets(2));
      expect(_add, findsOneWidget);
      expect(find.text('사진이 같이 가요 · 글은 안 써도 돼요'), findsOneWidget);

      await t.tap(_send);
      await t.pumpAndSettle();
      expect([for (final i in s.server.feedback.single.images) i['type']], ['image/jpeg', 'image/png'],
          reason: '빼고 남은 두 장(갤러리에서 고른 차례 그대로)만');
    });

    testWidgets('X 로 화면을 빼면 — 글이 없으니 보내기가 꺼진다', (t) async {
      await _host(t);
      await _openSheet(t);
      expect(_enabled(t), isTrue);
      await t.tap(_remove(0));
      await t.pumpAndSettle();
      expect(_thumbs, findsNothing);
      expect(_enabled(t), isFalse);
      expect(find.byKey(const Key('feedback-privacy')), findsNothing);
    });

    testWidgets('작은 그림을 누르면 크게 보이고, 누르면 닫힌다', (t) async {
      await _host(t);
      await _openSheet(t);
      await t.tap(_thumb(0));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('feedback-preview')), findsOneWidget);
      await t.tapAt(const Offset(20, 20));   // 아무 데나
      await t.pumpAndSettle();
      expect(find.byKey(const Key('feedback-preview')), findsNothing);
      expect(_send, findsOneWidget, reason: '시트는 그대로');
    });

    testWidgets('갤러리를 못 열면(권한 등) 붙인 것은 그대로, 한 줄로 알린다', (t) async {
      final s = await _host(t);
      s.fakes.pickError = PlatformException(code: 'photo_access_denied');
      await _openSheet(t);
      await t.tap(_add);
      await t.pumpAndSettle();
      expect(find.text('사진을 못 가져왔어요'), findsOneWidget);
      expect(_thumbs, findsOneWidget);
      expect(_enabled(t), isTrue);
    });

    testWidgets('고르다 말면(빈 목록) 아무 일도 없다', (t) async {
      final s = await _host(t, capture: false);
      await _openSheet(t);
      await t.tap(_add);
      await t.pumpAndSettle();
      expect(s.fakes.picks, [3]);
      expect(_thumbs, findsNothing);
      expect(_error, findsNothing);
    });
  });

  group('결과', () {
    testWidgets('성공 — 시트가 닫히고 「보냈어요 — 고마워요!」', (t) async {
      await _host(t);
      await _openSheet(t);
      await t.tap(_send);
      await t.pumpAndSettle();
      expect(_send, findsNothing);
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('보냈어요 — 고마워요!'), findsOneWidget);
    });

    testWidgets('서버 오류 — 시트에 그대로, 글과 사진이 남고 까닭이 보인다 · 다시 누르면 간다', (t) async {
      final s = await _host(t);
      s.server
        ..status = 400
        ..reply = {'ok': false, 'error': '1번째 사진의 내용이 PNG 가 아닙니다'};
      await _openSheet(t);
      await t.enterText(_text, '저장 버튼이 안 눌려요');
      await t.pump();
      await t.tap(_send);
      await t.pumpAndSettle();

      expect(_send, findsOneWidget, reason: '실패하면 닫지 않습니다');
      expect(find.text('1번째 사진의 내용이 PNG 가 아닙니다'), findsOneWidget);
      expect(t.widget<EditableText>(find.descendant(of: _text, matching: find.byType(EditableText)))
          .controller.text, '저장 버튼이 안 눌려요', reason: '써 둔 글이 날아가면 다시 안 씁니다');
      expect(_thumbs, findsOneWidget);
      expect(_enabled(t), isTrue);
      final errColor = t.widget<Text>(_error).style?.color;
      expect(errColor, mb(t.element(_error)).bad);

      s.server
        ..status = 200
        ..reply = {'ok': true, 'id': 8};
      await t.tap(_send);
      await t.pumpAndSettle();
      expect(s.server.feedback, hasLength(2));
      expect(s.server.feedback.last.body['text'], '저장 버튼이 안 눌려요');
      expect(_send, findsNothing);
      expect(find.text('보냈어요 — 고마워요!'), findsOneWidget);
    });

    testWidgets('하루 한도(429) — 「오늘은 더 보낼 수 없어요 — 내일 다시」', (t) async {
      final s = await _host(t);
      s.server
        ..status = 429
        ..reply = {'ok': false, 'error': '오늘은 의견을 20개까지 보낼 수 있습니다. 내일 다시 보내 주세요'};
      await _openSheet(t);
      await t.tap(_send);
      await t.pumpAndSettle();
      expect(find.text('오늘은 더 보낼 수 없어요 — 내일 다시'), findsOneWidget);
      expect(_send, findsOneWidget);
    });

    testWidgets('서버에 못 닿으면 — 다시 누르라는 한 줄', (t) async {
      final s = await _host(t);
      s.server.offline = true;
      await _openSheet(t);
      await t.tap(_send);
      await t.pumpAndSettle();
      expect(find.text('서버에 닿지 못했어요 — 잠시 뒤 다시 눌러 주세요'), findsOneWidget);
      expect(_thumbs, findsOneWidget);
    });

    /* 느린 데이터에서 보내기는 몇십 초 — 그사이 시트를 닫는 사람이 있습니다. 보내기는
       이어지고, 결과는 연 화면에 한 줄로 떠야 합니다(말없이 사라지면 또 보냅니다). */
    for (final ok in [true, false]) {
      testWidgets('보내는 사이에 시트를 닫아도 — 결과는 연 화면에 한 줄로 (${ok ? '성공' : '실패'})', (t) async {
        final s = await _host(t);
        s.server.gate = Completer<void>();
        if (!ok) {
          s.server
            ..status = 400
            ..reply = {'ok': false, 'error': '1번째 사진의 내용이 PNG 가 아닙니다'};
        }
        await _openSheet(t);
        await t.tap(_send);
        await t.pump();
        await t.tapAt(const Offset(20, 20));   // 바깥(가림막)을 눌러 닫기
        await t.pumpAndSettle();
        expect(_send, findsNothing, reason: '보내는 중에도 닫을 수는 있습니다 — 앱에 갇히지 않게');
        expect(find.byType(SnackBar), findsNothing, reason: '아직 결과가 없습니다');

        s.server.gate!.complete();
        await t.pumpAndSettle();
        expect(s.server.feedback, hasLength(1));
        expect(
            find.text(ok ? '보냈어요 — 고마워요!' : '의견을 못 보냈어요 — 1번째 사진의 내용이 PNG 가 아닙니다'),
            findsOneWidget);
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('보내는 동안 — 단추가 막히고 「보내는 중…」, 두 번 안 간다 · 사진도 못 뺀다', (t) async {
      final s = await _host(t);
      s.server.gate = Completer<void>();
      await _openSheet(t);
      await t.tap(_send);
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      expect(find.text('보내는 중…'), findsOneWidget);
      expect(_enabled(t), isFalse);
      await t.tap(_send, warnIfMissed: false);
      await t.tap(_remove(0));
      await t.pump();
      expect(s.server.feedback, hasLength(1));
      expect(_thumbs, findsOneWidget);
      expect(t.widget<OutlinedButton>(_add).onPressed, isNull);

      s.server.gate!.complete();
      await t.pumpAndSettle();
      expect(_send, findsNothing);
      expect(find.text('보냈어요 — 고마워요!'), findsOneWidget);
    });
  });

  group('글 칸', () {
    testWidgets('세는 글자는 끝이 가까울 때만 보인다', (t) async {
      await _host(t, capture: false);
      await _openSheet(t);
      await t.enterText(_text, '짧은 글');
      await t.pump();
      expect(find.textContaining('/ 2000'), findsNothing);
      await t.enterText(_text, '가' * 1850);
      await t.pump();
      expect(find.text('1850 / 2000'), findsOneWidget);
    });
  });

  group('키보드', () {
    for (final size in const [Size(360, 740), Size(390, 844)]) {
      testWidgets('${size.width.toInt()}×${size.height.toInt()} — 키보드가 올라와도 보내기가 키보드 위에 보이고 눌린다',
          (t) async {
        final s = await _host(t, size: size);
        s.fakes.gallery = [_jpeg, _jpeg];
        await _openSheet(t);
        await t.tap(_add);
        await t.pumpAndSettle();
        await t.tap(_text);
        await t.pumpAndSettle();
        expect(t.testTextInput.hasAnyClients, isTrue);
        t.view.viewInsets = const FakeViewPadding(bottom: 300);
        await t.pumpAndSettle();
        await t.enterText(_text, '줄\n' * 6);
        await t.pumpAndSettle();

        final r = t.getRect(_send);
        expect(r.bottom, lessThanOrEqualTo(size.height - 300), reason: '키보드 뒤에 깔림: $r');
        expect(r.top, greaterThanOrEqualTo(0));
        expect(t.takeException(), isNull);

        await t.tap(_send);
        await t.pumpAndSettle();
        expect(s.server.feedback, hasLength(1));
        expect(t.testTextInput.hasAnyClients, isFalse, reason: '보내면 키보드도 내려갑니다');
      });
    }

    testWidgets('글 칸 밖(제목)을 누르면 키보드가 내려간다 — 전역 바깥 탭', (t) async {
      await _host(t);
      await _openSheet(t);
      await t.tap(_text);
      await t.pumpAndSettle();
      expect(t.testTextInput.hasAnyClients, isTrue);
      await t.tap(find.text('의견 보내기'));
      await t.pumpAndSettle();
      expect(t.testTextInput.hasAnyClients, isFalse);
      expect(_send, findsOneWidget, reason: '시트는 그대로');
    });
  });

  group('360px · 글자 1.3배', () {
    for (final (name, theme) in [('밝게', mbLight), ('어둡게', mbDark)]) {
      testWidgets('$name — 사진 3장 · 긴 글 · 오류 줄이 있어도 넘치지 않는다', (t) async {
        t.platformDispatcher.textScaleFactorTestValue = 1.3;
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        final s = await _host(t, size: const Size(360, 740), theme: theme());
        s.fakes.gallery = [_jpeg];
        s.server
          ..status = 400
          ..reply = {'ok': false, 'error': '의견 글이나 화면 중 하나는 있어야 합니다 — 아주 긴 까닭이 와도 줄을 바꿔 보여 줍니다'};
        await _openSheet(t);
        expect(t.takeException(), isNull);
        /* 「사진 추가」 칸이 있을 때(1.3배 글자가 작은 칸 안에 드는가). */
        final addRect = t.getRect(_add);
        final addLabel = t.getRect(find.descendant(of: _add, matching: find.text('사진 추가')));
        expect(addLabel.left, greaterThanOrEqualTo(addRect.left));
        expect(addLabel.right, lessThanOrEqualTo(addRect.right));
        expect(addLabel.bottom, lessThanOrEqualTo(addRect.bottom));

        await t.tap(_add);
        await t.pumpAndSettle();
        await t.tap(_add);
        await t.pumpAndSettle();
        expect(_thumbs, findsNWidgets(3));
        await t.enterText(_text, '긴 글 ' * 80);
        await t.pump();
        await t.tap(_send);
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        expect(_error, findsOneWidget);

        for (final f in [_send, _error, _thumb(2), _text]) {
          final r = t.getRect(f);
          expect(r.left, greaterThanOrEqualTo(0), reason: '$f');
          expect(r.right, lessThanOrEqualTo(360), reason: '$f');
          expect(r.bottom, lessThanOrEqualTo(740), reason: '$f');
        }
        /* 색은 테마에서 — 어둡게에서도 오류 줄이 그 테마의 bad 색. */
        final ctx = t.element(_error);
        expect(t.widget<Text>(_error).style?.color, mb(ctx).bad);
        expect(Theme.of(ctx).brightness, theme().brightness);
      });
    }
  });

  group('설정 — 도움말', () {
    /* [testing] 을 주면 그 값을 답하는 서버에 물은 새 판 확인기를 겁니다. 안 주면 확인기가
       없습니다 — 모르는 것이라 시험 중으로 봅니다. */
    Future<UpdateCheck?> updateCheck(WidgetTester t, _Server server, Api api, Object? testing) async {
      if (testing == null) return null;
      server.testing = testing;
      final u = UpdateCheck(api: api, platform: TargetPlatform.android, web: false);
      await t.runAsync(u.start);
      return u;
    }

    Future<_Fakes> openSettings(WidgetTester t,
        {Size size = const Size(1000, 4000), Object? testing, double text = 1.0}) async {
      final s = await _host(t, size: size);
      t.platformDispatcher.textScaleFactorTestValue = text;
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      final update = await updateCheck(t, s.server, s.api, testing);
      await t.pumpWidget(Scope(
        state: await AppState.boot(),
        api: s.api,
        update: update,
        onServerChange: (_) async {},
        child: MaterialApp(
          theme: mbLight(),
          builder: edgeSafe,
          home: Builder(
            builder: (c) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(c)
                      .push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen())),
                  child: const Text('첫 화면'),
                ),
              ),
            ),
          ),
        ),
      ));
      await t.tap(find.text('첫 화면'));
      await t.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);
      return s.fakes;
    }

    Finder cardOf(Finder inside) =>
        find.ancestor(of: inside, matching: find.byType(MbCard)).first;

    testWidgets('「지우기」 위 · 동기화 밑에 「도움말」 카드 — 말풍선 스위치와 한 줄 폭 「앱 안내 다시 보기」', (t) async {
      await openSettings(t);
      final bubble = find.byKey(const Key('settings-feedback-bubble'));
      final welcome = find.byKey(const Key('settings-welcome'));
      expect(find.text('도움말'), findsOneWidget);
      expect(find.byKey(const Key('settings-feedback')), findsNothing,
          reason: '「의견 보내기」 줄은 없습니다 — 화면 옆 말풍선이 같은 일을 합니다');
      expect(find.text('의견 보내기'), findsNothing);
      expect(find.descendant(of: bubble, matching: find.text('의견 버튼 보이기')), findsOneWidget);
      expect(find.descendant(of: welcome, matching: find.text('앱 안내 다시 보기')), findsOneWidget);
      final help = cardOf(bubble);
      expect(t.widget(cardOf(welcome)), same(t.widget(help)), reason: '두 줄이 한 카드에');
      expect(t.getRect(bubble).bottom, lessThanOrEqualTo(t.getRect(welcome).top), reason: '스위치가 위');
      final wipe = cardOf(find.text('이 기기에서 전부 지우기'));
      expect(t.getRect(help).bottom, lessThanOrEqualTo(t.getRect(wipe).top));
      expect(t.getRect(find.byType(SyncSettingsCard)).bottom, lessThanOrEqualTo(t.getRect(help).top));
      /* 카드 안을 꽉 채우는 폭 — 작은 단추면 못 찾습니다. */
      final inner = t.getRect(help).width - 2 - 32;   // 테두리 · 카드 여백
      expect(t.getRect(welcome).width, closeTo(inner, 1.0));
      expect(t.getRect(bubble).width, closeTo(inner, 1.0));
    });

    testWidgets('「의견 버튼 보이기」(시험 끝) — 말풍선과 같은 값: 끄면 곧바로 · 저장되고, 켜면 돌아온다', (t) async {
      feedbackBubbleOn.value = true;
      addTearDown(() => feedbackBubbleOn.value = true);
      await openSettings(t, size: const Size(390, 844), testing: false);
      final sw = find.byKey(const Key('settings-feedback-bubble'));
      await t.scrollUntilVisible(sw, 300, scrollable: find.byType(Scrollable).first);
      await t.pumpAndSettle();
      expect(t.widget<SwitchListTile>(sw).value, isTrue, reason: '처음에는 켜져 있습니다');
      expect(t.widget<SwitchListTile>(sw).onChanged, isNotNull, reason: '시험이 끝났으면 잠기지 않습니다');
      expect(find.descendant(of: sw, matching: find.text('화면 가장자리 말풍선 · 꾹 눌러 옮겨요')), findsOneWidget);
      await t.tap(sw);
      await t.pumpAndSettle();
      expect(feedbackBubbleOn.value, isFalse);
      expect(t.widget<SwitchListTile>(sw).value, isFalse);
      final sp = await SharedPreferences.getInstance();
      expect(sp.getBool(kFeedbackBubbleOnKey), isFalse, reason: '이 기기에 저장(동기화 settings 가 아님)');
      expect(((await AppState.boot()).state['settings'] as Map?)?.containsKey('feedbackBubble') ?? false, isFalse);

      /* 말풍선을 X 로 치운 값도 같은 곳 — 스위치가 곧바로 따라옵니다. */
      await setFeedbackBubbleOn(true);
      await t.pump();
      expect(t.widget<SwitchListTile>(sw).value, isTrue);
      expect(sp.getBool(kFeedbackBubbleOnKey), isTrue);
    });

    Future<({UpdateCheck? update, _Server server})> savedOff(WidgetTester t, Object? testing) async {
      feedbackBubbleOn.value = true;
      addTearDown(() => feedbackBubbleOn.value = true);
      final s = await _host(t);
      SharedPreferences.setMockInitialValues({kFeedbackBubbleOnKey: false});
      final update = await updateCheck(t, s.server, s.api, testing);
      await t.pumpWidget(Scope(
        state: await AppState.boot(),
        api: s.api,
        update: update,
        onServerChange: (_) async {},
        child: MaterialApp(theme: mbLight(), builder: edgeSafe, home: const SettingsScreen()),
      ));
      await t.pumpAndSettle();
      final sw = find.byKey(const Key('settings-feedback-bubble'));
      await t.scrollUntilVisible(sw, 300, scrollable: find.byType(Scrollable).first);
      await t.pumpAndSettle();
      return (update: update, server: s.server);
    }

    testWidgets('설정을 열면 저장된 값을 읽는다 — 시험이 끝났고 숨겨 둔 기기에서는 꺼진 채로 보인다', (t) async {
      await savedOff(t, false);
      final sw = find.byKey(const Key('settings-feedback-bubble'));
      expect(t.widget<SwitchListTile>(sw).value, isFalse);
      expect(t.widget<SwitchListTile>(sw).onChanged, isNotNull);
    });

    /* 주인의 말: "테스트기간에는 … 없앨수없어요". 시험 중에는 스위치도 켜진 채 잠급니다 — 옛 판에서
       꺼 둔 기기도(말풍선은 그래도 뜹니다, feedback_bubble_test.dart). 누르면 아무 일도 없습니다. */
    for (final (name, testing) in [('서버 testing 참', true), ('확인기 없음(모름)', null), ('틀린 값', 'yes')]) {
      testWidgets('시험 기간($name) — 저장이 꺼짐이어도 켜진 채 잠김 · 「테스트 기간에는 켜 둡니다」', (t) async {
        await savedOff(t, testing);
        final sw = find.byKey(const Key('settings-feedback-bubble'));
        expect(feedbackBubbleOn.value, isFalse, reason: '저장된 값은 그대로');
        expect(t.widget<SwitchListTile>(sw).value, isTrue);
        expect(t.widget<SwitchListTile>(sw).onChanged, isNull, reason: '잠김');
        expect(find.descendant(of: sw, matching: find.text('테스트 기간에는 켜 둡니다')), findsOneWidget);
        await t.tap(sw);
        await t.pumpAndSettle();
        expect(feedbackBubbleOn.value, isFalse, reason: '눌러도 안 바뀝니다');
        final sp = await SharedPreferences.getInstance();
        expect(sp.getBool(kFeedbackBubbleOnKey), isFalse);
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('시험이 끝나면(서버 testing 거짓) 연 채로도 곧바로 풀리고, 다시 시험을 켜면 잠긴다', (t) async {
      final (:update, :server) = await savedOff(t, true);
      final sw = find.byKey(const Key('settings-feedback-bubble'));
      expect(t.widget<SwitchListTile>(sw).onChanged, isNull);
      /* 주인이 시험을 끝냄(--testing=off) — 확인기가 새로 물으면. */
      server.testing = false;
      await t.runAsync(() => update!.check(force: true));
      await t.pumpAndSettle();
      expect(t.widget<SwitchListTile>(sw).value, isFalse, reason: '꺼 둔 대로');
      expect(t.widget<SwitchListTile>(sw).onChanged, isNotNull, reason: '풀림');
      await t.tap(sw);
      await t.pumpAndSettle();
      expect(feedbackBubbleOn.value, isTrue);

      server.testing = true;
      await t.runAsync(() => update!.check(force: true));
      await t.pumpAndSettle();
      expect(t.widget<SwitchListTile>(sw).value, isTrue);
      expect(t.widget<SwitchListTile>(sw).onChanged, isNull);
    });

    for (final (name, testing) in [('잠김', true), ('풀림', false)]) {
      testWidgets('360px · 글자 1.3배 — 도움말 카드가 넘치지 않는다($name)', (t) async {
        await openSettings(t, size: const Size(360, 640), testing: testing, text: 1.3);
        final sw = find.byKey(const Key('settings-feedback-bubble'));
        await t.scrollUntilVisible(sw, 300, scrollable: find.byType(Scrollable).first);
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        expect(t.getRect(sw).right, lessThanOrEqualTo(360));
      });
    }

    testWidgets('「앱 안내 다시 보기」 — 눌러도 던지지 않는다', (t) async {
      await openSettings(t, size: const Size(390, 844));
      final welcome = find.byKey(const Key('settings-welcome'));
      await t.scrollUntilVisible(welcome, 300, scrollable: find.byType(Scrollable).first);
      await t.pumpAndSettle();
      await t.tap(welcome);
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(t.takeException(), isNull);
    });
  });

  /* 진짜 셸 위의 화면 옆 말풍선으로 — 말풍선은 Navigator 위에 있어서 맨 위 화면의
     context 를 건넵니다(Scaffold 위). 화면 이름이 지금 탭의 이름으로 가고, 화면이 붙어
     있어야 합니다. 앱바에는 의견 단추가 없습니다. */
  group('셸의 말풍선', () {
    testWidgets('홈에서 누르면 화면이 붙고 「홈」 으로, 식단 탭에서는 「식단」 으로 간다', (t) async {
      final s = await _host(t);
      final app = await AppState.boot();
      app.store.set({
        'guest': true,
        'onboarded': true,
        'profile': {'sex': 'male', 'age': 22, 'heightCm': 187, 'activityLevel': 'moderate',
            'trainingAge': 'novice', 'daysPerWeek': 4, 'mealsPerDay': 3},
      });
      markTesterWelcomeSeen(app);
      app.store.addScan({'id': 's1', 'weightKg': 86.7, 'smmKg': 38.0, 'bfmKg': 20.0,
          'pbfPct': 23.1, 'measuredAt': '2026-03-01T00:00:00.000Z'});
      await t.pumpWidget(Scope(
        state: app,
        api: s.api,
        onServerChange: (_) async {},
        child: MaterialApp(
          theme: mbLight(),
          navigatorObservers: [feedbackRoutes],
          builder: appFrame,
          home: const Shell(),
        ),
      ));
      await t.pump(const Duration(milliseconds: 300));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.descendant(of: find.byType(AppBar), matching: find.byIcon(LucideIcons.messageSquare)),
          findsNothing, reason: '앱바의 의견 단추는 뺐습니다 — 같은 일을 하는 단추가 둘이면 안 됩니다');
      final bubble = find.byKey(const Key('feedback-bubble'));
      expect(bubble.hitTestable(), findsOneWidget);

      await t.tap(bubble);
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(s.fakes.captures, 1);
      expect(_thumbs, findsOneWidget);
      await t.tap(_send);
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(s.server.feedback.single.body['screen'], '홈');
      expect(s.server.feedback.single.images, hasLength(1));
      expect(_send, findsNothing);

      await t.tap(find.widgetWithText(NavigationDestination, '식단'));
      await t.pump(const Duration(milliseconds: 300));
      await t.pump(const Duration(seconds: 4));   // 앞의 「보냈어요」 알림이 걷히게
      await t.tap(bubble);
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      await t.enterText(_text, '식단에서');
      await t.pump();
      await t.tap(_send);
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(s.server.feedback, hasLength(2));
      expect(s.server.feedback.last.body['screen'], '식단');
      expect(s.server.feedback.last.body['text'], '식단에서');
      expect(t.takeException(), isNull);
    });
  });

  group('화면 캡처(진짜로 굽기)', () {
    testWidgets('앱 맨 위 경계를 PNG 로 — 배율은 min(기기 배율, 1.5)', (t) async {
      t.view.physicalSize = const Size(390 * 3, 844 * 3);
      t.view.devicePixelRatio = 3.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        theme: mbDark(),
        builder: (c, child) => appCaptureBoundary(edgeSafe(c, child)),
        home: Scaffold(appBar: AppBar(title: const Text('홈')), body: const Center(child: Text('찍힐 화면'))),
      ));
      final bytes = await t.runAsync(captureAppScreen);
      expect(bytes, isNotNull);
      expect(bytes!.sublist(0, 8), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
      expect(bytes.length, lessThanOrEqualTo(kFeedbackImageMaxBytes));
      /* IHDR 의 가로 · 세로(큰 끝) — 390×844 논리 픽셀 × 1.5. */
      final bd = ByteData.sublistView(bytes);
      expect(bd.getUint32(16), 585);
      expect(bd.getUint32(20), 1266);
    });

    /* 위 시험은 main.dart 의 builder 를 흉내 냅니다 — 여기서는 진짜 앱으로. 앱은 켜는 동안
       MaterialApp 을 바로 내놓고, 준비되면 그 위에 Scope 를 씌웁니다(부모가 바뀜). 경계가
       GlobalKey 라 그때 옮겨 붙어야 합니다 — 떨어지면 말풍선이 조용히 캡처 없이 엽니다. */
    testWidgets('진짜 앱(main.dart) — 켜는 중에도, 준비된 뒤에도 앱 맨 위가 찍힌다', (t) async {
      SharedPreferences.setMockInitialValues({'mybody.server.v1': 'https://x.test'});
      PackageInfo.setMockInitialValues(
          appName: 'Mybody', packageName: 'test.mybody', version: '0.2.17',
          buildNumber: '310', buildSignature: '');
      await t.pumpWidget(const MyBodyApp());
      final early = await t.runAsync(captureAppScreen);
      expect(early, isNotNull, reason: '켜는 중(도는 원 화면)');
      expect(sniffImageType(early!), 'image/png');
      for (var i = 0; i < 30 && find.byType(Shell).evaluate().isEmpty; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(Shell), findsOneWidget);
      final bytes = await t.runAsync(captureAppScreen);
      expect(bytes, isNotNull, reason: '준비된 뒤(Scope 가 위에 붙은 뒤)에도 경계가 살아 있어야 합니다');
      expect(sniffImageType(bytes!), 'image/png');
      expect(bytes.length, lessThanOrEqualTo(kFeedbackImageMaxBytes));
    });

    testWidgets('경계가 없으면 null — 캡처 없이 연다', (t) async {
      await t.pumpWidget(const MaterialApp(home: Scaffold(body: Text('경계 없음'))));
      expect(await t.runAsync(captureAppScreen), isNull);
    });

    testWidgets('1배로 구워도 1.5MB 를 넘으면 null', (t) async {
      t.view.physicalSize = const Size(1000 * 2, 1000 * 2);
      t.view.devicePixelRatio = 2.0;
      addTearDown(t.view.reset);
      final noise = (await t.runAsync(() => _noise(1000, 1000)))!;
      await t.pumpWidget(MaterialApp(
        builder: (c, child) => appCaptureBoundary(child!),
        home: RawImage(image: noise, fit: BoxFit.fill, filterQuality: FilterQuality.none),
      ));
      expect(await t.runAsync(captureAppScreen), isNull);
      noise.dispose();
    });
  });

  group('사진 손질', () {
    test('앞머리로 형식을 본다 — PNG · JPEG 만', () {
      expect(sniffImageType(_png), 'image/png');
      expect(sniffImageType(_jpeg), 'image/jpeg');
      expect(sniffImageType(Uint8List.fromList([0x47, 0x49, 0x46, 0x38])), isNull, reason: 'GIF');
      expect(sniffImageType(Uint8List(0)), isNull);
    });

    testWidgets('PNG · JPEG 은 그대로, 다른 형식(BMP)은 다시 그려 PNG 로, 그림이 아니면 null', (t) async {
      await t.runAsync(() async {
        final png = await prepareFeedbackImage(_png);
        expect(png?.type, 'image/png');
        expect(png?.bytes, _png);
        final jpg = await prepareFeedbackImage(_jpeg);
        expect(jpg?.type, 'image/jpeg');
        expect(jpg?.bytes, _jpeg, reason: 'EXIF 가 없으면 바뀔 것이 없습니다');

        final bmp = await prepareFeedbackImage(_bmp(3, 2));
        expect(bmp?.type, 'image/png');
        expect(sniffImageType(bmp!.bytes), 'image/png');
        final bd = ByteData.sublistView(bmp.bytes);
        expect([bd.getUint32(16), bd.getUint32(20)], [3, 2]);

        expect(await prepareFeedbackImage(Uint8List.fromList(utf8.encode('그림이 아닙니다'))), isNull);
      });
    });

    testWidgets('1.5MB 를 넘는 PNG 는 더 작게 다시 그려 1.5MB 안으로', (t) async {
      await t.runAsync(() async {
        final img = await _noise(1000, 1000);
        final big = (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
        img.dispose();
        expect(big.length, greaterThan(kFeedbackImageMaxBytes), reason: '잡음 그림은 PNG 로 잘 안 줄어듭니다');
        final out = await prepareFeedbackImage(big);
        expect(out, isNotNull);
        expect(out!.type, 'image/png');
        expect(out.bytes.length, lessThanOrEqualTo(kFeedbackImageMaxBytes));
        final bd = ByteData.sublistView(out.bytes);
        expect(bd.getUint32(16), lessThan(1000));
        expect(bd.getUint32(16), bd.getUint32(20), reason: '가로세로 비율은 그대로');
      });
    });

    for (final big in [false, true]) {
      test('JPEG 의 GPS 는 비우고 XMP 는 빼되, 방향 · 그림은 그대로 (${big ? 'MM' : 'II'})', () {
        final src = _jpegWithGps(bigEndian: big);
        final out = scrubJpegLocation(src.bytes);
        expect(out.sublist(0, 2), [0xFF, 0xD8]);
        expect(_indexOf(out, 'http://ns.adobe.com/xap'.codeUnits), -1, reason: 'XMP 는 통째로 뺍니다');
        expect(_indexOf(out, 'GPS-IN-XMP'.codeUnits), -1);
        expect(out.length, src.bytes.length - src.xmpLength);
        /* 그림(SOS 부터 끝)은 한 바이트도 안 바뀝니다. */
        final sos = _indexOf(src.bytes, const [0xFF, 0xDA]);
        expect(out.sublist(out.length - (src.bytes.length - sos)), src.bytes.sublist(sos));

        final tiff = _indexOf(out, 'Exif'.codeUnits) + 6;
        int u16(int o) => big ? out[o] << 8 | out[o + 1] : out[o] | out[o + 1] << 8;
        /* 방향(0x0112 = 6)은 그대로 — 빼면 세로 사진이 눕습니다. */
        expect(u16(tiff + 10), 0x0112);
        expect(u16(tiff + 18), 6);
        /* GPS 칸 수 0, 칸들 · 위도 값 0. */
        expect(u16(tiff + src.gpsOffset), 0);
        expect(out.sublist(tiff + src.gpsOffset, tiff + src.gpsOffset + 2 + 2 * 12 + 4).every((b) => b == 0), isTrue);
        expect(out.sublist(tiff + src.latOffset, tiff + src.latOffset + 24).every((b) => b == 0), isTrue);
        expect(_indexOf(out, const [0x4E, 0x00, 0x00, 0x00]), -1, reason: "위도 방향 'N' 도 사라집니다");
      });
    }

    /* 처리방침이 "사진에 담긴 위치 정보는 지우고 보냅니다" 라고 적었습니다 — PNG 도 참이어야
       합니다(안드로이드 고르기 화면은 투명한 그림을 PNG 로 다시 구우며 원본 EXIF 의 GPS 를
       옮겨 붙입니다). CRC 는 gzip(dart:io)이 센 것과 대조 — 앱의 CRC 가 헛돌지 않게. */
    testWidgets('PNG 의 eXIf GPS 는 비우고(방향 · CRC 는 맞게) 글 덩어리(XMP 등)는 빼되, 그림은 그대로 열린다',
        (t) async {
      final src = _pngWithGps();
      final out = scrubPngLocation(src.bytes);
      expect(out.sublist(0, 8), src.bytes.sublist(0, 8), reason: 'PNG 머리');
      final chunks = _pngChunks(out);
      expect(chunks.map((c) => c.type), ['IHDR', 'eXIf', 'IDAT', 'IEND'], reason: '글 덩어리 셋은 빠집니다');
      expect(_indexOf(out, 'GPS-IN-XMP'.codeUnits), -1);
      expect(_indexOf(out, 'GPS-IN-TEXT'.codeUnits), -1);
      for (final c in chunks) {
        expect(c.crc, _gzipCrc([...c.type.codeUnits, ...c.data]), reason: '${c.type} 의 CRC');
      }
      final tiff = chunks[1].data;
      int u16(int o) => tiff[o] | tiff[o + 1] << 8;
      expect(u16(10), 0x0112);
      expect(u16(18), 6, reason: '방향은 그대로 — 빼면 세로 사진이 눕습니다');
      expect(u16(src.gpsOffset), 0, reason: 'GPS 칸 수 0');
      expect(tiff.sublist(src.latOffset, src.latOffset + 24).every((b) => b == 0), isTrue, reason: '위도 값 0');
      expect(chunks[2].data, _pngChunks(_png)[1].data, reason: '그림 자료(IDAT)는 한 바이트도 안 바뀝니다');

      final prepared = await prepareFeedbackImage(src.bytes);
      expect(prepared?.type, 'image/png');
      expect(prepared?.bytes, out, reason: '고른 PNG 도 이 길을 거칩니다');
      await t.runAsync(() async {
        final codec = await ui.instantiateImageCodec(out);
        final img = (await codec.getNextFrame()).image;
        expect([img.width, img.height], [1, 1], reason: '지운 뒤에도 열리는 그림');
        img.dispose();
        codec.dispose();
      });
    });

    test('PNG 에 지울 것이 없거나 모양이 낯설면 손대지 않는다(같은 객체)', () {
      expect(identical(scrubPngLocation(_png), _png), isTrue, reason: '바꿀 것이 없음');
      expect(identical(scrubPngLocation(_jpeg), _jpeg), isTrue, reason: 'PNG 가 아님');
      final noEnd = Uint8List.fromList(_png.sublist(0, 58));
      expect(identical(scrubPngLocation(noEnd), noEnd), isTrue, reason: 'IEND 없음');
      final broken = Uint8List.fromList([..._png.sublist(0, 33), 0x7F, 0xFF, 0xFF, 0xFF, ..._png.sublist(37)]);
      expect(identical(scrubPngLocation(broken), broken), isTrue, reason: '길이가 파일 밖을 가리킴');
    });

    test('JPEG 이 아니거나 모양이 낯설면 손대지 않는다', () {
      expect(identical(scrubJpegLocation(_png), _png), isTrue);
      final broken = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE1, 0x7F, 0xFF, 0x45]);
      expect(identical(scrubJpegLocation(broken), broken), isTrue, reason: '길이가 파일 밖을 가리킴');
    });
  });

  group('곁 정보', () {
    test('판 — 0.2.17+310, 빌드가 없거나 판과 같으면 판만, 약속 밖이면 안 싣는다', () {
      expect(feedbackAppVersion('0.2.17', '310'), '0.2.17+310');
      expect(feedbackAppVersion('0.2.17', ''), '0.2.17');
      expect(feedbackAppVersion('0.2.17', '0.2.17'), '0.2.17');
      expect(feedbackAppVersion('', '310'), isNull);
      expect(feedbackAppVersion('판0.2', '1'), isNull, reason: 'ASCII 만');
      expect(feedbackAppVersion('1' * 30, '310'), isNull, reason: '32자까지');
    });

    test('기종 — android · ios, 그 밖은 null', () {
      try {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        expect(feedbackPlatform(), 'ios');
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        expect(feedbackPlatform(), 'android');
        debugDefaultTargetPlatformOverride = TargetPlatform.linux;
        expect(feedbackPlatform(), isNull);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    test('실패 문구 — 429 · 닿지 못함 · 옛 서버 · 서버의 말 그대로', () {
      expect(feedbackFailure(const ApiResult(429, {'ok': false, 'error': '아무 말'})),
          '오늘은 더 보낼 수 없어요 — 내일 다시');
      expect(feedbackFailure(const ApiResult(0, {})), '서버에 닿지 못했어요 — 잠시 뒤 다시 눌러 주세요');
      expect(feedbackFailure(const ApiResult(404, {'ok': false, 'reason': '그런 경로가 없습니다'})),
          '서버가 아직 의견을 못 받아요 — 다음 판에서 다시');
      /* 옛 서버는 로그인 안 한 사람에게 모르는 길에 로그인부터 묻습니다 — 새 서버는 이 길에서
         401 을 안 주므로 401 도 옛 서버. "로그인이 필요합니다" 를 그대로 보이지 않습니다. */
      expect(feedbackFailure(const ApiResult(401, {'ok': false, 'reason': '로그인이 필요합니다'})),
          '서버가 아직 의견을 못 받아요 — 다음 판에서 다시');
      expect(feedbackFailure(const ApiResult(400, {'ok': false, 'error': '사진은 3장까지 붙일 수 있습니다'})),
          '사진은 3장까지 붙일 수 있습니다');
      expect(feedbackFailure(const ApiResult(400, {'ok': false, 'reason': '까닭만'})), '까닭만');
      expect(feedbackFailure(const ApiResult(413, {})), '사진이 너무 커요 — 한 장을 빼고 다시');
      expect(feedbackFailure(const ApiResult(500, {})), '보내지 못했어요 (500) — 다시 눌러 주세요');
    });

    testWidgets('화면 이름 — 위에 Scaffold 가 있으면 그것, 없으면 아래로 찾은 첫 Scaffold 의 앱바 제목', (t) async {
      late BuildContext above, inside;
      await t.pumpWidget(MaterialApp(
        home: Builder(builder: (c) {
          above = c;
          return Scaffold(
            appBar: AppBar(title: const Text('식단')),
            body: Builder(builder: (c2) {
              inside = c2;
              return const SizedBox();
            }),
          );
        }),
      ));
      expect(feedbackScreenName(above), '식단');
      expect(feedbackScreenName(inside), '식단');
      await t.pumpWidget(MaterialApp(home: Builder(builder: (c) {
        above = c;
        return const Scaffold(body: SizedBox());
      })));
      expect(feedbackScreenName(above), isNull, reason: '앱바가 없으면 이름 없이');
    });

    test('sendFeedback — 빈 칸은 안 싣고, 사진은 base64', () async {
      Map<String, dynamic>? body;
      final api = Api(
        baseUrl: 'https://x.test',
        client: MockClient((req) async {
          body = (jsonDecode(req.body) as Map).cast<String, dynamic>();
          return http.Response('{"ok":true,"id":1}', 200, headers: {'content-type': 'application/json'});
        }),
      );
      final r = await api.sendFeedback(text: '  ', images: [(type: 'image/png', bytes: _png)], screen: '');
      expect(r.ok, isTrue);
      expect(body, {
        'images': [
          {'type': 'image/png', 'data': base64Encode(_png)},
        ],
      });
    });
  });
}

/* --- 시험용 그림 만들기 --------------------------------------------------------- */

/// 잡음 그림(불투명). PNG 로 거의 안 줄어서 크기 상한을 시험하기 좋습니다.
Future<ui.Image> _noise(int w, int h) {
  final rnd = math.Random(7);
  final px = Uint8List(w * h * 4);
  for (var i = 0; i < px.length; i += 4) {
    px[i] = rnd.nextInt(256);
    px[i + 1] = rnd.nextInt(256);
    px[i + 2] = rnd.nextInt(256);
    px[i + 3] = 255;
  }
  final c = Completer<ui.Image>();
  ui.decodeImageFromPixels(px, w, h, ui.PixelFormat.rgba8888, c.complete);
  return c.future;
}

/// 24비트 BMP — 서버가 모르는 형식의 대표.
Uint8List _bmp(int w, int h) {
  final row = (w * 3 + 3) & ~3;
  final size = 54 + row * h;
  final b = ByteData(size);
  b.setUint8(0, 0x42);
  b.setUint8(1, 0x4D);
  b.setUint32(2, size, Endian.little);
  b.setUint32(10, 54, Endian.little);
  b.setUint32(14, 40, Endian.little);
  b.setInt32(18, w, Endian.little);
  b.setInt32(22, h, Endian.little);
  b.setUint16(26, 1, Endian.little);
  b.setUint16(28, 24, Endian.little);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final o = 54 + y * row + x * 3;
      b.setUint8(o, 200);
      b.setUint8(o + 1, (x * 40) & 0xFF);
      b.setUint8(o + 2, (y * 90) & 0xFF);
    }
  }
  return b.buffer.asUint8List();
}

/// EXIF(방향 6 · GPS 위도) + XMP 가 든 JPEG 조각. 오프셋은 TIFF 머리 기준.
({Uint8List bytes, int gpsOffset, int latOffset, int xmpLength}) _jpegWithGps({bool bigEndian = false}) {
  final e = bigEndian ? Endian.big : Endian.little;
  const ifd0 = 8;
  const gps = ifd0 + 2 + 2 * 12 + 4; // 38
  const lat = gps + 2 + 2 * 12 + 4; // 68
  final tiff = ByteData(lat + 24);
  tiff.setUint8(0, bigEndian ? 0x4D : 0x49);
  tiff.setUint8(1, bigEndian ? 0x4D : 0x49);
  tiff.setUint16(2, 42, e);
  tiff.setUint32(4, ifd0, e);
  tiff.setUint16(ifd0, 2, e);
  // 방향: SHORT 1 = 6
  tiff.setUint16(ifd0 + 2, 0x0112, e);
  tiff.setUint16(ifd0 + 4, 3, e);
  tiff.setUint32(ifd0 + 6, 1, e);
  tiff.setUint16(ifd0 + 10, 6, e);
  // GPS 표: LONG 1 = gps
  tiff.setUint16(ifd0 + 14, 0x8825, e);
  tiff.setUint16(ifd0 + 16, 4, e);
  tiff.setUint32(ifd0 + 18, 1, e);
  tiff.setUint32(ifd0 + 22, gps, e);
  tiff.setUint32(ifd0 + 26, 0, e);
  // GPS 칸: 위도 방향 ASCII 2 'N\0'(칸 안), 위도 RATIONAL 3(밖)
  tiff.setUint16(gps, 2, e);
  tiff.setUint16(gps + 2, 0x0001, e);
  tiff.setUint16(gps + 4, 2, e);
  tiff.setUint32(gps + 6, 2, e);
  tiff.setUint8(gps + 10, 0x4E);
  tiff.setUint16(gps + 14, 0x0002, e);
  tiff.setUint16(gps + 16, 5, e);
  tiff.setUint32(gps + 18, 3, e);
  tiff.setUint32(gps + 22, lat, e);
  tiff.setUint32(gps + 26, 0, e);
  for (final (i, v) in [(37, 1), (33, 1), (1234, 100)].indexed) {
    tiff.setUint32(lat + i * 8, v.$1, e);
    tiff.setUint32(lat + i * 8 + 4, v.$2, e);
  }
  final exif = [...'Exif'.codeUnits, 0, 0, ...tiff.buffer.asUint8List()];
  final xmp = [...'http://ns.adobe.com/xap/1.0/'.codeUnits, 0, ...'<x:xmpmeta>GPS-IN-XMP</x:xmpmeta>'.codeUnits];
  List<int> seg(int marker, List<int> data) =>
      [0xFF, marker, (data.length + 2) >> 8, (data.length + 2) & 0xFF, ...data];
  final xmpSeg = seg(0xE1, xmp);
  final bytes = Uint8List.fromList([
    0xFF, 0xD8,
    ...seg(0xE0, [0x4A, 0x46, 0x49, 0x46, 0x00, 0x01, 0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00]),
    ...seg(0xE1, exif),
    ...xmpSeg,
    0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01, 0x00, 0x00, 0x3F, 0x00,
    0x12, 0x34, 0xFF, 0x00, 0x99, // 그림 자료
    0xFF, 0xD9,
  ]);
  return (bytes: bytes, gpsOffset: gps, latOffset: lat, xmpLength: xmpSeg.length);
}

/// [_png] 에 eXIf(방향 6 · GPS 위도 — [_jpegWithGps] 와 같은 TIFF, II) · tEXt · zTXt · iTXt(XMP)
/// 를 끼운 PNG. 오프셋은 TIFF 머리(= eXIf 자료의 처음) 기준.
({Uint8List bytes, int gpsOffset, int latOffset}) _pngWithGps() {
  final j = _jpegWithGps();
  final at = _indexOf(j.bytes, 'Exif'.codeUnits) + 6;
  final tiff = j.bytes.sublist(at, at + j.latOffset + 24);
  final bytes = Uint8List.fromList([
    ..._png.sublist(0, 33), // 머리 + IHDR
    ..._pngChunk('eXIf', tiff),
    ..._pngChunk('tEXt', [...'Comment'.codeUnits, 0, ...'GPS-IN-TEXT'.codeUnits]),
    ..._pngChunk('zTXt', [...'Raw profile type exif'.codeUnits, 0, 0, ...ZLibEncoder().convert([1, 2, 3])]),
    ..._pngChunk('iTXt', [...'XML:com.adobe.xmp'.codeUnits, 0, 0, 0, 0, 0,
      ...'<x:xmpmeta>GPS-IN-XMP</x:xmpmeta>'.codeUnits]),
    ..._png.sublist(33), // IDAT + IEND
  ]);
  return (bytes: bytes, gpsOffset: j.gpsOffset, latOffset: j.latOffset);
}

List<int> _pngChunk(String type, List<int> data) {
  final crc = _gzipCrc([...type.codeUnits, ...data]);
  List<int> be(int v) => [v >> 24 & 0xFF, v >> 16 & 0xFF, v >> 8 & 0xFF, v & 0xFF];
  return [...be(data.length), ...type.codeUnits, ...data, ...be(crc)];
}

/// PNG 덩어리들(형식 · 자료 · 적힌 CRC).
List<({String type, List<int> data, int crc})> _pngChunks(List<int> b) {
  final out = <({String type, List<int> data, int crc})>[];
  var i = 8;
  while (i + 12 <= b.length) {
    final n = b[i] << 24 | b[i + 1] << 16 | b[i + 2] << 8 | b[i + 3];
    final e = i + 8 + n;
    out.add((
      type: String.fromCharCodes(b.sublist(i + 4, i + 8)),
      data: b.sublist(i + 8, e),
      crc: b[e] << 24 | b[e + 1] << 16 | b[e + 2] << 8 | b[e + 3],
    ));
    i = e + 4;
  }
  return out;
}

/// CRC-32 — 앱의 것과 따로, gzip 꼬리(CRC32 · 길이, 둘 다 리틀 엔디언)에서 읽습니다.
int _gzipCrc(List<int> data) {
  final z = GZipCodec().encode(data);
  final n = z.length;
  return z[n - 8] | z[n - 7] << 8 | z[n - 6] << 16 | z[n - 5] << 24;
}

int _indexOf(List<int> hay, List<int> needle) {
  outer:
  for (var i = 0; i + needle.length <= hay.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (hay[i + j] != needle[j]) continue outer;
    }
    return i;
  }
  return -1;
}
