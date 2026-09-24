#!/usr/bin/env bash
# =============================================================================
# factory/scripts/bootstrap.sh — 공장을 GitHub 에 세웁니다. 맥 미니(또는 gh 가 주인으로 로그인된 아무 기계)에서 한 번.
#
#   bash factory/scripts/bootstrap.sh            # MyBody 저장소 안에서
#
# 하는 일 (전부 다시 돌려도 안전 — 있으면 건너뜀):
#   1. 저장소 둘: app-factory(비공개) · app-factory-ship(공개) — seed/ · ship-seed/ 를 첫 커밋으로
#   2. 출시 창구: store-production 환경 + Required reviewer = 주인 + main 브랜치만 · 배포 열쇠(쓰기) → app-factory 시크릿
#   3. app-factory: 라벨 · lab-results 브랜치 · main 보호(ci 의 `ok` 필수 — 비공개는 GitHub Pro 필요, 없으면 건너뜀)
#   4. 스토어 열쇠가 ~/app-keys/store/ 에 있으면 시크릿으로 (없으면 무엇을 넣어야 하는지 출력)
#   5. 맥 미니 러너 등록 (macOS 일 때) — 등록 토큰을 API 로 받으니 사람 개입 없음
#
# 주인이 하는 것: gh auth login(한 번) · ~/app-keys/store/ 에 스토어 열쇠 파일 넣기(계정당 한 번).
# =============================================================================
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"                      # factory/
OWNER="$(gh api user -q .login)"; OWNER_ID="$(gh api user -q .id)"
F="$OWNER/app-factory"; S="$OWNER/app-factory-ship"
say() { printf '\n\033[1m== %s\033[0m\n' "$*"; }

# ── 1. 저장소 ──────────────────────────────────────────────────────────────
say "1. 저장소"
push_seed() { # <owner/repo> <seed dir>
  local repo="$1" src="$2" t; t="$(mktemp -d)"
  gh repo clone "$repo" "$t" -- -q 2>/dev/null || git init -q "$t"
  ( cd "$t"; git checkout -q -B main 2>/dev/null || true
    cp -R "$src/." .; git add -A
    if ! git diff --cached --quiet; then git -c user.name=factory -c user.email=factory@users.noreply.github.com commit -qm "공장 씨앗 (factory/ 에서)"; git push -q -u origin main; echo "  $repo ← $(basename "$src") 푸시"; else echo "  $repo: 바뀐 것 없음"; fi )
  rm -rf "$t"
}
gh repo view "$F" >/dev/null 2>&1 || gh repo create "$F" --private -d "앱 공장 — Claude 가 조사·기획·구현·시험·출시 준비까지, 주인은 승인만" >/dev/null
gh repo view "$S" >/dev/null 2>&1 || gh repo create "$S" --public  -d "앱 공장 출시 창구 — 코드 없음. 주인 승인 뒤에만 스토어 제출·배포" >/dev/null
push_seed "$F" "$HERE/seed"
push_seed "$S" "$HERE/ship-seed"
# 설계 문서도 app-factory/docs/factory 로
t="$(mktemp -d)"; gh repo clone "$F" "$t" -- -q; mkdir -p "$t/docs/factory"
cp "$HERE"/*.md "$t/docs/factory/"; ( cd "$t"; git add -A; git diff --cached --quiet || { git -c user.name=factory -c user.email=factory@users.noreply.github.com commit -qm "docs/factory: 설계 문서"; git push -q; } ); rm -rf "$t"

# ── 2. 출시 창구 ───────────────────────────────────────────────────────────
say "2. 출시 창구 승인 환경"
gh api -X PUT "repos/$S/environments/store-production" --input - >/dev/null <<JSON
{"reviewers":[{"type":"User","id":$OWNER_ID}],"prevent_self_review":false,"deployment_branch_policy":{"protected_branches":false,"custom_branch_policies":true}}
JSON
gh api -X POST "repos/$S/environments/store-production/deployment-branch-policies" -f name=main -f type=branch >/dev/null 2>&1 || true
echo "  store-production: Required reviewer = $OWNER · main 만"
# 배포 열쇠: app-factory → app-factory-ship 에 queue/ 를 밀어 넣는 데만 씁니다
if ! gh secret list -R "$F" | grep -q '^SHIP_DEPLOY_KEY'; then
  k="$(mktemp -d)"; ssh-keygen -q -t ed25519 -N '' -C "app-factory→ship queue" -f "$k/id"
  gh repo deploy-key add "$k/id.pub" --allow-write -R "$S" -t "app-factory queue" >/dev/null
  gh secret set SHIP_DEPLOY_KEY -R "$F" < "$k/id"; rm -rf "$k"; echo "  배포 열쇠 만들어 넣음 (SHIP_DEPLOY_KEY)"
fi

# ── 3. app-factory 정리 ────────────────────────────────────────────────────
say "3. app-factory 라벨 · 브랜치 · 보호"
for l in "status:상황판:0E8A16" "factory:공장:5319E7" "blocked:막힘:B60205"; do IFS=: read -r n d c <<<"$l"; gh label create "$n" -d "$d" -c "$c" -R "$F" --force >/dev/null; done
if ! gh api "repos/$F/branches/lab-results" >/dev/null 2>&1; then
  t="$(mktemp -d)"; ( cd "$t"; git init -q; git checkout -q --orphan lab-results; echo "# lab-results — device-lab 결과 (앱/실행번호/)" > README.md; git add -A
    git -c user.name=factory -c user.email=factory@users.noreply.github.com commit -qm "lab-results 시작"; git push -q "https://github.com/$F.git" lab-results ); rm -rf "$t"; echo "  lab-results 브랜치"
fi
if gh api -X PUT "repos/$F/branches/main/protection" --input - >/dev/null 2>&1 <<'JSON'
{"required_status_checks":{"strict":false,"contexts":["ok"]},"enforce_admins":false,"required_pull_request_reviews":null,"restrictions":null,"allow_force_pushes":false,"allow_deletions":false}
JSON
then echo "  main 보호: ci/ok 필수 · 강제 푸시 금지"; else echo "  main 보호 못 켬 — 비공개 저장소 보호는 GitHub Pro 필요 (없어도 공장은 돕니다; 훅이 강제 푸시를 막음)"; fi
gh issue list -R "$F" -l factory --json title -q '.[].title' | grep -q '^\[공장\] 오늘' || gh issue create -R "$F" -l factory -t "[공장] 오늘" -b "하루 요약 루틴이 이 본문을 매일 고쳐 씁니다." >/dev/null

# ── 4. 스토어 열쇠 ─────────────────────────────────────────────────────────
say "4. 스토어 열쇠 (~/app-keys/store/)"
K="$HOME/app-keys/store"; mkdir -p "$K"; chmod 700 "$HOME/app-keys" "$K"
put() { # <repo> <secret> <file>
  [ -s "$3" ] && { gh secret set "$2" -R "$1" < "$3" >/dev/null; echo "  $2 ← $(basename "$3")"; } || echo "  (없음) $2 ← $3"; }
put "$F" ASC_BETA_KEY_ID     "$K/asc-beta.keyid"
put "$F" ASC_BETA_ISSUER_ID  "$K/asc.issuer"
put "$F" ASC_BETA_KEY_P8     "$K/asc-beta.p8"
put "$F" PLAY_BETA_SA_JSON   "$K/play-beta.json"
put "$F" CLAUDE_CODE_OAUTH_TOKEN "$K/claude.token"
put "$S" ASC_PROD_KEY_ID     "$K/asc-prod.keyid"
put "$S" ASC_PROD_ISSUER_ID  "$K/asc.issuer"
put "$S" ASC_PROD_KEY_P8     "$K/asc-prod.p8"
put "$S" PLAY_PROD_SA_JSON   "$K/play-prod.json"
cat <<TXT
  파일 이름 규칙: asc-beta.keyid(키 ID 한 줄) · asc.issuer · asc-beta.p8 · asc-prod.keyid · asc-prod.p8 (App Store Connect API 키 둘:
  Developer 역할 = beta, App Manager 역할 = prod) · play-beta.json · play-prod.json (Play 서비스 계정 둘) · claude.token (claude setup-token).
  넣은 뒤 이 스크립트를 다시 돌리면 시크릿으로 올라갑니다. 환경 시크릿(store-production)은 저장소 시크릿과 별개이므로:
TXT
for s in ASC_PROD_KEY_ID ASC_PROD_ISSUER_ID ASC_PROD_KEY_P8 PLAY_PROD_SA_JSON; do
  f=""; case $s in ASC_PROD_KEY_ID) f="$K/asc-prod.keyid";; ASC_PROD_ISSUER_ID) f="$K/asc.issuer";; ASC_PROD_KEY_P8) f="$K/asc-prod.p8";; PLAY_PROD_SA_JSON) f="$K/play-prod.json";; esac
  [ -s "$f" ] && gh secret set "$s" -R "$S" -e store-production < "$f" >/dev/null && echo "  [환경] $s"
done

# ── 5. 러너 (맥 미니) ─────────────────────────────────────────────────────
if [ "$(uname)" = Darwin ]; then
  say "5. 맥 미니 러너"
  R="$HOME/actions-runner"
  if [ ! -f "$R/.runner" ]; then
    mkdir -p "$R"; cd "$R"
    v=$(gh api repos/actions/runner/releases/latest -q .tag_name | tr -d v)
    curl -sL -o r.tgz "https://github.com/actions/runner/releases/download/v$v/actions-runner-osx-arm64-$v.tar.gz" && tar xzf r.tgz && rm r.tgz
    tok=$(gh api -X POST "repos/$F/actions/runners/registration-token" -q .token)
    ./config.sh --unattended --url "https://github.com/$F" --token "$tok" --name macmini-lab --labels lab,macos,ios,android --work _work >/dev/null
    ./svc.sh install >/dev/null && ./svc.sh start >/dev/null; echo "  등록 · 서비스 시작 (라벨 lab)"
  else echo "  이미 등록됨"; fi
fi

say "끝. 다음: 맥 미니 세팅은 factory/scripts/macmini-setup.sh · 첫 앱은 프로젝트 대화에 주제 한 줄"
