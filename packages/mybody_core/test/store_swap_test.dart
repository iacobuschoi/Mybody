/* Store.swap — 계정이 바뀔 때 기록 칸을 갈아 끼우기(앱의 local_owner.dart).
 *
 * reset 과 importJSON 을 못 쓰는 까닭이 곧 이 시험입니다: reset 은 사진을 지우고(치워 둔 칸의
 * 측정이 그 사진을 가리킵니다), importJSON 은 친구에게 올리고(publishWeekly) 이 기기가 바꾼 것으로
 * 찍힙니다. swap 은 듣는 쪽에 알리기만 하고, 알리는 동안 swapping 이 참입니다. */
import 'dart:convert';

import 'package:mybody_core/mybody_core.dart';
import 'package:test/test.dart';

class _Photos implements PhotoHost {
  final ids = <String>{'p1'};
  @override
  Map<String, Object?> list() => {for (final i in ids) i: true};
  @override
  void remove(String id) => ids.remove(id);
  @override
  void clearAll() => ids.clear();
}

void main() {
  test('사진은 그대로, 친구에게 안 올리고, 알리는 동안 swapping · 기기에 적힌다', () {
    final storage = MemoryStorage();
    final s = Store(storage: storage);
    final photos = _Photos();
    s.photos = photos;
    var published = 0;
    s.currentUser = () => 'tok';
    s.publishSnapshot = (_, __) {
      published++;
      return {'ok': true};
    };
    final seen = <bool>[];
    s.onChange((_) => seen.add(s.swapping));

    s.set({'onboarded': true, 'scans': [{'id': 'a', 'weightKg': 80, 'photoId': 'p1'}]});
    expect(published, 1, reason: '보통 저장은 올립니다(시험의 전제)');

    expect(s.swap({'scans': [{'id': 'b', 'weightKg': 60}]}), isTrue);
    expect(published, 1, reason: '칸 바꾸기는 올리지 않습니다');
    expect(photos.ids, {'p1'}, reason: '치워 둔 칸의 측정이 가리키는 사진');
    expect(seen, [false, true]);
    expect(s.swapping, isFalse);
    expect((s.get()['scans'] as List).single['id'], 'b');
    expect(s.get()['onboarded'], isFalse, reason: '빈 칸 위에 얹습니다');
    expect(jsonDecode(storage.read()!)['scans'][0]['id'], 'b');

    s.swap({});
    expect(s.get()['scans'], isEmpty);
    expect(photos.ids, {'p1'});
  });

  test('다른 칸이 가리키는 사진 — 측정을 지워도 · 자리가 없어 사진을 버릴 때도 남긴다', () {
    final s = Store(storage: MemoryStorage());
    final photos = _Photos()..ids.addAll(['p2', 'p3']);
    s.photos = photos;
    s.photoKeptElsewhere = (id) => id == 'p1';
    s.set({'scans': [
      {'id': 'a', 'weightKg': 80, 'photoId': 'p1'},
      {'id': 'b', 'weightKg': 79, 'photoId': 'p2'},
      {'id': 'c', 'weightKg': 78, 'photoId': 'p2'},
    ]});
    expect(s.photoInUse('p1'), isTrue, reason: '치워 둔 칸');
    expect(s.photoInUse('p2', exceptScanId: 'b'), isTrue, reason: '이 칸의 다른 측정');
    expect(s.photoInUse('p3'), isFalse);
    s.removeScan('a');
    expect(photos.ids, contains('p1'));
    s.removeScan('b');
    expect(photos.ids, contains('p2'), reason: 'c 가 아직 가리킵니다');
    s.removeScan('c');
    expect(photos.ids, isNot(contains('p2')), reason: '아무도 안 가리키면 전처럼 지웁니다');
    /* 훅을 몰라서 던져도 지우지 않습니다. */
    s.photoKeptElsewhere = (_) => throw StateError('x');
    expect(s.photoInUse('p3'), isTrue);

    final flaky = _Flaky();
    final t = Store(storage: flaky);
    final many = _Many(['old-kept', 'new-free']);
    t.photos = many;
    t.photoKeptElsewhere = (id) => id == 'old-kept';
    flaky.failures = 1;   // 첫 쓰기는 자리가 없음 → 사진을 하나 버리고 다시
    t.set({'onboarded': true});
    expect(t.saved(), isTrue);
    expect(many.ids, ['old-kept'], reason: '더 오래됐어도 다른 칸의 사진은 안 버립니다');
  });

  test('기기에 못 쓰면 false — 칸은 그래도 바뀐다(이번 실행 동안)', () {
    final s = Store(storage: MemoryStorage(readOnly: true));
    expect(s.swap({'onboarded': true}), isFalse);
    expect(s.get()['onboarded'], isTrue);
    expect(s.saved(), isFalse);
  });
}

/* 사진 파일은 계정마다의 기록 칸이 한 폴더를 같이 씁니다(앱의 local_owner.dart). 치워 둔 칸이
   가리키는 사진([Store.photoKeptElsewhere])은 이 칸에서 측정을 지우거나 자리가 없어 사진을 버릴 때도
   남깁니다 — 사진은 서버에 안 가서 지우면 되찾을 수 없습니다. */
class _Flaky implements StateStorage {
  int failures = 0;
  String? v;
  @override
  String? read() => v;
  @override
  bool write(String value) {
    if (failures > 0) {
      failures--;
      return false;
    }
    v = value;
    return true;
  }
}

class _Many implements PhotoHost {
  _Many(this.ids);
  final List<String> ids;
  @override
  Map<String, Object?> list() => {for (final (i, id) in ids.indexed) id: {'at': '2026-09-0${i + 1}'}};
  @override
  void remove(String id) => ids.remove(id);
  @override
  void clearAll() => ids.clear();
}
