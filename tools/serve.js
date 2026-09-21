/* =============================================================================
 * tools/serve.js — 한 줄로 띄우기
 *
 *   node tools/serve.js            설정을 읽어서 서버를 띄웁니다
 *   node tools/serve.js --setup    설정을 처음 한 번 만듭니다 (대화식)
 *   node tools/serve.js --show     지금 설정을 보여줍니다 (비밀은 가립니다)
 *
 * 왜 있나
 *   손으로 띄우려면 환경변수 다섯 개를 외워서 쳐야 했습니다. 하나를
 *   빠뜨리면 조용히 다른 일이 일어납니다 — STATIC 을 빼면 개발 빌드가
 *   나가고, OWNER 를 빼면 처방침의 운영자 칸이 빕니다. 외우게 하지 말고
 *   한 번 적어 두고 쓰게 합니다.
 *
 * 설정은 어디에
 *   ~/.mybody/config.json · 권한 600. 저장소 안에 두지 않습니다 —
 *   거기 두면 언젠가 git 에 들어가고, 가입 코드와 API 키가 같이 갑니다.
 *
 * 의존성은 없습니다. 노드 기본 기능만 씁니다 (윈도우 포함).
 * ========================================================================== */
'use strict';
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const readline = require('node:readline');
const crypto = require('node:crypto');
const { spawn, spawnSync } = require('node:child_process');
const CONFIG = require('./config.js');

const ROOT = path.join(__dirname, '..');
const FILE = CONFIG.FILE();

/** 설정은 tools/config.js 한 군데서만 읽습니다 — doctor 와 같은 답이 나오게. */
function readConfig() { return CONFIG.load().cfg; }

function writeConfig(cfg) {
  CONFIG.save(cfg);
  /* 윈도우에는 chmod 가 없습니다. 파일 권한을 못 좁히면 그 사실을
     말해 줍니다 — 조용히 넘어가면 안전하다고 오해합니다. */
  if (process.platform === 'win32') {
    console.log('  (윈도우에서는 파일 권한을 좁히지 못했습니다. 이 컴퓨터를 남과 같이 쓴다면');
    console.log('   ' + FILE + ' 의 접근 권한을 직접 확인하세요.)');
  }
}

function mask(v) { return v ? v.slice(0, 4) + '…' + String(v.length) + '자' : '(없음)'; }

/* --- --show ------------------------------------------------------------- */
if (process.argv.includes('--show')) {
  const c = readConfig();
  console.log('');
  console.log('설정 파일: ' + FILE + (fs.existsSync(FILE) ? '' : '  (아직 없습니다)'));
  console.log('');
  console.log('  포트           ' + c.port);
  console.log('  내보낼 폴더     ' + c.static + (c.static === 'prototype' ? '   ← 개발 빌드' : ''));
  console.log('  가입           ' + (c.openSignup
    ? '누구나 (코드 없음)   ← 주소를 아는 사람은 다 만듭니다'
    : '코드 필요'));
  console.log('  가입 코드       ' + mask(c.pairSecret) +
              (c.openSignup ? '   (지금은 안 씁니다)' : ''));
  console.log('  상시 접속       ' + (c.alwaysOn ? '컴퓨터를 계속 켜 둔다고 했습니다' : '(정한 것 없음)'));
  console.log('  운영자         ' + (c.owner || '(없음)'));
  console.log('  연락처         ' + (c.ownerContact || '(없음)'));
  console.log('  자동 판독 키    ' + mask(c.anthropicKey));
  console.log('  공개 주소       ' + (c.origin || '(같은 출처만)'));
  console.log('  터널 뒤         ' + (c.trustProxy ? '예' : '아니오'));
  console.log('');
  process.exit(0);
}

/* --- --setup ------------------------------------------------------------- */
if (process.argv.includes('--setup')) {
  setup().then(() => process.exit(0)).catch(e => {
    console.error('\n설정을 못 만들었습니다: ' + ((e && e.message) || e));
    process.exit(1);
  });
} else {
  main();
}

/** --owner="이름" 같은 깃발을 읽습니다. 대화식이 안 되는 자리(스크립트 ·
    검사 · 원격 셸)에서도 설정을 만들 수 있어야 합니다. */
function flags() {
  const out = {};
  process.argv.slice(2).forEach(a => {
    const m = /^--([a-zA-Z-]+)(?:=([\s\S]*))?$/.exec(a);
    if (m) out[m[1]] = m[2] == null ? true : m[2];
  });
  return out;
}

async function setup() {
  const cur = readConfig();
  const f = flags();
  const cfg0 = Object.assign({}, cur);
  if (!cfg0.pairSecret) cfg0.pairSecret = crypto.randomBytes(16).toString('hex');

  /* 깃발로 값을 준 사람에게는 묻지 않습니다.
   *
   * 예전에는 터미널이면 무조건 질문 흐름으로 갔습니다. 그래서
   * `node tools/serve.js --setup --key="sk-..."` 를 치면 깃발이 조용히
   * 무시되고 운영자 이름부터 다시 물었습니다 — doctor 와 문서가 바로
   * 그 명령을 알려 주고 있는데요. 시킨 대로 안 하면서 아무 말도 안 하는
   * 것이 제일 나쁩니다.
   *
   * 값을 준 항목만 바꾸고, 무엇이 바뀌었는지 찍고 끝냅니다. */
  const GIVEN = ['owner', 'contact', 'no-owner', 'port', 'key', 'workspace', 'origin',
                 'static', 'open-signup', 'close-signup', 'always-on'].filter(k => k in f);

  /* `--key` 를 값 없이 주면 **가려서 물어봅니다.**
   *
   * --key="sk-ant-..." 는 한 줄로 끝나서 편한데, 그 값이 셸 기록에
   * 그대로 남습니다 (윈도우는 ConsoleHost_history.txt). 주인은 방금
   * 키가 새서 한 번 갈아 끼운 참입니다 — 같은 자리에 또 흘리면 안 됩니다.
   *
   * 그렇다고 질문 흐름 전체를 지나가게 하면 운영자 · 포트 · 공개 주소를
   * 다 다시 물어야 합니다. 키 하나만 바꾸러 온 사람에게 그건 벽입니다.
   * 그래서 키만 묻고 끝냅니다. */
  if (process.stdin.isTTY && f.key === true) {
    const rl0 = readline.createInterface({ input: process.stdin, output: process.stdout });
    const askHidden = (q) => new Promise(res => {
      const out = rl0.output;
      let muted = false;
      const orig = out.write.bind(out);
      out.write = function (chunk) { if (muted) { orig('*'); return true; } return orig(chunk); };
      orig(q + ' ');
      muted = true;
      rl0.question('', a2 => { muted = false; out.write = orig; orig('\n'); res((a2 || '').trim()); });
    });
    console.log('');
    console.log('자동 판독 키를 넣습니다. 붙여넣어도 화면에는 * 만 보입니다.');
    console.log('  지금 키: ' + mask(cfg0.anthropicKey));
    console.log('  (지우려면 "없음", 그대로 두려면 그냥 엔터)');
    const v = await askHidden('  ANTHROPIC_API_KEY:');
    rl0.close();
    if (!v) { console.log('  그대로 뒀습니다.'); return; }
    const cfg = Object.assign({}, cfg0);
    cfg.anthropicKey = /^(없음|없다|지움|none|delete|-)$/i.test(v) ? '' : v;
    writeConfig(cfg);
    console.log('  → ' + (cfg.anthropicKey ? '키를 넣었습니다 (' + mask(cfg.anthropicKey) + ').'
                                            : '키를 지웠습니다.'));
    console.log('');
    console.log('  확인:   node tools/doctor.js      ← 키가 진짜 되는지 물어봅니다');
    console.log('  띄우기: node tools/launch.js');
    console.log('');
    return;
  }

  /* 터미널이 아니면(파이프·스크립트) 물어볼 수가 없습니다. 예전에는
     여기서 질문을 던지다 stdin 이 끝나 버려 설정 파일도 없이 죽었습니다 —
     사용자는 뭐가 저장됐는지 모른 채 남습니다. 깃발로 받고 끝냅니다. */
  if (!process.stdin.isTTY || GIVEN.length) {
    const cfg = Object.assign(cfg0, {
      owner: f['no-owner'] ? '' : (f.owner != null && f.owner !== true ? String(f.owner) : cfg0.owner),
      ownerContact: f['no-owner'] ? '' : (f.contact != null && f.contact !== true ? String(f.contact) : cfg0.ownerContact),
      ownerOmitted: f['no-owner'] ? true : cfg0.ownerOmitted,
      openSignup: f['open-signup'] ? true : (f['close-signup'] ? false : cfg0.openSignup),
      alwaysOn: f['always-on'] ? true : cfg0.alwaysOn,
      port: f.port ? Number(f.port) || cfg0.port : cfg0.port,
      anthropicKey: f.key != null && f.key !== true ? String(f.key) : cfg0.anthropicKey,
      anthropicWorkspace: f.workspace != null && f.workspace !== true
        ? String(f.workspace) : cfg0.anthropicWorkspace,
      origin: f.origin != null && f.origin !== true ? String(f.origin) : cfg0.origin,
      static: f.static === 'prototype' ? 'prototype' : cfg0.static
    });
    cfg.trustProxy = !!cfg.origin;
    writeConfig(cfg);
    console.log('설정을 저장했습니다: ' + FILE);
    console.log('  운영자 ' + (cfg.owner || (cfg.ownerOmitted ? '(안 적기로 함)' : '(없음)')) +
                ' · 연락처 ' + (cfg.ownerContact || '(없음)') +
                ' · 포트 ' + cfg.port);
    /* 깃발로 고친 것을 하나씩 확인해 줍니다. "저장했습니다" 만 찍으면
       오타 난 깃발이 조용히 무시된 것과 구분이 안 됩니다.
       키는 가려서 찍습니다 — 터미널 기록에 남습니다. */
    if (GIVEN.length) {
      GIVEN.forEach(k => {
        if (k === 'key') console.log('  자동 판독 키   ' + mask(cfg.anthropicKey));
        else if (k === 'origin') console.log('  공개 주소      ' + (cfg.origin || '(없음)'));
        else if (k === 'static') console.log('  내보낼 폴더    ' + cfg.static);
        else if (k === 'always-on') console.log('  상시 접속      켜 둔다고 했습니다');
        else if (k === 'open-signup' || k === 'close-signup') {
          console.log('  가입           ' + (cfg.openSignup ? '누구나 (코드 없음)' : '코드 필요'));
        }
      });
      if (cfg.anthropicKey && GIVEN.indexOf('key') >= 0) {
        console.log('');
        console.log('  서버가 이미 떠 있으면 껐다 켜야 새 키를 씁니다.');
      }
    }
    if (cfg.openSignup) {
      console.log('');
      console.log('  가입   누구나 (가입 코드 없음)  ← 주소를 아는 사람은 다 만듭니다');
      console.log('  닫으려면: node tools/serve.js --setup --close-signup');
    } else if (!cur.pairSecret) {
      console.log('');
      console.log('  가입 코드를 새로 만들었습니다 — 이 값을 아는 사람만 계정을 만들 수 있습니다:');
      console.log('    ' + cfg.pairSecret);
    }
    console.log('');
    console.log('  바꾸려면: node tools/serve.js --setup --owner="이름" --contact="연락처"');
    console.log('            이름을 안 걸 거면: --no-owner');
    return;
  }

  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  const ask = (q, def) => new Promise(res => {
    rl.question(q + (def ? ' [' + def + ']' : '') + ' ', a => res((a || '').trim() || def || ''));
  });

  /* 비밀을 받을 때는 화면에 안 찍습니다.
   *
   * 예전엔 그냥 ask() 로 받았습니다. 그래서 붙여넣은 API 키가 터미널에
   * 그대로 찍혔고, 스크롤백과 PowerShell 기록에 남았습니다. 주인이
   * 실제로 그 화면을 통째로 복사해 보냈습니다 — 키가 새는 경로로
   * 이보다 쉬운 게 없습니다.
   *
   * 노드 readline 에는 가리기 옵션이 없어서, 출력이 지나가는 자리를
   * 잠깐 막습니다. 되돌리는 것을 finally 에 두어야 합니다 — 안 그러면
   * 중간에 던졌을 때 그 뒤 입력이 전부 안 보이게 됩니다. */
  const askSecret = (q) => new Promise(res => {
    const out = rl.output;
    let muted = false;
    const orig = out.write.bind(out);
    out.write = function (chunk) {
      if (muted) { orig('*'); return true; }
      return orig(chunk);
    };
    orig(q + ' ');
    muted = true;
    rl.question('', a => {
      muted = false;
      out.write = orig;
      orig('\n');
      res((a || '').trim());
    });
  });

  console.log('');
  console.log('Mybody 서버 설정 — 한 번만 하면 됩니다.');
  console.log('그냥 엔터를 치면 대괄호 안의 값을 씁니다.');
  console.log('');

  const cfg = cfg0;

  if (cfg.openSignup) {
    console.log('가입을 열어 둔 상태입니다 — 주소를 아는 사람은 누구나 계정을 만듭니다.');
    console.log('닫으려면:  node tools/serve.js --setup --close-signup');
    console.log('');
  } else if (!cur.pairSecret) {
    console.log('가입 코드를 새로 만들었습니다:');
    console.log('');
    console.log('    ' + cfg.pairSecret);
    console.log('');
    console.log('이 값을 아는 사람만 계정을 만들 수 있습니다. 친구에게 직접 주세요.');
    console.log('여기 말고 다른 데 한 번 더 적어 두세요.');
    console.log('');
  } else {
    console.log('가입 코드는 이미 있습니다 (' + mask(cfg.pairSecret) + ').');
    console.log('');
  }

  console.log('개인정보처리방침에 적을 이름과 연락처입니다.');
  console.log('이 앱은 몸에 대한 숫자를 다루니까, 받는 사람이 "누구에게 말하면 되는지"');
  console.log('를 알 수 있어야 합니다. 본명이 아니어도 됩니다.');
  console.log('  아무것도 안 적고 갈 수도 있습니다. 그 때는 "없음" 이라고 쓰세요.');
  const ownerIn = await ask('  운영자 이름:', cfg.owner || 'Mybody 운영자');
  if (/^(없음|없다|안 ?적음|none|skip|-)$/i.test(ownerIn.trim())) {
    /* 빈칸으로 두는 것과 안 적기로 정하는 것은 다른 일입니다.
       빈칸은 깜빡한 것일 수 있어서 배포 전 점검이 막습니다. 여기서
       고른 것은 결정이므로 기록에 남기고 통과시킵니다 — 대신
       "알고 올리는 것" 목록에 줄이 남습니다. */
    cfg.owner = ''; cfg.ownerContact = ''; cfg.ownerOmitted = true;
    console.log('  → 안 적기로 했습니다. 방침에는 "이 주소를 알려준 사람에게');
    console.log('     직접 말해 주세요" 로 나갑니다.');
  } else {
    cfg.owner = ownerIn; cfg.ownerOmitted = false;
    console.log('  연락처는 메일이든 오픈채팅 링크든, 실제로 읽는 곳이면 됩니다.');
    console.log('  비워 두면 방침에 "주소를 알려준 사람에게 직접 말하세요" 라고 나갑니다.');
    cfg.ownerContact = await ask('  연락처:', cfg.ownerContact);
  }
  console.log('');

  cfg.port = Number(await ask('  포트:', String(cfg.port))) || 8080;
  console.log('');

  console.log('사진에서 숫자를 자동으로 읽게 하려면 Anthropic API 키가 필요합니다.');
  console.log('없어도 앱은 그대로 씁니다 — 숫자를 직접 넣으면 됩니다. 비워도 됩니다.');
  /* 이미 넣어 둔 키를 기본값으로 화면에 찍으면, 설정을 다시 돌릴 때마다
     터미널 기록에 키가 남습니다. 남이 어깨 너머로 보기도 하고요.
     가려서 보여주고, 그냥 엔터면 있던 값을 그대로 둡니다. */
  console.log(cfg.anthropicKey
    ? '  지금 키: ' + mask(cfg.anthropicKey) + '  (그대로 두려면 그냥 엔터, 지우려면 "없음")'
    : '  (없으면 그냥 엔터)');
  /* 입력은 화면에 안 찍힙니다 — 붙여넣어도 * 만 보입니다. */
  const keyIn = await askSecret('  ANTHROPIC_API_KEY:');
  if (!keyIn) { /* 엔터 — 있던 값 그대로 */ }
  else if (/^(없음|없다|지움|none|delete|-)$/i.test(keyIn)) {
    cfg.anthropicKey = '';
    console.log('  → 키를 지웠습니다. 자동 판독은 꺼집니다.');
  } else {
    cfg.anthropicKey = keyIn;
    console.log('  → 키를 넣었습니다 (' + mask(cfg.anthropicKey) + ').');
  }
  console.log('');

  console.log('밖에서(터널로) 열 거면 그 주소를 적어 주세요. 집 안에서만 쓸 거면 비워 두세요.');
  console.log('  예: https://mybody.내도메인.com');
  console.log('  **내가 가진 주소만** 적으세요. 남의 도메인을 적으면 브라우저가 요청을');
  console.log('  막고, 폰 알림이 그 주소를 연락처라고 주장하게 됩니다.');
  console.log('  지우려면 "없음". 그냥 엔터는 있던 값을 그대로 둡니다.');
  const originIn = await ask('  공개 주소:', cfg.origin);
  /* 한 번 넣으면 **지울 방법이 없었습니다** — 빈 입력은 있던 값을 그대로
     두니까요. 잘못 넣은 사람이 되돌릴 길이 없는 설정은 설정이 아닙니다. */
  cfg.origin = /^(없음|없다|지움|none|delete|-)$/i.test(originIn.trim()) ? '' : originIn;
  cfg.trustProxy = !!cfg.origin;
  if (cfg.origin) {
    try {
      const u = new URL(cfg.origin);
      if (u.protocol !== 'https:') {
        console.log('  ! https 가 아닙니다 — 폰 알림과 앱 설치가 안 됩니다.');
      }
    } catch (e) {
      console.log('  ! 주소 형식이 아닙니다 (https://... 로 적어야 합니다).');
    }
  }
  console.log('');

  rl.close();
  writeConfig(cfg);
  console.log('저장했습니다: ' + FILE);
  console.log('');
  console.log('이제 이것만 치면 됩니다:');
  console.log('');
  console.log('    node tools/serve.js');
  console.log('');
}

function main() {
  const cfg = readConfig();

  if (!cfg.pairSecret) {
    console.error('');
    console.error('아직 설정이 없습니다. 한 번만 하면 됩니다:');
    console.error('');
    console.error('    node tools/serve.js --setup');
    console.error('');
    process.exit(1);
  }

  /* 띄우기 전에 이 컴퓨터가 준비됐는지 봅니다. 막히는 것이 있으면
     doctor 가 무엇을 하면 되는지까지 말해 줍니다 — 여기서 같은 말을
     두 벌로 적지 않습니다. */
  const env = envFor(cfg);
  const doc = spawnSync(process.execPath, [path.join(__dirname, 'doctor.js')],
    { cwd: ROOT, env: env, encoding: 'utf8' });
  if (doc.status !== 0) {
    process.stdout.write(doc.stdout || '');
    process.stderr.write(doc.stderr || '');
    process.exit(1);
  }

  /* 배포 빌드가 없거나 원본보다 낡았으면 다시 만듭니다.
     "빌드하는 걸 깜빡해서 옛 화면이 나간다" 는 혼자 못 알아챕니다. */
  if (cfg.static === 'release' && needsBuild()) {
    console.log('배포 빌드를 새로 만듭니다...');
    const b = spawnSync(process.execPath, [path.join(__dirname, 'build-release.js')],
      { cwd: ROOT, env: env, encoding: 'utf8' });
    process.stdout.write(b.stdout || '');
    if (b.status !== 0) {
      process.stderr.write(b.stderr || '');
      console.error('빌드가 실패했습니다. 위 내용을 보세요.');
      process.exit(1);
    }
  }

  console.log('');
  const child = spawn(process.execPath, [path.join(ROOT, 'server', 'server.js')],
    { cwd: ROOT, env: env, stdio: 'inherit' });

  const bye = () => { try { child.kill(); } catch (e) {} };
  process.on('SIGINT', bye);
  process.on('SIGTERM', bye);
  child.on('exit', code => process.exit(code == null ? 0 : code));
}

function envFor(cfg) {
  const e = Object.assign({}, process.env);
  e.PAIR_SECRET = cfg.pairSecret;
  e.PORT = String(cfg.port);
  e.STATIC = path.join(ROOT, cfg.static);
  if (cfg.db) e.DB = cfg.db;
  if (cfg.owner) e.OWNER = cfg.owner;
  if (cfg.ownerContact) e.OWNER_CONTACT = cfg.ownerContact;
  if (cfg.anthropicKey) e.ANTHROPIC_API_KEY = cfg.anthropicKey;
  if (cfg.anthropicWorkspace) e.ANTHROPIC_WORKSPACE_ID = cfg.anthropicWorkspace;
  if (cfg.openSignup) e.OPEN_SIGNUP = '1';
  if (cfg.vapidPublic && cfg.vapidPrivate) {
    e.VAPID_PUBLIC = cfg.vapidPublic;
    e.VAPID_PRIVATE = cfg.vapidPrivate;
  }
  if (cfg.origin) e.ORIGIN = cfg.origin;
  if (cfg.trustProxy) e.TRUST_PROXY = '1';
  /* node:sqlite 가 시작할 때마다 "experimental" 경고를 찍습니다.
     맞는 말이지만, 서버를 띄울 때마다 영문 경고가 보이면 쓰는 사람은
     뭔가 잘못된 줄 압니다.
     이 스위치는 그 경고만이 아니라 노드의 경고를 전부 끕니다 —
     이 명령으로 띄운 서버 한 프로세스 안에서만입니다. 서버가 하는
     말(포트 충돌 · 개발 빌드 경고 등)은 console 로 찍으므로 그대로
     보입니다. 개발 중에 노드 경고를 보고 싶으면 serve.js 말고
     server.js 를 직접 띄우세요. */
  e.NODE_NO_WARNINGS = '1';
  return e;
}

function needsBuild() {
  const rel = path.join(ROOT, 'release', 'index.html');
  if (!fs.existsSync(rel)) return true;

  /* 원본 파일만 보면 "설정에서 운영자 이름을 바꿨는데 방침에는 옛 이름이
     그대로" 인 상태가 됩니다. 이름은 빌드할 때 방침에 박히는데, 이름을
     바꿔도 prototype/ 은 안 건드려지니까요. 실제로 박힌 값을 봅니다. */
  const cfg = readConfig();
  const priv = path.join(ROOT, 'release', 'privacy.html');
  if (!fs.existsSync(priv)) return true;
  const txt = fs.readFileSync(priv, 'utf8');
  if (cfg.owner && !txt.includes(cfg.owner)) return true;
  if (cfg.ownerContact && !txt.includes(cfg.ownerContact)) return true;
  /* 연락처를 지웠으면 기본 문구로 돌아가 있어야 합니다 */
  if (!cfg.ownerContact && !txt.includes('따로 적어 두지 않았습니다')) return true;

  const built = fs.statSync(rel).mtimeMs;
  let newest = 0;
  const walk = d => {
    for (const f of fs.readdirSync(d)) {
      const p = path.join(d, f);
      const st = fs.statSync(p);
      if (st.isDirectory()) walk(p); else if (st.mtimeMs > newest) newest = st.mtimeMs;
    }
  };
  try { walk(path.join(ROOT, 'prototype')); } catch (e) {}
  return newest > built;
}
