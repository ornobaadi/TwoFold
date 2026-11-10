import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing: android/key.properties holds the upload key and is never
// committed. Without it, release builds use the debug key for local installs.
val keyProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}

android {
    namespace = "com.ornobaadi.twofold"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.ornobaadi.twofold"
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

    buildFeatures {
        resValues = true
    }

    signingConfigs {
        if (keyProperties.isNotEmpty()) {
            create("upload") {
                keyAlias = keyProperties.getProperty("keyAlias")
                keyPassword = keyProperties.getProperty("keyPassword")
                storeFile = file(keyProperties.getProperty("storeFile"))
                storePassword = keyProperties.getProperty("storePassword")
            }
        }
    }

    // The Play Store app is the release build. Debug and profile builds are
    // "TwoFold Dev": a different application id and name, so they install next
    // to the Play version with their own library and settings, and never ask to
    // replace it (the signing keys differ).
    buildTypes {
        debug {
            applicationIdSuffix = ".dev"
            resValue("string", "app_name", "TwoFold Dev")
        }
        // `flutter build apk --profile`: optimised like release, signed with the
        // debug key, no shrinking so it builds quickly.
        getByName("profile") {
            applicationIdSuffix = ".dev"
            resValue("string", "app_name", "TwoFold Dev")
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = false
            isShrinkResources = false
            ndk { debugSymbolLevel = "NONE" }
        }
        release {
            resValue("string", "app_name", "TwoFold")
            signingConfig = signingConfigs.getByName(
                if (keyProperties.isNotEmpty()) "upload" else "debug",
            )
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
            // Lets Play Console show readable native crash reports.
            ndk { debugSymbolLevel = "SYMBOL_TABLE" }
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
