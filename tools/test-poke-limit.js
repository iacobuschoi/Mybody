/* =============================================================================
 * tools/test-poke-limit.js — 운동 독촉을 얼마나 자주 보낼 수 있나
 *
 *   node tools/test-poke-limit.js
 *
 * 주인의 말: "하루한번가능>1초에 한번으로 고치고 · '1분에 한사람에게 10번 이상이면 30분 제한'
 * 으로 · 사람마다 카운팅". 규칙은 server/db.js 의 poke() 머리 주석.
 *
 * 시각을 poke(…, now) 로 넣어 봅니다 — 진짜로 1분 · 30분을 기다리지 않습니다.
 * ========================================================================== */
'use strict';
require('./testenv.js');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const ROOT = path.join(__dirname, '..');
const DBM = require(path.join(ROOT, 'server', 'db.js'));

let pass = 0, fail = 0;
const ok = (n, c, d) => {
  if (c) { pass++; console.log('  ✓', n); }
  else { fail++; console.log('  ✗', n, d === undefined ? '' : JSON.stringify(d).slice(0, 400)); }
};

const TMP = fs.mkdtempSync(path.join(os.tmpdir(), 'mybody-poke-'));
const PW = 'test-password-1';
const db = DBM.open(path.join(TMP, 'poke.db'));
const api = DBM.makeApi(db);
const mk = h => api.signUp({ handle: h, password: PW, displayName: h, healthConsent: DBM.HEALTH_CONSENT_VERSION });
const friend = (a, b) => { api.sendRequest(a.user.id, b.user.inviteCode); api.accept(b.user.id, a.user.id); };

const A = mk('poke-a'), B = mk('poke-b'), C = mk('poke-c'), D = mk('poke-d');
friend(A, B); friend(A, C); friend(D, B);
const a = A.user.id, b = B.user.id, c = C.user.id, d = D.user.id;
const T0 = Date.parse('2026-09-29T12:00:00.000Z');
const S = 1000, M = 60 * 1000;

console.log('\n[1] 1초에 한 번 — 하루 한 번이 아님');
{
  const r1 = api.poke(a, b, 'workout', T0);
  ok('보낸다', r1.ok === true && !r1.limited, r1);
  const r2 = api.poke(a, b, 'workout', T0 + 999);
  ok('1초 안에 또 → tooFast (already 없음 — 옛 앱이 단추를 끄지 않게)',
     r2.ok === false && r2.tooFast === true && !r2.already && !r2.limited, r2);
  const r3 = api.poke(a, b, 'workout', T0 + 1000);
  ok('딱 1초 뒤면 간다', r3.ok === true, r3);
  const r4 = api.poke(a, b, 'workout', T0 + 1000 + 2 * S);
  ok('같은 날 여러 번 간다', r4.ok === true, r4);
  ok('다른 친구(C)에게는 바로 간다 — 사람마다 따로', api.poke(a, c, 'workout', T0 + 1000 + 2 * S + 10).ok === true);
  ok('다른 사람(D)이 같은 B 에게 보내는 것도 따로', api.poke(d, b, 'workout', T0 + 1000 + 2 * S + 10).ok === true);
  const pulled = api.pullPokes(b).pokes;
  ok('받는 쪽은 보낸 만큼(A 3 + D 1) 가져간다', pulled.length === 4, pulled.length);
}

console.log('\n[2] 1분에 10번이면 10번째는 가고, 그 사람에게만 30분 쉼');
{
  const X = mk('poke-x'), Y = mk('poke-y'), Z = mk('poke-z');
  friend(X, Y); friend(X, Z);
  const x = X.user.id, y = Y.user.id, z = Z.user.id;
  const t = T0 + 10 * M;
  let last;
  for (let i = 0; i < 9; i++) {
    last = api.poke(x, y, 'workout', t + i * 2 * S);
    if (!last.ok || last.limited) break;
  }
  ok('9번째까지는 그냥 간다', last.ok === true && !last.limited, last);
  const tenth = api.poke(x, y, 'workout', t + 9 * 2 * S);
  ok('10번째(1분 안)는 가고 limited · until 이 붙는다', tenth.ok === true && tenth.limited === true &&
     Date.parse(tenth.until) === t + 18 * S + 30 * M, tenth);
  const after = api.poke(x, y, 'workout', t + 18 * S + 5 * S);
  ok('그다음은 거절 — limited · already · 30분 안내', after.ok === false && after.limited === true &&
     after.already === true && /30분 뒤에/.test(after.reason) && after.retryAfter === 30 * 60 - 5, after);
  ok('다른 친구(Z)에게는 그대로 간다', api.poke(x, z, 'workout', t + 18 * S + 5 * S).ok === true);
  const late = api.poke(x, y, 'workout', t + 18 * S + 30 * M - 1);
  ok('30분이 되기 1ms 전에도 거절 (1분 뒤에)', late.ok === false && late.limited === true && /1분 뒤에/.test(late.reason), late);
  const back = api.poke(x, y, 'workout', t + 18 * S + 30 * M);
  ok('30분이 지나면 다시 간다', back.ok === true && !back.limited, back);
  ok('막힌 시도는 세지 않는다 — 쉼이 끝난 뒤 한 번 보냈다고 다시 막히지 않음',
     api.poke(x, y, 'workout', t + 18 * S + 30 * M + 2 * S).ok === true);
}

console.log('\n[3] 1분 넘게 걸쳐 10번이면 쉬지 않는다');
{
  const P = mk('poke-p'), Q = mk('poke-q');
  friend(P, Q);
  const p = P.user.id, qq = Q.user.id;
  const t = T0 + 100 * M;
  let r;
  for (let i = 0; i < 20; i++) {
    r = api.poke(p, qq, 'workout', t + i * 7 * S);   // 7초 간격 → 10번이 63초
    if (!r.ok) break;
  }
  ok('7초마다 20번 — 모두 간다(어느 10번도 1분 안이 아님)', r.ok === true && !r.limited, r);
}

console.log('\n[4] 서버를 다시 켜도 쉼은 그대로 (기록에서 셈)');
{
  const U = mk('poke-u'), V = mk('poke-v');
  friend(U, V);
  const u = U.user.id, v = V.user.id;
  const t = T0 + 300 * M;
  for (let i = 0; i < 10; i++) api.poke(u, v, 'workout', t + i * S);
  const api2 = DBM.makeApi(db);
  const r = api2.poke(u, v, 'workout', t + 10 * M);
  ok('새 api 로도 거절', r.ok === false && r.limited === true, r);
}

console.log('\n[5] 시계가 뒤로 가도 영영 막히지 않는다');
{
  const G = mk('poke-g'), H = mk('poke-h');
  friend(G, H);
  const g = G.user.id, h = H.user.id;
  const t = T0 + 500 * M;
  api.poke(g, h, 'workout', t);
  const r = api.poke(g, h, 'workout', t - 60 * M);
  ok('한 시간 앞 시각으로 보내도 tooFast 로 막지 않는다', r.ok === true, r);
}

db.close();
fs.rmSync(TMP, { recursive: true, force: true });
console.log(`\n${pass} 통과 / ${fail} 실패`);
process.exit(fail ? 1 : 0);
