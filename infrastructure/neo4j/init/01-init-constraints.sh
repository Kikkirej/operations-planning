#!/bin/sh
# Bootstrap script for the Neo4j graph database.
# Creates the UUID uniqueness constraint on :Entity nodes.
# Run once after Neo4j is healthy (neo4j-init service in Docker Compose,
# or init container in Kubernetes).

set -e

NEO4J_HOST="${NEO4J_HOST:-neo4j}"
NEO4J_PORT="${NEO4J_PORT:-7687}"
NEO4J_USER="${NEO4J_USER:-neo4j}"

echo "Waiting for Neo4j bolt on ${NEO4J_HOST}:${NEO4J_PORT}..."

# Poll until cypher-shell can connect (max 60 retries × 2s = 2 minutes)
retries=60
until cypher-shell \
  -a "bolt://${NEO4J_HOST}:${NEO4J_PORT}" \
  -u "${NEO4J_USER}" \
  -p "${NEO4J_PASSWORD}" \
  "RETURN 1;" > /dev/null 2>&1; do
  retries=$((retries - 1))
  if [ "$retries" -le 0 ]; then
    echo "ERROR: Neo4j did not become available in time." >&2
    exit 1
  fi
  sleep 2
done

echo "Neo4j is available. Applying constraints..."

cypher-shell \
  -a "bolt://${NEO4J_HOST}:${NEO4J_PORT}" \
  -u "${NEO4J_USER}" \
  -p "${NEO4J_PASSWORD}" \
  "CREATE CONSTRAINT entity_uuid_unique IF NOT EXISTS FOR (e:Entity) REQUIRE e.uuid IS UNIQUE;"

echo "Constraint applied successfully."
