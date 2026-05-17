# Tasks: Zero Trust PKI & Secrets Management

**Input**: Design documents from `specs/004-zero-trust-pki/`

**Branch**: `004-zero-trust-pki`

**User Stories**:
- **US1** (P1): Developer First-Time Setup — `setup.sh` + certs + Dockerfiles ← MVP
- **US2** (P2): Operator Deploys to Production (AKS) — CI/CD expiry check + AKS docs
- **US3** (P3): Platform Engineer Adds a New Service — pattern verification + new service support

---

## Phase 1: Setup (Repository Cleanup)

**Purpose**: Remove the old ad-hoc cert structure and create the canonical PKI directory layout. All other phases depend on this.

- [x] T001 Delete `infrastructure/traefik/certs/` directory and all contents (`cert.pem`, `key.pem`, `.gitignore`) — this directory is replaced by `infrastructure/certs/`
- [x] T002 Create `infrastructure/certs/trust/` and `infrastructure/certs/server/` directories with `.gitignore` files per `data-model.md` (root `.gitignore`: `*.key`, `server/`, `!trust/local-ca.crt`; `trust/.gitignore`: `*.key`; `server/.gitignore`: `*`)

**Checkpoint**: `infrastructure/certs/` structure in place; old `traefik/certs/` gone.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before any user story can be tested. Includes the setup script, generated CA cert, and updated Traefik config.

**⚠️ CRITICAL**: No user story work begins until this phase is complete.

- [x] T003 Write `deployment/compose/setup.sh` — cert generation section: create CA key + self-signed CA cert → `infrastructure/certs/trust/local-ca.{key,crt}`; create server key + CSR + CA-signed wildcard cert → `infrastructure/certs/server/local.{key,crt}`; skip if certs already exist; accept `--domain <name>` flag (default `ops.local`); accept `--renew` flag to force regeneration of server cert; accept `--renew-ca` flag to regenerate CA (warn that images must be rebuilt)
- [x] T004 Write `deployment/compose/setup.sh` — `.env` management section: copy `deployment/compose/.env.example` → `deployment/compose/.env` if `.env` does not exist; print "Created .env — fill in all CHANGE_ME_BEFORE_USE values" message
- [x] T005 Write `deployment/compose/setup.sh` — secret validation section (`--check` mode): read `.env`, flag every variable whose value is exactly `CHANGE_ME_BEFORE_USE`, print variable name with one-line description for each; print count summary; exit 0 even when secrets are missing (reporting only); run automatically at end of default invocation
- [x] T006 Write `deployment/compose/setup.sh` — cert expiry check section: use `openssl x509 -enddate -noout` to read expiry of `trust/local-ca.crt` and `server/local.crt`; warn if either expires within 30 days; print exact expiry date and renewal command; exit 0 (warning only in local mode); run as part of `--check`
- [x] T007 Write `deployment/compose/setup.sh` — `/etc/hosts` section: integrate logic from `deployment/compose/setup-hosts.sh` (add `auth.ops.local`, `admin.ops.local`, `config.ops.local` → `127.0.0.1` if not already present, require sudo); remove `deployment/compose/setup-hosts.sh` once logic is absorbed
- [x] T008 Run `deployment/compose/setup.sh` from repo root to bootstrap `infrastructure/certs/trust/local-ca.crt`; commit the generated `local-ca.crt` (public cert only — key is gitignored) so CI can COPY it during Docker builds
- [x] T009 Update `infrastructure/traefik/dynamic/tls.yml` — change `certFile` from `/etc/traefik/certs/cert.pem` to `/etc/traefik/server/local.crt` and `keyFile` from `/etc/traefik/certs/key.pem` to `/etc/traefik/server/local.key`
- [x] T010 Update `deployment/compose/docker-compose.yml` — Traefik `volumes`: replace `../../infrastructure/traefik/certs:/etc/traefik/certs:ro` with `../../infrastructure/certs/server:/etc/traefik/server:ro` and add `../../infrastructure/certs/trust:/etc/traefik/trust:ro`

**Checkpoint**: `setup.sh` functional, CA cert committed, Traefik config updated. Foundation ready.

---

## Phase 3: User Story 1 — Developer First-Time Setup (Priority: P1) 🎯 MVP

**Goal**: A developer runs `./setup.sh` once, fills in secrets, runs `docker compose up --build`, and all services start with HTTPS working and no cert errors.

**Independent Test**: On a clean environment (delete `.env`, delete `infrastructure/certs/server/`), run `./setup.sh`, fill secrets, run `docker compose up --build`, verify all services healthy and `https://admin.ops.local` loads without cert warnings.

### TDD: Tests First (write these before implementation — they MUST fail initially)

- [x] T011 [P] [US1] Write `deployment/compose/test-setup.sh` — integration test that invokes `setup.sh` with no prior state, verifies `infrastructure/certs/trust/local-ca.crt` and `infrastructure/certs/server/local.{crt,key}` exist, verifies `.env` was created, verifies `--check` output lists CHANGE_ME secrets
- [x] T012 [P] [US1] Write `deployment/compose/test-ca-trust.sh` — integration test that runs `docker build --target runtime -f infrastructure/<service>/Dockerfile .` for each JVM service and verifies `keytool -list -alias platform-ca` exits 0 inside the built image

### Implementation for User Story 1

- [x] T013 [P] [US1] Update `infrastructure/eureka/Dockerfile` — add CA import block in `runtime` stage before `adduser`: `COPY infrastructure/certs/trust/local-ca.crt /tmp/platform-ca.crt` then `RUN keytool -importcert -noprompt -alias platform-ca -file /tmp/platform-ca.crt -keystore "$JAVA_HOME/lib/security/cacerts" -storepass changeit && rm /tmp/platform-ca.crt`
- [x] T014 [P] [US1] Update `infrastructure/config-server/Dockerfile` — add same CA import block in `runtime` stage (identical pattern to T013)
- [x] T015 [P] [US1] Update `infrastructure/spring-boot-admin/Dockerfile` — add same CA import block in `runtime` stage (identical pattern to T013); remove any previous partial CA import attempt if present
- [x] T016 [US1] Run `docker compose up --build` with filled `.env`; verify all services reach healthy state; verify `https://admin.ops.local` loads without cert warnings after browser CA import step
- [x] T017 [US1] Delete `deployment/compose/setup-hosts.sh` (logic now in `setup.sh` T007)
- [x] T018 [US1] Update `deployment/compose/.env.example` — add a one-line comment above each variable explaining its purpose, so `setup.sh --check` output references are self-documenting

**Checkpoint**: US1 fully functional — developer setup works end-to-end in under 10 minutes.

---

## Phase 4: User Story 2 — Operator Deploys to Production (Priority: P2)

**Goal**: CI/CD fails the build if any certificate expires within 30 days; AKS deployment procedure is documented with a clear CA-swap process.

**Independent Test**: Edit `infrastructure/certs/trust/local-ca.crt` expiry to a near-future date (or mock via a short-lived test cert), push to CI, verify the build job fails with an expiry warning.

### TDD: Tests First

- [x] T019 [US2] Write a short-lived test cert (1-day validity) using `openssl`; add a test assertion to `.github/workflows/build-images.yml` dry-run that confirms the expiry-check step would fail for that cert — document expected output in `specs/004-zero-trust-pki/research.md`

### Implementation for User Story 2

- [x] T020 [US2] Add `Check certificate expiry` step to `.github/workflows/build-images.yml` — runs `openssl x509 -enddate -noout -in infrastructure/certs/trust/local-ca.crt` and `openssl x509 -enddate -noout -in infrastructure/certs/server/local.crt`; computes days remaining; fails (`exit 1`) if either cert expires within 30 days; step runs before any Docker build step
- [x] T021 [US2] Update `docs/infrastructure/pki/README.md` — verify Flow 6 (AKS deployment) accurately describes how to substitute the production CA cert at CI build time; add concrete example of overriding `local-ca.crt` via a CI secret

**Checkpoint**: CI blocks merges when certs are within 30 days of expiry; AKS procedure is documented.

---

## Phase 5: User Story 3 — Platform Engineer Adds a New Service (Priority: P3)

**Goal**: A new service Dockerfile following the documented pattern automatically trusts the platform CA with zero additional configuration.

**Independent Test**: Add the CA import block to `infrastructure/test-runner/Dockerfile`; run `docker build --target runtime -f infrastructure/test-runner/Dockerfile .`; verify `keytool -list -alias platform-ca` exits 0 inside the built image.

### TDD: Tests First

- [x] T022 [US3] Extend `deployment/compose/test-ca-trust.sh` (from T012) to also verify `infrastructure/test-runner/Dockerfile` runtime image trusts the platform CA

### Implementation for User Story 3

- [x] T023 [US3] Update `infrastructure/test-runner/Dockerfile` — add CA import block in `runtime` stage (same pattern as T013–T015); confirm the test stage also has access to the CA for any integration tests that make HTTPS calls
- [x] T024 [US3] Verify `docs/infrastructure/pki/README.md` Flow 5 (Adding a New Service) matches the exact Dockerfile lines added in T013–T015 and T023 — update if any discrepancy

**Checkpoint**: New service pattern verified; test-runner trusts platform CA.

---

## Phase 6: Polish & Cross-Cutting Concerns

- [x] T025 [P] Verify `README.md` Quick Start section accurately reflects the final `setup.sh` interface (flags, output, URLs) — update any discrepancies from implementation
- [x] T026 [P] Run `./setup.sh --check` on a fully configured environment and confirm output is "0 secrets missing" with no warnings
- [x] T027 [P] Run `docker compose up --build` and verify all 7 infrastructure services reach healthy state; record any timing issues in `docs/infrastructure/pki/README.md`
- [ ] T028 Commit `specs/004-zero-trust-pki/` artifacts and all implementation changes in a single PR; verify `docker build --target test` passes for eureka, config-server, and spring-boot-admin before raising PR

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: No dependencies — start immediately
- **Phase 2 (Foundational)**: Depends on Phase 1 completion — BLOCKS all user stories
- **Phase 3 (US1)**: Depends on Phase 2 — MVP, implement first
- **Phase 4 (US2)**: Depends on Phase 2; can start in parallel with Phase 3
- **Phase 5 (US3)**: Depends on Phase 3 (needs Dockerfile pattern established)
- **Phase 6 (Polish)**: Depends on Phases 3, 4, and 5

### Within Phase 2 (Sequential — order matters)

T003 → T004 → T005 → T006 → T007 (all setup.sh sections written sequentially)
T008 (run script, commit CA cert) → T009, T010 (can then run in parallel)

### Within Phase 3 (US1)

T011, T012 in parallel (write tests first — they MUST fail)
→ T013, T014, T015 in parallel (Dockerfile updates)
→ T016 (integration test — must run after T013–T015)
→ T017, T018 in parallel (cleanup and .env.example docs)

### Parallel Opportunities

- T003–T007: Write as one cohesive script (sequential sections)
- T009, T010: Parallel after T008
- T011, T012: Parallel (both test-writing tasks)
- T013, T014, T015: Parallel (different Dockerfiles, no conflicts)
- T017, T018: Parallel (different files)
- T025, T026, T027: Parallel (verification tasks)

---

## Parallel Example: Phase 3 (US1)

```bash
# Write tests in parallel (both will fail until Dockerfiles updated):
Task T011: "Write test-setup.sh — integration test for setup.sh"
Task T012: "Write test-ca-trust.sh — integration test for Dockerfile CA import"

# Update all three Dockerfiles in parallel (different files, no conflicts):
Task T013: "Update infrastructure/eureka/Dockerfile — CA import block"
Task T014: "Update infrastructure/config-server/Dockerfile — CA import block"
Task T015: "Update infrastructure/spring-boot-admin/Dockerfile — CA import block"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (cleanup)
2. Complete Phase 2: Foundational (setup.sh + CA cert + Traefik config)
3. Complete Phase 3: User Story 1 (Dockerfiles + end-to-end test)
4. **STOP and VALIDATE**: `docker compose up --build` works cleanly
5. Raise MVP PR if validated

### Incremental Delivery

1. Phase 1 + Phase 2 → foundation ready (CA committed, Traefik updated)
2. Phase 3 → US1 complete → developer onboarding works ← **release this**
3. Phase 4 → US2 complete → CI guards against cert expiry
4. Phase 5 → US3 complete → new service pattern verified
5. Phase 6 → polish, verify, merge

---

## Notes

- `[P]` tasks = different files, no dependencies between them — safe to run in parallel
- `[US1/2/3]` label maps each task to its user story for traceability
- **T008 is the bootstrap step**: running `setup.sh` and committing `local-ca.crt` unblocks all Dockerfile work
- Write tests (T011, T012) before touching Dockerfiles — Constitution II (TDD) requires tests to fail first
- `docker build --target test` must pass for all services before the PR can merge (Constitution IX)
- The complexity cap applies: if any task requires more than one manual command, simplify
