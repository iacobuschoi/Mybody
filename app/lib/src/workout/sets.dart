/* =============================================================================
 * sets.dart — 세트 하나의 기록
 *
 * 0.2.21 까지 헬스 기록은 종목마다 「몇 세트 했는가(sets)」 와 「무게 하나(kg)」 였습니다.
 * 세트마다 무게 · 횟수가 다른 날(1세트 80kg 5회 · 2세트 85kg 3회)을 적을 수 없었고,
 * 음성으로 「벤치 80키로 4개」 라고 말한 것을 둘 자리도 없었습니다. 이제 종목 줄은
 * 세트 목록(SetEntry)을 들고, 기록에는 `setLog: [{kg, reps, src}]` 로 남깁니다.
 *
 * 옛 칸(sets · kg · reps)은 그대로 남깁니다 — 무게 추천(lastLoadsFrom) · 브리핑 · 친구
 * 화면 · 옛 판이 그 칸을 읽습니다. setLog 는 **덧붙이는** 칸이고, 없으면 옛 기록입니다.
 *
 *   kg    null 이면 맨몸. 줄의 「오늘 무게」 를 누른 시점의 값이 들어가므로, 세트 사이에
 *         무게를 바꾸면 그 뒤 세트만 바뀝니다.
 *   reps  null 이면 「계획대로」 — 세트 단추만 눌렀고 횟수는 안 적은 것. 지어내지 않습니다.
 *   src   'tap'(세트 단추) · 'voice'(누르고 말하기) · 'edit'(세트 시트에서 고침). 'tap' 은
 *         기록에 안 적습니다(기본값).
 * ========================================================================== */
library;

/// 세트 하나.
class SetEntry {
  SetEntry({this.kg, this.reps, this.src = 'tap'});

  double? kg;
  int? reps;
  String src;

  bool get edited => src != 'tap' || reps != null;

  Map<String, Object?> toMap() => {
        'kg': kg,
        if (reps != null) 'reps': reps,
        if (src != 'tap') 'src': src,
      };

  factory SetEntry.fromMap(Map m) {
    final kg = m['kg'];
    final reps = m['reps'];
    return SetEntry(
      kg: kg is num && kg > 0 ? kg.toDouble() : null,
      reps: reps is num && reps > 0 ? reps.round() : null,
      src: '${m['src'] ?? 'tap'}',
    );
  }

  SetEntry copy() => SetEntry(kg: kg, reps: reps, src: src);

  /// 칩 · 기록 화면의 글자 — '80×5' · '80kg' · '맨몸×12' · '맨몸'.
  String get label {
    final w = kg == null ? '맨몸' : kgLabel(kg!);
    return reps == null ? (kg == null ? '맨몸' : '${w}kg') : '$w×$reps';
  }

  /// 82.5 → '82.5', 80.0 → '80'.
  static String kgLabel(double v) {
    final r = (v * 100).round() / 100;
    return r == r.roundToDouble() ? '${r.round()}' : '$r';
  }
}

/// 기록의 종목 한 줄(`{name, sets, of, reps, kg, setLog?}`)에서 세트 목록을 읽습니다.
/// setLog 가 없는 옛 기록은 sets 개수만큼 같은 kg 의 세트로 봅니다(횟수는 모름).
List<SetEntry> setLogOf(Map row) {
  final raw = row['setLog'];
  if (raw is List && raw.isNotEmpty) {
    return [for (final m in raw) if (m is Map) SetEntry.fromMap(m)];
  }
  final n = row['sets'];
  final count = n is num ? n.round() : 0;
  final kg = row['kg'];
  return [for (var i = 0; i < count; i++) SetEntry(kg: kg is num && kg > 0 ? kg.toDouble() : null)];
}

/// 세트 목록 한 줄 요약 — 같은 세트가 이어지면 묶습니다: '80×5 · 80×5 · 85×3' → '80×5 ×2 · 85×3'.
/// 횟수를 모르는 옛 기록은 '60kg ×3세트'.
String setLogSummary(List<SetEntry> log) {
  if (log.isEmpty) return '';
  final out = <String>[];
  var i = 0;
  while (i < log.length) {
    var j = i;
    while (j + 1 < log.length && log[j + 1].kg == log[i].kg && log[j + 1].reps == log[i].reps) {
      j++;
    }
    final n = j - i + 1;
    final e = log[i];
    if (e.reps == null) {
      out.add('${e.kg == null ? '맨몸' : '${SetEntry.kgLabel(e.kg!)}kg'} ×$n세트');
    } else {
      out.add(n > 1 ? '${e.label} ×$n' : e.label);
    }
    i = j + 1;
  }
  return out.join(' · ');
}

/// 총 볼륨(kg × 횟수의 합). 횟수를 모르는 세트는 셈에서 뺍니다.
double setLogVolume(List<SetEntry> log) {
  var v = 0.0;
  for (final e in log) {
    if (e.kg != null && e.reps != null) v += e.kg! * e.reps!;
  }
  return v;
}

/// 가장 무거운 세트의 kg. 맨몸뿐이면 null.
double? setLogMaxKg(List<SetEntry> log) {
  double? m;
  for (final e in log) {
    if (e.kg != null && (m == null || e.kg! > m)) m = e.kg;
  }
  return m;
}
