/* =============================================================================
 * pokes.dart — 운동 독촉: 친구가 "오늘 운동 어때요" 하고 콕 찌른 것
 *
 * 받는 쪽은 서버에서 **가져갑니다** — 앱을 켤 때, 앱으로 돌아올 때([PokeResume]),
 * 그리고 앱 알림(FCM, native_push.dart)이 왔을 때. 친구 탭 맨 위의 띠로 보여 주고
 * 읽을 때까지 기기에 남습니다. 보내는 쪽은 하루 한 번만(서버가 막습니다).
 *
 * 폰 알림은 한 번만 — 서버가 앱 알림으로 이미 보낸 독촉은 `pushed` 가 참으로 오고,
 * 그때는 가져와도 알림을 또 띄우지 않습니다(main.dart). 앱 알림이 없는 빌드 ·
 * 옛 서버에서는 늘 거짓이라 예전처럼 가져올 때 하나 띄웁니다.
 * ========================================================================== */
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:mybody_core/mybody_core.dart' as core;
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';

/// 이 친구에게 독촉할 만한가 — 이번 주 기록이 없거나, 하기로 한 날을 다 못 지켰거나.
/// 공유를 안 한 친구(snap 없음)도 "안 했다" 는 뜻은 아니지만, 찔러 볼 수는 있습니다.
bool needsNudge(Map<String, dynamic>? snap) {
  if (snap == null || snap.isEmpty) return true;
  if (snap['checkedIn'] != true) return true;
  final planned = snap['plannedDays'];
  if (planned != null && core.jsToNumber(snap['keptDays'] ?? 0) < core.jsToNumber(planned)) return true;
  return false;
}

class PokeBox extends ChangeNotifier {
  PokeBox(this._sp) {
    try {
      final s = _sp.getString(_key);
      if (s != null) {
        _items = (jsonDecode(s) as List).map((x) => (x as Map).cast<String, dynamic>()).toList();
      }
    } catch (_) {}
  }
  final SharedPreferences _sp;
  static const _key = 'mybody.pokes.v1';
  static const _max = 30;

  List<Map<String, dynamic>> _items = [];

  /// 아직 안 치운 독촉들 — 최근 것이 위.
  List<Map<String, dynamic>> get items => List.unmodifiable(_items.reversed);
  int get unread => _items.length;

  Future<void> _save() async {
    try {
      await _sp.setString(_key, jsonEncode(_items));
    } catch (_) {}
  }

  /// 서버에서 새 독촉을 가져옵니다. 돌려주는 것은 **이번에 새로 온 것**.
  Future<List<Map<String, dynamic>>> fetch(Api api) async {
    if (!api.signedIn) return const [];
    final r = await api.pullPokes();
    if (!r.ok) return const [];
    final fresh = <Map<String, dynamic>>[];
    for (final p in ((r.body['pokes'] as List?) ?? const [])) {
      if (p is! Map) continue;
      final from = (p['from'] as Map?)?.cast<String, dynamic>() ?? const {};
      fresh.add({
        'id': p['id'], 'kind': p['kind'] ?? 'workout', 'at': p['at'],
        'fromId': from['id'], 'name': from['displayName'] ?? '친구',
        /* 서버가 앱 알림(FCM)으로 이미 보냈는가 — 그러면 폰 알림을 또 띄우지 않습니다. */
        'pushed': p['pushed'] == true,
      });
    }
    if (fresh.isEmpty) return fresh;
    _items.addAll(fresh);
    while (_items.length > _max) {
      _items.removeAt(0);
    }
    await _save();
    notifyListeners();
    return fresh;
  }

  Future<void> dismiss(Object? id) async {
    _items.removeWhere((x) => x['id'] == id);
    await _save();
    notifyListeners();
  }

  Future<void> dismissAll() async {
    _items.clear();
    await _save();
    notifyListeners();
  }

  static String title(Map<String, dynamic> p) => '${p['name']}님이 운동하라고 콕 찔렀어요';
  static String body(Map<String, dynamic> p) => '오늘 운동 어때요? 💪';
}

/// 앱으로 돌아올 때(resume) 독촉을 다시 가져옵니다.
///
/// 예전에는 켤 때만 가져와서, 앱을 뒤에 둔 채로 며칠을 쓰는 사람은 친구가 찌른 것을
/// 몰랐습니다. 앱 알림(FCM)이 없는 빌드 · 서버 · 알림을 거절한 폰에서는 이게 유일한 길입니다.
/// 알림 창을 잠깐 내렸다 올리는 것도 resume 이라, [minGap] 안에는 다시 묻지 않습니다.
class PokeResume {
  PokeResume(this.fetch, {this.minGap = const Duration(seconds: 30), DateTime Function()? now})
      : _now = now ?? DateTime.now;

  final Future<void> Function() fetch;
  final Duration minGap;
  final DateTime Function() _now;
  AppLifecycleListener? _life;
  DateTime? _last;

  void wire() {
    _life ??= AppLifecycleListener(onResume: () => unawaited(run()));
  }

  Future<void> run() async {
    final now = _now();
    final last = _last;
    if (last != null && now.difference(last) < minGap) return;
    _last = now;
    try {
      await fetch();
    } catch (_) {/* 못 가져오면 다음에 돌아올 때 */}
  }

  void dispose() {
    _life?.dispose();
    _life = null;
  }
}
