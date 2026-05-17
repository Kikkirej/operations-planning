# Stage 1: Build — compile and produce the fat JAR
FROM gradle:8-jdk21-alpine AS builder
WORKDIR /workspace
COPY gradle/ gradle/
COPY build.gradle.kts settings.gradle.kts ./
COPY infrastructure/config-server/build.gradle.kts infrastructure/config-server/build.gradle.kts
# Resolve and cache all dependencies before copying source — keeps this layer cached when only src changes
RUN gradle :infrastructure:config-server:dependencies --no-daemon
COPY infrastructure/config-server/src infrastructure/config-server/src
RUN gradle :infrastructure:config-server:bootJar --no-daemon --parallel

# Stage 2: Test — run the full test suite (CI gate)
# docker build --target test -f infrastructure/config-server/Dockerfile .
FROM builder AS test
ENV SKIP_DOCKER_TESTS=true
RUN gradle :infrastructure:config-server:test --no-daemon --parallel

# Stage 3: Runtime — minimal JRE image, non-root user
FROM eclipse-temurin:21-jre-alpine AS runtime
COPY infrastructure/certs/trust/local-ca.crt /tmp/platform-ca.crt
RUN keytool -importcert -noprompt -alias platform-ca \
    -file /tmp/platform-ca.crt \
    -keystore "$JAVA_HOME/lib/security/cacerts" \
    -storepass changeit && \
    rm /tmp/platform-ca.crt
RUN addgroup -S appgroup && adduser -S appuser -G appgroup -u 1001
USER 1001
WORKDIR /app
COPY --from=builder /workspace/infrastructure/config-server/build/libs/*.jar app.jar
EXPOSE 8888
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
  CMD wget -qO- http://localhost:8888/actuator/health || exit 1
ENTRYPOINT ["java", "-jar", "app.jar"]
