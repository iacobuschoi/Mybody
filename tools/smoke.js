/* =============================================================================
 * tools/smoke.js — 프로토타입 실제 브라우저 검증
 *
 *   NODE_PATH=/opt/node22/lib/node_modules node tools/smoke.js
 *   SHOT_DIR=/tmp/shots  ...   스크린샷 저장 위치 (기본: tools/.shots)
 *
 * 화면을 전부 돌면서 JS 오류 · 고유번호 규칙 위반 · 빈 화면을 잡는다.
 * ========================================================================== */
const { chromium } = require('playwright');
const http = require('http');
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..', 'prototype');
const OUT = process.env.SHOT_DIR || path.join(__dirname, '.shots');
const PORT = Number(process.env.PORT || 8731);
const CHROME = process.env.CHROME_PATH || '/opt/pw-browsers/chromium-1194/chrome-linux/chrome';
fs.mkdirSync(OUT, { recursive: true });

const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.json': 'application/json', '.svg': 'image/svg+xml' };
const server = http.createServer((req, res) => {
  let p = decodeURIComponent(req.url.split('?')[0]);
  if (p === '/') p = '/index.html';
  const f = path.join(ROOT, p);
  if (!f.startsWith(ROOT) || !fs.existsSync(f) || fs.statSync(f).isDirectory()) {
    res.writeHead(404); return res.end('not found: ' + p);
  }
  res.writeHead(200, { 'Content-Type': MIME[path.extname(f)] || 'application/octet-stream' });
  res.end(fs.readFileSync(f));
});

const SCREENS = ['P01','P02','P03','P04','P05','P06','P07','P08','P09','P10','P11','P12','P13','P14','P15','P16','P18','P19','P20','P21'];
const UID_RE = /^(P\d{2}|M\d{2}|A\d{2})(-[A-Z]\d{2})?(#\d+)?$/;

(async () => {
  await new Promise(r => server.listen(PORT, r));
  const browser = await chromium.launch({ executablePath: CHROME });
  const ctx = await browser.newContext({ viewport: { width: 420, height: 900 }, deviceScaleFactor: 2 });
  const page = await ctx.newPage();

  const errors = [];
  page.on('console', m => {
    if (m.type() !== 'error') return;
    /* 앱은 켜질 때 <서버주소>/health 를 한 번 두드립니다 — 이 주소에
       우리 서버가 있는지 알아야 화면이 사실대로 말할 수 있어서입니다.
       여기 정적 서버에는 /health 가 없으니 404 가 오고, 그게 맞는
       답입니다. 브라우저는 그것도 콘솔 오류로 찍습니다. */
    if (/health|Failed to load resource/.test(m.text())) return;
    errors.push('CONSOLE: ' + m.text().slice(0, 200));
  });
  page.on('pageerror', e => errors.push('PAGEERROR: ' + e.message.slice(0, 200)));

  await page.goto(`http://localhost:${PORT}/`, { waitUntil: 'load' });
  await page.waitForTimeout(400);

  // 오너의 실제 인바디로 시드
  await page.evaluate(() => { window.MB_STORE.seed(); window.MB_APP.go('P02'); });
  await page.waitForTimeout(300);

  const rows = [];
  const uidProblems = [];
  const allUids = new Map();

  for (const id of SCREENS) {
    const before = errors.length;
    const went = await page.evaluate((sid) => {
      try { window.MB_APP.go(sid); return 'ok'; } catch (e) { return 'THROW: ' + e.message; }
    }, id);
    await page.waitForTimeout(420);

    const info = await page.evaluate(() => {
      const s = document.querySelector('.screen.is-active');
      const main = document.getElementById('main');
      const uids = [];
      main.querySelectorAll('[data-uid]').forEach(el => uids.push({
        uid: el.getAttribute('data-uid'),
        label: el.getAttribute('data-uid-label') || '',
        tag: el.tagName.toLowerCase(),
        interactive: /^(button|input|select|textarea|a)$/.test(el.tagName.toLowerCase())
      }));
      return {
        uid: s ? s.getAttribute('data-uid') : null,
        uids,
        badgeCount: main.querySelectorAll('.uid-badge').length,
        textLen: main.innerText.trim().length,
        emptyState: !!main.querySelector('.empty')
      };
    });

    // 고유번호 규칙 검사 (화면이 실제로 바뀐 경우에만 — 미등록 화면은 이전 화면이 남는다)
    const seen = new Set();
    if (info.uid !== id) { rows.push({ id, went, reached: info.uid, n: info.uids.length,
      badges: info.badgeCount, text: info.textLen, empty: info.emptyState,
      newErr: errors.length - before, skipped: true }); continue; }
    for (const u of info.uids) {
      if (!UID_RE.test(u.uid)) uidProblems.push(`${id}: 형식 위반 "${u.uid}"`);
      else if (u.uid.indexOf('-') > 0 && !u.uid.startsWith(id)) {
        uidProblems.push(`${id}: 다른 화면 번호 "${u.uid}"`);
      }
      if (seen.has(u.uid)) uidProblems.push(`${id}: 중복 "${u.uid}"`);
      seen.add(u.uid);
      if (!u.label) uidProblems.push(`${id}: 라벨 없음 "${u.uid}"`);
      allUids.set(u.uid, u.label);
    }

    await page.screenshot({ path: path.join(OUT, id + '.png'), fullPage: true });
    rows.push({ id, went, reached: info.uid, n: info.uids.length, badges: info.badgeCount,
                text: info.textLen, empty: info.emptyState, newErr: errors.length - before });
  }

  // 실제 플로우: 목표 → 강도 → 플랜 → 탭
  const flow = [];
  async function click(uid) {
    return page.evaluate((u) => {
      const b = document.querySelector('[data-uid="' + u + '"]');
      if (!b) return 'not-found';
      b.click(); return 'ok';
    }, uid);
  }
  async function where() {
    return page.evaluate(() => {
      const s = document.querySelector('.screen.is-active');
      return s ? s.getAttribute('data-uid') : null;
    });
  }

  await page.evaluate(() => window.MB_APP.go('P05'));
  await page.waitForTimeout(400);
  flow.push({ step: 'P05-B05 강도 고르기', r: await click('P05-B05') });
  await page.waitForTimeout(500);
  flow.push({ step: '도착', r: await where() });

  flow.push({ step: 'P06-B22 중 선택', r: await click('P06-B22') });
  await page.waitForTimeout(400);
  await page.evaluate(() => { const b = document.querySelector('.modal-backdrop .btn--primary'); if (b) b.click(); });
  await page.waitForTimeout(600);
  flow.push({ step: '도착', r: await where() });

  for (const t of ['P07-T02', 'P07-T03', 'P07-T01']) {
    flow.push({ step: t, r: await click(t) });
    await page.waitForTimeout(350);
    await page.screenshot({ path: path.join(OUT, 'flow-' + t + '.png'), fullPage: true });
  }

  // 판독(OCR) 경로: 샘플 판독 → P04 검수. 일부러 틀리게 읽은 값을 화면이 잡아내는지 본다.
  let ocr = { ran: false };
  await page.evaluate(() => window.MB_APP.go('P03'));
  await page.waitForTimeout(400);
  const parseClick = await click('P03-B03');
  if (parseClick === 'ok') {
    await page.waitForTimeout(6000);
    ocr = await page.evaluate(() => {
      const s = document.querySelector('.screen.is-active');
      const main = document.getElementById('main');
      const txt = main.innerText;
      // 점의 뜻이 바뀌었습니다: OCR 신뢰도가 아니라 검산 상태입니다.
      const bad = main.querySelectorAll('.dot-conf.ck-bad').length;
      const none = main.querySelectorAll('.dot-conf.ck-none').length;
      const ok = main.querySelectorAll('.dot-conf.ck-ok').length;
      const vals = {};
      main.querySelectorAll('input').forEach(i => {
        const u = i.getAttribute('data-uid'); if (u) vals[u] = i.value;
      });
      const fieldErrs = [];
      main.querySelectorAll('.field__err').forEach(e => {
        if (e.textContent.trim() && e.style.display !== 'none') {
          const row = e.closest('.field') || e.parentElement;
          const inp = row ? row.querySelector('input') : null;
          fieldErrs.push((inp && inp.getAttribute('data-uid') || '?') + ': ' + e.textContent.trim().slice(0, 60));
        }
      });
      return { ran: true, screen: s ? s.getAttribute('data-uid') : null,
               dots: { 모순: bad, 미검산: none, 검산됨: ok }, fieldErrs,
               flagsWhr: txt.indexOf('0.34') >= 0 || txt.indexOf('복부지방률') >= 0,
               warnCount: main.querySelectorAll('.note--warn, .note--bad').length,
               values: vals };
    });
    await page.screenshot({ path: path.join(OUT, 'ocr-P04.png'), fullPage: true });
  }

  // 플랜이 생긴 뒤 화면들을 한 번 더 (빈 상태가 아닌 본 모습)
  for (const id of ['P02', 'P07', 'P08', 'P09']) {
    await page.evaluate((s) => window.MB_APP.go(s), id);
    await page.waitForTimeout(450);
    await page.screenshot({ path: path.join(OUT, 'withplan-' + id + '.png'), fullPage: true });
  }

  const planInfo = await page.evaluate(() => {
    const st = window.MB_STORE.get();
    return st.plan ? {
      level: st.plan.label, weeks: st.plan.weeks, targetDate: st.plan.targetDate,
      strategy: st.plan.strategyLabel, kcal: st.plan.macros.intakeKcal,
      protein: st.plan.macros.proteinG, days: st.plan.workout.daysPerWeek,
      milestones: st.plan.milestones.length
    } : null;
  });

  const uidInfo = await page.evaluate(() => {
    window.MB_UID.toggle(false);
    const b = document.querySelector('.uid-badge');
    const hidden = b ? getComputedStyle(b).display === 'none' : null;
    window.MB_UID.toggle(true);
    return { offHides: hidden, liveIndex: window.MB_UID.liveIndex().length };
  });

  /* ── 소셜 2차 패스 ───────────────────────────────────────────────
     1차 패스는 로그아웃 상태입니다 — 신규 설치의 기본 상태이고, 지금까지
     친구 화면이 자동 검증된 유일한 상태였습니다. 문제는 그게 "로그인이
     필요합니다" 빈 화면만 찍고 통과했다는 것입니다. 친구가 실제로 있는
     화면은 한 번도 검증된 적이 없습니다. ------------------------------- */
  const socialProblems = [];
  const social = await page.evaluate(() => {
    window.MB_BACKEND.reset();
    const u = window.MB_BACKEND.signIn({ provider: 'kakao' });
    window.MB_STORE.publishWeekly();
    window.MB_APP.go('P15');
    const d = window.MB_SOCIAL.makeDemoFriend();
    window.MB_APP.refresh();
    return { me: u.id, demo: d && d.id, session: window.MB_BACKEND.currentUser().id };
  });
  await page.waitForTimeout(400);

  // 데모 친구를 만드는 동안 세션이 데모로 바뀌었다가 반드시 돌아와야 합니다.
  if (social.session !== social.me) socialProblems.push('데모 친구 생성 후 세션이 안 돌아옴');
  if (!social.demo) socialProblems.push('데모 친구 생성 실패');

  const SOCIAL_CASES = [
    { name: 'P15 친구1명', go: () => window.MB_APP.go('P15') },
    { name: 'P16 친구상세', go: (d) => window.MB_APP.go('P16', { friendId: d }) },
    { name: 'P16 없는친구', go: () => window.MB_APP.go('P16', { friendId: 'nope_999' }) }
  ];
  for (let i = 0; i < SOCIAL_CASES.length; i++) {
    const before = errors.length;
    await page.evaluate(([idx, demo]) => {
      const F = [
        () => window.MB_APP.go('P15'),
        () => window.MB_APP.go('P16', { friendId: demo }),
        () => window.MB_APP.go('P16', { friendId: 'nope_999' })
      ];
      F[idx]();
    }, [i, social.demo]);
    await page.waitForTimeout(350);
    const info = await page.evaluate(() => ({
      title: document.getElementById('appbar-title').textContent,
      text: document.querySelector('#main').innerText.length,
      // 누를 수 있는데 번호가 없는 카드 — 사용자의 유일한 피드백 수단이 빠진 자리
      noUid: document.querySelectorAll('#main .card[data-clickable]:not([data-uid])').length,
      uids: [...document.querySelectorAll('#main [data-uid]')].map(e => e.getAttribute('data-uid'))
    }));
    await page.screenshot({ path: path.join(OUT, 'social-' + i + '.png'), fullPage: true });
    console.log('  ' + SOCIAL_CASES[i].name.padEnd(14) +
                ' 제목=' + info.title.padEnd(8) + ' 글자=' + String(info.text).padStart(5) +
                ' 번호없는카드=' + info.noUid + ' 오류=' + (errors.length - before));
    if (info.noUid) socialProblems.push(SOCIAL_CASES[i].name + ': 번호 없는 클릭 카드 ' + info.noUid + '개');
    info.uids.forEach(u => {
      const bare = u.split('#')[0];
      if (!UID_RE.test(u)) socialProblems.push(SOCIAL_CASES[i].name + ': 형식 위반 ' + u);
      allUids.set(bare, allUids.get(bare) || '');
    });
  }
  // 없는 친구로 들어가면 앱바에 이전 친구 이름이 남으면 안 됩니다
  const ghostTitle = await page.evaluate(() => document.getElementById('appbar-title').textContent);
  if (ghostTitle === '데모친구') socialProblems.push('없는 친구 화면에 이전 친구 이름이 남음');

  if (socialProblems.length) {
    console.log('\n=== 소셜 문제 ' + socialProblems.length + '건 ===');
    socialProblems.forEach(p => console.log('  ' + p));
  } else console.log('\n소셜 화면 문제 없음');


  /* --- 다시 그려도 배지가 남는가 ---------------------------------------
   * app.js 는 화면을 바꿀 때 한 번 scan(main) 을 부릅니다. 화면 안에서
   * draw() 로 본문을 갈아 끼우는 곳들(목표 설정 · 인바디 넣기 · 식단 ·
   * 검수)에서는 배지가 통째로 날아갔습니다. 몇몇 화면은 자기가 scan 을
   * 다시 불렀는데, 그건 "새 화면마다 기억해야 하는 규칙" 이라 언젠가
   * 빠집니다 — P05 에서 실제로 빠져 있었고 21개가 1개로 줄었습니다.
   * 지금은 uid.js 가 본문을 지켜봅니다. 그게 계속 도는지 확인합니다. */
  const badgeRows = [];
  for (const [sid, uid] of [['P05', 'P05-B01'], ['P03', 'P03-B02'],
                            ['P18', 'P18-B09'], ['P04', 'P04-F01']]) {
    await page.evaluate(s2 => window.MB_APP.go(s2), sid);
    await page.waitForTimeout(400);
    const before = await page.evaluate(() => document.querySelectorAll('#main .uid-badge').length);
    await page.evaluate(u => {
      const e = document.querySelector('#main [data-uid="' + u + '"]');
      if (!e) return;
      if (e.tagName === 'INPUT') { e.value = '42'; e.dispatchEvent(new Event('input', { bubbles: true })); }
      else e.click();
    }, uid);
    await page.waitForTimeout(600);
    const after = await page.evaluate(() => document.querySelectorAll('#main .uid-badge').length);
    badgeRows.push({ sid, before, after, ok: after > 0 && after >= Math.min(before, 3) });
    await page.keyboard.press('Escape').catch(() => {});
  }
  const badgeBad = badgeRows.filter(r => !r.ok);
  console.log('\n=== 다시 그린 뒤 배지 ===');
  badgeRows.forEach(r => console.log(`  ${r.ok ? '✓' : '✗'} ${r.sid} ${r.before} → ${r.after}`));
  if (badgeBad.length) uidProblems.push('다시 그린 뒤 배지가 사라짐: ' +
    badgeBad.map(r => r.sid + ' ' + r.before + '→' + r.after).join(', '));

  await browser.close();
  server.close();

  console.log('=== 화면 ===');
  rows.forEach(r => console.log(
    ` ${r.id} ${r.reached === r.id ? '✓' : '✗ →' + r.reached} 요소=${String(r.n).padStart(3)} 배지=${String(r.badges).padStart(3)}` +
    ` 글자=${String(r.text).padStart(5)}${r.empty ? ' [빈상태]' : ''}${r.newErr ? ' 오류+' + r.newErr : ''}` +
    (r.went !== 'ok' ? '  ' + r.went : '')));

  console.log('\n=== 플로우 ===');
  flow.forEach(f => console.log(`  ${f.step}: ${f.r}`));
  console.log('\n=== 플랜 ===\n ', JSON.stringify(planInfo));
  console.log('\n=== 판독 검수 ===\n ', JSON.stringify({
    ran: ocr.ran, screen: ocr.screen, dots: ocr.dots, warnings: ocr.warnCount,
    whr: ocr.values && ocr.values['P04-F09'], smm: ocr.values && ocr.values['P04-F02'],
    weight: ocr.values && ocr.values['P04-F01'] }));
  if (ocr.fieldErrs) { console.log('  필드 경고:'); ocr.fieldErrs.forEach(e => console.log('    ' + e)); }
  console.log('\n=== 고유번호 ===\n ', JSON.stringify(uidInfo), '· 수집', allUids.size, '개');

  if (uidProblems.length) {
    console.log('\n=== 고유번호 문제 ' + uidProblems.length + '건 ===');
    uidProblems.slice(0, 40).forEach(p => console.log('  ' + p));
  } else console.log('\n고유번호 규칙 위반 없음');

  console.log('\n=== JS 오류 ' + errors.length + '건 ===');
  [...new Set(errors)].slice(0, 30).forEach(e => console.log('  ' + e));

  fs.writeFileSync(path.join(OUT, 'uids.json'),
    JSON.stringify([...allUids].map(([uid, label]) => ({ uid, label })), null, 1));

  const failed = errors.length || uidProblems.length || socialProblems.length ||
                 rows.some(r => r.reached !== r.id) || !planInfo;
  console.log('\n' + (failed ? '실패' : '통과'));
  process.exit(failed ? 1 : 0);
})().catch(e => { console.error('FATAL', e); try { server.close(); } catch (_) {} process.exit(2); });
