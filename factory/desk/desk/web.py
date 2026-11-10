"""비서 웹 — 연구실 · 노트북 브라우저에서 쓰는 비서 화면 (주인 11월 9일).

    브라우저 ──테일넷──▶ 폰 서버(:7071) /web
        폰 비서 앱과 같은 길(/ask · /talk · /notices · /screen · /input …)을 쓰고, 화면만 큰 화면 · 마우스 · 키보드에 맞춤.
        - 왼쪽: 비서와 대화(글 · 말) · 주인 확인 알림
        - 오른쪽: 맥 화면 보기와 조작(클릭 · 두 번 · 오른쪽 · 휠 · 끌기 · 글자) · 화면 · 핸드마우스 · 음량

/web 의 HTML 자체에는 비밀이 없어 열쇠 없이 주고(테일넷 · 127.0.0.1 에서만), 열쇠는 처음 한 번 붙여 넣으면
그 브라우저에만 남깁니다(주소창 · 방문 기록에 안 남게). 모든 요청은 X-Desk-Token 으로 phone.py 가 검사합니다.

주로 논문 정리 웹 안(https://<맥>.ts.net:8443/desk/web — 그쪽 로그인, 열쇠는 그 서버가 붙임)에서 씁니다.
말하기(마이크)는 브라우저가 https 에서만 허락합니다 — 그냥 http://100.x 주소에서는 글로만 씁니다.
"""
from __future__ import annotations

import hashlib

WEB = r"""<!doctype html><html lang="ko"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="color-scheme" content="light dark">
<title>책상 비서</title>
<link rel="icon" href="data:,">
<style>
:root{--bg:#f6f7f9;--panel:#fff;--line:#d9dde3;--ink:#1b1f24;--sub:#5b6470;--me:#dbe8ff;--ai:#eef0f3;--acc:#1f6feb;--acc-ink:#fff;
 --warn-bg:#fff4d6;--warn:#8a5a00;--ok:#1a7f37;--bad:#cf222e;--scr:#111}
@media (prefers-color-scheme:dark){:root:not([data-theme="light"]){--bg:#0d1117;--panel:#161b22;--line:#30363d;--ink:#e6edf3;--sub:#8b949e;
 --me:#1f6feb40;--ai:#21262d;--acc:#2f81f7;--acc-ink:#fff;--warn-bg:#e3b34122;--warn:#e3b341;--ok:#3fb950;--bad:#f85149;--scr:#000}}
:root[data-theme="dark"]{--bg:#0d1117;--panel:#161b22;--line:#30363d;--ink:#e6edf3;--sub:#8b949e;
 --me:#1f6feb40;--ai:#21262d;--acc:#2f81f7;--acc-ink:#fff;--warn-bg:#e3b34122;--warn:#e3b341;--ok:#3fb950;--bad:#f85149;--scr:#000}
*{box-sizing:border-box}
html,body{margin:0;height:100%;background:var(--bg);color:var(--ink);font:15px/1.5 system-ui,-apple-system,"Apple SD Gothic Neo","Malgun Gothic",sans-serif}
body{display:flex;flex-direction:column}
button,input,textarea,select{font:inherit;color:inherit}
button{border:1px solid var(--line);background:var(--panel);border-radius:8px;padding:6px 10px;cursor:pointer;white-space:nowrap}
button:hover{border-color:var(--acc)}button:disabled{opacity:.5;cursor:default}
button.on{background:var(--acc);border-color:var(--acc);color:var(--acc-ink)}
button.pri{background:var(--acc);border-color:var(--acc);color:var(--acc-ink);font-weight:600}
input,textarea{background:var(--bg);border:1px solid var(--line);border-radius:8px;padding:8px 10px;min-width:0}
input:focus,textarea:focus{outline:2px solid var(--acc);outline-offset:-1px}
#app{flex:1;min-height:0;display:grid;grid-template-columns:minmax(320px,420px) 1fr}
header{display:flex;flex-wrap:wrap;align-items:center;gap:12px;padding:8px 14px;background:var(--panel);border-bottom:1px solid var(--line)}
header h1{font-size:16px;margin:0}
#mode{font-size:13px;color:var(--sub)}#mode b{color:var(--ok)}#mode.off b{color:var(--bad)}
header .sp{flex:1}
a.hb{color:inherit;text-decoration:none;border:1px solid var(--line);border-radius:8px;padding:6px 10px}a.hb:hover{border-color:var(--acc)}
#tabs{display:flex;gap:4px}#tabs button{border-radius:999px;padding:5px 14px}
#left{display:flex;flex-direction:column;min-height:0;border-right:1px solid var(--line);background:var(--panel)}
#chat{flex:1;overflow:auto;padding:12px}
.m{margin:8px 0;padding:9px 12px;border-radius:12px;max-width:92%;white-space:pre-wrap;word-break:break-word}
.m .t{display:block;font-size:12px;color:var(--sub);margin-top:2px}
.me{background:var(--me);margin-left:auto}.ai{background:var(--ai)}
.need{background:var(--warn-bg);border:1px solid var(--warn)}.need b{color:var(--warn)}
.sys{color:var(--sub);font-size:13px;text-align:center;max-width:none}
.wait{color:var(--sub)}
#empty{color:var(--sub);text-align:center;margin-top:30%;padding:0 20px}
#form{border-top:1px solid var(--line);padding:10px;display:flex;flex-direction:column;gap:8px}
#msg{resize:none;height:64px}
#row{display:flex;gap:8px;align-items:center}#row .sp{flex:1}
#mic.rec{background:var(--bad);border-color:var(--bad);color:#fff}
#hint{font-size:12px;color:var(--sub)}
#right{display:flex;flex-direction:column;min-height:0;min-width:0}
#tools{display:flex;flex-wrap:wrap;gap:6px;padding:8px 12px;align-items:center;border-bottom:1px solid var(--line);background:var(--panel)}
#tools .g{display:flex;gap:6px;align-items:center;padding-right:10px;border-right:1px solid var(--line)}
#tools .g:last-child{border-right:0}
#vol{width:110px}#volv{width:3.2em;font-size:13px;color:var(--sub)}
#view{flex:1;min-height:0;background:var(--scr);position:relative;overflow:hidden}
#viewmsg{position:absolute;inset:0;display:none;align-items:center;justify-content:center;color:#ccc;text-align:center;padding:20px}
#keys{display:flex;gap:6px;padding:8px 12px;border-top:1px solid var(--line);background:var(--panel);align-items:center}
#keys input{flex:1}
#st{font-size:13px;color:var(--sub);min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
#login{position:fixed;inset:0;background:var(--bg);display:none;align-items:center;justify-content:center;padding:16px;z-index:9}
#login form{background:var(--panel);border:1px solid var(--line);border-radius:12px;padding:22px;max-width:420px;width:100%;display:flex;flex-direction:column;gap:10px}
#login h2{margin:0;font-size:18px}#login p{margin:0;color:var(--sub);font-size:14px}#login .err{color:var(--bad)}
code{font-size:13px;background:var(--ai);padding:1px 5px;border-radius:5px}
@media (max-width:820px){#app{grid-template-columns:1fr;grid-template-rows:55% 45%}#left{border-right:0;border-bottom:1px solid var(--line)}
 #tools{flex-wrap:nowrap;overflow-x:auto}#tools .g{flex:none}}
/* ── 강의자료 ── */
#study{flex:1;min-height:0;display:none;grid-template-columns:280px 1fr 360px}
#study.show{display:grid}
#sl{display:flex;flex-direction:column;min-height:0;border-right:1px solid var(--line);background:var(--panel)}
#sl .top{padding:10px;display:flex;flex-direction:column;gap:8px;border-bottom:1px solid var(--line)}
#sq{width:100%}
#slist{flex:1;overflow:auto;padding:6px}
.crs{border-radius:10px;padding:8px 10px;cursor:pointer;display:flex;gap:8px;align-items:center}
.crs:hover{background:var(--ai)}.crs.sel{background:var(--me)}
.crs .nm{flex:1;font-weight:600;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.dday{font-size:12px;font-weight:700;padding:1px 7px;border-radius:999px;background:var(--ai);color:var(--sub)}
.dday.soon{background:var(--warn-bg);color:var(--warn)}.dday.past{opacity:.6}
.prog{font-size:12px;color:var(--sub)}
.files{margin:2px 0 8px 8px;border-left:2px solid var(--line);padding-left:6px}
.fl{display:flex;gap:8px;align-items:center;padding:5px 8px;border-radius:8px;cursor:pointer;font-size:14px}
.fl:hover{background:var(--ai)}.fl.sel{background:var(--me)}
.fl .nm{flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.fl .pg{font-size:12px;color:var(--sub)}
.dot{width:9px;height:9px;border-radius:50%;flex:none;border:2px solid var(--sub)}
.dot.reading{border-color:var(--acc);background:linear-gradient(90deg,var(--acc) 50%,transparent 50%)}
.dot.done{border-color:var(--ok);background:var(--ok)}.dot.review{border-color:var(--warn);background:var(--warn)}
.filt{display:flex;gap:4px;flex-wrap:wrap}.filt button{font-size:12px;padding:3px 9px;border-radius:999px}
.drop{margin:6px 8px 4px;border:2px dashed var(--line);border-radius:10px;padding:10px;text-align:center;color:var(--sub);font-size:13px;cursor:pointer}
.drop.over,#study.over .drop{border-color:var(--acc);color:var(--acc)}
.hit{padding:7px 9px;border-radius:8px;cursor:pointer;font-size:13px}.hit:hover{background:var(--ai)}
.hit b{font-size:13px}.hit .s{color:var(--sub);display:block;word-break:break-word}
.hit mark{background:var(--warn-bg);color:inherit}
.muted{color:var(--sub);font-size:13px;padding:8px 10px}
#sv{display:flex;flex-direction:column;min-width:0;min-height:0}
#svbar{display:flex;gap:6px;align-items:center;padding:8px 12px;border-bottom:1px solid var(--line);background:var(--panel);flex-wrap:wrap}
#svname{font-weight:600;flex:1;min-width:120px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
#svpage{width:70px}
.seg{display:flex}.seg button{border-radius:0;margin-left:-1px;font-size:13px;padding:5px 8px}
.seg button:first-child{border-radius:8px 0 0 8px}.seg button:last-child{border-radius:0 8px 8px 0}
#pdf{flex:1;border:0;width:100%;background:var(--scr)}
#svempty{flex:1;display:flex;align-items:center;justify-content:center;color:var(--sub);text-align:center;padding:30px}
#sp{display:flex;flex-direction:column;min-height:0;border-left:1px solid var(--line);background:var(--panel)}
#sptabs{display:flex;border-bottom:1px solid var(--line)}
#sptabs button{flex:1;border:0;border-radius:0;border-bottom:2px solid transparent;background:none;padding:9px 4px}
#sptabs button.on{border-bottom-color:var(--acc);color:var(--acc);font-weight:600}
.pane{flex:1;min-height:0;overflow:auto;padding:12px;display:none;flex-direction:column;gap:10px}
.pane.on{display:flex}
.md .h{font-weight:700;margin:6px 0 2px}.md .li{position:relative}.md .li::before{content:'•';position:absolute;margin-left:-10px;color:var(--sub)}.md .gap{height:6px}
.aih{display:flex;gap:8px;align-items:center}.aih b{flex:1;font-size:14px}
#ailog{flex:1;min-height:120px;overflow:auto;display:flex;flex-direction:column;gap:8px}
.qa .tag{display:block;font-size:11px;color:var(--sub);margin-bottom:2px}.qa.sys{background:none;color:var(--sub);font-size:12px;text-align:center}.qa.err{color:var(--bad)}
#p-ai.on{overflow:hidden}
#note{flex:1;min-height:240px;resize:none;line-height:1.6}
.saved{font-size:12px;color:var(--sub)}
.mk{display:flex;gap:8px;align-items:flex-start;padding:7px 9px;border-radius:8px;background:var(--ai);cursor:pointer}
.mk .p{font-weight:700;color:var(--acc);flex:none;min-width:3em}.mk .x{margin-left:auto;border:0;background:none;padding:0 4px;color:var(--sub)}
.addrow{display:flex;gap:6px}.addrow input{flex:1}
.chips{display:flex;flex-wrap:wrap;gap:6px}.chips button{font-size:13px}
.qa{white-space:pre-wrap;word-break:break-word;background:var(--ai);border-radius:10px;padding:9px 11px;font-size:14px}
.qa.q{background:var(--me)}
.field{display:flex;flex-direction:column;gap:4px;font-size:13px;color:var(--sub)}
.field input,.field textarea,.field select{color:var(--ink)}
select{background:var(--bg);border:1px solid var(--line);border-radius:8px;padding:7px 8px}
.todo{display:flex;gap:8px;align-items:center;font-size:14px}.todo.done span{text-decoration:line-through;color:var(--sub)}
.todo .x{margin-left:auto;border:0;background:none;color:var(--sub)}
button.danger{color:var(--bad)}
.err{color:var(--bad);font-size:13px}
#serr .err{padding:6px 10px}
@media (max-width:1100px){#study.show{grid-template-columns:240px 1fr}#sp{grid-column:1/-1;max-height:45vh;border-left:0;border-top:1px solid var(--line)}}
@media (max-width:700px){#study.show{grid-template-columns:1fr;overflow:auto;grid-auto-rows:auto}#sl{max-height:40vh;border-right:0}#sv{min-height:60vh}}
/* 과목 접기 · 펼치기 · 세 갈래 · 회독 색 띠 · 쪽 보기 · 진행 창 · 구석 표시 (11월 10일 20:23~20:35) */
.crs .arr{display:inline-block;width:1em;color:var(--sub);transition:transform .15s;flex:none}.crs .arr.open{transform:rotate(90deg)}
.crs:focus-visible{outline:2px solid var(--acc);outline-offset:-2px}
.grp{display:flex;align-items:center;gap:6px;margin:8px 0 2px;padding:0 4px}
.grp .gn{flex:1;font-size:12px;font-weight:700;color:var(--sub);letter-spacing:.02em}
button.mini{font-size:12px;padding:1px 7px;border-radius:999px}
.muted.sm{font-size:12px;padding:2px 8px}
.fl{border-left:3px solid hsl(var(--h,8) 36% 52%);border-radius:0 8px 8px 0}
.fl .rc{font-size:11px;color:hsl(var(--h,8) 30% 40%);font-weight:600}
.jb{font-size:11px;font-weight:700;padding:0 6px;border-radius:999px;background:var(--ai);color:var(--sub)}
.jb.run{color:var(--acc)}.jb.ok{color:var(--ok)}.jb.bad{color:var(--bad)}
.rd{display:inline-flex;align-items:center;gap:4px;border-left:3px solid hsl(var(--h,8) 36% 52%);padding-left:6px}
.rd button{padding:2px 7px}.rd b{font-size:13px;min-width:3.4em;text-align:center}
button.link{border:0;background:none;color:var(--acc);padding:4px 2px;font-size:13px;text-decoration:underline}
.kinds{display:flex;justify-content:center;gap:4px;margin-top:6px}.kinds button{font-size:12px;padding:2px 9px;border-radius:999px}
.pgnav{display:inline-flex;align-items:center;gap:4px}
#pv{flex:1;overflow:auto;position:relative;background:var(--scr);padding:8px 0;outline:0}
#pv .pgs{margin:0 auto;max-width:100%;display:flex;flex-direction:column;gap:8px;min-width:200px}
#pv .muted{color:#bbb;text-align:center;padding:40px}
.vpg{position:relative;background:#fff;width:100%;min-height:40px;box-shadow:0 1px 3px #0006}
.vpg img{display:block;width:100%;height:auto}
.vpg.ld img{display:none}
.vpg.ld{background:linear-gradient(100deg,#e9ebee 40%,#f6f7f8 50%,#e9ebee 60%) 0 0/300% 100%;animation:shim 1.2s linear infinite}
.vpg.fail{background:#f3e3e3}
@keyframes shim{to{background-position:-150% 0}}
@media (prefers-reduced-motion:reduce){.vpg.ld{animation:none}}
.vpg .pn{position:absolute;right:6px;bottom:4px;font-size:11px;color:#555;background:#fffc;border-radius:6px;padding:0 5px}
.hwst{font-size:14px;padding:8px 10px;border-radius:8px;background:var(--ai)}
.hwst.error{color:var(--bad)}.hwst.done{color:var(--ok)}
.hwp{display:grid;grid-template-columns:3.2em 1fr 64px;gap:4px 8px;align-items:center;font-size:13px;padding:6px 8px;border-radius:8px;background:var(--ai)}
.hwp.bad{outline:1px solid var(--bad)}.hwp .miss{grid-column:2/3;color:var(--warn);font-size:12px}.hwp input{padding:4px 6px}
#pm{position:fixed;inset:0;background:#0007;display:flex;align-items:center;justify-content:center;z-index:20;padding:16px}
#pm[hidden]{display:none}
#pm .box{background:var(--panel);border:1px solid var(--line);border-radius:14px;padding:20px;max-width:460px;width:100%;display:flex;flex-direction:column;gap:10px;box-shadow:0 10px 40px #0005}
.pmh{display:flex;gap:10px;align-items:flex-start}.pmh b{flex:1;font-size:16px;line-height:1.4}
.pbar{height:10px;border-radius:999px;background:var(--ai);overflow:hidden}
.pbar i{display:block;height:100%;width:0;background:var(--acc);border-radius:999px;transition:width .6s}.pbar i.bad{background:var(--bad)}
.pmrow{display:flex;gap:10px;align-items:baseline}.pmrow b{font-size:22px;min-width:3.2em}.pmrow span{color:var(--sub);font-size:13px}
#pmsteps{margin:0;padding-left:22px;font-size:14px;color:var(--sub);display:flex;flex-direction:column;gap:2px}
#pmsteps li.ok{color:var(--ok)}#pmsteps li.ok::marker{content:'✓  '}#pmsteps li.now{color:var(--ink);font-weight:600}#pmsteps li.bad{color:var(--bad);font-weight:600}
.pmbtns{display:flex;gap:8px;justify-content:flex-end;flex-wrap:wrap}.pmbtns:empty{display:none}
#pchip{position:fixed;right:14px;bottom:14px;z-index:15;display:flex;align-items:center;gap:7px;border-radius:999px;padding:5px 12px 5px 6px;font-size:13px;font-weight:700;box-shadow:0 2px 10px #0003}
#pchip[hidden]{display:none}
#pchip .ring{width:20px;height:20px;border-radius:50%;background:conic-gradient(var(--acc) calc(var(--p,0)*1%),var(--line) 0);-webkit-mask:radial-gradient(circle,transparent 6px,#000 6.5px);mask:radial-gradient(circle,transparent 6px,#000 6.5px)}
#pchip.done .ring{background:var(--ok)}#pchip.error .ring{background:var(--bad)}
#pchip.done{color:var(--ok)}#pchip.error{color:var(--bad)}
@media (prefers-color-scheme:dark){:root:not([data-theme="light"]) .fl,:root:not([data-theme="light"]) .rd{border-left-color:hsl(var(--h,8) 28% 55%)}:root:not([data-theme="light"]) .fl .rc{color:hsl(var(--h,8) 30% 68%)}}
:root[data-theme="dark"] .fl,:root[data-theme="dark"] .rd{border-left-color:hsl(var(--h,8) 28% 55%)}:root[data-theme="dark"] .fl .rc{color:hsl(var(--h,8) 30% 68%)}
/* 비서 탭: Claude 사용량 줄 · 두 화면 나란히 (11월 10일 20:29) */
#usage{display:flex;flex-wrap:wrap;gap:6px 16px;padding:6px 12px;border-bottom:1px solid var(--line);background:var(--panel);font-size:13px;color:var(--sub);align-items:center}
#usage .u{display:flex;align-items:center;gap:6px}#usage .u b{color:var(--ink)}
#usage .ub{width:70px;height:6px;border-radius:999px;background:var(--ai);overflow:hidden}#usage .ub i{display:block;height:100%;background:var(--ok)}
#usage .low .ub i{background:var(--warn)}#usage .out .ub i{background:var(--bad)}
#view.both{display:flex;gap:4px}
#view .scr{width:100%;height:100%;object-fit:contain;display:block;user-select:none;-webkit-user-drag:none;cursor:crosshair;min-width:0}
#view:not(.both) .scr:not(.cur){display:none}
#view.both .scr{flex:1 1 0}
</style></head><body>
<div id="login"><form id="lf">
 <h2>책상 비서</h2>
 <p>이 브라우저에서 처음이면 열쇠를 한 번 넣어 주세요. 이 브라우저에만 남아요.</p>
 <p>열쇠 찾는 곳: 맥 터미널에서 <code>cat ~/.config/desk/phone_token</code></p>
 <input id="lt" type="password" autocomplete="off" placeholder="열쇠" aria-label="열쇠">
 <p class="err" id="le"></p>
 <button class="pri" type="submit">들어가기</button>
</form></div>
<header><h1>책상 비서</h1><nav id="tabs"><button data-tab="desk" class="on">비서 · 맥</button><button data-tab="study">강의자료</button></nav>
 <span id="mode">연결 확인 중…</span><span class="sp"></span>
 <a id="home" href="/" style="display:none" class="hb">논문 정리</a><button id="theme" title="밝게 · 어둡게">테마</button><button id="out" title="이 브라우저에서 열쇠 지우기">나가기</button></header>
<div id="app">
 <section id="left">
  <div id="chat"><div id="empty">비서에게 글로 물어보세요.<br>예: 「오늘 승인할 거 있어?」 「논문 정리 웹 어디까지 됐어?」</div></div>
  <div id="form">
   <textarea id="msg" placeholder="비서에게 (Enter 보내기 · Shift+Enter 줄바꿈)" aria-label="비서에게 보낼 글"></textarea>
   <div id="row"><button id="mic">말하기</button><button id="stop" title="비서가 하던 말 · 일을 멈춤">멈춰</button><span class="sp"></span><button class="pri" id="send">보내기</button></div>
   <div id="hint"></div>
  </div>
 </section>
 <section id="right">
  <div id="usage" title="Claude 사용량 — Claude Code 상태줄이 넘겨 준 5시간 · 주간 한도 값. 못 받았으면 모름"></div>
  <div id="tools">
   <div class="g"><button data-s="2" class="on">두 화면</button><button data-s="0">주 화면</button><button data-s="1">세로 모니터</button></div>
   <div class="g"><button id="drag" title="켜 두면 누른 채 끈 만큼 맥에서 끌기">끌기</button></div>
   <div class="g"><button id="son">화면 켜기</button><button id="soff">화면 끄기</button><button id="scrm">주 화면 …</button><button id="scrd">세로 화면 …</button></div>
   <div class="g"><button id="hm">핸드마우스 …</button></div>
   <div class="g"><label for="vol">음량</label><input id="vol" type="range" min="0" max="100" disabled><span id="volv">…</span></div>
  </div>
  <div id="view" class="both"><img id="scr" class="scr cur" alt="맥 주 화면"><img id="scr1" class="scr cur" alt="맥 세로 모니터"><div id="viewmsg"></div></div>
  <div id="keys"><input id="typ" placeholder="맥에 글자 입력 (Enter 로 넣기)" aria-label="맥에 입력할 글"><button data-k="enter">⏎</button><button data-k="delete">⌫</button><button data-k="tab">Tab</button><button data-k="escape">Esc</button><span id="st"></span></div>
 </section>
</div>
<div id="study">
 <aside id="sl">
  <div class="top">
   <input id="sq" type="search" placeholder="모든 자료에서 찾기 (예: likelihood)" aria-label="자료 본문 찾기">
   <div class="filt" id="filt"><button data-f="" class="on">전체</button><button data-f="new">안 봄</button><button data-f="reading">보는 중</button><button data-f="review">다시 볼 것</button><button data-f="done">다 봄</button></div>
  </div>
  <div id="serr" role="alert"></div>
  <div id="slist"></div>
  <div class="drop" id="drop"><span id="droplabel">PDF 를 여기로 끌어 놓거나 눌러서 고르기</span>
   <div class="kinds" id="dkind" role="group" aria-label="올릴 자료의 종류"><button data-k="lecture" class="on">수업자료</button><button data-k="assignment">과제</button><button data-k="textbook">교과서</button></div>
   <input id="pick" type="file" accept="application/pdf,.pdf" multiple hidden></div>
  <div style="padding:0 8px 10px"><button id="addc" style="width:100%">+ 과목 추가</button></div>
 </aside>
 <section id="sv">
  <div id="svbar" style="display:none">
   <span id="svname"></span>
   <div class="seg" id="vseg" style="display:none"><button data-v="">과제 원본</button><button data-v="sheet">문제지</button><button data-v="solution">해설지</button></div>
   <span class="pgnav"><input id="svpage" type="number" min="1" aria-label="쪽 번호로 가기"><span id="svpages" class="muted" style="padding:0"></span></span>
   <span class="seg"><button id="zout" title="작게" aria-label="작게">−</button><button id="zin" title="크게" aria-label="크게">＋</button></span>
   <div class="seg" id="seg"><button data-st="new">안 봄</button><button data-st="reading">보는 중</button><button data-st="done">다 봄</button><button data-st="review">다시 볼 것</button></div>
   <span class="rd" id="rd"><button id="rdm" title="회독 하나 빼기" aria-label="회독 하나 빼기">−</button><b id="rdn">0회독</b><button id="rdp" title="회독 하나 더하기" aria-label="회독 하나 더하기">＋</button></span>
   <button id="stauto" class="link" style="display:none" title="직접 고른 상태 · 회독 수를 풀고, 열어 본 것으로 저절로 매기게">자동으로 되돌리기</button>
   <button id="svopen" title="PDF 를 통째로 받아 새 탭에서">PDF 받기</button>
  </div>
  <div id="svempty">왼쪽에서 자료를 고르세요.<br>PDF 를 이 화면 아무 데나 끌어 놓으면 고른 과목 · 고른 종류로 들어가요.</div>
  <div id="pv" style="display:none" tabindex="0" aria-label="자료 쪽들"></div>
 </section>
 <aside id="sp">
  <nav id="sptabs"><button data-p="note" class="on">메모</button><button data-p="marks">쪽 표시</button><button data-p="ai">비서에게</button><button data-p="hw" id="sptab-hw" style="display:none">과제</button><button data-p="course">과목</button></nav>
  <div class="pane on" id="p-note"><textarea id="note" placeholder="이 자료 메모. 쓰면 저절로 저장돼요." aria-label="자료 메모" disabled></textarea><span class="saved" id="saved"></span></div>
  <div class="pane" id="p-marks">
   <div class="addrow"><input id="mkp" type="number" min="1" placeholder="쪽" style="max-width:70px" aria-label="표시할 쪽"><input id="mkt" placeholder="한 줄 (예: 시험에 나온다 함)" aria-label="표시 내용"><button id="mkadd">표시</button></div>
   <div id="mklist"></div>
  </div>
  <div class="pane" id="p-ai">
   <div class="aih"><b id="aiwhat">과목을 고르면 그 과목 전담 비서와 이야기해요.</b><button id="ainew" class="mini" title="대화 세션만 새로 시작(기록은 남음)" disabled>새 대화</button></div>
   <div class="muted sm" id="aiprep" style="padding:0"></div>
   <div id="ailog"></div>
   <div class="chips" id="aichips"><button data-q="지금 보는 쪽을 처음 배우는 사람에게 설명하듯 풀어 줘. 이 내용이 다른 강의 · 과제 어디에 이어지는지도.">이 쪽 설명</button><button data-q="이 쪽 내용으로 시험에 나올 만한 문제 3개를 내 줘. 답과 풀이는 맨 아래에 따로.">예상 문제</button><button data-q="이 쪽에 나오는 공식 · 기호를 정리하고, 같은 공식이 나오는 다른 자료와 쪽을 알려 줘.">공식 · 연결</button><button data-q="이 자료 전체의 핵심을 시험공부용으로 요약해 줘. 꼭 외울 정의 · 공식은 따로.">자료 요약</button></div>
   <textarea id="aiq" rows="3" placeholder="이 과목에 대해 묻기 — 지금 보는 쪽을 같이 보내요 (Enter 보내기)" aria-label="과목 비서에게 묻기" disabled></textarea>
  </div>
  <div class="pane" id="p-hw"><div id="hwform" style="display:flex;flex-direction:column;gap:10px"></div></div>
  <div class="pane" id="p-course">
   <div id="cform" style="display:flex;flex-direction:column;gap:10px"></div>
  </div>
 </aside>
</div>
<div id="pm" role="dialog" aria-modal="true" aria-labelledby="pmt" hidden>
 <div class="box">
  <div class="pmh"><b id="pmt">교과서를 읽어 과제 문제/해설지를 생성하는 중</b><button id="pmx" title="닫아도 맥에서 계속 만들어요">닫기</button></div>
  <div id="pmname" class="muted" style="padding:0"></div>
  <div class="pbar" role="progressbar" aria-valuemin="0" aria-valuemax="100" id="pmbarw"><i id="pmbar"></i></div>
  <div class="pmrow"><b id="pmpct">0%</b><span id="pmmsg"></span></div>
  <ol id="pmsteps"></ol>
  <div id="pmdone" class="pmbtns"></div>
  <p class="muted" style="padding:0" id="pmnote">창을 닫아도 맥에서 계속 만들어요. 오른쪽 아래 작은 표시를 누르면 다시 열려요. 퍼센트는 단계별 어림이에요.</p>
 </div>
</div>
<button id="pchip" hidden></button>
<script src="web.js"></script></body></html>
"""
WEB_JS = r"""const BUILD='__BUILD__';
const $=id=>document.getElementById(id);
// 이 화면이 열린 자리 — 맥에서 바로(/web)면 빈 글, 논문 정리 웹 안(/desk/web)이면 「/desk」. 모든 요청 앞에 붙임
const B=location.pathname.replace(/\/web\/?$/,'');
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
// 브라우저 저장소는 막혀 있을 수 있음(사생활 창 등) — 그때는 이 탭이 열린 동안만 기억
const mem={};
function get(k){try{return localStorage.getItem(k)}catch(e){return mem[k]??null}}
function put(k,v){try{v===null?localStorage.removeItem(k):localStorage.setItem(k,v)}catch(e){mem[k]=v}}
let T=get('desk.token')||'';
const H=()=>({'X-Desk-Token':T});
function api(path,opt={}){return fetch(B+path,{...opt,headers:{...H(),...(opt.headers||{})},cache:'no-store'}).then(r=>{if(r.status===401){needLogin('열쇠가 맞지 않아요.');throw new Error('401')}return r})}
// ── 테마 ──
function applyTheme(){const t=get('desk.theme');if(t)document.documentElement.dataset.theme=t;else delete document.documentElement.dataset.theme}
applyTheme();
$('theme').onclick=()=>{const dark=matchMedia('(prefers-color-scheme: dark)').matches;const cur=get('desk.theme')||(dark?'dark':'light');put('desk.theme',cur==='dark'?'light':'dark');applyTheme()};
// ── 열쇠 ──
let started=false;
function needLogin(err){$('login').style.display='flex';$('le').textContent=err||'';$('lt').focus()}
$('lf').onsubmit=async e=>{e.preventDefault();const v=$('lt').value.trim();if(!v)return;
 const r=await fetch(B+'/state',{headers:{'X-Desk-Token':v}}).catch(()=>null);
 if(!r){$('le').textContent='맥에 닿지 않아요. 이 컴퓨터의 Tailscale 이 켜져 있는지 봐 주세요.';return}
 if(r.status===401){$('le').textContent='열쇠가 맞지 않아요.';return}
 T=v;put('desk.token',v);$('lt').value='';$('login').style.display='none';start()};
$('out').onclick=()=>{put('desk.token',null);T='';location.reload()};
// ── 대화 ──
let hist=[];try{hist=JSON.parse(get('desk.chat')||'[]')}catch(e){hist=[]}
function hm(t){return new Date(t).toLocaleTimeString('ko-KR',{hour:'2-digit',minute:'2-digit'})}
function draw(m){$('empty').style.display='none';const d=document.createElement('div');d.className='m '+m.c;
 if(m.title){const b=document.createElement('b');b.textContent=m.title;d.appendChild(b);d.appendChild(document.createTextNode('\n'))}
 d.appendChild(document.createTextNode(m.text));if(m.at){const s=document.createElement('span');s.className='t';s.textContent=hm(m.at);d.appendChild(s)}
 $('chat').appendChild(d);$('chat').scrollTop=1e9;return d}
function add(c,text,title){const m={c,text,title,at:Date.now()};hist.push(m);hist=hist.slice(-200);put('desk.chat',JSON.stringify(hist));return draw(m)}
hist.forEach(draw);
let busy=false;
function setBusy(b,label){busy=b;$('send').disabled=b;$('mic').disabled=b&&!recOn;if(label!==undefined)$('send').textContent=label}
async function ask(text){add('me',text);setBusy(true,'생각 중…');const w=draw({c:'ai wait',text:'생각 중…'});
 try{const r=await (await api('/ask',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({text})})).json();
  w.remove();add('ai',r.full||r.reply||r.error||'(답이 비었어요)')}
 catch(e){w.remove();if(e.message!=='401')add('sys','맥에 닿지 않아요. Tailscale 연결을 봐 주세요.')}
 finally{setBusy(false,'보내기')}}
function sendMsg(){const v=$('msg').value.trim();if(!v||busy)return;$('msg').value='';ask(v)}
$('send').onclick=sendMsg;
$('msg').addEventListener('keydown',e=>{if(e.key==='Enter'&&!e.shiftKey&&!e.isComposing){e.preventDefault();sendMsg()}});
$('stop').onclick=()=>api('/stop',{method:'POST'}).then(()=>add('sys','멈추라고 했어요.')).catch(()=>{});
// ── 말하기: https 에서만(브라우저 규칙). 누르면 녹음, 다시 누르면 보냄. 16kHz 모노 16비트로 /talk ──
let recOn=false,recCtx=null,recSrc=null,recNode=null,recStream=null,recBufs=[],recTimer=null;
if(!window.isSecureContext||!navigator.mediaDevices){$('mic').disabled=true;$('mic').title='말하기는 https 주소에서만 돼요';
 $('hint').textContent='말하기는 https 주소(논문 정리 웹 안 「비서 · 강의자료」)에서만 돼요. 여기서는 글로 써 주세요.'}
$('mic').onclick=()=>recOn?recStop():recStart();
async function recStart(){if(busy)return;
 try{recStream=await navigator.mediaDevices.getUserMedia({audio:{channelCount:1,echoCancellation:true,noiseSuppression:true}})}
 catch(e){add('sys','마이크를 못 열었어요: '+e.message);return}
 recCtx=new AudioContext();recSrc=recCtx.createMediaStreamSource(recStream);recNode=recCtx.createScriptProcessor(4096,1,1);recBufs=[];
 recNode.onaudioprocess=e=>recBufs.push(new Float32Array(e.inputBuffer.getChannelData(0)));
 recSrc.connect(recNode);recNode.connect(recCtx.destination);recOn=true;$('mic').classList.add('rec');$('mic').textContent='듣는 중 · 누르면 보냄';
 recTimer=setTimeout(recStop,90000)}
async function recStop(){clearTimeout(recTimer);if(!recOn)return;recOn=false;$('mic').classList.remove('rec');$('mic').textContent='말하기';
 const sr=recCtx.sampleRate;recNode.disconnect();recSrc.disconnect();recStream.getTracks().forEach(t=>t.stop());recCtx.close();
 let n=0;recBufs.forEach(b=>n+=b.length);if(n<sr*0.3){add('sys','너무 짧아요. 다시 말해 주세요.');return}
 const all=new Float32Array(n);let o=0;recBufs.forEach(b=>{all.set(b,o);o+=b.length});
 const k=sr/16000,m=Math.floor(n/k),pcm=new Int16Array(m);
 for(let i=0;i<m;i++){const a=Math.floor(i*k),b=Math.min(n,Math.floor((i+1)*k));let s=0;for(let j=a;j<b;j++)s+=all[j];const v=Math.max(-1,Math.min(1,s/Math.max(1,b-a)));pcm[i]=v<0?v*32768:v*32767}
 setBusy(true,'받아쓰는 중…');const w=draw({c:'ai wait',text:'받아쓰고 생각 중…'});
 try{const r=await (await api('/talk',{method:'POST',body:pcm.buffer})).json();w.remove();
  if(r.heard)add('me','🎙 '+r.heard);add('ai',r.full||r.reply||r.error||'(답이 비었어요)')}
 catch(e){w.remove();if(e.message!=='401')add('sys','맥에 닿지 않아요.')}
 finally{setBusy(false,'보내기')}}
// ── 주인 확인 알림(폰 알림과 같은 것) — 롱폴 ──
async function notices(){let boot='',since=-1;
 while(true){try{const r=await (await api(`/notices?since=${Math.max(0,since)}&wait=${since<0?0:50}`)).json();
   if(r.boot!==boot){const first=since<0;boot=r.boot;since=r.seq;if(first){continue}}
   (r.items||[]).forEach(n=>add('need',n.body||'',n.title||'주인 확인 필요'));since=r.seq}
  catch(e){if(e.message==='401')return;await sleep(5000)}}}
// ── 상태(3초마다) — 연결 · 화면 · 핸드마우스 · 음량. 맥의 페이지가 바뀌면 다시 읽음 ──
let scrOn={},hmOn=null,volDragging=false;
function scrDraw(s){scrOn=s||{};[['scrm','main','주 화면'],['scrd','desk','세로 화면']].forEach(([id,r,nm])=>{const on=scrOn[r];
 $(id).textContent=nm+' '+(on===true?'켜짐':on===false?'꺼짐':'모름');$(id).classList.toggle('on',on===true)})}
function hmDraw(on){hmOn=on;$('hm').textContent='핸드마우스 '+(on===true?'켜짐':on===false?'꺼짐':'모름');$('hm').classList.toggle('on',on===true)}
const MODE={awake:'대기 중',sleep:'자는 중',muted:'조용히'};   // daemon.py 의 self.mode 값
async function poll(){while(true){try{const s=await (await api('/state')).json();
  if(s.web&&s.web!==BUILD&&!recOn&&!busy)return location.reload();
  $('mode').className='';$('mode').innerHTML='';const b=document.createElement('b');b.textContent='● ';$('mode').appendChild(b);
  $('mode').appendChild(document.createTextNode('맥 연결됨 · '+(MODE[s.mode]||s.mode||'')));
  if(s.screens)scrDraw(s.screens);drawUsage(s.usage);if(s.handmouse)hmDraw(s.handmouse.on);
  if(s.volume&&s.volume.v!=null&&!volDragging){$('vol').disabled=false;$('vol').value=s.volume.v;$('volv').textContent=s.volume.muted?'음소거':s.volume.v}}
 catch(e){if(e.message==='401')return;$('mode').className='off';$('mode').innerHTML='<b>● </b>맥에 닿지 않아요'}
 await sleep(3000)}}
// ── 맥 화면 — 「두 화면」 이면 주 화면과 세로 모니터를 나란히(세로는 세로 비율 그대로), 아니면 고른 하나 (주인 11월 10일 20:29) ──
const IMG=[$('scr'),$('scr1')];let scr=+(get('desk.scr')??2);if(![0,1,2].includes(scr))scr=2;const tags=['',''];
function scrMode(s){scr=s;put('desk.scr',s);document.querySelectorAll('#tools [data-s]').forEach(x=>x.classList.toggle('on',+x.dataset.s===s));
 $('view').classList.toggle('both',s===2);IMG.forEach((im,i)=>im.classList.toggle('cur',s===2||s===i));tags[0]=tags[1]=''}
document.querySelectorAll('#tools [data-s]').forEach(b=>b.onclick=()=>scrMode(+b.dataset.s));
scrMode(scr);
function vmsg(t){$('viewmsg').style.display=t?'flex':'none';$('viewmsg').textContent=t||''}
function fit(i){const im=IMG[i];if(im.naturalWidth)im.style.flexGrow=String(im.naturalWidth/im.naturalHeight)}   // 두 화면의 높이가 같게 — 너비를 화면 비율만큼
async function grab(i){const im=IMG[i],R=(scr===2?im:$('view')).getBoundingClientRect(),w=Math.min(2560,Math.max(320,Math.round(R.width*devicePixelRatio)));
 const r=await api(`/screen/${i}.jpg?w=${w}&q=60&h=${tags[i]}`);
 if(r.status===200){const b=await r.blob();tags[i]=r.headers.get('X-Frame')||'';const u=URL.createObjectURL(b),old=im.src;im.onload=()=>fit(i);im.src=u;if(old.startsWith('blob:'))setTimeout(()=>URL.revokeObjectURL(old),1000);return ''}
 if(r.status===503&&r.headers.get('X-Asleep'))return '맥 화면이 꺼져 있어요. 위의 「화면 켜기」를 눌러 주세요.';
 if(r.status===404)return scr===2&&i===1?'':'이 화면이 없어요.';
 if(r.status!==204)return '화면을 못 받았어요 ('+r.status+')';
 return ''}
async function screenLoop(){let fails=0;while(true){
  if(document.hidden||tab!=='desk'){await sleep(500);continue}   // 강의자료 탭에서는 맥 화면을 안 받음
  try{const want=scr===2?[0,1]:[scr];let m='';for(const i of want){const x=await grab(i);if(x&&!m)m=x}
   vmsg(m);if(m)await sleep(1500);fails=0}
  catch(e){if(e.message==='401')return;fails++;vmsg('연결이 끊겼어요. 다시 잇는 중…');await sleep(Math.min(5000,500*fails))}
  await sleep(150)}}
function frac(im,cx,cy){const R=im.getBoundingClientRect(),iw=im.naturalWidth||1,ih=im.naturalHeight||1;
 const k=Math.min(R.width/iw,R.height/ih),w=iw*k,h=ih*k,x0=R.left+(R.width-w)/2,y0=R.top+(R.height-h)/2;
 return[(cx-x0)/w,(cy-y0)/h]}
const inside=([f,g])=>f>=0&&f<=1&&g>=0&&g<=1;
function act(ev,i){ev.screen=i??(scr===2?0:scr);tags[ev.screen]='';return api('/input',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(ev)}).then(r=>r.json()).then(r=>{if(r.r&&r.r!=='ok')$('st').textContent=r.r}).catch(()=>{})}
// 클릭 하나는 잠깐 기다렸다 보냄 — 곧바로 한 번 더 누르면 두 번 클릭(맥은 클릭 횟수를 따로 셈). 누른 그림이 곧 그 화면
let down=null,clickT=null,dragMode=false;
IMG.forEach((SCR,i)=>{
 SCR.addEventListener('mousedown',e=>{if(e.button!==0)return;e.preventDefault();down={x:e.clientX,y:e.clientY,i}});
 SCR.addEventListener('mouseup',e=>{if(e.button!==0||!down||down.i!==i)return;const p=frac(SCR,down.x,down.y),moved=Math.hypot(e.clientX-down.x,e.clientY-down.y)>6;down=null;
  if(!inside(p))return;
  if(moved){if(dragMode){const q=frac(SCR,e.clientX,e.clientY);act({action:'drag',x:p[0],y:p[1],x2:q[0],y2:q[1]},i)}return}
  if(clickT){clearTimeout(clickT);clickT=null;act({action:'double',x:p[0],y:p[1]},i)}
  else clickT=setTimeout(()=>{clickT=null;act({action:'click',x:p[0],y:p[1]},i)},260)});
 SCR.addEventListener('contextmenu',e=>{e.preventDefault();const p=frac(SCR,e.clientX,e.clientY);if(inside(p))act({action:'right',x:p[0],y:p[1]},i)});
 let wy=0,wx=0,wt=null,wp=null;
 SCR.addEventListener('wheel',e=>{e.preventDefault();wp=frac(SCR,e.clientX,e.clientY);wy+=-e.deltaY;wx+=-e.deltaX;
  if(!wt)wt=setTimeout(()=>{wt=null;if(inside(wp)&&(Math.abs(wy)>=1||Math.abs(wx)>=1))act({action:'scroll',x:wp[0],y:wp[1],dy:Math.round(wy),dx:Math.round(wx)},i);wy=0;wx=0},60)},{passive:false})});
// Claude 사용량 — desk/usage.py 가 Claude Code 상태줄에서 받아 둔 5시간 · 주간 한도 값만. 모르면 「모름」 (지어내지 않음)
function drawUsage(rows){const box=$('usage');box.replaceChildren(el('b',null,'Claude 사용량'));
 (rows||[]).forEach(r=>{const d=el('span','u'+(r.known?(r.left<=10?' out':r.left<=25?' low':''):''));d.appendChild(document.createTextNode(r.label+' '));
  if(!r.known){d.appendChild(el('b',null,'모름'));if(r.note)d.appendChild(document.createTextNode(' · '+r.note));d.title='Claude Code 상태줄 값을 아직 못 받았어요';box.appendChild(d);return}
  d.appendChild(el('b',null,r.left+'% 남음'));const bar=el('span','ub');const i=el('i');i.style.width=r.left+'%';bar.appendChild(i);d.appendChild(bar);
  d.appendChild(document.createTextNode(r.resets?r.resets+' 뒤 초기화':'초기화 시각 모름'));if(r.note)d.appendChild(document.createTextNode(' · '+r.note));
  d.title=`${r.label} 한도의 ${r.used}% 사용`;box.appendChild(d)});
 if(!(rows||[]).length)box.appendChild(el('span',null,'모름'))}
$('drag').onclick=()=>{dragMode=!dragMode;$('drag').classList.toggle('on',dragMode)};
$('typ').addEventListener('keydown',e=>{if(e.key==='Enter'&&!e.isComposing){e.preventDefault();const v=$('typ').value;if(v){act({action:'type',text:v});$('typ').value=''}else act({action:'key',key:'enter'})}});
document.querySelectorAll('[data-k]').forEach(b=>b.onclick=()=>act({action:'key',key:b.dataset.k}));
function post(path,msg){$('st').textContent=msg||'';return api(path,{method:'POST'}).then(r=>r.json()).then(r=>{$('st').textContent=r.r&&r.r!=='ok'?String(r.r):''}).catch(e=>{if(e.message!=='401')$('st').textContent='맥에 닿지 않아요'})}
$('son').onclick=()=>post('/screen_on','켜는 중…');
$('soff').onclick=()=>post('/screen_off','끄는 중…');
$('scrm').onclick=()=>post('/screen_main_'+(scrOn.main===false?'on':'off'));
$('scrd').onclick=()=>post('/screen_desk_'+(scrOn.desk===false?'on':'off'));
$('hm').onclick=()=>post(hmOn===true?'/handmouse_off':'/handmouse_on');
$('vol').addEventListener('input',()=>{volDragging=true;$('volv').textContent=$('vol').value});
$('vol').addEventListener('change',()=>{const v=+$('vol').value;api('/volume',{method:'POST',body:JSON.stringify({v})}).catch(()=>{}).finally(()=>volDragging=false)});
// ── 탭: 비서 · 맥 / 강의자료 ──
let tab=get('web.tab')||'desk';
function showTab(t){tab=t;put('web.tab',t);document.querySelectorAll('#tabs button').forEach(b=>b.classList.toggle('on',b.dataset.tab===t));
 $('app').style.display=t==='desk'?'':'none';$('study').classList.toggle('show',t==='study');if(t==='study'&&started)loadStudy()}
document.querySelectorAll('#tabs button').forEach(b=>b.onclick=()=>showTab(b.dataset.tab));
// ── 강의자료 (desk/study.py) ──
const ST={new:'안 봄',reading:'보는 중',done:'다 봄',review:'다시 볼 것'};
const KIND={lecture:'수업자료',assignment:'과제',textbook:'교과서'};
const S={db:null,course:get('study.course')||'',file:'',filter:'',q:'',hits:null,page:1,view:'',kind:get('study.kind')||'lecture',
 open:new Set(JSON.parse(get('study.open')||'[]')),watch:get('study.watch')||'',pmOpen:false};
const el=(tag,cls,text)=>{const d=document.createElement(tag);if(cls)d.className=cls;if(text!=null)d.textContent=text;return d};
async function jpost(path,obj){const r=await api(path,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(obj)});
 const j=await r.json().catch(()=>({}));if(!r.ok)throw new Error(j.error||('맥이 거절했어요 ('+r.status+')'));return j}
function serr(msg){const d=el('div','err',msg);$('serr').appendChild(d);setTimeout(()=>d.remove(),8000)}   // 목록을 다시 그려도 안 지워지게 따로 칸
const course=id=>(S.db?.courses||[]).find(c=>c.id===id);
const file=id=>(S.db?.files||[]).find(f=>f.id===id);
const job=f=>(f&&f.hw&&f.hw.job)||{};
const busyJob=f=>['queued','running'].includes(job(f).state);
function dday(exam){if(!exam)return null;const t=new Date();t.setHours(0,0,0,0);const d=Math.round((new Date(exam+'T00:00:00')-t)/864e5);
 return d>0?{t:'D-'+d,c:d<=7?'soon':''}:d===0?{t:'D-day',c:'soon'}:{t:'끝남',c:'past'}}
// 회독 수 → 색(빨강 쪽 → 초록 쪽). 채도를 낮춘 차분한 색, 테두리 띠로만 (주인 11월 10일 20:34)
const readHue=n=>Math.round(8+112*Math.min(n||0,4)/4);
function saveOpen(){put('study.open',JSON.stringify([...S.open]))}
let pollT=null;
async function loadStudy(light){try{S.db=await (await api('/study/list')).json()}catch(e){if(e.message!=='401'&&!light)$('slist').replaceChildren(el('div','muted','맥에 닿지 않아요.'));return}
 if(!course(S.course))S.course=S.db.courses[0]?.id||'';
 if(S.course&&!get('study.open'))S.open.add(S.course);
 if(S.file&&!file(S.file))closeFile();
 if(!light&&!S.file){const last=get('study.file');if(last&&file(last))openFile(last)}
 renderList();if(!light)renderCourse();drawJob();drawHw(light);drawSv();
 clearTimeout(pollT);
 const running=S.db.files.some(busyJob),indexing=S.db.files.some(f=>f.pages==null&&!f.index_error);
 if(running||indexing)pollT=setTimeout(()=>{if(started)loadStudy(true)},running?2000:3000)}   // 만드는 중 · 쪽 수를 뽑는 중이면 다시 읽음(다른 탭에 있어도 진행률은 계속)
function fileRow(f){const d=el('div','fl'+(f.id===S.file?' sel':''));d.style.setProperty('--h',readHue(f.reads));
 const dot=el('span','dot '+f.status);dot.title=ST[f.status]+(f.status_manual?' (직접 고름)':'');d.appendChild(dot);
 d.appendChild(el('span','nm',f.name));
 const j=job(f);
 if(f.kind==='assignment'&&busyJob(f)){const b=el('span','jb run',(j.pct||0)+'%');b.title=j.msg||'만드는 중';d.appendChild(b)}
 else if(f.kind==='assignment'&&j.state==='error'){const b=el('span','jb bad','멈춤');b.title=j.msg||'';d.appendChild(b)}
 else if(f.kind==='assignment'&&f.hw&&f.hw.solution)d.appendChild(el('span','jb ok','해설지'));
 if(f.reads)d.appendChild(el('span','rc',f.reads+'회독'));
 d.appendChild(el('span','pg',f.pages!=null?f.pages+'쪽':f.index_error?'검색 안 됨':'읽는 중…'));
 d.title=(f.index_error||f.name)+` · ${f.reads||0}회독`;d.onclick=()=>openFile(f.id);return d}
function renderList(){const box=$('slist');const keep=box.scrollTop;box.replaceChildren();
 if(S.hits){const head=el('div','muted',S.hits.length?`「${S.q}」 ${S.hits.length}곳`+(S.hits.length>=60?' (60곳까지만)':''):`「${S.q}」 은(는) 어느 자료에도 없어요.`);box.appendChild(head);
  const words=S.q.toLowerCase().split(/\s+/).filter(Boolean);
  S.hits.forEach(h=>{const d=el('div','hit');const b=el('b',null,`${h.name} · ${h.page}쪽`);d.appendChild(b);const s=el('span','s');
   let rest=h.snip;const low=()=>rest.toLowerCase();   // 찾은 말에 형광펜(textContent 로만 넣음)
   while(rest){let at=-1,w='';words.forEach(x=>{const i=low().indexOf(x);if(i>=0&&(at<0||i<at)){at=i;w=x}});
    if(at<0){s.appendChild(document.createTextNode(rest));break}
    s.appendChild(document.createTextNode(rest.slice(0,at)));s.appendChild(el('mark',null,rest.slice(at,at+w.length)));rest=rest.slice(at+w.length)}
   d.appendChild(s);d.onclick=()=>{S.course=h.course;openFile(h.id,h.page)};box.appendChild(d)});return}
 if(!S.db.courses.length){box.appendChild(el('div','muted','아래 「+ 과목 추가」로 과목부터 만들어 주세요.'));return}
 S.db.courses.forEach(c=>{const fs=S.db.files.filter(f=>f.course===c.id);const open=S.open.has(c.id);
  const r=el('div','crs'+(c.id===S.course?' sel':''));r.setAttribute('role','button');r.setAttribute('aria-expanded',open);r.tabIndex=0;
  r.appendChild(el('span','arr'+(open?' open':''),'▸'));
  r.appendChild(el('span','nm',c.name));const dd=dday(c.exam);if(dd){const b=el('span','dday '+dd.c,dd.t);b.title='시험 '+c.exam;r.appendChild(b)}
  const lec=fs.filter(f=>f.kind!=='assignment');r.appendChild(el('span','prog',`${lec.filter(f=>f.status==='done').length}/${lec.length}`)).title='다 본 자료 / 수업자료 · 교과서';
  // 과목 줄: 누르면 펼침 · 다시 누르면 접힘 (주인 11월 10일 20:28). 다른 과목이면 그 과목을 고르고 펼침
  const tog=()=>{if(S.course!==c.id){S.course=c.id;put('study.course',c.id);S.open.add(c.id)}else if(open)S.open.delete(c.id);else S.open.add(c.id);saveOpen();renderList();renderCourse()};
  r.onclick=tog;r.onkeydown=e=>{if(e.key==='Enter'||e.key===' '){e.preventDefault();tog()}};box.appendChild(r);
  if(!open)return;
  const list=el('div','files');
  ['lecture','assignment','textbook'].forEach(k=>{const all=fs.filter(f=>f.kind===k),shown=all.filter(f=>!S.filter||f.status===S.filter);
   const g=el('div','grp');g.appendChild(el('span','gn',`${KIND[k]} ${all.length}`));
   const up=el('button','mini','+ 올리기');up.title=`${KIND[k]} PDF 올리기`;up.onclick=e=>{e.stopPropagation();S.course=c.id;setKind(k);$('pick').click()};g.appendChild(up);
   if(k==='assignment'){const nb=el('button','mini','+ 번호로');nb.title='문제 번호만 적어 과제 넣기 (예: 3.2, 3.5, 4.1)';nb.onclick=e=>{e.stopPropagation();S.course=c.id;addNumbered()};g.appendChild(nb)}
   list.appendChild(g);
   if(!all.length)list.appendChild(el('div','muted sm',k==='assignment'?'과제를 넣으면 교과서로 문제지 · 해설지를 만들어요.':k==='textbook'?'교과서를 넣으면 과제 문제를 여기서 찾아요.':'아직 없어요. PDF 를 끌어 놓아 주세요.'));
   else if(!shown.length)list.appendChild(el('div','muted sm',`「${ST[S.filter]}」 자료가 없어요.`));
   shown.forEach(f=>list.appendChild(fileRow(f)))});
  box.appendChild(list)});
 box.scrollTop=keep}
document.querySelectorAll('#filt button').forEach(b=>b.onclick=()=>{S.filter=b.dataset.f;document.querySelectorAll('#filt button').forEach(x=>x.classList.toggle('on',x===b));renderList()});
let sqT=null;
$('sq').addEventListener('input',()=>{clearTimeout(sqT);sqT=setTimeout(async()=>{const q=$('sq').value.trim();S.q=q;
 if(!q){S.hits=null;renderList();return}
 try{const r=await (await api('/study/search?q='+encodeURIComponent(q))).json();if(S.q===q){S.hits=r.hits||[];renderList()}}catch(e){}},300)});
$('sq').addEventListener('keydown',e=>{if(e.key==='Escape'){$('sq').value='';S.q='';S.hits=null;renderList()}});
// ── 쪽 보기: 보이는 쪽만 그림으로 받음(맥이 그려 캐시) · 받은 쪽은 이 탭에 최근 것부터 PV_MAX 장까지 (주인 11월 10일 20:35)
// 어느 쪽을 보는지 알아야 「보는 중 → 다 봄 · 회독」 을 저절로 매길 수 있어서 브라우저 PDF 보기 대신 씀. 통째 PDF 는 「PDF 받기」
const PV_MAX=80,PV_W=[600,1000,1400,2000];
const PV={key:'',id:'',v:'',n:0,zoom:+(get('study.zoom')||1),cache:new Map(),seen:new Set(),ended:false,cur:1,endT:null,obs:null,lastT:null};
function pvW(){const w=$('pv').clientWidth*PV.zoom*devicePixelRatio;return PV_W.find(x=>x>=w)||2000}
function pvUrl(p){return `/study/page/${PV.id}/${p}.jpg?w=${pvW()}${PV.v?'&v='+PV.v:''}`}
function pvMeta(f,v){if(!v)return{n:f.pages||0,ratio:f.ratio||1.414};const h=f.hw||{};return{n:h[v+'_pages']||0,ratio:h[v+'_ratio']||1.414}}
function pvOpen(f,v,page){const m=pvMeta(f,v),key=`${f.id}|${v}|${(f.hw||{})[v||'x']||''}`;
 const box=$('pv');if(PV.key===key&&box.childElementCount){pvGo(page||PV.cur);return}
 PV.key=key;PV.id=f.id;PV.v=v;PV.n=m.n;PV.seen=new Set();PV.ended=false;clearTimeout(PV.endT);
 if(PV.obs)PV.obs.disconnect();box.replaceChildren();
 if(!m.n){box.appendChild(el('div','muted',f.pages==null&&!v?'쪽 수를 세는 중이에요. 잠깐만요…':'쪽이 없어요.'));return}
 const wrap=el('div','pgs');wrap.style.width=Math.round(PV.zoom*100)+'%';
 for(let p=1;p<=m.n;p++){const d=el('div','vpg ld');d.dataset.p=p;d.style.aspectRatio=`1 / ${m.ratio}`;const im=el('img');im.alt=`${p}쪽`;im.decoding='async';d.appendChild(im);
  d.appendChild(el('span','pn',p));wrap.appendChild(d)}
 box.appendChild(wrap);
 PV.obs=new IntersectionObserver(es=>es.forEach(e=>{if(e.isIntersecting)pvLoad(e.target)}),{root:box,rootMargin:'800px 0px'});
 wrap.querySelectorAll('.vpg').forEach(d=>PV.obs.observe(d));
 $('svpages').textContent='/ '+m.n;requestAnimationFrame(()=>pvGo(page||1,true))}
async function pvLoad(d){const p=+d.dataset.p,url=pvUrl(p),im=d.firstChild;if(im.dataset.u===url)return;im.dataset.u=url;
 let b=PV.cache.get(url);
 if(b){PV.cache.delete(url);PV.cache.set(url,b)}                 // 최근에 씀
 else{try{const r=await api(url);if(!r.ok)throw new Error((await r.json().catch(()=>({}))).error||r.status);b=URL.createObjectURL(await r.blob())}
  catch(e){im.dataset.u='';d.classList.remove('ld');d.classList.add('fail');d.title='이 쪽을 못 받았어요: '+e.message;return}
  PV.cache.set(url,b);
  while(PV.cache.size>PV_MAX){const [k,u]=PV.cache.entries().next().value;PV.cache.delete(k);URL.revokeObjectURL(u);   // 오래된 쪽부터 버림
   document.querySelectorAll('#pv img').forEach(x=>{if(x.dataset.u===k){x.removeAttribute('src');x.dataset.u='';x.parentNode.classList.add('ld');if(PV.obs)PV.obs.unobserve(x.parentNode),PV.obs.observe(x.parentNode)}})}}
 if(im.dataset.u!==url)return;
 im.onload=()=>{d.classList.remove('ld','fail');d.style.aspectRatio=''};im.src=b}
function pvGo(n,instant){n=Math.max(1,Math.min(+n||1,PV.n||1));const d=$('pv').querySelector(`.vpg[data-p="${n}"]`);if(!d)return;
 $('pv').scrollTo({top:d.offsetTop-8,behavior:instant?'auto':'smooth'});pvSet(n)}
function pvSet(n){if(PV.cur===n&&$('svpage').value==n)return;PV.cur=n;S.page=n;$('svpage').value=n;PV.seen.add(n);
 const f=file(S.file);if(!f)return;
 if(!PV.v){clearTimeout(PV.lastT);PV.lastT=setTimeout(()=>{if(f.last_page!==n){f.last_page=n;jpost('/study/file',{id:f.id,last_page:n}).catch(()=>{})}},1500);
  // 끝 쪽에 3초 머물고, 이번에 연 동안 절반 넘는 쪽을 지나왔으면 「끝까지 봄」 → 다 봄 · 회독 +1 (주인 11월 10일 20:33 · 20:34)
  clearTimeout(PV.endT);if(n===PV.n&&!PV.ended&&PV.seen.size>=Math.max(1,Math.ceil(PV.n*0.5)))PV.endT=setTimeout(()=>readEnd(f),3000)}}
async function readEnd(f){if(PV.ended||S.file!==f.id||PV.v)return;PV.ended=true;
 try{const r=await jpost('/study/read_end',{id:f.id});Object.assign(f,r);drawSeg();renderList()}catch(e){PV.ended=false;serr(e.message)}}
let pvRaf=0;
$('pv').addEventListener('scroll',()=>{if(pvRaf)return;pvRaf=requestAnimationFrame(()=>{pvRaf=0;const box=$('pv'),mid=box.scrollTop+box.clientHeight*0.4;
 let best=1;for(const d of box.querySelectorAll('.vpg')){if(d.offsetTop<=mid)best=+d.dataset.p;else break}
 if(box.scrollTop+box.clientHeight>=box.scrollHeight-4)best=PV.n;   // 맨 아래까지 내렸으면 끝 쪽(마지막 쪽은 위로 못 올라와서)
 pvSet(best)})},{passive:true});
function zoom(k){const keep=PV.cur;PV.zoom=Math.max(0.5,Math.min(2.5,Math.round(PV.zoom*k*10)/10));put('study.zoom',PV.zoom);
 const w=$('pv').querySelector('.pgs');if(w)w.style.width=Math.round(PV.zoom*100)+'%';$('pv').querySelectorAll('.vpg').forEach(d=>{d.firstChild.dataset.u='';PV.obs&&PV.obs.unobserve(d);PV.obs&&PV.obs.observe(d)});pvGo(keep,true)}
$('zin').onclick=()=>zoom(1.25);$('zout').onclick=()=>zoom(0.8);
$('pv').addEventListener('keydown',e=>{if(e.target!==$('pv'))return;if(e.key==='PageDown'||e.key==='ArrowRight'){e.preventDefault();pvGo(PV.cur+1)}if(e.key==='PageUp'||e.key==='ArrowLeft'){e.preventDefault();pvGo(PV.cur-1)}});
// 자료 열기
function closeFile(){S.file='';put('study.file',null);$('pv').style.display='none';$('pv').replaceChildren();PV.key='';$('svbar').style.display='none';$('svempty').style.display='';
 $('note').value='';$('note').disabled=true;$('mklist').replaceChildren();$('sptab-hw').style.display='none'}
function openFile(id,page,view){const f=file(id);if(!f)return;
 if(S.file!==id){S.file=id;put('study.file',id);S.course=f.course;put('study.course',f.course);S.open.add(f.course);saveOpen();S.view='';
  $('svempty').style.display='none';$('svbar').style.display='';$('pv').style.display='';
  $('svname').textContent=f.name;$('svname').title=f.name;
  $('note').value=f.note||'';$('note').disabled=false;$('saved').textContent='';
  $('sptab-hw').style.display=f.kind==='assignment'?'':'none';if(f.kind!=='assignment'&&$('p-hw').classList.contains('on'))spTab('note');
  if(f.status==='new')jpost('/study/file',{id,status:'reading',auto:true}).then(r=>{Object.assign(f,r);drawSeg();renderList()}).catch(()=>{});   // 열어 보면 「보는 중」 (주인이 직접 고른 상태면 맥이 안 바꿈)
  drawSeg();drawMarks();drawHw();renderList();renderCourse()}
 if(view!==undefined)S.view=view;
 if(f.kind==='assignment'&&page==null&&view===undefined&&!S.view&&f.hw&&f.hw.solution&&!PV.key)S.view='';
 drawSv();pvOpen(f,S.view,page||(S.view?1:f.last_page||1))}
function drawSv(){const f=file(S.file);if(!f)return;const h=f.hw||{};
 $('vseg').style.display=f.kind==='assignment'?'':'none';
 document.querySelectorAll('#vseg button').forEach(b=>{const v=b.dataset.v;b.classList.toggle('on',v===S.view);b.disabled=!!v&&!h[v];
  b.title=!v?'올린 과제':h[v]?'':v==='sheet'?'번호만 나열된 과제일 때 만들어요':'아직 안 만들었어요'});
 $('svpages').textContent=PV.n?'/ '+PV.n:''}
document.querySelectorAll('#vseg button').forEach(b=>b.onclick=()=>{const f=file(S.file);if(!f||b.disabled)return;S.view=b.dataset.v;drawSv();pvOpen(f,S.view,1)});
$('svpage').addEventListener('keydown',e=>{if(e.key==='Enter')pvGo($('svpage').value)});
$('svpage').addEventListener('change',()=>pvGo($('svpage').value));
$('svopen').onclick=async()=>{const f=file(S.file);if(!f)return;const b=$('svopen'),label=b.textContent;b.disabled=true;b.textContent='받는 중…';
 const w=window.open('','_blank');   // 받은 뒤에 열면 팝업 막기에 걸려서 먼저 엶
 try{const r=await api(S.view?`/study/out/${f.id}-${S.view}.pdf`:`/study/file/${f.id}.pdf`);if(!r.ok)throw new Error((await r.json().catch(()=>({}))).error||r.status);
  const u=URL.createObjectURL(await r.blob());if(w)w.location=u+'#page='+PV.cur;else location.href=u;setTimeout(()=>URL.revokeObjectURL(u),120000)}
 catch(e){if(w)w.close();if(e.message!=='401')serr('PDF 를 못 받았어요: '+e.message)}finally{b.disabled=false;b.textContent=label}};
function drawSeg(){const f=file(S.file);document.querySelectorAll('#seg button').forEach(b=>b.classList.toggle('on',!!f&&b.dataset.st===f.status));
 if(!f)return;$('rdn').textContent=(f.reads||0)+'회독';$('rd').style.setProperty('--h',readHue(f.reads));
 $('rdn').title=f.reads_manual?'직접 고친 회독 수 — 끝까지 봐도 저절로 안 늘어요':'끝 쪽까지 볼 때마다 저절로 하나씩 늘어요';
 $('stauto').style.display=f.status_manual||f.reads_manual?'':'none'}
document.querySelectorAll('#seg button').forEach(b=>b.onclick=async()=>{const f=file(S.file);if(!f)return;const old=f.status;f.status=b.dataset.st;drawSeg();renderList();
 try{Object.assign(f,await jpost('/study/file',{id:f.id,status:f.status}));drawSeg()}catch(e){f.status=old;drawSeg();renderList();serr(e.message)}});
async function setReads(n){const f=file(S.file);if(!f)return;try{Object.assign(f,await jpost('/study/file',{id:f.id,reads:Math.max(0,n)}));drawSeg();renderList()}catch(e){serr(e.message)}}
$('rdm').onclick=()=>{const f=file(S.file);if(f)setReads((f.reads||0)-1)};$('rdp').onclick=()=>{const f=file(S.file);if(f)setReads((f.reads||0)+1)};
$('stauto').onclick=async()=>{const f=file(S.file);if(!f)return;try{Object.assign(f,await jpost('/study/file',{id:f.id,status_manual:false,reads_manual:false}));drawSeg();renderList()}catch(e){serr(e.message)}};
// 메모 — 쓰고 0.7초 쉬면 저장
let noteT=null;
$('note').addEventListener('input',()=>{const id=S.file,v=$('note').value;$('saved').textContent='쓰는 중…';clearTimeout(noteT);
 noteT=setTimeout(async()=>{try{await jpost('/study/file',{id,note:v});const f=file(id);if(f)f.note=v;if(S.file===id)$('saved').textContent='저장됨 '+hm(Date.now())}
  catch(e){if(S.file===id)$('saved').textContent='저장 못 함: '+e.message}},700)});
// 쪽 표시
function drawMarks(){const f=file(S.file),box=$('mklist');box.replaceChildren();if(!f)return;$('mkp').value=S.page||'';
 if(!f.marks.length)box.appendChild(el('div','muted','시험에 나올 쪽, 헷갈리는 쪽을 표시해 두세요. 누르면 그 쪽으로 가요.'));
 f.marks.forEach((m,i)=>{const d=el('div','mk');d.appendChild(el('span','p',m.p+'쪽'));d.appendChild(el('span',null,m.t));
  const x=el('button','x','✕');x.title='표시 지우기';x.onclick=e=>{e.stopPropagation();saveMarks(f,f.marks.filter((_,j)=>j!==i))};d.appendChild(x);
  d.onclick=()=>{if(S.view){S.view='';drawSv();pvOpen(f,'',m.p)}else pvGo(m.p)};box.appendChild(d)})}
async function saveMarks(f,marks){try{const r=await jpost('/study/file',{id:f.id,marks});f.marks=r.marks;drawMarks()}catch(e){serr(e.message)}}
function addMark(){const f=file(S.file);if(!f)return;const p=+$('mkp').value||S.page||1,t=$('mkt').value.trim();$('mkt').value='';saveMarks(f,[...f.marks,{p,t}])}
$('mkadd').onclick=addMark;$('mkt').addEventListener('keydown',e=>{if(e.key==='Enter'&&!e.isComposing)addMark()});
// 오른쪽 칸 탭
function spTab(p){document.querySelectorAll('#sptabs button').forEach(x=>x.classList.toggle('on',x.dataset.p===p));
 document.querySelectorAll('#sp .pane').forEach(x=>x.classList.toggle('on',x.id==='p-'+p));if(p==='marks')$('mkp').value=S.page||'';if(p==='ai')loadAi(true)}
document.querySelectorAll('#sptabs button').forEach(b=>b.onclick=()=>spTab(b.dataset.p));
// 과목 비서 (desk/coursechat.py) — 과목마다 전담 세션. 자료를 바꿔도 같은 과목이면 대화가 이어짐. 묻을 때는 지금 보는 쪽만 붙여 보냄 (주인 11월 10일 20:51)
const AI={course:'',data:null,t:null,kicked:{}};
function aiOpen(){return $('p-ai').classList.contains('on')}
async function loadAi(kick){const cid=S.course;clearTimeout(AI.t);
 if(!cid){AI.course='';AI.data=null;drawAi();return}
 try{const r=await (await api('/study/chat?course='+cid)).json();if(S.course!==cid)return;AI.course=cid;AI.data=r;
  if(kick&&r.prep.done<r.prep.total&&!r.prep.running&&!AI.kicked[cid]){AI.kicked[cid]=1;jpost('/study/chat_prep',{course:cid}).catch(()=>{})}   // 아직 안 읽은 자료가 있으면 미리 읽기 시작
  drawAi()}catch(e){if(e.message!=='401')$('aiprep').textContent='맥에 닿지 않아요.'}
 const d=AI.data;if(d&&S.course===cid&&(d.asking||d.prep.running||d.history.some(m=>m.q&&m.a==null)))AI.t=setTimeout(()=>loadAi(),aiOpen()?1500:5000)}
// 답의 마크다운(제목 · 굵게 · 목록)만 — innerHTML 없이 글자 노드로 만듦
function md(text){const box=el('div','md');
 const inline=(parent,t)=>{t.split(/(\*\*[^*]+\*\*)/g).forEach(x=>{if(/^\*\*[^*]+\*\*$/.test(x))parent.appendChild(el('b',null,x.slice(2,-2)));else if(x)parent.appendChild(document.createTextNode(x))})};
 text.split('\n').forEach(line=>{let m;
  if((m=line.match(/^#{1,4}\s+(.*)/))){const h=el('div','h');inline(h,m[1]);box.appendChild(h)}
  else if((m=line.match(/^(\s*)[-*]\s+(.*)/))){const li=el('div','li');li.style.paddingLeft=(10+Math.min(3,Math.floor(m[1].length/2))*14)+'px';inline(li,m[2]);box.appendChild(li)}
  else if(line.trim()===''){box.appendChild(el('div','gap'))}
  else{const p=el('div');inline(p,line);box.appendChild(p)}});
 return box}
function drawAi(){const c=course(S.course),d=AI.course===S.course?AI.data:null,box=$('ailog'),stick=box.scrollHeight-box.scrollTop-box.clientHeight<40;
 $('aiwhat').textContent=c?`「${c.name}」 전담 비서`:'과목을 고르면 그 과목 전담 비서와 이야기해요.';
 $('aiq').disabled=!c;$('ainew').disabled=!c;
 const pr=d?d.prep:null;
 $('aiprep').textContent=!pr?'':pr.running?`과목 자료를 미리 읽는 중 ${pr.done}/${pr.total} · 「${pr.running}」 (손글씨는 쪽 그림으로 읽어요)`:
  pr.done<pr.total?`미리 읽은 자료 ${pr.done}/${pr.total} — 나머지는 차례로 읽어요`:`이 과목 자료 ${pr.total}개를 모두 읽어 두었어요.`;
 if(pr&&pr.errors.length)$('aiprep').title='못 읽은 자료: '+pr.errors.join(' / ');
 box.replaceChildren();
 if(!d||!d.history.length){box.appendChild(el('div','muted',c?'지금 보는 쪽을 함께 보내요. 다른 자료와 이어서 답해요 — 예: 「이건 몇 강 몇 쪽 내용이고 어느 과제에 쓰여요」.':''));return}
 d.history.forEach(m=>{if(m.sys){box.appendChild(el('div','qa sys',m.sys));return}
  const q=el('div','qa q');const f=file(m.file);if(f){q.appendChild(el('span','tag',`${f.name}${m.variant==='sheet'?' 문제지':m.variant==='solution'?' 해설지':''} · ${m.page}쪽`))}
  q.appendChild(document.createTextNode(m.q));box.appendChild(q);
  const a=el('div','qa'+(m.a==null?' wait':m.error?' err':''));if(m.a==null||m.error)a.textContent=m.a==null?'자료를 보며 생각하는 중…':m.a;else{a.style.whiteSpace='normal';a.appendChild(md(m.a))}box.appendChild(a)});
 if(stick||d.history.some(m=>m.a==null))box.scrollTop=1e9}
async function askAbout(q){const c=course(S.course);if(!c)return;const f=file(S.file);
 try{await jpost('/study/chat',{course:c.id,q,file:f&&f.course===c.id?f.id:'',page:S.page||1,variant:S.view||''});await loadAi()}catch(e){serr(e.message)}}
document.querySelectorAll('#aichips button').forEach(b=>b.onclick=()=>askAbout(b.dataset.q.replace('PAGE',S.page)));
$('aiq').addEventListener('keydown',e=>{if(e.key==='Enter'&&!e.shiftKey&&!e.isComposing){e.preventDefault();const v=$('aiq').value.trim();if(v){$('aiq').value='';askAbout(v)}}});
$('ainew').onclick=async()=>{if(!S.course)return;try{await jpost('/study/chat_reset',{course:S.course});loadAi()}catch(e){serr(e.message)}};
// ── 과제 칸: 방식 · 문제 번호 · 교과서 · 찾은 결과 · 다시 만들기 ──
const KO={fig:'그림',table:'표',example:'예제',eq:'식',probfig:'문제 그림'};
function drawHw(light){const box=$('hwform'),f=file(S.file);
 if(!f||f.kind!=='assignment'){box.replaceChildren();return}
 if(light&&box.contains(document.activeElement))return;   // 쓰는 중에는 다시 그리지 않음
 box.replaceChildren();const h=f.hw||{},j=h.job||{};
 const st=el('div','hwst '+(j.state||''));
 st.textContent=busyJob(f)?`만드는 중 ${j.pct||0}% · ${j.msg||''}`:j.state==='error'?'멈춤: '+(j.msg||''):j.state==='done'?(j.msg||'다 만들었어요.'):'아직 안 만들었어요.';
 box.appendChild(st);
 if(busyJob(f)){const b=el('button',null,'진행 창 열기');b.onclick=()=>{watch(f.id);pmShow(true)};box.appendChild(b)}
 const fld=(label,input)=>{const l=el('label','field');l.appendChild(document.createTextNode(label));l.appendChild(input);box.appendChild(l);return input};
 const md=fld('방식',el('select'));[['','저절로 (번호만 있으면 교과서에서 문제를 가져옴)'],['numbers','문제 번호만 — 교과서에서 문제 · 그림을 가져와 문제지'],['full','과제에 문제가 다 있음 — 해설지만']].forEach(([v,t])=>{const o=el('option',null,t);o.value=v;o.selected=(h.mode||'')===v;md.appendChild(o)});
 if(h.mode_used)md.title='지난번에 쓴 방식: '+(h.mode_used==='numbers'?'문제 번호':'문제 전체');
 const nums=fld('문제 번호 (비우면 과제에서 저절로 뽑음)',Object.assign(el('input'),{value:(h.numbers||[]).join(', '),placeholder:(h.numbers_used||[]).join(', ')||'예: 3.2, 3.5, 4.1~4.3'}));
 const books=S.db.files.filter(x=>x.course===f.course&&x.kind==='textbook');
 const tb=fld('교과서',el('select'));const o0=el('option',null,books.length?'이 과목의 교과서 모두에서 찾기':'이 과목에 교과서가 없어요 — 「교과서」 칸에 올려 주세요');o0.value='';tb.appendChild(o0);
 books.forEach(b=>{const o=el('option',null,b.name);o.value=b.id;o.selected=h.textbook===b.id;tb.appendChild(o)});
 const msg=el('span','saved');
 const save=async()=>{try{Object.assign(f,await jpost('/study/hw',{id:f.id,mode:md.value,numbers:nums.value,textbook:tb.value}));msg.textContent='저장됨 — 「다시 만들기」를 누르면 반영돼요'}catch(e){msg.textContent=e.message}};
 [md,tb].forEach(x=>x.onchange=save);nums.addEventListener('change',save);box.appendChild(msg);
 if((h.problems||[]).length){box.appendChild(el('b',null,'교과서에서 찾은 것'));
  h.problems.forEach(p=>{const r=el('div','hwp'+(p.error?' bad':''));
   r.appendChild(el('b',null,p.label||p.num));
   const t=el('span',null,p.error?'못 찾음':`${p.page}쪽`+((p.refs||[]).length?' · '+p.refs.map(x=>`${KO[x.kind]} ${x.num}(${x.page}쪽${x.approx?', 대략':''})`).join(', '):''));r.appendChild(t);
   if((p.missing||[]).length)r.appendChild(el('span','miss','못 찾은 참조: '+p.missing.join(', ')));
   const pi=Object.assign(el('input'),{type:'number',min:1,placeholder:'쪽',value:(h.pages||{})[p.num]||''});pi.title='교과서에서 이 문제가 있는 쪽 — 엉뚱한 곳을 잘랐거나 못 찾았을 때 적고 다시 만들기';pi.setAttribute('aria-label',`문제 ${p.num} 의 교과서 쪽`);
   pi.onchange=async()=>{const pages={...(h.pages||{})};pages[p.num]=pi.value;try{Object.assign(f,await jpost('/study/hw',{id:f.id,pages}));msg.textContent='저장됨 — 「다시 만들기」를 누르면 반영돼요'}catch(e){msg.textContent=e.message}};
   r.appendChild(pi);box.appendChild(r)})}
 const row=el('div','addrow');
 const a=el('button','pri','문제지 + 해설지 다시 만들기');a.onclick=()=>runHw(f,'all');
 const s=el('button',null,'문제지만');s.title='해설은 빼고 문제지만 빨리';s.onclick=()=>runHw(f,'sheet');
 a.disabled=s.disabled=busyJob(f);row.appendChild(a);row.appendChild(s);box.appendChild(row);
 box.appendChild(el('div','muted sm','해설은 Claude 가 이 과목의 수업자료 · 교과서를 읽고 써요. 숫자는 검산하며 보세요.'))}
async function runHw(f,what){try{Object.assign(f,await jpost('/study/hw_run',{id:f.id,what}));watch(f.id);pmShow(true);loadStudy(true)}catch(e){serr(e.message)}}
// ── 진행 창 · 구석 표시 (주인 11월 10일 20:26) — 닫아도 맥에서 계속, 구석 표시를 누르면 다시 열림, 끝나면 결과로 ──
const STAGES=[['read','교과서 읽기'],['find','문제 찾기'],['crop','그림 · 예제 캡처'],['sheet','문제지 PDF'],['solve','해설 쓰기'],['solution','해설지 PDF']];
function watch(id){S.watch=id;put('study.watch',id)}
function pmShow(on){S.pmOpen=on;$('pm').hidden=!on;drawJob();if(on)$('pmx').focus()}
$('pmx').onclick=()=>pmShow(false);
$('pm').addEventListener('click',e=>{if(e.target===$('pm'))pmShow(false)});
document.addEventListener('keydown',e=>{if(e.key==='Escape'&&S.pmOpen)pmShow(false)});
function goResult(f,v){pmShow(false);showTab('study');openFile(f.id,1,v);if(job(f).state==='done'){S.watch='';put('study.watch',null);drawJob()}}
function drawJob(){if(!S.db)return;let f=file(S.watch);
 if(!f||(!busyJob(f)&&job(f).state!=='done'&&job(f).state!=='error')){const r=S.db.files.find(busyJob);if(r){watch(r.id);f=r}}   // 지켜보는 게 없으면 만드는 중인 것
 const chip=$('pchip');
 if(!f||!job(f).state||job(f).state==='idle'){chip.hidden=true;   // 막 넣은 과제가 아직 목록에 없을 수 있음 — 창은 그대로 두고 「준비 중」
  if(S.pmOpen){$('pmname').textContent='';$('pmpct').textContent='0%';$('pmbar').style.width='0';$('pmmsg').textContent='과제를 맥에 넣는 중';$('pmsteps').replaceChildren();$('pmdone').replaceChildren()}return}
 const j=job(f),h=f.hw||{},pct=j.state==='done'?100:(j.pct||0);
 const used=h.mode_used==='full'?['solve','solution']:j.what==='sheet'?['read','find','crop','sheet']:STAGES.map(s=>s[0]);
 // 구석 표시: 원형 진행률. 끝나면 ✓ · 누르면 결과, 멈추면 ! · 누르면 창
 chip.hidden=S.pmOpen;chip.className=j.state;chip.style.setProperty('--p',pct);
 chip.replaceChildren(el('i','ring'),el('span',null,j.state==='done'?'✓ '+(h.solution?'해설지':'문제지'):j.state==='error'?'! 멈춤':pct+'%'));
 chip.title=`${f.name} — ${j.state==='done'?'다 만들었어요. 누르면 열어요':j.state==='error'?j.msg:j.msg||'만드는 중'}`;
 chip.onclick=()=>{if(j.state==='done')goResult(f,h.solution?'solution':'sheet');else pmShow(true)};
 if(!S.pmOpen)return;
 $('pmt').textContent=j.state==='done'?'다 만들었어요':j.state==='error'?'만들다 멈췄어요':'교과서를 읽어 과제 문제/해설지를 생성하는 중';
 $('pmname').textContent=f.name;$('pmbar').style.width=pct+'%';$('pmbarw').setAttribute('aria-valuenow',pct);$('pmpct').textContent=pct+'%';$('pmmsg').textContent=j.msg||'';
 $('pmbar').className=j.state==='error'?'bad':'';
 const ol=$('pmsteps');ol.replaceChildren();const at=used.indexOf(j.stage);
 STAGES.filter(s=>used.includes(s[0])).forEach(([k,n],i)=>{const li=el('li',null,n);
  li.className=j.state==='done'||i<at?'ok':i===at?(j.state==='error'?'bad':'now'):'';ol.appendChild(li)});
 const btns=$('pmdone');btns.replaceChildren();
 if(j.state==='done'){if(h.sheet){const b=el('button',null,'문제지 보기');b.onclick=()=>goResult(f,'sheet');btns.appendChild(b)}
  if(h.solution){const b=el('button','pri','해설지 보기');b.onclick=()=>goResult(f,'solution');btns.appendChild(b)}}
 if(j.state==='error'){const b=el('button','pri','다시 만들기');b.onclick=()=>runHw(f,j.what||'all');btns.appendChild(b);
  const o=el('button',null,'과제 칸 열기');o.onclick=()=>{pmShow(false);showTab('study');openFile(f.id);spTab('hw')};btns.appendChild(o)}
 $('pmnote').style.display=busyJob(f)?'':'none'}
// 과목 칸 — 이름 · 시험 날짜 · 범위 · 할 일, 그리고 열린 자료 옮기기 · 이름 바꾸기 · 종류 · 지우기
function renderCourse(){if(AI.course!==S.course)loadAi(aiOpen());else drawAi();const box=$('cform');if(box.contains(document.activeElement)&&box.childElementCount)return;box.replaceChildren();const c=course(S.course);
 if(!c){box.appendChild(el('div','muted','과목을 고르면 시험 날짜 · 범위 · 할 일을 적을 수 있어요.'));return}
 const fld=(label,input)=>{const l=el('label','field');l.appendChild(document.createTextNode(label));l.appendChild(input);box.appendChild(l);return input};
 const nm=fld('과목 이름',Object.assign(el('input'),{value:c.name}));
 const ex=fld('시험 날짜',Object.assign(el('input'),{type:'date',value:c.exam||''}));
 const sc=fld('시험 범위 · 교수님 말씀',Object.assign(el('textarea'),{rows:4,value:c.scope||''}));
 const msg=el('span','saved');
 const save=async()=>{try{const r=await jpost('/study/course',{id:c.id,name:nm.value,exam:ex.value,scope:sc.value});Object.assign(c,r);msg.textContent='저장됨 '+hm(Date.now());renderList()}catch(e){msg.textContent=e.message}};
 [nm,ex,sc].forEach(i=>i.addEventListener('change',save));box.appendChild(msg);
 box.appendChild(el('b',null,'할 일'));
 c.todo.forEach((t,i)=>{const r=el('label','todo'+(t.done?' done':''));const cb=Object.assign(el('input'),{type:'checkbox',checked:t.done});
  cb.onchange=()=>saveTodo(c,c.todo.map((x,j)=>j===i?{...x,done:cb.checked}:x));r.appendChild(cb);r.appendChild(el('span',null,t.t));
  const x=el('button','x','✕');x.title='지우기';x.onclick=e=>{e.preventDefault();saveTodo(c,c.todo.filter((_,j)=>j!==i))};r.appendChild(x);box.appendChild(r)});
 const ar=el('div','addrow');const ti=Object.assign(el('input'),{placeholder:'예: 4~7강 공식 외우기'});const tb=el('button',null,'추가');
 const addT=()=>{const v=ti.value.trim();if(v)saveTodo(c,[...c.todo,{t:v,done:false}])};tb.onclick=addT;ti.addEventListener('keydown',e=>{if(e.key==='Enter'&&!e.isComposing)addT()});
 ar.appendChild(ti);ar.appendChild(tb);box.appendChild(ar);
 const f=file(S.file);
 if(f&&f.course===c.id){box.appendChild(el('b',null,'열린 자료'));
  const rn=fld('이름',Object.assign(el('input'),{value:f.name}));rn.addEventListener('change',async()=>{try{const r=await jpost('/study/file',{id:f.id,name:rn.value});f.name=r.name;$('svname').textContent=f.name;renderList()}catch(e){serr(e.message);rn.value=f.name}});
  const kd=fld('종류',el('select'));Object.entries(KIND).forEach(([k,n])=>{const o=el('option',null,n);o.value=k;o.selected=f.kind===k;kd.appendChild(o)});
  kd.onchange=async()=>{try{Object.assign(f,await jpost('/study/file',{id:f.id,kind:kd.value}));$('sptab-hw').style.display=f.kind==='assignment'?'':'none';renderList();drawHw();drawSv()}catch(e){serr(e.message);kd.value=f.kind}};
  const mv=fld('다른 과목으로 옮기기',el('select'));S.db.courses.forEach(x=>{const o=el('option',null,x.name);o.value=x.id;o.selected=x.id===f.course;mv.appendChild(o)});
  mv.onchange=async()=>{try{await jpost('/study/file',{id:f.id,course:mv.value});f.course=mv.value;S.course=mv.value;S.open.add(mv.value);saveOpen();renderList();renderCourse()}catch(e){serr(e.message)}};
  const del=el('button','danger','이 자료 지우기');del.onclick=async()=>{if(!confirm(`「${f.name}」을(를) 지울까요? 맥의 study-data/trash 로 옮겨져서 되살릴 수 있어요.`))return;
   try{await jpost('/study/file_delete',{id:f.id});closeFile();loadStudy()}catch(e){serr(e.message)}};box.appendChild(del)}
 const dc=el('button','danger','과목 지우기');dc.onclick=async()=>{if(!confirm(`「${c.name}」 과목을 지울까요?`))return;
  try{await jpost('/study/course_delete',{id:c.id});S.course='';loadStudy()}catch(e){serr(e.message)}};box.appendChild(dc)}
async function saveTodo(c,todo){try{const r=await jpost('/study/course',{id:c.id,todo});Object.assign(c,r);renderCourse()}catch(e){serr(e.message)}}
$('addc').onclick=async()=>{const n=prompt('과목 이름');if(!n||!n.trim())return;
 try{const c=await jpost('/study/course',{name:n.trim()});S.course=c.id;put('study.course',c.id);S.open.add(c.id);saveOpen();await loadStudy()}catch(e){serr(e.message)}};
// 올리기 — 끌어 놓기 · 고르기. 고른 과목 · 고른 종류로, 하나씩. 4MB 조각으로 나눠 보내고 끊기면 받은 데부터 이어 보냄 (주인 11월 10일 20:35)
function setKind(k){S.kind=k;put('study.kind',k);document.querySelectorAll('#dkind button').forEach(b=>b.classList.toggle('on',b.dataset.k===k));
 $('droplabel').textContent=`PDF 끌어 놓기 · 눌러서 고르기 → ${KIND[k]}`}
setKind(KIND[S.kind]?S.kind:'lecture');
document.querySelectorAll('#dkind button').forEach(b=>b.onclick=e=>{e.stopPropagation();setKind(b.dataset.k)});
const CHUNK=4*1024*1024;
async function upId(f){const s=`${S.course}|${S.kind}|${f.name}|${f.size}|${f.lastModified}`;
 if(crypto.subtle){const h=await crypto.subtle.digest('SHA-256',new TextEncoder().encode(s));return [...new Uint8Array(h)].slice(0,16).map(x=>x.toString(16).padStart(2,'0')).join('')}
 let a=0;for(const ch of s)a=(a*31+ch.charCodeAt(0))>>>0;return (a.toString(16)+Date.now().toString(16)+'0000000000000000').slice(0,32)}   // http 주소에서는 crypto.subtle 이 없음
async function sendFile(f,show){const up=await upId(f);
 let have=(await (await api('/study/upload_status?up='+up)).json()).have||0,tries=0;
 while(have<f.size){show(Math.floor(have/f.size*100));
  try{const r=await api(`/study/upload_part?up=${up}&off=${have}`,{method:'POST',body:f.slice(have,have+CHUNK)});const j=await r.json();if(!r.ok)throw new Error(j.error||r.status);have=j.have;tries=0}
  catch(e){if(e.message==='401'||++tries>6)throw e;await sleep(1000*tries);   // 끊김 — 맥이 받은 만큼을 다시 묻고 거기서부터
   have=(await (await api('/study/upload_status?up='+up)).json().catch(()=>({have}))).have??have}}
 show(100);return jpost('/study/upload_done',{up,course:S.course,name:f.name,kind:S.kind,size:f.size})}
async function upload(list){const pdfs=[...list].filter(f=>/\.pdf$/i.test(f.name)||f.type==='application/pdf');
 if(!pdfs.length){serr('PDF 만 올릴 수 있어요.');return}
 if(!course(S.course)){serr('과목을 먼저 고르거나 만들어 주세요.');return}
 const lab=$('droplabel'),label=lab.textContent;let ok=0,last='',hw='';
 for(const [i,f] of pdfs.entries()){
  try{const j=await sendFile(f,p=>lab.textContent=`올리는 중 ${i+1}/${pdfs.length} · ${f.name} ${p}%`);ok++;last=j.id;if(j.kind==='assignment')hw=j.id}
  catch(e){if(e.message==='401')return;serr(`${f.name}: ${e.message}`)}}
 lab.textContent=label;S.open.add(S.course);saveOpen();
 if(hw){watch(hw);pmShow(true)}
 await loadStudy();if(ok===1&&last)openFile(last)}
async function addNumbered(){if(!course(S.course)){serr('과목을 먼저 고르거나 만들어 주세요.');return}
 const t=prompt('과제 문제 번호 (예: 3.2, 3.5, 4.1~4.3)');if(!t||!t.trim())return;
 const d=new Date(),name=`과제 ${d.getMonth()+1}월 ${d.getDate()}일`;
 try{const f=await jpost('/study/assignment',{course:S.course,name,text:t.trim()});S.open.add(S.course);saveOpen();watch(f.id);pmShow(true);await loadStudy();openFile(f.id)}catch(e){serr(e.message)}}
$('drop').onclick=()=>$('pick').click();$('pick').onchange=()=>{upload($('pick').files);$('pick').value=''};
const SV=$('study');let dragN=0;
SV.addEventListener('dragenter',e=>{if(e.dataTransfer.types.includes('Files')){e.preventDefault();dragN++;SV.classList.add('over')}});
SV.addEventListener('dragleave',()=>{if(--dragN<=0){dragN=0;SV.classList.remove('over')}});
SV.addEventListener('dragover',e=>{if(e.dataTransfer.types.includes('Files'))e.preventDefault()});
SV.addEventListener('drop',e=>{e.preventDefault();dragN=0;SV.classList.remove('over');if(e.dataTransfer.files.length)upload(e.dataTransfer.files)});
function start(){if(started)return;started=true;poll();notices();screenLoop();showTab(tab)}
if(B){$('out').style.display='none';$('home').style.display=''}   // 논문 정리 웹 안: 로그인은 그쪽이 맡음
api('/state').then(()=>start()).catch(e=>{if(e.message!=='401'){$('mode').className='off';$('mode').innerHTML='<b>● </b>맥에 닿지 않아요';start()}});
"""
WEB_BUILD = hashlib.blake2b((WEB + WEB_JS).encode(), digest_size=6).hexdigest()
WEB_JS = WEB_JS.replace("__BUILD__", WEB_BUILD)
