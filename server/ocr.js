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
      headers: {
        'content-type': 'application/json',
        'x-api-key': apiKey,
        'anthropic-version': API_VERSION
      },
      body: JSON.stringify({
        model: opts.model || 'claude-opus-5',
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
    console.error('[ocr] 상태', r.status, j && j.error && j.error.type);
    const reason = r.status === 429 ? '판독 서비스가 바쁩니다. 잠시 뒤에 다시 해 주세요'
                 : r.status === 401 ? '이 서버의 판독 키가 거부되었습니다'
                 : '판독에 실패했습니다';
    return { status: r.status === 429 ? 429 : 502, body: { ok: false, reason } };
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

module.exports = { runOcr, clean, FIELDS, SYSTEM, TOOL };
