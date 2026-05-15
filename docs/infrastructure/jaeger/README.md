# Jaeger

Jaeger 2.x — distributed tracing for request flow visibility across platform services.

## Purpose

Jaeger collects OpenTelemetry traces from all instrumented services and provides a UI
for trace search, timeline visualization, and service dependency graphs. It runs as
part of the optional `observability` profile.

## Enabling the Observability Profile

```bash
# Docker Compose
docker compose --profile observability up -d

# Helm
helm install core-infrastructure deployment/helm/core-infrastructure \
  -f deployment/helm/core-infrastructure/values.observability.yaml
```

## OTLP Endpoints

| Protocol | Port | Use |
|----------|------|-----|
| gRPC (OTLP) | 4317 | Spring Boot Micrometer + OTEL exporter |
| HTTP (OTLP) | 4318 | Alternative HTTP/protobuf export |
| Jaeger UI | 16686 | Browser access to trace search |

## Service Instrumentation Guide

Add to service's `pom.xml` / `build.gradle.kts`:

```kotlin
implementation("io.micrometer:micrometer-tracing-bridge-otel")
implementation("io.opentelemetry:opentelemetry-exporter-otlp")
```

Configure in service's `application.yml`:

```yaml
management:
  tracing:
    sampling:
      probability: 1.0   # sample 100% in dev; lower in prod
  otlp:
    tracing:
      endpoint: http://jaeger:4317
```

## Jaeger UI

```bash
open http://localhost:16686
```

Select a service from the dropdown, set a time range, and click **Find Traces**.

## Startup / Shutdown

```bash
docker compose --profile observability up -d jaeger
open http://localhost:16686

docker compose stop jaeger
```

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| No traces visible | Service not instrumented | Add Micrometer OTEL dependencies and configure `management.otlp.tracing.endpoint` |
| Traces missing after restart | In-memory storage cleared | Jaeger uses Badger persistent storage; ensure volume is mounted |
| Port 4317 not reachable | Observability profile not active | Start with `--profile observability` |
