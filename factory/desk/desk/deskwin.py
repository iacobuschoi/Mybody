"""책상 화면 — 두 번째 모니터(주 화면이 아닌 화면 중 가장 오른쪽)는 책상 상태판 전용 (주인 10월 2일 15:04).

deskd 시작 · 화면 구성이 바뀔 때(모니터 다시 붙음 · 화면이 깸)만 한 번씩 (keep — 그 사이엔 손대지 않음):
  1. 사파리에 「책상」 창이 없으면 새 창으로 연다.
  2. 그 창이 책상 화면을 꽉 채우게 옮기고 키운다 — 이미 제자리면 그대로. 최소화 · 사파리 가리기도 푼다.
  3. 책상 화면에 올라온 다른 창은 주 화면으로 옮긴다 (전체 화면 창은 건드리지 않음).
화면이 하나뿐이거나 책상 화면이 잠들었으면 아무것도 안 한다. 창 찾기 · 옮기기는 손쉬운 사용(AX) — deskd 가 이미 받은 권한.
끄기: config.toml [dashboard] keep_screen = false.
"""
from __future__ import annotations

import logging
import subprocess
import threading
import time

log = logging.getLogger("desk")

TITLE = "책상"            # dashboard.PAGE 의 <title>
SAFARI = "com.apple.Safari"
OPEN_WAIT_S = 8.0         # 새 창을 열라고 한 뒤 이만큼은 다시 열지 않음 (사파리가 뜨는 동안)
MENUBAR = 25             # 그 화면에도 메뉴 막대가 있을 때 높이 (pt)
MIN_SIDE = 60
MOVE_WAIT_S = 0.25       # AX 자리 → 크기 사이 기다림             # 이보다 작은 창(툴팁 · 작은 패널)은 옮기지 않음


def screens(Q=None) -> tuple[tuple, tuple | None]:
    """(주 화면, 책상 화면) — 각 (x, y, w, h), 왼쪽 위 원점 전역 좌표(AX 와 같음). 책상 화면이 없으면 None."""
    if Q is None:
        import Quartz as Q
    ids = Q.CGGetActiveDisplayList(16, None, None)[1] or []
    main = Q.CGMainDisplayID()

    def rect(d):
        b = Q.CGDisplayBounds(d)
        return (b.origin.x, b.origin.y, b.size.width, b.size.height), d

    others = [rect(d) for d in ids if d != main]
    m = rect(main)[0]
    if not others:
        return m, None
    r, d = max(others, key=lambda o: o[0][0])
    return m, (r if not Q.CGDisplayIsAsleep(d) else None)


def inside(rect: tuple, frame: tuple) -> bool:
    """창(x, y, w, h)의 가운데가 화면 안인가."""
    cx, cy = rect[0] + rect[2] / 2, rect[1] + rect[3] / 2
    return frame[0] <= cx < frame[0] + frame[2] and frame[1] <= cy < frame[1] + frame[3]


def same(a: tuple, b: tuple, tol: float = 3) -> bool:
    return all(abs(x - y) <= tol for x, y in zip(a, b))


def fills(f: tuple, screen: tuple, menubar: float = 40, tol: float = 3) -> bool:
    """창이 화면을 꽉 채웠나 — 위는 그 화면 메뉴 막대만큼 내려와도 됨 (macOS 가 막대 아래로 밀어냄)."""
    return (abs(f[0] - screen[0]) <= tol and abs(f[2] - screen[2]) <= tol
            and -tol <= f[1] - screen[1] <= menubar and abs(f[1] + f[3] - screen[1] - screen[3]) <= tol)


def evicted(rect: tuple, main: tuple, menubar: float = 25) -> tuple:
    """책상 화면에 있던 창 → 주 화면 안에 들어가는 자리 (x, y, w, h). 크면 줄인다."""
    w, h = min(rect[2], main[2]), min(rect[3], main[3] - menubar)
    x = main[0] + max(0, (main[2] - w) / 2)
    y = main[1] + menubar + max(0, (main[3] - menubar - h) / 2)
    return (x, y, w, h)


class AX:
    """손쉬운 사용 API 를 얇게 — 시험에서는 가짜로 바꾼다."""

    def __init__(self):
        import ApplicationServices as A
        self.A = A

    def trusted(self) -> bool:
        return bool(self.A.AXIsProcessTrusted())

    def _get(self, el, attr):
        err, v = self.A.AXUIElementCopyAttributeValue(el, attr, None)
        return v if err == 0 else None

    def windows(self, pid: int) -> list:
        return list(self._get(self.A.AXUIElementCreateApplication(pid), "AXWindows") or [])

    def app(self, pid: int):
        return self.A.AXUIElementCreateApplication(pid)

    def title(self, w) -> str:
        return str(self._get(w, "AXTitle") or "")

    def flag(self, el, attr) -> bool:
        return bool(self._get(el, attr))

    def set_flag(self, el, attr, v: bool) -> None:
        self.A.AXUIElementSetAttributeValue(el, attr, v)

    def frame(self, w) -> tuple | None:
        A = self.A
        p, s = self._get(w, "AXPosition"), self._get(w, "AXSize")
        if p is None or s is None:
            return None
        _, pt = A.AXValueGetValue(p, A.kAXValueCGPointType, None)
        _, sz = A.AXValueGetValue(s, A.kAXValueCGSizeType, None)
        return (pt.x, pt.y, sz.width, sz.height)

    def move(self, w, rect: tuple) -> None:
        A = self.A
        x, y, wd, ht = rect
        # 옮기기는 비동기라, 자리가 바뀌기 전에 크기를 넣으면 옛 화면(주 화면 768) 높이로 잘린다 (실제 15:13: 689 에서 멈춤)
        A.AXUIElementSetAttributeValue(w, "AXPosition", A.AXValueCreate(A.kAXValueCGPointType, (x, y)))
        time.sleep(MOVE_WAIT_S)
        A.AXUIElementSetAttributeValue(w, "AXSize", A.AXValueCreate(A.kAXValueCGSizeType, (wd, ht)))
        time.sleep(MOVE_WAIT_S)
        A.AXUIElementSetAttributeValue(w, "AXPosition", A.AXValueCreate(A.kAXValueCGPointType, (x, y)))


def onscreen_windows(Q=None) -> list[tuple[int, tuple]]:
    """화면에 보이는 보통 창(layer 0)들 — (pid, (x, y, w, h))."""
    if Q is None:
        import Quartz as Q
    infos = Q.CGWindowListCopyWindowInfo(Q.kCGWindowListOptionOnScreenOnly | Q.kCGWindowListExcludeDesktopElements,
                                         Q.kCGNullWindowID) or []
    out = []
    for i in infos:
        if i.get("kCGWindowLayer", 0) != 0 or i.get("kCGWindowAlpha", 1) <= 0:
            continue
        b = i.get("kCGWindowBounds") or {}
        r = (b.get("X", 0), b.get("Y", 0), b.get("Width", 0), b.get("Height", 0))
        if r[2] >= MIN_SIDE and r[3] >= MIN_SIDE:
            out.append((int(i.get("kCGWindowOwnerPID", 0)), r))
    return out


def safari_pid() -> int | None:
    from AppKit import NSRunningApplication
    apps = NSRunningApplication.runningApplicationsWithBundleIdentifier_(SAFARI)
    return int(apps[0].processIdentifier()) if apps and len(apps) else None


def open_window(url: str) -> None:
    """사파리 새 창으로 (다른 창의 탭으로 끼어들지 않게). 사파리를 앞으로 가져오지는 않는다."""
    subprocess.Popen(["osascript", "-e", f'tell application "Safari" to make new document with properties {{URL:"{url}"}}'],
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


class Keeper:
    def __init__(self, url: str, ax=None, screens_fn=screens, windows_fn=onscreen_windows, pid_fn=safari_pid,
                 open_fn=open_window):
        self.url = url
        self.ax = ax
        self.screens, self.windows, self.pid, self.open = screens_fn, windows_fn, pid_fn, open_fn
        self.opened = -1e9
        self.warned = False
        self.last = ""             # 같은 말을 몇 초마다 로그에 쌓지 않게
        self.mine = None           # 마지막 step 에서 찾은 책상 창 자리

    def _say(self, msg: str) -> None:
        if msg != self.last:
            self.last = msg
            log.info("책상 화면: %s", msg)

    def fit(self, w, desk: tuple) -> None:
        """메뉴 막대(MENUBAR) 바로 아래부터 화면 끝까지. y=0 에 놓으면 그 화면 메뉴 막대 때문에 창이 엉뚱하게 아래로 밀리고
        (실제: y=309, 10월 2일 15:11) 옮기기는 비동기라 곧바로 읽어 고칠 수도 없다 → 처음부터 막대 아래에 놓는다."""
        self.ax.move(w, (desk[0], desk[1] + MENUBAR, desk[2], desk[3] - MENUBAR))

    def step(self, now: float | None = None) -> str:
        """한 번 맞춤. 무엇을 했는지 짧게 돌려줌 (시험 · 로그용)."""
        now = time.monotonic() if now is None else now
        main, desk = self.screens()
        if desk is None:
            return "책상 화면 없음"
        if self.ax is None:
            self.ax = AX()
        if not self.ax.trusted():
            if not self.warned:
                self.warned = True
                log.warning("책상 화면: 손쉬운 사용 권한이 없어 창을 못 옮김 (설정 → 개인정보 보호 및 보안 → 손쉬운 사용 → deskd)")
            return "권한 없음"
        did = []
        pid = self.pid()
        mine = None
        if pid:
            ours = [w for w in self.ax.windows(pid) if self.ax.title(w) == TITLE]
            framed = [(w, self.ax.frame(w)) for w in ours]
            framed = [(w, f) for w, f in framed if f]
            on = [x for x in framed if inside(x[1], desk)]
            pick = (on or framed or [None])[0]
            if pick is None and ours:
                pick = (ours[0], None)
            if pick:
                w, f = pick
                app = self.ax.app(pid)
                if self.ax.flag(app, "AXHidden"):
                    self.ax.set_flag(app, "AXHidden", False)
                    did.append("사파리 보이기")
                if self.ax.flag(w, "AXMinimized"):
                    self.ax.set_flag(w, "AXMinimized", False)
                    did.append("최소화 풀기")
                if f is None or not fills(f, desk):
                    self.fit(w, desk)
                    did.append("창 맞춤")
                mine = self.ax.frame(w)
        self.mine = mine
        if mine is None and now - self.opened > OPEN_WAIT_S:
            self.opened = now
            self.open(self.url)
            did.append("새 창 열기")
        for wpid, r in self.windows():
            if not inside(r, desk) or (wpid == pid and mine and same(r, mine)):
                continue
            for w in self.ax.windows(wpid):
                f = self.ax.frame(w)
                if f and same(f, r) and not self.ax.flag(w, "AXFullScreen"):
                    if wpid == pid and self.ax.title(w) == TITLE:
                        continue
                    self.ax.move(w, evicted(r, main))
                    did.append("다른 창 옮김")
                    break
        msg = " · ".join(did) or "그대로"
        if did:
            self._say(msg)
        return msg


_running = False


def running() -> bool:
    """keep 이 돌고 있나 — 그러면 mac.open_dashboard 는 따로 열지 않는다 (창이 둘 생기지 않게)."""
    return _running


def keep(url: str, every_s: float = 2.0) -> threading.Thread:
    """deskd 시작 때, 그리고 화면 구성이 바뀔 때(모니터를 다시 붙임 · 화면이 잠에서 깸 · 크기 바뀜)만 한 번 맞춘다.
    그 사이에는 창을 건드리지 않는다 (주인 15:13: 창이 계속 왔다 갔다 함 — 이미 제자리면 손대지 말 것).
    새 창을 연 뒤에는 그 창이 뜰 때까지(OPEN_WAIT_S)만 다시 본다. 오류는 로그만 남기고 계속."""
    global _running
    _running = True
    k = Keeper(url)

    def loop():
        seen, until = object(), 0.0
        while True:
            try:
                now = time.monotonic()
                cur = k.screens()
                if cur != seen or now < until:
                    seen = cur
                    msg = k.step(now)
                    until = now + OPEN_WAIT_S if "새 창 열기" in msg else (until if now < until and k.mine is None else 0.0)
            except Exception as e:  # noqa: BLE001
                k._say(f"오류 {e!r}")
            time.sleep(every_s)
    t = threading.Thread(target=loop, daemon=True, name="deskwin")
    t.start()
    return t
