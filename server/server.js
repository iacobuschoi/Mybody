/* =============================================================================
 * server/server.js — Mybody 자가호스팅 서버 (의존성 0, Node 내장 기능만)
 *
 *   node server/server.js
 *   PORT=8080 DB=./mybody.db STATIC=../prototype node server/server.js
 *
 * 권한은 전부 서버에서 겁니다. 클라이언트가 보내는 "나는 누구다"를 믿지 않고
 * 토큰으로만 판단합니다.
 *
 * 가입 · 로그인 · 복구 말고 로그인 없이 받는 길은 셋뿐입니다 — /health · /version,
 * 그리고 앱 안 「의견 보내기」(POST /api/feedback). 의견은 로그인 없이 쓰는 사람도 보낼 수 있어야 해서
 * 토큰이 없거나 틀려도 401 이 아니라 익명으로 받습니다. 그 대신 하루 개수(사람마다 ·
 * 주소마다 · 서버 전체 — 본문을 받기 전과 저장 직전에 두 번), 동시에 받는 수, 사진
 * 검사(server/feedback.js)로 막습니다. 설정에
 * feedbackNotify(아이디)를 적어 두면 새 의견이 올 때 그 사람 폰으로 "새 의견이
 * 왔어요" 한 줄이 10분에 한 번까지 갑니다 — 의견 내용은 알림에 안 실립니다.
 * 그 아이디의 계정(운영자)만 앱 설정의 「의견함」(/api/feedback/inbox…)에서 의견을
 * 읽습니다. 받는 길과 반대로 읽는 길은 로그인 관문 **뒤**에 있고, 운영자인지는 요청마다
 * 서버가 가립니다(handleFeedbackInbox). 같은 운영자만 「가입자 목록」(/api/operator/users —
 * 아이디 · 표시 이름 · 가입일)도 봅니다(handleOperator).
 *
 * /api 밖에서 로그인 없이 여는 페이지가 정적 파일 말고 하나 더 있습니다 — 친구 초대
 * 링크(GET /i/<코드>). DB 를 보지 않고 코드 모양만 봅니다(아래 serveInvite). 그 링크를
 * 폰이 앱으로 바로 열게 하는 파일 둘(/.well-known/assetlinks.json ·
 * /.well-known/apple-app-site-association)도 로그인 없이 나갑니다(아래 "앱 링크 파일").
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
const { open, makeApi, str, USERS_LIST_MAX } = require('./db.js');
const { runOcr: callOcr } = require('./ocr.js');
const PUSH = require('./push.js');
const FCMLIB = require('./fcm.js');
const APPVER = require('./appversion.js');
const FEEDBACK = require('./feedback.js');

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
  put('FCM_SERVICE_ACCOUNT', cfg.fcmServiceAccount);
  put('OWNER', cfg.owner);
  put('OWNER_CONTACT', cfg.ownerContact);
  put('ORIGIN', cfg.origin);
  put('DB', cfg.db);
  /* 새 의견이 오면 알림을 받을 계정의 **아이디**. 비워 두면 알림 없음. */
  put('FEEDBACK_NOTIFY', cfg.feedbackNotify);
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
    /* x-mybody-app — 앱이 모든 요청에 싣는 판 표시(주인 표시를 아는 판인가). 웹 빌드가 다른
       주소에서 부를 때 미리 묻기(OPTIONS)에 걸리지 않게. 지금은 적어 두기만 합니다. */
    'Access-Control-Allow-Headers': 'content-type, authorization, x-mybody-app',
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
 * 수 없으니, 시간으로 끊습니다.
 *
 * 상한을 올린 길(의견 6.2MB)은 시간도 같은 비율로 늘려 받습니다(timeoutMs) — 같은
 * 30초에 세 배를 올리라고 하면, 올리기가 느린 폰(1Mbps 면 6MB 에 50초)의 의견은
 * 다 오기 전에 408 로 끊기고 앱은 90초를 기다린 끝에 「못 보냈어요」 를 봅니다. */
const BODY_TIMEOUT_MS = Number(process.env.BODY_TIMEOUT_MS || 30_000);

function readBody(req, limit = 2_000_000, timeoutMs = BODY_TIMEOUT_MS) {
  const HARD = limit * 4;
  return new Promise((resolve, reject) => {
    let n = 0, over = false, done = false; const chunks = [];
    const timer = setTimeout(() => {
      if (done) return;
      done = true;
      chunks.length = 0;
      reject(Object.assign(new Error('본문이 너무 느립니다'), { status: 408 }));
      req.destroy();
    }, timeoutMs);
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

/* 친구 요청 · 수락 알림의 둘째 줄 — 받는 사람이 친구에게 **보여 주게 될 것**.
 *
 * 예전엔 "서로의 운동 체크가 보입니다 · 몸 숫자는 기본 비공개" 로 못 박혀
 * 있었습니다. 기본값을 사람마다 바꿀 수 있게 된 뒤로는 거짓말이 될 수 있고,
 * 하필 수락을 누를지 정하는 순간의 문장입니다 — 기본값에서 체중을 켜 둔
 * 사람이 "기본 비공개" 를 믿고 수락하면 곧바로 체중이 나갑니다. 그래서 그
 * 사람의 실제 값(s)으로 씁니다. 몸 쪽이 하나라도 켜져 있으면 그걸 먼저
 * 말합니다. lead 는 '수락하면 상대에게' · '친구에게'. */
const NOTICE_BODY = [['weightTrend', '체중 변화'], ['smmTrend', '골격근 변화'],
                     ['bfmTrend', '체지방 변화'], ['planProgress', '목표 진행률'],
                     ['absolute', '실제 수치']];
function shareNotice(s, lead) {
  const f = s || {};
  const body = NOTICE_BODY.filter(([k]) => f[k] === true).map(([, l]) => l);
  if (body.length) return lead + ' 내 ' + body.join(' · ') + '도 보입니다 (기본 공유 설정)';
  const act = [];
  if (f.streak === true || f.schedule === true) act.push('운동 체크');
  if (f.diet === true) act.push('식단');
  if (!act.length) return lead + ' 내 기록은 안 보입니다 (기본 공유 설정)';
  const last = act[act.length - 1];
  const code = last.charCodeAt(last.length - 1) - 0xAC00;
  const josa = code >= 0 && code < 11172 && code % 28 ? '이' : '가';
  return lead + ' 내 ' + act.join(' · ') + josa + ' 보입니다 · 몸 숫자는 기본 비공개';
}

/* --- 앱 알림(FCM) ---------------------------------------------------------
 *
 * 친구의 운동 독촉이 앱이 아니라 크롬(웹 푸시)으로 왔습니다. 앱에는 서버가
 * 밀어 주는 길이 없어서, 크롬 구독이 있는 사람에게는 크롬이 먼저 울리고
 * 앱은 나중에 켜질 때에야 같은 독촉을 띄웠습니다.
 *
 * 서비스 계정 파일(~/.mybody/fcm-service-account.json)이 있으면 켜집니다.
 * 없으면 null — 조용히 꺼지고 모든 것이 예전처럼 웹 푸시로만 갑니다.
 * 파일은 서버가 뜰 때 한 번 읽습니다. 파일을 놓거나 바꾼 뒤에는 서버를
 * 다시 띄워야 합니다(뜰 때 켜짐/꺼짐을 한 줄로 말합니다).
 * -------------------------------------------------------------------------- */
const FCM_STATE = FCMLIB.load(process.env);
const FCM = FCM_STATE.sender;

/* 앱 쪽이 **우리 설정 문제로** 못 보낸 경우. 접근 토큰을 못 받았거나(열쇠 폐기 ·
   시계 어긋남), APNs 키를 안 올렸거나, 권한이 없는 경우입니다. 기기가 전부
   이렇게 막혔으면 크롬 알림을 막지 않습니다 — 막으면 그 사람은 아무 데서도
   못 받고, 우리는 "알림을 켰는데 안 온다" 를 만든 셈이 됩니다. */
function fcmBlockedOnOurSide(r) {
  return r.code === 'AUTH' || r.code === 'THIRD_PARTY_AUTH_ERROR' ||
         r.status === 401 || r.status === 403;
}

/* FCM 으로 나가는 제목 · 본문. 웹 푸시는 종단 암호화라 이름과 숫자를 실어도 중계하는
   쪽(구글 · 모질라 · 애플)이 못 읽지만, FCM 의 notification 은 평문이라 구글과 애플(APNs)이
   읽습니다. 그래서 앱 알림에는 이름 · 숫자 · 공유 설정 없이 무슨 일인지만 싣고, 누구인지는
   앱이 열린 뒤 서버에서 가져와 보여 줍니다(친구 탭 · 독촉 띠). */
const APP_TEXT = {
  poke: { t: '친구가 운동하라고 콕 찔렀어요', b: '오늘 운동 어때요?' },
  workout: { t: '친구가 운동했어요', b: '친구 탭에서 확인하세요' },
  friend_request: { t: '친구 요청이 왔어요', b: '친구 탭에서 확인하세요' },
  friend_accept: { t: '친구 요청이 수락됐어요', b: '친구 탭에서 확인하세요' },
  /* 초대 링크로 곧 친구가 된 경우 — 코드 주인은 요청을 보낸 적이 없어서 "수락됐어요" 가 어색했습니다
     (0.2.19 리뷰). 이름 없이 "생겼다" 만. */
  friend_link: { t: '새 친구가 생겼어요', b: '친구 탭에서 확인하세요' },
  /* 주인에게만 갑니다(FEEDBACK_NOTIFY). 의견 글 · 보낸 사람 · 판은 싣지 않습니다 —
     누르면 앱이 「의견함」을 엽니다(route 'feedback'). 내용은 그 화면이 로그인한 채로
     서버에서 가져오고, 알림은 "왔다" 만 알리면 됩니다. */
  feedback: { t: '새 의견이 왔어요', b: '눌러서 보기' }
};
const APP_TEXT_FALLBACK = { t: '친구 알림이 왔어요', b: '앱에서 확인하세요' };

/** 이 사람에게 FCM 으로 보낼 것 — 웹 푸시용 t · b 는 절대 옮겨 싣지 않습니다. */
function appNoteFor(userId, n) {
  const text = APP_TEXT[n.kind] || APP_TEXT_FALLBACK;
  /* tag(같은 칸 덮어쓰기)에 사용자 id 를 그대로 쓰면 구글 · 애플에 내부 id 가 남습니다.
     독촉은 독촉 번호로(앱이 같은 칸을 가리키려면 앱도 알 수 있는 값이어야 합니다),
     나머지는 받는 사람마다 다른 HMAC 으로 — 여러 사람의 알림을 서로 잇지 못하게. */
  const tag = n.appTag || (n.collapse && FCM ? FCM.tagFor(n.collapse[0], userId, n.collapse[1]) : '');
  return { t: text.t, b: text.b, route: n.route, kind: n.kind, tag, data: n.data };
}

/**
 * 한 사람에게 한 건 — 앱(FCM) 먼저, 크롬(웹 푸시)은 최근 30일 안에 앱이
 * 등록되지 않은 사람에게만. 죽은 기기 · 죽은 구독은 정리합니다.
 *
 * note: { t, b, u, route, kind, appTag, collapse, data, onDelivered }
 *   t · b · u  웹 푸시(암호화)의 제목 · 본문 · 누르면 열 주소. FCM 에는 안 실립니다
 *   kind       무슨 소식인가 — FCM 의 일반 문구(APP_TEXT)를 고릅니다
 *   route      앱이 누르면 갈 곳('pokes' · 'social' · 'feedback' — 운영자의 「의견함」)
 *   appTag     FCM 의 tag 를 그대로(독촉: 'poke-<번호>')
 *   collapse   [접두어, 누구에 대한 소식인가] — 받는 사람별 HMAC tag 로 바뀝니다
 *   onDelivered  FCM 이 한 기기에라도 받았을 때 **바로** 한 번 — 나머지 기기로 보내기를
 *              기다리지 않습니다. 앱은 이 표시(독촉의 pushed)만 보고 중복을 거르는데,
 *              기기마다 10초씩 기다린 뒤에 적으면 그 사이에 가져간 앱이 한 번 더 띄웁니다.
 *
 * 누구에게 보낼지는 부르는 쪽이 이미 정했습니다(공유 설정 · 차단). 여기서는
 * 사람을 늘리지 않습니다 — 알림이 공유 설정을 우회하는 뒷문이 되면 안 됩니다.
 */
async function pushToUser(userId, note) {
  const n = note || {};
  let tried = 0, delivered = 0, blocked = 0;
  if (FCM) {
    const devices = api.pushDevicesOf(userId);
    const appNote = devices.length ? appNoteFor(userId, n) : null;
    for (const d of devices) {
      tried++;
      try {
        const r = await FCM.send(d.token, appNote);
        if (r.ok) {
          if (!delivered++ && typeof n.onDelivered === 'function') {
            try { n.onDelivered(); } catch (e) {}
          }
        } else if (r.gone) api.dropPushDevice(d.token);
        else {
          api.notePushDeviceFail(d.token);
          if (fcmBlockedOnOurSide(r)) blocked++;
        }
      } catch (e) { api.notePushDeviceFail(d.token); }
    }
  }
  if (!VAPID) return;
  /* 앱이 있으면 크롬은 조용히 — 같은 독촉이 두 번 울리고, 하필 크롬이 먼저
     울렸습니다. 알림을 거절한 폰은 "앱이 있다" 로 치지 않습니다(db.js). */
  const allBlocked = tried > 0 && delivered === 0 && blocked === tried;
  if (FCM && !allBlocked && api.hasRecentAppDevice(userId, 30)) return;
  const payload = JSON.stringify({ t: n.t, b: n.b, u: n.u || '/#P15' });
  for (const sub of api.pushSubsOf(userId)) {
    try {
      const r = await PUSH.send(sub, payload, VAPID);
      if (r.gone) api.dropPushSub(sub.endpoint);
      else if (!r.ok) api.notePushFail(sub.endpoint);
    } catch (e) { api.notePushFail(sub.endpoint); }
  }
}

async function fanoutPush(ownerId, snap) {
  if (!VAPID && !FCM) return;
  const who = api.me(ownerId);
  const name = (who && who.displayName) || '친구';
  /* 보내는 말은 한 줄뿐이고, 늘 좋은 소식입니다.
     "이번 주 3일째" 처럼 늘어난 숫자만 들어갑니다 — 무슨 요일에 무슨
     운동을 했는지는 스냅샷에 아예 없으므로 보낼 수도 없습니다. */
  const note = {
    t: name + '님이 운동했습니다',
    b: '이번 주 ' + snap.keptDays + '일째' +
       (snap.plannedDays ? ' · 계획 ' + snap.plannedDays + '일' : ''),
    u: '/#P15', route: 'social', kind: 'workout',
    /* 같은 친구의 소식은 한 칸을 덮어씁니다 — 하루하루 쌓이면 소음입니다.
       이름 · 숫자는 웹 푸시(암호화)에만 실리고 앱 알림은 일반 문구입니다(APP_TEXT). */
    collapse: ['news', ownerId]
  };
  /* 받는 사람은 공유 설정으로 거릅니다(일정을 안 보여 주기로 한 친구는 뺌).
     웹 구독이 없어도 앱으로 받을 수 있으므로 기기가 아니라 사람으로 셉니다. */
  for (const viewer of api.newsViewersFor(ownerId)) await pushToUser(viewer, note);
}

/* --- 앱 안 「의견 보내기」 ------------------------------------------------
 *
 * 검사 규칙(글 2000자 · 사진 3장 · 한 장 1.5MB · PNG/JPEG 앞머리)은 server/feedback.js,
 * 저장은 db.js 입니다. 여기서는 누가 보냈나 · 오늘 몇 개째인가 · 주인에게 알릴까만 봅니다.
 * -------------------------------------------------------------------------- */
/* 하루 개수. 로그인했으면 사람마다(DB 에서 셈 — 껐다 켜도 안 풀림), 아니면 보내온
   주소마다(메모리 — 주소를 DB 에 남기지 않으려고). 터널 뒤에서 TRUST_PROXY 를 안 켰으면
   익명은 전부 한 주소로 보여 한 칸을 나눠 씁니다(위 clientIp 주석과 같은 사정). */
const FEEDBACK_PER_DAY = Number(process.env.FEEDBACK_PER_DAY || FEEDBACK.PER_DAY);
const FEEDBACK_PER_DAY_TOTAL = Number(process.env.FEEDBACK_PER_DAY_TOTAL || FEEDBACK.PER_DAY_TOTAL);
const FEEDBACK_NOTIFY = (process.env.FEEDBACK_NOTIFY || '').trim();
/* 알림 사이 간격. 시험(tools/test-feedback.js)이 10분을 기다리지 않고 "간격이 지나면
   다시 울린다" 를 보려고 줄입니다 — 운영에서는 기본값(10분) 그대로 두세요. */
const FEEDBACK_NOTIFY_GAP_MS = Number(process.env.FEEDBACK_NOTIFY_GAP_MS || FEEDBACK.NOTIFY_GAP_MS);
const feedbackNotifyAllowed = FEEDBACK.makeThrottle(FEEDBACK_NOTIFY_GAP_MS);
const anonFeedback = new Map();   // 'ip|YYYY-MM-DD' → 개수
let feedbackOwnerWarned = false;
/* 지금 본문을 받고 있는 의견 — 서버 전체 · 보낸 사람(계정 또는 주소)마다.
   의견 한 건은 받는 동안 본문(6MB)과 그걸 푼 사본 몇 벌을 메모리에 듭니다. 하루 개수는
   **저장한 것**만 세므로, 동시에 백 개를 열면 전부 "아직 0개" 로 보고 들어와 서버가
   메모리를 다 씁니다. 그래서 받는 중인 것의 수를 따로 묶습니다. 넘치면 503 — 429 는
   앱이 "오늘은 끝, 내일 다시" 로 읽지만 이건 잠시 뒤면 풀리는 일입니다. */
const FEEDBACK_INFLIGHT_MAX = 6;
const FEEDBACK_INFLIGHT_PER = 2;
let feedbackInflight = 0;
const feedbackInflightOf = new Map();   // 'u:<id>' · 'ip:<주소>' → 받는 중인 수

function anonFeedbackCount(ip, day) { return anonFeedback.get(ip + '|' + day) || 0; }
function anonFeedbackBump(ip, day) {
  const k = ip + '|' + day;
  anonFeedback.set(k, anonFeedbackCount(ip, day) + 1);
  // 지난 날 것만 버립니다 — 통째로 비우면 오늘 한도에 걸린 주소까지 풀립니다.
  if (anonFeedback.size > 5000) {
    for (const key of anonFeedback.keys()) { if (!key.endsWith('|' + day)) anonFeedback.delete(key); }
  }
}

/* 운영자 = 설정의 feedbackNotify(FEEDBACK_NOTIFY)에 적은 아이디의 계정. 없으면 아무도 아님.
 *
 * **요청마다 다시 찾습니다**(아이디 → 내부 id, 유일 색인 한 번). 기억해 두면 운영자가
 * 탈퇴하고 다시 가입했을 때(내부 id 가 바뀜) 옛 id 를 들고 있거나, 거꾸로 "없음" 을 들고
 * 있다가 가입한 뒤에도 의견함이 안 열립니다 — 무효화할 곳을 빠뜨리면 조용히 틀립니다.
 * 아이디는 로그인과 같은 규칙(앞뒤 공백 빼고 소문자)으로 맞춥니다(db.js userIdByHandle).
 *
 * 아이디로 적혀 있다는 것이 약점이기도 합니다: 그 계정을 지우면 아이디가 비고, 같은
 * 아이디로 새로 가입한 사람이 운영자가 됩니다. 그래서 계정을 지웠으면 설정의 아이디도
 * 지우거나 바꿔야 하고(server/README.md), 그 계정이 아직 없으면 뜰 때 크게 말합니다 — 누구나
 * 가입할 수 있는 서버(OPEN_SIGNUP)면 아무나, 아니어도 가입 코드를 받은 사람이면 그 아이디를 먼저 가져갑니다. */
function operatorId() {
  return FEEDBACK_NOTIFY ? api.userIdByHandle(FEEDBACK_NOTIFY) : null;
}
function isOperator(uid) {
  const op = operatorId();
  return !!(op && uid && op === uid);
}

/* 주인에게 "새 의견이 왔어요". 응답을 기다리게 하지 않습니다 — 알림이 늦는 것은
   괜찮지만, 보낸 사람 화면이 FCM 을 기다리며 굳으면 안 됩니다. 간격은 **보낼 사람을
   찾은 뒤에** 셉니다: 아이디를 잘못 적어 둔 동안 들어온 의견이 간격만 깎지 않게.
   앱 알림(FCM)은 누르면 「의견함」으로 갑니다(route 'feedback' · APP_TEXT.feedback).
   크롬(웹 푸시)은 앱이 없는 운영자에게만 가고, 웹 앱에는 의견함이 없어서 "눌러서 보기"
   대신 어디서 보는지를 적습니다. */
function notifyOwnerOfFeedback() {
  if (!FEEDBACK_NOTIFY || (!VAPID && !FCM)) return;
  const owner = operatorId();
  if (!owner) {
    if (!feedbackOwnerWarned) {
      feedbackOwnerWarned = true;
      console.log('  ⚠ 의견 알림: 설정(feedbackNotify)에 적은 아이디의 계정이 없어 알림을 못 보냅니다.');
    }
    return;
  }
  if (!feedbackNotifyAllowed()) return;
  pushToUser(owner, { kind: 'feedback', appTag: 'feedback', route: 'feedback', u: '/',
                      t: APP_TEXT.feedback.t, b: '앱의 설정 → 「의견함」에서 볼 수 있어요' })
    .catch(() => {});
}

/* --- 앱 안 「의견함」 (운영자만) -------------------------------------------
 *
 * 왜 있나
 *   "의견 어디서 봐" — 알림은 폰으로 오는데 보려면 노트북을 열어 도구를 돌려야 했습니다.
 *   알림을 누르면 바로 그 의견이 보여야 합니다. 그래서 운영자 계정의 앱에만 읽는 길을 엽니다.
 *
 * 약속 (앱: app/lib/src/api.dart · 의견함 화면)
 *   GET    /api/feedback/inbox?limit=30&before=<번호>
 *            → {ok, unread, items:[{id, createdAt, appVersion|null, platform|null, screen|null,
 *               text('' = 글 없음), read, images:[{n, type}], from:{name}|null(익명)}], nextBefore|null}
 *            새것부터 · 번호로 넘김(db.js feedbackInbox) · limit 1~50
 *   GET    /api/feedback/inbox/<번호>/image/<n>   사진 바이트 그대로(저장된 형식) · 없으면 404
 *   POST   /api/feedback/inbox/<번호>/read        읽음 표시(이미 읽었으면 그 시각 그대로)
 *   POST   /api/feedback/inbox/read-all           안 읽은 것 전부 — {upTo:<번호>} 를 주면 거기까지만
 *   DELETE /api/feedback/inbox/<번호>             의견과 사진을 함께(한 트랜잭션)
 *   읽음 · 지우기는 없는 번호여도 {ok:true} 입니다 — 다른 기기에서 먼저 지웠거나 1년이 지나
 *   서버가 지운 것을 다시 지우는 것은 할 일이 없는 것이지 실패가 아닙니다. 노트북에 꺼내 둔
 *   캡처는 tools/feedback.js 가 다음에 돌 때 "DB 에 더는 없는 번호" 로 보고 지웁니다.
 *
 * 막는 것
 *   · 로그인 관문 뒤에 있습니다 — 토큰이 없거나 틀리면 다른 길과 같은 401.
 *   · 운영자가 아니면 **어느 길이든**(사진 포함) 403 「운영자만 볼 수 있어요」. 누가 운영자인지는
 *     어디에도 내보내지 않습니다 — /api/me 의 isOperator 는 본인에게만, 운영자일 때만 붙습니다.
 *   · 의견 · 사진 번호는 1 이상의 정수만(아니면 400)이고, 사진 번호가 1~3 밖이면 없는 것(404).
 *     SQLite 까지 이상한 값이 내려가지 않게.
 *   · 캐시 금지(private, no-store) — 몸 숫자가 찍혀 있을 수 있는 캡처가 폰 · 중간 캐시에 남지 않게.
 *   · 로그에는 경로와 상태만 남습니다(logLine) — 의견 내용은 안 찍힙니다.
 * -------------------------------------------------------------------------- */
const INBOX_HEADERS = { 'Cache-Control': 'private, no-store' };
/* 경로의 번호 — 1 이상의 안전한 정수만. "1e3" · "0x10" · "-1" · 아주 긴 숫자는 거절. */
function inboxId(s) {
  if (typeof s !== 'string' || !/^[1-9]\d{0,15}$/.test(s)) return null;
  const n = Number(s);
  return Number.isSafeInteger(n) ? n : null;
}

async function handleFeedbackInbox(req, res, url, p, method, me) {
  const fail = (status, msg) => send(res, status, { ok: false, error: msg, reason: msg }, INBOX_HEADERS);
  const ok = body => send(res, 200, Object.assign({ ok: true }, body || {}), INBOX_HEADERS);
  /* 경로 모양을 보기 **전에** 운영자부터 — 없는 길 · 틀린 번호로 두드려 봐도 운영자가
     아니면 똑같이 403 이라, 응답으로 어떤 길이 있는지 · 몇 번 의견이 있는지 알 수 없습니다. */
  if (!isOperator(me)) return fail(403, '운영자만 볼 수 있어요');

  if (p === '/feedback/inbox' && method === 'GET') {
    const raw = url.searchParams.get('before');
    let before = null;
    if (raw !== null && raw !== '') {
      before = inboxId(raw);
      /* 틀린 커서를 첫 쪽으로 바꿔 주면 앱의 "더 보기" 가 같은 쪽을 끝없이 다시 받습니다. */
      if (!before) return fail(400, 'before 는 의견 번호(1 이상의 정수)여야 합니다');
    }
    const limit = intParam(url.searchParams.get('limit'), 30, 1, 50);
    return ok(api.feedbackInbox({ before, limit }));
  }
  if (p === '/feedback/inbox/read-all' && method === 'POST') {
    const b = await readBody(req, 16_000);
    const rawUp = b && typeof b === 'object' && b.upTo !== undefined && b.upTo !== null
      ? b.upTo : url.searchParams.get('upTo');
    let upTo = null;
    if (rawUp !== null && rawUp !== undefined && rawUp !== '') {
      upTo = inboxId(String(rawUp));
      if (!upTo) return fail(400, 'upTo 는 의견 번호(1 이상의 정수)여야 합니다');
    }
    api.markAllFeedbackRead(upTo);
    return ok();
  }

  const m = p.match(/^\/feedback\/inbox\/([^/]+)(?:\/(read|image)(?:\/([^/]+))?)?$/);
  if (!m) return fail(404, '그런 경로가 없습니다');
  const id = inboxId(m[1]);
  if (!id) return fail(400, '의견 번호는 1 이상의 정수여야 합니다');

  if (m[2] === 'image' && m[3] !== undefined && method === 'GET') {
    const n = inboxId(m[3]);
    if (!n) return fail(400, '사진 번호는 1 이상의 정수여야 합니다');
    const im = n <= FEEDBACK.IMAGES_MAX ? api.feedbackImage(id, n) : null;
    if (!im) return fail(404, '그 사진이 없어요');
    /* 저장된 형식 그대로 — 단, 받을 때 검사하는 형식(PNG · JPEG)만. 서버를 거치지 않고 들어간
       행이 text/html 같은 것을 들고 있어도 그대로 내보내지 않습니다(nosniff 와 함께). */
    const type = Object.prototype.hasOwnProperty.call(FEEDBACK.TYPES, im.type) ? im.type : 'application/octet-stream';
    return send(res, 200, im.data, Object.assign({ 'Content-Type': type,
                                                   'Content-Length': String(im.data.length) }, INBOX_HEADERS));
  }
  if (m[2] === 'read' && m[3] === undefined && method === 'POST') {
    api.markFeedbackRead([id]);
    return ok();
  }
  if (m[2] === undefined && method === 'DELETE') {
    api.deleteFeedback(id);
    return ok();
  }
  return fail(404, '그런 경로가 없습니다');
}

/* --- 앱 안 「가입자 목록」 (운영자만) ---------------------------------------
 *
 * 왜 있나
 *   비밀번호를 잊은 친구의 아이디를 찾으려면 노트북에서 tools/reset-password.js 를 인자 없이
 *   돌려야 했습니다. 운영자 폰의 설정 → 「가입자 목록」 에서 보고, 줄을 눌러 복사한 아이디를
 *   노트북의 reset-password.js <아이디> 에 붙여 넣습니다.
 *
 * 약속 (앱: app/lib/src/api.dart ApiOperatorUsers · screens/user_list.dart)
 *   GET /api/operator/users?limit=<1~1000>
 *         → {ok, total, users:[{handle, displayName, createdAt, me?:true}]}
 *         새 가입부터 · 기본이자 최대 1000명(db.js USERS_LIST_MAX) · total 은 자르기 전 전체 수 ·
 *         me 는 운영자 본인 줄에만
 *
 * 막는 것 — 의견함과 같은 규칙입니다(위 handleFeedbackInbox).
 *   · 로그인 관문 뒤(401). 운영자가 아니면 /api/operator/ 아래 어느 길이든 경로를 보기 전에 403.
 *   · 싣는 것은 아이디 · 표시 이름 · 가입 시각뿐 — 비밀번호 · 복구 코드 해시, 토큰, 초대 코드,
 *     내부 id, 알림 기기는 질의에서부터 고르지 않습니다(db.js operatorListUsers).
 *   · 캐시 금지(의견함과 같은 머리) · 로그에는 경로와 상태만.
 * -------------------------------------------------------------------------- */
function handleOperator(res, url, p, method, me) {
  const fail = (status, msg) => send(res, status, { ok: false, error: msg, reason: msg }, INBOX_HEADERS);
  if (!isOperator(me)) return fail(403, '운영자만 볼 수 있어요');
  if (p === '/operator/users' && method === 'GET') {
    const limit = intParam(url.searchParams.get('limit'), USERS_LIST_MAX, 1, USERS_LIST_MAX);
    return send(res, 200, Object.assign({ ok: true }, api.operatorListUsers({ limit, meId: me })), INBOX_HEADERS);
  }
  return fail(404, '그런 경로가 없습니다');
}

/* 오늘 한도에 걸렸으면 그 까닭(429 로 내보낼 말), 아니면 null. 저장한 것만 셉니다:
   형식이 틀려 거절된 요청은 한도를 안 깎습니다(판독 ocrCount 와 같은 이유). */
function feedbackOverLimit(uid, ip, day) {
  const since = day + 'T00:00:00.000Z';
  if (api.countFeedbackSince(null, since) >= FEEDBACK_PER_DAY_TOTAL) {
    return '오늘은 이 서버가 의견을 더 받을 수 없습니다. 내일 다시 보내 주세요';
  }
  const mine = uid ? api.countFeedbackSince(uid, since) : anonFeedbackCount(ip, day);
  if (mine >= FEEDBACK_PER_DAY) {
    return '오늘은 의견을 ' + FEEDBACK_PER_DAY + '개까지 보낼 수 있습니다. 내일 다시 보내 주세요';
  }
  return null;
}

async function handleFeedback(req, res, ip) {
  /* 약속한 모양은 {ok:false, error}. 앱의 Api 는 reason 을 읽으므로 같은 말을 둘 다 싣습니다. */
  const fail = (status, msg) => send(res, status, { ok: false, error: msg, reason: msg });
  /* 토큰이 없거나 틀리거나 만료됐으면 **익명**입니다. 401 을 주면 로그아웃된 채로 보낸
     사람의 의견이 통째로 사라지고, 앱은 그걸 "로그인이 풀렸다" 로 읽습니다. */
  const who = api.userForToken(bearer(req));
  const uid = who ? who.id : null;
  const day = ocrDay();

  /* 한도는 본문을 받기 **전에** 봅니다 — 6MB 를 다 받아 놓고 거절하지 않게. */
  const over = feedbackOverLimit(uid, ip, day);
  if (over) return fail(429, over);
  const key = uid ? 'u:' + uid : 'ip:' + ip;
  if (feedbackInflight >= FEEDBACK_INFLIGHT_MAX || (feedbackInflightOf.get(key) || 0) >= FEEDBACK_INFLIGHT_PER) {
    return fail(503, '지금 받는 의견이 많습니다. 잠시 뒤에 다시 보내 주세요');
  }

  let body;
  feedbackInflight++;
  feedbackInflightOf.set(key, (feedbackInflightOf.get(key) || 0) + 1);
  try {
    /* 본문이 다른 길의 세 배라 기다리는 시간도 세 배(readBody 주석) — 앱은 90초를 기다립니다. */
    body = await readBody(req, FEEDBACK.BODY_LIMIT, BODY_TIMEOUT_MS * 3);
  } catch (e) {
    if (!e || !e.status) throw e;
    return fail(e.status, e.status === 413 ? '보낸 내용이 너무 큽니다 (사진은 한 장 1.5MB · 3장까지)' : e.message);
  } finally {
    feedbackInflight--;
    const left = (feedbackInflightOf.get(key) || 1) - 1;
    if (left > 0) feedbackInflightOf.set(key, left); else feedbackInflightOf.delete(key);
  }
  const r = FEEDBACK.parseFeedback(body);
  if (!r.ok) return fail(400, r.reason);
  /* 한 번 더 봅니다. 본문을 받는 몇십 초 사이에 같은 사람(주소)의 다른 요청이 먼저
     저장됐을 수 있습니다 — 앞의 검사만 믿으면 동시에 보낸 것들이 전부 "19개째" 로 보고
     한도를 넘어 들어옵니다. 여기서 저장까지는 await 가 없어 끼어들 틈이 없습니다. */
  const late = feedbackOverLimit(uid, ip, day);
  if (late) return fail(429, late);
  const id = api.addFeedback(uid, r.value);
  if (!uid) anonFeedbackBump(ip, day);
  notifyOwnerOfFeedback();
  return send(res, 200, { ok: true, id });
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

  /* 앱 안 「의견 보내기」 — 로그인은 **있으면 묶고, 없어도 받습니다.** 그래서 아래
     로그인 관문(401)보다 앞에 둡니다. 자세한 것은 handleFeedback. */
  if (p === '/feedback' && method === 'POST') return handleFeedback(req, res, reqIp);

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
  /* isOperator — 앱이 설정에 「의견함」 · 「가입자 목록」 칸을 보일지 정하는 표시. **본인에게만,
     운영자일 때만** 붙습니다(아니면 칸 자체가 없음). 친구 목록 · 스냅샷 같은 남에게 가는 응답에는
     안 실어서 누가 운영자인지 다른 사람은 알 수 없습니다. 보이는 칸은 편의일 뿐이고, 막는 것은
     두 곳의 모든 길이 요청마다 다시 가리는 쪽입니다(handleFeedbackInbox · handleOperator).
     PATCH 도 같은 user 를 돌려줍니다 — 앱이 그 답으로 자기 정보를 갈아 끼워도 칸이 안 사라지게. */
  const meView = u => (u && isOperator(me) ? Object.assign(u, { isOperator: true }) : u);
  if (p === '/me' && method === 'GET') return send(res, 200, { ok: true, user: meView(api.me(me)), stats: api.stats(me) });
  if (p === '/me' && method === 'PATCH') return send(res, 200, { ok: true, user: meView(api.updateMe(me, await readBody(req))) });
  if (p === '/me' && method === 'DELETE') { api.deleteMe(me); return send(res, 200, { ok: true }); }
  if (p === '/me/consent' && method === 'POST') {
    const r = api.consent(me, await readBody(req));
    return send(res, r.ok ? 200 : 400, r);
  }

  /* 운영자의 「의견함」 — 로그인 관문 뒤. 운영자인지는 그 안에서 요청마다 가립니다.
     받는 길(POST /feedback)은 위, 관문 앞에 따로 있습니다. */
  if (p === '/feedback/inbox' || p.startsWith('/feedback/inbox/')) {
    return handleFeedbackInbox(req, res, url, p, method, me);
  }
  /* 운영자의 「가입자 목록」 — 의견함처럼 관문 뒤, 운영자인지는 안에서 요청마다(handleOperator). */
  if (p === '/operator' || p.startsWith('/operator/')) return handleOperator(res, url, p, method, me);

  if (p === '/friends' && method === 'GET') return send(res, 200, { ok: true, friends: api.listFriends(me) });
  if (p === '/friends/request' && method === 'POST') {
    const b = await readBody(req);
    /* 안드로이드 앱 0.2.3 까지는 'code' 로 보냈습니다. 이미 깔린 앱이 서버만
       다시 띄우면 친구 추가가 되도록 둘 다 받습니다.
       via:'link' — 앱이 초대 링크(· 설치 추천인)로 받은 코드입니다. 그러면 요청이 아니라
       그 자리에서 친구가 됩니다(주인 의견 48 · db.js sendRequest). 손으로 친 코드 · 클립보드에서
       고른 코드는 via 없이 와서 예전처럼 코드 주인의 수락을 기다립니다. 다른 값은 없는 것으로.
       코드 주인이 나를 거절 · 끊기 · 차단한 적이 있으면 링크여도 요청입니다(db.js friend_refusals) —
       그때 답 · 알림은 아래 pending 그대로입니다. */
    const viaLink = !!(b && b.via === 'link');
    const r = api.sendRequest(me, b.inviteCode || b.code, { viaLink });
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
    /* 링크로 이미 친구인 사이(already)는 아무것도 안 바뀌었으니 알림도 없습니다 — 링크를 다시
       누를 때마다 코드 주인의 폰이 울리면 안 됩니다. */
    if (r.ok && r.otherId && !r.already) {
      const who = api.me(me);
      const name = (who && who.displayName) || '누군가';
      /* 둘째 줄은 **알림을 받는 사람이 보여 주게 될 것** — 그 사람의 실제 값으로.
         요청이면 아직 관계가 없으니 그 사람의 기본값(수락하면 그대로 복사됩니다),
         맞요청 · 초대 링크로 방금 친구가 됐으면 이미 복사된 그 방향의 행.
         초대 링크면 코드 주인은 수락을 누른 적이 없으니 "○○님과 친구가 됐어요" 로 알립니다.
         앱 알림(FCM)은 일반 문구 APP_TEXT.friend_link("새 친구가 생겼어요") — 코드 주인은 요청을
         보낸 적이 없으니 "친구 요청이 수락됐어요" 는 어색합니다. 이름은 여전히 싣지 않습니다. */
      const msg = r.status === 'accepted'
        ? { t: name + (viaLink ? '님과 친구가 됐어요' : '님과 친구가 되었습니다'),
            b: shareNotice(api.shareFields(r.otherId, me), '친구에게'), kind: viaLink ? 'friend_link' : 'friend_accept' }
        : { t: name + '님이 친구 요청을 보냈습니다',
            b: shareNotice(api.shareDefaults(r.otherId), '수락하면 상대에게'), kind: 'friend_request' };
      /* 이름 · 공유 기본값은 웹 푸시(암호화)에만 실립니다. 앱 알림(FCM)은 평문이라
         "친구 요청이 왔어요" 같은 일반 문구만 갑니다(APP_TEXT). */
      pushToUser(r.otherId, Object.assign(msg, { u: '/#P15', route: 'social', collapse: ['friend', me] }))
        .catch(() => {});
    }
    /* 친구가 됐으면(맞요청 · 초대 링크) 상대의 표시 이름을 같이 줍니다 — 앱이 「○○님과 친구가
       됐어요」 라고 말하게. **이때만** 싣습니다: 이제 친구라 친구 목록에도 뜨는 이름이고,
       요청만 간 상태(pending)나 실패에 실으면 코드 → 이름 사전이 됩니다(초대 페이지 주석과 같은 까닭). */
    if (r.ok && r.status === 'accepted' && r.otherId) {
      const them = api.me(r.otherId);
      return send(res, 200, Object.assign({}, r, { friend: { name: (them && them.displayName) || '' } }));
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
      pushToUser(uid, {
        t: name + '님이 친구 요청을 수락했습니다',
        b: shareNotice(api.shareFields(uid, me), '친구에게'),
        u: '/#P15', route: 'social', kind: 'friend_accept', collapse: ['friend', me]
      }).catch(() => {});
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

  /* 새 친구에게 기본으로 보여 주는 것 — 친구를 맺는 순간 그 관계로 복사됩니다.
     이 길을 모르는 옛 앱은 부르지 않을 뿐이고, 그때도 accept 는 이 값을
     씁니다(안 정했으면 blankShare() 그대로 — 예전과 같은 동작).
     거절을 200 으로 보내지 않습니다 — 앱이 성공으로 읽고 스위치를 켠 채로 둡니다.
     apply 의 {expect} 가 저장된 값과 다르면 409 — 사람이 본 것과 다른 값을
     친구 전원에게 쓰지 않습니다(db.js applyShareDefaults). */
  if (p === '/share-defaults' && method === 'GET') {
    return send(res, 200, { ok: true, defaults: api.shareDefaults(me) });
  }
  if (p === '/share-defaults' && method === 'PUT') {
    const r = api.setShareDefaults(me, await readBody(req));
    return send(res, r.ok ? 200 : 400, r);
  }
  if (p === '/share-defaults/apply' && method === 'POST') {
    const b = await readBody(req);
    const r = api.applyShareDefaults(me, b && typeof b === 'object' ? b.expect : undefined);
    return send(res, r.ok ? 200 : (r.conflict ? 409 : 400), r);
  }

  /* --- 운동 독촉 ------------------------------------------------------- */
  if (p === '/pokes' && method === 'POST') {
    const b = await readBody(req);
    const r = api.poke(me, b && b.userId, b && b.kind);
    if (r.ok) {
      /* 앱 알림(FCM)이 있으면 앱으로 바로, 없으면 예전처럼 웹 푸시로.
         앱은 켜질 때도 독촉을 가져가는데, FCM 으로 이미 닿은 것은 pushed 로
         표시돼서 같은 알림을 또 띄우지 않습니다. 웹 푸시 문구는 앱이 가져가서
         띄우는 것(app/lib/src/pokes.dart)과 같게 두고, 앱 알림은 이름 없는 일반
         문구입니다(APP_TEXT — 구글 · 애플이 읽는 평문이라).
         tag 는 독촉 번호 — 앱이 가져가서 띄우는 로컬 알림도 같은 tag 를 써서, 둘이
         엇갈려 와도 안드로이드에서는 한 칸을 덮어씁니다(main.dart). */
      const who = api.me(me);
      const name = (who && who.displayName) || '친구';
      const pokeId = r.id;
      pushToUser(String(b.userId), {
        t: name + '님이 운동하라고 콕 찔렀어요', b: '오늘 운동 어때요?', u: '/#P15',
        route: 'pokes', kind: 'poke', appTag: 'poke-' + pokeId, data: { pokeId: String(pokeId) },
        onDelivered: () => api.markPokePushed(pokeId)
      }).catch(() => {});
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
    // 다른 계정의 요약(payload.owner ≠ 나)은 409 — db.js publishSnapshot.
    if (snap.conflict) ownerConflict(req, 'snapshots');
    return send(res, snap.ok ? 200 : (snap.conflict ? 409 : 400), snap);
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

  /* --- 앱 알림(FCM) 기기 -------------------------------------------------
   * 앱이 켜질 때마다 자기 토큰을 올립니다. FCM 이 꺼진 서버에서도 받아
   * 둡니다 — 주인이 나중에 서비스 계정 파일을 놓고 다시 띄우면 그때부터
   * 바로 씁니다. 기기는 지금 로그인(세션)에 묶이므로, 로그아웃 · 탈퇴 때
   * 따로 지우지 않아도 같이 사라집니다.
   * -------------------------------------------------------------------- */
  if (p === '/push/device' && method === 'POST') {
    const b = await readBody(req, 16_000);
    const r = api.addPushDevice(me, tok, b);
    /* 409: 다른 계정의 살아 있는 로그인에 묶인 토큰인데 설치 비밀이 안 맞음(db.js). */
    return send(res, r.ok ? 200 : (r.conflict ? 409 : 400), Object.assign(r, { fcm: !!FCM }));
  }
  if (p === '/push/device' && method === 'DELETE') {
    const b = await readBody(req, 16_000);
    if (!b || typeof b.token !== 'string') return send(res, 400, { ok: false, reason: 'token 이 필요합니다' });
    /* 남의 토큰 · 없는 토큰 · 내 토큰 모두 200 {ok:true} — 답으로 토큰이 있는지 알 수 없게. */
    return send(res, 200, api.removePushDevice(me, b.token));
  }
  /* 설정 화면의 「푸시 알림」 줄이 fcm(서버가 앱으로 보낼 수 있나)을 봅니다. 크롬 쪽 칸
     (webSubs · webMuted)은 이제 앱 화면에 안 나옵니다 — 설정에서 크롬 이야기를 뺐습니다(주인
     의견 47). 옛 앱 · 검사용으로 그대로 둡니다. webMuted 는 "크롬 구독이 있어도 앱이 있어서
     크롬으로는 안 보낸다" 입니다. */
  if (p === '/push/status' && method === 'GET') {
    const c = api.pushCounts(me);
    return send(res, 200, { ok: true, fcm: !!FCM, web: !!VAPID,
                            devices: c.devices, webSubs: c.webSubs,
                            webMuted: !!FCM && api.hasRecentAppDevice(me, 30) });
  }
  /* 내 웹 푸시(크롬) 구독을 전부 지웁니다. 크롬이 알림을 쥐고 있으면 브라우저를
     안 열어도 계속 울립니다. 예전엔 설정의 「크롬(웹) 알림 끄기」 단추가 불렀고, 이제는
     앱이 이 기기의 앱 알림을 등록한 뒤 **계정마다 한 번 저절로** 부릅니다(주인 의견 47 ·
     app/lib/src/native_push.dart). 두 이름 다 받습니다. */
  if ((p === '/push/web' || p === '/push/web-subscriptions') && method === 'DELETE') {
    return send(res, 200, api.dropPushSubsOf(me));
  }
  m = p.match(/^\/snapshots\/([\w-]+)$/);
  if (m && method === 'GET') {
    return send(res, 200, api.friendSnapshots(me, m[1], intParam(url.searchParams.get('limit'), 26, 1, 200)));
  }

  if (p === '/sync/push' && method === 'POST') {
    const b = await readBody(req);
    const r = api.push(me, b.records);
    // 거절이면 200 으로 보내면 안 됩니다 — 클라이언트가 성공으로 읽고
    // 큐에서 지워 버립니다. 다른 계정의 기록 사본(syncMeta.owner ≠ 나)은 409 — db.js push.
    if (r.conflict) ownerConflict(req, 'sync/push');
    return send(res, r.ok ? 200 : (r.conflict ? 409 : 400), r);
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

/* /.well-known/assetlinks.json 은 예전에 여기서(웹 앱을 플레이에 감싸 올리던 TWA 용, 설정
   TWA_PACKAGE · TWA_FINGERPRINT) 냈습니다. 지금은 앱 링크 파일 둘이 아래 "앱 링크 파일" 에
   있고, 정적 파일보다 먼저 봅니다 — 내보내는 폴더에 같은 이름의 파일이 생겨도 그쪽이 이깁니다. */
function serveStatic(req, res, url) {
  let rel;
  try { rel = decodeURIComponent(url.pathname); }
  catch (e) { return send(res, 400, 'bad path', { 'Content-Type': 'text/plain; charset=utf-8' }); }

  /* %2E 처럼 돌려 적은 이름도 같은 대답을 받게 — 폴더 안의 파일이 끼어들 틈을 안 둡니다. */
  if (Object.hasOwn(WELL_KNOWN, rel)) return serveWellKnown(req, res, rel);

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

/* --- 친구 초대 링크 (GET /i/<코드>) ---------------------------------------
 *
 * 왜 있나
 *   친구를 부르는 길이 "코드 여덟 글자를 불러 주기" 뿐이었습니다. 받은 사람은 앱을 열고 ·
 *   친구 탭으로 가서 · 칸을 찾아 · 여덟 글자를 옮겨 칩니다. 앱이 아직 없으면 어디서 받는지부터
 *   물어야 합니다 — 비공개 시험이라 가게에서 검색해도 안 나옵니다. 링크 하나로 줄입니다:
 *   누르면 앱이 열려 바로 친구가 되고(주인 의견 48 — 코드 주인의 수락 없이, 앱이 보내는
 *   POST /friends/request 의 via:'link'), 앱이 없으면 받는 곳이 바로 보입니다.
 *
 * 약속 (앱의 딥링크 처리와 같아야 합니다)
 *   링크        <서버 주소>/i/<코드>     코드는 대문자 8자. 소문자로 오면 대문자 주소로 돌려보냅니다
 *   아이폰      mybody://invite/<코드>
 *   안드로이드  intent://invite/<코드>#Intent;scheme=mybody;package=<앱>;S.browser_fallback_url=<…>;end
 *               앱이 없으면 크롬이 fallback 으로 갑니다 — 시험 기간에는 이 페이지 + ?noapp=1
 *               (설치 안내를 앞세움: "앱이 없어서 설치 안내로 왔어요"), 정식 출시 뒤에는 바로
 *               플레이 가게(아래 추천인 붙은 주소).
 *   앱 링크     앱이 깔려 있고 폰이 이 주소를 앱의 것으로 확인했으면(아래 "앱 링크 파일") 이
 *               페이지는 **아예 안 뜹니다** — 링크를 누르는 순간 앱이 열립니다. 이 페이지는
 *               앱이 없거나 · 확인이 아직이거나 · 앱 안 브라우저(카카오톡 등)가 링크를 쥐고 놓지
 *               않을 때 보입니다. 그래서 할 일이 "앱이 없다고 보고 설치로 데려가기" 쪽입니다.
 *
 * 저절로 (주인의 말: "링크만 누르면 바로 친추 · 앱이 없으면 스토어로 · 모든 걸 자동으로")
 *   · 카카오톡 안 브라우저 — 앱 링크가 안 먹는 곳이라 곧바로 폰의 기본 브라우저로 넘깁니다
 *     (kakaotalk://web/openExternal). 거기서는 앱 링크가 앱을 엽니다.
 *   · 그 밖의 앱 안 브라우저(인스타그램 · 페이스북 · 라인 · 네이버) — 넘기는 길이 없어서
 *     "오른쪽 위 ⋯ → 다른 브라우저로 열기" 한 줄을 단추 위에 둡니다.
 *   · 안드로이드 — 열리자마자 intent 로 앱을 부릅니다(없으면 위 fallback). 크롬이 누름 없이는
 *     막을 수 있어서 "앱에서 열기" 단추는 그대로 둡니다.
 *   · 아이폰 — 여기까지 왔으면 앱 링크가 앱을 못 연 것입니다(앱이 없을 가능성이 큼). 1.5초 뒤
 *     설치 페이지(시험 기간: TestFlight · 뒤: App Store)로 갑니다 — 그 사이에 뭔가 눌렀거나
 *     다른 화면으로 갔으면 안 갑니다. "여기 있기"(?stay=1)로 멈춥니다. mybody:// 를 저절로
 *     부르지는 않습니다: 앱이 없는 아이폰에서는 "주소가 유효하지 않음" 창부터 뜹니다.
 *   · 한 탭에서 한 번씩만(sessionStorage) — 뒤로 가기로 돌아왔을 때 다시 튕기지 않게.
 *
 * 설치한 뒤에도 초대가 이어지게 (앱이 읽는 길은 app/lib/src/invite_link.dart · install_referrer.dart)
 *   · 플레이 주소에 추천인 invite=<코드> 를 붙입니다(&referrer=invite%3D<코드>) — 앱이 처음 켤 때
 *     한 번 설치 추천인(Play Install Referrer)으로 읽습니다. 묻지 않고 이어집니다.
 *   · 설치 단추를 누르면 "Mybody 초대 <코드> <이 페이지 주소>" 를 클립보드에 담고 갑니다.
 *     안드로이드 앱은 탭 화면이 처음 설 때 한 번 읽어 "친구 요청할까요?" 를 묻고, 아이폰 앱은
 *     스스로 읽지 않습니다(읽으면 "붙여넣기 허용" 창이 뜹니다) — 인사 화면 · 친구 추가의
 *     「초대 코드 붙여넣기」 를 누를 때 이걸 씁니다. 추천인이 없는 아이폰에게는 이것이 유일한
 *     길이라, 아이폰이 저절로 설치 페이지로 갈 때(담을 수 없음 — 아래)는 코드가 끊깁니다: 깐
 *     뒤 링크를 다시 누르면 됩니다. 담기는 누르는 순간에만 됩니다(브라우저 규칙). 못 담아도
 *     그냥 갑니다.
 *
 * 누구 코드인지 **찾지 않습니다**
 *   DB 를 보지 않습니다. "○○님이 초대했어요" 는 반갑지만, 주소만 두드려 보는 사람에게는
 *   코드 → 이름 사전이 됩니다(맞히면 그 사람 이름과 "이 서버에 있다" 가 샙니다). 모양만 맞으면
 *   있는 코드든 없는 코드든 **글자 하나 다르지 않은** 페이지입니다 — 응답으로는 코드가 있는지
 *   알 수 없습니다. 누구인지는 앱이 로그인한 뒤 요청을 보낼 때 서버가 가립니다.
 *
 * 스크립트는 하나 — 해시로만
 *   무엇을 할지(기종 · 앱 안 브라우저 · 어디로 갈지)는 User-Agent 와 설정으로 **서버가 정해**
 *   <body data-…> 에 적고, 스크립트는 그걸 읽어 실행만 합니다. 그래서 스크립트는 코드마다
 *   · 사람마다 한 글자도 안 바뀌고, CSP 는 그 한 덩이의 해시만 허락합니다(default-src 'none',
 *   스타일도 해시 하나). 스크립트가 꺼져 있어도 단추는 전부 진짜 링크라 누르면 됩니다 —
 *   "설치 페이지로 가요…" 줄만 안 보입니다(hidden 으로 나가고 스크립트가 켭니다).
 *
 * 코드가 새지 않게
 *   · 로그에 안 남습니다(logLine 은 /api 만 찍습니다).
 *   · Referrer-Policy: no-referrer — 참여 단추로 TestFlight · 플레이 · 구글 그룹에 갈 때 이 주소가
 *     따라가지 않습니다.
 *   · noindex — 검색에 안 걸립니다. 캐시는 no-store(send 기본값)에 Vary: * — 웹 앱의
 *     서비스워커도 못 담습니다(INVITE_HEADERS).
 *
 * 설치 안내는 GET /api/version 과 같은 설정(tools/app-version.js)을 부를 때마다 읽습니다.
 *   시험 기간(testing)   아이폰 TestFlight 공개 링크(join.ios) · 안드로이드 ① 구글 그룹
 *                        (join.androidGroup) ② 테스트 참여(join.android) ③ 플레이(추천인)
 *   정식 출시 뒤         아이폰 App Store · 안드로이드 플레이(추천인)
 *   필요한 링크가 안 적혀 있으면 "곧 열려요 — 코드 <코드> 를 적어 두세요".
 *   가게 주소는 설정의 urls(앱 안 업데이트 단추용 appUrl…)가 아니라 앱과 약속한 고정 주소입니다
 *   (APPSTORE_URL · PLAY_URL) — 플레이 쪽은 코드마다 추천인을 붙여야 해서입니다.
 * -------------------------------------------------------------------------- */
/* server/db.js 의 inviteCode() 와 같은 글자판이어야 합니다(헷갈리는 I · O · 0 · 1 없음).
   tools/test-invite.js 가 두 파일의 글자판이 같은지 봅니다. */
const INVITE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
const INVITE_RE = new RegExp('^[' + INVITE_ALPHABET + ']{8}$');
/* 앱의 안드로이드 패키지 · 딥링크 스킴 — 앱(app/)과 약속한 값입니다. */
const APP_PACKAGE = 'io.github.iacobuschoi.mybody';
const APP_SCHEME = 'mybody';
/* TestFlight 앱 자체의 App Store 주소 — 공개 참여 링크는 이 앱이 있어야 열립니다. */
const TESTFLIGHT_APP_URL = 'https://apps.apple.com/app/testflight/id899247664';
/* 정식 출시 뒤 받는 곳. 앱과 약속한 주소입니다(앱의 같은 안내와 한 곳으로 가게).
   App Store 는 나라를 빼 둡니다 — 애플이 받는 사람의 나라 가게로 보냅니다.
   플레이에는 코드마다 추천인(&referrer=invite%3D<코드>)을 붙입니다(playWithReferrer). */
const APPSTORE_URL = 'https://apps.apple.com/app/id6815144446';
const PLAY_URL = 'https://play.google.com/store/apps/details?id=' + APP_PACKAGE;

function escHtml(v) {
  return String(v).replace(/[&<>"']/g, c =>
    ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
}

/** 안드로이드 · 아이폰 · 그 밖(컴퓨터). 아이패드의 데스크톱 Safari 는 맥과 구분이 안 되어
 *  '그 밖' 으로 갑니다 — 그 경우 안드로이드 · 아이폰 안내가 둘 다 보여서 막히지는 않습니다. */
function platformOf(ua) {
  const s = str(ua);
  if (/Android/i.test(s)) return 'android';
  if (/iPhone|iPad|iPod/i.test(s)) return 'ios';
  return 'other';
}

/** 앱 안 브라우저인가. 'kakao' · 'other'(인스타그램 · 페이스북 · 라인 · 네이버) · ''.
 *  이런 곳에서는 앱 링크가 앱을 안 열고 자기 안에서 페이지를 엽니다. 카카오톡은 기본
 *  브라우저로 넘기는 주소가 있어서 저절로 넘기고, 나머지는 방법을 한 줄로 알려 줍니다.
 *  "Line/" 은 대소문자를 가립니다 — 다른 이름 속의 "line/" 을 잘못 잡지 않게. */
function inAppOf(ua) {
  const s = str(ua);
  if (/KAKAOTALK/i.test(s)) return 'kakao';
  if (/Instagram|FBAN|FBAV|Line\/|NAVER\(inapp/.test(s)) return 'other';
  return '';
}

/** 밖에서 보는 이 서버의 주소("https://이름.ts.net"). 못 정하면 ''.
 *
 *  og:image(미리보기 그림)와 안드로이드 fallback 은 **절대 주소**여야 합니다. fallback 은 "앱이
 *  없으면 **지금 이 페이지**로 돌아오기" 라서, 받은 사람이 실제로 연 주소 — 요청의 Host — 가
 *  제일 맞습니다. 초대 링크는 앱이 쓰는 서버 주소로 만들어지니 그 주소가 곧 Host 입니다.
 *  설정의 공개 주소(ORIGIN)를 먼저 쓰면, 그 값이 틀렸거나 옛것일 때(위 warnOriginMismatch 가
 *  말하는 일 — 실제로 있었습니다) 앱이 없는 사람이 **다른 주소**로 떨어져 설치 안내를 못 봅니다.
 *
 *  그래서 순서는
 *    · Host 가 ORIGIN 과 같은 이름 → ORIGIN(https 인지를 설정이 확실히 압니다)
 *    · Host 가 없거나 이 컴퓨터 자신(localhost · 127.0.0.1 — 주인이 직접 열었거나, 프록시가
 *      Host 를 바꿔 끼운 경우) → ORIGIN
 *    · 그 밖 → 요청대로. 터널 · 프록시의 X-Forwarded-* 는 TRUST_PROXY 를 켠 사람만 믿습니다
 *      (clientIp 와 같은 규칙 — launch.js 는 터널을 붙일 때 ORIGIN 과 함께 켭니다).
 *  Host 는 누구나 적어 보낼 수 있으니 이름 모양만 받습니다 — 페이지에 그대로 박히기 때문입니다.
 *  거짓 Host 를 보내 봐야 **자기가 받는** 페이지만 바뀝니다(no-store · Vary: * — 남에게 안 갑니다). */
const LOOPBACK_HOST = /^(?:localhost|127(?:\.\d{1,3}){3}|\[::1\]|0\.0\.0\.0)(?::\d{1,5})?$/;
function publicBase(req) {
  let origin = null;
  if (ORIGIN && ORIGIN !== '*') {
    try {
      const u = new URL(ORIGIN);
      if (u.protocol === 'https:' || u.protocol === 'http:') origin = u;
    } catch (e) {}
  }
  const first = v => str(v).split(',')[0].trim();
  const host = ((TRUST_PROXY && first(req.headers['x-forwarded-host'])) || first(req.headers.host)).toLowerCase();
  const named = /^(?:[a-z0-9-]{1,63}(?:\.[a-z0-9-]{1,63})*|\[[0-9a-f:.]{2,45}\])(?::\d{1,5})?$/.test(host);
  if (origin && (!named || LOOPBACK_HOST.test(host) || host === origin.host)) return origin.origin;
  if (!named) return '';
  const proto = (TRUST_PROXY && first(req.headers['x-forwarded-proto']).toLowerCase() === 'https') ||
                req.socket.encrypted ? 'https' : 'http';
  return proto + '://' + host;
}

/** 미리보기 그림 — 지금 내보내는 폴더에 실제로 있는 앱 아이콘. 없으면 ''. */
function inviteIcon(sizes) {
  for (const f of sizes) {
    try { if (fs.statSync(path.join(STATIC_ROOT, 'assets', f)).isFile()) return '/assets/' + f; } catch (e) {}
  }
  return '';
}

/* 페이지 모양. 앱과 같은 색(prototype/css/base.css 의 토큰)이고, 밝게 · 어둡게는 기기를 따릅니다.
   글자를 1.3배로 키운 360px 폰에서도 코드 여덟 글자가 한 줄에 들어가게 코드 글자는 화면
   폭에 맞춰 줄입니다(clamp). **여기를 고치면 CSP 해시가 저절로 따라갑니다** — 페이지에 박는
   <style> 과 해시가 같은 문자열에서 나옵니다. */
const INVITE_CSS = [
  ':root{--bg:#f6f7f9;--surface:#fff;--border:#e2e5ea;--text:#16181d;--muted:#5b6270;',
  '--accent:#4f46e5;--accent-ink:#fff;--accent-sub:#eef0ff;--warn:#b45309;--warn-bg:#fdf3e3;color-scheme:light dark}',
  '@media (prefers-color-scheme:dark){:root{--bg:#0e1014;--surface:#171a20;--border:#2a2f39;--text:#e9ecf1;',
  '--muted:#a3adbb;--accent:#7c7cf7;--accent-ink:#0e1014;--accent-sub:#232447;--warn:#fbbf24;--warn-bg:#2c2110}}',
  /* text-size-adjust 는 일부러 안 둡니다 — 폰의 "글자 크게" 를 막을 수 있습니다. */
  '*{box-sizing:border-box}',
  'body{margin:0;background:var(--bg);color:var(--text);padding:28px 16px 48px;',
  'font:16px/1.6 -apple-system,BlinkMacSystemFont,"Apple SD Gothic Neo","Noto Sans KR","Segoe UI",Roboto,sans-serif;',
  'word-break:keep-all;overflow-wrap:anywhere}',
  'main{max-width:440px;margin:0 auto}',
  '.top{text-align:center;margin:0 0 14px}',
  '.icon{display:block;width:56px;height:56px;border-radius:14px;margin:0 auto 8px}',
  'h1{font-size:22px;line-height:1.3;margin:0}',
  'h2{font-size:18px;line-height:1.3;margin:0 0 10px}',
  'h3{font-size:15px;margin:16px 0 4px;color:var(--muted)}',
  '.card{background:var(--surface);border:1px solid var(--border);border-radius:14px;padding:18px 16px;margin:12px 0}',
  '.card--em{border:2px solid var(--accent)}',
  '.flag{background:var(--warn-bg);color:var(--warn);border-radius:12px;padding:12px 14px;margin:0 0 12px;',
  'font-weight:700;text-align:center}',
  '.label{margin:0;text-align:center;color:var(--muted);font-size:14px}',
  '.code{margin:2px 0 10px;text-align:center;font-weight:700;font-size:clamp(24px,8.5vw,38px);line-height:1.25;',
  'font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,"Roboto Mono",monospace;',
  'letter-spacing:.16em;padding-left:.16em;-webkit-user-select:all;user-select:all}',
  '.btn{display:block;width:100%;margin:8px 0 0;padding:14px 12px;border-radius:12px;text-align:center;',
  'text-decoration:none;font-weight:700;font-size:17px;line-height:1.35;',
  'background:var(--accent-sub);color:var(--accent);border:1px solid transparent}',
  '.btn--primary{background:var(--accent);color:var(--accent-ink)}',
  '.hint{margin:10px 0 0;color:var(--muted);font-size:14px;text-align:center}',
  '.soon{margin:4px 0 0}',
  /* 스크립트가 켜는 줄("설치 페이지로 가요…")은 hidden 으로 나갑니다 — .hint 의 모양이 이기지 않게. */
  '[hidden]{display:none!important}',
  'a{color:var(--accent)}'
].join('');

/* 페이지의 스크립트 — 무엇을 할지는 서버가 <body data-…> 에 적어 두고(serveInvite), 이것은
 * 읽어서 실행만 합니다. 그래서 코드 · 기종 · 설정이 달라도 이 글자들은 그대로이고, CSP 는 이
 * 한 덩이의 해시만 허락합니다. 브라우저에는 아래 함수의 **소스 글자 그대로** 나갑니다
 * (INVITE_JS = 함수.toString(), 줄바꿈만 LF 로) — 여기를 고치면 해시가 저절로 따라갑니다. 서버에서는 한 번도
 * 부르지 않습니다. 옛 웹뷰도 읽게 var · function 으로만 씁니다. 페이지로 나가는 글자라
 * 설명은 여기(밖)에 둡니다.
 *
 *   data-copy     설치 단추를 누르면 담을 글("Mybody 초대 <코드> <주소>"). 담기를 기다렸다가
 *                 (최대 0.8초) 갑니다. 클립보드가 없는 브라우저 · 새 탭으로 열기(⌘ · Ctrl
 *                 누른 채)는 막지 않고 원래대로 둡니다.
 *   data-inapp    'kakao' → 기본 브라우저로 넘김(openExternal 에 지금 주소를 인코딩해 실음).
 *   data-intent   안드로이드 — 열리자마자 이 intent 로(location.replace: 앱이 없어서 fallback 으로
 *                 가도 뒤로 가기가 이 페이지로 돌아와 다시 튕기지 않게).
 *   data-later    아이폰 — 1.5초 뒤 이 설치 페이지로. 그 사이에 누르거나(pointerdown ·
 *                 touchstart · keydown · 단추) 화면이 가려졌으면(visibilityState) 안 갑니다.
 *                 여기서도 담기를 해 보지만, 사파리는 누른 순간이 아니면 거절합니다.
 *                 1.5초가 지나면 가든 안 가든 "설치 페이지로 가요…" 줄을 숨깁니다 — App Store ·
 *                 TestFlight 는 다른 앱으로 열려 이 페이지가 남는데, 돌아왔을 때 이미 지난 예고가
 *                 떠 있으면 거짓말이 됩니다.
 *   data-code     "한 탭에서 한 번" 을 코드마다 셉니다(sessionStorage — 못 쓰면 그냥 합니다).
 */
function inviteScript() {
  var body = document.body;
  var data = function (k) { return body.getAttribute('data-' + k) || ''; };
  var copyText = data('copy');
  var touched = false;
  var copy = function () {
    try { return copyText ? navigator.clipboard.writeText(copyText) : null; } catch (e) { return null; }
  };
  var firstTime = function (what) {
    try {
      var key = 'mybody-invite-' + what + '-' + data('code');
      if (sessionStorage.getItem(key)) return false;
      sessionStorage.setItem(key, '1');
    } catch (e) {}
    return true;
  };
  var buttons = document.querySelectorAll('a[data-install]');
  for (var i = 0; i < buttons.length; i++) {
    buttons[i].addEventListener('click', function (e) {
      var href = this.getAttribute('href');
      touched = true;
      var p = copy();
      if (!p || !href || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey || e.button) return;
      e.preventDefault();
      var went = false;
      var go = function () { if (!went) { went = true; location.href = href; } };
      p.then(go, go);
      setTimeout(go, 800);
    });
  }
  if (data('inapp') === 'kakao') {
    if (firstTime('kakao')) {
      location.replace('kakaotalk://web/openExternal?url=' + encodeURIComponent(location.href));
    }
    return;
  }
  var intent = data('intent');
  if (intent) {
    if (firstTime('intent')) location.replace(intent);
    return;
  }
  var later = data('later');
  var line = document.getElementById('later');
  if (!later || !line || !firstTime('later')) return;
  line.hidden = false;
  ['pointerdown', 'touchstart', 'keydown'].forEach(function (t) {
    document.addEventListener(t, function () { touched = true; }, true);
  });
  setTimeout(function () {
    line.hidden = true;
    if (touched || document.visibilityState !== 'visible') return;
    var p = copy();
    if (p) p.then(null, function () {});
    location.href = later;
  }, 1500);
}
/* 줄바꿈은 LF 로 맞춥니다. 윈도우에서 git 이 이 파일을 CRLF 로 꺼내면(core.autocrlf — Git for
   Windows 의 기본값이고, 서버를 띄우는 노트북이 윈도우입니다) toString() 에 \r\n 이 실립니다.
   그런데 브라우저는 HTML 을 읽으면서 \r\n 을 \n 으로 바꾼 **뒤에** 스크립트의 해시를 잽니다 —
   그대로 두면 해시가 어긋나 CSP 가 스크립트를 조용히 막고, 카카오톡 넘기기 · 안드로이드 앱
   부르기 · 아이폰 설치 페이지 · 클립보드 담기가 전부 멈춥니다(단추만 남음). 어디에도 안 적히는
   고장이라 여기서 막습니다. tools/test-invite.js [15] 가 CRLF 로 읽힌 server.js 로 봅니다. */
const INVITE_JS = ('(' + inviteScript.toString() + ')();').replace(/\r\n?/g, '\n');
const cspHash = s => "'sha256-" + crypto.createHash('sha256').update(s, 'utf8').digest('base64') + "'";
const INVITE_CSP = "default-src 'none'; script-src " + cspHash(INVITE_JS) + '; style-src ' + cspHash(INVITE_CSS) +
  "; img-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'";
/* Vary: * — 웹 앱(prototype/sw.js)의 서비스워커가 이 페이지를 **캐시에 담지 못하게.**
   이 서버의 웹 앱을 한 번이라도 연 브라우저에는 서비스워커가 / 전체를 쥐고 있고, 받은 200 을
   Cache Storage 에 담습니다(no-store 를 안 봅니다). 그리고 찾을 때 물음표 뒤를 뺍니다
   (ignoreSearch). 실제로 크롬에서 재 보니 /i/<코드> 를 한 번 연 뒤 안드로이드 fallback
   (/i/<코드>?noapp=1)이 캐시의 **보통 페이지**로 나와서 "앱이 없어서 설치 안내로 왔어요" 가
   안 떴습니다 — 참여 링크를 바꿔도 옛 안내가 남습니다. Cache.put 은 Vary: * 인 응답을
   거절하고(표준) sw.js 는 그 거절을 삼키므로, sw.js 를 고치지 않아도 이 페이지는 늘
   네트워크에서 옵니다. HTTP 캐시에는 원래 no-store 라 달라지는 것이 없습니다. */
const INVITE_HEADERS = {
  'Content-Type': 'text/html; charset=utf-8',
  'Content-Security-Policy': INVITE_CSP,
  'Referrer-Policy': 'no-referrer',
  'X-Frame-Options': 'DENY',
  'X-Robots-Tag': 'noindex',
  'Vary': '*'
};

/** 머리(<head>)와 몸통을 이어 한 페이지로. head 는 이미 이스케이프된 조각입니다.
 *  viewport-fit=cover 는 두지 않습니다 — 노치 · 홈 막대 여백(safe-area)을 따로 안 주므로,
 *  기본값이 글자를 가려지지 않는 곳에 둡니다.
 *  bodyAttrs(이미 이스케이프된 data-… 조각)를 주면 스크립트(INVITE_JS)를 끝에 붙입니다 —
 *  404 에는 할 일이 없어서 안 붙입니다(머리글 · CSP 는 같습니다). */
function invitePage(head, body, bodyAttrs) {
  const icon = inviteIcon(['icon-192.png', 'apple-touch-icon.png']);
  const fav = inviteIcon(['favicon-32.png']);
  const withJs = typeof bodyAttrs === 'string';
  return '<!doctype html>\n<html lang="ko">\n<head>\n<meta charset="utf-8">\n' +
    '<meta name="viewport" content="width=device-width, initial-scale=1">\n' +
    '<meta name="robots" content="noindex">\n<meta name="referrer" content="no-referrer">\n' +
    '<meta name="color-scheme" content="light dark">\n<meta name="theme-color" content="#4f46e5">\n' +
    (fav ? '<link rel="icon" type="image/png" href="' + escHtml(fav) + '">\n' : '') +
    head + '<style>' + INVITE_CSS + '</style>\n</head>\n<body' + (withJs ? bodyAttrs : '') + '>\n<main>\n' +
    '<header class="top">' + (icon ? '<img class="icon" src="' + escHtml(icon) + '" alt="" width="56" height="56">' : '') +
    '<h1>Mybody 친구 초대</h1></header>\n' + body + '</main>\n' +
    (withJs ? '<script>' + INVITE_JS + '</script>\n' : '') + '</body>\n</html>\n';
}

/** 단추 하나. 밖으로 나가는 링크라 rel="noreferrer" — 이 주소(코드)가 따라가지 않게. */
function inviteBtn(href, label, primary) {
  return '<a class="btn' + (primary ? ' btn--primary' : '') + '" href="' + escHtml(href) +
         '" rel="noreferrer">' + escHtml(label) + '</a>\n';
}
/** 설치 단추 — 누르면 스크립트가 초대 글을 클립보드에 담고 갑니다(data-install). 스크립트가
 *  없으면 그냥 링크입니다. */
function installBtn(href, label) {
  return '<a class="btn" href="' + escHtml(href) + '" rel="noreferrer" data-install>' + escHtml(label) + '</a>\n';
}
/** 받을 곳이 아직 없을 때 — 코드를 적어 두라고 코드를 그 자리에 한 번 더 적습니다. */
function soonLine(who, code) {
  return '<p class="soon">' + who + ' 곧 열려요 — 코드 ' + escHtml(code) + ' 를 적어 두세요</p>\n';
}
/** 플레이 가게 주소 + 추천인 invite=<코드>. 앱이 첫 실행에 설치 추천인으로 읽어 초대를 잇습니다
 *  (referrer 값 전체를 한 번 인코딩: invite%3D<코드>). */
function playWithReferrer(code) {
  return PLAY_URL + '&referrer=' + encodeURIComponent('invite=' + code);
}

/** "앱이 없나요?" 의 한 기종 몫. testing 이 켜져 있으면 참여 링크, 꺼져 있으면 가게.
 *  받을 곳이 없으면 "곧 열려요" 한 줄 — 그때는 "설치한 뒤 돌아와서" 도 붙이지 않습니다(offers).
 *  가게 주소는 설정(urls)이 아니라 앱과 약속한 주소입니다(APPSTORE_URL · playWithReferrer). */
function offersInstall(os, info) {
  return !info.testing || !!(info.join || {})[os === 'android' ? 'android' : 'ios'];
}
/** 아이폰이 저절로 갈 설치 페이지. 없으면 ''(그때는 안 갑니다). */
function iosInstallTarget(info) {
  return info.testing ? ((info.join || {}).ios || '') : APPSTORE_URL;
}
function installFor(os, info, code) {
  const join = info.join || {};
  const play = playWithReferrer(code);
  if (!info.testing) {
    return os === 'android' ? installBtn(play, 'Google Play 에서 받기')
                            : installBtn(APPSTORE_URL, 'App Store 에서 받기');
  }
  if (os === 'android') {
    if (!join.android) return soonLine('안드로이드는', code);
    /* 비공개 테스트는 구글 그룹에 먼저 들어가야 참여 주소가 열립니다. 그룹이 없는 테스트면
       그 단계를 뺍니다. 그룹 · 플레이가 다른 구글 계정이면 "테스트에 참여할 수 없음" 이
       나오는데, 까닭이 어디에도 안 적혀서 한 줄 둡니다.
       마지막 단추는 참여 페이지의 "Google Play 에서 다운로드" 대신 **추천인이 붙은** 가게
       주소입니다 — 그래야 앱이 처음 열릴 때 이 초대를 압니다. */
    const last = '<p class="hint">마지막 단추로 받으면 앱을 처음 열 때 초대가 이어져요</p>\n';
    if (!join.androidGroup) {
      return installBtn(join.android, '① 테스트 참여') + installBtn(play, '② Google Play 에서 설치') + last;
    }
    return installBtn(join.androidGroup, '① 구글 그룹 가입') +
           installBtn(join.android, '② 테스트 참여') +
           installBtn(play, '③ Google Play 에서 설치') + last +
           '<p class="hint">그룹 · 플레이 모두 같은 구글 계정으로</p>\n';
  }
  if (!join.ios) return soonLine('아이폰은', code);
  return installBtn(join.ios, 'TestFlight 에서 받기') +
         '<p class="hint">TestFlight 앱이 있어야 열려요 · <a href="' + escHtml(TESTFLIGHT_APP_URL) +
         '" rel="noreferrer" data-install>TestFlight 받기</a></p>\n';
}

/** 코드 모양이 틀린 주소 — 같은 모양의 404. 받은 글자는 **다시 찍지 않습니다.** */
function inviteNotFound(res) {
  return send(res, 404, invitePage('<title>Mybody 친구 초대</title>\n',
    '<section class="card"><h2>초대 링크가 맞지 않아요</h2>' +
    '<p class="soon">코드는 영문 대문자 · 숫자 8자예요. 친구에게 링크를 다시 받아 주세요.</p></section>\n'),
    INVITE_HEADERS);
}

function serveInvite(req, res, url) {
  if (req.method !== 'GET' && req.method !== 'HEAD') {
    return send(res, 405, { ok: false, reason: '그런 방법으로는 열 수 없습니다' }, { Allow: 'GET, HEAD' });
  }
  const m = /^\/i\/([A-Za-z0-9]{8})\/?$/.exec(url.pathname);
  const code = m ? m[1].toUpperCase() : '';
  if (!INVITE_RE.test(code)) return inviteNotFound(res);
  const noapp = url.searchParams.get('noapp') === '1';
  /* ?stay=1 — "여기 있기". 저절로 어디로 가지 않습니다. */
  const stay = url.searchParams.get('stay') === '1';
  /* 소문자 · 끝의 / 는 대문자 주소로 돌려보냅니다 — 앱에 넘길 코드와 미리보기가 한 모양이 되게.
     302 로 둡니다: 브라우저가 영원히 기억하는 301 은 규칙을 바꿀 때 발목을 잡습니다.
     다른 쿼리는 떼어 냅니다(돌려보낼 곳에 받은 글자를 싣지 않습니다) — 우리가 아는 noapp ·
     stay 만 정해진 모양으로 다시 붙입니다. */
  if (url.pathname !== '/i/' + code) {
    const q = [noapp ? 'noapp=1' : '', stay ? 'stay=1' : ''].filter(Boolean).join('&');
    return send(res, 302, '', { Location: '/i/' + code + (q ? '?' + q : ''),
                                'Content-Type': 'text/plain; charset=utf-8' });
  }

  let saved = {};
  try { saved = require('../tools/config.js').readFileStrict(); } catch (e) { saved = {}; }
  const info = APPVER.versionInfo(saved);
  const ua = req.headers['user-agent'];
  const os = platformOf(ua);
  const inapp = inAppOf(ua);
  const base = publicBase(req);
  const self = base ? base + '/i/' + code : '';

  /* 앱 열기 — 안드로이드는 intent:(앱이 없으면 fallback), 아이폰은 스킴 그대로.
     fallback 은 시험 기간이면 이 페이지 + ?noapp=1(참여 단계를 보여 줘야 해서), 정식 출시
     뒤에는 추천인 붙은 플레이 가게(한 번에 설치로). 시험 기간인데 주소를 못 정했으면 fallback 을
     빼서 크롬이 가게로 보내게 둡니다. */
  let open = '';
  if (os === 'android') {
    const fallback = info.testing ? (self ? self + '?noapp=1' : '') : playWithReferrer(code);
    open = 'intent://invite/' + code + '#Intent;scheme=' + APP_SCHEME + ';package=' + APP_PACKAGE +
           (fallback ? ';S.browser_fallback_url=' + encodeURIComponent(fallback) : '') + ';end';
  } else if (os === 'ios') {
    open = APP_SCHEME + '://invite/' + code;
  }

  /* 스크립트가 할 일(위 inviteScript). 앱 안 브라우저에서는 저절로 앱을 부르거나 가게로 가지
     않습니다 — 카카오톡만 기본 브라우저로 넘기고, 나머지는 방법을 한 줄로. */
  const autoIntent = os === 'android' && !inapp && !noapp && !stay ? open : '';
  const later = os === 'ios' && !inapp && !stay ? iosInstallTarget(info) : '';
  const dataAttr = (k, v) => v ? ' data-' + k + '="' + escHtml(v) + '"' : '';
  const bodyAttrs = dataAttr('code', code) +
    dataAttr('copy', 'Mybody 초대 ' + code + (self ? ' ' + self : '')) +
    dataAttr('inapp', inapp === 'kakao' ? 'kakao' : '') +
    dataAttr('intent', autoIntent) + dataAttr('later', later);

  const desc = '링크를 누르면 바로 친구가 돼요 · 코드 ' + code;
  const image = inviteIcon(['icon-512.png', 'icon-192.png', 'apple-touch-icon.png']);
  const head = '<title>Mybody 친구 초대</title>\n' +
    '<meta name="description" content="' + escHtml(desc) + '">\n' +
    '<meta property="og:type" content="website">\n<meta property="og:site_name" content="Mybody">\n' +
    '<meta property="og:title" content="Mybody 친구 초대">\n' +
    '<meta property="og:description" content="' + escHtml(desc) + '">\n' +
    (self ? '<meta property="og:url" content="' + escHtml(self) + '">\n' : '') +
    (base && image ? '<meta property="og:image" content="' + escHtml(base + image) + '">\n' : '') +
    '<meta name="twitter:card" content="summary">\n';

  /* 앱이 없어서 돌아온 경우(noapp)는 "앱에서 열기" 를 설치 안내 끝으로 내립니다 — 설치한 뒤
     누르는 단추입니다. 그 밖에는 코드 바로 밑의 큰 단추입니다. 아이폰은 그 밑에 "설치
     페이지로 가요… 여기 있기" 줄(스크립트가 켤 때만 보임). */
  const auto = '<p class="hint">앱을 연 뒤에는 바로 친구가 돼요 (로그인 필요)</p>\n';
  const codeCard = '<section class="card"><p class="label">초대 코드</p>' +
    '<p class="code">' + escHtml(code) + '</p>\n' +
    (open && !noapp ? inviteBtn(open, '앱에서 열기', true) : '') +
    (later ? '<p class="hint" id="later" hidden>앱이 없으면 설치 페이지로 가요… <a href="/i/' + escHtml(code) +
             '?stay=1">여기 있기</a></p>\n' : '') + auto +
    (os === 'other' ? '<p class="hint">폰에서 이 링크를 열면 앱으로 바로 가요</p>\n' : '') + '</section>\n';
  let install;
  if (os === 'other') {
    install = '<h3>안드로이드</h3>\n' + installFor('android', info, code) +
              '<h3>아이폰</h3>\n' + installFor('ios', info, code);
  } else {
    const can = offersInstall(os, info);
    install = installFor(os, info, code) + (noapp
      ? (can ? '<p class="hint">설치했으면 이 단추로</p>\n' + inviteBtn(open, '앱에서 열기') : '')
      : (can ? '<p class="hint">설치한 뒤 돌아와서 「앱에서 열기」</p>\n' : ''));
  }
  const body = (noapp ? '<p class="flag">앱이 없어서 설치 안내로 왔어요</p>\n' : '') +
    (inapp === 'other' ? '<p class="flag">여기서는 앱이 바로 안 열려요 · 오른쪽 위 ⋯ → 다른 브라우저로 열기</p>\n' : '') +
    codeCard +
    '<section class="card' + (noapp ? ' card--em' : '') + '"><h2>앱이 없나요?</h2>\n' + install + '</section>\n';
  return send(res, 200, invitePage(head, body, bodyAttrs), INVITE_HEADERS);
}

/* --- 앱 링크 파일 (GET /.well-known/assetlinks.json · /.well-known/apple-app-site-association) ---
 *
 * 왜 있나
 *   위 초대 링크를 누르면 브라우저가 먼저 열리고, 거기서 "앱에서 열기" 를 한 번 더 눌러야
 *   했습니다. 주인의 말은 "링크만 누르면 바로 친추". 안드로이드 App Links · 아이폰 Universal
 *   Links 가 그 길입니다 — 폰이 https://<이 서버>/i/… 를 **앱의 것**으로 알고, 누르는 순간
 *   브라우저 없이 앱을 엽니다. 폰은(아이폰은 애플의 CDN 을 거쳐) 앱을 깔 때 이 서버에 "이 앱이
 *   네 것이 맞나" 를 묻고, 그 대답이 이 두 파일입니다. 대답이 틀리거나 없으면 **아무 말 없이**
 *   예전처럼 브라우저가 열립니다 — 그래서 tools/test-invite.js 가 모양을 글자 그대로 봅니다.
 *
 * 안드로이드 (assetlinks.json)
 *   앱 패키지 + 앱에 서명한 인증서의 SHA-256 지문. 업로드 키(직접 받는 APK · 우리가 올리는 판)
 *   지문은 늘 싣고, 플레이가 다시 서명하는 "앱 서명 키" 는 설정 androidCertSha256 으로
 *   더합니다(노트북이 플레이 콘솔에서 읽어 적습니다 — 이게 없으면 플레이로 깐 폰에서만
 *   링크가 브라우저로 열립니다). 지문은 콜론으로 끊긴 대문자 32덩이여야 합니다 — 소문자 ·
 *   공백이 섞이면 구글이 조용히 무시해서, 여기서 맞추고 모양이 아닌 것은 빼고 한 번 말합니다.
 *   (예전에는 웹 앱을 플레이에 감싸 올리던 TWA 용으로 TWA_PACKAGE · TWA_FINGERPRINT 를
 *   적어야만 나갔습니다. 같은 패키지 이름의 진짜 앱이 나와서 그 길은 없앴습니다.)
 *
 * 아이폰 (apple-app-site-association)
 *   "<팀 ID>.<번들 ID> 가 /i/* 를 연다". 애플은 확장자 없는 이 이름을 **리디렉션 없이 200 ·
 *   application/json** 으로만 받습니다. 팀 ID 는 설정 appleTeamId(없거나 모양이 틀리면 기본값).
 *   앱 쪽에는 associated-domains 권한(applinks:<이 서버>)이 있어야 합니다 — CI 가 넣습니다.
 *
 * 공통
 *   로그인 없음 · 정적 파일보다 먼저(serveStatic 도 이 이름은 여기로 넘깁니다). 웹 앱의
 *   서비스워커와는 상관없습니다 — 폰 · 애플 CDN 은 브라우저 밖에서 받아 갑니다. 캐시는 한 시간:
 *   지문을 더한 뒤 확인이 오래 헛돌지 않게. 설정은 부를 때마다 읽습니다(환경변수
 *   ANDROID_CERT_SHA256 · APPLE_TEAM_ID 가 먼저 — tools/config.js 와 같은 순서). 설정 파일이
 *   망가졌으면 기본값만으로 답합니다 — 업로드 키 · 기본 팀은 그래도 맞습니다.
 * -------------------------------------------------------------------------- */
/* 업로드 키 — 앱의 릴리스 서명 열쇠. 공개해도 되는 값입니다(모든 APK 안에 들어 있습니다). */
const ANDROID_UPLOAD_CERT = '06:D9:45:A3:83:79:71:CE:A7:AF:0C:03:BC:EF:F3:13:96:4F:57:7B:C8:C1:6A:41:03:3A:A2:60:17:83:DE:11';
/* 애플 개발자 팀 ID — 이것도 공개되는 값입니다(앱 서명 · 이 파일에 그대로 나갑니다). */
const APPLE_TEAM_DEFAULT = 'JT4YLVNKDZ';
const WELL_KNOWN_HEADERS = { 'Content-Type': 'application/json', 'Cache-Control': 'public, max-age=3600' };

/* 모양이 틀린 값은 한 번만 말합니다 — 폰 · 애플 CDN 이 자주 받아 가서, 매번 찍으면 로그가 묻힙니다. */
const wellKnownWarned = new Set();
function wellKnownWarn(key, msg) {
  if (wellKnownWarned.has(key)) return;
  wellKnownWarned.add(key);
  console.log('  ⚠ ' + msg);
}

/** 지문 하나 → "AB:CD:…"(32덩이) 또는 ''. keytool 이 찍는 "SHA256: …" 줄 · 소문자 · 공백 ·
 *  콜론 없는 64자(apksigner)를 다 받습니다. */
function normFingerprint(v) {
  if (typeof v !== 'string') return '';
  const hex = v.trim().replace(/^SHA-?256\s*:?/i, '').replace(/[\s:]/g, '').toUpperCase();
  return /^[0-9A-F]{64}$/.test(hex) ? hex.match(/../g).join(':') : '';
}
/** 업로드 키 + 설정의 지문(배열 · 쉼표로 이은 글자). 겹치면 한 번. */
function androidCerts(extra) {
  const list = Array.isArray(extra) ? extra : typeof extra === 'string' ? extra.split(/[,;\n]+/) : [];
  const out = [ANDROID_UPLOAD_CERT];
  list.forEach(x => {
    if (typeof x === 'string' && !x.trim()) return;
    const f = normFingerprint(x);
    if (!f) {
      return wellKnownWarn('cert:' + String(x), 'androidCertSha256 에 SHA-256 지문 모양이 아닌 값이 있어 뺐습니다: ' +
                           JSON.stringify(x).slice(0, 120));
    }
    if (out.indexOf(f) < 0) out.push(f);
  });
  return out;
}
/** 팀 ID — 영문 대문자 · 숫자 10자. 아니면 기본값. */
function appleTeam(v) {
  const t = typeof v === 'string' ? v.trim().toUpperCase() : '';
  if (/^[A-Z0-9]{10}$/.test(t)) return t;
  if (v !== undefined && v !== null && v !== '') {
    wellKnownWarn('team:' + String(v), 'appleTeamId 가 팀 ID 모양(영문 · 숫자 10자)이 아니라 기본값을 씁니다: ' +
                  JSON.stringify(v).slice(0, 60));
  }
  return APPLE_TEAM_DEFAULT;
}
function wellKnownConfig() {
  let saved = {};
  try { saved = require('../tools/config.js').readFileStrict(); } catch (e) { saved = {}; }
  const env = k => (process.env[k] || '').trim();
  return { certs: env('ANDROID_CERT_SHA256') || saved.androidCertSha256,
           team: env('APPLE_TEAM_ID') || saved.appleTeamId };
}
const WELL_KNOWN = {
  '/.well-known/assetlinks.json': c => JSON.stringify([{
    relation: ['delegate_permission/common.handle_all_urls'],
    target: { namespace: 'android_app', package_name: APP_PACKAGE, sha256_cert_fingerprints: androidCerts(c.certs) }
  }]),
  /* 번들 ID 는 안드로이드 패키지와 같은 이름입니다. comment 는 애플이 읽지 않는 메모 칸입니다. */
  '/.well-known/apple-app-site-association': c => JSON.stringify({
    applinks: { details: [{ appIDs: [appleTeam(c.team) + '.' + APP_PACKAGE],
                            components: [{ '/': '/i/*', comment: 'friend invite' }] }] }
  })
};

function serveWellKnown(req, res, name) {
  if (req.method !== 'GET' && req.method !== 'HEAD') {
    return send(res, 405, { ok: false, reason: '그런 방법으로는 열 수 없습니다' }, { Allow: 'GET, HEAD' });
  }
  const body = WELL_KNOWN[name](wellKnownConfig());
  return send(res, 200, body,
              Object.assign({ 'Content-Length': String(Buffer.byteLength(body)) }, WELL_KNOWN_HEADERS));
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

/* 다른 계정의 기록을 거절한 것(409)은 한 줄 남깁니다 — 계정이 섞이려던 흔적이라 운영자가 봐야 합니다.
   계정 id 는 안 적고, 앱 판(X-Mybody-App)만 적습니다. */
function ownerConflict(req, where) {
  if (!LOG) return;
  console.log('  ⚠ 다른 계정의 기록을 거절했습니다 (' + where + ', 앱 ' +
              String(req.headers['x-mybody-app'] || '판 표시 없음').slice(0, 20) + ')');
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
    if (url.pathname === '/i' || url.pathname.startsWith('/i/')) return serveInvite(req, res, url);
    /* 앱 링크 파일 — 정적 파일(내보내는 폴더)이 가로채지 못하게 먼저. */
    if (Object.hasOwn(WELL_KNOWN, url.pathname)) return serveWellKnown(req, res, url.pathname);
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

  /* 만료된 로그인을 치웁니다 — 뜰 때 한 번, 그 뒤로 하루 한 번.
     세션은 쓰일 때만 지워졌어서, 앱을 지운 폰의 세션과 거기 묶인 앱 알림 기기 행이
     90일이 지나도 끝없이 남았습니다(처리방침의 보관 기간과 어긋남). 기기 행은 세션을
     지우면 cascade 로 같이 지워집니다. unref — 이 타이머 때문에 서버가 안 꺼지면 안 됩니다. */
  /* 보관 기간(1년)이 지난 의견과 붙인 화면도 같은 때 지웁니다 — 처리방침에 적은
     "1년" 을 지키는 곳이 여기입니다. 서버를 몇 달 안 껐다 켜도 하루 한 번은 돕니다. */
  const pruneDaily = () => {
    try { api.pruneExpiredSessions(); } catch (e) { console.error('만료된 로그인 정리 실패:', e.message); }
    try { api.pruneOldFeedback(); } catch (e) { console.error('오래된 의견 정리 실패:', e.message); }
  };
  pruneDaily();
  setInterval(pruneDaily, 24 * 3600 * 1000).unref();

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
    /* 앱 알림이 켜졌는지는 뜰 때 한 번 말합니다. 파일을 놓고도 다시 안 띄우면
       꺼진 채로 돌고, 그걸 알 수 있는 곳이 여기뿐입니다. */
    console.log('  앱 알림(FCM) ' + FCMLIB.describe(FCM_STATE));
    for (const w of (FCM_STATE.warnings || [])) console.log('  ⚠ 앱 알림(FCM): ' + w);
    /* 의견 알림도 뜰 때 한 번 말합니다. 아이디를 잘못 적었거나 알림 길이 꺼져 있으면
       켜 둔 줄 아는데 안 오는 상태가 됩니다. 아이디 자체는 찍지 않습니다. */
    if (FEEDBACK_NOTIFY) {
      const why = !(VAPID || FCM) ? '⚠ 알림 길(앱 알림 · 웹 푸시)이 꺼져 있어 못 보냅니다'
        : (api.userIdByHandle(FEEDBACK_NOTIFY) ? '켜짐 — 새 의견이 오면 설정한 계정의 폰으로 (' +
             (FEEDBACK_NOTIFY_GAP_MS >= 60000 ? Math.round(FEEDBACK_NOTIFY_GAP_MS / 60000) + '분'
               : (FEEDBACK_NOTIFY_GAP_MS / 1000) + '초') + '에 한 번까지)'
           : '⚠ 설정(feedbackNotify)에 적은 아이디의 계정이 없습니다');
      console.log('  의견 알림 ' + why);
      /* 의견함은 알림 길과 상관없이 열립니다(읽는 것은 HTTP). 그 계정이 아직 없으면, 그 아이디로
         **먼저 가입한 사람**이 의견함을 봅니다 — 조용히 넘기지 않습니다(operatorId 주석).
         누구나 가입할 수 있는 서버(OPEN_SIGNUP)만의 일이 아닙니다: 가입 코드는 주인이 시험하는
         사람들에게 나눠 주는 것이라, 코드를 받은 사람이면 그 아이디를 먼저 가져갈 수 있습니다.
         위의 "의견 알림" 줄은 알림 길이 꺼져 있으면 계정 얘기를 안 하므로 여기서 따로 말합니다. */
      if (api.userIdByHandle(FEEDBACK_NOTIFY)) {
        console.log('  의견함   켜짐 — 설정한 계정으로 로그인한 앱의 설정 화면에');
      } else {
        console.log(OPEN_SIGNUP
          ? '  ⚠ 의견함: 누구나 가입할 수 있는데 설정(feedbackNotify)에 적은 아이디의 계정이 아직 없습니다.'
          : '  ⚠ 의견함: 설정(feedbackNotify)에 적은 아이디의 계정이 아직 없습니다 (가입 코드를 아는 사람은 그 아이디로 가입할 수 있습니다).');
        console.log('    그 아이디로 먼저 가입한 사람이 모든 의견과 가입자 목록을 보게 됩니다 — 지금 그 아이디로 가입하거나');
        console.log('    ~/.mybody/config.json 의 feedbackNotify 를 지우고 다시 띄우세요.');
      }
    }
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
