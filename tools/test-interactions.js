/* =============================================================================
 * tools/test-interactions.js — 누를 수 있는 것을 전부 눌러 본다
 *
 *   NODE_PATH=/opt/node22/lib/node_modules node tools/test-interactions.js
 *   STATES=fresh,full  node tools/test-interactions.js     일부 상태만
 *   ONLY=P03,P04       node tools/test-interactions.js     일부 화면만
 *
 * smoke.js 는 화면을 열어 보고 오류가 없는지만 봅니다. 그건 "화면이 뜬다" 는
 * 확인이지 "쓸 수 있다" 는 확인이 아닙니다. 실제로 망가지는 자리는 버튼을
 * 눌렀을 때이고, 그중에서도 앱이 예상 못 한 상태일 때입니다 — 측정이 없는데
 * 기록 화면, 계획이 없는데 체크인, 로그아웃 상태의 친구 탭 같은 것들.
 *
 * 그래서 여기서는 상태 × 화면 × 요소를 전부 곱해서 하나씩 눌러 봅니다.
 * 누를 때마다 원래 자리로 돌아와서 다음 것을 누릅니다 — 앞의 클릭이 남긴
 * 영향으로 뒤의 결과가 달라지면 무엇이 원인인지 알 수 없기 때문입니다.
 *
 * 무엇을 잡는가
 *   1. JS 오류          — 누르는 순간 터지는 것
 *   2. 무반응           — 눌러도 화면도 모달도 토스트도 안 바뀌는 버튼
 *   3. 막다른 길        — 도착한 곳에서 빠져나올 길이 없는 상태
 *   4. 빈 화면          — 아무 설명도 없이 비어 있는 화면
 *   5. 유령 이동        — 등록되지 않은 화면으로 보내는 버튼
 *
 * 파괴적인 버튼(전체 초기화 · 계정 삭제 · 기록 삭제)은 맨 마지막에, 자기
 * 상태에서만 눌러 봅니다. 중간에 누르면 그 뒤 검사가 전부 빈 상태에서
 * 돌아서 의미가 없어집니다.
 * ========================================================================== */
'use strict';
const { chromium } = require('playwright');
const { spawn } = require('child_process');
const http = require('http');
const os = require('os');
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..', 'prototype');
/* 포트를 0 으로 열면 커널이 빈 포트를 줍니다. 고정 포트를 쓰면
   검증 도구 두 개를 같이 돌릴 때 서로를 막습니다 — 실제로 막혔습니다. */
let PORT = Number(process.env.PORT || 0);
const CHROME = process.env.CHROME_PATH || '/opt/pw-browsers/chromium-1194/chrome-linux/chrome';
const OUT = process.env.SHOT_DIR || path.join(__dirname, '.shots');
fs.mkdirSync(OUT, { recursive: true });

const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css',
               '.json': 'application/json', '.svg': 'image/svg+xml' };
const server = http.createServer((req, res) => {
  let p = decodeURIComponent(req.url.split('?')[0]);
  if (p === '/') p = '/index.html';
  const f = path.join(ROOT, p);
  if (!f.startsWith(ROOT) || !fs.existsSync(f) || fs.statSync(f).isDirectory()) {
    res.writeHead(404); return res.end('not found');
  }
  res.writeHead(200, { 'Content-Type': MIME[path.extname(f)] || 'application/octet-stream' });
  res.end(fs.readFileSync(f));
});

const SCREENS = ['P01','P02','P03','P04','P05','P06','P07','P08','P09','P10',
                 'P11','P12','P13','P14','P15','P16','P18','P19','P20','P21'];

/* 누르면 데이터가 사라지는 것들. 맨 마지막에 따로 돌립니다. */
const DESTRUCTIVE = new Set([
  'P12-B06',  // 전체 초기화
  'P12-B09',  // 피드백 모두 지우기 (설정)
  'P12-B14',  // 사진 모두 지우기
  'P13-B12',  // 메모 모두 지우기 (ID 목록)
  'P14-B06',  // 계정 삭제
  'P11-B02',  // 이 측정 삭제 (상세)
  'P15-B32'   // 데모 친구 지우기
]);

/* 파일 고르기 창을 여는 것들 — 브라우저가 멈춰 버립니다 */
const OPENS_FILE_DIALOG = new Set([
  'P03-B02',  // 파일 선택
  'P03-F01',  // 파일 입력 자체
  'P03-C01',  // 드래그앤드롭 존 — 누르면 파일 입력을 대신 누릅니다
  'P12-B04'   // 데이터 가져오기
]);

/* 상태 만들기. 각각이 실제 사용자가 처할 수 있는 상황입니다. */
const STATES = {
  fresh: {
    label: '설치 직후 (온보딩 전)',
    setup: () => { localStorage.clear(); }
  },
  onboarded: {
    label: '온보딩만 끝냄 (측정 0건)',
    setup: () => {
      localStorage.clear();
      const st = window.MB_STORE.get();
      st.onboarded = true; st.disclaimerAccepted = true;
      st.profile = Object.assign({}, window.MB_DATA.SEED_PROFILE);
      st.scans = []; st.goal = null; st.plan = null;
      window.MB_STORE.save();
    }
  },
  scansOnly: {
    label: '측정은 있고 목표는 없음',
    setup: () => {
      localStorage.clear();
      window.MB_STORE.seed();
      const st = window.MB_STORE.get();
      st.goal = null; st.plan = null;
      window.MB_STORE.save();
    }
  },
  full: {
    label: '측정 · 목표 · 계획 전부 있음',
    setup: () => {
      localStorage.clear();
      window.MB_STORE.seed();
    },
    afterBoot: async (page) => {
      // 계획을 실제로 만들어 둡니다 (P05 → P06 → P07)
      await page.evaluate(() => window.MB_APP.go('P05'));
      await page.waitForTimeout(350);
      await page.evaluate(() => { const b = document.querySelector('[data-uid="P05-B05"]'); if (b) b.click(); });
      await page.waitForTimeout(500);
      await page.evaluate(() => { const b = document.querySelector('[data-uid="P06-B22"]'); if (b) b.click(); });
      await page.waitForTimeout(350);
      await page.evaluate(() => { const b = document.querySelector('.modal-backdrop .btn--primary'); if (b) b.click(); });
      await page.waitForTimeout(600);
    }
  },
  /* 로그인 상태. 서버가 있어야만 만들 수 있습니다.
     이걸 안 돌면 P14(계정) · P15(친구) · P16(친구 한 사람) 이 전부
     로그아웃 화면만 검사됩니다 — 정작 그 화면들의 본 모습은 한 번도
     안 보는 것입니다. 계정 삭제 버튼도 마찬가지고요. */
  /* 로그인 · 친구 있음. 서버가 있어야만 만들 수 있습니다.
     이걸 안 돌면 P14(계정) · P15(친구) · P16(친구 한 사람) 이 전부
     로그아웃 화면만 검사됩니다 — 정작 그 화면들의 본 모습은 한 번도
     안 보는 것입니다. 계정 삭제 버튼도 마찬가지고요.

     "데모 친구" 버튼으로 때우려다 실패했습니다. 데모 친구는 이 기기에만
     있는데, 로그인 상태에서는 boot() 의 pull() 이 서버 기준으로 친구
     목록을 덮어써서 조용히 사라집니다. 그래서 계정을 둘 만들어 서로
     수락시킵니다 — 실제 사용자가 겪는 경로 그대로입니다. */
  signedIn: {
    label: '로그인 · 친구 있음 (서버 필요)',
    needsServer: true,
    setup: () => { localStorage.clear(); window.MB_STORE.seed(); },
    afterBoot: async (page, api) => {
      const PW = 'sweep-password-1';
      const PAIR = 'sweep-pair-secret';
      const post = (p, body, tok) => fetch(api + '/api' + p, {
        method: 'POST',
        headers: Object.assign({ 'content-type': 'application/json' },
                               tok ? { authorization: 'Bearer ' + tok } : {}),
        body: JSON.stringify(body)
      }).then(r => r.json().catch(() => ({})));

      // 상대편 계정은 브라우저를 안 거치고 HTTP 로 만듭니다
      let buddy = await post('/auth/signup',
        { handle: 'buddy', password: PW, displayName: '친구', pairSecret: PAIR,
          healthConsent: '2026-09-20' });
      if (!buddy.token) buddy = await post('/auth/signin', { handle: 'buddy', password: PW });
      const buddyTok = buddy.token;
      const buddyMe = await fetch(api + '/api/me', { headers: { authorization: 'Bearer ' + buddyTok } })
        .then(r => r.json()).catch(() => ({}));
      const buddyCode = buddyMe.user && buddyMe.user.inviteCode;

      // 이쪽은 앱이 하는 대로 브라우저에서
      await page.evaluate(b => window.MB_SYNC.configure(b), api);
      const me = await page.evaluate(async ([pw, pair]) => {
        const r = await window.MB_SYNC.signUp({
          handle: 'sweeper', password: pw, displayName: '검증', pairSecret: pair,
          healthConsent: true
        }).catch(() => window.MB_SYNC.signIn({ handle: 'sweeper', password: pw }));
        return r && r.user ? r.user.id : null;
      }, [PW, PAIR]);
      await page.waitForTimeout(400);

      if (buddyCode && me) {
        await page.evaluate(c => window.MB_SYNC.sendRequest(c), buddyCode);
        await page.waitForTimeout(300);
        await post('/friends/accept', { userId: me }, buddyTok);
        await page.evaluate(() => window.MB_SYNC.pull());
        await page.waitForTimeout(500);
      }
    }
  },

  corrupt: {
    label: '저장소가 깨진 상태',
    setup: () => {
      localStorage.clear();
      // 실제로 일어납니다 — 버전이 안 맞는 예전 데이터, 중간에 잘린 JSON.
      localStorage.setItem('mybody.state.v1', '{"version":1,"scans":[{"id":"x"}],"profile":null');
      localStorage.setItem('mybody.photos.v1', 'not json at all');
      localStorage.setItem('mybody.feedback.v1', '[[[');
    }
  }
};

let errors = [];
const findings = [];
function found(kind, where, detail, extra) {
  findings.push(Object.assign({ kind, where, detail }, extra || {}));
}

const wanted = (process.env.STATES || '').split(',').filter(Boolean);
const onlyScreens = (process.env.ONLY || '').split(',').filter(Boolean);

/* 앱 서버(자가호스팅) — signedIn 상태에서만 씁니다. */
let apiProc = null, apiBase = null;
async function bootApi() {
  const port = 8900 + Math.floor(process.pid % 400);
  const db = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'mb-sweep-')), 'sweep.db');
  apiProc = spawn(process.execPath, [path.join(__dirname, '..', 'server', 'server.js')], {
    env: Object.assign({}, process.env, {
      PORT: String(port), DB: db, PAIR_SECRET: 'sweep-pair-secret'
    }),
    stdio: 'ignore'
  });
  const base = `http://localhost:${port}`;
  const until = Date.now() + 8000;
  while (Date.now() < until) {
    try { if ((await fetch(base + '/health')).ok) { apiBase = base; return base; } } catch {}
    await new Promise(r => setTimeout(r, 120));
  }
  apiProc.kill(); apiProc = null;
  return null;
}

(async () => {
  await new Promise(r => server.listen(PORT, r));
  PORT = server.address().port;
  const browser = await chromium.launch({ executablePath: CHROME });
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 } });
  const page = await ctx.newPage();
  page.on('pageerror', e => errors.push('PAGEERROR: ' + e.message.slice(0, 240)));
  page.on('console', m => { if (m.type() === 'error') errors.push('CONSOLE: ' + m.text().slice(0, 240)); });
  page.on('dialog', d => d.dismiss().catch(() => {}));

  let clicks = 0, screensSeen = 0;

  for (const [key, state] of Object.entries(STATES)) {
    if (wanted.length && !wanted.includes(key)) continue;
    if (state.needsServer && !apiBase) {
      const b = await bootApi();
      if (!b) {
        console.log(`\n=== ${key} — 서버를 띄우지 못해 건너뜀 ===`);
        found('검사못함', key, '서버가 안 떠서 로그인 상태를 한 번도 못 봤습니다');
        continue;
      }
    }
    console.log(`\n=== ${key} · ${state.label} ===`);

    await page.goto(`http://localhost:${PORT}/`, { waitUntil: 'load' });
    await page.waitForTimeout(250);
    await page.evaluate(state.setup);
    await page.reload({ waitUntil: 'load' });
    await page.waitForTimeout(450);
    errors = [];
    if (state.afterBoot) await state.afterBoot(page, apiBase);

    // 이 상태를 그대로 복원할 수 있게 떠 둡니다 — 클릭마다 여기로 되돌립니다.
    const snapshot = await page.evaluate(() => {
      const o = {};
      for (let i = 0; i < localStorage.length; i++) {
        const k = localStorage.key(i); o[k] = localStorage.getItem(k);
      }
      return o;
    });

    const registered = await page.evaluate(() => window.MB_APP.screenIds || []);
    const screenList = (onlyScreens.length ? onlyScreens : SCREENS);

    for (const sid of screenList) {
      await restore(page, snapshot);
      const arrival = await goTo(page, sid);
      if (!arrival.ok) {
        found('유령화면', `${key}/${sid}`, `MB_APP.go('${sid}') 가 도착하지 못함 (현재 ${arrival.at})`);
        continue;
      }
      screensSeen++;

      /* 접혀 있는 카드 안의 입력은 크기가 0이라 눌러볼 수가 없습니다.
         접힌 채로 두면 P04 의 체수분·단백질·무기질 같은 칸이 한 번도
         검사되지 않습니다 — 안 본 것을 통과로 세면 안 됩니다. */
      await page.evaluate(() => {
        document.querySelectorAll('#main [data-uid]').forEach(e => {
          const t = (e.innerText || '');
          if (e.tagName === 'BUTTON' && /펼치기|접기|더 보기|자세히/.test(t)) {
            const box = e.closest('.card') || document;
            const hidden = [...box.querySelectorAll('input')].some(i => !i.offsetParent);
            if (hidden) e.click();
          }
        });
      });
      await page.waitForTimeout(220);

      const shape = await page.evaluate(() => {
        const main = document.getElementById('main');
        const txt = (main.innerText || '').replace(/\s+/g, ' ').trim();
        const uids = [...main.querySelectorAll('[data-uid]')];
        const act = uids.filter(e => {
          const t = e.tagName;
          return t === 'BUTTON' || t === 'INPUT' || t === 'SELECT' || t === 'TEXTAREA' ||
                 e.classList.contains('chip') || e.classList.contains('tab') ||
                 getComputedStyle(e).cursor === 'pointer';
        });
        return {
          chars: txt.length,
          uids: act.map(e => ({
            uid: e.getAttribute('data-uid'),
            tag: e.tagName,
            type: e.getAttribute('type') || '',
            disabled: !!e.disabled,
            label: (e.innerText || e.getAttribute('aria-label') || '').replace(/\s+/g, ' ').trim().slice(0, 40)
          })),
          hasNav: !!document.querySelector('.tabbar, .nav, [data-uid^="A"]')
        };
      });

      if (shape.chars < 30) {
        found('빈화면', `${key}/${sid}`, `본문이 ${shape.chars}자 — 왜 비었는지 설명이 없습니다`);
      }
      if (!shape.uids.length && !shape.hasNav) {
        found('막다른길', `${key}/${sid}`, '누를 수 있는 것이 하나도 없습니다');
      }

      for (const el of shape.uids) {
        if (!el.uid) continue;
        if (DESTRUCTIVE.has(el.uid) || OPENS_FILE_DIALOG.has(el.uid)) continue;
        if (el.disabled) continue;
        if (el.tag === 'INPUT' && /file/.test(el.type)) continue;

        // 매번 같은 자리에서 출발합니다
        await restore(page, snapshot);
        const back = await goTo(page, sid);
        if (!back.ok) break;
        await page.evaluate(() => {
          document.querySelectorAll('#main button[data-uid]').forEach(e => {
            const t = (e.innerText || '');
            if (/펼치기|접기|더 보기|자세히/.test(t)) {
              const box = e.closest('.card') || document;
              if ([...box.querySelectorAll('input')].some(i => !i.offsetParent)) e.click();
            }
          });
        });
        await page.waitForTimeout(160);

        // 이미 선택된 탭·칩을 누르면 아무 일도 안 일어나는 게 맞습니다.
        const alreadyOn = await page.evaluate(u => {
          const e = document.querySelector('#main [data-uid="' + CSS.escape(u) + '"]');
          return !!e && (e.classList.contains('is-on') || e.classList.contains('is-active') ||
                         e.getAttribute('aria-selected') === 'true');
        }, el.uid);

        const before = await snapshotUi(page);
        errors = [];
        const r = await clickUid(page, el.uid, el.tag, el.type);
        clicks++;
        await page.waitForTimeout(240);
        const after = await snapshotUi(page);

        const errs = errors.slice();
        if (errs.length) {
          found('오류', `${key}/${sid}/${el.uid}`, errs[0], { label: el.label });
          continue;
        }
        if (!r.clicked) {
          found('못누름', `${key}/${sid}/${el.uid}`, r.why, { label: el.label });
          continue;
        }

        /* 바깥 문서로 가는 링크 — 주소가 실제로 열리는지 받아 봅니다.
           깨진 링크는 "눌러도 아무 일 없음" 보다 나쁩니다: 사용자는
           눌렀는데 빈 탭을 봅니다. */
        if (r.link) {
          const st = await page.evaluate(u =>
            fetch(u).then(x => x.status).catch(() => 0), r.link);
          if (st !== 200) {
            found('죽은링크', `${key}/${sid}/${el.uid}`,
                  `${r.link} 를 여는데 ${st === 0 ? '연결이 안 됩니다' : st + ' 가 돌아옵니다'}`,
                  { label: el.label });
          }
          continue;
        }

        if (!reacted(before, after)) {
          if (!alreadyOn) {
            found('무반응', `${key}/${sid}/${el.uid}`,
                  '눌러도 화면 · 모달 · 토스트 · 본문 · 포커스가 전혀 안 바뀝니다', { label: el.label });
          }
          continue;
        }

        // 도착한 곳에서 빠져나올 길이 있는가
        if (after.modal) {
          const esc = await page.evaluate(() => {
            const m = document.querySelector('.modal');
            if (!m) return true;
            return !!(m.querySelector('[data-uid$="-B99"]') || m.querySelector('.modal__actions .btn'));
          });
          if (!esc) found('막다른길', `${key}/${sid}/${el.uid}`, '모달에 닫을 방법이 없습니다', { label: el.label });
          await page.keyboard.press('Escape').catch(() => {});
          await page.waitForTimeout(150);
        } else if (after.screen !== before.screen) {
          if (!registered.includes(after.screen) && after.screen) {
            found('유령이동', `${key}/${sid}/${el.uid}`,
                  `등록되지 않은 화면 ${after.screen} 으로 보냅니다`, { label: el.label });
          }
          const stuck = await page.evaluate(() => {
            const main = document.getElementById('main');
            const txt = (main.innerText || '').trim();
            const anyOut = document.querySelector('.tabbar, [data-uid^="A"]') ||
                           main.querySelector('button, .chip, a');
            return { chars: txt.length, anyOut: !!anyOut };
          });
          if (!stuck.anyOut) {
            found('막다른길', `${key}/${sid}/${el.uid}`,
                  `${after.screen} 에 도착했는데 빠져나올 길이 없습니다`, { label: el.label });
          }
          if (stuck.chars < 30) {
            found('빈화면', `${key}/${sid}/${el.uid}`,
                  `${after.screen} 이 ${stuck.chars}자로 비어 있습니다`, { label: el.label });
          }
        }
      }
      process.stdout.write(`  ${sid} ${shape.uids.length}개 `);
    }
    console.log('');
  }

  /* --- 파괴적인 버튼 — 자기 상태에서 따로 ------------------------------- */
  console.log('\n=== 파괴적인 동작 ===');
  /* 앞 단계에서 서버가 죽었을 수 있습니다. 살아 있는지 확인하고,
     아니면 다시 띄웁니다. 죽은 채로 진행하면 로그인이 실패하고
     P14 · P15 버튼이 화면에 안 나와서 "없음" 으로 넘어갑니다 —
     검사했다고 착각하게 됩니다. */
  let apiAlive = false;
  if (apiBase) {
    try { apiAlive = (await fetch(apiBase + '/health')).ok; } catch { apiAlive = false; }
  }
  if (!apiAlive) {
    if (apiProc) { try { apiProc.kill(); } catch {} apiProc = null; }
    apiBase = null;
    await bootApi();
  }
  if (!apiBase) found('검사못함', '파괴적 동작', '서버가 안 떠서 계정·친구 쪽 버튼을 못 봤습니다');

  for (const uid of DESTRUCTIVE) {
    const sid = uid.slice(0, 3);
    await page.goto(`http://localhost:${PORT}/`, { waitUntil: 'load' });
    await page.waitForTimeout(200);
    await page.evaluate(() => {
      localStorage.clear();
      window.MB_STORE.seed();
      // 지울 것이 없으면 버튼이 disabled 라 확인 모달이 뜰 일도 없습니다.
      localStorage.setItem('mybody.feedback.v1', JSON.stringify([
        { uid: 'P02-B03', text: '검증용 메모', at: '2026-09-01T00:00:00.000Z' }
      ]));
      localStorage.setItem('mybody.photos.v1', JSON.stringify({
        'shot-test': { dataUrl: 'data:image/gif;base64,R0lGODlhAQABAAAAACw=',
                       at: '2026-09-01T00:00:00.000Z', w: 1, h: 1, bytes: 40, name: 't.gif' }
      }));
    });
    await page.reload({ waitUntil: 'load' });
    await page.waitForTimeout(400);
    // 계정·친구 쪽 버튼은 로그인해야 화면에 나옵니다
    if (apiBase && /^P1[456]$/.test(sid)) {
      await page.evaluate(b => window.MB_SYNC.configure(b), apiBase);
      const signedIn = await page.evaluate(async () => {
        try {
          await window.MB_SYNC.signUp({
            handle: 'destroyer', password: 'destroy-password-1',
            displayName: '삭제검증', pairSecret: 'sweep-pair-secret',
            healthConsent: true
          }).catch(() => window.MB_SYNC.signIn({ handle: 'destroyer', password: 'destroy-password-1' }));
          return window.MB_SYNC.status().signedIn;
        } catch (e) { return false; }
      });
      if (!signedIn) {
        found('검사못함', sid + '/' + uid, '로그인이 안 돼서 이 버튼을 못 눌렀습니다');
        console.log(`  ${uid} — 로그인 실패 — 판정 안 함`);
        continue;
      }
      await page.waitForTimeout(600);
      if (uid === 'P15-B32') {
        // 데모 친구 버튼은 개발 빌드 전용이고, 로그인 상태에서는 pull() 이
        // 덮어써서 남지도 않습니다. 여기서는 그냥 건너뜁니다.
        console.log('  P15-B32 — 데모 친구는 개발 빌드 전용 — 판정 안 함');
        continue;
      }
    }
    errors = [];
    const at = await goTo(page, sid);
    if (!at.ok) { console.log(`  ${uid} — ${sid} 에 못 감`); continue; }
    const r = await clickUid(page, uid, 'BUTTON', '');
    await page.waitForTimeout(300);
    if (!r.clicked) { console.log(`  ${uid} — 화면에 없음 (${r.why})`); continue; }
    if (r.disabled) { console.log(`  ${uid} — 비활성 (지울 것이 없음) — 판정 안 함`); continue; }
    // 확인 모달이 떠야 정상입니다
    const guarded = await page.evaluate(() => !!document.querySelector('.modal'));
    if (!guarded) {
      found('무확인삭제', `${sid}/${uid}`, '확인 없이 바로 지웁니다');
    }
    if (errors.length) found('오류', `${sid}/${uid}`, errors[0]);
    console.log(`  ${uid} — ${guarded ? '확인 모달 있음 ✓' : '확인 없음 ✗'}${errors.length ? ' · 오류' : ''}`);
    await page.keyboard.press('Escape').catch(() => {});
  }

  /* --- 보고 --------------------------------------------------------------- */
  console.log(`\n=== 결과 ===`);
  console.log(`  화면 진입 ${screensSeen}회 · 클릭 ${clicks}회`);

  const byKind = {};
  findings.forEach(f => { (byKind[f.kind] = byKind[f.kind] || []).push(f); });
  const ORDER = ['오류', '유령이동', '유령화면', '막다른길', '무확인삭제', '빈화면', '무반응', '못누름'];
  let hard = 0;
  for (const kind of ORDER) {
    const list = byKind[kind] || [];
    if (!list.length) continue;
    if (kind !== '무반응' && kind !== '못누름') hard += list.length;
    console.log(`\n  [${kind}] ${list.length}건`);
    list.slice(0, 40).forEach(f => {
      console.log(`    ${f.where}${f.label ? ' (' + f.label + ')' : ''}`);
      console.log(`      ${f.detail}`);
    });
    if (list.length > 40) console.log(`    ... 그 외 ${list.length - 40}건`);
  }

  fs.writeFileSync(path.join(OUT, 'interactions.json'),
    JSON.stringify({ clicks, screensSeen, findings }, null, 1));
  console.log(`\n  상세: ${path.join(OUT, 'interactions.json')}`);
  console.log(hard ? `\n실패 — 고쳐야 할 것 ${hard}건` : '\n통과');

  await browser.close(); server.close();
  if (apiProc) apiProc.kill();
  process.exit(hard ? 1 : 0);
})().catch(e => { console.error(e); server.close(); if (apiProc) apiProc.kill(); process.exit(1); });

/* --- 조각 ---------------------------------------------------------------- */

/* 어떤 화면은 인자가 있어야 본 모습이 나옵니다.
   P16 은 친구 id, P11 은 측정 id 가 없으면 "그런 것 없습니다" 빈 화면만
   보여줍니다. 인자 없이 열어 놓고 "통과" 라고 하면, 정작 사람이 실제로
   보는 화면은 한 번도 안 본 것입니다. 인자는 지금 저장된 데이터에서
   뽑습니다 — 지어내면 그것대로 없는 화면을 보게 됩니다. */
async function goTo(page, sid) {
  const at = await page.evaluate((s) => {
    var p = null;
    try {
      var st = window.MB_STORE.get();
      if (s === 'P16') {
        var f = window.MB_BACKEND && window.MB_BACKEND.listFriends();
        if (f && f.accepted && f.accepted.length) p = { friendId: f.accepted[0].id };
      } else if (s === 'P11' || s === 'P04') {
        if (st.scans && st.scans.length) p = { scanId: st.scans[st.scans.length - 1].id };
      }
    } catch (e) {}
    try { window.MB_APP.go(s, p); } catch (e) { return 'THREW:' + e.message; }
    return window.MB_APP.current;
  }, sid);
  await page.waitForTimeout(260);
  // 모달이 떠 있으면 닫고 봅니다 (고지 모달 등)
  await page.evaluate(() => {
    const b = document.querySelector('.modal-backdrop .modal__actions .btn--primary');
    if (b) b.click();
  });
  await page.waitForTimeout(150);
  const now = await page.evaluate(() => window.MB_APP.current);
  return { ok: now === sid, at: now };
}

async function restore(page, snap) {
  await page.evaluate((s) => {
    localStorage.clear();
    Object.keys(s).forEach(k => localStorage.setItem(k, s[k]));
  }, snap);
  await page.reload({ waitUntil: 'load' });
  await page.waitForTimeout(330);
  await page.evaluate(() => {
    const b = document.querySelector('.modal-backdrop .modal__actions .btn--primary');
    if (b) b.click();
  });
  await page.waitForTimeout(120);
}

/* 무엇을 "반응" 으로 볼 것인가.
 *
 * 처음엔 본문 앞 400자만 비교했는데, 그러면 화면 아래쪽이 바뀌는 버튼이
 * 전부 "무반응" 으로 찍혔습니다. 46건이 나왔고 그중 진짜는 몇 개뿐이라,
 * 목록 자체를 안 보게 되는 상태였습니다. 거짓 경보가 많은 검사는 검사가
 * 아닙니다.
 *
 * 그래서 사람이 "뭔가 일어났다" 고 느끼는 것을 전부 셉니다:
 *   화면 이동 · 모달 · 토스트 · 본문 변화(전체) · 포커스 이동 ·
 *   입력값 변화 · 선택 상태 변화(탭/칩)
 * 포커스 이동이 특히 중요합니다 — "체중 입력하러 가기" 같은 버튼은
 * 하는 일이 포커스를 옮기는 것뿐입니다. */
async function snapshotUi(page) {
  return page.evaluate(() => {
    const main = document.getElementById('main');
    /* 떠오르는 것이 .modal 만 있는 게 아닙니다 — 단축키 도움말과 메모
       입력은 .uid-note-backdrop 이라는 자기 레이어를 씁니다. */
    const over = document.querySelector('.modal, .uid-note-backdrop, [role="dialog"]');
    const a = document.activeElement;
    let h = 0;
    const txt = (main.innerText || '') + '|' + (main.innerHTML || '').length;
    for (let i = 0; i < txt.length; i++) { h = ((h << 5) - h + txt.charCodeAt(i)) | 0; }
    return {
      screen: window.MB_APP.current,
      modal: !!over,
      toast: (document.querySelector('.toast') || {}).textContent || '',
      body: h,
      focus: a ? (a.getAttribute('data-uid') || a.tagName + ':' + (a.className || '')) : '',
      values: [...main.querySelectorAll('input, select, textarea')]
        .map(e => (e.getAttribute('data-uid') || '') + '=' + (e.value || '')).join('|'),
      on: [...main.querySelectorAll('.is-on, .is-active, [aria-selected="true"]')]
        .map(e => e.getAttribute('data-uid') || e.className).join('|')
    };
  });
}

function reacted(a, b) {
  return a.screen !== b.screen || a.modal !== b.modal || a.toast !== b.toast ||
         a.body !== b.body || a.focus !== b.focus || a.values !== b.values || a.on !== b.on;
}

async function clickUid(page, uid, tag, type) {
  return page.evaluate(([u, t, ty]) => {
    const el = document.querySelector('#main [data-uid="' + CSS.escape(u) + '"]');
    if (!el) return { clicked: false, why: '화면에서 사라졌습니다' };
    const r = el.getBoundingClientRect();
    if (!r.width && !r.height) return { clicked: false, why: '크기가 0입니다 (안 보임)' };
    if (el.disabled) return { clicked: true, disabled: true };
    if (t === 'INPUT' || t === 'TEXTAREA') {
      // 입력은 "값을 넣어 본다" 가 곧 상호작용입니다
      if (ty === 'checkbox' || ty === 'radio') { el.click(); return { clicked: true }; }
      if (ty === 'date') { el.value = '2026-08-01'; }
      else if (ty === 'datetime-local') { el.value = '2026-08-01T09:00'; }
      else if (ty === 'number' || el.inputMode === 'decimal') { el.value = '42.0'; }
      else { el.value = '검증'; }
      el.dispatchEvent(new Event('input', { bubbles: true }));
      el.dispatchEvent(new Event('change', { bubbles: true }));
      return { clicked: true };
    }
    /* 새 탭으로 여는 링크(개인정보처리방침 등)는 누르지 않습니다.
       누르면 팝업이 열리고 지금 페이지는 그대로라서 "무반응" 으로
       잘못 찍힙니다. 대신 주소를 돌려주고, 부르는 쪽에서 그 주소가
       실제로 열리는지 받아 봅니다 — 건너뛰는 것이 아니라 다르게
       확인하는 것입니다. */
    if (t === 'A' && el.getAttribute('href')) {
      return { clicked: true, link: el.getAttribute('href') };
    }
    el.click();
    return { clicked: true };
  }, [uid, tag, type]);
}
