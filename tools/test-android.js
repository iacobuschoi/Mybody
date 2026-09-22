/* =============================================================================
 * test-android.js — **폰에 깔았을 때 되는가**
 *
 * 여기서 돌리는 시험은 전부 웹 아니면 디버그 빌드입니다. 둘 다 권한이
 * 넉넉해서, 릴리스 APK 에서만 깨지는 것들을 못 잡습니다. 실제로 하나
 * 있었습니다 — 인터넷 권한이 debug/ 와 profile/ 매니페스트에만 있었고
 * 릴리스에는 없었습니다. 앱은 깔리고 켜지고, 서버 요청만 전부 막히고,
 * 화면에는 "컴퓨터가 꺼져 있을 수 있습니다" 가 떴습니다.
 *
 * 안드로이드 SDK 없이 볼 수 있는 것만 봅니다. 파일을 읽어서 봅니다.
 * ========================================================================== */
'use strict';
const fs = require('node:fs');
const path = require('node:path');

const ROOT = path.join(__dirname, '..');
const R = (p) => fs.readFileSync(path.join(ROOT, p), 'utf8');
const E = (p) => fs.existsSync(path.join(ROOT, p));

let pass = 0, fail = 0;
const ok = (m) => { pass++; console.log('  ✓ ' + m); };
const no = (m, d) => { fail++; console.log('  ✗ ' + m + (d ? '\n      ' + d : '')); };

console.log('\n폰에 깔았을 때 되는가\n');

/* --- 1. 인터넷 권한 ------------------------------------------------------ */
const MAIN = 'app/android/app/src/main/AndroidManifest.xml';
const main = R(MAIN);
if (/uses-permission\s+android:name="android\.permission\.INTERNET"/.test(main)) {
  ok('릴리스 매니페스트에 인터넷 권한이 있습니다');
} else {
  no('main/AndroidManifest.xml 에 인터넷 권한이 없습니다 — 앱이 깔려도 서버에 못 붙습니다',
     'debug/ 와 profile/ 에만 있으면 릴리스에는 안 들어갑니다. ' +
     '<uses-permission android:name="android.permission.INTERNET"/> 를 넣으세요');
}

/* --- 2. 앱 아이디 -------------------------------------------------------- */
const GRADLE = 'app/android/app/build.gradle.kts';
const gradle = R(GRADLE);
const appId = (gradle.match(/applicationId\s*=\s*"([^"]+)"/) || [])[1];
const ns = (gradle.match(/namespace\s*=\s*"([^"]+)"/) || [])[1];
/* 템플릿 냄새: com.example.* 이거나, 같은 조각이 두 번 들어간 것
   (flutter create 가 com.mybody.app + mybody 로 만들어 준 자리입니다). */
const seg = appId ? appId.split('.') : [];
const dup = seg.length !== new Set(seg).size;
if (!appId) no('applicationId 를 못 찾았습니다');
else if (/^com\.example\./.test(appId))
  no('applicationId 가 아직 flutter create 기본값입니다: ' + appId);
else if (dup)
  no('applicationId 에 같은 조각이 두 번 들어가 있습니다: ' + appId,
     '템플릿이 만들어 준 자리입니다. 누가 깔고 나면 못 바꿉니다');
else if (appId !== ns)
  no('applicationId 와 namespace 가 다릅니다: ' + appId + ' / ' + ns);
else ok('앱 아이디: ' + appId);

/* 매니페스트가 `.MainActivity` 라고만 적으므로, namespace 와 실제 코드의
   package 가 어긋나면 **빌드가 아니라 실행할 때** 죽습니다. */
if (ns) {
  const kt = path.join('app/android/app/src/main/kotlin', ns.replace(/\./g, '/'),
                       'MainActivity.kt');
  if (!E(kt)) no('namespace 와 MainActivity.kt 위치가 다릅니다', '없는 곳: ' + kt);
  else if (R(kt).indexOf('package ' + ns) !== 0)
    no('MainActivity.kt 의 package 가 namespace 와 다릅니다');
  else ok('namespace 와 MainActivity 가 같은 곳을 가리킵니다');
}

/* --- 3. 이름과 아이콘 ---------------------------------------------------- */
const label = (main.match(/android:label="([^"]+)"/) || [])[1];
if (label === 'mybody') no('폰에 나오는 이름이 템플릿 값(mybody)입니다');
else ok('폰에 나오는 이름: ' + label);

for (const d of ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi']) {
  const p = 'app/android/app/src/main/res/mipmap-' + d + '/ic_launcher_foreground.png';
  if (!E(p)) { no('아이콘이 없습니다: ' + p); break; }
}
if (E('app/android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml'))
  ok('adaptive 아이콘이 있습니다 (안 주면 런처가 흰 동그라미 안에 축소해 넣습니다)');
else no('adaptive 아이콘이 없습니다 — python3 tools/make-android-icons.py');

/* --- 4. 서명 ------------------------------------------------------------- */
if (/key\.properties/.test(gradle) && /signingConfigs/.test(gradle))
  ok('내 열쇠가 있으면 그걸 쓰게 돼 있습니다');
else no('릴리스가 디버그 열쇠로만 서명됩니다',
        '빌드 기계마다 열쇠가 달라서, 다음 앱이 업데이트로 안 깔립니다');

/* 열쇠가 저장소에 들어오면 안 됩니다. */
const { execFileSync } = require('node:child_process');
const tracked = execFileSync('git', ['ls-files'], { cwd: ROOT, encoding: 'utf8' });
const leaked = tracked.split('\n').filter(f => /\.(jks|keystore)$|key\.properties$/.test(f));
if (leaked.length) no('서명 열쇠가 저장소에 들어 있습니다: ' + leaked.join(' '));
else ok('서명 열쇠는 저장소에 없습니다');

/* --- 4b. Kotlin DSL 의 `java` 함정 --------------------------------------
 * .gradle.kts 안에서 `java` 는 Gradle 의 java 확장을 가리킵니다 — 패키지가
 * 아닙니다. 그래서 `java.util.Properties()` 라고 쓰면
 * "Unresolved reference: util" 로 **빌드가 시작도 못 합니다.**
 * 여기서는 안드로이드 SDK 가 없어 Gradle 을 못 돌려 보므로, 이 한 가지는
 * 글자로 막습니다 (실제로 첫 빌드가 이걸로 죽었습니다). */
const gradleBody = gradle.split('\n').filter(l => !/^\s*import\s/.test(l)).join('\n');
if (/(^|[^.\w])java\.(util|io|nio|text|time)\./m.test(gradleBody))
  no('build.gradle.kts 가 java.* 를 그대로 씁니다 — Kotlin DSL 에서는 안 됩니다',
     '위에 import 를 넣고 이름만 쓰세요: import java.util.Properties');
else ok('Kotlin DSL 에서 java.* 를 그대로 쓰지 않습니다');

/* --- 5. http 주소 -------------------------------------------------------- */
const acc = R('app/lib/src/screens/account.dart');
if (/안드로이드가 http 주소를 막습니다/.test(acc))
  ok('http 주소를 받으면 왜 안 되는지 말해 줍니다');
else no('http 주소를 그냥 받습니다',
        '안드로이드 9 부터 http 는 막힙니다 — 저장은 되고 연결만 조용히 실패합니다');

/* --- 6. 빌드 설정 -------------------------------------------------------- */
const WF = '.github/workflows/apk.yml';
if (!E(WF)) no('앱 파일을 만드는 설정이 없습니다: ' + WF);
else {
  const wf = R(WF);
  if (/--build-number=\$\{\{\s*github\.run_number\s*\}\}/.test(wf))
    ok('앱마다 번호가 올라갑니다 (안 올리면 폰이 업데이트로 안 받습니다)');
  else no('빌드 번호를 안 올립니다 — 만든 앱이 전부 1번이 됩니다');

  /* `secrets` 는 step 의 `if:` 문맥에 없습니다. 쓰면 빌드가 시작도 못 합니다. */
  const stepIfs = wf.split('\n').filter(l => /^\s+if:/.test(l));
  const bad = stepIfs.filter(l => /secrets\./.test(l));
  if (bad.length) no('step 의 if 에서 secrets 를 봅니다 — 그 문맥에 없어서 빌드가 시작도 못 합니다',
                     bad.join('\n      '));
  else ok('조건문이 볼 수 있는 것만 봅니다');
}

console.log('\n통과 ' + pass + ' / 실패 ' + fail);
process.exit(fail ? 1 : 0);
