"""모델 고르기 — 이름 · 말 알아듣기 · 라우터 · 데몬에서 [brain] model 만 고쳐 쓰고 바로 적용."""
import os
import sys
import tempfile
import tomllib
import unittest
from unittest import mock

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from desk import config, model_settings  # noqa: E402
from desk.router import route  # noqa: E402
from tests.test_daemon import make  # noqa: E402

OPUS, SONNET, HAIKU = (m[0] for m in model_settings.MODELS)


class ResolveTest(unittest.TestCase):
    def test_names(self):
        for text, want in [("claude-sonnet-5", SONNET), ("Haiku 4.5", HAIKU), ("opus", OPUS), ("Sonnet", SONNET),
                           ("빠른 모드", SONNET), ("제일 빠른 모드", HAIKU), ("정확한 모드", OPUS), ("하이쿠로", HAIKU)]:
            self.assertEqual(model_settings.resolve(text), want, text)
        for bad in ("", "gpt", "아무거나"):
            self.assertIsNone(model_settings.resolve(bad))

    def test_current_and_spoken(self):
        self.assertEqual(model_settings.current(""), OPUS)          # 비어 있으면 Claude Code 기본(Opus 5.5)
        self.assertEqual(model_settings.current("sonnet"), SONNET)
        self.assertEqual(model_settings.label(""), "Opus 5.5")
        self.assertEqual(model_settings.spoken(HAIKU), "하이쿠 4.5")


class RouteTest(unittest.TestCase):
    def test_voice_commands(self):
        for text, want in [("빠른 모드", SONNET), ("빠른 모드로 바꿔 줘", SONNET), ("하이쿠로 바꿔", HAIKU),
                           ("제일 빠른 모드로", HAIKU), ("정확한 모드로 해 줘", OPUS), ("오퍼스로 바꿔", OPUS),
                           ("기본 모드", OPUS)]:
            a = route(text)
            self.assertEqual((a.kind, a.arg), ("model", want), text)

    def test_other_talk_goes_to_claude(self):
        self.assertEqual(route("소넷 써 봤어?").kind, "claude")                      # 바꾸라는 말 없음
        self.assertEqual(route("빠른 모드로 가계부 앱 실기기 시험 돌려 줘").kind, "claude")   # 긴 말
        self.assertEqual(route("조용히 모드").kind, "mute")
        self.assertEqual(route("빠른 모드", muted=True).kind, "ignore")


class DaemonTest(unittest.TestCase):
    def setUp(self):
        fd, self.path = tempfile.mkstemp(suffix=".toml")
        os.write(fd, '[tts]\nengine = "say"\n\n[brain]\nworkdir = "~/lab/desk-assistant"\n'
                     'model = ""                        # 비우면 Claude Code 기본\ntimeout_s = 180\n'.encode())
        os.close(fd)
        self.p = mock.patch.object(config, "PATH", self.path)
        self.p.start()
        self.d = make()

    def tearDown(self):
        self.p.stop()
        os.unlink(self.path)

    def read(self):
        with open(self.path, "rb") as f:
            return tomllib.load(f)

    def test_board_shows_models(self):
        st = self.d.board.get()
        self.assertEqual(st["model"], OPUS)
        self.assertEqual([m["label"] for m in st["models"]], ["Opus 5.5", "Sonnet 5", "Haiku 4.5"])

    def test_toggle_saves_and_applies(self):
        self.assertEqual(self.d.model_set(""), "Opus 5.5")               # 빈 글 = 지금 모델만
        self.assertEqual(self.d.model_set(HAIKU), "Haiku 4.5")
        self.assertEqual(self.d.brain.model, HAIKU)
        self.assertEqual(self.d.board.get()["model"], HAIKU)
        got = self.read()
        self.assertEqual(got["brain"], {"workdir": "~/lab/desk-assistant", "model": HAIKU, "timeout_s": 180})
        self.assertEqual(got["tts"], {"engine": "say"})
        with self.assertRaises(ValueError):
            self.d.model_set("gpt-9")
        self.assertEqual(self.d.brain.model, HAIKU)

    def test_voice_fast_mode(self):
        self.d.mode = "awake"
        self.d.handle("빠른 모드")
        self.assertEqual(self.d.brain.model, SONNET)
        self.assertTrue(self.d.brain_q.empty())                          # Claude 로 안 감
        self.assertEqual(self.d.voice.said[-1], "소넷 5로 바꿨어요. 다음 말부터 적용돼요.")
        self.assertEqual(self.read()["brain"]["model"], SONNET)


if __name__ == "__main__":
    unittest.main()
