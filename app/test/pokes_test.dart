/* =============================================================================
 * pokes_test.dart — 운동 독촉: 누구에게 보낼 수 있고, 받은 것은 어떻게 남는가
 * ========================================================================== */
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mybody/src/api.dart';
import 'package:mybody/src/app_state.dart';
import 'package:mybody/src/pokes.dart';
import 'package:mybody/src/scope.dart';
import 'package:mybody/src/screens/social.dart';
import 'package:mybody/src/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('needsNudge — 기록 없거나 하기로 한 날을 못 지킨 친구', () {
    expect(needsNudge(null), isTrue);
    expect(needsNudge({}), isTrue);
    expect(needsNudge({'checkedIn': false}), isTrue);
    expect(needsNudge({'checkedIn': true, 'plannedDays': 3, 'keptDays': 1}), isTrue);
    expect(needsNudge({'checkedIn': true, 'plannedDays': 3, 'keptDays': 3}), isFalse);
    expect(needsNudge({'checkedIn': true}), isFalse);
  });

  test('받은 독촉은 가져오면 남고, 치우면 사라진다', () async {
    SharedPreferences.setMockInitialValues({});
    final sp = await SharedPreferences.getInstance();
    var served = [
      {'id': 7, 'kind': 'workout', 'at': '2026-09-22T05:00:00.000Z', 'from': {'id': 'f1', 'displayName': '나린'}},
    ];
    final api = Api(baseUrl: 'https://x.test', client: MockClient((req) async {
      if (req.url.path.endsWith('/pokes')) {
        final body = jsonEncode({'ok': true, 'pokes': served});
        served = [];
        return http.Response.bytes(utf8.encode(body), 200, headers: {'content-type': 'application/json; charset=utf-8'});
      }
      return http.Response('{"ok":false}', 404);
    }));
    await api.setToken('tok');
    final box = PokeBox(sp);
    final fresh = await box.fetch(api);
    expect(fresh, hasLength(1));
    expect(box.items.first['name'], '나린');
    expect(PokeBox.title(box.items.first), '나린님이 운동하라고 콕 찔렀어요');
    expect(await box.fetch(api), isEmpty, reason: '서버는 한 번 준 것을 다시 안 줍니다');
    expect(PokeBox(sp).items, hasLength(1), reason: '기기에 남습니다');
    await box.dismiss(7);
    expect(box.items, isEmpty);
    expect(PokeBox(sp).items, isEmpty);
  });

  testWidgets('친구 목록: 운동 안 한 친구에게만 독촉 버튼, 누르면 서버로 간다', (t) async {
    SharedPreferences.setMockInitialValues({});
    final app = await AppState.boot();
    final posts = <Map<String, dynamic>>[];
    final api = Api(baseUrl: 'https://x.test', client: MockClient((req) async {
      final p = req.url.path;
      if (p.endsWith('/friends')) {
        return http.Response.bytes(utf8.encode(jsonEncode({'ok': true, 'friends': {
          'accepted': [{'id': 'lazy', 'displayName': '게으른'}, {'id': 'hero', 'displayName': '부지런'}],
          'incoming': [], 'outgoing': [],
        }})), 200, headers: {'content-type': 'application/json; charset=utf-8'});
      }
      if (p.endsWith('/me')) return http.Response('{"ok":true,"user":{"id":"me","handle":"me","inviteCode":"ABCD"}}', 200);
      if (p.contains('/snapshots/lazy')) {
        return http.Response(jsonEncode({'ok': true, 'rows': [{'weekStart': '2026-09-21', 'checkedIn': false, 'plannedDays': 3, 'keptDays': 0}]}), 200);
      }
      if (p.contains('/snapshots/hero')) {
        return http.Response(jsonEncode({'ok': true, 'rows': [{'weekStart': '2026-09-21', 'checkedIn': true, 'plannedDays': 3, 'keptDays': 3}]}), 200);
      }
      if (p.endsWith('/pokes') && req.method == 'POST') {
        posts.add(jsonDecode(req.body) as Map<String, dynamic>);
        return http.Response('{"ok":true,"id":1}', 200);
      }
      if (p.endsWith('/pokes')) return http.Response('{"ok":true,"pokes":[]}', 200);
      return http.Response('{"ok":false}', 404);
    }));
    await api.setToken('tok');
    await t.pumpWidget(Scope(state: app, api: api, onServerChange: (_) async {},
        child: MaterialApp(theme: mbLight(), home: Scaffold(body: SocialScreen(go: (_, [__]) {})))));
    await t.pumpAndSettle();
    expect(find.text('게으른'), findsOneWidget);
    expect(find.byTooltip('운동 독촉'), findsOneWidget, reason: '안 한 친구 하나에게만');
    await t.tap(find.byTooltip('운동 독촉'));
    await t.pumpAndSettle();
    expect(posts, hasLength(1));
    expect(posts.first['userId'], 'lazy');
    expect(find.byTooltip('오늘 보냄'), findsOneWidget);
    expect(find.textContaining('운동 독촉을 보냈습니다', findRichText: true), findsOneWidget);
  });
}
