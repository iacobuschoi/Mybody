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
 * ========================================================================== */
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

class SnackNudge {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;
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
            android: AndroidInitializationSettings('@mipmap/ic_launcher')),
      );
      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      _ready = true;
    } catch (_) {
      _ready = false;
    }
  }

  /// 지금 상태로 다음 알림을 다시 겁니다. 늘 먼저 지우고 — 남은 양이
  /// 바뀌었으면 옛 문구가 울리면 안 됩니다.
  static Future<void> reschedule(AppState app) async {
    if (!_ready) return;
    try {
      await _plugin.cancel(id: _id);
      final settings = (app.state['settings'] as Map?) ?? const {};
      if (settings['snackNudge'] == false) return;
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
