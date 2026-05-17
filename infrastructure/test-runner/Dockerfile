# Test runner for data layer integration tests.
# Bundles psql (PostgreSQL client) and cypher-shell (Neo4j client) so all
# integration test scripts can run inside Docker without bare-metal toolchain.
#
# Build targets:
#   builder  — installs tools on top of the Neo4j base (which ships cypher-shell)
#   test     — CI gate: docker build --target test . must succeed
#   runtime  — image used by docker compose run --rm test-runner
#
# This image is NOT pushed to the container registry.
# Usage: docker compose run --rm test-runner sh infrastructure/<service>/test/<script>.sh

FROM neo4j:5-community AS builder
USER root
RUN apt-get update \
    && apt-get install -y --no-install-recommends postgresql-client \
    && rm -rf /var/lib/apt/lists/*
USER neo4j

FROM builder AS test
# Smoke-test: both clients available
RUN cypher-shell --version && psql --version

FROM builder AS runtime
USER root
COPY infrastructure/certs/trust/local-ca.crt /usr/local/share/ca-certificates/platform-ca.crt
RUN update-ca-certificates
USER neo4j
WORKDIR /workspace
ENTRYPOINT ["sh"]
