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
#scr{width:100%;height:100%;object-fit:contain;display:block;user-select:none;-webkit-user-drag:none;cursor:crosshair}
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
#svbar{display:flex;gap:8px;align-items:center;padding:8px 12px;border-bottom:1px solid var(--line);background:var(--panel);flex-wrap:wrap}
#svname{font-weight:600;flex:1;min-width:120px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
#svpage{width:70px}
.seg{display:flex}.seg button{border-radius:0;margin-left:-1px;font-size:13px;padding:5px 9px}
.seg button:first-child{border-radius:8px 0 0 8px}.seg button:last-child{border-radius:0 8px 8px 0}
#pdf{flex:1;border:0;width:100%;background:var(--scr)}
#svempty{flex:1;display:flex;align-items:center;justify-content:center;color:var(--sub);text-align:center;padding:30px}
#sp{display:flex;flex-direction:column;min-height:0;border-left:1px solid var(--line);background:var(--panel)}
#sptabs{display:flex;border-bottom:1px solid var(--line)}
#sptabs button{flex:1;border:0;border-radius:0;border-bottom:2px solid transparent;background:none;padding:9px 4px}
#sptabs button.on{border-bottom-color:var(--acc);color:var(--acc);font-weight:600}
.pane{flex:1;min-height:0;overflow:auto;padding:12px;display:none;flex-direction:column;gap:10px}
.pane.on{display:flex}
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
  <div id="tools">
   <div class="g"><button data-s="0" class="on">주 화면</button><button data-s="1">세로 모니터</button></div>
   <div class="g"><button id="drag" title="켜 두면 누른 채 끈 만큼 맥에서 끌기">끌기</button></div>
   <div class="g"><button id="son">화면 켜기</button><button id="soff">화면 끄기</button><button id="scrm">주 화면 …</button><button id="scrd">세로 화면 …</button></div>
   <div class="g"><button id="hm">핸드마우스 …</button></div>
   <div class="g"><label for="vol">음량</label><input id="vol" type="range" min="0" max="100" disabled><span id="volv">…</span></div>
  </div>
  <div id="view"><img id="scr" alt="맥 화면"><div id="viewmsg"></div></div>
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
  <div class="drop" id="drop">PDF 를 여기로 끌어 놓거나 눌러서 고르기<input id="pick" type="file" accept="application/pdf,.pdf" multiple hidden></div>
  <div style="padding:0 8px 10px"><button id="addc" style="width:100%">+ 과목 추가</button></div>
 </aside>
 <section id="sv">
  <div id="svbar" style="display:none">
   <span id="svname"></span>
   <label class="muted" for="svpage" style="padding:0">쪽</label><input id="svpage" type="number" min="1" aria-label="쪽 번호로 가기"><span id="svpages" class="muted" style="padding:0"></span>
   <div class="seg" id="seg"><button data-st="new">안 봄</button><button data-st="reading">보는 중</button><button data-st="done">다 봄</button><button data-st="review">다시 볼 것</button></div>
   <button id="svopen" title="새 탭에서 크게">새 탭</button>
  </div>
  <div id="svempty">왼쪽에서 자료를 고르세요.<br>PDF 를 이 화면 아무 데나 끌어 놓으면 고른 과목에 들어가요.</div>
  <iframe id="pdf" title="강의자료" style="display:none"></iframe>
 </section>
 <aside id="sp">
  <nav id="sptabs"><button data-p="note" class="on">메모</button><button data-p="marks">쪽 표시</button><button data-p="ai">비서에게</button><button data-p="course">과목</button></nav>
  <div class="pane on" id="p-note"><textarea id="note" placeholder="이 자료 메모. 쓰면 저절로 저장돼요." aria-label="자료 메모" disabled></textarea><span class="saved" id="saved"></span></div>
  <div class="pane" id="p-marks">
   <div class="addrow"><input id="mkp" type="number" min="1" placeholder="쪽" style="max-width:70px" aria-label="표시할 쪽"><input id="mkt" placeholder="한 줄 (예: 시험에 나온다 함)" aria-label="표시 내용"><button id="mkadd">표시</button></div>
   <div id="mklist"></div>
  </div>
  <div class="pane" id="p-ai">
   <div class="muted" style="padding:0" id="aiwhat">자료를 고르면 그 자료를 비서가 직접 읽고 답해요.</div>
   <div class="chips" id="aichips"><button data-q="이 자료의 핵심을 시험공부용으로 요약해 줘. 꼭 외울 정의 · 공식은 따로 모아 줘.">핵심 요약</button><button data-q="이 자료로 시험 예상 문제 5개를 내 줘. 답과 풀이는 맨 아래에 따로.">예상 문제 5개</button><button data-q="이 자료에 나오는 공식을 모두 모아 각 기호의 뜻과 언제 쓰는지 정리해 줘.">공식 정리</button><button data-q="PAGE 쪽을 처음 배우는 사람에게 설명하듯 풀어 줘.">이 쪽 설명</button></div>
   <textarea id="aiq" rows="3" placeholder="이 자료에 대해 묻기 (Enter 보내기)" aria-label="자료에 대해 묻기" disabled></textarea>
   <div id="ailog" style="display:flex;flex-direction:column;gap:8px"></div>
  </div>
  <div class="pane" id="p-course">
   <div id="cform" style="display:flex;flex-direction:column;gap:10px"></div>
  </div>
 </aside>
</div>
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
  if(s.screens)scrDraw(s.screens);if(s.handmouse)hmDraw(s.handmouse.on);
  if(s.volume&&s.volume.v!=null&&!volDragging){$('vol').disabled=false;$('vol').value=s.volume.v;$('volv').textContent=s.volume.muted?'음소거':s.volume.v}}
 catch(e){if(e.message==='401')return;$('mode').className='off';$('mode').innerHTML='<b>● </b>맥에 닿지 않아요'}
 await sleep(3000)}}
// ── 맥 화면 ──
let scr=0,tag='';
document.querySelectorAll('#tools [data-s]').forEach(b=>b.onclick=()=>{document.querySelectorAll('#tools [data-s]').forEach(x=>x.classList.remove('on'));b.classList.add('on');scr=+b.dataset.s;tag=''});
function vmsg(t){$('viewmsg').style.display=t?'flex':'none';$('viewmsg').textContent=t||''}
async function screenLoop(){let fails=0;while(true){
  if(document.hidden||tab!=='desk'){await sleep(500);continue}   // 강의자료 탭에서는 맥 화면을 안 받음
  const R=$('view').getBoundingClientRect(),w=Math.min(2560,Math.round(R.width*devicePixelRatio)),s=scr;
  try{const r=await api(`/screen/${s}.jpg?w=${w}&q=60&h=${tag}`);
   if(r.status===200){const b=await r.blob();if(s===scr){tag=r.headers.get('X-Frame')||'';const u=URL.createObjectURL(b),old=$('scr').src;$('scr').src=u;if(old.startsWith('blob:'))setTimeout(()=>URL.revokeObjectURL(old),1000)}vmsg('')}
   else if(r.status===503&&r.headers.get('X-Asleep')){vmsg('맥 화면이 꺼져 있어요. 위의 「화면 켜기」를 눌러 주세요.');await sleep(1500)}
   else if(r.status===404){vmsg('이 화면이 없어요.');await sleep(2000)}
   else if(r.status!==204){vmsg('화면을 못 받았어요 ('+r.status+')');await sleep(1000)}
   fails=0}
  catch(e){if(e.message==='401')return;fails++;vmsg('연결이 끊겼어요. 다시 잇는 중…');await sleep(Math.min(5000,500*fails))}
  await sleep(150)}}
function frac(cx,cy){const im=$('scr'),R=im.getBoundingClientRect(),iw=im.naturalWidth||1,ih=im.naturalHeight||1;
 const k=Math.min(R.width/iw,R.height/ih),w=iw*k,h=ih*k,x0=R.left+(R.width-w)/2,y0=R.top+(R.height-h)/2;
 return[(cx-x0)/w,(cy-y0)/h]}
const inside=([f,g])=>f>=0&&f<=1&&g>=0&&g<=1;
function act(ev){ev.screen=scr;tag='';return api('/input',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(ev)}).then(r=>r.json()).then(r=>{if(r.r&&r.r!=='ok')$('st').textContent=r.r}).catch(()=>{})}
// 클릭 하나는 잠깐 기다렸다 보냄 — 곧바로 한 번 더 누르면 두 번 클릭(맥은 클릭 횟수를 따로 셈)
let down=null,clickT=null,dragMode=false;
const SCR=$('scr');
SCR.addEventListener('mousedown',e=>{if(e.button!==0)return;e.preventDefault();down={x:e.clientX,y:e.clientY}});
SCR.addEventListener('mouseup',e=>{if(e.button!==0||!down)return;const p=frac(down.x,down.y),moved=Math.hypot(e.clientX-down.x,e.clientY-down.y)>6;down=null;
 if(!inside(p))return;
 if(moved){if(dragMode){const q=frac(e.clientX,e.clientY);act({action:'drag',x:p[0],y:p[1],x2:q[0],y2:q[1]})}return}
 if(clickT){clearTimeout(clickT);clickT=null;act({action:'double',x:p[0],y:p[1]})}
 else clickT=setTimeout(()=>{clickT=null;act({action:'click',x:p[0],y:p[1]})},260)});
SCR.addEventListener('contextmenu',e=>{e.preventDefault();const p=frac(e.clientX,e.clientY);if(inside(p))act({action:'right',x:p[0],y:p[1]})});
let wy=0,wx=0,wt=null,wp=null;
SCR.addEventListener('wheel',e=>{e.preventDefault();wp=frac(e.clientX,e.clientY);wy+=-e.deltaY;wx+=-e.deltaX;
 if(!wt)wt=setTimeout(()=>{wt=null;if(inside(wp)&&(Math.abs(wy)>=1||Math.abs(wx)>=1))act({action:'scroll',x:wp[0],y:wp[1],dy:Math.round(wy),dx:Math.round(wx)});wy=0;wx=0},60)},{passive:false});
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
const S={db:null,course:get('study.course')||'',file:'',filter:'',q:'',hits:null,blob:{},page:1};
const el=(tag,cls,text)=>{const d=document.createElement(tag);if(cls)d.className=cls;if(text!=null)d.textContent=text;return d};
async function jpost(path,obj){const r=await api(path,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(obj)});
 const j=await r.json().catch(()=>({}));if(!r.ok)throw new Error(j.error||('맥이 거절했어요 ('+r.status+')'));return j}
function serr(msg){const d=el('div','err',msg);$('serr').appendChild(d);setTimeout(()=>d.remove(),8000)}   // 목록을 다시 그려도 안 지워지게 따로 칸
const course=id=>(S.db?.courses||[]).find(c=>c.id===id);
const file=id=>(S.db?.files||[]).find(f=>f.id===id);
function dday(exam){if(!exam)return null;const t=new Date();t.setHours(0,0,0,0);const d=Math.round((new Date(exam+'T00:00:00')-t)/864e5);
 return d>0?{t:'D-'+d,c:d<=7?'soon':''}:d===0?{t:'D-day',c:'soon'}:{t:'끝남',c:'past'}}
async function loadStudy(){try{S.db=await (await api('/study/list')).json()}catch(e){if(e.message!=='401')$('slist').replaceChildren(el('div','muted','맥에 닿지 않아요.'));return}
 if(!course(S.course))S.course=S.db.courses[0]?.id||'';
 if(S.file&&!file(S.file))closeFile();
 if(!S.file){const last=get('study.file');if(last&&file(last))openFile(last)}
 renderList();renderCourse();
 if(S.db.files.some(f=>f.pages==null&&!f.index_error))setTimeout(()=>{if(tab==='study')loadStudy()},3000)}   // 쪽 수 · 본문을 뽑는 중
function renderList(){const box=$('slist');box.replaceChildren();
 if(S.hits){const head=el('div','muted',S.hits.length?`「${S.q}」 ${S.hits.length}곳`+(S.hits.length>=60?' (60곳까지만)':''):`「${S.q}」 은(는) 어느 자료에도 없어요.`);box.appendChild(head);
  const words=S.q.toLowerCase().split(/\s+/).filter(Boolean);
  S.hits.forEach(h=>{const d=el('div','hit');const b=el('b',null,`${h.name} · ${h.page}쪽`);d.appendChild(b);const s=el('span','s');
   let rest=h.snip;const low=()=>rest.toLowerCase();   // 찾은 말에 형광펜(textContent 로만 넣음)
   while(rest){let at=-1,w='';words.forEach(x=>{const i=low().indexOf(x);if(i>=0&&(at<0||i<at)){at=i;w=x}});
    if(at<0){s.appendChild(document.createTextNode(rest));break}
    s.appendChild(document.createTextNode(rest.slice(0,at)));s.appendChild(el('mark',null,rest.slice(at,at+w.length)));rest=rest.slice(at+w.length)}
   d.appendChild(s);d.onclick=()=>{S.course=h.course;openFile(h.id,h.page)};box.appendChild(d)});return}
 if(!S.db.courses.length){box.appendChild(el('div','muted','아래 「+ 과목 추가」로 과목부터 만들어 주세요.'));return}
 S.db.courses.forEach(c=>{const fs=S.db.files.filter(f=>f.course===c.id);const r=el('div','crs'+(c.id===S.course?' sel':''));
  r.appendChild(el('span','nm',c.name));const dd=dday(c.exam);if(dd){const b=el('span','dday '+dd.c,dd.t);b.title='시험 '+c.exam;r.appendChild(b)}
  r.appendChild(el('span','prog',`${fs.filter(f=>f.status==='done').length}/${fs.length}`));
  r.onclick=()=>{S.course=c.id;put('study.course',c.id);renderList();renderCourse()};box.appendChild(r);
  if(c.id!==S.course)return;
  const list=el('div','files');const shown=fs.filter(f=>!S.filter||f.status===S.filter);
  if(!fs.length)list.appendChild(el('div','muted','아직 자료가 없어요. PDF 를 끌어 놓아 주세요.'));
  else if(!shown.length)list.appendChild(el('div','muted',`「${ST[S.filter]}」 자료가 없어요.`));
  shown.forEach(f=>{const d=el('div','fl'+(f.id===S.file?' sel':''));const dot=el('span','dot '+f.status);dot.title=ST[f.status];d.appendChild(dot);
   d.appendChild(el('span','nm',f.name));d.appendChild(el('span','pg',f.pages!=null?f.pages+'쪽':f.index_error?'검색 안 됨':'읽는 중…'));
   d.title=f.index_error||f.name;d.onclick=()=>openFile(f.id);list.appendChild(d)});
  box.appendChild(list)})}
document.querySelectorAll('#filt button').forEach(b=>b.onclick=()=>{S.filter=b.dataset.f;document.querySelectorAll('#filt button').forEach(x=>x.classList.toggle('on',x===b));renderList()});
let sqT=null;
$('sq').addEventListener('input',()=>{clearTimeout(sqT);sqT=setTimeout(async()=>{const q=$('sq').value.trim();S.q=q;
 if(!q){S.hits=null;renderList();return}
 try{const r=await (await api('/study/search?q='+encodeURIComponent(q))).json();if(S.q===q){S.hits=r.hits||[];renderList()}}catch(e){}},300)});
$('sq').addEventListener('keydown',e=>{if(e.key==='Escape'){$('sq').value='';S.q='';S.hits=null;renderList()}});
// 자료 열기 — PDF 를 열쇠와 함께 받아 브라우저 안 PDF 보기로. 쪽 이동은 #page=N
function closeFile(){S.file='';put('study.file',null);$('pdf').style.display='none';$('svbar').style.display='none';$('svempty').style.display='';
 $('note').value='';$('note').disabled=true;$('aiq').disabled=true;$('mklist').replaceChildren();$('ailog').replaceChildren();
 $('aiwhat').textContent='자료를 고르면 그 자료를 비서가 직접 읽고 답해요.'}
async function openFile(id,page){const f=file(id);if(!f)return;
 if(S.file!==id){S.file=id;put('study.file',id);S.course=f.course;put('study.course',f.course);
  $('svempty').style.display='none';$('svbar').style.display='';$('pdf').style.display='';
  $('svname').textContent=f.name;$('svname').title=f.name;$('svpages').textContent=f.pages?'/ '+f.pages:'';
  $('note').value=f.note||'';$('note').disabled=false;$('saved').textContent='';$('aiq').disabled=false;$('aiwhat').textContent=`「${f.name}」에 대해 물어요. 비서가 이 PDF 를 직접 읽어요.`;
  drawSeg();drawMarks();drawAi();renderList();renderCourse()}
 if(!S.blob[id]){$('svempty').style.display='';$('svempty').textContent='자료를 받는 중…';$('pdf').style.display='none';
  try{const r=await api(`/study/file/${id}.pdf`);if(!r.ok)throw new Error((await r.json().catch(()=>({}))).error||String(r.status));S.blob[id]=URL.createObjectURL(await r.blob())}
  catch(e){$('svempty').textContent='자료를 못 받았어요: '+e.message;return}
  if(S.file!==id)return;$('svempty').style.display='none';$('pdf').style.display=''}
 gotoPage(page||f.last_page||1)}
function gotoPage(n){const f=file(S.file);if(!f)return;n=Math.max(1,Math.min(+n||1,f.pages||1e6));S.page=n;$('svpage').value=n;
 $('pdf').src='about:blank';setTimeout(()=>{$('pdf').src=S.blob[f.id]+'#page='+n},30);   // 같은 주소에서 #page 만 바꾸면 PDF 보기가 안 움직여서
 if(f.last_page!==n){f.last_page=n;jpost('/study/file',{id:f.id,last_page:n}).catch(()=>{})}}
$('svpage').addEventListener('keydown',e=>{if(e.key==='Enter')gotoPage($('svpage').value)});
$('svpage').addEventListener('change',()=>gotoPage($('svpage').value));
$('svopen').onclick=()=>{if(S.file&&S.blob[S.file])window.open(S.blob[S.file]+'#page='+S.page,'_blank')};
function drawSeg(){const f=file(S.file);document.querySelectorAll('#seg button').forEach(b=>b.classList.toggle('on',!!f&&b.dataset.st===f.status))}
document.querySelectorAll('#seg button').forEach(b=>b.onclick=async()=>{const f=file(S.file);if(!f)return;const old=f.status;f.status=b.dataset.st;drawSeg();renderList();
 try{await jpost('/study/file',{id:f.id,status:f.status})}catch(e){f.status=old;drawSeg();renderList();serr(e.message)}});
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
  d.onclick=()=>gotoPage(m.p);box.appendChild(d)})}
async function saveMarks(f,marks){try{const r=await jpost('/study/file',{id:f.id,marks});f.marks=r.marks;drawMarks()}catch(e){serr(e.message)}}
function addMark(){const f=file(S.file);if(!f)return;const p=+$('mkp').value||S.page||1,t=$('mkt').value.trim();$('mkt').value='';saveMarks(f,[...f.marks,{p,t}])}
$('mkadd').onclick=addMark;$('mkt').addEventListener('keydown',e=>{if(e.key==='Enter'&&!e.isComposing)addMark()});
// 오른쪽 칸 탭
document.querySelectorAll('#sptabs button').forEach(b=>b.onclick=()=>{document.querySelectorAll('#sptabs button').forEach(x=>x.classList.toggle('on',x===b));
 document.querySelectorAll('#sp .pane').forEach(p=>p.classList.toggle('on',p.id==='p-'+b.dataset.p));if(b.dataset.p==='marks')$('mkp').value=S.page||''});
// 비서에게 — 자료 경로 · 쪽을 붙여 /ask 로(비서가 이 맥에서 파일을 직접 읽음). 주고받은 것은 이 브라우저에 자료별로
function aiKey(){return 'study.ai.'+S.file}
function drawAi(){const box=$('ailog');box.replaceChildren();let log=[];try{log=JSON.parse(get(aiKey())||'[]')}catch(e){}
 log.slice().reverse().forEach(m=>box.appendChild(el('div','qa'+(m.q?' q':''),m.t)))}
function aiPush(m){let log=[];try{log=JSON.parse(get(aiKey())||'[]')}catch(e){}log.push(m);put(aiKey(),JSON.stringify(log.slice(-30)))}
async function askAbout(q){const f=file(S.file),c=course(f?.course);if(!f||busy)return;
 const text=`[강의자료 · 비서 웹] 과목: ${c?c.name:''}${c&&c.exam?` (시험 ${c.exam})`:''}\n자료: ${f.name} — 파일 ${S.db.root}/files/${f.id}.pdf (${f.pages||'?'}쪽, 지금 ${S.page}쪽을 보는 중)\n요청: ${q}`;
 aiPush({q:1,t:q});drawAi();const w=el('div','qa wait','비서가 읽는 중… (긴 자료는 백그라운드로 넘길 수도 있어요)');$('ailog').prepend(w);setBusy(true,'생각 중…');$('aiq').disabled=true;
 try{const r=await (await api('/ask',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({text})})).json();aiPush({t:r.full||r.reply||r.error||'(답이 비었어요)'})}
 catch(e){if(e.message!=='401')aiPush({t:'맥에 닿지 않아요.'})}
 finally{setBusy(false,'보내기');$('aiq').disabled=!S.file;drawAi()}}
document.querySelectorAll('#aichips button').forEach(b=>b.onclick=()=>askAbout(b.dataset.q.replace('PAGE',S.page)));
$('aiq').addEventListener('keydown',e=>{if(e.key==='Enter'&&!e.shiftKey&&!e.isComposing){e.preventDefault();const v=$('aiq').value.trim();if(v){$('aiq').value='';askAbout(v)}}});
// 과목 칸 — 이름 · 시험 날짜 · 범위 · 할 일, 그리고 열린 자료 옮기기 · 이름 바꾸기 · 지우기
function renderCourse(){const box=$('cform');box.replaceChildren();const c=course(S.course);
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
  const mv=fld('다른 과목으로 옮기기',el('select'));S.db.courses.forEach(x=>{const o=el('option',null,x.name);o.value=x.id;o.selected=x.id===f.course;mv.appendChild(o)});
  mv.onchange=async()=>{try{await jpost('/study/file',{id:f.id,course:mv.value});f.course=mv.value;S.course=mv.value;renderList();renderCourse()}catch(e){serr(e.message)}};
  const del=el('button','danger','이 자료 지우기');del.onclick=async()=>{if(!confirm(`「${f.name}」을(를) 지울까요? 맥의 study-data/trash 로 옮겨져서 되살릴 수 있어요.`))return;
   try{await jpost('/study/file_delete',{id:f.id});closeFile();loadStudy()}catch(e){serr(e.message)}};box.appendChild(del)}
 const dc=el('button','danger','과목 지우기');dc.onclick=async()=>{if(!confirm(`「${c.name}」 과목을 지울까요?`))return;
  try{await jpost('/study/course_delete',{id:c.id});S.course='';loadStudy()}catch(e){serr(e.message)}};box.appendChild(dc)}
async function saveTodo(c,todo){try{const r=await jpost('/study/course',{id:c.id,todo});Object.assign(c,r);renderCourse()}catch(e){serr(e.message)}}
$('addc').onclick=async()=>{const n=prompt('과목 이름');if(!n||!n.trim())return;
 try{const c=await jpost('/study/course',{name:n.trim()});S.course=c.id;put('study.course',c.id);await loadStudy()}catch(e){serr(e.message)}};
// 올리기 — 끌어 놓기 · 고르기. 고른 과목으로, 하나씩
async function upload(list){const pdfs=[...list].filter(f=>/\.pdf$/i.test(f.name)||f.type==='application/pdf');
 if(!pdfs.length){serr('PDF 만 올릴 수 있어요.');return}
 if(!course(S.course)){serr('과목을 먼저 고르거나 만들어 주세요.');return}
 const d=$('drop'),label=d.firstChild.textContent;let ok=0,last='';
 for(const [i,f] of pdfs.entries()){d.firstChild.textContent=`올리는 중 ${i+1}/${pdfs.length} · ${f.name}`;
  try{const r=await api(`/study/upload?course=${encodeURIComponent(S.course)}&name=${encodeURIComponent(f.name)}`,{method:'POST',body:f});
   const j=await r.json().catch(()=>({}));if(!r.ok)throw new Error(j.error||String(r.status));ok++;last=j.id}
  catch(e){if(e.message==='401')return;serr(`${f.name}: ${e.message}`)}}
 d.firstChild.textContent=label;await loadStudy();if(ok===1&&last)openFile(last)}
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
