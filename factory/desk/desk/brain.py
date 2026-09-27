"""Claude 와 이어지는 곳 — 로컬 명령이 아닌 말은 전부 여기로.

맥 미니의 Claude Code 를 `claude -p` 로 부르고, 하루 동안은 같은 대화를 `--resume` 으로 이어 갑니다
(어제 한 말을 오늘 기억할 필요는 없고, 대화가 길어지면 느려지므로 날마다 새로).
구독 로그인으로 돌고(API 열쇠 불필요), 작업 폴더의 CLAUDE.md · 훅 · 권한 규칙이 그대로 적용됩니다.
권한 창이 뜨면 아무도 못 누르므로 `--permission-mode auto --permission-prompts none`.
"""
from __future__ import annotations

import datetime as dt
import json
import os
import shutil
import subprocess
import threading
from pathlib import Path

IGNORE = "<IGNORE>"


class Brain:
    def __init__(self, workdir: str, model: str = "", timeout_s: int = 180,
                 state_file: str = "~/.local/state/desk/session.json"):
        self.workdir = os.path.expanduser(workdir)
        self.model, self.timeout_s = model, timeout_s
        self.state_file = Path(os.path.expanduser(state_file))
        self.claude = shutil.which("claude") or os.path.expanduser("~/.local/bin/claude")
        self._p: subprocess.Popen | None = None
        self._lock = threading.Lock()

    # 날마다 새 대화
    def _sid(self) -> str | None:
        try:
            d = json.loads(self.state_file.read_text())
            return d["session_id"] if d.get("date") == dt.date.today().isoformat() else None
        except Exception:
            return None

    def _save_sid(self, sid: str) -> None:
        self.state_file.parent.mkdir(parents=True, exist_ok=True)
        self.state_file.write_text(json.dumps({"date": dt.date.today().isoformat(), "session_id": sid}))

    def busy(self) -> bool:
        with self._lock:
            return self._p is not None and self._p.poll() is None

    def cancel(self) -> bool:
        with self._lock:
            if self._p and self._p.poll() is None:
                self._p.send_signal(2)      # SIGINT — 하던 턴을 정리하고 끝냄
                return True
        return False

    def ask(self, heard: str) -> tuple[str | None, str]:
        """(말할 글 또는 None=무시, 화면에 보일 전체 글)"""
        now = dt.datetime.now().strftime("%H:%M")
        prompt = f"[음성 {now}] {heard}"
        cmd = [self.claude, "-p", prompt, "--output-format", "json",
               "--permission-mode", "auto", "--permission-prompts", "none"]
        if self.model:
            cmd += ["--model", self.model]
        sid = self._sid()
        if sid:
            cmd += ["--resume", sid]
        with self._lock:
            self._p = subprocess.Popen(cmd, cwd=self.workdir, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                       text=True)
            p = self._p
        try:
            out, err = p.communicate(timeout=self.timeout_s)
        except subprocess.TimeoutExpired:
            p.send_signal(2)
            try:
                p.communicate(timeout=10)
            except Exception:
                p.kill()
            return "시간이 오래 걸려서 멈췄어요. 백그라운드 작업으로 다시 시켜 주세요.", "(시간 초과)"
        finally:
            with self._lock:
                self._p = None
        try:
            r = json.loads(out.strip().splitlines()[-1])
        except Exception:
            tail = (err or out or "").strip()[-400:]
            return "Claude 가 응답하지 않아요. 로그인이나 사용량 한도를 확인해 주세요.", tail
        if r.get("session_id"):
            self._save_sid(r["session_id"])
        text = (r.get("result") or "").strip()
        if r.get("is_error"):
            return "Claude 쪽에서 오류가 났어요.", text
        if text.startswith(IGNORE) or not text:
            return None, text
        return text, text
