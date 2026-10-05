"""폰 비서 — 주인 안드로이드 폰(비서 앱)이 집 밖에서도 이 맥을 방에서처럼 쓰게 (주인 10월 5일 17:03).

    폰 ──Tailscale(100.x)──▶ 이 서버(:7071)
        누르고 말하기 → 받아쓰기(deskd 와 같은 whisper) → 왼손 주먹 말과 같은 길(같은 세션 · CLAUDE.md · 권한)
                        → 답은 맥 스피커가 아니라 폰으로(글 · 폰이 소리로 읽음)
        두 화면 보기 → /screen/<i>.jpg (바뀐 게 없으면 304)
        터치 → /input  클릭 · 두 번 · 오른쪽 · 스크롤 · 끌기 · 글자 입력

테일넷 주소(100.64.0.0/10)와 127.0.0.1 에만 열고, 공개 인터넷(funnel)에는 내지 않습니다.
그래도 열쇠(~/.config/desk/phone_token)가 맞아야 받습니다 — 테일넷에 다른 기기가 붙어도 못 씀.
"""
from __future__ import annotations

import hashlib
import ipaddress
import json
import logging
import os
import secrets
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

import numpy as np

log = logging.getLogger("deskd")

TOKEN_FILE = "~/.config/desk/phone_token"
TAILNET = ipaddress.ip_network("100.64.0.0/10")
APK = "~/.local/share/desk/desk-phone.apk"          # phone-app/build.sh 가 만든 것


def token(path: str = TOKEN_FILE) -> str:
    """폰 열쇠 — 없으면 만들고 주인만 읽게"""
    p = Path(os.path.expanduser(path))
    try:
        t = p.read_text().strip()
        if t:
            return t
    except OSError:
        pass
    p.parent.mkdir(parents=True, exist_ok=True)
    t = secrets.token_urlsafe(24)
    p.write_text(t + "\n")
    os.chmod(p, 0o600)
    return t


def tailscale_ip(run=subprocess.run) -> str:
    for exe in ("tailscale", "/opt/homebrew/bin/tailscale", "/Applications/Tailscale.app/Contents/MacOS/Tailscale"):
        try:
            r = run([exe, "ip", "-4"], capture_output=True, text=True, timeout=5)
        except (OSError, subprocess.TimeoutExpired):
            continue
        for line in (r.stdout or "").split():
            try:
                if ipaddress.ip_address(line) in TAILNET:
                    return line
            except ValueError:
                pass
    return ""


def allowed_peer(ip: str) -> bool:
    try:
        a = ipaddress.ip_address(ip.removeprefix("::ffff:"))
    except ValueError:
        return False
    return a.is_loopback or a in TAILNET


# ── 화면 ──────────────────────────────────────────────────────────────────
def displays() -> list[dict]:
    """[{id, x, y, w, h(포인트), main, rotation, asleep}] — 주 화면이 먼저.
    화면이 잠들면(deskd 「화면 꺼」 · 15분 조용) 활성 목록이 비어 폰이 404 를 받던 것 — 연결된(online) 목록으로 (주인 10월 5일 18:36)"""
    import Quartz
    _, ids, n = Quartz.CGGetOnlineDisplayList(8, None, None)
    out = []
    for d in ids[:n]:
        b = Quartz.CGDisplayBounds(d)
        out.append({"id": int(d), "x": b.origin.x, "y": b.origin.y, "w": b.size.width, "h": b.size.height,
                    "main": bool(Quartz.CGDisplayIsMain(d)), "rotation": int(Quartz.CGDisplayRotation(d)),
                    "asleep": bool(Quartz.CGDisplayIsAsleep(d))})
    out.sort(key=lambda d: (not d["main"], d["x"]))
    return out


def cursor() -> tuple[float, float]:
    import Quartz
    p = Quartz.CGEventGetLocation(Quartz.CGEventCreate(None))
    return p.x, p.y


def grab(d: dict) -> np.ndarray | None:
    """한 화면을 BGR 로 (화면 기록 권한이 없으면 배경만 보이거나 None)"""
    import Quartz
    img = Quartz.CGDisplayCreateImage(d["id"])
    if img is None:
        return None
    w, h = Quartz.CGImageGetWidth(img), Quartz.CGImageGetHeight(img)
    bpr = Quartz.CGImageGetBytesPerRow(img)
    data = Quartz.CGDataProviderCopyData(Quartz.CGImageGetDataProvider(img))
    a = np.frombuffer(data, np.uint8).reshape(h, bpr // 4, 4)[:, :w, :3]
    return np.ascontiguousarray(a)


def frame(d: dict, width: int = 1280, quality: int = 60) -> bytes | None:
    """화면 JPEG — 마우스 자리에 동그라미(화면 캡처엔 커서가 안 찍힘)"""
    import cv2
    a = grab(d)
    if a is None:
        return None
    h, w = a.shape[:2]
    width = max(160, min(int(width), w))
    if width < w:
        a = cv2.resize(a, (width, round(h * width / w)), interpolation=cv2.INTER_AREA)
    sx = a.shape[1] / d["w"]
    cx, cy = cursor()
    if d["x"] <= cx < d["x"] + d["w"] and d["y"] <= cy < d["y"] + d["h"]:
        p = (int((cx - d["x"]) * sx), int((cy - d["y"]) * sx))
        r = max(6, int(10 * sx))
        cv2.circle(a, p, r, (0, 0, 0), 4)
        cv2.circle(a, p, r, (80, 220, 255), 2)
    ok, buf = cv2.imencode(".jpg", a, [cv2.IMWRITE_JPEG_QUALITY, int(quality)])
    return buf.tobytes() if ok else None


# ── 마우스 · 키보드 (손쉬운 사용 권한 필요 — 오른손 주먹 받아쓰기와 같은 권한) ──────────
KEYS = {"enter": 36, "delete": 51, "escape": 53, "tab": 48, "left": 123, "right": 124, "down": 125, "up": 126,
        "space": 49}


def point(d: dict, fx: float, fy: float) -> tuple[float, float]:
    fx, fy = min(max(fx, 0.0), 0.999), min(max(fy, 0.0), 0.999)
    return d["x"] + fx * d["w"], d["y"] + fy * d["h"]


def act(d: dict | None, ev: dict) -> str:
    import Quartz

    from .blackout import PHONE_TAG
    Q = Quartz
    a = ev.get("action", "click")

    def post(e):                                  # 폰이 넣은 입력 표시 — 검은 화면이 「방에서 누름」으로 알고 켜지 않게
        Q.CGEventSetIntegerValueField(e, Q.kCGEventSourceUserData, PHONE_TAG)
        Q.CGEventPost(Q.kCGHIDEventTap, e)

    def mouse(kind, p, button=Q.kCGMouseButtonLeft, clicks=1):
        e = Q.CGEventCreateMouseEvent(None, kind, p, button)
        Q.CGEventSetIntegerValueField(e, Q.kCGMouseEventClickState, clicks)
        post(e)

    if a == "type":
        text = str(ev.get("text", ""))
        for i in range(0, len(text), 16):                        # 한 번에 너무 길면 앱이 자름
            chunk = text[i:i + 16]
            for down in (True, False):
                e = Q.CGEventCreateKeyboardEvent(None, 0, down)
                Q.CGEventKeyboardSetUnicodeString(e, len(chunk.encode("utf-16-le")) // 2, chunk)
                post(e)
            time.sleep(0.01)
        return "ok"
    if a == "key":
        code = KEYS.get(str(ev.get("key", "")))
        if code is None:
            return "모르는 키"
        for down in (True, False):
            post(Q.CGEventCreateKeyboardEvent(None, code, down))
        return "ok"
    if d is None:
        return "화면 없음"
    p = point(d, float(ev.get("x", 0.5)), float(ev.get("y", 0.5)))
    if a == "move":
        mouse(Q.kCGEventMouseMoved, p)
    elif a in ("click", "double"):
        mouse(Q.kCGEventMouseMoved, p)
        for n in ((1, 2) if a == "double" else (1,)):
            mouse(Q.kCGEventLeftMouseDown, p, clicks=n)
            mouse(Q.kCGEventLeftMouseUp, p, clicks=n)
    elif a == "right":
        mouse(Q.kCGEventMouseMoved, p)
        mouse(Q.kCGEventRightMouseDown, p, Q.kCGMouseButtonRight)
        mouse(Q.kCGEventRightMouseUp, p, Q.kCGMouseButtonRight)
    elif a == "scroll":                                          # dx · dy: 폰 화면에서 끈 만큼(맥 포인트)
        mouse(Q.kCGEventMouseMoved, p)
        dy, dx = int(float(ev.get("dy", 0))), int(float(ev.get("dx", 0)))
        e = Q.CGEventCreateScrollWheelEvent(None, Q.kCGScrollEventUnitPixel, 2, dy, dx)
        post(e)
    elif a == "drag":                                            # x,y → x2,y2
        q = point(d, float(ev.get("x2", 0.5)), float(ev.get("y2", 0.5)))
        mouse(Q.kCGEventMouseMoved, p)
        mouse(Q.kCGEventLeftMouseDown, p)
        for i in range(1, 11):
            t = i / 10
            mouse(Q.kCGEventLeftMouseDragged, (p[0] + (q[0] - p[0]) * t, p[1] + (q[1] - p[1]) * t))
            time.sleep(0.015)
        mouse(Q.kCGEventLeftMouseUp, q)
    else:
        return "모르는 동작"
    return "ok"


# ── 알림: 주인 확인이 필요한 일 → 폰 알림 ─────────────────────────────────────
# 「작업 현황」 카드의 「주인 확인이 필요해요」(state needs) 와 같은 기준 + deskctl say 로 주인을 부르는 말.
# 같은 일(id)은 한 번만. 폰 앱의 상주 서비스가 /notices 를 롱폴로 받아 안드로이드 알림으로 띄움.
import re  # noqa: E402

ASK_RE = re.compile(r"주세요|하세요|해 줘|확인|허용|승인|비밀번호|눌러|골라|정해|할까요|될까요|\?")
SAY_KEEP_S = 6 * 3600                                   # 같은 말은 6시간 안에 다시 알리지 않음


class Notices:
    def __init__(self, now=time.time):
        self.now = now
        self.items: list[dict] = []                     # {seq, id, title, body, at}
        self.seq = 0
        self.boot = secrets.token_hex(4)                # deskd 가 다시 뜨면 바뀜 — 앱은 since 를 0 으로
        self._sent: dict[str, float] = {}               # id → 마지막으로 알린 때
        self._needs: set[str] = set()                   # 지금 주인 손을 기다리는 작업(id)
        self.cv = threading.Condition()

    def _add(self, nid: str, title: str, body: str) -> None:
        with self.cv:
            self.seq += 1
            self.items.append({"seq": self.seq, "id": nid, "title": title, "body": body, "at": int(self.now())})
            del self.items[:-50]
            self._sent[nid] = self.now()
            self.cv.notify_all()

    def agents(self, rows: list[dict]) -> None:
        """작업 현황 목록 — needs 로 새로 들어온 것만 알림. 빠졌다가 다시 들어오면 다시"""
        cur = {}
        for r in rows or []:
            if r.get("state") == "needs":
                cur[f"agent:{r.get('name')}"] = r       # 막힌 동안 까닭 글이 바뀌어도 한 번만
        for nid, r in cur.items():
            if nid not in self._needs:
                why = r.get("why") or "확인이 필요해요"
                body = " · ".join(x for x in (why, r.get("last") or r.get("detail") or "") if x)
                self._add(nid, f"{r.get('name')} — 주인 확인 필요", body[:300])
        self._needs = set(cur)

    def said(self, text: str) -> None:
        """deskctl say — 주인에게 무언가를 해 달라는 말이면 알림(같은 말은 6시간에 한 번)"""
        t = (text or "").strip()
        if not t or not ASK_RE.search(t):
            return
        nid = "say:" + hashlib.blake2b(t.encode(), digest_size=6).hexdigest()
        if nid in self._sent and self.now() - self._sent[nid] < SAY_KEEP_S:
            return
        self._add(nid, "비서가 불러요", t[:300])

    def since(self, seq: int, wait: float = 0) -> dict:
        end = self.now() + wait
        with self.cv:
            while True:
                new = [i for i in self.items if i["seq"] > seq]
                left = end - self.now()
                if new or left <= 0:
                    return {"boot": self.boot, "seq": self.seq, "items": new}
                self.cv.wait(min(left, 5))


# ── 서버 ──────────────────────────────────────────────────────────────────
class Phone:
    """desk: ask(text) -> dict · hear(pcm16) -> str 를 가진 것(deskd 의 Desk)"""

    def __init__(self, desk, port: int = 7071, token_file: str = TOKEN_FILE):
        self.desk, self.port = desk, port
        self.token = token(token_file)
        self.servers: list[ThreadingHTTPServer] = []
        self._hash: dict[int, str] = {}
        self.notices = Notices()

    def watch(self, board, every_s: float = 5) -> None:
        """상태판의 작업 현황(agents)을 보고 알림을 만듦"""
        def loop():
            while True:
                try:
                    rows = board.get().get("agents")
                    if rows is not None:
                        self.notices.agents(rows)
                except Exception:  # noqa: BLE001
                    log.exception("폰 알림: 작업 현황 읽기 실패")
                time.sleep(every_s)
        threading.Thread(target=loop, daemon=True, name="phone-notices").start()

    def start(self, hosts: list[str] | None = None) -> None:
        """127.0.0.1 은 바로, 테일넷 주소는 잡힐 때까지 30초마다 다시(Tailscale 이 늦게 뜰 때)"""
        if hosts is not None:
            for h in hosts:
                self._bind(h)
            return
        self._bind("127.0.0.1")

        def loop():
            while True:
                ip = tailscale_ip()
                if ip and self._bind(ip):
                    return
                time.sleep(30)
        threading.Thread(target=loop, daemon=True).start()

    def _bind(self, host: str) -> bool:
        try:
            srv = ThreadingHTTPServer((host, self.port), self._handler())
        except OSError as e:
            log.warning("폰 서버 %s:%d 못 엶: %s", host, self.port, e)
            return False
        srv.daemon_threads = True
        threading.Thread(target=srv.serve_forever, daemon=True).start()
        self.servers.append(srv)
        log.info("폰 서버 %s:%d", host, self.port)
        return True

    def _handler(self):
        ph = self

        class H(BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.1"

            def log_message(self, *a):
                pass

            def _send(self, code: int, body: bytes = b"", ctype: str = "text/plain; charset=utf-8", extra=None):
                self.send_response(code)
                self.send_header("Content-Type", ctype)
                self.send_header("Content-Length", str(len(body)))
                self.send_header("Cache-Control", "no-store")
                for k, v in (extra or {}).items():
                    self.send_header(k, v)
                self.end_headers()
                self.wfile.write(body)

            def _json(self, obj, code: int = 200):
                self._send(code, json.dumps(obj, ensure_ascii=False).encode(), "application/json")

            def _ok(self) -> bool:
                if not allowed_peer(self.client_address[0]):
                    self._send(403, b"tailnet only")
                    return False
                q = parse_qs(urlparse(self.path).query)
                t = self.headers.get("X-Desk-Token") or (q.get("t") or [""])[0]
                if not secrets.compare_digest(t, ph.token):
                    self._send(401, b"bad token")
                    return False
                return True

            def _body(self) -> bytes:
                n = int(self.headers.get("Content-Length") or 0)
                return self.rfile.read(n) if n else b""

            def do_GET(self):
                u = urlparse(self.path)
                if u.path == "/app.apk" and allowed_peer(self.client_address[0]):   # 설치 링크 — 테일넷 안에서만
                    try:
                        data = Path(os.path.expanduser(APK)).read_bytes()
                    except OSError:
                        return self._send(404, b"no apk")
                    return self._send(200, data, "application/vnd.android.package-archive",
                                      {"Content-Disposition": 'attachment; filename="desk-phone.apk"'})
                if not self._ok():
                    return
                q = parse_qs(u.query)
                if u.path == "/":
                    return self._send(200, PAGE.encode(), "text/html; charset=utf-8")
                if u.path == "/screens":
                    return self._json(displays())
                if u.path.startswith("/screen/"):
                    ds = displays()
                    try:
                        d = ds[int(u.path.split("/")[2].split(".")[0])]
                    except (ValueError, IndexError):
                        return self._send(404, b"no screen")
                    if d.get("asleep"):
                        return self._send(503, "맥 화면이 꺼져 있어요".encode(), extra={"X-Asleep": "1"})
                    img = frame(d, int((q.get("w") or ["1280"])[0]), int((q.get("q") or ["60"])[0]))
                    if img is None:
                        return self._send(503, b"capture failed")
                    tag = hashlib.blake2b(img, digest_size=8).hexdigest()
                    if (q.get("h") or [""])[0] == tag:
                        return self._send(204, extra={"X-Frame": tag})
                    return self._send(200, img, "image/jpeg", {"X-Frame": tag})
                if u.path == "/notices":                      # 롱폴 — ?since=<seq>&wait=<초>
                    seq = int((q.get("since") or ["0"])[0] or 0)
                    wait = min(float((q.get("wait") or ["0"])[0] or 0), 55)
                    return self._json(ph.notices.since(seq, wait))
                if u.path == "/state":
                    return self._json(ph.desk.phone_state())
                self._send(404, b"not found")

            def do_POST(self):
                if not self._ok():
                    return
                u = urlparse(self.path)
                body = self._body()
                try:
                    if u.path == "/ask":                      # 글로 — {"text": ...} 또는 그냥 글
                        try:
                            text = json.loads(body).get("text", "")
                        except (ValueError, AttributeError):
                            text = body.decode("utf-8", "replace")
                        return self._json(ph.desk.phone_ask(text.strip()))
                    if u.path == "/talk":                     # 누르고 말하기 — 16kHz 모노 16비트 PCM
                        pcm = np.frombuffer(body[: len(body) // 2 * 2], "<i2").astype(np.float32) / 32768
                        text = ph.desk.phone_hear(pcm)
                        if not text:
                            return self._json({"heard": "", "reply": "잘 못 들었어요. 다시 말해 주세요.", "kind": "empty"})
                        return self._json(ph.desk.phone_ask(text))
                    if u.path == "/input":
                        ev = json.loads(body or b"{}")
                        ds = displays()
                        i = int(ev.get("screen", 0))
                        return self._json({"r": act(ds[i] if 0 <= i < len(ds) else None, ev)})
                    if u.path == "/wake":
                        return self._json({"r": ph.desk.phone_wake()})
                    if u.path == "/stop":
                        return self._json({"r": ph.desk.stop()})
                except Exception as e:  # noqa: BLE001
                    log.exception("폰 요청 실패 %s", u.path)
                    return self._json({"error": str(e)}, 500)
                self._send(404, b"not found")

        return H


PAGE = r"""<!doctype html><html lang="ko"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
<title>비서</title>
<style>
*{box-sizing:border-box;-webkit-tap-highlight-color:transparent}
html,body{margin:0;height:100%;background:#0d1117;color:#e6edf3;font-family:system-ui,sans-serif;overflow:hidden}
#top{display:flex;gap:6px;padding:6px;background:#161b22;align-items:center}
#top button{flex:1;padding:10px 4px;border:1px solid #30363d;border-radius:8px;background:#21262d;color:#e6edf3;font-size:15px}
#top button.on{background:#2ea043;border-color:#2ea043}
#view{position:absolute;top:52px;bottom:var(--bot);left:0;right:0;overflow:hidden;touch-action:none;background:#000}
#view.zoom{overflow:auto;touch-action:pan-x pan-y}
#scr{display:block;width:100%;height:100%;object-fit:contain;user-select:none;-webkit-user-drag:none}
#view.zoom #scr{width:200%;height:auto;object-fit:fill}
#bar{position:absolute;left:0;right:0;bottom:0;background:#161b22;padding:8px}
#keys{display:flex;gap:6px;margin-bottom:6px}
#keys input{flex:1;min-width:0;padding:9px;border-radius:8px;border:1px solid #30363d;background:#0d1117;color:#e6edf3;font-size:15px}
#keys button,#tools button{padding:9px 10px;border-radius:8px;border:1px solid #30363d;background:#21262d;color:#e6edf3;font-size:14px}
#tools{display:flex;gap:6px;margin-bottom:6px}
#tools button.on{background:#1f6feb;border-color:#1f6feb}
#talk{width:100%;padding:16px;border-radius:14px;border:0;background:#1f6feb;color:#fff;font-size:19px;font-weight:600;touch-action:none;user-select:none;-webkit-user-select:none;-webkit-touch-callout:none}
#talk.rec{background:#da3633}
#talk.wait{background:#6e7681}
#reply{font-size:15px;line-height:1.45;max-height:30vh;overflow:auto;margin-bottom:6px;white-space:pre-wrap}
#reply .h{color:#8b949e;font-size:13px}
#chat{position:absolute;top:52px;bottom:var(--bot);left:0;right:0;overflow:auto;padding:12px;display:none}
#chat .m{margin:8px 0;padding:10px 12px;border-radius:12px;max-width:90%;white-space:pre-wrap;line-height:1.45}
#chat .me{background:#1f6feb33;margin-left:auto}
#chat .ai{background:#21262d}
#st{font-size:12px;color:#8b949e;padding:0 4px}
#chat .need{background:#e3b34126;border:2px solid #e3b341;margin-right:auto}
#chat .need b{color:#e3b341}
</style></head><body>
<div id="top"><button data-s="0" class="on">주 화면</button><button data-s="1">세로 모니터</button><button data-s="c">비서</button></div>
<div id="view"><img id="scr" alt=""></div>
<div id="chat"></div>
<div id="bar">
 <div id="reply"></div>
 <div id="tools"><button id="zoom">확대</button><button id="drag">끌기</button><button id="rclick">오른쪽 클릭</button><button id="wake">맥 화면 켜기</button><span id="st"></span></div>
 <div id="keys"><input id="txt" placeholder="글 입력"><button id="ask">비서에게</button><button id="typ">맥에 입력</button><button data-k="enter">⏎</button><button data-k="delete">⌫</button></div>
 <button id="talk">누르고 말하기</button>
</div>
<script>
const T=new URLSearchParams(location.search).get('t')||'';
const H={'X-Desk-Token':T};
const $=id=>document.getElementById(id);
const app=window.DeskApp||null;
let scr=0,tag='',mode='',live=true,fails=0;
function setBot(){document.documentElement.style.setProperty('--bot',$('bar').offsetHeight+'px')}
new ResizeObserver(setBot).observe($('bar'));setBot();
document.querySelectorAll('#top button').forEach(b=>b.onclick=()=>{
 document.querySelectorAll('#top button').forEach(x=>x.classList.remove('on'));b.classList.add('on');
 const c=b.dataset.s==='c';$('chat').style.display=c?'block':'none';$('view').style.display=c?'none':'block';
 $('tools').style.display=c?'none':'flex';
 if(!c){scr=+b.dataset.s;tag='';}});
async function loop(){
 while(true){
  if(document.hidden||$('view').style.display==='none'){await sleep(400);continue}
  const w=Math.min(2560,Math.round(innerWidth*devicePixelRatio*($('view').classList.contains('zoom')?2:1)));
  const s=scr;
  try{
   const r=await fetch(`/screen/${s}.jpg?w=${w}&q=55&h=${tag}`,{headers:H,cache:'no-store'});
   if(r.status===200){const b=await r.blob();if(s===scr){tag=r.headers.get('X-Frame')||'';const u=URL.createObjectURL(b);const old=$('scr').src;$('scr').src=u;if(old.startsWith('blob:'))setTimeout(()=>URL.revokeObjectURL(old),1000)}}
   else if(r.status===503&&r.headers.get('X-Asleep')){$('st').textContent='맥 화면이 꺼져 있어요 — 「맥 화면 켜기」';await sleep(1500)}
   else if(r.status!==204){$('st').textContent='화면 '+r.status;await sleep(1000)}
   fails=0;if(r.status===200||r.status===204)$('st').textContent='';
  }catch(e){fails++;$('st').textContent='연결 끊김 — 다시 시도';await sleep(Math.min(5000,500*fails))}
  await sleep(120);
 }}
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
// 이미지 안의 실제 그림 위치(object-fit:contain 여백 빼고) → 0~1
function frac(cx,cy){const im=$('scr'),R=im.getBoundingClientRect();const iw=im.naturalWidth||1,ih=im.naturalHeight||1;
 if($('view').classList.contains('zoom'))return[(cx-R.left)/R.width,(cy-R.top)/R.height];
 const k=Math.min(R.width/iw,R.height/ih),w=iw*k,h=ih*k,x0=R.left+(R.width-w)/2,y0=R.top+(R.height-h)/2;
 return[(cx-x0)/w,(cy-y0)/h]}
function send(ev){ev.screen=scr;tag='';return fetch('/input',{method:'POST',headers:{...H,'Content-Type':'application/json'},body:JSON.stringify(ev)}).then(r=>r.json()).catch(()=>({}))}
let t0=null,lastTap=0,moved=false,pressT=null,lastY=0,lastX=0,acc=0,accx=0,rightNext=false;
const V=$('view');
V.addEventListener('pointerdown',e=>{t0={x:e.clientX,y:e.clientY,t:Date.now()};moved=false;lastX=e.clientX;lastY=e.clientY;
 pressT=setTimeout(()=>{if(!moved&&t0){const[f,g]=frac(t0.x,t0.y);send({action:'right',x:f,y:g});navigator.vibrate&&navigator.vibrate(30);t0=null}},650)});
V.addEventListener('pointermove',e=>{if(!t0)return;const dx=e.clientX-lastX,dy=e.clientY-lastY;
 if(Math.hypot(e.clientX-t0.x,e.clientY-t0.y)>12){moved=true;clearTimeout(pressT)}
 if(moved&&!dragMode&&!V.classList.contains('zoom')){acc+=dy;accx+=dx;lastX=e.clientX;lastY=e.clientY;
  if(Math.abs(acc)>=6||Math.abs(accx)>=6){const k=1.5;const[f,g]=frac(t0.x,t0.y);send({action:'scroll',x:f,y:g,dy:Math.round(acc*k),dx:Math.round(accx*k)});acc=0;accx=0}}});
V.addEventListener('pointerup',e=>{clearTimeout(pressT);if(!t0)return;const[f,g]=frac(t0.x,t0.y);
 if(moved&&dragMode){const[f2,g2]=frac(e.clientX,e.clientY);send({action:'drag',x:f,y:g,x2:f2,y2:g2})}
 else if(!moved){if(rightNext){send({action:'right',x:f,y:g});rightNext=false;$('rclick').classList.remove('on')}
  else{const now=Date.now();if(now-lastTap<350){send({action:'double',x:f,y:g});lastTap=0}else{lastTap=now;send({action:'click',x:f,y:g})}}}
 t0=null});
V.addEventListener('pointercancel',()=>{clearTimeout(pressT);t0=null});
let dragMode=false;
$('drag').onclick=()=>{dragMode=!dragMode;$('drag').classList.toggle('on',dragMode)};
$('zoom').onclick=()=>{V.classList.toggle('zoom');$('zoom').classList.toggle('on');tag=''};
$('rclick').onclick=()=>{rightNext=!rightNext;$('rclick').classList.toggle('on',rightNext)};
$('wake').onclick=()=>{$('st').textContent='켜는 중…';fetch('/wake',{method:'POST',headers:H})};
$('typ').onclick=()=>{const v=$('txt').value;if(v){send({action:'type',text:v});$('txt').value=''}};
document.querySelectorAll('[data-k]').forEach(b=>b.onclick=()=>send({action:'key',key:b.dataset.k}));
function addMsg(cls,t){const d=document.createElement('div');d.className='m '+cls;d.textContent=t;$('chat').appendChild(d);$('chat').scrollTop=1e9}
function showReply(r){
 const heard=r.heard||'',rep=r.reply||r.error||'';
 $('reply').innerHTML='';if(heard){const h=document.createElement('div');h.className='h';h.textContent='🎙 '+heard;$('reply').appendChild(h)}
 const p=document.createElement('div');p.textContent=rep;$('reply').appendChild(p);setBot();
 if(heard)addMsg('me',heard);if(rep)addMsg('ai',r.full||rep);
 $('talk').classList.remove('wait');$('talk').textContent='누르고 말하기';
 if(app&&rep&&r.kind!=='local-silent')app.speak(rep)}
window.deskReply=s=>{try{showReply(typeof s==='string'?JSON.parse(s):s)}catch(e){showReply({reply:String(s)})}};
window.deskStatus=s=>{$('talk').textContent=s};
// 알림을 눌러 앱이 열림 — 비서 탭으로 가서 무엇을 확인해야 하는지 보여 줌
function showTab(k){document.querySelector(`#top button[data-s="${k}"]`).click()}
function addNeed(n){const d=document.createElement('div');d.className='m need';const b=document.createElement('b');b.textContent=n.title||'주인 확인 필요';
 d.appendChild(b);d.appendChild(document.createTextNode('\n'+(n.body||'')+(n.at?'\n'+new Date(n.at*1000).toLocaleTimeString('ko-KR',{hour:'2-digit',minute:'2-digit'}):'')));$('chat').appendChild(d);$('chat').scrollTop=1e9}
window.deskNotice=s=>{let n;try{n=typeof s==='string'?JSON.parse(s):s}catch(e){n={body:String(s)}}showTab('c');addNeed(n)};
$('ask').onclick=async()=>{const v=$('txt').value.trim();if(!v)return;$('txt').value='';
 $('talk').classList.add('wait');$('talk').textContent='생각 중…';addMsg('me',v);
 try{const r=await (await fetch('/ask',{method:'POST',headers:{...H,'Content-Type':'application/json'},body:JSON.stringify({text:v})})).json();delete r.heard;showReply(r)}
 catch(e){showReply({reply:'연결이 안 돼요. Tailscale 이 켜져 있는지 봐 주세요.'})}};
const tk=$('talk');
if(!app){tk.textContent='누르고 말하기 (앱에서만)';tk.disabled=true}
// 누르고 있는 동안 계속 녹음 — 손가락을 뗄 때(touchend · pointerup)만 보냄. 길게 누르기 · 스크롤 제스처가 만드는
// pointercancel · pointerleave 는 떼기가 아님(주인 10월 5일 18:12: 누르고 있는데 「생각 중」 으로 넘어가던 것)
let recTimer=null;
const begin=e=>{e.preventDefault();if(!app||tk.classList.contains('wait')||tk.classList.contains('rec'))return;
 app.stopSpeak();tk.classList.add('rec');tk.textContent='듣는 중… 떼면 보냄';app.startTalk();
 recTimer=setTimeout(end,90000)};
function end(){clearTimeout(recTimer);if(!app||!tk.classList.contains('rec'))return;tk.classList.remove('rec');tk.classList.add('wait');tk.textContent='받아쓰고 생각 중…';app.stopTalk()}
tk.addEventListener('touchstart',begin,{passive:false});
tk.addEventListener('mousedown',begin);
tk.addEventListener('contextmenu',e=>e.preventDefault());
document.addEventListener('touchend',e=>{if(!e.touches.length)end()});
document.addEventListener('mouseup',end);
loop();
</script></body></html>
"""
