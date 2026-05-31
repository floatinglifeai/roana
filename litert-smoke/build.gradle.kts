plugins {
    id("com.android.application")
}

val litertVersion = providers.gradleProperty("litertVersion").orElse("2.1.5").get()
val litertExtraAssetDir = providers.gradleProperty("litertExtraAssetDir")
val litertExtraJniDir = providers.gradleProperty("litertExtraJniDir")
val litertUseOnlyExtraJni =
    providers.gradleProperty("litertUseOnlyExtraJni").map(String::toBoolean).orElse(false).get()

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
            litertExtraAssetDir.orNull?.let { assets.srcDir(it) }
            val jniDirs = mutableListOf<String>()
            if (!litertUseOnlyExtraJni) {
                jniDirs += "src/main/jniLibs"
            }
            litertExtraJniDir.orNull?.let { jniDirs += it }
            jniLibs.setSrcDirs(jniDirs)
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
    implementation("com.google.ai.edge.litert:litert:$litertVersion")
}
