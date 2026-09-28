"""deskd — 책상의 상주 프로그램.

    자는 중(화면 꺼짐) ──박수 두 번──▶ (얼굴 인증) ──주인──▶ 깨어남: 화면 켜기 · 차임 · 인사 · 브리핑
         ▲          ▲ 아니면 짧게 알리고 그대로 ─┘                │
         │ "화면 꺼" · 15분 조용 · 박수(설정)   ▼
         └──────────────────────────── 듣는 중 ──말──▶ 로컬 명령(즉시) 또는 Claude(생각 중 → 말하는 중)
                                          │ "조용히" ▲ "다시 들어" · 박수 두 번
                                          ▼         │
                                        조용히 모드 ─┘

자는 중에는 받아쓰기를 하지 않습니다(박수만 봅니다) — 방에서 하는 말이 글로 남지 않고, 전기도 덜 씁니다.
맥은 잠들지 않습니다(caffeinate -i). 잠들면 마이크가 멈춰 박수를 못 듣습니다. 화면만 꺼집니다.
"""
from __future__ import annotations

import datetime as dt
import json
import logging
import queue
import threading
import time

import numpy as np

from . import briefing, config, mac
from .face import Gate
from .brain import Brain
from .clap import ClapConfig, ClapDetector
from .dashboard import Board, serve
from .router import route
from .stt import WhisperSTT
from .vad import Segmenter

log = logging.getLogger("deskd")


class Desk:
    def __init__(self, cfg: dict):
        self.cfg = cfg
        sr = cfg["audio"]["samplerate"]
        self.sr = sr
        ccfg = ClapConfig(sr=sr, **cfg.get("clap", {}))
        self.clap = ClapDetector(ccfg)
        li = cfg["listen"]
        self.seg = Segmenter(sr=sr, level=li["vad_level"], end_silence_s=li["end_silence_s"],
                             min_utt_s=li["min_utt_s"], max_utt_s=li["max_utt_s"], energy_db=li["energy_db"])
        st = cfg["stt"]
        self.stt = WhisperSTT(st["model"], st["language"], st.get("prompt", ""))
        self.voice = mac.Voice(cfg["tts"]["voice"], cfg["tts"]["rate"], device=cfg["tts"].get("device", ""))
        b = cfg["brain"]
        self.brain = Brain(b["workdir"], b.get("model", ""), b.get("timeout_s", 180))
        self.board = Board()
        self.face = Gate(cfg["face"])
        self._verifying = False                       # 얼굴 보는 중엔 박수를 더 받지 않음
        self.mode = "sleep"                          # sleep · awake · muted
        self.last_activity = time.time()
        self.audio_q: queue.Queue[np.ndarray] = queue.Queue(maxsize=400)
        self.utt_q: queue.Queue[np.ndarray] = queue.Queue(maxsize=8)
        self.brain_q: queue.Queue[str] = queue.Queue(maxsize=8)
        self._stop = threading.Event()
        self._dash_opened = False
        self._changed_at = 0.0                        # 우리가 화면을 켜고/끈 시각 — 화면 감시가 헷갈리지 않게
        self.mic_blocked = False
        self._mic_heard = time.time()                 # 마지막으로 0 이 아닌 소리가 들어온 시각
        self._mic_warned = False

    # ── 상태 바꾸기 ────────────────────────────────────────────────────────
    def _show(self, sub: str | None = None) -> None:
        m = {"sleep": "sleep", "muted": "muted"}.get(self.mode)
        self.board.set(mode=m or sub or ("speaking" if self.voice.busy() else
                                         "thinking" if self.brain.busy() else "listening"))

    def wake(self, why: str = "clap", greeting: str = "시스템을 시작합니다.") -> str:
        why = why or "deskctl"                         # /api/wake 는 빈 글을 넘김
        if self.mode != "sleep":
            self.say_brief()
            return "이미 깨어 있음"
        log.info("깨어남 (%s)", why)
        self._changed_at = time.time()
        self.mode = "awake"
        self.last_activity = time.time()
        self.clap.reset()
        self.seg.reset()
        mac.display_on()
        mac.sound("Glass")
        if not self._dash_opened:
            mac.open_dashboard(f"http://127.0.0.1:{self.cfg['dashboard']['port']}", self.cfg["dashboard"].get("open_cmd", ""))
            self._dash_opened = True
        self.board.log("wake", why)
        self.voice.say(greeting)
        threading.Thread(target=self.say_brief, daemon=True).start()
        self._show()
        return "ok"

    # ── 얼굴 인증 ──────────────────────────────────────────────────────────
    def clap_wake(self) -> None:
        """자는 중에 박수 — 얼굴 인증을 켰고 등록했으면 먼저 얼굴을 봅니다(따로 스레드, 소리 흐름은 안 멈춤)"""
        if self._verifying:
            return
        if not self.face.active():
            self.wake("clap")
            return
        self._verifying = True
        threading.Thread(target=self._face_wake, daemon=True).start()

    def _face_wake(self) -> None:
        fc = self.cfg["face"]
        try:
            self.board.log("face", "얼굴 확인 중")
            self.voice.say(fc.get("prompt", ""))
            r = self.face.check()
            log.info("얼굴 확인: %s", r)
            if self.mode != "sleep":                   # 그새 키보드 · deskctl 로 깨어남
                return
            if r.get("ok"):
                self.wake("clap · 얼굴", greeting=self._welcome())
                return
            err = r.get("error")
            self.board.log("face", f"실패: {err}" if err else f"주인 아님 (닮음 {r.get('best', 0)})")
            if err and fc.get("on_error") == "wake":
                self.wake("clap · 얼굴 확인 못 함")
                return
            while self.voice.busy():
                time.sleep(0.1)
            self.voice.say(fc.get("error_say", "") if err else fc.get("fail", ""))
            self.clap.reset()
        except Exception as e:  # noqa: BLE001 — 무슨 일이 있어도 데몬은 계속
            log.exception("얼굴 확인 중 오류")
            self.board.log("error", f"얼굴 확인: {e}")
        finally:
            self._verifying = False

    def _welcome(self) -> str:
        fc = self.cfg["face"]
        name = (fc.get("name") or self.cfg.get("owner") or "").strip()
        if not name:
            return "환영합니다."
        try:
            return fc.get("welcome", "{name}님, 환영합니다.").format(name=name)
        except (KeyError, IndexError, ValueError):
            return f"{name}님, 환영합니다."

    def enroll(self, _: str = "") -> str:
        """deskctl enroll — 데몬이 찍어서 카메라 권한이 deskd 하나로 끝남"""
        self.voice.say("카메라를 보고 10초쯤 기다려 주세요.")
        r = self.face.enroll()
        self.board.log("face", f"등록: {r}")
        self.voice.say("얼굴을 등록했어요." if r.get("ok") else "얼굴 등록에 실패했어요. 자세한 건 화면에.")
        return json.dumps(r, ensure_ascii=False)

    def face_test(self, _: str = "") -> str:
        """deskctl face — 지금 카메라 앞 얼굴이 주인인지(깨우지는 않음)"""
        if not self.face.active():
            return json.dumps({"ok": False, "error": "얼굴 인증이 꺼져 있거나 등록 전"}, ensure_ascii=False)
        return json.dumps(self.face.check(), ensure_ascii=False)

    def say_brief(self, _: str = "") -> str:
        data = briefing.gather(self.cfg)
        text = briefing.compose(data, owner=self.cfg.get("owner", ""))
        self.board.set(briefing=data, reply=text)
        while self.voice.busy():
            time.sleep(0.1)
        self.voice.say(text)
        return text

    def sleep(self, why: str = "voice") -> str:
        why = why or "deskctl"
        log.info("잠듦 (%s)", why)
        self.brain.cancel()
        self.voice.say("화면 끌게요. 박수 두 번이면 다시 켜요.", block=True)
        self.mode = "sleep"
        self._changed_at = time.time()
        self.seg.reset()
        self.clap.reset()
        mac.display_off()
        self.board.log("sleep", why)
        self._show()
        return "ok"

    def mute(self, _: str = "") -> str:
        self.mode = "muted"
        self.voice.say("조용히 있을게요. 다시 들어, 또는 박수 두 번.")
        self.board.log("mute", "")
        self._show()
        return "ok"

    def unmute(self, _: str = "") -> str:
        self.mode = "awake"
        self.last_activity = time.time()
        self.clap.reset()
        mac.sound("Tink")
        self.board.log("unmute", "")
        self._show()
        return "ok"

    def stop(self, _: str = "") -> str:
        self.voice.stop()
        cancelled = self.brain.cancel()
        self.board.log("stop", "Claude 작업 취소" if cancelled else "")
        return "ok"

    def show(self, text: str) -> str:
        """Claude 가 긴 내용을 화면에 (deskctl show)"""
        self.board.set(panel=text[:20000])
        return "ok"

    # ── 들은 말 처리 ───────────────────────────────────────────────────────
    def handle(self, text: str) -> None:
        a = route(text, muted=(self.mode == "muted"))
        self.board.log(a.kind, text)
        if a.kind == "ignore":
            return
        self.last_activity = time.time()
        self.board.set(heard=text)
        k = a.kind
        if k == "unmute":
            self.unmute()
        elif k == "mute":
            self.mute()
        elif k == "sleep":
            self.sleep("voice")
        elif k == "stop":
            self.stop()
        elif k == "brief":
            threading.Thread(target=self.say_brief, daemon=True).start()
        elif k in ("louder", "softer"):
            v = mac.change_volume(10 if k == "louder" else -10)
            self.voice.say(f"소리 {v}." if v >= 0 else "소리를 바꿨어요.")
        elif k == "repeat":
            self.voice.say(self.voice.last_text or "아직 한 말이 없어요.")
        elif k == "time":
            n = dt.datetime.now()
            self.voice.say(f"{'오전' if n.hour < 12 else '오후'} {n.hour % 12 or 12}시 {n.minute}분이에요.")
        elif k == "claude":
            mac.sound("Tink")                       # 들었다는 표시 — 말로 "잠시만요" 하면 매번 귀찮습니다
            try:
                self.brain_q.put_nowait(text)
            except queue.Full:
                self.voice.say("밀린 일이 많아요. 잠시 뒤에 다시 말해 주세요.")
        self._show()

    # ── 일꾼 스레드 ────────────────────────────────────────────────────────
    def _stt_worker(self) -> None:
        while not self._stop.is_set():
            audio = self.utt_q.get()
            try:
                text = self.stt.transcribe(audio)
            except Exception as e:  # noqa: BLE001
                log.exception("받아쓰기 실패")
                self.board.log("error", f"받아쓰기: {e}")
                continue
            if text:
                log.info("들음: %s", text)
                self.handle(text)

    def _brain_worker(self) -> None:
        while not self._stop.is_set():
            text = self.brain_q.get()
            self._show("thinking")
            spoken, full = self.brain.ask(text)
            if spoken is None:
                self.board.log("ignore", f"(Claude: 나한테 한 말 아님) {text}")
            else:
                self.board.set(reply=full)
                if self.mode != "sleep":
                    self.voice.say(mac.speakable(spoken))
            self.last_activity = time.time()
            self._show()

    # ── 마이크 권한 ────────────────────────────────────────────────────────
    def _mic_check(self, x: np.ndarray | None, now: float | None = None) -> bool:
        """권한이 없으면 macOS 는 마이크 대신 정확히 0 만 보냅니다. 진짜 마이크는 조용한 방에서도 0 이 아닙니다.
        막혔다고 처음 알게 되면 True (호출한 쪽이 스트림을 다시 열 때 씀)."""
        now = time.time() if now is None else now
        if x is not None and np.any(x):
            self._mic_heard = now
            if self.mic_blocked:
                self.mic_blocked = False
                log.info("마이크 들림")
                self.board.log("mic", "마이크 들림")
            self.board.set(mic="ok")
            return False
        if self.mic_blocked or now - self._mic_heard < 6:
            return False
        self.mic_blocked = True
        log.warning("마이크에서 0 만 들어옴 — 권한 없음? 설정 → 개인정보 보호 및 보안 → 마이크 → deskd")
        self.board.set(mic="blocked")
        self.board.log("error", "마이크 막힘 — 설정 → 개인정보 보호 및 보안 → 마이크 → deskd 켜기")
        if not self._mic_warned:                      # 화면이 꺼져 있어도 들리게 한 번은 말로
            self._mic_warned = True
            self.voice.say("마이크 권한이 없어서 박수를 못 들어요. 시스템 설정, 개인정보 보호 및 보안, 마이크에서 deskd를 켜 주세요.")
        return True

    # ── 소리 흐름 ──────────────────────────────────────────────────────────
    def _required_claps(self) -> int:
        w = self.cfg["wake"]
        a, b = w.get("night", ["01:00", "07:00"])
        now = dt.datetime.now().strftime("%H:%M")
        if a == b:
            return int(w["claps"])                     # 밤 구간 없음
        night = (a <= now < b) if a < b else (now >= a or now < b)
        return int(w["night_claps"] if night else w["claps"])

    def _on_audio(self, x: np.ndarray) -> None:
        bursts = self.clap.feed(x)
        if self.mode == "sleep":
            if any(n == self._required_claps() for n in bursts):
                self.clap_wake()
            return
        if bursts and any(n == 2 for n in bursts):
            if self.mode == "muted":
                self.unmute()
                return
            if self.cfg["wake"].get("clap_when_awake") == "sleep" and not self.seg.in_speech:
                threading.Thread(target=self.sleep, args=("clap",), daemon=True).start()
                return
        if self.mode == "awake" or self.mode == "muted":
            if self.voice.busy():
                self.seg.pause()                     # 스피커에서 나가는 제 목소리를 듣지 않게
                return
            self.seg.resume()
            for utt in self.seg.feed(x):
                try:
                    self.utt_q.put_nowait(utt)
                except queue.Full:
                    pass
        if self.mode == "awake" and time.time() - self.last_activity > self.cfg["idle_minutes"] * 60 \
                and not self.voice.busy() and not self.brain.busy() and not self.seg.in_speech:
            threading.Thread(target=self.sleep, args=("idle",), daemon=True).start()
            self.last_activity = time.time()

    def run(self) -> None:
        import sounddevice as sd
        mac.keep_system_awake()
        serve(self.board, {"wake": self.wake, "sleep": self.sleep, "brief": self.say_brief, "mute": self.mute,
                           "unmute": self.unmute, "stop": self.stop,
                           "say": lambda t: (self.voice.say(t), "ok")[1], "show": self.show,
                           "enroll": self.enroll, "face": self.face_test},
              port=self.cfg["dashboard"]["port"])
        threading.Thread(target=self._stt_worker, daemon=True).start()
        threading.Thread(target=self._brain_worker, daemon=True).start()
        threading.Thread(target=self._warmup, daemon=True).start()

        def cb(indata, frames, t, status):  # noqa: ARG001
            try:
                self.audio_q.put_nowait(indata[:, 0].copy())
            except queue.Full:
                pass

        dev = self.cfg["audio"].get("device") or None
        log.info("deskd 시작 · 마이크 %s · 박수 %d번(밤 %d번)", dev or "기본", self.cfg["wake"]["claps"],
                 self.cfg["wake"]["night_claps"])
        self._show()
        last_show = last_display = 0.0
        while not self._stop.is_set():
            opened = self._mic_heard = time.time()
            # 권한을 나중에 허용하면 이미 열린 스트림엔 계속 0 이 옵니다 — 막혀 있는 동안은 20초마다 다시 엽니다
            with sd.InputStream(samplerate=self.sr, channels=1, dtype="float32", blocksize=int(self.sr * 0.03),
                                device=dev, callback=cb):
                while not self._stop.is_set():
                    try:
                        x = self.audio_q.get(timeout=1)
                    except queue.Empty:
                        x = None
                    self._mic_check(x)
                    if self.mic_blocked and time.time() - opened > 20:
                        break
                    if x is None:
                        continue
                    self._on_audio(x)
                    if time.time() - last_show > 0.5:        # 말하기가 끝났는지 등 — 상태판을 따라가게
                        self._show()
                        last_show = time.time()
                    if time.time() - last_display > 2:       # 키보드로 켠 화면 · 저절로 꺼진 화면 따라가기
                        self._watch_display()
                        last_display = time.time()

    def _watch_display(self) -> None:
        """박수 말고 다른 걸로 화면이 켜지거나 꺼졌을 때 상태를 맞춥니다.
        키보드 · 마우스로 화면을 켜면 → 조용히 '듣는 중'(인사 · 브리핑 없이 딩만)
        30분 안전망이나 손으로 화면이 꺼지면 → '자는 중'"""
        if time.time() - self._changed_at < 8:
            return
        asleep = mac.displays_asleep()
        if asleep is None:
            return
        if self.mode == "sleep" and not asleep:
            log.info("화면이 켜짐(키보드 · 마우스) → 듣는 중")
            self._changed_at = time.time()
            self.mode = "awake"
            self.last_activity = time.time()
            self.clap.reset()
            self.seg.reset()
            mac.sound("Tink")
            self.board.log("wake", "키보드 · 마우스")
            self._show()
        elif self.mode in ("awake", "muted") and asleep and not self.voice.busy():
            log.info("화면이 꺼짐 → 자는 중")
            self._changed_at = time.time()
            self.brain.cancel()
            self.mode = "sleep"
            self.seg.reset()
            self.clap.reset()
            self.board.log("sleep", "화면 꺼짐")
            self._show()

    def _warmup(self) -> None:
        try:
            self.stt.warmup()                        # 첫 받아쓰기가 모델 내려받기 · 올리기로 늦지 않게
            log.info("받아쓰기 모델 준비됨")
        except Exception as e:  # noqa: BLE001
            log.warning("받아쓰기 준비 실패: %s", e)
            self.board.log("error", f"받아쓰기 준비 실패: {e}")


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    Desk(config.load()).run()
