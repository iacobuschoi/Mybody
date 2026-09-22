/* 친구 소식이 지켜야 하는 성질들.
 *
 * 이건 남의 행동에 대해 내 화면이 하는 말입니다. 틀리면 "나린님이
 * 운동했습니다" 가 근거 없이 남습니다. */
import 'package:mybody_core/news.dart';
import 'package:test/test.dart';

class MemNews implements NewsStorage {
  String? _v;
  @override String? read() => _v;
  @override void write(String raw) => _v = raw;
  @override void clear() => _v = null;
}

List<Object?> snap(String id, {String week = '2026-09-21', int? kept, int? planned = 4}) =>
    [{'id': id, 'rows': [{'weekStart': week, 'keptDays': kept, 'plannedDays': planned}]}];

final friends = [{'id': 'f1', 'displayName': '나린'}];

void main() {
  test('처음 보는 친구는 조용하다', () {
    final n = News(MemNews());
    /* 친구를 맺은 첫 pull 에서 "3일 운동했습니다" 가 쏟아지면 안 됩니다 —
       지난 일인데 방금 일어난 것처럼 보입니다. */
    expect(n.apply(snap('f1', kept: 3), friends), 0);
    expect(n.list(), isEmpty);
  });

  test('늘어나면 소식이 된다', () {
    final n = News(MemNews());
    n.apply(snap('f1', kept: 2), friends);
    expect(n.apply(snap('f1', kept: 3), friends), 1);
    expect((n.list().first as Map)['keptDays'], 3);
  });

  test('줄어들어도 새 소식은 안 만든다 — 나쁜 소식은 안 흐릅니다', () {
    final n = News(MemNews());
    n.apply(snap('f1', kept: 3), friends);
    expect(n.apply(snap('f1', kept: 1), friends), 0);
  });

  test('줄어들면 근거가 사라진 줄을 거둬들인다', () {
    final n = News(MemNews());
    n.apply(snap('f1', kept: 1), friends);
    n.apply(snap('f1', kept: 3), friends);       // "3일째" 가 남습니다
    expect(n.list().length, 1);
    n.apply(snap('f1', kept: 2), friends);       // 되돌렸습니다
    /* "3일째" 는 이제 거짓입니다. 남의 행동에 대해 사실이 아닌 문장을
       들고 있는 쪽이 조용히 지우는 것보다 나쁩니다. */
    expect(n.list(), isEmpty);
  });

  test('주가 바뀌어 0 이 된 것은 아무 일도 아니다', () {
    final n = News(MemNews());
    n.apply(snap('f1', week: '2026-09-14', kept: 4), friends);
    expect(n.apply(snap('f1', week: '2026-09-21', kept: 0), friends), 0);
    expect(n.list(), isEmpty);
  });

  test('친구를 끊으면 그 사람 소식이 사라진다', () {
    final n = News(MemNews());
    n.apply(snap('f1', kept: 1), friends);
    n.apply(snap('f1', kept: 3), friends);
    expect(n.list().length, 1);
    n.apply(snap('f1', kept: 3), const []);      // 친구 목록에서 빠짐
    expect(n.list(), isEmpty);
  });

  test('공유를 끄면 사라지지만, 못 받아온 것으로는 안 사라진다', () {
    final n = News(MemNews());
    n.apply(snap('f1', kept: 1), friends);
    n.apply(snap('f1', kept: 3), friends);
    expect(n.list().length, 1);

    /* 행이 아예 없는 것은 **못 받아온 것**입니다. 한 번 깜빡인 네트워크가
       소식 기능을 꺼 버리면 안 됩니다. */
    n.apply([{'id': 'f1', 'rows': const []}], friends);
    expect(n.list().length, 1, reason: '못 받아온 것으로 지우면 안 됩니다');

    /* 행은 왔는데 일정 숫자가 없는 것 = 서버가 공유 설정으로 걸러 낸 것. */
    n.apply(snap('f1', kept: null), friends);
    expect(n.list(), isEmpty);
  });

  test('안 읽은 개수는 번호로 센다 (시계와 무관)', () {
    final n = News(MemNews());
    n.apply(snap('f1', kept: 1), friends);
    n.apply(snap('f1', kept: 2), friends);
    n.apply(snap('f1', kept: 3), friends);
    expect(n.unread(), 2);
    n.markRead();
    expect(n.unread(), 0);
    n.apply(snap('f1', kept: 4), friends);
    expect(n.unread(), 1);
  });

  test('오래된 소식은 버린다', () {
    final n = News(MemNews());
    n.apply(snap('f1', kept: 1), friends, '2026-08-01T00:00:00.000Z');
    n.apply(snap('f1', kept: 2), friends, '2026-08-01T00:00:00.000Z');
    expect(n.list().length, 1);
    // 21일이 넘게 지난 뒤
    n.apply(snap('f1', kept: 2), friends, '2026-09-21T00:00:00.000Z');
    expect(n.list(), isEmpty, reason: '석 달 전 소식은 소식이 아니라 화석입니다');
  });

  test('계정을 바꾸면 남의 소식이 안 남는다', () {
    final st = MemNews();
    final n = News(st);
    n.apply(snap('f1', kept: 1), friends);
    n.apply(snap('f1', kept: 2), friends);
    n.reset();
    expect(News(st).list(), isEmpty);
  });
}
