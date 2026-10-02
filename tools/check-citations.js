/* =============================================================================
 * tools/check-citations.js — 앱 안 「출처」 링크가 실제로 열리는가
 *
 *   node tools/check-citations.js
 *
 * 0.2.20 (347) 은 애플 심사(1.4.1)에서 "건강 권장값에 출처(링크)가 없다" 로
 * 거절됐습니다. 그래서 app/lib/src/citations.dart 에 출처를 달았는데, 심사관이
 * 「출처」 를 눌러 404 나 빈 페이지를 보면 출처가 없는 것과 같습니다 — 다시
 * 거절됩니다. 올리기 전에 **인터넷이 되는 컴퓨터에서** 이것을 돌립니다.
 *
 * 하는 일: citations.dart 의 id · url 을 뽑아 하나씩 열어 봅니다(리디렉트 따라감).
 * 2xx 면 통과, 나머지는 실패로 찍고 끝에 실패 수만큼 종료 코드를 냅니다. 403 은
 * 사람 브라우저만 받는 사이트(출판사 · 정부 게시판)에서 흔해서 「직접 열어 보기」 로
 * 따로 모읍니다 — 그런 주소는 아이폰 · 아이패드 Safari 에서 손으로 열어 확인하세요.
 *
 * 통과해도 **제목 · 숫자가 맞는지는 사람 눈으로** 봐야 합니다(DOI 가 다른 논문으로
 * 갈 수도 있습니다). 특히 DOI 가 아닌 주소(정부 게시판 · 포털 · 블로그)는 전부 손으로.
 *
 *   node tools/check-citations.js --meta
 *
 * --meta 면 줄마다 「우리가 적은 서지」 와 「그 링크가 실제로 가리키는 것」 을 나란히
 * 찍습니다 — DOI 는 Crossref 기록(제목 · 첫 저자 · 연도 · 학술지), 나머지는 페이지 <title>.
 * 클라우드 작업 환경은 출판사 · 정부 사이트가 막혀 있어서, GitHub Actions
 * 「출처 링크 점검」(citations-check.yml)이 이것을 돌립니다.
 * ========================================================================== */
'use strict';
const fs = require('fs');
const path = require('path');

const FILE = path.join(__dirname, '..', 'app', 'lib', 'src', 'citations.dart');
const UA = 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 '
  + '(KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1';

function entries() {
  const src = fs.readFileSync(FILE, 'utf8');
  const out = [];
  const re = /id:\s*'([^']+)'[\s\S]*?reference:\s*((?:'[^']*'\s*)+),[\s\S]*?url:\s*'([^']+)'/g;
  let m;
  while ((m = re.exec(src))) {
    const reference = [...m[2].matchAll(/'([^']*)'/g)].map(x => x[1]).join('');
    out.push({ id: m[1], reference, url: m[3] });
  }
  return out;
}

/** 링크가 실제로 가리키는 것 — DOI 는 Crossref, 나머지는 페이지 <title>. 못 읽으면 이유. */
async function describe(url) {
  const u = new URL(url);
  try {
    if (u.host === 'doi.org') {
      const doi = decodeURIComponent(u.pathname.slice(1));
      const res = await fetch(`https://api.crossref.org/works/${encodeURIComponent(doi)}`, {
        headers: { 'user-agent': 'mybody-citation-check/1.0 (https://github.com/iacobuschoi/Mybody)' },
        signal: AbortSignal.timeout(20000),
      });
      if (!res.ok) return `Crossref ${res.status} — 이 DOI 기록 없음`;
      const w = (await res.json()).message || {};
      const a = (w.author || [])[0];
      const year = ((w.issued || {})['date-parts'] || [[]])[0][0];
      return `${(w.title || ['?'])[0]} | ${a ? `${a.family || ''} ${a.given || ''}`.trim() : '?'} | ${year || '?'} | `
        + `${(w['container-title'] || [w.publisher || '?'])[0]}`;
    }
    /* FoodData Central 은 화면이 자바스크립트로만 그려져서 페이지 제목으로는 무슨 식품인지 모릅니다 —
       같은 번호를 공개 API(DEMO_KEY)로 읽어 이름과 단백질 값을 찍습니다. */
    const fdc = url.match(/fdc\.nal\.usda\.gov\/.*food-details\/(\d+)/);
    if (fdc) {
      const r = await fetch(`https://api.nal.usda.gov/fdc/v1/food/${fdc[1]}?api_key=DEMO_KEY`,
        { signal: AbortSignal.timeout(20000) });
      if (!r.ok) return `FDC API ${r.status}`;
      const f = await r.json();
      const prot = (f.foodNutrients || []).find(n => (n.nutrient || {}).name === 'Protein');
      return `FDC ${fdc[1]}: ${f.description} (${f.dataType}) · 단백질 ${prot ? prot.amount : '?'} g/100g`;
    }
    const res = await fetch(url, {
      redirect: 'follow', headers: { 'user-agent': UA, accept: 'text/html,*/*' }, signal: AbortSignal.timeout(20000),
    });
    /* 한국 정부 · 학회 사이트는 아직 EUC-KR 인 곳이 있습니다 — 머리말 · <meta> 의 charset 대로 풉니다. */
    const buf = Buffer.from(await res.arrayBuffer());
    const head = buf.toString('latin1', 0, 4096);
    const cs = ((res.headers.get('content-type') || '').match(/charset=([\w-]+)/i)
      || head.match(/charset=["']?([\w-]+)/i) || [])[1] || 'utf-8';
    let html;
    try { html = new TextDecoder(cs.toLowerCase()).decode(buf); } catch (e) { html = buf.toString('utf8'); }
    const clean = x => (x || '').replace(/<[^>]+>/g, ' ').replace(/&nbsp;/g, ' ').replace(/\s+/g, ' ').trim();
    const t = clean((html.match(/<title[^>]*>([\s\S]*?)<\/title>/i) || [])[1]).slice(0, 160);
    /* 게시판 글은 <title> 이 사이트 이름뿐일 때가 많아서 글 제목(h1~h4 · og:title)도 같이 찍습니다. */
    const og = (html.match(/<meta[^>]+property=["']og:title["'][^>]+content=["']([^"']+)/i) || [])[1];
    const hs = [...html.matchAll(/<h[1-4][^>]*>([\s\S]*?)<\/h[1-4]>/gi)].map(m => clean(m[1])).filter(Boolean)
      .slice(0, 4).join(' / ').slice(0, 200);
    return `HTTP ${res.status} | <title> ${t || '(없음)'}${og ? ` | og: ${og.slice(0, 120)}` : ''}${hs ? ` | 제목: ${hs}` : ''}`;
  } catch (e) {
    return `못 읽음(${String(e.cause?.code || e.message)})`;
  }
}

async function probe(url) {
  for (const method of ['HEAD', 'GET']) {
    try {
      const res = await fetch(url, {
        method, redirect: 'follow', headers: { 'user-agent': UA, accept: 'text/html,*/*' },
        signal: AbortSignal.timeout(20000),
      });
      /* HEAD 를 안 받는 서버가 있습니다(405 · 403) — GET 으로 한 번 더. */
      if (method === 'HEAD' && !res.ok) continue;
      return { status: res.status, final: res.url };
    } catch (e) {
      if (method === 'GET') return { status: 0, final: String(e.cause?.code || e.message) };
    }
  }
  return { status: 0, final: '?' };
}

(async () => {
  const list = entries();
  if (list.length === 0) {
    console.error('citations.dart 에서 url 을 못 찾았습니다');
    process.exit(2);
  }
  const bad = [], manual = [];
  const meta = process.argv.includes('--meta');
  for (const { id, reference, url } of list) {
    const { status, final } = await probe(url);
    const doi = new URL(url).host === 'doi.org';
    const tag = status >= 200 && status < 300 ? 'ok ' : (status === 403 ? '403' : 'BAD');
    console.log(`${tag} ${String(status).padStart(3)}  ${id.padEnd(34)} ${url}${final && final !== url ? `  → ${final}` : ''}`);
    if (meta) {
      console.log(`      우리 서지: ${reference}`);
      console.log(`      실제 링크: ${await describe(url)}`);
    }
    if (tag === 'BAD') bad.push(id);
    if (tag === '403' || !doi) manual.push(`${id}  ${url}`);
  }
  console.log(`\n${list.length}개 중 실패 ${bad.length}개${bad.length ? ': ' + bad.join(', ') : ''}`);
  if (manual.length) {
    console.log('\n직접 열어 볼 것(DOI 가 아니거나 403 — 아이폰 · 아이패드 Safari 에서):');
    for (const m of manual) console.log('  ' + m);
  }
  process.exit(bad.length);
})();
