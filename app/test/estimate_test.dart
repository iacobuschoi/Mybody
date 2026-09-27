/* =============================================================================
 * estimate_test.dart — 키 · 체중 추정이 약속한 숫자를 내는가
 *
 * 숫자는 설계 때 손으로 푼 예(오너 남 187cm · 22세 · 86.7kg, 여 162 · 25 · 58,
 * 작은 70세 여성의 골격근 묶음)를 그대로 봅니다. 공식이 한 자리라도 어긋나면
 * 여기서 먼저 깨집니다.
 *
 * 추정 기록은 엔진의 검사(validateScan · 검산)를 전부 통과해야 합니다 — 안 그러면
 * 추정으로 시작한 사람이 첫 화면부터 "물리적으로 맞지 않는 값" 을 봅니다.
 *
 * 친구에게 나갈 스냅샷 거르기 · 「실측으로 바꿨어요」 카드의 수명 · 동기화에서
 * 묘비가 추정을 지우는지도 여기서 봅니다(합치기는 순수 함수라 저장소 없이).
 * ========================================================================== */
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mybody/src/estimate.dart';
import 'package:mybody/src/estimate_upgrade.dart';
import 'package:mybody/src/merge.dart';
import 'package:mybody_core/mybody_core.dart' as core;

const _profile = {
  'sex': 'male', 'age': 22, 'heightCm': 187, 'activityLevel': 'moderate',
  'trainingAge': 'novice', 'daysPerWeek': 4, 'mealsPerDay': 3,
};

Map<String, Object?> _real({String id = 'r1', String at = '2026-09-20T00:00:00.000Z'}) => {
      'id': id, 'measuredAt': at, 'weightKg': 86.7, 'smmKg': 38.0, 'bfmKg': 20.0,
      'pbfPct': 23.1, 'ffmKg': 66.7, 'bmi': 24.8, 'bmrKcal': 1810,
    };

Map<String, Object?> _copy(Map<String, Object?> m) =>
    (jsonDecode(jsonEncode(m)) as Map).cast<String, Object?>();

List<Object?> _ids(Object? list) => [for (final x in list as List) (x as Map)['id']];

void main() {
  group('estimateComposition — 공식', () {
    test('남 187cm · 22세 · 86.7kg → 22.1% · 19.2 · 67.5 · 35.7 · BMI 24.8 · 1828kcal', () {
      final c = estimateComposition(sex: 'male', age: 22, heightCm: 187, weightKg: 86.7)!;
      expect(c['pbfPct'], 22.1);
      expect(c['bfmKg'], 19.2);
      expect(c['ffmKg'], 67.5);
      expect(c['smmKg'], 35.7);
      expect(c['bmi'], 24.8);
      expect(c['bmrKcal'], 1828);
      expect(c['weightKg'], 86.7);
      expect(c['heightCm'], 187.0);
    });

    test('여 162cm · 25세 · 58kg → 30.9% · 17.9 · 40.1 · 19.8 · BMI 22.1 · 1236kcal', () {
      final c = estimateComposition(sex: 'female', age: 25, heightCm: 162, weightKg: 58)!;
      expect(c['pbfPct'], 30.9);
      expect(c['bfmKg'], 17.9);
      expect(c['ffmKg'], 40.1);
      expect(c['smmKg'], 19.8);
      expect(c['bmi'], 22.1);
      expect(c['bmrKcal'], 1236);
    });

    test('골격근 묶음 — 여 155cm · 70세 · 45kg 은 Lee 가 11.7kg(제지방의 34%)이라 45% 로 올린다', () {
      final c = estimateComposition(sex: 'female', age: 70, heightCm: 155, weightKg: 45)!;
      expect(c['pbfPct'], 23.1);
      expect(c['ffmKg'], 34.6);
      expect(c['smmKg'], 15.6);
      final k = (c['smmKg'] as num) / (c['ffmKg'] as num);
      expect(k, greaterThanOrEqualTo(0.45));
    });

    test('나이는 18~90 으로 묶어 식에 넣는다 — 15세는 18세와 같은 숫자', () {
      final a = estimateComposition(sex: 'male', age: 15, heightCm: 175, weightKg: 70)!;
      final b = estimateComposition(sex: 'male', age: 18, heightCm: 175, weightKg: 70)!;
      expect(a, b);
    });

    test('범위를 벗어난 입력은 null — 성별 · 키 · 체중 · NaN · BMI', () {
      expect(estimateComposition(sex: 'x', age: 22, heightCm: 187, weightKg: 86.7), isNull);
      expect(estimateComposition(sex: null, age: 22, heightCm: 187, weightKg: 86.7), isNull);
      expect(estimateComposition(sex: 'male', age: 22, heightCm: 90, weightKg: 86.7), isNull);
      expect(estimateComposition(sex: 'male', age: 22, heightCm: 187, weightKg: 20), isNull);
      expect(estimateComposition(sex: 'male', age: double.nan, heightCm: 187, weightKg: 86.7),
          isNull);
      expect(estimateComposition(sex: 'male', age: 22, heightCm: 187, weightKg: double.nan),
          isNull);
      expect(estimateComposition(sex: 'male', age: 9, heightCm: 187, weightKg: 86.7), isNull);
      // 230cm · 25kg → BMI 4.7
      expect(estimateComposition(sex: 'male', age: 22, heightCm: 230, weightKg: 25), isNull);
    });
  });

  group('estimateScan — 저장할 한 장', () {
    final now = DateTime.utc(2026, 9, 27, 3);
    final scan = estimateScan(sex: 'male', age: 22, heightCm: 187, weightKg: 86.7, now: now)!;

    test('엔진 검사를 전부 통과한다 — validateScan · 검산', () {
      expect(core.validateScan(scan, null), isNull);
      final r = core.run(scan, _profile, null);
      final checks = (r['checks'] as List).cast<Map>();
      expect(checks, isNotEmpty);
      for (final c in checks) {
        expect(c['ok'], isTrue, reason: '${c['id']} ${c['label']} — ${c['why']}');
      }
      expect(r['rangeIssues'], isEmpty);
    });

    test('기초대사량은 derive 가 계산값으로 채운다 — 기록엔 없음', () {
      expect(scan.containsKey('bmrKcal'), isFalse);
      expect(scan.containsKey('photoId'), isFalse);
      expect(scan.containsKey('inbodyScore'), isFalse);
      final d = core.derive(scan, _profile);
      expect(d['bmrSource'], 'Katch-McArdle 계산값');
      expect(d['bmrKcal'], 1828);
    });

    test('표시와 모양', () {
      expect(scan['source'], kEstimateSource);
      expect(scan['id'], 'est-${now.millisecondsSinceEpoch}');
      expect(scan['measuredAt'], '2026-09-27T03:00:00.000Z');
      expect(scan['weightKg'], 86.7);
      expect(scan['smmKg'], 35.7);
      final e = (scan['estimate'] as Map).cast<String, Object?>();
      expect(e['v'], 1);
      expect(e['method'], 'gallagher2000+lee2000(asian)');
      expect(e['sex'], 'male');
      expect(e['heightCm'], 187);
      expect(estimateScan(sex: 'x', age: 22, heightCm: 187, weightKg: 86.7, now: now), isNull);
    });
  });

  group('판별', () {
    final est = {'id': 'e', 'source': 'estimate', 'measuredAt': '2026-09-10T00:00:00.000Z'};
    final ocr = {'id': 'o', 'source': 'ocr', 'measuredAt': '2026-09-01T00:00:00.000Z'};
    final plain = {'id': 'p', 'measuredAt': '2026-09-20T00:00:00.000Z'};

    test('isEstimate · planFromEstimate', () {
      expect(isEstimate(est), isTrue);
      expect(isEstimate(ocr), isFalse);
      expect(isEstimate(plain), isFalse);
      expect(isEstimate(null), isFalse);
      expect(isEstimate('estimate'), isFalse);
      expect(planFromEstimate({'fromEstimate': true}), isTrue);
      expect(planFromEstimate({'fromEstimate': 'true'}), isFalse);
      expect(planFromEstimate({'level': 'mid'}), isFalse);
      expect(planFromEstimate(null), isFalse);
    });

    test('realScans 는 순서를 지키고, chartScans 는 실측이 없을 때만 추정', () {
      expect(realScans([ocr, est, plain]), [ocr, plain]);
      expect(chartScans([ocr, est, plain]), [ocr, plain]);
      expect(chartScans([est]), [est]);
      expect(chartScans(<Map<String, Object?>>[]), isEmpty);
    });

    test('needsEstimateUpgrade — 실측이 있고 (추정 기록 또는 추정 계획)', () {
      expect(needsEstimateUpgrade({'scans': [est]}), isFalse, reason: '추정뿐');
      expect(needsEstimateUpgrade({'scans': [plain]}), isFalse, reason: '실측뿐');
      expect(needsEstimateUpgrade({'scans': [est, plain]}), isTrue, reason: '둘 다');
      expect(needsEstimateUpgrade({'scans': [plain, est]}), isTrue, reason: '순서 무관');
      expect(needsEstimateUpgrade({'scans': [plain], 'plan': {'fromEstimate': true}}), isTrue,
          reason: '추정 계획 + 실측');
      expect(needsEstimateUpgrade({'scans': [est], 'plan': {'fromEstimate': true}}), isFalse);
      expect(needsEstimateUpgrade({'scans': <Object?>[]}), isFalse);
      expect(needsEstimateUpgrade({'scans': null}), isFalse);
      expect(needsEstimateUpgrade({'scans': ['junk', est, 3]}), isFalse, reason: 'Map 아닌 것은 건너뜀');
    });
  });

  group('saveEstimate', () {
    test('두 번째가 첫 번째를 바꾼다 — 추정은 하나, 첫 것엔 묘비', () {
      final store = core.Store();
      store.set({'profile': Map<String, Object?>.of(_profile)});
      final t = DateTime.utc(2026, 9, 27);
      final a = saveEstimate(store, sex: 'male', age: 22, heightCm: 187, weightKg: 86.7, now: t)!;
      final b = saveEstimate(store, sex: 'male', age: 22, heightCm: 187, weightKg: 85.0,
          now: t.add(const Duration(minutes: 1)))!;
      final scans = store.sortedScans();
      expect(scans.where(isEstimate), hasLength(1));
      expect(scans.single['id'], b['id']);
      expect(scans.single['weightKg'], 85.0);
      final tomb = ((store.get()['tombstones'] as Map)['scans'] as Map);
      expect(tomb.containsKey(a['id']), isTrue);
      expect(tomb.containsKey(b['id']), isFalse, reason: '살아 있는 기록엔 묘비가 없다');
    });

    test('같은 밀리초에 두 번 — 이름표가 겹치지 않는다(묘비 선 이름표를 다시 쓰지 않음)', () {
      final store = core.Store();
      store.set({'profile': Map<String, Object?>.of(_profile)});
      final t = DateTime.utc(2026, 9, 27);
      final a = saveEstimate(store, sex: 'male', age: 22, heightCm: 187, weightKg: 86.7, now: t)!;
      final b = saveEstimate(store, sex: 'male', age: 22, heightCm: 187, weightKg: 86.0, now: t)!;
      expect(b['id'], isNot(a['id']));
      final tomb = ((store.get()['tombstones'] as Map)['scans'] as Map);
      expect(tomb.containsKey(b['id']), isFalse);
      expect(store.sortedScans().single['id'], b['id']);
    });

    test('프로필이 없으면 만들고, 키가 다르면 고친다', () {
      final store = core.Store();
      expect(store.get()['profile'], isNull);
      saveEstimate(store, sex: 'female', age: 25, heightCm: 162, weightKg: 58);
      final p = (store.get()['profile'] as Map).cast<String, Object?>();
      expect(p['sex'], 'female');
      expect(p['age'], 25.0);
      expect(p['heightCm'], 162.0);
      expect(p['activityLevel'], 'moderate');
      expect(p['trainingAge'], 'novice');
      expect(p['daysPerWeek'], 4);

      store.set({'profile': {...p, 'mealsPerDay': 4}});
      saveEstimate(store, sex: 'female', age: 25, heightCm: 165, weightKg: 58);
      final q = (store.get()['profile'] as Map).cast<String, Object?>();
      expect(q['heightCm'], 165.0);
      expect(q['mealsPerDay'], 4, reason: '나머지는 그대로');
    });

    test('입력이 틀리면 아무것도 안 바꾸고 null', () {
      final store = core.Store();
      expect(saveEstimate(store, sex: 'male', age: 22, heightCm: 187, weightKg: 10), isNull);
      expect(store.get()['profile'], isNull);
      expect(store.sortedScans(), isEmpty);
    });
  });

  group('withoutEstimatedBody — 친구에게 나갈 것', () {
    final snap = <String, Object?>{
      'weightKg': 86.7, 'smmKg': 35.7, 'bfmKg': 19.2, 'pbfPct': 22.1,
      'dWeightKg': -0.5, 'dSmmKg': 0.2, 'dBfmKg': -0.7, 'progressPct': 10,
      'checkedIn': true, 'plannedDays': 3, 'today': {'logged': true},
      'week': {'start': '2026-09-21'}, 'streaks': {'workoutDays': 2},
    };
    final est = {'id': 'e', 'source': 'estimate', 'measuredAt': '2026-09-10T00:00:00.000Z'};
    final real = {'id': 'r', 'measuredAt': '2026-09-20T00:00:00.000Z'};
    final older = {'id': 'o', 'measuredAt': '2026-09-01T00:00:00.000Z'};

    test('마지막이 추정 → 몸 숫자 전부 null, 행동은 그대로', () {
      final out = withoutEstimatedBody(snap, scans: [real, est]);
      for (final k in ['weightKg', 'smmKg', 'bfmKg', 'pbfPct', 'dWeightKg', 'dSmmKg', 'dBfmKg',
        'progressPct']) {
        expect(out[k], isNull, reason: k);
      }
      expect(out['checkedIn'], true);
      expect(out['plannedDays'], 3);
      expect(out['today'], snap['today']);
      expect(out['week'], snap['week']);
      expect(out['streaks'], snap['streaks']);
      expect(snap['weightKg'], 86.7, reason: '원본은 건드리지 않는다');
    });

    test('그 앞이 추정 → 변화량만 null', () {
      final out = withoutEstimatedBody(snap, scans: [est, real]);
      expect(out['weightKg'], 86.7);
      expect(out['smmKg'], 35.7);
      expect(out['progressPct'], 10);
      expect(out['dWeightKg'], isNull);
      expect(out['dSmmKg'], isNull);
      expect(out['dBfmKg'], isNull);
    });

    test('추정 위에 세운 계획 → 진행률만 null', () {
      final out = withoutEstimatedBody(snap, scans: [older, real], plan: {'fromEstimate': true});
      expect(out['progressPct'], isNull);
      expect(out['weightKg'], 86.7);
      expect(out['dBfmKg'], -0.7);
    });

    test('실측뿐이면 그대로', () {
      expect(withoutEstimatedBody(snap, scans: [older, real], plan: {'level': 'mid'}), snap);
      expect(withoutEstimatedBody(snap, scans: const []), snap);
    });
  });

  group('「실측으로 바꿨어요」 카드의 수명', () {
    final now = DateTime.utc(2026, 9, 27, 12);
    Map<String, Object?> rec(DateTime at, {bool? seen}) => {
          kEstimateUpgradeKey: {
            'at': at.toIso8601String(), 'plan': 'none',
            'before': {'smmKg': 35.7}, 'after': {'smmKg': 38.0},
            if (seen != null) 'seen': seen,
          },
        };

    test('막 생긴 것은 보이고, 8일 지난 것 · 닫은 것은 안 보인다', () {
      expect(upgradeNotice(rec(now.subtract(const Duration(hours: 1))), now), isNotNull);
      expect(upgradeNotice(rec(now.add(const Duration(hours: 3))), now), isNotNull,
          reason: '다른 기기 시계가 빨라도 새것');
      expect(upgradeNotice(rec(now.subtract(const Duration(days: 8))), now), isNull);
      expect(upgradeNotice(rec(now, seen: true), now), isNull);
      expect(upgradeNotice(const {}, now), isNull);
      expect(upgradeNotice({kEstimateUpgradeKey: {'at': 'x'}}, now), isNull);
    });

    test('닫으면 seen: true — null 로 지우지 않는다(동기화가 되살림)', () {
      final store = core.Store(now: () => now);
      dismissUpgradeNotice(store); // 기록이 없으면 아무 일 없음
      expect(store.get().containsKey(kEstimateUpgradeKey), isFalse);
      store.set(rec(now));
      expect(upgradeNotice(store.get(), now), isNotNull);
      dismissUpgradeNotice(store);
      final r = (store.get()[kEstimateUpgradeKey] as Map).cast<String, Object?>();
      expect(r['seen'], true);
      expect(r['plan'], 'none', reason: '나머지는 그대로');
      expect(upgradeNotice(store.get(), now), isNull);
    });
  });

  group('동기화 — 묘비가 다른 기기의 추정을 지운다', () {
    test('기준본이 있어도 없어도, 합친 측정에 추정이 없다', () {
      final store = core.Store(now: () => DateTime.utc(2026, 9, 2));
      store.set({'profile': Map<String, Object?>.of(_profile), 'onboarded': true});
      final est = saveEstimate(store, sex: 'male', age: 22, heightCm: 187, weightKg: 86.7,
          now: DateTime.utc(2026, 9, 1))!;
      final base = _copy(store.get());
      store.addScan(_real(at: '2026-09-02T00:00:00.000Z'));
      expect(upgradeEstimates(store), isNotNull);
      final local = _copy(store.get());
      expect(_ids(local['scans']), ['r1']);
      final remote = _copy(base);
      expect(_ids(remote['scans']), [est['id']]);

      final m1 = mergeStates(local, remote,
          localAt: '2026-09-02T00:00:00.000Z', remoteAt: '2026-09-01T00:00:00.000Z',
          base: base, baseAt: '2026-09-01T00:00:00.000Z');
      expect(_ids(m1['scans']), ['r1']);

      final m2 = mergeStates(local, remote,
          localAt: '2026-09-02T00:00:00.000Z', remoteAt: '2026-09-01T00:00:00.000Z');
      expect(_ids(m2['scans']), ['r1'], reason: '기준본 없이도 묘비의 합집합이 지운다');
      expect(((m2['tombstones'] as Map)['scans'] as Map).containsKey(est['id']), isTrue);
    });
  });
}
