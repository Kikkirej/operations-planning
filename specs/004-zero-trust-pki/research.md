# Research: Zero Trust PKI & Secrets Management

## Certificate Generation

**Decision**: OpenSSL on the host machine (inside `setup.sh`) generates the CA and server cert.

**Rationale**: OpenSSL is universally available on Linux/macOS dev machines and in CI Docker images. Running it on the host for setup (a one-time operation) avoids a `docker run` step that would slow first-run UX. The output (CA cert + server cert + keys) is placed in `infrastructure/certs/` according to the gitignore rules.

**Alternative rejected**: Generate inside a Docker container — adds `docker run` overhead and requires volume mounts, increasing setup complexity.

**OpenSSL commands** (verified against OpenSSL 3.0):

```sh
# 1. Generate CA key and self-signed CA cert (10-year validity, dev only)
openssl genrsa -out infrastructure/certs/trust/local-ca.key 4096
openssl req -x509 -new -nodes \
  -key infrastructure/certs/trust/local-ca.key \
  -sha256 -days 3650 \
  -subj "/CN=ops.local Dev CA/O=ops.local" \
  -out infrastructure/certs/trust/local-ca.crt

# 2. Generate server key
openssl genrsa -out infrastructure/certs/server/local.key 2048

# 3. Generate CSR + SAN ext file
cat > /tmp/ops-local-san.cnf <<EOF
[req]
req_extensions = v3_req
distinguished_name = req_distinguished_name
[req_distinguished_name]
[v3_req]
subjectAltName = DNS:ops.local,DNS:*.ops.local
EOF

openssl req -new \
  -key infrastructure/certs/server/local.key \
  -subj "/CN=*.ops.local" \
  -config /tmp/ops-local-san.cnf \
  -out /tmp/ops-local.csr

# 4. Sign server cert with CA (2-year validity)
openssl x509 -req \
  -in /tmp/ops-local.csr \
  -CA infrastructure/certs/trust/local-ca.crt \
  -CAkey infrastructure/certs/trust/local-ca.key \
  -CAcreateserial \
  -days 730 -sha256 \
  -extfile /tmp/ops-local-san.cnf \
  -extensions v3_req \
  -out infrastructure/certs/server/local.crt
```

---

## JVM Trust Store Update

**Decision**: `keytool -importcert` inside the Dockerfile `runtime` stage, executed as root before switching to the non-root user.

**Rationale**: `eclipse-temurin:21-jre-alpine` includes `keytool`. A single `COPY` + `RUN keytool` block adds the CA at build time. The resulting image needs no runtime CA volume mount and works identically in Docker Compose and AKS (as a Kubernetes Pod).

**Alternative rejected**: Mount CA cert as a Docker volume and import at container startup — requires an entrypoint script, adds startup time, and doesn't work in AKS without a ConfigMap or InitContainer.

**Dockerfile pattern** (same for all JVM services):

```dockerfile
# In runtime stage, before switching to non-root user:
COPY infrastructure/certs/trust/local-ca.crt /tmp/platform-ca.crt
RUN keytool -importcert -noprompt -alias platform-ca \
    -file /tmp/platform-ca.crt \
    -keystore "$JAVA_HOME/lib/security/cacerts" \
    -storepass changeit && \
    rm /tmp/platform-ca.crt
```

**Layer caching**: The `COPY infrastructure/certs/trust/local-ca.crt` layer only invalidates when the CA cert changes (rare — expected once per environment setup). All subsequent layers (JAR copy, user creation) are unaffected.

---

## Traefik Certificate Loading

**Decision**: Traefik dynamic file provider + single `tls.yml` pointing to `infrastructure/certs/server/` files. Traefik watches the directory; updating the files and sending `SIGHUP` (or using Traefik's file watcher) applies new certs without restart.

**Current state**: `infrastructure/traefik/dynamic/tls.yml` already exists and references `/etc/traefik/certs/cert.pem`. Update to reference new paths: `/etc/traefik/server/local.crt` and `/etc/traefik/server/local.key`.

**Docker Compose volume mount update**:

```yaml
traefik:
  volumes:
    - ../../infrastructure/certs/server:/etc/traefik/server:ro   # server certs
    - ../../infrastructure/certs/trust:/etc/traefik/trust:ro     # CA (for reference)
    # Remove: ../../infrastructure/traefik/certs:/etc/traefik/certs:ro
```

**Traefik tls.yml update**:

```yaml
tls:
  stores:
    default:
      defaultCertificate:
        certFile: /etc/traefik/server/local.crt
        keyFile: /etc/traefik/server/local.key
```

---

## Secret Validation

**Decision**: A plain shell function in `setup.sh` that reads `.env` and flags any line where the value is `CHANGE_ME_BEFORE_USE`. Output is human-readable: lists each missing variable name and a one-line description. Does NOT block `docker compose up` (too complex, causes startup dependency ordering issues).

**Rationale**: Docker Compose `healthcheck` or `depends_on` cannot read `.env` content at the Docker Compose level. A separate `depends_on` "validator" service adds a container and a profile — that's the complexity line. A pre-flight shell function run by `setup.sh` achieves the same result with zero overhead.

**Alternative rejected**: Docker Compose `validator` service with `profiles: [validate]` — adds a container definition, a profile, and requires the user to remember to pass `--profile validate`. Fails the complexity cap.

**Implementation**:

```sh
check_secrets() {
  missing=0
  while IFS='=' read -r key value; do
    [ -z "$key" ] || [ "${key#\#}" != "$key" ] && continue
    if [ "$value" = "CHANGE_ME_BEFORE_USE" ]; then
      echo "  MISSING: $key"
      missing=$((missing + 1))
    fi
  done < .env
  return $missing
}
```

---

## Browser CA Trust (Optional — Not in main setup script)

**Decision**: Document the `certutil` import in `docs/infrastructure/pki/README.md` as an optional step. The primary setup script does NOT attempt to auto-import into Firefox/Chrome (too OS-dependent).

**Rationale**: Auto-importing browser certs requires sudo, varies by OS and browser, and fails silently in CI. The user already has a working `certutil` import documented from the previous session. Document it clearly; don't automate it.

---

## AKS Compatibility

**Decision**: In AKS, the `infrastructure/certs/trust/local-ca.crt` file in the repo is replaced with the production CA cert (or an empty placeholder) during CI image builds. The environment variable interface is identical — services don't know or care whether they're using a dev CA or a production CA.

**For server certs in AKS**: cert-manager (or Azure Key Vault + CSI driver) provides the cert to Traefik via a Kubernetes Secret mounted at the same path. This is out of scope for this feature — only the interface is defined.

---

## Existing cert.pem Migration

**Current**: `infrastructure/traefik/certs/cert.pem` — self-signed wildcard, CN=ops.local, CA:TRUE (acts as its own CA), valid 10 years.

**Migration**: This cert is retired. The new `local-ca.crt` (generated by `setup.sh`) replaces it. The old `infrastructure/traefik/certs/` directory is removed and replaced by `infrastructure/certs/`.

**Transition**: During implementation, the old `traefik/certs/.gitignore` and `cert.pem` are deleted. The `traefik/dynamic/tls.yml` is updated to the new path. Firefox's `certutil` import documentation is updated in the PKI README.

---

## CI Certificate Expiry Check (T019 — US2 TDD)

**Test scenario**: A cert with 1-day validity triggers the CI expiry check failure.

**Generating a short-lived test cert** (for manual verification):
```sh
openssl req -new -x509 -days 1 -nodes \
  -newkey rsa:2048 \
  -keyout /tmp/test-expiring.key \
  -out /tmp/test-expiring.crt \
  -subj "/CN=test-expiring-ca/O=test"
```

**Expected CI step output** when `local-ca.crt` has 1 day remaining:
```
FAIL: platform CA expires in 1 day(s) (on May 18 11:09:39 2026 GMT)
      Renew locally with ./setup.sh --renew (or --renew-ca for CA) and commit local-ca.crt
Error: Process completed with exit code 1.
```

**Expected CI step output** when certs are valid (e.g., 3650 days remaining):
```
OK:   platform CA valid for 3650 more day(s) (expires May 13 22:05:30 2036 GMT)
SKIP: server cert not found (gitignored or not yet generated)
```

**How to test the CI gate locally**:
```sh
# Temporarily replace CA cert with 1-day cert and run the CI check script inline
openssl req -new -x509 -days 1 -nodes -newkey rsa:2048 \
  -keyout /tmp/exp.key -out /tmp/exp.crt -subj "/CN=exp/O=test" 2>/dev/null
cp infrastructure/certs/trust/local-ca.crt infrastructure/certs/trust/local-ca.crt.bak
cp /tmp/exp.crt infrastructure/certs/trust/local-ca.crt
# Run the check inline (mirrors CI step logic)
expiry=$(openssl x509 -enddate -noout -in infrastructure/certs/trust/local-ca.crt | cut -d= -f2)
expiry_epoch=$(date -d "$expiry" +%s)
days=$(( (expiry_epoch - $(date +%s)) / 86400 ))
echo "Days: $days"  # expect: 1 → would trigger exit 1 in CI
# Restore
cp infrastructure/certs/trust/local-ca.crt.bak infrastructure/certs/trust/local-ca.crt
rm /tmp/exp.key /tmp/exp.crt infrastructure/certs/trust/local-ca.crt.bak
```
