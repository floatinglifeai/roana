plugins {
    id("com.android.application")
}

android {
    namespace = "com.roana.litertsmoke"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.roana.litertsmoke"
        minSdk = 31
        targetSdk = 35
        versionCode = 1
        versionName = "0.0.1"

        ndk {
            abiFilters += "arm64-v8a"
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    sourceSets {
        getByName("main") {
            assets.srcDir("../app/src/main/assets")
        }
    }

    androidResources {
        noCompress += "tflite"
    }

    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }
}

dependencies {
    implementation("com.google.ai.edge.litert:litert:2.1.5")
}
