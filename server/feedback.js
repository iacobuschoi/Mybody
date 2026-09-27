/* =============================================================================
 * server/feedback.js — 앱 안 「의견 보내기」 가 보낸 것을 받아도 되는 모양으로 다듬기
 *
 * 왜 있나
 *   시험판을 쓰는 사람이 "여기 이상해요" 를 말할 길이 카톡뿐이었습니다. 그러면
 *   어느 판 · 어느 화면인지를 주인이 되물어야 하고, 캡처는 대화방에 묻힙니다.
 *   그래서 앱이 화면 캡처(최대 3장)와 글 한 토막을 서버로 바로 보냅니다
 *   (POST /api/feedback). 글은 없어도 됩니다 — 캡처만 붙여 보내는 게 제일
 *   빠르고, 그게 주인이 원한 "누르면 끝" 입니다.
 *
 * 이 파일이 하는 일
 *   · 본문 검사 — 글 · 사진 · 판 · 기종 · 화면 이름. 어디서 틀렸는지 한국어로.
 *   · 사진 검사 — base64 를 **엄격하게** 풀고(되돌려 인코딩해서 같아야 함),
 *     크기 상한, 그리고 앞머리 바이트가 말한 형식과 맞는지(PNG 89 50 4E 47 ·
 *     JPEG FF D8 FF). 로그인 없이도 받는 길이라, "image/png" 라는 말만 믿고
 *     아무 바이트나 DB 에 쌓지 않습니다. 이 사진은 나중에 주인이 노트북에서
 *     파일로 꺼내 여는 것이라 더 그렇습니다.
 *   · 주인 알림을 10분에 한 번으로 묶는 것(makeThrottle).
 *   · 노트북 도구(tools/feedback.js)가 사람을 가리킬 때 쓰는 가명(pseudonym).
 *     아이디 · 이메일 대신 sha256(user_id) 앞 6자 — 같은 사람이 보낸 것끼리는
 *     묶어 볼 수 있고, 그게 누구인지는 도구 출력만으로는 모릅니다.
 *
 * 규칙을 한 군데 두는 이유
 *   서버(server.js) · DB(db.js) · 노트북 도구 · 시험이 같은 숫자(2000자 · 3장 ·
 *   1.5MB · 1년)를 봐야 합니다. 도구는 받아 주는데 서버는 버리는 값, 방침에는
 *   1년이라 적었는데 코드는 2년인 값이 생기면 그중 하나는 거짓말입니다.
 *
 * 저장소가 공개라서
 *   의견 내용은 이 파일 · 로그 · 알림 어디에도 찍지 않습니다. 서버 로그에는
 *   "POST /api/feedback 200" 한 줄만 남고(server.js logLine), 주인 폰으로 가는
 *   알림은 "새 의견이 왔어요" 뿐입니다 — FCM 본문은 구글 · 애플이 읽는 평문입니다.
 * ========================================================================== */
'use strict';
const crypto = require('node:crypto');

/* 글자 수는 **코드 포인트**로 셉니다. JS 의 length 는 UTF-16 단위라 이모지 하나가
   2 로 세어지고, 앱 입력칸(플러터 maxLength — 글자 단위)이 받아 준 2000자를 서버가
   "너무 깁니다" 로 버리는 일이 생깁니다. 보내는 사람은 그걸 고칠 방법이 없습니다. */
const TEXT_MAX = 2000;
const IMAGES_MAX = 3;
/* 캡처 한 장의 상한(풀어 낸 바이트). 폰 화면 PNG 는 보통 0.3~1MB 입니다. */
const IMAGE_BYTES_MAX = 1_500_000;
/* base64 는 3바이트를 4글자로 늘립니다. 풀기 **전에** 이것으로 먼저 자릅니다 —
   20MB 짜리 글자를 받아 놓고 다 풀어 본 뒤에야 크다고 하면 그만큼 메모리를 씁니다. */
const IMAGE_B64_MAX = Math.ceil(IMAGE_BYTES_MAX / 3) * 4;
const APP_VERSION_MAX = 32;
const SCREEN_MAX = 64;
/* 이 길만 본문 상한을 올립니다: 사진 3장 × 2,000,000 글자 + 글(2000자가 전부 \uXXXX
   이스케이프여도 수십 KB) + 나머지. 다른 길은 그대로 2MB 입니다(server.js readBody). */
const BODY_LIMIT = 6_200_000;
/* 하루에 받는 개수 — 로그인했으면 사람마다, 아니면 보내온 주소(IP)마다. */
const PER_DAY = 20;
/* 서버 전체 하루 상한. 로그인 없이도 받는 길이라, 주소를 여러 개 쥔 사람이 한 장에
   4.5MB 씩 디스크를 채우는 것을 막는 울타리입니다. 사람 100명 규모에서 하루 300건은
   오지 않습니다 — 여기 걸리면 고장이거나 남용입니다. */
const PER_DAY_TOTAL = 300;
/* 보관 기간(일). 처리방침(docs/privacy.html 「의견 보내기」)에 적힌 숫자와 같아야 합니다. */
const KEEP_DAYS = 365;
/* 주인 알림 사이 최소 간격. 시험판을 막 돌린 날 의견이 몰려도 폰은 한 번만 울립니다 —
   알림을 보고 할 일은 "노트북에서 도구를 돌린다" 하나라서, 몇 번 울려도 할 일이 같습니다. */
const NOTIFY_GAP_MS = 10 * 60_000;

const TYPES = {
  'image/png': { ext: 'png', magic: Buffer.from([0x89, 0x50, 0x4e, 0x47]) },
  'image/jpeg': { ext: 'jpg', magic: Buffer.from([0xff, 0xd8, 0xff]) }
};
/* TYPES[x] 로 바로 찾으면 "constructor" · "toString" 같은 물려받은 이름이 통과합니다 —
   형식 검사를 지나 magic 을 읽다가 500 이 납니다. 자기 이름만 봅니다. */
function typeOf(t) {
  return typeof t === 'string' && Object.prototype.hasOwnProperty.call(TYPES, t) ? TYPES[t] : null;
}

/* 저장하기 전에 걸러 내는 글자 — 줄바꿈(\n)과 탭만 남기고 나머지 제어 문자는 뺍니다.
 *
 * 로그인 없이 받는 글이 **주인의 터미널**에 그대로 찍힙니다(tools/feedback.js).
 * ESC(\x1b)로 시작하는 줄을 넣으면 터미널의 제목을 바꾸거나 화면을 지우거나, 어떤
 * 터미널에서는 그 이상도 합니다. 글자 방향을 뒤집는 문자(U+202A~202E · U+2066~2069)도
 * 뺍니다 — 보이는 글과 실제 글이 달라지게 만드는 것 말고는 쓸 데가 없습니다.
 * 도구도 찍기 전에 한 번 더 거릅니다(옛 행 · 손으로 넣은 행).
 * 그 문자들은 **\u 로만** 적습니다. 글자 그대로 넣으면 이 줄 자체가 보이는 것과 다르게
 * 읽히고, 공개 저장소(GitHub)가 "숨은 양방향 문자" 경고를 파일에 붙입니다. */
const CONTROL_RE = /[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f-\u009f\u202a-\u202e\u2066-\u2069]/g;
function cleanText(s) {
  return String(s).replace(/\r\n?/g, '\n').replace(CONTROL_RE, '');
}

function codePoints(s) { return Array.from(s).length; }

/** 거절 — server.js 가 400 으로 내보냅니다. */
function no(reason) { return { ok: false, reason }; }

/**
 * 받은 본문을 저장할 모양으로. 틀리면 { ok:false, reason }.
 * @returns {{ok:true, value:{text:string|null, images:{type:string, data:Buffer}[],
 *            appVersion:string|null, platform:string|null, screen:string|null}}}
 */
function parseFeedback(body) {
  if (!body || typeof body !== 'object' || Array.isArray(body)) return no('보낸 내용의 형식이 맞지 않습니다');

  /* 글 — 없어도 됩니다. 숫자 · 객체는 거절합니다(문자열로 바꿔 받으면 "[object Object]"
     라는 의견이 쌓입니다). */
  let text = null;
  if (body.text !== undefined && body.text !== null) {
    if (typeof body.text !== 'string') return no('의견 글은 글자여야 합니다');
    /* 코드 포인트로 세려면 글자를 배열로 펼쳐야 합니다. 6MB 짜리 글을 통째로 펼치면
       그 몇 배의 메모리를 씁니다 — 넉넉한 UTF-16 길이로 먼저 자릅니다(2000자는 많아야 4000). */
    if (body.text.length > TEXT_MAX * 4) return no('의견 글은 ' + TEXT_MAX + '자까지 보낼 수 있습니다');
    const t = cleanText(body.text).trim();
    if (codePoints(t) > TEXT_MAX) return no('의견 글은 ' + TEXT_MAX + '자까지 보낼 수 있습니다');
    text = t || null;
  }

  const images = [];
  if (body.images !== undefined && body.images !== null) {
    if (!Array.isArray(body.images)) return no('사진 목록의 형식이 맞지 않습니다');
    if (body.images.length > IMAGES_MAX) return no('사진은 ' + IMAGES_MAX + '장까지 붙일 수 있습니다');
    for (let i = 0; i < body.images.length; i++) {
      const im = body.images[i];
      const n = (i + 1) + '번째 사진';
      if (!im || typeof im !== 'object') return no(n + '의 형식이 맞지 않습니다');
      const kind = typeOf(im.type);
      if (!kind) return no(n + '은 PNG 나 JPEG 여야 합니다');
      if (typeof im.data !== 'string' || !im.data) return no(n + '의 내용이 비어 있습니다');
      if (im.data.length > IMAGE_B64_MAX) return no(n + '이 너무 큽니다 (한 장 1.5MB 까지)');
      /* 엄격하게: 글자 모양 · 4의 배수 길이 · 되돌려 인코딩했을 때 같아야 함.
         Buffer.from(…, 'base64') 는 틀린 글자를 **조용히 건너뛰고** 풀어 줍니다 —
         그대로 믿으면 반쯤 깨진 파일이 "PNG" 로 저장됩니다. */
      if (im.data.length % 4 !== 0 || !/^[A-Za-z0-9+/]+={0,2}$/.test(im.data)) {
        return no(n + '의 base64 형식이 맞지 않습니다');
      }
      const buf = Buffer.from(im.data, 'base64');
      if (buf.toString('base64') !== im.data) return no(n + '의 base64 형식이 맞지 않습니다');
      if (buf.length > IMAGE_BYTES_MAX) return no(n + '이 너무 큽니다 (한 장 1.5MB 까지)');
      if (buf.length < kind.magic.length || !buf.subarray(0, kind.magic.length).equals(kind.magic)) {
        return no(n + '의 내용이 ' + (im.type === 'image/png' ? 'PNG' : 'JPEG') + ' 가 아닙니다');
      }
      images.push({ type: im.type, data: buf });
    }
  }

  if (!text && !images.length) return no('의견 글이나 화면 중 하나는 있어야 합니다');

  /* 판 · 기종 · 화면 — 없어도 되지만, 있는데 모양이 틀리면 거절합니다(/push/device 와
     같은 규칙). 앱이 보내는 값이라 틀렸다면 앱 쪽 고장이고, 조용히 버리면 아무도 모릅니다. */
  let appVersion = null;
  if (body.appVersion !== undefined && body.appVersion !== null && body.appVersion !== '') {
    if (typeof body.appVersion !== 'string' || body.appVersion.length > APP_VERSION_MAX ||
        !/^[\x20-\x7e]+$/.test(body.appVersion)) {
      return no('appVersion 형식이 맞지 않습니다');
    }
    appVersion = body.appVersion.trim() || null;
  }
  let platform = null;
  if (body.platform !== undefined && body.platform !== null && body.platform !== '') {
    if (body.platform !== 'android' && body.platform !== 'ios') return no('platform 은 android 또는 ios 입니다');
    platform = body.platform;
  }
  let screen = null;
  if (body.screen !== undefined && body.screen !== null && body.screen !== '') {
    if (typeof body.screen !== 'string') return no('screen 형식이 맞지 않습니다');
    if (body.screen.length > SCREEN_MAX * 4) return no('screen 은 ' + SCREEN_MAX + '자까지입니다');
    const s = cleanText(body.screen).replace(/\s+/g, ' ').trim();
    if (codePoints(s) > SCREEN_MAX) return no('screen 은 ' + SCREEN_MAX + '자까지입니다');
    screen = s || null;
  }

  return { ok: true, value: { text, images, appVersion, platform, screen } };
}

/** 저장된 형식 → 파일 확장자. 모르는 형식은 bin(열어 보기 전에 한 번 의심하게). */
function extFor(type) { const k = typeOf(type); return k ? k.ext : 'bin'; }

/** 사람을 가리키는 짧은 가명. 익명이면 '익명'. 같은 사람 = 같은 가명. */
function pseudonym(userId) {
  if (!userId) return '익명';
  return crypto.createHash('sha256').update(String(userId)).digest('hex').slice(0, 6);
}

/**
 * gapMs 안에 한 번만 true. 처음은 늘 true.
 * 보냈는지(기기가 있었는지)와 상관없이 **물어본 순간**을 적습니다 — 주인 폰이 꺼져
 * 있을 때 의견이 올 때마다 FCM 을 다시 두드릴 이유가 없습니다.
 */
function makeThrottle(gapMs, now) {
  const clock = now || Date.now;
  let last = -Infinity;
  return function allow() {
    const t = clock();
    if (t - last < gapMs) return false;
    last = t;
    return true;
  };
}

module.exports = { TEXT_MAX, IMAGES_MAX, IMAGE_BYTES_MAX, IMAGE_B64_MAX, APP_VERSION_MAX, SCREEN_MAX,
                   BODY_LIMIT, PER_DAY, PER_DAY_TOTAL, KEEP_DAYS, NOTIFY_GAP_MS, TYPES,
                   parseFeedback, cleanText, extFor, pseudonym, makeThrottle };
