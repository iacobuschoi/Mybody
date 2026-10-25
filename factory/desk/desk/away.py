"""자리 비움 — 손 카메라(hand-mouse)에 주인이 몇 초째 안 보이면, 주먹 없이 한 말도 비서에게 한 말로 (주인 10월 25일 11:49).

카메라는 hand-mouse 가 쥐고 있으므로 따로 열지 않고, hand-mouse 가 책상 「손 카메라」 칸에 넘기는 그림
(~/.cache/hand-mouse/view.jpg)을 every_s 마다 봅니다. 볼 때마다 want 를 건드려 책상 페이지가 닫혀 있어도 그림이 오게.
사람이 있다 = 얼굴(YuNet, desk/face.py 와 같은 모델)이 보이거나 그림이 움직임(몸을 돌려 얼굴이 안 보여도).
둘 다 away_s 동안 계속 없을 때만 자리 비움 — 잠깐 고개를 숙이거나 한 장 놓친 것으로 깜빡이지 않게.
새 그림이 stale_s 넘게 없으면(hand-mouse 꺼짐 · 화면 꺼짐) 모름 → 자리 비움 아님(예전처럼).
"""
from __future__ import annotations

import logging
import os
import threading
import time
from typing import Callable

import numpy as np

log = logging.getLogger("desk")

HANDCAM = os.path.expanduser("~/.cache/hand-mouse")   # dashboard.HANDCAM · hand-mouse overlay.py DESK_DIR 와 같은 자리


class Away:
    def __init__(self, cfg: dict, wanted: Callable[[], bool] = lambda: True,
                 on_change: Callable[[bool], None] | None = None, folder: str = ""):
        self.enabled = bool(cfg.get("enabled", True))
        self.away_s = float(cfg.get("away_s", 8.0))
        self.every_s = float(cfg.get("every_s", 1.0))
        self.stale_s = float(cfg.get("stale_s", 3.0))
        self.min_face_px = int(cfg.get("min_face_px", 20))
        self.face_score = float(cfg.get("face_score", 0.6))
        self.motion = float(cfg.get("motion", 0.005))  # 1초 사이 바뀐 칸이 이 비율 이상이면 움직임 (빈 방 0 · 앉은 주인 0.009~0.13)
        self.folder = folder or HANDCAM
        self.wanted, self.on_change = wanted, on_change
        self.seen = time.time()          # 마지막으로 사람을 본 때 — 켜자마자 자리 비움이 되지 않게 지금으로
        self.frame_t = 0.0               # 마지막으로 새 그림을 본 때
        self._mtime = 0.0
        self._prev: np.ndarray | None = None
        self._det = None
        self._was = False
        self._stop = threading.Event()

    # ── 판단 ─────────────────────────────────────────────────────────────
    def away(self, now: float | None = None) -> bool:
        """지금 자리 비움인가 — 그림이 살아 있고 away_s 넘게 사람이 안 보였을 때만"""
        now = time.time() if now is None else now
        return (self.enabled and now - self.frame_t < self.stale_s and now - self.seen >= self.away_s)

    def look(self, frame: np.ndarray, now: float | None = None) -> bool:
        """새 그림 한 장 — 사람이 보였나(얼굴 또는 움직임)"""
        now = time.time() if now is None else now
        if not self.frame_t or now - self.frame_t >= self.stale_s:
            self.seen = max(self.seen, now)   # 그림이 끊겼다 다시 옴 — 그동안은 모르므로 지금부터 다시 셈
            self._prev = None
        self.frame_t = now
        person = self._face(frame) or self._moved(frame)
        if person:
            self.seen = now
        return person

    def _face(self, frame: np.ndarray) -> bool:
        if self._det is None:
            from .face import have_models, model_path
            if not have_models():
                self._det = False
            else:
                import cv2
                self._det = cv2.FaceDetectorYN.create(model_path("detector"), "", (320, 320),
                                                      self.face_score, 0.3, 20)
        if self._det is False:
            return False
        h, w = frame.shape[:2]
        self._det.setInputSize((w, h))
        _, found = self._det.detect(frame)
        return found is not None and any(min(f[2], f[3]) >= self.min_face_px for f in found)

    def _moved(self, frame: np.ndarray) -> bool:
        import cv2
        g = cv2.GaussianBlur(cv2.cvtColor(cv2.resize(frame, (160, 120)), cv2.COLOR_BGR2GRAY), (5, 5), 0)
        prev, self._prev = self._prev, g
        if prev is None:
            return False
        return float(np.mean(cv2.absdiff(g, prev) > 25)) >= self.motion

    # ── 고리 ─────────────────────────────────────────────────────────────
    def _read(self) -> np.ndarray | None:
        p = os.path.join(self.folder, "view.jpg")
        try:
            m = os.stat(p).st_mtime
        except OSError:
            return None
        if m == self._mtime or time.time() - m > self.stale_s:
            return None
        import cv2
        f = cv2.imread(p)
        if f is not None:
            self._mtime = m
        return f

    def _touch(self) -> None:
        os.makedirs(self.folder, exist_ok=True)
        p = os.path.join(self.folder, "want")
        with open(p, "a"):
            pass
        os.utime(p)

    def tick(self) -> None:
        if self.wanted():
            self._touch()
            f = self._read()
            if f is not None:
                self.look(f)
        now = self.away()
        if now != self._was:
            self._was = now
            log.info("자리 비움 — 주먹 없이 한 말도 비서에게" if now else "주인 보임 — 주먹 말만 직접")
            if self.on_change:
                self.on_change(now)

    def run(self) -> None:
        if not self.enabled:
            return
        while not self._stop.wait(self.every_s):
            try:
                self.tick()
            except Exception:  # noqa: BLE001
                log.exception("자리 비움 보기 실패")

    def start(self) -> None:
        threading.Thread(target=self.run, daemon=True, name="away").start()

    def stop(self) -> None:
        self._stop.set()
