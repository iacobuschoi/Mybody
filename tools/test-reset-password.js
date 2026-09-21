/* =============================================================================
 * tools/test-reset-password.js — 주인이 대신 풀어 주는 비밀번호 초기화
 *
 *   node tools/test-reset-password.js
 *
 * 여기서 봐야 하는 것은 "비밀번호가 바뀌는가" 가 아닙니다. 그건 쉽습니다.
 * 봐야 하는 것은 **초기화를 하고 나서도 그 사람이 그 사람인가** 입니다.
 *
 * 이 기능이 생긴 이유가 그겁니다 — 사람들이 로그인이 안 되니까 새 계정을
 * 만들고 있었고, 그러면 측정 기록과 친구 연결이 통째로 끊겼습니다.
 * 초기화가 그걸 똑같이 끊어 버리면 만든 의미가 없습니다.
 * ========================================================================== */
'use strict';
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const ROOT = path.join(__dirname, '..');
const DB = require(path.join(ROOT, 'server', 'db.js'));

let pass = 0, fail = 0;
const ok = (n, c, d) => {
  if (c) { pass++; console.log('  ✓', n); }
  else { fail++; console.log('  ✗', n, d === undefined ? '' : JSON.stringify(d)); }
};

const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'mybody-reset-'));
const file = path.join(dir, 'test.db');

function run(args) {
  const r = spawnSync(process.execPath, [path.join(ROOT, 'tools', 'reset-password.js')].concat(args),
    { cwd: ROOT, encoding: 'utf8', timeout: 30000,
      env: Object.assign({}, process.env, { DB: file, NODE_NO_WARNINGS: '1' }) });
  return { out: (r.stdout || '') + (r.stderr || ''), code: r.status };
}

function main() {
  const api = DB.makeApi(DB.open(file));
  const consent = DB.HEALTH_CONSENT_VERSION;

  console.log('\n[1] 준비 — 기록과 친구가 있는 계정');
  const a = api.signUp({ handle: 'chulsoo', password: 'oldpassword1', displayName: '철수',
                         pairSecret: null, healthConsent: consent });
  const b = api.signUp({ handle: 'younghee', password: 'otherpassword1', displayName: '영희',
                         pairSecret: null, healthConsent: consent });
  ok('두 계정이 생긴다', a.ok && b.ok, [a.reason, b.reason]);

  const aId = a.user.id, bId = b.user.id;
  ok('사용자 id 를 얻는다', !!aId && !!bId);

  const put = api.publishSnapshot(aId, '2026-08-31', { weightTrend: 'down', streak: 3 });
  ok('주간 기록이 올라간다', put.ok, put.reason);
  const req = api.sendRequest(aId, b.user.inviteCode);
  ok('친구 요청이 간다', req.ok, req.reason);
  const acc = api.accept(bId, aId);
  ok('친구 수락이 된다', acc.ok, acc.reason);

  const before = api.listFriends(aId);
  const beforeSnaps = api.friendSnapshots(bId, aId, 26);
  ok('기록이 있다', (beforeSnaps.rows || []).length > 0, beforeSnaps.rows && beforeSnaps.rows.length);
  ok('친구가 있다', (before.accepted || []).length === 1, before);

  console.log('\n[2] 옛 비밀번호로 세션을 하나 만들어 둔다');
  const sess = api.signIn({ handle: 'chulsoo', password: 'oldpassword1' });
  ok('로그인된다', sess.ok, sess.reason);
  const oldToken = sess.token;
  ok('토큰을 받았다', !!oldToken);
  ok('그 토큰이 실제로 통한다', !!api.userForToken(oldToken));

  console.log('\n[3] 목록 보기 — 비밀은 안 싣는다');
  {
    const r = run([]);
    ok('두 사람이 보인다', /chulsoo/.test(r.out) && /younghee/.test(r.out), r.out);
    /* 목록에 해시나 토큰이 섞여 나오면, 이 화면을 캡처해 보내는 순간
       그게 같이 나갑니다. 주인은 그걸 비밀이라고 생각하지 않습니다. */
    ok('비밀번호 해시가 안 보인다', !/pw_hash|salt|token/i.test(r.out), r.out);
  }

  console.log('\n[4] 없는 아이디는 조용히 성공하지 않는다');
  {
    const r = run(['nosuchperson']);
    ok('실패로 끝난다', r.code !== 0, r.code);
    ok('없다고 말한다', /그런 아이디가 없습니다/.test(r.out), r.out);
  }

  console.log('\n[5] 초기화');
  const r = run(['chulsoo']);
  ok('성공으로 끝난다', r.code === 0, r.code);
  const pw = (r.out.match(/새 비밀번호\s+(\S+)/) || [])[1];
  const rc = (r.out.match(/새 복구 코드\s+(\S+)/) || [])[1];
  ok('새 비밀번호를 보여준다', !!pw, r.out);
  ok('새 복구 코드도 같이 준다', !!rc, r.out);
  ok('복구 코드가 한 번만 보인다고 말한다', /지금만/.test(r.out), r.out);

  console.log('\n[6] 초기화 뒤 — 그 사람이 그 사람인가');
  {
    const fresh = DB.makeApi(DB.open(file));
    const inNew = fresh.signIn({ handle: 'chulsoo', password: pw });
    ok('새 비밀번호로 들어간다', inNew.ok, inNew.reason);

    const inOld = fresh.signIn({ handle: 'chulsoo', password: 'oldpassword1' });
    ok('옛 비밀번호는 막힌다', !inOld.ok, inOld);

    /* 이게 이 시험의 핵심입니다. 새 계정을 만들면 잃는 것들이
       초기화에서는 남아 있어야 합니다 — 안 그러면 만든 의미가 없습니다. */
    const snaps = fresh.friendSnapshots(bId, aId, 26);
    ok('측정 기록이 그대로 있다', (snaps.rows || []).length === (beforeSnaps.rows || []).length,
       [(snaps.rows || []).length, (beforeSnaps.rows || []).length]);

    const fr = fresh.listFriends(aId);
    ok('친구도 그대로 있다', (fr.accepted || []).length === 1, fr);

    /* 세션은 반대로 **끊겨야** 합니다. 초기화하는 이유가 "남이 들어갔다"
       일 수도 있는데, 그때 옛 토큰이 살아 있으면 초기화가 무의미합니다. */
    const who = fresh.userForToken(oldToken);
    ok('쓰던 세션은 끊긴다', !who, who && who.handle);
  }

  console.log('\n[7] 새 복구 코드가 진짜 듣는다');
  {
    const fresh = DB.makeApi(DB.open(file));
    const rec = fresh.recoverPassword({ handle: 'chulsoo', code: rc, password: 'brandnewpass1' });
    ok('새 복구 코드로 비밀번호를 바꾼다', rec.ok, rec.reason);
    const inAgain = DB.makeApi(DB.open(file)).signIn({ handle: 'chulsoo', password: 'brandnewpass1' });
    ok('그 비밀번호로 들어간다', inAgain.ok, inAgain.reason);
  }
}

try { main(); } catch (e) { console.error(e); fail++; }
console.log(`\n통과 ${pass} / 실패 ${fail}`);
try { fs.rmSync(dir, { recursive: true, force: true }); } catch (e) {}
process.exit(fail ? 1 : 0);
