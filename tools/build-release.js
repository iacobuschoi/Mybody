/* =============================================================================
 * tools/build-release.js — 배포 빌드 만들기
 *
 *   node tools/build-release.js              release/ 에 생성
 *   OUT=/some/dir node tools/build-release.js
 *
 * 개발 빌드와 배포 빌드의 차이는 파일 하나뿐입니다 — js/build.js 의
 * release 플래그. 그 플래그가 고유번호 배지, 피드백 메모, 시드 주입,
 * 내장 샘플 판독, ID 목록 화면을 한꺼번에 끕니다.
 *
 * 여기서 하는 일
 *   1. prototype/ 을 통째로 복사
 *   2. js/build.js 를 release: true 로 바꿔 끼움
 *   3. index.html 에 PWA 머리글(매니페스트 · 아이콘 · theme-color) 삽입
 *   4. 서비스워커 등록 코드 삽입 + sw.js 의 자리표시자를 실제 파일 목록으로
 *   5. 개발 전용 파일(js/screens/idindex.js, css/uid.css) 제외
 *
 * 번들링도 압축도 하지 않습니다. 파일 서른 개를 그냥 올립니다 —
 * HTTP/2 에서는 큰 차이가 없고, 번들러를 들이는 순간 "빌드 없음" 이라는
 * 이 앱의 전제가 깨집니다. 지금 전체가 840KB 입니다.
 * ========================================================================== */
'use strict';
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');
const crypto = require('crypto');

const ROOT = path.join(__dirname, '..');
const SRC = path.join(ROOT, 'prototype');
const OUT = process.env.OUT || path.join(ROOT, 'release');

/* 개발 빌드에만 있는 것들. 배포본에 파일 자체를 넣지 않습니다 —
   플래그로 꺼도 코드가 같이 올라가면, 주소를 아는 사람은 여전히 읽습니다. */
const DEV_ONLY = new Set([
  'js/screens/idindex.js',   // P13 ID 목록 화면
  'css/uid.css'              // 고유번호 배지 스타일
]);

/* 버전 문자열은 서비스워커의 캐시 이름이 됩니다. 이름이 같으면
 * 브라우저는 이미 받아 둔 것을 그대로 씁니다 — 내용이 달라도요.
 *
 * 예전엔 커밋 SHA + '-dirty' 뿐이었습니다. 커밋 없이 고치고 다시
 * 빌드하면 내용은 다른데 이름이 같아서, 올려도 사용자 화면은 안
 * 바뀌었습니다. 고쳤는데 안 고쳐진 것처럼 보이는 상태입니다 —
 * 그 상태로 한참 헤매게 됩니다.
 *
 * 더티일 때는 올릴 파일 전체의 해시를 붙입니다. 내용이 다르면
 * 이름이 다릅니다. */
function version(files, override) {
  let sha = 'nogit', dirty = '';
  try {
    sha = execSync('git rev-parse --short HEAD', { cwd: ROOT }).toString().trim();
    dirty = execSync('git status --porcelain', { cwd: ROOT }).toString().trim();
  } catch { /* git 없이도 빌드는 됩니다 */ }
  if (!dirty && sha !== 'nogit' && !override) return sha;
  const hash = crypto.createHash('sha1');
  (files || []).slice().sort().forEach(f => {
    hash.update(f);
    /* override 는 아래 점검이 씁니다 — "내용이 달라지면 버전도 달라지는가"
       를 확인하려고 파일을 진짜로 고쳤다가 되돌리면, 하필 그 사이에
       파일을 읽는 다른 도구가 깨진 것을 봅니다. 읽는 값만 바꿔 봅니다. */
    hash.update((override && override[f]) || fs.readFileSync(path.join(SRC, f)));
  });
  return sha + '-' + hash.digest('hex').slice(0, 8);
}

function walk(dir, base = '') {
  return fs.readdirSync(dir).flatMap(f => {
    const p = path.join(dir, f);
    const rel = base ? base + '/' + f : f;
    return fs.statSync(p).isDirectory() ? walk(p, rel) : [rel];
  });
}

/* --- 1. 복사 -------------------------------------------------------------- */
fs.rmSync(OUT, { recursive: true, force: true });
fs.mkdirSync(OUT, { recursive: true });

const all = walk(SRC).filter(f => !DEV_ONLY.has(f));
all.forEach(rel => {
  const dst = path.join(OUT, rel);
  fs.mkdirSync(path.dirname(dst), { recursive: true });
  fs.copyFileSync(path.join(SRC, rel), dst);
});

/* --- 2. 빌드 플래그 -------------------------------------------------------- */
const V = version(all);
const NOW = new Date().toISOString();

/* 속성만 정확히 집어서 바꿉니다.
 *
 * 처음엔 /release:\s*false/ 를 그냥 치환했는데, 이 파일 머리 주석에
 * "개발 빌드 (release: false)" 라는 설명이 있어서 그쪽이 먼저 바뀌었습니다.
 * 진짜 플래그는 false 로 남았고, 뒤이은 /release:\s*true/ 검사는 방금
 * 바뀐 그 주석을 보고 통과했습니다. 빌드는 "통과" 라고 말했고 배포본에는
 * 고유번호 배지가 전부 떠 있었습니다.
 *
 * 그래서 두 가지를 바꿨습니다.
 *   (가) 들여쓰기까지 포함해 속성 줄만 집는다
 *   (나) 바뀌었는지를 정규식으로 묻지 않고, 만든 파일을 실제로 실행해서
 *        MB_BUILD.release 를 읽어 본다
 * 그렇게 적혀 있나를 보는 것은 확인이 아닙니다. */
const buildJs = fs.readFileSync(path.join(SRC, 'js/build.js'), 'utf8')
  .replace(/^(\s*)release:\s*false,$/m, '$1release: true,')
  .replace(/^(\s*)version:\s*'dev',$/m, `$1version: ${JSON.stringify(V)},`)
  .replace(/^(\s*)builtAt:\s*null,$/m, `$1builtAt: ${JSON.stringify(NOW)},`);

const probe = { MB_BUILD: null };
new Function('window', buildJs)(probe);
if (!probe.MB_BUILD) throw new Error('build.js 가 MB_BUILD 를 만들지 않습니다');
if (probe.MB_BUILD.release !== true) throw new Error('배포 플래그가 켜지지 않았습니다');
if (probe.MB_BUILD.tools !== false) throw new Error('개발 도구 플래그가 꺼지지 않았습니다');
if (probe.MB_BUILD.version !== V) throw new Error('버전이 안 박혔습니다');
if (!probe.MB_BUILD.builtAt) throw new Error('빌드 시각이 안 박혔습니다');
fs.writeFileSync(path.join(OUT, 'js/build.js'), buildJs);

/* --- 2.5 개인정보처리방침의 운영자 칸 --------------------------------------
 *
 * 이 앱은 사람마다 자기 컴퓨터에 서버를 띄웁니다. 그래서 "개인정보를
 * 처리하는 사람" 이 누구인지는 코드가 알 수 없고, 서버를 띄우는 사람만
 * 압니다. 그 칸을 빌드할 때 채웁니다.
 *
 *   OWNER="김아무개" OWNER_CONTACT="me@example.com" node tools/build-release.js
 *
 * 안 채우면 자리표시자를 그대로 두지 않고 "아직 적지 않았습니다" 라고
 * 적습니다 — __OWNER_NAME__ 이 그대로 보이는 것은 사용자에게 고장으로
 * 보이고, 고장 난 방침은 없는 것보다 나쁩니다. 대신 preflight 가
 * 그 상태를 배포 금지로 잡습니다.
 */
{
  const priv = path.join(OUT, 'privacy.html');
  if (!fs.existsSync(priv)) throw new Error('privacy.html 이 없습니다 — 방침 없이 배포할 수 없습니다');
  /* 안 채웠을 때 무엇이라고 적을 것인가.
   *
   * "아직 적지 않았습니다" 는 고장으로 보입니다. 그런데 이 앱은 주인이
   * 친구에게 주소를 직접 주는 방식이라, 안 적혔어도 사실은 연락할 데가
   * 있습니다 — 주소를 준 그 사람입니다. 그게 참이고 쓸모도 있습니다.
   * 널리 열 거면 preflight 가 따로 막습니다. */
  const UNSET_NAME = '이 서버를 띄운 사람 (주소를 알려준 그 사람)';
  const UNSET_CONTACT = '따로 적어 두지 않았습니다 — 이 주소를 알려준 사람에게 직접 말해 주세요';
  const owner = (process.env.OWNER || '').trim();
  const contact = (process.env.OWNER_CONTACT || '').trim();
  let txt = fs.readFileSync(priv, 'utf8')
    .replace(/__OWNER_NAME__/g, esc(owner || UNSET_NAME))
    .replace(/__OWNER_CONTACT__/g, esc(contact || UNSET_CONTACT));
  if (/__OWNER_/.test(txt)) throw new Error('방침의 자리표시자를 못 바꿨습니다');
  fs.writeFileSync(priv, txt);
  if (!owner || !contact) {
    console.log('  ! 방침의 운영자 칸이 비었습니다 — OWNER · OWNER_CONTACT 를 넣고 다시 빌드하세요');
  }
}

function esc(x) {
  return String(x).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

/* --- 3. index.html ------------------------------------------------------- */
let html = fs.readFileSync(path.join(SRC, 'index.html'), 'utf8');

// 개발 전용 파일 참조 제거
DEV_ONLY.forEach(f => {
  html = html.replace(new RegExp(`\\s*<script src="${f}"></script>`, 'g'), '')
             .replace(new RegExp(`\\s*<link rel="stylesheet" href="${f}">`, 'g'), '');
});

const HEAD = `<link rel="manifest" href="manifest.webmanifest">
<meta name="theme-color" content="#4f46e5">
<meta name="theme-color" media="(prefers-color-scheme: dark)" content="#0e1014">
<meta name="mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-status-bar-style" content="default">
<meta name="apple-mobile-web-app-title" content="Mybody">
<link rel="apple-touch-icon" href="assets/apple-touch-icon.png">
<link rel="icon" type="image/png" sizes="32x32" href="assets/favicon-32.png">
<link rel="icon" type="image/png" sizes="192x192" href="assets/icon-192.png">`;

if (/<\/head>/.test(html)) html = html.replace('</head>', HEAD + '\n</head>');
else html = html.replace(/(<link rel="stylesheet"[^>]*>)(?![\s\S]*<link rel="stylesheet")/, '$1\n' + HEAD);

/* 서비스워커 등록. 실패해도 앱은 그대로 돌아야 하므로 조용히 넘어갑니다 —
   file:// 로 열었거나 HTTPS 가 아니면 등록 자체가 안 됩니다. */
const SW = `
<script>
  if ('serviceWorker' in navigator) {
    window.addEventListener('load', function () {
      navigator.serviceWorker.register('sw.js').catch(function () {});
    });
  }
</script>`;
html = html.replace('</body>', SW + '\n</body>');
fs.writeFileSync(path.join(OUT, 'index.html'), html);

/* --- 4. 서비스워커의 파일 목록 --------------------------------------------- */
/* 껍데기 목록.
 *
 * cache.addAll() 은 같은 URL 이 두 번 들어 있으면 통째로 거부합니다.
 * 처음엔 앞에 'index.html', 'manifest.webmanifest' 를 손으로 넣고 뒤에
 * 파일 목록을 './' 를 붙여 이어 붙였는데, './index.html' 과 'index.html'
 * 은 같은 주소라 중복이 됐습니다. 설치가 조용히 실패했고 — 등록은
 * 성공한 것처럼 보이는데 잠시 뒤 사라졌습니다. 캐시는 만들어진 채로
 * 비어 있었고요.
 *
 * 그래서 전부 './' 로 맞춘 뒤 중복을 걷어냅니다. 아래 점검에서 중복이
 * 남아 있으면 빌드를 실패시킵니다. */
const shell = [...new Set(
  ['./'].concat(
    all.filter(f => /\.(html|js|css|png|svg|webmanifest)$/.test(f) && f !== 'sw.js')
       .map(f => './' + f)
  )
)];
const sw = fs.readFileSync(path.join(SRC, 'sw.js'), 'utf8')
  .replace('__BUILD_VERSION__', V)
  .replace('__SHELL_FILES__', JSON.stringify(shell, null, 2));
if (sw.includes('__SHELL_FILES__') || sw.includes('__BUILD_VERSION__')) {
  throw new Error('sw.js 의 자리표시자를 못 바꿨습니다');
}
new Function(sw);   // 문법 확인
fs.writeFileSync(path.join(OUT, 'sw.js'), sw);

/* --- 5. 점검 --------------------------------------------------------------- */
const problems = [];
const outFiles = walk(OUT);
DEV_ONLY.forEach(f => { if (outFiles.includes(f)) problems.push('개발 전용 파일이 남았습니다: ' + f); });
if (html.includes('idindex.js')) problems.push('index.html 이 아직 idindex.js 를 부릅니다');
if (!outFiles.includes('privacy.html')) problems.push('개인정보처리방침이 빠졌습니다');
if (html.includes('uid.css')) problems.push('index.html 이 아직 uid.css 를 부릅니다');
// 껍데기 목록의 파일이 실제로 있는지 — 하나라도 없으면 서비스워커 설치가 통째로 실패합니다
shell.filter(f => f !== './').forEach(f => {
  const rel = f.replace(/^\.\//, '');
  if (!outFiles.includes(rel)) problems.push('껍데기 목록에 없는 파일: ' + rel);
});
// 중복도 마찬가지입니다 — addAll() 이 거부합니다
const seenShell = new Set();
shell.forEach(f => {
  const u = new URL(f, 'http://x/').pathname;
  if (seenShell.has(u)) problems.push('껍데기 목록에 같은 주소가 두 번: ' + f);
  seenShell.add(u);
});
/* 버전이 실제로 내용을 따라가는지 — 서비스워커 캐시 이름이 이 값입니다.
   같은 내용이면 같아야 하고, 한 글자라도 다르면 달라야 합니다.
   예전엔 커밋 SHA 뿐이라, 커밋 없이 고치고 다시 빌드하면 이름이 같아서
   올려도 사용자 화면이 안 바뀌었습니다. */
{
  const again = version(all);
  if (again !== V) problems.push('같은 내용인데 버전이 달라집니다: ' + V + ' vs ' + again);
  const one = all[0];
  const changed = Buffer.concat([fs.readFileSync(path.join(SRC, one)), Buffer.from('\n// x\n')]);
  const shifted = version(all, { [one]: changed });
  if (shifted === V) {
    problems.push('내용이 달라졌는데 버전이 그대로입니다 — 서비스워커가 안 갈립니다');
  }
}

const bytes = outFiles.reduce((n, f) => n + fs.statSync(path.join(OUT, f)).size, 0);

console.log(`release/ — 파일 ${outFiles.length}개 · ${(bytes / 1024).toFixed(0)}KB · ${V}`);
console.log(`  빌드 플래그   release: true`);
console.log(`  제외한 파일   ${[...DEV_ONLY].join(', ')}`);
console.log(`  서비스워커    껍데기 ${shell.length}개 미리 받음`);
if (problems.length) {
  console.log('\n문제:');
  problems.forEach(p => console.log('  ✗ ' + p));
  process.exit(1);
}
console.log('\n통과 — 이 폴더를 그대로 올리면 됩니다');
