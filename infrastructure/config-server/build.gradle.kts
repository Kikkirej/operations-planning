plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.kotlin.spring)
    alias(libs.plugins.spring.boot)
    alias(libs.plugins.spring.dependency.management)
}

kotlin {
    jvmToolchain(21)
}

dependencyManagement {
    imports {
        mavenBom(libs.spring.cloud.dependencies.get().toString())
        mavenBom(libs.testcontainers.bom.get().toString())
    }
}

dependencies {
    implementation("org.springframework.cloud:spring-cloud-config-server")
    implementation("org.springframework.cloud:spring-cloud-starter-bus-kafka")
    implementation("org.springframework.boot:spring-boot-starter-security")
    implementation("org.springframework.boot:spring-boot-starter-actuator")
    implementation("org.jetbrains.kotlin:kotlin-reflect")

    testImplementation("org.springframework.boot:spring-boot-starter-test")
    testImplementation(libs.testcontainers.junit.jupiter)
    testImplementation(libs.testcontainers.kafka)
    testImplementation(libs.kotest.runner.junit5)
    testImplementation(libs.kotest.assertions.core)
    testImplementation(libs.kotest.extensions.spring)
}

tasks.withType<Test> {
    useJUnitPlatform {
        val skipDockerTests = System.getenv("SKIP_DOCKER_TESTS") == "true"
        val onlyIntegration = project.hasProperty("onlyIntegration")
        when {
            onlyIntegration -> includeTags("integration")
            skipDockerTests -> excludeTags("integration")
        }
    }
}
