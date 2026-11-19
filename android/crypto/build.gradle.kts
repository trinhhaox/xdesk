plugins {
    id("org.jetbrains.kotlin.jvm")
}

java {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
}

dependencies {
    testImplementation(testFixtures(project(":wire")))
    testImplementation(kotlin("test"))
    testImplementation(libs.junit)
}

// Cache của Kotlin compile bị hỏng đầu ra main khi chỉ sửa test (Kotlin 2.0.20 + Gradle 9.7); tắt cache cho các task này.
tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach { outputs.cacheIf { false } }

val testFallbackX25519 = tasks.register<Test>("testFallbackX25519") {
    description = "Chạy toàn bộ test với X25519 thuần Kotlin thay vì XDH của JCA."
    group = "verification"
    val main = sourceSets.test.get()
    testClassesDirs = main.output.classesDirs
    classpath = main.runtimeClasspath
    systemProperty("xdesk.x25519.fallback", "true")
    filter { excludeTestsMatching("*X25519FallbackTest*") }
}
tasks.named("check") { dependsOn(testFallbackX25519) }
