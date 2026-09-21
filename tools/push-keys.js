/* =============================================================================
 * tools/push-keys.js — 폰 알림에 쓸 열쇠 한 쌍 만들기
 *
 *   node tools/push-keys.js            새로 만들어 설정에 저장
 *   node tools/push-keys.js --show     지금 있는 것 보기 (비밀은 가림)
 *
 * 이 열쇠가 하는 일
 *   푸시 서비스(구글·애플·모질라)에게 "이 알림은 그 서버가 보낸 게 맞다" 를
 *   증명합니다. 공개키는 브라우저에 그대로 나가고, 비밀키는 서버에만 있습니다.
 *
 * 잃어버리면
 *   지금 켜 둔 사람들의 구독이 전부 무효가 됩니다 — 각자 알림을 다시
 *   켜야 합니다. 그래서 이미 있으면 덮어쓰지 않고 물어봅니다.
 * ========================================================================== */
'use strict';
const path = require('node:path');
const PUSH = require(path.join(__dirname, '..', 'server', 'push.js'));
const CONFIG = require(path.join(__dirname, 'config.js'));
const { load, save } = CONFIG;
const FILE = CONFIG.FILE();

const args = process.argv.slice(2);
const has = f => args.includes('--' + f);
const { cfg } = load();

function mask(v) { return v ? v.slice(0, 8) + '…(' + v.length + '자)' : '(없음)'; }

if (has('show')) {
  console.log('설정 파일: ' + FILE);
  console.log('  공개키  ' + (cfg.vapidPublic || '(없음)'));
  console.log('  비밀키  ' + mask(cfg.vapidPrivate));
  if (!cfg.vapidPublic) {
    console.log('\n아직 없습니다. 만들려면: node tools/push-keys.js');
  }
  process.exit(0);
}

if (cfg.vapidPublic && !has('force')) {
  console.log('이미 열쇠가 있습니다.');
  console.log('  공개키  ' + cfg.vapidPublic);
  console.log('');
  console.log('새로 만들면 지금 알림을 켜 둔 사람들의 구독이 전부 무효가 됩니다 —');
  console.log('각자 앱에서 알림을 다시 켜야 합니다.');
  console.log('그래도 만들려면: node tools/push-keys.js --force');
  process.exit(0);
}

const k = PUSH.generateVapid();
cfg.vapidPublic = k.publicKey;
cfg.vapidPrivate = k.privateKey;
save(cfg);
console.log('열쇠를 만들어 설정에 저장했습니다: ' + FILE);
console.log('  공개키  ' + k.publicKey);
console.log('  비밀키  ' + mask(k.privateKey) + ' — 이 파일 밖으로 내보내지 마세요');
console.log('');
console.log('이제 node tools/serve.js 로 띄우면 알림이 켜집니다.');
console.log('단, 폰 알림은 https 로 열었을 때만 됩니다 (터널). 같은 와이파이의');
console.log('http 주소에서는 브라우저가 알림 자체를 허용하지 않습니다.');
