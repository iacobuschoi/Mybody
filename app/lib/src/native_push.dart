/* =============================================================================
 * native_push.dart — 앱 알림(안드로이드 FCM · 아이폰은 FCM 을 거친 APNs)
 *
 * 왜 있나: 친구의 운동 독촉이 앱이 아니라 크롬(예전 웹 앱의 웹 푸시)으로 왔습니다.
 * 앱은 켤 때만 서버에서 가져왔기 때문입니다. 이제 이 기기의 알림 주소(FCM 토큰)를
 * 내 로그인에 묶어 서버에 등록하고, 서버는 앱이 있는 사람에게는 앱으로 보냅니다
 * (최근에 앱을 쓴 사람에게는 크롬을 조용히 — server.js pushToUser).
 *
 * **설정 파일이 없으면 아무것도 안 합니다.** google-services.json · GoogleService-Info.plist
 * 는 공개 저장소에 안 넣고 CI 가 비밀에서 꺼내 둡니다. 비밀이 아직 없는 빌드에서는
 * Firebase 초기화가 실패하고, 앱은 예전처럼 켤 때 · 돌아올 때 가져옵니다(pokes.dart).
 *
 * Firebase 를 만지는 곳은 [FirebasePushPlatform] 하나입니다. 나머지는 [PushPlatform]
 * 만 보므로 시험은 가짜를 넣어 등록 · 갱신 · 로그아웃을 확인합니다.
 *
 * 권한: 아이폰은 첫 로그인 뒤 한 번 시스템 창으로 묻고, 거절하면 다시 조르지 않습니다.
 * 안드로이드는 알림 권한을 이미 SnackNudge.init 이 묻습니다 — 여기서 또 물으면 같은 창이
 * 두 번 뜹니다. 거절된 기기도 등록은 합니다(permission: 'denied'). 서버는 그런 사람에게
 * 크롬 알림을 계속 보내므로, 앱 알림을 끈 사람이 아무 알림도 못 받게 되지는 않습니다.
 *
 * 구글에 기기를 등록하는 것은 **로그인한 뒤에만** 입니다. 매니페스트 · Info.plist 에서 FCM
 * 자동 초기화를 꺼 두고, 서버에 등록할 때 켜고(setAutoInit), 로그아웃하면 끕니다. 켜 두면
 * 로그인하지 않은 사람 · 「로그인 없이 쓰기」 사용자도 켤 때마다 설치 ID · 토큰이 만들어집니다.
 *
 * 등록할 때 서버마다 따로 만든 난수 비밀(설치 비밀)을 같이 보냅니다. 토큰만 아는 사람(같은
 * 폰을 쓰던 사람 · 토큰을 받아 간 다른 서버의 운영자)이 이 기기를 자기 계정으로 옮기지 못하게
 * 서버가 이 값을 봅니다(server/db.js addPushDevice). 서버마다 다르므로 한 서버가 받은 비밀로
 * 다른 서버의 등록을 옮길 수도 없습니다.
 * ========================================================================== */
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';

/// 알림 data.route 중 앱이 따라가는 것. 모르는 값은 버립니다 — 서버가 새 값을 보내도
/// 옛 앱이 엉뚱한 곳으로 가지 않게.
const kPushRoutes = {'social', 'pokes'};

/// 알림의 data 에서 갈 곳을 꺼냅니다. [kPushRoutes] 밖이면 null.
String? pushRoute(Map<String, dynamic> data) {
  final r = '${data['route'] ?? ''}';
  return kPushRoutes.contains(r) ? r : null;
}

/// 앱을 쓰는 중에 온 앱 알림을 안드로이드에서 직접 띄울 때의 번호 시작 —
/// 간식(7) · 끼니(100~141) · 독촉(1000~1999) · 운동(2000~2013)과 겹치지 않게.
const kPushIdBase = 3000;

/// 친구 알림 채널. 로컬 알림(SnackNudge.showNow)과 FCM 이 같이 씁니다 — 매니페스트의
/// default_notification_channel_id 와 서버가 보내는 android.notification.channel_id 도 이 값.
const kFriendsChannelId = 'friends';
const kFriendsChannelName = '친구 알림';
const kFriendsChannelDescription = '친구의 운동 독촉 · 운동 소식 · 친구 요청';

/// 상태바용 흰 단색 아이콘(res/drawable/ic_stat_mybody.xml). 컬러 앱 아이콘은 상태바에서
/// 흰 덩어리로 나옵니다.
const kPushIcon = 'ic_stat_mybody';

/// 아이폰 권한을 한 번 물었는가 — 거절하면 다시 조르지 않습니다.
const kPushAskedKey = 'mybody.push.asked.v1';

/// 설치 비밀을 두는 자리. 뒤에 `|서버 주소` 가 붙습니다(서버마다 따로).
const kPushSecretKey = 'mybody.push.secret.v1';

/// 독촉 알림 한 칸. 서버는 FCM 에 tag `poke-<독촉 번호>` 를 붙여 보내고, 안드로이드의 FCM 알림은
/// 그 tag 와 번호 0 으로 뜹니다. 앱이 가져와서 띄우는 로컬 알림도 같은 칸을 쓰면, 둘이 엇갈려
/// 와도(가져오기가 FCM 보다 먼저 닿은 경우) 알림이 두 개가 되지 않고 한 칸을 덮어씁니다.
/// 아이폰의 로컬 알림은 번호만으로 칸을 가르므로(tag 없음) 예전 번호(1000~1999)를 씁니다 —
/// 거기서는 [NativePush.claimPoke] 가 중복을 막습니다.
({int id, String? tag}) pokeSlot(int pokeId, {bool? android}) {
  final a = android ?? (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);
  return a ? (id: 0, tag: 'poke-$pokeId') : (id: 1000 + pokeId % 1000, tag: null);
}

/// 알림 하나를 Firebase 와 상관없는 꼴로.
class PushMessage {
  const PushMessage({this.title, this.body, this.data = const {}, this.id});
  final String? title;
  final String? body;
  final Map<String, dynamic> data;
  final String? id;

  String? get route => pushRoute(data);
}

enum PushPermission { granted, denied, unknown }

/// Firebase 를 감싼 것. 진짜는 [FirebasePushPlatform], 시험은 가짜.
abstract class PushPlatform {
  /// 서버에 보내는 이름 — 'android' | 'ios'.
  String get platform;

  /// 앱이 앞에 있을 때 시스템이 알아서 띄우는가. 아이폰은 AppDelegate 가 띄우게 해 두었고,
  /// 안드로이드는 안 띄우고 onMessage 로만 넘기므로 앱이 직접 띄웁니다.
  bool get systemShowsForeground;

  /// 시스템 권한 창을 여기서 묻는가(아이폰). 안드로이드는 SnackNudge 가 묻습니다.
  bool get asksPermission;

  /// 설정 파일이 없거나 초기화가 실패하면 false — 그러면 아무것도 안 합니다.
  Future<bool> init();

  Future<PushPermission> permission({required bool ask});

  /// 이 기기의 FCM 토큰. 못 얻으면 null(아이폰에서 APNs 토큰이 안 오는 빌드 등).
  Future<String?> token();

  /// FCM 자동 초기화(구글에 설치 ID · 토큰을 스스로 만들고 갱신) 켜기 · 끄기.
  /// 로그인해서 서버에 등록할 때만 켭니다.
  Future<void> setAutoInit(bool on);

  Future<void> deleteToken();

  Stream<String> get onTokenRefresh;

  /// 앱을 쓰는 중에 온 알림.
  Stream<PushMessage> get onForeground;

  /// 뒤에 있던 앱이 알림을 눌러 앞으로 나옴.
  Stream<PushMessage> get onOpened;

  /// 꺼져 있던 앱이 알림을 눌러 켜짐.
  Future<PushMessage?> initialMessage();

  /// [tag] 가 있으면 안드로이드에서 같은 tag · 번호의 알림을 덮어씁니다(FCM 이 띄운 것 포함).
  Future<void> showLocal({required int id, required String title, required String body, String? payload,
      String? tag});
}

/* 백그라운드 메시지 처리기(onBackgroundMessage)는 두지 않습니다. 서버가 보내는 것은 전부
   알림(notification) 메시지라 앱이 뒤에 있거나 꺼져 있으면 시스템이 그대로 띄우고, 내용은
   앱이 돌아올 때 서버에서 가져옵니다. 빈 처리기라도 등록하는 순간 안드로이드는 알림마다
   헤드리스 Flutter 엔진을 띄워 모든 플러그인을 올립니다 — 얻는 것 없이 배터리 · 메모리를 쓰고,
   그 엔진에서 다른 플러그인이 초기화에 실패할 위험만 늘어납니다. 데이터 전용 메시지를
   뒤에서 처리해야 할 날이 오면 그때 넣습니다. */

/// 진짜 Firebase. 설정 파일이 없는 빌드에서는 [init] 이 false 를 돌려주고 끝납니다.
class FirebasePushPlatform implements PushPlatform {
  FirebasePushPlatform(this.platform);

  @override
  final String platform;

  bool get _ios => platform == 'ios';

  @override
  bool get systemShowsForeground => _ios;

  @override
  bool get asksPermission => _ios;

  @override
  Future<bool> init() async {
    try {
      await Firebase.initializeApp();
    } catch (_) {
      return false;   // google-services.json / GoogleService-Info.plist 가 없는 빌드
    }
    if (!_ios) {
      /* 채널을 미리 만듭니다. 전에는 첫 로컬 알림 때에야 생겨서, FCM 이 먼저 오면 안드로이드가
         「기타(Miscellaneous)」 채널로 띄웠습니다. 중요도는 이미 깔린 폰의 채널과 같은 값 —
         한 번 만들어진 채널의 중요도는 코드로 못 바꿉니다. */
      try {
        await FlutterLocalNotificationsPlugin()
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
            ?.createNotificationChannel(const AndroidNotificationChannel(
              kFriendsChannelId, kFriendsChannelName,
              description: kFriendsChannelDescription,
              importance: Importance.defaultImportance,
            ));
      } catch (_) {}
    }
    return true;
  }

  @override
  Future<PushPermission> permission({required bool ask}) async {
    final fm = FirebaseMessaging.instance;
    final s = ask
        ? await fm.requestPermission(alert: true, sound: true, badge: false)
        : await fm.getNotificationSettings();
    final a = s.authorizationStatus;
    if (a == AuthorizationStatus.authorized || a == AuthorizationStatus.provisional) {
      return PushPermission.granted;
    }
    if (a == AuthorizationStatus.denied || a == AuthorizationStatus.deniedPermanently) {
      return PushPermission.denied;
    }
    return PushPermission.unknown;
  }

  @override
  Future<String?> token() async {
    final fm = FirebaseMessaging.instance;
    try {
      if (_ios) {
        /* APNs 토큰보다 먼저 getToken 을 부르면 apns-token-not-set 으로 던집니다.
           푸시 권한(aps-environment)이 안 붙은 빌드에서는 끝내 안 오므로 10초만 기다립니다. */
        for (var i = 0; i < 10 && await fm.getAPNSToken() == null; i++) {
          await Future<void>.delayed(const Duration(seconds: 1));
        }
      }
      return await fm.getToken();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> setAutoInit(bool on) => FirebaseMessaging.instance.setAutoInitEnabled(on);

  @override
  Future<void> deleteToken() => FirebaseMessaging.instance.deleteToken();

  @override
  Stream<String> get onTokenRefresh => FirebaseMessaging.instance.onTokenRefresh;

  static PushMessage _msg(RemoteMessage m) => PushMessage(
      title: m.notification?.title, body: m.notification?.body, data: m.data, id: m.messageId);

  @override
  Stream<PushMessage> get onForeground => FirebaseMessaging.onMessage.map(_msg);

  @override
  Stream<PushMessage> get onOpened => FirebaseMessaging.onMessageOpenedApp.map(_msg);

  @override
  Future<PushMessage?> initialMessage() async {
    final m = await FirebaseMessaging.instance.getInitialMessage();
    return m == null ? null : _msg(m);
  }

  @override
  Future<void> showLocal({required int id, required String title, required String body, String? payload,
          String? tag}) =>
      /* 같은 플러그인(싱글턴)이라 누르면 SnackNudge 가 걸어 둔 콜백이 payload 를
         notificationRoute 로 넘기고, 셸이 그 화면으로 갑니다. */
      FlutterLocalNotificationsPlugin().show(
        id: id,
        title: title,
        body: body,
        payload: payload,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            kFriendsChannelId, kFriendsChannelName,
            channelDescription: kFriendsChannelDescription,
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
            icon: kPushIcon,
            tag: tag,
          ),
        ),
      );
}

PushPlatform? _defaultPlatform() {
  /* 웹 빌드(검사용)와 데스크톱에서는 Firebase 를 부르지 않습니다. */
  if (kIsWeb) return null;
  if (defaultTargetPlatform == TargetPlatform.android) return FirebasePushPlatform('android');
  if (defaultTargetPlatform == TargetPlatform.iOS) return FirebasePushPlatform('ios');
  return null;
}

Future<String> _defaultAppVersion() async {
  final p = await PackageInfo.fromPlatform();
  return p.buildNumber.isEmpty ? p.version : '${p.version}+${p.buildNumber}';
}

/// 이 기기의 앱 알림. 앱 전체에 하나([instance]) — 설정 화면이 상태를 읽습니다.
class NativePush extends ChangeNotifier {
  NativePush({
    PushPlatform? Function()? platform,
    Future<String> Function()? appVersion,
    DateTime Function()? now,
  })  : _makePlatform = platform ?? _defaultPlatform,
        _appVersion = appVersion ?? _defaultAppVersion,
        _now = now ?? DateTime.now;

  /// 앱이 쓰는 것. 시험은 가짜 플랫폼을 넣은 것으로 바꿔 끼웁니다.
  static NativePush instance = NativePush();

  final PushPlatform? Function() _makePlatform;
  final Future<String> Function() _appVersion;
  final DateTime Function() _now;

  PushPlatform? _p;
  Api? _api;
  String? _session;   // 마지막으로 본 로그인 토큰 — 바뀌면 다시 등록, 사라지면 FCM 토큰 폐기
  bool _started = false;
  bool _initDone = false;
  void Function(String route)? _onOpen;
  Future<void> Function(PushMessage m, String? route)? _onMessage;
  final _subs = <StreamSubscription<Object?>>[];

  String? _token;
  PushPermission _perm = PushPermission.unknown;
  String? _sentKey;
  DateTime? _registeredAt;
  bool? _serverSupports;
  bool? _serverFcm;

  /// 앱 알림(FCM) · 가져오기 중 한쪽이 이미 알린 독촉 번호 — [claimPoke].
  final _claimedPokes = <String>{};

  /// 한 번에 하나씩 — 로그아웃의 토큰 폐기와 곧바로 이은 로그인의 등록이 겹치면
  /// 폐기될 옛 토큰이 새 계정에 등록됩니다.
  Future<void> _chain = Future<void>.value();

  Future<void> _serial(Future<void> Function() job) {
    final run = _chain.then((_) => job());
    _chain = run.catchError((_) {});
    return run;
  }

  /// 줄 서 있는 등록 · 폐기가 다 끝날 때 — 시험이 기다리는 데 씁니다.
  @visibleForTesting
  Future<void> get idle => _chain;

  /// 이 기기에서 앱 알림을 쓸 수 있는가(설정 파일이 있고 초기화가 됐는가).
  bool get available => _p != null;

  /// [start] 가 불렸는데 아직 초기화 중인가 — 설정 화면이 「확인 중」 과 「꺼짐」 을 가릅니다.
  bool get starting => _started && !_initDone;

  PushPermission get permission => _perm;
  String? get token => _token;

  /// 지금 로그인으로 서버에 등록돼 있는가.
  bool get registered => _sentKey != null;

  /// 서버가 등록 길을 아는가. false 면 옛 서버(404), null 이면 아직 모름.
  bool? get serverSupports => _serverSupports;

  /// 서버가 실제로 보낼 수 있는가(서버의 FCM 설정 파일). null 이면 아직 모름.
  bool? get serverFcm => _serverFcm;

  /// 이 독촉을 지금 폰 알림으로 알려도 되는가 — 처음 묻는 쪽만 true.
  ///
  /// 같은 독촉이 두 길로 옵니다: 앱 알림(FCM)과 서버에서 가져오기. 서버의 pushed 표시는
  /// FCM 이 받은 **뒤에야** 적히므로, 그 전에 가져오면 가져오기도 알림을 띄우고 곧이어
  /// FCM 도 띄웁니다. 두 길이 여기서 번호를 먼저 잡은 쪽만 띄웁니다.
  bool claimPoke(Object? pokeId) {
    final k = '${pokeId ?? ''}';
    if (k.isEmpty) return true;
    if (_claimedPokes.length > 500) _claimedPokes.remove(_claimedPokes.first);
    return _claimedPokes.add(k);
  }

  /// 켤 때 한 번. [onOpen] 은 알림을 눌러 앱이 앞으로 왔을 때 갈 곳,
  /// [onMessage] 는 앱을 쓰는 중에 온 알림(독촉이면 바로 가져오기).
  Future<void> start({
    required Api api,
    void Function(String route)? onOpen,
    Future<void> Function(PushMessage m, String? route)? onMessage,
  }) async {
    if (_started) return;
    _started = true;
    _onOpen = onOpen;
    _onMessage = onMessage;
    /* 켜지기 전에 서버 주소가 바뀌어 [attach] 가 새 Api 를 이미 물었으면 그쪽을 둡니다. */
    if (_api == null) _bind(api);
    PushPlatform? p;
    try {
      p = _makePlatform();
    } catch (_) {
      p = null;
    }
    var ok = false;
    if (p != null) {
      try {
        ok = await p.init();
      } catch (_) {
        ok = false;
      }
    }
    if (!ok || p == null) {
      _initDone = true;
      notifyListeners();
      return;
    }
    _p = p;
    try {
      _subs.add(p.onOpened.listen(_opened));
      _subs.add(p.onForeground.listen((m) => unawaited(_foreground(m))));
      _subs.add(p.onTokenRefresh.listen((t) {
        _token = t;
        unawaited(register());
      }));
      final first = await p.initialMessage();
      if (first != null) _opened(first);
    } catch (_) {}
    /* 로그인하지 않았으면 자동 초기화를 끈 채로 둡니다. 설정 파일에서 꺼 두었지만, 지난
       실행이 켠 채로(로그아웃 전에) 끝났으면 그 값이 남아 있습니다. */
    if (!(_api?.signedIn ?? false)) {
      try {
        await p.setAutoInit(false);
      } catch (_) {}
    }
    _initDone = true;
    notifyListeners();
    await register();
  }

  /// 서버 주소가 바뀌어 Api 를 새로 만들었을 때(main.dart _setServer). 새 서버에 다시 등록합니다.
  ///
  /// 옛 서버에는 이 기기를 빼 달라고 말하고(4초만 기다림), 토큰도 폐기해서 새 토큰으로 새 서버에만
  /// 등록합니다. 옛 서버의 세션은 90일짜리라 그대로 두면 그 서버가 옛 계정의 독촉 · 친구 소식을
  /// 이 폰으로 계속 보내는데, 앱은 그 서버와 더는 말하지 않으므로 사람이 끌 방법이 없습니다.
  /// 옛 서버가 꺼져 있어 말이 못 닿아도, 토큰이 죽었으니 그 서버는 다음에 보낼 때
  /// UNREGISTERED 를 받고 행을 지웁니다.
  void attach(Api api) {
    if (identical(api, _api)) return;
    final old = _api;
    final oldSupports = _serverSupports;
    _bind(api);
    _sentKey = null;
    _serverSupports = null;
    _serverFcm = null;
    notifyListeners();
    if (old != null && old.baseUrl != api.baseUrl) {
      /* 줄을 서서 합니다 — 옛 서버로 가던 등록이 아직 돌고 있으면 그게 끝난 뒤의 토큰을 봐야
         합니다. 새 서버 등록은 이 뒤에 줄을 섭니다. */
      unawaited(_serial(() async {
        final p = _p;
        final t = _token;
        if (p == null || t == null) return;
        if (old.signedIn && oldSupports != false) {
          try {
            await old.removePushDevice(t).timeout(const Duration(seconds: 4));
          } catch (_) {}
        }
        _token = null;
        try {
          await p.deleteToken();
        } catch (_) {}
      }));
    }
    unawaited(register());
  }

  void _bind(Api api) {
    _api?.removeListener(_onApi);
    _api = api;
    _session = api.signedIn ? api.token : null;
    api.addListener(_onApi);
  }

  void _onApi() {
    final api = _api;
    if (api == null) return;
    final now = api.signedIn ? api.token : null;
    if (now == _session) return;
    final was = _session;
    _session = now;
    _sentKey = null;
    if (now != null) {
      unawaited(register());
    } else if (was != null) {
      _serverFcm = null;
      notifyListeners();
      unawaited(_forgetToken());
    }
  }

  /* 로그아웃하면 이 기기의 FCM 토큰을 폐기합니다. 로그아웃 요청이 서버에 못 닿았으면
     서버에는 옛 로그인과 기기 행이 남아 있을 수 있는데, 토큰이 죽으면 서버가 다음에 보낼 때
     UNREGISTERED 를 받고 행을 지웁니다 — 로그아웃한 폰에 친구 소식이 가지 않게.
     다음 로그인에서는 새 토큰으로 등록합니다. */
  Future<void> _forgetToken() => _serial(() async {
        final p = _p;
        if (p == null) return;
        _token = null;
        /* 자동 초기화를 먼저 끕니다 — 켜진 채로 폐기하면 Firebase 가 곧바로 새 토큰을 만들어
           로그인하지 않은 기기가 다시 구글에 등록됩니다. */
        try {
          await p.setAutoInit(false);
        } catch (_) {}
        try {
          await p.deleteToken();
        } catch (_) {}
      });

  /// 로그아웃 직전(아직 로그인이 살아 있을 때) — 서버에서 이 기기를 뺍니다.
  /// 서버가 세션과 같이 지우지만, 로그아웃 요청이 실패해도 이 기기로는 안 가게 먼저 말합니다.
  /// 서버가 꺼져 있으면 로그아웃을 오래 붙잡지 않게 4초만 기다립니다.
  Future<void> beforeSignOut(Api api) async {
    final t = _token;
    if (_p == null || t == null || !api.signedIn || _serverSupports == false) return;
    try {
      await api.removePushDevice(t).timeout(const Duration(seconds: 4));
    } catch (_) {}
    _sentKey = null;
  }

  /// 로그인돼 있으면 권한 · 토큰을 확인하고 서버에 등록합니다. 같은 것은 두 번 안 보냅니다.
  Future<void> register({bool force = false}) => _serial(() => _register(force));

  Future<void> _register(bool force) async {
    final p = _p;
    final api = _api;
    if (p == null || api == null || !api.signedIn) return;

    var ask = false;
    SharedPreferences? sp;
    if (p.asksPermission) {
      try {
        sp = await SharedPreferences.getInstance();
        ask = sp.getBool(kPushAskedKey) != true;
      } catch (_) {}
    }
    try {
      _perm = await p.permission(ask: ask);
    } catch (_) {
      _perm = PushPermission.unknown;
    }
    if (ask) {
      try {
        await sp?.setBool(kPushAskedKey, true);
      } catch (_) {}
    }

    /* 로그인한 뒤에만 구글에 기기를 등록합니다(설정 파일에서는 꺼 둠). */
    try {
      await p.setAutoInit(true);
    } catch (_) {}
    final t = _token ?? await p.token();
    if (t == null || t.isEmpty) {
      notifyListeners();
      return;
    }
    _token = t;
    /* 로그인 · 서버 · 토큰 · 권한 중 하나라도 바뀌면 다시 보냅니다. 권한이 들어 있는 까닭:
       폰 설정에서 알림을 끄면 서버가 그 사람에게 크롬 알림을 다시 보내야 합니다. */
    final key = '${api.baseUrl}|${api.token}|$t|${_perm.name}';
    if (!force && key == _sentKey) return;
    String? version;
    try {
      version = await _appVersion();
    } catch (_) {}
    final secret = await _installSecret(api.baseUrl);
    final r = await api.registerPushDevice(
      token: t,
      platform: p.platform,
      appVersion: version,
      secret: secret,
      permission: switch (_perm) {
        PushPermission.granted => 'granted',
        PushPermission.denied => 'denied',
        PushPermission.unknown => null,
      },
    );
    /* 기다리는 사이에 로그아웃 · 다른 계정 로그인이 있었으면 이 결과는 버립니다. */
    if (!identical(api, _api) || key != '${api.baseUrl}|${api.token}|$t|${_perm.name}') return;
    if (r.status == 404) {
      _serverSupports = false;
    } else if (r.ok) {
      _serverSupports = true;
      _serverFcm = r.body['fcm'] == true;
      _sentKey = key;
      _registeredAt = _now();
    }
    notifyListeners();
  }

  /// 이 서버에 보낼 설치 비밀. 처음이면 만들어 둡니다(32바이트 난수). 못 만들면 null — 그때는
  /// 비밀 없이 등록하고, 서버는 다른 계정의 살아 있는 등록을 옮기지 않을 뿐입니다.
  Future<String?> _installSecret(String baseUrl) async {
    try {
      final sp = await SharedPreferences.getInstance();
      final k = '$kPushSecretKey|$baseUrl';
      var v = sp.getString(k);
      if (v == null || v.length < 32) {
        final r = Random.secure();
        v = base64Url.encode(List<int>.generate(32, (_) => r.nextInt(256))).replaceAll('=', '');
        await sp.setString(k, v);
      }
      return v;
    } catch (_) {
      return null;
    }
  }

  /// 앱이 돌아왔을 때. 폰 설정에서 알림을 켜고 끄고 왔을 수 있어 권한을 다시 보고,
  /// 12시간이 지났으면 등록을 새로 합니다 — 서버는 30일 넘게 안 쓴 기기 대신 크롬으로 보냅니다.
  Future<void> resumed() async {
    if (_p == null || !(_api?.signedIn ?? false)) return;
    /* 이 길을 모르는 옛 서버에 돌아올 때마다 404 를 받으러 가지 않습니다 — 다음에 켤 때 다시 봅니다. */
    if (_serverSupports == false) return;
    final at = _registeredAt;
    final stale = at == null || _now().difference(at) > const Duration(hours: 12);
    await register(force: stale);
  }

  void _opened(PushMessage m) {
    /* 사람이 이미 본 독촉입니다 — 돌아와서 가져올 때 또 띄우지 않게 번호를 잡아 둡니다. */
    claimPoke(m.data['pokeId']);
    final r = m.route;
    if (r != null) _onOpen?.call(r);
  }

  Future<void> _foreground(PushMessage m) async {
    final p = _p;
    if (p == null) return;
    /* 로그아웃한 뒤에 늦게 온 것은 띄우지 않습니다 — 그 계정의 친구 소식입니다. */
    if (!(_api?.signedIn ?? false)) return;
    final route = m.route;
    final title = m.title ?? '';
    /* 가져오기가 먼저 띄운 독촉이면 또 띄우지 않습니다. 아이폰은 시스템이 띄우지만 번호는 잡아
       둡니다 — 뒤이은 가져오기가 같은 독촉을 또 띄우지 않게. */
    final fresh = claimPoke(m.data['pokeId']);
    if (!p.systemShowsForeground && title.isNotEmpty && fresh) {
      /* 서버가 준 tag 가 있으면 FCM 이 뒤에서 띄웠을 칸(tag, 번호 0)과 같은 칸에 띄웁니다. */
      final tag = '${m.data['tag'] ?? ''}';
      try {
        await p.showLocal(
          id: tag.isNotEmpty ? 0 : kPushIdBase + ((m.id ?? '$title${m.body}').hashCode & 0x7fffffff) % 1000,
          title: title,
          body: m.body ?? '',
          payload: route,
          tag: tag.isNotEmpty ? tag : null,
        );
      } catch (_) {}
    }
    try {
      await _onMessage?.call(m, route);
    } catch (_) {}
  }

  @override
  void dispose() {
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    _api?.removeListener(_onApi);
    super.dispose();
  }
}

/// 설정 화면 「푸시 알림」 한 줄.
enum PushLine { on, off, serverOff }

/// [status] 는 GET /push/status 의 결과(없으면 null). 서버가 모르면(404) 「서버 미지원」,
/// 이 기기가 못 받으면 「꺼짐」, 둘 다 되면 「켜짐」.
({PushLine line, String label, String hint}) describePush(NativePush p, {ApiResult? status}) {
  const fallback = '친구 독촉은 앱을 켜거나 돌아올 때 가져옵니다';
  if (status?.status == 404 || p.serverSupports == false) {
    return (line: PushLine.serverOff, label: '서버 미지원', hint: '서버가 아직 앱 알림을 모릅니다 — $fallback');
  }
  if (p.starting) {
    return (line: PushLine.off, label: '확인 중', hint: fallback);
  }
  if (!p.available) {
    return (line: PushLine.off, label: '꺼짐', hint: '이 판은 앱 알림을 받지 못합니다 — $fallback');
  }
  if (p.permission == PushPermission.denied) {
    return (line: PushLine.off, label: '꺼짐', hint: '폰 설정에서 Mybody 알림을 켜면 친구 독촉이 바로 옵니다');
  }
  final serverFcm = (status != null && status.ok && status.body['fcm'] is bool)
      ? status.body['fcm'] == true
      : p.serverFcm;
  if (serverFcm == false) {
    return (line: PushLine.serverOff, label: '서버 미지원', hint: '서버에서 앱 알림이 아직 켜지지 않았습니다 — $fallback');
  }
  if (p.registered) {
    return (line: PushLine.on, label: '켜짐', hint: '친구의 운동 독촉 · 소식이 앱으로 바로 옵니다');
  }
  if (p.token == null) {
    return (line: PushLine.off, label: '꺼짐', hint: '이 기기의 알림 주소를 아직 못 받았습니다 — $fallback');
  }
  return (line: PushLine.off, label: '꺼짐', hint: '서버에 아직 등록하지 못했습니다 — 다음에 앱을 켤 때 다시 합니다');
}

/// 로그아웃 직전에 이 기기의 알림 등록을 서버에서 지우는 Api.
///
/// 로그아웃 버튼이 여러 화면에 있어서(설정 · 계정 · 동의 거절 · 전부 지우기 · 계정 지우기)
/// 한 곳에서 잡습니다. main.dart 가 Api 를 이것으로 만듭니다.
class PushAwareApi extends Api {
  PushAwareApi({required super.baseUrl, super.client, NativePush? push}) : _push = push;

  final NativePush? _push;
  NativePush get push => _push ?? NativePush.instance;

  @override
  Future<void> signOut() async {
    try {
      await push.beforeSignOut(this);
    } catch (_) {/* 못 지워도 로그아웃은 됩니다 — 서버가 세션과 같이 지웁니다 */}
    await super.signOut();
  }
}
