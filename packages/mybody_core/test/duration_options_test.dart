/* 「기간으로 목표 정하기」 — W 주 안에 갈 수 있는 곳을 감량 하 · 중 · 상 세 장과 증량 한 장으로.
 *
 * 목표를 먼저 정하는 대신 기간을 먼저 정하는 길입니다. 엔진은 목표를 아주 멀리 두고
 * 시뮬레이션을 W 주까지 돌려 그 주의 몸을 읽습니다. 여기서 보는 것은 방향 · 단조성 ·
 * 합치기 · 추천 · 범위 접기 · 이상한 입력 · 궤적 길이, 그리고 세 가지 약속입니다:
 *   · 감량 카드는 이 앱의 체지방률 하한(남 8% · 여 15%) 밑으로 내려가지 않는다
 *   · 인바디 오차 안의 변화만 남는 카드는 내지 않는다 (뒤에서 유지 계획이 되므로)
 *   · 증량은 한 장 — compareLevels 가 실제로 만들 계획과 같은 a 로
 * JS 원본과 같은 답인지는 tools/difftest.js 가 봅니다. */
import 'package:mybody_core/engine.dart';
import 'package:mybody_core/modes.dart' show byId;
import 'package:test/test.dart';

const scanOwner = {
  'weightKg': 86.7, 'smmKg': 38.0, 'bfmKg': 20.0, 'pbfPct': 23.1, 'ffmKg': 66.7,
  'bmrKcal': 1810, 'measuredAt': '2026-03-01T00:00:00.000Z',
};
const profOwner = {
  'sex': 'male', 'age': 22, 'heightCm': 187, 'activityLevel': 'moderate',
  'trainingAge': 'novice', 'daysPerWeek': 4, 'mealsPerDay': 3,
};
/// 여성 입문자 — 58kg · 근육 22 · 지방 16 (27.6%).
const scanWoman = {'weightKg': 58.0, 'smmKg': 22.0, 'bfmKg': 16.0};
final Map<String, Object?> profWoman = {...profOwner, 'sex': 'female'};

Map<String, Object?> run(Map<String, Object?> scan, Map<String, Object?> profile, Object? weeks,
        [Map<String, Object?>? modeDef]) =>
    durationOptions({...scan}, {...profile}, weeks, '2026-03-01', modeDef);

List<Map<String, Object?>> optionsOf(Map<String, Object?> d) =>
    (d['options'] as List).cast<Map<String, Object?>>();
List<Map<String, Object?>> dirOf(Map<String, Object?> d, String k) =>
    optionsOf(d).where((o) => o['direction'] == k).toList();
List<String> warnsOf(Map<String, Object?> d) => [for (final w in (d['warnings'] as List)) '$w'];
num goalOf(Map<String, Object?> o, String k) => (o['goal'] as Map)[k] as num;
num deltaOf(Map<String, Object?> o, String k) => (o['delta'] as Map)[k] as num;
/// 카드의 목표를 목표 화면이 읽듯 분류하면 무엇이 되는지 — 이게 뒤에서 만들어질 계획입니다.
String typeOf(Map<String, Object?> d, Map<String, Object?> o) =>
    classifyGoal(d['current'] as Map<String, Object?>, o['goal'] as Map<String, Object?>)['type']
        as String;
/// 목표 화면과 같은 식 — 카드가 넘기는 세 숫자로 계산한 체지방률.
double pbfOf(Map p) => (p['bfmKg'] as num) / (p['weightKg'] as num) * 100;

void main() {
  final d12 = run(scanOwner, profOwner, 12);

  test('12주: 감량은 지방이 지금보다 적고, 증량은 근육이 지금보다 많다', () {
    expect(d12['weeks'], 12);
    final cuts = dirOf(d12, 'cut'), bulks = dirOf(d12, 'bulk');
    expect(cuts, isNotEmpty);
    expect(bulks, isNotEmpty);
    for (final o in cuts) {
      expect(goalOf(o, 'bfmKg'), lessThan(20.0), reason: o['id'] as String);
      expect(deltaOf(o, 'bfmKg'), lessThan(0));
      expect(o['directionLabel'], '감량');
    }
    for (final o in bulks) {
      expect(goalOf(o, 'smmKg'), greaterThan(38.0), reason: o['id'] as String);
      expect(deltaOf(o, 'smmKg'), greaterThan(0));
      expect(o['directionLabel'], '증량');
    }
  });

  test('강도가 높을수록 감량 변화가 크거나 같다 — 증량은 한 장이라 비교할 것이 없다', () {
    final cuts = dirOf(d12, 'cut');
    expect(cuts.length, 3);
    for (var i = 1; i < cuts.length; i++) {
      expect(goalOf(cuts[i], 'bfmKg'), lessThanOrEqualTo(goalOf(cuts[i - 1], 'bfmKg')));
      expect(cuts[i]['a'] as num, greaterThan(cuts[i - 1]['a'] as num));
    }
    expect(dirOf(d12, 'bulk').length, 1);
  });

  test('카드 모양 — id · 라벨 · 공격성 · 매크로 · 운동 · 날짜', () {
    final o = optionsOf(d12).first;
    expect(o['id'], 'cut-low');
    expect(o['level'], 'low');
    expect(o['label'], '하');
    expect(o['levels'], ['low']);
    expect(o['a'], 0.2);
    expect(dirOf(d12, 'cut').map((x) => x['a']), [0.2, 0.5, 0.8]);
    expect(o['intakeKcal'] as num, greaterThan(1500));
    expect(o['proteinG'] as num, greaterThan(100));
    expect(o['daysPerWeek'], 4);
    expect(o['sessionMinutes'], isA<num>());
    expect((o['goal'] as Map).keys, containsAll(['weightKg', 'smmKg', 'bfmKg', 'pbfPct']));
    expect((o['delta'] as Map).keys, containsAll(['weightKg', 'smmKg', 'bfmKg', 'pbfPct']));
    expect(deltaOf(o, 'weightKg'), closeTo(goalOf(o, 'weightKg') - 86.7, 0.051), reason: 'r1 로 반올림한 차이');
    expect(d12['startDate'], '2026-03-01');
    expect(d12['targetDate'], '2026-05-24');
    expect(d12['mode'], isNull);

    /* 증량 한 장 — id 는 예전의 '중' 자리를 그대로 써서 화면이 찾던 열쇠가 바뀌지 않고,
       라벨은 '증량', 세 강도 이름을 다 답니다. 공격성은 범위의 아래 끝(모드 없음 → 0). */
    final b = dirOf(d12, 'bulk').single;
    expect(b['id'], 'bulk-mid');
    expect(b['level'], 'mid');
    expect(b['label'], '증량');
    expect(b['levels'], ['low', 'mid', 'high']);
    expect(b['a'], 0.0);
    expect(b['stoppedAt'], isNull);
    expect(b['note'], isNull);
    expect((b['goal'] as Map).keys, containsAll(['weightKg', 'smmKg', 'bfmKg', 'pbfPct']));
  });

  test('같은 곳에 닿는 강도는 한 장으로 — 폭 0 모드에서 하·중이 합쳐진다', () {
    final d = run(scanOwner, profOwner, 12,
        {'id': 'narrow', 'nameKo': '시험모드', 'aMin': 0.5, 'aMax': 0.5});
    final cuts = dirOf(d, 'cut');
    expect(cuts.first['label'], startsWith('하·중'));
    expect(cuts.first['levels'], containsAll(['low', 'mid']));
    expect(cuts.first['a'], 0.5);
    expect(cuts.length, lessThan(3));
    for (var i = 1; i < cuts.length; i++) {
      expect(goalOf(cuts[i], 'bfmKg'), isNot(closeTo(goalOf(cuts[0], 'bfmKg'), 0.05)),
          reason: '합쳐지지 않은 카드는 정말 다른 곳에 닿는다');
    }
    expect(d['recommended'], 'cut-low', reason: '중이 하에 합쳐졌으면 합친 카드가 추천');
    expect(dirOf(d, 'bulk').single['a'], 0.5, reason: '증량은 모드의 아래 끝');
  });

  test('유지모드(공격성 0~0.08)에서는 감량 셋이 한 점에 모여 한 장 — 경고는 감량 한 줄뿐', () {
    final d = run(scanOwner, profOwner, 12, byId('maintain'));
    expect(dirOf(d, 'cut').length, 1);
    expect(dirOf(d, 'cut').first['label'], '하·중·상');
    expect(dirOf(d, 'cut').first['levels'], ['low', 'mid', 'high']);
    expect(dirOf(d, 'cut').first['a'], closeTo(0.08, 1e-9));
    final warns = warnsOf(d);
    expect(warns.where((w) => w.contains('「유지모드」') && w.contains('하나뿐')).length, 1);
    expect(warns.single, '「유지모드」 안에서는 감량 강도가 하나뿐입니다 (공격성 0.08).');
    /* 증량은 한 장이 설계라 "하나뿐" 이라고 말하지 않습니다. 공격성은 모드의 아래 끝(0). */
    final b = dirOf(d, 'bulk').single;
    expect(b['a'], 0.0);
    expect(b['label'], '증량');
    expect(warns.any((w) => w.contains('증량 강도')), isFalse);
    expect(d['recommended'], 'cut-low');
  });

  test('추천은 체지방률 기준(남 15 · 여 24)을 따른다', () {
    expect(pbfRecommendThreshold('male'), 15);
    expect(pbfRecommendThreshold('female'), 24);
    expect(pbfRecommendThreshold(null), 24);
    expect(d12['recommended'], 'cut-mid', reason: '23.1% > 15');
    final lean = run({...scanOwner, 'bfmKg': 9.0}, profOwner, 12);
    expect(lean['recommended'], 'bulk-mid', reason: '10.4% < 15');
    final woman2 = run({'weightKg': 58.0, 'smmKg': 20.0, 'bfmKg': 16.0}, profWoman, 12);
    expect(woman2['recommended'], 'cut-mid', reason: '27.6% > 24');
  });

  test('추천 — 원하는 방향이 오차 안이라 비면 남은 첫 장, 다 비면 null', () {
    /* 22.4% < 24 라 증량을 권하고 싶지만, 여성 입문자는 12주에 근육 +0.4kg — 오차(0.6) 안이라
       증량 카드가 없습니다. 그러면 남은 카드 중 첫 장을 짚습니다(아무것도 안 짚는 것보다 낫습니다). */
    final woman = run({'weightKg': 58.0, 'smmKg': 22.0, 'bfmKg': 13.0}, profWoman, 12);
    expect(dirOf(woman, 'bulk'), isEmpty);
    expect(warnsOf(woman), contains('12주 안에는 증량 변화가 인바디 오차보다 작습니다'));
    expect(woman['recommended'], optionsOf(woman).first['id']);
    expect(woman['recommended'], 'cut-low');

    /* 감량 '중' 만 빠지고 '상' 이 남는 일은 드물지만, 그때는 같은 방향의 남은 첫 장이어야 합니다.
       4주의 오너: 하 는 오차 안이라 빠지고 중 · 상은 남습니다 → 중. */
    final d4 = run(scanOwner, profOwner, 4);
    expect(d4['recommended'], 'cut-mid');

    /* 이미 하한인 여성(15.2%) — 감량은 하한, 증량은 오차 안. 카드가 하나도 없으면 null. */
    final none = run({'weightKg': 60.0, 'smmKg': 22.0, 'bfmKg': 9.1}, profWoman, 12);
    expect(optionsOf(none), isEmpty);
    expect(none['recommended'], isNull);
    expect(warnsOf(none), [
      '이미 체지방률 하한(15%)이라 더 줄일 수 없습니다',
      '12주 안에는 증량 변화가 인바디 오차보다 작습니다',
    ]);
  });

  test('기간은 4~104주로 접고, 숫자가 아니면 12주 — 8주 미만은 경고', () {
    expect(run(scanOwner, profOwner, 2)['weeks'], 4);
    expect(run(scanOwner, profOwner, -3)['weeks'], 4);
    expect(run(scanOwner, profOwner, 500)['weeks'], 104);
    expect(run(scanOwner, profOwner, 'abc')['weeks'], 12);
    expect(run(scanOwner, profOwner, null)['weeks'], 12);
    expect(run(scanOwner, profOwner, double.nan)['weeks'], 12);
    expect(run(scanOwner, profOwner, double.infinity)['weeks'], 12);
    expect(run(scanOwner, profOwner, 12.4)['weeks'], 12);
    final short = run(scanOwner, profOwner, 6);
    expect((short['warnings'] as List).any((w) => '$w'.contains('8주 미만')), isTrue);
    expect((d12['warnings'] as List).any((w) => '$w'.contains('8주 미만')), isFalse);
    expect(run(scanOwner, profOwner, 104)['weeks'], 104);
  });

  test('이상한 입력에는 던지지 않고 빈 결과', () {
    final garbage = <Map<String, Object?>>[
      {},
      {'weightKg': 'abc'},
      {'weightKg': double.nan, 'smmKg': 30.0, 'bfmKg': 10.0},
      {'weightKg': 70.0, 'smmKg': 0, 'bfmKg': 10.0},
      {'weightKg': 70.0, 'smmKg': 30.0, 'bfmKg': 90.0},
      {'weightKg': 70.0, 'smmKg': null, 'bfmKg': null},
    ];
    for (final scan in garbage) {
      final d = durationOptions(scan, {}, 12, 'not-a-date', null);
      expect(d['options'], isEmpty, reason: '$scan');
      expect(d['recommended'], isNull);
      expect(d['warnings'], isNotEmpty);
      expect(d['weeks'], 12);
    }
    // 날짜가 이상해도, 프로필이 비어도 던지지 않는다.
    final odd = durationOptions({...scanOwner}, {...profOwner}, 12, 'not-a-date', null);
    expect(odd['options'], isNotEmpty);
    expect(odd['startDate'], 'NaN-NaN-NaN');
    expect(optionsOf(durationOptions({...scanOwner}, {}, 12, null, null)), isNotEmpty);
    expect(optionsOf(durationOptions({...scanOwner}, {'sex': 'female', 'age': null}, 'x', '', null)),
        isNotEmpty);
  });

  test('궤적 길이는 min(W, stoppedAt) + 1 — 12주 오너는 아무 데도 안 걸린다', () {
    for (final o in optionsOf(d12)) {
      expect(o['stoppedAt'], isNull, reason: o['id'] as String);
      expect(o['note'], isNull);
      final tr = o['trajectory'] as List;
      expect(tr.length, 13);
      expect((tr.first as Map)['week'], 0);
      expect((tr.last as Map)['week'], 12);
      expect((tr.last as Map)['bfmKg'], goalOf(o, 'bfmKg'));
    }
  });

  /* ---------------------------------------------------------- 체지방률 하한 */

  test('하한 숫자는 목표 화면과 같다 — 남 8 · 여 15, 모르면 여성 쪽', () {
    expect(pbfFloorPct('male'), 8);
    expect(pbfFloorPct('female'), 15);
    expect(pbfFloorPct(null), 15);
  });

  test('52주 감량은 하한(8%) 밑으로 내려가지 않고, 잘린 카드는 닿는 주를 말한다', () {
    /* 오너(23.1%)는 52주면 중 · 상 강도로 8% 를 지나쳐 6% 대까지 갑니다 — 시뮬레이션은 필수지방
       (5%)에서만 멈추므로. 목표 화면은 8% 밑의 목표를 거절하니 그런 카드를 내면 안 됩니다. */
    final d = run(scanOwner, profOwner, 52);
    final cuts = dirOf(d, 'cut');
    expect(cuts, isNotEmpty);
    for (final o in optionsOf(d)) {
      expect(goalOf(o, 'pbfPct'), greaterThanOrEqualTo(8), reason: o['id'] as String);
      expect(pbfOf(o['goal'] as Map), greaterThanOrEqualTo(8), reason: '목표 화면의 식으로도');
      for (final p in (o['trajectory'] as List).cast<Map>()) {
        expect(pbfOf(p), greaterThanOrEqualTo(8), reason: '${o['id']} ${p['week']}주째');
      }
    }
    final clamped = cuts.where((o) => o['stoppedAt'] != null).toList();
    expect(clamped, isNotEmpty, reason: '중 · 상은 52주 안에 8% 에 닿는다');
    for (final o in clamped) {
      final stop = o['stoppedAt'] as int;
      expect(stop, inInclusiveRange(1, 51), reason: o['id'] as String);
      expect(o['note'], '체지방률 하한(8%)에 $stop주째 닿습니다 — 그 뒤는 유지');
      final tr = (o['trajectory'] as List).cast<Map>();
      expect(tr.length, stop + 1);
      expect(tr.last['week'], stop);
      expect(tr.last['bfmKg'], goalOf(o, 'bfmKg'), reason: '카드의 목표는 잘린 그 주의 몸');
      expect(goalOf(o, 'pbfPct'), closeTo(8, 0.6), reason: '하한 바로 위에서 멈춘다 — 미리 자르지 않는다');
      expect(deltaOf(o, 'bfmKg'), lessThan(-10), reason: '잘려도 감량 카드다');
    }
    /* 하 는 52주에 9% — 하한에 안 닿으니 그대로 52주. */
    final low = cuts.firstWhere((o) => o['id'] == 'cut-low');
    expect(low['stoppedAt'], isNull);
    expect(low['note'], isNull);
    expect((low['trajectory'] as List).length, 53);
    expect(goalOf(low, 'pbfPct'), greaterThan(8.5));
  });

  test('여성은 15% 에서 자른다 — 성별을 모르면 여성 쪽 하한', () {
    final d = run(scanWoman, profWoman, 52);
    final cuts = dirOf(d, 'cut');
    expect(cuts.length, 3);
    for (final o in cuts) {
      expect(goalOf(o, 'pbfPct'), greaterThanOrEqualTo(15), reason: o['id'] as String);
      expect(o['stoppedAt'], isNotNull, reason: '27.6% → 15% 는 52주 안이다');
      expect('${o['note']}', startsWith('체지방률 하한(15%)에 '));
      expect('${o['note']}', endsWith('주째 닿습니다 — 그 뒤는 유지'));
    }
    /* 더 센 강도가 더 일찍 닿는다 — 잘린 주는 단조 감소. */
    for (var i = 1; i < cuts.length; i++) {
      expect(cuts[i]['stoppedAt'] as int, lessThanOrEqualTo(cuts[i - 1]['stoppedAt'] as int));
    }
    /* 프로필이 비면 목표 화면과 같이 15% — 남성 오너도 15% 위에서 멈춘다. */
    final unknown = run(scanOwner, {}, 52);
    for (final o in dirOf(unknown, 'cut')) {
      expect(goalOf(o, 'pbfPct'), greaterThanOrEqualTo(15), reason: o['id'] as String);
    }
    expect(dirOf(unknown, 'cut').any((o) => '${o['note']}'.contains('하한(15%)')), isTrue);
  });

  test('이미 하한 밑이면 감량 카드는 없고 — 오차가 아니라 하한이라고 말한다', () {
    /* 체지방 4kg 남성(5.7%). 예전에는 필수지방(5%)까지 몇 주 더 깎는 카드를 냈습니다. 이제는
       0주째에서 잘려 목표가 지금과 같고(유지), 그런 카드는 내지 않습니다. 이유는 오차가 아니라
       하한이므로 경고도 하한 이야기여야 합니다. */
    final lean = run({'weightKg': 70.0, 'smmKg': 37.0, 'bfmKg': 4.0}, profOwner, 12);
    expect(dirOf(lean, 'cut'), isEmpty);
    expect(warnsOf(lean), ['이미 체지방률 하한(8%)이라 더 줄일 수 없습니다']);
    final b = dirOf(lean, 'bulk').single;
    expect(b['stoppedAt'], isNull);
    expect((b['trajectory'] as List).length, 13);
    expect(lean['recommended'], 'bulk-mid');
  });

  /* ------------------------------------------------------ 오차 안의 카드 */

  test('카드의 목표를 분류하면 언제나 그 방향이다 — 유지로 읽히는 카드는 없다', () {
    /* 카드의 세 숫자는 그대로 목표 화면 → compareLevels 로 갑니다. 거기서 classifyGoal 이
       '유지' 라고 읽으면 유지 계획이 나옵니다 — 감량 카드를 골랐는데. 그런 카드는 애초에 안 냅니다. */
    final tables = [
      d12,
      run(scanOwner, profOwner, 4),
      run(scanOwner, profOwner, 6),
      run(scanOwner, profOwner, 52),
      run(scanWoman, profWoman, 4),
      run(scanWoman, profWoman, 12),
      run(scanWoman, profWoman, 52),
      run(scanOwner, profOwner, 12, byId('maintain')),
      run(scanOwner, profOwner, 8, byId('recovery')),
    ];
    for (final d in tables) {
      for (final o in optionsOf(d)) {
        final type = typeOf(d, o);
        expect(type, isNot('maintain'), reason: '${d['weeks']}주 ${o['id']}');
        expect(type, isIn(o['direction'] == 'cut' ? ['cut', 'recomp'] : ['bulk', 'recomp']),
            reason: '${d['weeks']}주 ${o['id']}');
      }
    }
  });

  test('4주: 오차 안의 카드는 빠지고, 방향이 통째로 비면 한 줄로 말한다', () {
    /* 오너 4주 — 감량 하 는 지방 −0.97kg(오차 1.0 안), 증량은 근육 +0.5kg(오차 0.6 안). */
    final d4 = run(scanOwner, profOwner, 4);
    expect(optionsOf(d4).map((o) => o['id']), ['cut-mid', 'cut-high']);
    final warns = warnsOf(d4);
    expect(warns.where((w) => w == '4주 안에는 증량 변화가 인바디 오차보다 작습니다').length, 1,
        reason: '방향마다 한 번');
    expect(warns.any((w) => w.contains('감량 변화가')), isFalse, reason: '감량은 카드가 남았다');
    expect(warns.any((w) => w.contains('8주 미만')), isTrue, reason: '기존 경고는 그대로');
    expect(warns.length, 2);
    expect(d4['recommended'], 'cut-mid');
    /* 모드가 없으면 "하나로 보여 줍니다" 류의 경고는 없다 — 빠진 것과 합친 것은 다르다. */
    expect(warns.any((w) => w.contains('강도가')), isFalse);
  });

  test('여성 12주 증량 — 근육 +0.4kg 은 오차 안이라 빠지고, 남으면 반드시 증량으로 읽힌다', () {
    final d = run(scanWoman, profWoman, 12);
    final bulks = dirOf(d, 'bulk');
    if (bulks.isEmpty) {
      expect(warnsOf(d), contains('12주 안에는 증량 변화가 인바디 오차보다 작습니다'));
    } else {
      for (final o in bulks) {
        expect(typeOf(d, o), isIn(['bulk', 'recomp']), reason: o['id'] as String);
      }
      expect(warnsOf(d).any((w) => w.contains('증량 변화가')), isFalse);
    }
    /* 지금 엔진으로는 빠집니다 — 여성 계수 0.5 로 12주 근육 +0.4kg. */
    expect(bulks, isEmpty);
    expect(dirOf(d, 'cut').length, 3);
    expect(d['recommended'], 'cut-mid', reason: '27.6% > 24');
    /* 52주면 근육 +2kg — 증량 카드가 돌아온다. */
    final long = run(scanWoman, profWoman, 52);
    expect(dirOf(long, 'bulk').length, 1);
    expect(warnsOf(long), isEmpty);
  });

  /* ---------------------------------------------------------- 증량 한 장 */

  test('증량은 한 장 — 그 카드의 목표로 compareLevels 를 돌리면 세 강도가 전부 그 카드의 계획이다', () {
    /* 증량에서 a 는 근성장 속도를 못 건드리므로 compareLevels 는 세 강도를 가장 여유로운 a 로
       접습니다. 카드가 다른 a 를 보여 주면 kcal 과 Δ지방이 실제 계획과 어긋납니다. 그래서 카드는
       그 a 하나이고, 계획의 kcal · 단백질 · 기간이 카드와 같아야 합니다. */
    for (final mode in [null, byId('fatLoss'), byId('muscleGain')]) {
      for (final W in [12, 24]) {
        final d = run(scanOwner, profOwner, W, mode);
        final b = dirOf(d, 'bulk').single;
        final lo = mode == null ? 0.0 : (mode['aMin'] as num).toDouble();
        expect(b['a'], closeTo(lo, 1e-9), reason: '${mode?['id']} $W주');
        final goal = {
          'weightKg': goalOf(b, 'weightKg'), 'smmKg': goalOf(b, 'smmKg'), 'bfmKg': goalOf(b, 'bfmKg'),
        };
        final cmp = compareLevels({...scanOwner}, {...profOwner}, goal, '2026-03-01', W, mode);
        final results = (cmp['results'] as List).cast<Map<String, Object?>>();
        expect(results.length, 3, reason: '${mode?['id']} $W주');
        for (final r in results) {
          final why = '${mode?['id']} $W주 ${r['level']}';
          expect(r['a'] as num, closeTo(lo, 1e-9), reason: why);
          expect(r['weeks'], W, reason: why);
          expect((r['macros'] as Map)['intakeKcal'], b['intakeKcal'], reason: why);
          expect((r['macros'] as Map)['proteinG'], b['proteinG'], reason: why);
        }
      }
    }
  });

  test('증량 카드에는 "강도가 하나뿐" 경고를 달지 않는다 — 한 장이 설계다', () {
    for (final id in ['maintain', 'recovery', 'fatLoss', 'muscleGain', 'cutting', 'miniCut']) {
      final d = run(scanOwner, profOwner, 24, byId(id));
      expect(dirOf(d, 'bulk').length, 1, reason: id);
      expect(warnsOf(d).any((w) => w.contains('증량 강도')), isFalse, reason: id);
      expect(warnsOf(d).any((w) => w.contains('증량 변화가')), isFalse, reason: '$id — 24주 남성 입문자는 오차 밖');
    }
  });
}
