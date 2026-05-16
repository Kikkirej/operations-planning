# Implementation Plan: Shared Data Layer (PostgreSQL + Neo4j)

**Branch**: `003-postgres-neo4j-databases` | **Date**: 2026-05-15 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/002-postgres-neo4j-databases/spec.md`

## Summary

Provision a shared application PostgreSQL 17 database (distinct from the Keycloak-PostgreSQL
instance) and a shared Neo4j 5 Community Edition graph database. PostgreSQL enforces
per-service schema isolation via dedicated roles bootstrapped from a shared `app` role;
Neo4j stores only UUID-keyed nodes and typed relationship edges. Both databases are added to
the existing Docker Compose stack and as new sub-charts under the
`deployment/helm/core-infrastructure` umbrella chart. Health checks and log forwarding to
the existing OpenSearch/Logstash stack are included. No custom Spring Boot service is
produced — this feature delivers infrastructure configuration only.

## Technical Context

**Language/Version**: N/A — infrastructure-only; SQL, YAML, and shell scripts only

**Primary Dependencies**:
- `postgres:17-alpine` — matches the Keycloak PostgreSQL version already in Compose
- `neo4j:5-community` — Neo4j 5.x Community Edition (current stable)
- Helm sub-chart pattern matching existing `deployment/helm/core-infrastructure/charts/`

**Storage**:
- Application PostgreSQL: named volume `app-postgres-data` (Compose); PVC (Helm)
- Neo4j: named volume `neo4j-data` (Compose); PVC (Helm)

**Testing**: Shell-based integration test scripts via `docker compose run`; mirrors existing
`infrastructure/kafka/test/kafka-end-to-end-test.sh` and `keycloak/test/realm-import-test.sh`
patterns; no bare-metal toolchain required

**Target Platform**: Linux containers — Docker Engine + Compose (local dev); Kubernetes + Helm (prod)

**Project Type**: Infrastructure (database layer); official OCI images used directly; no custom image built

**Performance Goals**: p99 < 100 ms for single-record PostgreSQL reads/writes and single-hop
Neo4j relationship queries under expected load (SC-001, SC-002)

**Constraints**:
- No hardcoded credentials; all secrets via environment variables
- Neo4j Community Edition only; Enterprise features and clustering out of scope
- Both databases reachable only from within platform networks; no external port exposure (FR-013)
- Single-instance replicas; HA deferred to infrastructure hardening feature

**Scale/Scope**: Single-instance databases; initial deployment; no replication

## Constitution Check

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Specification-First | ✅ PASS | spec.md clarified; 5 clarifications recorded 2026-05-15 |
| II. TDD | ✅ PASS | Integration test scripts required for each acceptance scenario; no unit tests (no custom code) |
| III. Incremental Delivery | ✅ PASS | Stories 1–3 testable with Compose only; Story 4 tests full stack |
| IV. Documentation as Code | ✅ PASS | `docs/infrastructure/postgres/` and `docs/infrastructure/neo4j/` required by FR-014 |
| V. Simplicity | ✅ PASS | Official images; minimal init SQL; no custom abstraction layer added |
| VI. Platform Compliance | ✅ PASS | Databases are always-on infrastructure; no Eureka/OIDC/Traefik wrapping needed for DB containers; internal network only (FR-013) |
| VII. Technology Standards | ✅ PASS | Official OCI images; Helm sub-charts follow existing pattern; container-only deployment |
| VIII. Loose Coupling | ✅ PASS | Databases are platform infrastructure; services connect independently via credentials |
| IX. Docker-First | ✅ PASS | Official images need no multi-stage Dockerfile (no custom build stage); test scripts run via `docker compose run`; no bare-metal toolchain needed |

**No violations — Complexity Tracking table not required.**

## Project Structure

### Documentation (this feature)

```text
specs/002-postgres-neo4j-databases/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
│   └── data-layer.md    # Data layer interaction contract
└── tasks.md             # Phase 2 output (/speckit-tasks — NOT created by /speckit-plan)
```

### Source Code (repository root)

```text
infrastructure/
├── postgres/                              # NEW — application PostgreSQL component
│   ├── init/
│   │   └── 01-init-app-role.sql          # Bootstrap: app role + DB-level grants
│   └── test/
│       ├── postgres-isolation-test.sh    # Integration: schema isolation, UUID PKs, cross-schema rejection
│       └── cross-store-cleanup-test.sh   # Integration: entity deletion leaves no orphans in either store (SC-003)
├── neo4j/                                # NEW — Neo4j graph database component
│   ├── init/
│   │   └── 01-init-constraints.sh        # Bootstrap: entity_uuid_unique constraint via cypher-shell
│   └── test/
│       └── neo4j-relationship-test.sh    # Integration: node CRUD, relationships, idempotency, DETACH DELETE (US2+US3)
└── test-runner/                          # NEW — shared test runner image
    └── Dockerfile                        # Multi-stage: installs psql + cypher-shell on neo4j base

deployment/
├── compose/
│   ├── .env.example                      # UPDATE: add APP_POSTGRES_* and NEO4J_* variables
│   ├── test-data-layer.sh               # NEW: deployment test — startup health, data persistence (SC-004, SC-007)
│   └── docker-compose.yml               # UPDATE: add app-postgres, neo4j, neo4j-init, test-runner services + volumes
└── helm/
    └── core-infrastructure/
        ├── values.yaml                   # UPDATE: add postgres and neo4j value blocks
        └── charts/
            ├── postgres/                 # NEW sub-chart (mirrors keycloak/ structure)
            │   ├── Chart.yaml
            │   ├── templates/
            │   │   ├── _helpers.tpl
            │   │   ├── configmap-init.yaml
            │   │   ├── deployment.yaml
            │   │   ├── pvc.yaml
            │   │   └── service.yaml
            │   └── values.yaml
            └── neo4j/                   # NEW sub-chart
                ├── Chart.yaml
                ├── templates/
                │   ├── _helpers.tpl
                │   ├── deployment.yaml
                │   ├── pvc.yaml
                │   └── service.yaml
                └── values.yaml

docs/
└── infrastructure/
    ├── postgres/
    │   └── README.md                    # NEW — application PostgreSQL docs (FR-014)
    └── neo4j/
        └── README.md                    # NEW — Neo4j docs (FR-014)

contracts/
└── capabilities/
    └── infrastructure.md                # UPDATE: add relational-data + graph-data capability keys
```

**Structure Decision**: Infrastructure-only feature; follows the `infrastructure/<component-name>/`
pattern established by Keycloak, Kafka, and Traefik. No `services/` entry because no application
service is produced. Helm sub-charts mirror the existing pattern (keycloak, kafka, jaeger, etc.).
Capability keys registered in the top-level `contracts/capabilities/infrastructure.md` consistent
with Principle VIII and existing registry format.
