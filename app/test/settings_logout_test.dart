/* 설정의 「로그아웃」 — 맨 아래 한 곳, 한 번 묻고, 예전 버튼과 똑같이 합니다.
 *
 * 주인 피드백 40: "설정 하단에 로그아웃 버튼 만들어". 예전 로그아웃은 긴 설정
 * 한가운데 「계정」 카드 안, 「계정 관리」 옆의 작은 버튼이라 주인이 못 찾았습니다.
 * 그래서 여기서 지키는 것:
 *
 *   · 자리 — 로그인했으면 「지우기」 카드 **밑**, 작은 글씨(내 기록 내보내기 …)
 *     **위**에 한 줄 폭으로 하나. 계정 카드에는 없습니다(두 곳이면 또 찾습니다).
 *   · 묻기 — 누르면 「로그아웃할까요?」. 「취소」 는 아무것도 안 하고, 「로그아웃」
 *     은 api.signOut(알림 등록 빼기가 그 안 — PushAwareApi) → 설정 닫기.
 *     다이얼로그가 "이 계정의 기록은 이 기기에 따로 보관돼, 다시 로그인하면 돌아와요" 라고
 *     하니, 기록이 화면에서 치워지고(다음 사람 · 다음 계정에 안 보임 — 피드백 52) 같은
 *     계정으로 돌아오면 그대로 돌아오는지 봅니다. 못 보낸 것은 먼저 보내 보고, 큐에 남은
 *     건수는 다이얼로그가 미리 말합니다.
 *   · 느린 서버 — 끝날 때까지 버튼을 막고 「로그아웃하는 중…」. 그동안 다른 창을
 *     열었거나 뒤로 가기를 눌렀어도, 끝나면 셸(첫 화면)만 남습니다 — pop() 하나로
 *     닫던 때는 그 창만 닫히고 설정이 남거나, 셸까지 닫혀 빈 화면이 됐습니다.
 *   · 로그인 안 했으면 버튼이 없습니다.
 *   · 360px · 글자 1.3배 · 밝게/어둡게 — 넘치지 않고 한 줄 폭 그대로. */
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mybody/src/api.dart';
import 'package:mybody/src/app_state.dart';
import 'package:mybody/src/cloud.dart';
import 'package:mybody/src/local_owner.dart';
import 'package:mybody/src/news_store.dart';
import 'package:mybody/src/scope.dart';
import 'package:mybody/src/sync_queue.dart';
import 'package:mybody/src/screens/settings.dart';
import 'package:mybody/src/theme.dart';
import 'package:mybody/src/ui/widgets.dart';

/// signOut 을 몇 번 불렀는지 셉니다 — 앱의 Api(PushAwareApi)는 알림 등록 빼기를
/// signOut 안에서 하므로, 버튼이 **이 길로** 가야 그 일도 됩니다.
class _SpyApi extends Api {
  _SpyApi({required super.baseUrl, super.client});
  int signOuts = 0;
  @override
  Future<void> signOut({bool flush = true, bool thenGuest = false}) async {
    signOuts++;
    await super.signOut(flush: flush, thenGuest: thenGuest);
  }
}

final _logout = find.byKey(const Key('settings-logout'));
final _confirm = find.byKey(const Key('settings-logout-confirm'));
final _cancel = find.byKey(const Key('settings-logout-cancel'));

void main() {
  /// 서버 가짜 — 부른 길을 적고, 전부 ok(로그인 · /me 는 계정 u1). [signOutGate] 가 있으면 로그아웃
  /// 요청은 그게 풀릴 때까지 답하지 않습니다(느린 서버). [failing] 의 길은 망 오류(503) — 큐에 남습니다.
  MockClient server(List<String> seen, {Completer<void>? signOutGate, Set<String> failing = const {}}) =>
      MockClient((req) async {
        final path = req.url.path.replaceFirst('/api', '');
        seen.add('${req.method} $path');
        if (path == '/auth/signout' && signOutGate != null) await signOutGate.future;
        if (failing.contains(path)) return http.Response('', 503);
        final body = <String, Object?>{
          'ok': true,
          if (path == '/auth/signin') 'token': 'tok2',
          if (path == '/auth/signin' || path == '/me') 'user': {'id': 'u1', 'handle': 'me'},
        };
        return http.Response.bytes(utf8.encode(jsonEncode(body)), 200,
            headers: {'content-type': 'application/json; charset=utf-8'});
      });

  /// 셸 자리(첫 화면) 위에 설정을 밀어 올린 상태 — 앱에서 실제로 그렇게 엽니다.
  /// 그래야 「로그아웃하면 설정을 닫는다」 를 볼 수 있습니다.
  /// 앱처럼 엮습니다 — 큐 · 계정 칸(local_owner.dart) · 동기화. [debounce] 는 저장을 모으는 시간.
  Future<({AppState app, _SpyApi api, List<String> seen, SyncQueue queue, CloudSync cloud})> open(
    WidgetTester t, {
    bool signedIn = true,
    Size size = const Size(1000, 4000),
    ThemeData? theme,
    Completer<void>? signOutGate,
    Set<String> failing = const {},
    Duration debounce = Duration.zero,
  }) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    SharedPreferences.setMockInitialValues({});
    final sp = await SharedPreferences.getInstance();
    final seen = <String>[];
    final api = _SpyApi(baseUrl: 'https://x.test',
        client: server(seen, signOutGate: signOutGate, failing: failing));
    if (signedIn) await api.setToken('tok', uid: 'u1');
    final queue = SyncQueue(api: api, storage: PrefsQueue(sp));
    final app = await AppState.boot();
    final slots = AccountSlots(app: app, queue: queue, flushLimit: const Duration(seconds: 2));
    api.accounts = slots;
    final cloud = CloudSync(app: app, api: api, queue: queue, debounce: debounce)..wire();
    slots.cloud = cloud;
    app.store.set({'onboarded': true, 'profile': {'sex': 'male', 'age': 30, 'heightCm': 175}});
    app.store.addScan({'id': 's1', 'weightKg': 80.0, 'smmKg': 35.0, 'bfmKg': 18.0,
        'pbfPct': 22.5, 'measuredAt': '2026-09-01T00:00:00.000Z'});

    await t.pumpWidget(Scope(
      state: app,
      api: api,
      queue: queue,
      cloud: cloud,
      slots: slots,
      onServerChange: (_) async {},
      child: MaterialApp(
        theme: theme ?? mbLight(),
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
    seen.clear();   // 화면이 서면서 부른 것(알림 상태 등)은 빼고 봅니다
    addTearDown(() {
      queue.clear();
      cloud.dispose();
    });
    return (app: app, api: api, seen: seen, queue: queue, cloud: cloud);
  }

  Finder cardOf(Finder inside) =>
      find.ancestor(of: inside, matching: find.byType(MbCard)).first;

  group('자리', () {
    testWidgets('로그인했으면 「지우기」 카드 밑, 작은 글씨 위에 하나 — 계정 카드에는 없다', (t) async {
      await open(t);
      expect(_logout, findsOneWidget);
      expect(find.text('로그아웃'), findsOneWidget, reason: '로그아웃은 한 곳 — 두 곳이면 어느 게 진짜인지 또 찾습니다');

      /* 계정 카드에는 「계정 관리」 만. */
      final account = cardOf(find.text('계정 관리'));
      expect(find.descendant(of: account, matching: find.text('로그아웃')), findsNothing);
      expect(find.descendant(of: account, matching: find.byType(OutlinedButton)), findsOneWidget);

      /* 카드들을 다 지난 맨 끝 — 어떤 카드보다도 아래. */
      final top = t.getRect(_logout).top;
      final cards = find.byType(MbCard);
      expect(cards, findsWidgets);
      for (var i = 0; i < cards.evaluate().length; i++) {
        expect(t.getRect(cards.at(i)).bottom, lessThanOrEqualTo(top + 0.01),
            reason: '카드 하나가 로그아웃보다 아래에 있습니다');
      }
      expect(t.getRect(_logout).bottom, lessThanOrEqualTo(t.getRect(find.text('내 기록 내보내기')).top),
          reason: '작은 글씨(자주 안 쓰는 것)는 로그아웃 밑');

      /* 한 줄 폭 — 설정 여백(16) 안을 꽉 채웁니다. 작은 버튼이면 또 못 찾습니다. */
      expect(t.getRect(_logout).width, closeTo(1000 - 32, 0.01));
    });

    testWidgets('휴대폰 크기에서 끝까지 내려가면 「지우기」 카드 바로 밑에 보인다', (t) async {
      await open(t, size: const Size(390, 844));
      await t.scrollUntilVisible(_logout, 300, scrollable: find.byType(Scrollable).first);
      await t.pumpAndSettle();
      final wipeCard = cardOf(find.text('이 기기에서 전부 지우기'));
      expect(t.getRect(wipeCard).bottom, lessThanOrEqualTo(t.getRect(_logout).top + 0.01));
      /* 둘 사이에 다른 것이 끼지 않습니다 — 카드 아래 여백(12)뿐. */
      expect(t.getRect(_logout).top - t.getRect(wipeCard).bottom, lessThan(24));
      /* 빨강이 아닙니다 — 로그아웃은 아무것도 지우지 않습니다. */
      final ctx = t.element(_logout);
      final fg = t.widget<ButtonStyleButton>(_logout).style?.foregroundColor?.resolve({});
      expect(fg, Theme.of(ctx).colorScheme.onSurface);
      expect(fg, isNot(mb(ctx).bad));
    });

    testWidgets('로그인 안 했으면 로그아웃 버튼이 없고, 계정 카드는 「로그인」', (t) async {
      await open(t, signedIn: false);
      expect(_logout, findsNothing);
      expect(find.text('로그아웃'), findsNothing);
      expect(find.widgetWithText(FilledButton, '로그인'), findsOneWidget);
      expect(find.text('계정 관리'), findsNothing);
    });
  });

  group('누르면', () {
    testWidgets('한 번 묻는다 — 이 계정의 기록은 기기에 따로 보관돼 다시 로그인하면 돌아온다고 말한다', (t) async {
      await open(t);
      await t.tap(_logout);
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('로그아웃할까요?'), findsOneWidget);
      expect(find.text('이 계정의 기록은 이 기기에 따로 보관돼, 다시 로그인하면 돌아와요.'), findsOneWidget);
      expect(find.byKey(const Key('settings-logout-unsent')), findsNothing, reason: '못 보낸 것이 없으면 그 줄도 없음');
      expect(find.descendant(of: _cancel, matching: find.text('취소')), findsOneWidget);
      expect(find.descendant(of: _confirm, matching: find.text('로그아웃')), findsOneWidget);
    });

    testWidgets('「취소」 — 로그인 그대로, 설정도 그대로, 서버에 아무 말도 안 한다', (t) async {
      final s = await open(t);
      await t.tap(_logout);
      await t.pumpAndSettle();
      await t.tap(_cancel);
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(s.api.signedIn, isTrue);
      expect(s.api.signOuts, 0);
      expect(s.seen, isNot(contains('POST /auth/signout')));
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(_logout, findsOneWidget);
    });

    /* 예전 이 시험은 "로그아웃해도 이 기기의 기록이 화면에 남는다" 를 기대값으로 굳혀 두었습니다 —
       그 기록이 다음에 가입한 계정으로 올라갔습니다(피드백 52). 이제는 이 계정의 칸으로 치워지고,
       같은 계정으로 돌아오면 그대로 돌아옵니다. */
    testWidgets('「로그아웃」 — api.signOut 로 로그아웃하고 설정을 닫는다, 기록은 이 계정의 칸으로', (t) async {
      final s = await open(t);
      await t.tap(_logout);
      await t.pumpAndSettle();
      await t.tap(_confirm);
      await t.pumpAndSettle();

      expect(s.api.signOuts, 1, reason: '알림 등록 빼기(PushAwareApi)가 signOut 안에 있습니다 — 그 길로 한 번');
      expect(s.seen, contains('POST /auth/signout'));
      expect(s.api.signedIn, isFalse);
      expect(s.api.token, isNull);
      final sp = await SharedPreferences.getInstance();
      expect(sp.getString('mybody.token.v1'), isNull, reason: '다음에 켜도 로그아웃된 채로');

      expect(find.byType(SettingsScreen), findsNothing, reason: '셸이 로그인 화면으로 바뀌니 설정은 닫습니다');
      expect(find.text('첫 화면'), findsOneWidget);

      expect((s.app.state['scans'] as List?) ?? const [], isEmpty,
          reason: '다음 사람의 「로그인 없이 쓰기」 · 다음 계정에 보이면 안 됩니다');
      expect(s.app.state['onboarded'], isNot(true));
      expect(sp.getString('${kSlotPrefix}https://x.test|u1.state'), contains('s1'), reason: '이 기기에 따로 보관');

      /* 같은 계정으로 다시 로그인하면 돌아옵니다. */
      await s.api.signIn(handle: 'me', password: 'pw');
      await t.pumpAndSettle();
      expect((s.app.state['scans'] as List).map((x) => (x as Map)['id']), ['s1']);
      expect(s.app.state['onboarded'], isTrue);
    });

    testWidgets('로그아웃 전에 못 보낸 것부터 — 3초 모으던 변경도 먼저 이 계정으로 보낸다', (t) async {
      final s = await open(t, debounce: const Duration(minutes: 1));
      s.app.store.addScan({'id': 's2', 'weightKg': 79.5, 'smmKg': 35.1, 'bfmKg': 17.6,
          'measuredAt': '2026-09-20T00:00:00.000Z'});
      await t.pump();
      expect(s.seen, isNot(contains('POST /sync/push')), reason: '아직 모으는 중');
      await t.tap(_logout);
      await t.pumpAndSettle();
      await t.tap(_confirm);
      await t.pumpAndSettle();
      expect(s.seen, contains('POST /sync/push'));
      expect(s.seen.indexOf('POST /sync/push'), lessThan(s.seen.indexOf('POST /auth/signout')),
          reason: '토큰이 살아 있을 때 보내야 이 계정으로 갑니다');
    });

    testWidgets('못 보낸 것이 있으면 확인창이 건수를 말한다', (t) async {
      final s = await open(t, failing: {'/friends/block'});
      s.queue.add('block', {'userId': 'f2'});
      await t.pump();
      expect(s.queue.pending, 1);
      await t.tap(_logout);
      await t.pumpAndSettle();
      expect(find.byKey(const Key('settings-logout-unsent')), findsOneWidget);
      expect(find.textContaining('못 보낸 것 1건'), findsOneWidget);
      await t.tap(_cancel);
      await t.pumpAndSettle();
      s.queue.clear();   // 다시 보내기 타이머를 남기지 않습니다
    });

    testWidgets('서버가 느리면 끝날 때까지 버튼을 막고 「로그아웃하는 중…」', (t) async {
      final gate = Completer<void>();
      final s = await open(t, signOutGate: gate);
      await t.tap(_logout);
      await t.pumpAndSettle();
      await t.tap(_confirm);
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));   // 다이얼로그가 닫히는 동안

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(find.descendant(of: _logout, matching: find.text('로그아웃하는 중…')), findsOneWidget);
      expect(t.widget<ButtonStyleButton>(_logout).onPressed, isNull, reason: '두 번 누르지 않게');

      gate.complete();
      await t.pumpAndSettle();
      expect(s.api.signOuts, 1);
      expect(s.api.signedIn, isFalse);
      expect(find.byType(SettingsScreen), findsNothing);
    });

    /* 느린 로그아웃 동안 설정의 다른 단추는 살아 있습니다. 끝났을 때 맨 위의 것
       하나만 닫으면(pop) 그 창이 닫히고 설정은 로그아웃된 채 남았습니다. */
    testWidgets('기다리는 동안 다른 창을 열었어도 — 끝나면 설정까지 닫혀 첫 화면', (t) async {
      final gate = Completer<void>();
      final s = await open(t, signOutGate: gate);
      await t.tap(_logout);
      await t.pumpAndSettle();
      await t.tap(_confirm);
      await t.pumpAndSettle();
      await t.tap(find.text('내 기록 내보내기'));
      await t.pumpAndSettle();
      expect(find.text('백업'), findsOneWidget);

      gate.complete();
      await t.pumpAndSettle();
      expect(s.api.signedIn, isFalse);
      expect(find.text('백업'), findsNothing);
      expect(find.byType(SettingsScreen), findsNothing, reason: '로그아웃된 설정이 남으면 안 됩니다');
      expect(find.text('첫 화면'), findsOneWidget);
    });

    /* 뒤로 가기로 설정이 닫히는 중에 로그아웃이 끝나면, pop() 은 밑의 셸을
       닫았습니다(설정은 이미 닫히는 중이라 맨 위가 셸). */
    testWidgets('기다리는 동안 뒤로 가기 — 끝나도 첫 화면은 그대로', (t) async {
      final gate = Completer<void>();
      final s = await open(t, signOutGate: gate);
      await t.tap(_logout);
      await t.pumpAndSettle();
      await t.tap(_confirm);
      await t.pumpAndSettle();

      await t.pageBack();
      await t.pump();   // 설정이 닫히는 애니메이션이 막 시작된 때
      gate.complete();
      await t.pump();
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(s.api.signedIn, isFalse);
      expect(find.byType(SettingsScreen), findsNothing);
      expect(find.text('첫 화면'), findsOneWidget, reason: '셸까지 닫으면 빈 화면입니다');
    });
  });

  group('360px · 글자 1.3배', () {
    for (final (name, theme) in [('밝게', mbLight), ('어둡게', mbDark)]) {
      testWidgets('$name — 버튼과 다이얼로그가 넘치지 않는다', (t) async {
        t.platformDispatcher.textScaleFactorTestValue = 1.3;
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        await open(t, size: const Size(360, 780), theme: theme());
        expect(t.takeException(), isNull);

        await t.scrollUntilVisible(_logout, 300, scrollable: find.byType(Scrollable).first);
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        final btn = t.getRect(_logout);
        expect(btn.width, closeTo(360 - 32, 0.01), reason: '한 줄 폭 그대로');
        /* 글자가 버튼 안에 한 줄로 — 1.3배에서 잘리거나 두 줄로 접히지 않습니다. */
        final label = t.getRect(find.descendant(of: _logout, matching: find.text('로그아웃')));
        expect(label.left, greaterThanOrEqualTo(btn.left));
        expect(label.right, lessThanOrEqualTo(btn.right));
        expect(label.height, lessThan(btn.height));
        final ctx = t.element(_logout);
        expect(t.widget<ButtonStyleButton>(_logout).style?.foregroundColor?.resolve({}),
            Theme.of(ctx).colorScheme.onSurface, reason: '어둡게에서도 테마 글자색 — 박아 둔 색이 아닙니다');

        await t.tap(_logout);
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        expect(find.text('로그아웃할까요?'), findsOneWidget);
        final dialog = t.getRect(find.byType(AlertDialog));
        for (final f in [_cancel, _confirm]) {
          final r = t.getRect(f);
          expect(r.left, greaterThanOrEqualTo(dialog.left));
          expect(r.right, lessThanOrEqualTo(dialog.right));
        }
        await t.tap(_cancel);
        await t.pumpAndSettle();
      });
    }
  });
}
