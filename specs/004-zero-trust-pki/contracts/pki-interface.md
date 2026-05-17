# Contract: Platform PKI Interface

**Version**: 1.0.0 | **Feature**: 004-zero-trust-pki

## Overview

This contract defines the interface between the PKI infrastructure and all platform
consumers (Spring services, Traefik, Docker Compose, AKS). Any change to these paths,
variable names, or formats is a breaking change requiring a contract version bump.

## Certificate Interface

### CA Certificate

| Property | Value |
|----------|-------|
| Canonical path (repo) | `infrastructure/certs/trust/local-ca.crt` |
| Mount path (Traefik container) | `/etc/traefik/trust/local-ca.crt` |
| Import path (JVM images) | Imported into `$JAVA_HOME/lib/security/cacerts` at build time as alias `platform-ca` |
| Format | PEM-encoded X.509 |
| Rotation trigger | Manual: replace file + rebuild images |

### Server Certificate

| Property | Value |
|----------|-------|
| Canonical path (repo) | `infrastructure/certs/server/local.crt` |
| Mount path (Traefik container) | `/etc/traefik/server/local.crt` |
| Key path (Traefik container) | `/etc/traefik/server/local.key` |
| Format | PEM-encoded X.509 + RSA private key |
| Rotation trigger | Replace files + Traefik reload (no app restarts needed) |

## Secrets Interface

All secrets are consumed as environment variables. The canonical list of required
variables is maintained in `deployment/compose/.env.example`. A value of
`CHANGE_ME_BEFORE_USE` indicates an unset secret.

**Contract rule**: Any service that requires a secret MUST declare it in `.env.example`
with a `CHANGE_ME_BEFORE_USE` placeholder and a comment describing its purpose.

## Traefik Certificate Configuration

Traefik reads certificates via its file provider. The dynamic config at
`infrastructure/traefik/dynamic/tls.yml` MUST reference:

```yaml
tls:
  stores:
    default:
      defaultCertificate:
        certFile: /etc/traefik/server/local.crt
        keyFile: /etc/traefik/server/local.key
```

## Docker Compose Volume Mounts (Traefik)

```yaml
traefik:
  volumes:
    - ../../infrastructure/certs/server:/etc/traefik/server:ro
    - ../../infrastructure/certs/trust:/etc/traefik/trust:ro
```

## Dockerfile CA Import Pattern

All JVM service Dockerfiles MUST include this block in the `runtime` stage before
switching to the non-root user:

```dockerfile
COPY infrastructure/certs/trust/local-ca.crt /tmp/platform-ca.crt
RUN keytool -importcert -noprompt -alias platform-ca \
    -file /tmp/platform-ca.crt \
    -keystore "$JAVA_HOME/lib/security/cacerts" \
    -storepass changeit && \
    rm /tmp/platform-ca.crt
```

## AKS Mapping

| Docker Compose | AKS Equivalent |
|----------------|----------------|
| `infrastructure/certs/trust/local-ca.crt` in image build | Production CA cert in image build (same path) |
| `infrastructure/certs/server/` host directory | Kubernetes Secret mounted at equivalent container path |
| `.env` file | Kubernetes Secrets as environment variables (same variable names) |

## Compatibility Matrix

| Consumer | Uses CA cert | Uses server cert | Uses secrets |
|----------|-------------|------------------|--------------|
| Traefik | reference only | serves it | via .env |
| Eureka | truststore (image) | — | via .env |
| Config Server | truststore (image) | — | via .env |
| Spring Boot Admin | truststore (image) | — | via .env |
| AKS Traefik | same CA in image | from K8s Secret | from K8s Secrets |
