/* =============================================================================
 * tools/test-flutter.js — 옮기는 중인 앱의 화면 시험
 *
 *   node tools/test-flutter.js
 *
 * `flutter test` 를 app/ 에서 돌립니다. Flutter 가 없는 컴퓨터에서는
 * **건너뜁니다** — 주인의 윈도우 노트북에는 아직 없고, 거기서 배포 전
 * 점검이 앱과 상관없는 이유로 막히면 안 됩니다.
 *
 * 이 시험이 잡는 것은 폰 없이 잡히는 것들입니다: 버튼을 눌렀을 때
 * 화면이 바뀌는가, 서버가 준 오류 문구가 그대로 보이는가, 서버가 꺼져
 * 있을 때 그렇다고 말하는가. 제스처 · 노치 · 키보드처럼 실제 기기에서만
 * 드러나는 것은 여기서 안 잡힙니다 — 그건 사람이 폰에서 봐야 합니다.
 * ========================================================================== */
'use strict';
const path = require('node:path');
const fs = require('node:fs');
const { spawnSync } = require('node:child_process');

const ROOT = path.join(__dirname, '..');
const APP = path.join(ROOT, 'app');

function findFlutter() {
  if (process.env.FLUTTER) return process.env.FLUTTER;
  const guess = '/opt/flutter/bin/flutter';
  if (fs.existsSync(guess)) return guess;
  const probe = process.platform === 'win32'
    ? spawnSync('where', ['flutter'], { encoding: 'utf8' })
    : spawnSync('sh', ['-c', 'command -v flutter'], { encoding: 'utf8' });
  const p = (probe.stdout || '').trim().split('\n')[0];
  return p || null;
}

if (!fs.existsSync(APP)) {
  console.log('app/ 이 아직 없습니다 — 건너뜁니다.');
  process.exit(0);
}

const flutter = findFlutter();
if (!flutter) {
  console.log('Flutter 가 없어서 건너뜁니다.');
  console.log('옮기는 중인 앱을 검사하려면 Flutter SDK 를 깔고 다시 돌리세요.');
  process.exit(0);
}

const r = spawnSync(flutter, ['test'], {
  cwd: APP, encoding: 'utf8', timeout: 15 * 60 * 1000,
  env: Object.assign({}, process.env, { FLUTTER_ROOT: path.dirname(path.dirname(flutter)) })
});
/* flutter 가 root 로 돌 때 찍는 잔소리는 걷어냅니다 — 실패 줄을 덮습니다. */
const noise = /Woah!|superuser|^\s*\/\s*$|📎|^\s*$/;
const out = ((r.stdout || '') + (r.stderr || ''))
  .split('\n').filter(l => !noise.test(l)).join('\n').trim();
console.log(out.split('\n').slice(-12).join('\n'));
process.exit(r.status === 0 ? 0 : 1);
