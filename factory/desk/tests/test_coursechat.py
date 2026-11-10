"""과목 비서 (desk/coursechat.py) — 미리 읽기 · 과목별 세션 이어 가기 · 지금 보는 쪽만 붙이기 · 맥락 줄이기"""
import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pymupdf  # noqa: E402

import fake_textbook  # noqa: E402
from desk import coursechat, study  # noqa: E402


def pdf(pages):
    doc = pymupdf.open()
    for t in pages:
        p = doc.new_page()
        if t:
            p.insert_text((72, 72), t)
    return doc.tobytes()


class Fake:
    def __init__(self):
        self.calls = []
        self.tokens = 1000

    def __call__(self, prompt, cwd, add_dirs, timeout, resume="", system_file="", **kw):
        self.calls.append({"prompt": prompt, "resume": resume, "system": open(system_file).read() if system_file else ""})
        if prompt.startswith("과목 공부용 자료"):
            return {"result": "# 정리\n- 1쪽: 베이즈 정리", "session_id": "x"}
        if prompt.startswith("지금까지"):
            return {"result": "요약: 주인은 MLE 를 헷갈려함", "session_id": resume}
        return {"result": "LN5 12쪽 내용이에요.", "session_id": resume or "s-1",
                "usage": {"input_tokens": 10, "cache_read_input_tokens": self.tokens}}


class CourseChat(unittest.TestCase):
    def setUp(self):
        self.fake = Fake()
        self.S = study.Study(tempfile.mkdtemp(), background=False, chat_runner=self.fake)
        self.c = self.S.save_course({"name": "지능형모빌리티"})["id"]
        self.lec = self.S.add_file(self.c, "05 NBC", pdf(["Naive Bayes classifier and the likelihood of features " * 3, "posterior"]))
        self.note = self.S.add_file(self.c, "2026-10-23_m2", pdf(["", ""]))       # 손글씨처럼 글이 없는 노트
        tb = os.path.join(self.S.root, "tb.pdf")
        fake_textbook.make(tb)
        self.tb = self.S.add_file(self.c, "교과서", open(tb, "rb").read(), kind="textbook")

    def test_prep_reads_text_images_and_textbook_toc(self):
        self.S.chat.prep(self.c)
        prompts = [c["prompt"] for c in self.fake.calls]
        self.assertEqual(len(prompts), 2)                       # 교과서는 Claude 로 통째 읽지 않음
        lec = next(p for p in prompts if "05 NBC" in p)
        self.assertIn(f"{self.lec['id']}.json", lec)
        note = next(p for p in prompts if "2026-10-23_m2" in p)
        self.assertIn(f"{self.note['id']}-1.jpg", note)         # 글 없는 쪽은 그림으로
        self.assertTrue(os.path.exists(os.path.join(self.S.root, "chat", self.c, "img", f"{self.note['id']}-1.jpg")))
        course = open(os.path.join(self.S.root, "chat", self.c, "course.md")).read()
        self.assertIn("베이즈 정리", course)
        self.assertIn("Chapter 3", course)                      # 교과서는 글자 배치에서 뽑은 목차
        self.assertIn("연습문제 번호가 있는 쪽", course)
        v = self.S.chat.view(self.c)
        self.assertEqual((v["prep"]["done"], v["prep"]["total"]), (3, 3))
        # 다시 불러도 바뀐 게 없으면 또 읽지 않음
        self.S.chat.prep(self.c)
        self.assertEqual(len(self.fake.calls), 2)

    def test_same_course_keeps_session_across_files(self):
        self.S.chat.prep(self.c)
        n0 = len(self.fake.calls)
        for q, f, pg in (("이게 뭐야", self.lec, 2), ("그럼 이건", self.note, 1)):
            body = json.dumps({"course": self.c, "q": q, "file": f["id"], "page": pg}).encode()
            self.assertEqual(self.S.handle("POST", "/study/chat", {}, body)[0], 200)
        a, b = self.fake.calls[n0:]
        self.assertEqual(a["resume"], "")
        self.assertEqual(b["resume"], "s-1")                    # 자료를 바꿔도 같은 세션
        self.assertIn("05 NBC", a["prompt"])
        self.assertIn("2/2쪽", a["prompt"])
        self.assertIn("posterior", a["prompt"])                 # 그 쪽 글만
        self.assertNotIn("Naive Bayes classifier", a["prompt"])  # 다른 쪽 글은 안 보냄
        self.assertIn(".jpg", a["prompt"])                      # 그 쪽 그림 경로
        self.assertIn("베이즈 정리", a["system"])                # 과목 지식은 시스템 프롬프트로
        h = self.S.chat.view(self.c)["history"]
        self.assertEqual([m["a"] for m in h], ["LN5 12쪽 내용이에요."] * 2)

    def test_other_course_has_own_session(self):
        c2 = self.S.save_course({"name": "고체역학2"})["id"]
        self.S.chat.ask(self.c, "a", background=False)
        self.S.chat.ask(c2, "b", background=False)
        self.assertEqual(self.fake.calls[-1]["resume"], "")
        self.assertIn("고체역학2", self.fake.calls[-1]["system"])

    def test_compact_when_context_grows(self):
        self.fake.tokens = coursechat.COMPACT_TOKENS + 1
        self.S.chat.ask(self.c, "길게", background=False)
        d = self.S.chat._load(self.c)
        self.assertEqual(d["sid"], "")                          # 새 세션으로
        self.assertIn("MLE", d["summary"])
        self.fake.tokens = 1000
        self.S.chat.ask(self.c, "다음", background=False)
        self.assertIn("이전 대화 요약", self.fake.calls[-1]["prompt"])
        self.assertEqual(self.fake.calls[-1]["resume"], "")

    def test_failure_shows_in_answer(self):
        def bad(*a, **k):
            raise RuntimeError("사용량 한도")
        self.S.chat.run = bad
        self.S.chat.ask(self.c, "q", background=False)
        m = self.S.chat.view(self.c)["history"][-1]
        self.assertTrue(m["error"])
        self.assertIn("사용량 한도", m["a"])
        self.assertFalse(self.S.chat.view(self.c)["asking"])

    def test_limit_error_in_korean(self):
        self.assertEqual(coursechat.korean_error("You've hit your 5-hour limit · resets 12:10am (Asia/Seoul)"),
                         "Claude 5시간 사용량 한도에 걸렸어요. 12:10am 에 풀려요.")

    def test_empty_question_and_bad_course(self):
        code, out, _ = self.S.handle("POST", "/study/chat", {}, json.dumps({"course": self.c, "q": " "}).encode())
        self.assertEqual(code, 400)
        code, out, _ = self.S.handle("POST", "/study/chat", {}, b'{"course":"c-00","q":"x"}')
        self.assertEqual(code, 400)


if __name__ == "__main__":
    unittest.main()
