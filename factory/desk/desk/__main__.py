"""python -m desk <명령>

  run         상주 (launchd 가 부름)
  calibrate   박수 · 소음 값을 실시간으로 보기 — 방에서 박수를 쳐 보고 config 를 맞춤
  selftest    마이크 · 말하기 · 받아쓰기 · Claude · gh 를 차례로 확인
  brief       브리핑 글만 출력 (말 안 함)
  face <명령>  얼굴 인증: models(모델 받기) · enroll(등록) · verify(확인) · forget(지우기) · status
  ctl <명령> [글]  실행 중인 데몬에 명령: wake · sleep · brief · mute · unmute · stop · say · show · model [이름]
                   · enroll(얼굴 등록) · face(얼굴 확인만)
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
        print(urllib.request.urlopen(req, timeout=150).read().decode())
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
        x = sd.rec(int(sr * 2), samplerate=sr, channels=1, dtype="float32", device=cfg["audio"].get("device") or None)
        sd.wait()
        rms = float(np.sqrt(np.mean(x ** 2)))
        if rms < 0.003:
            raise RuntimeError(f"소리가 거의 없음 (rms {rms:.4f}) — 마이크 권한 · 입력 장치 확인")
        return f"rms {rms:.3f}"

    def tts():
        v = mac.make_voice(cfg["tts"])
        if hasattr(v, "ready"):                 # 신경망 목소리: 모델이 뜰 때까지(처음이면 내려받기)
            v.ready.wait(300)
            if v.error:
                raise RuntimeError(f"Supertonic 못 씀 — {v.error} (pip install supertonic)")
        v.say("책상 시스템 점검 중입니다.", block=True)
        where = cfg["tts"].get("device") or "기본 출력"
        if hasattr(v, "engine"):
            return f"{v.engine} · {where}"
        voices = subprocess.run(["say", "-v", "?"], capture_output=True, text=True).stdout
        if cfg["tts"]["voice"] not in voices:
            raise RuntimeError(f"음성 {cfg['tts']['voice']} 없음 — 설정 → 손쉬운 사용 → 읽기 및 말하기에서 내려받기")
        if "(" not in v.voice:
            return f"{v.voice} · {where} — 프리미엄을 받으면 더 자연스러움"
        return f"{v.voice} · {where}"

    def daemon_mic():
        # 시험(터미널)이 들린다고 상주 프로그램도 들리는 게 아닙니다 — 권한 주인이 다릅니다(터미널 vs deskd)
        import json
        port = cfg["dashboard"]["port"]
        try:
            st = json.loads(urllib.request.urlopen(f"http://127.0.0.1:{port}/state", timeout=3).read())
        except Exception:
            raise RuntimeError("deskd 가 안 떠 있음 — launchctl kickstart -k gui/$(id -u)/lab.deskd, "
                               "로그: tail ~/Library/Logs/deskd.log") from None
        if st.get("mic") == "blocked":
            raise RuntimeError("deskd 마이크 막힘 — 설정 → 개인정보 보호 및 보안 → 마이크 → deskd 켜기. "
                               "목록에 없으면: tccutil reset Microphone 뒤 launchctl kickstart -k gui/$(id -u)/lab.deskd")
        if st.get("mic") != "ok":
            raise RuntimeError("deskd 가 아직 소리를 못 받음 — 권한 창이 떠 있으면 허용 뒤 20초 기다렸다 다시")
        return f"지금 {st.get('mode')}"

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
            raise RuntimeError((r.stderr.strip() or r.stdout.strip())[-200:])   # "Not logged in" 은 stdout 으로 나옴
        return r.stdout.strip()[:40]

    def face():
        from . import face as f
        st = f.status(cfg["face"])
        if not st["enabled"]:
            return "꺼짐 (config [face] enabled = false) — 박수만으로 깨어남"
        if not st["models"]:
            raise RuntimeError("모델 없음 — python -m desk face models")
        if not st["enrolled"]:
            raise RuntimeError("얼굴 등록 전 — 박수만으로 깨어남. 등록: deskctl enroll")
        return "등록됨" + (" · hand-mouse 와 카메라 같이 씀(640×480)" if st["hand_mouse"] else "")

    def brief():
        return briefing.compose(briefing.gather(cfg))[:80] + "…"

    step("마이크", mic)
    step("말하기", tts)
    step("받아쓰기 모델", stt)
    step("Claude", claude)
    step("브리핑", brief)
    step("상주 프로그램(deskd) 마이크", daemon_mic)
    step("얼굴 인증", face)
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
    elif cmd == "face":
        from .face import cli
        cli(argv[2:])
    elif cmd == "ctl":
        ctl(argv[2] if len(argv) > 2 else "brief", " ".join(argv[3:]))
    else:
        print(__doc__)


if __name__ == "__main__":
    main(sys.argv)
