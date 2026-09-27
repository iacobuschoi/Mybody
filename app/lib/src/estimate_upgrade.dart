/* =============================================================================
 * estimate_upgrade.dart — 첫 실측이 들어오면 추정을 걷어 내고 계획을 다시 세웁니다
 *
 * 키 · 체중으로 시작한 사람(estimate.dart)이 나중에 인바디를 넣으면, 그때부터는
 * 실측이 사실입니다. 추정 기록을 옆에 남겨 두면 그래프가 추정 → 실측으로 선을
 * 긋고(몸이 아니라 공식의 오차를 그립니다), 계획의 출발점은 여전히 추정 몸입니다.
 * 그래서 첫 실측이 저장되는 순간:
 *
 *   1. 추정 기록을 **묘비와 함께** 지웁니다(store.removeScan). 동기화가 묘비를
 *      합치므로 추정을 받아 간 다른 기기에서도 지워집니다.
 *   2. 추정 위에 세운 계획(plan.fromEstimate)이면 실측 몸에서 다시 세웁니다.
 *   3. 무엇이 바뀌었는지 기록을 하나 남깁니다(state.estimateUpgrade) — 홈이
 *      「실측으로 바꿨어요」 카드로 한 번 보여 줍니다.
 *
 * ── 다시 세울 때 **사람이 원한 것**을 지킵니다 ───────────────────────────────
 *   · 목표 체중은 **그대로**(절대값). 체중은 추정한 적이 없습니다 — 저울에서
 *     읽은 값입니다. 공식이 틀렸다고 목표 체중이 움직이면 아무도 반기지 않습니다.
 *   · 목표 골격근은 **변화량**을 옮깁니다: 실측 + (목표 − 출발점). 추정 36.7kg
 *     목표는 "추정 35.7 + 1kg" 이라는 뜻이었습니다. 절대값 36.7 을 그대로 두면
 *     실측 38.0 보다 낮아서 "근육을 빼라" 로 방향이 뒤집힙니다. 변화량을 옮기면
 *     사람마다 일정한 공식의 치우침(오너는 −2.3kg)이 계획을 흔들지 못합니다.
 *   · 목표 체지방은 체중 − 골격근 ÷ (실측 골격근/제지방) 으로 맞춥니다. 그래야 세
 *     숫자가 서로 맞고(classifyGoal 어긋남 0) 모드 규칙의 "세 숫자가 안 맞음" 거절이
 *     서지 않습니다. 체지방 변화량은 원래와 0.1~0.3kg 안쪽이라 속도 · 주수 · 칼로리는
 *     거의 안 움직입니다.
 *   · 마감 · 직접 고른 모드 · 강도(상/중/하) · 계획의 모드는 그대로. 시작일은 오늘.
 *   · 변화량은 **같은 틀**끼리 뺍니다(목표 − 궤적 첫 점, 둘 다 추정 기준). 다른 기기가
 *     먼저 바꾼 목표(이미 실측 기준)가 동기화로 추정 계획과 섞이면 계획의 goal 을
 *     씁니다 — 안 그러면 변화량이 두 번 얹힙니다(아래 intent).
 *
 *   예 (오너, 진짜 엔진으로 돌린 것): 추정 {체중 81.6 · 골격근 36.7 · 체지방 12.2}
 *   중 30주 → 실측 {81.6 · 39.0 · 13.1} 중 27주. 실측 몸에서의 변화는
 *   체중 −5.1 · 근육 +1.0 · 지방 −6.9 로, 추정 몸에서의 −5.1 · +1.0 · −7.0 과 같은 뜻입니다.
 *
 * ── 안전이 먼저입니다 ──────────────────────────────────────────────────────
 *   옮긴 목표를 목표 화면과 **같은 규칙**(selectGoalMode)에 다시 넣습니다. 추정 몸에서는
 *   괜찮던 목표가 실측 몸에서는 하한(남 8% · 여 15%) 아래이거나 속도 상한을 넘을 수
 *   있습니다. 거절되면 목표는 옮긴 값으로 두고 계획은 비웁니다 — 홈이 「목표 다시
 *   정하기」를 권하고, 목표 화면은 옮긴 값으로 열려 거절 이유를 보여 줍니다. 규칙을
 *   통과해도 compareLevels 가 불가능이라 하거나 열린 강도가 없으면 같은 길로 갑니다.
 *
 * ── 어디서 불리나 ──────────────────────────────────────────────────────────
 *   · 검수 화면(review.dart)이 저장 직후 바로 — 토스트 문구를 정하려고.
 *   · AppState 의 store.onChange 와 부팅 — 동기화 · 백업 가져오기 · 옛 판 기기가 실측을
 *     들여온 경우. 어느 기기든 섞인 상태를 처음 본 쪽이 정리합니다.
 *   멱등입니다: 한 번 돌면 추정 기록도 fromEstimate 계획도 남지 않아 두 번째는 null.
 *
 * 목표 화면의 규칙(selectGoalMode)과 강도 표 읽기(resultsOf · isBlocked)를 화면
 * 파일에서 가져옵니다. scope.dart 를 거치는 import 고리가 생기지만 Dart 에선 문제가
 * 없고, 규칙을 두 벌 두는 것보다 낫습니다.
 * ========================================================================== */
import 'package:mybody_core/mybody_core.dart' as core;

import 'estimate.dart';
import 'screens/goal.dart' show selectGoalMode;
import 'screens/intensity.dart' show resultsOf, isBlocked;

/// goalHistory 에 남는 바뀐 이유.
const String kUpgradeReason = '실측으로 바꿈';

Map<String, Object?>? _mapOf(Object? x) => x is Map ? x.cast<String, Object?>() : null;

/// 숫자면 숫자, 아니면 NaN. jsToNumber 는 null 을 0 으로 읽어서, 빠진 칸이
/// "0kg 목표" 로 조용히 둔갑합니다.
double _num(Object? x) => x is num ? x.toDouble() : double.nan;

Map<String, Object?> _body3(Map<String, Object?> m) => {
      'weightKg': m['weightKg'], 'smmKg': m['smmKg'], 'bfmKg': m['bfmKg'],
    };

/// 카드에 쓸 네 숫자 — 계획 궤적의 골격근 · 체지방은 소수 둘째 자리라 첫째로 맞춥니다.
/// 못 읽은 칸은 null. 이 기록은 저장소에 그대로 들어가는데 JSON 은 NaN 을 못 적습니다 —
/// NaN 하나가 들어가면 그 뒤로 **모든 저장이 실패**합니다(골격근 칸이 빠진 옛 기록의
/// derive 가 NaN 을 냅니다).
Map<String, Object?> _body4(Map<String, Object?> m) => {
      for (final k in const ['weightKg', 'smmKg', 'bfmKg', 'pbfPct'])
        k: _finiteOrNull(core.r1(core.jsToNumber(m[k]))),
    };

double? _finiteOrNull(double x) => x.isFinite ? x : null;

/// 추정을 걷어 내고, 추정 위에 세운 계획이면 실측에서 다시 세웁니다.
/// 할 일이 없으면 null, 했으면 state[kEstimateUpgradeKey] 에 쓴 기록.
Map<String, Object?>? upgradeEstimates(core.Store store) {
  final st = store.get();
  if (!needsEstimateUpgrade(st)) return null;

  /* --- 바꾸기 전에 전부 잡아 둡니다 — 지우고 나면 추정 몸은 다시 못 읽습니다. */
  final all = store.sortedScans();
  final est = [for (final s in all) if (isEstimate(s)) s];
  final real = realScans(all);
  if (real.isEmpty) return null;
  final profile = _mapOf(st['profile']) ?? core.kSeedProfile;
  final oldPlan = _mapOf(st['plan']);
  final oldGoal = _mapOf(st['goal']);
  final fromEst = planFromEstimate(oldPlan);
  final tr = oldPlan?['trajectory'];
  final traj0 = tr is List && tr.isNotEmpty ? _mapOf(tr.first) : null;
  final beforeSrc = est.isNotEmpty ? core.derive(est.last, profile) : traj0;
  final realLatest = real.last;
  final after = core.derive(realLatest, profile);

  /* 사람이 원한 목표를 **어느 틀에서** 읽나. 계획의 goal 과 궤적 첫 점은 buildPlan 이
     한 몸에서 같이 만든 짝이라 늘 같은 틀(추정)입니다. state.goal 도 한 기기 안에서는
     그 짝과 같은 숫자입니다(목표와 계획은 늘 같이 저장됩니다). 다른 것은 동기화가
     엇갈렸을 때뿐입니다: 기기 A 가 먼저 실측으로 바꿨는데(목표 · 계획 둘 다) 기기 B 가
     아직 옛 추정 계획에 체크인을 했다면, 합치면 목표는 A 것(이미 실측 기준) · 계획은
     B 것(추정 기준, fromEstimate)입니다. 그 목표에 변화량을 또 얹으면 골격근이 두 번
     밀립니다 — 오너로 39.0 → 41.3kg, 27 → 62주. 목표가 지난 바꾸기 기록의 goalAfter
     와 같으면 이미 옮긴 것이니, 뜻은 계획의 goal(궤적 첫 점과 같은 틀)에서 읽습니다. */
  final prevRec = _mapOf(st[kEstimateUpgradeKey]);
  final planGoal = _mapOf(oldPlan?['goal']);
  final alreadyMoved = oldGoal != null &&
      planGoal != null &&
      prevRec != null &&
      core.Store.sameGoal(oldGoal, _mapOf(prevRec['goalAfter']));
  final intent = alreadyMoved ? planGoal : oldGoal;

  /* --- 1. 추정 기록을 지웁니다. 묘비가 다음 동기화에 실려 다른 기기에서도 지웁니다. */
  for (final e in est) {
    store.removeScan(e['id']);
  }

  var planState = 'none';
  Map<String, Object?>? goalBefore, goalAfter;
  Object? weeksBefore, weeksAfter;
  String? reason;

  /* --- 2. 추정 위에 세운 계획이면 다시 세웁니다. 아니면(옛 계획 · 실측 계획) 손대지 않습니다. */
  if (fromEst) {
    goalBefore = intent == null ? null : _body3(intent);
    weeksBefore = oldPlan!['weeks'];
    void clearPlan() => store.set({'plan': null, 'baselinePlan': null});
    void needsGoal(String why) {
      clearPlan();
      planState = 'needsGoal';
      reason = why;
    }

    if (oldGoal == null || intent == null) {
      needsGoal('목표가 없습니다');
    } else {
      final anchor = traj0 ?? beforeSrc;
      final w = _num(intent['weightKg']);                    // 체중은 저울 값 — 그대로
      final smm = core.r1(core.jsToNumber(after['smmKg']) +
          (_num(intent['smmKg']) - _num(anchor?['smmKg']))); // 고른 근육 변화량을 옮김
      final k = core.jsToNumber(after['smmToFfm']);
      final bfm = core.r1(w - smm / k);                       // 실측 비율로 세 숫자를 맞춤
      if ([w, smm, bfm].any((x) => !x.isFinite || x <= 0)) {
        /* 목표는 건드리지 않습니다 — 옮기지 못한 값을 목표로 박아 두면 목표 화면이
           그 이상한 값으로 열립니다. 원래 목표로 열리는 편이 고치기 쉽습니다. */
        needsGoal('실측 기준으로 목표를 옮기지 못했어요');
      } else {
        final newGoal = <String, Object?>{
          for (final e in oldGoal.entries)
            if (e.key != 'setAt') e.key: e.value,
          'weightKg': w, 'smmKg': smm, 'bfmKg': bfm,
        };
        final goal3 = _body3(newGoal);
        final sel = selectGoalMode(
          scans: store.sortedScans(), // 이제 실측뿐
          cur: after,
          goal: newGoal,
          profile: profile,
          deadlineWeeks: newGoal['deadlineWeeks'],
        );
        if (sel['refused'] == true) {
          store.setGoal(newGoal, kUpgradeReason);
          goalAfter = goal3;
          needsGoal('${sel['message']}');
        } else {
          /* 계획의 모드를 그대로 — 기간 길로 세운 계획은 모드가 null 이고 null 로 둡니다. */
          final pm = oldPlan['mode'];
          final modeDef = pm is Map && pm['id'] != null ? core.modeById(pm['id']) : null;
          final cmp = core.compareLevels(realLatest, profile, newGoal, store.dayKey(),
              newGoal['deadlineWeeks'], modeDef);
          if (cmp['impossible'] == true) {
            final warns = (cmp['warnings'] as List?) ?? const [];
            store.setGoal(newGoal, kUpgradeReason);
            goalAfter = goal3;
            needsGoal(warns.isEmpty ? '고를 수 있는 계획이 없어요' : '${warns.first}');
          } else {
            /* 강도는 원래 것이 열려 있으면 그것, 아니면 추천, 그것도 막혔으면 첫 열린 것. */
            final open = [for (final r in resultsOf(cmp)) if (!isBlocked(r)) r];
            Object? level;
            if (open.any((r) => r['level'] == oldPlan['level'])) {
              level = oldPlan['level'];
            } else if (open.any((r) => r['level'] == cmp['recommended'])) {
              level = cmp['recommended'];
            } else if (open.isNotEmpty) {
              level = open.first['level'];
            }
            final plan =
                level == null ? null : core.buildPlan(cmp, level, realLatest, profile);
            store.setGoal(newGoal, kUpgradeReason);
            goalAfter = goal3;
            if (plan == null) {
              needsGoal('고를 수 있는 계획이 없어요');
            } else {
              /* 옛 기준 계획(baselinePlan)도 추정 몸에서 출발한 궤적이라 같이 버립니다 —
                 setPlan 이 새 계획으로 기준을 다시 세웁니다. 새 계획엔 fromEstimate 가 없습니다. */
              clearPlan();
              store.setPlan(plan);
              planState = 'rebuilt';
              weeksAfter = plan['weeks'];
            }
          }
        }
      }
    }
  }

  /* --- 3. 기록 — 홈 카드가 한 번 보여 줍니다. 동기화되니 다른 기기에서도 한 번. */
  final record = <String, Object?>{
    'at': (store.now ?? DateTime.now)().toUtc().toIso8601String(),
    'before': beforeSrc == null ? null : _body4(beforeSrc),
    'after': _body4(after),
    'plan': planState,
    'goalBefore': goalBefore,
    'goalAfter': goalAfter,
    'weeksBefore': weeksBefore,
    'weeksAfter': weeksAfter,
    'reason': reason,
  };
  store.set({kEstimateUpgradeKey: record});
  return record;
}
