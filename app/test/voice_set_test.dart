/* =============================================================================
 * voice_set_test.dart — 받아쓴 말이 종목 · 무게 · 횟수 · 세트 수로 풀리는가
 *
 * 화면 없이 돕니다. 헬스장에서 실제로 하는 말과 받아쓰기가 자주 내는 모양을 넣어
 * 봅니다 — 한국어 숫자(팔십 · 네 · 열두), 단위(키로 · kg · 개 · 회 · 번), 틀린 글자(밴치 ·
 * 스쿼드), 여러 세트를 한 마디에, 단위 없는 숫자.
 * ========================================================================== */
import 'package:flutter_test/flutter_test.dart';
import 'package:mybody/src/workout/voice_set.dart';

void main() {
  group('숫자 읽기', () {
    test('아라비아 · 소수점', () {
      expect(spokenNumber('80'), 80);
      expect(spokenNumber('82.5'), 82.5);
      expect(spokenNumber('82,5'), 82.5);
      expect(spokenNumber('82점5'), 82.5);
    });
    test('한자어', () {
      expect(spokenNumber('팔십'), 80);
      expect(spokenNumber('백이십'), 120);
      expect(spokenNumber('십오'), 15);
      expect(spokenNumber('이십오'), 25);
      expect(spokenNumber('백'), 100);
      expect(spokenNumber('팔십이점오'), 82.5);
      expect(spokenNumber('오'), 5);
    });
    test('고유어', () {
      expect(spokenNumber('네'), 4);
      expect(spokenNumber('다섯'), 5);
      expect(spokenNumber('열두'), 12);
      expect(spokenNumber('스무'), 20);
      expect(spokenNumber('스물다섯'), 25);
      expect(spokenNumber('여덟'), 8);
      expect(spokenNumber('벤치'), isNull);
    });
  });

  group('한 세트', () {
    test('벤치 80키로 4개', () {
      final r = parseSpokenSets('벤치 80키로 4개');
      expect(r.sets, hasLength(1));
      expect(r.sets.first.exercise?.id, 'bench-press');
      expect(r.sets.first.kg, 80);
      expect(r.sets.first.reps, 4);
      expect(r.sets.first.count, 1);
      expect(r.sets.first.summary, '바벨 벤치프레스 80kg × 4회');
    });
    test('단위 변형 — kg · 회 · 번 · 킬로그램 · 케이지', () {
      for (final s in ['벤치프레스 80kg 4회', '벤치 80 kg 4번', '벤치 80킬로그램 네 개', '벤치 80케이지 4렙', '벤치 80KG 4 reps']) {
        final r = parseSpokenSets(s);
        expect(r.sets, hasLength(1), reason: s);
        expect(r.sets.first.kg, 80, reason: s);
        expect(r.sets.first.reps, 4, reason: s);
        expect(r.sets.first.exercise?.id, 'bench-press', reason: s);
      }
    });
    test('한국어 숫자 — 팔십 키로 네 개 · 백이십 키로 다섯 번', () {
      final a = parseSpokenSets('벤치 팔십 키로 네 개');
      expect(a.sets.single.kg, 80);
      expect(a.sets.single.reps, 4);
      final b = parseSpokenSets('스쿼트 백이십키로 다섯번');
      expect(b.sets.single.kg, 120);
      expect(b.sets.single.reps, 5);
      expect(b.sets.single.exercise?.id, 'barbell-squat');
      final c = parseSpokenSets('레그프레스 백 키로 열두 개');
      expect(c.sets.single.kg, 100);
      expect(c.sets.single.reps, 12);
    });
    test('소수점 무게', () {
      expect(parseSpokenSets('벤치 82.5키로 3개').sets.single.kg, 82.5);
      expect(parseSpokenSets('벤치 팔십이점오 키로 3개').sets.single.kg, 82.5);
      expect(parseSpokenSets('벤치 82점5 3개').sets.single.kg, 82.5);
    });
    test('단위 없는 숫자 — 무게 → 횟수 순, 소수점은 무게', () {
      final a = parseSpokenSets('벤치 80 5');
      expect(a.sets.single.kg, 80);
      expect(a.sets.single.reps, 5);
      final b = parseSpokenSets('벤치 80 다섯개');
      expect(b.sets.single.kg, 80);
      expect(b.sets.single.reps, 5);
      final c = parseSpokenSets('벤치 5개 80');
      expect(c.sets.single.kg, 80);
      expect(c.sets.single.reps, 5);
      final d = parseSpokenSets('벤치 80x5');
      expect(d.sets.single.kg, 80);
      expect(d.sets.single.reps, 5);
    });
    test('맨몸 종목은 단위 없는 숫자가 횟수', () {
      final r = parseSpokenSets('푸시업 20');
      expect(r.sets.single.exercise?.id, 'push-up');
      expect(r.sets.single.kg, isNull);
      expect(r.sets.single.reps, 20);
      final p = parseSpokenSets('풀업 8개');
      expect(p.sets.single.reps, 8);
      expect(p.sets.single.kg, isNull);
    });
    test('군말 · 조사 — 「벤치프레스를 80키로로 4개 했어」', () {
      final r = parseSpokenSets('어 벤치프레스를 80키로로 4개 했어');
      expect(r.sets.single.exercise?.id, 'bench-press');
      expect(r.sets.single.kg, 80);
      expect(r.sets.single.reps, 4);
      final o = parseSpokenSets('오늘 데드리프트 백키로 다섯개 완료');
      expect(o.sets.single.exercise?.id, 'deadlift');
      expect(o.sets.single.kg, 100);
    });
  });

  group('여러 세트', () {
    test('무게 · 횟수 쌍이 둘', () {
      final r = parseSpokenSets('벤치 80키로 5개 85키로 3개');
      expect(r.sets, hasLength(2));
      expect(r.sets[0].kg, 80);
      expect(r.sets[0].reps, 5);
      expect(r.sets[1].kg, 85);
      expect(r.sets[1].reps, 3);
      expect(r.sets.every((s) => s.exercise?.id == 'bench-press'), isTrue);
    });
    test('횟수만 이어지면 무게를 이어받는다', () {
      final r = parseSpokenSets('벤치 80키로 5개 5개 4개');
      expect(r.sets.map((s) => s.kg), [80, 80, 80]);
      expect(r.sets.map((s) => s.reps), [5, 5, 4]);
    });
    test('「5개씩 3세트」', () {
      final r = parseSpokenSets('스쿼트 100키로 5개씩 3세트');
      expect(r.sets.single.count, 3);
      expect(r.sets.single.kg, 100);
      expect(r.sets.single.reps, 5);
      final k = parseSpokenSets('스쿼트 세 세트 100키로 5개');
      expect(k.sets.single.count, 3);
    });
    test('단위 없는 숫자 넷 — 80 5 5 5', () {
      final r = parseSpokenSets('벤치 80 5 5 5');
      expect(r.sets, hasLength(3));
      expect(r.sets.map((s) => s.kg), [80, 80, 80]);
      expect(r.sets.map((s) => s.reps), [5, 5, 5]);
    });
  });

  group('종목 찾기', () {
    test('오늘 목록이 사전보다 먼저 — 「벤치」 → 오늘의 덤벨 벤치프레스', () {
      final r = parseSpokenSets('벤치 30키로 10개', today: ['덤벨 벤치프레스', '레그프레스']);
      expect(r.sets.single.exercise?.id, 'db-bench-press');
    });
    test('짧게 부르는 말', () {
      expect(parseSpokenSets('데드 140 3개').sets.single.exercise?.id, 'deadlift');
      expect(parseSpokenSets('렛풀 50 12개').sets.single.exercise?.id, 'pullup-latpulldown');
      expect(parseSpokenSets('숄더 20 10개').sets.single.exercise?.id, 'db-shoulder-press');
      expect(parseSpokenSets('사레레 8 15개').sets.single.exercise?.id, 'lateral-raise');
    });
    test('받아쓰기 오류 — 밴치 · 스쿼드 · 벤취프레스 · 레그프래스', () {
      expect(parseSpokenSets('밴치 80 4개').sets.single.exercise?.id, 'bench-press');
      expect(parseSpokenSets('스쿼드 100 5개').sets.single.exercise?.id, 'barbell-squat');
      expect(parseSpokenSets('벤취 프레스 80 4개').sets.single.exercise?.id, 'bench-press');
      expect(parseSpokenSets('레그프래스 120 10개').sets.single.exercise?.id, 'leg-press');
      expect(parseSpokenSets('랫 풀 다운 50 10개').sets.single.exercise?.id, 'pullup-latpulldown');
    });
    test('자모 유사도', () {
      expect(spokenSimilarity('밴치', '벤치'), greaterThan(0.7));
      expect(spokenSimilarity('벤치', '스쿼트'), lessThan(0.4));
    });
    test('이름 속 수 글자(사이드 · 오버헤드 · 이지바 · 삼두)를 숫자로 보지 않는다', () {
      final a = parseSpokenSets('사이드 레터럴레이즈 8키로 15개');
      expect(a.sets.single.exercise?.id, 'lateral-raise');
      expect(a.sets.single.kg, 8);
      expect(a.sets.single.reps, 15);
      final b = parseSpokenSets('오버헤드 프레스 40키로 8개');
      expect(b.sets.single.exercise?.id, 'overhead-press');
      expect(b.sets.single.kg, 40);
      final c = parseSpokenSets('이지바 컬 20키로 10개');
      expect(c.sets.single.exercise?.id, 'ez-bar-curl');
      expect(c.sets.single.kg, 20);
      expect(c.sets.single.reps, 10);
    });
    test('모르는 종목은 null 로 두되 들은 말은 남긴다', () {
      final r = parseSpokenSets('뿡뿡이 80키로 4개');
      expect(r.sets.single.exercise, isNull);
      expect(r.sets.single.spokenName, '뿡뿡이');
      expect(r.sets.single.kg, 80);
      expect(r.empty, isFalse);
    });
    test('숫자도 종목도 없으면 empty', () {
      expect(parseSpokenSets('음 그러니까').empty, isTrue);
      expect(parseSpokenSets('').empty, isTrue);
    });
    test('종목만 말하면 숫자 없는 한 줄', () {
      final r = parseSpokenSets('벤치프레스');
      expect(r.sets.single.exercise?.id, 'bench-press');
      expect(r.sets.single.hasNumbers, isFalse);
      expect(r.empty, isFalse);
    });
    test('말이 안 되는 값은 비운다', () {
      final r = parseSpokenSets('벤치 8000키로 4개');
      expect(r.sets.single.kg, isNull);
      expect(r.sets.single.reps, 4);
    });
  });
}
