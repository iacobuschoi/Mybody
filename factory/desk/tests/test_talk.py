"""왼손 주먹 = 비서에게 말하기(desk/talk.py) — 녹음 구간 · 데몬 흐름(상시 듣기와 안 섞임, 무시 판정 없음)."""
import os
import sys
import time
import unittest

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from desk import stt  # noqa: E402
from desk.brain import Brain  # noqa: E402
from desk.talk import PushToTalk  # noqa: E402
from desk.vad import Cut  # noqa: E402
from tests.test_daemon import feed, make  # noqa: E402

SR = 16000


def tone(s, f=220.0, a=0.1):
    t = np.arange(int(SR * s)) / SR
    return (a * np.sin(2 * np.pi * f * t)).astype(np.float32)


class Clock:
    def __init__(self):
        self.t = 1000.0

    def __call__(self):
        return self.t


class PushToTalkTest(unittest.TestCase):
    def setUp(self):
        self.c = Clock()
        self.p = PushToTalk(SR, preroll_s=0.3, tail_s=0.2, max_s=10, beat_s=3, clock=self.c)

    def run_for(self, s, chunk=480):
        got = None
        for _ in range(int(s * SR / chunk)):
            self.c.t += chunk / SR
            got = self.p.feed(np.ones(chunk, np.float32)) or got
            if got:
                return got
        return got

    def test_start_end_with_preroll_and_tail(self):
        self.run_for(1.0)
        self.assertTrue(self.p.start())
        self.assertIsNone(self.run_for(1.5))
        self.p.end()
        audio, t0, t1, why = self.run_for(1.0)
        self.assertEqual(why, "손 폄")
        self.assertAlmostEqual(len(audio) / SR, 0.3 + 1.5 + 0.2, delta=0.06)   # 앞 0.3 + 쥔 동안 + 뒤 0.2
        self.assertAlmostEqual(t1 - t0, len(audio) / SR, delta=0.06)
        self.assertFalse(self.p.active)

    def test_regrip_during_tail_continues(self):
        self.p.start()
        self.run_for(0.5)
        self.p.end()
        self.run_for(0.1)
        self.assertFalse(self.p.start())                  # 펴자마자 다시 쥠 — 이어서
        self.assertIsNone(self.run_for(1.0))
        self.p.end()
        self.assertGreater(len(self.run_for(1.0)[0]) / SR, 1.5)

    def test_lost_beat_and_max_cut(self):
        self.p.start()
        self.assertEqual(self.run_for(4.0)[3], "hand-mouse 소식 없음")
        self.p.start()
        for _ in range(12):
            self.p.hold()
            got = self.run_for(1.0)
            if got:
                break
        self.assertEqual(got[3], "너무 김")


class DirectTranscript(unittest.TestCase):
    def test_short_answers_kept_only_when_direct(self):
        self.assertEqual(stt.clean_transcript("응"), "")
        self.assertEqual(stt.clean_transcript("응", direct=True), "응")
        self.assertEqual(stt.clean_transcript("해", direct=True), "해")
        self.assertEqual(stt.clean_transcript("시청해 주셔서 감사합니다", direct=True), "")
        self.assertEqual(stt.clean_transcript("감사합니다", direct=True), "")


class BrainTag(unittest.TestCase):
    def test_prompt_tag(self):
        seen = []

        class P:
            def __init__(self, cmd, **k):
                seen.append(cmd[2])

            def communicate(self, timeout=None):
                return '{"result": "네"}', ""

            def poll(self):
                return 0

        import desk.brain as b
        old, b.subprocess.Popen = b.subprocess.Popen, P
        try:
            br = Brain("/tmp", state_file="/tmp/desk-talk-test-session.json")
            br.ask("불 꺼 줘", direct=True)
            br.ask("불 꺼 줘")
        finally:
            b.subprocess.Popen = old
        self.assertRegex(seen[0], r"^\[음성·주먹 \d\d:\d\d\] 불 꺼 줘$")
        self.assertRegex(seen[1], r"^\[음성 \d\d:\d\d\] 불 꺼 줘$")


class DaemonTalk(unittest.TestCase):
    def setUp(self):
        self.d = make()
        self.d.wake("test")
        time.sleep(0.1)
        self.d.voice.said.clear()

    def test_fist_span_goes_to_utt_queue_not_segmenter(self):
        d = self.d
        feed(d, np.zeros(SR, np.float32))
        self.assertEqual(d.talk("start"), "ok")
        feed(d, tone(1.5))
        self.assertFalse(d.seg.in_speech)                 # 상시 듣기 자르개는 안 들음
        self.assertTrue(d.utt_q.empty())
        d.talk("end")
        time.sleep(d.ptt.tail_s + 0.05)                  # 펴고 tail_s 뒤 (벽시계)
        feed(d, np.zeros(480, np.float32))
        cut = d.utt_q.get_nowait()
        self.assertTrue(cut.direct and cut.final)
        self.assertGreater(len(cut.audio) / SR, 1.5)
        self.assertTrue(d.utt_q.empty())

    def test_hold_after_restart_resumes_with_heard_speech(self):
        """쥔 사이 deskd 가 다시 켜짐 — start 없이 hold 가 오면 상시 듣기가 받던 말부터 이어 녹음"""
        d = self.d
        feed(d, np.zeros(SR, np.float32))
        feed(d, tone(1.0))                                # 다시 켜진 뒤 상시 듣기로 들어온 말
        self.assertTrue(d.seg.in_speech)
        self.assertEqual(d.talk("hold"), "ok")
        self.assertTrue(d.ptt.active)
        self.assertFalse(d.seg.in_speech)
        feed(d, tone(0.5))
        self.assertEqual(d.talk("end"), "ok")             # 예전: "녹음 중 아님"
        time.sleep(d.ptt.tail_s + 0.05)
        feed(d, np.zeros(480, np.float32))
        cut = d.utt_q.get_nowait()
        self.assertTrue(cut.direct)
        self.assertGreater(len(cut.audio) / SR, 1.4)
        self.assertTrue(d.utt_q.empty())

    def test_direct_text_skips_dictate_and_reaches_brain_tagged(self):
        d = self.d
        d.dictation.wants = lambda *a: True               # 오른손 주먹 + Claude 앱이어도 왼손 주먹이 이김
        d.stt.transcribe = lambda audio, direct=False: "응 해" if direct else "?"
        now = time.time()
        d.utt_q.put(Cut(np.zeros(SR, np.float32), True, -1, 0, now - 1, now, direct=True))
        cut = d.utt_q.get()
        d._talked(cut, d._hear_cut(cut))
        text, _, direct, _ = d.brain_q.get_nowait()
        self.assertEqual((text, direct), ("응 해", True))

    def test_muted_still_hears_fist_and_sleep_does_not(self):
        d = self.d
        d.mode = "muted"
        d.handle("오늘 일정 정리해 줘", direct=True)
        self.assertEqual(d.brain_q.get_nowait()[2], True)
        d.mode = "sleep"
        self.assertEqual(d.talk("start"), "자는 중")

    def test_empty_long_fist_asks_again(self):
        d = self.d
        now = time.time()
        d._talked(Cut(np.zeros(SR * 2, np.float32), True, -1, 0, now - 2, now, direct=True), "")
        self.assertEqual(d.voice.said[-1], "잘 못 들었어요. 다시 말해 주세요.")
        d.voice.said.clear()
        d._talked(Cut(np.zeros(SR // 2, np.float32), True, -1, 0, now - 0.5, now, direct=True), "")
        self.assertEqual(d.voice.said, [])               # 잠깐 쥐었다 편 건 조용히


if __name__ == "__main__":
    unittest.main()
