/* =============================================================================
 * fmt.dart — 숫자와 날짜를 **지금 앱과 똑같이** 찍습니다
 *
 * 값은 코어가 내고, 여기는 그걸 사람이 읽는 모양으로만 바꿉니다.
 * 자릿수가 달라지면 같은 몸이 두 앱에서 다른 숫자로 보입니다 —
 * 63.4 와 63.40 은 다른 인상을 줍니다.
 *
 * `—` 는 "모른다" 입니다. 0 이 아닙니다. 이 구분이 이 앱의 약속이라
 * 여기서부터 지킵니다.
 * ========================================================================== */
import 'package:mybody_core/mybody_core.dart' as core;

String n1(Object? x) => x == null ? '—' : core.toFixed(core.jsToNumber(x), 1);
String n2(Object? x) => x == null ? '—' : core.toFixed(core.jsToNumber(x), 2);
String n0(Object? x) => x == null ? '—' : core.jsNumToString(core.jsRound(core.jsToNumber(x)));

/// 부호를 앞에 붙입니다. 빼기 기호는 하이픈(-)이 아니라 −(U+2212) 입니다 —
/// 하이픈은 숫자 옆에서 너무 작아 보여서 증감을 반대로 읽는 일이 생깁니다.
String signed(Object? x, [int d = 1]) {
  if (x == null) return '—';
  final v = core.jsToNumber(x);
  final body = d == 2 ? n2(v.abs()) : n1(v.abs());
  return (v > 0 ? '+' : (v < 0 ? '−' : '')) + body;
}

String dateK(Object? iso) {
  if (iso == null || '$iso'.isEmpty) return '—';
  final s = '$iso';
  final d = DateTime.tryParse(s.length <= 10 ? '${s}T00:00:00' : s);
  if (d == null) return '—';
  final l = d.toLocal();
  return '${l.year}. ${l.month}. ${l.day}.';
}

String dateShort(Object? iso) {
  if (iso == null || '$iso'.isEmpty) return '—';
  final s = '$iso';
  final d = DateTime.tryParse(s.length <= 10 ? '${s}T00:00:00' : s);
  if (d == null) return '—';
  final l = d.toLocal();
  return '${l.month}/${l.day}';
}

/// 쉬는 시간을 사람 말로 — '75초' · '90초' · '1분' · '2분' · '2분 30초'. 정각이면 분,
/// 2분 아래는 초로 말하고(헬스장에서 "90초 쉬어" 는 자연스럽습니다) 150초부터는 분으로 —
/// 그건 아무도 안 셉니다. 플랜 탭과 헬스 화면이 같은 종목에 다른 글자를 내면 안 되므로
/// 둘 다 이 함수입니다(3차 리뷰: 60 → 「60초」/「1분」, 90 → 「1분 30초」/「90초」 로 갈렸습니다).
String restText(int sec) {
  final m = sec ~/ 60, s = sec % 60;
  if (s == 0 && m > 0) return '$m분';
  if (sec < 120) return '$sec초';
  return '$m분 $s초';
}

/// "78주 (약 17개월 4주)" — 주 단위만 주면 사람이 기간을 못 가늠합니다.
String weeksToHuman(Object? w) {
  if (w == null) return '—';
  final v = core.jsToNumber(w);
  final m = (v / 4.345).floor();
  final rest = core.jsRound(v - m * 4.345);
  if (m <= 0) return '${core.jsNumToString(v)}주';
  return '${core.jsNumToString(v)}주 (약 $m개월${rest > 0 ? ' ${core.jsNumToString(rest)}주' : ''})';
}

/// 이름의 **첫 글자 한 개**. 이모지를 반으로 자르면 깨진 네모가 나오므로
/// 코드포인트 단위로 자릅니다.
String firstChar(Object? name) {
  final t = '${name ?? ''}'.trim();
  if (t.isEmpty) return '?';
  return String.fromCharCodes(t.runes.take(1));
}

/// 이름에서 색을 뽑습니다 — 같은 사람은 언제나 같은 색입니다.
int tintOf(Object? seed) {
  final t = '${seed ?? ''}';
  var n = 0;
  for (final c in t.codeUnits) {
    n = (n * 31 + c) & 0xFFFFFFFF;
  }
  return n % 360;
}
