/* tools/dump-text.js — 화면에 실제로 뜨는 문구를 전부 뽑는다 (문구 다듬기용) */
const { chromium } = require('playwright');
const http = require('http'); const fs = require('fs'); const path = require('path');
const ROOT = path.join(__dirname, '..', 'prototype');
const MIME = { '.html':'text/html','.js':'text/javascript','.css':'text/css' };
const server = http.createServer((req,res)=>{
  let p=decodeURIComponent(req.url.split('?')[0]); if(p==='/')p='/index.html';
  const f=path.join(ROOT,p);
  if(!f.startsWith(ROOT)||!fs.existsSync(f)){res.writeHead(404);return res.end('x');}
  res.writeHead(200,{'Content-Type':MIME[path.extname(f)]||'application/octet-stream'});
  res.end(fs.readFileSync(f));
});
const SCREENS=['P01','P02','P03','P04','P05','P06','P07','P08','P09','P10','P11','P12','P13'];
(async()=>{
  await new Promise(r=>server.listen(8733,r));
  const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium-1194/chrome-linux/chrome'});
  const pg=await (await b.newContext({viewport:{width:420,height:900}})).newPage();
  await pg.goto('http://localhost:8733/?app=1',{waitUntil:'load'});
  await pg.waitForTimeout(400);
  await pg.evaluate(()=>{window.MB_STORE.seed();window.MB_APP.go('P05');});
  await pg.waitForTimeout(400);
  // 플랜까지 만들어 둔다
  await pg.evaluate(()=>{const x=document.querySelector('[data-uid="P05-B05"]');if(x)x.click();});
  await pg.waitForTimeout(500);
  await pg.evaluate(()=>{const x=document.querySelector('[data-uid="P06-B22"]');if(x)x.click();});
  await pg.waitForTimeout(400);
  await pg.evaluate(()=>{const x=document.querySelector('.modal-backdrop .btn--primary');if(x)x.click();});
  await pg.waitForTimeout(600);

  const out=[];
  for(const id of SCREENS){
    await pg.evaluate(s=>window.MB_APP.go(s),id);
    await pg.waitForTimeout(400);
    const rows=await pg.evaluate(()=>{
      const r=[];
      document.querySelectorAll('#main .note, #main .muted, #main .card__sub, #main .field__hint, #main .radio-card__d, #main .empty__d')
        .forEach(el=>{
          const t=el.innerText.trim().replace(/\s+/g,' ');
          if(t.length>0) r.push({cls:el.className.split(' ')[0], len:t.length, text:t});
        });
      return r;
    });
    rows.forEach(r=>out.push({screen:id,...r}));
  }
  await b.close(); server.close();
  out.sort((a,b)=>b.len-a.len);
  console.log('총',out.length,'개 문구 · 긴 것부터\n');
  out.slice(0,45).forEach(r=>console.log(`[${r.screen}] ${String(r.len).padStart(4)}자 (${r.cls})\n   ${r.text}\n`));
  const long=out.filter(r=>r.len>90);
  console.log(`\n90자 넘는 문구: ${long.length}개 / 전체 ${out.length}개`);
  const byScreen={}; long.forEach(r=>byScreen[r.screen]=(byScreen[r.screen]||0)+1);
  console.log('화면별:',JSON.stringify(byScreen));
  fs.writeFileSync(path.join(__dirname,'.shots','text-dump.json'),JSON.stringify(out,null,1));
})().catch(e=>{console.error(e);process.exit(1)});
