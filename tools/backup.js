/* =============================================================================
 * tools/backup.js — 서버가 켜져 있는 채로 안전하게 백업
 *
 *   node tools/backup.js                   백업 하나 뜨고 오래된 것 지우기
 *   node tools/backup.js --list            지금 있는 백업 보기
 *   node tools/backup.js --restore <파일>  되돌리기
 *   node tools/backup.js --keep=60         며칠치 둘지 (기본 30)
 *   node tools/backup.js --out=<폴더>      어디에 둘지 (기본 ~/mybody-backups)
 *
 * 왜 cp 로는 안 되나 — 실제로 확인한 것
 *   이 데이터베이스는 WAL 방식입니다. 서버가 켜져 있는 동안 새 기록은
 *   곁파일(mybody.db-wal)에 쌓이고 본파일은 거의 안 자랍니다.
 *   계정 하나를 만든 직후 상태가 이랬습니다:
 *
 *     mybody.db       4,096 바이트
 *     mybody.db-wal 152,472 바이트   ← 계정이 여기 있습니다
 *
 *   이때 mybody.db 만 복사하면 users 테이블조차 없는 파일이 나옵니다.
 *   백업한 줄 알았는데 아무것도 없는 상태 — 제일 나쁜 종류입니다.
 *
 *   그래서 SQLite 에게 직접 "온전한 사본을 하나 만들어라" 고 시킵니다
 *   (VACUUM INTO). 서버가 켜져 있어도 됩니다.
 *
 * 왜 sqlite3 명령을 안 쓰나
 *   대부분의 컴퓨터에 안 깔려 있습니다. 문서에 sqlite3 를 쓰는 크론을
 *   적어 두면 조용히 한 번도 안 돕니다 — 그러다 정작 필요할 때 백업이
 *   하나도 없습니다. 노드에 들어 있는 것만 씁니다.
 * ========================================================================== */
'use strict';
process.removeAllListeners('warning');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { DatabaseSync } = require('node:sqlite');
const CONFIG = require('./config.js');

const ROOT = path.join(__dirname, '..');
const args = {};
/* 문서마다 `--restore <파일>` 로 띄어 적혀 있는데 `=` 꼴만 읽었습니다. 띄어 쓰면
   "true" 라는 파일을 찾다가 "그런 파일이 없습니다" 로 멈췄습니다 — 서버를 옮기며
   되돌리는 바로 그 단계에서. 값을 받는 것은 다음 칸도 봅니다. */
const VALUED = new Set(['restore', 'out', 'keep']);
const argv = process.argv.slice(2);
argv.forEach((a, i) => {
  const m = /^--([a-zA-Z-]+)(?:=([\s\S]*))?$/.exec(a);
  if (!m) return;
  const next = argv[i + 1];
  if (m[2] == null && VALUED.has(m[1]) && next != null && !next.startsWith('--')) args[m[1]] = next;
  else args[m[1]] = m[2] == null ? true : m[2];
});

const { cfg } = CONFIG.load();
const DB = cfg.db ? path.resolve(cfg.db) : path.join(ROOT, 'server', 'mybody.db');
const OUT = args.out ? path.resolve(String(args.out))
                     : path.join(os.homedir(), 'mybody-backups');
const KEEP = Number(args.keep || 30);

function counts(file) {
  const d = new DatabaseSync(file, { readOnly: true });
  const n = t => { try { return d.prepare('SELECT COUNT(*) c FROM ' + t).get().c; } catch (e) { return '?'; } };
  const o = { 계정: n('users'), 친구: n('friendships'), '주간 요약': n('snapshots') };
  d.close();
  return o;
}

function human(b) {
  return b > 1e6 ? (b / 1e6).toFixed(1) + 'MB' : Math.max(1, Math.round(b / 1024)) + 'KB';
}

/* --- --list -------------------------------------------------------------- */
if (args.list) {
  if (!fs.existsSync(OUT)) { console.log('백업이 아직 없습니다: ' + OUT); process.exit(0); }
  const files = fs.readdirSync(OUT).filter(f => /^mybody-.*\.db$/.test(f)).sort();
  if (!files.length) { console.log('백업이 아직 없습니다: ' + OUT); process.exit(0); }
  console.log('');
  console.log(OUT);
  files.forEach(f => {
    const p = path.join(OUT, f);
    let c = '';
    try { const o = counts(p); c = '계정 ' + o.계정 + '명 · 친구 ' + o.친구 + '건'; }
    catch (e) { c = '읽지 못했습니다 — ' + String(e.message).slice(0, 40); }
    console.log('  ' + f + '   ' + human(fs.statSync(p).size).padStart(7) + '   ' + c);
  });
  console.log('');
  process.exit(0);
}

/* --- --restore ------------------------------------------------------------ */
if (args.restore) {
  const src = path.resolve(String(args.restore));
  if (!fs.existsSync(src)) { console.error('그런 파일이 없습니다: ' + src); process.exit(1); }

  /* 서버가 켜져 있으면 되돌리면 안 됩니다. 켜진 채로 파일을 바꾸면
     서버는 옛 데이터를 들고 있다가 덮어씁니다 — 되돌린 것이 도로
     사라집니다. 확인하고 막습니다. */
  const port = cfg.port;
  fetch('http://localhost:' + port + '/health').then(r => r.ok).catch(() => false)
    .then(alive => {
      if (alive) {
        console.error('');
        console.error('서버가 아직 켜져 있습니다 (포트 ' + port + ').');
        console.error('먼저 서버를 끄세요 — 켠 채로 되돌리면 도로 덮어써집니다.');
        console.error('');
        process.exit(1);
      }
      let before = null;
      try { before = counts(src); } catch (e) {
        console.error('이 파일은 데이터베이스가 아니거나 깨져 있습니다: ' + e.message);
        process.exit(1);
      }
      /* 지금 것을 먼저 옆에 치워 둡니다 — 되돌리기를 되돌릴 수 있게.
         곁파일(-wal · -shm)도 같이 치워야 합니다. 안 그러면 새 본파일에
         옛 곁파일이 붙어서 무슨 일이 일어날지 모릅니다. */
      const stamp = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
      ['', '-wal', '-shm'].forEach(sfx => {
        if (fs.existsSync(DB + sfx)) fs.renameSync(DB + sfx, DB + sfx + '.before-' + stamp);
      });
      fs.mkdirSync(path.dirname(DB), { recursive: true });
      fs.copyFileSync(src, DB);
      console.log('');
      console.log('되돌렸습니다.');
      console.log('  ' + src);
      console.log('  → ' + DB);
      console.log('  계정 ' + before.계정 + '명 · 친구 ' + before.친구 + '건 · 주간 요약 ' + before['주간 요약'] + '건');
      console.log('');
      console.log('  옛 파일은 ' + path.basename(DB) + '.before-' + stamp + ' 로 옆에 있습니다.');
      console.log('  괜찮은 걸 확인하고 지우세요.');
      console.log('');
    });
  return;
}

/* --- 백업 ---------------------------------------------------------------- */
if (!fs.existsSync(DB)) {
  console.error('데이터베이스가 아직 없습니다: ' + DB);
  console.error('서버를 한 번도 안 띄웠거나, 설정의 db 경로가 다릅니다.');
  process.exit(1);
}

fs.mkdirSync(OUT, { recursive: true, mode: 0o700 });
const day = new Date().toISOString().slice(0, 10);
const dest = path.join(OUT, 'mybody-' + day + '.db');
fs.rmSync(dest, { force: true });

/* 읽기 전용으로 열면 WAL 을 못 봅니다 — 그 상태로 백업하면 최근 기록이
   통째로 빠집니다. 쓰기로 열어야 SQLite 가 WAL 을 합쳐서 보여 줍니다.
   VACUUM INTO 는 읽기 잠금만 잡으므로 서버가 켜져 있어도 됩니다. */
const db = new DatabaseSync(DB);
db.exec("VACUUM INTO '" + dest.replace(/'/g, "''") + "'");
db.close();

const after = counts(dest);
console.log('');
console.log('백업했습니다: ' + dest + '  (' + human(fs.statSync(dest).size) + ')');
console.log('  계정 ' + after.계정 + '명 · 친구 ' + after.친구 + '건 · 주간 요약 ' + after['주간 요약'] + '건');

/* 오래된 것 지우기.
   누가 계정을 지워도 옛 백업에는 그 사람의 몸 숫자가 그대로 남습니다.
   지우기로 한 것이 어딘가에 남아 있으면 지운 게 아닙니다. */
const cutoff = Date.now() - KEEP * 86400000;
let dropped = 0;
fs.readdirSync(OUT).filter(f => /^mybody-.*\.db$/.test(f)).forEach(f => {
  const p = path.join(OUT, f);
  if (fs.statSync(p).mtimeMs < cutoff) { fs.rmSync(p, { force: true }); dropped++; }
});
if (dropped) console.log('  ' + KEEP + '일 지난 백업 ' + dropped + '개를 지웠습니다.');
console.log('');
