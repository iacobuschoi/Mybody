/* =============================================================================
 * exercise_library_test.dart — 종목 사전 확장(2차 피드백 12)
 *
 * 두 가지를 지킵니다. (1) 원래 있던 항목은 id · 이름 · 순서가 그대로 — 엔진
 * 이름 1:1, tailorSession 의 대체 우선순위, 저장된 익숙한 종목 id 가 걸려
 * 있습니다. (2) 새로 붙인 항목은 부위 블록의 뒤에만, 별칭·검색으로 찾힙니다.
 * ========================================================================== */
import 'package:flutter_test/flutter_test.dart';
import 'package:mybody/src/workout/exercises.dart';

/// 확장 전 사전(74개) — (id, 이름, 부위). 이 표는 바뀌면 안 됩니다.
const List<(String, String, String)> _legacy = [
  ('bench-press', '바벨 벤치프레스', 'chest'),
  ('incline-db-press', '인클라인 덤벨프레스', 'chest'),
  ('dips', '딥스', 'chest'),
  ('chest-press-machine', '체스트 프레스 머신', 'chest'),
  ('push-up', '푸시업', 'chest'),
  ('incline-push-up', '인클라인 푸시업', 'chest'),
  ('decline-push-up', '디클라인 푸시업', 'chest'),
  ('db-floor-press', '덤벨 플로어프레스', 'chest'),
  ('band-chest-press', '밴드 체스트프레스', 'chest'),
  ('cable-fly', '케이블 플라이', 'chest'),
  ('db-fly', '덤벨 플라이', 'chest'),
  ('pullup-latpulldown', '풀업 / 랫풀다운', 'back'),
  ('barbell-row', '바벨 로우', 'back'),
  ('seated-cable-row', '시티드 케이블로우', 'back'),
  ('one-arm-db-row', '원암 덤벨로우', 'back'),
  ('pull-up', '풀업', 'back'),
  ('band-pulldown', '밴드 풀다운', 'back'),
  ('inverted-row', '인버티드 로우', 'back'),
  ('band-row', '밴드 로우', 'back'),
  ('superman', '슈퍼맨', 'back'),
  ('prone-y-raise', '프론 Y레이즈', 'back'),
  ('reverse-snow-angel', '리버스 스노우엔젤', 'back'),
  ('overhead-press', '오버헤드 프레스', 'shoulder'),
  ('lateral-raise', '사이드 레터럴레이즈', 'shoulder'),
  ('face-pull', '페이스풀', 'shoulder'),
  ('db-shoulder-press', '덤벨 숄더프레스', 'shoulder'),
  ('pike-push-up', '파이크 푸시업', 'shoulder'),
  ('band-face-pull', '밴드 페이스풀', 'shoulder'),
  ('rear-delt-raise', '덤벨 리어델트 레이즈', 'shoulder'),
  ('band-lateral-raise', '밴드 레터럴레이즈', 'shoulder'),
  ('barbell-curl', '바벨 컬', 'arms'),
  ('incline-db-curl', '인클라인 덤벨컬', 'arms'),
  ('cable-pushdown', '케이블 푸시다운', 'arms'),
  ('overhead-extension', '오버헤드 익스텐션', 'arms'),
  ('db-curl', '덤벨 컬', 'arms'),
  ('band-curl', '밴드 컬', 'arms'),
  ('db-kickback', '덤벨 킥백', 'arms'),
  ('diamond-push-up', '다이아몬드 푸시업', 'arms'),
  ('bench-dips', '벤치 딥스', 'arms'),
  ('barbell-squat', '바벨 스쿼트', 'quads'),
  ('leg-press', '레그프레스', 'quads'),
  ('bulgarian-split-squat', '불가리안 스플릿스쿼트', 'quads'),
  ('leg-extension', '레그 익스텐션', 'quads'),
  ('goblet-squat', '고블릿 스쿼트', 'quads'),
  ('bodyweight-squat', '맨몸 스쿼트', 'quads'),
  ('jump-squat', '점프 스쿼트', 'quads'),
  ('lunge', '런지', 'quads'),
  ('split-squat', '스플릿 스쿼트', 'quads'),
  ('step-up', '스텝업', 'quads'),
  ('wall-sit', '월 싯', 'quads'),
  ('rdl', '루마니안 데드리프트', 'hamsGlutes'),
  ('hip-thrust', '힙 쓰러스트', 'hamsGlutes'),
  ('leg-curl', '레그 컬', 'hamsGlutes'),
  ('db-rdl', '덤벨 루마니안 데드리프트', 'hamsGlutes'),
  ('kettlebell-swing', '케틀벨 스윙', 'hamsGlutes'),
  ('glute-bridge', '글루트 브릿지', 'hamsGlutes'),
  ('single-leg-glute-bridge', '싱글레그 글루트브릿지', 'hamsGlutes'),
  ('calf-raise', '카프 레이즈', 'hamsGlutes'),
  ('hanging-leg-raise', '행잉 레그레이즈', 'core'),
  ('cable-crunch', '케이블 크런치', 'core'),
  ('plank', '플랭크', 'core'),
  ('lying-leg-raise', '라잉 레그레이즈', 'core'),
  ('dead-bug', '데드버그', 'core'),
  ('bird-dog', '버드독', 'core'),
  ('side-plank', '사이드 플랭크', 'core'),
  ('hollow-hold', '할로우 홀드', 'core'),
  ('crunch', '크런치', 'core'),
  ('plank-shoulder-tap', '플랭크 숄더탭', 'core'),
  ('mountain-climber', '마운틴 클라이머', 'core'),
  ('burpee', '버피', 'full'),
  ('jumping-jack', '점핑잭', 'full'),
  ('high-knees', '하이니', 'full'),
  ('jump-rope', '줄넘기', 'full'),
  ('bear-crawl', '베어 크롤', 'full'),
];

const _bodyGroups = ['chest', 'back', 'shoulder', 'arms', 'quads', 'hamsGlutes', 'core'];

String _loose(String s) => s.replaceAll(RegExp(r'\s+'), '').toLowerCase();

void main() {
  group('종목 사전 확장', () {
    test('원래 항목은 id · 이름 · 부위 · 상대 순서가 그대로', () {
      final ids = [for (final e in kExerciseLibrary) e.id];
      var last = -1;
      for (final (id, name, g) in _legacy) {
        final i = ids.indexOf(id);
        expect(i, greaterThan(last), reason: '$id 의 순서');
        last = i;
        expect(kExerciseLibrary[i].name, name, reason: id);
        expect(kExerciseLibrary[i].group, g, reason: id);
      }
    });

    test('새 항목은 부위 블록의 뒤 — 대체 우선순위는 앞 항목이 이긴다', () {
      final legacyIds = {for (final (id, _, _) in _legacy) id};
      for (final g in kGroupLabel.keys) {
        final xs = exercisesFor(g);
        final lastLegacy = xs.lastIndexWhere((e) => legacyIds.contains(e.id));
        final firstNew = xs.indexWhere((e) => !legacyIds.contains(e.id));
        if (firstNew < 0) continue;
        expect(firstNew, greaterThan(lastLegacy), reason: g);
      }
    });

    test('150개 이상 · id 와 이름이 유일 · 값이 아는 범위', () {
      expect(kExerciseLibrary.length, greaterThanOrEqualTo(150));
      expect(kExerciseLibrary.map((e) => e.id).toSet().length, kExerciseLibrary.length);
      expect(kExerciseLibrary.map((e) => _loose(e.name)).toSet().length, kExerciseLibrary.length,
          reason: '띄어쓰기만 다른 이름도 안 됩니다');
      for (final e in kExerciseLibrary) {
        expect(kEquipLabel.containsKey(e.equip), isTrue, reason: e.name);
        expect(kGroupLabel.containsKey(e.group), isTrue, reason: e.name);
        expect(e.pattern, isNotEmpty, reason: e.name);
        expect(e.met, inInclusiveRange(2.8, 11.0), reason: e.name);
        expect(e.muscles, isNotEmpty, reason: e.name);
        expect(RegExp(r'^[a-z0-9-]+$').hasMatch(e.id), isTrue, reason: e.id);
      }
    });

    test('별칭은 다른 종목의 이름과 겹치지 않고, 자기 이름을 되풀이하지 않는다', () {
      final names = {for (final e in kExerciseLibrary) _loose(e.name): e.id};
      for (final e in kExerciseLibrary) {
        for (final a in e.aliases) {
          expect(a.trim(), isNotEmpty, reason: e.id);
          expect(_loose(a), isNot(_loose(e.name)), reason: '${e.id}: $a');
          final other = names[_loose(a)];
          expect(other, isNull, reason: '${e.id} 의 별칭 "$a" 가 $other 의 이름');
        }
        expect(e.aliases.map(_loose).toSet().length, e.aliases.length, reason: '${e.id} 별칭 중복');
      }
    });

    test('별칭은 종목 사이에서도 겹치지 않는다 — exerciseByAlias 가 순서에 좌우되면 안 된다', () {
      final owner = <String, String>{};
      for (final e in kExerciseLibrary) {
        for (final a in e.aliases) {
          final k = _loose(a);
          expect(owner[k], isNull, reason: '"$a" 가 ${owner[k]} 와 ${e.id} 둘 다에');
          owner[k] = e.id;
        }
      }
      /* 애매했던 말은 한쪽에만 — 뜻이 더 흔한 쪽. '스미스' 만으로는 아무것도 아닙니다(검색은 됩니다). */
      expect(exerciseByAlias('풀업 머신')?.id, 'assisted-pullup');
      expect(exerciseByAlias('덤벨 런지')?.id, 'lunge');
      expect(exerciseByAlias('케이블 킥백')?.id, 'cable-glute-kickback');
      expect(exerciseByAlias('스미스'), isNull);
      expect(searchExercises('스미스').length, greaterThanOrEqualTo(9));
    });

    test('무게를 걸 곳이 없는 고정 스테이션은 맨몸 + needsBar — 무게 추천도 머신 수도 안 붙는다', () {
      for (final id in ['captains-chair-knee-raise', 'decline-sit-up', 'back-extension-45', 'glute-ham-raise']) {
        final e = exerciseById(id)!;
        expect(e.equip, 'bodyweight', reason: id);
        expect(e.needsBar, isTrue, reason: '$id 는 집에 없습니다');
        expect(e.isMachine, isFalse);
      }
      /* 플레이트를 거는 것은 그대로 머신입니다. */
      expect(exerciseById('reverse-hyper')!.equip, 'machine');
      expect(exerciseById('sled-push')!.equip, 'machine');
    });

    test('허벅지 뒤·엉덩이 머신은 힙 쓰러스트 머신 · 풀스루가 킥백류보다 앞 — 대체 우선순위', () {
      final ids = [for (final e in exercisesFor('hamsGlutes')) e.id];
      expect(ids.indexOf('hip-thrust-machine'), lessThan(ids.indexOf('glute-kickback-machine')));
      expect(ids.indexOf('cable-pull-through'), lessThan(ids.indexOf('glute-kickback-machine')));
      expect(ids.indexOf('leg-curl'), lessThan(ids.indexOf('hip-thrust-machine')), reason: '원래 항목이 먼저');
    });

    test('부위마다 머신·케이블 4개 이상, 머신 종목 40개 이상', () {
      for (final g in _bodyGroups) {
        expect(exercisesFor(g).where((e) => e.isMachine).length, greaterThanOrEqualTo(4), reason: g);
      }
      expect(kExerciseLibrary.where((e) => e.equip == 'machine').length, greaterThanOrEqualTo(40));
      /* 집에서 되는 맨몸 대체는 여전히 부위마다 있어야 합니다. */
      for (final g in _bodyGroups) {
        expect(exercisesFor(g, equip: {'bodyweight'}).where((e) => !e.needsBar), isNotEmpty, reason: g);
      }
    });

    test('스미스 머신은 machine 으로 두고 「스미스 머신 …」 별칭으로 찾는다', () {
      final smith = kExerciseLibrary.where((e) => e.id.startsWith('smith-')).toList();
      expect(smith.length, greaterThanOrEqualTo(9));
      for (final e in smith) {
        expect(e.equip, 'machine', reason: e.id);
        expect(e.isMachine, isTrue);
        expect(e.aliases.any((a) => a.startsWith('스미스 머신')), isTrue, reason: e.id);
      }
      expect(exerciseByAlias('스미스 머신 스쿼트')?.id, 'smith-squat');
      expect(exerciseByAlias('Smith Squat')?.id, 'smith-squat');
    });

    test('exerciseByAlias — 이름 · 별칭 · 영문, 공백과 대소문자 무시', () {
      expect(exerciseByAlias('아웃싸이')?.id, 'hip-abduction-machine');
      expect(exerciseByAlias('이너싸이')?.id, 'hip-adduction-machine');
      expect(exerciseByAlias('펙덱')?.id, 'pec-deck');
      expect(exerciseByAlias('pecdeckfly')?.id, 'pec-deck');
      expect(exerciseByAlias('LAT PULLDOWN')?.id, 'pullup-latpulldown');
      expect(exerciseByAlias('바벨 벤치프레스')?.id, 'bench-press', reason: '이름도 됩니다');
      expect(exerciseByAlias('랫풀다운')?.id, 'pullup-latpulldown');
      expect(exerciseByAlias('하이퍼익스텐션')?.id, 'back-extension-45');
      expect(exerciseByAlias('펙'), isNull, reason: '부분 일치는 안 합니다');
      expect(exerciseByAlias(''), isNull);
      expect(exerciseByAlias('없는 종목'), isNull);
    });

    test('exerciseByName 은 엔진 이름을 여전히 글자 그대로 찾는다', () {
      for (final (id, name, _) in _legacy) {
        expect(exerciseByName(name)?.id, id, reason: name);
      }
      expect(exerciseByName('풀업')?.id, 'pull-up');
      expect(exerciseByName('랫풀다운')?.id, 'pullup-latpulldown');
    });

    test('searchExercises — 부분 일치, 이름 맞은 것이 별칭만 맞은 것보다 앞', () {
      final smith = searchExercises('스미스');
      expect(smith.length, greaterThanOrEqualTo(9));
      for (final e in smith) {
        expect(_loose(e.name).contains('스미스') || e.aliases.any((a) => _loose(a).contains('스미스')), isTrue,
            reason: e.id);
      }
      expect(searchExercises('벤치프레스').first.id, 'bench-press');
      expect(searchExercises('벤치프레스').map((e) => e.id), contains('smith-bench-press'));
      final pec = searchExercises('Pec Deck');
      expect(pec.map((e) => e.id), contains('pec-deck'));
      expect(searchExercises('ROW').map((e) => e.id), containsAll(['barbell-row', 'seated-row-machine']));
      expect(searchExercises('  '), isEmpty);
      expect(searchExercises('zzz없는것'), isEmpty);
      /* 별칭으로만 맞은 것은 이름으로 맞은 것 뒤에. */
      final hits = searchExercises('풀다운');
      final firstAlias = hits.indexWhere((e) => !_loose(e.name).contains('풀다운'));
      final lastName = hits.lastIndexWhere((e) => _loose(e.name).contains('풀다운'));
      expect(firstAlias == -1 || firstAlias > lastName, isTrue);
    });

    test('searchExercises 는 equip 으로 거른다', () {
      final cable = searchExercises('로우', equip: {'cable'});
      expect(cable, isNotEmpty);
      expect(cable.every((e) => e.equip == 'cable'), isTrue);
      expect(searchExercises('로우').length, greaterThan(cable.length));
    });
  });
}
