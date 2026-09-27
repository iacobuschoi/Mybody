/* =============================================================================
 * estimate.dart — 인바디 없이 시작하기: 키 · 체중으로 체성분을 어림합니다
 *
 * 인바디 결과지가 없는 사람은 지금까지 첫 화면에서 멈췄습니다. 목표도, 식단
 * 숫자도, 운동 무게도 전부 "지금 몸" 에서 출발하는데 그 몸을 넣을 길이 결과지
 * 사진 하나뿐이었습니다. 오너의 말 그대로 — "인바디 사진 없으면 키/체중만으로
 * 추정하고, 나중에 제대로 된 사진 넣으면 업데이트되는 거로" — 체중 한 칸으로
 * 시작하고, 실측이 들어오면 그걸로 갈아 끼웁니다(estimate_upgrade.dart).
 *
 * ── 체지방률: Gallagher 2000 (아시아인 항 포함) ─────────────────────────────
 *   Gallagher D, Heymsfield SB, Heo M, Jebb SA, Murgatroyd PR, Sakamoto Y.
 *   "Healthy percentage body fat ranges…" Am J Clin Nutr 2000;72(3):694–701.
 *   기준법 4C · DXA, 세 기관(도쿄 지케이대 포함 — 일본인 성인이 들어 있습니다),
 *   R = 0.90, SEE = 4.31 %BF.
 *
 *     %BF = 76.0 − 1097.8/BMI − 20.6·남 + 0.053·나이
 *           + 95.0·아시아/BMI − 0.044·아시아·나이
 *           + 154·남/BMI + 0.034·남·나이          (남 = 1 · 여 = 0, 아시아 = 1)
 *
 *   더 유명한 Deurenberg 1991(%BF = 1.20·BMI + 0.23·나이 − 10.8·남 − 5.4)을
 *   안 쓴 이유: 인종 항이 없습니다. 같은 체지방에서 중국인의 BMI 가 백인보다
 *   1.9 낮다는 게 Deurenberg 본인의 1998 년 보고(Int J Obes 22:1164)라, 같은
 *   BMI 면 한국인은 체지방률이 2%p 넘게 높게 나와야 맞습니다. 오너의 실측
 *   23.1% 에 대 보면 Deurenberg 18.6% · 거기에 아시아 보정을 더해 20.9% ·
 *   Gallagher(아시아 항) 22.1% — 마지막이 가장 가깝고, 기준법도 더 단단합니다.
 *
 * ── 골격근: Lee 2000 (아시아인 항 포함) ─────────────────────────────────────
 *   Lee RC, Wang Z, Heo M, Ross R, Janssen I, Heymsfield SB. "Total-body skeletal
 *   muscle mass: development and cross-validation of anthropometric prediction
 *   models." Am J Clin Nutr 2000;72:796–803. 전신 MRI 244 명, R² = 0.86, SEE 2.8kg.
 *
 *     SM = 0.244·체중 + 7.80·키(m) − 0.098·나이 + 6.6·남 + 인종 − 3.3
 *          (인종: 아시아 −1.2 · 아프리카계 +1.4 · 그 밖 0)
 *
 *   MRI 로 잰 골격근과 인바디의 골격근량(SMM)은 **같은 양이 아닙니다.** 인바디는
 *   자기 회귀식(비공개)으로 SMM 을 냅니다. 오너는 Lee 35.7kg · 인바디 38.0kg 으로
 *   2.3kg 차이 — SEE 하나 안쪽입니다. 그래도 **보정 계수를 곱하지 않습니다.**
 *   한 사람 한 점으로 만든 계수는 다음 사람에게 틀린 숫자를 자신 있게 말하게
 *   합니다. 대신 실측으로 바꿀 때 목표의 골격근은 절대값이 아니라 **변화량**
 *   (+1kg 을 원했다면 실측 + 1kg)을 옮기므로, 사람마다 일정한 치우침은 계획을
 *   움직이지 못합니다. 화면은 ±3kg 이라고 말합니다(kEstimateCaveat).
 *
 * ── 나머지 ─────────────────────────────────────────────────────────────────
 *   BMI = 체중/키², 체지방량 = 체중 × 체지방률, 제지방 = 체중 − 체지방량.
 *   기초대사량은 Katch–McArdle(370 + 21.6·제지방) — 인바디가 인쇄하는 식과
 *   같습니다(오너 결과지 370 + 21.6×66.7 = 1810.7, 인쇄값 1810). 단 **추정
 *   기록에는 bmrKcal 을 넣지 않습니다.** 넣으면 core.derive 가 "InBody 인쇄값" 이라
 *   부릅니다. 비워 두면 derive 가 같은 식으로 계산하고 "계산값" 이라 부릅니다 —
 *   그게 정직한 이름입니다.
 *
 * ── 가드 ───────────────────────────────────────────────────────────────────
 *   입력: 성별 남/여, 키 100~230cm · 나이 10~100 (온보딩과 같은 범위), 체중
 *   25~300kg (엔진 validateScan 과 같은 범위), BMI 12~60. 벗어나면 null.
 *   두 식 모두 성인 식이라 식에 넣는 나이는 18~90 으로 묶습니다. 미성년은 여기서
 *   막지 않습니다 — 19세 미만 감량은 modeSelect 가 이미 거절합니다.
 *   체지방률은 남 6~45% · 여 14~55% 로, 골격근은 제지방의 45~60% 로 묶습니다.
 *   앱의 검산 C6 이 45~65% 를 "사람" 으로 보고 validateScan 은 35~65% 를 받습니다.
 *   이 묶음이 실제로 걸리는 건 나이 많은 작은 여성뿐입니다 — Lee 의 나이 항이
 *   골격근을 너무 낮게 끌어내립니다(155cm · 70세 · 45kg → 11.7kg, 제지방의 34%).
 *   반올림은 검수 화면 · 검산과 같은 순서라(체지방률 → 체지방량 → 제지방)
 *   추정 기록이 검산을 전부 통과합니다.
 *
 * ── 체중은 추정이 아닙니다 ─────────────────────────────────────────────────
 *   사용자가 저울에서 읽어 넣은 진짜 값입니다. 추정은 그 체중을 근육과 지방으로
 *   **나누는 비율**뿐입니다. 그래서 체크인 · 체중 기준 무게 추천 · 목표 체중은
 *   추정 기록에서도 그대로 믿고, 실측으로 바꿀 때도 목표 체중은 옮기지 않습니다.
 *
 * ── 친구에게는 추정 몸 숫자를 보내지 않습니다 ───────────────────────────────
 *   친구 화면은 받은 숫자를 "측정값" 으로 읽습니다. 공식으로 나눈 근육 · 지방을
 *   잰 것처럼 내보내면, 친구는 틀릴 수 있는 숫자를 사실로 보게 됩니다. 몸 숫자는
 *   인바디에서만 나갑니다 — 체중까지 같이 뺍니다(친구 화면이 "kg · 근 · 지" 를
 *   한 줄로 찍습니다). 운동 일정 · 스트릭 · 오늘 식단 같은 행동은 그대로 나갑니다.
 *   (withoutEstimatedBody — publish.dart 가 올리기 직전에 거릅니다.)
 *
 * 이 파일은 순수합니다 — 코어만 씁니다. 코어(mybody_core)와 웹 원본은 차이
 * 검사로 묶여 있어서 새 추정 규칙은 앱 쪽에만 둡니다.
 * ========================================================================== */
import 'package:mybody_core/mybody_core.dart' as core;

/// 추정 기록의 표시 — scan['source']. 검수 화면이 이미 'ocr' 을 싣는 칸입니다.
const String kEstimateSource = 'estimate';

/// 실측으로 바꾼 기록(홈 카드 한 번)이 사는 최상위 칸. 동기화는 하나짜리 값으로 합칩니다.
const String kEstimateUpgradeKey = 'estimateUpgrade';

/// 추정 옆에 붙는 한 줄.
const String kEstimateHint = '인바디를 넣으면 실측으로 바뀌어요';

/// 오차 한 줄 — 두 식의 SEE 하나쯤에 BIA 와 기준법 사이의 차이를 더한 폭입니다.
const String kEstimateCaveat = '체지방률 ±5%p · 골격근 ±3kg 오차가 있을 수 있어요';

/// 「실측으로 바꿨어요」 카드를 보여 주는 기간. 닫으면 그 전에 사라집니다.
const Duration kUpgradeNoticeFor = Duration(days: 7);

/// 추정 기록인가.
bool isEstimate(Object? scan) => scan is Map && scan['source'] == kEstimateSource;

/// 추정 기록 위에서 세운 계획인가 — intensity · duration 이 세울 때 도장을 찍습니다.
bool planFromEstimate(Object? plan) => plan is Map && plan['fromEstimate'] == true;

/// 실측만, 순서 그대로.
List<Map<String, Object?>> realScans(List<Map<String, Object?>> scans) =>
    [for (final s in scans) if (!isEstimate(s)) s];

/// 그래프 · 추세에 쓸 측정 — 실측이 하나라도 있으면 실측만, 없으면 추정 그대로.
/// 추정 → 실측으로 긋는 선은 몸의 변화가 아니라 공식의 오차입니다.
List<Map<String, Object?>> chartScans(List<Map<String, Object?>> scans) {
  final real = realScans(scans);
  return real.isNotEmpty ? real : List.of(scans);
}

/// 실측이 있는데 추정(기록이든, 추정 위에 세운 계획이든)이 남아 있는가.
/// 저장할 때마다 불리므로 정렬하지 않고 원래 목록을 한 번 훑기만 합니다.
bool needsEstimateUpgrade(Map<String, Object?> state) {
  var real = false, est = false;
  final raw = state['scans'];
  if (raw is List) {
    for (final s in raw) {
      if (s is! Map) continue;
      if (isEstimate(s)) {
        est = true;
      } else {
        real = true;
      }
      if (real && est) return true;
    }
  }
  return real && (est || planFromEstimate(state['plan']));
}

/// 성별 · 나이 · 키 · 체중으로 체성분을 어림합니다. 입력이 범위를 벗어나면 null.
///
/// 돌려주는 것: {weightKg, heightCm, bmi, pbfPct, bfmKg, ffmKg, smmKg, bmrKcal}.
Map<String, Object?>? estimateComposition({
  required Object? sex,
  required num age,
  required num heightCm,
  required num weightKg,
}) {
  if (sex != 'male' && sex != 'female') return null;
  if (!age.isFinite || !heightCm.isFinite || !weightKg.isFinite) return null;
  if (heightCm < 100 || heightCm > 230) return null;
  if (age < 10 || age > 100) return null;
  if (weightKg < 25 || weightKg > 300) return null;

  final w = weightKg.toDouble();
  final h = heightCm / 100;
  final bmi = w / (h * h);
  if (!bmi.isFinite || bmi < 12 || bmi > 60) return null;

  final male = sex == 'male' ? 1 : 0;
  // 두 식 모두 성인에서 만든 식입니다 — 식에 넣는 나이만 묶습니다.
  final a = age.clamp(18, 90).toDouble();
  final inv = 1 / bmi;

  // Gallagher 2000, 아시아 = 1.
  final pbfRaw = 76.0 -
      1097.8 * inv -
      20.6 * male +
      0.053 * a +
      95.0 * inv -
      0.044 * a +
      154 * male * inv +
      0.034 * male * a;
  final pbfPct = core.r1(male == 1 ? pbfRaw.clamp(6, 45) : pbfRaw.clamp(14, 55));
  // 검수 화면과 같은 반올림 순서 — 체지방량 = 체중 × 체지방률, 제지방 = 체중 − 체지방량.
  final bfmKg = core.r1(w * pbfPct / 100);
  final ffmKg = core.r1(w - bfmKg);

  // Lee 2000, 아시아 −1.2. 제지방의 45~60% 로 묶습니다(검산 C6 은 45~65% 를 사람으로 봅니다).
  final smRaw = 0.244 * w + 7.80 * h - 0.098 * a + 6.6 * male - 1.2 - 3.3;
  final smmKg = core.r1(smRaw.clamp(0.45 * ffmKg, 0.60 * ffmKg));

  return {
    'weightKg': w,
    'heightCm': heightCm.toDouble(),
    'bmi': core.r1(bmi),
    'pbfPct': pbfPct,
    'bfmKg': bfmKg,
    'ffmKg': ffmKg,
    'smmKg': smmKg,
    // Katch–McArdle — 미리보기용입니다. 기록에는 안 넣습니다(머리말).
    'bmrKcal': core.jsRound(370 + 21.6 * ffmKg),
  };
}

/// 저장할 추정 기록 한 장. 입력이 범위를 벗어나면 null.
///
/// bmrKcal · photoId · inbodyScore 는 **일부러 없습니다** — derive 가 기초대사량을
/// 계산값으로 채우고, 홈의 인바디 점수 칸은 점수가 없으면 스스로 숨습니다.
Map<String, Object?>? estimateScan({
  required Object? sex,
  required num age,
  required num heightCm,
  required num weightKg,
  required DateTime now,
}) {
  final c = estimateComposition(sex: sex, age: age, heightCm: heightCm, weightKg: weightKg);
  if (c == null) return null;
  return {
    'id': 'est-${now.millisecondsSinceEpoch}',
    'measuredAt': now.toUtc().toIso8601String(),
    'weightKg': c['weightKg'],
    'smmKg': c['smmKg'],
    'bfmKg': c['bfmKg'],
    'pbfPct': c['pbfPct'],
    'ffmKg': c['ffmKg'],
    'bmi': c['bmi'],
    'source': kEstimateSource,
    'estimate': {
      'v': 1,
      'method': 'gallagher2000+lee2000(asian)',
      'sex': sex,
      'age': age,
      'heightCm': heightCm,
    },
  };
}

/// 추정 기록을 저장합니다. 프로필이 없거나 성별 · 나이 · 키가 다르면 프로필도 고칩니다.
/// 추정은 한 번에 하나만 — 옛 추정은 묘비와 함께 지웁니다(다른 기기에서도 지워지게).
///
/// 저장했으면 그 기록, 입력이 틀렸거나 기기에 못 썼으면 null.
Map<String, Object?>? saveEstimate(
  core.Store store, {
  required String sex,
  required num age,
  required num heightCm,
  required num weightKg,
  DateTime? now,
}) {
  final t = now ?? (store.now ?? DateTime.now)();
  final scan = estimateScan(sex: sex, age: age, heightCm: heightCm, weightKg: weightKg, now: t);
  if (scan == null) return null;

  final p = (store.get()['profile'] as Map?)?.cast<String, Object?>();
  if (p == null) {
    /* 온보딩을 건너뛴 경우의 기본값 — 온보딩 화면이 고르는 기본과 같습니다. */
    store.set({
      'profile': {
        'sex': sex,
        'age': age.toDouble(),
        'heightCm': heightCm.toDouble(),
        'activityLevel': 'moderate',
        'trainingAge': 'novice',
        'daysPerWeek': 4,
        'sessionMinutes': 60,
        'mealsPerDay': 3,
        'hadPriorPeak': false,
      },
    });
  } else if (p['sex'] != sex ||
      core.jsToNumber(p['age']) != age ||
      core.jsToNumber(p['heightCm']) != heightCm) {
    store.set({
      'profile': {...p, 'sex': sex, 'age': age.toDouble(), 'heightCm': heightCm.toDouble()},
    });
  }

  /* 묘비가 선 이름표를 다시 쓰면 동기화가 새 기록까지 "지운 것" 으로 버립니다.
     같은 밀리초에 두 번 저장하면(시험 · 두 번 누름) 이름표가 겹치니 뒤에 번호를 답니다. */
  final tomb = (store.get()['tombstones'] as Map?)?['scans'];
  final taken = <String>{
    for (final s in store.sortedScans()) '${s['id']}',
    if (tomb is Map) for (final k in tomb.keys) '$k',
  };
  final base = '${scan['id']}';
  var id = base;
  for (var n = 2; taken.contains(id); n++) {
    id = '$base-$n';
  }
  scan['id'] = id;

  for (final s in store.sortedScans()) {
    if (isEstimate(s)) store.removeScan(s['id']);
  }
  store.addScan(scan);
  return store.saved() ? scan : null;
}

/// 친구에게 나갈 스냅샷에서 추정 몸 숫자를 뺍니다. [scans] 는 오름차순.
///
/// · 마지막 측정이 추정 → 몸 숫자 전부(체중 · 근 · 지 · 체지방률 · 변화량 · 진행률).
/// · 그 앞 측정이 추정 → 변화량만(추정 → 실측의 차이는 공식의 오차입니다).
/// · 계획이 추정 위에 세워짐 → 진행률(출발점이 추정입니다).
/// 행동(일정 · 스트릭 · 오늘 식단 · 체크)은 그대로 둡니다.
Map<String, Object?> withoutEstimatedBody(
  Map<String, Object?> snap, {
  required List<Map<String, Object?>> scans,
  Object? plan,
}) {
  final out = Map<String, Object?>.of(snap);
  const deltas = ['dWeightKg', 'dSmmKg', 'dBfmKg'];
  if (scans.isNotEmpty && isEstimate(scans.last)) {
    for (final k in const ['weightKg', 'smmKg', 'bfmKg', 'pbfPct', ...deltas, 'progressPct']) {
      out[k] = null;
    }
  } else if (scans.length >= 2 && isEstimate(scans[scans.length - 2])) {
    for (final k in deltas) {
      out[k] = null;
    }
  }
  if (planFromEstimate(plan)) out['progressPct'] = null;
  return out;
}

/// 홈에 한 번 띄울 「실측으로 바꿨어요」 기록. 닫았거나 7일이 지났으면 null.
/// 시각이 앞날이면(다른 기기의 시계가 빠른 경우) 아직 새것으로 봅니다.
Map<String, Object?>? upgradeNotice(Map<String, Object?> state, DateTime now) {
  final r = state[kEstimateUpgradeKey];
  if (r is! Map) return null;
  final m = r.cast<String, Object?>();
  if (m['seen'] == true) return null;
  final at = DateTime.tryParse('${m['at']}');
  if (at == null) return null;
  if (now.difference(at) >= kUpgradeNoticeFor) return null;
  return m;
}

/// 카드를 닫습니다. 기록을 지우지 않고 'seen' 을 답니다 — 동기화(merge.lww)는
/// null 을 "값 없음" 으로 보고 기준본 없는 합치기에서 저쪽 기록을 되살립니다.
void dismissUpgradeNotice(core.Store store) {
  final r = store.get()[kEstimateUpgradeKey];
  if (r is! Map) return;
  store.set({
    kEstimateUpgradeKey: {...r.cast<String, Object?>(), 'seen': true},
  });
}
