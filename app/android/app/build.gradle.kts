plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

/* 서명 열쇠.
 *
 * 있으면 그걸로 서명하고, 없으면 아래에서 디버그 열쇠로 넘어갑니다.
 * 열쇠 자체는 저장소에 **안 들어갑니다** — 깃허브 Secrets 에 넣어 두고
 * 빌드할 때만 풀어서 씁니다 (.github/workflows/apk.yml 참고).
 */
val keystoreProperties = java.util.Properties().apply {
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
}

flutter {
    source = "../.."
}
