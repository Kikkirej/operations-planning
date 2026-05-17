#!/bin/sh
# setup.sh — Bootstrap local development environment for ops.local platform.
# Run once from the repo root or from deployment/compose/.
#
# Usage:
#   ./setup.sh                  # full setup (certs + .env + /etc/hosts + check)
#   ./setup.sh --check          # validate secrets and cert expiry only
#   ./setup.sh --renew          # force-regenerate server cert (keep CA)
#   ./setup.sh --renew-ca       # regenerate CA + server cert (warn: images must rebuild)
#   ./setup.sh --domain NAME    # override domain (default: ops.local)

set -e

# ---------------------------------------------------------------------------
# Resolve repo root (script may be invoked from any directory)
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# If invoked from repo root the script is at deployment/compose/setup.sh
# If invoked from deployment/compose/ the script is at ./setup.sh
# Either way, repo root is two levels up from deployment/compose/
case "$SCRIPT_DIR" in
  */deployment/compose) REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)" ;;
  *)                    REPO_ROOT="$(cd "$SCRIPT_DIR" && pwd)" ;;
esac

CERTS_DIR="$REPO_ROOT/infrastructure/certs"
TRUST_DIR="$CERTS_DIR/trust"
SERVER_DIR="$CERTS_DIR/server"
CA_KEY="$TRUST_DIR/local-ca.key"
CA_CERT="$TRUST_DIR/local-ca.crt"
SERVER_KEY="$SERVER_DIR/local.key"
SERVER_CERT="$SERVER_DIR/local.crt"
ENV_EXAMPLE="$REPO_ROOT/deployment/compose/.env.example"
ENV_FILE="$REPO_ROOT/deployment/compose/.env"

# ---------------------------------------------------------------------------
# Parse flags
# ---------------------------------------------------------------------------
DOMAIN="ops.local"
MODE="setup"    # setup | check | renew | renew-ca

while [ $# -gt 0 ]; do
  case "$1" in
    --check)    MODE="check" ;;
    --renew)    MODE="renew" ;;
    --renew-ca) MODE="renew-ca" ;;
    --domain)
      shift
      if [ -z "$1" ]; then
        echo "ERROR: --domain requires an argument" >&2; exit 1
      fi
      DOMAIN="$1"
      ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
  shift
done

WILDCARD_DOMAIN="*.${DOMAIN}"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
require_openssl() {
  if ! command -v openssl >/dev/null 2>&1; then
    echo "ERROR: openssl is not installed." >&2
    echo "  Ubuntu/Debian: sudo apt-get install openssl" >&2
    echo "  macOS:         brew install openssl" >&2
    exit 1
  fi
}

days_until_expiry() {
  cert="$1"
  expiry_str=$(openssl x509 -enddate -noout -in "$cert" 2>/dev/null | cut -d= -f2)
  if [ -z "$expiry_str" ]; then echo "-1"; return; fi
  # Convert to epoch seconds (portable: use openssl for date parsing)
  expiry_epoch=$(openssl x509 -enddate -noout -in "$cert" | cut -d= -f2 | \
    xargs -I{} date -d "{}" +%s 2>/dev/null || \
    openssl x509 -enddate -noout -in "$cert" | cut -d= -f2 | \
    xargs -I{} date -j -f "%b %e %T %Y %Z" "{}" +%s 2>/dev/null || \
    echo "0")
  now_epoch=$(date +%s)
  echo $(( (expiry_epoch - now_epoch) / 86400 ))
}

# ---------------------------------------------------------------------------
# Section: Certificate generation
# ---------------------------------------------------------------------------
generate_ca() {
  require_openssl
  echo "Generating platform CA for $DOMAIN..."
  mkdir -p "$TRUST_DIR"
  openssl genrsa -out "$CA_KEY" 4096 2>/dev/null
  openssl req -new -x509 -days 3650 \
    -key "$CA_KEY" \
    -out "$CA_CERT" \
    -subj "/CN=${DOMAIN} Dev CA/O=ops.local/C=DE" \
    2>/dev/null
  echo "  CA cert: $CA_CERT"
  echo "  CA key:  $CA_KEY (gitignored — stays local)"
}

generate_server_cert() {
  require_openssl
  echo "Generating server cert for *.${DOMAIN}..."
  mkdir -p "$SERVER_DIR"
  openssl genrsa -out "$SERVER_KEY" 2048 2>/dev/null

  SAN_EXT="subjectAltName=DNS:${DOMAIN},DNS:${WILDCARD_DOMAIN}"
  openssl req -new \
    -key "$SERVER_KEY" \
    -subj "/CN=${WILDCARD_DOMAIN}/O=ops.local/C=DE" \
    -addext "$SAN_EXT" \
    -out "$SERVER_DIR/local.csr" \
    2>/dev/null

  openssl x509 -req -days 730 \
    -in "$SERVER_DIR/local.csr" \
    -CA "$CA_CERT" \
    -CAkey "$CA_KEY" \
    -CAcreateserial \
    -copy_extensions copy \
    -out "$SERVER_CERT" \
    2>/dev/null

  rm -f "$SERVER_DIR/local.csr" "$TRUST_DIR/local-ca.srl"
  echo "  Server cert: $SERVER_CERT"
  echo "  Server key:  $SERVER_KEY (gitignored)"
}

run_cert_setup() {
  # CA: generate only if missing (or --renew-ca)
  if [ "$MODE" = "renew-ca" ] || [ ! -f "$CA_CERT" ]; then
    if [ "$MODE" = "renew-ca" ] && [ -f "$CA_CERT" ]; then
      echo "WARNING: Regenerating CA — all Docker images must be rebuilt and browser CA trust re-imported."
    fi
    generate_ca
  else
    echo "  CA cert already exists — skipping (use --renew-ca to regenerate)"
  fi

  # Server cert: generate if missing, or on --renew / --renew-ca
  if [ "$MODE" = "renew" ] || [ "$MODE" = "renew-ca" ] || [ ! -f "$SERVER_CERT" ]; then
    generate_server_cert
  else
    echo "  Server cert already exists — skipping (use --renew to regenerate)"
  fi
}

# ---------------------------------------------------------------------------
# Section: .env management
# ---------------------------------------------------------------------------
run_env_setup() {
  if [ ! -f "$ENV_FILE" ]; then
    cp "$ENV_EXAMPLE" "$ENV_FILE"
    echo "Created $ENV_FILE — fill in all CHANGE_ME_BEFORE_USE values before running docker compose up."
  else
    echo "  .env already exists — skipping copy"
  fi
}

# ---------------------------------------------------------------------------
# Section: Secret validation
# ---------------------------------------------------------------------------
run_secret_check() {
  echo ""
  echo "Checking secrets in .env..."

  if [ ! -f "$ENV_FILE" ]; then
    echo "  WARNING: $ENV_FILE does not exist. Run setup.sh first."
    return
  fi

  missing=0
  while IFS= read -r line; do
    # Skip blank lines and comments
    case "$line" in
      ''|\#*) continue ;;
    esac
    varname="${line%%=*}"
    varvalue="${line#*=}"
    if [ "$varvalue" = "CHANGE_ME_BEFORE_USE" ]; then
      # Find the comment line immediately above this variable in .env.example
      desc=$(grep -B1 "^${varname}=" "$ENV_EXAMPLE" 2>/dev/null | grep '^#' | sed 's/^# *//' | head -1)
      if [ -n "$desc" ]; then
        printf '  MISSING: %-40s # %s\n' "$varname" "$desc"
      else
        printf '  MISSING: %s\n' "$varname"
      fi
      missing=$((missing + 1))
    fi
  done < "$ENV_FILE"

  if [ "$missing" -eq 0 ]; then
    echo "  All secrets are set."
  else
    echo ""
    echo "  $missing secret(s) need to be set."
    echo "  Edit $ENV_FILE and replace CHANGE_ME_BEFORE_USE values."
  fi
}

# ---------------------------------------------------------------------------
# Section: Certificate expiry check
# ---------------------------------------------------------------------------
WARN_DAYS=30

check_cert_expiry() {
  cert="$1"
  label="$2"

  if [ ! -f "$cert" ]; then
    return
  fi

  expiry=$(openssl x509 -enddate -noout -in "$cert" 2>/dev/null | cut -d= -f2)
  days=$(days_until_expiry "$cert")

  if [ "$days" -lt 0 ]; then
    echo "  WARNING: Could not read expiry for $label"
    return
  fi

  if [ "$days" -le "$WARN_DAYS" ]; then
    echo "  WARNING: $label expires in $days day(s) (on $expiry)"
    if [ "$label" = "CA cert" ]; then
      echo "           Renew: ./setup.sh --renew-ca  (then rebuild all images)"
    else
      echo "           Renew: ./setup.sh --renew  (then: docker compose kill -s SIGHUP traefik)"
    fi
  else
    echo "  OK: $label valid for $days more day(s) (expires $expiry)"
  fi
}

run_expiry_check() {
  echo ""
  echo "Checking certificate expiry..."
  check_cert_expiry "$CA_CERT"     "CA cert"
  check_cert_expiry "$SERVER_CERT" "server cert"
}

# ---------------------------------------------------------------------------
# Section: /etc/hosts
# ---------------------------------------------------------------------------
HOSTS_FILE="/etc/hosts"
HOSTS_TARGET_IP="127.0.0.1"

HOSTS_ENTRIES="
auth.${DOMAIN}
admin.${DOMAIN}
config.${DOMAIN}
"

run_hosts_setup() {
  echo ""
  echo "Updating /etc/hosts (requires sudo)..."
  added=0
  for host in $HOSTS_ENTRIES; do
    if grep -qE "^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+[[:space:]]+.*\b${host}\b" "$HOSTS_FILE" 2>/dev/null; then
      echo "  already present: $host"
    else
      printf '%s\t%s\n' "$HOSTS_TARGET_IP" "$host" | sudo tee -a "$HOSTS_FILE" >/dev/null
      echo "  added:           $host"
      added=$((added + 1))
    fi
  done

  if [ "$added" -gt 0 ]; then
    echo "  $added entry/entries added to $HOSTS_FILE."
  else
    echo "  Nothing to add — all hosts already present."
  fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
echo "=== ops.local Platform Setup ==="
echo ""

case "$MODE" in
  check)
    run_secret_check
    run_expiry_check
    ;;
  renew|renew-ca)
    run_cert_setup
    run_secret_check
    run_expiry_check
    ;;
  setup)
    run_cert_setup
    echo ""
    run_env_setup
    run_hosts_setup
    run_secret_check
    run_expiry_check
    echo ""
    echo "=== Setup complete ==="
    echo "Next: fill in .env secrets, then run: docker compose up --build"
    ;;
esac
