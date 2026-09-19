/* =============================================================================
 * tools/preflight.js — 지금 배포해도 되는가
 *
 *   node tools/preflight.js
 *
 * 검증 도구가 여러 개로 흩어져 있으면, 배포하려는 순간에 "뭘 돌려야 하지"
 * 를 매번 다시 생각하게 됩니다. 그러다 하나를 빼먹습니다.
 * 그래서 전부를 한 줄로 묶었습니다. 빨간 줄이 없으면 올려도 됩니다.
 *
 * 나누는 기준
 *   막음(BLOCK)  — 이게 빨간 채로 올리면 쓰는 사람이 다칩니다
 *   확인(WARN)   — 알고 올리는 건 괜찮습니다
 *
 * 느린 것(브라우저를 띄우는 것들)은 FAST=1 로 건너뛸 수 있지만, 진짜
 * 배포 전에는 전부 돌리세요. 브라우저에서만 잡히는 것이 실제로 있었습니다.
 * ========================================================================== */
'use strict';
const { execSync, spawnSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..');
const FAST = !!process.env.FAST;
const NODE_PATH = process.env.NODE_PATH || '/opt/node22/lib/node_modules';

const CHECKS = [
  { id: '엔진 정확도', level: 'BLOCK', slow: false, cmd: ['node', 'tools/validate.js'],
    why: '계획 숫자가 실제 연구와 어긋나면 사용자가 자기 몸을 잘못 읽습니다' },
  { id: '결과지 검산', level: 'BLOCK', slow: false, cmd: ['node', 'tools/test-crosscheck.js'],
    why: '잘못 읽은 숫자가 통과하면 몇 주짜리 계획이 통째로 어긋납니다' },
  { id: '서버 권한', level: 'BLOCK', slow: false, cmd: ['node', 'tools/test-social.js'],
    why: '안 켠 항목이 친구에게 새면 돌이킬 수 없습니다' },
  { id: '판독 프록시', level: 'BLOCK', slow: false, cmd: ['node', 'tools/test-ocr.js'],
    why: '모델이 내놓은 헛소리가 그대로 저장되면 안 됩니다' },
  { id: '고유번호', level: 'BLOCK', slow: false, cmd: ['node', 'tools/uid-registry.js'],
    why: '번호가 겹치면 남겨둔 피드백 메모가 엉뚱한 곳에 붙습니다' },
  { id: '장기 시뮬레이션', level: 'BLOCK', slow: false, cmd: ['node', 'tools/simulate.js'],
    why: '3년짜리 경로에서만 드러나는 불변식 위반이 있습니다' },
  { id: '데이터 유실', level: 'BLOCK', slow: true, cmd: ['node', 'tools/test-dataloss.js'],
    why: '앱은 저장했다고 말하는데 실제로는 없어지는 것들 — 눌러보는 검사로는 안 잡힙니다' },
  { id: '화면 스모크', level: 'BLOCK', slow: true, cmd: ['node', 'tools/smoke.js'],
    why: '화면이 안 뜨면 나머지는 의미가 없습니다' },
  { id: '인터랙션 전수', level: 'BLOCK', slow: true, cmd: ['node', 'tools/test-interactions.js'],
    why: '누르면 터지는 버튼 · 막다른 길' },
  { id: '2인 실사용', level: 'BLOCK', slow: true, cmd: ['node', 'tools/test-e2e.js'],
    why: '두 사람이 실제 서버로 주고받는 경로' },
  { id: '배포 빌드', level: 'BLOCK', slow: true, cmd: ['node', 'tools/build-release.js'],
    why: '빌드가 안 되면 올릴 것이 없습니다' },
  { id: '배포 빌드 검증', level: 'BLOCK', slow: true, cmd: ['node', 'tools/test-release.js'],
    why: '개발용 UI 가 남아 있으면 쓰는 사람에게 미완성으로 보입니다' }
];

/* 코드를 읽어서 확인하는 것들 — 명령이 아니라 규칙입니다 */
function staticChecks() {
  const out = [];
  const read = f => { try { return fs.readFileSync(path.join(ROOT, f), 'utf8'); } catch { return ''; } };

  // (1) 배포 플래그가 원본에서는 꺼져 있어야 합니다.
  //     켜진 채로 커밋되면 개발할 때 배지가 안 보여서, 자기가 뭘 보고
  //     있는지 모른 채 작업하게 됩니다.
  const build = read('prototype/js/build.js');
  out.push({ id: '원본 빌드 플래그', level: 'BLOCK',
    ok: /release:\s*false/.test(build),
    detail: 'prototype/js/build.js 는 release: false 여야 합니다 (배포본은 빌드가 만듭니다)' });

  // (2) 거짓 개인정보 문구. 한 번 고치고 또 생겼던 종류라 못으로 박아 둡니다.
  const LIES = [
    '서버로 전송되지 않습니다',
    '실제로 올라가지 않습니다',
    '실제 인증은 하지 않습니다',
    '기기 밖으로 나가지 않습니다'
  ];
  const files = walk(path.join(ROOT, 'prototype', 'js')).filter(f => f.endsWith('.js'));
  const hits = [];
  files.forEach(f => {
    const t = fs.readFileSync(f, 'utf8');
    LIES.forEach(lie => {
      // 주석에 적힌 "예전엔 이랬다" 는 기록이라 봐줍니다
      t.split('\n').forEach((line, i) => {
        if (line.includes(lie) && !/^\s*(\*|\/\/|\/\*)/.test(line) && !line.includes('예전')) {
          hits.push(path.relative(ROOT, f) + ':' + (i + 1) + ' — "' + lie + '"');
        }
      });
    });
  });
  out.push({ id: '거짓 개인정보 문구', level: 'BLOCK', ok: hits.length === 0,
    detail: hits.length ? hits.join('\n         ') :
      '서버로 올라가는데 안 올라간다고 말하는 문구가 없습니다' });

  // (3) 서버는 가입 코드 없이 뜨면 안 됩니다.
  //     정규식으로 "그렇게 적혀 있나" 를 보는 것은 확인이 아닙니다 —
  //     실제로 띄워 보고 죽는지 봅니다. (처음엔 정규식으로 했다가,
  //     멀쩡한 코드를 거짓으로 빨갛게 찍었습니다.)
  const env = Object.assign({}, process.env);
  delete env.PAIR_SECRET;
  env.PORT = '8799';
  env.DB = path.join(require('os').tmpdir(), 'preflight-probe.db');
  const probe = spawnSync(process.execPath, [path.join(ROOT, 'server', 'server.js')],
    { encoding: 'utf8', timeout: 15000, env });
  out.push({ id: '가입 코드 강제', level: 'BLOCK',
    ok: probe.status !== 0,
    detail: probe.status === 0
      ? 'PAIR_SECRET 없이도 서버가 떴습니다 — 아무나 계정을 만들 수 있습니다'
      : 'PAIR_SECRET 없이는 서버가 시작하지 않습니다' });

  // (4) 커밋 안 된 변경 — 지금 올리는 것이 무엇인지 알 수 없게 됩니다
  let dirty = '';
  try { dirty = execSync('git status --porcelain', { cwd: ROOT }).toString().trim(); } catch {}
  out.push({ id: '커밋 상태', level: 'WARN', ok: !dirty,
    detail: dirty ? '커밋 안 된 변경 ' + dirty.split('\n').length + '개 — 되돌릴 지점이 없습니다'
                  : '작업 트리가 깨끗합니다' });

  // (5) 알고 올리는 것들
  out.push({ id: '비밀번호 찾기', level: 'WARN', ok: false,
    detail: '없습니다. 잊으면 서버 주인이 DB 에서 지우고 다시 만들어야 합니다' });
  out.push({ id: '상시 접속', level: 'WARN', ok: false,
    detail: '컴퓨터가 꺼지면 친구도 못 봅니다' });
  out.push({ id: '사진 백업', level: 'WARN', ok: false,
    detail: '사진은 기기에만 있습니다. 폰을 잃으면 사진도 잃습니다 (숫자는 서버에 남습니다)' });

  return out;
}

function walk(dir) {
  return fs.readdirSync(dir).flatMap(f => {
    const p = path.join(dir, f);
    return fs.statSync(p).isDirectory() ? walk(p) : [p];
  });
}

/* --- 실행 ----------------------------------------------------------------- */
console.log('\n배포 전 점검' + (FAST ? '  (FAST=1 — 브라우저 검사 건너뜀)' : '') + '\n');

const results = [];

console.log('규칙');
staticChecks().forEach(c => {
  results.push(c);
  const mark = c.ok ? '✓' : (c.level === 'BLOCK' ? '✗' : '!');
  console.log(`  ${mark} ${c.id}`);
  if (!c.ok) console.log(`       ${c.detail}`);
});

console.log('\n검사');
for (const c of CHECKS) {
  if (FAST && c.slow) { console.log(`  · ${c.id} — 건너뜀`); continue; }
  process.stdout.write(`  … ${c.id}`);
  const t0 = Date.now();
  const r = spawnSync(c.cmd[0], c.cmd.slice(1), {
    cwd: ROOT, encoding: 'utf8',
    env: Object.assign({}, process.env, { NODE_PATH }),
    timeout: 20 * 60 * 1000
  });
  const secs = ((Date.now() - t0) / 1000).toFixed(0);
  const ok = r.status === 0;
  const tail = ((r.stdout || '') + (r.stderr || '')).trim().split('\n').slice(-3).join('\n       ');
  results.push({ id: c.id, level: c.level, ok, detail: tail, why: c.why });
  process.stdout.write(`\r  ${ok ? '✓' : '✗'} ${c.id} (${secs}초)          \n`);
  if (!ok) {
    console.log(`       ${c.why}`);
    console.log(`       ${tail}`);
  }
}

/* --- 판정 ----------------------------------------------------------------- */
const blocked = results.filter(r => r.level === 'BLOCK' && !r.ok);
const warned = results.filter(r => r.level === 'WARN' && !r.ok);

console.log('\n' + '─'.repeat(52));
if (warned.length) {
  console.log('\n알고 올리는 것 (막지는 않습니다)');
  warned.forEach(w => console.log(`  ! ${w.id} — ${w.detail}`));
}
if (blocked.length) {
  console.log(`\n배포하면 안 됩니다 — ${blocked.length}건\n`);
  blocked.forEach(b => console.log(`  ✗ ${b.id}`));
  console.log('\n위의 것을 고치고 다시 돌리세요.');
  process.exit(1);
}
console.log('\n배포해도 됩니다.\n');
console.log('  node tools/build-release.js');
console.log('  PAIR_SECRET=$(cat ~/.mybody-pair) STATIC=./release node server/server.js');
console.log('  cloudflared tunnel --url http://localhost:8080\n');
console.log('  자세한 것은 docs/DEPLOY.md\n');
