import os
import sys
import tomllib
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from desk import config  # noqa: E402

EXAMPLE = os.path.join(os.path.dirname(__file__), "..", "config.example.toml")


class ConfigExampleTest(unittest.TestCase):
    def test_keys_sit_where_the_code_reads_them(self):
        # TOML 은 [표] 아래 줄을 전부 그 표에 넣습니다 — 맨 위 값을 표 아래에 두면 설정이 안 먹습니다
        with open(EXAMPLE, "rb") as f:
            ex = tomllib.load(f)
        for key, val in ex.items():
            self.assertIn(key, config.DEFAULTS, key)
            want = config.DEFAULTS[key]
            self.assertEqual(isinstance(val, dict), isinstance(want, dict), key)
            if isinstance(val, dict) and want:            # [clap] 은 ClapConfig 로 가서 기본값이 비어 있음
                for k in val:
                    self.assertIn(k, want, f"[{key}] {k}")


if __name__ == "__main__":
    unittest.main()
