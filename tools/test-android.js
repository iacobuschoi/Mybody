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

/* --- 3b. 몸 기록이 구글로 넘어가지 않는가 --------------------------------
 * android:allowBackup 을 **안 적으면 기본이 true** 입니다. 그러면 안드로이드
 * 자동 백업이 앱 저장소를 통째로 떠서 사용자의 구글 드라이브에 올립니다 —
 * 측정 기록 · 프로필 · 목표 전부요.
 *
 * 이 앱은 "몸 숫자는 이 폰에만" 을 내세우고 개인정보처리방침에도 그렇게
 * 적혀 있습니다. 비어 있으면 그 말이 거짓이 됩니다. 그래서 **명시적으로**
 * false 인지 봅니다. */
if (/android:allowBackup\s*=\s*"false"/.test(main))
  ok('자동 백업이 꺼져 있습니다 — 몸 기록이 구글 드라이브로 안 넘어갑니다');
else
  no('android:allowBackup 이 false 가 아닙니다 — 안드로이드가 몸 기록을 구글에 백업합니다',
     '안 적으면 기본이 true 입니다. 개인정보처리방침과 어긋납니다');

/* 내보내기가 **가져갈 수 있는** 것인가. "지우기 전에 내보내기 하세요" 라고
   여러 군데서 말하고 있으므로, 화면에 띄우기만 하면 거짓말이 됩니다. */
const settings = R('app/lib/src/screens/settings.dart');
if (/Clipboard\.setData/.test(settings))
  ok('내보내기가 복사됩니다 (붙여넣어 두면 그게 백업입니다)');
else
  no('내보내기가 화면에 보여 주기만 합니다',
     '"지우기 전에 내보내기 하세요" 라고 안내하면서 가져갈 방법이 없습니다');

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
/* 문구에 "안드로이드" 를 쓰지 않습니다 — 같은 화면이 아이폰에도 나가고,
   앱스토어 심사(2.3.10)는 다른 플랫폼 이름이 앱에 나오는 것을 싫어합니다. */
if (/http 주소는 폰이 막습니다/.test(acc))
  ok('http 주소를 받으면 왜 안 되는지 말해 줍니다');
else no('http 주소를 그냥 받습니다',
        '안드로이드 9 부터 http 는 막힙니다 — 저장은 되고 연결만 조용히 실패합니다');

/* --- 6. 빌드 설정 -------------------------------------------------------- */
const WF = '.github/workflows/apk.yml';
if (!E(WF)) no('앱 파일을 만드는 설정이 없습니다: ' + WF);
else {
  const wf = R(WF);
  /* 판 번호는 **커밋 수**입니다(git rev-list --count). 실행 번호(run_number)는
     푸시 빌드와 배포 빌드가 서로 다른 번호를 받아서, 플레이에 한 번 올리면
     다음 배포가 "번호가 작다" 고 거부됐습니다. 커밋 수는 길이 하나입니다 —
     단, 얕은 클론이면 언제나 1 이라 fetch-depth: 0 이 같이 있어야 합니다. */
  const countsCommits = /git rev-list --count HEAD/.test(wf);
  const usesCount = /--build-number=\$\{\{\s*steps\.vc\.outputs\.code\s*\}\}/.test(wf);
  const fullClone = /fetch-depth:\s*0/.test(wf);
  if (countsCommits && usesCount && fullClone)
    ok('앱마다 번호가 올라갑니다 — 커밋 수, 한 갈래 (안 올리면 폰이 업데이트로 안 받습니다)');
  else if (/--build-number=\$\{\{\s*github\.run_number\s*\}\}/.test(wf))
    no('빌드 번호가 실행 번호입니다 — 푸시 빌드와 배포 빌드가 다른 번호를 받아 플레이가 거부합니다');
  else if (countsCommits && usesCount && !fullClone)
    no('커밋 수를 쓰는데 fetch-depth: 0 이 없습니다 — 얕은 클론이라 번호가 언제나 1 입니다');
  else no('빌드 번호를 안 올립니다 — 만든 앱이 전부 1번이 됩니다');

  /* 플레이에 올리는 묶음(AAB)만 STORE=play 로 만듭니다(app/lib/src/update.dart).
     빠지면 플레이의 출시 전 보고서(adb 설치)에서 앱이 자기를 "직접 깐 APK" 로
     여기고, GitHub 에서 새 APK 를 받으라고 합니다 — 플레이 정책에 걸립니다. */
  const aab = (wf.match(/flutter build appbundle[\s\S]*?(?:\n\s*\n|$)/) || [''])[0];
  const apk = (wf.match(/flutter build apk[\s\S]*?(?:\n\s*\n|$)/) || [''])[0];
  if (/--dart-define=STORE=play/.test(aab) && !/STORE=play/.test(apk))
    ok('플레이용 묶음만 STORE=play 로 만듭니다 (업데이트 안내가 플레이 밖을 가리키지 않게)');
  else no('STORE=play 가 플레이용 묶음에만 있지 않습니다',
          'AAB 빌드에 --dart-define=STORE=play 가 있고, GitHub 에 올리는 APK 빌드에는 없어야 합니다');

  /* `secrets` 는 step 의 `if:` 문맥에 없습니다. 쓰면 빌드가 시작도 못 합니다. */
  const stepIfs = wf.split('\n').filter(l => /^\s+if:/.test(l));
  const bad = stepIfs.filter(l => /secrets\./.test(l));
  if (bad.length) no('step 의 if 에서 secrets 를 봅니다 — 그 문맥에 없어서 빌드가 시작도 못 합니다',
                     bad.join('\n      '));
  else ok('조건문이 볼 수 있는 것만 봅니다');
}

/* --- 7. 앱 알림(FCM) ---------------------------------------------------
 * 설정 파일(google-services.json)은 공개 저장소에 없고 CI 비밀에서만 나옵니다.
 * 그래서 플러그인 적용이 "파일이 있을 때만" 이 아니면 비밀이 없는 날의 빌드가
 * "File google-services.json is missing" 으로 깨집니다. 채널 · 아이콘 이름이
 * 어긋나면 빌드는 초록인 채로 알림이 「기타」 채널 · 흰 덩어리로 뜹니다. */
const code = (t) => t.replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '');
const GS_ID = 'com.google.gms.google-services';
const gradleCode = code(gradle);
const guarded = /if\s*\(\s*file\("google-services\.json"\)\.exists\(\)\s*\)\s*\{\s*apply\(plugin\s*=\s*"com\.google\.gms\.google-services"\)\s*\}/;
const uses = gradleCode.split(GS_ID).length - 1;
const settingsCode = code(R('app/android/settings.gradle.kts'));
const settingsOk = !settingsCode.includes(GS_ID) ||
  /id\("com\.google\.gms\.google-services"\)\s*version\s*"[^"]+"\s*apply\s+false/.test(settingsCode);
if (guarded.test(gradleCode) && uses === 1 && settingsOk)
  ok('google-services 플러그인은 설정 파일이 있을 때만 켭니다 (비밀이 없는 날도 빌드됨)');
else no('google-services 플러그인이 조건 없이 켜집니다 — 비밀이 없는 빌드가 깨집니다',
        'app/build.gradle.kts 에 if (file("google-services.json").exists()) { apply(plugin = "' + GS_ID + '") } 하나만, ' +
        'settings.gradle.kts 에는 apply false 로만 두세요');

const secretFiles = tracked.split('\n').filter(f =>
  /(^|\/)google-services\.json$|(^|\/)GoogleService-Info\.plist$|service-account[^/]*\.json$|\.p8$/.test(f));
if (secretFiles.length) no('앱 알림 설정 · 열쇠 파일이 저장소에 들어 있습니다: ' + secretFiles.join(' '),
                          '공개 저장소입니다 — git rm --cached 로 빼고 열쇠는 폐기하세요(docs/PUSH.md 7절)');
else ok('앱 알림 설정 · 열쇠 파일은 저장소에 없습니다');

const PUSH_DART = R('app/lib/src/native_push.dart');
const FCM_JS = R('server/fcm.js');
const chanManifest = (main.match(/android:name="com\.google\.firebase\.messaging\.default_notification_channel_id"\s*android:value="([^"]+)"/) || [])[1];
const chanApp = (PUSH_DART.match(/const kFriendsChannelId = '([^']+)'/) || [])[1];
const chanServer = (FCM_JS.match(/const CHANNEL = '([^']+)'/) || [])[1];
if (chanManifest && chanManifest === chanApp && chanApp === chanServer)
  ok('알림 채널이 한 이름입니다 (매니페스트 · 앱 · 서버: ' + chanApp + ')');
else no('알림 채널 이름이 어긋납니다 — FCM 알림이 조용히 「기타」 채널로 갑니다',
        '매니페스트 ' + chanManifest + ' · native_push.dart ' + chanApp + ' · server/fcm.js ' + chanServer);

const iconManifest = (main.match(/android:name="com\.google\.firebase\.messaging\.default_notification_icon"\s*android:resource="@drawable\/([^"]+)"/) || [])[1];
const iconApp = (PUSH_DART.match(/const kPushIcon = '([^']+)'/) || [])[1];
const iconServer = (FCM_JS.match(/const ICON = '([^']+)'/) || [])[1];
const iconFile = ['xml', 'png'].some(x => E('app/android/app/src/main/res/drawable/' + iconApp + '.' + x));
if (iconFile && iconManifest === iconApp && iconApp === iconServer)
  ok('상태바 알림 아이콘이 있습니다 (drawable/' + iconApp + ')');
else no('상태바 알림 아이콘이 없거나 이름이 어긋납니다 — 흰 덩어리로 뜨거나 아이콘 없이 뜹니다',
        '파일 ' + (iconFile ? '있음' : '없음') + ' · 매니페스트 ' + iconManifest + ' · 앱 ' + iconApp + ' · 서버 ' + iconServer);

/* 자동 초기화가 켜져 있으면 로그인하지 않은 사람 · 「로그인 없이 쓰기」 사용자도 켤 때마다
   구글에 기기가 등록됩니다(설치 ID · 토큰). 앱은 로그인 뒤에만 켭니다(native_push.dart). */
const plist = R('app/ios/Runner/Info.plist');
const autoOffAndroid = /android:name="firebase_messaging_auto_init_enabled"\s*android:value="false"/.test(main);
const autoOffIos = /<key>FirebaseMessagingAutoInitEnabled<\/key>\s*<false\/>/.test(plist);
if (autoOffAndroid && autoOffIos)
  ok('FCM 자동 초기화가 꺼져 있습니다 — 로그인 전에는 구글에 기기를 등록하지 않습니다');
else no('FCM 자동 초기화가 켜져 있습니다 — 로그인하지 않은 사람도 구글에 기기가 등록됩니다',
        (autoOffAndroid ? '' : '매니페스트에 firebase_messaging_auto_init_enabled=false 가 없음 ') +
        (autoOffIos ? '' : 'Info.plist 에 FirebaseMessagingAutoInitEnabled=false 가 없음'));

console.log('\n통과 ' + pass + ' / 실패 ' + fail);
process.exit(fail ? 1 : 0);
