"""왼손 주먹 = 비서에게 말하기(desk/talk.py) — 녹음 구간 · 데몬 흐름(상시 듣기와 안 섞임, 무시 판정 없음)."""
import os
import sys
import time
import unittest

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from desk import mac, stt  # noqa: E402
from desk.brain import Brain  # noqa: E402
from desk.talk import PushToTalk  # noqa: E402
from desk.vad import Cut  # noqa: E402
from desk.router import route  # noqa: E402
from tests.test_daemon import CALLS, ROOM, SCREEN_CALLS, clap, feed, make, silence  # noqa: E402

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

    def test_listening_label_only_while_fist_is_closed(self):
        """책상 탭 「듣는 중」은 주먹을 쥔 동안만. 평소 상시 듣기는 「대기 중」(idle) (주인 11월 5일 0:02)"""
        d = self.d
        mode = lambda: d.board.get()["mode"]  # noqa: E731
        d._show()
        self.assertEqual(mode(), "idle")
        d.talk("start")
        self.assertEqual(mode(), "listening")
        d._show()                                         # 0.5초마다 도는 갱신이 되돌리지 않음
        self.assertEqual(mode(), "listening")
        d._show("thinking")                               # 앞선 말의 답을 만들기 시작해도 쥔 동안은 듣는 중
        self.assertEqual(mode(), "listening")
        d.talk("end")
        time.sleep(d.ptt.tail_s + 0.05)
        feed(d, np.zeros(480, np.float32))
        d._show()
        self.assertEqual(mode(), "idle")
        d.utt_q.get_nowait()

    def test_listening_label_after_cancel_and_in_other_modes(self):
        d = self.d
        mode = lambda: d.board.get()["mode"]  # noqa: E731
        d.talk("start")
        d.ptt.cancel()
        d._show()
        self.assertEqual(mode(), "idle")
        d._show("thinking")                               # 주먹 없으면 생각 중 · 말하는 중은 그대로
        self.assertEqual(mode(), "thinking")
        d.mode = "muted"
        d._show()
        self.assertEqual(mode(), "muted")
        d.talk("start")                                   # 조용히 모드에서도 주먹 말은 받으므로 듣는 중
        self.assertEqual(mode(), "listening")
        d.ptt.cancel()
        d._show()
        self.assertEqual(mode(), "muted")
        d.mode = "sleep"
        d._show()
        self.assertEqual(mode(), "sleep")

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
        text, _, direct, *_ = d.brain_q.get_nowait()
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



class FistOnly(unittest.TestCase):
    """[listen] always_on = false — 주먹 · 폰 · 박수 · deskctl 만 (주인 11월 5일 0:20)"""

    def setUp(self):
        self.d = make()
        self.d.always_on = False
        self.d.wake("test")
        time.sleep(0.1)
        self.d.voice.said.clear()
        self.handled = []
        real = self.d.handle
        self.d.handle = lambda text, **k: (self.handled.append(text), real(text, **k))

    def test_config_default_keeps_always_on(self):
        self.assertTrue(make().always_on)

    def test_speech_without_fist_is_not_cut_or_barged(self):
        d = self.d
        d.barge.feed = lambda *a: self.fail("끼어들기를 듣고 있음")
        feed(d, tone(2.0))
        feed(d, np.zeros(SR, np.float32))
        self.assertFalse(d.seg.in_speech)
        self.assertTrue(d.utt_q.empty())
        self.assertFalse(d._owner_talking())
        self.assertEqual(self.handled, [])

    def test_fist_still_records_and_marks_owner_talking(self):
        d = self.d
        feed(d, np.zeros(SR, np.float32))
        self.assertEqual(d.talk("start"), "ok")
        self.assertTrue(d._owner_talking())
        feed(d, tone(1.0))
        d.talk("end")
        time.sleep(d.ptt.tail_s + 0.05)
        feed(d, np.zeros(480, np.float32))
        self.assertTrue(d.utt_q.get_nowait().direct)
        self.assertFalse(d._owner_talking())

    def test_fist_cuts_speaker(self):
        d = self.d
        cuts = []
        d._cut = lambda heard, timing="": cuts.append(heard)
        d.voice.busy = lambda: True
        self.assertEqual(d.talk("start"), "ok")
        self.assertEqual(cuts, ["왼손 주먹"])

    def test_hold_after_restart_starts_recording(self):
        d = self.d
        self.assertEqual(d.talk("hold"), "ok")
        self.assertTrue(d.ptt.active)

    def test_claps_still_turn_off_and_wake(self):
        d = self.d
        d._changed_at = 0                                 # 켠 직후 보호 시간은 지남
        feed(d, np.concatenate([silence(1.0), clap(), silence(0.3), clap(), silence(1.5)]))
        time.sleep(0.2)
        self.assertEqual(d.mode, "sleep")
        feed(d, np.concatenate([silence(1.0), clap(), silence(0.3), clap(), silence(1.5)]))
        self.assertEqual(d.mode, "awake")

    def test_idle_sleep_still_runs(self):
        d = self.d
        d.last_activity = time.time() - d.cfg["idle_minutes"] * 60 - 1
        d.voice.busy = d.brain.busy = lambda: False
        feed(d, np.zeros(480, np.float32))
        time.sleep(0.2)
        self.assertEqual(d.mode, "sleep")

    def test_mic_check_does_not_depend_on_listening(self):
        d = self.d
        now = time.time()
        d._mic_heard = now - 7
        d._mic_check(np.zeros(480, np.float32), now)
        self.assertTrue(d.mic_blocked)
        d._mic_check(tone(0.03), now)
        self.assertFalse(d.mic_blocked)


    def test_idle_sleep_waits_while_netflix_or_keyboard_in_use(self):
        """상시 듣기가 꺼져 있으면 넷플릭스 소리로 활동을 알 수 없음 — 재생 · 입력 중에는 15분이 지나도 안 끔"""
        d = self.d
        d.voice.busy = d.brain.busy = lambda: False
        d.last_activity = time.time() - d.cfg["idle_minutes"] * 60 - 1
        ROOM["in_use"] = True
        feed(d, np.zeros(480, np.float32))
        time.sleep(0.2)
        self.assertEqual(d.mode, "awake")
        ROOM["in_use"] = False
        feed(d, np.zeros(480, np.float32))
        time.sleep(0.2)
        self.assertEqual(d.mode, "awake")                 # 1분 뒤에 다시 봄
        d.last_activity = time.time() - d.cfg["idle_minutes"] * 60 - 1
        feed(d, np.zeros(480, np.float32))
        time.sleep(0.2)
        self.assertEqual(d.mode, "sleep")


class OneScreen(unittest.TestCase):
    """화면 하나만 끄고 켜기 (주인 11월 5일 0:25)"""

    def setUp(self):
        self.d = make()
        self.d.wake("test")
        time.sleep(0.1)
        SCREEN_CALLS.clear()
        CALLS.clear()

    def test_off_and_on_leave_everything_else_alone(self):
        d = self.d
        self.assertEqual(d.screen_one("desk", False), "ok")
        self.assertEqual(d.board.get()["screens"], {"main": True, "desk": False})
        self.assertEqual(d.mode, "awake")
        self.assertNotIn("cameras_off", CALLS)
        self.assertNotIn("display_off", CALLS)
        self.assertEqual(d.screen_one("desk", True), "ok")
        self.assertEqual(d.board.get()["screens"], {"main": True, "desk": True})
        self.assertEqual(SCREEN_CALLS, [("hold", "desk"), ("release", "desk")])

    def test_turning_one_on_during_whole_off_keeps_other_off(self):
        d = self.d
        d.mode = "sleep"
        kept = []
        real = mac.display_on
        mac.display_on = lambda keep=(): kept.append(keep)
        try:
            self.assertEqual(d.screen_one("main", True, "폰"), "ok")
        finally:
            mac.display_on = real
        self.assertEqual(d.mode, "awake")
        self.assertEqual(kept, [("desk",)])
        self.assertEqual(SCREEN_CALLS, [("hold", "desk")])
        self.assertEqual(d.screen_one("desk", False), "ok")   # 깨어 있으니 이제 그냥 듦

    def test_off_during_whole_off_does_nothing(self):
        d = self.d
        d.mode = "sleep"
        self.assertEqual(d.screen_one("desk", False), "이미 꺼져 있음")
        self.assertEqual(SCREEN_CALLS, [])

    def test_unknown_screen_is_refused(self):
        with self.assertRaises(ValueError):
            self.d.screen_one("left", False)

    def test_voice_words(self):
        self.assertEqual(route("세로 화면 꺼").kind, "screen_desk_off")
        self.assertEqual(route("세로 모니터 켜 줘").kind, "screen_desk_on")
        self.assertEqual(route("주 화면 꺼").kind, "screen_main_off")
        self.assertEqual(route("티비 화면 켜").kind, "screen_main_on")
        self.assertEqual(route("화면 꺼").kind, "sleep")     # 전체 끄기는 그대로
        self.assertEqual(route("다시 들어", muted=True).kind, "unmute")

    def test_voice_turns_screen_off(self):
        d = self.d
        d.handle("세로 화면 꺼", direct=True)
        self.assertEqual(SCREEN_CALLS, [("hold", "desk")])
        self.assertIn("세로 화면을 껐어요.", d.voice.said)


if __name__ == "__main__":
    unittest.main()
