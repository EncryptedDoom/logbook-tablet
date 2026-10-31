import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.logbook.logbook"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.logbook.logbook"
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

    // The team's shared signing key lives outside the repository, in
    // ~/.logbook beside the activation key. With it, a build from any team
    // member's machine installs over any other - and the device code stays the
    // same, since Android derives it partly from the signing key. Without it
    // the build falls back to this machine's own debug key, which works on an
    // emulator but can never update the real tablet.
    val sharedSigning = File(System.getProperty("user.home"), ".logbook/signing.properties")
    if (sharedSigning.exists()) {
        val props = Properties().apply { sharedSigning.inputStream().use { load(it) } }
        signingConfigs.create("shared") {
            storeFile = File(sharedSigning.parentFile, props.getProperty("storeFile"))
            storePassword = props.getProperty("storePassword")
            keyAlias = props.getProperty("keyAlias")
            keyPassword = props.getProperty("keyPassword")
        }
    } else {
        logger.warn("No ~/.logbook/signing.properties: signing with this machine's debug key")
    }
    val teamSigning = signingConfigs.findByName("shared") ?: signingConfigs.getByName("debug")

    buildTypes {
        debug {
            // debug builds too, so `flutter run` can update the tablet
            signingConfig = teamSigning
        }
        release {
            signingConfig = teamSigning
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
