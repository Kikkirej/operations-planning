#!/bin/sh
# Integration test: Application PostgreSQL schema isolation and UUID PKs.
# Covers acceptance scenarios from spec US1 (FR-001, FR-002, FR-003, SC-001, SC-005).
#
# Requires: app-postgres running and healthy on the Docker network.
# Run via: docker compose run --rm test-runner sh infrastructure/postgres/test/postgres-isolation-test.sh
#
# Environment variables (from .env):
#   APP_POSTGRES_HOST  (default: app-postgres)
#   APP_POSTGRES_USER  (default: postgres)
#   APP_POSTGRES_PASSWORD
#   APP_POSTGRES_DB    (default: app_db)

set -e

HOST="${APP_POSTGRES_HOST:-app-postgres}"
PORT="${APP_POSTGRES_PORT:-5432}"
SUPERUSER="${APP_POSTGRES_USER:-postgres}"
DB="${APP_POSTGRES_DB:-app_db}"
export PGPASSWORD="${APP_POSTGRES_PASSWORD}"

psql_cmd() {
  psql -h "$HOST" -p "$PORT" -U "$SUPERUSER" -d "$DB" -v ON_ERROR_STOP=1 "$@"
}

PASS=0
FAIL=0

pass() { echo "[PASS] $1"; PASS=$((PASS + 1)); }
fail() { echo "[FAIL] $1"; FAIL=$((FAIL + 1)); }

echo "=== PostgreSQL Schema Isolation & UUID PK Tests ==="
echo "Connecting to ${HOST}:${PORT}/${DB} as ${SUPERUSER}"

# ── Test 1: Bootstrap — app role exists ──────────────────────────────────────
result=$(psql_cmd -tAc "SELECT 1 FROM pg_roles WHERE rolname = 'app' AND rolcanlogin = true;" 2>&1)
if [ "$result" = "1" ]; then
  pass "T1: 'app' role exists with LOGIN"
else
  fail "T1: 'app' role not found or missing LOGIN — bootstrap script may not have run"
fi

# ── Setup: create two service-owned schemas for tests ────────────────────────
psql_cmd -c "DROP SCHEMA IF EXISTS test_svc_a CASCADE;" > /dev/null 2>&1 || true
psql_cmd -c "DROP SCHEMA IF EXISTS test_svc_b CASCADE;" > /dev/null 2>&1 || true
psql_cmd -c "DROP ROLE IF EXISTS test_svc_a;" > /dev/null 2>&1 || true
psql_cmd -c "DROP ROLE IF EXISTS test_svc_b;" > /dev/null 2>&1 || true

psql_cmd -c "CREATE ROLE test_svc_a WITH LOGIN PASSWORD 'test_svc_a_pass' NOINHERIT IN ROLE app;"
psql_cmd -c "CREATE SCHEMA test_svc_a AUTHORIZATION test_svc_a;"
psql_cmd -c "REVOKE ALL ON SCHEMA public FROM test_svc_a;"
psql_cmd -c "GRANT USAGE, CREATE ON SCHEMA test_svc_a TO test_svc_a;"

psql_cmd -c "CREATE ROLE test_svc_b WITH LOGIN PASSWORD 'test_svc_b_pass' NOINHERIT IN ROLE app;"
psql_cmd -c "CREATE SCHEMA test_svc_b AUTHORIZATION test_svc_b;"
psql_cmd -c "REVOKE ALL ON SCHEMA public FROM test_svc_b;"
psql_cmd -c "GRANT USAGE, CREATE ON SCHEMA test_svc_b TO test_svc_b;"

# ── Test 2: UUID PK — service A creates table with UUID primary key ───────────
export PGPASSWORD="test_svc_a_pass"
psql_cmd_a() {
  psql -h "$HOST" -p "$PORT" -U "test_svc_a" -d "$DB" -v ON_ERROR_STOP=1 "$@"
}

psql_cmd_a -c "
  CREATE TABLE test_svc_a.orders (
    id UUID PRIMARY KEY,
    label TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
  );"
pass "T2: Service A created table with UUID primary key"

# ── Test 3: CRUD succeeds in owned schema ────────────────────────────────────
TEST_UUID="a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11"
psql_cmd_a -c "INSERT INTO test_svc_a.orders (id, label) VALUES ('${TEST_UUID}', 'test-order');"
result=$(psql_cmd_a -tAc "SELECT label FROM test_svc_a.orders WHERE id = '${TEST_UUID}';")
if [ "$result" = "test-order" ]; then
  pass "T3: CRUD succeeds — record created and retrieved by UUID"
else
  fail "T3: CRUD failed — expected 'test-order', got '${result}'"
fi

# ── Test 4: Cross-schema access rejected ─────────────────────────────────────
cross_result=$(psql_cmd_a -c "SELECT * FROM test_svc_b.orders;" 2>&1 || true)
if echo "$cross_result" | grep -qi "permission denied"; then
  pass "T4: Cross-schema access correctly rejected with permission denied"
else
  fail "T4: Cross-schema access was NOT rejected — got: ${cross_result}"
fi

# ── Test 5: Non-UUID value rejected by type constraint ───────────────────────
bad_insert=$(psql_cmd_a -c "INSERT INTO test_svc_a.orders (id, label) VALUES ('not-a-uuid', 'bad');" 2>&1 || true)
if echo "$bad_insert" | grep -qi "invalid input syntax"; then
  pass "T5: UUID type constraint enforced — non-UUID value rejected"
else
  fail "T5: UUID type constraint NOT enforced — non-UUID value was accepted"
fi

# ── Test 6: Cross-schema read as service B also rejected ─────────────────────
export PGPASSWORD="test_svc_b_pass"
psql_cmd_b() {
  psql -h "$HOST" -p "$PORT" -U "test_svc_b" -d "$DB" -v ON_ERROR_STOP=1 "$@"
}
cross_b=$(psql_cmd_b -c "SELECT * FROM test_svc_a.orders;" 2>&1 || true)
if echo "$cross_b" | grep -qi "permission denied"; then
  pass "T6: Service B cannot read Service A schema — permission denied"
else
  fail "T6: Service B READ on Service A schema NOT rejected — got: ${cross_b}"
fi

# ── Cleanup ───────────────────────────────────────────────────────────────────
export PGPASSWORD="${APP_POSTGRES_PASSWORD}"
psql_cmd -c "DROP SCHEMA IF EXISTS test_svc_a CASCADE;" > /dev/null
psql_cmd -c "DROP SCHEMA IF EXISTS test_svc_b CASCADE;" > /dev/null
psql_cmd -c "DROP ROLE IF EXISTS test_svc_a;" > /dev/null
psql_cmd -c "DROP ROLE IF EXISTS test_svc_b;" > /dev/null

echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
[ "$FAIL" -eq 0 ] || exit 1
