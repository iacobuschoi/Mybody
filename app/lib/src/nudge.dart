/* =============================================================================
 * nudge.dart — 간식으로 단백질 채우기 알림
 *
 * "오늘 단백질 40g 남았는데 저녁은 먹었다" — 그때 사람은 잊습니다. 간식
 * 시간(오후 3시 반 · 저녁 8시 반)에 한 번, 남은 단백질과 그걸 채울 간식을
 * 폰이 알려 줍니다.
 *
 * **서버가 아니라 폰이 예약합니다.** 앱이 켜져 있을 때(켤 때, 먹은 것을
 * 적을 때) 남은 양을 계산해 다음 간식 시각에 알림을 걸어 둡니다. 서버는
 * 식단을 모르고, 알아서도 안 됩니다. 단백질이 15g 안 남았으면 안 웁니다 —
 * 매일 오는 알림은 독려가 아니라 잔소리입니다.
 *
 * **끼니 기록 알림** — 10시 아침 · 13시 점심 · 19시 저녁에 "○○ 메뉴를
 * 기록해주세요!". 그 끼니를 오늘 이미 적었으면 안 웁니다. 폰은 알림이 울릴
 * 때 앱 코드를 돌리지 않으므로 반복 알림 하나로는 "적었으면 건너뛰기" 가
 * 안 됩니다. 그래서 앞으로 [kMealDays]일치를 하나씩 걸어 두고, 앱을 켜거나
 * 기록할 때마다 다시 겁니다(오늘 적은 끼니는 빼고). 앱을 [kMealDays]일 넘게
 * 안 열면 알림도 멈춥니다 — 안 쓰는 사람에게 매일 세 번은 잔소리입니다.
 *
 * **운동 알림** — 헬스를 하기로 한 날 저녁 8시 반까지 체크가 없으면 한 번
 * "오늘 헬스를 못 갔나요?" 하고, 대신 집에서 15분 맨몸 운동을 권합니다. 누르면
 * 그 날짜의 맨몸 운동 화면으로 갑니다(payload 'workout:bodyweight:YYYY-MM-DD').
 * 끼니 알림과 같은 이유로 14일치를 미리 걸어 두고, 운동을 기록하면(done)
 * 다음 예약에서 그 날이 빠집니다. 번호는 2000 부터([kWorkoutIdBase]).
 *
 * **아이폰** — 예전 init 에는 안드로이드 설정만 있어서 아이폰에서는 플러그인이
 * "iOS settings must be set" 로 실패했고, 그 예외를 삼켜 간식 알림 · 운동 독촉까지
 * 전부 조용히 꺼져 있었습니다. 권한은 켜자마자 묻지 않고, 처음 설정을 마친
 * 뒤(onboarded) 알림이 하나라도 켜져 있을 때 한 번 묻습니다.
 * ========================================================================== */
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:mybody_core/mybody_core.dart' as core;
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'app_state.dart';
import 'ui/fmt.dart';

/// 간식 알림 시각 (시, 분). 오후 간식과 저녁 뒤.
const kSnackSlots = [(15, 30), (20, 30)];

/// 이보다 덜 남았으면 안 웁니다.
const kSnackMinProteinG = 15.0;

/// 다음 알림 — 시각과 문구. 없으면 null (단백질이 충분하거나 오늘 시각이 다 지남).
({DateTime at, String title, String body})? planSnackNudge({
  required double remainP,
  required double remainKcal,
  required double remainC,
  required double remainF,
  required DateTime now,
  List<String> avoid = const [],
}) {
  if (!(remainP >= kSnackMinProteinG)) return null;
  DateTime? at;
  for (final s in kSnackSlots) {
    final t = DateTime(now.year, now.month, now.day, s.$1, s.$2);
    if (t.isAfter(now)) {
      at = t;
      break;
    }
  }
  if (at == null) return null;

  /* 무엇을 먹을지까지 — 엔진의 간식 추천에서 하나. 오늘 먹은 것과 남은
     탄단지에 맞춘 것. */
  final res = core.suggestSnack({
    'remainP': remainP, 'remainKcal': remainKcal,
    'remainC': remainC, 'remainF': remainF,
    'avoid': avoid, 'limit': 1,
  });
  final opts = (res['options'] as List?) ?? const [];
  String body;
  if (opts.isNotEmpty) {
    final o = (opts.first as Map).cast<String, Object?>();
    final names = ((o['items'] as List?) ?? const [])
        .map((x) => '${(x as Map)['name']} ${core.suggestPortionText(x.cast<String, Object?>())}'.trim())
        .join(' + ');
    body = '단백질 ${n0(remainP)}g 남았어요. 간식으로 $names (단백질 ${n0(o['totalP'])}g) 어때요?';
  } else {
    body = '단백질 ${n0(remainP)}g 남았어요. 단백질바·그릭요거트·우유로 채워 보세요.';
  }
  return (at: at, title: '간식으로 단백질 채우기', body: body);
}

/// 끼니 알림 시각 (시, 끼니 이름). 끼니 이름은 식단 기록의 meal 값과 같습니다.
const kMealSlots = [(10, '아침'), (13, '점심'), (19, '저녁')];

/// 몇 일치를 미리 걸어 두는가. 아이폰은 예약 알림을 64개까지만 받습니다(3×14=42).
const kMealDays = 14;

/// 끼니 알림 id 의 시작. 간식(7) · 운동 독촉(1000~1999)과 겹치지 않게.
const kMealIdBase = 100;

/// 앞으로 울릴 끼니 알림들. 오늘 이미 지난 시각과 오늘 이미 적은 끼니는 뺍니다.
List<({int id, DateTime at, String meal, String title, String body})> planMealReminders({
  required DateTime now,
  Set<String> loggedToday = const {},
  int days = kMealDays,
}) {
  final out = <({int id, DateTime at, String meal, String title, String body})>[];
  for (var d = 0; d < days; d++) {
    for (var i = 0; i < kMealSlots.length; i++) {
      final (hour, meal) = kMealSlots[i];
      /* DateTime(…, 일 + d, …) 는 달 · 해 넘김을 알아서 맞춥니다. */
      final at = DateTime(now.year, now.month, now.day + d, hour);
      if (d == 0 && (!at.isAfter(now) || loggedToday.contains(meal))) continue;
      out.add((
        id: kMealIdBase + d * kMealSlots.length + i,
        at: at,
        meal: meal,
        title: '$meal 메뉴를 기록해주세요!',
        body: '먹은 것을 적어 두면 오늘 남은 칼로리 · 단백질을 바로 계산해 드려요.',
      ));
    }
  }
  return out;
}

/// 알림을 눌러 앱이 열렸을 때 갈 곳('food', 끼니 알림은 'food:아침' 처럼 끼니까지).
/// 셸이 듣고 그 탭으로 갑니다.
final ValueNotifier<String?> notificationRoute = ValueNotifier<String?>(null);

/// 방금 누른 끼니 알림 — 식단 화면의 기본 끼니가 이걸 따릅니다([mealFromReminder]).
/// 10시 「아침 메뉴를 기록해주세요!」 를 누르고 10시 5분에 적으면 시각으로는 점심이라,
/// 아침이 점심으로 저장되고 13시 점심 알림까지 빠졌습니다.
({String meal, DateTime at})? tappedMealReminder;

/// 끼니 알림을 누른 지 3시간 안이면 그 끼니. 아니면 null.
String? mealFromReminder([DateTime? now]) {
  final r = tappedMealReminder;
  if (r == null) return null;
  final n = now ?? DateTime.now();
  if (n.isBefore(r.at) || n.difference(r.at) > const Duration(hours: 3)) return null;
  return r.meal;
}

class SnackNudge {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;
  static bool _askedIos = false;
  static const _id = 7;

  /// 플러그인·시간대 준비. 못 되면 조용히 꺼진 채로 둡니다 — 알림 때문에
  /// 앱이 안 뜨면 안 됩니다.
  static Future<void> init() async {
    try {
      tzdata.initializeTimeZones();
      try {
        final info = await FlutterTimezone.getLocalTimezone();
        tz.setLocalLocation(tz.getLocation(info.identifier));
      } catch (_) {/* 모르면 UTC 로 두되, 아래에서 폰 시각 그대로 씁니다 */}
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          /* 켜자마자 권한을 묻지 않습니다 — askPermission 이 처음 설정을 마친 뒤에 묻습니다. */
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestSoundPermission: false,
            requestBadgePermission: false,
          ),
        ),
        onDidReceiveNotificationResponse: (r) {
          if (r.payload != null && r.payload!.isNotEmpty) notificationRoute.value = r.payload;
        },
      );
      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      /* 알림을 눌러 앱이 새로 켜진 경우 — 위 콜백은 안 불립니다. */
      try {
        final launch = await _plugin.getNotificationAppLaunchDetails();
        final payload = launch?.notificationResponse?.payload;
        if ((launch?.didNotificationLaunchApp ?? false) && payload != null && payload.isNotEmpty) {
          notificationRoute.value = payload;
        }
      } catch (_) {}
      _ready = true;
    } catch (_) {
      _ready = false;
    }
  }

  /// 아이폰 알림 권한 — 처음 설정을 마친 뒤, 알림이 하나라도 켜져 있을 때 한 번.
  /// 이미 답했으면 아이폰이 다시 묻지 않고 지금 상태만 돌려줍니다.
  static Future<void> askPermission(AppState app) async {
    if (!_ready || _askedIos) return;
    if (app.state['onboarded'] != true) return;
    final settings = (app.state['settings'] as Map?) ?? const {};
    if (settings['mealReminder'] == false && settings['snackNudge'] == false &&
        settings['workoutReminder'] == false) {
      return;
    }
    _askedIos = true;
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, sound: true);
    } catch (_) {}
  }

  /// 지금 바로 하나 — 친구의 운동 독촉 같은 것. 못 띄워도 조용히.
  static Future<void> showNow({required int id, required String title, required String body}) async {
    if (!_ready) return;
    try {
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'friends', '친구 알림',
            channelDescription: '친구가 보낸 운동 독촉',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
        ),
      );
    } catch (_) {}
  }

  /// 지금 상태로 다음 알림을 다시 겁니다. 늘 먼저 지우고 — 남은 양이
  /// 바뀌었으면 옛 문구가 울리면 안 됩니다.
  static Future<void> reschedule(AppState app) async {
    if (!_ready) return;
    try {
      await _plugin.cancel(id: _id);
      final settings = (app.state['settings'] as Map?) ?? const {};
      if (settings['snackNudge'] == false) return;
      await askPermission(app);
      final plan = app.state['plan'];
      final macros = plan is Map ? plan['macros'] : null;
      if (macros is! Map) return;
      final target = macros.cast<String, Object?>();
      final totals = app.store.dayTotals();
      final avoid = <String>{
        for (final l in app.store.logsForDate())
          for (final it in ((l['items'] as List?) ?? const [])) '${(it as Map)['name']}',
      }.toList();
      final n = planSnackNudge(
        remainP: core.jsToNumber(target['proteinG']) - core.jsToNumber(totals['p']),
        remainKcal: core.jsToNumber(target['intakeKcal']) - core.jsToNumber(totals['kcal']),
        remainC: core.jsToNumber(target['carbG']) - core.jsToNumber(totals['c']),
        remainF: core.jsToNumber(target['fatG']) - core.jsToNumber(totals['f']),
        now: DateTime.now(),
        avoid: avoid,
      );
      if (n == null) return;
      await _plugin.zonedSchedule(
        id: _id,
        title: n.title,
        body: n.body,
        payload: 'food',
        scheduledDate: tz.TZDateTime.from(n.at, tz.local),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'snack', '간식 단백질 알림',
            channelDescription: '그날 단백질이 남았을 때 간식 시간에 한 번',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
        ),
        /* 몇 분 늦어도 되는 알림입니다 — 정확한 알람 권한을 안 받습니다. */
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (_) {/* 알림은 편의입니다. 실패해도 앱은 그대로 */}
  }
}

/// 끼니 기록 알림 — [planMealReminders] 를 폰에 겁니다. 플러그인은 [SnackNudge] 것을 같이 씁니다.
class MealReminder {
  /// 마지막으로 다 건 것 — 같으면 다시 안 겁니다. 저장할 때마다 42개를 다시 거는 것은
  /// 낭비라서, 날짜 · 오늘 적은 끼니 · 설정이 바뀔 때만 겁니다.
  static String? _last;

  /// 한 번에 하나씩 — 켤 때와 저장할 때 두 번이 겹치면, 먼저 시작한 쪽이 뒤에 지운
  /// 알림(오늘 적은 점심)을 다시 걸었습니다.
  static Future<void> _chain = Future<void>.value();

  static Future<void> reschedule(AppState app) {
    final run = _chain.then((_) => _run(app));
    _chain = run.catchError((_) {});
    return run;
  }

  static Future<void> _run(AppState app) async {
    if (!SnackNudge._ready) return;
    final plugin = SnackNudge._plugin;
    final settings = (app.state['settings'] as Map?) ?? const {};
    final on = settings['mealReminder'] != false && app.state['onboarded'] == true;
    final logged = <String>{for (final l in app.store.logsForDate()) '${l['meal']}'};
    var plan = on
        ? planMealReminders(now: DateTime.now(), loggedToday: logged)
        : const <({int id, DateTime at, String meal, String title, String body})>[];
    /* 시각까지 넣습니다 — 10시가 지나면 오늘 아침 알림이 빠져야 합니다. */
    final sig = [for (final r in plan) '${r.id}@${r.at.toIso8601String()}'].join(',');
    if (sig == _last) return;
    if (on) {
      await SnackNudge.askPermission(app);
      /* 권한을 묻는 동안 시각이 지났을 수 있습니다. */
      plan = [for (final r in plan) if (r.at.isAfter(DateTime.now())) r];
    }

    /* 안드로이드 7~11 은 며칠 뒤로 건 「정확하지 않은」 알람을 창을 크게 잡고 서로
       묶어서, 10 · 13시 알림이 19시에 같이 오거나 다음 날로 밀렸습니다. 그 판들은
       정확한 알람에 권한이 필요 없어서(플러그인이 true), 되면 정확하게 겁니다.
       12 이상은 권한이 없으면 정확하지 않은 알람이고, 늦어도 한 시간 안입니다. */
    var mode = AndroidScheduleMode.inexactAllowWhileIdle;
    try {
      final android = plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (android != null && (await android.canScheduleExactNotifications() ?? false)) {
        mode = AndroidScheduleMode.exactAllowWhileIdle;
      }
    } catch (_) {}

    /* 새것을 먼저 겁니다(같은 번호면 바뀜) — 다 지운 뒤에 걸다가 하나가 실패하면
       알림이 하나도 안 남았습니다. 그다음 계획에 없는 번호만 지웁니다. */
    var ok = true;
    final keep = <int>{};
    for (final r in plan) {
      if (!r.at.isAfter(DateTime.now())) continue;
      try {
        await plugin.zonedSchedule(
          id: r.id,
          title: r.title,
          body: r.body,
          payload: 'food:${r.meal}',
          scheduledDate: tz.TZDateTime.from(r.at, tz.local),
          notificationDetails: NotificationDetails(
            android: AndroidNotificationDetails(
              'meals', '끼니 기록 알림',
              channelDescription: '10시 · 13시 · 19시에 아침 · 점심 · 저녁 메뉴 기록을 알려 줍니다',
              importance: Importance.defaultImportance,
              priority: Priority.defaultPriority,
              /* 폰이 꺼져 있다 켜지면 안드로이드는 놓친 알림을 그 자리에서 띄웁니다.
                 원래 시각을 보여 주고, 세 시간이 지나면 스스로 사라지게 합니다. */
              when: r.at.millisecondsSinceEpoch,
              showWhen: true,
              timeoutAfter: const Duration(hours: 3).inMilliseconds,
            ),
          ),
          androidScheduleMode: mode,
        );
        keep.add(r.id);
      } catch (_) {
        ok = false;
      }
    }
    for (var id = kMealIdBase; id < kMealIdBase + kMealDays * kMealSlots.length; id++) {
      if (keep.contains(id)) continue;
      try {
        await plugin.cancel(id: id);
      } catch (_) {
        ok = false;
      }
    }
    _last = ok ? sig : null;   // 실패가 있으면 다음에 다시
  }
}

/* --- 운동 알림 ---------------------------------------------------------------
 *
 * 헬스를 하기로 한 날인데 저녁 8시 반까지 기록이 없으면 한 번 묻습니다. 그리고
 * 대안을 같이 줍니다 — "못 갔네요" 로 끝나는 알림은 죄책감만 남기고, 죄책감은
 * 앱을 지우게 합니다. 집에서 15분 맨몸 운동을 하면 오늘은 지킨 날입니다.
 * -------------------------------------------------------------------------- */

/// 운동 알림 시각 — 저녁을 먹고 나서도 15분은 남는 시각. planWorkoutReminders 의 기본값이라
/// 여기만 바꾸면 됩니다 (레코드의 $1 은 기본값 자리에서 못 써서 둘로 둡니다).
const kWorkoutHour = 20;
const kWorkoutMinute = 30;
const kWorkoutSlot = (kWorkoutHour, kWorkoutMinute);

/// 며칠치를 미리 걸어 두는가. 끼니 알림과 같은 이유(아이폰 64개 한도)로 14일.
const kWorkoutDays = 14;

/// 운동 알림 id 의 시작. 간식(7) · 끼니(100~141) · 운동 독촉(1000~1999)과 겹치지 않게.
const kWorkoutIdBase = 2000;

const _workoutTitle = '오늘 헬스를 못 갔나요?';
const _workoutBody = '집에서 15분 맨몸 운동으로 오늘 계획을 지켜요 — 종목과 횟수를 골라 뒀어요.';

String _dateKeyOf(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// 알림 payload — 셸이 [parseWorkoutPayload] 로 되읽습니다.
String workoutPayload(String type, String dateKey) => 'workout:$type:$dateKey';

/// `workout:(gym|cardio|bodyweight):YYYY-MM-DD` → 종류와 날짜. 모양이 다르면 null.
({String type, String dateKey})? parseWorkoutPayload(String payload) {
  final m = RegExp(r'^workout:(gym|cardio|bodyweight):(\d{4}-\d{2}-\d{2})$').firstMatch(payload);
  if (m == null) return null;
  return (type: m.group(1)!, dateKey: m.group(2)!);
}

/// 앞으로 울릴 운동 알림들. [schedule] 은 state['schedule'] — 날짜 키마다
/// {plan: [...], done: {...}}. 헬스를 계획했고 아직 체크가 없는 날만, 하루에
/// 하나. 오늘은 시각이 아직 안 지났을 때만.
List<({int id, DateTime at, String dateKey, String title, String body})> planWorkoutReminders({
  required DateTime now,
  required Map<String, Object?> schedule,
  int days = kWorkoutDays,
  int hour = kWorkoutHour,
  int minute = kWorkoutMinute,
}) {
  final out = <({int id, DateTime at, String dateKey, String title, String body})>[];
  for (var d = 0; d < days; d++) {
    /* DateTime(…, 일 + d, …) 는 달 · 해 넘김을 알아서 맞춥니다. */
    final at = DateTime(now.year, now.month, now.day + d, hour, minute);
    if (d == 0 && !at.isAfter(now)) continue;
    final key = _dateKeyOf(at);
    final e = schedule[key];
    if (e is! Map) continue;
    final plan = (e['plan'] as List?) ?? const [];
    final done = (e['done'] as Map?) ?? const {};
    if (!plan.contains('gym') || core.jsTruthy(done['gym'])) continue;
    out.add((id: kWorkoutIdBase + d, at: at, dateKey: key, title: _workoutTitle, body: _workoutBody));
  }
  return out;
}

/// 운동 알림 — [planWorkoutReminders] 를 폰에 겁니다. 플러그인은 [SnackNudge] 것을
/// 같이 쓰고, 거는 방식은 [MealReminder] 와 같습니다.
class WorkoutReminder {
  /// 마지막으로 다 건 것 — 같으면 다시 안 겁니다. 일정 · 체크 · 설정이 바뀔 때만.
  static String? _last;

  /// 한 번에 하나씩 — 켤 때와 저장할 때가 겹치면 먼저 시작한 쪽이 뒤에 지운 것을 되살립니다.
  static Future<void> _chain = Future<void>.value();

  static Future<void> reschedule(AppState app) {
    final run = _chain.then((_) => _run(app));
    _chain = run.catchError((_) {});
    return run;
  }

  static Future<void> _run(AppState app) async {
    if (!SnackNudge._ready) return;
    final plugin = SnackNudge._plugin;
    final settings = (app.state['settings'] as Map?) ?? const {};
    final on = settings['workoutReminder'] != false && app.state['onboarded'] == true;
    final schedule = ((app.state['schedule'] as Map?) ?? const {}).cast<String, Object?>();
    var plan = on
        ? planWorkoutReminders(now: DateTime.now(), schedule: schedule)
        : const <({int id, DateTime at, String dateKey, String title, String body})>[];
    /* 시각까지 넣습니다 — 8시 반이 지나면 오늘 것이 빠져야 합니다. */
    final sig = [for (final r in plan) '${r.id}@${r.at.toIso8601String()}'].join(',');
    if (sig == _last) return;
    if (on) {
      await SnackNudge.askPermission(app);
      /* 권한을 묻는 동안 시각이 지났을 수 있습니다. */
      plan = [for (final r in plan) if (r.at.isAfter(DateTime.now())) r];
    }

    /* 안드로이드 7~11 은 며칠 뒤로 건 「정확하지 않은」 알람을 묶어서 다음 날로
       밀었습니다. 그 판들은 정확한 알람에 권한이 필요 없어서, 되면 정확하게 겁니다. */
    var mode = AndroidScheduleMode.inexactAllowWhileIdle;
    try {
      final android = plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (android != null && (await android.canScheduleExactNotifications() ?? false)) {
        mode = AndroidScheduleMode.exactAllowWhileIdle;
      }
    } catch (_) {}

    /* 새것을 먼저 겁니다(같은 번호면 바뀜). 그다음 계획에 없는 번호만 지웁니다 —
       운동을 기록한 날이 여기서 빠집니다. */
    var ok = true;
    final keep = <int>{};
    for (final r in plan) {
      if (!r.at.isAfter(DateTime.now())) continue;
      try {
        await plugin.zonedSchedule(
          id: r.id,
          title: r.title,
          body: r.body,
          payload: workoutPayload('bodyweight', r.dateKey),
          scheduledDate: tz.TZDateTime.from(r.at, tz.local),
          notificationDetails: NotificationDetails(
            android: AndroidNotificationDetails(
              'workout', '운동 알림',
              channelDescription: '헬스를 계획한 날 저녁 8시 반, 아직 안 갔으면 집에서 하는 15분 맨몸 운동을 권합니다',
              importance: Importance.defaultImportance,
              priority: Priority.defaultPriority,
              /* 놓친 알림은 원래 시각을 보여 주고, 세 시간이 지나면 스스로 사라집니다. */
              when: r.at.millisecondsSinceEpoch,
              showWhen: true,
              timeoutAfter: const Duration(hours: 3).inMilliseconds,
            ),
          ),
          androidScheduleMode: mode,
        );
        keep.add(r.id);
      } catch (_) {
        ok = false;
      }
    }
    for (var id = kWorkoutIdBase; id < kWorkoutIdBase + kWorkoutDays; id++) {
      if (keep.contains(id)) continue;
      try {
        await plugin.cancel(id: id);
      } catch (_) {
        ok = false;
      }
    }
    _last = ok ? sig : null;   // 실패가 있으면 다음에 다시
  }
}
