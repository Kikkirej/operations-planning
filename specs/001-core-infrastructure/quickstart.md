# Quickstart: Core Infrastructure Platform

**Date**: 2026-05-15 | **Branch**: `002-core-infrastructure`

> **Security Notice**: All default credentials in `.env.example` are placeholder values
> marked `CHANGE_ME_BEFORE_USE`. You MUST rotate every password and secret before exposing
> any service beyond `localhost`. Never commit `.env` (only `.env.example`). See
> `docs/infrastructure/keycloak/README.md` and `docs/infrastructure/config-server/README.md`
> for credential rotation guidance.

---

## Prerequisites

| Tool | Minimum Version | Check |
|------|----------------|-------|
| Docker Engine | 26.x | `docker --version` |
| Docker Compose | v2.x (plugin) | `docker compose version` |
| Helm | 3.x | `helm version` |
| kubectl | 1.29+ | `kubectl version --client` |
| JVM | 21 LTS | `java -version` |
| Gradle | 8.x (wrapper) | `./gradlew --version` |

**Hardware (local dev)**: ≥ 8 GB RAM, ≥ 4 CPU cores for the default core stack. Add
≥ 6 GB RAM for the observability profile.

---

## Local Development — Docker Compose

### 1. Clone and configure environment

```bash
git clone <repo-url> operations-planing
cd operations-planing
cp deployment/compose/.env.example deployment/compose/.env
# Edit .env — fill in all required credentials (see below)
```

**Required environment variables** (`.env`):

| Variable | Description |
|----------|-------------|
| `KEYCLOAK_ADMIN` | Keycloak admin username |
| `KEYCLOAK_ADMIN_PASSWORD` | Keycloak admin password (rotate after first login) |
| `KC_DB_USERNAME` | PostgreSQL username for Keycloak |
| `KC_DB_PASSWORD` | PostgreSQL password for Keycloak |
| `CONFIG_SERVER_USERNAME` | Basic auth username for Config Server |
| `CONFIG_SERVER_PASSWORD` | Basic auth password for Config Server |
| `CONFIG_REPO_PATH` | Absolute path to the config repository on the host |

### 2. Start the core stack

```bash
docker compose -f deployment/compose/docker-compose.yml up -d
```

All seven services (Eureka, Keycloak-PostgreSQL, Keycloak, Config Server, Traefik,
Spring Boot Admin, Kafka) start and pass health checks within 2 minutes on a
standard development machine.

### 3. Verify health

```bash
# Eureka dashboard
open http://localhost:8761

# Spring Boot Admin (Keycloak login required — use a user with sba-admin role)
open https://admin.ops.local

# Keycloak admin console
open https://auth.ops.local/admin

# Traefik dashboard
open http://localhost:8080/dashboard/
```

### 4. Start with observability (optional)

```bash
docker compose -f deployment/compose/docker-compose.yml \
  --profile observability up -d
```

Additional services started: Jaeger, Logstash, OpenSearch, OpenSearch Dashboards.

| UI | URL |
|----|-----|
| Jaeger | http://localhost:16686 |
| OpenSearch Dashboards | http://localhost:5601 |

### 5. Trigger a config refresh

```bash
curl -X POST -u "${CONFIG_SERVER_USERNAME}:${CONFIG_SERVER_PASSWORD}" \
  http://localhost:8888/actuator/busrefresh
```

All subscribed services reload configuration from the mounted config repository.

### 6. Tear down

```bash
docker compose -f deployment/compose/docker-compose.yml down
# Add -v to also remove named volumes (destroys Keycloak and Kafka data)
docker compose -f deployment/compose/docker-compose.yml down -v
```

---

## Kubernetes — Helm

### 1. Install the core infrastructure chart

```bash
helm install core-infra deployment/helm/core-infrastructure/ \
  --namespace ops-platform \
  --create-namespace \
  -f deployment/helm/core-infrastructure/values.yaml \
  --set keycloak.adminPassword="${KEYCLOAK_ADMIN_PASSWORD}" \
  --set keycloak.db.password="${KC_DB_PASSWORD}" \
  --set configServer.basicAuth.password="${CONFIG_SERVER_PASSWORD}"
```

All services reach `Running` status and pass readiness probes within 3 minutes.

### 2. Install with observability

```bash
helm install core-infra deployment/helm/core-infrastructure/ \
  --namespace ops-platform \
  --create-namespace \
  -f deployment/helm/core-infrastructure/values.yaml \
  -f deployment/helm/core-infrastructure/values.observability.yaml \
  --set keycloak.adminPassword="${KEYCLOAK_ADMIN_PASSWORD}" \
  --set keycloak.db.password="${KC_DB_PASSWORD}" \
  --set configServer.basicAuth.password="${CONFIG_SERVER_PASSWORD}"
```

### 3. Upgrade

```bash
helm upgrade core-infra deployment/helm/core-infrastructure/ \
  --namespace ops-platform \
  -f deployment/helm/core-infrastructure/values.yaml
```

### 4. Uninstall

```bash
helm uninstall core-infra --namespace ops-platform
# PVCs are NOT deleted automatically; remove manually if data is no longer needed:
kubectl delete pvc -n ops-platform --all
```

---

## Onboarding a New Service

To register a new application service in the platform, add the following to the
service's configuration (no platform code changes required — SC-006):

```yaml
# application.yml (served by Config Server)
eureka:
  client:
    service-url:
      defaultZone: http://eureka:8761/eureka/
  instance:
    prefer-ip-address: true

spring:
  config:
    import: "configserver:http://config-server:8888"
  security:
    oauth2:
      resourceserver:
        jwt:
          issuer-uri: http://keycloak:8080/realms/operations
  kafka:
    bootstrap-servers: kafka:9092
    consumer:
      group-id: ${spring.application.name}
      auto-offset-reset: earliest
```

And in the service's Docker Compose labels:

```yaml
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.<service-name>.rule=Host(`<service-name>.ops.local`)"
  - "traefik.http.routers.<service-name>.entrypoints=websecure"
  - "traefik.http.routers.<service-name>.tls=true"
  - "traefik.http.services.<service-name>.loadbalancer.server.port=<port>"
```

Register the service as a Keycloak client in the `operations` realm export and run
`POST /actuator/busrefresh` on Config Server to propagate any new configuration.

---

## Common Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| Keycloak fails to start | PostgreSQL not healthy yet | Wait for `keycloak-postgres` healthcheck; check `KC_DB_*` env vars |
| Realm not imported | `realm-export.json` not mounted correctly | Verify volume mount and file path |
| Config Server returns 401 | Wrong Basic auth credentials | Check `CONFIG_SERVER_USERNAME`/`CONFIG_SERVER_PASSWORD` |
| Service not appearing in Eureka | Missing Eureka client config | Verify `eureka.client.service-url.defaultZone` |
| SBA login loop | Keycloak `spring-boot-admin` client misconfigured | Verify redirect URI and `sba-admin` role assignment |
| Kafka topic not found | Init script didn't run or failed | Check init container logs; verify `topics.yml` |
| Traefik route not found | Missing `traefik.enable=true` label | Add required Traefik labels to service container |
