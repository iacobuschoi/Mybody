"""말 끝 기다리기 — 잠정 조각 · commit · 끝말 가늠(desk/vad.py, desk/endpoint.py, Desk._hear_cut)."""
import os
import sys
import unittest

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from desk.endpoint import looks_unfinished  # noqa: E402
from desk.vad import Cut, Segmenter  # noqa: E402

SR = 16000
RNG = np.random.default_rng(3)


def quiet(s):
    return (RNG.standard_normal(int(SR * s)) * 0.002).astype(np.float32)


def voice(s):
    t = np.arange(int(SR * s)) / SR
    return (0.2 * np.sin(2 * np.pi * 180 * t) * (0.6 + 0.4 * np.sin(2 * np.pi * 3 * t))).astype(np.float32)


def run(seg, sig, on_cut=None):
    cuts = []
    for i in range(0, len(sig), 480):
        for c in seg.feed_cuts(sig[i:i + 480]):
            cuts.append(c)
            if on_cut:
                on_cut(c)
    return cuts


def hold_seg():
    return Segmenter(sr=SR, end_silence_s=0.8, hold_silence_s=2.5)


PAUSED = np.concatenate([quiet(1.0), voice(1.0), quiet(1.2), voice(1.0), quiet(3.0)])   # 1.2초 뜸


class HoldTest(unittest.TestCase):
    def test_no_hold_is_old_behaviour(self):
        seg = Segmenter(sr=SR, end_silence_s=0.8)
        cuts = run(seg, PAUSED)
        self.assertEqual([c.final for c in cuts], [True, True])            # 뜸에서 잘림(예전)

    def test_waits_through_pause_when_unfinished(self):
        cuts = run(hold_seg(), PAUSED)                                     # commit 없음 = 끝말이 이어질 듯
        self.assertEqual([c.final for c in cuts], [False, False, True])
        self.assertGreater(len(cuts[-1].audio) / SR, 3.0)                  # 두 말이 한 구간
        self.assertEqual(len({c.seq for c in cuts}), 1)

    def test_commit_closes_during_silence(self):
        seg = hold_seg()
        cuts = run(seg, PAUSED, lambda c: None if c.final else seg.commit(c.seq, c.frames))
        self.assertEqual([c.final for c in cuts], [False, False])          # 둘 다 끝난 말 — 확정을 기다리지 않음
        self.assertEqual(len({c.seq for c in cuts}), 2)                    # 뜸에서 닫혀 두 구간
        self.assertLess(len(cuts[1].audio) / SR, 2.2)

    def test_commit_after_speech_resumed_keeps_rest(self):
        seg = hold_seg()
        pending = []
        sig = np.concatenate([quiet(1.0), voice(1.0), quiet(0.9)])
        run(seg, sig, pending.append)
        self.assertEqual([c.final for c in pending], [False])
        run(seg, voice(0.6))                                               # 받아쓰는 사이 말이 이어짐
        seg.commit(pending[0].seq, pending[0].frames)                      # 그래도 앞 말은 끝난 말로 답함
        cuts = run(seg, quiet(3.0))
        finals = [c for c in cuts if c.final]
        self.assertEqual(len(finals), 1)
        self.assertNotEqual(finals[0].seq, pending[0].seq)
        self.assertLess(len(finals[0].audio) / SR, 0.9 + 0.6 + 2.6)        # 앞 말은 빠짐

    def test_stale_commit_is_ignored(self):
        seg = hold_seg()
        cuts = run(seg, PAUSED)
        seg.commit(cuts[0].seq, cuts[0].frames)                            # 이미 닫힌 구간
        self.assertFalse(seg.in_speech)


class MinLevelTest(unittest.TestCase):
    def test_gated_silence_blip_is_not_speech(self):
        """스피커폰은 조용하면 거의 0 — 그 위의 아주 작은 소리(제 말이 끝나고 마이크가 다시 열릴 때)를 말로 자르지 않음."""
        blip = (RNG.standard_normal(int(SR * 1.0)) * 0.0012).astype(np.float32)
        sig = np.concatenate([np.zeros(int(SR * 3), dtype=np.float32), blip, np.zeros(int(SR * 2), dtype=np.float32)])
        self.assertTrue(run(Segmenter(sr=SR), sig))                                 # 예전: 빈 구간을 받아씀
        self.assertEqual(run(Segmenter(sr=SR, min_level=0.001), sig), [])
        talk = np.concatenate([np.zeros(int(SR * 3), dtype=np.float32), voice(1.0), np.zeros(int(SR * 2), dtype=np.float32)])
        self.assertEqual(len([c for c in run(Segmenter(sr=SR, min_level=0.001), talk) if c.final]), 1)


class EndpointTest(unittest.TestCase):
    DONE = ["화면 꺼", "오늘 날씨 어때?", "브리핑 해 줘", "음량 좀 줄여줘.", "지금 몇 시야", "공장 상태 알려줘", "고마워",
            "그만", "이거 뭐지", "빌드 돌려", "알았어", "내일 일정 정리해 줘요", "조용히 해", "좋아", "다시 들어",
            "메일 보냈니", "응", "날씨 알려 줄래", "잠깐", "",
            "안 움직인다고", "세팅하라고", "이동모드가 뭐냐고", "같이 하자고"]
    CONT = ["오늘 일정이랑", "그리고", "음", "공장에서", "아이폰으로", "내일은", "날씨를", "빌드 돌리고", "시간 되면",
            "그러니까", "이거 끝나면", "앱 만들어서", "확인했는데", "브리핑하고,", "그 앱을", "깃허브에", "근데…"]

    def test_finished(self):
        self.assertEqual([t for t in self.DONE if looks_unfinished(t)], [])

    def test_unfinished(self):
        self.assertEqual([t for t in self.CONT if not looks_unfinished(t)], [])


class DaemonHearCut(unittest.TestCase):
    def setUp(self):
        from tests.test_daemon import make
        self.d = make()
        self.d.seg = hold_seg()
        self.heard = []
        self.d.stt.transcribe = lambda a: self.heard.append(len(a)) or self.text

    def test_finished_tentative_answers_and_commits(self):
        self.text = "화면 꺼"
        cuts = run(self.d.seg, np.concatenate([quiet(1.0), voice(1.0), quiet(1.0)]))
        self.assertEqual(self.d._hear_cut(cuts[0]), "화면 꺼")
        self.assertFalse(self.d.seg.in_speech)                             # 닫혔으니 확정 조각은 안 옴
        self.assertEqual([c for c in run(self.d.seg, quiet(3.0)) if c.final], [])

    def test_unfinished_tentative_waits(self):
        self.text = "오늘 일정이랑"
        cuts = run(self.d.seg, np.concatenate([quiet(1.0), voice(1.0), quiet(1.0)]))
        self.assertEqual(self.d._hear_cut(cuts[0]), "")
        self.assertTrue(self.d.seg.in_speech)

    def test_held_text_reused_when_nothing_followed(self):
        self.text = "작업 브리핑을"
        cuts = run(self.d.seg, np.concatenate([quiet(1.0), voice(1.0), quiet(3.0)]))
        self.assertEqual([c.final for c in cuts], [False, True])
        self.assertEqual(self.d._hear_cut(cuts[0]), "")
        self.assertEqual(self.d._hear_cut(cuts[1]), "작업 브리핑을")       # 다시 받아쓰지 않음
        self.assertEqual(len(self.heard), 1)
        self.assertGreaterEqual(cuts[1].tail_s, 2.5)

    def test_held_then_more_speech_hears_again(self):
        self.text = "오늘 일정이랑"
        cuts = run(self.d.seg, PAUSED)
        self.assertEqual([c.final for c in cuts], [False, False, True])
        self.assertEqual(self.d._hear_cut(cuts[0]), "")                    # 첫 뜸에서 기다림
        self.text = "오늘 일정이랑 날씨"
        self.assertEqual(self.d._hear_cut(cuts[2]), "오늘 일정이랑 날씨")   # 뒤에 말이 더 있었으니 합쳐 다시 받아씀
        self.assertEqual(len(self.heard), 2)

    def test_speech_during_stt_not_answered_twice(self):
        self.text = "아래로 내려가는 걸 인식을 못해요"                     # 10/2 13:34 — 같은 말에 두 번 답함
        sig = lambda *p: np.concatenate(p)
        first = run(self.d.seg, sig(quiet(1.0), voice(1.0), quiet(0.9)))
        second = run(self.d.seg, sig(voice(0.6), quiet(0.9)))              # 받아쓰는 사이 이어 말하고 또 쉼
        self.assertEqual([c.final for c in first + second], [False, False])
        self.assertEqual(self.d._hear_cut(first[0]), self.text)            # 앞 말 답하고 구간을 나눔
        self.assertEqual(self.d._hear_cut(second[0]), "")                  # 옛 구간 번호 — 앞 말까지 든 조각은 버림
        self.assertEqual(len(self.heard), 1)
        rest = run(self.d.seg, quiet(0.1))                                 # 뒤 말은 새 구간으로 바로 다시 나옴
        self.assertEqual([c.final for c in rest], [False])
        self.assertNotEqual(rest[0].seq, first[0].seq)
        self.assertLess(len(rest[0].audio) / SR, 1.8)
        self.text = "손가락 아래로 향했을 때"
        self.assertEqual(self.d._hear_cut(rest[0]), self.text)             # 뒤 말만 따로 답함
        self.assertEqual(len(self.heard), 2)

    def test_tentative_skipped_when_final_queued(self):
        self.text = "화면 꺼"
        self.d._finals.add(7)
        self.assertEqual(self.d._hear_cut(Cut(voice(1.0), False, 7, 30)), "")
        self.assertEqual(self.heard, [])

    def test_final_after_answered_tentative_hears_only_tail(self):
        self.text = "화면 꺼"
        self.d._taken[5] = 50                                              # 앞 1.5초는 이미 답함
        self.assertEqual(self.d._hear_cut(Cut(quiet(1.5 + 2.6), True, 5, 0)), "")   # 뒤는 침묵뿐
        self.d._taken[6] = 50
        self.assertEqual(self.d._hear_cut(Cut(quiet(1.5 + 1.0 + 2.6), True, 6, 0)), "화면 꺼")
        self.assertEqual(self.heard, [int(SR * (1.0 + 2.6))])


if __name__ == "__main__":
    unittest.main()
