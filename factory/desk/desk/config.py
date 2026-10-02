"""설정 — ~/.config/desk/config.toml 이 있으면 그 값이 기본값을 덮습니다(config.example.toml 참고)."""
from __future__ import annotations

import copy
import json
import os
import re
import tomllib

DEFAULTS: dict = {
    "owner": "",                    # 인사할 때 부를 이름 (비우면 이름 없이)
    "audio": {"device": "", "samplerate": 16000,   # device: 이름 하나 또는 목록(꽂힌 첫 장치, desk/devices.py)
              "side_device": ""},           # 박수 · 끼어들기를 들을 마이크(비우면 device 와 같음)
    "wake": {
        "claps": 2,                 # 켜는 박수 수
        "night_claps": 3,           # 밤에는 더 (침대 앞 책상 — 기침 · 뒤척임에 켜지지 않게)
        "night": ["01:00", "07:00"],
        "clap_when_awake": "none",  # none · sleep (깨어 있을 때 박수로 끄기)
    },
    "clap": {},                     # ClapConfig 값 덮어쓰기 (rise_db · min_centroid_hz · max_gap_s …)
    "listen": {"end_silence_s": 0.8, "min_utt_s": 0.4, "max_utt_s": 20.0,
               "hold_silence_s": 2.0,       # 받아쓴 끝이 조사 · 접속사("…이랑", "그리고")면 이만큼까지 더 기다림. 0 = 끔
               "vad_level": -1,             # webrtcvad 0~3, -1 = 끔(말소리 대역 크기로만 — desk/vad.py)
               "energy_db": 6.0},           # 말소리 대역이 바닥 소음보다 이만큼 커야 말
    "stt": {"model": "mlx-community/whisper-large-v3-turbo", "language": "ko",
            "prompt": "앱 공장, 상황판, 브리핑, 클로드, 깃허브, 맥 미니, 아이폰, 안드로이드, 워크플로, 출시"},
    "idle_minutes": 15,             # 이만큼 아무 말 없으면 화면 끄고 박수 대기로
    "camera_off": ["~/.local/bin/hand-mouse off"],   # 화면을 끌 때(어느 길로든) 돌려 카메라를 끄는 명령들
    "camera_on": ["~/.local/bin/hand-mouse on --no-sweep"],   # 화면이 켜질 때(어느 길로든) 돌려 카메라를 켜는 명령들 — 끄기의 짝
    "tts": {"voice": "Yuna", "rate": 190, "device": "",   # device: 소리 낼 장치 이름(비우면 기본 출력)
            "engine": "say",                                # say · supertonic(신경망, desk/tts.py — 못 쓰면 say)
            "style": "F1", "model": "supertonic-3", "speed": 1.05, "steps": 5,
            "pitch": 0,                                     # 반음(-6~6). Supertonic 에 없어 틀기 직전에 바꿈
            "volume": 1.0},                                 # 이 목소리만의 크기(0~1.5, say 는 1 까지) — 시스템 음량과 별개
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
    "bargein": {                    # 말하는 도중 멈춤 말을 들으면 말하기 · 남은 답 · 밀린 말을 버림 (desk/bargein.py)
        "enabled": True,
        "stop_words": ["잠깐", "멈춰", "그만", "스톱", "스탑"],
        "margin_db": 3.0,           # 민감도: 스피커 되먹임보다 이만큼 커야 받아써 봄. 못 알아들으면 낮추고(0), 헛멈추면 올림(6)
        "min_s": 0.12,              # 0.3초 안에 그 큰 소리가 이만큼 있어야
        "grace_s": 0.3,             # 말 시작 뒤 이 시간은 되먹임 크기만 배움
    },
    "dictate": {                    # 주먹 쥐고 말하기 — Claude 앱이 맨 앞이면 받아쓴 글을 그 입력창에 (desk/dictate.py)
        "enabled": True,
        "fist_state": "~/lab/hand-mouse/.run/fist.json",   # hand-mouse 가 적는 주먹 상태
        "apps": ["com.anthropic.claudefordesktop"],        # 이 앱이 맨 앞일 때만
        "fist_ratio": 0.5,          # 말한 시간의 이만큼 이상 주먹이면
        "fist_enough_s": 1.0,       # 또는 이만큼 이상 주먹이면 (긴 말)
        "join_s": 60.0,             # 이 안에 이어 넣으면 앞에 띄어쓰기
        "erase_window_s": 120.0,    # 왼손 지우기 다이얼이 먹는 시간 (넣거나 지운 뒤, 그 뒤엔 커서가 옮겨졌을 수 있어 안 함)
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


def _toml(v) -> str:
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(round(v, 3)) if isinstance(v, float) else str(v)
    return json.dumps(str(v), ensure_ascii=False)       # 보통 글자는 TOML 기본 문자열과 같음


_KEY = re.compile(r'^(\s*)([A-Za-z_][\w-]*)(\s*=\s*)("(?:[^"\\]|\\.)*"|[^#]*?)(\s*#.*)?$')


def save_table(table: str, values: dict, path: str | None = None) -> None:
    """[table] 의 값만 고쳐 씁니다 — 다른 줄 · 주석은 그대로(설정 창 저장). 없는 키는 표 끝에, 없는 표는 파일 끝에."""
    path = path or PATH
    lines = []
    if os.path.exists(path):
        with open(path, encoding="utf-8") as f:
            lines = f.read().splitlines()
    start = next((i for i, ln in enumerate(lines) if re.match(rf"^\s*\[{re.escape(table)}\]\s*(#.*)?$", ln)), None)
    if start is None:
        lines += ([""] if lines and lines[-1].strip() else []) + [f"[{table}]"]
        start = len(lines) - 1
    end = next((i for i in range(start + 1, len(lines)) if re.match(r"^\s*\[", lines[i])), len(lines))
    left = dict(values)
    for i in range(start + 1, end):
        m = _KEY.match(lines[i])
        if m and m.group(2) in left:
            new = f"{m.group(1)}{m.group(2)}{m.group(3)}{_toml(left.pop(m.group(2)))}"
            if m.group(5):                                # 주석은 원래 자리(열)에 맞춰 남김
                col = len(lines[i]) - len(m.group(5).lstrip())
                new = new + " " * max(1, col - len(new)) + m.group(5).lstrip()
            lines[i] = new
    ins = end
    while ins > start + 1 and not lines[ins - 1].strip():
        ins -= 1
    lines[ins:ins] = [f"{k} = {_toml(v)}" for k, v in left.items()]
    out = "\n".join(lines) + "\n"
    tomllib.loads(out)                                    # 깨진 파일은 쓰지 않음
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(out)
    os.replace(tmp, path)
