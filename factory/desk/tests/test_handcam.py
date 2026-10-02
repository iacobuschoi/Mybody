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

    def test_state_live_only_when_fresh(self):
        self.assertEqual(dashboard.handcam_state(), {"live": False, "text": ""})
        self.write("고정 · 주먹", time.time())
        self.assertEqual(dashboard.handcam_state(), {"live": True, "text": "고정 · 주먹"})
        self.write("고정 · 주먹", time.time() - 10)
        self.assertFalse(dashboard.handcam_state()["live"])

    def test_http_touches_want_and_streams_jpeg(self):
        self.write("손 없음", time.time())
        with socket.socket() as s:
            s.bind(("127.0.0.1", 0))
            port = s.getsockname()[1]
        srv = dashboard.serve(dashboard.Board(), {}, port=port)
        try:
            got = json.load(urllib.request.urlopen(f"http://127.0.0.1:{port}/handcam.json", timeout=3))
            self.assertEqual(got, {"live": True, "text": "손 없음"})
            self.assertLess(time.time() - os.stat(os.path.join(self.tmp.name, "want")).st_mtime, 3)
            r = urllib.request.urlopen(f"http://127.0.0.1:{port}/handcam.mjpg", timeout=3)
            self.assertIn("multipart/x-mixed-replace", r.headers["Content-Type"])
            head = r.read(60)
            self.assertTrue(head.startswith(b"--frame\r\nContent-Type: image/jpeg"), head)
            self.assertIn(b"Content-Length: 8\r\n\r\n\xff\xd8", head)
            r.close()
        finally:
            srv.shutdown()

    def test_page_has_camera_card(self):
        self.assertIn('id="handCard"', dashboard.PAGE)
        self.assertIn("/handcam.mjpg", dashboard.PAGE)


if __name__ == "__main__":
    unittest.main()
