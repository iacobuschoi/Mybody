pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.11.1" apply false
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
    // 앱 알림(FCM) 설정 파일(google-services.json)을 읽는 플러그인. 여기서는 판만 정하고,
    // 적용은 app/build.gradle.kts 가 그 파일이 있을 때만 합니다(공개 저장소라 파일은 CI 비밀).
    id("com.google.gms.google-services") version "4.4.4" apply false
}

include(":app")
