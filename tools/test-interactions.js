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
const http = require('http');
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..', 'prototype');
const PORT = Number(process.env.PORT || 8751);
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

(async () => {
  await new Promise(r => server.listen(PORT, r));
  const browser = await chromium.launch({ executablePath: CHROME });
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 } });
  const page = await ctx.newPage();
  page.on('pageerror', e => errors.push('PAGEERROR: ' + e.message.slice(0, 240)));
  page.on('console', m => { if (m.type() === 'error') errors.push('CONSOLE: ' + m.text().slice(0, 240)); });
  page.on('dialog', d => d.dismiss().catch(() => {}));

  let clicks = 0, screensSeen = 0;

  for (const [key, state] of Object.entries(STATES)) {
    if (wanted.length && !wanted.includes(key)) continue;
    console.log(`\n=== ${key} · ${state.label} ===`);

    await page.goto(`http://localhost:${PORT}/`, { waitUntil: 'load' });
    await page.waitForTimeout(250);
    await page.evaluate(state.setup);
    await page.reload({ waitUntil: 'load' });
    await page.waitForTimeout(450);
    errors = [];
    if (state.afterBoot) await state.afterBoot(page);

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

        const changed = before.screen !== after.screen || before.modal !== after.modal ||
                        before.html !== after.html || after.toast !== before.toast;
        if (!changed) {
          found('무반응', `${key}/${sid}/${el.uid}`,
                '눌러도 화면 · 모달 · 토스트 · 본문이 전혀 안 바뀝니다', { label: el.label });
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
  process.exit(hard ? 1 : 0);
})().catch(e => { console.error(e); server.close(); process.exit(1); });

/* --- 조각 ---------------------------------------------------------------- */

async function goTo(page, sid) {
  const at = await page.evaluate((s) => {
    try { window.MB_APP.go(s); } catch (e) { return 'THREW:' + e.message; }
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

async function snapshotUi(page) {
  return page.evaluate(() => {
    const main = document.getElementById('main');
    /* 떠오르는 것이 .modal 만 있는 게 아닙니다 — 단축키 도움말과 메모
       입력은 .uid-note-backdrop 이라는 자기 레이어를 씁니다. 이걸 안 보면
       멀쩡히 동작하는 버튼이 "무반응" 으로 찍힙니다. */
    const over = document.querySelector('.modal, .uid-note-backdrop, [role="dialog"]');
    return {
      screen: window.MB_APP.current,
      modal: !!over,
      overClass: over ? over.className : '',
      toast: (document.querySelector('.toast') || {}).textContent || '',
      html: (main.innerHTML || '').length + ':' + (main.innerText || '').slice(0, 400)
    };
  });
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
    el.click();
    return { clicked: true };
  }, [uid, tag, type]);
}
