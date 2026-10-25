#!/usr/bin/env node
/* =============================================================================
 * tools/asc-store.js — 앱스토어 새 버전의 등록정보를 API 로 채우기 (심사 제출은 안 함)
 *
 *   node tools/asc-store.js --version 0.2.22 --build 450 \
 *        --desc desc.txt --notes notes.txt --shots DIR [--apply] [--wait-build 40]
 *
 * 환경변수: tools/asc.js 와 같음 (ASC_KEY_ID · ASC_ISSUER_ID · ASC_KEY_P8 / ASC_KEY_P8_BASE64)
 *
 * 하는 일
 *   1. 그 판(버전)이 없으면 만듭니다(수동 출시). 이미 있으면 그대로 씀.
 *   2. 한국어 「설명」 · 「이 버전의 새로운 기능」 을 파일 글로 바꿉니다.
 *   3. 아이폰 스크린샷: 스크린샷이 들어 있던 아이폰 칸 중 가장 큰 칸에 DIR 의 png 를 이름 순서로
 *      올리고, 다른 아이폰 칸의 옛 스크린샷은 지웁니다(애플이 큰 칸을 줄여 씀).
 *   4. 빌드 번호가 처리 끝(VALID)이면 그 판에 붙입니다(--wait-build 분까지 기다림).
 *
 * --apply 가 없으면 무엇을 바꿀지 출력만 합니다.
 * **심사 제출 · 출시는 하지 않습니다** — reviewSubmissions 를 부르는 코드가 없습니다. 그건 주인이 콘솔에서.
 * ========================================================================== */
'use strict';
const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const { loadKeyPem, client } = require('./asc.js');

const BUNDLE = 'io.github.iacobuschoi.mybody';
const EDITABLE = ['PREPARE_FOR_SUBMISSION', 'DEVELOPER_REJECTED', 'REJECTED', 'METADATA_REJECTED'];

function arg(argv, k, d) {
  const i = argv.indexOf('--' + k);
  return i >= 0 && argv[i + 1] !== undefined ? argv[i + 1] : d;
}
const sleep = ms => new Promise(r => setTimeout(r, ms));

/** PNG 의 가로 · 세로 (IHDR). */
function pngSize(buf) { return [buf.readUInt32BE(16), buf.readUInt32BE(20)]; }

async function uploadShot(c, setId, file) {
  const buf = fs.readFileSync(file);
  const made = await c.call('POST', '/v1/appScreenshots', {
    data: {
      type: 'appScreenshots',
      attributes: { fileName: path.basename(file), fileSize: buf.length },
      relationships: { appScreenshotSet: { data: { type: 'appScreenshotSets', id: setId } } },
    },
  });
  for (const op of made.data.attributes.uploadOperations || []) {
    const headers = {};
    for (const h of op.requestHeaders || []) headers[h.name] = h.value;
    const res = await fetch(op.url, { method: op.method, headers, body: buf.subarray(op.offset, op.offset + op.length) });
    if (!res.ok) throw new Error(`스크린샷 올리기 실패 ${path.basename(file)} → ${res.status}`);
  }
  await c.call('PATCH', `/v1/appScreenshots/${made.data.id}`, {
    data: {
      type: 'appScreenshots', id: made.data.id,
      attributes: { uploaded: true, sourceFileChecksum: crypto.createHash('md5').update(buf).digest('hex') },
    },
  });
  return made.data.id;
}

async function main(argv, env) {
  const version = arg(argv, 'version'), build = arg(argv, 'build');
  const desc = arg(argv, 'desc'), notes = arg(argv, 'notes'), shotsDir = arg(argv, 'shots');
  const apply = argv.includes('--apply');
  const waitMin = Number(arg(argv, 'wait-build', '0'));
  if (!version || !build || !desc || !notes || !shotsDir) {
    console.error('사용법: node tools/asc-store.js --version 0.2.22 --build 450 --desc f --notes f --shots dir [--apply]');
    return 2;
  }
  const c = client({ keyId: env.ASC_KEY_ID.trim(), issuerId: env.ASC_ISSUER_ID.trim(), pem: loadKeyPem(env) });
  const say = s => console.log((apply ? '' : '[미리 보기] ') + s);
  const descText = fs.readFileSync(desc, 'utf8').trim(), notesText = fs.readFileSync(notes, 'utf8').trim();
  const shots = fs.readdirSync(shotsDir).filter(f => f.endsWith('.png')).sort().map(f => path.join(shotsDir, f));
  if (descText.length > 4000 || notesText.length > 4000) throw new Error('설명 · 새로운 기능은 4000자 이내');
  if (!shots.length || shots.length > 10) throw new Error('스크린샷은 1~10장');

  const app = (await c.call('GET', `/v1/apps?filter[bundleId]=${BUNDLE}`)).data[0];
  console.log(`앱 ${app.attributes.name} (${app.id})`);

  // 1. 판
  const vs = (await c.call('GET', `/v1/apps/${app.id}/appStoreVersions?filter[platform]=IOS&limit=20`)).data;
  for (const v of vs.slice(0, 4)) console.log(`  판 ${v.attributes.versionString} · ${v.attributes.appStoreState}`);
  let ver = vs.find(v => v.attributes.versionString === version);
  if (ver && !EDITABLE.includes(ver.attributes.appStoreState)) {
    throw new Error(`${version} 은 지금 ${ver.attributes.appStoreState} — 고칠 수 없는 상태라 멈춥니다`);
  }
  if (!ver) {
    say(`판 ${version} 만들기 (수동 출시)`);
    if (apply) {
      ver = (await c.call('POST', '/v1/appStoreVersions', {
        data: {
          type: 'appStoreVersions',
          attributes: { platform: 'IOS', versionString: version, releaseType: 'MANUAL' },
          relationships: { app: { data: { type: 'apps', id: app.id } } },
        },
      })).data;
    }
  }
  if (!ver) { say('(판이 아직 없어 나머지는 --apply 때 확인)'); return 0; }

  // 2. 한국어 글
  const locs = (await c.call('GET', `/v1/appStoreVersions/${ver.id}/appStoreVersionLocalizations`)).data;
  const loc = locs.find(l => l.attributes.locale === 'ko') || locs[0];
  console.log(`언어 ${loc.attributes.locale} · 지금 설명 ${(loc.attributes.description || '').length}자 · 새로운 기능 ${(loc.attributes.whatsNew || '').length}자`);
  say(`설명 → ${descText.length}자 · 새로운 기능 → ${notesText.length}자`);
  if (apply) {
    await c.call('PATCH', `/v1/appStoreVersionLocalizations/${loc.id}`, {
      data: { type: 'appStoreVersionLocalizations', id: loc.id, attributes: { description: descText, whatsNew: notesText } },
    });
  }

  // 3. 스크린샷
  const sets = (await c.call('GET', `/v1/appStoreVersionLocalizations/${loc.id}/appScreenshotSets?include=appScreenshots&limit=50`));
  const iphone = (sets.data || []).filter(s => /^APP_IPHONE_/.test(s.attributes.screenshotDisplayType));
  const count = s => ((s.relationships.appScreenshots || {}).data || []).length;
  for (const s of iphone) console.log(`  칸 ${s.attributes.screenshotDisplayType} · ${count(s)}장`);
  const order = ['APP_IPHONE_69', 'APP_IPHONE_67', 'APP_IPHONE_65', 'APP_IPHONE_61', 'APP_IPHONE_58', 'APP_IPHONE_55'];
  const rank = t => { const i = order.indexOf(t); return i < 0 ? 99 : i; };
  const filled = iphone.filter(count).sort((a, b) => rank(a.attributes.screenshotDisplayType) - rank(b.attributes.screenshotDisplayType));
  let target = filled[0];
  const [w, h] = pngSize(fs.readFileSync(shots[0]));
  say(`스크린샷 ${shots.length}장(${w}×${h}) → 칸 ${target ? target.attributes.screenshotDisplayType : 'APP_IPHONE_67(새로)'}, 옛 스크린샷 ${filled.reduce((n, s) => n + count(s), 0)}장 지움`);
  if (apply) {
    for (const s of filled) {
      for (const r of s.relationships.appScreenshots.data) await c.call('DELETE', `/v1/appScreenshots/${r.id}`);
    }
    if (!target) {
      target = (await c.call('POST', '/v1/appScreenshotSets', {
        data: {
          type: 'appScreenshotSets', attributes: { screenshotDisplayType: 'APP_IPHONE_67' },
          relationships: { appStoreVersionLocalization: { data: { type: 'appStoreVersionLocalizations', id: loc.id } } },
        },
      })).data;
    }
    for (const f of shots) console.log(`  올림 ${path.basename(f)} → ${await uploadShot(c, target.id, f)}`);
  }

  // 4. 빌드
  const deadline = Date.now() + waitMin * 60000;
  for (;;) {
    const b = (await c.call('GET', `/v1/builds?filter[app]=${app.id}&filter[version]=${build}&filter[preReleaseVersion.version]=${version}&limit=5`)).data[0];
    const st = b ? b.attributes.processingState : '없음';
    console.log(`빌드 ${build}: ${st}`);
    if (b && st === 'VALID') {
      say(`빌드 ${build} 를 판 ${version} 에 붙임`);
      if (apply) {
        await c.call('PATCH', `/v1/appStoreVersions/${ver.id}/relationships/build`, { data: { type: 'builds', id: b.id } });
      }
      break;
    }
    if (b && st !== 'PROCESSING') throw new Error(`빌드 ${build} 처리 상태가 ${st}`);
    if (Date.now() > deadline) { console.log('빌드가 아직 처리 중 — 붙이지 못함(나중에 다시 실행)'); break; }
    await sleep(60000);
  }
  console.log(apply ? '끝 — 심사 제출은 하지 않았습니다.' : '미리 보기 끝 — --apply 로 실제 반영');
  return 0;
}

if (require.main === module) {
  main(process.argv.slice(2), process.env).then(code => process.exit(code), e => {
    console.error('실패: ' + (e && e.message ? e.message : e));
    process.exit(1);
  });
}
