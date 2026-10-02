"""소리 장치 고르기 — 스피커폰을 빼면 다음 이름으로, 다시 꽂으면 돌아옴. 장치 감시가 데몬을 다시 열게 하는지."""
import os
import sys
import unittest

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from desk import devices  # noqa: E402
from tests.test_clap import clap, silence  # noqa: E402
from tests.test_daemon import make  # noqa: E402

JABRA, BRIO, MINI = "Jabra Speak2 40 UC", "Brio 100", "Mac mini 스피커"


class Pick(unittest.TestCase):
    def test_first_present(self):
        self.assertEqual(devices.pick(["Jabra", "Brio"], "input", [BRIO, JABRA]), JABRA)
        self.assertEqual(devices.pick(["Jabra", "Brio"], "input", [BRIO]), BRIO)          # 뺌 → Brio
        self.assertEqual(devices.pick(["jabra", "Mac mini"], "output", [MINI, JABRA]), JABRA)

    def test_old_style_and_missing(self):
        self.assertEqual(devices.pick("Brio", "input", [BRIO]), BRIO)
        self.assertEqual(devices.pick("", "input", [BRIO]), "")
        self.assertEqual(devices.pick(["Jabra"], "input", [BRIO]), "")                      # 없음 → 시스템 기본
        saved, devices.present = devices.present, lambda kind: None
        try:
            self.assertEqual(devices.pick(["Jabra", "Brio"], "input"), "Jabra")             # 목록을 모름 → 첫 이름
        finally:
            devices.present = saved

    def test_names(self):
        self.assertEqual(devices.names(" "), [])
        self.assertEqual(devices.names(["Jabra", "", "Brio"]), ["Jabra", "Brio"])


class DaemonDevices(unittest.TestCase):
    def setUp(self):
        self.refreshed = 0
        self._saved = (devices.present, devices.refresh)
        devices.refresh = lambda: setattr(self, "refreshed", self.refreshed + 1)
        self.have = {"input": [JABRA, BRIO], "output": [JABRA, MINI]}
        devices.present = lambda kind: self.have[kind]

    def tearDown(self):
        devices.present, devices.refresh = self._saved

    def desk(self):
        d = make()
        d.cfg["audio"]["device"] = ["Jabra", "Brio"]
        d.cfg["audio"]["side_device"] = ["Brio", "Jabra"]
        d.cfg["tts"]["device"] = ["Jabra", "Mac mini 스피커"]
        return d

    def test_unplug_and_replug(self):
        d = self.desk()
        self.assertEqual(d._use_devices(d._pick_devices()), (JABRA, BRIO))
        self.assertEqual((d.voice.device, self.refreshed), (JABRA, 0))     # 처음 열 땐 새로 읽을 것 없음
        self.have = {"input": [BRIO], "output": [MINI]}                     # 스피커폰 뺌
        self.assertEqual(d._use_devices(d._pick_devices()), (BRIO, BRIO))
        self.assertEqual((d.voice.device, self.refreshed), (MINI, 1))
        self.have = {"input": [JABRA, BRIO], "output": [JABRA, MINI]}      # 다시 꽂음
        self.assertEqual(d._use_devices(d._pick_devices()), (JABRA, BRIO))
        self.assertEqual((d.voice.device, self.refreshed), (JABRA, 2))
        d._use_devices(d._pick_devices())                                   # 그대로면 다시 읽지 않음
        self.assertEqual(self.refreshed, 2)

    def test_side_device_defaults_to_mic(self):
        d = self.desk()
        d.cfg["audio"]["side_device"] = ""
        self.assertEqual(d._pick_devices(), (JABRA, JABRA, JABRA))

    def test_side_mic_claps_wake(self):
        """박수 마이크가 따로면 듣기 마이크(스피커폰) 소리로는 박수를 세지 않고, 따로 들은 소리로 셈."""
        d = self.desk()
        sig = np.concatenate([silence(1.0), clap(), silence(0.3), clap(), silence(1.2)])
        quiet = silence(0.03)
        for i in range(0, len(sig), 480):
            d._on_audio(sig[i:i + 480], [quiet])                    # 스피커폰엔 박수가 있어도 무시
        self.assertEqual(d.mode, "sleep")
        for i in range(0, len(sig), 480):
            d._on_audio(quiet, [sig[i:i + 480]])                    # Brio 에 들어온 박수
        self.assertEqual(d.mode, "awake")

    def test_side_mic_barge(self):
        """말하는 동안 끼어들기도 따로 듣는 마이크로 — 스피커폰은 제가 말하는 동안 마이크를 닫으므로."""
        d = self.desk()
        d.mode = "awake"
        fed = []
        d.voice.busy = lambda: True
        d.barge.feed = lambda a, speaking: fed.append((len(a), speaking))
        d._on_audio(np.zeros(480, dtype=np.float32), [np.ones(480, dtype=np.float32)] * 2)
        self.assertEqual(fed, [(480, True), (480, True)])

if __name__ == "__main__":
    unittest.main()
