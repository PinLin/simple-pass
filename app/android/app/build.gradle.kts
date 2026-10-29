import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing credentials live outside the repo (android/key.properties, gitignored).
val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}

android {
    namespace = "me.pinlin.simple_pass"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    buildFeatures {
        // Required since AGP 8: BuildConfig generation is opt-in. Needed so
        // MainActivity can pass BuildConfig.VERSION_CODE to FreeDroidWarn.
        buildConfig = true
    }

    defaultConfig {
        applicationId = "me.pinlin.simple_pass"
        // KeystorePlugin relies on API 30: setUserAuthenticationParameters,
        // and BiometricPrompt accepting BIOMETRIC_STRONG | DEVICE_CREDENTIAL.
        minSdk = 30
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (keystoreProperties.isEmpty) return@create
            storeFile = file(keystoreProperties["storeFile"] as String)
            storePassword = keystoreProperties["storePassword"] as String
            keyAlias = keystoreProperties["keyAlias"] as String
            keyPassword = keystoreProperties["keyPassword"] as String
        }
    }

    buildTypes {
        release {
            if (!keystoreProperties.isEmpty) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

// Checked only once the task graph is known, so debug builds, IDE syncs and
// `flutter test` never need a keystore; a release build must never quietly
// ship with the debug key.
gradle.taskGraph.whenReady {
    val needsReleaseSigning = allTasks.any { it.project == project && it.name.contains("Release") }
    if (needsReleaseSigning && keystoreProperties.isEmpty) {
        throw GradleException(
            "Release signing is not configured: ${rootProject.file("key.properties")} is missing " +
                "or empty. Create it with storeFile, storePassword, keyAlias and keyPassword " +
                "to build a release."
        )
    }
}

flutter {
    source = "../.."
}

dependencies {
    // LaunchTheme/NormalTheme extend Theme.AppCompat.
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("androidx.biometric:biometric:1.1.0")

    // Pinned to an exact tag (not V1.+) for reproducible builds; see https://github.com/woheller69/FreeDroidWarn tags.
    implementation("com.github.woheller69:FreeDroidWarn:V1.13")
}
