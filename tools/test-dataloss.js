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
 *
 * 4. 지운 측정의 사진이 기기에 남는다
 *    결과지 사진에는 보통 이름 · 나이 · 성별이 같이 인쇄돼 있습니다.
 *    "전부 지웠다" 고 믿고 폰을 넘긴 사람에게는 그게 전부입니다.
 *
 * 5. 판독 결과가 취소·삭제 뒤에 도착해 값을 덮는다
 *    판독은 몇 초 걸리고, 그 사이에 사용자는 취소하거나 사진을 뺍니다.
 *    늦게 온 답이 그대로 적용되면 취소가 취소가 아닙니다.
 *
 * 6. 서버가 결과지에서 읽은 시각을 버린다
 *    날짜만 남기고 시각을 버리면 같은 날 두 번 잰 순서를 잃습니다.
 *
 * 7. 고치던 값을 두고 나가면 말없이 버린다
 *    "저장하지 않고 나갈까요?" 모달(M23)이 만들어져 있었는데 부르는 곳이
 *    한 군데도 없었습니다. 나가는 길이 탭바 · 뒤로가기 · 화면 안 버튼으로
 *    여러 개라, 라우터에서 한 번 막습니다.
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


  console.log('\n[4] 안 고쳤으면 그냥 나간다');
  await pg.evaluate(()=>window.MB_APP.go('P04',{manual:true})); await pg.waitForTimeout(400);
  await pg.evaluate(()=>{const m=document.querySelector('.modal-backdrop .btn--primary'); if(m)m.click();});
  await pg.waitForTimeout(250);
  await pg.evaluate(()=>window.MB_APP.go('P02')); await pg.waitForTimeout(400);
  ok('막지 않는다', (await pg.evaluate(()=>window.MB_APP.current))==='P02');

  console.log('\n[5] 고치던 중이면 물어본다');
  await pg.evaluate(()=>window.MB_APP.go('P04',{manual:true})); await pg.waitForTimeout(400);
  await pg.evaluate(()=>{const m=document.querySelector('.modal-backdrop .btn--primary'); if(m)m.click();});
  await pg.waitForTimeout(250);
  await pg.evaluate(()=>{const e=document.querySelector('[data-uid="P04-F01"]');e.value='85.5';e.dispatchEvent(new Event('input',{bubbles:true}));});
  await pg.waitForTimeout(300);
  await pg.evaluate(()=>window.MB_APP.go('P02')); await pg.waitForTimeout(400);
  const st = await pg.evaluate(()=>({screen:window.MB_APP.current, modal:!!document.querySelector('.modal'),
    title:(document.querySelector('.modal__title')||{}).textContent||''}));
  ok('화면이 안 바뀐다', st.screen==='P04', st);
  ok('M23 모달이 뜬다', st.modal && /저장하지 않고/.test(st.title), st);

  console.log('\n[6] "계속 편집" 을 누르면 값이 살아 있다');
  await pg.evaluate(()=>{const b=[...document.querySelectorAll('.modal__actions .btn')].find(x=>/계속/.test(x.textContent)); if(b)b.click();});
  await pg.waitForTimeout(350);
  ok('P04 에 남아 있다', (await pg.evaluate(()=>window.MB_APP.current))==='P04');
  ok('고치던 값이 그대로', (await pg.evaluate(()=>{const e=document.querySelector('[data-uid="P04-F01"]');return e?e.value:null;}))==='85.5');

  console.log('\n[7] "나가기" 를 누르면 나간다');
  await pg.evaluate(()=>window.MB_APP.go('P02')); await pg.waitForTimeout(350);
  await pg.evaluate(()=>{const b=[...document.querySelectorAll('.modal__actions .btn')].find(x=>/나가기/.test(x.textContent)); if(b)b.click();});
  await pg.waitForTimeout(450);
  ok('P02 로 나갔다', (await pg.evaluate(()=>window.MB_APP.current))==='P02');

  console.log('\n[8] 탭바로 나가도 막힌다 (나가는 길이 여러 개다)');
  await pg.evaluate(()=>window.MB_APP.go('P04',{manual:true})); await pg.waitForTimeout(400);
  await pg.evaluate(()=>{const m=document.querySelector('.modal-backdrop .btn--primary'); if(m)m.click();});
  await pg.waitForTimeout(250);
  await pg.evaluate(()=>{const e=document.querySelector('[data-uid="P04-F02"]');e.value='38.5';e.dispatchEvent(new Event('input',{bubbles:true}));});
  await pg.waitForTimeout(300);
  await pg.evaluate(()=>{const t=document.querySelector('.tabbar__item[data-to="P02"]'); if(t)t.click();});
  await pg.waitForTimeout(400);
  ok('탭바도 막힌다', (await pg.evaluate(()=>window.MB_APP.current))==='P04');
  await pg.evaluate(()=>{const b=[...document.querySelectorAll('.modal__actions .btn')].find(x=>/나가기/.test(x.textContent)); if(b)b.click();});
  await pg.waitForTimeout(400);

  console.log('\n[9] 저장한 뒤에는 안 물어본다');
  await pg.evaluate(()=>window.MB_APP.go('P04',{manual:true})); await pg.waitForTimeout(400);
  await pg.evaluate(()=>{const m=document.querySelector('.modal-backdrop .btn--primary'); if(m)m.click();});
  await pg.waitForTimeout(250);
  await pg.evaluate(()=>{
    const dt=document.querySelector('[data-uid="P04-F14"]'); if(dt){dt.value='2026-11-20T09:00';dt.dispatchEvent(new Event('change',{bubbles:true}));}
    [['P04-F01','84.0'],['P04-F02','38.3'],['P04-F03','17.5']].forEach(([u,v])=>{
      const e=document.querySelector('[data-uid="'+u+'"]'); e.value=v; e.dispatchEvent(new Event('input',{bubbles:true}));});
  });
  await pg.waitForTimeout(350);
  await pg.evaluate(()=>{const b=document.querySelector('[data-uid="P04-B04"]'); if(b)b.click();});
  await pg.waitForTimeout(700);
  const after = await pg.evaluate(()=>({screen:window.MB_APP.current, modal:!!document.querySelector('.modal')}));
  ok('저장 뒤 바로 나간다 (M23 안 뜸)', after.screen!=='P04' || !after.modal, after);

  console.log('\n[10] 지운 측정의 사진이 기기에 안 남는다');
  const r = await pg.evaluate(()=>{
    localStorage.clear(); window.MB_STORE.seed();
    const st=window.MB_STORE.get();
    const P=window.MB_PHOTO;
    // 스캔 두 개에 사진을 하나씩 붙입니다
    P.save('ph-a','data:image/gif;base64,R0lGODlhAQABAAAAACw=',{w:1,h:1,name:'a'});
    P.save('ph-b','data:image/gif;base64,R0lGODlhAQABAAAAACw=',{w:1,h:1,name:'b'});
    st.scans[0].photoId='ph-a';
    st.scans[1].photoId='ph-b';
    st.scans[2].photoId='ph-b';   // 같은 사진을 둘이 가리킴
    window.MB_STORE.save();
    const before=Object.keys(P.list()).length;
    window.MB_STORE.removeScan(st.scans[0].id);
    const afterA=Object.keys(P.list());
    window.MB_STORE.removeScan(window.MB_STORE.get().scans[0].id);   // ph-b 를 가리키는 것 하나
    const afterB=Object.keys(P.list());
    window.MB_STORE.reset();
    const afterReset=Object.keys(P.list()).length;
    return {before, afterA, afterB, afterReset};
  });
  ok('측정을 지우면 딸린 사진도 지워진다', !r.afterA.includes('ph-a'), r);
  ok('다른 측정이 쓰는 사진은 남는다', r.afterB.includes('ph-b'), r);
  ok('전체 초기화가 사진까지 지운다', r.afterReset===0, r);

  console.log('\n[11] 서버가 읽은 시각이 살아남는다');
  const o1 = await pg.evaluate(async ()=>{
    localStorage.clear(); window.MB_STORE.seed();
    // 판독을 켜고, MB_SYNC.ocr 을 가짜로 바꿔 시각까지 돌려주게 합니다
    window.MB_SYNC.configure('http://x');
    window.MB_SYNC.canOcr = () => true;
    window.MB_SYNC.ocr = (url, cb) => {
      setTimeout(()=>cb(null,{weightKg:85.2,smmKg:38.2,bfmKg:18.1,
        measuredAt:'2026-11-20T07:36:00'}),60);
      return ()=>{};
    };
    window.MB_APP.go('P03');
    await new Promise(r=>setTimeout(r,350));
    // 사진을 하나 넣습니다
    const c=document.createElement('canvas'); c.width=80;c.height=80;
    const blob=await new Promise(r=>c.toBlob(r,'image/jpeg',0.8));
    const dt=new DataTransfer(); dt.items.add(new File([blob],'s.jpg',{type:'image/jpeg'}));
    const i=document.querySelector('[data-uid="P03-F01"]'); i.files=dt.files;
    i.dispatchEvent(new Event('change',{bubbles:true}));
    await new Promise(r=>setTimeout(r,700));
    const btn=document.querySelector('[data-uid="P03-B13"]');
    if(!btn) return {err:'서버 판독 버튼이 없습니다'};
    btn.click();
    /* 세 칸을 다 읽으면 앱이 스스로 검수 화면으로 넘어갑니다 —
       예전엔 여기서 "검수 화면으로" 를 한 번 더 눌러야 했습니다. */
    await new Promise(r=>setTimeout(r,1200));
    const st=window.MB_STORE.get();
    return { screen: window.MB_APP.current, draftAt: st.draft && st.draft.measuredAt };
  });
  ok('다 읽으면 검수 화면으로 저절로 넘어간다', o1.screen==='P04', o1);
  ok('결과지의 시각 07:36 이 남는다', o1.draftAt && /T07:36/.test(o1.draftAt), o1);

  console.log('\n[12] 취소하면 업로드를 실제로 멈춘다');
  const o2 = await pg.evaluate(async ()=>{
    localStorage.clear(); window.MB_STORE.seed();
    window.MB_SYNC.configure('http://x');
    window.MB_SYNC.canOcr = () => true;
    let aborted = false, delivered = false;
    window.MB_SYNC.ocr = (url, cb) => {
      const t=setTimeout(()=>{ delivered=true; cb(null,{weightKg:99.9}); }, 1200);
      return ()=>{ aborted=true; clearTimeout(t); };
    };
    window.MB_APP.go('P03');
    await new Promise(r=>setTimeout(r,350));
    const c=document.createElement('canvas'); c.width=80;c.height=80;
    const blob=await new Promise(r=>c.toBlob(r,'image/jpeg',0.8));
    const dt=new DataTransfer(); dt.items.add(new File([blob],'s.jpg',{type:'image/jpeg'}));
    const i=document.querySelector('[data-uid="P03-F01"]'); i.files=dt.files;
    i.dispatchEvent(new Event('change',{bubbles:true}));
    await new Promise(r=>setTimeout(r,700));
    document.querySelector('[data-uid="P03-B13"]').click();
    await new Promise(r=>setTimeout(r,300));
    const cancel=document.querySelector('[data-uid="P03-B05"]');
    if(!cancel) return {err:'취소 버튼이 없습니다'};
    cancel.click();
    await new Promise(r=>setTimeout(r,1500));
    const w=document.querySelector('[data-uid="P03-F02"]');
    return { aborted, delivered, weightField: w?w.value:null };
  });
  ok('취소가 업로드를 끊는다', o2.aborted===true, o2);
  ok('늦은 응답이 값을 안 덮는다', o2.delivered===false && !o2.weightField, o2);

  console.log('\n[13] 사진을 빼도 멈춘다');
  const o3 = await pg.evaluate(async ()=>{
    localStorage.clear(); window.MB_STORE.seed();
    window.MB_SYNC.configure('http://x');
    window.MB_SYNC.canOcr = () => true;
    let aborted=false;
    window.MB_SYNC.ocr = (url, cb) => { const t=setTimeout(()=>cb(null,{weightKg:99.9}),1200);
      return ()=>{aborted=true;clearTimeout(t);}; };
    window.MB_APP.go('P03');
    await new Promise(r=>setTimeout(r,350));
    const c=document.createElement('canvas'); c.width=80;c.height=80;
    const blob=await new Promise(r=>c.toBlob(r,'image/jpeg',0.8));
    const dt=new DataTransfer(); dt.items.add(new File([blob],'s.jpg',{type:'image/jpeg'}));
    const i=document.querySelector('[data-uid="P03-F01"]'); i.files=dt.files;
    i.dispatchEvent(new Event('change',{bubbles:true}));
    await new Promise(r=>setTimeout(r,700));
    document.querySelector('[data-uid="P03-B13"]').click();
    await new Promise(r=>setTimeout(r,300));
    // 판독 중에는 사진 카드가 안 보이므로 취소 후 빼기
    document.querySelector('[data-uid="P03-B05"]').click();
    await new Promise(r=>setTimeout(r,300));
    const rm=document.querySelector('[data-uid="P03-B11"]');
    if(rm) rm.click();
    await new Promise(r=>setTimeout(r,1400));
    const main=document.getElementById('main');
    return { aborted, chars:(main.innerText||'').trim().length };
  });
  ok('화면이 비지 않는다', o3.chars>30, o3);

  console.log('\n[14] JS 오류');
  ok('오류 0건', errs.length===0, errs);

  console.log(`\n통과 ${pass} / 실패 ${fail}`);
  await b.close(); srv.close();
  process.exit(fail?1:0);
})().catch(e=>{console.error(e);srv.close();process.exit(1);});
