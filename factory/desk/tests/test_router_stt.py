import os
import sys
import unittest

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from desk.router import route  # noqa: E402
from desk.stt import clean_transcript  # noqa: E402
from desk.vad import Segmenter  # noqa: E402


class RouterTest(unittest.TestCase):
    def k(self, s, muted=False):
        return route(s, muted).kind

    def test_local_commands(self):
        cases = {
            "화면 꺼 줘": "sleep", "이제 잘게": "sleep", "오늘은 끝": "sleep",
            "조용히 해": "mute", "잠깐 듣지 마": "mute", "그만 들어": "mute",
            "멈춰": "stop", "그만": "stop", "취소": "stop",
            "브리핑해 줘": "brief", "지금 상황 어때?": "brief",
            "소리 키워": "louder", "소리 줄여": "softer",
            "뭐라고?": "repeat", "지금 몇 시야": "time",
        }
        for s, want in cases.items():
            self.assertEqual(self.k(s), want, s)

    def test_long_sentences_go_to_claude(self):
        for s in ["화면 꺼지기 전에 오늘 할 일 브리핑해 줘",
                  "가계부 앱 실기기 시험 돌려 줘",
                  "새 앱 만들자, 수능 영단어 음성 퀴즈"]:
            self.assertEqual(self.k(s), "claude", s)

    def test_muted_only_hears_unmute(self):
        self.assertEqual(self.k("다시 들어", muted=True), "unmute")
        self.assertEqual(self.k("화면 꺼 줘", muted=True), "ignore")
        self.assertEqual(self.k("가계부 앱 시험 돌려", muted=True), "ignore")

    def test_empty_and_one_char(self):
        self.assertEqual(self.k(""), "ignore")
        self.assertEqual(self.k("아"), "ignore")


class SttFilterTest(unittest.TestCase):
    def test_hallucinations_dropped(self):
        for s in ["시청해 주셔서 감사합니다.", "구독과 좋아요 부탁드립니다", "MBC 뉴스 이덕영입니다.",
                  "감사합니다.", "Thank you.", "아아아아아아아", "네", "아프지 않게, " * 25]:
            self.assertEqual(clean_transcript(s), "", s)

    def test_real_commands_kept(self):
        for s in ["브리핑해 줘", "가계부 앱 실기기 시험 돌려 줘", "화면 꺼"]:
            self.assertEqual(clean_transcript(s), s)

    def test_segment_scores(self):
        segs = [{"text": "화면 꺼", "no_speech_prob": 0.1, "avg_logprob": -0.3},
                {"text": " 시청", "no_speech_prob": 0.9, "avg_logprob": -0.2}]
        self.assertEqual(clean_transcript("", segs), "화면 꺼")


class SegmenterTest(unittest.TestCase):
    def test_cuts_one_utterance(self):
        sr = 16000
        rng = np.random.default_rng(1)
        quiet = (rng.standard_normal(sr) * 0.002).astype(np.float32)
        t = np.arange(int(sr * 1.2)) / sr
        voice = (0.2 * np.sin(2 * np.pi * 180 * t) * (0.6 + 0.4 * np.sin(2 * np.pi * 3 * t))).astype(np.float32)
        sig = np.concatenate([quiet, voice, quiet, quiet])
        seg = Segmenter(sr=sr)
        seg._vad = None                      # 시험은 에너지로만
        outs = []
        for i in range(0, len(sig), 480):
            outs += seg.feed(sig[i:i + 480])
        self.assertEqual(len(outs), 1)
        self.assertGreater(len(outs[0]) / sr, 1.0)

    def test_weak_voice_under_dc_and_hum(self):
        # Brio 100 · 침대(2.5m): 직류 +0.008 과 58Hz 험이 바닥을 채우고 말은 그보다 작음 — 전체 크기로는 1.1배
        sr = 16000
        rng = np.random.default_rng(2)
        t = np.arange(int(sr * 4.7)) / sr
        sig = 0.008 + 0.004 * np.sin(2 * np.pi * 58 * t) + rng.standard_normal(len(t)) * 0.0007
        tv = t[: int(sr * 1.2)]
        voice = sum(np.sin(2 * np.pi * 180 * k * tv) / k for k in range(1, 8)) * 0.006 * (0.6 + 0.4 * np.sin(2 * np.pi * 3 * tv))
        sig[int(sr * 2.0): int(sr * 2.0) + len(voice)] += voice
        sig = sig.astype(np.float32)
        seg = Segmenter(sr=sr)
        outs = []
        for i in range(0, len(sig), 480):
            outs += seg.feed(sig[i:i + 480])
        self.assertEqual(len(outs), 1)
        self.assertGreater(len(outs[0]) / sr, 1.0)

    def test_paused_hears_nothing(self):
        seg = Segmenter()
        seg._vad = None
        seg.pause()
        t = np.arange(16000) / 16000
        self.assertEqual(seg.feed((0.3 * np.sin(2 * np.pi * 200 * t)).astype(np.float32)), [])


if __name__ == "__main__":
    unittest.main()
