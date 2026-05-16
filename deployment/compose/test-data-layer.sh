#!/bin/sh
# Integration test: Data layer deployment — startup within 60s and data persistence.
# Covers US4 acceptance scenarios (SC-004, SC-007).
#
# SC-008 (log visibility in OpenSearch within 60s) is NOT asserted here — it requires
# the observability Compose profile (logstash + opensearch) and is validated manually.
#
# Prerequisites: .env file present with APP_POSTGRES_* and NEO4J_PASSWORD set.
# Run from deployment/compose/:  sh test-data-layer.sh

set -e

COMPOSE_FILE="$(dirname "$0")/docker-compose.yml"
TIMEOUT=60
POLL_INTERVAL=5

export PGPASSWORD="${APP_POSTGRES_PASSWORD}"

PASS=0
FAIL=0

pass() { echo "[PASS] $1"; PASS=$((PASS + 1)); }
fail() { echo "[FAIL] $1"; FAIL=$((FAIL + 1)); }

# ── Helper: poll until both services healthy or timeout ──────────────────────
wait_healthy() {
  service="$1"
  elapsed=0
  while [ "$elapsed" -lt "$TIMEOUT" ]; do
    status=$(docker compose -f "$COMPOSE_FILE" ps --format "{{.Health}}" "$service" 2>/dev/null || echo "unknown")
    if [ "$status" = "healthy" ]; then
      return 0
    fi
    sleep "$POLL_INTERVAL"
    elapsed=$((elapsed + POLL_INTERVAL))
  done
  return 1
}

echo "=== Data Layer Deployment Tests ==="

# ── Step 1: Start both databases ─────────────────────────────────────────────
echo "Starting app-postgres and neo4j..."
docker compose -f "$COMPOSE_FILE" up -d app-postgres neo4j neo4j-init

# ── Test 1: Both healthy within 60 seconds (SC-004) ──────────────────────────
echo "Waiting for app-postgres health (timeout: ${TIMEOUT}s)..."
if wait_healthy "app-postgres"; then
  pass "T1: app-postgres healthy within ${TIMEOUT}s (SC-004)"
else
  fail "T1: app-postgres did NOT become healthy within ${TIMEOUT}s"
fi

echo "Waiting for neo4j health (timeout: ${TIMEOUT}s)..."
if wait_healthy "neo4j"; then
  pass "T2: neo4j healthy within ${TIMEOUT}s (SC-004)"
else
  fail "T2: neo4j did NOT become healthy within ${TIMEOUT}s"
fi

# ── Step 2: Write test data to both databases ─────────────────────────────────
TEST_UUID="deadbeef-dead-beef-dead-beefdeadbeef"
PG_HOST="${APP_POSTGRES_HOST:-app-postgres}"
PG_USER="${APP_POSTGRES_USER:-postgres}"
PG_DB="${APP_POSTGRES_DB:-app_db}"
NEO4J_HOST="${NEO4J_HOST:-neo4j}"
NEO4J_PORT="${NEO4J_PORT:-7687}"

# Write to PostgreSQL (using the public schema under superuser for persistence test only)
docker compose -f "$COMPOSE_FILE" exec -T app-postgres \
  psql -U "$PG_USER" -d "$PG_DB" -c "
    CREATE TABLE IF NOT EXISTS _deploy_test (id UUID PRIMARY KEY, tag TEXT);
    INSERT INTO _deploy_test (id, tag) VALUES ('${TEST_UUID}', 'persist-check')
    ON CONFLICT DO NOTHING;" > /dev/null

# Write to Neo4j
docker compose -f "$COMPOSE_FILE" exec -T neo4j \
  cypher-shell -u neo4j -p "${NEO4J_PASSWORD}" \
  "MERGE (:Entity {uuid: '${TEST_UUID}'});" > /dev/null

pass "T3: Test data written to both databases before restart"

# ── Step 3: Restart both databases ───────────────────────────────────────────
echo "Restarting app-postgres and neo4j..."
docker compose -f "$COMPOSE_FILE" restart app-postgres neo4j

echo "Waiting for app-postgres to recover..."
if wait_healthy "app-postgres"; then
  pass "T4: app-postgres healthy after restart"
else
  fail "T4: app-postgres did NOT recover after restart"
fi

echo "Waiting for neo4j to recover..."
if wait_healthy "neo4j"; then
  pass "T5: neo4j healthy after restart"
else
  fail "T5: neo4j did NOT recover after restart"
fi

# ── Test 2: Data persists through restart (SC-007) ────────────────────────────
pg_result=$(docker compose -f "$COMPOSE_FILE" exec -T app-postgres \
  psql -U "$PG_USER" -d "$PG_DB" -tAc \
  "SELECT count(*) FROM _deploy_test WHERE id = '${TEST_UUID}';" 2>/dev/null || echo "0")
if [ "$pg_result" = "1" ]; then
  pass "T6: PostgreSQL data persists through container restart (SC-007)"
else
  fail "T6: PostgreSQL data LOST after restart — expected 1 row, got: ${pg_result}"
fi

neo4j_result=$(docker compose -f "$COMPOSE_FILE" exec -T neo4j \
  cypher-shell -u neo4j -p "${NEO4J_PASSWORD}" \
  "MATCH (e:Entity {uuid: '${TEST_UUID}'}) RETURN count(e) AS cnt;" 2>/dev/null || echo "0")
if echo "$neo4j_result" | grep -q "^1$"; then
  pass "T7: Neo4j data persists through container restart (SC-007)"
else
  fail "T7: Neo4j data LOST after restart — result: ${neo4j_result}"
fi

# ── Cleanup test data ─────────────────────────────────────────────────────────
docker compose -f "$COMPOSE_FILE" exec -T app-postgres \
  psql -U "$PG_USER" -d "$PG_DB" -c "DROP TABLE IF EXISTS _deploy_test;" > /dev/null 2>&1 || true
docker compose -f "$COMPOSE_FILE" exec -T neo4j \
  cypher-shell -u neo4j -p "${NEO4J_PASSWORD}" \
  "MATCH (e:Entity {uuid: '${TEST_UUID}'}) DELETE e;" > /dev/null 2>&1 || true

echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
[ "$FAIL" -eq 0 ] || exit 1
