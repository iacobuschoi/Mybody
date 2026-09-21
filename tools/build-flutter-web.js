/* =============================================================================
 * tools/build-flutter-web.js — 옮기는 중인 앱을 웹으로 빌드합니다
 *
 *   node tools/build-flutter-web.js
 *
 * 왜 웹으로도 빌드하는가
 *   APK 를 만들려면 안드로이드 SDK 와 실제 기기가 필요하고, 아이폰은
 *   맥이 필요합니다. 그런데 웹 빌드는 **지금 있는 서버에 얹기만 하면**
 *   폰에서 바로 열립니다 — 실제 손가락으로, 아이폰 친구까지 같이.
 *   화면을 옮기는 동안 만져 볼 수 있는 유일한 길입니다.
 *
 *   그리고 검사에도 씁니다. 크로미움으로 띄워서 실제로 눌러 보면,
 *   "누르면 터지는 버튼" 을 사람이 폰을 들기 전에 찾을 수 있습니다.
 *
 * CanvasKit 을 왜 손대는가
 *   Flutter 웹은 기본으로 CanvasKit 을 구글 CDN(gstatic.com)에서 받습니다.
 *   네트워크가 막힌 곳에서는 **화면이 통째로 안 뜹니다.** 빌드 결과에
 *   사본이 이미 들어 있는데도요. 그 사본을 보도록 한 줄 고칩니다.
 *   손으로 고치면 다음 빌드에서 사라지므로 여기서 합니다.
 * ========================================================================== */
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const ROOT = path.join(__dirname, '..');
const APP = path.join(ROOT, 'app');

function findFlutter() {
  if (process.env.FLUTTER) return process.env.FLUTTER;
  if (fs.existsSync('/opt/flutter/bin/flutter')) return '/opt/flutter/bin/flutter';
  const probe = process.platform === 'win32'
    ? spawnSync('where', ['flutter'], { encoding: 'utf8' })
    : spawnSync('sh', ['-c', 'command -v flutter'], { encoding: 'utf8' });
  return (probe.stdout || '').trim().split('\n')[0] || null;
}

const flutter = findFlutter();
if (!flutter) {
  console.log('Flutter 가 없습니다. https://docs.flutter.dev/get-started 에서 받으세요.');
  process.exit(1);
}

console.log('빌드 중… (처음이면 1~2분 걸립니다)');
const r = spawnSync(flutter, ['build', 'web', '--release'], {
  cwd: APP, encoding: 'utf8', timeout: 20 * 60 * 1000,
  env: Object.assign({}, process.env, { FLUTTER_ROOT: path.dirname(path.dirname(flutter)) })
});
if (r.status !== 0) {
  console.log(((r.stdout || '') + (r.stderr || '')).split('\n').slice(-20).join('\n'));
  process.exit(1);
}

/* CanvasKit 을 빌드에 딸려 온 사본으로 돌립니다.
 *
 * 안 고치면 엔진이 www.gstatic.com 에서 canvaskit.js 를 받으려 하고,
 * 막힌 곳에서는 **화면이 통째로 안 뜹니다** — 흰 화면에 콘솔 오류만
 * 남습니다. 빌드에 이미 canvaskit/ 사본이 들어 있는데도요.
 *
 * 처음에는 `s.indexOf('canvasKitBaseUrl') < 0` 으로 "이미 고쳤나" 를
 * 봤는데, **압축된 엔진 코드 안에 그 이름이 원래 들어 있습니다.**
 * 그래서 검사가 언제나 "이미 고쳐져 있다" 고 답했고 패치가 한 번도
 * 안 걸렸습니다. 빌드는 성공하고, 오류도 없고, 화면만 안 떴습니다.
 * 우리가 넣는 표식을 그대로 찾습니다. */
const boot = path.join(APP, 'build', 'web', 'flutter_bootstrap.js');
let s = fs.readFileSync(boot, 'utf8');
const anchor = '_flutter.loader.load({';
const MARK = 'canvasKitBaseUrl: "canvaskit/"';
if (s.indexOf(MARK) < 0) {
  const i = s.indexOf(anchor);
  if (i < 0) {
    console.log('✗ flutter_bootstrap.js 의 모양이 바뀌었습니다 — CanvasKit 경로를 못 고쳤습니다.');
    console.log('  이대로 두면 네트워크가 막힌 곳에서 화면이 안 뜹니다.');
    process.exit(1);
  }
  s = s.slice(0, i + anchor.length) +
      '\n  config: { ' + MARK + ' },' +
      s.slice(i + anchor.length);
  fs.writeFileSync(boot, s);
  console.log('CanvasKit 을 내장 사본으로 돌렸습니다.');
} else {
  console.log('CanvasKit 은 이미 내장 사본을 씁니다.');
}

/* 고쳐졌는지 **확인합니다.** 위에서 한 번 조용히 실패했던 자리입니다. */
if (fs.readFileSync(boot, 'utf8').indexOf(MARK) < 0) {
  console.log('✗ CanvasKit 경로를 못 박았습니다 — 막힌 네트워크에서 화면이 안 뜹니다.');
  process.exit(1);
}

const out = path.join(APP, 'build', 'web');
let bytes = 0;
(function walk(d) {
  for (const f of fs.readdirSync(d)) {
    const p = path.join(d, f);
    const st = fs.statSync(p);
    if (st.isDirectory()) walk(p); else bytes += st.size;
  }
})(out);

console.log('');
console.log('✓ ' + out);
console.log('  크기 ' + (bytes / 1024 / 1024).toFixed(1) + 'MB');
console.log('');
console.log('폰에서 만져 보려면 이 폴더를 서버로 내보내세요:');
console.log('  STATIC=' + path.relative(ROOT, out) + ' node tools/serve.js');
console.log('');
