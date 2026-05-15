# Spring Cloud Config Server

Spring Cloud Config Server — centralised external configuration for all registered services.

## Purpose

Config Server serves per-application, per-profile property files from a mounted config
repository. Services fetch their configuration on startup and can reload it platform-wide
via a single Spring Cloud Bus refresh call without restarts.

## Config Repository Layout

Mount a directory at `/config` inside the container. Files follow the naming convention:

```
/config
├── application.yml          # shared defaults for all services
├── myapp.yml                # service-specific defaults
├── myapp-dev.yml            # dev profile overrides
└── myapp-prod.yml           # prod profile overrides
```

A client service fetches configuration at: `GET /myapp/dev` (application name + profile).

## Basic Auth Setup

All config fetch endpoints require HTTP Basic authentication. Supply credentials via
environment variables — never hardcode them:

```bash
CONFIG_SERVER_USERNAME=config
CONFIG_SERVER_PASSWORD=<strong-secret>   # CHANGE_ME_BEFORE_USE
```

Client services must configure:

```yaml
spring:
  cloud:
    config:
      uri: http://config-server:8888
      username: ${CONFIG_SERVER_USERNAME}
      password: ${CONFIG_SERVER_PASSWORD}
```

## Spring Cloud Bus Refresh

After updating a config file in the repository, broadcast a reload to all connected clients:

```bash
curl -X POST -u "$CONFIG_SERVER_USERNAME:$CONFIG_SERVER_PASSWORD" \
  https://config.ops.local/actuator/busrefresh
```

All services subscribed to the `springCloudBus` Kafka topic receive a
`RefreshRemoteApplicationEvent` and reload `@RefreshScope` beans without restart.

## Profile Guide

| Profile | Use Case |
|---------|----------|
| `default` | Production-safe baseline; no debug logging |
| `dev` | Local development overrides; verbose logging, debug endpoints |
| `prod` | Production hardening; logging to JSON, secrets from env |

## Docker-First Build

```bash
# Run tests only (CI gate)
docker build --target test -f infrastructure/config-server/Dockerfile .

# Build runtime image
docker build --target runtime -f infrastructure/config-server/Dockerfile \
  -t ghcr.io/kikkirej/ops/config-server:local .
```

## Configuration Reference

| Variable | Default | Description |
|----------|---------|-------------|
| `CONFIG_SERVER_USERNAME` | `config` | Basic auth username |
| `CONFIG_SERVER_PASSWORD` | — | Basic auth password (required) |
| `KAFKA_BOOTSTRAP_SERVERS` | `kafka:9092` | Kafka bootstrap for Spring Cloud Bus |
| `EUREKA_CLIENT_SERVICEURL_DEFAULTZONE` | `http://eureka:8761/eureka/` | Eureka registry URL |
| `SERVER_PORT` | `8888` | HTTP port |
| `CONFIG_REPO_PATH` | — | Host path bind-mounted to `/config` |

## Startup / Shutdown

```bash
docker compose up -d eureka kafka config-server
open https://config.ops.local/myapp/default

docker compose stop config-server
```

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| 401 on config fetch | Wrong credentials or not passed | Verify `CONFIG_SERVER_USERNAME`/`PASSWORD` env vars match client config |
| 404 on `/{app}/{profile}` | Config file not in repo | Check file exists in `CONFIG_REPO_PATH` with correct naming (`appname.yml`) |
| Stale config after file change | Bus refresh not triggered | `POST /actuator/busrefresh` with Basic auth |
| Bus refresh has no effect | Client not subscribed to Kafka bus | Add `spring-cloud-starter-bus-kafka` to client dependencies |
| Config Server not starting | `CONFIG_SERVER_PASSWORD` not set | Supply the env variable — it has no default |
