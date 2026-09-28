/* =============================================================================
 * fake_accounts.dart — 계정 여럿을 드는 가짜 서버와, main.dart 처럼 엮은 한 벌(시험 도우미)
 *
 * 피드백 52(계정 A 의 기록이 새 계정 B 로 샌 것)를 보는 시험들이 같이 씁니다
 * (account_switch_test · settings_logout_test · signup_test · cloud_test · wipe_test).
 * 서버는 server/db.js 와 같은 규칙으로 계정마다 따로 듭니다 — 기록(state/main)은 계정별 한 줄,
 * 옛 시각으로 올린 것은 안 받고, 사본에 실린 주인(syncMeta.owner · payload.owner)이 토큰의
 * 계정과 다르면 409 로 거절합니다. 누가 무엇을 어느 토큰으로 보냈는지 다 적습니다.
 * ========================================================================== */
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mybody/src/api.dart';
import 'package:mybody/src/app_state.dart';
import 'package:mybody/src/cloud.dart';
import 'package:mybody/src/local_owner.dart';
import 'package:mybody/src/news_store.dart';
import 'package:mybody/src/publish.dart';
import 'package:mybody/src/scope.dart';
import 'package:mybody/src/screens/account.dart' show kHealthConsentVersion;
import 'package:mybody/src/sync_queue.dart';
import 'package:mybody/src/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeUser {
  FakeUser(this.id, this.handle);
  final String id;
  final String handle;
  Map<String, Object?>? state;
  String at = '';
  final snapshots = <Map<String, Object?>>[];
  final pokes = <Map<String, Object?>>[];
  /// 이 계정에 온 친구 요청 — GET /friends 의 incoming.
  final incoming = <Map<String, Object?>>[];
  /// 옛 판 동의로 가입한 계정 — /me 가 옛 판을 말해 동의 다시 묻기가 뜹니다.
  bool oldConsent = false;
  List<Object?> get scanIds => [for (final s in (state?['scans'] as List?) ?? const []) (s as Map)['id']];
}

/// 서버 대신. 부른 길은 [calls] 에 'METHOD /path @uid' 로 적습니다(로그인 없으면 @-).
class FakeAccounts {
  final users = <String, FakeUser>{};
  final tokens = <String, String>{};
  final calls = <String>[];
  /// 받은 머리(X-Mybody-App) — 모든 요청에 붙는지 봅니다.
  final appHeaders = <String?>[];
  bool down = false;
  /// 받아 오기는 되고 올리기(기록 · 요약 · 친구 일)만 망 오류 — "못 보낸 일이 큐에 남은" 상태를 만듭니다.
  bool failWrites = false;
  /// 기록 사본 올리기를 모두 409(다른 계정의 기록)로 — 앱이 409 를 받았을 때를 봅니다.
  bool conflictAll = false;
  /// 요청 하나를 붙잡습니다 — '메서드 경로'(예: 'POST /friends/accept') → 풀어 줄 때의 답. 받은 값이
  /// 상태 번호면 그 번호로 끝내고(503 등), null 이면 여느 때처럼 처리합니다. 한 번 쓰면 빠집니다.
  /// 느린 망에 걸린 요청이 끝나기 전에 계정을 바꾸는 시험이 씁니다.
  final holds = <String, Completer<int?>>{};
  int _n = 0;

  FakeUser add(String handle) => users['u_$handle'] = FakeUser('u_$handle', handle);
  FakeUser? byHandle(String h) => users.values.where((u) => u.handle == h).firstOrNull;
  FakeUser user(String handle) => byHandle(handle)!;

  /// 그 계정의 새 토큰 — 시험이 로그인된 기기를 바로 세울 때.
  String login(String handle) {
    final t = 'tok${++_n}';
    tokens[t] = user(handle).id;
    return t;
  }

  static String _iso(String s) => CloudSync.isoMs(DateTime.parse(s));

  http.Response _json(Object body, [int status = 200]) => http.Response.bytes(
      utf8.encode(jsonEncode(body)), status,
      headers: {'content-type': 'application/json; charset=utf-8'});

  Map<String, Object?> _pub(FakeUser u) => {
        'id': u.id, 'handle': u.handle, 'displayName': u.handle,
        'healthConsentVersion': u.oldConsent ? '2026-09-01' : kHealthConsentVersion,
        'healthConsentCurrent': kHealthConsentVersion,
        'inviteCode': 'CODE${u.handle.toUpperCase()}',
      };

  Map<String, Object?> _session(FakeUser u, {bool recovery = false}) {
    final t = 'tok${++_n}';
    tokens[t] = u.id;
    return {'ok': true, 'token': t, 'user': _pub(u), if (recovery) 'recoveryCode': 'RC-${u.handle}'};
  }

  /// 그 요청에서 이 계정의 기록 · 요약을 받은 것들(누가 보냈든 그 계정 행에 들어간 것).
  List<String> writesTo(String handle) {
    final id = user(handle).id;
    return [for (final c in calls) if (c.endsWith('@$id') && (c.startsWith('POST /sync/push') || c.startsWith('POST /snapshots'))) c];
  }

  MockClient get client => MockClient((req) async {
        if (down) return http.Response('', 503);
        final p = req.url.path.replaceFirst('/api', '');
        final auth = req.headers['Authorization'] ?? req.headers['authorization'] ?? '';
        final tok = auth.startsWith('Bearer ') ? auth.substring(7) : null;
        final uid = tok == null ? null : tokens[tok];
        final me = uid == null ? null : users[uid];
        calls.add('${req.method} $p @${uid ?? '-'}');
        appHeaders.add(req.headers['X-Mybody-App'] ?? req.headers['x-mybody-app']);
        final hold = holds.remove('${req.method} $p');
        if (hold != null) {
          final status = await hold.future;
          if (status != null) return http.Response('', status);
        }
        Map<String, dynamic> body() {
          try {
            return (jsonDecode(req.body) as Map).cast<String, dynamic>();
          } catch (_) {
            return {};
          }
        }

        switch ((req.method, p)) {
          case ('GET', '/health'):
            return _json({'ok': true, 'openSignup': true});
          case ('POST', '/auth/signup'):
            final h = '${body()['handle']}';
            if (byHandle(h) != null) return _json({'ok': false, 'reason': '이미 있는 아이디입니다'}, 400);
            return _json(_session(add(h), recovery: true));
          case ('POST', '/auth/signin'):
          case ('POST', '/auth/recover'):
            final u = byHandle('${body()['handle']}');
            if (u == null) return _json({'ok': false, 'reason': '아이디나 비밀번호가 틀렸습니다'}, 401);
            return _json(_session(u));
          case ('POST', '/auth/signout'):
            if (tok != null) tokens.remove(tok);
            return _json({'ok': true});
        }
        if (failWrites && (p == '/sync/push' || p == '/snapshots' || p.startsWith('/friends/') ||
            p.startsWith('/share/'))) {
          return http.Response('', 503);
        }
        if (me == null) {
          if (p == '/health') return _json({'ok': true});
          return _json({'ok': false, 'reason': '다시 로그인해야 합니다'}, 401);
        }
        switch ((req.method, p)) {
          case ('GET', '/me'):
            return _json({'ok': true, 'user': _pub(me)});
          case ('POST', '/me/consent'):
            me.oldConsent = false;
            return _json({'ok': true, 'user': _pub(me)});
          case ('DELETE', '/me'):
            users.remove(me.id);
            tokens.removeWhere((_, v) => v == me.id);
            return _json({'ok': true});
          case ('POST', '/sync/push'):
            final rec = ((body()['records'] as List?) ?? const []).first as Map;
            final payload = (rec['payload'] as Map).cast<String, Object?>();
            final owner = (payload['syncMeta'] as Map?)?['owner'];
            if (conflictAll || (owner != null && owner != me.id)) {
              return _json({'ok': false, 'reason': '다른 계정의 기록입니다'}, 409);
            }
            final up = _iso('${rec['updatedAt']}');
            if (me.at.isEmpty || up.compareTo(me.at) >= 0) {
              me.state = payload;
              me.at = up;
            }
            return _json({'ok': true, 'accepted': 1, 'rejected': []});
          case ('GET', '/sync/pull'):
            final recs = me.state == null
                ? []
                : [{'kind': 'state', 'id': 'main', 'updatedAt': me.at, 'deleted': false, 'payload': me.state}];
            return _json({'ok': true, 'records': recs, 'cursor': '', 'hasMore': false});
          case ('POST', '/snapshots'):
            final b = body();
            final payload = (b['payload'] as Map?)?.cast<String, Object?>() ?? {};
            if (payload['owner'] != null && payload['owner'] != me.id) {
              return _json({'ok': false, 'reason': '다른 계정의 기록입니다'}, 409);
            }
            me.snapshots.add(payload);
            return _json({'ok': true});
          case ('GET', '/pokes'):
            final out = [...me.pokes];
            me.pokes.clear();
            return _json({'ok': true, 'pokes': out});
          case ('GET', '/friends'):
            return _json({'ok': true, 'friends': {'accepted': [], 'incoming': me.incoming, 'outgoing': [], 'blocked': []}});
          case ('GET', '/share-defaults'):
            return _json({'ok': true, 'defaults': {}});
        }
        if (p.startsWith('/friends/') || p.startsWith('/share/')) return _json({'ok': true});
        return _json({'ok': false, 'reason': '그런 경로가 없습니다'}, 404);
      });
}

/// main.dart 처럼 엮은 한 벌 — Api · 큐 · AppState · 계정 칸 · 주간 요약 · 동기화.
class Rig {
  Rig._(this.server, this.api, this.queue, this.app, this.slots, this.cloud);
  final FakeAccounts server;
  final Api api;
  final SyncQueue queue;
  final AppState app;
  final AccountSlots slots;
  final CloudSync cloud;

  /// [prefs] 로 기기에 적힌 것부터 시작합니다(0.2.19 모양 등). [signedInAs] 면 그 계정 토큰으로.
  /// [base] 는 이 기기가 쓰는 서버 주소 — 앱에 박힌 주소가 바뀐 판 · 주소를 바꾼 기기를 흉내 냅니다.
  static Future<Rig> boot(FakeAccounts server,
      {Map<String, Object> prefs = const {},
      String? signedInAs,
      bool withUid = true,
      Duration debounce = Duration.zero,
      String base = 'https://x.test'}) async {
    final init = <String, Object>{...prefs};
    if (signedInAs != null) {
      final tok = init['mybody.token.v1'] = server.login(signedInAs);
      if (withUid) init['mybody.token.uid.v1'] = Api.uidRecordOf(tok, server.user(signedInAs).id);
    }
    SharedPreferences.setMockInitialValues(init);
    final sp = await SharedPreferences.getInstance();
    final api = Api(baseUrl: base, client: server.client);
    await api.loadToken();
    final queue = SyncQueue(api: api, storage: PrefsQueue(sp));
    final app = await AppState.boot();
    final slots = AccountSlots(app: app, queue: queue, flushLimit: const Duration(seconds: 2));
    await slots.migrate(api);
    api.accounts = slots;
    wirePublishing(app, api, queue);
    final cloud = CloudSync(app: app, api: api, queue: queue, debounce: debounce)..wire();
    slots.cloud = cloud;
    return Rig._(server, api, queue, app, slots, cloud);
  }

  /// 다시 보내기 타이머 · 동기화를 남기지 않습니다(위젯 시험은 끝날 때 남은 타이머를 탓합니다).
  void dispose() {
    queue.clear();
    queue.dispose();
    cloud.dispose();
  }

  Widget host(Widget child) => Scope(
        state: app,
        api: api,
        queue: queue,
        cloud: cloud,
        slots: slots,
        onServerChange: (_) async {},
        child: MaterialApp(theme: mbLight(), home: child),
      );

  List<Object?> get scanIds => app.store.sortedScans().map((s) => s['id']).toList();
}

/// 계정 A 가 쓰던 기록 — 주인 폰에 뜬 그 모양(9/19 86.7kg · 목표 · 상체 A).
Map<String, Object?> recordsOfA({String scanId = 'scan-1758240000000', String? photoId}) => {
      'profile': {'sex': 'male', 'age': 22, 'heightCm': 187, 'activityLevel': 'moderate',
          'trainingAge': 'novice', 'daysPerWeek': 4},
      'onboarded': true,
      'disclaimerAccepted': true,
      'goal': {'weightKg': 80.5, 'smmKg': 39.0, 'bfmKg': 12.0},
      'scans': [
        {'id': scanId, 'weightKg': 86.7, 'smmKg': 38.0, 'bfmKg': 20.0, 'pbfPct': 23.1,
         'measuredAt': '2026-09-19T00:00:00.000Z', if (photoId != null) 'photoId': photoId},
      ],
      'settings': {'theme': 'auto', 'units': 'metric', 'checkinEveryWeeks': 1, 'defaultLevel': 'mid',
          'testerWelcomeSeen': true},
    };

/// 지금(밀리초까지 — 서버가 적는 꼴). [minutes] 만큼 뒤로.
String isoNow({int minutes = 0}) => CloudSync.isoMs(DateTime.now().add(Duration(minutes: minutes)));

/// 비동기 일이 한 바퀴 돌게(가짜 서버는 마이크로태스크로 답합니다).
Future<void> settle([int ms = 150]) => Future<void>.delayed(Duration(milliseconds: ms));
