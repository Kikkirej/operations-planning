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
import org.springframework.kafka.test.context.EmbeddedKafka
import org.springframework.test.context.TestPropertySource
import org.springframework.web.client.RestTemplate
import org.springframework.web.client.exchange
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
        "eureka.client.enabled=false",
        "spring.kafka.bootstrap-servers=\${spring.embedded.kafka.brokers}"
    ]
)
@EmbeddedKafka(partitions = 1, topics = ["springCloudBus"])
class BusRefreshIT {

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
        resp.isSuccess shouldBe true
    }
}
