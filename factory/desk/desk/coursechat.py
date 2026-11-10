"""과목 비서 — 강의자료 탭의 「비서에게」 대화창 (주인 11월 10일 20:51 「지금 대화창 품질이 아주 나쁘다」).

과목마다 전담 Claude 세션 하나(claude-opus-5-5 · 추론 medium):
  - 미리 읽기: 자료를 올리면 그 과목의 자료를 하나씩 읽어 「자료별 요약 · 쪽 색인 · 핵심 정의/공식 · 문제 목록」 을
    chat/<과목>/digest/<자료>.md 로 둔다. 글이 안 뽑히는 쪽(손글씨 노트 · 스캔)은 쪽 그림을 보고 정리한다.
    교과서처럼 큰 자료는 Claude 로 통째 읽지 않고 글자 배치에서 목차(장 · 절 → 쪽)와 문제 번호 범위만 뽑는다.
  - 과목 지식 = 과목 정보 + 모든 자료 요약을 한 파일(course.md)로 묶어 시스템 프롬프트로 붙임(--append-system-prompt-file).
    매번 같은 앞부분이라 프롬프트 캐시가 맞는다.
  - 묻기: PDF 를 다시 읽히지 않고, 주인이 지금 보는 화면(자료 이름 · 쪽 번호 · 그 쪽 글 · 그 쪽 그림 경로)만 붙인다.
    같은 과목 안에서는 자료를 바꿔도 같은 세션(--resume)이 이어지고, 과목이 바뀌면 그 과목의 세션.
  - 맥락 줄이기: 세션 맥락이 COMPACT_TOKENS 를 넘으면 그 세션에게 대화 요약을 받아 두고 새 세션으로 갈아탄다.

    ~/lab/study-data/chat/<과목 id>.json            세션 id · 대화 기록 · 이전 대화 요약 · 미리 읽기 상태
    ~/lab/study-data/chat/<과목 id>/digest/<자료>.md  자료별 요약
    ~/lab/study-data/chat/<과목 id>/course.md        세션에 붙이는 과목 지식
    ~/lab/study-data/chat/<과목 id>/img/…            글이 없는 쪽 · 지금 보는 쪽의 그림
"""
from __future__ import annotations

import json
import logging
import os
import queue
import re
import shutil
import subprocess
import threading
import time
from pathlib import Path

log = logging.getLogger("deskd")

MODEL = "claude-opus-5-5"
EFFORT = "medium"
COMPACT_TOKENS = 110_000            # 세션 맥락이 이보다 크면 요약하고 새 세션 (비용 · 속도)
BIG_PAGES = 120                     # 이보다 긴 자료(교과서)는 Claude 로 통째 읽지 않고 목차만
IMG_PAGES_MAX = 40                  # 글 없는 쪽을 그림으로 읽을 때 한 자료에서 최대
DIGEST_TIMEOUT = 900
ASK_TIMEOUT = 300
HISTORY_MAX = 200


def _err(msg: str):
    from .study import StudyError                       # 주인에게 그대로 보일 까닭(400)
    return StudyError(msg)


def korean_error(msg: str) -> str:
    """Claude 의 영어 오류를 주인이 읽을 한국어로 — 사용량 한도는 초기화 시각까지"""
    m = re.search(r"hit your (.+?) limit\s*·?\s*resets ([^()]+)", msg)
    if m:
        kind = {"5-hour": "5시간", "weekly": "주간"}.get(m.group(1).strip(), m.group(1).strip())
        return f"Claude {kind} 사용량 한도에 걸렸어요. {m.group(2).strip()} 에 풀려요."
    return "Claude 쪽 오류: " + msg[:200]


def _now() -> float:
    return time.time()


def claude_json(prompt: str, cwd: str, add_dirs: list, timeout: int, resume: str = "", system_file: str = "",
                model: str = MODEL, effort: str = EFFORT) -> dict:
    """claude -p 한 번 → 결과 JSON. 읽기 도구만(쓰기 · 명령 · 인터넷 금지)"""
    exe = shutil.which("claude") or os.path.expanduser("~/.local/bin/claude")
    cmd = [exe, "-p", prompt, "--output-format", "json", "--model", model, "--effort", effort,
           "--permission-mode", "bypassPermissions", "--allowedTools", "Read,Grep,Glob",
           "--disallowedTools", "Bash,Write,Edit,NotebookEdit,WebFetch,WebSearch,Agent"]
    for d in add_dirs:
        cmd += ["--add-dir", d]
    if system_file:
        cmd += ["--append-system-prompt-file", system_file]
    if resume:
        cmd += ["--resume", resume]
    try:
        p = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        raise RuntimeError(f"{timeout // 60}분 안에 답이 안 와서 멈췄어요.")
    try:
        r = json.loads(p.stdout.strip().splitlines()[-1])
    except (ValueError, IndexError):
        log.error("과목 비서: claude 응답을 못 읽음 rc=%s err=%s", p.returncode, (p.stderr or "")[-400:])
        raise RuntimeError("Claude 가 응답하지 않았어요. 로그인이나 사용량 한도를 확인해 주세요.")
    if r.get("is_error"):
        raise RuntimeError(korean_error(str(r.get("result", ""))))
    return r


def context_tokens(r: dict) -> int:
    u = r.get("usage") or {}
    return int(u.get("input_tokens") or 0) + int(u.get("cache_read_input_tokens") or 0) + \
        int(u.get("cache_creation_input_tokens") or 0) + int(u.get("output_tokens") or 0)


class CourseChat:
    def __init__(self, study, runner=claude_json):
        self.st = study
        self.root = study.root / "chat"
        self.root.mkdir(parents=True, exist_ok=True)
        self.run = runner                                # 시험에서 가짜를 꽂음
        self.lock = threading.RLock()
        self._q: queue.Queue = queue.Queue()
        self._queued: set = set()
        self._worker = None
        self._asking: dict = {}                          # 과목 → 묻는 중인 스레드

    # ── 상태 파일 ────────────────────────────────────────────────────────────
    def _path(self, cid: str) -> Path:
        if not re.fullmatch(r"c-[0-9a-f]+", cid or ""):
            raise ValueError("과목 id 가 틀렸어요.")
        return self.root / f"{cid}.json"

    def _load(self, cid: str) -> dict:
        try:
            d = json.loads(self._path(cid).read_text())
        except FileNotFoundError:
            d = {}
        d.setdefault("sid", "")
        d.setdefault("history", [])
        d.setdefault("summary", "")
        d.setdefault("tokens", 0)
        d.setdefault("prep", {})
        return d

    def _save(self, cid: str, d: dict) -> None:
        p = self._path(cid)
        tmp = p.with_suffix(".tmp")
        tmp.write_text(json.dumps(d, ensure_ascii=False, indent=1))
        os.replace(tmp, p)

    def _dir(self, cid: str) -> Path:
        d = self.root / cid
        (d / "digest").mkdir(parents=True, exist_ok=True)
        (d / "img").mkdir(parents=True, exist_ok=True)
        return d

    # ── 미리 읽기 ────────────────────────────────────────────────────────────
    def schedule(self, cid: str) -> None:
        """그 과목에서 아직 안 읽은(또는 바뀐) 자료를 줄 세움. 한 번에 한 자료씩(사용량 · 맥 부하)"""
        with self.lock:
            if cid in self._queued:
                return
            self._queued.add(cid)
        self._q.put(cid)
        if self._worker is None or not self._worker.is_alive():
            self._worker = threading.Thread(target=self._loop, daemon=True, name="course-prep")
            self._worker.start()

    def _loop(self):
        while True:
            cid = self._q.get()
            with self.lock:
                self._queued.discard(cid)
            try:
                self.prep(cid)
            except Exception:  # noqa: BLE001 — 자료별 실패는 prep 이 상태에 적음. 여기는 다음 과목을 계속하려고
                log.exception("과목 비서: 미리 읽기 실패 %s", cid)

    def _files(self, cid: str) -> list:
        with self.st.lock:
            return [dict(f) for f in self.st.db["files"] if f["course"] == cid]

    def prep(self, cid: str) -> None:
        files = self._files(cid)
        for f in files:
            with self.lock:
                d = self._load(cid)
                cur = d["prep"].get(f["id"]) or {}
            if cur.get("state") == "done" and cur.get("size") == f.get("size") and cur.get("name") == f.get("name") \
                    and cur.get("kind") == f.get("kind"):
                continue
            if f.get("pages") is None and not f.get("index_error"):
                continue                                 # 아직 쪽 수 · 글을 뽑는 중 — 끝나면 다시 불림
            self._set_prep(cid, f["id"], state="running", at=_now())
            try:
                text = self.digest_file(cid, f)
                (self._dir(cid) / "digest" / f"{f['id']}.md").write_text(text)
                self._set_prep(cid, f["id"], state="done", size=f.get("size"), name=f.get("name"),
                               kind=f.get("kind"), at=_now(), error="")
            except Exception as e:  # noqa: BLE001 — 주인에게 보이고 로그에 남김. 다른 자료는 계속
                log.exception("과목 비서: %s 미리 읽기 실패", f["id"])
                self._set_prep(cid, f["id"], state="error", error=str(e)[:200], at=_now())
            self.build_course(cid)
        # 지운 자료의 요약 정리
        alive = {f["id"] for f in files}
        with self.lock:
            d = self._load(cid)
            for fid in list(d["prep"]):
                if fid not in alive:
                    d["prep"].pop(fid)
                    (self._dir(cid) / "digest" / f"{fid}.md").unlink(missing_ok=True)
            self._save(cid, d)
        self.build_course(cid)

    def _set_prep(self, cid: str, fid: str, **kw) -> None:
        with self.lock:
            d = self._load(cid)
            d["prep"].setdefault(fid, {}).update(kw)
            self._save(cid, d)

    def _pages(self, fid: str) -> list:
        try:
            return json.loads((self.st.root / "text" / f"{fid}.json").read_text())
        except FileNotFoundError:
            return []

    def textbook_toc(self, f: dict) -> str:
        """큰 자료(교과서): 글자 배치에서 장 · 절 제목과 쪽, 쪽마다 처음 나오는 문제 번호"""
        from . import homework as hw
        src = str(self.st.root / "files" / f"{f['id']}.pdf")
        cache = self.st.root / "text" / f"{f['id']}.layout.json"
        lay = hw.load_layout(src, cache)
        if lay is None:
            lay = hw.build_layout(src)
            hw.save_layout(lay, cache)
        out, probs = [], {}
        for p, pl in enumerate(lay.lines):
            for l in sorted(pl, key=lambda l: l.y0):
                if l.size >= lay.body * 1.25 and 3 <= len(l.text) <= 90 and re.match(r"^(\d|Chapter|CHAPTER|[A-Z][a-z])", l.text):
                    out.append(f"- {p + 1}쪽: {l.text}")
                m = hw.GENERIC.match(l.text)
                if m and not hw._is_heading(l, lay.body):
                    ch = int(m.group(1))
                    probs.setdefault(ch, []).append((p + 1, f"{m.group(1)}–{m.group(2)}"))
        lines = [f"# 교과서 「{f['name']}」 ({len(lay.lines)}쪽) — 목차(큰 제목과 쪽)"] + out[:600]
        if probs:
            lines.append("\n## 연습문제 번호가 있는 쪽")
            for ch in sorted(probs):
                xs = probs[ch]
                lines.append(f"- {ch}장: {xs[0][1]}({xs[0][0]}쪽) ~ {xs[-1][1]}({xs[-1][0]}쪽)")
        lines.append(f"\n본문 글(쪽별 JSON 배열): {self.st.root / 'text' / (f['id'] + '.json')} — 필요하면 Grep 으로 찾는다.")
        return "\n".join(lines)

    def digest_file(self, cid: str, f: dict) -> str:
        n = f.get("pages") or 0
        if f.get("kind") == "textbook" or n > BIG_PAGES:
            return self.textbook_toc(f)
        pages = self._pages(f["id"])
        blank = [i + 1 for i, t in enumerate(pages) if len(t.strip()) < 30]
        imgs = []
        for p in blank[:IMG_PAGES_MAX]:                  # 손글씨 · 스캔 쪽은 그림으로
            out = self._dir(cid) / "img" / f"{f['id']}-{p}.jpg"
            if not out.exists():
                out.write_bytes(self.st.page_image(f["id"], p, 1400))
            imgs.append((p, str(out)))
        kind = {"lecture": "수업자료", "assignment": "과제", "textbook": "교과서"}.get(f.get("kind"), "자료")
        img_txt = "\n".join(f"- {p}쪽 그림: {path}" for p, path in imgs) or "- (없음)"
        more = f"\n(글 없는 쪽이 {len(blank)}쪽이라 앞 {IMG_PAGES_MAX}쪽만 그림으로 준다.)" if len(blank) > IMG_PAGES_MAX else ""
        prompt = f"""과목 공부용 자료 하나를 읽고, 나중에 이 과목 질문에 답할 때 쓸 정리 노트를 쓴다.

자료: 「{f['name']}」 ({kind}, {n}쪽)
쪽별 본문(JSON 배열, 0번 = 1쪽): {self.st.root / 'text' / (f['id'] + '.json')}
글이 안 뽑히는 쪽(손글씨 · 스캔) — 그림을 Read 로 직접 보고 읽어라:
{img_txt}{more}

정리 노트 모양(마크다운, 한국어, 3000자 안):
# {f['name']} ({kind})
한 줄 요약
## 쪽 색인
- 3쪽: … (그 쪽에서 다루는 개념 · 정의 · 예제 · 문제 번호를 짧게. 비슷한 쪽은 묶어도 됨: 「5~7쪽: …」)
## 핵심 정의 · 공식
- 기호와 뜻까지
## 문제 · 예제
- 번호와 한 줄 (과제 · 연습문제 자료면 모든 문제를)

지어내지 말고 자료에 있는 것만. 손글씨를 못 읽은 곳은 「(판독 어려움)」 이라고 쓴다. 정리 노트만 출력한다."""
        r = self.run(prompt, cwd=str(self.st.root), add_dirs=[str(self.st.root)], timeout=DIGEST_TIMEOUT)
        text = (r.get("result") or "").strip()
        if not text:
            raise RuntimeError("정리가 비어 있어요.")
        return text

    def build_course(self, cid: str) -> Path:
        """과목 지식 파일 — 세션 시스템 프롬프트로 붙임. 자료 순서가 같으면 내용도 같아 캐시가 맞음"""
        with self.st.lock:
            c = next((x for x in self.st.db["courses"] if x["id"] == cid), {})
        files = self._files(cid)
        dd = self._dir(cid)
        parts = [f"""너는 이 과목 「{c.get('name', '')}」의 전담 공부 도우미다. 주인(대학생)이 강의자료를 보면서 묻는다.
- 답은 한국어로, 번역투 없이. 시험공부에 바로 쓰이게 핵심부터. 수식은 유니코드로(LaTeX 금지).
- 이 과목 자료 전체를 아래 「자료 정리」로 이미 알고 있다. 묻는 쪽만 보고 답하지 말고 **다른 자료와 이어서** 답한다:
  예) 「이건 LN5 12쪽 내용이고, Exercise 05 의 P5.14 에 그대로 쓰여요.」 — 자료 이름과 쪽을 정확히.
- 질문에는 주인이 지금 보는 쪽(자료 이름 · 쪽 번호 · 그 쪽 글 · 그 쪽 그림 경로)이 붙어 온다. 그림이 필요하면 Read 로 본다.
- 정리에 없는 세부가 필요할 때만 쪽별 본문 JSON({self.st.root / 'text'}/<자료 id>.json)을 Grep 으로 찾는다. PDF 를 통째로 다시 읽지 않는다.
- 모르면 모른다고 한다. 지어내지 않는다.
""",
                 f"# 과목 정보\n시험 날짜: {c.get('exam') or '모름'}\n시험 범위 · 교수님 말씀: {c.get('scope') or '-'}\n"]
        parts.append("# 자료 정리 (자료 id → 정리)")
        for f in sorted(files, key=lambda x: (x.get("kind") != "lecture", x.get("added", 0))):
            p = dd / "digest" / f"{f['id']}.md"
            body = p.read_text() if p.exists() else "(아직 미리 읽지 않음)"
            parts.append(f"\n---\n자료 id {f['id']} · 「{f['name']}」 · {f.get('pages') or '?'}쪽\n{body}")
        out = dd / "course.md"
        out.write_text("\n".join(parts))
        return out

    # ── 묻기 ───────────────────────────────────────────────────────────────
    def view(self, cid: str) -> dict:
        with self.lock:
            d = self._load(cid)
        files = self._files(cid)
        prep = d["prep"]
        done = sum(1 for f in files if (prep.get(f["id"]) or {}).get("state") == "done")
        running = next((f["name"] for f in files if (prep.get(f["id"]) or {}).get("state") == "running"), "")
        errors = [f"{f['name']}: {(prep.get(f['id']) or {}).get('error')}" for f in files
                  if (prep.get(f["id"]) or {}).get("state") == "error"]
        return {"history": d["history"][-60:], "prep": {"done": done, "total": len(files), "running": running,
                                                       "errors": errors[:5]},
                "tokens": d["tokens"], "compact_at": COMPACT_TOKENS, "summary": bool(d["summary"]),
                "asking": cid in self._asking}

    def ask(self, cid: str, q: str, fid: str = "", page: int = 0, variant: str = "", background: bool = True) -> dict:
        q = str(q or "").strip()[:4000]
        if not q:
            raise _err("물어볼 말을 써 주세요.")
        with self.lock:
            if cid in self._asking:
                raise _err("앞 질문에 답하는 중이에요. 잠깐만요.")
            d = self._load(cid)
            ent = {"id": f"m{int(_now() * 1000)}", "q": q, "a": None, "t": int(_now()), "file": fid, "page": page,
                   "variant": variant}
            d["history"].append(ent)
            d["history"] = d["history"][-HISTORY_MAX:]
            self._save(cid, d)
            self._asking[cid] = True
        args = (cid, ent["id"], q, fid, page, variant)
        if background:
            threading.Thread(target=self._answer, args=args, daemon=True, name="course-ask").start()
        else:
            self._answer(*args)
        return ent

    def _screen(self, cid: str, fid: str, page: int, variant: str) -> str:
        """지금 보는 화면 — 자료 이름 · 쪽 · 그 쪽 글 · 그 쪽 그림 경로"""
        if not fid:
            return "[지금 보는 화면] 자료를 열지 않음"
        with self.st.lock:
            f = next((x for x in self.st.db["files"] if x["id"] == fid), None)
        if not f:
            return "[지금 보는 화면] (지운 자료)"
        name = f["name"] + {"sheet": " (문제지)", "solution": " (해설지)"}.get(variant, "")
        txt = ""
        if not variant:
            pages = self._pages(fid)
            txt = pages[page - 1] if 0 < page <= len(pages) else ""
        img = ""
        try:
            out = self._dir(cid) / "img" / f"now-{fid}-{variant or 'f'}-{page}.jpg"
            out.write_bytes(self.st.page_image(fid, max(1, page), 1400, variant))
            img = str(out)
        except Exception:  # noqa: BLE001 — 그림을 못 그려도 글 · 쪽 번호로 묻기는 됨. 로그에 남김
            log.exception("과목 비서: 지금 보는 쪽 그림 실패 %s %s", fid, page)
        return (f"[지금 보는 화면] 자료 「{name}」 (자료 id {fid}) · {page}/{f.get('pages') or '?'}쪽\n"
                f"이 쪽 그림: {img or '(없음)'}\n이 쪽 글:\n{(txt or '(글 없음 — 손글씨 · 그림이면 그림을 Read 로 볼 것)')[:3500]}")

    def _answer(self, cid, mid, q, fid, page, variant):
        try:
            system = self.build_course(cid)
            with self.lock:
                d = self._load(cid)
            prompt = self._screen(cid, fid, page, variant) + f"\n\n[질문] {q}"
            if not d["sid"] and d["summary"]:
                prompt = f"[이전 대화 요약 — 맥락이 길어 새로 시작함]\n{d['summary']}\n\n" + prompt
            r = self.run(prompt, cwd=str(self._dir(cid)), add_dirs=[str(self.st.root)], timeout=ASK_TIMEOUT,
                         resume=d["sid"], system_file=str(system))
            a, sid, tok = (r.get("result") or "").strip() or "(답이 비었어요)", r.get("session_id") or d["sid"], context_tokens(r)
            with self.lock:
                d = self._load(cid)
                for e in d["history"]:
                    if e["id"] == mid:
                        e["a"] = a
                d["sid"], d["tokens"] = sid, tok
                self._save(cid, d)
            if tok > COMPACT_TOKENS:
                self.compact(cid)
        except Exception as e:  # noqa: BLE001 — 답 칸에 까닭을 보이고 로그에 남김
            log.exception("과목 비서: 답 실패 %s", cid)
            with self.lock:
                d = self._load(cid)
                for x in d["history"]:
                    if x["id"] == mid:
                        x["a"], x["error"] = f"답을 못 받았어요: {e}", True
                self._save(cid, d)
        finally:
            with self.lock:
                self._asking.pop(cid, None)

    def compact(self, cid: str) -> None:
        """맥락이 커짐 → 지금 세션에게 대화 요약을 받고 세션을 비움(다음 질문은 새 세션 + 요약)"""
        with self.lock:
            d = self._load(cid)
        if not d["sid"]:
            return
        try:
            r = self.run("지금까지 이 대화에서 주인이 물은 것 · 헷갈려한 것 · 정리해 준 결론을 다음 대화에 넘길 메모로 "
                         "1500자 안에 정리해 줘. 메모만 출력.", cwd=str(self._dir(cid)), add_dirs=[str(self.st.root)],
                         timeout=ASK_TIMEOUT, resume=d["sid"], system_file=str(self._dir(cid) / "course.md"))
            summary = (r.get("result") or "").strip()
        except Exception:  # noqa: BLE001 — 요약을 못 받아도 새 세션으로는 감(맥락이 계속 커지지 않게). 로그에 남김
            log.exception("과목 비서: 대화 요약 실패 %s", cid)
            summary = d["summary"]
        with self.lock:
            d = self._load(cid)
            d.update(sid="", tokens=0, summary=summary[:3000])
            self._save(cid, d)

    def reset(self, cid: str) -> None:
        """「새 대화」 — 기록은 남기고 세션만 새로"""
        with self.lock:
            d = self._load(cid)
            d.update(sid="", tokens=0, summary="")
            d["history"].append({"id": f"m{int(_now() * 1000)}", "sys": "새 대화를 시작했어요. 과목 자료 정리는 그대로 알고 있어요.",
                                 "t": int(_now())})
            self._save(cid, d)
