"""신경망 목소리 시험 — Supertonic 과 스피커를 가짜로 끼우고: 문장마다 틀기 · 멈추기 · 못 쓰면 say 로."""
import os
import sys
import time
import types
import unittest

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from desk import mac, tts  # noqa: E402

SR = 1000
REAL_VOICE = mac.Voice          # test_daemon 이 mac.Voice 를 가짜로 바꿔 두므로 진짜를 잡아 둠
SAID: list[list[str]] = []


class FakeTTS:
    fail = False

    def __init__(self, model="supertonic-3"):
        if FakeTTS.fail:
            raise RuntimeError("모델 없음")
        self.sample_rate = SR
        self.made: list[str] = []

    def get_voice_style(self, name):
        return name

    def synthesize(self, text, voice_style, lang=None, total_steps=5, speed=1.05):
        self.made.append(text)
        self.last = (voice_style, speed)
        return np.full((1, SR // 2), 0.1, dtype=np.float32), np.array([0.5])   # 문장마다 0.5초


class FakeStream:
    written: list[int] = []
    peaks: list[float] = []
    slow = 0.0

    def __init__(self, samplerate, channels, dtype, device=None):
        FakeStream.device = device

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False

    def write(self, x):
        FakeStream.written.append(len(x))
        FakeStream.peaks.append(float(np.max(np.abs(x))) if len(x) else 0.0)
        time.sleep(FakeStream.slow)

    def abort(self):
        FakeStream.written.append(-1)


def install_fakes():
    sys.modules["supertonic"] = types.SimpleNamespace(TTS=FakeTTS)
    sys.modules["sounddevice"] = types.SimpleNamespace(
        OutputStream=FakeStream,
        query_devices=lambda: [{"name": "Brio 100", "max_output_channels": 0},
                               {"name": "Mac mini 스피커", "max_output_channels": 2}])
    REAL_VOICE.say = lambda self, text, block=False, opts=None: SAID.append([(opts or {}).get("voice") or self.voice, text])
    mac.Voice = REAL_VOICE
    mac.best_voice = lambda name: name


class NeuralVoiceTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls._saved = (sys.modules.get("supertonic"), sys.modules.get("sounddevice"), REAL_VOICE.say, mac.Voice,
                      mac.best_voice)
        install_fakes()

    @classmethod
    def tearDownClass(cls):
        st, sd, REAL_VOICE.say, mac.Voice, mac.best_voice = cls._saved
        for name, mod in (("supertonic", st), ("sounddevice", sd)):
            if mod is None:
                sys.modules.pop(name, None)
            else:
                sys.modules[name] = mod

    def setUp(self):
        SAID.clear()
        FakeStream.written, FakeStream.peaks, FakeStream.slow, FakeTTS.fail = [], [], 0.0, False

    def voice(self, **k):
        v = mac.make_voice({"engine": "supertonic", "voice": "Yuna", "rate": 190, "device": "Mac mini", **k})
        self.assertTrue(v.ready.wait(2))
        return v

    def test_speaks_each_sentence_on_named_speaker(self):
        v = self.voice()
        v.say("첫 문장이에요. 두 번째예요!  세 번째?", block=True)
        self.assertEqual(v._tts.made[1:], ["첫 문장이에요.", "두 번째예요!", "세 번째?"])   # [0] 은 미리 데우기
        self.assertEqual(FakeStream.device, 1)
        self.assertEqual(sum(n for n in FakeStream.written if n > 0), 3 * SR // 2 + 3 * int(SR * 0.15))
        self.assertFalse(v._speaking)
        self.assertEqual(v.last_text, "첫 문장이에요. 두 번째예요!  세 번째?")
        self.assertEqual(SAID, [])

    def test_stop_cuts_off_and_is_not_busy(self):
        FakeStream.slow = 0.05
        v = self.voice()
        v.say("길게 말하는 중이에요. 아직 남았어요.")
        time.sleep(0.12)
        self.assertTrue(v.busy())
        v.stop()
        time.sleep(0.3)
        self.assertIn(-1, FakeStream.written)                    # 틀던 소리를 끊음
        self.assertLess(sum(n for n in FakeStream.written if n > 0), SR)
        v._until = 0
        self.assertFalse(v.busy())

    def test_falls_back_to_say_without_model(self):
        FakeTTS.fail = True
        v = self.voice()
        self.assertIn("모델 없음", v.error)
        self.assertEqual(v.engine, "say Yuna")
        v.say("안녕하세요.")
        self.assertEqual(SAID, [["Yuna", "안녕하세요."]])

    def test_say_engine_stays_plain_voice(self):
        v = mac.make_voice({"voice": "Yuna", "rate": 190, "device": ""})
        self.assertIs(type(v), REAL_VOICE)

    def test_new_say_replaces_old(self):
        FakeStream.slow = 0.02
        v = self.voice()
        v.say("하나. 둘. 셋. 넷.")
        time.sleep(0.05)
        v.say("새 말.", block=True)
        self.assertEqual(v.last_text, "새 말.")
        self.assertFalse(v._speaking)

    def test_preview_opts_change_style_pitch_volume_once(self):
        v = self.voice()
        v.say("한 문장.", block=True, opts={"engine": "supertonic", "style": "M2", "speed": 1.0, "pitch": 12,
                                          "volume": 0.5})
        self.assertEqual(v._tts.last, ("M2", 0.5))              # 한 옥타브 올릴 만큼 느리게 만들고
        self.assertEqual(sum(n for n in FakeStream.written if n > 0), SR // 4 + int(SR * 0.15))   # 반으로 줄여 틂
        self.assertAlmostEqual(max(FakeStream.peaks), 0.05, places=5)
        v.say("다시.", block=True)
        self.assertEqual(v._tts.last, ("F1", 1.05))             # 저장한 값은 그대로

    def test_configure_applies_without_restart(self):
        v = self.voice()
        v.configure({"engine": "supertonic", "style": "M1", "speed": 1.2, "pitch": 0, "volume": 1.5})
        v.say("크게.", block=True)
        self.assertEqual(v._tts.last, ("M1", 1.2))
        self.assertAlmostEqual(max(FakeStream.peaks), 0.15, places=5)
        v.configure({"engine": "say", "voice": "Yuna", "rate": 220})
        self.assertEqual(v.engine, "say Yuna")
        v.say("예비.")
        self.assertEqual(SAID, [["Yuna", "예비."]])

    def test_preview_say_on_neural_voice(self):
        v = self.voice()
        v.say("예비로.", opts={"engine": "say", "voice": "Yuna"})
        self.assertEqual(SAID, [["Yuna", "예비로."]])


class ShiftPitchTest(unittest.TestCase):
    def test_up_is_shorter_and_zero_is_same(self):
        x = np.sin(np.arange(1000) / 5).astype(np.float32)
        self.assertIs(tts.shift_pitch(x, 0), x)
        self.assertEqual(len(tts.shift_pitch(x, 12)), 500)
        self.assertEqual(len(tts.shift_pitch(x, -12)), 2000)


if __name__ == "__main__":
    unittest.main()
