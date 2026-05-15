#!/bin/sh
# test-traefik-routing.sh — Integration test for Traefik routing.
# Starts Eureka + Traefik via docker compose, registers a stub service with
# Traefik labels, and asserts it is reachable within 30 seconds.
# Covers US1.AcceptanceScenario.2 and SC-002.
set -e

COMPOSE_FILE="${COMPOSE_FILE:-$(dirname "$0")/docker-compose.yml}"
TIMEOUT=30
STUB_HOST="stub.ops.local"
STUB_PORT=8199

cleanup() {
  echo "Cleaning up..."
  docker compose -f "$COMPOSE_FILE" rm -fsv stub-service 2>/dev/null || true
  docker compose -f "$COMPOSE_FILE" down --remove-orphans 2>/dev/null || true
}
trap cleanup EXIT INT TERM

echo "Starting Eureka + Traefik..."
docker compose -f "$COMPOSE_FILE" up -d eureka traefik

# Wait for Eureka
echo "Waiting for Eureka..."
RETRIES=12
until curl -sf http://localhost:8761/actuator/health > /dev/null 2>&1; do
  RETRIES=$((RETRIES - 1))
  [ "$RETRIES" -le 0 ] && echo "FAIL: Eureka not ready" >&2 && exit 1
  sleep 5
done
echo "Eureka ready."

# Start stub service with Traefik labels
docker run -d \
  --name stub-service \
  --network ops_app-net \
  --label "traefik.enable=true" \
  --label "traefik.http.routers.stub.rule=Host(\`${STUB_HOST}\`)" \
  --label "traefik.http.routers.stub.entrypoints=websecure" \
  --label "traefik.http.routers.stub.tls=true" \
  --label "traefik.http.services.stub.loadbalancer.server.port=80" \
  nginx:alpine

echo "Waiting up to ${TIMEOUT}s for stub to be routable via Traefik..."
START=$(date +%s)
while true; do
  NOW=$(date +%s)
  ELAPSED=$((NOW - START))
  if [ "$ELAPSED" -ge "$TIMEOUT" ]; then
    echo "FAIL: Stub service not routable after ${TIMEOUT}s" >&2
    exit 1
  fi
  STATUS=$(curl -sk -o /dev/null -w "%{http_code}" \
    --resolve "${STUB_HOST}:443:127.0.0.1" \
    "https://${STUB_HOST}/" 2>/dev/null || echo "000")
  if [ "$STATUS" = "200" ] || [ "$STATUS" = "301" ] || [ "$STATUS" = "302" ]; then
    echo "PASS: Stub reachable via Traefik (HTTP $STATUS) after ${ELAPSED}s"
    exit 0
  fi
  sleep 2
done
