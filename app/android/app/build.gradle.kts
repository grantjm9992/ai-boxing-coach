import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing is driven by a gitignored `android/key.properties` (see
// android/.gitignore). Without it — CI, a fresh clone, `flutter run --debug` —
// the release build falls back to the debug keys so nothing breaks. To produce
// a Play-uploadable AAB, create the keystore and key.properties (see
// docs/RELEASE_SIGNING.md).
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        load(FileInputStream(keystorePropertiesFile))
    }
}
val hasReleaseKeystore = keystorePropertiesFile.exists()

android {
    namespace = "com.aiboxingcoach.boxing_coach"
    // Google Play requires new apps/updates to target Android 16 (API 36) from
    // 2026-08-31. compileSdk is pinned to match; both need the SDK 36 platform
    // installed locally (`sdkmanager "platforms;android-36"`).
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.aiboxingcoach.boxing_coach"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // v0.5: the camera plugin needs 21; MediaPipe Tasks Vision (stage 0.3)
        // needs 24. Set it once here so pose work does not force a second bump.
        minSdk = maxOf(24, flutter.minSdkVersion)
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        // Only wired when key.properties is present; otherwise the release build
        // uses the debug keys (below) so local/CI builds keep working.
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Real upload key when key.properties exists, debug keys otherwise.
            // Play rejects debug-signed uploads, so a store build MUST have it.
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }

            // Flutter release builds run R8. Without these keep rules R8 strips
            // com.google.protobuf message fields that MediaPipe reads by
            // reflection ("Field platform_ ... not found").
            //
            // proguard-rules.pro also carries `-dontoptimize`: R8's method
            // inlining collapses the stack frames Google Flogger walks inside
            // MediaPipe's Graph static initializer, throwing "no caller found on
            // the stack" -> ExceptionInInitializerError -> NoClassDefFoundError:
            // com.google.mediapipe.framework.Graph. (AGP 8.3+ rejects the
            // non-optimizing proguard-android.txt, so we disable optimization in
            // our own rules instead.)
            isMinifyEnabled = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
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
