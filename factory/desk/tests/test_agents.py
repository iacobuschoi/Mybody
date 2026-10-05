import json
import os
import shutil
import subprocess
import tempfile
import unittest

from desk.dashboard import read_agents


def fake(out):
    return lambda *a, **k: subprocess.CompletedProcess(a, 0, stdout=out, stderr="")


class ReadAgents(unittest.TestCase):
    def setUp(self):
        self.jobs = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.jobs)

    def job(self, jid, state, timeline=()):
        os.makedirs(os.path.join(self.jobs, jid))
        with open(os.path.join(self.jobs, jid, "state.json"), "w") as f:
            json.dump(state, f)
        with open(os.path.join(self.jobs, jid, "timeline.jsonl"), "w") as f:
            f.writelines(json.dumps(t) + "\n" for t in timeline)

    def test_background_only_with_state(self):
        items = [
            {"kind": "interactive", "name": "사람", "status": "busy", "startedAt": 1},
            {"kind": "background", "name": "끝남", "status": "idle", "state": "done", "startedAt": 10},
            {"kind": "background", "name": "막힘", "status": "idle", "state": "blocked", "startedAt": 20},
            {"kind": "background", "name": "도는 중", "status": "busy", "state": "working", "startedAt": 30},
            {"kind": "background", "id": "abc", "status": "waiting", "startedAt": 40},
            {"kind": "background", "name": "꺼짐", "status": "idle", "state": "stopped", "startedAt": 50},
        ]
        rows = read_agents(run=fake(json.dumps(items)), jobs=self.jobs)
        self.assertEqual([(r["name"], r["state"]) for r in rows],
                         [("abc", "needs"), ("막힘", "needs"), ("도는 중", "working"), ("꺼짐", "stopped"), ("끝남", "done")])
        self.assertEqual(rows[2]["started"], 30)

    def test_job_files_give_detail_why_and_last_line(self):
        self.job("j1", {"state": "working", "detail": "Running **tests**", "updatedAt": "2026-10-05T08:40:37.913Z"},
                 [{"state": "working", "detail": "a", "text": "첫 문단\n\n- 마지막 `문단` 이에요"},
                  {"state": "working", "detail": "b", "text": ""}])
        self.job("j2", {"state": "blocked", "detail": "awaiting go-ahead", "tempo": "blocked",
                        "needs": "choose: allow or deny"})
        items = [{"kind": "background", "id": "j1", "name": "일", "status": "busy", "state": "working", "startedAt": 5},
                 {"kind": "background", "id": "j2", "name": "권한", "status": "busy", "state": "working",
                  "waitingFor": "permission", "startedAt": 6}]
        rows = read_agents(run=fake(json.dumps(items)), jobs=self.jobs)
        need, work = rows
        self.assertEqual((need["name"], need["state"]), ("권한", "needs"))
        self.assertEqual(need["why"], "choose: allow or deny · permission")
        self.assertEqual(need["detail"], "awaiting go-ahead")
        self.assertEqual(work["detail"], "Running tests")
        self.assertEqual(work["last"], "마지막 문단 이에요")
        self.assertEqual(work["updated"], 1791189637913)

    def test_last_line_only_from_current_state(self):
        self.job("j1", {"state": "working", "detail": "다시 일함"},
                 [{"state": "done", "text": "지난번 끝 보고"}, {"state": "working", "text": ""}])
        items = [{"kind": "background", "id": "j1", "name": "일", "state": "working", "startedAt": 5}]
        self.assertEqual(read_agents(run=fake(json.dumps(items)), jobs=self.jobs)[0]["last"], "")

    def test_done_waiting_for_owner_goes_to_top_for_a_day(self):
        import time
        now = time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime())
        self.job("j1", {"state": "done", "detail": "model upgraded; announcement pending owner", "updatedAt": now})
        self.job("j2", {"state": "done", "detail": "awaiting owner", "updatedAt": "2026-01-01T00:00:00.000Z"})
        items = [{"kind": "background", "id": j, "name": j, "state": "done", "startedAt": 5} for j in ("j1", "j2")]
        rows = read_agents(run=fake(json.dumps(items)), jobs=self.jobs)
        self.assertEqual([(r["name"], r["state"]) for r in rows], [("j1", "needs"), ("j2", "done")])

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

    def test_task_card_replaces_status_card(self):
        from desk import dashboard
        self.assertIn('id="taskCard"', dashboard.PAGE)
        self.assertIn("작업 현황", dashboard.PAGE)
        for gone in ('id="briefCard"', 'id="agentsCard"', "지금 상태"):
            self.assertNotIn(gone, dashboard.PAGE)


if __name__ == "__main__":
    unittest.main()
