"""받아쓰기 — 맥 미니 안에서(mlx-whisper), 인터넷으로 소리를 보내지 않습니다.

Whisper 는 조용한 소리 · 잡음에서 **없는 말을 지어냅니다**. 한국어에서 가장 흔한 것이 유튜브 자막에서 배운
"시청해 주셔서 감사합니다" · "구독과 좋아요" 입니다. 상시 듣기에서 이게 명령으로 가면 곤란하니 거릅니다:
  · 구간별 no_speech_prob 가 높거나 avg_logprob 가 낮으면 버림
  · 알려진 환각 문구면 버림
  · 같은 글자가 계속 반복되면 버림
"""
from __future__ import annotations

import re

HALLUCINATIONS = [
    "시청해주셔서감사합니다", "시청해주셔서고맙습니다", "시청감사합니다", "구독과좋아요", "좋아요와구독",
    "구독좋아요", "알림설정", "다음영상에서만나요", "다음시간에만나요", "영상편집", "자막제공", "자막by",
    "mbc뉴스", "kbs뉴스", "sbs뉴스", "ytn", "이덕영입니다", "김수현입니다", "이시각세계",
    "thankyou", "thanksforwatching", "subtitlesby", "you",
]
_ONLY_THANKS = {"감사합니다", "고맙습니다", "네", "아", "음", "어", "응"}


def _norm(s: str) -> str:
    return re.sub(r"[\s\.,!?~·…'\"“”‘’\-]+", "", s).lower()


def clean_transcript(text: str, segments: list[dict] | None = None,
                     no_speech_max: float = 0.6, logprob_min: float = -1.0, direct: bool = False) -> str:
    """Whisper 결과를 명령으로 써도 되는 글로. 못 쓰면 ""
    direct: 주먹 쥐고 한 말 — "응" · "네" 같은 짧은 대답도 진짜 대답이라 남김(확인 받기에 씀)"""
    if segments:
        kept = [s.get("text", "") for s in segments
                if s.get("no_speech_prob", 0.0) <= no_speech_max and s.get("avg_logprob", 0.0) >= logprob_min]
        text = "".join(kept)
    text = (text or "").strip()
    n = _norm(text)
    if len(n) < (1 if direct else 2):
        return ""
    if n in _ONLY_THANKS and not (direct and n != "감사합니다"):
        return ""
    if any(h in n for h in HALLUCINATIONS):
        return ""
    if re.search(r"(.{1,4})\1{4,}", n):          # "아아아아아" · "감사감사감사감사감사"
        return ""
    if re.search(r"(.{5,40})\1{3,}", n):         # "아프지 않게, …" ×25 · 박수 소리에 힌트 문구("앱 공장, 브리핑, …")를 되풀이
        return ""
    return text


class WhisperSTT:
    def __init__(self, model: str = "mlx-community/whisper-large-v3-turbo", language: str = "ko",
                 prompt: str = ""):
        self.model, self.language, self.prompt = model, language, prompt
        self._mlx = None

    def _load(self):
        if self._mlx is None:
            import mlx_whisper  # 맥(애플 실리콘)에서만
            self._mlx = mlx_whisper
        return self._mlx

    def warmup(self) -> None:
        import numpy as np
        self.transcribe(np.zeros(16000, dtype=np.float32))

    def transcribe(self, audio, direct: bool = False) -> str:
        mw = self._load()
        kw = dict(path_or_hf_repo=self.model, language=self.language, temperature=0.0,
                  condition_on_previous_text=False, verbose=None)
        if self.prompt:
            kw["initial_prompt"] = self.prompt   # 자주 쓰는 낱말(앱 공장 · 상황판 · 클로드 …)을 알려 줘 인식을 돕습니다
        try:
            r = mw.transcribe(audio, **kw)
        except TypeError:                         # 판에 따라 받는 인자가 다름
            r = mw.transcribe(audio, path_or_hf_repo=self.model, language=self.language)
        return clean_transcript(r.get("text", ""), r.get("segments"), direct=direct)

    def hear(self, audio) -> str:
        """멈춤 말 찾기용(desk/bargein.py) — 힌트 문구 없이, 거르지 않은 글.
        짧은 낱말 하나를 스피커 소리 위에서 찾을 때는 힌트가 그쪽 낱말로 끌고 가고, 환각 거르기가 진짜 말도 버립니다
        (방 녹음 시험: 힌트 · 거르기 있으면 24번 중 16번, 없으면 22번 찾음). 멈춤 말만 보므로 환각은 상관없음."""
        r = self._load().transcribe(audio, path_or_hf_repo=self.model, language=self.language, temperature=0.0,
                                    condition_on_previous_text=False, verbose=None)
        return r.get("text", "")
