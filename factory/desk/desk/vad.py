"""말소리 구간 자르기 — 상시 듣기에서 "한 마디" 를 잘라 받아쓰기에 넘긴다.

크기는 **말소리 대역(150~4000Hz)** 에서 재서 바닥 소음(최근 3초의 중앙값)보다 energy_db 이상 크면 말로 봅니다.
전체 크기로 재면 마이크의 직류(DC) · 전기 험(50/60Hz)이 바닥을 부풀려 침대에서 한 말이 안 잡힙니다
(Brio 100, 2.5m: 전체 크기로는 바닥의 1.1배, 대역으로는 3~6배).
webrtcvad 는 level 0~3 을 주면 같이 봅니다(둘 다 맞아야 말). 기본은 끔 — 같은 녹음에서 말한 칸의 14~40% 만
말이라고 해서 한 마디도 못 잘랐습니다. 선풍기처럼 꾸준한 소리는 바닥이 따라 올라가 걸러집니다.
말하는 중(스피커로 우리 목소리가 나가는 중)에는 pause() 로 귀를 닫습니다. 안 그러면 제 목소리를 명령으로 듣습니다.
"""
from __future__ import annotations

from collections import deque

import numpy as np


class Segmenter:
    def __init__(self, sr: int = 16000, frame_ms: int = 30, level: int = -1, start_ratio: float = 0.6,
                 end_silence_s: float = 0.8, min_utt_s: float = 0.4, max_utt_s: float = 20.0,
                 preroll_s: float = 0.3, energy_db: float = 6.0, band: tuple[float, float] = (150.0, 4000.0)):
        self.sr, self.n = sr, int(sr * frame_ms / 1000)
        self.frame_s = frame_ms / 1000
        self.start_ratio, self.end_silence_s = start_ratio, end_silence_s
        self.min_utt_s, self.max_utt_s = min_utt_s, max_utt_s
        self.energy_k = 10 ** (energy_db / 20)
        self._win = np.hanning(self.n)
        freqs = np.fft.rfftfreq(self.n, 1.0 / sr)
        self._band = (freqs >= band[0]) & (freqs <= band[1])
        self._norm = 2.0 / (self.n * float((self._win ** 2).sum()))   # 대역 에너지 → RMS 눈금
        self._vad = None
        if level >= 0:
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
        f = f - f.mean()                                   # 직류(DC) 빼기
        spec = np.abs(np.fft.rfft(f * self._win)) ** 2
        rms = float(np.sqrt(spec[self._band].sum() * self._norm)) + 1e-9
        floor = max(float(np.median(self._floor)) if self._floor else rms, 1e-5)
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
