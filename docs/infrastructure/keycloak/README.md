# Keycloak

Keycloak 26.x — OIDC identity provider for the operations platform.

## Purpose

Keycloak enforces zero-trust authentication across all platform services. The `operations`
realm is auto-imported on first startup from `realm-export.json`. All inter-service
communication requires Keycloak-issued JWT tokens.

## Realm Management

### Export / Import Workflow

After changing realm configuration via the Keycloak Admin UI, export the updated realm
and commit the result:

```bash
# Export from running Keycloak
docker compose exec keycloak /opt/keycloak/bin/kc.sh export \
  --realm operations \
  --dir /tmp/export \
  --users realm_file

docker compose cp keycloak:/tmp/export/operations-realm.json \
  infrastructure/keycloak/realm-export.json
```

On next Keycloak restart with `--import-realm`, the exported realm replaces the live realm.

### Updating realm-export.json

Edit `infrastructure/keycloak/realm-export.json` directly for:
- Adding new clients (copy an existing entry, change `clientId` and `secret`)
- Adding new roles (add to `roles.realm` array)
- Changing token lifetimes (`accessTokenLifespan`, `ssoSessionIdleTimeout`)

**Never commit real credentials** — use `CHANGE_ME_BEFORE_USE` placeholder values and
supply real values via environment variables at deployment time.

## Client Registration Guide

Three client types are used in this platform:

| Type | Clients | Grant Type |
|------|---------|-----------|
| Bearer-only | `eureka-server`, `config-server` | JWT validation only, no login |
| Authorization Code | `spring-boot-admin` | User-facing OAuth2 login |

To register a new application service as a bearer-only resource server, add to `realm-export.json`:

```json
{
  "clientId": "my-service",
  "name": "My Service",
  "enabled": true,
  "protocol": "openid-connect",
  "publicClient": false,
  "bearerOnly": true,
  "standardFlowEnabled": false,
  "serviceAccountsEnabled": false,
  "secret": "CHANGE_ME_MY_SERVICE_SECRET"
}
```

## Forced Password Change Setup

The default `admin` user in `realm-export.json` has `"requiredActions": ["UPDATE_PASSWORD"]`
and `"temporary": true` on the credential. On first login, Keycloak forces a password change
before granting access. To add this requirement to other users:

1. Set the credential's `"temporary": true` in `realm-export.json`, or
2. Via Admin UI: Users → select user → Credentials → toggle "Temporary"

## Zero-Trust Model

All service endpoints validate Keycloak-issued JWT tokens. No implicit internal trust:

- **Eureka**: requires JWT on `/eureka/**` endpoints (resource server)
- **Config Server**: uses HTTP Basic auth for config fetch (bootstrapping exception — see
  `plan.md` Complexity Tracking), JWT for actuator endpoints
- **Spring Boot Admin**: OAuth2 Login, requires `sba-admin` realm role

## Configuration Reference

| Variable | Default | Description |
|----------|---------|-------------|
| `KEYCLOAK_ADMIN` | — | Initial admin username |
| `KEYCLOAK_ADMIN_PASSWORD` | — | Initial admin password (CHANGE_ME_BEFORE_USE) |
| `KC_DB` | `postgres` | Database type |
| `KC_DB_URL` | — | JDBC URL for PostgreSQL |
| `KC_DB_USERNAME` | — | Database username |
| `KC_DB_PASSWORD` | — | Database password (CHANGE_ME_BEFORE_USE) |
| `KC_PROXY` | `edge` | Proxy mode (Traefik terminates TLS) |
| `KC_HOSTNAME_STRICT` | `false` | Allow any hostname in dev |

## Startup / Shutdown

```bash
docker compose up -d keycloak-postgres keycloak
open https://auth.ops.local/admin

docker compose stop keycloak keycloak-postgres
```

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| Realm not imported on startup | `--import-realm` flag missing or wrong mount path | Verify command includes `--import-realm`; check bind-mount path |
| 401 on service endpoints | Token from wrong realm | Ensure client uses `operations` realm issuer URI |
| Token accepted but 403 | User lacks required role | Assign realm role in Keycloak admin |
| Admin login fails | Initial admin credentials not set | Verify `KEYCLOAK_ADMIN` and `KEYCLOAK_ADMIN_PASSWORD` env vars |
| DB connection error | PostgreSQL not ready | Ensure `keycloak-postgres` health check passes before Keycloak starts |
| H2 database in use | `KC_DB` env not set | Set `KC_DB=postgres` and all `KC_DB_*` vars |
