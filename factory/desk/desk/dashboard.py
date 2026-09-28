"""화면 — 첫 번째 모니터에 띄우는 상태판. 이 맥 안에서만 열립니다(127.0.0.1).

/          상태판 (전체 화면 크롬 앱 창)
/events    상태가 바뀔 때마다 보내는 스트림(SSE) — 화면 판(build)이 바뀌면 열린 페이지가 스스로 새로고침
/api/<명령> deskctl 이 부르는 곳: wake · sleep · brief · mute · unmute · stop · say · show

오른쪽 칸의 「백그라운드 작업」 은 `claude agents --json` 을 몇 초마다 읽어 채웁니다(watch_agents).
"""
from __future__ import annotations

import hashlib
import json
import os
import shutil
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

PAGE = r"""<!doctype html><html lang="ko"><head><meta charset="utf-8"><title>책상</title>
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>
:root{--bg:#0d1117;--panel:#161b22;--line:#262d36;--ink:#e6edf3;--dim:#8b949e;--acc:#56d4c1;--warn:#e3b341;--bad:#f47067}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font:18px/1.55 "Apple SD Gothic Neo","Noto Sans KR",system-ui,sans-serif;padding:32px 40px;height:100vh;display:grid;grid-template-rows:auto 1fr auto;gap:24px}
header{display:flex;align-items:baseline;gap:24px;flex-wrap:wrap}
#clock{font-size:64px;font-weight:700;font-variant-numeric:tabular-nums;letter-spacing:-.02em}
#date{color:var(--dim);font-size:22px}
#state{margin-left:auto;display:flex;align-items:center;gap:12px;font-size:24px;font-weight:600}
#dot{width:18px;height:18px;border-radius:50%;background:var(--dim)}
.listening #dot{background:var(--acc);box-shadow:0 0 0 0 var(--acc);animation:p 1.6s infinite}
.thinking #dot{background:var(--warn)}.speaking #dot{background:#7aa2f7}.muted #dot{background:var(--bad)}
@keyframes p{0%{box-shadow:0 0 0 0 rgba(86,212,193,.6)}70%{box-shadow:0 0 0 18px rgba(86,212,193,0)}100%{box-shadow:0 0 0 0 rgba(86,212,193,0)}}
main{display:grid;grid-template-columns:1.4fr 1fr;grid-template-rows:minmax(0,1fr) minmax(0,1fr);gap:24px;min-height:0}
#agentsCard{grid-column:2;grid-row:1/3}
section{background:var(--panel);border:1px solid var(--line);border-radius:10px;padding:20px 24px;overflow:auto;min-height:0}
h2{margin:0 0 12px;font-size:14px;letter-spacing:.08em;color:var(--dim);font-weight:600}
#heard{font-size:30px;font-weight:600;min-height:1.5em}#reply{font-size:22px;margin-top:14px;white-space:pre-wrap;color:#c9d1d9}
#panel{white-space:pre-wrap;font-size:17px;margin-top:18px;color:#c9d1d9;border-top:1px solid var(--line);padding-top:14px}
#panel:empty{display:none}
.row{display:flex;justify-content:space-between;gap:12px;padding:6px 0;border-bottom:1px dashed var(--line)}.row:last-child{border:0}
.todo{color:var(--warn)}.bad{color:var(--bad)}
#log{font-size:14px;color:var(--dim);font-family:ui-monospace,Menlo,monospace;max-height:22vh;overflow:auto}
#log div.ig{opacity:.5}
footer{color:var(--dim);font-size:15px}
#agents .row{font-size:16px;flex-wrap:wrap;row-gap:0}#agents .nm{white-space:nowrap;overflow:hidden;text-overflow:ellipsis;max-width:100%}
#agents .st{margin-left:auto;white-space:nowrap;font-variant-numeric:tabular-nums}.ag-working{color:var(--acc)}.ag-waiting{color:var(--warn)}.ag-done{color:var(--dim)}
</style></head><body class="sleep">
<header><div id="clock">--:--</div><div id="date"></div><div id="state"><span id="dot"></span><span id="stateText">대기</span></div></header>
<main>
 <section><h2>들은 말</h2><div id="heard">—</div><div id="reply"></div><div id="panel"></div></section>
 <section><h2>지금 상태</h2><div id="brief"></div><h2 style="margin-top:20px">기록</h2><div id="log"></div></section>
 <section id="agentsCard"><h2>백그라운드 작업</h2><div id="agents"></div></section>
</main>
<footer>명령 예: "브리핑" · "조용히" · "다시 들어" · "화면 꺼" · "멈춰" · 그 밖의 말은 Claude 에게</footer>
<script>
const S={sleep:"자는 중",listening:"듣는 중",thinking:"생각 중",speaking:"말하는 중",muted:"조용히 모드"};
const W="일월화수목금토";
function tick(){const d=new Date();clock.textContent=d.toTimeString().slice(0,5);date.textContent=`${d.getMonth()+1}월 ${d.getDate()}일 ${W[d.getDay()]}요일`}
setInterval(tick,1000);tick();
function esc(s){return String(s??"").replace(/[&<>]/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;"}[c]))}
const AG={working:"작업 중",done:"완료",waiting:"대기"};
function ago(ms){const m=Math.max(0,Math.floor((Date.now()-ms)/60000));return m<60?`${m}분`:m<1440?`${Math.floor(m/60)}시간 ${m%60}분`:`${Math.floor(m/1440)}일`}
let agentsNow=null;
function renderAgents(){const a=agentsNow;
 if(a===null){agents.innerHTML='<span style="color:var(--dim)">읽는 중…</span>';return}
 agents.innerHTML=a.length?a.map(x=>`<div class="row ag-${x.state}"><span class="nm">${esc(x.name)}</span><span class="st">${AG[x.state]||esc(x.state)} · ${x.started?ago(x.started):"—"}</span></div>`).join(""):'<span style="color:var(--dim)">없음</span>'}
setInterval(renderAgents,30000);
function render(st){
 document.body.className=st.mode||"sleep";stateText.textContent=S[st.mode]||st.mode;
 heard.textContent=st.heard||"—";reply.textContent=st.reply||"";panel.textContent=st.panel||"";
 const b=st.briefing||{},f=b.factory||{},l=b.lab||{};let h="";
 if(st.mic==="blocked")h+=`<div class="row bad"><span>마이크 막힘</span><span>설정 → 개인정보 보호 및 보안 → 마이크 → deskd 켜기</span></div>`;
 if(b.weather)h+=`<div class="row"><span>날씨</span><span>${esc(b.weather)}</span></div>`;
 (f.apps||[]).forEach(a=>h+=`<div class="row"><span>${esc(a.name)}</span><span>${esc(a.stage)}</span></div>`);
 if(f.waiting_approvals)h+=`<div class="row todo"><span>출시 승인 대기</span><span>${f.waiting_approvals}건</span></div>`;
 (f.owner_todo||[]).forEach(t=>h+=`<div class="row todo"><span>할 일</span><span>${esc(t)}</span></div>`);
 if(f.red_main)h+=`<div class="row bad"><span>실패한 빌드</span><span>${f.red_main}</span></div>`;
 if(l.runner!==undefined)h+=`<div class="row"><span>실험실</span><span>러너 ${l.runner?"켜짐":"꺼짐"} · 아이폰 ${l.iphone?"연결":"없음"} · 안드로이드 ${l.android||0} · 디스크 ${esc(l.disk_free||"")}</span></div>`;
 brief.innerHTML=h||'<span style="color:var(--dim)">박수 두 번이면 브리핑합니다</span>';
 if(st.agents!==undefined&&JSON.stringify(st.agents)!==JSON.stringify(agentsNow)){agentsNow=st.agents;renderAgents()}
 log.innerHTML=(st.log||[]).slice().reverse().map(x=>`<div class="${x.kind==='ignore'?'ig':''}">${esc(x.t)} ${esc(x.kind)} · ${esc(x.text)}</div>`).join("");
}
const BUILD="@BUILD@";   // deskd 가 다른 화면으로 바뀌어 다시 뜨면 스스로 새로고침
function connect(){const es=new EventSource("/events");es.onmessage=e=>{const st=JSON.parse(e.data);if(st.build&&st.build!==BUILD)return location.reload();render(st)};es.onerror=()=>{es.close();setTimeout(connect,2000)}}
connect();renderAgents();
</script></body></html>"""
BUILD = hashlib.sha1(PAGE.encode()).hexdigest()[:12]
PAGE = PAGE.replace("@BUILD@", BUILD)


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


def read_agents(run=subprocess.run) -> list[dict] | None:
    """`claude agents --json` 에서 kind 가 background 인 것만 — 이름 · 상태(working/done/waiting) · 시작 시각(ms).
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
        st = a.get("state") or a.get("status") or ""
        state = ("done" if st in ("done", "idle") else
                 "working" if st in ("working", "busy") else "waiting")   # blocked · waiting · 그 밖
        rows.append({"name": a.get("name") or a.get("id") or str(a.get("pid", "")), "state": state,
                     "started": a.get("startedAt") or 0})
    order = {"working": 0, "waiting": 1, "done": 2}
    rows.sort(key=lambda r: (order[r["state"]], -r["started"]))
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
