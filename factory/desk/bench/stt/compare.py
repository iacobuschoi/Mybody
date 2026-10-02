"""pc_<이름>.json(percall.py · deskpath.py · e2e.py)들을 같은 잣대로: 글자 오류 · 버림 · 낱말 맞춤 · 걸린 시간(평균 · p90 · 최대)
python compare.py new_F new_F8 e2e_F   (SET=녹음 폴더)"""
import json, os, re, sys
import numpy as np
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
from desk.stt import clean_transcript
from configs import NEW2
D = os.environ.get("SET") or os.path.dirname(os.path.abspath(__file__))
KW = ["책상", "탭", "마우스", "포인터", "권한", "승인", "잘 먹네", "핸드마우스", "조이스틱", "더블클릭", "터미널", "사파리",
      "배포", "다이얼", "앱스토어", "마이바디", "깃허브", "상황판", "클로드", "맥 미니", "아이폰", "안드로이드", "브리핑",
      "워크플로", "카카오톡", "키보드", "리모트 컨트롤", "작업 공간", "녹화", "심사"]


def norm(s): return re.sub(r"[\s\.,!?~·…'\"“”‘’\-]+", "", s).lower()


def cer(ref, hyp):
    r, h = norm(ref), norm(hyp)
    d = list(range(len(h) + 1))
    for i in range(1, len(r) + 1):
        p, d[0] = d[0], i
        for j in range(1, len(h) + 1):
            p, d[j] = d[j], min(d[j] + 1, d[j - 1] + 1, p + (r[i - 1] != h[j - 1]))
    return d[len(h)] / max(1, len(r))


def kept(o): return o["kept"] if "kept" in o else clean_transcript(o["raw"], o["segs"], prompt=NEW2)


for name in sys.argv[1:]:
    rows = json.load(open(f"{D}/pc_{name}.json"))
    print(name)
    for grp, cond in (("어려움", lambda o: o["vol"] in (10, 5)), ("깨끗", lambda o: o["vol"] == 1.0),
                      ("잡음", lambda o: o["vol"] == "noise")):
        rs = [o for o in rows if cond(o)]
        if not rs:
            continue
        ts = sorted(o["t"] for o in rs)
        took = f"평균 {np.mean(ts):.2f}초 p90 {ts[int(.9 * len(ts))]:.2f} 최대 {ts[-1]:.2f}"
        if grp == "잡음":
            print(f"   {grp}: 남은 글 {sum(1 for o in rs if kept(o))}/{len(rs)} · {took}")
            continue
        kh = kt = 0
        for o in rs:
            for w in KW:
                if norm(w) in norm(o["ref"]):
                    kt += 1
                    kh += norm(w) in norm(kept(o))
        print(f"   {grp}: 오류 {np.mean([cer(o['ref'], kept(o)) for o in rs]) * 100:.1f}% · 버림 {sum(1 for o in rs if not kept(o))}"
              f" · 낱말 {kh}/{kt} · {took}")
