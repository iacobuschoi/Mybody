"""말소리 구간 자르기 — 상시 듣기에서 "한 마디" 를 잘라 받아쓰기에 넘긴다.

크기는 **말소리 대역(150~4000Hz)** 에서 재서 바닥 소음(최근 3초의 중앙값)보다 energy_db 이상 크면 말로 봅니다.
전체 크기로 재면 마이크의 직류(DC) · 전기 험(50/60Hz)이 바닥을 부풀려 침대에서 한 말이 안 잡힙니다
(Brio 100, 2.5m: 전체 크기로는 바닥의 1.1배, 대역으로는 3~6배).
webrtcvad 는 level 0~3 을 주면 같이 봅니다(둘 다 맞아야 말). 기본은 끔 — 같은 녹음에서 말한 칸의 14~40% 만
말이라고 해서 한 마디도 못 잘랐습니다. 선풍기처럼 꾸준한 소리는 바닥이 따라 올라가 걸러집니다.
말하는 중(스피커로 우리 목소리가 나가는 중)에는 pause() 로 귀를 닫습니다. 안 그러면 제 목소리를 명령으로 듣습니다.

말 끝 기다리기(hold_silence_s > end_silence_s 일 때): end_silence_s 만큼 조용하면 그때까지를 "잠정" 조각으로 먼저
내보내되 구간은 닫지 않습니다. 받아쓴 끝이 끝난 말이면 데몬이 commit() 으로 닫고, 조사 · 접속사로 끝나면 그대로
두어 hold_silence_s 까지 기다립니다 — 그 사이 말이 이어지면 한 구간으로 붙습니다.
"""
from __future__ import annotations

import threading
from collections import deque
from dataclasses import dataclass

import numpy as np


@dataclass
class Cut:
    """잘린 조각. final=False 면 잠정(구간은 아직 열려 있음) — seq · frames 로 commit() 에 되돌려 줌"""
    audio: np.ndarray
    final: bool
    seq: int
    frames: int
    t0: float = 0.0     # 벽시계 — 말 시작 · 조각이 나온 때 (deskd 가 찍음, 주먹 쥐고 말하기에 씀)
    t1: float = 0.0
    voiced: int = 0     # 앞에서부터 마지막 말소리 칸까지의 칸 수 — 잠정 조각 뒤로 말이 더 있었는지 봄
    tail_s: float = 0.0  # 조각이 나올 때까지 기다린 끝 침묵(초)
    direct: bool = False  # 왼손 주먹을 쥐고 한 말(desk/talk.py) — 비서에게 한 말이 확실함


class Segmenter:
    def __init__(self, sr: int = 16000, frame_ms: int = 30, level: int = -1, start_ratio: float = 0.6,
                 end_silence_s: float = 0.8, min_utt_s: float = 0.4, max_utt_s: float = 20.0,
                 preroll_s: float = 0.3, energy_db: float = 6.0, band: tuple[float, float] = (150.0, 4000.0),
                 hold_silence_s: float = 0.0, min_level: float = 1e-5, on_drop=None):
        self.sr, self.n = sr, int(sr * frame_ms / 1000)
        self.min_level = min_level      # 바닥 소음을 이보다 낮게 보지 않음 — 스피커폰은 조용하면 잡음 제거로 거의 0 을 보내
                                        # 아주 작은 소리도 "바닥보다 6dB" 가 되어 빈 구간을 받아쓰고 환각이 남(10월 2일)
        self.frame_s = frame_ms / 1000
        self.start_ratio, self.end_silence_s = start_ratio, end_silence_s
        self.hold_silence_s = max(hold_silence_s, end_silence_s)   # 같으면 잠정 조각 없이 예전처럼
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
        self._seq = 0                              # 구간마다 +1
        self._offered = False                      # 이번 침묵에서 잠정 조각을 이미 냈는지
        self._voiced_at = 0                        # 구간에서 마지막으로 말소리가 난 칸
        self._lock = threading.Lock()              # feed(소리 스레드) 와 commit(받아쓰기 스레드)
        self._peak = 0.0                           # 구간에서 가장 큰 말소리 대역 크기(로그용)
        self._last_rms = 0.0
        self.on_drop = on_drop                     # 짧아서 버린 구간을 알림(말한 초, 가장 큰 크기) — 데몬이 로그에 남김

    @property
    def holding(self) -> bool:
        return self.hold_silence_s > self.end_silence_s

    def pause(self) -> None:
        self._paused = True
        self.reset()

    def resume(self) -> None:
        self._paused = False

    def reset(self) -> None:
        with self._lock:
            self._buf = np.zeros(0, dtype=np.float32)
            self._ring.clear()
            self._utt = None
            self._silence = 0.0
            self._offered = False

    def commit(self, seq: int, frames: int) -> None:
        """잠정 조각(seq, 앞 frames 칸)을 끝난 말로 확정 — 그만큼 구간에서 떼어 냄.
        그 뒤로 말이 이어졌으면 남은 칸이 새 구간이 되고, 조용하기만 했으면 구간을 닫음."""
        with self._lock:
            if self._utt is None or seq != self._seq:
                return
            if self._voiced_at < frames:           # 잠정 뒤로 조용하기만 함
                self._utt = None
                self._silence, self._offered = 0.0, False
                return
            self._utt = self._utt[frames:]         # 뒤이어 한 말은 새 구간
            self._voiced_at -= frames
            self._seq += 1
            self._offered = False                  # 그 말도 지금 침묵에서 잠정 조각으로 다시 낼 수 있게(옛 구간 번호로 낸 건 버려짐)

    def flush(self) -> Cut | None:
        """열린 구간을 지금까지로 끝냄(말하기가 시작돼 귀를 닫기 직전) — 충분히 길면 확정 조각으로, 아니면 버림"""
        with self._lock:
            if self._utt is None:
                return None
            spoken = len(self._utt) * self.frame_s - self._silence
            n, audio, seq = len(self._utt), np.concatenate(self._utt), self._seq
            self._utt = None
            self._silence, self._offered = 0.0, False
            if spoken >= self.min_utt_s:
                return Cut(audio, True, seq, n, voiced=self._voiced_at + 1, tail_s=0.0)
            if self.on_drop:
                self.on_drop(spoken, self._peak)
            return None

    def take(self) -> np.ndarray | None:
        """열린 구간의 소리를 가져가고 구간을 버림(받아쓰기로 넘기지 않음)"""
        with self._lock:
            if self._utt is None:
                return None
            audio = np.concatenate(self._utt)
            self._utt = None
            self._silence, self._offered = 0.0, False
            return audio

    @property
    def seq(self) -> int:
        return self._seq

    @property
    def in_speech(self) -> bool:
        return self._utt is not None

    @property
    def talking(self) -> bool:
        """지금 말하는 중 — 구간이 열려 있고 말 끝 침묵(end_silence_s)에 아직 못 미침. 조사로 끝나 더 기다리는 동안은 아님"""
        return self._utt is not None and not self._paused and self._silence < self.end_silence_s

    def _is_speech(self, f: np.ndarray) -> bool:
        f = f - f.mean()                                   # 직류(DC) 빼기
        spec = np.abs(np.fft.rfft(f * self._win)) ** 2
        rms = float(np.sqrt(spec[self._band].sum() * self._norm)) + 1e-9
        self._last_rms = rms
        floor = max(float(np.median(self._floor)) if self._floor else rms, self.min_level)
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
        """끝난 말만 (예전 방식). 잠정 조각까지 받으려면 feed_cuts"""
        return [c.audio for c in self.feed_cuts(x) if c.final]

    def feed_cuts(self, x: np.ndarray) -> list[Cut]:
        with self._lock:
            return self._feed(x)

    def _feed(self, x: np.ndarray) -> list[Cut]:
        out: list[Cut] = []
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
                    self._offered = False
                    self._voiced_at = len(self._utt) - 1
                    self._seq += 1
                    self._peak = self._last_rms
            else:
                self._utt.append(f)
                self._peak = max(self._peak, self._last_rms)
                if sp:
                    self._silence, self._offered = 0.0, False
                    self._voiced_at = len(self._utt) - 1
                else:
                    self._silence += self.frame_s
                dur = len(self._utt) * self.frame_s
                spoken = dur - self._silence            # 말한 길이(끝 침묵 뺌)
                if self._silence >= self.hold_silence_s or dur >= self.max_utt_s:
                    audio = np.concatenate(self._utt)
                    n, tail = len(self._utt), self._silence
                    self._utt = None
                    self._silence, self._offered = 0.0, False
                    if spoken >= self.min_utt_s:
                        out.append(Cut(audio, True, self._seq, n, voiced=self._voiced_at + 1, tail_s=tail))
                    elif self.on_drop:
                        self.on_drop(spoken, self._peak)
                elif self.holding and not self._offered and self._silence >= self.end_silence_s:
                    self._offered = True
                    if spoken >= self.min_utt_s:
                        out.append(Cut(np.concatenate(self._utt), False, self._seq, len(self._utt),
                                       voiced=self._voiced_at + 1, tail_s=self._silence))
        return out
