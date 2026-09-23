/* 음식 검색이 한 개도 못 찾았을 때 대신 보여 주는 "비슷한 이름" 이 지켜야
 * 하는 성질들.
 *
 * 사용자는 오타를 고쳐 다시 치지 않습니다. '김치찌게' 를 치고 아무것도
 * 안 나오면 검색이 없는 줄 압니다. 그래서 여기 있는 사례들은 "첫 줄에
 * 무엇이 보이는가" 를 검사합니다 — 첫 줄이 틀리면 있는 기능도 없는 것과
 * 같습니다. */
import 'package:mybody_core/fooddb.dart';
import 'package:test/test.dart';

String first(String q) => '${similar(q).first['name']}';
String why(String q) => '${similar(q).first['why']}';

void main() {
  test('오타 — 모음·받침 하나가 틀린 것은 자모 하나 차이로 잡는다', () {
    expect(first('김치찌게'), '김치찌개');
    expect(why('김치찌게'), 'typo');
    expect(first('제육복음'), '제육볶음');
    expect(first('된장찌게'), '된장찌개');
    expect(first('순두부찌게'), '순두부찌개');
    expect(first('닭가습살'), '닭가슴살(생)');
    expect(first('삼결살'), '삼겹살 구이', reason: '같은 점수면 짧은 이름이 먼저');
    expect(first('비빔빱'), '비빔밥');
    expect(first('김빱'), '김밥');
    expect(first('자장면'), '짜장면');
    expect(first('아메리키노'), '아메리카노');
    expect(first('까페라떼'), '카페라떼(그란데)');
    expect(first('샌드위지'), '샌드위치(편의점)');
    expect(first('햄버가'), '햄버거(불고기)');
    expect(first('삼게탕'), '삼계탕');
    expect(first('갈비땅'), '갈비탕');
    expect(first('김치복음밥'), '김치볶음밥');
    expect(first('바나너'), '바나나');
    expect(first('계란후라의'), '계란후라이');
    expect(first('족빨'), '족발 1인분');
    expect(first('보삼'), '보쌈');
    expect(first('돈까쓰'), startsWith('돈까스'));
    expect(first('떡뽁이'), contains('떡볶이'));
  });

  test('부분 — 자모열이 통째로 들어 있으면 오타보다 위', () {
    expect(first('닭가ㅅ'), '닭가슴살(생)');
    expect(why('닭가ㅅ'), 'partial');
    expect(first('초밥연어'), '초밥(연어) 10개');
    expect(why('초밥연어'), 'partial');
    expect(first('프로틴 바'), startsWith('프로틴바('), reason: '공백은 이름 장식이라 뺍니다');
    expect(why('프로틴 바'), 'partial');
    expect(first('짬뽀'), '짬뽕');
    expect(first('오무라이스'), '오므라이스');
  });

  test('별명으로도 찾는다', () {
    expect(first('햇반'), '즉석밥(햇반 210g)');
    expect(why('햇반'), 'partial');
  });

  test('초성', () {
    expect(first('ㄷㄱㅅㅅ'), '닭가슴살(생)');
    expect(why('ㄷㄱㅅㅅ'), 'chosung');
    expect(first('ㅂㅂㅂ'), '비빔밥');
  });

  test('한/영 키를 안 누른 채 친 것', () {
    expect(first('ekfrrktmatkf'), '닭가슴살(생)');
    expect(why('ekfrrktmatkf'), 'qwerty');
    /* 원본 명세의 예시는 r 이 하나 빠져 있습니다(닭 = ekfr, 가 = rk).
       그래도 자판 변환 뒤 오타 하나로 잡혀서 같은 첫 줄이 나와야 합니다. */
    expect(first('ekfrktmatkf'), '닭가슴살(생)');
    expect(why('ekfrktmatkf'), 'qwerty');
    expect(first('rlaclWlro'), '김치찌개', reason: '대문자 W 는 ㅉ');
    expect(first('qlqlaqkq'), '비빔밥');
    expect(similar('dkapfl zkshsh'), isEmpty, reason: '영문 사이에 공백이 있으면 자판 변환은 안 합니다');
  });

  test('없는 것은 없다고 한다', () {
    expect(similar('zzz'), isEmpty);
    expect(similar(''), isEmpty);
    expect(similar('  '), isEmpty);
    expect(similar(null), isEmpty);
    expect(similar('a'), isEmpty, reason: '자모 하나로는 아무것도 고르지 않습니다');
  });

  test('한 글자도 자모 셋이면 부분 일치로 잡힌다 — 정상', () {
    final r = similar('밥');
    expect(r, isNotEmpty);
    for (final m in r) {
      expect('${m['name']}', contains('밥'));
      expect(m['why'], 'partial');
    }
  });

  test('결과 모양과 개수', () {
    final r = similar('밥');
    expect(r.length, 8, reason: '기본 8개');
    expect(r.first.keys.toList(), ['name', 'score', 'why']);
    expect(r.first['score'], isA<int>(), reason: '점수는 정수만 — 두 언어가 같은 순서를 내야 합니다');
    expect(similar('밥', 3).length, 3);
    expect(similar('밥', '2').length, 2);
    expect(similar('밥', 0).length, 8, reason: '0 은 없는 것과 같습니다 (limit || 8)');
  });

  test('점수 내림차순, 같은 점수는 짧은 이름이 먼저', () {
    final r = similar('닭가습살');
    for (var i = 1; i < r.length; i++) {
      final a = r[i - 1], b = r[i];
      final sa = a['score'] as int, sb = b['score'] as int;
      expect(sa >= sb, isTrue);
    }
    expect(r.first['name'], '닭가슴살(생)');
  });

  test('정확히 겹치는 것은 search 가 먼저 잡는다 — similar 는 그 뒤에 부르는 것', () {
    /* 이 검사는 역할 분담을 못 박습니다. search 가 이미 찾는 입력을
       similar 에 넣어도 같은 이름이 나오지만, 화면은 search 가 비었을 때만
       similar 를 부릅니다. */
    expect(search('김치찌개'), isNotEmpty);
    expect(first('김치찌개'), '김치찌개');
  });
}
