"""화면 — 첫 번째 모니터에 띄우는 상태판. 이 맥 안에서만 열립니다(127.0.0.1).

/          상태판 (전체 화면 크롬 앱 창)
/events    상태가 바뀔 때마다 보내는 스트림(SSE)
/api/<명령> deskctl 이 부르는 곳: wake · sleep · brief · mute · unmute · stop · say · show
"""
from __future__ import annotations

import json
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
main{display:grid;grid-template-columns:1.2fr 1fr;gap:24px;min-height:0}
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
</style></head><body class="sleep">
<header><div id="clock">--:--</div><div id="date"></div><div id="state"><span id="dot"></span><span id="stateText">대기</span></div></header>
<main>
 <section><h2>들은 말</h2><div id="heard">—</div><div id="reply"></div><div id="panel"></div></section>
 <section><h2>지금 상태</h2><div id="brief"></div><h2 style="margin-top:20px">기록</h2><div id="log"></div></section>
</main>
<footer>명령 예: "브리핑" · "조용히" · "다시 들어" · "화면 꺼" · "멈춰" · 그 밖의 말은 Claude 에게</footer>
<script>
const S={sleep:"자는 중",listening:"듣는 중",thinking:"생각 중",speaking:"말하는 중",muted:"조용히 모드"};
const W="일월화수목금토";
function tick(){const d=new Date();clock.textContent=d.toTimeString().slice(0,5);date.textContent=`${d.getMonth()+1}월 ${d.getDate()}일 ${W[d.getDay()]}요일`}
setInterval(tick,1000);tick();
function esc(s){return String(s??"").replace(/[&<>]/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;"}[c]))}
function render(st){
 document.body.className=st.mode||"sleep";stateText.textContent=S[st.mode]||st.mode;
 heard.textContent=st.heard||"—";reply.textContent=st.reply||"";panel.textContent=st.panel||"";
 const b=st.briefing||{},f=b.factory||{},l=b.lab||{};let h="";
 if(b.weather)h+=`<div class="row"><span>날씨</span><span>${esc(b.weather)}</span></div>`;
 (f.apps||[]).forEach(a=>h+=`<div class="row"><span>${esc(a.name)}</span><span>${esc(a.stage)}</span></div>`);
 if(f.waiting_approvals)h+=`<div class="row todo"><span>출시 승인 대기</span><span>${f.waiting_approvals}건</span></div>`;
 (f.owner_todo||[]).forEach(t=>h+=`<div class="row todo"><span>할 일</span><span>${esc(t)}</span></div>`);
 if(f.red_main)h+=`<div class="row bad"><span>실패한 빌드</span><span>${f.red_main}</span></div>`;
 if(l.runner!==undefined)h+=`<div class="row"><span>실험실</span><span>러너 ${l.runner?"켜짐":"꺼짐"} · 아이폰 ${l.iphone?"연결":"없음"} · 안드로이드 ${l.android||0} · 디스크 ${esc(l.disk_free||"")}</span></div>`;
 brief.innerHTML=h||'<span style="color:var(--dim)">박수 두 번이면 브리핑합니다</span>';
 log.innerHTML=(st.log||[]).slice().reverse().map(x=>`<div class="${x.kind==='ignore'?'ig':''}">${esc(x.t)} ${esc(x.kind)} · ${esc(x.text)}</div>`).join("");
}
function connect(){const es=new EventSource("/events");es.onmessage=e=>render(JSON.parse(e.data));es.onerror=()=>{es.close();setTimeout(connect,2000)}}
connect();
</script></body></html>"""


class Board:
    """상태판에 보일 것 — 데몬이 고치면 열린 화면으로 바로 갑니다."""

    def __init__(self):
        self._st = {"mode": "sleep", "heard": "", "reply": "", "panel": "", "briefing": {}, "log": []}
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


def serve(board: Board, commands: dict, host: str = "127.0.0.1", port: int = 7070) -> ThreadingHTTPServer:
    class H(BaseHTTPRequestHandler):
        def log_message(self, *a):
            pass

        def _send(self, code: int, body: bytes, ctype: str = "text/plain; charset=utf-8") -> None:
            self.send_response(code)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(body)))
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
                        self.wfile.write(b"data: " + json.dumps(board.get(), ensure_ascii=False).encode() + b"\n\n")
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
