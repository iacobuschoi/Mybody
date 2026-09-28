"""비서 모델 고르기 — 상태판 위쪽 토글 · 음성("빠른 모드") · `deskctl model <이름>`.

고르면 ~/.config/desk/config.toml 의 [brain] model 에 기록하고(config.save_table), 데몬이 다시 켜지 않고
다음 말부터 그 모델로 `claude -p --model …` 을 부릅니다(Desk.model_set). 오늘 대화는 그대로 이어 갑니다(--resume).
"""
from __future__ import annotations

import re

# (config 에 적는 값, 화면 이름, 말로 읽을 이름, 한마디)
MODELS = [
    ("claude-opus-5-5", "Opus 5.5", "오퍼스", "정확"),
    ("claude-sonnet-5", "Sonnet 5", "소넷", "빠름"),
    ("claude-haiku-4-5-20251001", "Haiku 4.5", "하이쿠", "가장 빠름"),
]
DEFAULT = MODELS[0][0]           # [brain] model 이 비어 있을 때 Claude Code 기본 — 지금은 Opus 5.5

# 짧은 이름 · 옛 값도 받음 ("sonnet" · "opus" …)
ALIASES = {"opus": MODELS[0][0], "sonnet": MODELS[1][0], "haiku": MODELS[2][0]}

# 음성 — 받아쓰기(router.normalize 뒤: 공백 없음 · 소문자). 위에서부터 먼저 맞는 것
SPEECH = [
    (MODELS[2][0], r"(제일빠른|가장빠른|아주빠른|초고속|최고속|하이쿠|haiku)"),
    (MODELS[1][0], r"(빠른모드|빠르게답|빨리답|빠른답|빠른모델|소넷|쏘넷|sonnet)"),
    (MODELS[0][0], r"(정확한모드|정밀모드|똑똑한모드|기본모드|느려도|오퍼스|오푸스|opus)"),
]
_SPEECH = [(m, re.compile(p)) for m, p in SPEECH]


def resolve(text: str) -> str | None:
    """model id · 짧은 이름 · 화면 이름 · 말 → model id. 모르면 None"""
    t = (text or "").strip()
    if not t:
        return None
    for mid, label, _, _ in MODELS:
        if t in (mid, label):
            return mid
    if t.lower() in ALIASES:
        return ALIASES[t.lower()]
    n = re.sub(r"[\s\.,!?~·…'\"“”‘’\-]+", "", t).lower()
    for mid, rx in _SPEECH:
        if rx.search(n):
            return mid
    return None


def current(model: str) -> str:
    """config 값 → 지금 쓰는 model id (빈 값 · 짧은 이름도)"""
    return resolve(model) or model or DEFAULT


def label(model: str) -> str:
    mid = current(model)
    return next((lb for m, lb, _, _ in MODELS if m == mid), mid)


def spoken(model: str) -> str:
    """스피커로 읽을 이름 — "소넷 5" """
    mid = current(model)
    return next((f"{sp} {lb.split()[-1]}" for m, lb, sp, _ in MODELS if m == mid), "그 모델")


def options() -> list[dict]:
    """상태판 토글에 그릴 것"""
    return [{"id": m, "label": lb, "note": note} for m, lb, _, note in MODELS]
