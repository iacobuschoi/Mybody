/* =============================================================================
 * uid.js — 고유번호 배지 + 피드백 시스템
 *
 * 오너가 "P05-B02 버튼 문구 이상함" 하고 던지면 바로 찾을 수 있게 하는 게 목적.
 *
 * ID 규칙 (2세그먼트 고정, 3단 중첩 금지)
 *   P## / M## / A##      컨테이너·전역 컴포넌트 (화면 / 모달 / 토스트) — 전역 연번
 *   {컨테이너}-{종류}##   리프 — 소속 컨테이너 안에서 01부터
 *     B 버튼 · F 입력 · C 카드/섹션 · T 탭 · N 내비 · L 리스트 · G 차트 · S 상태
 *   리스트 행은 런타임이 #n 을 붙인다 (레지스트리에는 없음)
 *
 * 조작
 *   배지 클릭          ID + 라벨 클립보드 복사
 *   Shift + 배지 클릭   그 ID에 메모 달기
 *   Alt + 배지 클릭     딥링크(#P05-B02) 복사
 *   i 키               배지 전체 켜기/끄기
 *   f 키               피드백 모드 (아무 요소나 클릭 → 메모)
 *   ? 키               단축키 도움말
 * ========================================================================== */
(function (global) {
  'use strict';

  var LS_NOTES = 'mybody.feedback.v1';
  var LS_PREFS = 'mybody.uidprefs.v1';

  var TYPE_OF = {
    P: '화면', M: '팝업', A: '토스트', B: '버튼', F: '입력',
    C: '카드', T: '탭', N: '내비', L: '리스트', G: '차트', S: '상태'
  };

  /* 배지는 개발 빌드에서만 기본으로 켜집니다.
     배포 빌드에서 모든 버튼에 'P02-B17' 같은 딱지가 붙어 있으면, 쓰는
     사람에게는 그냥 미완성 앱으로 보입니다. 이건 저한테 어디가 이상한지
     말해 주시라고 만든 도구지 제품의 일부가 아닙니다.
     끄더라도 코드는 남습니다 — data-uid 속성은 그대로라서 검증 도구는
     배포 빌드에서도 똑같이 돌아갑니다. */
  var TOOLS = !!(global.MB_BUILD && global.MB_BUILD.tools);
  var state = {
    on: TOOLS,
    feedbackMode: false,
    notes: [],
    prefs: { badgeSize: 9, showLabels: false }
  };

  /* --- 저장소 ------------------------------------------------------------ */
  function loadNotes() {
    try { state.notes = JSON.parse(localStorage.getItem(LS_NOTES) || '[]'); }
    catch (e) { state.notes = []; }
  }
  function saveNotes() {
    try { localStorage.setItem(LS_NOTES, JSON.stringify(state.notes)); } catch (e) {}
    refreshNoteCounts();
  }
  function loadPrefs() {
    try {
      var p = JSON.parse(localStorage.getItem(LS_PREFS) || 'null');
      if (p) { state.prefs = Object.assign(state.prefs, p); if (typeof p.on === 'boolean') state.on = p.on; }
    } catch (e) {}
  }
  function savePrefs() {
    try { localStorage.setItem(LS_PREFS, JSON.stringify(Object.assign({ on: state.on }, state.prefs))); } catch (e) {}
  }

  /* --- ID 파싱 ----------------------------------------------------------- */
  function parseUid(uid) {
    var base = String(uid).split('#')[0];
    var seg = base.split('-');
    var container = seg[0];
    var leaf = seg[1] || null;
    var kind = leaf ? leaf.charAt(0) : container.charAt(0);
    return { uid: uid, base: base, container: container, leaf: leaf, kind: kind, kindLabel: TYPE_OF[kind] || '요소' };
  }

  /* --- 배지 주입 --------------------------------------------------------- */
  function isContainerKind(kind) { return 'PMCLG'.indexOf(kind) >= 0; }

  function ensureAnchor(el) {
    var pos = getComputedStyle(el).position;
    if (pos === 'static') el.classList.add('uid-anchored');
  }

  function depthOf(el) {
    var d = 0, p = el.parentElement;
    while (p) { if (p.hasAttribute && p.hasAttribute('data-uid')) d++; p = p.parentElement; }
    return d;
  }

  function attachBadge(el) {
    /* 배포 빌드에서는 배지를 아예 만들지 않습니다.
       처음엔 CSS 로 숨기려 했는데, 배포본에서 uid.css 를 빼고 나니
       숨길 것이 없어져서 배지 14개가 스타일 없이 그대로 떴습니다.
       "만들고 숨기기" 는 숨기는 쪽이 하나만 빠져도 드러납니다.
       data-uid 속성 자체는 그대로 둡니다 — 검증 도구가 배포 빌드에서도
       똑같이 돌아야 하니까요. */
    if (!TOOLS) return null;
    if (el.__uidBadge && el.__uidBadge.isConnected) return el.__uidBadge;
    var uid = el.getAttribute('data-uid');
    if (!uid) return null;
    var info = parseUid(uid);
    var label = el.getAttribute('data-uid-label') || guessLabel(el);

    var host = el;
    // input/img/canvas 같은 replaced element는 감싸서 배지를 래퍼에 단다
    if (/^(INPUT|IMG|CANVAS|SELECT|PROGRESS|TEXTAREA)$/.test(el.tagName)) {
      var wrap = el.parentElement;
      if (!wrap || !wrap.classList.contains('uid-wrap')) {
        wrap = document.createElement('span');
        wrap.className = 'uid-wrap';
        if (getComputedStyle(el).display === 'block' || el.tagName === 'TEXTAREA') wrap.style.display = 'block';
        el.parentNode.insertBefore(wrap, el);
        wrap.appendChild(el);
      }
      host = wrap;
    }
    ensureAnchor(host);

    var badge = document.createElement('span');
    badge.className = 'uid-badge';
    badge.setAttribute('data-uid-for', uid);
    badge.setAttribute('data-uid-kind', info.kind);
    badge.setAttribute('data-uid-pos', isContainerKind(info.kind) ? 'tl' : 'tr');
    badge.style.setProperty('--uid-depth', depthOf(el));
    badge.title = uid + (label ? ' · ' + label : '') + '\n클릭: ID 복사 · Shift+클릭: 메모 · Alt+클릭: 링크 복사';
    badge.innerHTML =
      '<span class="uid-badge__id"></span>' +
      '<span class="uid-badge__label"></span>' +
      '<span class="uid-badge__count"></span>';
    badge.querySelector('.uid-badge__id').textContent = uid;
    badge.querySelector('.uid-badge__label').textContent = label || '';
    badge.addEventListener('click', onBadgeClick);

    host.appendChild(badge);
    el.__uidBadge = badge;
    el.__uidLabel = label;
    return badge;
  }

  function guessLabel(el) {
    var t = (el.getAttribute('aria-label') || el.textContent || '').trim().replace(/\s+/g, ' ');
    return t.length > 20 ? t.slice(0, 20) + '…' : t;
  }

  /** 새로 그려진 DOM에 배지를 붙인다 (화면 전환마다 호출) */
  function scan(root) {
    var scope = root || document;
    var els = scope.querySelectorAll('[data-uid]');
    for (var i = 0; i < els.length; i++) attachBadge(els[i]);
    refreshNoteCounts();
    applyVisibility();
    return els.length;
  }

  /* --- 배지 상호작용 ------------------------------------------------------ */
  function onBadgeClick(ev) {
    ev.preventDefault();
    ev.stopPropagation();
    var uid = this.getAttribute('data-uid-for');
    var el = document.querySelector('[data-uid="' + cssEscape(uid) + '"]');
    var label = (el && el.__uidLabel) || '';
    if (ev.shiftKey) { openNoteDialog(uid, label); return; }
    if (ev.altKey) { copy(location.origin + location.pathname + '#' + uid); toast('딥링크 복사됨 · #' + uid); return; }
    copy(uid + (label ? ' · ' + label : ''));
    toast('복사됨 · ' + uid);
    flash(el);
  }

  function cssEscape(s) { return String(s).replace(/"/g, '\\"'); }

  function flash(el) {
    if (!el) return;
    el.classList.remove('uid-flash');
    void el.offsetWidth;
    el.classList.add('uid-flash');
    setTimeout(function () { el.classList.remove('uid-flash'); }, 1600);
  }

  function copy(text) {
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text).catch(function () { fallbackCopy(text); });
    } else { fallbackCopy(text); }
  }
  function fallbackCopy(text) {
    var ta = document.createElement('textarea');
    ta.value = text; ta.style.position = 'fixed'; ta.style.opacity = '0';
    document.body.appendChild(ta); ta.select();
    try { document.execCommand('copy'); } catch (e) {}
    document.body.removeChild(ta);
  }

  /* --- 메모 -------------------------------------------------------------- */
  function notesFor(uid) {
    return state.notes.filter(function (n) { return n.uid === uid; });
  }
  function refreshNoteCounts() {
    var badges = document.querySelectorAll('.uid-badge');
    for (var i = 0; i < badges.length; i++) {
      var uid = badges[i].getAttribute('data-uid-for');
      var c = notesFor(uid).length;
      var span = badges[i].querySelector('.uid-badge__count');
      if (span) span.textContent = c ? '●' + c : '';
      badges[i].classList.toggle('has-note', c > 0);
    }
    [document.getElementById('uid-note-count'), document.getElementById('uid-note-count2')]
      .forEach(function (b) { if (b) b.textContent = state.notes.length ? String(state.notes.length) : ''; });
  }

  function openNoteDialog(uid, label) {
    var existing = notesFor(uid);
    var wrap = document.createElement('div');
    wrap.className = 'uid-note-backdrop';
    wrap.innerHTML =
      '<div class="uid-note" role="dialog" aria-modal="true">' +
        '<div class="uid-note__head">' +
          '<span class="uid-note__id"></span>' +
          '<span class="uid-note__label"></span>' +
        '</div>' +
        '<div class="uid-note__list"></div>' +
        '<textarea class="uid-note__input" rows="3" placeholder="여기가 왜 이상한지 한 줄로 적어주세요"></textarea>' +
        '<div class="uid-note__actions">' +
          '<button class="btn btn--ghost" data-act="cancel">취소</button>' +
          '<button class="btn btn--primary" data-act="save">저장</button>' +
        '</div>' +
      '</div>';
    wrap.querySelector('.uid-note__id').textContent = uid;
    wrap.querySelector('.uid-note__label').textContent = label || '';
    var list = wrap.querySelector('.uid-note__list');
    existing.forEach(function (n) {
      var row = document.createElement('div');
      row.className = 'uid-note__item';
      var txt = document.createElement('span');
      txt.textContent = n.text;
      var del = document.createElement('button');
      del.className = 'uid-note__del'; del.textContent = '×'; del.title = '삭제';
      del.addEventListener('click', function () {
        state.notes = state.notes.filter(function (x) { return x.id !== n.id; });
        saveNotes(); row.remove();
      });
      row.appendChild(txt); row.appendChild(del);
      list.appendChild(row);
    });

    function close() { wrap.remove(); document.removeEventListener('keydown', onKey); }
    function onKey(e) {
      if (e.key === 'Escape') close();
      if (e.key === 'Enter' && (e.metaKey || e.ctrlKey)) save();
    }
    function save() {
      var v = wrap.querySelector('.uid-note__input').value.trim();
      if (v) {
        state.notes.push({
          id: 'n' + state.notes.length + '_' + uid, uid: uid, label: label || '',
          screen: currentScreenId(), text: v, at: nowStamp()
        });
        saveNotes(); toast('메모 저장됨 · ' + uid);
      }
      close();
    }
    wrap.addEventListener('click', function (e) { if (e.target === wrap) close(); });
    wrap.querySelector('[data-act="cancel"]').addEventListener('click', close);
    wrap.querySelector('[data-act="save"]').addEventListener('click', save);
    document.addEventListener('keydown', onKey);
    document.body.appendChild(wrap);
    wrap.querySelector('.uid-note__input').focus();
  }

  function nowStamp() {
    var d = new Date();
    return d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate()) + ' ' +
           pad(d.getHours()) + ':' + pad(d.getMinutes());
  }
  function pad(n) { return String(n).padStart(2, '0'); }

  function currentScreenId() {
    var s = document.querySelector('.screen.is-active');
    return s ? s.getAttribute('data-uid') : '';
  }

  /* --- 피드백 모드 -------------------------------------------------------- */
  function setFeedbackMode(on) {
    state.feedbackMode = on;
    document.body.classList.toggle('uid-feedback-mode', on);
    var btn = document.getElementById('uid-fb-btn');
    if (btn) btn.classList.toggle('is-on', on);
    toast(on ? '피드백 모드 ON — 아무 요소나 클릭하면 메모창이 열립니다' : '피드백 모드 OFF');
  }

  function onCaptureClick(ev) {
    if (!state.feedbackMode) return;
    if (ev.target.closest('.uid-note-backdrop, .uid-dock, .uid-badge')) return;
    var el = ev.target.closest('[data-uid]');
    if (!el) return;
    ev.preventDefault(); ev.stopPropagation();
    openNoteDialog(el.getAttribute('data-uid'), el.__uidLabel || guessLabel(el));
  }

  /* --- 표시 토글 ---------------------------------------------------------- */
  function applyVisibility() {
    document.body.classList.toggle('uid-off', !state.on);
    document.documentElement.style.setProperty('--uid-badge-fs', state.prefs.badgeSize + 'px');
    var btn = document.getElementById('uid-toggle-btn');
    if (btn) { btn.classList.toggle('is-on', state.on); btn.textContent = state.on ? '번호 ON' : '번호 OFF'; }
  }
  function toggle(force) {
    state.on = (typeof force === 'boolean') ? force : !state.on;
    savePrefs(); applyVisibility();
  }

  /* --- 내보내기 ----------------------------------------------------------- */
  function exportMarkdown() {
    if (!state.notes.length) return '# Mybody 프로토타입 피드백\n\n(메모 없음)\n';
    var byScreen = {};
    state.notes.forEach(function (n) {
      var key = n.screen || '미분류';
      (byScreen[key] = byScreen[key] || []).push(n);
    });
    var out = ['# Mybody 프로토타입 피드백', '', '총 ' + state.notes.length + '건 · ' + nowStamp(), ''];
    Object.keys(byScreen).sort().forEach(function (scr) {
      var title = screenTitle(scr);
      out.push('## ' + scr + (title ? ' ' + title : '') + ' (' + byScreen[scr].length + '건)', '');
      byScreen[scr].forEach(function (n) {
        out.push('- **' + n.uid + '**' + (n.label ? ' (' + n.label + ')' : '') + ': ' + n.text);
      });
      out.push('');
    });
    return out.join('\n');
  }

  function screenTitle(uid) {
    var el = document.querySelector('[data-uid="' + cssEscape(uid) + '"]');
    return el ? (el.getAttribute('data-uid-label') || '') : '';
  }

  function exportAll() {
    var md = exportMarkdown();
    copy(md);
    toast('피드백 ' + state.notes.length + '건 복사됨 — 채팅에 붙여넣으세요');
    return md;
  }

  function clearAll() {
    if (!confirm('저장된 피드백 ' + state.notes.length + '건을 모두 지울까요?')) return;
    state.notes = []; saveNotes(); toast('피드백을 모두 지웠습니다');
  }

  /* --- 딥링크 ------------------------------------------------------------- */
  function gotoUid(uid) {
    var info = parseUid(uid);
    if (global.MB_APP && global.MB_APP.go) global.MB_APP.go(info.container);
    setTimeout(function () {
      var el = document.querySelector('[data-uid="' + cssEscape(uid) + '"]');
      if (el) { el.scrollIntoView({ block: 'center', behavior: 'smooth' }); flash(el); }
    }, 80);
  }

  /* --- 라이브 인덱스 ------------------------------------------------------- */
  function liveIndex() {
    var out = [];
    document.querySelectorAll('[data-uid]').forEach(function (el) {
      var uid = el.getAttribute('data-uid');
      var info = parseUid(uid);
      var screen = el.closest('.screen');
      var modal = el.closest('.modal');
      out.push({
        uid: uid, kind: info.kind, kindLabel: info.kindLabel,
        label: el.getAttribute('data-uid-label') || guessLabel(el),
        container: modal ? modal.getAttribute('data-uid')
                 : (screen ? screen.getAttribute('data-uid') : info.container),
        notes: notesFor(uid).length
      });
    });
    out.sort(function (a, b) { return a.uid.localeCompare(b.uid); });
    return out;
  }

  /* --- 토스트 ------------------------------------------------------------- */
  function toast(msg, uid) {
    var host = document.getElementById('toast-host');
    if (!host) return;
    var t = document.createElement('div');
    t.className = 'toast';
    if (uid) { t.setAttribute('data-uid', uid); }
    t.textContent = msg;
    host.appendChild(t);
    if (uid) attachBadge(t);
    setTimeout(function () { t.classList.add('is-out'); setTimeout(function () { t.remove(); }, 300); }, 2600);
  }

  /* --- 개발자 독 (화면 우하단) --------------------------------------------- */
  function buildDock() {
    var dock = document.createElement('div');
    dock.className = 'uid-dock is-collapsed';
    dock.innerHTML =
      '<button id="uid-dock-fab" class="uid-dock__fab" title="프로토타입 도구 (열기/닫기)">#<span id="uid-note-count2" class="uid-dock__count"></span></button>' +
      '<button id="uid-toggle-btn" class="uid-dock__btn is-on" title="배지 켜기/끄기 (i)">번호 ON</button>' +
      '<button id="uid-fb-btn" class="uid-dock__btn" title="피드백 모드 (f)">피드백<span id="uid-note-count" class="uid-dock__count"></span></button>' +
      '<button id="uid-idx-btn" class="uid-dock__btn" title="ID 인덱스">ID 목록</button>' +
      '<button id="uid-exp-btn" class="uid-dock__btn" title="피드백 전체 복사">내보내기</button>';
    document.body.appendChild(dock);
    dock.querySelector('#uid-toggle-btn').addEventListener('click', function () { toggle(); });
    dock.querySelector('#uid-fb-btn').addEventListener('click', function () { setFeedbackMode(!state.feedbackMode); });
    dock.querySelector('#uid-idx-btn').addEventListener('click', function () {
      if (global.MB_APP && global.MB_APP.go) global.MB_APP.go('P13');
    });
    dock.querySelector('#uid-exp-btn').addEventListener('click', exportAll);
    dock.querySelector('#uid-dock-fab').addEventListener('click', function () {
      dock.classList.toggle('is-collapsed');
    });
  }

  function onKeydown(e) {
    if (/^(INPUT|TEXTAREA|SELECT)$/.test(e.target.tagName)) return;
    if (e.metaKey || e.ctrlKey || e.altKey) return;
    // 배포 빌드에서는 i · f 가 아무것도 안 합니다. 쓰는 사람이 타이핑하다가
    // 개발자 도구를 켜게 되는 일이 없어야 합니다.
    if (!TOOLS) return;
    if (e.key === 'i' || e.key === 'ㅑ') { toggle(); }
    else if (e.key === 'f' || e.key === 'ㄹ') { setFeedbackMode(!state.feedbackMode); }
    else if (e.key === '?') { showHelp(); }
  }

  function showHelp() {
    var w = document.createElement('div');
    w.className = 'uid-note-backdrop';
    w.innerHTML =
      '<div class="uid-note" role="dialog">' +
      '<div class="uid-note__head"><span class="uid-note__id">단축키</span></div>' +
      '<div class="uid-help">' +
        '<div><kbd>i</kbd> 번호 배지 켜기/끄기</div>' +
        '<div><kbd>f</kbd> 피드백 모드 (아무 요소나 클릭 → 메모)</div>' +
        '<div><kbd>?</kbd> 이 도움말</div>' +
        '<hr>' +
        '<div><b>배지 클릭</b> ID 복사</div>' +
        '<div><b>Shift + 배지 클릭</b> 그 ID에 메모</div>' +
        '<div><b>Alt + 배지 클릭</b> 딥링크 복사</div>' +
        '<hr>' +
        '<div>주소창에 <code>#P07-B01</code> 처럼 붙이면 그 요소로 바로 이동합니다.</div>' +
      '</div>' +
      '<div class="uid-note__actions"><button class="btn btn--primary" data-act="ok">닫기</button></div></div>';
    w.addEventListener('click', function (e) { if (e.target === w || e.target.dataset.act === 'ok') w.remove(); });
    document.body.appendChild(w);
  }

  /* --- 부팅 -------------------------------------------------------------- */
  /* 화면이 자기 본문을 다시 그리면 배지가 사라집니다.
   *
   * app.js 는 화면을 바꿀 때 한 번 scan(main) 을 부릅니다. 그런데 화면
   * 안에서 draw() 로 본문을 갈아 끼우는 곳이 여럿이라(목표 설정 ·
   * 인바디 넣기 · 음식 사진 · 검수), 거기서 배지가 통째로 날아갔습니다.
   * 몇몇 화면은 자기가 scan 을 다시 부르고 있었는데, 그건 "새 화면을
   * 만들 때마다 기억해야 하는 규칙" 이라 언젠가 빠집니다 — 실제로
   * P05 에서 빠져 있었습니다.
   *
   * 화면마다 고치는 대신 본문을 지켜봅니다. 이미 배지가 붙은 요소는
   * attachBadge 가 곧바로 돌아오므로 다시 훑는 비용은 거의 없습니다.
   * 배지를 다는 것 자체가 DOM 변경이라, 스스로를 다시 부르지 않게
   * 한 번 끊었다가 다시 붙입니다. */
  var watcher = null;
  function watchMain() {
    if (!TOOLS || typeof MutationObserver === 'undefined') return;
    var main = document.getElementById('main');
    if (!main) return;
    var queued = false;
    watcher = new MutationObserver(function () {
      if (queued) return;
      queued = true;
      requestAnimationFrame(function () {
        queued = false;
        watcher.disconnect();
        try { scan(main); } catch (e) {}
        watcher.observe(main, { childList: true, subtree: true });
      });
    });
    watcher.observe(main, { childList: true, subtree: true });
  }

  function init() {
    loadPrefs(); loadNotes();
    if (!TOOLS) return;          // 도크도 단축키도 배포 빌드에는 없습니다
    buildDock();
    watchMain();
    document.addEventListener('click', onCaptureClick, true);
    document.addEventListener('keydown', onKeydown);
    window.addEventListener('hashchange', function () {
      var h = location.hash.slice(1);
      if (h) gotoUid(h);
    });
    applyVisibility();
  }

  global.MB_UID = {
    init: init, scan: scan, toggle: toggle, toast: toast,
    setFeedbackMode: setFeedbackMode, exportMarkdown: exportMarkdown, exportAll: exportAll,
    clearAll: clearAll, gotoUid: gotoUid, liveIndex: liveIndex, notesFor: notesFor,
    parseUid: parseUid, showHelp: showHelp,
    get notes() { return state.notes; },
    get state() { return state; }
  };
})(window);
