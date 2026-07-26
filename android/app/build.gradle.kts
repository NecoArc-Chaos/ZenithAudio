plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "io.qzz.luolingy.zenithaudio"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "io.qzz.luolingy.zenithaudio"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = if (File("$projectDir/key.properties").exists()) {
                val keystoreProperties = java.util.Properties()
                keystoreProperties.load(java.io.FileInputStream("$projectDir/key.properties"))
                val storeFilePath = keystoreProperties.getProperty("storeFile") ?: ""
                val storePassword = keystoreProperties.getProperty("storePassword") ?: ""
                val keyAlias = keystoreProperties.getProperty("keyAlias") ?: ""
                val keyPassword = keystoreProperties.getProperty("keyPassword") ?: ""

                signingConfigs.create("release") {
                    storeFile = file(storeFilePath)
                    storePassword = storePassword
                    keyAlias = keyAlias
                    keyPassword = keyPassword
                }
            } else {
                signingConfigs.getByName("debug")
            }
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
