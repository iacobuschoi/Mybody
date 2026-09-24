/* =============================================================================
 * tools/config.js — 설정을 어디서 읽는지 한 군데서 정합니다
 *
 * doctor 와 serve 가 각자 설정을 읽었더니, 한쪽은 ~/.mybody/config.json 을
 * 보고 다른 쪽은 ~/.mybody-pair 만 봤습니다. serve --setup 으로 설정을
 * 다 해 놓고도 doctor 는 "가입 코드가 없습니다" 라고 막았습니다.
 * 같은 질문에 두 대답이 나오면 둘 다 못 믿게 됩니다 — 그래서 한 군데
 * 두고 둘 다 여기를 봅니다.
 *
 * 읽는 순서 (앞이 이깁니다)
 *   1. 환경변수 — 한 번만 다르게 띄우고 싶을 때
 *   2. ~/.mybody/config.json — serve --setup 이 만드는 것
 *   3. ~/.mybody-pair — 예전에 가입 코드만 파일로 만들어 둔 사람
 * ========================================================================== */
'use strict';
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const DIR = () => path.join(os.homedir(), '.mybody');
const FILE = () => path.join(DIR(), 'config.json');
const LEGACY_PAIR = () => path.join(os.homedir(), '.mybody-pair');

const DEFAULTS = {
  port: 8080,
  static: 'release',
  pairSecret: '',
  owner: '',
  ownerContact: '',
  /* 이름을 안 걸기로 **정했다** 는 표시. 빈칸(깜빡함)과 구분하려고
     따로 둡니다 — preflight 의 "방침 운영자" 가 이 둘을 다르게 봅니다. */
  ownerOmitted: false,
  /* 폰 알림(웹푸시) 열쇠. 없으면 알림 기능 전체가 꺼진 채로 돕니다. */
  vapidPublic: '',
  vapidPrivate: '',
  /* 가입 코드를 없애기로 **정했다** 는 표시. 빈 값(깜빡함)과 구분합니다 —
     빈 값이면 서버가 아예 안 뜨고, 이건 켜야 열립니다. */
  openSignup: false,
  /* 컴퓨터를 계속 켜 두기로 정했다는 표시. 배포 전 점검의 "상시 접속"
     경고가 이걸 보고 잔소리를 멈춥니다. */
  alwaysOn: false,
  anthropicKey: '',
  /* 조직 전체 키를 쓸 때만 필요합니다. 워크스페이스 안에서 만든
     키라면 비워 두세요 — 그쪽이 낫습니다(지출 한도를 걸 수 있습니다). */
  anthropicWorkspace: '',
  /* 어느 모델로 읽을 것인가. 비워 두면 server/ocr.js 의 기본값입니다.
     tools/ocr-compare.js 로 자기 결과지에 재 보고 정하는 값입니다 —
     제일 비싼 것이 항상 제일 잘 읽는 건 아니고, 값은 5배 차이납니다. */
  anthropicModel: '',
  origin: '',
  trustProxy: false,
  db: '',
  /* 앱 안 업데이트 안내(GET /api/version) — tools/app-version.js 로 고칩니다.
     가게마다 따로 둡니다. 같은 판이라도 올라가는 날이 다릅니다 — APK 는
     릴리스 바로 뒤, 플레이는 출시 뒤, 앱스토어는 심사가 끝난 뒤입니다.
     빈 값이면 그 가게로 깐 사람에게는 새 판 안내를 안 합니다. */
  appLatestAppStore: '',
  appLatestPlay: '',
  appLatestApk: '',
  /* 이보다 낮은 앱은 "이 서버와 안 맞습니다" 를 봅니다(닫을 수 없는 안내).
     서버가 옛 앱을 더는 못 받게 됐을 때만 올립니다. */
  appMin: '',
  /* 업데이트 단추가 여는 주소. 비워 두면 server/appversion.js 의 기본
     주소입니다. 기본 주소를 여기 적지 않는 이유: 다른 도구가 설정을
     저장할 때 이 값들이 파일에 그대로 굳습니다. 그러면 나중에 코드의
     주소를 고쳐도 이미 저장한 사람은 옛 주소를 계속 내보냅니다. */
  appUrlAppStore: '',
  appUrlPlay: '',
  appUrlApk: ''
};

function readFileJson() {
  try { return JSON.parse(fs.readFileSync(FILE(), 'utf8')) || {}; } catch (e) { return {}; }
}

/** @returns {{cfg: object, from: object}} from 은 항목마다 어디서 온 값인지 */
function load() {
  const saved = readFileJson();
  const cfg = Object.assign({}, DEFAULTS, saved);
  const from = {};
  Object.keys(saved).forEach(k => { from[k] = '설정 파일'; });

  if (!cfg.pairSecret) {
    try {
      const v = fs.readFileSync(LEGACY_PAIR(), 'utf8').trim();
      if (v) { cfg.pairSecret = v; from.pairSecret = LEGACY_PAIR(); }
    } catch (e) {}
  }

  const env = process.env;
  const take = (key, envName, cast) => {
    const v = (env[envName] || '').trim();
    if (!v) return;
    cfg[key] = cast ? cast(v) : v;
    from[key] = '환경변수 ' + envName;
  };
  take('pairSecret', 'PAIR_SECRET');
  take('owner', 'OWNER');
  take('ownerContact', 'OWNER_CONTACT');
  if (/^(1|true|yes)$/i.test(String(process.env.OWNER_OMIT || ''))) {
    cfg.ownerOmitted = true; from.ownerOmitted = '환경변수 OWNER_OMIT';
  }
  if (/^(1|true|yes)$/i.test(String(process.env.OPEN_SIGNUP || ''))) {
    cfg.openSignup = true; from.openSignup = '환경변수 OPEN_SIGNUP';
  }
  if (/^(1|true|yes)$/i.test(String(process.env.ALWAYS_ON || ''))) {
    cfg.alwaysOn = true; from.alwaysOn = '환경변수 ALWAYS_ON';
  }
  take('anthropicKey', 'ANTHROPIC_API_KEY');
  take('anthropicWorkspace', 'ANTHROPIC_WORKSPACE_ID');
  take('anthropicModel', 'OCR_MODEL');
  take('origin', 'ORIGIN');
  take('db', 'DB');
  take('port', 'PORT', v => Number(v) || DEFAULTS.port);
  if ((env.STATIC || '').trim()) { cfg.static = env.STATIC.trim(); from.static = '환경변수 STATIC'; }
  if (env.TRUST_PROXY === '1') { cfg.trustProxy = true; from.trustProxy = '환경변수 TRUST_PROXY'; }

  return { cfg: cfg, from: from };
}

function save(cfg) {
  fs.mkdirSync(DIR(), { recursive: true, mode: 0o700 });
  fs.writeFileSync(FILE(), JSON.stringify(cfg, null, 2) + '\n', { mode: 0o600 });
  try { fs.chmodSync(FILE(), 0o600); } catch (e) {}
}

function exists() { return fs.existsSync(FILE()); }

/** 파일을 **엄격하게** 읽습니다. 없으면 {}, 있는데 JSON 객체가 아니면 던집니다.
 *
 *  load() 는 망가진 파일을 빈 설정으로 봅니다 — 서버를 띄울 때는 그게
 *  맞습니다. 그런데 GET /api/version 은 빈 값을 "주인이 안내를 전부
 *  지웠다" 로 내보냅니다. 거기서는 망가진 것과 빈 것을 갈라야 합니다. */
function readFileStrict() {
  let raw;
  try { raw = fs.readFileSync(FILE(), 'utf8'); }
  catch (e) { if (e && e.code === 'ENOENT') return {}; throw e; }
  const j = JSON.parse(raw);
  if (!j || typeof j !== 'object' || Array.isArray(j)) throw new Error('설정 파일이 JSON 객체가 아닙니다');
  return j;
}

/** 환경변수를 섞지 않은, **파일에 실제로 적힌 것**. setup 이 씁니다 —
 *  거기서는 "지금 셸에 뭐가 떠 있나" 가 아니라 "저장된 게 뭔가" 가
 *  기준이어야 합니다. */
function loadFile() { return readFileJson(); }

module.exports = { load, loadFile, readFileStrict, save, exists, DEFAULTS, FILE, LEGACY_PAIR };
