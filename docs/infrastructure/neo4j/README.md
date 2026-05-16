# Neo4j Graph Database

Shared graph database for cross-service entity relationship management. Stores only
UUID-keyed nodes and typed relationship edges — no service-specific attribute data.

## Purpose

Enables services to record and traverse relationships between entities that live in
different services' PostgreSQL tables, using only their UUIDs. This keeps cross-service
relationship data decoupled from each service's own relational schema.

## Node & Relationship Model

- **Nodes**: Label `:Entity`, single property `uuid` (UUID v4 string). No other properties.
- **Relationships**: Typed (e.g., `BELONGS_TO`, `REFERENCES`), no properties, directed storage.
- **Constraint**: `entity_uuid_unique` on `:Entity(uuid)` — enforced automatically at startup.

See `specs/002-postgres-neo4j-databases/data-model.md` for the full data model and
example Cypher patterns.

## Configuration Reference

| Environment Variable | Description | Default |
|---------------------|-------------|---------|
| `NEO4J_PASSWORD` | Neo4j `neo4j` user password | **Required — no default** |
| `NEO4J_HOST` | Hostname (init script only) | `neo4j` |
| `NEO4J_PORT` | Bolt port (init script only) | `7687` |

Set `NEO4J_PASSWORD` in `deployment/compose/.env`. Never hardcode credentials.

## Protocol

Services connect via the **Bolt protocol** on port `7687`. Use an official Neo4j driver
for your language (e.g., `neo4j-java-driver`, `neo4j-python-driver`).

The Neo4j Browser UI is available at `http://localhost:7474` for **development inspection
only** — it is not a production-facing tool and the port is not exposed on the Kubernetes
Service by default.

## Startup

```bash
cd deployment/compose
docker compose up -d neo4j neo4j-init
docker compose ps neo4j     # wait for Status: healthy
docker compose logs neo4j-init  # confirm constraint applied
```

## Shutdown

```bash
docker compose stop neo4j
```

**Destroy data** (irreversible):
```bash
docker compose down -v neo4j
```

## Integration Tests

```bash
docker compose run --rm test-runner sh infrastructure/neo4j/test/neo4j-relationship-test.sh
```

Tests cover: UUID uniqueness constraint, idempotent node registration, relationship
creation, directed and bidirectional query, UUID-only node inspection.

## Troubleshooting

**Container fails health check**: Check `docker compose logs neo4j`. Neo4j can take up
to 30 seconds to initialise. Ensure `NEO4J_PASSWORD` is set in `.env`.

**Authentication error**: If the volume already has a different password baked in, Neo4j
will reject the new credentials. Destroy the volume and restart:
`docker compose down -v neo4j && docker compose up -d neo4j neo4j-init`

**Constraint not found**: The `neo4j-init` service applies the constraint after Neo4j
is healthy. Check `docker compose logs neo4j-init`. If the init exited non-zero, run it
again: `docker compose run --rm neo4j-init sh /init-constraints.sh`

**Relationship creation returns no rows** (no match): Verify both UUID nodes were
registered via `MERGE` before creating the relationship. Neo4j Community Edition does
not enforce referential integrity — the service must verify both nodes exist first.

**Kubernetes**: Credentials are read from a Secret named in `values.yaml`
(`neo4j.auth.existingSecret`). Create the Secret before deploying:

```bash
kubectl create secret generic neo4j-secret \
  --from-literal=NEO4J_PASSWORD=<secret> \
  -n ops
```
