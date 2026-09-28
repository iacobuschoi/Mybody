"""비서 폴더의 .claude/settings.json 을 설치 때 덮어쓰지 않고 합칩니다.

사람이(또는 말로 시켜서) 고친 권한 규칙은 그대로 두고, 지난 설치 뒤 공장 기본값(seed)에서 새로 생기거나
빠진 것만 반영합니다(3방향 합치기). 지난 설치의 seed 는 옆의 seed-settings.json 에 남겨 비교합니다.
공장 훅(guard.js)은 비서의 안전장치라, 등록이 빠져 있으면 다시 넣습니다.

    python -m desk.settings_merge <seed settings.json> <비서 settings.json>
"""
from __future__ import annotations

import copy
import json
import sys
from pathlib import Path

KINDS = ("allow", "deny", "ask")


def _merge_list(mine: list, seed: list, last: list) -> list:
    out = [x for x in mine if not (x in last and x not in seed)]      # 공장이 뺀 것은 뺌
    out += [x for x in seed if x not in last and x not in out]         # 공장이 새로 넣은 것만 더함
    return out


def merge(mine: dict, seed: dict, last: dict | None) -> dict:
    last = seed if last is None else last          # 처음이면 지금 seed 가 기준 — 사람이 고친 것을 건드리지 않음
    out = copy.deepcopy(mine)
    perms = out.get("permissions", {})
    for kind in KINDS:
        s, l = seed.get("permissions", {}).get(kind, []), last.get("permissions", {}).get(kind, [])
        merged = _merge_list(perms.get(kind, []), s, l)
        if merged or kind in perms:
            out.setdefault("permissions", {})[kind] = merged
    events = set(seed.get("hooks", {})) | set(last.get("hooks", {})) | set(out.get("hooks", {}))
    for ev in sorted(events):
        merged = _merge_list(out.get("hooks", {}).get(ev, []), seed.get("hooks", {}).get(ev, []),
                             last.get("hooks", {}).get(ev, []))
        if merged or ev in out.get("hooks", {}):
            out.setdefault("hooks", {})[ev] = merged
    if "guard.js" in json.dumps(seed.get("hooks", {})) and "guard.js" not in json.dumps(out.get("hooks", {})):
        for ev, groups in seed["hooks"].items():                        # 안전장치가 빠졌으면 다시
            out.setdefault("hooks", {}).setdefault(ev, []).extend(copy.deepcopy(groups))
    return out


def main(seed_path: str, mine_path: str) -> str:
    seed_p, mine_p = Path(seed_path), Path(mine_path)
    last_p = mine_p.with_name("seed-settings.json")
    seed = json.loads(seed_p.read_text(encoding="utf-8"))
    if not mine_p.exists():
        mine_p.parent.mkdir(parents=True, exist_ok=True)
        mine_p.write_text(seed_p.read_text(encoding="utf-8"), encoding="utf-8")
        msg = "새로 만듦"
    else:
        try:
            mine = json.loads(mine_p.read_text(encoding="utf-8"))
        except json.JSONDecodeError as e:
            return f"※ {mine_p} 가 JSON 이 아니어서 건드리지 않음 ({e})"
        last = json.loads(last_p.read_text(encoding="utf-8")) if last_p.exists() else None
        merged = merge(mine, seed, last)
        if merged == mine:
            msg = "그대로 둠(고친 것 유지)"
        else:
            mine_p.with_suffix(".json.bak").write_text(mine_p.read_text(encoding="utf-8"), encoding="utf-8")
            mine_p.write_text(json.dumps(merged, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
            msg = "공장 기본값 바뀐 것만 합침(전 파일: settings.json.bak)"
    last_p.write_text(seed_p.read_text(encoding="utf-8"), encoding="utf-8")
    return msg


if __name__ == "__main__":
    print(main(sys.argv[1], sys.argv[2]))
