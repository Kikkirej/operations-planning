# Eureka Service Registry

Spring Cloud Netflix Eureka Server — service registration and discovery hub for the platform.

## Purpose

Eureka is the central service registry. Every application service registers on startup and
deregisters on graceful shutdown. Traefik and Spring Boot Admin discover services through it.

## Configuration Reference

| Variable | Default | Description |
|----------|---------|-------------|
| `KEYCLOAK_URL` | `http://keycloak:8080` | Keycloak issuer base URL for JWT validation |
| `SERVER_PORT` | `8761` | HTTP port |

Key `application.yml` settings:

```yaml
eureka.client.register-with-eureka: false   # Server does not register itself
eureka.client.fetch-registry: false          # Server does not replicate
eureka.server.eviction-interval-timer-in-ms: 30000  # Evict stale instances every 30s
eureka.server.enable-self-preservation: false        # Evict immediately in dev
```

## Onboarding a New Service

Add to the service's `application.yml`:

```yaml
eureka:
  client:
    service-url:
      defaultZone: http://eureka:8761/eureka/
  instance:
    prefer-ip-address: true
    metadata-map:
      capabilities: "your-capability-key"   # optional, see contracts/capabilities/
```

The service appears in the Eureka dashboard within 30 s of startup.

## Startup / Shutdown

```bash
# Start only Eureka
docker compose up -d eureka

# Verify
curl http://localhost:8761/actuator/health

# Stop
docker compose stop eureka
```

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| Service not appearing after 60 s | Wrong `defaultZone` URL | Verify `eureka.client.service-url.defaultZone` |
| Stale instance stays in registry | Self-preservation mode | Ensure `enable-self-preservation: false` in dev |
| Service evicted immediately | Heartbeat interval too long | Reduce `eureka.instance.lease-renewal-interval-in-seconds` |
| 401 on REST API | JWT validation enabled | Provide valid Keycloak token in `Authorization: Bearer` header |
