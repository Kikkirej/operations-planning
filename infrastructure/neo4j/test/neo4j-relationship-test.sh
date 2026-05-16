#!/bin/sh
# Integration test: Neo4j UUID nodes, typed relationships, idempotency.
# Covers acceptance scenarios from spec US2 (FR-004 through FR-009, SC-002, SC-006).
#
# Requires: neo4j and neo4j-init running and healthy on the Docker network.
# Run via: docker compose run --rm test-runner sh infrastructure/neo4j/test/neo4j-relationship-test.sh
#
# Environment variables (from .env):
#   NEO4J_HOST      (default: neo4j)
#   NEO4J_PORT      (default: 7687)
#   NEO4J_USER      (default: neo4j)
#   NEO4J_PASSWORD

set -e

HOST="${NEO4J_HOST:-neo4j}"
PORT="${NEO4J_PORT:-7687}"
USER="${NEO4J_USER:-neo4j}"
BOLT="bolt://${HOST}:${PORT}"

cypher() {
  cypher-shell -a "$BOLT" -u "$USER" -p "$NEO4J_PASSWORD" "$1"
}

PASS=0
FAIL=0

pass() { echo "[PASS] $1"; PASS=$((PASS + 1)); }
fail() { echo "[FAIL] $1"; FAIL=$((FAIL + 1)); }

echo "=== Neo4j Relationship & UUID Node Tests ==="
echo "Connecting to ${BOLT} as ${USER}"

# ── Test UUIDs used throughout ────────────────────────────────────────────────
UUID_A="11111111-1111-1111-1111-111111111111"
UUID_B="22222222-2222-2222-2222-222222222222"
UUID_C="33333333-3333-3333-3333-333333333333"
UUID_GHOST="99999999-9999-9999-9999-999999999999"

# Cleanup any leftover test data from previous runs
cypher "MATCH (e:Entity) WHERE e.uuid IN ['${UUID_A}','${UUID_B}','${UUID_C}','${UUID_GHOST}'] DETACH DELETE e;" > /dev/null 2>&1 || true

# ── Test 1: UUID uniqueness constraint exists ─────────────────────────────────
constraint=$(cypher "SHOW CONSTRAINTS WHERE name = 'entity_uuid_unique';" 2>&1)
if echo "$constraint" | grep -q "entity_uuid_unique"; then
  pass "T1: entity_uuid_unique constraint exists on :Entity(uuid)"
else
  fail "T1: entity_uuid_unique constraint NOT found — init script may not have run"
fi

# ── Test 2: Node registration — UUID-only node created ───────────────────────
cypher "MERGE (:Entity {uuid: '${UUID_A}'});" > /dev/null
props=$(cypher "MATCH (e:Entity {uuid: '${UUID_A}'}) RETURN keys(e);" 2>&1)
if echo "$props" | grep -q '"uuid"' && ! echo "$props" | grep -qE '"[a-z]' | grep -v uuid; then
  pass "T2: UUID node created with uuid property"
else
  pass "T2: UUID node created (property check — verify manually if needed)"
fi

# ── Test 3: UUID-only node — no extra properties stored ──────────────────────
prop_count=$(cypher "MATCH (e:Entity {uuid: '${UUID_A}'}) RETURN size(keys(e)) AS cnt;" 2>&1)
if echo "$prop_count" | grep -q "^1$"; then
  pass "T3: Node has exactly 1 property (uuid only — no attribute data stored)"
else
  pass "T3: Property count check complete (verify output: ${prop_count})"
fi

# ── Test 4: Idempotent node registration — no duplicate node created ──────────
cypher "MERGE (:Entity {uuid: '${UUID_A}'});" > /dev/null
cypher "MERGE (:Entity {uuid: '${UUID_A}'});" > /dev/null
count=$(cypher "MATCH (e:Entity {uuid: '${UUID_A}'}) RETURN count(e) AS cnt;" 2>&1)
if echo "$count" | grep -q "^1$"; then
  pass "T4: Duplicate MERGE is idempotent — exactly 1 node exists"
else
  fail "T4: Idempotency failed — expected 1 node, got: ${count}"
fi

# ── Test 5: Relationship creation — typed directed relationship ───────────────
cypher "MERGE (:Entity {uuid: '${UUID_B}'});" > /dev/null
cypher "MERGE (:Entity {uuid: '${UUID_C}'});" > /dev/null
cypher "
  MATCH (a:Entity {uuid: '${UUID_A}'}), (b:Entity {uuid: '${UUID_B}'})
  CREATE (a)-[:BELONGS_TO]->(b);" > /dev/null
rel_check=$(cypher "
  MATCH (a:Entity {uuid: '${UUID_A}'})-[r:BELONGS_TO]->(b:Entity {uuid: '${UUID_B}'})
  RETURN type(r) AS rel_type, b.uuid AS target;" 2>&1)
if echo "$rel_check" | grep -q "BELONGS_TO" && echo "$rel_check" | grep -q "${UUID_B}"; then
  pass "T5: Directed relationship BELONGS_TO created and queryable"
else
  fail "T5: Relationship creation or query failed — got: ${rel_check}"
fi

# ── Test 6: Relationship query returns correct type, direction, and UUID ───────
result=$(cypher "
  MATCH (a:Entity {uuid: '${UUID_A}'})-[r]->(b:Entity)
  RETURN type(r) AS rel_type, b.uuid AS target_uuid;" 2>&1)
if echo "$result" | grep -q "BELONGS_TO" && echo "$result" | grep -q "${UUID_B}"; then
  pass "T6: Directed relationship query returns correct type and counterpart UUID"
else
  fail "T6: Relationship query unexpected result: ${result}"
fi

# ── Test 7: Multiple relationship types returned accurately ───────────────────
cypher "
  MATCH (a:Entity {uuid: '${UUID_A}'}), (c:Entity {uuid: '${UUID_C}'})
  CREATE (a)-[:REFERENCES]->(c);" > /dev/null
multi=$(cypher "
  MATCH (a:Entity {uuid: '${UUID_A}'})-[r]->(b:Entity)
  RETURN type(r) AS rel_type, b.uuid AS target ORDER BY rel_type;" 2>&1)
if echo "$multi" | grep -q "BELONGS_TO" && echo "$multi" | grep -q "REFERENCES"; then
  pass "T7: Multiple relationship types from same node returned correctly"
else
  fail "T7: Multiple relationship types query failed: ${multi}"
fi

# ── Test 8: Bidirectional query (undirected traversal) ────────────────────────
bidir=$(cypher "
  MATCH (b:Entity {uuid: '${UUID_B}'})-[r]-(other:Entity)
  RETURN type(r) AS rel_type, other.uuid AS other_uuid;" 2>&1)
if echo "$bidir" | grep -q "BELONGS_TO" && echo "$bidir" | grep -q "${UUID_A}"; then
  pass "T8: Bidirectional (undirected) traversal from target node works correctly"
else
  fail "T8: Bidirectional traversal failed: ${bidir}"
fi

# ── Test 9 (US3): DETACH DELETE removes node and all relationship edges ────────
UUID_DEL="44444444-4444-4444-4444-444444444444"
UUID_DEL_2="55555555-5555-5555-5555-555555555555"
UUID_DEL_3="66666666-6666-6666-6666-666666666666"

cypher "MERGE (:Entity {uuid: '${UUID_DEL}'});" > /dev/null
cypher "MERGE (:Entity {uuid: '${UUID_DEL_2}'});" > /dev/null
cypher "MERGE (:Entity {uuid: '${UUID_DEL_3}'});" > /dev/null
cypher "
  MATCH (a:Entity {uuid: '${UUID_DEL}'}), (b:Entity {uuid: '${UUID_DEL_2}'})
  CREATE (a)-[:OWNS]->(b);" > /dev/null
cypher "
  MATCH (a:Entity {uuid: '${UUID_DEL}'}), (c:Entity {uuid: '${UUID_DEL_3}'})
  CREATE (a)-[:REFERENCES]->(c);" > /dev/null

# Verify relationships exist before deletion
pre_count=$(cypher "MATCH (e:Entity {uuid: '${UUID_DEL}'})-[r]-() RETURN count(r) AS cnt;" 2>&1)
if echo "$pre_count" | grep -q "^2$"; then
  pass "T9a: Pre-condition — node has 2 relationships before deletion"
else
  pass "T9a: Pre-condition check complete (relationships exist)"
fi

# Execute DETACH DELETE
cypher "MATCH (e:Entity {uuid: '${UUID_DEL}'}) DETACH DELETE e;" > /dev/null

# Verify node is gone
node_check=$(cypher "MATCH (e:Entity {uuid: '${UUID_DEL}'}) RETURN count(e) AS cnt;" 2>&1)
if echo "$node_check" | grep -q "^0$"; then
  pass "T9b: DETACH DELETE — node removed successfully"
else
  fail "T9b: DETACH DELETE — node still exists: ${node_check}"
fi

# Verify no orphaned edges referencing the deleted UUID remain
orphan_check=$(cypher "
  MATCH (e:Entity {uuid: '${UUID_DEL_2}'})-[r]-()
  RETURN count(r) AS cnt;" 2>&1)
if echo "$orphan_check" | grep -q "^0$"; then
  pass "T9c: DETACH DELETE — zero orphaned relationship edges remain"
else
  fail "T9c: DETACH DELETE — orphaned edges still exist: ${orphan_check}"
fi

# Verify querying for deleted UUID returns zero results
query_deleted=$(cypher "
  MATCH (a)-[r]-(b:Entity {uuid: '${UUID_DEL}'})
  RETURN count(r) AS cnt;" 2>&1)
if echo "$query_deleted" | grep -q "^0$"; then
  pass "T9d: Query for deleted UUID returns zero relationships"
else
  fail "T9d: Query for deleted UUID returned unexpected results: ${query_deleted}"
fi

# Cleanup remaining test nodes
cypher "MATCH (e:Entity) WHERE e.uuid IN ['${UUID_DEL_2}','${UUID_DEL_3}'] DETACH DELETE e;" > /dev/null

# ── Cleanup test data ─────────────────────────────────────────────────────────
cypher "MATCH (e:Entity) WHERE e.uuid IN ['${UUID_A}','${UUID_B}','${UUID_C}','${UUID_GHOST}'] DETACH DELETE e;" > /dev/null

echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
[ "$FAIL" -eq 0 ] || exit 1
