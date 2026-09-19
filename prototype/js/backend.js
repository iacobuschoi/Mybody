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
    { key: 'absolute',     label: '실제 수치까지', kind: 'absolute' }
  ];

  function blankShare() {
    // 전부 꺼짐이 기본. 체크인 여부만 켜 둔다 — 이건 몸에 대한 정보가 아니라 행동에 대한 정보다.
    return { weightTrend: false, smmTrend: false, bfmTrend: false,
             planProgress: false, streak: true, absolute: false, updatedAt: null };
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
      var A = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789', s = '';
      for (var i = 0; i < 8; i++) s += A[(db.seq * 7919 + i * 131 + Object.keys(db.users).length * 37) % A.length];
      db.seq++;
      return s;
    }
    function pairKey(a, b) { return a < b ? a + '|' + b : b + '|' + a; }
    function shareKey(owner, viewer) { return owner + '>' + viewer; }

    /* --- 계정 --------------------------------------------------------- */
    function signIn(opts) {
      opts = opts || {};
      var provider = opts.provider || 'kakao';
      var handle = opts.handle || (provider + ':' + nextId('u'));
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
    function currentUser() { return db.session ? JSON.parse(JSON.stringify(db.users[db.session])) : null; }
    function requireUser() {
      if (!db.session) throw new Error('로그인이 필요합니다');
      return db.session;
    }
    function updateProfile(patch) {
      var me = requireUser();
      if (patch.displayName) db.users[me].displayName = String(patch.displayName).slice(0, 20);
      save();
      return currentUser();
    }
    function deleteAccount() {
      var me = requireUser();
      db.friendships = db.friendships.filter(function (f) { return f.aId !== me && f.bId !== me; });
      Object.keys(db.shares).forEach(function (k) {
        if (k.indexOf(me) >= 0) delete db.shares[k];
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
      return { ok: true, status: 'accepted' };
    }

    function decline(otherId) {
      var me = requireUser();
      var e = edgeOf(me, otherId);
      if (!e || e.status !== 'pending') return { ok: false, reason: '받은 요청이 없습니다' };
      db.friendships = db.friendships.filter(function (f) { return f !== e; });
      save();
      return { ok: true };
    }

    function removeFriend(otherId) {
      var me = requireUser();
      var e = edgeOf(me, otherId);
      if (!e) return { ok: false, reason: '친구가 아닙니다' };
      db.friendships = db.friendships.filter(function (f) { return f !== e; });
      delete db.shares[shareKey(me, otherId)];
      delete db.shares[shareKey(otherId, me)];
      // 끊으면 상대가 받아간 스냅샷도 더는 읽히지 않는다
      save();
      return { ok: true };
    }

    function block(otherId) {
      var me = requireUser();
      var e = edgeOf(me, otherId);
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
    function getShare(ownerId, viewerId) {
      return JSON.parse(JSON.stringify(db.shares[shareKey(ownerId, viewerId)] || blankShare()));
    }
    function setShare(viewerId, patch) {
      var me = requireUser();
      if (!areFriends(me, viewerId)) return { ok: false, reason: '친구가 아닙니다' };
      var cur = db.shares[shareKey(me, viewerId)] || blankShare();
      SHARE_FIELDS.forEach(function (f) {
        if (Object.prototype.hasOwnProperty.call(patch, f.key)) cur[f.key] = !!patch[f.key];
      });
      // 실제 수치는 변화량 공유가 하나라도 켜져 있어야 의미가 있다
      if (cur.absolute && !cur.weightTrend && !cur.smmTrend && !cur.bfmTrend) cur.absolute = false;
      cur.updatedAt = now();
      db.shares[shareKey(me, viewerId)] = cur;
      save();
      return { ok: true, share: JSON.parse(JSON.stringify(cur)) };
    }
    function shareSummary(ownerId, viewerId) {
      var s = db.shares[shareKey(ownerId, viewerId)] || blankShare();
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
      return { ok: true };
    }

    /** 친구가 나에게 공유한 것만. 허용 안 된 키는 아예 객체에 없다. */
    function getFriendSnapshots(ownerId, limit) {
      var me = requireUser();
      if (!areFriends(me, ownerId)) return { ok: false, reason: '친구가 아닙니다', rows: [] };
      var s = db.shares[shareKey(ownerId, me)] || blankShare();
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
          // 서버(server/db.js)와 같은 규칙: 켠 항목에만 숫자가 붙습니다
          if (s.absolute) {
            if (s.weightTrend && p.weightKg != null) out.weightKg = p.weightKg;
            if (s.smmTrend && p.smmKg != null) out.smmKg = p.smmKg;
            if (s.bfmTrend && p.bfmKg != null) out.bfmKg = p.bfmKg;
            if (s.bfmTrend && p.pbfPct != null) out.pbfPct = p.pbfPct;
          }
          return out;
        });
      return { ok: true, rows: rows, allowed: s };
    }

    function reset() { db = blankDb(); save(); }
    function raw() { return db; }

    return {
      SHARE_FIELDS: SHARE_FIELDS, blankShare: blankShare,
      signIn: signIn, signOut: signOut, currentUser: currentUser,
      updateProfile: updateProfile, deleteAccount: deleteAccount,
      findByInviteCode: findByInviteCode, sendRequest: sendRequest,
      accept: accept, decline: decline, removeFriend: removeFriend, block: block,
      listFriends: listFriends, areFriends: areFriends,
      getShare: getShare, setShare: setShare, shareSummary: shareSummary,
      publishSnapshot: publishSnapshot, getFriendSnapshots: getFriendSnapshots,
      reset: reset, raw: raw,
      _setSession: function (id) { db.session = id; save(); }   // 시뮬레이션용
    };
  }

  global.MB_BACKEND = make();
  global.MB_BACKEND_make = make;      // 시뮬레이터가 독립 인스턴스를 만들 때
})(typeof window !== 'undefined' ? window : globalThis);
