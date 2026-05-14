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
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.lingodiary.lingodiary_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
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
                val keystoreProperties = java.util.Properties()
                keystoreProperties.load(java.io.FileInputStream(keystorePropertiesFile))

                val storeFilePath = keystoreProperties["storeFile"] as String
                val storeFileObj = file(storeFilePath)

                if (storeFileObj.exists()) {
                    storeFile = storeFileObj
                    storePassword = keystoreProperties["storePassword"] as String
                    keyAlias = keystoreProperties["keyAlias"] as String
                    keyPassword = keystoreProperties["keyPassword"] as String
                    signingConfigured = true
                    println("Release signing configured with keystore: ${storeFileObj.absolutePath}")
                } else {
                    println("ERROR: Keystore file not found at: $storeFilePath")
                }
            } else {
                // Fallback to environment variables for local development
                val keystorePath = System.getenv("KEYSTORE_PATH")
                val keystorePassword = System.getenv("KEYSTORE_PASSWORD")
                val keyAliasEnv = System.getenv("KEY_ALIAS")
                val keyPasswordEnv = System.getenv("KEY_PASSWORD")

                if (!keystorePath.isNullOrEmpty() && !keystorePassword.isNullOrEmpty() &&
                    !keyAliasEnv.isNullOrEmpty() && !keyPasswordEnv.isNullOrEmpty()) {
                    val storeFileObj = file(keystorePath)
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
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = false
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}

flutter {
    source = "../.."
}
