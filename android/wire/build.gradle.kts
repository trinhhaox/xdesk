plugins {
    id("org.jetbrains.kotlin.jvm")
    `java-test-fixtures`
}

java {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
}

dependencies {
    testFixturesImplementation(libs.junit)
    testImplementation(kotlin("test"))
    testImplementation(libs.junit)
}

// Cache của Kotlin compile bị hỏng đầu ra main khi chỉ sửa test (Kotlin 2.0.20 + Gradle 9.7); tắt cache cho các task này.
tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach { outputs.cacheIf { false } }
