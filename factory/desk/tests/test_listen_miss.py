"""상시 듣기가 주인 말을 놓치거나 자르지 않는지 — 짧은 말, 말하기 시작 · 끝에 겹친 말, 버린 말 로그(10월 2일)."""
import os
import sys
import time
import unittest

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from desk.bargein import Listener, strip_echo  # noqa: E402
from desk.vad import Segmenter  # noqa: E402
from tests import test_daemon  # noqa: E402
from tests.test_bargein import speechlike  # noqa: E402
from tests.test_daemon import make  # noqa: E402
from tests.test_vad import quiet, run, voice  # noqa: E402

SR = 16000


class ShortWords(unittest.TestCase):
    SIG = np.concatenate([quiet(1.0), voice(0.3), quiet(1.5)])      # "응" 한 음절

    def test_short_word_kept(self):
        self.assertEqual(len([c for c in run(Segmenter(sr=SR, min_utt_s=0.3), self.SIG) if c.final]), 1)

    def test_dropped_short_word_is_reported(self):
        dropped = []
        seg = Segmenter(sr=SR, min_utt_s=0.6, on_drop=lambda s, peak: dropped.append((s, peak)))
        self.assertEqual(run(seg, self.SIG), [])
        self.assertEqual(len(dropped), 1)
        self.assertGreater(dropped[0][1], 0.01)


class Flush(unittest.TestCase):
    def test_flush_hands_over_open_utterance(self):
        seg = Segmenter(sr=SR)
        run(seg, np.concatenate([quiet(1.0), voice(0.8)]))
        self.assertTrue(seg.in_speech)
        cut = seg.flush()
        self.assertTrue(cut.final)
        self.assertGreater(len(cut.audio) / SR, 0.7)
        self.assertFalse(seg.in_speech)
        self.assertIsNone(seg.flush())


class VoiceRun(unittest.TestCase):
    def test_voice_over_echo_has_length(self):
        li = Listener()
        run_li = lambda sig, sp=True: [li.feed(sig[i:i + 480], sp) for i in range(0, len(sig), 480)]  # noqa: E731
        run_li(speechlike(2.0, 0.001), False)
        run_li(speechlike(2.0, 0.05))
        self.assertEqual(li.voice_s(), 0.0)
        run_li(speechlike(0.6, 0.05) + speechlike(0.6, 0.2))
        self.assertAlmostEqual(li.voice_s(), 0.6, delta=0.15)


class StripEcho(unittest.TestCase):
    def test_strips_assistant_tail(self):
        self.assertEqual(strip_echo("하나 있어요 근데 그거 말고", "지금 기다리는 작업이 하나 있어요."), "근데 그거 말고")

    def test_keeps_own_words(self):
        self.assertEqual(strip_echo("화면 꺼 줘", "작업이 하나 있어요."), "화면 꺼 줘")
        self.assertEqual(strip_echo("있어", "작업이 하나 있어요."), "")


class SpeakingVoice(test_daemon.FakeVoice):
    on = False

    def busy(self):
        return self.on

    def sounding(self, echo_s=0.2):
        return self.on


def feed(d, sig):
    for i in range(0, len(sig), 480):
        d._on_audio(sig[i:i + 480])


def drain(d):
    out = []
    while not d.utt_q.empty():
        out.append(d.utt_q.get_nowait())
    return out


class DaemonOverlap(unittest.TestCase):
    def setUp(self):
        self.d = make()
        self.d.wake("test")
        self.d.voice = SpeakingVoice()
        drain(self.d)

    def test_speech_open_when_speaking_starts_is_not_lost(self):
        feed(self.d, np.concatenate([quiet(1.0), voice(1.0)]))
        self.assertTrue(self.d.seg.in_speech)
        self.d.voice.on = True                                       # 비서가 말하기 시작
        feed(self.d, quiet(0.3))
        cuts = drain(self.d)
        self.assertEqual([c.final for c in cuts], [True])
        self.assertGreater(len(cuts[0].audio) / SR, 0.9)

    def test_voice_over_end_of_speech_keeps_its_start(self):
        feed(self.d, speechlike(2.0, 0.001))                         # 방 바닥
        self.d.voice.on = True
        feed(self.d, speechlike(2.0, 0.05))                          # 제 목소리 되먹임
        feed(self.d, speechlike(0.6, 0.05) + speechlike(0.6, 0.2))   # 주인이 말 끝에 얹음
        self.d.voice.last_text = "작업이 하나 있어요."
        self.d.voice.on = False                                      # 비서 말 끝
        feed(self.d, np.concatenate([speechlike(0.5, 0.2), speechlike(3.0, 0.001)]))
        cuts = [c for c in drain(self.d) if c.final]
        self.assertEqual(len(cuts), 1)
        self.assertGreater(len(cuts[0].audio) / SR - cuts[0].tail_s, 0.5 + 0.5)   # 겹친 앞부분까지
        self.assertEqual(self.d._echo_seq[:2], (cuts[0].seq, "작업이 하나 있어요."))
        self.d.stt.transcribe = lambda a: "하나 있어요 근데 그거 말고"
        self.assertEqual(self.d._hear_cut(cuts[0]), "근데 그거 말고")

    def test_echo_that_stops_with_speech_is_dropped(self):
        feed(self.d, speechlike(2.0, 0.001))
        self.d.voice.on = True
        feed(self.d, speechlike(2.0, 0.05))
        feed(self.d, speechlike(0.6, 0.2))                           # 크게 튄 제 목소리(사람으로 잡힘)
        self.d.voice.on = False
        feed(self.d, speechlike(3.0, 0.001))                         # 끝나자 조용
        cuts = [c for c in drain(self.d) if c.final]
        self.assertEqual(len(cuts), 1)
        self.d.stt.transcribe = lambda a: "하나 있어요"
        self.assertEqual(self.d._hear_cut(cuts[0]), "")

    def test_no_overlap_no_prepend(self):
        feed(self.d, speechlike(2.0, 0.001))
        self.d.voice.on = True
        feed(self.d, speechlike(2.0, 0.05))
        self.d.voice.on = False
        feed(self.d, speechlike(3.0, 0.001))
        self.assertEqual(drain(self.d), [])
        self.assertEqual(self.d._echo_seq[0], -1)


class AnswerWords(unittest.TestCase):
    def test_short_answer_after_question_kept(self):
        d = make()
        d.voice.last_text, d.voice.said_at = "지금 다시 시킬까요?", time.time()
        self.assertTrue(d._answering())
        d.voice.said_at = time.time() - 60
        self.assertFalse(d._answering())
        d.voice.last_text, d.voice.said_at = "다시 시켰어요.", time.time()
        self.assertFalse(d._answering())


if __name__ == "__main__":
    unittest.main()
