/* 소식을 이 기기에 담는 그릇. 계산은 코어(news.dart)가 합니다. */
import 'package:mybody_core/news.dart';

import 'sync_queue.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PrefsNews implements NewsStorage {
  PrefsNews(this._sp);
  final SharedPreferences _sp;
  /// 웹 앱과 **같은 이름**을 씁니다 — 같은 기기에서 둘을 오가도 소식이
  /// 두 벌로 갈라지지 않습니다.
  static const _key = 'mybody.news.v1';

  @override
  String? read() {
    try { return _sp.getString(_key); } catch (_) { return null; }
  }

  @override
  void write(String raw) {
    try { _sp.setString(_key, raw); } catch (_) {}
  }

  @override
  void clear() {
    try { _sp.remove(_key); } catch (_) {}
  }
}


/// 오프라인 큐를 담는 그릇.
class PrefsQueue implements QueueStorage {
  PrefsQueue(this._sp);
  final SharedPreferences _sp;
  static const _key = 'mybody.sync.queue.v1';

  @override
  String? read() {
    try { return _sp.getString(_key); } catch (_) { return null; }
  }

  @override
  void write(String raw) {
    try { _sp.setString(_key, raw); } catch (_) {}
  }
}
