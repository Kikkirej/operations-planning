#!/bin/sh
# Smoke test: verify docker compose up starts all core services and they pass health checks.
# Also verifies the observability profile starts the correct additional services.
# Run from a host with Docker + Docker Compose CLI access.
# Exits 0 on success, 1 on failure. Cleans up regardless of outcome.

set -e

COMPOSE_DIR="$(cd "$(dirname "$0")" && pwd)"
CORE_TIMEOUT=120
OBS_TIMEOUT=180
RETRY_INTERVAL=5

log() { printf '[test-compose] %s\n' "$1"; }
fail() { log "FAIL: $1"; cleanup; exit 1; }

cleanup() {
  log "Cleaning up ..."
  docker compose -f "$COMPOSE_DIR/docker-compose.yml" --profile observability down -v --remove-orphans > /dev/null 2>&1 || true
}

# Ensure .env exists (copy from example if needed)
if [ ! -f "$COMPOSE_DIR/.env" ]; then
  if [ -f "$COMPOSE_DIR/.env.example" ]; then
    cp "$COMPOSE_DIR/.env.example" "$COMPOSE_DIR/.env"
    log "Copied .env.example to .env for test run"
  else
    fail ".env file missing and no .env.example found"
  fi
fi

wait_healthy() {
  local service="$1"
  local url="$2"
  local timeout="$3"
  local elapsed=0

  log "Waiting for $service at $url (max ${timeout}s) ..."
  until curl -sf "$url" > /dev/null 2>&1; do
    if [ "$elapsed" -ge "$timeout" ]; then
      log "FAIL: $service did not become healthy within ${timeout}s"
      return 1
    fi
    sleep "$RETRY_INTERVAL"
    elapsed=$((elapsed + RETRY_INTERVAL))
  done
  log "  ✓ $service healthy"
}

# ─── Test 1: Core stack ────────────────────────────────────────────────────────
log "=== Test 1: Core stack (7 services) ==="
docker compose -f "$COMPOSE_DIR/docker-compose.yml" up -d \
  keycloak-postgres keycloak eureka traefik kafka kafka-init config-server spring-boot-admin

wait_healthy "eureka"           "http://localhost:8761/actuator/health"  "$CORE_TIMEOUT" || fail "eureka unhealthy"
wait_healthy "spring-boot-admin" "http://localhost:8090/actuator/health"  "$CORE_TIMEOUT" || fail "spring-boot-admin unhealthy"
wait_healthy "config-server"    "http://localhost:8888/actuator/health"  "$CORE_TIMEOUT" || fail "config-server unhealthy"
wait_healthy "keycloak"         "http://localhost:8080/realms/master"    "$CORE_TIMEOUT" || fail "keycloak unhealthy"

# Assert 0 observability containers running without profile
OBS_COUNT=$(docker compose -f "$COMPOSE_DIR/docker-compose.yml" ps --services | \
  grep -cE "jaeger|opensearch|logstash|opensearch-dashboards" || true)
if [ "$OBS_COUNT" -gt 0 ]; then
  fail "Observability services ($OBS_COUNT) started without --profile observability"
fi
log "  ✓ 0 observability services started (correct)"
log "=== Test 1 PASSED ==="

# ─── Test 2: Observability profile ───────────────────────────────────────────
log "=== Test 2: Observability profile ==="
docker compose -f "$COMPOSE_DIR/docker-compose.yml" --profile observability up -d

wait_healthy "jaeger"                "http://localhost:16686/"           "$OBS_TIMEOUT" || fail "jaeger unhealthy"
wait_healthy "opensearch"            "http://localhost:9200/_cluster/health" "$OBS_TIMEOUT" || fail "opensearch unhealthy"
wait_healthy "opensearch-dashboards" "http://localhost:5601/api/status"  "$OBS_TIMEOUT" || fail "opensearch-dashboards unhealthy"

log "=== Test 2 PASSED ==="

cleanup
log "All assertions passed."
exit 0
