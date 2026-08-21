plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.aiboxingcoach.boxing_coach"
    compileSdk = flutter.compileSdkVersion
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
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")

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
