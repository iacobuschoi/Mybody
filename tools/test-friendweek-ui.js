/* =============================================================================
 * tools/test-friendweek-ui.js — 친구의 한 주를 어느 주라고 부르는가
 *
 *   NODE_PATH=/opt/node22/lib/node_modules node tools/test-friendweek-ui.js
 *
 * 스냅샷은 친구가 **자기 앱에서 저장할 때만** 올라갑니다. 새 주가 시작되고
 * 친구가 아직 앱을 안 열었으면 그 주의 행이 없고 rows[0] 은 지난주 것입니다.
 * 월요일 아침의 기본 상태입니다.
 *
 * 그때 화면이 그 행을 "이번 주 일정" 이라고 부르면, 남의 지난주 성적을
 * 이번 주라고 말하는 것이 됩니다. 같은 화면이 위에서는 "마지막 소식 ·
 * 1주 전" 이라고 적으면서 바로 아래 카드는 같은 행을 "이번 주" 라고
 * 불렀습니다 — 화면이 자기 자신과 어긋나 있었습니다.
 *
 * 눈으로는 못 잡습니다. 이 고장은 "친구가 이번 주에 아직 앱을 안 열었다"
 * 라는 상태에서만 보이고, 개발하면서 만드는 데이터는 언제나 이번 주
 * 것이니까요. 그래서 그 상태를 일부러 만들어 놓고 봅니다.
 * ========================================================================== */
'use strict';
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const { chromium } = require(process.env.NODE_PATH
  ? path.join(process.env.NODE_PATH, 'playwright') : 'playwright');

const ROOT = path.join(__dirname, '..', 'prototype');
const PORT = 9500 + Math.floor(Math.random() * 200);
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
  else { fail++; console.log('  ✗', n, d === undefined ? '' : JSON.stringify(d).slice(0, 300)); }
};

(async () => {
  await new Promise(r => server.listen(PORT, r));
  const browser = await chromium.launch({ executablePath: CHROME });
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 } });
  /* 수요일 낮에 못박습니다. 월요일 00:05 같은 경계에서만 도는 시험은
     "통과했다" 는 말을 믿을 수 없게 만듭니다 — 경계는 아래에서 따로 봅니다. */
  await ctx.clock.setFixedTime(new Date('2026-09-23T10:00:00'));
  const page = await ctx.newPage();
  const errs = [];
  page.on('pageerror', e => errs.push('PAGEERROR: ' + e.message.slice(0, 200)));
  page.on('console', m => {
    if (m.type() !== 'error') return;
    if (/health|Failed to load resource/.test(m.text())) return;
    errs.push('CONSOLE: ' + m.text().slice(0, 200));
  });

  await page.goto(`http://localhost:${PORT}/`, { waitUntil: 'load' });
  await page.waitForTimeout(400);
  await page.addStyleTag({ content: '.uid-dock{display:none!important}' });

  /** 데모 친구를 하나 만들고, 그 친구의 주간 일정 행을 내가 정한 주에만
   *  올려 둡니다. weeks = [0, 1] 이면 이번 주와 지난주 둘 다. */
  /* MB_SOCIAL.makeDemoFriend() 는 안 씁니다 — 그건 12주치를 통째로
     올려 두기 때문에 "이번 주 행이 없다" 를 만들 수가 없습니다.
     같은 일을 손으로 하되 올릴 주만 내가 고릅니다. */
  const seed = (weeks, payload) => page.evaluate(([ws, pay]) => {
    const BE = window.MB_BACKEND, S = window.MB_STORE;
    BE.reset();
    const me = BE.signIn({ provider: 'kakao' });
    S.publishWeekly();
    const saved = BE.currentUser().id;

    const demo = BE.signIn({ provider: 'demo', handle: 'demo:1', displayName: '데모친구' });
    BE.sendRequest(me.inviteCode);
    BE._setSession(saved);
    BE.accept(demo.id);
    BE._setSession(demo.id);
    BE.setShare(saved, { streak: true, schedule: true });
    const wkOf = n => {
      const d = new Date();
      d.setDate(d.getDate() - n * 7);
      return S.weekStartOf(d);
    };
    ws.forEach(n => BE.publishSnapshot(wkOf(n), pay));
    BE._setSession(saved);
    return { me: saved, demo: demo.id, session: BE.currentUser().id,
             weeks: ws.map(wkOf) };
  }, [weeks, payload || { checkedIn: true,
                          plannedDays: 4, keptDays: 2, missedDays: 1, openDays: 1 }]);

  const go = async id => {
    await page.evaluate(d => window.MB_APP.go('P16', { friendId: d }), id);
    await page.waitForTimeout(350);
  };
  const u = s => `[data-uid="${s}"]`;

  console.log('\n[1] 이번 주 행이 있으면 "이번 주" 라고 부른다');
  let s1 = await seed([0, 1]);
  ok('데모 친구를 만든 뒤 내 세션으로 돌아온다', s1.session === s1.me, s1);
  await go(s1.demo);
  {
    const t = await page.locator(u('P16-C06')).innerText();
    ok('카드 제목이 "이번 주 일정"', t.startsWith('이번 주 일정'), t.slice(0, 120));
    ok('남은 날을 "남았습니다" 로 말한다', t.includes('남았습니다'), t.slice(0, 200));
    const head = await page.locator(u('P16-C01')).innerText();
    ok('헤더도 "이번 주" 라고 말한다', head.includes('마지막 소식 · 이번 주'), head.slice(0, 200));
  }

  console.log('\n[2] 이번 주 행이 없으면 "지난주" 라고 부른다 (월요일 아침의 기본 상태)');
  let s2 = await seed([1]);
  await go(s2.demo);
  {
    const t = await page.locator(u('P16-C06')).innerText();
    ok('카드 제목이 "지난주 일정"', t.startsWith('지난주 일정'), t.slice(0, 120));
    ok('"이번 주" 라고 안 한다', !t.includes('이번 주'), t.slice(0, 200));
    /* "1일이 남았습니다" 는 끝난 주에 대해 거짓입니다 — 그 날들은
       이미 지나갔고 기회가 남아 있지 않습니다. */
    ok('끝난 주에 "남았습니다" 라고 안 한다', !t.includes('남았습니다'), t.slice(0, 200));
    ok('숫자 자체는 그대로 보인다', t.includes('계획 4일 · 지킴 2일'), t.slice(0, 200));
    const head = await page.locator(u('P16-C01')).innerText();
    ok('헤더가 "1주 전" 이라고 말한다', head.includes('마지막 소식 · 지난주'), head.slice(0, 200));
  }

  console.log('\n[3] 세 주 전 행이면 "3주 전"');
  let s3 = await seed([3]);
  await go(s3.demo);
  {
    const t = await page.locator(u('P16-C06')).innerText();
    ok('카드 제목이 "3주 전 일정"', t.startsWith('3주 전 일정'), t.slice(0, 120));
  }

  console.log('\n[4] 친구 목록 줄도 같은 주 이름을 쓴다');
  {
    await page.evaluate(() => window.MB_APP.go('P15'));
    await page.waitForTimeout(350);
    const t = await page.locator(u('P15-L01')).innerText();
    ok('목록에서도 "3주 전 계획" 이라고 적는다',
       t.includes('3주 전 계획 4일'), t.slice(0, 300));
    ok('목록이 "이번 주" 라고 안 한다', !t.includes('이번 주 계획'), t.slice(0, 300));
  }

  console.log('\n[5] 이번 주 것이 안 올라왔을 때와 계획이 없을 때를 구분한다');
  {
    /* 일정 공유는 켜져 있는데 그 행에 일정 숫자가 없는 경우.
       "이번 주에 적은 일정이 없습니다" 는 이번 주 행이 있을 때만 참입니다. */
    // 지난주 행만, 그것도 일정 숫자 없이
    const s5 = await seed([1], { checkedIn: true });
    await go(s5.demo);
    const has22 = await page.locator(u('P16-S22')).count();
    if (has22) {
      const t = await page.locator(u('P16-S22')).innerText();
      ok('"아직 안 올라왔습니다" 라고 말한다', t.includes('아직 안 올라왔습니다'), t.slice(0, 250));
      ok('"적은 일정이 없습니다" 라고 단정하지 않는다',
         !t.includes('적은 일정이 없습니다'), t.slice(0, 250));
    } else {
      ok('일정 없음 카드가 나온다', false, '카드가 없습니다');
    }
  }

  console.log('\n[6] 주 경계 — 월요일 0시 5분에도 어제가 "이번 주" 가 되지 않는다');
  {
    /* 경과 시간을 7로 나눠 반올림하던 옛 계산은 여기서 틀렸습니다:
       지난주 월요일부터 6일 23시간 55분은 "0주" 로 반올림됩니다. */
    await ctx.clock.setFixedTime(new Date('2026-09-28T00:05:00'));   // 월요일 새벽
    const s6 = await seed([1]);
    await go(s6.demo);
    const t = await page.locator(u('P16-C06')).innerText();
    ok('월요일 새벽에도 지난주는 지난주', t.startsWith('지난주 일정'), t.slice(0, 150));
  }

  console.log('\n[7] 화면이 콘솔에 오류를 안 낸다');
  ok('페이지 오류 없음', errs.length === 0, errs.slice(0, 3));

  console.log(`\n통과 ${pass} / 실패 ${fail}`);
  await browser.close();
  server.close();
  process.exit(fail ? 1 : 0);
})().catch(e => { console.error(e); process.exit(1); });
