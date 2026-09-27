#!/usr/bin/env node
/* =============================================================================
 * tools/test-asc-submit.js — tools/asc-submit.js 를 가짜 App Store Connect 로 시험
 *
 *   node tools/test-asc-submit.js
 *
 * 가짜는 애플의 규칙 몇 가지를 흉내 냅니다: 심사 대기 중인 판은 고칠 수 없고(409), 취소하면
 * 한 번 물어본 뒤에야 DEVELOPER_REJECTED 가 되고, 앱마다 안 낸 제출은 하나만 열 수 있습니다.
 * ========================================================================== */
'use strict';
const { run } = require('./asc-submit.js');

let pass = 0, fail = 0;
function ok(cond, name) {
  if (cond) { pass++; console.log('  ✓ ' + name); } else { fail++; console.log('  ✗ ' + name); }
}

function fake(opts = {}) {
  const st = {
    app: { id: 'app1', type: 'apps', attributes: { name: 'MyBody', bundleId: 'io.github.iacobuschoi.mybody' } },
    versions: [{ id: 'v1', type: 'appStoreVersions',
      attributes: { versionString: '0.2.8', appStoreState: opts.verState || 'WAITING_FOR_REVIEW' } }],
    subs: opts.noSub ? [] : [{ id: 's1', type: 'reviewSubmissions', attributes: { state: 'WAITING_FOR_REVIEW' } }],
    builds: opts.noBuild ? [] : [{ id: 'b298', type: 'builds',
      attributes: { version: '298', processingState: opts.buildState || 'VALID', usesNonExemptEncryption: false } }],
    groups: [{ id: 'g1', type: 'betaGroups', attributes: { name: 'friends', isInternalGroup: false } }],
    groupBuilds: { g1: [{ id: 'b269', type: 'builds' }] },
    locs: [],
    betaSubs: [],
    items: [],
    calls: [],
    cancelPending: 0,
  };
  const err = (status, msg) => { const e = new Error(msg); e.status = status; throw e; };
  async function call(method, p, body) {
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
      if (!['PREPARE_FOR_SUBMISSION', 'DEVELOPER_REJECTED'].includes(v.attributes.appStoreState)) err(409, '판을 고칠 수 없음');
      Object.assign(v.attributes, body.data.attributes);
      return { data: v };
    }
    const vb = path.match(/^\/v1\/appStoreVersions\/(\w+)\/relationships\/build$/);
    if (vb && method === 'PATCH') {
      const v = st.versions.find(x => x.id === vb[1]);
      if (!['PREPARE_FOR_SUBMISSION', 'DEVELOPER_REJECTED'].includes(v.attributes.appStoreState)) err(409, '빌드를 바꿀 수 없음');
      v.build = body.data.id;
      return null;
    }
    const sm = path.match(/^\/v1\/reviewSubmissions\/(\w+)$/);
    if (sm && method === 'PATCH') {
      const s = st.subs.find(x => x.id === sm[1]);
      if (body.data.attributes.canceled) { s.attributes.state = 'CANCELING'; st.cancelPending = opts.cancelPolls || 2; }
      if (body.data.attributes.submitted) {
        if (!st.items.some(i => i.sub === s.id)) err(409, '빈 제출');
        s.attributes.state = 'WAITING_FOR_REVIEW';
        const it = st.items.find(i => i.sub === s.id);
        st.versions.find(v => v.id === it.ver).attributes.appStoreState = 'WAITING_FOR_REVIEW';
      }
      return { data: s };
    }
    if (method === 'POST' && path === '/v1/reviewSubmissions') {
      if (st.subs.some(s => s.attributes.state === 'READY_FOR_REVIEW')) err(409, '열린 제출이 이미 있음');
      const s = { id: 's' + (st.subs.length + 1), type: 'reviewSubmissions', attributes: { state: 'READY_FOR_REVIEW' } };
      st.subs.push(s);
      return { data: s };
    }
    if (method === 'POST' && path === '/v1/reviewSubmissionItems') {
      const r = body.data.relationships;
      st.items.push({ sub: r.reviewSubmission.data.id, ver: r.appStoreVersion.data.id });
      return { data: { id: 'i1' } };
    }
    if (method === 'POST' && path === '/v1/appStoreVersions') {
      const v = { id: 'v2', type: 'appStoreVersions',
        attributes: { versionString: body.data.attributes.versionString, appStoreState: 'PREPARE_FOR_SUBMISSION' } };
      st.versions.push(v);
      return { data: v };
    }
    if (method === 'GET' && path === '/v1/betaGroups') return { data: st.groups };
    const gb = path.match(/^\/v1\/betaGroups\/(\w+)\/builds$/);
    if (gb) return { data: st.groupBuilds[gb[1]] };
    const gr = path.match(/^\/v1\/betaGroups\/(\w+)\/relationships\/builds$/);
    if (gr && method === 'POST') { st.groupBuilds[gr[1]].push(...body.data); return null; }
    if (gr && method === 'DELETE') {
      const ids = body.data.map(x => x.id);
      st.groupBuilds[gr[1]] = st.groupBuilds[gr[1]].filter(b => !ids.includes(b.id));
      return null;
    }
    if (method === 'GET' && /\/betaBuildLocalizations$/.test(path)) return { data: st.locs };
    if (method === 'POST' && path === '/v1/betaBuildLocalizations') { st.locs.push({ id: 'l1', attributes: body.data.attributes }); return { data: {} }; }
    if (method === 'POST' && path === '/v1/betaAppReviewSubmissions') {
      const b = body.data.relationships.build.data.id;
      if (st.betaSubs.includes(b)) err(409, '이미 제출');
      st.betaSubs.push(b);
      return { data: {} };
    }
    err(500, `모르는 요청 ${method} ${path}`);
  }
  return { st, client: { call } };
}

const quiet = { log: () => {}, noWait: true };

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
    ok(f.st.subs[0].attributes.state === 'CANCELING', '옛 제출 취소');
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

  console.log('[7] 베타 심사가 이미 제출돼 있으면(409) 그대로 둔다');
  {
    const f = fake();
    f.st.betaSubs.push('b298');
    let threw = null;
    try {
      await run(['--version', '0.2.15', '--build', '298', '--beta', 'friends', '--beta-only', '--submit'], {},
        { client: f.client, ...quiet });
    } catch (e) { threw = e; }
    ok(!threw, '오류 없이 끝남');
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

  console.log(`\n통과 ${pass} / 실패 ${fail}`);
  process.exit(fail ? 1 : 0);
})().catch(e => { console.error(e); process.exit(1); });
