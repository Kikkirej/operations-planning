# Quickstart: Shared Data Layer (PostgreSQL + Neo4j)

**Feature**: 002 — Shared Data Layer
**Date**: 2026-05-15

All operations below require only **Docker Engine** and **Docker Compose** — no local
database toolchain (psql, cypher-shell, etc.) is required on developer machines.

---

## Prerequisites

1. Copy `.env.example` to `.env` in `deployment/compose/` and fill in the required values:

```bash
# Application PostgreSQL
APP_POSTGRES_DB=app_db
APP_POSTGRES_USER=postgres
APP_POSTGRES_PASSWORD=<choose a strong password>

# Neo4j
NEO4J_PASSWORD=<choose a strong password>
```

2. Ensure the core infrastructure stack from feature 001 is already running (Traefik,
   Eureka, Keycloak, Kafka). The data layer services join the same `app-net`.

---

## Start the Data Layer

```bash
cd deployment/compose
docker compose up -d app-postgres neo4j
```

Both containers must reach healthy status before services attempt to connect:

```bash
docker compose ps app-postgres neo4j
# Expected: Status = healthy for both services
```

Health check timeout: 60 seconds (SC-004).

---

## Verify PostgreSQL Bootstrap

```bash
# Connect to the application PostgreSQL as the superuser
docker compose exec app-postgres \
  psql -U postgres -d app_db -c "\du"
# Expected: role 'app' listed with LOGIN attribute

docker compose exec app-postgres \
  psql -U postgres -d app_db -c "\dn"
# Expected: only 'public' schema (no service schemas pre-provisioned)
```

---

## Verify Neo4j Bootstrap

```bash
# Open Cypher shell inside the Neo4j container
docker compose exec neo4j \
  cypher-shell -u neo4j -p "${NEO4J_PASSWORD}" \
  "SHOW CONSTRAINTS;"
# Expected: entity_uuid_unique constraint on :Entity(uuid)
```

Neo4j Browser is also available at `http://localhost:7474` for development inspection only.

---

## Run Integration Tests

The test scripts exercise all acceptance scenarios from the spec. They run inside the Docker
network — no local toolchain needed.

```bash
# PostgreSQL: schema isolation, UUID primary keys, cross-schema rejection
docker compose run --rm test-runner \
  sh infrastructure/postgres/test/postgres-isolation-test.sh

# Neo4j: node registration, relationships, idempotency, DETACH DELETE
docker compose run --rm test-runner \
  sh infrastructure/neo4j/test/neo4j-relationship-test.sh
```

All tests MUST pass before raising a PR.

---

## Kubernetes (Helm)

```bash
# Add/update the core-infrastructure umbrella chart with postgres + neo4j sub-charts
helm upgrade --install core-infra deployment/helm/core-infrastructure \
  --namespace ops \
  --set postgres.auth.password=<secret> \
  --set neo4j.auth.password=<secret>

# Watch pod readiness (target: Running + Ready within 3 minutes — SC from Story 4)
kubectl get pods -n ops -w
```

---

## Common Operations

| Task | Command |
|------|---------|
| View PostgreSQL logs | `docker compose logs app-postgres` |
| View Neo4j logs | `docker compose logs neo4j` |
| Connect to app PostgreSQL | `docker compose exec app-postgres psql -U postgres -d app_db` |
| Connect to Neo4j Cypher shell | `docker compose exec neo4j cypher-shell -u neo4j -p $NEO4J_PASSWORD` |
| Stop data layer only | `docker compose stop app-postgres neo4j` |
| Destroy volumes (data loss!) | `docker compose down -v app-postgres neo4j` |

---

## Troubleshooting

**PostgreSQL fails health check**: Confirm `APP_POSTGRES_PASSWORD` is set in `.env`. Check
`docker compose logs app-postgres` for authentication or permission errors.

**Neo4j authentication error**: Confirm `NEO4J_PASSWORD` matches `NEO4J_AUTH=neo4j/<password>`
in the container environment. On first start, Neo4j sets the password from this variable;
if the volume already exists with a different password, destroy the volume and restart.

**Cross-schema access not rejected**: The bootstrap script revokes CREATE on the public
schema; per-service schema isolation is enforced by each service's own role setup. Verify
the service migration created a role with schema-scoped grants only.

**Neo4j relationship creation fails**: Confirm both UUID nodes exist before creating the
relationship. Neo4j Community Edition does not enforce referential integrity — the service
must verify both nodes are present prior to creating the edge.
