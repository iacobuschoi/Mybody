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
