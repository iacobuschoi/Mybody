/* =============================================================================
 * update.dart — "새 버전이 나왔습니다" · "이 버전은 서버와 안 맞습니다"
 *
 * 지금까지는 업데이트 안내가 하나도 없었습니다. 스토어는 조용히 자동
 * 업데이트하고, TestFlight 는 스스로 알립니다. 그런데 GitHub 에서 APK 를
 * 받아 깐 친구는 새 판이 나와도 알 길이 없었습니다. 서버가 동의 판을
 * 올렸을 때 옛 앱은 「앱을 업데이트해 주세요」 오류 한 줄만 봤습니다 —
 * 왜 그런지, 어디서 받는지 없이.
 *
 * 서버의 GET /api/version 이 채널별 최신 판과 최소 판을 알려 줍니다.
 * 판단은 순수 함수로 두고(시험하기 쉽게), 가져오기는 작은 확인기
 * ([UpdateCheck])가 합니다.
 *
 * 지키는 것:
 *  - 켤 때와 앱으로 돌아올 때 확인하되 6시간에 한 번까지입니다. 실패는
 *    조용히 넘깁니다 — 서버가 꺼져 있다고 오류를 띄우지 않습니다. 이
 *    길이 없는 옛 서버(404)도 같습니다.
 *  - 받은 값과 「나중에」는 **이 기기에만** 둡니다(따로 한 칸). 동기화되는
 *    상태에 넣으면 다른 기기로 넘어가는데, 설치한 판은 폰마다 다릅니다.
 *  - 받은 값은 그 값을 준 서버의 것입니다. 서버를 옮기면 버립니다 — 옛
 *    서버의 최소 판으로 새 서버 이야기를 하면 안 됩니다.
 *  - 「서버와 안 맞음」은 닫을 수 없지만 앱을 막지도 않습니다. 기기의
 *    기록은 서버 없이도 됩니다.
 *  - 이 앱의 판을 서버에 보내지 않습니다. 묻기만 하고 비교는 여기서 합니다.
 * ========================================================================== */
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api.dart';

/* --- 판 번호 ----------------------------------------------------------------- */

/* 한 칸에 9자리까지. 그보다 길면 int 를 넘칠 수 있어 "모른다" 로 둡니다. */
final RegExp _xyz = RegExp(r'^(\d{1,9})\.(\d{1,9})\.(\d{1,9})$');

/// '0.2.8' → [0, 2, 8]. '+262' 같은 빌드 꼬리와 '-beta' 같은 꼬리는 뗍니다.
/// 모양이 틀리면 null 입니다 — 던지지 않습니다.
List<int>? parseVersion(Object? v) {
  if (v is! String) return null;
  var s = v.trim();
  final cut = s.indexOf(RegExp(r'[+-]'));
  if (cut >= 0) s = s.substring(0, cut);
  final m = _xyz.firstMatch(s);
  if (m == null) return null;
  return [int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!)];
}

/// 다듬은 'x.y.z'. 모양이 틀리면 ''. '0.2.08' 은 '0.2.8' 이 됩니다 —
/// 서버(server/appversion.js)와 같은 규칙입니다.
String cleanVersion(Object? v) => parseVersion(v)?.join('.') ?? '';

/// a 가 b 보다 앞이면 음수, 같으면 0, 뒤면 양수.
///
/// **숫자로 견줍니다.** 글자로 견주면 '0.2.10' 이 '0.2.9' 보다 앞이 됩니다.
/// 어느 한쪽이라도 모양이 틀리면 null(모른다) 입니다 — 모르는 것을 두고
/// "업데이트하세요" 라고 하지 않습니다.
int? compareVersions(Object? a, Object? b) {
  final x = parseVersion(a), y = parseVersion(b);
  if (x == null || y == null) return null;
  for (var i = 0; i < 3; i++) {
    if (x[i] != y[i]) return x[i] < y[i] ? -1 : 1;
  }
  return 0;
}

/* --- 어디서 깔았나 ----------------------------------------------------------- */

/// 이 앱을 받은 곳. 받은 곳마다 최신 판이 다릅니다 — 스토어 심사를
/// 기다리는 동안에는 APK 만 새 판일 수 있습니다.
enum UpdateChannel { appstore, testflight, play, apk, none }

/* 플레이 스토어가 깐 앱의 설치 주체. 아주 옛 기기는 feedback 쪽 이름을 댑니다. */
const _playInstallers = {'com.android.vending', 'com.google.android.feedback'};

/// 플레이에 올리는 묶음(AAB)으로 만든 앱인가. apk.yml 이 그 빌드에만
/// `--dart-define=STORE=play` 를 넣습니다. GitHub 의 APK 에는 없습니다.
const bool kPlayBuild = String.fromEnvironment('STORE') == 'play';

/// package_info_plus 의 `installerStore` 로 채널을 정합니다.
///
/// 안드로이드는 설치를 시작한 앱의 패키지 이름을 줍니다(11 이상은
/// initiatingPackageName). 플레이면 'com.android.vending' 이고, 파일로 깔면
/// 파일 관리자나 브라우저 이름, adb 면 null 이나 셸입니다 — 플레이가 아니면
/// 전부 직접 설치한 APK 로 봅니다.
///
/// **다만 플레이용으로 만든 앱([playBuild])은 누가 깔았든 play 입니다.**
/// 플레이의 출시 전 보고서는 심사할 앱을 adb 로 깝니다. 설치 주체만 보면
/// 그 기기에 "GitHub 에서 새 APK 를 받으세요" 가 뜹니다 — 플레이로 받은
/// 앱이 플레이 밖 업데이트로 이끄는 것은 플레이 정책(기기 및 네트워크
/// 악용)에 걸립니다. null 을 아예 "모름" 으로 두지 않는 까닭: 옛 기기는
/// 파일로 깐 앱도 설치 주체가 비어 있을 수 있고, 그 사람이 이 안내가 제일
/// 필요한 사람입니다.
///
/// 아이폰은 영수증 경로로 셋 중 하나를 줍니다: 'com.apple.testflight'
/// (영수증이 sandboxReceipt), 'com.apple.simulator', 그 밖은 'com.apple'.
/// TestFlight 가 아니면 앱스토어로 봅니다.
///
/// 웹과 데스크톱은 알릴 곳이 없습니다.
UpdateChannel channelOf(TargetPlatform platform, String? installerStore,
    {bool web = false, bool playBuild = false}) {
  if (web) return UpdateChannel.none;
  switch (platform) {
    case TargetPlatform.android:
      if (playBuild) return UpdateChannel.play;
      return _playInstallers.contains(installerStore) ? UpdateChannel.play : UpdateChannel.apk;
    case TargetPlatform.iOS:
      return installerStore == 'com.apple.testflight'
          ? UpdateChannel.testflight
          : UpdateChannel.appstore;
    default:
      return UpdateChannel.none;
  }
}

/// 설정 화면에 쓰는 이름. 친구를 도울 때 "어디서 깔았어?" 를 묻지 않게.
///
/// testflight 는 이름을 안 붙입니다. 아이폰이 주는 단서(sandboxReceipt)는
/// TestFlight · 앱스토어 심사 · 개발 빌드가 모두 같습니다. 심사하는 사람
/// 화면에 "TestFlight" 가 찍히면 시험판을 냈다고 볼 수 있습니다(심사
/// 지침 2.2). 앱스토어로 깐 것만 "앱스토어" 로 보이면 나머지는 짐작됩니다.
String channelLabel(UpdateChannel c) => switch (c) {
      UpdateChannel.appstore => '앱스토어',
      UpdateChannel.testflight => '',
      UpdateChannel.play => '플레이 스토어',
      UpdateChannel.apk => '직접 설치한 APK',
      UpdateChannel.none => '',
    };

/* 서버 값의 칸 이름. TestFlight 는 따로 칸이 없고 앱스토어 값을 봅니다. */
String? _slot(UpdateChannel c) => switch (c) {
      UpdateChannel.appstore || UpdateChannel.testflight => 'appstore',
      UpdateChannel.play => 'play',
      UpdateChannel.apk => 'apk',
      UpdateChannel.none => null,
    };

const _slots = ['appstore', 'play', 'apk'];

/// 서버가 주소를 안 줬을 때 여는 곳. 서버의 기본값과 같습니다.
const kUpdateUrls = {
  'appstore': 'https://apps.apple.com/kr/app/id6815144446',
  'play': 'https://play.google.com/store/apps/details?id=io.github.iacobuschoi.mybody',
  'apk': 'https://github.com/iacobuschoi/Mybody/releases/latest',
};

/* 서버에서 온 주소는 https 만 엽니다. 이 값은 단추가 그대로 여는 곳입니다. */
bool _okUrl(Object? v) {
  if (v is! String) return false;
  final u = Uri.tryParse(v.trim());
  return u != null && u.scheme == 'https' && u.host.isNotEmpty;
}

/* --- 서버가 알려 준 것 ------------------------------------------------------- */

/// GET /api/version 의 답. 모르는 칸 · 틀린 값은 '' 로 둡니다 — 던지지 않습니다.
@immutable
class VersionInfo {
  const VersionInfo({this.latest = const {}, this.min = '', this.urls = const {}});

  /// 채널별 최신 판('appstore' · 'play' · 'apk'). '' 는 "안 알림".
  final Map<String, String> latest;

  /// 서버가 받아 주는 가장 낮은 판. '' 는 "제한 없음".
  final String min;

  /// 채널별 업데이트 주소. 없는 칸은 [kUpdateUrls] 로 채웁니다.
  final Map<String, String> urls;

  factory VersionInfo.fromJson(Object? j) {
    if (j is! Map) return const VersionInfo();
    final l = j['latest'], u = j['urls'];
    return VersionInfo(
      latest: {for (final k in _slots) k: cleanVersion(l is Map ? l[k] : null)},
      min: cleanVersion(j['min']),
      urls: {
        for (final k in _slots)
          if (u is Map && _okUrl(u[k])) k: (u[k] as String).trim(),
      },
    );
  }

  Map<String, Object?> toJson() => {'latest': latest, 'min': min, 'urls': urls};

  String latestFor(UpdateChannel c) => latest[_slot(c)] ?? '';

  String urlFor(UpdateChannel c) {
    final k = _slot(c);
    if (k == null) return '';
    return urls[k] ?? kUpdateUrls[k]!;
  }
}

/* --- 무엇을 알릴까 ----------------------------------------------------------- */

enum UpdateKind {
  /// 새 판이 있습니다. 「나중에」로 그 판만 접을 수 있습니다.
  available,

  /// 이 판은 서버가 더는 받지 않습니다. 접을 수 없습니다.
  required,
}

@immutable
class UpdateNotice {
  const UpdateNotice({
    required this.kind,
    required this.version,
    required this.current,
    required this.url,
    required this.channel,
  });

  final UpdateKind kind;

  /// 알리는 판 — 새 판이면 최신 판, 서버와 안 맞으면 최소 판.
  final String version;

  /// 지금 깔려 있는 판.
  final String current;

  /// 업데이트 단추가 여는 곳.
  final String url;

  final UpdateChannel channel;

  bool get dismissable => kind == UpdateKind.available;
}

/// 알릴 것이 있으면 하나, 없으면 null.
///
///  - **서버와 안 맞음**: 지금 판 < 최소 판. 「나중에」를 눌렀어도 보입니다.
///  - **새 판**: 지금 판 < 이 채널의 최신 판, 그리고 그 판을 접지 않았을 때.
///    더 새 판이 나오면 다시 보입니다 — 접은 것은 그 판 하나입니다.
///  - TestFlight 는 앱스토어 값을 보되 「서버와 안 맞음」만 띄웁니다.
///    새 빌드는 TestFlight 가 스스로 알립니다. 두 번 알리면 소음입니다.
///  - 서버 값이 없거나, 판을 모르거나, 모양이 틀리면 아무것도 안 띄웁니다.
UpdateNotice? decideUpdate({
  required String current,
  required UpdateChannel channel,
  VersionInfo? info,
  String dismissed = '',
}) {
  if (info == null || channel == UpdateChannel.none) return null;
  final now = cleanVersion(current);
  if (now.isEmpty) return null;
  final url = info.urlFor(channel);

  final belowMin = compareVersions(now, info.min);
  if (belowMin != null && belowMin < 0) {
    return UpdateNotice(
        kind: UpdateKind.required, version: info.min, current: now, url: url, channel: channel);
  }
  if (channel == UpdateChannel.testflight) return null;

  final latest = info.latestFor(channel);
  if (latest.isEmpty || latest == cleanVersion(dismissed)) return null;
  final behind = compareVersions(now, latest);
  if (behind == null || behind >= 0) return null;
  return UpdateNotice(
      kind: UpdateKind.available, version: latest, current: now, url: url, channel: channel);
}

/* --- 확인기 ------------------------------------------------------------------ */

/// 켤 때와 앱으로 돌아올 때 서버에 새 판을 묻습니다. 홈의 안내와 설정의
/// 판 표시가 이걸 듣습니다.
class UpdateCheck extends ChangeNotifier {
  UpdateCheck({
    required Api api,
    Future<PackageInfo> Function()? packageInfo,
    TargetPlatform? platform,
    bool? web,
    DateTime Function()? now,
    Future<bool> Function(Uri)? launch,
  })  : _api = api,
        _packageInfo = packageInfo ?? PackageInfo.fromPlatform,
        _platform = platform,
        _web = web,
        _now = now ?? DateTime.now,
        _launch = launch ?? _openOutside;

  /// 이 기기에만 있는 칸. 동기화되는 상태(`mybody.state.v1`)와 따로 둡니다.
  static const storageKey = 'mybody.update.v1';

  /// 서버에 묻는 간격. 새 판은 며칠에 한 번 나오고, 서버는 주인 노트북입니다.
  static const every = Duration(hours: 6);

  Api _api;
  final Future<PackageInfo> Function() _packageInfo;
  final TargetPlatform? _platform;
  final bool? _web;
  final DateTime Function() _now;
  final Future<bool> Function(Uri) _launch;

  PackageInfo? _package;
  UpdateChannel _channel = UpdateChannel.none;
  VersionInfo? _info;
  DateTime? _checkedAt;
  String _dismissed = '';
  bool _started = false;
  bool _loaded = false;
  bool _busy = false;
  bool _again = false;
  bool _disposed = false;
  AppLifecycleListener? _life;

  /// 이 앱의 판과 빌드 번호. 못 읽었으면 null 입니다.
  PackageInfo? get package => _package;
  UpdateChannel get channel => _channel;
  VersionInfo? get info => _info;
  DateTime? get checkedAt => _checkedAt;
  String get dismissed => _dismissed;

  /// 지금 띄울 안내. 없으면 null.
  UpdateNotice? get notice {
    final p = _package;
    if (p == null) return null;
    return decideUpdate(current: p.version, channel: _channel, info: _info, dismissed: _dismissed);
  }

  Api get api => _api;

  /// 서버를 옮겼으면 지난 답을 버리고 새 서버에 바로 묻습니다 — 6시간을
  /// 기다리지 않습니다.
  ///
  /// 버리는 까닭: 새 서버가 이 길이 없는 옛 서버(404)거나 꺼져 있으면 새
  /// 답이 안 옵니다. 그때 옛 서버의 최소 판이 남아 있으면, 닫을 수 없는
  /// 안내가 쓰지도 않는 서버와 안 맞는다고 계속 말합니다.
  /// 로그아웃처럼 같은 서버에 Api 만 새로 만든 것이면 지난 답이 그대로 맞습니다.
  set api(Api a) {
    if (identical(a, _api)) return;
    final moved = _base(a) != _base(_api);
    _api = a;
    if (!moved) return;
    _info = null;
    _checkedAt = null;
    _changed();
    /* 아직 못 읽었으면 적지 않습니다 — 「나중에」 가 지워집니다. 읽을 때
       [_load] 가 옛 서버의 답을 알아서 거릅니다. */
    if (_loaded) unawaited(_save());
    unawaited(check(force: true));
  }

  static String _base(Api a) => a.baseUrl.trim().replaceAll(RegExp(r'/+$'), '');

  /// 앱으로 돌아올 때마다 확인합니다(간격은 [check] 가 지킵니다).
  void wire() {
    _life ??= AppLifecycleListener(onResume: () => unawaited(check()));
  }

  @override
  void dispose() {
    _disposed = true;
    _life?.dispose();
    super.dispose();
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  /// 판을 읽고, 지난번 답을 꺼내 보이고, 때가 됐으면 서버에 묻습니다.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    await _load();
    /* 지난번 답으로 먼저 띄웁니다 — 서버가 꺼져 있어도 "서버와 안 맞음" 은
       계속 보여야 합니다. */
    _changed();
    await check();
  }

  /// 서버에 묻습니다. [every] 안에 이미 물었으면 건너뜁니다.
  ///
  /// **서버에 못 닿으면 물은 것으로 치지 않습니다.** 지하철에서 켰다고
  /// 여섯 시간 동안 확인을 거르면 안 되니까요([_answered]). 대답은 했지만
  /// 실패(옛 서버의 404 등)면 물은 것으로 칩니다 — 같은 서버에 같은 404 를
  /// 계속 물을 까닭이 없습니다. 어느 쪽이든 지난번 답은 그대로 둡니다.
  Future<void> check({bool force = false}) async {
    if (!_loaded || _disposed) return;
    if (_channel == UpdateChannel.none) return;
    if (_busy) {
      /* 묻는 중에 서버를 옮겼으면 끝난 뒤 새 서버에 다시 묻습니다. 그냥
         건너뛰면 옛 서버에 물은 것이 "물었음" 으로 남아 여섯 시간을 쉽니다. */
      if (force) _again = true;
      return;
    }
    final last = _checkedAt;
    if (!force && last != null) {
      final age = _now().difference(last);
      /* 시계를 뒤로 돌린 기기(나이가 음수)는 오래된 것으로 봅니다. */
      if (!age.isNegative && age < every) return;
    }
    _busy = true;
    final api = _api;
    try {
      final r = await api.appVersion();
      /* 묻는 사이 서버를 옮겼으면 이 답은 옛 서버의 것입니다 — 버립니다. */
      if (_base(api) != _base(_api)) return;
      if (!_answered(r.status)) return;
      _checkedAt = _now();
      if (r.ok && r.body['ok'] == true) _info = VersionInfo.fromJson(r.body);
      await _save();
      _changed();
    } catch (_) {
      /* 안내 하나 때문에 앱이 멈추면 안 됩니다. */
    } finally {
      _busy = false;
      if (_again && !_disposed) {
        _again = false;
        unawaited(check(force: true));
      }
    }
  }

  /* 서버가 정말 대답했나. 못 닿음(0), 시간 초과(408), 너무 잦음(429),
     5xx 는 물은 것으로 치지 않습니다. 터널(cloudflared)은 노트북이 꺼져
     있으면 502 · 530 을 대신 답하는데, 그건 서버의 대답이 아닙니다 —
     다음에 앱으로 돌아올 때 다시 묻습니다. 404(이 길이 없는 옛 서버)와
     401(옛 서버는 모르는 길에 로그인부터 묻습니다)은 진짜 대답입니다. */
  static bool _answered(int status) =>
      status != 0 && status != 408 && status != 429 && status < 500;

  /// 「나중에」 — 지금 알린 새 판만 접습니다. 「서버와 안 맞음」은 접지 않습니다.
  Future<void> dismiss() async {
    final n = notice;
    if (n == null || !n.dismissable) return;
    _dismissed = n.version;
    _changed();
    await _save();
  }

  /// 업데이트 단추 — 스토어나 릴리스 페이지를 앱 밖에서 엽니다.
  Future<bool> open(UpdateNotice n) async {
    final u = Uri.tryParse(n.url);
    if (u == null || n.url.isEmpty) return false;
    try {
      return await _launch(u);
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _openOutside(Uri u) =>
      launchUrl(u, mode: LaunchMode.externalApplication);

  Future<void> _load() async {
    try {
      final p = await _packageInfo();
      _package = p;
      _channel = channelOf(_platform ?? defaultTargetPlatform, p.installerStore,
          web: _web ?? kIsWeb, playBuild: kPlayBuild);
    } catch (_) {
      /* 판을 모르면 견줄 것도 없습니다 — 안내 없이 갑니다. */
    }
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(storageKey);
      final j = raw == null ? null : jsonDecode(raw);
      if (j is Map) {
        /* 지난 답은 그 답을 준 서버에서만 씁니다. 서버를 옮기고 바로 껐다
           켜면 옛 서버의 답이 남아 있을 수 있습니다. */
        if (j['from'] == _base(_api)) {
          if (j['info'] != null) _info = VersionInfo.fromJson(j['info']);
          _checkedAt = DateTime.tryParse('${j['at'] ?? ''}');
        }
        _dismissed = cleanVersion(j['dismissed']);
      }
    } catch (_) {
      /* 못 읽으면 처음처럼 — 서버에 다시 물으면 됩니다. */
    }
    _loaded = true;
  }

  Future<void> _save() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(storageKey, jsonEncode({
        /* 이 답을 준 서버. 옮긴 뒤에는 [_load] 가 안 씁니다. */
        'from': _base(_api),
        if (_info != null) 'info': _info!.toJson(),
        if (_checkedAt != null) 'at': _checkedAt!.toUtc().toIso8601String(),
        if (_dismissed.isNotEmpty) 'dismissed': _dismissed,
      }));
    } catch (_) {/* 못 적으면 다음에 켤 때 한 번 더 물을 뿐입니다 */}
  }
}
