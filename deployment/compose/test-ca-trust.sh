#!/bin/sh
# test-ca-trust.sh — Verify platform CA is trusted in built Docker images.
# Builds the runtime stage of each JVM service and checks keytool for the alias.
# Run from repo root.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
case "$SCRIPT_DIR" in
  */deployment/compose) REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)" ;;
  *)                    REPO_ROOT="$(cd "$SCRIPT_DIR" && pwd)" ;;
esac

cd "$REPO_ROOT"

PASS=0
FAIL=0

ok() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

check_ca_trust() {
  service="$1"
  dockerfile="$2"
  echo ""
  echo "Building $service runtime image..."
  tag="test-ca-trust-${service}:$$"
  if docker build --target runtime -f "$dockerfile" -t "$tag" . >/dev/null 2>&1; then
    if docker run --rm "$tag" keytool -list -alias platform-ca \
        -keystore "$JAVA_HOME/lib/security/cacerts" \
        -storepass changeit >/dev/null 2>&1; then
      ok "$service: platform-ca alias found in truststore"
    else
      fail "$service: platform-ca alias NOT found in truststore"
    fi
    docker rmi "$tag" >/dev/null 2>&1 || true
  else
    fail "$service: docker build failed"
  fi
}

echo "=== test-ca-trust.sh ==="

check_ca_trust "eureka"           "infrastructure/eureka/Dockerfile"
check_ca_trust "config-server"    "infrastructure/config-server/Dockerfile"
check_ca_trust "spring-boot-admin" "infrastructure/spring-boot-admin/Dockerfile"
check_ca_trust "test-runner"      "infrastructure/test-runner/Dockerfile"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
