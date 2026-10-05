"""폰 비서 앱 — 누르고 한 말은 왼손 주먹 말과 같은 길(direct)로 Claude 에게, 답은 맥 스피커가 아니라 폰으로 (주인 10월 5일 17:03)."""
import json
import os
import sys
import tempfile
import threading
import unittest
import urllib.request

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from desk import phone  # noqa: E402
from tests.test_daemon import make  # noqa: E402


class PhonePath(unittest.TestCase):
    def setUp(self):
        self.d = make()
        self.d.mode = "awake"
        threading.Thread(target=self.d._brain_worker, daemon=True).start()

    def tearDown(self):
        self.d._stop.set()
        self.d.brain_q.put(("끝", -1, False))

    def test_claude_answer_goes_to_phone_not_speaker(self):
        r = self.d.phone_ask("가계부 앱 실기기 시험 돌려 줘", wait_s=3)
        self.assertEqual(r["reply"], "네, 가계부 시험을 돌렸어요.")
        self.assertEqual(r["heard"], "가계부 앱 실기기 시험 돌려 줘")
        self.assertEqual(self.d.brain.asked, ["가계부 앱 실기기 시험 돌려 줘"])
        self.assertEqual(self.d.voice.said, [])                 # 맥 스피커로는 안 말함

    def test_same_path_as_left_fist(self):
        seen = []
        self.d.brain.ask = lambda text, direct=False: (seen.append(direct), ("네.", "네."))[1]
        self.d.phone_ask("오늘 승인할 거 있어?", wait_s=3)
        self.assertEqual(seen, [True])                          # [음성·주먹] — 무시 판정 없이 답함

    def test_muted_still_answers(self):
        self.d.mode = "muted"
        self.assertEqual(self.d.phone_ask("오늘 승인할 거 있어?", wait_s=3)["reply"], "네, 가계부 시험을 돌렸어요.")

    def test_ignored_reply_asks_again(self):
        self.d.brain.ask = lambda text, direct=False: (None, "")
        self.assertIn("다시 말해", self.d.phone_ask("음", wait_s=3)["reply"])

    def test_time_is_answered_on_phone(self):
        r = self.d.phone_ask("몇 시야", wait_s=3)
        self.assertIn("시", r["reply"])
        self.assertEqual(self.d.voice.said, [])

    def test_fist_path_unchanged(self):
        self.d.handle("가계부 앱 실기기 시험 돌려 줘", direct=True)
        for _ in range(100):
            if self.d.voice.said:
                break
            threading.Event().wait(0.02)
        self.assertEqual(self.d.voice.said, ["네, 가계부 시험을 돌렸어요."])


class FakeDesk:
    def phone_ask(self, text):
        return {"heard": text, "reply": "네."}

    def phone_hear(self, pcm):
        return "들은 말" if len(pcm) else ""

    def phone_state(self):
        return {"mode": "awake"}


class Server(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp()
        cls.p = phone.Phone(FakeDesk(), port=0, token_file=os.path.join(cls.tmp, "t"))
        cls.p.start(["127.0.0.1"])
        cls.base = f"http://127.0.0.1:{cls.p.servers[0].server_address[1]}"

    @classmethod
    def tearDownClass(cls):
        for s in cls.p.servers:
            s.shutdown()

    def req(self, path, body=None, tok=True):
        r = urllib.request.Request(self.base + path, data=body, headers={"X-Desk-Token": self.p.token} if tok else {})
        try:
            with urllib.request.urlopen(r, timeout=5) as f:
                return f.status, f.read()
        except urllib.error.HTTPError as e:
            return e.code, e.read()

    def test_token_required(self):
        self.assertEqual(self.req("/state", tok=False)[0], 401)
        self.assertEqual(self.req("/state")[0], 200)
        self.assertEqual(oct(os.stat(os.path.join(self.tmp, "t")).st_mode & 0o777), "0o600")

    def test_ask_and_talk(self):
        c, b = self.req("/ask", json.dumps({"text": "안녕"}).encode())
        self.assertEqual(json.loads(b)["reply"], "네.")
        c, b = self.req("/talk", b"\x00\x01" * 1600)
        self.assertEqual(json.loads(b)["heard"], "들은 말")

    def test_page(self):
        c, b = self.req("/")
        self.assertIn("누르고 말하기", b.decode())


class Peers(unittest.TestCase):
    def test_tailnet_only(self):
        self.assertTrue(phone.allowed_peer("100.83.32.36"))
        self.assertTrue(phone.allowed_peer("127.0.0.1"))
        self.assertFalse(phone.allowed_peer("192.168.0.10"))
        self.assertFalse(phone.allowed_peer("8.8.8.8"))


if __name__ == "__main__":
    unittest.main()
