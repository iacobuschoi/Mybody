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


class Erase(unittest.TestCase):
    def test_erase_words_only_alone(self):
        self.assertEqual(dictate.erase_kind("지워."), "one")
        self.assertEqual(dictate.erase_kind("방금 거 지워 줘"), "one")
        self.assertEqual(dictate.erase_kind("취소"), "one")
        self.assertEqual(dictate.erase_kind("다 지워!"), "all")
        self.assertEqual(dictate.erase_kind("이 파일 지워 줘"), "")      # 문장 속 "지워"는 글로 넣음
        self.assertEqual(dictate.erase_kind(""), "")

    def test_erase_last_chunk_counts_hangul_and_space(self):
        dc, put, _ = rig()
        dc.put("테스트 추가해")
        dc.put("로그도")
        self.assertEqual(dc.erase(), 4)                     # " 로그도"
        self.assertEqual(dc.erase(), 7)                     # "테스트 추가해"
        self.assertEqual(dc.erase(), 0)                     # 더 지울 것 없음
        self.assertEqual(put[-2:], ["<BS4>", "<BS7>"])
        dc.put("새로")
        self.assertEqual(put[-1], "새로")                   # 다 지운 뒤엔 띄어쓰기 없이

    def test_erase_all(self):
        dc, put, _ = rig()
        dc.put("하나")
        dc.put("둘")
        self.assertEqual(dc.erase(everything=True), 4)   # "하나" + " 둘"
        self.assertEqual(put[-1], "<BS4>")

    def test_no_erase_after_window_or_app_change(self):
        dc, put, _ = rig()
        dc.put("하나")
        dc._last_at -= 1000
        self.assertEqual(dc.erase(), 0)
        dc2, put2, _ = rig()
        dc2.put("하나")
        dc2._front = lambda: "com.apple.Safari"
        self.assertEqual(dc2.erase(), 0)
        self.assertFalse(any(p.startswith("<BS") for p in put + put2))


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

    def test_fist_erase_word_erases_not_typed(self):
        dc, put, _ = rig()
        self.route(dc, "테스트 추가해")
        self.route(dc, "지워")
        self.assertEqual(put, ["테스트 추가해", "<BS7>"])
        self.assertTrue(self.d.brain_q.empty())

    def test_cancel_without_fist_goes_to_assistant_router(self):
        dc, put, _ = rig(fist=False)
        self.route(dc, "취소")
        self.assertEqual(put, [])

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
