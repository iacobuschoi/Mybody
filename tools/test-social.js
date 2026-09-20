/* =============================================================================
 * tools/test-social.js — 친구 기능 전 구간 검증 (HTTP 계층까지)
 *
 * 서버를 직접 띄우고 실제 요청을 쏩니다. 권한 판정은 서버가 하므로
 * db.js 를 직접 부르지 않고 HTTP 로 두드려야 의미가 있습니다.
 *
 *   node tools/test-social.js
 * ========================================================================== */
'use strict';
const { spawn } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const PORT = 8300 + Math.floor(Math.random() * 500);
const PAIR = 'test-pair-secret';
const DB = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'mybody-test-')), 'test.db');
const B = `http://localhost:${PORT}/api`;

let pass = 0, fail = 0;
const ok = (n, c, d) => {
  if (c) { pass++; console.log('  ✓', n); }
  else { fail++; console.log('  ✗', n, d === undefined ? '' : JSON.stringify(d)); }
};

/** 가입에는 페어링 비밀이, 로그인에는 비밀번호가 필요합니다. */
const PW = 'test-password-1';
function withPair(p, body) {
  /* 가입에는 건강정보 별도 동의가 필요합니다 — 검사도 같은 문을 지납니다. */
  if (p === '/auth/signup' && body) return Object.assign(
    { pairSecret: PAIR, password: PW, healthConsent: '2026-09-20' }, body);
  if (p === '/auth/signin' && body) return Object.assign({ password: PW }, body);
  return body;
}

async function call(m, p, body, tok) {
  body = withPair(p, body);
  const r = await fetch(B + p, {
    method: m,
    headers: { 'content-type': 'application/json', ...(tok ? { authorization: 'Bearer ' + tok } : {}) },
    body: body ? JSON.stringify(body) : undefined
  });
  return { status: r.status, json: await r.json().catch(() => ({})) };
}

async function waitUp(ms = 5000) {
  const until = Date.now() + ms;
  while (Date.now() < until) {
    try { if ((await fetch(`http://localhost:${PORT}/health`)).ok) return true; } catch {}
    await new Promise(r => setTimeout(r, 100));
  }
  throw new Error('서버가 뜨지 않습니다');
}

async function main() {
  console.log('\n[1] 로그인 · 계정');
  const A = await call('POST', '/auth/signup', { handle: 'gayoung', displayName: '가영' });
  const Bo = await call('POST', '/auth/signup', { handle: 'narin', displayName: '나린' });

  /* 건강정보 별도 동의(제23조) — 체성분을 올리는 것은 계정을 만드는 것과
     다른 일이고, 동의도 따로 받아야 합니다. 서버가 그걸 강제하는지 봅니다:
     화면이 실수로 빠뜨려도 여기서 막혀야 합니다. */
  const noConsent = await fetch(B + '/auth/signup', {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ handle: 'noconsent', password: PW, displayName: 'N', pairSecret: PAIR })
  });
  ok('건강정보 동의 없이는 가입 불가', noConsent.status === 400);
  const wrongVer = await fetch(B + '/auth/signup', {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ handle: 'oldver', password: PW, displayName: 'O',
                           pairSecret: PAIR, healthConsent: '2020-01-01' })
  });
  ok('옛 문구로 한 동의는 안 통한다', wrongVer.status === 400);
  ok('동의 시각이 남는다', !!(A.json.user && A.json.user.healthConsentAt), A.json.user);

  /* 보유 기간(제21조) — 52주가 지난 주간 요약은 지웁니다.
     화면이 보는 것은 26주뿐이고, 아무도 안 보는 오래된 건강정보를
     계속 들고 있을 이유가 없습니다. */
  {
    const tok = A.json.token;
    const day = (n) => new Date(Date.now() - n * 86400000).toISOString().slice(0, 10);
    /* 이번 주는 건드리지 않습니다 — 아래 공유 검사가 쓰는 행입니다.
       여기서 덮어쓰면 그쪽이 엉뚱한 값을 보고 실패합니다. */
    for (const d of [100, 300, 400, 800]) {
      await call('POST', '/snapshots', { weekStart: day(d), payload: { weightKg: 80 } }, tok);
    }
    /* 자기 주간 요약을 읽는 HTTP 길은 없습니다(그 길은 친구용입니다).
       보관은 저장소의 성질이므로 DB 를 직접 들여다봅니다 — 서버가
       진짜로 지웠는지를 봐야지, 안 보여주는 것만으로는 부족합니다. */
    const { DatabaseSync } = require('node:sqlite');
    const sdb = new DatabaseSync(DB);
    const weeks = sdb.prepare('SELECT week_start FROM snapshots WHERE owner_id = ? ORDER BY week_start')
      .all(A.json.user.id).map(r => r.week_start);
    sdb.close();
    ok('52주 지난 주간 요약은 안 남는다',
       weeks.length === 2 && weeks.every(w => w >= day(365)), weeks);
  }
  const ta = A.json.token, tb = Bo.json.token;
  ok('A 로그인', !!ta, A.json);
  ok('B 로그인', !!tb, Bo.json);
  ok('아이디 없으면 400', (await call('POST', '/auth/signin', {})).status === 400);
  ok('가입 코드 없으면 401', (await fetch(B + '/auth/signup', {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ handle: 'nopair', password: PW })
  })).status === 401);
  ok('짧은 비밀번호 거부', (await fetch(B + '/auth/signup', {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ handle: 'shortpw', password: 'abc', pairSecret: PAIR })
  })).status === 400);
  ok('같은 아이디로 두 번 가입 불가',
     (await call('POST', '/auth/signup', { handle: 'gayoung' })).json.ok === false);
  // 예전엔 handle 만으로 세션이 발급됐습니다 — 남의 아이디를 아는 사람이
  // 계정을 그대로 가져갈 수 있었습니다. 이제 비밀번호를 확인합니다.
  ok('맞는 비밀번호로 로그인 = 같은 계정',
     (await call('POST', '/auth/signin', { handle: 'gayoung' })).json.user.id === A.json.user.id);
  const noPw = await fetch(B + '/auth/signin', {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ handle: 'gayoung' })
  });
  ok('비밀번호 없이는 로그인 불가', noPw.status === 401);
  const badPw = await fetch(B + '/auth/signin', {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ handle: 'gayoung', password: 'wrong-password-x' })
  });
  ok('틀린 비밀번호도 불가', badPw.status === 401);
  ok('없는 아이디도 같은 답 (계정 존재 여부를 흘리지 않음)',
     (await fetch(B + '/auth/signin', {
       method: 'POST', headers: { 'content-type': 'application/json' },
       body: JSON.stringify({ handle: 'nosuchuser', password: 'whatever-123' })
     })).status === 401);

  const meA = (await call('GET', '/me', null, ta)).json.user;
  const meB = (await call('GET', '/me', null, tb)).json.user;
  ok('초대코드 발급', !!meA.inviteCode && !!meB.inviteCode);
  ok('초대코드가 서로 다름', meA.inviteCode !== meB.inviteCode);
  ok('토큰 없으면 401', (await call('GET', '/me')).status === 401);
  ok('가짜 토큰 401', (await call('GET', '/me', null, 'deadbeef')).status === 401);
  ok('이름 수정',
     (await call('PATCH', '/me', { displayName: '가영2' }, ta)).json.user.displayName === '가영2');

  console.log('\n[2] 친구 요청 · 수락');
  ok('없는 코드 거부', (await call('POST', '/friends/request', { inviteCode: 'ZZZZZZ' }, ta)).json.ok === false);
  ok('내 코드로 요청 거부', (await call('POST', '/friends/request', { inviteCode: meA.inviteCode }, ta)).json.ok === false);
  ok('친구 요청', (await call('POST', '/friends/request', { inviteCode: meB.inviteCode }, ta)).json.ok === true);
  ok('같은 요청 두 번은 거부', (await call('POST', '/friends/request', { inviteCode: meB.inviteCode }, ta)).json.ok === false);
  const bl = (await call('GET', '/friends', null, tb)).json.friends;
  ok('B에게 요청 도착', bl.incoming.length === 1 && bl.outgoing.length === 0, bl);
  ok('보낸 쪽은 outgoing 에 있다', (await call('GET', '/friends', null, ta)).json.friends.outgoing.length === 1);
  ok('내가 보낸 요청을 내가 수락할 수 없다', (await call('POST', '/friends/accept', { userId: meB.id }, ta)).json.ok === false);
  ok('수락 전엔 남의 추이를 못 본다', (await call('GET', '/snapshots/' + meB.id, null, ta)).json.ok === false);
  ok('수락', (await call('POST', '/friends/accept', { userId: meA.id }, tb)).json.ok === true);
  ok('양쪽 모두 친구 목록에',
     (await call('GET', '/friends', null, ta)).json.friends.accepted.length === 1 &&
     (await call('GET', '/friends', null, tb)).json.friends.accepted.length === 1);

  console.log('\n[3] 공유 — 켠 것만 나간다');
  const payload = { dWeightKg: -0.8, dSmmKg: 0.2, dBfmKg: -0.9, progressPct: 42, checkedIn: true,
                    weightKg: 86.3, smmKg: 38.1, bfmKg: 19.9, pbfPct: 23.1 };
  await call('POST', '/snapshots', { weekStart: '2026-09-14', payload }, tb);
  const BODY = ['dWeightKg', 'dSmmKg', 'dBfmKg', 'progressPct', 'weightKg', 'smmKg', 'bfmKg', 'pbfPct'];
  let row = (await call('GET', '/snapshots/' + meB.id, null, ta)).json.rows[0];
  ok('기본값: 몸에 대한 정보는 하나도 안 나간다', BODY.every(k => !(k in row)), row);
  ok('기본값: 체크인 여부만 보인다', 'checkedIn' in row, row);

  ok('B가 체중만 켠다', (await call('PUT', '/share/' + meA.id, { weightTrend: true }, tb)).json.ok === true);
  row = (await call('GET', '/snapshots/' + meB.id, null, ta)).json.rows[0];
  ok('체중 변화 보임', 'dWeightKg' in row, row);
  ok('골격근·체지방은 여전히 숨김', !('dSmmKg' in row) && !('dBfmKg' in row), row);
  ok('실제 수치는 따로 켜야 나온다', !('weightKg' in row), row);
  ok('남의 공유 설정은 못 바꾼다', (await call('PUT', '/share/' + meB.id, { smmTrend: true }, ta)).json.ok === false ||
     !('dSmmKg' in (await call('GET', '/snapshots/' + meB.id, null, ta)).json.rows[0]));

  // 회귀 방지: absolute 는 표시 방식일 뿐, 항목을 새로 여는 스위치가 아닙니다.
  await call('PUT', '/share/' + meA.id, { absolute: true }, tb);
  row = (await call('GET', '/snapshots/' + meB.id, null, ta)).json.rows[0];
  ok('실제 수치는 켠 항목에만 붙는다', 'weightKg' in row, row);
  ok('안 켠 항목이 실제 수치로 새지 않는다',
     !('smmKg' in row) && !('bfmKg' in row) && !('pbfPct' in row), row);
  ok('아무 항목도 안 켜면 absolute 는 꺼진다',
     (await call('PUT', '/share/' + meA.id, { weightTrend: false }, tb)).json.share.absolute === false);

  console.log('\n[4] 끊기 · 차단 · 탈퇴');
  ok('친구 끊기', (await call('DELETE', '/friends/' + meB.id, null, ta)).json.ok === true);
  ok('끊으면 즉시 안 보인다', (await call('GET', '/snapshots/' + meB.id, null, ta)).json.ok === false);
  await call('POST', '/friends/request', { inviteCode: meB.inviteCode }, ta);
  ok('차단', (await call('POST', '/friends/block', { userId: meA.id }, tb)).json.ok === true);
  ok('차단하면 다시 요청 못 한다', (await call('POST', '/friends/request', { inviteCode: meB.inviteCode }, ta)).json.ok === false);

  console.log('\n[5] 동기화');
  await call('POST', '/sync/push', { records: [
    { kind: 'scan', id: 's1', updatedAt: '2026-09-01T00:00:00Z', payload: { weightKg: 86.3 } }
  ] }, ta);
  const pull = (await call('GET', '/sync/pull?since=', null, ta)).json;
  ok('푸시한 게 그대로 돌아온다', pull.records.length === 1 && pull.records[0].payload.weightKg === 86.3, pull);
  ok('커서 뒤는 빈 결과',
     (await call('GET', '/sync/pull?since=' + encodeURIComponent(pull.cursor), null, ta)).json.records.length === 0);
  ok('남의 기록은 안 섞인다', (await call('GET', '/sync/pull?since=', null, tb)).json.records.length === 0);

  console.log('\n[6] 보안 회귀 — 한 번 열렸던 구멍들');

  // 차단 우회: 차단당한 사람이 "친구 끊기"로 자기를 막고 있는 행을 지웠습니다
  const V = await call('POST', '/auth/signup', { handle: 'victim', displayName: '차단당함' });
  const tv = V.json.token, meV = (await call('GET', '/me', null, tv)).json.user;
  await call('POST', '/friends/request', { inviteCode: meV.inviteCode }, ta);
  await call('POST', '/friends/accept', { userId: meA.id }, tv);
  ok('A가 V를 차단', (await call('POST', '/friends/block', { userId: meV.id }, ta)).json.ok === true);
  ok('차단당한 V는 그 관계를 못 지운다',
     (await call('DELETE', '/friends/' + meA.id, null, tv)).json.ok === false);
  ok('V의 맞차단으로 A의 차단을 덮어쓸 수 없다',
     (await call('POST', '/friends/block', { userId: meA.id }, tv)).json.ok === false);
  ok('V는 차단을 풀 수 없다',
     (await call('POST', '/friends/unblock', { userId: meA.id }, tv)).json.ok === false);
  ok('A는 자기 차단을 풀 수 있다',
     (await call('POST', '/friends/unblock', { userId: meV.id }, ta)).json.ok === true);

  // setShare 강제변환: 문자열 "false" 가 스위치를 켰습니다
  await call('POST', '/friends/request', { inviteCode: meV.inviteCode }, ta);
  await call('POST', '/friends/accept', { userId: meA.id }, tv);
  const coerce = await call('PUT', '/share/' + meV.id,
    { weightTrend: 'false', smmTrend: 'false', bfmTrend: 'false', absolute: 'false' }, ta);
  ok('문자열 "false" 는 거부된다', coerce.json.ok === false, coerce.json);
  const after = await call('GET', '/share/' + meV.id, null, ta);
  ok('거부된 요청이 아무것도 켜지 않았다',
     !after.json.share.weightTrend && !after.json.share.absolute, after.json.share);

  // pbfPct 역산: 체지방량과 체지방률이 같이 나가면 체중이 복원됩니다
  await call('POST', '/snapshots', { weekStart: '2026-09-14',
    payload: { dBfmKg: -0.9, bfmKg: 18.9, pbfPct: 25.5, weightKg: 74.2 } }, ta);
  await call('PUT', '/share/' + meV.id, { bfmTrend: true, absolute: true }, ta);
  const leak = (await call('GET', '/snapshots/' + meA.id, null, tv)).json.rows[0];
  ok('체중을 안 켰으면 체지방률도 안 나간다', !('pbfPct' in leak), leak);
  ok('체중도 당연히 안 나간다', !('weightKg' in leak), leak);
  await call('PUT', '/share/' + meV.id, { weightTrend: true }, ta);
  const both = (await call('GET', '/snapshots/' + meA.id, null, tv)).json.rows[0];
  ok('둘 다 켜면 체지방률이 나온다', 'pbfPct' in both, both);

  // 동기화 커서: 같은 타임스탬프의 형제 행이 영구 유실됐습니다
  const SAME = '2026-09-10T00:00:00.000Z';
  await call('POST', '/sync/push', { records: [
    { kind: 'scan', id: 'x1', updatedAt: SAME, payload: { n: 1 } },
    { kind: 'goal', id: 'x1', updatedAt: SAME, payload: { n: 2 } },
    { kind: 'checkin', id: 'x1', updatedAt: SAME, payload: { n: 3 } }
  ] }, tv);
  let cursor = '', seen = 0, guard = 0;
  while (guard++ < 10) {
    const page = (await call('GET', '/sync/pull?since=' + encodeURIComponent(cursor) + '&limit=1', null, tv)).json;
    if (!page.records.length) break;
    seen += page.records.length;
    cursor = page.cursor;
  }
  ok('같은 시각 형제 행 3건이 한 건도 안 샌다', seen === 3, { seen });
  ok('잘못된 updatedAt 은 거부된다',
     (await call('POST', '/sync/push', { records: [
       { kind: 'scan', id: 'bad', updatedAt: 'zzzz', payload: {} }
     ] }, tv)).json.accepted === 0);
  ok('limit=abc 로 500이 나지 않는다',
     (await call('GET', '/sync/pull?since=&limit=abc', null, tv)).status === 200);
  ok('userId 없는 block 도 500이 아니다',
     (await call('POST', '/friends/block', {}, tv)).status === 400);

  console.log('\n[6-2] 프로필 사진');
  /* 1×1 JPEG. 실제 사진을 만들 필요는 없습니다 — 서버는 형식과 크기만 봅니다. */
  const JPG = 'data:image/jpeg;base64,' + 'A'.repeat(64) + '==';
  ok('사진을 올릴 수 있다',
     (await call('PATCH', '/me', { avatar: JPG }, ta)).json.user.avatar === JPG);
  ok('다시 읽어도 남아 있다', (await call('GET', '/me', null, ta)).json.user.avatar === JPG);
  ok('이름만 바꾸면 사진은 그대로다',
     (await call('PATCH', '/me', { displayName: '가영' }, ta)).json.user.avatar === JPG);
  ok('24KB 넘는 사진은 거절한다',
     (await call('PATCH', '/me', { avatar: 'data:image/jpeg;base64,' + 'A'.repeat(30000) }, ta)).status === 400);
  ok('SVG 는 받지 않는다',
     (await call('PATCH', '/me', { avatar: 'data:image/svg+xml;base64,QQ==' }, ta)).status === 400);
  ok('http 주소는 받지 않는다',
     (await call('PATCH', '/me', { avatar: 'https://example.com/a.jpg' }, ta)).status === 400);
  ok('거절당해도 원래 사진은 안 지워진다',
     (await call('GET', '/me', null, ta)).json.user.avatar === JPG);
  /* 앞 절에서 가영·나린은 이미 차단 상태라, 사진이 목록에 실리는지는
     새 두 사람으로 봅니다. 끊긴 관계를 재활용하면 통과 여부가 앞 절
     순서에 딸려 다닙니다. */
  const P1 = await call('POST', '/auth/signup', { handle: 'pic1', displayName: '사진하나' });
  const P2 = await call('POST', '/auth/signup', { handle: 'pic2', displayName: '사진둘' });
  const t1 = P1.json.token, t2 = P2.json.token;
  await call('POST', '/friends/request', { inviteCode: P2.json.user.inviteCode }, t1);
  await call('POST', '/friends/accept', { userId: P1.json.user.id }, t2);
  await call('PATCH', '/me', { avatar: JPG }, t1);
  const friendsOf2 = () => call('GET', '/friends', null, t2).then(r => r.json.friends);
  ok('수락한 친구 목록에는 사진이 실려 온다',
     ((await friendsOf2()).accepted[0] || {}).avatar === JPG);
  ok('null 을 보내면 지워진다',
     (await call('PATCH', '/me', { avatar: null }, t1)).json.user.avatar === null);
  ok('지운 뒤 친구 목록에도 없다',
     ((await friendsOf2()).accepted[0] || {}).avatar === null);

  /* 아직 수락 안 한 요청에는 사진을 안 싣습니다 — 초대 코드만 아는
     사람이 남의 화면에 이미지를 밀어 넣지 못하게. */
  const P3 = await call('POST', '/auth/signup', { handle: 'pic3', displayName: '사진셋' });
  await call('PATCH', '/me', { avatar: JPG }, P3.json.token);
  await call('POST', '/friends/request', { inviteCode: P2.json.user.inviteCode }, P3.json.token);
  ok('수락 전 요청에는 사진이 안 실린다',
     ((await friendsOf2()).incoming[0] || {}).avatar === undefined,
     (await friendsOf2()).incoming[0]);

  console.log('\n[7] 탈퇴 뒷정리');
  const C = await call('POST', '/auth/signup', { handle: 'temp', displayName: '임시' });
  ok('탈퇴', (await call('DELETE', '/me', null, C.json.token)).json.ok === true);
  ok('탈퇴하면 토큰이 죽는다', (await call('GET', '/me', null, C.json.token)).status === 401);
  ok('탈퇴한 계정 코드로는 친구 요청이 안 된다',
     (await call('POST', '/friends/request', { inviteCode: C.json.user.inviteCode }, ta)).json.ok === false);
}

const srv = spawn(process.execPath, [path.join(__dirname, '..', 'server', 'server.js')], {
  env: { ...process.env, PORT: String(PORT), DB, PAIR_SECRET: PAIR },
  stdio: 'ignore'
});
process.on('exit', () => srv.kill());

waitUp()
  .then(main)
  .then(() => {
    console.log(`\n통과 ${pass} / 실패 ${fail}`);
    srv.kill();
    process.exit(fail ? 1 : 0);
  })
  .catch(e => { console.error(e); srv.kill(); process.exit(1); });
