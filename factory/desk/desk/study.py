"""강의자료 — 비서 웹의 「강의자료」 탭 (주인 11월 10일: 시험공부용, 다루기 편하게).

과목마다 PDF 를 모아 두고, 자료마다 공부 상태 · 메모 · 쪽 표시를 남기고, 모든 자료의 본문을 검색하고,
비서에게 "이 자료로 예상 문제" 처럼 물을 수 있게 합니다(비서는 이 맥의 파일 경로를 받아 직접 읽음).

    ~/lab/study-data/
        study.json          과목 · 자료 목록(메모 · 표시 · 상태 포함)
        files/<id>.pdf      올린 자료
        text/<id>.json      쪽별 본문(검색용, 올릴 때 뽑음)
        trash/              지운 자료(되살릴 수 있게 지우지 않고 옮김)
        out/<id>-sheet.pdf · <id>-solution.pdf   과제의 문제지 · 해설지 (desk/homework.py)
        text/<id>.layout.json   교과서 글자 배치(문제 찾기용, 처음 한 번 뽑음)

자료는 세 갈래(kind): 수업자료(lecture) · 과제(assignment) · 교과서(textbook) — 주인 11월 10일 20:23.
과제를 올리면 같은 과목의 교과서 · 수업자료로 문제지 · 해설지를 저절로 만듦(진행률은 자료의 hw.job).

길(모두 phone.py 의 열쇠 검사를 거친 뒤):
    GET  /study/list · /study/file/<id>.pdf · /study/search?q=&course=
    POST /study/course {id?, name, exam, scope, todo} · /study/course_delete {id}
    POST /study/upload?course=&name=&kind=  (본문 = PDF) · /study/file {id, …바꿀 칸} · /study/file_delete {id}
    POST /study/assignment {course, name, text}  번호로 넣는 과제(「3.2, 3.5, 4.1」)
    POST /study/hw {id, mode?, numbers?, textbook?, pages?} · /study/hw_run {id, what: all|sheet}
    GET  /study/out/<id>-sheet.pdf · /study/out/<id>-solution.pdf · /study/page/<id>/<쪽>.jpg?w=
"""
from __future__ import annotations

import io
import json
import logging
import math
import queue
import os
import re
import secrets
import shutil
import threading
import time
from pathlib import Path

log = logging.getLogger("deskd")

DATA_DIR = "~/lab/study-data"
MAX_PDF = 200 * 1024 * 1024
PART = 8 * 1024 * 1024                                  # 나눠 올리기 한 조각 상한
PAGE_CACHE_MAX = 600 * 1024 * 1024                      # 쪽 그림 캐시(디스크) 상한 — 넘으면 오래 안 쓴 것부터 지움
STATUS = ("new", "reading", "done", "review")          # 안 봄 · 보는 중 · 다 봄 · 다시 볼 것
FILE_FIELDS = {"status", "note", "marks", "course", "name", "last_page", "kind", "status_manual", "reads", "reads_manual"}
KINDS = ("lecture", "assignment", "textbook")           # 수업자료 · 과제 · 교과서
HW_NAME = re.compile(r"(?i)^(hw|homework|assignment|과제|숙제)")


def pdf_meta(path: Path) -> tuple[int, float]:
    """(쪽 수, 첫 쪽 높이/너비) — 화면이 쪽 자리를 미리 잡게(받기 전에 스크롤이 튀지 않게)"""
    import pymupdf
    with pymupdf.open(str(path)) as doc:
        r = doc[0].rect if len(doc) else None
        return len(doc), round(r.height / r.width, 4) if r and r.width else 1.414


def _guess_kind(name: str) -> str:
    """kind 가 없던 옛 자료 · 종류 없이 올린 자료: 이름이 HW · 과제로 시작하면 과제"""
    return "assignment" if HW_NAME.match(name or "") else "lecture"
COURSE_FIELDS = {"name", "exam", "scope", "todo"}


class StudyError(ValueError):
    """주인에게 그대로 보여 줄 수 있는 까닭"""


def _id(prefix: str) -> str:
    return prefix + secrets.token_hex(5)


# 수식 글꼴의 사용자 정의 영역 글자(강의자료의 U+F0DE 등) · 깨진 글자 · 제어 문자 — 화면에 네모로 나와서 뺌 (11월 10일)
JUNK = re.compile(r"[\ue000-\uf8ff\ufffd\x00-\x08\x0b\x0c\x0e-\x1f]")


def clean(text: str) -> str:
    return re.sub(r"[ \t]+", " ", JUNK.sub(" ", text or "")).strip()


def pdf_text(path: Path) -> list[str]:
    """쪽별 본문. 글자가 없는 쪽(스캔 그림)은 빈 글. pymupdf 가 pypdf 보다 몇 배 빠르고 메모리를 덜 씀(쪽을 하나씩 읽음)"""
    try:
        import pymupdf
    except ImportError:
        return _pdf_text_pypdf(path)
    out = []
    with pymupdf.open(str(path)) as doc:
        for pg in doc:
            try:
                out.append(clean(pg.get_text()))
            except Exception:  # noqa: BLE001 — 한 쪽이 깨져도 나머지 쪽은 검색되게. 깨진 쪽은 로그에 남김
                log.exception("강의자료: %s 의 한 쪽 본문을 못 뽑음", path.name)
                out.append("")
    return out


def _pdf_text_pypdf(path: Path) -> list[str]:
    from pypdf import PdfReader
    out = []
    for pg in PdfReader(str(path)).pages:
        try:
            out.append(clean(pg.extract_text()))
        except Exception:  # noqa: BLE001 — 한 쪽이 깨져도 나머지 쪽은 검색되게. 깨진 쪽은 로그에 남김
            log.exception("강의자료: %s 의 한 쪽 본문을 못 뽑음", path.name)
            out.append("")
    return out


class Study:
    def __init__(self, root: str = DATA_DIR, now=time.time, background: bool = True, solver=None,
                 auto_hw: bool = True, chat_runner=None):
        self.root = Path(os.path.expanduser(root))
        self.now = now
        self.background = background
        self.solver = solver                             # 시험에서 Claude 대신 꽂음: (prompt, problems) → html
        self.auto_hw = auto_hw
        self.lock = threading.RLock()
        self._q: queue.Queue = queue.Queue()
        self._worker: threading.Thread | None = None
        for d in ("files", "text", "trash", "out", "incoming", "cache"):
            (self.root / d).mkdir(parents=True, exist_ok=True)
        self.db = self._load()
        from .coursechat import CourseChat, claude_json
        self.chat = CourseChat(self, runner=chat_runner or claude_json)   # 과목 비서(미리 읽기 · 과목별 세션)
        # 저절로 미리 읽기(진짜 Claude 사용량)는 진짜 자료 폴더에서만 — 시험의 임시 폴더에서는 가짜를 꽂았을 때만
        self.chat_auto = background and (chat_runner is not None or self.root == Path(os.path.expanduser(DATA_DIR)))
        if background and auto_hw:
            self._catch_up()
            for c in list(self.db["courses"]) if self.chat_auto else []:   # 기능 전에 올린 자료도 미리 읽게(읽은 것은 건너뜀)
                self.chat.schedule(c["id"])

    def _catch_up(self) -> None:
        """이 기능 전에 넣은 과제(hw 칸이 아예 없음) 가운데 과목에 교과서가 있고 문제 번호가 보이는 것 — 새로 올린 것처럼 한 번 만듦"""
        from . import homework as hw
        with self.lock:
            books = {f["course"] for f in self.db["files"] if f.get("kind") == "textbook"}
            todo = [f["id"] for f in self.db["files"] if f.get("kind") == "assignment" and "hw" not in f
                    and f["course"] in books]
        for fid in todo:
            f = self._file(fid)
            if hw.parse_numbers(self._hw_text(f)):
                log.info("강의자료: 예전에 넣은 과제 %s 의 문제지 · 해설지를 만듦", f["name"])
                f["hw"] = {"text": ""}
                self.run_hw(fid, "all")

    # ── 저장 ──────────────────────────────────────────────────────────────
    def _load(self) -> dict:
        p = self.root / "study.json"
        try:
            db = json.loads(p.read_text())
        except FileNotFoundError:
            db = {}
        db.setdefault("courses", [])
        db.setdefault("files", [])
        for f in db["files"]:
            if f.get("kind") not in KINDS:
                f["kind"] = _guess_kind(f.get("name", ""))
                if f["kind"] == "lecture" and (f.get("pages") or 0) > 300:
                    f["kind"] = "textbook"                     # 수백 쪽짜리는 교과서로 (화면에서 바꿀 수 있음)
            if "ratio" not in f:                              # 쪽 그림 보기 전에 올린 자료
                try:
                    f["ratio"] = pdf_meta(self.root / "files" / f"{f['id']}.pdf")[1]
                except Exception:  # noqa: BLE001 — 파일이 없거나 깨짐: 화면은 A4 비율로 자리를 잡음
                    log.warning("강의자료: %s 쪽 크기를 못 읽음", f.get("id"))
            job = (f.get("hw") or {}).get("job") or {}
            if job.get("state") in ("queued", "running"):    # 만드는 중에 deskd 가 다시 켜짐
                job.update(state="error", msg="맥 프로그램이 다시 켜져서 멈췄어요. 「다시 만들기」를 눌러 주세요.")
        return db

    def _save(self) -> None:
        p = self.root / "study.json"
        tmp = p.with_suffix(".tmp")
        tmp.write_text(json.dumps(self.db, ensure_ascii=False, indent=1))
        os.replace(tmp, p)                                   # 쓰다 꺼져도 전 판이 남게

    def _course(self, cid: str) -> dict:
        for c in self.db["courses"]:
            if c["id"] == cid:
                return c
        raise StudyError("그 과목이 없어요.")

    def _file(self, fid: str) -> dict:
        for f in self.db["files"]:
            if f["id"] == fid:
                return f
        raise StudyError("그 자료가 없어요.")

    def pdf_path(self, fid: str) -> Path:
        with self.lock:
            self._file(fid)
        return self.root / "files" / f"{fid}.pdf"

    # ── 과목 ──────────────────────────────────────────────────────────────
    def list(self) -> dict:
        with self.lock:
            out = json.loads(json.dumps(self.db))
        out["root"] = str(self.root)                         # 비서에게 물을 때 파일 경로를 알려 주려고
        return out

    def save_course(self, d: dict) -> dict:
        with self.lock:
            old = self._course(d["id"]) if d.get("id") else None
            # 고칠 판을 따로 만들어 검사가 다 통과한 뒤에만 넣음 — 틀린 값이 메모리에 남아 다음 저장까지 막던 것 (11월 10일)
            c = dict(old) if old else {"id": _id("c-"), "name": "", "exam": "", "scope": "", "todo": [],
                                       "added": int(self.now())}
            for k in COURSE_FIELDS & d.keys():
                c[k] = d[k]
            c["name"] = str(c.get("name") or "").strip()[:100]
            c["exam"] = str(c.get("exam") or "").strip()
            c["scope"] = str(c.get("scope") or "")[:5000]
            if not c["name"]:
                raise StudyError("과목 이름을 써 주세요.")
            if c["exam"] and not re.fullmatch(r"\d{4}-\d{2}-\d{2}", c["exam"]):
                raise StudyError("시험 날짜는 2026-12-15 처럼 써 주세요.")
            c["todo"] = [{"id": t.get("id") or _id("t-"), "t": str(t.get("t", ""))[:300], "done": bool(t.get("done"))}
                         for t in (c.get("todo") or []) if str(t.get("t", "")).strip()]
            if old:
                old.clear()
                old.update(c)
                c = old
            else:
                self.db["courses"].append(c)
            self._save()
            return c

    def delete_course(self, cid: str) -> None:
        with self.lock:
            c = self._course(cid)
            if any(f["course"] == cid for f in self.db["files"]):
                raise StudyError("자료가 남아 있어요. 자료를 먼저 지우거나 다른 과목으로 옮겨 주세요.")
            self.db["courses"].remove(c)
            self._save()

    # ── 자료 ──────────────────────────────────────────────────────────────
    def add_file(self, course: str, name: str, data: bytes, kind: str = "", hw_text: str = "",
                 src: Path | None = None) -> dict:
        """src: 나눠 올리기로 이미 디스크에 받은 파일 — 메모리에 다시 읽지 않고 옮김"""
        size = src.stat().st_size if src else len(data)
        if not src and not data.startswith(b"%PDF"):
            raise StudyError("PDF 만 올릴 수 있어요.")
        if size > MAX_PDF:
            raise StudyError("200MB 보다 큰 파일은 못 올려요.")
        name = re.sub(r"\.pdf$", "", Path(name or "자료").name, flags=re.I).strip() or "자료"
        with self.lock:
            self._course(course)
            fid = _id("f-")
            if src:
                shutil.move(str(src), str(self.root / "files" / f"{fid}.pdf"))
            else:
                (self.root / "files" / f"{fid}.pdf").write_bytes(data)
            kind = kind if kind in KINDS else _guess_kind(name)
            f = {"id": fid, "course": course, "name": name[:200], "size": size, "pages": None,
                 "status": "new", "note": "", "marks": [], "last_page": 1, "added": int(self.now()), "kind": kind}
            if kind == "assignment":
                f["hw"] = {"text": hw_text, "job": {"state": "queued", "stage": "read", "pct": 0,
                                                    "msg": "과제를 읽는 중", "at": int(self.now())}}
            self.db["files"].append(f)
            self._save()
        if self.background:
            threading.Thread(target=self._index, args=(fid,), daemon=True, name="study-index").start()
        else:
            self._index(fid)
        return f

    def _index(self, fid: str) -> None:
        """쪽 수 · 본문 뽑기 — 실패해도 자료는 남고(볼 수는 있음), 검색만 안 됨. 까닭은 로그와 자료의 index_error 에"""
        src = self.root / "files" / f"{fid}.pdf"
        with self.lock:
            kind = next((f.get("kind") for f in self.db["files"] if f["id"] == fid), "")
        ratio = None
        try:
            ratio = pdf_meta(src)[1]
        except Exception:  # noqa: BLE001 — 쪽 비율은 화면 자리 잡기용일 뿐. 없으면 A4 로 그림
            log.exception("강의자료: 쪽 크기를 못 읽음 %s", fid)
        try:
            pages = pdf_text(src)
            if kind == "textbook":                          # 문제 찾기용 글자 배치를 올릴 때 한 번 — 해설지 때 다시 안 읽음
                try:
                    from . import homework as hw
                    hw.save_layout(hw.build_layout(str(src)), self.root / "text" / f"{fid}.layout.json")
                except Exception:  # noqa: BLE001 — 배치를 못 뽑아도 보기 · 검색은 됨. 과제 때 다시 시도
                    log.exception("강의자료: 교과서 글자 배치 뽑기 실패 %s", fid)
            (self.root / "text" / f"{fid}.json").write_text(json.dumps(pages, ensure_ascii=False))
            err = ""
        except Exception as e:  # noqa: BLE001
            log.exception("강의자료: 본문 뽑기 실패 %s", fid)
            pages, err = None, f"본문을 못 읽었어요({type(e).__name__}). 보기는 되고 검색만 안 돼요."
        with self.lock:
            try:
                f = self._file(fid)
            except StudyError:
                return                                       # 뽑는 사이에 지워짐
            f["pages"] = len(pages) if pages is not None else None
            f["index_error"] = err
            if ratio:
                f["ratio"] = ratio
            self._save()
            auto = f.get("kind") == "assignment" and self.auto_hw and not (f.get("hw") or {}).get("sheet")
            cid = f["course"]
        if self.chat_auto:
            self.chat.schedule(cid)                          # 과목 비서가 새 자료를 미리 읽음 (주인 11월 10일 20:51)
        if auto:
            self.run_hw(fid, "all")                          # 과제를 넣으면 문제지 · 해설지를 저절로 (주인 11월 10일)

    def update_file(self, d: dict) -> dict:
        with self.lock:
            f = self._file(str(d.get("id", "")))
            new = {}                                         # 다 검사한 뒤에 한꺼번에 넣음(일부만 바뀐 채 남지 않게)
            auto = bool(d.get("auto"))                       # 열어 봄 · 끝 쪽까지 봄으로 저절로 바꾸는 것
            for k in FILE_FIELDS & d.keys():
                v = d[k]
                if k == "status" and v not in STATUS:
                    raise StudyError("모르는 상태예요.")
                if k == "status" and auto and f.get("status_manual"):
                    continue                                 # 주인이 직접 고른 상태가 먼저 (주인 11월 10일 20:33)
                if k in ("status_manual", "reads_manual"):
                    v = bool(v)
                if k == "reads":
                    v = max(0, min(99, int(v)))
                if k == "kind" and v not in KINDS:
                    raise StudyError("모르는 종류예요.")
                if k == "course":
                    self._course(v)
                if k == "name":
                    v = str(v).strip()[:200]
                    if not v:
                        raise StudyError("이름을 써 주세요.")
                if k == "marks":
                    v = sorted(({"p": max(1, int(m.get("p", 1))), "t": str(m.get("t", ""))[:300]} for m in v),
                               key=lambda m: m["p"])
                if k == "last_page":
                    v = max(1, int(v))
                if k == "note":
                    v = str(v)[:100_000]
                new[k] = v
            if "status" in new and not auto and "status_manual" not in new:
                new["status_manual"] = True
            if "reads" in new and "reads_manual" not in new:
                new["reads_manual"] = True                   # 주인이 고친 회독 수가 먼저
            if new.get("kind") == "assignment" and "hw" not in f:
                f["hw"] = {"text": "", "job": {"state": "idle", "pct": 0, "msg": ""}}
            f.update(new)
            self._save()
            if self.chat_auto and {"kind", "name", "course"} & new.keys():
                self.chat.schedule(f["course"])
            return f

    def read_end(self, fid: str) -> dict:
        """한 번 열어서 끝 쪽까지 봄(화면이 판정) → 다 봄 · 회독 +1. 주인이 직접 고른 값은 건드리지 않음 (주인 11월 10일 20:33 · 20:34)"""
        with self.lock:
            f = self._file(fid)
            if not f.get("status_manual"):
                f["status"] = "done"
            if not f.get("reads_manual"):
                f["reads"] = int(f.get("reads") or 0) + 1
            f["read_at"] = int(self.now())
            self._save()
            return f

    def delete_file(self, fid: str) -> None:
        with self.lock:
            f = self._file(fid)
            stamp = time.strftime("%Y%m%d-%H%M%S", time.localtime(self.now()))
            src = self.root / "files" / f"{fid}.pdf"
            if src.exists():
                shutil.move(str(src), str(self.root / "trash" / f"{stamp}-{fid}-{Path(f['name']).name}.pdf"))
            (self.root / "trash" / f"{stamp}-{fid}.json").write_text(json.dumps(f, ensure_ascii=False))
            (self.root / "text" / f"{fid}.json").unlink(missing_ok=True)
            (self.root / "text" / f"{fid}.layout.json").unlink(missing_ok=True)
            shutil.rmtree(self.root / "cache" / fid, ignore_errors=True)
            shutil.rmtree(self.root / "out" / f"{fid}-solve", ignore_errors=True)
            for kind in ("sheet", "solution"):
                out = self.root / "out" / f"{fid}-{kind}.pdf"
                if out.exists():
                    shutil.move(str(out), str(self.root / "trash" / f"{stamp}-{fid}-{kind}.pdf"))
            self.db["files"].remove(f)
            self._save()
            if self.chat_auto:
                self.chat.schedule(f["course"])

    def import_dir(self, course: str, folder: str, pattern: str = "*.pdf") -> list[dict]:
        """폴더의 PDF 를 이름순으로 가져옴(이미 같은 이름이 있으면 건너뜀)"""
        have = {(f["course"], f["name"]) for f in self.db["files"]}
        out = []
        for p in sorted(Path(os.path.expanduser(folder)).glob(pattern)):
            if (course, p.stem) not in have:
                out.append(self.add_file(course, p.name, p.read_bytes()))
        return out


    # ── 과제: 문제지 · 해설지 (desk/homework.py) ─────────────────────────────────
    def add_text_assignment(self, course: str, name: str, text: str) -> dict:
        """「3.2, 3.5, 4.1」 처럼 글로 넣는 과제 — 한 쪽 PDF 로 만들어 다른 과제와 똑같이 다룸"""
        from . import homework as hw
        text = str(text or "").strip()[:5000]
        name = str(name or "").strip()[:200] or "과제"
        if not text:
            raise StudyError("과제 내용(예: 3.2, 3.5, 4.1)을 써 주세요.")
        return self.add_file(course, name + ".pdf", hw.text_pdf(text, name), kind="assignment", hw_text=text)

    def _hw_text(self, f: dict) -> str:
        t = (f.get("hw") or {}).get("text") or ""
        if t:
            return t
        try:
            return "\n".join(json.loads((self.root / "text" / f"{f['id']}.json").read_text()))
        except FileNotFoundError:
            return ""

    def set_hw(self, d: dict) -> dict:
        """과제 설정 고치기: 번호 모드/전체 모드 · 문제 번호 · 쓸 교과서 · 문제별 쪽(못 찾을 때 주인이 알려 줌)"""
        from . import homework as hw
        with self.lock:
            f = self._file(str(d.get("id", "")))
            if f.get("kind") != "assignment":
                raise StudyError("과제가 아니에요.")
            h = f.setdefault("hw", {})
            new = {}
            if "mode" in d:
                if d["mode"] not in ("", "numbers", "full"):
                    raise StudyError("모르는 방식이에요.")
                new["mode"] = d["mode"]
            if "numbers" in d:
                raw = d["numbers"] if isinstance(d["numbers"], str) else ", ".join(map(str, d["numbers"]))
                nums = hw.parse_numbers(raw)
                if raw.strip() and not nums:
                    raise StudyError("문제 번호는 3.2, 3.5, 4.1 처럼 써 주세요.")
                new["numbers"] = nums
            if "textbook" in d:
                tb = str(d["textbook"] or "")
                if tb and self._file(tb).get("kind") != "textbook":
                    raise StudyError("교과서로 올린 자료가 아니에요.")
                new["textbook"] = tb
            if "pages" in d:
                pages = {}
                for k, v in (d["pages"] or {}).items():
                    if str(v).strip():
                        pages[str(k)] = max(1, int(v))
                new["pages"] = pages
            h.update(new)
            self._save()
            return f

    def _job(self, fid: str, save: bool = False, **kw) -> None:
        with self.lock:
            try:
                f = self._file(fid)
            except StudyError:
                return
            job = f.setdefault("hw", {}).setdefault("job", {})
            job.update(kw, at=int(self.now()))
            if save:
                self._save()

    def run_hw(self, fid: str, what: str = "all") -> dict:
        """문제지(what=sheet) 또는 문제지 + 해설지(all) 만들기를 줄 세움. 한 번에 하나씩(Claude 사용량 · 맥 부하)"""
        if what not in ("all", "sheet"):
            raise StudyError("모르는 일이에요.")
        with self.lock:
            f = self._file(fid)
            if f.get("kind") != "assignment":
                raise StudyError("과제가 아니에요.")
            job = f.setdefault("hw", {}).setdefault("job", {})
            if job.get("state") == "running" or (job.get("state") == "queued" and job.get("what")):
                raise StudyError("이미 만드는 중이에요.")
            job.clear()
            job.update(state="queued", stage="read", pct=0, msg="차례를 기다리는 중", what=what,
                       started=int(self.now()), at=int(self.now()))
            self._save()
        if not self.background:
            self._hw_do(fid, what)
        else:
            self._q.put((fid, what))
            if self._worker is None or not self._worker.is_alive():
                self._worker = threading.Thread(target=self._hw_loop, daemon=True, name="study-hw")
                self._worker.start()
        with self.lock:
            return self._file(fid)

    def _hw_loop(self) -> None:
        while True:
            fid, what = self._q.get()
            try:
                self._hw_do(fid, what)
            except Exception:  # noqa: BLE001 — _hw_do 가 까닭을 job 에 적음. 여기는 다음 일을 계속하려고
                log.exception("과제: 일 하나가 끝까지 실패 %s", fid)

    def _hw_do(self, fid: str, what: str) -> None:
        try:
            self._hw_steps(fid, what)
        except StudyError as e:
            self._job(fid, True, state="error", msg=str(e))
        except Exception as e:  # noqa: BLE001 — 주인에게 까닭을 보이고 로그에 전체를 남김(삼키지 않음)
            log.exception("과제: 만들기 실패 %s", fid)
            self._job(fid, True, state="error", msg=f"만들다 멈췄어요: {e}"[:300])

    def _hw_steps(self, fid: str, what: str) -> None:
        import pymupdf
        from . import homework as hw
        with self.lock:
            f = json.loads(json.dumps(self._file(fid)))
            course = self._course(f["course"])["name"]
            same = [x for x in self.db["files"] if x["course"] == f["course"] and x["id"] != fid]
            lectures = [x for x in same if x.get("kind") == "lecture"]
            books = [x for x in same if x.get("kind") == "textbook"]
        h = f.get("hw") or {}
        text = self._hw_text(f)
        nums = h.get("numbers") or hw.parse_numbers(text)
        # 저절로: 번호만 나열됐거나, 공지 글에 섞여 있어도 교과서가 있으면 일단 번호 모드 — 교과서에서 절반도 못 찾으면 아래에서 전체 모드로
        auto = not h.get("mode")
        mode = h.get("mode") or ("numbers" if hw.numbers_only(text) or (nums and books) else "full")
        if mode == "numbers" and not nums:
            mode = "full"
        if h.get("textbook"):
            books.sort(key=lambda x: x["id"] != h["textbook"])   # 고른 교과서를 먼저 찾음
        skip = () if mode == "numbers" else ("read", "find", "crop", "sheet")
        if what == "sheet":
            skip += ("solve", "solution")
        with self.lock:
            ff = self._file(fid)
            ff["hw"].update(mode_used=mode, numbers_used=nums)

        def prog(stage, frac=0.0, msg=None, save=False):
            self._job(fid, save, state="running", stage=stage, pct=hw.pct_at(stage, frac, skip),
                      msg=msg or hw.STAGE_NAME[stage] + " 중")

        out_dir = self.root / "out"
        sheet_path = out_dir / f"{fid}-sheet.pdf"
        problems = None
        docs = {}
        if mode == "numbers":
            if not books:
                raise StudyError("이 과목에 교과서가 없어요. 교과서 PDF 를 「교과서」 칸에 올린 뒤 「다시 만들기」를 눌러 주세요.")
            prog("read", 0, "교과서를 읽는 중", save=True)
            lays = []
            for i, b in enumerate(books):
                src = str(self.root / "files" / f"{b['id']}.pdf")
                cache = self.root / "text" / f"{b['id']}.layout.json"
                lay = hw.load_layout(src, cache)
                if lay is None:
                    lay = hw.build_layout(src, lambda x, i=i: prog("read", (i + x) / len(books),
                                                                   f"교과서 「{b['name']}」를 읽는 중"))
                    hw.save_layout(lay, cache)
                lays.append((b, lay))
                docs[src] = pymupdf.open(src)
            regions = {b["id"]: hw._problems_region(lay) for b, lay in lays}
            prog("find", 0, "교과서에서 문제를 찾는 중", save=True)
            problems = []
            pages = h.get("pages") or {}
            for i, n in enumerate(nums):
                prog("find", i / len(nums), f"교과서에서 문제 {n} 를 찾는 중")
                got = None
                for b, lay in lays:
                    hint = pages.get(n) if (not h.get("textbook") or b["id"] == h.get("textbook")) else None
                    got = hw.find_problem(lay, docs[lay.path], n, page_hint=hint, region=regions[b["id"]])
                    if got:
                        problems.append({"num": n, "label": got.label, "clips": got.clips, "text": got.text, "book": b["id"],
                                         "book_name": b["name"], "page": got.clips[0].page + 1, "lay": lay})
                        break
                if not got:
                    problems.append({"num": n, "error": "교과서에서 이 문제를 못 찾았어요. 오른쪽 「과제」 칸에 쪽 번호를 적고 다시 만들어 주세요."})
            found = sum(1 for p in problems if not p.get("error"))
            if auto and not hw.numbers_only(text) and found < max(1, (len(nums) + 1) // 2):
                mode, problems = "full", None              # 과제 글의 번호가 교과서 문제가 아니었음 — 과제 글 그대로 풂
                skip = ("read", "find", "crop", "sheet") + (("solve", "solution") if what == "sheet" else ())
                with self.lock:
                    self._file(fid)["hw"]["mode_used"] = "full"
        if mode == "numbers":
            prog("crop", 0, "그림 · 표 · 예제를 잘라 오는 중", save=True)
            for i, pr in enumerate(problems):
                prog("crop", i / len(problems), f"문제 {pr['num']} 의 그림 · 예제를 잘라 오는 중")
                if pr.get("error"):
                    continue
                lay = pr.pop("lay")
                refs, missing = [], []
                # 문제 글과 떨어져 놓인 문제 그림(「Prob. 1–5」) — 글에 「Fig.」 가 없어도
                r = hw.find_ref(lay, docs[lay.path], "probfig", pr["num"], pr["clips"], page_hint=pr["page"] - 1)
                if r:
                    refs.append({"kind": "probfig", "num": pr["num"], "page": r[1], "clips": r[0], "approx": r[2]})
                for kind, num in hw.find_refs(pr["text"]):
                    r = hw.find_ref(lay, docs[lay.path], kind, num, pr["clips"])
                    if r:
                        refs.append({"kind": kind, "num": num, "page": r[1], "clips": r[0], "approx": r[2]})
                    elif not self._ref_inside(lay, kind, num, pr["clips"]):
                        # 문제 조각 안에 이미 있는 그림이면 find_ref 가 None — 그때는 「못 찾음」 이 아님
                        missing.append(f"{hw.KIND_KO[kind]} {num}")
                pr["refs"], pr["missing"] = refs, missing
            prog("sheet", 0, "문제지 PDF 를 만드는 중", save=True)
            names = ", ".join(sorted({p.get("book_name", "") for p in problems if p.get("book_name")}))
            hw.build_sheet(sheet_path, f["name"], f"{course} · 교과서 {names or '-'} · 문제 {', '.join(nums)}",
                           problems, docs)
            summary = [{"num": p["num"], "label": p.get("label", p["num"]), "page": p.get("page"), "book": p.get("book"), "error": p.get("error", ""),
                        "refs": [{"kind": r["kind"], "num": r["num"], "page": r["page"], "approx": r["approx"]}
                                 for r in p.get("refs", [])], "missing": p.get("missing", [])} for p in problems]
            with self.lock:
                ff = self._file(fid)
                n, r = pdf_meta(sheet_path)
                ff["hw"].update(sheet=int(self.now()), problems=summary, sheet_pages=n, sheet_ratio=r)
                self._save()
        else:
            with self.lock:
                ff = self._file(fid)
                ff["hw"].pop("sheet", None)
                ff["hw"]["problems"] = []
                self._save()
            sheet_path.unlink(missing_ok=True)
        shutil.rmtree(self.root / "cache" / fid, ignore_errors=True)   # 다시 만든 문제지 · 해설지의 옛 쪽 그림
        if what == "sheet":
            self._job(fid, True, state="done", stage="sheet", pct=100, msg="문제지를 만들었어요.", ended=int(self.now()))
            return
        # 해설
        prog("solve", 0, "Claude 가 수업자료 · 교과서를 읽고 해설을 쓰는 중", save=True)
        R = self.root

        def tri(x):
            return (x["name"], str(R / "files" / f"{x['id']}.pdf"), str(R / "text" / f"{x['id']}.json"))
        solve_dir = R / "out" / f"{fid}-solve"
        shutil.rmtree(solve_dir, ignore_errors=True)
        images = hw.problem_images(problems, docs, solve_dir) if problems else None
        prompt = hw.solve_prompt(course, f["name"], mode, str(sheet_path) if problems else None,
                                 str(R / "files" / f"{fid}.pdf"), problems, [tri(x) for x in lectures],
                                 [tri(x) for x in books], images)
        expect = 90 + 75 * (len(problems) if problems else 4)      # 대략 걸리는 초 — 진행률 추산용

        def tick(sec):
            frac = 1 - math.exp(-sec / expect)                       # 끝을 모르니 천천히 100 에 다가감
            prog("solve", min(0.97, frac), f"Claude 가 해설을 쓰는 중 ({int(sec // 60)}분 {int(sec % 60)}초)")
        if self.solver:
            sol = self.solver(prompt, problems)
        else:
            from . import homework as _hw
            sol = _hw.run_claude(prompt, cwd=str(R), add_dirs=[str(R)], on_tick=tick)
        prog("solution", 0, "해설지 PDF 를 만드는 중", save=True)
        img = R / "out" / f"{fid}-img"
        shutil.rmtree(img, ignore_errors=True)
        hw.build_solution(R / "out" / f"{fid}-solution.pdf", f["name"], f"{course} · 해설지 (Claude 가 쓴 것 — 검산하며 보세요)",
                          sol, problems, docs, img)
        shutil.rmtree(img, ignore_errors=True)
        with self.lock:
            ff = self._file(fid)
            n, r = pdf_meta(R / "out" / f"{fid}-solution.pdf")
            ff["hw"].update(solution=int(self.now()), solution_pages=n, solution_ratio=r)
            self._save()
        self._job(fid, True, state="done", stage="solution", pct=100, msg="문제지와 해설지를 만들었어요."
                  if problems else "해설지를 만들었어요.", ended=int(self.now()))

    def _ref_inside(self, lay, kind: str, num: str, clips: list) -> bool:
        """참조(그림 P3.3 등)의 캡션이 문제 조각 안에 이미 있나"""
        from . import homework as hw
        if kind not in hw.CAPTION:
            return False
        head = re.compile(rf"^{hw.CAPTION[kind]}\s*{re.escape(num)}(?!\d)")
        for c in clips:
            for l in lay.lines[c.page]:
                if head.match(l.text) and l.y0 >= c.rect[1] - 2 and l.y1 <= c.rect[3] + 2 \
                        and l.x0 >= c.rect[0] - 2 and l.x1 <= c.rect[2] + 2:
                    return True
        return False

    def out_path(self, fid: str, kind: str) -> Path:
        with self.lock:
            self._file(fid)
        p = self.root / "out" / f"{fid}-{kind}.pdf"
        if not p.exists():
            raise StudyError("아직 만들지 않았어요.")
        return p

    def page_image(self, fid: str, page: int, width: int = 1000, variant: str = "") -> bytes:
        """자료 한 쪽을 그림(JPEG)으로 — 화면의 쪽 넘김 보기용. 어느 쪽을 보는지 알아야 「다 봄」 을 저절로 매김"""
        import pymupdf
        width = min((200, 600, 1000, 1400, 2000), key=lambda w: abs(w - int(width)))   # 몇 가지 너비로만 — 캐시가 맞게
        if variant not in ("", "sheet", "solution"):
            raise StudyError("모르는 종류예요.")
        src = self.out_path(fid, variant) if variant else self.pdf_path(fid)
        cdir = self.root / "cache" / fid
        hit = cdir / f"{variant or 'f'}-{width}-{page}.jpg"
        try:
            data = hit.read_bytes()
            os.utime(hit)                                     # 최근에 씀 — 캐시 정리 때 늦게 지움
            return data
        except FileNotFoundError:
            pass
        with pymupdf.open(str(src)) as doc:                   # 여는 것은 가벼움(쪽은 필요할 때만 읽음)
            if not 1 <= page <= len(doc):
                raise StudyError("없는 쪽이에요.")
            pg = doc[page - 1]
            zoom = width / max(1.0, pg.rect.width)
            pix = pg.get_pixmap(matrix=pymupdf.Matrix(zoom, zoom), alpha=False)
            data = pix.tobytes("jpeg", jpg_quality=72 if width > 300 else 60)
        cdir.mkdir(parents=True, exist_ok=True)
        tmp = hit.with_suffix(".tmp")
        tmp.write_bytes(data)
        os.replace(tmp, hit)
        self._cache_bytes = getattr(self, "_cache_bytes", None)
        if self._cache_bytes is None:
            self._cache_bytes = sum(p.stat().st_size for p in (self.root / "cache").rglob("*.jpg"))
        self._cache_bytes += len(data)
        if self._cache_bytes > PAGE_CACHE_MAX:
            self._trim_cache()
        return data

    def _trim_cache(self) -> None:
        """오래 안 본 쪽 그림부터 지워 상한의 80% 까지"""
        files = sorted(((p.stat().st_mtime, p.stat().st_size, p) for p in (self.root / "cache").rglob("*.jpg")))
        total = sum(sz for _, sz, _ in files)
        for _, sz, p in files:
            if total <= PAGE_CACHE_MAX * 0.8:
                break
            p.unlink(missing_ok=True)
            total -= sz
        self._cache_bytes = total

    # ── 나눠 올리기 · 이어 올리기 (큰 교과서 — 주인 11월 10일 20:35) ─────────────────
    def _up(self, up: str) -> Path:
        if not re.fullmatch(r"[0-9a-f]{16,64}", up or ""):
            raise StudyError("올리기 표가 틀렸어요.")
        return self.root / "incoming" / f"{up}.part"

    def upload_status(self, up: str) -> dict:
        p = self._up(up)
        return {"have": p.stat().st_size if p.exists() else 0}

    def upload_part(self, up: str, offset: int, data: bytes) -> dict:
        """offset 부터 이어 씀. 끊겼다 다시 오면 have 를 보고 그 뒤부터 보냄"""
        p = self._up(up)
        if len(data) > PART:
            raise StudyError("조각이 너무 커요.")
        with self.lock:
            have = p.stat().st_size if p.exists() else 0
            if offset != have:
                return {"have": have, "retry": True}           # 앞 조각이 덜 왔거나 이미 받은 조각
            if have + len(data) > MAX_PDF:
                p.unlink(missing_ok=True)
                raise StudyError("200MB 보다 큰 파일은 못 올려요.")
            with open(p, "ab") as fh:
                fh.write(data)
            return {"have": have + len(data)}

    def upload_done(self, up: str, course: str, name: str, kind: str, size: int) -> dict:
        p = self._up(up)
        if not p.exists() or p.stat().st_size != size:
            raise StudyError("파일이 다 오지 않았어요. 다시 올려 주세요.")
        with open(p, "rb") as fh:
            if fh.read(4) != b"%PDF":
                p.unlink(missing_ok=True)
                raise StudyError("PDF 만 올릴 수 있어요.")
        return self.add_file(course, name, b"", kind=kind, src=p)

    # ── 검색 ──────────────────────────────────────────────────────────────
    def search(self, q: str, course: str = "", limit: int = 60) -> list[dict]:
        """띄어쓰기 · 대소문자 무시. 모든 낱말이 같은 쪽에 있어야 맞음"""
        words = [w.lower() for w in q.split() if w.strip()]
        if not words:
            return []
        with self.lock:
            files = [f for f in self.db["files"] if not course or f["course"] == course]
        hits = []
        for f in files:
            try:
                pages = json.loads((self.root / "text" / f"{f['id']}.json").read_text())
            except FileNotFoundError:
                continue                                    # 아직 뽑는 중이거나 못 뽑음
            for i, text in enumerate(pages):
                low = text.lower()
                if all(w in low for w in words):
                    at = low.find(words[0])
                    a, b = max(0, at - 60), min(len(text), at + 100)
                    snip = ("…" if a else "") + text[a:b].replace("\n", " ") + ("…" if b < len(text) else "")
                    hits.append({"id": f["id"], "name": f["name"], "course": f["course"], "page": i + 1, "snip": snip})
                    if len(hits) >= limit:
                        return hits
        return hits

    # ── HTTP (phone.py 가 열쇠를 본 뒤 부름) ──────────────────────────────────
    def handle(self, method: str, path: str, q: dict, body: bytes | None):
        """→ (코드, 본문 bytes 또는 dict, 종류). dict 는 JSON 으로"""
        try:
            if method == "GET":
                if path == "/study/list":
                    return 200, self.list(), None
                m = re.fullmatch(r"/study/file/(f-[0-9a-f]+)\.pdf", path)
                if m:
                    return 200, self.pdf_path(m.group(1)), "application/pdf"     # 경로 — phone.py 가 조금씩 흘려 보냄
                m = re.fullmatch(r"/study/out/(f-[0-9a-f]+)-(sheet|solution)\.pdf", path)
                if m:
                    return 200, self.out_path(m.group(1), m.group(2)), "application/pdf"
                m = re.fullmatch(r"/study/page/(f-[0-9a-f]+)/(\d+)\.jpg", path)
                if m:
                    w = int((q.get("w") or ["1000"])[0] or 1000)
                    return 200, self.page_image(m.group(1), int(m.group(2)), w, (q.get("v") or [""])[0]), "image/jpeg"
                if path == "/study/chat":
                    return 200, self.chat.view((q.get("course") or [""])[0]), None
                if path == "/study/upload_status":
                    return 200, self.upload_status((q.get("up") or [""])[0]), None
                if path == "/study/search":
                    return 200, {"hits": self.search((q.get("q") or [""])[0], (q.get("course") or [""])[0])}, None
                return 404, {"error": "없는 길"}, None
            if path == "/study/upload_part":
                return 200, self.upload_part((q.get("up") or [""])[0], int((q.get("off") or ["0"])[0]), body or b""), None
            if path == "/study/upload":
                f = self.add_file((q.get("course") or [""])[0], (q.get("name") or [""])[0], body or b"",
                                  kind=(q.get("kind") or [""])[0])
                return 200, f, None
            d = json.loads(body or b"{}")
            if not isinstance(d, dict):
                raise StudyError("요청 모양이 틀렸어요.")
            if path == "/study/course":
                return 200, self.save_course(d), None
            if path == "/study/course_delete":
                self.delete_course(str(d.get("id", "")))
                return 200, {"r": "ok"}, None
            if path == "/study/file":
                return 200, self.update_file(d), None
            if path == "/study/chat":
                cid = str(d.get("course", ""))
                self._course(cid)
                return 200, self.chat.ask(cid, str(d.get("q", "")), str(d.get("file", "")), int(d.get("page") or 0),
                                          str(d.get("variant", "")), background=self.background), None
            if path == "/study/chat_reset":
                self.chat.reset(self._course(str(d.get("course", "")))["id"])
                return 200, {"r": "ok"}, None
            if path == "/study/chat_prep":
                cid = self._course(str(d.get("course", "")))["id"]
                if self.background:
                    self.chat.schedule(cid)
                else:
                    self.chat.prep(cid)
                return 200, self.chat.view(cid), None
            if path == "/study/upload_done":
                return 200, self.upload_done(str(d.get("up", "")), str(d.get("course", "")), str(d.get("name", "")),
                                             str(d.get("kind", "")), int(d.get("size", -1))), None
            if path == "/study/read_end":
                return 200, self.read_end(str(d.get("id", ""))), None
            if path == "/study/assignment":
                return 200, self.add_text_assignment(str(d.get("course", "")), str(d.get("name", "")),
                                                     str(d.get("text", ""))), None
            if path == "/study/hw":
                return 200, self.set_hw(d), None
            if path == "/study/hw_run":
                return 200, self.run_hw(str(d.get("id", "")), str(d.get("what", "all"))), None
            if path == "/study/file_delete":
                self.delete_file(str(d.get("id", "")))
                return 200, {"r": "ok"}, None
            return 404, {"error": "없는 길"}, None
        except StudyError as e:
            return 400, {"error": str(e)}, None
        except (ValueError, TypeError) as e:
            return 400, {"error": f"요청 모양이 틀렸어요({e})"}, None
