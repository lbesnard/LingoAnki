import java.io.FileInputStream
import java.io.File
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.lingodiary.lingodiary_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.lingodiary.lingodiary_app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            val keystorePropertiesFile = rootProject.file("key.properties")
            var signingConfigured = false

            if (keystorePropertiesFile.exists()) {
                println("Found key.properties file, configuring release signing...")
                val keystoreProperties = Properties()
                keystoreProperties.load(FileInputStream(keystorePropertiesFile))

                val storeFilePath = keystoreProperties["storeFile"] as String
                val storeFileObj = File(projectDir, storeFilePath)

                if (storeFileObj.exists()) {
                    storeFile = storeFileObj
                    storePassword = keystoreProperties["storePassword"] as String
                    keyAlias = keystoreProperties["keyAlias"] as String
                    keyPassword = keystoreProperties["keyPassword"] as String
                    signingConfigured = true
                    println("Release signing configured with keystore: ${storeFileObj.absolutePath}")
                } else {
                    println("ERROR: Keystore file not found at: ${storeFileObj.absolutePath}")
                }
            } else {
                // Fallback to environment variables for local development
                val keystorePath = System.getenv("KEYSTORE_PATH")
                val keystorePassword = System.getenv("KEYSTORE_PASSWORD")
                val keyAliasEnv = System.getenv("KEY_ALIAS")
                val keyPasswordEnv = System.getenv("KEY_PASSWORD")

                if (!keystorePath.isNullOrEmpty() && !keystorePassword.isNullOrEmpty() &&
                    !keyAliasEnv.isNullOrEmpty() && !keyPasswordEnv.isNullOrEmpty()) {
                    val storeFileObj = File(keystorePath)
                    if (storeFileObj.exists()) {
                        storeFile = storeFileObj
                        storePassword = keystorePassword
                        keyAlias = keyAliasEnv
                        keyPassword = keyPasswordEnv
                        signingConfigured = true
                        println("Release signing configured with environment variables, keystore: ${storeFileObj.absolutePath}")
                    } else {
                        println("ERROR: Keystore file not found at: $keystorePath")
                    }
                } else {
                    println("WARNING: No signing configuration found (neither key.properties nor environment variables)")
                }
            }

            if (!signingConfigured) {
                println("ERROR: Release signing not configured! APK will be unsigned or debug-signed.")
                throw GradleException("Release signing configuration is required but not found. Please ensure key.properties exists or environment variables are set.")
            }
        }
    }

    buildTypes {
        getByName("debug") {
            applicationIdSuffix = ".debug"
            versionNameSuffix = "-DEBUG"
            isDebuggable = true
            // Uses auto-generated debug keystore (~/.android/debug.keystore)
        }
        getByName("release") {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}

flutter {
    source = "../.."
}
