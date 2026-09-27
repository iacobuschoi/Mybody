"""말소리 구간 자르기 — 상시 듣기에서 "한 마디" 를 잘라 받아쓰기에 넘긴다.

webrtcvad 가 있으면 쓰고(말인지), 에너지(바닥 소음보다 큰지)와 같이 봅니다. 둘 다 맞아야 말로 칩니다 —
webrtcvad 는 선풍기 소리에도 곧잘 "말" 이라고 합니다.
말하는 중(스피커로 우리 목소리가 나가는 중)에는 pause() 로 귀를 닫습니다. 안 그러면 제 목소리를 명령으로 듣습니다.
"""
from __future__ import annotations

from collections import deque

import numpy as np


class Segmenter:
    def __init__(self, sr: int = 16000, frame_ms: int = 30, level: int = 2, start_ratio: float = 0.6,
                 end_silence_s: float = 0.8, min_utt_s: float = 0.4, max_utt_s: float = 20.0,
                 preroll_s: float = 0.3, energy_db: float = 8.0):
        self.sr, self.n = sr, int(sr * frame_ms / 1000)
        self.frame_s = frame_ms / 1000
        self.start_ratio, self.end_silence_s = start_ratio, end_silence_s
        self.min_utt_s, self.max_utt_s = min_utt_s, max_utt_s
        self.energy_k = 10 ** (energy_db / 20)
        try:
            import webrtcvad
            self._vad = webrtcvad.Vad(level)
        except Exception:
            self._vad = None
        self._buf = np.zeros(0, dtype=np.float32)
        self._ring: deque[tuple[np.ndarray, bool]] = deque(maxlen=max(3, int(preroll_s / self.frame_s)))
        self._floor: deque[float] = deque(maxlen=int(3.0 / self.frame_s))
        self._utt: list[np.ndarray] | None = None
        self._silence = 0.0
        self._paused = False

    def pause(self) -> None:
        self._paused = True
        self.reset()

    def resume(self) -> None:
        self._paused = False

    def reset(self) -> None:
        self._buf = np.zeros(0, dtype=np.float32)
        self._ring.clear()
        self._utt = None
        self._silence = 0.0

    @property
    def in_speech(self) -> bool:
        return self._utt is not None

    def _is_speech(self, f: np.ndarray) -> bool:
        rms = float(np.sqrt(np.mean(f.astype(np.float64) ** 2))) + 1e-9
        floor = max(float(np.median(self._floor)) if self._floor else rms, 1e-4)
        if not self.in_speech:
            self._floor.append(rms)
        loud = rms > floor * self.energy_k
        if self._vad is None:
            return loud
        pcm = (np.clip(f, -1, 1) * 32767).astype(np.int16).tobytes()
        try:
            return loud and self._vad.is_speech(pcm, self.sr)
        except Exception:
            return loud

    def feed(self, x: np.ndarray) -> list[np.ndarray]:
        out: list[np.ndarray] = []
        if self._paused:
            return out
        self._buf = np.concatenate([self._buf, np.asarray(x, dtype=np.float32).reshape(-1)])
        while len(self._buf) >= self.n:
            f, self._buf = self._buf[: self.n], self._buf[self.n:]
            sp = self._is_speech(f)
            if self._utt is None:
                self._ring.append((f, sp))
                voiced = sum(1 for _, v in self._ring if v)
                if len(self._ring) == self._ring.maxlen and voiced >= self.start_ratio * len(self._ring):
                    self._utt = [g for g, _ in self._ring]
                    self._ring.clear()
                    self._silence = 0.0
            else:
                self._utt.append(f)
                self._silence = 0.0 if sp else self._silence + self.frame_s
                dur = len(self._utt) * self.frame_s
                if self._silence >= self.end_silence_s or dur >= self.max_utt_s:
                    audio = np.concatenate(self._utt)
                    self._utt = None
                    self._silence = 0.0
                    if dur - self.end_silence_s >= self.min_utt_s:
                        out.append(audio)
        return out
