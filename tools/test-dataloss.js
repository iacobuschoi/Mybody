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
  await pg.goto(`http://localhost:${PORT}/?app=1`,{waitUntil:'load'}); await pg.waitForTimeout(400);

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

  /* --------------------------------------------------------------------
   * [14] 앱을 지웠다 다시 깔아도 서버의 이번 주 기록이 안 지워진다
   *
   * 기기 안의 것이 사라지는 것은 알려진 일입니다. 문제는 그 다음입니다 —
   * 다시 로그인하면 온보딩을 처음부터 하게 되고, 온보딩의 첫 저장이
   * publishWeekly() 를 부릅니다. 측정이 0건이라 빈 스냅샷이 나가고,
   * 서버는 같은 주를 덮어씁니다. 친구 넷의 화면에서 그 사람의 이번 주
   * 점이 그 자리에서 꺼집니다. 기기를 정리한 것이 남의 화면에서 내
   * 기록을 지우는 일이 되면 안 됩니다.
   * ------------------------------------------------------------------ */
  console.log('\n[14] 다시 깔아도 서버의 이번 주 기록이 안 지워진다');
  const o4 = await pg.evaluate(async ()=>{
    localStorage.clear(); window.MB_STORE.seed();
    /* 로그인해야 올릴 것이 생깁니다. 서버 없이 로컬 거울에만 로그인합니다 —
       여기서 보려는 것은 "빈 스냅샷을 만드느냐" 이지 전송이 아닙니다. */
    window.MB_BACKEND.signIn({ provider: 'local', handle: 'loss:test', displayName: '검증' });
    const withScans = window.MB_STORE.publishWeekly();
    /* 다시 깐 직후 로그인한 상태: 측정도 없고 온보딩도 안 끝났습니다.
       일정은 하나 넣어 둡니다 — 안 그러면 "올릴 것이 아예 없어서"
       막히는 것이라 설치 직후 판정을 지나가지 못합니다. */
    window.MB_STORE.setSchedulePlan(window.MB_STORE.dayKey(), 'gym', true);
    window.MB_STORE.set({ scans: [], onboarded: false });
    const fresh = window.MB_STORE.publishWeekly();
    // 정말 아무것도 없을 때 (온보딩은 끝냈지만 올릴 것이 하나도 없음)
    window.MB_STORE.set({ onboarded: true, checkins: [], schedule: {} });
    const nothing = window.MB_STORE.publishWeekly();
    /* 인바디가 없어도 운동 일정만으로는 올라가야 합니다 — 그 사람의
       친구 화면이 영원히 비면 안 됩니다. */
    window.MB_STORE.setSchedulePlan(window.MB_STORE.dayKey(), 'gym', true);
    const schedOnly = window.MB_STORE.publishWeekly();
    return { withScans: withScans && withScans.ok,
             fresh: fresh && fresh.ok, freshWhy: fresh && fresh.reason,
             nothing: nothing && nothing.ok, nothingWhy: nothing && nothing.reason,
             schedOnly: schedOnly && schedOnly.ok };
  });
  ok('측정이 있으면 올린다', o4.withScans === true, o4);
  ok('다시 깐 직후에는 아무것도 안 올린다',
     o4.fresh === false && /설치 직후/.test(o4.freshWhy || ''), o4);
  ok('올릴 것이 하나도 없으면 안 올린다',
     o4.nothing === false && /올릴 것 없음/.test(o4.nothingWhy || ''), o4);
  ok('인바디가 없어도 운동 일정만으로는 올린다', o4.schedOnly === true, o4);

  /* --------------------------------------------------------------------
   * [15] 측정일이 마지막 기록보다 앞서면 짚어 준다
   *
   * 폰 시계가 이틀 느리면 오늘 잰 것이 그저께로 박힙니다. 앱은 측정일
   * 순으로 정렬하므로 어제 것이 "최신" 이 되고, 변화량이 거꾸로 계산돼
   * 친구 화면에 부호가 반대로 나갑니다. 주 경계도 틀어져서 지난주
   * 스냅샷을 덮어쓰면 그건 되돌릴 수 없습니다.
   * 기기 시계를 앱이 고칠 수는 없지만, 한 번 물어보면 대부분 걸립니다.
   * ------------------------------------------------------------------ */
  /* --------------------------------------------------------------------
   * [14-2] "모두 지웠습니다" 가 정말 모두인가
   *
   * 이 기기에는 친구의 이름 · 프로필 사진 · 그 사람이 나에게 보여 주기로
   * 한 숫자가 거울로 남아 있습니다. 결과지 사진과 같은 이유입니다 —
   * "전부 지웠다" 고 믿고 폰을 넘긴 사람에게는 그게 전부입니다.
   * 게다가 이건 내 데이터가 아니라 **남의** 데이터입니다.
   * ------------------------------------------------------------------ */
  console.log('\n[14-2] "모두 지웠습니다" 가 정말 모두인가');
  const oWipe = await pg.evaluate(async ()=>{
    localStorage.clear(); window.MB_STORE.seed();
    const S = window.MB_STORE, B = window.MB_BACKEND;
    B.signIn({ provider: 'local', handle: 'wipe:me', displayName: '나' });
    // 친구 하나를 거울에 심습니다 (사진 · 스냅샷 · 소식까지)
    const raw = B.raw(), me = raw.session, fid = 'u_friend';
    raw.users[fid] = { id: fid, handle: 'f', provider: 'local', displayName: '나린',
                       inviteCode: 'CODE', createdAt: '2026-08-01T00:00:00Z',
                       avatar: 'data:image/jpeg;base64,AAAA' };
    raw.friendships.push({ id: 'f1', aId: me, bId: fid, status: 'accepted',
      requestedBy: me, createdAt: '2026-08-01T00:00:00Z', respondedAt: '2026-08-01T00:00:00Z' });
    raw.snapshots.push({ ownerId: fid, weekStart: S.weekStartOf(),
      payload: { plannedDays: 4, keptDays: 2, dWeightKg: -0.8 } });
    B._setSession(me);
    window.MB_NEWS.apply([{ id: fid, rows: [{ weekStart: S.weekStartOf(), keptDays: 1 }] }],
      [{ id: fid, displayName: '나린' }]);
    window.MB_NEWS.apply([{ id: fid, rows: [{ weekStart: S.weekStartOf(), keptDays: 2 }] }],
      [{ id: fid, displayName: '나린' }]);
    S.setSchedulePlan(S.dayKey(), 'gym', true);
    const before = {
      news: window.MB_NEWS.list().length,
      friends: B.listFriends().accepted.length,
      raw: JSON.stringify(localStorage).includes('나린')
    };

    // 화면의 "삭제" 버튼이 하는 일 그대로
    window.MB_MODALS.resetAll();
    const inp = document.querySelector('[data-uid="M18"] input.input');
    inp.value = '초기화';
    /* 번호로 집습니다. 글자로 찾으면 고유번호 배지가 붙은 개발 빌드에서
       textContent 가 '삭제M18-B02' 가 돼서 안 걸립니다. */
    document.querySelector('[data-uid="M18-B02"]').click();
    await new Promise(r => setTimeout(r, 400));

    return { before, after: {
      scans: S.get().scans.length,
      schedule: Object.keys(S.get().schedule || {}).length,
      news: window.MB_NEWS.list().length,
      signedIn: !!B.currentUser(),
      friendName: JSON.stringify(localStorage).includes('나린'),
      avatar: JSON.stringify(localStorage).includes('data:image/jpeg')
    } };
  });
  ok('지우기 전에는 친구 · 소식이 있었다',
     oWipe.before.news >= 1 && oWipe.before.friends === 1 && oWipe.before.raw === true, oWipe.before);
  ok('내 측정이 지워진다', oWipe.after.scans === 0, oWipe.after);
  ok('운동 일정도 지워진다', oWipe.after.schedule === 0, oWipe.after);
  ok('친구 소식도 지워진다', oWipe.after.news === 0, oWipe.after);
  ok('로그아웃된다 (안 그러면 다음 동기화에 다시 내려옵니다)',
     oWipe.after.signedIn === false, oWipe.after);
  ok('친구 이름이 저장소에 안 남는다', oWipe.after.friendName === false, oWipe.after);
  ok('친구 프로필 사진도 안 남는다', oWipe.after.avatar === false, oWipe.after);

  console.log('\n[15] 측정일이 거꾸로 가면 짚어 준다');
  const o5 = await pg.evaluate(async ()=>{
    localStorage.clear(); window.MB_STORE.seed();
    const st = window.MB_STORE.get();
    const newest = window.MB_STORE.sortedScans().slice(-1)[0];
    // 마지막 기록보다 이틀 이른 날짜로 새 측정을 넣습니다 (시계가 느린 폰)
    const back = new Date(Date.parse(newest.measuredAt) - 2*24*3600*1000).toISOString();
    window.MB_STORE.set({ draft: {
      id: 'scan-backdated', measuredAt: back, source: 'manual', device: '',
      weightKg: 86.0, smmKg: 38.0, bfmKg: 19.5, partial: false,
      photoId: null, confidence: {}, lowConfidenceFields: []
    } });
    window.MB_DRAFT = window.MB_STORE.get().draft;
    window.MB_APP.go('P04', { ocr: false });
    await new Promise(r=>setTimeout(r,700));
    return (document.getElementById('main').innerText || '');
  });
  ok('앞선 날짜라고 말한다', /마지막 기록보다 앞섭니다/.test(o5),
     (o5.match(/.{0,60}앞섭니다.{0,80}/)||[''])[0]);
  ok('폰 시계를 확인하라고 한다', /시계/.test(o5));

  /* 정상 날짜면 안 뜹니다 — 거짓 경보는 경보를 죽입니다 */
  const o6 = await pg.evaluate(async ()=>{
    const st = window.MB_STORE.get();
    const newest = window.MB_STORE.sortedScans().slice(-1)[0];
    const fwd = new Date(Date.parse(newest.measuredAt) + 7*24*3600*1000).toISOString();
    const d = Object.assign({}, st.draft, { measuredAt: fwd });
    window.MB_STORE.set({ draft: d });
    window.MB_DRAFT = d;
    window.MB_APP.go('P02');
    await new Promise(r=>setTimeout(r,250));
    window.MB_APP.go('P04', { ocr: false });
    await new Promise(r=>setTimeout(r,700));
    return (document.getElementById('main').innerText || '');
  });
  ok('정상 날짜에는 안 뜬다', !/마지막 기록보다 앞섭니다/.test(o6));

  /* --------------------------------------------------------------------
   * [16] 온보딩을 채우다 앱을 나갔다 와도 안 날아간다
   *
   * 첫 화면에서 하는 일이 "인바디 결과지를 보면서 키·나이를 넣는" 것인데,
   * 폰에서 결과지 사진을 보려면 앱을 나갔다 와야 합니다. 그러면 브라우저가
   * 탭을 버리는 일이 흔하고, 예전에는 돌아오면 1/3 부터 다시였습니다.
   * 두 번 겪으면 앱을 지웁니다.
   * ------------------------------------------------------------------ */
  console.log('\n[16] 온보딩 답이 앱을 나갔다 와도 남는다');
  /* 저장소를 비우고 한 번 새로 불러옵니다 — 그래야 앱이 정말로
     "설치 직후" 상태에서 시작합니다. 메모리에 남은 프로필을 들고
     있으면 실제 첫 사용과 다른 길을 검사하게 됩니다. */
  await pg.evaluate(()=>localStorage.clear());
  await pg.reload({ waitUntil: 'load' });
  await pg.waitForTimeout(500);
  await pg.evaluate(async ()=>{
    window.MB_APP.go('P01');
    await new Promise(r=>setTimeout(r,400));
    // 1단계를 채웁니다 — 여 · 34세 · 163cm
    const sex = document.querySelector('[data-uid="P01-F01"]');
    if (sex) { const f=[...sex.querySelectorAll('button')].find(b=>b.textContent.trim()==='여'); if(f) f.click(); }
    const set = (uid, v) => { const i=document.querySelector('[data-uid="'+uid+'"]');
      if(i){ i.value=v; i.dispatchEvent(new Event('input',{bubbles:true}));
             i.dispatchEvent(new Event('change',{bubbles:true})); } };
    set('P01-F02', '34');
    set('P01-F03', '163');
    await new Promise(r=>setTimeout(r,300));
  });
  // 탭이 버려진 것과 같습니다 — 새로 불러옵니다
  await pg.reload({ waitUntil: 'load' });
  await pg.waitForTimeout(600);
  const o7 = await pg.evaluate(async ()=>{
    window.MB_APP.go('P01');
    await new Promise(r=>setTimeout(r,450));
    const val = u => { const i=document.querySelector('[data-uid="'+u+'"]'); return i ? i.value : null; };
    const sexOn = (()=>{ const c=document.querySelector('[data-uid="P01-F01"]');
      if(!c) return null; const on=c.querySelector('.is-on'); return on?on.textContent.trim():null; })();
    return { age: val('P01-F02'), height: val('P01-F03'), sex: sexOn,
             main: (document.getElementById('main').innerText||'').slice(0,60) };
  });
  ok('나이가 남아 있다', String(o7.age) === '34', o7);
  ok('키가 남아 있다', String(o7.height) === '163', o7);
  ok('성별 선택이 남아 있다', o7.sex === '여', o7);

  /* 완료하면 초안은 지웁니다 — 끝난 답을 남겨 둘 이유가 없습니다 */
  const o8 = await pg.evaluate(async ()=>{
    window.MB_STORE.set({ profile: { sex:'female', age:34, heightCm:163 }, onboarded: true });
    localStorage.removeItem('mybody.onboarding.v1');
    return localStorage.getItem('mybody.onboarding.v1');
  });
  ok('완료 뒤에는 초안이 안 남는다', o8 === null);

  console.log('\n[16-2] 저장된 기록을 못 읽으면, 그 원본을 덮어쓰지 않는다');
  {
    /* 측정 기록은 서버로 안 올라가는 **유일본**입니다.
       예전에는 손상·버전 불일치를 조용히 삼키고 빈 상태로 시작했습니다.
       그러면 앱이 온보딩을 띄우고, 한 걸음 넘어가는 순간 첫 저장이
       깨진 원본 바이트를 덮어씁니다 — 손으로 복구할 재료까지 그때
       사라집니다. 화면에는 아무것도 안 뜹니다. */
    await pg.evaluate(() => {
      localStorage.clear();
      // 사람이 읽을 수 있는 숫자가 들어 있는, 깨진 저장값
      localStorage.setItem('mybody.state.v1',
        '{"version":1,"scans":[{"weightKg":86.7,"smmKg":37.9}],  ← 여기서 깨짐');
    });
    await pg.reload({ waitUntil: 'load' });
    await pg.waitForTimeout(700);

    const kept = await pg.evaluate(() =>
      Object.keys(localStorage).filter(k => k.indexOf('mybody.state.v1.broken.') === 0));
    ok('원본을 옆에 보관한다', kept.length === 1, kept);
    if (kept.length) {
      const body = await pg.evaluate(k => localStorage.getItem(k), kept[0]);
      ok('보관한 것이 원본 그대로다', /86\.7/.test(body) && /37\.9/.test(body), String(body).slice(0, 80));
    }
    const shown = await pg.evaluate(() =>
      !!document.querySelector('[data-uid="M53"]'));
    ok('못 읽었다고 말한다', shown, shown);
    const txt = await pg.evaluate(() => (document.body.innerText || ''));
    ok('어디에 보관했는지 알려준다', /mybody\.state\.v1\.broken\./.test(txt), txt.slice(0, 400));

    /* 그리고 이제부터 쓰기 시작해도 보관본은 그대로 있어야 합니다. */
    await pg.evaluate(() => {
      document.querySelectorAll('.modal,.scrim,.backdrop').forEach(e => e.remove());
      window.MB_STORE.set({ onboarded: true });
    });
    await pg.waitForTimeout(300);
    const still = await pg.evaluate(() =>
      Object.keys(localStorage).filter(k => k.indexOf('mybody.state.v1.broken.') === 0));
    ok('그 뒤에 저장해도 보관본이 안 지워진다', still.length === 1, still);

    /* 같은 말을 새로고침마다 되풀이하지는 않습니다 — 한 번이면 됩니다. */
    await pg.reload({ waitUntil: 'load' });
    await pg.waitForTimeout(600);
    const again = await pg.evaluate(() => !!document.querySelector('[data-uid="M53"]'));
    ok('두 번째부터는 안 띄운다', !again, again);
  }

  console.log('\n[16-3] 저장이 실패하면 "했습니다" 라고 안 한다');
  {
    await pg.evaluate(() => { localStorage.clear(); });
    await pg.reload({ waitUntil: 'load' });
    await pg.waitForTimeout(500);
    await pg.evaluate(() => { window.MB_STORE.seed(); });
    await pg.waitForTimeout(200);

    /* 저장이 실패하는 상태를 만듭니다 — setItem 이 던지게. */
    await pg.evaluate(() => {
      window.__realSet = localStorage.setItem.bind(localStorage);
      localStorage.setItem = function (k, v) {
        if (k === 'mybody.state.v1') { const e = new Error('quota'); e.name = 'QuotaExceededError'; throw e; }
        return window.__realSet(k, v);
      };
    });

    const r = await pg.evaluate(() => {
      const S = window.MB_STORE;
      const okSave = S.set({ onboarded: true });
      return { saved: S.saved(), returned: okSave };
    });
    ok('저장이 실패하면 false 를 돌려준다', r.saved === false, r);

    /* 친구에게 올리지도 않아야 합니다 — 이 기기에서는 사라진 체크가
       친구 화면에는 남으면, 어느 쪽이 사실인지 알 수 없게 됩니다. */
    const published = await pg.evaluate(() => {
      const B = window.MB_BACKEND;
      B.reset();
      B.signIn({ provider: 'kakao' });
      const n0 = (B.raw().snapshots || []).length;
      window.MB_STORE.set({ onboarded: true });
      return { n0: n0, n1: (B.raw().snapshots || []).length };
    });
    ok('저장 못 한 것을 친구에게 올리지 않는다',
       published.n1 === published.n0, published);

    /* 가져오기는 "복원됐다" 를 믿은 사람이 원본 파일을 지웁니다. */
    const imp = await pg.evaluate(() => {
      try {
        window.MB_STORE.importJSON(JSON.stringify(
          Object.assign(window.MB_STORE.blank(), { onboarded: true })));
        return { threw: false };
      } catch (e) { return { threw: true, msg: String(e.message || e) }; }
    });
    ok('가져오기가 실패하면 성공이라고 안 한다', imp.threw === true, imp);
    ok('원본 파일을 지우지 말라고 말한다',
       /원본 파일을 지우지 마세요/.test(imp.msg || ''), imp);

    await pg.evaluate(() => { if (window.__realSet) localStorage.setItem = window.__realSet; });
  }

  console.log('\n[17] JS 오류');
  ok('오류 0건', errs.length===0, errs);

  console.log(`\n통과 ${pass} / 실패 ${fail}`);
  await b.close(); srv.close();
  process.exit(fail?1:0);
})().catch(e=>{console.error(e);srv.close();process.exit(1);});
