/* =============================================================================
 * tools/test-weekplan-ui.js — 홈의 주간 운동 칸을 진짜 브라우저에서 눌러본다
 *
 *   NODE_PATH=/opt/node22/lib/node_modules node tools/test-weekplan-ui.js
 *
 * 계산은 test-schedule.js 가 봅니다. 여기서 보는 건 그 계산이 화면까지
 * 닿는가입니다 — 칸을 누르면 모달이 뜨는가, 정한 것이 칸에 표시되는가,
 * 체크하면 그 자리에서 바뀌는가, 새로고침해도 남는가.
 * ========================================================================== */
'use strict';
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const { chromium } = require(process.env.NODE_PATH
  ? path.join(process.env.NODE_PATH, 'playwright') : 'playwright');

const ROOT = path.join(__dirname, '..', 'prototype');
const PORT = 8900 + Math.floor(Math.random() * 200);
const CHROME = process.env.CHROME_PATH || '/opt/pw-browsers/chromium-1194/chrome-linux/chrome';
const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css',
               '.json': 'application/json', '.svg': 'image/svg+xml',
               '.webmanifest': 'application/manifest+json' };

const server = http.createServer((req, res) => {
  let p = decodeURIComponent(req.url.split('?')[0]);
  if (p === '/') p = '/index.html';
  const f = path.join(ROOT, p);
  if (!f.startsWith(ROOT) || !fs.existsSync(f) || fs.statSync(f).isDirectory()) {
    res.writeHead(404); return res.end('404');
  }
  res.writeHead(200, { 'Content-Type': MIME[path.extname(f)] || 'application/octet-stream' });
  res.end(fs.readFileSync(f));
});

let pass = 0, fail = 0;
const ok = (n, c, d) => {
  if (c) { pass++; console.log('  ✓', n); }
  else { fail++; console.log('  ✗', n, d === undefined ? '' : JSON.stringify(d).slice(0, 200)); }
};

(async () => {
  await new Promise(r => server.listen(PORT, r));
  const browser = await chromium.launch({ executablePath: CHROME });
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 } });
  /* 시계를 수요일에 못박습니다.
     안 그러면 이번 주에 "지난 날"이나 "앞날" 칸이 없는 요일이 생기고,
     그 날은 시험이 조용히 건너뜁니다 — 일요일에만 검사가 반쯤 도는
     테스트는 통과했다는 말을 믿을 수 없게 만듭니다. */
  await ctx.clock.setFixedTime(new Date('2026-09-23T10:00:00'));
  const page = await ctx.newPage();
  const errs = [];
  page.on('pageerror', e => errs.push('PAGEERROR: ' + e.message.slice(0, 200)));
  page.on('console', m => {
    if (m.type() !== 'error') return;
    /* 정적 서버에 /health 가 없는 건 맞는 상태입니다 (smoke.js 와 같은 이유) */
    if (/health|Failed to load resource/.test(m.text())) return;
    errs.push('CONSOLE: ' + m.text().slice(0, 200));
  });

  /* 개발 빌드에만 있는 우하단 도크를 치웁니다. 배포 빌드에는 css/uid.css
     자체가 안 들어가서 없는 물건인데, 여기서는 바텀시트 아래쪽 버튼을
     가려 버립니다. 강제 클릭으로 뚫으면 진짜 가림 버그까지 같이 안 보이게
     되므로 개발 전용 요소만 숨기고 나머지는 그대로 둡니다. */
  const hideDock = () => page.addStyleTag({ content: '.uid-dock{display:none!important}' });

  const go = async () => {
    await page.goto(`http://localhost:${PORT}/`, { waitUntil: 'load' });
    await page.waitForTimeout(350);
    await hideDock();
    await page.evaluate(() => { window.MB_STORE.seed(); window.MB_APP.go('P02'); });
    await page.waitForTimeout(350);
  };
  const u = s => `[data-uid="${s}"]`;

  console.log('\n[1] 카드가 홈에 있는가');
  await go();
  ok('이번 주 운동 카드', await page.locator(u('P02-C08')).count() === 1);
  ok('일곱 칸이 일곱 개', await page.locator(u('P02-L02#1')).count() === 1 &&
     await page.locator(u('P02-L02#7')).count() === 1);
  const cells = await page.locator('.wk__d').count();
  ok('칸이 정확히 7개', cells === 7, cells);
  ok('스트릭 줄이 있다', await page.locator(u('P02-C09')).count() === 1);

  console.log('\n[1-2] 한 줄에 들어가는가 (가장 좁은 폰)');
  await page.setViewportSize({ width: 320, height: 720 });
  await page.waitForTimeout(150);
  const boxes = await page.locator('.wk__d').evaluateAll(
    els => els.map(e => { const r = e.getBoundingClientRect(); return { t: Math.round(r.top), w: Math.round(r.width), h: Math.round(r.height) }; }));
  ok('일곱 칸이 같은 줄에 있다', new Set(boxes.map(b => b.t)).size === 1, boxes.map(b => b.t));
  ok('칸이 눌릴 만큼 크다 (44px 이상)', boxes.every(b => b.h >= 44), boxes[0]);
  ok('가로로 넘치지 않는다',
     await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth));
  await page.setViewportSize({ width: 390, height: 844 });

  console.log('\n[2] 칸을 누르면 그 날을 정할 수 있는가');
  await page.locator(u('P02-L02#1')).click();
  await page.waitForTimeout(250);
  ok('하루 정하기 모달이 뜬다', await page.locator(u('M51')).count() === 1);
  ok('부제에 날짜가 있다',
     /\d+월 \d+일/.test(await page.locator(u('M51') + ' .card__sub').innerText()));
  await page.locator(u('M51-L01#1')).click();          // 헬스
  await page.waitForTimeout(150);
  ok('헬스가 "하기로 함" 으로 바뀐다',
     (await page.locator(u('M51-L01#1')).innerText()).includes('하기로 함'));
  await page.locator(u('M51-B01')).click();            // 닫기
  await page.waitForTimeout(250);

  console.log('\n[3] 정한 것이 칸에 표시되는가');
  const marks = await page.locator(u('P02-L02#1') + ' .wk__m').count();
  ok('월요일 칸에 표시가 하나 생겼다', marks === 1, marks);
  ok('아직 완료 표시는 아니다',
     await page.locator(u('P02-L02#1') + ' .wk__m.is-done').count() === 0);

  console.log('\n[4] 오늘 할 일은 카드에서 바로 체크된다');
  const todayIdx = await page.evaluate(() => {
    const w = window.MB_SCHED.week();
    for (let i = 0; i < 7; i++) if (w.days[i].isToday) return i + 1;
    return 0;
  });
  await page.evaluate(() => {
    window.MB_STORE.setSchedulePlan(window.MB_STORE.dayKey(), 'gym', true);
    window.MB_APP.refresh();
  });
  await page.waitForTimeout(250);
  ok('오늘 헬스 체크 버튼이 보인다', await page.locator(u('P02-B23#1')).count() === 1);
  await page.locator(u('P02-B23#1')).click();
  await page.waitForTimeout(300);
  ok('버튼이 사라지고 다 했다고 말한다',
     await page.locator(u('P02-B23#1')).count() === 0 &&
     (await page.locator(u('P02-C08')).innerText()).includes('다 했습니다'));
  ok('오늘 칸에 완료 표시가 찍힌다',
     await page.locator(u('P02-L02#' + todayIdx) + ' .wk__m.is-done').count() === 1);
  ok('스트릭이 1일째가 된다',
     (await page.locator(u('P02-C09')).innerText()).includes('1일 연속'),
     await page.locator(u('P02-C09')).innerText());

  console.log('\n[5] 새로고침해도 남는가');
  await page.reload({ waitUntil: 'load' });
  await page.waitForTimeout(400);
  await hideDock();
  await page.evaluate(() => window.MB_APP.go('P02'));
  await page.waitForTimeout(300);
  ok('오늘 완료 표시가 그대로 있다',
     await page.locator(u('P02-L02#' + todayIdx) + ' .wk__m.is-done').count() === 1);
  ok('스트릭도 그대로', (await page.locator(u('P02-C09')).innerText()).includes('1일 연속'));

  console.log('\n[6] 아직 오지 않은 날은 체크할 수 없다');
  const futureIdx = await page.evaluate(() => {
    const w = window.MB_SCHED.week();
    for (let i = 0; i < 7; i++) if (w.days[i].isFuture) return i + 1;
    return 0;
  });
  ok('이번 주에 앞날 칸이 있다 (시계 고정이 먹었는가)', futureIdx > 0, futureIdx);
  await page.locator(u('P02-L02#' + futureIdx)).click();
  await page.waitForTimeout(250);
  await page.locator(u('M51-L01#1')).click();          // 앞날에 헬스 계획
  await page.waitForTimeout(150);
  ok('앞날에는 "했어요" 버튼이 없다', await page.locator(u('M51-L02#1')).count() === 0);
  ok('왜 없는지 적혀 있다',
     (await page.locator(u('M51')).innerText()).includes('아직 오지 않은 날'));
  await page.locator(u('M51-B01')).click();
  await page.waitForTimeout(250);
  ok('앞날 칸에는 예정 표시만 찍힌다',
     await page.locator(u('P02-L02#' + futureIdx) + ' .wk__m').count() === 1 &&
     await page.locator(u('P02-L02#' + futureIdx) + ' .wk__m.is-done').count() === 0);

  console.log('\n[6-2] 지나갔는데 못 한 날');
  await page.evaluate(() => {
    const y = window.MB_SCHED.shiftKey(window.MB_STORE.dayKey(), -1);
    window.MB_STORE.setSchedulePlan(y, 'cardio', true);
    window.MB_APP.refresh();
  });
  await page.waitForTimeout(250);
  const pastIdx = await page.evaluate(() => {
    const w = window.MB_SCHED.week();
    for (let i = 6; i >= 0; i--) if (w.days[i].isPast) return i + 1;
    return 0;
  });
  ok('점선으로만 구분한다 (빨간 칸이 아니다)',
     await page.locator(u('P02-L02#' + pastIdx) + '.is-missed').count() === 1);
  ok('지난 날도 나중에 체크할 수 있다', await (async () => {
    await page.locator(u('P02-L02#' + pastIdx)).click();
    await page.waitForTimeout(250);
    const has = await page.locator(u('M51-L02#2')).count() === 1;
    await page.locator(u('M51-L02#2')).click();
    await page.waitForTimeout(150);
    const said = (await page.locator(u('M51')).innerText()).includes('에 체크했습니다');
    await page.locator(u('M51-B01')).click();
    await page.waitForTimeout(200);
    return has && said;
  })());

  console.log('\n[7] 인바디가 없어도 일정은 쓸 수 있다');
  await page.evaluate(() => { localStorage.clear(); });
  await page.reload({ waitUntil: 'load' });
  await page.waitForTimeout(400);
  await hideDock();
  await page.evaluate(() => window.MB_APP.go('P02'));
  await page.waitForTimeout(300);
  ok('측정이 없어도 카드가 보인다', await page.locator(u('P02-C08')).count() === 1);
  ok('인바디 올리기 안내도 같이 있다', await page.locator(u('P02-S01')).count() === 1);

  console.log('\n[8] 고유번호 규칙');
  const bad = await page.evaluate(() => {
    const RE = /^(P\d{2}|M\d{2}|A\d{2})(-[A-Z]\d{2})?(#\d+)?$/;
    return [...document.querySelectorAll('[data-uid]')]
      .map(e => e.getAttribute('data-uid')).filter(x => !RE.test(x));
  });
  ok('규칙에 어긋나는 번호 없음', bad.length === 0, bad);
  const naked = await page.evaluate(() => [...document.querySelectorAll('.wk__d, .daypick__main')]
    .filter(e => !e.getAttribute('data-uid')).length);
  ok('누를 수 있는 새 요소에 번호가 다 있다', naked === 0, naked);

  console.log('\n[9] JS 오류');
  ok('오류 0건', errs.length === 0, errs);

  await browser.close();
  server.close();
  console.log('\n' + (fail ? '✗ ' + fail + '개 실패 / ' : '✓ 전부 통과 — ') + (pass + fail) + '개');
  process.exit(fail ? 1 : 0);
})().catch(e => { console.error(e); process.exit(1); });
