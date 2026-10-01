"""주먹 쥐고 말하기 시험 — 주먹 상태 파일 · 맨 앞 앱 · 붙여넣기를 가짜로 바꿔 끼우고 말이 어디로 가는지.

  주먹 + Claude 앱이 맨 앞 → 입력창에 붙여넣기(비서로 안 감) / 하나라도 아니면 → 지금처럼 비서로
"""
import json
import os
import sys
import tempfile
import time
import unittest

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from desk import dictate  # noqa: E402
from desk.dictate import CLAUDE_APP, Dictation, fist_overlap, held_fist  # noqa: E402
from desk.vad import Cut  # noqa: E402
from tests.test_daemon import make  # noqa: E402

T = 1_000_000.0


class FistWindow(unittest.TestCase):
    def test_overlap_closed_span(self):
        st = {"at": time.time(), "fist": False, "spans": [[T, T + 2]]}
        self.assertAlmostEqual(fist_overlap(st, T + 1, T + 4), 1.0)
        self.assertEqual(fist_overlap(st, T + 3, T + 4), 0.0)

    def test_open_span_counts_to_end_of_speech(self):
        now = time.time()
        st = {"at": now, "fist": True, "spans": [[now - 3, None]]}
        self.assertAlmostEqual(fist_overlap(st, now - 2, now), 2.0, places=2)

    def test_stale_open_span_ends_at_last_write(self):
        now = time.time()                       # hand-mouse 가 10초 전에 멈춤 — 주먹이 계속된 걸로 보지 않음
        st = {"at": now - 10, "fist": True, "spans": [[now - 12, None]]}
        self.assertEqual(fist_overlap(st, now - 3, now), 0.0)

    def test_no_state(self):
        self.assertFalse(held_fist(None, T, T + 2))
        self.assertFalse(held_fist({"spans": [["x", None]], "at": 0}, T, T + 2))

    def test_released_right_after_speaking_still_counts(self):
        # 2초 말 + 끝 침묵 0.8초 — 말을 마치며 손을 폄
        st = {"at": time.time(), "fist": False, "spans": [[T - 0.5, T + 2.0]]}
        self.assertTrue(held_fist(st, T, T + 2.8))

    def test_brief_fist_during_speech_does_not_count(self):
        st = {"at": time.time(), "fist": False, "spans": [[T + 1.0, T + 1.3]]}
        self.assertFalse(held_fist(st, T, T + 3.0))

    def test_long_speech_needs_only_enough_seconds(self):
        st = {"at": time.time(), "fist": False, "spans": [[T, T + 1.2]]}
        self.assertTrue(held_fist(st, T, T + 10.0, enough_s=1.0))

    def test_reads_file_written_by_hand_mouse(self):
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "fist.json")
            with open(p, "w") as f:
                json.dump({"at": T, "fist": True, "spans": [[T, None]]}, f)
            self.assertEqual(dictate.read_fist(p)["spans"], [[T, None]])
            self.assertIsNone(dictate.read_fist(os.path.join(d, "none.json")))


class FrontApp(unittest.TestCase):
    def test_parses_lsappinfo(self):
        outs = iter(['"LSASN:{hi=0x0;lo=0x1234}"\n', '"CFBundleIdentifier"="com.anthropic.claudefordesktop"\n'])

        class R:
            def __init__(self):
                self.stdout = next(outs)
        orig = dictate.subprocess.run
        dictate.subprocess.run = lambda *a, **k: R()
        try:
            self.assertEqual(dictate.front_bundle(), CLAUDE_APP)
        finally:
            dictate.subprocess.run = orig


def rig(front=CLAUDE_APP, fist=True, ok=True):
    now = time.time()
    put = []
    state = {"at": now, "fist": fist, "spans": [[now - 5, None]] if fist else []}
    dc = Dictation({}, front=lambda: front, put=lambda t: put.append(t) or ok, fist=lambda p: state,
                   back=lambda n: put.append(f"<BS{n}>") or ok)
    return dc, put, now


class DictationRule(unittest.TestCase):
    def test_fist_and_claude_front(self):
        dc, put, now = rig()
        self.assertTrue(dc.wants(now - 2, now))
        self.assertTrue(dc.put("  테스트 돌려 줘 "))
        self.assertTrue(dc.put("그리고 로그도"))
        self.assertEqual(put, ["테스트 돌려 줘", " 그리고 로그도"])   # 이어 말하면 띄어 붙임, 엔터 없음

    def test_other_app_front(self):
        dc, _, now = rig(front="com.google.Chrome")
        self.assertFalse(dc.wants(now - 2, now))

    def test_no_fist(self):
        dc, _, now = rig(fist=False)
        self.assertFalse(dc.wants(now - 2, now))

    def test_disabled(self):
        dc, _, now = rig()
        dc.enabled = False
        self.assertFalse(dc.wants(now - 2, now))


class Dial(unittest.TestCase):
    """왼손 지우기 다이얼: - 칸 = 단어 지우기(백스페이스), + 칸 = 되살리기(붙여넣기)"""

    def setUp(self):
        self.dc, self.out, _ = rig()
        self.dc.put("테스트 추가해")
        self.dc.put("로그도 봐")
        self.out.clear()                                  # 창: "테스트 추가해 로그도 봐"

    def test_erase_word_by_word_with_leading_space(self):
        self.assertEqual(self.dc.dial(-1), "지움 2글자")  # " 봐"
        self.assertEqual(self.dc.dial(-2), "지움 8글자")  # " 로그도" + " 추가해"
        self.assertEqual(self.dc.dial(-5), "지움 3글자")  # "테스트" — 처음에서 멈춤
        self.assertEqual(self.dc.dial(-1), "끝")
        self.assertEqual(self.out, ["<BS2>", "<BS8>", "<BS3>"])

    def test_restore_brings_back_exact_text(self):
        self.dc.dial(-3)
        self.assertEqual(self.dc.dial(+2), "되살림 8글자")
        self.assertEqual(self.out[-1], " 추가해 로그도")
        self.assertEqual(self.dc.dial(+9), "되살림 2글자")
        self.assertEqual(self.dc.dial(+1), "끝")

    def test_new_dictation_after_erase_drops_erased_tail(self):
        self.dc.dial(-2)                                  # 남은 것: "테스트 추가해"
        self.dc.put("커밋해")
        self.assertEqual(self.out[-1], " 커밋해")
        self.assertEqual(self.dc.text, "테스트 추가해 커밋해")
        self.assertEqual(self.dc.dial(+1), "끝")          # 버린 "로그도 봐"는 안 돌아옴

    def test_erase_everything_then_new_text_has_no_leading_space(self):
        self.dc.dial(-9)
        self.dc.put("새로")
        self.assertEqual(self.out[-1], "새로")

    def test_nothing_after_window_or_app_change(self):
        self.dc._last_at -= 1000
        self.assertIn("안 함", self.dc.dial(-1))
        dc2, out2, _ = rig()
        dc2.put("하나 둘")
        dc2._front = lambda: "com.apple.Safari"
        self.assertIn("안 함", dc2.dial(-1))
        self.assertFalse(any(p.startswith("<BS") for p in self.out + out2))

    def test_nothing_typed_yet(self):
        dc, out, _ = rig()
        self.assertEqual(dc.dial(-1), "없음")
        self.assertEqual(out, [])


class DaemonRouting(unittest.TestCase):
    def setUp(self):
        self.d = make()
        self.d.wake("test")
        self.d.voice.said.clear()

    def cut(self):
        now = time.time()
        return Cut(np.zeros(16000 * 2, dtype=np.float32), True, 1, 66, now - 2, now)

    def route(self, dc, text="이 함수 테스트 추가해 줘"):
        self.d.dictation = dc
        c = self.cut()
        if not self.d._dictate(c, text):
            self.d.handle(text)

    def test_goes_to_claude_app_not_assistant(self):
        dc, put, _ = rig()
        self.route(dc)
        self.assertEqual(put, ["이 함수 테스트 추가해 줘"])
        self.assertTrue(self.d.brain_q.empty())

    def test_stop_word_with_fist_is_typed_not_obeyed(self):
        dc, put, _ = rig()
        self.route(dc, "그만")
        self.assertEqual(put, ["그만"])

    def test_other_app_goes_to_assistant(self):
        dc, put, _ = rig(front="com.apple.Safari")
        self.route(dc)
        self.assertEqual(put, [])
        self.assertEqual(self.d.brain_q.get_nowait()[0], "이 함수 테스트 추가해 줘")

    def test_no_fist_goes_to_assistant(self):
        dc, put, _ = rig(fist=False)
        self.route(dc)
        self.assertEqual(put, [])
        self.assertFalse(self.d.brain_q.empty())

    def test_fist_erase_word_is_typed_as_text(self):
        dc, put, _ = rig()
        self.route(dc, "지워")                             # 말로 지우기는 뺐음 — 그냥 글로 들어감
        self.assertEqual(put, ["지워"])

    def test_dial_api(self):
        dc, put, _ = rig()
        self.route(dc, "테스트 추가해")
        self.assertEqual(self.d.dial("-1"), "지움 4글자")
        self.assertEqual(self.d.dial("+1"), "되살림 4글자")
        self.assertEqual(self.d.dial("x"), "칸 수가 아님")
        self.assertEqual(put[-2:], ["<BS4>", " 추가해"])

    def test_muted_does_not_dictate(self):
        dc, put, _ = rig()
        self.d.mute()
        self.route(dc)
        self.assertEqual(put, [])

    def test_no_permission_swallows_and_warns_once(self):
        dc, put, _ = rig(ok=False)
        orig = dictate.can_post_keys
        from desk import daemon
        daemon.can_post_keys = lambda ask=False: False
        try:
            self.route(dc)
            self.route(dc)
        finally:
            daemon.can_post_keys = orig
        self.assertTrue(self.d.brain_q.empty())                  # 주먹 쥐고 한 말은 비서로 새지 않음
        self.assertEqual(sum("손쉬운 사용" in s for s in self.d.voice.said), 1)

    def test_cut_gets_wall_clock_times(self):
        from tests.test_daemon import feed
        from tests.test_clap import silence
        got = []
        self.d.utt_q.put_nowait = got.append
        t = np.arange(16000 * 2) / 16000
        voice = (0.3 * np.sin(2 * np.pi * 300 * t)).astype(np.float32)
        feed(self.d, np.concatenate([silence(1.0), voice, silence(3.5)]))
        self.assertTrue(got)
        c = got[-1]
        self.assertAlmostEqual(c.t1 - c.t0, len(c.audio) / 16000, places=3)
        self.assertLess(abs(c.t1 - time.time()), 5)


if __name__ == "__main__":
    unittest.main()
