#!/usr/bin/env bash
# =============================================================================
# scripts/lab-report.sh — device-lab 결과를 파일과 상태로 (docs/factory/SESSIONS.md 4-2)
#
#   lab-report.sh <앱> <sha> <suite> <결과폴더> <실행번호> <실행URL>
#
# 1. <결과폴더> 를 읽어 summary.json · report.md 를 만들고
# 2. lab-results 브랜치 <앱>/<실행번호>/ 에 푸시하고 (없으면 브랜치를 만듦)
# 3. <sha> 에 체크 런 lab/android · lab/ios 를 붙입니다 → PR 체크 이벤트가 담당 스레드를 깨웁니다.
#    (커밋 상태가 아니라 체크 런인 이유: Claude 의 PR 구독이 받는 것은 체크 이벤트입니다. Actions 의 GITHUB_TOKEN 은 앱 토큰이라 체크 런을 만들 수 있습니다.)
# 필요: GH_TOKEN(checks:write · contents:write), git, jq, python3
# =============================================================================
set -euo pipefail
APP="$1"; SHA="$2"; SUITE="$3"; OUT="$4"; RUN="$5"; URL="$6"
REPO="${GITHUB_REPOSITORY:?}"

# ── 1. 요약 ────────────────────────────────────────────────────────────────
python3 - "$OUT" "$APP" "$SHA" "$SUITE" "$RUN" "$URL" <<'PY'
import json, os, sys, glob, re, xml.etree.ElementTree as ET
out, app, sha, suite, run, url = sys.argv[1:7]
devices = []
for d in sorted(glob.glob(os.path.join(out, "android-*")) + glob.glob(os.path.join(out, "ios-*"))):
    name = os.path.basename(d); flows = {}
    j = os.path.join(d, "junit.xml")
    if os.path.exists(j):
        try:
            for tc in ET.parse(j).iter("testcase"):
                bad = tc.find("failure") is not None or tc.find("error") is not None
                flows[tc.get("name") or "?"] = "fail" if bad else "pass"
        except Exception as e:
            flows["(junit 읽기 실패)"] = "fail"
    else:
        flows["(결과 없음)"] = "fail"
    devices.append({"name": name, "platform": "android" if name.startswith("android") else "ios", "flows": flows})
startup = {}
p = os.path.join(out, "startup.txt")
if os.path.exists(p):
    for line in open(p):
        m = re.match(r"(\S+)\s+TotalTime:\s*(\d+)", line.strip())
        if m: startup[m.group(1)] = int(m.group(2))
notes = []
for n in ("ios.note", "explore.note"):
    p = os.path.join(out, n)
    if os.path.exists(p): notes += [l.strip() for l in open(p) if l.strip()]
def plat_ok(pl):
    ds = [d for d in devices if d["platform"] == pl]
    if not ds: return None
    return all(v == "pass" for d in ds for v in d["flows"].values())
res = {"android": plat_ok("android"), "ios": plat_ok("ios")}
explore = os.path.join(out, "explore.md")
blocking = any(v is False for v in res.values()) or (os.path.exists(explore) and "막을 것 있음" in open(explore).read())
summary = {"app": app, "ref": sha, "suite": suite, "run": run, "url": url, "devices": devices,
           "startupMs": startup, "result": res, "notes": notes, "blocking": blocking,
           "shots": sorted(os.path.basename(x) for x in glob.glob(os.path.join(out, "shots", "*.png")))}
json.dump(summary, open(os.path.join(out, "summary.json"), "w"), ensure_ascii=False, indent=1)
lines = [f"# {app} · {suite} · {sha[:8]} · 실행 {run}", "", f"막을 것: {'있음' if blocking else '없음'}", ""]
for d in devices:
    fails = [k for k, v in d["flows"].items() if v != "pass"]
    lines.append(f"## {d['name']} — {'실패 ' + ', '.join(fails) if fails else '전부 통과'} ({len(d['flows'])}개)")
if startup: lines += ["", "## 시작 시간 (ms)"] + [f"- {k}: {v}" for k, v in startup.items()]
if notes: lines += ["", "## 메모"] + [f"- {n}" for n in notes]
if os.path.exists(explore): lines += ["", "## AI 탐색 시험", open(explore).read()]
lines += ["", f"[실행]({url})"]
open(os.path.join(out, "report.md"), "w").write("\n".join(lines) + "\n")
print(json.dumps(res), "blocking" if blocking else "ok")
PY

# ── 2. lab-results 브랜치에 푸시 ───────────────────────────────────────────
W="$(mktemp -d)"
git fetch -q origin lab-results 2>/dev/null && git worktree add -q "$W" origin/lab-results || {
  git worktree add -q --detach "$W"; (cd "$W" && git checkout -q --orphan lab-results && git rm -rqf . 2>/dev/null || true)
}
D="$W/$APP/$RUN"; mkdir -p "$D"
cp "$OUT/summary.json" "$OUT/report.md" "$D/"
[ -d "$OUT/shots" ] && cp -R "$OUT/shots" "$D/" || true
find "$OUT" -name 'junit.xml' -exec sh -c 'mkdir -p "$0/$(basename $(dirname "$1"))" && cp "$1" "$0/$(basename $(dirname "$1"))/"' "$D" {} \;
[ -f "$OUT/explore.md" ] && cp "$OUT/explore.md" "$D/" || true
( cd "$W" && git config user.name factory-lab && git config user.email lab@users.noreply.github.com \
  && git add -A && git commit -qm "lab: $APP $SUITE ${SHA:0:8} run $RUN" && git push -q origin HEAD:lab-results )
git worktree remove -f "$W" || true
RES_URL="https://github.com/$REPO/tree/lab-results/$APP/$RUN"

# ── 3. 체크 런 ───────────────────────────────────────────────────────────
for pl in android ios; do
  v=$(jq -r ".result.$pl" "$OUT/summary.json")
  case "$v" in true) c=success; desc="전부 통과";; false) c=failure; desc="실패한 흐름 있음 — report.md";; *) c=neutral; desc="시험 기기 없음(건너뜀)";; esac
  gh api -X POST "repos/$REPO/check-runs" -f name="lab/$pl" -f head_sha="$SHA" -f status=completed -f conclusion="$c" \
    -f details_url="$RES_URL" -f "output[title]=$SUITE · $desc" -f "output[summary]=$(head -c 60000 "$OUT/report.md")" >/dev/null
done
{ echo "### device-lab $APP · $SUITE"; echo "- android: $(jq -r .result.android "$OUT/summary.json") · ios: $(jq -r .result.ios "$OUT/summary.json") · 막을 것: $(jq -r .blocking "$OUT/summary.json")"; echo "- 결과: $RES_URL"; } >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
