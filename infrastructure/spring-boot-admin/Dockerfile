# Stage 1: Build — compile and produce the fat JAR
FROM gradle:8-jdk21-alpine AS builder
WORKDIR /workspace
COPY gradle/ gradle/
COPY build.gradle.kts settings.gradle.kts ./
COPY infrastructure/spring-boot-admin/build.gradle.kts infrastructure/spring-boot-admin/build.gradle.kts
COPY infrastructure/spring-boot-admin/src infrastructure/spring-boot-admin/src
RUN gradle :infrastructure:spring-boot-admin:bootJar --no-daemon --parallel

# Stage 2: Test — run the full test suite (CI gate)
# docker build --target test -f infrastructure/spring-boot-admin/Dockerfile .
FROM builder AS test
ENV SKIP_DOCKER_TESTS=true
RUN gradle :infrastructure:spring-boot-admin:test --no-daemon --parallel

# Stage 3: Runtime — minimal JRE image, non-root user
FROM eclipse-temurin:21-jre-alpine AS runtime
RUN addgroup -S appgroup && adduser -S appuser -G appgroup -u 1001
USER 1001
WORKDIR /app
COPY --from=builder /workspace/infrastructure/spring-boot-admin/build/libs/*.jar app.jar
EXPOSE 8090
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
  CMD wget -qO- http://localhost:8090/actuator/health || exit 1
ENTRYPOINT ["java", "-jar", "app.jar"]
