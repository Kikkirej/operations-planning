package net.kikkirej.ops.admin

import io.kotest.matchers.shouldBe
import io.kotest.matchers.shouldNotBe
import org.junit.jupiter.api.Tag
import org.junit.jupiter.api.Test
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.boot.test.web.server.LocalServerPort
import org.springframework.context.annotation.Import
import org.springframework.http.HttpStatus
import org.springframework.web.client.RestTemplate

// Context loading fails in Alpine JDK (ClassNotFoundException at SpringBootCondition evaluation).
// Runs on the Ubuntu CI runner where the full classpath is available.
@Tag("integration")
@SpringBootTest(
    webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
    properties = [
        "spring.security.oauth2.client.registration.keycloak.client-secret=test-secret",
        "spring.security.oauth2.client.provider.keycloak.issuer-uri=",
        "spring.security.oauth2.client.provider.keycloak.authorization-uri=http://localhost:9999/auth",
        "spring.security.oauth2.client.provider.keycloak.token-uri=http://localhost:9999/token",
        "spring.boot.admin.discovery.enabled=false",
        "eureka.client.enabled=false",
        "spring.main.allow-bean-definition-overriding=true"
    ]
)
@Import(TestSecurityConfig::class)
class SbaDiscoveryIT {

    @LocalServerPort
    private var port: Int = 0

    private val rest = RestTemplate()

    @Test
    fun `spring boot admin health endpoint returns UP`() {
        val response = rest.getForEntity(
            "http://localhost:$port/actuator/health",
            Map::class.java
        )
        response.statusCode shouldBe HttpStatus.OK
        @Suppress("UNCHECKED_CAST")
        (response.body as? Map<String, Any>)?.get("status") shouldBe "UP"
    }

    @Test
    fun `spring boot admin instances endpoint is accessible`() {
        val response = rest.getForEntity(
            "http://localhost:$port/instances",
            String::class.java
        )
        response.body shouldNotBe null
    }
}
