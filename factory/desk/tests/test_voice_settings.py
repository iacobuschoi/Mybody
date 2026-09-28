"""목소리 설정 창 — 받은 값 다듬기 · config.toml [tts] 만 고쳐 쓰기 · say 목소리 크기 · 데몬에서 바로 적용."""
import json
import os
import sys
import tempfile
import tomllib
import unittest
from unittest import mock

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from desk import config, mac, voice_settings  # noqa: E402

REAL_VOICE = mac.Voice
REAL_SAY = mac.Voice.say
def read(path):
    with open(path, "rb") as f:
        return tomllib.load(f)


VOICES = ["Yuna", "Yuna (Premium)", "Eddy (한국어(대한민국))"]

CONF = '''owner = "민종"

[tts]
engine = "supertonic"             # 신경망 목소리
style = "F1"                      # F1~F5 · M1~M5
speed = 1.05
device = "Mac mini 스피커"          # 소리 낼 장치 # 주석 속 #

[brain]
workdir = "~/lab/desk-assistant"
'''


class CleanTest(unittest.TestCase):
    def test_clamps_numbers_and_checks_names(self):
        c = voice_settings.clean({"engine": "supertonic", "style": "M3", "voice": "Yuna", "speed": 9, "pitch": -2.4,
                                  "volume": -1, "rate": 50, "device": "몰래"}, VOICES)
        self.assertEqual(c, {"engine": "supertonic", "style": "M3", "voice": "Yuna", "speed": 1.6, "pitch": -2,
                             "volume": 0.0, "rate": 120})     # device 같은 다른 키는 버림
        for bad in ({"engine": "espeak"}, {"engine": "say", "voice": "없는사람"}, {"engine": "supertonic", "style": "F9"}):
            with self.assertRaises(ValueError):
                voice_settings.clean(bad, VOICES)


class SaveTableTest(unittest.TestCase):
    def setUp(self):
        fd, self.path = tempfile.mkstemp(suffix=".toml")
        os.write(fd, CONF.encode())
        os.close(fd)

    def tearDown(self):
        os.unlink(self.path)

    def test_rewrites_only_tts_and_keeps_comments(self):
        config.save_table("tts", {"engine": "say", "style": "M2", "speed": 1.2, "pitch": 3, "volume": 0.8,
                                  "voice": "Yuna (Premium)"}, self.path)
        with open(self.path, encoding="utf-8") as f:
            text = f.read()
        got = tomllib.loads(text)
        self.assertEqual(got["tts"], {"engine": "say", "style": "M2", "speed": 1.2, "device": "Mac mini 스피커",
                                      "pitch": 3, "volume": 0.8, "voice": "Yuna (Premium)"})
        self.assertEqual(got["brain"], {"workdir": "~/lab/desk-assistant"})
        self.assertEqual(got["owner"], "민종")
        self.assertIn('engine = "say"                    # 신경망 목소리', text)   # 주석 자리 그대로
        self.assertIn("# 주석 속 #", text)
        self.assertLess(text.index("volume = 0.8"), text.index("[brain]"))       # 새 키는 [tts] 안에

    def test_adds_table_when_missing(self):
        os.unlink(self.path)
        config.save_table("tts", {"engine": "say"}, self.path)
        self.assertEqual(read(self.path), {"tts": {"engine": "say"}})
        open(self.path, "w").close()                      # tearDown 이 지울 것


class SayVolumeTest(unittest.TestCase):
    def test_volume_goes_into_say_text_and_caps_at_full(self):
        with mock.patch.object(mac.shutil, "which", return_value="/usr/bin/say"), \
                mock.patch.object(mac, "best_voice", side_effect=lambda n: n), \
                mock.patch.object(mac.subprocess, "Popen") as popen:
            v = REAL_VOICE("Yuna", 190, device="Mac mini", volume=0.4)
            REAL_SAY(v, "작게.")
            self.assertEqual(popen.call_args[0][0], ["say", "-r", "190", "-v", "Yuna", "-a", "Mac mini", "[[volm 0.40]] 작게."])
            REAL_SAY(v, "미리.", opts={"voice": "Eddy (한국어(대한민국))", "rate": 250, "volume": 1.4})
            self.assertEqual(popen.call_args[0][0], ["say", "-r", "250", "-v", "Eddy (한국어(대한민국))", "-a", "Mac mini", "미리."])
            self.assertEqual(v.last_text, "미리.")


class DaemonApplyTest(unittest.TestCase):
    def test_save_writes_config_and_configures_voice(self):
        from tests.test_daemon import make
        d = make()
        fd, path = tempfile.mkstemp(suffix=".toml")
        os.write(fd, CONF.encode())
        os.close(fd)
        try:
            with mock.patch.object(config, "PATH", path), mock.patch.object(mac, "korean_voices", return_value=VOICES):
                view = json.loads(d.tts_view())
                self.assertEqual(view["styles"][0], "F1")
                self.assertIn("Yuna", view["voices"])
                r = d.tts_save(json.dumps({"engine": "say", "voice": "Yuna", "rate": 200, "volume": 0.7}))
                self.assertIn("저장했어요", r)
                self.assertEqual(read(path)["tts"]["rate"], 200)
                self.assertEqual(d.voice.configured["volume"], 0.7)
                self.assertEqual(d.cfg["tts"]["engine"], "say")
                d.tts_test(json.dumps({"engine": "say", "voice": "Yuna", "volume": 0.3}))
                self.assertEqual(d.voice.said[-1], voice_settings.SAMPLE)
                self.assertEqual(d.voice.opts["volume"], 0.3)
                with self.assertRaises(ValueError):
                    d.tts_save(json.dumps({"engine": "say", "voice": "; rm -rf"}))
        finally:
            os.unlink(path)


if __name__ == "__main__":
    unittest.main()
