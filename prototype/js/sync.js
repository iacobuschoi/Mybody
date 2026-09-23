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

  /* 주소가 적혀 있다는 것과 그 주소에 우리 서버가 있다는 것은 다릅니다.
   *
   * defaultBase() 가 location.origin 을 기본값으로 잡습니다. 앱을 내 서버에서
   * 열면 맞는 값이지만, 미리보기 링크(claude.ai)로 열면 그 주소가 그대로
   * 들어옵니다. 그러면 화면은 "서버가 있다" 고 믿고 "로그인하면 자동 판독을
   * 켤 수 있습니다" 라고 말하는데, 눌러 보면 아무 데도 안 닿습니다.
   * 막다른 길을 두 번 안내하는 셈입니다.
   *
   * 그래서 /health 를 한 번 두드려 보고, 답이 온 적이 있는지를 따로 둡니다.
   *   null  아직 안 물어봤다
   *   true  우리 서버가 맞다
   *   false 그 주소에는 우리 서버가 없다
   */
  var reachable = null;

  /* 안 닿을 때도 이유가 둘입니다. 둘을 같은 말로 다루면 한쪽에 틀린
     안내를 하게 됩니다:
       'other'  그 주소에 웹서버는 있는데 이 앱의 서버가 아님
                (미리보기 링크 · 정적 호스트). → 주소를 넣어야 합니다.
       'down'   연결 자체가 안 됨. 컴퓨터가 꺼졌거나 서버를 멈춘 것.
                → 주소는 그대로 둬야 합니다. 바꾸면 기록이 안 보이게
                  됩니다(브라우저가 주소마다 따로 저장하니까). */
  var serverKind = null;   // 'ours' | 'other' | 'down' | null(아직 모름)
  /* 이 서버가 가입에 코드를 요구하는가. null 이면 아직 안 물어봤습니다 —
     "안 요구한다" 와 "모른다" 를 섞으면 화면이 없는 칸을 감추거나
     있는 칸을 빼먹습니다. */
  var openSignup = null;

  /* 서버가 내 토큰을 거절했습니다 (만료 · 탈퇴 · 비밀번호 변경 · 서버 DB 교체).
   *
   * api() 는 401 을 보면 조용히 로그아웃합니다. 조용한 것까지는 맞습니다 —
   * 화면 한가운데에 모달을 띄울 일은 아니니까요. 문제는 그 뒤였습니다.
   * enqueue() 가 "토큰 없으면 그냥 돌아감" 이라, 그 상태에서 공유를 끄면
   *   · 로컬 거울은 꺼지고
   *   · 큐에는 아무것도 안 들어가고 (pending 0, lastError null)
   *   · 화면은 "상대 화면에서 사라졌습니다" 라고 말하고
   *   · 다음 pull 이 서버 값으로 거울을 덮어써 **다시 켜진 채로 돌아옵니다.**
   * 껐다고 믿는 사람은 다시 확인하지 않습니다. */
  var disconnected = false;

  function probe() {
    var base = cfg.baseUrl || defaultBase();
    if (!base) { reachable = false; serverKind = 'other'; emit(); return Promise.resolve(false); }
    /* no-store: 브라우저 HTTP 캐시가 "살아 있다" 를 재활용하지 않게.
       (서비스워커 캐시는 이것으로 못 막아서 sw.js 에서 따로 뺍니다.) */
    return fetch(base + '/health', { cache: 'no-store' })
      .then(function (r) {
        if (!r.ok) return null;
        return r.json().catch(function () { return null; });
      })
      .then(function (j) {
        /* 우리 /health 는 { ok: true } 를 줍니다. 남의 서버가 우연히
           200 을 줘도 그것까지 우리 것으로 세지는 않습니다. */
        var ours = !!(j && j.ok);
        reachable = ours;
        serverKind = ours ? 'ours' : 'other';
        openSignup = ours ? !!j.openSignup : null;
        emit();
        return ours;
      })
      .catch(function () {
        reachable = false; serverKind = 'down'; emit(); return false;
      });
  }

  /* 이 앱을 그 서버가 직접 내보내고 있는가.
     같은 출처에서 왔으면 "여긴 서버가 없는 미리보기" 일 수가 없습니다 —
     방금 이 페이지를 준 게 그 서버니까요. 안 닿으면 꺼진 것입니다. */
  function servedByConfigured() {
    try {
      var base = cfg.baseUrl || defaultBase();
      return !!base && base === location.origin;
    } catch (e) { return false; }
  }

  function status() {
    return {
      configured: !!cfg.baseUrl,
      reachable: reachable,
      serverKind: serverKind,
      openSignup: openSignup,
      /* 로그인한 적이 있는데 지금 토큰이 없는 상태. "아직 로그인 안 함" 과
         다릅니다 — 이쪽은 이 기기에서 한 일이 서버에 안 갑니다. */
      disconnected: disconnected && !cfg.token && !!cfg.handle,
      ownServer: servedByConfigured(),
      signedIn: !!cfg.token,
      baseUrl: cfg.baseUrl || null,
      handle: cfg.handle || null,
      pending: cfg.queue.length,
      lastPullAt: lastPullAt,
      lastError: lastError,
      online: (typeof navigator === 'undefined') || navigator.onLine !== false
    };
  }

  /* --- 방금 한 변경이 상대에게 닿았는가 ----------------------------------
   *
   * 화면이 "상대 화면에서 사라졌습니다" 라고 **완료형**으로 말하던 자리가
   * 여럿 있었습니다. setShare 는 큐를 탈 뿐인데요. 오프라인이면 아직 안
   * 갔고, 토큰이 죽었으면 영영 안 갑니다. 프라이버시 스위치에 대해
   * 실제보다 튼튼하게 말하는 것이 제일 나쁩니다 — 껐다고 믿는 사람은
   * 다시 확인하지 않습니다.
   *
   * 판단을 한 곳에 모읍니다. 화면마다 따로 재면 반드시 어긋납니다.
   *   'local'    서버를 안 씁니다. 이 기기의 값이 곧 사실입니다.
   *   'sending'  로그인·온라인. 큐가 곧 보냅니다 — 미래형으로 말합니다.
   *   'offline'  인터넷이 없습니다. 연결되면 보냅니다.
   *   'cut'      로그인했었는데 토큰이 죽었습니다. 다시 로그인해야 갑니다.
   * -------------------------------------------------------------------- */
  function deliveryMode() {
    if (!cfg.token) return cfg.handle ? 'cut' : 'local';
    try {
      if (typeof navigator !== 'undefined' && navigator.onLine === false) return 'offline';
    } catch (e) {}
    return 'sending';
  }

  /**
   * 끈 직후에 붙일 꼬리 문장.
   * @param {string} who  상대 이름 (없으면 "상대")
   */
  function deliveryNote(who) {
    var name = who || '상대';
    switch (deliveryMode()) {
      case 'local':   return name + '님 화면에서 사라졌습니다';
      case 'sending': return name + '님 화면에서 사라집니다';
      case 'offline': return '지금은 인터넷이 없어서 아직 안 갔습니다 — 연결되면 보냅니다';
      default:        return '이 기기가 서버에서 끊겼습니다 — 다시 로그인해야 반영됩니다';
    }
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
    /* 주소가 바뀌었으니 다시 물어봐야 합니다.
       openSignup 까지 같이 비웁니다 — 열린 서버를 본 뒤 코드가 필요한
       서버로 옮기면, 옛 답이 남아 가입 코드 칸이 사라집니다 — 친구는
       코드를 넣을 데가 없어 가입을 못 합니다. */
    reachable = null; serverKind = null; openSignup = null;
    saveCfg(cfg); emit();
    probe();
    return status();
  }

  function api(path, opts) {
    var base = cfg.baseUrl || defaultBase();
    if (!base) return Promise.reject(new Error('서버 주소가 설정되지 않았습니다'));
    opts = opts || {};
    var headers = { 'content-type': 'application/json' };
    if (cfg.token) headers.authorization = 'Bearer ' + cfg.token;
    /* 시간 제한이 없으면, 대답이 영영 안 오는 요청 하나가 flush() 의
       flushing 플래그를 세션 내내 true 로 잠급니다 — 재시도 타이머조차
       안 걸립니다. 노트북 서버가 잠들거나 폰이 와이파이에서 LTE 로
       넘어가면 그 상태가 됩니다. 그 동안 화면은 "아직 못 올린 변경이
       N건 있습니다 — 곧 다시 보냅니다" 라고 말합니다. 안 보냅니다.

       판독은 자기 signal 을 씁니다(취소 버튼). 그쪽은 건드리지 않습니다. */
    var signal = opts.signal;
    if (!signal && typeof AbortSignal !== 'undefined' && AbortSignal.timeout) {
      try { signal = AbortSignal.timeout(20000); } catch (e) { signal = undefined; }
    }
    return fetch(base + '/api' + path, {
      method: opts.method || 'GET',
      headers: headers,
      signal: signal,
      body: opts.body ? JSON.stringify(opts.body) : undefined
    }).then(function (r) {
      return r.json().catch(function () { return {}; }).then(function (j) {
        if (r.status === 401 && cfg.token) {
          // 토큰이 죽었습니다(만료·탈퇴·비밀번호 변경). 조용히 로그아웃하되,
          // **끊겼다는 사실은 남깁니다** — 이걸 안 남기면 그 뒤로 하는 일이
          // 전부 로컬에만 남고 사용자는 다 된 줄 압니다.
          cfg.token = null; disconnected = true; saveCfg(cfg); emit();
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

  /* 건강정보 업로드 동의 문구의 판. server/db.js 의 같은 이름과
     값이 맞아야 합니다 — 서버가 이 값을 보고 동의를 판정합니다. */
  var HEALTH_CONSENT_VERSION = '2026-09-23';

  function signUp(o) {
    return api('/auth/signup', { method: 'POST', body: {
      handle: o.handle, password: o.password, displayName: o.displayName,
      pairSecret: o.pairSecret,
      /* 체크를 안 했으면 아예 안 보냅니다. 화면이 실수로 통과시켜도
         서버가 거절하고, 서버가 느슨해져도 화면이 안 보냅니다. */
      healthConsent: o.healthConsent ? HEALTH_CONSENT_VERSION : null
    } }).then(function (r) {
      cfg.token = r.token; cfg.handle = r.user.handle; disconnected = false; saveCfg(cfg);
      emit();
      return pull().then(function () { return r; });
    });
  }

  function signIn(o) {
    return api('/auth/signin', { method: 'POST', body: {
      handle: o.handle, password: o.password
    } }).then(function (r) {
      cfg.token = r.token; cfg.handle = r.user.handle; disconnected = false; saveCfg(cfg);
      emit();
      return pull().then(function () { return r; });
    });
  }

  /**
   * 로그아웃.
   *
   * @returns {Promise<{unsent:number}>} 끝내 못 보낸 작업 개수
   *
   * **나가기 전에 먼저 보냅니다.** 예전에는 큐를 통째로 버렸습니다.
   * 오프라인에서 공유를 끄고 로그아웃하면 그 끄기가 사라졌고, 다시
   * 로그인하면 pull 이 서버 값(= 켜진 채)으로 거울을 덮었습니다.
   * "껐는데 계속 나간다" 는 이 앱에서 제일 나쁜 고장입니다.
   *
   * 그래도 못 보낸 것이 남을 수 있습니다(인터넷이 없을 때). 그때는
   * 개수를 돌려주고, 화면이 그 사실을 말합니다 — 조용히 버리지 않습니다.
   */
  function signOut() {
    var first = cfg.token && cfg.queue.length
      ? flush().catch(function () {})
      : Promise.resolve();
    return first.then(function () {
      var unsent = cfg.queue.length;
      var done = cfg.token ? api('/auth/signout', { method: 'POST' }).catch(function () {})
                           : Promise.resolve();
      return done.then(function () {
        cfg.token = null; cfg.queue = []; disconnected = false; saveCfg(cfg);
        // 로컬 거울도 비웁니다. 남의 기기에 내 친구 목록을 남기지 않습니다.
        if (global.MB_BACKEND) global.MB_BACKEND.reset();
        emit();
        return { unsent: unsent };
      });
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
    /* avatar 는 undefined 면 아예 안 보냅니다 — 서버에서 "사진 얘기 안 함"
       과 "사진 지워 달라(null)" 를 구분하기 때문입니다. */
    updateMe:     function (a) {
      var body = {};
      if (a.displayName !== undefined) body.displayName = a.displayName;
      if (a.avatar !== undefined) body.avatar = a.avatar;
      return api('/me', { method: 'PATCH', body: body });
    },
    snapshot:     function (a) { return api('/snapshots', { method: 'POST', body: { weekStart: a.weekStart, payload: a.payload } }); },
    /* 기록 전체를 내 계정에 — 앱으로 옮겨 로그인하면 그대로 따라옵니다. */
    syncState:    function (a) {
      return api('/sync/push', { method: 'POST', body: { records: [
        { kind: 'state', id: 'main', updatedAt: a.updatedAt, payload: a.payload } ] } });
    }
  };

  var QUEUE_MAX = 500;

  function enqueue(op, args) {
    if (!cfg.token) {
      /* 한 번도 로그인한 적이 없으면 서버에 보낼 것이 정말로 없습니다 —
         친구도 없고 이 앱은 그대로 혼자 씁니다. 조용히 돌아가는 게 맞습니다.

         하지만 **로그인했었는데 토큰이 죽은** 경우는 다릅니다. 방금 한
         일이 로컬 거울에만 남고 서버에는 영영 안 가며, 다음 pull 이
         그것마저 덮어씁니다. 조용히 넘기면 안 됩니다. */
      if (cfg.handle) {
        disconnected = true;
        lastError = '이 기기가 서버에서 끊겼습니다 — 다시 로그인해야 반영됩니다';
        emit();
      }
      return;
    }
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
    /* 기록 전체도 마지막 것 하나만 — 서버는 같은 레코드를 덮어씁니다. */
    if (op === 'syncState') {
      for (var s2 = cfg.queue.length - 1; s2 >= 0; s2--) {
        if (cfg.queue[s2].op === 'syncState') cfg.queue.splice(s2, 1);
      }
    }

    cfg.queue.push({ op: op, args: args, at: Date.now() });

    /* 그래도 넘치면, 버리는 순서를 정합니다.
       스냅샷은 다음 저장 때 다시 만들어지지만 친구 수락은 안 그렇습니다. */
    while (cfg.queue.length > QUEUE_MAX) {
      var drop = -1;
      for (var k = 0; k < cfg.queue.length - 1; k++) {
        if (cfg.queue[k].op === 'snapshot' || cfg.queue[k].op === 'syncState') { drop = k; break; }
      }
      cfg.queue.splice(drop >= 0 ? drop : 0, 1);
    }
    saveCfg(cfg); emit();
    flush();
  }

  /** 다시 보내면 될 수도 있는 거절 — 큐에서 버리면 안 됩니다 */
  function RETRYABLE(st) { return st === 429 || st === 408; }

  function flush() {
    if (flushing || !cfg.token || !cfg.queue.length) return Promise.resolve();
    flushing = true;
    /* 아래 then/catch 사슬이 어떤 이유로든 안 끝나면 이 플래그가 잠깁니다.
       요청에 시간 제한을 붙였으니 보통은 안 그렇지만, 잠기는 쪽의 대가가
       "그 뒤로 아무것도 안 올라가는데 화면은 곧 보낸다고 말함" 이라
       한 겹 더 둡니다. */
    var unlock = null;
    try {
      unlock = global.setTimeout(function () {
        if (flushing) { flushing = false; lastError = '서버가 대답하지 않습니다'; emit(); scheduleRetry(); }
      }, 60000);
    } catch (e) { unlock = null; }
    var failed = [];

    /* 보낸 작업만 정확히 집어서 뺍니다.
     *
     * 예전엔 성공하면 shift() 로 맨 앞을 뺐습니다. 그런데 요청이 날아가
     * 있는 동안에도 enqueue() 가 큐를 건드립니다 — 같은 주 스냅샷 겹침
     * 제거가 **지금 보내고 있는 맨 앞 작업**을 splice 로 빼 버립니다.
     * 그러면 응답이 온 뒤의 shift() 는 엉뚱한 작업을 지웁니다.
     *
     * 실제로 두 가지가 일어났습니다.
     *   (가) 일정을 네 칸 연달아 누르면 서버에는 첫 번째 것만 남았습니다.
     *        1번이 날아가 있는 동안 2·3·4번이 서로를 지우며 쌓이고,
     *        1번이 도착하자 shift() 가 마지막에 남은 4번을 지웠습니다.
     *        화면은 4일이라고 하는데 친구 화면에는 1일이 떴습니다.
     *   (나) 큐에 친구 수락이나 공유 끄기가 같이 있으면 그게 지워졌습니다.
     *        "껐는데 계속 나간다" 는 이 앱에서 제일 나쁜 고장입니다.
     *
     * 자리(index)가 아니라 그 작업 자체로 지웁니다. 중간에 누가 큐를
     * 어떻게 흔들어도 내가 보낸 것만 빠집니다. */
    function drop(job) {
      var i = cfg.queue.indexOf(job);
      if (i >= 0) cfg.queue.splice(i, 1);
      saveCfg(cfg);
    }

    function step() {
      if (!cfg.queue.length) return Promise.resolve();
      var job = cfg.queue[0];
      return OPS[job.op](job.args).then(function () {
        drop(job);
        retryMs = 2000;          // 한 번이라도 통했으면 간격을 되돌립니다
        return step();
      }).catch(function (e) {
        /* 4xx 는 "다시 보내도 같은 답" 이라 버렸습니다. 두 개는 아닙니다.
         *
         *   429  지금은 너무 잦다 — 조금 뒤엔 된다
         *   408  시간이 초과됐다 — 다시 보내면 된다
         *
         * 이 둘을 같이 버리는 바람에, 한도에 걸린 상태에서 공유를 끄면
         * 앱은 껐다고 하고 서버는 계속 보냈습니다. 프라이버시 스위치가
         * 조용히 안 먹는 것은 이 앱에서 제일 나쁜 종류의 고장입니다 —
         * 껐다고 믿는 사람은 다시 확인하지 않습니다. */
        if (RETRYABLE(e.status)) throw e;      // 큐에 남겨 두고 나중에 다시
        if (e.status && e.status >= 400 && e.status < 500) {
          // 서버가 거절했습니다. 다시 보내도 같은 답이 옵니다.
          drop(job);
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
      try { if (unlock) global.clearTimeout(unlock); } catch (e) {}
      flushing = false; emit();
      /* 큐가 안 비었으면 스스로 다시 시도합니다.
         예전엔 다시 보낼 계기가 "저장을 또 한다" 와 "온라인이 됐다"
         뿐이었습니다. 공유를 끄고 앱을 닫으면 그 두 가지가 안 일어나고,
         끄기가 서버에 영영 안 닿았습니다. */
      scheduleRetry();
      return pull();
    });
  }

  /* 2초 → 4초 → … → 5분, 성공하면 초기화. 화면은 status().pending 으로
     못 올린 개수를 이미 보여 주고 있으므로, 여기서는 조용히 재시도만 합니다. */
  var retryTimer = null, retryMs = 2000;
  var RETRY_MAX = 5 * 60 * 1000;
  function scheduleRetry() {
    if (retryTimer) return;
    if (!cfg.token || !cfg.queue.length) { retryMs = 2000; return; }
    try {
      retryTimer = global.setTimeout(function () {
        retryTimer = null;
        retryMs = Math.min(retryMs * 2, RETRY_MAX);
        flush();
      }, retryMs);
    } catch (e) { retryTimer = null; }
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
          /* 친구 소식은 여기서 계산합니다 — 서버가 준 것을 지난번 본 것과
             견주는 일이라, 받아오는 자리 말고는 할 데가 없습니다.
             새로 나가는 정보는 없습니다. */
          try {
            if (global.MB_NEWS) global.MB_NEWS.apply(snaps, accepted);
          } catch (e) {}
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
    probe();
    /* 앱을 열면 서버에서 받아 옵니다.
     *
     * 예전엔 flush() 만 불렀는데, flush() 는 보낼 것이 없으면 즉시
     * 돌아옵니다 — 그래서 보통은 pull() 이 아예 안 돌았습니다.
     * 친구가 수락했는지, 친구가 이번 주에 기록했는지가 앱을 몇 번을
     * 열어도 안 바뀌었습니다. 화면은 그 오래된 값을 확신을 갖고
     * 보여 주고 있었고요. */
    if (cfg.token) { flush(); pull(); }
    try {
      global.addEventListener('online', function () { flush(); pull(); });
      /* 폰에서는 앱을 껐다 켜는 게 아니라 다른 앱에 갔다 오는 것이
         보통입니다. 그때도 한 번 맞춰 옵니다 — 너무 잦지 않게
         1분 이상 지났을 때만. */
      global.document.addEventListener('visibilitychange', function () {
        if (global.document.visibilityState !== 'visible') return;
        if (!cfg.token) return;
        var last = lastPullAt ? Date.parse(lastPullAt) : 0;
        if (Date.now() - last > 60000) pull();
      });
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
   * @param {function(err, fields, res)} cb  res 는 서버 응답 전체
   *        (notInBody 같은 이유가 여기 들어 있습니다)
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
      if (cancelled) return;
      /* 응답 전체를 세 번째 인자로 같이 넘깁니다.
         fields 만 꺼내면 서버가 애써 구분해 준 "인바디 결과지로 보이지
         않습니다"(notInBody) 가 사라지고, 영수증을 찍은 사람이 "핵심 세
         칸을 읽지 못했습니다" 를 받아 같은 사진을 다시 찍게 됩니다. */
      cb(null, (r && r.fields) || {}, r || {});
    }).catch(function (e) {
      /* 취소해서 난 오류는 오류가 아닙니다. 여기서 안 걸러 내면
         "판독을 취소했습니다" 바로 뒤에 "판독에 실패했습니다" 가
         같이 뜹니다 — 사용자가 시킨 일을 실패라고 부르는 셈입니다. */
      if (cancelled) return;
      lastError = e.message; emit();
      cb(e);
    });

    /* 이 return 이 없었습니다.
     *
     * 거절 분기 셋은 전부 함수를 돌려주는데 정작 **업로드를 시작하는
     * 경로에만** return 이 없어서, 화면이 받아 둔 cancelOcr 은 언제나
     * undefined 였습니다. 취소 · 사진 바꾸기 · 사진 빼기 세 군데의
     * if (cancelOcr) 가 전부 빈 분기였고, 화면은 "판독을 취소했습니다"
     * 라고 말하면서 결과지 사진은 그대로 외부 판독 서비스로 올라가고
     * 서버의 하루 한도까지 깎았습니다. 바로 위 JSDoc 이 "부르면
     * 업로드를 실제로 멈춥니다" 라고 계약을 적어 둔 채로요. */
    return function cancel() {
      if (cancelled) return;
      cancelled = true;
      try { if (ctrl) ctrl.abort(); } catch (e) {}
    };
  }

  global.MB_SYNC = {
    status: status, onChange: onChange, configure: configure,
    deliveryMode: deliveryMode, deliveryNote: deliveryNote,
    signUp: signUp, signIn: signIn, signOut: signOut, changePassword: changePassword,
    recover: recover, newRecoveryCode: newRecoveryCode,
    HEALTH_CONSENT_VERSION: HEALTH_CONSENT_VERSION,
    signOutEverywhere: function () { return api('/auth/signout-all', { method: 'POST' }); },
    deleteAccount: function () { return api('/me', { method: 'DELETE' }); },
    enqueue: enqueue, flush: flush, pull: pull, boot: boot, probe: probe,
    sendRequest: sendRequest,
    canOcr: canOcr, setOcr: setOcr, ocr: ocr,
    _api: api
  };
})(window);
