"""끼어들기 시험 — 말하는 동안 되먹임만으로는 안 멈추고, 멈춤 말에만 말하기(작업 말고)가 멈추는지."""
import os
import sys
import unittest

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from desk.bargein import Listener, has_stop_word, is_stop_utterance, STOP_WORDS  # noqa: E402
from tests import test_daemon  # noqa: E402
from tests.test_daemon import CALLS, make  # noqa: E402

SR = 16000
rng = np.random.default_rng(0)


def speechlike(s: float, amp: float) -> np.ndarray:
    """음절처럼 4Hz 로 커졌다 작아지는 말소리 대역 소리"""
    t = np.arange(int(SR * s)) / SR
    env = 0.55 + 0.45 * np.sin(2 * np.pi * 4 * t)
    return (amp * env * (np.sin(2 * np.pi * 300 * t) + 0.5 * np.sin(2 * np.pi * 1200 * t))
            + 0.002 * rng.standard_normal(len(t))).astype(np.float32)


def run(li: Listener, sig: np.ndarray, speaking: bool = True) -> list[np.ndarray]:
    return [a for i in range(0, len(sig), 480) if (a := li.feed(sig[i:i + 480], speaking)) is not None]


class Words(unittest.TestCase):
    def test_stop_words(self):
        self.assertTrue(has_stop_word("잠깐만요", STOP_WORDS))
        self.assertTrue(has_stop_word("오늘 일정은 세 건이에요 멈춰", STOP_WORDS, spoken="오늘 일정은 세 건이에요"))
        self.assertFalse(has_stop_word("그만큼 중요해요", STOP_WORDS, spoken="그만큼 중요해요"))   # 제 말의 되먹임
        self.assertFalse(has_stop_word("내일 일정 알려 줘", STOP_WORDS))

    def test_stop_utterance(self):
        for t in ["잠깐", "잠깐만", "멈춰", "그만해", "스톱"]:
            self.assertTrue(is_stop_utterance(t, STOP_WORDS), t)
        for t in ["그만 들어", "잠깐 듣지 마", "잠깐 화면 꺼 줘", "잠깐 내일 가계부 앱 시험 돌리고 결과 알려 줘"]:
            self.assertFalse(is_stop_utterance(t, STOP_WORDS), t)
        self.assertFalse(is_stop_utterance("잠깐", ["멈춰"]))            # 설정으로 바꾼 목록을 따름


class Listen(unittest.TestCase):
    def test_echo_alone_does_not_trigger(self):
        li = Listener()
        run(li, speechlike(2.0, 0.001), speaking=False)                  # 조용한 방
        self.assertEqual(run(li, speechlike(6.0, 0.05)), [])              # 제 목소리 되먹임만

    def test_louder_voice_over_echo_is_checked(self):
        li = Listener()
        run(li, speechlike(2.0, 0.001), speaking=False)
        run(li, speechlike(2.0, 0.05))
        got = run(li, speechlike(0.6, 0.05) + speechlike(0.6, 0.2) * 1.0)
        got += run(li, speechlike(1.0, 0.05))
        self.assertTrue(got)
        self.assertLessEqual(len(got[0]), int(SR * 2.0) + 480)

    def test_silence_between_speeches_resets(self):
        li = Listener()
        run(li, speechlike(1.0, 0.05))
        run(li, speechlike(0.5, 0.001), speaking=False)
        self.assertEqual(li._spoke, 0)


class BusyVoice(test_daemon.FakeVoice):
    speaking = True

    def busy(self):
        return self.speaking

    def stop(self):
        CALLS.append("voice.stop")
        self.speaking = False


class DaemonStop(unittest.TestCase):
    def setUp(self):
        self.d = make()
        self.d.wake("test")
        self.d.voice = BusyVoice()

    def test_stop_word_while_speaking_stops_speech_only(self):
        self.d.handle("잠깐만")
        self.assertIn("voice.stop", CALLS)
        self.assertNotIn("brain.cancel", CALLS)                            # Claude 작업은 계속
        self.assertTrue(self.d.brain_q.empty())                            # 명령으로 안 넘어감
        CALLS.clear()
        self.d.handle("멈춰")                                               # 끊은 직후 또 들림 — 조용히 버림
        self.assertEqual(CALLS, [])

    def test_other_words_do_not_stop(self):
        self.d.handle("그만 들어")
        self.assertEqual(self.d.mode, "muted")

    def test_stop_when_silent_still_cancels(self):
        self.d.voice.speaking = False
        self.d.handle("멈춰")
        self.assertIn("brain.cancel", CALLS)

    def test_probe(self):
        class STT:
            text = ""

            def hear(self, a):
                return self.text
        self.d.stt = STT()
        self.d.stt.text = "오늘 할 일은 세 건이에요"                              # 되먹임만
        self.d._probe(np.zeros(100, np.float32), "오늘 할 일은 세 건이에요")
        self.assertNotIn("voice.stop", CALLS)
        self.d.stt.text = "오늘 할 일은 그만"
        self.d._probe(np.zeros(100, np.float32), "오늘 할 일은 세 건이에요")
        self.assertIn("voice.stop", CALLS)
        self.assertNotIn("brain.cancel", CALLS)


if __name__ == "__main__":
    unittest.main()
