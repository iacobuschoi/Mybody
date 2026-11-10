"""강의자료 탭 (desk/study.py) — 저장 · 검색 · 지우기 · 열쇠 검사"""
import io
import json
import os
import sys
import tempfile
import unittest
import urllib.error
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from desk import phone, study  # noqa: E402


def make_pdf(pages: list[str]) -> bytes:
    """글자가 든 작은 PDF — pypdf 로 만들고, 본문은 Helvetica 텍스트 연산자로 넣음"""
    from pypdf import PdfWriter
    from pypdf.generic import DecodedStreamObject, DictionaryObject, NameObject
    w = PdfWriter()
    font = DictionaryObject({NameObject("/Type"): NameObject("/Font"), NameObject("/Subtype"): NameObject("/Type1"),
                             NameObject("/BaseFont"): NameObject("/Helvetica")})
    fref = w._add_object(font)
    for text in pages:
        pg = w.add_blank_page(300, 300)
        s = DecodedStreamObject()
        s.set_data(f"BT /F1 12 Tf 20 250 Td ({text}) Tj ET".encode())
        pg[NameObject("/Contents")] = w._add_object(s)
        pg[NameObject("/Resources")] = DictionaryObject(
            {NameObject("/Font"): DictionaryObject({NameObject("/F1"): fref})})
    buf = io.BytesIO()
    w.write(buf)
    return buf.getvalue()


class Clean(unittest.TestCase):
    def test_private_use_glyphs_removed(self):
        # 강의자료 수식에서 실제로 나온 U+F0DE — 검색 결과에 네모로 보였음
        self.assertEqual(study.clean("x\uf0de1  \ufffd≷ y\x07"), "x 1 ≷ y")


class StudyStore(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp()
        self.s = study.Study(self.dir, background=False)
        self.c = self.s.save_course({"name": "지능형모빌리티", "exam": "2026-12-15"})

    def test_course_rules(self):
        with self.assertRaises(study.StudyError):
            self.s.save_course({"name": "  "})
        self.assertEqual(len(self.s.list()["courses"]), 1)           # 이름 없는 과목은 남지 않음
        with self.assertRaises(study.StudyError):
            self.s.save_course({"id": self.c["id"], "exam": "12월 15일"})
        self.assertEqual(self.s.list()["courses"][0]["exam"], "2026-12-15")   # 거절된 값이 남지 않음
        c = self.s.save_course({"id": self.c["id"], "todo": [{"t": "1~5강 복습"}, {"t": " "}]})
        self.assertEqual([t["t"] for t in c["todo"]], ["1~5강 복습"])

    def test_upload_index_and_search(self):
        f = self.s.add_file(self.c["id"], "04 MLE.pdf", make_pdf(["Maximum Likelihood", "log likelihood gradient"]))
        self.assertEqual(f["name"], "04 MLE")
        meta = self.s.list()["files"][0]
        self.assertEqual((meta["pages"], meta["index_error"]), (2, ""))
        hits = self.s.search("LIKELIHOOD gradient")
        self.assertEqual([(h["page"], h["name"]) for h in hits], [(2, "04 MLE")])
        self.assertEqual(self.s.search("likelihood", course="c-none"), [])
        self.assertEqual(self.s.search("   "), [])

    def test_only_pdf(self):
        with self.assertRaises(study.StudyError):
            self.s.add_file(self.c["id"], "x.pdf", b"<html>")
        with self.assertRaises(study.StudyError):
            self.s.add_file("c-none", "x.pdf", make_pdf(["a"]))

    def test_broken_pdf_still_kept_but_says_why(self):
        f = self.s.add_file(self.c["id"], "깨진.pdf", b"%PDF-1.4 garbage")
        meta = self.s.list()["files"][0]
        self.assertIsNone(meta["pages"])
        self.assertIn("검색만 안 돼요", meta["index_error"])
        self.assertTrue(self.s.pdf_path(f["id"]).exists())

    def test_update_fields(self):
        f = self.s.add_file(self.c["id"], "a.pdf", make_pdf(["a"]))
        r = self.s.update_file({"id": f["id"], "status": "review", "note": "공식 외우기",
                                "marks": [{"p": 7, "t": "시험"}, {"p": 2, "t": "정의"}], "pages": 999})
        self.assertEqual((r["status"], r["note"], [m["p"] for m in r["marks"]]), ("review", "공식 외우기", [2, 7]))
        self.assertEqual(r["pages"], 1)                               # 쪽 수는 손으로 못 바꿈
        with self.assertRaises(study.StudyError):
            self.s.update_file({"id": f["id"], "status": "아무거나"})
        with self.assertRaises(study.StudyError):                      # 앞 칸이 맞아도 뒤 칸이 틀리면 아무것도 안 바뀜
            self.s.update_file({"id": f["id"], "note": "바뀌면 안 됨", "course": "c-none"})
        self.assertEqual(self.s.list()["files"][0]["note"], "공식 외우기")
        # 다시 열어도 남아 있음
        again = study.Study(self.dir, background=False).list()["files"][0]
        self.assertEqual(again["note"], "공식 외우기")

    def test_delete_moves_to_trash(self):
        f = self.s.add_file(self.c["id"], "a.pdf", make_pdf(["hello"]))
        with self.assertRaises(study.StudyError):
            self.s.delete_course(self.c["id"])                       # 자료가 남은 과목은 못 지움
        self.s.delete_file(f["id"])
        self.assertEqual(self.s.list()["files"], [])
        self.assertEqual(len([p for p in os.listdir(os.path.join(self.dir, "trash")) if p.endswith(".pdf")]), 1)
        self.assertEqual(self.s.search("hello"), [])
        self.s.delete_course(self.c["id"])

    def test_import_dir_skips_same_name(self):
        src = tempfile.mkdtemp()
        for n in ("02 Theory.pdf", "01 Introduction.pdf"):
            open(os.path.join(src, n), "wb").write(make_pdf([n]))
        self.assertEqual([f["name"] for f in self.s.import_dir(self.c["id"], src)], ["01 Introduction", "02 Theory"])
        self.assertEqual(self.s.import_dir(self.c["id"], src), [])


class FakeDesk:
    def phone_state(self):
        return {"mode": "awake"}


class StudyRoutes(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp()
        cls.p = phone.Phone(FakeDesk(), port=0, token_file=os.path.join(cls.tmp, "t"),
                            study_dir=os.path.join(cls.tmp, "study"))
        cls.p.start(["127.0.0.1"])
        cls.base = f"http://127.0.0.1:{cls.p.servers[0].server_address[1]}"

    @classmethod
    def tearDownClass(cls):
        for s in cls.p.servers:
            s.shutdown()

    def req(self, path, body=None, tok=True):
        r = urllib.request.Request(self.base + path, data=body, headers={"X-Desk-Token": self.p.token} if tok else {})
        try:
            with urllib.request.urlopen(r, timeout=10) as f:
                return f.status, f.read(), f.headers.get("Content-Type")
        except urllib.error.HTTPError as e:
            return e.code, e.read(), None

    def test_token_required(self):
        for path, body in (("/study/list", None), ("/study/course", b'{"name":"x"}'), ("/study/upload?course=x", b"%PDF")):
            self.assertEqual(self.req(path, body, tok=False)[0], 401, path)

    def test_flow(self):
        c = json.loads(self.req("/study/course", json.dumps({"name": "선형대수"}).encode())[1])
        pdf = make_pdf(["eigenvalue decomposition"])
        code, b, _ = self.req(f"/study/upload?course={c['id']}&name=%EA%B0%95%EC%9D%981.pdf", pdf)
        f = json.loads(b)
        self.assertEqual((code, f["name"]), (200, "강의1"))
        code, b, ct = self.req(f"/study/file/{f['id']}.pdf")
        self.assertEqual((code, b, ct), (200, pdf, "application/pdf"))
        self.assertEqual(self.req("/study/file/f-0000000000.pdf")[0], 400)
        self.assertEqual(self.req("/study/file/../../t.pdf")[0], 404)   # 경로를 밖으로 못 나감
        code, b, _ = self.req("/study/file", json.dumps({"id": f["id"], "status": "nope"}).encode())
        self.assertEqual((code, json.loads(b)["error"]), (400, "모르는 상태예요."))
        self.assertEqual(self.req("/study/file", b"[1]")[0], 400)

    def test_too_big_refused_before_reading(self):
        r = urllib.request.Request(self.base + "/study/upload?course=x", data=b"x",
                                   headers={"X-Desk-Token": self.p.token, "Content-Length": str(study.MAX_PDF + 10_000)})
        with self.assertRaises(urllib.error.HTTPError) as e:
            urllib.request.urlopen(r, timeout=10)
        self.assertEqual(e.exception.code, 413)


if __name__ == "__main__":
    unittest.main()
