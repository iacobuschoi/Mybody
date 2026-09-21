/* =============================================================================
 * server/ocr.js — 결과지 사진 판독 (2층)
 *
 * 브라우저가 사진을 보내면 여기서 Vision 모델에 넘기고, 돌아온 JSON 을
 * 다듬어서 돌려줍니다.
 *
 * 왜 서버를 거치는가
 *   API 키를 정적 클라이언트에 넣을 수 없습니다. 키는 이 서버의
 *   환경변수에만 있습니다.
 *
 * 왜 규칙 기반 OCR(tesseract 등)이 아닌가
 *   결과지에서 값을 읽는 일의 어려움은 글자를 알아보는 데 있지 않고,
 *   "한 줄에 있는 일곱 개의 숫자 중 어느 것이 값인가" 를 아는 데
 *   있습니다. 실제 줄이 이렇게 생겼습니다:
 *
 *     골격근량  28.1 kg   | 55  70  85  100  115  130 |
 *
 *   28.1 이 값이고 나머지는 막대그래프의 눈금입니다. 글자만 읽는
 *   엔진은 이 둘을 구분할 방법이 없습니다. 레이아웃을 이해하는 모델은
 *   구분합니다.
 *
 * 돌려주는 값은 초안입니다
 *   앱은 이 값을 그대로 저장하지 않습니다. crosscheck.js 가 결과지
 *   안에서 검산하고, 사람이 검수 화면에서 확정합니다. 여기서는 사람의
 *   값이 아닌 것(범위 밖, 숫자가 아닌 것)만 걸러서 버립니다.
 * ========================================================================== */
'use strict';

/* 기본은 앤트로픽 API 입니다. 자가호스팅하는 사람이 사내 프록시를
   거쳐야 하는 경우와, 시험에서 가짜 서버를 물릴 때를 위해 바꿀 수
   있게 열어 둡니다. */
const API_URL = process.env.OCR_API_URL || 'https://api.anthropic.com/v1/messages';
const API_VERSION = '2023-06-01';

/* 어떤 모델로 읽을 것인가.
 *
 * 기본은 제일 잘 읽는 것입니다 — 결과지 한 장이 몇 달치 기록의 출발점이라
 * 여기서 잘못 읽으면 그 뒤가 전부 어긋납니다. 대신 값이 비쌉니다.
 * 계정에 그 모델 권한이 없거나 더 싼 것으로 충분하면 바꿀 수 있게 둡니다:
 *
 *   OCR_MODEL=claude-sonnet-5 node tools/serve.js
 *
 * 한 장(1135×1600 결과지)에 드는 값은 대략 이렇습니다 — 입력 3천 토큰 ·
 * 출력 3백 토큰 기준, 2026년 9월 공시가:
 *   claude-opus-5    $5/$25 per M  →  약 $0.024  (35원쯤)
 *   claude-sonnet-5  $2/$10 per M  →  약 $0.010  (14원쯤)
 *   claude-haiku-4-5 $1/$5  per M  →  약 $0.005  (7원쯤)
 * 환율은 대략값입니다. 서버는 하루 횟수(OCR_PER_DAY)로 한 번 더 막습니다. */
const DEFAULT_MODEL = process.env.OCR_MODEL || 'claude-opus-5';

/* 워크스페이스에 묶이지 않은 키를 쓸 때 필요한 값.
 *
 * 앤트로픽 콘솔에서 **조직 전체** 키를 만들면 어느 워크스페이스에서
 * 쓸지를 요청마다 말해 줘야 합니다. 안 보내면 400 입니다:
 *   "This API key is not scoped to a workspace, so this request must
 *    include the anthropic-workspace-id header..."
 * 주인이 실제로 여기서 막혔습니다.
 *
 * 더 나은 길은 **워크스페이스 안에서 키를 만드는 것**입니다 — 그러면
 * 이 값이 아예 필요 없고, 거기에만 월 지출 한도를 걸 수 있습니다
 * (기본 워크스페이스에는 한도를 못 겁니다). 그래도 이미 만든 키를
 * 쓰고 싶은 사람을 위해 열어 둡니다. */
const WORKSPACE = (process.env.ANTHROPIC_WORKSPACE_ID || '').trim();

function authHeaders(apiKey, workspace) {
  const h = { 'x-api-key': apiKey, 'anthropic-version': API_VERSION };
  /* 다듬어서 싣습니다. 설정 파일에 공백이 섞여 들어오는 길이 여럿이고
     (붙여넣기, --workspace=" ... "), 공백 하나 때문에 400 이 오면
     화면에 보이지 않는 것을 의심해야 합니다. 여기서 한 번 막습니다. */
  const w = String(workspace === undefined ? WORKSPACE : (workspace || '')).trim();
  if (w) h['anthropic-workspace-id'] = w;
  return h;
}

/* 앤트로픽이 돌려주는 오류 종류를 사람 말로 옮깁니다.
 *
 * 예전에는 401 · 429 가 아니면 전부 "판독에 실패했습니다" 였습니다.
 * 그 말로는 **주인이 할 일을 알 수 없습니다** — 잔액이 없는 것과,
 * 그 모델 권한이 없는 것과, 사진이 큰 것이 같은 문장으로 나왔습니다.
 * 실제로 주인이 502 를 받고 무엇을 해야 할지 물었습니다.
 *
 * 키나 내부 주소가 새면 안 되므로 앤트로픽의 원문을 그대로 싣지는
 * 않습니다. 종류(type)만 보고 우리가 쓴 문장을 돌려줍니다. 잔액 문제는
 * 종류가 invalid_request_error 하나로 뭉뚱그려져 오기 때문에, 그때만
 * 원문에서 정해진 표식을 찾아봅니다. */
/* 워크스페이스 때문에 나는 오류는 **세 갈래**이고, 할 일이 전부 다릅니다.
   한 문장으로 뭉치면 주인이 엉뚱한 데를 고칩니다. 실제로 그럴 뻔했습니다 —
   워크스페이스 번호를 잘못 넣으면 404 가 오는데, 그건 여기 손대기 전까지
   "판독 모델 이름을 못 찾았습니다 — OCR_MODEL 값을 확인하세요" 로 나갔습니다.
   모델은 멀쩡한데 모델을 보라고 한 셈입니다.

   앤트로픽 문서(platform.claude.com/docs/en/manage-claude/authentication,
   "Select a workspace")가 세 경우를 이렇게 적어 둡니다:
     · 헤더를 안 보냄        → 400 invalid_request_error
     · 값의 형식이 틀림      → 400 "anthropic-workspace-id header must be
                                a valid workspace ID."
     · 없거나 권한이 없음    → 404 not_found_error "Workspace `<id>` not found."
   문구는 바뀔 수 있으므로 넓게 봅니다. */
function workspaceTrouble(status, msg) {
  if (/must be a valid workspace id/i.test(msg)) {
    return '서버에 넣어 둔 워크스페이스 번호의 형식이 틀렸습니다 — ' +
           'wrkspc_ 로 시작하는 값이어야 합니다. node tools/workspaces.js 로 ' +
           '쓸 수 있는 번호를 확인하세요';
  }
  if (status === 404 && /workspace/i.test(msg)) {
    return '그 워크스페이스를 찾지 못했습니다 — 없거나, 이 키로는 들어갈 수 ' +
           '없습니다. node tools/workspaces.js 로 쓸 수 있는 목록을 보세요';
  }
  if (/not scoped to a workspace|anthropic-workspace-id/i.test(msg)) {
    return '판독 키가 워크스페이스에 묶여 있지 않습니다 — ' +
           'node tools/workspaces.js 로 워크스페이스 번호를 넣거나, ' +
           '콘솔 Settings > API keys 에서 워크스페이스를 지정해 키를 새로 만드세요';
  }
  return null;
}

function explain(status, err) {
  const type = (err && err.type) || '';
  const msg = String((err && err.message) || '');

  /* 워크스페이스를 **먼저** 봅니다. 아래 잔액 검사가 넓은 그물이라,
     워크스페이스 한도 문구가 거기 먼저 걸리면 엉뚱한 안내가 나갑니다. */
  const ws = workspaceTrouble(status, msg);
  if (ws) return ws;

  /* 요금제가 자동으로 거는 월 상한은 **429** 로 옵니다. 그리고
     retry-after 가 안 옵니다 — 기다려도 안 풀립니다. 아래 429 갈래의
     "잠시 뒤에 다시 해 주세요" 로 보내면 주인은 영영 다시 하게 됩니다.
     구분자는 상태코드가 아니라 details.error_code 입니다. */
  const code = String((err && err.details && err.details.error_code) || '');
  if (code === 'enforced_spend_limit_reached') {
    return '이 계정의 월 사용 한도에 닿았습니다 — 기다려도 안 풀립니다. ' +
           '콘솔(platform.claude.com)의 결제에서 한도를 확인하세요';
  }

  /* 잔액 문제는 종류가 invalid_request_error 하나로 뭉뚱그려져 오므로
     문장에서 찾습니다. 앤트로픽이 문구를 바꿔도 걸리게 넓게 봅니다 —
     이 한 줄이 "무엇을 해야 하는지" 를 아는 유일한 단서입니다. */
  if (/credit|balance|billing|quota|funds|payment|spend limit/i.test(msg)) {
    /* 갈 곳이 셋입니다. 워크스페이스 한도는 그 워크스페이스의 Spend
       limits 탭, 조직 한도는 결제 화면의 한도, 잔액은 결제 자체입니다.
       셋을 뭉치면 못 고치는 화면을 열게 됩니다 — 특히 조직 한도를
       "워크스페이스를 보세요" 로 보내면, 기본 워크스페이스만 있는
       사람에게는 열 화면조차 없습니다. */
    if (/workspace/i.test(msg)) {
      return '워크스페이스의 월 지출 한도에 닿았습니다 — 콘솔의 ' +
             'Settings > Workspaces 에서 그 워크스페이스의 Spend limits 를 보세요';
    }
    if (/spend limit/i.test(msg)) {
      return '이 계정의 월 지출 한도에 닿았습니다 — ' +
             '콘솔(platform.claude.com)의 결제에서 한도를 올리세요';
    }
    return '판독 계정에 돈이 없거나 결제에 문제가 있습니다 — ' +
           '콘솔(platform.claude.com)에서 결제 상태를 확인하세요';
  }
  switch (type) {
    case 'authentication_error':
      /* 키에는 이제 유효기간이 있습니다 (만들 때 3시간·1일·7일·30일·Never
         중에서 고릅니다). 지난 키는 401 로 돌아오고, 다시 살릴 수 없습니다 —
         "지워졌거나 틀렸습니다" 만 말하면 멀쩡히 넣어 둔 키를 의심하게 됩니다. */
      return '이 서버의 판독 키가 거부되었습니다 — 지워졌거나, 틀렸거나, ' +
             '유효기간이 지났습니다';
    case 'permission_error':
      return '이 키로는 그 판독 모델을 쓸 수 없습니다 (OCR_MODEL 로 바꿀 수 있습니다)';
    case 'not_found_error':
      return '판독 모델 이름을 못 찾았습니다 — 서버의 OCR_MODEL 값을 확인하세요';
    case 'rate_limit_error':
      return '판독 서비스가 바쁩니다. 잠시 뒤에 다시 해 주세요';
    case 'overloaded_error':
      return '판독 서비스가 지금 밀려 있습니다. 잠시 뒤에 다시 해 주세요';
    case 'invalid_request_error':
      /* 이 한 종류 안에 "무엇을 해야 하는지" 가 전혀 다른 것들이 섞여
         옵니다. 알아볼 수 있는 것은 위에서 이미 알아봤습니다. */
      return '판독 요청이 거절되었습니다 — 서버 화면의 [ocr] 줄을 보세요';
    case 'api_error':
      return '판독 서비스 쪽 오류입니다. 잠시 뒤에 다시 해 주세요';
    default:
      return '판독에 실패했습니다 (' + (status || '?') + ') — 서버 화면의 [ocr] 줄을 보세요';
  }
}


/**
 * 키가 살아 있고 그 모델을 쓸 수 있는가. 판독을 돌리기 전에 확인합니다.
 * 모델 조회는 토큰을 안 씁니다 — 돈이 안 듭니다.
 * @returns {Promise<{ok:boolean, reason:string}>}
 */
async function checkKey(apiKey, model, opts) {
  opts = opts || {};
  if (!apiKey) return { ok: false, reason: '키가 없습니다' };
  const m = model || DEFAULT_MODEL;
  const base = (opts.apiUrl || API_URL).replace(/\/v1\/messages\/?$/, '');
  const doFetch = opts.fetchImpl || globalThis.fetch;
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), opts.timeoutMs || 6000);
  try {
    const r = await doFetch(base + '/v1/models/' + encodeURIComponent(m), {
      signal: ctrl.signal,
      headers: authHeaders(apiKey, opts.workspace)
    });
    clearTimeout(timer);
    if (r.ok) return { ok: true, reason: m + ' 를 쓸 수 있습니다' };
    let j = null;
    try { j = await r.json(); } catch { j = null; }
    const e = (j && j.error) || {};
    /* **원문도 같이 돌려줍니다.**
       explain() 은 앱 화면에 나가는 말이라 조심스럽게 씁니다 — 모르는
       종류면 "서버 화면의 [ocr] 줄을 보세요" 로 넘깁니다. 그런데 doctor
       는 서버가 아니라서 그 줄이 없습니다. 주인만 보는 자리이므로
       여기서는 앤트로픽이 한 말을 그대로 붙여 줍니다. 안 그러면 답을
       알고 있으면서 안 알려 주는 꼴입니다. */
    return { ok: false, reason: explain(r.status, e), model: m,
             raw: [r.status, e.type || '', e.message || ''].filter(Boolean).join(' · ') };
  } catch (e) {
    clearTimeout(timer);
    return { ok: false, reason: e && e.name === 'AbortError'
      ? '판독 서비스에 닿는 데 시간이 걸립니다 (네트워크가 막혀 있을 수 있습니다)'
      : '판독 서비스에 닿지 못했습니다 — 이 컴퓨터에서 api.anthropic.com 이 막혀 있는지 보세요' };
  }
}

/* 읽어 올 칸들. hard 범위는 crosscheck.js 와 같은 값입니다 — 사람의
   몸에서 나올 수 없는 값은 여기서 이미 버립니다. 애매한 값은 버리지
   않습니다. 그건 검산과 사람의 몫입니다. */
const FIELDS = {
  weightKg:         { hard: [25, 250],    desc: '체중 (kg)' },
  smmKg:            { hard: [8, 60],      desc: '골격근량 SMM (kg). 근육량(Muscle Mass)과 다릅니다 — 골격근량 줄을 읽으세요' },
  bfmKg:            { hard: [1, 120],     desc: '체지방량 BFM (kg). 체지방률(%)이 아니라 kg 입니다' },
  pbfPct:           { hard: [2, 65],      desc: '체지방률 PBF (%)' },
  ffmKg:            { hard: [20, 130],    desc: '제지방량 FFM (kg). 인쇄돼 있을 때만' },
  bmi:              { hard: [10, 55],     desc: 'BMI' },
  tbwL:             { hard: [15, 90],     desc: '체수분 TBW (L)' },
  proteinKg:        { hard: [3, 25],      desc: '단백질 (kg)' },
  mineralKg:        { hard: [1, 10],      desc: '무기질 (kg)' },
  bmrKcal:          { hard: [700, 3500],  desc: '기초대사량 BMR (kcal)' },
  visceralFatLevel: { hard: [1, 30],      desc: '내장지방 레벨 (정수)' },
  whr:              { hard: [0.55, 1.30], desc: '복부지방률 WHR' },
  inbodyScore:      { hard: [0, 100],     desc: 'InBody 점수 (정수)' },
  idealWeightKg:    { hard: [25, 200],    desc: '적정체중 (kg)' }
};

const SYSTEM = [
  '당신은 인바디(InBody) 체성분 결과지 사진에서 숫자를 옮겨 적는 일만 합니다.',
  '',
  '값을 고르는 규칙 — 이것만 지키면 됩니다:',
  '1. 값은 라벨 오른쪽(영수증형이면 바로 아랫줄)에서, 단위 토큰(kg, %, L, kcal)이',
  '   바로 뒤따르는 첫 번째 숫자입니다.',
  '2. 괄호 안의 숫자는 표준범위입니다. 값이 아닙니다. 예: "28.1 kg (24.8~30.3)" → 28.1',
  '3. 막대그래프 위아래의 등간격 정수 나열은 축 눈금입니다. 값이 아닙니다.',
  '   예: "골격근량 28.1 kg | 55 70 85 100 115 130" → 28.1 이 값이고 나머지는 눈금입니다.',
  '4. 체지방"량"(kg)과 체지방"률"(%)은 다른 항목입니다. 단위를 보고 고르세요.',
  '5. 골격근량(SMM)과 근육량(Muscle Mass)은 다른 항목입니다. 골격근량을 고르세요.',
  '6. 읽히지 않거나 결과지에 없는 항목은 null 로 두세요. 추측하거나 계산해서',
  '   채우지 마세요 — 계산은 앱이 따로 합니다. 지어낸 값은 빈칸보다 나쁩니다.',
  '7. 측정일시는 보통 머리글에 있습니다. 없으면 null 입니다.',
  '',
  '사진이 인바디 결과지가 아니면 모든 칸을 null 로 두고 notInBody 를 true 로 하세요.'
].join('\n');

/* 구조화 출력. 도구 하나만 주고 그것만 쓰게 하면 JSON 이 깨질 일이
   없습니다 — 모델이 산문으로 답할 자리가 없습니다. */
function schema() {
  const props = {
    measuredAt: { type: ['string', 'null'],
      description: '측정일시. ISO 8601 (예: 2026-09-19T11:09:00). 시각을 모르면 날짜만.' },
    device: { type: ['string', 'null'], description: '기기 이름 (예: InBody270). 없으면 null' },
    notInBody: { type: 'boolean', description: '인바디 결과지가 아니면 true' }
  };
  Object.keys(FIELDS).forEach(k => {
    props[k] = { type: ['number', 'null'], description: FIELDS[k].desc };
  });
  return { type: 'object', properties: props, required: ['notInBody'] };
}

const TOOL = {
  name: 'record_sheet',
  description: '결과지에서 읽은 값을 기록합니다.',
  input_schema: schema()
};

/** 사람의 몸에서 나올 수 없는 값은 버립니다. 애매한 값은 남겨 둡니다. */
function clean(raw) {
  const out = {};
  Object.keys(FIELDS).forEach(k => {
    const v = raw[k];
    if (typeof v !== 'number' || !isFinite(v)) return;
    const [lo, hi] = FIELDS[k].hard;
    if (v < lo || v > hi) return;          // 자릿수 오독 — 앱까지 들고 가지 않습니다
    out[k] = Math.round(v * 1000) / 1000;
  });
  if (out.visceralFatLevel != null) out.visceralFatLevel = Math.round(out.visceralFatLevel);
  if (out.inbodyScore != null) out.inbodyScore = Math.round(out.inbodyScore);

  if (typeof raw.measuredAt === 'string') {
    const t = Date.parse(raw.measuredAt.length <= 10 ? raw.measuredAt + 'T09:00:00' : raw.measuredAt);
    // 미래이거나 10년보다 오래됐으면 잘못 읽은 것입니다.
    if (isFinite(t) && t <= Date.now() + 86400000 && t > Date.now() - 10 * 365 * 86400000) {
      out.measuredAt = new Date(t).toISOString();
    }
  }
  if (typeof raw.device === 'string' && raw.device.length <= 40) {
    out.device = raw.device.replace(/[^\w가-힣 .\-]/g, '').slice(0, 40);
  }
  return out;
}

/**
 * @param {object} body    { mediaType, data }  data 는 base64 (데이터 URL 접두사 없이)
 * @param {object} opts    { apiKey, model, timeoutMs, fetchImpl }
 * @returns {Promise<{status:number, body:object}>}
 */
async function runOcr(body, opts) {
  opts = opts || {};
  const apiKey = opts.apiKey;
  if (!apiKey) return { status: 503, body: { ok: false, reason: '판독 키가 없습니다' } };

  const mediaType = String((body && body.mediaType) || '');
  const data = (body && body.data) || '';
  if (!/^image\/(jpeg|png|webp|gif)$/.test(mediaType)) {
    return { status: 400, body: { ok: false, reason: 'JPEG · PNG · WEBP 만 판독할 수 있습니다' } };
  }
  if (typeof data !== 'string' || data.length < 100) {
    return { status: 400, body: { ok: false, reason: '사진이 비어 있습니다' } };
  }
  if (!/^[A-Za-z0-9+/=\s]+$/.test(data.slice(0, 4096))) {
    return { status: 400, body: { ok: false, reason: '사진 형식이 올바르지 않습니다' } };
  }
  // base64 는 원본의 4/3 배입니다. 5MB 원본이면 약 6.7MB.
  if (data.length > 7 * 1024 * 1024) {
    return { status: 413, body: { ok: false, reason: '사진이 너무 큽니다. 더 작게 찍어 주세요' } };
  }

  const doFetch = opts.fetchImpl || globalThis.fetch;
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), opts.timeoutMs || 60_000);
  let r;
  try {
    r = await doFetch(opts.apiUrl || API_URL, {
      method: 'POST',
      signal: ctrl.signal,
      headers: Object.assign({ 'content-type': 'application/json' },
                             authHeaders(apiKey, opts.workspace)),
      body: JSON.stringify({
        model: opts.model || DEFAULT_MODEL,
        max_tokens: 1500,
        system: SYSTEM,
        tools: [TOOL],
        tool_choice: { type: 'tool', name: TOOL.name },
        messages: [{
          role: 'user',
          content: [
            { type: 'image', source: { type: 'base64', media_type: mediaType, data: data } },
            { type: 'text', text: '이 결과지에서 값을 읽어 기록해 주세요.' }
          ]
        }]
      })
    });
  } catch (e) {
    clearTimeout(timer);
    // 왜 실패했는지는 서버 로그에만 둡니다 — 응답에 담으면 키나 내부
    // 주소가 새어 나갈 수 있습니다.
    console.error('[ocr] 요청 실패:', e && e.message);
    return { status: 502, body: { ok: false,
      reason: e && e.name === 'AbortError' ? '판독이 시간을 초과했습니다' : '판독 서비스에 닿지 못했습니다' } };
  }
  clearTimeout(timer);

  let j = null;
  try { j = await r.json(); } catch { j = null; }
  if (!r.ok) {
    /* 원문은 여기(서버 화면)에만 둡니다. 주인만 보는 자리이고,
       무엇을 해야 하는지가 대개 이 한 줄에 다 있습니다. */
    console.error('[ocr] 상태', r.status,
                  (j && j.error && j.error.type) || '',
                  (j && j.error && j.error.message) || '');
    return { status: r.status === 429 ? 429 : 502,
             body: { ok: false, reason: explain(r.status, j && j.error) } };
  }

  const block = (j && Array.isArray(j.content) ? j.content : [])
    .find(c => c && c.type === 'tool_use' && c.name === TOOL.name);
  if (!block || !block.input || typeof block.input !== 'object') {
    return { status: 502, body: { ok: false, reason: '판독 결과를 읽지 못했습니다' } };
  }
  if (block.input.notInBody === true) {
    return { status: 200, body: { ok: true, fields: {}, notInBody: true,
      reason: '인바디 결과지로 보이지 않습니다' } };
  }

  const fields = clean(block.input);
  return { status: 200, body: {
    ok: true,
    fields: fields,
    read: Object.keys(fields).length,
    usage: j.usage ? { in: j.usage.input_tokens, out: j.usage.output_tokens } : null
  } };
}

module.exports = { runOcr, clean, FIELDS, SYSTEM, TOOL, checkKey, explain, DEFAULT_MODEL };
