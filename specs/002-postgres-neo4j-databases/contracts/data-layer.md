# Contract: Shared Data Layer

**Feature**: 002 — Shared Data Layer
**Date**: 2026-05-15
**Capability Keys**: `relational-data`, `graph-data`

---

## Purpose

This contract defines how application services interact with the two shared platform
databases: the application PostgreSQL instance and the Neo4j graph database. Adherence
to this contract is mandatory for all services that read from or write to either database.

---

## PostgreSQL Contract

### Connection

| Parameter | Value |
|-----------|-------|
| Host | `app-postgres` (Docker Compose) / `postgres` (Kubernetes service name) |
| Port | `5432` |
| Database | `app_db` (configurable via `APP_POSTGRES_DB` env var) |
| Protocol | PostgreSQL wire protocol |
| TLS | Not required on internal network; services connect within `app-net` |

### Service Responsibilities

A service wishing to use the application PostgreSQL MUST:

1. **Create a dedicated role** on startup:
   ```sql
   CREATE ROLE svc_<name> WITH LOGIN NOINHERIT IN ROLE app;
   ```
2. **Create its own schema** owned by that role:
   ```sql
   CREATE SCHEMA IF NOT EXISTS svc_<name> AUTHORIZATION svc_<name>;
   ```
3. **Restrict its role** to its own schema only:
   ```sql
   REVOKE ALL ON SCHEMA public FROM svc_<name>;
   GRANT USAGE, CREATE ON SCHEMA svc_<name> TO svc_<name>;
   ```
4. **Use UUID primary keys** on all entity tables (UUID v4, service-generated).
5. **Never access another service's schema** — cross-schema queries are prohibited and
   will be rejected by PostgreSQL with a permission denied error.

### Platform Guarantees

- The `app` role with LOGIN exists before any service starts.
- `REVOKE CREATE ON SCHEMA public FROM PUBLIC` is applied at bootstrap.
- Data survives container/pod restart via named volume / PVC.
- Credentials are supplied via environment variables (never hardcoded).

---

## Neo4j Contract

### Connection

| Parameter | Value |
|-----------|-------|
| Host | `neo4j` (Docker Compose) / `neo4j` (Kubernetes service name) |
| Bolt port | `7687` |
| HTTP (browser, dev only) | `7474` |
| Protocol | Bolt 5.x |
| Authentication | Username `neo4j`, password from `NEO4J_PASSWORD` env var |

### Node Convention

- All entity nodes use label `:Entity`.
- The only stored property is `uuid` (UUID v4 string).
- No service-specific attribute data is stored on any node.

### Relationship Convention

- Relationships are typed with SCREAMING_SNAKE_CASE type names (e.g., `BELONGS_TO`,
  `REFERENCES`, `OWNED_BY`).
- No properties are stored on relationships.
- Direction (start → end UUID) is specified by the creating service.
- Bidirectional traversal is expressed in Cypher (`MATCH (a)-[r]-(b)`) not in storage.

### Service Responsibilities

A service interacting with Neo4j MUST:

1. **Register a node** when a new entity is created in PostgreSQL:
   ```cypher
   MERGE (:Entity {uuid: $uuid})
   ```
2. **Verify both nodes exist** before creating a relationship between two UUIDs (Neo4j
   does not enforce referential integrity in Community Edition):
   ```cypher
   MATCH (a:Entity {uuid: $sourceUuid}), (b:Entity {uuid: $targetUuid})
   CREATE (a)-[:RELATIONSHIP_TYPE]->(b)
   ```
3. **Remove the node and all its edges** when the entity is deleted from PostgreSQL:
   ```cypher
   MATCH (e:Entity {uuid: $uuid}) DETACH DELETE e
   ```
4. **Not store attribute data** beyond `uuid` on any node or relationship.

### Platform Guarantees

- The `:Entity(uuid)` uniqueness constraint exists before any service starts.
- Neo4j runs with authentication enabled; anonymous access is rejected.
- Data survives container/pod restart via named volume / PVC.

---

## Failure Handling

| Failure | Required Service Behaviour |
|---------|---------------------------|
| PostgreSQL unreachable at startup | Fail fast with a clear DB connection error; do NOT start with in-memory fallback |
| Neo4j unreachable at startup or runtime | Surface a clear error on graph operations; do NOT silently skip relationship registration |
| Partial failure (PostgreSQL write succeeds, Neo4j registration fails) | Service is responsible for retry or compensating action; no platform-level reconciliation is provided |
| Orphaned Neo4j node (entity deleted from PostgreSQL, node not removed) | Service is responsible for detecting and cleaning up; no automated platform reconciliation |
