"""「손 카메라」 칸 — hand-mouse(overlay.py)가 쓰는 view.jpg · view.json 을 상태판으로."""
import json
import os
import socket
import tempfile
import time
import unittest
import urllib.request

from desk import dashboard


class HandcamTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.old = dashboard.HANDCAM
        dashboard.HANDCAM = self.tmp.name

    def tearDown(self):
        dashboard.HANDCAM = self.old
        self.tmp.cleanup()

    def write(self, text, t):
        with open(os.path.join(self.tmp.name, "view.json"), "w") as f:
            json.dump({"text": text, "t": t}, f)
        with open(os.path.join(self.tmp.name, "view.jpg"), "wb") as f:
            f.write(b"\xff\xd8fake\xff\xd9")

    def test_state_live_stuck_and_gone(self):
        self.assertEqual(dashboard.handcam_state(), {"shown": False, "live": False, "age": None, "text": ""})
        self.write("고정 · 주먹", time.time())
        st = dashboard.handcam_state()
        self.assertEqual((st["shown"], st["live"], st["text"]), (True, True, "고정 · 주먹"))
        self.write("고정 · 주먹", time.time() - 10)          # 멈춤: 칸은 보이되 live 아님
        st = dashboard.handcam_state()
        self.assertEqual((st["shown"], st["live"]), (True, False))
        self.assertGreaterEqual(st["age"], 10)
        self.write("고정 · 주먹", time.time() - 120)         # 꺼짐: 칸 숨김
        self.assertFalse(dashboard.handcam_state()["shown"])

    def test_http_touches_want_and_serves_latest_jpeg_each_time(self):
        self.write("손 없음", time.time())
        with socket.socket() as s:
            s.bind(("127.0.0.1", 0))
            port = s.getsockname()[1]
        srv = dashboard.serve(dashboard.Board(), {}, port=port)
        try:
            got = json.load(urllib.request.urlopen(f"http://127.0.0.1:{port}/handcam.json", timeout=3))
            self.assertEqual((got["live"], got["text"]), (True, "손 없음"))
            self.assertLess(time.time() - os.stat(os.path.join(self.tmp.name, "want")).st_mtime, 3)
            r = urllib.request.urlopen(f"http://127.0.0.1:{port}/handcam.jpg", timeout=3)
            self.assertEqual(r.headers["Content-Type"], "image/jpeg")
            self.assertEqual(r.headers["Cache-Control"], "no-store")
            self.assertEqual(r.read(), b"\xff\xd8fake\xff\xd9")
            with open(os.path.join(self.tmp.name, "view.jpg"), "wb") as f:   # 새 그림 → 다음 요청에 바로
                f.write(b"\xff\xd8new")
            self.assertEqual(urllib.request.urlopen(f"http://127.0.0.1:{port}/handcam.jpg", timeout=3).read(), b"\xff\xd8new")
        finally:
            srv.shutdown()

    def test_page_has_camera_card(self):
        self.assertIn('id="handCard"', dashboard.PAGE)
        self.assertIn("/handcam.jpg", dashboard.PAGE)
        self.assertIn("멈춤", dashboard.PAGE)


if __name__ == "__main__":
    unittest.main()
