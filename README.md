# Operations Planning Platform

A loosely coupled, microservices-based operations planning platform built on Spring Cloud,
secured with Keycloak OIDC, and deployed as OCI containers via Docker Compose and Helm.

## Repository Structure

```
operations-planing/
├── contracts/        # Canonical API and event contracts (OpenAPI, event schemas, capability keys)
├── docs/             # User documentation for all services and infrastructure components
├── infrastructure/   # Platform infrastructure services (Eureka, Keycloak, Config Server, Traefik, …)
├── services/         # Application service modules (estimation, scheduling, …)
└── deployment/
    ├── helm/         # Helm charts for Kubernetes deployment
    └── compose/      # Docker Compose files for local development
```

## Platform Infrastructure

The following infrastructure services are **always deployed** in every environment:

| Service | Role | Technology |
|---------|------|------------|
| Eureka | Service discovery & capability registry | Spring Cloud Netflix Eureka |
| Keycloak | Identity provider & OIDC authorization | Keycloak |
| Config Server | Centralised configuration from file-mount | Spring Cloud Config |
| Traefik | API gateway & reverse proxy | Traefik |
| Spring Boot Admin | Service monitoring & management | Spring Boot Admin |
| Kafka | Async event streaming between services | Apache Kafka (KRaft) |

## Quick Start (Local Development)

```bash
# Start the full infrastructure stack
docker compose -f deployment/compose/docker-compose.yml up -d

# Verify all services are healthy
docker compose -f deployment/compose/docker-compose.yml ps
```

All infrastructure services should be healthy within 2 minutes. See
[`docs/infrastructure/`](docs/infrastructure/) for per-service startup and
troubleshooting guides.

## Architecture Principles

- **Loosely coupled**: Application services activate features conditionally based on
  capability metadata discovered in Eureka — no hard startup dependencies between
  application services.
- **Zero trust**: No service trusts another based on network location alone. All
  inter-service calls are authenticated (Keycloak OIDC or Basic auth for Config Server).
- **Contract-first**: All API endpoints and event types are defined in `contracts/`
  before implementation begins.
- **Infrastructure always on**: The platform infrastructure stack is deployed in full in
  every environment; application services are deployed independently.
- **Kotlin + Spring Cloud**: All custom services are written in Kotlin on Spring Boot /
  Spring Cloud foundations.

Full governance details are in [`.specify/memory/constitution.md`](.specify/memory/constitution.md).

## Contracts

Cross-service interfaces are defined in [`contracts/`](contracts/):

- `contracts/api/<service>/openapi.yml` — REST API definitions (OpenAPI 3.x)
- `contracts/events/<event-type>.json` — Async event schemas
- `contracts/capabilities/<key>.md` — Eureka capability metadata key registry

## Documentation

User-facing documentation lives in [`docs/`](docs/):

- [`docs/infrastructure/`](docs/infrastructure/) — Infrastructure component guides
- [`docs/services/`](docs/services/) — Application service guides

## Security

Authentication uses Keycloak OIDC. The realm configuration is auto-imported on first
start from `infrastructure/keycloak/realm-export.json`. All default accounts require a
password change on first login.

See [`docs/infrastructure/keycloak/`](docs/infrastructure/keycloak/) for the security
setup guide.

## Deployment (Kubernetes)

```bash
# Deploy full infrastructure stack
helm install operations-infra deployment/helm/infrastructure/

# Deploy an application service
helm install estimation-service deployment/helm/services/estimation/
```

See [`deployment/helm/`](deployment/helm/) for chart documentation and value overrides.
# operations-planning
