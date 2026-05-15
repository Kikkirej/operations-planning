# Research: Core Infrastructure Platform

**Date**: 2026-05-15 | **Branch**: `002-core-infrastructure`

---

## 1. Traefik ↔ Service Discovery Strategy

**Decision**: Traefik uses Docker label-based dynamic routing for Docker Compose and
Kubernetes Ingress / IngressRoute CRDs for Helm. Traefik does not integrate natively
with Eureka; the two operate in parallel.

**Rationale**: Traefik's Docker provider watches container start/stop events and
reads routing metadata from container labels. For Docker Compose, each service container
declares its own `traefik.http.routers.*` and `traefik.http.services.*` labels.
When a service starts, Docker triggers Traefik to add the route automatically — achieving
the "dynamic reload within 30 seconds of registration" acceptance criterion because the
service starts both processes (Eureka registration and Traefik label publication)
simultaneously. For Kubernetes, Traefik acts as an Ingress Controller; routes are
declared via `IngressRoute` CRDs in each service's Helm chart.

**Impact on spec**: FR-002's phrase "dynamic service-discovery-based routing" is
satisfied by label-based routing at container startup, not Eureka polling. The
acceptance scenario in User Story 1 (route available within 30 s of Eureka registration)
holds because both events are triggered by the same container start event.

**Alternatives considered**:
- Traefik + Eureka custom plugin: No production-grade plugin exists; introduces
  an unsupported dependency.
- Spring Cloud Gateway in front of Traefik: Adds a JVM service and another point of
  failure; rejected per constitution §VII.

---

## 2. Kotlin + Spring Boot Version Selection

**Decision**: Kotlin 2.1.x, Spring Boot 3.4.x, Spring Cloud 2024.x (also known as
Spring Cloud Moorgate / 2024.0.x).

**Rationale**: Spring Boot 3.4.x is the current stable GA release on the 3.x line
(JVM 17+ minimum; JVM 21 LTS recommended). Spring Cloud 2024.x is the compatible
release train. Kotlin 2.1.x is the current stable release and is fully compatible
with Spring Boot 3.x and the Kotlin Gradle DSL.

**Key Spring Cloud modules**:
- `spring-cloud-starter-netflix-eureka-server` — Eureka Server
- `spring-cloud-config-server` — Config Server
- `spring-cloud-starter-bus-kafka` — Spring Cloud Bus with Kafka transport
- `de.codecentric:spring-boot-admin-starter-server` — Spring Boot Admin Server

**Alternatives considered**: Spring Boot 3.3.x (previous minor; 3.4.x preferred for
latest security patches and Kotlin coroutine improvements).

---

## 3. Keycloak Realm Auto-Import

**Decision**: Use Keycloak 26.x with the `--import-realm` startup flag (or equivalent
environment variable `KC_IMPORT_REALM_DIR`). The realm export JSON is mounted at
`/opt/keycloak/data/import/` inside the container.

**Rationale**: Keycloak 26.x (Quarkus-based) imports realm files placed in the
`/opt/keycloak/data/import/` directory on first start when the `--import-realm`
option is active. If the realm already exists, import is skipped (idempotent). The
realm export file is version-controlled in `infrastructure/keycloak/realm-export.json`.

**`KC_DB` configuration**: `postgres` with `KC_DB_URL`, `KC_DB_USERNAME`, `KC_DB_PASSWORD`
injected as environment variables. `KC_DB_SCHEMA` can be set to isolate Keycloak schema.

**TLS**: Local development uses `KC_HOSTNAME_STRICT=false` and `KC_PROXY=edge` (TLS
terminated by Traefik). Production uses `KC_PROXY=reencrypt` or `KC_PROXY=passthrough`
depending on cert-manager configuration.

**Realm export required fields** for `operations` realm:
- Clients: one per custom service + `spring-boot-admin`
- Roles: platform roles including `sba-admin`
- Default users: all with `UPDATE_PASSWORD` required action enabled
- Token settings: access token lifespan, refresh token configuration

**Alternatives considered**: Terraform Keycloak provider for realm management (too heavy
for initial setup; export file is simpler and version-controlled).

---

## 4. Spring Boot Admin + Keycloak OAuth2 Login

**Decision**: Configure Spring Boot Admin Server with Spring Security OAuth2 Login
(`spring-boot-starter-oauth2-client`) targeting the Keycloak `operations` realm. Access
to the SBA UI is restricted to users holding the `sba-admin` Keycloak role.

**Rationale**: SBA's admin UI exposes sensitive actuator data (heap dumps, log level
changes, env vars). OAuth2 Login with Keycloak reuses the existing identity provider
and avoids a separate credential system.

**Key configuration**:
```yaml
spring:
  security:
    oauth2:
      client:
        registration:
          keycloak:
            client-id: spring-boot-admin
            client-secret: ${KEYCLOAK_CLIENT_SECRET}
            scope: openid,profile,email,roles
            authorization-grant-type: authorization_code
            redirect-uri: "{baseUrl}/login/oauth2/code/{registrationId}"
        provider:
          keycloak:
            issuer-uri: ${KEYCLOAK_URL}/realms/operations
```

Role extraction requires a custom `GrantedAuthoritiesMapper` or a JWT converter that
maps Keycloak realm roles to Spring Security authorities. SBA's HTTP security config
restricts `/` and sub-paths to `ROLE_sba-admin`.

**SBA discovery**: SBA discovers services via Eureka (Spring Cloud Eureka client
configured on the SBA server). No direct registration from services to SBA is required.

---

## 5. Spring Cloud Bus + Kafka Config Refresh

**Decision**: Spring Cloud Config Server integrates with Spring Cloud Bus using Kafka as
the event transport. A `POST /actuator/busrefresh` on Config Server broadcasts a
`RefreshRemoteApplicationEvent` to the `springCloudBus` Kafka topic. All subscribing
client services reload their configuration.

**Rationale**: Kafka is already a platform component. Bus eliminates the need to call
`/actuator/refresh` individually on each running service instance. Config changes take
effect platform-wide with a single operator action.

**`springCloudBus` topic**: Must be pre-created with 3 partitions, retention 1 h, and
`auto.offset.reset=latest`. Added to `infrastructure/kafka/topics.yml`.

**Bus security**: The `/actuator/busrefresh` endpoint on Config Server is sensitive.
Secure it with Basic auth (same credential scheme used for config repo access) so only
authorised operators can trigger a broadcast refresh.

**Client side**: Each service must include `spring-cloud-starter-bus-kafka` and declare
the same `spring.kafka.bootstrap-servers`. No additional configuration is required beyond
what services already need for Kafka connectivity.

---

## 6. Kafka KRaft Configuration

**Decision**: Kafka 3.9.x in KRaft mode using the official `apache/kafka:3.9` image.
Single-node KRaft (combined broker + controller role) for both Docker Compose and
Kubernetes (single replica).

**Key environment variables**:
```
KAFKA_PROCESS_ROLES=broker,controller
KAFKA_NODE_ID=1
KAFKA_CONTROLLER_QUORUM_VOTERS=1@kafka:9093
KAFKA_LISTENERS=PLAINTEXT://:9092,CONTROLLER://:9093
KAFKA_ADVERTISED_LISTENERS=PLAINTEXT://kafka:9092
KAFKA_AUTO_CREATE_TOPICS_ENABLE=false
KAFKA_LOG_DIRS=/var/lib/kafka/data
```

**Topic init**: An init container (or `docker compose` `depends_on` + `healthcheck`
sequencing) runs `init-topics.sh` which uses the `kafka-topics.sh` CLI to create all
topics declared in `topics.yml` before any producer/consumer connects.

**Pre-defined topics** (initial set):
- `springCloudBus` — 3 partitions, retention 1 h
- Application event topics added by each feature as they are defined

---

## 7. Jaeger Deployment Model

**Decision**: Jaeger 2.x all-in-one (`jaegertracing/all-in-one:2`) for both Docker
Compose (optional profile) and Kubernetes (optional, single-replica pod).

**Rationale**: At ≤ 50 services and development/staging scale, the all-in-one image
(collector + query + UI in one process) is sufficient. Separate Jaeger components
(collector + query + storage backend) are only warranted at high trace volume.
In-memory storage for Docker Compose (no persistence needed in dev); Badger embedded
storage on a PVC for Kubernetes (lightweight, no external dependency).

**Ports**:
- `4317` — OTLP gRPC (ingest from services)
- `4318` — OTLP HTTP (alternative ingest)
- `16686` — Jaeger UI

**Service instrumentation** (out of scope for this feature): Each service adds
`io.micrometer:micrometer-tracing-bridge-otel` and `io.opentelemetry.instrumentation:
opentelemetry-spring-boot-starter` with `OTEL_EXPORTER_OTLP_ENDPOINT` pointing to Jaeger.

---

## 8. OpenSearch + Logstash Stack

**Decision**: OpenSearch 2.x (`opensearchproject/opensearch:2`), Logstash 8.x
(`opensearchproject/logstash-oss-with-opensearch-output-plugin:8`), and OpenSearch
Dashboards 2.x (`opensearchproject/opensearch-dashboards:2`). All three are part of the
optional `observability` Docker Compose profile.

**Log ingestion pipeline**: Services write structured JSON logs to stdout; a Logstash
pipeline reads from Beats (port 5044) or TCP input, transforms, and writes to OpenSearch
via the `logstash-output-opensearch` plugin. Index pattern: `ops-logs-YYYY.MM.DD`.

**OpenSearch security**: OpenSearch ships with its own security plugin. For local
development, `DISABLE_SECURITY_PLUGIN=true` is acceptable. For Kubernetes, security
plugin should be enabled with credentials.

**Service log shipping** (out of scope for this feature): Each service configures a
Logback appender (e.g., `logback-logstash-encoder` TCP appender) or a sidecar Filebeat
agent to forward logs to Logstash.

---

## 9. PostgreSQL for Keycloak

**Decision**: PostgreSQL 17.x (`postgres:17-alpine`). Dedicated instance, not shared
with application services. Schema: `keycloak` (or default `public` with dedicated role).

**Init**: Keycloak creates its own schema on first start when `KC_DB_SCHEMA` is set.
No additional init SQL required beyond the PostgreSQL user/database creation.

**Docker Compose health check**:
```yaml
healthcheck:
  test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]
  interval: 10s
  timeout: 5s
  retries: 5
```

Keycloak `depends_on` with `condition: service_healthy` ensures Keycloak does not
start before PostgreSQL is ready.

---

## 10. Network Topology

**Decision**: Two Docker Compose networks:
- `infra-net` — infrastructure services (Eureka, Config, Traefik, SBA, Kafka, Keycloak, PostgreSQL)
- `app-net` — shared by application services and infrastructure; Eureka, Config, Kafka, Traefik are on both

Traefik's Docker provider monitors `app-net` for routing labels. Keycloak and PostgreSQL
are on `infra-net` only (no direct access from application services; token validation
is indirect via Keycloak's public endpoint through Traefik).

For Kubernetes: a single namespace `ops-platform` with NetworkPolicy restricting
database ports (PostgreSQL 5432, Kafka 9092 internal listener) to service-to-service
within the namespace only.
