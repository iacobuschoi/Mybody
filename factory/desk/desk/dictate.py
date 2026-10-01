"""주먹 쥐고 말하기 — Claude 데스크톱 앱이 맨 앞일 때 주먹을 쥔 채 한 말은 비서 대신 그 앱 입력창에 넣습니다.

    hand-mouse ──~/lab/hand-mouse/.run/fist.json (주먹 구간)──▶ deskd: 말한 동안 주먹이었나? + 맨 앞 앱이 Claude?
                                                              ├─ 둘 다 맞음 → 받아쓴 글을 붙여넣기(엔터 없음)
                                                              └─ 아니면 → 지금처럼 비서로

넣는 법은 실제 타이핑이 아니라 **클립보드 붙여넣기(⌘V)** 입니다.
  · 한글 입력기: 글자 하나씩 키 이벤트로 보내면(CGEventKeyboardSetUnicodeString) 한글 입력 소스가 켜져 있을 때
    입력기가 그 이벤트를 가로채 자모가 깨지거나(가상 키 0 = 'ㅁ') 조합 중인 글자와 섞입니다. ⌘V 는 입력 소스와
    상관없이 같은 키(가상 키 9)로 듣고, 붙여넣기는 조합 중인 글자를 먼저 확정한 뒤 들어갑니다.
  · Claude 앱은 Electron 이라 합성 유니코드 키 이벤트를 다루는 게 앱 · 버전마다 다릅니다. 붙여넣기는 늘 같습니다.
  · 한 번에 들어가 빠르고(긴 말도 0.1초), 그 사이 손 · 키보드 입력과 섞이지 않습니다.
  · 클립보드는 잠깐 빌렸다가 0.6초 뒤 원래 것(모든 형식)으로 되돌립니다. 그 사이 주인이 복사한 게 있으면 안 건드립니다.
    빌리는 동안 "잠깐 쓰는 값"(org.nspasteboard.TransientType · ConcealedType) 표시를 달아 클립보드 기록 앱이 남기지 않게.
⌘V 를 보내려면 deskd 에 손쉬운 사용 권한(시스템 설정 → 개인정보 보호 및 보안 → 손쉬운 사용)이 있어야 합니다.

지우기 다이얼: 다른 손(왼손)으로 엄지 · 검지를 집은 채 반시계로 돌리면 넣은 글을 **한 단어씩** 지우고, 시계로 돌리면
지운 걸 되살립니다(hand-mouse 가 25도마다 한 칸씩 POST /api/dial 로 보냄).
  · 단위가 단어(띄어쓰기 덩어리)인 이유: 받아쓰기는 보통 단어째 틀리고, 손목을 편하게 돌리는 범위(±90도)에 서너 칸이라
    글자 단위면 한 문장을 지우는 데 손을 여러 번 고쳐 쥐어야 합니다. 단어 앞 띄어쓰기도 같이 지워 깔끔하게 남습니다.
  · 회전 → 자리(속도 아님): 돌린 만큼 정확히 지우고 되돌리면 그만큼 돌아와, 지나쳐도 바로 고칩니다.
  · 지우기는 백스페이스(우리가 넣은 글자 수만큼 정확, ⌘Z 는 앱이 직접 친 글과 묶기도 함), 되살리기는 그 부분을 다시 붙여넣기.
  · 넣은 지 erase_window_s(2분)가 지났거나 앞 앱이 바뀌었으면 커서가 옮겨졌을 수 있어 아무것도 안 합니다.
  · 지운 뒤 새로 받아쓰면 지운 부분은 버려지고(되살리기 끝) 남은 글 뒤에 이어 붙습니다.
"""
from __future__ import annotations

import json
import logging
import os
import subprocess
import threading
import time

log = logging.getLogger("deskd")

CLAUDE_APP = "com.anthropic.claudefordesktop"
TRANSIENT = ("org.nspasteboard.TransientType", "org.nspasteboard.ConcealedType")
V_KEY = 9                                      # ⌘V 의 v (ANSI 자판 자리 — 입력 소스와 상관없음)
DELETE_KEY = 51                                # 백스페이스



# ── 주먹 상태 (hand-mouse 가 적는 파일) ─────────────────────────────────────
def read_fist(path: str) -> dict | None:
    try:
        with open(os.path.expanduser(path)) as f:
            d = json.load(f)
        return d if isinstance(d, dict) else None
    except (OSError, ValueError):
        return None


def fist_overlap(state: dict | None, t0: float, t1: float, stale_s: float = 3.0) -> float:
    """[t0, t1] 동안 주먹이었던 시간(초). 끝나지 않은 구간은 지금(또는 hand-mouse 가 멈췄으면 마지막 적은 때)까지로 봄"""
    if not state:
        return 0.0
    at = float(state.get("at") or 0.0)
    open_end = at if time.time() - at > stale_s else max(at, t1)
    total = 0.0
    for span in state.get("spans") or []:
        try:
            a, b = float(span[0]), (float(span[1]) if span[1] is not None else open_end)
        except (TypeError, ValueError, IndexError):
            continue
        total += max(0.0, min(b, t1) - max(a, t0))
    return total


def held_fist(state: dict | None, t0: float, t1: float, ratio: float = 0.5, enough_s: float = 1.0,
              stale_s: float = 3.0) -> bool:
    """말한 동안 주먹을 쥐고 있었나 — 말한 시간의 ratio 이상, 또는 enough_s 이상 주먹이면 그렇다고 봄
    (말 끝 침묵까지 조각에 들어 있어 말을 마치고 바로 손을 펴도 되게)"""
    dur = max(t1 - t0, 1e-6)
    got = fist_overlap(state, t0, t1, stale_s)
    return got >= min(ratio * dur, enough_s)


# ── 맨 앞 앱 ────────────────────────────────────────────────────────────────
def front_bundle() -> str:
    """맨 앞 앱의 번들 ID. System Events 는 loginwindow 오류를 내서 lsappinfo 로(10ms 안팎)"""
    try:
        asn = subprocess.run(["lsappinfo", "front"], capture_output=True, text=True, timeout=2).stdout.strip()
        if not asn:
            return ""
        out = subprocess.run(["lsappinfo", "info", "-only", "bundleid", asn],
                             capture_output=True, text=True, timeout=2).stdout
    except (OSError, subprocess.SubprocessError):
        return ""
    # "CFBundleIdentifier"="com.anthropic.claudefordesktop"
    return out.rsplit("=", 1)[-1].strip().strip('"') if "=" in out else ""


# ── 붙여넣기 ────────────────────────────────────────────────────────────────
def can_post_keys(ask: bool = False) -> bool:
    try:
        import Quartz
    except ImportError:
        return False
    if Quartz.CGPreflightPostEventAccess():
        return True
    if ask:
        Quartz.CGRequestPostEventAccess()      # 설정 창 안내를 한 번 띄움
    return False


def _save_board(pb) -> list[list[tuple[str, object]]]:
    saved = []
    for item in pb.pasteboardItems() or []:
        saved.append([(t, item.dataForType_(t)) for t in item.types() if item.dataForType_(t) is not None])
    return saved


def _restore_board(pb, saved) -> None:
    import AppKit
    pb.clearContents()
    items = []
    for kinds in saved:
        it = AppKit.NSPasteboardItem.alloc().init()
        for t, data in kinds:
            it.setData_forType_(data, t)
        items.append(it)
    if items:
        pb.writeObjects_(items)


def _cmd_v() -> None:
    import Quartz
    src = Quartz.CGEventSourceCreate(Quartz.kCGEventSourceStateHIDSystemState)
    for down in (True, False):
        e = Quartz.CGEventCreateKeyboardEvent(src, V_KEY, down)
        Quartz.CGEventSetFlags(e, Quartz.kCGEventFlagMaskCommand)
        Quartz.CGEventPost(Quartz.kCGHIDEventTap, e)
        time.sleep(0.01)


def backspace(n: int) -> bool:
    """백스페이스 n 번(맨 앞 앱에)"""
    if n <= 0 or not can_post_keys():
        return n <= 0
    import Quartz
    src = Quartz.CGEventSourceCreate(Quartz.kCGEventSourceStateHIDSystemState)
    for _ in range(n):
        for down in (True, False):
            e = Quartz.CGEventCreateKeyboardEvent(src, DELETE_KEY, down)
            Quartz.CGEventSetFlags(e, 0)
            Quartz.CGEventPost(Quartz.kCGHIDEventTap, e)
        time.sleep(0.004)
    return True


def paste(text: str, restore_after_s: float = 0.6) -> bool:
    """글을 맨 앞 앱의 입력란에 붙여 넣음(엔터는 안 침). 클립보드는 잠시 뒤 되돌림"""
    import AppKit
    if not can_post_keys():
        return False
    pb = AppKit.NSPasteboard.generalPasteboard()
    saved = _save_board(pb)
    pb.clearContents()
    pb.setString_forType_(text, AppKit.NSPasteboardTypeString)
    for t in TRANSIENT:
        pb.setString_forType_("", t)
    mine = pb.changeCount()
    _cmd_v()

    def restore():
        time.sleep(restore_after_s)            # 앱이 클립보드를 읽을 시간
        if pb.changeCount() == mine:           # 그 사이 주인이 복사했으면 그대로 둠
            _restore_board(pb, saved)
    threading.Thread(target=restore, daemon=True, name="dictate-restore").start()
    return True


class Dictation:
    """주먹 + Claude 앱이 맨 앞 → 붙여넣기. take() 가 True 면 그 말은 비서로 보내지 않음"""

    def __init__(self, cfg: dict, front=front_bundle, put=paste, fist=read_fist, back=backspace):
        self.enabled = bool(cfg.get("enabled", True))
        self.state_path = cfg.get("fist_state", "~/lab/hand-mouse/.run/fist.json")
        self.apps = list(cfg.get("apps", [CLAUDE_APP]))
        self.ratio = float(cfg.get("fist_ratio", 0.5))
        self.enough_s = float(cfg.get("fist_enough_s", 1.0))
        self.join_s = float(cfg.get("join_s", 60.0))
        self.erase_window_s = float(cfg.get("erase_window_s", 120.0))
        self._front, self._put, self._fist, self._back = front, put, fist, back
        self._last_at = 0.0                    # 마지막으로 넣거나 지운 때 — 이어 말하면 앞에 띄어쓰기
        self.text = ""                         # 이번에 이어 넣은 글 전부(지운 부분 포함 — 되살리기용)
        self.kept = 0                          # 그중 지금 입력창에 남아 있는 글자 수
        self._app = ""                         # 그 글을 넣은 앱
        self._lock = threading.Lock()          # 다이얼(HTTP 스레드)과 받아쓰기가 겹치지 않게
        self.warned = False                    # 권한 없음 알림은 한 번만

    def wants(self, t0: float, t1: float) -> bool:
        """이 말([t0, t1], 벽시계)을 받아쓰기로 넣을지 — 글 없이도 판단(받아쓰기 전에 물어도 됨)"""
        if not self.enabled or t1 <= 0:
            return False
        if not held_fist(self._fist(self.state_path), t0, t1, self.ratio, self.enough_s):
            return False
        return self._front() in self.apps

    def put(self, text: str) -> bool:
        text = text.strip()
        if not text:
            return False
        with self._lock:
            now = time.time()
            app = self._front()
            fresh = now - self._last_at >= self.join_s or app != self._app
            if fresh:
                self.text, self.kept = "", 0
            sep = " " if self.kept else ""
            ok = self._put(sep + text)
            if ok:
                self.text = self.text[:self.kept] + sep + text   # 지운 부분은 버림(되살리기 끝)
                self.kept = len(self.text)
                self._app, self._last_at = app, now
            return ok

    def stops(self) -> list[int]:
        """다이얼 칸 자리: 0 과 단어 끝(뒤가 띄어쓰기거나 글 끝)"""
        t = self.text
        return [0] + [i for i in range(1, len(t) + 1) if t[i - 1] != " " and (i == len(t) or t[i] == " ")]

    def dial(self, steps: int) -> str:
        """다이얼 steps 칸(- 지우기 · + 되살리기). 한 일을 짧게 돌려줌"""
        with self._lock:
            if not steps or not self.text:
                return "없음"
            if time.time() - self._last_at > self.erase_window_s or self._front() != self._app:
                return "안 함(시간이 지났거나 앞 앱이 바뀜)"
            stops = self.stops()
            at = max(i for i, p in enumerate(stops) if p <= self.kept)
            to = stops[min(max(at + steps, 0), len(stops) - 1)]
            if to == self.kept:
                return "끝"
            if to < self.kept:
                ok, did = self._back(self.kept - to), f"지움 {self.kept - to}글자"
            else:
                ok, did = self._put(self.text[self.kept:to]), f"되살림 {to - self.kept}글자"
            if not ok:
                return "못 함(손쉬운 사용 권한)"
            self.kept, self._last_at = to, time.time()
            return did
