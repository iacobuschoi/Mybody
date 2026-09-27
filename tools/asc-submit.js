#!/usr/bin/env node
/* =============================================================================
 * tools/asc-submit.js — 앱스토어 심사 · TestFlight 베타 심사를 API 로 다시 올리기 (웹 로그인 없이)
 *
 *   node tools/asc-submit.js --version 0.2.15 --build 298 [--beta friends] [--drop-old-beta]
 *                            [--submit] [--whats-new "…"]
 *
 *   node tools/asc-submit.js --link-only --beta friends [--submit]
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
 *   2. 걸려 있는 심사 제출(reviewSubmissions: 대기 · 심사 중 · 문제 있음)을 취소하고, 판(appStoreVersion)이
 *      고칠 수 있는 상태가 될 때까지 기다립니다(취소는 애플 쪽에서 몇 초~몇 분 걸림).
 *   3. 아직 출시된 적 없는 판이면 그 판의 번호를 새 번호로 바꿉니다(0.2.8 → 0.2.15). 심사 정보(데모 계정 ·
 *      메모) · 설명 · 스크린샷은 그 판에 붙어 있으니 그대로 따라옵니다. 이미 출시된 판뿐이면 새 판을 만듭니다.
 *   4. 빌드(버전 + 빌드 번호, 처리 완료)를 그 판에 붙이고, 새 심사 제출을 만들어 판을 넣고 제출합니다.
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
 *
 * 멈추는 자리
 *   빌드가 없거나 처리 중이면(processingState ≠ VALID) 아무것도 바꾸지 않고 멈춥니다. 취소한 뒤 판이
 *   고칠 수 있는 상태로 안 바뀌면(시간 초과) 새 제출을 만들지 않고 멈춥니다 — 반쯤 된 상태로 두지 않으려고
 *   **바꾸기 전에 확인할 수 있는 것은 전부 먼저 확인**합니다.
 * ========================================================================== */
'use strict';
const asc = require('./asc.js');

const OPEN_REVIEW = ['WAITING_FOR_REVIEW', 'IN_REVIEW', 'UNRESOLVED_ISSUES', 'READY_FOR_REVIEW'];
/* 판의 상태 중 번호 · 빌드를 바꿀 수 있는 것. */
const EDITABLE = ['PREPARE_FOR_SUBMISSION', 'DEVELOPER_REJECTED', 'REJECTED', 'METADATA_REJECTED',
  'INVALID_BINARY'];
const RELEASED = ['READY_FOR_SALE', 'READY_FOR_DISTRIBUTION', 'PROCESSING_FOR_DISTRIBUTION',
  'PENDING_APPLE_RELEASE', 'PENDING_DEVELOPER_RELEASE', 'REPLACED_WITH_NEW_VERSION', 'REMOVED_FROM_SALE',
  'DEVELOPER_REMOVED_FROM_SALE'];

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

async function submitAppStore(c, opts, p) {
  const log = opts.log;
  if (!p.build) throw new Error(`빌드 ${opts.version} (${opts.build}) 를 못 찾았습니다 — TestFlight 처리가 끝났는지 보세요`);
  const bstate = p.build.attributes.processingState;
  if (bstate !== 'VALID') throw new Error(`빌드 처리 상태가 ${bstate} 입니다 — VALID 가 된 뒤 다시`);

  /* 1. 걸려 있는 제출을 취소합니다. */
  for (const s of p.subs) {
    const st = s.attributes.state;
    if (st === 'READY_FOR_REVIEW') continue;             // 아직 안 낸 것 — 아래에서 다시 씀
    log(`심사 제출 취소: ${s.id} (${st})`);
    await c.call('PATCH', `/v1/reviewSubmissions/${s.id}`, {
      data: { type: 'reviewSubmissions', id: s.id, attributes: { canceled: true } },
    });
  }

  /* 2. 판을 고칠 수 있게 되면 번호 · 빌드를 바꿉니다. */
  let ver = p.target;
  if (!ver) {
    log(`새 판 ${opts.version} 를 만듭니다`);
    const r = await c.call('POST', '/v1/appStoreVersions', {
      data: { type: 'appStoreVersions', attributes: { platform: 'IOS', versionString: opts.version },
        relationships: { app: { data: { type: 'apps', id: p.app.id } } } },
    });
    ver = r.data;
  } else {
    await waitEditable(c, ver.id, opts);
    if (ver.attributes.versionString !== opts.version) {
      log(`판 번호 바꾸기: ${ver.attributes.versionString} → ${opts.version}`);
      await c.call('PATCH', `/v1/appStoreVersions/${ver.id}`, {
        data: { type: 'appStoreVersions', id: ver.id, attributes: { versionString: opts.version } },
      });
    }
  }
  log(`빌드 붙이기: ${opts.version} (${opts.build})`);
  await c.call('PATCH', `/v1/appStoreVersions/${ver.id}/relationships/build`, {
    data: { type: 'builds', id: p.build.id },
  });

  /* 3. 새 심사 제출 — 안 낸 것이 남아 있으면 그것을 씁니다(애플은 앱마다 열린 제출을 하나만 허락). */
  const left = (await openSubmissions(c, p.app.id)).find(s => s.attributes.state === 'READY_FOR_REVIEW');
  let subId = left && left.id;
  if (!subId) {
    const r = await c.call('POST', '/v1/reviewSubmissions', {
      data: { type: 'reviewSubmissions', attributes: { platform: 'IOS' },
        relationships: { app: { data: { type: 'apps', id: p.app.id } } } },
    });
    subId = r.data.id;
  }
  try {
    await c.call('POST', '/v1/reviewSubmissionItems', {
      data: { type: 'reviewSubmissionItems', relationships: {
        reviewSubmission: { data: { type: 'reviewSubmissions', id: subId } },
        appStoreVersion: { data: { type: 'appStoreVersions', id: ver.id } } } },
    });
  } catch (e) {
    if (e.status !== 409) throw e;                       // 이미 들어 있음
  }
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
  try {
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
    appStore: !has(argv, '--beta-only'),
    log, noWait: deps.noWait, waitMs: deps.waitMs, tries: deps.tries,
  };
  const client = () => deps.client || asc.client({
    keyId: String(env.ASC_KEY_ID || '').trim(), issuerId: String(env.ASC_ISSUER_ID || '').trim(),
    pem: asc.loadKeyPem(env),
  });
  if (has(argv, '--link-only')) {
    if (!opts.beta) throw new Error('--link-only 에는 --beta 그룹이름이 필요합니다');
    return { link: await publicLink(client(), opts) };
  }
  if (!/^\d+\.\d+\.\d+$/.test(opts.version || '')) throw new Error('--version 0.2.15 같은 판 번호가 필요합니다');
  if (!/^\d+$/.test(opts.build || '')) throw new Error('--build 298 같은 빌드 번호가 필요합니다');
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

module.exports = { run, plan, publicLink, betaState, stateOf, EDITABLE, OPEN_REVIEW };
