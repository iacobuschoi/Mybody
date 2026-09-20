/* =============================================================================
 * tools/test-e2e.js — 브라우저 두 개가 서버를 통해 친구가 되는지 확인
 *
 * 이 테스트가 필요한 이유: 여기 오기 전까지 브라우저 앱에는 fetch 가 한 개도
 * 없었습니다. 서버 테스트(test-social.js)는 HTTP 로만 때렸고, 화면 테스트
 * (smoke.js)는 localStorage 만 봤습니다. 둘 다 통과하는데 실제 앱에서는
 * 친구 기능이 한 브라우저 안에서만 작동했습니다.
 *
 * 그 사이를 재는 테스트가 이것입니다 — 진짜 브라우저 두 개, 진짜 서버.
 *   node tools/test-e2e.js
 * ========================================================================== */
'use strict';
const { spawn } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { chromium } = require(process.env.NODE_PATH
  ? path.join(process.env.NODE_PATH, 'playwright')
  : 'playwright');

const PORT = 8600 + Math.floor(Math.random() * 300);
const PAIR = 'e2e-pair-secret';
const DB = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'mybody-e2e-')), 'e2e.db');
const BASE = `http://localhost:${PORT}`;

let pass = 0, fail = 0;
const ok = (n, c, d) => {
  if (c) { pass++; console.log('  ✓', n); }
  else { fail++; console.log('  ✗', n, d === undefined ? '' : JSON.stringify(d)); }
};

async function waitUp(ms = 8000) {
  const until = Date.now() + ms;
  while (Date.now() < until) {
    try { if ((await fetch(BASE + '/health')).ok) return true; } catch {}
    await new Promise(r => setTimeout(r, 120));
  }
  throw new Error('서버가 뜨지 않습니다');
}

/** 한 "기기" = 브라우저 컨텍스트 하나. localStorage 가 서로 완전히 분리됩니다. */
async function device(browser, label) {
  const ctx = await browser.newContext({ viewport: { width: 420, height: 900 } });
  const page = await ctx.newPage();
  const errs = [];
  page.on('pageerror', e => errs.push(label + ': ' + e.message));
  page.on('console', m => { if (m.type() === 'error') errs.push(label + ' CONSOLE: ' + m.text().slice(0, 160)); });
  await page.goto(BASE + '/', { waitUntil: 'load' });
  await page.waitForTimeout(500);
  return { ctx, page, errs, label };
}

const ev = (d, fn, arg) => d.page.evaluate(fn, arg);

async function main() {
  const browser = await chromium.launch({ executablePath: process.env.CHROME ||
    '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const A = await device(browser, '가영폰');
  const B = await device(browser, '나린폰');

  console.log('\n[1] 서버가 앱을 서빙하는가');
  ok('앱이 로드됨', await ev(A, () => !!window.MB_APP));
  ok('sync 계층이 있음', await ev(A, () => !!window.MB_SYNC));
  ok('서버 주소를 자동으로 잡음',
     (await ev(A, () => window.MB_SYNC.status().baseUrl)) === BASE,
     await ev(A, () => window.MB_SYNC.status().baseUrl));

  console.log('\n[2] 계정 만들기 — 우리 서버에서');
  const bad = await ev(A, () => window.MB_SYNC.signUp({
    handle: 'gayoung', password: 'short', pairSecret: 'e2e-pair-secret' })
    .then(() => null).catch(e => e.message));
  ok('짧은 비밀번호 거부', /8자/.test(bad || ''), bad);

  const noPair = await ev(A, () => window.MB_SYNC.signUp({
    handle: 'gayoung', password: 'correct-horse-1', pairSecret: 'wrong' })
    .then(() => null).catch(e => e.message));
  ok('가입 코드 없이는 불가', /가입 코드/.test(noPair || ''), noPair);

  /* 동의 없이는 계정이 안 만들어집니다 — 화면이 실수로 통과시켜도 서버가 막습니다. */
  const noConsent = await ev(A, () => window.MB_SYNC.signUp({
    handle: 'gayoung', password: 'correct-horse-1', displayName: '가영',
    pairSecret: 'e2e-pair-secret' }).then(() => null).catch(e => e.message));
  ok('건강정보 동의 없이는 가입 불가', /동의/.test(noConsent || ''), noConsent);

  const rA = await ev(A, () => window.MB_SYNC.signUp({
    handle: 'gayoung', password: 'correct-horse-1', displayName: '가영',
    pairSecret: 'e2e-pair-secret', healthConsent: true })
    .then(r => r.user).catch(e => ({ err: e.message })));
  ok('가영 가입', !!rA.inviteCode, rA);

  const rB = await ev(B, () => window.MB_SYNC.signUp({
    handle: 'narin', password: 'correct-horse-2', displayName: '나린',
    pairSecret: 'e2e-pair-secret', healthConsent: true })
    .then(r => r.user).catch(e => ({ err: e.message })));
  ok('나린 가입', !!rB.inviteCode, rB);
  ok('초대 코드가 서로 다름', rA.inviteCode !== rB.inviteCode);

  console.log('\n[3] 비밀번호 로그인');
  const wrong = await ev(A, () => window.MB_SYNC.signIn({ handle: 'gayoung', password: 'nope-nope-1' })
    .then(() => null).catch(e => e.message));
  ok('틀린 비밀번호 거부', /맞지 않습니다/.test(wrong || ''), wrong);
  const right = await ev(A, () => window.MB_SYNC.signIn({ handle: 'gayoung', password: 'correct-horse-1' })
    .then(r => r.user.id).catch(e => ({ err: e.message })));
  ok('맞는 비밀번호로 로그인', right === rA.id, right);

  console.log('\n[4] 다른 기기끼리 친구가 되는가  ← 핵심');
  const sent = await ev(A, code => window.MB_SYNC.sendRequest(code)
    .then(() => 'ok').catch(e => e.message), rB.inviteCode);
  ok('초대 코드로 요청 전송', sent === 'ok', sent);
  await A.page.waitForTimeout(700);
  await ev(B, () => window.MB_SYNC.pull());
  await B.page.waitForTimeout(500);

  const incoming = await ev(B, () => window.MB_BACKEND.listFriends().incoming.map(x => x.displayName));
  ok('나린 폰에 가영의 요청이 도착', incoming.length === 1 && incoming[0] === '가영', incoming);

  /* 보낸 쪽에도 보여야 합니다.
     서버는 outgoing 으로 돌려주는데 로컬 거울이 그 상태를 몰라서
     조용히 버렸습니다 — 보낸 사람 화면에는 아무 일도 안 일어난 것처럼
     보였고, 잘못 보낸 요청을 물릴 방법도 없었습니다. */
  await ev(A, () => window.MB_SYNC.pull());
  await A.page.waitForTimeout(500);
  const outgoing = await ev(A, () => window.MB_BACKEND.listFriends().outgoing.map(x => x.displayName));
  ok('가영 폰에 "보낸 요청" 으로 남아 있다', outgoing.length === 1 && outgoing[0] === '나린', outgoing);
  const outUi = await ev(A, () => {
    window.MB_APP.go('P15');
    return new Promise(r => setTimeout(() => {
      const el = document.querySelector('[data-uid="P15-L03"]');
      r(el ? el.innerText : '');
    }, 350));
  });
  ok('친구 탭에 보낸 요청 카드가 뜬다', /보낸 요청 1건/.test(outUi), outUi.slice(0, 120));
  ok('취소할 수 있다', await A.page.locator('[data-uid="P15-B28#1"]').count().then(n => n > 0));

  await ev(B, id => window.MB_BACKEND.accept(id), rA.id);
  await ev(B, () => window.MB_SYNC.flush());
  await B.page.waitForTimeout(700);
  await ev(A, () => window.MB_SYNC.pull());
  await A.page.waitForTimeout(500);

  ok('가영 폰에도 친구로 보임',
     (await ev(A, () => window.MB_BACKEND.listFriends().accepted.map(x => x.displayName))).includes('나린'));
  ok('나린 폰에도 친구로 보임',
     (await ev(B, () => window.MB_BACKEND.listFriends().accepted.map(x => x.displayName))).includes('가영'));

  console.log('\n[5] 공유 설정이 상대 화면에 실제로 반영되는가');
  await ev(B, () => { window.MB_STORE.seed(); window.MB_STORE.publishWeekly(); });
  await ev(B, () => window.MB_SYNC.flush());
  await B.page.waitForTimeout(700);
  await ev(A, () => window.MB_SYNC.pull());
  await A.page.waitForTimeout(500);

  let row = await ev(A, id => {
    const r = window.MB_BACKEND.getFriendSnapshots(id, 26);
    return r.rows[0] || null;
  }, rB.id);
  ok('기본값에서는 몸 정보가 없다',
     !row || (!('dWeightKg' in row) && !('dBfmKg' in row) && !('weightKg' in row)), row);

  await ev(B, id => window.MB_BACKEND.setShare(id, { bfmTrend: true }), rA.id);
  await ev(B, () => window.MB_SYNC.flush());
  await B.page.waitForTimeout(700);
  await ev(A, () => window.MB_SYNC.pull());
  await A.page.waitForTimeout(500);

  row = await ev(A, id => {
    const r = window.MB_BACKEND.getFriendSnapshots(id, 26);
    return r.rows[0] || null;
  }, rB.id);
  ok('나린이 켠 항목이 가영 화면에 나타남', !!row && ('dBfmKg' in row), row);
  ok('안 켠 항목은 여전히 없음', !!row && !('dWeightKg' in row) && !('weightKg' in row), row);

  /* 큐가 흔들릴 때 엉뚱한 작업이 지워지던 버그는 tools/test-syncqueue.js 가
     봅니다. 여기서도 해 봤지만, 요청이 날아가 있는 창을 브라우저에서
     정확히 여는 것이 안 돼서 고치기 전 코드로도 통과했습니다 — 못 잡는
     시험을 두면 없는 것보다 나쁩니다. fetch 를 직접 붙잡는 쪽으로 옮겼습니다. */

  /* --------------------------------------------------------------------
   * [5-3] 운동 일정이 친구 화면에 "확인"으로 닿는가
   *
   * 사용자 요청: "친구가 운동하기로했는데 안했으면 확인할수있게".
   * 여기서 확인은 **보는 것**입니다. 그래서 이 시험은 두 가지를 같이
   * 봅니다 — 숫자가 닿는가, 그리고 **찌를 수 있는 버튼이 안 생겼는가.**
   * 두 번째가 첫 번째만큼 중요합니다.
   * ------------------------------------------------------------------ */
  console.log('\n[5-3] 운동 일정이 친구 화면에 닿는가');
  {
    await ev(B, () => {
      const S = window.MB_STORE, W = window.MB_SCHED, T = S.dayKey();
      const mon = S.weekStartOf();
      /* 이번 주 월·수·금·일 계획, 월요일만 지킴. 요일을 직접 찍어야
         오늘이 무슨 요일이든 "계획 4 · 지킴 1" 이 나옵니다. */
      [0, 2, 4, 6].forEach(i => S.setSchedulePlan(W.shiftKey(mon, i), 'gym', true));
      S.setScheduleDone(W.shiftKey(mon, 0), 'gym', true);
      S.publishWeekly();
    });
    await ev(B, () => window.MB_SYNC.flush());
    await B.page.waitForTimeout(700);
    await ev(A, () => window.MB_SYNC.pull());
    await A.page.waitForTimeout(500);

    const row = await ev(A, id => window.MB_BACKEND.getFriendSnapshots(id, 4).rows[0] || null, rB.id);
    ok('일정 숫자가 건너간다', row && row.plannedDays === 4 && row.keptDays === 1, row);
    ok('요일은 안 건너간다', row && !('days' in row) && !('schedule' in row), row);
    ok('종목도 안 건너간다', row && !('gym' in row) && !('cardio' in row), row);

    await ev(A, id => window.MB_APP.go('P16', { friendId: id }), rB.id);
    await A.page.waitForTimeout(450);
    const card = A.page.locator('[data-uid="P16-C06"]');
    ok('친구 화면에 이번 주 일정 카드가 있다', await card.count() === 1);
    const txt = await card.count() ? await card.innerText() : '';
    ok('계획과 지킴이 숫자로 적혀 있다', /계획 4일/.test(txt) && /지킴 1일/.test(txt), txt);
    ok('퍼센트를 쓰지 않는다', !/%/.test(txt), txt);
    ok('"미달성" 같은 말을 쓰지 않는다', !/미달성|실패|안 했|게으/.test(txt), txt);
    ok('앱이 아는 것의 한계를 적는다', /체크를 안 눌렀을 수도/.test(txt), txt);

    /* 이 카드 안에 누를 수 있는 것이 하나도 없어야 합니다. 찌르기·응원·
       리마인드 버튼이 생기면 "확인"이 "간섭"이 됩니다. */
    const clickables = await card.count()
      ? await card.locator('button, a, [data-clickable]').count() : -1;
    ok('카드 안에 누를 수 있는 것이 하나도 없다', clickables === 0, clickables);

    /* 홈에는 친구 숫자가 올라오지 않습니다 — 하루에 여러 번 보는 화면에
       남의 수행도가 있으면 확인이 아니라 상시 감시가 됩니다. */
    await ev(A, () => window.MB_APP.go('P02'));
    await A.page.waitForTimeout(400);
    const home = await A.page.locator('.main').innerText();
    ok('홈에는 친구 이름도 친구 숫자도 없다', !home.includes(rB.displayName), home.slice(0, 200));

    /* 끄면 사라져야 합니다. 껐는데 남아 있으면 이 화면의 약속이 깨집니다. */
    await ev(B, id => window.MB_BACKEND.setShare(id, { schedule: false }), rA.id);
    await ev(B, () => window.MB_SYNC.flush());
    await B.page.waitForTimeout(700);
    await ev(A, () => window.MB_SYNC.pull());
    await A.page.waitForTimeout(500);
    await ev(A, id => window.MB_APP.go('P16', { friendId: id }), rB.id);
    await A.page.waitForTimeout(450);
    ok('나린이 일정 공유를 끄면 카드가 사라진다',
       await A.page.locator('[data-uid="P16-C06"]').count() === 0);
    ok('"비공개" 같은 대체 표시도 남기지 않는다',
       await A.page.locator('[data-uid="P16-S22"]').count() === 0);
    await ev(B, id => window.MB_BACKEND.setShare(id, { schedule: true }), rA.id);
    await ev(B, () => window.MB_SYNC.flush());
    await B.page.waitForTimeout(600);
  }

  /* --------------------------------------------------------------------
   * [5-2] 프로필 사진이 상대 화면에 실제로 뜨는가
   *
   * 화면 없이 API 로만 보면, 서버에는 잘 저장되는데 친구 목록에는
   * 영영 안 그려지는 상태로도 전부 통과합니다. 사진 기능에서 사용자가
   * 원하는 것은 "저장됐다"가 아니라 "친구 화면에 내 얼굴이 뜬다" 입니다.
   * ------------------------------------------------------------------ */
  console.log('\n[5-2] 프로필 사진이 상대 화면에 뜨는가');
  {
    /* 진짜 사진을 캔버스로 만들어 photo.js 의 축소·EXIF 제거 경로를
       그대로 지나가게 합니다. 파일 고르기 대화상자는 브라우저가 띄우므로
       거기만 건너뛰고, 나머지는 사용자와 같은 길입니다. */
    const made = await ev(B, () => new Promise(res => {
      const c = document.createElement('canvas');
      c.width = 600; c.height = 900;               // 세로로 긴 사진 — 정사각 자르기를 시험
      const g = c.getContext('2d');
      g.fillStyle = '#2f7de1'; g.fillRect(0, 0, 600, 900);
      g.fillStyle = '#fff'; g.fillRect(150, 300, 300, 300);
      window.MB_PHOTO.avatarFromDataUrl(c.toDataURL('image/png'), (err, out) => {
        if (err) return res({ err: err.message });
        window.MB_BACKEND.updateProfile({ avatar: out.dataUrl });
        res({ bytes: out.bytes, head: out.dataUrl.slice(0, 22) });
      });
    }));
    ok('사진이 만들어졌다', !made.err, made);
    ok('JPEG 로 바뀐다 (PNG 를 넣어도)', made.head === 'data:image/jpeg;base64,'.slice(0, 22), made.head);
    ok('24KB 안에 들어온다', made.bytes > 0 && made.bytes <= 24 * 1024, made.bytes);

    await ev(B, () => window.MB_SYNC.flush());
    await B.page.waitForTimeout(700);
    await ev(A, () => window.MB_SYNC.pull());
    await A.page.waitForTimeout(500);
    await ev(A, () => window.MB_APP.go('P15'));
    await A.page.waitForTimeout(400);

    const seen = await A.page.locator('[data-uid^="P15-C22"] .avatar__img').count();
    ok('가영 친구 목록에 나린 사진이 그려진다', seen >= 1, seen);
    const src = seen ? await A.page.locator('[data-uid^="P15-C22"] .avatar__img').first()
      .getAttribute('src') : '';
    ok('그려진 것이 그 사진이다', (src || '').startsWith('data:image/jpeg;base64,'));

    /* 지우면 상대 화면에서도 사라져야 합니다. 서버에서만 지워지고
       친구 화면에 남으면, 지웠다고 믿는 사람에게 거짓말이 됩니다. */
    await ev(B, () => window.MB_BACKEND.updateProfile({ avatar: null }));
    await ev(B, () => window.MB_SYNC.flush());
    await B.page.waitForTimeout(700);
    await ev(A, () => window.MB_SYNC.pull());
    await A.page.waitForTimeout(500);
    await ev(A, () => window.MB_APP.go('P15'));
    await A.page.waitForTimeout(400);
    ok('지우면 상대 화면에서도 사라진다',
       await A.page.locator('[data-uid^="P15-C22"] .avatar__img').count() === 0);
    ok('대신 이름 첫 글자가 남는다',
       await A.page.locator('[data-uid^="P15-C22"] .avatar--letter').count() >= 1);
  }

  /* --------------------------------------------------------------------
   * [6] 비밀번호를 잊은 사람이 실제로 돌아오는가 — 화면을 눌러서
   *
   * 서버 쪽은 test-hardening 이 봅니다. 여기서 봐야 하는 것은 화면입니다:
   * 복구 코드가 가입 직후 눈앞에 뜨는가, 실수로 닫아 잃을 수 없는가,
   * "비밀번호 잊음" 길이 실제로 계정을 되돌려 주는가.
   *
   * 여기를 화면 없이 API 로만 확인하면, 코드가 서버에서 잘 만들어지는데
   * 사용자는 그걸 한 번도 못 보는 상태로도 전부 통과합니다.
   * ------------------------------------------------------------------ */
  console.log('\n[6] 비밀번호를 잊으면 돌아올 수 있는가 (화면)');
  {
    const C = await device(browser, '다솜폰');
    const click = (d, uid) => d.page.click(`[data-uid="${uid}"]`);
    const fill  = (d, uid, v) => d.page.fill(`[data-uid="${uid}"]`, v);
    const seen  = (d, uid) => d.page.locator(`[data-uid="${uid}"]`).count().then(n => n > 0);

    await ev(C, () => window.MB_APP.go('P14'));
    await C.page.waitForTimeout(200);
    await click(C, 'P14-B01');                       // 로그인 / 가입
    await click(C, 'M29-B11');                       // 처음이에요
    await fill(C, 'M29-F01', 'dasom');
    await fill(C, 'M29-F02', 'dasom-password-1');
    await fill(C, 'M29-F03', 'dasom-password-1');
    await fill(C, 'M29-F04', '다솜');
    await fill(C, 'M29-F05', PAIR);

    /* 건강정보 별도 동의를 안 하면 가입이 안 됩니다 — 체크박스가 실제로
       문을 막는지, 그냥 장식인지를 봅니다. */
    await click(C, 'M29-B02');                       // 동의 없이 계속
    await C.page.waitForTimeout(500);
    ok('동의 전에는 가입이 안 된다', !(await seen(C, 'M49')));
    ok('무엇이 모자란지 말해 준다',
       /동의/.test(await ev(C, () => {
         const e = document.querySelector('[data-uid="M29"] .field__err');
         return e ? e.textContent : '';
       })));

    await click(C, 'M29-B14');                       // 동의합니다
    await click(C, 'M29-B02');                       // 계속
    await C.page.waitForSelector('[data-uid="M49"]', { timeout: 8000 }).catch(() => {});
    ok('가입하면 복구 코드가 눈앞에 뜬다', await seen(C, 'M49'));

    const code1 = (await ev(C, () => {
      const m = document.querySelector('[data-uid="M49"]');
      const t = m ? m.innerText.match(/[A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{4}/) : null;
      return t ? t[0] : null;
    })) || '';
    ok('코드가 화면에 읽을 수 있게 적혀 있다', /^[A-HJ-NP-Z2-9]{4}(-[A-HJ-NP-Z2-9]{4}){3}$/.test(code1), code1);

    // 실수로 닫아서 잃는 길이 없어야 합니다
    ok('✕ 가 없다', !(await seen(C, 'M49-B99')));
    await C.page.keyboard.press('Escape');
    await C.page.waitForTimeout(150);
    ok('Esc 로 안 닫힌다', await seen(C, 'M49'));
    /* 눌러 보는 대신 "눌리지 않는 상태인가" 를 봅니다. 꺼진 버튼은
       브라우저가 click 이벤트를 아예 안 보내므로, 눌러서 확인하려 들면
       테스트가 30초를 기다리다 죽습니다. */
    ok('적어 두기 전에는 닫기 버튼이 꺼져 있다',
       await C.page.locator('[data-uid="M49-B01"]').isDisabled());
    await click(C, 'M49-B11');                       // 적어 뒀습니다
    ok('적어 뒀다고 하면 켜진다',
       await C.page.locator('[data-uid="M49-B01"]').isEnabled());
    await click(C, 'M49-B01');
    await C.page.waitForTimeout(250);
    ok('적어 뒀다고 하면 닫힌다', !(await seen(C, 'M49')));

    // 이제 비밀번호를 잊습니다
    await ev(C, () => window.MB_SYNC.signOut());
    await C.page.waitForTimeout(400);
    await ev(C, () => window.MB_APP.go('P14'));
    await C.page.waitForTimeout(200);
    await click(C, 'P14-B01');
    await click(C, 'M29-B12');                       // 비밀번호 잊음
    ok('복구 코드 칸이 나온다', await seen(C, 'M29-F06'));

    await fill(C, 'M29-F01', 'dasom');
    await fill(C, 'M29-F06', 'AAAA-BBBB-CCCC-DDDD');
    await fill(C, 'M29-F02', 'dasom-password-2');
    await fill(C, 'M29-F03', 'dasom-password-2');
    await click(C, 'M29-B02');
    await C.page.waitForTimeout(900);
    const errText = await ev(C, () => {
      const e = document.querySelector('[data-uid="M29"] .field__err');
      return e ? e.textContent : '';
    });
    ok('틀린 코드는 화면에서도 거부된다', /맞지 않습니다/.test(errText), errText);

    // 사람이 옮겨 적은 모양 그대로 (소문자)
    await fill(C, 'M29-F06', code1.toLowerCase());
    await click(C, 'M29-B02');
    await C.page.waitForSelector('[data-uid="M49"]', { timeout: 8000 }).catch(() => {});
    ok('맞는 코드로 되찾으면 새 코드가 뜬다', await seen(C, 'M49'));
    const code2 = (await ev(C, () => {
      const m = document.querySelector('[data-uid="M49"]');
      const t = m ? m.innerText.match(/[A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{4}/) : null;
      return t ? t[0] : null;
    })) || '';
    ok('새 코드는 옛 코드와 다르다', !!code2 && code2 !== code1, { code1, code2 });
    await click(C, 'M49-B11');
    await click(C, 'M49-B01');
    await C.page.waitForTimeout(300);

    ok('되찾은 뒤 로그인 상태다', await ev(C, () => window.MB_SYNC.status().signedIn));
    const relog = await ev(C, () => window.MB_SYNC.signIn({ handle: 'dasom', password: 'dasom-password-2' })
      .then(r => r.user.displayName).catch(e => ({ err: e.message })));
    ok('새 비밀번호로 다시 들어가진다', relog === '다솜', relog);

    // 계정 화면에서 코드를 새로 받는 길
    await ev(C, () => window.MB_APP.go('P14'));
    await C.page.waitForTimeout(250);
    ok('계정 화면에 코드 새로 받기가 있다', await seen(C, 'P14-B08'));
    await click(C, 'P14-B08');
    await fill(C, 'M50-F01', 'dasom-password-2');
    await click(C, 'M50-B02');
    await C.page.waitForSelector('[data-uid="M49"]', { timeout: 8000 }).catch(() => {});
    ok('비밀번호를 대면 새 코드가 나온다', await seen(C, 'M49'));
    const code3 = (await ev(C, () => {
      const m = document.querySelector('[data-uid="M49"]');
      const t = m ? m.innerText.match(/[A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{4}/) : null;
      return t ? t[0] : null;
    })) || '';
    ok('또 다른 코드가 나온다', !!code3 && code3 !== code2 && code3 !== code1, { code2, code3 });
    await click(C, 'M49-B11');
    await click(C, 'M49-B01');
    await C.page.waitForTimeout(200);

    C.errs.forEach(e => A.errs.push(e));
    await C.ctx.close();
  }

  console.log('\n[7] 오프라인에서도 앱이 멈추지 않는가');
  await A.ctx.setOffline(true);
  const offlineOk = await ev(A, () => {
    try { window.MB_APP.go('P15'); return document.querySelector('#main').innerText.length > 30; }
    catch (e) { return 'ERR: ' + e.message; }
  });
  ok('오프라인에서 친구 탭이 열림', offlineOk === true, offlineOk);
  await ev(A, id => window.MB_BACKEND.setShare(id, { streak: false }), rB.id);
  const queued = await ev(A, () => window.MB_SYNC.status().pending);
  ok('오프라인 변경이 큐에 쌓임', queued > 0, { queued });
  await A.ctx.setOffline(false);
  await ev(A, () => window.MB_SYNC.flush());
  await A.page.waitForTimeout(900);
  ok('온라인이 되면 큐가 비워짐', (await ev(A, () => window.MB_SYNC.status().pending)) === 0);

  console.log('\n[8] 로그아웃하면 이 기기에 남의 흔적이 없는가');
  await ev(A, () => window.MB_SYNC.signOut());
  await A.page.waitForTimeout(400);
  const after = await ev(A, () => ({
    user: window.MB_BACKEND.currentUser(),
    raw: JSON.stringify(window.MB_BACKEND.raw()).length
  }));
  ok('로그아웃 후 계정 없음', after.user === null, after);

  /* 이 테스트는 일부러 실패하는 요청을 보냅니다 — 짧은 비밀번호(400),
     틀린 비밀번호(401), 오프라인(ERR_INTERNET_DISCONNECTED).
     브라우저는 그것도 콘솔 오류로 찍으므로, 예상된 것은 빼고 셉니다.
     실제 JS 예외(pageerror)는 하나도 없어야 합니다. */
  const EXPECTED = /status of (400|401|429)|ERR_INTERNET_DISCONNECTED/;
  const allErrs = [...new Set([...A.errs, ...B.errs])];
  const real = allErrs.filter(e => !EXPECTED.test(e));
  console.log('\n[9] JS 오류');
  ok('예상 못 한 오류 0건', real.length === 0, real.slice(0, 4));
  console.log('    (예상된 오류 ' + (allErrs.length - real.length) + '건은 제외 — 일부러 실패시킨 요청들)');

  await browser.close();
}

const srv = spawn(process.execPath, [path.join(__dirname, '..', 'server', 'server.js')], {
  env: { ...process.env, PORT: String(PORT), DB, PAIR_SECRET: PAIR }, stdio: 'ignore'
});
process.on('exit', () => srv.kill());

waitUp().then(main).then(() => {
  console.log(`\n통과 ${pass} / 실패 ${fail}`);
  srv.kill();
  process.exit(fail ? 1 : 0);
}).catch(e => { console.error(e); srv.kill(); process.exit(1); });
