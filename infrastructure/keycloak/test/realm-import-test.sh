#!/bin/sh
# Integration test: verify Keycloak starts with operations realm auto-imported.
# Starts a temporary Keycloak container with realm-export.json mounted, then
# uses the admin REST API to assert realm, clients, and user configuration.
# Exits 0 on success, 1 on any assertion failure.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REALM_EXPORT="$SCRIPT_DIR/../realm-export.json"
KC_IMAGE="quay.io/keycloak/keycloak:26.0"
CONTAINER_NAME="kc-realm-import-test-$$"
KC_PORT=18080
KC_ADMIN="admin"
KC_ADMIN_PASS="admin"
BASE_URL="http://localhost:$KC_PORT"
REALM="operations"
MAX_WAIT=120
RETRY_INTERVAL=5

log() { printf '[realm-import-test] %s\n' "$1"; }
fail() { log "FAIL: $1"; docker rm -f "$CONTAINER_NAME" 2>/dev/null || true; exit 1; }

# Start Keycloak with realm import
log "Starting Keycloak $KC_IMAGE on port $KC_PORT ..."
docker run -d --name "$CONTAINER_NAME" \
  -p "$KC_PORT:8080" \
  -e KEYCLOAK_ADMIN="$KC_ADMIN" \
  -e KEYCLOAK_ADMIN_PASSWORD="$KC_ADMIN_PASS" \
  -v "$REALM_EXPORT:/opt/keycloak/data/import/realm-export.json:ro" \
  "$KC_IMAGE" start-dev --import-realm

# Wait for Keycloak to be ready
log "Waiting for Keycloak to be ready (max ${MAX_WAIT}s) ..."
elapsed=0
until curl -sf "$BASE_URL/realms/master" > /dev/null 2>&1; do
  if [ "$elapsed" -ge "$MAX_WAIT" ]; then
    fail "Keycloak did not become ready within ${MAX_WAIT}s"
  fi
  sleep "$RETRY_INTERVAL"
  elapsed=$((elapsed + RETRY_INTERVAL))
done
log "Keycloak is ready."

# Obtain admin token
log "Obtaining admin token ..."
TOKEN=$(curl -sf -X POST "$BASE_URL/realms/master/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "client_id=admin-cli&grant_type=password&username=$KC_ADMIN&password=$KC_ADMIN_PASS" \
  | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4)
if [ -z "$TOKEN" ]; then
  fail "Could not obtain admin token"
fi

# Assert 'operations' realm exists
log "Asserting '$REALM' realm exists ..."
HTTP_STATUS=$(curl -sf -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer $TOKEN" \
  "$BASE_URL/admin/realms/$REALM")
if [ "$HTTP_STATUS" != "200" ]; then
  fail "'$REALM' realm not found (HTTP $HTTP_STATUS)"
fi
log "  ✓ Realm '$REALM' exists"

# Assert required clients exist
for CLIENT_ID in eureka-server config-server spring-boot-admin; do
  log "Asserting client '$CLIENT_ID' exists ..."
  CLIENTS=$(curl -sf \
    -H "Authorization: Bearer $TOKEN" \
    "$BASE_URL/admin/realms/$REALM/clients?clientId=$CLIENT_ID")
  if ! echo "$CLIENTS" | grep -q "\"clientId\":\"$CLIENT_ID\""; then
    fail "Client '$CLIENT_ID' not found in realm '$REALM'"
  fi
  log "  ✓ Client '$CLIENT_ID' present"
done

# Assert sba-admin role exists
log "Asserting role 'sba-admin' exists ..."
ROLES=$(curl -sf \
  -H "Authorization: Bearer $TOKEN" \
  "$BASE_URL/admin/realms/$REALM/roles")
if ! echo "$ROLES" | grep -q '"sba-admin"'; then
  fail "Role 'sba-admin' not found in realm '$REALM'"
fi
log "  ✓ Role 'sba-admin' present"

# Assert default admin user has UPDATE_PASSWORD required action
log "Asserting default user has UPDATE_PASSWORD required action ..."
USERS=$(curl -sf \
  -H "Authorization: Bearer $TOKEN" \
  "$BASE_URL/admin/realms/$REALM/users?first=0&max=100")
if ! echo "$USERS" | grep -q '"UPDATE_PASSWORD"'; then
  fail "No user with UPDATE_PASSWORD required action found in realm '$REALM'"
fi
log "  ✓ UPDATE_PASSWORD required action present on default user"

# Cleanup
log "Stopping Keycloak container ..."
docker rm -f "$CONTAINER_NAME" > /dev/null

log "All assertions passed."
exit 0
