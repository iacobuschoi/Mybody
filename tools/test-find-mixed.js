/* =============================================================================
 * tools/test-find-mixed.js — find-mixed-accounts.js 가 섞인 쌍만 찾고, DB 에 아무것도 안 쓰는가
 *
 *   node tools/test-find-mixed.js
 *
 * 보는 것 (피드백 52 — 계정 A 의 기록이 새 계정 B 의 사본으로 올라간 것을 찾는 도구)
 *   · A 와 B 가 'scan-<지금 ms>' · 식단 id 를 2개 이상 같이 가지면 나온다 · 받은 쪽은 **후보**로만
 *     (늦게 가입한 쪽) — 로그인 없이 쓰다 가입한 주인이면 반대라, 확인하라고 말한다(2차 검토)
 *   · 씨앗 id(scan-20260630/0831/0919) · 'scan-h*' · 웹 날짜 id 만 겹치면 안 나온다
 *   · 믿을 수 있는 id 가 1개만 겹치면 안 나온다(기본 --min 2)
 *   · 사람이 읽는 꼴 · --json 둘 다 · DB 파일이 한 바이트도 안 바뀐다
 * ========================================================================== */
'use strict';
require('./testenv.js');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const crypto = require('node:crypto');
const { spawnSync } = require('node:child_process');

const ROOT = path.join(__dirname, '..');
const DBM = require(path.join(ROOT, 'server', 'db.js'));
const TOOL = path.join(__dirname, 'find-mixed-accounts.js');
const { reliableKind } = require(TOOL);

let pass = 0, fail = 0;
const ok = (n, c, d) => {
  if (c) { pass++; console.log('  ✓', n); }
  else { fail++; console.log('  ✗', n, d === undefined ? '' : JSON.stringify(d).slice(0, 500)); }
};

const TMP = fs.mkdtempSync(path.join(os.tmpdir(), 'mybody-findmixed-'));
const FILE = path.join(TMP, 'mixed.db');

console.log('\n섞인 계정 찾기(읽기만)\n');

console.log('[1] 믿을 수 있는 id');
ok('scan-<13자리 ms> · est-<ms> · f<ms>_n 은 믿는다',
   reliableKind('scan-1758240000000') === 'scan' && reliableKind('est-1758240000000') === 'est' &&
   reliableKind('f1758240000000_3') === 'food');
ok('씨앗 · scan-h* · 날짜 id · 모르는 모양은 안 믿는다',
   ['scan-20260919', 'scan-20260630', 'scan-h1758240000000', 'scan-202609191000', 'scan-202609191000-2',
    's1', null, 42].every(x => reliableKind(x) === null));

/* --- DB 를 만듭니다 ------------------------------------------------------------ */
{
  const api = DBM.makeApi(DBM.open(FILE));
  const mk = h => api.signUp({ handle: h, password: 'test-password-1', displayName: h,
                               healthConsent: DBM.HEALTH_CONSENT_VERSION }).user.id;
  const put = (uid, scans, foodLogs, at) => api.push(uid, [{ kind: 'state', id: 'main', updatedAt: at,
    payload: { version: 1, scans: scans.map(id => ({ id, weightKg: 80 })), foodLogs: foodLogs.map(id => ({ id })) } }]);
  const alpha = mk('alpha'), bravo = mk('bravo'), charlie = mk('charlie'), delta = mk('delta'), echo = mk('echo');
  const spouse = mk('spouse'), realowner = mk('realowner');
  /* 가입 시각을 흉내 — alpha 는 오래전, bravo(받은 쪽)는 기록이 생긴 뒤. spouse(받은 쪽)는 오래전,
     realowner(진짜 주인)는 로그인 없이 쓰다(2026-07) 나중에 가입(2026-08). */
  const raw = new (require('node:sqlite').DatabaseSync)(FILE);
  raw.prepare('UPDATE users SET created_at=? WHERE id=?').run('2025-01-01T00:00:00.000Z', alpha);
  raw.prepare('UPDATE users SET created_at=? WHERE id=?').run('2026-09-28T09:00:00.000Z', bravo);
  raw.prepare('UPDATE users SET created_at=? WHERE id=?').run('2025-01-01T00:00:00.000Z', spouse);
  raw.prepare('UPDATE users SET created_at=? WHERE id=?').run('2026-08-01T00:00:00.000Z', realowner);
  raw.close();
  const R_SCANS = ['scan-1782864000000', 'scan-1783468800000'];   // 2026-07-01 · 07-08 (로그인 없이)
  const R_FOOD = ['f1782864000000_0'];
  put(realowner, R_SCANS, R_FOOD, '2026-08-01T00:00:00.000Z');
  put(spouse, [...R_SCANS, 'scan-1790000000000'], R_FOOD, '2026-09-20T00:00:00.000Z');
  const A_SCANS = ['scan-1758240000000', 'scan-1758844800000', 'scan-h1758240000000', 'scan-20260919'];
  const A_FOOD = ['f1758240000000_0', 'f1758240000001_1'];
  put(alpha, A_SCANS, A_FOOD, '2026-09-27T00:00:00.000Z');
  /* bravo — 피드백 52 의 모양: alpha 의 기록이 통째로 올라감 + 자기 것 하나. */
  put(bravo, [...A_SCANS, 'scan-1759050000000'], A_FOOD, '2026-09-28T09:05:00.000Z');
  /* charlie — 씨앗 · scan-h · 날짜 id 만 alpha 와 같음(웹 씨앗 버튼 · 같은 날 잰 사람). */
  put(charlie, ['scan-20260919', 'scan-20260831', 'scan-h1758240000000', 'scan-202609191000', 'scan-1759999999999'], [],
      '2026-09-20T00:00:00.000Z');
  /* delta — 믿을 수 있는 id 가 딱 하나만 겹침. */
  put(delta, ['scan-1758240000000', 'scan-1760000000000'], [], '2026-09-20T00:00:00.000Z');
  /* echo — 기록 사본 없음. */
  void echo;
  api.publishSnapshot(bravo, '2026-09-28', { keptDays: 1 });
}

const hash = f => crypto.createHash('sha256').update(fs.readFileSync(f)).digest('hex');
const filesOf = () => fs.readdirSync(TMP).sort().join(',');
/* 만드는 쪽의 -wal 을 본 파일로 모아 둡니다 — 도구가 뭔가를 쓰는지 가르려고. */
{
  const d = new (require('node:sqlite').DatabaseSync)(FILE);
  d.exec('PRAGMA wal_checkpoint(TRUNCATE)');
  d.close();
}
const before = { h: hash(FILE), files: filesOf(), size: fs.statSync(FILE).size };

console.log('\n[2] 도구 — --json');
const j = spawnSync(process.execPath, [TOOL, '--db', FILE, '--json'], { encoding: 'utf8', env: Object.assign({}, process.env, { NODE_NO_WARNINGS: '1' }) });
let out = null;
try { out = JSON.parse(j.stdout); } catch (e) {}
ok('끝까지 돈다 (종료 코드 0)', j.status === 0 && out && out.ok === true, j.stderr || j.stdout);
const pairs = (out && out.pairs) || [];
const names = pairs.map(p => [p.a.handle, p.b.handle].sort().join('+')).sort();
ok('섞인 쌍 둘 — alpha ⟷ bravo · realowner ⟷ spouse',
   JSON.stringify(names) === JSON.stringify(['alpha+bravo', 'realowner+spouse']), names);
const p = pairs.find(x => [x.a.handle, x.b.handle].includes('bravo')) || { shared: {} };
const q = pairs.find(x => [x.a.handle, x.b.handle].includes('spouse')) || {};
ok('겹친 기록은 믿을 수 있는 id 만 세었다 (측정 2 · 식단 2 — scan-h · 씨앗은 안 셈)',
   p.shared.scan === 2 && p.shared.food === 2 && p.shared.est === 0 && p.shared.total === 4, p.shared);
ok('받은 쪽 후보 — 기록이 생긴 뒤에 가입한 bravo', p.candidate === 'bravo', p.candidate);
ok('후보일 뿐 — 로그인 없이 쓰다 가입한 진짜 주인(realowner)이 후보로 찍힐 수 있다(그래서 단정하지 않음)',
   q.candidate === 'realowner' && !('receiver' in q), q);
ok('가장 이른 것 = 2025-09-19 의 측정', p.earliestAt === new Date(1758240000000).toISOString(), p.earliestAt);
ok('가입 시각 · 사본 마지막 시각 · 요약 첫 주가 실린다',
   [p.a, p.b].every(x => x && x.createdAt && x.syncedAt) &&
   [p.a, p.b].some(x => x.handle === 'bravo' && x.firstWeek === '2026-09-28'), [p.a, p.b]);
ok('씨앗 · scan-h · 날짜 id 만 같은 charlie 는 안 나온다', !names.some(n => n.includes('charlie')));
ok('하나만 겹치는 delta 는 안 나온다(기본 2개부터)', !names.some(n => n.includes('delta')));

const j1 = spawnSync(process.execPath, [TOOL, '--db', FILE, '--json', '--min', '1'], { encoding: 'utf8' });
const names1 = (JSON.parse(j1.stdout).pairs || []).map(x => [x.a.handle, x.b.handle].sort().join('+'));
ok('--min 1 이면 delta 도 나온다 · charlie 는 여전히 안 나온다',
   names1.includes('alpha+delta') && names1.includes('bravo+delta') && !names1.some(n => n.includes('charlie')), names1);

console.log('\n[3] 도구 — 사람이 읽는 꼴');
const h = spawnSync(process.execPath, [TOOL, '--db', FILE], { encoding: 'utf8' });
ok('아이디 · 겹친 수 · 받은 쪽 후보가 나온다', h.status === 0 && /alpha ⟷ bravo|bravo ⟷ alpha/.test(h.stdout) &&
   /겹친 기록 4개/.test(h.stdout) && /받은 쪽 후보: bravo/.test(h.stdout), h.stdout);
ok('단정하지 않는다 — 쌍마다 "반대일 수 있어요 · 두 계정 주인에게 확인" 을 말한다',
   (h.stdout.match(/로그인 없이 쓰다 가입한 계정이면 반대일 수 있어요 — 두 계정 주인에게 확인하세요/g) || []).length === 2 &&
   !/가능성이 큽니다/.test(h.stdout), h.stdout);
ok('정리 방법(확인한 뒤 · 앱의 계정 지우기)을 말하고, 스스로는 바꾸지 않는다고 말한다',
   /확인한 뒤/.test(h.stdout) && /계정 지우기/.test(h.stdout) && /아무것도 바꾸지 않습니다/.test(h.stdout));
const none = spawnSync(process.execPath, [TOOL, '--db', path.join(TMP, 'nope.db')], { encoding: 'utf8' });
ok('없는 DB 는 1 로 끝나고 만들지 않는다', none.status === 1 && !fs.existsSync(path.join(TMP, 'nope.db')));

console.log('\n[4] 읽기만');
ok('DB 파일이 한 바이트도 안 바뀌었다 · 새 파일(-wal · -journal)도 안 생겼다',
   hash(FILE) === before.h && fs.statSync(FILE).size === before.size && filesOf() === before.files,
   { before: before.files, after: filesOf() });

try { fs.rmSync(TMP, { recursive: true, force: true }); } catch (e) {}
console.log(`\n통과 ${pass} / 실패 ${fail}`);
process.exit(fail ? 1 : 0);
