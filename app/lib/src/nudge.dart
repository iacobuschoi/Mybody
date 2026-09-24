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

/// 알림을 눌러 앱이 열렸을 때 갈 곳('food' 등). 셸이 듣고 그 탭으로 갑니다.
final ValueNotifier<String?> notificationRoute = ValueNotifier<String?>(null);

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
    if (settings['mealReminder'] == false && settings['snackNudge'] == false) return;
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
  /// 마지막으로 건 것 — 같으면 다시 안 겁니다. 저장할 때마다 42개를 지우고 다시
  /// 거는 것은 낭비라서, 날짜 · 오늘 적은 끼니 · 설정이 바뀔 때만 겁니다.
  static String? _last;

  static Future<void> reschedule(AppState app) async {
    if (!SnackNudge._ready) return;
    try {
      final settings = (app.state['settings'] as Map?) ?? const {};
      final on = settings['mealReminder'] != false && app.state['onboarded'] == true;
      final now = DateTime.now();
      final logged = <String>{for (final l in app.store.logsForDate()) '${l['meal']}'};
      final plan = on ? planMealReminders(now: now, loggedToday: logged) : const <({int id, DateTime at, String meal, String title, String body})>[];
      /* 시각까지 넣습니다 — 10시가 지나면 오늘 아침 알림이 빠져야 합니다. */
      final sig = [for (final r in plan) '${r.id}@${r.at.toIso8601String()}'].join(',');
      if (sig == _last) return;
      for (var id = kMealIdBase; id < kMealIdBase + kMealDays * kMealSlots.length; id++) {
        await SnackNudge._plugin.cancel(id: id);
      }
      _last = sig;
      if (!on) return;
      await SnackNudge.askPermission(app);
      for (final r in plan) {
        await SnackNudge._plugin.zonedSchedule(
          id: r.id,
          title: r.title,
          body: r.body,
          payload: 'food',
          scheduledDate: tz.TZDateTime.from(r.at, tz.local),
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              'meals', '끼니 기록 알림',
              channelDescription: '10시 · 13시 · 19시에 아침 · 점심 · 저녁 메뉴 기록을 알려 줍니다',
              importance: Importance.defaultImportance,
              priority: Priority.defaultPriority,
            ),
          ),
          /* 몇 분 늦어도 되는 알림입니다 — 정확한 알람 권한을 안 받습니다. */
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }
    } catch (_) {
      _last = null;   // 다음에 다시 시도
    }
  }
}
