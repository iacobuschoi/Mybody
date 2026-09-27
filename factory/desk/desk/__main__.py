"""python -m desk <명령>

  run         상주 (launchd 가 부름)
  calibrate   박수 · 소음 값을 실시간으로 보기 — 방에서 박수를 쳐 보고 config 를 맞춤
  selftest    마이크 · 말하기 · 받아쓰기 · Claude · gh 를 차례로 확인
  brief       브리핑 글만 출력 (말 안 함)
  ctl <명령> [글]  실행 중인 데몬에 명령: wake · sleep · brief · mute · unmute · stop · say · show
"""
from __future__ import annotations

import sys
import time
import urllib.request


def ctl(cmd: str, text: str = "", port: int = 7070) -> None:
    if cmd == "show" and not text and not sys.stdin.isatty():
        text = sys.stdin.read()
    req = urllib.request.Request(f"http://127.0.0.1:{port}/api/{cmd}", data=text.encode(), method="POST")
    try:
        print(urllib.request.urlopen(req, timeout=60).read().decode())
    except Exception as e:  # noqa: BLE001
        print(f"deskd 에 닿지 못함: {e}", file=sys.stderr)
        sys.exit(1)


def calibrate() -> None:
    import sounddevice as sd
    from . import config
    from .clap import ClapConfig, ClapDetector
    cfg = config.load()
    sr = cfg["audio"]["samplerate"]
    det = ClapDetector(ClapConfig(sr=sr, **cfg.get("clap", {})))
    print("박수를 쳐 보세요. 큰 소리마다 한 줄, 묶음이 끝나면 ★. Ctrl+C 로 끝.")
    print("값 보는 법: 박수 centroid 가 min_centroid_hz 보다 충분히 높고, 말소리는 낮아야 합니다.")
    last = 0.0

    def cb(indata, frames, t, status):  # noqa: ARG001
        nonlocal last
        for n in det.feed(indata[:, 0].copy()):
            print(f"  ★ 묶음 끝: 박수 {n}번")
        f = det.last_frame or {}
        if f.get("centroid") is not None:
            print(f"  {f['t']:7.2f}s  rms {f['rms']:.3f}  바닥 {f['floor']:.4f}  문턱 {f['thr']:.3f}  "
                  f"centroid {f['centroid']:.0f}Hz")
        if time.time() - last > 5:
            last = time.time()
            print(f"  (바닥 소음 {f.get('floor', 0):.4f})")

    with sd.InputStream(samplerate=sr, channels=1, dtype="float32", blocksize=int(sr * 0.03),
                        device=cfg["audio"].get("device") or None, callback=cb):
        try:
            while True:
                time.sleep(0.2)
        except KeyboardInterrupt:
            pass


def selftest() -> None:
    import shutil
    import subprocess
    from . import briefing, config, mac
    cfg = config.load()
    ok = True

    def step(name, fn):
        nonlocal ok
        print(f"— {name} … ", end="", flush=True)
        try:
            r = fn()
            print("OK" + (f" ({r})" if r else ""))
        except Exception as e:  # noqa: BLE001
            ok = False
            print(f"실패: {e}")

    def mic():
        import numpy as np
        import sounddevice as sd
        sr = cfg["audio"]["samplerate"]
        print("2초 동안 말해 보세요 … ", end="", flush=True)
        x = sd.rec(int(sr * 2), samplerate=sr, channels=1, dtype="float32")
        sd.wait()
        rms = float(np.sqrt(np.mean(x ** 2)))
        if rms < 0.003:
            raise RuntimeError(f"소리가 거의 없음 (rms {rms:.4f}) — 마이크 권한 · 입력 장치 확인")
        return f"rms {rms:.3f}"

    def tts():
        v = mac.Voice(cfg["tts"]["voice"], cfg["tts"]["rate"])
        v.say("책상 시스템 점검 중입니다.", block=True)
        voices = subprocess.run(["say", "-v", "?"], capture_output=True, text=True).stdout
        if cfg["tts"]["voice"] not in voices:
            raise RuntimeError(f"음성 {cfg['tts']['voice']} 없음 — 설정 → 손쉬운 사용 → 읽기 및 말하기에서 내려받기")

    def stt():
        from .stt import WhisperSTT
        s = WhisperSTT(cfg["stt"]["model"], cfg["stt"]["language"])
        t0 = time.time()
        s.warmup()
        return f"모델 준비 {time.time() - t0:.1f}초"

    def claude():
        exe = shutil.which("claude")
        if not exe:
            raise RuntimeError("claude 가 PATH 에 없음")
        r = subprocess.run([exe, "-p", "한 단어로: 준비됐어?", "--output-format", "text"], capture_output=True,
                           text=True, timeout=90, cwd=__import__("os").path.expanduser(cfg["brain"]["workdir"]))
        if r.returncode:
            raise RuntimeError(r.stderr.strip()[-200:])
        return r.stdout.strip()[:40]

    def brief():
        return briefing.compose(briefing.gather(cfg))[:80] + "…"

    step("마이크", mic)
    step("말하기", tts)
    step("받아쓰기 모델", stt)
    step("Claude", claude)
    step("브리핑", brief)
    print("전부 OK" if ok else "실패한 것을 고친 뒤 다시: python -m desk selftest")
    sys.exit(0 if ok else 1)


def main(argv: list[str]) -> None:
    cmd = argv[1] if len(argv) > 1 else "run"
    if cmd == "run":
        from .daemon import main as run
        run()
    elif cmd == "calibrate":
        calibrate()
    elif cmd == "selftest":
        selftest()
    elif cmd == "brief":
        from . import briefing, config
        print(briefing.compose(briefing.gather(config.load())))
    elif cmd == "ctl":
        ctl(argv[2] if len(argv) > 2 else "brief", " ".join(argv[3:]))
    else:
        print(__doc__)


if __name__ == "__main__":
    main(sys.argv)
