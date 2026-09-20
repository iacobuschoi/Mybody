/* =============================================================================
 * tools/test-honesty.js — 모르는 것을 안다고 말하지 않는가
 *
 *   NODE_PATH=/opt/node22/lib/node_modules node tools/test-honesty.js
 *
 * 이 앱의 규칙 하나: 인바디 오차보다 작은 변화를 성과로 세지 않는다.
 *
 * 왜 이게 규칙인가. 오차 수준의 신호에 점수를 붙이면 사람은 거기서
 * 규칙을 찾아냅니다 — 없는 규칙을요. 어제 물을 많이 마셔서 0.4kg
 * 차이가 난 것을 "그 운동이 효과가 있었다" 로 읽고 행동을 바꿉니다.
 * 반대로 열심히 했는데 44% 라고 찍히면 "나는 해도 안 되는구나" 가
 * 됩니다. 둘 다 앱이 만든 것입니다.
 *
 * 그래서 막대에 숫자를 붙일 수 없을 때는 붙이지 않습니다. 대신
 * "이 사이 어딘가" 를 빗금 구간으로 보여줍니다. 그게 우리가 아는
 * 전부이기 때문입니다.
 *
 * 여기서 보는 것
 *   1. 갈 거리가 0인 목표에서 NaN% 가 안 나온다
 *   2. 오차보다 작은 변화에 달성률 퍼센트를 안 붙인다
 *   3. 그때 무엇을 모르는지 화면이 말한다
 * ========================================================================== */
'use strict';
const { chromium } = require('playwright');
const http = require('http'); const fs = require('fs'); const path = require('path');
const ROOT = path.join(__dirname, '..', 'prototype');
const MIME={'.html':'text/html','.js':'text/javascript','.css':'text/css','.json':'application/json','.png':'image/png','.webmanifest':'application/manifest+json'};
const srv=http.createServer((q,r)=>{let p=decodeURIComponent(q.url.split('?')[0]);if(p==='/')p='/index.html';
  const f=path.join(ROOT,p); if(!f.startsWith(ROOT)||!fs.existsSync(f)||fs.statSync(f).isDirectory()){r.writeHead(404);return r.end('x');}
  r.writeHead(200,{'Content-Type':MIME[path.extname(f)]||'application/octet-stream'}); r.end(fs.readFileSync(f));});
let pass=0,fail=0;
const ok=(n,c,d)=>{if(c){pass++;console.log('  ✓',n);}else{fail++;console.log('  ✗',n,d===undefined?'':JSON.stringify(d).slice(0,240));}};
(async()=>{
  await new Promise(r=>srv.listen(0,r)); const PORT=srv.address().port;
  const b=await chromium.launch({executablePath: process.env.CHROME_PATH || '/opt/pw-browsers/chromium-1194/chrome-linux/chrome'});
  const pg=await (await b.newContext({viewport:{width:390,height:844}})).newPage();
  const errs=[]; pg.on('pageerror',e=>errs.push(e.message.slice(0,160)));
  await pg.goto(`http://localhost:${PORT}/`,{waitUntil:'load'}); await pg.waitForTimeout(400);

  console.log('\n[1] 유지 목표에서 NaN 이 안 나온다');
  const r1 = await pg.evaluate(async ()=>{
    localStorage.clear(); window.MB_STORE.seed();
    const st = window.MB_STORE.get();
    const last = st.scans[st.scans.length-1];
    // 체지방 목표를 지금과 같게 (= 갈 거리 0)
    const E = window.MB_ENGINE;
    const prof = st.profile;
    const d = E.derive(last, prof);
    st.goal = { weightKg: d.weightKg, smmKg: d.smmKg, bfmKg: d.bfmKg,
                targetDate: null, deadlineWeeks: 26 };
    window.MB_STORE.save();
    try { window.MB_APP.go('P05'); } catch(e){}
    return true;
  });
  await pg.evaluate(()=>{const b=document.querySelector('[data-uid="P05-B05"]'); if(b)b.click();});
  await pg.waitForTimeout(600);
  await pg.evaluate(()=>{const b=document.querySelector('[data-uid="P06-B22"]'); if(b)b.click();});
  await pg.waitForTimeout(400);
  await pg.evaluate(()=>{const b=document.querySelector('.modal-backdrop .btn--primary'); if(b)b.click();});
  await pg.waitForTimeout(700);
  await pg.evaluate(()=>window.MB_APP.go('P02')); await pg.waitForTimeout(700);
  const txt1 = await pg.evaluate(()=>document.getElementById('main').innerText);
  ok('화면에 NaN 이 없다', !/NaN/.test(txt1), (txt1.match(/.{0,30}NaN.{0,30}/)||[''])[0]);

  console.log('\n[2] 오차보다 작은 변화에 퍼센트를 안 붙인다');
  const r2 = await pg.evaluate(async ()=>{
    localStorage.clear(); window.MB_STORE.seed();
    const st = window.MB_STORE.get();
    // 계획을 두 달 전에 세운 것으로 돌려서 창이 계획을 덮게 합니다
    return true;
  });
  await pg.reload({waitUntil:'load'}); await pg.waitForTimeout(500);
  await pg.evaluate(()=>window.MB_APP.go('P05')); await pg.waitForTimeout(400);
  await pg.evaluate(()=>{const b=document.querySelector('[data-uid="P05-B05"]'); if(b)b.click();});
  await pg.waitForTimeout(600);
  await pg.evaluate(()=>{const b=document.querySelector('[data-uid="P06-B22"]'); if(b)b.click();});
  await pg.waitForTimeout(400);
  await pg.evaluate(()=>{const b=document.querySelector('.modal-backdrop .btn--primary'); if(b)b.click();});
  await pg.waitForTimeout(700);
  await pg.evaluate(()=>{
    const st=window.MB_STORE.get();
    st.plan.startDate = new Date(Date.now()-60*86400000).toISOString().slice(0,10);
    window.MB_STORE.save();
  });
  await pg.evaluate(()=>window.MB_APP.go('P02')); await pg.waitForTimeout(700);
  await pg.evaluate(()=>{const b=document.querySelector('[data-uid="P02-B19"]'); if(b)b.click();});
  await pg.waitForTimeout(500);
  const r = await pg.evaluate(()=>{
    const c=document.querySelector('[data-uid="P02-C02"]');
    if(!c) return null;
    return {
      text: c.innerText,
      fills: [...c.querySelectorAll('.bar__fill')].map(e=>e.style.width),
      bands: [...c.querySelectorAll('.bar__band')].map(e=>e.style.left+'→'+e.style.width)
    };
  });
  ok('오차 안 항목에 빗금 구간이 쓰였다', r && r.bands.length>0, r && {bands:r.bands, fills:r.fills});
  ok('그 항목에 채운 막대가 없다', r && r.bands.length>0 && r.fills.length < 3, r && {f:r.fills.length,b:r.bands.length});
  ok('무엇인지 설명이 붙는다', r && /이 사이 어딘가|정할 수 없습니다/.test(r.text), r && r.text.slice(0,300));

  console.log('\n--- 실제 화면 ---');
  console.log((r?r.text:'').split('\n').filter(l=>!/^P02-/.test(l)&&l.trim()).join('\n'));
  console.log('막대:', JSON.stringify(r&&{fills:r.fills,bands:r.bands}));
  await pg.evaluate(()=>{
    const c=document.querySelector('[data-uid="P02-C02"]');
    if(c) c.scrollIntoView({block:'center'});
    document.body.classList.add('uid-off');
  });
  await pg.waitForTimeout(300);
  const box = await pg.evaluate(()=>{
    const c=document.querySelector('[data-uid="P02-C02"]');
    const r=c.getBoundingClientRect();
    return {x:Math.max(0,r.x-4), y:Math.max(0,r.y-4), width:Math.min(390,r.width+8), height:Math.min(844,r.height+8)};
  });
  await pg.screenshot({path: path.join(__dirname,'.shots','goal-range.png'), clip:box});

  console.log('\n[3] 도착 예정일이 얼마나 단단한지 같이 말한다');
  /* "D−153 · 2027. 2. 20. 도착 예정" 은 계획상으로는 정확하지만, 계획
     자체가 인바디 측정 한 번 위에 서 있다. 그 측정의 체지방이 ±1.0kg
     흔들리면 도착일이 4/10 ~ 5/1 로 3주 움직였고, 단조롭지도 않았다
     (19.0kg 과 20.0kg 이 같은 날짜). 날짜를 지우지는 않되 그 숫자가
     얼마나 단단한지는 같이 적어야 한다. */
  const arr = await pg.evaluate(()=>{
    const c=document.querySelector('[data-uid="P02-C02"]');
    return c ? c.innerText : '';
  });
  ok('오차 범위를 같이 적는다', /인바디 오차만으로도 ±\d+주/.test(arr),
     (arr.match(/.{0,40}도착 예정.{0,60}/)||[''])[0]);

  /* --------------------------------------------------------------------
   * [4] 큰 고리가 50% 에서 시작하지 않는다
   *
   * 제일 흔한 목표가 "체지방은 빼고 근육은 유지" 입니다. 근육 축은
   * 갈 거리가 0 이라 자동으로 100 점이 됐고, 평균이 (0+100)/2 = 50
   * 에서 시작했습니다. 하루도 안 지났고 1kg 도 안 뺐는데 홈 화면
   * 맨 위 고리가 50% 를 가리킵니다. 절대 그 밑으로도 안 내려갑니다.
   *
   * 같은 순간에 추이 화면은 0%, 친구에게 나가는 값도 0 입니다.
   * 한 앱이 같은 질문에 세 가지로 답하는데, 제일 자주 보는 자리가
   * 제일 후한 답을 하고 있었습니다.
   * ------------------------------------------------------------------ */
  console.log('\n[4] 아무것도 안 했는데 절반이라고 하지 않는다');
  /* 화면이 하는 그대로 목표를 정하고 계획을 만듭니다 — 엔진을 직접
     부르면 화면이 안 쓰는 경로를 검사하게 됩니다. */
  await pg.evaluate(async ()=>{
    localStorage.clear(); window.MB_STORE.seed();
    const st = window.MB_STORE.get();
    const last = st.scans[st.scans.length-1];
    const d = window.MB_ENGINE.derive(last, st.profile);
    // 제일 평범한 목표: 체지방 -5kg, 골격근은 지금 그대로
    st.goal = { weightKg: Math.round((d.weightKg - 5) * 10) / 10,
                smmKg: d.smmKg, bfmKg: Math.round((d.bfmKg - 5) * 10) / 10,
                targetDate: null, deadlineWeeks: 26 };
    window.MB_STORE.save();
    try { window.MB_APP.go('P05'); } catch(e){}
  });
  /* 버튼 하나를 누르면 확인 창이 뜨는 자리가 있습니다(목표가 권고
     범위를 벗어났다 · 강도가 세다). 창을 닫아야 다음 화면으로 갑니다. */
  const tap = async (uid) => {
    for (let i = 0; i < 4; i++) {
      const hit = await pg.evaluate(u => {
        const m = document.querySelector('.modal-backdrop .modal__actions .btn--primary');
        if (m) { m.click(); return 'modal'; }
        const b = document.querySelector('[data-uid="' + u + '"]');
        if (b) { b.click(); return 'btn'; }
        return null;
      }, uid);
      await pg.waitForTimeout(500);
      if (hit === 'btn') break;
      if (!hit) break;
    }
    // 남은 확인 창을 마저 닫습니다
    for (let i = 0; i < 3; i++) {
      const more = await pg.evaluate(() => {
        const m = document.querySelector('.modal-backdrop .modal__actions .btn--primary');
        if (m) { m.click(); return true; } return false;
      });
      await pg.waitForTimeout(450);
      if (!more) break;
    }
  };
  await tap('P05-B05');
  await tap('P06-B22');
  await pg.waitForTimeout(500);
  const ring = await pg.evaluate(async ()=>{
    window.MB_APP.go('P02');
    await new Promise(r=>setTimeout(r,500));
    const c = document.querySelector('[data-uid="P02-C02"]');
    const txt = c ? c.innerText : '';
    const m = txt.match(/(\d+)%/);
    const snap = window.MB_STORE.weeklySnapshot();
    const st2 = window.MB_STORE.get();
    return { pct: m ? +m[1] : null, progressPct: snap.progressPct, txt: txt.slice(0, 240),
             hasPlan: !!st2.plan, hasGoal: !!st2.goal, screen: window.MB_APP.current,
             main: (document.getElementById('main').innerText||'').slice(0,200) };
  });
  ok('시작 직후 고리가 0% 다', ring.pct === 0, ring);
  ok('친구에게 나가는 값과 같다', ring.pct === ring.progressPct, ring);

  /* --------------------------------------------------------------------
   * [5] 본 적 없는 것을 봤다고 하지 않는다
   *
   * 운동 탭에 "부위별 분석상 뚜렷한 약점 없음" 이 모든 사용자에게
   * 떴습니다. 부위별 값은 앱에 들어오는 길이 자체가 없습니다 —
   * 화면에도 없고, 서버 판독이 읽는 14개 칸에도 없습니다.
   * 결과지에는 좌우 근육량 비교가 실제로 인쇄돼 있는데, 그걸 읽지도
   * 않고 "괜찮다" 고 하면 진짜 불균형이 있는 사람이 확인받았다고
   * 믿고 넘어갑니다.
   * ------------------------------------------------------------------ */
  console.log('\n[5] 부위별 분석을 본 적 없으면 봤다고 안 한다');
  /* 운동 카드는 P07 의 "운동" 탭(P07-T02)에 있습니다. */
  const workoutCard = async () => {
    await pg.evaluate(()=>window.MB_APP.go('P07'));
    await pg.waitForTimeout(450);
    await pg.evaluate(()=>{const b=document.querySelector('[data-uid="P07-T02"]'); if(b)b.click();});
    await pg.waitForTimeout(400);
    return pg.evaluate(()=>{
      const c = document.querySelector('[data-uid="P07-C10"]');
      return c ? c.innerText : '';
    });
  };

  /* 시드에는 부위별 값이 있습니다 — 있을 때는 말해도 됩니다. */
  const seg2 = await workoutCard();
  ok('값이 있으면 부위별이라고 말한다', /부위별 분석 기반/.test(seg2), seg2.slice(0, 200));

  /* 이제 부위별 값을 빼고 계획을 다시 만듭니다.
     계획에 이미 박힌 문장을 보는 게 아니라, 값 없이 새로 만든 계획이
     무엇이라고 말하는지를 봅니다. */
  await pg.evaluate(()=>{
    const st = window.MB_STORE.get();
    st.scans = st.scans.map(x => { const y = Object.assign({}, x);
      delete y.segmentalLean; delete y.segmentalFat; return y; });
    st.plan = null; st.baselinePlan = null;
    window.MB_STORE.save();
    window.MB_APP.go('P05');
  });
  await pg.waitForTimeout(600);
  await tap('P05-B05');
  await tap('P06-B22');
  await pg.waitForTimeout(500);
  const seg = await workoutCard();
  ok('"약점 없음" 이라고 단정하지 않는다', !/뚜렷한 약점 없음/.test(seg), seg.slice(0, 200));
  ok('없다는 것을 말한다', /부위별 분석은 아직 넣을 수 없습니다/.test(seg), seg.slice(0, 200));
  ok('제목도 부위별이라고 안 한다', !/부위별 분석 기반/.test(seg), seg.slice(0, 200));

  /* --------------------------------------------------------------------
   * [6] 안전 경고가 읽는 사람에게 하는 말인가
   *
   * 앱에서 유일하게 "그건 몸에 해롭습니다" 라고 말하는 자리입니다.
   * 그런데 문장이 "남성 필수지방은..." 으로 박혀 있어서, 여성 사용자는
   * 자기 얘기가 아니거나 앱이 성별을 잘못 안 것으로 읽었습니다.
   * 막으려고 만든 경고가 무시당하는 방식입니다.
   * ------------------------------------------------------------------ */
  console.log('\n[6] 안전 경고가 읽는 사람에게 하는 말인가');
  const warnFor = async (sex) => pg.evaluate(async (sx)=>{
    localStorage.clear(); window.MB_STORE.seed();
    const st = window.MB_STORE.get();
    st.profile = Object.assign({}, st.profile, { sex: sx, heightCm: sx === 'male' ? 187 : 163 });
    const last = st.scans[st.scans.length-1];
    const d = window.MB_ENGINE.derive(last, st.profile);
    // 체지방을 아주 낮게 — 경고가 뜨는 구간으로
    st.goal = { weightKg: Math.round((d.weightKg - 14) * 10) / 10, smmKg: d.smmKg,
                bfmKg: Math.max(1, Math.round((d.bfmKg - 14) * 10) / 10),
                targetDate: null, deadlineWeeks: 26 };
    window.MB_STORE.save();
    window.MB_APP.go('P05');
    await new Promise(r=>setTimeout(r,600));
    const el = document.querySelector('[data-uid="P05-S04"]');
    return el ? el.innerText : '';
  }, sex);

  const wF = await warnFor('female');
  ok('여성에게 "남성" 이라고 안 한다', wF && !/남성/.test(wF), wF.slice(0, 160));
  ok('여성 숫자를 말한다', /여성/.test(wF) && /10~13/.test(wF), wF.slice(0, 160));
  const wM = await warnFor('male');
  ok('남성에게는 남성 숫자를', /남성/.test(wM) && /2~5/.test(wM), wM.slice(0, 160));
  ok('앱의 하한과 필수지방을 구분해 말한다', /하한/.test(wM), wM.slice(0, 160));

  console.log('\n[7] JS 오류');
  ok('오류 0건', errs.length===0, errs);
  console.log(`\n통과 ${pass} / 실패 ${fail}`);
  await b.close(); srv.close(); process.exit(fail?1:0);
})().catch(e=>{console.error(e);srv.close();process.exit(1);});
