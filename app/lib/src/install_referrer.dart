/* =============================================================================
 * install_referrer.dart — 앱이 없던 친구가 초대 링크로 깔았을 때(안드로이드)
 *
 * 주인 의견 45: "친추 링크 보내면 링크만 누르면 바로 친추되게해 / 앱이 안깔려있으면 스토어로
 * 이어지게하고 / … / 모든걸 자동으로 해야해".
 *
 * 앱이 있으면 링크가 앱을 열고 코드가 따라옵니다(invite_link.dart). 앱이 **없으면** 링크의
 * 페이지(서버의 /i/<코드>)가 스토어로 보내는데, 스토어를 거치면 코드가 끊깁니다 — 깔고 처음
 * 연 앱은 누가 불렀는지 모릅니다. 그래서 페이지는 플레이 주소에 코드를 실어 보냅니다:
 *
 *   https://play.google.com/store/apps/details?id=<앱>&referrer=invite%3D<코드>
 *
 * 플레이는 이 referrer 를 깔린 앱에게 한 번 건네줍니다(Play Install Referrer — 설치 뒤 90일).
 * 앱은 **처음 켤 때 한 번** 그것을 묻고, 「invite=<코드>」 가 있으면 링크로 받은 것과 똑같이
 * 쥡니다(InviteInbox) — 묻지 않고 곧바로. 로그인 · 첫 설정을 마치고 탭 화면이 서면 셸이
 * 보냅니다 — 링크와 같이 via:'link' 로, 그래서 곧바로 친구입니다(주인 의견 48). 친구는 링크 하나
 * 누르고 깔고 가입했을 뿐인데 초대한 사람과 친구가 돼 있습니다.
 *
 * 한 번만 묻는 까닭
 *   referrer 는 설치에 붙은 값이라 앱을 켤 때마다 같은 것이 옵니다. 매번 받으면 보낸 요청이
 *   또 가고(「이미 요청을 보냈어요」), 7일이 지난 뒤에 불쑥 가기도 합니다. 그래서 답을 한 번
 *   받으면 이 기기에 「끝」 을 적습니다([kInstallReferrerKey]). 못 물었으면(플레이 서비스가
 *   잠깐 안 닿음 · 5초 안에 답이 없음) 다음에 켤 때 다시 — 세 번까지만.
 *   이미 쓰던 사람도 이 판으로 올린 뒤 한 번 묻습니다. 옛 판을 초대 링크로 깐 사람이면 그
 *   요청이 이제라도 갑니다 — 원래 갔어야 할 요청입니다.
 *
 * 아이폰 · 시험에서는 아무것도 안 합니다
 *   플레이 서비스는 안드로이드에만 있고(플러그인은 아이폰에서 던집니다), 시험 안에는 플랫폼
 *   채널이 없습니다. 그래서 묻는 길은 바꿔 끼울 수 있게 두고([InstallReferrerRead]), 진짜
 *   길([playInstallReferrer])은 main.dart 가 안드로이드에서만 넘깁니다(InviteInbox.platform).
 *   아이폰은 스토어가 이런 값을 넘겨주지 않아서, 페이지가 설치 단추를 누를 때 초대 글을
 *   클립보드에 넣어 두고 앱의 「초대 코드 붙여넣기」 가 그것을 받습니다(social.dart).
 * ========================================================================== */
import 'dart:async';

import 'package:android_play_install_referrer/android_play_install_referrer.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/social.dart' show isInviteCode;

/// 설치 referrer 를 묻는 길. 없으면(organic 설치 등) null. 못 물으면 던집니다.
typedef InstallReferrerRead = Future<String?> Function();

/// 물어본 적이 있나 — 'done'(답을 받음) 또는 못 물은 횟수(정수).
const String kInstallReferrerKey = 'mybody.invite.referrer.v1';

/// 못 물었을 때 다시 묻는 횟수(켤 때마다 한 번).
const int kInstallReferrerTries = 3;

/// 플레이 서비스의 답을 기다리는 시간. 넘으면 못 물은 것으로 칩니다.
const Duration kInstallReferrerTimeout = Duration(seconds: 5);

/// 진짜 길 — android_play_install_referrer. 안드로이드가 아니면 묻지 않고 null.
Future<String?> playInstallReferrer() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
  final d = await AndroidPlayInstallReferrer.installReferrer;
  return d.installReferrer;
}

/// referrer 글(「invite=K7M2QX9D」 · 「utm_source=…&invite=…」)에서 초대 코드를 꺼냅니다(대문자).
///
/// 플레이는 페이지가 보낸 referrer=invite%3D<코드> 를 한 번 풀어 「invite=<코드>」 로 줍니다.
/// 한 번 더 싸인 채로(「invite%3D…」) 오는 일도 있어 그때는 한 번 더 풀어 봅니다. 모양이
/// 틀린 코드는 null — 모르는 값으로 요청을 보내지 않습니다.
String? inviteCodeFromReferrer(String? referrer) {
  if (referrer == null) return null;
  var s = referrer.trim();
  for (var i = 0; i < 2 && s.isNotEmpty; i++) {
    Map<String, String> q;
    try {
      q = Uri.splitQueryString(s);
    } catch (_) {
      return null;   // 풀 수 없는 % 등
    }
    final v = q['invite'];
    if (v != null) {
      final code = v.trim().toUpperCase();
      return isInviteCode(code) ? code : null;
    }
    String d;
    try {
      d = Uri.decodeComponent(s);
    } catch (_) {
      return null;
    }
    if (d == s) return null;
    s = d.trim();
  }
  return null;
}

/// 처음 켤 때 한 번 — 설치 referrer 에 초대 코드가 있으면 그 코드, 없거나 이미 물었으면 null.
///
/// 답을 받으면(코드가 없어도) 「끝」 을 적어 다시 묻지 않습니다. 못 물었으면 횟수만 적고
/// null — [kInstallReferrerTries] 번까지 켤 때마다 다시 묻습니다. 던지지 않습니다.
Future<String?> installReferrerInviteOnce(InstallReferrerRead read) async {
  SharedPreferences sp;
  try {
    sp = await SharedPreferences.getInstance();
  } catch (_) {
    return null;   // 적어 둘 곳이 없으면 묻지 않습니다 — 켤 때마다 묻게 됩니다
  }
  final v = sp.get(kInstallReferrerKey);
  if (v == 'done') return null;
  final tries = v is int ? v : 0;
  if (tries >= kInstallReferrerTries) return null;
  String? referrer;
  try {
    referrer = await read().timeout(kInstallReferrerTimeout);
  } catch (_) {
    try {
      await sp.setInt(kInstallReferrerKey, tries + 1);
    } catch (_) {}
    return null;
  }
  try {
    await sp.setString(kInstallReferrerKey, 'done');
  } catch (_) {}
  return inviteCodeFromReferrer(referrer);
}
