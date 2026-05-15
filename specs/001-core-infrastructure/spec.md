# Feature Specification: Core Infrastructure Platform

**Feature Branch**: `002-core-infrastructure`

**Created**: 2026-05-15

**Status**: Draft (amended 2026-05-15 — Kotlin, zero-trust, Basic auth for Config, realm auto-import, forced password change, optional observability profile: Jaeger + OpenSearch stack)

**Input**: User description: "infrastructure specification. It consists of the following
services: Eureka service discovery, Keycloak identity management and authorization
centrally, spring cloud config server (+ repo with all standard config and pulling them in
from a file mount in docker or kubernetes), traefik, spring boot admin, kafka for events
(async trigger between components). ensure that infrastructure is also documented in the
docs folder. also ensure that these are all part of deployment definition."

## Clarifications

### Session 2026-05-15

- Q: Is distributed tracing or centralized log aggregation in scope for this infrastructure feature? → A: Both — Jaeger for distributed tracing and an OpenSearch-based ELK stack (Logstash → OpenSearch → OpenSearch Dashboards) for log aggregation — are in scope, deployed as an optional Docker Compose profile (`observability`) that is not started by default.
- Q: What is the expected initial number of concurrently registered service instances the platform must support? → A: 10–50 services.
- Q: Should Traefik enforce request rate limiting on inbound API traffic? → A: No — Traefik is routing-only; rate limiting is out of scope for this feature.
- Q: What is the canonical Keycloak realm name? → A: `operations`.
- Q: What is the maximum acceptable p95 latency overhead added by Traefik routing? → A: No explicit Traefik latency SLA for this feature — latency targets are owned by individual services.
- Q: How is access to Spring Boot Admin protected? → A: Keycloak SSO — SBA is a registered Keycloak client in the `operations` realm, access restricted by role.
- Q: Which config refresh mechanism should the platform support? → A: Spring Cloud Bus via Kafka — one bus event broadcasts config refresh to all subscribed services simultaneously.
- Q: How should Kafka topics be created in this platform? → A: Pre-defined via init script — topics declared in a config file and created at stack startup before any service connects.
- Q: Should any infrastructure service run with more than one replica in the Kubernetes Helm deployment? → A: Single replica for all services — HA topology deferred to a dedicated hardening feature.
- Q: What database backend should Keycloak use? → A: PostgreSQL for both Docker Compose and Kubernetes — one consistent config, durable state in all environments.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Developer Registers a New Service (Priority: P1)

A developer has built a new backend service and wants it to be discoverable by other
services, monitored centrally, and reachable through the platform gateway — without
writing any platform-specific boilerplate beyond configuration.

**Why this priority**: Service discoverability and gateway routing are prerequisites for
every other user story and for any feature service to function within the platform.

**Independent Test**: Stand up only Eureka, Traefik, and Spring Boot Admin. Register a
stub service. Verify the stub appears in Eureka, is reachable via Traefik, and is visible
in Spring Boot Admin.

**Acceptance Scenarios**:

1. **Given** a new service is configured with Eureka client settings, **When** the service
   starts, **Then** it appears as a registered instance in the Eureka dashboard within 30
   seconds.
2. **Given** a service is registered in Eureka, **When** a Traefik dynamic configuration
   reload occurs, **Then** the service is reachable via the gateway at its configured
   route within 30 seconds of registration.
3. **Given** a registered service exposes a `/actuator` endpoint, **When** Spring Boot
   Admin polls it, **Then** the service's health, metrics, and log levels are visible in
   the Spring Boot Admin UI.

---

### User Story 2 — Developer Retrieves Centralised Configuration (Priority: P1)

A developer wants all environment-specific configuration (database URLs, feature flags,
credentials references) to be served from a single source of truth rather than bundled
into each service image.

**Why this priority**: Without centralised config, every service must be rebuilt or
restarted to change configuration, breaking the platform's operational model.

**Independent Test**: Deploy Spring Cloud Config Server with a file-mounted config
repository. A client service fetches its configuration on startup and confirms the
correct values are injected.

**Acceptance Scenarios**:

1. **Given** a config repository is mounted (Docker volume or Kubernetes ConfigMap/PVC),
   **When** Config Server starts, **Then** it serves the correct property files for each
   application profile (default, dev, prod) without errors.
2. **Given** Config Server is running, **When** a client service starts with its
   application name and profile, **Then** it receives the correct configuration values
   for that profile within the startup sequence.
3. **Given** a config file is updated in the mounted repository, **When** a Spring Cloud
   Bus refresh event is published to the Kafka bus topic, **Then** all subscribed client
   services receive and activate the updated configuration values without a full service
   restart.

---

### User Story 3 — Operator Secures All Service Endpoints via Keycloak (Priority: P1)

An operator wants all service APIs to require authentication via a central identity
provider so that no service needs to manage its own user store or token issuance.

**Why this priority**: Security is a platform-wide, foundational concern. Services cannot
accept production traffic without it.

**Independent Test**: Deploy Keycloak with the bundled realm config auto-imported. Attempt
unauthenticated access to a stub service (expect 401). Authenticate via Keycloak and retry
(expect 200). Log in with the default admin credentials and verify a forced password-change
prompt appears before access is granted.

**Acceptance Scenarios**:

1. **Given** Keycloak is running with a configured realm, **When** an unauthenticated
   request reaches a protected service endpoint via Traefik, **Then** the request is
   rejected with HTTP 401.
2. **Given** a client presents a valid Keycloak-issued JWT, **When** the request reaches
   a protected service, **Then** the service processes the request and returns the
   expected response.
3. **Given** a JWT has expired, **When** the request reaches a protected service, **Then**
   the service rejects the request with HTTP 401 and does not process it.
4. **Given** Keycloak is configured with roles, **When** a user with insufficient role
   accesses a role-restricted endpoint, **Then** the service returns HTTP 403.
5. **Given** the bundled realm configuration file exists in `infrastructure/keycloak/`,
   **When** Keycloak starts for the first time, **Then** the realm, clients, roles, and
   default users defined in that file are automatically imported with no manual admin-UI
   interaction required.
6. **Given** a default user account defined in the realm config logs in for the first time,
   **When** valid credentials are provided, **Then** Keycloak presents a mandatory
   password-change prompt and MUST NOT grant access until the new password is set.
7. **Given** the zero-trust model, **When** a service calls another service without a
   valid credential (Keycloak token or, for Config Server, Basic auth), **Then** the
   request is rejected regardless of network location — no implicit internal trust exists.
8. **Given** Spring Boot Admin is configured as a Keycloak client in the `operations`
   realm, **When** an unauthenticated user navigates to the SBA UI, **Then** they are
   redirected to Keycloak for login; access is only granted to users holding the
   designated SBA admin role.

---

### User Story 4 — Developer Publishes and Consumes Async Events via Kafka (Priority: P2)

A developer wants services to communicate asynchronously by publishing events to named
topics and having consumer services subscribe to those topics, without tight coupling
between producer and consumer.

**Why this priority**: Async eventing is a secondary concern that builds on top of the
running service mesh. Services can function synchronously until Kafka is available.

**Independent Test**: Deploy Kafka (KRaft mode, no Zookeeper). A producer service publishes
a test event; a consumer service receives it and records receipt. Verify end-to-end
delivery.

**Acceptance Scenarios**:

1. **Given** Kafka is running, **When** a producer service sends an event to a named
   topic, **Then** the event is persisted in Kafka and available for consumers.
2. **Given** a consumer service subscribes to a topic, **When** an event is published,
   **Then** the consumer receives the event within an acceptable latency window
   (≤ 5 seconds under normal load).
3. **Given** a consumer service is temporarily offline, **When** it restarts, **Then** it
   resumes consuming from its last committed offset with no event loss.

---

### User Story 5 — Operator Deploys the Full Platform Stack (Priority: P2)

An operator wants to bring up the entire infrastructure platform with a single command in
both local (Docker Compose) and production-like (Helm/Kubernetes) environments, with
all services connected and healthy.

**Why this priority**: Deployment automation is essential for reproducibility but does not
block individual service development, which can proceed against partial stacks.

**Independent Test**: Run `docker compose up` from `deployment/compose/`. Confirm all
infrastructure services reach a healthy state and pass their health checks within
2 minutes.

**Acceptance Scenarios**:

1. **Given** a correctly configured `deployment/compose/` directory, **When**
   `docker compose up` is executed, **Then** all infrastructure services (Eureka,
   Keycloak, Keycloak-PostgreSQL, Config Server, Traefik, Spring Boot Admin, Kafka)
   start successfully and pass their configured health checks.
2. **Given** a correctly configured Helm umbrella chart in `deployment/helm/`, **When**
   `helm install` is executed against a Kubernetes cluster, **Then** all infrastructure
   services reach `Running` status and pass readiness probes within 3 minutes.
3. **Given** the platform stack is running, **When** any single infrastructure service is
   restarted, **Then** dependent services reconnect automatically without manual
   intervention.
4. **Given** the `observability` Docker Compose profile is activated, **When**
   `docker compose --profile observability up` is executed, **Then** Jaeger, Logstash,
   OpenSearch, and OpenSearch Dashboards start and pass health checks within 3 minutes
   without affecting the core infrastructure services.

---

### Edge Cases

- What happens when Config Server is unavailable at service startup? Services MUST fail
  fast with a clear error rather than starting with empty/default configuration.
- What happens when a service provides incorrect Basic auth credentials to Config Server?
  Config Server MUST reject the request with HTTP 401 and log the attempt.
- What happens when Eureka is unreachable? Services MUST retry registration and log each
  failed attempt; they MUST NOT silently discard registration failures.
- What happens when Keycloak is down? Protected services MUST reject all requests (fail
  closed), not fall back to unauthenticated access.
- What happens if the Keycloak realm import file is malformed or missing on first start?
  Keycloak MUST fail to start and surface a clear error; it MUST NOT start with an empty
  or default realm.
- What happens if Keycloak-PostgreSQL is unavailable when Keycloak starts? Keycloak MUST
  fail to start with a clear database connection error; it MUST NOT fall back to an
  in-memory or embedded store.
- What happens when a service presents a Keycloak token issued for a different realm or
  client? The receiving service MUST reject it with HTTP 401.
- What happens when Kafka is unavailable? Producers MUST surface a clear error; consumers
  MUST retry connection. Neither MUST silently drop events.
- What happens when the Kafka bus topic is unavailable during a config refresh broadcast?
  Config Server MUST surface a clear error on the `/actuator/busrefresh` call; client
  services MUST remain on their last-loaded configuration and MUST NOT crash.
- What happens when a service crashes and re-registers? Eureka MUST evict the stale
  registration and accept the fresh one within the configured eviction window.
- What happens if a default-password account tries to bypass the forced password-change
  prompt (e.g., via direct API token request)? Keycloak MUST block token issuance until
  the required action is completed.
- What happens when the `observability` profile is not active? Services MUST continue to
  function normally; trace export failures MUST be non-fatal (fire-and-forget); log
  shipping errors MUST NOT block service startup or request processing.
- What happens when OpenSearch is unreachable? Logstash MUST buffer events and retry; it
  MUST NOT silently discard log events.
- What happens when Jaeger is unreachable? Services MUST continue operating; trace spans
  are dropped client-side without error propagation to the caller.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The platform MUST provide a service registry (Eureka) that all application
  services register with on startup and deregister from on graceful shutdown.
- **FR-002**: The platform MUST provide a central API gateway (Traefik) that routes all
  inbound external traffic to registered services using dynamic service-discovery-based
  routing. Traefik operates as a pure routing layer; request rate limiting is explicitly
  out of scope for this feature.
- **FR-003**: The platform MUST provide a centralised identity provider (Keycloak) that
  issues and validates OIDC tokens; all protected endpoints MUST require a valid token.
- **FR-004**: The platform MUST provide a centralised configuration server (Spring Cloud
  Config Server) that serves per-application, per-profile property files from a
  file-mounted configuration repository.
- **FR-005**: The configuration repository MUST be mountable as a file-system volume
  (Docker bind mount or Kubernetes PersistentVolume / ConfigMap) so that configuration
  can be updated without rebuilding any container image.
- **FR-006**: The platform MUST provide a monitoring dashboard (Spring Boot Admin) that
  aggregates health, metrics, environment, and log-level information from all registered
  Spring Boot services.
- **FR-007**: The platform MUST provide an event streaming backbone (Kafka) that enables
  services to publish and consume events asynchronously on named topics.
- **FR-008**: Every infrastructure component MUST be packaged as an OCI container image
  and MUST have a corresponding `Dockerfile` (or reference a pre-built official image)
  in the monorepo.
- **FR-009**: All infrastructure components MUST be included in a Docker Compose file
  under `deployment/compose/` suitable for local development and integration testing.
- **FR-010**: All infrastructure components MUST have Helm chart definitions under
  `deployment/helm/` suitable for Kubernetes deployment, including an umbrella chart
  that deploys the full stack.
- **FR-011**: User-facing documentation for each infrastructure component MUST exist
  under `docs/infrastructure/<component-name>/` and MUST cover: purpose, configuration
  reference, startup/shutdown procedure, and troubleshooting.
- **FR-012**: All custom Spring Boot services within `infrastructure/` and `services/`
  MUST be implemented in Kotlin. Third-party or pre-built images (e.g., Keycloak,
  Kafka, Traefik) are exempt as they are not custom-developed services.
- **FR-013**: The platform MUST implement a zero-trust security model. No service MAY
  assume implicit trust based solely on network location. All inter-service communication
  MUST be authenticated:
  - Clients connecting to Config Server MUST authenticate using HTTP Basic authentication
    (username and password configured per service).
  - All other service-to-service and user-to-service communication MUST use
    Keycloak-issued OIDC tokens (client credentials flow for machine-to-machine; authorisation
    code / device flow for user-facing interactions).
  - Internal network placement does NOT grant any implicit access; authentication is
    enforced at the application layer for every request.
- **FR-014**: A Keycloak realm configuration file MUST be stored in `infrastructure/keycloak/`
  and automatically imported on Keycloak's first startup. The realm definition MUST include:
  all service clients, role definitions, default user accounts, and required OIDC settings.
  No manual admin-UI steps MUST be required to achieve a functional security configuration.
- **FR-015**: Every default user and service-account password defined in the bundled realm
  configuration MUST have the "Update Password" required action enabled. Keycloak MUST
  block token issuance for any account with this action pending until a new password is
  set by the user on first login.
- **FR-016**: The platform MUST provide optional distributed tracing via Jaeger (collector
  + query UI). Jaeger MUST be packaged as a Docker Compose service in an `observability`
  profile and MUST NOT start as part of the default profile.
- **FR-017**: The platform MUST provide optional centralized log aggregation via
  Logstash → OpenSearch → OpenSearch Dashboards. These components MUST be packaged in the
  same `observability` Docker Compose profile as Jaeger and MUST NOT start as part of the
  default profile.
- **FR-018**: Both observability components (Jaeger, OpenSearch stack) MUST have
  corresponding Helm chart definitions under `deployment/helm/` with values flags to
  enable or disable each component independently at deploy time.
- **FR-019**: Spring Boot Admin MUST be registered as a dedicated Keycloak client in the
  `operations` realm and MUST enforce role-based access via OAuth2 login (Spring Security
  + Keycloak). Only authenticated users holding the designated SBA admin role MUST be
  granted access to the Admin UI; all other requests MUST be redirected to Keycloak.
- **FR-020**: Config Server MUST integrate with Spring Cloud Bus using Kafka as the event
  transport. A single `/actuator/busrefresh` call on Config Server MUST broadcast a config
  refresh signal to all subscribed client services simultaneously via the Kafka bus topic,
  without requiring individual per-instance `/actuator/refresh` calls.
- **FR-021**: Kafka topics MUST be pre-defined in a versioned configuration file stored at
  `infrastructure/kafka/topics.yml`. An init script or init container MUST create all
  declared topics (with explicit partition count and retention settings) before any
  producer or consumer service connects. Auto-creation MUST be disabled on the Kafka
  broker. This applies to both Docker Compose and Kubernetes deployments.
- **FR-022**: Keycloak MUST use PostgreSQL as its database backend in both Docker Compose
  and Kubernetes deployments; the embedded H2 database MUST NOT be used in any deployment
  target. A dedicated PostgreSQL service MUST be included in `deployment/compose/` and a
  corresponding Helm dependency MUST be included in `deployment/helm/`. The PostgreSQL
  data volume MUST be declared as a named Docker volume (Compose) or PersistentVolumeClaim
  (Kubernetes) to ensure durability across container restarts. Connection credentials MUST
  be supplied via environment variables only.

### Key Entities

- **Realm (Keycloak)**: Logical security boundary containing clients, users, and roles;
  one realm per environment is the standard configuration.
- **Realm Configuration File**: A Keycloak-exported JSON file stored in
  `infrastructure/keycloak/` that defines the complete realm — clients, roles, default
  users, and required actions — and is automatically imported on first startup.
- **Client (Keycloak)**: A registered application or service that uses Keycloak for
  authentication; each service MUST have its own client definition within the realm.
- **Required Action (Keycloak)**: An action a user MUST complete before token issuance
  is permitted; "Update Password" is applied to all default accounts.
- **Service Instance (Eureka)**: A registered entry representing a running service
  process, identified by application name, host, and port.
- **Config Repository**: The file-system directory mounted into Config Server containing
  `<application>[-<profile>].yml` property files; access is protected by Basic auth.
- **Topic (Kafka)**: A named, ordered, append-only log to which producers write events
  and from which consumer groups read. All topics are pre-declared in
  `infrastructure/kafka/topics.yml` and created by an init script at startup; Kafka
  broker auto-creation is disabled.
- **Route (Traefik)**: A mapping from an inbound request rule (host/path) to a backend
  service, configured dynamically via Eureka or static configuration.
- **Spring Cloud Bus**: An event bridge backed by Kafka that broadcasts configuration
  refresh signals from Config Server to all subscribed client services; a single
  `/actuator/busrefresh` call replaces per-instance manual refresh.
- **Jaeger**: Distributed tracing backend (collector + query UI) that collects, stores,
  and visualizes traces from instrumented services; deployed in the optional `observability`
  profile only.
- **OpenSearch**: Search and analytics engine serving as the log storage backend in the
  observability stack (the OpenSearch-native replacement for Elasticsearch).
- **Logstash**: Log ingestion and transformation pipeline that receives structured log
  events from services and indexes them into OpenSearch.
- **OpenSearch Dashboards**: Web-based visualization UI for logs stored in OpenSearch;
  deployed alongside OpenSearch in the `observability` profile.
- **Keycloak-PostgreSQL**: Dedicated PostgreSQL instance providing durable relational
  storage for Keycloak realm data, users, sessions, and client registrations; not shared
  with application services.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: All seven infrastructure services (Eureka, Keycloak, Keycloak-PostgreSQL,
  Config Server, Traefik, Spring Boot Admin, Kafka) start successfully via
  `docker compose up` within 2 minutes on a standard development machine
  (≥ 8 GB RAM, 4 CPU cores).
- **SC-002**: A new service registers in Eureka and becomes routable through Traefik
  within 30 seconds of startup, with no manual gateway reconfiguration required.
- **SC-003**: Configuration changes made to the mounted config repository are consumable
  by client services without rebuilding any container image.
- **SC-004**: An unauthenticated request to any protected endpoint is rejected 100% of
  the time; a validly authenticated request succeeds and reaches the upstream service.
  No Traefik-level latency SLA is defined — response time targets are owned by individual
  services.
- **SC-005**: An event published to Kafka is received by an active consumer within
  5 seconds under normal operating conditions.
- **SC-006**: A developer can onboard a new service into the platform (config, discovery,
  gateway, monitoring) by adding configuration only — no platform code changes required.
- **SC-007**: The full infrastructure stack can be deployed to Kubernetes via Helm with
  all services reaching readiness within 3 minutes.
- **SC-008**: Every infrastructure component has complete user documentation available in
  `docs/infrastructure/` before the feature is considered done.
- **SC-009**: Keycloak starts with the realm fully configured (clients, roles, users,
  required actions) from the bundled realm file with no manual admin-UI interaction;
  verified by attempting login immediately after a clean first start.
- **SC-010**: All default user accounts require a password change on their first login;
  no default password permits full platform access without being changed first.
- **SC-011**: Any request — regardless of its originating network — that lacks valid
  credentials is rejected at the application layer with no data exposure.
- **SC-012**: When `docker compose --profile observability up` is executed, Jaeger,
  Logstash, OpenSearch, and OpenSearch Dashboards all start successfully and pass their
  health checks within 3 minutes.
- **SC-013**: `docker compose up` (default profile, without `--profile observability`)
  completes successfully with no observability components started; no service error or
  dependency failure occurs due to the absent observability stack.

## Assumptions

- All custom Spring Boot services (both in `infrastructure/` and `services/`) are written
  in Kotlin; third-party images (Keycloak, Kafka, Traefik, PostgreSQL) are used as-is.
- Keycloak uses PostgreSQL as its database backend in all deployment targets (Docker
  Compose and Kubernetes). The PostgreSQL instance is dedicated to Keycloak and MUST NOT
  be shared with application services. Credentials are supplied via environment variables;
  data is persisted to a named volume (Compose) or PersistentVolumeClaim (Kubernetes).
- Keycloak realm configuration is maintained as a versioned JSON export in
  `infrastructure/keycloak/realm-export.json`; it is auto-imported via Keycloak's
  `--import-realm` mechanism on first startup. Manual admin-UI-only changes are out of
  scope and MUST be captured back into the export file to be considered durable.
- The bundled realm export defines one realm named `operations` covering all infrastructure
  and application service clients; per-environment realm variants are handled by
  environment-variable overrides in the deployment descriptors, not by maintaining separate
  realm files.
- All default accounts in the realm export have "Update Password" as a required action;
  the initial password values are placeholder secrets and MUST be rotated before any
  environment is exposed beyond localhost.
- Config Server Basic auth credentials (username / password) are provided via environment
  variables injected at deployment time; they are never hardcoded in source files or
  container images.
- The config repository is managed separately (e.g., a dedicated Git repo or a mounted
  directory); this feature provisions the Config Server and the mount mechanism, not the
  config file content for application services.
- Config Server integrates with Spring Cloud Bus using Kafka as the event transport. The
  bus topic name defaults to `springCloudBus` and is configurable via environment variable.
  Client services must include `spring-cloud-starter-bus-kafka` to participate in broadcast
  refresh; this is a service-level dependency, not provisioned by this feature.
- Kafka runs in KRaft mode (no separate Zookeeper) for all new deployments. Topic
  auto-creation is disabled on the broker; all topics are pre-defined in
  `infrastructure/kafka/topics.yml` and provisioned by an init script/container before
  any service connects. The `springCloudBus` topic is included in this file.
- Traefik operates as a reverse proxy in Docker-provider mode for local compose and as
  an Ingress Controller for Kubernetes; no commercial load balancer integration is in
  scope.
- Spring Boot Admin operates in standalone mode; it discovers services via Eureka rather
  than requiring each service to register directly with Admin. SBA is registered as a
  dedicated Keycloak client (`spring-boot-admin`) in the `operations` realm; the realm
  export MUST include this client and the SBA admin role definition.
- TLS termination for local development is handled by Traefik with self-signed certificates;
  production TLS (cert-manager / Let's Encrypt) is configuration, not a code deliverable
  of this feature.
- All infrastructure services run as non-root users inside their containers.
- Network isolation between infrastructure and application service tiers is enforced at
  the Docker Compose / Kubernetes network level; this feature defines the network topology.
- Zero-trust enforcement is at the application layer; network-level controls (firewalls,
  security groups) are considered defence-in-depth and are not a substitute for
  application-layer authentication.
- The observability stack (Jaeger, Logstash, OpenSearch, OpenSearch Dashboards) is
  packaged as a Docker Compose profile named `observability`; it is excluded from the
  default compose profile. Activation requires the explicit flag `--profile observability`.
- Service-side instrumentation for distributed tracing (e.g., Micrometer Tracing with an
  OpenTelemetry exporter) is the responsibility of each individual service; this feature
  provisions only the Jaeger collector and query backend.
- Log shipping from services to Logstash (e.g., via a Logback appender or sidecar
  Filebeat agent) is configured at the service level; this feature provisions the
  Logstash → OpenSearch → OpenSearch Dashboards pipeline only.
- Trace export failures from services to Jaeger are non-fatal; services continue operating
  if the Jaeger backend is unreachable.
- All infrastructure services in the Kubernetes Helm deployment run with a single replica
  (`replicas: 1`). High-availability topology (Keycloak clustering, Eureka peer awareness,
  Kafka multi-broker) is explicitly out of scope for this feature and deferred to a
  dedicated hardening feature.
- The platform is designed to support 10–50 concurrently registered service instances.
  Kafka topics default to 3 partitions with replication factor 1 for local Docker Compose
  and 3 partitions with replication factor 3 for Kubernetes. Eureka eviction uses the
  standard 90-second heartbeat and 3× miss eviction window. Helm chart resource requests
  are sized for this range (no extreme over- or under-provisioning for < 10 or > 200
  service scenarios).
