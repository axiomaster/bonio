plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
}

android {
    namespace = "ai.axiomaster.boji"
    compileSdk = 36
    
    defaultConfig {
        applicationId = "ai.axiomaster.boji"
        minSdk = 31
        targetSdk = 36
        versionCode = 1
        versionName = "1.0"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    androidResources {
        noCompress += listOf(".lottie")
    }
    @Suppress("DEPRECATION")
    aaptOptions {
        noCompress += listOf(".lottie", "lottie")
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    buildFeatures {
        compose = true
        buildConfig = true
    }
}

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.ui.graphics)
    implementation(libs.androidx.compose.ui.tooling.preview)
    implementation(libs.androidx.compose.material3)
    
    // Lottie for animations
    implementation("com.airbnb.android:lottie:6.3.0")
    implementation("com.airbnb.android:lottie-compose:6.3.0")
    // CardView for Text Bubble container
    implementation("androidx.cardview:cardview:1.0.0")
    // AppCompat for Lottie's AppCompatImageView requirement
    implementation("androidx.appcompat:appcompat:1.6.1")
    // Navigation Compose
    implementation(libs.androidx.navigation.compose)

    // OpenClaw Port Dependencies
    implementation(libs.kotlinx.serialization.json)
    implementation(libs.okhttp)
    implementation(libs.androidx.security.crypto)
    implementation(libs.androidx.webkit)
    implementation(libs.androidx.compose.material.icons.extended)
    implementation(libs.bouncycastle)
    implementation(libs.dnsjava)
    implementation(libs.androidx.exifinterface)
    
    // CameraX
    implementation(libs.androidx.camera.core)
    implementation(libs.androidx.camera.camera2)
    implementation(libs.androidx.camera.lifecycle)
    implementation(libs.androidx.camera.video)
    implementation(libs.androidx.camera.view)

    // Sherpa-ONNX offline speech recognition (native libs in jniLibs/, Kotlin API in source)
    // No Maven dependency needed — uses bundled .so files + com.k2fsa.sherpa.onnx source

    // Markdown
    implementation(libs.commonmark)
    implementation(libs.commonmark.ext.autolink)
    implementation(libs.commonmark.ext.gfm.strikethrough)
    implementation(libs.commonmark.ext.gfm.tables)
    implementation(libs.commonmark.ext.task.listitems)

    testImplementation(libs.junit)
    androidTestImplementation(libs.androidx.junit)
    androidTestImplementation(libs.androidx.espresso.core)
    androidTestImplementation(platform(libs.androidx.compose.bom))
    androidTestImplementation(libs.androidx.compose.ui.test.junit4)
    debugImplementation(libs.androidx.compose.ui.tooling)
    debugImplementation(libs.androidx.compose.ui.test.manifest)
}