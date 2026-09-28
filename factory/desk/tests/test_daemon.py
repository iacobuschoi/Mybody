"""데몬 흐름 시험 — 마이크 · 스피커 · 화면 · Claude 를 가짜로 바꿔 끼우고 상태가 맞게 바뀌는지.

  자는 중 → 박수 두 번 → 깨어남(화면 켜짐 · 브리핑) → 말(로컬/Claude) → "조용히" → "다시 들어" → "화면 꺼" → 자는 중
"""
import os
import sys
import time
import unittest

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from desk import briefing, config, daemon, mac  # noqa: E402
from tests.test_clap import clap, silence  # noqa: E402

CALLS: list[str] = []
DISPLAY = {"asleep": None}


class FakeVoice:
    def __init__(self, *a, **k):
        self.said, self.last_text = [], ""

    def busy(self):
        return False

    def say(self, text, block=False, opts=None):
        self.said.append(text)
        self.last_text = text
        self.opts = opts

    def configure(self, c):
        self.configured = c

    def stop(self):
        CALLS.append("voice.stop")


class FakeBrain:
    def __init__(self, *a, **k):
        self.asked = []
        self.model = a[1] if len(a) > 1 else ""

    def busy(self):
        return False

    def cancel(self):
        CALLS.append("brain.cancel")
        return False

    def ask(self, text):
        self.asked.append(text)
        return ("<IGNORE>" in text and (None, "")) or ("네, 가계부 시험을 돌렸어요.", "네, 가계부 시험을 돌렸어요.")


def make():
    CALLS.clear()
    for name in ["display_on", "display_off", "open_dashboard", "keep_system_awake"]:
        setattr(mac, name, (lambda n: (lambda *a, **k: CALLS.append(n)))(name))
    mac.sound = lambda *a, **k: None
    mac.displays_asleep = lambda: DISPLAY["asleep"]
    mac.change_volume = lambda d: 50
    mac.Voice = FakeVoice
    daemon.Brain = FakeBrain
    briefing.gather = lambda cfg: {"weather": "맑음", "factory": {"ok": False}, "lab": {"runner": True, "iphone": True, "android": 1}}
    cfg = config.load("/nonexistent")
    cfg["wake"]["night"] = ["00:00", "00:00"]      # 시험 중엔 밤이 아니게
    cfg["face"]["enabled"] = False                 # 이 맥에 얼굴이 등록돼 있어도 시험이 카메라를 켜지 않게
    d = daemon.Desk(cfg)
    return d


def feed(d, sig):
    for i in range(0, len(sig), 480):
        d._on_audio(sig[i:i + 480])


class DaemonFlow(unittest.TestCase):
    def test_full_flow(self):
        d = make()
        self.assertEqual(d.mode, "sleep")

        feed(d, np.concatenate([silence(1.0), clap()]))            # 한 번은 안 켜짐
        feed(d, silence(1.5))
        self.assertEqual(d.mode, "sleep")

        feed(d, np.concatenate([silence(1.0), clap(), silence(0.3), clap(), silence(1.5)]))
        self.assertEqual(d.mode, "awake")
        self.assertIn("display_on", CALLS)
        time.sleep(0.2)                                             # 브리핑 스레드
        self.assertTrue(any("시스템을 시작합니다" in s for s in d.voice.said))
        self.assertTrue(any("실험실은 정상" in s for s in d.voice.said))

        d.handle("지금 몇 시야")
        self.assertRegex(d.voice.said[-1], r"(오전|오후) \d+시 \d+분이에요")

        d.handle("가계부 앱 실기기 시험 돌려 줘")
        self.assertEqual(d.brain_q.get_nowait(), "가계부 앱 실기기 시험 돌려 줘")

        d.handle("조용히 해")
        self.assertEqual(d.mode, "muted")
        d.handle("가계부 앱 실기기 시험 돌려 줘")                  # 조용히 모드: 아무 데도 안 감
        self.assertTrue(d.brain_q.empty())
        d.handle("다시 들어")
        self.assertEqual(d.mode, "awake")

        d.handle("화면 꺼 줘")
        self.assertEqual(d.mode, "sleep")
        self.assertIn("display_off", CALLS)

    def test_muted_unmutes_on_double_clap(self):
        d = make()
        d.wake("test")
        d.mute()
        feed(d, np.concatenate([silence(1.0), clap(), silence(0.3), clap(), silence(1.5)]))
        self.assertEqual(d.mode, "awake")

    def test_night_needs_three_claps(self):
        d = make()
        d.cfg["wake"]["night"] = ["00:00", "23:59"]
        feed(d, np.concatenate([silence(1.0), clap(), silence(0.3), clap(), silence(1.5)]))
        self.assertEqual(d.mode, "sleep")
        feed(d, np.concatenate([silence(1.0), clap(), silence(0.3), clap(), silence(0.3), clap(), silence(1.5)]))
        self.assertEqual(d.mode, "awake")

    def test_idle_goes_to_sleep(self):
        d = make()
        d.wake("test")
        d.last_activity = time.time() - 16 * 60
        feed(d, silence(0.1))
        time.sleep(0.2)
        self.assertEqual(d.mode, "sleep")

    def test_stop_cancels_claude(self):
        d = make()
        d.wake("test")
        d.handle("멈춰")
        self.assertIn("brain.cancel", CALLS)
        self.assertIn("voice.stop", CALLS)


    def test_keyboard_wake_and_external_sleep(self):
        d = make()
        DISPLAY["asleep"] = False                 # 키보드로 화면을 켬
        d._changed_at = 0
        d._watch_display()
        self.assertEqual(d.mode, "awake")
        self.assertFalse(any("시스템을 시작합니다" in s for s in d.voice.said))   # 조용히
        DISPLAY["asleep"] = True                  # 30분 안전망으로 화면이 꺼짐
        d._changed_at = 0
        d._watch_display()
        self.assertEqual(d.mode, "sleep")
        DISPLAY["asleep"] = None

    def test_mic_blocked_when_only_zeros(self):
        # 권한이 없으면 macOS 는 정확히 0 만 보냄 → 6초 뒤 막힘으로 보고 한 번만 말함, 소리가 오면 풀림
        d = make()
        t0 = d._mic_heard
        zeros = np.zeros(480, dtype=np.float32)
        self.assertFalse(d._mic_check(zeros, t0 + 3))
        self.assertFalse(d.mic_blocked)
        self.assertTrue(d._mic_check(zeros, t0 + 7))
        self.assertTrue(d.mic_blocked)
        self.assertEqual(d.board.get()["mic"], "blocked")
        self.assertFalse(d._mic_check(None, t0 + 30))            # 이미 알림 — 또 말하지 않음
        self.assertEqual(sum("마이크 권한" in s for s in d.voice.said), 1)
        d._mic_check(silence(0.03), t0 + 31)                     # 조용한 방도 0 은 아님
        self.assertFalse(d.mic_blocked)
        self.assertEqual(d.board.get()["mic"], "ok")


if __name__ == "__main__":
    unittest.main()
