#!/usr/bin/env node
/* =============================================================================
 * tools/asc-submit.js — 앱스토어 심사 · TestFlight 베타 심사를 API 로 다시 올리기 (웹 로그인 없이)
 *
 *   node tools/asc-submit.js --version 0.2.15 --build 298 [--beta friends] [--drop-old-beta]
 *                            [--submit] [--whats-new "…"] [--review-notes-file 파일]
 *
 *   node tools/asc-submit.js --link-only --beta friends [--submit] [--link-off]
 *
 *   node tools/asc-submit.js --release --version 0.2.20 [--submit]
 *
 *   --submit 이 없으면 **읽기만** 합니다(지금 상태와 할 일을 찍음). 있을 때만 바꿉니다.
 *   환경변수: ASC_KEY_ID · ASC_ISSUER_ID · ASC_KEY_P8 또는 ASC_KEY_P8_BASE64 (tools/asc.js 와 같음)
 *            ASC_BUNDLE_ID (기본 io.github.iacobuschoi.mybody)
 *
 * 왜 있는가
 *   0.2.8 이 앱스토어 심사에 「대기 중」 으로 사흘째 걸려 있는데, 그 사이 판이 일곱 번 나갔습니다.
 *   주인이 "새 판으로 다시 올려라" 했습니다. 노트북의 애플 웹 로그인은 풀려 있고, CI 에는 서명에
 *   쓰는 App Store Connect API 열쇠가 있습니다 — 같은 열쇠로 심사 제출도 됩니다.
 *
 * 무엇을 하는가 (앱스토어)
 *   1. 번들 ID 로 앱을 찾습니다.
 *   2. 걸려 있는 심사 제출(reviewSubmissions)을 닫습니다 — 대기 · 심사 중은 취소, 거절된 것(문제 있음)은 애플이
 *      취소를 받지 않으니 거절된 항목을 뺍니다(다 빼면 제출이 끝남). 애플 쪽 정리(CANCELING · COMPLETING →
 *      COMPLETE)와 판(appStoreVersion)이 고칠 수 있는 상태가 될 때까지 기다립니다(몇 초~몇 분).
 *   3. 아직 출시된 적 없는 판이면 그 판의 번호를 새 번호로 바꿉니다(0.2.8 → 0.2.15). 심사 정보(데모 계정 ·
 *      메모) · 설명 · 스크린샷은 그 판에 붙어 있으니 그대로 따라옵니다. 이미 출시된 판뿐이면 새 판을 만듭니다.
 *   4. 빌드(버전 + 빌드 번호, 처리 완료)를 그 판에 붙이고, 새 심사 제출을 만들어 판을 넣고 제출합니다.
 *      그래도 새 제출 · 판 넣기가 409 면 기다렸다 다시 합니다 — 판이 정말 들어간 것을 본 뒤에만 제출합니다.
 *   이미 이 판 · 이 빌드로 심사 대기 · 심사 중이면 아무것도 바꾸지 않습니다(응답을 못 받은 실행을 다시 돌려도
 *   멀쩡한 제출을 취소하지 않게).
 *
 * 거절된 제출(UNRESOLVED_ISSUES)이 하나뿐일 때 (10/2 — 0.2.20 이 1.4.1 로 거절)
 *   취소하지 않고 **같은 제출로 다시 냅니다**(웹의 「다시 심사 요청」 과 같음 — 거절 때 오간 기록이 그 제출에
 *   이어짐). 판 번호 · 빌드를 바꾸고 → 거절된 항목을 「고침」(resolved)으로 → 제출(submitted)합니다.
 *   애플이 그 길을 400 · 404 · 409 · 422 로 받지 않으면 위의 2~4(거절된 항목을 빼고 새로 내기)로 넘어갑니다.
 *   항목도 못 빼면 멈추고 웹에서 누를 단추(「Resubmit to App Review」)를 알려 줍니다. 401 · 403 · 5xx 는 넘어가지
 *   않고 멈춥니다. 거절된 판은 이미 대기 줄에서 빠져 있어서, 다시 내도 잃는 순서는 없습니다.
 *
 * 심사 메모 (--review-notes-file 파일)
 *   --submit 일 때 그 판의 「App Review 정보 → 메모」(appStoreReviewDetail.notes) 끝에 파일 내용을
 *   덧붙입니다(API 로는 Resolution Center 답장을 못 쓰니 심사원에게 하는 말은 여기에). 첫 줄이 이미 메모에
 *   있으면 다시 붙이지 않습니다. 원래 메모 · 데모 계정 · 연락처는 **읽기만 하고 로그에 찍지 않습니다**
 *   (Actions 로그는 공개 — 글자 수 · 애플 오류 코드만). 메모를 못 붙이면(못 읽음 · 못 씀 · 합쳐서 4000자 넘음)
 *   **제출하지 않고 멈춥니다** — 심사원에게 할 말 없이 내지 않으려고(그 앞의 일은 다시 돌려도 무해).
 *   읽기만일 때는 붙을지(원래 + 새 = 합계/4000)만 찍습니다.
 *
 * 무엇을 하는가 (--beta 그룹이름)
 *   그 외부 테스트 그룹에 빌드를 넣고, 「테스트할 내용」(--whats-new)을 적고, 베타 심사를 제출합니다.
 *   --drop-old-beta 면 그 그룹의 다른 빌드는 뺍니다(옛 판이 먼저 승인돼 친구들이 옛 판을 받는 일을 막음).
 *
 * 무엇을 하는가 (--link-only --beta 그룹이름)
 *   그 외부 그룹의 TestFlight 공개 링크를 찍습니다(판 · 빌드 번호는 안 받음). --submit 이면 꺼져 있을 때
 *   켭니다(인원 제한 없음). 친구에게 보내는 초대 문구의 「아이폰: …」 이 이 링크입니다 — 주소를 받으면
 *   노트북이 tools/app-version.js --join-ios=<링크> 로 서버에 넣습니다. 누구나 받을 수 있지만, 그룹에
 *   승인된 빌드가 있어야 실제로 깔립니다(베타 심사 통과 뒤).
 *   --link-off 를 더하면 반대로 닫습니다(--submit 일 때만 바꿈).
 *
 * 무엇을 하는가 (--release --version 판번호)
 *   주인 결정(9/29): "애플 심사 통과하면 배포" — 0.2.20 은 「수동 출시」 로 냈으니 승인되면
 *   PENDING_DEVELOPER_RELEASE 에서 멈춰 기다립니다. 그 판이 그 상태일 때만(두 칸 모두) --submit 으로
 *   출시 요청(appStoreVersionReleaseRequests)을 보냅니다. 이미 출시 중 · 출시됐으면 「이미 출시됨」 으로
 *   끝나고, 아직 심사 중이면(두 칸이 잠깐 다를 때도) 아무것도 안 하고 **성공(0)으로** 끝납니다 — 한
 *   시간마다 돌려도 빨간 불이 쌓이지 않게. 심사에서 빠졌으면(거절 · 철회 · 제출 전으로 돌아감 — DEAD)
 *   실패(1)입니다: 기다려도 승인되지 않으니 고쳐서 다시 내야 하고, 그걸 초록 「기다리는 중」 으로 덮으면
 *   아무도 모릅니다. 판 번호를 못 찾거나 애플이 출시 요청을 거절해도 실패(1)입니다(사람이 봐야 함).
 *   심사 제출 · 베타 그룹 · 공개 링크는 읽지도 바꾸지도 않습니다(--beta 등을 줘도 무시).
 *
 * 앱스토어 페이지 (읽기만 · 기본 모드의 --submit 없는 읽기와 --release)
 *   상태 줄 뒤에 iTunes lookup(로그인 없음)으로 「앱스토어 페이지: 공개됨 (판 …)」 / 「아직 안 보임」 을
 *   찍습니다. 출시 요청 뒤에도 페이지가 뜨기까지 시간이 걸립니다 — 설치 링크(/get)를 앱스토어로 돌리거나
 *   app-version.js --appstore 를 적는 신호는 「출시 요청 보냄」 이 아니라 이 줄입니다(docs/DEPLOY.md
 *   「가게에 실제로 올라가기 전에는 올리지 마세요」). 못 읽어도 실행은 멈추지 않습니다.
 *
 * 멈추는 자리
 *   빌드가 없거나 처리 중이면(processingState ≠ VALID) 아무것도 바꾸지 않고 멈춥니다. 취소한 뒤 판이
 *   고칠 수 있는 상태로 안 바뀌면(시간 초과) 새 제출을 만들지 않고 멈춥니다 — 반쯤 된 상태로 두지 않으려고
 *   **바꾸기 전에 확인할 수 있는 것은 전부 먼저 확인**합니다.
 * ========================================================================== */
'use strict';
const fs = require('fs');
const https = require('https');
const asc = require('./asc.js');

const OPEN_REVIEW = ['WAITING_FOR_REVIEW', 'IN_REVIEW', 'UNRESOLVED_ISSUES', 'READY_FOR_REVIEW'];
/* 판의 상태 중 번호 · 빌드를 바꿀 수 있는 것. */
const EDITABLE = ['PREPARE_FOR_SUBMISSION', 'DEVELOPER_REJECTED', 'REJECTED', 'METADATA_REJECTED',
  'INVALID_BINARY'];
const RELEASED = ['READY_FOR_SALE', 'READY_FOR_DISTRIBUTION', 'PROCESSING_FOR_DISTRIBUTION',
  'PENDING_APPLE_RELEASE', 'PENDING_DEVELOPER_RELEASE', 'REPLACED_WITH_NEW_VERSION', 'REMOVED_FROM_SALE',
  'DEVELOPER_REMOVED_FROM_SALE'];
/* --release: 출시 요청을 받는 상태는 이것 하나(「수동 출시」 로 낸 판이 승인되면 여기서 기다림). */
const RELEASABLE = 'PENDING_DEVELOPER_RELEASE';
/* 이미 출시가 시작됐거나 끝난 상태 — 옛 칸(…_APP_STORE · …_SALE)과 새 칸(…_DISTRIBUTION) 둘 다. */
const LIVE = ['PROCESSING_FOR_APP_STORE', 'PROCESSING_FOR_DISTRIBUTION', 'READY_FOR_SALE', 'READY_FOR_DISTRIBUTION'];
/* 심사에서 빠진 상태 — 기다려도 PENDING_DEVELOPER_RELEASE 가 오지 않습니다(고쳐서 다시 제출해야 함).
   「아직 승인 전」 으로 0 을 내면 한 시간마다 도는 호출이 초록 불로 끝없이 기다립니다. */
const DEAD = ['REJECTED', 'METADATA_REJECTED', 'INVALID_BINARY', 'DEVELOPER_REJECTED', 'PREPARE_FOR_SUBMISSION'];
/* 심사는 지났지만 우리가 출시 요청을 낼 자리가 아닌 상태 — 「승인 전」 이라고 찍으면 틀린 말이 됩니다. */
const PAST_REVIEW = ['PENDING_APPLE_RELEASE', 'ACCEPTED', 'PREORDER_READY_FOR_SALE', 'REPLACED_WITH_NEW_VERSION',
  'REMOVED_FROM_SALE', 'DEVELOPER_REMOVED_FROM_SALE'];
const LOOKUP = 'https://itunes.apple.com/lookup';
const LOOKUP_MS = 8000;
/* 「App Review 정보 → 메모」 의 최대 길이(애플 4000자). */
const NOTES_MAX = 4000;
/* 거절된 제출을 같은 제출로 다시 낼 때, 애플이 「그 상태 · 그 요청으로는 안 됨」 이라고 하는 답 —
   이때만 닫고 새로 내는 길로 넘어갑니다. 401 · 403(열쇠 · 권한) · 5xx · 네트워크는 그대로 멈춥니다. */
const RESUBMIT_SOFT = [400, 404, 409, 422];

/** 애플 오류의 코드 · 설명을 한 줄로(로그용 · 200자). */
function appleDetail(e) {
  return ((e && e.errors) || []).map(x => [x.code, x.detail || x.title].filter(Boolean).join(': '))
    .filter(Boolean).join(' | ').replace(/\s+/g, ' ').slice(0, 200);
}

function arg(argv, k, d) {
  const i = argv.indexOf(k);
  return i >= 0 && i + 1 < argv.length ? argv[i + 1] : d;
}
const has = (argv, k) => argv.includes(k);

/** 판의 상태 — 새 칸(appVersionState)이 있으면 그것, 없으면 옛 칸(appStoreState). */
function stateOf(v) {
  const a = (v && v.attributes) || {};
  return String(a.appStoreState || a.appVersionState || '');
}
/** 두 칸을 다 — 애플이 두 칸을 따로 갱신해 잠깐 다를 때가 있습니다. 「이미 출시됨」 은 둘 중 하나라도로,
 *  「출시 요청을 보내도 됨」 은 두 칸 모두로 봅니다(releaseVersion). */
function statesOf(v) {
  const a = (v && v.attributes) || {};
  return [...new Set([a.appStoreState, a.appVersionState].filter(Boolean).map(String))];
}

async function findApp(c, bundleId) {
  const r = await c.call('GET', `/v1/apps?filter[bundleId]=${encodeURIComponent(bundleId)}&limit=5`);
  const app = (r.data || []).find(a => a.attributes && a.attributes.bundleId === bundleId);
  if (!app) throw new Error(`앱을 못 찾았습니다: ${bundleId}`);
  return app;
}

async function versionsOf(c, appId) {
  const r = await c.call('GET', `/v1/apps/${appId}/appStoreVersions?filter[platform]=IOS&limit=20`);
  return r.data || [];
}

async function openSubmissions(c, appId) {
  const r = await c.call('GET',
    `/v1/reviewSubmissions?filter[app]=${appId}&filter[platform]=IOS&filter[state]=${OPEN_REVIEW.join(',')}&limit=20`);
  return r.data || [];
}

async function findBuild(c, appId, version, build) {
  const r = await c.call('GET',
    `/v1/builds?filter[app]=${appId}&filter[version]=${encodeURIComponent(build)}` +
    `&filter[preReleaseVersion.version]=${encodeURIComponent(version)}&filter[preReleaseVersion.platform]=IOS&limit=5`);
  return (r.data || [])[0] || null;
}

async function sleep(ms, opts) { if (!opts.noWait) await new Promise(r => setTimeout(r, ms)); }

/** 계획만 세웁니다 — 아무것도 바꾸지 않습니다. */
async function plan(c, opts) {
  const app = await findApp(c, opts.bundleId);
  const versions = await versionsOf(c, app.id);
  const subs = await openSubmissions(c, app.id);
  const build = await findBuild(c, app.id, opts.version, opts.build);
  const unreleased = versions.filter(v => !RELEASED.includes(stateOf(v)));
  /* 고칠 판: 같은 번호가 이미 있으면 그것, 아니면 출시 안 된 판(심사 대기 중이던 0.2.8 같은 것). */
  const target = versions.find(v => v.attributes.versionString === opts.version) || unreleased[0] || null;
  return { app, versions, subs, build, target };
}

async function waitEditable(c, versionId, opts) {
  const tries = opts.tries || 30;
  for (let i = 0; i < tries; i++) {
    const r = await c.call('GET', `/v1/appStoreVersions/${versionId}`);
    const s = stateOf(r.data);
    if (EDITABLE.includes(s)) return s;
    opts.log(`  판 상태 ${s} — 취소가 반영되길 기다립니다 (${i + 1}/${tries})`);
    await sleep(opts.waitMs || 10000, opts);
  }
  throw new Error('취소한 뒤에도 판이 고칠 수 있는 상태가 되지 않았습니다 — 새 제출을 만들지 않고 멈춥니다');
}

/** 판 번호를 opts.version 으로(다르면), 빌드를 그 판에 붙입니다. 바꾼 번호는 ver 에도 적습니다 — 같은 제출로
 *  다시 내려다 닫고 새로 내는 길로 넘어가도 번호를 두 번 바꾸지 않게. */
async function editVersion(c, opts, p, ver) {
  if (ver.attributes.versionString !== opts.version) {
    opts.log(`판 번호 바꾸기: ${ver.attributes.versionString} → ${opts.version}`);
    await c.call('PATCH', `/v1/appStoreVersions/${ver.id}`, {
      data: { type: 'appStoreVersions', id: ver.id, attributes: { versionString: opts.version } },
    });
    ver.attributes.versionString = opts.version;
  }
  opts.log(`빌드 붙이기: ${opts.version} (${opts.build})`);
  await c.call('PATCH', `/v1/appStoreVersions/${ver.id}/relationships/build`, {
    data: { type: 'builds', id: p.build.id },
  });
}

/** 그 판에 붙은 빌드가 이 빌드인가. 못 읽으면(404 외) 던집니다 — 「아니다」 로 넘기면 멀쩡한 제출을 닫습니다. */
async function buildIs(c, versionId, buildId) {
  try {
    const r = await c.call('GET', `/v1/appStoreVersions/${versionId}/build`);
    return !!(r && r.data && r.data.id === buildId);
  } catch (e) {
    if (e.status === 404) return false;
    throw e;
  }
}

/** 제출의 항목들(판 관계 포함). */
async function itemsOf(c, subId) {
  return (await c.call('GET', `/v1/reviewSubmissions/${subId}/items?include=appStoreVersion&limit=50`)).data || [];
}
const itemVer = it => ((((it && it.relationships) || {}).appStoreVersion || {}).data || {}).id;

/** 심사 메모 — 원래 메모를 읽어 덧붙일 글과 합친 결과만 돌려줍니다(바꾸지 않음). 원래 내용은 밖으로 찍지
 *  않습니다. { detail, old, already, notes } — detail 이 null 이면 심사 정보가 아직 없음(404). */
async function notesPlan(c, opts, ver) {
  const add = opts.reviewNotes;
  let detail = null;
  try {
    detail = (await c.call('GET', `/v1/appStoreVersions/${ver.id}/appStoreReviewDetail`)).data || null;
  } catch (e) {
    if (e.status !== 404) throw e;
  }
  const old = String((detail && detail.attributes && detail.attributes.notes) || '');
  const mark = add.split('\n')[0].trim();
  const already = !!mark && old.includes(mark);
  const notes = old.trim() ? `${old.replace(/\s+$/, '')}\n\n${add}` : add;
  return { detail, old, already, notes };
}

/** 애플 오류의 코드만(심사 정보 쪽 — 설명은 보낸 값을 되풀이할 수 있어 찍지 않음). */
const codesOf = e => ((e && e.errors) || []).map(x => x && x.code).filter(Boolean).join(' | ').slice(0, 120);

/** 심사 메모 덧붙이기(머리말 「심사 메모」). 메모 파일을 줬는데 못 붙이면 **던집니다** — 심사원에게 할 말
 *  없이 내지 않으려고(이 앞의 일은 다시 돌려도 무해하니 멈춰도 잃는 것이 없음). 원래 메모 · 데모 계정 ·
 *  연락처는 로그에 찍지 않습니다(글자 수만). 돌려주는 값: 'added' · 'already' · 'none'(파일 없음). */
async function addReviewNotes(c, opts, ver) {
  const log = opts.log;
  const add = opts.reviewNotes;
  if (!add) return 'none';
  const stop = why => new Error(`심사 메모를 붙이지 못해 제출하지 않고 멈춥니다(${why}) — 판 ${opts.version} · ` +
    `빌드 ${opts.build} 는 붙어 있습니다. 메모 파일을 고치거나 다시 돌리세요`);
  let m;
  try { m = await notesPlan(c, opts, ver); } catch (e) {
    throw stop(`읽기 ${(e && e.status) || '응답 없음'}${codesOf(e) ? ' ' + codesOf(e) : ''}`);
  }
  if (m.already) {
    log('심사 메모: 이미 들어 있음 — 다시 붙이지 않습니다');
    return 'already';
  }
  if (m.notes.length > NOTES_MAX) throw stop(`합치면 ${m.notes.length}자 — 한도 ${NOTES_MAX}`);
  try {
    if (!m.detail) {
      await c.call('POST', '/v1/appStoreReviewDetails', {
        data: { type: 'appStoreReviewDetails', attributes: { notes: add },
          relationships: { appStoreVersion: { data: { type: 'appStoreVersions', id: ver.id } } } },
      });
      log(`심사 메모: 새로 적음 (${add.length}자)`);
    } else {
      await c.call('PATCH', `/v1/appStoreReviewDetails/${m.detail.id}`, {
        data: { type: 'appStoreReviewDetails', id: m.detail.id, attributes: { notes: m.notes } },
      });
      log(`심사 메모: 덧붙임 (원래 ${m.old.length}자 + ${add.length}자)`);
    }
  } catch (e) {
    throw stop(`쓰기 ${(e && e.status) || '응답 없음'}${codesOf(e) ? ' ' + codesOf(e) : ''}`);
  }
  return 'added';
}

/** 거절된 제출(UNRESOLVED_ISSUES)을 취소하지 않고 같은 제출로 다시 냅니다(머리말) — 애플 도움말의
 *  「거절된 항목 고치기 → 다시 심사 요청」 과 같은 순서. 애플이 그 길을 받지 않으면(RESUBMIT_SOFT) null —
 *  부른 쪽이 거절된 항목을 빼고 새로 내는 길로 갑니다. 그 밖의 오류(권한 · 애플 고장 · 메모)는 던집니다. */
async function resubmitUnresolved(c, opts, p, sub) {
  const log = opts.log;
  const ver = p.target;
  const soft = (e, what) => {
    if (!RESUBMIT_SOFT.includes(e && e.status)) throw e;
    const d = appleDetail(e);
    log(`같은 제출로 다시 내기: ${what}에서 애플이 받지 않음(${e.status}${d ? ' ' + d : ''}) — 거절된 항목을 빼고 새로 냅니다`);
    return null;
  };
  /* 판을 고칠 수 없는 상태면, 지난 실행이 번호 · 빌드를 이미 바꿔 놓은 경우(그 뒤에 멈춤)만 그대로 이어서 냅니다. */
  const editable = EDITABLE.includes(stateOf(ver));
  if (!editable && !(ver.attributes.versionString === opts.version && await buildIs(c, ver.id, p.build.id))) {
    log(`거절된 제출 ${sub.id}: 판 ${ver.attributes.versionString} 이 ${stateOf(ver)} — 새로 냅니다`);
    return null;
  }
  let items;
  try { items = await itemsOf(c, sub.id); } catch (e) { return soft(e, '제출 항목 읽기'); }
  if (!items.some(it => itemVer(it) === ver.id)) {
    log(`거절된 제출 ${sub.id} 에 판 ${ver.attributes.versionString} 이 없습니다 — 새로 냅니다`);
    return null;
  }
  log(`거절된 제출 ${sub.id} 를 취소하지 않고 같은 제출로 다시 냅니다`);
  if (editable) {
    try { await editVersion(c, opts, p, ver); } catch (e) { return soft(e, '판 번호 · 빌드 바꾸기'); }
  } else {
    log(`판 ${opts.version} · 빌드 ${opts.build} 는 이미 붙어 있음(${stateOf(ver)}) — 그대로 다시 냅니다`);
  }
  await addReviewNotes(c, opts, ver);
  try {
    for (const it of items) {
      if (((it.attributes || {}).state) !== 'REJECTED') continue;
      log(`거절된 항목 「고침」 표시: ${it.id}`);
      await c.call('PATCH', `/v1/reviewSubmissionItems/${it.id}`, {
        data: { type: 'reviewSubmissionItems', id: it.id, attributes: { resolved: true } },
      });
    }
  } catch (e) { return soft(e, '거절된 항목 「고침」 표시'); }
  try {
    await c.call('PATCH', `/v1/reviewSubmissions/${sub.id}`, {
      data: { type: 'reviewSubmissions', id: sub.id, attributes: { submitted: true } },
    });
  } catch (e) { return soft(e, '다시 제출'); }
  log(`앱스토어 다시 심사 요청 끝: 판 ${opts.version} (${opts.build}) · 같은 제출 ${sub.id}`);
  return { submissionId: sub.id, versionId: ver.id, resubmitted: true };
}

/** 걸려 있는 제출을 닫습니다. 대기 · 심사 중은 취소(canceled), 거절된 것(UNRESOLVED_ISSUES)은 애플이 취소를
 *  받지 않으므로(409 「not in cancellable state」) 거절된 항목을 뺍니다(removed — 애플 도움말: 항목을 다 빼면
 *  제출이 끝남). 닫은 제출의 id 들을 돌려줍니다. */
async function closeOpen(c, opts, p) {
  const log = opts.log;
  const closed = [];
  for (const s of p.subs) {
    const st = s.attributes.state;
    if (st === 'READY_FOR_REVIEW') continue;             // 아직 안 낸 것 — 아래에서 다시 씀
    if (st === 'UNRESOLVED_ISSUES') {
      try {
        const items = (await itemsOf(c, s.id)).filter(it => !['REMOVED', 'APPROVED', 'ACCEPTED'].includes((it.attributes || {}).state));
        log(`거절된 제출 정리: ${s.id} — 항목 ${items.length}개 빼기`);
        for (const it of items) {
          await c.call('PATCH', `/v1/reviewSubmissionItems/${it.id}`, {
            data: { type: 'reviewSubmissionItems', id: it.id, attributes: { removed: true } },
          });
        }
      } catch (e) {
        const d = appleDetail(e);
        throw new Error(`거절된 제출 ${s.id} 을 정리하지 못했습니다(${(e && e.status) || (e && e.message) || e}${d ? ' ' + d : ''}) — ` +
          `판 · 빌드 · 메모는 붙어 있을 수 있습니다. App Store Connect → 앱 심사에서 「Resubmit to App Review」 를 누르세요`);
      }
    } else {
      log(`심사 제출 취소: ${s.id} (${st})`);
      await c.call('PATCH', `/v1/reviewSubmissions/${s.id}`, {
        data: { type: 'reviewSubmissions', id: s.id, attributes: { canceled: true } },
      });
    }
    closed.push(s.id);
  }
  return closed;
}

/** 닫은 제출이 애플 쪽에서 정리(CANCELING · COMPLETING → COMPLETE)될 때까지 기다립니다 — 그 사이에는 새 제출 ·
 *  항목 넣기가 409 로 막힙니다. 시간 안에 안 끝나면 새 제출을 만들지 않고 멈춥니다. */
const STILL_OPEN = ['CANCELING', 'COMPLETING', 'WAITING_FOR_REVIEW', 'IN_REVIEW', 'UNRESOLVED_ISSUES'];
async function waitClosed(c, ids, opts) {
  const tries = opts.tries || 30;
  for (const id of ids) {
    for (let i = 0; ; i++) {
      let st = null;
      try { st = String(((((await c.call('GET', `/v1/reviewSubmissions/${id}`)) || {}).data || {}).attributes || {}).state || ''); }
      catch (e) { if (e.status !== 404) throw e; }
      if (!STILL_OPEN.includes(st)) break;
      if (i + 1 >= tries) throw new Error(`닫은 제출 ${id} 이 정리되지 않았습니다(${st}) — 새 제출을 만들지 않고 멈춥니다`);
      opts.log(`  제출 ${id} 정리를 기다립니다(${st}) (${i + 1}/${tries})`);
      await sleep(opts.waitMs || 10000, opts);
    }
  }
}

/** 안 낸 제출(READY_FOR_REVIEW)을 쓰거나 새로 만듭니다. 그래도 애플이 409 로 막으면 열릴 때까지
 *  기다립니다(같은 횟수 · 간격). */
async function draftSubmission(c, opts, appId) {
  const tries = opts.tries || 30;
  for (let i = 0; ; i++) {
    const left = (await openSubmissions(c, appId)).find(s => s.attributes.state === 'READY_FOR_REVIEW');
    if (left) return left.id;
    try {
      const r = await c.call('POST', '/v1/reviewSubmissions', {
        data: { type: 'reviewSubmissions', attributes: { platform: 'IOS' },
          relationships: { app: { data: { type: 'apps', id: appId } } } },
      });
      return r.data.id;
    } catch (e) {
      if (e.status !== 409 || i + 1 >= tries) throw e;
      opts.log(`  새 제출을 아직 못 만듭니다(409) — 기다립니다 (${i + 1}/${tries})`);
      await sleep(opts.waitMs || 10000, opts);
    }
  }
}

/** 제출에 판을 넣습니다. 409 는 「이미 들어 있음」 일 수도, 「아직 못 넣음」 일 수도 있어서 항목을 다시 읽어
 *  판이 정말 들어 있을 때만 넘어갑니다(빈 제출을 내지 않게). */
async function addItem(c, opts, subId, verId) {
  const tries = opts.tries || 30;
  for (let i = 0; ; i++) {
    try {
      await c.call('POST', '/v1/reviewSubmissionItems', {
        data: { type: 'reviewSubmissionItems', relationships: {
          reviewSubmission: { data: { type: 'reviewSubmissions', id: subId } },
          appStoreVersion: { data: { type: 'appStoreVersions', id: verId } } } },
      });
      return;
    } catch (e) {
      if (e.status !== 409) throw e;
      if ((await itemsOf(c, subId)).some(it => itemVer(it) === verId)) return;   // 이미 들어 있음
      if (i + 1 >= tries) throw e;
      opts.log(`  제출 ${subId} 에 판을 아직 못 넣습니다(409) — 기다립니다 (${i + 1}/${tries})`);
      await sleep(opts.waitMs || 10000, opts);
    }
  }
}

async function submitAppStore(c, opts, p) {
  const log = opts.log;
  if (!p.build) throw new Error(`빌드 ${opts.version} (${opts.build}) 를 못 찾았습니다 — TestFlight 처리가 끝났는지 보세요`);
  const bstate = p.build.attributes.processingState;
  if (bstate !== 'VALID') throw new Error(`빌드 처리 상태가 ${bstate} 입니다 — VALID 가 된 뒤 다시`);

  /* 이미 이 판 · 이 빌드로 심사 대기 · 심사 중이면 아무것도 안 바꿉니다 — 응답을 못 받은 실행을 다시 돌려도
     멀쩡한 제출을 취소하지 않게. */
  const t = p.target;
  if (t && t.attributes.versionString === opts.version && ['WAITING_FOR_REVIEW', 'IN_REVIEW'].includes(stateOf(t)) &&
      await buildIs(c, t.id, p.build.id)) {
    const s = p.subs.find(x => ['WAITING_FOR_REVIEW', 'IN_REVIEW'].includes(x.attributes.state));
    log(`이미 판 ${opts.version} (${opts.build}) 로 ${stateOf(t)} — 아무것도 바꾸지 않습니다`);
    return { submissionId: s ? s.id : null, versionId: t.id, already: true };
  }

  /* 0. 거절된 제출 하나만 걸려 있으면 같은 제출로 다시 냅니다(머리말). 안 되면 아래로. */
  const unresolved = p.subs.filter(s => s.attributes.state === 'UNRESOLVED_ISSUES');
  const busy = p.subs.filter(s => !['READY_FOR_REVIEW', 'UNRESOLVED_ISSUES'].includes(s.attributes.state));
  if (t && unresolved.length === 1 && !busy.length) {
    const done = await resubmitUnresolved(c, opts, p, unresolved[0]);
    if (done) return done;
  }

  /* 1. 걸려 있는 제출을 닫고(취소 · 거절된 항목 빼기), 애플 쪽 정리가 끝날 때까지 기다립니다. */
  const closed = await closeOpen(c, opts, p);
  await waitClosed(c, closed, opts);

  /* 2. 판을 고칠 수 있게 되면 번호 · 빌드를 바꿉니다. */
  let ver = t;
  if (!ver) {
    log(`새 판 ${opts.version} 를 만듭니다`);
    const r = await c.call('POST', '/v1/appStoreVersions', {
      data: { type: 'appStoreVersions', attributes: { platform: 'IOS', versionString: opts.version },
        relationships: { app: { data: { type: 'apps', id: p.app.id } } } },
    });
    ver = r.data;
  } else {
    await waitEditable(c, ver.id, opts);
  }
  /* 같은 제출로 다시 내려다 넘어온 경우 번호 · 빌드는 이미 바뀌어 있을 수 있습니다 — 그대로 다시 붙여도 무해. */
  await editVersion(c, opts, p, ver);
  await addReviewNotes(c, opts, ver);

  /* 3. 새 심사 제출 — 안 낸 것이 남아 있으면 그것을 씁니다(애플은 앱마다 열린 제출을 하나만 허락). */
  const subId = await draftSubmission(c, opts, p.app.id);
  await addItem(c, opts, subId, ver.id);
  await c.call('PATCH', `/v1/reviewSubmissions/${subId}`, {
    data: { type: 'reviewSubmissions', id: subId, attributes: { submitted: true } },
  });
  log(`앱스토어 심사 제출 끝: 판 ${opts.version} (${opts.build}) · 제출 ${subId}`);
  return { submissionId: subId, versionId: ver.id };
}

async function submitBeta(c, opts, p) {
  const log = opts.log;
  if (!p.build || p.build.attributes.processingState !== 'VALID') {
    throw new Error('베타 심사: 빌드가 없거나 처리 중입니다');
  }
  const r = await c.call('GET',
    `/v1/betaGroups?filter[app]=${p.app.id}&filter[name]=${encodeURIComponent(opts.beta)}&limit=5`);
  const g = (r.data || []).find(x => x.attributes && x.attributes.name === opts.beta);
  if (!g) throw new Error(`TestFlight 그룹 「${opts.beta}」 이 없습니다`);
  if (g.attributes.isInternalGroup) throw new Error(`「${opts.beta}」 는 내부 그룹입니다 — 베타 심사가 필요 없습니다`);

  const inGroup = (await c.call('GET', `/v1/betaGroups/${g.id}/builds?limit=50`)).data || [];
  if (!inGroup.some(b => b.id === p.build.id)) {
    log(`「${opts.beta}」 에 빌드 넣기: ${opts.version} (${opts.build})`);
    await c.call('POST', `/v1/betaGroups/${g.id}/relationships/builds`, {
      data: [{ type: 'builds', id: p.build.id }],
    });
  }
  if (opts.whatsNew) {
    const locs = (await c.call('GET', `/v1/builds/${p.build.id}/betaBuildLocalizations?limit=20`)).data || [];
    const ko = locs.find(l => /^ko/.test(l.attributes.locale || ''));
    if (ko) {
      await c.call('PATCH', `/v1/betaBuildLocalizations/${ko.id}`, {
        data: { type: 'betaBuildLocalizations', id: ko.id, attributes: { whatsNew: opts.whatsNew } },
      });
    } else {
      await c.call('POST', '/v1/betaBuildLocalizations', {
        data: { type: 'betaBuildLocalizations', attributes: { locale: 'ko', whatsNew: opts.whatsNew },
          relationships: { build: { data: { type: 'builds', id: p.build.id } } } },
      });
    }
  }
  /* 이미 심사에 들어간 빌드를 다시 내면 애플은 409 가 아니라 422 INVALID_QC_STATE 로 거절합니다
     (9/28 — 「테스트할 내용」 만 고치려고 다시 돌렸을 때). 상태를 먼저 보고 넘어갑니다. */
  const st = p.beta || await betaState(c, p.build.id);
  if (['WAITING_FOR_REVIEW', 'IN_REVIEW', 'APPROVED'].includes(st.review)) {
    log(`베타 심사: 이 빌드는 이미 ${st.review} — 다시 내지 않습니다`);
  } else try {
    await c.call('POST', '/v1/betaAppReviewSubmissions', {
      data: { type: 'betaAppReviewSubmissions',
        relationships: { build: { data: { type: 'builds', id: p.build.id } } } },
    });
    log(`베타 심사 제출 끝: ${opts.version} (${opts.build}) → 「${opts.beta}」`);
  } catch (e) {
    if (e.status !== 409) throw e;
    log('베타 심사: 이 빌드는 이미 제출돼 있습니다(409) — 그대로 둡니다');
  }
  /* 옛 빌드 빼기는 맨 끝에, 실패해도 멈추지 않습니다 — 새 빌드의 베타 심사가 먼저입니다. */
  if (opts.dropOldBeta) {
    const old = inGroup.filter(b => b.id !== p.build.id);
    if (old.length) {
      log(`「${opts.beta}」 에서 옛 빌드 ${old.length}개 빼기`);
      try {
        await c.call('DELETE', `/v1/betaGroups/${g.id}/relationships/builds`, {
          data: old.map(b => ({ type: 'builds', id: b.id })),
        });
      } catch (e) {
        log(`::warning::옛 빌드를 못 뺐습니다 (${e.status || ''}) — 새 빌드는 그룹에 들어가 있습니다`);
      }
    }
  }
}

function describe(p, opts) {
  const lines = [];
  lines.push(`앱: ${p.app.attributes.name} (${p.app.id})`);
  for (const v of p.versions) lines.push(`  판 ${v.attributes.versionString} — ${stateOf(v)}`);
  lines.push(`열린 심사 제출: ${p.subs.length ? p.subs.map(s => `${s.id} ${s.attributes.state}`).join(', ') : '없음'}`);
  lines.push(p.build
    ? `빌드 ${opts.version} (${opts.build}): ${p.build.attributes.processingState} · 암호화 ${p.build.attributes.usesNonExemptEncryption}`
    : `빌드 ${opts.version} (${opts.build}): 없음`);
  lines.push(p.target
    ? `고칠 판: ${p.target.attributes.versionString} (${stateOf(p.target)}) → ${opts.version}`
    : `고칠 판 없음 → 새 판 ${opts.version} 를 만듦`);
  return lines.join('\n');
}

/** 이 빌드의 베타 심사(betaReviewState: WAITING_FOR_REVIEW · IN_REVIEW · APPROVED · REJECTED)와
 *  외부 테스트 상태(externalBuildState: READY_FOR_BETA_TESTING · IN_BETA_TESTING …). 못 읽으면 null. */
async function betaState(c, buildId) {
  const out = { review: null, external: null };
  try {
    const r = await c.call('GET', `/v1/betaAppReviewSubmissions?filter[build]=${encodeURIComponent(buildId)}&limit=1`);
    const d = (r && r.data || [])[0];
    out.review = d && d.attributes ? String(d.attributes.betaReviewState || '') || null : null;
  } catch (e) { /* 모름 */ }
  try {
    const r = await c.call('GET', `/v1/builds/${encodeURIComponent(buildId)}/buildBetaDetail`);
    const a = r && r.data && r.data.attributes;
    out.external = a ? String(a.externalBuildState || '') || null : null;
  } catch (e) { /* 모름 */ }
  return out;
}

/** TestFlight 공개 링크 — 읽거나(기본) 켭니다(--submit). 판 · 빌드와 상관없습니다. */
async function publicLink(c, opts) {
  const log = opts.log;
  const app = await findApp(c, opts.bundleId);
  const r = await c.call('GET',
    `/v1/betaGroups?filter[app]=${app.id}&filter[name]=${encodeURIComponent(opts.beta)}&limit=5`);
  const g = (r.data || []).find(x => x.attributes && x.attributes.name === opts.beta);
  if (!g) throw new Error(`TestFlight 그룹 「${opts.beta}」 이 없습니다`);
  if (g.attributes.isInternalGroup) throw new Error(`「${opts.beta}」 는 내부 그룹입니다 — 공개 링크가 없습니다`);
  let a = g.attributes;
  /* --link-off: 공개 링크를 닫습니다(주인 결정 9/28 — 계정 섞임 버그가 있는 옛 판을 새 사람이 받지 않게,
     고친 판이 승인될 때까지). 이미 들어온 테스터는 그대로입니다. 다시 열 때는 --link-only --submit. */
  if (opts.linkOff) {
    if (a.publicLinkEnabled && opts.submit) {
      log(`「${opts.beta}」 공개 링크를 닫습니다`);
      const u = await c.call('PATCH', `/v1/betaGroups/${g.id}`, {
        data: { type: 'betaGroups', id: g.id, attributes: { publicLinkEnabled: false } },
      });
      a = (u && u.data && u.data.attributes) || Object.assign({}, a, { publicLinkEnabled: false });
    }
    log(a.publicLinkEnabled ? '공개 링크: 열림 (--submit 으로 닫습니다)' : '공개 링크: 닫힘');
    return { enabled: !!a.publicLinkEnabled, link: a.publicLinkEnabled ? a.publicLink || null : null };
  }
  if (!a.publicLinkEnabled && opts.submit) {
    log(`「${opts.beta}」 공개 링크를 켭니다`);
    const u = await c.call('PATCH', `/v1/betaGroups/${g.id}`, {
      data: { type: 'betaGroups', id: g.id,
        attributes: { publicLinkEnabled: true, publicLinkLimitEnabled: false } },
    });
    a = (u && u.data && u.data.attributes) || a;
    /* 응답에 주소가 없으면 한 번 더 읽습니다 — 켠 직후에 만들어지는 칸입니다. */
    if (!a.publicLink) a = ((await c.call('GET', `/v1/betaGroups/${g.id}`)).data || {}).attributes || a;
  }
  log(a.publicLinkEnabled
    ? `공개 링크: ${a.publicLink || '(주소 아직 없음 — 잠시 뒤 다시 읽기)'}`
    : '공개 링크: 꺼짐' + (opts.submit ? '' : ' (--submit 으로 켭니다)'));
  return { enabled: !!a.publicLinkEnabled, link: a.publicLink || null };
}

/** GET 한 번 → JSON. 전체 시간 제한(ms)이 있습니다 — 소켓 idle 제한만 걸면 느리게 조금씩 오는 응답에
 *  끝없이 매달립니다. agent:false 는 keep-alive 소켓이 남아 CLI 가 늦게 끝나는 일을 막으려고.
 *  get 은 시험이 가짜 전송(조금씩 오는 응답 · 403 등)을 넣는 자리입니다 — 평소에는 https.get. */
function getJson(url, ms, get = https.get) {
  return new Promise((resolve, reject) => {
    let done = false, t = null;
    const finish = (e, v) => {
      if (done) return;
      done = true; clearTimeout(t);
      if (e) reject(e); else resolve(v);
    };
    const req = get(url, { agent: false, headers: { accept: 'application/json' } }, res => {
      if (res.statusCode !== 200) { res.resume(); finish(new Error(`HTTP ${res.statusCode}`)); return; }
      let buf = '';
      res.setEncoding('utf8');
      res.on('data', d => { buf += d; });
      res.on('error', finish);
      res.on('end', () => {
        let j;
        try { j = JSON.parse(buf); } catch (e) { finish(new Error('JSON 이 아닌 응답')); return; }
        finish(null, j);
      });
    });
    t = setTimeout(() => { finish(new Error(`${ms / 1000}초 안에 응답 없음`)); req.destroy(); }, ms);
    req.on('error', finish);
  });
}

/** 앱스토어 페이지가 바깥(로그인 없는 사람)에게 보이는지 — iTunes lookup, 읽기만. 무슨 일이 있어도
 *  던지지 않습니다: 이 줄은 참고용이고, 이것 때문에 출시 요청이나 읽기가 멈추면 안 됩니다. */
async function storeCheck(appId, opts, deps) {
  const log = opts.log;
  const get = deps.lookup || getJson;
  let j;
  try {
    j = await get(`${LOOKUP}?id=${encodeURIComponent(appId)}&country=kr`, LOOKUP_MS);
    if (!j || typeof j !== 'object' || typeof j.resultCount !== 'number') throw new Error('resultCount 없는 응답');
  } catch (e) {
    const why = String((e && (e.code || e.message)) || e).replace(/\s+/g, ' ').slice(0, 120);
    log(`앱스토어 페이지: 확인 못 함(${why})`);
    return { visible: null, error: why };
  }
  if (j.resultCount >= 1) {
    const r = (Array.isArray(j.results) && j.results[0]) || {};
    const version = r.version ? String(r.version) : '?';
    log(`앱스토어 페이지: 공개됨 (판 ${version})`);
    return { visible: true, version };
  }
  log('앱스토어 페이지: 아직 안 보임');
  return { visible: false };
}

/** --release: 심사 통과(PENDING_DEVELOPER_RELEASE)한 판을 출시합니다. 판 하나만 읽고 그 판에만
 *  출시 요청을 보냅니다 — 심사 제출 · 베타 · 공개 링크 쪽 주소는 부르지도 않습니다. */
async function releaseVersion(c, opts, deps) {
  const log = opts.log;
  const app = await findApp(c, opts.bundleId);
  const ver = (await versionsOf(c, app.id)).find(v => v.attributes && v.attributes.versionString === opts.version);
  if (!ver) throw new Error(`앱스토어에 판 ${opts.version} 이 없습니다 — 판 번호를 확인하세요`);
  const ss = statesOf(ver);
  const shown = ss.join(' / ') || '모름';
  log(`앱: ${app.attributes.name} (${app.id})`);
  log(`판 ${opts.version} — ${shown}`);
  const store = await storeCheck(app.id, opts, deps);
  const out = (action, extra) => ({ release: Object.assign({ versionId: ver.id, state: shown, action }, extra), store });

  /* 이미 출시가 시작됐으면 다시 보내지 않습니다 — 두 번 보내면 애플이 409 로 거절하고, 한 시간마다
     도는 호출이 빨간 불이 됩니다. 두 칸이 잠깐 다를 때(한쪽만 PROCESSING…)도 출시된 쪽을 믿습니다. */
  if (ss.some(s => LIVE.includes(s))) {
    log('이미 출시됨 — 출시 요청을 다시 보내지 않습니다');
    return out('already');
  }
  /* 한 칸만 PENDING_DEVELOPER_RELEASE 이고 다른 칸이 다른 말을 하면(웹에서 판을 뺐는데 한 칸이 아직
     안 따라왔을 때 등) 보내지 않습니다 — 두 칸 모두 같은 이름이라 맞을 때까지 기다려도 잃는 것이 없습니다. */
  if (ss.includes(RELEASABLE) && ss.length > 1) {
    log(`두 칸이 다름(${shown}) — 출시하지 않고 다음 실행에 다시 봅니다`);
    return out('waiting');
  }
  /* 심사에서 빠졌으면 기다려도 오지 않습니다 — 사람이 고쳐서 다시 내야 하니 실패(1)로 알립니다. */
  if (ss.some(s => DEAD.includes(s))) {
    const m = `심사에서 빠짐(${shown}) — 출시하지 않음. 고쳐서 다시 제출해야 합니다`;
    log(m);
    throw new Error(m);
  }
  /* 승인 전은 실패가 아니라 「아직」 입니다 — 0 으로 끝나서 반복 호출이 무해하게. */
  if (!ss.includes(RELEASABLE)) {
    log(ss.some(s => PAST_REVIEW.includes(s))
      ? `출시 요청을 받는 상태가 아님(${shown}) — 출시하지 않음`
      : `아직 승인 전(${shown}) — 출시하지 않음`);
    return out('waiting');
  }
  if (!opts.submit) {
    log(`심사 통과 — --submit 이면 판 ${opts.version} 출시 요청을 보냅니다`);
    log('읽기만 했습니다(--submit 없음).');
    return out('ready');
  }
  try {
    await c.call('POST', '/v1/appStoreVersionReleaseRequests', {
      data: { type: 'appStoreVersionReleaseRequests',
        relationships: { appStoreVersion: { data: { type: 'appStoreVersions', id: ver.id } } } },
    });
  } catch (e) {
    if (e.status !== 409 && e.status !== 422) throw e;
    /* 거절이면 판을 다시 읽습니다 — 읽은 뒤 · 보내기 전 사이에 (웹에서 누르는 등) 출시가 시작됐으면
       바라던 결과이니 성공입니다. 아니면 사람이 봐야 하니 멈춥니다(계약 · 세금 미비 등). */
    let now = [];
    try { now = statesOf((await c.call('GET', `/v1/appStoreVersions/${ver.id}`)).data); } catch (e2) { /* 모름 */ }
    if (now.some(s => LIVE.includes(s))) {
      log(`이미 출시됨 — 출시 요청은 ${e.status} 로 거절됐지만 판이 ${now.join(' / ')} 입니다`);
      return out('already', { state: now.join(' / ') });
    }
    const detail = appleDetail(e);
    const msg = `출시 요청을 애플이 받지 않았습니다(${e.status}${detail ? ' ' + detail : ''}) — ` +
      `판 ${opts.version} 은 ${now.join(' / ') || '상태 모름'} 그대로입니다. App Store Connect 에서 확인하세요`;
    log(msg);
    throw new Error(msg);
  }
  log(`출시 요청 보냄: 판 ${opts.version} — 앱스토어 페이지가 뜨기까지 몇 시간 걸릴 수 있습니다`);
  return out('requested');
}

async function run(argv, env, deps = {}) {
  const log = deps.log || (s => console.log(s));
  const opts = {
    bundleId: env.ASC_BUNDLE_ID || 'io.github.iacobuschoi.mybody',
    version: arg(argv, '--version'),
    build: arg(argv, '--build'),
    beta: arg(argv, '--beta', ''),
    whatsNew: arg(argv, '--whats-new', ''),
    dropOldBeta: has(argv, '--drop-old-beta'),
    submit: has(argv, '--submit'),
    linkOff: has(argv, '--link-off'),
    appStore: !has(argv, '--beta-only'),
    log, noWait: deps.noWait, waitMs: deps.waitMs, tries: deps.tries,
  };
  const client = () => deps.client || asc.client({
    keyId: String(env.ASC_KEY_ID || '').trim(), issuerId: String(env.ASC_ISSUER_ID || '').trim(),
    pem: asc.loadKeyPem(env),
  });
  /* --release 는 따로 갑니다(--link-only 처럼 여기서 끝남) — 아래의 취소 · 재제출 · 베타 길을 절대 안 탐. */
  if (has(argv, '--release')) {
    if (has(argv, '--link-only')) throw new Error('--release 와 --link-only 는 함께 쓸 수 없습니다');
    if (!/^\d+\.\d+\.\d+$/.test(opts.version || '')) throw new Error('--release 에는 --version 0.2.20 같은 판 번호가 필요합니다');
    return releaseVersion(client(), opts, deps);
  }
  if (has(argv, '--link-only')) {
    if (!opts.beta) throw new Error('--link-only 에는 --beta 그룹이름이 필요합니다');
    return { link: await publicLink(client(), opts) };
  }
  if (!/^\d+\.\d+\.\d+$/.test(opts.version || '')) throw new Error('--version 0.2.15 같은 판 번호가 필요합니다');
  if (!/^\d+$/.test(opts.build || '')) throw new Error('--build 298 같은 빌드 번호가 필요합니다');
  /* 심사 메모 파일 — 바꾸기 전에 먼저 읽고 검사합니다(못 읽으면 아무것도 안 바꾸고 멈춤). */
  const notesFile = arg(argv, '--review-notes-file', '');
  if (has(argv, '--review-notes-file') && !notesFile) throw new Error('--review-notes-file 에는 파일 경로가 필요합니다');
  if (notesFile) {
    const text = String((deps.readFile || (f => fs.readFileSync(f, 'utf8')))(notesFile)).replace(/\r\n/g, '\n').trim();
    if (!text) throw new Error(`심사 메모 파일이 비어 있습니다: ${notesFile}`);
    if (text.length > NOTES_MAX) throw new Error(`심사 메모가 ${text.length}자입니다(한도 ${NOTES_MAX})`);
    opts.reviewNotes = text;
  }
  const c = client();
  const p = await plan(c, opts);
  log(describe(p, opts));
  /* 베타 심사 상태 — 읽기만 · 실패해도 멈추지 않습니다. 주인 결정(9/28): friends 베타가 승인되면
     안드로이드 비공개 테스트를 시작합니다 — 그 신호를 여기서 읽습니다. */
  if (p.build) {
    const beta = await betaState(c, p.build.id);
    p.beta = beta;
    log(`베타 심사: ${beta.review || '모름'} · 외부 테스트 빌드 상태: ${beta.external || '모름'}`);
  }
  if (!opts.submit) {
    /* 앱스토어 페이지가 바깥에 보이는지 — 읽기만 · 못 읽어도 멈추지 않습니다(머리말 「앱스토어 페이지」).
       --submit 길(취소 · 재제출)에는 넣지 않습니다 — 그 길은 바깥 요청 하나 없이 전과 같게. */
    p.store = await storeCheck(p.app.id, opts, deps);
    /* 심사 메모가 붙을 수 있는지 미리 — 원래 메모는 읽기만 하고 길이만 찍습니다(내용 · 계정은 안 찍음). */
    if (opts.reviewNotes) {
      let how = `새 ${opts.reviewNotes.length}자`;
      if (p.target) {
        try {
          const m = await notesPlan(c, opts, p.target);
          how = m.already ? '이미 들어 있음'
            : `원래 ${m.old.length}자 + 새 ${opts.reviewNotes.length}자 = ${m.notes.length}/${NOTES_MAX}` +
              (m.notes.length > NOTES_MAX ? ' — 넘침(제출하면 멈춤)' : '');
        } catch (e) {
          how += ` · 원래 메모 확인 못 함(${(e && e.status) || '응답 없음'})`;
        }
      }
      log(`심사 메모: ${notesFile} — ${how} · --submit 이면 덧붙입니다`);
    }
    log('읽기만 했습니다(--submit 없음).');
    return { plan: p, submitted: false };
  }
  let out = {};
  if (opts.appStore) out = await submitAppStore(c, opts, p);
  if (opts.beta) await submitBeta(c, opts, p);
  return { plan: p, submitted: true, ...out };
}

if (require.main === module) {
  run(process.argv.slice(2), process.env).catch(e => {
    console.error(`::error::${String((e && e.message) || e).replace(/\s+/g, ' ').slice(0, 500)}`);
    process.exit(1);
  });
}

module.exports = { run, plan, publicLink, betaState, stateOf, statesOf, storeCheck, getJson, releaseVersion,
  EDITABLE, OPEN_REVIEW, RELEASABLE, LIVE, DEAD };
