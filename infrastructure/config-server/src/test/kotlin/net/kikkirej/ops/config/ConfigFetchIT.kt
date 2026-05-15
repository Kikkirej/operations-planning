package net.kikkirej.ops.config

import io.kotest.matchers.shouldBe
import io.kotest.matchers.shouldNotBe
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.boot.test.web.server.LocalServerPort
import org.springframework.http.HttpHeaders
import org.springframework.http.HttpStatus
import org.springframework.http.RequestEntity
import org.springframework.web.client.RestTemplate
import org.springframework.web.client.exchange
import org.testcontainers.junit.jupiter.Testcontainers
import java.io.File
import java.net.URI
import java.util.Base64

@SpringBootTest(
    webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
    properties = [
        "spring.profiles.active=native",
        "spring.cloud.config.server.native.search-locations=file:\${config.repo.path}",
        "spring.security.user.name=testuser",
        "spring.security.user.password=testpass",
        "spring.cloud.bus.enabled=false",
        "eureka.client.enabled=false"
    ]
)
@Testcontainers
class ConfigFetchIT {

    @LocalServerPort
    private var port: Int = 0

    private val rest = RestTemplate()

    @TempDir
    lateinit var configDir: File

    private fun basicAuthHeader(user: String = "testuser", pass: String = "testpass"): HttpHeaders {
        val token = Base64.getEncoder().encodeToString("$user:$pass".toByteArray())
        return HttpHeaders().apply { set(HttpHeaders.AUTHORIZATION, "Basic $token") }
    }

    @Test
    fun `config server health endpoint returns UP`() {
        val req = RequestEntity.get(URI("http://localhost:$port/actuator/health"))
            .headers(basicAuthHeader())
            .build()
        val resp = rest.exchange<Map<*, *>>(req)
        resp.statusCode shouldBe HttpStatus.OK
        @Suppress("UNCHECKED_CAST")
        (resp.body as? Map<String, Any>)?.get("status") shouldBe "UP"
    }

    @Test
    fun `config fetch returns properties for default profile`() {
        File(configDir, "myapp.yml").writeText("greeting: hello-default\n")
        System.setProperty("config.repo.path", configDir.absolutePath)

        val req = RequestEntity.get(URI("http://localhost:$port/myapp/default"))
            .headers(basicAuthHeader())
            .build()
        val resp = rest.exchange<Map<*, *>>(req)
        resp.statusCode shouldBe HttpStatus.OK
        resp.body shouldNotBe null
    }

    @Test
    fun `unauthenticated config fetch returns 401`() {
        val req = RequestEntity.get(URI("http://localhost:$port/myapp/default"))
            .build()
        val resp = runCatching {
            rest.exchange<Map<*, *>>(req)
        }
        resp.exceptionOrNull() shouldNotBe null
    }

    @Test
    fun `wrong credentials returns 401`() {
        val req = RequestEntity.get(URI("http://localhost:$port/myapp/default"))
            .headers(basicAuthHeader("wrong", "creds"))
            .build()
        val resp = runCatching {
            rest.exchange<Map<*, *>>(req)
        }
        resp.exceptionOrNull() shouldNotBe null
    }
}
