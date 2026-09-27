/* =============================================================================
 * app_state.dart — 코어(mybody_core)를 Flutter 에 꽂는 자리
 *
 * 코어는 기기를 모릅니다. localStorage 도 파일도 네트워크도 모르고, 시계도
 * 꽂아 넣게 돼 있습니다. 일부러 그렇게 만들었습니다 — 그래야 차이 검사가
 * 원본 자바스크립트와 **같은 입력으로** 돌려 볼 수 있습니다.
 *
 * 그 대신 어딘가에서는 진짜 기기에 연결해야 하고, 그게 이 파일입니다.
 *
 * 저장은 SharedPreferences 한 칸에 JSON 통째로 넣습니다. 웹 앱이
 * localStorage 에 하던 것과 **글자 그대로 같은 모양**이라, 백업 파일이
 * 두 앱 사이를 오갈 수 있습니다. 칸을 쪼개서 넣으면 빨라 보이지만
 * 백업 호환이 깨집니다 — 그건 사용자의 유일본을 다루는 문제입니다.
 * ========================================================================== */
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mybody_core/mybody_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mybody_core/news.dart';

import 'estimate.dart';
import 'estimate_upgrade.dart';
import 'news_store.dart';
import 'photos.dart';
import 'pokes.dart';

/// SharedPreferences 한 칸을 코어의 저장소로 씁니다.
///
/// 코어의 write 는 **동기**입니다(원본 localStorage 가 그랬고, 저장 실패를
/// 그 자리에서 알아야 하기 때문입니다). SharedPreferences 는 비동기라
/// 마지막 값을 들고 있다가 뒤에서 씁니다. 쓰기가 실패하면 그 사실을
/// 남겨서 다음 저장이 false 를 돌려주게 합니다 — 못 쓴 것을 썼다고
/// 말하지 않습니다.
class PrefsStorage implements StateStorage {
  PrefsStorage(this._prefs, {this.key = storeKey}) {
    _cache = _prefs.getString(key);
  }

  final SharedPreferences _prefs;
  final String key;
  String? _cache;
  bool _lastWriteFailed = false;

  @override
  String? read() => _cache;

  @override
  bool write(String value) {
    if (_lastWriteFailed) return false;
    _cache = value;
    () async {
      try {
        if (!await _prefs.setString(key, value)) _lastWriteFailed = true;
      } catch (_) {
        _lastWriteFailed = true;
      }
    }();
    return true;
  }

  /// 마지막 쓰기가 실제로 기기에 닿았는지 확인합니다 (화면이 물어볼 때).
  bool get healthy => !_lastWriteFailed;
}

/// 앱 한 벌의 상태. 화면들은 이걸 듣습니다.
class AppState extends ChangeNotifier {
  AppState._(this.store, this.news, this.pokes) : schedule = Schedule(store) {
    store.onChange((_) => notifyListeners());
    /* 엔진이 modes 를 느슨하게 부르는 고리를 여기서 꽂습니다 —
       원본이 `global.MB_MODES` 가 있으면 쓰던 자리입니다. */
    engineModeLookup = modeById;
    engineNoise = kNoise;
    store.weekSummaryOf = (ws) => schedule.weekSummary(ws);
    store.streaksOf = () => {
      'workoutDays': schedule.workoutStreak()['days'],
      'foodDays': schedule.foodStreak()['days'],
    };
    /* 실측이 들어왔는데 추정이 남아 있으면 정리합니다(estimate_upgrade.dart).
       검수 화면은 저장하자마자 직접 부르지만, 다른 기기 · 옛 판 기기에서 동기화로
       들어온 실측이나 백업 가져오기는 그 화면을 안 거칩니다 — 저장소의 바뀜을 듣는
       이 자리가 그 길을 다 받습니다. */
    store.onChange((_) => _upgradeSoon());
  }

  /* 저장소가 아직 듣는 쪽들에게 알리는 중에 또 저장하면 알림이 겹칩니다. 마이크로태스크로
     한 박자 미뤄서, 지금 저장이 끝난 뒤에 정리합니다(동기화 가져오기도 그 사이에
     _importing 을 내려서, 이 정리가 "이 기기가 바꾼 것" 으로 찍혀 올라갑니다).
     이미 줄 서 있으면 또 세우지 않습니다. 줄 표시는 정리가 **끝난 뒤에** 내립니다 —
     정리 자신의 저장이 또 줄을 세우면, 정리가 중간에 던지는 경우 저장 → 줄 → 던짐 →
     저장 … 으로 마이크로태스크가 끝없이 돌 수 있습니다. */
  bool _upgradeQueued = false;
  void _upgradeSoon() {
    if (_upgradeQueued || !needsEstimateUpgrade(store.get())) return;
    _upgradeQueued = true;
    scheduleMicrotask(() {
      /* 다른 기기에서 온 이상한 모양 하나 때문에 앱이 멈추면 안 됩니다 — 못 하면
         다음 저장 때 다시 해 봅니다. */
      try {
        upgradeEstimates(store);
      } catch (_) {
      } finally {
        _upgradeQueued = false;
      }
    });
  }

  static Future<AppState> boot() async {
    SharedPreferences? sp;
    try {
      sp = await SharedPreferences.getInstance();
    } catch (_) {/* 저장소가 없으면 메모리로 돕니다 — 앱이 멈추지는 않습니다 */}
    final storage = sp == null ? MemoryStorage() : PrefsStorage(sp);
    final store = Store(storage: storage);

    /* 친구 소식. 저장소가 없으면 소식만 조용히 꺼집니다. */
    final news = sp == null ? null : News(PrefsNews(sp));
    store.newsReset = () => news?.reset();

    store.load();
    final pokes = sp == null ? null : PokeBox(sp);
    final app = AppState._(store, news, pokes);
    /* 섞인 상태(실측 + 추정)로 저장된 채 앱이 꺼졌으면 켜자마자 한 번 정리합니다. */
    app._upgradeSoon();

    /* 사진 보관소는 **기다리지 않습니다.**
     *
     * 폴더 위치는 플랫폼 플러그인이 알려 주는데, 그게 대답을 안 하면 그
     * await 는 영영 안 끝납니다. 실제로 그랬습니다 — 화면 시험(플러그인이
     * 없는 환경)이 첫 번째 화면도 못 세우고 그 자리에서 멈췄습니다.
     * `timeout` 도 소용없습니다. 시험은 시계를 멈춰 놓고 돌기 때문입니다.
     *
     * 사진 하나 못 붙이는 것 때문에 앱이 켜지는 화면에 서 있으면 안 되니,
     * 먼저 돌고 열리면 그때 끼웁니다. 폰에서는 첫 화면이 그려지기 전에
     * 끝나는 일입니다. 못 열면 사진 없이 갑니다 — 숫자 세 개로 쓰는 0층은
     * 그대로입니다. */
    unawaited(app._openPhotos());
    return app;
  }

  Future<void> _openPhotos() async {
    try {
      final p = await FilePhotos.open();
      photos = p;
      store.photos = p;
      notifyListeners();
    } catch (_) {}
  }

  /// 결과지 사진 보관소. 아직 안 열렸거나 못 열었으면 null 입니다.
  FilePhotos? photos;

  /// 친구 소식. 저장소가 없으면 null 입니다.
  final News? news;

  /// 친구가 보낸 운동 독촉. 저장소가 없으면 null 입니다.
  final PokeBox? pokes;

  final Store store;
  final Schedule schedule;

  Map<String, Object?> get state => store.get();
  bool get onboarded => state['onboarded'] == true;
  Map<String, Object?>? get profile =>
      state['profile'] == null ? null : (state['profile'] as Map).cast<String, Object?>();

  /// 읽기 실패를 화면이 **한 번** 물어봅니다.
  Map<String, Object?>? takeLoadProblem() => store.takeLoadProblem();

  void save() => store.save();
}
