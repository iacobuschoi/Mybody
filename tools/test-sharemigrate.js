/* =============================================================================
 * tools/test-sharemigrate.js — 나중에 생긴 공유 항목이 옛 관계에서
 *                              저절로 켜지지 않는가
 *
 *   node tools/test-sharemigrate.js
 *
 * 이 파일이 왜 따로 있는가
 *   이 고장은 **서버를 새 버전으로 다시 띄우는 순간**에만 드러납니다.
 *   HTTP 로 두드리는 시험(test-social)은 한 프로세스 안에서만 돌아서
 *   구버전 저장 행을 만들 수가 없습니다.
 *
 * 실제로 일어난 일
 *   shareFields() 가 Object.assign(blankShare(), 저장값) 이었습니다.
 *   저장된 행에 없는 키는 blankShare() 의 기본값이 그대로 남습니다.
 *   그래서 schedule 을 기본 켜짐으로 넣자, 그 항목이 생기기 전에 저장된
 *   **모든 관계에서 저절로 켜졌습니다** — "전부 끄기" 를 눌러 둔 사람까지.
 *   껐다고 믿는 사람은 다시 확인하지 않습니다.
 *
 * 규칙: 사용자가 본 적 없는 항목은 켜져 있을 수 없습니다.
 *       동의는 읽은 문장에 대해 하는 것이지 코드에 대해 하는 것이 아닙니다.
 * ========================================================================== */
'use strict';
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { open, makeApi, SHARE_FIELDS, blankShare } = require('../server/db.js');

let pass = 0, fail = 0;
const t = (n, c, d) => {
  if (c) { pass++; console.log('  ✓ ' + n); }
  else { fail++; console.log('  ✗ ' + n, d === undefined ? '' : JSON.stringify(d)); }
};

const DB = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'mb-share-')), 't.db');
const PW = 'pw-123456', CONSENT = '2026-09-20';

function boot() { const db = open(DB); return { db, api: makeApi(db) }; }

/* --- 구버전 상태를 만듭니다 ------------------------------------------- */
let { db, api } = boot();
const A = api.signUp({ handle: 'gayoung', password: PW, displayName: '가영', healthConsent: CONSENT });
const B = api.signUp({ handle: 'narin', password: PW, displayName: '나린', healthConsent: CONSENT });
const C = api.signUp({ handle: 'dasom', password: PW, displayName: '다솜', healthConsent: CONSENT });
api.sendRequest(A.user.id, B.user.inviteCode); api.accept(B.user.id, A.user.id);
api.sendRequest(A.user.id, C.user.inviteCode); api.accept(C.user.id, A.user.id);

/* 지금 있는 항목들 중 "나중에 생긴 것" 하나를 골라, 그게 없던 시절의
   행을 직접 써 넣습니다. 목록 마지막에서 두 번째(schedule)가 그것입니다.
   항목이 또 늘면 이 시험은 그때 생긴 항목을 자동으로 고릅니다. */
const NEWEST = 'schedule';
const legacyKeys = SHARE_FIELDS.filter(k => k !== NEWEST);

function writeLegacy(owner, viewer, allOff) {
  const f = {};
  legacyKeys.forEach(k => { f[k] = allOff ? false : (k === 'streak'); });
  db.prepare('UPDATE shares SET fields=? WHERE owner_id=? AND viewer_id=?')
    .run(JSON.stringify(f), owner, viewer);
}
// 나린: 전부 끈 사람.  다솜: 손 안 댄 사람(체크인만 켜진 옛 기본값).
writeLegacy(B.user.id, A.user.id, true);
writeLegacy(C.user.id, A.user.id, false);
api.publishSnapshot(B.user.id, '2026-09-14', { checkedIn: true, plannedDays: 4, keptDays: 2 });
api.publishSnapshot(C.user.id, '2026-09-14', { checkedIn: true, plannedDays: 3, keptDays: 3 });
db.close();

/* --- 새 버전으로 다시 띄웁니다 ---------------------------------------- */
({ db, api } = boot());

console.log('\n[1] 전부 끈 사람에게서 새 항목이 켜지지 않는다');
const sB = api.shareFields(B.user.id, A.user.id);
t('새 항목이 꺼져 있다', sB[NEWEST] === false, sB);
t('나머지도 전부 꺼진 그대로', SHARE_FIELDS.every(k => sB[k] === false), sB);
const rowB = api.friendSnapshots(A.user.id, B.user.id, 4).rows[0];
t('친구 화면에 정말 아무것도 안 간다',
  Object.keys(rowB).filter(k => k !== 'weekStart').length === 0, rowB);

console.log('\n[2] 손 안 댄 옛 관계도 새 항목은 꺼진 채다');
const sC = api.shareFields(C.user.id, A.user.id);
t('켜 뒀던 것은 그대로 켜져 있다', sC.streak === true, sC);
t('새 항목은 꺼져 있다', sC[NEWEST] === false, sC);
const rowC = api.friendSnapshots(A.user.id, C.user.id, 4).rows[0];
t('체크인은 가고 일정은 안 간다',
  rowC.checkedIn === true && !('plannedDays' in rowC), rowC);

console.log('\n[3] 새로 맺는 관계는 지금 화면에 적힌 기본값 그대로');
const D = api.signUp({ handle: 'jihun', password: PW, displayName: '지훈', healthConsent: CONSENT });
api.sendRequest(A.user.id, D.user.inviteCode); api.accept(D.user.id, A.user.id);
const sD = api.shareFields(D.user.id, A.user.id);
const want = blankShare();
t('blankShare() 와 똑같다',
  SHARE_FIELDS.every(k => sD[k] === want[k]), { got: sD, want });
t('행동 항목 둘은 켜져 있다', sD.streak === true && sD[NEWEST] === true, sD);

console.log('\n[4] 마이그레이션은 여러 번 돌아도 안전하다');
const before = JSON.stringify(api.shareFields(C.user.id, A.user.id));
db.close();
({ db, api } = boot());
t('다시 띄워도 값이 안 바뀐다',
  JSON.stringify(api.shareFields(C.user.id, A.user.id)) === before, before);

console.log('\n[5] 저장된 행이 깨져 있어도 더 열리지 않는다');
db.prepare('UPDATE shares SET fields=? WHERE owner_id=? AND viewer_id=?')
  .run('{깨진 json', C.user.id, A.user.id);
const broken = api.shareFields(C.user.id, A.user.id);
t('몸에 대한 항목은 전부 꺼짐',
  !broken.weightTrend && !broken.smmTrend && !broken.bfmTrend && !broken.absolute, broken);
db.close();

console.log('\n' + (fail ? '✗ ' + fail + '개 실패 / ' : '✓ 전부 통과 — ') + (pass + fail) + '개');
process.exit(fail ? 1 : 0);
