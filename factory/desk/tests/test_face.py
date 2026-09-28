"""얼굴 인증 시험 — 카메라 없이: 판정 셈 · 데몬 흐름(주인 · 남 · 고장) · 확인 프로그램이 죽거나 멈출 때."""
import os
import sys
import time
import unittest

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from desk import face  # noqa: E402
from tests.test_clap import clap, silence  # noqa: E402
from tests.test_daemon import CALLS, feed, make  # noqa: E402


class FakeGate:
    def __init__(self, result, active=True):
        self.result, self._active, self.checked = result, active, 0

    def active(self):
        return self._active

    def check(self):
        self.checked += 1
        return self.result


def claps(d):
    feed(d, np.concatenate([silence(1.0), clap(), silence(0.3), clap(), silence(1.5)]))


def settle(d):
    for _ in range(100):
        if not d._verifying:
            return
        time.sleep(0.02)


class Match(unittest.TestCase):
    def test_score_and_decide(self):
        a = np.eye(4, dtype=np.float32)[:2]
        self.assertAlmostEqual(face.score(a, np.array([0, 1, 0, 0], np.float32)), 1.0)
        self.assertTrue(face.decide([0.2, 0.5, 0.45], 0.4, 2))
        self.assertFalse(face.decide([0.2, 0.5, 0.3], 0.4, 2))
        self.assertFalse(face.decide([], 0.4, 1))


class Flow(unittest.TestCase):
    def test_owner_wakes_with_welcome(self):
        d = make()
        d.cfg["face"]["name"] = "최민종"
        d.face = FakeGate({"ok": True, "best": 0.7})
        claps(d)
        settle(d)
        self.assertEqual(d.mode, "awake")
        self.assertIn("display_on", CALLS)
        self.assertIn("얼굴 인증해 주세요.", d.voice.said)
        self.assertIn("최민종님, 환영합니다.", d.voice.said)
        self.assertNotIn("시스템을 시작합니다.", d.voice.said)

    def test_stranger_stays_asleep(self):
        d = make()
        d.face = FakeGate({"ok": False, "best": 0.1})
        claps(d)
        settle(d)
        self.assertEqual(d.mode, "sleep")
        self.assertNotIn("display_on", CALLS)
        self.assertEqual(d.voice.said[-1], "얼굴을 확인하지 못했어요.")

    def test_camera_error_follows_on_error(self):
        d = make()
        d.face = FakeGate({"ok": False, "error": "카메라를 못 엶"})
        claps(d)
        settle(d)
        self.assertEqual(d.mode, "sleep")
        self.assertIn("카메라를 쓸 수 없어서", d.voice.said[-1])
        d.cfg["face"]["on_error"] = "wake"
        claps(d)
        settle(d)
        self.assertEqual(d.mode, "awake")

    def test_gate_exception_does_not_kill(self):
        d = make()
        g = FakeGate(None)
        g.check = lambda: 1 / 0
        d.face = g
        claps(d)
        settle(d)
        self.assertEqual(d.mode, "sleep")
        self.assertFalse(d._verifying)

    def test_not_enrolled_is_plain_clap(self):
        d = make()
        d.face = FakeGate({"ok": False}, active=False)
        claps(d)
        self.assertEqual(d.mode, "awake")
        self.assertEqual(d.face.checked, 0)

    def test_no_name_says_plain_welcome(self):
        d = make()
        self.assertEqual(d._welcome(), "환영합니다.")
        d.cfg["face"]["welcome"] = "{이름} 어서 와요"          # 틀린 틀이어도 죽지 않음
        d.cfg["owner"] = "민종"
        self.assertEqual(d._welcome(), "민종님, 환영합니다.")


class GateProcess(unittest.TestCase):
    def test_timeout_and_crash_become_errors(self):
        g = face.Gate({"enabled": True, "timeout_s": 1})
        orig = face.sys.executable
        try:
            face.sys.executable = "/bin/sleep"            # "sleep -m desk face verify" → 바로 죽음
            r = g._run("verify", 2)
            self.assertFalse(r["ok"])
            self.assertIn("error", r)
        finally:
            face.sys.executable = orig

    def test_active_needs_enrollment(self):
        old = face.OWNER
        try:
            face.OWNER = "/nonexistent/owner.npz"
            self.assertFalse(face.Gate({"enabled": True}).active())
        finally:
            face.OWNER = old


if __name__ == "__main__":
    unittest.main()
