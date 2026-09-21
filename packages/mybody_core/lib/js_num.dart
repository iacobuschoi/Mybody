/* =============================================================================
 * js_num.dart — 자바스크립트와 **같은 숫자**를 내기 위한 도구
 *
 * 이 파일이 있는 이유는 Dart 가 틀려서가 아니라, 우리가 옮기는 원본이
 * 자바스크립트이고 두 언어의 반올림이 **다르기 때문**입니다.
 * 다르면 검산 결과가 갈리고, 갈리면 어느 쪽을 믿어야 할지 알 수 없습니다.
 *
 * 실제로 다른 것들:
 *
 *   1. 음수의 반올림
 *        JS   Math.round(-2.5) === -2      (항상 +∞ 쪽으로)
 *        Dart (-2.5).round()   == -3       (0 에서 먼 쪽으로)
 *      검산에는 차이값(gap)이 오가므로 음수가 실제로 들어옵니다.
 *
 *   2. 0.5 가 걸린 소수 반올림
 *      두 언어 다 2진 부동소수를 쓰므로 대개 같지만, toFixed 와
 *      toStringAsFixed 의 구현이 달라 끝자리가 갈릴 수 있습니다.
 *      그래서 "JS 가 내는 문자열" 을 기준으로 맞춥니다.
 *
 * 규칙: 검산·엔진 코드에서는 절대로 Dart 의 round()/toStringAsFixed() 를
 * 직접 쓰지 않습니다. 여기 있는 것만 씁니다. 차이 검사(difftest)가
 * 이걸 어기면 바로 잡아냅니다.
 * ========================================================================== */

/// JS 의 `Math.round` — 0.5 는 **항상 +∞ 쪽**으로 갑니다.
num jsRound(num x) {
  if (x.isNaN || x.isInfinite) return x;
  return (x + 0.5).floorToDouble();
}

/// JS 의 `Math.round(x * 10) / 10`
double r1(num x) => jsRound(x * 10) / 10;

/// JS 의 `Math.round(x * 100) / 100`
double r2(num x) => jsRound(x * 100) / 100;

/// JS 의 `Number.prototype.toFixed`.
///
/// Dart 의 toStringAsFixed 는 대부분 같은 답을 내지만, 음수의 0.5 와
/// 일부 경계에서 갈립니다. jsRound 로 먼저 자리수를 확정한 뒤 찍습니다.
String toFixed(num x, int digits) {
  if (x.isNaN) return 'NaN';
  if (x.isInfinite) return x.isNegative ? '-Infinity' : 'Infinity';
  final p = _pow10(digits);
  final v = jsRound(x * p) / p;
  return v.toStringAsFixed(digits);
}

/// JS 의 `String(number)` — 정수는 소수점을 안 붙입니다.
///
/// Dart 는 1.0 을 "1.0" 으로 찍고 JS 는 "1" 로 찍습니다. 이 차이가
/// 그대로 화면 문구에 새어 나갑니다 ("체중 63.0 − 체지방 12" 대 "12.0").
String jsNumToString(num x) {
  if (x is int) return x.toString();
  final d = x.toDouble();
  if (d.isNaN) return 'NaN';
  if (d.isInfinite) return d.isNegative ? '-Infinity' : 'Infinity';
  if (d == d.truncate() && d.abs() < 1e21) return d.toInt().toString();
  return d.toString();
}

double _pow10(int n) {
  var v = 1.0;
  for (var i = 0; i < n; i++) v *= 10;
  return v;
}

/// JS 의 `typeof x === 'number' && isFinite(x)` 검사와 같은 뜻.
/// 결과지 값은 null · 문자열 · NaN 으로 들어올 수 있습니다.
double? num_(Object? x) {
  if (x is num && x.isFinite) return x.toDouble();
  return null;
}

/* --- 자바스크립트의 타입 강제 --------------------------------------------
 *
 * engine.js 는 값을 다듬지 않고 그대로 산수에 씁니다 (crosscheck.js 는
 * n() 으로 먼저 정규화하는 것과 다릅니다). 그래서 옮길 때 자바스크립트의
 * 강제 규칙을 그대로 따라가야 합니다. 안 따라가면 조용히 다른 답이 납니다.
 *
 * 차이 검사가 실제로 잡은 것 둘:
 *
 *   1. `null * 10` 은 **0** 입니다 (undefined * 10 은 NaN).
 *      JSON 에서 "키가 없다" 와 "값이 null" 은 다른 것인데, Dart Map 에서는
 *      둘 다 null 로 보입니다. containsKey 로 갈라야 합니다.
 *      골격근량이 null 인 결과지에서 JS 는 0 을, 옮긴 쪽은 NaN 을 냈습니다.
 *
 *   2. `"abc" || fallback` 에서 **문자열은 참**입니다. 그래서 fallback 이
 *      아니라 "abc" 가 쓰이고, 그 뒤 산수가 NaN 이 됩니다.
 *      옮긴 쪽은 "숫자가 아니면 fallback" 으로 읽어서 멀쩡한 값을 냈습니다 —
 *      더 "올바른" 동작이지만, 다른 동작입니다.
 * -------------------------------------------------------------------------- */

/// JS 의 ToNumber.
double jsToNumber(Object? v) {
  if (v == null) return 0;                       // null → 0  (undefined 가 아닙니다)
  if (v is bool) return v ? 1 : 0;
  if (v is num) return v.toDouble();
  if (v is String) {
    final t = v.trim();
    if (t.isEmpty) return 0;                     // '' → 0
    return double.tryParse(t) ?? double.nan;
  }
  return double.nan;                             // 객체·배열은 여기서는 NaN 으로 봅니다
}

/// JS 의 참/거짓. 0 · '' · null · NaN 이 거짓이고 나머지는 참입니다.
bool jsTruthy(Object? v) {
  if (v == null) return false;
  if (v is bool) return v;
  if (v is num) return v != 0 && !v.isNaN;
  if (v is String) return v.isNotEmpty;
  return true;
}

/// 맵에서 JS 처럼 읽습니다 — **키가 없으면 NaN, 값이 null 이면 0.**
double jsNum(Map<String, Object?> m, String key) {
  if (!m.containsKey(key)) return double.nan;    // undefined
  return jsToNumber(m[key]);
}
