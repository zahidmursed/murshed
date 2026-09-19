import java.util.Properties

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(keystorePropertiesFile.inputStream())
}

/// Secret resolution: **environment variable first** (CI / secret-manager
/// friendly — পাসওয়ার্ড কোনো ফাইলে না রেখেই বিল্ড করা যায়), তারপর local
/// key.properties। নাম দুটোতেই এক: storePassword, keyPassword, keyAlias,
/// storeFile (SECURITY-KEY-ROTATION.md দেখুন)।
fun secret(name: String): String? =
    System.getenv(name)?.takeIf { it.isNotBlank() }
        ?: keystoreProperties.getProperty(name)?.takeIf { it.isNotBlank() }

val hasSigningSecrets =
    listOf("keyAlias", "keyPassword", "storeFile", "storePassword")
        .all { !secret(it).isNullOrBlank() }

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.madrasa.dakhilacamera"
    compileSdk = flutter.compileSdkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.madrasa.dakhilacamera"
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
        create("upload") {
            keyAlias = secret("keyAlias")
            keyPassword = secret("keyPassword")
            storeFile = secret("storeFile")?.let { file(it) }
            storePassword = secret("storePassword")
        }
    }

    buildTypes {
        release {
            // env-ভেরিয়েবল বা key.properties — যেকোনো একটায় সম্পূর্ণ সিক্রেট
            // থাকলে release signing, নইলে debug key (আগের আচরণ অপরিবর্তিত)
            signingConfig = if (hasSigningSecrets) {
                signingConfigs.getByName("upload")
            } else {
                signingConfigs.getByName("debug")
            }
            // APK সাইজ কমাতে (Phase 4)
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
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
