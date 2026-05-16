package net.kikkirej.ops.eureka

import io.kotest.assertions.withClue
import io.kotest.matchers.shouldBe
import io.kotest.matchers.shouldNotBe
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import org.mockito.ArgumentMatchers.anyString
import org.mockito.BDDMockito.given
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.boot.test.mock.mockito.MockBean
import org.springframework.boot.test.web.server.LocalServerPort
import org.springframework.http.HttpEntity
import org.springframework.http.HttpHeaders
import org.springframework.http.HttpMethod
import org.springframework.http.HttpStatus
import org.springframework.security.oauth2.jwt.Jwt
import org.springframework.security.oauth2.jwt.JwtDecoder
import org.springframework.web.client.RestTemplate
import java.time.Instant

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class EurekaRegistrationIT {

    // Prevents NimbusJwtDecoder from fetching OIDC discovery at startup.
    // Configured below to accept any Bearer token presented by the tests.
    @MockBean
    private lateinit var jwtDecoder: JwtDecoder

    @LocalServerPort
    private var port: Int = 0

    private val rest = RestTemplate()

    @BeforeEach
    fun configureJwt() {
        val jwt = Jwt.withTokenValue("test-token")
            .header("alg", "RS256")
            .claim("sub", "testuser")
            .issuedAt(Instant.now())
            .expiresAt(Instant.now().plusSeconds(3600))
            .build()
        given(jwtDecoder.decode(anyString())).willReturn(jwt)
    }

    @Test
    fun `eureka server starts and exposes apps endpoint`() {
        val headers = HttpHeaders().apply { setBearerAuth("test-token") }
        val response = rest.exchange(
            "http://localhost:$port/eureka/apps",
            HttpMethod.GET,
            HttpEntity<Void>(headers),
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
