/* =============================================================================
 * tools/voice-feedback.js — 헬스 「누르고 말하기」 를 사람이 고친 것을 노트북에서 봅니다
 *
 *   node tools/voice-feedback.js                     아직 처리 안 한 고침 (새것부터)
 *   node tools/voice-feedback.js --all               처리한 것까지 전부
 *   node tools/voice-feedback.js --since=2026-10-20  그날(한국 시각 0시)부터 — 처리한 것도 같이
 *                                (--since 2026-10-20T03:00:00Z 처럼 ISO 시각도 · 띄어 써도 됩니다)
 *   node tools/voice-feedback.js --summary           "말 → 알아들은 것 → 고른 것" 을 많은 순서로
 *   node tools/voice-feedback.js --json              사람 대신 프로그램이 읽을 JSON 으로
 *   node tools/voice-feedback.js --mark-done=12,13   그 번호들을 처리함으로
 *
 * 왜 있나
 *   고침은 서버의 DB(voice_feedback)에 쌓입니다(POST /api/voice/feedback · server/voice-feedback.js).
 *   하나하나 보는 것보다 **모아 보는 것**이 쓸모 있습니다 — "벤치 → (못 알아들음) → bench-press
 *   ×14" 가 보이면 별칭 사전(server/voice-aliases.json)에 "벤치": "bench-press" 한 줄을 더하고,
 *   그 고침들을 --mark-done 으로 치웁니다. 사전은 서버를 다시 띄우지 않아도 바로 나갑니다.
 *   tools/feedback.js 처럼 서버 컴퓨터 앞에서 DB 를 직접 엽니다(서버를 끄지 않아도 됩니다 — WAL).
 *
 * DB 는 서버와 같은 규칙으로 찾습니다
 *   환경변수 DB → ~/.mybody/config.json 의 db → server/mybody.db (tools/feedback.js 와 같음).
 *
 * 누가 보냈는지는 안 찍습니다
 *   tools/feedback.js 와 같은 가명 6자(sha256(내부 id) 앞 6자) · 로그인 없이 보낸 것은 「익명」.
 *   --json 에도 내부 id 대신 가명(user)만 싣습니다.
 *
 * 글은 그대로 찍지 않습니다
 *   로그인 없이 보낼 수 있는 글이라, 제어 문자 · 방향 뒤집기 문자를 빼고 찍습니다
 *   (서버도 저장할 때 한 번 뺍니다 — 옛 행 · 손으로 넣은 행 때문에 한 번 더).
 *
 * 이 도구는 지우지 않습니다 — 고침은 1년이 지나거나 보낸 사람이 탈퇴하면 서버가 지웁니다.
 * ========================================================================== */
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const CONFIG = require('./config.js');
const FEEDBACK = require(path.join(__dirname, '..', 'server', 'feedback.js'));

/* true = 값을 받는 깃발. */
const KNOWN = { all: false, since: true, 'mark-done': true, summary: false, json: false, help: false };
const USAGE = '  쓰는 법: node tools/voice-feedback.js [--all] [--since=YYYY-MM-DD|ISO] [--summary] [--json] [--mark-done=1,2,3]';

function die(lines) {
  console.error('');
  [].concat(lines).forEach(l => console.error(l));
  console.error('');
  process.exit(1);
}

function usage() {
  console.log('');
  console.log('  node tools/voice-feedback.js                     처리 안 한 고침 (새것부터)');
  console.log('  node tools/voice-feedback.js --all               처리한 것까지');
  console.log('  node tools/voice-feedback.js --since=2026-10-20  그날부터 (처리한 것도 같이 · ISO 시각도 됨)');
  console.log('  node tools/voice-feedback.js --summary           말 → 알아들은 것 → 고른 것, 많은 순서');
  console.log('  node tools/voice-feedback.js --json              JSON 으로');
  console.log('  node tools/voice-feedback.js --mark-done=12,13   그 번호들을 처리함으로');
  console.log('');
}

/* 모르는 깃발은 거절합니다 — --mark-dnoe 를 조용히 무시하면 "치웠다" 고 믿습니다.
   값은 --since=X 와 --since X 둘 다 받습니다. */
function parseFlags(av) {
  const out = {};
  for (let i = 0; i < av.length; i++) {
    const a = av[i];
    const m = /^--([a-z][a-z-]*)(?:=([\s\S]*))?$/.exec(a);
    if (!m || !Object.prototype.hasOwnProperty.call(KNOWN, m[1])) die(['모르는 인자입니다: ' + a, '', USAGE]);
    if (m[1] === 'help') { usage(); process.exit(0); }
    let v = m[2];
    if (KNOWN[m[1]] && v === undefined && i + 1 < av.length && !av[i + 1].startsWith('--')) v = av[++i];
    if (KNOWN[m[1]] && (v === undefined || v === '')) die(['--' + m[1] + ' 에 값이 없습니다.', '', USAGE]);
    if (!KNOWN[m[1]] && v !== undefined) die(['--' + m[1] + ' 에는 값을 붙이지 않습니다.']);
    out[m[1]] = KNOWN[m[1]] ? v : true;
  }
  return out;
}

/* --since — 날짜만 적으면 **한국 날짜**(tools/feedback.js 와 같은 이유), 시각까지 적으면 그 시각. */
function sinceIso(v) {
  if (/^\d{4}-\d{2}-\d{2}$/.test(v)) {
    const t = Date.parse(v + 'T00:00:00+09:00');
    if (!Number.isFinite(t) || new Date(t + 9 * 3600e3).toISOString().slice(0, 10) !== v) die(['없는 날짜입니다: --since=' + v]);
    return new Date(t).toISOString();
  }
  if (/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d+)?)?(Z|[+-]\d{2}:\d{2})$/.test(v) && Number.isFinite(Date.parse(v))) {
    return new Date(Date.parse(v)).toISOString();
  }
  die(['--since 는 2026-10-20 (한국 날짜) 이나 2026-10-20T03:00:00Z (ISO 시각) 로 적어 주세요: ' + v]);
}

function idsOf(v) {
  const parts = String(v).split(',').map(x => x.trim()).filter(Boolean);
  if (!parts.length || !parts.every(x => /^[1-9]\d{0,15}$/.test(x))) {
    die(['--mark-done 에는 번호를 쉼표로 이어 적습니다. 예: --mark-done=12,13 : ' + v]);
  }
  return [...new Set(parts.map(Number))];
}

function kst(iso) {
  const t = Date.parse(iso);
  if (!Number.isFinite(t)) return String(iso || '?');
  return new Date(t + 9 * 3600e3).toISOString().slice(0, 16).replace('T', ' ') + ' KST';
}

/* 찍기 직전에 한 번 더 — 한 줄로(세트 칸은 한 줄입니다). */
function safe(s) { return FEEDBACK.cleanText(s == null ? '' : String(s)).replace(/\s+/g, ' ').trim(); }
const num = v => (typeof v === 'number' && Number.isFinite(v) ? v : null);

/** 세트 한 묶음 → "벤치 [bench-press] 60kg × 10회 × 3세트" */
function setLine(s) {
  s = s && typeof s === 'object' ? s : {};
  const head = [];
  if (s.spoken) head.push('「' + safe(s.spoken) + '」');
  if (s.name) head.push(safe(s.name));
  head.push('[' + (s.exercise ? safe(s.exercise) : '종목 없음') + ']');
  const kg = num(s.kg), reps = num(s.reps), count = num(s.count);
  const tail = [kg === null ? '?kg' : kg + 'kg', reps === null ? '?회' : reps + '회', (count === null ? 1 : count) + '세트'];
  return head.join(' ') + '  ' + tail.join(' × ');
}

/**
 * "말 → 알아들은 것 → 고른 것" 묶어 세기. chosen 의 i 번째를 heard 의 i 번째와 짝짓습니다
 * (앱의 확인 시트가 알아들은 묶음을 그 자리에서 고치기 때문). 말은 고른 쪽의 spoken, 없으면
 * 알아들은 쪽의 것. 한 고침 안의 묶음 하나가 1 입니다(세트 수가 아니라).
 */
function summarize(items) {
  const m = new Map();
  for (const it of items) {
    (it.chosen || []).forEach((c, i) => {
      const h = (it.heard || [])[i] || null;
      const spoken = safe((c && c.spoken) || (h && h.spoken) || '') || null;
      const heard = h && h.exercise ? safe(h.exercise) : null;
      const chosen = c && c.exercise ? safe(c.exercise) : null;
      const k = JSON.stringify([spoken, heard, chosen]);
      const cur = m.get(k) || { spoken, heard, chosen, count: 0, ids: [] };
      cur.count++;
      if (!cur.ids.includes(it.id)) cur.ids.push(it.id);
      m.set(k, cur);
    });
  }
  return [...m.values()].sort((a, b) => b.count - a.count ||
    String(a.spoken || '').localeCompare(String(b.spoken || '')) ||
    String(a.chosen || '').localeCompare(String(b.chosen || '')));
}

function main() {
  const f = parseFlags(process.argv.slice(2));
  const { cfg } = CONFIG.load();
  const file = cfg.db ? path.resolve(cfg.db) : path.join(__dirname, '..', 'server', 'mybody.db');
  /* 없는 DB 를 열면 빈 DB 가 새로 생깁니다 — 만들지 말고 말합니다(tools/feedback.js 와 같음). */
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

  /* --mark-done 은 그것만 합니다 — 목록을 같이 찍으면 "어느 것을 치웠나" 가 흐려집니다. */
  if (f['mark-done'] !== undefined) {
    const ids = idsOf(f['mark-done']);
    const n = api.markVoiceFeedbackDone(ids);
    if (f.json) console.log(JSON.stringify({ ok: true, marked: n, asked: ids.length }));
    else console.log('\n처리함으로 표시했습니다: ' + n + '개' +
                     (n < ids.length ? ' (나머지 ' + (ids.length - n) + '개는 이미 처리했거나 없는 번호)' : '') + '.\n');
    return 0;
  }

  const since = f.since ? sinceIso(f.since) : '';
  const includeDone = !!(f.all || f.since);
  const items = api.voiceFeedbackList({ since, includeDone });
  const what = f.since ? f.since + ' 부터 온 고침' : (f.all ? '모든 고침' : '처리 안 한 고침');

  if (f.summary) {
    const rows = summarize(items);
    if (f.json) { console.log(JSON.stringify(rows, null, 2)); return 0; }
    console.log('');
    if (!rows.length) { console.log(what + '이 없습니다.' + (includeDone ? '' : '  (처리한 것까지: --all)') + '\n'); return 0; }
    console.log(what + ' ' + items.length + '개 — 말 → 알아들은 것 → 고른 것 (많은 순서)');
    console.log('');
    const w = Math.min(6, Math.max(...rows.map(r => String(r.count).length)));
    for (const r of rows) {
      const same = r.heard === r.chosen;
      console.log('  ' + String(r.count).padStart(w) + '×  「' + (r.spoken || '말 없음') + '」 → ' +
                  (r.heard || '(못 알아들음)') + ' → ' + (r.chosen || '(종목 없음)') + (same ? '  (같음)' : '') +
                  '   #' + r.ids.slice(0, 8).join(',') + (r.ids.length > 8 ? ',…' : ''));
    }
    console.log('');
    console.log('사전에 더했으면:  node tools/voice-feedback.js --mark-done=<번호,…>');
    console.log('');
    return 0;
  }

  if (f.json) {
    /* 내부 id 대신 가명 — 출력을 어디에 붙여도 사람이 드러나지 않게. 글은 거른 것. */
    console.log(JSON.stringify(items.map(it => ({
      id: it.id, createdAt: it.createdAt, user: FEEDBACK.pseudonym(it.userId),
      appVersion: it.appVersion ? safe(it.appVersion) : null, platform: it.platform ? safe(it.platform) : null,
      transcript: safe(it.transcript), heard: it.heard, chosen: it.chosen, doneAt: it.doneAt
    })), (k, v) => (typeof v === 'string' && k !== 'createdAt' && k !== 'doneAt' ? safe(v) : v), 2));
    return 0;
  }

  console.log('');
  if (!items.length) {
    console.log(what + '이 없습니다.' + (includeDone ? '' : '  (처리한 것까지: --all)'));
    console.log('');
    return 0;
  }
  console.log(what + ' ' + items.length + '개  (새것부터 · ' + file + ')');
  for (const it of items) {
    const meta = [kst(it.createdAt), safe(it.appVersion) || '판 모름', safe(it.platform) || '기종 모름',
                  FEEDBACK.pseudonym(it.userId)];
    console.log('');
    console.log('#' + it.id + '  ' + meta.join(' · ') + (it.doneAt ? '  (처리함)' : ''));
    console.log('    들은 말   ' + safe(it.transcript));
    if (!it.heard.length) console.log('    알아들음  (없음)');
    it.heard.forEach((s, i) => console.log('    ' + (i ? '          ' : '알아들음  ') + setLine(s)));
    it.chosen.forEach((s, i) => console.log('    ' + (i ? '          ' : '고른 것   ') + setLine(s)));
  }
  console.log('');
  if (items.some(it => !it.doneAt)) console.log('모아 보기:  node tools/voice-feedback.js --summary');
  console.log('');
  return 0;
}

process.exitCode = main();
