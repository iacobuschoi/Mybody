/* =============================================================================
 * tools/ocr-compare.js — 같은 결과지를 여러 모델에 읽혀서 나란히 놓습니다
 *
 *   node tools/ocr-compare.js 결과지.jpg
 *   node tools/ocr-compare.js 결과지.jpg --models=claude-sonnet-5,claude-haiku-4-5-20251001
 *   node tools/ocr-compare.js 결과지.jpg --runs=3        같은 모델을 세 번씩
 *
 * 왜 있나
 *   "인바디 판독에 어느 모델이면 충분한가" 는 제가 대답할 수 없습니다.
 *   벤치마크 점수는 님의 결과지가 아니고, 님의 결과지는 님만 갖고 있습니다.
 *   기기(인바디 270 · 570 · 770)마다 줄 이름과 배치가 다르고, 사진은
 *   기울어지고 형광등이 비칩니다. 그래서 답을 고르지 말고 **재 보게**
 *   합니다. 한 번 돌리는 데 세 모델 합쳐 50원쯤 듭니다.
 *
 *   서버와 **똑같은** 프롬프트 · 똑같은 도구 정의로 부릅니다
 *   (server/ocr.js 를 그대로 씁니다). 여기서 맞으면 앱에서도 맞습니다.
 *
 * 무엇을 보나
 *   1. 값이 갈리는 칸. 다 같으면 싼 모델로 내려도 됩니다.
 *      갈리면 **어느 쪽이 맞는지 결과지를 눈으로 보고** 정하세요.
 *   2. 실제 값. 추정이 아니라 앤트로픽이 돌려준 토큰 수로 계산합니다.
 *   3. --runs 로 같은 모델을 여러 번. 매번 다른 답을 내는 모델은
 *      한 번 맞았다고 믿을 수 없습니다 — 싼 모델에서 실제로 생깁니다.
 *
 * 의존성은 없습니다. 노드 기본 기능만 씁니다.
 * ========================================================================== */
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const CONFIG = require('./config.js');
const OCR = require('../server/ocr.js');

/* 공시가 (platform.claude.com/docs/en/about-claude/pricing, 2026-09-21 확인).
   단위는 백만 토큰당 달러입니다. 바뀌면 여기만 고치면 됩니다. */
const PRICES = {
  'claude-opus-5':             { in: 5, out: 25, name: 'Opus 5' },
  'claude-sonnet-5':           { in: 2, out: 10, name: 'Sonnet 5' },
  'claude-haiku-4-5-20251001': { in: 1, out: 5,  name: 'Haiku 4.5' }
};
const DEFAULT_MODELS = Object.keys(PRICES);

const argv = process.argv.slice(2);
function flag(name, dflt) {
  const hit = argv.find(a => a.indexOf('--' + name + '=') === 0);
  return hit ? hit.slice(name.length + 3) : dflt;
}

/* 사진 크기를 헤더에서 직접 읽습니다. 라이브러리를 안 쓰는 이유는
   이 저장소에 의존성이 없기 때문이고, 크기를 봐야 하는 이유는
   **앱이 보내는 것과 다른 크기로 재면 비교가 거짓말이 되기 때문**입니다.
   앱은 긴 변 1600 으로 줄여서 보냅니다 (prototype/js/photo.js). */
function dimensions(buf) {
  /* 경계 조건에 주의: PNG 의 IHDR 은 24바이트째에서 끝나므로 >= 24 이고,
     JPEG 은 i+8 까지 읽으므로 i + 8 < length 여야 합니다. 예전에는 둘 다
     한 칸씩 빡빡해서, 딱 맞는 크기의 파일에서 "크기 모름" 이 나왔습니다. */
  if (buf.length >= 24 && buf.readUInt32BE(0) === 0x89504e47) {          // PNG
    return { w: buf.readUInt32BE(16), h: buf.readUInt32BE(20) };
  }
  if (buf[0] === 0xFF && buf[1] === 0xD8) {                             // JPEG
    let i = 2;
    while (i + 8 < buf.length) {
      if (buf[i] !== 0xFF) { i++; continue; }
      const m = buf[i + 1];
      if (m >= 0xC0 && m <= 0xCF && m !== 0xC4 && m !== 0xC8 && m !== 0xCC) {
        return { h: buf.readUInt16BE(i + 5), w: buf.readUInt16BE(i + 7) };
      }
      i += 2 + buf.readUInt16BE(i + 2);
    }
  }
  return null;
}

function mediaTypeOf(file, buf) {
  if (buf[0] === 0xFF && buf[1] === 0xD8) return 'image/jpeg';
  if (buf.length > 8 && buf.readUInt32BE(0) === 0x89504e47) return 'image/png';
  if (buf.length > 12 && buf.slice(8, 12).toString() === 'WEBP') return 'image/webp';
  const e = path.extname(file).toLowerCase();
  if (e === '.jpg' || e === '.jpeg') return 'image/jpeg';
  if (e === '.png') return 'image/png';
  if (e === '.webp') return 'image/webp';
  return '';
}

function money(usd, krw) {
  return '$' + usd.toFixed(4) + ' (' + Math.round(usd * krw).toLocaleString('ko-KR') + '원)';
}

function costOf(model, usage) {
  const p = PRICES[model];
  if (!p || !usage) return null;
  return (usage.in || 0) * p.in / 1e6 + (usage.out || 0) * p.out / 1e6;
}

function pad(s, n) {
  s = String(s === undefined || s === null ? '' : s);
  /* 한글은 두 칸을 먹습니다. 안 세면 표가 어긋납니다. */
  let w = 0;
  for (const ch of s) w += /[ᄀ-ᇿ　-〿가-힯＀-￯]/.test(ch) ? 2 : 1;
  return s + ' '.repeat(Math.max(0, n - w));
}

async function main() {
  const file = argv.find(a => a.indexOf('--') !== 0);
  if (!file) {
    console.log('결과지 사진을 하나 주세요:');
    console.log('  node tools/ocr-compare.js 결과지.jpg');
    console.log('');
    console.log('  --models=a,b   비교할 모델 (기본: ' + DEFAULT_MODELS.join(', ') + ')');
    console.log('  --runs=3       같은 모델을 여러 번 (같은 답을 내는지)');
    console.log('  --krw=1400     환율 (기본 1400)');
    return 1;
  }

  const { cfg } = CONFIG.load();
  const key = cfg.anthropicKey;
  if (!key) { console.log('판독 키가 없습니다: node tools/serve.js --setup --key'); return 1; }
  const workspace = cfg.anthropicWorkspace || undefined;

  let buf;
  try { buf = fs.readFileSync(file); }
  catch (e) { console.log('사진을 못 읽었습니다: ' + file); return 1; }

  const mediaType = mediaTypeOf(file, buf);
  if (!mediaType) { console.log('JPEG · PNG · WEBP 만 됩니다.'); return 1; }

  const dim = dimensions(buf);
  const krw = Number(flag('krw', 1400)) || 1400;
  const runs = Math.max(1, Number(flag('runs', 1)) || 1);
  const models = String(flag('models', DEFAULT_MODELS.join(','))).split(',')
    .map(s => s.trim()).filter(Boolean);

  console.log('');
  console.log('사진: ' + path.basename(file) + '  ' +
              (dim ? dim.w + '×' + dim.h : '크기 모름') + '  ' +
              Math.round(buf.length / 1024) + 'KB');
  if (dim && Math.max(dim.w, dim.h) > 1600) {
    /* 조용히 넘어가면 안 됩니다. 앱보다 큰 사진으로 재면 값도 더 나오고
       정확도도 더 좋게 나옵니다 — 둘 다 실제보다 좋게 보입니다. */
    console.log('  ⚠ 앱은 긴 변을 1600 으로 줄여서 보냅니다. 이 사진은 그보다 큽니다 —');
    console.log('    실제 앱보다 값이 더 나오고 더 잘 읽힐 수 있습니다. 참고하세요.');
  }
  console.log('모델 ' + models.length + '개' + (runs > 1 ? ' × ' + runs + '번' : '') +
              '  (환율 ' + krw.toLocaleString('ko-KR') + '원 가정)');
  console.log('');

  const data = buf.toString('base64');
  const results = [];   // { model, run, fields, usage, cost, ms, error }

  for (const model of models) {
    for (let run = 1; run <= runs; run++) {
      const t0 = Date.now();
      let r;
      try {
        r = await OCR.runOcr(key, { mediaType: mediaType, data: data },
                             { model: model, workspace: workspace, timeoutMs: 90000 });
      } catch (e) {
        r = { status: 0, body: { ok: false, reason: String(e && e.message || e) } };
      }
      const ms = Date.now() - t0;
      const b = r.body || {};
      const row = { model: model, run: run, ms: ms,
                    fields: b.fields || null, usage: b.usage || null,
                    error: b.ok ? null : (b.reason || ('실패 ' + r.status)) };
      row.cost = costOf(model, row.usage);
      results.push(row);
      const label = (PRICES[model] && PRICES[model].name) || model;
      console.log('  ' + pad(label, 12) + (runs > 1 ? '#' + run + ' ' : '') +
        (row.error ? '✗ ' + row.error
                   : '✓ ' + Object.keys(row.fields).length + '칸 · ' + (ms / 1000).toFixed(1) + '초' +
                     (row.usage ? ' · 입력 ' + row.usage.in + ' 출력 ' + row.usage.out : '') +
                     (row.cost != null ? ' · ' + money(row.cost, krw) : '')));
    }
  }

  const good = results.filter(r => r.fields);
  if (!good.length) { console.log('\n전부 실패했습니다.'); return 1; }

  /* --- 값이 갈리는 칸 ----------------------------------------------------- */
  const keys = [];
  for (const r of good) for (const k of Object.keys(r.fields)) if (keys.indexOf(k) < 0) keys.push(k);

  console.log('');
  console.log('읽은 값');
  const head = pad('', 18) + good.map(r =>
    pad((PRICES[r.model] && PRICES[r.model].name || r.model) + (runs > 1 ? '#' + r.run : ''), 16)).join('');
  console.log('  ' + head);

  let disagree = 0;
  for (const k of keys) {
    const vals = good.map(r => r.fields[k]);
    const norm = vals.map(v => v === undefined ? '—' : String(v));
    const same = norm.every(v => v === norm[0]);
    if (!same) disagree++;
    const desc = (OCR.FIELDS[k] && OCR.FIELDS[k].desc) || k;
    console.log('  ' + (same ? ' ' : '≠') + ' ' + pad(k, 16) +
                norm.map(v => pad(v, 16)).join('') + (same ? '' : '   ← ' + desc.split('.')[0]));
  }

  console.log('');
  if (!disagree) {
    console.log('✓ 모든 칸이 같습니다. 이 사진에서는 제일 싼 모델로 내려도 됩니다.');
  } else {
    console.log('≠ 표시된 ' + disagree + '칸이 갈립니다. **결과지를 눈으로 보고** 어느 쪽이');
    console.log('  맞는지 확인하세요. 비싼 모델이 항상 맞는 건 아닙니다.');
  }

  /* --- 값 -------------------------------------------------------------- */
  console.log('');
  console.log('한 장에 드는 값 (앤트로픽이 돌려준 실제 토큰 기준)');
  const byModel = {};
  for (const r of good) {
    if (r.cost == null) continue;
    (byModel[r.model] = byModel[r.model] || []).push(r.cost);
  }
  const rows = Object.keys(byModel).map(m => ({
    m: m, avg: byModel[m].reduce((a, b) => a + b, 0) / byModel[m].length
  })).sort((a, b) => a.avg - b.avg);
  const cheapest = rows.length ? rows[0].avg : 0;
  for (const r of rows) {
    console.log('  ' + pad((PRICES[r.m] && PRICES[r.m].name) || r.m, 12) +
                pad(money(r.avg, krw), 22) +
                (cheapest > 0 ? '제일 싼 것의 ' + (r.avg / cheapest).toFixed(1) + '배' : ''));
  }
  console.log('');
  console.log('  한 달에 8장(주 2회)이면 ' + rows.map(r =>
    (PRICES[r.m] && PRICES[r.m].name || r.m) + ' ' + Math.round(r.avg * 8 * krw).toLocaleString('ko-KR') + '원'
  ).join(' · '));
  console.log('');
  console.log('  바꾸려면:  node tools/serve.js --setup --model=<모델이름>');
  console.log('');
  return 0;
}

if (require.main === module) {
  main().then(c => process.exit(c || 0))
        .catch(e => { console.error('비교 중 오류: ' + (e && e.message || e)); process.exit(1); });
}
module.exports = { dimensions, mediaTypeOf, costOf, PRICES };
