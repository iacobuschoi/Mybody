#!/usr/bin/env node
/* =============================================================================
 * tools/asc.js — App Store Connect API 로 아이폰 서명 재료 만들기 (맥 없이)
 *
 *   node tools/asc.js prepare --bundle io.github.iacobuschoi.mybody \
 *        --csr csr.pem --out DIR [--profile "Mybody AppStore GHA"] [--github-env FILE]
 *   node tools/asc.js list
 *
 * 환경변수: ASC_KEY_ID · ASC_ISSUER_ID · ASC_KEY_P8 (PEM 원문) 또는 ASC_KEY_P8_BASE64
 *
 * 왜 있는가
 *   배포 인증서와 프로비저닝 프로파일은 원래 맥의 Xcode 로 만듭니다. 그런데
 *   애플의 App Store Connect API 가 둘 다 만들어 줍니다 — CSR 만 있으면
 *   됩니다. CSR 은 openssl 로 어디서든 나오고, 깃허브의 맥 러너가 그걸 하면
 *   주인은 맥 없이 폰에서 실행 버튼만 누르면 됩니다.
 *
 * 무엇을 하는가 (prepare)
 *   1. 번들 ID 가 없으면 등록합니다.
 *   2. 우리 프로파일(이름으로 찾음)에 묶여 있던 인증서를 폐기합니다 — 지난
 *      실행이 만든 것이고, 그 열쇠는 그 러너와 함께 사라졌으니 어차피 못 씁니다.
 *      다른 인증서(맥에서 만든 것)는 건드리지 않습니다.
 *   3. 새 배포 인증서를 CSR 로 만듭니다.
 *   4. 우리 프로파일을 지우고 새 인증서로 다시 만듭니다.
 *   5. cert.cer(DER) 와 profile.mobileprovision 을 --out 에 씁니다.
 *
 * 의존성 0 — JWT(ES256) 는 node:crypto 로 직접 만듭니다. server/push.js 와
 * 같은 요령입니다: crypto.sign('sha256', …, { dsaEncoding: 'ieee-p1363' }).
 * ========================================================================== */
'use strict';
const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');

const API = 'https://api.appstoreconnect.apple.com';

/* --- 열쇠 --------------------------------------------------------------- */
function loadKeyPem(env) {
  /* 윈도우 메모장에서 복사하면 앞에 BOM(\uFEFF)·공백·\r 이 붙습니다. 깃허브 Secrets 에
     붙일 때 머리/꼬리 줄을 빼먹기도 합니다. 어느 쪽이든 본문(base64)만 뽑아 다시
     감쌉니다. */
  const clean = x => String(x || '').replace(/^\uFEFF/, '').replace(/\r/g, '').trim();
  let raw = clean(env.ASC_KEY_P8);
  const b64 = clean(env.ASC_KEY_P8_BASE64);
  if (!raw && b64) {
    const dec = clean(Buffer.from(b64.replace(/\s+/g, ''), 'base64').toString('utf8'));
    raw = dec.includes('BEGIN') ? dec : b64;
  }
  if (!raw) throw new Error('ASC_KEY_P8 (PEM) 또는 ASC_KEY_P8_BASE64 가 필요합니다');
  const body = raw.replace(/-----(BEGIN|END)[^-]*-----/g, '').replace(/[^A-Za-z0-9+/=]/g, '');
  if (body.length < 100) throw new Error('ASC_KEY_P8 에 열쇠 본문이 없습니다 (.p8 파일 내용 전체를 붙여 넣으세요)');
  const pem = '-----BEGIN PRIVATE KEY-----\n' + body.replace(/(.{64})/g, '$1\n').replace(/\n$/, '') +
    '\n-----END PRIVATE KEY-----\n';
  crypto.createPrivateKey(pem);   // 열쇠로 안 읽히면 여기서 바로 멈춥니다
  return pem;
}

const b64url = b => Buffer.from(b).toString('base64').replace(/=+$/, '').replace(/\+/g, '-').replace(/\//g, '_');

/** App Store Connect 용 JWT. 20분 한도라 매 요청마다 새로 만들어도 됩니다. */
function makeJwt({ keyId, issuerId, pem, now }) {
  const iat = Math.floor((now || Date.now()) / 1000);
  const header = { alg: 'ES256', kid: keyId, typ: 'JWT' };
  const payload = { iss: issuerId, iat, exp: iat + 15 * 60, aud: 'appstoreconnect-v1' };
  const signed = b64url(JSON.stringify(header)) + '.' + b64url(JSON.stringify(payload));
  const sig = crypto.sign('sha256', Buffer.from(signed), {
    key: crypto.createPrivateKey(pem), dsaEncoding: 'ieee-p1363',
  });
  return signed + '.' + b64url(sig);
}

/* --- 요청 --------------------------------------------------------------- */
function client({ keyId, issuerId, pem, fetchImpl, now, log }) {
  const f = fetchImpl || globalThis.fetch;
  const say = log || (() => {});
  async function call(method, p, body) {
    const res = await f(API + p, {
      method,
      headers: {
        authorization: 'Bearer ' + makeJwt({ keyId, issuerId, pem, now: now && now() }),
        'content-type': 'application/json',
        accept: 'application/json',
      },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    const text = await res.text();
    let json = null;
    try { json = text ? JSON.parse(text) : null; } catch (e) { json = null; }
    if (!res.ok) {
      const errs = (json && json.errors) || [];
      const detail = errs.map(e => `${e.status || ''} ${e.code || ''} ${e.title || ''}: ${e.detail || ''}`.trim()).join(' | ') ||
        text.slice(0, 300);
      const err = new Error(`${method} ${p} → ${res.status} ${detail}`);
      err.status = res.status;
      err.errors = errs;
      throw err;
    }
    say(`${method} ${p} → ${res.status}`);
    return json;
  }
  return { call };
}

/* --- 단계 --------------------------------------------------------------- */
async function ensureBundleId(c, identifier, name) {
  const r = await c.call('GET', `/v1/bundleIds?filter[identifier]=${encodeURIComponent(identifier)}&limit=200`);
  const hit = (r.data || []).find(x => x.attributes && x.attributes.identifier === identifier);
  if (hit) return { id: hit.id, created: false };
  const made = await c.call('POST', '/v1/bundleIds', {
    data: { type: 'bundleIds', attributes: { identifier, name: name || 'Mybody', platform: 'IOS' } },
  });
  return { id: made.data.id, created: true };
}

async function findProfile(c, name) {
  const r = await c.call('GET', `/v1/profiles?filter[name]=${encodeURIComponent(name)}&limit=200`);
  return (r.data || []).filter(x => x.attributes && x.attributes.name === name);
}

/** 우리 프로파일에 묶인 인증서 — 지난 실행이 만든 것들. */
async function certsOfProfile(c, profileId) {
  const r = await c.call('GET', `/v1/profiles/${profileId}/certificates?limit=200`);
  return (r.data || []).map(x => x.id);
}

async function createCertificate(c, csrPem) {
  try {
    const r = await c.call('POST', '/v1/certificates', {
      data: { type: 'certificates', attributes: { certificateType: 'DISTRIBUTION', csrContent: csrPem } },
    });
    return r.data;
  } catch (e) {
    const s = String(e.message);
    if (/maximum|limit|too many/i.test(s) || e.status === 409) {
      e.message += '\n\n  → 배포 인증서가 이미 최대 개수입니다. developer.apple.com → Certificates 에서\n' +
        '    안 쓰는 Apple Distribution 인증서 하나를 Revoke 하고 다시 돌리세요.\n' +
        '    (TestFlight 에 이미 올라간 빌드는 폐기해도 영향이 없습니다.)';
    }
    throw e;
  }
}

async function createProfile(c, { name, bundleIdId, certificateId }) {
  const r = await c.call('POST', '/v1/profiles', {
    data: {
      type: 'profiles',
      attributes: { name, profileType: 'IOS_APP_STORE' },
      relationships: {
        bundleId: { data: { type: 'bundleIds', id: bundleIdId } },
        certificates: { data: [{ type: 'certificates', id: certificateId }] },
      },
    },
  });
  return r.data;
}

/**
 * 서명 재료 한 벌을 만들어 out 에 씁니다.
 * 반환: { bundleIdId, bundleCreated, revoked: [certId…], certificateId, profileId, profileName, profileUuid, certFile, profileFile }
 */
async function prepare(opts) {
  const c = client(opts);
  const bundle = await ensureBundleId(c, opts.bundle, opts.bundleName);

  const old = await findProfile(c, opts.profileName);
  const revoked = [];
  for (const p of old) {
    for (const id of await certsOfProfile(c, p.id)) {
      try { await c.call('DELETE', `/v1/certificates/${id}`); revoked.push(id); }
      catch (e) { if (e.status !== 404) throw e; }
    }
    try { await c.call('DELETE', `/v1/profiles/${p.id}`); } catch (e) { if (e.status !== 404) throw e; }
  }

  const cert = await createCertificate(c, opts.csrPem);
  const profile = await createProfile(c, { name: opts.profileName, bundleIdId: bundle.id, certificateId: cert.id });

  fs.mkdirSync(opts.out, { recursive: true });
  const certFile = path.join(opts.out, 'cert.cer');
  const profileFile = path.join(opts.out, 'profile.mobileprovision');
  fs.writeFileSync(certFile, Buffer.from(cert.attributes.certificateContent, 'base64'));
  fs.writeFileSync(profileFile, Buffer.from(profile.attributes.profileContent, 'base64'));
  return {
    bundleIdId: bundle.id, bundleCreated: bundle.created, revoked,
    certificateId: cert.id, certificateName: cert.attributes.displayName || cert.attributes.name || '',
    profileId: profile.id, profileName: profile.attributes.name, profileUuid: profile.attributes.uuid,
    certFile, profileFile,
  };
}

async function list(opts) {
  const c = client(opts);
  const b = await c.call('GET', '/v1/bundleIds?limit=200');
  const k = await c.call('GET', '/v1/certificates?limit=200');
  const p = await c.call('GET', '/v1/profiles?limit=200');
  return {
    bundleIds: (b.data || []).map(x => ({ id: x.id, identifier: x.attributes.identifier, name: x.attributes.name })),
    certificates: (k.data || []).map(x => ({ id: x.id, type: x.attributes.certificateType, name: x.attributes.displayName, expires: x.attributes.expirationDate })),
    profiles: (p.data || []).map(x => ({ id: x.id, name: x.attributes.name, type: x.attributes.profileType, expires: x.attributes.expirationDate })),
  };
}

/* --- CLI ---------------------------------------------------------------- */
function arg(argv, k, d) {
  const i = argv.indexOf('--' + k);
  return i >= 0 && argv[i + 1] !== undefined ? argv[i + 1] : d;
}

async function main(argv, env) {
  const cmd = argv[0];
  if (cmd === 'write-key') {
    /* 워크플로가 altool 용 AuthKey_<id>.p8 을 이걸로 씁니다 — 붙여 넣은 값을 정리해서. */
    const out = argv[1];
    if (!out) { console.error('사용법: node tools/asc.js write-key <파일>'); return 2; }
    fs.writeFileSync(out, loadKeyPem(env), { mode: 0o600 });
    console.log('API 키 파일을 썼습니다 (열쇠로 읽히는 것 확인)');
    return 0;
  }
  if (cmd !== 'prepare' && cmd !== 'list') {
    console.error('사용법: node tools/asc.js prepare --bundle <id> --csr <csr.pem> --out <dir> [--profile <이름>] [--github-env <file>]\n' +
                  '        node tools/asc.js list');
    return 2;
  }
  const keyId = (env.ASC_KEY_ID || '').trim(), issuerId = (env.ASC_ISSUER_ID || '').trim();
  if (!keyId || !issuerId) { console.error('ASC_KEY_ID 와 ASC_ISSUER_ID 가 필요합니다'); return 2; }
  const pem = loadKeyPem(env);
  const common = { keyId, issuerId, pem, log: s => console.log('  ' + s) };

  if (cmd === 'list') {
    console.log(JSON.stringify(await list(common), null, 2));
    return 0;
  }
  const bundle = arg(argv, 'bundle');
  const csr = arg(argv, 'csr');
  const out = arg(argv, 'out');
  if (!bundle || !csr || !out) { console.error('--bundle, --csr, --out 이 다 필요합니다'); return 2; }
  const r = await prepare({
    ...common, bundle, bundleName: arg(argv, 'bundle-name', 'Mybody'),
    csrPem: fs.readFileSync(csr, 'utf8'), out,
    profileName: arg(argv, 'profile', 'Mybody AppStore GHA'),
  });
  console.log(`번들 ID  ${bundle} (${r.bundleCreated ? '새로 등록' : '있음'})`);
  console.log(`폐기     ${r.revoked.length ? r.revoked.join(', ') : '없음'} (지난 실행의 인증서)`);
  console.log(`인증서   ${r.certificateId} ${r.certificateName}`);
  console.log(`프로파일 ${r.profileName} (${r.profileUuid})`);
  const ge = arg(argv, 'github-env');
  if (ge) {
    fs.appendFileSync(ge, `profile_name=${r.profileName}\nprofile_uuid=${r.profileUuid}\n`);
  }
  return 0;
}

module.exports = { loadKeyPem, makeJwt, client, prepare, list, ensureBundleId, createCertificate, createProfile };

if (require.main === module) {
  main(process.argv.slice(2), process.env).then(code => process.exit(code), e => {
    console.error('실패: ' + (e && e.message ? e.message : e));
    process.exit(1);
  });
}
