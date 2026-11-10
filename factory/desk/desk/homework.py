"""과제 → 문제지 · 해설지 PDF (주인 11월 10일 20:23 · 20:26).

강의자료 탭에서 과제를 올리면:
  1. 과제 글에서 문제 번호(3.2, 3.5, 4.1 …)를 뽑는다. 번호만 나열된 과제면 「번호 모드」.
  2. 번호 모드면 같은 과목의 교과서에서 그 문제 본문을 찾아 쪽에서 그대로 잘라 온다(수식 · 그림이 깨지지 않게
     글을 다시 치지 않고 PDF 의 그 부분을 벡터로 옮김). 문제가 가리키는 그림 · 표 · 예제 · 식도 찾아 잘라
     문제 옆(좁으면 바로 아래)에 붙인다 → 문제지 PDF.
  3. Claude 가 문제지 · 수업자료 · 교과서를 읽고 해설을 쓴다 → 같은 문제지 기준의 해설지 PDF.

교과서 찾기는 글자 배치(쪽 · 줄 위치 · 글씨 크기)로 한다:
  - 「3.2」 로 시작하는 줄 가운데, 절 제목(큰 글씨)이 아니고, 「Problems」 같은 연습문제 머리 뒤에 있고,
    이웃 번호(3.1 · 3.3)가 같은 들여쓰기에 있는 것을 고른다.
  - 문제의 끝 = 같은 들여쓰기의 다음 문제 번호 · 큰 제목 · 쪽 끝(두 단이면 오른쪽 단, 아니면 다음 쪽으로 이어짐).
  - 그림 · 표는 「Figure 3.4」 로 시작하는 캡션 줄 근처의 그림 · 선 묶음을, 예제는 「Example 3.2」 부터 다음 예제 ·
    제목까지를 자른다. 못 찾은 것은 문제지에 「못 찾음」 으로 적는다(조용히 빼지 않음).
"""
from __future__ import annotations

import html as _html
import json
import logging
import os
import re
import shutil
import subprocess
import time
from dataclasses import dataclass, field
from pathlib import Path

log = logging.getLogger("deskd")

# ── 진행률: 단계와 가중치(합 100) — 주인 11월 10일 20:26 「단계별 가중치로 추산」 ──────────────
STAGES = [
    ("read", "교과서 읽기", 10),
    ("find", "문제 찾기", 10),
    ("crop", "그림 · 예제 캡처", 15),
    ("sheet", "문제지 PDF", 5),
    ("solve", "해설 쓰기", 55),
    ("solution", "해설지 PDF", 5),
]
STAGE_W = {k: w for k, _, w in STAGES}
STAGE_NAME = {k: n for k, n, _ in STAGES}


def pct_at(stage: str, frac: float = 0.0, skip: tuple = ()) -> int:
    """stage 의 frac(0~1) 만큼 왔을 때의 전체 퍼센트. skip: 이번 일에서 안 하는 단계(번호 모드가 아니면 문제 찾기 등)"""
    tot = sum(w for k, _, w in STAGES if k not in skip)
    done = 0.0
    for k, _, w in STAGES:
        if k in skip:
            continue
        if k == stage:
            done += w * max(0.0, min(1.0, frac))
            break
        done += w
    return int(round(100 * done / tot)) if tot else 0


# ── 과제 글에서 문제 번호 뽑기 ───────────────────────────────────────────────
# 3.2 · 4-12 · 4–12 (Hibbeler 처럼 장-번호를 줄표로 쓰는 교과서도). 안에서는 모두 「4.12」 로
SEP = r"\s*[.\-–—]\s*"
NUM = rf"(\d{{1,2}}){SEP}(\d{{1,3}})"
DOTNUM = r"(\d{1,2})\s*\.\s*(\d{1,3})"
RANGE = re.compile(rf"(?<![\d.\-–]){DOTNUM}\s*(?:~|–|—|-|to|부터)\s*(?:{DOTNUM}|(\d{{1,3}}))(?![\d.]?\d)|"
                   rf"(?<![\d.\-–]){NUM}\s*(?:~|to|부터)\s*(?:{NUM}|(\d{{1,3}}))(?![\d.]?\d)")
SINGLE = re.compile(rf"(?<![\d.\-–—/]){NUM}(?![\d]|[.\-–—/]\d)")
# 번호 말고 있어도 되는 말 — 이것만 남으면 「번호만 나열된 과제」
FILLER = re.compile(
    r"(?i)\b(?:problems?|prob|ex(?:ercises?)?|chapter|ch|sections?|sec|homework|hw|assignment|textbook|text|book|"
    r"due|by|and|or|the|of|from|page|pages|pp?|odd|even|all|do|solve|submit|week|set|no)\b|"
    r"과제|숙제|문제|번|교과서|책|풀기|풀어|풀이|제출|마감|까지|및|장|절|쪽|주차|이름|학번|"
    r"\d{4}[-./]\d{1,2}[-./]\d{1,2}|\d+|[^\w]")


def parse_numbers(text: str) -> list[str]:
    """「3.2, 3.5, 4.1」 「3.2~3.5」 「P3.7」 → ['3.2', '3.5', …]. 순서는 처음 나온 대로, 겹치면 한 번"""
    found: list[tuple] = []                              # (글 안 자리, 번호)

    def add(c, n, at):
        found.append((at, f"{int(c)}.{int(n)}"))
    used = []
    for m in RANGE.finditer(text):
        g = m.groups()
        c1, n1, c2, n2, n3 = g[:5] if g[0] else g[5:]
        if c2 and int(c2) != int(c1):
            continue                                    # 3.9~4.2 처럼 장을 넘는 범위는 두 번호로만
        lo, hi = int(n1), int(n2 or n3)
        if 0 < hi - lo <= 40:
            for n in range(lo, hi + 1):
                add(c1, n, m.start() + (n - lo) * 1e-3)
            used.append(m.span())
    for m in SINGLE.finditer(text):
        if any(a <= m.start() < b for a, b in used):
            continue
        add(m.group(1), m.group(2), m.start())
    out: list[str] = []
    for _, k in sorted(found):
        if k not in out:
            out.append(k)
    return out


def numbers_only(text: str) -> bool:
    """과제가 문제 번호 나열뿐인가 — 번호와 흔한 말(Problems · 마감 · 이름 · 학번 …)을 빼면 낱말이 거의 안 남음"""
    if not parse_numbers(text):
        return False
    rest = SINGLE.sub(" ", RANGE.sub(" ", text))
    rest = FILLER.sub(" ", rest)
    words = [w for w in rest.split() if len(w) > 1]
    # 홍길동 같은 이름 · 과목 이름 한두 마디는 봐 줌
    return len(words) <= 12


# ── 교과서 글자 배치 ────────────────────────────────────────────────────────
@dataclass(slots=True)
class Line:
    page: int
    x0: float
    y0: float
    x1: float
    y1: float
    size: float
    bold: bool
    block: int
    text: str

    @property
    def rect(self):
        import pymupdf
        return pymupdf.Rect(self.x0, self.y0, self.x1, self.y1)


@dataclass
class Layout:
    path: str
    sizes: list                                         # 쪽마다 (너비, 높이)
    lines: list                                         # 쪽마다 [Line]
    body: float = 10.0                                  # 본문 글씨 크기(가장 흔한 크기)
    _graphics: dict = field(default_factory=dict)

    def graphics(self, doc, p: int) -> list:
        """그 쪽의 그림 · 선 묶음 사각형(쪽 전체 배경 · 아주 작은 점은 뺌)"""
        if p not in self._graphics:
            import pymupdf
            pg = doc[p]
            W, H = pg.rect.width, pg.rect.height
            out = []
            try:
                for im in pg.get_image_info():
                    out.append(pymupdf.Rect(im["bbox"]))
            except Exception:  # noqa: BLE001 — 그림 정보가 깨진 쪽: 선만으로 자름. 로그에 남김
                log.exception("과제: %s 쪽 그림 정보를 못 읽음", p + 1)
            try:
                for d in pg.get_drawings():
                    out.append(pymupdf.Rect(d["rect"]))
            except Exception:  # noqa: BLE001 — 위와 같음
                log.exception("과제: %s 쪽 선 정보를 못 읽음", p + 1)
            keep = []
            for r in out:
                if r.width < 1:                         # 세로 · 가로 선은 넓이가 0 이라 겹침 검사에 안 걸림 → 1pt 두께로
                    r = pymupdf.Rect(r.x0 - 0.5, r.y0, r.x1 + 0.5, r.y1)
                if r.height < 1:
                    r = pymupdf.Rect(r.x0, r.y0 - 0.5, r.x1, r.y1 + 0.5)
                r = r & pg.rect
                if r.is_empty:
                    continue
                if r.width * r.height > 0.8 * W * H:
                    continue                            # 쪽 배경
                if r.width < 2 and r.height < 2:
                    continue
                if r.y1 < H * 0.05 or r.y0 > H * 0.95:
                    continue                            # 머리 · 꼬리의 장식 선
                keep.append(r)
            self._graphics[p] = keep
        return self._graphics[p]


def build_layout(path: str, progress=None) -> Layout:
    import pymupdf
    doc = pymupdf.open(path)
    sizes, lines = [], []
    hist: dict = {}
    n = len(doc)
    for p in range(n):
        pg = doc[p]
        sizes.append((pg.rect.width, pg.rect.height))
        pl = []
        try:
            d = pg.get_text("dict", flags=0)
        except Exception:  # noqa: BLE001 — 깨진 쪽 하나 때문에 교과서 전체를 버리지 않음. 그 쪽은 빈 쪽으로
            log.exception("과제: 교과서 %s 쪽 글자 배치를 못 읽음", p + 1)
            d = {"blocks": []}
        for bi, b in enumerate(d.get("blocks", [])):
            for ln in b.get("lines", []):
                spans = [s for s in ln.get("spans", []) if s.get("text", "").strip()]
                if not spans:
                    continue
                text = "".join(s["text"] for s in ln["spans"]).strip()
                big = max(spans, key=lambda s: len(s["text"]))
                size = round(float(big["size"]), 1)
                bold = bool(big.get("flags", 0) & 16) or "bold" in big.get("font", "").lower()
                x0, y0, x1, y1 = ln["bbox"]
                pl.append(Line(p, x0, y0, x1, y1, size, bold, bi, text))
                hist[size] = hist.get(size, 0) + len(text)
        lines.append(pl)
        if progress and (p % 20 == 0 or p == n - 1):
            progress((p + 1) / n)
    body = max(hist, key=hist.get) if hist else 10.0
    return Layout(path, sizes, lines, body)


def save_layout(lay: Layout, out: Path) -> None:
    d = {"v": 1, "sizes": lay.sizes, "body": lay.body,
         "lines": [[[l.x0, l.y0, l.x1, l.y1, l.size, int(l.bold), l.block, l.text] for l in pl] for pl in lay.lines]}
    tmp = out.with_suffix(".tmp")
    tmp.write_text(json.dumps(d, ensure_ascii=False))
    os.replace(tmp, out)


def load_layout(path: str, cache: Path) -> Layout | None:
    try:
        d = json.loads(cache.read_text())
    except (FileNotFoundError, ValueError):
        return None
    if d.get("v") != 1:
        return None
    lines = [[Line(p, *l[:5], bool(l[5]), l[6], l[7]) for l in pl] for p, pl in enumerate(d["lines"])]
    return Layout(path, [tuple(s) for s in d["sizes"]], lines, d["body"])


# ── 교과서에서 문제 · 그림 찾기 ──────────────────────────────────────────────
LEAD = r"(?:[*•●■▪◆#†]\s*)?(?:(?:P|Problem|PROBLEM)\s*)?"   # 「Prob. 2–10」 은 그림 캡션이라 뺌
GENERIC = re.compile(rf"^{LEAD}(\d{{1,2}}){SEP}(\d{{1,3}})(?!\d)(?![.\-–]\d)(?=[\s.:)\]]|$)")
PROBLEMS_HEAD = re.compile(r"^(?:Problems|PROBLEMS|Exercises|EXERCISES|Homework Problems|Problem Set|"
                           r"Review Questions|연습\s*문제|장\s*말\s*문제)\b")
CHAPTER_HEAD = re.compile(r"^(?:Chapter|CHAPTER)\s+\d+|^제\s*\d+\s*장")


def _label(num: str):
    c, n = num.split(".")
    return re.compile(rf"^{LEAD}{int(c)}{SEP}{int(n)}(?!\d)(?![.\-–]\d)(?=[\s.:)\]]|$)")


def _is_heading(l: Line, body: float) -> bool:
    return l.size >= body * 1.12 or bool(CHAPTER_HEAD.match(l.text))


@dataclass
class Clip:
    page: int                                           # 0 부터
    rect: tuple                                         # (x0, y0, x1, y1)
    src: str = ""                                       # 어느 교과서 PDF 인가(교과서가 여럿일 때)


def _doc(tb, clip: Clip):
    """tb: 교과서 Document 하나, 또는 {경로: Document}"""
    return tb[clip.src] if isinstance(tb, dict) else tb


@dataclass
class Found:
    num: str
    clips: list
    text: str
    label: str = ""                                     # 교과서에 찍힌 모양 그대로(「4–12」)


def _columns(lay: Layout, p: int, x0: float):
    """줄이 있는 단의 가로 범위. 두 단 쪽이면 그 줄이 있는 단, 아니면 쪽 전체"""
    W = lay.sizes[p][0]
    pl = lay.lines[p]
    mid = W / 2
    left = sum(1 for l in pl if l.x1 <= mid + 6)
    right = sum(1 for l in pl if l.x0 >= mid - 6)
    across = sum(1 for l in pl if l.x0 < mid - 30 and l.x1 > mid + 30)
    two = left >= 6 and right >= 6 and across <= 0.25 * max(1, len(pl))
    if not two:
        return (0.0, W), False
    return ((mid - 6, W) if x0 >= mid - 6 else (0.0, mid + 6)), True


def _in_col(l: Line, col) -> bool:
    return l.x0 >= col[0] - 2 and l.x1 <= col[1] + 2


def _body_lines(lay: Layout, p: int, col):
    """머리 · 꼬리(쪽 번호 · 머리글)를 뺀 그 단의 줄을 위에서 아래로"""
    H = lay.sizes[p][1]
    out = []
    for l in lay.lines[p]:
        if not _in_col(l, col):
            continue
        if (l.y1 < H * 0.06 or l.y0 > H * 0.94) and len(l.text) < 80:
            continue
        out.append(l)
    return sorted(out, key=lambda l: (round(l.y0, 0), l.x0))


def _flow(lay: Layout, start: Line, stop, max_segments: int = 3, doc=None, max_gap: float = 0) -> list:
    """start 줄부터 stop(줄) 이 참인 줄 바로 앞까지 — 단 끝이면 다음 단 · 다음 쪽으로 이어 감. → [(쪽, 단, 줄들)]"""
    p = start.page
    col, two = _columns(lay, p, start.x0)
    segs = []
    first = True
    while len(segs) < max_segments and p < len(lay.lines):
        rows = _body_lines(lay, p, col)
        if first:
            rows = [l for l in rows if l.y0 >= start.y0 - 1]
        taken = []
        for l in rows:
            if (taken or not first) and stop(l, col):
                if taken:
                    segs.append((p, col, taken))
                return segs
            if max_gap and taken and l.y0 - taken[-1].y1 > max_gap and doc is not None and not any(
                    g.y0 < l.y0 and g.y1 > taken[-1].y1 and g.x1 > col[0] and g.x0 < col[1]
                    for g in lay.graphics(doc, p)):
                segs.append((p, col, taken))             # 그림 없는 큰 빈칸 = 문제 칸이 끝남
                return segs
            if first and not taken and l is not start and l.y0 < start.y0 - 1:
                continue
            taken.append(l)
        if taken:
            segs.append((p, col, taken))
        first = False
        if two and col[0] < 1:                          # 왼쪽 단이 끝남 → 같은 쪽 오른쪽 단
            col = (lay.sizes[p][0] / 2 - 6, lay.sizes[p][0])
            continue
        p += 1
        if p >= len(lay.lines):
            break
        col, two = _columns(lay, p, 0.0)
        if two:
            col = (0.0, lay.sizes[p][0] / 2 + 6)
    return segs


def _seg_rects(lay: Layout, doc, segs) -> list:
    out = []
    for p, col, rows in segs:
        y0 = min(l.y0 for l in rows) - 2
        y1 = max(l.y1 for l in rows) + 2
        x0 = min(l.x0 for l in rows)
        x1 = max(l.x1 for l in rows)
        # 문제 안의 그림(같은 단 · 같은 높이 범위)까지 넓힘
        for g in lay.graphics(doc, p):
            if g.y0 >= y0 - 1 and g.y1 <= y1 + 1 and g.x0 >= col[0] - 4 and g.x1 <= col[1] + 4:
                x0, x1 = min(x0, g.x0), max(x1, g.x1)
        W = lay.sizes[p][0]
        out.append(Clip(p, (max(0, x0 - 3), max(0, y0), min(W, x1 + 3), y1), lay.path))
    return out


def page_chapters(lay: Layout) -> list:
    """쪽마다 지금 몇 장인가 — 「Chapter 4」 · 큰 글씨 절 제목 「4.2 …」 로 셈. 모르면 0"""
    out, cur = [], 0
    for pl in lay.lines:
        for l in sorted(pl, key=lambda l: l.y0):
            m = re.match(r"^(?:Chapter|CHAPTER)\s+(\d+)|^제\s*(\d+)\s*장", l.text)
            if m:
                cur = int(m.group(1) or m.group(2))
                continue
            m = re.match(r"^(\d{1,2})\.\d{1,2}\s+[A-Za-z가-힣]", l.text)
            if m and l.size >= lay.body * 1.12:
                cur = int(m.group(1))
        out.append(cur)
    return out


def _problems_region(lay: Layout) -> list:
    """쪽마다 「연습문제 칸 안인가」 — 마지막 Problems 머리가 마지막 큰 절 제목보다 뒤면 참"""
    out = []
    state = False
    for pl in lay.lines:
        for l in sorted(pl, key=lambda l: l.y0):
            if PROBLEMS_HEAD.match(l.text) and len(l.text) < 60:
                state = True
            elif _is_heading(l, lay.body) and re.match(r"^\d+(\.\d+)*\s+\S", l.text) and not PROBLEMS_HEAD.match(l.text):
                state = False
            elif CHAPTER_HEAD.match(l.text):
                state = False
        out.append(state)
    return out


def find_problem(lay: Layout, doc, num: str, page_hint: int | None = None, region=None, chapters=None) -> Found | None:
    lab = _label(num)
    region = region if region is not None else _problems_region(lay)
    chapters = chapters if chapters is not None else page_chapters(lay)
    c, n = (int(x) for x in num.split("."))
    sib = {f"{c}.{n - 1}", f"{c}.{n + 1}"}
    best, best_s = None, -1e9
    pages = [page_hint - 1] if page_hint else range(len(lay.lines))
    for p in pages:
        if p < 0 or p >= len(lay.lines):
            continue
        for l in lay.lines[p]:
            if not lab.match(l.text):
                continue
            s = 0.0
            if _is_heading(l, lay.body):
                s -= 4                                  # 「3.2 키르히호프 법칙」 같은 절 제목
            if region[p]:
                s += 3
            near = [x for q in (p - 1, p, p + 1) if 0 <= q < len(lay.lines) for x in lay.lines[q]]
            for x in near:
                m = GENERIC.match(x.text)
                if m and f"{int(m.group(1))}.{int(m.group(2))}" in sib and abs(x.x0 - l.x0) < 15 \
                        and not _is_heading(x, lay.body):
                    s += 2
                    break
            rest = lab.sub("", l.text, count=1).strip(" .:)")
            if rest and len(rest) <= 3:
                s -= 3                                  # 「1.5 m」 같은 그림 속 치수
            if chapters[p] == c:
                s += 2                                  # 그 장 안의 쪽
            elif chapters[p]:
                s -= 1
            s += p / max(1, len(lay.lines)) * 0.1       # 같으면 뒤쪽(장 끝 연습문제)
            if s > best_s:
                best, best_s = l, s
    if best is None or (best_s < 0 and not page_hint):
        return None

    def left(p: int, col) -> float:
        xs = [l.x0 for l in lay.lines[p] if _in_col(l, col)]
        return min(xs) if xs else col[0]
    bcol, _ = _columns(lay, best.page, best.x0)
    indent = best.x0 - left(best.page, bcol)            # 단 글머리에서의 들여쓰기 — 다음 단의 번호도 같은 자리

    def stop(x: Line, col) -> bool:
        if x is best:
            return False
        m = GENERIC.match(x.text)
        if m and abs((x.x0 - left(x.page, col)) - indent) < 20 and not _is_heading(x, lay.body):
            return True
        return _is_heading(x, lay.body) or bool(PROBLEMS_HEAD.match(x.text))
    segs = _flow(lay, best, stop, max_segments=3, doc=doc, max_gap=lay.body * 5)
    clips = _seg_rects(lay, doc, segs)
    text = "\n".join(l.text for _, _, rows in segs for l in rows)
    m = re.match(rf"^{LEAD}(\d{{1,2}}{SEP}\d{{1,3}})", best.text)
    return Found(num, clips, text, re.sub(r"\s+", "", m.group(1)) if m else num)


# 문제 글 안의 참조 — 그림 · 표 · 예제 · 식
REF = re.compile(r"(?<![A-Za-z])(Figures?|Figs?\.?|FIGURES?|FIG\.?|Tables?|TABLES?|Tab\.|Examples?|EXAMPLES?|Ex\.|"
                 r"Equations?|Eqs?\.|Eqns?\.?|그림|표|예제|식)\s*\(?\s*(P?\d{1,2}\.\d{1,3}[a-z]?)\)?")
MORE = re.compile(r"\s*(?:,|and|&|및|와|과|or)\s*\(?\s*(P?\d{1,2}\.\d{1,3}[a-z]?)\)?")
KIND = [("fig", r"(?i)^fig|^그림"), ("table", r"(?i)^tab|^표"), ("example", r"(?i)^ex(?!a?m?p?l?e?q)|^example|^예제"),
        ("eq", r"(?i)^eq|^식")]
KIND_KO = {"fig": "그림", "table": "표", "example": "예제", "eq": "식", "probfig": "문제 그림"}


def find_refs(text: str) -> list[tuple]:
    """→ [(종류, 번호)] 처음 나온 순서. 「Figs. 3.4 and 3.5」 처럼 이어 쓴 번호도"""
    out = []
    for m in REF.finditer(text.replace("\n", " ")):
        word = m.group(1)
        kind = next(k for k, pat in KIND if re.match(pat, word)) if any(re.match(p, word) for _, p in KIND) else None
        if word.lower().startswith("eq"):
            kind = "eq"
        if not kind:
            continue
        nums = [m.group(2)]
        rest = text.replace("\n", " ")[m.end():]
        while True:
            mm = MORE.match(rest)
            if not mm:
                break
            nums.append(mm.group(1))
            rest = rest[mm.end():]
        for n in nums:
            if (kind, n) not in out:
                out.append((kind, n))
    return out


CAPTION = {
    "fig": r"(?:Figure|FIGURE|Fig\.?|FIG\.?|그림)",
    "table": r"(?:Table|TABLE|Tab\.|표)",
    "example": r"(?:Example|EXAMPLE|Ex\.|예제)",
}
EX_END = re.compile(r"^(?:Example|EXAMPLE|Practice Problem|PRACTICE PROBLEM|Exercise\s+\d|Exercises|EXERCISES|"
                    r"Problems|PROBLEMS|Summary|SUMMARY|예제|연습\s*문제)\b")


def _cluster(cands: list, seed, gap: float = 14.0):
    import pymupdf
    box = pymupdf.Rect(seed)
    grew = True
    while grew:
        grew = False
        for g in cands:
            if g in (box,) or box.contains(g):
                continue
            near = pymupdf.Rect(box.x0 - gap, box.y0 - gap, box.x1 + gap, box.y1 + gap)
            if near.intersects(g):
                box |= g
                grew = True
    return box


def find_ref(lay: Layout, doc, kind: str, num: str, avoid: list, page_hint: int | None = None) -> tuple | None:
    """→ (clips, 쪽 번호 1부터, 대략인가) 또는 None"""
    import pymupdf
    if kind == "eq":
        pat = re.compile(rf"\(\s*{re.escape(num)}\s*\)\s*$")
        for p, pl in enumerate(lay.lines):
            for l in pl:
                if pat.search(l.text) and l.x1 > lay.sizes[p][0] * 0.45:
                    blk = [x for x in pl if x.block == l.block]
                    r = pymupdf.Rect(min(x.x0 for x in blk), min(x.y0 for x in blk),
                                     max(x.x1 for x in blk), max(x.y1 for x in blk))
                    if r.height > lay.sizes[p][1] * 0.15:
                        r = pymupdf.Rect(r.x0, l.y0 - 14, r.x1, l.y1 + 14)
                    col, _ = _columns(lay, p, l.x0)
                    r = pymupdf.Rect(max(col[0], r.x0 - 4), r.y0 - 3, min(col[1], r.x1 + 4), r.y1 + 3)
                    if not _overlaps(p, r, avoid):
                        return [Clip(p, tuple(r), lay.path)], p + 1, False
        return None
    if kind == "probfig":
        # 문제의 그림 — 「Prob. 1–5」 · 「Probs. 5–19/20」(여러 문제가 같이 씀) · 「Figure P3.2」. 문제 근처 쪽에서만
        c, n = (int(x) for x in num.split("."))
        pat = re.compile(rf"^(?:Probs?\.\s*|(?:Figure|FIGURE|Fig\.?)\s*P\s*){c}{SEP}(\d{{1,3}})(?:\s*[/,]\s*(\d{{1,3}}))?(?:\s*[–-]\s*(\d{{1,3}}))?")
        near = range(max(0, page_hint - 2), min(len(lay.lines), page_hint + 2)) if page_hint else range(len(lay.lines))
        cands = []
        for p in near:
            for l in lay.lines[p]:
                m = pat.match(l.text)
                if m:
                    a = int(m.group(1))
                    b = int(m.group(2) or m.group(3) or a)
                    if a == n or (a <= n <= b and b - a <= 6):
                        cands.append(l)
        kind = "fig"
    else:
        head = re.compile(rf"^{CAPTION[kind]}\s*{re.escape(num)}(?![\d])(?!\.\d)")
        cands = [l for pl in lay.lines for l in pl if head.match(l.text)]
    if not cands:
        return None
    if kind == "example":
        cand = next((l for l in cands if l.bold or l.size > lay.body), cands[0])

        def stop(x: Line, col) -> bool:
            return x is not cand and (bool(EX_END.match(x.text)) or (_is_heading(x, lay.body)
                                       and bool(re.match(r"^\d+(\.\d+)*\s+\S", x.text))))
        segs = _flow(lay, cand, stop, max_segments=3)
        clips = _seg_rects(lay, doc, segs)
        if clips and all(_overlaps(c.page, pymupdf.Rect(c.rect), avoid) for c in clips):
            return None
        return clips, cand.page + 1, False
    best = None
    for cap in cands:
        p = cap.page
        W, H = lay.sizes[p]
        col, _ = _columns(lay, p, cap.x0)
        gs = [g for g in lay.graphics(doc, p) if g.x1 >= col[0] - 4 and g.x0 <= col[1] + 4]
        above = [g for g in gs if g.y1 <= cap.y0 + 3 and g.y1 >= cap.y0 - H * 0.6]
        below = [g for g in gs if g.y0 >= cap.y1 - 3 and g.y0 <= cap.y1 + H * 0.6]
        order = (above, below) if kind == "fig" else (below, above)
        box = None
        for side in order:
            if not side:
                continue
            seed = max(side, key=lambda g: g.y1) if side is above else min(side, key=lambda g: g.y0)
            b = _cluster(side, seed, gap=max(14.0, lay.body * 2.4) if kind == "table" else 14.0)   # 표의 가로줄 사이는 넓음
            if b.width * b.height >= 600:
                box = b
                break
        s = (3 if box else 0) + (1 if cap.size <= lay.body * 1.05 else 0) + (1 if len(cap.text) < 160 else 0)
        if best is None or s > best[0]:
            best = (s, cap, box)
    _, cap, box = best
    p = cap.page
    W, H = lay.sizes[p]
    col, _ = _columns(lay, p, cap.x0)
    capr = pymupdf.Rect(cap.x0, cap.y0, cap.x1, cap.y1)
    # 캡션 문단(같은 묶음의 바로 이은 줄)까지
    for x in sorted(lay.lines[p], key=lambda l: l.y0):
        if x.block == cap.block and x.y0 >= cap.y1 - 1 and x.y0 - capr.y1 < cap.size * 1.6:
            capr |= x.rect
    approx = box is None
    if box is None:
        rows = _body_lines(lay, p, col) or [cap]
        fx0, fx1 = min(l.x0 for l in rows), max(l.x1 for l in rows)   # 글이 놓인 너비(쪽 여백은 뺌)
        if kind == "fig":
            box = pymupdf.Rect(fx0, max(H * 0.06, cap.y0 - H * 0.35), fx1, cap.y0)
        else:
            box = pymupdf.Rect(fx0, cap.y1, fx1, min(H * 0.94, cap.y1 + H * 0.35))
    else:
        # 그림 안의 글자(R1 = 5 Ω 같은 이름표)가 선 밖으로 나간 만큼
        for x in lay.lines[p]:
            near = pymupdf.Rect(box.x0 - 6, box.y0 - 6, box.x1 + 6, box.y1 + 6)
            if near.intersects(x.rect) and x.rect.width < (col[1] - col[0]) * 0.9 and x is not cap:
                box |= x.rect
    r = (box | capr) + (-4, -4, 4, 4)
    r &= pymupdf.Rect(0, 0, W, H)
    if _overlaps(p, r, avoid):
        return None                                     # 이미 문제 조각 안에 있는 그림
    return [Clip(p, tuple(r), lay.path)], p + 1, approx


def _overlaps(p: int, r, avoid: list) -> bool:
    import pymupdf
    for c in avoid:
        if c.page != p:
            continue
        a = pymupdf.Rect(c.rect)
        inter = a & r
        if not inter.is_empty and inter.width * inter.height >= 0.6 * r.width * r.height:
            return True
    return False


# ── 문제지 PDF ─────────────────────────────────────────────────────────────
A4 = (595.0, 842.0)
M = 40.0
FONT_CSS = "* {font-family: sans-serif;}"


def _text(page, rect, html_body: str, size: float = 11, bold: bool = False):
    import pymupdf
    css = FONT_CSS + f" div {{font-size:{size}pt; {'font-weight:bold;' if bold else ''} line-height:1.35}}"
    page.insert_htmlbox(pymupdf.Rect(rect), f"<div>{html_body}</div>", css=css)


def _h(s: str) -> str:
    return _html.escape(str(s))


def build_sheet(out: Path, title: str, sub: str, problems: list, tb_doc) -> None:
    """problems: [{num, page, clips:[Clip], refs:[{kind,num,page,clips,approx}], missing:[str]} | {num, error}]"""
    import pymupdf
    doc = pymupdf.open()
    cw = A4[0] - 2 * M
    state = {"page": None, "y": 0.0}

    def new_page():
        state["page"] = doc.new_page(width=A4[0], height=A4[1])
        state["y"] = M
        n = len(doc)
        _text(state["page"], (M, A4[1] - 28, A4[0] - M, A4[1] - 12),
              f"<span style='color:#777'>{_h(title)} · {n}쪽</span>", 8)

    def need(h):
        if state["page"] is None or state["y"] + h > A4[1] - M:
            new_page()

    new_page()
    _text(state["page"], (M, M, A4[0] - M, M + 28), f"{_h(title)} — 문제지", 16, True)
    _text(state["page"], (M, M + 28, A4[0] - M, M + 48), f"<span style='color:#555'>{_h(sub)}</span>", 9.5)
    state["y"] = M + 56

    def size_of(clip: Clip, scale: float):
        x0, y0, x1, y1 = clip.rect
        return (x1 - x0) * scale, (y1 - y0) * scale

    def put(clip: Clip, x: float, y: float, scale: float):
        w, h = size_of(clip, scale)
        state["page"].show_pdf_page(pymupdf.Rect(x, y, x + w, y + h), _doc(tb_doc, clip), clip.page, clip=pymupdf.Rect(clip.rect))
        state["page"].draw_rect(pymupdf.Rect(x - 2, y - 2, x + w + 2, y + h + 2), color=(0.82, 0.82, 0.82), width=0.5)
        return h

    for pr in problems:
        def head(first_h: float):
            """제목만 쪽 끝에 홀로 남거나, 제목 뒤가 빈 채 다음 쪽으로 넘어가지 않게 첫 조각까지 들어갈 자리를 먼저 봄"""
            need(22 + min(first_h, A4[1] - 2 * M - 60))
            t = f"문제 {_h(pr.get('label') or pr['num'])}"
            if pr.get("page"):
                t += f" <span style='color:#666;font-weight:normal'>· 교과서 {pr['page']}쪽</span>"
            _text(state["page"], (M, state["y"], A4[0] - M, state["y"] + 20), t, 12.5, True)
            state["y"] += 22
        if pr.get("error"):
            head(40)
            _text(state["page"], (M, state["y"], A4[0] - M, state["y"] + 36),
                  f"<span style='color:#b00'>{_h(pr['error'])}</span>", 10)
            state["y"] += 40
            continue
        refs = [r for r in pr.get("refs", []) if r.get("clips")]
        pw = max((c.rect[2] - c.rect[0]) for c in pr["clips"])
        side = bool(refs) and pw * 0.85 <= cw * 0.6     # 두 단 교과서처럼 문제가 좁으면 그림을 옆에
        lw = cw * 0.6 if side else cw
        ps = min(1.25, lw / pw)
        ph = sum(size_of(c, ps)[1] + 8 for c in pr["clips"])
        if side:
            rx, rw = M + lw + 14, cw - lw - 14
            items = []
            for r in refs:
                for c in r["clips"]:
                    s = min(1.1, rw / (c.rect[2] - c.rect[0]))
                    items.append((r, c, s, size_of(c, s)[1]))
            rh = sum(h + 22 for *_, h in items)
            avail = A4[1] - 2 * M - 30
            k = min(1.0, avail / max(ph, rh, 1))
            head(max(ph, rh) * k)
            y0 = state["y"]
            y = y0
            for c in pr["clips"]:
                y += put(c, M, y, ps * k) + 8
            yr = y0
            for r, c, s, h in items:
                _text(state["page"], (rx, yr, A4[0] - M, yr + 16), _ref_label(r), 8.5, True)
                yr += 16
                yr += put(c, rx, yr, s * k) + 8
            state["y"] = max(y, yr) + 12
        else:
            c0 = pr["clips"][0]
            head(min(size_of(c0, ps)[1], A4[1] - 2 * M - 30) + 8)
            for c in pr["clips"]:
                s = ps
                h = size_of(c, s)[1]
                if h > A4[1] - 2 * M - 30:
                    s *= (A4[1] - 2 * M - 30) / h
                    h = size_of(c, s)[1]
                need(h + 8)
                state["y"] += put(c, M, state["y"], s) + 8
            for r in refs:
                for c in r["clips"]:
                    s = min(1.1, (cw * 0.8) / (c.rect[2] - c.rect[0]))
                    h = size_of(c, s)[1]
                    if h > A4[1] - 2 * M - 50:
                        s *= (A4[1] - 2 * M - 50) / h
                        h = size_of(c, s)[1]
                    need(h + 26)
                    _text(state["page"], (M + 16, state["y"], A4[0] - M, state["y"] + 16), _ref_label(r), 8.5, True)
                    state["y"] += 16
                    state["y"] += put(c, M + 16, state["y"], s) + 8
            state["y"] += 10
        miss = pr.get("missing") or []
        if miss:
            need(20)
            _text(state["page"], (M, state["y"], A4[0] - M, state["y"] + 30),
                  f"<span style='color:#b00'>교과서에서 못 찾음: {_h(', '.join(miss))}</span>", 9)
            state["y"] += 22
        state["y"] += 8
    tmp = out.with_suffix(".tmp.pdf")
    doc.save(str(tmp), garbage=3, deflate=True)
    os.replace(tmp, out)


def _ref_label(r: dict) -> str:
    t = (f"{KIND_KO.get(r['kind'], '')} · 교과서 {r['page']}쪽" if r["kind"] == "probfig"
         else f"{KIND_KO.get(r['kind'], '')} {_h(r['num'])} · 교과서 {r['page']}쪽")
    if r.get("approx"):
        t += " <span style='font-weight:normal;color:#a60'>(그림 테두리를 못 찾아 넉넉히 자름)</span>"
    return t


# ── 해설지 PDF ─────────────────────────────────────────────────────────────
ALLOWED = {"h2", "h3", "h4", "p", "ul", "ol", "li", "b", "strong", "i", "em", "sub", "sup", "br", "table", "thead",
           "tbody", "tr", "th", "td", "pre", "code", "div", "span", "section", "hr", "blockquote"}
SOL_CSS = FONT_CSS + """
body {font-size:10.5pt; line-height:1.5}
h1 {font-size:17pt; margin:0 0 4pt 0}
.sub {color:#555; font-size:9pt; margin-bottom:12pt}
h2 {font-size:13pt; margin:14pt 0 6pt 0; border-bottom:1px solid #bbb}
h3 {font-size:11pt; margin:8pt 0 4pt 0}
p {margin:3pt 0 5pt 0}
.ans {border:1px solid #333; padding:4pt 6pt; margin:6pt 0; font-weight:bold}
.src {color:#666; font-size:8.5pt}
.eq {margin:4pt 0 4pt 18pt}
table {border-collapse:collapse} td, th {border:1px solid #999; padding:2pt 5pt}
.prob {margin:4pt 0 6pt 0}
.warn {color:#a00}
"""


def clean_html(s: str) -> str:
    """Claude 가 쓴 해설 조각에서 정해 둔 태그만 남김(그림 · 스크립트 · 바깥 주소 금지)"""
    s = re.sub(r"(?is)<(script|style|iframe|object)[^>]*>.*?</\1>", "", s)

    def tag(m):
        close, name, attrs = m.group(1), m.group(2).lower(), m.group(3) or ""
        if name not in ALLOWED:
            return ""
        keep = ""
        mm = re.search(r'class\s*=\s*"([\w\s-]{1,40})"', attrs)
        if mm and not close:
            keep = f' class="{mm.group(1)}"'
        mm = re.search(r'data-num\s*=\s*"([\w.]{1,12})"', attrs)
        if mm and not close:
            keep += f' data-num="{mm.group(1)}"'
        return f"<{close}{name}{keep}>"
    return re.sub(r"<(/?)([A-Za-z][A-Za-z0-9]*)([^>]*)>", tag, s)


def split_sections(sol_html: str) -> dict:
    """<section data-num="3.2"> … </section> → {'3.2': 안쪽 html}"""
    out = {}
    for m in re.finditer(r'(?is)<section[^>]*data-num="([\d.]+)"[^>]*>(.*?)</section>', sol_html):
        out[m.group(1)] = m.group(2)
    return out


def build_solution(out: Path, title: str, sub: str, sol_html: str, problems: list | None, tb_doc, img_dir: Path) -> None:
    """번호 모드: 문제마다 문제지와 같은 조각(그림) → 해설. 아니면 Claude 가 쓴 해설 그대로"""
    import pymupdf
    img_dir.mkdir(parents=True, exist_ok=True)
    body = [f"<h1>{_h(title)} — 해설지</h1><div class='sub'>{_h(sub)}</div>"]
    if problems:
        secs = split_sections(sol_html)
        for i, pr in enumerate(problems):
            body.append(f"<h2>문제 {_h(pr.get('label') or pr['num'])}</h2>")
            for j, c in enumerate(pr.get("clips") or []):
                name = f"p{i}-{j}.png"
                pix = _doc(tb_doc, c)[c.page].get_pixmap(clip=pymupdf.Rect(c.rect), dpi=170)
                pix.save(str(img_dir / name))
                w = min(500, (c.rect[2] - c.rect[0]) * 1.0)
                body.append(f"<div class='prob'><img src='{name}' width='{int(w)}'/></div>")
            for r in pr.get("refs") or []:
                for j, c in enumerate(r.get("clips") or []):
                    name = f"p{i}-r{len(body)}-{j}.png"
                    _doc(tb_doc, c)[c.page].get_pixmap(clip=pymupdf.Rect(c.rect), dpi=150).save(str(img_dir / name))
                    w = min(380, (c.rect[2] - c.rect[0]) * 0.85)
                    body.append(f"<div class='src'>{_ref_label(r)}</div><div class='prob'><img src='{name}' width='{int(w)}'/></div>")
            sec = secs.get(pr["num"])
            body.append(sec if sec else "<p class='warn'>이 문제의 해설이 비어 있어요. 「해설지 다시 만들기」를 눌러 주세요.</p>")
        rest = re.sub(r'(?is)<section[^>]*data-num="[\d.]+"[^>]*>.*?</section>', "", sol_html).strip()
        if re.sub(r"<[^>]+>", "", rest).strip():
            body.append("<h2>덧붙임</h2>" + rest)
    else:
        body.append(sol_html)
    html = "<html><body>" + "\n".join(body) + "</body></html>"
    story = pymupdf.Story(html, user_css=SOL_CSS, archive=pymupdf.Archive(str(img_dir)))
    tmp = out.with_suffix(".tmp.pdf")
    w = pymupdf.DocumentWriter(str(tmp))
    mb = pymupdf.Rect(0, 0, *A4)
    where = mb + (M, M, -M, -M)
    more, n = 1, 0
    while more:
        dev = w.begin_page(mb)
        more, _ = story.place(where)
        story.draw(dev)
        w.end_page()
        n += 1
        if n > 400:
            break                                       # 끝나지 않는 배치(깨진 html) 막기
    w.close()
    os.replace(tmp, out)


def text_pdf(text: str, title: str) -> bytes:
    """글로 넣은 과제(「3.2, 3.5, 4.1」)를 보기 좋은 한 쪽 PDF 로"""
    import pymupdf
    doc = pymupdf.open()
    pg = doc.new_page(width=A4[0], height=A4[1])
    _text(pg, (M, M, A4[0] - M, M + 30), _h(title), 16, True)
    _text(pg, (M, M + 40, A4[0] - M, A4[1] - M), _h(text).replace("\n", "<br>"), 12)
    return doc.tobytes()


# ── Claude 로 해설 쓰기 ─────────────────────────────────────────────────────
def solve_prompt(course: str, title: str, mode: str, sheet: str | None, assignment_pdf: str,
                 problems: list | None, lectures: list, textbooks: list) -> str:
    lec = "\n".join(f"- 「{n}」 PDF {p} · 쪽별 본문(JSON 배열) {t}" for n, p, t in lectures) or "- (없음)"
    tbs = "\n".join(f"- 「{n}」 PDF {p} · 쪽별 본문(JSON 배열) {t}" for n, p, t in textbooks) or "- (없음)"
    if mode == "numbers" and problems:
        lst = []
        for pr in problems:
            if pr.get("error"):
                lst.append(f"- 문제 {pr['num']}: 교과서에서 못 찾음. 교과서 본문 JSON 을 Grep 해서 직접 찾아 풀 것. 못 찾으면 그렇다고 쓸 것.")
                continue
            refs = ", ".join(f"{KIND_KO[r['kind']]} {r['num']}(교과서 {r['page']}쪽)" for r in pr.get("refs", []) if r.get("clips"))
            lst.append(f"- 문제 {pr['num']} (교과서 {pr['page']}쪽){' · 참조: ' + refs if refs else ''}\n  뽑은 글: "
                       + pr.get("text", "").replace("\n", " ")[:1500])
        what = (f"문제지 PDF: {sheet}\n(문제지에 교과서에서 잘라 온 문제 본문과 문제가 가리키는 그림 · 표 · 예제가 들어 있다. "
                f"뽑은 글은 수식이 깨져 있을 수 있으니 **문제지 PDF 를 Read 로 직접 보고** 숫자 · 그림을 확인할 것.)\n"
                "문제 목록:\n" + "\n".join(lst))
        fmt = ("문제마다 정확히 하나씩, 문제 목록 순서대로 <section data-num=\"3.2\"> … </section> 로 감싼다"
               "(data-num 은 위 번호 그대로). section 안에 문제 번호 제목은 쓰지 않는다(따로 붙임).")
    else:
        what = f"과제 PDF: {assignment_pdf}\n(과제 안의 문제를 모두 푼다. 과제가 교과서 문제 번호를 가리키면 교과서에서 찾아 푼다.)"
        fmt = "문제마다 <h2>문제 …</h2> 로 시작한다."
    return f"""너는 대학 과목 「{course}」의 조교다. 과제 「{title}」의 해설지를 쓴다. 결과는 PDF 로 만들어져 학생이 공부에 쓴다.

{what}

같은 과목의 수업자료(풀이 방법 · 기호 · 표기는 수업자료를 먼저 따른다):
{lec}

교과서:
{tbs}

할 일:
1. 문제를 읽고, 수업자료와 교과서에서 관련 개념 · 공식 · 예제를 찾는다(본문 JSON 을 Grep 으로 찾고, 필요한 쪽은 PDF 를 Read 로 본다).
2. 문제마다 풀이를 쓴다: 쓰는 개념/공식 → 단계별 풀이(숫자 대입 · 단위 포함) → 최종 답 → 검산(가능하면).
3. 풀이에 쓴 근거를 짧게 단다: 예) <p class="src">근거: 수업자료 「04 MLE」 7쪽, 교과서 식 (3.12)</p>
4. 확실하지 않은 것(문제 글이 흐림, 그림의 값이 안 보임 등)은 지어내지 말고 무엇을 가정했는지 분명히 쓴다.

쓰는 법:
- 한국어로, 사람이 쓴 해설처럼 자연스럽게. 번역투 · "~하십시오" 금지. 전문 용어는 처음에 한 번 영어를 괄호로.
- 결과는 HTML 조각 하나를 <solution> 과 </solution> 사이에 넣어서 낸다. 그 밖의 말은 쓰지 않는다.
- 쓸 수 있는 태그: h3 p ul ol li b i sub sup br table tr th td pre div span section. 그림 · 링크 · 스크립트 · style 금지.
- 수식은 LaTeX 를 쓰지 말고 유니코드 글자로: 예) V<sub>R</sub> = I·R = 2 A × 5 Ω = 10 V, √(x² + y²), ∑, ∫, ≈, ≤, θ, μ, σ².
  분수는 (a + b) / (c − d) 처럼 괄호로. 혼자 줄에 놓을 식은 <p class="eq"> … </p>.
- 최종 답은 <p class="ans">답: …</p>.
- {fmt}
"""


def run_claude(prompt: str, cwd: str, add_dirs: list, timeout_s: int = 1800, model: str = "", on_tick=None):
    """claude -p 로 해설을 받음 → html. 읽기 도구만 허락(쓰기 · 명령 · 인터넷 금지)"""
    exe = shutil.which("claude") or os.path.expanduser("~/.local/bin/claude")
    cmd = [exe, "-p", prompt, "--output-format", "json", "--permission-mode", "bypassPermissions",
           "--allowedTools", "Read,Grep,Glob", "--disallowedTools", "Bash,Write,Edit,NotebookEdit,WebFetch,WebSearch,Agent"]
    for d in add_dirs:
        cmd += ["--add-dir", d]
    if model:
        cmd += ["--model", model]
    p = subprocess.Popen(cmd, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    t0 = time.time()
    while True:
        try:
            out, err = p.communicate(timeout=2)
            break
        except subprocess.TimeoutExpired:
            if on_tick:
                on_tick(time.time() - t0)
            if time.time() - t0 > timeout_s:
                p.kill()
                p.communicate()
                raise RuntimeError(f"해설 쓰기가 {timeout_s // 60}분을 넘어서 멈췄어요.")
    try:
        r = json.loads(out.strip().splitlines()[-1])
    except (ValueError, IndexError):
        log.error("과제: claude 응답을 못 읽음 rc=%s err=%s", p.returncode, (err or "")[-400:])
        raise RuntimeError("Claude 가 응답하지 않았어요. 로그인이나 사용량 한도를 확인해 주세요.")
    if r.get("is_error"):
        from .coursechat import korean_error
        raise RuntimeError(korean_error(str(r.get("result", ""))))
    text = r.get("result") or ""
    m = re.search(r"(?is)<solution>(.*)</solution>", text)
    if not m:
        log.error("과제: 해설에 <solution> 이 없음: %s", text[:400])
        raise RuntimeError("Claude 가 해설을 정해진 모양으로 내지 않았어요. 다시 만들어 주세요.")
    return clean_html(m.group(1))
