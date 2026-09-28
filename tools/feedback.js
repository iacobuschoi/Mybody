/* =============================================================================
 * tools/feedback.js — 앱 안 「의견 보내기」 로 온 것을 노트북에서 봅니다
 *
 *   node tools/feedback.js                    안 읽은 의견 (새것부터) + 붙인 화면을 파일로
 *   node tools/feedback.js --all              읽은 것까지 전부
 *   node tools/feedback.js --since=2026-09-20 그날(한국 시각 0시)부터 — 읽은 것도 같이
 *   node tools/feedback.js --mark-read        보여 준 것을 읽음으로 표시
 *   node tools/feedback.js --no-export        화면 캡처를 파일로 꺼내지 않음
 *
 * 왜 있나
 *   의견은 서버의 DB(feedback · feedback_images)에 쌓입니다. 이 도구는 reset-password.js
 *   처럼 **서버 컴퓨터 앞에 앉은 사람**이 DB 를 직접 열어 봅니다. 서버를 끄지 않아도 됩니다(WAL).
 *   폰에서 보는 길은 따로 있습니다 — 운영자(설정의 feedbackNotify 계정)의 앱 설정 「의견함」
 *   (server.js handleFeedbackInbox). 그 길은 운영자 한 계정에만 열려서, 그 계정의 비밀번호가
 *   새면 모든 의견과 캡처(몸 숫자가 찍혀 있을 수 있음)가 같이 샙니다. 운영자 계정의 비밀번호는
 *   다른 곳과 다르게 두세요. 이 도구의 읽음 표시 · 번호는 의견함과 같은 표를 씁니다.
 *   컴퓨터 브라우저: <서버>/inbox — 같은 의견함을 운영자 계정으로 로그인해 봅니다(server/inbox-page.js).
 *
 * DB 는 서버와 같은 규칙으로 찾습니다
 *   환경변수 DB → ~/.mybody/config.json 의 db → server/mybody.db
 *   (server.js 가 설정의 db 를 DB 로 옮겨 쓰는 것과 같은 순서 — tools/config.js).
 *
 * 화면 캡처는 기본으로 꺼냅니다
 *   글 없이 캡처만 보내는 게 이 기능의 제일 흔한 쓰임새라, 목록만 보여 주고 사진은
 *   따로 꺼내라고 하면 한 번 더 쳐야 합니다. ~/.mybody/feedback/<번호>-<n>.png|jpg 로
 *   꺼내고, 이미 같은 크기의 파일이 있으면 다시 쓰지 않습니다. 폴더는 700 · 파일은
 *   600 입니다 — 캡처에 몸 숫자가 찍혀 있을 수 있습니다. 필요 없으면 --no-export
 *   (--export 는 기본이라 붙여도 같습니다).
 *
 * 누가 보냈는지는 안 찍습니다
 *   아이디 · 표시 이름 · 내부 id 대신 **가명 6자**(sha256(내부 id) 앞 6자)만 찍습니다.
 *   같은 사람이 보낸 것끼리 묶어 볼 수는 있고, 그게 누구인지는 이 출력만으로는 모릅니다.
 *   이 터미널을 화면 공유하거나 출력을 이슈에 붙여도 사람이 드러나지 않게.
 *   로그인 없이 보낸 것은 「익명」 입니다.
 *
 * 글은 그대로 찍지 않습니다
 *   로그인 없이도 보낼 수 있는 글이 주인의 터미널에 찍힙니다. ESC 같은 제어 문자는
 *   터미널을 조작할 수 있어서 빼고 찍습니다(서버도 저장할 때 한 번 뺍니다).
 *
 * 읽음 표시(--mark-read)는 **이번에 목록에 나온 것만** 표시합니다. 보여 준 적 없는
 * 의견이 "읽음" 이 되는 일은 없습니다. 이 도구는 지우지 않습니다 — 의견은 1년이 지나거나
 * 보낸 사람이 탈퇴하면 서버가 지우고(처리방침과 같은 규칙), 운영자가 앱의 「의견함」에서
 * 직접 지울 수도 있습니다.
 *
 * 꺼내 둔 캡처도 그 규칙을 따릅니다
 *   서버가 DB 에서 지운 의견(탈퇴 · 1년 · 의견함에서 지움)의 캡처가 ~/.mybody/feedback 에 남아 있으면
 *   처리방침의 "탈퇴하면 함께 지워집니다 · 1년 뒤 지웁니다" 가 이 노트북에서만 거짓이
 *   됩니다. 그래서 돌릴 때마다(--no-export 여도) **DB 에 더는 없는 번호**의 파일을
 *   지웁니다. 번호는 다시 쓰이지 않아서(db.js AUTOINCREMENT) 헷갈릴 일이 없고, 남아
 *   있는 의견의 파일은 DB 에서 언제든 다시 꺼낼 수 있는 사본이라 지워도 잃는 것이
 *   없습니다. 이 폴더에 손으로 둔 다른 이름의 파일은 건드리지 않습니다.
 * ========================================================================== */
'use strict';
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const CONFIG = require('./config.js');
const FEEDBACK = require(path.join(__dirname, '..', 'server', 'feedback.js'));

const KNOWN = { all: false, since: true, 'mark-read': false, 'no-export': false, export: false, help: false };

function die(lines) {
  console.error('');
  [].concat(lines).forEach(l => console.error(l));
  console.error('');
  process.exit(1);
}

function usage() {
  console.log('');
  console.log('  node tools/feedback.js                    안 읽은 의견 + 붙인 화면을 파일로');
  console.log('  node tools/feedback.js --all              읽은 것까지 전부');
  console.log('  node tools/feedback.js --since=2026-09-20 그날부터 (읽은 것도 같이)');
  console.log('  node tools/feedback.js --mark-read        보여 준 것을 읽음으로');
  console.log('  node tools/feedback.js --no-export        화면 캡처를 파일로 안 꺼냄');
  console.log('');
}

/* 모르는 깃발은 거절합니다 — --mark-raed 를 조용히 무시하면 "읽음 표시했다" 고 믿습니다. */
function parseFlags(av) {
  const out = {};
  for (const a of av) {
    const m = /^--([a-z][a-z-]*)(?:=([\s\S]*))?$/.exec(a);
    if (!m || !Object.prototype.hasOwnProperty.call(KNOWN, m[1])) {
      die(['모르는 인자입니다: ' + a, '', '  쓰는 법: node tools/feedback.js [--all] [--since=YYYY-MM-DD] [--mark-read] [--no-export]']);
    }
    if (m[1] === 'help') { usage(); process.exit(0); }
    if (KNOWN[m[1]] && (m[2] === undefined || m[2] === '')) die(['--' + m[1] + ' 에 값이 없습니다. 예: --since=2026-09-20']);
    if (!KNOWN[m[1]] && m[2] !== undefined) die(['--' + m[1] + ' 에는 값을 붙이지 않습니다.']);
    out[m[1]] = KNOWN[m[1]] ? m[2] : true;
  }
  return out;
}

/* --since 는 **한국 날짜**로 받습니다 — 목록의 시각이 전부 한국 시각이라, 같은
   날짜를 UTC 로 읽으면 그날 아침 9시 전에 온 의견이 빠집니다. */
function sinceIso(v) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(v)) die(['--since 는 2026-09-20 처럼 YYYY-MM-DD 로 적어 주세요: ' + v]);
  const t = Date.parse(v + 'T00:00:00+09:00');
  if (!Number.isFinite(t) || new Date(t + 9 * 3600e3).toISOString().slice(0, 10) !== v) {
    die(['없는 날짜입니다: --since=' + v]);
  }
  return new Date(t).toISOString();
}

function kst(iso) {
  const t = Date.parse(iso);
  if (!Number.isFinite(t)) return String(iso || '?');
  return new Date(t + 9 * 3600e3).toISOString().slice(0, 16).replace('T', ' ') + ' KST';
}

/* 찍기 직전에 한 번 더 — 서버가 거르기 전의 행이나 손으로 넣은 행이 있을 수 있습니다. */
function safe(s) { return FEEDBACK.cleanText(s == null ? '' : s); }

/** 사진을 파일로. 이미 같은 크기의 파일이 있으면 그대로 둡니다. 꺼낸 경로들을 돌려줍니다. */
function exportImages(api, item, dir) {
  const out = [];
  for (const im of api.feedbackImages(item.id)) {
    const file = path.join(dir, item.id + '-' + im.idx + '.' + FEEDBACK.extFor(im.type));
    let same = false;
    try { same = fs.statSync(file).size === im.data.length; } catch (e) {}
    if (!same) {
      fs.writeFileSync(file, im.data, { mode: 0o600 });
      try { fs.chmodSync(file, 0o600); } catch (e) {}
    }
    out.push(file);
  }
  return out;
}

/* 꺼내 둔 캡처 중 DB 에서 지워진 의견(탈퇴 · 1년 · 의견함에서 지움)의 것을 지웁니다. 지운 수를 돌려줍니다.
   도구가 만든 이름(<번호>-<n>.png|jpg|bin)만 봅니다. */
function sweepExports(api, dir) {
  let names;
  try { names = fs.readdirSync(dir); } catch (e) { return 0; }
  const alive = new Set(api.feedbackIds());
  let n = 0;
  for (const name of names) {
    const m = /^(\d+)-\d+\.(png|jpg|bin)$/.exec(name);
    if (!m || alive.has(Number(m[1]))) continue;
    try { fs.unlinkSync(path.join(dir, name)); n++; } catch (e) {}
  }
  return n;
}

function main() {
  const f = parseFlags(process.argv.slice(2));
  const { cfg } = CONFIG.load();
  const file = cfg.db ? path.resolve(cfg.db) : path.join(__dirname, '..', 'server', 'mybody.db');
  /* 없는 DB 를 열면 빈 DB 가 새로 생깁니다. 서버가 다른 파일을 쓰고 있다는 뜻일 수
     있으니 만들지 말고 말합니다. */
  if (!fs.existsSync(file)) {
    die(['데이터베이스가 없습니다: ' + file,
         '  서버를 이 컴퓨터에서 띄운 적이 있는지, 설정의 db(또는 환경변수 DB)가 맞는지 확인하세요.']);
  }
  let api;
  try {
    const { open, makeApi } = require(path.join(__dirname, '..', 'server', 'db.js'));
    api = makeApi(open(file));
  } catch (e) {
    die(['데이터베이스를 못 열었습니다: ' + file, '  ' + (e && e.message || e)]);
  }

  const since = f.since ? sinceIso(f.since) : '';
  const includeRead = !!(f.all || f.since);
  const items = api.listFeedback({ includeRead, since });
  const doExport = !f['no-export'];
  const dir = path.join(os.homedir(), '.mybody', 'feedback');

  const what = f.since ? f.since + ' 부터 온 의견' : (f.all ? '모든 의견' : '안 읽은 의견');
  console.log('');
  const swept = sweepExports(api, dir);
  if (swept) console.log('지워진 의견(탈퇴 · 1년 · 의견함에서 지움)의 캡처 ' + swept + '장을 ' + dir + ' 에서 지웠습니다.\n');
  if (!items.length) {
    console.log(what + '이 없습니다.' + (includeRead ? '' : '  (읽은 것까지: --all)'));
    console.log('');
    return 0;
  }
  if (doExport && items.some(it => it.images)) {
    fs.mkdirSync(dir, { recursive: true, mode: 0o700 });
    try { fs.chmodSync(dir, 0o700); } catch (e) {}
  }

  console.log(what + ' ' + items.length + '개  (새것부터 · ' + file + ')');
  let nImages = 0;
  for (const it of items) {
    const meta = [kst(it.createdAt), safe(it.appVersion) || '판 모름', safe(it.platform) || '기종 모름',
                  safe(it.screen) || '화면 모름', FEEDBACK.pseudonym(it.userId),
                  it.images ? '사진 ' + it.images + '장' : '사진 없음'];
    console.log('');
    console.log('#' + it.id + '  ' + meta.join(' · ') + (it.readAt ? '  (읽음)' : ''));
    const text = safe(it.text).trim();
    if (text) text.split('\n').forEach(l => console.log('    ' + l));
    else console.log('    (글 없음)');
    if (it.images) {
      if (doExport) {
        const files = exportImages(api, it, dir);
        nImages += files.length;
        files.forEach(p => console.log('    → ' + p));
      } else {
        console.log('    (사진은 --no-export 라 안 꺼냈습니다)');
      }
    }
  }
  console.log('');
  if (nImages) console.log('화면 캡처 ' + nImages + '장을 ' + dir + ' 에 꺼냈습니다.');
  if (f['mark-read']) {
    const n = api.markFeedbackRead(items.map(it => it.id));
    console.log('읽음으로 표시했습니다: ' + n + '개' + (n < items.length ? ' (나머지는 이미 읽음)' : '') + '.');
  } else if (items.some(it => !it.readAt)) {
    console.log('다 봤으면:  node tools/feedback.js --mark-read' +
                (f.since ? ' --since=' + f.since : (f.all ? ' --all' : '')));
  }
  console.log('');
  return 0;
}

process.exitCode = main();
