package net.kikkirej.ops.eureka

import io.kotest.assertions.withClue
import io.kotest.matchers.shouldBe
import io.kotest.matchers.shouldNotBe
import org.junit.jupiter.api.Test
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.boot.test.mock.mockito.MockBean
import org.springframework.boot.test.web.server.LocalServerPort
import org.springframework.context.annotation.Import
import org.springframework.http.HttpStatus
import org.springframework.security.oauth2.jwt.JwtDecoder
import org.springframework.web.client.RestTemplate

@SpringBootTest(
    webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
    properties = ["spring.main.allow-bean-definition-overriding=true"]
)
@Import(TestSecurityConfig::class)
class EurekaRegistrationIT {

    // Replaces the auto-configured NimbusJwtDecoder so no OIDC discovery HTTP call is made
    // to Keycloak at startup. The TestSecurityConfig permits all, so this mock is never invoked.
    @MockBean
    private lateinit var jwtDecoder: JwtDecoder

    @LocalServerPort
    private var port: Int = 0

    private val rest = RestTemplate()

    @Test
    fun `eureka server starts and exposes apps endpoint`() {
        val response = rest.getForEntity(
            "http://localhost:$port/eureka/apps",
            String::class.java
        )
        response.statusCode shouldBe HttpStatus.OK
        withClue("apps endpoint should return valid response") {
            response.body shouldNotBe null
        }
    }

    @Test
    fun `eureka health endpoint returns UP`() {
        val response = rest.getForEntity(
            "http://localhost:$port/actuator/health",
            Map::class.java
        )
        response.statusCode shouldBe HttpStatus.OK
        @Suppress("UNCHECKED_CAST")
        (response.body as? Map<String, Any>)?.get("status") shouldBe "UP"
    }
}
