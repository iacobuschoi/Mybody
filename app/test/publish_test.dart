/* =============================================================================
 * publish_test.dart — 저장하면 이번 주 요약이 서버로 가는가
 *
 * 이 고리가 안 꽂혀 있어서 앱은 주간 요약을 한 번도 안 올렸습니다 —
 * 에뮬레이터에서 친구 화면이 늘 비어 있던 이유의 절반.
 * ========================================================================== */
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mybody/src/api.dart';
import 'package:mybody/src/app_state.dart';
import 'package:mybody/src/news_store.dart';
import 'package:mybody/src/publish.dart';
import 'package:mybody/src/sync_queue.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _profile = {
  'sex': 'male', 'age': 22, 'heightCm': 187, 'activityLevel': 'moderate',
  'trainingAge': 'novice', 'daysPerWeek': 4, 'mealsPerDay': 3,
};

void main() {
  late List<Map<String, dynamic>> posts;
  MockClient client() => MockClient((req) async {
        if (req.url.path.endsWith('/snapshots') && req.method == 'POST') {
          posts.add(jsonDecode(req.body) as Map<String, dynamic>);
          return http.Response('{"ok":true}', 200);
        }
        return http.Response('{"ok":false}', 404);
      });

  setUp(() {
    posts = [];
    SharedPreferences.setMockInitialValues({});
  });

  test('저장하면 이번 주 요약이 큐를 거쳐 서버로 간다 — 오늘 식단·요일별 일정·스트릭까지', () async {
    final api = Api(baseUrl: 'https://x.test', client: client());
    await api.setToken('tok');
    final sp = await SharedPreferences.getInstance();
    final q = SyncQueue(api: api, storage: PrefsQueue(sp));
    final app = await AppState.boot();
    wirePublishing(app, api, q);

    app.store.set({'profile': _profile, 'onboarded': true});
    app.store.addScan({
      'id': 's1', 'weightKg': 86.7, 'smmKg': 38.0, 'bfmKg': 20.0,
      'measuredAt': '2026-03-01T00:00:00.000Z',
    });
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(posts, isNotEmpty, reason: '저장했는데 아무것도 안 올라갔습니다');
    final last = posts.last;
    expect('${last['weekStart']}', matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
    final payload = last['payload'] as Map<String, dynamic>;
    expect(payload['weightKg'], 86.7);
    expect(payload['today'], isA<Map>(), reason: '오늘 식단');
    expect(payload['week'], isA<Map>(), reason: '요일별 일정');
    expect((payload['week'] as Map)['days'], hasLength(7));
    expect(payload['streaks'], isA<Map>(), reason: '스트릭');
  });

  test('로그인하는 순간에도 한 번 올라간다', () async {
    final api = Api(baseUrl: 'https://x.test', client: client());
    final sp = await SharedPreferences.getInstance();
    final q = SyncQueue(api: api, storage: PrefsQueue(sp));
    final app = await AppState.boot();
    app.store.set({'profile': _profile, 'onboarded': true});
    app.store.addScan({'id': 's1', 'weightKg': 86.7, 'smmKg': 38.0, 'bfmKg': 20.0,
        'measuredAt': '2026-03-01T00:00:00.000Z'});
    wirePublishing(app, api, q);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(posts, isEmpty, reason: '로그인 전엔 보낼 곳이 없습니다');

    await api.setToken('tok');   // 로그인 성공이 하는 일
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(posts, hasLength(1));
  });
}
