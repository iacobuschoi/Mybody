"""강의자료 — 비서 웹의 「강의자료」 탭 (주인 11월 10일: 시험공부용, 다루기 편하게).

과목마다 PDF 를 모아 두고, 자료마다 공부 상태 · 메모 · 쪽 표시를 남기고, 모든 자료의 본문을 검색하고,
비서에게 "이 자료로 예상 문제" 처럼 물을 수 있게 합니다(비서는 이 맥의 파일 경로를 받아 직접 읽음).

    ~/lab/study-data/
        study.json          과목 · 자료 목록(메모 · 표시 · 상태 포함)
        files/<id>.pdf      올린 자료
        text/<id>.json      쪽별 본문(검색용, 올릴 때 뽑음)
        trash/              지운 자료(되살릴 수 있게 지우지 않고 옮김)

길(모두 phone.py 의 열쇠 검사를 거친 뒤):
    GET  /study/list · /study/file/<id>.pdf · /study/search?q=&course=
    POST /study/course {id?, name, exam, scope, todo} · /study/course_delete {id}
    POST /study/upload?course=&name=  (본문 = PDF) · /study/file {id, …바꿀 칸} · /study/file_delete {id}
"""
from __future__ import annotations

import json
import logging
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
STATUS = ("new", "reading", "done", "review")          # 안 봄 · 보는 중 · 다 봄 · 다시 볼 것
FILE_FIELDS = {"status", "note", "marks", "course", "name", "last_page"}
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
    """쪽별 본문. 글자가 없는 쪽(스캔 그림)은 빈 글"""
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
    def __init__(self, root: str = DATA_DIR, now=time.time, background: bool = True):
        self.root = Path(os.path.expanduser(root))
        self.now = now
        self.background = background
        self.lock = threading.RLock()
        for d in ("files", "text", "trash"):
            (self.root / d).mkdir(parents=True, exist_ok=True)
        self.db = self._load()

    # ── 저장 ──────────────────────────────────────────────────────────────
    def _load(self) -> dict:
        p = self.root / "study.json"
        try:
            db = json.loads(p.read_text())
        except FileNotFoundError:
            db = {}
        db.setdefault("courses", [])
        db.setdefault("files", [])
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
    def add_file(self, course: str, name: str, data: bytes) -> dict:
        if not data.startswith(b"%PDF"):
            raise StudyError("PDF 만 올릴 수 있어요.")
        if len(data) > MAX_PDF:
            raise StudyError("200MB 보다 큰 파일은 못 올려요.")
        name = re.sub(r"\.pdf$", "", Path(name or "자료").name, flags=re.I).strip() or "자료"
        with self.lock:
            self._course(course)
            fid = _id("f-")
            (self.root / "files" / f"{fid}.pdf").write_bytes(data)
            f = {"id": fid, "course": course, "name": name[:200], "size": len(data), "pages": None,
                 "status": "new", "note": "", "marks": [], "last_page": 1, "added": int(self.now())}
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
        try:
            pages = pdf_text(src)
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
            self._save()

    def update_file(self, d: dict) -> dict:
        with self.lock:
            f = self._file(str(d.get("id", "")))
            new = {}                                         # 다 검사한 뒤에 한꺼번에 넣음(일부만 바뀐 채 남지 않게)
            for k in FILE_FIELDS & d.keys():
                v = d[k]
                if k == "status" and v not in STATUS:
                    raise StudyError("모르는 상태예요.")
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
            f.update(new)
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
            self.db["files"].remove(f)
            self._save()

    def import_dir(self, course: str, folder: str, pattern: str = "*.pdf") -> list[dict]:
        """폴더의 PDF 를 이름순으로 가져옴(이미 같은 이름이 있으면 건너뜀)"""
        have = {(f["course"], f["name"]) for f in self.db["files"]}
        out = []
        for p in sorted(Path(os.path.expanduser(folder)).glob(pattern)):
            if (course, p.stem) not in have:
                out.append(self.add_file(course, p.name, p.read_bytes()))
        return out

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
                    p = self.pdf_path(m.group(1))
                    return 200, p.read_bytes(), "application/pdf"
                if path == "/study/search":
                    return 200, {"hits": self.search((q.get("q") or [""])[0], (q.get("course") or [""])[0])}, None
                return 404, {"error": "없는 길"}, None
            if path == "/study/upload":
                f = self.add_file((q.get("course") or [""])[0], (q.get("name") or [""])[0], body or b"")
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
            if path == "/study/file_delete":
                self.delete_file(str(d.get("id", "")))
                return 200, {"r": "ok"}, None
            return 404, {"error": "없는 길"}, None
        except StudyError as e:
            return 400, {"error": str(e)}, None
        except (ValueError, TypeError) as e:
            return 400, {"error": f"요청 모양이 틀렸어요({e})"}, None
