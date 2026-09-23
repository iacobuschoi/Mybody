/* 친구 추가 요청이 서버가 읽는 필드 이름(inviteCode)으로 나가는가.
 * 'code' 로 나가서 앱에서는 친구 추가가 한 번도 안 된 적이 있습니다. */
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mybody/src/api.dart';

void main() {
  test('requestFriend 는 inviteCode 로 보낸다', () async {
    Map<String, dynamic>? body;
    String? path;
    final api = Api(
      baseUrl: 'https://example.test',
      client: MockClient((req) async {
        path = req.url.path;
        body = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response('{"ok":true}', 200);
      }),
    );
    api.setToken('tok');
    await api.requestFriend('ABC123');
    expect(path, '/api/friends/request');
    expect(body, {'inviteCode': 'ABC123'});
  });
}
