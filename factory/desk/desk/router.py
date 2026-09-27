"""받아쓴 말 → 무엇을 할지.

짧고 정해진 말은 여기서 바로 처리합니다(0.1초 · 사용량 0). 나머지는 전부 Claude 로 갑니다.
"화면 꺼" 는 즉시, "화면 꺼지기 전에 브리핑해 줘" 처럼 긴 문장은 Claude 가 판단합니다 —
그래서 로컬 명령은 **짧은 말에만** 맞춥니다(LOCAL_MAX_CHARS).
"""
from __future__ import annotations

import re
from dataclasses import dataclass

LOCAL_MAX_CHARS = 14   # 공백 · 문장부호를 뺀 글자 수

# 순서가 중요합니다 — "그만 들어" 는 mute, "그만" 은 stop.
PATTERNS: list[tuple[str, str]] = [
    ("unmute", r"^(다시들어|다시들어줘|일어나|듣기시작|다시시작|들어줘)"),
    ("mute",   r"(조용히|듣지마|그만들어|음소거|귀닫아|잠깐듣지마)"),
    ("sleep",  r"(잘게|자자|잘자|화면꺼|모니터꺼|꺼줘$|끝내자|퇴근|오늘은끝|이제쉴게|쉬자)"),
    ("stop",   r"^(멈춰|그만|취소|스톱|스탑|stop|됐어|그만해|닥쳐)"),
    ("brief",  r"(브리핑|상황알려|상황어때|현재상태|지금상태|요약해줘|뭐있어)"),
    ("louder", r"(소리키워|크게말해|볼륨올려|소리올려|크게해)"),
    ("softer", r"(소리줄여|작게말해|볼륨내려|소리내려|작게해)"),
    ("repeat", r"(다시말해|뭐라고|다시한번|한번더말해)"),
    ("time",   r"^(지금)?몇시(야|니|예요|에요)?$"),
]
_COMPILED = [(k, re.compile(p)) for k, p in PATTERNS]


@dataclass
class Action:
    kind: str          # unmute · mute · sleep · stop · brief · louder · softer · repeat · time · claude · ignore
    text: str = ""


def normalize(text: str) -> str:
    return re.sub(r"[\s\.,!?~·…'\"“”‘’\-]+", "", text).lower()


def route(text: str, muted: bool = False) -> Action:
    t = (text or "").strip()
    n = normalize(t)
    if not n:
        return Action("ignore")
    if muted:
        # 조용히 모드에서는 "다시 들어" 류만 받습니다. 나머지 말은 아무 데도 가지 않습니다.
        if len(n) <= LOCAL_MAX_CHARS and _COMPILED[0][1].search(n):
            return Action("unmute", t)
        return Action("ignore", t)
    if len(n) <= LOCAL_MAX_CHARS:
        for kind, rx in _COMPILED:
            if rx.search(n):
                return Action(kind, t)
    if len(n) < 2:
        return Action("ignore", t)
    return Action("claude", t)
