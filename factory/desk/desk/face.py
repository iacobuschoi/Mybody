"""얼굴 인증 — 박수로 깨울 때 웹캠으로 주인인지 봅니다. 전부 이 맥 안에서만 돕니다(사진 · 특징값을 밖으로 안 보냄).

    박수 두 번 → "얼굴 인증해 주세요" → 웹캠 몇 장 → 주인이면 "○○님, 환영합니다" · 화면 · 브리핑
                                                   → 아니면 짧게 알리고 다시 박수 대기

방법: OpenCV 의 YuNet(얼굴 찾기, 0.2MB) + SFace(얼굴 특징 128개 숫자, 37MB). 등록할 때 찍은 특징들과
코사인 유사도를 재서 threshold 이상인 장이 need 장 넘으면 주인. 사진은 저장하지 않고 특징값만 남깁니다.

  등록:  deskctl enroll                 (데몬이 찍음 — 카메라 권한이 deskd 하나로 끝남)
         python -m desk face enroll     (터미널에서 — 터미널에도 카메라 권한이 필요)
  확인:  deskctl face  ·  python -m desk face verify
  지우기: python -m desk face forget

카메라 잡기는 따로 뜬 파이썬(자식 프로세스)이 합니다. 카메라 · OpenCV 가 멈추거나 죽어도 데몬은 그대로고,
timeout_s 가 지나면 끊습니다. 등록 데이터: ~/.local/share/desk/face/ (설치 스크립트가 지우지 않는 곳).

웹캠 손동작 마우스(~/lab/hand-mouse)와 같이 켜져 있어도 됩니다 — macOS 는 한 카메라를 여러 프로그램이 같이
열 수 있습니다. 다만 해상도를 바꿔 열면 저쪽 화면 비율까지 바뀌므로, hand-mouse 가 돌 때는 저쪽과 같은
640×480 으로 엽니다. hand-mouse 를 끄고 켜지는 않습니다(데몬이 다시 띄우면 권한 주인이 deskd 로 바뀜).
"""
from __future__ import annotations

import contextlib
import fcntl
import hashlib
import json
import os
import subprocess
import sys
import time
import urllib.request

import numpy as np

DIR = os.path.expanduser(os.environ.get("DESK_FACE_DIR", "~/.local/share/desk/face"))
OWNER = os.path.join(DIR, "owner.npz")
_ZOO = "https://github.com/opencv/opencv_zoo/raw/main/models"
MODELS = {   # 이름: (주소, sha256) — 받은 파일이 다르면 쓰지 않습니다
    "detector": ("face_detection_yunet_2023mar.onnx", f"{_ZOO}/face_detection_yunet/face_detection_yunet_2023mar.onnx",
                 "8f2383e4dd3cfbb4553ea8718107fc0423210dc964f9f4280604804ed2552fa4"),
    "recognizer": ("face_recognition_sface_2021dec.onnx", f"{_ZOO}/face_recognition_sface/face_recognition_sface_2021dec.onnx",
                   "0ba9fbfa01b5270c96627c4ef784da859931e02f04419c829e83484087c34e79"),
}
HAND_MOUSE = "hand_mouse.py"


def _mkdir(path: str) -> None:
    os.makedirs(path, exist_ok=True)
    for p in (DIR, path):                     # 얼굴 특징은 주인만 읽게
        os.chmod(p, 0o700)


def model_path(key: str) -> str:
    return os.path.join(DIR, "models", MODELS[key][0])


def have_models() -> bool:
    return all(os.path.exists(model_path(k)) for k in MODELS)


def enrolled() -> bool:
    return os.path.exists(OWNER)


def _sha(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()


def fetch_models() -> str:
    """모델 두 개를 받아 둡니다(처음 한 번, 약 37MB). 이미 있으면 그대로."""
    _mkdir(os.path.join(DIR, "models"))
    for key, (name, url, sha) in MODELS.items():
        path = model_path(key)
        if os.path.exists(path):
            continue
        tmp = path + ".part"
        with urllib.request.urlopen(url, timeout=120) as r, open(tmp, "wb") as f:
            while b := r.read(1 << 20):
                f.write(b)
        if _sha(tmp) != sha:
            os.remove(tmp)
            raise RuntimeError(f"{name} 내용이 예상과 다름 — 받지 않음")
        os.replace(tmp, path)
    return os.path.join(DIR, "models")


# ── 카메라 ──────────────────────────────────────────────────────────────
def hand_mouse_running() -> bool:
    try:
        return subprocess.run(["pgrep", "-f", HAND_MOUSE], capture_output=True, timeout=3).returncode == 0
    except Exception:
        return False


def camera_index(name: str, fallback: int = 0) -> int:
    """이름 일부("Brio")로 카메라 번호 찾기. 아이폰 연속성 카메라가 끼면 번호가 바뀌어서 이름으로 고릅니다.
    OpenCV 가 쓰는 것과 같은 목록(AVCaptureDevice devicesWithMediaType)의 순서가 곧 번호입니다."""
    if not name:
        return fallback
    try:
        import AVFoundation as AV
        names = [str(d.localizedName()) for d in AV.AVCaptureDevice.devicesWithMediaType_(AV.AVMediaTypeVideo)]
    except Exception:
        return fallback
    for i, n in enumerate(names):
        if name.lower() in n.lower():
            return i
    raise RuntimeError(f"카메라 '{name}' 없음 (있는 것: {', '.join(names) or '없음'})")


@contextlib.contextmanager
def _lock():
    """등록과 확인이 동시에 카메라를 잡지 않게"""
    _mkdir(DIR)
    with open(os.path.join(DIR, ".lock"), "w") as f:
        try:
            fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            raise RuntimeError("다른 얼굴 확인이 카메라를 쓰는 중") from None
        yield


@contextlib.contextmanager
def camera(fc: dict):
    import cv2
    idx = camera_index(fc.get("camera", ""), int(fc.get("camera_index", 0)))
    shared = hand_mouse_running()
    w, h = (640, 480) if shared else (1280, 720)          # 침대 쪽 얼굴은 작아서 혼자일 땐 크게
    cap = cv2.VideoCapture(idx)
    try:
        if not cap.isOpened():
            raise RuntimeError("카메라를 못 엶 — 권한(설정 → 개인정보 보호 및 보안 → 카메라 → deskd) 또는 연결 확인"
                               + (" · hand-mouse 가 쓰는 중" if shared else ""))
        cap.set(cv2.CAP_PROP_FRAME_WIDTH, w)
        cap.set(cv2.CAP_PROP_FRAME_HEIGHT, h)
        yield cap
    finally:
        cap.release()


def frames(cap, seconds: float, warmup_s: float = 0.8, every_s: float = 0.15):
    """자동 노출이 자리 잡을 때까지(warmup_s) 버리고, 그다음 every_s 마다 한 장씩 seconds 동안"""
    t0 = time.time()
    last = 0.0
    bad = 0
    while time.time() - t0 < warmup_s + seconds:
        ok, f = cap.read()
        if not ok or f is None:
            bad += 1
            if bad > 30:
                raise RuntimeError("카메라에서 화면이 안 옴 — 권한 확인")
            time.sleep(0.05)
            continue
        now = time.time()
        if now - t0 < warmup_s or now - last < every_s:
            continue
        last = now
        yield f


# ── 얼굴 → 특징 ─────────────────────────────────────────────────────────
class Faces:
    def __init__(self, min_face_px: int = 40):
        import cv2
        if not have_models():
            raise RuntimeError("얼굴 모델 없음 — python -m desk face models")
        self.det = cv2.FaceDetectorYN.create(model_path("detector"), "", (320, 320), 0.8, 0.3, 50)
        self.rec = cv2.FaceRecognizerSF.create(model_path("recognizer"), "")
        self.min_face_px = min_face_px

    def embed(self, frame: np.ndarray) -> np.ndarray | None:
        """가장 큰 얼굴 하나의 특징(길이 1로 맞춘 128개). 얼굴이 없거나 너무 작으면 None."""
        h, w = frame.shape[:2]
        self.det.setInputSize((w, h))
        _, found = self.det.detect(frame)
        if found is None or not len(found):
            return None
        face = max(found, key=lambda f: f[2] * f[3])
        if min(face[2], face[3]) < self.min_face_px:
            return None
        v = self.rec.feature(self.rec.alignCrop(frame, face)).reshape(-1).astype(np.float32)
        return v / (np.linalg.norm(v) + 1e-9)


def score(owner: np.ndarray, v: np.ndarray) -> float:
    """등록된 특징들 중 가장 닮은 것과의 코사인 유사도"""
    return float(np.max(owner @ v))


def decide(scores: list[float], threshold: float, need: int) -> bool:
    return sum(s >= threshold for s in scores) >= need


def load_owner() -> np.ndarray:
    with np.load(OWNER) as z:
        return z["emb"].astype(np.float32)


# ── 명령 ────────────────────────────────────────────────────────────────
def enroll(fc: dict, seconds: float = 10.0, want: int = 15) -> dict:
    fetch_models()
    faces = Faces(int(fc.get("min_face_px", 40)))
    embs: list[np.ndarray] = []
    with _lock(), camera(fc) as cap:
        for f in frames(cap, seconds, every_s=0.3):
            v = faces.embed(f)
            if v is not None:
                embs.append(v)
                if len(embs) >= want:
                    break
    if len(embs) < 5:
        raise RuntimeError(f"얼굴이 {len(embs)}장만 잡힘 — 밝은 곳에서 카메라를 보고 다시")
    _mkdir(DIR)
    tmp = OWNER + ".tmp.npz"
    np.savez(tmp, emb=np.stack(embs), at=time.time())
    os.chmod(tmp, 0o600)
    os.replace(tmp, OWNER)
    return {"ok": True, "shots": len(embs)}


def verify(fc: dict) -> dict:
    if not enrolled():
        return {"ok": False, "error": "등록된 얼굴 없음"}
    owner = load_owner()
    faces = Faces(int(fc.get("min_face_px", 40)))
    thr, need = float(fc.get("threshold", 0.40)), int(fc.get("need", 2))
    scores: list[float] = []
    seen = 0
    with _lock(), camera(fc) as cap:
        for f in frames(cap, float(fc.get("look_s", 4.0))):
            seen += 1
            v = faces.embed(f)
            if v is None:
                continue
            scores.append(score(owner, v))
            if decide(scores, thr, need):
                break
    best = max(scores, default=0.0)
    return {"ok": decide(scores, thr, need), "best": round(best, 3), "faces": len(scores), "frames": seen}


def forget() -> dict:
    with contextlib.suppress(FileNotFoundError):
        os.remove(OWNER)
    return {"ok": True}


def status(fc: dict) -> dict:
    return {"enabled": bool(fc.get("enabled")), "models": have_models(), "enrolled": enrolled(),
            "hand_mouse": hand_mouse_running()}


def cli(argv: list[str]) -> None:
    """python -m desk face models|enroll|verify|forget|status — 마지막 줄은 JSON(데몬이 읽음)"""
    from . import config
    fc = config.load()["face"]
    cmd = argv[0] if argv else "status"
    fn = {"models": lambda: {"ok": True, "dir": fetch_models()}, "enroll": lambda: enroll(fc),
          "verify": lambda: verify(fc), "forget": forget, "status": lambda: status(fc)}.get(cmd)
    if not fn:
        print(cli.__doc__)
        sys.exit(2)
    if cmd == "enroll" and sys.stdout.isatty():
        print("카메라를 보고 10초쯤 가만히 — 고개를 조금씩 좌우로 돌리면 더 잘 알아봅니다.", file=sys.stderr)
    try:
        r = fn()
    except Exception as e:  # noqa: BLE001
        r = {"ok": False, "error": str(e)}
    print(json.dumps(r, ensure_ascii=False), flush=True)
    sys.exit(0 if r.get("ok") or cmd == "status" else 1)


# ── 데몬 쪽 ─────────────────────────────────────────────────────────────
class Gate:
    """데몬이 부르는 문지기. 무슨 일이 있어도 예외를 던지지 않고 결과 dict 를 돌려줍니다."""

    def __init__(self, fc: dict):
        self.fc = fc

    def active(self) -> bool:
        """켜져 있고 등록까지 했을 때만 얼굴을 봄. 등록 전이면 예전처럼 박수만으로 깨어남."""
        return bool(self.fc.get("enabled")) and enrolled()

    def _run(self, cmd: str, timeout: float) -> dict:
        root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        env = dict(os.environ, OPENCV_LOG_LEVEL="ERROR")
        try:
            p = subprocess.run([sys.executable, "-m", "desk", "face", cmd], cwd=root, env=env,
                               capture_output=True, text=True, timeout=timeout)
        except subprocess.TimeoutExpired:
            return {"ok": False, "error": f"{timeout:.0f}초 안에 못 끝냄(카메라 멈춤?)"}
        except Exception as e:  # noqa: BLE001
            return {"ok": False, "error": str(e)}
        for line in reversed(p.stdout.strip().splitlines()):
            with contextlib.suppress(ValueError):
                r = json.loads(line)
                if isinstance(r, dict):
                    return r
        return {"ok": False, "error": f"확인 프로그램이 죽음 (코드 {p.returncode}) {p.stderr.strip()[-200:]}"}

    def check(self) -> dict:
        return self._run("verify", float(self.fc.get("timeout_s", 15)))

    def enroll(self) -> dict:
        return self._run("enroll", 120)
