plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

android {
    namespace = "com.staydriv.app"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        val customAppId = project.findProperty("appId") as String?
        applicationId = customAppId ?: "com.staydriv.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        val customAppLabel = project.findProperty("appLabel") as String?
        manifestPlaceholders["appLabel"] = customAppLabel ?: (if (applicationId == "com.staydriv.pilot") "StayDriv Pilot" else "StayDriv")
    }

    signingConfigs {
        create("release") {
            keyAlias = "upload"
            keyPassword = "staydriv123"
            storeFile = file("upload-keystore.jks")
            storePassword = "staydriv123"
        }
    }

    buildTypes {
        debug {
            // Configure debug build to use the release signing config
            signingConfig = signingConfigs.getByName("release")
        }
        release {
            // Configure release build to use the release signing config
            signingConfig = signingConfigs.getByName("release")
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
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
