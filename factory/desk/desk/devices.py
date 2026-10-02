"""소리 장치 고르기 — 설정의 이름 목록 중 지금 꽂혀 있는 첫 장치.

  [audio] device = ["Jabra", "Brio"]               듣기(박수도 같은 마이크)
  [tts]   device = ["Jabra", "Mac mini 스피커"]    말하기

스피커폰(Jabra)을 빼면 다음 이름(Brio · 맥 미니 스피커)으로, 다시 꽂으면 Jabra 로 돌아갑니다. 하나만 적은 글자("Brio")도
예전처럼 됩니다. 아무것도 없으면 "" = 시스템 기본.

꽂혀 있는지는 system_profiler 로 봅니다(0.1초 안팎) — sounddevice(PortAudio)는 켤 때 본 장치 목록을 계속 쓰므로 새로 꽂은
장치를 모르고, 뺀 장치도 목록에 남습니다. 그래서 고른 장치가 바뀌면 refresh() 로 PortAudio 를 다시 띄운 뒤 엽니다.
"""
from __future__ import annotations

import json
import subprocess
import threading

# PortAudio 를 다시 띄우는 동안(refresh) 말하기가 스피커를 열지 않게 — 말하기는 여는 동안만 잡습니다.
pa_lock = threading.Lock()


def names(v) -> list[str]:
    """설정 값(글자 하나 또는 목록) → 이름 목록."""
    if isinstance(v, str):
        return [v] if v.strip() else []
    return [str(s) for s in (v or []) if str(s).strip()]


def present(kind: str) -> list[str] | None:
    """지금 꽂혀 있는 장치 이름(kind = "input" · "output"). 알 수 없으면 None."""
    try:
        out = subprocess.run(["system_profiler", "SPAudioDataType", "-json"], capture_output=True, text=True,
                             timeout=5).stdout
        items = json.loads(out)["SPAudioDataType"][0]["_items"]
    except Exception:  # noqa: BLE001
        return None
    return [d.get("_name", "") for d in items if d.get(f"coreaudio_device_{kind}")]


def pick(want, kind: str, have: list[str] | None = None) -> str:
    """want 중 꽂혀 있는 첫 장치의 실제 이름. 없으면 "". 목록을 알 수 없으면 첫 이름을 그대로(예전처럼)."""
    want = names(want)
    if not want:
        return ""
    have = present(kind) if have is None else have
    if have is None:
        return want[0]
    for w in want:
        for h in have:
            if w.lower() in h.lower():
                return h
    return ""


def refresh() -> None:
    """PortAudio 장치 목록 새로 읽기 — 열린 스트림이 없을 때만 부릅니다."""
    import sounddevice as sd
    with pa_lock:
        sd._terminate()
        sd._initialize()
