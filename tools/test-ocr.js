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
const fake = http.createServer((req, res) => {
  let body = '';
  req.on('data', c => { body += c; });
  req.on('end', () => {
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
  console.log('\n[1] 판독 키가 없는 서버 — 0층은 그대로 남아야 한다');
  srv = boot({});
  await waitUp(PORT);
  const u = await call('POST', '/auth/signup',
    { handle: 'owner', displayName: '주인', password: PW, pairSecret: PAIR });
  const tok = u.json.token;
  ok('가입됨', !!tok, u.json);

  const noKey = await call('POST', '/ocr', shot(), tok);
  ok('키가 없으면 503', noKey.status === 503, noKey);
  ok('왜인지 말해 준다', /판독 키/.test(noKey.json.reason || ''), noKey.json);
  stop();

  /* ===== 2. 키가 있는 서버 ============================================== */
  console.log('\n[2] 로그인 · 입력 검사');
  srv = boot({ ANTHROPIC_API_KEY: 'test-key',
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
  srv = boot({ ANTHROPIC_API_KEY: 'test-key', OCR_PER_DAY: '3',
               OCR_API_URL: `http://localhost:${FAKE_PORT}/v1/messages` });
  await waitUp(PORT);
  const t3 = (await call('POST', '/auth/signin', { handle: 'owner', password: PW })).json.token;
  nextReply = { status: 200, body: toolReply({ notInBody: false, weightKg: 86.7 }) };
  const codes = [];
  for (let i = 0; i < 5; i++) codes.push((await call('POST', '/ocr', shot(), t3)).status);
  ok('세 번까지는 통과', codes.slice(0, 3).every(c => c === 200), codes);
  ok('네 번째부터 429', codes.slice(3).every(c => c === 429), codes);
  stop();

  console.log('\n[9] 서버 전체 한도 — 계정을 늘려도 못 넘는다');
  /* 사람당 한도만 두면 가입 코드를 아는 사람이 계정을 계속 만들어
     한도를 무한정 늘릴 수 있습니다. 청구서는 서버 주인에게 갑니다. */
  srv = boot({ ANTHROPIC_API_KEY: 'test-key', OCR_PER_DAY: '2', OCR_PER_DAY_TOTAL: '3',
               OCR_API_URL: `http://localhost:${FAKE_PORT}/v1/messages` });
  await waitUp(PORT);
  nextReply = { status: 200, body: toolReply({ notInBody: false, weightKg: 86.7 }) };
  const seen = [];
  for (let i = 0; i < 4; i++) {
    const u3 = await call('POST', '/auth/signup',
      { handle: 'many' + i, password: PW, displayName: 'm' + i, pairSecret: PAIR });
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
