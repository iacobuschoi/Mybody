/* =============================================================================
 * tools/reset-password.js — 친구가 비밀번호를 잊었을 때 주인이 풀어 줍니다
 *
 *   node tools/reset-password.js                 누가 있는지 봅니다
 *   node tools/reset-password.js <아이디>         새 비밀번호를 만들어 줍니다
 *   node tools/reset-password.js <아이디> --ask   직접 정합니다 (가려서 물어봅니다)
 *
 * 왜 있나
 *   이 서버는 메일을 안 보냅니다. 그래서 비밀번호를 잊은 사람이 돌아올
 *   길은 가입할 때 한 번 보여준 복구 코드뿐입니다. 그걸 안 적어 둔
 *   사람에게는 길이 없었습니다.
 *
 *   그래서 실제로 무슨 일이 났냐면 — 서버 로그 한 판에서
 *     로그인 실패 6회 · 로그인 성공 1회 · 가입 7회
 *   가 나왔습니다. 사람들이 로그인이 안 되니까 **그냥 새 계정을 만들고
 *   있었습니다.** 그러면 그 사람의 측정 기록과 친구 연결이 통째로
 *   끊기고, 친구 목록에는 아무도 안 쓰는 계정이 남습니다.
 *
 *   서버가 주인 컴퓨터에 있으니 주인은 풀어 줄 수 있습니다. 그 한 줄이
 *   없어서 사람이 막혀 있었습니다.
 *
 * 왜 HTTP 로 안 여는가
 *   "비밀번호를 대신 바꿔 주는 주소" 가 인터넷에 열려 있으면 그건
 *   계정 탈취 창구입니다. 이건 그 컴퓨터 앞에 앉은 사람만 할 수 있는
 *   일이라, 서버를 거치지 않고 DB 를 직접 엽니다.
 *
 * 서버를 끄지 않아도 됩니다. 다만 그 사람의 기기는 전부 로그아웃됩니다 —
 * 일부러 그렇게 합니다. 아래 주석에 이유를 적어 뒀습니다.
 * ========================================================================== */
'use strict';
const path = require('node:path');
const crypto = require('node:crypto');
const readline = require('node:readline');
const CONFIG = require('./config.js');
const { open, makeApi } = require(path.join(__dirname, '..', 'server', 'db.js'));

const argv = process.argv.slice(2);
const ASK = argv.includes('--ask');
const handle = argv.find(a => a.indexOf('--') !== 0);

/* 사람이 불러 주고 받아 적을 값입니다. 헷갈리는 글자를 뺍니다 —
   0/O, 1/l/I 를 섞어 두면 "안 되는데?" 가 한 번 더 옵니다. */
const ALPHA = 'abcdefghjkmnpqrstuvwxyz';
const DIGIT = '23456789';
function pick(set, n) {
  let out = '';
  const b = crypto.randomBytes(n * 2);
  for (let i = 0; i < n; i++) out += set[b[i] % set.length];
  return out;
}
function makePassword() {
  // 8자 이상 + 숫자만이면 안 됨 (server/db.js 의 passwordProblem)
  return pick(ALPHA, 4) + '-' + pick(DIGIT, 4) + '-' + pick(ALPHA, 4);
}

function askHidden(q) {
  return new Promise(res => {
    const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
    const out = rl.output;
    let muted = false;
    const orig = out.write.bind(out);
    out.write = function (c) { if (muted) { orig('*'); return true; } return orig(c); };
    orig(q + ' ');
    muted = true;
    rl.question('', a => { muted = false; out.write = orig; orig('\n'); rl.close(); res((a || '').trim()); });
  });
}

async function main() {
  const { cfg } = CONFIG.load();
  const file = cfg.db || path.join(__dirname, '..', 'server', 'mybody.db');

  let api;
  try { api = makeApi(open(file)); }
  catch (e) {
    console.log('데이터베이스를 못 열었습니다: ' + file);
    console.log('  ' + (e && e.message || e));
    return 1;
  }

  if (!handle) {
    const users = api.adminListUsers();
    console.log('');
    console.log('계정 ' + users.length + '개  (' + file + ')');
    console.log('');
    for (const u of users) {
      console.log('  ' + (u.handle || '').padEnd(20) +
                  (u.displayName || '').padEnd(14) +
                  String(u.createdAt || '').slice(0, 10));
    }
    console.log('');
    console.log('비밀번호를 풀어 주려면:  node tools/reset-password.js <아이디>');
    console.log('');
    return 0;
  }

  let next;
  if (ASK) {
    next = await askHidden('새 비밀번호 (8자 이상):');
    if (!next) { console.log('아무것도 안 넣어서 그만둡니다.'); return 1; }
  } else {
    next = makePassword();
  }

  const r = api.adminResetPassword(handle, next);
  if (!r.ok) { console.log('✗ ' + r.reason); return 1; }

  console.log('');
  console.log('✓ ' + r.handle + (r.displayName ? ' (' + r.displayName + ')' : '') + ' 의 비밀번호를 바꿨습니다.');
  console.log('');
  console.log('  아이디        ' + r.handle);
  if (!ASK) console.log('  새 비밀번호   ' + next);
  console.log('  새 복구 코드  ' + r.recoveryCode);
  console.log('');
  console.log('  이 둘을 본인에게 전해 주세요. 복구 코드는 **지금만** 보입니다 —');
  console.log('  서버에는 해시만 남아서, 이 화면을 닫으면 저도 못 되살립니다.');
  console.log('  다음에 또 잊지 않게 "적어 두라" 고 한마디 해 주세요.');
  console.log('');
  console.log('  그 사람이 쓰던 기기는 전부 로그아웃됐습니다. 새 비밀번호로');
  console.log('  다시 들어가면 됩니다 — 기록과 친구는 그대로 있습니다.');
  console.log('');
  return 0;
}

main().then(c => process.exit(c || 0))
      .catch(e => { console.error('오류: ' + (e && e.message || e)); process.exit(1); });
