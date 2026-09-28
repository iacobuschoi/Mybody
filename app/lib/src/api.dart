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
 *      사진을 싣고 가는 두 길(판독 /ocr · 의견 /feedback)만 길게 줍니다.
 *
 * 로그인 없이 가는 길도 같은 [Api.send] 로 갑니다 — 토큰이 있을 때만 머리에
 * 붙이므로, 로그인 안 한 사람의 「의견 보내기」 는 그냥 토큰 없이 나갑니다
 * (서버가 그때는 익명으로 받습니다).
 *
 * 그렇게 모인 의견을 운영자가 앱 안에서 읽는 길(「의견함」)은 아래
 * [ApiFeedbackInbox] 입니다. 캡처 사진만은 JSON 이 아니라 바이트로 받아서
 * [Api.send] 를 못 타고 따로 갑니다 — 토큰은 똑같이 머리에 붙입니다.
 * 같은 운영자의 「가입자 목록」 은 맨 아래 [ApiOperatorUsers] 입니다.
 * ========================================================================== */
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// 계정에 딸린 화면 캐시의 열쇠 앞머리 — 친구 목록 · 친구별 공유 · 기본 공유
/// (social.dart · share_defaults.dart). 로그인이 끝나면(로그아웃 · 세션 만료 ·
/// 「이 기기에서 전부 지우기」) 지웁니다. 열쇠에 계정이 없어서, 남겨 두면 같은
/// 기기에서 다른 계정으로 로그인한 뒤 서버에 못 닿을 때 앞 사람의 설정이
/// 「마지막으로 본 설정」 으로 보이고 스위치가 그 값을 기준으로 움직입니다.
const kAccountCachePrefixes = ['mybody.share.', 'mybody.friends.cache.'];

/// 의견에 붙이는 사진 한 장 — [type] 은 'image/png' 또는 'image/jpeg' 만(서버가
/// 앞머리 바이트로 한 번 더 봅니다). 바이트는 풀린 그대로, base64 는 [Api.sendFeedback] 가.
typedef FeedbackImage = ({String type, Uint8List bytes});

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

  /// 이 로그인이 운영자인가(/me 의 user.isOperator). null 이면 아직 모름 — [me] 가 채웁니다.
  bool? _operator;

  /// 이 로그인의 계정 id(/me 의 user.id). null 이면 아직 모름 — [me] 가 채웁니다.
  String? _userId;

  /// 운영자인지 묻는 중인 /me([askOperator]) — 설정의 운영자 줄 둘이 같이 물어도 한 번만 갑니다.
  Future<bool?>? _operatorAsk;

  /// 이 로그인으로 받은 「가입자 목록」 길의 마지막 답([ApiOperatorUsers.operatorUsersSeen]).
  /// null 이면 아직 모름.
  ({bool open, int total})? _operatorUsersSeen;

  /* 의견함 캡처의 메모리 캐시([ApiFeedbackInbox.inboxImage]). 넣은 차례가 곧 오래된 차례라
     (LinkedHashMap) 꺼낼 때 뒤로 다시 넣으면 LRU 입니다. 받는 중인 것은 [_inboxImageLoads] 에
     — 목록의 작은 그림과 상세가 같은 장을 동시에 청해도 한 번만 받게. */
  final _inboxImages = <String, Uint8List>{};
  final _inboxImageLoads = <String, Future<Uint8List?>>{};
  int _inboxImageBytes = 0;

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
    /* 로그인이 바뀌면 운영자인지도, 운영자로 받아 둔 캡처도 앞 사람 것입니다 — 같은 기기에서
       다른 계정으로 들어온 사람에게 앞 운영자의 의견 사진이 캐시에서 나오면 안 됩니다. */
    if (t != _token) _forgetAccountMemory();
    _token = t;
    notifyListeners();   // 저장보다 먼저 — 화면은 지금 바뀌어야 합니다
    try {
      final sp = await SharedPreferences.getInstance();
      if (t == null) {
        await sp.remove(_tokenKey);
        await clearAccountCaches();
      } else {
        await sp.setString(_tokenKey, t);
      }
    } catch (_) {/* 못 적어도 이번 실행 동안은 씁니다 */}
  }

  void _forgetAccountMemory() {
    _operator = null;
    _userId = null;
    _operatorAsk = null;
    _operatorUsersSeen = null;
    _inboxImages.clear();
    _inboxImageLoads.clear();
    _inboxImageBytes = 0;
  }

  /// [kAccountCachePrefixes] 의 캐시를 전부 지웁니다. 로그인이 끝날 때와
  /// 「이 기기에서 전부 지우기」(로그인 안 한 채로 눌러도)가 부릅니다.
  static Future<void> clearAccountCaches() async {
    try {
      final sp = await SharedPreferences.getInstance();
      for (final k in sp.getKeys().toList()) {
        if (kAccountCachePrefixes.any(k.startsWith)) await sp.remove(k);
      }
    } catch (_) {/* 못 지워도 로그아웃은 됩니다 */}
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
         사진 한 장 읽는 데 7초쯤 걸리고, 느릴 때는 15초까지 갑니다.
         의견(/feedback)도 — 화면 캡처 3장이면 6MB 가까이 올라갑니다. 느린 데이터
         (올리기 1Mbps)에서 50초쯤이라, 20초에 끊으면 다 간 의견을 「못 보냈어요」
         라고 말하고 사람은 같은 것을 또 보냅니다. */
      final timeout = path == '/ocr' || path == '/feedback'
          ? const Duration(seconds: 90)
          : const Duration(seconds: 20);
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

  /// 채널별 최신 판과 서버가 받아 주는 최소 판 (update.dart).
  /// 로그인이 필요 없고, 이 앱의 판은 보내지 않습니다 — 비교는 앱이 합니다.
  /// 이 길이 없는 옛 서버는 404 를 줍니다. 그때는 안내가 없을 뿐입니다.
  Future<ApiResult> appVersion() => _send('GET', '/version');

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

  /// 앱 안 「의견 보내기」(screens/feedback.dart). `{ok, id}`, 틀리면 `{ok:false, error}`.
  ///
  /// **로그인 없이도 갑니다.** 토큰이 있으면 [_send] 가 머리에 붙여 그 계정에 묶이고,
  /// 없으면 안 붙어서 서버가 익명으로 받습니다 — 서버는 이 길에서 401 을 주지
  /// 않습니다. 로그인 안 하고 쓰는 사람이 제일 먼저 막히는 사람일 수 있습니다.
  ///
  /// 글과 사진은 **둘 중 하나만 있어도** 됩니다. 비어 있는 칸은 아예 안 싣습니다 —
  /// 서버가 "글이 비었다" 와 "글을 안 보냈다" 를 가를 까닭이 없게.
  /// 사진은 여기서 base64 로 바꿉니다(부르는 쪽은 바이트만 들고 있게).
  Future<ApiResult> sendFeedback({
    String? text,
    List<FeedbackImage> images = const [],
    String? appVersion,
    String? platform,
    String? screen,
  }) {
    final t = text?.trim() ?? '';
    return _send('POST', '/feedback', {
      if (t.isNotEmpty) 'text': t,
      if (images.isNotEmpty)
        'images': [
          for (final i in images) {'type': i.type, 'data': base64Encode(i.bytes)},
        ],
      if (appVersion != null && appVersion.isNotEmpty) 'appVersion': appVersion,
      if (platform != null && platform.isNotEmpty) 'platform': platform,
      if (screen != null && screen.isNotEmpty) 'screen': screen,
    });
  }

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

  /// 내 계정. 받을 때마다 운영자인지([isOperator])를 적어 둡니다 — 셸 · 친구 탭 · 계정 화면이
  /// 이미 /me 를 부르므로, 설정의 「의견함」 줄은 대개 따로 묻지 않고 그 값을 씁니다.
  Future<ApiResult> me() async {
    final asked = _token;
    final r = await _send('GET', '/me');
    /* 기다리는 사이 로그인이 바뀌었으면 앞 계정의 답입니다 — 적지 않습니다. */
    if (r.ok && asked == _token) {
      final u = r.body['user'];
      _operator = isOperatorUser(u);
      final id = u is Map ? u['id'] : null;
      _userId = id is String && id.isNotEmpty ? id : null;
    }
    return r;
  }

  /// 이 로그인의 계정 id — [me] 를 한 번 받은 뒤에 압니다(모르면 null). 계정마다 한 번만
  /// 하는 일(native_push.dart 의 크롬 알림 지우기)이 열쇠로 씁니다. 로그인이 바뀌면 비웁니다.
  String? get userId => signedIn ? _userId : null;

  /// 이 로그인이 운영자인가 — 서버 설정(feedbackNotify)에 적힌 아이디의 계정만 참.
  /// null 이면 이 로그인으로 아직 /me 를 못 받았습니다. 화면을 가르는 데만 씁니다 —
  /// 의견함의 권한 판정은 언제나 서버가 합니다(아니면 403).
  bool? get isOperator => signedIn ? _operator : false;

  /// /me 의 user 가 운영자인가. 옛 서버는 칸이 없어서 거짓입니다.
  static bool isOperatorUser(Object? user) => user is Map && user['isOperator'] == true;

  /// [isOperator] 를 아직 모르면 /me 를 한 번 물어 채우고 그 값을 돌려줍니다(알면 묻지 않음).
  /// 설정의 「의견함」 · 「가입자 목록」 줄이 같이 불러도 /me 는 한 번만 갑니다. 못 닿으면 null.
  Future<bool?> askOperator() {
    if (!signedIn) return Future.value(false);
    if (_operator != null) return Future.value(_operator);
    final going = _operatorAsk;
    if (going != null) return going;
    /* 끝나면 비웁니다 — 단 자기 것일 때만(그사이 로그인이 바뀌어 새 물음이 섰으면 그쪽 것). */
    late final Future<bool?> ask;
    ask = me().then((_) => isOperator).whenComplete(() {
      if (identical(_operatorAsk, ask)) _operatorAsk = null;
    });
    return _operatorAsk = ask;
  }

  /// 옛 판으로 동의한 계정이 새 판에 다시 동의합니다 (account.dart ConsentGate).
  Future<ApiResult> consent(String version) =>
      _send('POST', '/me/consent', {'healthConsent': version});
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

  /* 서버는 inviteCode 를 읽습니다. 예전에 'code' 로 보내서 앱에서는 친구
     추가가 한 번도 안 됐습니다(웹은 맞게 보냈음). */
  /*
     [viaLink] — 초대 링크(· 설치 추천인)로 받은 코드. 서버가 요청이 아니라 그 자리에서 친구로
     맺습니다(주인 의견 48 · server.js POST /friends/request 의 via:'link'). 손으로 친 코드 ·
     클립보드에서 고른 코드 · 다시 보내기 줄(sync_queue.dart)은 붙이지 않습니다 — 코드 주인의
     수락을 기다리는 예전 흐름 그대로. 이 칸을 모르는 옛 서버는 버리고 요청으로 받습니다. */
  Future<ApiResult> requestFriend(String inviteCode, {bool viaLink = false}) =>
      send('POST', '/friends/request', {'inviteCode': inviteCode, if (viaLink) 'via': 'link'});
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

  /// 새 친구에게 기본으로 보여 주는 것. `{ok, defaults:{streak, …}}`.
  /// 친구를 맺는 순간 서버가 이 값을 그 관계로 복사합니다 — 이미 맺은
  /// 친구는 [applyShareDefaults] 로만 바뀝니다. 이 길이 없는 옛 서버는 404.
  Future<ApiResult> getShareDefaults() => send('GET', '/share-defaults');

  /// 바꾼 스위치만 보냅니다 — 캐시에서 본 옛 값으로 나머지를 덮지 않게.
  /// 서버가 합친 결과를 `defaults` 로 돌려줍니다.
  Future<ApiResult> setShareDefaults(Map<String, bool> patch) =>
      send('PUT', '/share-defaults', patch);

  /// 지금 친구 모두의 "내가 보여 주는 것" 을 기본값으로 덮습니다. `{ok, applied}`.
  /// [expect] 는 사람이 확인 창에서 본 값 — 서버에 저장된 기본값과 다르면
  /// 서버가 아무것도 안 바꾸고 409 `{conflict, defaults}` 를 줍니다.
  Future<ApiResult> applyShareDefaults({Map<String, bool>? expect}) =>
      send('POST', '/share-defaults/apply', expect == null ? null : {'expect': expect});

  /// 운동 독촉 — 친구에게 "오늘 운동 어때요" 한 번(하루 한 번).
  Future<ApiResult> poke(String userId) => _send('POST', '/pokes', {'userId': userId, 'kind': 'workout'});
  /// 나에게 온 독촉. 가져가면 서버는 전달됐다고 표시합니다.
  Future<ApiResult> pullPokes() => _send('GET', '/pokes');

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

/* --- 앱 알림(FCM) ------------------------------------------------------------
 *
 * 이 기기의 알림 주소(FCM 토큰)를 내 로그인에 묶어 둡니다(native_push.dart).
 * 서버는 그 로그인이 끝나면(로그아웃 · 비밀번호 변경 · 탈퇴) 행을 같이 지웁니다.
 * 이 길이 없는 옛 서버는 404 를 줍니다 — 그때 앱은 켤 때 · 돌아올 때 가져오기로 삽니다.
 * -------------------------------------------------------------------------- */
extension ApiPush on Api {
  /// `{ok, fcm}` — fcm 은 서버가 실제로 보낼 수 있는가(설정 파일이 있는가).
  /// 서버가 FCM 을 아직 안 켰어도 저장은 합니다 — 켜는 날 바로 씁니다.
  /// [permission] 은 'granted' · 'denied' — 거절된 기기는 서버가 앱이 있는 것으로 치지 않습니다
  /// (크롬(웹) 구독이 남아 있으면 그리로 보냄).
  /// [secret] 은 이 설치가 이 서버에 쓰는 난수 비밀 — 다른 계정이 토큰만으로 이 기기를
  /// 옮겨 가지 못하게 서버가 봅니다(맞지 않으면 409).
  Future<ApiResult> registerPushDevice({
    required String token,
    required String platform,
    String? appVersion,
    String? permission,
    String? secret,
  }) =>
      send('POST', '/push/device', {
        'token': token,
        'platform': platform,
        if (appVersion != null && appVersion.isNotEmpty) 'appVersion': appVersion,
        if (permission != null) 'permission': permission,
        if (secret != null && secret.isNotEmpty) 'secret': secret,
      });

  /// 이 기기를 알림 받는 곳에서 뺍니다. 로그아웃 직전에 부릅니다 — 토큰이 없으면 말을 못 합니다.
  Future<ApiResult> removePushDevice(String token) =>
      send('DELETE', '/push/device', {'token': token});

  /// 설정 화면의 「푸시 알림」 줄. `{ok, fcm, web, devices, webSubs, webMuted}` — 화면은 fcm 만
  /// 봅니다(크롬 칸은 설정에서 뺐습니다 · 주인 의견 47).
  Future<ApiResult> pushStatus() => send('GET', '/push/status');

  /// 이 계정의 크롬(웹) 알림 구독을 전부 지웁니다. `{ok, removed}`.
  /// 사람이 누르는 단추는 없습니다 — 이 기기의 앱 알림을 서버에 등록한 뒤 NativePush 가
  /// 계정마다 한 번 저절로 부릅니다(native_push.dart).
  /// 서버 판에 따라 이름이 둘이라(설계는 /push/web, 먼저 알린 이름은 /push/web-subscriptions)
  /// 앞의 것이 404 면 뒤의 것을 부릅니다. 둘 다 404 면 이 서버에는 없는 기능입니다.
  Future<ApiResult> dropWebPush() async {
    final r = await send('DELETE', '/push/web');
    if (r.status != 404) return r;
    return send('DELETE', '/push/web-subscriptions');
  }
}

/* --- 의견함(운영자) ----------------------------------------------------------
 *
 * 앱 안 「의견 보내기」 로 모인 의견을 운영자가 폰에서 읽는 길(screens/feedback_inbox.dart).
 * 서버 설정(feedbackNotify)에 적힌 아이디로 로그인한 계정만 됩니다 — 다른 계정은 403
 * `{ok:false, error:'운영자만 볼 수 있어요'}`, 로그인 안 했으면 다른 길처럼 401.
 *
 * 보낸 사람은 표시 이름만 옵니다(`from: {name}`, 로그인 없이 보냈으면 null). 아이디 ·
 * 이메일은 서버가 싣지 않습니다.
 * -------------------------------------------------------------------------- */

/// 의견에 붙은 캡처 한 장 — [n] 은 1부터(서버의 feedback_images.idx).
typedef InboxImage = ({int n, String type});

/// 의견함의 한 건.
class InboxItem {
  const InboxItem({
    required this.id,
    this.createdAt,
    this.appVersion,
    this.platform,
    this.screen,
    this.text = '',
    this.read = false,
    this.images = const [],
    this.anonymous = true,
    this.fromName,
  });

  final int id;

  /// 보낸 때(이 폰의 시각대로 바꿔 둠). 서버가 이상한 값을 주면 null.
  final DateTime? createdAt;
  final String? appVersion;

  /// 'android' · 'ios' — 모르는 값이면 그대로.
  final String? platform;

  /// 보낼 때 보던 화면의 앱바 제목(홈 · 식단 · 설정 …).
  final String? screen;

  /// 글. 캡처만 보냈으면 빈 글자.
  final String text;
  final bool read;
  final List<InboxImage> images;

  /// 로그인 없이 보냈는가(`from: null`).
  final bool anonymous;

  /// 보낸 계정의 표시 이름. 익명이거나 계정의 이름이 비었으면 null — 둘은 [anonymous] 로 가릅니다.
  final String? fromName;

  InboxItem copyWith({bool? read}) => InboxItem(
        id: id,
        createdAt: createdAt,
        appVersion: appVersion,
        platform: platform,
        screen: screen,
        text: text,
        read: read ?? this.read,
        images: images,
        anonymous: anonymous,
        fromName: fromName,
      );

  /// 서버의 한 칸을 읽습니다. id 가 없으면 null — 그 칸은 버립니다(누를 수도 지울 수도 없음).
  static InboxItem? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = _int(j['id']);
    if (id == null) return null;
    String? s(Object? v) => v is String && v.trim().isNotEmpty ? v.trim() : null;
    final at = j['createdAt'];
    final from = j['from'];
    return InboxItem(
      id: id,
      createdAt: at is String ? DateTime.tryParse(at)?.toLocal() : null,
      appVersion: s(j['appVersion']),
      platform: s(j['platform']),
      screen: s(j['screen']),
      text: j['text'] is String ? j['text'] as String : '',
      read: j['read'] == true,
      images: [
        if (j['images'] is List)
          for (final i in j['images'] as List)
            if (i is Map && _int(i['n']) != null)
              (n: _int(i['n'])!, type: i['type'] is String ? i['type'] as String : 'image/png'),
      ],
      anonymous: from is! Map,
      fromName: from is Map ? s(from['name']) : null,
    );
  }

  static int? _int(Object? v) =>
      v is int ? v : v is num ? v.toInt() : v is String ? int.tryParse(v) : null;
}

/// GET /feedback/inbox 한 쪽.
class InboxPage {
  const InboxPage(this.result, {this.items = const [], this.unread = 0, this.nextBefore});
  final ApiResult result;

  /// 새것부터.
  final List<InboxItem> items;

  /// 서버 전체의 안 읽은 개수(이 쪽만이 아니라).
  final int unread;

  /// 다음 쪽을 부를 때의 before. null 이면 이게 마지막 쪽.
  final int? nextBefore;

  bool get ok => result.ok;

  /// 운영자가 아니다(403) · 로그인이 없다(401) — 다시 해 봐도 같은 답입니다.
  bool get denied => result.status == 403 || result.status == 401;

  /// 화면에 쓸 까닭. 서버는 이 길에서 까닭을 `error` 로 줍니다.
  String get reason => inboxReason(result);

  factory InboxPage.from(ApiResult r) {
    if (!r.ok) return InboxPage(r);
    final b = r.body;
    return InboxPage(
      r,
      items: [
        if (b['items'] is List)
          for (final j in b['items'] as List)
            if (InboxItem.fromJson(j) case final it?) it,
      ],
      unread: InboxItem._int(b['unread']) ?? 0,
      nextBefore: InboxItem._int(b['nextBefore']),
    );
  }
}

/// 의견함 길의 실패를 한 줄로. 운영자 판정(401 · 403)은 무엇을 하면 되는지로 말합니다.
String inboxReason(ApiResult r) {
  if (r.status == 403 || r.status == 401) return '운영자 계정으로 로그인하면 볼 수 있어요';
  final e = r.body['error'];
  if (e is String && e.isNotEmpty) return e;
  return r.reason;
}

/// 캡처 캐시에 두는 장수 · 바이트 — 한 장이 1.5MB 까지라 장수만 세면 45MB 가 될 수 있어 둘 다 봅니다.
const kInboxImageCacheCount = 30;
const kInboxImageCacheBytes = 32 * 1024 * 1024;

extension ApiFeedbackInbox on Api {
  /// 의견함 한 쪽 — 새것부터 [limit](1~50)건. 다음 쪽은 앞 쪽의 [InboxPage.nextBefore] 를 [before] 로.
  Future<InboxPage> fetchInbox({int? before, int limit = 30}) async {
    final n = limit.clamp(1, 50);
    final r = await _send('GET', '/feedback/inbox?limit=$n${before == null ? '' : '&before=$before'}');
    return InboxPage.from(r);
  }

  /// 캡처 한 장의 바이트. 못 받으면 null(권한 · 없음 · 못 닿음 — 부르는 쪽은 깨진 그림 표시만).
  ///
  /// 받은 것은 메모리에만 [kInboxImageCacheCount] 장까지 둡니다(오래 안 본 것부터 뺌).
  /// 디스크에는 안 남깁니다 — 캡처에 몸 숫자가 찍혀 있을 수 있고, 서버에서 지워지면
  /// (1년 · 탈퇴 · 의견함에서 지우기) 폰에도 없어야 합니다. 로그인이 바뀌면 비웁니다.
  Future<Uint8List?> inboxImage(int id, int n) {
    final key = '$id/$n';
    final hit = cachedInboxImage(id, n);
    if (hit != null) return Future.value(hit);
    final going = _inboxImageLoads[key];
    if (going != null) return going;
    /* 끝나면 받는 중 표에서 뺍니다 — 단 **자기 것일 때만**. 그사이 로그인이 바뀌어 표가 비고
       새 계정이 같은 장을 청했으면 그 자리는 새 받기의 것입니다. */
    late final Future<Uint8List?> load;
    load = _loadInboxImage(key, id, n).whenComplete(() {
      if (identical(_inboxImageLoads[key], load)) _inboxImageLoads.remove(key);
    });
    return _inboxImageLoads[key] = load;
  }

  /// 이미 받아 둔 캡처(없으면 null) — 화면이 첫 그림부터 자리표시 없이 그리게. 꺼내면 최근 것이 됩니다.
  Uint8List? cachedInboxImage(int id, int n) {
    final key = '$id/$n';
    final hit = _inboxImages.remove(key);
    if (hit != null) _inboxImages[key] = hit;
    return hit;
  }

  Future<Uint8List?> _loadInboxImage(String key, int id, int n) async {
    final asked = _token;
    if (!signedIn) return null;
    try {
      final req = http.Request('GET', Uri.parse('$baseUrl/api/feedback/inbox/$id/image/$n'))
        ..headers['Authorization'] = 'Bearer $asked';
      /* 몸통까지 다 받는 데 30초 — 캡처 한 장이 1.5MB 까지라 [_send] 의 20초(머리만)보다 넉넉히.
         머리만 제한하면 느린 데이터에서 몸통을 받다가 영영 멈춘 채 자리표시로 남습니다. */
      final res = await () async {
        final streamed = await _client.send(req);
        return http.Response.fromStream(streamed);
      }()
          .timeout(const Duration(seconds: 30));
      final type = res.headers['content-type'] ?? '';
      if (res.statusCode != 200 || !type.startsWith('image/') || res.bodyBytes.isEmpty) return null;
      /* 받는 사이 로그인이 바뀌었으면 앞 계정의 것 — 캐시에도 안 넣고 화면에도 안 줍니다
         (다른 계정으로 들어온 사람 앞에 앞 운영자의 캡처가 뜨지 않게). */
      if (asked != _token) return null;
      final bytes = res.bodyBytes;
      _rememberInboxImage(key, bytes);
      return bytes;
    } catch (_) {
      return null;
    }
  }

  void _rememberInboxImage(String key, Uint8List bytes) {
    final old = _inboxImages.remove(key);
    if (old != null) _inboxImageBytes -= old.length;
    _inboxImages[key] = bytes;
    _inboxImageBytes += bytes.length;
    while (_inboxImages.length > 1 &&
        (_inboxImages.length > kInboxImageCacheCount || _inboxImageBytes > kInboxImageCacheBytes)) {
      final first = _inboxImages.keys.first;
      _inboxImageBytes -= _inboxImages.remove(first)!.length;
    }
  }

  /// 캐시에 몇 장 있나 — 시험이 LRU 를 확인합니다.
  @visibleForTesting
  int get inboxImageCacheSize => _inboxImages.length;

  /// 한 건을 읽은 것으로. `{ok}`.
  Future<ApiResult> markRead(int id) => _send('POST', '/feedback/inbox/$id/read');

  /// 전부 읽은 것으로(이 쪽만이 아니라 서버 전체). `{ok}`.
  ///
  /// [upTo] 는 화면에 받아 둔 것 중 가장 새 번호 — 주면 서버가 그 번호까지만 읽음으로 합니다.
  /// 목록을 받은 뒤에 온 의견(아직 본 적 없는 것)이 「모두 읽음」 에 같이 쓸려 가지 않게.
  Future<ApiResult> markAllRead({int? upTo}) =>
      _send('POST', '/feedback/inbox/read-all', upTo == null ? null : {'upTo': upTo});

  /// 한 건과 그 캡처를 지웁니다 — 되돌릴 수 없습니다. 받아 둔 캡처도 캐시에서 뺍니다.
  Future<ApiResult> deleteFeedback(int id) async {
    final r = await _send('DELETE', '/feedback/inbox/$id');
    if (r.ok || r.status == 404) {
      for (final k in _inboxImages.keys.where((k) => k.startsWith('$id/')).toList()) {
        _inboxImageBytes -= _inboxImages.remove(k)!.length;
      }
    }
    return r;
  }
}

/* --- 가입자 목록(운영자) ------------------------------------------------------
 *
 * 노트북의 tools/reset-password.js(인자 없이)가 보여 주던 것 — 아이디 · 표시 이름 · 가입일 — 을
 * 운영자 폰에서 봅니다(screens/user_list.dart). 규칙은 의견함과 같습니다: 운영자가 아니면 403,
 * 로그인 안 했으면 401, 까닭은 [inboxReason] 으로. 새 가입부터 1000명까지 오고, 그보다 많으면
 * [OperatorUsersPage.total] 이 전체 수를 말합니다. 비밀(비밀번호 · 토큰 · 초대 코드 · 내부 id)은
 * 서버가 싣지 않습니다.
 * -------------------------------------------------------------------------- */

/// 서버가 한 번에 싣는 최대 사람 수(server/db.js USERS_LIST_MAX).
const kOperatorUsersMax = 1000;

/// 가입자 한 명.
class OperatorUser {
  const OperatorUser({required this.handle, this.displayName = '', this.createdAt, this.me = false});

  /// 로그인 아이디 — 줄을 누르면 복사되는 값(reset-password.js <아이디>).
  final String handle;

  /// 표시 이름. 비었으면 ''.
  final String displayName;

  /// 가입한 때(이 폰의 시각대로). 서버가 이상한 값을 주면 null.
  final DateTime? createdAt;

  /// 운영자 본인의 줄인가.
  final bool me;

  /// 서버의 한 칸을 읽습니다. 아이디가 없으면 null — 그 칸은 버립니다(복사할 것이 없음).
  static OperatorUser? fromJson(Object? j) {
    if (j is! Map) return null;
    final h = j['handle'];
    if (h is! String || h.trim().isEmpty) return null;
    final name = j['displayName'];
    final at = j['createdAt'];
    return OperatorUser(
      handle: h.trim(),
      displayName: name is String ? name.trim() : '',
      createdAt: at is String ? DateTime.tryParse(at)?.toLocal() : null,
      me: j['me'] == true,
    );
  }
}

/// GET /operator/users 한 번.
class OperatorUsersPage {
  const OperatorUsersPage(this.result, {this.users = const [], this.total = 0});
  final ApiResult result;

  /// 새 가입부터.
  final List<OperatorUser> users;

  /// 서버 전체의 가입자 수 — [users] 가 1000명에서 잘렸어도 전부.
  final int total;

  bool get ok => result.ok;

  /// 운영자가 아니다(403) · 로그인이 없다(401) — 다시 해 봐도 같은 답입니다.
  bool get denied => result.status == 403 || result.status == 401;

  /// 이 길이 없는 옛 서버(404) — 설정의 줄을 거둡니다.
  bool get missing => result.status == 404;

  /// 화면에 쓸 까닭 — 의견함과 같은 말.
  String get reason => inboxReason(result);

  factory OperatorUsersPage.from(ApiResult r) {
    if (!r.ok) return OperatorUsersPage(r);
    final b = r.body;
    final users = [
      if (b['users'] is List)
        for (final j in b['users'] as List)
          if (OperatorUser.fromJson(j) case final u?) u,
    ];
    final total = InboxItem._int(b['total']) ?? users.length;
    return OperatorUsersPage(r, users: users, total: total < users.length ? users.length : total);
  }
}

extension ApiOperatorUsers on Api {
  /// 가입자 목록 — 새 가입부터 [limit](1~1000, 없으면 서버 기본 1000)명. 설정의 줄은 수만 알면 돼서 1.
  /// 받은 답(열림 + 전체 수 · 403/401/404 면 닫힘)은 [operatorUsersSeen] 에 적어 둡니다.
  Future<OperatorUsersPage> fetchOperatorUsers({int? limit}) async {
    final asked = _token;
    final q = limit == null ? '' : '?limit=${limit.clamp(1, kOperatorUsersMax)}';
    final p = OperatorUsersPage.from(await _send('GET', '/operator/users$q'));
    /* 기다리는 사이 로그인이 바뀌었으면 앞 계정의 답 — 적지 않습니다. 못 닿음 · 5xx 는 길이 있는지
       말해 주지 않으므로 앞 답을 그대로 둡니다. */
    if (asked == _token) {
      if (p.ok) {
        _operatorUsersSeen = (open: true, total: p.total);
      } else if (p.denied || p.missing) {
        _operatorUsersSeen = (open: false, total: 0);
      }
    }
    return p;
  }

  /// 이 로그인으로 받은 이 길의 마지막 답 — 열려 있었나(403 · 401 · 404 면 거짓)와 그때의 전체 수.
  /// null 이면 아직 모름. 설정의 「가입자 목록」 줄이 처음 그릴 때 씁니다: 한 번 열렸던 서버면 답을
  /// 기다리지 않고 바로 서고, 이 길이 없는 옛 서버면 다음에 열 때도 섰다 사라지지 않게.
  ({bool open, int total})? get operatorUsersSeen => signedIn ? _operatorUsersSeen : null;
}
