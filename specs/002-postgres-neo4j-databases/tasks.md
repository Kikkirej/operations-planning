# Tasks: Shared Data Layer (PostgreSQL + Neo4j)

**Input**: Design documents from `specs/002-postgres-neo4j-databases/`

**Prerequisites**: plan.md ✅ research.md ✅ data-model.md ✅ contracts/ ✅ quickstart.md ✅

**Tech stack**: postgres:17-alpine, neo4j:5-community, Docker Compose, Helm (sub-charts)

**Note**: This is an infrastructure-only feature — no custom Spring Boot service, no compiled
code. All tasks produce configuration files (SQL, YAML, shell scripts). Tests are shell
integration scripts run via `docker compose run`.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: User story label ([US1]–[US4])

---

## Phase 1: Setup

**Purpose**: Create directory structure and bootstrap scripts before any Compose/Helm work begins.

- [x] T001 Create directory structure: `infrastructure/postgres/init/`, `infrastructure/postgres/test/`, `infrastructure/neo4j/init/`, `infrastructure/neo4j/test/`
- [x] T002 [P] Write `infrastructure/postgres/init/01-init-app-role.sql` — CREATE ROLE app WITH LOGIN NOINHERIT; REVOKE CREATE ON SCHEMA public FROM PUBLIC; GRANT CONNECT ON DATABASE app_db TO app
- [x] T003 [P] Write `infrastructure/neo4j/init/01-init-constraints.sh` — sh script invoking cypher-shell against bolt://neo4j:7687 to create entity_uuid_unique constraint (CREATE CONSTRAINT entity_uuid_unique IF NOT EXISTS FOR (e:Entity) REQUIRE e.uuid IS UNIQUE)
- [x] T004 [P] Add APP_POSTGRES_DB, APP_POSTGRES_USER, APP_POSTGRES_PASSWORD, NEO4J_PASSWORD entries to `deployment/compose/.env.example`

**Checkpoint**: Bootstrap scripts and env template in place; directory structure exists

---

## Phase 2: Foundational (Docker Compose additions)

**Purpose**: Add both database services to the existing Compose stack. All user story test
scripts depend on these services being present and healthy.

**⚠️ CRITICAL**: Stories 1–4 are not testable until this phase is complete.

- [x] T005 Update `deployment/compose/docker-compose.yml` — add `app-postgres-data` and `neo4j-data` to the top-level `volumes:` block
- [x] T006 Update `deployment/compose/docker-compose.yml` — add `app-postgres` service: image postgres:17-alpine, networks [app-net], volume app-postgres-data, env POSTGRES_DB/USER/PASSWORD from APP_POSTGRES_* vars, init SQL mount (`../../infrastructure/postgres/init/01-init-app-role.sql:/docker-entrypoint-initdb.d/01-init-app-role.sql:ro`), healthcheck (`pg_isready -U $APP_POSTGRES_USER -d $APP_POSTGRES_DB`), restart unless-stopped
- [x] T007 Update `deployment/compose/docker-compose.yml` — add `neo4j` service: image neo4j:5-community, networks [app-net], volume neo4j-data:/data, env NEO4J_AUTH=neo4j/${NEO4J_PASSWORD}, port 7474 (browser, dev only), healthcheck (wget -qO- http://localhost:7474 || exit 1), restart unless-stopped; no external bolt port exposed (FR-013)
- [x] T008 Update `deployment/compose/docker-compose.yml` — add `neo4j-init` one-shot service: image neo4j:5-community, networks [app-net], depends_on neo4j (service_healthy), volume mount `../../infrastructure/neo4j/init/01-init-constraints.sh:/init-constraints.sh:ro`, command ["sh", "/init-constraints.sh"], env NEO4J_HOST=neo4j NEO4J_PASSWORD=${NEO4J_PASSWORD}, restart "no"

**Checkpoint**: `docker compose up app-postgres neo4j` — both services healthy; constraint applied

---

## Phase 3: User Story 1 — Service Developer Stores and Retrieves Relational Data (P1) 🎯 MVP

**Goal**: Application PostgreSQL with per-service schema isolation and UUID primary key enforcement, plus Helm sub-chart for Kubernetes deployment.

**Independent Test**: `docker compose run --rm test-runner sh infrastructure/postgres/test/postgres-isolation-test.sh`

- [x] T009 [US1] Write `infrastructure/postgres/test/postgres-isolation-test.sh` — integration tests covering: (1) `app` role exists after bootstrap; (2) service can create schema + UUID PK table + CRUD succeeds; (3) cross-schema access attempt returns permission denied error; (4) UUID type enforced on primary key column — test runs entirely via psql inside Docker network, no bare-metal psql required
- [x] T010 [P] [US1] Create `deployment/helm/core-infrastructure/charts/postgres/Chart.yaml` — apiVersion v2, name postgres, description "Application PostgreSQL", type application, version 0.1.0, appVersion "17"
- [x] T011 [P] [US1] Create `deployment/helm/core-infrastructure/charts/postgres/values.yaml` — image (postgres:17-alpine), auth (database, username, existingSecret), storage (size 10Gi, storageClass ""), resources requests/limits
- [x] T012 [P] [US1] Create `deployment/helm/core-infrastructure/charts/postgres/templates/_helpers.tpl` — define postgres.fullname helper following existing sub-chart pattern
- [x] T013 [US1] Create `deployment/helm/core-infrastructure/charts/postgres/templates/configmap-init.yaml` — ConfigMap containing 01-init-app-role.sql content, mounted into /docker-entrypoint-initdb.d/ in the deployment
- [x] T014 [US1] Create `deployment/helm/core-infrastructure/charts/postgres/templates/deployment.yaml` — single-replica Deployment; mounts configmap-init volume at /docker-entrypoint-initdb.d/; env from Secret for POSTGRES_PASSWORD; liveness probe (exec pg_isready); readiness probe (exec pg_isready); PVC volume mount at /var/lib/postgresql/data
- [x] T015 [P] [US1] Create `deployment/helm/core-infrastructure/charts/postgres/templates/pvc.yaml` — PersistentVolumeClaim, ReadWriteOnce, storage from values
- [x] T016 [P] [US1] Create `deployment/helm/core-infrastructure/charts/postgres/templates/service.yaml` — ClusterIP Service on port 5432; no NodePort/LoadBalancer (FR-013)
- [x] T017 [US1] Update `deployment/helm/core-infrastructure/values.yaml` — add `postgres:` block with enabled flag, auth, storage, and resources sub-keys matching charts/postgres/values.yaml
- [x] T018 [P] [US1] Write `docs/infrastructure/postgres/README.md` — purpose, configuration reference (all env vars), schema ownership model (app role + per-service pattern), startup/shutdown commands, troubleshooting (FR-014)

**Checkpoint**: US1 independently testable — schema isolation and UUID PKs verified via test script; Helm sub-chart lintable

---

## Phase 4: User Story 2 — Developer Registers and Queries Cross-Service Entity Relationships (P1)

**Goal**: Neo4j graph database with UUID-only `:Entity` nodes, typed relationships, idempotent node registration, and Helm sub-chart.

**Independent Test**: `docker compose run --rm test-runner sh infrastructure/neo4j/test/neo4j-relationship-test.sh`

- [x] T019 [US2] Write `infrastructure/neo4j/test/neo4j-relationship-test.sh` — integration tests covering: (1) entity_uuid_unique constraint exists; (2) MERGE creates node with uuid property only (no extra properties); (3) duplicate MERGE is idempotent — no second node created; (4) relationship created between two existing UUID nodes with correct type and direction; (5) query returns correct relationship type, direction, and counterpart UUID; (6) UUID-only node inspection — no attribute data beyond uuid on any node; (7) attempt to create relationship with non-existent node fails at application guard level — test runs via cypher-shell inside Docker network
- [x] T020 [P] [US2] Create `deployment/helm/core-infrastructure/charts/neo4j/Chart.yaml` — apiVersion v2, name neo4j, description "Neo4j Community graph database", type application, version 0.1.0, appVersion "5"
- [x] T021 [P] [US2] Create `deployment/helm/core-infrastructure/charts/neo4j/values.yaml` — image (neo4j:5-community), auth (existingSecret key NEO4J_PASSWORD), storage (size 20Gi, storageClass ""), boltPort 7687, browserPort 7474 (disabled in service by default), resources requests/limits
- [x] T022 [P] [US2] Create `deployment/helm/core-infrastructure/charts/neo4j/templates/_helpers.tpl` — define neo4j.fullname helper following existing sub-chart pattern
- [x] T023 [US2] Create `deployment/helm/core-infrastructure/charts/neo4j/templates/deployment.yaml` — single-replica Deployment; env NEO4J_AUTH from Secret; liveness probe (HTTP GET /); readiness probe (HTTP GET /); PVC volume mount at /data; init container using neo4j:5-community image running 01-init-constraints.sh via cypher-shell against localhost:7687 after main container is ready (or post-start lifecycle hook)
- [x] T024 [P] [US2] Create `deployment/helm/core-infrastructure/charts/neo4j/templates/pvc.yaml` — PersistentVolumeClaim, ReadWriteOnce, storage from values
- [x] T025 [P] [US2] Create `deployment/helm/core-infrastructure/charts/neo4j/templates/service.yaml` — ClusterIP Service on bolt port 7687; no NodePort/LoadBalancer (FR-013); browser port 7474 conditionally exposed based on values flag
- [x] T026 [US2] Update `deployment/helm/core-infrastructure/values.yaml` — add `neo4j:` block with enabled flag, auth, storage, and resources sub-keys matching charts/neo4j/values.yaml (append after postgres block from T017)
- [x] T027 [P] [US2] Write `docs/infrastructure/neo4j/README.md` — purpose, configuration reference (all env vars, Bolt protocol), node and relationship model summary, startup/shutdown, Neo4j Browser access (dev only), troubleshooting (FR-014)

**Checkpoint**: US2 independently testable — node registration, relationship creation/query, and idempotency verified via test script; Helm sub-chart lintable

---

## Phase 5: User Story 3 — Developer Removes an Entity and Its Relationships (P2)

**Goal**: Verified deletion path — entity removed from both PostgreSQL and Neo4j leaves zero orphaned relationship edges.

**Independent Test**: Extend existing Neo4j test script with deletion scenario; run cross-store cleanup validation.

- [x] T028 [US3] Extend `infrastructure/neo4j/test/neo4j-relationship-test.sh` — add deletion scenario: create `:Entity` node with three typed relationships to other nodes, execute DETACH DELETE, query for any relationship referencing the deleted UUID, assert zero results (acceptance scenarios 1–2 of US3)
- [x] T029 [US3] Write `infrastructure/postgres/test/cross-store-cleanup-test.sh` — cross-store lifecycle test: (1) insert UUID record into a test schema in PostgreSQL; (2) MERGE matching `:Entity` node in Neo4j; (3) create relationships from that node; (4) delete PostgreSQL record and DETACH DELETE Neo4j node; (5) verify PostgreSQL SELECT returns zero rows; (6) verify Neo4j query for that UUID returns zero nodes and zero relationship edges (SC-003)

**Checkpoint**: US3 independently testable — deletion leaves no orphans in either store

---

## Phase 6: User Story 4 — Operator Deploys the Data Layer Stack (P2)

**Goal**: Both databases start within 60s via `docker compose up` and survive container restarts with data intact.

**Independent Test**: `sh deployment/compose/test-data-layer.sh`

- [x] T030 [US4] Write `deployment/compose/test-data-layer.sh` — deployment integration test: (1) docker compose up app-postgres neo4j; (2) poll until both health checks pass, fail if not healthy within 60s (SC-004); (3) write a test record to PostgreSQL and a UUID node to Neo4j; (4) docker compose restart app-postgres neo4j; (5) poll until both healthy again; (6) read back the test record and UUID node, assert they still exist (SC-007); cleanup test data on exit

**Checkpoint**: US4 independently testable — deployment reproducibility and data persistence confirmed

---

## Phase 7: Polish & Cross-Cutting Concerns

- [x] T031 [P] Update `contracts/capabilities/infrastructure.md` notes section — add service detection guidance: `relational-data` detected via TCP connection retry to app-postgres:5432; `graph-data` detected via Bolt connection retry to neo4j:7687; include fail-fast behaviour expectation per FR-002/spec edge cases
- [x] T032 Cross-reference all spec success criteria (SC-001 through SC-008) against test scripts T009, T019, T028, T029, T030 — confirm each criterion has a corresponding assertion; add any missing assertions in-place

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately
- **Foundational (Phase 2)**: Depends on T001–T004 — BLOCKS all user story test scripts
- **US1 (Phase 3)**: Depends on Phase 2 completion; no dependency on US2
- **US2 (Phase 4)**: Depends on Phase 2 completion; no dependency on US1
- **US3 (Phase 5)**: Depends on Phase 4 (T019 must exist before T028 extends it)
- **US4 (Phase 6)**: Depends on Phases 2–5 (requires both databases running and test data)
- **Polish (Phase 7)**: Depends on all story phases complete

### User Story Dependencies

- **US1 (P1)**: Independent after Foundational — PostgreSQL only
- **US2 (P1)**: Independent after Foundational — Neo4j only
- **US3 (P2)**: Depends on US2 (extends neo4j test script); cross-store test requires US1 Compose setup
- **US4 (P2)**: Depends on US1 + US2 being deployable via Compose; Helm charts validated last

### Within Each User Story

- Test script before Helm charts (validates foundation)
- Helm files in order: Chart.yaml + values.yaml + _helpers.tpl (parallel) → configmap/deployment → pvc + service (parallel)
- values.yaml umbrella update after sub-chart files complete
- Docs last (written from observed behaviour)

---

## Parallel Opportunities

### Phase 2 (Foundational)
All 4 Docker Compose updates touch the same file → run sequentially (T005 → T006 → T007 → T008)

### Phase 3 (US1) — run in parallel after T006
```
T009  (test script, standalone)
T010 + T011 + T012  (Chart.yaml, values.yaml, _helpers.tpl — different files)
T013 → T014  (configmap before deployment that references it)
T015 + T016  (pvc.yaml, service.yaml — different files)
T018  (docs, standalone)
```

### Phase 4 (US2) — run in parallel with Phase 3 after T008
```
T019  (test script, standalone)
T020 + T021 + T022  (Chart.yaml, values.yaml, _helpers.tpl)
T023  (deployment.yaml — after T022)
T024 + T025  (pvc.yaml, service.yaml)
T027  (docs, standalone)
```

---

## Implementation Strategy

### MVP (US1 + US2 only — Compose, no Helm)

1. Complete Phase 1 (T001–T004)
2. Complete Phase 2 (T005–T008)
3. Run test: `docker compose up app-postgres neo4j neo4j-init`
4. Complete T009 (US1 test) → run: passes ✅
5. Complete T019 (US2 test) → run: passes ✅
6. **STOP and validate**: both P1 stories working locally

### Full Delivery

1. MVP above
2. Add Helm sub-charts (T010–T017, T020–T026)
3. Add deletion tests (T028–T029)
4. Add deployment test (T030)
5. Polish (T031–T032)
6. `/speckit-analyze` before PR

---

## Notes

- [P] tasks operate on different files — safe to parallelise within the same phase
- No compiled code — all tasks produce SQL, YAML, or shell scripts
- Credentials must never appear in committed files; use env vars from `.env` (which is gitignored)
- `docker build --target test` does not apply here (no custom Dockerfile); test execution is `docker compose run --rm test-runner sh <script>`
- Commit after each phase checkpoint to maintain clean, traceable history
