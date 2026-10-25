"""자리 비움 — 손 카메라에 주인이 몇 초째 안 보이면 주먹 없이 한 말도 [음성·자리비움] 으로 비서에게 (주인 10월 25일 11:49)."""
import os
import sys
import tempfile
import time
import unittest

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from desk import brain as brain_mod  # noqa: E402
from desk.away import Away  # noqa: E402
from tests.test_daemon import make  # noqa: E402

BLANK = np.full((360, 480, 3), 200, np.uint8)


def moved():
    f = BLANK.copy()
    f[100:250, 150:330] = 30                       # 사람만 한 어두운 덩어리
    return f


class AwayLogic(unittest.TestCase):
    def setUp(self):
        self.a = Away({"away_s": 8.0, "stale_s": 3.0})
        self.a._face = lambda f: False             # 얼굴 모델 없이 움직임만

    def test_needs_away_s_without_person(self):
        t = 1000.0
        self.a.seen = t
        for i in range(8):                         # 빈 방 그림이 1초마다 — 8초 전엔 아직
            self.a.look(BLANK, t + i)
            self.assertFalse(self.a.away(t + i))
        self.a.look(BLANK, t + 8)
        self.assertTrue(self.a.away(t + 8))

    def test_motion_resets(self):
        t = 1000.0
        self.a.seen = t
        for i in range(9):
            self.a.look(BLANK, t + i)
        self.assertTrue(self.a.away(t + 8))
        self.a.look(moved(), t + 9)                # 누가 움직임 → 바로 자리 비움 끝
        self.assertFalse(self.a.away(t + 9))

    def test_face_counts(self):
        t = 1000.0
        self.a.seen = t - 100
        self.a._face = lambda f: True
        self.a.look(BLANK, t)
        self.assertFalse(self.a.away(t))

    def test_stale_frames_mean_unknown(self):
        t = 1000.0
        self.a.seen = t - 100
        for i in range(9):
            self.a.look(BLANK, t + i)
        self.assertTrue(self.a.away(t + 9))
        self.assertFalse(self.a.away(t + 12))      # hand-mouse 꺼짐 → 모름 → 예전처럼
        self.a.look(BLANK, t + 60)                 # 다시 켜지면 그때부터 away_s 를 다시 셈
        self.assertFalse(self.a.away(t + 61))
        for i in range(2, 9):
            self.a.look(BLANK, t + 60 + i)
        self.assertTrue(self.a.away(t + 68))

    def test_disabled(self):
        a = Away({"enabled": False})
        a.seen, a.frame_t = 0.0, time.time()
        self.assertFalse(a.away())

    def test_tick_reads_handcam_view(self):
        import cv2
        with tempfile.TemporaryDirectory() as d:
            changes = []
            a = Away({"away_s": 0.0}, on_change=changes.append, folder=d)
            a._face = lambda f: False
            cv2.imwrite(os.path.join(d, "view.jpg"), BLANK)
            a.seen = time.time() - 1
            a.tick()
            self.assertTrue(os.path.exists(os.path.join(d, "want")))   # 책상 페이지가 닫혀 있어도 그림이 오게
            self.assertEqual(changes, [True])
            os.utime(os.path.join(d, "view.jpg"), (time.time() + 0.5,) * 2)
            a._face = lambda f: True
            a.away_s = 5.0
            a.tick()
            self.assertEqual(changes, [True, False])


class AwayDaemon(unittest.TestCase):
    def test_plain_speech_marked_when_away(self):
        d = make()
        d.wake("test")
        d.away.away = lambda now=None: True
        d.handle("가계부 앱 실기기 시험 돌려 줘")
        text, _, direct, _, away = d.brain_q.get_nowait()
        self.assertFalse(direct)
        self.assertTrue(away)

    def test_present_or_fist_or_muted_unchanged(self):
        d = make()
        d.wake("test")
        d.handle("가계부 앱 실기기 시험 돌려 줘")
        self.assertFalse(d.brain_q.get_nowait()[4])        # 보이면 예전처럼
        d.away.away = lambda now=None: True
        d.handle("이것도 해 줘", direct=True)
        self.assertEqual(d.brain_q.get_nowait()[2:5:2], (True, False))   # 주먹은 주먹 꼬리표
        d.mute()
        d.handle("가계부 앱 실기기 시험 돌려 줘")
        self.assertTrue(d.brain_q.empty())                 # 조용히 모드는 자리 비움이어도 안 받음

    def test_brain_tag(self):
        b = brain_mod.Brain(tempfile.mkdtemp(), state_file=os.path.join(tempfile.mkdtemp(), "s.json"))
        seen = []

        class P:
            def __init__(self, cmd, **k):
                seen.append(cmd[2])

            def communicate(self, timeout=None):
                return '{"result": "<IGNORE>", "session_id": "x"}', ""
        old = brain_mod.subprocess.Popen
        brain_mod.subprocess.Popen = P
        try:
            b.ask("불 꺼 줘", away=True)
            b.ask("불 꺼 줘", direct=True, away=True)
            b.ask("불 꺼 줘")
        finally:
            brain_mod.subprocess.Popen = old
        self.assertRegex(seen[0], r"^\[음성·자리비움 \d\d:\d\d\] 불 꺼 줘$")
        self.assertRegex(seen[1], r"^\[음성·주먹 ")
        self.assertRegex(seen[2], r"^\[음성 \d\d:\d\d\] ")


if __name__ == "__main__":
    unittest.main()
