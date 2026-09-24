/* =============================================================================
 * friend_today_test.dart — 친구의 오늘 할 일: 하기로 한 것과 한 것
 *
 * 주인이 v0.2.9 를 써 보고: "친구 탭에도 친구의 오늘 할 일 대시보드를 보여
 * 주고, 한 것은 했다고 표시되게." 줄을 만드는 쪽(friendTodayItems)은 위젯
 * 없이 시험하고, 상세의 오늘 카드와 목록의 한 줄은 화면을 세워서 봅니다.
 *
 * 여기서 지키는 선: **서버가 안 보낸 것은 줄이 없습니다.** week 가 없으면
 * 운동 줄이 없고, today 가 없으면 식단 줄이 없고, checkedIn 이 없으면
 * 체크인 줄이 없습니다. 공유를 끈 것을 "안 했다" 로 그리면 안 됩니다.
 * ========================================================================== */
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:mybody/src/api.dart';
import 'package:mybody/src/app_state.dart';
import 'package:mybody/src/scope.dart';
import 'package:mybody/src/screens/social.dart';
import 'package:mybody/src/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _today = '2026-09-24';

Map<String, Object?> _day(String key, List<String> plan, List<String> done) => {
      'key': key, 'dow': '?', 'dayNum': int.parse(key.substring(8)),
      'plan': plan, 'done': done,
      'kept': plan.isNotEmpty && plan.every(done.contains), 'missed': false,
    };

/// 이번 주 — 어제 헬스 했고, 오늘은 plan/done 대로, 내일 유산소.
Map<String, Object?> _week(List<String> plan, List<String> done) => {
      'start': '2026-09-21',
      'days': [
        _day('2026-09-23', ['gym'], ['gym']),
        _day(_today, plan, done),
        _day('2026-09-25', ['cardio'], []),
      ],
    };

List<String> _ids(List<TodayItem> items) => [for (final i in items) i.id];

void main() {
  group('friendTodayItems', () {
    test('헬스 하기로 하고 했다 → 헬스 줄에 체크', () {
      final items = friendTodayItems({'week': _week(['gym'], ['gym'])}, _today);
      expect(_ids(items), ['gym']);
      expect(items.single.label, '헬스');
      expect(items.single.done, isTrue);
      expect(items.single.detail, isNull);
    });

    test('유산소 하기로 하고 아직 → 유산소 줄에 빈 동그라미', () {
      final items = friendTodayItems({'week': _week(['cardio'], [])}, _today);
      expect(_ids(items), ['cardio']);
      expect(items.single.label, '유산소');
      expect(items.single.done, isFalse);
    });

    test('둘 다 하기로 했으면 순서는 헬스 → 유산소 (계획 목록 순서와 무관)', () {
      final items = friendTodayItems({'week': _week(['cardio', 'gym'], ['cardio'])}, _today);
      expect(_ids(items), ['gym', 'cardio']);
      expect(items[0].done, isFalse);
      expect(items[1].done, isTrue);
    });

    test('오늘 식단을 적었다 → 식단 줄에 체크, kcal 덧말', () {
      final items = friendTodayItems({
        'today': {'date': _today, 'logged': true, 'kcal': 1800, 'p': 140, 'c': 180, 'f': 50},
      }, _today);
      expect(_ids(items), ['diet']);
      expect(items.single.label, '식단 기록');
      expect(items.single.done, isTrue);
      expect(items.single.detail, '1800 kcal');
    });

    test('식단 공유는 하는데 아직 안 적었다 → 빈 동그라미, 덧말 없음', () {
      final items = friendTodayItems({
        'today': {'date': _today, 'logged': false, 'kcal': 0, 'p': 0, 'c': 0, 'f': 0},
      }, _today);
      expect(items.single.done, isFalse);
      expect(items.single.detail, isNull);
    });

    /* 친구가 어제 올리고 오늘 앱을 안 열었으면 today 는 어제 것입니다.
       그걸 오늘 한 일로 그리면 어제 먹은 것이 오늘 체크가 됩니다. */
    test('today 가 어제 것이면 식단은 "아직" 이지 체크가 아니다', () {
      final items = friendTodayItems({
        'today': {'date': '2026-09-23', 'logged': true, 'kcal': 1800},
      }, _today);
      expect(_ids(items), ['diet']);
      expect(items.single.done, isFalse);
      expect(items.single.detail, isNull);
    });

    test('이번 주 체크인 아직 → 체크인 줄에 빈 동그라미', () {
      final items = friendTodayItems({'checkedIn': false}, _today);
      expect(_ids(items), ['checkin']);
      expect(items.single.label, '이번 주 체크인');
      expect(items.single.done, isFalse);
    });

    test('이번 주 체크인 했다 → 체크', () {
      expect(friendTodayItems({'checkedIn': true}, _today).single.done, isTrue);
    });

    /* 공유 스위치가 꺼진 것은 서버가 키를 아예 안 보냅니다. 그 줄은 없어야
       합니다 — "안 했다" 가 아니라 "안 보여 준다" 니까요. */
    test('일정 공유 안 함(week 없음) → 운동 줄이 없다, 나머지는 그대로', () {
      final items = friendTodayItems({
        'today': {'date': _today, 'logged': true, 'kcal': 1200},
        'checkedIn': true,
      }, _today);
      expect(_ids(items), ['diet', 'checkin']);
    });

    test('아무것도 공유 안 함 → 줄이 하나도 없다', () {
      expect(friendTodayItems({}, _today), isEmpty);
      expect(friendTodayItems({'weekStart': '2026-09-21', 'weightKg': 80.0}, _today), isEmpty);
    });

    test('일정은 공유하는데 오늘 계획이 비었다 → 운동 줄 없음 (쉬는 날)', () {
      final items = friendTodayItems({'week': _week([], []), 'checkedIn': false}, _today);
      expect(_ids(items), ['checkin']);
      expect(friendTodayDay({'week': _week([], [])}, _today), isNotNull,
          reason: '오늘 칸은 있습니다 — 계획이 빈 것뿐');
    });

    test('지난주에 올린 스냅샷이면 오늘 칸이 없다 → 모른다(null)', () {
      final stale = {'week': _week(['gym'], ['gym'])};
      expect(friendTodayDay(stale, '2026-10-01'), isNull);
      expect(friendTodayItems(stale, '2026-10-01'), isEmpty);
      expect(friendTodayDay({}, _today), isNull, reason: 'week 없음');
    });

    test('전부 — 순서는 운동(헬스·유산소) → 식단 → 체크인', () {
      final items = friendTodayItems({
        'week': _week(['gym', 'cardio'], ['gym']),
        'today': {'date': _today, 'logged': true, 'kcal': 1800},
        'checkedIn': true,
      }, _today);
      expect(_ids(items), ['gym', 'cardio', 'diet', 'checkin']);
      expect([for (final i in items) i.done], [true, false, true, true]);
    });
  });

  /* 상세 화면 — 오늘 카드가 헤더 바로 아래 서고, 한 것은 체크, 아직은 빈
     동그라미로 그려지는가. 시계를 스냅샷의 날짜에 맞춥니다 — 기기 날짜로
     돌리면 스냅샷의 "오늘" 이 다른 날이 됩니다. */
  testWidgets('친구 상세 — 오늘 카드: 한 것은 체크, 아직은 빈 동그라미, n/m 완료', (t) async {
    t.view.physicalSize = const Size(1000, 4000);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    SharedPreferences.setMockInitialValues({});
    final app = await AppState.boot();
    app.store.now = () => DateTime(2026, 9, 24, 10);
    final api = Api(baseUrl: 'https://x.test',
        client: MockClient((_) async => http.Response('{"ok":false}', 404)));
    await api.setToken('tok');

    final snap = <String, Object?>{
      'weekStart': '2026-09-21', 'checkedIn': true,
      'plannedDays': 4, 'keptDays': 2, 'missedDays': 0, 'openDays': 2,
      'streaks': {'workoutDays': 3, 'foodDays': 5},
      'week': _week(['gym', 'cardio'], ['gym']),
      'today': {'date': _today, 'logged': true, 'kcal': 1800, 'p': 140, 'c': 180, 'f': 50,
                'target': {'intakeKcal': 2445, 'proteinG': 147, 'carbG': 250, 'fatG': 70}},
    };
    await t.pumpWidget(Scope(
      state: app, api: api, onServerChange: (_) async {},
      child: MaterialApp(theme: mbLight(), home: FriendDetailScreen(
          person: {'id': 'u1', 'displayName': '건강지킴', 'snapshot': snap})),
    ));
    await t.pumpAndSettle();
    expect(find.byType(ErrorWidget), findsNothing);
    expect(t.takeException(), isNull);

    expect(find.text('오늘'), findsOneWidget);
    expect(find.text('3/4 완료'), findsOneWidget, reason: '헬스·식단·체크인 했고 유산소는 아직');
    expect(find.text('헬스'), findsOneWidget);
    expect(find.text('유산소'), findsOneWidget);
    expect(find.text('식단 기록'), findsOneWidget);
    expect(find.text('1800 kcal'), findsOneWidget, reason: '적은 식단은 kcal 덧말');
    expect(find.text('이번 주 체크인'), findsOneWidget);
    expect(find.byIcon(LucideIcons.checkCircle2), findsNWidgets(3), reason: '한 것 셋');
    expect(find.byIcon(LucideIcons.circle), findsOneWidget, reason: '아직인 것 하나(유산소)');

    /* 오늘 카드가 헤더(스트릭 타일) 다음, 오늘 식단보다 위에. 이름은 앱바에도
       있어서 앵커로 못 씁니다 — 헤더에만 있는 '운동 스트릭' 으로 잡습니다. */
    final todayY = t.getTopLeft(find.text('오늘')).dy;
    expect(todayY, lessThan(t.getTopLeft(find.text('오늘 식단')).dy));
    expect(todayY, greaterThan(t.getTopLeft(find.text('운동 스트릭')).dy));

    /* 이번 주 카드는 그대로. */
    expect(find.text('이번 주 운동'), findsOneWidget);
    expect(find.text('2/4일 완료'), findsOneWidget);
  });

  testWidgets('친구 상세 — 일정은 공유하는데 오늘 계획이 없으면 조용한 한 줄, "정한 날 없음" 은 없다',
      (t) async {
    SharedPreferences.setMockInitialValues({});
    final app = await AppState.boot();
    app.store.now = () => DateTime(2026, 9, 24, 10);
    final api = Api(baseUrl: 'https://x.test',
        client: MockClient((_) async => http.Response('{"ok":false}', 404)));
    await api.setToken('tok');
    /* plannedDays 없음 = 이번 주에 하기로 한 날이 0 — 코어는 그때 키를 안 넣습니다. */
    final snap = <String, Object?>{'weekStart': '2026-09-21', 'week': _week([], [])};
    await t.pumpWidget(Scope(
      state: app, api: api, onServerChange: (_) async {},
      child: MaterialApp(theme: mbLight(), home: FriendDetailScreen(
          person: {'id': 'u2', 'displayName': '쉬는날', 'snapshot': snap})),
    ));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(find.text('오늘은 운동 계획이 없어요'), findsOneWidget);
    expect(find.textContaining('완료'), findsNothing, reason: '줄이 없으면 n/m 도 없습니다');
    expect(find.text('정한 날 없음'), findsNothing, reason: '오늘 카드가 이미 말했습니다');
    expect(find.byIcon(LucideIcons.circle), findsNothing, reason: '안 보낸 것에 빈 동그라미를 달지 않습니다');
  });

  testWidgets('친구 상세 — 아무것도 공유 안 하면 "공유하지 않습니다" 한 줄', (t) async {
    SharedPreferences.setMockInitialValues({});
    final app = await AppState.boot();
    final api = Api(baseUrl: 'https://x.test',
        client: MockClient((_) async => http.Response('{"ok":false}', 404)));
    await api.setToken('tok');
    await t.pumpWidget(Scope(
      state: app, api: api, onServerChange: (_) async {},
      child: MaterialApp(theme: mbLight(), home: const FriendDetailScreen(
          person: {'id': 'u3', 'displayName': '비공개'})),
    ));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(find.text('이 친구가 오늘 할 일을 공유하지 않습니다.'), findsOneWidget);
    expect(find.byIcon(LucideIcons.checkCircle2), findsNothing);
    expect(find.byIcon(LucideIcons.circle), findsNothing);
  });

  /* 친구 목록 — 이름 밑에 오늘 한 줄. 공유한 것이 있는 친구에게만. */
  testWidgets('친구 목록 — 이름 밑에 오늘 한 줄(종목 아이콘 · 체크 · 이름), 공유 없는 친구는 그대로',
      (t) async {
    t.view.physicalSize = const Size(1000, 2000);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    SharedPreferences.setMockInitialValues({});
    final app = await AppState.boot();
    app.store.now = () => DateTime(2026, 9, 24, 10);
    http.Response json(Object body) => http.Response.bytes(
        utf8.encode(jsonEncode(body)), 200,
        headers: {'content-type': 'application/json; charset=utf-8'});
    final api = Api(baseUrl: 'https://x.test', client: MockClient((req) async {
      final p = req.url.path;
      if (p.endsWith('/friends')) {
        return json({'ok': true, 'friends': {
          'accepted': [{'id': 'f1', 'displayName': '나린'}, {'id': 'f2', 'displayName': '다솜'}],
          'incoming': [], 'outgoing': [],
        }});
      }
      if (p.endsWith('/me')) {
        return json({'ok': true, 'user': {'id': 'me', 'handle': 'me', 'inviteCode': 'ABCD'}});
      }
      if (p.contains('/snapshots/f1')) {
        return json({'ok': true, 'rows': [{
          'weekStart': '2026-09-21', 'checkedIn': true, 'plannedDays': 3, 'keptDays': 1,
          'week': _week(['gym', 'cardio'], ['gym']),
          'today': {'date': _today, 'logged': true, 'kcal': 1500},
        }]});
      }
      if (p.contains('/snapshots/f2')) {
        return json({'ok': true, 'rows': [{'weekStart': '2026-09-21'}]});
      }
      if (p.endsWith('/pokes')) return http.Response('{"ok":true,"pokes":[]}', 200);
      return http.Response('{"ok":false}', 404);
    }));
    await api.setToken('tok');
    await t.pumpWidget(Scope(state: app, api: api, onServerChange: (_) async {},
        child: MaterialApp(theme: mbLight(), home: Scaffold(body: SocialScreen(go: (_, [__]) {})))));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(find.text('나린'), findsOneWidget);
    expect(find.text('다솜'), findsOneWidget);

    /* 나린: 헬스(했음) · 유산소(아직) · 식단(했음) · 체크인(했음). */
    expect(find.text('헬스'), findsOneWidget);
    expect(find.text('유산소'), findsOneWidget);
    expect(find.text('식단'), findsOneWidget);
    expect(find.text('체크인'), findsOneWidget);
    expect(find.byIcon(LucideIcons.dumbbell), findsOneWidget);
    expect(find.byIcon(LucideIcons.footprints), findsOneWidget);
    expect(find.byIcon(LucideIcons.utensils), findsOneWidget);
    expect(find.byIcon(LucideIcons.clipboardCheck), findsOneWidget);
    expect(find.byIcon(LucideIcons.checkCircle2), findsNWidgets(3));
    expect(find.byIcon(LucideIcons.circle), findsOneWidget, reason: '유산소만 아직');

    /* 다솜은 아무것도 공유 안 함 — 위의 아이콘 수가 나린 것뿐이라는 게 그 증거.
       줄 자체가 없고, 있던 글은 그대로입니다. */
    expect(find.text('이번 주 공유한 것이 없습니다'), findsOneWidget);
  });

  /* 360px 폰 — 「이번 주 기록」 알약과 독촉 단추(하기로 한 날을 다 못 지킨 친구)가
     이름 칸을 70px 남짓까지 밀어냅니다. 그래도 오늘 줄이 넘치면 안 됩니다. */
  testWidgets('친구 목록 — 좁은 폰에서 알약과 독촉 단추가 같이 있어도 오늘 줄이 넘치지 않는다',
      (t) async {
    t.view.physicalSize = const Size(360, 740);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    SharedPreferences.setMockInitialValues({});
    final app = await AppState.boot();
    app.store.now = () => DateTime(2026, 9, 24, 10);
    http.Response json(Object body) => http.Response.bytes(
        utf8.encode(jsonEncode(body)), 200,
        headers: {'content-type': 'application/json; charset=utf-8'});
    final api = Api(baseUrl: 'https://x.test', client: MockClient((req) async {
      final p = req.url.path;
      if (p.endsWith('/friends')) {
        return json({'ok': true, 'friends': {
          'accepted': [{'id': 'f1', 'displayName': '나린'}], 'incoming': [], 'outgoing': [],
        }});
      }
      if (p.endsWith('/me')) {
        return json({'ok': true, 'user': {'id': 'me', 'handle': 'me', 'inviteCode': 'ABCD'}});
      }
      if (p.contains('/snapshots/f1')) {
        /* 체크인 했고(알약) 7일 중 3일만 지킴(독촉 단추). */
        return json({'ok': true, 'rows': [{
          'weekStart': '2026-09-21', 'checkedIn': true, 'plannedDays': 7, 'keptDays': 3,
          'week': _week(['gym', 'cardio'], ['gym']),
          'today': {'date': _today, 'logged': true, 'kcal': 1500},
        }]});
      }
      if (p.endsWith('/pokes')) return http.Response('{"ok":true,"pokes":[]}', 200);
      return http.Response('{"ok":false}', 404);
    }));
    await api.setToken('tok');
    await t.pumpWidget(Scope(state: app, api: api, onServerChange: (_) async {},
        child: MaterialApp(theme: mbLight(), home: Scaffold(body: SocialScreen(go: (_, [__]) {})))));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull, reason: '오늘 줄이 이름 칸을 넘쳤습니다');
    expect(find.text('이번 주 기록'), findsOneWidget);
    expect(find.byIcon(LucideIcons.checkCircle2), findsNWidgets(3));
  });
}
