#!/usr/bin/env node
/* guard.js 시험 — 막아야 할 것은 막고, 평소 일은 막지 않는지.
 *   node .claude/hooks/guard.test.js
 * 막는 쪽만 보면 "다 막는 훅" 도 통과합니다. 그래서 막으면 안 되는 쪽을 더 많이 둡니다. */
'use strict';
const { spawnSync } = require('child_process');
const path = require('path');
const { check } = require('./guard.js');

const BLOCK = [
  ['store-api', 'curl -X POST https://api.appstoreconnect.apple.com/v1/reviewSubmissions -d @body.json'],
  ['store-api', 'curl https://androidpublisher.googleapis.com/androidpublisher/v3/applications/x/edits'],
  ['store-upload', 'cd apps/habit && bundle exec fastlane ios release'],
  ['store-upload', 'fastlane android promote_to_production'],
  ['store-upload', 'fastlane pilot upload --ipa build.ipa'],
  ['approval-gate', 'gh api -X POST repos/me/app-factory/actions/runs/123/pending_deployments -f state=approved'],
  ['approval-gate', 'gh api -X PUT repos/me/app-factory/environments/store-production'],
  ['approval-gate', 'gh api repos/me/app-factory/branches/main/protection -X DELETE'],
  ['secrets', 'gh secret set ASC_KEY_P8 < AuthKey.p8'],
  ['key-read', 'cat ~/private_keys/AuthKey_ABC123.p8'],
  ['key-read', 'base64 -i upload.jks | pbcopy'],
  ['key-read', 'cp ~/mybody-signing-key/KEY-INFO.txt /tmp/'],
  ['key-read', 'tail -n 5 android/key.properties'],
  ['key-read', 'cat play-service-account.json'],
  ['key-read', 'Get-Content C:\\keys\\upload.keystore'],
  ['keychain-dump', 'security find-generic-password -s asc -w'],
  ['keychain-dump', 'security export -k login.keychain -t identities -f pkcs12 -o out.p12'],
  ['force-push-main', 'git push --force origin main'],
  ['force-push-main', 'git push origin main -f'],
  ['force-push-main', 'git push origin +main'],
  ['delete-main', 'git push origin :main'],
  ['delete-main', 'git push origin --delete main'],
  ['rm-root', 'rm -rf ~'],
  ['rm-root', 'rm -rf $HOME/'],
  ['rm-root', 'rm -fr /'],
  ['rm-root', 'rm -rf /Users/owner'],
  ['device-wipe', 'adb -s R58M reboot recovery'],
  ['device-wipe', 'adb shell pm uninstall --user 0 com.samsung.android.messaging'],
  ['device-wipe', 'adb shell pm clear com.google.android.gms'],
  ['ad-spend', 'curl -X POST https://api.searchads.apple.com/api/v5/campaigns'],
];

const ALLOW = [
  'flutter test',
  'cd apps/habit && flutter build apk --debug',
  'grep -rn "keystore" apps/habit/android',
  'grep -rn "\\.jks" .github/workflows',
  'ls ~/app-keys',
  'fastlane ios snapshot',
  'fastlane android screengrab',
  'fastlane ios test',
  'git push -u origin claude/habit-onboarding',
  'git push origin main',
  'git push --force origin claude/habit-onboarding',
  'gh run list --workflow ship.yml',
  'gh workflow run ship.yml -f app=habit',
  'gh api repos/me/app-factory/actions/runs/123',
  'gh pr create --title "습관 앱: 온보딩" --body-file /tmp/body.md',
  'rm -rf build/ .dart_tool/',
  'rm -rf ~/Library/Developer/Xcode/DerivedData/Runner-abc',
  'adb -s R58M install -r build/app/outputs/flutter-apk/app-debug.apk',
  'adb shell pm clear io.github.owner.habit',
  'adb shell pm uninstall io.github.owner.habit',
  'maestro test .maestro/onboarding.yaml',
  'curl -s "https://itunes.apple.com/search?term=habit&country=kr&entity=software"',
  'openssl x509 -in cert.pem -noout -dates',
  'node tools/preflight.js',
  'xcrun simctl boot "iPhone SE (3rd generation)"',
  'cat apps/habit/pubspec.yaml',
];

let fail = 0;
for (const [want, cmd] of BLOCK) {
  const hit = check(cmd);
  if (!hit || hit.id !== want) { fail++; console.log(`✗ 막아야 함(${want}): ${cmd}  → ${hit ? hit.id : '통과됨'}`); }
}
for (const cmd of ALLOW) {
  const hit = check(cmd);
  if (hit) { fail++; console.log(`✗ 막으면 안 됨: ${cmd}  → ${hit.id}`); }
}

/* 훅으로서 실제로 도는지 — stdin JSON, 종료코드 2, stderr 이유 */
const guard = path.join(__dirname, 'guard.js');
const run = (obj) => spawnSync(process.execPath, [guard], { input: typeof obj === 'string' ? obj : JSON.stringify(obj), encoding: 'utf8' });
const blocked = run({ hook_event_name: 'PreToolUse', tool_name: 'Bash', tool_input: { command: 'fastlane ios release' } });
if (blocked.status !== 2 || !/막음:store-upload/.test(blocked.stderr)) { fail++; console.log('✗ 훅: 막는 명령에 종료코드 2 + 이유가 안 나옴', blocked.status, blocked.stderr); }
const passed = run({ hook_event_name: 'PreToolUse', tool_name: 'Bash', tool_input: { command: 'flutter test' } });
if (passed.status !== 0) { fail++; console.log('✗ 훅: 평소 명령이 막힘', passed.status, passed.stderr); }
const garbage = run('not json');
if (garbage.status !== 0) { fail++; console.log('✗ 훅: 입력을 못 읽으면 통과시켜야 함', garbage.status); }

const total = BLOCK.length + ALLOW.length + 3;
console.log(fail ? `\n${fail}/${total} 실패` : `${total}개 전부 통과`);
process.exit(fail ? 1 : 0);
