/* =============================================================================
 * server/appversion.js — 앱에게 "새 판이 나왔다 · 이 판은 너무 낡았다" 를 알릴 값
 *
 * 왜 있나
 *   앱스토어와 플레이는 조용히 자동 업데이트하고, TestFlight 는 알아서
 *   알려 줍니다. 그런데 GitHub Releases 에서 APK 를 직접 받아 깐 친구는
 *   새 판이 나온 것을 영영 모릅니다. 그리고 서버가 동의 판을 올렸을 때
 *   옛 앱이 본 것은 "앱을 업데이트해 주세요" 한 줄뿐이었습니다 — 어디서,
 *   왜 해야 하는지는 없이.
 *
 * 값은 ~/.mybody/config.json 에 있고 tools/app-version.js 로 고칩니다.
 * 이 파일은 그 값을 **내보내도 되는 모양으로 다듬기만** 합니다. 서버와
 * 도구가 같은 규칙(x.y.z · 기본 주소)을 쓰도록 한 군데 둡니다 — 도구는
 * 받아 주는데 서버는 버리는 값이 생기면, 주인은 적었는데 안내가 안 나갑니다.
 * ========================================================================== */
'use strict';

/* testflight: 아이폰 시험판. TestFlight 는 새 빌드를 스스로 알리지만, 앱 안에서도 "새 판이
   있다" 를 같은 자리에서 보여 달라는 주인의 요청 — 스토어에 낸 판과 시험판은 번호가 다릅니다. */
const CHANNELS = ['appstore', 'testflight', 'play', 'apk'];

/* 설정 파일의 키. tools/config.js 의 DEFAULTS 와 이름이 같아야 합니다. */
const LATEST_KEY = { appstore: 'appLatestAppStore', testflight: 'appLatestTestFlight',
                     play: 'appLatestPlay', apk: 'appLatestApk' };
const URL_KEY = { appstore: 'appUrlAppStore', testflight: 'appUrlTestFlight',
                  play: 'appUrlPlay', apk: 'appUrlApk' };
const MIN_KEY = 'appMin';

/* 업데이트 단추가 여는 곳. 설정에 주소가 없으면 이걸 씁니다.
   APK 는 "최신 릴리스" 주소라서 판마다 고칠 필요가 없습니다. */
const DEFAULT_URLS = {
  appstore: 'https://apps.apple.com/kr/app/id6815144446',
  /* TestFlight 앱이 깔린 폰에서는 이 주소가 TestFlight 의 이 앱 화면으로 열립니다. */
  testflight: 'https://beta.itunes.apple.com/v1/app/6815144446',
  play: 'https://play.google.com/store/apps/details?id=io.github.iacobuschoi.mybody',
  apk: 'https://github.com/iacobuschoi/Mybody/releases/latest'
};

/** "0.2.8" 꼴만 받습니다. 아니면 ''.
 *
 *  손으로 고친 설정 파일에는 무엇이든 들어 있을 수 있습니다 — "0.2",
 *  숫자 0.28, "0.2.8-beta". 그걸 그대로 내보내면 앱이 비교하다 헷갈려
 *  엉뚱한 안내를 띄웁니다. 모르는 값은 "안내 안 함" 으로 둡니다.
 *  "0.2.08" 처럼 앞에 0 이 붙은 것은 숫자로 같으니 "0.2.8" 로 맞춥니다. */
function cleanVersion(v) {
  if (typeof v !== 'string') return '';
  const m = /^(\d{1,6})\.(\d{1,6})\.(\d{1,6})$/.exec(v.trim());
  if (!m) return '';
  return [m[1], m[2], m[3]].map(Number).join('.');
}

/** 두 판을 숫자로 견줍니다. 둘 다 cleanVersion 을 지난 값이어야 합니다.
 *  "0.2.10" 이 "0.2.9" 보다 뒤입니다 — 글자로 견주면 거꾸로 나옵니다. */
function compareVersions(a, b) {
  const x = String(a).split('.').map(Number), y = String(b).split('.').map(Number);
  for (let i = 0; i < 3; i++) {
    if ((x[i] || 0) !== (y[i] || 0)) return (x[i] || 0) < (y[i] || 0) ? -1 : 1;
  }
  return 0;
}

/** https 주소만 받습니다. 아니면 ''. 앱이 이 주소를 그대로 열기 때문입니다. */
function cleanUrl(v) {
  if (typeof v !== 'string' || !v.trim()) return '';
  try {
    const u = new URL(v.trim());
    return u.protocol === 'https:' ? u.href : '';
  } catch (e) { return ''; }
}

/** GET /api/version 이 돌려줄 것. 개인정보는 없습니다 — 설정 값뿐입니다. */
function versionInfo(cfg) {
  const c = cfg || {};
  const latest = {}, urls = {};
  CHANNELS.forEach(ch => {
    latest[ch] = cleanVersion(c[LATEST_KEY[ch]]);
    urls[ch] = cleanUrl(c[URL_KEY[ch]]) || DEFAULT_URLS[ch];
  });
  return { ok: true, latest: latest, min: cleanVersion(c[MIN_KEY]), urls: urls };
}

module.exports = { CHANNELS, LATEST_KEY, URL_KEY, MIN_KEY, DEFAULT_URLS,
                   cleanVersion, compareVersions, cleanUrl, versionInfo };
