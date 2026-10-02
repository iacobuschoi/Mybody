#!/usr/bin/env node
/* =============================================================================
 * tools/test-asc-submit.js — tools/asc-submit.js 를 가짜 App Store Connect 로 시험
 *
 *   node tools/test-asc-submit.js
 *
 * 가짜는 애플의 규칙 몇 가지를 흉내 냅니다: 심사 대기 중인 판은 고칠 수 없고(409), 취소하면
 * 한 번 물어본 뒤에야 DEVELOPER_REJECTED 가 되고, 앱마다 안 낸 제출은 하나만 열 수 있습니다.
 * 출시 요청은 PENDING_DEVELOPER_RELEASE 인 판만 받고(아니면 409), 받으면 PROCESSING_FOR_APP_STORE
 * (새 칸은 PROCESSING_FOR_DISTRIBUTION)가 됩니다. 판에는 두 칸을 따로 · 함께 적을 수 있습니다(relFake).
 * 앱스토어 페이지(iTunes lookup)는 가짜 함수로 바꿔 넣습니다 — 시험이 바깥 네트워크를 타지 않게.
 * ========================================================================== */
'use strict';
const net = require('net');
const { EventEmitter } = require('events');
const { run, getJson } = require('./asc-submit.js');

let pass = 0, fail = 0;
function ok(cond, name) {
  if (cond) { pass++; console.log('  ✓ ' + name); } else { fail++; console.log('  ✗ ' + name); }
}

function fake(opts = {}) {
  const st = {
    app: { id: 'app1', type: 'apps', attributes: { name: 'MyBody', bundleId: 'io.github.iacobuschoi.mybody' } },
    versions: opts.versions || [{ id: 'v1', type: 'appStoreVersions',
      attributes: { versionString: '0.2.8', appStoreState: opts.verState || 'WAITING_FOR_REVIEW' } }],
    subs: opts.noSub ? [] : [{ id: 's1', type: 'reviewSubmissions', attributes: { state: opts.subState || 'WAITING_FOR_REVIEW' } }],
    builds: opts.noBuild ? [] : [{ id: 'b298', type: 'builds',
      attributes: { version: '298', processingState: opts.buildState || 'VALID', usesNonExemptEncryption: false } }],
    groups: [{ id: 'g1', type: 'betaGroups', attributes: { name: 'friends', isInternalGroup: false } }],
    groupBuilds: { g1: [{ id: 'b269', type: 'builds' }] },
    locs: [],
    betaSubs: [],
    items: (opts.items || []).map(i => Object.assign({}, i)),
    reviewDetail: opts.reviewDetail === undefined ? null : opts.reviewDetail,
    releases: [],
    calls: [],
    cancelPending: 0,
    postBusy: 0,
    itemBusy: 0,
  };
  const err = (status, msg, code) => {
    const e = new Error(msg); e.status = status;
    if (code) e.errors = [{ status: String(status), code, detail: msg }];
    throw e;
  };
  /* 판을 고칠 수 있는가 — 애플처럼 거절된 판(REJECTED)도 고칠 수 있고, lockWhileUnresolved 면
     거절된 제출이 열려 있는 동안은 막습니다(그 길이 막힌 애플을 흉내). */
  const editable = v => ['PREPARE_FOR_SUBMISSION', 'DEVELOPER_REJECTED', 'REJECTED'].includes(v.attributes.appStoreState) &&
    !(opts.lockWhileUnresolved && st.subs.some(s => s.attributes.state === 'UNRESOLVED_ISSUES'));
  /* 진짜 API 처럼 응답은 늘 새 사본 — 스크립트가 받은 객체를 고쳐도 가짜 쪽 상태가 따라 바뀌지 않게. */
  async function call(method, p, body) {
    const r = await raw(method, p, body);
    return r == null ? r : JSON.parse(JSON.stringify(r));
  }
  async function raw(method, p, body) {
    st.calls.push(`${method} ${p.split('?')[0]}`);
    const path = p.split('?')[0];
    if (method === 'GET' && path === '/v1/apps') return { data: [st.app] };
    if (method === 'GET' && path === '/v1/apps/app1/appStoreVersions') return { data: st.versions };
    if (method === 'GET' && path === '/v1/reviewSubmissions') {
      return { data: st.subs.filter(s => ['WAITING_FOR_REVIEW', 'IN_REVIEW', 'UNRESOLVED_ISSUES', 'READY_FOR_REVIEW'].includes(s.attributes.state)) };
    }
    if (method === 'GET' && path === '/v1/builds') return { data: st.builds };
    const vm = path.match(/^\/v1\/appStoreVersions\/(\w+)$/);
    if (vm && method === 'GET') {
      const v = st.versions.find(x => x.id === vm[1]);
      if (st.cancelPending > 0) { st.cancelPending--; if (st.cancelPending === 0) v.attributes.appStoreState = 'DEVELOPER_REJECTED'; }
      return { data: v };
    }
    if (vm && method === 'PATCH') {
      const v = st.versions.find(x => x.id === vm[1]);
      if (!editable(v)) err(409, '판을 고칠 수 없음', 'STATE_ERROR');
      Object.assign(v.attributes, body.data.attributes);
      return { data: v };
    }
    const vb = path.match(/^\/v1\/appStoreVersions\/(\w+)\/relationships\/build$/);
    if (vb && method === 'PATCH') {
      const v = st.versions.find(x => x.id === vb[1]);
      if (!editable(v)) err(409, '빌드를 바꿀 수 없음', 'STATE_ERROR');
      v.build = body.data.id;
      return null;
    }
    const sm = path.match(/^\/v1\/reviewSubmissions\/(\w+)$/);
    if (sm && method === 'GET') {
      const s = st.subs.find(x => x.id === sm[1]);
      if (!s) err(404, '없는 제출');
      if (['CANCELING', 'COMPLETING'].includes(s.attributes.state) && !opts.neverClose && --s.closePolls <= 0) {
        s.attributes.state = 'COMPLETE';
      }
      return { data: s };
    }
    if (sm && method === 'PATCH') {
      const s = st.subs.find(x => x.id === sm[1]);
      if (body.data.attributes.canceled) {
        /* 애플은 거절된 제출(UNRESOLVED_ISSUES)의 취소를 받지 않습니다 — 항목을 빼야 끝남. */
        if (s.attributes.state === 'UNRESOLVED_ISSUES') err(409, 'Resource is not in cancellable state', 'STATE_ERROR');
        s.attributes.state = 'CANCELING'; st.cancelPending = opts.cancelPolls || 2; s.closePolls = opts.closePolls || 1;
      }
      if (body.data.attributes.submitted) {
        if (!st.items.some(i => i.sub === s.id)) err(409, '빈 제출');
        if (opts.noResubmit && s.attributes.state === 'UNRESOLVED_ISSUES') err(422, '다시 낼 수 없음', 'STATE_ERROR');
        if (st.items.some(i => i.sub === s.id && i.state === 'REJECTED')) err(409, '고치지 않은 항목', 'STATE_ERROR');
        s.attributes.state = 'WAITING_FOR_REVIEW';
        const it = st.items.find(i => i.sub === s.id);
        st.versions.find(v => v.id === it.ver).attributes.appStoreState = 'WAITING_FOR_REVIEW';
      }
      return { data: s };
    }
    if (method === 'POST' && path === '/v1/reviewSubmissions') {
      if (st.subs.some(s => s.attributes.state === 'READY_FOR_REVIEW')) err(409, '열린 제출이 이미 있음');
      if (st.subs.some(s => ['CANCELING', 'COMPLETING'].includes(s.attributes.state))) err(409, '닫는 중인 제출이 있음');
      if (opts.postBusy && st.postBusy++ < opts.postBusy) err(409, '아직 못 만듦');
      const s = { id: 's' + (st.subs.length + 1), type: 'reviewSubmissions', attributes: { state: 'READY_FOR_REVIEW' } };
      st.subs.push(s);
      return { data: s };
    }
    if (method === 'POST' && path === '/v1/reviewSubmissionItems') {
      const r = body.data.relationships;
      if (st.subs.some(s => ['CANCELING', 'COMPLETING'].includes(s.attributes.state))) err(409, 'not in valid state', 'STATE_ERROR.ENTITY_STATE_INVALID');
      if (opts.itemBusy && st.itemBusy++ < opts.itemBusy) err(409, 'not in valid state', 'STATE_ERROR.ENTITY_STATE_INVALID');
      if (st.items.some(i => i.sub === r.reviewSubmission.data.id && i.ver === r.appStoreVersion.data.id && i.state !== 'REMOVED')) {
        err(409, '이미 들어 있음', 'ENTITY_ERROR.RELATIONSHIP.INVALID');
      }
      st.items.push({ id: 'i' + (st.items.length + 1), sub: r.reviewSubmission.data.id, ver: r.appStoreVersion.data.id,
        state: 'READY_FOR_REVIEW' });
      return { data: { id: 'i1' } };
    }
    const si = path.match(/^\/v1\/reviewSubmissions\/(\w+)\/items$/);
    if (si && method === 'GET') {
      if (opts.itemsErr) err(opts.itemsErr, '항목을 못 읽음');
      return { data: st.items.filter(i => i.sub === si[1]).map(i => ({ id: i.id, type: 'reviewSubmissionItems',
        attributes: { state: i.state },
        relationships: { appStoreVersion: { data: i.ver ? { type: 'appStoreVersions', id: i.ver } : null } } })) };
    }
    const ip = path.match(/^\/v1\/reviewSubmissionItems\/(\w+)$/);
    if (ip && method === 'PATCH') {
      const it = st.items.find(i => i.id === ip[1]);
      if (body.data.attributes.resolved) {
        if (opts.noResolve) err(409, 'resolved 는 모르는 칸', 'ENTITY_ERROR.ATTRIBUTE.UNKNOWN');
        it.state = 'READY_FOR_REVIEW';
      }
      if (body.data.attributes.removed) {
        if (opts.removeErr) err(opts.removeErr, '뺄 수 없음', 'STATE_ERROR');
        it.state = 'REMOVED';
        const s = st.subs.find(x => x.id === it.sub);
        if (st.items.filter(i => i.sub === s.id).every(i => i.state === 'REMOVED')) {
          s.attributes.state = 'COMPLETING'; s.closePolls = opts.closePolls || 1;   // 다 빼면 제출이 끝남(애플 도움말)
        }
      }
      return { data: { id: it.id } };
    }
    const vbg = path.match(/^\/v1\/appStoreVersions\/(\w+)\/build$/);
    if (vbg && method === 'GET') {
      if (opts.buildReadErr) err(opts.buildReadErr, '빌드를 못 읽음');
      const v = st.versions.find(x => x.id === vbg[1]);
      return { data: v && v.build ? { id: v.build, type: 'builds' } : null };
    }
    const rd = path.match(/^\/v1\/appStoreVersions\/(\w+)\/appStoreReviewDetail$/);
    if (rd && method === 'GET') {
      if (opts.notesErr) err(opts.notesErr, '심사 정보를 못 읽음');
      if (!st.reviewDetail) err(404, '심사 정보 없음');
      return { data: st.reviewDetail };
    }
    if (method === 'POST' && path === '/v1/appStoreReviewDetails') {
      st.reviewDetail = { id: 'rd1', type: 'appStoreReviewDetails', attributes: Object.assign({}, body.data.attributes) };
      return { data: st.reviewDetail };
    }
    const rp = path.match(/^\/v1\/appStoreReviewDetails\/(\w+)$/);
    if (rp && method === 'PATCH') {
      Object.assign(st.reviewDetail.attributes, body.data.attributes);
      return { data: st.reviewDetail };
    }
    if (method === 'POST' && path === '/v1/appStoreVersions') {
      const v = { id: 'v2', type: 'appStoreVersions',
        attributes: { versionString: body.data.attributes.versionString, appStoreState: 'PREPARE_FOR_SUBMISSION' } };
      st.versions.push(v);
      return { data: v };
    }
    if (method === 'GET' && path === '/v1/betaGroups') return { data: st.groups };
    if (method === 'GET' && path === '/v1/betaAppReviewSubmissions') {
      if (opts.betaFail) err(500, '베타 조회 실패');
      const want = (p.match(/filter\[build\]=(\w+)/) || [])[1];
      const review = opts.betaReview || (st.betaSubs.includes(want) ? 'WAITING_FOR_REVIEW' : null);
      return { data: review ? [{ id: 'br1', attributes: { betaReviewState: review } }] : [] };
    }
    if (method === 'GET' && /^\/v1\/builds\/\w+\/buildBetaDetail$/.test(path)) {
      if (opts.betaFail) err(500, '베타 조회 실패');
      return { data: { id: 'bd1', attributes: { externalBuildState: opts.external || 'WAITING_FOR_BETA_REVIEW' } } };
    }
    const g1 = path.match(/^\/v1\/betaGroups\/(\w+)$/);
    if (g1 && method === 'GET') return { data: st.groups.find(g => g.id === g1[1]) };
    if (g1 && method === 'PATCH') {
      const g = st.groups.find(x => x.id === g1[1]);
      Object.assign(g.attributes, body.data.attributes);
      if (g.attributes.publicLinkEnabled) g.attributes.publicLink = 'https://testflight.apple.com/join/AbCd1234';
      return { data: opts.patchNoLink ? { id: g.id, attributes: { publicLinkEnabled: true } } : g };
    }
    const gb = path.match(/^\/v1\/betaGroups\/(\w+)\/builds$/);
    if (gb) return { data: st.groupBuilds[gb[1]] };
    const gr = path.match(/^\/v1\/betaGroups\/(\w+)\/relationships\/builds$/);
    if (gr && method === 'POST') { st.groupBuilds[gr[1]].push(...body.data); return null; }
    if (gr && method === 'DELETE') {
      const ids = body.data.map(x => x.id);
      st.groupBuilds[gr[1]] = st.groupBuilds[gr[1]].filter(b => !ids.includes(b.id));
      return null;
    }
    if (method === 'POST' && path === '/v1/appStoreVersionReleaseRequests') {
      st.releases.push(body);
      const v = st.versions.find(x => x.id === body.data.relationships.appStoreVersion.data.id);
      if (opts.releaseRace) v.attributes.appStoreState = 'READY_FOR_SALE';   // 그 사이 웹에서 출시됨
      if (opts.releaseErr) err(opts.releaseErr, 'The version is not in a valid state for release', 'STATE_ERROR');
      const a = v.attributes;
      if (a.appStoreState !== 'PENDING_DEVELOPER_RELEASE' && a.appVersionState !== 'PENDING_DEVELOPER_RELEASE') {
        err(409, '출시할 수 없는 상태', 'STATE_ERROR');
      }
      if (a.appStoreState) a.appStoreState = 'PROCESSING_FOR_APP_STORE';
      if (a.appVersionState) a.appVersionState = 'PROCESSING_FOR_DISTRIBUTION';
      return { data: { id: 'rr1', type: 'appStoreVersionReleaseRequests' } };
    }
    if (method === 'GET' && /\/betaBuildLocalizations$/.test(path)) return { data: st.locs };
    if (method === 'POST' && path === '/v1/betaBuildLocalizations') { st.locs.push({ id: 'l1', attributes: body.data.attributes }); return { data: {} }; }
    if (method === 'POST' && path === '/v1/betaAppReviewSubmissions') {
      const b = body.data.relationships.build.data.id;
      if (st.betaSubs.includes(b)) err(422, 'INVALID_QC_STATE');   // 애플은 409 가 아니라 422 로 거절(9/28)
      st.betaSubs.push(b);
      return { data: {} };
    }
    err(500, `모르는 요청 ${method} ${path}`);
  }
  return { st, client: { call } };
}

/* 앱스토어 페이지 조회 가짜 — 기본은 「아직 안 보임」. 부른 주소를 모읍니다. */
const lookups = [];
const notListed = async url => { lookups.push(url); return { resultCount: 0, results: [] }; };
const listed = v => async url => { lookups.push(url); return { resultCount: 1, results: [{ version: v }] }; };
const quiet = { log: () => {}, noWait: true, lookup: notListed };

/* --release 시험용: 0.2.20 판 하나(상태를 고름) + 걸려 있는 심사 제출 s1(건드리면 안 됨).
   진짜 응답에는 두 칸이 다 옵니다 — extra.both = [appStoreState, appVersionState] 로 둘 다 적습니다. */
function relFake(state, extra = {}) {
  const attrs = extra.both ? { versionString: '0.2.20', appStoreState: extra.both[0], appVersionState: extra.both[1] }
    : extra.newField ? { versionString: '0.2.20', appVersionState: state }
    : { versionString: '0.2.20', appStoreState: state };
  return fake(Object.assign({ versions: [{ id: 'v20', type: 'appStoreVersions', attributes: attrs }] }, extra));
}
/* --release 가 부르면 안 되는 주소 — 심사 제출 · 베타 그룹 · 빌드 · 베타 심사. */
const FORBIDDEN = /reviewSubmission|betaGroups|betaAppReview|betaBuild|\/v1\/builds/;

(async () => {
  console.log('[1] 읽기만 — 바꾸는 요청이 하나도 없다');
  {
    const f = fake();
    const r = await run(['--version', '0.2.15', '--build', '298', '--beta', 'friends'], {}, { client: f.client, ...quiet });
    ok(r.submitted === false, '제출하지 않음');
    ok(f.st.calls.every(c => c.startsWith('GET')), 'GET 만 불림');
    ok(r.plan.target.id === 'v1', '고칠 판은 심사 대기 중이던 0.2.8');
  }

  console.log('[2] 제출 — 취소 → 기다림 → 번호 · 빌드 바꿈 → 새 제출');
  {
    const f = fake({ cancelPolls: 3 });
    const r = await run(['--version', '0.2.15', '--build', '298', '--submit'], {}, { client: f.client, ...quiet, tries: 10 });
    const v = f.st.versions[0];
    ok(f.st.subs[0].attributes.state === 'COMPLETE', '옛 제출 취소 → 정리 끝(COMPLETE)까지 기다림');
    ok(v.attributes.versionString === '0.2.15', '판 번호 0.2.15');
    ok(v.build === 'b298', '빌드 298 붙음');
    ok(v.attributes.appStoreState === 'WAITING_FOR_REVIEW', '다시 심사 대기');
    ok(r.submissionId === 's2', '새 제출 s2');
    const iCancel = f.st.calls.indexOf('PATCH /v1/reviewSubmissions/s1');
    const iPatch = f.st.calls.indexOf('PATCH /v1/appStoreVersions/v1');
    ok(iCancel >= 0 && iPatch > iCancel, '취소가 먼저, 판 고치기는 그 뒤');
  }

  console.log('[3] 취소가 끝나지 않으면 새 제출을 만들지 않고 멈춘다');
  {
    const f = fake({ cancelPolls: 99 });
    let threw = null;
    try { await run(['--version', '0.2.15', '--build', '298', '--submit'], {}, { client: f.client, ...quiet, tries: 3 }); }
    catch (e) { threw = e; }
    ok(threw && /고칠 수 있는 상태/.test(threw.message), '시간 초과로 멈춤');
    ok(!f.st.calls.includes('POST /v1/reviewSubmissions'), '새 제출 없음');
  }

  console.log('[4] 빌드가 처리 중이면 아무것도 바꾸지 않는다');
  {
    const f = fake({ buildState: 'PROCESSING' });
    let threw = null;
    try { await run(['--version', '0.2.15', '--build', '298', '--submit'], {}, { client: f.client, ...quiet }); }
    catch (e) { threw = e; }
    ok(threw && /VALID/.test(threw.message), '멈춤');
    ok(f.st.calls.every(c => c.startsWith('GET')), '바꾼 것 없음');
  }

  console.log('[5] 빌드가 없으면 아무것도 바꾸지 않는다');
  {
    const f = fake({ noBuild: true });
    let threw = null;
    try { await run(['--version', '0.2.15', '--build', '298', '--submit'], {}, { client: f.client, ...quiet }); }
    catch (e) { threw = e; }
    ok(threw && /못 찾았습니다/.test(threw.message), '멈춤');
    ok(f.st.calls.every(c => c.startsWith('GET')), '바꾼 것 없음');
  }

  console.log('[6] 베타 — 그룹에 넣고, 옛 빌드 빼고, 테스트할 내용, 베타 심사 제출');
  {
    const f = fake();
    await run(['--version', '0.2.15', '--build', '298', '--beta', 'friends', '--beta-only', '--drop-old-beta',
      '--whats-new', '앱 알림 코드 · 키보드', '--submit'], {}, { client: f.client, ...quiet });
    ok(f.st.groupBuilds.g1.map(b => b.id).join() === 'b298', '그룹에는 298 만');
    ok(f.st.betaSubs.includes('b298'), '베타 심사 제출');
    ok(f.st.locs[0] && f.st.locs[0].attributes.whatsNew === '앱 알림 코드 · 키보드', '테스트할 내용');
    ok(!f.st.calls.some(c => c.startsWith('PATCH /v1/reviewSubmissions')), '--beta-only 는 앱스토어를 안 건드림');
  }

  console.log('[7] 베타 심사가 이미 제출돼 있으면 다시 내지 않는다(애플은 422) · 「테스트할 내용」 은 고친다');
  {
    const f = fake();
    f.st.betaSubs.push('b298');
    let threw = null;
    try {
      await run(['--version', '0.2.15', '--build', '298', '--beta', 'friends', '--beta-only', '--submit',
        '--whats-new', '꾹 눌러'], {}, { client: f.client, ...quiet });
    } catch (e) { threw = e; }
    ok(!threw, '오류 없이 끝남');
    ok(!f.st.calls.includes('POST /v1/betaAppReviewSubmissions'), '다시 내지 않음');
    ok(f.st.locs.some(l => l.attributes.whatsNew === '꾹 눌러'), '「테스트할 내용」 은 고침');
  }
  {
    const f = fake({ betaReview: 'APPROVED' });
    let threw = null;
    try {
      await run(['--version', '0.2.15', '--build', '298', '--beta', 'friends', '--beta-only', '--submit'], {},
        { client: f.client, ...quiet });
    } catch (e) { threw = e; }
    ok(!threw && !f.st.calls.includes('POST /v1/betaAppReviewSubmissions'), '승인된 빌드도 다시 내지 않음');
  }
  {
    const f = fake({ betaReview: 'REJECTED' });
    await run(['--version', '0.2.15', '--build', '298', '--beta', 'friends', '--beta-only', '--submit'], {},
      { client: f.client, ...quiet });
    ok(f.st.betaSubs.includes('b298'), '거절된 빌드는 다시 냄');
  }

  console.log('[8] 심사 제출이 없는(취소된) 판도 번호를 바꿔 새로 낸다');
  {
    const f = fake({ noSub: true, verState: 'DEVELOPER_REJECTED' });
    const r = await run(['--version', '0.2.15', '--build', '298', '--submit'], {}, { client: f.client, ...quiet });
    ok(f.st.versions[0].attributes.versionString === '0.2.15', '번호 바뀜');
    ok(r.submissionId, '제출됨');
  }

  console.log('[9] 인자 검사');
  {
    let threw = null;
    try { await run(['--version', 'v0.2.15', '--build', '298'], {}, { client: fake().client, ...quiet }); }
    catch (e) { threw = e; }
    ok(threw && /판 번호/.test(threw.message), 'v 붙은 판 번호 거절');
  }

  console.log('[10] 공개 링크 — 읽기만은 안 바꾸고, --submit 이면 켜서 주소를 준다');
  {
    const f = fake();
    const r = await run(['--link-only', '--beta', 'friends'], {}, { client: f.client, ...quiet });
    ok(!f.st.calls.some(c => !c.startsWith('GET')), '읽기만은 GET 뿐');
    ok(r.link.enabled === false && r.link.link === null, '꺼짐으로 읽음');
    const r2 = await run(['--link-only', '--beta', 'friends', '--submit'], {}, { client: f.client, ...quiet });
    ok(r2.link.enabled && r2.link.link === 'https://testflight.apple.com/join/AbCd1234', '켜고 주소');
    ok(f.st.groups[0].attributes.publicLinkLimitEnabled === false, '인원 제한 없음');
    const n = f.st.calls.filter(c => c.startsWith('PATCH')).length;
    await run(['--link-only', '--beta', 'friends', '--submit'], {}, { client: f.client, ...quiet });
    ok(f.st.calls.filter(c => c.startsWith('PATCH')).length === n, '이미 켜져 있으면 다시 안 바꿈');
    const f2 = fake({ patchNoLink: true });
    const r3 = await run(['--link-only', '--beta', 'friends', '--submit'], {}, { client: f2.client, ...quiet });
    ok(r3.link.link === 'https://testflight.apple.com/join/AbCd1234', '응답에 주소가 없으면 다시 읽음');
    /* --link-off: 읽기만은 안 바꾸고, --submit 이면 닫음(주소는 돌려주지 않음) · 이미 닫혔으면 안 바꿈 */
    const off0 = await run(['--link-only', '--link-off', '--beta', 'friends'], {}, { client: f.client, ...quiet });
    ok(off0.link.enabled === true && f.st.groups[0].attributes.publicLinkEnabled === true, '닫기 읽기만은 그대로');
    const m = f.st.calls.filter(c => c.startsWith('PATCH')).length;
    const off = await run(['--link-only', '--link-off', '--beta', 'friends', '--submit'], {}, { client: f.client, ...quiet });
    ok(off.link.enabled === false && off.link.link === null, '닫음');
    ok(f.st.groups[0].attributes.publicLinkEnabled === false, '그룹이 닫힘');
    ok(f.st.calls.filter(c => c.startsWith('PATCH')).length === m + 1, 'PATCH 한 번');
    await run(['--link-only', '--link-off', '--beta', 'friends', '--submit'], {}, { client: f.client, ...quiet });
    ok(f.st.calls.filter(c => c.startsWith('PATCH')).length === m + 1, '이미 닫혔으면 다시 안 바꿈');
    const reopen = await run(['--link-only', '--beta', 'friends', '--submit'], {}, { client: f.client, ...quiet });
    ok(reopen.link.enabled === true, '다시 열기');
    let threw = null;
    try { await run(['--link-only'], {}, { client: fake().client, ...quiet }); } catch (e) { threw = e; }
    ok(threw && /--beta/.test(threw.message), '--beta 없으면 거절');
  }

  console.log('[11] 베타 심사 상태 — 읽기만에 같이 찍고, 못 읽어도 멈추지 않는다');
  {
    const lines = [];
    const f = fake({ betaReview: 'APPROVED', external: 'IN_BETA_TESTING' });
    const r = await run(['--version', '0.2.15', '--build', '298', '--beta', 'friends'], {},
      { client: f.client, noWait: true, lookup: notListed, log: s => lines.push(s) });
    ok(r.plan.beta.review === 'APPROVED' && r.plan.beta.external === 'IN_BETA_TESTING', '상태를 읽음');
    ok(lines.some(l => /베타 심사: APPROVED · 외부 테스트 빌드 상태: IN_BETA_TESTING/.test(l)), '로그 한 줄');
    ok(!f.st.calls.some(c => !c.startsWith('GET')), '읽기만은 GET 뿐');
    const f2 = fake({ betaFail: true });
    const r2 = await run(['--version', '0.2.15', '--build', '298'], {}, { client: f2.client, ...quiet });
    ok(r2.plan.beta.review === null && r2.plan.beta.external === null, '못 읽으면 모름 — 멈추지 않음');
  }

  const rel = ['--release', '--version', '0.2.20'];
  const logInto = lines => ({ ...quiet, log: s => lines.push(s) });

  console.log('[12] 출시 — 심사 통과(PENDING_DEVELOPER_RELEASE) 판에 출시 요청을 딱 한 번');
  {
    const f = relFake('PENDING_DEVELOPER_RELEASE');
    const lines = [];
    const r = await run([...rel, '--submit'], {}, { client: f.client, ...logInto(lines) });
    ok(f.st.releases.length === 1, '출시 요청 한 번');
    const b = f.st.releases[0] && f.st.releases[0].data;
    ok(b && b.type === 'appStoreVersionReleaseRequests' && b.relationships.appStoreVersion.data.type === 'appStoreVersions' &&
      b.relationships.appStoreVersion.data.id === 'v20', '본문: appStoreVersionReleaseRequests → 판 v20');
    ok(f.st.calls.filter(c => !c.startsWith('GET')).join() === 'POST /v1/appStoreVersionReleaseRequests', '바꾸는 요청은 그것 하나');
    ok(r.release.action === 'requested' && r.release.versionId === 'v20', '결과: requested');
    ok(lines.some(l => /^출시 요청 보냄/.test(l)), '로그 「출시 요청 보냄」');
    /* 한 시간마다 다시 돌아도 — 이미 출시 중이면 다시 안 보냄 */
    const lines2 = [];
    const r2 = await run([...rel, '--submit'], {}, { client: f.client, ...logInto(lines2) });
    ok(f.st.releases.length === 1 && r2.release.action === 'already', '두 번째는 「이미 출시됨」 · 요청 없음');
    ok(lines2.some(l => /^이미 출시됨/.test(l)), '로그 「이미 출시됨」');
    /* 새 칸(appVersionState)만 있어도 */
    const f2 = relFake('PENDING_DEVELOPER_RELEASE', { newField: true });
    const r3 = await run([...rel, '--submit'], {}, { client: f2.client, ...quiet });
    ok(f2.st.releases.length === 1 && r3.release.action === 'requested', 'appVersionState 만 있어도 출시');
  }

  console.log('[13] 이미 출시된 판 — 요청을 보내지 않고 성공');
  for (const [state, newField] of [['READY_FOR_SALE'], ['PROCESSING_FOR_APP_STORE'], ['READY_FOR_DISTRIBUTION', true],
    ['PROCESSING_FOR_DISTRIBUTION', true]]) {
    const f = relFake(state, { newField });
    const lines = [];
    const r = await run([...rel, '--submit'], {}, { client: f.client, ...logInto(lines) });
    ok(f.st.releases.length === 0 && r.release.action === 'already' && lines.some(l => /^이미 출시됨/.test(l)),
      `${state} → 「이미 출시됨」 · POST 없음`);
  }

  console.log('[14] 아직 승인 전 — 출시하지 않고, 실패도 아님(한 시간마다 돌려도 무해)');
  for (const state of ['WAITING_FOR_REVIEW', 'IN_REVIEW', 'READY_FOR_REVIEW', 'WAITING_FOR_EXPORT_COMPLIANCE',
    'PENDING_CONTRACT']) {
    const f = relFake(state);
    const lines = [];
    let threw = null, r = null;
    try { r = await run([...rel, '--submit'], {}, { client: f.client, ...logInto(lines) }); } catch (e) { threw = e; }
    ok(!threw && r.release.action === 'waiting' && f.st.releases.length === 0 &&
      lines.includes(`아직 승인 전(${state}) — 출시하지 않음`), `${state} → 「아직 승인 전」 · POST 없음 · 오류 없음`);
  }
  {
    const f = relFake('PENDING_APPLE_RELEASE');
    const lines = [];
    const r = await run([...rel, '--submit'], {}, { client: f.client, ...logInto(lines) });
    ok(r.release.action === 'waiting' && f.st.releases.length === 0 &&
      lines.some(l => /^출시 요청을 받는 상태가 아님\(PENDING_APPLE_RELEASE\)/.test(l)), '애플이 잡고 있는 판은 「승인 전」 이라 하지 않음');
  }

  console.log('[14-2] 심사에서 빠짐(거절 · 철회 · 제출 전) — 출시하지 않고 실패로 멈춘다(기다려도 안 옴)');
  for (const [state, newField] of [['REJECTED'], ['METADATA_REJECTED'], ['INVALID_BINARY'], ['DEVELOPER_REJECTED'],
    ['PREPARE_FOR_SUBMISSION'], ['REJECTED', true], ['DEVELOPER_REJECTED', true]]) {
    for (const submit of [true, false]) {
      const f = relFake(state, { newField });
      const lines = [];
      const msg = `심사에서 빠짐(${state}) — 출시하지 않음. 고쳐서 다시 제출해야 합니다`;
      let threw = null;
      try { await run(submit ? [...rel, '--submit'] : rel, {}, { client: f.client, ...logInto(lines) }); } catch (e) { threw = e; }
      ok(threw && threw.message === msg && lines.includes(msg) && f.st.releases.length === 0 &&
        f.st.calls.every(c => c.startsWith('GET')) && !lines.some(l => /아직 승인 전/.test(l)),
        `${newField ? 'appVersionState ' : ''}${state}${submit ? '' : ' (읽기만)'} → 멈춤(오류) · POST 없음 · 「아직 승인 전」 아님`);
    }
  }

  console.log('[14-3] 두 칸(appStoreState · appVersionState)이 함께 올 때 — 출시 요청은 두 칸 모두일 때만');
  {
    const f = relFake(null, { both: ['PENDING_DEVELOPER_RELEASE', 'PENDING_DEVELOPER_RELEASE'] });
    const r = await run([...rel, '--submit'], {}, { client: f.client, ...quiet });
    ok(r.release.action === 'requested' && f.st.releases.length === 1, '두 칸 모두 PENDING_DEVELOPER_RELEASE → 출시 요청 한 번');
    const r2 = await run([...rel, '--submit'], {}, { client: f.client, ...quiet });
    ok(r2.release.action === 'already' && f.st.releases.length === 1, '다시 돌면 「이미 출시됨」 · 요청 없음');
  }
  /* 한 칸은 출시가 시작됐다고 하면 — 다시 보내면 409 로 빨간 불이 됩니다. 출시된 쪽을 믿습니다. */
  for (const both of [['PENDING_DEVELOPER_RELEASE', 'PROCESSING_FOR_DISTRIBUTION'],
    ['PROCESSING_FOR_DISTRIBUTION', 'PENDING_DEVELOPER_RELEASE'], ['PROCESSING_FOR_APP_STORE', 'PENDING_DEVELOPER_RELEASE']]) {
    const f = relFake(null, { both });
    const lines = [];
    const r = await run([...rel, '--submit'], {}, { client: f.client, ...logInto(lines) });
    ok(r.release.action === 'already' && f.st.releases.length === 0 && lines.some(l => /^이미 출시됨/.test(l)),
      `${both.join(' / ')} → 「이미 출시됨」 · POST 없음`);
  }
  /* 한 칸만 PENDING_DEVELOPER_RELEASE 이고 다른 칸이 다른 말(웹에서 뺌 · 아직 심사 중) — 보내지 않고 기다림. */
  for (const both of [['PENDING_DEVELOPER_RELEASE', 'DEVELOPER_REJECTED'], ['DEVELOPER_REJECTED', 'PENDING_DEVELOPER_RELEASE'],
    ['PENDING_DEVELOPER_RELEASE', 'IN_REVIEW'], ['WAITING_FOR_REVIEW', 'PENDING_DEVELOPER_RELEASE']]) {
    const f = relFake(null, { both });
    const lines = [];
    let threw = null, r = null;
    try { r = await run([...rel, '--submit'], {}, { client: f.client, ...logInto(lines) }); } catch (e) { threw = e; }
    ok(!threw && r.release.action === 'waiting' && f.st.releases.length === 0 &&
      f.st.calls.every(c => c.startsWith('GET')) && lines.includes(`두 칸이 다름(${both.join(' / ')}) — 출시하지 않고 다음 실행에 다시 봅니다`),
      `${both.join(' / ')} → 「두 칸이 다름」 · POST 없음 · 오류 없음`);
  }

  console.log('[15] --release 읽기만(--submit 없음) — 승인됐어도 요청을 보내지 않는다');
  {
    const f = relFake('PENDING_DEVELOPER_RELEASE');
    const lines = [];
    const r = await run(rel, {}, { client: f.client, ...logInto(lines) });
    ok(f.st.releases.length === 0 && f.st.calls.every(c => c.startsWith('GET')), 'GET 만 불림');
    ok(r.release.action === 'ready', '결과: ready');
    ok(lines.some(l => /--submit 이면 판 0\.2\.20 출시 요청/.test(l)) && lines.includes('읽기만 했습니다(--submit 없음).'), '할 일을 찍음');
    ok(f.st.versions[0].attributes.appStoreState === 'PENDING_DEVELOPER_RELEASE', '판 상태 그대로');
  }

  console.log('[16] --release 는 심사 제출 · 베타 · 공개 링크를 부르지도 않는다(--beta 등을 줘도)');
  {
    const extra = ['--beta', 'friends', '--drop-old-beta', '--whats-new', 'x', '--build', '347', '--submit'];
    const all = [];
    for (const state of ['PENDING_DEVELOPER_RELEASE', 'WAITING_FOR_REVIEW', 'READY_FOR_SALE']) {
      const f = relFake(state);
      await run([...rel, ...extra], {}, { client: f.client, ...quiet });
      all.push(...f.st.calls);
      ok(f.st.subs[0].attributes.state === 'WAITING_FOR_REVIEW', `${state}: 걸린 심사 제출 그대로`);
      ok(f.st.groupBuilds.g1.map(b => b.id).join() === 'b269' && !('publicLinkEnabled' in f.st.groups[0].attributes),
        `${state}: 베타 그룹 · 공개 링크 그대로`);
    }
    ok(!all.some(c => FORBIDDEN.test(c)), '심사 제출 · 베타 · 빌드 주소를 한 번도 안 부름');
    ok(all.filter(c => !c.startsWith('GET')).every(c => c === 'POST /v1/appStoreVersionReleaseRequests'), '바꾸는 요청은 출시 요청뿐');
  }

  console.log('[17] 애플이 출시 요청을 거절(409 · 422) — 분명한 한국어 줄');
  {
    const f = relFake('PENDING_DEVELOPER_RELEASE', { releaseErr: 409 });
    const lines = [];
    let threw = null;
    try { await run([...rel, '--submit'], {}, { client: f.client, ...logInto(lines) }); } catch (e) { threw = e; }
    ok(threw && /출시 요청을 애플이 받지 않았습니다\(409 STATE_ERROR/.test(threw.message) &&
      /PENDING_DEVELOPER_RELEASE 그대로/.test(threw.message), '409 → 멈춤(상태 그대로라 사람이 봐야 함)');
    ok(lines.some(l => /^출시 요청을 애플이 받지 않았습니다\(409/.test(l)), '로그에도 한 줄');
    ok(f.st.releases.length === 1, '다시 보내지 않음');
    const f2 = relFake('PENDING_DEVELOPER_RELEASE', { releaseErr: 422, releaseRace: true });
    const lines2 = [];
    let threw2 = null, r2 = null;
    try { r2 = await run([...rel, '--submit'], {}, { client: f2.client, ...logInto(lines2) }); } catch (e) { threw2 = e; }
    ok(!threw2 && r2.release.action === 'already' && lines2.some(l => /^이미 출시됨 — 출시 요청은 422/.test(l)),
      '422 인데 그 사이 출시됐으면 「이미 출시됨」 으로 성공');
    const f3 = relFake('PENDING_DEVELOPER_RELEASE', { releaseErr: 500 });
    let threw3 = null;
    try { await run([...rel, '--submit'], {}, { client: f3.client, ...quiet }); } catch (e) { threw3 = e; }
    ok(threw3 && threw3.status === 500, '그 밖의 오류는 그대로 올림');
  }

  console.log('[18] --release 인자 검사');
  {
    /* noCalls: 앱스토어 커넥트를 한 번도 부르기 전에 거절하는지(인자만 보고) */
    const bad = async (argv, re, name, noCalls) => {
      let threw = null;
      const f = relFake('PENDING_DEVELOPER_RELEASE');
      try { await run(argv, {}, { client: f.client, ...quiet }); } catch (e) { threw = e; }
      ok(threw && re.test(threw.message) && f.st.releases.length === 0 && (!noCalls || f.st.calls.length === 0), name);
    };
    await bad(['--release', '--submit'], /^--release 에는 --version /, '--version 없으면 거절 · 부르기 전에', true);
    await bad(['--release', '--version', 'v0.2.20', '--submit'], /^--release 에는 --version /, 'v 붙은 판 번호 거절 · 부르기 전에', true);
    await bad([...rel, '--link-only', '--beta', 'friends', '--submit'], /함께 쓸 수 없습니다/, '--link-only 와 함께면 거절 · 부르기 전에', true);
    await bad(['--release', '--version', '0.2.21', '--submit'], /판 0\.2\.21 이 없습니다/, '없는 판이면 멈춤');
  }

  console.log('[19] 앱스토어 페이지(iTunes lookup) — 보임 · 안 보임 · 못 읽음(멈추지 않음)');
  {
    lookups.length = 0;
    const f = relFake('READY_FOR_SALE');
    const lines = [];
    const r = await run(rel, {}, { client: f.client, ...logInto(lines), lookup: listed('0.2.20') });
    ok(lines.includes('앱스토어 페이지: 공개됨 (판 0.2.20)') && r.store.visible === true && r.store.version === '0.2.20', '보임 → 「공개됨 (판 0.2.20)」');
    ok(lookups[0] === 'https://itunes.apple.com/lookup?id=app1&country=kr', '주소: lookup?id=앱&country=kr');
    const iState = lines.findIndex(l => /^판 0\.2\.20 — /.test(l)), iStore = lines.findIndex(l => /^앱스토어 페이지/.test(l));
    ok(iState >= 0 && iStore > iState, '상태 줄 뒤에 찍음');

    const f2 = relFake('PENDING_DEVELOPER_RELEASE');
    const lines2 = [];
    const r2 = await run(rel, {}, { client: f2.client, ...logInto(lines2) });
    ok(lines2.includes('앱스토어 페이지: 아직 안 보임') && r2.store.visible === false, '안 보임 → 「아직 안 보임」');

    const f3 = relFake('PENDING_DEVELOPER_RELEASE');
    const lines3 = [];
    const down = async () => { throw Object.assign(new Error('getaddrinfo ENOTFOUND itunes.apple.com'), { code: 'ENOTFOUND' }); };
    let threw = null, r3 = null;
    try { r3 = await run([...rel, '--submit'], {}, { client: f3.client, ...logInto(lines3), lookup: down }); } catch (e) { threw = e; }
    ok(!threw && lines3.includes('앱스토어 페이지: 확인 못 함(ENOTFOUND)') && r3.store.visible === null, '네트워크 오류 → 「확인 못 함(ENOTFOUND)」');
    ok(f3.st.releases.length === 1, '못 읽어도 출시 요청은 그대로 감');

    const lines4 = [];
    await run(rel, {}, { client: relFake('WAITING_FOR_REVIEW').client, ...logInto(lines4), lookup: async () => ({}) });
    ok(lines4.some(l => /^앱스토어 페이지: 확인 못 함\(resultCount 없는 응답\)/.test(l)), '모양이 다른 응답 → 「확인 못 함」');

    /* 기본 모드(판 · 빌드)의 읽기에도 같은 줄 — 바꾸는 요청은 여전히 없음 */
    const f5 = fake();
    const lines5 = [];
    const r5 = await run(['--version', '0.2.15', '--build', '298'], {}, { client: f5.client, ...logInto(lines5), lookup: listed('0.2.20') });
    ok(lines5.includes('앱스토어 페이지: 공개됨 (판 0.2.20)') && r5.plan.store.visible === true, '기본 모드 읽기에도 찍음');
    ok(f5.st.calls.every(c => c.startsWith('GET')), '기본 모드 읽기는 여전히 GET 뿐');
    const iLast = lines5.findIndex(l => /^베타 심사:/.test(l)), iS5 = lines5.findIndex(l => /^앱스토어 페이지/.test(l));
    ok(iLast >= 0 && iS5 > iLast, '기본 모드도 상태 줄 뒤');

    /* 기본 모드의 --submit 길(취소 · 재제출)은 전과 같게 — 바깥 조회를 하지 않습니다 */
    lookups.length = 0;
    const f6 = fake({ cancelPolls: 1 });
    const lines6 = [];
    const r6 = await run(['--version', '0.2.15', '--build', '298', '--submit'], {},
      { client: f6.client, ...logInto(lines6), lookup: listed('0.2.20'), tries: 10 });
    ok(r6.submitted === true && lookups.length === 0 && !('store' in r6.plan) &&
      !lines6.some(l => /^앱스토어 페이지/.test(l)), '기본 모드 --submit 은 앱스토어 페이지를 조회하지 않음');
  }

  console.log('[20] 진짜 조회 함수 — 전체 시간 제한 · HTTP 상태 · 연결 거절에서 매달리지 않는다');
  {
    /* 가짜 전송(getJson 의 셋째 인자): 부르면 응답을 plan 대로 흘립니다. trickle 이면 그 간격으로
       한 글자씩 끝없이 — idle 제한은 한 번도 안 걸리고 전체 시간 제한만 끝낼 수 있는 모양입니다. */
    const fakeGet = plan => {
      const seen = {};
      const get = (url, o, cb) => {
        const req = new EventEmitter();
        let timer = null;
        req.destroy = () => { seen.destroyed = true; clearInterval(timer); };
        const res = new EventEmitter();
        res.statusCode = plan.status || 200;
        res.setEncoding = () => {};
        res.resume = () => { seen.resumed = true; };
        Object.assign(seen, { url, opts: o });
        setImmediate(() => {
          cb(res);
          if (plan.trickle) timer = setInterval(() => res.emit('data', ' '), plan.trickle);
          else { res.emit('data', plan.body); res.emit('end'); }
        });
        return req;
      };
      return { get, seen };
    };
    const U = 'https://itunes.apple.com/lookup?id=app1&country=kr';
    const tr = fakeGet({ trickle: 50 });
    const t1 = Date.now();
    let et = null, cap = null;
    /* 시험 쪽 한도 — 전체 제한이 망가졌으면 매달리지 않고 여기서 실패로 끝나게 */
    const capped = new Promise((_, rej) => { cap = setTimeout(() => rej(new Error('시험 한도 3초 넘김')), 3000); });
    try { await Promise.race([getJson(U, 400, tr.get), capped]); } catch (e) { et = e; }
    clearTimeout(cap);
    const took = Date.now() - t1;
    ok(et && et.message === '0.4초 안에 응답 없음' && took >= 350 && took < 2000 && tr.seen.destroyed,
      `조금씩 끝없이 오는 응답 → 전체 시간 제한으로 끝남 · 요청을 끊음(${took}ms)`);
    const f403 = fakeGet({ status: 403, body: '{"resultCount":1,"results":[]}' });
    let e403 = null, v403 = null;
    try { v403 = await getJson(U, 3000, f403.get); } catch (e) { e403 = e; }
    ok(!v403 && e403 && e403.message === 'HTTP 403' && f403.seen.resumed, '403 → 「HTTP 403」 (본문이 JSON 이어도 받지 않음)');
    const fOk = fakeGet({ body: '{"resultCount":1,"results":[{"version":"0.2.20"}]}' });
    const vOk = await getJson(U, 3000, fOk.get);
    ok(vOk && vOk.resultCount === 1 && vOk.results[0].version === '0.2.20', '200 + JSON → 읽은 객체');
    ok(fOk.seen.url === U && fOk.seen.opts.agent === false && fOk.seen.opts.headers.accept === 'application/json',
      '주소 그대로 · keep-alive 없이(agent:false) · accept: application/json');
    let eHtml = null;
    try { await getJson(U, 3000, fakeGet({ body: '<html>' }).get); } catch (e) { eHtml = e; }
    ok(eHtml && eHtml.message === 'JSON 이 아닌 응답', '200 인데 JSON 이 아니면 → 「JSON 이 아닌 응답」');

    /* 진짜 https: 연결은 받고 아무 말도 안 하는 서버 — TLS 인사가 끝나지 않아도 정해진 시간에 끝남.
       (idle 제한으로도 끝나는 모양이라 전체 제한은 위 가짜 전송이 지킵니다.) */
    const socks = [];
    const srv = net.createServer(s => { socks.push(s); s.on('error', () => {}); });
    await new Promise(r => srv.listen(0, '127.0.0.1', r));
    const port = srv.address().port;
    const t0 = Date.now();
    let e1 = null;
    try { await getJson(`https://127.0.0.1:${port}/lookup`, 300); } catch (e) { e1 = e; }
    ok(e1 && /응답 없음/.test(e1.message) && Date.now() - t0 < 3000, `시간 초과로 끝남(${Date.now() - t0}ms)`);
    socks.forEach(s => s.destroy());
    await new Promise(r => srv.close(r));
    let e2 = null;
    try { await getJson(`https://127.0.0.1:${port}/`, 3000); } catch (e) { e2 = e; }   // 방금 닫은 자리
    ok(e2 && e2.code === 'ECONNREFUSED', '연결 거절 → 오류(ECONNREFUSED)');
  }

  /* 10/2 — 0.2.20 이 1.4.1 로 거절된 모양 그대로: 판 0.2.20 REJECTED · 제출 s1 UNRESOLVED_ISSUES ·
     그 제출의 항목 i0(판 v20, REJECTED). 새 빌드 298 을 0.2.21 로 다시 냅니다. */
  const rejFake = (extra = {}) => fake(Object.assign({
    versions: [{ id: 'v20', type: 'appStoreVersions', attributes: { versionString: '0.2.20', appStoreState: 'REJECTED' } }],
    subState: 'UNRESOLVED_ISSUES', cancelPolls: 1,
    items: [{ id: 'i0', sub: 's1', ver: 'v20', state: 'REJECTED' }],
  }, extra));
  const again = ['--version', '0.2.21', '--build', '298', '--submit'];

  console.log('[21] 거절된 제출 하나 — 취소하지 않고 같은 제출로: 번호 · 빌드 → 항목 「고침」 → 제출');
  {
    const f = rejFake();
    const lines = [];
    const r = await run(again, {}, { client: f.client, ...logInto(lines) });
    const v = f.st.versions[0];
    ok(r.submissionId === 's1' && r.resubmitted === true, '같은 제출 s1 로 다시 냄');
    ok(f.st.subs.length === 1 && f.st.subs[0].attributes.state === 'WAITING_FOR_REVIEW', '취소 · 새 제출 없이 심사 대기');
    ok(!f.st.calls.includes('POST /v1/reviewSubmissions'), '새 제출을 만들지 않음');
    ok(v.attributes.versionString === '0.2.21' && v.build === 'b298', '판 0.2.21 · 빌드 298');
    ok(f.st.items[0].state === 'READY_FOR_REVIEW', '거절된 항목은 「고침」');
    const iVer = f.st.calls.indexOf('PATCH /v1/appStoreVersions/v20');
    const iItem = f.st.calls.indexOf('PATCH /v1/reviewSubmissionItems/i0');
    const iSub = f.st.calls.indexOf('PATCH /v1/reviewSubmissions/s1');
    ok(iVer >= 0 && iItem > iVer && iSub > iItem, '판 고치기 → 항목 고침 → 제출 순서');
    ok(f.st.calls.filter(c => c === 'PATCH /v1/reviewSubmissions/s1').length === 1, '제출 PATCH 는 한 번(취소 없음)');
    ok(lines.some(l => /같은 제출 s1/.test(l)), '로그에 「같은 제출」');
  }

  console.log('[22] 애플이 「고침」 표시를 받지 않으면(409) — 취소가 아니라 거절된 항목을 빼고, 정리되면 새로 낸다');
  {
    const f = rejFake({ noResolve: true });
    const lines = [];
    const r = await run(again, {}, { client: f.client, ...logInto(lines), tries: 5 });
    ok(f.st.items[0].state === 'REMOVED' && f.st.subs[0].attributes.state === 'COMPLETE', '거절된 항목을 빼서 제출을 끝냄');
    ok(!f.st.calls.includes('PATCH /v1/reviewSubmissions/s1'), '거절된 제출에 취소를 보내지 않음(애플이 409 로 막음)');
    ok(r.submissionId === 's2' && !r.resubmitted, '새 제출 s2');
    ok(f.st.subs[1].attributes.state === 'WAITING_FOR_REVIEW', '새 제출이 심사 대기');
    ok(f.st.versions[0].attributes.versionString === '0.2.21' && f.st.versions[0].build === 'b298', '판 · 빌드 그대로');
    ok(f.st.calls.filter(c => c === 'PATCH /v1/appStoreVersions/v20').length === 1, '번호는 한 번만 바꿈(응답이 사본이어도)');
    ok(lines.some(l => /409 ENTITY_ERROR\.ATTRIBUTE\.UNKNOWN/.test(l) && /거절된 항목을 빼고/.test(l)), '애플 코드와 함께 넘어간다고 찍음');
    const iWait = f.st.calls.indexOf('GET /v1/reviewSubmissions/s1');
    ok(iWait >= 0 && iWait < f.st.calls.indexOf('POST /v1/reviewSubmissions'), '정리 끝을 확인한 뒤에 새 제출');
  }

  console.log('[23] 같은 제출 다시 내기를 422 로 거절 → 「고침」 했던 항목도 빼고 새로 낸다');
  {
    const f = rejFake({ noResubmit: true, closePolls: 3 });
    const lines = [];
    const r = await run(again, {}, { client: f.client, ...logInto(lines), tries: 5 });
    ok(r.submissionId === 's2' && f.st.subs[1].attributes.state === 'WAITING_FOR_REVIEW', '새 제출 s2 심사 대기');
    ok(f.st.items[0].state === 'REMOVED', '「고침」 했던 항목도 뺌');
    ok(lines.some(l => /정리를 기다립니다\(COMPLETING\)/.test(l)), '정리(COMPLETING)를 기다린다고 찍음');
    ok(f.st.calls.filter(c => c === 'POST /v1/reviewSubmissions').length === 1, '정리 뒤라 새 제출은 한 번에');
  }
  {
    const f = rejFake({ noResubmit: true, neverClose: true });
    let threw = null;
    try { await run(again, {}, { client: f.client, ...quiet, tries: 3 }); } catch (e) { threw = e; }
    ok(threw && /정리되지 않았습니다/.test(threw.message) && !f.st.calls.includes('POST /v1/reviewSubmissions'),
      '끝내 정리되지 않으면 새 제출 없이 멈춤(무한히 기다리지 않음)');
  }
  {
    const f = rejFake({ noResubmit: true, removeErr: 409 });
    let threw = null;
    try { await run(again, {}, { client: f.client, ...quiet, tries: 3 }); } catch (e) { threw = e; }
    ok(threw && /Resubmit to App Review/.test(threw.message) && !f.st.calls.includes('POST /v1/reviewSubmissions'),
      '항목도 못 빼면 — 웹에서 누를 단추를 알려 주고 멈춤');
    ok(f.st.versions[0].attributes.versionString === '0.2.21' && f.st.versions[0].build === 'b298', '판 · 빌드는 준비된 채');
  }

  console.log('[24] 거절된 제출이 열려 있는 동안 판을 못 고치면(409) 항목을 빼고 새로 낸다');
  {
    const f = rejFake({ lockWhileUnresolved: true });
    const r = await run(again, {}, { client: f.client, ...quiet, tries: 5 });
    ok(f.st.subs[0].attributes.state === 'COMPLETE' && r.submissionId === 's2', '정리하고 새 제출 s2');
    ok(f.st.versions[0].attributes.versionString === '0.2.21' && f.st.versions[0].build === 'b298', '판 · 빌드 바뀜');
    ok(!f.st.calls.some(c => c.startsWith('PATCH /v1/reviewSubmissionItems')) || f.st.items[0].state === 'REMOVED',
      '「고침」 은 안 보내고 빼기만');
  }

  console.log('[25] 거절된 제출에 이 판이 없거나 · 다른 제출이 걸려 있으면 같은 제출로 내지 않는다');
  {
    const f = rejFake({ items: [{ id: 'i0', sub: 's1', ver: 'vX', state: 'REJECTED' }] });
    const r = await run(again, {}, { client: f.client, ...quiet, tries: 5 });
    ok(f.st.subs[0].attributes.state === 'COMPLETE' && r.submissionId === 's2', '다른 판의 제출 — 정리하고 새로');
    ok(!f.st.calls.includes('PATCH /v1/appStoreVersions/v20') || f.st.calls.indexOf('PATCH /v1/appStoreVersions/v20') >
      f.st.calls.indexOf('GET /v1/reviewSubmissions/s1'), '판은 정리가 끝난 뒤에 고침');
  }
  {
    /* 대기 중인 제출이 또 있으면(앱마다 하나라 실제로는 드묾) 같은 제출 길을 타지 않음 */
    const f = rejFake();
    f.st.subs.push({ id: 's9', type: 'reviewSubmissions', attributes: { state: 'WAITING_FOR_REVIEW' } });
    await run(again, {}, { client: f.client, ...quiet, tries: 5 });
    ok(!f.st.calls.some(c => c === 'PATCH /v1/reviewSubmissions/s1') && f.st.subs[0].attributes.state === 'COMPLETE' &&
      f.st.subs[1].attributes.state === 'COMPLETE', '다른 제출이 걸려 있으면 둘 다 닫고(거절된 것은 항목 빼기) 새로');
  }
  {
    /* 지난 실행이 번호 · 빌드까지 바꾸고 멈췄는데 판이 고칠 수 없는 상태가 됐으면 — 번호 · 빌드가 맞을 때만 그대로 이어서 */
    const f = rejFake({ versions: [{ id: 'v20', type: 'appStoreVersions', attributes: { versionString: '0.2.21', appStoreState: 'READY_FOR_REVIEW' } }] });
    f.st.versions[0].build = 'b298';
    const r = await run(again, {}, { client: f.client, ...quiet, tries: 5 });
    ok(r.submissionId === 's1' && r.resubmitted && !f.st.calls.includes('PATCH /v1/appStoreVersions/v20'),
      '번호 · 빌드가 맞으면 고치지 않고 같은 제출로 이어서 냄');
    const g = rejFake({ versions: [{ id: 'v20', type: 'appStoreVersions', attributes: { versionString: '0.2.21', appStoreState: 'READY_FOR_REVIEW' } }] });
    g.st.versions[0].build = 'b111';
    let threw = null;
    try { await run(again, {}, { client: g.client, ...quiet, tries: 2 }); } catch (e) { threw = e; }
    ok(!g.st.calls.some(c => c.startsWith('PATCH /v1/reviewSubmissionItems/i0') && g.st.items[0].state !== 'REMOVED'),
      '빌드가 다르면 같은 제출로 내지 않음');
  }

  console.log('[26] 권한 · 애플 고장(401 · 403 · 5xx)은 닫고 새로 내기로 넘어가지 않고 멈춘다');
  for (const code of [401, 403, 500]) {
    const f = rejFake({ itemsErr: code });
    let threw = null;
    try { await run(again, {}, { client: f.client, ...quiet }); } catch (e) { threw = e; }
    ok(threw && threw.status === code && f.st.subs[0].attributes.state === 'UNRESOLVED_ISSUES' &&
      f.st.calls.every(c => c.startsWith('GET')), `${code} — 아무것도 안 바꾸고 멈춤`);
  }

  console.log('[27] 심사 메모 — 원래 메모 뒤에 덧붙임 · 한 번만 · 원래 메모 · 데모 계정 · 연락처는 로그에 안 찍음');
  {
    const NOTE = 'Version 0.2.21 - citations\nSettings -> Help -> Sources';
    const rf = { readFile: f => (f === 'notes.txt' ? NOTE + '\r\n' : (() => { throw new Error('ENOENT'); })()) };
    const secret = { notes: 'Demo login: reviewer / pw-SECRET-1', demoAccountName: 'reviewer',
      demoAccountPassword: 'pw-SECRET-1', contactEmail: 'owner@example.invalid', contactPhone: '+82-10-0000-0000' };
    const f = rejFake({ reviewDetail: { id: 'rd1', type: 'appStoreReviewDetails', attributes: Object.assign({}, secret) } });
    const lines = [];
    const argv = [...again, '--review-notes-file', 'notes.txt'];
    await run(argv, {}, { client: f.client, ...logInto(lines), ...rf });
    const n = f.st.reviewDetail.attributes.notes;
    ok(n === `${secret.notes}\n\n${NOTE}`, '원래 메모 + 빈 줄 + 새 글(CRLF · 끝 공백 정리)');
    ok(f.st.reviewDetail.attributes.demoAccountPassword === 'pw-SECRET-1', '데모 계정은 그대로');
    ok(!lines.some(l => /SECRET|owner@example|0000-0000|reviewer/.test(l)), '로그에 원래 메모 · 계정 · 연락처 없음');
    ok(lines.some(l => /심사 메모: 덧붙임/.test(l)), '덧붙였다고 찍음(글자 수만)');
    const iNotes = f.st.calls.indexOf('PATCH /v1/appStoreReviewDetails/rd1');
    ok(iNotes >= 0 && iNotes < f.st.calls.indexOf('PATCH /v1/reviewSubmissions/s1'), '메모는 제출 전에');
    /* 같은 판을 다시 내도(예: 다시 거절된 뒤) 두 번 붙지 않음 */
    f.st.subs[0].attributes.state = 'UNRESOLVED_ISSUES';
    f.st.versions[0].attributes.appStoreState = 'REJECTED';
    f.st.items[0].state = 'REJECTED';
    const lines2 = [];
    await run(argv, {}, { client: f.client, ...logInto(lines2), ...rf });
    ok(f.st.reviewDetail.attributes.notes === n && lines2.some(l => /이미 들어 있음/.test(l)), '두 번째는 붙이지 않음');
  }
  {
    const NOTE = 'Version 0.2.21 - citations';
    const rf = { readFile: () => NOTE };
    const f = rejFake();                                   // 심사 정보가 아직 없음(404)
    await run([...again, '--review-notes-file', 'n.txt'], {}, { client: f.client, ...quiet, ...rf });
    ok(f.st.reviewDetail && f.st.reviewDetail.attributes.notes === NOTE, '심사 정보가 없으면 새로 만들어 적음');
    /* 메모를 줬는데 못 붙이면 내지 않고 멈춤 — 심사원에게 할 말 없이 내지 않게. 그 앞의 일은 다시 돌려도 무해. */
    const noSubmit = st => !st.calls.some(c => c.startsWith('PATCH /v1/reviewSubmission') || c === 'POST /v1/reviewSubmissions');
    const g = rejFake({ reviewDetail: { id: 'rd1', attributes: { notes: 'x'.repeat(3990) } } });
    let tg = null;
    try { await run([...again, '--review-notes-file', 'n.txt'], {}, { client: g.client, ...quiet, ...rf }); } catch (e) { tg = e; }
    ok(tg && /4018자 — 한도 4000/.test(tg.message) && g.st.reviewDetail.attributes.notes === 'x'.repeat(3990), '4000자를 넘으면 원래 메모를 지키고 멈춤');
    ok(noSubmit(g.st) && g.st.subs[0].attributes.state === 'UNRESOLVED_ISSUES', '「고침」 · 제출을 보내지 않음');
    for (const code of [500, 409]) {
      const h = rejFake({ notesErr: code, reviewDetail: { id: 'rd1', attributes: { notes: 'pw-SECRET-2' } } });
      let th = null;
      try { await run([...again, '--review-notes-file', 'n.txt'], {}, { client: h.client, ...quiet, ...rf }); } catch (e) { th = e; }
      ok(th && new RegExp(`읽기 ${code}`).test(th.message) && !/SECRET/.test(th.message) && noSubmit(h.st), `메모를 못 읽으면(${code}) 내지 않고 멈춤`);
    }
    /* 멈춘 뒤 다시 돌리면(메모가 고쳐졌다고 치고) 같은 제출로 이어서 냄 */
    g.st.reviewDetail.attributes.notes = 'short';
    const rg = await run([...again, '--review-notes-file', 'n.txt'], {}, { client: g.client, ...quiet, ...rf });
    ok(rg.submissionId === 's1' && rg.resubmitted && g.st.reviewDetail.attributes.notes === `short\n\n${NOTE}`, '다시 돌리면 이어서 같은 제출로');
  }
  {
    const f = rejFake({ reviewDetail: { id: 'rd1', attributes: { notes: 'old' } } });
    const lines = [];
    await run(['--version', '0.2.21', '--build', '298', '--review-notes-file', 'n.txt'], {},
      { client: f.client, ...logInto(lines), readFile: () => 'Version 0.2.21 - citations' });
    ok(f.st.calls.every(c => c.startsWith('GET')) && f.st.reviewDetail.attributes.notes === 'old', '읽기만은 메모를 바꾸지 않음');
    ok(lines.some(l => /심사 메모: n\.txt — 원래 3자 \+ 새 26자 = 31\/4000/.test(l)), '읽기만은 합친 길이만 찍음');
    ok(!lines.some(l => /\bold\b/.test(l)), '원래 메모 내용은 안 찍음');
    const g = rejFake({ reviewDetail: { id: 'rd1', attributes: { notes: 'z'.repeat(3990) } } });
    const l2 = [];
    await run(['--version', '0.2.21', '--build', '298', '--review-notes-file', 'n.txt'], {},
      { client: g.client, ...logInto(l2), readFile: () => 'Version 0.2.21 - citations' });
    ok(l2.some(l => /넘침\(제출하면 멈춤\)/.test(l)), '읽기만에서 넘침을 미리 알림');
    const h = rejFake({ notesErr: 500 });
    const l3 = [];
    const r3 = await run(['--version', '0.2.21', '--build', '298', '--review-notes-file', 'n.txt'], {},
      { client: h.client, ...logInto(l3), readFile: () => 'Version 0.2.21 - citations' });
    ok(r3.submitted === false && l3.some(l => /원래 메모 확인 못 함\(500\)/.test(l)), '읽기만은 메모를 못 읽어도 멈추지 않음');
  }

  console.log('[28] 메모 파일 검사 — 비었거나 · 너무 길거나 · 경로가 없으면 아무것도 안 바꾸고 멈춘다');
  for (const [name, text, re] of [['빈 파일', '  \n', /비어/], ['4001자', 'y'.repeat(4001), /4001자/]]) {
    const f = rejFake();
    let threw = null;
    try { await run([...again, '--review-notes-file', 'n.txt'], {}, { client: f.client, ...quiet, readFile: () => text }); }
    catch (e) { threw = e; }
    ok(threw && re.test(threw.message) && f.st.calls.length === 0, `${name} — 애플에 묻기 전에 멈춤`);
  }
  {
    const f = rejFake();
    let threw = null;
    try { await run([...again, '--review-notes-file'], {}, { client: f.client, ...quiet }); } catch (e) { threw = e; }
    ok(threw && /파일 경로/.test(threw.message) && f.st.calls.length === 0, '경로 없음 — 멈춤');
    let t2 = null;
    try { await run([...again, '--review-notes-file', '/없는/파일.txt'], {}, { client: f.client, ...quiet }); } catch (e) { t2 = e; }
    ok(t2 && f.st.calls.length === 0, '못 읽는 파일 — 멈춤');
  }

  console.log('[29] 이미 이 판 · 이 빌드로 심사 대기 중이면(응답을 못 받은 실행을 다시 돌림) 아무것도 안 바꾼다');
  {
    const f = fake({ versions: [{ id: 'v1', type: 'appStoreVersions', attributes: { versionString: '0.2.15', appStoreState: 'WAITING_FOR_REVIEW' } }] });
    f.st.versions[0].build = 'b298';
    const lines = [];
    const r = await run(['--version', '0.2.15', '--build', '298', '--submit'], {}, { client: f.client, ...logInto(lines) });
    ok(r.already === true && r.submissionId === 's1', '이미 제출됨으로 끝남');
    ok(f.st.calls.every(c => c.startsWith('GET')) && f.st.subs[0].attributes.state === 'WAITING_FOR_REVIEW', '취소 · 수정 없음');
    ok(lines.some(l => /이미 판 0\.2\.15 \(298\) 로 WAITING_FOR_REVIEW/.test(l)), '그렇다고 찍음');
    const g = fake({ versions: [{ id: 'v1', type: 'appStoreVersions', attributes: { versionString: '0.2.15', appStoreState: 'WAITING_FOR_REVIEW' } }] });
    g.st.versions[0].build = 'b111';
    const r2 = await run(['--version', '0.2.15', '--build', '298', '--submit'], {}, { client: g.client, ...quiet, tries: 5 });
    ok(r2.submissionId === 's2' && g.st.versions[0].build === 'b298', '빌드가 다르면 예전처럼 취소하고 새 빌드로 다시 냄');
    const h = fake({ versions: [{ id: 'v1', type: 'appStoreVersions', attributes: { versionString: '0.2.15', appStoreState: 'WAITING_FOR_REVIEW' } }], buildReadErr: 500 });
    let th = null;
    try { await run(['--version', '0.2.15', '--build', '298', '--submit'], {}, { client: h.client, ...quiet }); } catch (e) { th = e; }
    ok(th && th.status === 500 && h.st.calls.every(c => c.startsWith('GET')), '붙은 빌드를 못 읽으면 취소하지 않고 멈춤');
  }

  console.log('[30] 판 넣기가 409 — 정말 들어 있을 때만 넘어가고, 아니면 기다렸다 다시 · 끝내 안 되면 빈 제출을 내지 않음');
  {
    const f = fake({ itemBusy: 2 });
    const lines = [];
    const r = await run(['--version', '0.2.15', '--build', '298', '--submit'], {}, { client: f.client, ...logInto(lines), tries: 5 });
    ok(r.submissionId === 's2' && f.st.subs[1].attributes.state === 'WAITING_FOR_REVIEW', '기다렸다 넣고 제출');
    ok(f.st.calls.filter(c => c === 'POST /v1/reviewSubmissionItems').length === 3 && lines.some(l => /판을 아직 못 넣습니다/.test(l)), '409 두 번 → 세 번째에 들어감');
    const g = fake({ itemBusy: 99 });
    let tg = null;
    try { await run(['--version', '0.2.15', '--build', '298', '--submit'], {}, { client: g.client, ...quiet, tries: 3 }); } catch (e) { tg = e; }
    ok(tg && tg.status === 409 && !g.st.calls.includes('PATCH /v1/reviewSubmissions/s2'), '끝내 못 넣으면 빈 제출을 내지 않고 멈춤');
    /* 이미 들어 있는 409 — 남은 안 낸 제출(READY_FOR_REVIEW)에 판이 이미 있을 때 */
    const h = fake({ noSub: true, verState: 'DEVELOPER_REJECTED' });
    h.st.subs.push({ id: 's5', type: 'reviewSubmissions', attributes: { state: 'READY_FOR_REVIEW' } });
    h.st.items.push({ id: 'i5', sub: 's5', ver: 'v1', state: 'READY_FOR_REVIEW' });
    const rh = await run(['--version', '0.2.15', '--build', '298', '--submit'], {}, { client: h.client, ...quiet, tries: 3 });
    ok(rh.submissionId === 's5' && h.st.subs[0].attributes.state === 'WAITING_FOR_REVIEW', '이미 들어 있으면(409) 그대로 제출');
  }

  console.log('[31] 새 제출 만들기가 409 — 기다렸다 다시 · 끝내 안 되면 멈춤');
  {
    const f = fake({ postBusy: 2 });
    const r = await run(['--version', '0.2.15', '--build', '298', '--submit'], {}, { client: f.client, ...quiet, tries: 5 });
    ok(r.submissionId === 's2' && f.st.calls.filter(c => c === 'POST /v1/reviewSubmissions').length === 3, '세 번째에 만듦');
    const g = fake({ postBusy: 99 });
    let tg = null;
    try { await run(['--version', '0.2.15', '--build', '298', '--submit'], {}, { client: g.client, ...quiet, tries: 3 }); } catch (e) { tg = e; }
    ok(tg && tg.status === 409, '끝내 안 되면 409 로 멈춤');
  }

  console.log(`\n통과 ${pass} / 실패 ${fail}`);
  process.exit(fail ? 1 : 0);
})().catch(e => { console.error(e); process.exit(1); });
