# Stage 1: Build — compile and produce the fat JAR
FROM gradle:8-jdk21-alpine AS builder
WORKDIR /workspace
COPY gradle/ gradle/
COPY build.gradle.kts settings.gradle.kts ./
COPY infrastructure/eureka/build.gradle.kts infrastructure/eureka/build.gradle.kts
# Resolve and cache all dependencies before copying source — keeps this layer cached when only src changes
RUN gradle :infrastructure:eureka:dependencies --no-daemon
COPY infrastructure/eureka/src infrastructure/eureka/src
RUN gradle :infrastructure:eureka:bootJar --no-daemon --parallel

# Stage 2: Test — run the full test suite (CI gate)
# docker build --target test -f infrastructure/eureka/Dockerfile .
FROM builder AS test
RUN gradle :infrastructure:eureka:test --no-daemon --parallel

# Stage 3: Runtime — minimal JRE image, non-root user
FROM eclipse-temurin:21-jre-alpine AS runtime
RUN addgroup -S appgroup && adduser -S appuser -G appgroup -u 1001
USER 1001
WORKDIR /app
COPY --from=builder /workspace/infrastructure/eureka/build/libs/*.jar app.jar
EXPOSE 8761
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
  CMD wget -qO- http://localhost:8761/actuator/health || exit 1
ENTRYPOINT ["java", "-jar", "app.jar"]
