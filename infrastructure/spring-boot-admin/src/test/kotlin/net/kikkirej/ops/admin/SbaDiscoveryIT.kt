package net.kikkirej.ops.admin

import io.kotest.matchers.shouldBe
import io.kotest.matchers.shouldNotBe
import org.junit.jupiter.api.Test
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.boot.test.web.server.LocalServerPort
import org.springframework.http.HttpStatus
import org.springframework.web.client.RestTemplate

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
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
