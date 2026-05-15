# Data Model: Core Infrastructure Platform

**Date**: 2026-05-15 | **Branch**: `002-core-infrastructure`

This document describes the configuration entities, runtime state objects, and data
structures that the platform infrastructure manages. There is no single application
database for this feature — each component owns its own storage.

---

## Keycloak Domain

### Realm

| Attribute | Value / Constraint |
|-----------|-------------------|
| Name | `operations` (canonical, fixed) |
| Storage | Keycloak-PostgreSQL |
| Source of truth | `infrastructure/keycloak/realm-export.json` |
| Import trigger | Keycloak first-start `--import-realm` |
| Idempotency | Import skipped if realm already exists |

### Client

| Attribute | Constraint |
|-----------|-----------|
| `clientId` | Unique within realm; one per service (e.g., `eureka-server`, `spring-boot-admin`, `config-server`) |
| `protocol` | `openid-connect` |
| `publicClient` | `false` (confidential) |
| `standardFlowEnabled` | `true` for user-facing clients (SBA); `false` for machine-to-machine |
| `serviceAccountsEnabled` | `true` for machine-to-machine clients |

### User (default accounts)

| Attribute | Constraint |
|-----------|-----------|
| `username` | Defined in realm export |
| `requiredActions` | MUST include `UPDATE_PASSWORD` |
| `credentials` | Placeholder value; MUST be rotated before any non-localhost exposure |
| Token issuance | Blocked until `UPDATE_PASSWORD` action is completed |

### Role

| Attribute | Constraint |
|-----------|-----------|
| `sba-admin` | Required to access Spring Boot Admin UI |
| Additional roles | Defined per service's access control requirements |

---

## Eureka Domain

### Service Instance

| Attribute | Constraint |
|-----------|-----------|
| `appName` | Uppercase application name (e.g., `USER-SERVICE`) |
| `instanceId` | `<host>:<appName>:<port>` |
| `ipAddr` | Container IP within platform network |
| `port` | Service's HTTP port |
| `statusPageUrl` | `/actuator/info` |
| `healthCheckUrl` | `/actuator/health` |
| `homePageUrl` | `/` |
| `metadata` | Map of capability key-value pairs (see `contracts/capabilities/`) |
| Heartbeat interval | 30 s (default); 3 missed heartbeats triggers eviction |
| Registration SLA | Service MUST appear in registry within 30 s of startup |
| Deregistration | Triggered by graceful shutdown hook |

---

## Config Server Domain

### Config Repository Entry

| Attribute | Constraint |
|-----------|-----------|
| File path pattern | `<appName>[-<profile>].yml` |
| Supported profiles | `default`, `dev`, `prod` |
| Mount path (Compose) | Docker bind-mount from host directory |
| Mount path (Kubernetes) | PersistentVolume or ConfigMap |
| Access control | HTTP Basic auth; credentials in environment variables |
| Refresh trigger | `POST /actuator/busrefresh` on Config Server |

### Spring Cloud Bus Refresh Event

Defined in `contracts/events/spring-cloud-bus-refresh.json`.

| Attribute | Value |
|-----------|-------|
| Kafka topic | `springCloudBus` |
| Partitions | 3 |
| Retention | 1 hour |
| Offset reset | `latest` |
| Event type | `RefreshRemoteApplicationEvent` |

---

## Kafka Domain

### Topic

All topics are declared in `infrastructure/kafka/topics.yml`. Topic auto-creation is
disabled (`KAFKA_AUTO_CREATE_TOPICS_ENABLE=false`).

| Field | Constraint |
|-------|-----------|
| `name` | Kebab-case string; globally unique |
| `partitions` | Default 3 (Compose: RF=1, Kubernetes: RF=3) |
| `retentionMs` | Per-topic; `springCloudBus` default 3 600 000 ms (1 h) |
| `cleanupPolicy` | `delete` (default); `compact` for event-sourced topics |

**Minimum declared topics**:

| Topic | Partitions | Retention | Purpose |
|-------|-----------|-----------|---------|
| `springCloudBus` | 3 | 1 h | Spring Cloud Bus refresh events |

Application event topics are declared by each feature as they are introduced.

### Consumer Group

| Attribute | Constraint |
|-----------|-----------|
| `group.id` | One per service; matches service application name |
| `auto.offset.reset` | `earliest` for application topics; `latest` for `springCloudBus` |
| `enable.auto.commit` | `false`; services commit offsets explicitly after processing |

---

## Traefik Domain

### Route (Docker Compose)

Routes are declared as container labels on each service. Traefik watches Docker events
and updates its routing table within seconds of container start.

| Label | Example |
|-------|---------|
| `traefik.enable` | `"true"` |
| `traefik.http.routers.<name>.rule` | `Host(\`<service>.ops.local\`)` |
| `traefik.http.routers.<name>.entrypoints` | `websecure` |
| `traefik.http.routers.<name>.tls` | `"true"` |
| `traefik.http.services.<name>.loadbalancer.server.port` | `<port>` |

### Route (Kubernetes)

Declared as `IngressRoute` CRDs in each service's Helm sub-chart.

---

## Spring Boot Admin Domain

### Monitored Service

SBA discovers services via Eureka. Every registered Spring Boot service that exposes
`/actuator` is visible in SBA automatically.

| Attribute | Source |
|-----------|--------|
| Service name | Eureka `appName` |
| Health status | `/actuator/health` |
| Metrics | `/actuator/metrics` |
| Log level | `/actuator/loggers` |
| Env | `/actuator/env` |

### SBA Keycloak Client

| Attribute | Value |
|-----------|-------|
| `clientId` | `spring-boot-admin` |
| `grantType` | `authorization_code` |
| Required role | `sba-admin` |
| Redirect URI | `{baseUrl}/login/oauth2/code/keycloak` |

---

## Observability Domain (optional profile)

### Trace (Jaeger)

| Attribute | Constraint |
|-----------|-----------|
| Ingest protocol | OTLP gRPC (port 4317) or OTLP HTTP (port 4318) |
| Storage (Compose) | In-memory (ephemeral; traces lost on restart) |
| Storage (Kubernetes) | Badger embedded on PVC |
| Node attributes | `service.name`, `service.version` (set by each service) |
| Span cardinality | No entity attribute data stored in Jaeger; trace IDs only |

### Log Entry (OpenSearch)

| Attribute | Constraint |
|-----------|-----------|
| Index pattern | `ops-logs-YYYY.MM.DD` |
| Required fields | `@timestamp`, `level`, `service`, `message` |
| Ingest path | Service stdout → Logstash → OpenSearch |
| Retention | Configurable (default: 30 days index lifecycle) |

---

## PostgreSQL (Keycloak) Domain

### Database

| Attribute | Value |
|-----------|-------|
| Database name | `keycloak` |
| Owner role | `keycloak` (dedicated role) |
| Application role | Separate read-write role for Keycloak service account |
| Schema management | Managed by Keycloak on startup (`KC_DB_SCHEMA`) |
| Persistence | Named Docker volume (Compose) / PVC (Kubernetes) |

> **Note**: This PostgreSQL instance is exclusively for Keycloak. Application service
> data uses a separate PostgreSQL instance defined in feature `002-postgres-neo4j-databases`.
