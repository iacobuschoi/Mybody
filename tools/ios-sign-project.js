#!/usr/bin/env node
/* =============================================================================
 * tools/ios-sign-project.js — Runner 타깃만 수동 서명으로 바꿉니다 (CI 전용)
 *
 *   node tools/ios-sign-project.js --team ABCDE12345 --profile "Mybody AppStore GHA" \
 *        [--bundle io.github.iacobuschoi.mybody] [--project app/ios/Runner.xcodeproj/project.pbxproj]
 *
 * 왜 명령줄 대신 프로젝트 파일을 고치는가
 *   xcodebuild 에 PROVISIONING_PROFILE_SPECIFIER 를 명령줄로 넘기면 **모든 타깃**에
 *   걸립니다. 플러그인 Pods(image_picker 등)는 프레임워크 타깃이라 "does not
 *   support provisioning profiles" 로 멈춥니다. 그래서 앱 타깃(번들 ID 가 정확히
 *   우리 것인 설정)의 Release·Profile 에만 넣습니다. 저장소에는 올리지 않습니다 —
 *   러너가 빌드 직전에 고치고, 러너와 함께 사라집니다.
 * ========================================================================== */
'use strict';
const fs = require('node:fs');
const path = require('node:path');

const KEYS = (team, profile) => ({
  CODE_SIGN_STYLE: 'Manual',
  DEVELOPMENT_TEAM: team,
  PROVISIONING_PROFILE_SPECIFIER: `"${profile}"`,
  CODE_SIGN_IDENTITY: '"Apple Distribution"',
  '"CODE_SIGN_IDENTITY[sdk=iphoneos*]"': '"Apple Distribution"',
});

/** pbxproj 본문을 받아 고친 본문과 고친 설정 이름 목록을 돌려줍니다. */
function patch(text, { team, profile, bundle, configs }) {
  if (!/^[A-Z0-9]{10}$/.test(team || '')) throw new Error('팀 ID 는 대문자·숫자 10자입니다: ' + team);
  if (!profile || /["\n]/.test(profile)) throw new Error('프로파일 이름이 비었거나 따옴표가 있습니다');
  const want = new Set(configs || ['Release', 'Profile']);
  const keys = KEYS(team, profile);
  const touched = [];
  const re = /(\t\t[0-9A-F]{24} \/\* (\w+) \*\/ = \{\n\t\t\tisa = XCBuildConfiguration;[\s\S]*?\n\t\t\tbuildSettings = \{\n)([\s\S]*?)(\n\t\t\t\};\n\t\t\tname = (\w+);\n\t\t\};)/g;
  const out = text.replace(re, (all, head, _c, body, tail, name) => {
    if (!want.has(name)) return all;
    if (!body.split('\n').some(l => l.trim() === `PRODUCT_BUNDLE_IDENTIFIER = ${bundle};`)) return all;
    let lines = body.split('\n');
    const keyOf = l => l.trim().split(' = ')[0];
    lines = lines.filter(l => !(keyOf(l) in keys));
    for (const [k, v] of Object.entries(keys)) lines.push(`\t\t\t\t${k} = ${v};`);
    /* Xcode 처럼 키 이름순으로 둡니다 — 여러 줄 값(LD_RUNPATH_SEARCH_PATHS 의 괄호)은
       한 덩어리로 묶어 정렬합니다. */
    const items = [];
    for (const l of lines) {
      if (/^\t\t\t\t[^\t)]/.test(l)) items.push([l]);
      else if (items.length) items[items.length - 1].push(l);
    }
    const sortKey = it => keyOf(it[0]).replace(/"/g, '');
    items.sort((a, b) => (sortKey(a) < sortKey(b) ? -1 : sortKey(a) > sortKey(b) ? 1 : 0));
    touched.push(name);
    return head + items.map(it => it.join('\n')).join('\n') + tail;
  });
  return { text: out, touched };
}

function arg(argv, k, d) {
  const i = argv.indexOf('--' + k);
  return i >= 0 && argv[i + 1] !== undefined ? argv[i + 1] : d;
}

if (require.main === module) {
  const argv = process.argv.slice(2);
  const file = arg(argv, 'project', path.join(__dirname, '..', 'app', 'ios', 'Runner.xcodeproj', 'project.pbxproj'));
  try {
    const { text, touched } = patch(fs.readFileSync(file, 'utf8'), {
      team: arg(argv, 'team'), profile: arg(argv, 'profile'),
      bundle: arg(argv, 'bundle', 'io.github.iacobuschoi.mybody'),
    });
    if (touched.length < 2) throw new Error('Runner 타깃의 Release·Profile 설정을 못 찾았습니다 (찾은 것: ' + (touched.join(', ') || '없음') + ')');
    fs.writeFileSync(file, text);
    console.log('수동 서명으로 바꿈: Runner ' + touched.join(', '));
  } catch (e) {
    console.error('실패: ' + e.message);
    process.exit(1);
  }
}

module.exports = { patch };
