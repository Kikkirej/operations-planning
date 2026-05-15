# Tasks: Core Infrastructure Platform

**Input**: Design documents from `specs/001-core-infrastructure/`

**Prerequisites**: plan.md ✅ | spec.md ✅ | research.md ✅ | data-model.md ✅ | contracts/ ✅ | quickstart.md ✅

**TDD**: Mandatory per Constitution §II. Integration test tasks are included for each
user story and MUST be written before the corresponding implementation tasks are marked
complete. Tests MUST fail before implementation.

**Docker-First**: Mandatory per Constitution §IX. All tests execute inside Docker via
`docker build --target test`. No local JVM or Gradle required. Multi-stage Dockerfiles
(`builder` → `test` → `runtime`) are required for every custom service.

**Organization**: Tasks are grouped by user story to enable independent implementation
and testing of each story.

## Format: `[ID] [P?] [Story?] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: User story this task belongs to (US1–US5)

---

## Phase 1: Setup

**Purpose**: Repository structure, build system initialization, and CI pipeline

- [x] T001 Create monorepo directory scaffold: `infrastructure/{eureka,config-server,spring-boot-admin,keycloak,kafka,traefik}/`, `deployment/{compose,helm/core-infrastructure/charts/}`, `docs/infrastructure/`, `contracts/{events,capabilities}/`, `.github/workflows/`
- [x] T002 Initialize Gradle root project with Kotlin DSL: `build.gradle.kts`, `settings.gradle.kts` (include subprojects eureka, config-server, spring-boot-admin), `gradle/libs.versions.toml` (Kotlin 2.1.x, Spring Boot 3.4.x, Spring Cloud 2024.x, JUnit 5, Kotest, Testcontainers)
- [x] T003 [P] Configure `infrastructure/eureka/build.gradle.kts` (spring-cloud-starter-netflix-eureka-server, spring-boot-starter-security, spring-boot-starter-oauth2-resource-server, spring-boot-starter-actuator)
- [x] T004 [P] Configure `infrastructure/config-server/build.gradle.kts` (spring-cloud-config-server, spring-cloud-starter-bus-kafka, spring-boot-starter-security, spring-boot-starter-actuator)
- [x] T005 [P] Configure `infrastructure/spring-boot-admin/build.gradle.kts` (spring-boot-admin-starter-server, spring-cloud-starter-netflix-eureka-client, spring-boot-starter-oauth2-client, spring-boot-starter-security, spring-boot-starter-actuator)
- [x] T006 Create `deployment/compose/.env.example` with all required variables: `KEYCLOAK_ADMIN`, `KEYCLOAK_ADMIN_PASSWORD`, `KC_DB_USERNAME`, `KC_DB_PASSWORD`, `CONFIG_SERVER_USERNAME`, `CONFIG_SERVER_PASSWORD`, `CONFIG_REPO_PATH` — all values set to clearly marked placeholder strings
- [x] T007 Create `.github/workflows/build-images.yml`: GitHub Actions workflow triggering on push to all branches and PRs to `main`; matrix job over `[eureka, config-server, spring-boot-admin]` with `docker/setup-buildx-action`; step 1 runs `docker build --target test -f infrastructure/${{ matrix.service }}/Dockerfile .` (CI gate — failure blocks merge); step 2 uses `docker/build-push-action` to build and push `runtime` stage to `ghcr.io/kikkirej/ops/${{ matrix.service }}:${{ github.ref_name }}` with `latest` tag on `main`; GHA layer cache (`cache-from/cache-to: type=gha`); `permissions: contents: read, packages: write`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Shared configuration files, Docker Compose base, and cross-cutting contracts that all user story phases build on

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [x] T008 Create `deployment/compose/docker-compose.yml` skeleton: define `infra-net` and `app-net` bridge networks; declare named volumes for all stateful services (keycloak-postgres-data, kafka-data, opensearch-data)
- [x] T009 [P] Create `infrastructure/kafka/topics.yml` declaring `springCloudBus` (3 partitions, retention 3600000 ms, cleanup-policy: delete, auto.offset.reset: latest) and a placeholder section for application topics with documentation comments
- [x] T010 [P] Create `infrastructure/kafka/init-topics.sh` (POSIX sh): reads each entry in `topics.yml`, calls `kafka-topics.sh --create --if-not-exists --topic <name> --partitions <n> --replication-factor <rf> --config retention.ms=<ms>` for each declared topic; validates Kafka is ready before first attempt; exits non-zero on any topic creation failure
- [x] T011 [P] Create `infrastructure/traefik/traefik.yml`: static config with `docker` provider (watch: true, network: app-net), `websecure` entrypoint (port 443), `web` entrypoint (port 80 → redirect to websecure), self-signed TLS resolver for local dev, Traefik API/dashboard enabled on port 8080 (insecureAPI: true for local dev)
- [x] T012 [P] Create `infrastructure/keycloak/realm-export.json` skeleton: `operations` realm, access token lifespan 300 s, refresh token lifespan 1800 s, OIDC settings, empty `clients`/`roles`/`users` arrays (completed in Phase 5)
- [x] T013 Add Keycloak-PostgreSQL service to `deployment/compose/docker-compose.yml`: image `postgres:17-alpine`, named volume `keycloak-postgres-data`, health check (`pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}` interval 10 s / timeout 5 s / retries 5), env vars `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD` from `.env`, network infra-net only
- [x] T014 [P] Create `contracts/events/spring-cloud-bus-refresh.json` at repo root (adapt from design artifact `specs/001-core-infrastructure/contracts/spring-cloud-bus-refresh.json`): CloudEvents-compatible JSON Schema with fields `type` (const: `RefreshRemoteApplicationEvent`), `timestamp` (epoch ms), `originService`, `destinationService` (default `**`), `id` (UUID); required before Phase 4 bus work (Constitution §VIII)
- [x] T015 [P] Create `contracts/capabilities/README.md` at repo root (adapt from `specs/001-core-infrastructure/contracts/capabilities.md`): document capability keys `config` (config-server), `tracing` (jaeger, optional), `log-aggregation` (logstash, optional) with publishing service, detection mechanism, and graceful degradation guidance; required before Phase 4 bus work (Constitution §VIII)

**Checkpoint**: Base structure ready. All user story phases can now begin in priority order.

---

## Phase 3: User Story 1 — Developer Registers a New Service (Priority: P1) 🎯 MVP

**Goal**: A stub service can register with Eureka, become routable through Traefik, and be
visible in Spring Boot Admin within 30 seconds of startup.

**Independent Test**: Stand up only Eureka, Traefik, and Spring Boot Admin. Register a
stub service. Verify it appears in Eureka, is reachable via Traefik route within 30 s,
and is visible in Spring Boot Admin.

### Tests for User Story 1

> **Write FIRST — must FAIL before implementation starts**
> Run via: `docker build --target test -f infrastructure/eureka/Dockerfile .`

- [x] T016 [US1] Write integration test `infrastructure/eureka/src/test/kotlin/net/kikkirej/ops/eureka/EurekaRegistrationIT.kt`: start Eureka via Testcontainers, register a stub service via Eureka REST API, assert it appears in Eureka instances response within 30 s
- [x] T017 [P] [US1] Write integration test `deployment/compose/test-traefik-routing.sh` (POSIX sh): start Eureka + Traefik via `docker compose up`, register a stub service container with Traefik labels, assert it is reachable through the Traefik route at `https://stub.ops.local` within 30 s (covers US1.AcceptanceScenario.2 and SC-002)
- [x] T018 [P] [US1] Write integration test `infrastructure/spring-boot-admin/src/test/kotlin/net/kikkirej/ops/admin/SbaDiscoveryIT.kt`: start SBA + Eureka via Testcontainers, register a stub service exposing `/actuator/health` and `/actuator/metrics`, assert health status and metrics appear in SBA REST API within 60 s

### Implementation for User Story 1

- [x] T019 [US1] Implement `infrastructure/eureka/src/main/kotlin/net/kikkirej/ops/eureka/EurekaServerApplication.kt`: annotate `@SpringBootApplication @EnableEurekaServer`, minimal Spring Boot entry point
- [x] T020 [US1] Create `infrastructure/eureka/src/main/resources/application.yml`: port 8761, `eureka.client.register-with-eureka: false`, `eureka.client.fetch-registry: false`, Eureka dashboard enabled, `eureka.server.eviction-interval-timer-in-ms: 30000`
- [x] T021 [US1] Create `infrastructure/eureka/Dockerfile`: three-stage — stage `builder` (`gradle:8-jdk21-alpine`, copies root build files + eureka subproject, runs `gradle :eureka:bootJar --no-daemon`); stage `test` (extends builder, runs `gradle :eureka:test --no-daemon` — CI gate via `docker build --target test`); stage `runtime` (`eclipse-temurin:21-jre-alpine`, copies JAR from builder, `USER 1001`, `EXPOSE 8761`, `HEALTHCHECK` wget `/actuator/health`)
- [x] T022 [US1] Add Eureka service to `deployment/compose/docker-compose.yml`: build from `infrastructure/eureka/` (target: runtime), port 8761, health check on `/actuator/health`, networks `infra-net` and `app-net`, `traefik.enable=false` (Eureka is internal only)
- [x] T023 [US1] Implement `infrastructure/spring-boot-admin/src/main/kotlin/net/kikkirej/ops/admin/SpringBootAdminApplication.kt`: annotate `@SpringBootApplication @EnableAdminServer @EnableDiscoveryClient`
- [x] T024 [US1] Create `infrastructure/spring-boot-admin/src/main/resources/application.yml`: port 8090, Eureka client `service-url.defaultZone: http://eureka:8761/eureka/`, SBA `eureka.instance.metadata-map.user.name` and `user.password` for actuator access
- [x] T025 [US1] Create `infrastructure/spring-boot-admin/Dockerfile`: three-stage — stage `builder` (`gradle:8-jdk21-alpine`, runs `gradle :spring-boot-admin:bootJar --no-daemon`); stage `test` (extends builder, runs `gradle :spring-boot-admin:test --no-daemon` — CI gate); stage `runtime` (`eclipse-temurin:21-jre-alpine`, copies JAR from builder, `USER 1001`, `EXPOSE 8090`, `HEALTHCHECK` wget `/actuator/health`)
- [x] T026 [US1] Add Spring Boot Admin service to `deployment/compose/docker-compose.yml`: build from `infrastructure/spring-boot-admin/` (target: runtime), depends on `eureka` (condition: service_healthy), networks `infra-net` and `app-net`, Traefik labels for `admin.ops.local` on `websecure`
- [x] T027 [P] [US1] Write `docs/infrastructure/eureka/README.md`: purpose, configuration reference (port, eviction settings), Eureka client setup for new services, startup/shutdown procedure, troubleshooting (service not appearing, stale instances)
- [x] T028 [P] [US1] Write `docs/infrastructure/traefik/README.md`: purpose, Docker label routing guide (required labels, hostname pattern `<service>.ops.local`), TLS setup for local dev, Kubernetes IngressRoute pattern, startup/shutdown, troubleshooting (route not found)
- [x] T029 [P] [US1] Write `docs/infrastructure/spring-boot-admin/README.md`: purpose, Eureka discovery setup, Keycloak login note (Phase 5), actuator endpoint requirements, startup/shutdown, troubleshooting (SBA login loop, missing services)

**Checkpoint**: `docker compose up eureka traefik spring-boot-admin` → stub service registers, routable via Traefik, visible in SBA. User Story 1 independently verified.

---

## Phase 4: User Story 2 — Developer Retrieves Centralised Configuration (Priority: P1)

**Goal**: A client service fetches per-profile configuration from Config Server on startup
and can reload it platform-wide via a single Spring Cloud Bus refresh call.

**Independent Test**: Deploy Config Server with a file-mounted config repo and Kafka. A
client fetches correct profile config on startup; a bus refresh updates values without restart.

### Tests for User Story 2

> **Write FIRST — must FAIL before implementation starts**
> Run via: `docker build --target test -f infrastructure/config-server/Dockerfile .`

- [x] T030 [US2] Write integration test `infrastructure/config-server/src/test/kotlin/net/kikkirej/ops/config/ConfigFetchIT.kt`: start Config Server + Kafka via Testcontainers with a temp config repo bind-mount; assert client receives correct property values for `default` and `dev` profiles; assert HTTP 401 on missing Basic auth credentials
- [x] T031 [US2] Write integration test `infrastructure/config-server/src/test/kotlin/net/kikkirej/ops/config/BusRefreshIT.kt`: update a config file in the temp repo, call `POST /actuator/busrefresh` with Basic auth, assert a subscribed client service receives the `RefreshRemoteApplicationEvent` on `springCloudBus` Kafka topic and reloads the updated value without service restart

### Implementation for User Story 2

- [x] T032 [US2] Implement `infrastructure/config-server/src/main/kotlin/net/kikkirej/ops/config/ConfigServerApplication.kt`: annotate `@SpringBootApplication @EnableConfigServer`; Spring Cloud Bus Kafka auto-configured via `spring-cloud-starter-bus-kafka`
- [x] T033 [US2] Create `infrastructure/config-server/src/main/resources/application.yml`: port 8888, native file-system backend (`spring.cloud.config.server.native.searchLocations: file:/config`), Spring Security Basic auth on all endpoints (username/password from env), Spring Cloud Bus Kafka `bootstrap-servers` from `${KAFKA_BOOTSTRAP_SERVERS}`, Eureka client registration, `spring.cloud.bus.id: config-server`
- [x] T034 [US2] Create `infrastructure/config-server/Dockerfile`: three-stage — stage `builder` (`gradle:8-jdk21-alpine`, runs `gradle :config-server:bootJar --no-daemon`); stage `test` (extends builder, runs `gradle :config-server:test --no-daemon` — CI gate via `docker build --target test`); stage `runtime` (`eclipse-temurin:21-jre-alpine`, copies JAR from builder, `USER 1001`, `EXPOSE 8888`, `HEALTHCHECK` wget `/actuator/health`)
- [x] T035 [US2] Add Config Server service to `deployment/compose/docker-compose.yml`: build from `infrastructure/config-server/` (target: runtime), bind-mount `${CONFIG_REPO_PATH}:/config:ro`, depends on `eureka` (healthy) and `kafka` (healthy), env vars `SPRING_SECURITY_USER_NAME`, `SPRING_SECURITY_USER_PASSWORD`, `KAFKA_BOOTSTRAP_SERVERS=kafka:9092`, Traefik labels for `config.ops.local` on `websecure`
- [x] T036 [US2] Add Kafka service to `deployment/compose/docker-compose.yml`: image `apache/kafka:3.9`, KRaft env vars (`KAFKA_PROCESS_ROLES=broker,controller`, `KAFKA_NODE_ID=1`, `KAFKA_CONTROLLER_QUORUM_VOTERS=1@kafka:9093`, `KAFKA_AUTO_CREATE_TOPICS_ENABLE=false`, `KAFKA_LOG_DIRS=/var/lib/kafka/data`), named volume `kafka-data`, health check on `kafka-topics.sh --list`; separate `kafka-init` service (depends on `kafka: healthy`) runs `init-topics.sh` and exits 0
- [x] T037 [P] [US2] Write `docs/infrastructure/config-server/README.md`: purpose, config repo layout (`<appName>[-<profile>].yml`), Basic auth setup, bus refresh procedure (`POST /actuator/busrefresh`), profile guide (default/dev/prod), Docker-first build note (`docker build --target test`), startup/shutdown, troubleshooting (401, missing profile, stale config)

**Checkpoint**: `docker compose up eureka config-server kafka` → config fetched correctly; bus refresh event propagates. User Story 2 independently verified.

---

## Phase 5: User Story 3 — Operator Secures All Service Endpoints via Keycloak (Priority: P1)

**Goal**: All service endpoints require Keycloak-issued tokens. Realm auto-imports on first
start. Forced password change on first login. Zero-trust enforcement across all services.

**Independent Test**: Deploy Keycloak with realm auto-imported. Unauthenticated → 401.
Authenticated → 200. Default admin login → forced password change prompt. Token for wrong realm → 401.

### Tests for User Story 3

> **Write FIRST — must FAIL before implementation starts**
> Run via: `docker build --target test -f infrastructure/spring-boot-admin/Dockerfile .`

- [x] T038 [US3] Write integration test `infrastructure/spring-boot-admin/src/test/kotlin/net/kikkirej/ops/admin/SbaKeycloakIT.kt`: start SBA + Eureka + Keycloak via Testcontainers; verify unauthenticated access to SBA UI redirects to Keycloak login (HTTP 302); verify user with `sba-admin` role receives HTTP 200 after OAuth2 login; verify user without `sba-admin` role receives HTTP 403
- [x] T039 [P] [US3] Write integration test `infrastructure/keycloak/test/realm-import-test.sh` (POSIX sh using `curl` against a Docker-started Keycloak): start Keycloak with realm export mounted; assert `operations` realm exists via admin REST API; assert clients `eureka-server`, `config-server`, `spring-boot-admin` present; assert default user has `UPDATE_PASSWORD` required action; assert token request for default user fails until password changed

### Implementation for User Story 3

- [x] T040 [US3] Complete `infrastructure/keycloak/realm-export.json`: add clients (`eureka-server` machine-to-machine, `config-server` machine-to-machine, `spring-boot-admin` authorization_code with standard flow), roles (`sba-admin`, `platform-user`), one default admin user with `UPDATE_PASSWORD` required action and placeholder credentials, OIDC token settings (access token 300 s, refresh 1800 s)
- [x] T041 [US3] Add Keycloak service to `deployment/compose/docker-compose.yml`: image `keycloak/keycloak:26`, `depends_on: keycloak-postgres (healthy)`, bind-mount `infrastructure/keycloak/realm-export.json:/opt/keycloak/data/import/realm-export.json:ro`, command includes `--import-realm`, env: `KC_DB=postgres`, `KC_DB_URL`, `KC_DB_USERNAME`, `KC_DB_PASSWORD`, `KC_PROXY=edge`, `KC_HOSTNAME_STRICT=false`, Traefik labels for `auth.ops.local` on `websecure`, networks `infra-net` and `app-net`
- [x] T042 [US3] Implement `infrastructure/spring-boot-admin/src/main/kotlin/net/kikkirej/ops/admin/SecurityConfig.kt`: Spring Security `@Configuration @EnableWebSecurity`; configure `oauth2Login` targeting Keycloak `operations` realm; custom `GrantedAuthoritiesMapper` mapping Keycloak realm role `sba-admin` → `ROLE_sba-admin`; HTTP security: all SBA paths require `ROLE_sba-admin`, `/actuator/health` and `/actuator/info` permit unauthenticated
- [x] T043 [US3] Update `infrastructure/spring-boot-admin/src/main/resources/application.yml`: add `spring.security.oauth2.client.registration.keycloak` (client-id: `spring-boot-admin`, client-secret from env, scope: `openid profile email roles`, grant-type: `authorization_code`) and `spring.security.oauth2.client.provider.keycloak.issuer-uri: ${KEYCLOAK_URL}/realms/operations`
- [x] T044 [P] [US3] Update `infrastructure/eureka/src/main/resources/application.yml`: add `spring.security.oauth2.resourceserver.jwt.issuer-uri: ${KEYCLOAK_URL}/realms/operations`; configure Spring Security to require JWT on Eureka REST API endpoints (`/eureka/**`); permit unauthenticated on `/actuator/health` and `/actuator/info`
- [x] T045 [P] [US3] Update `infrastructure/config-server/src/main/resources/application.yml`: retain HTTP Basic auth for config fetch endpoints; add `spring.security.oauth2.resourceserver.jwt.issuer-uri` for actuator endpoints; explicitly secure `/actuator/busrefresh` with Basic auth (see plan.md Complexity Tracking for §VI exception rationale)
- [x] T046 [P] [US3] Write `docs/infrastructure/keycloak/README.md`: purpose, realm management (export/import workflow, updating realm-export.json), client registration guide, forced password change setup, zero-trust model overview, startup/shutdown, troubleshooting (realm not imported, token errors, H2 not used)

**Checkpoint**: Full auth stack works. Unauthenticated requests rejected. Realm auto-imported. User Story 3 independently verified.

---

## Phase 6: User Story 4 — Developer Publishes and Consumes Async Events via Kafka (Priority: P2)

**Goal**: Services publish events to named Kafka topics and consumers receive them within
5 seconds. Consumer resumes from last offset after restart with no event loss.

**Independent Test**: Deploy Kafka (KRaft). Produce a test event; consumer receives it
within 5 s. Restart consumer; verify offset resume with no loss.

### Tests for User Story 4

> **Write FIRST — must FAIL before implementation starts**

- [x] T047 [US4] Write integration test `infrastructure/kafka/test/kafka-end-to-end-test.sh` (POSIX sh using Docker): start Kafka KRaft via `docker run apache/kafka:3.9`, produce an event to `springCloudBus` topic, assert consumer receives within 5 s; stop consumer, produce second event, restart consumer, assert second event received from last committed offset with no loss

### Implementation for User Story 4

- [x] T048 [US4] Finalize `infrastructure/kafka/topics.yml` with complete initial topic set: `springCloudBus` (3 partitions, retention 1 h, reset: latest) and any platform-level event topics identified in `contracts/events/`; document each topic's purpose, partition count, retention policy, replication factor (1 for Compose, 3 for Kubernetes)
- [x] T049 [US4] Harden `infrastructure/kafka/init-topics.sh`: accept `--replication-factor` arg (default 1; parameterizable for Kubernetes via env `KAFKA_REPLICATION_FACTOR`); add `kafka-topics.sh --bootstrap-server` readiness wait loop (max 60 s, retry every 5 s); validate each topic creation via `--describe`; print summary on success; exit non-zero on any failure with descriptive message
- [x] T050 [P] [US4] Write `docs/infrastructure/kafka/README.md`: purpose, KRaft configuration (key env vars), topic management (topics.yml workflow, adding new topics), consumer group conventions (`group.id = service application name`, manual commit), startup/shutdown, troubleshooting (topic not found, init script failure)

**Checkpoint**: Kafka topics pre-created; end-to-end event delivery verified within 5 s. User Story 4 independently verified.

---

## Phase 7: User Story 5 — Operator Deploys the Full Platform Stack (Priority: P2)

**Goal**: `docker compose up` starts all 7 core services and passes health checks within
2 minutes. `helm install` reaches readiness within 3 minutes. Observability profile starts
4 additional services on demand without affecting the core stack.

**Independent Test**: Cold `docker compose up`; all services healthy within 2 min.
`docker compose --profile observability up`; Jaeger + OpenSearch stack healthy within 3 min.
`docker compose up` (no profile) starts 0 observability services.

### Tests for User Story 5

> **Write FIRST — must FAIL before implementation starts**

- [x] T051 [US5] Write end-to-end smoke test `deployment/compose/test-compose.sh` (POSIX sh, run from a Docker container with Docker CLI access): `docker compose up -d`; poll `/actuator/health` for all 7 core services; assert all healthy within 120 s; re-run with `--profile observability` and assert Jaeger (16686), OpenSearch (9200), Logstash (5044), OpenSearch Dashboards (5601) also healthy within 180 s; assert `docker compose up` without profile returns 0 observability containers

### Implementation for User Story 5

- [x] T052 [US5] Add optional `observability` Docker Compose profile to `deployment/compose/docker-compose.yml`: Jaeger (`jaegertracing/all-in-one:2`, ports 4317/4318/16686, in-memory storage, `profiles: [observability]`); Logstash (`opensearchproject/logstash-oss-with-opensearch-output-plugin:8`, port 5044, `profiles: [observability]`); OpenSearch (`opensearchproject/opensearch:2`, port 9200, `DISABLE_SECURITY_PLUGIN=true`, named volume `opensearch-data`, `profiles: [observability]`); OpenSearch Dashboards (`opensearchproject/opensearch-dashboards:2`, port 5601, `profiles: [observability]`); all `depends_on: opensearch (healthy)` where appropriate
- [x] T053 [US5] Create Helm umbrella chart at `deployment/helm/core-infrastructure/Chart.yaml`: name `core-infrastructure`, version `0.1.0`, declare sub-chart dependencies for eureka, config-server, keycloak, kafka, traefik, spring-boot-admin, jaeger, opensearch, logstash, opensearch-dashboards — each with a `condition:` flag
- [x] T054 [US5] Create `deployment/helm/core-infrastructure/values.yaml`: all core sub-charts enabled, `replicas: 1` for all, observability sub-charts disabled by default (`jaeger.enabled: false`, `opensearch.enabled: false`, `logstash.enabled: false`, `opensearch-dashboards.enabled: false`), resource requests sized for 10–50 service instances; custom service images reference `ghcr.io/kikkirej/ops/<service>:latest`
- [x] T055 [US5] Create `deployment/helm/core-infrastructure/values.observability.yaml`: override to enable all observability sub-charts (`jaeger.enabled: true`, `opensearch.enabled: true`, `logstash.enabled: true`, `opensearch-dashboards.enabled: true`)
- [x] T056 [P] [US5] Create Eureka Helm sub-chart at `deployment/helm/core-infrastructure/charts/eureka/`: `Deployment` (1 replica, image `ghcr.io/kikkirej/ops/eureka:latest`), `Service` (ClusterIP port 8761), `ConfigMap` for `application.yml` overrides, readiness probe `GET /actuator/health` port 8761
- [x] T057 [P] [US5] Create Config Server Helm sub-chart at `deployment/helm/core-infrastructure/charts/config-server/`: `Deployment` (image `ghcr.io/kikkirej/ops/config-server:latest`), `Service` (ClusterIP port 8888), `PersistentVolumeClaim` for config repo mount, `Secret` for Basic auth credentials
- [x] T058 [P] [US5] Create Keycloak Helm sub-chart at `deployment/helm/core-infrastructure/charts/keycloak/`: `Deployment` with `--import-realm` arg, `Service` (ClusterIP port 8080), `ConfigMap` for `realm-export.json`, `Secret` for admin and DB credentials, PostgreSQL sub-dependency with `PersistentVolumeClaim`
- [x] T059 [P] [US5] Create Kafka Helm sub-chart at `deployment/helm/core-infrastructure/charts/kafka/`: `StatefulSet` (1 replica), `Service` (headless + ClusterIP), `PersistentVolumeClaim`, init `Job` that runs `init-topics.sh` via `initContainers` before any producer connects; `KAFKA_REPLICATION_FACTOR=3` for Kubernetes
- [x] T060 [P] [US5] Create Traefik Helm sub-chart at `deployment/helm/core-infrastructure/charts/traefik/`: `Deployment`, `Service` (type: LoadBalancer, ports 80/443), `IngressClass`, `ClusterRole` + `ClusterRoleBinding` for Ingress watching, `ConfigMap` for `traefik.yml`
- [x] T061 [P] [US5] Create Spring Boot Admin Helm sub-chart at `deployment/helm/core-infrastructure/charts/spring-boot-admin/`: `Deployment` (image `ghcr.io/kikkirej/ops/spring-boot-admin:latest`), `Service` (ClusterIP port 8090), `Secret` for Keycloak client secret, readiness probe on `/actuator/health`
- [x] T062 [P] [US5] Create Jaeger Helm sub-chart (disabled by default) at `deployment/helm/core-infrastructure/charts/jaeger/`: `Deployment` (all-in-one image), `Service` (ports 4317/4318/16686), `PersistentVolumeClaim` for Badger storage, `condition: jaeger.enabled`
- [x] T063 [P] [US5] Create OpenSearch Helm sub-chart (disabled by default) at `deployment/helm/core-infrastructure/charts/opensearch/`: `StatefulSet` (1 replica), `Service`, `PersistentVolumeClaim`, `SecurityContext` (`DISABLE_SECURITY_PLUGIN=true` for dev), `condition: opensearch.enabled`
- [x] T064 [P] [US5] Create Logstash Helm sub-chart (disabled by default) at `deployment/helm/core-infrastructure/charts/logstash/`: `Deployment`, `Service` (port 5044), `ConfigMap` for pipeline config (Beats input → OpenSearch output), `condition: logstash.enabled`
- [x] T065 [P] [US5] Create OpenSearch Dashboards Helm sub-chart (disabled by default) at `deployment/helm/core-infrastructure/charts/opensearch-dashboards/`: `Deployment`, `Service` (port 5601), env `OPENSEARCH_HOSTS`, `condition: opensearch-dashboards.enabled`
- [x] T066 [P] [US5] Write `docs/infrastructure/jaeger/README.md`: purpose, enabling the observability profile (`--profile observability`), OTLP endpoint (gRPC 4317, HTTP 4318), service instrumentation guide (Micrometer Tracing + OTEL), Jaeger UI (port 16686), startup/shutdown
- [x] T067 [P] [US5] Write `docs/infrastructure/opensearch/README.md`: purpose, index management (`ops-logs-YYYY.MM.DD`), OpenSearch Dashboards access, log retention (30-day ILM default), security note (`DISABLE_SECURITY_PLUGIN` for dev), startup/shutdown
- [x] T068 [P] [US5] Write `docs/infrastructure/logstash/README.md`: purpose, pipeline config (Beats input → OpenSearch output), log shipping guide (Logback TCP appender via `logstash-logback-encoder`), input port 5044, startup/shutdown
- [x] T069 [P] [US5] Write `docs/infrastructure/opensearch-dashboards/README.md`: purpose, accessing the Dashboards UI (port 5601), creating the default index pattern (`ops-logs-*`), enabling the observability profile, startup/shutdown, troubleshooting (covers FR-011 for OpenSearch Dashboards)

**Checkpoint**: Full stack deployable via single command in both environments. Observability optional. All CI/CD images built and pushed. User Story 5 independently verified.

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Security hardening, contract completeness, CI compliance, quickstart validation

- [x] T070 [P] Audit all Dockerfiles for three-stage compliance (Constitution §IX): verify each `infrastructure/{eureka,config-server,spring-boot-admin}/Dockerfile` has named stages `builder`, `test`, and `runtime`; run `docker build --target test -f infrastructure/<service>/Dockerfile .` for each service and confirm clean pass; verify `runtime` stage runs as non-root `USER 1001`
- [x] T071 [P] Verify `contracts/events/spring-cloud-bus-refresh.json` at repo root matches the final Spring Cloud Bus event structure observed in BusRefreshIT.kt; update schema fields if any drift detected during integration testing
- [x] T072 [P] Verify and finalize `contracts/capabilities/README.md` at repo root: confirm `tracing` and `log-aggregation` capability keys are accurate after Phase 7 observability implementation; add any new capability keys discovered during implementation
- [x] T073 Run quickstart validation: execute all commands in `specs/001-core-infrastructure/quickstart.md` against a clean environment; fix any discrepancies; verify SC-006 — demonstrate a developer can onboard a new stub service (config, discovery, gateway, monitoring) by adding configuration only with no platform code changes
- [x] T074 [P] Add credential rotation warnings to all `docs/` pages referencing default passwords (keycloak, config-server); ensure `deployment/compose/.env.example` values are clearly marked as placeholder secrets that MUST be rotated before any non-localhost exposure
- [x] T075 Run `/speckit-analyze` cross-artifact consistency check before creating PR

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately; T007 (GitHub Actions) can be done first
- **Foundational (Phase 2)**: Depends on Setup — BLOCKS all user story phases
- **US1 (Phase 3)**: Depends on Foundational — first P1 story
- **US2 (Phase 4)**: Depends on Foundational — can parallel US1 if team allows
- **US3 (Phase 5)**: Depends on US1 and US2 (Keycloak auth layered onto running services)
- **US4 (Phase 6)**: Depends on Foundational — Kafka is independent of Keycloak
- **US5 (Phase 7)**: Depends on US1–US4 being complete (full stack to package)
- **Polish (Phase 8)**: Depends on all user story phases

### User Story Dependencies

| Story | Depends On | Notes |
|-------|-----------|-------|
| US1 (P1) | Foundational | Independent — Eureka + Traefik + SBA |
| US2 (P1) | Foundational | Independent — Config Server + Kafka |
| US3 (P1) | US1 + US2 | Keycloak auth overlaid on running services |
| US4 (P2) | Foundational | Independent — Kafka can be verified standalone |
| US5 (P2) | US1 + US2 + US3 + US4 | Packages the complete stack |

### Within Each User Story

1. Write tests → confirm they FAIL via `docker build --target test` (Red)
2. Implement → confirm tests PASS via `docker build --target test` (Green)
3. Refactor → tests still pass
4. Write docs in parallel with implementation (both touch different files → [P])

---

## Parallel Opportunities

### Phase 3 (US1) — after T019

```
Parallel group (different files):
  T017 test-traefik-routing.sh
  T018 SbaDiscoveryIT.kt
  T020 Eureka application.yml
  T023 SBA Application.kt
  T027 docs/infrastructure/eureka/
  T028 docs/infrastructure/traefik/
  T029 docs/infrastructure/spring-boot-admin/
```

### Phase 5 (US3) — parallelize security updates

```
Parallel group (different services):
  T044 Eureka JWT resource server config
  T045 Config Server JWT + Basic auth config
  T046 docs/infrastructure/keycloak/
```

### Phase 7 (US5) — Helm sub-charts and docs are independent files

```
Parallel group (all independent):
  T056 Eureka sub-chart         T066 docs/jaeger/
  T057 Config Server sub-chart  T067 docs/opensearch/
  T058 Keycloak sub-chart       T068 docs/logstash/
  T059 Kafka sub-chart          T069 docs/opensearch-dashboards/
  T060 Traefik sub-chart
  T061 SBA sub-chart
  T062 Jaeger sub-chart
  T063 OpenSearch sub-chart
  T064 Logstash sub-chart
  T065 OpenSearch Dashboards sub-chart
```

---

## Implementation Strategy

### MVP First (User Stories 1–3 only)

1. Phase 1: Setup (including GitHub Actions CI — T007 — so images are built from day one)
2. Phase 2: Foundational
3. Phase 3: US1 → verify service registration independently
4. Phase 4: US2 → verify config delivery independently
5. Phase 5: US3 → verify security independently (depends on US1+US2)
6. **STOP and VALIDATE**: Full secured core platform running locally; CI pushing images

### Incremental Delivery

- After US1: Discovery + routing + monitoring verified; CI building Eureka + SBA images ✓
- After US2: Centralised config + broadcast refresh verified; CI building Config Server ✓
- After US3: Zero-trust security fully enforced ✓
- After US4: Async event streaming verified ✓
- After US5: Full Helm + observability deployment verified ✓

### Parallel Team Strategy

After Phase 2 (Foundational):
- **Developer A**: US1 (Eureka + Traefik + SBA)
- **Developer B**: US2 (Config Server + Spring Cloud Bus)
- **Developer C**: US4 (Kafka hardening)
- US3 and US5 require synchronisation (US3 on top of US1+US2; US5 packaging all)

---

## Notes

- `[P]` tasks touch different files — no merge conflicts when run in parallel
- `[USn]` maps each task to its user story for traceability
- Constitution §II (TDD): all test tasks MUST be written and confirmed failing before implementation
- Constitution §IX (Docker-First): run `docker build --target test -f infrastructure/<service>/Dockerfile .` to execute tests; no local JDK/Gradle required
- GitHub Actions CI (`T007`) runs the `test` stage on every push; a failing test stage blocks merge
- Commit after each task or logical group using `/speckit-git-commit`
- Run `/speckit-analyze` before raising a PR
- Keycloak and Kafka are not Eureka clients; availability is checked via health endpoints and connection retry
- Config Server uses HTTP Basic auth instead of OIDC client credentials — see plan.md Complexity Tracking for the documented §VI exception rationale
