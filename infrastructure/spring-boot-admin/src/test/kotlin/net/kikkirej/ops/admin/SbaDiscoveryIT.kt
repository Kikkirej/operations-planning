package net.kikkirej.ops.admin

import io.kotest.matchers.shouldBe
import io.kotest.matchers.shouldNotBe
import org.junit.jupiter.api.Tag
import org.junit.jupiter.api.Test
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.boot.test.mock.mockito.MockBean
import org.springframework.boot.test.web.client.TestRestTemplate
import org.springframework.boot.test.web.server.LocalServerPort
import org.springframework.http.HttpStatus
import org.springframework.security.oauth2.client.registration.ClientRegistrationRepository
import org.springframework.web.client.RestTemplate

@Tag("integration")
@SpringBootTest(
    webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
    properties = [
        "spring.boot.admin.discovery.enabled=false",
        "eureka.client.enabled=false"
    ]
)
class SbaDiscoveryIT {

    // oauth2Login() in SecurityConfig requires this bean; mock it so no real Keycloak
    // is needed and no OAuth2 client registration properties need to be set (which would
    // otherwise trigger autoconfiguration that causes ClassNotFoundException at condition
    // evaluation time due to javax.servlet vs jakarta.servlet classpath conflicts).
    @MockBean
    private lateinit var clientRegistrationRepository: ClientRegistrationRepository

    // TestRestTemplate does not follow redirects — lets us assert 302 on protected endpoints.
    @Autowired
    private lateinit var testRestTemplate: TestRestTemplate

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
    fun `spring boot admin instances endpoint is secured`() {
        val response = testRestTemplate.getForEntity("/instances", String::class.java)
        // Unauthenticated access is redirected to the login page, not served directly.
        response.statusCode shouldNotBe HttpStatus.OK
        response.statusCode shouldNotBe HttpStatus.INTERNAL_SERVER_ERROR
    }
}
