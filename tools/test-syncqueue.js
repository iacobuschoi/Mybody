/* =============================================================================
 * tools/test-syncqueue.js — 보낸 작업만 정확히 빠지는가
 *
 *   node tools/test-syncqueue.js
 *
 * 이 시험이 왜 따로 있는가
 *   이건 타이밍 버그라 브라우저에서 눈으로 잡기 어렵습니다. 요청이 날아가
 *   있는 그 창 안에서 큐를 건드려야 재현되고, 증상은 "조용히 사라진 작업"
 *   이라 화면에 아무것도 안 뜹니다. 그래서 fetch 를 직접 붙잡아 두고
 *   그 창을 손으로 엽니다.
 *
 *   실제로 두 가지가 일어났습니다.
 *     (가) 일정 칸을 네 번 연달아 누르면 서버에는 첫 번째 것만 남았습니다.
 *     (나) 큐에 친구 수락이나 공유 끄기가 같이 있으면 그게 지워졌습니다.
 *   (나)가 훨씬 나쁩니다 — 껐다고 믿는 사람은 다시 확인하지 않습니다.
 * ========================================================================== */
'use strict';
global.window = global;

let mem = {};
global.localStorage = {
  getItem: k => (k in mem ? mem[k] : null),
  setItem: (k, v) => { mem[k] = String(v); },
  removeItem: k => { delete mem[k]; }
};
/* node 22 의 navigator 는 읽기 전용이라 그냥 대입하면 던집니다. */
Object.defineProperty(global, 'navigator', { value: { onLine: true }, configurable: true });
Object.defineProperty(global, 'location', { value: { protocol: 'http:', origin: 'http://localhost:9999' }, configurable: true });

/* fetch 를 우리가 쥡니다. 보낸 요청을 순서대로 쌓아 두고, 언제 응답할지
   시험이 정합니다. 이렇게 해야 "날아가 있는 중" 이 확정됩니다. */
const sent = [];
global.fetch = (url, opts) => {
  let resolve;
  const p = new Promise(r => { resolve = r; });
  const rec = {
    url: String(url), body: opts && opts.body ? JSON.parse(opts.body) : null,
    done: false,
    /* 상태 코드를 고를 수 있게 해 둡니다 — 401(토큰이 죽음) 뒤의
       동작이 이 시험의 절반입니다. */
    finish: (status, body) => { rec.done = true; resolve({
      ok: !status || (status >= 200 && status < 300),
      status: status || 200,
      json: () => Promise.resolve(body || { ok: true }),
      text: () => Promise.resolve(JSON.stringify(body || { ok: true }))
    }); }
  };
  sent.push(rec);
  return p;
};

require('../prototype/js/sync.js');
let SY;

let pass = 0, fail = 0;
const t = (n, c, d) => {
  if (c) { pass++; console.log('  ✓ ' + n); }
  else { fail++; console.log('  ✗ ' + n, d === undefined ? '' : JSON.stringify(d)); }
};
const tick = () => new Promise(r => setImmediate(r));
const settle = async () => { for (let i = 0; i < 40; i++) await tick(); };
/* 큐가 멈출 때까지 날아간 요청을 차례로 응답해 줍니다.
   fetch 를 붙잡아 두는 시험이라 아무도 대신 풀어 주지 않습니다. */
const drain = async (max = 12) => {
  for (let i = 0; i < max; i++) {
    await settle();
    const next = sent.find(s => !s.done);
    if (!next) return;
    next.finish();
  }
  await settle();
};

(async () => {
  /* 로그인 상태를 만듭니다 — enqueue 는 토큰이 없으면 아무것도 안 합니다. */
  /* 토큰은 configure() 가 아니라 저장된 설정에 들어 있습니다 —
     로그인 결과를 흉내내려면 저장소에 직접 씁니다. */
  mem['mybody.sync.v1'] = JSON.stringify({
    baseUrl: 'http://localhost:9999', token: 'tok', handle: 'me', queue: [] });
  delete require.cache[require.resolve('../prototype/js/sync.js')];
  require('../prototype/js/sync.js');
  await settle();
  SY = window.MB_SYNC;
  sent.length = 0;

  console.log('\n[1] 요청이 날아가 있는 동안 같은 주 스냅샷을 또 넣는다');
  SY.enqueue('snapshot', { weekStart: '2026-09-14', payload: { plannedDays: 1 } });
  await settle();
  t('첫 스냅샷이 바로 날아간다', sent.length === 1, sent.map(s => s.url));
  const inflight = sent[0];

  /* 이 창이 버그의 자리입니다. 겹침 제거가 "지금 보내는 중" 인 맨 앞을
     빼 버리고, 응답이 오면 shift() 가 엉뚱한 것을 지웠습니다. */
  SY.enqueue('snapshot', { weekStart: '2026-09-14', payload: { plannedDays: 2 } });
  SY.enqueue('updateMe', { displayName: '나린' });
  SY.enqueue('snapshot', { weekStart: '2026-09-14', payload: { plannedDays: 4 } });
  await settle();
  t('날아가 있는 동안엔 더 안 보낸다', sent.length === 1, sent.length);

  inflight.finish();
  await drain();

  const ops = sent.map(s => s.url.replace(/^.*\/api/, ''));
  t('큐가 다 비워진다', SY.status().pending === 0, SY.status());
  t('이름 바꾸기가 안 지워졌다', ops.filter(o => o === '/me').length === 1, ops);
  const snaps = sent.filter(s => /snapshots/.test(s.url));
  t('스냅샷은 두 번만 갔다 (첫 것 + 마지막 것)', snaps.length === 2, ops);
  t('마지막으로 간 스냅샷이 마지막 상태다',
    snaps[snaps.length - 1].body.payload.plannedDays === 4,
    snaps.map(s => s.body.payload.plannedDays));
  t('거절당한 작업으로 기록되지 않았다', SY.status().lastError === null, SY.status().lastError);

  console.log('\n[2] 평범한 경우엔 순서대로 그대로 나간다');
  sent.length = 0;
  SY.enqueue('updateMe', { displayName: 'A' });
  await drain();
  SY.enqueue('updateMe', { displayName: 'B' });
  await drain();
  t('두 건 다 나갔다', sent.length === 2, sent.length);
  t('순서가 유지된다',
    sent[0].body.displayName === 'A' && sent[1].body.displayName === 'B',
    sent.map(s => s.body.displayName));
  t('큐가 비었다', SY.status().pending === 0);

  console.log('\n[3] 토큰이 죽은 뒤에 끈 공유는 조용히 사라지지 않는다');
  {
    /* api() 는 401 을 보면 조용히 로그아웃합니다 — 거기까지는 맞습니다.
       문제는 그 뒤였습니다. enqueue() 가 "토큰 없으면 그냥 돌아감" 이라,
       그 상태에서 공유를 끄면
         · 로컬 거울은 꺼지고
         · 큐에는 아무것도 안 들어가고 (pending 0, lastError null)
         · 화면은 "상대 화면에서 사라졌습니다" 라고 말하고
         · 다음 pull 이 서버 값으로 거울을 덮어 **다시 켜집니다.**
       껐다고 믿는 사람은 다시 확인하지 않습니다. */
    mem['mybody.sync.v1'] = JSON.stringify({
      baseUrl: 'http://localhost:9999', token: 'dead', handle: 'me', queue: [] });
    delete require.cache[require.resolve('../prototype/js/sync.js')];
    require('../prototype/js/sync.js');
    await settle();
    const S3 = window.MB_SYNC;
    sent.length = 0;

    S3.enqueue('setShare', { userId: 'friend1', patch: { streak: false } });
    await settle();
    t('일단 보내 본다', sent.length === 1, sent.map(x => x.url));
    sent[0].finish(401, { ok: false, reason: '로그인이 필요합니다' });
    await settle();
    t('토큰이 죽으면 로그아웃된다', S3.status().signedIn === false, S3.status());
    t('그냥 "로그인 안 함" 이 아니라 "끊김" 으로 구분한다',
      S3.status().disconnected === true, S3.status());

    // 이제 사용자가 또 하나를 끕니다 — 화면은 이게 되는 줄 압니다
    sent.length = 0;
    S3.enqueue('setShare', { userId: 'friend2', patch: { schedule: false } });
    await settle();
    /* 여기서 "lastError 가 있다" 만 보면 안 됩니다 — 바로 위 401 이
       남긴 옛 오류가 그대로 있어서, 고치기 전에도 통과합니다.
       **무엇이라고 적혀 있는가** 를 봐야 이 고장이 잡힙니다. */
    t('끊겼다는 사실이 사람 말로 적힌다',
      /끊겼|다시 로그인/.test(S3.status().lastError || ''), S3.status().lastError);
  }

  console.log('\n[4] 로그아웃은 나가기 전에 먼저 보낸다');
  {
    mem['mybody.sync.v1'] = JSON.stringify({
      baseUrl: 'http://localhost:9999', token: 'tok', handle: 'me',
      queue: [{ op: 'setShare', args: { userId: 'f1', patch: { streak: false } }, at: 1 }] });
    delete require.cache[require.resolve('../prototype/js/sync.js')];
    require('../prototype/js/sync.js');
    await settle();
    const S4 = window.MB_SYNC;
    sent.length = 0;

    /* 예전에는 여기서 큐를 통째로 버렸습니다. 오프라인에서 공유를 끄고
       로그아웃하면 그 끄기가 사라졌고, 다시 로그인하면 pull 이 서버
       값(= 켜진 채)으로 거울을 덮었습니다. */
    const out = S4.signOut();
    await settle();
    const shareReq = sent.find(x => /\/share\//.test(x.url));
    t('큐에 있던 공유 끄기를 먼저 보낸다', !!shareReq, sent.map(x => x.url));
    if (shareReq) shareReq.finish();
    await settle();
    const bye = sent.find(x => /signout/.test(x.url));
    if (bye) bye.finish();
    const r = await out;
    t('다 보냈으면 남은 것이 없다고 말한다', r && r.unsent === 0, r);
    t('로그아웃됐다', S4.status().signedIn === false);
  }

  console.log('\n[5] 못 보낸 채로 로그아웃하면 그 사실을 돌려준다');
  {
    mem['mybody.sync.v1'] = JSON.stringify({
      baseUrl: 'http://localhost:9999', token: 'tok', handle: 'me',
      queue: [{ op: 'setShare', args: { userId: 'f1', patch: { streak: false } }, at: 1 }] });
    delete require.cache[require.resolve('../prototype/js/sync.js')];
    require('../prototype/js/sync.js');
    await settle();
    const S5 = window.MB_SYNC;
    sent.length = 0;

    const out = S5.signOut();
    await settle();
    // 네트워크가 죽은 척 — 요청에 아무 대답도 안 합니다... 가 아니라
    // 500 으로 거절합니다(큐에 남는 쪽).
    const req = sent.find(x => /\/share\//.test(x.url));
    if (req) req.finish(500, { ok: false, reason: '서버 오류' });
    await settle();
    const bye = sent.find(x => /signout/.test(x.url));
    if (bye) bye.finish();
    const r = await out;
    t('못 보낸 개수를 알려준다', r && r.unsent === 1, r);
  }

  console.log('\n' + (fail ? '✗ ' + fail + '개 실패 / ' : '✓ 전부 통과 — ') + (pass + fail) + '개');
  process.exit(fail ? 1 : 0);
})().catch(e => { console.error(e); process.exit(1); });
