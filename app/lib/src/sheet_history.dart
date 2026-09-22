/* =============================================================================
 * sheet_history.dart — 결과지 맨 아래 「신체변화」 그래프에서 읽은 지난 측정
 *
 * 인바디 결과지 한 장에는 지난 측정이 몇 개씩 같이 인쇄돼 있습니다 — 체중 ·
 * 골격근량 · 체지방률이 날짜와 함께. 앱을 처음 쓰는 사람은 결과지 한 장으로
 * 추이가 서너 점부터 시작할 수 있습니다. 옛 결과지를 찾아 하나씩 넣지 않아도.
 *
 * 서버가 열들을 다듬어 보내고(날짜 형식 · 값 범위), 여기서는 **내 기록과
 * 대조**합니다. 이번 측정과 같은 날은 이번 측정이고, 이미 있는 날은 이미
 * 있는 것입니다. 둘 다 빼고 남는 것만 후보입니다. 값이 물리적으로 안 맞는
 * 열(validateScan)은 조용히 뺍니다 — 그래프의 작은 글씨는 오독이 잦고,
 * 검수 화면에 열마다 검산을 보여 줄 자리는 없습니다.
 * ========================================================================== */
import 'package:mybody_core/mybody_core.dart' as core;

class SheetHistoryItem {
  const SheetHistoryItem({
    required this.measuredAt,
    required this.weightKg,
    required this.smmKg,
    required this.pbfPct,
  });

  /// ISO(UTC). 결과지에 시각이 있으면 그 시각, 없으면 그날 9시.
  final String measuredAt;
  final double weightKg;
  final double smmKg;
  final double pbfPct;

  double get bfmKg => core.r1(weightKg * pbfPct / 100);

  /// 저장할 측정. 아이디는 시각으로 정해집니다 — 같은 결과지를 두 번 넣어도
  /// 같은 줄을 덮어쓰지, 두 줄이 되지 않습니다.
  Map<String, Object?> toScan({double? heightCm}) {
    final bfm = bfmKg;
    final ms = DateTime.tryParse(measuredAt)?.millisecondsSinceEpoch ?? 0;
    final h = (heightCm ?? 0) / 100;
    return {
      'id': 'scan-h$ms',
      'measuredAt': measuredAt,
      'weightKg': weightKg,
      'smmKg': smmKg,
      'pbfPct': pbfPct,
      'bfmKg': bfm,
      'ffmKg': core.r1(weightKg - bfm),
      if (h > 0) 'bmi': core.r1(weightKg / (h * h)),
      'source': 'chart',   // 웹 기록 화면이 '그래프 복원' 으로 읽는 값
    };
  }
}

/// 같은 날인지 볼 때 쓰는 열쇠 — 폰의 시간대 기준 날짜.
String localDayKey(Object? iso) {
  final d = iso == null ? null : DateTime.tryParse('$iso');
  if (d == null) return '';
  final l = d.toLocal();
  return '${l.year}-${l.month}-${l.day}';
}

/// 서버가 보낸 그래프 열들 중 **새로 저장할 만한 것**. 오래된 순.
///
/// [currentAt] 은 이번 측정의 시각 — 같은 날과 그 뒤는 뺍니다.
/// [scans] 는 이미 있는 측정 — 같은 날이 있으면 뺍니다.
List<SheetHistoryItem> sheetHistory(
  Object? raw, {
  required Object? currentAt,
  required List<Map<String, Object?>> scans,
}) {
  if (raw is! List) return const [];
  final cur = currentAt == null ? null : DateTime.tryParse('$currentAt');
  final taken = <String>{
    localDayKey(currentAt),
    for (final s in scans) localDayKey(s['measuredAt']),
  };
  final out = <SheetHistoryItem>[];
  for (final e in raw) {
    if (e is! Map) continue;
    final at = e['measuredAt'];
    final d = at is String ? DateTime.tryParse(at) : null;
    final w = e['weightKg'];
    final m = e['smmKg'];
    final p = e['pbfPct'];
    if (d == null || w is! num || m is! num || p is! num) continue;
    if (cur != null && !d.isBefore(cur)) continue;
    final key = localDayKey(at);
    if (key.isEmpty || !taken.add(key)) continue;
    final item = SheetHistoryItem(
      measuredAt: d.toUtc().toIso8601String(),
      weightKg: w.toDouble(),
      smmKg: m.toDouble(),
      pbfPct: p.toDouble(),
    );
    if (core.validateScan(item.toScan(), null) != null) continue;
    out.add(item);
  }
  out.sort((a, b) => a.measuredAt.compareTo(b.measuredAt));
  return out;
}
