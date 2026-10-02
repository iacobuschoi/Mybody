"""받아쓰기 — 맥 미니 안에서(mlx-whisper), 인터넷으로 소리를 보내지 않습니다.

Whisper 는 조용한 소리 · 잡음에서 **없는 말을 지어냅니다**. 한국어에서 가장 흔한 것이 유튜브 자막에서 배운
"시청해 주셔서 감사합니다" · "구독과 좋아요" 입니다. 상시 듣기에서 이게 명령으로 가면 곤란하니 거릅니다:
  · 구간별 no_speech_prob 가 높거나 avg_logprob 가 낮으면 버림
  · 알려진 환각 문구면 버림
  · 같은 글자가 계속 반복되면 버림
"""
from __future__ import annotations

import re
import threading

HALLUCINATIONS = [
    "시청해주셔서감사합니다", "시청해주셔서고맙습니다", "시청감사합니다", "구독과좋아요", "좋아요와구독",
    "구독좋아요", "알림설정", "다음영상에서만나요", "다음시간에만나요", "영상편집", "자막제공", "자막by",
    "mbc뉴스", "kbs뉴스", "sbs뉴스", "ytn", "이덕영입니다", "김수현입니다", "이시각세계",
    "thankyou", "thanksforwatching", "subtitlesby", "you",
]
_ONLY_THANKS = {"감사합니다", "고맙습니다", "네", "아", "음", "어", "응"}


def _norm(s: str) -> str:
    return re.sub(r"[\s\.,!?~·…'\"“”‘’\-]+", "", s).lower()


def _prompt_echo(n: str, prompt: str) -> bool:
    """받아쓴 글이 힌트 문구(initial_prompt)를 그대로 읊은 것 — 소리가 거의 없으면 Whisper 가 힌트를 되풀이함
    (10월 2일 15:40 "룰이, 아이폰, 안드로이드, 워크플로, 출시")"""
    p = _norm(prompt)
    if not p or len(n) < 4:
        return False
    words = [_norm(w) for w in prompt.split(",") if len(_norm(w)) >= 2 and _norm(w) in n]
    return (len(n) >= 8 and n in p) or (len(words) >= 3 and sum(map(len, words)) >= 0.6 * len(n))   # 힌트 낱말 셋 이상으로만 된 글


def clean_transcript(text: str, segments: list[dict] | None = None,
                     no_speech_max: float = 0.6, logprob_min: float = -1.0, direct: bool = False,
                     prompt: str = "") -> str:
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
    if _prompt_echo(n, prompt):
        return ""
    if re.search(r"(.{1,4})\1{4,}", n):          # "아아아아아" · "감사감사감사감사감사"
        return ""
    if re.search(r"(.{5,40})\1{3,}", n):         # "아프지 않게, …" ×25 · 박수 소리에 힌트 문구("앱 공장, 브리핑, …")를 되풀이
        return ""
    return text


# MLX(Metal)는 스레드 둘이 동시에 GPU 를 쓰면 "GPU Timeout" 이 나고, 그 뒤로는 그 프로세스의 모든 받아쓰기가 실패합니다
# (10월 2일 14:20 — 주먹 말하기 받아쓰기와 끼어들기 작은 모델 데우기가 겹침). 그래서 모델 호출은 모두 여기서 한 줄로.
_gpu = threading.Lock()


class WhisperSTT:
    def __init__(self, model: str = "mlx-community/whisper-large-v3-turbo", language: str = "ko",
                 prompt: str = "", fast_model: str = "", probe_model: str = ""):
        self.model, self.language, self.prompt = model, language, prompt
        self.fast_model = fast_model             # 끼어들기 첫 받아쓰기용 작은 모델(desk/bargein.py). 비우면 늘 model
        self.probe_model = probe_model           # 끼어들기 두 번째(작은 모델이 못 찾았을 때). 비우면 model —
                                                 # model 을 느린 large-v3 로 바꿔도 끼어들기는 turbo(1.3초)로
        self._mlx = None
        self._models: dict[str, object] = {}
        self.last_raw = ""                       # 거르기 전 받아쓴 글 — 걸러 버린 말을 데몬이 로그에 남기게     # 불러 둔 모델 — 큰 · 작은 모델을 번갈아 써도 다시 읽지 않게

    def _load(self):
        if self._mlx is None:
            import mlx_whisper  # 맥(애플 실리콘)에서만
            self._mlx = mlx_whisper
        return self._mlx

    def _use(self, name: str) -> None:
        """mlx_whisper 는 모델을 하나만 들고 있어, 다른 모델을 부르면 매번 디스크에서 다시 읽고 허깅페이스에 물어봄
        (10월 2일 15:08 — 끼어들기가 작은 · 큰 모델을 번갈아 불러 한 번에 1~2초씩, "받아쓰기 바쁨" 으로 "잠깐" 을 건너뜀).
        그래서 둘 다 여기 들고 있다가 부르기 전에 바꿔 끼움. _gpu 안에서 부름."""
        import sys
        import mlx.core as mx
        holder = sys.modules["mlx_whisper.transcribe"].ModelHolder
        if holder.model_path == name and holder.model is not None:
            return
        m = self._models.get(name)
        if m is None:
            from mlx_whisper.load_models import load_model
            m = self._models[name] = load_model(name, dtype=mx.float16)
        holder.model, holder.model_path = m, name

    def warmup(self) -> None:
        import numpy as np
        self.transcribe(np.zeros(16000, dtype=np.float32))
        if self.fast_model:
            self.hear(np.zeros(16000, dtype=np.float32), fast=True)
        if self.probe_model and self.probe_model != self.model:
            self.hear(np.zeros(16000, dtype=np.float32))

    def transcribe(self, audio, direct: bool = False) -> str:
        mw = self._load()
        # temperature 를 0.0 하나만 주면 Whisper 의 되풀이 · 낮은 확신 다시 받아쓰기가 꺼져 "아, 아, 아 …" 에 빠진 채 끝남
        # (10월 2일 주먹 말 여러 번이 3.5초 걸려 빈 말). 막힐 때만 0.2 · 0.4 로 다시 — 어려운 시험 묶음에서 시간은 그대로
        kw = dict(path_or_hf_repo=self.model, language=self.language, temperature=(0.0, 0.2, 0.4),
                  condition_on_previous_text=False, verbose=None)
        if self.prompt:
            kw["initial_prompt"] = self.prompt   # 자주 쓰는 낱말(앱 공장 · 상황판 · 클로드 …)을 알려 줘 인식을 돕습니다
        with _gpu:
            self._use(self.model)
            try:
                r = mw.transcribe(audio, **kw)
            except TypeError:                         # 판에 따라 받는 인자가 다름
                r = mw.transcribe(audio, path_or_hf_repo=self.model, language=self.language)
        self.last_raw = r.get("text", "") or ""
        return clean_transcript(self.last_raw, r.get("segments"), direct=direct, prompt=self.prompt)

    def hear(self, audio, fast: bool = False) -> str:
        """멈춤 말 찾기용(desk/bargein.py) — 힌트 문구 없이, 거르지 않은 글.
        짧은 낱말 하나를 스피커 소리 위에서 찾을 때는 힌트가 그쪽 낱말로 끌고 가고, 환각 거르기가 진짜 말도 버립니다
        (방 녹음 시험: 힌트 · 거르기 있으면 24번 중 16번, 없으면 22번 찾음). 멈춤 말만 보므로 환각은 상관없음.
        sample_len=40: 2초 소리엔 넉넉하고, 되먹임에 "다음은 다음은 …" 처럼 되풀이에 빠져도 224 토큰(4초)까지 붙잡지 않게
        (10월 2일 15:21 — 그동안 뒤의 소리가 "받아쓰기 바쁨" 으로 건너뜀).
        fast: 작은 모델로 — 2초 소리에 0.3초(큰 모델 1.4~1.8초). 대신 짧은 "그만" 을 더 놓쳐서(24번 중 20번) 큰 모델이 뒤를 받침."""
        model = self.fast_model if fast and self.fast_model else (self.probe_model or self.model)
        mw = self._load()
        with _gpu:
            self._use(model)
            r = mw.transcribe(audio, path_or_hf_repo=model, language=self.language, temperature=0.0,
                              condition_on_previous_text=False, verbose=None, sample_len=40)
        return r.get("text", "")
