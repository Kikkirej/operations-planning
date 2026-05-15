# Spring Boot Admin

Spring Boot Admin Server — centralized monitoring dashboard for all registered Spring Boot services.

## Purpose

SBA discovers services via Eureka and aggregates health status, metrics, environment variables,
log levels, and thread dumps from each service's `/actuator` endpoints. Access to the UI is
restricted to users holding the `sba-admin` Keycloak role.

## Prerequisites for Monitored Services

Any service to be visible in SBA must:

1. Expose Spring Boot Actuator endpoints (add `spring-boot-starter-actuator` dependency).
2. Register with Eureka (SBA discovers services via Eureka, not direct registration).
3. Expose at minimum `/actuator/health` and `/actuator/info`.

```yaml
management:
  endpoints:
    web:
      exposure:
        include: health,info,metrics,loggers,env
  endpoint:
    health:
      show-details: always
```

## Configuration Reference

| Variable | Default | Description |
|----------|---------|-------------|
| `EUREKA_CLIENT_SERVICEURL_DEFAULTZONE` | `http://eureka:8761/eureka/` | Eureka registry URL |
| `KEYCLOAK_URL` | `http://keycloak:8080` | Keycloak issuer base URL |
| `KEYCLOAK_CLIENT_SECRET` | — | OAuth2 client secret for `spring-boot-admin` client |
| `SERVER_PORT` | `8090` | HTTP port |

## Keycloak Login

SBA is protected by Keycloak OAuth2 Login. Only users with the `sba-admin` realm role
can access the UI. After Phase 5 (US3 implementation), unauthenticated access redirects
to the Keycloak login page at `https://auth.ops.local`.

## Startup / Shutdown

```bash
docker compose up -d eureka spring-boot-admin
open https://admin.ops.local

docker compose stop spring-boot-admin
```

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| Redirect loop on login | `spring-boot-admin` Keycloak client redirect URI mismatch | Verify redirect URI in `realm-export.json` matches `KEYCLOAK_URL` |
| Service shows as DOWN | `/actuator/health` not exposed | Add `health` to `management.endpoints.web.exposure.include` |
| 403 after login | User lacks `sba-admin` role | Assign `sba-admin` realm role to the user in Keycloak admin |
| SBA not discovering services | Eureka client misconfigured | Verify `eureka.client.service-url.defaultZone` |
