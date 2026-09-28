"""신경망 목소리 — Supertonic(Supertone 이 공개한 온디바이스 TTS, ONNX). 맥 안에서만 돌고 키 · 결제 없음.

`say` 의 Yuna 보다 훨씬 사람 같지만 모델이 떠 있어야 합니다(처음 한 번 380MB 안팎 내려받기, 뜨는 데 1초 미만).
모델이 뜨기 전이나 못 쓰면(패키지 없음 · 장치 오류) 알아서 `say` 로 말합니다 — 목소리가 끊기는 일은 없게.
문장 단위로 만들면서 앞 문장을 틀어 첫소리가 빨리 나옵니다(M1 에서 짧은 문장 0.3~0.6초).

음높이(pitch, 반음)는 Supertonic 에 없어서 틀기 직전에 바꿉니다: 느리게 만든 소리를 그만큼 줄여 틀면 빠르기는 그대로,
음만 올라갑니다(shift_pitch). 목소리 크기(volume)는 이 목소리에만 곱하는 값 — 시스템 음량과 따로입니다.
"""
from __future__ import annotations

import queue
import re
import threading
import time

from . import mac


def sentences(text: str) -> list[str]:
    parts = re.split(r"(?<=[.!?。…])\s+", text.strip())
    return [p.strip() for p in parts if p.strip()]


def shift_pitch(wav, semitones: float):
    """반음만큼 음을 올리고(+) 내림(-). 길이도 1/p 로 바뀌므로 합성할 때 speed 를 p 로 나눠 두면 빠르기는 그대로."""
    import numpy as np
    if not semitones:
        return wav
    p = 2 ** (semitones / 12)
    n = max(1, int(len(wav) / p))
    return np.interp(np.arange(n) * p, np.arange(len(wav)), wav).astype(np.float32)


def output_device(name: str):
    """이름 일부("Mac mini 스피커") → sounddevice 출력 장치 번호. 없으면 None(시스템 기본)."""
    if not name:
        return None
    import sounddevice as sd
    for i, d in enumerate(sd.query_devices()):
        if d["max_output_channels"] > 0 and name.lower() in d["name"].lower():
            return i
    return None


class NeuralVoice(mac.Voice):
    """mac.Voice 와 같은 모양(say · busy · stop · last_text) — 데몬은 차이를 모릅니다."""

    def __init__(self, style: str = "F1", model: str = "supertonic-3", speed: float = 1.05, steps: int = 5,
                 voice: str = "Yuna", rate: int = 190, tail_s: float = 0.5, device: str = "",
                 pitch: float = 0, volume: float = 1.0, use: str = "supertonic"):
        super().__init__(voice, rate, tail_s, device, volume)   # 모델이 뜨기 전 · 실패했을 때 쓸 say 목소리
        self.style_name, self.model_name, self.speed, self.steps, self.pitch = style, model, speed, steps, pitch
        self.use = use                  # "say" 면 모델은 떠 있어도 say 로(설정 창에서 예비 음성을 고른 경우)
        self._tts = None
        self._styles: dict = {}
        self._gen = 0                   # 말 하나마다 +1 — stop() 도 올려서 하던 말을 멈추게
        self._speaking = False
        self.ready = threading.Event()
        self.error = ""
        threading.Thread(target=self._load, daemon=True).start()

    def _load(self) -> None:
        try:
            from supertonic import TTS
            tts = TTS(model=self.model_name)
            style = tts.get_voice_style(self.style_name)
            tts.synthesize("준비", voice_style=style, lang="ko", total_steps=self.steps)   # 첫 합성만 느려서 미리
            self._styles[self.style_name] = style
            self._tts = tts
        except Exception as e:
            self.error = f"{type(e).__name__}: {e}"
            print(f"[말하기] Supertonic 을 못 써서 say 로 말합니다 — {self.error}", flush=True)
        self.ready.set()

    def _style_of(self, name: str):
        if name not in self._styles:
            self._styles[name] = self._tts.get_voice_style(name)
        return self._styles[name]

    @property
    def engine(self) -> str:
        return f"Supertonic {self.style_name}" if self._tts is not None and self.use != "say" else f"say {self.voice}"

    def configure(self, c: dict) -> None:
        super().configure(c)
        self.use = c.get("engine", self.use)
        self.style_name = c.get("style", self.style_name)
        self.speed = float(c.get("speed", self.speed))
        self.pitch = float(c.get("pitch", self.pitch))

    def busy(self) -> bool:
        return self._speaking or super().busy()

    def say(self, text: str, block: bool = False, opts: dict | None = None) -> None:
        """opts: 이번 말에만 쓸 설정(설정 창의 「들어 보기」) — engine · style · speed · pitch · volume · voice · rate."""
        text = (text or "").strip()
        if not text:
            return
        o = opts or {}
        if self._tts is None or o.get("engine", self.use) == "say":
            return super().say(text, block, opts)
        try:
            p = {"style": self._style_of(o.get("style", self.style_name)), "speed": float(o.get("speed", self.speed)),
                 "pitch": float(o.get("pitch", self.pitch)), "volume": float(o.get("volume", self.volume))}
        except Exception as e:
            print(f"[말하기] 목소리 {o.get('style')} 를 못 씀: {e}", flush=True)
            return super().say(text, block, opts)
        self.stop()
        self.last_text = text
        with self._lock:
            self._gen += 1
            gen, self._speaking = self._gen, True
        t = threading.Thread(target=self._speak, args=(text, gen, p), daemon=True)
        t.start()
        if block:
            t.join()

    def stop(self) -> None:
        with self._lock:
            self._gen += 1
            self._speaking = False
        super().stop()

    def _speak(self, text: str, gen: int, p: dict) -> None:
        import numpy as np
        import sounddevice as sd
        alive = lambda: self._gen == gen   # noqa: E731
        sr = self._tts.sample_rate
        parts: queue.Queue = queue.Queue()
        stretch = 2 ** (p["pitch"] / 12)            # 음을 올릴 만큼 느리게 만들어 두고 shift_pitch 가 도로 줄임

        def make() -> None:
            for s in sentences(text):
                if not alive():
                    break
                try:
                    wav, _ = self._tts.synthesize(s, voice_style=p["style"], lang="ko",
                                                  total_steps=self.steps, speed=p["speed"] / stretch)
                except Exception as e:
                    print(f"[말하기] 합성 실패: {e}", flush=True)
                    break
                wav = shift_pitch(np.asarray(wav, dtype=np.float32).reshape(-1), p["pitch"])
                parts.put(np.clip(wav * p["volume"], -1, 1).astype(np.float32))
            parts.put(None)

        threading.Thread(target=make, daemon=True).start()
        played = False
        try:
            with sd.OutputStream(samplerate=sr, channels=1, dtype="float32", device=output_device(self.device)) as out:
                gap = np.zeros(int(sr * 0.15), dtype=np.float32)
                while alive() and (wav := parts.get()) is not None:
                    for i in range(0, len(wav), sr // 10):    # 0.1초씩 — stop() 에 바로 멈추게
                        if not alive():
                            break
                        out.write(wav[i:i + sr // 10])
                        played = True
                    if alive():
                        out.write(gap)
                if not alive():
                    out.abort()
        except Exception as e:
            print(f"[말하기] 스피커 오류, say 로 말합니다: {e}", flush=True)
            if alive() and not played:
                super(NeuralVoice, self).say(text)
                return
        with self._lock:
            if self._gen == gen:
                self._speaking = False
                self._until = time.time() + self.tail_s
