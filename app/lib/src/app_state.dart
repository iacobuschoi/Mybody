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
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:mybody_core/mybody_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mybody_core/news.dart';

import 'estimate.dart';
import 'estimate_upgrade.dart';
import 'local_owner.dart';
import 'news_store.dart';
import 'photos.dart';
import 'pokes.dart';

/// 기록 칸의 JSON 맨 끝에 같이 적는 주인 서명의 자리(3차 검토 N9 — [PrefsStorage]).
const String kStateOwnerField = '_owner';
const String _ownerTail = ',"$kStateOwnerField":';

/// 코어가 적은 기록 JSON([json]) 끝에 주인 서명([owner] — null 이면 주인 없음 {})을 붙인 글자.
/// JSON 객체 모양이 아니면(깨진 원본을 옆으로 치우는 쓰기 등) 그대로.
String withOwnerStamp(String json, LocalOwner? owner) {
  if (json.length < 3 || !json.startsWith('{') || !json.endsWith('}')) return json;
  return '${json.substring(0, json.length - 1)}$_ownerTail${jsonEncode(owner?.toJson() ?? const {})}}';
}

/// SharedPreferences 한 칸을 코어의 저장소로 씁니다.
///
/// 코어의 write 는 **동기**입니다(원본 localStorage 가 그랬고, 저장 실패를
/// 그 자리에서 알아야 하기 때문입니다). SharedPreferences 는 비동기라
/// 마지막 값을 들고 있다가 뒤에서 씁니다. 쓰기가 실패하면 그 사실을
/// 남겨서 다음 저장이 false 를 돌려주게 합니다 — 못 쓴 것을 썼다고
/// 말하지 않습니다.
///
/// **적을 때마다 그때의 주인 서명을 기록 끝에 같이 붙입니다**(3차 검토 N9). 웹에서는 같은
/// localStorage 를 보는 탭이 여럿일 수 있고, 한 탭이 계정을 바꿔도(A → B — 주인 칸 'mybody.owner.v1'
/// 은 B) 다른 탭은 A 의 기록을 메모리에 든 채 이 칸에 적습니다. 주인 칸과 기록 칸은 따로 적히니
/// 어긋나고, 다시 켜면 A 의 기록이 B 의 것으로 읽혔습니다. 서명은 기록과 **한 번의 쓰기**로 적혀
/// 어긋날 수 없습니다 — 켤 때 주인 칸과 견줍니다(local_owner.dart AccountSlots._reconcile). 서명은 읽을
/// 때 떼어 내 코어의 기록에는 들어가지 않습니다(내보내기 · 동기화에 안 실림). 붙이는 자리는 JSON 의
/// 맨 끝 한 칸이라 붙이고 떼는 데 기록 전체를 다시 풀지 않습니다. 모바일 앱에는 두 탭이 없지만 같은
/// 길을 탑니다(몇십 글자 더 적을 뿐). 옛 판(0.2.19)이 이 칸을 읽으면 모르는 칸 하나가 더 있을 뿐입니다.
class PrefsStorage implements StateStorage {
  PrefsStorage(this._prefs, {this.key = storeKey}) {
    _cache = _unstamp(_prefs.getString(key));
  }

  final SharedPreferences _prefs;
  final String key;
  String? _cache;
  bool _lastWriteFailed = false;

  /// 켤 때 기록 칸에 붙어 있던 주인 서명(JSON) — 없으면 null. [OwnerBook] 이 받습니다.
  Object? stampedOwner;

  /// 지금 활성 칸의 주인 — 적을 때마다 이것을 붙입니다. 꽂기 전(null)에는 안 붙입니다.
  LocalOwner? Function()? ownerOf;

  String? _unstamp(String? raw) {
    if (raw == null || !raw.endsWith('}')) return raw;
    final i = raw.lastIndexOf(_ownerTail);
    if (i <= 0) return raw;
    try {
      /* 우리가 붙인 것은 맨 끝의 한 칸뿐이라, 그 뒤가 JSON 하나로 읽히지 않으면(안쪽 칸의 같은 이름 등)
         서명이 아닙니다 — 그대로 둡니다. */
      stampedOwner = jsonDecode(raw.substring(i + _ownerTail.length, raw.length - 1));
      return '${raw.substring(0, i)}}';
    } catch (_) {
      return raw;
    }
  }

  String _stamped(String value) {
    final of = ownerOf;
    return of == null ? value : withOwnerStamp(value, of());
  }

  @override
  String? read() => _cache;

  @override
  bool write(String value) {
    if (_lastWriteFailed) return false;
    _cache = value;
    _put(_stamped(value));
    return true;
  }

  /// 주인이 바뀌었을 때 — 기록은 그대로 두고 서명만 새 주인으로 다시 적습니다(OwnerBook.onChanged).
  /// 이 쓰기가 실패해도 '마지막 쓰기 실패' 로 적지 않습니다(4차 검토): 기록은 이미 적혀 있고 서명만 옛
  /// 것으로 남습니다 — 서명은 켤 때 다른 **계정 id** 를 말할 때만 쓰이는데, 계정이 바뀌는 칸 바꾸기는
  /// 서명을 기록과 같이 적고 기다리며(local_owner.dart _activate) 못 적으면 멈춥니다. 여기서 실패를
  /// 적으면 다음 저장부터 모두 거짓이 되고, 코어는 자리를 만든다며 결과지 사진을 하나씩 지웁니다.
  void restamp() {
    final v = _cache;
    if (v == null || _lastWriteFailed) return;
    _put(_stamped(v), mark: false);
  }

  void _put(String raw, {bool mark = true}) {
    () async {
      try {
        if (!await _prefs.setString(key, raw) && mark) _lastWriteFailed = true;
      } catch (_) {
        if (mark) _lastWriteFailed = true;
      }
    }();
  }

  /// 마지막 쓰기가 실제로 기기에 닿았는지 확인합니다 (화면이 물어볼 때).
  bool get healthy => !_lastWriteFailed;
}

/// 앱 한 벌의 상태. 화면들은 이걸 듣습니다.
class AppState extends ChangeNotifier {
  AppState._(this.store, this.news, this.pokes, this.owner) : schedule = Schedule(store) {
    _blankSeen = isBlankState(store.get());
    /* 듣는 쪽 가운데 맨 먼저 적습니다 — 같은 알림의 다른 쪽(동기화 등)은 이번 저장까지 넣은 답을
       봅니다. 알리기 전(저장 안에서 주간 요약을 올릴 때)에는 그 전 저장의 답입니다([wasBlank]). */
    store.onChange((st) => _blankSeen = isBlankState(st));
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
    /* 사진 파일은 계정마다의 기록 칸이 한 폴더를 같이 씁니다 — 치워 둔 칸이 가리키는 사진은 이 칸에서
       측정을 지워도 남깁니다(local_owner.dart). */
    if (sp != null) {
      final prefs = sp;
      store.photoKeptElsewhere = (id) => parkedPhotoIds(prefs).contains(id);
    }
    final pokes = sp == null ? null : PokeBox(sp);
    /* 기록 칸에 같이 적힌 주인 서명(웹의 두 탭 — PrefsStorage 머리 주석)을 주인 장부에 넘기고, 주인이
       바뀌면 서명을 다시 적게 잇습니다. */
    final book = OwnerBook(sp, stamped: storage is PrefsStorage ? storage.stampedOwner : null);
    if (storage is PrefsStorage) {
      storage.ownerOf = () => book.current;
      book.onChanged = storage.restamp;
    }
    final app = AppState._(store, news, pokes, book);
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

  /// 이 기기의 기록(활성 칸)이 누구 것인지 — local_owner.dart.
  final OwnerBook owner;

  bool _blankSeen = true;

  /// 마지막으로 알린 때(이번 저장 전) 기록 칸이 비어 있었나. 로그인한 채 빈 칸에 새로 쓰기 시작한
  /// 것은 그 로그인의 기록입니다(local_owner.dart mayLeave) — 저장은 친구에게 올리는 것
  /// (publishWeekly)을 알리기 전에 하므로, 여기는 그 저장 전의 답입니다.
  bool get wasBlank => _blankSeen;

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
