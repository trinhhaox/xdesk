plugins {
    id("org.jetbrains.kotlin.jvm")
}

java {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
}

dependencies {
    api(project(":wire"))
    api(project(":crypto"))
    testImplementation(kotlin("test"))
    testImplementation(libs.junit)
}

// Cache của Kotlin compile bị hỏng đầu ra main khi chỉ sửa test (Kotlin 2.0.20 + Gradle 9.7); tắt cache cho các task này.
tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach { outputs.cacheIf { false } }

tasks.withType<Test>().configureEach {
    testLogging { showStandardStreams = true }
    // Test interop với host Mac thật chỉ chạy khi có biến môi trường XDESK_INTEROP_*; truyền qua cho JVM test.
    listOf("XDESK_INTEROP_URI_FILE", "XDESK_INTEROP_REVOKE_URI_FILE", "XDESK_INTEROP_SECONDS").forEach { name ->
        System.getenv(name)?.let {
            environment(name, it)
            outputs.upToDateWhen { false }
            outputs.cacheIf { false }
        }
    }
}
