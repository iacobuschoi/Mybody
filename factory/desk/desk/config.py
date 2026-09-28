"""설정 — ~/.config/desk/config.toml 이 있으면 그 값이 기본값을 덮습니다(config.example.toml 참고)."""
from __future__ import annotations

import copy
import os
import tomllib

DEFAULTS: dict = {
    "owner": "",                    # 인사할 때 부를 이름 (비우면 이름 없이)
    "audio": {"device": "", "samplerate": 16000},
    "wake": {
        "claps": 2,                 # 켜는 박수 수
        "night_claps": 3,           # 밤에는 더 (침대 앞 책상 — 기침 · 뒤척임에 켜지지 않게)
        "night": ["01:00", "07:00"],
        "clap_when_awake": "none",  # none · sleep (깨어 있을 때 박수로 끄기)
    },
    "clap": {},                     # ClapConfig 값 덮어쓰기 (rise_db · min_centroid_hz · max_gap_s …)
    "listen": {"end_silence_s": 0.8, "min_utt_s": 0.4, "max_utt_s": 20.0, "vad_level": 2},
    "stt": {"model": "mlx-community/whisper-large-v3-turbo", "language": "ko",
            "prompt": "앱 공장, 상황판, 브리핑, 클로드, 깃허브, 맥 미니, 아이폰, 안드로이드, 워크플로, 출시"},
    "idle_minutes": 15,             # 이만큼 아무 말 없으면 화면 끄고 박수 대기로
    "tts": {"voice": "Yuna", "rate": 190, "device": ""},   # device: say -a 장치 이름(비우면 기본 출력)
    "brain": {"workdir": "~/lab/desk-assistant", "model": "", "timeout_s": 180},
    "briefing": {"city": "Seoul", "repo": "", "ship_repo": ""},   # repo = 주인/app-factory
    "dashboard": {"port": 7070, "open_cmd": ""},
}

PATH = os.path.expanduser(os.environ.get("DESK_CONFIG", "~/.config/desk/config.toml"))


def _merge(a: dict, b: dict) -> dict:
    out = copy.deepcopy(a)
    for k, v in b.items():
        out[k] = _merge(out[k], v) if isinstance(v, dict) and isinstance(out.get(k), dict) else v
    return out


def load(path: str = PATH) -> dict:
    if os.path.exists(path):
        with open(path, "rb") as f:
            return _merge(DEFAULTS, tomllib.load(f))
    return copy.deepcopy(DEFAULTS)
