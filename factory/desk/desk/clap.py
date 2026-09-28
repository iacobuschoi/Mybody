"""박수 감지 — 마이크 입력에서 "짝짝" 묶음을 찾는다.

박수와 다른 소리를 가르는 네 가지:
  1. 갑자기 커진다   — 바닥 소음보다 rise_db 이상, 바로 앞 10ms 보다 4배 이상 (말은 20~50ms 에 걸쳐 커짐)
  2. 금방 사라진다   — max_len_s 안에 최고점의 25% 아래로 (말의 음절은 150ms 넘게 이어짐)
  3. 소리가 높다     — 스펙트럼 무게중심이 min_centroid_hz 이상 (문 닫는 쿵 · 발소리는 낮음)
  4. 앞뒤가 조용하다 — 묶음 앞 quiet_before_s 와 박수 사이에 다른 큰 소리가 없음 ("짝 (말) 짝" 은 무효)

묶음: 박수 사이 간격이 min_gap_s ~ max_gap_s 이면 같은 묶음. 마지막 박수 뒤 burst_end_s 동안 조용하면
묶음이 끝나고 박수 수를 돌려준다. 몇 번이 "켜기" 인지는 부르는 쪽(데몬)이 정한다(밤에는 3번 등).

크기는 칸마다 평균(직류, DC)을 빼고 잽니다. Brio 100 은 +0.008 쯤 섞여 나와, 안 빼면 바닥 소음이 두 배로
부풀어 침대에서 치는 약한 두 번째 박수가 문턱에 못 미칩니다.

숫자는 방마다 다릅니다 — `python -m desk calibrate` 로 실제 박수의 값을 보고 config 에서 조정합니다.
"""
from __future__ import annotations

from collections import deque
from dataclasses import dataclass

import numpy as np


@dataclass
class ClapConfig:
    sr: int = 16000
    hop_s: float = 0.01
    rise_db: float = 18.0          # 바닥 소음보다 이만큼 커야
    abs_min: float = 0.02          # 이것보다 작은 소리는 무시 (RMS, 전체 크기 1.0 기준)
    attack_ratio: float = 4.0      # 바로 앞 두 칸 중 작은 것보다 이 배수 이상
    min_centroid_hz: float = 1500.0
    max_len_s: float = 0.12        # 이 안에 25% 아래로 떨어져야 박수
    decay_ratio: float = 0.25
    min_gap_s: float = 0.12        # 이보다 가까우면 같은 박수의 울림
    max_gap_s: float = 0.8         # 이보다 멀면 다른 묶음
    quiet_before_s: float = 0.3    # 첫 박수 앞은 조용해야
    ring_s: float = 0.15           # 박수 뒤 이 시간까지의 큰 소리는 울림으로 봄
    burst_end_s: float = 0.8       # 마지막 박수 뒤 이만큼 조용하면 묶음 끝
    floor_s: float = 3.0           # 바닥 소음 추정 창


class ClapDetector:
    def __init__(self, cfg: ClapConfig | None = None):
        self.cfg = c = cfg or ClapConfig()
        self.hop = max(1, int(round(c.sr * c.hop_s)))
        self._buf = np.zeros(0, dtype=np.float32)
        self._t = 0.0
        self._hist: deque[float] = deque(maxlen=max(10, int(c.floor_s / c.hop_s)))
        self._prev: deque[float] = deque([0.0, 0.0], maxlen=2)
        self._cand: tuple[float, float, int] | None = None   # (시작 시각, 최고 RMS, 지난 칸 수)
        self._burst: list[float] = []
        self._tainted = False
        self._last_loud = -1e9
        self._win = np.hanning(self.hop).astype(np.float32)
        self._freqs = np.fft.rfftfreq(self.hop, 1.0 / c.sr)
        self.last_frame: dict | None = None                    # calibrate 용

    # ── 바깥에서 부르는 것 ─────────────────────────────────────────────────
    def feed(self, x: np.ndarray) -> list[int]:
        """오디오 조각(float32 mono, -1~1)을 넣고, 이번 조각에서 끝난 묶음의 박수 수를 돌려준다."""
        out: list[int] = []
        self._buf = np.concatenate([self._buf, np.asarray(x, dtype=np.float32).reshape(-1)])
        while len(self._buf) >= self.hop:
            frame, self._buf = self._buf[: self.hop], self._buf[self.hop:]
            n = self._step(frame)
            if n:
                out.append(n)
            self._t += self.cfg.hop_s
        return out

    def reset(self) -> None:
        self._cand = None
        self._burst = []
        self._tainted = False

    # ── 한 칸(10ms) ──────────────────────────────────────────────────────
    def _centroid(self, frame: np.ndarray) -> float:
        spec = np.abs(np.fft.rfft(frame * self._win)) ** 2
        s = float(spec.sum())
        return float((self._freqs * spec).sum() / s) if s > 0 else 0.0

    def _step(self, frame: np.ndarray) -> int:
        c, t = self.cfg, self._t
        frame = frame - frame.mean()                       # 직류(DC) 빼기
        rms = float(np.sqrt(np.mean(frame.astype(np.float64) ** 2))) + 1e-9
        floor = max(float(np.median(self._hist)) if self._hist else rms, 1e-4)
        thr = max(floor * 10 ** (c.rise_db / 20), c.abs_min)
        emitted = 0

        if self._cand is not None:
            t0, peak, n = self._cand
            n += 1
            peak = max(peak, rms)
            if rms < peak * c.decay_ratio:
                self._on_clap(t0)
                self._cand = None
            elif n * c.hop_s > c.max_len_s:
                self._cand = None            # 오래 끄는 소리 — 박수 아님
                self._loud(t0)
            else:
                self._cand = (t0, peak, n)
            cen = None
        else:
            cen = None
            if rms > thr and rms > c.attack_ratio * min(self._prev):
                cen = self._centroid(frame)
                if cen >= c.min_centroid_hz:
                    self._cand = (t, rms, 0)
                else:
                    self._loud(t)
            elif rms > thr:
                self._loud(t)

        # 묶음 끝?
        if self._burst and self._cand is None and t - self._burst[-1] > c.burst_end_s:
            emitted = 0 if self._tainted else len(self._burst)
            self._burst = []
            self._tainted = False

        self._hist.append(rms)
        self._prev.append(rms)
        self.last_frame = {"t": t, "rms": rms, "floor": floor, "thr": thr, "centroid": cen}
        return emitted

    def _loud(self, t: float) -> None:
        """박수가 아닌 큰 소리. 묶음 도중(울림 시간 밖)이면 그 묶음은 무효."""
        if self._burst and t - self._burst[-1] > self.cfg.ring_s:
            self._tainted = True
        self._last_loud = t

    def _on_clap(self, t0: float) -> None:
        c = self.cfg
        if self._burst:
            gap = t0 - self._burst[-1]
            if gap < c.min_gap_s:
                return                         # 같은 박수의 울림
            if gap <= c.max_gap_s:
                self._burst.append(t0)
                return
            # 너무 멀면 앞 묶음은 _step 에서 이미 끝났어야 함 — 안전하게 새로 시작
            self._burst = []
            self._tainted = False
        if t0 - self._last_loud < c.quiet_before_s:
            return                             # 시끄러운 중에 난 소리 — 묶음을 시작하지 않음
        self._burst = [t0]
        self._tainted = False
