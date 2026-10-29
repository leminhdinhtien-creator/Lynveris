import java.util.Properties
import java.util.Base64

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseKeysFile = rootProject.file("key.properties")
val releaseKeys = Properties()
// Flutter test builds a generated listener target, so inspect its native-report define too.
val integrationBuild = (project.findProperty("dart-defines") as? String).orEmpty()
    .split(",").any { encoded ->
        runCatching { String(Base64.getDecoder().decode(encoded), Charsets.UTF_8) }
            .getOrDefault("").startsWith("INTEGRATION_TEST_SHOULD_REPORT_RESULTS_TO_NATIVE=")
    }
val qaBuild = project.findProperty("lynverisQa") == "true" ||
    (project.findProperty("target") as? String)?.contains("integration_test") == true ||
    integrationBuild
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
        applicationId = if (qaBuild) "vn.lynveris.lynveris.qa" else "vn.lynveris.lynveris"
        manifestPlaceholders["lynverisLabel"] = if (qaBuild) "Lynveris QA" else "Lynveris"
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
