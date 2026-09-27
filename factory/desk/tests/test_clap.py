"""박수 감지 시험 — 합성 소리로. 막아야 할 소리(말 · 쿵 · 문 두드림 · 음악 박자)를 더 많이 둡니다."""
import os
import sys
import unittest

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from desk.clap import ClapDetector  # noqa: E402

SR = 16000
rng = np.random.default_rng(7)


def silence(sec, level=0.002):
    return (rng.standard_normal(int(SR * sec)) * level).astype(np.float32)


def clap(amp=0.5, tau=0.012, dur=0.08):
    n = int(SR * dur)
    env = np.exp(-np.arange(n) / (SR * tau))
    return (rng.standard_normal(n) * env * amp).astype(np.float32)


def lowpass(x, k=40):
    return np.convolve(x, np.ones(k) / k, mode="same").astype(np.float32)


def thump(amp=0.6, tau=0.06, dur=0.25):
    """문 닫는 쿵 — 낮은 소리"""
    n = int(SR * dur)
    env = np.exp(-np.arange(n) / (SR * tau))
    return lowpass(rng.standard_normal(n) * env * amp * 6, 60)


def syllable(f0=140, dur=0.22, amp=0.3):
    """모음 같은 소리 — 배음 · 천천히 커지고 작아짐"""
    t = np.arange(int(SR * dur)) / SR
    env = np.sin(np.pi * t / dur) ** 0.7
    sig = sum((1 / k) * np.sin(2 * np.pi * f0 * k * t) for k in range(1, 12))
    return (sig * env * amp / 2).astype(np.float32)


def speech(n=6):
    parts = []
    for _ in range(n):
        parts += [syllable(f0=rng.uniform(110, 220), dur=rng.uniform(0.15, 0.3)), silence(rng.uniform(0.03, 0.12))]
    return np.concatenate(parts)


def run(sig, cfg=None):
    d = ClapDetector(cfg)
    out = []
    for i in range(0, len(sig), 480):          # 30ms 조각으로 흘려 넣기(실제 마이크와 같게)
        out += d.feed(sig[i:i + 480])
    return out


def seq(*parts):
    return np.concatenate([silence(1.0), *parts, silence(1.5)])


class ClapTest(unittest.TestCase):
    def test_double_clap(self):
        self.assertEqual(run(seq(clap(), silence(0.3), clap())), [2])

    def test_double_clap_fast_and_slow(self):
        self.assertEqual(run(seq(clap(), silence(0.15), clap())), [2])
        self.assertEqual(run(seq(clap(), silence(0.6), clap())), [2])

    def test_single_clap(self):
        self.assertEqual(run(seq(clap())), [1])

    def test_triple_clap(self):
        self.assertEqual(run(seq(clap(), silence(0.3), clap(), silence(0.3), clap())), [3])

    def test_two_claps_far_apart_are_two_bursts(self):
        self.assertEqual(run(seq(clap(), silence(1.6), clap())), [1, 1])

    def test_quieter_claps_across_room(self):
        self.assertEqual(run(seq(clap(amp=0.12), silence(0.35), clap(amp=0.12))), [2])

    def test_speech_is_not_clap(self):
        self.assertEqual(run(seq(speech(10))), [])

    def test_thumps_are_not_claps(self):
        self.assertEqual(run(seq(thump(), silence(0.3), thump())), [])

    def test_clap_talk_clap_is_invalid(self):
        self.assertEqual(run(seq(clap(), silence(0.05), syllable(dur=0.25), silence(0.1), clap())), [])

    def test_clap_right_after_talking_does_not_start(self):
        self.assertNotIn(2, run(seq(speech(4), clap(), silence(0.3), clap())))

    def test_long_noise_burst_is_not_clap(self):
        # 치익 — 높은 소리지만 길다 (스프레이 · 바람)
        hiss = (rng.standard_normal(int(SR * 0.4)) * 0.3).astype(np.float32)
        self.assertEqual(run(seq(hiss, silence(0.3), hiss)), [])

    def test_steady_beat_music_is_not_double(self):
        # 일정한 박자의 높은 소리가 계속 — 묶음이 길게 이어지므로 2 가 아님
        beat = []
        for _ in range(8):
            beat += [clap(amp=0.3), silence(0.35)]
        self.assertNotIn(2, run(seq(*beat)))


if __name__ == "__main__":
    unittest.main()
