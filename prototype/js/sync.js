/* =============================================================================
 * sync.js — 브라우저와 자가호스팅 서버를 잇는 계층
 *
 * 왜 이 파일이 필요한가
 *   여기 오기 전까지 브라우저 앱에는 fetch 호출이 단 한 개도 없었습니다.
 *   권한 엔진이 두 벌(backend.js / server/db.js)인데 실제로 도는 쪽은
 *   localStorage 뿐이었고, 서버는 아무도 안 썼습니다. 그래서 친구 기능이
 *   한 브라우저 안에서만 작동했습니다 — 초대 코드를 줘도 상대 폰에는
 *   내 계정이 존재하지 않았습니다.
 *
 * 왜 동기 API 를 유지하는가
 *   화면 21개가 B().listFriends() 를 동기로 부릅니다. 전부 async 로 바꾸면
 *   앱을 다시 써야 하고, 그 과정에서 새 버그가 화면 수만큼 생깁니다.
 *   대신 오프라인 우선으로 갑니다 — 읽기는 로컬 거울에서 즉시, 쓰기는
 *   로컬에 먼저 반영하고 서버로 밀어 보냅니다. 앱이 원래 내세우던 구조이고
 *   인터넷이 끊겨도 앱이 멈추지 않습니다.
 *
 * 진실의 소재
 *   로그인한 동안에는 서버가 진실입니다. pull() 이 서버 상태로 로컬을
 *   덮어씁니다. 특히 친구의 스냅샷은 서버에서만 올 수 있습니다 —
 *   남의 데이터를 로컬이 알 방법이 없습니다.
 *   권한 판정은 언제나 서버가 합니다. 로컬 거울은 이미 걸러진 값만 받습니다.
 * ========================================================================== */
(function (global) {
  'use strict';

  var KEY = 'mybody.sync.v1';

  function loadCfg() {
    try { return JSON.parse(localStorage.getItem(KEY) || 'null') || {}; }
    catch (e) { return {}; }
  }
  function saveCfg(c) {
    try { localStorage.setItem(KEY, JSON.stringify(c)); } catch (e) {}
  }

  var cfg = loadCfg();
  cfg.queue = cfg.queue || [];
  var listeners = [];
  var flushing = false;
  var lastError = null;
  var lastPullAt = null;

  function emit() { listeners.forEach(function (f) { try { f(status()); } catch (e) {} }); }
  function onChange(f) { listeners.push(f); }

  function status() {
    return {
      configured: !!cfg.baseUrl,
      signedIn: !!cfg.token,
      baseUrl: cfg.baseUrl || null,
      handle: cfg.handle || null,
      pending: cfg.queue.length,
      lastPullAt: lastPullAt,
      lastError: lastError,
      online: (typeof navigator === 'undefined') || navigator.onLine !== false
    };
  }

  /** 서버 주소. 앱이 서버에서 서빙되고 있으면 같은 출처를 기본값으로 씁니다. */
  function defaultBase() {
    try {
      if (location.protocol === 'http:' || location.protocol === 'https:') return location.origin;
    } catch (e) {}
    return null;
  }

  function configure(baseUrl) {
    cfg.baseUrl = baseUrl ? String(baseUrl).replace(/\/+$/, '') : null;
    saveCfg(cfg); emit();
    return status();
  }

  function api(path, opts) {
    var base = cfg.baseUrl || defaultBase();
    if (!base) return Promise.reject(new Error('서버 주소가 설정되지 않았습니다'));
    opts = opts || {};
    var headers = { 'content-type': 'application/json' };
    if (cfg.token) headers.authorization = 'Bearer ' + cfg.token;
    return fetch(base + '/api' + path, {
      method: opts.method || 'GET',
      headers: headers,
      body: opts.body ? JSON.stringify(opts.body) : undefined
    }).then(function (r) {
      return r.json().catch(function () { return {}; }).then(function (j) {
        if (r.status === 401 && cfg.token) {
          // 토큰이 죽었습니다(만료·탈퇴·비밀번호 변경). 조용히 로그아웃합니다.
          cfg.token = null; saveCfg(cfg); emit();
        }
        if (!r.ok) {
          var e = new Error(j.reason || ('서버 오류 ' + r.status));
          e.status = r.status; e.body = j;
          throw e;
        }
        return j;
      });
    });
  }

  /* --- 계정 ------------------------------------------------------------- */

  function signUp(o) {
    return api('/auth/signup', { method: 'POST', body: {
      handle: o.handle, password: o.password, displayName: o.displayName, pairSecret: o.pairSecret
    } }).then(function (r) {
      cfg.token = r.token; cfg.handle = r.user.handle; saveCfg(cfg);
      emit();
      return pull().then(function () { return r; });
    });
  }

  function signIn(o) {
    return api('/auth/signin', { method: 'POST', body: {
      handle: o.handle, password: o.password
    } }).then(function (r) {
      cfg.token = r.token; cfg.handle = r.user.handle; saveCfg(cfg);
      emit();
      return pull().then(function () { return r; });
    });
  }

  function signOut() {
    var done = cfg.token ? api('/auth/signout', { method: 'POST' }).catch(function () {})
                         : Promise.resolve();
    return done.then(function () {
      cfg.token = null; cfg.queue = []; saveCfg(cfg);
      // 로컬 거울도 비웁니다. 남의 기기에 내 친구 목록을 남기지 않습니다.
      if (global.MB_BACKEND) global.MB_BACKEND.reset();
      emit();
    });
  }

  function changePassword(o) {
    return api('/auth/password', { method: 'POST', body: { current: o.current, next: o.next } })
      .then(function (r) { cfg.token = r.token; saveCfg(cfg); emit(); return r; });
  }

  /* --- 쓰기 큐 ----------------------------------------------------------
   * 로컬에 먼저 반영하고 서버로 밀어 보냅니다.
   * 4xx(영구 실패)는 큐에서 빼고 기록합니다 — 계속 재시도하면 큐가 영원히 막힙니다.
   * 네트워크 오류는 남겨 둡니다.
   * -------------------------------------------------------------------- */
  var OPS = {
    sendRequest:  function (a) { return api('/friends/request', { method: 'POST', body: { inviteCode: a.inviteCode } }); },
    accept:       function (a) { return api('/friends/accept', { method: 'POST', body: { userId: a.userId } }); },
    decline:      function (a) { return api('/friends/decline', { method: 'POST', body: { userId: a.userId } }); },
    removeFriend: function (a) { return api('/friends/' + encodeURIComponent(a.userId), { method: 'DELETE' }); },
    block:        function (a) { return api('/friends/block', { method: 'POST', body: { userId: a.userId } }); },
    unblock:      function (a) { return api('/friends/unblock', { method: 'POST', body: { userId: a.userId } }); },
    setShare:     function (a) { return api('/share/' + encodeURIComponent(a.userId), { method: 'PUT', body: a.patch }); },
    updateMe:     function (a) { return api('/me', { method: 'PATCH', body: { displayName: a.displayName } }); },
    snapshot:     function (a) { return api('/snapshots', { method: 'POST', body: { weekStart: a.weekStart, payload: a.payload } }); }
  };

  function enqueue(op, args) {
    if (!cfg.token) return;          // 로그인 안 했으면 서버에 보낼 것이 없습니다
    if (!OPS[op]) { console.warn('알 수 없는 동기화 작업:', op); return; }
    cfg.queue.push({ op: op, args: args, at: Date.now() });
    if (cfg.queue.length > 500) cfg.queue.shift();
    saveCfg(cfg); emit();
    flush();
  }

  function flush() {
    if (flushing || !cfg.token || !cfg.queue.length) return Promise.resolve();
    flushing = true;
    var failed = [];

    function step() {
      if (!cfg.queue.length) return Promise.resolve();
      var job = cfg.queue[0];
      return OPS[job.op](job.args).then(function () {
        cfg.queue.shift(); saveCfg(cfg);
        return step();
      }).catch(function (e) {
        if (e.status && e.status >= 400 && e.status < 500) {
          // 서버가 거절했습니다. 다시 보내도 같은 답이 옵니다.
          cfg.queue.shift(); saveCfg(cfg);
          failed.push({ op: job.op, reason: e.message });
          return step();
        }
        throw e;   // 네트워크 문제 — 큐를 남기고 멈춥니다
      });
    }

    return step().then(function () {
      lastError = failed.length ? ('서버가 거절한 작업 ' + failed.length + '건: ' +
                                   failed.map(function (f) { return f.op + '(' + f.reason + ')'; }).join(', '))
                                : null;
    }).catch(function (e) {
      lastError = e.message;
    }).then(function () {
      flushing = false; emit();
      return pull();
    });
  }

  /* --- 읽기 ------------------------------------------------------------
   * 서버 상태를 로컬 거울에 씁니다. 친구의 스냅샷은 서버에서만 옵니다 —
   * 이미 서버가 공유 설정으로 걸러서 준 값입니다.
   * -------------------------------------------------------------------- */
  function pull() {
    if (!cfg.token) return Promise.resolve(null);
    var B = global.MB_BACKEND;
    if (!B || !B.mirror) return Promise.resolve(null);

    return api('/me').then(function (meRes) {
      return api('/friends').then(function (frRes) {
        var friends = frRes.friends || {};
        var accepted = friends.accepted || [];
        // 친구마다 허용된 스냅샷을 받아옵니다
        return Promise.all(accepted.map(function (f) {
          return api('/snapshots/' + encodeURIComponent(f.id) + '?limit=26')
            .then(function (s) { return { id: f.id, rows: s.rows || [], allowed: s.allowed || {} }; })
            .catch(function () { return { id: f.id, rows: [], allowed: {} }; });
        })).then(function (snaps) {
          B.mirror({ me: meRes.user, friends: friends, snapshots: snaps });
          lastPullAt = new Date().toISOString();
          lastError = null;
          emit();
          return { me: meRes.user, friends: friends };
        });
      });
    }).catch(function (e) {
      lastError = e.message; emit();
      return null;
    });
  }

  /**
   * 친구 요청은 큐에 넣지 않고 바로 보냅니다.
   *
   * 초대 코드는 상대의 것이라 내 기기에 있을 리가 없습니다. 로컬에서 찾으면
   * 언제나 "그런 코드를 가진 사람이 없습니다"가 나옵니다 — 실제로 그랬고,
   * 그래서 다른 기기끼리는 친구가 될 수 없었습니다.
   * 코드가 맞는지는 서버만 압니다. 답을 기다렸다가 사용자에게 보여줍니다.
   */
  function sendRequest(inviteCode) {
    if (!cfg.token) return Promise.reject(new Error('로그인이 필요합니다'));
    return api('/friends/request', { method: 'POST', body: { inviteCode: inviteCode } })
      .then(function (r) {
        if (!r.ok) { var e = new Error(r.reason || '요청에 실패했습니다'); throw e; }
        return pull().then(function () { return r; });
      });
  }

  /* 앱이 켜질 때와 온라인으로 돌아올 때 맞춰 옵니다. */
  function boot() {
    if (!cfg.baseUrl) cfg.baseUrl = defaultBase();
    if (cfg.token) { flush(); }
    try {
      global.addEventListener('online', function () { flush(); });
    } catch (e) {}
  }

  global.MB_SYNC = {
    status: status, onChange: onChange, configure: configure,
    signUp: signUp, signIn: signIn, signOut: signOut, changePassword: changePassword,
    signOutAll: function () { return api('/auth/signout-all', { method: 'POST' }); },
    deleteAccount: function () { return api('/me', { method: 'DELETE' }); },
    enqueue: enqueue, flush: flush, pull: pull, boot: boot,
    sendRequest: sendRequest,
    _api: api
  };
})(window);
