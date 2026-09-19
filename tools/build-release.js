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

const ROOT = path.join(__dirname, '..');
const SRC = path.join(ROOT, 'prototype');
const OUT = process.env.OUT || path.join(ROOT, 'release');

/* 개발 빌드에만 있는 것들. 배포본에 파일 자체를 넣지 않습니다 —
   플래그로 꺼도 코드가 같이 올라가면, 주소를 아는 사람은 여전히 읽습니다. */
const DEV_ONLY = new Set([
  'js/screens/idindex.js',   // P13 ID 목록 화면
  'css/uid.css'              // 고유번호 배지 스타일
]);

function version() {
  try {
    const sha = execSync('git rev-parse --short HEAD', { cwd: ROOT }).toString().trim();
    const dirty = execSync('git status --porcelain', { cwd: ROOT }).toString().trim();
    return sha + (dirty ? '-dirty' : '');
  } catch { return 'nogit'; }
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
const V = version();
const NOW = new Date().toISOString();
const buildJs = fs.readFileSync(path.join(SRC, 'js/build.js'), 'utf8')
  .replace(/release:\s*false/, 'release: true')
  .replace(/version:\s*'dev'/, `version: ${JSON.stringify(V)}`)
  .replace(/builtAt:\s*null/, `builtAt: ${JSON.stringify(NOW)}`);
if (!/release:\s*true/.test(buildJs)) throw new Error('build.js 의 release 플래그를 못 바꿨습니다');
fs.writeFileSync(path.join(OUT, 'js/build.js'), buildJs);

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
const shell = ['./', 'index.html', 'manifest.webmanifest']
  .concat(all.filter(f => /\.(js|css|png|svg|webmanifest)$/.test(f) && f !== 'sw.js')
             .map(f => './' + f));
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
if (html.includes('uid.css')) problems.push('index.html 이 아직 uid.css 를 부릅니다');
// 껍데기 목록의 파일이 실제로 있는지 — 하나라도 없으면 서비스워커 설치가 통째로 실패합니다
shell.filter(f => f !== './').forEach(f => {
  const rel = f.replace(/^\.\//, '');
  if (!outFiles.includes(rel)) problems.push('껍데기 목록에 없는 파일: ' + rel);
});
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
