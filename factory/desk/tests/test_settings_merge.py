import json
import os
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from desk.settings_merge import main, merge  # noqa: E402

GUARD = {"matcher": "Bash|PowerShell", "hooks": [{"type": "command", "command": "node guard.js", "timeout": 10}]}
SEED = {"permissions": {"deny": ["Read(*.p8)", "Read(.env)"]}, "hooks": {"PreToolUse": [GUARD]}}


class SettingsMergeTest(unittest.TestCase):
    def test_owner_edits_survive_reinstall(self):
        mine = {"permissions": {"allow": ["Bash(ls *)", "Bash(deskctl *)"], "deny": ["Read(*.p8)"]},
                "hooks": {"PreToolUse": [GUARD]}}                    # allow 더하고 deny 하나 지움
        self.assertEqual(merge(mine, SEED, SEED), mine)
        self.assertEqual(merge(mine, SEED, None), mine)             # 처음 합칠 때도 그대로

    def test_new_factory_rules_are_added_and_dropped_ones_removed(self):
        mine = {"permissions": {"allow": ["Bash(ls *)"], "deny": ["Read(*.p8)", "Read(.env)"]},
                "hooks": {"PreToolUse": [GUARD]}}
        new_seed = {"permissions": {"deny": ["Read(*.p8)", "Read(*.jks)"]}, "hooks": {"PreToolUse": [GUARD]}}
        out = merge(mine, new_seed, SEED)
        self.assertEqual(out["permissions"]["allow"], ["Bash(ls *)"])
        self.assertEqual(out["permissions"]["deny"], ["Read(*.p8)", "Read(*.jks)"])

    def test_guard_hook_is_put_back(self):
        mine = {"permissions": {"allow": ["Bash(ls *)"]}, "hooks": {}}
        self.assertIn(GUARD, merge(mine, SEED, SEED)["hooks"]["PreToolUse"])

    def test_files(self):
        with tempfile.TemporaryDirectory() as d:
            seed_p, mine_p = Path(d, "seed.json"), Path(d, "a", ".claude", "settings.json")
            seed_p.write_text(json.dumps(SEED))
            self.assertEqual(main(str(seed_p), str(mine_p)), "새로 만듦")
            text = mine_p.read_text().replace('"permissions": {', '"permissions": {\n "allow": ["Bash(ls *)"],\n', 1)
            mine_p.write_text(text)                                  # 사람이 손으로 고침(모양 그대로 둬야 함)
            self.assertEqual(main(str(seed_p), str(mine_p)), "그대로 둠(고친 것 유지)")
            self.assertEqual(mine_p.read_text(), text)
            mine_p.write_text("{ 고치다 만 파일")
            self.assertIn("건드리지 않음", main(str(seed_p), str(mine_p)))
            self.assertEqual(mine_p.read_text(), "{ 고치다 만 파일")


if __name__ == "__main__":
    unittest.main()
