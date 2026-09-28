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
    "listen": {"end_silence_s": 0.8, "min_utt_s": 0.4, "max_utt_s": 20.0,
               "vad_level": -1,             # webrtcvad 0~3, -1 = 끔(말소리 대역 크기로만 — desk/vad.py)
               "energy_db": 6.0},           # 말소리 대역이 바닥 소음보다 이만큼 커야 말
    "stt": {"model": "mlx-community/whisper-large-v3-turbo", "language": "ko",
            "prompt": "앱 공장, 상황판, 브리핑, 클로드, 깃허브, 맥 미니, 아이폰, 안드로이드, 워크플로, 출시"},
    "idle_minutes": 15,             # 이만큼 아무 말 없으면 화면 끄고 박수 대기로
    "tts": {"voice": "Yuna", "rate": 190, "device": "",   # device: 소리 낼 장치 이름(비우면 기본 출력)
            "engine": "say",                                # say · supertonic(신경망, desk/tts.py — 못 쓰면 say)
            "style": "F1", "model": "supertonic-3", "speed": 1.05, "steps": 5},
    "brain": {"workdir": "~/lab/desk-assistant", "model": "", "timeout_s": 180},
    "briefing": {"city": "Seoul", "repo": "", "ship_repo": ""},   # repo = 주인/app-factory
    "dashboard": {"port": 7070, "open_cmd": ""},
    "face": {                       # 박수로 깨울 때 얼굴 인증 (desk/face.py). 등록(deskctl enroll) 전에는 박수만으로 깨어남
        "enabled": True,
        "camera": "Brio",           # 카메라 이름 일부 (아이폰 연속성 카메라를 피해서). 비우면 camera_index
        "camera_index": 0,
        "name": "",                 # 환영 인사에 부를 이름 (비우면 owner)
        "prompt": "얼굴 인증해 주세요.",
        "welcome": "{name}님, 환영합니다.",
        "fail": "얼굴을 확인하지 못했어요.",
        "on_error": "stay",         # 카메라 · 인식이 안 될 때: stay(안 켬) · wake(얼굴 없이 켬)
        "error_say": "카메라를 쓸 수 없어서 얼굴을 확인하지 못했어요.",
        "threshold": 0.40,          # 닮음 문턱(코사인). 주인인데 자꾸 실패하면 0.36, 남이 통과하면 0.45
        "need": 2,                  # 문턱을 넘은 장이 이만큼
        "look_s": 4.0,              # 이 시간 동안 찍어 봄
        "min_face_px": 40,          # 이보다 작은 얼굴은 안 봄
        "timeout_s": 15,
    },
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
