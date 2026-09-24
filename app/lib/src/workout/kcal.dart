/* =============================================================================
 * kcal.dart — 운동 소모 칼로리 어림
 *
 *   kcal = MET × 3.5 × 체중(kg) / 200 × 분    (ACSM 대사 공식)
 *
 * MET 는 2011 Compendium of Physical Activities 의 값입니다. 걷기·달리기는
 * 거리를 알면 속도로 MET 를 고르고, 모르면 흔한 속도의 값을 씁니다.
 *
 * 이 숫자는 어림입니다. 같은 30분이라도 사람마다 ±30% 는 다릅니다 —
 * 화면은 "약" 을 붙여야 하고, 식단 목표에 그대로 더하면 안 됩니다.
 * ========================================================================== */
library;

/// 유산소 종류. 화면의 선택지가 이 순서로 그립니다.
const List<String> kCardioKinds = ['walk', 'run', 'bike', 'cardio'];

/// 걷기 — 시속별 MET (Compendium 17152~17220). 느린 산책부터 빠른 걸음까지.
double _walkMet(double kmh) {
  if (kmh < 4.0) return 2.8;
  if (kmh < 5.5) return 3.5;
  if (kmh < 6.5) return 4.3;
  return 5.0;
}

/// 달리기 — 시속별 MET (Compendium 12020~12130). 사이는 직선으로 잇습니다.
const List<List<double>> _runTable = [
  [6.4, 6.0], [8.0, 8.3], [8.4, 9.0], [9.7, 9.8], [10.8, 10.5], [11.3, 11.0],
  [12.1, 11.5], [12.9, 11.8], [13.8, 12.3], [14.5, 12.8], [16.1, 14.5], [17.7, 16.0],
];

double _runMet(double kmh) {
  if (kmh <= _runTable.first[0]) return _runTable.first[1];
  if (kmh >= _runTable.last[0]) return _runTable.last[1];
  for (var i = 1; i < _runTable.length; i++) {
    final a = _runTable[i - 1], b = _runTable[i];
    if (kmh <= b[0]) return a[1] + (kmh - a[0]) / (b[0] - a[0]) * (b[1] - a[1]);
  }
  return _runTable.last[1];
}

/// 자전거 — 시속별 MET (Compendium 01010~01040).
double _bikeMet(double kmh) {
  if (kmh < 16) return 4.0;
  if (kmh < 19) return 6.8;
  if (kmh < 22) return 8.0;
  if (kmh < 26) return 10.0;
  return 12.0;
}

/// 종류와 (있으면) 속도로 MET 를 정합니다. 속도를 못 구하면 기본값.
double workoutMet({required String kind, double? kmh}) {
  final v = kmh != null && kmh.isFinite && kmh > 0 ? kmh : null;
  switch (kind) {
    case 'walk':
      return v == null ? 3.5 : _walkMet(v);
    case 'run':
      return v == null ? 9.8 : _runMet(v);
    case 'bike':
      return v == null ? 6.8 : _bikeMet(v);
    case 'gym':
      return 5.0;
    case 'bodyweight':
      return 8.0;
    default:
      return 6.0;                          // 'cardio' 와 모르는 것 — 일반 유산소
  }
}

/// kcal = MET × 3.5 × kg / 200 × minutes (ACSM).
/// kind: 'gym' | 'bodyweight' | 'walk' | 'run' | 'bike' | 'cardio'.
/// km 을 주면 걷기·달리기·자전거는 속도로 MET 를 고릅니다.
double workoutKcal({
  required double weightKg,
  required Duration duration,
  required String kind,
  double? km,
}) {
  /* 말이 안 되는 입력은 잘라 냅니다. 체중 칸에 0 이나 자릿수 오독(634)이
     들어와도 화면에 0 kcal 이나 5,000 kcal 이 찍히면 안 됩니다. */
  final kg = weightKg.isFinite ? weightKg.clamp(30.0, 250.0) : 70.0;
  final minutes = (duration.inSeconds / 60).clamp(0.0, 360.0);
  double? kmh;
  if (km != null && km.isFinite && km > 0 && minutes > 0) {
    kmh = km.clamp(0.0, 100.0) / (minutes / 60);
  }
  final met = workoutMet(kind: kind, kmh: kmh);
  return met * 3.5 * kg / 200 * minutes;
}

/// 걷기 · 달리기 · 자전거 · 유산소 (헬스 · 맨몸도 이름은 있습니다).
String cardioKindLabel(String kind) {
  switch (kind) {
    case 'walk':
      return '걷기';
    case 'run':
      return '달리기';
    case 'bike':
      return '자전거';
    case 'gym':
      return '헬스';
    case 'bodyweight':
      return '맨몸';
    default:
      return '유산소';
  }
}
