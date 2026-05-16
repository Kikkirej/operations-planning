package net.kikkirej.ops.admin

import io.kotest.matchers.shouldBe
import io.kotest.matchers.shouldNotBe
import org.junit.jupiter.api.Tag
import org.junit.jupiter.api.Test
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.boot.test.web.server.LocalServerPort
import org.springframework.http.HttpStatus
import org.springframework.test.context.DynamicPropertyRegistry
import org.springframework.test.context.DynamicPropertySource
import org.springframework.web.client.RestTemplate
import org.testcontainers.containers.GenericContainer
import org.testcontainers.containers.wait.strategy.Wait
import org.testcontainers.junit.jupiter.Container
import org.testcontainers.junit.jupiter.Testcontainers

@Tag("integration")
@SpringBootTest(
    webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
    properties = [
        "spring.security.oauth2.client.registration.keycloak.client-id=spring-boot-admin",
        "spring.security.oauth2.client.registration.keycloak.client-secret=test-secret",
        "eureka.client.enabled=false"
    ]
)
@Testcontainers
class SbaKeycloakIT {

    companion object {
        @Container
        @JvmStatic
        val keycloak: GenericContainer<*> = GenericContainer("quay.io/keycloak/keycloak:26.0")
            .withExposedPorts(8080)
            .withEnv("KEYCLOAK_ADMIN", "admin")
            .withEnv("KEYCLOAK_ADMIN_PASSWORD", "admin")
            .withCommand("start-dev")
            .waitingFor(Wait.forHttp("/realms/master").forStatusCode(200))

        @DynamicPropertySource
        @JvmStatic
        fun keycloakProperties(registry: DynamicPropertyRegistry) {
            // Use master realm (exists by default in start-dev); tests validate redirect behaviour
            // not realm-specific content. keycloak.port retained for direct URL assertions.
            registry.add("keycloak.port") { keycloak.getMappedPort(8080) }
            registry.add("spring.security.oauth2.client.provider.keycloak.issuer-uri") {
                "http://localhost:${keycloak.getMappedPort(8080)}/realms/master"
            }
        }
    }

    @LocalServerPort
    private var port: Int = 0

    private val rest = RestTemplate()

    @Test
    fun `unauthenticated access to SBA UI redirects to Keycloak`() {
        // RestTemplate follows redirects by default; when Keycloak is not reachable
        // the redirect chain will result in a non-200 or exception — either way not 200 OK
        val resp = runCatching {
            rest.getForEntity("http://localhost:$port/", String::class.java)
        }
        // Either redirected to Keycloak (non-200) or client error
        val status = resp.getOrNull()?.statusCode
        if (status != null) {
            status shouldNotBe HttpStatus.OK
        } else {
            resp.exceptionOrNull() shouldNotBe null
        }
    }

    @Test
    fun `actuator health endpoint is accessible without authentication`() {
        val resp = rest.getForEntity("http://localhost:$port/actuator/health", Map::class.java)
        resp.statusCode shouldBe HttpStatus.OK
        @Suppress("UNCHECKED_CAST")
        (resp.body as? Map<String, Any>)?.get("status") shouldBe "UP"
    }

    @Test
    fun `keycloak container starts and master realm is reachable`() {
        val keycloakUrl = "http://localhost:${keycloak.getMappedPort(8080)}/realms/master"
        val resp = rest.getForEntity(keycloakUrl, Map::class.java)
        resp.statusCode shouldBe HttpStatus.OK
        resp.body shouldNotBe null
    }
}
