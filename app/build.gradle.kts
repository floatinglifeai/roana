import org.gradle.api.tasks.JavaExec

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.roana.app"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.roana.app"
        minSdk = 31
        targetSdk = 35
        versionCode = 2
        versionName = "0.0.2"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"

        ndk {
            abiFilters += "arm64-v8a"
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        buildConfig = true
    }

    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }
}

kotlin {
    jvmToolchain(17)
}

dependencies {
    implementation("androidx.activity:activity-ktx:1.9.3")
    implementation("androidx.camera:camera-camera2:1.4.1")
    implementation("androidx.camera:camera-core:1.4.1")
    implementation("androidx.camera:camera-lifecycle:1.4.1")
    implementation("androidx.camera:camera-view:1.4.1")
    implementation("androidx.core:core-ktx:1.15.0")
    implementation("com.qualcomm.qti:qnn-runtime:2.46.0")
    implementation("com.qualcomm.qti:qnn-litert-delegate:2.46.0")
    implementation("org.tensorflow:tensorflow-lite:2.17.0")
    testImplementation("junit:junit:4.13.2")
}

tasks.register<JavaExec>("generateCorridorParityFixtures") {
    group = "verification"
    description = "Generate corridor parity fixtures for the Swift iOS port."
    val compileTasks = listOf(
        "compileDebugUnitTestKotlin",
        "compileDebugUnitTestJavaWithJavac",
        "processDebugUnitTestJavaRes",
        "compileDebugKotlin",
        "compileDebugJavaWithJavac",
        "processDebugJavaRes",
    ).map { taskName -> tasks.named(taskName) }
    dependsOn(compileTasks)
    classpath = files(
        configurations.named("debugUnitTestRuntimeClasspath"),
        "$buildDir/tmp/kotlin-classes/debugUnitTest",
        "$buildDir/intermediates/javac/debugUnitTest/classes",
        "$buildDir/tmp/kotlin-classes/debug",
        "$buildDir/intermediates/javac/debug/classes",
    )
    mainClass.set("com.roana.app.parity.CorridorParityFixtureGenerator")
    args(rootProject.layout.projectDirectory.file("parity/corridor-core.json").asFile.absolutePath)
}
