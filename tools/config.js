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
  anthropicKey: '',
  origin: '',
  trustProxy: false,
  db: ''
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
  take('anthropicKey', 'ANTHROPIC_API_KEY');
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

module.exports = { load, save, exists, DEFAULTS, FILE, LEGACY_PAIR };
