/* =============================================================================
 * friend_detail_test.dart — 친구 상세: 친구에 대한 것이 먼저, 공유 설정은 접힘
 *
 * 그리고 공유 스위치가 **서버가 아는 이름**으로 나가는가. 예전엔 weight·smm
 * 같은 이름으로 보내서 켜도 서버가 버렸습니다 — 스위치는 켜졌는데 나가는
 * 건 없었습니다.
 * ========================================================================== */
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mybody/src/api.dart';
import 'package:mybody/src/app_state.dart';
import 'package:mybody/src/scope.dart';
import 'package:mybody/src/screens/social.dart';
import 'package:mybody/src/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// server/db.js 의 SHARE_FIELDS 그대로.
const _serverShareKeys = [
  'weightTrend', 'smmTrend', 'bfmTrend', 'planProgress', 'streak', 'schedule', 'absolute', 'diet',
];

Map<String, Object?> _day(String key, String dow, int n, List<String> plan, List<String> done) =>
    {'key': key, 'dow': dow, 'dayNum': n, 'plan': plan, 'done': done,
     'kept': plan.isNotEmpty && plan.every(done.contains), 'missed': false};

final _rich = <String, Object?>{
  'weekStart': '2026-09-21', 'checkedIn': true,
  'plannedDays': 4, 'keptDays': 2, 'missedDays': 1, 'openDays': 1,
  'streaks': {'workoutDays': 3, 'foodDays': 5},
  'week': {'start': '2026-09-21', 'days': [
    _day('2026-09-21', '월', 21, ['gym'], ['gym']),
    _day('2026-09-22', '화', 22, [], []),
    _day('2026-09-23', '수', 23, ['gym'], ['gym']),
    _day('2026-09-24', '목', 24, [], []),
    _day('2026-09-25', '금', 25, ['gym'], []),
    _day('2026-09-26', '토', 26, ['cardio'], []),
    _day('2026-09-27', '일', 27, [], []),
  ]},
  'today': {'date': '2026-09-22', 'logged': true, 'kcal': 1800, 'p': 140, 'c': 180, 'f': 50,
            'target': {'intakeKcal': 2445, 'proteinG': 147, 'carbG': 250, 'fatG': 70}},
  'weightKg': 86.3, 'dWeightKg': -0.8,
};

void main() {
  testWidgets('친구 상세 — 스트릭·오늘 식단·이번 주 운동이 먼저, 공유 설정은 접혀 있다', (t) async {
    t.view.physicalSize = const Size(1000, 4000);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    SharedPreferences.setMockInitialValues({});
    final app = await AppState.boot();

    final puts = <Map<String, dynamic>>[];
    final client = MockClient((req) async {
      final p = req.url.path;
      if (p.endsWith('/share/f1') && req.method == 'GET') {
        return http.Response(jsonEncode({'ok': true, 'share': {
          for (final k in _serverShareKeys) k: k == 'streak' || k == 'schedule' || k == 'diet',
        }}), 200);
      }
      if (p.endsWith('/share/f1') && req.method == 'PUT') {
        puts.add(jsonDecode(req.body) as Map<String, dynamic>);
        return http.Response('{"ok":true}', 200);
      }
      if (p.contains('/snapshots/f1')) {
        /* 한글이 들어 있으면 Response(String) 은 latin1 로 못 담아 던집니다 —
           바이트로 줍니다(진짜 서버가 utf-8 로 주는 것과 같게). */
        return http.Response.bytes(utf8.encode(jsonEncode({'ok': true, 'rows': [_rich]})), 200,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }
      return http.Response('{"ok":false}', 404);
    });
    final api = Api(baseUrl: 'https://x.test', client: client);
    await api.setToken('tok');

    await t.pumpWidget(Scope(
      state: app, api: api, onServerChange: (_) async {},
      child: MaterialApp(theme: mbLight(), home: const FriendDetailScreen(
          person: {'id': 'f1', 'displayName': '나린', 'handle': 'narin'})),
    ));
    await t.pumpAndSettle();

    expect(find.byType(ErrorWidget), findsNothing);
    expect(find.text('3일째'), findsOneWidget, reason: '운동 스트릭');
    expect(find.text('5일째'), findsOneWidget, reason: '식단 스트릭');
    expect(find.text('오늘 식단'), findsOneWidget);
    expect(find.text('140 / 147 g'), findsOneWidget, reason: '단백질 달성/목표');
    expect(find.text('1800 / 2445 kcal'), findsOneWidget);
    expect(find.text('이번 주 운동'), findsOneWidget);
    expect(find.text('2/4일 완료'), findsOneWidget);
    expect(find.text('몸'), findsOneWidget, reason: '켠 몸 수치만 따로');
    expect(find.byType(SwitchListTile), findsNothing, reason: '공유 설정은 접혀 있어야 합니다');

    await t.tap(find.text('내가 이 친구에게 보여 주는 것'));
    await t.pumpAndSettle();
    expect(find.byType(SwitchListTile), findsNWidgets(_serverShareKeys.length));

    await t.tap(find.widgetWithText(SwitchListTile, '체중 변화'));
    await t.pumpAndSettle();
    expect(puts, hasLength(1));
    expect(puts.first.keys.every(_serverShareKeys.contains), isTrue,
        reason: '서버가 모르는 이름으로 보내면 켜도 안 켜집니다: ${puts.first.keys}');
    expect(puts.first['weightTrend'], isTrue);
    expect(puts.first['diet'], isTrue, reason: '이미 켜진 것은 그대로 같이 갑니다');
  });

  testWidgets('친구 상세 — 아무것도 공유 안 한 친구도 선다', (t) async {
    SharedPreferences.setMockInitialValues({});
    final app = await AppState.boot();
    final api = Api(baseUrl: 'https://x.test',
        client: MockClient((_) async => http.Response('{"ok":false}', 404)));
    await api.setToken('tok');
    await t.pumpWidget(Scope(
      state: app, api: api, onServerChange: (_) async {},
      child: MaterialApp(theme: mbLight(), home: const FriendDetailScreen(
          person: {'id': 'f2', 'displayName': '다솜'})),
    ));
    await t.pumpAndSettle();
    expect(find.byType(ErrorWidget), findsNothing);
    expect(t.takeException(), isNull);
    expect(find.text('공유 안 함'), findsNWidgets(2));
    expect(find.text('이 친구가 식단을 공유하지 않습니다.'), findsOneWidget);
  });

  /* 서버에 못 닿았다고 친구 목록을 비우면, 비행기 모드에서 친구 상세에
     못 들어가고 "나중에 보냅니다" 도 못 씁니다 — 에뮬레이터에서 잡힌 것. */
  testWidgets('친구 목록 — 서버에 못 닿으면 마지막으로 본 목록을 보여 준다', (t) async {
    SharedPreferences.setMockInitialValues({});
    final app = await AppState.boot();
    http.Response friendsOk(http.Request req) {
      final p = req.url.path;
      if (p.endsWith('/friends')) {
        return http.Response.bytes(utf8.encode(jsonEncode({'ok': true, 'friends': {
          'accepted': [{'id': 'f1', 'displayName': '나린'}], 'incoming': [], 'outgoing': [],
        }})), 200, headers: {'content-type': 'application/json; charset=utf-8'});
      }
      if (p.endsWith('/me')) {
        return http.Response('{"ok":true,"user":{"id":"me","handle":"me","inviteCode":"ABCD"}}', 200);
      }
      return http.Response('{"ok":false}', 404);
    }
    final good = Api(baseUrl: 'https://x.test', client: MockClient((r) async => friendsOk(r)));
    await good.setToken('tok');
    await t.pumpWidget(Scope(state: app, api: good, onServerChange: (_) async {},
        child: MaterialApp(theme: mbLight(), home: Scaffold(body: SocialScreen(go: (_, [__]) {})))));
    await t.pumpAndSettle();
    expect(find.text('나린'), findsOneWidget);

    /* 이제 망이 끊깁니다. 같은 저장소, 새 화면. */
    final dead = Api(baseUrl: 'https://x.test',
        client: MockClient((_) async => throw Exception('no network')));
    await dead.setToken('tok');
    /* 다른 key — 같은 자리의 같은 위젯이면 State 가 재사용돼 옛 목록이 남는데,
       그건 캐시가 아니라 우연입니다. 새 화면이 캐시에서 읽어야 합니다. */
    await t.pumpWidget(Scope(state: app, api: dead, onServerChange: (_) async {},
        child: MaterialApp(theme: mbLight(),
            home: Scaffold(body: SocialScreen(key: const ValueKey('offline'), go: (_, [__]) {})))));
    await t.pumpAndSettle();
    expect(find.text('나린'), findsOneWidget, reason: '마지막으로 본 목록이 남아야 합니다');
    expect(find.textContaining('마지막으로 본 목록', findRichText: true), findsOneWidget);
  });

  /* 비행기 모드에서 상세를 열면 "0개 켜짐" 에 스위치가 전부 꺼진 채로 보였고,
     사람은 "다 꺼졌네" 하고 다시 켰습니다 — 서버엔 중복 PUT. */
  testWidgets('친구 상세 — 서버에 못 닿으면 마지막으로 본 공유 설정을 보여 준다', (t) async {
    SharedPreferences.setMockInitialValues({});
    final app = await AppState.boot();
    final good = Api(baseUrl: 'https://x.test', client: MockClient((req) async {
      if (req.url.path.endsWith('/share/f1')) {
        return http.Response(jsonEncode({'ok': true, 'share': {
          for (final k in _serverShareKeys) k: k == 'streak' || k == 'schedule' || k == 'diet',
        }}), 200);
      }
      return http.Response('{"ok":false}', 404);
    }));
    await good.setToken('tok');
    await t.pumpWidget(Scope(state: app, api: good, onServerChange: (_) async {},
        child: MaterialApp(theme: mbLight(), home: const FriendDetailScreen(
            key: ValueKey('online'), person: {'id': 'f1', 'displayName': '나린'}))));
    await t.pumpAndSettle();
    expect(find.text('3개 켜짐'), findsOneWidget);

    final dead = Api(baseUrl: 'https://x.test',
        client: MockClient((_) async => throw Exception('no network')));
    await dead.setToken('tok');
    await t.pumpWidget(Scope(state: app, api: dead, onServerChange: (_) async {},
        child: MaterialApp(theme: mbLight(), home: const FriendDetailScreen(
            key: ValueKey('offline'), person: {'id': 'f1', 'displayName': '나린'}))));
    await t.pumpAndSettle();
    expect(find.textContaining('3개 켜짐'), findsOneWidget, reason: '캐시된 설정');
    expect(find.textContaining('마지막으로 본 설정'), findsOneWidget);
  });
}
