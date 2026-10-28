import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseKeysFile = rootProject.file("key.properties")
val releaseKeys = Properties()
if (releaseKeysFile.exists()) {
    releaseKeysFile.inputStream().use { releaseKeys.load(it) }
}

android {
    namespace = "vn.lynveris.lynveris"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Stable identifier for Lynveris Android builds.
        applicationId = "vn.lynveris.lynveris"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (releaseKeysFile.exists()) {
            create("release") {
                keyAlias = releaseKeys["keyAlias"] as String
                keyPassword = releaseKeys["keyPassword"] as String
                storeFile = file(releaseKeys["storeFile"] as String)
                storePassword = releaseKeys["storePassword"] as String
            }
        }
    }
    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release")
        }
    }
}

gradle.taskGraph.whenReady {
    if (!releaseKeysFile.exists() && allTasks.any { it.name.contains("Release") }) {
        throw GradleException("Release signing required: create android/key.properties; see README. Debug builds need no release key.")
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
