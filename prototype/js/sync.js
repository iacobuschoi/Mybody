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
      signal: opts.signal,          // 취소할 수 있게 (판독이 씁니다)
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

  /* 복구 코드로 비밀번호를 새로 정합니다 — 로그인 전에 쓰는 길입니다.
     서버가 다른 기기의 세션을 전부 끊고 새 코드를 하나 줍니다.
     성공하면 이 기기는 바로 로그인 상태가 됩니다. */
  function recover(o) {
    return api('/auth/recover', { method: 'POST', body: {
      handle: o.handle, code: o.code, password: o.password
    } }).then(function (r) {
      cfg.token = r.token; cfg.handle = r.user.handle; saveCfg(cfg);
      emit();
      return pull().then(function () { return r; });
    });
  }

  /* 코드를 잃어버렸을 때 새로 받습니다. 옛 코드는 그 자리에서 죽습니다. */
  function newRecoveryCode(o) {
    return api('/auth/recovery-code', { method: 'POST', body: { password: o.password } });
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

  var QUEUE_MAX = 500;

  function enqueue(op, args) {
    if (!cfg.token) return;          // 로그인 안 했으면 서버에 보낼 것이 없습니다
    if (!OPS[op]) { console.warn('알 수 없는 동기화 작업:', op); return; }

    /* 같은 주 스냅샷은 겹쳐 쌓지 않습니다.
     *
     * store.save() 가 저장할 때마다 publishWeekly() 를 부르고, 그게
     * snapshot 작업을 큐에 넣습니다. 검수 화면에서 숫자 몇 개를 고치면
     * 같은 주에 대한 똑같은 작업이 수십 개 쌓였습니다. 서버는 같은
     * weekStart 를 덮어쓰므로 마지막 하나만 의미가 있습니다.
     *
     * 오프라인에서 이게 왜 위험했냐면 — 큐가 500 을 넘으면 shift() 로
     * 제일 오래된 것부터 버렸습니다. 제일 오래된 것은 사용자가 실제로
     * 한 일(친구 수락 · 공유 켜기)이고, 쌓인 쪽은 전부 같은 스냅샷의
     * 복사본이었습니다. 중요한 걸 버리고 쓸모없는 걸 지킨 셈입니다. */
    if (op === 'snapshot') {
      for (var i = cfg.queue.length - 1; i >= 0; i--) {
        var j = cfg.queue[i];
        if (j.op === 'snapshot' && j.args && args && j.args.weekStart === args.weekStart) {
          cfg.queue.splice(i, 1);
        }
      }
    }

    cfg.queue.push({ op: op, args: args, at: Date.now() });

    /* 그래도 넘치면, 버리는 순서를 정합니다.
       스냅샷은 다음 저장 때 다시 만들어지지만 친구 수락은 안 그렇습니다. */
    while (cfg.queue.length > QUEUE_MAX) {
      var drop = -1;
      for (var k = 0; k < cfg.queue.length - 1; k++) {
        if (cfg.queue[k].op === 'snapshot') { drop = k; break; }
      }
      cfg.queue.splice(drop >= 0 ? drop : 0, 1);
    }
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

  /* --- 2층: 서버 판독 ------------------------------------------------------
   *
   * 사진을 서버로 보내고 숫자 초안을 받아 옵니다. 이 층은 꺼져 있는 게
   * 기본입니다 — 건강 데이터를 기기 밖으로 내보내는 일이라, 켜는 것은
   * 사용자가 직접 해야 합니다(설정 → 서버).
   *
   * 돌아온 값은 그대로 쓰지 않습니다. crosscheck.js 의 검산을 통과한
   * 것만 초록으로 표시되고, 어긋나면 그 칸을 짚어 줍니다. 그리고 어느
   * 쪽이든 검수 화면은 거칩니다. 2층은 타자를 줄여 줄 뿐, 확정하지
   * 않습니다.
   *
   * 크기: server.js 가 본문 2,000,000 바이트에서 소켓을 끊습니다.
   * base64 는 4/3 배로 부푸니 실질 한도가 1.4MB 남짓이고, 넘으면
   * 브라우저에는 413 이 아니라 "Failed to fetch" 가 뜹니다. 그래서
   * /api/ocr 은 서버에서 따로 큰 한도를 갖고, 클라이언트도 보내기 전에
   * 크기를 확인합니다. photo.js 가 이미 900KB 아래로 줄여 놓습니다.
   * ------------------------------------------------------------------------ */

  var OCR_MAX = 6 * 1024 * 1024;     // 데이터 URL 길이 기준

  /** 2층을 쓸 수 있는 상태인가 — 로그인 + 사용자가 켬 */
  function canOcr() {
    return !!(cfg.token && cfg.ocrEnabled);
  }

  /** 설정 화면에서 켜고 끕니다 */
  function setOcr(on) {
    cfg.ocrEnabled = !!on;
    saveCfg(cfg); emit();
    return canOcr();
  }

  /**
   * @param {string} dataUrl  photo.js 가 줄여 놓은 JPEG 데이터 URL
   * @param {function(err, fields)} cb
   */
  /**
   * @returns {function} 취소 함수. 부르면 업로드를 실제로 멈춥니다.
   *
   * 취소 버튼이 결과만 무시하고 업로드는 계속하게 두면, 사용자의 데이터와
   * 서버의 돈이 그대로 나갑니다 — 사용자가 취소를 누르는 이유는 보통
   * 느려서이고, 그때가 제일 아까운 순간입니다.
   */
  function ocr(dataUrl, cb) {
    cb = cb || function () {};
    if (!canOcr()) { cb(new Error('자동 판독이 꺼져 있습니다')); return function () {}; }
    if (!dataUrl || dataUrl.indexOf('data:image/') !== 0) {
      cb(new Error('사진이 아닙니다')); return function () {};
    }
    if (dataUrl.length > OCR_MAX) {
      cb(new Error('사진이 너무 큽니다')); return function () {};
    }
    var comma = dataUrl.indexOf(',');
    var mime = dataUrl.slice(5, dataUrl.indexOf(';'));
    var ctrl = (typeof AbortController !== 'undefined') ? new AbortController() : null;
    var cancelled = false;

    api('/ocr', { method: 'POST', signal: ctrl ? ctrl.signal : undefined, body: {
      mediaType: mime, data: dataUrl.slice(comma + 1)
    } }).then(function (r) {
      cb(null, (r && r.fields) || {});
    }).catch(function (e) {
      lastError = e.message; emit();
      cb(e);
    });
  }

  global.MB_SYNC = {
    status: status, onChange: onChange, configure: configure,
    signUp: signUp, signIn: signIn, signOut: signOut, changePassword: changePassword,
    recover: recover, newRecoveryCode: newRecoveryCode,
    signOutAll: function () { return api('/auth/signout-all', { method: 'POST' }); },
    deleteAccount: function () { return api('/me', { method: 'DELETE' }); },
    enqueue: enqueue, flush: flush, pull: pull, boot: boot,
    sendRequest: sendRequest,
    canOcr: canOcr, setOcr: setOcr, ocr: ocr,
    _api: api
  };
})(window);
