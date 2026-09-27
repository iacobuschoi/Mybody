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
 * 시험판 참여 링크(join)
 *   아이폰 TestFlight 공개 링크 · 플레이 비공개 테스트 참여 주소 · 그 테스트에 들어가려면
 *   먼저 가입해야 하는 구글 그룹 주소. 시험판을 쓰는 사람이 친구에게 "이걸로 들어와" 를
 *   앱 안에서 바로 건넬 수 있게 내보냅니다(앱의 시험판 환영 화면). **적힌 것만** 나가고,
 *   https 가 아니면 버립니다 — 기본 주소가 없습니다. 초대 링크는 판마다가 아니라 시험을
 *   새로 열 때 바뀌는 값이라, 코드에 박아 두면 닫힌 시험으로 사람을 보냅니다.
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
/* 시험판 참여 링크 — 내보내는 이름 ↔ 설정 키. 이것도 tools/config.js 의 DEFAULTS 와 같아야 합니다. */
const JOIN_KEY = { ios: 'appJoinIos', android: 'appJoinAndroid', androidGroup: 'appJoinAndroidGroup' };

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

/** 시험판 참여 링크 — **적혀 있고 https 인 것만.** 하나도 없으면 {}. */
function joinLinks(cfg) {
  const c = cfg || {}, join = {};
  Object.keys(JOIN_KEY).forEach(k => {
    const u = cleanUrl(c[JOIN_KEY[k]]);
    if (u) join[k] = u;
  });
  return join;
}

/** GET /api/version 이 돌려줄 것. 개인정보는 없습니다 — 설정 값뿐입니다.
 *  join 은 늘 싣습니다(비었으면 {}). 앱이 "이 서버는 join 을 모른다(옛 서버)" 와
 *  "링크가 없다" 를 가를 수 있게 — 옛 서버는 이 칸 자체가 없습니다. */
function versionInfo(cfg) {
  const c = cfg || {};
  const latest = {}, urls = {};
  CHANNELS.forEach(ch => {
    latest[ch] = cleanVersion(c[LATEST_KEY[ch]]);
    urls[ch] = cleanUrl(c[URL_KEY[ch]]) || DEFAULT_URLS[ch];
  });
  return { ok: true, latest: latest, min: cleanVersion(c[MIN_KEY]), urls: urls, join: joinLinks(c) };
}

module.exports = { CHANNELS, LATEST_KEY, URL_KEY, MIN_KEY, JOIN_KEY, DEFAULT_URLS,
                   cleanVersion, compareVersions, cleanUrl, joinLinks, versionInfo };
