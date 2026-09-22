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

import 'package:flutter/foundation.dart';
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

/// 로그인 상태가 바뀌면(토큰이 생기거나 지워지면) 듣는 쪽에 알립니다 —
/// 셸이 그걸 듣고 로그인 화면과 앱 사이를 오갑니다.
class Api extends ChangeNotifier {
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
    notifyListeners();
  }

  /// 시험에서 로그인된 상태를 만들 때 씁니다. 앱 코드는 부르지 않습니다.
  @visibleForTesting
  Future<void> setToken(String? t) => _saveToken(t);

  Future<void> _saveToken(String? t) async {
    _token = t;
    notifyListeners();   // 저장보다 먼저 — 화면은 지금 바뀌어야 합니다
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

  /// 친구 한 명의 주간 요약들. `{ok, rows:[{weekStart, keptDays, …}]}`.
  ///
  /// **서버가 공유 설정으로 미리 걸러서** 줍니다 — 친구가 안 켠 항목은
  /// 아예 안 실려 옵니다. 그래서 이 값을 그대로 화면에 써도 됩니다.
  Future<ApiResult> friendSnapshots(String friendId, {int limit = 4}) =>
      _send('GET', '/snapshots/$friendId?limit=$limit');

  /// 결과지 사진을 서버에 보내 숫자를 읽어 옵니다.
  ///
  /// **직접 켰을 때만 부릅니다.** 이게 몸 사진이 기기 밖으로 나가는 단 하나의
  /// 길이고, 서버는 읽고 나서 사진을 보관하지 않습니다.
  ///
  /// 돌아오는 것: `{ok, fields:{weightKg, smmKg, bfmKg, …}, read, notInBody}`.
  /// `notInBody` 는 "인바디 결과지로 안 보입니다" 입니다 — 영수증을 찍은
  /// 사람에게 "핵심 세 칸을 못 읽었습니다" 라고 하면 같은 사진을 다시 찍습니다.
  Future<ApiResult> ocr({required String mediaType, required String data}) =>
      _send('POST', '/ocr', {'mediaType': mediaType, 'data': data});

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

  /// 비밀번호를 잊었을 때. 가입할 때 받은 복구 코드로 새 비밀번호를 겁니다.
  ///
  /// 로그인 화면이 "복구 코드가 필요합니다" 라고 말하면서 정작 이 길이
  /// 없었습니다 — 그 말을 믿고 코드를 찾아온 사람이 넣을 데가 없었습니다.
  Future<ApiResult> recover({
    required String handle,
    required String code,
    required String password,
  }) async {
    final r = await _send('POST', '/auth/recover',
        {'handle': handle, 'code': code, 'password': password});
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

  /// 기록 전체를 내 계정에 — 기기를 바꿔도 따라오게. 서버는 종류·id 별
  /// 레코드를 그대로 보관합니다(/sync). 사진은 안 갑니다.
  Future<ApiResult> pushRecords(List<Map<String, Object?>> records) =>
      _send('POST', '/sync/push', {'records': records});
  Future<ApiResult> pullRecords({String since = '', int limit = 500}) =>
      _send('GET', '/sync/pull?since=${Uri.encodeQueryComponent(since)}&limit=$limit');

  Future<ApiResult> publishSnapshot(String weekStart, Map<String, dynamic> snap) =>
      send('POST', '/snapshots', {'weekStart': weekStart, 'payload': snap});

  Future<ApiResult> pull() => send('GET', '/sync/pull');

  Future<ApiResult> changePassword(String current, String next) =>
      send('POST', '/auth/password', {'current': current, 'next': next});
  Future<ApiResult> newRecoveryCode(String password) =>
      send('POST', '/auth/recovery-code', {'password': password});
  Future<ApiResult> signOutEverywhere() => send('POST', '/auth/signout-all');
}
