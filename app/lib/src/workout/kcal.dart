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
 *
 * 유산소 화면은 스포츠도 받습니다(피드백 41 — 필라테스 · 탁구 …). 종목은 코드가
 * 아니라 [kSports] 표 한 줄씩이라 하나 더하는 일은 줄 하나 더하는 일입니다.
 * 기록에는 종목 id 만 남고(log['cardio'].kind — 스키마 그대로), 이름과 MET 는
 * 읽을 때 이 표에서 찾습니다. 표에 없는 id(다음 판에서 온 것)는 일반 유산소 6.0.
 * ========================================================================== */
library;

/// 유산소 · 스포츠 종목 하나. [id] 는 기록에 그대로 남는 열쇠라 바꾸면 안 됩니다.
class SportKind {
  const SportKind({
    required this.id,
    required this.label,
    required this.met,
    required this.group,
    this.hasDistance = false,
    this.meters = false,
  });

  final String id;
  final String label;

  /// 속도를 모를 때의 MET. 걷기 · 달리기 · 자전거는 거리를 알면 속도로 다시 고릅니다.
  final double met;

  /// 거리(km)를 묻는가 — 걷기 · 달리기 · 자전거 · 수영 · 등산만. 탁구에 km 칸은 소음입니다.
  final bool hasDistance;

  /// 거리 칸을 m 로 받는가 — 수영. 수영은 m(1500m)로 세고, km 칸에 1500 을 넣으면
  /// 「1500.0km」 가 됩니다. 기록에는 늘 km 로 남습니다(log['cardio'].km — 스키마 그대로).
  final bool meters;

  /// 'cardio' | 'mind-body' | 'racket' | 'team' | 'water' | 'outdoor' | 'combat' | 'winter' | 'other'
  final String group;
}

/// 종목 표. MET 는 2011 Compendium(괄호 안은 코드). 맨 앞 넷은 처음부터 있던 id —
/// 옛 기록이 그대로 읽히도록 id · 이름을 바꾸지 않습니다. 묶음 안의 순서가 곧 화면 순서.
const List<SportKind> kSports = [
  SportKind(id: 'walk', label: '걷기', met: 3.5, group: 'cardio', hasDistance: true),     // 17190
  SportKind(id: 'run', label: '달리기', met: 9.8, group: 'cardio', hasDistance: true),    // 12050
  SportKind(id: 'bike', label: '자전거', met: 6.8, group: 'cardio', hasDistance: true),   // 01020 시속 16~19km
  SportKind(id: 'cardio', label: '유산소', met: 6.0, group: 'cardio'),                    // 종류를 모를 때
  SportKind(id: 'spinning', label: '스피닝', met: 8.5, group: 'cardio'),                  // 02019 RPM/스핀 수업
  SportKind(id: 'rowing', label: '로잉머신', met: 7.0, group: 'cardio'),                  // 02072 100W
  SportKind(id: 'stairs', label: '계단 오르기', met: 8.8, group: 'cardio'),               // 17134 빠르게
  SportKind(id: 'jump-rope', label: '줄넘기', met: 11.8, group: 'cardio'),                // 15552 보통 속도
  SportKind(id: 'aerobics', label: '에어로빅', met: 7.3, group: 'cardio'),                // 03015
  SportKind(id: 'dance', label: '댄스', met: 5.0, group: 'cardio'),                       // 03010 수업
  SportKind(id: 'crossfit', label: '크로스핏', met: 8.0, group: 'cardio'),                // 02040 서킷 고강도
  SportKind(id: 'pilates', label: '필라테스', met: 3.0, group: 'mind-body'),              // 02105
  SportKind(id: 'yoga', label: '요가', met: 2.5, group: 'mind-body'),                     // 02150 하타
  SportKind(id: 'table-tennis', label: '탁구', met: 4.0, group: 'racket'),                // 15660
  SportKind(id: 'badminton', label: '배드민턴', met: 5.5, group: 'racket'),               // 15030 친선
  SportKind(id: 'tennis', label: '테니스', met: 7.3, group: 'racket'),                    // 15675
  SportKind(id: 'squash', label: '스쿼시', met: 7.3, group: 'racket'),                    // 15652
  SportKind(id: 'soccer', label: '축구', met: 7.0, group: 'team'),                        // 15610 친선
  /* 풋살은 2011 판에 없습니다 — 친선 축구(15610 · 7.0)와 경기(15605 · 10.0) 사이.
     코트가 좁아 서 있는 시간이 적습니다. */
  SportKind(id: 'futsal', label: '풋살', met: 8.0, group: 'team'),
  SportKind(id: 'basketball', label: '농구', met: 6.5, group: 'team'),                    // 15055
  SportKind(id: 'volleyball', label: '배구', met: 4.0, group: 'team'),                    // 15710
  SportKind(id: 'baseball', label: '야구', met: 5.0, group: 'team'),                      // 15620
  SportKind(id: 'bowling', label: '볼링', met: 3.8, group: 'team'),                       // 15092 볼링장
  SportKind(id: 'swim', label: '수영', met: 5.8, group: 'water', hasDistance: true, meters: true), // 18310 자유형 천천히
  SportKind(id: 'aqua-aerobics', label: '아쿠아로빅', met: 5.3, group: 'water'),          // 18355
  SportKind(id: 'surfing', label: '서핑', met: 3.0, group: 'water'),                      // 18220
  SportKind(id: 'kayak', label: '카약', met: 5.0, group: 'water'),                        // 18100 보통
  SportKind(id: 'hiking', label: '등산', met: 6.0, group: 'outdoor', hasDistance: true),  // 17080
  SportKind(id: 'climbing', label: '클라이밍', met: 5.8, group: 'outdoor'),               // 15537 쉬운~중간
  /* 골프 — 카트(15290 · 3.5). 한국 골프장은 카트가 기본이라 「일반」(15255 · 4.8)이나 채를 메고
     걷기(15265 · 4.3)로 두면 5시간 라운딩이 수백 kcal 부풀려집니다. 스크린 · 연습장(15270 · 3.0)과도 가깝습니다. */
  SportKind(id: 'golf', label: '골프', met: 3.5, group: 'outdoor'),
  SportKind(id: 'inline', label: '인라인', met: 7.5, group: 'outdoor'),                   // 15591 시속 14km
  SportKind(id: 'boxing', label: '복싱', met: 7.8, group: 'combat'),                      // 15120 스파링
  /* 무술 — 15430(보통 속도 · 10.3, 예시에 태권도 · 유도 · 주짓수 · 가라테)은 쉬지 않고 하는
     속도의 값이고 15425(느린 수련 · 5.3)는 초보 연습입니다. 성인 취미 수련은 기술 연습과
     쉬는 틈이 섞여 그 사이(7.0)로 둡니다 — 10.3 이면 70kg · 1시간이 760kcal 가까이 됩니다.
     같은 줄(15430)의 두 종목이라 태권도·무술과 주짓수는 같은 값입니다. */
  SportKind(id: 'martial-arts', label: '태권도·무술', met: 7.0, group: 'combat'),
  SportKind(id: 'jiu-jitsu', label: '주짓수', met: 7.0, group: 'combat'),
  /* 스키 · 스노보드 — 19160(보통 · 5.3)은 「active time only」, 실제로 타는 시간만의 값입니다.
     시계는 리프트 · 줄 · 쉬는 시간까지 잽니다(4시간이면 5.3 으로 1,500kcal 넘게). 반쯤은
     리프트에 앉아 있는 것(1.5)으로 보고 하루 평균 3.4. */
  SportKind(id: 'ski', label: '스키', met: 3.4, group: 'winter'),
  SportKind(id: 'snowboard', label: '스노보드', met: 3.4, group: 'winter'),
  SportKind(id: 'skate', label: '스케이트', met: 7.0, group: 'winter'),                   // 19030
];

/// 「다른 종목」 시트의 묶음과 이름 — 이 순서로 그립니다. 종목이 없는 묶음은 안 그립니다.
const List<(String, String)> kSportGroups = [
  ('cardio', '유산소'),
  ('mind-body', '요가·필라테스'),
  ('racket', '라켓'),
  ('team', '구기'),
  ('water', '물'),
  ('outdoor', '야외'),
  ('combat', '격투'),
  ('winter', '겨울'),
  ('other', '기타'),
];

/// 종료 시트 맨 위에 늘 있는 종목. 그 옆에 최근에 한 종목이 붙습니다.
const List<String> kQuickSports = ['walk', 'run', 'bike'];

final Map<String, SportKind> _sportById = {for (final s in kSports) s.id: s};

/// id → 종목. 표에 없으면 null.
SportKind? sportOf(String? id) => _sportById[id];

/// 기록의 kind → 이름. 표에 없거나 비었으면 '유산소' — 옛 기록 · 다음 판의 기록도 읽힙니다.
String sportLabel(String? id) => _sportById[id]?.label ?? '유산소';

/// 최근 [days]일([dateKey] 그 날부터 거꾸로)의 유산소 기록에 나온 종목 id — 최근 것부터,
/// 겹치는 것도 그대로. [skip] 날은 뺍니다. 표에 없는 id 는 뺍니다.
List<String> _recentSportLog(Map<String, Object?> schedule, String dateKey, int days, String? skip) {
  final out = <String>[];
  final start = DateTime.tryParse('${dateKey}T00:00:00');
  if (start == null) return out;
  for (var i = 0; i < days; i++) {
    /* 달력 산수로 — Duration 으로 빼면 서머타임 날(23시간) 다음에 하루가 건너뜁니다. */
    final d = DateTime(start.year, start.month, start.day - i);
    final k = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    if (k == skip) continue;
    final day = schedule[k];
    final log = day is Map ? day['log'] : null;
    final cardio = log is Map ? log['cardio'] : null;
    final id = cardio is Map ? cardio['kind'] : null;
    if (id is String && _sportById.containsKey(id)) out.add(id);
  }
  return out;
}

/// 최근 [days]일([dateKey] 그 날 포함)의 유산소 기록에 나온 종목 id — 최근 것부터, 겹치지
/// 않게. 표에 없는 id 는 뺍니다(칩으로 올릴 이름이 없습니다). [schedule] 은 state['schedule'].
List<String> recentSportIds(Map<String, Object?> schedule, String dateKey, {int days = 30}) =>
    _recentSportLog(schedule, dateKey, days, null).toSet().toList();

/// 종료 시트가 미리 골라 둘 종목 — 최근 [days]일에 **두 번 이상** 한 종목 중 가장 최근 것,
/// 없으면 걷기. [skip](기록하려는 그 날)은 셈에서 뺍니다: 오늘 자전거로 출근했다고 저녁
/// 배드민턴의 기본값이 자전거가 되면, 「저장」 한 번에 잘못된 종목이 남습니다. 한 번 해 본
/// 종목(어제의 테니스)도 기본값이 되지 않습니다 — 칩으로만 올라옵니다. 필라테스를 다니는
/// 사람은 두 번째부터 시트를 열면 이미 필라테스입니다.
String defaultSportId(Map<String, Object?> schedule, String dateKey, {String? skip, int days = 30}) {
  final log = _recentSportLog(schedule, dateKey, days, skip);
  for (final id in log) {
    if (log.where((x) => x == id).length >= 2) return id;
  }
  return kQuickSports.first;
}

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

/// 종류와 (있으면) 속도로 MET 를 정합니다. 속도를 못 구하면 표([kSports])의 값.
double workoutMet({required String kind, double? kmh}) {
  final v = kmh != null && kmh.isFinite && kmh > 0 ? kmh : null;
  if (v != null) {
    switch (kind) {
      case 'walk':
        return _walkMet(v);
      case 'run':
        return _runMet(v);
      case 'bike':
        return _bikeMet(v);
    }
  }
  switch (kind) {
    case 'gym':
      return 5.0;
    case 'bodyweight':
      return 8.0;
    default:
      /* 스포츠는 속도와 상관없이 표의 값. 모르는 id 는 일반 유산소 — 옛 판이 새 판의
         기록을 받아도 0 kcal 이 되지 않습니다. */
      return _sportById[kind]?.met ?? 6.0;
  }
}

/// kcal = MET × 3.5 × kg / 200 × minutes (ACSM).
/// kind: 'gym' | 'bodyweight' | [kSports] 의 id('walk' · 'pilates' …).
/// km 을 주면 걷기·달리기·자전거는 속도로 MET 를 고릅니다(수영 · 등산은 거리만 남깁니다).
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

/// 종목 이름 — [kSports] 의 이름에 헬스 · 맨몸까지. 모르는 것은 '유산소'.
String cardioKindLabel(String kind) {
  switch (kind) {
    case 'gym':
      return '헬스';
    case 'bodyweight':
      return '맨몸';
    default:
      return sportLabel(kind);
  }
}
