/* =============================================================================
 * backend.js — 계정 · 친구 · 공유
 *
 * 전송 계층만 로컬 목(mock)이고, 권한 규칙은 진짜입니다.
 * 나중에 Supabase 로 갈 때 이 파일의 adapter 만 갈아끼우면 화면은 그대로입니다.
 *
 * 설계 원칙 (docs/PLAN-social.md)
 *   1. 친구 추가와 데이터 공개는 다른 일이다 — 공유 기본값은 전부 꺼짐
 *   2. 친구는 원본을 못 읽는다 — 공유 설정이 허용한 항목만 걸러서 준다
 *   3. 기본 공유 단위는 절대값이 아니라 변화량
 *   4. 끄면 즉시 사라진다
 *   5. 친구 찾기는 초대 코드로만 — 전화번호·이메일 검색 없음
 * ========================================================================== */
(function (global) {
  'use strict';

  var KEY = 'mybody.backend.v1';

  /* --- 저장 어댑터: 브라우저면 localStorage, 노드면 메모리 ----------------- */
  function makeStorage() {
    var hasLS = false;
    try { hasLS = typeof localStorage !== 'undefined' && localStorage !== null; } catch (e) {}
    if (hasLS) {
      return {
        read: function () { try { return JSON.parse(localStorage.getItem(KEY) || 'null'); } catch (e) { return null; } },
        write: function (v) { try { localStorage.setItem(KEY, JSON.stringify(v)); } catch (e) {} }
      };
    }
    var mem = null;
    return { read: function () { return mem; }, write: function (v) { mem = v; } };
  }

  var SHARE_FIELDS = [
    { key: 'weightTrend',  label: '체중 변화',     kind: 'trend' },
    { key: 'smmTrend',     label: '골격근 변화',   kind: 'trend' },
    { key: 'bfmTrend',     label: '체지방 변화',   kind: 'trend' },
    { key: 'planProgress', label: '목표 달성률',   kind: 'progress' },
    { key: 'streak',       label: '체크인 기록',   kind: 'streak' },
    { key: 'schedule',     label: '이번 주 운동 일정', kind: 'schedule' },
    { key: 'absolute',     label: '실제 수치까지', kind: 'absolute' }
  ];

  function blankShare() {
    // 몸에 대한 것은 전부 꺼짐이 기본. 행동에 대한 것 둘만 켜 둔다 —
    // 체크인 여부와 이번 주 일정("계획 4일 · 지킴 2일" 두 숫자).
    // 서버의 blankShare() 와 같아야 한다. 어긋나면 오프라인에서 켜 둔
    // 것이 로그인 순간 꺼지거나, 그 반대가 된다.
    return { weightTrend: false, smmTrend: false, bfmTrend: false,
             planProgress: false, streak: true, schedule: true,
             absolute: false, updatedAt: null };
  }

  function blankDb() {
    return { users: {}, session: null, friendships: [], shares: {}, snapshots: [], seq: 1 };
  }

  function make(storageOverride, clock) {
    var store = storageOverride || makeStorage();
    var now = clock || function () { return new Date().toISOString(); };
    var db = store.read() || blankDb();

    function save() { store.write(db); }
    function nextId(p) { return p + '_' + (db.seq++); }
    function code() {
      // 사람이 불러줄 수 있는 8자리. 헷갈리는 글자(0/O, 1/I)는 뺀다.
      //
      // 예전 구현은 db.seq 로 만든 등차수열이라 세상에 코드가 16개뿐이었다.
      // 20명 가입시키면 4명이 남의 코드를 받았고, findByInviteCode 는 마지막 사람을
      // 돌려줬다 — 친구 요청이 생판 모르는 사람에게 간다는 뜻이다.
      // 초대 코드는 이 앱 프라이버시 모델의 유일한 관문이라 추측 가능하면 안 된다.
      var A = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
      for (var tries = 0; tries < 50; tries++) {
        var s = '', i;
        var buf = null;
        try {
          if (typeof crypto !== 'undefined' && crypto.getRandomValues) {
            buf = new Uint32Array(8); crypto.getRandomValues(buf);
          }
        } catch (e) {}
        for (i = 0; i < 8; i++) {
          var r = buf ? buf[i] : Math.floor(Math.random() * 0xffffffff);
          s += A[r % A.length];
        }
        if (!findByInviteCode(s)) return s;   // 충돌하면 다시 뽑는다
      }
      return null;
    }
    function pairKey(a, b) { return a < b ? a + '|' + b : b + '|' + a; }
    function shareKey(owner, viewer) { return owner + '>' + viewer; }

    /* --- 계정 --------------------------------------------------------- */
    function signIn(opts) {
      opts = opts || {};
      var provider = opts.provider || 'kakao';
      // handle 은 계정의 정체성이다. 예전엔 여기서 nextId() 로 매번 새 값을 만들어서
      // 바로 아래 "기존 사용자 찾기"가 절대 매치되지 않았다 — 로그아웃 한 번에
      // 초대 코드가 바뀌고 친구 목록이 통째로 사라졌다.
      // 이 기기에서 한 제공자는 한 계정이다. 실서버에서는 OAuth 가 주는 subject 가 들어온다.
      var handle = opts.handle || (provider + ':local');
      var found = null;
      Object.keys(db.users).forEach(function (id) {
        if (db.users[id].handle === handle) found = db.users[id];
      });
      if (!found) {
        var id = nextId('user');
        found = {
          id: id, handle: handle, provider: provider,
          displayName: opts.displayName || ('사용자' + id.split('_')[1]),
          inviteCode: code(), createdAt: now()
        };
        db.users[id] = found;
      }
      db.session = found.id;
      save();
      return JSON.parse(JSON.stringify(found));
    }
    function signOut() { db.session = null; save(); }
    function currentUser() {
      // 세션이 지워진 계정을 가리키면(다른 탭에서 탈퇴, localStorage 부분 삭제 등)
      // 예전엔 JSON.parse(undefined) 가 던져서 설정 탭과 친구 화면이 통째로 죽었다.
      // 복구 경로까지 막혀서 로그아웃 버튼조차 못 눌렀다. 조용히 로그아웃 상태로 떨어뜨린다.
      if (!db.session) return null;
      var u = db.users[db.session];
      if (!u) { db.session = null; save(); return null; }
      return JSON.parse(JSON.stringify(u));
    }
    function requireUser() {
      if (!db.session) throw new Error('로그인이 필요합니다');
      return db.session;
    }
    function updateProfile(patch) {
      var me = requireUser();
      if (patch.displayName) {
        db.users[me].displayName = String(patch.displayName).slice(0, 20);
        push('updateMe', { displayName: db.users[me].displayName });
      }
      /* 서버와 같은 규칙: undefined 는 "안 건드림", null 은 "지워 달라". */
      if (patch.avatar !== undefined) {
        db.users[me].avatar = patch.avatar || null;
        push('updateMe', { avatar: db.users[me].avatar });
      }
      save();
      return currentUser();
    }
    function deleteAccount() {
      var me = requireUser();
      db.friendships = db.friendships.filter(function (f) { return f.aId !== me && f.bId !== me; });
      // 예전엔 k.indexOf(me) >= 0 이라 user_1 탈퇴가 user_11·user_13 의 공유 행까지
      // 지웠습니다. 친구 관계 행은 동등 비교라 살아남으므로, 두 사람은 공유 행 없는
      // 친구로 남고 getShare 가 blankShare() 로 떨어집니다 — 그 기본값의 streak:true
      // 때문에 명시적으로 꺼 둔 설정이 남의 탈퇴로 다시 켜졌습니다.
      Object.keys(db.shares).forEach(function (k) {
        var pp = k.split('>');
        if (pp[0] === me || pp[1] === me) delete db.shares[k];
      });
      db.snapshots = db.snapshots.filter(function (s) { return s.ownerId !== me; });
      delete db.users[me];
      db.session = null;
      save();
    }

    /* --- 친구 --------------------------------------------------------- */
    function findByInviteCode(c) {
      var hit = null;
      Object.keys(db.users).forEach(function (id) {
        if (db.users[id].inviteCode === String(c || '').toUpperCase()) hit = db.users[id];
      });
      return hit ? { id: hit.id, displayName: hit.displayName } : null;
    }

    function edgeOf(a, b) {
      var k = pairKey(a, b);
      for (var i = 0; i < db.friendships.length; i++) {
        if (pairKey(db.friendships[i].aId, db.friendships[i].bId) === k) return db.friendships[i];
      }
      return null;
    }

    function sendRequest(inviteCode) {
      var me = requireUser();
      var other = findByInviteCode(inviteCode);
      if (!other) return { ok: false, reason: '그런 코드를 가진 사람이 없습니다' };
      if (other.id === me) return { ok: false, reason: '자기 자신은 추가할 수 없습니다' };
      var e = edgeOf(me, other.id);
      if (e) {
        if (e.status === 'blocked') return { ok: false, reason: '요청할 수 없는 상대입니다' };
        if (e.status === 'accepted') return { ok: false, reason: '이미 친구입니다' };
        if (e.status === 'pending') {
          if (e.requestedBy === me) return { ok: false, reason: '이미 보낸 요청입니다' };
          return accept(other.id);            // 상대가 먼저 보냈으면 바로 성사
        }
      }
      db.friendships.push({
        id: nextId('fr'), aId: me, bId: other.id, status: 'pending',
        requestedBy: me, createdAt: now(), respondedAt: null
      });
      save();
      push('sendRequest', { inviteCode: String(inviteCode || '').toUpperCase() });
      return { ok: true, status: 'pending' };
    }

    function accept(otherId) {
      var me = requireUser();
      var e = edgeOf(me, otherId);
      if (!e || e.status !== 'pending') return { ok: false, reason: '받은 요청이 없습니다' };
      if (e.requestedBy === me) return { ok: false, reason: '내가 보낸 요청은 내가 수락할 수 없습니다' };
      e.status = 'accepted';
      e.respondedAt = now();
      // 친구가 되어도 공유는 켜지지 않는다. 양쪽 모두 기본값(꺼짐)으로 시작한다.
      if (!db.shares[shareKey(me, otherId)]) db.shares[shareKey(me, otherId)] = blankShare();
      if (!db.shares[shareKey(otherId, me)]) db.shares[shareKey(otherId, me)] = blankShare();
      save();
      push('accept', { userId: otherId });
      return { ok: true, status: 'accepted' };
    }

    function decline(otherId) {
      var me = requireUser();
      var e = edgeOf(me, otherId);
      if (!e || e.status !== 'pending') return { ok: false, reason: '받은 요청이 없습니다' };
      db.friendships = db.friendships.filter(function (f) { return f !== e; });
      save();
      push('decline', { userId: otherId });
      return { ok: true };
    }

    function removeFriend(otherId) {
      var me = requireUser();
      var e = edgeOf(me, otherId);
      if (!e) return { ok: false, reason: '친구가 아닙니다' };
      // 차단당한 사람이 "친구 끊기"로 자기를 막고 있는 행을 지울 수 있었습니다.
      if (e.status === 'blocked' && e.blockedBy !== me)
        return { ok: false, reason: '친구가 아닙니다' };
      if (e.status === 'pending' && e.requestedBy !== me)
        return { ok: false, reason: '받은 요청은 거절로 처리합니다' };
      db.friendships = db.friendships.filter(function (f) { return f !== e; });
      delete db.shares[shareKey(me, otherId)];
      delete db.shares[shareKey(otherId, me)];
      // 끊으면 상대가 받아간 스냅샷도 더는 읽히지 않는다
      save();
      push('removeFriend', { userId: otherId });
      return { ok: true };
    }

    function block(otherId) {
      var me = requireUser();
      if (otherId === me) return { ok: false, reason: '자기 자신은 차단할 수 없습니다' };
      var e = edgeOf(me, otherId);
      // 맞차단으로 남의 차단을 자기 것으로 덮어쓰면, 그걸 풀어서 관계를 되살릴 수 있습니다.
      if (e && e.status === 'blocked' && e.blockedBy !== me)
        return { ok: false, reason: '요청할 수 없는 상대입니다' };
      if (!e) {
        e = { id: nextId('fr'), aId: me, bId: otherId, status: 'blocked',
              requestedBy: me, createdAt: now(), respondedAt: now() };
        db.friendships.push(e);
      }
      e.status = 'blocked';
      e.blockedBy = me;
      delete db.shares[shareKey(me, otherId)];
      delete db.shares[shareKey(otherId, me)];
      save();
      push('block', { userId: otherId });
      return { ok: true };
    }

    /** 차단 해제. 차단한 본인만. 이게 없으면 차단한 사람이 영원히 지울 수 없는 행에 묶입니다. */
    function unblock(otherId) {
      var me = requireUser();
      var e = edgeOf(me, otherId);
      if (!e || e.status !== 'blocked') return { ok: false, reason: '차단하지 않은 상대입니다' };
      if (e.blockedBy !== me) return { ok: false, reason: '내가 차단한 상대가 아닙니다' };
      db.friendships = db.friendships.filter(function (f) { return f !== e; });
      save();
      push('unblock', { userId: otherId });
      return { ok: true };
    }

    function listFriends() {
      var me = requireUser();
      var out = { accepted: [], incoming: [], outgoing: [], blocked: [] };
      db.friendships.forEach(function (f) {
        if (f.aId !== me && f.bId !== me) return;
        var otherId = f.aId === me ? f.bId : f.aId;
        var u = db.users[otherId];
        if (!u) return;
        var row = { id: otherId, displayName: u.displayName, since: f.respondedAt || f.createdAt };
        if (f.status === 'accepted') {
          /* 사진은 수락한 친구에게만 — 서버 구현과 같은 규칙입니다. */
          row.avatar = u.avatar || null;
          row.iShare = shareSummary(me, otherId);
          row.theyShare = shareSummary(otherId, me);
          out.accepted.push(row);
        } else if (f.status === 'pending') {
          (f.requestedBy === me ? out.outgoing : out.incoming).push(row);
        } else if (f.status === 'blocked' && f.blockedBy === me) {
          out.blocked.push(row);
        }
      });
      return out;
    }

    function areFriends(a, b) {
      var e = edgeOf(a, b);
      return !!(e && e.status === 'accepted');
    }

    /* --- 공유 설정 ----------------------------------------------------- */
    /* 저장된 행이 있으면 **그 행이 전부** 입니다.
     *
     * 없는 키를 blankShare() 로 채우면, 나중에 생긴 기본 켜짐 항목이
     * 그 항목을 본 적도 없는 옛 관계에서 저절로 켜집니다. 서버에서
     * 실제로 그렇게 됐습니다(server/db.js 의 마이그레이션 주석 참고).
     * 여기는 원래 병합을 안 하고 있어서 운 좋게 안전했는데, 운에
     * 기대지 않도록 규칙을 눈에 보이게 적어 둡니다. */
    function readShare(ownerId, viewerId) {
      var saved = db.shares[shareKey(ownerId, viewerId)];
      if (!saved) return blankShare();
      var out = { updatedAt: saved.updatedAt || null };
      for (var i = 0; i < SHARE_FIELDS.length; i++) {
        out[SHARE_FIELDS[i].key] = saved[SHARE_FIELDS[i].key] === true;
      }
      return out;
    }
    function getShare(ownerId, viewerId) {
      return readShare(ownerId, viewerId);
    }
    function setShare(viewerId, patch) {
      var me = requireUser();
      if (!areFriends(me, viewerId)) return { ok: false, reason: '친구가 아닙니다' };
      var cur = readShare(me, viewerId);
      // !! 강제변환이면 문자열 "false" 가 true 가 됩니다. 이 앱에서 가장 민감한
      // 스위치가 한쪽 방향으로만(= 더 열리는 쪽으로만) 실패하던 자리입니다.
      for (var si = 0; si < SHARE_FIELDS.length; si++) {
        var sk = SHARE_FIELDS[si].key;
        if (!Object.prototype.hasOwnProperty.call(patch, sk)) continue;
        if (typeof patch[sk] !== 'boolean') return { ok: false, reason: '공유 설정은 true/false 여야 합니다' };
        cur[sk] = patch[sk];
      }
      // 실제 수치는 변화량 공유가 하나라도 켜져 있어야 의미가 있다
      if (cur.absolute && !cur.weightTrend && !cur.smmTrend && !cur.bfmTrend) cur.absolute = false;
      cur.updatedAt = now();
      db.shares[shareKey(me, viewerId)] = cur;
      save();
      // 서버에는 patch 만 보냅니다 — 전체를 보내면 로컬이 서버보다 오래된
      // 값을 갖고 있을 때 다른 항목을 되돌려 버립니다.
      push('setShare', { userId: viewerId, patch: JSON.parse(JSON.stringify(patch)) });
      return { ok: true, share: JSON.parse(JSON.stringify(cur)) };
    }
    function shareSummary(ownerId, viewerId) {
      var s = readShare(ownerId, viewerId);
      var on = SHARE_FIELDS.filter(function (f) { return s[f.key]; }).map(function (f) { return f.label; });
      return { count: on.length, labels: on, settings: JSON.parse(JSON.stringify(s)) };
    }

    /* --- 스냅샷 -------------------------------------------------------- */
    /**
     * 소유자가 자기 주간 요약을 올린다. payload 는 전부 담기지만,
     * 읽을 때 viewer 별 공유 설정으로 걸러서 나간다.
     * (실서버라면 viewer 별로 이미 걸러진 행을 따로 저장하는 편이 더 안전하다 —
     *  읽기 경로 하나가 뚫려도 허용 안 된 값이 애초에 존재하지 않으므로.)
     */
    function publishSnapshot(weekStart, payload) {
      var me = requireUser();
      if (!db.users[me]) return { ok: false, reason: '없는 계정입니다' };
      var existing = null;
      for (var i = 0; i < db.snapshots.length; i++) {
        if (db.snapshots[i].ownerId === me && db.snapshots[i].weekStart === weekStart) existing = db.snapshots[i];
      }
      var row = existing || { id: nextId('snap'), ownerId: me, weekStart: weekStart };
      row.payload = JSON.parse(JSON.stringify(payload || {}));
      row.computedAt = now();
      if (!existing) db.snapshots.push(row);
      if (db.snapshots.length > 20000) db.snapshots.shift();
      save();
      push('snapshot', { weekStart: weekStart, payload: row.payload });
      return { ok: true };
    }

    /** 친구가 나에게 공유한 것만. 허용 안 된 키는 아예 객체에 없다. */
    function getFriendSnapshots(ownerId, limit) {
      var me = requireUser();
      if (!areFriends(me, ownerId)) return { ok: false, reason: '친구가 아닙니다', rows: [] };
      var s = readShare(ownerId, me);

      /* 서버에서 온 행은 이미 걸러진 값입니다. 여기서 다시 거르면
         로컬 설정이 서버 설정보다 앞서 적용되어, 서버가 허용한 것을
         로컬이 숨기거나(혼란) 그 반대가 됩니다. */
      var fromServer = db.snapshots.filter(function (x) {
        return x.ownerId === ownerId && x.serverFiltered;
      });
      if (fromServer.length) {
        var srvRows = fromServer
          .sort(function (a, b) { return a.weekStart < b.weekStart ? 1 : -1; })
          .slice(0, limit || 26)
          .map(function (x) { return x.payload; });
        return { ok: true, rows: srvRows,
                 allowed: (db.serverAllowed && db.serverAllowed[ownerId]) || s };
      }

      var rows = db.snapshots
        .filter(function (x) { return x.ownerId === ownerId; })
        .sort(function (a, b) { return a.weekStart < b.weekStart ? 1 : -1; })
        .slice(0, limit || 26)
        .map(function (x) {
          var p = x.payload || {}, out = { weekStart: x.weekStart };
          if (s.weightTrend && p.dWeightKg != null) out.dWeightKg = p.dWeightKg;
          if (s.smmTrend && p.dSmmKg != null) out.dSmmKg = p.dSmmKg;
          if (s.bfmTrend && p.dBfmKg != null) out.dBfmKg = p.dBfmKg;
          if (s.planProgress && p.progressPct != null) out.progressPct = p.progressPct;
          if (s.streak && p.checkedIn != null) out.checkedIn = p.checkedIn;
          /* 일정은 숫자 두 개만 — 며칠 하기로 했고 며칠 지켰는가.
             요일과 종목은 안 나갑니다 (server/db.js 와 같은 규칙). */
          if (s.schedule && p.plannedDays != null) {
            out.plannedDays = p.plannedDays;
            out.keptDays = p.keptDays;
            out.missedDays = p.missedDays;
            out.openDays = p.openDays;
          }
          // 서버(server/db.js)와 같은 규칙: 켠 항목에만 숫자가 붙습니다
          if (s.absolute) {
            if (s.weightTrend && p.weightKg != null) out.weightKg = p.weightKg;
            if (s.smmTrend && p.smmKg != null) out.smmKg = p.smmKg;
            if (s.bfmTrend && p.bfmKg != null) out.bfmKg = p.bfmKg;
            // 원칙: 다른 두 값으로 계산되는 항목은 두 게이트의 논리곱으로 잠급니다.
            // pbfPct = bfmKg / weightKg 이므로 둘이 같이 나가면 체중이 복원됩니다.
            if (s.weightTrend && s.bfmTrend && p.pbfPct != null) out.pbfPct = p.pbfPct;
          }
          return out;
        });
      return { ok: true, rows: rows, allowed: s };
    }

    function reset() {
      db = blankDb(); save();
      /* 친구 소식도 같이 지웁니다. 로컬 거울을 비우는 이유가 "남의 기기에
         내 친구 목록을 남기지 않는다" 인데, 소식은 그보다 더 구체적입니다 —
         누가 언제 운동했는지가 이름째로 적혀 있습니다. */
      try { if (global.MB_NEWS) global.MB_NEWS.reset(); } catch (e) {}
    }
    function raw() { return db; }

    /* --- 서버 상태를 로컬 거울에 쓴다 -----------------------------------
     * sync.js 가 서버에서 받아온 것을 여기로 넣습니다. 화면은 계속
     * 동기로 읽고, 그 값은 서버가 이미 공유 설정으로 걸러 준 것입니다.
     *
     * 중요: 여기서 권한을 다시 판정하지 않습니다. 서버가 안 준 값은
     * 애초에 없습니다 — 로컬이 "이건 보여도 되나"를 다시 계산하면
     * 두 판정이 어긋날 때 더 관대한 쪽이 이깁니다.
     * ------------------------------------------------------------------ */
    function mirror(snap) {
      if (!snap || !snap.me) return;
      var meId = snap.me.id;
      db.users = db.users || {};
      db.users[meId] = {
        id: meId, handle: snap.me.handle, provider: snap.me.provider || 'local',
        displayName: snap.me.displayName, inviteCode: snap.me.inviteCode,
        createdAt: snap.me.createdAt, avatar: snap.me.avatar || null
      };
      db.session = meId;

      var f = snap.friends || {};
      db.friendships = [];
      db.shares = {};
      function put(list, status) {
        (list || []).forEach(function (r) {
          db.users[r.id] = db.users[r.id] ||
            { id: r.id, handle: null, provider: 'local', displayName: r.displayName,
              inviteCode: null, createdAt: r.since };
          db.users[r.id].displayName = r.displayName;
          /* 서버는 수락한 친구에게만 사진을 실어 줍니다. 아직 수락 전인
             행에는 avatar 키 자체가 없으므로, 거울도 그 상태 그대로
             둡니다 — 없는 것을 null 로 덮어써도 결과는 같지만, 나중에
             수락되면 다음 pull 이 채웁니다. */
          if (r.avatar !== undefined) db.users[r.id].avatar = r.avatar || null;
          db.friendships.push({
            id: 'srv_' + r.id, aId: meId, bId: r.id,
            /* 'outgoing' 은 서버 응답의 이름일 뿐, 이 거울이 아는 상태가
               아닙니다. listFriends() 는 accepted · pending · blocked
               세 가지만 봅니다 — 그래서 내가 보낸 친구 요청은 서버가
               멀쩡히 돌려줬는데도 조용히 사라졌습니다.
               화면에는 "보낸 요청 N건 · 수락을 기다리는 중" 과 취소
               버튼이 이미 만들어져 있었는데, 한 번도 안 돌았습니다.
               보낸 사람 눈에는 아무 일도 안 일어난 것처럼 보였고,
               잘못 보낸 요청을 물릴 방법도 없었습니다.
               누가 보냈는지는 아래 requestedBy 가 그대로 들고 있으므로,
               pending 으로 넣으면 listFriends() 가 알아서 나눕니다. */
            status: status === 'outgoing' ? 'pending' : status,
            requestedBy: status === 'outgoing' ? meId : r.id,
            blockedBy: status === 'blocked' ? meId : null,
            createdAt: r.since, respondedAt: r.since
          });
          // 내가 이 친구에게 무엇을 보내는지 — 서버가 준 설정 그대로
          if (r.iShare && r.iShare.settings) db.shares[shareKey(meId, r.id)] = r.iShare.settings;
          if (r.theyShare && r.theyShare.settings) db.shares[shareKey(r.id, meId)] = r.theyShare.settings;
        });
      }
      put(f.accepted, 'accepted');
      put(f.incoming, 'pending');
      put(f.outgoing, 'outgoing');
      put(f.blocked, 'blocked');

      // 서버가 걸러서 준 친구 스냅샷. 내 것은 publishWeekly 가 따로 올립니다.
      db.snapshots = (db.snapshots || []).filter(function (x) { return x.ownerId === meId; });
      (snap.snapshots || []).forEach(function (s2) {
        (s2.rows || []).forEach(function (row) {
          db.snapshots.push({ id: 'srv_' + s2.id + '_' + row.weekStart,
                              ownerId: s2.id, weekStart: row.weekStart,
                              payload: row, serverFiltered: true });
        });
        db.serverAllowed = db.serverAllowed || {};
        db.serverAllowed[s2.id] = s2.allowed || {};
      });
      save();
    }

    /** 서버에 보낼 작업을 큐에 넣는다. 로그인 안 했으면 아무 일도 안 일어난다. */
    function push(op, args) {
      var S = global.MB_SYNC;
      if (S && S.enqueue) { try { S.enqueue(op, args); } catch (e) {} }
    }

    return {
      SHARE_FIELDS: SHARE_FIELDS, blankShare: blankShare,
      signIn: signIn, signOut: signOut, currentUser: currentUser,
      updateProfile: updateProfile, deleteAccount: deleteAccount,
      findByInviteCode: findByInviteCode, sendRequest: sendRequest,
      accept: accept, decline: decline, removeFriend: removeFriend,
      block: block, unblock: unblock,
      listFriends: listFriends, areFriends: areFriends,
      getShare: getShare, setShare: setShare, shareSummary: shareSummary,
      publishSnapshot: publishSnapshot, getFriendSnapshots: getFriendSnapshots,
      reset: reset, raw: raw, mirror: mirror,
      _setSession: function (id) { db.session = id; save(); }   // 시뮬레이션용
    };
  }

  global.MB_BACKEND = make();
  global.MB_BACKEND_make = make;      // 시뮬레이터가 독립 인스턴스를 만들 때
})(typeof window !== 'undefined' ? window : globalThis);
