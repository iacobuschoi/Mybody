"""과제 → 문제지 · 해설지 (desk/homework.py · study.py) — 가짜 교과서로 문제 · 그림 찾기, 진행률, 자동 열람 상태 · 회독, 나눠 올리기"""
import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pymupdf  # noqa: E402

import fake_textbook  # noqa: E402
from desk import homework as hw  # noqa: E402
from desk import study  # noqa: E402


class Numbers(unittest.TestCase):
    def test_parse_keeps_order_and_ranges(self):
        self.assertEqual(hw.parse_numbers("HW3: Problems 3.2, 3.5, 4.1 and 4.3~4.5  due 2026-11-17"),
                         ["3.2", "3.5", "4.1", "4.3", "4.4", "4.5"])
        self.assertEqual(hw.parse_numbers("P3.7, 3.7, 10.12"), ["3.7", "10.12"])

    def test_section_like_numbers_are_not_problems(self):
        self.assertEqual(hw.parse_numbers("see 3.2.1"), [])

    def test_numbers_only(self):
        self.assertTrue(hw.numbers_only("이름:홍길동 학번:2024001001\nHW3 Problems 3.2, 3.5, 4.1 제출 11/17"))
        self.assertFalse(hw.numbers_only("Derive the MLE of a Gaussian mean and explain why the estimator is unbiased. "
                                         "Then discuss problem 3.2 in detail with plots of the likelihood function."))
        self.assertFalse(hw.numbers_only("no numbers here"))

    def test_refs(self):
        self.assertEqual(hw.find_refs("see Figs. 3.4 and 3.5, Table 3.1, Example 3.2, Eq. (3.12), Figure P3.3"),
                         [("fig", "3.4"), ("fig", "3.5"), ("table", "3.1"), ("example", "3.2"), ("eq", "3.12"),
                          ("fig", "P3.3")])

    def test_progress_is_monotonic_and_reaches_100(self):
        seq = [hw.pct_at(k, f) for k, _, _ in hw.STAGES for f in (0, 0.5, 1)]
        self.assertEqual(seq, sorted(seq))
        self.assertEqual(hw.pct_at("solution", 1), 100)
        # 해설만(번호 모드 아님)일 때도 0 → 100
        skip = ("read", "find", "crop", "sheet")
        self.assertEqual(hw.pct_at("solve", 0, skip), 0)
        self.assertEqual(hw.pct_at("solution", 1, skip), 100)


class Textbook(unittest.TestCase):
    def setUp(self):
        self.d = tempfile.mkdtemp()

    def load(self, two):
        path = os.path.join(self.d, f"tb{int(two)}.pdf")
        fake_textbook.make(path, two)
        return hw.build_layout(path), pymupdf.open(path)

    def test_problem_not_section_heading(self):
        # 「3.2 Kirchhoff's Laws」 (1쪽 절 제목)이 아니라 연습문제의 3.2 (3쪽)
        for two in (False, True):
            lay, doc = self.load(two)
            got = hw.find_problem(lay, doc, "3.2")
            self.assertIsNotNone(got)
            self.assertEqual(got.clips[0].page, 2, two)
            self.assertIn("Fig. 3.4", got.text.replace("\n", " "))
            self.assertNotIn("3.3", got.text.split("\n")[-1][:4], two)    # 다음 문제에서 멈춤

    def test_two_column_stops_at_next_column_problem(self):
        lay, doc = self.load(True)
        got = hw.find_problem(lay, doc, "3.2")
        self.assertEqual(len(got.clips), 1)                    # 오른쪽 단의 3.3 까지 끌고 가지 않음

    def test_chapter_end_stops(self):
        lay, doc = self.load(False)
        got = hw.find_problem(lay, doc, "3.4")
        self.assertNotIn("Chapter 4", got.text)

    def test_answers_page_and_soft_hyphen(self):
        lay, doc = self.load(False)
        for n in ("3.2", "3.3", "4.1"):
            self.assertNotEqual(hw.find_problem(lay, doc, n).clips[0].page, len(lay.lines) - 1, n)   # 책 끝 답 목록이 아님
        # Hibbeler 의 「\u00ad11–39.」 — 글꼴이 그리지 않는 soft hyphen 이 번호 앞에 붙어 있었음(가짜 PDF 로는 못 만들어 글로 검사)
        self.assertTrue(hw._label("11.39").match("\u00ad11–39. The 50-mm-diameter shaft"))
        self.assertTrue(hw.GENERIC.match("\u00ad11–39. The shaft"))

    def test_missing_problem(self):
        lay, doc = self.load(False)
        self.assertIsNone(hw.find_problem(lay, doc, "9.9"))

    def test_refs_are_cropped_from_their_pages(self):
        lay, doc = self.load(False)
        got = hw.find_problem(lay, doc, "3.2")
        found = {(k, n): hw.find_ref(lay, doc, k, n, got.clips) for k, n in hw.find_refs(got.text)}
        fig = found[("fig", "3.4")]
        self.assertEqual(fig[1], 1)
        self.assertFalse(fig[2])                               # 선 묶음을 찾음(대략 아님)
        x0, y0, x1, y1 = fig[0][0].rect
        self.assertLess(y1 - y0, 200)                          # 쪽 전체가 아니라 그림 + 캡션
        table = found[("table", "3.1")]
        self.assertEqual(table[1], 2)
        self.assertFalse(table[2])
        self.assertLess(table[0][0].rect[3], 200)              # 표 아래 본문까지 자르지 않음
        self.assertEqual(found[("eq", "3.12")][1], 1)
        self.assertEqual(found[("example", "3.2")][1], 1)

    def test_figure_inside_problem_is_not_repeated(self):
        lay, doc = self.load(False)
        got = hw.find_problem(lay, doc, "3.3")
        self.assertIsNone(hw.find_ref(lay, doc, "fig", "P3.3", got.clips))

    def test_sheet_pdf(self):
        lay, doc = self.load(False)
        probs = []
        for n in ("3.2", "9.9"):
            got = hw.find_problem(lay, doc, n)
            if not got:
                probs.append({"num": n, "error": "못 찾음"})
                continue
            refs = []
            for k, m in hw.find_refs(got.text):
                r = hw.find_ref(lay, doc, k, m, got.clips)
                if r:
                    refs.append({"kind": k, "num": m, "page": r[1], "clips": r[0], "approx": r[2]})
            probs.append({"num": n, "page": 3, "clips": got.clips, "refs": refs})
        out = os.path.join(self.d, "s.pdf")
        from pathlib import Path
        hw.build_sheet(Path(out), "HW3", "시험", probs, doc)
        text = "".join(p.get_text() for p in pymupdf.open(out))
        self.assertIn("문제 3.2", text)
        self.assertIn("For the circuit", text)                 # 교과서 글이 벡터로 옮겨짐(그림이 아님)
        self.assertIn("Figure 3.4", text)
        self.assertIn("못 찾음", text)

    def test_layout_cache_roundtrip(self):
        lay, _ = self.load(False)
        from pathlib import Path
        p = Path(self.d) / "l.json"
        hw.save_layout(lay, p)
        back = hw.load_layout(lay.path, p)
        self.assertEqual(len(back.lines), len(lay.lines))
        self.assertEqual(back.body, lay.body)

    def test_clean_html_drops_unknown_tags(self):
        s = hw.clean_html('<p class="ans" onclick="x()">답</p><script>bad()</script><img src="http://x"><a href="x">l</a>')
        self.assertEqual(s, '<p class="ans">답</p>l')


class Flow(unittest.TestCase):
    """올리기 → 문제지 · 해설지까지(Claude 대신 가짜 해설)"""

    def setUp(self):
        self.root = tempfile.mkdtemp()
        self.prompts = []

        def solver(prompt, problems):
            self.prompts.append(prompt)
            return "".join(f'<section data-num="{p["num"]}"><p>풀이 {p["num"]}</p><p class="ans">답: 2 A</p></section>'
                           for p in problems or [])
        self.S = study.Study(self.root, background=False, solver=solver)
        self.c = self.S.save_course({"name": "전기전자공학개론"})["id"]
        tb = os.path.join(self.root, "tb.pdf")
        fake_textbook.make(tb)
        self.tb = self.S.add_file(self.c, "교과서", open(tb, "rb").read(), kind="textbook")

    def test_textbook_layout_built_once_at_upload(self):
        self.assertTrue(os.path.exists(os.path.join(self.root, "text", f"{self.tb['id']}.layout.json")))

    def test_numbered_assignment_makes_sheet_and_solution(self):
        f = self.S.add_text_assignment(self.c, "HW3", "3.2, 3.3, 9.9")
        f = self.S._file(f["id"])
        job = f["hw"]["job"]
        self.assertEqual(job["state"], "done", job)
        self.assertEqual(job["pct"], 100)
        self.assertEqual(f["hw"]["mode_used"], "numbers")
        probs = {p["num"]: p for p in f["hw"]["problems"]}
        self.assertEqual(probs["3.2"]["page"], 3)
        self.assertTrue(any(r["kind"] == "fig" and r["num"] == "3.4" for r in probs["3.2"]["refs"]))
        self.assertTrue(probs["9.9"]["error"])
        for kind in ("sheet", "solution"):
            self.assertTrue(self.S.out_path(f["id"], kind).exists())
        sol = "".join(p.get_text() for p in pymupdf.open(str(self.S.out_path(f["id"], "solution"))))
        self.assertIn("풀이 3.2", sol)
        self.assertIn("문제 3.3", sol)
        self.assertGreater(f["hw"]["sheet_pages"], 0)
        # 해설을 쓰는 Claude 에게 문제지 · 수업자료 · 교과서 경로를 줌
        self.assertIn("-sheet.pdf", self.prompts[0])
        self.assertIn(self.tb["id"], self.prompts[0])
        # 문제지 쪽 그림
        code, img, ct = self.S.handle("GET", f"/study/page/{f['id']}/1.jpg", {"v": ["sheet"], "w": ["600"]}, None)
        self.assertEqual((code, ct), (200, "image/jpeg"))

    def test_numbers_inside_announcement_use_textbook(self):
        # 조교 공지 글 안에 번호가 섞인 과제(실제 HW4 모양) — 교과서에 있으면 번호 모드
        text = ("[고체역학 II] HW4 · Due Friday 안녕하세요, 조교입니다. 네 번째 과제를 아래와 같이 공지해 드립니다. "
                "대상 문제 (교재): 3장: 3-2, 3-3 제출 기한: 11월 13일 (금)")
        f = self.S.add_text_assignment(self.c, "HW4", text)
        h = self.S._file(f["id"])["hw"]
        self.assertEqual(h["mode_used"], "numbers")
        self.assertEqual([p["page"] for p in h["problems"]], [3, 3])
        self.assertEqual(h["problems"][0]["label"], "3.2")

    def test_numbers_not_in_textbook_fall_back_to_full(self):
        text = ("Write a report about Section 7.5 and 8.2 of the lecture with your own experiment design, "
                "explain the data you will collect and the expected results in two pages.")
        f = self.S.add_text_assignment(self.c, "보고서", text)
        h = self.S._file(f["id"])["hw"]
        self.assertEqual(h["mode_used"], "full")
        self.assertEqual(h["job"]["state"], "done")
        self.assertFalse(h.get("sheet"))
        self.assertTrue(self.S.out_path(f["id"], "solution").exists())

    def test_old_assignment_is_made_once_at_start(self):
        f = self.S.add_text_assignment(self.c, "HW4", "3.2")
        self.S._file(f["id"]).pop("hw")                        # 기능 전에 넣은 과제처럼
        self.S._save()
        calls = []
        again = study.Study(self.root, background=True, auto_hw=True, solver=lambda p, pr: calls.append(1) or "")
        import time
        for _ in range(100):
            if (again._file(f["id"]).get("hw") or {}).get("job", {}).get("state") in ("done", "error"):
                break
            time.sleep(0.1)
        self.assertEqual(again._file(f["id"])["hw"]["job"]["state"], "done")
        self.assertEqual(calls, [1])
        third = study.Study(self.root, background=True, auto_hw=True, solver=lambda p, pr: calls.append(1) or "")
        time.sleep(0.5)
        self.assertEqual(calls, [1])                           # 한 번만

    def test_no_textbook_tells_owner(self):
        c2 = self.S.save_course({"name": "빈 과목"})["id"]
        f = self.S.add_text_assignment(c2, "HW1", "1.1, 1.2")
        job = self.S._file(f["id"])["hw"]["job"]
        self.assertEqual(job["state"], "error")
        self.assertIn("교과서", job["msg"])

    def test_solver_failure_is_reported_not_swallowed(self):
        def bad(prompt, problems):
            raise RuntimeError("사용량 한도")
        self.S.solver = bad
        f = self.S.add_text_assignment(self.c, "HW3", "3.2")
        job = self.S._file(f["id"])["hw"]["job"]
        self.assertEqual(job["state"], "error")
        self.assertIn("사용량 한도", job["msg"])
        self.assertTrue(self.S.out_path(f["id"], "sheet").exists())   # 문제지는 남음

    def test_restart_marks_running_job_as_stopped(self):
        f = self.S.add_text_assignment(self.c, "HW3", "3.2")
        self.S._file(f["id"])["hw"]["job"]["state"] = "running"
        self.S._save()
        again = study.Study(self.root, background=False)
        job = again._file(f["id"])["hw"]["job"]
        self.assertEqual(job["state"], "error")
        self.assertIn("다시", job["msg"])

    def test_old_files_get_kind(self):
        db = json.loads(open(os.path.join(self.root, "study.json")).read())
        for f in db["files"]:
            f.pop("kind", None)
        db["files"].append({"id": "f-0000000001", "course": self.c, "name": "HW1", "status": "new"})
        open(os.path.join(self.root, "study.json"), "w").write(json.dumps(db))
        again = study.Study(self.root, background=False)
        self.assertEqual(again._file("f-0000000001")["kind"], "assignment")
        self.assertEqual(again._file(self.tb["id"])["kind"], "lecture")   # 이름으로 모르면 수업자료


class ReadState(unittest.TestCase):
    def setUp(self):
        self.S = study.Study(tempfile.mkdtemp(), background=False)
        c = self.S.save_course({"name": "c"})["id"]
        doc = pymupdf.open()
        for _ in range(3):
            doc.new_page()
        self.f = self.S.add_file(c, "1강", doc.tobytes())

    def test_auto_then_manual_wins(self):
        fid = self.f["id"]
        self.S.update_file({"id": fid, "status": "reading", "auto": True})
        self.assertFalse(self.S._file(fid).get("status_manual"))
        f = self.S.read_end(fid)
        self.assertEqual((f["status"], f["reads"]), ("done", 1))
        f = self.S.read_end(fid)
        self.assertEqual(f["reads"], 2)                        # 다 본 뒤 다시 끝까지 = 2회독
        self.S.update_file({"id": fid, "status": "review"})    # 주인이 직접
        self.assertTrue(self.S._file(fid)["status_manual"])
        self.S.update_file({"id": fid, "status": "reading", "auto": True})
        f = self.S.read_end(fid)
        self.assertEqual(f["status"], "review")                # 자동이 덮어쓰지 않음
        self.assertEqual(f["reads"], 3)
        self.S.update_file({"id": fid, "reads": 7})
        f = self.S.read_end(fid)
        self.assertEqual(f["reads"], 7)                        # 직접 고친 회독 수도 그대로
        self.S.update_file({"id": fid, "status_manual": False, "reads_manual": False})
        f = self.S.read_end(fid)
        self.assertEqual((f["status"], f["reads"]), ("done", 8))

    def test_page_image_cache(self):
        fid = self.f["id"]
        a = self.S.page_image(fid, 1, 1000)
        b = self.S.page_image(fid, 1, 990)                     # 가까운 너비는 같은 캐시
        self.assertEqual(a, b)
        self.assertEqual(len(list((self.S.root / "cache" / fid).glob("*.jpg"))), 1)
        with self.assertRaises(study.StudyError):
            self.S.page_image(fid, 9)

    def test_cache_trim(self):
        old = study.PAGE_CACHE_MAX
        try:
            study.PAGE_CACHE_MAX = 1
            self.S._cache_bytes = None
            self.S.page_image(self.f["id"], 1, 600)
            self.S.page_image(self.f["id"], 2, 600)
            self.assertLessEqual(len(list((self.S.root / "cache").rglob("*.jpg"))), 1)
        finally:
            study.PAGE_CACHE_MAX = old


class ChunkedUpload(unittest.TestCase):
    def test_resume(self):
        S = study.Study(tempfile.mkdtemp(), background=False)
        c = S.save_course({"name": "c"})["id"]
        doc = pymupdf.open()
        doc.new_page()
        data = doc.tobytes()
        up = "ab" * 16
        self.assertEqual(S.upload_status(up)["have"], 0)
        S.upload_part(up, 0, data[:100])
        self.assertTrue(S.upload_part(up, 0, data[:100])["retry"])     # 같은 조각이 또 와도 두 번 쓰지 않음
        S.upload_part(up, 100, data[100:])
        f = S.upload_done(up, c, "교과서.pdf", "textbook", len(data))
        self.assertEqual(f["kind"], "textbook")
        self.assertEqual(S.pdf_path(f["id"]).read_bytes(), data)
        self.assertFalse((S.root / "incoming" / f"{up}.part").exists())
        with self.assertRaises(study.StudyError):
            S.upload_done(up, c, "x.pdf", "", 5)                       # 다 안 온 것
        with self.assertRaises(study.StudyError):
            S.upload_status("../../etc")


if __name__ == "__main__":
    unittest.main()
