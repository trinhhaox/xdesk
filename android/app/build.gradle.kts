plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "vn.xox.xdesk.app"
    compileSdk = 34
    defaultConfig {
        applicationId = "vn.xox.xdesk"
        minSdk = 31
        targetSdk = 36
        versionCode = 9
        versionName = "0.1.9-beta"
    }
    buildFeatures { compose = true }
    // Khoá ký đọc từ biến môi trường do tools/release-android.sh đặt; không bao giờ nằm trong repo.
    val keystorePath: String? = System.getenv("XDESK_KEYSTORE_PATH")
    signingConfigs {
        if (keystorePath != null) {
            create("release") {
                storeFile = file(keystorePath)
                storePassword = System.getenv("XDESK_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("XDESK_KEY_ALIAS")
                keyPassword = System.getenv("XDESK_KEYSTORE_PASSWORD")
            }
        }
    }
    buildTypes {
        // Bản debug (cài bằng Android Studio/adb, ký khoá debug) là app riêng "Xdesk Dev": cài song song với bản phát hành
        // và không bao giờ đè lên nhau. Trước đây hai bản cùng id nên bản phát hành không cập nhật đè được (chữ ký khác).
        debug {
            applicationIdSuffix = ".dev"
            versionNameSuffix = "-dev"
            manifestPlaceholders["appLabel"] = "Xdesk Dev"
        }
        release {
            manifestPlaceholders["appLabel"] = "Xdesk"
            if (keystorePath != null) signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
    testOptions { unitTests.isReturnDefaultValues = true }
}

dependencies {
    implementation(project(":wire"))
    implementation(project(":crypto"))
    implementation(project(":transport"))
    implementation(project(":media"))
    implementation(platform(libs.compose.bom))
    implementation(libs.compose.ui)
    implementation(libs.compose.material3)
    implementation(libs.compose.icons)
    implementation(libs.activity.compose)
    implementation(libs.lifecycle.viewmodel)
    implementation(libs.camerax.core)
    implementation(libs.camerax.camera2)
    implementation(libs.camerax.lifecycle)
    implementation(libs.camerax.view)
    implementation(libs.zxing.core)
    testImplementation(kotlin("test"))
    testImplementation(libs.junit)
}
