import io
import json
import os
import shutil
import tempfile
import time
import unittest

from desk import usage

NOW = 1_800_000_000.0


class Usage(unittest.TestCase):
    def setUp(self):
        d = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, d)
        self.path = os.path.join(d, "u", "claude-usage.json")

    def test_picks_only_rate_limit_numbers(self):
        payload = {"session_id": "s", "transcript_path": "/x", "model": {"display_name": "Opus"},
                   "rate_limits": {"five_hour": {"used_percentage": 23.5, "resets_at": NOW + 3600},
                                   "seven_day": {"used_percentage": 41.2, "resets_at": NOW + 3 * 86400}}}
        usage.record(payload, self.path, now=NOW)
        with open(self.path) as f:
            saved = json.load(f)
        self.assertEqual(set(saved), {"five_hour", "seven_day"})
        self.assertEqual(saved["five_hour"], {"used": 23.5, "resets_at": NOW + 3600, "t": NOW})
        rows = usage.view(self.path, now=NOW + 60)
        self.assertEqual([(r["label"], r["known"], r["left"], r["resets"]) for r in rows],
                         [("5시간", True, 76, "59분"), ("주간", True, 59, "2일 23시간")])

    def test_unknown_when_missing(self):
        rows = usage.view(self.path, now=NOW)
        self.assertEqual([r["known"] for r in rows], [False, False])
        self.assertEqual(usage.record({"model": {}}, self.path), {})   # rate_limits 없으면 파일도 안 만듦
        self.assertFalse(os.path.exists(self.path))

    def test_reset_passed_is_unknown_not_zero(self):
        usage.record({"rate_limits": {"five_hour": {"used_percentage": 90, "resets_at": NOW + 10}}}, self.path, now=NOW)
        r = usage.view(self.path, now=NOW + 20)[0]
        self.assertFalse(r["known"])
        self.assertEqual(r["note"], "초기화 지남")

    def test_stale_value_says_how_old(self):
        usage.record({"rate_limits": {"seven_day": {"used_percentage": 10, "resets_at": NOW + 86400 * 5}}}, self.path, now=NOW)
        usage.record({"rate_limits": {"five_hour": {"used_percentage": 5, "resets_at": NOW + 7200}}}, self.path, now=NOW + 3600)
        five, week = usage.view(self.path, now=NOW + 3600)
        self.assertEqual((five["note"], week["note"]), ("", "1시간 0분 전 값"))   # 빠진 창은 전 값을 그 시각과 함께 둠

    def test_bad_values_ignored(self):
        usage.record({"rate_limits": {"five_hour": {"used_percentage": "50"}, "seven_day": {"used_percentage": 140}}}, self.path)
        self.assertEqual([r["known"] for r in usage.view(self.path)], [False, False])

    def test_statusline_records_and_prints(self):
        payload = {"model": {"display_name": "Opus"}, "session_id": "secret-ish",
                   "rate_limits": {"five_hour": {"used_percentage": 30, "resets_at": time.time() + 600}}}
        out = io.StringIO()
        usage.statusline(io.StringIO(json.dumps(payload)), out, self.path)
        self.assertTrue(out.getvalue().startswith("Opus · 5시간 30% ("), out.getvalue())
        with open(self.path) as f:
            self.assertNotIn("secret-ish", f.read())

    def test_statusline_survives_garbage(self):
        out = io.StringIO()
        usage.statusline(io.StringIO("not json"), out, self.path)
        self.assertEqual(out.getvalue(), "\n")


if __name__ == "__main__":
    unittest.main()
