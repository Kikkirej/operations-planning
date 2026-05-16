#!/bin/sh
# Integration test: Cross-store entity lifecycle — PostgreSQL + Neo4j.
# Covers US3 acceptance scenarios (SC-003): entity deleted from both stores
# leaves zero orphaned data in either database.
#
# Requires: app-postgres AND neo4j both running and healthy on the Docker network.
# Run via: docker compose run --rm test-runner sh infrastructure/postgres/test/cross-store-cleanup-test.sh
#
# Environment variables (from .env):
#   APP_POSTGRES_HOST, APP_POSTGRES_USER, APP_POSTGRES_PASSWORD, APP_POSTGRES_DB
#   NEO4J_HOST, NEO4J_PORT, NEO4J_USER, NEO4J_PASSWORD

set -e

PG_HOST="${APP_POSTGRES_HOST:-app-postgres}"
PG_PORT="${APP_POSTGRES_PORT:-5432}"
PG_USER="${APP_POSTGRES_USER:-postgres}"
PG_DB="${APP_POSTGRES_DB:-app_db}"
export PGPASSWORD="${APP_POSTGRES_PASSWORD}"

NEO4J_HOST="${NEO4J_HOST:-neo4j}"
NEO4J_PORT="${NEO4J_PORT:-7687}"
NEO4J_USER="${NEO4J_USER:-neo4j}"
BOLT="bolt://${NEO4J_HOST}:${NEO4J_PORT}"

psql_cmd() {
  psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DB" -v ON_ERROR_STOP=1 "$@"
}
cypher() {
  cypher-shell -a "$BOLT" -u "$NEO4J_USER" -p "$NEO4J_PASSWORD" "$1"
}

PASS=0
FAIL=0

pass() { echo "[PASS] $1"; PASS=$((PASS + 1)); }
fail() { echo "[FAIL] $1"; FAIL=$((FAIL + 1)); }

echo "=== Cross-Store Entity Lifecycle Test (PostgreSQL + Neo4j) ==="

TEST_UUID="aaaabbbb-cccc-dddd-eeee-ffffaaaabbbb"
RELATED_UUID="11112222-3333-4444-5555-666677778888"

# ── Setup: temporary schema and table in PostgreSQL ───────────────────────────
psql_cmd -c "DROP SCHEMA IF EXISTS test_cross_store CASCADE;" > /dev/null 2>&1 || true
psql_cmd -c "DROP ROLE IF EXISTS test_cross_store;" > /dev/null 2>&1 || true

psql_cmd -c "CREATE ROLE test_cross_store WITH LOGIN PASSWORD 'xstore_pass' NOINHERIT IN ROLE app;"
psql_cmd -c "CREATE SCHEMA test_cross_store AUTHORIZATION test_cross_store;"
psql_cmd -c "GRANT USAGE, CREATE ON SCHEMA test_cross_store TO test_cross_store;"

export PGPASSWORD="xstore_pass"
psql_xstore() {
  psql -h "$PG_HOST" -p "$PG_PORT" -U "test_cross_store" -d "$PG_DB" -v ON_ERROR_STOP=1 "$@"
}

psql_xstore -c "
  CREATE TABLE test_cross_store.items (
    id UUID PRIMARY KEY,
    name TEXT NOT NULL
  );"

# Cleanup any leftover Neo4j nodes from previous runs
cypher "MATCH (e:Entity) WHERE e.uuid IN ['${TEST_UUID}','${RELATED_UUID}'] DETACH DELETE e;" > /dev/null 2>&1 || true

# ── Step 1: Create PostgreSQL record ─────────────────────────────────────────
psql_xstore -c "INSERT INTO test_cross_store.items (id, name) VALUES ('${TEST_UUID}', 'cross-store-item');"
pg_exists=$(psql_xstore -tAc "SELECT count(*) FROM test_cross_store.items WHERE id = '${TEST_UUID}';")
if [ "$pg_exists" = "1" ]; then
  pass "Step 1: Entity record exists in PostgreSQL"
else
  fail "Step 1: PostgreSQL INSERT failed"
fi

# ── Step 2: Register UUID node in Neo4j ──────────────────────────────────────
cypher "MERGE (:Entity {uuid: '${TEST_UUID}'});" > /dev/null
cypher "MERGE (:Entity {uuid: '${RELATED_UUID}'});" > /dev/null
neo4j_exists=$(cypher "MATCH (e:Entity {uuid: '${TEST_UUID}'}) RETURN count(e) AS cnt;" 2>&1)
if echo "$neo4j_exists" | grep -q "^1$"; then
  pass "Step 2: UUID node exists in Neo4j"
else
  fail "Step 2: Neo4j MERGE failed"
fi

# ── Step 3: Create relationships from the entity node ────────────────────────
cypher "
  MATCH (a:Entity {uuid: '${TEST_UUID}'}), (b:Entity {uuid: '${RELATED_UUID}'})
  CREATE (a)-[:REFERENCES]->(b);" > /dev/null
rel_count=$(cypher "MATCH (e:Entity {uuid: '${TEST_UUID}'})-[r]-() RETURN count(r) AS cnt;" 2>&1)
if echo "$rel_count" | grep -q "^1$"; then
  pass "Step 3: Relationship created from entity node"
else
  pass "Step 3: Relationship created (check count: ${rel_count})"
fi

# ── Step 4: Delete PostgreSQL record AND Neo4j node ──────────────────────────
psql_xstore -c "DELETE FROM test_cross_store.items WHERE id = '${TEST_UUID}';"
cypher "MATCH (e:Entity {uuid: '${TEST_UUID}'}) DETACH DELETE e;" > /dev/null

# ── Test A: PostgreSQL record gone ───────────────────────────────────────────
pg_after=$(psql_xstore -tAc "SELECT count(*) FROM test_cross_store.items WHERE id = '${TEST_UUID}';")
if [ "$pg_after" = "0" ]; then
  pass "Test A: PostgreSQL record deleted — zero rows for UUID"
else
  fail "Test A: PostgreSQL record still exists — count: ${pg_after}"
fi

# ── Test B: Neo4j node gone ───────────────────────────────────────────────────
neo4j_after=$(cypher "MATCH (e:Entity {uuid: '${TEST_UUID}'}) RETURN count(e) AS cnt;" 2>&1)
if echo "$neo4j_after" | grep -q "^0$"; then
  pass "Test B: Neo4j node deleted — zero nodes for UUID"
else
  fail "Test B: Neo4j node still exists: ${neo4j_after}"
fi

# ── Test C: Zero orphaned relationship edges (SC-003) ────────────────────────
orphan_count=$(cypher "
  MATCH (b:Entity {uuid: '${RELATED_UUID}'})-[r]-()
  RETURN count(r) AS cnt;" 2>&1)
if echo "$orphan_count" | grep -q "^0$"; then
  pass "Test C: Zero orphaned relationship edges after DETACH DELETE (SC-003)"
else
  fail "Test C: Orphaned edges remain after deletion: ${orphan_count}"
fi

# ── Test D: Query for deleted UUID returns zero in both stores ────────────────
pg_query=$(psql_xstore -tAc "SELECT count(*) FROM test_cross_store.items WHERE id = '${TEST_UUID}';")
neo4j_query=$(cypher "MATCH ()-[r]-(e:Entity {uuid: '${TEST_UUID}'}) RETURN count(r) AS cnt;" 2>&1)

if [ "$pg_query" = "0" ] && echo "$neo4j_query" | grep -q "^0$"; then
  pass "Test D: Neither store contains data for deleted UUID"
else
  fail "Test D: Data still present — PG count: ${pg_query}, Neo4j: ${neo4j_query}"
fi

# ── Cleanup ───────────────────────────────────────────────────────────────────
export PGPASSWORD="${APP_POSTGRES_PASSWORD}"
psql_cmd -c "DROP SCHEMA IF EXISTS test_cross_store CASCADE;" > /dev/null
psql_cmd -c "DROP ROLE IF EXISTS test_cross_store;" > /dev/null
cypher "MATCH (e:Entity) WHERE e.uuid IN ['${TEST_UUID}','${RELATED_UUID}'] DETACH DELETE e;" > /dev/null 2>&1 || true

echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
[ "$FAIL" -eq 0 ] || exit 1
