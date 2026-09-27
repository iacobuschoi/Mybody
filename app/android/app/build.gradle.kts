import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

/* 앱 알림(FCM) 설정.
 *
 * google-services.json 은 공개 저장소에 안 넣습니다. CI 가 비밀에서 꺼내 이 폴더에 둔 빌드에서만
 * 플러그인을 켭니다(plugins 블록 안에서는 if 를 못 써서 여기서 겁니다). 파일이 없으면 예전처럼
 * 빌드되고, 앱은 Firebase 초기화에 실패해 알림 없이 돕니다(lib/src/native_push.dart). */
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}

/* 서명 열쇠.
 *
 * 있으면 그걸로 서명하고, 없으면 아래에서 디버그 열쇠로 넘어갑니다.
 * 열쇠 자체는 저장소에 **안 들어갑니다** — 깃허브 Secrets 에 넣어 두고
 * 빌드할 때만 풀어서 씁니다 (.github/workflows/apk.yml 참고).
 */
val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
val hasOwnKey = keystoreProperties.getProperty("storeFile") != null

/* 초대 링크 호스트 (안드로이드 App Links).
 *
 * 친구가 받은 https://<서버>/i/<코드> 를 누르면 브라우저 없이 이 앱이 바로 열리게 하는 필터가
 * 매니페스트에 있고(autoVerify), 그 필터의 호스트가 이 값입니다(자리표시자 inviteHost).
 * 안드로이드는 앱을 깔 때 이 호스트의 /.well-known/assetlinks.json(서버가 내 줌)으로 "이 앱이
 * 이 주소의 주인" 인지 확인합니다.
 *
 * **앱에 박히는 서버 주소와 같은 호스트여야 합니다.** 앱은 자기 서버의 링크만 초대로 받습니다
 * (lib/src/invite_link.dart). 그래서 빌드할 때의 환경변수 SERVER_URL — CI 는 비밀
 * MYBODY_SERVER_URL 을 apk.yml 의 두 빌드 단계(APK · AAB)가 env 로 넘기고, 같은 값이
 * --dart-define=SERVER_URL 로 앱에도 들어갑니다 — 에서 호스트만 떼어 씁니다(https:// · 포트 ·
 * 경로 · 사용자@ 를 버리고 소문자로).
 *
 * 비었거나 호스트 모양이 아니면 lib/main.dart 의 기본 주소와 같은 호스트를 씁니다 — 노트북에서
 * 그냥 flutter build 해도 앱과 같은 값이 되게. 틀린 값이어도 빌드는 안 깨지고, 링크가 예전처럼
 * 브라우저(초대 페이지)로 열릴 뿐입니다. 호스트는 비밀에서 나온 값이라 빌드 로그에 찍지 않습니다.
 */
val inviteHost: String = run {
    val fallback = "desktop-il9c3if.tail0a8f8f.ts.net"
    val raw = (providers.environmentVariable("SERVER_URL").orNull ?: "").trim()
    val host = raw.substringAfter("://", raw)                             // https:// (없으면 그대로)
        .substringBefore('/').substringBefore('?').substringBefore('#')   // 경로 · 물음 · 조각
        .substringAfterLast('@')                                          // 사용자:비밀번호@
        .substringBefore(':')                                             // 포트
        .trimEnd('.')
        .lowercase()
    val label = "[a-z0-9]([a-z0-9-]*[a-z0-9])?"
    if (Regex("^$label(\\.$label)+$").matches(host)) host else fallback
}

android {
    namespace = "io.github.iacobuschoi.mybody"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // 알림 플러그인(flutter_local_notifications)이 java.time 을 씁니다 —
        // 옛 안드로이드에도 깔리려면 이게 켜져 있어야 합니다.
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        /* 폰이 앱을 구분하는 이름입니다. **누가 한 번 깔고 나면 못 바꿉니다** —
         * 바꾸면 폰은 다른 앱으로 보고, 업데이트가 아니라 새 설치가 됩니다
         * (그 폰에 있던 기록은 옛날 앱에 남고 새 앱은 빈 상태로 시작합니다).
         * 도메인을 안 가지고 있어서 깃허브 계정을 근거로 삼았습니다. */
        applicationId = "io.github.iacobuschoi.mybody"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // 매니페스트의 초대 링크 필터(https · autoVerify)가 쓰는 호스트 — 위 inviteHost.
        // 대입(=)이 아니라 한 칸만 넣습니다 — Flutter 가 넣는 applicationName 을 지우지 않게.
        manifestPlaceholders["inviteHost"] = inviteHost
    }

    signingConfigs {
        if (hasOwnKey) {
            create("release") {
                storeFile = rootProject.file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            /* **열쇠가 없으면 디버그 열쇠로 서명됩니다.**
             *
             * 그 자체로는 깔리고 잘 돕니다. 문제는 디버그 열쇠가 빌드하는
             * 컴퓨터마다 다르다는 점입니다 — 깃허브 작업 기계는 매번 새로
             * 만들어 쓰므로, 다음에 만든 앱은 **다른 열쇠로 서명된 다른 앱**이
             * 됩니다. 친구 폰은 그걸 업데이트로 안 받고
             * "패키지가 기존 패키지와 충돌합니다" 하고 거부합니다.
             *
             * 그래서 첫 앱은 이대로 나눠 줘도 되지만, 두 번째부터는
             * key.properties 가 있어야 합니다. 만드는 법은
             * docs/APK.md 에 적어 뒀습니다. */
            signingConfig = if (hasOwnKey) signingConfigs.getByName("release")
                            else signingConfigs.getByName("debug")
        }
    }

    /* x86_64 에서 켜자마자 죽었습니다 (노트북 10번 보고).
     *
     * 앱은 arm 두 가지로만 빌드하는데(apk.yml 의 --target-platform), 플러그인
     * 하나가 lib/x86_64/ 에 파일 둘을 넣어 둡니다. x86_64 기기(에뮬레이터 ·
     * 인텔 크롬북)의 설치기는 그 둘만 보고 x86_64 를 고르고, 정작 Flutter
     * 엔진(libflutter.so)은 없어서 UnsatisfiedLinkError 로 죽습니다.
     * 그 조각을 빼면 설치기가 arm64 를 골라 번역으로 돕니다 — 노트북이
     * `adb install --abi arm64-v8a` 로 확인한 그 길입니다. 실제 폰(arm64)은
     * 영향 없습니다. x86_64 를 통째로 넣는 쪽은 앱이 10MB 넘게 커집니다. */
    packaging {
        jniLibs {
            excludes += listOf("lib/x86_64/**", "lib/x86/**")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
