/* =============================================================================
 * tools/test-voice-feedback.js — 헬스 「누르고 말하기」 고침 받기 · 별칭 사전 · 노트북 도구
 *
 *   node tools/test-voice-feedback.js
 *
 * 왜 이 시험이 있나
 *   POST /api/voice/feedback 은 의견처럼 **로그인 없이도** 받는 길이고, GET /api/voice/aliases 는
 *   누구나 읽는 길입니다. 로그인 관문 앞의 길이라 막는 장치(모르는 칸 · 소리 거절 · 하루 개수)가
 *   실제로 막는지, 그리고 "탈퇴하면 지웁니다 · 1년 뒤 지웁니다 · 로그에 안 남깁니다" 가
 *   코드에서 지켜지는지를 HTTP 로 두드려 봅니다.
 *
 * 보는 것
 *   [1] 검사 규칙(server/voice-feedback.js) — 글 · 세트 · 모르는 칸 · 사전 걸러 내기
 *   [2] DB — 넣기 · 세기 · 목록 · 처리함 · 탈퇴 · 1년
 *   [3] 진짜 서버 — 로그인 · 익명 · 틀린 토큰 · 400 · 413 · 429 · 로그에 내용 없음 · 탈퇴 ·
 *       사전(걸러 냄 · 캐시 머리 · 고친 파일을 다시 띄우지 않고 읽음 · 망가지면 지난 것) ·
 *       뜰 때 1년 지난 것 정리
 *   [4] 노트북 도구 tools/voice-feedback.js — 목록 · --json · --summary · --mark-done · --since
 * ========================================================================== */
'use strict';
/* 검사하는 사람의 ~/.mybody 설정이 결과를 바꾸지 않게. */
require('./testenv.js');
const { spawn, spawnSync } = require('node:child_process');
const crypto = require('node:crypto');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { DatabaseSync } = require('node:sqlite');

const ROOT = path.join(__dirname, '..');
const V = require(path.join(ROOT, 'server', 'voice-feedback.js'));
const FB = require(path.join(ROOT, 'server', 'feedback.js'));
const DBM = require(path.join(ROOT, 'server', 'db.js'));

let pass = 0, fail = 0;
const ok = (n, c, d) => {
  if (c) { pass++; console.log('  ✓', n); }
  else { fail++; console.log('  ✗', n, d === undefined ? '' : JSON.stringify(d).slice(0, 400)); }
};
const wait = ms => new Promise(r => setTimeout(r, ms));
const TMP = fs.mkdtempSync(path.join(os.tmpdir(), 'mybody-voice-'));
const PW = 'test-password-1';

const SET = (o) => Object.assign({ exercise: 'bench-press', spoken: '벤치', kg: 60, reps: 10, count: 3 }, o || {});
const BODY = (o) => Object.assign({
  appVersion: '0.2.22+330', platform: 'android', transcript: '벤치 육십 킬로 열 개 세 세트',
  heard: [SET({ exercise: null })], chosen: [SET()]
}, o || {});

/* --- [1] 검사 규칙 -------------------------------------------------------- */
function unit() {
  console.log('\n[1] 검사 규칙 (server/voice-feedback.js)');
  const P = V.parseVoiceFeedback;
  const a = P(BODY());
  ok('보통 본문 → 통과', a.ok && a.value.transcript === '벤치 육십 킬로 열 개 세 세트' &&
     a.value.heard[0].exercise === null && a.value.chosen[0].exercise === 'bench-press' &&
     a.value.chosen[0].kg === 60 && a.value.chosen[0].count === 3 && a.value.platform === 'android', a);
  ok('빠진 칸은 null · count 는 1', (() => {
    const r = P({ transcript: '스쿼트', chosen: [{ exercise: 'squat' }] });
    const s = r.ok && r.value.chosen[0];
    return s && s.kg === null && s.reps === null && s.spoken === null && s.name === null && s.count === 1 &&
      r.value.heard.length === 0 && r.value.appVersion === null && r.value.platform === null;
  })());
  ok('platform web 도 받는다 · 다른 것은 거절', P(BODY({ platform: 'web' })).ok && P(BODY({ platform: 'ios' })).ok &&
     !P(BODY({ platform: 'windows' })).ok && !P(BODY({ platform: ['ios'] })).ok);
  ok('transcript 300자 → 통과 · 301자 → 거절', P(BODY({ transcript: '가'.repeat(300) })).ok &&
     !P(BODY({ transcript: '가'.repeat(301) })).ok && /300자/.test(P(BODY({ transcript: '가'.repeat(301) })).reason));
  ok('이모지 300개도 통과 (코드 포인트로 셈)', P(BODY({ transcript: '💪'.repeat(300) })).ok);
  ok('transcript 없음 · 빈 글 · 숫자 → 거절', !P(BODY({ transcript: undefined })).ok &&
     !P(BODY({ transcript: '  \n ' })).ok && !P(BODY({ transcript: 5 })).ok);
  const esc = P(BODY({ transcript: 'a\x1b]0;x\x07b\nc‮d', chosen: [SET({ spoken: '벤\x1b치\n프레스' })] }));
  ok('제어 · 방향 뒤집기 문자는 빼고, 줄바꿈은 한 칸', esc.ok && esc.value.transcript === 'a]0;xb cd' &&
     esc.value.chosen[0].spoken === '벤치 프레스', esc.value);
  const au = P(BODY({ audio: 'UklGRg==' }));
  ok('audio 칸 → 거절 (목소리는 안 받음)', !au.ok && /audio/.test(au.reason) && /[가-힣]/.test(au.reason), au);
  ok('모르는 칸(userId 등) → 거절', !P(BODY({ userId: 'user_x' })).ok && !P(BODY({ extra: 1 })).ok);
  ok('세트 안의 모르는 칸(audio · note) → 거절', !P(BODY({ chosen: [SET({ audio: 'x' })] })).ok &&
     !P(BODY({ heard: [SET({ note: 'x' })] })).ok);
  ok('chosen 이 비었거나 없음 → 거절', !P(BODY({ chosen: [] })).ok && !P(BODY({ chosen: undefined })).ok &&
     /하나는/.test(P(BODY({ chosen: [] })).reason));
  ok('chosen · heard 10묶음 통과 · 11묶음 거절', P(BODY({ chosen: Array(10).fill(SET()), heard: Array(10).fill(SET()) })).ok &&
     !P(BODY({ chosen: Array(11).fill(SET()) })).ok && !P(BODY({ heard: Array(11).fill(SET()) })).ok);
  ok('heard 가 배열이 아니면 거절', !P(BODY({ heard: 'x' })).ok && !P(BODY({ heard: { 0: SET() } })).ok);
  ok('kg: 0 · 1000 · 62.5 통과, -1 · 1001 · "60" 거절', [0, 1000, 62.5].every(kg => P(BODY({ chosen: [SET({ kg })] })).ok) &&
     [-1, 1001, '60', true, {}].every(kg => !P(BODY({ chosen: [SET({ kg })] })).ok));
  ok('kg 이 틀리면 한국어로 어디인지', /chosen 1번째의 kg/.test(P(BODY({ chosen: [SET({ kg: 2000 })] })).reason));
  ok('reps: 정수 0~1000 · 10.5 거절', P(BODY({ chosen: [SET({ reps: 0 })] })).ok && !P(BODY({ chosen: [SET({ reps: 10.5 })] })).ok &&
     !P(BODY({ chosen: [SET({ reps: 1001 })] })).ok);
  ok('count: 1~20 · 0 · 21 · 1.5 거절', P(BODY({ chosen: [SET({ count: 20 })] })).ok &&
     [0, 21, 1.5, '3'].every(count => !P(BODY({ chosen: [SET({ count })] })).ok));
  ok('exercise: id 모양만 · 대문자 · 공백 · 65자 거절', P(BODY({ chosen: [SET({ exercise: 'lat-pulldown-2' })] })).ok &&
     ['Bench', 'bench press', 'a'.repeat(65), 5, ''].every(exercise => !P(BODY({ chosen: [SET({ exercise })] })).ok));
  ok('spoken · name 64자 통과 · 65자 거절', P(BODY({ chosen: [SET({ spoken: '벤'.repeat(64), name: '벤'.repeat(64) })] })).ok &&
     !P(BODY({ chosen: [SET({ spoken: '벤'.repeat(65) })] })).ok && !P(BODY({ chosen: [SET({ name: '벤'.repeat(65) })] })).ok);
  ok('이상한 모양은 전부 거절 — 던지지 않는다', [null, [], 'x', 7, BODY({ chosen: [null] }), BODY({ chosen: [5] }),
     BODY({ chosen: [[]] }), BODY({ appVersion: {} }), BODY({ appVersion: '판' }), BODY({ appVersion: '1'.repeat(33) })]
     .every(b => P(b).ok === false));
  ok('물려받은 이름(__proto__ · constructor)을 칸으로 대도 거절', !P(JSON.parse('{"transcript":"x","chosen":[{}],"__proto__":1}')).ok &&
     !P(BODY({ chosen: [JSON.parse('{"constructor":1}')] })).ok);
  ok('약속한 숫자: 300자 · 10묶음 · 64KB · 하루 200 · 전체 3000 · 1년', V.TRANSCRIPT_MAX === 300 && V.SETS_MAX === 10 &&
     V.BODY_LIMIT === 65536 && V.PER_DAY === 200 && V.PER_DAY_TOTAL === 3000 && V.KEEP_DAYS === 365);

  const c = V.cleanAliases({ aliases: {
    '벤치': 'bench-press', '  스쿼트   ': 'squat', 'Lat  Pull': 'lat-pulldown', '': 'squat', '나쁜값': 'Bench Press',
    ['가'.repeat(33)]: 'squat', ['가'.repeat(32)]: 'squat', '숫자': 5, '제어\x1b': 'squat', '뒤집‮기': 'squat',
    ['__proto__']: 'deadlift', '벤치 ': 'deadlift'
  } });
  ok('사전: 맞는 줄만 남기고 틀린 줄은 건너뜀', JSON.stringify(Object.keys(c.aliases).sort()) ===
     JSON.stringify(['__proto__', '가'.repeat(32), '벤치', '스쿼트', 'lat pull'].sort()) && c.skipped === 7,
     [Object.keys(c.aliases), c.skipped]);
  ok('사전: 공백 한 칸 · 앞뒤 공백 빼고 · 소문자 · 같은 말은 앞의 것', c.aliases['lat pull'] === 'lat-pulldown' &&
     c.aliases['스쿼트'] === 'squat' && c.aliases['벤치'] === 'bench-press');
  const many = {};
  for (let i = 0; i < 2100; i++) many['말' + i] = 'squat';
  ok('사전: 2000줄까지', Object.keys(V.cleanAliases({ aliases: many }).aliases).length === 2000);
  ok('사전 모양이 틀리면 던진다 (평평한 객체 · 배열)', [{ '벤치': 'bench-press' }, [], { aliases: [] }, null]
     .every(j => { try { V.cleanAliases(j); return false; } catch (e) { return true; } }));
  ok('version: 나가는 내용이 같으면 같다 (순서 · 공백만 다름)',
     V.aliasVersion(V.cleanAliases({ aliases: { a: 'x', b: 'y' } }).aliases) ===
     V.aliasVersion(V.cleanAliases({ aliases: { ' a ': 'x', b: 'y', bad: 'Y' } }).aliases) &&
     /^[0-9a-f]{12}$/.test(V.aliasVersion({})));
  ok('저장소의 기본 사전 파일은 {"aliases": {}} 모양', (() => {
    try { const r = V.cleanAliases(JSON.parse(fs.readFileSync(path.join(ROOT, 'server', 'voice-aliases.json'), 'utf8'))); return !!r; }
    catch (e) { return false; }
  })());
}

/* --- [2] DB ---------------------------------------------------------------- */
function dbUnit() {
  console.log('\n[2] DB — 넣기 · 목록 · 처리함 · 탈퇴 · 1년');
  const file = path.join(TMP, 'unit.db');
  const api = DBM.makeApi(DBM.open(file));
  const mk = h => api.signUp({ handle: h, password: PW, displayName: h, healthConsent: DBM.HEALTH_CONSENT_VERSION });
  const a = mk('vuser1'), b = mk('vuser2');
  const v = V.parseVoiceFeedback(BODY()).value;
  const idA = api.addVoiceFeedback(a.user.id, v);
  const idB = api.addVoiceFeedback(b.user.id, v);
  const idN = api.addVoiceFeedback(null, v);
  ok('번호가 늘어난다', idA > 0 && idB > idA && idN > idB, [idA, idB, idN]);
  const list = api.voiceFeedbackList();
  ok('목록은 새것부터 · heard · chosen 이 풀린 채로', list.length === 3 && list[0].id === idN && list[0].userId === null &&
     list[2].userId === a.user.id && list[2].chosen[0].exercise === 'bench-press' && list[2].heard[0].exercise === null &&
     list[2].transcript === v.transcript && list[2].appVersion === '0.2.22+330', list[2]);
  ok('limit', api.voiceFeedbackList({ limit: 2 }).length === 2);
  ok('세기: 사람별 · 전체', api.countVoiceFeedbackSince(a.user.id, '2000-01-01') === 1 &&
     api.countVoiceFeedbackSince(null, '2000-01-01') === 3 && api.countVoiceFeedbackSince(null, '2999-01-01') === 0);
  ok('처리함 → 기본 목록에서 빠짐 · 두 번째는 0개', api.markVoiceFeedbackDone([idB]) === 1 &&
     api.markVoiceFeedbackDone([idB]) === 0 && api.voiceFeedbackList().length === 2 &&
     api.voiceFeedbackList({ includeDone: true }).length === 3);
  api.deleteMe(a.user.id);
  const raw = new DatabaseSync(file, { readOnly: true });
  ok('탈퇴하면 그 사람의 고침이 안 남는다 · 다른 것은 그대로',
     raw.prepare('SELECT COUNT(*) c FROM voice_feedback WHERE user_id=?').get(a.user.id).c === 0 &&
     raw.prepare('SELECT COUNT(*) c FROM voice_feedback').get().c === 2);
  const cols = raw.prepare('PRAGMA table_info(voice_feedback)').all().map(c => c.name);
  const idx = raw.prepare("SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='voice_feedback'").all().map(x => x.name);
  raw.close();
  ok('칸: id · created_at · user_id · app_version · platform · transcript · heard · chosen · done_at',
     JSON.stringify(cols) === JSON.stringify(['id', 'created_at', 'user_id', 'app_version', 'platform', 'transcript',
                                              'heard', 'chosen', 'done_at']), cols);
  ok('색인: created_at · user_id', idx.includes('idx_voice_feedback_created') && idx.includes('idx_voice_feedback_user'), idx);
  const w = new DatabaseSync(file);
  const ago = d => new Date(Date.now() - d * 86400000).toISOString();
  w.prepare('UPDATE voice_feedback SET created_at=? WHERE id=?').run(ago(366), idB);
  w.prepare('UPDATE voice_feedback SET created_at=? WHERE id=?').run(ago(364), idN);
  w.close();
  ok('1년 지난 것만 지운다', api.pruneOldVoiceFeedback() === 1 &&
     api.voiceFeedbackList({ includeDone: true }).map(x => x.id).join() === String(idN));
}

/* --- [3] 진짜 서버 --------------------------------------------------------- */
/* 11400~11699 — 다른 서버 시험과 안 겹치게(test-inbox-page 11000~11299 가 바로 아래). */
const PORT = 11400 + Math.floor(Math.random() * 300);
const PAIR = 'voice-pair-secret';
const DB = path.join(TMP, 'srv.db');
const ALIASES = path.join(TMP, 'aliases.json');
const B = `http://127.0.0.1:${PORT}/api`;
let srv = null, out = '';
function boot(env) {
  out = '';
  const p = spawn(process.execPath, [path.join(ROOT, 'server', 'server.js')], {
    cwd: ROOT, stdio: ['ignore', 'pipe', 'pipe'],
    env: Object.assign({}, process.env, {
      PORT: String(PORT), PAIR_SECRET: PAIR, DB, AUTH_MAX: '100000', RATE_MAX: '100000',
      STATIC: path.join(ROOT, 'prototype'), NODE_NO_WARNINGS: '1', VOICE_ALIASES: ALIASES
    }, env || {})
  });
  p.stdout.on('data', d => { out += d; });
  p.stderr.on('data', d => { out += d; });
  return p;
}
async function stop() {
  if (!srv) return;
  const p = srv; srv = null;
  await new Promise(r => { p.once('exit', r); try { p.kill('SIGTERM'); } catch (e) { r(); } setTimeout(r, 3000); });
}
async function waitUp() {
  for (let i = 0; i < 80; i++) {
    try { if ((await fetch(`http://127.0.0.1:${PORT}/api/health`)).ok) return true; } catch (e) {}
    await wait(150);
  }
  return false;
}
async function call(method, p, body, token, raw) {
  const r = await fetch(B + p, {
    method,
    headers: Object.assign({ 'Content-Type': 'application/json' }, token ? { Authorization: 'Bearer ' + token } : {}),
    body: raw !== undefined ? raw : (body ? JSON.stringify(body) : undefined)
  });
  let j = null; try { j = await r.json(); } catch (e) {}
  return { status: r.status, json: j || {}, headers: r.headers };
}
const send = (body, token) => call('POST', '/voice/feedback', body, token);
function dbRows(sql, ...args) {
  const d = new DatabaseSync(DB, { readOnly: true });
  try { return d.prepare(sql).all(...args); } finally { d.close(); }
}
async function until(fn, ms = 3000) {
  const t0 = Date.now();
  while (Date.now() - t0 < ms) { if (await fn()) return true; await wait(50); }
  return fn();
}
const is400 = r => r.status === 400 && r.json.ok === false && typeof r.json.error === 'string' &&
  /[가-힣]/.test(r.json.error) && r.json.reason === r.json.error;

async function integration() {
  fs.writeFileSync(ALIASES, JSON.stringify({ aliases: { '벤치': 'bench-press', '나쁜': 'Not An Id', '데드': 'deadlift' } }));
  console.log('\n[3] 진짜 서버 — 받기');
  srv = boot({ VOICE_FEEDBACK_PER_DAY: '5', VOICE_FEEDBACK_PER_DAY_TOTAL: '12' });
  ok('서버가 뜬다', await waitUp(), out.slice(-400));
  const mk = async (handle) => (await call('POST', '/auth/signup', {
    handle, password: PW, displayName: handle, pairSecret: PAIR, healthConsent: DBM.HEALTH_CONSENT_VERSION })).json;
  const T = await mk('vtester1'), T2 = await mk('vtester2');
  ok('계정 둘', !!(T.token && T2.token));

  const MARK = '비밀스러운말' + crypto.randomBytes(3).toString('hex');
  const a = await send(BODY({ transcript: MARK + ' 벤치 육십' }), T.token);
  ok('로그인 → 200 {ok:true, id:숫자}', a.status === 200 && a.json.ok === true && Number.isInteger(a.json.id), a.json);
  const row = dbRows('SELECT * FROM voice_feedback WHERE id=?', a.json.id)[0] || {};
  ok('그 계정에 묶여 저장된다 (판 · 기종 · 글 · 세트 · 시각)', row.user_id === T.user.id && row.app_version === '0.2.22+330' &&
     row.platform === 'android' && row.transcript === MARK + ' 벤치 육십' && JSON.parse(row.chosen)[0].exercise === 'bench-press' &&
     JSON.parse(row.heard)[0].exercise === null && /^\d{4}-\d{2}-\d{2}T/.test(row.created_at) && row.done_at === null, row);
  const g = await send(BODY({ platform: 'web' }));
  ok('로그인 없이도 받는다 (익명 — user_id 없음)', g.status === 200 &&
     (dbRows('SELECT user_id FROM voice_feedback WHERE id=?', g.json.id)[0] || {}).user_id === null, g.json);
  const wt = await send(BODY(), 'not-a-real-token');
  ok('틀린 토큰이면 401 이 아니라 익명으로', wt.status === 200 &&
     (dbRows('SELECT user_id FROM voice_feedback WHERE id=?', wt.json.id)[0] || {}).user_id === null, wt.json);

  console.log('\n[3-1] 거절 — 400 · 413');
  ok('transcript 301자 → 400 {ok:false, error:한국어}', is400(await send(BODY({ transcript: '가'.repeat(301) }), T.token)));
  ok('audio 칸 → 400', is400(await send(BODY({ audio: 'UklGRiQAAABXQVZF' }), T.token)));
  ok('kg 이 틀림 → 400', is400(await send(BODY({ chosen: [SET({ kg: 5000 })] }), T.token)) &&
     is400(await send(BODY({ chosen: [SET({ kg: '60' })] }), T.token)));
  ok('chosen 이 비었음 → 400', is400(await send(BODY({ chosen: [] }), T.token)));
  ok('JSON 이 아님 → 400', (await call('POST', '/voice/feedback', null, T.token, '{깨짐')).status === 400);
  const big = await call('POST', '/voice/feedback', null, T.token, JSON.stringify(BODY({ pad: 'x'.repeat(70 * 1024) })));
  ok('본문이 64KB 를 넘음 → 413 {ok:false}', big.status === 413 && big.json.ok === false && !!big.json.error, big.json);
  ok('읽는 길(GET /api/voice/feedback)은 없다', (await call('GET', '/voice/feedback')).status === 401);

  console.log('\n[3-2] 하루 개수 (시험은 사람마다 5 · 전체 12 로 줄여 띄움)');
  for (let k = 2; k <= 5; k++) await send(BODY(), T.token);
  ok('로그인: 5번째까지 받고 거절된 400 은 안 셈', dbRows('SELECT COUNT(*) c FROM voice_feedback WHERE user_id=?', T.user.id)[0].c === 5);
  const t6 = await send(BODY(), T.token);
  ok('로그인: 6번째 → 429 {ok:false, error}', t6.status === 429 && t6.json.ok === false && /5개/.test(t6.json.error || ''), t6.json);
  ok('다른 사람은 막히지 않는다', (await send(BODY(), T2.token)).status === 200);
  /* 익명은 지금까지 2개(로그인 없음 · 틀린 토큰). 같은 주소(127.0.0.1). */
  for (let k = 3; k <= 5; k++) await send(BODY());
  const a6 = await send(BODY(), 'wrong');
  ok('익명: 같은 주소에서 6번째 → 429 (틀린 토큰도 익명으로 셈)', a6.status === 429, a6.json);
  /* 지금 전체 5 + 1 + 5 = 11. 하나 더면 12 — 그다음은 누구든 막힘. */
  ok('전체 12번째까지 받는다', (await send(BODY(), T2.token)).status === 200);
  const tot = await send(BODY(), T2.token);
  ok('전체 상한(12)을 넘으면 누구든 429', tot.status === 429 && /이 서버가/.test(tot.json.error || ''), tot.json);
  ok('서버 로그에 내용이 안 남는다 (경로 · 상태만)', /POST\s+\/api\/voice\/feedback/.test(out) && !out.includes(MARK) &&
     !out.includes('육십'), out.split('\n').filter(l => /voice/.test(l)).slice(0, 3));

  console.log('\n[3-3] 별칭 사전 GET /api/voice/aliases');
  const s1 = await call('GET', '/voice/aliases');
  ok('누구나 → 200 {ok, version, aliases} · 틀린 줄은 빠짐', s1.status === 200 && s1.json.ok === true &&
     /^[0-9a-f]{12}$/.test(s1.json.version) &&
     JSON.stringify(s1.json.aliases) === JSON.stringify({ '벤치': 'bench-press', '데드': 'deadlift' }), s1.json);
  ok('Cache-Control: public, max-age=3600', s1.headers.get('cache-control') === 'public, max-age=3600', s1.headers.get('cache-control'));
  fs.writeFileSync(ALIASES, JSON.stringify({ aliases: { '벤치': 'bench-press', '데드': 'deadlift', '스쿼트': 'squat' } }, null, 2));
  const s2 = await call('GET', '/voice/aliases');
  ok('파일을 고치면 다시 띄우지 않아도 새 내용 · 새 version', s2.json.aliases['스쿼트'] === 'squat' &&
     s2.json.version !== s1.json.version, s2.json);
  fs.writeFileSync(ALIASES, '{"aliases": {"벤치": "bench-pr');
  const s3 = await call('GET', '/voice/aliases');
  ok('쓰다 만(망가진) 파일이면 지난번 것을 그대로 (200 · 같은 version)', s3.status === 200 && s3.json.version === s2.json.version &&
     s3.json.aliases['스쿼트'] === 'squat', s3.json);
  ok('망가진 사전을 뜰 때 · 읽을 때 로그에 한 줄 (내용은 안 찍음)', /음성 별칭 사전을 못 읽었습니다 \(JSON 형식이 아닙니다\)/.test(out) &&
     !out.includes('bench-pr'), out.split('\n').filter(l => /별칭/.test(l)));
  fs.writeFileSync(ALIASES, JSON.stringify({ aliases: { '벤치': 'bench-press' } }));
  const s4 = await call('GET', '/voice/aliases');
  ok('고쳐 놓으면 다시 읽는다', JSON.stringify(s4.json.aliases) === JSON.stringify({ '벤치': 'bench-press' }), s4.json);
  fs.rmSync(ALIASES);
  const s5 = await call('GET', '/voice/aliases');
  ok('파일이 없으면 빈 사전', s5.status === 200 && JSON.stringify(s5.json.aliases) === '{}' &&
     s5.json.version === V.aliasVersion({}), s5.json);

  console.log('\n[3-4] 탈퇴 · 뜰 때 1년 지난 것 정리 · 기본 사전 파일');
  const before = dbRows('SELECT COUNT(*) c FROM voice_feedback WHERE user_id IS NULL')[0].c;
  ok('지우기 전: 둘째의 고침이 있다', dbRows('SELECT COUNT(*) c FROM voice_feedback WHERE user_id=?', T2.user.id)[0].c === 2);
  const del = await call('DELETE', '/me', null, T2.token);
  ok('탈퇴 200 → 그 사람의 고침이 안 남는다', del.status === 200 &&
     dbRows('SELECT COUNT(*) c FROM voice_feedback WHERE user_id=?', T2.user.id)[0].c === 0, del.json);
  ok('익명 고침은 그대로', dbRows('SELECT COUNT(*) c FROM voice_feedback WHERE user_id IS NULL')[0].c === before);
  const w = new DatabaseSync(DB);
  const ago = d => new Date(Date.now() - d * 86400000).toISOString();
  const ins = w.prepare("INSERT INTO voice_feedback (created_at, transcript, heard, chosen) VALUES (?, 'x', '[]', '[]')");
  const oldId = Number(ins.run(ago(400)).lastInsertRowid), keepId = Number(ins.run(ago(300)).lastInsertRowid);
  w.close();
  await stop();
  srv = boot({ VOICE_ALIASES: '' });
  ok('다시 뜬다 (사전 경로 없이)', await waitUp(), out.slice(-300));
  ok('1년 지난 고침이 지워졌다 · 안 된 것은 남았다', await until(() =>
    dbRows('SELECT COUNT(*) c FROM voice_feedback WHERE id=?', oldId)[0].c === 0) &&
    dbRows('SELECT COUNT(*) c FROM voice_feedback WHERE id=?', keepId)[0].c === 1);
  const s6 = await call('GET', '/voice/aliases');
  ok('경로를 안 주면 server/voice-aliases.json 을 내보낸다', s6.status === 200 && s6.json.ok === true &&
     typeof s6.json.aliases === 'object', s6.json);
  ok('기본 사전 경로는 설정 키 voiceAliases(환경변수 VOICE_ALIASES)로 바꾼다', (() => {
    const home = fs.mkdtempSync(path.join(os.tmpdir(), 'mybody-voice-cfg-'));
    fs.mkdirSync(path.join(home, '.mybody'));
    fs.writeFileSync(path.join(home, '.mybody', 'config.json'), JSON.stringify({ voiceAliases: '/tmp/x-aliases.json' }));
    const r = spawnSync(process.execPath, ['-e', "console.log(require('./tools/config.js').load().cfg.voiceAliases)"],
      { cwd: ROOT, encoding: 'utf8', env: Object.assign({}, process.env, { HOME: home, USERPROFILE: home, VOICE_ALIASES: '' }) });
    fs.rmSync(home, { recursive: true, force: true });
    return r.stdout.trim() === '/tmp/x-aliases.json';
  })());
  await stop();
}

/* --- [4] 노트북 도구 ------------------------------------------------------- */
function cli() {
  console.log('\n[4] 노트북 도구 tools/voice-feedback.js');
  const home = fs.mkdtempSync(path.join(os.tmpdir(), 'mybody-voicecli-home-'));
  const file = path.join(TMP, 'cli.db');
  const api = DBM.makeApi(DBM.open(file));
  const u = api.signUp({ handle: 'clivoice', password: PW, displayName: '홍길동', healthConsent: DBM.HEALTH_CONSENT_VERSION });
  const add = (uid, o) => api.addVoiceFeedback(uid, V.parseVoiceFeedback(BODY(o)).value);
  /* "벤치" 를 못 알아들은 것 셋 · "스쿼트" 를 레그프레스로 잘못 알아들은 것 하나. */
  const id1 = add(u.user.id, {});
  const id2 = add(null, {});
  const id3 = add(null, { transcript: '스쿼트 백 킬로 다섯 개', heard: [SET({ spoken: '스쿼트', exercise: 'leg-press' })],
                          chosen: [SET({ spoken: '스쿼트', exercise: 'squat' })] });
  const id4 = add(null, { transcript: '벤치 두 개 데드', heard: [SET({ exercise: null }), SET({ spoken: '데드', exercise: 'deadlift' })],
                          chosen: [SET(), SET({ spoken: '데드', exercise: 'deadlift' })] });
  const raw = new DatabaseSync(file);
  const id5 = Number(raw.prepare("INSERT INTO voice_feedback (created_at, transcript, heard, chosen) VALUES (?,?,?,?)")
    .run(new Date().toISOString(), '색\x1b[31m빨강\x1b]0;제목\x07끝', '[]',
         JSON.stringify([{ exercise: 'squat', spoken: '스\x1b[2J쿼트' }])).lastInsertRowid);
  raw.close();
  const env = Object.assign({}, process.env, { HOME: home, USERPROFILE: home, DB: file, NODE_NO_WARNINGS: '1' });
  const run = (...args) => {
    const r = spawnSync(process.execPath, [path.join(ROOT, 'tools', 'voice-feedback.js')].concat(args),
                        { cwd: ROOT, encoding: 'utf8', timeout: 30000, env });
    return { code: r.status, out: (r.stdout || '') + (r.stderr || ''), stdout: r.stdout || '' };
  };

  const r1 = run();
  ok('기본: 처리 안 한 고침 5개 (exit 0)', r1.code === 0 && /처리 안 한 고침 5개/.test(r1.out), r1.out.slice(0, 300));
  ok('새것부터', r1.out.indexOf('#' + id5) < r1.out.indexOf('#' + id4) && r1.out.indexOf('#' + id2) < r1.out.indexOf('#' + id1));
  ok('들은 말 · 알아들음 · 고른 것 · 판 · 기종', /들은 말   벤치 육십 킬로 열 개 세 세트/.test(r1.out) &&
     /알아들음  「벤치」 \[종목 없음\]  60kg × 10회 × 3세트/.test(r1.out) &&
     /고른 것   「벤치」 \[bench-press\]  60kg × 10회 × 3세트/.test(r1.out) && /0\.2\.22\+330 · android/.test(r1.out), r1.out);
  ok('보낸 사람은 가명 6자 · 익명 · 아이디 · 이름 · 내부 id 를 안 찍는다', r1.out.includes(FB.pseudonym(u.user.id)) &&
     /익명/.test(r1.out) && !r1.out.includes('clivoice') && !r1.out.includes('홍길동') && !r1.out.includes(u.user.id));
  ok('제어 문자(ESC · BEL)를 터미널에 안 흘린다', !/[\x1b\x07]/.test(r1.out) && /색\[31m빨강\]0;제목끝/.test(r1.out));

  const j = run('--json');
  let rows = null; try { rows = JSON.parse(j.stdout); } catch (e) {}
  ok('--json: 행 배열 · 가명(user) · 내부 id 없음 · 제어 문자 없음', j.code === 0 && Array.isArray(rows) && rows.length === 5 &&
     rows.find(x => x.id === id1).user === FB.pseudonym(u.user.id) && !j.stdout.includes(u.user.id) &&
     !/\\u001b|\x1b/.test(j.stdout) && rows.find(x => x.id === id1).chosen[0].exercise === 'bench-press', j.out.slice(0, 300));

  const s = run('--summary');
  const lines = s.out.split('\n').filter(l => /×  「/.test(l));
  ok('--summary: 말 → 알아들은 것 → 고른 것, 많은 순서', s.code === 0 &&
     /^\s*3×  「벤치」 → \(못 알아들음\) → bench-press/.test(lines[0] || '') &&
     lines.some(l => /1×  「스쿼트」 → leg-press → squat/.test(l)) &&
     lines.some(l => /1×  「데드」 → deadlift → deadlift  \(같음\)/.test(l)), s.out);
  ok('--summary 도 제어 문자를 안 흘린다', !/[\x1b\x07]/.test(s.out) && /스\[2J쿼트/.test(s.out));
  const sj = run('--summary', '--json');
  let sum = null; try { sum = JSON.parse(sj.stdout); } catch (e) {}
  ok('--summary --json: [{spoken, heard, chosen, count, ids}]', Array.isArray(sum) && sum[0].spoken === '벤치' &&
     sum[0].heard === null && sum[0].chosen === 'bench-press' && sum[0].count === 3 &&
     JSON.stringify(sum[0].ids.slice().sort((x, y) => x - y)) === JSON.stringify([id1, id2, id4]), sum && sum[0]);

  const m = run('--mark-done=' + id1 + ',' + id2 + ',' + id4);
  ok('--mark-done: 그 번호들만 처리함', m.code === 0 && /처리함으로 표시했습니다: 3개/.test(m.out), m.out);
  const s2 = run('--summary');
  ok('그 뒤 --summary 에는 처리 안 한 것만', s2.code === 0 && !/「벤치」/.test(s2.out) && /「스쿼트」 → leg-press → squat/.test(s2.out), s2.out);
  ok('--mark-done 두 번째는 0개 (없는 번호도 조용히)', /표시했습니다: 0개/.test(run('--mark-done', id1 + ',999999').out));
  const all = run('--all');
  ok('--all: 처리한 것까지 (처리함) 표시와 함께', all.code === 0 && /모든 고침 5개/.test(all.out) &&
     (all.out.match(/\(처리함\)/g) || []).length === 3, all.out.slice(0, 300));
  const kstToday = new Date(Date.now() + 9 * 3600e3).toISOString().slice(0, 10);
  const kstTomorrow = new Date(Date.now() + 33 * 3600e3).toISOString().slice(0, 10);
  ok('--since=오늘 → 5개 · --since 내일 → 없음 · ISO 시각도', /부터 온 고침 5개/.test(run('--since=' + kstToday).out) &&
     /부터 온 고침이 없습니다/.test(run('--since', kstTomorrow).out) &&
     /부터 온 고침 5개/.test(run('--since=2000-01-01T00:00:00Z').out));
  ok('모르는 깃발 · 틀린 값 → exit 1', run('--mark-dnoe=1').code === 1 && run('--mark-done=a,b').code === 1 &&
     run('--mark-done').code === 1 && run('--since=2026-13-01').code === 1 && run('--since=어제').code === 1 &&
     run('--json=1').code === 1);
  const missing = path.join(TMP, 'nope', 'none.db');
  const r6 = spawnSync(process.execPath, [path.join(ROOT, 'tools', 'voice-feedback.js')],
    { cwd: ROOT, encoding: 'utf8', env: Object.assign({}, env, { DB: missing }) });
  ok('DB 가 없으면 만들지 않고 exit 1', r6.status === 1 && !fs.existsSync(missing) && /데이터베이스가 없습니다/.test(r6.stderr));
  try { fs.rmSync(home, { recursive: true, force: true }); } catch (e) {}
}

(async () => {
  try {
    unit();
    dbUnit();
    await integration();
    cli();
  } catch (e) {
    fail++;
    console.error(e);
  }
  await stop();
  try { fs.rmSync(TMP, { recursive: true, force: true }); } catch (e) {}
  console.log(`\n통과 ${pass} / 실패 ${fail}`);
  process.exit(fail ? 1 : 0);
})();
process.on('exit', () => { if (srv) { try { srv.kill(); } catch (e) {} } });
