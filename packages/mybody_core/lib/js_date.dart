/* =============================================================================
 * js_date.dart — 자바스크립트의 **날짜 읽는 법**을 그대로 흉내 냅니다.
 *
 * 두 언어가 같은 문자열을 다르게 읽는 곳이 딱 하나 있는데, 하필 우리가
 * 제일 많이 쓰는 형태입니다:
 *
 *     new Date('2026-01-15')              → 자바스크립트: **UTC** 자정
 *     DateTime.parse('2026-01-15')        → Dart:        **현지** 자정
 *
 *     new Date('2026-01-15T00:00:00')     → 둘 다 현지 자정
 *     new Date('2026-01-15T00:00:00Z')    → 둘 다 UTC 자정
 *
 * 날짜만 있는 형태를 UTC 로 읽는 것은 ECMAScript 명세가 그렇게 정해 둔
 * 것입니다. 그리고 engine.js 의 toISODate 는 **현지** 달력으로 다시
 * 찍습니다(getFullYear/getMonth/getDate). 그래서 한국(UTC+9)에서는
 * 아무 일도 안 일어나지만, 시차가 음수인 곳에서는 목표일이 하루 당겨집니다.
 *
 * 그 동작을 "고치지" 않습니다. 고치면 두 앱이 같은 계획에서 다른 날짜를
 * 말합니다. 여기서는 **같게** 만드는 것이 목적이고, 고칠지 말지는 원본
 * 쪽에서 정할 일입니다.
 *
 * 앱이 만드는 날짜 문자열은 ISO 두 형태뿐입니다. 'Jan 15 2026' 같은
 * 자유 형식은 자바스크립트만 읽는데, 앱에 그런 값이 들어올 길이 없어서
 * 흉내 내지 않습니다 — 들어오면 양쪽 다 "못 읽음" 이 됩니다.
 * ========================================================================== */
library;

final RegExp _dateOnly = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// JS 의 `new Date(x)`. 못 읽으면 null (= Invalid Date).
DateTime? jsParseDate(Object? x) {
  if (x is DateTime) return x;
  if (x is! String) return null;
  final s = x.trim();
  if (_dateOnly.hasMatch(s)) return DateTime.tryParse('${s}T00:00:00Z');
  return DateTime.tryParse(s);
}

/// JS 의 `String(Invalid Date 의 조각들)` — "NaN-NaN-NaN" 이 나옵니다.
const String invalidDateISO = 'NaN-NaN-NaN';

/// engine.js 의 toISODate — **현지 달력**으로 YYYY-MM-DD.
String toISODate(Object? d) {
  final dt = jsParseDate(d);
  if (dt == null) return invalidDateISO;
  final l = dt.toLocal();
  final m = l.month.toString().padLeft(2, '0');
  final day = l.day.toString().padLeft(2, '0');
  return '${l.year}-$m-$day';
}

/// engine.js 의 addWeeks — `setDate(getDate() + Math.round(w*7))` 입니다.
/// 현지 달력 위에서 날짜를 더하므로 달·해 넘김은 알아서 처리됩니다.
String addWeeks(Object? d, num weeks) {
  final dt = jsParseDate(d);
  if (dt == null) return invalidDateISO;
  if (weeks.isNaN || weeks.isInfinite) return invalidDateISO;
  final days = (weeks * 7 + 0.5).floor();     // jsRound
  final l = dt.toLocal();
  final n = DateTime(l.year, l.month, l.day + days, l.hour, l.minute, l.second,
      l.millisecond, l.microsecond);
  return toISODate(n);
}

/// engine.js 의 daysUntil — `new Date(iso + 'T00:00:00')` 이라 **현지** 자정입니다.
/// fromISO 가 없으면 지금(now)을 씁니다.
num daysUntil(Object? iso, [Object? fromISO, DateTime? now]) {
  final a = DateTime.tryParse('${iso}T00:00:00');
  if (a == null) return double.nan;
  DateTime b;
  if (fromISO != null && '$fromISO'.isNotEmpty) {
    final parsed = DateTime.tryParse('${fromISO}T00:00:00');
    if (parsed == null) return double.nan;
    b = parsed;
  } else {
    b = now ?? DateTime.now();
  }
  final ms = a.millisecondsSinceEpoch - b.millisecondsSinceEpoch;
  return (ms / 86400000 + 0.5).floor();
}
