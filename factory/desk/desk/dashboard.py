"""화면 — 첫 번째 모니터에 띄우는 상태판. 이 맥 안에서만 열립니다(127.0.0.1).

/          상태판 (전체 화면 크롬 앱 창)
/events    상태가 바뀔 때마다 보내는 스트림(SSE) — 화면 판(build)이 바뀌면 열린 페이지가 스스로 새로고침
/api/<명령> deskctl 이 부르는 곳: wake · sleep · brief · mute · unmute · stop · say · show
           그리고 「목소리」 설정 창: tts(지금 값) · tts_test(들어 보기) · tts_save(저장 → config.toml [tts])
           위쪽 모델 토글: model(고른 모델 → config.toml [brain] model, 빈 글이면 지금 모델)
/handcam.jpg · /handcam.json  hand-mouse 카메라(손 인식 그림) 한 장 · 상태 줄 — 「손 카메라」 칸.
           페이지가 한 장씩 계속 받아 감(긴 MJPEG 스트림은 deskd 가 다시 뜨면 사파리에서 오류 없이 마지막 장에 멈춰 있었다,
           주인 15:47). 새 그림이 몇 초 안 오면 칸에 「멈춤」.
           hand-mouse(overlay.py)는 HANDCAM/want 가 몇 초 안에 건드려졌을 때만 view.jpg · view.json 을 쓴다.

「작업 현황」 칸은 `claude agents --json` 과 ~/.claude/jobs/<id>/state.json · timeline.jsonl 을 몇 초마다 읽어 채웁니다
(watch_agents). 주인 손이 필요한 것(권한 · 질문 · blocked)이 맨 위, 그다음 작업 중 · 멈춤(까닭 · 마지막 말) · 끝남.
"""
from __future__ import annotations

import hashlib
import json
import os
import re
import shutil
import subprocess
import threading
import time
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

HANDCAM = os.path.expanduser("~/.cache/hand-mouse")   # hand-mouse overlay.py DESK_DIR 와 같은 자리
HANDCAM_STALE_S = 3.0   # 이만큼 새 그림이 없으면 「멈춤」
HANDCAM_GONE_S = 60.0   # 이만큼 없으면 꺼진 것으로 (칸을 숨김 — hand-mouse off · 화면 꺼짐)

PAGE = r"""<!doctype html><html lang="ko"><head><meta charset="utf-8"><title>책상</title>
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>
:root{--bg:#0d1117;--panel:#161b22;--line:#262d36;--ink:#e6edf3;--dim:#8b949e;--acc:#56d4c1;--warn:#e3b341;--bad:#f47067}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font:23px/1.5 "Apple SD Gothic Neo","Noto Sans KR",system-ui,sans-serif;padding:32px 40px;height:100vh;display:grid;grid-template-rows:auto 1fr auto;gap:24px}
header{display:flex;align-items:baseline;gap:24px;flex-wrap:wrap}
#clock{font-size:84px;font-weight:700;font-variant-numeric:tabular-nums;letter-spacing:-.02em}
#date{color:var(--dim);font-size:30px}
#state{margin-left:auto;display:flex;align-items:center;gap:12px;font-size:32px;font-weight:600}
#dot{width:22px;height:22px;border-radius:50%;background:var(--dim)}
.listening #dot{background:var(--acc);box-shadow:0 0 0 0 var(--acc);animation:p 1.6s infinite}
.thinking #dot{background:var(--warn)}.speaking #dot{background:#7aa2f7}.muted #dot{background:var(--bad)}
@keyframes p{0%{box-shadow:0 0 0 0 rgba(86,212,193,.6)}70%{box-shadow:0 0 0 18px rgba(86,212,193,0)}100%{box-shadow:0 0 0 0 rgba(86,212,193,0)}}
main{display:grid;grid-template-columns:1.4fr 1fr;grid-template-rows:minmax(0,1fr) minmax(0,1fr);gap:24px;min-height:0}
#heardCard{grid-column:1;grid-row:1/3}.showing #heardCard{grid-row:1}#taskCard{grid-column:2;grid-row:1/3}
#handCard{display:none;grid-column:2;grid-row:1;flex-direction:column;padding:16px 20px;overflow:hidden}
.cam #handCard{display:flex}.stuck #handImg{opacity:.35}.stuck #handText{color:var(--warn)}.cam #taskCard{grid-row:2}
#handImg{flex:1;min-height:0;width:100%;object-fit:contain;border-radius:8px;background:#000}
#handText{margin-top:10px;font-size:26px;font-weight:600;text-align:center;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
/* 세로 책상 화면(두 번째 모니터 640×1024, 사파리 창 — desk/deskwin.py): 한 줄로 쌓고 글자는 이 화면에 맞춤 */
@media (orientation:portrait) and (max-width:900px){
body{font-size:19px;padding:14px 16px;gap:12px;grid-template-rows:auto minmax(0,1fr)}footer{display:none}
header{gap:6px 16px}#clock{font-size:56px}#date{font-size:21px}#state{font-size:23px;gap:8px}#dot{width:16px;height:16px}
#models button,#voiceBtn{font-size:16px;padding:4px 10px}#models button small{font-size:12px}
main{grid-template-columns:1fr 1fr;grid-template-rows:auto minmax(0,1fr);grid-template-areas:"heard heard" "tasks tasks";gap:12px}
/* 손 카메라가 켜지면 「들은 말」 과 한 줄에 나란히(왼쪽 말 · 오른쪽 카메라) — 주인 10월 5일 17:52 */
.cam main{grid-template-columns:1.15fr 1fr;grid-template-rows:27vh minmax(0,1fr);grid-template-areas:"heard cam" "tasks tasks"}
.showing main{grid-template-rows:auto minmax(0,1fr) minmax(0,34vh);grid-template-areas:"heard heard" "show show" "tasks tasks"}
.showing.cam main{grid-template-rows:22vh minmax(0,1fr) minmax(0,30vh);grid-template-areas:"heard cam" "show show" "tasks tasks"}
#heardCard,.showing #heardCard{grid-area:heard;max-height:20vh}#handCard{grid-area:cam}#showCard{grid-area:show}
#taskCard,.cam #taskCard{grid-area:tasks}
section{padding:12px 14px}h2{font-size:14px;margin-bottom:6px}
#heard{font-size:30px}#reply{font-size:21px;margin-top:8px}.showing #heard{font-size:22px}.showing #reply{font-size:17px}
#panel{font-size:19px}
#handCard{padding:10px 12px}#handText{font-size:17px;line-height:1.3;margin-top:6px;white-space:normal}
.cam #heardCard{max-height:none}.cam #heard{font-size:28px;line-height:1.35}.cam #reply{font-size:20px}
}
section{background:var(--panel);border:1px solid var(--line);border-radius:10px;padding:20px 24px;overflow:auto;min-height:0}
h2{margin:0 0 12px;font-size:18px;letter-spacing:.08em;color:var(--dim);font-weight:600}
#heard{font-size:40px;font-weight:600;min-height:1.5em}#reply{font-size:29px;margin-top:14px;white-space:pre-wrap;color:#c9d1d9}
#showCard{display:none;grid-column:1;grid-row:2}#showCard h2 span{float:right;font-weight:400;letter-spacing:0}
#panel{white-space:pre-wrap;font-size:25px;color:#c9d1d9}
.showing main{grid-template-rows:auto minmax(0,1fr)}.showing #showCard{display:block}
.showing #heardCard{max-height:30vh}.showing #heard{font-size:29px}.showing #reply{font-size:24px;margin-top:6px}
.row{display:flex;justify-content:space-between;gap:12px;padding:6px 0;border-bottom:1px dashed var(--line)}.row:last-child{border:0}
.todo{color:var(--warn)}.bad{color:var(--bad)}
footer{color:var(--dim);font-size:20px}
/* 「작업 현황」 — 세로 화면에서 멀리서도 읽히게 큰 글씨. 주인 손이 필요한 것은 노란 테두리로 맨 위 */
#taskCard h2 b{float:right;font-weight:600;letter-spacing:0;color:var(--ink)}
#tasks h3{margin:14px 0 6px;font-size:17px;letter-spacing:.06em;color:var(--dim);font-weight:600}#tasks h3:first-child{margin-top:0}
.tk{padding:8px 0;border-bottom:1px dashed var(--line)}.tk:last-child{border:0}
.tk-top{display:flex;align-items:baseline;gap:12px}.tk-name{font-size:26px;font-weight:700;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.tk-ago{margin-left:auto;white-space:nowrap;font-size:19px;color:var(--dim);font-variant-numeric:tabular-nums}
.tk-detail{font-size:21px;line-height:1.35;margin-top:2px}.tk-why{font-size:22px;font-weight:600;color:var(--warn);margin-top:2px}
.tk-last{font-size:18px;line-height:1.4;color:var(--dim);margin-top:3px;display:-webkit-box;-webkit-box-orient:vertical;-webkit-line-clamp:2;overflow:hidden}
.tk.need{border:2px solid var(--warn);background:rgba(227,179,65,.12);border-radius:10px;padding:10px 14px;margin-bottom:10px}
.tk.need .tk-name{color:var(--warn)}.tk.need .tk-last{color:#c9d1d9;-webkit-line-clamp:3}
.tk.working .tk-name{color:var(--acc)}.tk.working .tk-last{-webkit-line-clamp:1}
.tk.stopped .tk-name{color:var(--bad)}.tk.stopped .tk-why{color:var(--bad)}
.tk.done{padding:5px 0}.tk.done .tk-name{font-size:19px;font-weight:600;color:var(--dim);flex:none;max-width:45%}
.tk.done .tk-detail{font-size:17px;color:var(--dim);margin:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;min-width:0}
.badge{font-size:16px;font-weight:700;background:var(--warn);color:#2b1d00;border-radius:6px;padding:1px 8px;white-space:nowrap}
#models{display:flex;border:1px solid var(--line);border-radius:8px;overflow:hidden}
#models button{background:none;border:0;border-left:1px solid var(--line);color:var(--dim);padding:6px 14px;font:inherit;font-size:20px;cursor:pointer}
#models button:first-child{border-left:0}#models button:hover{color:var(--ink)}
#models button.on{background:var(--acc);color:#04201c;font-weight:600}#models button small{font-size:15px;opacity:.75;margin-left:6px}
#voiceBtn{background:none;border:1px solid var(--line);color:var(--dim);border-radius:8px;padding:6px 14px;font:inherit;font-size:20px;cursor:pointer}
#voiceBtn:hover{color:var(--ink);border-color:var(--dim)}
#voiceDlg{position:fixed;inset:0;background:rgba(1,4,9,.72);display:flex;align-items:center;justify-content:center;z-index:10}
#voiceDlg[hidden]{display:none}
#voiceBox{background:var(--panel);border:1px solid var(--line);border-radius:12px;padding:28px 32px;width:min(680px,92vw)}
#voiceBox h2{font-size:19px}#voiceBox label{display:block;margin:18px 0 6px;color:var(--dim);font-size:19px}
#voiceBox label b{float:right;color:var(--ink);font-weight:600;font-variant-numeric:tabular-nums}
#voiceBox select,#voiceBox input[type=range]{width:100%;accent-color:var(--acc)}
#voiceBox select{background:var(--bg);color:var(--ink);border:1px solid var(--line);border-radius:8px;padding:8px;font:inherit}
#voiceBox .off{opacity:.4}#voiceBox small{color:var(--dim);font-size:16px}
#voiceBox .btns{display:flex;gap:10px;margin-top:24px}#voiceBox button{font:inherit;font-size:20px;border-radius:8px;padding:8px 18px;cursor:pointer;border:1px solid var(--line);background:var(--bg);color:var(--ink)}
#voiceBox button.pri{background:var(--acc);color:#04201c;border-color:var(--acc);font-weight:600}#voiceBox .btns span{margin-left:auto}
#vMsg{margin-top:14px;min-height:1.4em;font-size:19px;color:var(--dim)}
</style></head><body class="sleep">
<header><div id="clock">--:--</div><div id="date"></div><div id="state"><span id="dot"></span><span id="stateText">대기</span></div><div id="models" title="비서 모델 — 말로도: &quot;빠른 모드&quot; · &quot;정확한 모드&quot;"></div><button id="voiceBtn">목소리</button></header>
<main>
 <section id="heardCard"><h2>들은 말</h2><div id="heard">—</div><div id="reply"></div></section>
 <section id="showCard"><h2>화면에 띄운 글<span>클릭 · Esc 로 닫기</span></h2><div id="panel"></div></section>
 <section id="handCard"><h2>손 카메라</h2><img id="handImg" alt=""><div id="handText"></div></section>
 <section id="taskCard"><h2>작업 현황<b id="taskSum"></b></h2><div id="mic"></div><div id="tasks"></div></section>
</main>
<div id="voiceDlg" hidden><div id="voiceBox"><h2>목소리 설정</h2>
 <label>목소리</label><select id="vSel"></select>
 <label id="vSpeedL">말 빠르기 <b id="vSpeedV"></b></label><input type="range" id="vSpeed">
 <label id="vPitchL">음높이 <b id="vPitchV"></b></label><input type="range" id="vPitch" min="-6" max="6" step="1">
 <label>목소리 크기 <b id="vVolV"></b></label><input type="range" id="vVol" min="0" max="150" step="5">
 <small id="vNote">비서 목소리에만 — 시스템 음량과 따로예요.</small>
 <div class="btns"><button id="vTest">들어 보기</button><button id="vSave" class="pri">저장</button><span></span><button id="vClose">닫기</button></div>
 <div id="vMsg"></div></div></div>
<footer>명령 예: "브리핑" · "조용히" · "다시 들어" · "화면 꺼" · "멈춰" · "빠른 모드" · 그 밖의 말은 Claude 에게</footer>
<script>
const S={sleep:"자는 중",listening:"듣는 중",thinking:"생각 중",speaking:"말하는 중",muted:"조용히 모드"};
const W="일월화수목금토";
function tick(){const d=new Date();clock.textContent=d.toTimeString().slice(0,5);date.textContent=`${d.getMonth()+1}월 ${d.getDate()}일 ${W[d.getDay()]}요일`}
setInterval(tick,1000);tick();
function esc(s){return String(s??"").replace(/[&<>]/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;"}[c]))}
function ago(ms){const m=Math.max(0,Math.floor((Date.now()-ms)/60000));return m<60?`${m}분`:m<1440?`${Math.floor(m/60)}시간 ${m%60}분`:`${Math.floor(m/1440)}일`}
let agentsNow=null;
// 「작업 현황」 — 주인 손 필요(needs) · 작업 중 · 멈춤 · 끝남(최근 4개만) 순서
const DONE_MAX=4;
function tkRow(x){const t=x.state==="working"?x.started:x.updated;
 const top=`<div class="tk-top"><span class="tk-name">${esc(x.name)}</span>${x.state==="needs"?'<span class="badge">확인 필요</span>':""}<span class="tk-ago">${t?ago(t)+(x.state==="working"?"째":" 전"):""}</span></div>`;
 if(x.state==="done")return `<div class="tk done"><div class="tk-top"><span class="tk-name">${esc(x.name)}</span><span class="tk-detail">${esc(x.detail)}</span><span class="tk-ago">${t?ago(t)+" 전":""}</span></div></div>`;
 const why=x.state==="working"?"":(x.why||(x.state==="stopped"?"멈춤":""));
 const last=x.last&&x.last!==x.detail?`<div class="tk-last">${esc(x.last)}</div>`:"";
 return `<div class="tk ${x.state}">${top}${why?`<div class="tk-why">${esc(why)}</div>`:""}${x.detail?`<div class="tk-detail">${esc(x.detail)}</div>`:""}${last}</div>`}
function renderAgents(){const a=agentsNow;
 if(a===null){tasks.innerHTML='<span style="color:var(--dim)">읽는 중…</span>';return}
 const g=k=>a.filter(x=>x.state===k),need=g("needs"),work=g("working"),stop=g("stopped"),done=g("done");
 taskSum.textContent=[need.length&&`확인 ${need.length}`,`작업 중 ${work.length}`,stop.length&&`멈춤 ${stop.length}`].filter(Boolean).join(" · ");
 let h="";
 if(need.length)h+=`<h3>주인 확인이 필요해요</h3>`+need.map(tkRow).join("");
 if(work.length)h+=`<h3>작업 중</h3>`+work.map(tkRow).join("");
 if(stop.length)h+=`<h3>멈춤</h3>`+stop.map(tkRow).join("");
 if(done.length)h+=`<h3>끝남${done.length>DONE_MAX?` (최근 ${DONE_MAX}개 / ${done.length})`:""}</h3>`+done.slice(0,DONE_MAX).map(tkRow).join("");
 tasks.innerHTML=h||'<span style="color:var(--dim)">백그라운드 작업 없음</span>'}
setInterval(renderAgents,30000);
// deskctl show 로 온 긴 글은 「들은 말」 아래에 크게 — 클릭 · Esc 로 닫거나 15분 지나면 원래대로
const SHOW_MS=15*60000;let shown="",closedAt=-1,last={};
function showing(){return !!last.panel&&last.panel_at!==closedAt&&Date.now()-(last.panel_at||0)<SHOW_MS}
function closeShow(){closedAt=last.panel_at;render(last)}
let camShown=false;
function render(st){last=st;
 document.body.className=(st.mode||"sleep")+(showing()?" showing":"")+(camShown?" cam":"");stateText.textContent=S[st.mode]||st.mode;
 heard.textContent=st.heard||"—";reply.textContent=st.reply||"";
 if(st.panel!==shown){shown=st.panel||"";panel.textContent=shown;showCard.scrollTop=0}
 mic.innerHTML=st.mic==="blocked"?`<div class="tk need"><div class="tk-name">마이크 막힘</div><div class="tk-detail">설정 → 개인정보 보호 및 보안 → 마이크 → deskd 켜기</div></div>`:"";
 if(st.agents!==undefined&&JSON.stringify(st.agents)!==JSON.stringify(agentsNow)){agentsNow=st.agents;renderAgents()}
 drawModels(st);
}
// 위쪽 모델 토글 — 누르면 config.toml [brain] model 에 쓰고 다음 말부터 그 모델 (말로는 "빠른 모드" 등)
let modelsKey="";
function drawModels(st){const ms=st.models||[];const k=JSON.stringify(ms);
 if(k!==modelsKey){modelsKey=k;models.innerHTML=ms.map(m=>`<button data-id="${esc(m.id)}">${esc(m.label)}<small>${esc(m.note)}</small></button>`).join("")}
 models.querySelectorAll("button").forEach(b=>b.className=b.dataset.id===st.model?"on":"")}
models.onclick=e=>{const b=e.target.closest("button");if(!b||b.className==="on")return;
 fetch("/api/model",{method:"POST",body:b.dataset.id}).then(async r=>{if(!r.ok)alert("모델을 못 바꿈: "+await r.text())})};
const BUILD="@BUILD@";   // deskd 가 다른 화면으로 바뀌어 다시 뜨면 스스로 새로고침
function connect(){const es=new EventSource("/events");es.onmessage=e=>{const st=JSON.parse(e.data);if(st.build&&st.build!==BUILD)return location.reload();render(st)};es.onerror=()=>{es.close();setTimeout(connect,2000)}}
// 「목소리」 설정 창 — 들어 보기는 저장 없이 한 번, 저장하면 config.toml [tts] 에 쓰고 deskd 가 바로 적용
const SUP={F:"여성",M:"남성"};let vs=null,vr=null;
function api(n,b){return fetch("/api/"+n,{method:"POST",body:b===undefined?"":JSON.stringify(b)}).then(async r=>{const t=await r.text();if(!r.ok)throw new Error(t);return t})}
function vDraw(){const say=vs.engine==="say";
 vSel.value=say?"say:"+vs.voice:"supertonic:"+vs.style;
 const[lo,hi]=say?vr.rate:vr.speed;vSpeed.min=lo;vSpeed.max=hi;vSpeed.step=say?10:0.05;vSpeed.value=say?vs.rate:vs.speed;
 vSpeedV.textContent=say?`분당 ${vs.rate}단어`:`${Number(vs.speed).toFixed(2)}배`;
 vPitch.value=vs.pitch||0;vPitch.disabled=say;vPitchL.className=vPitch.className=say?"off":"";
 vPitchV.textContent=say?"say 는 못 바꿈":(vs.pitch>0?"+":"")+(vs.pitch||0)+" 반음";
 vVol.max=say?100:150;vVol.value=Math.round((say?Math.min(1,vs.volume):vs.volume)*100);vVolV.textContent=vVol.value+"%";
 vNote.textContent="비서 목소리에만 — 시스템 음량과 따로예요."+(say?" 예비 say 음성은 100% 까지.":"")}
function vOpen(){vMsg.textContent="읽는 중…";voiceDlg.hidden=false;
 api("tts").then(t=>{const v=JSON.parse(t);vr=v.ranges;vs={engine:"supertonic",style:"F1",voice:"Yuna",speed:1.05,pitch:0,volume:1,rate:190,...v.now};
  vSel.innerHTML=`<optgroup label="Supertonic (신경망)">${v.styles.map(s=>`<option value="supertonic:${s}">${s} · ${SUP[s[0]]} ${s[1]}</option>`).join("")}</optgroup>`+
   `<optgroup label="예비 — 맥 say">${v.voices.map(n=>`<option value="say:${esc(n)}">${esc(n)}</option>`).join("")}</optgroup>`;
  vDraw();vMsg.textContent="지금: "+v.engine_now}).catch(e=>vMsg.textContent="못 읽음: "+e.message)}
function vHide(){voiceDlg.hidden=true}
vSel.onchange=()=>{const[e,...n]=vSel.value.split(":");vs.engine=e;if(e==="say")vs.voice=n.join(":");else vs.style=n[0];vDraw()};
vSpeed.oninput=()=>{vs[vs.engine==="say"?"rate":"speed"]=Number(vSpeed.value);vDraw()};
vPitch.oninput=()=>{vs.pitch=Number(vPitch.value);vDraw()};
vVol.oninput=()=>{vs.volume=Number(vVol.value)/100;vDraw()};
vTest.onclick=()=>{vMsg.textContent="들려 드릴게요…";api("tts_test",vs).then(t=>vMsg.textContent=t==="ok"?"":t).catch(e=>vMsg.textContent=e.message)};
vSave.onclick=()=>{vMsg.textContent="저장 중…";api("tts_save",vs).then(t=>vMsg.textContent=t).catch(e=>vMsg.textContent="저장 못 함: "+e.message)};
voiceBtn.onclick=vOpen;vClose.onclick=vHide;voiceDlg.onclick=e=>{if(e.target===voiceDlg)vHide()};
showCard.onclick=closeShow;addEventListener("keydown",e=>{if(e.key==="Escape"){if(!voiceDlg.hidden)return vHide();closeShow()}});
setInterval(()=>{if(last.panel)render(last)},30000);
// 손 카메라 — hand-mouse 가 켜져 있는 동안 칸이 보임. 그림은 한 장씩 계속 받아 감(3초 넘게 안 오면 끊고 다시),
// 상태 줄은 짧게 물어봄. 새 그림이 3초 넘게 없으면(hand-mouse 쪽이든 받는 쪽이든) 「멈춤」
let camOk=0,camUrl="";const nap=ms=>new Promise(r=>setTimeout(r,ms));
async function camLoop(){for(;;){
 if(!camShown){await nap(500);continue}
 const ctl=new AbortController(),to=setTimeout(()=>ctl.abort(),3000);
 try{const r=await fetch("/handcam.jpg?"+Date.now(),{cache:"no-store",signal:ctl.signal});
  if(r.ok){const u=URL.createObjectURL(await r.blob());handImg.src=u;if(camUrl)URL.revokeObjectURL(camUrl);camUrl=u;camOk=Date.now()}
  else await nap(1000)}
 catch(e){await nap(1000)}finally{clearTimeout(to)}
 await nap(60)}}
function camPoll(){fetch("/handcam.json?"+Date.now(),{cache:"no-store"}).then(r=>r.json()).then(c=>{
  if(c.shown!==camShown){camShown=c.shown;camOk=Date.now();render(last)}
  const ago=Math.max(c.live?0:c.age,(Date.now()-camOk)/1000),stuck=camShown&&ago>=3;
  handCard.classList.toggle("stuck",stuck);
  handText.textContent=stuck?`멈춤 — ${Math.round(ago)}초째 새 그림 없음`:(c.text||"")}).catch(()=>{}).finally(()=>setTimeout(camPoll,300))}
connect();renderAgents();camPoll();camLoop();
</script></body></html>"""
BUILD = hashlib.sha1(PAGE.encode()).hexdigest()[:12]
PAGE = PAGE.replace("@BUILD@", BUILD)


def handcam_touch(folder: str = "") -> None:
    """hand-mouse 에게 「책상이 보고 있음」 — 이게 몇 초 안 건드려지면 hand-mouse 는 그림을 안 씁니다."""
    folder = folder or HANDCAM
    os.makedirs(folder, exist_ok=True)
    p = os.path.join(folder, "want")
    with open(p, "a"):
        pass
    os.utime(p)


def handcam_state(folder: str = "", now: float | None = None) -> dict:
    """{"shown": 칸을 보일까(HANDCAM_GONE_S 안), "live": 새 그림이 HANDCAM_STALE_S 안에 왔나, "age": 초, "text": 상태 줄}."""
    folder = folder or HANDCAM
    try:
        with open(os.path.join(folder, "view.json"), encoding="utf-8") as f:
            v = json.load(f)
    except (OSError, ValueError):
        return {"shown": False, "live": False, "age": None, "text": ""}
    age = max(0.0, (now or time.time()) - float(v.get("t") or 0))
    return {"shown": age < HANDCAM_GONE_S, "live": age < HANDCAM_STALE_S, "age": round(age, 1),
            "text": str(v.get("text") or "")}


class Board:
    """상태판에 보일 것 — 데몬이 고치면 열린 화면으로 바로 갑니다."""

    def __init__(self):
        self._st = {"mode": "sleep", "mic": "", "heard": "", "reply": "", "panel": "", "briefing": {}, "log": []}
        self._cv = threading.Condition()
        self._ver = 0

    def set(self, **kw) -> None:
        with self._cv:
            if all(self._st.get(k) == v for k, v in kw.items()):
                return                                   # 바뀐 게 없으면 화면에 안 보냄
            self._st.update(kw)
            self._ver += 1
            self._cv.notify_all()

    def log(self, kind: str, text: str) -> None:
        with self._cv:
            self._st["log"] = (self._st["log"] + [{"t": time.strftime("%H:%M:%S"), "kind": kind, "text": text[:200]}])[-40:]
            self._ver += 1
            self._cv.notify_all()

    def get(self) -> dict:
        with self._cv:
            return dict(self._st)

    def wait(self, ver: int, timeout: float = 15) -> int:
        with self._cv:
            self._cv.wait_for(lambda: self._ver != ver, timeout=timeout)
            return self._ver


JOBS = os.path.expanduser("~/.claude/jobs")   # 백그라운드 작업마다 <id>/state.json · timeline.jsonl
STATE = {"blocked": "needs", "waiting": "needs", "needs_input": "needs",
         "working": "working", "running": "working", "busy": "working",
         "done": "done", "idle": "done", "completed": "done",
         "stopped": "stopped", "failed": "stopped", "error": "stopped", "killed": "stopped"}
ORDER = {"needs": 0, "working": 1, "stopped": 2, "done": 3}
# 끝난 작업이라도 끝 보고가 주인을 기다리면(「announcement pending owner」 · 「주인 확인」) 하루 동안은 맨 위로
OWNER_RE = re.compile(r"\b(owner|user)\b|go-ahead|approv|주인|승인|확인 요청", re.I)
OWNER_FRESH_MS = 24 * 3600 * 1000


def _ms(iso) -> int:
    """'2026-10-05T08:40:37.913Z' → ms (못 읽으면 0)."""
    if not isinstance(iso, str) or not iso:
        return 0
    try:
        return int(datetime.fromisoformat(iso.replace("Z", "+00:00")).timestamp() * 1000)
    except ValueError:
        return 0


def _gist(text: str, limit: int = 160) -> str:
    """마지막 메시지에서 마지막 문단 한 줄 — 마크다운 기호를 걷고 짧게."""
    paras = [p for p in re.split(r"\n\s*\n", text or "") if p.strip()]
    if not paras:
        return ""
    s = re.sub(r"[*`#>]|^\s*[-•]\s*|\[([^\]]*)\]\([^)]*\)", lambda m: m.group(1) or "", paras[-1], flags=re.M)
    s = " ".join(s.split())
    return s if len(s) <= limit else s[:limit - 1].rstrip() + "…"


def _tail_text(path: str, max_bytes: int = 65536) -> str:
    """timeline.jsonl 끝에서부터 글(text)이 있는 마지막 줄의 글 — 지금 상태가 이어진 구간 안에서만
    (새로 작업 중인데 지난번 끝 보고가 「마지막 말」로 보이지 않게)."""
    try:
        with open(path, "rb") as f:
            f.seek(0, 2)
            f.seek(max(0, f.tell() - max_bytes))
            lines = f.read().decode("utf-8", "replace").splitlines()
    except OSError:
        return ""
    now = None
    for ln in reversed(lines):
        try:
            e = json.loads(ln)
            state, t = e.get("state"), e.get("text")
        except (ValueError, AttributeError):
            continue
        if now is None:
            now = state
        elif state != now:
            return ""
        if isinstance(t, str) and t.strip():
            return t
    return ""


def _job(jid: str, jobs: str) -> dict:
    if not jid:
        return {}
    try:
        with open(os.path.join(jobs, jid, "state.json"), encoding="utf-8") as f:
            st = json.load(f)
    except (OSError, ValueError):
        return {}
    if not isinstance(st, dict):
        return {}
    st["_last"] = _tail_text(os.path.join(jobs, jid, "timeline.jsonl"))
    return st


def read_agents(run=subprocess.run, jobs: str = JOBS) -> list[dict] | None:
    """「작업 현황」 — `claude agents --json` 의 background 작업마다 ~/.claude/jobs/<id>/state.json 을 붙여 읽음.
    state: needs(주인 손 필요: 권한 · 질문 · blocked) · working · stopped(멈춤) · done.
    detail 은 지금 하는 일(state.json detail), why 는 멈춘 · 기다리는 까닭(waitingFor · needs), last 는 마지막 메시지 한 줄.
    못 읽으면 None(화면은 직전 목록을 그대로 둠)."""
    exe = shutil.which("claude") or os.path.expanduser("~/.local/bin/claude")
    try:
        out = run([exe, "agents", "--json"], capture_output=True, text=True, timeout=10).stdout
        items = json.loads(out)
    except (OSError, subprocess.SubprocessError, ValueError):
        return None
    if not isinstance(items, list):
        return None
    rows = []
    for a in items:
        if not isinstance(a, dict) or a.get("kind") != "background":
            continue
        job = _job(a.get("id") or "", jobs)
        waiting = a.get("waitingFor") or job.get("waitingFor") or ""
        needs = job.get("needs") or a.get("needs") or ""
        raw = job.get("state") or a.get("state") or a.get("status") or ""
        state = STATE.get(raw, "stopped" if raw else "done")
        if waiting or needs or a.get("status") == "waiting" or job.get("tempo") == "blocked":
            state = "needs"
        why = " · ".join(str(x) for x in (needs, waiting) if x)
        updated = _ms(job.get("updatedAt")) or a.get("startedAt") or 0
        if (state == "done" and OWNER_RE.search(job.get("detail") or "")
                and time.time() * 1000 - updated < OWNER_FRESH_MS):
            state, why = "needs", "끝났지만 주인 확인이 필요해요"
        rows.append({"name": a.get("name") or job.get("name") or a.get("id") or str(a.get("pid", "")),
                     "state": state, "started": a.get("startedAt") or 0,
                     "updated": updated,
                     "detail": _gist(job.get("detail") or "", 120), "why": why,
                     "last": _gist(job.get("_last") or "")})
    rows.sort(key=lambda r: (ORDER[r["state"]], -r["updated"]))
    return rows


def watch_agents(board: Board, every_s: float = 5) -> threading.Thread:
    """몇 초마다 백그라운드 작업 목록을 읽어 상태판에 — 바뀐 게 없으면 Board.set 이 화면에 안 보냅니다."""
    def loop():
        while True:
            rows = read_agents()
            if rows is not None:
                board.set(agents=rows)
            time.sleep(every_s)
    t = threading.Thread(target=loop, daemon=True, name="agents")
    t.start()
    return t


def serve(board: Board, commands: dict, host: str = "127.0.0.1", port: int = 7070) -> ThreadingHTTPServer:
    class H(BaseHTTPRequestHandler):
        def log_message(self, *a):
            pass

        def _send(self, code: int, body: bytes, ctype: str = "text/plain; charset=utf-8") -> None:
            self.send_response(code)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")   # 사파리가 옛 화면을 붙들고 있지 않게
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            u = urlparse(self.path)
            if u.path == "/":
                return self._send(200, PAGE.encode(), "text/html; charset=utf-8")
            if u.path == "/state":
                return self._send(200, json.dumps(board.get(), ensure_ascii=False).encode(), "application/json")
            if u.path == "/handcam.json":
                handcam_touch()
                return self._send(200, json.dumps(handcam_state(), ensure_ascii=False).encode(), "application/json")
            if u.path == "/handcam.jpg":
                handcam_touch()
                try:
                    with open(os.path.join(HANDCAM, "view.jpg"), "rb") as f:
                        return self._send(200, f.read(), "image/jpeg")
                except OSError:
                    return self._send(404, b"no frame")
            if u.path == "/events":
                self.send_response(200)
                self.send_header("Content-Type", "text/event-stream")
                self.send_header("Cache-Control", "no-cache")
                self.end_headers()
                ver = -1
                try:
                    while True:
                        ver = board.wait(ver)
                        self.wfile.write(b"data: " + json.dumps({**board.get(), "build": BUILD}, ensure_ascii=False).encode() + b"\n\n")
                        self.wfile.flush()
                except (BrokenPipeError, ConnectionResetError):
                    return
            self._send(404, b"not found")

        def do_POST(self):
            u = urlparse(self.path)
            if not u.path.startswith("/api/"):
                return self._send(404, b"not found")
            name = u.path[5:]
            n = int(self.headers.get("Content-Length") or 0)
            body = self.rfile.read(n).decode("utf-8", "replace") if n else ""
            arg = body or (parse_qs(u.query).get("text") or [""])[0]
            fn = commands.get(name)
            if not fn:
                return self._send(404, f"모르는 명령: {name}".encode())
            try:
                r = fn(arg)
                return self._send(200, (r or "ok").encode())
            except Exception as e:  # noqa: BLE001
                return self._send(500, str(e).encode())

    srv = ThreadingHTTPServer((host, port), H)
    srv.daemon_threads = True
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    return srv
