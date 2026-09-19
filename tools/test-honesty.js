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

  console.log('\n[4] JS 오류');
  ok('오류 0건', errs.length===0, errs);
  console.log(`\n통과 ${pass} / 실패 ${fail}`);
  await b.close(); srv.close(); process.exit(fail?1:0);
})().catch(e=>{console.error(e);srv.close();process.exit(1);});
