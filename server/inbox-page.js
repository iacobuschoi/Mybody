/* =============================================================================
 * server/inbox-page.js — 컴퓨터 브라우저로 보는 「의견함」 (GET /inbox)
 *
 * 왜 있나
 *   주인의 말 "의견함 컴퓨터에서 볼 수 있는 거 만들어 주라". 의견은 운영자 폰 앱의
 *   설정 → 「의견함」(app/lib/src/screens/feedback_inbox.dart)과 서버 컴퓨터 앞의 도구
 *   (tools/feedback.js)로만 봤습니다. 긴 글 · 화면 캡처는 큰 화면이 읽기 편하고, 노트북에서
 *   도구를 돌리지 않아도 **아무 컴퓨터의 브라우저**에서 <서버>/inbox 를 열면 됩니다.
 *
 * 무엇을 하나 — 페이지는 껍데기뿐입니다
 *   서버가 내보내는 것은 글자 한 벌(HTML · 스타일 · 스크립트)이고, 누구에게나 같습니다 —
 *   DB 를 안 보고, 요청의 어떤 글자도 페이지에 싣지 않습니다. 의견은 페이지의 스크립트가
 *   앱과 **같은 API** 로 가져옵니다(server.js handleFeedbackInbox 머리 주석의 약속):
 *     로그인    POST /api/auth/signin {handle, password} → {token}
 *               GET /api/me 의 user.isOperator 가 true 가 아니면 「운영자 계정만 볼 수 있어요」 +
 *               방금 받은 토큰을 POST /api/auth/signout 으로 바로 끊음(쓰지 않을 로그인이 90일
 *               남지 않게)
 *     목록      GET  /api/feedback/inbox?limit=30&before=<번호>
 *     사진      GET  /api/feedback/inbox/<번호>/image/<n>  (Authorization 머리로 받아 blob URL)
 *     읽음      POST /api/feedback/inbox/<번호>/read       열면 읽음 — 앱처럼 화면 먼저, 못 닿으면
 *                                                          되돌림(404 는 그사이 지워진 것이라 그대로)
 *     모두 읽음 POST /api/feedback/inbox/read-all {upTo}   받아 둔 것 중 가장 새 번호까지만
 *     지우기    DELETE /api/feedback/inbox/<번호>           페이지 안에서 한 번 묻고(404 도 지운 것)
 *   막는 것은 전부 그 API 가 요청마다 합니다(로그인 없으면 401, 운영자 아니면 403). 이 페이지는
 *   누구나 열 수 있지만 로그인 칸만 보입니다.
 *
 * 토큰
 *   기본은 sessionStorage(탭을 닫으면 없어짐), 「이 컴퓨터에서 로그인 유지」 를 켜면 localStorage.
 *   「로그아웃」 은 서버의 로그인을 끊고(signout) 두 곳을 다 비웁니다. 401 이 오면 비우고
 *   로그인 화면으로. 토큰은 Authorization 머리로만 나가고 주소 · 쿠키에는 안 실립니다.
 *
 * 남의 글을 다루는 법 (XSS)
 *   의견 글은 **로그인 없이도** 보낼 수 있는 남의 글이고, 보낸 사람 이름 · 판 · 화면 이름도
 *   남이 정한 글자입니다. 페이지의 스크립트는 받은 글자를 전부 textContent · createElement 로만
 *   놓습니다 — HTML 문자열로 끼워 넣는 길(innerHTML · insertAdjacentHTML · document.write)은
 *   데이터가 아니어도 쓰지 않습니다. 인라인 이벤트 속성(onclick= …)도 없습니다(CSP 가 막음).
 *   tools/test-inbox-page.js 가 페이지 글자를 읽어 이것들이 없는지 보고, 진짜 브라우저에서
 *   <img onerror> · </script> 가 든 의견이 글자 그대로 보이는지 봅니다.
 *
 * CSP — 친구 초대 페이지(server.js serveInvite · INVITE_CSP)와 같은 방식
 *   default-src 'none' 에 스크립트 · 스타일은 페이지에 박는 한 덩이씩의 sha256 해시만.
 *   해시는 박는 글자와 **같은 문자열**에서 계산해서 어긋날 수 없습니다. 사진은 blob: 만,
 *   fetch 는 같은 서버(connect-src 'self')만, 폼은 어디로도 못 보냄(form-action 'none' —
 *   스크립트가 막혀도 비밀번호가 주소에 실려 나가지 않게), 남의 페이지 안에 못 들어감
 *   (frame-ancestors 'none'). 외부 글꼴 · 그림 없음(시스템 글꼴).
 *   줄바꿈은 LF 로 맞춥니다 — 윈도우에서 git 이 이 파일을 CRLF 로 꺼내면(core.autocrlf)
 *   toString() 에 \r\n 이 실리는데, 브라우저는 \r\n 을 \n 으로 바꾼 뒤에 해시를 잽니다.
 *   안 맞추면 CSP 가 스크립트를 조용히 막아 로그인 단추가 아무 일도 안 합니다.
 *   (tools/test-inbox-page.js 가 CRLF 로 읽힌 이 파일로 봅니다 — test-invite.js [15] 와 같은 방법.)
 *
 * 머리
 *   Cache-Control: no-store · Vary: * — 이 서버의 웹 앱을 연 적 있는 브라우저의 서비스워커가
 *   페이지를 Cache Storage 에 담지 못하게(server.js INVITE_HEADERS 주석 — Cache.put 은
 *   Vary: * 를 거절합니다). X-Robots-Tag: noindex · Referrer-Policy: no-referrer ·
 *   X-Frame-Options: DENY(frame-ancestors 를 모르는 옛 브라우저용). 로그에는 안 남습니다
 *   (server.js logLine 은 /api 만 찍음 — 페이지가 부르는 API 줄은 경로 · 상태만).
 *
 * 정적 파일이 아닙니다 — 운영은 STATIC=./release 로 띄우고 prototype/ 는 나가지 않습니다.
 * 서버 코드가 만들어 보내므로 어느 폴더를 내보내든 같고, 그 폴더에 inbox 라는 파일이 있어도
 * 이것이 먼저입니다(server.js 가 정적 파일보다 먼저 봄).
 * ========================================================================== */
'use strict';
const crypto = require('node:crypto');

/* 페이지 모양. 색은 초대 페이지(server.js INVITE_CSS)와 같은 토큰이고, 밝게 · 어둡게는 컴퓨터를
   따릅니다. 넓으면(801px~) 왼쪽 목록 · 오른쪽 자세히 — 둘이 따로 스크롤. 좁으면 한 줄: 목록을
   누르면 자세히가 목록 자리에 서고 「← 목록」 으로 돌아옵니다. 360px 에서도 가로로 밀리지 않게
   긴 글자는 아무 데서나 끊고(overflow-wrap:anywhere) 칩은 말줄임. 글꼴은 시스템 것만 —
   CSP 가 밖의 글꼴을 막습니다. **여기를 고치면 CSP 해시가 저절로 따라갑니다.** */
const INBOX_CSS = [
  ':root{--bg:#f6f7f9;--surface:#fff;--border:#e2e5ea;--text:#16181d;--muted:#5b6270;',
  '--accent:#4f46e5;--accent-ink:#fff;--accent-sub:#eef0ff;--bad:#b42318;--bad-bg:#fdecea;--bad-ink:#fff;color-scheme:light dark}',
  '@media (prefers-color-scheme:dark){:root{--bg:#0e1014;--surface:#171a20;--border:#2a2f39;--text:#e9ecf1;',
  '--muted:#a3adbb;--accent:#8b8cf8;--accent-ink:#0e1014;--accent-sub:#232447;--bad:#f97066;--bad-bg:#2d1512;--bad-ink:#0e1014}}',
  '*{box-sizing:border-box}',
  'html,body{margin:0}',
  'body{background:var(--bg);color:var(--text);',
  'font:15px/1.55 system-ui,-apple-system,BlinkMacSystemFont,"Apple SD Gothic Neo","Malgun Gothic","Noto Sans KR","Segoe UI",Roboto,sans-serif;',
  'word-break:keep-all;overflow-wrap:anywhere}',
  '[hidden]{display:none!important}',
  'button,input{font:inherit;color:inherit}',
  'h1,h2,p{margin:0}',
  ':focus-visible{outline:2px solid var(--accent);outline-offset:2px}',
  '.btn{appearance:none;border:1px solid var(--border);background:var(--surface);color:var(--text);border-radius:10px;',
  'padding:6px 12px;font-size:14px;line-height:1.4;cursor:pointer;white-space:nowrap}',
  '.btn:hover{border-color:var(--accent)}',
  '.btn:disabled{opacity:.5;cursor:default;border-color:var(--border)}',
  '.btn.primary{background:var(--accent);color:var(--accent-ink);border-color:var(--accent);font-weight:700}',
  '.btn.danger{color:var(--bad)}',
  '.btn.danger.solid{background:var(--bad);color:var(--bad-ink);border-color:var(--bad);font-weight:700}',
  '.msg{color:var(--bad);font-size:14px}',
  '.msg.calm{color:var(--muted)}',
  '.muted{color:var(--muted)}',
  '#boot{padding:48px 16px;text-align:center;color:var(--muted)}',
  /* 로그인 */
  '.login{min-height:100vh;display:flex;align-items:center;justify-content:center;padding:24px 16px}',
  '.login form{width:100%;max-width:360px;background:var(--surface);border:1px solid var(--border);border-radius:16px;',
  'padding:24px 20px;display:flex;flex-direction:column;gap:12px}',
  '.login h1{font-size:22px}',
  '.login label{display:flex;flex-direction:column;gap:4px;font-size:14px;color:var(--muted)}',
  '.login input:not([type=checkbox]){width:100%;padding:10px 12px;border:1px solid var(--border);border-radius:10px;',
  'background:var(--bg);color:var(--text);font-size:16px}',
  '.login label.check{flex-direction:row;align-items:center;gap:8px;color:var(--text)}',
  '.login .btn{padding:11px 12px;font-size:16px}',
  /* 위 막대 */
  '.inbox{display:flex;flex-direction:column;min-height:100vh}',
  '.bar{position:sticky;top:0;z-index:3;display:flex;flex-wrap:wrap;align-items:center;gap:8px 12px;',
  'padding:10px 16px;background:var(--surface);border-bottom:1px solid var(--border)}',
  '.bar h1{font-size:18px;display:flex;align-items:center;gap:8px;margin-right:auto}',
  '.badge{font-size:12px;font-weight:700;background:var(--accent);color:var(--accent-ink);border-radius:999px;padding:1px 8px}',
  '.tools{display:flex;flex-wrap:wrap;gap:6px}',
  '.seg{display:inline-flex;border:1px solid var(--border);border-radius:10px;overflow:hidden}',
  '.seg button{appearance:none;border:0;background:var(--surface);padding:6px 10px;font-size:14px;cursor:pointer;white-space:nowrap}',
  '.seg button+button{border-left:1px solid var(--border)}',
  '.seg button[aria-pressed=true]{background:var(--accent-sub);color:var(--accent);font-weight:700}',
  '.err{display:flex;flex-wrap:wrap;align-items:center;gap:8px;margin:12px 16px 0;padding:10px 12px;border-radius:10px;',
  'background:var(--bad-bg);color:var(--bad);font-size:14px}',
  '.err span{flex:1;min-width:0}',
  /* 목록 · 자세히 */
  '.panes{flex:1;display:grid;grid-template-columns:minmax(280px,380px) minmax(0,1fr);min-height:0}',
  '.list-pane{border-right:1px solid var(--border);overflow:auto;padding:12px}',
  '.list{list-style:none;margin:0;padding:0;display:flex;flex-direction:column;gap:8px}',
  '.row{display:block;width:100%;text-align:left;background:var(--surface);border:1px solid var(--border);',
  'border-radius:12px;padding:10px 12px;cursor:pointer;min-width:0}',
  '.row:hover{border-color:var(--accent)}',
  '.row.sel{border-color:var(--accent);background:var(--accent-sub)}',
  '.row.sel .chip{background:var(--surface)}',
  '.row>span{display:block}',
  '.top{display:flex!important;align-items:center;gap:8px;min-width:0}',
  '.dot{flex:none;width:8px;height:8px;border-radius:50%;background:var(--accent)}',
  '.from{flex:1;min-width:0;overflow:hidden;white-space:nowrap;text-overflow:ellipsis;font-weight:500}',
  '.unread .from{font-weight:800}',
  '.time{flex:none;font-size:13px;color:var(--muted);white-space:nowrap}',
  '.chips{display:flex!important;flex-wrap:wrap;gap:4px;margin-top:6px;min-width:0}',
  '.chip{max-width:100%;overflow:hidden;white-space:nowrap;text-overflow:ellipsis;font-size:12px;',
  'padding:1px 8px;border-radius:999px;background:var(--accent-sub);color:var(--text)}',
  '.preview{margin-top:6px;overflow:hidden;display:-webkit-box!important;-webkit-line-clamp:2;-webkit-box-orient:vertical;',
  'overflow-wrap:anywhere}',
  '.preview.none,.d-text.none{color:var(--muted);font-style:italic}',
  '.empty{padding:32px 8px;text-align:center;color:var(--muted)}',
  '.more{display:block;width:100%;margin-top:10px;padding:10px}',
  '.detail{overflow:auto;padding:16px 20px 40px;min-width:0}',
  '.placeholder{padding:48px 8px;text-align:center;color:var(--muted)}',
  '.d-head{display:flex;align-items:center;gap:10px;margin-bottom:12px}',
  '.d-head h2{flex:1;min-width:0;font-size:19px;overflow:hidden;white-space:nowrap;text-overflow:ellipsis}',
  '.back{display:none}',
  '.meta{display:grid;grid-template-columns:auto minmax(0,1fr);gap:2px 14px;margin:0 0 14px;font-size:14px}',
  '.meta dt{color:var(--muted)}',
  '.meta dd{margin:0;overflow-wrap:anywhere}',
  '.d-text{white-space:pre-wrap;overflow-wrap:anywhere;font-size:16px;line-height:1.65;background:var(--surface);',
  'border:1px solid var(--border);border-radius:12px;padding:14px 16px;margin:0 0 14px}',
  '.shots{display:flex;flex-wrap:wrap;gap:10px}',
  '.shot{appearance:none;padding:0;border:1px solid var(--border);border-radius:10px;background:var(--surface);',
  'cursor:zoom-in;overflow:hidden;max-width:100%}',
  '.shot img{display:block;max-width:100%;max-height:420px;min-width:40px;min-height:40px}',
  '.shot.wait{width:180px;height:240px}',
  '.shot.wait img{visibility:hidden}',
  '.shot.broken{width:180px;height:80px;cursor:default;color:var(--muted);font-size:13px;padding:8px}',
  '.confirm{margin:0 0 14px;padding:12px 14px;border:1px solid var(--bad);border-radius:12px;background:var(--bad-bg)}',
  '.confirm p{margin:0 0 10px}',
  '.confirm-btns{display:flex;flex-wrap:wrap;gap:8px}',
  '.confirm .msg{margin:8px 0 0}',
  /* 사진 크게 */
  '.viewer{position:fixed;inset:0;z-index:10;background:rgba(0,0,0,.9);display:flex;flex-direction:column;',
  'align-items:center;justify-content:center;gap:10px;padding:12px;cursor:zoom-out}',
  '.viewer img{display:block;max-width:100%;max-height:calc(100vh - 80px);object-fit:contain}',
  '.viewer-bar{display:flex;align-items:center;gap:10px;color:#fff}',
  '.viewer .btn{background:rgba(255,255,255,.12);color:#fff;border-color:rgba(255,255,255,.3)}',
  '.toast{position:fixed;left:50%;bottom:20px;transform:translateX(-50%);z-index:11;max-width:calc(100% - 32px);',
  'background:var(--text);color:var(--bg);border-radius:10px;padding:8px 14px;font-size:14px}',
  /* 좁은 화면 — 한 줄 */
  '@media (max-width:800px){',
  '.panes{display:block}',
  '.list-pane{border-right:0;overflow:visible}',
  '.detail{overflow:visible;padding:14px 16px 32px}',
  'body.show-detail .list-pane,body:not(.show-detail) .detail{display:none}',
  '.back{display:inline-block}',
  '.bar{padding:8px 12px}',
  '}'
].join('');

/* 페이지의 뼈대 — 받은 글자는 하나도 안 들어갑니다(누구에게나 같은 글자). 스크립트가 켜지기
   전에는 "불러오는 중…" 만 보이고, 켜지면 저장된 로그인이 있는지 보고 로그인 칸이나 목록을
   엽니다. 폼은 method="post" 에 action 이 없어도 CSP form-action 'none' 이 막으므로, 스크립트가
   막혀도 비밀번호가 어디로 보내지지 않습니다(스크립트는 늘 preventDefault). */
const INBOX_BODY = [
  '<p id="boot">불러오는 중…</p>',
  '<noscript><p class="empty">자바스크립트를 켜야 볼 수 있어요</p></noscript>',
  '<section id="login" class="login" hidden>',
  '<form id="login-form" method="post" autocomplete="on" novalidate>',
  '<h1>의견함</h1>',
  '<p class="muted">운영자 계정으로 로그인</p>',
  '<label>아이디<input id="handle" name="username" autocomplete="username" autocapitalize="none" spellcheck="false" maxlength="64"></label>',
  '<label>비밀번호<input id="password" name="password" type="password" autocomplete="current-password" maxlength="200"></label>',
  '<label class="check"><input id="keep" type="checkbox">이 컴퓨터에서 로그인 유지</label>',
  '<button id="login-btn" class="btn primary" type="submit">로그인</button>',
  '<p id="login-msg" class="msg" role="alert" hidden></p>',
  '</form>',
  '</section>',
  '<section id="inbox" class="inbox" hidden>',
  '<header class="bar">',
  '<h1>의견함<span id="unread" class="badge" hidden></span></h1>',
  '<div class="tools">',
  '<div class="seg" role="group" aria-label="보기">',
  '<button id="f-unread" type="button" aria-pressed="false">안 읽은 것만</button>',
  '<button id="f-all" type="button" aria-pressed="true">전체</button>',
  '</div>',
  '<button id="read-all" class="btn" type="button" disabled>모두 읽음</button>',
  '<button id="refresh" class="btn" type="button">새로고침</button>',
  '<button id="logout" class="btn" type="button">로그아웃</button>',
  '</div>',
  '</header>',
  '<div id="err" class="err" role="alert" hidden><span id="err-text"></span>',
  '<button id="retry" class="btn" type="button">다시 시도</button></div>',
  '<div class="panes">',
  '<nav id="list-pane" class="list-pane" aria-label="의견 목록">',
  '<ul id="list" class="list"></ul>',
  '<p id="empty" class="empty" hidden></p>',
  '<button id="more" class="btn more" type="button" hidden>더 보기</button>',
  '</nav>',
  '<article id="detail" class="detail"></article>',
  '</div>',
  '</section>',
  '<div id="viewer" class="viewer" role="dialog" aria-modal="true" aria-label="사진" hidden>',
  '<img id="viewer-img" alt="">',
  '<div class="viewer-bar">',
  '<button id="viewer-prev" class="btn" type="button" aria-label="앞 사진">‹</button>',
  '<span id="viewer-n"></span>',
  '<button id="viewer-next" class="btn" type="button" aria-label="다음 사진">›</button>',
  '<button id="viewer-close" class="btn" type="button">닫기</button>',
  '</div>',
  '</div>',
  '<p id="toast" class="toast" role="status" hidden></p>'
].join('\n');

/* 페이지의 스크립트 — 브라우저에는 아래 함수의 **소스 글자 그대로** 나갑니다
 * (INBOX_JS = 함수.toString(), 줄바꿈만 LF 로). 서버에서는 한 번도 부르지 않습니다.
 * 여기를 고치면 해시가 저절로 따라갑니다. 컴퓨터 브라우저용이라 요즘 문법(const · 화살표 ·
 * async)을 씁니다. 안의 주석도 페이지로 나가므로 짧게 둡니다.
 *
 * 흐름
 *   켜짐   저장된 토큰(sessionStorage → localStorage)이 있으면 GET /api/me 로 확인 — 운영자면
 *          목록, 401 이면 로그인 칸, 운영자가 아니면 그 토큰을 끊고 로그인 칸. 서버에 못 닿으면
 *          목록 자리에 까닭과 「다시 시도」.
 *   목록   새것부터 30건. 「더 보기」 는 nextBefore 로. 「안 읽은 것만」 일 때 받아 둔 쪽에
 *          안 읽은 것이 서버의 수보다 적으면 다음 쪽을 저절로 받습니다(한 번에 열 쪽까지).
 *          새로고침은 첫 쪽만 다시 받아 그 범위를 갈아 끼웁니다 — 「더 보기」 로 받아 둔 옛 쪽은
 *          그대로. 탭으로 돌아왔을 때 30초가 지났으면 저절로 새로고침.
 *   자세히 고르면 읽음(앱과 같음 — 화면 먼저, 못 닿으면 되돌림). 사진은 그때 받아 blob URL 로,
 *          다른 의견으로 가거나 목록으로 돌아가거나 지우거나 로그아웃하면 revoke.
 *   키     j · k 로 위아래(한글 자판이어도 — 키 자리로 봄), Esc 로 사진 닫기 · 묻기 취소 ·
 *          (좁은 화면) 목록으로. 사진을 크게 볼 때 ← → 로 넘김.
 */
function inboxScript() {
  'use strict';
  const KEY = 'mybody-inbox-token';
  const FILTER_KEY = 'mybody-inbox-unread-only';
  const PAGE = 30;
  const AUTO_PAGES = 10;
  const TITLE = '의견함 · Mybody';
  const $ = id => document.getElementById(id);
  const S = {
    token: '', items: [], unread: 0, nextBefore: null, sel: null, unreadOnly: false,
    gen: 0, loading: false, loadingMore: false, readingAll: false, auto: 0, lastLoad: 0,
    detailGen: 0, urls: [], shots: [], view: -1, busyLogin: false
  };

  /* 요소 만들기 — 글자는 늘 글자로(textContent). */
  const el = (tag, attrs, kids) => {
    const n = document.createElement(tag);
    if (attrs) {
      for (const k of Object.keys(attrs)) {
        const v = attrs[k];
        if (v === null || v === undefined || v === false) continue;
        if (k === 'class') n.className = v;
        else n.setAttribute(k, v === true ? '' : String(v));
      }
    }
    for (const c of [].concat(kids === undefined ? [] : kids)) {
      if (c === null || c === undefined || c === false) continue;
      n.append(typeof c === 'string' ? document.createTextNode(c) : c);
    }
    return n;
  };
  const two = v => (v < 10 ? '0' : '') + v;
  /* 한국 시각(UTC+9, 서머타임 없음) — 이 컴퓨터의 시간대와 상관없이. */
  const kst = (iso, full) => {
    const t = Date.parse(iso);
    if (!Number.isFinite(t)) return '';
    const d = new Date(t + 9 * 3600000);
    const y = d.getUTCFullYear();
    const s = (d.getUTCMonth() + 1) + '월 ' + d.getUTCDate() + '일 ' + two(d.getUTCHours()) + ':' + two(d.getUTCMinutes());
    return full || y !== new Date(Date.now() + 9 * 3600000).getUTCFullYear() ? y + '년 ' + s : s;
  };
  const who = it => it.from ? (it.from.name || '이름 없음') : '익명';
  const osName = p => p === 'android' ? 'Android' : p === 'ios' ? 'iOS' : p;
  const find = id => S.items.find(i => i.id === id) || null;
  const narrow = () => window.matchMedia('(max-width: 800px)').matches;
  /* 서버가 준 한 건을 쓸 모양으로 — 모양이 틀린 것은 버립니다. */
  const clean = it => {
    if (!it || typeof it !== 'object' || !Number.isSafeInteger(it.id) || it.id < 1) return null;
    const s = v => typeof v === 'string' && v ? v : null;
    return {
      id: it.id, createdAt: s(it.createdAt) || '', appVersion: s(it.appVersion),
      platform: s(it.platform), screen: s(it.screen),
      text: typeof it.text === 'string' ? it.text : '', read: it.read === true,
      images: Array.isArray(it.images)
        ? it.images.filter(i => i && Number.isSafeInteger(i.n) && i.n > 0).map(i => ({ n: i.n })) : [],
      from: it.from && typeof it.from === 'object'
        ? { name: typeof it.from.name === 'string' ? it.from.name : '' } : null
    };
  };

  /* 토큰 — 기본은 이 탭(sessionStorage), 「로그인 유지」 면 localStorage. 못 쓰는 브라우저면 메모리만. */
  const box = kind => {
    try { return kind === 'local' ? window.localStorage : window.sessionStorage; } catch (e) { return null; }
  };
  const savedToken = () => {
    for (const k of ['session', 'local']) {
      try { const b = box(k); const v = b && b.getItem(KEY); if (v) return v; } catch (e) {}
    }
    return '';
  };
  const forget = () => {
    for (const k of ['session', 'local']) {
      try { const b = box(k); if (b) b.removeItem(KEY); } catch (e) {}
    }
  };
  const keep = (tok, long) => {
    forget();
    try { const b = box(long ? 'local' : 'session'); if (b) b.setItem(KEY, tok); } catch (e) {}
  };

  /* API 한 번. token 을 안 주면 지금 로그인. asBlob 이면 성공일 때 바이트. */
  async function call(method, path, body, token, asBlob) {
    const tok = token === undefined ? S.token : token;
    const headers = {};
    if (tok) headers.Authorization = 'Bearer ' + tok;
    if (body !== undefined) headers['Content-Type'] = 'application/json';
    const ac = typeof AbortController === 'function' ? new AbortController() : null;
    const timer = ac ? setTimeout(() => ac.abort(), asBlob ? 60000 : 20000) : 0;
    try {
      const r = await fetch('/api' + path, {
        method, headers, cache: 'no-store', credentials: 'omit',
        body: body === undefined ? undefined : JSON.stringify(body),
        signal: ac ? ac.signal : undefined
      });
      if (asBlob && r.ok) {
        return { ok: true, status: r.status, blob: await r.blob(), type: r.headers.get('content-type') || '' };
      }
      let j = null;
      try { j = await r.json(); } catch (e) {}
      if (!j || typeof j !== 'object') j = {};
      const why = typeof j.error === 'string' && j.error ? j.error
        : typeof j.reason === 'string' && j.reason ? j.reason : '서버 오류 (' + r.status + ')';
      return { ok: r.ok && j.ok !== false, status: r.status, body: j, reason: why };
    } catch (e) {
      return { ok: false, status: 0, body: {}, reason: '서버에 닿지 않아요' };
    } finally {
      if (timer) clearTimeout(timer);
    }
  }

  /* 로그인이 끊겼거나(401) 운영자가 아니면(403) 로그인 칸으로. 그렇게 했으면 true. */
  function gate(r) {
    if (!S.token) return true;
    if (r.status === 401) { out('로그인이 끊겼어요 · 다시 로그인해 주세요', false); return true; }
    if (r.status === 403) { out('운영자 계정만 볼 수 있어요', true); return true; }
    return false;
  }
  /* 나가기 — 화면 · 저장소를 비우고 로그인 칸. signout 이면 서버의 로그인도 끊습니다. */
  function out(msg, signout, calm) {
    const tok = S.token;
    S.token = '';
    S.gen++;
    forget();
    wipe();
    showLogin(msg, calm);
    return signout && tok ? call('POST', '/auth/signout', undefined, tok) : Promise.resolve();
  }
  function wipe() {
    deselect();
    S.items = []; S.unread = 0; S.nextBefore = null;
    S.loading = S.loadingMore = S.readingAll = false;
    showErr('');
    $('list').replaceChildren();
    document.title = TITLE;
  }
  function showLogin(msg, calm) {
    $('boot').hidden = true;
    $('inbox').hidden = true;
    $('login').hidden = false;
    loginMsg(msg || '', calm);
    $('password').value = '';
    ($('handle').value ? $('password') : $('handle')).focus();
  }
  function loginMsg(msg, calm) {
    const m = $('login-msg');
    m.textContent = msg;
    m.hidden = !msg;
    m.classList.toggle('calm', !!calm);
  }
  function showInbox() {
    $('boot').hidden = true;
    $('login').hidden = true;
    $('inbox').hidden = false;
    loginMsg('');
    if (S.sel === null) deselect();
  }
  function showErr(msg) {
    $('err-text').textContent = msg;
    $('err').hidden = !msg;
  }
  let toastTimer = 0;
  function toast(msg) {
    const t = $('toast');
    t.textContent = msg;
    t.hidden = false;
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => { t.hidden = true; }, 2500);
  }

  async function login(e) {
    e.preventDefault();
    if (S.busyLogin) return;
    const handle = $('handle').value.trim();
    const password = $('password').value;
    if (!handle || !password) { loginMsg('아이디와 비밀번호를 넣어 주세요'); return; }
    const btn = $('login-btn');
    S.busyLogin = true;
    btn.disabled = true;
    btn.textContent = '확인 중…';
    loginMsg('');
    try {
      const r = await call('POST', '/auth/signin', { handle, password }, '');
      if (!r.ok || typeof r.body.token !== 'string' || !r.body.token) { loginMsg(r.reason); return; }
      const tok = r.body.token;
      const me = await call('GET', '/me', undefined, tok);
      if (me.ok && me.body.user && me.body.user.isOperator === true) {
        S.token = tok;
        keep(tok, $('keep').checked);
        $('password').value = '';
        showInbox();
        load();
        return;
      }
      /* 운영자가 아니면(확인을 못 했어도) 방금 받은 로그인을 바로 끊습니다. */
      await call('POST', '/auth/signout', undefined, tok);
      $('password').value = '';
      loginMsg(me.ok ? '운영자 계정만 볼 수 있어요' : me.reason);
    } finally {
      S.busyLogin = false;
      btn.disabled = false;
      btn.textContent = '로그인';
    }
  }
  function logout() {
    return out('로그아웃했어요', true, true);
  }

  /* --- 목록 --- */
  async function load() {
    if (!S.token) return;
    const gen = ++S.gen;
    S.loading = true;
    S.loadingMore = false;
    S.auto = 0;
    paintBusy();
    const r = await call('GET', '/feedback/inbox?limit=' + PAGE);
    if (gen !== S.gen) return;
    S.loading = false;
    S.lastLoad = Date.now();
    paintBusy();
    if (!r.ok) { if (!gate(r)) { showErr(r.reason); paint(); } return; }
    showErr('');
    mergeTop(r.body);
    const cur = S.sel === null ? null : find(S.sel);
    if (S.sel !== null && !cur) deselect('다른 곳에서 지워진 의견이에요');
    /* 보고 있는 것은 읽은 것 — 읽음 표시보다 먼저 떠난 목록 요청이 "안 읽음" 으로 되돌렸으면 다시. */
    else if (cur && !cur.read) markRead(cur);
    paint();
    autoFill();
  }
  /* 첫 쪽이 덮는 범위(그 쪽의 가장 작은 번호 이상)는 새것으로 갈아 끼우고, 그보다 옛것은 그대로.
     단 새 첫 쪽이 받아 둔 것과 이어질 때만 — 그사이 서른 건 넘게 와서 틈이 생겼으면 옛것을 버리고
     처음부터(안 그러면 틈에 든 의견을 「더 보기」 로도 못 받습니다). */
  function mergeTop(b) {
    const fresh = (Array.isArray(b.items) ? b.items : []).map(clean).filter(Boolean);
    const last = Number.isSafeInteger(b.nextBefore) ? b.nextBefore : null;
    const floor = last !== null && fresh.length ? Math.min.apply(null, fresh.map(i => i.id)) : 0;
    const top = S.items.length ? Math.max.apply(null, S.items.map(i => i.id)) : 0;
    const older = floor && floor <= top ? S.items.filter(i => i.id < floor) : [];
    S.items = fresh.concat(older);
    S.nextBefore = !floor ? null : older.length ? S.nextBefore : last;
    S.unread = Number.isSafeInteger(b.unread) && b.unread >= 0 ? b.unread : 0;
  }
  async function more() {
    const before = S.nextBefore;
    if (before === null || S.loading || S.loadingMore || !S.token) return;
    const gen = S.gen;
    S.loadingMore = true;
    paint();
    const r = await call('GET', '/feedback/inbox?limit=' + PAGE + '&before=' + before);
    if (gen !== S.gen) return;
    S.loadingMore = false;
    if (!r.ok) { if (!gate(r)) { showErr(r.reason); paint(); } return; }
    const have = new Set(S.items.map(i => i.id));
    const got = (Array.isArray(r.body.items) ? r.body.items : []).map(clean).filter(i => i && !have.has(i.id));
    S.items = S.items.concat(got);
    const next = r.body.nextBefore;
    /* 다음 번호는 이번 것보다 작아야 — 아니면(서버의 실수) 같은 쪽을 끝없이 받지 않게 멈춤. */
    S.nextBefore = got.length && Number.isSafeInteger(next) && next < before ? next : null;
    if (Number.isSafeInteger(r.body.unread) && r.body.unread >= 0) S.unread = r.body.unread;
    paint();
    autoFill();
  }
  function autoFill() {
    if (!S.unreadOnly || S.nextBefore === null || S.auto >= AUTO_PAGES) return;
    if (S.items.filter(i => !i.read).length >= S.unread) return;
    S.auto++;
    more();
  }
  function setFilter(only) {
    if (S.unreadOnly === only) return;
    S.unreadOnly = only;
    S.auto = 0;
    try { const b = box('local'); if (b) { if (only) b.setItem(FILTER_KEY, '1'); else b.removeItem(FILTER_KEY); } } catch (e) {}
    paint();
    autoFill();
  }
  const visible = () => S.unreadOnly ? S.items.filter(i => !i.read || i.id === S.sel) : S.items;

  function row(it) {
    const chips = [];
    if (it.appVersion) chips.push(el('span', { class: 'chip', title: '판' }, it.appVersion));
    if (it.platform) chips.push(el('span', { class: 'chip', title: '기종' }, osName(it.platform)));
    if (it.screen) chips.push(el('span', { class: 'chip', title: '보던 화면' }, it.screen));
    if (it.images.length) chips.push(el('span', { class: 'chip' }, '사진 ' + it.images.length));
    const text = it.text.replace(/\s+/g, ' ').trim();
    const sel = it.id === S.sel;
    return el('li', null, el('button', {
      type: 'button', class: 'row' + (it.read ? '' : ' unread') + (sel ? ' sel' : ''),
      'data-id': it.id, 'aria-current': sel ? 'true' : null
    }, [
      el('span', { class: 'top' }, [
        it.read ? null : el('span', { class: 'dot', role: 'img', 'aria-label': '안 읽음' }),
        el('span', { class: 'from' }, who(it)),
        el('span', { class: 'time' }, kst(it.createdAt))
      ]),
      chips.length ? el('span', { class: 'chips' }, chips) : null,
      el('span', { class: 'preview' + (text ? '' : ' none') }, text ? text.slice(0, 300) : '글 없이 사진만')
    ]));
  }
  function paint() {
    const list = $('list');
    const focusIn = list.contains(document.activeElement);
    const frag = document.createDocumentFragment();
    const vis = visible();
    for (const it of vis) frag.append(row(it));
    list.replaceChildren(frag);
    const empty = $('empty');
    empty.hidden = vis.length > 0;
    empty.textContent = S.loading || S.loadingMore ? '불러오는 중…'
      : S.unreadOnly && S.items.length ? '안 읽은 의견이 없어요' : '아직 의견이 없어요';
    const m = $('more');
    m.hidden = S.nextBefore === null;
    m.disabled = S.loadingMore;
    m.textContent = S.loadingMore ? '불러오는 중…' : '더 보기';
    const u = $('unread');
    u.hidden = !S.unread;
    u.textContent = '안 읽음 ' + S.unread;
    $('read-all').disabled = !S.unread || S.readingAll;
    $('f-unread').setAttribute('aria-pressed', String(S.unreadOnly));
    $('f-all').setAttribute('aria-pressed', String(!S.unreadOnly));
    document.title = (S.unread ? '(' + S.unread + ') ' : '') + TITLE;
    if (focusIn) { const b = list.querySelector('.row.sel'); if (b) b.focus({ preventScroll: true }); }
  }
  function paintBusy() {
    const b = $('refresh');
    b.disabled = S.loading;
    b.textContent = S.loading ? '불러오는 중…' : '새로고침';
    if (!S.items.length) paint();
  }

  function markRead(it) {
    it.read = true;
    S.unread = Math.max(0, S.unread - 1);
    const gen = S.gen;
    call('POST', '/feedback/inbox/' + it.id + '/read').then(r => {
      if (r.ok || r.status === 404 || gen !== S.gen) return;
      if (gate(r)) return;
      const cur = find(it.id);
      if (cur && cur.read) { cur.read = false; S.unread++; paint(); }
    });
  }
  async function readAll() {
    if (!S.unread || S.readingAll) return;
    const gen = S.gen;
    const was = new Map(S.items.map(i => [i.id, i.read]));
    const unread = S.unread;
    /* 받아 둔 것 중 가장 새 번호까지만 — 이 목록을 받은 뒤에 온 의견은 본 적이 없습니다. */
    const upTo = S.items.length ? Math.max.apply(null, S.items.map(i => i.id)) : null;
    S.readingAll = true;
    for (const i of S.items) i.read = true;
    S.unread = 0;
    paint();
    const r = await call('POST', '/feedback/inbox/read-all', upTo ? { upTo } : {});
    S.readingAll = false;
    if (gen !== S.gen) { paint(); return; }
    if (!r.ok) {
      if (gate(r)) return;
      for (const i of S.items) if (was.has(i.id)) i.read = was.get(i.id);
      S.unread = unread;
      paint();
      toast(r.reason);
      return;
    }
    toast('모두 읽음으로 표시했어요');
    load();
  }

  /* --- 자세히 --- */
  function select(id) {
    const it = find(id);
    if (!it) return;
    if (S.sel !== id) { drop(); S.sel = id; paintDetail(it); }
    if (!it.read) markRead(it);
    document.body.classList.add('show-detail');
    paint();
    const b = $('list').querySelector('.row.sel');
    if (b && !narrow()) b.scrollIntoView({ block: 'nearest' });
    if (narrow()) window.scrollTo(0, 0);
  }
  /* 보던 자세히를 떠남 — 늦게 오는 사진은 버리고, 만든 blob URL 은 revoke. */
  function drop() {
    S.detailGen++;
    closeViewer();
    for (const u of S.urls) { try { URL.revokeObjectURL(u); } catch (e) {} }
    S.urls = [];
    S.shots = [];
  }
  function deselect(msg) {
    drop();
    const had = S.sel !== null;
    S.sel = null;
    document.body.classList.remove('show-detail');
    $('detail').replaceChildren(el('p', { class: 'placeholder' }, msg || '왼쪽에서 의견을 고르세요 · j / k 로 위아래'));
    if (had) paint();
  }
  function paintDetail(it) {
    const gen = S.detailGen;
    const info = [
      ['받은 시각', kst(it.createdAt, true) + ' (한국 시각)'],
      ['보낸 사람', who(it)],
      ['판', it.appVersion],
      ['기종', it.platform && osName(it.platform)],
      ['보던 화면', it.screen],
      ['번호', '#' + it.id]
    ].filter(p => p[1]);
    const dl = el('dl', { class: 'meta' }, [].concat.apply([], info.map(p => [el('dt', null, p[0]), el('dd', null, p[1])])));
    const text = it.text.trim()
      ? el('div', { class: 'd-text', id: 'd-text' }, it.text)
      : el('p', { class: 'd-text none', id: 'd-text' }, '글 없이 사진만 보냈어요');
    const shots = el('div', { class: 'shots' });
    it.images.forEach((im, i) => {
      const img = el('img', { alt: '사진 ' + im.n });
      const btn = el('button', { type: 'button', class: 'shot wait', 'data-i': i, 'aria-label': '사진 ' + im.n + ' 크게 보기' }, img);
      shots.append(btn);
      const shot = { n: im.n, url: '', img, btn };
      S.shots.push(shot);
      loadShot(it.id, shot, gen);
    });
    const ask = el('div', { class: 'confirm', id: 'confirm', role: 'alertdialog', 'aria-labelledby': 'confirm-q', hidden: true }, [
      el('p', { id: 'confirm-q' }, '이 의견을 지울까요? 사진도 같이 지워지고 되돌릴 수 없어요.'),
      el('div', { class: 'confirm-btns' }, [
        el('button', { type: 'button', class: 'btn', id: 'del-no' }, '취소'),
        el('button', { type: 'button', class: 'btn danger solid', id: 'del-yes' }, '지우기')
      ]),
      el('p', { class: 'msg', id: 'del-msg', hidden: true })
    ]);
    /* replaceChildren 은 null 도 "null" 이라는 글자로 넣습니다 — 있는 것만 넘깁니다. */
    const parts = [
      el('div', { class: 'd-head' }, [
        el('button', { type: 'button', class: 'btn back', id: 'back' }, '← 목록'),
        el('h2', null, who(it)),
        el('button', { type: 'button', class: 'btn danger', id: 'del' }, '지우기')
      ]),
      ask, dl, text
    ];
    if (it.images.length) parts.push(shots);
    $('detail').replaceChildren(...parts);
  }
  async function loadShot(id, shot, gen) {
    const r = await call('GET', '/feedback/inbox/' + id + '/image/' + shot.n, undefined, undefined, true);
    if (gen !== S.detailGen) return;
    shot.btn.classList.remove('wait');
    if (!r.ok) {
      if ((r.status === 401 || r.status === 403) && gate(r)) return;
      shot.btn.classList.add('broken');
      shot.btn.disabled = true;
      shot.btn.replaceChildren('사진을 못 불러왔어요');
      return;
    }
    /* 받은 형식은 PNG · JPEG 만 그대로 — 그 밖은 그림으로만 쓰이게 이름 없는 바이트로. */
    const type = /^image\/(png|jpeg)$/.test(r.type) ? r.type : 'application/octet-stream';
    const url = URL.createObjectURL(new Blob([r.blob], { type }));
    S.urls.push(url);
    shot.url = url;
    shot.img.src = url;
  }
  function askDelete(show) {
    const c = $('confirm');
    if (!c) return;
    c.hidden = !show;
    $('del').disabled = show;
    $('del-msg').hidden = true;
    (show ? $('del-no') : $('del')).focus();
  }
  async function doDelete() {
    const id = S.sel;
    if (id === null || !find(id)) return;
    const yes = $('del-yes');
    const no = $('del-no');
    yes.disabled = no.disabled = true;
    yes.textContent = '지우는 중…';
    const r = await call('DELETE', '/feedback/inbox/' + id);
    /* 404 는 그사이 이미 지워진 것 — 바란 대로 없어졌으니 같은 결과입니다. */
    if (r.ok || r.status === 404) {
      const cur = find(id);
      if (cur) {
        if (!cur.read) S.unread = Math.max(0, S.unread - 1);
        S.items = S.items.filter(i => i.id !== id);
      }
      if (S.sel === id) deselect('지웠어요');
      paint();
      toast('지웠어요');
      return;
    }
    if (gate(r) || S.sel !== id) return;
    yes.disabled = no.disabled = false;
    yes.textContent = '지우기';
    const m = $('del-msg');
    m.textContent = r.reason;
    m.hidden = false;
  }

  /* --- 사진 크게 --- */
  function openViewer(i) {
    const s = S.shots[i];
    if (!s || !s.url) return;
    S.view = i;
    const img = $('viewer-img');
    img.src = s.url;
    img.alt = '사진 ' + s.n;
    const many = S.shots.length > 1;
    $('viewer-n').textContent = many ? (i + 1) + ' / ' + S.shots.length : '';
    $('viewer-prev').hidden = $('viewer-next').hidden = !many;
    $('viewer').hidden = false;
    $('viewer-close').focus();
  }
  function closeViewer() {
    const v = $('viewer');
    if (v.hidden) return;
    v.hidden = true;
    $('viewer-img').removeAttribute('src');
    const s = S.shots[S.view];
    S.view = -1;
    if (s && s.btn.isConnected) s.btn.focus();
  }
  function stepViewer(d) {
    const n = S.shots.length;
    if (n < 2 || S.view < 0) return;
    for (let k = 1; k < n; k++) {
      const i = (S.view + d * k + n * n) % n;
      if (S.shots[i].url) { openViewer(i); return; }
    }
  }

  function step(d) {
    const vis = visible();
    if (!vis.length) return;
    let k = vis.findIndex(i => i.id === S.sel);
    k = k < 0 ? (d > 0 ? 0 : vis.length - 1) : Math.min(vis.length - 1, Math.max(0, k + d));
    if (vis[k].id !== S.sel) select(vis[k].id);
    const b = $('list').querySelector('.row.sel');
    if (b && !narrow()) b.focus({ preventScroll: true });
  }

  function wire() {
    $('login-form').addEventListener('submit', login);
    $('f-unread').addEventListener('click', () => setFilter(true));
    $('f-all').addEventListener('click', () => setFilter(false));
    $('read-all').addEventListener('click', () => { readAll(); });
    $('refresh').addEventListener('click', () => { if (!S.loading) load(); });
    $('retry').addEventListener('click', () => { if (!S.loading) load(); });
    $('logout').addEventListener('click', () => { logout(); });
    $('more').addEventListener('click', () => { more(); });
    $('list').addEventListener('click', e => {
      const b = e.target.closest('.row');
      if (b) select(Number(b.getAttribute('data-id')));
    });
    $('detail').addEventListener('click', e => {
      const t = e.target;
      if (t.closest('#back')) deselect();
      else if (t.closest('#del')) askDelete(true);
      else if (t.closest('#del-no')) askDelete(false);
      else if (t.closest('#del-yes')) doDelete();
      else {
        const s = t.closest('.shot');
        if (s && !s.disabled) openViewer(Number(s.getAttribute('data-i')));
      }
    });
    $('viewer').addEventListener('click', e => {
      if (e.target.closest('#viewer-prev')) stepViewer(-1);
      else if (e.target.closest('#viewer-next')) stepViewer(1);
      else closeViewer();
    });
    document.addEventListener('keydown', e => {
      if (e.ctrlKey || e.metaKey || e.altKey) return;
      if (!$('viewer').hidden) {
        if (e.key === 'Escape') { e.preventDefault(); closeViewer(); }
        else if (e.key === 'ArrowRight') { e.preventDefault(); stepViewer(1); }
        else if (e.key === 'ArrowLeft') { e.preventDefault(); stepViewer(-1); }
        return;
      }
      if ($('inbox').hidden) return;
      const t = e.target;
      if (t && t.closest && t.closest('input, textarea, select, [contenteditable]')) return;
      if (e.key === 'Escape') {
        const c = $('confirm');
        if (c && !c.hidden) askDelete(false);
        else if (S.sel !== null && narrow()) deselect();
        return;
      }
      if (e.code === 'KeyJ' || e.key === 'j') { e.preventDefault(); step(1); }
      else if (e.code === 'KeyK' || e.key === 'k') { e.preventDefault(); step(-1); }
    });
    document.addEventListener('visibilitychange', () => {
      if (document.visibilityState === 'visible' && S.token && !$('inbox').hidden && !S.loading &&
          Date.now() - S.lastLoad > 30000) load();
    });
  }

  async function boot() {
    try { const b = box('local'); S.unreadOnly = !!b && b.getItem(FILTER_KEY) === '1'; } catch (e) {}
    wire();
    const tok = savedToken();
    if (!tok) { showLogin(''); return; }
    S.token = tok;
    const me = await call('GET', '/me');
    if (me.status === 401) { S.token = ''; forget(); showLogin(''); return; }
    if (me.ok && !(me.body.user && me.body.user.isOperator === true)) { out('운영자 계정만 볼 수 있어요', true); return; }
    showInbox();
    load();
  }
  boot();
}

/* 줄바꿈은 LF 로 — 머리 주석의 "CSP" 참고. 스타일은 한 줄로 이어 붙인 글자라 줄바꿈이 없지만
   같은 규칙으로 둡니다. */
const lf = s => s.replace(/\r\n?/g, '\n');
const INBOX_JS = lf('(' + inboxScript.toString() + ')();');
const INBOX_STYLE = lf(INBOX_CSS);
const cspHash = s => "'sha256-" + crypto.createHash('sha256').update(s, 'utf8').digest('base64') + "'";
const INBOX_CSP = "default-src 'none'; script-src " + cspHash(INBOX_JS) + '; style-src ' + cspHash(INBOX_STYLE) +
  "; img-src 'self' blob:; connect-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'";
const INBOX_HEADERS = {
  'Content-Type': 'text/html; charset=utf-8',
  'Content-Security-Policy': INBOX_CSP,
  'Cache-Control': 'no-store',
  'Vary': '*',
  'X-Robots-Tag': 'noindex',
  'Referrer-Policy': 'no-referrer',
  'X-Frame-Options': 'DENY'
};
/* 페이지는 뜰 때 한 번 짓습니다 — 요청마다 달라지는 것이 없습니다. 아이콘은 웹 앱과 같은 파일
   (prototype · release 둘 다 assets/favicon-32.png 를 둠 — tools/build-release.js). */
const INBOX_HTML = lf('<!doctype html>\n<html lang="ko">\n<head>\n<meta charset="utf-8">\n' +
  '<meta name="viewport" content="width=device-width, initial-scale=1">\n' +
  '<meta name="robots" content="noindex">\n<meta name="referrer" content="no-referrer">\n' +
  '<meta name="color-scheme" content="light dark">\n' +
  '<link rel="icon" type="image/png" href="/assets/favicon-32.png">\n' +
  '<title>의견함 · Mybody</title>\n<style>' + INBOX_STYLE + '</style>\n</head>\n<body>\n' +
  INBOX_BODY + '\n<script>' + INBOX_JS + '</script>\n</body>\n</html>\n');

/** GET /inbox. send 는 server.js 의 것(기본 머리 — nosniff 등 — 를 같이 붙임). */
function serveInboxPage(req, res, url, send) {
  if (req.method !== 'GET' && req.method !== 'HEAD') {
    return send(res, 405, { ok: false, reason: '그런 방법으로는 열 수 없습니다' }, { Allow: 'GET, HEAD' });
  }
  /* /inbox/ 는 /inbox 로 — 받은 쿼리는 싣지 않습니다. */
  if (url.pathname !== '/inbox') {
    return send(res, 302, '', { Location: '/inbox', 'Content-Type': 'text/plain; charset=utf-8' });
  }
  return send(res, 200, INBOX_HTML, INBOX_HEADERS);
}

module.exports = { serveInboxPage, INBOX_HTML, INBOX_JS, INBOX_CSS: INBOX_STYLE, INBOX_CSP, INBOX_HEADERS };
