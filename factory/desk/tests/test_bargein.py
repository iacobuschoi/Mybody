"""끼어들기 시험 — 말하는 동안 되먹임만으로는 안 멈추고, 멈춤 말에 말하기 · 남은 답 · 밀린 말이 모두 멈추는지."""
import os
import sys
import threading
import time
import unittest

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from desk.bargein import Listener, has_stop_word, is_stop_utterance, only_stop_words, STOP_WORDS  # noqa: E402
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

    def test_only_stop_words(self):
        for t in ["잠깐", "잠깐만요", "멈춰 멈춰", "그만해", "스톱!", "아 잠깐만", "제발 그만"]:
            self.assertTrue(only_stop_words(t, STOP_WORDS), t)
        for t in ["잠깐 이것 좀 찾아 줘", "많이 멈춰", "그만 들어 봐", "오늘 날씨", ""]:
            self.assertFalse(only_stop_words(t, STOP_WORDS), t)

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

    def test_stop_word_while_speaking_drops_the_rest(self):
        self.d.handle("패치노트 띄워 줘")
        self.d.handle("패치노트 좀 내가 볼 수 있게 띄워 달라고")             # 말하는 동안 밀린 말 둘
        self.d.handle("잠깐만")
        self.assertIn("voice.stop", CALLS)
        self.assertIn("brain.cancel", CALLS)                               # 지금 만드는 답도 취소
        self.assertTrue(self.d.brain_q.empty())                            # 밀린 말도 버리고, 멈춤 말은 명령으로 안 넘어감
        self.d.voice.said.clear()
        self.d.handle("멈춰")                                               # 끊은 직후 또 들림 — 조용히 버림
        self.assertEqual(self.d.voice.said, [])
        self.assertTrue(self.d.brain_q.empty())

    def test_other_words_do_not_stop(self):
        self.d.handle("그만 들어")
        self.assertEqual(self.d.mode, "muted")

    def test_stop_when_silent_still_cancels(self):
        self.d.voice.speaking = False
        self.d.handle("멈춰")
        self.assertIn("brain.cancel", CALLS)

    def test_stop_only_never_goes_to_claude(self):
        self.d.voice.speaking = False
        self.d._barged_at = 0                                              # 끊은 지 오래 — 그래도
        for t in ["잠깐", "잠깐만", "멈춰", "그만해"]:
            self.d.handle(t)
        self.assertTrue(self.d.brain_q.empty())
        self.d.handle("잠깐 이것 좀 찾아 줘")                                # 멈춤 말만 한 게 아니면 그대로
        self.assertEqual(self.d.brain_q.get_nowait()[0], "잠깐 이것 좀 찾아 줘")

    def test_answer_in_flight_is_dropped(self):
        """멈추기 전에 시작한 Claude 턴 — 끝나서 돌아온 답도, 그 턴이 deskctl say 로 하는 말도 버림"""
        d = self.d
        d.voice.speaking = False
        d.voice.said.clear()
        started, release = threading.Event(), threading.Event()

        def ask(text, direct=False):
            started.set()
            d.remote_say("패치노트는 이렇습니다")                              # 턴 도중 말하기(끊기 전) — 말함
            release.wait(2)
            d.remote_say("그리고 이것도요")                                   # 끊은 뒤 — 버림
            return "패치노트를 띄웠어요.", "패치노트를 띄웠어요."
        d.brain.ask = ask
        d.brain_q.put(("패치노트 띄워 줘", d._turn, False))
        d.brain_q.put(("그다음 것도", d._turn, False))
        threading.Thread(target=d._brain_worker, daemon=True).start()
        self.assertTrue(started.wait(2))
        d.handle("멈춰")
        self.assertTrue(d.brain_q.empty())
        release.set()
        time.sleep(0.3)
        self.assertEqual(d.voice.said, ["패치노트는 이렇습니다"])
        self.assertIsNone(d._asking)
        d.remote_say("다음 일 끝났어요")                                      # 턴이 끝나면 다시 말함
        self.assertEqual(d.voice.said[-1], "다음 일 끝났어요")
        d._stop.set()
        d.brain_q.put(("끝", -1, False))                                        # 일꾼 스레드를 깨워 끝냄

    def test_brief_waiting_for_speech_is_dropped(self):
        d = self.d
        d.voice.said.clear()
        t = threading.Thread(target=d.say_brief)
        t.start()
        time.sleep(0.2)
        d.handle("그만")
        t.join(2)
        self.assertEqual(d.voice.said, [])

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
        self.assertIn("brain.cancel", CALLS)


if __name__ == "__main__":
    unittest.main()
