"""브리핑 — 켜질 때 들려주는 현재 상태.

**브리핑은 Claude 를 거치지 않습니다.** 모으는 건 명령 몇 개(gh · adb · xcrun · 날씨)이고 문장은 틀에 넣어 만듭니다.
그래서 빠르고(2~3초), 사용량이 들지 않고, 숫자를 지어내지 않습니다. 더 알고 싶으면 그다음에 말로 물으면 Claude 가 답합니다.

공장 상황판 이슈 본문의 형식은 factory/seed/CLAUDE.md §5 — 「단계:」 「주인 할 일:」 줄을 읽습니다.
"""
from __future__ import annotations

import datetime as dt
import json
import re
import shutil
import subprocess
from concurrent.futures import ThreadPoolExecutor

WEEK = "월화수목금토일"


def sh(cmd: list[str], timeout: float = 8) -> str:
    if not shutil.which(cmd[0]):
        return ""
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout).stdout.strip()
    except Exception:
        return ""


# ── 모으기 (하나가 실패해도 나머지는 나감) ─────────────────────────────────────
def weather(city: str) -> str:
    return weather_ko(sh(["curl", "-s", "-m", "4", f"https://wttr.in/{city}?format=%C+%t&lang=ko"]))


# wttr.in 은 lang=ko 여도 날씨 이름을 영어로 줍니다("Overcast") — 소리 내어 읽게 우리말로. 앞에 있는 낱말이 먼저.
_SKY = [("thunder", "천둥 번개"), ("blizzard", "눈보라"), ("sleet", "진눈깨비"), ("snow", "눈"),
        ("drizzle", "이슬비"), ("shower", "소나기"), ("rain", "비"), ("fog", "안개"), ("mist", "옅은 안개"),
        ("haze", "실안개"), ("overcast", "흐림"), ("partly", "구름 조금"), ("cloud", "구름 많음"),
        ("sunny", "맑음"), ("clear", "맑음")]


def sky_ko(cond: str) -> str:
    low = cond.strip().lower()
    ko = next((k for w, k in _SKY if w in low), "")
    if not ko:
        return cond.strip()                      # 이미 우리말이거나 모르는 말
    if ko in ("비", "눈", "소나기", "이슬비"):
        ko = ("곳에 따라 " if any(w in low for w in ("patchy", "possible", "nearby")) else
              "강한 " if any(w in low for w in ("heavy", "torrential")) else
              "약한 " if "light" in low else "") + ko
    return ko


def weather_ko(raw: str) -> str:
    """"Overcast  +22°C" → "흐림 +22°C" """
    m = re.match(r"(.*?)\s*([+-]?\d+\s*°C)\s*$", raw or "")
    return f"{sky_ko(m.group(1))} {m.group(2)}".strip() if m else (raw or "")


def factory(repo: str, ship_repo: str) -> dict:
    d: dict = {"apps": [], "owner_todo": [], "waiting_approvals": 0, "red_main": 0, "ok": False}
    if not repo:
        return d
    raw = sh(["gh", "issue", "list", "-R", repo, "-l", "status", "--state", "open", "--json", "title,body", "-L", "30"])
    if raw:
        d["ok"] = True
        for it in json.loads(raw):
            name = re.sub(r"^\[상황판\]\s*", "", it.get("title", "")).strip()
            body = it.get("body", "")
            stage = _line(body, "단계")
            todo = _line(body, "주인 할 일")
            d["apps"].append({"name": name, "stage": stage})
            if todo and todo not in ("없음", "-"):
                d["owner_todo"].append(f"{name}: {todo}")
    runs = sh(["gh", "run", "list", "-R", repo, "--branch", "main", "-L", "10", "--json", "conclusion,workflowName"])
    if runs:
        seen = {}
        for r in json.loads(runs):                     # 워크플로마다 가장 최근 것만
            seen.setdefault(r.get("workflowName"), r.get("conclusion"))
        d["red_main"] = sum(1 for c in seen.values() if c == "failure")
    if ship_repo:
        w = sh(["gh", "api", f"repos/{ship_repo}/actions/runs?status=waiting", "-q", ".total_count"])
        d["waiting_approvals"] = int(w) if w.isdigit() else 0
    return d


def _line(body: str, key: str) -> str:
    m = re.search(rf"^\s*{key}\s*[:：]\s*(.+)$", body or "", flags=re.M)
    if not m:
        return ""
    v = m.group(1).strip()
    return re.split(r"\s{2,}마지막 갱신", v)[0].strip()


def lab() -> dict:
    adb = sh(["adb", "devices"])
    android = sum(1 for l in adb.splitlines()[1:] if l.strip().endswith("\tdevice"))
    ios_raw = sh(["xcrun", "devicectl", "list", "devices"], timeout=10)
    iphone = any("iPhone" in l and ("connected" in l.lower() or "available" in l.lower()) for l in ios_raw.splitlines())
    runner = bool(sh(["pgrep", "-f", "Runner.Listener"]))
    disk = sh(["df", "-h", "/"]).splitlines()
    free = disk[1].split()[3] if len(disk) > 1 and len(disk[1].split()) > 3 else ""
    return {"android": android, "iphone": iphone, "runner": runner, "disk_free": free}


def gather(cfg: dict) -> dict:
    b = cfg.get("briefing", {})
    with ThreadPoolExecutor(3) as ex:
        fw = ex.submit(weather, b.get("city", "Seoul"))
        ff = ex.submit(factory, b.get("repo", ""), b.get("ship_repo", ""))
        fl = ex.submit(lab)
        return {"now": dt.datetime.now().isoformat(timespec="minutes"), "weather": fw.result(),
                "factory": ff.result(), "lab": fl.result()}


# ── 문장 만들기 ──────────────────────────────────────────────────────────────
def greeting(now: dt.datetime, name: str = "") -> str:
    h = now.hour
    g = ("늦은 시간이네요" if h < 5 else "좋은 아침이에요" if h < 11 else "좋은 오후예요" if h < 17
         else "좋은 저녁이에요" if h < 22 else "늦은 시간이네요")
    return f"{name + '님, ' if name else ''}{g}."


def compose(data: dict, now: dt.datetime | None = None, owner: str = "") -> str:
    now = now or dt.datetime.now()
    ampm = "오전" if now.hour < 12 else "오후"
    h12 = now.hour % 12 or 12
    parts = [greeting(now, owner), f"{now.month}월 {now.day}일 {WEEK[now.weekday()]}요일, {ampm} {h12}시 {now.minute}분입니다."]
    if data.get("weather"):
        w = re.sub(r"\+?(-?\d+)\s*°C", r"\1도", data["weather"])      # "+18°C" → "18도" (소리 내어 읽기 좋게)
        parts.append(f"바깥은 {w}.")
    f = data.get("factory", {})
    if f.get("ok"):
        apps = f.get("apps", [])
        if apps:
            head = ", ".join(f"{_topic(a['name'])} {_short_stage(a['stage'])} 단계" if _short_stage(a['stage'])
                             else a['name'] for a in apps[:3])
            more = f" 외 {len(apps) - 3}개" if len(apps) > 3 else ""
            parts.append(f"공장에서 앱 {len(apps)}개가 돌고 있어요. {head}{more}.")
        else:
            parts.append("공장에 진행 중인 앱은 없어요.")
        todo = f.get("owner_todo", [])
        if f.get("waiting_approvals"):
            parts.append(f"출시 승인 대기가 {f['waiting_approvals']}건 있어요.")
        if todo:
            parts.append(f"직접 하실 일이 {len(todo)}건 — {todo[0]}.")
        elif not f.get("waiting_approvals"):
            parts.append("직접 하실 일은 없어요.")
        if f.get("red_main"):
            parts.append(f"실패한 빌드가 {f['red_main']}개 있는데, 담당 세션이 보고 있어요.")
    else:
        parts.append("공장 상황은 지금 못 읽었어요.")
    l = data.get("lab", {})
    bad = []
    if not l.get("runner"):
        bad.append("시험 러너 꺼짐")
    if not l.get("iphone"):
        bad.append("아이폰 연결 안 됨")
    if bad:
        parts.append("실험실 확인이 필요해요 — " + ", ".join(bad) + ".")
    else:
        parts.append(f"실험실은 정상이에요. 안드로이드 {l.get('android', 0)}대, 아이폰 연결됨.")
    return " ".join(parts)


def _short_stage(stage: str) -> str:
    m = re.match(r"(S\d)\s*([^\s(]+)?", stage or "")
    if not m:
        return stage[:12] if stage else ""
    return (m.group(2) or m.group(1)).strip()


def _topic(word: str) -> str:
    """은/는 — 받침이 있으면 은"""
    if not word:
        return word
    ch = word[-1]
    if "가" <= ch <= "힣":
        return word + ("은" if (ord(ch) - 0xAC00) % 28 else "는")
    return word + "은(는)"
