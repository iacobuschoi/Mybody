/* =============================================================================
 * server/voice-feedback.js — 헬스 「누르고 말하기」 가 틀렸을 때 고친 것을 받기 · 별칭 사전
 *
 * 왜 있나
 *   「누르고 말하기」 는 "벤치 육십 킬로 열 개 세 세트" 같은 말을 세트로 바꿉니다. 앱이
 *   알아들은 것(heard)이 틀리면 사람은 확인 시트에서 고쳐서(chosen) 저장합니다. 그 고친 것이
 *   어디에도 안 남으면, 같은 말을 백 명이 백 번 고쳐도 앱은 계속 같은 말을 틀립니다.
 *   그래서 앱이 "들은 글 · 알아들은 것 · 고른 것" 세 가지를 서버로 보냅니다
 *   (POST /api/voice/feedback). 주인은 노트북 도구(tools/voice-feedback.js --summary)로
 *   "이 말 → 이렇게 알아들었는데 → 사실은 이것" 을 많은 순서로 보고, 별칭 사전
 *   (GET /api/voice/aliases — 아래 makeAliasStore)에 한 줄을 더합니다. 앱은 그 사전을
 *   받아 다음부터 그 말을 맞게 알아듣습니다.
 *
 * 받는 것과 안 받는 것
 *   · 받는 것 — 받아쓴 글(transcript, 300자까지)과 세트 묶음 두 개. 몸 숫자라고 해야
 *     무게 · 횟수뿐이고, 그것도 "어떤 말을 어떻게 알아들었나" 를 보려고 받는 것입니다.
 *   · **목소리(소리 파일)는 안 받습니다.** 모르는 칸은 전부 거절합니다 — audio 같은 칸을
 *     조용히 버리면, 앱이 언젠가 소리를 실어 보내도 아무도 모른 채 바이트가 오가기만 합니다.
 *     거절하면 그 판을 만든 사람이 시험에서 바로 봅니다.
 *
 * 검사는 server/feedback.js 와 같은 규칙입니다
 *   글자 수는 코드 포인트로, 제어 문자 · 글자 방향 뒤집기 문자는 저장하기 전에 빼고
 *   (feedback.js cleanText — 로그인 없이 받은 글이 주인의 터미널에 찍힙니다), 판은 같은
 *   모양(32자 · 보이는 ASCII). 틀리면 어디서 틀렸는지 한국어로 돌려줍니다.
 *
 * 저장소가 공개라서
 *   받은 내용은 이 파일 · 로그 어디에도 찍지 않습니다. 서버 로그에는
 *   "POST /api/voice/feedback 200" 한 줄만 남습니다(server.js logLine). 알림도 없습니다 —
 *   주인이 "음성 고침은 알림 받지 않겠다" 고 정했습니다. 하루에 한 번 도구로 모아 봅니다.
 * ========================================================================== */
'use strict';
const crypto = require('node:crypto');
const fs = require('node:fs');
const FEEDBACK = require('./feedback.js');

const { cleanText, codePoints } = FEEDBACK;

/* 받아쓴 글. 한 번 누르고 말하는 길이라 몇 마디입니다 — 300자면 넉넉합니다. */
const TRANSCRIPT_MAX = 300;
/* 한 번에 말하는 세트 묶음 수(종목 하나 = 묶음 하나). 열 종목을 한 숨에 말하는 사람은 없습니다. */
const SETS_MAX = 10;
const WORD_MAX = 64;          // spoken · name
const EXERCISE_RE = /^[a-z0-9-]{1,64}$/;
const KG_MAX = 1000;
const REPS_MAX = 1000;
const COUNT_MAX = 20;
const APP_VERSION_MAX = FEEDBACK.APP_VERSION_MAX;
const PLATFORM_MAX = 16;
const PLATFORMS = ['android', 'ios', 'web'];
/* 본문 상한. 글 300자(전부 \uXXXX 여도 2KB 남짓) + 세트 20묶음이라 몇 KB 입니다.
   다른 길의 2MB 를 그대로 열어 둘 이유가 없습니다 — 로그인 없이 받는 길입니다. */
const BODY_LIMIT = 64 * 1024;
/* 하루에 받는 개수 — 로그인했으면 사람마다, 아니면 보내온 주소(IP)마다.
   한 번의 운동에 세트를 스무 번 넘게 말하고, 고칠 때마다 한 건씩 옵니다. 200 이면
   열심히 고치는 사람도 안 막히고, 고장 난 앱이 끝없이 보내는 것은 거기서 멈춥니다. */
const PER_DAY = 200;
/* 서버 전체 하루 상한. 한 건이 몇 KB 라 3000 건이어도 하루 10MB 안쪽입니다. */
const PER_DAY_TOTAL = 3000;
/* 보관 기간(일). 의견과 같은 1년(feedback.js KEEP_DAYS) — 처리방침에 숫자를 하나만 적게. */
const KEEP_DAYS = FEEDBACK.KEEP_DAYS;

/* 세트 한 묶음에 올 수 있는 칸. 이 밖의 칸은 거절합니다(위 "받는 것과 안 받는 것"). */
const SET_KEYS = ['exercise', 'name', 'spoken', 'kg', 'reps', 'count'];
const BODY_KEYS = ['appVersion', 'platform', 'transcript', 'heard', 'chosen'];

function no(reason) { return { ok: false, reason }; }
const has = (o, k) => Object.prototype.hasOwnProperty.call(o, k);
const given = v => v !== undefined && v !== null;

/* 한 줄짜리 낱말(spoken · name): 거르고, 줄바꿈 · 탭은 한 칸으로, 앞뒤 공백 빼고.
   비면 null. 길면 { bad } — 거절할 말은 부르는 쪽이 붙입니다. */
function word(v, max) {
  if (typeof v !== 'string') return { bad: '글자여야 합니다' };
  /* 펼치기 전에 넉넉한 UTF-16 길이로 먼저 자릅니다(feedback.js 와 같은 이유). */
  if (v.length > max * 4) return { bad: max + '자까지입니다' };
  const s = cleanText(v).replace(/\s+/g, ' ').trim();
  if (codePoints(s) > max) return { bad: max + '자까지입니다' };
  return { value: s || null };
}

/**
 * 세트 한 묶음 → 저장할 모양. 틀리면 { ok:false, reason }.
 * 빠진 칸은 null(count 는 1)입니다 — "몰라서 비움" 과 "0kg(맨몸)" 을 가르려고 0 으로 채우지 않습니다.
 */
function parseSet(s, label) {
  if (!s || typeof s !== 'object' || Array.isArray(s)) return no(label + '의 형식이 맞지 않습니다');
  for (const k of Object.keys(s)) {
    if (!SET_KEYS.includes(k)) return no(label + '에 모르는 칸이 있습니다: ' + String(k).slice(0, 32));
  }
  let exercise = null;
  if (given(s.exercise)) {
    if (typeof s.exercise !== 'string' || !EXERCISE_RE.test(s.exercise)) {
      return no(label + '의 exercise 는 영문 소문자 · 숫자 · - 로 된 종목 id(64자까지)여야 합니다');
    }
    exercise = s.exercise;
  }
  let name = null;
  if (given(s.name)) {
    const w = word(s.name, WORD_MAX);
    if (w.bad) return no(label + '의 name 은 ' + w.bad);
    name = w.value;
  }
  let spoken = null;
  if (given(s.spoken)) {
    const w = word(s.spoken, WORD_MAX);
    if (w.bad) return no(label + '의 spoken 은 ' + w.bad);
    spoken = w.value;
  }
  /* 숫자는 숫자로만. "60" 같은 글자를 바꿔 받으면, 앱이 어디선가 글자를 보내고 있다는
     고장이 서버에서 조용히 덮입니다. */
  let kg = null;
  if (given(s.kg)) {
    if (typeof s.kg !== 'number' || !Number.isFinite(s.kg) || s.kg < 0 || s.kg > KG_MAX) {
      return no(label + '의 kg 은 0~' + KG_MAX + ' 사이의 숫자여야 합니다');
    }
    kg = s.kg;
  }
  let reps = null;
  if (given(s.reps)) {
    if (!Number.isInteger(s.reps) || s.reps < 0 || s.reps > REPS_MAX) {
      return no(label + '의 reps 는 0~' + REPS_MAX + ' 사이의 정수여야 합니다');
    }
    reps = s.reps;
  }
  let count = 1;
  if (given(s.count)) {
    if (!Number.isInteger(s.count) || s.count < 1 || s.count > COUNT_MAX) {
      return no(label + '의 count 는 1~' + COUNT_MAX + ' 사이의 정수여야 합니다');
    }
    count = s.count;
  }
  return { ok: true, value: { exercise, name, spoken, kg, reps, count } };
}

function parseSets(list, what, min) {
  if (!Array.isArray(list)) return no(what + ' 는 세트 목록(배열)이어야 합니다');
  if (list.length < min) return no(what + ' 에 세트가 하나는 있어야 합니다');
  if (list.length > SETS_MAX) return no(what + ' 는 ' + SETS_MAX + '묶음까지입니다');
  const out = [];
  for (let i = 0; i < list.length; i++) {
    const r = parseSet(list[i], what + ' ' + (i + 1) + '번째');
    if (!r.ok) return r;
    out.push(r.value);
  }
  return { ok: true, value: out };
}

/**
 * 받은 본문을 저장할 모양으로. 틀리면 { ok:false, reason }.
 * @returns {{ok:true, value:{appVersion:string|null, platform:string|null, transcript:string,
 *            heard:object[], chosen:object[]}}}
 */
function parseVoiceFeedback(body) {
  if (!body || typeof body !== 'object' || Array.isArray(body)) return no('보낸 내용의 형식이 맞지 않습니다');
  for (const k of Object.keys(body)) {
    if (!BODY_KEYS.includes(k)) {
      return no(k === 'audio' ? '목소리(audio)는 받지 않습니다' : '모르는 칸이 있습니다: ' + String(k).slice(0, 32));
    }
  }

  if (typeof body.transcript !== 'string') return no('transcript(받아쓴 글)가 필요합니다');
  if (body.transcript.length > TRANSCRIPT_MAX * 4) return no('transcript 는 ' + TRANSCRIPT_MAX + '자까지입니다');
  /* 받아쓴 글은 한 줄입니다 — 줄바꿈이 섞여 와도 한 칸으로. */
  const transcript = cleanText(body.transcript).replace(/\s+/g, ' ').trim();
  if (!transcript) return no('transcript(받아쓴 글)가 비어 있습니다');
  if (codePoints(transcript) > TRANSCRIPT_MAX) return no('transcript 는 ' + TRANSCRIPT_MAX + '자까지입니다');

  /* 알아들은 것은 비어도 됩니다(아무것도 못 알아들어서 사람이 다 고른 경우).
     고른 것은 하나는 있어야 합니다 — 고친 게 없으면 보낼 까닭이 없습니다. */
  const heard = parseSets(given(body.heard) ? body.heard : [], 'heard', 0);
  if (!heard.ok) return heard;
  const chosen = parseSets(body.chosen, 'chosen', 1);
  if (!chosen.ok) return chosen;

  /* 판 · 기종 — feedback.js 와 같은 규칙. 웹(PWA)에서도 말하기가 되므로 web 도 받습니다. */
  let appVersion = null;
  if (given(body.appVersion) && body.appVersion !== '') {
    if (typeof body.appVersion !== 'string' || body.appVersion.length > APP_VERSION_MAX ||
        !/^[\x20-\x7e]+$/.test(body.appVersion)) {
      return no('appVersion 형식이 맞지 않습니다');
    }
    appVersion = body.appVersion.trim() || null;
  }
  let platform = null;
  if (given(body.platform) && body.platform !== '') {
    if (typeof body.platform !== 'string' || body.platform.length > PLATFORM_MAX || !PLATFORMS.includes(body.platform)) {
      return no('platform 은 android · ios · web 중 하나입니다');
    }
    platform = body.platform;
  }

  return { ok: true, value: { appVersion, platform, transcript, heard: heard.value, chosen: chosen.value } };
}

/* --- 별칭 사전 (GET /api/voice/aliases) ------------------------------------
 *
 * 파일 모양 — 하나만 받습니다:
 *   { "aliases": { "벤치": "bench-press", "스쿼트": "squat", ... } }
 * 바깥을 한 겹 싸는 이유: 나중에 칸(예: 적은 날짜 · 메모)을 더해도 앱과의 약속이 안 바뀝니다.
 *
 * 들어오는 말(키)은 1~32자 — 거르고(제어 · 방향 뒤집기 문자가 있으면 그 줄을 버림), 공백은
 * 한 칸으로, 앞뒤 공백 빼고, NFC 로 맞추고 소문자로. 종목 id(값)는 /^[a-z0-9-]{1,64}$/.
 * 틀린 줄은 **그 줄만** 건너뜁니다 — 매일 도는 작업이 한 줄을 잘못 적었다고 사전 전체가
 * 사라지면, 앱은 어제까지 맞게 알아듣던 말을 오늘 전부 틀립니다. 2000줄까지(파일 순서대로).
 *
 * 파일을 고쳐도 서버를 다시 띄우지 않습니다: 부를 때마다 stat 을 보고, 바뀌었으면(수정 시각 ·
 * 크기 · inode) 다시 읽습니다. 바뀐 파일이 JSON 이 아니면(쓰는 도중에 읽었거나 손으로 고치다
 * 틀림) **지난번에 읽은 것**을 그대로 내보냅니다 — GET /api/version 이 망가진 설정을 빈 값으로
 * 내보내지 않는 것과 같은 이유입니다. 한 번도 못 읽었으면 null(server.js 가 503).
 * 파일이 아예 없으면 빈 사전입니다(주인이 아직 아무것도 안 적은 것).
 *
 * version — 내보내는 사전(걸러 낸 뒤)의 sha256 앞 12자. 파일 내용이 아니라 **나가는 내용**으로
 * 셉니다: 공백 · 순서만 바꾸거나 틀린 줄만 고쳐 넣어도 앱이 받는 것이 같으면 같은 version 입니다.
 * -------------------------------------------------------------------------- */
const ALIAS_KEY_MAX = 32;
const ALIASES_MAX = 2000;
/* 2000줄이면 100KB 안쪽입니다. 그 열 배를 넘는 파일은 사전이 아니라 사고입니다. */
const ALIAS_FILE_MAX = 1_000_000;
const CONTROL_ONE = /[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f-\u009f‪-‮⁦-⁩]/;

/** 파일에서 읽은 객체 → { aliases, skipped }. 모양이 틀렸으면 던집니다. */
function cleanAliases(j) {
  if (!j || typeof j !== 'object' || Array.isArray(j) || !j.aliases ||
      typeof j.aliases !== 'object' || Array.isArray(j.aliases)) {
    throw new Error('{"aliases": {...}} 모양이 아닙니다');
  }
  /* 물려받은 이름이 없는 객체 — "__proto__" 라는 말도 그냥 한 줄로 다룹니다. */
  const out = Object.create(null);
  let n = 0, skipped = 0;
  for (const k of Object.keys(j.aliases)) {
    const v = j.aliases[k];
    if (n >= ALIASES_MAX) { skipped++; continue; }
    if (CONTROL_ONE.test(k) || typeof v !== 'string' || !EXERCISE_RE.test(v)) { skipped++; continue; }
    const key = k.replace(/\s+/g, ' ').trim().normalize('NFC').toLowerCase();
    const len = codePoints(key);
    if (len < 1 || len > ALIAS_KEY_MAX || has(out, key)) { skipped++; continue; }
    out[key] = v;
    n++;
  }
  return { aliases: out, skipped };
}

function aliasVersion(aliases) {
  return crypto.createHash('sha256').update(JSON.stringify(aliases)).digest('hex').slice(0, 12);
}

/**
 * file 을 읽는 사전. get() → { version, aliases, skipped } 또는 null(한 번도 못 읽음).
 * onError(message) — 바뀐 파일을 못 읽었을 때 한 번(같은 파일 상태에 대해서는 다시 안 부름).
 */
function makeAliasStore(file, onError) {
  let seen = null;      // 마지막으로 본 파일 상태 'mtime:size:ino' (못 읽은 것 포함)
  let good = null;      // 마지막으로 읽어 낸 사전
  return function get() {
    let st = null;
    try { st = fs.statSync(file); }
    catch (e) {
      if (!e || e.code !== 'ENOENT') { if (onError && seen !== 'err') onError(e.message); seen = 'err'; return good; }
    }
    const key = st ? st.mtimeMs + ':' + st.size + ':' + st.ino : 'none';
    if (key === seen) return good;
    seen = key;
    if (!st) {
      const aliases = Object.create(null);
      good = { version: aliasVersion(aliases), aliases, skipped: 0 };
      return good;
    }
    try {
      if (st.size > ALIAS_FILE_MAX) throw new Error('파일이 너무 큽니다 (' + st.size + '바이트)');
      const r = cleanAliases(JSON.parse(fs.readFileSync(file, 'utf8')));
      good = { version: aliasVersion(r.aliases), aliases: r.aliases, skipped: r.skipped };
    } catch (e) {
      /* 메시지에 파일 내용 조각이 섞일 수 있어(JSON.parse) 종류만 넘깁니다. */
      if (onError) onError(e instanceof SyntaxError ? 'JSON 형식이 아닙니다' : e.message);
    }
    return good;
  };
}

module.exports = { TRANSCRIPT_MAX, SETS_MAX, WORD_MAX, KG_MAX, REPS_MAX, COUNT_MAX, PLATFORMS,
                   BODY_LIMIT, PER_DAY, PER_DAY_TOTAL, KEEP_DAYS, EXERCISE_RE,
                   ALIAS_KEY_MAX, ALIASES_MAX, ALIAS_FILE_MAX,
                   parseVoiceFeedback, parseSet, cleanAliases, aliasVersion, makeAliasStore };
