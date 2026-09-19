/* =============================================================================
 * tools/test-dataloss.js — 조용히 사라지는 것들
 *
 *   NODE_PATH=/opt/node22/lib/node_modules node tools/test-dataloss.js
 *
 * 여기 있는 것들은 전부 "앱은 성공했다고 말하는데 실제로는 데이터가
 * 없어진" 종류입니다. 화면에 오류가 안 뜨기 때문에 눌러보는 검사로는
 * 절대 안 잡힙니다 — 사용자도 한참 뒤에야 알아채고, 그때는 앱을
 * 의심하기 전에 자기 기억을 의심합니다.
 *
 * 1. 같은 날 두 번째 측정이 첫 번째를 덮어쓴다
 *    EXIF 없는 사진(카톡으로 받은 것 · 스크린샷 · PNG)은 측정시각이
 *    똑같이 박혀서 id 가 충돌했습니다. 주인 실측만 해도 하루 세 번
 *    잰 날이 있습니다.
 *
 * 2. 저장소가 꽉 차면 조용히 실패한다
 *    localStorage 는 보통 5MB 이고 결과지 사진이 같은 칸을 씁니다.
 *    예전에는 catch {} 로 삼켰습니다.
 *
 * 3. 그때 사진보다 숫자를 지킨다
 *    사진은 다시 찍을 수 있지만 지나간 측정일의 숫자는 못 되찾습니다.
 * ========================================================================== */
const { chromium } = require('playwright');
const http = require('http'); const fs = require('fs'); const path = require('path');
const ROOT = path.join(__dirname, '..', 'prototype');
const MIME={'.html':'text/html','.js':'text/javascript','.css':'text/css','.json':'application/json','.png':'image/png','.webmanifest':'application/manifest+json'};
const srv=http.createServer((q,r)=>{let p=decodeURIComponent(q.url.split('?')[0]);if(p==='/')p='/index.html';
  const f=path.join(ROOT,p); if(!f.startsWith(ROOT)||!fs.existsSync(f)||fs.statSync(f).isDirectory()){r.writeHead(404);return r.end('x');}
  r.writeHead(200,{'Content-Type':MIME[path.extname(f)]||'application/octet-stream'}); r.end(fs.readFileSync(f));});
let pass=0,fail=0;
const ok=(n,c,d)=>{if(c){pass++;console.log('  ✓',n);}else{fail++;console.log('  ✗',n,d===undefined?'':JSON.stringify(d).slice(0,220));}};
(async()=>{
  await new Promise(r=>srv.listen(0,r));
  const PORT=srv.address().port;
  const b=await chromium.launch({executablePath: process.env.CHROME_PATH || '/opt/pw-browsers/chromium-1194/chrome-linux/chrome'});
  const pg=await (await b.newContext({viewport:{width:390,height:844}})).newPage();
  const errs=[]; pg.on('pageerror',e=>errs.push(e.message.slice(0,160)));
  await pg.goto(`http://localhost:${PORT}/`,{waitUntil:'load'}); await pg.waitForTimeout(400);

  console.log('\n[1] 같은 날 두 번째 측정이 첫 번째를 안 덮는다');
  await pg.evaluate(()=>{localStorage.clear();window.MB_STORE.seed();});
  await pg.reload({waitUntil:'load'}); await pg.waitForTimeout(500);
  const before = await pg.evaluate(()=>window.MB_STORE.get().scans.length);
  // EXIF 없는 사진 두 장을 같은 날짜로 넣는 경로를 그대로 흉내냅니다
  // P04 직접 입력으로 같은 날 두 번 저장합니다 (사진 경로와 같은 makeId 를 탑니다)
  const ids = await pg.evaluate(async ()=>{
    const out=[];
    for (const [w,s,f] of [[85.0,38.0,19.0],[84.4,38.1,18.4]]) {
      window.MB_APP.go('P04',{manual:true});
      await new Promise(r=>setTimeout(r,400));
      const m0=document.querySelector('.modal-backdrop .btn--primary');
      if(m0){m0.click(); await new Promise(r=>setTimeout(r,300));}
      const dt=document.querySelector('[data-uid="P04-F14"]');
      if(dt){ dt.value='2026-10-05T09:00'; dt.dispatchEvent(new Event('change',{bubbles:true})); }
      [['P04-F01',w],['P04-F02',s],['P04-F03',f]].forEach(([u,v])=>{
        const e=document.querySelector('[data-uid="'+u+'"]');
        if(e){ e.value=String(v); e.dispatchEvent(new Event('input',{bubbles:true})); }
      });
      await new Promise(r=>setTimeout(r,300));
      const btn=document.querySelector('[data-uid="P04-B04"]');
      if(btn) btn.click();
      await new Promise(r=>setTimeout(r,500));
      const m=document.querySelector('.modal-backdrop .btn--primary');
      if(m){m.click(); await new Promise(r=>setTimeout(r,500));}
      const sc=window.MB_STORE.get().scans;
      out.push(sc.length ? sc[sc.length-1].id : null);
    }
    return {ids:out, count:window.MB_STORE.get().scans.length};
  });
  ok('측정 2건이 둘 다 남았다', ids.count===before+2, {before, after:ids.count, ids:ids.ids});
  ok('id 가 서로 다르다', ids.ids[0]!==ids.ids[1], ids.ids);

  console.log('\n[2] 저장소가 꽉 차면 사실대로 말한다');
  const r2 = await pg.evaluate(async ()=>{
    localStorage.clear();
    window.MB_STORE.seed();
    // setItem 을 막아서 꽉 찬 상태를 흉내냅니다
    const real = Storage.prototype.setItem;
    Storage.prototype.setItem = function(k,v){
      if (k === 'mybody.state.v1') { const e=new Error('quota'); e.name='QuotaExceededError'; throw e; }
      return real.call(this,k,v);
    };
    const okFlag = window.MB_STORE.save();
    const said = window.MB_STORE.saved();
    Storage.prototype.setItem = real;
    return {okFlag, said};
  });
  ok('save() 가 false 를 돌려준다', r2.okFlag===false, r2);
  ok('saved() 도 false', r2.said===false, r2);

  console.log('\n[3] 사진을 버려서라도 숫자는 지킨다');
  const r3 = await pg.evaluate(async ()=>{
    localStorage.clear();
    window.MB_STORE.seed();
    // 사진을 몇 장 넣어 둡니다
    const map={};
    for(let i=0;i<4;i++) map['shot-'+i]={dataUrl:'data:image/gif;base64,R0lGODlhAQABAAAAACw=',
      at:'2026-09-0'+(i+1)+'T00:00:00.000Z',w:1,h:1,bytes:40,name:'t'+i};
    localStorage.setItem('mybody.photos.v1', JSON.stringify(map));
    const photosBefore = Object.keys(window.MB_PHOTO.list()).length;
    // 사진이 남아 있는 동안만 실패하게 만듭니다
    const real = Storage.prototype.setItem;
    let tries = 0;
    Storage.prototype.setItem = function(k,v){
      if (k === 'mybody.state.v1') {
        tries++;
        if (Object.keys(JSON.parse(localStorage.getItem('mybody.photos.v1')||'{}')).length > 1) {
          const e=new Error('quota'); e.name='QuotaExceededError'; throw e;
        }
      }
      return real.call(this,k,v);
    };
    const okFlag = window.MB_STORE.save();
    Storage.prototype.setItem = real;
    return {okFlag, photosBefore, photosAfter:Object.keys(window.MB_PHOTO.list()).length, tries};
  });
  ok('결국 저장에 성공한다', r3.okFlag===true, r3);
  ok('사진을 버려서 자리를 만들었다', r3.photosAfter < r3.photosBefore, r3);

  console.log('\n[4] JS 오류');
  ok('오류 0건', errs.length===0, errs);

  console.log(`\n통과 ${pass} / 실패 ${fail}`);
  await b.close(); srv.close();
  process.exit(fail?1:0);
})().catch(e=>{console.error(e);srv.close();process.exit(1);});
