#!/usr/bin/env node
/* =============================================================================
 * .claude/hooks/guard.js — Claude 가 셸에서 하면 안 되는 것 막기 (PreToolUse 훅)
 *
 * settings.json 이 Bash · PowerShell 도구를 부를 때마다 이 파일을 먼저 돌립니다.
 * 막히면 종료코드 2 와 함께 이유를 stderr 로 내고, Claude 는 그 이유를 봅니다.
 *
 * 왜 CLAUDE.md 만으로는 안 되는가
 *   CLAUDE.md 는 Claude 가 "하려는 것" 을 바꾸지만 "할 수 있는 것" 은 못 바꿉니다.
 *   출시 · 열쇠 · 돈은 한 번 새면 되돌릴 수 없으므로 도구 단계에서 막습니다.
 *
 * 이게 전부는 아니다
 *   명령 글자를 보는 검사라 다른 모양으로 우회될 수 있습니다. 진짜 잠금은
 *   GitHub 환경(store-production)의 승인 버튼과, 그 환경에만 넣은 출시용 열쇠입니다
 *   (factory/PIPELINE.md 「승인 게이트」). 이 훅은 실수를 막는 두 번째 줄입니다.
 *
 * 시험: node .claude/hooks/guard.test.js
 * ========================================================================== */
'use strict';

/* 각 규칙: 이름 · 정규식 · 이유. 이유는 Claude 가 읽고 다른 길을 찾게 씁니다. */
const RULES = [
  {
    id: 'store-api',
    re: /api\.appstoreconnect\.apple\.com|androidpublisher\.googleapis\.com/i,
    why: '스토어 API 는 GitHub 워크플로에서만 부릅니다(출시는 store-production 환경 승인 뒤). ' +
         '세션에서 직접 부르지 말고 워크플로를 실행하세요.',
  },
  {
    id: 'store-upload',
    re: /\bfastlane\b[^\n;&|]*\b(deliver|upload_to_app_store|upload_to_testflight|pilot|supply|upload_to_play_store|submit\w*|promote\w*|release|ship|beta)\b/i,
    why: '스토어 업로드 · 제출 레인은 CI 에서만 돕니다. 로컬에서 쓸 수 있는 레인은 test · snapshot · screengrab 입니다.',
  },
  {
    id: 'approval-gate',
    re: /\bgh\s+api\b[^\n]*(pending_deployments|\/environments\b|\/protection\b|\/rulesets\b)/i,
    why: '출시 승인 · 환경 보호 규칙 · 브랜치 보호는 주인만 바꿉니다.',
  },
  {
    id: 'secrets',
    re: /\bgh\s+secret\b|\bgh\s+variable\s+(set|delete)\b/i,
    why: '저장소 Secrets 는 주인(또는 주인이 돌린 설치 스크립트)만 넣습니다. 필요한 값은 보고의 「주인 할 일」에 적으세요.',
  },
  {
    id: 'key-read',
    // 읽거나 옮기는 명령 + 열쇠 파일 이름이 같이 있을 때만. 그냥 grep 으로 "keystore" 글자를 찾는 건 막지 않습니다.
    re: /\b(cat|less|more|head|tail|bat|base64|xxd|hexdump|od|strings|cp|mv|scp|rsync|curl|wget|nc|openssl|gpg|zip|tar|type|Get-Content)\b[^\n]*((AuthKey_\w*|\S*)\.(p8|p12|jks|keystore|mobileprovision)\b|KEY-INFO|key\.properties|service[-_]?account\S*\.json|play[-_]\S*\.json)/i,
    why: '서명 열쇠 · API 열쇠 파일은 열거나 옮기지 않습니다. 빌드는 CI 가 Secrets 로 합니다.',
  },
  {
    id: 'keychain-dump',
    re: /\bsecurity\s+(find-(generic|internet)-password\b[^\n]*\s-w\b|export\b|dump-keychain\b)/i,
    why: '키체인의 비밀번호 · 열쇠를 꺼내지 않습니다.',
  },
  {
    id: 'force-push-main',
    re: /\bgit\s+push\b(?=[^\n]*(\s--force(-with-lease)?\b|\s-f\b|\s\+))(?=[^\n]*\b(main|master)\b)/i,
    why: 'main 에 강제 푸시하지 않습니다. 되돌릴 게 있으면 되돌리는 커밋을 올리세요.',
  },
  {
    id: 'delete-main',
    re: /\bgit\s+push\b[^\n]*(\s:(main|master)\b|--delete\s+(main|master)\b)/i,
    why: 'main 브랜치를 지우지 않습니다.',
  },
  {
    id: 'rm-root',
    re: /\brm\s+-[a-zA-Z]*(r[a-zA-Z]*f|f[a-zA-Z]*r)[a-zA-Z]*\s+("?(\/|~\/?|\$HOME\/?|\/Users\/[^\s\/]*\/?|\/home\/[^\s\/]*\/?)"?)(\s|$)/,
    why: '홈이나 루트를 통째로 지우는 명령입니다. 지울 폴더를 정확히 적으세요.',
  },
  {
    id: 'device-wipe',
    re: /\badb\b[^\n]*(\breboot\s+(recovery|bootloader)\b|\bshell\s+(recovery|wipe)\b|\bpm\s+(uninstall|clear)\s+(--?\S+\s+(\d+\s+)?)*(com\.(android|google|samsung|sec|lge)\.))/i,
    why: '주인 폰의 시스템 앱을 지우거나 초기화하지 않습니다. 우리 앱 패키지만 다룹니다.',
  },
  {
    id: 'ad-spend',
    re: /api\.searchads\.apple\.com|googleads\.googleapis\.com|graph\.facebook\.com\/[^\s]*\/(ads|campaigns)/i,
    why: '광고 예산 집행은 주인이 합니다. 제안서(금액 · 기간 · 기대 효과)를 보고에 넣으세요.',
  },
];

function check(command) {
  const cmd = String(command || '');
  for (const r of RULES) if (r.re.test(cmd)) return r;
  return null;
}

module.exports = { check, RULES };

if (require.main === module) {
  let raw = '';
  process.stdin.setEncoding('utf8');
  process.stdin.on('data', c => { raw += c; });
  process.stdin.on('end', () => {
    let input;
    try { input = JSON.parse(raw); } catch {
      // 훅이 깨져서 모든 셸 명령이 멈추면 공장이 섭니다. 읽지 못하면 통과시키고 흔적만 남깁니다.
      process.stderr.write('guard.js: 입력을 읽지 못했습니다 — 통과시킵니다\n');
      process.exit(0);
    }
    const hit = check(input && input.tool_input && input.tool_input.command);
    if (!hit) process.exit(0);
    process.stderr.write(`[막음:${hit.id}] ${hit.why}\n`);
    process.exit(2);
  });
}
