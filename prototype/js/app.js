/* =============================================================================
 * app.js — 앱 셸 · 라우터 · 화면 레지스트리
 *
 * 화면 번호 (컨테이너는 전역 연번)
 *   P00 앱 셸      P01 온보딩     P02 홈        P03 인바디 업로드
 *   P04 판독 검수  P05 목표 설정  P06 강도 선택  P07 플랜
 *   P08 체크인     P09 추이       P10 히스토리   P11 스캔 상세
 *   P12 설정       P13 ID 인덱스
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

     점은 받은 친구 요청(관계)에만 켭니다. 내 몸 데이터를 보여달라는 요청에
     빨간 점을 다는 건 압박입니다. 이 구분이 압박의 상한선입니다. */
  function updateTabDot() {
    var n = 0;
    try {
      var BE = global.MB_BACKEND;
      if (BE && BE.currentUser()) n = BE.listFriends().incoming.length;
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

  /* --- 라우팅 ------------------------------------------------------------- */
  function go(id, p, opts) {
    if (!screens[id]) { console.warn('알 수 없는 화면:', id); return; }
    if (current && current !== id && !(opts && opts.replace)) history.push({ id: current, params: params });
    current = id;
    params = p || {};
    render();
    window.scrollTo({ top: 0, behavior: 'instant' in window ? 'instant' : 'auto' });
  }

  function back() {
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
  function requireScan(wrap, ctx, uidPrefix) {
    var scan = S.latestScan();
    if (scan) return scan;
    wrap.appendChild(UI.h('div.empty', { uid: uidPrefix + '-S01', uidLabel: '스캔 없음 빈 상태' }, [
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
    wrap.appendChild(UI.h('div.empty', { uid: uidPrefix + '-S02', uidLabel: '플랜 없음 빈 상태' }, [
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
    S.load();
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
    requireScan: requireScan, requirePlan: requirePlan,
    get current() { return current; },
    get params() { return params; },
    TABS: TABS
  };
})(window);
