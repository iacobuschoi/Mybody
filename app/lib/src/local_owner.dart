/* =============================================================================
 * local_owner.dart — 이 기기의 기록이 **누구 것인지**, 계정이 바뀔 때 칸을 갈아 끼우기
 *
 * 피드백 52: 계정 A 로 쓰다 로그아웃하고 새 계정 B 로 가입하니, A 의 기록(9/19 86.7kg · D-81 ·
 * 상체 A)이 B 의 화면에 뜨고 B 의 서버 사본 · 주간 요약으로 올라갔습니다. 기록은
 * 'mybody.state.v1' 한 칸에 있었고, 그 칸에도 곁의 동기화 · 큐 칸에도 **주인 표시가 없었습니다.**
 * 로그아웃은 일부러 기록을 남겼고, 로그인 뒤의 첫 동기화는 "지금 이 기기 기록 = 방금 들어온
 * 계정의 기록" 으로 보고 합쳐 올렸습니다.
 *
 * 그래서:
 *   · 지금 화면이 쓰는 칸(활성 칸)에 주인을 적습니다 — 'mybody.owner.v1' = {server, uid, …}.
 *     Store 밖이라 내보내기 · 동기화에 안 실립니다.
 *   · 로그아웃하면 그 계정의 칸을 통째로 치워 둡니다 — 'mybody.slot.<서버>|<uid>.*' 에 기록 ·
 *     동기화 기준본 · 마지막으로 바꾼 시각 · 못 보낸 큐 작업 · 독촉 · 소식 · 초대 표시. 활성 칸은
 *     빈 기록(또는 로그인 없이 쓰던 기록)이 되고, 같은 계정으로 다시 로그인하면 돌아옵니다. 사진
 *     파일은 안 지웁니다 — 치워 둔 칸의 측정이 photoId 로 가리킵니다. 동기화를 꺼 둔 계정의
 *     칸도 똑같이 치워 두기만 합니다 — 그때는 이 기기가 유일본입니다.
 *   · 로그인 · 가입 · 복구는 **토큰을 알리기 전에** 칸을 바꿉니다(api.dart [AccountSwitch]) —
 *     알림을 듣는 쪽(주간 요약 · 동기화 · 독촉 · 셸)이 앞 계정의 칸을 한 번도 못 보게. 다른
 *     계정의 칸은 절대 합치지 않습니다. 주인 없는 기록(로그인 없이 쓴 것)만 합칠지 묻고, 고르기
 *     전에는 토큰이 없어 아무것도 안 나갑니다.
 *   · 보내는 쪽(동기화 · 주간 요약 · 큐)은 칸의 주인이 지금 로그인과 맞을 때만 보냅니다
 *     ([mayLeave]) — 칸을 못 바꾼 날이 있어도 다른 계정으로 새지 않게 두 번 잠급니다.
 *
 * 로그인 없이 쓰던 기록을 [합치지 않기] 하면 그것도 칸('mybody.slot.guest.*')으로 치워 두고,
 * 로그아웃하면 그 칸이 돌아옵니다 — 「로그인 없이 쓰기」 의 기록은 계정과 따로 삽니다. 같은
 * 계정에 같은 기록으로 다시 묻지는 않습니다(사람이 직접 고른 것만 적어 둠 — 창은 뒤로 가기로
 * 안 닫히고, 고르지 못하고 끝났으면 다음에 다시 묻습니다). 「계정 지우기」 뒤 남은 기록은 누구
 * 것이었는지 아는 기록이라 '모름' 으로 둡니다 — 다음 로그인은 경고와 함께 묻습니다.
 *
 * 칸 바꾸기는 기기 저장소에 여러 번 나눠 씁니다. 그 사이 앱이 죽거나 저장이 실패해도 새지 않고
 * 잃지 않게 차례를 정해 두었습니다([AccountSlots] 주석 · account_switch_crash_test.dart 가 모든
 * 멈춘 자리를 돌려 봅니다). 결과지 사진은 모든 칸이 한 폴더를 같이 써서, 치워 둔 칸이 가리키는
 * 사진은 다른 칸에서 측정을 지워도 남깁니다([parkedPhotoIds]).
 *
 * 0.2.19 에서 올라온 첫 실행([AccountSlots.migrate]): 로그인돼 있으면 주인 = 지금 로그인한 계정
 * (id 를 아직 모르면 그 로그인의 표시로 묶어 두고 /me 로 채웁니다). 로그인 없이 기록만 있으면
 * 주인 '모름' — 다음 로그인에서 「다른 계정의 기록일 수 있어요」 와 함께 묻고, 기본은
 * [합치지 않기]입니다. 기록이 비었으면 주인 없음. 이 기기에서 여러 계정이 로그인했었는지
 * 짐작(크롬 알림 표시 등)은 하지 않습니다 — 틀린 경고가 더 나쁩니다(주인이 정함).
 * ========================================================================== */
import 'dart:async';
import 'dart:convert';

import 'package:mybody_core/mybody_core.dart' as core;
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'app_state.dart';
import 'cloud.dart';
import 'invite_link.dart';
import 'merge.dart';
import 'screens/social.dart' show kMyInviteCodeKey;
import 'sync_queue.dart';

/// 활성 칸의 주인.
const String kOwnerKey = 'mybody.owner.v1';

/// 치워 둔 칸들의 앞머리 — 'mybody.slot.(칸).(조각)'. 칸은 '(서버)|(uid)' 또는 'guest'.
const String kSlotPrefix = 'mybody.slot.';

/// 로그인 없이 쓰던 기록의 칸.
const String kGuestSlot = 'guest';

/// 로그인 없이 쓰던 기록을 [합치지 않기] 한 계정들 — {칸: 그때 기록의 요약}. 같은 기록으로는
/// 그 계정에 다시 묻지 않습니다. 기기의 것이라 칸과 같이 옮기지 않습니다.
const String kGuestDeclinedKey = '${kSlotPrefix}guest-declined';

/// 칸과 함께 옮기는 기기 칸들 — 조각 이름 → 열쇠. 기록(state)과 큐는 메모리에도 있어 따로 옮깁니다.
/// 열쇠는 각 파일이 쓰는 이름 그대로입니다(cloud.dart · pokes.dart · news_store.dart ·
/// social.dart · invite_link.dart).
const Map<String, String> kSlotParts = {
  'cloud.at': CloudSync.keyAt,
  'cloud.base': CloudSync.keyBase,
  'cloud.last': CloudSync.keyLast,
  'pokes': 'mybody.pokes.v1',
  'news': 'mybody.news.v1',
  'invite.mine': kMyInviteCodeKey,
  'invite.handled': 'mybody.invite.handled.v1',
};

/// 서버 주소를 칸 이름에 쓰는 꼴로 — 끝의 / 를 뗍니다(cloud.dart 의 기준본과 같은 꼴).
String serverOf(Api api) => api.baseUrl.trim().replaceAll(RegExp(r'/+$'), '');

/// 기록이 비었나 — 온보딩 전이고 측정 · 식단이 없음. 동기화의 "막 깐 기기" 와 같은 뜻입니다.
bool isBlankState(Map<String, Object?> st) =>
    st['onboarded'] != true &&
    ((st['scans'] as List?) ?? const []).isEmpty &&
    ((st['foodLogs'] as List?) ?? const []).isEmpty;

/// 활성 칸의 주인. 없으면(null) 주인 없는 칸 — 로그인 없이 쓰는 기록이거나 빈 기록.
class LocalOwner {
  const LocalOwner({this.server, this.uid, this.sess, this.handle, this.since, this.unknown = false});

  /// 이 로그인([api])의 칸으로.
  factory LocalOwner.of(Api api, {String? handle}) => LocalOwner(
      server: serverOf(api),
      uid: api.userId,
      sess: api.sessionTag,
      handle: handle,
      since: DateTime.now().toUtc().toIso8601String());

  final String? server;
  final String? uid;

  /// 계정 id 를 모를 때 묶어 둔 로그인의 표시([Api.sessionTag]).
  final String? sess;
  final String? handle;
  final String? since;

  /// 누구 것인지 모르는 기록(0.2.19 에서 올라온 기기 · 로그아웃 때 id 를 끝내 모름).
  final bool unknown;

  /// 치워 둘 칸의 이름. 계정 id 를 모르면 null.
  String? get slot => (unknown || server == null || uid == null) ? null : '$server|$uid';

  /// 지금 로그인([api])이 이 칸의 주인인가.
  bool isSession(Api api) {
    if (unknown || !api.signedIn) return false;
    if (server != null && server != serverOf(api)) return false;
    final u = api.userId;
    if (uid != null && u != null) return uid == u;
    return sess != null && sess == api.sessionTag;
  }

  LocalOwner copyWith({String? uid, String? sess, String? handle}) => LocalOwner(
      server: server,
      uid: uid ?? this.uid,
      sess: sess ?? this.sess,
      handle: handle ?? this.handle,
      since: since);

  Map<String, Object?> toJson() => {
        if (server != null) 'server': server,
        if (uid != null) 'uid': uid,
        if (sess != null) 'sess': sess,
        if (handle != null) 'handle': handle,
        if (since != null) 'since': since,
        if (unknown) 'unknown': true,
      };

  /// 빈 {} 는 주인 없음(null).
  static LocalOwner? fromJson(Object? j) {
    if (j is! Map || j.isEmpty) return null;
    String? s(Object? v) => v is String && v.isNotEmpty ? v : null;
    final o = LocalOwner(
        server: s(j['server']),
        uid: s(j['uid']),
        sess: s(j['sess']),
        handle: s(j['handle']),
        since: s(j['since']),
        unknown: j['unknown'] == true);
    return (o.unknown || o.uid != null || o.sess != null) ? o : null;
  }
}

/// 활성 칸의 주인을 들고 있습니다 — 메모리가 먼저이고 기기에는 뒤에서 적습니다(보내는 쪽이 같은
/// 틈에 묻습니다). AppState 가 하나 가집니다. 칸을 바꿀 때는 [commit] 으로 적고 기다립니다.
class OwnerBook {
  OwnerBook(this._sp) {
    try {
      final raw = _sp?.getString(kOwnerKey);
      _recorded = raw != null;
      if (raw != null) _o = LocalOwner.fromJson(jsonDecode(raw));
    } catch (_) {
      /* 깨졌으면 모름 — 합치기 전에 묻게. */
      _recorded = true;
      _o = const LocalOwner(unknown: true);
    }
  }

  final SharedPreferences? _sp;
  LocalOwner? _o;
  bool _recorded = false;

  /// 활성 칸의 주인. null 이면 주인 없음.
  LocalOwner? get current => _o;

  /// 주인 칸이 적혀 있었나 — 없으면 0.2.19 에서 올라온 첫 실행입니다(이관).
  bool get recorded => _recorded;

  static String _raw(LocalOwner? o) => jsonEncode(o?.toJson() ?? const <String, Object?>{});

  void set(LocalOwner? o) {
    _o = o;
    _recorded = true;
    try {
      unawaited(_sp?.setString(kOwnerKey, _raw(o)));
    } catch (_) {}
  }

  /// 적고 **기다립니다** — 못 적었으면 던집니다(칸 바꾸기를 멈추게). 메모리는 먼저 바뀝니다.
  Future<void> commit(LocalOwner? o) async {
    _o = o;
    _recorded = true;
    final sp = _sp;
    if (sp == null) return;
    if (!await sp.setString(kOwnerKey, _raw(o))) throw StateError('이 기기에 저장하지 못했습니다: $kOwnerKey');
  }

  /// 그 칸이 이 기기에 치워져 있나.
  bool hasParked(String slot) => _sp?.containsKey('$kSlotPrefix$slot.state') ?? false;
}

/// 이 기기의 기록(활성 칸)이 지금 로그인([api])으로 나가도 되는가 — 동기화 · 주간 요약이 보내기
/// 전에 봅니다. 칸에 주인이 없고 비어 있던 채로 로그인돼 있으면(이 로그인에서 새로 쓰기 시작한 것)
/// 그 로그인의 칸으로 적습니다 — 다만 그 계정의 칸이 치워져 있으면 적지 않습니다(다음에 켤 때
/// 되돌립니다 — [AccountSlots.migrate]). 주인 없는 기록이 있으면 로그인하는 문에서 합칠지 고르기
/// 전까지 안 나갑니다. id 를 몰랐던 칸(이관)이 맞으면 이제 알게 된 id 를 적습니다 — 로그아웃할 때 칸 이름.
bool mayLeave(AppState app, Api api) {
  if (!api.signedIn) return false;
  final book = app.owner;
  final o = book.current;
  if (o == null) {
    if (!app.wasBlank && !isBlankState(app.state)) return false;
    if (_parkedFor(book, api)) return false;
    book.set(LocalOwner.of(api));
    return true;
  }
  if (!o.isSession(api)) return false;
  final u = api.userId;
  if (o.uid == null && u != null) book.set(o.copyWith(uid: u));
  return true;
}

bool _parkedFor(OwnerBook book, Api api) {
  final u = api.userId;
  return u != null && book.hasParked('${serverOf(api)}|$u');
}

/// 로그인한 채 칸이 비어 있고 주인이 없으면 이 로그인의 칸으로 적습니다(동기화가 켤 때 · 로그인할 때).
/// 그 계정의 칸이 치워져 있으면 적지 않습니다 — 빈 칸이 그 계정의 것이 되면 다음 로그아웃이 치워 둔
/// 칸을 빈 기록으로 덮습니다.
void claimIfBlank(AppState app, Api api) {
  if (!api.signedIn || app.owner.current != null || !isBlankState(app.state)) return;
  if (_parkedFor(app.owner, api)) return;
  app.owner.set(LocalOwner.of(api));
}

/// 합칠지 묻는 창에 보일 요약 — 측정 수 · 식단 수 · 마지막 측정(「9/19 86.7kg」).
LocalRecords summarize(Map<String, Object?> st, {bool unknown = false}) {
  final scans = [for (final s in (st['scans'] as List?) ?? const []) if (s is Map) s];
  Map? last;
  DateTime? lastAt;
  for (final s in scans) {
    final at = DateTime.tryParse('${s['measuredAt'] ?? ''}');
    if (at != null && (lastAt == null || at.isAfter(lastAt))) {
      last = s;
      lastAt = at;
    }
  }
  String? latest;
  if (last != null && lastAt != null) {
    final l = lastAt.toLocal();
    final w = last['weightKg'];
    latest = '${l.month}/${l.day}${w is num ? ' ${core.jsNumToString(w)}kg' : ''}';
  }
  return (
    scans: scans.length,
    foodLogs: ((st['foodLogs'] as List?) ?? const []).length,
    latest: latest,
    unknown: unknown,
  );
}

/* 같은 기록인지 알아보는 짧은 표시 — [합치지 않기] 를 적어 둘 때. */
String _signature(Map<String, Object?> st) {
  final s = summarize(st);
  final ids = [for (final x in (st['scans'] as List?) ?? const []) if (x is Map) '${x['id']}']..sort();
  return '${s.scans}|${s.foodLogs}|${ids.isEmpty ? '' : ids.last}|${st['onboarded'] == true}';
}

/// 치워 둔 칸들의 측정이 가리키는 결과지 사진 — 사진 파일은 모든 칸이 한 폴더를 같이 쓰므로, 한
/// 칸에서 측정을 지울 때 다른 칸이 가리키는 사진은 남깁니다(Store.photoKeptElsewhere).
Set<String> parkedPhotoIds(SharedPreferences sp) {
  final out = <String>{};
  for (final k in sp.getKeys()) {
    if (!k.startsWith(kSlotPrefix) || !k.endsWith('.state')) continue;
    try {
      final st = jsonDecode(sp.getString(k) ?? '{}');
      for (final s in (st is Map ? st['scans'] as List? : null) ?? const []) {
        final p = s is Map ? s['photoId'] : null;
        if (p != null && '$p'.isNotEmpty) out.add('$p');
      }
    } catch (_) {/* 못 읽는 칸은 건너뜁니다 */}
  }
  return out;
}

/// 기기 저장소에 적고 **기다립니다** — 못 적었으면 던집니다(칸 바꾸기를 멈추게). [value] 가 null 이면 지웁니다.
Future<void> _put(SharedPreferences sp, String key, String? value) async {
  final ok = value == null ? await sp.remove(key) : await sp.setString(key, value);
  if (!ok) throw StateError('이 기기에 저장하지 못했습니다: $key');
}

/// 계정이 바뀌는 경계에서 칸을 갈아 끼우는 쪽. main.dart 가 하나 만들어 Api 에 꽂습니다
/// ([Api.accounts]). 서버 주소가 바뀌면 큐 · 동기화가 새것이 되므로 [queue] · [cloud] 를 바꿔 끼웁니다.
///
/// **칸 바꾸기의 차례**(2차 검토 — 기기 저장소에는 여러 번 나눠 쓰므로, 어디서 앱이 죽거나 저장이
/// 실패해도 다른 계정으로 새지 않고 잃지 않게):
///   1. 떠나는 칸이 어느 계정의 것이면 그 계정 이름으로 치울 곳에 적습니다 — 같은 이름의 칸이 이미
///      있으면 합칩니다(덮지 않음). 여기서 멈추면 주인은 아직 그 계정이라 다음에 켤 때 마저 치웁니다.
///   2. 주인을 '모름'(바꾸는 중)으로 적고 기다립니다 — 여기부터 멈추면 다음 로그인이 경고와 함께
///      묻고, 보내는 쪽([mayLeave])은 아무것도 안 보냅니다.
///   3. 들어올 칸을 활성 칸에 적습니다(기록 · 곁의 기기 칸들).
///   4. 새 주인을 적습니다.
///   5. 되돌린 칸의 치워 둔 사본을 지웁니다 — 맨 끝(그 전에 멈추면 사본이 남을 뿐).
/// 로그아웃은 그 전에 토큰부터 기기에서 지웁니다(api.dart). 로그인은 토큰을 맨 끝에 적습니다. 그래서
/// 켤 때 "로그아웃돼 있는데 주인이 어느 계정" 이면 로그아웃이 멈춘 것이라 마저 치웁니다([migrate]).
/// 로그인하다 저장이 실패하면 로그인을 멈춥니다(api.dart) — 화면은 앞 칸 그대로입니다.
class AccountSlots implements AccountSwitch {
  AccountSlots({
    required this.app,
    this.queue,
    CloudSync? cloud,
    this.invites,
    this.flushLimit = const Duration(seconds: 5),
  }) {
    this.cloud = cloud;
  }

  final AppState app;
  SyncQueue? queue;
  InviteInbox? invites;

  /// 로그아웃하기 전에 못 보낸 것을 보내 보는 시간. 서버가 꺼져 있으면 그만큼만 기다립니다.
  final Duration flushLimit;

  CloudSync? _cloud;
  CloudSync? get cloud => _cloud;
  set cloud(CloudSync? c) {
    _cloud = c;
    c?.slotsManaged = true;
  }

  static const _switching = LocalOwner(unknown: true);

  /* 칸 바꾸기는 한 번에 하나씩 — 로그아웃이 끝나기 전에 로그인이 오면 뒤에 줄을 섭니다. */
  Future<void> _chain = Future<void>.value();
  Future<void> _serial(Future<void> Function() f) {
    final run = _chain.then((_) => f());
    _chain = run.catchError((_) {});
    return run;
  }

  /* --- 켤 때: 0.2.19 → 첫 실행 · 멈춘 칸 바꾸기 마저 하기 ------------------------------ */

  /// 켤 때 한 번, 동기화 · 주간 요약을 꽂기 전에 부릅니다. 주인 칸이 없는 기기(0.2.19 에서 올라옴)면
  /// 주인을 적고, 칸 바꾸기가 도중에 멈춘 흔적이 있으면 마저 합니다.
  Future<void> migrate(Api api) => _serial(() async {
        final book = app.owner;
        if (book.recorded) {
          try {
            await _recover(api);
          } catch (_) {/* 못 하면 다음에 켤 때 — 보내는 쪽이 주인을 다시 봅니다 */}
          return;
        }
        final st = app.state;
        if (isBlankState(st)) {
          book.set(api.signedIn ? LocalOwner.of(api) : null);
          queue?.adoptLegacy(uid: api.userId, sess: api.sessionTag);
          return;
        }
        if (api.signedIn) {
          /* 로그인돼 있으면 지금 기록은 이 로그인의 것입니다(0.2.19 는 로그아웃해도 기록을
             남겼으니 틀릴 수 있지만, 주인이 업데이트 전에 폰을 정리하기로 했습니다). */
          book.set(LocalOwner.of(api));
          queue?.adoptLegacy(uid: api.userId, sess: api.sessionTag);
          /* 로그인한 칸에 「로그인 없이 쓰기」 표시가 남아 있으면 뗍니다 — 로그아웃한 뒤 로그인
             화면 없이 빈 탭이 뜨지 않게. */
          if (st['guest'] == true) app.store.swap({...st}..remove('guest'));
          /* 계정 id 는 /me 로 곧 알아 둡니다(기다리지 않음) — 로그아웃할 때 칸 이름입니다.
             못 닿으면 다음 동기화 · 로그아웃이 다시 묻습니다. */
          if (api.userId == null) {
            unawaited(api.me().then((_) {
              final o = book.current;
              final u = api.userId;
              if (o != null && o.uid == null && u != null && o.isSession(api)) book.set(o.copyWith(uid: u));
            }).catchError((_) {}));
          }
          return;
        }
        /* 로그인 없이 기록만 — 로그인 없이 쓴 것인지 로그아웃한 계정이 남긴 것인지 모릅니다. */
        book.set(const LocalOwner(unknown: true));
        queue?.adoptLegacy();
        final sp = await _prefs();
        if (sp == null) return;
        /* 어느 계정의 기준본 · 독촉 · 소식인지 모릅니다 — 합칠 때 쓰면 안 됩니다. */
        for (final part in ['cloud.base', 'cloud.last', 'pokes', 'news']) {
          await sp.remove(kSlotParts[part]!);
        }
        app.pokes?.reload();
      });

  /* 칸 바꾸기가 도중에 멈춘 흔적(클래스 주석의 차례):
     · 로그아웃돼 있는데 주인이 어느 계정 — 로그아웃이 칸을 치우기 전에(또는 로그인이 토큰을 적기
       전에) 멈췄습니다. 그 계정의 칸으로 마저 치웁니다(로그인 화면 · 「로그인 없이 쓰기」 에 안 보이게).
     · 로그인한 채 빈 칸 · 주인 없음인데 그 계정의 칸이 치워져 있음 — 되돌립니다. */
  Future<void> _recover(Api api) async {
    final sp = await _prefs();
    if (sp == null) return;
    final o = app.owner.current;
    final server = serverOf(api);
    if (!api.signedIn && o != null && !o.unknown && o.slot != null) {
      _cloud?.slotChanged(reload: false);
      await _leave(sp, o.slot!, <String, Object?>{...app.state}..remove('guest'), o,
          queue?.jobsFor(uid: o.uid, sess: o.sess) ?? const []);
      await app.owner.commit(_switching);
      await _enterGuest(sp, thenGuest: false);
      return;
    }
    final u = api.userId;
    if (api.signedIn && o == null && u != null && isBlankState(app.state) && _hasSlot(sp, '$server|$u')) {
      _cloud?.slotChanged(reload: false);
      await app.owner.commit(_switching);
      await _enter(sp, '$server|$u', LocalOwner.of(api));
    }
  }

  /* --- 로그인 ----------------------------------------------------------------- */

  @override
  Future<void> beforeSignIn(Api api,
          {required String? uid, required String sess, String? handle, MergeAsk? ask}) =>
      _serial(() async {
        final before = <String, Object?>{...app.state};
        try {
          await _signIn(api, uid: uid, sess: sess, handle: handle, ask: ask);
        } catch (_) {
          /* 칸을 다 못 바꿨습니다(저장 공간 등) — 로그인은 멈추고(api.dart), 화면은 앞 칸으로
             되돌립니다. 주인은 '모름' 으로 둡니다 — 기기에 반쯤 적힌 칸이 있을 수 있어, 다음 로그인은
             경고와 함께 묻습니다(그 계정 칸을 되돌리다 멈춘 사본이면 묻지 않고 되돌림). */
          app.owner.set(_switching);
          _swap(before);
          _cloud?.slotChanged();
          rethrow;
        }
      });

  Future<void> _signIn(Api api,
      {required String? uid, required String sess, String? handle, MergeAsk? ask}) async {
    final sp = await _prefs();
    final server = serverOf(api);
    final book = app.owner;
    final o = book.current;
    final target = uid == null ? null : '$server|$uid';
    final me = LocalOwner(
        server: server, uid: uid, sess: sess, handle: handle,
        since: DateTime.now().toUtc().toIso8601String());
    /* 로그인하면 「로그인 없이 쓰기」 표시는 뗍니다 — 계정 칸에 남으면 로그아웃한 뒤 로그인
       화면 없이 탭이 뜹니다. */
    final st = <String, Object?>{...app.state}..remove('guest');

    /* 1. 같은 계정 — 칸은 그대로, 토큰만 새것. 옛 토큰으로 적힌 큐 작업도 id 로 알아보게. */
    if (o != null && !o.unknown && uid != null && o.uid == uid && o.server == server) {
      await book.commit(o.copyWith(sess: sess, handle: handle));
      final q = queue;
      if (q != null && o.sess != null) q.putBack(q.takeFor(uid: uid, sess: o.sess));
      if (app.state['guest'] == true) app.store.swap(st);
      return;
    }

    if (sp == null) {
      /* 기기 저장소가 없으면 칸을 치워 둘 곳이 없습니다 — 다른 계정의 기록이면 빈 기록으로
         시작합니다(합치지 않음). 주인 없는 기록은 그대로 이 계정의 것으로. */
      if (o != null && !o.unknown && o.uid != null) app.store.swap({});
      book.set(me);
      return;
    }

    _cloud?.slotChanged(reload: false);

    /* 2. 다른 계정의 칸 — 치워 두고, 들어온 계정의 칸(없으면 빈 기록)으로. 절대 합치지 않습니다. */
    if (o != null && !o.unknown && o.slot != null) {
      await _leave(sp, o.slot!, st, o, queue?.jobsFor(uid: o.uid, sess: o.sess) ?? const []);
      await book.commit(_switching);
      await _enter(sp, target, me);
      return;
    }

    /* 3. 주인 없는 칸(로그인 없이 쓴 기록) · 모르는 칸. id 를 끝내 몰랐던 옛 로그인의 칸도
       누구 것인지 모르니 같이 봅니다 — 그 로그인의 못 보낸 일은 큐에 남겨 두었다가(주인 모름)
       이 기록을 어느 계정에 합치면 그 계정으로 보냅니다(_adopt). */
    final unknown = o != null;
    if (isBlankState(st) || (target != null && _isParkedCopy(sp, target, st))) {
      /* 빈 기록이거나, 그 계정 칸을 되돌리다 멈춰 남은 사본 — 묻지 않고 그 계정의 칸으로. */
      await book.commit(_switching);
      await _enter(sp, target, me);
      return;
    }
    final declined = _declined(sp);
    final sig = _signature(st);
    final bool? merge = target != null && declined[target] == sig
        ? false
        : await ask?.call(summarize(st, unknown: unknown));
    if (merge == true) {
      if (target != null && declined.remove(target) != null) {
        await _put(sp, kGuestDeclinedKey, jsonEncode(declined));
      }
      await book.commit(_switching);
      await _adopt(sp, st, target, me, uid: uid, sess: sess, unknown: unknown);
      return;
    }
    /* [합치지 않기] 를 **직접 고른 때만** 적어 둡니다 — 창이 닫히지 못하게 막았어도(뒤로 가기) 고르지
       않은 채 끝났으면(화면이 내려감 · 묻는 창 없음) 다음 로그인에 다시 묻습니다. */
    if (merge == false && target != null) {
      declined[target] = sig;
      await _put(sp, kGuestDeclinedKey, jsonEncode(declined));
    }
    await _parkGuest(sp, st, unknown: unknown);
    await book.commit(_switching);
    await _enter(sp, target, me);
  }

  /* 활성 칸이 그 계정의 치워 둔 칸과 내용이 같은가 — 되돌리다 멈춘 흔적입니다(차례 3 뒤, 5 전). */
  static bool _isParkedCopy(SharedPreferences sp, String target, Map<String, Object?> st) =>
      _hasSlot(sp, target) &&
      sameState(withoutSyncMeta({...core.Store.blank(), ..._readState(sp, target)}..remove('guest')),
          withoutSyncMeta({...core.Store.blank(), ...st}..remove('guest')));

  /* 주인 없는 기록을 이 계정의 것으로. 그 계정의 칸이 치워져 있으면 되돌리고 이 기기 안에서
     합칩니다(기준본 없이 합집합 — 목록은 다 남고, 하나짜리 값은 나중에 바꾼 쪽). 없으면 이 칸이
     곧 그 계정의 칸이고, 동기화가 계정 사본과 합칩니다(예전의 「로그인 없이 쓰다 로그인」 과 같음).
     누구 것인지 모르던 기록이면 그 기록의 못 보낸 일(id 를 몰랐던 로그인)도 이 계정으로 보냅니다 —
     기록을 이 계정의 것으로 고른 것과 같은 결정입니다. */
  Future<void> _adopt(SharedPreferences sp, Map<String, Object?> guest, String? target, LocalOwner me,
      {required String? uid, required String sess, required bool unknown}) async {
    final guestAt = sp.getString(CloudSync.keyAt) ?? '';
    if (target != null && _hasSlot(sp, target)) {
      final parked = _readState(sp, target);
      final parkedAt = sp.getString(_k(target, 'cloud.at')) ?? '';
      final merged = withoutSyncMeta(
          mergeStates(guest, parked, localAt: guestAt, remoteAt: parkedAt));
      /* 합친 것은 이 기기가 지금 바꾼 것 — 기준본과 달라 다음 동기화가 올립니다. */
      final parts = {..._slotParts(sp, target), 'cloud.at': CloudSync.isoMs(DateTime.now())};
      await _activate(sp, merged, parts, me);
      queue?.putBack(_slotJobs(sp, target));
      if (unknown) queue?.adoptOrphans(uid: uid, sess: sess);
      await _dropSlot(sp, target);
      _settled();
      return;
    }
    /* 모르는 칸의 기준본 · 독촉 · 소식은 다른 계정 것일 수 있습니다. 로그인 없이 쓴 칸에는 원래
       없습니다. 초대 표시는 기기에 남아도 되는 것이라 둡니다. 모르는 기록의 시각은 이 계정의
       프로필 · 목표를 이기지 않게 버립니다 — 합칠 때 계정 쪽을 믿습니다. */
    final parts = <String, String?>{
      for (final e in kSlotParts.entries) e.key: sp.getString(e.value),
      'cloud.base': null, 'cloud.last': null, 'pokes': null, 'news': null,
      if (unknown) 'cloud.at': null,
    };
    await _activate(sp, guest, parts, me);
    if (unknown) queue?.adoptOrphans(uid: uid, sess: sess);
    _settled();
  }

  /* --- 로그아웃 ---------------------------------------------------------------- */

  /// 로그아웃하기 전 — 3초 모으던 변경까지 그 계정으로 보내 봅니다(못 보낸 것은 칸에 남았다가
  /// 그 계정으로 돌아오면 갑니다). 계정 id 를 아직 모르면(이관) 먼저 알아 둡니다 — 칸 이름입니다.
  @override
  Future<void> beforeSignOut(Api api) async {
    try {
      await () async {
        if (api.userId == null) await api.me();
        await _cloud?.syncNow();
        await queue?.flush();
      }()
          .timeout(flushLimit);
    } catch (_) {}
  }

  @override
  Future<void> afterSignOut(Api api,
          {required String? uid, required String? sess, required bool gone, bool thenGuest = false}) =>
      _serial(() async {
        final sp = await _prefs();
        final server = serverOf(api);
        final book = app.owner;
        final o = book.current;
        /* 「로그인 없이 쓰기」 표시는 칸에 남기지 않습니다 — 다음 칸은 로그인 화면부터(전에 그 표시가
           있었어도). 「동의하지 않고 로그인 없이 쓰기」 만 곧바로 탭 화면으로([thenGuest]). */
        final st = <String, Object?>{...app.state}..remove('guest');
        final id = uid ?? o?.uid;
        _cloud?.slotChanged(reload: false);

        if (gone) {
          await _accountGone(sp, server, id, sess, st, thenGuest);
          return;
        }
        final mine = o != null && !o.unknown &&
            ((id != null && o.uid == id) || (sess != null && o.sess == sess));
        /* 치울 칸 — 이 계정의 것이면 이 계정 이름으로. 칸의 주인이 다른 계정이면(로그인 문을 안
           거친 토큰 — 앱에는 없는 길) 그 주인의 이름으로 치웁니다. 어느 쪽이든 화면에는 안 남깁니다. */
        final slot = mine ? (id == null ? null : '$server|$id') : (o != null && !o.unknown ? o.slot : null);
        if (sp != null && o != null && slot != null) {
          final jobs = queue?.jobsFor(uid: mine ? id : o.uid, sess: mine ? sess : o.sess) ?? const <SyncJob>[];
          await _leave(sp, slot, st, mine ? o.copyWith(uid: id) : o, jobs);
          if (!mine) queue?.takeFor(uid: id, sess: sess);   // 이 로그인의 일 — 둘 칸이 없어 버립니다
          await book.commit(_switching);
          /* 다음 칸 — 로그인 없이 쓰던 기록이 치워져 있으면 그것, 없으면 빈 기록. */
          await _enterGuest(sp, thenGuest: thenGuest);
          return;
        }
        /* 주인 없는 기록 · 모르는 기록이거나, 이 계정의 id 를 끝내 몰랐으면(이관 뒤 한 번도 서버에
           못 닿음) 치워 둘 칸 이름이 없습니다. 그대로 두되 다음 로그인이 묻게 '모름' 으로 적습니다.
           그 로그인의 못 보낸 일은 **버리지 않고** 큐에 둡니다 — 이 로그인이 끝났으니 아무에게도 안
           나가고, 이 기록을 어느 계정에 [합치기] 하면 그 계정으로 갑니다(_adopt). */
        if (mine) {
          try {
            await book.commit(_switching);
          } catch (_) {
            book.set(_switching);
          }
        }
        _swap(thenGuest ? {...st, 'guest': true} : st);
        _cloud?.slotChanged();
      });

  /* 「계정 지우기」 — 서버의 사본은 이미 없습니다. 이 기기의 기록은 **그대로 남깁니다**(확인 창의
     약속 「이 기기의 기록은 그대로 남고」): 지우면 유일본이 사라지고, 없는 계정의 칸으로 치우면
     아무도 못 엽니다. 대신 **주인 모르는 기록**이 됩니다 — 로그인 없이 쓴 기록과 달리 누구 것이었는지
     아는 기록이라, 다른 계정으로 로그인하면 「다른 계정의 기록일 수 있어요」 와 함께 묻고 기본은
     [합치지 않기]입니다(2차 검토 — 주인 없음으로 두면 경고 없이 [합치기]가 앞에 섰습니다). 그 계정의
     친구 쪽 것(독촉 · 소식 · 초대 표시)과 기준본 · 못 보낸 일은 버립니다 — 갈 곳이 없습니다.
     로그인 없이 쓰던 기록이 손님 칸에 따로 있으면 그대로 둡니다. 다음 로그인에서 이 기록도
     [합치지 않기] 하면 손님 칸과 이 기기 안에서 합쳐 보관합니다(「로그인 없이 쓰기」 는 한 칸이라
     따로 두면 한쪽을 다시 열 길이 없습니다 — 합친 칸은 계속 '모름' 이라 어느 계정에 합칠 때도 경고). */
  Future<void> _accountGone(SharedPreferences? sp, String server, String? id, String? sess,
      Map<String, Object?> st, bool thenGuest) async {
    queue?.takeFor(uid: id, sess: sess);
    if (sp != null) {
      await app.owner.commit(_switching);
      for (final part in ['cloud.base', 'cloud.last', 'pokes', 'news', 'invite.mine', 'invite.handled']) {
        await _put(sp, kSlotParts[part]!, null);
      }
      if (id != null) await _dropSlot(sp, '$server|$id');
    } else {
      app.owner.set(_switching);
    }
    _swap(thenGuest ? {...st, 'guest': true} : st);
    _cloud?.slotChanged();
  }

  /* --- 칸 옮기기 ---------------------------------------------------------------- */

  static String _k(String slot, String part) => '$kSlotPrefix$slot.$part';

  static bool _hasSlot(SharedPreferences sp, String slot) =>
      sp.containsKey(_k(slot, 'state')) || sp.containsKey(_k(slot, 'owner'));

  static Map<String, Object?> _readState(SharedPreferences sp, String slot) {
    try {
      final j = jsonDecode(sp.getString(_k(slot, 'state')) ?? '{}');
      return j is Map ? j.cast<String, Object?>() : <String, Object?>{};
    } catch (_) {
      return <String, Object?>{};
    }
  }

  static Map<String, String?> _slotParts(SharedPreferences sp, String slot) =>
      {for (final part in kSlotParts.keys) part: sp.getString(_k(slot, part))};

  static List<SyncJob> _slotJobs(SharedPreferences sp, String slot) {
    try {
      final raw = jsonDecode(sp.getString(_k(slot, 'queue')) ?? '[]');
      return [
        if (raw is List)
          for (final o in raw)
            if (SyncJob.fromJson(o) case final j?) j,
      ];
    } catch (_) {
      return const [];
    }
  }

  static Map<String, Object?> _declined(SharedPreferences sp) {
    try {
      final j = jsonDecode(sp.getString(kGuestDeclinedKey) ?? '{}');
      return j is Map ? j.cast<String, Object?>() : <String, Object?>{};
    } catch (_) {
      return <String, Object?>{};
    }
  }

  /* 떠나는 칸을 [slot] 으로 치웁니다(차례 1) — 기록 · 기기 칸들 · 큐 작업 · 주인. 같은 이름의 칸이
     이미 있으면(되돌리다 멈춘 사본 등) 덮지 않고 합칩니다 — 목록은 합집합, 곁의 칸은 지금 것이 먼저,
     큐는 둘 다. 칸에 다 적은 뒤에야 큐에서 뺍니다. 활성 칸은 다음 칸이 덮습니다(차례 3). */
  Future<void> _leave(SharedPreferences sp, String slot, Map<String, Object?> st, LocalOwner owner,
      List<SyncJob> jobs) async {
    var state = st;
    final parts = <String, String?>{for (final e in kSlotParts.entries) e.key: sp.getString(e.value)};
    var all = jobs;
    if (_hasSlot(sp, slot)) {
      final old = _readState(sp, slot);
      final oldParts = _slotParts(sp, slot);
      final at = parts['cloud.at'] ?? '', oldAt = oldParts['cloud.at'] ?? '';
      state = withoutSyncMeta(mergeStates(st, old, localAt: at, remoteAt: oldAt));
      for (final part in kSlotParts.keys) {
        parts[part] ??= oldParts[part];
      }
      if (oldAt.compareTo(at) > 0) parts['cloud.at'] = oldAt;
      all = SyncQueue.dedupe([..._slotJobs(sp, slot), ...jobs]);
    }
    await _put(sp, _k(slot, 'state'), jsonEncode(state));
    for (final e in parts.entries) {
      await _put(sp, _k(slot, e.key), e.value);
    }
    await _put(sp, _k(slot, 'queue'), all.isEmpty ? null : jsonEncode([for (final j in all) j.toJson()]));
    await _put(sp, _k(slot, 'owner'), jsonEncode(owner.toJson()));
    queue?.removeJobs(jobs);
  }

  /* 활성 칸에 [next] 를 적습니다(차례 3 · 4) — 메모리부터 갈아 끼우고(그 사이 저장이 나도 새 칸을
     적게), 기기에 적힌 것을 기다리고, 곁의 기기 칸들([parts] — 없는 조각은 지움), 마지막에 주인. */
  Future<void> _activate(SharedPreferences sp, Map<String, Object?> next, Map<String, String?> parts,
      LocalOwner? owner) async {
    app.store.swap(next);
    await _put(sp, core.storeKey, jsonEncode(app.store.get()));
    for (final e in kSlotParts.entries) {
      await _put(sp, e.value, parts[e.key]);
    }
    await app.owner.commit(owner);
  }

  static Future<void> _dropSlot(SharedPreferences sp, String slot) async {
    final head = '$kSlotPrefix$slot.';
    for (final k in sp.getKeys().where((k) => k.startsWith(head)).toList()) {
      await _put(sp, k, null);
    }
  }

  /* 들어온 계정의 칸으로 — 치워 둔 것이 있으면 되돌리고, 없으면 빈 기록(새 계정은 온보딩부터).
     치워 둔 사본은 활성 칸에 다 적은 뒤에 지웁니다(차례 5). */
  Future<void> _enter(SharedPreferences sp, String? target, LocalOwner me) async {
    if (target != null && _hasSlot(sp, target)) {
      await _activate(sp, _readState(sp, target)..remove('guest'), _slotParts(sp, target), me);
      queue?.putBack(_slotJobs(sp, target));
      await _dropSlot(sp, target);
    } else {
      await _activate(sp, const {}, const {}, me);
    }
    _settled();
  }

  /* 로그인 없이 쓰던 기록을 손님 칸으로. 이미 있으면 합칩니다(둘 다 이 기기의 주인 없는 기록 —
     기기 밖으로는 안 나갑니다. 하나라도 누구 것인지 모르는 기록이면 합친 칸도 '모름'). 활성 칸의
     기준본 · 독촉 · 소식은 옮기지 않습니다 — 다음 칸이 덮습니다. 옛 손님 칸은 덮어쓰고(합친 것이라
     잃는 것이 없음) 필요 없는 조각만 지웁니다. */
  Future<void> _parkGuest(SharedPreferences sp, Map<String, Object?> st, {required bool unknown}) async {
    var state = st;
    var at = sp.getString(CloudSync.keyAt) ?? '';
    var wasUnknown = false;
    if (_hasSlot(sp, kGuestSlot)) {
      final old = _readState(sp, kGuestSlot);
      final oldAt = sp.getString(_k(kGuestSlot, 'cloud.at')) ?? '';
      state = withoutSyncMeta(mergeStates(st, old, localAt: at, remoteAt: oldAt));
      if (oldAt.compareTo(at) > 0) at = oldAt;
      try {
        wasUnknown = (jsonDecode(sp.getString(_k(kGuestSlot, 'owner')) ?? '{}') as Map)['unknown'] == true;
      } catch (_) {}
    }
    await _put(sp, _k(kGuestSlot, 'state'), jsonEncode(state));
    await _put(sp, _k(kGuestSlot, 'cloud.at'), at.isEmpty ? null : at);
    await _put(sp, _k(kGuestSlot, 'owner'), jsonEncode({if (unknown || wasUnknown) 'unknown': true}));
    const keep = {'state', 'cloud.at', 'owner'};
    for (final k in sp.getKeys().where((k) => k.startsWith(_k(kGuestSlot, ''))).toList()) {
      if (!keep.contains(k.substring(_k(kGuestSlot, '').length))) await _put(sp, k, null);
    }
  }

  /* 로그아웃한 뒤의 칸 — 손님 칸이 있으면 되돌리고, 없으면 빈 기록. */
  Future<void> _enterGuest(SharedPreferences sp, {required bool thenGuest}) async {
    Map<String, Object?> st = const {};
    Map<String, String?> parts = const {};
    LocalOwner? owner;
    final parked = _hasSlot(sp, kGuestSlot);
    if (parked) {
      st = _readState(sp, kGuestSlot);
      parts = _slotParts(sp, kGuestSlot);
      try {
        if ((jsonDecode(sp.getString(_k(kGuestSlot, 'owner')) ?? '{}') as Map)['unknown'] == true) {
          owner = const LocalOwner(unknown: true);
        }
      } catch (_) {}
    }
    final next = <String, Object?>{...st}..remove('guest');
    if (thenGuest) next['guest'] = true;
    await _activate(sp, next, parts, owner);
    queue?.putBack(parked ? _slotJobs(sp, kGuestSlot) : const []);
    if (parked) await _dropSlot(sp, kGuestSlot);
    _settled();
  }

  /* 칸을 다 바꾼 뒤 — 메모리에 칸을 든 쪽(독촉 · 초대 · 동기화)이 새 칸을 다시 읽게. */
  void _settled() {
    app.pokes?.reload();
    unawaited(invites?.reloadHandled());
    _cloud?.slotChanged();
  }

  /* 기록만 갈아 끼우고 새 칸을 다시 읽게(기기 칸들을 옮기지 않는 길 — 계정 지우기 · id 모름). */
  void _swap(Map<String, Object?> next) {
    app.store.swap(next);
    app.pokes?.reload();
    unawaited(invites?.reloadHandled());
  }

  static Future<SharedPreferences?> _prefs() async {
    try {
      return await SharedPreferences.getInstance();
    } catch (_) {
      return null;
    }
  }
}

/// 「이 기기에서 전부 지우기」 — 활성 칸과 **치워 둔 모든 칸**(다른 계정 · 로그인 없이 쓴 것), 결과지
/// 사진, 독촉 · 소식 · 초대 표시, 못 보낸 큐, 동기화의 기기 칸을 지웁니다. 로그아웃은 부른 쪽이
/// 먼저 합니다(settings.dart). 계정의 서버 사본은 그대로입니다.
Future<void> wipeDevice({
  required AppState app,
  SyncQueue? queue,
  CloudSync? cloud,
  InviteInbox? invites,
}) async {
  /* 사진 · 소식 · 기록(Store.reset). 사진은 치워 둔 칸의 것까지 한 폴더라 같이 지워집니다. */
  app.store.reset();
  queue?.clear();
  /* 동기화가 방금 찍은 시각 · 하던 맞춤도 버립니다. */
  cloud?.slotChanged(reload: false);
  try {
    final sp = await SharedPreferences.getInstance();
    for (final k in sp.getKeys().toList()) {
      if (k.startsWith(kSlotPrefix) ||
          k == kOwnerKey ||
          kSlotParts.values.contains(k) ||
          k.startsWith('mybody.invite.')) {
        await sp.remove(k);
      }
    }
  } catch (_) {}
  app.owner.set(null);
  app.pokes?.reload();
  invites?.forgetAll();
  await Api.clearAccountCaches();
  cloud?.slotChanged();
}

/// 이 기기에 따로 보관된 칸 — 다른 계정 수와 로그인 없이 쓴 기록이 있는지. 「이 기기에서 전부 지우기」
/// 확인창이 말합니다(보관된 칸은 화면에 안 보여도 같이 지워지고, 서버에 사본이 없으면 되찾을 수 없음).
Future<({int accounts, bool guest})> parkedSlots() async {
  try {
    final sp = await SharedPreferences.getInstance();
    final slots = {
      for (final k in sp.getKeys())
        if (k.startsWith(kSlotPrefix) && k.endsWith('.state'))
          k.substring(kSlotPrefix.length, k.length - '.state'.length),
    };
    return (accounts: slots.where((s) => s != kGuestSlot).length, guest: slots.contains(kGuestSlot));
  } catch (_) {
    return (accounts: 0, guest: false);
  }
}
