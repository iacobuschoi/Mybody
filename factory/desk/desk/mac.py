"""맥에 시키는 것 — 화면 켜고 끄기 · 말하기 · 소리 크기 · 효과음. 전부 macOS 기본 명령입니다."""
from __future__ import annotations

import re
import shutil
import subprocess
import threading
import time

SOUNDS = "/System/Library/Sounds"


def _run(cmd: list[str], timeout: float = 5) -> str:
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout).stdout.strip()
    except Exception:
        return ""


def display_on() -> None:
    """꺼진 화면을 켭니다. `caffeinate -u` = 사용자가 뭔가 했다고 알림 → 두 모니터 다 켜짐."""
    subprocess.Popen(["caffeinate", "-u", "-t", "3"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def display_off() -> None:
    subprocess.Popen(["pmset", "displaysleepnow"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def displays_asleep() -> bool | None:
    """모르면 None. (pyobjc 가 있으면 실제 상태)"""
    try:
        import Quartz
        return bool(Quartz.CGDisplayIsAsleep(Quartz.CGMainDisplayID()))
    except Exception:
        return None


def keep_system_awake() -> subprocess.Popen:
    """이 프로세스가 사는 동안 시스템 잠자기 금지(화면은 꺼져도 됨). 잠들면 마이크도 멈춰 박수를 못 듣습니다."""
    import os
    return subprocess.Popen(["caffeinate", "-i", "-s", "-w", str(os.getpid())],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def sound(name: str = "Glass") -> None:
    subprocess.Popen(["afplay", f"{SOUNDS}/{name}.aiff"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def change_volume(delta: int) -> int:
    out = _run(["osascript", "-e",
                f"set v to (output volume of (get volume settings)) + {delta}\n"
                "if v > 100 then set v to 100\nif v < 0 then set v to 0\n"
                "set volume output volume v\nreturn v"])
    return int(out) if out.isdigit() else -1


def open_dashboard(url: str, cmd: str = "") -> None:
    if cmd:
        subprocess.Popen(cmd.replace("{url}", url), shell=True)
        return
    chrome = "/Applications/Google Chrome.app"
    import os
    if os.path.exists(chrome):
        subprocess.Popen(["open", "-na", "Google Chrome", "--args", f"--app={url}", "--start-fullscreen"])
    else:
        subprocess.Popen(["open", url])


def speakable(text: str, max_sentences: int = 3) -> str:
    """화면용 글을 말하기 좋게: 마크다운 · 코드 · 링크를 걷고 앞 몇 문장만."""
    t = re.sub(r"```.*?```", " ", text, flags=re.S)
    t = re.sub(r"`([^`]*)`", r"\1", t)
    t = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", t)
    t = re.sub(r"https?://\S+", "", t)
    t = re.sub(r"^[#>\-\*\d\.\s]+", "", t, flags=re.M)
    t = re.sub(r"[*_#|]", "", t)
    t = re.sub(r"\s+", " ", t).strip()
    parts = re.split(r"(?<=[.!?。])\s+|(?<=다\.)\s*|(?<=요\.)\s*", t)
    parts = [p.strip() for p in parts if p and p.strip()]
    return " ".join(parts[:max_sentences]) if parts else t


def best_voice(name: str) -> str:
    """음성 이름 "Yuna" → 받아 둔 것 중 가장 좋은 것("Yuna (Premium)" > "Yuna (Enhanced)" > "Yuna").
    괄호까지 적었으면 그대로. `say -v ?` 한 줄: 「이름   언어_지역   # 예문」."""
    if not name or "(" in name:
        return name
    names = [m.group(1).strip() for m in
             (re.match(r"^(.+?)\s+[a-z]{2,3}_[A-Z]{2,}\s+#", ln) for ln in _run(["say", "-v", "?"]).splitlines()) if m]
    mine = [n for n in names if n == name or n.startswith(name + " (")]
    for words in (("Premium", "프리미엄"), ("Enhanced", "향상")):
        for n in mine:
            if any(w in n for w in words):
                return n
    return name


def make_voice(c: dict) -> "Voice":
    """[tts] 설정대로 목소리를 만듭니다. engine = "supertonic" 이면 신경망 목소리(desk/tts.py, 못 쓰면 알아서 say)."""
    if c.get("engine") == "supertonic":
        from .tts import NeuralVoice
        return NeuralVoice(c.get("style", "F1"), c.get("model", "supertonic-3"), c.get("speed", 1.05),
                           c.get("steps", 5), voice=c["voice"], rate=c["rate"], device=c.get("device", ""))
    return Voice(c["voice"], c["rate"], device=c.get("device", ""))


class Voice:
    """`say` 로 말하기. 말하는 동안 busy — 데몬이 그동안 귀를 닫습니다(제 목소리를 명령으로 안 듣게)."""

    def __init__(self, voice: str = "Yuna", rate: int = 190, tail_s: float = 0.5, device: str = ""):
        # device: 소리를 낼 장치(say -a). 비우면 시스템 기본 출력.
        # TV 를 HDMI 로 꽂으면 맥이 기본 출력을 TV 로 바꾸는데, TV 가 꺼져 있으면 안내가 안 들립니다 —
        # 그래서 맥 미니 내장 스피커를 이름으로 고정해 둡니다(install.sh 가 찾아서 넣음).
        self.voice, self.rate, self.tail_s, self.device = voice, rate, tail_s, device
        self._p: subprocess.Popen | None = None
        self._until = 0.0
        self._lock = threading.Lock()
        self.last_text = ""
        if not shutil.which("say"):
            self.voice = ""
        else:
            self.voice = best_voice(voice)

    def busy(self) -> bool:
        with self._lock:
            running = self._p is not None and self._p.poll() is None
        return running or time.time() < self._until

    def say(self, text: str, block: bool = False) -> None:
        text = (text or "").strip()
        if not text:
            return
        self.stop()
        self.last_text = text
        cmd = (["say", "-r", str(self.rate)] + (["-v", self.voice] if self.voice else [])
               + (["-a", self.device] if self.device else []) + [text])
        with self._lock:
            try:
                self._p = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            except FileNotFoundError:
                print("[말]", text)
                return
        if block:
            self.wait()
        else:
            threading.Thread(target=self.wait, daemon=True).start()

    def wait(self) -> None:
        p = self._p
        if p:
            p.wait()
        self._until = time.time() + self.tail_s

    def stop(self) -> None:
        with self._lock:
            if self._p and self._p.poll() is None:
                self._p.terminate()
            self._p = None
        self._until = time.time() + 0.2
