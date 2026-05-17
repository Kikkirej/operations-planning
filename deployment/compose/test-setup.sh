#!/bin/sh
# test-setup.sh — Integration test for setup.sh
# Verifies cert generation, .env creation, and --check output.
# Run from repo root or deployment/compose/.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
case "$SCRIPT_DIR" in
  */deployment/compose) REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)" ;;
  *)                    REPO_ROOT="$(cd "$SCRIPT_DIR" && pwd)" ;;
esac

SETUP="$REPO_ROOT/deployment/compose/setup.sh"
TRUST_DIR="$REPO_ROOT/infrastructure/certs/trust"
SERVER_DIR="$REPO_ROOT/infrastructure/certs/server"
ENV_FILE="$REPO_ROOT/deployment/compose/.env"
ENV_EXAMPLE="$REPO_ROOT/deployment/compose/.env.example"

PASS=0
FAIL=0

ok() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

echo "=== test-setup.sh ==="
echo ""

# ---------------------------------------------------------------------------
# Fixture: remove generated certs and .env to simulate clean state
# ---------------------------------------------------------------------------
echo "Preparing clean state..."
rm -f "$TRUST_DIR/local-ca.crt" "$TRUST_DIR/local-ca.key"
rm -f "$SERVER_DIR/local.crt" "$SERVER_DIR/local.key"

BACKUP_ENV=""
if [ -f "$ENV_FILE" ]; then
  BACKUP_ENV="$ENV_FILE.bak.$$"
  cp "$ENV_FILE" "$BACKUP_ENV"
  rm "$ENV_FILE"
fi

# ---------------------------------------------------------------------------
# Run setup.sh — /etc/hosts entries are already present so no sudo is needed
# ---------------------------------------------------------------------------
echo "Running setup.sh..."
sh "$SETUP" >/dev/null 2>&1
SETUP_EXIT=$?
if [ "$SETUP_EXIT" -ne 0 ]; then
  echo "  WARNING: setup.sh exited with code $SETUP_EXIT (may be sudo prompt for /etc/hosts)"
fi

# ---------------------------------------------------------------------------
# Assertions
# ---------------------------------------------------------------------------
echo ""
echo "Assertions:"

if [ -f "$TRUST_DIR/local-ca.crt" ]; then ok "CA cert exists"; else fail "CA cert missing"; fi
if [ -f "$TRUST_DIR/local-ca.key" ]; then ok "CA key present (gitignored)"; else fail "CA key missing"; fi
if [ -f "$SERVER_DIR/local.crt" ]; then ok "server cert exists"; else fail "server cert missing"; fi
if [ -f "$SERVER_DIR/local.key" ]; then ok "server key exists"; else fail "server key missing"; fi
if [ -f "$ENV_FILE" ]; then ok ".env was created"; else fail ".env was NOT created"; fi

if [ -f "$ENV_FILE" ]; then
  if grep -q "CHANGE_ME_BEFORE_USE" "$ENV_FILE"; then
    ok ".env contains CHANGE_ME_BEFORE_USE placeholders"
  else
    fail ".env has no CHANGE_ME_BEFORE_USE placeholders (expected from fresh copy)"
  fi
fi

CHECK_OUTPUT=$(sh "$SETUP" --check 2>/dev/null)

if echo "$CHECK_OUTPUT" | grep -q "MISSING:"; then
  ok "--check reports missing secrets"
else
  fail "--check did not report missing secrets"
fi

if echo "$CHECK_OUTPUT" | grep -q "OK: CA cert"; then
  ok "--check reports CA cert expiry status"
else
  fail "--check did not report CA cert expiry"
fi

# ---------------------------------------------------------------------------
# Restore .env
# ---------------------------------------------------------------------------
if [ -n "$BACKUP_ENV" ]; then
  cp "$BACKUP_ENV" "$ENV_FILE"
  rm "$BACKUP_ENV"
fi

# ---------------------------------------------------------------------------
# Result
# ---------------------------------------------------------------------------
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
