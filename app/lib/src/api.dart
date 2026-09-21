/* =============================================================================
 * api.dart — 서버와 이야기하는 곳
 *
 * 서버는 **그대로 씁니다.** 엔드포인트 18개가 이미 돌고 있고, 지금 쓰는
 * 앱과 같은 서버를 봅니다. 그래서 옮기는 동안 두 앱이 같이 살아 있을 수
 * 있습니다 — 친구들은 준비될 때까지 지금 것을 계속 씁니다.
 *
 * 여기서 조심하는 것 두 가지:
 *
 *   1. **토큰이 죽었을 때 조용히 로그아웃하지 않습니다.**
 *      지금 앱에서 그것 때문에 한 번 데였습니다 — 판독 키가 거부됐을 뿐인데
 *      사용자를 로그아웃시켜서, 쓰던 화면이 통째로 날아갔습니다.
 *      401 은 "이 요청이 거부됐다" 이지 "너는 이제 남이다" 가 아닙니다.
 *      진짜 세션 만료(/me 가 401)일 때만 로그아웃합니다.
 *
 *   2. **시간 제한을 겁니다.** 서버가 주인 노트북이라 꺼져 있을 수 있습니다.
 *      제한이 없으면 화면이 영원히 도는 원으로 남고, 사용자는 앱이 고장 난
 *      줄 압니다. "컴퓨터가 꺼져 있는 것 같습니다" 라고 말할 수 있어야 합니다.
 * ========================================================================== */
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiResult {
  final int status;
  final Map<String, dynamic> body;
  const ApiResult(this.status, this.body);

  bool get ok => status >= 200 && status < 300 && body['ok'] != false;
  String get reason => (body['reason'] as String?) ?? _byStatus();

  String _byStatus() {
    if (status == 0) return '서버에 닿지 못했습니다 — 컴퓨터가 꺼져 있을 수 있습니다';
    if (status == 401) return '다시 로그인해야 합니다';
    if (status == 429) return '잠시 뒤에 다시 해 주세요';
    return '요청이 실패했습니다 ($status)';
  }
}

class Api {
  Api({required this.baseUrl, http.Client? client})
      : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;
  String? _token;

  static const _tokenKey = 'mybody.token.v1';

  String? get token => _token;
  bool get signedIn => _token != null && _token!.isNotEmpty;

  Future<void> loadToken() async {
    try {
      final sp = await SharedPreferences.getInstance();
      _token = sp.getString(_tokenKey);
    } catch (_) {
      /* 저장소를 못 읽어도 앱은 떠야 합니다 — 로그인만 다시 하면 됩니다. */
      _token = null;
    }
  }

  Future<void> _saveToken(String? t) async {
    _token = t;
    try {
      final sp = await SharedPreferences.getInstance();
      if (t == null) {
        await sp.remove(_tokenKey);
      } else {
        await sp.setString(_tokenKey, t);
      }
    } catch (_) {/* 못 적어도 이번 실행 동안은 씁니다 */}
  }

  /// 확장(extension)에서도 부릅니다 — 친구·공유 호출이 여기 묶여 있습니다.
  Future<ApiResult> send(String method, String path, [Map<String, dynamic>? body]) =>
      _send(method, path, body);

  Future<ApiResult> _send(String method, String path, [Map<String, dynamic>? body]) async {
    final uri = Uri.parse('$baseUrl/api$path');
    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (signedIn) 'Authorization': 'Bearer $_token',
    };
    try {
      final req = http.Request(method, uri)
        ..headers.addAll(headers)
        ..body = body == null ? '' : jsonEncode(body);
      /* 20초. 지금 앱과 같은 값입니다. 판독(/ocr)만 따로 길게 줍니다 —
         사진 한 장 읽는 데 7초쯤 걸리고, 느릴 때는 15초까지 갑니다. */
      final timeout = path == '/ocr' ? const Duration(seconds: 90) : const Duration(seconds: 20);
      final streamed = await _client.send(req).timeout(timeout);
      final res = await http.Response.fromStream(streamed);
      Map<String, dynamic> j;
      try {
        /* **res.body 를 쓰지 않습니다.**
         *
         * http 꾸러미는 Content-Type 에 charset 이 없으면 latin1 로 읽습니다.
         * 그러면 서버가 보낸 한글이 통째로 깨져서 "ì•„ì´ë””..." 같은
         * 글자가 화면에 나갑니다 — 오류 문구가 다 한글이라 하필 제일
         * 중요한 순간에 읽을 수 없게 됩니다.
         *
         * 지금 서버는 charset=utf-8 을 붙이고 있어서 안 깨집니다. 그래도
         * 거기 기대지 않습니다: 엔드포인트 하나만 빠뜨려도 그 길만 깨지고,
         * 그건 아무도 안 보는 곳에서 조용히 일어납니다.
         * (이 줄은 시험이 먼저 잡았습니다.) */
        j = (jsonDecode(utf8.decode(res.bodyBytes)) as Map).cast<String, dynamic>();
      } catch (_) {
        j = {};
      }
      return ApiResult(res.statusCode, j);
    } on TimeoutException {
      return const ApiResult(0, {'reason': '서버가 응답하지 않습니다 — 컴퓨터가 꺼져 있거나 느립니다'});
    } catch (_) {
      return const ApiResult(0, {});
    }
  }

  Future<ApiResult> health() => _send('GET', '/health');

  Future<ApiResult> signUp({
    required String handle,
    required String password,
    required String displayName,
    String? pairSecret,
    required String healthConsent,
  }) async {
    final r = await _send('POST', '/auth/signup', {
      'handle': handle,
      'password': password,
      'displayName': displayName,
      if (pairSecret != null && pairSecret.isNotEmpty) 'pairSecret': pairSecret,
      'healthConsent': healthConsent,
    });
    if (r.ok && r.body['token'] is String) await _saveToken(r.body['token'] as String);
    return r;
  }

  Future<ApiResult> signIn({required String handle, required String password}) async {
    final r = await _send('POST', '/auth/signin', {'handle': handle, 'password': password});
    if (r.ok && r.body['token'] is String) await _saveToken(r.body['token'] as String);
    return r;
  }

  Future<void> signOut() async {
    /* 서버에 먼저 말하고 지웁니다. 순서가 반대면 토큰이 없어서 말을 못 합니다. */
    if (signedIn) await _send('POST', '/auth/signout');
    await _saveToken(null);
  }

  Future<ApiResult> me() => _send('GET', '/me');
  Future<ApiResult> friends() => _send('GET', '/friends');

  /* 세션이 진짜로 끝났는가.
     /me 가 401 이면 그때만 로그아웃합니다. 다른 요청의 401 은 그 요청이
     거부된 것이지 세션이 끝난 것이 아닙니다 — 그걸 구분 안 해서 사용자가
     쓰던 화면을 잃은 적이 있습니다. */
  Future<bool> sessionAlive() async {
    final r = await me();
    if (r.status == 401) {
      await _saveToken(null);
      return false;
    }
    return r.ok;
  }
}

/* --- 친구 · 공유 · 스냅샷 ---------------------------------------------------
 *
 * 서버 엔드포인트를 그대로 씁니다. 지금 쓰는 웹 앱과 **같은 서버**를 보므로,
 * 옮기는 동안 두 앱이 같이 살아 있을 수 있습니다 — 친구들은 준비될 때까지
 * 지금 것을 계속 씁니다.
 * -------------------------------------------------------------------------- */
extension ApiSocial on Api {
  Future<ApiResult> updateMe(Map<String, dynamic> patch) => send('PATCH', '/me', patch);
  Future<ApiResult> deleteMe() => send('DELETE', '/me');

  Future<ApiResult> requestFriend(String inviteCode) =>
      send('POST', '/friends/request', {'code': inviteCode});
  Future<ApiResult> acceptFriend(String userId) =>
      send('POST', '/friends/accept', {'userId': userId});
  Future<ApiResult> declineFriend(String userId) =>
      send('POST', '/friends/decline', {'userId': userId});
  Future<ApiResult> blockFriend(String userId) =>
      send('POST', '/friends/block', {'userId': userId});
  Future<ApiResult> unblockFriend(String userId) =>
      send('POST', '/friends/unblock', {'userId': userId});

  Future<ApiResult> removeFriend(String userId) => send('DELETE', '/friends/$userId');

  /// 친구별 공유 항목. **여기서 끄면 서버가 그 값을 안 보냅니다** —
  /// 화면에서 가리는 것이 아니라 아예 나가지 않습니다. 권한 판정은 언제나
  /// 서버가 하고, 앱은 이미 걸러진 값만 받습니다.
  Future<ApiResult> getShare(String userId) => send('GET', '/share/$userId');
  Future<ApiResult> setShare(String userId, Map<String, dynamic> flags) =>
      send('PUT', '/share/$userId', flags);

  Future<ApiResult> publishSnapshot(String weekStart, Map<String, dynamic> snap) =>
      send('POST', '/snapshots', {'weekStart': weekStart, 'payload': snap});

  Future<ApiResult> pull() => send('GET', '/sync/pull');

  Future<ApiResult> changePassword(String current, String next) =>
      send('POST', '/auth/password', {'current': current, 'next': next});
  Future<ApiResult> newRecoveryCode(String password) =>
      send('POST', '/auth/recovery-code', {'password': password});
  Future<ApiResult> signOutEverywhere() => send('POST', '/auth/signout-all');
}
