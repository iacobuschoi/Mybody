/* =============================================================================
 * invite_link.dart — 초대 링크를 눌러 앱이 열렸을 때
 *
 * 친구를 부르는 쪽은 「보내기」 로 링크 하나를 보냅니다 — <서버 주소>/i/<코드>
 * (social.dart 의 inviteShareText). 받은 사람이 누르면(주인 의견 45: "링크만 누르면 바로
 * 친추되게해"):
 *
 *   https://<서버>/i/<코드>      앱이 있으면 **이 주소가 곧바로 앱을 엽니다** — 안드로이드
 *                                App Links(AndroidManifest 의 autoVerify · 서버의
 *                                /.well-known/assetlinks.json), 아이폰 Universal Links(연결된
 *                                도메인 · 서버의 apple-app-site-association). 확인이 안 된 폰
 *                                (첫 설치 직후 · 인증서가 아직 안 적힘)이면 서버의 초대 페이지가
 *                                뜨고, 그 페이지의 「앱에서 열기」 가 아래 주소로 엽니다.
 *   mybody://invite/<코드>       아이폰은 이 주소 그대로, 안드로이드는 intent:// 주소로 같은 곳을
 *                                엽니다(앱 패키지를 짚고, 앱이 없으면 페이지로 돌아옴).
 *
 * https 주소는 **이 앱의 서버 주소와 호스트가 같을 때만** 초대로 봅니다(main.dart 가 서버
 * 주소를 아는 길 그대로 — 직접 넣은 주소가 있으면 그것, 없으면 앱에 박힌 주소). 다른 서버의
 * /i/<코드> 는 다른 서버의 사람이라 여기서 보내면 「그런 코드를 가진 사람이 없습니다」 뿐입니다.
 *
 * 앱은 그 주소를 받아 **친구 요청을 대신 보냅니다** — 여덟 글자를 옮겨 칠 일이 없습니다.
 * 주소를 받는 것은 app_links 이고, 이 파일은 받은 주소를 코드로 바꿔 쥐고 있는
 * 곳([InviteInbox])입니다. 실제로 보내는 것은 셸(shell.dart)이 합니다 — 보낼 수 있는지
 * (로그인 · 첫 설정 · 탭 화면)는 셸만 압니다.
 *
 * 앱이 없던 사람 — 스토어를 거쳐도 코드가 따라오게
 *   · 안드로이드: 페이지가 플레이 주소에 referrer=invite%3D<코드> 를 실어 보내고, 깔린 앱이
 *     처음 켤 때 한 번 그것을 물어 링크와 똑같이 쥡니다(install_referrer.dart) — 묻지 않고.
 *   · 클립보드: 페이지의 설치 단추는 누르는 순간 「Mybody 초대 <코드> https://<서버>/i/<코드>」 를
 *     클립보드에 넣습니다. 안드로이드는 탭 화면이 **처음** 설 때 클립보드를 한 번 읽어
 *     ([InviteInbox.clipboardInviteOnce]) 초대가 있으면(이 기기에서 「보내기」 로 내보낸 **내**
 *     코드는 빼고 — 인사 3쪽에서 보내고 닫은 바로 그때가 그 차례입니다) 셸이 「초대 코드 … 로 친구 요청할까요?」
 *     를 묻습니다 — 남의 클립보드로 요청이 가면 안 되니 이것만은 한 번 누르게 합니다. 아이폰은
 *     앱이 클립보드를 읽으면 「붙여넣기 허용」 창이 뜨므로 **스스로 읽지 않습니다** — 인사
 *     3쪽과 「친구 추가」 칸 옆의 「초대 코드 붙여넣기」 를 눌렀을 때만 읽습니다(social.dart).
 *
 * 왜 바로 안 보내고 쥐고 있나
 *   링크로 앱이 열리는 순간은 대개 보낼 수 없는 때입니다 — 앱이 켜지는 중이고, 로그인
 *   전이거나 첫 설정 중일 수 있습니다. 그래서 코드를 이 기기에 적어 두고(SharedPreferences ·
 *   받은 시각과 함께) 보낼 수 있게 되면 한 번 보냅니다. 앱이 도중에 꺼져도 남습니다.
 *   **7일**이 지나면 버립니다 — 일주일 전에 눌러 둔 링크로 오늘 갑자기 요청이 가면
 *   누가 보냈는지도 모를 일입니다.
 *
 * 두 번 보내지 않게
 *   · app_links 는 앱을 연 링크를 **두 길로** 줍니다 — getInitialLink 와, 듣기 시작할 때
 *     uriLinkStream 이 한 번 더. 같은 코드가 [kInviteDupWindow] 안에 또 오면 버립니다(https ·
 *     mybody 어느 모양으로 와도 코드로 봅니다).
 *     그래서 앱을 연 링크를 **먼저** 묻고 그다음에 흐름을 듣습니다 — 흐름부터 들으면 흐름 쪽이
 *     먼저 와서 "앱을 연 링크" 인지 모르고 받습니다(아래 되살아난 링크를 못 거릅니다).
 *   · 보낼 때는 코드를 먼저 **꺼내서 비우고**([InviteInbox.take]) 보냅니다 — 다시 그려지거나
 *     앱으로 돌아올 때 또 불려도 꺼낼 것이 없습니다.
 *   · 안드로이드는 최근 앱 목록에서 다시 연 것(LAUNCHED_FROM_HISTORY)을 링크로 치지 않습니다
 *     (app_links 가 거릅니다).
 *   · **되살아난 링크.** 그런데 링크로 켜진 앱이 뒤에 있다가 폰이 메모리를 비우려고 앱을
 *     끄면(갤럭시는 자주 끕니다), 다음에 **아이콘**으로 열 때 안드로이드는 화면을 처음 연
 *     그 링크(인텐트)로 다시 만듭니다 — app_links 는 그것을 또 "앱을 연 링크" 로 줍니다.
 *     그대로 두면 켤 때마다 요청이 또 가고 「이미 요청을 보냈어요」 가 뜹니다. 그래서 꺼내 간
 *     코드를 이 기기에 적어 두고(최근 [_handledCap] 개), **앱을 연 링크**가 그 코드면 버립니다.
 *     쥐고 있는 코드와 같아도 버립니다(로그인 안내가 다시 뜨지 않게). 설치 referrer 도 같은
 *     규칙입니다 — 링크로도 받고 referrer 로도 받은 코드는 한 번입니다. 앱을 쓰는 중에 누른
 *     링크(흐름)는 그대로 받습니다 — 다시 누른 사람은 답을 봐야 합니다. 서버에 못 닿아
 *     못 보낸 것은 적은 것을 지웁니다([InviteInbox.unsent]) — 다시 누르면 다시 갑니다.
 *
 * 로그인 안 한 사람 · 로그인 없이 쓰는 사람
 *   코드는 그대로 쥐고, 「로그인하면 친구 요청이 가요」 를 **한 번만** 알립니다(prompted 를
 *   같이 적어 둡니다). 로그인하면 그때 보냅니다.
 *
 * 시험은 링크 · 서버 주소 · referrer · 클립보드 · 기종이 오는 길을 바꿔 끼웁니다(생성자) —
 * 진짜 것들은 플랫폼 채널이라 시험 안에서는 없습니다. 그래서 main.dart 만
 * [InviteInbox.platform] 을 만들고, 앱을 통째로 세우는 시험(const MyBodyApp())은 링크를
 * 듣지 않습니다. 넘기지 않은 길은 쓰지 않습니다(referrer · 클립보드를 안 넘기면 안 봅니다).
 * ========================================================================== */
import 'dart:async';
import 'dart:convert';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show Clipboard;
import 'package:shared_preferences/shared_preferences.dart';

import 'install_referrer.dart';
import 'screens/social.dart' show isInviteCode, kMyInviteCodeKey;

/// 앱 링크 스킴 · 호스트 — 서버의 초대 페이지(server.js APP_SCHEME)와 AndroidManifest ·
/// Info.plist 가 같은 값을 씁니다.
const String kInviteScheme = 'mybody';
const String kInviteHost = 'invite';

/// https 초대 링크의 경로 — <서버 주소>/i/<코드>. 서버의 초대 페이지 · AndroidManifest 의
/// pathPrefix("/i/") · apple-app-site-association 의 "/i/*" 와 같아야 합니다.
const String kInvitePath = 'i';

/// 받은 코드를 쥐고 있는 기간. 지나면 보내지 않고 버립니다.
const Duration kInvitePendingTtl = Duration(days: 7);

/// 같은 코드가 이 안에 또 오면 겹친 것으로 봅니다(getInitialLink + uriLinkStream).
const Duration kInviteDupWindow = Duration(seconds: 5);

const String _pendingKey = 'mybody.invite.pending.v1';

/// 꺼내 간(보낸) 코드들 — 되살아난 앱 여는 링크를 거릅니다(머리 주석).
const String _handledKey = 'mybody.invite.handled.v1';

/// 탭 화면이 처음 섰을 때 클립보드를 읽었나(안드로이드, 한 번).
const String kInviteClipboardKey = 'mybody.invite.clipboard.v1';

/// 꺼내 간 코드를 몇 개까지 적어 두나. 오래된 것부터 밀려납니다.
const int _handledCap = 20;

/* 주소의 경로 토막 — 빈 토막(끝의 / · 겹친 /)은 뺍니다. */
List<String> _segments(Uri u) => u.pathSegments.where((s) => s.isNotEmpty).toList();

/* 호스트 견주기용 — 소문자, 끝의 점(「mypc.tail1234.ts.net.」 — tailscale status 가 내주는 꼴을
   그대로 넣은 주소)은 뗍니다. 점 하나 때문에 내 서버의 초대를 남의 것으로 버리지 않게. */
String _hostKey(String h) => h.toLowerCase().replaceAll(RegExp(r'\.+$'), '');

/* 서버 주소(Api.baseUrl 꼴)를 주소로. http(s) 이고 호스트가 있어야 합니다. */
Uri? _serverUri(String? base) {
  final b = base?.trim() ?? '';
  if (b.isEmpty) return null;
  final u = Uri.tryParse(b);
  if (u == null || u.host.isEmpty) return null;
  final s = u.scheme.toLowerCase();
  return s == 'https' || s == 'http' ? u : null;
}

/// 초대 링크에서 코드를 꺼냅니다(대문자). 초대 링크가 아니거나 코드 모양이 틀리면 null —
/// 모르는 링크로 요청을 보내지 않습니다.
///
///   mybody://invite/<코드>     늘.
///   https://<서버>/i/<코드>    [serverBase](이 앱의 서버 주소)와 스킴 · 호스트 · 포트가 같을 때만.
///                             서버 주소에 경로가 붙어 있으면(https://x/mybody) 그 뒤의 /i/<코드>.
///                             끝의 / · ?noapp=1 같은 물음표 뒤는 봐주고, 더 긴 경로는 아닙니다.
String? inviteCodeFromUri(Uri? uri, {String? serverBase}) {
  if (uri == null) return null;
  final scheme = uri.scheme.toLowerCase();
  final String raw;
  if (scheme == kInviteScheme) {
    if (uri.host.toLowerCase() != kInviteHost) return null;
    final parts = _segments(uri);
    if (parts.length != 1) return null;
    raw = parts.single;
  } else if (scheme == 'https' || scheme == 'http') {
    final base = _serverUri(serverBase);
    if (base == null ||
        scheme != base.scheme.toLowerCase() ||
        _hostKey(uri.host) != _hostKey(base.host) ||
        uri.port != base.port) {
      return null;
    }
    final prefix = _segments(base);
    final parts = _segments(uri);
    if (parts.length != prefix.length + 2 || parts[prefix.length] != kInvitePath) return null;
    for (var i = 0; i < prefix.length; i++) {
      if (parts[i] != prefix[i]) return null;
    }
    raw = parts.last;
  } else {
    return null;
  }
  final code = raw.trim().toUpperCase();
  return isInviteCode(code) ? code : null;
}

/* 호스트를 보기 **전의** 코드 — 겹침 판정은 서버 주소를 기다리기 전에 해야 합니다(receive). */
String? _codeBeforeHost(Uri uri) {
  final s = uri.scheme.toLowerCase();
  if (s == kInviteScheme) return inviteCodeFromUri(uri);
  if (s != 'https' && s != 'http') return null;
  final parts = _segments(uri);
  if (parts.length < 2 || parts[parts.length - 2] != kInvitePath) return null;
  final code = parts.last.trim().toUpperCase();
  return isInviteCode(code) ? code : null;
}

/* 글 속의 주소 — 영문 주소 글자만(주소 바로 뒤에 붙은 「를」 같은 한글은 주소가 아닙니다).
   끝에 붙은 문장부호는 뗍니다. */
final RegExp _linkInText =
    RegExp(r"(?:https?|mybody)://[A-Za-z0-9\-._~:/?#@!$&*+,;=%]+", caseSensitive: false);
final RegExp _trailingPunct = RegExp(r'[.,!?;:]+$');

/* 「초대 <코드>」 · 「초대 코드 <코드>」 · 「초대 코드: <코드>」. */
final RegExp _inviteLabel = RegExp(r'초대\s*(?:코드)?\s*[:：]?\s*([A-Za-z0-9]{8})(?![A-Za-z0-9])');

/// 클립보드 글에서 **Mybody 초대**만 골라 코드를 꺼냅니다(대문자). 없으면 null.
///
/// 초대로 보는 것: 초대 페이지가 넣는 글(「Mybody 초대 <코드> https://<서버>/i/<코드>」),
/// 이 앱 서버의 초대 주소(친구가 카톡으로 보낸 글을 통째로 복사한 것 포함), mybody://invite 주소,
/// 「초대 <코드>」. 아무 여덟 글자는 초대로 보지 않습니다 — 묻지도 않은 것을 "친구 요청할까요?"
/// 로 물으면 이상합니다(친구 코드 칸에 붙여 넣을 때는 social.dart 의 cleanInviteCode 가 더
/// 너그럽게 봅니다 — 그때는 사람이 코드라고 골라 넣은 것입니다).
String? inviteCodeFromClipboard(String? text, {String? serverBase}) {
  if (text == null || text.trim().isEmpty) return null;
  for (final m in _linkInText.allMatches(text)) {
    final u = Uri.tryParse(m[0]!.replaceAll(_trailingPunct, ''));
    final code = inviteCodeFromUri(u, serverBase: serverBase);
    if (code != null) return code;
  }
  for (final m in _inviteLabel.allMatches(text)) {
    final code = m[1]!.toUpperCase();
    if (isInviteCode(code)) return code;
  }
  return null;
}

/// 진짜 클립보드의 글. 시험은 [InviteInbox] 의 clipboard 로 바꿔 끼웁니다.
Future<String?> readClipboardText() async => (await Clipboard.getData(Clipboard.kTextPlain))?.text;

/// 받아 두고 아직 못 보낸 초대 — 코드, 받은 시각, 로그인 안내를 이미 했는가.
@immutable
class PendingInvite {
  const PendingInvite(this.code, this.at, {this.prompted = false});
  final String code;
  final DateTime at;
  final bool prompted;

  PendingInvite prompt() => PendingInvite(code, at, prompted: true);

  Map<String, Object> toJson() =>
      {'code': code, 'at': at.millisecondsSinceEpoch, if (prompted) 'prompted': true};

  /// 저장된 값에서. 모양이 틀리면 null — 저장소가 깨져도 엉뚱한 요청을 보내지 않습니다.
  static PendingInvite? fromJson(Object? j) {
    if (j is! Map) return null;
    final code = j['code'];
    final at = j['at'];
    if (code is! String || !isInviteCode(code) || at is! int) return null;
    return PendingInvite(code, DateTime.fromMillisecondsSinceEpoch(at),
        prompted: j['prompted'] == true);
  }
}

/// 초대 링크 받는 곳. 링크가 오면 코드를 쥐고 알립니다(ChangeNotifier) — 셸이 듣고
/// 보낼 수 있으면 [take] 로 꺼내 보냅니다.
class InviteInbox extends ChangeNotifier {
  /// [serverBase] 는 이 앱의 서버 주소를 주는 길 — https 초대 링크의 호스트를 견줍니다. 없으면
  /// https 링크는 받지 않습니다. [installReferrer] 를 주면 처음 켤 때 한 번 설치 referrer 를
  /// 묻고(install_referrer.dart), [clipboard] 를 주면 [clipboardInviteOnce] 가 그것으로 읽습니다.
  /// [platform] 은 기종(없으면 이 기기) — 클립보드를 스스로 읽는 것은 안드로이드뿐입니다.
  InviteInbox({
    Stream<Uri> Function()? links,
    Future<Uri?> Function()? initialLink,
    DateTime Function()? now,
    FutureOr<String?> Function()? serverBase,
    InstallReferrerRead? installReferrer,
    Future<String?> Function()? clipboard,
    TargetPlatform Function()? platform,
  })  : _links = links,
        _initialLink = initialLink,
        _now = now ?? DateTime.now,
        _serverBase = serverBase,
        _installReferrer = installReferrer,
        _clipboard = clipboard,
        _platform = platform ?? (() => defaultTargetPlatform);

  /// 실제 앱 — app_links 로 mybody:// · https://<서버>/i/ 링크를 받습니다. 안드로이드면 설치
  /// referrer 도 한 번 묻습니다. main.dart 만 만듭니다.
  factory InviteInbox.platform({FutureOr<String?> Function()? serverBase}) {
    final a = AppLinks();
    final android = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    return InviteInbox(
      links: () => a.uriLinkStream,
      initialLink: a.getInitialLink,
      serverBase: serverBase,
      installReferrer: android ? playInstallReferrer : null,
      clipboard: readClipboardText,
    );
  }

  final Stream<Uri> Function()? _links;
  final Future<Uri?> Function()? _initialLink;
  final DateTime Function() _now;
  final FutureOr<String?> Function()? _serverBase;
  final InstallReferrerRead? _installReferrer;
  final Future<String?> Function()? _clipboard;
  final TargetPlatform Function() _platform;

  StreamSubscription<Uri>? _sub;
  Future<void>? _loaded;
  Future<void>? _listening;
  Future<void>? _referred;
  bool _disposed = false;
  PendingInvite? _pending;

  /// 꺼내 간 코드들, 오래된 것부터. 이 기기에 적어 둡니다([_handledKey]).
  final List<String> _handled = [];

  /// 받은 코드 → 받은 시각. 두 길로 겹쳐 온 것을 거릅니다.
  final Map<String, DateTime> _seen = {};

  /// 듣기 시작합니다 — 저장된 코드를 읽고, 앱을 연 링크를 묻고, 그다음 링크 흐름을 듣습니다.
  /// 설치 referrer 를 받았으면 그것도 한 번 묻습니다. 여러 번 불러도 한 번만 합니다.
  /// 돌아오는 Future 는 저장된 코드를 다 읽고 흐름을 듣기 시작하고 referrer 를 다 물었을 때
  /// 끝납니다(아무도 기다리지 않습니다 — main.dart 는 부르고 지나갑니다).
  Future<void> start() {
    final loaded = _loaded ??= _load();
    final listening = _listening ??= _listen();
    final referred = _referred ??= _referrer();
    return Future.wait([loaded, listening, referred]).then((_) {});
  }

  Future<void> _listen() async {
    final initial = _initialLink;
    if (initial != null) {
      try {
        /* 채널이 답을 안 주는 일은 없어야 하지만, 여기서 멈추면 흐름을 영영 못 듣습니다. */
        final u = await initial().timeout(const Duration(seconds: 3));
        /* 기다리지 않습니다 — 겹침 표시(_seen)는 receive 의 첫머리에서 바로 적혀서, 곧 흐름으로
           한 번 더 오는 같은 링크를 거릅니다. */
        if (u != null) unawaited(receive(u, launch: true));
      } catch (_) {/* 앱을 연 링크를 못 물어도 흐름은 듣습니다 */}
    }
    final links = _links;
    if (links == null || _disposed) return;
    try {
      _sub = links().listen((u) => unawaited(receive(u)), onError: (Object _) {});
    } catch (_) {/* 링크를 못 들어도 앱은 돕니다 — 코드를 직접 넣으면 됩니다 */}
  }

  /* 설치 referrer — 처음 켤 때 한 번(install_referrer.dart). 초대가 있으면 앱을 연 링크와 같은
     규칙으로 쥡니다: 이미 꺼내 갔거나 쥐고 있는 코드면 그대로 둡니다(링크로도 받은 것). */
  Future<void> _referrer() async {
    final read = _installReferrer;
    if (read == null) return;
    try {
      await (_loaded ??= _load());
      final code = await installReferrerInviteOnce(read);
      if (code == null || _disposed) return;
      _seen[code] = _now();
      await _hold(code, launch: true);
    } catch (_) {/* referrer 가 없어도 링크 · 코드 칸이 있습니다 */}
  }

  Future<String?> _base() async {
    final f = _serverBase;
    if (f == null) return null;
    try {
      return await f();
    } catch (_) {
      return null;
    }
  }

  /// 링크 하나를 받습니다. 초대 링크면 코드를 쥐고 알리고 true. 초대 링크가 아니거나(다른
  /// 서버의 https 주소 포함), 코드 모양이 틀리거나, 방금 받은 것과 겹치면 false. [launch] 는
  /// 앱을 연 링크(getInitialLink) — 이미 꺼내 간 코드거나 쥐고 있는 코드면 되살아난 것이라
  /// false(머리 주석).
  Future<bool> receive(Uri uri, {bool launch = false}) async {
    final guess = _codeBeforeHost(uri);
    if (guess == null) return false;
    /* 겹침 판정은 기다리기 **전에** — 두 길로 거의 같이 온 둘이 서로를 봐야 합니다. 서버 주소를
       묻는 것도 기다림이라, 호스트를 보기 전의 코드로 판정합니다. */
    final now = _now();
    final last = _seen[guess];
    _seen[guess] = now;
    if (last != null && now.difference(last).abs() < kInviteDupWindow) return false;
    await (_loaded ??= _load());
    if (uri.scheme.toLowerCase() != kInviteScheme &&
        inviteCodeFromUri(uri, serverBase: await _base()) == null) {
      /* 다른 서버의 주소 — 겹침 표시를 되돌려, 곧 올 진짜 링크를 거르지 않게. */
      if (identical(_seen[guess], now)) {
        if (last == null) {
          _seen.remove(guess);
        } else {
          _seen[guess] = last;
        }
      }
      return false;
    }
    return _hold(guess, launch: launch);
  }

  /// 사람이 「요청」 을 눌러 고른 코드(클립보드에서 찾은 초대)를 링크로 받은 것처럼 쥡니다.
  /// 모양이 틀리면 false. 이미 꺼내 간 코드여도 받습니다 — 누른 사람은 답을 봐야 합니다.
  Future<bool> offer(String code) async {
    final c = code.trim().toUpperCase();
    if (!isInviteCode(c)) return false;
    await (_loaded ??= _load());
    _seen[c] = _now();
    return _hold(c);
  }

  Future<bool> _hold(String code, {bool launch = false}) async {
    if (launch && (_handled.contains(code) || pending?.code == code)) return false;
    /* 다시 누른 링크면 안내도 다시 — 누른 사람은 무슨 일이 생기는지 알고 싶어 합니다. */
    _pending = PendingInvite(code, _now());
    await _save();
    if (!_disposed) notifyListeners();
    return true;
  }

  /// 탭 화면이 처음 섰을 때 셸이 한 번 부릅니다 — **안드로이드만** 클립보드를 한 번 읽어,
  /// 초대(초대 페이지가 넣은 글 · 이 서버의 초대 주소 · 「초대 <코드>」)가 있으면 그 코드.
  /// 쥐지는 않습니다 — 셸이 「친구 요청할까요?」 를 묻고, 누르면 [offer] 로 쥡니다.
  ///
  /// 이 기기에서 한 번뿐입니다([kInviteClipboardKey] — 읽기 **전에** 적습니다). 아이폰은
  /// 읽지 않고 null(머리 주석) — 적지도 않습니다. 이미 쥐고 있거나 꺼내 간 코드(referrer ·
  /// 링크로 받은 것)면 묻지 않습니다 — 같은 요청을 두 번 권하지 않게. referrer 를 묻는 중이면
  /// 그 답을 먼저 기다립니다.
  ///
  /// **내 코드**([kMyInviteCodeKey] — 이 기기에서 「보내기」 로 내보낸 코드)면 묻지 않습니다.
  /// 테스터 인사 3쪽에서 「카톡 등으로 보내기」 → 공유 시트의 「복사」(또는 공유가 안 돼 복사해 둔
  /// 글)로 내 초대 글이 클립보드에 남은 채 인사를 닫으면, 바로 그때가 이 한 번의 차례입니다 —
  /// 그대로 두면 「초대 코드 <내 코드> 로 친구 요청할까요?」 를 묻고 누르면 「내 코드예요」 뿐입니다.
  Future<String?> clipboardInviteOnce() async {
    final read = _clipboard;
    if (read == null || _platform() != TargetPlatform.android) return null;
    await (_loaded ??= _load());
    await (_referred ?? Future<void>.value());
    final SharedPreferences sp;
    try {
      sp = await SharedPreferences.getInstance();
      if (sp.getBool(kInviteClipboardKey) ?? false) return null;
      await sp.setBool(kInviteClipboardKey, true);
    } catch (_) {
      return null;   // 적을 수 없으면 읽지 않습니다 — 켤 때마다 읽게 됩니다
    }
    String? text;
    try {
      text = await read().timeout(const Duration(seconds: 2));
    } catch (_) {
      return null;
    }
    final code = inviteCodeFromClipboard(text, serverBase: await _base());
    if (code == null || _handled.contains(code) || pending?.code == code) return null;
    if (code == sp.getString(kMyInviteCodeKey)) return null;
    return code;
  }

  /// 보낼 코드. 없거나 7일이 지났으면 null(지난 것은 이때 버립니다).
  PendingInvite? get pending {
    final p = _pending;
    if (p == null) return null;
    if (_now().difference(p.at) > kInvitePendingTtl) {
      _pending = null;
      unawaited(_save());
      return null;
    }
    return p;
  }

  /// 보낼 코드를 꺼냅니다 — **꺼내는 순간 비웁니다**. 같은 코드를 두 번 보내지 않는 자리가
  /// 여기 하나입니다. 없거나 지났으면 null.
  String? take() {
    final p = pending;
    if (p == null) return null;
    _pending = null;
    /* 꺼내 간 것으로 적습니다 — 앱이 꺼졌다 같은 링크로 되살아나도 또 안 보내게. */
    _handled
      ..remove(p.code)
      ..add(p.code);
    if (_handled.length > _handledCap) _handled.removeRange(0, _handled.length - _handledCap);
    unawaited(_save());
    return p.code;
  }

  /// 꺼내 간 코드를 서버에 못 보냈을 때(닿지 않음) — 꺼내 간 것으로 적은 것을 지웁니다.
  /// 그 링크를 다시 누르면, 앱이 꺼져 있다 켜지는 길이어도 다시 보냅니다.
  void unsent(String code) {
    if (_handled.remove(code)) unawaited(_save());
  }

  /// 로그인 안내를 했다고 적습니다 — 같은 코드로는 다시 안 알립니다.
  void markPrompted() {
    final p = pending;
    if (p == null || p.prompted) return;
    _pending = p.prompt();
    unawaited(_save());
  }

  Future<void> _load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      try {
        final h = jsonDecode(sp.getString(_handledKey) ?? '[]');
        if (h is List) {
          _handled
            ..clear()
            ..addAll(h.whereType<String>().where(isInviteCode));
        }
      } catch (_) {/* 깨졌으면 빈 것으로 — 되살아난 링크를 한 번 더 보낼 뿐입니다 */}
      final s = sp.getString(_pendingKey);
      final p = s == null ? null : PendingInvite.fromJson(jsonDecode(s));
      /* 읽는 사이에 새 링크가 왔으면(receive 가 먼저 적었으면) 그게 새것입니다. */
      if (_pending != null) return;
      _pending = p;
      if (s != null && p == null) await sp.remove(_pendingKey);
      if (pending != null && !_disposed) notifyListeners();
    } catch (_) {/* 못 읽으면 쥔 것이 없는 것 */}
  }

  Future<void> _save() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final p = _pending;
      if (p == null) {
        await sp.remove(_pendingKey);
      } else {
        await sp.setString(_pendingKey, jsonEncode(p.toJson()));
      }
      await sp.setString(_handledKey, jsonEncode(_handled));
    } catch (_) {/* 못 적어도 이번 실행 동안은 쥐고 있습니다 */}
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_sub?.cancel());
    _sub = null;
    super.dispose();
  }
}
