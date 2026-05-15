# Feature Specification: Shared Data Layer (PostgreSQL + Neo4j)

**Feature Branch**: `003-postgres-neo4j-databases`

**Created**: 2026-05-15

**Status**: Draft

**Input**: User description: "two databases are part of it. 1 postgres database for all relational data. each table is owned by a service. Entities can be defined by clear IDs. (UUIDs) Additionally a general neo4j database exists, which manages relationships between entities. neo4j just concentrates on IDs and relationships. no other data saved."

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Service Developer Stores and Retrieves Relational Data (Priority: P1)

A service developer wants to persist structured relational data to a shared PostgreSQL
database using service-owned tables, with each entity uniquely identified by a UUID,
without having to provision or manage database infrastructure themselves.

**Why this priority**: Relational data storage is the foundational data concern for every
application service. No service can function without it, and UUID-based identity is the
cross-cutting contract that ties PostgreSQL and Neo4j together.

**Independent Test**: Deploy PostgreSQL only. Create two schemas (one per service). Verify
each service can create, read, update, and delete records in its own schema, and that
cross-schema access is rejected. Confirm all primary keys are UUIDs.

**Acceptance Scenarios**:

1. **Given** a service has been assigned its own PostgreSQL schema, **When** it creates a
   record with a UUID primary key, **Then** the record is persisted and retrievable by
   that UUID.
2. **Given** two services each own a schema, **When** service A attempts to read from
   service B's schema, **Then** the database rejects the operation with a permission
   error.
3. **Given** a service creates a record, **When** another service queries the same UUID
   against its own tables, **Then** it finds no record — cross-service data is never
   implicitly shared.

---

### User Story 2 — Developer Registers and Queries Cross-Service Entity Relationships (Priority: P1)

A developer wants to record and traverse relationships between entities that live in
different services' PostgreSQL tables — using only their UUIDs — without denormalising
relationship data into each service's own schema.

**Why this priority**: The graph layer is the primary value proposition of Neo4j in this
architecture. Without it, cross-service relationship queries would require expensive
joins across service boundaries or duplicated data.

**Independent Test**: Deploy Neo4j only. Create nodes for three UUIDs (representing
entities from different services). Create typed relationships between them. Query the
graph for direct neighbours of one UUID and verify the correct relationships are returned.
Confirm no attribute data beyond UUID is stored on any node.

**Acceptance Scenarios**:

1. **Given** an entity UUID exists, **When** a service registers it as a node in Neo4j,
   **Then** the node exists in the graph containing only the UUID — no other properties.
2. **Given** two UUID nodes exist in Neo4j, **When** a service creates a typed
   relationship between them, **Then** the relationship is queryable by either UUID and
   returns the correct type and direction.
3. **Given** a relationship query is executed for a UUID, **When** the UUID has multiple
   relationships of different types, **Then** all relationships and their counterpart UUIDs
   are returned accurately.
4. **Given** a node registration is requested for a UUID that already exists, **When** the
   operation is executed, **Then** the operation is idempotent — no duplicate node is
   created and no error is returned.

---

### User Story 3 — Developer Removes an Entity and Its Relationships (Priority: P2)

A developer wants to cleanly delete an entity from the platform — removing its
PostgreSQL record and its Neo4j node along with all associated relationships — leaving
no orphaned data in either database.

**Why this priority**: Data consistency across two stores is a correctness concern. Stale
Neo4j nodes for deleted entities would corrupt relationship queries over time.

**Independent Test**: Create a UUID entity with records in PostgreSQL and a node with
relationships in Neo4j. Delete the entity. Verify the PostgreSQL record is gone, the
Neo4j node is gone, and no dangling relationships referencing that UUID remain.

**Acceptance Scenarios**:

1. **Given** an entity UUID exists in both PostgreSQL and Neo4j, **When** the entity is
   deleted from PostgreSQL, **Then** the corresponding Neo4j node and all its relationships
   MUST also be removed.
2. **Given** a Neo4j node is removed, **When** the graph is queried for relationships
   involving the deleted UUID, **Then** zero results are returned — no orphaned
   relationship edges remain.

---

### User Story 4 — Operator Deploys the Data Layer Stack (Priority: P2)

An operator wants to bring up both the shared PostgreSQL database and the Neo4j graph
database with a single command in both local (Docker Compose) and Kubernetes (Helm)
environments, with correct initial configuration applied automatically.

**Why this priority**: Deployment automation is essential for reproducibility. Developers
must be able to start the full data layer locally with no manual DB setup steps.

**Independent Test**: Run `docker compose up` from `deployment/compose/`. Confirm both
PostgreSQL and Neo4j start, pass health checks, and are reachable by a test client
within 60 seconds.

**Acceptance Scenarios**:

1. **Given** a correctly configured `deployment/compose/` directory, **When**
   `docker compose up` is executed, **Then** both PostgreSQL (application data) and
   Neo4j start successfully and pass their configured health checks within 60 seconds.
2. **Given** a correctly configured Helm chart in `deployment/helm/`, **When**
   `helm install` is executed against a Kubernetes cluster, **Then** both databases
   reach `Running` status and pass readiness probes within 3 minutes.
3. **Given** the data layer stack is running, **When** either database is restarted,
   **Then** persisted data survives the restart (volumes/PVCs intact) and the service
   reconnects automatically.

---

### Edge Cases

- What happens when a service attempts to access a schema owned by another service?
  PostgreSQL MUST reject the operation with a permission denied error; no data from
  the other service's schema MUST be exposed.
- What happens when a Neo4j node registration is requested for a UUID that already
  exists? The operation MUST be idempotent — no duplicate node is created, no error is
  returned.
- What happens when a relationship is created referencing a UUID that has no
  corresponding node? Neo4j MUST reject the operation with a clear error; dangling
  relationships MUST NOT be created.
- What happens when an entity is deleted from PostgreSQL but its Neo4j node is not
  removed (partial failure)? The platform MUST expose a mechanism to detect and clean
  up orphaned Neo4j nodes whose UUIDs no longer have a corresponding PostgreSQL record.
- What happens when PostgreSQL is unreachable at service startup? Services MUST fail
  fast with a clear database connection error; they MUST NOT start with empty or
  default in-memory state.
- What happens when Neo4j is unreachable? Services MUST surface a clear error on any
  graph operation; they MUST NOT silently skip relationship registration.
- What happens when data volume / PVC is full? Both databases MUST surface storage
  errors immediately; writes MUST fail with a clear error rather than silently
  corrupting data.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The platform MUST provide a shared PostgreSQL database instance accessible
  to all application services for relational data storage. This instance is distinct from
  the Keycloak-PostgreSQL instance and is dedicated to application data.
- **FR-002**: Each PostgreSQL table MUST be owned by exactly one service. Ownership is
  enforced via dedicated per-service database schemas and role-based access control;
  no service MAY read from or write to a schema it does not own.
- **FR-003**: Every entity persisted in PostgreSQL MUST use a UUID as its primary key.
  UUID generation is the responsibility of the owning service; the database enforces
  the UUID type constraint only.
- **FR-004**: The platform MUST provide a shared Neo4j graph database for managing
  cross-service entity relationships.
- **FR-005**: The Neo4j database MUST store only entity UUID nodes and typed
  relationship edges between them. No entity attribute or payload data MUST be stored
  in Neo4j; each node contains only its UUID identifier.
- **FR-006**: When an entity is created in PostgreSQL, a corresponding UUID node MUST
  be registerable in Neo4j to enable cross-service relationship tracking.
- **FR-007**: When an entity is deleted, its corresponding Neo4j node and all
  associated relationship edges MUST be removable atomically from Neo4j.
- **FR-008**: Neo4j relationship operations MUST be idempotent for node creation; a
  duplicate node registration for an existing UUID MUST succeed without creating
  duplicates.
- **FR-009**: Creating a relationship between two UUIDs MUST be rejected if either UUID
  does not exist as a node in Neo4j; dangling relationships MUST NOT be created.
- **FR-010**: Both PostgreSQL (application data) and Neo4j MUST be included in the
  Docker Compose file under `deployment/compose/` and have Helm chart definitions under
  `deployment/helm/`.
- **FR-011**: Both databases MUST persist data to named Docker volumes (Compose) or
  PersistentVolumeClaims (Kubernetes) to survive container restarts.
- **FR-012**: All database credentials (usernames, passwords, connection strings) MUST
  be supplied via environment variables; no credentials MAY be hardcoded in source
  files, container images, or Helm chart values committed to the repository.
- **FR-013**: Both databases MUST be reachable only from within the platform network;
  no external direct access to either database port is permitted.
- **FR-014**: User-facing documentation for the application PostgreSQL and Neo4j MUST
  exist under `docs/infrastructure/<component-name>/` and MUST cover purpose,
  configuration reference, schema ownership model, startup/shutdown, and
  troubleshooting.

### Key Entities

- **Entity**: Any domain object managed by a service, uniquely identified by a UUID;
  represented as records in a service-owned PostgreSQL schema and as a UUID-only node
  in Neo4j.
- **Service Schema (PostgreSQL)**: A PostgreSQL schema exclusively owned and managed by
  one service; the database enforces that no other service role can access it.
- **UUID**: The canonical, platform-wide identifier for every entity; used as the
  primary key in PostgreSQL and as the sole node property in Neo4j, forming the
  cross-store identity contract.
- **Node (Neo4j)**: A graph node representing one entity, identified solely by its UUID;
  no attribute data beyond the UUID is stored on the node.
- **Relationship (Neo4j)**: A directed or undirected typed edge between two UUID nodes
  in Neo4j, representing a cross-service association (e.g., `BELONGS_TO`,
  `REFERENCES`); carries no payload data.
- **Application PostgreSQL**: The shared relational database dedicated to application
  service data; distinct from the Keycloak-PostgreSQL instance used by the identity
  provider.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A service can create, read, update, and delete records in its own
  PostgreSQL schema with no awareness of other services' schemas; operations complete
  within normal database response times.
- **SC-002**: Cross-service entity relationships can be queried from Neo4j using only
  entity UUIDs, returning the correct relationship type and direction within normal
  graph query response times.
- **SC-003**: Deleting an entity from PostgreSQL and removing its Neo4j node leaves
  zero orphaned relationship edges referencing that UUID in the graph.
- **SC-004**: Both PostgreSQL (application data) and Neo4j start successfully and are
  reachable by services within 60 seconds of `docker compose up`.
- **SC-005**: No service can directly read or write another service's PostgreSQL schema;
  100% of cross-schema access attempts are rejected by the database.
- **SC-006**: Neo4j contains zero entity attribute data — inspection of any node reveals
  only its UUID property and no other fields.
- **SC-007**: Data in both databases survives a container/pod restart without loss;
  verified by writing records before restart and reading them after.

## Assumptions

- The application PostgreSQL instance is entirely separate from the Keycloak-PostgreSQL
  instance defined in the core infrastructure feature; they run as distinct services
  with distinct volumes and credentials.
- Service-owned schema isolation is enforced via PostgreSQL schemas (one schema per
  service) and dedicated PostgreSQL roles with schema-scoped GRANT permissions. Schema
  provisioning (CREATE SCHEMA, GRANT) is the responsibility of each service's database
  migration on startup.
- Neo4j runs in Community Edition for local development and Kubernetes; Enterprise
  Edition features (clustering, advanced security plugins) are out of scope.
- All Neo4j interactions use the Bolt protocol; the Neo4j Browser UI is available for
  development inspection but is not a production-facing tool.
- UUID generation is the responsibility of each owning service (e.g., via a UUID v4
  library); the database layer enforces the UUID type constraint only.
- Both databases run as single instances (replicas: 1); clustering and high-availability
  are deferred to the infrastructure hardening feature.
- Both databases use named Docker volumes (Compose) and PersistentVolumeClaims
  (Kubernetes) for data durability.
- Neo4j authentication uses username/password credentials supplied via environment
  variables; no anonymous access is permitted.
- The responsibility for keeping PostgreSQL and Neo4j in sync (i.e., registering/
  removing Neo4j nodes when PostgreSQL records are created/deleted) lies with each
  service's application logic; this feature provisions the databases and defines the
  contract, not the synchronisation mechanism.
- Both databases are placed on the same internal platform network as all other
  infrastructure services; no additional network segment is required.
