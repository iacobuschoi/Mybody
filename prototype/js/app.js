/* =============================================================================
 * app.js — 앱 셸 · 라우터 · 화면 레지스트리
 *
 * 화면 번호 (컨테이너는 전역 연번)
 *   P00 앱 셸      P01 온보딩     P02 홈         P03 인바디 넣기
 *   P04 판독 검수  P05 목표 설정  P06 강도 선택   P07 플랜
 *   P08 체크인     P09 추이       P10 히스토리    P11 스캔 상세
 *   P12 설정       P13 ID 인덱스  P14 계정        P15 친구
 *   P16 친구 상세  P18 식단       P19 음식 검색   P20 음식 사진
 *   P21 음식 상세
 *
 *   P13 은 만드는 사람용입니다 — 배포 빌드에서는 등록되지 않습니다.
 *   P17 은 회수됐습니다. 공유 설정은 화면이 아니라 모달(M27/M28)입니다.
 *   **다시 쓰지 마세요** — 번호를 재사용하면 그 번호에 달아 둔 피드백
 *   메모가 엉뚱한 곳을 가리키게 됩니다.
 *
 * 이 목록은 P13 에서 멈춰 있던 적이 있습니다. 그 사이에 P14~P16 과
 * P18~P21 이 생겼는데 주석은 그대로여서, 새 화면을 설계하던 초안 두
 * 개가 이미 쓰는 번호를 골랐습니다. 화면을 추가하면 여기도 고치세요.
 * ========================================================================== */
(function (global) {
  'use strict';
  var UI = global.MB_UI, S = global.MB_STORE;

  var screens = {};       // id -> {title, label, render, noChrome, hideTabs}
  var current = null;
  var params = {};
  var history = [];

  var TABS = [
    { uid: 'P00-N01', ico: '🏠', label: '홈',    to: 'P02' },
    { uid: 'P00-N02', ico: '🍚', label: '식단',  to: 'P18' },
    { uid: 'P00-N03', ico: '📋', label: '플랜',  to: 'P07' },
    { uid: 'P00-N04', ico: '📈', label: '추이',  to: 'P09' },
    // 설정은 앱바 톱니(P00-B03)로 옮겼습니다. 다섯 칸을 유지하는 이유:
    // 여섯 번째를 넣으면 탭바가 두 줄로 접혀 높이가 두 배가 되고,
    // iOS 는 5개를 넘기면 뒤쪽을 More 로 숨깁니다.
    // 번호는 N05 가 아니라 N06 입니다 — 사용자가 N05 에 달아둔 피드백 메모가
    // 조용히 엉뚱한 요소를 가리키면 안 됩니다.
    { uid: 'P00-N06', ico: '👥', label: '친구',  to: 'P15' }
  ];

  function register(id, def) { screens[id] = def; }

  /* 받은 친구 요청이 있으면 친구 탭에 점을 켭니다.
     지금까지 받은 요청은 설정 안 카드에만 떠서, 설정에 들어가 보기 전까지
     몰랐고 상대는 무한정 기다렸습니다.

     반드시 자체 try/catch 로 감쌉니다 — listFriends() 의 첫 줄이
     requireUser() 라 로그아웃 상태에서 던지는데, 그게 신규 설치의 기본
     상태입니다. 여기서 던지면 render() 뒷부분(앱바 제목·뒤로가기·탭 활성화·
     고유번호 배지 스캔)이 모든 화면에서 멈춥니다.

     점은 두 가지에만 켭니다 — 받은 친구 요청(내가 답해야 하는 일)과
     친구 소식(친구가 운동했다는 좋은 소식). 둘 다 숫자를 안 붙입니다.
     숫자를 붙이면 점수표가 되고, 그 순간 내가 이번 주에 몇 번 갔는지와
     나란히 놓입니다.

     그리고 **안 한 것에는 절대 안 켭니다.** 친구가 이번 주에 운동을
     안 했다는 것은 점이 되지 않습니다 — 소식은 늘어난 것에서만 나오게
     만들어져 있습니다(news.js). 내 몸 데이터를 보여달라는 요청에 빨간
     점을 다는 것도 마찬가지로 안 합니다. 이 구분이 압박의 상한선입니다. */
  function updateTabDot() {
    var n = 0;
    try {
      var BE = global.MB_BACKEND;
      if (BE && BE.currentUser()) n = BE.listFriends().incoming.length;
      if (global.MB_NEWS) n += global.MB_NEWS.unread();
    } catch (e) { n = 0; }
    var el = document.querySelector('.tabbar__item[data-to="P15"]');
    if (el) el.classList.toggle('has-dot', n > 0);
  }

  /* --- 셸 ---------------------------------------------------------------- */
  function buildShell() {
    var app = UI.h('div.app', { uid: 'P00', uidLabel: '앱 셸' }, [
      UI.h('header.appbar', { uid: 'P00-C01', uidLabel: '상단 앱바' }, [
        UI.h('button.appbar__back', { id: 'appbar-back', text: '‹', 'aria-label': '뒤로',
          uid: 'P00-B01', uidLabel: '뒤로가기', onClick: back }),
        UI.h('div', { style: { flex: '1', minWidth: '0' } }, [
          UI.h('div.appbar__title', { id: 'appbar-title', text: 'Mybody' }),
          UI.h('div.appbar__sub', { id: 'appbar-sub' })
        ]),
        UI.h('div.appbar__actions', [
          UI.h('button.btn.btn--ghost.btn--sm', { text: '⚙️', uid: 'P00-B03', uidLabel: '설정',
            title: '설정', 'aria-label': '설정', onClick: function () { go('P12'); } }),
          UI.h('button.btn.btn--ghost.btn--sm', { text: '?', uid: 'P00-B02', uidLabel: '단축키 도움말',
            title: '단축키 (?)', onClick: function () { global.MB_UID.showHelp(); } })
        ])
      ]),
      UI.h('main.main', { id: 'main' }),
      UI.h('nav.tabbar', { uid: 'P00-C02', uidLabel: '하단 탭바' },
        TABS.map(function (t) {
          return UI.h('button.tabbar__item', {
            'data-to': t.to, uid: t.uid, uidLabel: t.label,
            onClick: function () { go(t.to); }
          }, [UI.h('span.ico', { text: t.ico }), UI.h('span', { text: t.label })]);
        }))
    ]);
    document.body.appendChild(app);
    document.body.appendChild(UI.h('div', { id: 'toast-host' }));
  }

  /* --- 나가기 전에 물어보기 ------------------------------------------------
   *
   * 검수 화면에서 숫자를 고치다가 탭을 누르면 고친 게 전부 사라졌습니다.
   * 경고도 없었습니다. M23 "저장하지 않고 나갈까요?" 모달이 만들어져
   * 있었는데 부르는 곳이 한 군데도 없었습니다.
   *
   * 화면마다 go() 호출을 감싸는 방법도 있지만, 나가는 길이 탭바 ·
   * 뒤로가기 · 화면 안 버튼 · 주소 해시로 여러 개라 한 군데만 빠져도
   * 거기로 나갈 때 조용히 사라집니다. 그래서 라우터에 둡니다 —
   * 빠뜨릴 수가 없는 자리입니다.
   *
   * 화면은 render() 안에서 A.confirmLeave(fn) 을 부르고, fn 은 "지금
   * 나가면 잃을 게 있나" 를 돌려줍니다. 화면이 바뀌면 자동으로 풀립니다.
   */
  var leaveGuard = null;

  function confirmLeave(fn) { leaveGuard = fn; }

  function mayLeave(next) {
    if (!leaveGuard) return true;
    var dirty = false;
    try { dirty = !!leaveGuard(); } catch (e) { dirty = false; }
    if (!dirty) return true;
    if (global.MB_MODALS && global.MB_MODALS.unsaved) {
      global.MB_MODALS.unsaved(function () {
        leaveGuard = null;      // 사용자가 버리기로 했습니다
        next();
      });
      return false;
    }
    return true;                // 모달이 없으면 막지 않습니다 (막다른 길 방지)
  }

  /* --- 라우팅 ------------------------------------------------------------- */
  function go(id, p, opts) {
    if (!screens[id]) { console.warn('알 수 없는 화면:', id); return; }
    if (current === id) { leaveGuard = null; }
    else if (!mayLeave(function () { leaveGuard = null; go(id, p, opts); })) return;
    leaveGuard = null;
    if (current && current !== id && !(opts && opts.replace)) history.push({ id: current, params: params });
    current = id;
    params = p || {};
    render();
    window.scrollTo({ top: 0, behavior: 'instant' in window ? 'instant' : 'auto' });
  }

  function back() {
    if (!mayLeave(function () { leaveGuard = null; back(); })) return;
    leaveGuard = null;
    var prev = history.pop();
    if (prev) { current = prev.id; params = prev.params; render(); }
    else { current = 'P02'; params = {}; render(); }
  }

  function render() {
    var def = screens[current];
    if (!def) {
      var m0 = document.getElementById('main');
      UI.clear(m0);
      m0.appendChild(UI.h('div.note.note--warn',
        { text: '화면 ' + current + ' 이(가) 아직 등록되지 않았습니다.' }));
      return;
    }
    var main = document.getElementById('main');
    UI.clear(main);

    var wrap = UI.h('div.screen.is-active', {
      uid: current,
      uidLabel: def.label || (typeof def.title === 'string' ? def.title : current)
    });
    try {
      def.render(wrap, { params: params, go: go, back: back, state: S.get() });
    } catch (e) {
      console.error(e);
      wrap.appendChild(UI.h('div.note.note--bad', { text: '화면 렌더링 오류: ' + e.message }));
    }
    main.appendChild(wrap);

    /* title 이 함수면 params 로 부릅니다. 화면이 레지스트리 객체의 title 을
       직접 덮어쓰던 방식은, 없는 친구로 들어갔을 때 앱바에 이전 친구 이름이
       남는 버그를 만들었습니다. */
    try {
      var t = (typeof def.title === 'function') ? def.title(params) : def.title;
      document.getElementById('appbar-title').textContent = t || 'Mybody';
    } catch (e) { document.getElementById('appbar-title').textContent = 'Mybody'; }
    document.getElementById('appbar-sub').textContent = def.sub || '';
    document.getElementById('appbar-back').style.visibility = history.length ? 'visible' : 'hidden';

    var tabs = document.querySelectorAll('.tabbar__item');
    for (var i = 0; i < tabs.length; i++) {
      tabs[i].classList.toggle('is-active', tabs[i].getAttribute('data-to') === current);
    }
    document.querySelector('.tabbar').style.display = def.hideTabs ? 'none' : '';

    updateTabDot();
    global.MB_UID.scan(main);
  }

  function refresh() { render(); }

  /* --- 가드: 데이터 없을 때 안내 -------------------------------------------- */
  /* 앱 셸이 화면 대신 그려 주는 빈 상태들.
   *
   * 번호를 -S01 / -B90 으로 붙이고 있었습니다. 그런데 그건 화면들이
   * 자기 빈 상태에 흔히 쓰는 번호라 부딪혔습니다 — P06 은 여기서
   * 만드는 "스캔 없음"(P06-S01, P06-B90)과 자기가 만드는 "목표
   * 없음"(같은 번호)을 둘 다 갖고 있었습니다. 같은 번호가 두 가지를
   * 가리키면 거기 달아 둔 피드백 메모가 엉뚱한 버튼으로 갑니다.
   *
   * 그래서 90번대로 옮깁니다 — "앱 셸이 만든 것" 자리입니다.
   * 화면이 손으로 90번대를 고르는 일은 없습니다.
   * tools/uid-registry.js 가 그 규칙을 지킵니다. */
  function requireScan(wrap, ctx, uidPrefix) {
    var scan = S.latestScan();
    if (scan) return scan;
    wrap.appendChild(UI.h('div.empty', { uid: uidPrefix + '-S90', uidLabel: '스캔 없음 빈 상태' }, [
      UI.h('div.empty__ico', { text: '📄' }),
      UI.h('div.empty__t', { text: '아직 인바디 기록이 없습니다' }),
      UI.h('div.empty__d', { text: '결과지 사진을 올리면 여기서부터 시작됩니다.' }),
      UI.h('button.btn.btn--primary', { text: '인바디 올리기', uid: uidPrefix + '-B90',
        uidLabel: '인바디 올리기', onClick: function () { go('P03'); } })
    ]));
    return null;
  }

  function requirePlan(wrap, ctx, uidPrefix) {
    var st = S.get();
    if (st.plan) return st.plan;
    wrap.appendChild(UI.h('div.empty', { uid: uidPrefix + '-S91', uidLabel: '플랜 없음 빈 상태' }, [
      UI.h('div.empty__ico', { text: '🗺️' }),
      UI.h('div.empty__t', { text: '아직 플랜이 없습니다' }),
      UI.h('div.empty__d', { text: '목표를 정하고 강도를 고르면 플랜이 만들어집니다.' }),
      UI.h('button.btn.btn--primary', { text: '목표 설정하러 가기', uid: uidPrefix + '-B91',
        uidLabel: '목표 설정하러 가기', onClick: function () { go('P05'); } })
    ]));
    return null;
  }

  /* --- 부팅 --------------------------------------------------------------- */
  function boot() {
    // 서버가 설정돼 있으면 붙습니다. 안 돼 있으면 로컬만으로 그대로 동작합니다.
    try { if (global.MB_SYNC) global.MB_SYNC.boot(); } catch (e) {}

    /* 브라우저는 "깔 수 있다" 고 딱 한 번 말합니다 (beforeinstallprompt).
       그 때 안 잡아 두면 영영 못 띄웁니다 — 설정 화면이 열릴 때는 이미
       지나간 뒤입니다. 그래서 여기서 받아 두고 설정이 꺼내 씁니다. */
    global.MB_INSTALL = global.MB_INSTALL || { prompt: null };
    try {
      global.addEventListener('beforeinstallprompt', function (e) {
        e.preventDefault();               // 브라우저 기본 배너 대신 우리 버튼으로
        global.MB_INSTALL.prompt = e;
      });
      global.addEventListener('appinstalled', function () {
        global.MB_INSTALL.prompt = null;
      });
    } catch (e) {}
    S.load();

    /* 웹 주소로 처음 들어온 사람에게는 **앱 받는 법부터** 보여 줍니다.
     *
     * 이 앱은 브라우저에서도 그대로 돌아서, 친구가 링크를 열면 그냥
     * 쓰기 시작하고 앱으로 깔 수 있다는 걸 영영 모릅니다. 아이폰은
     * 깔아야만 알림이 오는데 그것도 모른 채 지나갑니다.
     *
     * 홈 화면 아이콘으로 연 경우(standalone), 매니페스트가 붙인 ?app=1
     * 로 들어온 경우, 그리고 "브라우저에서 쓰기" 를 한 번 고른 경우에는
     * 지나갑니다 — 한 번 고른 사람에게 같은 벽을 다시 세우지 않습니다. */
    if (global.MB_GATE && global.MB_GATE.needed()) {
      var gateRoot = document.createElement('div');
      gateRoot.id = 'gate';
      document.body.appendChild(gateRoot);
      global.MB_GATE.render(gateRoot, function () {
        gateRoot.remove();
        bootApp();
      });
      /* 관문에도 번호를 붙입니다 — 여기서 막힌 사람이 어디가 막혔는지
         말할 수 있어야 합니다. */
      try { global.MB_UID.init(); } catch (e) {}
      return;
    }
    bootApp();
  }

  function bootApp() {
    buildShell();
    global.MB_UID.init();

    var st = S.get();
    var startAt = !st.onboarded ? 'P01' : (st.scans.length ? 'P02' : 'P03');
    if (!screens[startAt]) startAt = Object.keys(screens)[0] || 'P02';
    var hash = location.hash.slice(1);
    if (hash) {
      var info = global.MB_UID.parseUid(hash);
      if (screens[info.container]) startAt = info.container;
    }
    current = startAt;
    render();
    if (hash) setTimeout(function () { global.MB_UID.gotoUid(hash); }, 120);
    if (st.onboarded && !st.disclaimerAccepted && global.MB_MODALS) global.MB_MODALS.disclaimer();
  }

  global.MB_APP = {
    register: register, go: go, back: back, refresh: refresh, boot: boot,
    confirmLeave: confirmLeave,
    requireScan: requireScan, requirePlan: requirePlan,
    get current() { return current; },
    get params() { return params; },
    /* 등록된 화면 목록. 검증 도구(tools/test-interactions.js)가 "이 버튼이
       보내는 곳이 실제로 존재하는가" 를 묻는 데 씁니다. 읽기 전용 사본을
       주는 이유는 밖에서 screens 를 건드려 화면을 지우는 일이 없게 하려는
       것입니다. */
    get screenIds() { return Object.keys(screens); },
    TABS: TABS
  };
})(window);
