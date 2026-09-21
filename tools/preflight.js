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
/* 규칙만 — 코드를 읽어 판정하는 것들만 보고 끝냅니다 (1초).
   node tools/preflight.js --rules   또는   RULES_ONLY=1 */
const RULES_ONLY = process.argv.includes('--rules') || !!process.env.RULES_ONLY;
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
  { id: '폰 알림 암호', level: 'BLOCK', slow: false, cmd: ['node', 'tools/test-push.js'],
    why: '암호가 조금만 틀려도 브라우저가 조용히 버립니다 — 서버는 보냈다고 하는데 폰엔 안 뜹니다' },
  { id: '동기화 큐', level: 'BLOCK', slow: false, cmd: ['node', 'tools/test-syncqueue.js'],
    why: '조용히 지워진 "공유 끄기" 는 껐다고 믿는 사람에게 제일 나쁜 고장입니다' },
  { id: '공유 항목 이관', level: 'BLOCK', slow: false, cmd: ['node', 'tools/test-sharemigrate.js'],
    why: '나중에 생긴 항목이 옛 관계에서 저절로 켜지면, 껐다고 믿는 사람이 새고 있습니다' },
  { id: '친구 소식', level: 'BLOCK', slow: false, cmd: ['node', 'tools/test-news.js'],
    why: '"안 했다" 가 알림으로 흐르면 그건 독려가 아니라 망신입니다' },
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
  { id: '인터랙션 전수', level: 'BLOCK', slow: true, minutes: 45,
    cmd: ['node', 'tools/test-interactions.js'],
    why: '누르면 터지는 버튼 · 막다른 길' },
  { id: '2인 실사용', level: 'BLOCK', slow: true, cmd: ['node', 'tools/test-e2e.js'],
    why: '두 사람이 실제 서버로 주고받는 경로' },
  { id: '띄우기', level: 'BLOCK', slow: true, cmd: ['node', 'tools/test-selfhost.js'],
    why: '앱이 멀쩡해도 서버를 못 띄우면 아무도 못 씁니다' },
  { id: '주간 일정 화면', level: 'BLOCK', slow: true, cmd: ['node', 'tools/test-weekplan-ui.js'],
    why: '매일 누르는 칸입니다 — 한 번 안 눌리면 그 날 기록이 통째로 비어 버립니다' },
  { id: '앱 받기 화면', level: 'BLOCK', slow: true, cmd: ['node', 'tools/test-gate-ui.js'],
    why: '링크를 받은 친구가 제일 먼저 보는 화면입니다 — 못 까는 기기에서 들어올 길이 막히면 그 친구는 못 씁니다' },
  { id: '친구 주 이름', level: 'BLOCK', slow: true, cmd: ['node', 'tools/test-friendweek-ui.js'],
    why: '남의 지난주 성적을 "이번 주" 라고 부르면 화면이 남에 대해 사실이 아닌 말을 합니다' },
  { id: '가입 화면', level: 'BLOCK', slow: true, cmd: ['node', 'tools/test-signup-ui.js'],
    why: '이 서버가 코드를 쓰는지 화면이 모르면, 친구는 받은 적 없는 코드를 넣으라는 빈칸 앞에서 멈춥니다' },
  { id: '판독 화면', level: 'BLOCK', slow: true, cmd: ['node', 'tools/test-ocr-ui.js'],
    why: '서버가 잘 읽어도 화면에 판독 버튼이 안 보이면 없는 기능입니다' },
  { id: '비밀번호 풀어주기', level: 'BLOCK', slow: true,
    cmd: ['node', 'tools/test-reset-password.js'],
    why: '비밀번호를 잊은 사람이 새 계정을 만드는 대신 돌아올 수 있는 유일한 길입니다 — 초기화하고 나서 기록과 친구가 남아 있지 않으면 만든 의미가 없습니다' },
  { id: '옮긴 로직', level: 'BLOCK', slow: true, minutes: 30,
    cmd: ['node', 'tools/difftest.js', '--n=3000'],
    why: 'Flutter 로 옮긴 도메인 로직이 원본과 같은 답을 내는가 — 갈리면 두 앱이 같은 결과지를 놓고 다른 말을 합니다 (Dart 가 없으면 건너뜁니다)' },
  { id: '워크스페이스 찾기', level: 'BLOCK', slow: true, cmd: ['node', 'tools/test-workspaces.js'],
    why: '판독이 막힌 사람이 마지막으로 쥐는 도구입니다 — 여기서도 "안 됩니다" 만 나오면 갈 데가 없습니다' },
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
  //
  //     OPEN_SIGNUP 은 환경에서 지우고 띄웁니다. 안 지우면 가입을 열어 둔
  //     사람의 컴퓨터에서는 이 규칙이 저절로 통과해서, 나중에 문지기가
  //     진짜로 부서져도 아무도 못 알아챕니다. 이 규칙이 보는 것은
  //     "둘 다 비었을 때 거절하는가" 하나입니다 — 열어 둔 것 자체는
  //     아래 '가입 열림' 이 따로 말합니다.
  const env = Object.assign({}, process.env);
  delete env.PAIR_SECRET;
  delete env.OPEN_SIGNUP;
  env.PORT = '8799';
  env.DB = path.join(require('os').tmpdir(), 'preflight-probe.db');
  const probe = spawnSync(process.execPath, [path.join(ROOT, 'server', 'server.js')],
    { encoding: 'utf8', timeout: 15000, env });
  out.push({ id: '가입 코드 강제', level: 'BLOCK',
    ok: probe.status !== 0,
    detail: probe.status === 0
      ? 'PAIR_SECRET 도 OPEN_SIGNUP 도 없는데 서버가 떴습니다 — 아무나 계정을 만들 수 있습니다'
      : '둘 다 비어 있으면 서버가 시작하지 않습니다 (열려면 OPEN_SIGNUP=1 로 분명히 말해야 합니다)' });

  /* (3.5) 데이터베이스 파일이 git 에 들어가 있는가.
   *
   * 안에는 비밀번호 해시와 복구 코드 해시가 들어 있습니다. 한 번
   * 커밋되면 히스토리에서 지우기 어렵고, 공개 저장소면 되돌릴 수
   * 없습니다. .gitignore 는 막으려고 있는 것이지만, 경로가 어긋나면
   * 조용히 통과합니다 — 실제로 undefined/t2/mybody.db 가 한 번
   * 들어갔습니다(다행히 전 테이블 0행이었습니다).
   * 규칙이 아니라 결과를 봅니다: 지금 추적 중인 파일 목록. */
  {
    let tracked = '';
    try { tracked = execSync('git ls-files', { cwd: ROOT }).toString(); } catch {}
    const bad = tracked.split('\n')
      .filter(f => /\.(db|sqlite|sqlite3)(-shm|-wal)?$|\.db\.before-/.test(f));
    out.push({ id: 'DB 파일 커밋', level: 'BLOCK', ok: bad.length === 0,
      detail: bad.length
        ? '데이터베이스가 git 에 들어 있습니다 (비밀번호·복구 코드 해시): ' + bad.join(', ') +
          ' — git rm --cached 로 빼고 .gitignore 를 확인하세요'
        : '데이터베이스 파일이 추적되고 있지 않습니다' });
  }

  // (4) 커밋 안 된 변경 — 지금 올리는 것이 무엇인지 알 수 없게 됩니다
  let dirty = '';
  try { dirty = execSync('git status --porcelain', { cwd: ROOT }).toString().trim(); } catch {}
  out.push({ id: '커밋 상태', level: 'WARN', ok: !dirty,
    detail: dirty ? '커밋 안 된 변경 ' + dirty.split('\n').length + '개 — 되돌릴 지점이 없습니다'
                  : '작업 트리가 깨끗합니다' });

  /* (4.5) 개인정보처리방침의 운영자 칸.
     늦게 알면 다시 빌드해야 하므로 여기서 먼저 말합니다. 실제 판정은
     배포 빌드를 실제로 열어 보는 test-release 가 합니다.

     이 규칙이 잡으려던 것은 **깜빡한 것** 입니다. 그런데 안 적기로
     **정한 것**과 구분을 못 해서, 이름을 안 걸기로 한 사람은 배포를
     통째로 막혔습니다. 규칙이 사람의 결정을 덮어쓰면 그건 규칙이
     아니라 벽입니다.

     그래서 "안 적는다" 를 명시적으로 고를 수 있게 하되, 그 선택은
     기록에 남습니다 — OWNER_OMIT=1 이거나 설정에 ownerOmitted 가
     켜져 있어야 하고, 그래도 "알고 올리는 것" 목록에 줄이 남습니다.
     빈칸으로 두는 것과 안 적기로 하는 것은 다른 일입니다. */
  {
    const owner = (process.env.OWNER || '').trim();
    const contact = (process.env.OWNER_CONTACT || '').trim();
    let omitted = /^(1|true|yes)$/i.test((process.env.OWNER_OMIT || '').trim());
    if (!omitted) {
      try { omitted = !!require('./config.js').load().cfg.ownerOmitted; } catch (e) {}
    }
    if (owner && contact) {
      out.push({ id: '방침 운영자', level: 'BLOCK', ok: true,
        detail: owner + ' · ' + contact + ' 로 방침에 박힙니다' });
    } else if (omitted) {
      out.push({ id: '방침 운영자', level: 'BLOCK', ok: true,
        detail: '안 적기로 정했습니다 — 방침에는 "이 주소를 알려준 사람에게 ' +
                '직접 말해 주세요" 로 나갑니다' });
      out.push({ id: '운영자 이름 없음', level: 'WARN', ok: false,
        detail: '처리방침에 이름도 연락처도 없습니다. 친구들은 주소를 직접 받았으니 ' +
                '누구에게 말할지 알지만, 모르는 사람이 보면 물어볼 데가 없습니다' });
    } else {
      out.push({ id: '방침 운영자', level: 'BLOCK', ok: false,
        detail: 'OWNER · OWNER_CONTACT 를 넣거나, 안 적기로 정했으면 OWNER_OMIT=1 ' +
                '(또는 serve --setup 에서 선택) 로 그 결정을 남기세요 — 빈칸으로 ' +
                '두면 깜빡한 것인지 정한 것인지 알 수 없습니다 (docs/DEPLOY.md 0번)' });
    }
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

  /* (4.8) 기본으로 나가는 항목이 몇 개이고, 화면이 그 숫자대로 말하는가.
   *
   * 이게 실제로 두 번 틀렸습니다. blankShare() 에 항목을 하나 더 켜 놓고
   * 화면 문구는 "이번 주에 기록을 했는지 여부 하나뿐입니다" 로 남겨 뒀습니다.
   * 친구 탭 네 군데와 개인정보처리방침이 전부 같은 거짓말을 하고 있었습니다.
   *
   * 공유 화면이 실제보다 적게 말하는 것은 이 앱에서 제일 나쁜 버그입니다 —
   * 그 문장을 읽고 "그 정도면 괜찮지" 하고 친구를 맺기 때문입니다.
   * 그래서 사람이 기억하기를 바라지 않고 여기서 셉니다.
   */
  {
    const srvSrc = read('server/db.js');
    const cliSrc = read('prototype/js/backend.js');
    function defaultsOf(src, re) {
      const m = src.match(re);
      if (!m) return null;
      const on = [];
      const body = m[0];
      body.replace(/(\w+)\s*:\s*true/g, (_, k) => { on.push(k); return _; });
      return on.sort();
    }
    const srvOn = defaultsOf(srvSrc, /function blankShare\(\)[\s\S]*?return \{[\s\S]*?\};/);
    const cliOn = defaultsOf(cliSrc, /function blankShare\(\)[\s\S]*?return \{[\s\S]*?\};/);
    const same = srvOn && cliOn && srvOn.join() === cliOn.join();
    out.push({ id: '기본 공유 서버·앱 일치', level: 'BLOCK', ok: !!same,
      detail: same
        ? '기본으로 켜지는 항목 ' + srvOn.length + '개가 양쪽에서 같습니다 (' + srvOn.join(' · ') + ')'
        : '서버는 [' + (srvOn || ['못 읽음']).join(' · ') + '] 인데 앱은 [' +
          (cliOn || ['못 읽음']).join(' · ') + '] 입니다 — ' +
          '오프라인에서 켜 둔 것이 로그인하는 순간 바뀝니다' });

    /* 화면이 "하나뿐" 이라고 말하는데 실제로는 둘 이상인 경우를 잡습니다.
       숫자를 세지 않고 문구를 봅니다 — 어차피 사람이 읽는 건 문구입니다. */
    if (srvOn && srvOn.length !== 1) {
      const ONLY_ONE = [
        '여부 하나입니다', '여부만 기본으로', '기록 하나입니다', '하나만 켜져',
        '여부 하나뿐입니다', '하나뿐입니다',
        /* 커밋 7676cbb 가 같은 거짓말을 다섯 군데 고치면서 하필
           **수락 버튼 바로 밑** 한 줄을 빠뜨렸습니다 — 동의가 실제로
           일어나는 유일한 자리입니다. 어미가 달라서 위 목록에 안 걸렸습니다.
           같은 뜻의 다른 어미를 같이 적어 둡니다. */
        '여부만 나갑니다', '여부만 갑니다', '여부만 보입니다', '여부뿐입니다'
      ];
      const files = ['prototype/js/screens/social.js', 'prototype/js/modals.js',
                     'prototype/privacy.html'];
      const hits = [];
      files.forEach(f => {
        const src = read(f);
        src.split('\n').forEach((line, i) => {
          if (/^\s*(\/\/|\*|\/\*)/.test(line)) return;          // 주석은 기록입니다
          // 한 줄에 두 표현이 같이 걸려도 한 번만 적습니다
          if (ONLY_ONE.some(w => line.includes(w))) hits.push(f + ':' + (i + 1));
        });
      });
      out.push({ id: '기본 공유 문구', level: 'BLOCK', ok: hits.length === 0,
        detail: hits.length
          ? '기본으로 켜지는 항목이 ' + srvOn.length + '개인데 "하나뿐" 이라고 적힌 곳: ' +
            hits.join(', ')
          : '기본 ' + srvOn.length + '개를 "하나뿐" 이라고 말하는 곳이 없습니다' });
    }
  }

  /* (4.9) 일정 공유가 "숫자 두 개" 라고 적힌 곳.
   *
   * 실제로 나가는 것은 넷입니다 — plannedDays · keptDays · missedDays ·
   * openDays. 뒤의 둘은 앞의 둘로 복원되지 않습니다: planned − kept 가
   * "빼먹은 날 + 남은 날" 이라는 것만 알 뿐, 그 둘의 나눔은 별도의
   * 사실이고 친구 화면에 그대로 그려집니다("지나간 날 중 2일은 체크가
   * 없습니다").
   *
   * 이 공유는 **기본 켜짐** 이라, 아무 설정도 안 만진 사람에게도
   * 해당합니다. 실제보다 적게 말하는 문구는 그래서 막습니다.
   */
  {
    const emitted = (() => {
      const m = read('server/db.js')
        .match(/if \(s\.schedule && p\.plannedDays != null\) \{[\s\S]*?\}/);
      if (!m) return null;
      const keys = new Set();
      m[0].replace(/o\.(\w+)\s*=/g, (_, k) => { keys.add(k); return _; });
      return keys.size;
    })();
    const WORDS = ['두 숫자', '숫자 두 개', '숫자 두개'];
    const files = ['prototype/js/screens/social.js', 'prototype/js/modals.js',
                   'prototype/privacy.html', 'docs/START.md'];
    const hits = [];
    if (emitted && emitted !== 2) {
      files.forEach(f => {
        const src = read(f);
        src.split('\n').forEach((line, i) => {
          if (/^\s*(\/\/|\*|\/\*)/.test(line)) return;      // 주석은 기록입니다
          if (WORDS.some(w => line.includes(w))) hits.push(f + ':' + (i + 1));
        });
      });
    }
    out.push({ id: '일정 공유 개수', level: 'BLOCK',
      ok: emitted != null && hits.length === 0,
      detail: emitted == null
        ? 'server/db.js 에서 일정으로 나가는 항목을 못 읽었습니다 (규칙이 헛돕니다)'
        : hits.length
          ? '일정으로 ' + emitted + '개가 나가는데 "두 개" 라고 적힌 곳: ' + hits.join(', ')
          : '일정으로 나가는 ' + emitted + '개를 "두 개" 라고 말하는 곳이 없습니다' });
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
  /* "컴퓨터가 꺼지면 친구도 못 봅니다" 는 맞는 말이지만, 계속 켜 두기로
     정한 사람에게는 매번 같은 잔소리입니다. 정했으면 그렇게 적어 둡니다. */
  {
    let alwaysOn = /^(1|true|yes)$/i.test((process.env.ALWAYS_ON || '').trim());
    if (!alwaysOn) {
      try { alwaysOn = !!require('./config.js').load().cfg.alwaysOn; } catch (e) {}
    }
    if (!alwaysOn) {
      out.push({ id: '상시 접속', level: 'WARN', ok: false,
        detail: '컴퓨터가 꺼지면 친구도 못 봅니다 ' +
                '(계속 켜 둘 거면 serve --setup --always-on)' });
    }
  }

  /* 가입을 열어 뒀으면 그 사실이 매번 보여야 합니다. 설정 파일 안에만
     있으면 몇 주 뒤엔 자기가 열어 뒀다는 것도 잊습니다. */
  {
    let open = /^(1|true|yes)$/i.test((process.env.OPEN_SIGNUP || '').trim());
    if (!open) {
      try { open = !!require('./config.js').load().cfg.openSignup; } catch (e) {}
    }
    if (open) {
      out.push({ id: '가입 열림', level: 'WARN', ok: false,
        detail: '가입 코드를 껐습니다 — 주소를 아는 사람은 누구나 계정을 만듭니다. ' +
                '터널 주소는 무작위처럼 보여도 스캔당합니다. ' +
                '다시 닫으려면 serve --setup --close-signup' });
    }
  }
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

/* 규칙만 빠르게 보고 싶을 때가 있습니다 — 특히 운영자·보유기간처럼
   코드를 읽어서 판정하는 것들은 1초면 끝나는데, 그걸 보려고 20분짜리
   브라우저 검사를 다 기다릴 이유가 없습니다. 시험에서도 이 길을 씁니다. */
if (RULES_ONLY) {
  const bad = results.filter(r => r.level === 'BLOCK' && !r.ok);
  console.log('\n' + (bad.length ? '✗ 규칙 ' + bad.length + '건이 막습니다' : '✓ 규칙 전부 통과')
              + ' (검사는 건너뛰었습니다 — --rules)');
  process.exit(bad.length ? 1 : 0);
}

console.log('\n검사');
for (const c of CHECKS) {
  if (FAST && c.slow) { console.log(`  · ${c.id} — 건너뜀`); continue; }
  process.stdout.write(`  … ${c.id}`);
  const t0 = Date.now();
  /* 검사마다 걸리는 시간이 다릅니다. 20분을 모두에게 똑같이 물리다가,
     화면 전수 검사(7가지 상태 × 21화면)가 자라면서 그 벽에 닿았습니다.
     그리고 **시간 초과가 실패와 똑같이 찍혔습니다** — 화면에는 ✗ 만
     뜨고, 그 아래에는 검사가 죽기 직전까지 찍던 중간 출력이 붙어서,
     읽는 사람은 제품이 고장 난 줄 압니다. 실제로 한 번 그렇게 읽었습니다.
     따로 적어 두고, 시간 초과는 시간 초과라고 말합니다. */
  const limit = (c.minutes || 20) * 60 * 1000;
  const r = spawnSync(c.cmd[0], c.cmd.slice(1), {
    cwd: ROOT, encoding: 'utf8',
    env: Object.assign({}, process.env, { NODE_PATH }),
    timeout: limit
  });
  const secs = ((Date.now() - t0) / 1000).toFixed(0);
  const timedOut = r.error && r.error.code === 'ETIMEDOUT';
  const ok = !timedOut && r.status === 0;
  /* 실패했을 때 **무엇이** 실패했는지 보여 줍니다.
   *
   * 예전엔 출력의 마지막 세 줄만 잘라 왔습니다. 그런데 시험들은 마지막에
   * "통과 91 / 실패 2" 같은 요약을 찍으므로, 잘라 온 세 줄이 대개 그
   * 요약과 경고 문구였습니다 — 읽는 사람은 **둘 중 어느 것이 실패했는지
   * 알 수가 없습니다.** 실제로 그래서 한 번 진단을 못 했습니다.
   * 막는 검사가 "고치라" 고만 하고 어디를 고칠지 안 알려주면, 그
   * 검사는 반쯤 없는 것입니다.
   *
   * 이제 ✗ 가 붙은 줄을 먼저 모으고, 하나도 없을 때만 꼬리를 씁니다. */
  const outAll = ((r.stdout || '') + '\n' + (r.stderr || '')).trim().split('\n');
  const failLines = outAll.filter(l => /(^|\s)✗/.test(l)).slice(0, 8);
  const tail = timedOut
    ? (c.minutes || 20) + '분 안에 안 끝났습니다 — 검사가 느려진 것이지 앱이 고장 난 것이 ' +
      '아닐 수 있습니다. 직접 돌려서 확인하세요:  ' + c.cmd.join(' ')
    : (failLines.length ? failLines : outAll.slice(-3)).join('\n       ');
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
