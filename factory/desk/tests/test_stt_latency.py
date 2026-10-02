"""받아쓰기 지연 — 주먹 말 먼저 · 묵은 잠정 조각 건너뜀 · 되풀이 끊기 · 상시 듣기는 다시 받아쓰지 않음(10월 2일 23:51 주인 지시)."""
import os
import sys
import unittest

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from desk.stt import WhisperSTT, clean_transcript, repeating  # noqa: E402
from desk.vad import Cut  # noqa: E402
from tests.test_daemon import make  # noqa: E402

SR = 16000


def cut(sec, final, seq, direct=False):
    return Cut(np.zeros(int(sec * SR), np.float32), final, seq, int(sec / 0.03), direct=direct)


class NextCut(unittest.TestCase):
    def setUp(self):
        self.d = make()

    def put(self, *cuts):
        for c in cuts:
            self.d.utt_q.put_nowait(c)

    def order(self):
        out = []
        while (c := self.d._next_cut(block=False)) is not None:
            out.append((c.seq, c.final, c.direct, round(len(c.audio) / SR, 1)))
        return out

    def test_fist_first(self):
        self.put(cut(2, True, 5), cut(3, False, 6), cut(4, True, -1, direct=True))
        self.assertEqual(self.order()[0], (-1, True, True, 4.0))

    def test_stale_tentative_skipped(self):
        # 23:43 — 한 구간(seq 7)의 잠정 조각이 1.2 · 2.4 · 3.1초로 자라는 중, 마지막만 받아씀
        self.put(cut(1.2, False, 7), cut(2.4, False, 7), cut(3.1, False, 7), cut(2.0, False, 8))
        self.assertEqual(self.order(), [(7, False, False, 3.1), (8, False, False, 2.0)])

    def test_tentative_before_final_of_same_utterance_skipped(self):
        self.put(cut(1.2, False, 9), cut(3.0, True, 9))
        self.assertEqual(self.order(), [(9, True, False, 3.0)])

    def test_overflow_drops_oldest_listening_cut_not_fist(self):
        self.put(cut(1, True, -1, direct=True))
        for s in range(7):
            self.put(cut(1, True, 10 + s))
        self.d._pending = [cut(1, True, 20 + s) for s in range(6)]
        got = self.order()
        self.assertEqual(len(got), 12)
        self.assertEqual(got[0][2], True)
        self.assertNotIn(20, [g[0] for g in got])
        self.assertNotIn(21, [g[0] for g in got])


def seg(text, lp=-0.1, ns=0.01, cr=1.0):
    return {"text": text, "segments": [{"text": text, "avg_logprob": lp, "no_speech_prob": ns, "compression_ratio": cr}]}


class Retry(unittest.TestCase):
    """다시 받아쓰기(0.2 · 0.4)는 주먹 말만 — 상시 듣기는 0.0 한 번"""

    def calls(self, direct):
        s = WhisperSTT("large")
        got = []
        s._run = lambda model, audio, temperature: got.append(temperature) or seg("화면 꺼 줘", lp=-1.3)
        s.transcribe(np.zeros(SR, np.float32), direct=direct)
        return got

    def test_listening_once(self):
        self.assertEqual(self.calls(False), [0.0])

    def test_fist_keeps_fallback(self):
        self.assertEqual(self.calls(True), [(0.0, 0.2, 0.4)])


class Loops(unittest.TestCase):
    def test_repeating(self):
        self.assertTrue(repeating([9, 1, 2, 1, 2, 1, 2, 1, 2, 1, 2]))
        self.assertTrue(repeating([5] * 5))
        self.assertFalse(repeating([1, 2] * 4))
        self.assertFalse(repeating([1, 2, 3, 4, 5, 6, 7]))

    def test_stopped_loop_text_is_dropped_anyway(self):
        # 되풀이를 5번에서 끊어도 clean_transcript 가 버리는 꼴 — 끊어서 잃는 말 없음
        for unit in ("아, ", "뱃속, ", "마이퍼를 연결하고, ", "다이얼을 사용하고, 마이퍼를 "):
            self.assertEqual(clean_transcript("터미널, " + unit * 5), "")


if __name__ == "__main__":
    unittest.main()
