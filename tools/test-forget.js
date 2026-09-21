/* =============================================================================
 * test-forget.js — **지웠다고 한 것이 정말 지워지는가**
 *
 * 이 앱은 몇 군데서 "지웁니다" 라고 말합니다. 그 말은 확인할 수 있어야
 * 합니다 — 못 지킨 약속은 안 한 약속보다 나쁩니다.
 *
 * 여기서 보는 것 둘 (둘 다 실제로 새고 있던 자리입니다):
 *
 *  1. 탈퇴하면 서버에 **판독 횟수**도 안 남는가.
 *     ocr_usage 만 users 를 참조하지 않아서 외래키가 없었고, 그날 치
 *     `{ day, who: 'user_e73fe…', n: 1 }` 이 남았습니다. db.js 자신이
 *     "안 남기기로 한 종류의 기록" 이라고 적어 둔 것입니다.
 *
 *  2. 상대가 탈퇴하면 **내 기기에서도 그 사람이 사라지는가.**
 *     친구 관계·공유·스냅샷은 pull 마다 다시 만드는데 사용자 거울만
 *     더하기만 해서, 지운 계정의 표시 이름과 얼굴 사진(base64 JPEG)이
 *     내 폰 localStorage 에 영원히 남았습니다.
 * ========================================================================== */
'use strict';
require('./testenv');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

let pass = 0, fail = 0;
const ok = (m) => { pass++; console.log('  ✓ ' + m); };
const no = (m, d) => { fail++; console.log('  ✗ ' + m + (d ? '\n      ' + d : '')); };

console.log('\n지웠다고 한 것이 정말 지워지는가\n');

/* --- 1. 서버: 탈퇴하면 판독 횟수도 사라지는가 --------------------------- */
{
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'mybody-forget-'));
  const file = path.join(dir, 'test.db');
  const { open, makeApi, HEALTH_CONSENT_VERSION } = require('../server/db.js');
  const db = makeApi(open(file));

  const a = db.signUp({ handle: 'jihun', password: 'pw-that-is-long-enough',
                        displayName: '지훈', healthConsent: HEALTH_CONSENT_VERSION });
  if (!a.ok) { no('계정을 못 만들었습니다', a.reason); }
  else {
    const uid = a.user.id;
    db.bumpOcr(uid);
    db.bumpOcr(uid);
    const before = db.bumpOcr(uid);
    if (before.user >= 3) ok('판독 횟수가 쌓입니다 (' + before.user + '장)');
    else no('판독 횟수가 안 쌓입니다');

    db.deleteMe(uid);

    /* 같은 날짜로 다시 물어봅니다 — pruneOcr 는 지난 날만 지우므로
       오늘 것이 남아 있으면 여기서 잡힙니다. */
    const raw = db.raw ? db.raw : null;
    const after = db.bumpOcr(uid);   // 다시 1 부터 세면 앞의 기록이 사라진 것입니다
    if (after.user === 1) ok('탈퇴하면 그 사람의 판독 횟수가 서버에 안 남습니다');
    else no('탈퇴 뒤에도 판독 횟수가 남아 있습니다 (' + after.user + '장)',
            '"누가 언제 몇 장 올렸나" 는 이 앱이 안 남기기로 한 기록입니다');
    void raw;
  }
  try { fs.rmSync(dir, { recursive: true, force: true }); } catch (e) {}
}

/* --- 2. 기기: 상대가 탈퇴하면 내 거울에서도 사라지는가 ------------------ */
{
  const mem = new Map();
  global.window = global;
  global.localStorage = {
    getItem: (k) => (mem.has(k) ? mem.get(k) : null),
    setItem: (k, v) => { mem.set(k, String(v)); },
    removeItem: (k) => { mem.delete(k); }
  };
  delete require.cache[require.resolve('../prototype/js/backend.js')];
  require('../prototype/js/backend.js');
  const B = global.MB_BACKEND;

  /* 서버가 준 것처럼 꾸며서 거울에 넣습니다. */
  const snapWith = (friends) => ({
    me: { id: 'me1', handle: 'me', displayName: '나', inviteCode: 'AAA', createdAt: 'x' },
    friends: friends,
    snapshots: []
  });

  B.mirror(snapWith({
    accepted: [{ id: 'gone1', displayName: '떠난사람', since: 'x',
                 avatar: 'data:image/jpeg;base64,/9j/4AAQSkZJRg==' }],
    incoming: [], outgoing: [], blocked: []
  }));

  const dbNow = () => JSON.parse(localStorage.getItem('mybody.backend.v1') || '{}');
  if (dbNow().users && dbNow().users.gone1) ok('친구가 거울에 들어옵니다');
  else no('친구가 거울에 안 들어옵니다');
  if ((dbNow().users.gone1 || {}).avatar) ok('얼굴 사진도 같이 들어옵니다');
  else no('얼굴 사진이 안 들어옵니다 — 이 시험이 무의미해집니다');

  /* 상대가 계정을 지웠습니다. 서버는 이제 그 사람을 안 돌려줍니다. */
  B.mirror(snapWith({ accepted: [], incoming: [], outgoing: [], blocked: [] }));

  const users = dbNow().users || {};
  if (!users.gone1) ok('탈퇴한 친구가 내 기기에서도 사라집니다 (이름 · 얼굴 사진)');
  else no('탈퇴한 친구가 내 기기에 남아 있습니다',
          '이름: ' + users.gone1.displayName +
          (users.gone1.avatar ? ' · 얼굴 사진 있음' : ''));

  if (users.me1) ok('나 자신은 남습니다');
  else no('나 자신까지 지워졌습니다');
}

console.log('\n통과 ' + pass + ' / 실패 ' + fail);
process.exit(fail ? 1 : 0);
