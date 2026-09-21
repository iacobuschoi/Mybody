/* =============================================================================
 * tools/doctor.js — 내 컴퓨터가 이 서버를 띄울 수 있나
 *
 *   node tools/doctor.js
 *
 * preflight.js 는 "올릴 물건이 멀쩡한가" 를 봅니다. 이건 "올릴 자리가
 * 준비됐나" 를 봅니다. 둘은 다른 질문이고, 막히는 자리도 다릅니다 —
 * 코드는 멀쩡한데 노드가 낡아서 안 도는 경우가 훨씬 흔합니다.
 *
 * 규칙 두 가지
 *   1. 짐작하지 않습니다. "이 버전이면 될 것이다" 가 아니라 실제로
 *      불러 보고 열어 봅니다. 버전 번호로 판정하면 언젠가 틀립니다.
 *   2. "무엇이 없다" 로 끝내지 않습니다. 무엇을 하면 되는지를 같이
 *      적습니다. 없다는 말만 듣고 할 일을 모르면 거기서 멈춥니다.
 *
 * 노드 기본 기능만 씁니다 — 윈도우에서도 그대로 돌아야 합니다.
 * ========================================================================== */
'use strict';
/* node:sqlite 를 부르면 "experimental" 경고가 찍힙니다. 이 검사는
   바로 아래에서 그 기능이 되는지 안 되는지를 직접 말해 주므로,
   같은 이야기를 노드가 한 번 더 할 필요가 없습니다. 무엇보다
   "준비됐는지 보는 도구" 가 경고를 뱉으면 사람은 뭔가 잘못된 줄 압니다. */
process.removeAllListeners('warning');
const fs = require('node:fs');
const os = require('node:os');
const net = require('node:net');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const CONFIG = require('./config.js');

const ROOT = path.join(__dirname, '..');
const { cfg: CFG, from: FROM } = CONFIG.load();
const PORT = CFG.port;
const WIN = process.platform === 'win32';

const rows = [];
/** level: BLOCK(못 띄움) · WARN(띄워지지만 알고 가야 함) · INFO(선택) */
function add(level, ok, id, detail, todo) {
  rows.push({ level, ok, id, detail, todo: todo || null });
}

/* --- 1. 노드가 이 서버를 돌릴 수 있는가 --------------------------------- */
{
  const v = process.versions.node;
  /* 버전 숫자로 판정하지 않습니다. node:sqlite 는 22.5 에 플래그와 함께
     들어왔고 나중에 플래그가 빠졌는데, 정확한 경계는 배포판마다
     다릅니다. 숫자를 외워 두면 언젠가 틀린 말을 하게 됩니다.
     실제로 불러서 열어 보는 것이 확실합니다. */
  let ok = false, why = '';
  try {
    const { DatabaseSync } = require('node:sqlite');
    const d = new DatabaseSync(':memory:');
    d.exec('CREATE TABLE t (a INTEGER)');
    d.prepare('INSERT INTO t VALUES (?)').run(1);
    ok = d.prepare('SELECT a FROM t').get().a === 1;
    d.close();
  } catch (e) { why = String((e && e.message) || e).split('\n')[0]; }

  /* 메모리에서만 열어 보면 "노드는 되는데 내 데이터베이스 파일이 깨진"
     경우를 놓칩니다 — 전부 ✓ 를 주고 서버가 영문 스택으로 죽습니다.
     이미 파일이 있으면 그것도 열어 봅니다. */
  if (ok) {
    const dbPath = CFG.db ? path.resolve(CFG.db) : path.join(ROOT, 'server', 'mybody.db');
    if (fs.existsSync(dbPath)) {
      try {
        const { DatabaseSync } = require('node:sqlite');
        const d2 = new DatabaseSync(dbPath, { readOnly: true });
        d2.prepare('SELECT COUNT(*) c FROM sqlite_master').get();
        d2.close();
      } catch (e) {
        ok = false;
        why = '데이터베이스 파일을 못 엽니다 — ' + String((e && e.message) || e).split('\n')[0];
      }
    }
  }

  /* "LTS 를 받아 깔으세요" 만으로는 사람이 멈춥니다 — 어디서 무엇을
     어떻게 받는지가 OS 마다 다르고, 특히 윈도우는 깐 뒤에 **새 터미널을
     열어야** PATH 가 바뀝니다. 그걸 모르면 깔고도 같은 화면을 봅니다. */
  const INSTALL =
    process.platform === 'win32'
      ? '         winget install OpenJS.NodeJS.LTS\n' +
        '       (winget 이 없으면 https://nodejs.org 에서 LTS · Windows Installer (.msi) · x64)\n' +
        '       깐 뒤 **PowerShell 창을 닫고 새로 여세요.** 그래야 PATH 가 바뀝니다.\n' +
        '       그래도 옛 버전이면:  where.exe node   ← 여러 개 깔려 있는지 보세요'
      : process.platform === 'darwin'
        ? '         brew install node    (또는 https://nodejs.org 에서 LTS · macOS Installer)\n' +
          '       깐 뒤 터미널을 새로 여세요. 그래도 옛 버전이면:  which -a node'
        : '         https://nodejs.org 의 LTS, 또는 배포판 패키지(nodesource·fnm·nvm)\n' +
          '       깐 뒤 셸을 새로 여세요. 그래도 옛 버전이면:  which -a node';

  add('BLOCK', ok, '노드 버전', 'v' + v + (ok ? ' — 데이터베이스까지 잘 됩니다' : ' — ' + why),
    ok ? null
       : '이 노드로는 못 띄웁니다. 이 서버는 노드에 내장된 SQLite 를 쓰는데,\n' +
         '       그건 **노드 22.13 이상**에 있습니다 (LTS 를 받으면 충분합니다).\n' +
         INSTALL + '\n' +
         '       그 다음  node --version  이 바뀌었는지 보고 다시 치세요.');
}

/* --- 2. 포트가 비어 있는가 ----------------------------------------------- */
{
  const free = probePort(PORT);
  add('BLOCK', free.ok, PORT + '번 포트',
    free.ok ? '비어 있습니다'
            : '이미 쓰이고 있습니다 (' + free.why + ')',
    free.ok ? null
            : '이 서버가 이미 떠 있을 수도 있습니다 — http://localhost:' + PORT + ' 를 열어 보세요.\n' +
              '       다른 프로그램이라면 PORT=' + (PORT + 1) + ' 로 바꿔서 띄우면 됩니다.');
}

/* --- 3. 쓸 자리가 있는가 ------------------------------------------------- */
{
  const dbDir = CFG.db ? path.dirname(path.resolve(CFG.db))
                       : path.join(ROOT, 'server');
  let ok = false, why = '';
  try {
    fs.mkdirSync(dbDir, { recursive: true });
    const probe = path.join(dbDir, '.mybody-write-test');
    fs.writeFileSync(probe, 'x');
    fs.unlinkSync(probe);
    ok = true;
  } catch (e) { why = String((e && e.message) || e); }

  let free = null;
  try { const s = fs.statfsSync(dbDir); free = s.bavail * s.bsize; } catch (e) {}
  const gb = free != null ? (free / 1e9).toFixed(1) + 'GB 남음' : '남은 용량은 못 읽었습니다';

  add('BLOCK', ok, '쓸 자리', ok ? dbDir + ' · ' + gb : dbDir + ' 에 못 씁니다 — ' + why,
    ok ? null : '폴더 권한을 보거나, DB 를 쓸 수 있는 다른 경로로 지정하세요.');

  if (ok && free != null && free < 200e6) {
    add('WARN', false, '디스크 여유', (free / 1e6).toFixed(0) + 'MB 밖에 없습니다',
      '기록이 쌓이면 모자랍니다. 자리를 좀 비워 두세요.');
  }
}

/* --- 4. 가입 코드 -------------------------------------------------------- */
{
  const secret = (CFG.pairSecret || '').trim();
  const where = FROM.pairSecret || '설정 파일';

  if (!secret) {
    add('BLOCK', false, '가입 코드', '아직 없습니다',
      '한 번만 만들면 됩니다:\n' +
      '         node tools/serve.js --setup\n' +
      '       이 값을 아는 사람만 계정을 만들 수 있습니다. 친구에게 직접 주세요.');
  } else if (secret.length < 16) {
    add('WARN', false, '가입 코드', where + ' · ' + secret.length + '자',
      '짧습니다. 이 값 하나가 "아무나 가입" 을 막는 유일한 문입니다 — 32자쯤으로 다시 만드세요.');
  } else {
    add('BLOCK', true, '가입 코드', where + ' · ' + secret.length + '자');
  }
}

/* --- 5. 방침에 적을 운영자 ----------------------------------------------- */
{
  const owner = (CFG.owner || '').trim();
  const contact = (CFG.ownerContact || '').trim();
  add('WARN', !!(owner && contact), '방침 운영자',
    owner || contact ? [owner || '(이름 없음)', contact || '(연락처 없음)'].join(' · ')
                     : '아직 안 정했습니다',
    owner && contact ? null
      : '건강정보를 다루는 앱이라 개인정보처리방침에 "누구에게 말하면 되는지" 가 있어야 합니다.\n' +
        '         node tools/serve.js --setup --owner="이름" --contact="연락처"\n' +
        '       혼자만 쓸 거면 지금은 넘어가도 됩니다.');
}

/* --- 6. 배포 빌드 -------------------------------------------------------- */
{
  const rel = path.join(ROOT, 'release', 'index.html');
  const has = fs.existsSync(rel);
  let stale = false, age = '';
  if (has) {
    try {
      const built = fs.statSync(rel).mtimeMs;
      const newest = newestMtime(path.join(ROOT, 'prototype'));
      stale = newest > built;
      const days = Math.floor((Date.now() - built) / 86400000);
      age = days > 0 ? days + '일 전에 만들었습니다' : '오늘 만들었습니다';
    } catch (e) {}
  }
  add('WARN', has && !stale, '배포 빌드',
    !has ? 'release/ 가 없습니다' : (stale ? age + ' — 그 뒤로 원본이 바뀌었습니다' : age),
    has && !stale ? null
      : 'OWNER="이름" OWNER_CONTACT="연락처" node tools/build-release.js\n' +
        '       이걸 안 하고 띄우면 개발 빌드가 나갑니다 — 화면에 번호 배지가 전부 뜹니다.');
}

/* --- 7. 자동 판독 (선택) --------------------------------------------------
 *
 * "키가 있습니다" 만 보고 넘어가면, 키가 살아 있는지 · 잔액이 있는지 ·
 * 그 모델을 쓸 수 있는지 · 이 컴퓨터에서 api.anthropic.com 에 닿는지를
 * 아무도 안 봅니다. 그 넷 중 하나만 틀려도 결과는 같습니다 — 폰에서
 * 판독을 누른 뒤에야 502 를 만납니다. 주인이 실제로 그렇게 만났습니다.
 *
 * 그래서 여기서 **실제로 물어봅니다.** 모델 조회는 토큰을 안 쓰므로
 * 돈이 안 들고, 막혀 있으면 몇 초 안에 그렇다고 말합니다.
 * -------------------------------------------------------------------------- */
{
  const key = (CFG.anthropicKey || '').trim();
  const model = (process.env.OCR_MODEL || '').trim() || null;
  if (!key) {
    add('INFO', false, '자동 판독', '키가 없습니다',
      '없어도 앱은 그대로 돕니다 — 숫자를 직접 넣으면 됩니다.\n' +
      '       사진에서 자동으로 읽게 하려면:\n' +
      '         node tools/serve.js --setup --key\n' +
      '       (값을 안 붙이면 가려서 물어봅니다 — 셸 기록에 안 남습니다)\n' +
      '       키는 https://console.anthropic.com/settings/keys 에서 받습니다.');
  } else {
    const probe = checkOcrKey(key, model);
    if (probe.ok) {
      add('INFO', true, '자동 판독', probe.why);
    } else {
      /* 키를 넣어 둔 사람에게 이건 "선택" 이 아닙니다 — 쓰려고 넣었는데
         안 되는 상태입니다. 그래서 WARN 으로 올립니다. */
      /* 앤트로픽이 한 말을 그대로 보여 줍니다. 여기는 주인만 보는
         자리이고, 무엇을 해야 하는지가 대개 그 한 줄에 다 있습니다. */
      add('WARN', false, '자동 판독', probe.why,
        (probe.raw ? '앤트로픽이 한 말: ' + probe.raw + '\n' : '') +
        (probe.model ? '       물어본 모델: ' + probe.model + '\n' : '') +
        '       키를 바꾸려면:  node tools/serve.js --setup --key   (가려서 물어봅니다)\n' +
        '       더 싼 모델로:   OCR_MODEL=claude-sonnet-5 node tools/serve.js\n' +
        '       그냥 둬도 앱은 돕니다 — 숫자를 직접 넣으면 됩니다.');
    }
  }
}

/* --- 7-2. 폰 알림 (선택) --------------------------------------------------
 * 열쇠가 있어도 https 가 아니면 브라우저가 구독 자체를 막습니다. 그래서
 * 두 조건을 같이 봅니다 — 하나만 맞으면 "켰는데 안 온다" 가 됩니다.
 * -------------------------------------------------------------------------- */
{
  const hasKeys = !!(CFG.vapidPublic && CFG.vapidPrivate);
  const origin = (CFG.origin || '').trim();
  const https = /^https:\/\//.test(origin);
  let detail, hint = null;
  if (hasKeys && https) {
    detail = '열쇠가 있고 https 주소도 있습니다';
  } else if (hasKeys && !https) {
    detail = '열쇠는 있는데 https 주소가 없습니다';
    hint = '같은 와이파이의 http 주소에서는 브라우저가 알림을 막습니다.\n' +
           '       터널로 열고 --setup --origin="https://..." 을 넣으세요.';
  } else if (!hasKeys && https) {
    detail = 'https 주소는 있는데 알림 열쇠가 없습니다';
    hint = '만들려면: node tools/push-keys.js';
  } else {
    detail = '알림이 꺼져 있습니다';
    hint = '없어도 앱은 그대로 돕니다 — 친구 소식은 앱을 열면 보입니다.\n' +
           '       폰 알림까지 받으려면 터널(https) + node tools/push-keys.js.';
  }
  add('INFO', hasKeys && https, '폰 알림', detail, hint);
}

/* --- 8. 밖에서 접속 (선택) ------------------------------------------------ */
{
  const has = which('cloudflared') || which('tailscale');
  add('INFO', !!has, '밖에서 접속',
    has ? has + ' 가 깔려 있습니다' : '터널 도구가 없습니다',
    has ? null
      : '집 안(같은 와이파이)에서만 쓸 거면 필요 없습니다.\n' +
        '       밖에서 쓰거나 폰에 앱처럼 깔려면 터널이 필요합니다 — docs/DEPLOY.md 3번.');
}

/* --- 출력 ---------------------------------------------------------------- */
/* --make-pair 는 없앴습니다. 가입 코드를 만드는 자리가 두 군데면
   둘이 서로 다른 데 쓰게 됩니다 — 실제로 그랬습니다. serve --setup
   한 군데서만 만듭니다. */

console.log('');
console.log('내 컴퓨터가 이 서버를 띄울 수 있나');
console.log('  ' + os.type() + ' ' + os.release() + ' · node ' + process.versions.node);
console.log('');

const MARK = { BLOCK: '✗', WARN: '!', INFO: '·' };
rows.forEach(r => {
  const mark = r.ok ? '✓' : MARK[r.level];
  console.log('  ' + mark + ' ' + pad(r.id) + ' ' + r.detail);
  if (!r.ok && r.todo) r.todo.split('\n').forEach(l => console.log('       ' + l.replace(/^ {7}/, '')));
});

const blocked = rows.filter(r => r.level === 'BLOCK' && !r.ok);
const warned = rows.filter(r => r.level === 'WARN' && !r.ok);

console.log('');
console.log('─'.repeat(52));
console.log('');
if (blocked.length) {
  console.log('아직 못 띄웁니다. 위의 ✗ ' + blocked.length + '개를 먼저 해결하세요.');
  console.log('');
  process.exit(1);
}
console.log('띄울 수 있습니다.' + (warned.length ? '  (! ' + warned.length + '개는 알고 넘어가는 것입니다)' : ''));
console.log('');
if (CONFIG.exists()) {
  /* 설정을 이미 만들어 둔 사람에게 환경변수 다섯 개짜리 명령을 다시
     보여줄 이유가 없습니다. 짧은 길이 있으면 짧은 길만 알려줍니다.
     예전엔 "직접 띄우려면" 하고 PAIR_SECRET=$(cat ~/.mybody-pair) 를
     같이 찍었는데, 그 파일은 이제 아무 도구도 안 만듭니다 — 그대로
     치면 빈 값이 들어가서 서버가 안 뜹니다. 없는 길을 알려주느니
     안 알려주는 게 낫습니다. */
  console.log('  node tools/serve.js');
} else {
  console.log('  node tools/serve.js --setup     # 한 번만');
  console.log('  node tools/serve.js');
}
console.log('');
console.log('  그다음 브라우저에서 http://localhost:' + PORT);
/* 폰에서 칠 주소. 이걸 아무 데서도 안 알려줘서, 폰으로 쓰려는 사람은
   자기 컴퓨터의 내부 주소를 따로 찾아내야 했습니다. */
const lan = lanAddresses();
if (lan.length) {
  console.log('');
  lan.forEach(a => console.log('  폰에서는  http://' + a + ':' + PORT + '   (같은 와이파이)'));
  console.log('  이 주소로는 앱 설치 · 오프라인 · 복사가 안 됩니다 (https 가 아니라서).');
  console.log('  그 셋까지 되게 하려면 docs/START.md 의 "폰에서 쓰기" 를 보세요.');
} else {
  console.log('  폰에서도 쓰려면 docs/START.md 의 "폰에서 쓰기" 를 보세요.');
}
console.log('');

/* --- 잔손질 -------------------------------------------------------------- */
function pad(s) {
  /* 한글은 폭이 두 칸입니다. 그걸 안 세면 줄이 들쭉날쭉해집니다. */
  let w = 0;
  for (const ch of s) w += /[ᄀ-ᇿ　-〿가-힯＀-｠]/.test(ch) ? 2 : 1;
  return s + ' '.repeat(Math.max(0, 16 - w));
}

/** 같은 와이파이에서 폰이 칠 수 있는 주소들 */
function lanAddresses() {
  const out = [];
  try {
    const nets = os.networkInterfaces();
    Object.keys(nets).forEach(name => {
      (nets[name] || []).forEach(n => {
        if (n.family !== 'IPv4' || n.internal) return;
        /* 도커·VM 이 만드는 가상 인터페이스는 폰에서 못 닿습니다 */
        if (/^(docker|br-|veth|vboxnet|utun|tun|tap)/.test(name)) return;
        out.push(n.address);
      });
    });
  } catch (e) {}
  return out;
}

function probePort(p) {
  /* 실제로 열어 봅니다. lsof·netstat 은 OS 마다 다르고 윈도우엔 없습니다. */
  const res = spawnSync(process.execPath, ['-e', `
    const net = require('node:net');
    const s = net.createServer();
    s.once('error', e => { process.stdout.write('BUSY:' + e.code); process.exit(0); });
    s.listen(${p}, '0.0.0.0', () => { s.close(() => { process.stdout.write('FREE'); process.exit(0); }); });
  `], { encoding: 'utf8', timeout: 5000 });
  const out = (res.stdout || '').trim();
  if (out === 'FREE') return { ok: true };
  if (out.startsWith('BUSY:')) return { ok: false, why: out.slice(5) };
  return { ok: false, why: '확인하지 못했습니다' };
}

/** 판독 키가 실제로 살아 있는가. doctor 는 동기라서 자식에게 물어봅니다. */
function checkOcrKey(key, model) {
  const code =
    'const o=require(' + JSON.stringify(path.join(ROOT, 'server', 'ocr.js')) + ');' +
    'o.checkKey(process.env.K, process.env.M || null, {timeoutMs:7000})' +
    '.then(r=>{process.stdout.write(JSON.stringify(r));})' +
    '.catch(e=>{process.stdout.write(JSON.stringify({ok:false,reason:String(e&&e.message||e)}));});';
  const r = spawnSync(process.execPath, ['-e', code], {
    encoding: 'utf8', timeout: 12000,
    env: Object.assign({}, process.env, { K: key, M: model || '', NODE_NO_WARNINGS: '1' })
  });
  let j = null;
  try { j = JSON.parse((r.stdout || '').trim()); } catch (e) { j = null; }
  if (!j) {
    return { ok: false, why: '키가 살아 있는지 확인하지 못했습니다 (네트워크가 막혀 있을 수 있습니다)' };
  }
  return { ok: !!j.ok,
           why: (j.ok ? '키가 살아 있습니다 · ' : '') + (j.reason || ''),
           raw: j.raw || '', model: j.model || '' };
}

function which(cmd) {
  const probe = WIN ? spawnSync('where', [cmd], { encoding: 'utf8' })
                    : spawnSync('sh', ['-c', 'command -v ' + cmd], { encoding: 'utf8' });
  return probe.status === 0 && (probe.stdout || '').trim() ? cmd : null;
}

function newestMtime(dir) {
  let newest = 0;
  const walk = d => {
    for (const f of fs.readdirSync(d)) {
      const p = path.join(d, f);
      const st = fs.statSync(p);
      if (st.isDirectory()) walk(p);
      else if (st.mtimeMs > newest) newest = st.mtimeMs;
    }
  };
  try { walk(dir); } catch (e) {}
  return newest;
}
