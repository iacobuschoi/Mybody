/* =============================================================================
 * server/server.js — Mybody 자가호스팅 서버 (의존성 0, Node 내장 기능만)
 *
 *   node server/server.js
 *   PORT=8080 DB=./mybody.db STATIC=../prototype node server/server.js
 *
 * 권한은 전부 서버에서 겁니다. 클라이언트가 보내는 "나는 누구다"를 믿지 않고
 * 토큰으로만 판단합니다.
 * ========================================================================== */
'use strict';
/* 노드가 너무 오래됐으면 여기서 사람 말로 끝냅니다.
 *
 * 이 서버는 노드에 내장된 SQLite 를 씁니다. 옛 노드에는 없어서,
 * 예전에는 첫 줄부터 이런 게 쏟아졌습니다:
 *
 *   Error [ERR_UNKNOWN_BUILTIN_MODULE]: No such built-in module: node:sqlite
 *       at Module._load (node:internal/modules/cjs/loader:1031:13)
 *       ...
 *
 * 개발자가 아니면 이게 "노드를 새로 깔아라" 라는 뜻인 줄 모릅니다.
 * 서버를 처음 띄우는 사람이 제일 먼저 만날 수 있는 벽이라 먼저 받습니다. */
try {
  require('node:sqlite');
} catch (e) {
  console.error('');
  console.error('이 Node 로는 못 띄웁니다 (지금 ' + process.version + ').');
  console.error('');
  console.error('  이 서버는 Node 에 내장된 데이터베이스를 씁니다. 오래된 Node 에는 없습니다.');
  console.error('  https://nodejs.org 에서 LTS 를 받아 다시 깔고, 새 터미널을 열어');
  console.error('  node --version 이 바뀌었는지 확인하세요.');
  console.error('');
  console.error('  자세한 확인은:  node tools/doctor.js');
  console.error('');
  process.exit(1);
}

const http = require('node:http');
const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const { open, makeApi, str } = require('./db.js');
const { runOcr: callOcr } = require('./ocr.js');
const PUSH = require('./push.js');
const APPVER = require('./appversion.js');

/* --- 저장해 둔 설정을 읽어 옵니다 ------------------------------------------
 *
 * 이게 없어서 조용히 깨지는 길이 있었습니다.
 *
 * 설정(판독 키 · 워크스페이스 · 가입 코드 …)은 ~/.mybody/config.json 에
 * 저장되는데, 그걸 환경변수로 바꿔 주는 곳이 tools/serve.js 하나뿐이었습니다.
 * 그런데 이 파일의 맨 위 주석도, server/README.md 도, docs/DEPLOY.md 도,
 * 배포 전 점검도 전부 `node server/server.js` 를 치라고 안내합니다.
 * **그 길로 띄우면 키도 워크스페이스도 통째로 사라집니다** — 서버는
 * 멀쩡히 뜨고, 판독만 503 이나 400 으로 죽습니다. 화면에는 "이 서버에는
 * 판독 키가 설정되지 않았습니다" 가 나오는데, 주인은 방금 키를 넣었으니
 * 그 말을 믿을 수가 없습니다.
 *
 * 순서는 그대로 둡니다: **환경변수가 먼저**입니다. 한 번만 다르게
 * 띄우고 싶을 때 쓰는 길이라 설정 파일이 그걸 덮으면 안 됩니다.
 * 여기서는 환경변수에 **없는 것만** 채웁니다.
 *
 * tools/ 가 없어도(server/ 만 떼어 옮긴 경우) 그냥 넘어갑니다.
 * -------------------------------------------------------------------------- */
(function loadSavedConfig() {
  let cfg;
  try { cfg = require('../tools/config.js').load().cfg; } catch (e) { return; }
  const put = (envName, v) => {
    if (v === undefined || v === null || v === '') return;
    if ((process.env[envName] || '').trim()) return;   // 환경변수가 이깁니다
    process.env[envName] = String(v);
  };
  put('PAIR_SECRET', cfg.pairSecret);
  put('ANTHROPIC_API_KEY', cfg.anthropicKey);
  put('ANTHROPIC_WORKSPACE_ID', cfg.anthropicWorkspace);
  put('OCR_MODEL', cfg.anthropicModel);
  put('VAPID_PUBLIC', cfg.vapidPublic);
  put('VAPID_PRIVATE', cfg.vapidPrivate);
  put('OWNER', cfg.owner);
  put('OWNER_CONTACT', cfg.ownerContact);
  put('ORIGIN', cfg.origin);
  put('DB', cfg.db);
  if (cfg.openSignup && !(process.env.OPEN_SIGNUP || '').trim()) process.env.OPEN_SIGNUP = '1';
  if (cfg.trustProxy && !(process.env.TRUST_PROXY || '').trim()) process.env.TRUST_PROXY = '1';
})();

const PORT = Number(process.env.PORT || 8080);
const DB_FILE = process.env.DB || path.join(__dirname, 'mybody.db');
const STATIC_DIR = process.env.STATIC
  ? path.resolve(process.env.STATIC)
  : path.join(__dirname, '..', 'prototype');
const ORIGIN = process.env.ORIGIN || '*';

/* ORIGIN 이 **실제로 들어오는 주소와 다르면** 조용히 어긋난 상태입니다.
 *
 * 설정의 "공개 주소" 칸에 자기 것이 아닌 도메인을 적는 일이 실제로
 * 있었습니다(예: https://mybody.com). 그러면
 *   · Access-Control-Allow-Origin 이 엉뚱한 값이 되고,
 *   · 폰 알림이 푸시 서비스에 그 주소를 "연락할 곳" 이라고 주장합니다.
 * 같은 출처 요청은 CORS 검사를 안 받으니 앱은 멀쩡해 보입니다 —
 * 그래서 아무도 안 알아챕니다. 첫 요청에서 한 번 크게 말합니다. */
let originWarned = false;
function warnOriginMismatch(req) {
  if (originWarned || ORIGIN === '*') return;
  let want = '';
  try { want = new URL(ORIGIN).host; } catch (e) { want = ''; }
  const got = str(req.headers['x-forwarded-host'] || req.headers.host || '').split(',')[0].trim();
  if (!want || !got) return;
  // localhost 로 들어오는 것은 주인이 직접 여는 것이라 어긋난 게 아닙니다.
  if (/^(localhost|127\.0\.0\.1|\[::1\])(:\d+)?$/i.test(got)) return;
  if (got.toLowerCase() === want.toLowerCase()) return;
  originWarned = true;
  console.log('');
  console.log('  ⚠ 설정의 공개 주소와 실제로 들어온 주소가 다릅니다.');
  console.log('      설정   ' + ORIGIN);
  console.log('      실제   ' + got);
  console.log('    내 주소가 아닌 것을 적어 두면 폰 알림이 그 주소를 연락처라고');
  console.log('    주장하고, 브라우저에 엉뚱한 CORS 값이 나갑니다.');
  console.log('    고치기:  node tools/serve.js --setup --origin="https://실제주소"');
  console.log('    지우기:  node tools/serve.js --setup --origin=""');
  console.log('');
}

/* 페어링 비밀 — 이 서버에 기기를 등록할 때 쓰는 한 개의 값.
 *
 * 이게 없을 때 /api/auth/signin 은 handle 만으로 세션을 발급했습니다.
 * 남의 handle 을 알면(친구끼리는 대개 압니다) 그 계정으로 그냥 로그인됐습니다.
 * 계정 탈취이고, 체성분 전체와 친구 관계가 통째로 넘어갑니다.
 *
 * 127.0.0.1 바인딩으로 막지 않는 이유: 주인이 "서버는 내 컴퓨터로 사용해"라고
 * 했고, 같은 와이파이의 폰이 못 들어오면 결국 되돌리게 됩니다. */
const PAIR_SECRET = process.env.PAIR_SECRET || '';
/* 가입 코드를 **없애기로 정한** 경우.
 *
 * 켜면 주소를 아는 사람은 누구나 계정을 만들 수 있습니다. 남의 몸
 * 숫자를 보는 것은 아니지만(친구 맺기는 초대 코드가 따로 필요합니다),
 * 모르는 사람 계정이 쌓입니다. 그리고 터널 주소는 무작위처럼 보여도
 * 실제로 스캔당합니다.
 *
 * 그래서 **빈 값으로 두는 것과 끄기로 정하는 것을 구분합니다.**
 * 빈 값은 깜빡한 것일 수 있어서 서버가 아예 안 뜹니다. 끄는 것은
 * OPEN_SIGNUP=1 로 명시해야 하고, 뜰 때마다 화면에 그 사실이 찍힙니다. */
const OPEN_SIGNUP = /^(1|true|yes)$/i.test((process.env.OPEN_SIGNUP || '').trim());

/* 2층 판독. 키가 없으면 /api/ocr 은 503 을 돌려주고, 앱은 0층(직접
   입력)으로 조용히 남습니다 — 판독은 편의기능이지 바닥이 아닙니다. */
const ANTHROPIC_KEY = process.env.ANTHROPIC_API_KEY || '';
const OCR_MODEL = process.env.OCR_MODEL || 'claude-sonnet-5';
/* 사람당 하루 판독 횟수.
 *
 * 40 이었습니다. 혼자 쓰던 때의 값이고, 그때는 "사실상 안 막는다" 가
 * 의도였습니다. 지금은 사람이 100명 규모로 늘었고, 40 은 한 사람이
 * 하루에 결과지 40장을 찍는다는 뜻입니다 — 그런 일은 없습니다.
 * 반대로 한 사람이 실수나 고장으로 40장을 태우면 그날 그 사람만으로
 * 600원이 나갑니다.
 *
 * 10 으로 내립니다. 결과지는 하루 한 장이고, 사진이 흐려서 다시
 * 찍는 경우까지 넉넉히 봐도 10 이면 남습니다. 막히면 숫자를 직접
 * 넣는 길이 그대로 있습니다 — 판독은 편의기능이지 바닥이 아닙니다. */
const OCR_PER_DAY = Number(process.env.OCR_PER_DAY || 10);

function pairOk(given) {
  const got = Buffer.from(str(given), 'utf8');
  const want = Buffer.from(PAIR_SECRET, 'utf8');
  if (got.length !== want.length) return false;
  return crypto.timingSafeEqual(got, want);   // 길이가 같을 때만 안전하게 비교
}

/** 쿼리 파라미터를 정수로. 못 읽으면 기본값 — 예전엔 SQLite 까지 내려가 HTTP 500 이 났습니다. */
function intParam(v, def, lo, hi) {
  const n = Number.parseInt(v, 10);
  return Number.isFinite(n) ? Math.min(hi, Math.max(lo, n)) : def;
}
/** 본문에서 받은 사용자 id. 문자열이 아니면 거절합니다. */
function idParam(v) {
  return (typeof v === 'string' && /^[\w-]{1,64}$/.test(v)) ? v : null;
}

const db = open(DB_FILE);
const api = makeApi(db);

/* --- 속도 제한 ---------------------------------------------------------------
 *
 * 누가 누구인지: 소켓 주소를 씁니다. 그런데 README 가 권하는
 * Cloudflare Tunnel 뒤에서는 그 주소가 전부 127.0.0.1 입니다 —
 * 모든 사용자가 한 버킷을 나눠 쓰게 되고, 친구 셋이 동시에 앱을
 * 열면 서로를 막습니다.
 *
 * x-forwarded-for 를 그냥 믿으면 아무나 헤더 한 줄로 제한을 피합니다.
 * 그래서 TRUST_PROXY=1 을 켠 사람만 믿습니다. 터널이나 리버스
 * 프록시를 쓰는 사람이 직접 켜는 것이고, 안 켜면 지금처럼 동작합니다.
 */
const TRUST_PROXY = process.env.TRUST_PROXY === '1';

function clientIp(req) {
  if (TRUST_PROXY) {
    const xff = req.headers['x-forwarded-for'];
    if (xff) return str(xff).split(',')[0].trim() || 'unknown';
  }
  return req.socket.remoteAddress || 'unknown';
}

/* 분당 허용 요청 수. LAN 안에서만 쓰거나 검증 도구를 돌릴 때 올립니다.
   인터넷에 열 때는 기본값 그대로 두세요. */
const RATE_MAX = Number(process.env.RATE_MAX || 300);

const hits = new Map();
function rateLimited(ip) {
  const now = Date.now();
  const win = 60_000, max = RATE_MAX;
  const rec = hits.get(ip) || { t: now, n: 0 };
  if (now - rec.t > win) { rec.t = now; rec.n = 0; }
  rec.n++;
  hits.set(ip, rec);
  // 통째로 비우면 지금 제한에 걸려 있던 사람까지 풀려납니다.
  // 지난 것만 골라 버립니다.
  if (hits.size > 5000) {
    for (const [k, v] of hits) { if (now - v.t > win) hits.delete(k); }
  }
  return rec.n > max;
}

/* --- 로그인 시도 제한 -------------------------------------------------------
 * 비밀번호 로그인은 무차별 대입의 표적입니다. 일반 속도 제한(분당 300)으로는
 * 턱없이 모자랍니다 — 분당 300번이면 흔한 비밀번호 목록을 하루에 다 돌립니다.
 * 아이디별로 따로 셉니다. IP 별로만 세면 여러 IP 로 한 계정을 때릴 수 있고,
 * 반대로 한 IP 뒤의 여러 사람이 서로를 막게 됩니다. */
/* 사람당 하루 판독 횟수. 사진 한 장이 돈이 드는 요청이라, 버그로
   같은 요청이 반복돼도 청구서가 터지지 않게 막아 둡니다. */
/* 서버 전체의 하루 한도도 같이 둡니다.
 *
 * 사람당 한도만 두면, 가입 코드를 아는 사람이 계정을 계속 만들어서
 * 한도를 무한정 늘릴 수 있습니다. 가입 코드는 친구에게 주는 값이라
 * "친구는 악의가 없다" 를 전제로 하지만, 코드가 한 번 새면 청구서는
 * 서버 주인에게 갑니다. 사람당 한도는 실수를 막고, 전체 한도는
 * 청구서를 막습니다. */
/* 서버 전체 하루 한도.
 *
 * 예전에는 사람당 한도 × 5 였습니다. 사람 수와 무관한 식이라,
 * 사람당 한도를 내리면 전체 한도까지 같이 내려가 **사람이 늘수록
 * 더 빨리 막히는** 이상한 동작이 됩니다 (10 × 5 = 50 이면 100명이
 * 하루 50장밖에 못 읽습니다).
 *
 * 사람 수 기준으로 못 박습니다. 100명이 하루 평균 2~3장을 찍는다고
 * 보면 실제 사용량은 하루 30장 안쪽입니다. 250 이면 8배 여유가 있고,
 * 다 써도 하루 3,750원에서 멈춥니다.
 *
 * 이건 **고장과 남용을 막는 울타리**지 예산이 아닙니다. 진짜 예산은
 * 앤트로픽 워크스페이스의 월 지출 한도로 거세요 — 여기가 뚫려도
 * 거기서 멈춥니다 (tools/workspaces.js 가 만들어 줍니다). */
const OCR_PER_DAY_TOTAL = Number(process.env.OCR_PER_DAY_TOTAL || 250);

/* 하루 한도는 **DB 에** 셉니다.
 *
 * 예전에는 메모리(Map)였습니다. 그래서 서버를 껐다 켜면 그날 한도가
 * 0 으로 돌아갔습니다. 개발 중에는 하루에도 여러 번 껐다 켜므로
 * 사실상 한도가 없는 것과 같았고, 그 상태에서 가입까지 열려 있으면
 * 주소를 아는 사람이 계정을 만들어 판독을 태울 수 있습니다.
 * 판독 한 장은 모델에 따라 7~35원입니다 — 취향이 아니라 지갑 문제입니다.
 *
 * DB 가 어떤 이유로든 안 되면 메모리로 물러섭니다. 세는 게 아예 없는
 * 것보다는 낫습니다 — 다만 그때는 껐다 켜면 리셋됩니다. */
const ocrHits = new Map();
function ocrDay() { return new Date().toISOString().slice(0, 10); }

/** 지금 한도에 걸리는가 — **세기만 합니다.** 올리지 않습니다. */
function ocrLimited(userId) {
  const day = ocrDay();
  let n, total;
  try {
    const r = api.peekOcr(userId, day);
    n = r.user; total = r.total;
  } catch (e) {
    n = ocrHits.get(userId + '|' + day) || 0;
    total = ocrHits.get('*|' + day) || 0;
  }
  if (total >= OCR_PER_DAY_TOTAL) return 'total';
  if (n >= OCR_PER_DAY) return 'user';
  return null;
}

/* 한 장을 **실제로 읽어 냈을 때만** 셉니다.
 *
 * 예전에는 한도 확인과 세기가 한 함수였습니다. 그래서 키가 거부되거나
 * 워크스페이스가 안 잡힌 날, 될 때까지 눌러 본 횟수가 그대로 한도를
 * 깎았습니다 — 열 번이면 그날이 끝납니다. 그리고 그 다음부터 화면은
 * 진짜 원인 대신 "오늘 판독 한도를 다 썼습니다" 를 말합니다.
 * 고치는 사람이 원인을 찾는 동안 원인이 가려지는 것입니다.
 *
 * 거절된 요청은 토큰을 안 써서 돈도 안 나갑니다. 셀 이유가 없습니다.
 *
 * 동시에 여러 장이 들어오면 몇 장 넘칠 수 있습니다 — 확인과 세기
 * 사이가 벌어지기 때문입니다. 이 규모(사람 100명)에서 그 몇 장보다
 * 위의 문제가 훨씬 비쌉니다. */
function ocrCount(userId) {
  const day = ocrDay();
  try { api.bumpOcr(userId, day); return; } catch (e) {}
  const key = userId + '|' + day, totalKey = '*|' + day;
  ocrHits.set(key, (ocrHits.get(key) || 0) + 1);
  ocrHits.set(totalKey, (ocrHits.get(totalKey) || 0) + 1);
  if (ocrHits.size > 2000) {
    for (const k of ocrHits.keys()) { if (!k.endsWith('|' + day)) ocrHits.delete(k); }
  }
}

const OCR_WORKSPACE = (process.env.ANTHROPIC_WORKSPACE_ID || '').trim();
async function runOcr(body) {
  return callOcr(body, { apiKey: ANTHROPIC_KEY, model: OCR_MODEL,
                         workspace: OCR_WORKSPACE });
}

const loginFails = new Map();
const LOGIN = { max: 8, windowMs: 15 * 60_000 };

/* 복구 코드는 로그인과 따로 셉니다.
 *
 * 예전엔 둘이 같은 칸을 썼습니다 — 키가 아이디 하나뿐이었습니다.
 * 그러면 비밀번호를 여덟 번 잘못 친 사람은 복구 코드를 한 번도 못
 * 넣어 보고 막힙니다. 비밀번호가 기억이 안 나서 복구하러 온 사람이
 * 정확히 그 상태입니다 — 유일한 출구가 들어오는 길에 잠겨 있습니다.
 * 반대로 공격자에게는 두 문을 한 칸으로 묶어 준 셈이라 이득도 없습니다.
 *
 * 숫자: 코드는 79비트이고 16자를 사람이 옮겨 적습니다. 오타가 잦으니
 * 시도를 너무 조이면 진짜 주인이 막힙니다. 시간당 5번이면 옮겨 적기에
 * 넉넉하고, 찍어 맞히려면 우주의 나이보다 오래 걸립니다. */
const RECOVER = { max: 5, windowMs: 60 * 60_000 };

/* 로그인만 따로, 더 빡빡하게 셉니다.
 *
 * 비밀번호 확인은 scrypt 입니다 — 건당 약 46ms 를 씁니다. 느린 것이
 * 의도고, 그래서 무차별 대입이 어렵습니다. 그런데 노드는 스레드가
 * 하나라 그 46ms 동안 서버 전체가 멈춥니다. 로그인도 안 한 사람이
 * 요청을 쏟아부으면 서버가 그냥 묶입니다 — 검증 도구로 5400번을
 * 보내 봤더니 4분이 넘게 걸렸습니다.
 *
 * 일반 제한(분당 300)으로는 모자랍니다. 300 × 46ms = 14초입니다.
 * 로그인·가입은 IP 당 분당 20번이면 사람이 쓰기에 충분하고, 그 위는
 * scrypt 를 돌리기 전에 잘라냅니다. 아이디별 잠금(8번/15분)은 그대로
 * 남아서 한 계정을 여러 IP 로 때리는 것을 막습니다. */
const AUTH_MAX = Number(process.env.AUTH_MAX || 20);
/* 실패 기록 맵의 상한. 검증 도구가 이걸 작게 줄여서, scrypt 를 5000번
   돌리지 않고도 "상한을 넘겼을 때 잠금이 풀리는가" 를 확인합니다. */
const LOGIN_MAP_MAX = Number(process.env.LOGIN_MAP_MAX || 5000);
const authHits = new Map();

function authLimited(ip) {
  const now = Date.now(), win = 60_000;
  const rec = authHits.get(ip) || { t: now, n: 0 };
  if (now - rec.t > win) { rec.t = now; rec.n = 0; }
  rec.n++;
  authHits.set(ip, rec);
  if (authHits.size > 5000) {
    for (const [k, v] of authHits) { if (now - v.t > win) authHits.delete(k); }
  }
  return rec.n > AUTH_MAX;
}

/* 키에 용도를 붙입니다 — 'pw|아이디' 와 'rc|아이디' 는 서로 다른 칸입니다. */
function failKey(handle, kind) { return (kind || 'pw') + '|' + handle; }
function rules(kind) { return kind === 'rc' ? RECOVER : LOGIN; }

function loginBlocked(handle, kind) {
  const R = rules(kind), key = failKey(handle, kind);
  const rec = loginFails.get(key);
  if (!rec) return 0;
  if (Date.now() - rec.t > R.windowMs) { loginFails.delete(key); return 0; }
  return rec.n >= R.max ? Math.ceil((R.windowMs - (Date.now() - rec.t)) / 60000) : 0;
}
function noteLoginFail(handle, kind) {
  const R = rules(kind), key = failKey(handle, kind);
  const rec = loginFails.get(key) || { t: Date.now(), n: 0 };
  if (Date.now() - rec.t > R.windowMs) { rec.t = Date.now(); rec.n = 0; }
  rec.n++;
  loginFails.set(key, rec);
  /* 맵이 넘칠 때 무엇을 버리는가 — 여기가 공격 지점입니다.
   *
   * 처음엔 loginFails.clear() 였습니다. 아무 아이디로 5000번을 흘리면
   * 맵이 통째로 비워지고 진짜 계정의 잠금까지 풀렸습니다.
   *
   * 그래서 "가장 오래된 것부터" 로 바꿨는데, 그게 더 나빴습니다.
   * 공격자가 밀어 넣는 쓰레기는 전부 방금 만들어진 최신 기록이고,
   * 지키려던 잠금은 조금 전에 생긴 오래된 기록입니다. 정확히 지켜야
   * 할 것부터 버리게 됩니다. 5000번이 필요하던 공격이 상한+1 번으로
   * 싸졌습니다.
   *
   * 지금 규칙: 잠겨 있는 기록(n >= max)은 만료되기 전까지 버리지
   * 않습니다. 만료된 것 → 아직 안 잠긴 것 순으로 버리고, 그래도
   * 자리가 없으면 새 기록을 아예 안 받습니다. 안 받아도 손해가
   * 없습니다 — 추적 안 되는 아이디는 원래 주는 8번을 받을 뿐입니다.
   */
  if (loginFails.size > LOGIN_MAP_MAX) {
    const now = Date.now();
    /* 기록마다 규칙이 다릅니다 — 키 앞머리가 그 기록이 로그인 것인지
       복구 것인지 말해 줍니다. 여기서 LOGIN 만 보면 복구 기록(창이 더
       긴 쪽)을 아직 살아 있는데도 만료로 오해하고 버립니다. */
    const ruleOf = k => rules(k.slice(0, 2));
    for (const [k, v] of loginFails) {
      if (now - v.t > ruleOf(k).windowMs) loginFails.delete(k);
    }
    for (const [k, v] of loginFails) {
      if (loginFails.size <= LOGIN_MAP_MAX) break;
      if (k !== key && v.n < ruleOf(k).max) loginFails.delete(k);
    }
    // 전부 잠긴 기록뿐이면 지금 것을 도로 뺍니다 — 남의 잠금을 밀어내지 않습니다.
    if (loginFails.size > LOGIN_MAP_MAX && rec.n < rules(kind).max) loginFails.delete(key);
  }
}
function clearLoginFails(handle, kind) { loginFails.delete(failKey(handle, kind)); }

/* 빠진 확장자는 application/octet-stream 으로 나갑니다. 그게 맞는 경우도
   있지만 매니페스트는 아닙니다 — 브라우저가 "폰에 설치" 를 띄울지 말지
   판단하는 파일인데, 알 수 없는 형식으로 내보내면 무시할 수 있습니다.
   검사 도구들은 자기 정적 서버에서 올바른 형식으로 내보내고 있어서
   이 차이를 한 번도 못 잡았습니다. */
const MIME = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8',
               '.css': 'text/css; charset=utf-8', '.json': 'application/json; charset=utf-8',
               '.webmanifest': 'application/manifest+json; charset=utf-8',
               '.svg': 'image/svg+xml', '.png': 'image/png', '.ico': 'image/x-icon',
               '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.webp': 'image/webp',
               '.woff2': 'font/woff2', '.txt': 'text/plain; charset=utf-8' };

function send(res, status, body, headers = {}) {
  const h = Object.assign({
    'Access-Control-Allow-Origin': ORIGIN,
    'Access-Control-Allow-Headers': 'content-type, authorization',
    'Access-Control-Allow-Methods': 'GET,POST,PUT,PATCH,DELETE,OPTIONS',
    'Cache-Control': 'no-store',
    'X-Content-Type-Options': 'nosniff'
  }, headers);
  if (typeof body === 'object' && !Buffer.isBuffer(body)) {
    body = JSON.stringify(body);
    h['Content-Type'] = 'application/json; charset=utf-8';
  }
  res.writeHead(status, h);
  res.end(body);
}

/* 본문 읽기.
 *
 * 한도를 넘으면 소켓을 바로 끊지 않습니다. 끊으면 브라우저에는 413 이
 * 아니라 "Failed to fetch" 가 뜨고, 그건 서버가 죽은 것과 구분이 안 됩니다.
 * 대신 남은 데이터를 버리면서 끝까지 받아 주고, 응답으로 413 을 보냅니다.
 * (그래도 무한정 받지는 않습니다 — HARD 를 넘으면 그때는 끊습니다.)
 */
/* 본문을 기다리는 시간에 상한을 둡니다.
 *
 * 예전에는 시간 제한이 없었습니다. 연결만 열어 두고 본문을 끝내지
 * 않으면 그 요청이 최대 2MB 를 붙든 채 영원히 남았습니다. 인증도
 * 필요 없으니, 그런 연결을 수백 개 열면 메모리가 그만큼 묶입니다
 * (slowloris). 요청을 보내다 만 것과 보내기 싫은 것은 서버가 구분할
 * 수 없으니, 시간으로 끊습니다. */
const BODY_TIMEOUT_MS = Number(process.env.BODY_TIMEOUT_MS || 30_000);

function readBody(req, limit = 2_000_000) {
  const HARD = limit * 4;
  return new Promise((resolve, reject) => {
    let n = 0, over = false, done = false; const chunks = [];
    const timer = setTimeout(() => {
      if (done) return;
      done = true;
      chunks.length = 0;
      reject(Object.assign(new Error('본문이 너무 느립니다'), { status: 408 }));
      req.destroy();
    }, BODY_TIMEOUT_MS);
    const finish = (fn, arg) => { if (done) return; done = true; clearTimeout(timer); fn(arg); };
    req.on('data', c => {
      n += c.length;
      if (n > HARD) {
        over = true;
        finish(reject, Object.assign(new Error('본문이 너무 큽니다'), { status: 413 }));
        req.destroy();
        return;
      }
      if (n > limit) { over = true; chunks.length = 0; return; }
      chunks.push(c);
    });
    req.on('end', () => {
      if (over) return finish(reject, Object.assign(new Error('본문이 너무 큽니다'), { status: 413 }));
      if (!chunks.length) return finish(resolve, {});
      try { finish(resolve, JSON.parse(Buffer.concat(chunks).toString('utf8'))); }
      catch { finish(reject, Object.assign(new Error('JSON 형식이 아닙니다'), { status: 400 })); }
    });
    req.on('error', e => finish(reject, e));
    req.on('aborted', () => finish(reject,
      Object.assign(new Error('연결이 끊겼습니다'), { status: 400 })));
  });
}

function bearer(req) {
  const a = req.headers.authorization || '';
  return a.startsWith('Bearer ') ? a.slice(7) : null;
}

/* --- 라우팅 --------------------------------------------------------------- */
/* --- 폰 알림 보내기 -------------------------------------------------------
 *
 * 키는 환경변수(VAPID_PUBLIC/VAPID_PRIVATE)로 받습니다. 없으면 알림 기능
 * 전체가 꺼진 채로 돌고, 화면은 "이 서버에는 알림이 꺼져 있습니다" 라고
 * 말합니다 — 켜 둔 줄 알았는데 안 오는 상태를 만들지 않습니다.
 * 키 만들기: node tools/push-keys.js
 * -------------------------------------------------------------------------- */
const VAPID = (process.env.VAPID_PUBLIC && process.env.VAPID_PRIVATE) ? {
  publicKey: process.env.VAPID_PUBLIC,
  privateKey: process.env.VAPID_PRIVATE,
  /* sub 은 푸시 서비스가 문제 생겼을 때 연락할 곳입니다. 운영자 연락처가
     없으면 서버 주소를 씁니다 — mailto: 를 지어내면 그게 거짓말입니다. */
  subject: process.env.OWNER_CONTACT && /^(mailto:|https:)/.test(process.env.OWNER_CONTACT)
    ? process.env.OWNER_CONTACT
    : (process.env.ORIGIN || 'https://example.invalid')
} : null;

/** 한 사람의 기기 전부에게 보냅니다. 죽은 주소는 정리합니다. */
async function pushToUser(userId, payload) {
  if (!VAPID) return;
  for (const sub of api.pushSubsOf(userId)) {
    try {
      const r = await PUSH.send(sub, payload, VAPID);
      if (r.gone) api.dropPushSub(sub.endpoint);
      else if (!r.ok) api.notePushFail(sub.endpoint);
    } catch (e) { api.notePushFail(sub.endpoint); }
  }
}

async function fanoutPush(ownerId, snap) {
  if (!VAPID) return;
  const who = api.me(ownerId);
  const name = (who && who.displayName) || '친구';
  /* 보내는 말은 한 줄뿐이고, 늘 좋은 소식입니다.
     "이번 주 3일째" 처럼 늘어난 숫자만 들어갑니다 — 무슨 요일에 무슨
     운동을 했는지는 스냅샷에 아예 없으므로 보낼 수도 없습니다. */
  const payload = JSON.stringify({
    t: name + '님이 운동했습니다',
    b: '이번 주 ' + snap.keptDays + '일째' +
       (snap.plannedDays ? ' · 계획 ' + snap.plannedDays + '일' : ''),
    u: '/#P15'
  });
  const targets = api.pushTargetsFor(ownerId);
  for (const { sub } of targets) {
    try {
      const r = await PUSH.send(sub, payload, VAPID);
      if (r.gone) api.dropPushSub(sub.endpoint);
      else if (!r.ok) api.notePushFail(sub.endpoint);
    } catch (e) { api.notePushFail(sub.endpoint); }
  }
}

async function handleApi(req, res, url) {
  const reqIp = clientIp(req);
  const p = url.pathname.replace(/^\/api/, '') || '/';
  const method = req.method;

  /* 가입에 코드가 필요한지 여기서 알려줍니다.
     숨길 이유가 없습니다 — 필요한지 아닌지는 한 번 시도해 보면 바로
     드러나고, 화면이 모르면 안 필요한 칸을 계속 보여 주게 됩니다. */
  if (p === '/health') {
    return send(res, 200, { ok: true, now: new Date().toISOString(),
                            openSignup: OPEN_SIGNUP });
  }

  /* 앱이 "새 판이 나왔나 · 내 판이 너무 낡았나" 를 묻는 곳.
   *
   * 로그인 없이 받습니다. 로그인이 안 되는 이유가 바로 "앱이 낡아서" 일
   * 수 있는데, 그걸 알려 주는 길이 로그인 뒤에 있으면 못 닿습니다.
   * 내보내는 것은 판 번호와 가게 주소뿐입니다.
   *
   * 설정 파일을 **부를 때마다 새로 읽습니다.** 판을 낸 뒤 주인이
   * tools/app-version.js 를 돌리면 서버를 다시 띄우지 않아도 바로
   * 나가야 합니다 — 다시 띄우는 걸 잊으면 안내가 조용히 안 나갑니다.
   * 앱은 몇 시간에 한 번만 물으니 읽는 값은 싸게 칩니다.
   * tools/ 가 없으면(server/ 만 떼어 옮긴 경우) 전부 빈 값 = 안내 없음.
   *
   * **망가진 설정 파일은 빈 값으로 내보내지 않습니다.** 손으로 고치다
   * 틀렸거나, 도구가 저장하는 바로 그 순간에 읽으면 파일이 JSON 이
   * 아닙니다. 그걸 빈 값으로 주면 "주인이 전부 지웠다" 와 똑같아서, 그때
   * 물은 앱은 닫을 수 없는 안내까지 지우고 여섯 시간을 쉽니다. 503 이면
   * 앱은 지난 답을 들고 다음에 다시 묻습니다(app/lib/src/update.dart). */
  if (p === '/version' && method === 'GET') {
    let CONFIG = null;
    try { CONFIG = require('../tools/config.js'); } catch (e) {}
    let saved = {};
    if (CONFIG) {
      try { saved = CONFIG.readFileStrict(); }
      catch (e) {
        return send(res, 503, { ok: false, reason: '서버 설정을 읽지 못했습니다 — 잠시 뒤에 다시 물어 주세요' });
      }
    }
    return send(res, 200, APPVER.versionInfo(saved));
  }

  /* 계정 만들기 — 페어링 비밀이 필요합니다.
     이 서버는 주인 것이지 공개 가입 서비스가 아닙니다. 비밀을 아는 사람만
     계정을 만들 수 있고, 그 비밀은 주인이 초대하고 싶은 사람에게만 줍니다. */
  if ((p === '/auth/signup' || p === '/auth/signin' || p === '/auth/recover')
      && method === 'POST' && authLimited(reqIp)) {
    // scrypt 를 돌리기 전에 잘라냅니다 — 비싼 것은 그 다음 줄입니다.
    return send(res, 429, { ok: false, reason: '로그인 시도가 너무 잦습니다. 잠시 뒤에 다시 해 주세요' });
  }

  if (p === '/auth/signup' && method === 'POST') {
    const b = await readBody(req);
    if (!OPEN_SIGNUP && !pairOk(b.pairSecret)) {
      return send(res, 401, { ok: false, reason: '이 서버의 가입 코드가 필요합니다' });
    }
    const r = api.signUp(b);
    return send(res, r.ok ? 200 : 400, r);
  }

  /* 로그인 — 가입 후에는 비밀번호만으로 들어옵니다.
     페어링 비밀을 계속 요구하면 그게 사실상 공용 비밀번호가 되어,
     한 사람만 새도 전원이 뚫립니다. */
  if (p === '/auth/signin' && method === 'POST') {
    const b = await readBody(req);
    const h = str(b.handle).trim().toLowerCase();
    if (!h) return send(res, 400, { ok: false, reason: '아이디가 필요합니다' });
    const wait = loginBlocked(h);
    if (wait) {
      return send(res, 429, { ok: false, reason: '로그인 시도가 너무 많습니다. ' + wait + '분 뒤에 다시 해주세요' });
    }
    const r = api.signIn(b);
    if (!r.ok) { noteLoginFail(h); return send(res, 401, r); }
    clearLoginFails(h);
    return send(res, 200, r);
  }

  /* 복구 코드로 비밀번호 새로 정하기 — 로그인 전에 쓰는 길입니다.
   *
   * 아이디별 잠금(loginBlocked)을 로그인과 같이 씁니다. 코드가 79비트라
   * 무차별 대입은 현실적으로 불가능하지만, 잠금이 있으면 "몇 번 찍어보다
   * 그만두는" 사람도 못 지나갑니다. 그리고 코드 확인도 scrypt 라 비싸서,
   * 제한이 없으면 그것만으로 서버를 묶을 수 있습니다. */
  if (p === '/auth/recover' && method === 'POST') {
    const b = await readBody(req);
    const h = str(b.handle).trim().toLowerCase();
    if (!h) return send(res, 400, { ok: false, reason: '아이디가 필요합니다' });
    const wait = loginBlocked(h, 'rc');
    if (wait) {
      return send(res, 429, { ok: false,
        reason: '복구 코드 시도가 너무 많습니다. ' + wait + '분 뒤에 다시 해 주세요' });
    }
    const r = api.recoverPassword(b);
    if (!r.ok) { noteLoginFail(h, 'rc'); return send(res, 400, r); }
    /* 되찾았으면 로그인 쪽 잠금도 풉니다 — 비밀번호를 잊어서 여덟 번
       틀리고 온 사람이 바로 그 상황입니다. 방금 코드로 본인임을
       증명했는데 옛 실패 기록 때문에 새 비밀번호로 못 들어가면
       되찾은 의미가 없습니다. */
    clearLoginFails(h, 'rc');
    clearLoginFails(h, 'pw');
    return send(res, 200, r);
  }

  const tok = bearer(req);
  const user = api.userForToken(tok);
  if (!user) return send(res, 401, { ok: false, reason: '로그인이 필요합니다' });
  const me = user.id;

  if (p === '/auth/signout' && method === 'POST') { api.signOut(tok); return send(res, 200, { ok: true }); }
  if (p === '/auth/signout-all' && method === 'POST') return send(res, 200, api.signOutEverywhere(me));
  if (p === '/auth/password' && method === 'POST') {
    const b = await readBody(req);
    const r = api.changePassword(me, b);
    return send(res, r.ok ? 200 : 400, r);
  }
  /* 복구 코드를 잃어버렸을 때 새로 받습니다. 비밀번호를 다시 확인합니다 —
     잠깐 열린 폰을 집어든 사람이 코드를 뽑아 가지 못하게. */
  if (p === '/auth/recovery-code' && method === 'POST') {
    const b = await readBody(req);
    const r = api.newRecoveryCode(me, b);
    return send(res, r.ok ? 200 : 400, r);
  }
  if (p === '/me' && method === 'GET') return send(res, 200, { ok: true, user: api.me(me), stats: api.stats(me) });
  if (p === '/me' && method === 'PATCH') return send(res, 200, { ok: true, user: api.updateMe(me, await readBody(req)) });
  if (p === '/me' && method === 'DELETE') { api.deleteMe(me); return send(res, 200, { ok: true }); }
  if (p === '/me/consent' && method === 'POST') {
    const r = api.consent(me, await readBody(req));
    return send(res, r.ok ? 200 : 400, r);
  }

  if (p === '/friends' && method === 'GET') return send(res, 200, { ok: true, friends: api.listFriends(me) });
  if (p === '/friends/request' && method === 'POST') {
    const b = await readBody(req);
    /* 안드로이드 앱 0.2.3 까지는 'code' 로 보냈습니다. 이미 깔린 앱이 서버만
       다시 띄우면 친구 추가가 되도록 둘 다 받습니다. */
    const r = api.sendRequest(me, b.inviteCode || b.code);
    /* 친구 요청은 **앱을 안 열면 영영 모르는** 소식이었습니다.
     * 요청을 받은 쪽은 상대가 기다리는 줄도 모르고, 보낸 쪽은 무시당한
     * 줄 압니다. 둘 다 앱을 안 여는 이유가 됩니다.
     *
     * 운동 알림(fanoutPush)과 달리 공유 설정으로 막지 않습니다. 아직
     * 친구가 아니라 공유 설정이라는 것이 존재하지 않고, 여기서 나가는
     * 것은 몸에 대한 정보가 아니라 "누가 너를 추가했다" 하나입니다.
     * 이름을 싣는 이유: 초대 코드를 직접 건넨 사이라 누구인지 알아야
     * 수락할지 정할 수 있습니다. 이름이 없으면 알림이 쓸모가 없습니다.
     *
     * 응답을 기다리게 하지 않습니다 — 푸시 서비스가 느리면 화면이 그만큼
     * 멈춥니다. 알림이 늦는 것과 앱이 굳는 것 중에는 전자가 낫습니다. */
    if (r.ok && r.otherId) {
      const who = api.me(me);
      const name = (who && who.displayName) || '누군가';
      const msg = r.status === 'accepted'
        ? { t: name + '님과 친구가 되었습니다',
            b: '서로의 운동 체크가 보입니다 · 몸 숫자는 기본 비공개' }
        : { t: name + '님이 친구 요청을 보냈습니다',
            b: '수락하면 서로의 운동 체크가 보입니다 · 몸 숫자는 기본 비공개' };
      pushToUser(r.otherId, JSON.stringify(Object.assign(msg, { u: '/#P15' })))
        .catch(() => {});
    }
    return send(res, 200, r);
  }
  if (p === '/friends/accept' && method === 'POST') {
    const b = await readBody(req);
    const uid = idParam(b.userId);
    if (!uid) return send(res, 400, { ok: false, reason: 'userId 가 필요합니다' });
    const r = api.accept(me, uid);
    /* 수락됐다는 것도 알려 줍니다.
     *
     * 요청 알림만 있을 때는 흐름이 반쪽이었습니다. 보낸 사람은 수락이
     * 됐는지 거절이 됐는지 **앱을 열어 봐야만** 알았고, 그래서 계속
     * 기다리거나 무시당했다고 생각했습니다. 기다리게 만드는 쪽이
     * 알림이 없는 쪽입니다.
     *
     * 거절(decline)은 안 보냅니다. 거절당했다는 알림은 받아서 할 수 있는
     * 일이 없고, 알림으로 받을 말도 아닙니다. 보낸 사람 화면에서는 요청이
     * 조용히 사라집니다 — 그게 맞습니다.
     *
     * ok 가 true 일 때만 옵니다. 이미 친구인데 다시 누르면 accept 가
     * '받은 요청이 없습니다' 로 끝나므로, 연타로 울리는 길이 없습니다. */
    if (r.ok) {
      const who = api.me(me);
      const name = (who && who.displayName) || '상대';
      pushToUser(uid, JSON.stringify({
        t: name + '님이 친구 요청을 수락했습니다',
        b: '서로의 운동 체크가 보입니다 · 몸 숫자는 기본 비공개',
        u: '/#P15'
      })).catch(() => {});
    }
    return send(res, 200, r);
  }
  if (p === '/friends/decline' && method === 'POST') {
    const b = await readBody(req);
    const uid = idParam(b.userId);
    if (!uid) return send(res, 400, { ok: false, reason: 'userId 가 필요합니다' });
    return send(res, 200, api.decline(me, uid));
  }
  if (p === '/friends/block' && method === 'POST') {
    const b = await readBody(req);
    const uid = idParam(b.userId);
    if (!uid) return send(res, 400, { ok: false, reason: 'userId 가 필요합니다' });
    return send(res, 200, api.block(me, uid));
  }
  if (p === '/friends/unblock' && method === 'POST') {
    const b = await readBody(req);
    const uid = idParam(b.userId);
    if (!uid) return send(res, 400, { ok: false, reason: 'userId 가 필요합니다' });
    return send(res, 200, api.unblock(me, uid));
  }
  let m = p.match(/^\/friends\/([\w-]+)$/);
  if (m && method === 'DELETE') return send(res, 200, api.removeFriend(me, m[1]));

  m = p.match(/^\/share\/([\w-]+)$/);
  if (m && method === 'GET') return send(res, 200, { ok: true, share: api.shareFields(me, m[1]) });
  if (m && method === 'PUT') {
    const b = await readBody(req); return send(res, 200, api.setShare(me, m[1], b || {}));
  }

  /* --- 운동 독촉 ------------------------------------------------------- */
  if (p === '/pokes' && method === 'POST') {
    const b = await readBody(req);
    const r = api.poke(me, b && b.userId, b && b.kind);
    if (r.ok) {
      /* 웹 푸시가 있으면 바로. 앱은 켜질 때 가져갑니다. */
      const who = api.me(me);
      const name = (who && who.displayName) || '친구';
      pushToUser(String(b.userId), JSON.stringify({
        t: name + '님이 운동하라고 콕 찔렀어요', b: '오늘 운동 어때요? 💪', u: '/#P15' })).catch(() => {});
    }
    return send(res, r.ok ? 200 : 400, r);
  }
  if (p === '/pokes' && method === 'GET') {
    return send(res, 200, api.pullPokes(me));
  }

  if (p === '/snapshots' && method === 'POST') {
    const b = await readBody(req);
    if (!b.weekStart) return send(res, 400, { ok: false, reason: 'weekStart 가 필요합니다' });
    const snap = api.publishSnapshot(me, b.weekStart, b.payload);
    /* 지킨 날이 늘었으면 친구들 폰에 한 줄 보냅니다.
       기다리지 않습니다 — 푸시 서비스가 느리다고 저장이 늦어지면 안 됩니다.
       실패는 fanout 안에서 처리하고 여기서는 응답을 막지 않습니다. */
    if (snap.ok && snap.grew) fanoutPush(me, snap).catch(() => {});
    // 거절을 200 으로 보내면 클라이언트가 성공으로 읽고 큐에서 지웁니다.
    return send(res, snap.ok ? 200 : 400, snap);
  }

  /* --- 폰 알림 ---------------------------------------------------------
   * 브라우저는 https 에서만 구독할 수 있습니다. 같은 와이파이 http 로
   * 열면 serviceWorker 자체가 없어서 여기까지 오지도 않습니다.
   * -------------------------------------------------------------------- */
  if (p === '/push/key' && method === 'GET') {
    return send(res, 200, { ok: true, key: VAPID ? VAPID.publicKey : null });
  }
  if (p === '/push/subscribe' && method === 'POST') {
    if (!VAPID) return send(res, 503, { ok: false, reason: '이 서버에는 알림 키가 없습니다' });
    const b = await readBody(req);
    return send(res, 200, api.addPushSub(me, b));
  }
  if (p === '/push/unsubscribe' && method === 'POST') {
    const b = await readBody(req);
    return send(res, 200, api.removePushSub(me, b && b.endpoint));
  }
  m = p.match(/^\/snapshots\/([\w-]+)$/);
  if (m && method === 'GET') {
    return send(res, 200, api.friendSnapshots(me, m[1], intParam(url.searchParams.get('limit'), 26, 1, 200)));
  }

  if (p === '/sync/push' && method === 'POST') {
    const b = await readBody(req);
    const r = api.push(me, b.records);
    // 거절이면 200 으로 보내면 안 됩니다 — 클라이언트가 성공으로 읽고
    // 큐에서 지워 버립니다.
    return send(res, r.ok ? 200 : 400, r);
  }
  if (p === '/sync/pull' && method === 'GET') {
    return send(res, 200, api.pull(me, url.searchParams.get('since') || '',
                                   intParam(url.searchParams.get('limit'), 500, 1, 2000)));
  }

  /* 2층 — 결과지 사진 판독 프록시.
   *
   * 왜 프록시인가: API 키를 정적 클라이언트에 넣을 수 없습니다. 키는
   * 이 서버의 환경변수에만 있고, 브라우저는 자기 계정 토큰으로만
   * 이 경로를 부릅니다.
   *
   * 사진 본문은 다른 요청보다 큽니다(base64 가 4/3 배). 그래서 한도를
   * 따로 줍니다. photo.js 가 이미 900KB 아래로 줄여서 보냅니다.
   */
  if (p === '/ocr' && method === 'POST') {
    if (!ANTHROPIC_KEY) {
      return send(res, 503, { ok: false, reason: '이 서버에는 판독 키가 설정되지 않았습니다' });
    }
    const capped = ocrLimited(me);
    if (capped) {
      return send(res, 429, { ok: false, reason: capped === 'total'
        ? '오늘 이 서버의 판독 한도를 다 썼습니다. 내일 다시 해 주세요'
        : '오늘 판독 한도를 다 썼습니다. 내일 다시 해 주세요' });
    }
    const b = await readBody(req, 8_000_000);
    const out = await runOcr(b);
    /* 읽어 낸 것만 셉니다. 실패는 한도를 안 깎습니다. */
    if (out.status === 200) ocrCount(me);
    return send(res, out.status, out.body);
  }

  return send(res, 404, { ok: false, reason: '그런 경로가 없습니다' });
}

/* 정적 파일 내보내기.
 *
 * 경계 검사가 file.startsWith(STATIC_DIR) 이었습니다. 구분자가 없어서
 * STATIC_DIR 이 /srv/webroot 이면 /srv/webroot-x/z.txt 가 통과했습니다.
 * 이름이 접두사로 겹치는 형제 디렉터리가 그대로 열렸습니다 —
 * prototype 과 prototype-old 같은 조합이면 바로 새어 나갑니다.
 *
 * 이제 양쪽을 resolve 해서 절대경로로 만들고, 뒤에 구분자를 붙여
 * 비교합니다. 그러면 /srv/webroot- 로 시작하는 것은 안 걸립니다.
 * %2e%2e%2f 류는 path.join 이 정규화한 뒤 이 검사에 걸립니다. */
const STATIC_ROOT = path.resolve(STATIC_DIR);

function insideRoot(file) {
  const f = path.resolve(file);
  return f === STATIC_ROOT || f.startsWith(STATIC_ROOT + path.sep);
}

/* --- 안드로이드 앱과 이 주소가 한 쌍임을 증명하는 파일 -------------------
 *
 * 구글플레이에 PWA 를 올리는 길(TWA)은 앱이 이 주소를 자기 것이라고
 * 주장하고, 이 주소가 그 앱을 자기 것이라고 맞장구쳐야 성립합니다.
 * 그 맞장구가 /.well-known/assetlinks.json 입니다.
 *
 * 없으면 앱이 열릴 때 주소창이 그대로 뜹니다 — TWA 가 아니라 그냥
 * 브라우저가 됩니다. 그리고 그건 심사에서 "웹사이트를 감싼 앱" 으로
 * 읽힙니다.
 *
 * 값은 환경변수로 받습니다. 앱을 안 만들 거면 비워 두면 되고, 그 때는
 * 이 주소가 404 를 줍니다 — 빈 파일을 내주면 "설정했는데 안 된다" 가
 * 됩니다. 채우는 법은 docs/APPSTORE.md 에 있습니다.
 * -------------------------------------------------------------------------- */
const TWA_PACKAGE = (process.env.TWA_PACKAGE || '').trim();
const TWA_FINGERPRINT = (process.env.TWA_FINGERPRINT || '').trim();

function assetLinks() {
  if (!TWA_PACKAGE || !TWA_FINGERPRINT) return null;
  return JSON.stringify([{
    relation: ['delegate_permission/common.handle_all_urls'],
    target: {
      namespace: 'android_app',
      package_name: TWA_PACKAGE,
      /* 지문은 콜론으로 끊긴 대문자 16진수 32덩이입니다. 소문자나 공백이
         섞이면 구글이 조용히 무시하고, 앱은 주소창이 뜬 채로 나옵니다 —
         왜 안 되는지 어디에도 안 적힙니다. 그래서 여기서 맞춰 둡니다. */
      sha256_cert_fingerprints: TWA_FINGERPRINT.split(',')
        .map(x => x.trim().toUpperCase().replace(/\s+/g, ''))
        .filter(Boolean)
    }
  }]);
}

function serveStatic(req, res, url) {
  let rel;
  try { rel = decodeURIComponent(url.pathname); }
  catch (e) { return send(res, 400, 'bad path', { 'Content-Type': 'text/plain; charset=utf-8' }); }

  if (rel === '/.well-known/assetlinks.json') {
    const body = assetLinks();
    if (!body) {
      return send(res, 404, 'not configured (TWA_PACKAGE / TWA_FINGERPRINT)',
                  { 'Content-Type': 'text/plain; charset=utf-8' });
    }
    return send(res, 200, body, { 'Content-Type': 'application/json' });
  }

  if (rel === '/') rel = '/index.html';
  if (rel.indexOf('\0') >= 0) {
    return send(res, 400, 'bad path', { 'Content-Type': 'text/plain; charset=utf-8' });
  }
  const file = path.join(STATIC_ROOT, rel);
  if (!insideRoot(file) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) {
    return send(res, 404, 'not found', { 'Content-Type': 'text/plain; charset=utf-8' });
  }
  send(res, 200, fs.readFileSync(file),
       { 'Content-Type': MIME[path.extname(file)] || 'application/octet-stream' });
}

/* --- 무슨 일이 있었는지 --------------------------------------------------
 *
 * 로그가 기동 배너뿐이었습니다. 친구가 "안 돼요" 라고 할 때 주인이 볼
 * 것이 하나도 없었습니다 — 요청이 오기는 했는지, 401 인지 429 인지,
 * 아니면 아예 안 닿는 건지 구분할 방법이 없었습니다.
 *
 * 무엇을 남기고 무엇을 안 남기나
 *   남김   시각 · 메서드 · 경로 · 상태 · 걸린 시간
 *   안 남김 본문 · 토큰 · 사진 · 몸에 대한 숫자. 건강정보를 로그에
 *          남기면 지워야 할 곳이 하나 더 생깁니다. 그리고 그 로그는
 *          보통 백업도 안 되고 보관 기간도 없습니다.
 *   IP 는 기본으로 안 남깁니다 — 터널 뒤에서는 전부 같은 값이라
 *          쓸모가 없고, 아니면 그게 곧 개인정보입니다.
 *
 * 정적 파일은 안 셉니다. 앱을 한 번 열면 서른 줄이 쏟아져서, 정작
 * 봐야 할 /api 줄이 묻힙니다.
 */
const LOG = process.env.LOG !== '0';

/* 경로에 박힌 **상대방 계정 id** 를 가립니다.
 *
 * /api/friends/user_ab12… · /api/share/user_ab12… · /api/snapshots/user_ab12…
 * 세 경로가 그대로 찍히고 있었습니다. 한 줄씩 보면 별것 아닌데, 쌓이면
 * "누가 누구의 주간 요약을 언제 열었는가" 가 됩니다 — 이 앱이 친구에게
 * 숫자를 안 보여 주려고 그렇게 애쓰는 바로 그 정보입니다. 게다가 이
 * 로그는 회전도 보유 기간도 없습니다(운영자가 파일로 받으면 영원히 쌓입니다).
 *
 * 앞 네 글자만 남깁니다. 고장을 쫓을 때 "같은 상대인가" 는 알 수 있고,
 * 누구인지는 로그만으로 알 수 없습니다. */
function maskPath(p2) {
  return p2.replace(/\/(user|snap|sess)_([0-9a-f]{4})[0-9a-f]*/g, '/$1_$2…');
}

function logLine(req, status, ms) {
  if (!LOG) return;
  const p2 = req.url.split('?')[0];
  if (!(p2.startsWith('/api/') || p2 === '/health')) return;
  if (p2 === '/health') return;          // 상태 확인은 1분에 몇 번씩 옵니다
  console.log(new Date().toISOString().slice(11, 19) + '  ' +
              String(status) + '  ' + req.method.padEnd(6) + maskPath(p2) + '  ' + ms + 'ms');
}

const server = http.createServer(async (req, res) => {
  const ip = clientIp(req);
  const t0 = Date.now();
  res.on('finish', () => logLine(req, res.statusCode, Date.now() - t0));
  /* 정적 파일은 제한에서 뺍니다. 앱 하나가 <script> 30개를 부르는데,
     그걸 세면 앱을 한 번 여는 것만으로 분당 제한의 10%를 씁니다 —
     터널 뒤에서 모두가 한 버킷일 때는 앱이 아예 안 열렸습니다.
     비싼 것은 /api 이고, 정적 파일은 서비스워커가 캐시합니다. */
  warnOriginMismatch(req);
  const isApi = req.url.startsWith('/api/') || req.url.split('?')[0] === '/health';
  if (isApi && rateLimited(ip)) return send(res, 429, { ok: false, reason: '요청이 너무 많습니다' });
  if (req.method === 'OPTIONS') return send(res, 204, '');
  const url = new URL(req.url, 'http://localhost');
  try {
    if (url.pathname === '/health' || url.pathname.startsWith('/api/')) return await handleApi(req, res, url);
    serveStatic(req, res, url);
  } catch (e) {
    // 예전엔 SQLite 드라이버 원문이 그대로 나갔습니다 ("Provided value cannot be
    // bound to SQLite parameter 1"). 내부 구조를 밖에 알려줄 이유가 없습니다.
    if (e && e.status) return send(res, e.status, { ok: false, reason: e.message || '요청 오류' });
    console.error('[500]', e && e.stack || e);
    send(res, 500, { ok: false, reason: '서버 오류' });
  }
});

if (require.main === module) {
  if (!PAIR_SECRET && !OPEN_SIGNUP) {
    console.error('PAIR_SECRET 없이는 시작하지 않습니다.');
    console.error('');
    console.error('  아무나 계정을 만들 수 있는 서버가 되기 때문입니다.');
    console.error('  아래처럼 값을 하나 정해서 넘기고, 같은 값을 친구에게만 알려주세요:');
    console.error('');
    console.error('    PAIR_SECRET=$(openssl rand -hex 16) node server/server.js');
    console.error('');
    console.error('  일부러 아무나 가입할 수 있게 열어 둘 거면 그렇게 말해 주세요:');
    console.error('');
    console.error('    OPEN_SIGNUP=1 node server/server.js');
    console.error('');
    process.exit(1);
  }
  /* 포트가 이미 쓰이고 있으면 예전에는 노드의 스택 추적이 그대로
     쏟아졌습니다 — 'Error: listen EADDRINUSE ... at Server.setupListenHandle
     (node:net:1940:16)'. 개발자가 아니면 이게 무슨 말인지 모르고,
     정작 할 일(포트를 바꾸거나 그 프로그램을 끄기)은 안 적혀 있습니다.
     서버를 처음 띄우는 사람이 제일 자주 만나는 오류라 따로 받습니다. */
  server.on('error', (e) => {
    if (e && e.code === 'EADDRINUSE') {
      console.error('');
      console.error(PORT + '번 포트를 이미 다른 프로그램이 쓰고 있습니다.');
      console.error('');
      console.error('  이 서버가 이미 떠 있을 수도 있습니다 — 브라우저에서');
      console.error('  http://localhost:' + PORT + ' 를 먼저 열어 보세요.');
      console.error('');
      console.error('  다른 프로그램이라면 포트를 바꿔서 띄우면 됩니다:');
      console.error('    PORT=' + (PORT + 1) + ' (나머지는 그대로) node server/server.js');
      console.error('');
      process.exit(1);
    }
    if (e && e.code === 'EACCES') {
      console.error('');
      console.error(PORT + '번 포트를 열 권한이 없습니다.');
      console.error('  1024 아래 번호는 관리자 권한이 필요합니다. 8080 처럼 큰 번호를 쓰세요.');
      console.error('');
      process.exit(1);
    }
    console.error('서버를 시작하지 못했습니다:', (e && e.message) || e);
    process.exit(1);
  });

  /* 끌 때 데이터베이스를 닫습니다.
   *
   * 안 닫으면 WAL(앞서 쓴 기록이 쌓이는 곁파일)이 그대로 남습니다.
   * 그 상태에서는 mybody.db 만 복사해도 빈 파일입니다 — 실제로
   * 확인했습니다: 계정 하나를 만든 직후 mybody.db 는 4KB 이고,
   * 그걸 복사하면 users 테이블조차 없습니다. 백업한 줄 알았는데
   * 아무것도 없는 상황이 제일 나쁩니다.
   *
   * 닫으면 SQLite 가 WAL 을 본파일에 합치고 곁파일을 지웁니다.
   * 그러면 파일 하나만 챙겨도 온전합니다. */
  let closing = false;
  const shutdown = (sig) => {
    if (closing) return;
    closing = true;
    console.log('\n' + sig + ' — 정리하고 끕니다...');
    try { server.close(); } catch (e) {}
    try { db.close(); } catch (e) { console.error('데이터베이스를 못 닫았습니다:', e.message); }
    process.exit(0);
  };
  process.on('SIGINT', () => shutdown('Ctrl+C'));
  process.on('SIGTERM', () => shutdown('SIGTERM'));

  server.listen(PORT, () => {
    console.log('Mybody 서버 실행 중');
    console.log('  주소   http://localhost:' + PORT);
    /* 폰에서 칠 주소를 찍어 줍니다.
       이걸 아무 데서도 안 알려줘서, 폰으로 쓰려는 사람은 자기 컴퓨터의
       내부 주소를 따로 찾아내야 했습니다 — 어디서 찾는지 모르면 거기서
       끝입니다. 이 서버는 0.0.0.0 에 붙으므로 같은 와이파이에서 바로
       열립니다. */
    lanAddresses().forEach(a => {
      console.log('  폰에서 http://' + a + ':' + PORT + '   (같은 와이파이)');
    });
    console.log('  DB     ' + DB_FILE);
    /* 열어 둔 상태는 띄울 때마다 눈에 띄어야 합니다. 설정 파일 안에만
       있으면 몇 주 뒤엔 자기가 열어 뒀다는 것도 잊습니다. */
    if (OPEN_SIGNUP) {
      console.log('  가입   누구나 (가입 코드 없음)  ← 주소를 아는 사람은 다 만들 수 있습니다');
    }
    const staticOk = fs.existsSync(path.join(STATIC_DIR, 'index.html'));
    console.log('  정적   ' + STATIC_DIR +
                (!staticOk ? '   ← 여기에 앱이 없습니다' :
                 (isDevTree(STATIC_DIR) ? '   ← 개발 빌드입니다' : '')));
    console.log('');
    /* 없는 폴더를 가리켜도 "실행 중" 이라고만 했습니다. 브라우저에는
       빈 404 만 나오고 서버는 멀쩡하다고 하니, 무엇이 잘못됐는지
       알아낼 방법이 없습니다. STATIC 을 상대경로로 주고 다른 폴더에서
       띄우면 바로 이렇게 됩니다 — cwd 기준으로 풀리기 때문입니다. */
    if (!staticOk) {
      console.log('  ⚠ 이 폴더에 index.html 이 없습니다. 브라우저에는 404 만 나옵니다.');
      console.log('    STATIC 을 상대경로로 줬다면 지금 폴더(' + process.cwd() + ')');
      console.log('    기준으로 풀립니다. 전체 경로로 주거나, 저장소 폴더에서 띄우세요:');
      console.log('');
      console.log('      cd ' + path.join(__dirname, '..') + ' && node tools/serve.js');
      console.log('');
    }
    /* 개발 빌드를 그대로 서빙하고 있으면 반드시 말합니다.
       STATIC 을 빼먹으면 prototype/ 이 나가는데, 그 화면에는 고유번호
       배지가 전부 떠 있고 "내 실제 인바디로 채우기" 같은 개발용 버튼이
       살아 있습니다. 친구에게 주소를 주고 나서야 알게 되면 늦습니다. */
    if (isDevTree(STATIC_DIR)) {
      console.log('  ⚠ 지금 나가는 것은 개발 빌드입니다 — 화면에 번호 배지가 전부 뜨고');
      console.log('    개발용 버튼이 살아 있습니다. 남에게 줄 주소라면 이렇게 하세요:');
      console.log('');
      console.log('      OWNER="이름" OWNER_CONTACT="연락처" node tools/build-release.js');
      console.log('      STATIC=./release (나머지는 그대로) node server/server.js');
      console.log('');
    }
    // cloudflared 안내는 뺐습니다. 집 안 서버를 공개 서버로 바꾸는 두 줄이었고,
    // 그 상태에서 인증 구멍이 있으면 피해가 바로 현실이 됩니다.
    console.log('  밖에서 접속하려면 먼저 server/README.md 의 "밖에서 접속하기"를 읽어 주세요.');
    if (LOG) {
      console.log('  아래로 요청이 한 줄씩 지나갑니다. 친구가 "안 된다" 고 하면 여기를 보세요.');
      console.log('  (몸에 대한 숫자나 사진은 안 남깁니다. 끄려면 LOG=0)');
    }
  });
}

/** 같은 와이파이에서 폰이 칠 수 있는 주소들 */
function lanAddresses() {
  const out = [];
  try {
    const nets = require('node:os').networkInterfaces();
    Object.keys(nets).forEach(name => {
      (nets[name] || []).forEach(n => {
        if (n.family !== 'IPv4' || n.internal) return;
        /* 도커·VM 이 만드는 가상 인터페이스는 폰에서 못 닿습니다.
           찍어 봐야 "쳐 봤는데 안 되는데요" 가 됩니다. */
        if (/^(docker|br-|veth|vboxnet|utun|tun|tap)/.test(name)) return;
        out.push(n.address);
      });
    });
  } catch (e) {}
  return out;
}

/** 지금 서빙하는 폴더가 개발 트리(prototype/)인가 — 배포본에는 없는 파일로 봅니다. */
function isDevTree(dir) {
  try {
    return fs.existsSync(path.join(dir, 'css', 'uid.css')) ||
           fs.existsSync(path.join(dir, 'js', 'screens', 'idindex.js'));
  } catch (e) { return false; }
}

module.exports = { server, api, db };
