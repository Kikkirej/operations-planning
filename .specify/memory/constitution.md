<!--
SYNC IMPACT REPORT
==================
Version change: 1.3.0 → 1.4.0
Bump rationale: MINOR — new Principle IX added (Docker-first build & test reproducibility;
  multi-stage Dockerfiles; GitHub Actions CI); .github/workflows/ added to Monorepo
  Structure; new quality gates for multi-stage Dockerfiles, CI pipeline, and Docker-only
  test execution.
Modified principles: None renamed or removed.
Added:
  - Principle IX: Docker-First Build & Test Reproducibility
    • All builds and tests MUST execute inside Docker containers
    • Multi-stage Dockerfiles: builder → test → runtime for all custom services
    • GitHub Actions CI MUST build, test, and push images on every push
    • No bare-metal toolchain (JDK, Gradle, etc.) required beyond Docker Engine
  - .github/workflows/ top-level directory added to Monorepo Structure
  - Quality gates: multi-stage Dockerfile, CI pipeline present, tests run in Docker
  - Code review checks: Docker-first compliance, CI workflow present
Removed: Nothing.
Templates reviewed:
  - .specify/templates/plan-template.md     ✅ aligned (Constitution Check gate covers IX)
  - .specify/templates/spec-template.md     ✅ aligned (no structural changes required)
  - .specify/templates/tasks-template.md    ✅ aligned (build/test/CI tasks fit Setup phase)
Follow-up TODOs:
  - None — all fields resolved from user input and repo context.
-->

# Operations Planning Constitution

## Core Principles

### I. Specification-First

Every feature MUST begin with a written specification (`spec.md`) before any implementation
work starts. No code is written without an approved spec. Specifications MUST include:
user stories with acceptance scenarios, functional requirements, and measurable success
criteria. Implementation MUST NOT begin until the spec has been reviewed and accepted.

**Rationale**: Prevents wasted effort on misunderstood requirements and ensures all
stakeholders share a common understanding before costly implementation begins.

### II. Test-Driven Development (NON-NEGOTIABLE)

TDD is mandatory for all implementation work. The Red-Green-Refactor cycle MUST be
enforced strictly:

- Tests MUST be written before the implementation they cover.
- Tests MUST fail before implementation is added.
- Implementation is considered complete only when tests pass.
- Contract and integration tests are required for all inter-service and API boundaries.

**Rationale**: Catches design flaws early, ensures correctness, and provides a living
safety net for future changes.

### III. Incremental & Independent Delivery

Features MUST be organized as independently deliverable user stories. Each user story
MUST be:

- Implementable without depending on unfinished sibling stories.
- Testable in isolation — a single story MUST constitute a viable MVP.
- Demonstrable to stakeholders upon completion without requiring the full feature set.

Planning phases (Setup → Foundational → Stories) MUST respect this dependency order.
No story work begins before foundational infrastructure is complete.

**Rationale**: Enables early value delivery, reduces integration risk, and allows
priorities to shift without blocking in-flight work.

### IV. Documentation as Code

All specification, planning, and task artifacts (spec.md, plan.md, tasks.md, research.md,
data-model.md, contracts/) are version-controlled alongside source code. These documents
MUST be kept in sync with implementation. Stale or missing documentation is treated as a
defect. Generated artifacts MUST NOT be manually edited outside the designated Specify Kit
commands.

Every service module and infrastructure component MUST have corresponding user
documentation maintained under `docs/`. A PR that introduces or modifies a service MUST
include updates to the relevant `docs/` subtree in the same changeset.

**Rationale**: Ensures traceability from requirements through to implementation and makes
the rationale behind decisions discoverable in the future.

### V. Simplicity (YAGNI)

Complexity MUST be justified. Every design decision that adds abstraction, indirection, or
new dependencies MUST be recorded in the plan's Complexity Tracking table with a stated
reason and a description of the simpler alternative that was rejected. Default to the
simplest implementation that satisfies the acceptance criteria. Premature optimization and
speculative generality are non-compliant with this principle.

**Rationale**: Reduces maintenance burden, accelerates onboarding, and keeps the system
understandable as it grows.

### VI. Platform Infrastructure Compliance (NON-NEGOTIABLE)

All services and infrastructure components MUST conform to the shared platform contracts.
No exceptions are permitted without a documented entry in the Complexity Tracking table.

**Identity & Access (Keycloak OIDC)**:
- Authentication and authorization MUST use OIDC via Keycloak.
- No service MAY implement its own auth mechanism or token issuance.
- Every protected endpoint MUST validate bearer tokens against the configured Keycloak realm.
- Service-to-service calls MUST use client credentials flow, not shared secrets.

**Service Registry (Eureka)**:
- Every service MUST register with Eureka on startup and deregister on graceful shutdown.
- Inter-service addressing MUST resolve through Eureka — hardcoded hostnames or IPs are
  non-compliant.
- Health-check endpoints MUST be implemented so Eureka can evict unhealthy instances.

**API Gateway (Traefik)**:
- All inbound external traffic MUST be routed through the Traefik gateway.
- Services MUST NOT expose ports directly to external consumers.
- Routing rules, middleware (auth, rate-limiting, TLS termination) MUST be declared in the
  service's deployment configuration under `deployment/`.

**Rationale**: Uniform platform contracts enable consistent observability, security, and
operational management across all modules without per-service duplication.

### VII. Technology Platform Standards

**Infrastructure Services — Spring Cloud**:

Infrastructure services (config server, service registry, circuit breakers, distributed
tracing, etc.) MUST be implemented using the appropriate Spring Cloud component where one
exists. Spring Boot MUST serve as the application framework baseline for all Spring Cloud
services.

- Exception: The API gateway role is fulfilled by **Traefik** (not Spring Cloud Gateway).
  This is the only infrastructure component explicitly exempt from the Spring Cloud mandate.
- New infrastructure components MUST be evaluated against the Spring Cloud catalogue first.
  Deviation requires a documented entry in the plan's Complexity Tracking table.

**Container-Based Deployments**:

All services and infrastructure components MUST be packaged as OCI-compliant container
images. No bare-metal or non-containerized deployment target is permitted.

- Every service MUST include a `Dockerfile` (or equivalent build descriptor) in its own
  directory under `services/<service-name>/` or `infrastructure/<component-name>/`.
- Container images MUST be the sole deployment artifact — no fat JARs or binary drops
  directly onto hosts.
- Orchestration descriptors (Helm charts, Docker Compose files) MUST live under
  `deployment/` per the Monorepo Structure principle.

**Rationale**: Spring Cloud provides a proven, opinionated foundation for distributed
systems that aligns with the platform stack (Eureka, config server). Containers enforce
environment parity between local development and production and make deployments
reproducible and auditable.

### VIII. Loose Coupling & Capability-Driven Activation

**Infrastructure is always on**: The full infrastructure stack (Eureka, Keycloak,
Config Server, Traefik, Spring Boot Admin, Kafka) MUST be deployed in every environment.
Infrastructure services are not optional and MUST NOT be conditionally included.

**Application services are loosely coupled**: Application services (under `services/`)
MUST NOT hard-code dependencies on other application services. No service MAY fail to
start because a sibling application service is absent.

**Capability discovery via service registry metadata**: Cross-service feature activation
MUST be driven by capability metadata published in the Eureka service registry:

- Each service that provides a cross-service capability MUST declare it as metadata in
  its Eureka registration (e.g., `capabilities: estimation,scheduling`).
- A consuming service MUST check for the required capability key in the registry metadata
  at runtime before activating the dependent feature.
- If the required capability is not present in the registry, the consuming service MUST
  degrade gracefully — disabling or hiding the dependent feature — and MUST NOT throw an
  unhandled error or prevent its own startup.
- Capability metadata keys and their meaning MUST be documented in `contracts/capabilities/`.

**Contract-first capability design**: Any capability that crosses a service boundary MUST
have a published API or event contract in `contracts/` before implementation begins. The
capability metadata key MUST reference the contract identifier.

**Rationale**: Loose coupling allows services to be deployed, upgraded, and retired
independently. Capability-driven activation means the system degrades gracefully rather
than failing catastrophically when a peer service is unavailable or not yet deployed,
enabling incremental rollout of new modules.

### IX. Docker-First Build & Test Reproducibility (NON-NEGOTIABLE)

All builds and all automated tests MUST execute inside Docker containers. No bare-metal
toolchain (JDK, Gradle, Node, Python, etc.) MUST be required on developer machines or CI
agents beyond Docker Engine and Docker Compose.

**Multi-stage Dockerfiles** are mandatory for every custom service:

- Stage 1 — `builder`: full build toolchain + source; produces the runnable artifact (fat JAR,
  binary, bundle). Gradle/compiler invocation happens here only.
- Stage 2 — `test`: inherits from `builder`; executes the full test suite
  (`gradle test` or equivalent). This stage is the CI gate — `docker build --target test`
  MUST succeed for the PR to merge. The test image is NOT pushed to the registry.
- Stage 3 — `runtime`: minimal base image (e.g., `eclipse-temurin:21-jre-alpine`); copies
  only the runnable artifact from `builder`; runs as a non-root user (UID ≥ 1000).
  This is the only stage that produces a pushed image.

**CI/CD via GitHub Actions** is mandatory for every repository with custom services:

- A workflow file MUST exist at `.github/workflows/build-images.yml`.
- The workflow MUST trigger on every push to any branch and on pull requests targeting `main`.
- The workflow MUST run `docker build --target test` for each custom service before
  building the runtime image — a test failure MUST fail the CI job and block merging.
- Built runtime images MUST be pushed to the configured container registry (default:
  `ghcr.io/<org>/ops/<service>`) tagged with the branch name; the `main` branch MUST
  also receive the `latest` tag.
- Layer caching (`cache-from: type=gha`) MUST be enabled to keep CI build times acceptable.

**Developer workflow** (local):

- `docker build --target test -f infrastructure/<service>/Dockerfile .` — runs all tests locally.
- `docker compose up` — starts the full stack; all images are either pre-built or built
  inline by Compose using the same multi-stage Dockerfile.
- No `gradle`, `java`, or language-specific toolchain commands SHOULD appear in the
  primary developer runbook (`quickstart.md`) outside of IDE-optional sidebars.

**Rationale**: Docker-first builds eliminate "works on my machine" failures by making the
build environment a versioned, reproducible artifact. Running tests inside the same Docker
stage used for production images catches environment divergence early. GitHub Actions CI
enforces this contract automatically and produces registry-ready images on every push,
enabling CD pipelines without additional build steps.

## Technology Stack & Quality Gates

This project uses Claude Code (claude-sonnet-4-6) as its AI integration via Specify Kit
(v0.8.11+). The authoritative tool configuration lives in `.specify/init-options.json`.

**Quality Gates** (MUST pass before merging):

- All tests pass (`unit`, `integration`, `contract` suites where applicable).
- No unresolved `NEEDS CLARIFICATION` markers remain in spec.md or plan.md.
- No unexplained bracket placeholder tokens remain in generated artifacts.
- Constitution Check in plan.md is explicitly satisfied or violations are documented in
  the Complexity Tracking table.
- All feature branches follow the sequential naming convention enforced by
  `/speckit-git-validate`.
- **Dependency freshness**: Every newly introduced or updated dependency MUST be verified
  to be the current stable release at the time of the PR. Outdated dependencies MUST NOT
  be introduced; if a version pin is below current stable, a justification MUST be added
  to the PR description (e.g., incompatibility with another pinned dependency).
- **Platform compliance**: OIDC integration, Eureka registration, and Traefik routing
  configuration MUST be present and reviewed for every new service.
- `docs/` entry exists and is current for every affected service or infrastructure component.
- **Spring Cloud compliance**: Every new infrastructure service MUST use the appropriate
  Spring Cloud component (or document the exception in Complexity Tracking).
- **Container image**: Every new or modified service MUST include or update its `Dockerfile`;
  no service merges without a buildable container image.
- **Multi-stage Dockerfile**: Every custom service `Dockerfile` MUST have a `builder`,
  `test`, and `runtime` stage per Principle IX. `docker build --target test` MUST succeed
  before the PR can merge.
- **CI pipeline**: `.github/workflows/build-images.yml` MUST exist and MUST be updated to
  include any new custom service. The workflow MUST run the `test` stage in CI.
- **Docker-only tests**: All automated test runs (unit, integration, contract) MUST be
  executable via `docker build --target test` or `docker compose run` without any local
  toolchain installation. No test task in `tasks.md` MAY require a bare-metal runtime.
- **Contracts currency**: Any PR that adds, removes, or changes an API endpoint or event
  type MUST include corresponding updates to `contracts/`. No API or event type change
  merges without a matching contract update.
- **Capability metadata**: Any new cross-service capability MUST have its metadata key
  documented in `contracts/capabilities/` before the consuming side is implemented.

**Tooling constraints**:

- Branch numbering: sequential (configured in `.specify/init-options.json`).
- Script runtime: `sh` (POSIX-compatible shell scripts only).
- Git extensions are mandatory and managed via `.specify/extensions.yml`.

## Monorepo Structure

The repository MUST follow this canonical top-level directory layout. No new top-level
directories may be introduced without a constitution amendment.

```
operations-planing/
├── .github/
│   └── workflows/  # GitHub Actions CI/CD workflows. build-images.yml is mandatory
│                   # (Principle IX). No new custom service may be added without updating
│                   # this workflow.
├── contracts/      # Canonical API and event contracts — source of truth for all
│   │               # cross-service interfaces.
│   ├── api/        # OpenAPI (REST) or GraphQL schemas, one subdirectory per service:
│   │               #   contracts/api/<service-name>/openapi.yml
│   ├── events/     # Event type definitions (JSON Schema / Avro / CloudEvents format),
│   │               # one file per event type:
│   │               #   contracts/events/<event-type>.json
│   └── capabilities/ # Eureka metadata capability key registry — documents every
│                   # capability key, its meaning, and which service publishes it.
├── docs/           # User documentation — one subtree per service module and per
│                   # infrastructure component. Every module MUST have a docs entry.
├── infrastructure/ # Shared infrastructure components: central configuration service,
│                   # Keycloak realm definitions, Eureka server config, Traefik static
│                   # config, and any other platform-level components.
├── services/       # Individual service modules (e.g., estimation-service, …).
│                   # Each service is a self-contained subdirectory with its own
│                   # build file, src/, and tests/.
└── deployment/     # Deployment descriptors for the full environment:
                    #   helm/   — Helm charts (one chart per service + umbrella chart)
                    #   compose/ — Docker Compose files for local development
```

**Placement rules**:

- A new service belongs under `services/<service-name>/`.
- Platform-level components (config server, Keycloak, Eureka, Traefik) belong under
  `infrastructure/<component-name>/`.
- All Helm charts live under `deployment/helm/`; Docker Compose files under
  `deployment/compose/`.
- Documentation for a service at `services/foo/` lives at `docs/services/foo/`.
- Documentation for infrastructure at `infrastructure/bar/` lives at `docs/infrastructure/bar/`.
- API contracts for a service at `services/foo/` live at `contracts/api/foo/openapi.yml`.
- Event schemas live at `contracts/events/<event-type>.json` (service-agnostic, since
  events are consumed by multiple services).
- Cross-service capability keys are registered at `contracts/capabilities/<key>.md`.

**Rationale**: A predictable, enforced layout allows tooling, CI pipelines, and developers
to locate any artifact without searching. It also makes dependency boundaries explicit.

## Development Workflow

The standard feature lifecycle MUST follow this sequence:

1. `/speckit-git-feature` — create a numbered feature branch.
2. `/speckit-specify` — generate or update `spec.md` from a natural language description.
3. `/speckit-clarify` (as needed) — resolve ambiguities before planning.
4. `/speckit-plan` — produce `plan.md`, `research.md`, `data-model.md`, and contracts.
5. `/speckit-tasks` — generate `tasks.md` from design artifacts.
6. `/speckit-implement` — execute tasks in dependency order.
7. `/speckit-analyze` — cross-artifact consistency check before PR creation.

Skipping steps is non-compliant unless explicitly documented in the PR description with
justification. Auto-commit hooks defined in `.specify/extensions.yml` MUST remain enabled
to maintain a clean, traceable commit history aligned with workflow stage transitions.

**Code review** MUST verify:
- Spec artifacts are present and up to date.
- All Constitution Check gates in plan.md are satisfied.
- No placeholder tokens remain in any artifact.
- Platform infrastructure compliance (Principle VI) is satisfied.
- Spring Cloud mandate and container image requirement (Principle VII) are satisfied.
- Loose coupling is maintained — no new hard startup dependency on a sibling application
  service has been introduced (Principle VIII).
- `contracts/` is updated for any new or changed API endpoint, event type, or capability
  key (Principle VIII).
- Docker-first compliance (Principle IX): every new service has a multi-stage Dockerfile
  (`builder` / `test` / `runtime`); `.github/workflows/build-images.yml` is updated;
  `docker build --target test` passes locally before the PR is raised.
- `docs/` is updated for every new or modified service or infrastructure component.
- All introduced dependencies are at current stable versions (or deviation is justified).

## Governance

This constitution supersedes all other documented practices within this repository. Any
conflict between this constitution and another document defaults to the constitution unless
an explicit, documented exception is recorded in the Complexity Tracking table of the
affected feature's plan.

**Amendment procedure**:
1. Open a dedicated PR with the proposed constitution change.
2. Update `LAST_AMENDED_DATE` and increment `CONSTITUTION_VERSION` per semantic rules.
3. Propagate changes to all dependent templates (plan, spec, tasks) in the same PR.
4. Obtain at least one reviewer approval before merging.

**Versioning policy** (semantic):
- MAJOR: Backward-incompatible principle removals or redefinitions.
- MINOR: New principle or section added, or materially expanded guidance.
- PATCH: Clarifications, wording fixes, non-semantic refinements.

**Compliance review**: Every PR description MUST include a one-line statement confirming
constitution compliance or citing the documented exception.

**Version**: 1.4.0 | **Ratified**: 2026-05-15 | **Last Amended**: 2026-05-15
