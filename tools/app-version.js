/* =============================================================================
 * tools/app-version.js — 앱에게 알릴 "최신판 · 최소판" 을 정합니다
 *
 *   node tools/app-version.js                    지금 값 보기
 *   node tools/app-version.js --apk=0.2.8        직접 설치한 APK 의 최신판
 *   node tools/app-version.js --play=0.2.8       플레이 스토어의 최신판
 *   node tools/app-version.js --appstore=0.2.8   앱스토어의 최신판
 *   node tools/app-version.js --testflight=0.2.10 TestFlight(아이폰 시험판)의 최신판
 *   node tools/app-version.js --min=0.2.9        이보다 낮은 앱은 "서버와 안 맞음"
 *   node tools/app-version.js --apk=none         지웁니다 (빈 값 "" 도 됩니다)
 *
 * 앱은 켤 때(6시간에 한 번까지) GET /api/version 으로 이 값을 묻고, 자기
 * 판이 낮으면 홈 화면 맨 위에 안내를 띄웁니다. 서버는 부를 때마다 설정을
 * 새로 읽으므로 **다시 띄울 필요가 없습니다.** 대신 서버가 도는 컴퓨터에서
 * 돌려야 합니다 — 값은 그 컴퓨터의 ~/.mybody/config.json 에 적힙니다.
 * 적고 나면 이 컴퓨터의 서버에 물어서 정말 그 값이 나가는지 봅니다. 서버가
 * 다른 컴퓨터에 있거나, /api/version 이 생기기 전의 옛 코드로 돌면 여기
 * 적은 값은 안 나갑니다 — 그럴 때 조용히 "저장했습니다" 로 끝내지 않습니다.
 *
 * 최신판은 가게에 실제로 올라간 **뒤에만** 올립니다
 *   앱의 [업데이트] 단추는 그 가게의 앱 페이지를 엽니다. 가게에 아직 그
 *   판이 없으면 거기에는 "열기" 만 있고, 눌러도 옛 판 그대로입니다. 앱은
 *   계속 "새 버전이 나왔습니다" 라고 합니다. 사람은 고장이라고 생각하고,
 *   다음부터는 안내를 안 믿습니다.
 *   · 심사 중인 앱스토어 판을 먼저 적으면, 심사가 며칠 걸리는 동안 아이폰
 *     쓰는 사람 모두가 그 상태가 됩니다. 심사에서 떨어지면 계속 그렇습니다.
 *   · 플레이도 검토 중이거나 단계적 출시 중이면 아직 못 받는 사람이 있습니다.
 *   · 그래서 가게마다 따로 적습니다. 같은 0.2.8 이라도 APK 는 릴리스 직후,
 *     플레이는 출시가 끝난 뒤, 앱스토어는 심사를 지나 배포가 시작된 뒤입니다.
 *
 * 최소판(--min)은 더 조심합니다
 *   그보다 낮은 앱은 닫을 수 없는 안내를 봅니다. 서버가 옛 앱을 정말로
 *   못 받게 됐을 때만 올리고, 그 판이 **모든 가게에** 올라간 뒤에 올립니다.
 *   어느 가게의 최신판보다 높은 최소판은 거절합니다 — 그 가게로 깐 사람은
 *   받을 판이 없는데 계속 업데이트하라는 말을 듣게 됩니다.
 *   안내는 0.2.8 부터 앱에 들어 있습니다. 그보다 낮은 앱은 최소판을 몰라서
 *   아무것도 못 봅니다 — 0.2.8 이하의 최소판은 누구에게도 안 뜹니다.
 *
 * 단추가 여는 주소를 바꾸려면 설정 파일에 appUrlAppStore · appUrlPlay ·
 * appUrlApk 를 직접 적습니다(https 만). 비워 두면 기본 주소입니다.
 * ========================================================================== */
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const CONFIG = require('./config.js');
const APPVER = require(path.join(__dirname, '..', 'server', 'appversion.js'));

const FILE = CONFIG.FILE();
const NAME = { appstore: '앱스토어', testflight: 'TestFlight', play: '플레이', apk: 'APK' };
/* 이 판부터 앱이 /api/version 을 묻습니다. 그보다 낮은 앱은 안내가 없습니다. */
const FIRST_WITH_NOTICE = '0.2.8';
/* 깃발 이름 ↔ 설정 키. 채널 이름을 그대로 깃발로 씁니다. */
const FLAG_KEY = Object.assign({}, APPVER.LATEST_KEY, { min: APPVER.MIN_KEY });
const CLEAR = /^(none|없음)$/i;

function usage() {
  console.log('');
  console.log('  node tools/app-version.js                    지금 값 보기');
  console.log('  node tools/app-version.js --apk=0.2.8        APK 최신판');
  console.log('  node tools/app-version.js --play=0.2.8       플레이 최신판');
  console.log('  node tools/app-version.js --appstore=0.2.8   앱스토어 최신판');
  console.log('  node tools/app-version.js --testflight=0.2.10 TestFlight 최신판');
  console.log('  node tools/app-version.js --min=0.2.9        최소판');
  console.log('  node tools/app-version.js --apk=none         지우기');
  console.log('');
}

function die(lines) {
  console.error('');
  [].concat(lines).forEach(l => console.error(l));
  console.error('');
  process.exit(1);
}

/* 깃발 읽기. `--apk 0.2.8` 처럼 등호 없이 띄어 줘도 받습니다(serve.js 와 같게).
   모르는 깃발은 거절합니다 — 조용히 버리면 "적었다" 고 믿는데 안 나갑니다. */
function parseFlags(av) {
  const out = {};
  for (let i = 0; i < av.length; i++) {
    const m = /^--([a-z]+)(?:=([\s\S]*))?$/.exec(av[i]);
    if (!m) die(['모르는 인자입니다: ' + av[i]].concat(usageLines()));
    if (m[1] === 'help') { usage(); process.exit(0); }
    /* `in` 은 쓰지 않습니다 — --constructor 같은 것이 Object 의 물려받은
       이름으로 통과해 설정 파일에 엉뚱한 키를 적었습니다. */
    if (!Object.prototype.hasOwnProperty.call(FLAG_KEY, m[1])) {
      die(['모르는 깃발입니다: --' + m[1]].concat(usageLines()));
    }
    let v = m[2];
    if (v == null) {
      const next = av[i + 1];
      if (next == null || /^--/.test(next)) {
        die(['--' + m[1] + ' 에 값이 없습니다. 예: --' + m[1] + '=0.2.8 (지우려면 --' + m[1] + '=none)']);
      }
      v = next; i++;
    }
    out[m[1]] = v;
  }
  return out;
}
function usageLines() {
  return ['', '  쓰는 법: node tools/app-version.js --apk=0.2.8   (--appstore · --testflight · --play · --apk · --min)'];
}

/** 받은 값을 저장할 값으로. 지우라는 말이면 '', 판이 아니면 멈춥니다. */
function toValue(flag, raw) {
  const s = String(raw).trim();
  if (s === '' || CLEAR.test(s)) return '';
  const v = APPVER.cleanVersion(s);
  if (!v) {
    die(['판 번호가 아닙니다: --' + flag + '=' + raw,
         '  0.2.8 처럼 숫자 셋을 점으로 이어 주세요 (앞의 v 나 뒤의 +빌드번호 없이).',
         '  지우려면 --' + flag + '=none']);
  }
  return v;
}

/* 설정 파일을 **엄격하게** 읽습니다.
 *
 * tools/config.js 는 읽다가 망가진 파일을 만나면 조용히 빈 설정을
 * 돌려줍니다(서버를 띄울 때는 그게 맞습니다). 그런데 여기서 그 빈 설정
 * 위에 판 번호만 얹어 저장하면, 파일에 있던 가입 코드와 판독 키가 통째로
 * 사라집니다. 망가진 파일은 고치라고 말하고 손대지 않습니다. */
function readSaved() {
  if (!CONFIG.exists()) return null;
  let raw;
  try { raw = fs.readFileSync(FILE, 'utf8'); }
  catch (e) { die('설정 파일을 못 읽었습니다: ' + FILE + '\n  ' + e.message); }
  try {
    const j = JSON.parse(raw);
    if (j && typeof j === 'object' && !Array.isArray(j)) return j;
  } catch (e) {}
  die(['설정 파일이 JSON 이 아니라서 손대지 않았습니다: ' + FILE,
       '  이 위에 쓰면 가입 코드와 판독 키가 사라집니다. 파일을 먼저 고쳐 주세요.']);
}

/** 설정 → 서버가 내보낼 값. 서버와 똑같이 다듬습니다. */
function effective(cfg) {
  return APPVER.versionInfo(Object.assign({}, CONFIG.DEFAULTS, cfg));
}

/** 최소판이 어느 가게의 최신판보다 높은가 — 그 가게 이름들. */
function minAboveLatest(info) {
  if (!info.min) return [];
  return APPVER.CHANNELS.filter(ch =>
    info.latest[ch] && APPVER.compareVersions(info.min, info.latest[ch]) > 0);
}

function show(cfg, changed) {
  const info = effective(cfg);
  const mark = k => (changed && changed.indexOf(k) >= 0) ? '   ← 바꿈' : '';
  /* 적어 뒀는데 판 모양이 아니면 서버가 버립니다. 그 사실을 말해 줍니다 —
     안 그러면 "적었는데 왜 안 뜨지" 가 됩니다. */
  const bad = (key, shown) => {
    const raw = cfg[key];
    if (shown || raw === undefined || raw === null || raw === '') return '';
    return '   ← 판 모양이 아니라 안 내보냅니다: ' + JSON.stringify(raw);
  };
  console.log('');
  console.log('설정 파일: ' + FILE + (CONFIG.exists() ? '' : '  (아직 없습니다)'));
  console.log('');
  APPVER.CHANNELS.forEach(ch => {
    const key = APPVER.LATEST_KEY[ch];
    const v = info.latest[ch];
    console.log('  ' + NAME[ch] + ' 최신판  ' + (v || '(없음 — 새 판 안내 안 함)') +
                mark(key) + bad(key, v));
    console.log('      단추 주소  ' + info.urls[ch]);
  });
  console.log('  최소판  ' + (info.min || '(없음)') + mark(APPVER.MIN_KEY) +
              bad(APPVER.MIN_KEY, info.min));
  console.log('');
}

/* 이 컴퓨터에서 도는 서버가 **정말로** 이 값을 내보내는지 물어봅니다.
 *
 * 파일에 적은 것과 앱이 받는 것은 다를 수 있습니다.
 *  · 서버가 다른 컴퓨터(오라클 VM 등)에 있다 — 여기 적은 값을 그쪽은 못 봅니다.
 *  · 서버가 따로 떼어 둔 옛 코드다(~/mybody-server) — /api/version 이 아직 없습니다.
 *  · 서버가 다른 사용자(HOME)로 돌아서 다른 설정 파일을 읽는다.
 * 어느 쪽이든 안내는 조용히 안 나갑니다. 확인일 뿐이라 결과가 어떻든
 * 저장은 그대로 두고, 끝나는 코드도 바꾸지 않습니다. */
async function verify(want) {
  const port = Number(CONFIG.load().cfg.port) || 8080;
  const url = 'http://127.0.0.1:' + port + '/api/version';
  let r, j = null;
  try {
    r = await fetch(url, { signal: AbortSignal.timeout(2500) });
    try { j = await r.json(); } catch (e) {}
  } catch (e) {
    console.log('  ! 이 컴퓨터의 ' + port + ' 포트에서 서버가 답하지 않습니다 (' + url + ').');
    console.log('    서버가 꺼져 있으면 켜진 뒤 바로 나갑니다. 서버가 다른 컴퓨터(오라클 VM 등)에서');
    console.log('    돈다면 여기 적은 값은 안 나갑니다 — 그 컴퓨터에서 이 도구를 다시 돌리세요.');
    return;
  }
  if (r.status === 404 || r.status === 401) {
    console.log('  ! 서버는 답하는데 /api/version 이 없습니다 (' + r.status + ') — 이 길이 생기기 전의 옛 서버 코드입니다.');
    console.log('    서버를 지금 코드로 올리고 한 번 다시 띄워야 안내가 나갑니다 (docs/DEPLOY.md 9절).');
    return;
  }
  if (!r.ok || !j || j.ok !== true) {
    console.log('  ! 서버가 /api/version 에 ' + r.status + ' 로 답했습니다' +
                (j && j.reason ? ' — ' + j.reason : '') + '.');
    return;
  }
  const same = k => JSON.stringify(j[k]) === JSON.stringify(want[k]);
  if (same('latest') && same('min') && same('urls')) {
    console.log('  서버(' + port + ' 포트)가 이 값을 내보내는 것을 확인했습니다.');
    return;
  }
  const line = v => APPVER.CHANNELS.map(ch => NAME[ch] + ' ' + ((v.latest || {})[ch] || '없음')).join(' · ') +
                    ' · 최소판 ' + (v.min || '없음');
  console.log('  ! 서버(' + port + ' 포트)가 내보내는 값이 여기 적힌 것과 다릅니다.');
  console.log('    서버: ' + line(j));
  console.log('    여기: ' + line(want));
  console.log('    서버가 다른 설정 파일을 읽고 있습니다 — 다른 사용자(HOME)로 돌거나, 이 포트가');
  console.log('    다른 서버일 수 있습니다. 서버가 도는 컴퓨터 · 사용자로 이 도구를 돌리세요.');
}

async function main() {
  const args = process.argv.slice(2);
  const saved = readSaved();

  if (!args.length) {
    show(saved || {});
    console.log('설정 파일에 적힌 값입니다. 서버는 부를 때마다 이 파일을 새로 읽습니다.');
    await verify(effective(saved || {}));
    console.log('');
    console.log('바꾸기: node tools/app-version.js --apk=0.2.8   (지우기: --apk=none)');
    console.log('');
    return;
  }

  const f = parseFlags(args);
  const next = Object.assign({}, saved || {});
  const changed = [];
  Object.keys(f).forEach(flag => {
    const key = FLAG_KEY[flag];
    next[key] = toValue(flag, f[flag]);
    changed.push(key);
  });

  const info = effective(next);
  const over = minAboveLatest(info);
  if (over.length) {
    die(['최소판(' + info.min + ')이 ' +
         over.map(ch => NAME[ch] + ' 최신판 ' + info.latest[ch]).join(' · ') +
         ' 보다 높아서 저장하지 않았습니다.',
         '  그 가게로 깐 사람은 받을 판이 없는데 업데이트하라는 말만 계속 듣게 됩니다.',
         '  그 가게에 새 판이 올라간 뒤 최신판을 먼저 올리거나, 최소판을 낮춰 주세요.']);
  }

  if (!saved) {
    console.log('');
    console.log('이 컴퓨터에는 아직 서버 설정이 없어서 새로 만듭니다: ' + FILE);
    console.log('  서버가 다른 컴퓨터에서 돈다면 그 컴퓨터에서 다시 돌려야 합니다.');
  }
  CONFIG.save(next);
  show(next, changed);
  console.log('저장했습니다. 서버는 부를 때마다 설정을 새로 읽으므로 다시 띄울 필요는 없습니다.');
  console.log('앱은 6시간에 한 번까지만 물으므로 폰에 뜨기까지 몇 시간 걸릴 수 있습니다.');
  console.log('');
  await verify(info);

  /* 0.2.8 이하의 최소판은 아무에게도 안 뜹니다. 그보다 낮은 앱에는 이
     안내가 없습니다. 오늘 쓰는 옛 앱에 알리려고 올렸다면 헛일이라고 말해
     줍니다 — 안 그러면 "올렸는데 왜 아무도 모르지" 가 됩니다. */
  const idle = info.min && APPVER.compareVersions(info.min, FIRST_WITH_NOTICE) <= 0;
  if (idle) {
    console.log('');
    console.log('  ! 최소판(' + info.min + ')으로는 아무에게도 안내가 안 뜹니다.');
    console.log('    안내는 ' + FIRST_WITH_NOTICE + ' 부터 앱에 들어 있어서, 그보다 낮은 앱은 이 값을 모릅니다.');
  }

  /* 최소판이 있는데 비어 있는 가게가 있으면 한 번 짚어 줍니다. 거절할 일은
     아닙니다(그 가게를 아직 안 쓸 수도 있습니다). 다만 그 가게로 깐 사람도
     최소판보다 낮으면 닫을 수 없는 안내를 봅니다. */
  if (info.min && !idle) {
    const empty = APPVER.CHANNELS.filter(ch => !info.latest[ch]);
    if (empty.length) {
      console.log('');
      console.log('  ! ' + empty.map(ch => NAME[ch]).join(' · ') + ' 최신판이 비어 있습니다.');
      console.log('    그쪽으로 깐 사람도 ' + info.min + ' 보다 낮으면 닫을 수 없는 안내를 봅니다.');
      console.log('    그 가게에 ' + info.min + ' 이상이 올라가 있는지 확인하세요.');
    }
  }
  console.log('');
}

main().catch(e => { console.error(e); process.exit(1); });
