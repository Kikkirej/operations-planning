# Implementation Plan: Core Infrastructure Platform

**Branch**: `002-core-infrastructure` | **Date**: 2026-05-15 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/001-core-infrastructure/spec.md`

## Summary

Provision the full platform infrastructure stack — Eureka (service registry), Keycloak +
PostgreSQL (identity/authorisation), Spring Cloud Config Server with Spring Cloud Bus
(centralised configuration + broadcast refresh), Traefik (API gateway), Spring Boot Admin
with Keycloak SSO (monitoring dashboard), and Kafka in KRaft mode (event streaming
backbone) — as OCI-containerised services with Docker Compose and Helm chart deployment
definitions, zero-trust authentication, pre-defined Kafka topics, and an optional Jaeger +
OpenSearch observability profile. All custom Spring Boot services are implemented in
Kotlin. All builds and tests execute inside Docker containers; no local JVM or Gradle
installation is required beyond Docker Engine. Multi-stage Dockerfiles provide reproducible
build, test, and runtime stages. GitHub Actions CI/CD builds and pushes images on every
push. Designed for 10–50 concurrently registered service instances; single replica in
Kubernetes with HA deferred.

## Technical Context

**Language/Version**: Kotlin 2.1.x on JVM 21 LTS for all custom Spring Boot services
(Eureka Server, Config Server, Spring Boot Admin). Third-party images use
vendor-managed JVM versions.

**Primary Dependencies**:
- Spring Boot 3.4.x
- Spring Cloud 2024.x (Eureka Server, Config Server, Bus)
- Spring Security 6.x (OAuth2 Resource Server + OAuth2 Login for SBA)
- Keycloak 26.x (Quarkus-based official image, `keycloak/keycloak:26`)
- Apache Kafka 3.9.x (KRaft mode, `apache/kafka:3.9`)
- Traefik 3.x (`traefik:v3`)
- PostgreSQL 17.x (`postgres:17-alpine`)
- Jaeger 2.x all-in-one — observability profile only (`jaegertracing/all-in-one:2`)
- OpenSearch 2.x + Logstash 8.x + OpenSearch Dashboards 2.x — observability profile only
- Gradle 8.x (Kotlin DSL build files) — executed inside Docker build stage only
- Helm 3.x for Kubernetes deployment

**Storage**:
- PostgreSQL 17.x — Keycloak relational store; named Docker volume / Kubernetes PVC
- Kafka — event log on disk; named Docker volume / Kubernetes PVC
- Jaeger — in-memory trace store for Docker Compose; Badger (embedded) on PVC for Kubernetes
- OpenSearch — log index store; named Docker volume / Kubernetes PVC

**Testing**:
- All tests execute inside Docker containers (Constitution §IX — Docker-First Build).
- JUnit 5 + Kotest for custom Kotlin service unit tests — run via `docker build --target test`
- Spring Boot Test + Testcontainers for integration tests (Keycloak, Config Server, SBA) —
  run via `docker compose run --rm <service>-test` or `docker build --target test`
- Contract tests: HTTP health check + `/actuator` endpoint verification per service
- End-to-end: `docker compose up` smoke test (`deployment/compose/test-compose.sh`) asserting
  all health checks pass within 2 minutes; executed from within a Docker CI container
- Shell integration tests (`realm-import-test.sh`, `test-traefik-routing.sh`,
  `kafka-end-to-end-test.sh`) run from within a Docker container that has Docker CLI access

**Build**:
- All custom service images use multi-stage Dockerfiles (stage 1: `builder` with Gradle + JDK21;
  stage 2: `test` running JUnit/Kotest suite; stage 3: `runtime` with JRE21-alpine, non-root user).
- No local JDK, Gradle, or Spring toolchain required — Docker Engine is the only prerequisite.
- CI builds run via `.github/workflows/build-images.yml` (GitHub Actions):
  - Trigger: push to any branch + pull requests targeting `main`
  - Jobs: build each custom image (eureka, config-server, spring-boot-admin) in parallel
  - Test stage runs automatically inside `docker build --target test`
  - Push to `ghcr.io/kikkirej/ops/<service>:<branch>` on every branch; tag `latest` on `main`

**Target Platform**: Linux x86_64 OCI containers. Local: Docker Compose (Docker Engine
≥ 26). Production: Kubernetes 1.29+ via Helm 3. CI: GitHub Actions (ubuntu-latest runners).

**Performance Goals**:
- Service registers in Eureka and becomes routable via Traefik within 30 s (SC-002)
- Kafka event delivered to active consumer ≤ 5 s under normal load (SC-005)
- Full core stack up via `docker compose up` ≤ 2 min on ≥ 8 GB RAM / 4 CPU (SC-001)
- Observability profile up ≤ 3 min (SC-012)
- All Kubernetes services reach readiness within 3 min post `helm install` (SC-007)
- CI image build for a single service completes within 10 min on GitHub Actions free tier

**Constraints**:
- Custom Spring Boot services implemented in Kotlin (FR-012)
- All builds and tests inside Docker — no bare-metal toolchain requirement (Constitution §IX)
- Multi-stage Dockerfiles: `builder` → `test` → `runtime` for all custom services (Constitution §IX)
- Single replica for all Kubernetes deployments; HA deferred to hardening feature
- Keycloak realm `operations` auto-imported from `infrastructure/keycloak/realm-export.json`
  on first start; manual admin-UI changes are not durable
- Kafka topic auto-creation disabled; topics declared in `infrastructure/kafka/topics.yml`
  and created by init script before any producer/consumer connects
- Traefik: pure routing layer, no rate limiting
- Spring Boot Admin protected by Keycloak OAuth2 Login (role-gated)
- Config refresh via Spring Cloud Bus `/actuator/busrefresh` (Kafka transport)

**Scale/Scope**: 10–50 concurrent service instances. Kafka defaults: 3 partitions,
replication factor 1 (Compose) / 3 (Kubernetes). Eureka: 90 s heartbeat, 3× miss
eviction window.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Specification-First | ✅ PASS | `spec.md` complete: user stories, FRs, clarification sessions |
| II. TDD | ✅ PASS | All acceptance scenarios defined; implementation follows Red-Green-Refactor; tests run inside Docker |
| III. Incremental & Independent Delivery | ✅ PASS | 5 user stories with P1/P2 priorities; each is independently testable |
| IV. Documentation as Code | ✅ PASS | FR-011 mandates `docs/infrastructure/<component>/` for every component |
| V. Simplicity (YAGNI) | ✅ PASS | Observability optional (Docker profile); HA deferred; no speculative extensions |
| VI. Platform Infrastructure Compliance | ✅ PASS | This feature *creates* the platform; Config Server Basic auth exception documented in Complexity Tracking |
| VII. Technology Platform Standards | ✅ PASS | Custom services on Spring Cloud; Traefik exception pre-approved in constitution |
| VIII. Loose Coupling | ✅ PASS | Infrastructure is always-on; contracts/ created before Phase 4; capability registry in Foundational phase |
| IX. Docker-First Build & Test | ✅ PASS | All custom services use multi-stage Dockerfiles; tests run inside Docker; GitHub Actions CI defined |

**Post-Phase-1 re-check**: Re-evaluate after contracts/ and data-model.md are written to
confirm no cross-service hard dependencies were introduced.

## Project Structure

### Documentation (this feature)

```text
specs/001-core-infrastructure/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
└── tasks.md             # Phase 2 output (/speckit-tasks — not created here)
```

### Source Code (repository root)

```text
.github/
└── workflows/
    └── build-images.yml          # CI: build + test + push all custom service images

infrastructure/
├── eureka/                            # Spring Cloud Eureka Server (Kotlin/Spring Boot)
│   ├── src/main/kotlin/net/kikkirej/ops/eureka/
│   │   └── EurekaServerApplication.kt
│   ├── src/main/resources/
│   │   └── application.yml
│   ├── src/test/kotlin/
│   ├── build.gradle.kts
│   └── Dockerfile                     # Multi-stage: builder → test → runtime
├── config-server/                     # Spring Cloud Config Server (Kotlin/Spring Boot)
│   ├── src/main/kotlin/net/kikkirej/ops/config/
│   │   └── ConfigServerApplication.kt
│   ├── src/main/resources/
│   │   └── application.yml
│   ├── src/test/kotlin/
│   ├── build.gradle.kts
│   └── Dockerfile                     # Multi-stage: builder → test → runtime
├── spring-boot-admin/                 # Spring Boot Admin + Keycloak SSO (Kotlin/Spring Boot)
│   ├── src/main/kotlin/net/kikkirej/ops/admin/
│   │   └── SpringBootAdminApplication.kt
│   ├── src/main/resources/
│   │   └── application.yml
│   ├── src/test/kotlin/
│   ├── build.gradle.kts
│   └── Dockerfile                     # Multi-stage: builder → test → runtime
├── keycloak/
│   ├── realm-export.json              # `operations` realm — auto-imported on first start
│   └── test/
│       └── realm-import-test.sh       # Shell integration test (POSIX sh + curl)
├── kafka/
│   ├── topics.yml                     # Canonical topic declarations (name, partitions, retention)
│   ├── init-topics.sh                 # Executed by init container before broker accepts connections
│   └── test/
│       └── kafka-end-to-end-test.sh   # Shell integration test
└── traefik/
    ├── traefik.yml                    # Static config (entrypoints, providers, TLS)
    └── dynamic/                       # Optional static dynamic config snippets

deployment/
├── compose/
│   ├── docker-compose.yml            # Core stack (default) + observability Docker profile
│   ├── .env.example                  # Required environment variable template
│   ├── test-compose.sh               # End-to-end stack health smoke test
│   └── test-traefik-routing.sh       # Traefik routing integration test
└── helm/
    └── core-infrastructure/
        ├── Chart.yaml
        ├── values.yaml                # Default values (single replica, observability disabled)
        ├── values.observability.yaml  # Override: enables Jaeger + OpenSearch stack
        └── charts/                   # One sub-chart per infrastructure component
            ├── eureka/
            ├── config-server/
            ├── keycloak/
            ├── kafka/
            ├── traefik/
            ├── spring-boot-admin/
            ├── jaeger/
            ├── opensearch/
            ├── logstash/
            └── opensearch-dashboards/

docs/
└── infrastructure/
    ├── eureka/
    ├── config-server/
    ├── spring-boot-admin/
    ├── keycloak/
    ├── kafka/
    ├── traefik/
    ├── jaeger/
    ├── opensearch/
    ├── logstash/
    └── opensearch-dashboards/

contracts/
├── events/
│   └── spring-cloud-bus-refresh.json  # Bus refresh event schema (CloudEvents format)
└── capabilities/
    └── README.md                       # Infrastructure capability key registry
```

### Multi-Stage Dockerfile Pattern (all custom services)

Every custom Kotlin/Spring Boot service MUST use this three-stage pattern:

```dockerfile
# Stage 1: Build — compile and produce the fat JAR
FROM gradle:8-jdk21-alpine AS builder
WORKDIR /workspace
COPY gradle/ gradle/
COPY build.gradle.kts settings.gradle.kts gradle.properties* ./
COPY infrastructure/<service>/build.gradle.kts infrastructure/<service>/
COPY infrastructure/<service>/src infrastructure/<service>/src
RUN gradle :<service>:bootJar --no-daemon --parallel

# Stage 2: Test — run the full test suite; image is NOT pushed, used in CI only
FROM builder AS test
RUN gradle :<service>:test --no-daemon --parallel
# docker build --target test → CI fails here if any test fails

# Stage 3: Runtime — minimal JRE image with non-root user
FROM eclipse-temurin:21-jre-alpine AS runtime
RUN addgroup -S appgroup && adduser -S appuser -G appgroup -u 1001
USER 1001
COPY --from=builder /workspace/infrastructure/<service>/build/libs/*.jar /app/app.jar
EXPOSE <port>
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
  CMD wget -qO- http://localhost:<port>/actuator/health || exit 1
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
```

### GitHub Actions CI Workflow

```yaml
# .github/workflows/build-images.yml
name: Build & Push Service Images

on:
  push:
    branches: ["**"]
  pull_request:
    branches: [main]

env:
  REGISTRY: ghcr.io
  IMAGE_PREFIX: ghcr.io/kikkirej/ops

jobs:
  build:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        service: [eureka, config-server, spring-boot-admin]
      fail-fast: false
    permissions:
      contents: read
      packages: write

    steps:
      - uses: actions/checkout@v4

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Log in to GHCR
        uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Run tests (build --target test)
        run: |
          docker build \
            --target test \
            -f infrastructure/${{ matrix.service }}/Dockerfile \
            .

      - name: Build and push runtime image
        uses: docker/build-push-action@v5
        with:
          context: .
          file: infrastructure/${{ matrix.service }}/Dockerfile
          target: runtime
          push: ${{ github.event_name == 'push' }}
          tags: |
            ${{ env.IMAGE_PREFIX }}/${{ matrix.service }}:${{ github.ref_name }}
            ${{ github.ref_name == 'main' && format('{0}/{1}:latest', env.IMAGE_PREFIX, matrix.service) || '' }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
```

**Structure Decision**: Custom Kotlin services (Eureka, Config Server, SBA) each live as
independent Gradle subprojects under `infrastructure/` per the constitution Monorepo
Structure. Third-party pre-built images (Keycloak, Kafka, Traefik, PostgreSQL) are
referenced by image tag only; their configuration files live under the corresponding
`infrastructure/<component>/` directory. All deployment descriptors live under
`deployment/`. CI workflows live under `.github/workflows/`.

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|--------------------------------------|
| Traefik as API gateway (not Spring Cloud Gateway) | Constitution §VII explicitly pre-approves Traefik for the gateway role | Spring Cloud Gateway adds a JVM service, another Eureka registration, and duplicates routing logic already handled by Traefik natively |
| Optional observability profile (4 additional services) | Jaeger + OpenSearch stack adds significant RAM overhead; most developers do not need it daily | Including observability in the default profile would require ≥ 16 GB RAM for local dev; optional profile keeps the default stack lean on ≥ 8 GB machines |
| Config Server uses HTTP Basic auth instead of OIDC client credentials (Constitution §VI) | Spring Cloud Config Server's canonical security mechanism is HTTP Basic auth per the Spring Cloud Config specification. Using OIDC client credentials introduces a bootstrapping circular dependency: Config Server must validate tokens against Keycloak, but services need config from Config Server in order to start — including the Keycloak issuer URI they would use to obtain a token. | OIDC client credentials flow requires Config Server to reach Keycloak's JWKS endpoint before serving any configuration. Any service whose startup configuration is served by Config Server cannot obtain a Keycloak token before it has its configuration, making the client-credentials path unworkable for the config fetch boundary. Basic auth is the only viable option here. |
