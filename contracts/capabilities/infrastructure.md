# Infrastructure Capability Registry

**Feature**: Core Infrastructure Platform
**Date**: 2026-05-15

This file registers the Eureka metadata capability keys published by infrastructure
services. Application services MAY declare capabilities using the same mechanism
(see Constitution §VIII).

---

## How Capability Metadata Works

Each service registers capability metadata as key-value pairs in its Eureka registration:

```yaml
eureka:
  instance:
    metadata-map:
      capabilities: "capability-key-1,capability-key-2"
```

A consuming service checks for a required capability at runtime by querying the Eureka
registry for the service and inspecting `metadata.capabilities`. If absent, the consumer
degrades gracefully per Constitution §VIII.

---

## Infrastructure Capability Keys

Infrastructure services publish implicit capabilities by virtue of being registered. The
following keys are reserved for infrastructure use:

| Key | Published By | Meaning |
|-----|-------------|---------|
| `config` | `config-server` | Centralised configuration service is available; clients may fetch configuration and subscribe to bus refresh events |
| `identity` | (Keycloak is not an Eureka client) | Keycloak availability is detected via the Keycloak `/health` endpoint, not Eureka metadata |
| `event-bus` | `kafka` (not an Eureka client) | Kafka event streaming is available; detected via Kafka bootstrap connectivity, not Eureka |
| `tracing` | `jaeger` (optional profile) | Distributed tracing backend is available; services MAY activate OTLP export when this capability is present |
| `log-aggregation` | `logstash` (optional profile) | Centralised log aggregation is available; services MAY activate log shipping when present |
| `relational-data` | `app-postgres` (not an Eureka client) | Shared application PostgreSQL is available; services detect availability via connection retry on `app-postgres:5432` |
| `graph-data` | `neo4j` (not an Eureka client) | Shared Neo4j graph database is available; services detect availability via Bolt connection retry on `neo4j:7687` |

---

## Registering a New Capability

1. Choose a kebab-case key that is unique and descriptive (e.g., `estimation`, `scheduling`).
2. Add an entry to this file with the publishing service, meaning, and any consuming services.
3. Update the publishing service's `application.yml` to include the key in `eureka.instance.metadata-map.capabilities`.
4. Implement graceful degradation in all consuming services for the case when the capability is absent.
5. No API or event contract change is permitted without a corresponding update to `contracts/`.

---

## Notes

- Keycloak and Kafka are not Spring Boot services and therefore do not register with
  Eureka. Their availability is detected by other means (health endpoint polling,
  connection retry).
- The `tracing` and `log-aggregation` capability keys are only published when the
  `observability` Docker Compose profile is active or the corresponding Helm values
  are enabled.
- **`relational-data`** (`app-postgres`): PostgreSQL does not register with Eureka.
  Services detect availability by attempting a TCP connection to `app-postgres:5432`
  with retry backoff. On failure, services MUST fail fast with a clear DB connection
  error — they MUST NOT start with in-memory or empty state (spec FR-002 edge case).
- **`graph-data`** (`neo4j`): Neo4j does not register with Eureka. Services detect
  availability by attempting a Bolt connection to `neo4j:7687` with retry backoff.
  On failure, services MUST surface a clear error on any graph operation — they MUST
  NOT silently skip relationship registration (spec edge case).
