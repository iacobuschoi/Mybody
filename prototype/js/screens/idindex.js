/* P13 — 고유번호 인덱스 (오너 전용 조회 화면) */
(function (global) {
  'use strict';
  var UI = global.MB_UI, S = global.MB_STORE, E = global.MB_ENGINE, A = global.MB_APP;
  var h = UI.h;

  var LS_SEEN  = 'mybody.uidseen.v1';   /* 누적 레지스트리 — 이 화면이 관리한다 */
  var LS_NOTES = 'mybody.feedback.v1';  /* uid.js 와 같은 키 — 메모 1건 삭제용 */

  /* 종류 칩. 내비(N)·토스트(A) 는 칩을 따로 두지 않고 '전체'에서만 보인다. */
  var KINDS = [
    { key: 'all', label: '전체' },
    { key: 'P',   label: '화면' },
    { key: 'M',   label: '팝업' },
    { key: 'B',   label: '버튼' },
    { key: 'F',   label: '입력' },
    { key: 'C',   label: '카드' },
    { key: 'T',   label: '탭' },
    { key: 'L',   label: '리스트' },
    { key: 'G',   label: '차트' },
    { key: 'S',   label: '상태' }
  ];

  /* 화면 상태 — 다시 들어와도 유지된다 */
  var query = '';
  var kindKey = 'all';

  /* ======================= 누적 레지스트리 ======================= */
  function loadSeen() {
    try {
      var raw = JSON.parse(localStorage.getItem(LS_SEEN) || '{}');
      return (raw && typeof raw === 'object' && !Array.isArray(raw)) ? raw : {};
    } catch (e) { return {}; }
  }
  function saveSeen(map) {
    try { localStorage.setItem(LS_SEEN, JSON.stringify(map)); } catch (e) {}
  }
  function p2(n) { return (n < 10 ? '0' : '') + n; }
  function stamp() {
    var d = new Date();
    return d.getFullYear() + '-' + p2(d.getMonth() + 1) + '-' + p2(d.getDate());
  }

  /**
   * 지금 DOM 에 떠 있는 요소를 누적 레지스트리에 합치고, 합쳐진 맵을 돌려준다.
   * 런타임이 붙이는 행 인스턴스(#n)는 레지스트리에 넣지 않는다 — 번호가 아니라 인스턴스다.
   */
  function harvest() {
    var map = loadSeen();
    if (!global.MB_UID || !global.MB_UID.liveIndex) return map;
    var changed = false;
    global.MB_UID.liveIndex().forEach(function (it) {
      if (!it.uid || it.uid.indexOf('#') >= 0) return;
      var old = map[it.uid];
      if (!old || old.label !== it.label || old.container !== it.container) {
        map[it.uid] = { label: it.label || '', container: it.container || '', at: stamp() };
        changed = true;
      }
    });
    if (changed) saveSeen(map);
    return map;
  }

  /* liveIndex() 는 지금 그려진 것만 본다. 오너가 앱을 돌아다니는 동안에도 목록이 자라도록
     화면이 바뀔 때마다 조용히 주워 담는다 (이 파일 안에서만 동작, 다른 파일은 건드리지 않음). */
  (function watchDom() {
    if (typeof MutationObserver !== 'function') return;
    var pending = null;
    var obs = new MutationObserver(function () {
      if (pending) return;
      pending = setTimeout(function () { pending = null; harvest(); }, 400);
    });
    try { obs.observe(document.documentElement, { childList: true, subtree: true }); } catch (e) {}
  })();

  /* ======================= 클립보드 ======================= */
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

  /* ======================= 화면 ======================= */
  /* P13 은 만드는 사람용 화면입니다. 배포 빌드에서는 등록조차 하지 않습니다 —
     주소창에 남은 #P13 으로도 들어올 수 없게. (app.js 의 boot() 이 해시를
     읽어 화면을 정하기 때문에, 카드만 숨겨서는 막히지 않습니다.) */
  if (!(global.MB_BUILD && global.MB_BUILD.tools)) return;

  A.register('P13', {
    title: 'ID 목록', label: '고유번호 인덱스',
    render: function (wrap, ctx) {
      var seen = harvest();

      /* 지금 화면에 떠 있는 번호.
         app.js 는 render() 가 끝난 뒤에야 wrap 을 문서에 붙인다. 그래서 document 만 훑으면
         이 화면 자신의 번호가 전부 '없음' 으로 잡히고, 앱 셸(P00-*) 말고는 아무것도 살아 있지
         않게 된다. 아직 문서에 붙기 전이면 wrap 도 같이 훑는다. */
      var liveMap = {}, liveCount = 0;
      function refreshLive() {
        liveMap = {}; liveCount = 0;
        var pool = [], i, els;
        els = document.querySelectorAll('[data-uid]');
        for (i = 0; i < els.length; i++) pool.push(els[i]);
        if (!wrap.isConnected) {
          if (wrap.getAttribute('data-uid')) pool.push(wrap);
          els = wrap.querySelectorAll('[data-uid]');
          for (i = 0; i < els.length; i++) pool.push(els[i]);
        }
        for (i = 0; i < pool.length; i++) {
          var u = pool[i].getAttribute('data-uid');
          if (!u || u.indexOf('#') >= 0) continue;
          if (!liveMap[u]) { liveMap[u] = true; liveCount++; }
        }
      }

      /* 누적 + 현재를 한 목록으로 */
      var rows = Object.keys(seen).map(function (uid) {
        var info = global.MB_UID.parseUid(uid);
        var rec = seen[uid] || {};
        return {
          uid: uid,
          kind: info.kind,
          kindLabel: info.kindLabel,
          label: rec.label || '',
          container: rec.container || info.container,
          notes: global.MB_UID.notesFor(uid).length
        };
      });
      rows.sort(function (a, b) { return a.uid.localeCompare(b.uid); });

      /* --- C01 번호 읽는 법 ------------------------------------------- */
      wrap.appendChild(h('div.card', { uid: 'P13-C01', uidLabel: '번호 읽는 법 설명' }, [
        h('div.card__head', [
          h('div.card__title', { text: '번호 읽는 법' }),
          h('div.card__sub', { text: '"이게 몇 번이더라" 를 없애려고 만든 화면입니다' })
        ]),
        h('div', { style: { fontSize: '13px', lineHeight: '1.65', color: 'var(--text-2)' }, text:
          '모든 번호는 두 칸입니다. 앞 칸은 소속 컨테이너 — P는 화면, M은 팝업이고, 뒤 칸은 그 안의 ' +
          '요소 종류와 순번입니다. B는 버튼, F는 입력, C는 카드, T는 탭, N은 내비, L은 리스트, ' +
          'G는 차트, S는 상태(빈 화면·로딩·오류)를 뜻합니다. 예를 들어 P06-B21 은 "강도 선택 화면(P06)의 ' +
          '21번 버튼" 입니다. 번호는 한 번 정하면 바꾸지 않으니, 고치고 싶은 곳이 보이면 번호만 ' +
          '불러 주시면 됩니다.' }),
        h('hr.sep'),
        h('div.section-title', { text: '배지 조작' }),
        h('div.kv', [h('span.kv__k', { text: '배지 클릭' }),
                     h('span.kv__v', { text: 'ID + 라벨 복사' })]),
        h('div.kv', [h('span.kv__k', { text: 'Shift + 배지 클릭' }),
                     h('span.kv__v', { text: '그 번호에 메모 남기기' })]),
        h('div.kv', [h('span.kv__k', { text: 'Alt + 배지 클릭' }),
                     h('span.kv__v', { text: '딥링크(#P06-B21) 복사' })]),
        h('hr.sep'),
        h('div.section-title', { text: '단축키' }),
        h('div.kv', [h('span.kv__k', { text: 'i' }),
                     h('span.kv__v', { text: '번호 배지 전체 켜기 / 끄기' })]),
        h('div.kv', [h('span.kv__k', { text: 'f' }),
                     h('span.kv__v', { text: '피드백 모드 — 아무 요소나 클릭하면 메모창' })]),
        h('div.kv', [h('span.kv__k', { text: '?' }),
                     h('span.kv__v', { text: '단축키 도움말' })])
      ]));

      /* --- C02 검색 · 종류 필터 ---------------------------------------- */
      var searchInput = h('input.input', {
        uid: 'P13-F01', uidLabel: '번호·라벨 검색',
        type: 'text', value: query, placeholder: 'P06-B21 또는 "강도"',
        'aria-label': '번호 또는 라벨 검색',
        onInput: function (ev) { query = ev.target.value; drawList(); }
      });

      var chipEls = KINDS.map(function (k) {
        var n = k.key === 'all' ? rows.length : rows.filter(function (r) { return r.kind === k.key; }).length;
        return h('button.chip' + (kindKey === k.key ? '.is-on' : ''), {
          text: k.label + ' ' + n,
          onClick: function () { kindKey = k.key; syncChips(); drawList(); }
        });
      });
      function syncChips() {
        chipEls.forEach(function (b, i) { b.classList.toggle('is-on', KINDS[i].key === kindKey); });
      }

      wrap.appendChild(h('div.card', { uid: 'P13-C02', uidLabel: '검색·종류 필터' }, [
        h('div.field.uid-index__search', [
          h('div.field__label', { text: '검색' }),
          searchInput,
          h('div.field__hint', { text: '번호나 한글 라벨 일부를 넣으면 바로 걸러집니다. 대소문자는 가리지 않습니다.' })
        ]),
        h('div.field', { style: { marginBottom: '0' } }, [
          h('div.field__label', { text: '종류' }),
          h('div.chips', { uid: 'P13-F02', uidLabel: '종류 필터' }, chipEls)
        ])
      ]));

      /* --- S01 목록 범위 안내 ------------------------------------------ */
      wrap.appendChild(h('div.note.note--warn', { uid: 'P13-S01', uidLabel: '목록 범위 안내' }, [
        '지금 화면에 그려진 요소만 보입니다. 각 화면을 한 번씩 들른 뒤 다시 오면 목록이 채워집니다.',
        h('div.muted', { style: { marginTop: '5px' },
          text: '한 번 본 번호는 이 기기에 누적 저장되므로, 다시 들어와도 남아 있습니다.' })
      ]));

      /* --- L01 번호 목록 ------------------------------------------------ */
      var countEl = h('div.muted', { style: { marginBottom: '6px' } });
      var listBody = h('div');

      wrap.appendChild(h('div.card', { uid: 'P13-L01', uidLabel: '고유번호 목록' }, [
        h('div.card__head', [
          h('div.card__title', { text: '번호 목록' }),
          h('span.badge.badge--accent', { text: '누적 ' + rows.length + '개' })
        ]),
        countEl,
        listBody
      ]));

      function matches(r) {
        if (kindKey !== 'all' && r.kind !== kindKey) return false;
        var q = query.trim().toLowerCase();
        if (!q) return true;
        return r.uid.toLowerCase().indexOf(q) >= 0 ||
               (r.label || '').toLowerCase().indexOf(q) >= 0;
      }

      function drawList() {
        UI.clear(listBody);
        refreshLive();
        var shown = rows.filter(matches);

        countEl.textContent = '누적 ' + rows.length + '개 · 현재 화면 ' + liveCount +
          '개 · 표시 ' + shown.length + '개';

        if (!rows.length) {
          listBody.appendChild(h('div.empty', { uid: 'P13-S02', uidLabel: '목록 없음 빈 상태' }, [
            h('div.empty__ico', { text: '🔢' }),
            h('div.empty__t', { text: '아직 모인 번호가 없습니다' }),
            h('div.empty__d', { text: '홈 · 플랜 · 체크인 · 추이 화면을 한 번씩 들른 뒤 다시 오세요.' }),
            h('button.btn.btn--primary', { text: '홈으로 가서 둘러보기', uid: 'P13-B15',
              uidLabel: '홈으로 가서 둘러보기', onClick: function () { A.go('P02'); } })
          ]));
          rescan();
          return;
        }
        if (!shown.length) {
          listBody.appendChild(h('div.empty', { uid: 'P13-S03', uidLabel: '검색 결과 없음' }, [
            h('div.empty__ico', { text: '🔍' }),
            h('div.empty__t', { text: '조건에 맞는 번호가 없습니다' }),
            h('div.empty__d', { text: '검색어를 줄이거나 종류를 "전체" 로 바꿔보세요.' })
          ]));
          rescan();
          return;
        }
        shown.forEach(function (r) { listBody.appendChild(indexRow(r)); });
      }

      /* 목록만 다시 그렸을 때만 배지를 붙인다.
         첫 렌더링 시점에는 wrap 이 아직 문서에 붙기 전이라
         app.js 의 scan(main) 에 맡긴다 (떨어진 트리에서는 배지 좌표가 틀어진다). */
      function rescan() {
        if (listBody.isConnected) global.MB_UID.scan(listBody);
      }

      function indexRow(r) {
        var live = !!liveMap[r.uid];
        /* gotoUid 는 소속 컨테이너로 A.go() 한다. 팝업(M##)·토스트(A##) 는 등록된 화면이 아니라
           go() 가 콘솔 경고만 내고 끝난다 — 그러면 그냥 먹통 클릭이 된다. 갈 수 없는 번호는
           이동하는 척하지 말고 번호를 복사해 준다. */
        function goThere() {
          if (live || r.container.charAt(0) === 'P') { global.MB_UID.gotoUid(r.uid); return; }
          copy(r.uid + (r.label ? ' · ' + r.label : ''));
          global.MB_UID.toast(r.uid + ' 복사됨 — 팝업·토스트는 그 상황에서만 화면에 뜹니다');
        }
        return h('div.uid-index__row', {
          role: 'button', tabindex: '0',
          title: (live || r.container.charAt(0) === 'P')
            ? (r.uid + ' 위치로 이동') : (r.uid + ' 번호 복사'),
          style: { cursor: 'pointer', opacity: live ? '1' : '.66' },
          onClick: goThere,
          onKeyDown: function (ev) {
            if (ev.key === 'Enter' || ev.key === ' ') { ev.preventDefault(); goThere(); }
          }
        }, [
          h('span.uid-index__id', { 'data-k': r.kind, text: r.uid }),
          h('div', { style: { minWidth: '0' } }, [
            h('div.uid-index__label', { text: r.label || '(라벨 없음)' }),
            h('div.uid-index__meta', { text: r.kindLabel + ' · ' + r.container +
              (live ? '' : ' · 지금 화면에 없음') })
          ]),
          r.notes > 0
            ? h('span.badge.badge--bad.nowrap', { text: '메모 ' + r.notes })
            : h('span.uid-index__meta', { text: '›' })
        ]);
      }

      /* 첫 그리기는 render() 맨 끝으로 미룬다 — wrap 이 다 채워진 뒤라야
         '현재 화면 N개' 와 살아있음 표시가 이 화면 전체를 세게 된다. */

      /* --- C03 피드백 목록 ---------------------------------------------- */
      var notes = global.MB_UID.notes;
      var fb = h('div.card', { uid: 'P13-C03', uidLabel: '피드백 목록' }, [
        h('div.card__head', [
          h('div.card__title', { text: '내가 남긴 피드백' }),
          h('span.badge' + (notes.length ? '.badge--accent' : ''), { text: notes.length + '건' })
        ])
      ]);

      if (!notes.length) {
        fb.appendChild(h('div.empty', { uid: 'P13-S04', uidLabel: '피드백 없음 빈 상태' }, [
          h('div.empty__ico', { text: '💬' }),
          h('div.empty__t', { text: '아직 남긴 메모가 없습니다' }),
          h('div.empty__d', { text: '고치고 싶은 곳의 배지를 Shift + 클릭하거나, f 키로 피드백 모드를 켜고 그 요소를 클릭하세요.' })
        ]));
      } else {
        notes.forEach(function (n, i) {
          var info = global.MB_UID.parseUid(n.uid);
          fb.appendChild(h('div.uid-index__row', [
            h('span.uid-index__id', { 'data-k': info.kind, text: n.uid }),
            h('div', { style: { minWidth: '0' } }, [
              h('div', { style: { wordBreak: 'break-word' }, text: n.text }),
              h('div.uid-index__meta', { text: (n.label ? n.label + ' · ' : '') +
                (n.screen ? n.screen + ' · ' : '') + (n.at || '') })
            ]),
            h('button.btn.btn--ghost.btn--sm', {
              text: '삭제', uid: 'P13-B14#' + (i + 1), uidLabel: '메모 삭제',
              onClick: function () { deleteNote(n); }
            })
          ]));
        });
      }

      fb.appendChild(h('div.btn-row.btn-row--stack', { style: { marginTop: '12px' } }, [
        h('button.btn.btn--primary.btn--block', {
          text: '📋 피드백 전체 복사', uid: 'P13-B11', uidLabel: '피드백 전체 복사',
          onClick: function () {
            if (!global.MB_UID.notes.length) { global.MB_UID.toast('아직 복사할 메모가 없습니다'); return; }
            global.MB_UID.exportAll();
          }
        }),
        h('button.btn.btn--block', {
          text: '✍️ 피드백 템플릿 복사', uid: 'P13-B13', uidLabel: '피드백 템플릿 복사',
          onClick: function () {
            copy('[P__-B__] 의견: ');
            global.MB_UID.toast('템플릿 복사됨 — 번호만 채워서 보내주세요');
          }
        }),
        h('button.btn.btn--danger.btn--block', {
          text: '🗑 메모 모두 지우기', uid: 'P13-B12', uidLabel: '피드백 모두 지우기',
          onClick: function () {
            var n = global.MB_UID.notes.length;
            if (!n) { global.MB_UID.toast('지울 메모가 없습니다'); return; }
            global.MB_MODALS.confirmClear({
              title: '메모를 모두 지울까요?',
              warn: '화면에 남긴 메모 ' + n + '개가 전부 사라지고 되돌릴 수 없습니다.',
              keep: '측정 기록과 계획은 그대로 남습니다.',
              onConfirm: function () {
                global.MB_UID.clearAll();
                global.MB_UID.toast('메모 ' + n + '개를 지웠습니다');
                A.refresh();
              }
            });
          }
        })
      ]));
      fb.appendChild(h('div.muted', { style: { marginTop: '8px' },
        text: '전체 복사는 화면별로 묶인 마크다운을 클립보드에 넣습니다. 그대로 채팅에 붙여넣으면 됩니다.' }));
      wrap.appendChild(fb);

      drawList();
    }
  });

  /* uid.js 에 메모 1건 삭제용 공개 API 가 없어서, 같은 배열을 직접 손보고 같은 키로 저장한다. */
  function deleteNote(note) {
    var arr = global.MB_UID.notes;
    var idx = arr.indexOf(note);
    if (idx < 0) {
      for (var i = 0; i < arr.length; i++) { if (arr[i].id === note.id) { idx = i; break; } }
    }
    if (idx < 0) return;
    arr.splice(idx, 1);
    try { localStorage.setItem(LS_NOTES, JSON.stringify(arr)); } catch (e) {}
    global.MB_UID.toast('메모를 지웠습니다');
    A.refresh();
  }
})(window);
