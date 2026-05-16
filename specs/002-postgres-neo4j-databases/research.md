# Research: Shared Data Layer (PostgreSQL + Neo4j)

**Feature**: 002 — Shared Data Layer
**Date**: 2026-05-15

---

## Decision 1 — PostgreSQL Version

**Decision**: `postgres:17-alpine`

**Rationale**: Matches the Keycloak-PostgreSQL image already present in
`deployment/compose/docker-compose.yml` (`postgres:17-alpine`). Using the same major
version across both PostgreSQL instances eliminates version-skew surprises during
operations. PostgreSQL 17 is the current stable release (2024); `alpine` keeps the image
footprint minimal.

**Alternatives considered**:
- `postgres:16-alpine`: previous LTS; no reason to pin to an older version when 17 is stable.
- `postgres:latest`: unacceptable for production — unpinned major version breaks
  reproducibility.

---

## Decision 2 — Neo4j Version and Edition

**Decision**: `neo4j:5-community`

**Rationale**: Neo4j 5.x is the current stable major version. The `5-community` tag tracks
the latest 5.x patch release in Community Edition, which is free, widely used, and
sufficient for single-instance deployment. Enterprise Edition features (clustering, advanced
security plugins, multi-database) are explicitly out of scope per spec Assumptions.

**Alternatives considered**:
- `neo4j:5.x.y` (pinned patch): more reproducible but requires manual bump on each patch.
  `5-community` is acceptable for infrastructure components where minor patch auto-updates
  via `docker compose pull` are desirable. Pin to a specific patch before production cut.
- Neo4j 4.x: EOL; not considered.

---

## Decision 3 — Log Forwarding to OpenSearch/Logstash

**Decision**: Docker default JSON file logging; Logstash collects via Docker socket or
log file polling. No explicit `logging.driver` override on PostgreSQL or Neo4j containers.

**Rationale**: No existing service in `deployment/compose/docker-compose.yml` uses an
explicit logging driver — all services use Docker's default JSON file driver. Adding a GELF
or syslog driver only to the new database containers would be inconsistent with the rest of
the stack. The existing Logstash configuration (present in
`deployment/helm/core-infrastructure/charts/logstash/`) is the authoritative log collection
endpoint. Adding Filebeat or direct Docker socket monitoring to Logstash is the standard
approach for collecting JSON-file Docker logs and is already implied by the Logstash
presence in the stack.

**Implementation**: Both `app-postgres` and `neo4j` containers inherit the Docker default
logging driver. Logstash is responsible for collecting logs from
`/var/lib/docker/containers/**/*.log` or via Docker socket. SC-008 (logs visible in
OpenSearch Dashboards within 60 seconds) is verified in the integration test script.

**Alternatives considered**:
- `logging.driver: gelf` on DB containers pointing to Logstash GELF input: inconsistent
  with all other services in the stack; introduces a different collection path.
- Fluentd sidecar: over-engineered for this feature scope.

---

## Decision 4 — PostgreSQL Bootstrap Init Script

**Decision**: Mount `infrastructure/postgres/init/01-init-app-role.sql` into
`/docker-entrypoint-initdb.d/` on the `app-postgres` container. For Kubernetes, deliver
the same SQL via a ConfigMap mounted into the same path.

**Rationale**: PostgreSQL's official image processes any `.sql` files placed in
`/docker-entrypoint-initdb.d/` on first startup (when the data directory is empty). This
is the idiomatic, zero-dependency mechanism for database bootstrap with no custom image
required.

**Init SQL content** (see `infrastructure/postgres/init/01-init-app-role.sql`):
```sql
-- Bootstrap role for all application services.
-- Each service creates its own schema and role derived from app.
CREATE ROLE app WITH LOGIN NOINHERIT;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
GRANT CONNECT ON DATABASE app_db TO app;
```

**Alternatives considered**:
- Init container running `psql`: requires a separate container image; adds startup
  complexity; overkill given the `initdb.d` mechanism.
- Flyway/Liquibase in a dedicated migration service: appropriate for service-level schema
  migrations (each service's responsibility), but not for the one-time platform bootstrap
  that this feature provides.

---

## Decision 5 — Neo4j Authentication

**Decision**: Username/password via `NEO4J_AUTH=neo4j/${NEO4J_PASSWORD}` environment
variable. No anonymous access.

**Rationale**: Neo4j's official image uses `NEO4J_AUTH` to set the initial password. This
is the standard mechanism, requires no custom image, and keeps credentials in environment
variables per FR-012.

**Neo4j constraint bootstrap**: On first connection, a Cypher constraint is created:
```cypher
CREATE CONSTRAINT entity_uuid_unique IF NOT EXISTS
FOR (e:Entity) REQUIRE e.uuid IS UNIQUE;
```
This constraint ensures UUID uniqueness for all Entity nodes. It is created via a
one-shot init script executed with `docker compose run` after Neo4j is healthy (or via a
Kubernetes Job for Helm deployments).

**Alternatives considered**:
- LDAP-backed auth (Neo4j Enterprise only): out of scope.
- No auth (`NEO4J_AUTH=none`): explicitly prohibited by FR-012 and Assumptions.

---

## Decision 6 — Neo4j Relationship Directionality (Storage Model)

**Decision**: All Neo4j relationships are stored as directed (start → end node). There is
no "undirected storage" in Neo4j. Caller-controlled directionality (per clarification
Answer C) is expressed at query time: services use `MATCH (a)-[r]->(b)` for directed
traversal and `MATCH (a)-[r]-(b)` for bidirectional traversal. The direction of storage
is always determined by the caller specifying start UUID and end UUID at relationship
creation time.

**Rationale**: This is the intrinsic Neo4j data model — all relationships have a defined
start and end node. Supporting both "directed" and "undirected" queries is simply a Cypher
query pattern choice and requires no special data-model accommodation.

**Alternatives considered**:
- Storing a `{bidirectional: true}` property on relationships: adds data model complexity
  with no benefit; query pattern (with/without arrow) is sufficient and the standard
  Neo4j approach.
- Creating two directed relationships in opposite directions to simulate undirectedness:
  wastes storage; anti-pattern in Neo4j.

---

## Decision 7 — Neo4j "Both Nodes Must Exist" Enforcement

**Decision**: Application-level enforcement only. Neo4j Community Edition does not support
a native constraint that prevents creating a relationship when one of the referenced nodes
is absent (there is no referential integrity equivalent for graph edges in Community
Edition). Services are responsible for verifying both UUID nodes exist before creating a
relationship (FR-009). The platform provides no automated enforcement at the database level.

**Rationale**: Consistent with clarification Answer A (service responsibility) and the
spec's Assumptions. The test script validates this constraint by attempting to create a
relationship with a non-existent node and confirming the service-level guard is tested.

---

## Decision 8 — Helm Sub-Chart Structure

**Decision**: Follow the existing sub-chart structure in
`deployment/helm/core-infrastructure/charts/`. Each database gets a sub-chart with:
`Chart.yaml`, `templates/_helpers.tpl`, `templates/deployment.yaml`, `templates/pvc.yaml`,
`templates/service.yaml`, `values.yaml`. The PostgreSQL sub-chart adds
`templates/configmap-init.yaml` to deliver the init SQL via ConfigMap.

**Rationale**: Consistency with the 10 existing sub-charts (keycloak, kafka, jaeger, etc.)
minimises cognitive overhead and enables the umbrella chart's `values.yaml` to configure all
databases uniformly.

---

## Decision 9 — Capability Key Registration

**Decision**: Register two new keys in `contracts/capabilities/infrastructure.md`:
- `relational-data`: signals application PostgreSQL availability
- `graph-data`: signals Neo4j availability

Both databases are not Eureka clients (like Keycloak and Kafka); availability is detected
via connection retry and health endpoint polling by consuming services.

**Rationale**: Consistent with the existing capability registry format and Constitution
§VIII. Services that require the data layer can check connectivity rather than Eureka
metadata.
