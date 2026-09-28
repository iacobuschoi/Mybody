/* =============================================================================
 * tools/find-mixed-accounts.js — 두 계정이 **같은 기록**을 가진 쌍을 찾습니다(읽기만)
 *
 *   node tools/find-mixed-accounts.js                 설정의 DB(없으면 server/mybody.db)
 *   node tools/find-mixed-accounts.js --db <파일>      그 DB
 *   node tools/find-mixed-accounts.js --json          기계가 읽는 꼴
 *   node tools/find-mixed-accounts.js --min 3         겹치는 기록이 3개 이상인 쌍만(기본 2)
 *
 * 왜 있나 (피드백 52)
 *   0.2.19 까지의 앱은 로그아웃해도 기록을 폰에 남겼고, 다른 계정으로 가입 · 로그인하면 그 기록을
 *   새 계정의 서버 사본(records state/main)으로 합쳐 올렸습니다. 주인 폰에서 실제로 났습니다.
 *   고친 앱(0.2.20)은 칸을 계정마다 따로 두지만, 이미 섞여 올라간 사본은 서버에 남아 있습니다.
 *   이 도구는 그런 쌍을 찾아 보여 주기만 합니다 — 정리는 앱의 「계정 지우기」 로 합니다
 *   (사본을 받은 쪽 계정으로 로그인해서).
 *
 * 무엇을 "같은 기록" 으로 보나 — 두 사람이 우연히 같을 수 없는 id 만
 *   · 측정 'scan-<13자리 ms>'(앱 upload.dart) · 추정 'est-<ms>'(estimate.dart)
 *   · 식단 'f<ms>_<n>'(store.dart addFoodLog)
 *   뺍니다: 'scan-h<ms>'(결과지 그래프에서 읽은 지난 측정 — 같은 날 잰 두 사람이 겹침),
 *   씨앗 'scan-20260630/0831/0919'(웹 씨앗 버튼을 누른 계정은 모두 같음), 웹 앱의 날짜 id
 *   ('scan-YYYYMMDD[HHMM][-n]' — 같은 날 잰 사람끼리 겹침).
 *
 * 무엇을 보여 주나
 *   쌍마다 두 계정의 아이디 · 가입 시각 · 사본을 마지막으로 올린 때 · 주간 요약의 첫 주, 겹친
 *   기록 수(측정 · 추정 · 식단)와 그중 가장 이른 것의 시각. DB 는 사본의 **마지막** 시각만 들고 있어
 *   첫 push 시각은 알 수 없습니다 — 대신 겹친 기록이 어느 계정의 가입보다 **먼저** 만들어졌는지를
 *   봅니다. 그 계정(늦게 가입한 쪽)을 사본을 받은 쪽의 **후보**로만 보입니다(candidate). 단정하지
 *   않는 까닭: 「로그인 없이 쓰기」 로 만든 기록은 가입할 때 그 계정에 합쳐지므로(0.2.19 는 저절로,
 *   0.2.20 은 [합치기]), 진짜 주인이 손님으로 먼저 쓰다 가입했고 사본을 받은 쪽이 원래 있던 계정이면
 *   반대입니다(2차 검토). 가입 시각만으로는 두 경우를 가를 수 없어, 정리하기 전에 두 계정 주인에게
 *   확인해야 합니다 — 출력이 그렇게 말합니다.
 *   reset-password.js 머리 주석처럼 비밀번호를 잊어 새 계정을 만든 사람의 두 계정도 여기 나옵니다.
 *
 * DB 는 읽기 전용으로 엽니다(서버를 끄지 않아도 됩니다). 아무것도 쓰지 않습니다.
 * ========================================================================== */
'use strict';
const path = require('node:path');
const fs = require('node:fs');
const { DatabaseSync } = require('node:sqlite');

const SEED_IDS = new Set(['scan-20260630', 'scan-20260831', 'scan-20260919']);

/** 믿을 수 있는 id 인가 — 그렇다면 종류('scan' · 'est' · 'food'), 아니면 null. */
function reliableKind(id) {
  if (typeof id !== 'string' || SEED_IDS.has(id)) return null;
  if (/^scan-\d{13}$/.test(id)) return 'scan';
  if (/^est-\d{13}$/.test(id)) return 'est';
  if (/^f\d{13}_\d+$/.test(id)) return 'food';
  return null;   // scan-h* · 날짜 id · 손으로 만든 id
}

/** id 에 박힌 시각(ms). */
function msOf(id) {
  const m = /(\d{13})/.exec(id);
  return m ? Number(m[1]) : NaN;
}

/** 한 계정의 사본(payload)에서 믿을 수 있는 id 를 꺼냅니다. */
function reliableIds(payload) {
  const out = new Map();
  if (!payload || typeof payload !== 'object') return out;
  for (const list of ['scans', 'foodLogs']) {
    for (const x of Array.isArray(payload[list]) ? payload[list] : []) {
      const k = x && reliableKind(x.id);
      if (k) out.set(x.id, k);
    }
  }
  return out;
}

/**
 * 겹치는 쌍을 찾습니다. [db] 는 node:sqlite 의 DatabaseSync(읽기 전용이면 좋음).
 * 돌려주는 것: [{a:{handle, createdAt, syncedAt, firstWeek}, b:{…}, shared:{scan, est, food, total},
 *               earliestAt, candidate}] — candidate 는 사본을 받은 쪽의 **후보**(단정 아님 — 머리 주석):
 *               겹친 기록 중 가장 이른 것보다 늦게 가입한 쪽의 아이디(둘 다 그 뒤면 늦게 가입한 쪽,
 *               판단이 안 서면 null).
 */
function findMixed(db, { min = 2 } = {}) {
  const users = new Map();
  for (const u of db.prepare('SELECT id, handle, created_at FROM users').all()) {
    users.set(u.id, { handle: u.handle, createdAt: u.created_at });
  }
  const firstWeek = new Map();
  try {
    for (const r of db.prepare('SELECT owner_id, MIN(week_start) w FROM snapshots GROUP BY owner_id').all()) {
      firstWeek.set(r.owner_id, r.w);
    }
  } catch (e) { /* 옛 DB — 요약 칸이 없으면 비워 둡니다 */ }
  const accounts = [];
  for (const r of db.prepare("SELECT user_id, updated_at, payload FROM records WHERE kind='state' AND id='main' AND deleted=0").all()) {
    const u = users.get(r.user_id);
    if (!u) continue;
    let payload = null;
    try { payload = JSON.parse(r.payload); } catch (e) { continue; }
    const ids = reliableIds(payload);
    if (ids.size) accounts.push({ id: r.user_id, handle: u.handle, createdAt: u.createdAt, syncedAt: r.updated_at,
                                  firstWeek: firstWeek.get(r.user_id) || null, ids });
  }
  const pairs = [];
  for (let i = 0; i < accounts.length; i++) {
    for (let j = i + 1; j < accounts.length; j++) {
      const A = accounts[i], B = accounts[j];
      const [small, big] = A.ids.size <= B.ids.size ? [A.ids, B.ids] : [B.ids, A.ids];
      const shared = { scan: 0, est: 0, food: 0, total: 0 };
      let earliest = Infinity;
      for (const [id, k] of small) {
        if (!big.has(id)) continue;
        shared[k]++;
        shared.total++;
        const t = msOf(id);
        if (t < earliest) earliest = t;
      }
      if (shared.total < min) continue;
      const pick = x => ({ handle: x.handle, createdAt: x.createdAt, syncedAt: x.syncedAt, firstWeek: x.firstWeek });
      /* 사본을 받은 쪽의 후보 — 겹친 기록 중 가장 이른 것보다 늦게 가입한 계정. 둘 다 늦으면 더 늦은 쪽.
         로그인 없이 쓰다 가입한 주인이면 반대일 수 있어 단정하지 않습니다(머리 주석). */
      const after = x => Number.isFinite(earliest) && Date.parse(x.createdAt) > earliest;
      let candidate = null;
      if (after(A) !== after(B)) candidate = after(A) ? A.handle : B.handle;
      else if (after(A) && after(B)) candidate = Date.parse(A.createdAt) > Date.parse(B.createdAt) ? A.handle : B.handle;
      pairs.push({ a: pick(A), b: pick(B), shared,
                   earliestAt: Number.isFinite(earliest) ? new Date(earliest).toISOString() : null, candidate });
    }
  }
  pairs.sort((x, y) => y.shared.total - x.shared.total);
  return pairs;
}

function dbFile(argv) {
  const i = argv.indexOf('--db');
  if (i >= 0 && argv[i + 1]) return path.resolve(argv[i + 1]);
  try {
    const { cfg } = require('./config.js').load();
    if (cfg && cfg.db) return cfg.db;
  } catch (e) {}
  return path.join(__dirname, '..', 'server', 'mybody.db');
}

function day(iso) { return iso ? String(iso).slice(0, 16).replace('T', ' ') : '—'; }

function main(argv) {
  const file = dbFile(argv);
  const json = argv.includes('--json');
  const mi = argv.indexOf('--min');
  const min = mi >= 0 ? Math.max(1, Number(argv[mi + 1]) || 2) : 2;
  if (!fs.existsSync(file)) {
    console.error('데이터베이스가 없습니다: ' + file);
    return 1;
  }
  const db = new DatabaseSync(file, { readOnly: true });
  let pairs;
  try { pairs = findMixed(db, { min }); } finally { db.close(); }
  if (json) {
    console.log(JSON.stringify({ ok: true, min, pairs }, null, 2));
    return 0;
  }
  console.log('\n같은 기록을 가진 계정 쌍 — ' + file);
  console.log('  (믿을 수 있는 id 가 ' + min + '개 이상 겹침: scan-<ms> · est-<ms> · 식단 f<ms>_n.' +
              ' 씨앗 · scan-h* · 날짜 id 는 뺌)\n');
  if (!pairs.length) {
    console.log('  없습니다.\n');
    return 0;
  }
  for (const p of pairs) {
    console.log('  ' + p.a.handle + ' ⟷ ' + p.b.handle);
    console.log('    겹친 기록 ' + p.shared.total + '개 (측정 ' + p.shared.scan + ' · 추정 ' + p.shared.est +
                ' · 식단 ' + p.shared.food + ') · 가장 이른 것 ' + day(p.earliestAt));
    for (const x of [p.a, p.b]) {
      console.log('    ' + x.handle.padEnd(16) + ' 가입 ' + day(x.createdAt) + ' · 사본 마지막 ' + day(x.syncedAt) +
                  ' · 요약 첫 주 ' + (x.firstWeek || '—'));
    }
    if (p.candidate) {
      console.log('    → 받은 쪽 후보: ' + p.candidate + ' (겹친 기록보다 늦게 가입)');
    }
    console.log('      로그인 없이 쓰다 가입한 계정이면 반대일 수 있어요 — 두 계정 주인에게 확인하세요.');
    console.log('');
  }
  console.log('  정리: 두 계정 주인에게 어느 쪽 기록인지 확인한 뒤, 사본을 받은 쪽 계정으로 앱에 로그인해\n' +
              '  설정 → 지우기 → 「계정 지우기」(0.2.20 부터 이 기기의 기록은 남고, 다른 계정으로 들어갈 때\n' +
              '  합칠지 먼저 묻습니다). 이 도구는 아무것도 바꾸지 않습니다.\n');
  return 0;
}

if (require.main === module) process.exit(main(process.argv.slice(2)));

module.exports = { findMixed, reliableKind, reliableIds };
