/* =============================================================================
 * news.js — 친구 소식 (기기 안에서만 계산합니다)
 *
 * 사용자 요청: "운동 해서 체크하면 친구한테 알림가게".
 *
 * 서버를 한 줄도 안 고치고 만듭니다. sync.pull() 이 이미 친구마다 주간
 * 스냅샷을 받아 옵니다. 그 안의 "지킴 일수"가 지난번 본 값보다 **늘었을
 * 때만** 소식 한 줄을 남깁니다. 새로 나가는 정보가 하나도 없습니다 —
 * 이미 공유 설정으로 걸러져 온 숫자를, 내 기기가 비교할 뿐입니다.
 *
 * 이 구조가 중요한 이유: **나쁜 소식이 흐를 수 없습니다.**
 * 늘어난 것만 소식이 되므로 "안 했다" 는 구조적으로 알림이 될 수 없습니다.
 * 줄어든 것도, 0 인 것도, 주가 바뀌어 초기화된 것도 조용합니다.
 * 찌르기 기능을 안 만드는 것과 같은 이유입니다 — 부재는 조용해야 합니다.
 *
 * 정직하게 말해 둘 것: 이건 폰 알림이 아닙니다. 서비스워커 푸시는
 * 보안 컨텍스트(HTTPS)를 요구하는데, 같은 와이파이에서 http://192.168.x.x
 * 로 쓰면 navigator.serviceWorker 자체가 없습니다(실측 확인). 그래서
 * 내 앱이 서버에서 받아올 때 화면 안에 쌓입니다. 화면에도 그렇게 씁니다.
 *
 * 시각도 정직하게: 친구가 **언제 운동했는지는 모릅니다.** 스냅샷에 그
 * 시각이 없습니다. 우리가 아는 건 "내가 언제 알게 됐는가" 뿐이라,
 * 그것만 적고 카드 밑에 그렇다고 써 둡니다.
 * ========================================================================== */
(function (global) {
  'use strict';

  var KEY = 'mybody.news.v1';
  var MAX = 40;
  var MAX_AGE_DAYS = 21;

  /* 읽음 표시를 시각이 아니라 번호로 합니다.
     시각으로 하면 기기 시계가 틀어졌을 때(수동 변경 · 시간대 이동 ·
     부팅 직후 동기화 전) 새 소식이 "이미 읽은 것" 으로 묻힙니다.
     번호는 이 기기 안에서만 늘어나는 값이라 시계와 무관합니다. */
  function blank() { return { seen: {}, items: [], readSeq: 0, seq: 0 }; }

  function load() {
    try {
      var raw = JSON.parse(localStorage.getItem(KEY) || 'null');
      if (!raw || typeof raw !== 'object') return blank();
      return { seen: raw.seen || {}, items: raw.items || [],
               readSeq: raw.readSeq || 0, seq: raw.seq || 0 };
    } catch (e) { return blank(); }
  }
  function save(db) {
    try { localStorage.setItem(KEY, JSON.stringify(db)); return true; }
    catch (e) { return false; }
  }

  /**
   * 받아온 친구 스냅샷을 지난번 본 것과 견줍니다.
   *
   * snaps:   [{ id, rows }]   rows[0] 이 가장 최근 주 (sync.pull 이 주는 모양)
   * friends: [{ id, displayName }]
   * 돌려주는 값: 이번에 새로 생긴 소식 개수
   */
  function apply(snaps, friends, nowISO) {
    var db = load();
    var now = nowISO || new Date().toISOString();
    var added = 0;

    /* 지금 친구가 아닌 사람, 그리고 일정 공유를 끈 친구의 소식은 지웁니다.
     *
     * backend.js 머리에 "끄면 즉시 사라진다" 가 적혀 있는데 여기에는
     * 지우는 경로가 하나도 없었습니다. 친구가 공유를 꺼도 · 친구를
     * 끊어도 · 차단해도, 그 사람 이름과 지킨 날 수가 내 기기에 그대로
     * 남았습니다. 끈 사람 쪽에서는 사라진 줄 아는데요. */
    var known = {};
    (friends || []).forEach(function (f) { known[f.id] = true; });

    /* "공유를 껐다" 와 "이번엔 못 받아왔다" 는 다릅니다.
     *
     * sync.pull() 은 스냅샷 요청이 실패하면 rows:[] 로 넘깁니다. 그걸
     * 껐다고 읽으면, 잠깐 끊긴 것만으로 그 친구 소식이 통째로 지워지고
     * 기준선까지 사라집니다 — 그 다음에 진짜로 운동해도 "처음 보는
     * 값" 이라 조용히 넘어갑니다. 한 번 깜빡인 네트워크가 소식 기능을
     * 꺼 버리는 셈입니다.
     *
     * 껐다고 단정하는 것은 **행은 왔는데 그 안에 일정 숫자가 없을 때**
     * 뿐입니다. 그건 서버가 공유 설정으로 걸러 냈다는 뜻입니다. */
    var stopped = {};
    (snaps || []).forEach(function (s) {
      var rows = s.rows || [];
      if (rows.length && rows[0].keptDays == null) stopped[s.id] = true;
    });
    db.items = db.items.filter(function (it) {
      return known[it.friendId] && !stopped[it.friendId];
    });
    Object.keys(db.seen).forEach(function (id) {
      if (!known[id] || stopped[id]) delete db.seen[id];
    });

    (snaps || []).forEach(function (s) {
      var row = (s.rows || [])[0];
      /* 행이 아예 없으면 이번엔 모르는 것뿐입니다 — 기준선을 건드리지
         않고 그냥 넘어갑니다. 껐을 때의 정리는 위에서 이미 했습니다. */
      if (!row || row.keptDays == null) return;
      var prev = db.seen[s.id];
      var cur = { weekStart: row.weekStart, keptDays: row.keptDays,
                  plannedDays: row.plannedDays == null ? null : row.plannedDays };

      /* 처음 보는 친구는 조용히 적어만 둡니다. 안 그러면 친구를 맺은
         첫 pull 에서 "3일 운동했습니다" 가 새 소식으로 쏟아집니다 —
         지난 일인데 방금 일어난 것처럼 보입니다. */
      var quiet = !prev || prev.weekStart !== cur.weekStart;

      if (!quiet && cur.keptDays > prev.keptDays) {
        db.seq = (db.seq || 0) + 1;
        db.items.unshift({
          seq: db.seq,
          id: s.id + '|' + cur.weekStart + '|' + cur.keptDays,
          friendId: s.id,
          /* 이름은 그릴 때 친구 목록에서 찾습니다. 여기 박아 두면
             친구가 이름을 바꾼 뒤에도 옛 이름이 계속 남습니다. */
          at: now,
          weekStart: cur.weekStart,
          keptDays: cur.keptDays,
          plannedDays: cur.plannedDays
        });
        added++;
      }
      /* 줄어들었으면 **그 소식을 거둬들입니다.**
       *
       * 새 소식을 만들지는 않습니다(나쁜 소식은 흐르지 않습니다). 대신
       * 이미 적어 둔 줄을 지웁니다. 친구가 체크를 눌렀다가 잘못 눌렀다고
       * 되돌렸는데 내 화면에 "나린님이 운동했습니다" 가 그대로 남아
       * 있으면, 그 줄은 근거가 사라진 말입니다. 남의 행동에 대해
       * 사실이 아닌 문장을 들고 있는 쪽이 조용히 지우는 것보다 나쁩니다.
       *
       * 그 주에 대해 지금 값보다 큰 숫자를 주장하던 줄만 지웁니다 —
       * 2일까지 내려갔으면 "3일째" 는 거짓이 됐고 "2일째" 는 아직 참입니다. */
      if (prev && prev.weekStart === cur.weekStart && cur.keptDays < prev.keptDays) {
        db.items = db.items.filter(function (it) {
          return !(it.friendId === s.id && it.weekStart === cur.weekStart &&
                   it.keptDays > cur.keptDays);
        });
      }
      /* 그대로이거나, 주가 바뀌어 0 으로 돌아간 것은 아무 일도 아닙니다 —
         그건 달력이 한 일입니다. */
      db.seen[s.id] = cur;
    });

    /* 거둬들이기만 하고 새 소식이 없을 때도 저장해야 합니다 —
       added 로만 판단하면 지운 것이 다음에 되살아납니다. */
    if (added) {
      // 같은 소식이 두 번 들어오지 않게 (id 로 한 번 더 거릅니다)
      var got = {};
      db.items = db.items.filter(function (it) {
        if (got[it.id]) return false;
        got[it.id] = true; return true;
      }).slice(0, MAX);
    }
    /* 오래된 소식은 버립니다. 개수 상한만 있으면, 소식이 뜸한 사이라면
       석 달 전 "운동했습니다" 가 계속 첫 줄에 앉아 있습니다 — 소식이
       아니라 화석입니다. */
    var cut = new Date(new Date(now).getTime() - MAX_AGE_DAYS * 86400000).toISOString();
    db.items = db.items.filter(function (it) { return (it.at || '') >= cut; });
    save(db);
    return added;
  }

  function list(limit) { return load().items.slice(0, limit || MAX); }

  /** 아직 안 읽은 소식 개수 */
  function unread() {
    var db = load();
    var n = 0;
    for (var i = 0; i < db.items.length; i++) {
      if ((db.items[i].seq || 0) > (db.readSeq || 0)) n++; else break;   // items 는 최신순
    }
    return n;
  }

  function markRead() {
    var db = load();
    db.readSeq = db.items.length ? (db.items[0].seq || 0) : (db.seq || 0);
    save(db);
  }

  /** 계정을 바꾸거나 지울 때. 남의 소식이 새 계정 화면에 남으면 안 됩니다. */
  function reset() { try { localStorage.removeItem(KEY); } catch (e) {} }

  global.MB_NEWS = { apply: apply, list: list, unread: unread,
                     markRead: markRead, reset: reset, MAX: MAX };
})(window);
