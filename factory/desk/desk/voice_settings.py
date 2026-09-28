"""상태판의 「목소리」 설정 창 — 고를 수 있는 것 · 받은 값 다듬기.

저장하면 ~/.config/desk/config.toml 의 [tts] 에 기록하고(config.save_table), 데몬이 다시 켜지 않고 바로 씁니다
(Desk.tts_save). 「들어 보기」는 저장 없이 이번 한 번만 그 설정으로 말합니다(Desk.tts_test).
"""
from __future__ import annotations

from . import mac

STYLES = [f"{g}{i}" for g in "FM" for i in range(1, 6)]          # Supertonic: F1~F5(여) · M1~M5(남)
KEYS = ("engine", "style", "voice", "speed", "pitch", "volume", "rate")
RANGES = {"speed": (0.7, 1.6), "pitch": (-6, 6), "volume": (0.0, 1.5), "rate": (120, 320)}
SAMPLE = "안녕하세요, 책상 비서예요. 오늘 오후 9시에 확인할 일이 3건 있어요."


def _clamp(k: str, v) -> float:
    lo, hi = RANGES[k]
    return min(hi, max(lo, float(v)))


def clean(d: dict, voices: list[str] | None = None) -> dict:
    """화면에서 온 값 → [tts] 에 쓸 값. 모르는 목소리는 ValueError(화면에 그대로 보임), 숫자는 범위 안으로."""
    if not isinstance(d, dict):
        raise ValueError("설정 형식이 아니에요")
    out: dict = {}
    eng = d.get("engine")
    if eng not in ("supertonic", "say"):
        raise ValueError(f"모르는 엔진: {eng}")
    out["engine"] = eng
    if "style" in d:
        if d["style"] not in STYLES:
            raise ValueError(f"모르는 Supertonic 목소리: {d['style']}")
        out["style"] = d["style"]
    if "voice" in d:
        known = voices if voices is not None else mac.korean_voices()
        if d["voice"] not in known:
            raise ValueError(f"이 맥에 없는 say 음성: {d['voice']}")
        out["voice"] = d["voice"]
    for k in ("speed", "volume"):
        if k in d:
            out[k] = round(_clamp(k, d[k]), 2)
    for k in ("pitch", "rate"):
        if k in d:
            out[k] = int(round(_clamp(k, d[k])))
    return out


def view(tts: dict, engine_now: str) -> dict:
    """설정 창을 열 때 보낼 것 — 지금 값 · 고를 수 있는 것 · 범위."""
    voices = mac.korean_voices()
    now = {k: tts[k] for k in KEYS if k in tts}
    if now.get("voice") and now["voice"] not in voices:
        voices = [now["voice"]] + voices                            # 설정에 적힌 이름이 목록 표기와 달라도 고른 채로
    return {"now": now, "engine_now": engine_now, "styles": STYLES, "voices": voices, "ranges": RANGES}
