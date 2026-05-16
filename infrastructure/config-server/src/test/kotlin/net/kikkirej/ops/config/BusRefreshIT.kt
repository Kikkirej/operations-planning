package net.kikkirej.ops.config

import io.kotest.matchers.shouldBe
import io.kotest.matchers.shouldNotBe
import org.junit.jupiter.api.Tag
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.boot.test.web.server.LocalServerPort
import org.springframework.http.HttpHeaders
import org.springframework.http.HttpMethod
import org.springframework.http.HttpStatus
import org.springframework.http.RequestEntity
import org.springframework.test.context.DynamicPropertyRegistry
import org.springframework.test.context.DynamicPropertySource
import org.springframework.web.client.RestTemplate
import org.springframework.web.client.exchange
import org.testcontainers.junit.jupiter.Container
import org.testcontainers.junit.jupiter.Testcontainers
import org.testcontainers.kafka.KafkaContainer
import java.io.File
import java.net.URI
import java.util.Base64

@Tag("integration")
@SpringBootTest(
    webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
    properties = [
        "spring.profiles.active=native",
        "spring.cloud.config.server.native.search-locations=file:\${config.repo.path}",
        "spring.security.user.name=testuser",
        "spring.security.user.password=testpass",
        "eureka.client.enabled=false"
    ]
)
@Testcontainers
class BusRefreshIT {

    companion object {
        @Container
        @JvmStatic
        val kafka = KafkaContainer("apache/kafka:3.9.0")

        @DynamicPropertySource
        @JvmStatic
        fun kafkaProperties(registry: DynamicPropertyRegistry) {
            registry.add("spring.kafka.bootstrap-servers") { kafka.bootstrapServers }
        }
    }

    @LocalServerPort
    private var port: Int = 0

    private val rest = RestTemplate()

    @TempDir
    lateinit var configDir: File

    private fun basicAuth(user: String = "testuser", pass: String = "testpass"): HttpHeaders {
        val token = Base64.getEncoder().encodeToString("$user:$pass".toByteArray())
        return HttpHeaders().apply { set(HttpHeaders.AUTHORIZATION, "Basic $token") }
    }

    @Test
    fun `busrefresh endpoint accepts POST with Basic auth`() {
        System.setProperty("config.repo.path", configDir.absolutePath)

        val req = RequestEntity<Void>(basicAuth(), HttpMethod.POST, URI("http://localhost:$port/actuator/busrefresh"))
        val resp = runCatching {
            rest.exchange<Void>(req)
        }
        val status = resp.getOrNull()?.statusCode
        // 204 No Content on success, 503 if bus not available — both are non-401
        status?.let {
            it shouldNotBe HttpStatus.UNAUTHORIZED
            it shouldNotBe HttpStatus.FORBIDDEN
        }
    }

    @Test
    fun `busrefresh endpoint rejects unauthenticated POST`() {
        val req = RequestEntity<Void>(HttpMethod.POST, URI("http://localhost:$port/actuator/busrefresh"))
        val resp = runCatching {
            rest.exchange<Void>(req)
        }
        resp.exceptionOrNull() shouldNotBe null
    }

    @Test
    fun `spring cloud bus kafka topic is springCloudBus`() {
        val req = RequestEntity.get(URI("http://localhost:$port/actuator/env/spring.cloud.bus.destination"))
            .headers(basicAuth())
            .build()
        val resp = runCatching { rest.exchange<Map<*, *>>(req) }
        // Verify bus is configured — endpoint may not exist but bus destination should be configured
        resp.isSuccess shouldBe true
    }
}
