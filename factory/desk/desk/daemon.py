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

import contextlib
import datetime as dt
import json
import logging
import queue
import threading
import time
from collections import deque

import numpy as np

from . import briefing, config, devices, mac, model_settings, voice_settings
from .face import Gate
from .bargein import Listener, has_stop_word, is_stop_utterance, only_stop_words, strip_echo
from .brain import Brain
from .clap import ClapConfig, ClapDetector
from .dictate import Dictation, can_post_keys
from .dashboard import Board, serve, watch_agents
from .router import normalize, route
from .stt import WhisperSTT
from .talk import PushToTalk
from .endpoint import looks_unfinished
from .vad import Cut, Segmenter

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
                             min_utt_s=li["min_utt_s"], max_utt_s=li["max_utt_s"], energy_db=li["energy_db"],
                             hold_silence_s=li.get("hold_silence_s", 0.0), min_level=li.get("min_level", 1e-5),
                             on_drop=lambda s, peak: log.info("짧아서 버림: 말 %.2f초 (기준 %.2f) · 가장 큰 %.4f",
                                                              s, li["min_utt_s"], peak))
        self.echo_s = float(li.get("echo_s", 0.2))   # 스피커 소리가 그친 뒤 이만큼만 귀를 닫음(되울림)
        self._deaf = False                           # 말하는 중이라 상시 듣기를 닫아 둔 상태
        self._spk: deque[np.ndarray] = deque()       # 닫아 둔 동안의 마이크 소리(최근 2초) — 겹친 말 앞부분 되살리기
        self._echo_seq: tuple[int, str, int] = (-1, "", 0)   # 비서 말 끝을 앞에 붙여 들은 구간 → (구간, 비서가 한 말, 붙인 칸 수)
        self._finals: set[int] = set()               # 확정 조각이 받아쓰기 줄에 들어간 구간(seq)
        self._taken: dict[int, int] = {}             # 잠정 조각으로 이미 답한 구간 → 그 칸 수
        self._held: dict[int, tuple[int, str]] = {}  # 이어질 듯해 기다리는 구간 → (잠정 조각 칸 수, 받아쓴 글)
        self._stt_s = 0.0                            # 마지막 받아쓰기에 걸린 시간(로그용)
        st = cfg["stt"]
        self.stt = WhisperSTT(st["model"], st["language"], st.get("prompt", ""), cfg["bargein"].get("fast_model", ""))
        self.voice = mac.make_voice(cfg["tts"])
        b = cfg["brain"]
        self.brain = Brain(b["workdir"], b.get("model", ""), b.get("timeout_s", 180))
        self.board = Board()
        self.board.set(model=model_settings.current(self.brain.model), models=model_settings.options())
        self.face = Gate(cfg["face"])
        self.dictation = Dictation(cfg.get("dictate", {}))   # 주먹 쥐고 말하기 → Claude 앱 입력창 (desk/dictate.py)
        tk = cfg.get("talk", {})
        self.talk_on = bool(tk.get("enabled", True))
        self.talk_sound = tk.get("sound", "Morse")
        self.ptt = PushToTalk(sr=sr, **tk)          # 왼손 주먹 = 비서에게 말하기 (desk/talk.py)
        self._verifying = False                       # 얼굴 보는 중엔 박수를 더 받지 않음
        bi = cfg["bargein"]
        self.barge_on = bool(bi.get("enabled", True)) and bool(bi.get("stop_words"))
        self.stop_words = list(bi.get("stop_words", []))
        self.barge = Listener(sr=sr, margin_db=bi.get("margin_db", 3.0), min_s=bi.get("min_s", 0.15),
                              grace_s=bi.get("grace_s", 0.3), listen_s=bi.get("listen_s", (0.5, 0.9)))
        self._barged_at = 0.0                        # 멈춤 말로 말하기를 끊은 시각
        self._turn = 0                               # 멈출 때마다 +1 — 그 전에 받은 말의 답 · 밀린 말하기는 버림
        self._asking: int | None = None               # 지금 Claude 가 답하는 말의 _turn(없으면 None)
        self._stt_lock = threading.Lock()            # 받아쓰기 모델은 한 번에 하나만
        self._probe_mu = threading.Lock()
        self._probe_n = 0                            # 끼어들기 받아쓰기 차례 번호(기다리는 동안 더 새 것이 왔나)
        self.mode = "sleep"                          # sleep · awake · muted
        self.last_activity = time.time()
        self.audio_q: queue.Queue[np.ndarray] = queue.Queue(maxsize=400)
        self.utt_q: queue.Queue[Cut] = queue.Queue(maxsize=8)
        self.brain_q: queue.Queue[tuple[str, int, bool]] = queue.Queue(maxsize=8)   # (들은 말, 받은 때의 _turn, 주먹)
        self._stop = threading.Event()
        self._dash_opened = False
        self._changed_at = 0.0                        # 우리가 화면을 켜고/끈 시각 — 화면 감시가 헷갈리지 않게
        self.mic_blocked = False
        self._mic_heard = time.time()                 # 마지막으로 0 이 아닌 소리가 들어온 시각
        self.side_q: queue.Queue[np.ndarray] = queue.Queue(maxsize=400)   # 박수 · 끼어들기 마이크가 따로일 때
        self._devs: tuple[str, str, str] | None = None   # 지금 쓰는 (마이크, 박수 · 끼어들기 마이크, 스피커) 실제 이름
        self._devs_want: tuple[str, str, str] | None = None   # 장치 감시가 고른 새 짝 — 듣기 고리가 다시 엶
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
        self._cameras_on(why)
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
        turn = self._turn
        data = briefing.gather(self.cfg)
        text = briefing.compose(data, owner=self.cfg.get("owner", ""))
        self.board.set(briefing=data, reply=text)
        while self.voice.busy() and self._turn == turn:
            time.sleep(0.1)
        if self._turn == turn:                     # 기다리는 동안 "멈춰" 했으면 말하지 않음(화면에만)
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
        mac.cameras_off(self.cfg["camera_off"])
        self.board.log("sleep", why)
        self._show()
        return "ok"

    def _cameras_on(self, why: str) -> None:
        """화면이 켜질 때(어느 길로든) 카메라 쓰는 것들을 켬 — 끌 때 cameras_off 의 짝. hand-mouse on 은 이미 켜져 있으면 그대로"""
        def report(cmd: str, out: str) -> None:
            log.info("카메라 켬(%s): %s → %s", why, cmd, out.splitlines()[0] if out else "(출력 없음)")
            self.board.log("camera", f"{cmd}: {out.splitlines()[0] if out else '출력 없음'}")
        mac.cameras_on(self.cfg.get("camera_on", []), report)

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
        cancelled, dropped = self._hush()
        self.board.log("stop", "Claude 작업 취소" if cancelled else (f"밀린 말 {dropped}개 버림" if dropped else ""))
        return "ok"

    def _hush(self) -> tuple[bool, int]:
        """멈춤 — 말하기 · 지금 Claude 가 만드는 답 · 밀린 말(아직 답하지 않은 것)을 모두 버림. (취소했나, 버린 수)"""
        self._turn += 1
        if self.voice.busy():
            self._barged_at = time.time()
        self.voice.stop()
        dropped = 0
        while True:
            try:
                self.brain_q.get_nowait()
                dropped += 1
            except queue.Empty:
                break
        return self.brain.cancel(), dropped

    def remote_say(self, text: str) -> str:
        """deskctl say — 멈춘 뒤 아직 끝나지 않은 Claude 턴이 부르는 말하기는 버림"""
        if self._asking is not None and self._asking != self._turn:
            log.info("멈춘 턴의 말하기 버림: %s", text[:40])
            return "dropped"
        self.voice.say(text)
        return "ok"

    # ── 목소리 설정 창 (상태판) ───────────────────────────────────────────
    def tts_view(self, _: str = "") -> str:
        return json.dumps(voice_settings.view(self.cfg["tts"], getattr(self.voice, "engine", "say")), ensure_ascii=False)

    def _tts_clean(self, body: str) -> dict:
        return voice_settings.clean(json.loads(body or "{}"), mac.korean_voices() + [self.cfg["tts"].get("voice", "")])

    def _neural(self, wait_s: float = 20) -> bool:
        """Supertonic 을 쓸 수 있게 — say 로 켜져 있었으면 그때 모델을 띄웁니다(처음이면 내려받기라 오래 걸릴 수 있음)."""
        if not hasattr(self.voice, "ready"):
            old, self.voice = self.voice, mac.make_voice(self.cfg["tts"], neural=True)
            old.stop()
        return self.voice.ready.wait(wait_s) and self.voice._tts is not None

    def tts_test(self, body: str) -> str:
        """「들어 보기」 — 저장하지 않고 이번 한 번만 그 설정으로."""
        c = self._tts_clean(body)
        if c["engine"] == "supertonic" and not self._neural():
            return "Supertonic 을 아직 못 써요 — " + (getattr(self.voice, "error", "") or "모델을 불러오는 중이에요. 잠시 뒤 다시.")
        self.voice.say(voice_settings.SAMPLE, opts=c)
        return "ok"

    def tts_save(self, body: str) -> str:
        """[tts] 에 기록하고 바로 적용 — deskd 를 다시 켜지 않아도 다음 말부터 이 목소리."""
        c = self._tts_clean(body)
        config.save_table("tts", c)
        self.cfg["tts"].update(c)
        if c["engine"] == "supertonic" and not hasattr(self.voice, "ready"):
            self._neural(0)                          # 모델이 뜨는 동안은 알아서 say 로 말함
        self.voice.configure(c)
        self.board.log("voice", " · ".join(f"{k} {v}" for k, v in c.items()))
        return "저장했어요 — " + getattr(self.voice, "engine", "say")

    # ── 모델 고르기 (상태판 토글 · "빠른 모드" · deskctl model) ────────────
    def model_set(self, text: str = "") -> str:
        """빈 글이면 지금 모델만 알려 줌. 고르면 [brain] model 에 기록하고 다음 말부터 — 다시 켜지 않아도 됨"""
        if not (text or "").strip():
            return model_settings.label(self.brain.model)
        mid = model_settings.resolve(text)
        if not mid:
            raise ValueError(f"모르는 모델: {text.strip()[:40]} — " + " · ".join(o["label"] for o in model_settings.options()))
        if self.cfg["brain"].get("model") != mid:
            config.save_table("brain", {"model": mid})
            self.cfg["brain"]["model"] = mid
            self.brain.model = mid
            self.board.log("model", model_settings.label(mid))
        self.board.set(model=mid)
        return model_settings.label(mid)

    def show(self, text: str) -> str:
        """Claude 가 긴 내용을 화면에 (deskctl show)"""
        self.board.set(panel=text[:20000], panel_at=int(time.time() * 1000))   # 같은 글을 다시 띄워도 다시 보이게
        return "ok"

    # ── 들은 말 처리 ───────────────────────────────────────────────────────
    def handle(self, text: str, direct: bool = False) -> None:
        """direct: 왼손 주먹을 쥐고 한 말 — 조용히 모드여도 받고, Claude 에게 비서에게 한 말이라고 알림"""
        if self._speech_stop(text):
            return
        a = route(text, muted=(self.mode == "muted" and not direct))
        self.board.log(a.kind, ("(주먹) " if direct else "") + text)
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
        elif k == "model":
            self.model_set(a.arg)
            self.voice.say(f"{model_settings.spoken(a.arg)}로 바꿨어요. 다음 말부터 적용돼요.")
        elif k == "time":
            n = dt.datetime.now()
            self.voice.say(f"{'오전' if n.hour < 12 else '오후'} {n.hour % 12 or 12}시 {n.minute}분이에요.")
        elif k == "claude":
            mac.sound("Tink")                       # 들었다는 표시 — 말로 "잠시만요" 하면 매번 귀찮습니다
            try:
                self.brain_q.put_nowait((text, self._turn, direct))
            except queue.Full:
                self.voice.say("밀린 일이 많아요. 잠시 뒤에 다시 말해 주세요.")
        self._show()

    # ── 끼어들기 (desk/bargein.py) ─────────────────────────────────────────
    def _speech_stop(self, text: str) -> bool:
        """"잠깐" · "멈춰" · "그만" 만 한 말 — 멈출 게 있으면 멈추고, 없어도 Claude 로는 넘기지 않음(새 답 없음).
        말하는 중 · Claude 가 답하는 중 · 막 끊은 뒤엔 "많이 멈춰" 처럼 멈춤 말이 든 짧은 말도 멈춤으로 봄"""
        active = self.voice.busy() or self.brain.busy() or not self.brain_q.empty() or self._asking is not None
        loose = active or time.time() - self._barged_at < 4
        if not (is_stop_utterance(text, self.stop_words) if loose else only_stop_words(text, self.stop_words)):
            return False
        if active:
            self._cut(text)
        else:
            self._hush()                             # 멈출 게 안 보여도 — 막 넘어간 말이 있을 수 있어서
            self.board.log("barge", f"(이미 멈춤) {text}")
        return True

    def _cut(self, heard: str, timing: str = "") -> None:
        """끼어들기 — 말하기와 그 차례의 남은 답 · 밀린 말을 모두 버림. 백그라운드 세션은 그대로"""
        cancelled, dropped = self._hush()
        log.info("끼어들기: 말하기 멈춤 (%s)%s%s%s", heard, " · Claude 답 취소" if cancelled else "",
                 f" · 밀린 말 {dropped}개 버림" if dropped else "", timing)
        self.board.log("barge", heard)
        self._show()

    def _probe(self, audio: np.ndarray, spoken: str, final: bool = True, t0: float | None = None) -> None:
        """말하는 도중 들린 소리를 받아써 멈춤 말인지 봄 — 먼저 작은 모델, 마지막 차례(final)에 못 찾으면 큰 모델도.
        t0: 큰 소리가 시작된 시각(로그용).
        받아쓰기가 바쁘면 잠깐(1.5초) 기다리되, 그사이 더 새 소리가 들어오면 이건 버림(새 소리 2초 안에 이 소리도 들어 있음).
        큰 모델은 작은 모델이 짧게 들었을 때만 — 긴 문장은 제 목소리 되먹임이라 큰 모델이 2초씩 붙잡으면 진짜 "잠깐" 을
        건너뛰게 됨(10월 2일 14:18 실제 시험: 여섯 번 중 두 번만 멈춤, 나머지는 "받아쓰기 바쁨" 으로 건너뜀)"""
        with self._probe_mu:
            self._probe_n += 1
            me = self._probe_n
        if not self._stt_lock.acquire(timeout=1.5):
            log.info("끼어들기 받아쓰기 건너뜀 (받아쓰기 바쁨)")
            return
        t0 = time.time() if t0 is None else t0
        tried = []
        try:
            if me != self._probe_n and not final:
                return                               # 더 새 소리가 기다리는 중
            for fast in ((True, False) if final and self.stt.fast_model else (True,)):
                if not fast and me != self._probe_n:   # 더 새 소리가 기다림 — 큰 모델(1.5초)로 붙잡지 말고 그걸 먼저
                    break                              # (15:15 큰 모델 도는 동안 새 소리 둘이 "바쁨" 으로 건너뜀)
                text = self.stt.hear(audio, fast=fast)
                tried.append(f"{'작은' if fast else '큰'} 모델 {text.strip()!r}")
                if not self.voice.busy():
                    return
                if text and has_stop_word(text, self.stop_words, spoken):
                    self._cut(text, f" · 소리 시작부터 {time.time() - t0:.2f}초 ({' → '.join(tried)})")
                    return
                if len(normalize(text)) > 5:         # 멈춤 말("잠깐만요")보다 긴 말 — 큰 모델로 다시 볼 것 없음
                    break
        except Exception as e:  # noqa: BLE001
            log.warning("끼어들기 받아쓰기 실패: %s", e)
            return
        finally:
            self._stt_lock.release()
        log.info("끼어들기 아님: 소리 시작부터 %.2f초 (%s)", time.time() - t0, " → ".join(tried))

    # ── 일꾼 스레드 ────────────────────────────────────────────────────────
    def _stt_worker(self) -> None:
        while not self._stop.is_set():
            cut = self.utt_q.get()
            if isinstance(cut, np.ndarray):
                cut = Cut(cut, True, -1, 0)
            text = self._hear_cut(cut)
            if cut.direct:
                self._talked(cut, text)
                continue
            if text:
                log.info("들음: %s", text)
                if cut.t1:
                    log.info("말 끝에서 %.2f초 (침묵 %.2f · 받아쓰기 %.2f)",
                             cut.tail_s + time.time() - cut.t1, cut.tail_s, self._stt_s)
                if not self._dictate(cut, text):
                    self.handle(text)

    # ── 왼손 주먹 = 비서에게 말하기 (desk/talk.py) ─────────────────────────
    def talk(self, body: str = "") -> str:
        """hand-mouse 가 부름: start(쥠) · hold(쥐고 있음, 1초마다) · end(폄) · cancel"""
        what = (body or "").strip()
        if what == "hold":
            if not self.ptt.active and self.talk_on and self.mode == "awake":
                # 쥐고 있는데 녹음이 없음 — 쥔 사이 deskd 가 다시 켜짐(배포). 상시 듣기가 받던 말부터 이어 녹음
                # (10월 2일 15:16 · 15:18 — 재시작에 녹음이 사라져 폈을 때 "녹음 중 아님", 말은 [음성] 으로 감)
                pre = self.seg.take()
                self.ptt.start(prefix=pre)
                log.info("주먹 녹음 이어 받음 (쥔 사이 다시 켜짐, 앞 %.1f초)", 0 if pre is None else len(pre) / self.sr)
                self.board.log("talk", "왼손 주먹 — 이어 듣는 중")
                self._show("listening")
                return "ok"
            self.ptt.hold()
            return "ok"
        if what == "end":
            return "ok" if self.ptt.end() else "녹음 중 아님"
        if what == "cancel":
            self.ptt.cancel()
            return "ok"
        if what != "start":
            return "start · hold · end · cancel 중 하나"
        if not self.talk_on:
            return "꺼짐"
        if self.mode == "sleep":
            return "자는 중"
        if not self.ptt.start():
            return "이어서 녹음"
        self.last_activity = time.time()
        if self.voice.busy():                       # 말하는 중에 쥐면 말을 끊고 듣기(밀린 답은 그대로)
            self._barged_at = time.time()
            self.voice.stop()
        mac.sound(self.talk_sound)                  # 듣는 중이라는 짧은 소리
        log.info("주먹 말하기 시작")
        self.board.log("talk", "왼손 주먹 — 듣는 중")
        self._show("listening")
        return "ok"

    def _talked(self, cut: Cut, text: str) -> None:
        dur = cut.t1 - cut.t0
        log.info("주먹 말하기 끝 (%.1f초, 받아쓰기 %.2f초): %s", dur, self._stt_s, text or "(빈 말)")
        if not text:
            self.board.log("talk", f"받아쓴 글 없음 ({dur:.1f}초)")
            if dur >= 1.0:                          # 잠깐 쥐었다 편 건 조용히 넘김
                self.voice.say("잘 못 들었어요. 다시 말해 주세요.")
            return
        log.info("들음(주먹): %s", text)
        self.handle(text, direct=True)

    def dial(self, body: str = "") -> str:
        """hand-mouse 지우기 다이얼(왼손 집고 돌리기) — 칸 수만큼 받아쓴 글을 단어째 지우거나(-) 되살림(+)"""
        try:
            steps = int(body.strip() or 0)
        except ValueError:
            return "칸 수가 아님"
        did = self.dictation.dial(steps)
        log.info("지우기 다이얼 %+d칸: %s", steps, did)
        if "글자" in did:
            self.last_activity = time.time()
            self.board.log("dictate", f"(다이얼 {steps:+d}) {did}")
        return did

    def _dictate(self, cut: Cut, text: str) -> bool:
        """주먹을 쥔 채 한 말이고 Claude 앱이 맨 앞이면 그 앱 입력창에 붙여 넣음(엔터 없음). 넣었으면 True — 비서로 안 감"""
        if self.mode != "awake" or not self.dictation.wants(cut.t0, cut.t1):
            return False
        self.last_activity = time.time()
        if self.dictation.put(text):
            log.info("받아쓰기 넣음 → Claude 앱: %s", text)
            self.board.log("dictate", text)
            mac.sound("Pop")
        else:
            log.warning("받아쓰기 못 넣음(손쉬운 사용 권한 없음): %s", text)
            self.board.log("error", f"받아쓰기 못 넣음 — deskd 에 손쉬운 사용 권한 필요: {text}")
            if not self.dictation.warned:
                self.dictation.warned = True
                can_post_keys(ask=True)
                self.voice.say("입력창에 넣으려면 손쉬운 사용 권한이 필요해요.")
        return True

    def _answering(self) -> bool:
        """비서가 방금(30초 안) 물었음 — "응" · "네" 같은 짧은 대답도 버리지 않음"""
        q = (self.voice.last_text or "").rstrip().rstrip(".")
        return time.time() - getattr(self.voice, "said_at", 0.0) < 30 and (q.endswith("?") or q.endswith("까요"))

    def _hear_cut(self, cut: Cut) -> str:
        """조각을 받아씀. 잠정 조각은 끝난 말로 보일 때만 글을 돌려주고 구간을 닫음(말 끝 기다리기, desk/endpoint.py)"""
        audio = cut.audio
        self._stt_s = 0.0
        if cut.final:
            self._finals.discard(cut.seq)
            held = self._held.pop(cut.seq, None)
            took = self._taken.pop(cut.seq, 0)
            if held and not took and cut.voiced <= held[0]:   # 기다리는 동안 말이 없었음 — 받아쓴 글 그대로
                return held[1]
            if took:                                   # 앞부분은 잠정 조각으로 이미 답함 — 뒤에 붙은 말만
                audio = audio[took * self.seg.n:]
                if len(audio) / self.sr - self.seg.hold_silence_s < self.seg.min_utt_s:
                    return ""
        elif cut.seq in self._finals:                  # 확정 조각이 벌써 줄에 있음 — 그걸로 받아씀
            return ""
        elif cut.seq in self._taken:                   # 받아쓰는 사이 말이 이어져 같은 구간에서 또 나온 잠정 조각 —
            return ""                                  # 앞은 이미 답했고, 뒤는 새 구간 번호로 다시 나옴
        t = time.time()
        try:
            with self._stt_lock:
                direct = cut.direct or self._answering()
                text = self.stt.transcribe(audio, direct=True) if direct else self.stt.transcribe(audio)
                raw = getattr(self.stt, "last_raw", "").strip()
            self._stt_s = time.time() - t
        except Exception as e:  # noqa: BLE001
            log.exception("받아쓰기 실패")
            self.board.log("error", f"받아쓰기: {e}")
            return ""
        if cut.seq == self._echo_seq[0] and not cut.direct and cut.voiced <= self._echo_seq[2] + 15:   # 마이크 지연 · 되울림 0.45초
            log.info("겹친 소리가 비서 말과 함께 그침 — 제 목소리로 보고 버림: %s", raw or "(빈 말)")
            return ""                                  # 끝난 뒤로 말소리가 없으면 되먹임(끼어들기 감지는 제 목소리에도 자주 걸림)
        if not text and raw:
            log.info("받아쓰기 거름 (환각 · 짧은 말로 봄, %.1f초): %s", len(audio) / self.sr, raw)
        if text and cut.seq == self._echo_seq[0] and not cut.direct:
            cut_text = strip_echo(text, self._echo_seq[1])
            if cut_text != text:
                log.info("겹친 말 앞의 비서 말 끝을 뗌: %s → %s", text, cut_text or "(없음)")
                text = cut_text
        if cut.final or not text:
            return text
        if looks_unfinished(text):
            log.info("말이 이어질 듯 — 더 기다림: %s", text)
            if len(self._held) > 32:
                self._held.clear()
            self._held[cut.seq] = (cut.frames, text)
            return ""
        self.seg.commit(cut.seq, cut.frames)
        if len(self._taken) > 32:
            self._taken.clear()
        self._taken[cut.seq] = cut.frames
        return text

    def _brain_worker(self) -> None:
        while not self._stop.is_set():
            text, turn, direct = self.brain_q.get()
            if turn != self._turn:                   # 받은 뒤에 "멈춰" — 답하지 않음
                continue
            self._asking = turn
            self._show("thinking")
            try:
                spoken, full = self.brain.ask(text, direct=direct)
            finally:
                self._asking = None
            if turn != self._turn:
                log.info("멈춘 뒤 온 답 버림: %s", text[:40])
                self.board.log("barge", f"(멈춘 뒤 온 답 버림) {text}")
            elif spoken is None and direct:          # 주먹 쥐고 한 말은 무시하지 않음 — 그래도 무시했으면 되묻기
                self.board.log("ignore", f"(Claude 가 주먹 말을 무시함) {text}")
                self.voice.say("무슨 말인지 잘 모르겠어요. 다시 말해 주세요.")
            elif spoken is None:
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

    def _on_audio(self, x: np.ndarray, side: list[np.ndarray] | None = None) -> None:
        """side: 박수 · 끼어들기를 듣는 마이크가 따로면(side_device) 그 사이 들어온 조각들. 없으면 x 로 둘 다 봄."""
        ears = [x] if side is None else side
        bursts = [n for a in ears for n in self.clap.feed(a)]
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
            if self._feed_talk(x):                   # 왼손 주먹으로 녹음 중 — 상시 듣기 자르개에는 안 넣음
                return
            # 스피커에서 소리가 나는 동안(+되울림 echo_s)만 말하는 중 — 합성 기다림 · 끝난 뒤 꼬리에는 듣기
            speaking = self.voice.sounding(self.echo_s) and time.time() - self._barged_at > 1.0   # 끊은 직후는 아님
            lead = (self.barge.voice_s() if self._deaf and not speaking and self.barge_on
                    and time.time() - self._barged_at > 1.5 else 0.0)   # 멈춤 말로 끊었으면 겹친 건 그 멈춤 말 — 이어 듣지 않음
            if self.barge_on:
                for a in ears:
                    heard = self.barge.feed(a, speaking)
                    if heard is not None:
                        threading.Thread(target=self._probe, daemon=True,
                                         args=(heard, self.voice.last_text, self.barge.final,
                                               time.time() - self.barge.after_s)).start()
            if speaking:
                if not self._deaf:                   # 막 말하기 시작 — 주인이 하던 말은 버리지 말고 여기까지로 넘김
                    self._deaf = True
                    self._spk.clear()
                    cut = self.seg.flush()
                    if cut is not None:
                        log.info("말하기 시작 — 듣던 말 %.1f초를 여기까지로 넘김", len(cut.audio) / self.sr)
                        self._queue_cut(cut)
                self._spk.append(x)
                while sum(len(a) for a in self._spk) - len(self._spk[0]) > 2 * self.sr:
                    self._spk.popleft()
                self.seg.pause()                     # 스피커에서 나가는 제 목소리를 듣지 않게(멈춤 말은 위에서 따로)
                return
            self.seg.resume()
            feed = x
            if self._deaf:
                self._deaf = False
                if lead > 0 and self._spk:           # 비서 말 끝에 주인 목소리가 겹쳐 있었음 — 그 앞부분부터 듣기
                    prev = np.concatenate(self._spk)
                    prev = prev[-int(min(lead + 0.3, 2.0) * self.sr):]
                    feed = np.concatenate([prev, x])
                    log.info("말하기 끝에 겹친 말 — 앞 %.1f초부터 이어 들음", len(prev) / self.sr)
                    self._echo_seq = (self.seg.seq + 1, self.voice.last_text, len(prev) // self.seg.n)
                self._spk.clear()
            for cut in self.seg.feed_cuts(feed):
                self._queue_cut(cut)
        if self.mode == "awake" and time.time() - self.last_activity > self.cfg["idle_minutes"] * 60 \
                and not self.voice.busy() and not self.brain.busy() and not self.seg.in_speech:
            threading.Thread(target=self.sleep, args=("idle",), daemon=True).start()
            self.last_activity = time.time()

    def _queue_cut(self, cut: Cut) -> None:
        cut.t1 = time.time()
        cut.t0 = cut.t1 - len(cut.audio) / self.sr
        if cut.final:
            self._finals.add(cut.seq)
        try:
            self.utt_q.put_nowait(cut)
        except queue.Full:
            log.warning("받아쓰기 줄이 차서 들은 말을 버림 (%.1f초)", len(cut.audio) / self.sr)
            self._finals.discard(cut.seq)

    def _feed_talk(self, x: np.ndarray) -> bool:
        """주먹 녹음에 소리를 넣음. 녹음 중(또는 방금 끝남)이면 True. 끝났으면 받아쓰기 줄에 넣음"""
        was = self.ptt.active
        got = self.ptt.feed(x)
        if got is None:
            return was
        audio, t0, t1, why = got
        log.info("주먹 녹음 끝 (%s, %.1f초)", why, t1 - t0)
        self.seg.reset()                             # 녹음 중 자르개에 남은 반쪽 말은 버림
        try:
            self.utt_q.put_nowait(Cut(audio, True, -1, 0, t0, t1, direct=True))
        except queue.Full:
            log.warning("받아쓰기 줄이 차서 주먹 말을 버림")
        return True

    def run(self) -> None:
        import sounddevice as sd
        mac.keep_system_awake()
        serve(self.board, {"wake": self.wake, "sleep": self.sleep, "brief": self.say_brief, "mute": self.mute,
                           "unmute": self.unmute, "stop": self.stop,
                           "say": self.remote_say, "show": self.show,
                           "enroll": self.enroll, "face": self.face_test,
                           "tts": self.tts_view, "tts_test": self.tts_test, "tts_save": self.tts_save,
                           "model": self.model_set, "dial": self.dial, "talk": self.talk},
              port=self.cfg["dashboard"]["port"])
        watch_agents(self.board)
        threading.Thread(target=self._stt_worker, daemon=True).start()
        threading.Thread(target=self._brain_worker, daemon=True).start()
        threading.Thread(target=self._warmup, daemon=True).start()

        def cb(indata, frames, t, status):  # noqa: ARG001
            try:
                self.audio_q.put_nowait(indata[:, 0].copy())
            except queue.Full:
                pass

        def side_cb(indata, frames, t, status):  # noqa: ARG001
            try:
                self.side_q.put_nowait(indata[:, 0].copy())
            except queue.Full:
                pass

        log.info("deskd 시작 · 박수 %d번(밤 %d번)", self.cfg["wake"]["claps"], self.cfg["wake"]["night_claps"])
        threading.Thread(target=self._watch_devices, daemon=True).start()
        self._show()
        last_show = last_display = 0.0
        clock = (time.time(), time.monotonic())
        while not self._stop.is_set():
            mic, side_mic = self._use_devices(self._devs_want or self._pick_devices())
            opened = self._mic_heard = time.time()
            # 권한을 나중에 허용하면 이미 열린 스트림엔 계속 0 이 옵니다 — 막혀 있는 동안은 20초마다 다시 엽니다
            # 장치를 빼거나 꽂아 고를 장치가 바뀌어도(_watch_devices) 닫고 새로 엽니다
            with contextlib.ExitStack() as streams:
                streams.enter_context(sd.InputStream(samplerate=self.sr, channels=1, dtype="float32",
                                                     blocksize=int(self.sr * 0.03), device=mic or None, callback=cb))
                if side_mic != mic:
                    with self.side_q.mutex:
                        self.side_q.queue.clear()
                    streams.enter_context(sd.InputStream(samplerate=self.sr, channels=1, dtype="float32",
                                                         blocksize=int(self.sr * 0.03), device=side_mic or None,
                                                         callback=side_cb))
                while not self._stop.is_set():
                    try:
                        x = self.audio_q.get(timeout=1)
                    except queue.Empty:
                        x = None
                    clock = self._check_system_wake(*clock)
                    if self._devs_want is not None and self._devs_want != self._devs:
                        break
                    side = None
                    if side_mic != mic:
                        side = []
                        while not self.side_q.empty():
                            side.append(self.side_q.get_nowait())
                    # 권한이 없으면 모든 마이크가 0 — 스피커폰은 조용한 방에서 잡음 제거로 몇 초씩 0 을 보내므로 둘 중 하나만 들려도 됨
                    self._mic_check(x if x is not None and np.any(x) or not side else np.concatenate(side))
                    if self.mic_blocked and time.time() - opened > 20:
                        break
                    if x is None:
                        continue
                    self._on_audio(x, side)
                    if time.time() - last_show > 0.5:        # 말하기가 끝났는지 등 — 상태판을 따라가게
                        self._show()
                        last_show = time.time()
                    if time.time() - last_display > 2:       # 키보드로 켠 화면 · 저절로 꺼진 화면 따라가기
                        self._watch_display()
                        last_display = time.time()

    # ── 소리 장치 (desk/devices.py) ───────────────────────────────────────
    def _pick_devices(self) -> tuple[str, str, str]:
        """[audio] device · side_device · [tts] device 목록 중 지금 꽂힌 첫 장치 (마이크, 박수 · 끼어들기 마이크, 스피커).

        스피커폰(Jabra Speak2)은 듣기엔 좋지만 박수 · 끼어들기엔 못 씁니다(10월 2일 녹음) — 잡음 제거가 말 첫소리를 박수처럼
        날카롭게 만들고(말 90초에 헛박수 8번, Brio 0번), 제가 말하는 동안엔 마이크를 아예 닫습니다(그 위로 한 "멈춰" 가 0).
        그래서 박수와 끼어들기는 side_device(Brio)로 듣습니다."""
        a = self.cfg["audio"]
        have_in, have_out = devices.present("input"), devices.present("output")
        mic = devices.pick(a.get("device"), "input", have_in)
        side = devices.pick(a.get("side_device"), "input", have_in) if devices.names(a.get("side_device")) else mic
        return mic, side, devices.pick(self.cfg["tts"].get("device"), "output", have_out)

    def _watch_devices(self) -> None:
        """3초마다 고를 장치를 다시 봅니다 — 스피커폰을 빼면 Brio · 맥 미니 스피커로, 다시 꽂으면 스피커폰으로."""
        while not self._stop.wait(3):
            want = self._pick_devices()
            if self._devs is not None and want != self._devs:
                self._devs_want = want

    def _use_devices(self, want: tuple[str, str, str]) -> tuple[str, str]:
        """스트림을 열기 전 — 장치가 바뀌었으면 PortAudio 목록을 새로 읽고(꽂은 장치를 알게) 목소리도 옮깁니다."""
        old, self._devs_want = self._devs, None
        if want != old:
            if old is not None:
                if want[2] != old[2]:
                    self.voice.stop()                 # 뺀 스피커로 나가던 말은 끊음
                until = time.time() + 15
                while self.voice.busy() and time.time() < until:   # 말하는 스트림이 열려 있으면 다시 못 띄움
                    time.sleep(0.1)
                devices.refresh()
                self.clap.reset()
                self.seg.reset()
                self.barge.forget()
            self.voice.device = want[2]
            line = f"마이크 {want[0] or '기본'} · 박수 · 끼어들기 {want[1] or '기본'} · 스피커 {want[2] or '기본'}"
            log.info("소리 장치: %s", line)
            if old is not None:
                self.board.log("mic", f"장치 바뀜 — {line}")
        self._devs = want
        return want[0], want[1]

    def _check_system_wake(self, wall: float, mono: float, now_wall: float | None = None,
                           now_mono: float | None = None) -> tuple[float, float]:
        """맥이 잠들었다 깨면 벽시계는 가는데 monotonic 은 멈춰 있어 둘의 차이가 벌어집니다 — 그걸로 '잠자기에서 깨어남'을
        알아챕니다(맥은 보통 안 자지만, 메뉴에서 재우면 잡니다). 깨어 보니 화면이 켜져 있고 듣는 중이면 카메라를 다시 켬
        (자는 중이면 _watch_display 가 화면 켜짐을 보고 함). 돌려주는 값을 다음 호출에 넣습니다."""
        now_wall = time.time() if now_wall is None else now_wall
        now_mono = time.monotonic() if now_mono is None else now_mono
        gap = (now_wall - wall) - (now_mono - mono)
        if gap > 5:
            log.info("잠자기에서 깨어남 (%.0f초 잤음)", gap)
            self.board.log("wake", f"잠자기에서 깨어남 ({gap:.0f}초)")
            if self.mode != "sleep" and mac.displays_asleep() is not True:
                self._cameras_on("잠자기에서 깨어남")
        return now_wall, now_mono

    def _watch_display(self) -> None:
        """박수 말고 다른 걸로 화면이 켜지거나 꺼졌을 때 상태를 맞춥니다.
        키보드 · 마우스 · 잠자기에서 깸으로 화면이 켜지면 → 조용히 '듣는 중'(인사 · 브리핑 없이 딩만) · 카메라 켬
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
            self._cameras_on("키보드 · 마우스")
            self._show()
        elif self.mode in ("awake", "muted") and asleep and not self.voice.busy():
            log.info("화면이 꺼짐 → 자는 중")
            self._changed_at = time.time()
            self.brain.cancel()
            self.mode = "sleep"
            self.seg.reset()
            self.clap.reset()
            mac.cameras_off(self.cfg["camera_off"])
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
