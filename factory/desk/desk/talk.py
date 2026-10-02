"""왼손 주먹 = 비서에게 말하기(누르고 말하기).

    hand-mouse ──POST /api/talk start──▶ deskd: 짧은 소리 · 녹음 시작(바로 앞 preroll_s 도 붙임)
               ──hold (1초마다)──────▶       쥐고 있는 동안 계속 녹음 (상시 듣기 자르개에는 안 넣음)
               ──end─────────────────▶       tail_s 만 더 받고 바로 받아쓰기 → "[음성·주먹 HH:MM] …" 로 비서에게

상시 듣기는 말 끝 침묵(0.8~2초)을 기다려야 하고 방의 다른 말과 섞이지만, 이 구간은 쥐고 편 때가 말의 처음과 끝이라
기다릴 것이 없고, 주인이 비서에게 한 말이 확실하므로 Claude 에게도 그렇게 알린다(무시 판정 없음).
hold 가 beat_s 넘게 안 오면(hand-mouse 가 죽음) · max_s 를 넘으면 거기서 끊어 넘긴다.
"""
from __future__ import annotations

import threading
import time
from collections import deque

import numpy as np


class PushToTalk:
    def __init__(self, sr: int = 16000, preroll_s: float = 0.4, tail_s: float = 0.25, max_s: float = 90.0,
                 beat_s: float = 3.0, clock=time.time, **_):
        self.sr = sr
        self.preroll_s, self.tail_s, self.max_s, self.beat_s = preroll_s, tail_s, max_s, beat_s
        self.clock = clock
        self._lock = threading.Lock()
        self._pre: deque[np.ndarray] = deque()     # 최근 preroll_s 소리 — 쥐기 조금 전에 말을 시작해도 첫소리가 안 잘리게
        self._pre_n = 0
        self._chunks: list[np.ndarray] | None = None
        self.started = 0.0                          # 녹음 시작(벽시계, preroll 포함)
        self._end_at = 0.0                          # 0 이 아니면 이때 끝냄
        self._beat = 0.0

    @property
    def active(self) -> bool:
        return self._chunks is not None

    def start(self) -> bool:
        """새로 시작했으면 True. 이미 녹음 중이면(펴자마자 다시 쥠 포함) 이어서 — False"""
        with self._lock:
            now = self.clock()
            self._beat = now
            if self._chunks is not None:
                self._end_at = 0.0
                return False
            self._chunks = list(self._pre)
            self.started = now - self._pre_n / self.sr
            self._end_at = 0.0
            return True

    def hold(self) -> None:
        with self._lock:
            self._beat = self.clock()

    def end(self) -> bool:
        with self._lock:
            if self._chunks is None:
                return False
            if not self._end_at:
                self._end_at = self.clock() + self.tail_s
            return True

    def cancel(self) -> None:
        with self._lock:
            self._chunks, self._end_at = None, 0.0

    def feed(self, x: np.ndarray) -> tuple[np.ndarray, float, float, str] | None:
        """소리 한 조각. 녹음이 끝났으면 (소리, 시작, 끝, 왜) — 받아쓰기로 넘길 것"""
        with self._lock:
            self._pre.append(x)
            self._pre_n += len(x)
            while self._pre and self._pre_n - len(self._pre[0]) >= self.preroll_s * self.sr:
                self._pre_n -= len(self._pre.popleft())
            if self._chunks is None:
                return None
            self._chunks.append(x)
            now = self.clock()
            why = ("손 폄" if self._end_at and now >= self._end_at else
                   "너무 김" if now - self.started > self.max_s else
                   "hand-mouse 소식 없음" if now - self._beat > self.beat_s else "")
            if not why:
                return None
            audio = np.concatenate(self._chunks)
            self._chunks, self._end_at = None, 0.0
            return audio, self.started, now, why
