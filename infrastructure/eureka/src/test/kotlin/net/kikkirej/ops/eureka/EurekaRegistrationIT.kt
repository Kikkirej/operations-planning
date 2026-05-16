package net.kikkirej.ops.eureka

import io.kotest.assertions.withClue
import io.kotest.matchers.shouldBe
import io.kotest.matchers.shouldNotBe
import org.junit.jupiter.api.Test
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.boot.test.web.server.LocalServerPort
import org.springframework.context.annotation.Import
import org.springframework.http.HttpStatus
import org.springframework.web.client.RestTemplate

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@Import(TestSecurityConfig::class)
class EurekaRegistrationIT {

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
