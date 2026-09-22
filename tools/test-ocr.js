/* =============================================================================
 * tools/test-ocr.js — 2층(서버 판독) 검증
 *
 *   node tools/test-ocr.js
 *
 * 진짜 모델을 부르지 않습니다. 가짜 API 서버를 띄워서, 모델이 무엇을
 * 돌려주든 우리 서버가 그것을 어떻게 다루는지만 봅니다. 여기서 봐야
 * 하는 것은 모델의 정확도가 아니라 우리 쪽의 처신입니다:
 *   - 키가 없으면 조용히 물러나는가 (0층이 남아야 합니다)
 *   - 로그인 없이는 안 되는가
 *   - 모델이 헛소리를 하면 걸러내는가
 *   - 사진이 너무 크면 끊지 않고 413 을 돌려주는가
 *     (끊으면 브라우저에는 "Failed to fetch" 로 보여서 서버가 죽은
 *      것과 구분이 안 됩니다)
 * ========================================================================== */
'use strict';
/* 검사하는 사람의 ~/.mybody 설정이 결과를 바꾸지 않게 떼어 놓습니다. */
require('./testenv.js');
const { spawn } = require('node:child_process');
const http = require('node:http');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const PORT = 8600 + Math.floor(Math.random() * 300);
const FAKE_PORT = PORT + 1;
const PAIR = 'test-pair-secret';
const PW = 'test-password-1';
const DB = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'mybody-ocr-')), 'test.db');
const B = `http://localhost:${PORT}/api`;

let pass = 0, fail = 0;
const ok = (n, c, d) => {
  if (c) { pass++; console.log('  ✓', n); }
  else { fail++; console.log('  ✗', n, d === undefined ? '' : JSON.stringify(d)); }
};

/* --- 가짜 모델 API ------------------------------------------------------- */
let nextReply = null;      // 다음 요청에 돌려줄 것
let lastRequest = null;    // 우리가 무엇을 보냈는지 확인용
let lastHeaders = null;    // 어떤 헤더로 보냈는지 확인용
const fake = http.createServer((req, res) => {
  let body = '';
  req.on('data', c => { body += c; });
  req.on('end', () => {
    lastHeaders = req.headers;
    try { lastRequest = JSON.parse(body); } catch { lastRequest = null; }
    const r = nextReply || { status: 200, body: toolReply({ notInBody: false }) };
    res.writeHead(r.status, { 'content-type': 'application/json' });
    res.end(JSON.stringify(r.body));
  });
});

function toolReply(input) {
  return { content: [{ type: 'tool_use', name: 'record_sheet', input }],
           usage: { input_tokens: 1200, output_tokens: 80 } };
}

/* --- 우리 서버 두드리기 -------------------------------------------------- */
async function call(m, p, body, tok) {
  const r = await fetch(B + p, {
    method: m,
    headers: { 'content-type': 'application/json', ...(tok ? { authorization: 'Bearer ' + tok } : {}) },
    body: body ? JSON.stringify(body) : undefined
  });
  return { status: r.status, json: await r.json().catch(() => ({})) };
}

const IMG = Buffer.alloc(3000, 0x41).toString('base64');   // 내용은 상관없습니다
function shot(over) { return Object.assign({ mediaType: 'image/jpeg', data: IMG }, over); }

async function waitUp(port, ms = 5000) {
  const until = Date.now() + ms;
  while (Date.now() < until) {
    try { if ((await fetch(`http://localhost:${port}/health`)).ok) return true; } catch {}
    await new Promise(r => setTimeout(r, 100));
  }
  throw new Error('서버가 뜨지 않습니다: ' + port);
}

/* --- 서버 두 판: 키 있는 것 / 없는 것 ------------------------------------ */
function boot(env) {
  return spawn(process.execPath, [path.join(__dirname, '..', 'server', 'server.js')], {
    env: { ...process.env, PORT: String(PORT), DB, PAIR_SECRET: PAIR, ...env },
    stdio: 'ignore'
  });
}

let srv = null;
function stop() { if (srv) { srv.kill(); srv = null; } }

async function main() {
  /* ===== 1. 키가 없는 서버 ============================================== */
  console.log('\n[0] 모델 비교 도구 — 사진 크기와 값 계산');
  {
    const C = require('./ocr-compare.js');

    /* 크기를 헤더에서 직접 읽습니다. 앱은 긴 변 1600 으로 줄여 보내므로,
       그보다 큰 사진으로 비교하면 값도 더 나오고 더 잘 읽힙니다 —
       둘 다 실제보다 좋게 보입니다. 그래서 크기를 알아야 합니다. */
    const png = Buffer.alloc(24);
    png.writeUInt32BE(0x89504e47, 0); png.write('IHDR', 12);
    png.writeUInt32BE(1131, 16); png.writeUInt32BE(1600, 20);
    const d1 = C.dimensions(png);
    ok('PNG 크기를 읽는다', d1 && d1.w === 1131 && d1.h === 1600, d1);

    const jpg = Buffer.from([
      0xFF, 0xD8,                                  // SOI
      0xFF, 0xE0, 0x00, 0x04, 0x00, 0x00,          // APP0 (길이 4)
      0xFF, 0xC0, 0x00, 0x11, 0x08,                // SOF0, 길이 17, 정밀도 8
      0x06, 0x40,                                  // 높이 1600
      0x04, 0x6B                                   // 너비 1131
    ]);
    const d2 = C.dimensions(jpg);
    ok('JPEG 크기를 읽는다', d2 && d2.w === 1131 && d2.h === 1600, d2);
    ok('JPEG 로 알아본다', C.mediaTypeOf('x.jpg', jpg) === 'image/jpeg');
    ok('PNG 로 알아본다', C.mediaTypeOf('x.png', png) === 'image/png');
    ok('모르는 것은 빈 값', C.mediaTypeOf('x.txt', Buffer.from('hello')) === '');

    /* 값은 추정이 아니라 앤트로픽이 돌려준 토큰 수로 계산합니다.
       공시가 기준(2026-09-21): Opus 5 $5/$25, Haiku 4.5 $1/$5 per MTok. */
    const u = { in: 4000, out: 200 };
    const opus = C.costOf('claude-opus-5', u);
    const haiku = C.costOf('claude-haiku-4-5-20251001', u);
    ok('Opus 값이 맞는다', Math.abs(opus - (4000 * 5 / 1e6 + 200 * 25 / 1e6)) < 1e-9, opus);
    ok('Haiku 값이 맞는다', Math.abs(haiku - (4000 * 1 / 1e6 + 200 * 5 / 1e6)) < 1e-9, haiku);
    ok('Haiku 가 Opus 보다 싸다', haiku < opus, [haiku, opus]);
    ok('모르는 모델은 값을 지어내지 않는다', C.costOf('claude-made-up', u) === null);
    ok('토큰 수를 모르면 값도 없다', C.costOf('claude-opus-5', null) === null);
  }

  console.log('\n[1] 판독 키가 없는 서버 — 0층은 그대로 남아야 한다');
  srv = boot({});
  await waitUp(PORT);
  const u = await call('POST', '/auth/signup',
    { handle: 'owner', displayName: '주인', password: PW, pairSecret: PAIR,
      healthConsent: '2026-09-22' });
  const tok = u.json.token;
  ok('가입됨', !!tok, u.json);

  const noKey = await call('POST', '/ocr', shot(), tok);
  ok('키가 없으면 503', noKey.status === 503, noKey);
  ok('왜인지 말해 준다', /판독 키/.test(noKey.json.reason || ''), noKey.json);
  stop();

  /* ===== 2. 키가 있는 서버 ============================================== */
  console.log('\n[2] 로그인 · 입력 검사');
  /* 한도를 **명시**합니다.
     예전에는 안 적었습니다. 그래서 서버의 기본 한도를 사람 수에 맞춰
     40 → 10 으로 내린 순간, 오류 종류를 하나씩 확인하는 아래 [6] 절이
     11번째부터 전부 "오늘 판독 한도를 다 썼습니다" 로 바뀌었습니다.
     시험이 확인하려던 것과 아무 상관 없는 이유로 빨개진 것입니다.
     시험은 자기가 기대는 값을 스스로 세워야 합니다 — 기본값이 바뀌는
     것은 제품의 자유이고, 그때마다 시험이 깨지면 기본값을 못 고칩니다. */
  srv = boot({ ANTHROPIC_API_KEY: 'test-key', OCR_PER_DAY: '500', OCR_PER_DAY_TOTAL: '500',
               OCR_API_URL: `http://localhost:${FAKE_PORT}/v1/messages` });
  await waitUp(PORT);
  const u2 = await call('POST', '/auth/signin', { handle: 'owner', password: PW });
  const t = u2.json.token;
  ok('로그인됨', !!t);

  ok('토큰 없으면 401', (await call('POST', '/ocr', shot())).status === 401);
  ok('사진이 아니면 400',
     (await call('POST', '/ocr', shot({ mediaType: 'application/pdf' }), t)).status === 400);
  ok('빈 사진이면 400',
     (await call('POST', '/ocr', shot({ data: 'AAAA' }), t)).status === 400);
  ok('base64 가 아니면 400',
     (await call('POST', '/ocr', shot({ data: '<<<< 이건 base64 가 아닙니다 >>>>'.repeat(20) }), t)).status === 400);

  console.log('\n[3] 잘 읽었을 때');
  nextReply = { status: 200, body: toolReply({
    notInBody: false, measuredAt: '2026-09-19T11:09:00',
    weightKg: 86.7, smmKg: 37.9, bfmKg: 20.0, pbfPct: 23.1, ffmKg: 66.7,
    bmi: 26.5, tbwL: 48.7, proteinKg: 13.3, mineralKg: 4.7, bmrKcal: 1811,
    whr: 0.90, inbodyScore: 76, visceralFatLevel: 9, device: 'InBody270'
  }) };
  const good = await call('POST', '/ocr', shot(), t);
  ok('200 으로 돌아온다', good.status === 200, good);
  ok('핵심 3종이 들어 있다',
     good.json.fields.weightKg === 86.7 && good.json.fields.smmKg === 37.9 &&
     good.json.fields.bfmKg === 20.0, good.json.fields);
  ok('측정일시가 ISO 로 정리된다', /^2026-09-19T/.test(good.json.fields.measuredAt || ''),
     good.json.fields.measuredAt);
  ok('기기 이름이 넘어온다', good.json.fields.device === 'InBody270');
  ok('사진이 실제로 실려 나갔다',
     !!(lastRequest && lastRequest.messages[0].content[0].type === 'image'));
  ok('도구를 강제한다 (산문 응답이 올 자리가 없다)',
     lastRequest && lastRequest.tool_choice && lastRequest.tool_choice.type === 'tool');

  console.log('\n[4] 모델이 헛소리를 할 때 — 앱까지 들고 가지 않는다');
  nextReply = { status: 200, body: toolReply({
    notInBody: false,
    weightKg: 867,          // 자릿수 오독
    smmKg: 37.9,
    bfmKg: -3,              // 음수
    pbfPct: 'twenty',       // 숫자가 아님
    bmi: null,
    bmrKcal: 1811,
    measuredAt: '2099-01-01T00:00:00',   // 미래
    device: '<script>alert(1)</script>'
  }) };
  const junk = await call('POST', '/ocr', shot(), t);
  ok('범위 밖 체중은 버린다', junk.json.fields.weightKg === undefined, junk.json.fields);
  ok('음수 체지방은 버린다', junk.json.fields.bfmKg === undefined);
  ok('숫자가 아닌 값은 버린다', junk.json.fields.pbfPct === undefined);
  ok('미래 측정일은 버린다', junk.json.fields.measuredAt === undefined);
  ok('기기 이름에서 태그를 걷어낸다',
     !/[<>]/.test(junk.json.fields.device || ''), junk.json.fields.device);
  ok('멀쩡한 값은 남긴다', junk.json.fields.smmKg === 37.9 && junk.json.fields.bmrKcal === 1811);

  console.log('\n[5] 인바디가 아닌 사진');
  nextReply = { status: 200, body: toolReply({ notInBody: true }) };
  const notIn = await call('POST', '/ocr', shot(), t);
  ok('200 이되 빈 결과', notIn.status === 200 && Object.keys(notIn.json.fields).length === 0);
  ok('이유를 말해 준다', /인바디/.test(notIn.json.reason || ''), notIn.json);

  console.log('\n[6] 모델 쪽이 실패했을 때');
  nextReply = { status: 429, body: { error: { type: 'rate_limit_error' } } };
  const busy = await call('POST', '/ocr', shot(), t);
  ok('429 는 429 로 전한다', busy.status === 429, busy);
  ok('내부 사정을 응답에 안 싣는다',
     !/rate_limit_error|api\.anthropic|test-key/.test(JSON.stringify(busy.json)), busy.json);

  nextReply = { status: 500, body: { error: { type: 'internal' } } };
  const broke = await call('POST', '/ocr', shot(), t);
  ok('500 은 502 로 전한다', broke.status === 502, broke);

  nextReply = { status: 200, body: { content: [{ type: 'text', text: '음... 잘 모르겠어요' }] } };
  const prose = await call('POST', '/ocr', shot(), t);
  ok('도구를 안 쓴 응답은 502', prose.status === 502, prose);

  /* 502 를 전부 "판독에 실패했습니다" 로 뭉개면 **주인이 할 일을 알 수
     없습니다.** 잔액이 없는 것 · 그 모델 권한이 없는 것 · 모델 이름이
     틀린 것이 같은 문장으로 나왔고, 셋의 할 일은 전부 다릅니다.
     주인이 실제로 502 를 받고 무엇을 해야 하는지 물었습니다. */
  nextReply = { status: 400, body: { error: { type: 'invalid_request_error',
    message: 'Your credit balance is too low to access the Anthropic API.' } } };
  const broke2 = await call('POST', '/ocr', shot(), t);
  ok('잔액 문제면 그렇다고 말한다',
     /돈이 없거나 결제/.test(JSON.stringify(broke2.json)), broke2.json);
  /* 어느 주소를 대는지까지 봅니다. "돈 문제입니다" 만 말하고 어디로
     가라는 말이 없으면 주인은 검색부터 해야 합니다.
     주소는 **도메인까지만** 댑니다 — 콘솔의 결제 페이지 경로는 문서에서
     확인하지 못했고, 확인 못 한 경로를 적어 두면 틀렸을 때 그게 더
     오래 걸립니다. 키·워크스페이스 경로는 문서에 있어서 따로 댑니다. */
  ok('확인할 곳까지 알려준다',
     /platform\.claude\.com/.test(JSON.stringify(broke2.json)), broke2.json);
  {
    /* 앤트로픽이 문구를 바꿔도 걸려야 합니다. "credit balance is too low"
       한 문장에만 맞춰 두면 그 문장이 바뀌는 날 다시 "판독에 실패했습니다"
       로 돌아갑니다. */
    nextReply = { status: 400, body: { error: { type: 'invalid_request_error',
      message: 'This organization has insufficient funds. Add a payment method.' } } };
    const other = await call('POST', '/ocr', shot(), t);
    ok('문구가 달라도 잔액 문제로 알아본다',
       /돈이 없거나 결제/.test(JSON.stringify(other.json)), other.json);
  }

  nextReply = { status: 404, body: { error: { type: 'not_found_error', message: 'model: nope' } } };
  const noModel = await call('POST', '/ocr', shot(), t);
  ok('모델 이름이 틀리면 그렇다고 말한다',
     /모델 이름/.test(JSON.stringify(noModel.json)), noModel.json);

  /* 판독 키가 거부됐을 때 **우리가 401 을 돌려주면 안 됩니다.**
   *
   * 앱의 api() 는 401 을 보면 "내 로그인 토큰이 죽었다" 로 읽고 조용히
   * 로그아웃합니다. 그런데 여기 401 은 **서버의 판독 키** 이야기지
   * 사용자 토큰 이야기가 아닙니다. 그대로 흘려보내면, 결과지 사진을
   * 한 장 올렸다가 로그아웃되고 친구 목록이 사라집니다 — 원인과
   * 증상이 아무 상관 없어 보여서 영영 못 찾습니다.
   * 주인의 키가 실제로 거부된 상태였으므로, 이 길은 지나간 길입니다. */
  nextReply = { status: 401, body: { error: { type: 'authentication_error',
    message: 'invalid x-api-key' } } };
  const keyBad = await call('POST', '/ocr', shot(), t);
  ok('판독 키가 거부돼도 401 을 그대로 흘리지 않는다', keyBad.status !== 401, keyBad.status);
  ok('키가 거부됐다고 말한다',
     /키가 거부되었습니다/.test(JSON.stringify(keyBad.json)), keyBad.json);
  {
    /* 그리고 실제로 로그아웃되지 않는지 — 같은 토큰이 계속 통해야 합니다. */
    const after = await call('GET', '/me', null, t);
    ok('그 뒤에도 로그인이 살아 있다', after.status === 200, after.status);
  }

  /* 조직 전체 키(워크스페이스에 안 묶인 키)로 부르면 400 이 옵니다.
     주인이 실제로 여기서 막혔습니다 — 그때 "판독 요청이 거절되었습니다"
     만 나오면 무엇을 해야 하는지 알 수가 없습니다. */
  nextReply = { status: 400, body: { error: { type: 'invalid_request_error',
    message: 'This API key is not scoped to a workspace, so this request must include ' +
             'the anthropic-workspace-id header with the ID of the workspace to use.' } } };
  const noWs = await call('POST', '/ocr', shot(), t);
  ok('워크스페이스에 안 묶인 키면 그렇다고 말한다',
     /워크스페이스에 묶여 있지 않습니다/.test(JSON.stringify(noWs.json)), noWs.json);
  ok('무엇을 하면 되는지까지 말한다',
     /workspaces\.js/.test(JSON.stringify(noWs.json)), noWs.json);

  /* 워크스페이스 오류는 **세 갈래**이고 할 일이 전부 다릅니다.
     하나로 뭉쳐 놓으면 번호를 잘못 넣은 사람이 키를 새로 만들러 갑니다.

     특히 404 는 위험했습니다 — 예전 코드는 not_found_error 를 전부
     "판독 모델 이름을 못 찾았습니다 — OCR_MODEL 값을 확인하세요" 로
     보냈습니다. 워크스페이스 번호에 오타가 났을 뿐인데 멀쩡한 모델
     이름을 들여다보게 만드는 안내입니다. */
  nextReply = { status: 400, body: { error: { type: 'invalid_request_error',
    message: 'anthropic-workspace-id header must be a valid workspace ID.' } } };
  const badWs = await call('POST', '/ocr', shot(), t);
  ok('워크스페이스 값의 형식이 틀리면 형식을 말한다',
     /형식이 틀렸습니다/.test(JSON.stringify(badWs.json)), badWs.json);
  ok('형식 오류를 "키를 새로 만들라" 로 보내지 않는다',
     !/키를 새로|묶여 있지 않습니다/.test(JSON.stringify(badWs.json)), badWs.json);

  nextReply = { status: 404, body: { error: { type: 'not_found_error',
    message: 'Workspace `wrkspc_01ZZZ` not found.' } } };
  const goneWs = await call('POST', '/ocr', shot(), t);
  ok('없는 워크스페이스면 워크스페이스를 가리킨다',
     /워크스페이스를 찾지 못했습니다/.test(JSON.stringify(goneWs.json)), goneWs.json);
  ok('없는 워크스페이스를 OCR_MODEL 탓으로 돌리지 않는다',
     !/OCR_MODEL/.test(JSON.stringify(goneWs.json)), goneWs.json);

  /* 반대로 **진짜** 모델 404 는 여전히 모델을 가리켜야 합니다.
     위 갈래를 넓게 잡다가 이쪽을 삼키면 고친 게 아니라 옮긴 것입니다. */
  nextReply = { status: 404, body: { error: { type: 'not_found_error',
    message: 'model: claude-does-not-exist' } } };
  const noModel2 = await call('POST', '/ocr', shot(), t);
  ok('진짜 모델 404 는 아직 모델을 가리킨다',
     /OCR_MODEL/.test(JSON.stringify(noModel2.json)), noModel2.json);

  /* 워크스페이스 월 한도와 조직 잔액은 갈 곳이 다릅니다.
     한도는 그 워크스페이스의 Spend limits, 잔액은 결제. */
  nextReply = { status: 400, body: { error: { type: 'invalid_request_error',
    message: 'This workspace has reached its monthly spend limit.' } } };
  const capped = await call('POST', '/ocr', shot(), t);
  ok('워크스페이스 지출 한도면 한도를 가리킨다',
     /지출 한도에 닿았습니다/.test(JSON.stringify(capped.json)), capped.json);

  /* 조직 한도와 워크스페이스 한도는 갈 화면이 다릅니다. 조직 한도를
     "워크스페이스를 보세요" 로 보내면, 기본 워크스페이스만 있는 사람은
     열 화면조차 없습니다 — 기본 워크스페이스에는 한도 탭이 없습니다. */
  nextReply = { status: 400, body: { error: { type: 'invalid_request_error',
    message: 'Your organization has reached its monthly spend limit.' } } };
  const orgCap = await call('POST', '/ocr', shot(), t);
  ok('조직 지출 한도는 워크스페이스로 보내지 않는다',
     !/Settings > Workspaces/.test(JSON.stringify(orgCap.json)), orgCap.json);
  ok('조직 지출 한도라고 말한다',
     /계정의 월 지출 한도/.test(JSON.stringify(orgCap.json)), orgCap.json);

  /* 요금제가 자동으로 거는 상한은 429 로 오고 retry-after 가 없습니다.
     "잠시 뒤에 다시" 라고 하면 영영 다시 하게 됩니다. 구분자는
     상태코드가 아니라 details.error_code 입니다. */
  nextReply = { status: 429, body: { error: { type: 'rate_limit_error',
    message: 'You have reached your monthly spend limit.',
    details: { error_code: 'enforced_spend_limit_reached' } } } };
  const hardCap = await call('POST', '/ocr', shot(), t);
  ok('월 상한 429 는 기다리라고 하지 않는다',
     !/잠시 뒤에/.test(JSON.stringify(hardCap.json)), hardCap.json);
  ok('기다려도 안 풀린다고 말한다',
     /기다려도 안 풀립니다/.test(JSON.stringify(hardCap.json)), hardCap.json);

  /* 반대로 **진짜** 429(잠깐 밀린 것)는 기다리라고 해야 맞습니다. */
  nextReply = { status: 429, body: { error: { type: 'rate_limit_error',
    message: 'Number of requests has exceeded your rate limit.' } } };
  const busy2 = await call('POST', '/ocr', shot(), t);
  ok('진짜 혼잡은 아직 기다리라고 한다',
     /잠시 뒤에/.test(JSON.stringify(busy2.json)), busy2.json);

  nextReply = { status: 400, body: { error: { type: 'invalid_request_error',
    message: 'Your credit balance is too low to access the API.' } } };
  const broke3 = await call('POST', '/ocr', shot(), t);
  ok('조직 잔액이면 결제를 가리킨다',
     /돈이 없거나/.test(JSON.stringify(broke3.json)), broke3.json);

  nextReply = { status: 403, body: { error: { type: 'permission_error', message: 'x' } } };
  const noPerm = await call('POST', '/ocr', shot(), t);
  ok('그 모델을 못 쓰면 그렇다고 말한다',
     /쓸 수 없습니다/.test(JSON.stringify(noPerm.json)), noPerm.json);
  ok('그래도 내부 사정은 안 싣는다',
     !/api\.anthropic|test-key|not_found_error|permission_error/.test(
       JSON.stringify([broke2.json, noModel.json, noPerm.json])),
     [broke2.json, noModel.json, noPerm.json]);

  console.log('\n[7] 큰 사진 — 끊지 말고 413 을 돌려준다');
  /* 예전 readBody 는 한도를 넘으면 req.destroy() 를 불렀습니다. 그러면
     브라우저에 뜨는 것은 413 이 아니라 "Failed to fetch" 이고, 그건
     서버가 죽은 것과 구분이 안 됩니다. */
  nextReply = null;
  const big = 'A'.repeat(9 * 1024 * 1024);
  let bigRes = null, bigErr = null;
  try { bigRes = await call('POST', '/ocr', shot({ data: big }), t); }
  catch (e) { bigErr = String(e); }
  ok('연결이 끊기지 않는다', !bigErr, bigErr);
  ok('413 으로 돌려준다', bigRes && bigRes.status === 413, bigRes && bigRes.status);

  console.log('\n[8] 하루 횟수 제한');
  /* 사진 한 장이 돈이 드는 요청이라, 버그로 같은 요청이 반복돼도
     청구서가 터지지 않게 막혀 있어야 합니다. */
  stop();
  /* 한도가 이제 **DB 에 남습니다.** 그래서 앞 절들이 쓴 횟수가 여기까지
     따라옵니다 — 특히 서버 전체 한도(기본이 사람당 한도의 5배)는 앞에서
     이미 다 차 있습니다. 한도 자체를 보는 절이니 자기 DB 를 씁니다. */
  const DB8 = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'mybody-ocr8-')), 'day.db');
  srv = boot({ ANTHROPIC_API_KEY: 'test-key', OCR_PER_DAY: '3', DB: DB8,
               OCR_API_URL: `http://localhost:${FAKE_PORT}/v1/messages` });
  await waitUp(PORT);
  /* **새 계정으로 셉니다.**
     한도가 이제 DB 에 남으므로, 앞 절에서 판독을 쓴 'owner' 로 세면
     이 절이 시작하기도 전에 한도를 넘어 있습니다. 한도가 껐다 켜도
     살아남는다는 것이 바로 이 검사가 방금 확인한 것이고요. */
  const dayUser = 'daycap' + Date.now().toString(36).slice(-5);
  const t3 = (await call('POST', '/auth/signup',
    { handle: dayUser, displayName: '한도', password: PW, pairSecret: PAIR,
      healthConsent: '2026-09-22' })).json.token;
  nextReply = { status: 200, body: toolReply({ notInBody: false, weightKg: 86.7 }) };
  const codes = [];
  for (let i = 0; i < 5; i++) codes.push((await call('POST', '/ocr', shot(), t3)).status);
  ok('세 번까지는 통과', codes.slice(0, 3).every(c => c === 200), codes);
  ok('네 번째부터 429', codes.slice(3).every(c => c === 429), codes);

  /* **껐다 켜도 한도가 그대로여야 합니다.**
   *
   * 예전에는 이 숫자가 메모리에만 있어서 서버를 다시 띄우면 0 으로
   * 돌아갔습니다. 개발 중에는 하루에도 여러 번 껐다 켜므로 사실상
   * 한도가 없는 것과 같았고, 가입까지 열려 있으면 주소를 아는 사람이
   * 계정을 만들어 판독을 태울 수 있습니다. 판독 한 장은 수십 원입니다.
   * 취향이 아니라 지갑 문제라 검사로 못 박습니다. */
  stop();
  srv = boot({ ANTHROPIC_API_KEY: 'test-key', OCR_PER_DAY: '3', DB: DB8,
               OCR_API_URL: `http://localhost:${FAKE_PORT}/v1/messages` });
  await waitUp(PORT);
  const t3b = (await call('POST', '/auth/signin', { handle: dayUser, password: PW })).json.token;
  nextReply = { status: 200, body: toolReply({ notInBody: false, weightKg: 86.7 }) };
  const afterRestart = (await call('POST', '/ocr', shot(), t3b)).status;
  ok('서버를 껐다 켜도 한도가 살아 있다', afterRestart === 429, afterRestart);
  stop();

  console.log('\n[8-3] 실패한 판독은 한도를 안 깎는다');
  {
    /* 이것 때문에 진단이 한 바퀴 더 돌 뻔했습니다.
       예전에는 한도 확인과 횟수 올리기가 한 함수였습니다. 그래서 키가
       거부되거나 워크스페이스가 안 잡힌 날, 될 때까지 눌러 본 횟수가
       그대로 한도를 깎았습니다. 열 번이면 그날이 끝나고, 그 다음부터
       화면은 **진짜 원인 대신** "오늘 판독 한도를 다 썼습니다" 를
       말합니다 — 고치는 사람이 원인을 찾는 동안 원인이 가려집니다.
       거절된 요청은 토큰을 안 써서 돈도 안 나갑니다. 셀 이유가 없습니다. */
    const DBf = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'mybody-ocrf-')), 'f.db');
    stop();
    srv = boot({ ANTHROPIC_API_KEY: 'test-key', OCR_PER_DAY: '2', OCR_PER_DAY_TOTAL: '50',
                 DB: DBf, OCR_API_URL: `http://localhost:${FAKE_PORT}/v1/messages` });
    await waitUp(PORT);
    const u = 'failcap' + Date.now().toString(36).slice(-5);
    const tk = (await call('POST', '/auth/signup',
      { handle: u, displayName: '실패', password: PW, pairSecret: PAIR,
        healthConsent: '2026-09-22' })).json.token;

    // 키가 거부되는 상황을 다섯 번 겪습니다 (사람이 될 때까지 눌러 보는 모습)
    nextReply = { status: 401, body: { error: { type: 'authentication_error', message: 'invalid x-api-key' } } };
    const failed = [];
    for (let i = 0; i < 5; i++) failed.push((await call('POST', '/ocr', shot(), tk)).status);
    ok('다섯 번 다 실패한다', failed.every(c => c !== 200), failed);
    ok('그 실패가 429 로 바뀌지 않는다', !failed.includes(429), failed);

    // 이제 키를 고쳤습니다. 한도 2가 그대로 남아 있어야 합니다.
    nextReply = { status: 200, body: toolReply({ notInBody: false, weightKg: 71.2 }) };
    const after = [];
    for (let i = 0; i < 3; i++) after.push((await call('POST', '/ocr', shot(), tk)).status);
    ok('고친 뒤 두 번은 된다', after.slice(0, 2).every(c => c === 200), after);
    ok('세 번째는 한도에 걸린다', after[2] === 429, after);
  }

  console.log('\n[8-2] 워크스페이스 값을 주면 헤더로 나간다');
  {
    /* 조직 전체 키를 이미 만들어 둔 사람을 위한 길입니다. 값을 설정에
       넣으면 요청 헤더에 실려야 하고, 안 넣으면 안 실려야 합니다 —
       안 쓰는 헤더를 늘 붙이면 그것대로 거절당합니다. */
    stop();
    const DBw = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'mybody-ocrw-')), 'ws.db');
    srv = boot({ ANTHROPIC_API_KEY: 'test-key', DB: DBw,
                 ANTHROPIC_WORKSPACE_ID: 'wrkspc_test_123',
                 OCR_API_URL: `http://localhost:${FAKE_PORT}/v1/messages` });
    await waitUp(PORT);
    const tw = (await call('POST', '/auth/signup',
      { handle: 'wsuser', password: PW, displayName: 'ws', pairSecret: PAIR,
        healthConsent: '2026-09-22' })).json.token;
    nextReply = { status: 200, body: toolReply({ notInBody: false, weightKg: 86.7 }) };
    lastHeaders = null;
    await call('POST', '/ocr', shot(), tw);
    ok('워크스페이스 헤더가 실려 나간다',
       !!lastHeaders && lastHeaders['anthropic-workspace-id'] === 'wrkspc_test_123',
       lastHeaders && lastHeaders['anthropic-workspace-id']);

    stop();
    srv = boot({ ANTHROPIC_API_KEY: 'test-key', DB: DBw,
                 OCR_API_URL: `http://localhost:${FAKE_PORT}/v1/messages` });
    await waitUp(PORT);
    const tw2 = (await call('POST', '/auth/signin',
      { handle: 'wsuser', password: PW })).json.token;
    lastHeaders = null;
    await call('POST', '/ocr', shot(), tw2);
    ok('안 주면 헤더를 안 붙인다',
       !!lastHeaders && !('anthropic-workspace-id' in lastHeaders),
       lastHeaders && Object.keys(lastHeaders).filter(k => /anthropic/.test(k)));
  }

  console.log('\n[9] 서버 전체 한도 — 계정을 늘려도 못 넘는다');
  /* 사람당 한도만 두면 가입 코드를 아는 사람이 계정을 계속 만들어
     한도를 무한정 늘릴 수 있습니다. 청구서는 서버 주인에게 갑니다. */
  /* stop() 이 없었습니다. 앞 절의 서버가 포트를 쥔 채 남아서, 여기서
     띄운 서버는 조용히 죽고 요청은 **앞 절 서버**로 갔습니다 — 이 절이
     세우려던 한도(OCR_PER_DAY_TOTAL=3)가 적용된 적이 없습니다.
     통과하고 있었지만 아무것도 안 보고 있었습니다. */
  stop();
  const DB9 = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'mybody-ocr9-')), 'total.db');
  srv = boot({ ANTHROPIC_API_KEY: 'test-key', OCR_PER_DAY: '2', OCR_PER_DAY_TOTAL: '3',
               DB: DB9, OCR_API_URL: `http://localhost:${FAKE_PORT}/v1/messages` });
  await waitUp(PORT);
  nextReply = { status: 200, body: toolReply({ notInBody: false, weightKg: 86.7 }) };
  const seen = [];
  for (let i = 0; i < 4; i++) {
    const u3 = await call('POST', '/auth/signup',
      { handle: 'many' + i, password: PW, displayName: 'm' + i, pairSecret: PAIR,
        healthConsent: '2026-09-22' });
    const tk = u3.json.token || (await call('POST', '/auth/signin',
      { handle: 'many' + i, password: PW })).json.token;
    seen.push((await call('POST', '/ocr', shot(), tk)).status);
  }
  ok('새 계정으로도 서버 한도를 못 넘는다', seen.includes(429), seen);
  stop();
}

fake.listen(FAKE_PORT);
process.on('exit', () => { stop(); fake.close(); });

main()
  .then(() => {
    console.log(`\n통과 ${pass} / 실패 ${fail}`);
    stop(); fake.close();
    process.exit(fail ? 1 : 0);
  })
  .catch(e => { console.error(e); stop(); fake.close(); process.exit(1); });
