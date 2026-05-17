# Implementation Plan: Zero Trust PKI & Secrets Management

**Branch**: `004-zero-trust-pki` | **Date**: 2026-05-16 | **Spec**: [spec.md](./spec.md)

## Summary

Establish a production-ready trust architecture for the platform: a central PKI directory,
automated CA injection into every Docker image at build time, a single `setup.sh` script
that generates local certs and validates secrets, and Traefik certificate directory loading.
Secrets validation blocks startup on placeholder values; certificate handling requires zero
manual browser steps. Complexity cap applies — if any step exceeds "one command", fall back
to simpler approach. Both local Docker and AKS use the same environment variable interface.

Full developer and operator flows are documented in `docs/infrastructure/pki/` and
the central `README.md` receives a revised Quick Start that covers the `setup.sh` step.

## Technical Context

**Language/Version**: Shell (POSIX sh) for setup scripts; Kotlin/JVM 21 for Spring services

**Primary Dependencies**: OpenSSL (cert generation), keytool (JVM cert import, included in eclipse-temurin JRE), Docker Compose, Traefik v3

**Storage**: Files — `infrastructure/certs/` central directory (CA cert committed; private keys and server certs git-ignored)

**Testing**: Integration tests via shell — verify cert presence, verify JVM trust, verify secret validation output

**Target Platform**: Local Docker Compose (dev), AKS (prod) — same image, different cert/secret source

**Project Type**: Infrastructure / DevOps tooling layer

**Performance Goals**: Setup script completes in under 60 seconds

**Constraints**: Zero bare-metal toolchain required beyond Docker Engine and Docker Compose; OpenSSL used only on host for cert generation (optional — install prompt if absent)

**Scale/Scope**: Applies to all ~5 custom Spring services + Traefik; no per-service special-casing

## Constitution Check

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Spec-First | ✅ PASS | spec.md written before planning |
| II. TDD | ✅ PASS | Shell integration tests verify cert trust and secret validation |
| III. Incremental | ✅ PASS | Stories are independently deliverable (certs → secrets validation → docs) |
| IV. Documentation as Code | ✅ PASS | `docs/infrastructure/pki/README.md` + `README.md` quickstart in same PR |
| V. Simplicity (YAGNI) | ✅ PASS | Complexity cap explicit: if any step exceeds one command, simplify |
| VI. Platform Infrastructure | ✅ PASS | Traefik cert loading is platform-level; no per-service deviation |
| VII. Technology Standards | ✅ PASS | Multi-stage Dockerfiles updated (builder → test → runtime) |
| VIII. Loose Coupling | N/A | No cross-service capability added; infrastructure only |
| IX. Docker-First | ✅ PASS | CA import happens inside Dockerfile; no local JDK/keytool needed |

## Project Structure

### Documentation (this feature)

```text
specs/004-zero-trust-pki/
├── plan.md              ← this file
├── research.md          ← Phase 0 output
├── data-model.md        ← Phase 1 output
├── quickstart.md        ← Phase 1 output (internal spec reference)
├── contracts/
│   └── pki-interface.md ← Phase 1 output
└── tasks.md             ← /speckit-tasks output (not created here)
```

### Source Code Changes

```text
infrastructure/
├── certs/                          ← NEW: central PKI directory
│   ├── .gitignore                  ← ignore *.key and server/
│   ├── trust/
│   │   ├── .gitignore              ← ignore *.key only
│   │   └── local-ca.crt            ← COMMITTED: Platform CA public cert
│   └── server/
│       └── .gitignore              ← ignore everything (generated locally)
├── traefik/
│   ├── certs/                      ← REMOVE: replaced by infrastructure/certs/
│   └── dynamic/
│       └── tls.yml                 ← UPDATE: paths → /etc/traefik/server/
├── eureka/Dockerfile               ← UPDATE: add CA import block
├── config-server/Dockerfile        ← UPDATE: add CA import block
└── spring-boot-admin/Dockerfile    ← UPDATE: add CA import block

deployment/
└── compose/
    ├── setup.sh                    ← REPLACE setup-hosts.sh: certs + .env + secrets check + /etc/hosts
    └── docker-compose.yml          ← UPDATE: Traefik volume mount to infrastructure/certs/

docs/
└── infrastructure/
    └── pki/
        └── README.md               ← NEW: full PKI & secrets documentation

README.md                           ← UPDATE: Quick Start — 4-step flow with setup.sh, secrets, browser trust, service URLs
docs/
└── infrastructure/
    └── pki/
        └── README.md               ← NEW: all 7 flows documented (setup, build, Traefik, secrets, new service, AKS, rotation)
```

## Complexity Tracking

No Constitution violations. Complexity cap applied as design constraint throughout.

| Decision | Why Chosen | Simpler Alternative Rejected Because |
|----------|------------|--------------------------------------|
| Separate `trust/` and `server/` subdirs | Clear split: committed vs. gitignored files | Flat dir — .gitignore complexity mixing committed and non-committed files |
| OpenSSL on host in setup.sh | One-time task; universally available | Generate inside Docker — adds `docker run` step, slower UX |
| keytool in Dockerfile at build time | Immutable image works in Docker and AKS identically | Mount CA at runtime — adds volume complexity, breaks AKS without ConfigMap |
| Plain shell secret check (no validator service) | Zero compose complexity; runs in < 1s | Docker Compose validator service — adds container, profile, startup ordering |
