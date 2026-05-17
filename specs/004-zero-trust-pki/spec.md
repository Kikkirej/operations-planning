# Feature Specification: Zero Trust PKI & Secrets Management

**Feature Branch**: `004-zero-trust-pki`

**Created**: 2026-05-16

**Status**: Draft

## Clarifications

### Session 2026-05-16

- Q: Should missing secrets block `docker compose up` or is reporting via `setup.sh --check` sufficient? → A: Shell-only reporting — `setup.sh --check` lists missing secrets; `docker compose up` does not block (Option B).
- Q: Should `ops.local` be hardcoded or configurable in the setup script? → A: Configurable via `--domain` flag, defaulting to `ops.local` as the platform standard.
- Q: How should the platform respond when a certificate is nearing expiry? → A: `setup.sh --check` reports cert expiry date and warns if within 30 days; the CI/CD pipeline also runs this check and fails the build if any cert expires within 30 days.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Developer First-Time Setup (Priority: P1)

A developer clones the repository and runs a single setup command. The command generates or installs all required certificates and validates that all required secrets are set before any service starts. Missing secrets surface clearly, with instructions for each — no service starts in a broken state.

**Why this priority**: Onboarding friction is the #1 blocker for a productive local dev environment. A smooth first-run experience is prerequisite to everything else.

**Independent Test**: Clone a clean copy of the repo, run the setup script, verify all services start healthy with no manual certificate or secret configuration beyond what the script guides the user through.

**Acceptance Scenarios**:

1. **Given** a fresh clone with no `.env`, **When** the developer runs the setup script, **Then** the script generates a local CA and self-signed certificates, copies `.env.example` to `.env`, and lists every secret that still requires a real value.
2. **Given** a `.env` with a missing required secret, **When** the developer runs `setup.sh --check`, **Then** the script reports each missing variable by name with a one-line description; `docker compose up` itself does not enforce this check.
3. **Given** all secrets are set and certificates are in place, **When** the developer runs `docker compose up`, **Then** all services start healthy without manual browser certificate imports.

---

### User Story 2 — Operator Deploys to Production (AKS) (Priority: P2)

An operator deploying to AKS provides a real CA-signed certificate and real secrets (via Kubernetes Secrets or a secrets manager). The infrastructure consumes them through a consistent, documented interface — no special-casing between dev and prod.

**Why this priority**: The same certificate and secrets interface must work for both local Docker and AKS without changing application code or Dockerfiles.

**Independent Test**: Deploy to AKS with a real certificate and externally managed secrets. All services start and inter-service HTTPS connections succeed without any self-signed certificates present.

**Acceptance Scenarios**:

1. **Given** a real CA-signed certificate placed in the designated certificates directory, **When** services start in AKS, **Then** all HTTPS connections between services succeed and no self-signed CA import is required.
2. **Given** secrets are supplied via Kubernetes Secrets, **When** services start, **Then** they consume the same environment variable names as the local Docker setup.

---

### User Story 3 — Platform Engineer Adds a New Service (Priority: P3)

A platform engineer adds a new microservice to the platform. The new service automatically trusts the platform CA (via the image build) and has access to the current certificates without any per-service certificate configuration.

**Why this priority**: The zero-trust model must be self-maintaining as the platform grows.

**Independent Test**: Add a new service whose Dockerfile inherits from the base image pattern. Verify the service can make HTTPS calls to existing platform services without additional CA configuration.

**Acceptance Scenarios**:

1. **Given** a new service Dockerfile that follows the platform build pattern, **When** the image is built, **Then** the platform CA is automatically included in the JVM truststore.
2. **Given** the central certificates directory is updated with a new certificate, **When** Traefik is reloaded, **Then** the new certificate is served without restarting any other service.

---

### Edge Cases

- When a certificate expires or is within 30 days of expiry: `setup.sh --check` warns with the exact expiry date and renewal command; CI/CD fails the build with the same warning so expiry is caught before it reaches production.
- How does the system behave when a required secret exists but contains a placeholder value (`CHANGE_ME_BEFORE_USE`)?
- What happens if the certificates directory contains multiple certificates with overlapping SANs?
- How does certificate rotation work without downtime?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The platform MUST provide a central directory for CA certificates and TLS certificates, used by both Traefik and application image builds.
- **FR-002**: All application Docker images MUST include the platform CA in their trust store at build time.
- **FR-003**: The setup process MUST generate a local self-signed CA and wildcard certificate automatically on first run. The domain defaults to `ops.local` (producing `*.ops.local` SANs) and MUST be overridable via a `--domain` flag (e.g., `./setup.sh --domain myteam.local`).
- **FR-004**: The setup script MUST validate all required secrets and report any that are missing or set to a placeholder value, with a clear per-variable message. Secret validation is a shell-level pre-flight check (`setup.sh --check`) — it does not block `docker compose up` directly, keeping compose configuration simple.
- **FR-005**: The certificate and secrets interface MUST be identical for local Docker and AKS deployments, differing only in the source of values (local files vs. Kubernetes Secrets).
- **FR-006**: Traefik MUST load all certificates from a designated configuration directory, enabling certificate rotation without service restarts.
- **FR-007**: Documentation MUST cover: how to generate/replace certificates, how to set secrets for both local and AKS environments, and how to add a new service to the trust chain.
- **FR-008**: Placeholder secrets (`CHANGE_ME_BEFORE_USE`) in `.env` MUST be treated as missing for the purpose of startup validation.
- **FR-009**: The private key for any certificate MUST never be committed to the repository; the `.gitignore` rules MUST enforce this.
- **FR-010**: The setup experience MUST not require manual browser certificate imports for local development.
- **FR-011**: The setup script MUST check certificate expiry and warn if any certificate expires within 30 days, reporting the exact expiry date and the renewal command. The CI/CD pipeline MUST run this same check and fail the build if any certificate is within 30 days of expiry.

### Key Entities

- **Platform CA**: The root certificate authority for the local environment. Signs all other certificates. Only the public certificate is committed; the private key stays local.
- **TLS Certificate**: A wildcard certificate covering `*.ops.local` (or equivalent), signed by the Platform CA, served by Traefik.
- **Trust Store**: The JVM (or system) certificate store in each application image, pre-seeded with the Platform CA at build time.
- **Secrets**: Environment variables required for services to function. All required secrets are declared in `.env.example` with `CHANGE_ME_BEFORE_USE` placeholder values.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A developer with no prior knowledge of the platform can complete local setup in under 10 minutes by following the setup script and documentation.
- **SC-002**: Zero manual certificate configuration steps are required after running the setup script in a local Docker environment.
- **SC-003**: All services start healthy on first `docker compose up` after the setup script completes, with no certificate warnings in browser or service logs.
- **SC-004**: Running `setup.sh --check` detects and reports 100% of missing or placeholder secrets before any container is started, with each variable listed by name and a one-line description of its purpose.
- **SC-005**: Certificate rotation (replacing a certificate in the central directory) takes effect without restarting application containers — only a Traefik reload is needed.
- **SC-006**: A new service added following the documented pattern trusts the platform CA without any additional configuration steps.
- **SC-007**: Certificate expiry within 30 days is detected and reported by both `setup.sh --check` (local) and the CI/CD pipeline (automated), preventing silent expiry in any environment.

## Assumptions

- Local development uses Docker Compose; production deployment targets AKS (Azure Kubernetes Service).
- The default local domain is `ops.local`; the setup script accepts `--domain <name>` to override. All tooling (certs, `/etc/hosts`, documentation) uses `ops.local` as the standard platform default.
- Application services are JVM-based (Java/Kotlin); non-JVM services use the system certificate store.
- The platform CA and self-signed certificates are development-only artifacts; production uses a real CA (e.g., Let's Encrypt or an enterprise CA).
- Secrets management in AKS is out of scope for this feature beyond defining the environment variable interface (the operator chooses the secrets manager).
- The existing `infrastructure/traefik/certs/` directory becomes the central certificates directory.
- Complexity cap: if any part of the implementation requires more than one manual step beyond running the setup script, that part reverts to a simpler approach.
