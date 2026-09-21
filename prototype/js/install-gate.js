/* =============================================================================
 * install-gate.js — 웹 주소로 들어오면 "앱 받기" 부터 보여 준다 (P22)
 *
 * 주인 요청: "웹 링크 들어가면 앱 다운로드 버튼만 나오게 하고,
 *             안드로이드, 아이폰, 아이패드 모두에서 작동하게 해"
 *
 * 왜 화면 하나가 더 필요한가
 *   이 앱은 브라우저에서도 그대로 돕니다. 그래서 친구가 링크를 열면
 *   그냥 쓰기 시작하고, **앱으로 깔 수 있다는 걸 영영 모릅니다.**
 *   깔아야 아이콘이 생기고, 주소창이 사라지고, 오프라인에서 열리고,
 *   아이폰에서는 알림까지 됩니다 — 안 깔면 그 넷을 전부 못 씁니다.
 *
 * 그런데 "다운로드 버튼만" 으로는 안 됩니다
 *   깔 수 없는 경우가 실제로 많습니다.
 *     · 파이어폭스는 설치 자체를 지원하지 않습니다.
 *     · 아이폰에서 크롬·삼성인터넷으로 열면 홈 화면 추가가 안 됩니다.
 *     · 임시 터널 주소(trycloudflare)는 크롬이 설치를 막습니다.
 *   그 사람들에게 설치 버튼만 보여 주면 **들어올 길이 아예 없습니다.**
 *   그래서 "브라우저에서 바로 쓰기" 를 늘 같이 둡니다. 못 깔 상황이면
 *   그쪽을 앞세웁니다. 문을 하나만 만들고 잠가 두지 않습니다.
 *
 * 깔고 나면 이 화면은 다시 안 보입니다
 *   매니페스트의 start_url 이 ?app=1 이라, 홈 화면 아이콘으로 열면
 *   여기를 지나갑니다. 그리고 standalone 으로 뜬 것도 알아봅니다 —
 *   아이폰은 navigator.standalone, 나머지는 display-mode 로 봅니다.
 * ========================================================================== */
(function (global) {
  'use strict';

  var KEY = 'mybody.usebrowser.v1';   // "브라우저로 쓰기로 했다" 는 기억

  function flagged() {
    try { return localStorage.getItem(KEY) === 'yes'; } catch (e) { return false; }
  }
  function remember() {
    try { localStorage.setItem(KEY, 'yes'); } catch (e) {}
  }
  function forget() {
    try { localStorage.removeItem(KEY); } catch (e) {}
  }

  /** 홈 화면 아이콘으로 켠 상태인가 */
  function standalone() {
    try {
      if (global.navigator && global.navigator.standalone === true) return true;   // iOS
      if (global.matchMedia) {
        return global.matchMedia('(display-mode: standalone)').matches ||
               global.matchMedia('(display-mode: fullscreen)').matches ||
               global.matchMedia('(display-mode: minimal-ui)').matches;
      }
    } catch (e) {}
    return false;
  }

  function param(name) {
    try {
      return new URLSearchParams(global.location.search).get(name);
    } catch (e) { return null; }
  }

  /** 이 기기·브라우저가 무엇인가. 안내가 전부 여기서 갈립니다. */
  function device() {
    var ua = '';
    try { ua = global.navigator.userAgent || ''; } catch (e) {}
    var maxTouch = 0;
    try { maxTouch = global.navigator.maxTouchPoints || 0; } catch (e) {}

    /* 아이패드는 iPadOS 13 부터 UA 가 "Macintosh" 입니다 — 문자열만 보면
       맥으로 읽힙니다. 손가락 개수로 갈라야 합니다. 이걸 안 하면
       아이패드 사용자가 "주소창의 설치 아이콘을 누르세요" 를 보게 되고,
       사파리에는 그런 아이콘이 없습니다. */
    var iPadDesktopUA = /Macintosh/.test(ua) && maxTouch > 1;
    var isIos = /iPhone|iPad|iPod/.test(ua) || iPadDesktopUA;
    var isAndroid = /Android/.test(ua);
    /* 아이폰·아이패드에서는 크롬도 파이어폭스도 속은 사파리(WebKit)입니다.
       그런데 홈 화면 추가는 **사파리에서만** 됩니다. 겉을 봐야 합니다. */
    var iosBrowser = isIos
      ? (/CriOS/.test(ua) ? 'chrome'
        : /FxiOS/.test(ua) ? 'firefox'
        : /EdgiOS/.test(ua) ? 'edge'
        : /NAVER|whale/i.test(ua) ? 'whale'
        : /KAKAOTALK/i.test(ua) ? 'kakao'
        : 'safari')
      : null;
    return {
      ios: isIos,
      ipad: /iPad/.test(ua) || iPadDesktopUA,
      android: isAndroid,
      desktop: !isIos && !isAndroid && !/Mobile/.test(ua),
      firefox: /Firefox\//.test(ua),
      iosBrowser: iosBrowser,
      /* 카카오톡·인스타그램 등의 **앱 안 브라우저**. 여기서는 어떤
         방법으로도 설치가 안 됩니다 — 밖으로 내보내야 합니다. */
      inApp: /KAKAOTALK|FBAN|FBAV|Instagram|Line\//i.test(ua)
    };
  }

  /** 지금 이 주소에서 설치가 아예 막혀 있는가 (기다려도 안 되는 경우) */
  function blocked(d) {
    var host = '';
    try { host = global.location.hostname || ''; } catch (e) {}
    if (d.inApp) {
      return '카카오톡·인스타그램 같은 앱 안에서 열면 설치가 안 됩니다. ' +
             '오른쪽 위 메뉴에서 "다른 브라우저로 열기" 를 눌러 주세요.';
    }
    if (d.ios && d.iosBrowser !== 'safari') {
      return '아이폰·아이패드는 **사파리**에서만 홈 화면에 추가할 수 있습니다. ' +
             '이 주소를 사파리로 열어 주세요.';
    }
    if (d.firefox) {
      return '파이어폭스는 앱 설치를 지원하지 않습니다. 크롬·엣지·사파리로 열면 깔 수 있습니다.';
    }
    if (/\.trycloudflare\.com$/i.test(host)) {
      return '지금 주소는 임시 터널입니다. 크롬이 이 도메인을 위험 사이트로 표시해서 ' +
             '설치를 막습니다 — 기다려도 안 나옵니다. 서버에 고정 주소를 붙이면 됩니다.';
    }
    try {
      if (global.isSecureContext === false) {
        return '지금 주소는 https 가 아닙니다. 브라우저가 설치를 막습니다.';
      }
    } catch (e) {}
    return null;
  }

  /** 이 화면을 보여줘야 하는가 */
  function needed() {
    if (standalone()) return false;                 // 이미 앱으로 실행 중
    if (param('app') === '1') return false;         // 매니페스트 start_url 로 들어옴
    if (flagged()) return false;                    // 브라우저로 쓰기로 이미 정함
    return true;
  }

  /* --- 그리기 ------------------------------------------------------------- */

  function h(tag, opts, kids) { return global.MB_UI.h(tag, opts, kids); }

  /** 이 기기에서 깔려면 무엇을 눌러야 하는가 */
  function steps(d) {
    if (d.ios) {
      return [
        d.ipad ? '사파리 위쪽의 공유 버튼(⬆️)을 누르세요.'
               : '사파리 아래쪽의 공유 버튼(⬆️)을 누르세요.',
        '목록을 내려서 **"홈 화면에 추가"** 를 누르세요.',
        '오른쪽 위 "추가" 를 누르면 끝입니다.'
      ];
    }
    if (d.android) {
      return [
        '브라우저 오른쪽 위 메뉴(⋮)를 누르세요.',
        '**"앱 설치"** 또는 "홈 화면에 추가" 를 누르세요.',
        '한 번 더 "설치" 를 누르면 끝입니다.'
      ];
    }
    return [
      '주소창 오른쪽의 설치 아이콘(⊕ 또는 모니터 모양)을 누르세요.',
      '안 보이면 브라우저 메뉴에서 **"Mybody 설치"**.'
    ];
  }

  function why() {
    return [
      ['📱', '아이콘이 생깁니다', '주소를 다시 칠 일이 없습니다.'],
      ['🖥', '주소창이 사라집니다', '진짜 앱처럼 화면을 다 씁니다.'],
      ['✈️', '오프라인에서도 열립니다', '지하철에서도 기록할 수 있습니다.'],
      ['🔔', '알림을 받을 수 있습니다', '아이폰은 깔아야만 알림이 옵니다.']
    ];
  }

  /**
   * 설치 안내를 그립니다.
   * @param {Element} root  여기를 비우고 채웁니다
   * @param {function} onSkip  "브라우저에서 바로 쓰기" 를 눌렀을 때
   */
  function render(root, onSkip) {
    var d = device();
    var why2 = blocked(d);
    var prompt = global.MB_INSTALL && global.MB_INSTALL.prompt;

    root.textContent = '';
    var wrap = h('div', { uid: 'P22', uidLabel: '앱 받기',
      style: { maxWidth: '460px', margin: '0 auto', padding: '28px 18px 40px' } });

    wrap.appendChild(h('div', { style: { textAlign: 'center' } }, [
      h('div', { style: { fontSize: '64px', lineHeight: '1' }, text: '💪' }),
      h('div', { style: { fontSize: '26px', fontWeight: '900', marginTop: '10px' },
                 text: 'Mybody' }),
      h('div.muted', { style: { marginTop: '6px' },
        text: '인바디 결과지를 읽어 목표까지의 계획을 세웁니다.' })
    ]));

    /* --- 설치 --- */
    var card = h('div.card', { uid: 'P22-C01', uidLabel: '앱 받기 카드',
                               style: { marginTop: '22px' } });

    if (why2) {
      /* 못 깝니다. 그렇다고 문을 닫아 두지 않습니다 — 왜 못 깔고,
         그럼 어떻게 쓰면 되는지를 같이 말합니다. */
      card.appendChild(h('div.card__title', { text: '이 브라우저에서는 앱으로 못 깝니다' }));
      card.appendChild(h('div.muted', { style: { marginTop: '6px' }, text: why2 }));
      card.appendChild(h('button.btn.btn--primary.btn--block', {
        text: '그냥 브라우저에서 쓰기', uid: 'P22-B02', uidLabel: '브라우저로 쓰기',
        style: { marginTop: '14px' },
        onClick: function () { remember(); onSkip(); } }));
      card.appendChild(h('div.field__hint', { style: { marginTop: '6px' },
        text: '기능은 똑같습니다. 아이콘·오프라인·알림만 안 됩니다.' }));
      wrap.appendChild(card);
    } else {
      card.appendChild(h('div.card__title', { text: '앱으로 받기' }));

      if (prompt) {
        /* 한 번에 깔 수 있는 경우 — 버튼 하나면 됩니다. */
        card.appendChild(h('button.btn.btn--primary.btn--block', {
          text: '앱 설치', uid: 'P22-B01', uidLabel: '앱 설치',
          style: { marginTop: '12px', fontSize: '17px', padding: '14px' },
          onClick: function () {
            prompt.prompt();
            prompt.userChoice.then(function (r) {
              global.MB_INSTALL.prompt = null;
              if (r && r.outcome === 'accepted') {
                /* 깔았어도 이 창은 그대로 웹입니다. 새로 생긴 아이콘으로
                   열라고 말해 줘야 합니다 — 안 그러면 같은 화면에 그대로
                   머물면서 "깔았는데 왜 똑같지" 가 됩니다. */
                card.textContent = '';
                card.appendChild(h('div.card__title', { text: '깔았습니다' }));
                card.appendChild(h('div.muted', { style: { marginTop: '6px' },
                  text: '홈 화면에 생긴 Mybody 아이콘으로 여세요. 이 창은 닫으셔도 됩니다.' }));
                card.appendChild(h('button.btn.btn--block', {
                  text: '여기서 계속 쓰기', uid: 'P22-B03', uidLabel: '여기서 계속',
                  style: { marginTop: '12px' },
                  onClick: function () { remember(); onSkip(); } }));
              } else {
                render(root, onSkip);      // 취소 — 안내를 다시 그립니다
              }
            }).catch(function () { render(root, onSkip); });
          } }));
        card.appendChild(h('div.field__hint', { style: { marginTop: '8px' },
          text: '누르면 브라우저가 한 번 더 물어봅니다.' }));
      } else {
        /* 버튼을 못 주는 경우 — 손으로 하는 길을 번호를 붙여 적습니다. */
        var ol = h('div', { style: { marginTop: '10px' } });
        steps(d).forEach(function (line, i) {
          ol.appendChild(h('div', {
            style: { display: 'flex', gap: '10px', alignItems: 'flex-start',
                     padding: '7px 0' } }, [
            h('span', { style: { flex: 'none', width: '22px', height: '22px',
                                 borderRadius: '11px', background: 'var(--accent)',
                                 color: '#fff', fontSize: '12px', fontWeight: '800',
                                 display: 'flex', alignItems: 'center',
                                 justifyContent: 'center' },
                        text: String(i + 1) }),
            h('span', { style: { flex: '1' } }, bold(line))
          ]));
        });
        card.appendChild(ol);
        if (d.android) {
          card.appendChild(h('div.field__hint', { style: { marginTop: '6px' },
            text: '메뉴에 "앱 설치" 가 없으면 조금 쓰다 보면 생깁니다 — 크롬이 그렇게 정해 뒀습니다.' }));
        }
      }
      wrap.appendChild(card);

      /* --- 왜 깔면 좋은가 --- */
      var list = h('div.card.card--flat', { uid: 'P22-C02', uidLabel: '설치하면 되는 것',
                                            style: { marginTop: '14px' } });
      why().forEach(function (row) {
        list.appendChild(h('div', {
          style: { display: 'flex', gap: '11px', alignItems: 'flex-start', padding: '7px 0' } }, [
          h('span', { style: { flex: 'none', fontSize: '19px' }, text: row[0] }),
          h('div', { style: { flex: '1', minWidth: '0' } }, [
            h('div', { style: { fontWeight: '700', fontSize: '14px' }, text: row[1] }),
            h('div.muted', { style: { fontSize: '12.5px' }, text: row[2] })
          ])
        ]));
      });
      wrap.appendChild(list);

      /* --- 안 깔고 쓰는 길. 늘 있어야 합니다. --- */
      wrap.appendChild(h('button.btn.btn--ghost.btn--block', {
        text: '브라우저에서 바로 쓰기', uid: 'P22-B02', uidLabel: '브라우저로 쓰기',
        style: { marginTop: '16px' },
        onClick: function () { remember(); onSkip(); } }));
      wrap.appendChild(h('div.field__hint', {
        style: { marginTop: '6px', textAlign: 'center' },
        text: '기능은 똑같습니다. 나중에 설정에서 다시 깔 수 있습니다.' }));
    }

    wrap.appendChild(h('div.muted', {
      style: { marginTop: '22px', fontSize: '12px', textAlign: 'center' } }, [
      h('span', { text: '측정 기록은 이 기기에만 저장됩니다.  ' }),
      h('a', { text: '개인정보처리방침', href: './privacy.html',
               target: '_blank', rel: 'noopener',
               uid: 'P22-B04', uidLabel: '개인정보처리방침' })
    ]));

    root.appendChild(wrap);
  }

  /** **굵게** 를 진짜 굵게. 안내 문장 한두 군데에만 씁니다. */
  function bold(line) {
    var out = [];
    String(line).split(/\*\*(.+?)\*\*/).forEach(function (part, i) {
      if (!part) return;
      out.push(i % 2 ? h('b', { text: part }) : h('span', { text: part }));
    });
    return out;
  }

  global.MB_GATE = { needed: needed, render: render, standalone: standalone,
                     device: device, blocked: blocked, forget: forget };
})(window);
