"""받아쓴 소리 남기기 — 받아쓰기 정확도를 주인의 실제 목소리로 재고 고치려고(10월 2일, "음성 인식 개선해 놔").

받아쓰기에 넘긴 소리마다 ~/.local/share/desk/heard/<날짜>/<시각>-<종류>.wav 와 같은 이름의 .json
(받아쓴 글 · 거르기 전 글 · 길이 · 크기)을 남깁니다. 주인의 목소리를 저장하는 일이라 기본은 꺼짐 — 주인이
config.toml [stt] keep_audio_days = 7 처럼 켤 때만. 이 맥 밖으로는 보내지 않고, keep_days 지난 날짜 폴더는 지웁니다.
"""
from __future__ import annotations

import datetime as dt
import json
import os
import shutil
import threading
import wave

import numpy as np

ROOT = os.path.expanduser("~/.local/share/desk/heard")


def _write(path: str, audio: np.ndarray, sr: int, info: dict) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    pcm = (np.clip(audio, -1, 1) * 32767).astype("<i2")
    with wave.open(path + ".wav", "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(pcm.tobytes())
    with open(path + ".json", "w") as f:
        json.dump(info, f, ensure_ascii=False)


def prune(keep_days: int, root: str = ROOT, today: dt.date | None = None) -> None:
    today = today or dt.date.today()
    if not os.path.isdir(root):
        return
    for name in os.listdir(root):
        try:
            day = dt.date.fromisoformat(name)
        except ValueError:
            continue
        if (today - day).days >= keep_days:
            shutil.rmtree(os.path.join(root, name), ignore_errors=True)


class Keeper:
    def __init__(self, keep_days: int = 0, root: str = ROOT):
        self.keep_days, self.root = int(keep_days), root
        self._pruned: dt.date | None = None

    def save(self, audio: np.ndarray, sr: int, kind: str, **info) -> None:
        """받아쓰기 스레드를 붙잡지 않게 따로 씀. keep_days 0 이면 안 남김"""
        if self.keep_days <= 0 or audio is None or not len(audio):
            return
        now = dt.datetime.now()
        a = np.asarray(audio, dtype=np.float32).copy()
        path = os.path.join(self.root, now.date().isoformat(), now.strftime("%H%M%S.%f")[:-3] + "-" + kind)
        meta = {"time": now.isoformat(timespec="milliseconds"), "kind": kind, "seconds": round(len(a) / sr, 2),
                "peak": round(float(np.abs(a).max()), 4), "rms": round(float(np.sqrt(np.mean(a ** 2))), 5), **info}

        def run() -> None:
            try:
                if self._pruned != now.date():
                    self._pruned = now.date()
                    prune(self.keep_days, self.root, now.date())
                _write(path, a, sr, meta)
            except OSError:
                pass

        threading.Thread(target=run, daemon=True).start()
