"""Claude 사용량 — 5시간 창 · 주간 한도. 책상 화면 위쪽 「Claude 사용량」 칸.

숫자는 Claude Code 가 상태줄 명령(statusLine)에 stdin 으로 넘기는 JSON 의 rate_limits 에서만 가져옵니다
(Pro · Max 구독, 그 세션이 첫 응답을 받은 뒤부터 들어 있음). 이 모듈을 상태줄 명령으로 걸어 두면
(`python -m desk.usage statusline`, ~/.claude/settings.json statusLine) 넘어올 때마다
rate_limits 의 숫자만 USAGE_FILE 에 적고 짧은 상태줄 한 줄을 찍습니다. 다른 값(세션 · 경로 · 토큰 등)은 적지 않습니다.

책상(watch_usage)은 그 파일만 읽습니다. 짐작은 하지 않습니다:
  - 파일이 없거나 값이 없으면 「모름」
  - 초기화 시각이 지났으면 그 창의 지금 값은 모르는 것 → 「모름 (초기화 지남)」
  - 값이 오래됐으면(마지막으로 넘어온 지 STALE_S 넘음) 몇 분 전 값인지 함께 보임
"""
from __future__ import annotations

import json
import os
import sys
import threading
import time
from datetime import datetime

USAGE_FILE = os.path.expanduser("~/.cache/desk/claude-usage.json")
STALE_S = 15 * 60   # 이보다 오래된 값이면 「N분 전 값」 을 붙임
WINDOWS = (("five_hour", "5시간"), ("seven_day", "주간"))


def _epoch(v) -> float | None:
    """resets_at — 유닉스 초(또는 ms) · ISO 글 모두 받음. 못 읽으면 None."""
    if isinstance(v, bool):
        return None
    if isinstance(v, (int, float)):
        return float(v) / 1000 if v > 1e12 else float(v)
    if isinstance(v, str) and v:
        try:
            return float(v) if v.replace(".", "", 1).isdigit() else datetime.fromisoformat(v.replace("Z", "+00:00")).timestamp()
        except ValueError:
            return None
    return None


def _pct(v) -> float | None:
    if isinstance(v, bool) or not isinstance(v, (int, float)):
        return None
    return float(v) if 0 <= v <= 100 else None


def pick(payload) -> dict:
    """상태줄 JSON 에서 rate_limits 의 숫자만 — {"five_hour": {"used": %, "resets_at": 초}, ...}. 없으면 {}."""
    rl = payload.get("rate_limits") if isinstance(payload, dict) else None
    out = {}
    if not isinstance(rl, dict):
        return out
    for key, _ in WINDOWS:
        w = rl.get(key)
        if not isinstance(w, dict):
            continue
        used = _pct(w.get("used_percentage", w.get("utilization")))
        if used is not None:
            out[key] = {"used": used, "resets_at": _epoch(w.get("resets_at"))}
    return out


def record(payload, path: str = USAGE_FILE, now: float | None = None) -> dict:
    """넘어온 값이 있으면 path 에 덮어씀(창마다 따로 — 이번에 빠진 창은 전에 적힌 값을 그 시각과 함께 둠)."""
    got = pick(payload)
    if not got:
        return {}
    now = time.time() if now is None else now
    try:
        with open(path, encoding="utf-8") as f:
            old = json.load(f)
        if not isinstance(old, dict):
            old = {}
    except (OSError, ValueError):
        old = {}
    for key in got:
        old[key] = {**got[key], "t": now}
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = f"{path}.{os.getpid()}.tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(old, f)
    os.replace(tmp, path)
    return got


def _left(sec: float) -> str:
    m = max(0, int(sec // 60))
    if m < 60:
        return f"{m}분"
    if m < 1440:
        return f"{m // 60}시간 {m % 60}분"
    return f"{m // 1440}일 {m % 1440 // 60}시간"


def view(path: str = USAGE_FILE, now: float | None = None) -> list[dict]:
    """화면에 띄울 칸들 — [{"label", "known", "used", "left", "resets", "note"}]. 모르면 known=False."""
    now = time.time() if now is None else now
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        if not isinstance(data, dict):
            data = {}
    except (OSError, ValueError):
        data = {}
    rows = []
    for key, label in WINDOWS:
        w = data.get(key)
        row = {"key": key, "label": label, "known": False, "used": None, "left": None, "resets": "", "note": ""}
        used = _pct(w.get("used")) if isinstance(w, dict) else None
        if used is None:
            rows.append(row)
            continue
        reset = _epoch(w.get("resets_at"))
        if reset is not None and reset <= now:
            row["note"] = "초기화 지남"
            rows.append(row)
            continue
        row.update(known=True, used=round(used), left=round(100 - used),
                   resets=_left(reset - now) if reset is not None else "")
        age = now - float(w.get("t") or 0)
        if age > STALE_S:
            row["note"] = f"{_left(age)} 전 값"
        rows.append(row)
    return rows


def watch_usage(board, every_s: float = 20, path: str = USAGE_FILE) -> threading.Thread:
    """몇십 초마다 파일을 읽어 상태판에 (남은 시간이 바뀌므로 주기적으로). 바뀐 게 없으면 Board.set 이 안 보냄."""
    def loop():
        while True:
            try:
                board.set(usage=view(path))
            except Exception:  # noqa: BLE001 — 화면 칸 하나 때문에 데몬 스레드가 죽지 않게
                pass
            time.sleep(every_s)
    t = threading.Thread(target=loop, daemon=True, name="usage")
    t.start()
    return t


def statusline(stdin=sys.stdin, stdout=sys.stdout, path: str = USAGE_FILE) -> None:
    """상태줄 명령 — rate_limits 숫자만 기록하고 「모델 · 5시간 N% · 주간 N%」 한 줄을 찍음."""
    try:
        payload = json.load(stdin)
    except ValueError:
        payload = {}
    try:
        record(payload, path)
    except OSError:
        pass
    model = ""
    if isinstance(payload, dict) and isinstance(payload.get("model"), dict):
        model = str(payload["model"].get("display_name") or "")
    parts = [model] if model else []
    for r in view(path):
        if r["known"]:
            parts.append(f"{r['label']} {r['used']}%" + (f" ({r['resets']} 뒤 초기화)" if r["resets"] and r["key"] == "five_hour" else ""))
    print(" · ".join(parts), file=stdout)


if __name__ == "__main__":
    if sys.argv[1:] == ["statusline"]:
        statusline()
    else:
        print(json.dumps(view(), ensure_ascii=False, indent=1))
