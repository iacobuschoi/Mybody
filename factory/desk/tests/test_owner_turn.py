"""주인이 말하는 동안 비서는 말을 시작하지 않음 · 말하는 중 왼손 주먹을 쥐면 바로 멈춤 (주인 10월 2일 15:34 · 15:37)."""
import os
import sys
import threading
import time
import unittest

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from desk import mac  # noqa: E402
from tests.test_daemon import CALLS, feed, make  # noqa: E402
from tests.test_talk import SR, tone  # noqa: E402

RealVoice = mac.Voice                                   # make() 가 가짜로 바꾸기 전


class FakeProc:
    started: list = []

    def __init__(self, cmd, **k):
        FakeProc.started.append(cmd[-1])
        self.done = threading.Event()

    def poll(self):
        return 0 if self.done.is_set() else None

    def wait(self):
        self.done.wait(2)

    def terminate(self):
        self.done.set()


class VoiceWaitsForOwner(unittest.TestCase):
    def setUp(self):
        FakeProc.started = []
        self.old = mac.subprocess.Popen
        mac.subprocess.Popen = FakeProc
        self.v = RealVoice("")
        self.talking = True
        self.v.hold = lambda: self.talking

    def tearDown(self):
        self.v.stop()
        mac.subprocess.Popen = self.old

    def test_waits_until_owner_is_quiet(self):
        self.v.say("답이에요")
        time.sleep(0.2)
        self.assertEqual(FakeProc.started, [])          # 주인이 말하는 중 — 아직 안 말함
        self.assertTrue(self.v.busy())                  # 밀린 말 · 브리핑이 끼어들지 않게
        self.assertFalse(self.v.sounding())             # 귀는 열어 둠(주인 말을 계속 들어야)
        self.talking = False
        time.sleep(0.2)
        self.assertEqual(FakeProc.started, ["답이에요"])

    def test_stop_drops_waiting_speech(self):
        self.v.say("버릴 말")
        time.sleep(0.1)
        self.v.stop()
        self.talking = False
        time.sleep(0.25)
        self.assertFalse(self.v.busy())
        self.assertEqual(FakeProc.started, [])

    def test_quiet_owner_speaks_at_once(self):
        self.talking = False
        self.v.say("바로")
        self.assertEqual(FakeProc.started, ["바로"])

    def test_gives_up_waiting_after_max(self):
        self.v.hold_max_s = 0.2
        self.v.say("잡음이 길어도")
        time.sleep(0.4)
        self.assertEqual(FakeProc.started, ["잡음이 길어도"])


class DaemonOwnerTurn(unittest.TestCase):
    def setUp(self):
        self.d = make()
        self.d.wake("test")
        time.sleep(0.1)
        CALLS.clear()

    def test_owner_talking_from_fist_and_open_mic(self):
        d = self.d
        self.assertIs(d.voice.hold.__func__, type(d)._owner_talking)
        feed(d, np.zeros(SR, np.float32))
        self.assertFalse(d._owner_talking())
        feed(d, tone(1.0))                              # 상시 듣기에 주인 목소리
        self.assertTrue(d._owner_talking())
        feed(d, np.zeros(int(SR * (d.seg.end_silence_s + 0.1)), np.float32))
        self.assertFalse(d._owner_talking())            # 말 끝 침묵이 지남 — 이제 말해도 됨
        d.talk("start")
        self.assertTrue(d._owner_talking())             # 주먹을 쥐고 있는 동안
        d.talk("cancel")
        self.assertFalse(d._owner_talking())

    def test_fist_stops_speech_and_answer_in_progress(self):
        d = self.d
        d.voice.busy = lambda: True
        d.brain.busy = lambda: True
        d.brain_q.put(("밀린 말", d._turn, True))
        turn = d._turn
        self.assertEqual(d.talk("start"), "ok")
        self.assertIn("voice.stop", CALLS)
        self.assertIn("brain.cancel", CALLS)            # 만드는 답도 끊음("잠깐" 과 같음)
        self.assertTrue(d.brain_q.empty())
        self.assertEqual(d._turn, turn + 1)             # 끊기 전에 받은 말의 답은 오더라도 버림
        self.assertTrue(d.ptt.active)                   # 이어서 주먹 녹음

    def test_fist_when_idle_does_not_cut(self):
        d = self.d
        turn = d._turn
        d.talk("start")
        self.assertEqual(d._turn, turn)
        self.assertNotIn("brain.cancel", CALLS)


if __name__ == "__main__":
    unittest.main()
