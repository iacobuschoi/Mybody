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
  { id: '서버 굳히기', level: 'BLOCK', slow: false, cmd: ['node', 'tools/test-hardening.js'],
    why: '인터넷에 여는 서버입니다 — 경로 탈출 하나면 옆 폴더가 통째로 열립니다' },
  { id: '동기화 큐', level: 'BLOCK', slow: false, cmd: ['node', 'tools/test-syncqueue.js'],
    why: '조용히 지워진 "공유 끄기" 는 껐다고 믿는 사람에게 제일 나쁜 고장입니다' },
  { id: '운동 일정·스트릭', level: 'BLOCK', slow: false, cmd: ['node', 'tools/test-schedule.js'],
    why: '스트릭이 틀리면 화면이 조용히 거짓말합니다 — 아무도 12일째를 검산하지 않습니다' },
  { id: '고유번호', level: 'BLOCK', slow: false, cmd: ['node', 'tools/uid-registry.js'],
    why: '번호가 겹치면 남겨둔 피드백 메모가 엉뚱한 곳에 붙습니다' },
  { id: '장기 시뮬레이션', level: 'BLOCK', slow: false, cmd: ['node', 'tools/simulate.js'],
    why: '3년짜리 경로에서만 드러나는 불변식 위반이 있습니다' },
  { id: '정직성', level: 'BLOCK', slow: true, cmd: ['node', 'tools/test-honesty.js'],
    why: '오차보다 작은 변화를 성과로 세면 없는 규칙을 믿게 만듭니다' },
  { id: '데이터 유실', level: 'BLOCK', slow: true, cmd: ['node', 'tools/test-dataloss.js'],
    why: '앱은 저장했다고 말하는데 실제로는 없어지는 것들 — 눌러보는 검사로는 안 잡힙니다' },
  { id: '화면 스모크', level: 'BLOCK', slow: true, cmd: ['node', 'tools/smoke.js'],
    why: '화면이 안 뜨면 나머지는 의미가 없습니다' },
  { id: '인터랙션 전수', level: 'BLOCK', slow: true, cmd: ['node', 'tools/test-interactions.js'],
    why: '누르면 터지는 버튼 · 막다른 길' },
  { id: '2인 실사용', level: 'BLOCK', slow: true, cmd: ['node', 'tools/test-e2e.js'],
    why: '두 사람이 실제 서버로 주고받는 경로' },
  { id: '띄우기', level: 'BLOCK', slow: true, cmd: ['node', 'tools/test-selfhost.js'],
    why: '앱이 멀쩡해도 서버를 못 띄우면 아무도 못 씁니다' },
  { id: '주간 일정 화면', level: 'BLOCK', slow: true, cmd: ['node', 'tools/test-weekplan-ui.js'],
    why: '매일 누르는 칸입니다 — 한 번 안 눌리면 그 날 기록이 통째로 비어 버립니다' },
  { id: '판독 화면', level: 'BLOCK', slow: true, cmd: ['node', 'tools/test-ocr-ui.js'],
    why: '서버가 잘 읽어도 화면에 판독 버튼이 안 보이면 없는 기능입니다' },
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
  /* 한 번 고치고 또 생긴 문구들입니다. 코드에 못으로 박아 둡니다.
     전부 "지금은 거짓" 이거나 "상태에 따라 거짓" 인 고정 문자열입니다. */
  const LIES = [
    '서버로 전송되지 않습니다',
    '실제로 올라가지 않습니다',
    '실제 인증은 하지 않습니다',
    '기기 밖으로 나가지 않습니다',
    '어디에도 보내지 않습니다',
    '네트워크 요청이 하나도 없습니다',
    '기기를 바꿔도 기록이 남',
    '전부 이 기기 안에만 저장됩니다',
    /* 복구 코드가 생긴 뒤로 거짓입니다. 실제보다 허술하게 말하는 것도
       튼튼하게 말하는 것만큼 나쁩니다 — 둘 다 자기 위험을 잘못 재게
       만듭니다. 여기서는 "못 돌아온다" 고 믿은 사람이 계정을 지우고
       다시 만듭니다. 친구 관계와 주간 기록을 같이 버리면서. */
    '되돌릴 방법이 없습니다'
  ];
  /* 무엇을 봐주고 무엇을 잡을지가 이 검사의 전부입니다.
     너무 느슨하면 거짓말이 새고, 너무 빡빡하면(처음이 그랬습니다) 자기
     주석과 정상적인 조건 분기까지 빨갛게 찍어서 아무도 안 보게 됩니다.

     봐주는 것
       · 주석 — 한 줄이든 블록이든. "예전엔 이랬다" 는 기록입니다.
       · 상태를 보고 고른 가지 — 위 몇 줄 안에 signedIn / canOcr /
         configured 같은 판단이 있으면, 그 문장은 그 상태에서 참입니다.
     잡는 것
       · 그 외 전부. 조건 없이 박힌 문장. */
  const files = walk(path.join(ROOT, 'prototype', 'js')).filter(f => f.endsWith('.js'));
  const GUARDS = /signedIn|canOcr\(\)|\.configured|MB_BUILD|status\(\)/;
  const hits = [];
  files.forEach(f => {
    const raw = fs.readFileSync(f, 'utf8');
    // 블록 주석을 같은 줄 수만큼의 빈 줄로 바꿔 둡니다 (줄 번호가 안 밀리게)
    const stripped = raw.replace(/\/\*[\s\S]*?\*\//g, m => m.replace(/[^\n]/g, ' '));
    const lines = stripped.split('\n');
    LIES.forEach(lie => {
      lines.forEach((line, i) => {
        if (!line.includes(lie)) return;
        if (/^\s*\/\//.test(line)) return;
        const near = lines.slice(Math.max(0, i - 6), i + 2).join('\n');
        if (GUARDS.test(near)) return;
        hits.push(path.relative(ROOT, f) + ':' + (i + 1) + ' — "' + lie + '"');
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

  /* (4.5) 개인정보처리방침의 운영자 칸.
     늦게 알면 다시 빌드해야 하므로 여기서 먼저 말합니다. 실제 판정은
     배포 빌드를 실제로 열어 보는 test-release 가 합니다. */
  {
    const owner = (process.env.OWNER || '').trim();
    const contact = (process.env.OWNER_CONTACT || '').trim();
    out.push({ id: '방침 운영자', level: 'BLOCK', ok: !!(owner && contact),
      detail: (owner && contact)
        ? owner + ' · ' + contact + ' 로 방침에 박힙니다'
        : 'OWNER · OWNER_CONTACT 를 넣고 다시 돌리세요 — 개인정보처리방침에 ' +
          '"누구에게 말하면 되는지" 가 비어 있으면 권리를 행사할 길이 없습니다 ' +
          '(docs/DEPLOY.md 0번)' });
  }

  /* (4.7) 보유 기간이 세 군데에서 같은 숫자인가.
     서버가 자르는 기간 · 가입 동의 문구 · 처리방침. 하나만 고치면
     나머지 둘이 거짓말이 됩니다. 사람이 기억하기를 바라지 말고
     여기서 붙잡습니다. */
  {
    const dbSrc = read('server/db.js');
    const uiSrc = read('prototype/js/modals.js');
    const pvSrc = read('prototype/privacy.html');
    const m = dbSrc.match(/const SNAPSHOT_WEEKS\s*=\s*(\d+)\s*\*\s*7/);
    const weeks = m ? Number(m[1]) : null;
    const inUi = weeks != null && uiSrc.includes('최근 ' + weeks + '주');
    const inPv = weeks != null && pvSrc.includes('<b>' + weeks + '주</b>');
    out.push({ id: '보유 기간 일치', level: 'BLOCK', ok: !!(weeks && inUi && inPv),
      detail: weeks
        ? (inUi && inPv
            ? '서버 · 동의 문구 · 처리방침이 모두 ' + weeks + '주입니다'
            : '서버는 ' + weeks + '주인데 ' +
              [!inUi ? '동의 문구' : null, !inPv ? '처리방침' : null].filter(Boolean).join(' · ') +
              ' 에 그 숫자가 없습니다')
        : 'server/db.js 에서 SNAPSHOT_WEEKS 를 못 찾았습니다' });
  }

  // (5) 알고 올리는 것들
  /* 복구 코드가 실제로 붙어 있는지 눈으로 확인합니다. 문구만 고치고
     기능을 안 붙인 채 배포하면, 사용자는 "코드로 돌아올 수 있다" 고
     믿은 채 비밀번호를 잊습니다. */
  {
    const dbSrc = read('server/db.js');
    const srvSrc = read('server/server.js');
    const uiSrc = read('prototype/js/modals.js');
    const wired = /recoverPassword/.test(dbSrc) && /\/auth\/recover/.test(srvSrc)
                  && /M\.recoveryCode/.test(uiSrc);
    out.push({ id: '비밀번호 찾기', level: 'WARN', ok: wired,
      detail: wired
        ? '복구 코드로 돌아올 수 있습니다. 코드까지 잃으면 서버 주인이 DB 를 손봐야 합니다'
        : '없습니다. 잊으면 서버 주인이 DB 에서 지우고 다시 만들어야 합니다' });
  }
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
