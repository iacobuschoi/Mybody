import json
import subprocess
import unittest

from desk.dashboard import read_agents


def fake(out):
    return lambda *a, **k: subprocess.CompletedProcess(a, 0, stdout=out, stderr="")


class ReadAgents(unittest.TestCase):
    def test_background_only_with_state(self):
        items = [
            {"kind": "interactive", "name": "사람", "status": "busy", "startedAt": 1},
            {"kind": "background", "name": "끝남", "status": "idle", "state": "done", "startedAt": 10},
            {"kind": "background", "name": "막힘", "status": "idle", "state": "blocked", "startedAt": 20},
            {"kind": "background", "name": "도는 중", "status": "busy", "state": "working", "startedAt": 30},
            {"kind": "background", "id": "abc", "status": "waiting", "startedAt": 40},
        ]
        rows = read_agents(run=fake(json.dumps(items)))
        self.assertEqual([(r["name"], r["state"]) for r in rows],
                         [("도는 중", "working"), ("abc", "waiting"), ("막힘", "waiting"), ("끝남", "done")])
        self.assertEqual(rows[0]["started"], 30)

    def test_unreadable_keeps_previous(self):
        self.assertIsNone(read_agents(run=fake("오류")))

        def boom(*a, **k):
            raise subprocess.TimeoutExpired(a, 10)
        self.assertIsNone(read_agents(run=boom))


class PageBuild(unittest.TestCase):
    def test_page_reloads_itself_when_build_changes(self):
        from desk import dashboard
        self.assertNotIn("@BUILD@", dashboard.PAGE)
        self.assertIn(f'const BUILD="{dashboard.BUILD}"', dashboard.PAGE)
        self.assertIn("location.reload()", dashboard.PAGE)

    def test_show_text_has_its_own_card(self):
        from desk import dashboard
        card = dashboard.PAGE.split('id="showCard"', 1)[1].split("</section>", 1)[0]
        self.assertIn('id="panel"', card)


if __name__ == "__main__":
    unittest.main()
