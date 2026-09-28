"""끼어들기 — 비서가 말하는 도중에 주인이 "잠깐" · "멈춰" · "그만" 하면 말하기만 멈춥니다.

아무 말에나 멈추지는 않습니다 — 옆 사람과 이야기할 수 있으니 **멈춤 말**(설정 [bargein] stop_words)만 봅니다.
멈추는 건 스피커 말하기뿐입니다. 진행 중인 Claude 호출 · 명령 · 백그라운드 작업은 그대로 둡니다.

스피커 소리가 마이크로 되돌아오므로(에코) 그냥 받아쓰면 제 목소리를 듣습니다. 그래서 두 겹으로 거릅니다.
  1. 크기: 말하는 동안 마이크에 들어오는 말소리 대역(150~4000Hz) 크기의 상위 10%(= 되먹임 기준)를 계속 배우고,
     그보다 margin_db 이상 큰 소리가 0.3초 안에 min_s 이상 있을 때만 "누가 끼어들었나?" 하고 들어 봅니다
     (말은 음절마다 끊기므로 이어진 길이가 아니라 합으로 셈). 그렇게 잡힌 소리는 되먹임 기준에 넣지 않습니다.
     말 시작 grace_s 동안은 기준만 배웁니다(스피커가 막 켜질 때의 소리로 멈추지 않게).
  2. 말: 그 앞뒤 2초를 받아써서(stt.hear) 멈춤 말이 있고, **그 낱말이 지금 비서가 하는 말 안에는 없을 때만** 멈춥니다
     (되먹임이 같이 받아써져도 비서 자신의 말로는 멈추지 않게). 말 시작부터 멈추기까지 2초 안팎.

반향 제거(에코 캔슬러)는 두지 않았습니다 — 맥 미니 스피커(음량 51) → Brio 되먹임이 말소리 대역에서 방 바닥 소음보다
평균 4~6dB 크기라, 이상적인 선형 필터로도 바닥까지밖에 안 내려가고 적응 필터는 오히려 잡음을 키웠습니다.
방 녹음(스피커 소리 11초)에 사람 목소리 "멈춰 · 잠깐만 · 그만" 을 섞은 시험: 24번 중 22번 멈춤, 되먹임만으로는 0번.
"""
from __future__ import annotations

from collections import deque

import numpy as np

from .router import LOCAL_MAX_CHARS, normalize, route

STOP_WORDS = ["잠깐", "멈춰", "그만", "스톱", "스탑"]


def has_stop_word(text: str, words: list[str], spoken: str = "") -> bool:
    """받아쓴 글에 멈춤 말이 있나. spoken(비서가 하던 말)에 이미 있는 낱말은 되먹임일 수 있어 안 셈."""
    n, s = normalize(text), normalize(spoken)
    return any(w and normalize(w) in n and normalize(w) not in s for w in words)


def is_stop_utterance(text: str, words: list[str]) -> bool:
    """들은 한 마디가 멈춤 말뿐인가("잠깐만", "그만해"). "그만 들어"(조용히) · "화면 꺼"(자기)는 제 명령으로."""
    n = normalize(text)
    if not n or len(n) > LOCAL_MAX_CHARS or not has_stop_word(text, words):
        return False
    return route(text).kind not in ("mute", "sleep", "unmute")


class Listener:
    """말하는 동안 마이크 소리를 받아 "받아써 볼 만한 소리가 들렸다" 를 알려 줍니다.

    feed(x, speaking) → 받아써 볼 소리(np.ndarray) 또는 None. 말하지 않을 때도 넣어 방의 바닥 소음을 배웁니다.
    """

    def __init__(self, sr: int = 16000, frame_ms: int = 30, margin_db: float = 3.0, min_s: float = 0.12,
                 grace_s: float = 0.3, listen_s: float = 0.9, window_s: float = 2.0,
                 band: tuple[float, float] = (150.0, 4000.0)):
        self.n = int(sr * frame_ms / 1000)
        fs = frame_ms / 1000
        self.k = 10 ** (margin_db / 20)
        self.min_frames = max(1, round(min_s / fs))
        self.grace_frames = round(grace_s / fs)
        self.listen_frames = max(1, round(listen_s / fs))   # 큰 소리가 시작된 뒤 이만큼 더 듣고 받아씀(멈춤 말 끝까지)
        self._win = np.hanning(self.n)
        freqs = np.fft.rfftfreq(self.n, 1.0 / sr)
        self._band = (freqs >= band[0]) & (freqs <= band[1])
        self._norm = 2.0 / (self.n * float((self._win ** 2).sum()))
        self._buf = np.zeros(0, dtype=np.float32)
        self._audio: deque[np.ndarray] = deque(maxlen=max(1, round(window_s / fs)))
        self._floor: deque[float] = deque(maxlen=round(3.0 / fs))      # 말하지 않을 때 방 소리
        self._echo: deque[float] = deque(maxlen=round(4.0 / fs))       # 말하는 동안 되먹임 — 다음 말에도 이어서 씀
        self._spoke = 0              # 이번 말하기에서 지난 칸 수
        self._recent: deque[bool] = deque(maxlen=round(0.3 / fs))   # 최근 칸들이 기준보다 컸나
        self._hold: list[float] = []  # 기준보다 컸던 칸 — 사람 목소리로 잡히지 않으면 나중에 되먹임 기준에 넣음
        self._hot = False            # 지금 사람 목소리로 잡힌 중
        self._wait = -1              # 받아쓰기까지 남은 칸(-1 = 기다리는 중 아님)

    def _rms(self, f: np.ndarray) -> float:
        f = f - f.mean()
        spec = np.abs(np.fft.rfft(f * self._win)) ** 2
        return float(np.sqrt(spec[self._band].sum() * self._norm)) + 1e-9

    def ref(self) -> float:
        floor = float(np.median(self._floor)) if self._floor else 1e-5
        echo = float(np.percentile(self._echo, 90)) if len(self._echo) >= 10 else 0.0
        return max(floor, echo, 1e-5)

    def feed(self, x: np.ndarray, speaking: bool) -> np.ndarray | None:
        out = None
        self._buf = np.concatenate([self._buf, np.asarray(x, dtype=np.float32).reshape(-1)])
        while len(self._buf) >= self.n:
            f, self._buf = self._buf[: self.n], self._buf[self.n:]
            rms = self._rms(f)
            if not speaking:
                self._floor.append(rms)
                self._spoke = 0
                self._wait = -1
                self._audio.clear()
                self._recent.clear()
                self._hold.clear()
                self._hot = False
                continue
            self._audio.append(f)
            self._spoke += 1
            loud = self._spoke > self.grace_frames and rms > self.ref() * self.k
            self._recent.append(loud)
            (self._hold if loud else self._echo).append(rms)
            if sum(self._recent) >= self.min_frames:
                self._hot = True
                self._hold.clear()                           # 사람 목소리 — 되먹임 기준에 안 넣음
                if self._wait < 0:
                    self._wait = self.listen_frames
            elif not any(self._recent):
                if not self._hot:
                    self._echo.extend(self._hold)            # 잠깐 튄 제 목소리였음
                self._hold.clear()
                self._hot = False
            if self._wait > 0:
                self._wait -= 1
            if self._wait == 0:
                self._wait = -1
                out = np.concatenate(self._audio)
        return out
