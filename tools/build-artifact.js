/* =============================================================================
 * tools/build-artifact.js — 아티팩트 배포용 페이지 생성
 *
 *   node tools/build-artifact.js        dist/index.html 을 만든다
 *
 * 아티팩트 호스트가 <!doctype>/<html>/<head>/<body> 를 자기가 감싸므로,
 * 본문만 남기고 <title> · 폰트 · 스타일시트 링크를 맨 앞에 둔다.
 * css/js 는 상대경로 그대로 두고 publish 의 files 로 같이 올린다.
 * ========================================================================== */
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..');
const SRC = path.join(ROOT, 'prototype', 'index.html');
const DIST = path.join(ROOT, 'dist');
const html = fs.readFileSync(SRC, 'utf8');

const body = html.slice(html.indexOf('<body>') + 6, html.lastIndexOf('</body>')).trim();
const links = [...html.matchAll(/<link rel="stylesheet" href="([^"]+)">/g)].map(m => m[1]);

const out = [];
out.push('<title>Mybody 인바디 플래너</title>');
out.push('<link rel="preconnect" href="https://fonts.googleapis.com">');
out.push('<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>');
out.push('<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Noto+Sans+KR:wght@400;600;700;900&display=swap">');
links.forEach(l => out.push(`<link rel="stylesheet" href="${l}">`));
out.push('<style>');
out.push('  /* 호스트 스켈레톤의 기본 폰트/배경을 이 앱의 것으로 되돌린다 */');
out.push('  html, body { margin: 0; background: var(--bg); color: var(--text); font-size: 15px; }');
out.push('</style>');
out.push('');
out.push(body);

fs.mkdirSync(DIST, { recursive: true });
fs.writeFileSync(path.join(DIST, 'index.html'), out.join('\n') + '\n');

// 함께 올릴 파일 목록을 만들어 둔다 (publish 의 files 인자에 그대로 쓴다)
function walk(dir, base) {
  return fs.readdirSync(dir).flatMap(f => {
    const p = path.join(dir, f);
    const rel = path.posix.join(base, f);
    return fs.statSync(p).isDirectory() ? walk(p, rel) : [rel];
  });
}
const assets = [
  ...walk(path.join(ROOT, 'prototype', 'css'), 'css'),
  ...walk(path.join(ROOT, 'prototype', 'js'), 'js'),
  /* 개인정보처리방침. 앱 안에서 링크로 걸려 있으므로 같이 올라가야
     합니다 — 없으면 눌렀을 때 빈 탭이 뜹니다. */
  'privacy.html'
];
const files = {};
assets.forEach(a => { files[a] = 'prototype/' + a; });

/* 방침의 운영자 칸은 서버에 올릴 때 채워집니다(tools/build-release.js).
   아티팩트는 서버가 없는 미리보기라 채울 이름도 연락처도 없습니다.
   자리표시자를 그대로 두면 __OWNER_NAME__ 이 화면에 뜨는데, 그건
   고장으로 보입니다. 미리보기라고 사실대로 적습니다. */
{
  const PREVIEW = '미리보기 — 실제 서버에 올릴 때 채워집니다';
  const priv = fs.readFileSync(path.join(ROOT, 'prototype', 'privacy.html'), 'utf8')
    .replace(/__OWNER_NAME__/g, PREVIEW)
    .replace(/__OWNER_CONTACT__/g, PREVIEW);
  if (/__OWNER_/.test(priv)) throw new Error('방침의 자리표시자를 못 바꿨습니다');
  fs.mkdirSync(DIST, { recursive: true });
  fs.writeFileSync(path.join(DIST, 'privacy.html'), priv);
  files['privacy.html'] = 'dist/privacy.html';
}
fs.writeFileSync(path.join(DIST, 'files.json'), JSON.stringify(files, null, 1));

const bytes = assets.reduce((n, a) => n + fs.statSync(path.join(ROOT, 'prototype', a)).size, 0)
            + Buffer.byteLength(out.join('\n'));
console.log(`dist/index.html — 보조 파일 ${assets.length}개, 합계 ${(bytes / 1024).toFixed(0)}KB`);
console.log(Object.keys(files).join('\n'));
